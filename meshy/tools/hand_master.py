"""Make the master hand once from Meshy's sculpted hand: put it in the hand
frame (wrist at the origin, the hand's axis +z, the palm's normal +x, the
thumb +y: a right hand), one long, reduced; find its fingers (the four by
slicing across the fingers' length and following each across the slices,
the thumb as what stands out past the palm's edge) and lay three joints
along each; weight every vertex to the palm, the wrist or its finger's
joints. Writes meshy/assets/hand_master.blend (+ its texture) and
hand_master.json (the chains).

    blender -b --python-exit-code 1 -P meshy/tools/hand_master.py -- <meshy hand.glb> <out dir>
"""
import json
import math
import os
import sys

import bmesh
import bpy
import numpy
from mathutils import Matrix, Vector

SRC, OUT = [os.path.abspath(a) for a in sys.argv[sys.argv.index("--") + 1:][:2]]
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
obs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for o in obs:
    o.select_set(True)
bpy.context.view_layer.objects.active = obs[0]
if len(obs) > 1:
    bpy.ops.object.join()
hand = bpy.context.view_layer.objects.active
hand.parent = None
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
co = numpy.array([v.co[:] for v in hand.data.vertices])
mid = co.mean(axis=0)
U, S, Vt = numpy.linalg.svd(co - mid, full_matrices=False)
ax = [Vector(Vt[k]) for k in range(3)]
p0 = (co - mid) @ Vt[0]
lo_, hi_ = p0.min(), p0.max()
L = hi_ - lo_


def slab_gaps(sel):
    """How many pieces the vertices `sel` make across the width axis."""
    w = numpy.sort((co[sel] - mid) @ Vt[1])
    if len(w) < 10:
        return 1
    gaps = numpy.diff(w)
    return 1 + int((gaps > L * .02).sum())


top = p0 > hi_ - L * .2
bot = p0 < lo_ + L * .2
a = ax[0] if slab_gaps(top) >= slab_gaps(bot) else -ax[0]
p = (co - mid) @ numpy.array(a[:])
base_s = p.min()
# The wrist: the middle of the lowest slice.
wrist = Vector(co[p < base_s + L * .03].mean(axis=0))
# Across the hand: the thumb's side is where it stands out widest at a
# third to a half of the length.
w_ax = ax[1] - a * ax[1].dot(a)
w_ax.normalize()
band = (p > base_s + L * .2) & (p < base_s + L * .6)
knuck = (p > base_s + L * .6) & (p < base_s + L * .7)
wv = (co[band] - numpy.array(wrist[:])) @ numpy.array(w_ax[:])
wk = (co[knuck] - numpy.array(wrist[:])) @ numpy.array(w_ax[:])
# (How far past the palm's own edge each side stands out: the thumb.)
pos = wv.max() - numpy.percentile(wk, 98)
neg = -wv.min() + numpy.percentile(wk, 2)
t = w_ax if pos > neg else -w_ax
n = t.cross(a).normalized()  # a right hand: t = a x n
# The thumb sits on the palm's side of the hand: if its tip is on the other
# side, this is a left hand (or seen mirrored): mirror it into a right one.
side_t = (co - numpy.array(wrist[:])) @ numpy.array(t[:])
thumbish = (side_t > numpy.percentile(side_t, 97)) & band
if ((co[thumbish] - numpy.array(wrist[:])) @ numpy.array(n[:])).mean() < 0:
    n = -n
print("MASTER thumb side %.3f vs %.3f" % (pos, neg))
M = Matrix((n, t, a)).transposed()  # canonical -> world
R = M.inverted()
hand.data.transform(Matrix.Translation(-wrist))
hand.data.transform(R.to_4x4())
if R.determinant() < 0:
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.flip_normals()
    bpy.ops.object.mode_set(mode="OBJECT")
co = numpy.array([v.co[:] for v in hand.data.vertices])
length = co[:, 2].max()
hand.data.transform(Matrix.Diagonal((1 / length, 1 / length, 1 / length, 1)))
# Rebuilt clean: Meshy's surface (open seams, faces inside) remeshed into
# one closed skin, reduced to a game hand's budget, unwrapped, and Meshy's
# painted skin baked onto it.
hi = hand
hand = hi.copy()
hand.data = hi.data.copy()
bpy.context.scene.collection.objects.link(hand)
for m in list(hand.modifiers):
    hand.modifiers.remove(m)
rem = hand.modifiers.new("rem", "REMESH")
rem.mode = "VOXEL"
rem.voxel_size = .0075
bpy.ops.object.select_all(action="DESELECT")
hand.select_set(True)
bpy.context.view_layer.objects.active = hand
bpy.ops.object.modifier_apply(modifier="rem")
for poly in hand.data.polygons:
    poly.use_smooth = True
while hand.data.uv_layers:
    hand.data.uv_layers.remove(hand.data.uv_layers[0])
hand.data.uv_layers.new(name="handuv")
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=.004)
bpy.ops.uv.pack_islands(rotate=True, margin=.004)
bpy.ops.object.mode_set(mode="OBJECT")
img = bpy.data.images.new("hand_master", 512, 512, alpha=False)
hand.data.materials.clear()
mat = bpy.data.materials.new("hand_master")
mat.use_nodes = True
tn = mat.node_tree.nodes.new("ShaderNodeTexImage")
tn.image = img
mat.node_tree.nodes.active = tn
hand.data.materials.append(mat)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.samples = 4
bpy.ops.object.select_all(action="DESELECT")
hi.select_set(True)
hand.select_set(True)
bpy.context.view_layer.objects.active = hand
bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, use_selected_to_active=True,
                    cage_extrusion=.02, max_ray_distance=.05, margin=4, use_clear=True)
img.filepath_raw = os.path.join(OUT, "hand_master.png")
img.file_format = "PNG"
img.save()
img.filepath = os.path.join(OUT, "hand_master.png")
bsdf = mat.node_tree.nodes["Principled BSDF"]
mat.node_tree.links.new(tn.outputs[0], bsdf.inputs["Base Color"])
bpy.data.objects.remove(hi)
co = numpy.array([v.co[:] for v in hand.data.vertices])
z, y, x = co[:, 2], co[:, 1], co[:, 0]
print("MASTER %d triangles" % len(hand.data.polygons))

# The four fingers: slices across their length, pieces in each slice along
# y, followed from the top down.
tracks = []
for zs in numpy.linspace(.98, .45, 45):
    sel = numpy.abs(z - zs) < .012
    if sel.sum() < 4:
        continue
    yy = numpy.sort(y[sel])
    cuts = numpy.nonzero(numpy.diff(yy) > .018)[0]
    pieces = numpy.split(yy, cuts + 1)
    centres = [(float(pc.mean()), float(zs)) for pc in pieces if len(pc) >= 2]
    for cy, cz in centres:
        best = None
        for tr in tracks:
            if tr["open"] and abs(tr["pts"][-1][0] - cy) < .035:
                if best is None or abs(tr["pts"][-1][0] - cy) < abs(best["pts"][-1][0] - cy):
                    best = tr
        if best is None:
            tracks.append({"pts": [(cy, cz)], "open": True, "n": len(centres)})
        else:
            best["pts"].append((cy, cz))
    # A track that found no piece in this slice has joined the palm.
    for tr in tracks:
        if tr["open"] and tr["pts"][-1][1] != zs:
            tr["open"] = False
print("MASTER tracks:", [(round(tr["pts"][0][0], 2), round(tr["pts"][0][1], 2), round(tr["pts"][-1][1], 2), len(tr["pts"])) for tr in tracks])
fingers = sorted([tr for tr in tracks if len(tr["pts"]) >= 5 and tr["pts"][0][1] > .74], key=lambda tr: -len(tr["pts"]))[:4]
fingers.sort(key=lambda tr: -tr["pts"][0][0])  # +y (the thumb's side) first: index
names = ["ix", "md", "rn", "pk"][:len(fingers)]
print("MASTER fingers found:", len(fingers), [(round(f["pts"][0][1], 2), round(f["pts"][-1][1], 2)) for f in fingers])
chains = {}
for nm, tr in zip(names, fingers):
    tip_z = max(pz for _py, pz in tr["pts"]) + .02
    base_z = min(pz for _py, pz in tr["pts"]) - .07
    ys = numpy.array([py for py, _pz in tr["pts"]])
    zs_ = numpy.array([pz for _py, pz in tr["pts"]])
    k = numpy.polyfit(zs_, ys, 1)
    sel = (numpy.abs(y - numpy.polyval(k, z)) < .045) & (z > base_z - .02)
    xm = float(x[sel].mean()) if sel.any() else 0.0
    flen = tip_z - base_z

    def at(zz, k=k, xm=xm):
        return [xm, float(numpy.polyval(k, zz)), float(zz)]

    chains[nm] = {"joints": [at(base_z), at(base_z + flen * .45), at(base_z + flen * .74)], "tip": at(tip_z)}
# The thumb: what stands out past the index side of the palm, low down.
fband = (z > .72) & (z < .82)
palm_edge = float(numpy.percentile(y[fband], 99)) + .02 if fband.any() else .2
th = (y > palm_edge) & (z < .78) & (z > .12)
if th.sum() > 10:
    pts = co[th]
    c = pts.mean(axis=0)
    _u, _s, vt = numpy.linalg.svd(pts - c, full_matrices=False)
    d = vt[0] if vt[0][1] > 0 or vt[0][2] > 0 else -vt[0]
    if numpy.dot(d, [0, 1, 1]) < 0:
        d = -d
    proj = (pts - c) @ d
    tip = c + d * proj.max()
    base = c + d * proj.min()
    # The thumb's root goes into the palm a little (its ball).
    base = base - d * .05
    chains["th"] = {"joints": [list(base), list(base + (tip - base) * .38), list(base + (tip - base) * .68)],
                    "tip": list(tip)}
print("MASTER chains:", {k_: [round(v, 2) for v in c_["tip"]] for k_, c_ in chains.items()})


def seg_d(pt, a_, b_):
    ab = b_ - a_
    tt = numpy.clip(((pt - a_) @ ab) / max(ab @ ab, 1e-9), 0, 1)
    return numpy.linalg.norm(pt - (a_ + tt[:, None] * ab), axis=1), tt


# (Now reduced: the fingers were found on the dense remesh.)
bpy.ops.object.select_all(action="DESELECT")
hand.select_set(True)
bpy.context.view_layer.objects.active = hand
dec = hand.modifiers.new("dec", "DECIMATE")
dec.ratio = min(1.0, 1900 / max(1, sum(len(p_.vertices) - 2 for p_ in hand.data.polygons)))
bpy.ops.object.modifier_apply(modifier="dec")
tri = hand.modifiers.new("tri", "TRIANGULATE")
bpy.ops.object.modifier_apply(modifier="tri")
for poly in hand.data.polygons:
    poly.use_smooth = True
co = numpy.array([v.co[:] for v in hand.data.vertices])
z, y, x = co[:, 2], co[:, 1], co[:, 0]
print("MASTER reduced to %d triangles" % len(hand.data.polygons))
# Weights: each vertex to its finger (the nearest chain, if it is past that
# finger's root) and along it to its joints, blended over the joints; the
# rest the palm's, the wrist's ring shared with the forearm.
groups = {}
for nm, ch in chains.items():
    pts = [numpy.array(j) for j in ch["joints"]] + [numpy.array(ch["tip"])]
    for k_ in range(3):
        groups["%s%d" % (nm, k_ + 1)] = numpy.zeros(len(co))
groups["hand"] = numpy.zeros(len(co))
groups["forearm"] = numpy.zeros(len(co))
dist = {}
for nm, ch in chains.items():
    pts = [numpy.array(j) for j in ch["joints"]] + [numpy.array(ch["tip"])]
    d_all = numpy.full(len(co), 9.0)
    for k_ in range(3):
        d, _t = seg_d(co, pts[k_], pts[k_ + 1])
        d_all = numpy.minimum(d_all, d)
    dist[nm] = d_all
owner = {}
for i in range(len(co)):
    best, bd = None, .09
    for nm in chains:
        if dist[nm][i] < bd:
            best, bd = nm, dist[nm][i]
    owner[i] = best
for i in range(len(co)):
    nm = owner[i]
    pt = co[i]
    if nm is None:
        if z[i] < .04:
            f = numpy.clip(z[i] / .04, 0, 1)
            groups["forearm"][i] = .5 * (1 - f)
            groups["hand"][i] = 1 - .5 * (1 - f)
        else:
            groups["hand"][i] = 1.0
        continue
    pts = [numpy.array(j) for j in chains[nm]["joints"]] + [numpy.array(chains[nm]["tip"])]
    # The position along the finger (0 its root .. 3 its tip).
    total = 0.0
    lens = [numpy.linalg.norm(pts[k_ + 1] - pts[k_]) for k_ in range(3)]
    ab = pts[3] - pts[0]
    s_ = numpy.dot(pt - pts[0], ab) / max(numpy.dot(ab, ab), 1e-9)
    if s_ < 0:
        f = numpy.clip(1 + s_ * 6, 0, 1)
        groups["hand"][i] += 1 - f
        groups["%s1" % nm][i] += f
        continue
    pos = s_ * sum(lens)
    k_ = 0
    while k_ < 2 and pos > lens[k_]:
        pos -= lens[k_]
        k_ += 1
    frac = pos / max(lens[k_], 1e-6)
    w_here = 1.0
    blend = .2
    if frac < blend:
        prev = "%s%d" % (nm, k_) if k_ > 0 else "hand"
        sh = .5 + .5 * frac / blend
        groups[prev][i] += 1 - sh
        w_here = sh
    elif frac > 1 - blend and k_ < 2:
        sh = .5 + .5 * (1 - frac) / blend
        groups["%s%d" % (nm, k_ + 2)][i] += 1 - sh
        w_here = sh
    groups["%s%d" % (nm, k_ + 1)][i] += w_here
for nm, w in groups.items():
    vg = hand.vertex_groups.new(name=nm)
    for i in numpy.nonzero(w > .004)[0]:
        vg.add([int(i)], float(w[i]), "REPLACE")
hand.name = "hand_master"
info = {"chains": chains, "width": float(numpy.percentile(y[(z > .3) & (z < .5)], 95)
                                         - numpy.percentile(y[(z > .3) & (z < .5)], 5)),
        "thick": float(numpy.percentile(x[(z > .3) & (z < .5)], 95) - numpy.percentile(x[(z > .3) & (z < .5)], 5)),
        "palm": float(min(c_["joints"][0][2] for k_, c_ in chains.items() if k_ != "th"))}
json.dump(info, open(os.path.join(OUT, "hand_master.json"), "w"), indent=1)
for o in list(bpy.context.scene.objects):
    if o is not hand:
        bpy.data.objects.remove(o)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "hand_master.blend"))
print("MASTER saved", info["width"], info["thick"], info["palm"])
