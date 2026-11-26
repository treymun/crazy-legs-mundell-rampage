"""Turn a Meshy A-pose character (rigged by Meshy's auto-rig) into one of the
game's actors: the format of scripts/blender/export_actors.py (a flat
skeleton, every frame a key of the action "poses", labels head/arm_l/...),
posed frame by frame from the CURRENT model's own keys, so every animation
the game plays works with the new mesh.

    blender -b --python-exit-code 1 -P meshy/tools/build_actor.py -- <config.json>

config: {"kind", "rigged" (Meshy rigged glb), "poses" (dump_actor.gd's
<kind>_poses.json), "old_glb", "old_tex" (assets/art/actor3d_<kind>.png),
"out" (raw dir), "tris", "texture", "gear": "old" | "none",
"skin_fix": [hue shift, saturation scale] (optional)}

What it does:
1. The Meshy mesh is sized to the old model's height, feet on the ground,
   hips over the origin, facing -y (the game's front).
2. Its Meshy skin weights are merged into the game's bones: one bone a body
   piece (torso, head, upper arm, forearm, hand, thigh, shin, foot), so
   RagdollRig finds a segment for every bone and a limb that bends at elbow
   and knee (no RagdollRig.stiff), skinned smoothly across the joints.
3. Each bone's origin sits on the ragdoll's point it stands for (shoulder,
   elbow, hand, hip, knee, foot, head): actors.json "joints" names them for
   RagdollRig.
4. Every key of the old action is retargeted: the old rig's fifteen points
   at that key give the torso's turn and where the hands and feet go; two-bone
   IK with anatomical hinges bends the new limbs to reach them; the head and
   the boots turn as the old ones did.
5. The gear (the gun and whatever else the old body drops when it dies) is
   cut from the old model, keyed exactly as it moved there, on its own bone,
   shrunk at the dead keys as before, so a gun never bends and the ragdoll
   drops it as a piece.
6. Unwrapped, baked under the game's dusk stage as export_actors.py bakes
   (four turns, each texel lit as if facing the camera), the gear's texels
   copied from the old look; a hurt look painted with blood.
Writes <out>/<kind>.glb, <kind>.png, <kind>_hurt.png, <kind>_gearmask.png,
<kind>_gear.png, <kind>.blend, and merges its entry into <out>/actors.json.
"""

import json
import math
import os
import sys

import bmesh
import bpy
import numpy
from mathutils import Matrix, Quaternion, Vector

CFG = json.load(open(sys.argv[sys.argv.index("--") + 1], encoding="utf-8"))
for _k in ("rigged", "poses", "old_glb", "old_tex", "out"):
    if _k in CFG:
        CFG[_k] = os.path.abspath(CFG[_k])
KIND = CFG["kind"]
OUT = CFG["out"]
TEXTURE = int(CFG.get("texture", 512))
TRIS = int(CFG.get("tris", 10000))
os.makedirs(OUT, exist_ok=True)

# Meshy's auto-rig bones -> the game's bones (weights summed).
MERGE = {
    "Hips": "body", "Spine02": "body", "Spine01": "body", "Spine": "body",
    "LeftShoulder": "body", "RightShoulder": "body",
    "neck": "neck", "Head": "head", "head_end": "head", "headfront": "head",
    "LeftArm": "upperarm_l", "LeftForeArm": "forearm_l", "LeftHand": "hand_l",
    "RightArm": "upperarm_r", "RightForeArm": "forearm_r", "RightHand": "hand_r",
    "LeftUpLeg": "thigh_l", "LeftLeg": "shin_l", "LeftFoot": "foot_l", "LeftToeBase": "foot_l",
    "RightUpLeg": "thigh_r", "RightLeg": "shin_r", "RightFoot": "foot_r", "RightToeBase": "foot_r",
}
LABEL = {
    "body": "body", "head": "head",
    "upperarm_l": "arm_l", "forearm_l": "arm_l", "hand_l": "arm_l",
    "upperarm_r": "arm_r", "forearm_r": "arm_r", "hand_r": "arm_r",
    "thigh_l": "leg_l", "shin_l": "leg_l", "foot_l": "leg_l",
    "thigh_r": "leg_r", "shin_r": "leg_r", "foot_r": "leg_r",
}
BONES = list(LABEL)
# The ragdoll's points each bone's origin stands on (RagdollRig constants).
JOINTS = {
    "0": "thigh_l", "1": "thigh_r", "2": "upperarm_l", "3": "upperarm_r", "4": "head",
    "5": "forearm_l", "6": "hand_l", "7": "forearm_r", "8": "hand_r",
    "9": "shin_l", "10": "foot_l", "11": "shin_r", "12": "foot_r",
}
HEAD_FAVOUR = 1.4
GAP = .002
TURNS = (0, 180, 90, 270)


def g2b(p):
    """Godot model space (y up, front +z) to Blender (z up, front -y)."""
    return Vector((p[0], -p[2], p[1]))


C = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))
CI = C.inverted()


def g2b_rot(q):
    """A Godot rotation (x, y, z, w) as a Blender basis."""
    return C @ Quaternion((q[3], q[0], q[1], q[2])).to_matrix() @ CI


def clean():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for o in list(new):
        if o.type == "MESH" and o.name.startswith("Icosphere"):
            bpy.data.objects.remove(o)
            new.remove(o)
    return new


def select(objs, active=None):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or objs[0]


# ---------------------------------------------------------------- the stage
def stage():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.render.fps = 24
    world = bpy.data.worlds.new("world")
    scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    # enemy_actors.py light_for(dusk=True)
    bg.inputs[0].default_value = (.56, .54, .58, 1)
    bg.inputs[1].default_value = .42
    nt.links.new(bg.outputs[0], out.inputs[0])
    for name, travel, power, color in (("key", (.50, .58, -.70), 4.9, (1, .86, .66)),
                                       ("fill", (-.7, .55, -.25), 1.0, (.66, .70, 1)),
                                       ("rim", (-.35, -.75, -.55), 6.5, (1, .70, .42)),
                                       ("rim2", (.6, -.7, -.35), 4.0, (.72, .80, 1))):
        light = bpy.data.lights.new(name, "SUN")
        light.energy = power
        light.color = color
        light.angle = math.radians(6)
        ob = bpy.data.objects.new(name, light)
        ob.rotation_euler = Vector(travel).to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(ob)
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for kind in ("OPTIX", "CUDA"):
            try:
                prefs.compute_device_type = kind
                prefs.get_devices()
                gpus = [d for d in prefs.devices if d.type == kind]
                if gpus:
                    for d in prefs.devices:
                        d.use = d.type == kind
                    scene.cycles.device = "GPU"
                    break
            except Exception:
                continue
    except Exception:
        pass


# ------------------------------------------------------------- the old pose
DUMP = json.load(open(CFG["poses"], encoding="utf-8"))
OLD_H = float(DUMP["height"])
FRAMES = DUMP["frames"]
BY_KEY = {int(round(v)): k for k, v in FRAMES.items()}
KEYS = sorted(BY_KEY)


def old_points(name):
    return [g2b(p) for p in DUMP["points"][name]]


def old_bone(name, i):
    row = DUMP["poses"][name][i]
    return g2b(row[0:3]), g2b_rot(row[3:7]), Vector(row[7:10])


# ------------------------------------------------------------ the new mesh
clean()
stage()
scene = bpy.context.scene
new = import_glb(CFG["rigged"])
arm = next(o for o in new if o.type == "ARMATURE")
meshes = [o for o in new if o.type == "MESH"]
select(meshes)
if len(meshes) > 1:
    bpy.ops.object.join()
mesh = bpy.context.view_layer.objects.active
heads = {b.name: arm.matrix_world @ b.head_local for b in arm.data.bones}
# The rest shape without the armature, applied.
for m in list(mesh.modifiers):
    mesh.modifiers.remove(m)
wm = mesh.matrix_world.copy()
mesh.parent = None
mesh.matrix_world = wm
select([mesh])
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.data.objects.remove(arm)
co = numpy.array([v.co[:] for v in mesh.data.vertices])
lo_z, hi_z = co[:, 2].min(), co[:, 2].max()
s = OLD_H / (hi_z - lo_z)
hip_mid = (heads["LeftUpLeg"] + heads["RightUpLeg"]) / 2
shift = Vector((-hip_mid.x, -hip_mid.y, -lo_z))
fit = Matrix.Diagonal((s, s, s, 1)) @ Matrix.Translation(shift)
mesh.data.transform(fit)
for k in heads:
    heads[k] = fit @ heads[k]
mesh.name = KIND + "_hi"
print("MESHY fitted: scale %.4f, height %.3f" % (s, OLD_H))

# A bulb nose where the cel has one (kind config "nose": "k" how far it
# swells, "r" its radius in metres): the face's most forward point in the
# nose's height band, the vertices round it scaled out from just behind it.
NOSE = None
if CFG.get("nose"):
    _nc = CFG["nose"]
    co = numpy.array([v.co[:] for v in mesh.data.vertices])
    zb = numpy.array(_nc.get("z", [.84, .92])) * OLD_H
    band = (co[:, 2] > zb[0]) & (co[:, 2] < zb[1]) & (numpy.abs(co[:, 0]) < .04 * OLD_H / 1.7)
    tip = co[band][numpy.argmin(co[band][:, 1])]
    r = float(_nc.get("r", .03)) * OLD_H / 1.7
    cen = tip + numpy.array([0, r * .9, 0])
    d = co - cen
    e = numpy.linalg.norm(d, axis=1) / (r * float(_nc.get("reach", 1.8)))
    w = numpy.clip(1 - e, 0, 1) ** 1.2
    co2 = co + d * (float(_nc.get("k", .6)) * w)[:, None]
    for i, v in enumerate(mesh.data.vertices):
        v.co = co2[i]
    NOSE = Vector(tip.tolist())
    print("MESHY nose: tip at %s, %d vertices swelled" % (numpy.round(tip, 3), int((w > .01).sum())))

# A rounder belly where the old cel had a ball (kind config "belly": its
# height and radii as shares of the height, "k" how far it swells): the
# front of the trunk scaled out from a centre inside the belly, faded to
# nothing at the radii; arms and hands untouched.
if CFG.get("belly"):
    _bc = CFG["belly"]
    co = numpy.array([v.co[:] for v in mesh.data.vertices])
    _armg = {g.index for g in mesh.vertex_groups if any(t in g.name for t in ("Arm", "Hand", "Shoulder"))}
    _armw = numpy.zeros(len(co))
    for v in mesh.data.vertices:
        _armw[v.index] = sum(g.weight for g in v.groups if g.group in _armg)
    zb = float(_bc.get("z", .45)) * OLD_H
    band = (numpy.abs(co[:, 2] - zb) < .08 * OLD_H) & (numpy.abs(co[:, 0]) < .12 * OLD_H) & (_armw < .2)
    # (the Meshy model faces -Y here, as the hurt look's "front" assumes)
    fdir = float(_bc.get("front", -1.0))
    yf = float((co[band, 1] * fdir).max())
    cen = numpy.array([0.0, fdir * yf * float(_bc.get("depth", .2)), zb])
    rad = numpy.array([float(_bc.get("rx", .2)), float(_bc.get("ry", .25)), float(_bc.get("rz", .2))]) * OLD_H
    d = co - cen
    e = numpy.sqrt(((d / rad) ** 2).sum(axis=1))
    w = numpy.clip(1 - e, 0, 1) ** 1.5 * (3 - 2 * numpy.clip(1 - e, 0, 1))
    fw = numpy.clip(d[:, 1] * fdir / (.05 * OLD_H) + .5, 0, 1)
    w = w * fw * numpy.clip(1 - _armw * 2, 0, 1)
    k = float(_bc.get("k", .25))
    co2 = co + d * (k * w)[:, None]
    for i, v in enumerate(mesh.data.vertices):
        v.co = co2[i]
    print("MESHY belly: front %+d, out %.3f m at most, %d vertices moved" % (
        fdir, float(numpy.linalg.norm(co2 - co, axis=1).max()), int((w > .01).sum())))

# Matte, as the game's plain bakes are.
for slot in mesh.material_slots:
    m = slot.material
    if m is None or not m.use_nodes:
        continue
    for n in m.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            for inp, val in (("Roughness", 1.0), ("Metallic", 0.0)):
                for link in list(n.inputs[inp].links):
                    m.node_tree.links.remove(link)
                n.inputs[inp].default_value = val
            if "Specular IOR Level" in n.inputs:
                n.inputs["Specular IOR Level"].default_value = 0.0

hi = mesh
lo = hi.copy()
lo.data = hi.data.copy()
lo.name = KIND
scene.collection.objects.link(lo)
select([lo])
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.remove_doubles(threshold=0.0002)
bpy.ops.object.mode_set(mode="OBJECT")
for _ in range(5):
    lo.data.calc_loop_triangles()
    now = len(lo.data.loop_triangles)
    if now <= TRIS * 1.03:
        break
    dec = lo.modifiers.new("dec", "DECIMATE")
    dec.decimate_type = "COLLAPSE"
    dec.ratio = min(1.0, TRIS / now)
    dec.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier="dec")
tri = lo.modifiers.new("tri", "TRIANGULATE")
bpy.ops.object.modifier_apply(modifier="tri")
lo.data.calc_loop_triangles()
print("MESHY tris %d" % len(lo.data.loop_triangles))

# A row of bottles on the bandolier (kind config "bandolier": the cel shows
# them and Meshy kept only the strap): small glass bottles stood in the
# strap from one shoulder across to the other hip, on the chest's surface,
# part of the body (on its bone, so rigid), in the Meshy model too so the
# bake paints them.
if CFG.get("bandolier"):
    from mathutils.bvhtree import BVHTree
    bc = CFG["bandolier"] if isinstance(CFG["bandolier"], dict) else {}
    dg = bpy.context.evaluated_depsgraph_get()
    tree = BVHTree.FromObject(hi, dg)
    sa = heads.get("LeftArm", heads.get("LeftShoulder"))
    sb = heads.get("RightUpLeg")
    if bc.get("from", "l") == "r":
        sa, sb = heads.get("RightArm", heads.get("RightShoulder")), heads.get("LeftUpLeg")
    front = Vector((0, -1, 0))
    nb = int(bc.get("count", 5))
    t0, t1 = bc.get("span", [.2, .62])
    BH = float(bc.get("height", .13)) * OLD_H / 1.7
    BR = float(bc.get("radius", .021)) * OLD_H / 1.7
    dirn = (sb - sa).normalized()
    up_ = Vector((0, 0, 1))
    perp = (up_ - dirn * up_.dot(dirn)).normalized()
    bm_b = bmesh.new()
    placed = 0
    for i in range(nb):
        t = t0 + (t1 - t0) * (i / max(nb - 1, 1))
        p = sa + (sb - sa) * t
        hit, hn, _fi, _d = tree.ray_cast(p + front * .6, -front, 2.0)
        if hit is None:
            continue
        hn = hn if hn.dot(front) > 0 else front
        ax = (perp * float(bc.get("tilt", .2)) + up_ * (1 - float(bc.get("tilt", .2)))).normalized()
        cen = hit + hn.normalized() * (BR * .85)
        rot = ax.to_track_quat("Z", "Y").to_matrix().to_4x4()
        for (d, r1, r2, off) in ((.62, 1.0, 1.0, -.08), (.16, 1.0, .42, .31), (.24, .4, .4, .5)):
            bmesh.ops.create_cone(bm_b, cap_ends=True, segments=8, radius1=BR * r1, radius2=BR * r2, depth=BH * d,
                                  matrix=Matrix.Translation(cen + ax * (BH * off)) @ rot)
        placed += 1
    bmesh.ops.triangulate(bm_b, faces=bm_b.faces[:])
    bme = bpy.data.meshes.new("bottles")
    bm_b.to_mesh(bme)
    bm_b.free()
    bmat = bpy.data.materials.new("bottle_glass")
    bmat.use_nodes = True
    _bs = bmat.node_tree.nodes["Principled BSDF"]
    _gc = [c / 255.0 for c in bc.get("colour", [52, 104, 50])]
    _bs.inputs["Base Color"].default_value = (_gc[0], _gc[1], _gc[2], 1)
    _bs.inputs["Roughness"].default_value = 1.0
    if "Specular IOR Level" in _bs.inputs:
        _bs.inputs["Specular IOR Level"].default_value = 0.0
    bme.materials.append(bmat)
    # into the Meshy model (painted by the bake) ...
    ob_h = bpy.data.objects.new("bottles_hi", bme.copy())
    scene.collection.objects.link(ob_h)
    select([hi, ob_h], hi)
    bpy.ops.object.join()
    # ... and the game mesh, each vertex weighted as the body's nearest
    from mathutils.kdtree import KDTree
    kd = KDTree(len(lo.data.vertices))
    for v in lo.data.vertices:
        kd.insert(v.co, v.index)
    kd.balance()
    ob_l = bpy.data.objects.new("bottles_lo", bme)
    scene.collection.objects.link(ob_l)
    for g in lo.vertex_groups:
        ob_l.vertex_groups.new(name=g.name)
    for v in bme.vertices:
        _co, near, _dd = kd.find(v.co)
        for g in lo.data.vertices[near].groups:
            ob_l.vertex_groups[lo.vertex_groups[g.group].name].add([v.index], g.weight, "REPLACE")
    select([lo, ob_l], lo)
    bpy.ops.object.join()
    lo.data.calc_loop_triangles()
    print("MESHY bandolier: %d bottles on the strap" % placed)

# A thing slung on the back that Meshy left off (kind config "slung": the
# revenue man's fire axe): a wooden handle from "a" to "b" (rest metres, b the
# head's end) and a head ["head": along, out, thick] with its edge "out" the
# way "side" points (+1 the left, -1 the right), painted by the bake from
# plain colours ("wood", "head_colour", "edge_colour"), rigid on the trunk.
if CFG.get("slung"):
    sc_ = CFG["slung"]
    A_, B_ = Vector(sc_["a"]), Vector(sc_["b"])
    ax_ = (B_ - A_).normalized()
    bm_s = bmesh.new()
    rot_ = ax_.to_track_quat("Z", "Y").to_matrix().to_4x4()
    r_ = float(sc_.get("r", .016))
    bmesh.ops.create_cone(bm_s, cap_ends=True, segments=8, radius1=r_, radius2=r_ * .85,
                          depth=(B_ - A_).length, matrix=Matrix.Translation((A_ + B_) / 2) @ rot_)
    n_wood = len(bm_s.faces)
    hl_, ho_, ht_ = sc_.get("head", [.075, .17, .028])
    back_n = Vector((0, 1, 0))
    out_ = (back_n.cross(ax_)).normalized() * float(sc_.get("side", 1))
    if out_.x * float(sc_.get("side", 1)) < 0:
        out_ = -out_
    up_ = ax_
    th_ = up_.cross(out_).normalized()  # (right-handed: the head's faces outward)
    cen_ = B_ - ax_ * (hl_ * .5) + out_ * (ho_ * .25)
    M_ = Matrix((out_, th_, up_)).transposed().to_4x4()
    M_.translation = cen_
    res_ = bmesh.ops.create_cube(bm_s, size=1.0, matrix=M_ @ Matrix.Diagonal((ho_, ht_, hl_, 1)))
    head_f = list({f for v in res_["verts"] for f in v.link_faces})
    # which is which by place: the head's box (its edge the outer third),
    # the rest the handle
    head_set = set(head_f)
    for f_ in bm_s.faces:
        if f_ in head_set:
            off_ = (f_.calc_center_median() - cen_).dot(out_)
            f_.material_index = 2 if off_ > ho_ * .3 else 1
        else:
            f_.material_index = 0
    bmesh.ops.triangulate(bm_s, faces=bm_s.faces[:])
    sme = bpy.data.meshes.new("slung")
    bm_s.to_mesh(sme)
    bm_s.free()
    for nm_, key_, dflt in (("slung_wood", "wood", [120, 82, 46]), ("slung_head", "head_colour", [178, 30, 24]),
                            ("slung_edge", "edge_colour", [150, 150, 150])):
        mt_ = bpy.data.materials.new(nm_)
        mt_.use_nodes = True
        bs_ = mt_.node_tree.nodes["Principled BSDF"]
        cc_ = [c / 255.0 for c in sc_.get(key_, dflt)]
        bs_.inputs["Base Color"].default_value = (cc_[0], cc_[1], cc_[2], 1)
        bs_.inputs["Roughness"].default_value = 1.0
        if "Specular IOR Level" in bs_.inputs:
            bs_.inputs["Specular IOR Level"].default_value = 0.0
        sme.materials.append(mt_)
    # (painted after the bake in plain colours: shed.paint, kind config
    # "paint"; the bake took the wood for the head)
    _pa = sme.attributes.new("paint_id", "INT", "FACE")
    for _p in sme.polygons:
        _pa.data[_p.index].value = 4 + _p.material_index
    CFG.setdefault("paint", {}).update({"4": sc_.get("wood", [120, 82, 46]), "5": sc_.get("head_colour", [178, 30, 24]),
                                        "6": sc_.get("edge_colour", [150, 150, 150])})
    ob_h = bpy.data.objects.new("slung_hi", sme.copy())
    scene.collection.objects.link(ob_h)
    select([hi, ob_h], hi)
    bpy.ops.object.join()
    ob_l = bpy.data.objects.new("slung_lo", sme)
    scene.collection.objects.link(ob_l)
    for g in lo.vertex_groups:
        ob_l.vertex_groups.new(name=g.name)
    _bg = ob_l.vertex_groups.get("Spine02") or ob_l.vertex_groups.get("Spine01") or ob_l.vertex_groups.get("Spine")
    ob_l.vertex_groups[_bg.name].add(list(range(len(sme.vertices))), 1.0, "REPLACE")
    select([lo, ob_l], lo)
    bpy.ops.object.join()
    lo.data.calc_loop_triangles()
    print("MESHY slung: a %.2f m handle and its head on the back, rigid on the trunk" % (B_ - A_).length)

# ------------------------------------------------- merge the skin weights
src_groups = {g.index: g.name for g in lo.vertex_groups}
nv = len(lo.data.vertices)
W = {b: numpy.zeros(nv) for b in BONES + ["neck"]}
for v in lo.data.vertices:
    for ge in v.groups:
        name = MERGE.get(src_groups.get(ge.group, ""), None)
        if name:
            W[name][v.index] += ge.weight
co = numpy.array([v.co[:] for v in lo.data.vertices])
# The neck: its lower half the torso's, its upper half the head's (a head shot
# off leaves the neck on the body).
neck_lo = heads["neck"].z
neck_hi = heads["Head"].z
t = numpy.clip((co[:, 2] - neck_lo) / max(neck_hi - neck_lo, 1e-4), 0, 1)
W["head"] += W["neck"] * t
W["body"] += W["neck"] * (1 - t)
del W["neck"]
total = sum(W.values())
orphan = total < 1e-6
W["body"][orphan] = 1.0
total[orphan] = 1.0
for b in BONES:
    W[b] /= total
# Meshy's auto-rig sometimes binds a stray piece to a far bone (billy's chaw
# rode his left boot): a weight on a vertex far from its bone's segment is
# dropped, and a vertex left with none takes its nearest segment.
_mid = (heads["LeftUpLeg"] + heads["RightUpLeg"]) / 2
_neck = heads["neck"]
_top = Vector((heads["Head"].x, heads["Head"].y, co[:, 2].max()))
SEG = {"body": (_mid, _neck, .62), "head": (_neck, _top, .32)}
for side, S in (("l", "Left"), ("r", "Right")):
    SEG["upperarm_" + side] = (heads[S + "Arm"], heads[S + "ForeArm"], .3)
    SEG["forearm_" + side] = (heads[S + "ForeArm"], heads[S + "Hand"], .3)
    SEG["hand_" + side] = (heads[S + "Hand"], heads[S + "Hand"] + (heads[S + "Hand"] - heads[S + "ForeArm"]) * .8, .26)
    SEG["thigh_" + side] = (heads[S + "UpLeg"], heads[S + "Leg"], .34)
    SEG["shin_" + side] = (heads[S + "Leg"], heads[S + "Foot"], .3)
    SEG["foot_" + side] = (heads[S + "Foot"], heads[S + "ToeBase"], .28)


def seg_dist(pts, a, b):
    a = numpy.array(a[:])
    b = numpy.array(b[:])
    ab = b - a
    t = numpy.clip(((pts - a) @ ab) / max(ab @ ab, 1e-9), 0, 1)
    return numpy.linalg.norm(pts - (a + t[:, None] * ab), axis=1)


_k = OLD_H / 1.7
DIST = {bn: seg_dist(co, *SEG[bn][:2]) for bn in BONES}
dropped = 0
for bn in BONES:
    far = (DIST[bn] > SEG[bn][2] * _k) & (W[bn] > 0)
    dropped += int((far & (W[bn] > .3)).sum())
    W[bn][far] = 0
total = sum(W.values())
none = total < 1e-6
if none.any():
    near = numpy.argmin(numpy.stack([DIST[bn] for bn in BONES]), axis=0)
    for i in numpy.nonzero(none)[0]:
        W[BONES[near[i]]][i] = 1.0
    total = sum(W.values())
for b in BONES:
    W[b] /= total
print("MESHY weights: %d vertices lost a far bone, %d rebound to the nearest" % (dropped, int(none.sum())))
# Things worn on the back (a sack, a pack) ride the trunk only (kind config
# "to_body": [{x, y, z, near}] boxes; vertices within `near` m of an arm's
# own bones keep theirs): Meshy's rig gave a sack's bottom to the arm.
for _bx in CFG.get("to_body", []):
    _in = numpy.ones(len(co), dtype=bool)
    for _ax, _k2 in (("x", 0), ("y", 1), ("z", 2)):
        _in &= (co[:, _k2] >= _bx[_ax][0]) & (co[:, _k2] <= _bx[_ax][1])
    _armd = numpy.min(numpy.stack([DIST[bn] for bn in BONES if bn.startswith(("upperarm", "forearm", "hand"))]), axis=0)
    _in &= _armd > float(_bx.get("near", .07))
    for b in BONES:
        W[b][_in] = 1.0 if b == "body" else 0.0
    print("MESHY to_body: %d vertices ride the trunk only" % int(_in.sum()))
for g in list(lo.vertex_groups):
    lo.vertex_groups.remove(g)
groups = {b: lo.vertex_groups.new(name=b) for b in BONES}
dominant = numpy.argmax(numpy.stack([W[b] for b in BONES]), axis=0)
for b in BONES:
    g = groups[b]
    w = W[b]
    for i in numpy.nonzero(w > .004)[0]:
        g.add([int(i)], float(w[i]), "REPLACE")


def cloud(names):
    idx = [BONES.index(n) for n in names]
    return co[numpy.isin(dominant, idx)]


# ------------------------------------------------------------ the hands
# Meshy's hands are mittens (fingers fused, no finger bones). Each is cut off
# at the wrist and a hand of hands.py put in its place, sized to it: a palm,
# four fingers and a thumb with knuckles and nails, three bones a finger, so
# it can close round a grip. Its skin is the Meshy hand's own colour.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hands  # noqa: E402

HANDF = {}
HANDS = {}
_hand_w = {"l": W["hand_l"], "r": W["hand_r"]}
# The skin's colour: the Meshy texture under its hands.
_img = None
for _m in hi.data.materials:
    if _m and _m.use_nodes:
        for _n in _m.node_tree.nodes:
            if _n.type == "TEX_IMAGE" and _n.image:
                _img = _n.image
_skin = numpy.array([.62, .42, .33])
if _img is not None:
    _iw, _ih = _img.size
    _ipx = numpy.empty(_iw * _ih * 4, dtype=numpy.float32)
    _img.pixels.foreach_get(_ipx)
    _ipx = _ipx.reshape(_ih, _iw, 4)
    _uvl = hi.data.uv_layers.active.data
    _hg = {g.index for g in hi.vertex_groups if g.name in ("LeftHand", "RightHand")}
    _cols = []
    for _pi in range(0, len(hi.data.polygons), 3):
        _poly = hi.data.polygons[_pi]
        _v = hi.data.vertices[_poly.vertices[0]]
        if any(g.group in _hg and g.weight > .7 for g in _v.groups):
            _u = _uvl[_poly.loop_indices[0]].uv
            _cols.append(_ipx[min(_ih - 1, int(_u.y * _ih)), min(_iw - 1, int(_u.x * _iw)), :3])
    if _cols:
        _skin = numpy.median(numpy.array(_cols), axis=0)
# (kind config "skin_rgb": a gloved character's skin taken from this, not
# from Meshy's white gloves - the face otherwise turns to the gloves' grey)
if CFG.get("skin_rgb"):
    _skin = numpy.array(CFG["skin_rgb"], dtype=float) / 255.0
print("MESHY skin colour of the hands", numpy.round(_skin * 255).astype(int))
_cut = numpy.zeros(len(co), dtype=bool)
_measure = {}
for side, S in (("l", "Left"), ("r", "Right")):
    wrist = heads[S + "Hand"]
    sel = _hand_w[side] > .5
    if sel.sum() < 8:
        continue
    hc = Vector(co[sel].mean(axis=0))
    a0 = (hc - wrist).normalized()
    mid = Vector((-1.0 if side == "l" else 1.0, 0.0, 0.0))
    n0 = (mid - a0 * mid.dot(a0)).normalized()
    fwd = Vector((0.0, -1.0, 0.0))
    t0 = (fwd - a0 * fwd.dot(a0) - n0 * fwd.dot(n0)).normalized()
    rel = co[sel] - numpy.array(wrist[:])
    length = float((rel @ numpy.array(a0[:])).max())
    across = rel @ numpy.array(t0[:])
    width = float(numpy.percentile(across, 95) - numpy.percentile(across, 5))
    deep = rel @ numpy.array(n0[:])
    thick = float(numpy.percentile(deep, 95) - numpy.percentile(deep, 5))
    fa = (W["forearm_" + side] > .5)
    rel_f = co[fa] - numpy.array(wrist[:])
    near = rel_f[numpy.abs(rel_f @ numpy.array(a0[:])) < .025]
    if len(near):
        perp = near - numpy.outer(near @ numpy.array(a0[:]), numpy.array(a0[:]))
        wrist_r = float(numpy.median(numpy.linalg.norm(perp, axis=1)))
    else:
        wrist_r = width * .3
    # (The Meshy hand's own length; its width and thickness eased toward a
    # hand's: a mitten measures fat.)
    length = min(length, OLD_H * float(CFG.get("hand_share", .118)))
    width = min(width, length * .5)
    thick = min(thick, length * .2)
    _measure[side] = (wrist, a0, n0, t0, length, width, thick, wrist_r)
    # Cut it off past the wrist.
    _cut |= (_hand_w[side] > .35) & (((co - numpy.array(wrist[:])) @ numpy.array(a0[:])) > .004)
print("MESHY hands cut off: %d vertices" % int(_cut.sum()))
bm = bmesh.new()
bm.from_mesh(lo.data)
bm.verts.ensure_lookup_table()
bmesh.ops.delete(bm, geom=[bm.verts[i] for i in numpy.nonzero(_cut)[0]], context="VERTS")
# The forearm's cut rim evened: the cut runs through a decimated mesh and
# leaves a ragged edge whose teeth stand proud of the hand's wrist sleeve
# (angular panels and spikes at the wrist up close). The rim is put on one
# ring across the forearm, drawn in a little toward the sleeve, and the row
# behind it half-way, so the forearm tapers into the wrist.
_rim_n = 0
for side, (wrist, a0, n0, t0, length, width, thick, wrist_r) in _measure.items():
    rim = [v for v in bm.verts if v.is_boundary and (v.co - wrist).length < .1]
    if len(rim) < 4:
        continue
    ts = [(v.co - wrist).dot(a0) for v in rim]
    t_ring = float(numpy.median(ts))
    rads = [((v.co - wrist) - a0 * (v.co - wrist).dot(a0)).length for v in rim]
    r_ring = float(numpy.median(rads)) * float(CFG.get("rim_tuck", .9))
    rimset = set(rim)
    behind = {e.other_vert(v) for v in rim for e in v.link_edges} - rimset
    for group, share in ((rim, 1.0), (list(behind), .5)):
        for v in group:
            d = v.co - wrist
            t = d.dot(a0)
            rv = d - a0 * t
            r = rv.length
            if r < 1e-6:
                continue
            nt = t + (min(t, t_ring) - t) * share if v not in rimset else t_ring
            nr = r + (min(r, r_ring) - r) * share
            v.co = wrist + a0 * nt + rv * (nr / r)
    _rim_n += len(rim)
print("MESHY forearm rims evened: %d vertices" % _rim_n)
bm.to_mesh(lo.data)
bm.free()
_keep = ~_cut
co = numpy.array([v.co[:] for v in lo.data.vertices])
dominant = dominant[_keep]
for b in list(W):
    W[b] = W[b][_keep]
for side, (wrist, a0, n0, t0, length, width, thick, wrist_r) in _measure.items():
    if CFG.get("hands", "meshy") == "meshy" and os.path.exists(os.path.join(hands.MASTER, "hand_master.blend")):
        hnd = hands.build_meshy(side, wrist, a0, n0, t0, length, width, thick, wrist_r, "hand_" + side,
                                CFG.get("fingers"))
    else:
        hnd = hands.build(side, wrist, a0, n0, t0, length, width, thick, wrist_r, "hand_" + side)
    HANDS[side] = hnd
    HANDF[side] = (wrist, a0, n0)
    me = hnd.obj.data
    att = me.attributes.new("is_hand", "INT", "FACE")
    for i in range(len(me.polygons)):
        att.data[i].value = 1
    print("MESHY %s hand: %.3f m long, %.3f wide, %.3f thick, %d triangles" % (
        side, length, width, thick, sum(len(p.vertices) - 2 for p in me.polygons)))
for side, hnd in HANDS.items():
    for bname, at_ in hnd.bones():
        BONES.append(bname)
        LABEL[bname] = "arm_" + side
    for g in hnd.obj.vertex_groups:
        if g.name not in lo.vertex_groups:
            lo.vertex_groups.new(name=g.name)
if HANDS:
    for g in lo.vertex_groups:
        for hnd in HANDS.values():
            if g.name not in hnd.obj.vertex_groups:
                hnd.obj.vertex_groups.new(name=g.name)
    select([lo] + [h_.obj for h_ in HANDS.values()], lo)
    bpy.ops.object.join()
SKIN = _skin

# ------------------------------------------------ the bones' origins (rest)
J = {}
for side, S in (("l", "Left"), ("r", "Right")):
    J["upperarm_" + side] = heads[S + "Arm"]
    J["forearm_" + side] = heads[S + "ForeArm"]
    J["wrist_" + side] = heads[S + "Hand"]
    if side in HANDS:
        J["hand_" + side] = HANDS[side].middle.copy()
        J["tip_" + side] = HANDS[side].chains["md"][1].copy()
        for bname, at_ in HANDS[side].bones():
            J[bname] = at_.copy()
    else:
        hand = cloud(["hand_" + side])
        J["hand_" + side] = Vector(hand.mean(axis=0)) if len(hand) else heads[S + "Hand"]
        shoulder = heads[S + "Arm"]
        tips = hand if len(hand) else cloud(["forearm_" + side])
        far = tips[numpy.argmax(((tips - numpy.array(shoulder[:])) ** 2).sum(axis=1))]
        J["tip_" + side] = Vector(far)
    J["thigh_" + side] = heads[S + "UpLeg"]
    J["shin_" + side] = heads[S + "Leg"]
    J["ankle_" + side] = heads[S + "Foot"]
    leg = cloud(["thigh_" + side, "shin_" + side, "foot_" + side])
    span = leg[:, 2].max() - leg[:, 2].min()
    low = leg[leg[:, 2] < leg[:, 2].min() + span * .12]
    lowb = leg[leg[:, 2] < leg[:, 2].min() + span * .2]
    foot_r = float(numpy.clip(min(numpy.ptp(lowb[:, 0]), numpy.ptp(lowb[:, 1])) * .55, .03, .14))
    J["foot_" + side] = Vector((low[:, 0].mean(), low[:, 1].mean(), leg[:, 2].min() + foot_r))
headc = cloud(["head"])
J["head"] = Vector((numpy.ptp(headc, axis=0) / 2 + headc.min(axis=0)))
J["neck"] = (J["upperarm_l"] + J["upperarm_r"]) / 2
J["neck"].z = heads["neck"].z
J["body"] = (J["thigh_l"] + J["thigh_r"]) / 2
J["hips"] = J["body"].copy()
# A hand on the hip (kind config "akimbo": [side]): where the waist's side is,
# from the hip joint, at rest (the body's outermost skin a hand above it).
WAIST_OFF = {}
for _sd in CFG.get("akimbo", []):
    _j = J["thigh_" + _sd]
    _sg = 1.0 if J["upperarm_" + _sd].x > 0 else -1.0
    _bc = cloud(["body", "thigh_l", "thigh_r"])
    _zb = float(CFG.get("akimbo_z", .13))
    _m = (numpy.abs(_bc[:, 2] - (_j.z + _zb)) < .04) & (numpy.abs(_bc[:, 1] - _j.y) < .1) & (_bc[:, 0] * _sg > 0)
    if _m.sum() > 5:
        _xo = float((_bc[_m, 0] * _sg).max()) * _sg
        WAIST_OFF[_sd] = Vector((_xo - _j.x, float(numpy.median(_bc[_m, 1])) - _j.y, _zb))
        print("MESHY akimbo %s: the waist's side %.3f m out from the hip joint" % (_sd, abs(_xo - _j.x)))
AKIMBO_KEYS = set()
ORIGIN = {b: J[b] for b in BONES}

# ------------------------------------------------------------------ gear
GEAR = []  # [(bone name, old bone index)]
GRIPS = []
GRIP_AT = {}  # side -> (old bone, the hand's middle at the standing key)
gear_obj = None
MEGA = {}  # the rebuilt megaphone's handle (kind config "megaphone")
HELD_MODEL = {}  # a held thing made with Meshy (kind config "held_model")
FISH_HI = None  # its Meshy model, baked from with the body
VERT_TAIL = []  # each gear vertex's piece (0 the front, 1.. the tail pieces)
TAIL_AT = []  # each tail joint (gear-source space)
TAILS = []  # [(bone, the bone before it, the item's bone)]
# Every part the old body loses when it dies (shrunk at the key "down") that
# is not a piece of its arms, legs or head: the gun and what else it holds.
# One gear bone per old bone, keyed with that bone's own motion.
LOST = []
for _i, _b in enumerate(DUMP["bones"]):
    _lab = DUMP["labels"].get(_b, "body")
    _s0 = DUMP["poses"]["0"][_i][7]
    _sd = DUMP["poses"]["down"][_i][7]
    # ("gear_force": parts held although the old body keeps them at "down" -
    # a boss's scripted fall never dropped the foreman's saw blade)
    _force = _b in CFG.get("gear_force", [])
    if ((_sd >= .2 or _s0 < .2) and not _force) or _b in CFG.get("gear_skip", []):
        continue
    # Kept when nearer a hand or an elbow than the head, a knee or a foot
    # (RagdollRig._find_gear's rule, per part: a cigarette or a boot's toe
    # still shrinks away).
    _o = g2b(DUMP["poses"]["0"][_i][0:3])
    _p0 = [g2b(q) for q in DUMP["points"]["0"]]
    _held = min((_p0[k] - _o).length for k in (5, 6, 7, 8))
    _other = min((_p0[k] - _o).length for k in (4, 9, 10, 11, 12))
    if _held < _other or _b in CFG.get("gear_extra", []) or _force:
        LOST.append(_i)
if CFG.get("gear", "old") == "old" and LOST:
    old_new = import_glb(CFG["old_glb"])
    old_arm = next(o for o in old_new if o.type == "ARMATURE")
    old_mesh = max((o for o in old_new if o.type == "MESH"), key=lambda o: len(o.data.polygons))
    scene.frame_set(int(FRAMES["0"]))
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    ev = old_mesh.evaluated_get(dg)
    em = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
    em.transform(old_mesh.matrix_world)
    names = {g.index: g.name for g in old_mesh.vertex_groups}
    # A part the colour of skin is the old hands round the gun (they shrank
    # with it): the new body has its own hands.
    _img = bpy.data.images.load(CFG["old_tex"])
    _iw, _ih = _img.size
    _px = numpy.array(_img.pixels[:]).reshape(_ih, _iw, 4)
    _uv = old_mesh.data.uv_layers.active.data
    _acc = {}
    for _l in old_mesh.data.loops:
        _v = old_mesh.data.vertices[_l.vertex_index]
        if _v.groups:
            _bn = names[max(_v.groups, key=lambda g: g.weight).group]
            _u = _uv[_l.index].uv
            _acc.setdefault(_bn, []).append(_px[min(_ih - 1, int(_u.y * _ih)), min(_iw - 1, int(_u.x * _iw)), :3])
    for _i in list(LOST):
        _bn = DUMP["bones"][_i]
        _c = numpy.mean(_acc.get(_bn, [[0, 0, 0]]), axis=0) * 255
        _skin = _c[0] > 115 and _c[0] - _c[2] > 40 and _c[1] > _c[2] and _bn not in CFG.get("gear_extra", [])
        print("MESHY gear part %s colour %s%s" % (_bn, numpy.round(_c).astype(int), " (skin: left off)" if _skin else ""))
        if _skin:
            LOST.remove(_i)
            GRIPS.append(_i)
    # The old hands: per side, the skin-coloured part nearest that side's
    # hand point over the living keys (billy's left hand is lost with the
    # gun, his right is a part of the arm). The new hands reach for where
    # those parts sit in every key they show in.
    _skinny = []
    for _bn, _cols in _acc.items():
        _c = numpy.mean(_cols, axis=0) * 255
        _bi = DUMP["bones"].index(_bn) if _bn in DUMP["bones"] else -1
        if _bi < 0 or DUMP["labels"].get(_bn, "body") in ("head", "leg_l", "leg_r"):
            continue
        if _c[0] > 115 and _c[0] - _c[2] > 40 and _c[1] > _c[2] and len(_cols) >= 30:
            _skinny.append(_bi)
            print("MESHY skin part", _bn, DUMP["labels"].get(_bn), len(_cols), numpy.round(_c).astype(int),
                  [round(x, 2) for x in DUMP["poses"]["0"][_bi][0:3]])
    _living = [f for f in FRAMES if not f.startswith("die") and "down" not in f]

    def _at(f, bi):
        return Vector(DUMP["poses"][f][bi][0:3])

    # Parts that move together in every living key are one hand.
    _groups = []
    for _bi in _skinny:
        for _g in _groups:
            if all((_at(f, _bi) - _at(f, _g[0])).length < .12 for f in _living):
                _g.append(_bi)
                break
        else:
            _groups.append([_bi])
    _score = []
    for _g in _groups:
        for _side, _hk in (("l", 6), ("r", 8)):
            _ds = [(_at(f, _g[0]) - Vector(DUMP["points"][f][_hk])).length for f in _living]
            _other = [(_at(f, _g[0]) - Vector(DUMP["points"][f][14 - _hk])).length for f in _living]
            _score.append((sum(_ds) / len(_ds) - sum(_other) / len(_other), _side, _g))
    _score.sort(key=lambda x: x[0])
    _used = []
    for _sc, _side, _g in _score:
        if _side in GRIP_AT or any(_g is u for u in _used) or _sc > 0:
            continue
        GRIP_AT[_side] = (_g, None)
        _used.append(_g)
    # (kind config "grip_parts" {side: [old bones]}: the old hands named where
    # the colour rule takes gold or white for skin - a boss's badge and hat,
    # white gloves)
    if "grip_parts" in CFG:
        GRIP_AT.clear()
        for _side, _bns in CFG["grip_parts"].items():
            GRIP_AT[_side] = ([DUMP["bones"].index(_b) for _b in _bns], None)
    print("MESHY hands:", {k: [DUMP["bones"][i] for i in v[0]] for k, v in GRIP_AT.items()})
    want = {DUMP["bones"][i] for i in LOST}
    keep_v = set()
    for v in old_mesh.data.vertices:
        if v.groups:
            best = max(v.groups, key=lambda g: g.weight)
            if names.get(best.group) in want:
                keep_v.add(v.index)
    bm = bmesh.new()
    bm.from_mesh(em)
    bm.verts.ensure_lookup_table()
    drop = [v for v in bm.verts if v.index not in keep_v]
    bmesh.ops.delete(bm, geom=drop, context="VERTS")
    # The old model's weights (indices into ITS groups) must not ride along.
    for _dl in list(bm.verts.layers.deform.values()):
        bm.verts.layers.deform.remove(_dl)
    gm = bpy.data.meshes.new("gear")
    bm.to_mesh(gm)
    bm.free()
    gear_obj = bpy.data.objects.new("gear_src", gm)
    scene.collection.objects.link(gear_obj)
    # The old look on it, as plain emission (copied, not lit again).
    img = bpy.data.images.load(CFG["old_tex"])
    gmat = bpy.data.materials.new("gear_src")
    gmat.use_nodes = True
    nt = gmat.node_tree
    nt.nodes.clear()
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    e = nt.nodes.new("ShaderNodeEmission")
    tx = nt.nodes.new("ShaderNodeTexImage")
    tx.image = img
    tx.interpolation = "Closest"
    nt.links.new(tx.outputs[0], e.inputs[0])
    nt.links.new(e.outputs[0], o.inputs[0])
    gm.materials.append(gmat)
    # The old parts that touch make one held thing (a gun, a jug, a bottle):
    # one gear bone each, moving as one piece.
    _vbone = []
    for v in old_mesh.data.vertices:
        if v.index in keep_v:
            best = names.get(max(v.groups, key=lambda g: g.weight).group)
            _vbone.append(DUMP["bones"].index(best) if best in DUMP["bones"] else LOST[0])
    _gco = numpy.array([v.co[:] for v in gm.vertices])
    _vb = numpy.array(_vbone)
    # (kind config "gear_scale" [{parts: [old bones], k, side}]: a held thing
    # grown about the point of it nearest the old hand - Maw's dryer was a
    # lollipop in a 4.4 m fist)
    for _gs in CFG.get("gear_scale", []):
        _sel = numpy.isin(_vb, [DUMP["bones"].index(b) for b in _gs["parts"] if b in DUMP["bones"]])
        if not _sel.any():
            continue
        _hp = numpy.array(g2b(DUMP["points"]["0"][8 if _gs.get("side", "r") == "r" else 6])[:])
        _piv = _gco[_sel][numpy.argmin(numpy.linalg.norm(_gco[_sel] - _hp, axis=1))]
        _gco[_sel] = _piv + (_gco[_sel] - _piv) * float(_gs["k"])
        for _i in numpy.nonzero(_sel)[0]:
            gm.vertices[int(_i)].co = _gco[_i]
        print("MESHY gear scaled x%.2f about %s: %d vertices" % (float(_gs["k"]), numpy.round(_piv, 3), int(_sel.sum())))
    # A megaphone the old model drew as a flat disc (its bell's mouth; kind
    # config "megaphone"): the disc's part rebuilt as a real horn - a cone
    # from the disc back toward the hand to a mouthpiece, a pistol handle
    # under it near the narrow end - in one plain colour.
    if CFG.get("megaphone"):
        mcfg = CFG["megaphone"] if isinstance(CFG["megaphone"], dict) else {}
        best = None
        for _x in LOST:
            pts = _gco[_vb == _x]
            if len(pts) < 8:
                continue
            sv = numpy.linalg.svd(pts - pts.mean(0), full_matrices=False)
            flat = sv[1][2] / max(sv[1][0], 1e-6)
            if best is None or flat < best[0]:
                best = (flat, _x, pts.mean(0), sv[2][2], float(numpy.linalg.norm(pts - pts.mean(0), axis=1).max()))
        if best is not None:
            _flat, _xb, _c, _nrm, _rad = best
            _c = Vector(_c)
            _nrm = Vector(_nrm).normalized()
            # (toward the hand that holds it at the standing key)
            _hp = min((g2b(DUMP["points"]["0"][k]) for k in (6, 8)), key=lambda q: (q - _c).length)
            if _nrm.dot(_hp - _c) < 0:
                _nrm = -_nrm
            L = float(mcfg.get("length", 1.5)) * _rad * 2
            r_bell = _rad * float(mcfg.get("bell", 1.0))
            r_tip = float(mcfg.get("tip", .02)) * OLD_H / 1.7
            bmm = bmesh.new()
            bmm.from_mesh(gm)
            bmm.verts.ensure_lookup_table()
            bmesh.ops.delete(bmm, geom=[bmm.verts[i] for i in numpy.nonzero(_vb == _xb)[0]], context="VERTS")
            nk = len(bmm.verts)
            a_ = _nrm
            u_ = (Vector((0, 0, 1)) - a_ * a_.dot(Vector((0, 0, 1)))).normalized()
            w_ = a_.cross(u_)
            seg = 16
            rings = []
            for t, r, th in ((0.0, r_bell, .006), (0.0, r_bell * .94, 0), (1.0, r_tip, 0), (1.06, r_tip * 1.2, 0)):
                ring = []
                for k in range(seg):
                    ang = 2 * math.pi * k / seg
                    ring.append(bmm.verts.new(_c + a_ * (t * L) + (u_ * math.cos(ang) + w_ * math.sin(ang)) * r))
                rings.append(ring)
            part_of = {}
            for ri, (ra, rb) in enumerate(zip(rings, rings[1:])):
                for k in range(seg):
                    f_ = bmm.faces.new((ra[k], ra[(k + 1) % seg], rb[(k + 1) % seg], rb[k]))
                    part_of[f_] = ("rim", "body", "tip")[ri]
            # the inside of the bell (seen from the front: a dark mouth)
            inner = [bmm.verts.new(_c + a_ * (L * .5) + (u_ * math.cos(2 * math.pi * k / seg)
                                                       + w_ * math.sin(2 * math.pi * k / seg)) * r_tip * 2.2)
                     for k in range(seg)]
            for k in range(seg):
                part_of[bmm.faces.new((rings[1][(k + 1) % seg], rings[1][k], inner[k], inner[(k + 1) % seg]))] = "inside"
            part_of[bmm.faces.new(inner)] = "inside"
            part_of[bmm.faces.new(rings[3])] = "tip"
            # the handle: a box under the horn a third of the way from the tip
            hc = _c + a_ * (L * .72) - u_ * (r_tip + (r_bell - r_tip) * .28)
            hl = float(mcfg.get("handle", .1)) * OLD_H / 1.7
            hw = .014 * OLD_H / 1.7
            MEGA.update(handle=hc - u_ * (hl * .45), down=-u_, axis=a_, half=hw)
            box = bmesh.ops.create_cube(bmm, size=1.0)["verts"]
            for v in box:
                q = v.co.copy()
                v.co = hc + a_ * (q.x * hw * 2) + w_ * (q.y * hw * 1.6) - u_ * ((q.z + .5) * hl)
            bmm.normal_update()
            bmesh.ops.recalc_face_normals(bmm, faces=[f for f in bmm.faces if part_of.get(f) != "inside"])
            # Its paint: the old horn's red-brown body, a brass rim and
            # mouthpiece, a dark mouth, a wooden handle; shaded by a light
            # from above and in front (the old gear's bake was lit; this
            # emission copy must carry its own light).
            cols = {"body": mcfg.get("colour", [128, 50, 34]), "rim": mcfg.get("rim", [196, 150, 62]),
                    "tip": mcfg.get("rim", [196, 150, 62]), "inside": [40, 22, 16], "handle": [96, 64, 40]}
            lay = bmm.loops.layers.color.new("mcol")
            Ld = Vector((.3, -.6, .75)).normalized()
            for f in bmm.faces:
                if f.index >= 0 and f not in part_of and not any(v in box for v in f.verts):
                    continue
                part = part_of.get(f, "handle")
                if part == "inside":
                    sh = .6
                else:
                    sh = .5 + .5 * max(0.0, f.normal.dot(Ld))
                c = [ch / 255.0 * sh for ch in cols[part]]
                for l_ in f.loops:
                    l_[lay] = (c[0], c[1], c[2], 1.0)
            nnew = len(bmm.verts) - nk
            for f in bmm.faces:
                if any(v.index < 0 or v.index >= nk for v in f.verts) or all(v.index >= nk for v in f.verts):
                    pass
            bmm.verts.index_update()
            # a plain colour slot for the new faces
            pmat = bpy.data.materials.new("gear_plain")
            pmat.use_nodes = True
            pnt = pmat.node_tree
            pnt.nodes.clear()
            po = pnt.nodes.new("ShaderNodeOutputMaterial")
            pe = pnt.nodes.new("ShaderNodeEmission")
            pvc = pnt.nodes.new("ShaderNodeVertexColor")
            pvc.layer_name = "mcol"
            pnt.links.new(pvc.outputs[0], pe.inputs[0])
            pnt.links.new(pe.outputs[0], po.inputs[0])
            gm.materials.append(pmat)
            for f in bmm.faces:
                if all(v.index >= nk for v in f.verts):
                    f.material_index = len(gm.materials) - 1
            bmm.to_mesh(gm)
            bmm.free()
            _vb = numpy.concatenate([_vb[_vb != _xb], numpy.full(nnew, _xb)])
            _gco = numpy.array([v.co[:] for v in gm.vertices])
            print("MESHY megaphone: the flat disc (%s) rebuilt as a horn %.2f m long, bell %.3f m" % (
                DUMP["bones"][_xb], L, r_bell))
    # A football (kind config "football" {length, width, colour}): the old
    # held parts (a crude cone) rebuilt as a real pigskin at their place and
    # along their long axis - a prolate leather ball, two white stripes near
    # its ends, white laces along its top - in plain colours lit from above.
    if CFG.get("football") is not None and LOST:
        fcfg = CFG["football"] if isinstance(CFG["football"], dict) else {}
        _c = Vector(_gco.mean(0))
        _sv = numpy.linalg.svd(_gco - _gco.mean(0), full_matrices=False)
        a_ = Vector(_sv[2][0]).normalized()
        L = float(fcfg.get("length", .29)) * OLD_H / 1.8
        R = float(fcfg.get("width", .17)) * OLD_H / 1.8 * .5
        _xb = LOST[0]
        bmm = bmesh.new()
        u_ = (Vector((0, 0, 1)) - a_ * a_.dot(Vector((0, 0, 1))))
        if u_.length < .1:
            u_ = Vector((0, 1, 0)) - a_ * a_.dot(Vector((0, 1, 0)))
        u_.normalize()
        w_ = a_.cross(u_)
        seg, nr = 14, 12
        rings = []
        for i in range(1, nr):
            t = -1 + 2 * i / nr
            r = R * math.sqrt(max(0.0, 1 - t * t)) ** .8
            rings.append([bmm.verts.new(_c + a_ * (t * L * .5) + (u_ * math.cos(2 * math.pi * k / seg)
                                                               + w_ * math.sin(2 * math.pi * k / seg)) * r)
                          for k in range(seg)])
        tip0 = bmm.verts.new(_c - a_ * L * .5)
        tip1 = bmm.verts.new(_c + a_ * L * .5)
        part_of = {}
        for ri, (ra, rb) in enumerate(zip(rings, rings[1:])):
            for k in range(seg):
                f_ = bmm.faces.new((ra[k], ra[(k + 1) % seg], rb[(k + 1) % seg], rb[k]))
                part_of[f_] = "stripe" if ri in (1, nr - 4) else "leather"
        for k in range(seg):
            part_of[bmm.faces.new((rings[0][(k + 1) % seg], rings[0][k], tip0))] = "leather"
            part_of[bmm.faces.new((rings[-1][k], rings[-1][(k + 1) % seg], tip1))] = "leather"
        # the laces: a short white ridge on top with cross stitches
        for i in range(-3, 4):
            q = _c + a_ * (i * L * .045) + u_ * (R * 1.0)
            box = bmesh.ops.create_cube(bmm, size=1.0)["verts"]
            for v in box:
                p_ = v.co.copy()
                v.co = q + a_ * (p_.x * L * .018) + w_ * (p_.y * R * .55) + u_ * (p_.z * R * .12)
            for f in {f for v in box for f in v.link_faces}:
                part_of[f] = "lace"
        bmm.normal_update()
        cols = {"leather": fcfg.get("colour", [112, 58, 32]), "stripe": [222, 218, 206], "lace": [230, 226, 214]}
        lay = bmm.loops.layers.color.new("mcol")
        Ld = Vector((.3, -.6, .75)).normalized()
        for f in bmm.faces:
            sh = .55 + .45 * max(0.0, f.normal.dot(Ld))
            c = [ch / 255.0 * sh for ch in cols[part_of.get(f, "leather")]]
            for l_ in f.loops:
                l_[lay] = (c[0], c[1], c[2], 1.0)
        pmat = bpy.data.materials.new("gear_plain")
        pmat.use_nodes = True
        pnt = pmat.node_tree
        pnt.nodes.clear()
        po = pnt.nodes.new("ShaderNodeOutputMaterial")
        pe = pnt.nodes.new("ShaderNodeEmission")
        pvc = pnt.nodes.new("ShaderNodeVertexColor")
        pvc.layer_name = "mcol"
        pnt.links.new(pvc.outputs[0], pe.inputs[0])
        pnt.links.new(pe.outputs[0], po.inputs[0])
        gm.materials.append(pmat)
        for f in bmm.faces:
            f.material_index = len(gm.materials) - 1
        bmm.to_mesh(gm)
        bmm.free()
        _gco = numpy.array([v.co[:] for v in gm.vertices])
        _vb = numpy.full(len(_gco), _xb)
        print("MESHY football: the old held parts rebuilt as a ball %.2f m long, %.2f wide" % (L, R * 2))
    _link = {i: {i} for i in LOST}
    for _x in LOST:
        for _y in LOST:
            if _x < _y:
                _a, _b = _gco[_vb == _x], _gco[_vb == _y]
                if len(_a) and len(_b):
                    _a = _a[:: max(1, len(_a) // 150)]
                    _b = _b[:: max(1, len(_b) // 150)]
                    _dmin = numpy.sqrt(((_a[:, None, :] - _b[None, :, :]) ** 2).sum(-1)).min()
                    # Touching, or near and moving as one in every key.
                    _same = _dmin < .15 * OLD_H / 1.7
                    if _same and _dmin >= .035 * OLD_H / 1.7:
                        for _f in FRAMES:
                            _pa, _ra, _sa = old_bone(_f, _x)
                            _pb, _rb, _sb = old_bone(_f, _y)
                            _qa, _qra, _ = old_bone("0", _x)
                            _qb, _qrb, _ = old_bone("0", _y)
                            if _sa.x < .2 or _sb.x < .2:
                                continue
                            if abs(((_pb - _pa) - (_rb @ _qrb.inverted()) @ (_qb - _qa)).length) > .02 or                                     ((_ra @ _qra.inverted()) @ (_rb @ _qrb.inverted()).inverted()).to_quaternion().angle > .06:
                                _same = False
                                break
                    if _same:
                        _u = _link[_x] | _link[_y]
                        for _k in _u:
                            _link[_k] = _u
    # (kind config "gear_one": every held part is one thing - a catfish
    # the old model built of five pieces)
    if CFG.get("gear_one"):
        _all = set(LOST)
        for _k in LOST:
            _link[_k] = _all
    _items = []
    for _i in LOST:
        if not any(_i in it for it in _items):
            _items.append(sorted(_link[_i]))
    vert_gear = []
    for _b in _vb:
        vert_gear.append(next(k for k, it in enumerate(_items) if _b in it))
    # Bits of the old gear that only made sense round the old fist (kind
    # config "gear_drop": [{"part", "above"}]: a stack of blocks over a jug's
    # neck where the old hand closed) taken away.
    for _gd in CFG.get("gear_drop", []):
        _x = DUMP["bones"].index(_gd["part"]) if _gd["part"] in DUMP["bones"] else -1
        if _x < 0:
            continue
        _sel = (_vb == _x) & (_gco[:, 2] > float(_gd.get("above", -9.0)))
        if not _sel.any():
            continue
        _bmg = bmesh.new()
        _bmg.from_mesh(gm)
        _bmg.verts.ensure_lookup_table()
        bmesh.ops.delete(_bmg, geom=[_bmg.verts[int(i)] for i in numpy.nonzero(_sel)[0]], context="VERTS")
        _bmg.to_mesh(gm)
        _bmg.free()
        _vb = _vb[~_sel]
        _gco = numpy.array([v.co[:] for v in gm.vertices])
        print("MESHY gear part %s: %d vertices above %.3f taken away" % (_gd["part"], int(_sel.sum()), _gd.get("above", -9)))
        vert_gear = [next(k for k, it in enumerate(_items) if _b in it) for _b in _vb]
    # Parts of a held thing floating clear of the rest (a jug's cork above
    # the gap where the old fist was; kind config "gear_snap": [part, ...])
    # dropped straight down onto the part under them.
    for _sn in CFG.get("gear_snap", []):
        _above = -9.0
        if isinstance(_sn, dict):
            _sn, _above = _sn["part"], float(_sn.get("above", -9.0))
        _x = DUMP["bones"].index(_sn) if _sn in DUMP["bones"] else -1
        if _x < 0 or not (_vb == _x).any():
            continue
        _sel = (_vb == _x) & (_gco[:, 2] > _above)
        if not _sel.any():
            continue
        _mine = _gco[_sel]
        _rest = _gco[~_sel & numpy.isin(_vb, list(_link[_x]))]
        if not len(_rest):
            continue
        # the rest under its footprint
        _cx, _cy = _mine[:, 0].mean(), _mine[:, 1].mean()
        _r = max(float(numpy.linalg.norm(_mine[:, :2] - [_cx, _cy], axis=1).max()), .01)
        _under = _rest[(numpy.linalg.norm(_rest[:, :2] - [_cx, _cy], axis=1) < _r * 1.5) & (_rest[:, 2] < _mine[:, 2].min() + .005)]
        if not len(_under):
            continue
        _drop = float(_mine[:, 2].min() - _under[:, 2].max())
        if _drop > .002:
            for _vi in numpy.nonzero(_sel)[0]:
                gm.vertices[int(_vi)].co.z -= _drop
            _gco = numpy.array([v.co[:] for v in gm.vertices])
            print("MESHY gear part %s dropped %.3f m onto the part under it" % (_sn, _drop))
    if os.environ.get("MESHY_DEBUG"):
        for _x in LOST:
            _zz = numpy.sort(_gco[_vb == _x][:, 2])
            if len(_zz) > 1 and numpy.diff(_zz).max() > .01:
                _k = int(numpy.argmax(numpy.diff(_zz)))
                print("MESHY part %s has a gap %.3f-%.3f" % (DUMP["bones"][_x], _zz[_k], _zz[_k + 1]))
            if (_vb == _x).any():
                _pp = _gco[_vb == _x]
                print("MESHY part %s z %.3f-%.3f x %.2f y %.2f n %d" % (DUMP["bones"][_x], _pp[:, 2].min(), _pp[:, 2].max(),
                                                               _pp[:, 0].mean(), _pp[:, 1].mean(), len(_pp)))
    # A held thing made anew with Meshy (kind config "held_model": {glb,
    # length, tris, tails: [shares of its length from the front], band}): the
    # noodler's catfish. It takes the old thing's place at the standing key
    # (its front at the old one's top, in the hand), decimated to a game
    # budget, and is cut across into rigid pieces at each tail joint - each
    # its own unskinned mesh on its own bone (the tail flops in the game,
    # looks only), the rear piece reaching a little forward into the one
    # before so a bend shows no gap. Its look is baked lit from the Meshy
    # model (FISH_HI) with the body, not copied from the old gear.
    if CFG.get("held_model"):
        _hm = CFG["held_model"]
        _old_c = _gco.mean(axis=0)
        _old_ax = Vector(numpy.linalg.svd(_gco - _old_c, full_matrices=False)[2][0])
        if _old_ax.z < 0:
            _old_ax = -_old_ax
        _fnew = import_glb(_hm["glb"])
        _fm = next(o for o in _fnew if o.type == "MESH")
        for _o in _fnew:
            if _o is not _fm:
                bpy.data.objects.remove(_o)
        _wmf = _fm.matrix_world.copy()
        _fm.parent = None
        _fm.matrix_world = _wmf
        select([_fm])
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        _fc = numpy.array([v.co[:] for v in _fm.data.vertices])
        # Its own frame: Meshy lays it along its longest way, back up (+Z);
        # the front (the head) is the end that is wide across (the tail is
        # tall and thin).
        _ctr = _fc.mean(axis=0)
        _ax = Vector(numpy.linalg.svd(_fc - _ctr, full_matrices=False)[2][0])
        _ax.z = 0
        _ax.normalize()
        _sv = (_fc - _ctr) @ numpy.array(_ax[:])
        _L = float(_sv.max() - _sv.min())
        _wd = Vector((0, 0, 1)).cross(_ax).normalized()
        _sw = (_fc - _ctr) @ numpy.array(_wd[:])
        _w_hi = numpy.ptp(_sw[_sv > _sv.max() - _L * .15]) if (_sv > _sv.max() - _L * .15).any() else 0
        _w_lo = numpy.ptp(_sw[_sv < _sv.min() + _L * .15]) if (_sv < _sv.min() + _L * .15).any() else 0
        if _w_lo > _w_hi:
            _ax = -_ax
            _sv = -_sv
            _wd = -_wd
        _k = float(_hm.get("length", .62)) * OLD_H / 1.73 / _L
        # The jaw: a little behind the snout, under the middle line - where
        # the fist closes (its place in the fish's own frame, scaled).
        _front = float(_sv.max())
        _near = (_sv > _front - _L * .09) & (_sv < _front - _L * .03) & (numpy.abs(_sw) < _L * .03)
        _zj = float(numpy.percentile(_fc[_near, 2], 25)) if _near.any() else float(_ctr[2])
        _jaw_f = Vector(_ctr) + _ax * (_front - _L * .05)
        _jaw_f.z = _zj
        # Placed where the old one hung: its front up at the old top, its
        # length along the old one's, its back out to the holding side.
        _top_old = Vector(_gco[numpy.argmax((_gco - _old_c) @ numpy.array(_old_ax[:]))])
        _side_x = 1.0 if J["upperarm_r"].x > 0 else -1.0
        _hold_side = "r"
        _out = Vector((_side_x if _hold_side == "r" else -_side_x, 0, 0))
        _out = (_out - _old_ax * _out.dot(_old_ax)).normalized()
        _Rf = (Matrix((_old_ax, _out, _old_ax.cross(_out))).transposed()
               @ Matrix((_ax, Vector((0, 0, 1)), _ax.cross(Vector((0, 0, 1))))).transposed().inverted())
        _snout = Vector(_ctr) + _ax * _front
        _place = (Matrix.Translation(_top_old) @ (Matrix.Diagonal((_k, _k, _k, 1)) @ _Rf.to_4x4())
                  @ Matrix.Translation(-_snout))
        _fm.data.transform(_place)
        FISH_HI = _fm.copy()
        FISH_HI.data = _fm.data.copy()
        scene.collection.objects.link(FISH_HI)
        FISH_HI.name = "held_model_hi"
        for _sl in FISH_HI.material_slots:
            _m = _sl.material
            if _m is not None and _m.use_nodes:
                for _n in _m.node_tree.nodes:
                    if _n.type == "BSDF_PRINCIPLED":
                        for _inp, _val in (("Roughness", 1.0), ("Metallic", 0.0)):
                            for _lk in list(_n.inputs[_inp].links):
                                _m.node_tree.links.remove(_lk)
                            _n.inputs[_inp].default_value = _val
                        if "Specular IOR Level" in _n.inputs:
                            _n.inputs["Specular IOR Level"].default_value = 0.0
        # The game's copy: welded and decimated.
        select([_fm])
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.mesh.remove_doubles(threshold=0.0003)
        bpy.ops.object.mode_set(mode="OBJECT")
        _want = int(_hm.get("tris", 1800))
        for _ in range(4):
            _fm.data.calc_loop_triangles()
            _now = len(_fm.data.loop_triangles)
            if _now <= _want * 1.05:
                break
            _dm = _fm.modifiers.new("dec", "DECIMATE")
            _dm.ratio = _want / _now
            bpy.ops.object.modifier_apply(modifier="dec")
        _fm.data.calc_loop_triangles()
        _fc2 = numpy.array([v.co[:] for v in _fm.data.vertices])
        _G = (_place.to_3x3() @ _ax).normalized()  # toward the front, placed
        _s0 = (_fc2 - numpy.array(_top_old[:])) @ numpy.array(_G[:])  # 0 at the snout, negative back
        _Lw = float(-_s0.min())
        _cuts = [float(t) * _Lw for t in _hm.get("tails", [.45, .72])]
        _band = float(_hm.get("band", .025)) * OLD_H / 1.73
        # Each face's piece by its middle; the rear piece also takes the
        # faces of the one before within `band` of the joint.
        _faces = []
        for _p in _fm.data.polygons:
            _sc = -float(numpy.mean(_s0[list(_p.vertices)]))
            _seg = sum(1 for _c in _cuts if _sc >= _c)
            _faces.append((_p, _seg))
            if _seg < len(_cuts) and _sc >= _cuts[_seg] - _band:
                _faces.append((_p, _seg + 1))
        _bmf = bmesh.new()
        _vmap = {}
        _vseg = []
        for _p, _seg in _faces:
            _vs = []
            for _vi in _p.vertices:
                if (_vi, _seg) not in _vmap:
                    _vmap[(_vi, _seg)] = _bmf.verts.new(_fm.data.vertices[_vi].co)
                    _vseg.append(_seg)
                _vs.append(_vmap[(_vi, _seg)])
            try:
                _bmf.faces.new(_vs)
            except ValueError:
                pass
        _bmf.verts.index_update()
        gm.clear_geometry()
        _bmf.to_mesh(gm)
        _bmf.free()
        bpy.data.objects.remove(_fm)
        _gco = numpy.array([v.co[:] for v in gm.vertices])
        _vb = numpy.full(len(_gco), LOST[0])
        VERT_TAIL = list(_vseg)
        _items = [sorted(LOST)]
        vert_gear = [0] * len(_gco)
        # The joints (gear-source space): each cut's middle on the fish's line.
        TAIL_AT = []
        for _c in _cuts:
            _ring = _gco[numpy.abs(((_gco - numpy.array(_top_old[:])) @ numpy.array(_G[:])) + _c) < _Lw * .03]
            TAIL_AT.append(Vector(_ring.mean(axis=0)) if len(_ring) else _top_old - _G * _c)
        HELD_MODEL.update(jaw=_place @ _jaw_f, front=_top_old.copy(), G=_G.copy(), out=_out.copy(),
                          length=_Lw, cuts=_cuts)
        print("MESHY held model: %s, %.3f m long, %d triangles in %d pieces (tail joints at %s of its length)" % (
            os.path.basename(_hm["glb"]), _Lw, len(gm.polygons), len(_cuts) + 1,
            [round(c / _Lw, 2) for c in _cuts]))
    for ci, it in enumerate(_items):
        _big = max(it, key=lambda i: int((_vb == i).sum()))
        GEAR.append(("gear%d" % ci, [_big] + [i for i in it if i != _big]))
    for o in old_new:
        bpy.data.objects.remove(o)
    print("MESHY gear: %d verts in %d pieces" % (len(gm.vertices), len(GEAR)))

# ------------------------------------------------------------ the skeleton
data = bpy.data.armatures.new("rig")
rig = bpy.data.objects.new("rig_" + KIND, data)
scene.collection.objects.link(rig)
select([rig])
bpy.ops.object.mode_set(mode="EDIT")
for b in BONES:
    eb = data.edit_bones.new(b)
    eb.head = ORIGIN[b]
    eb.tail = ORIGIN[b] + Vector((0, 0, .08))
gear_rest = {}
if gear_obj is not None:
    gco = numpy.array([v.co[:] for v in gear_obj.data.vertices])
    vg = numpy.array(vert_gear)
    for gi, (gname, cluster) in enumerate(GEAR):
        pts = gco[vg == gi]
        c = Vector(pts.mean(axis=0)) if len(pts) else Vector((0, 0, 1))
        gear_rest[gname] = c
        eb = data.edit_bones.new(gname)
        eb.head = c
        eb.tail = c + Vector((0, 0, .08))
bpy.ops.object.mode_set(mode="POSE")
for pb in rig.pose.bones:
    pb.rotation_mode = "QUATERNION"

# ------------------------------------------------------------ retargeting
P0 = old_points("0")
HIP_L, HIP_R, SH_L, SH_R, HEAD = 0, 1, 2, 3, 4
EL_L, HA_L, EL_R, HA_R, KN_L, FT_L, KN_R, FT_R = 5, 6, 7, 8, 9, 10, 11, 12


def torso_basis(hl, hr, sl, sr):
    hips = (hl + hr) / 2
    shoulders = (sl + sr) / 2
    up = (shoulders - hips).normalized()
    across = ((sr - sl) + (hr - hl)).normalized()
    across = (across - up * across.dot(up)).normalized()
    return Matrix((across, up, across.cross(up))).transposed()


T0 = torso_basis(J["thigh_l"], J["thigh_r"], J["upperarm_l"], J["upperarm_r"])
OLD_HIP_H = (P0[HIP_L].z + P0[HIP_R].z) / 2
NEW_HIP_H = J["hips"].z
HIP_K = NEW_HIP_H / OLD_HIP_H
head_anchor = DUMP["anchors"][1]


def lowest_bone(label):
    best, bz = -1, 1e9
    for i, b in enumerate(DUMP["bones"]):
        if DUMP["labels"].get(b) == label:
            p, _r, sc = old_bone("0", i)
            if sc.x > .2 and p.z < bz:
                best, bz = i, p.z
    return best


boot = {"l": lowest_bone("leg_l"), "r": lowest_bone("leg_r")}


def rel_rot(i, name):
    _p, r, _s = old_bone(name, i)
    _p0, r0, _s0 = old_bone("0", i)
    return r @ r0.inverted()


def frame_of(a, b):
    a = a.normalized()
    b = (b - a * b.dot(a)).normalized()
    return Matrix((a, b, a.cross(b))).transposed()


def two_bone(root, target, l1, l2, pole):
    """The middle joint of a chain root-mid-end reaching for target, bending
    toward pole."""
    d = target - root
    dist = d.length
    reach = (l1 + l2) * .999
    if dist > reach:
        d = d * (reach / dist)
        target = root + d
        dist = reach
    dist = max(dist, abs(l1 - l2) + 1e-3)
    a = (l1 * l1 + dist * dist - l2 * l2) / (2 * dist)
    h = math.sqrt(max(l1 * l1 - a * a, 0.0))
    axis = d.normalized()
    side = pole - axis * pole.dot(axis)
    if side.length < 1e-5:
        side = Vector((0, 0, 1)) - axis * axis.z
    side.normalize()
    return root + axis * a + side * h, target


def limb(R_t, root_r, mid_r, end_r, root_f, target, pole, bend0, stretch=1.0):
    """Upper and lower rotations of a limb (world) and its joints; `stretch`
    lets the limb reach a little further (its skin stretching at the joints)."""
    l1 = (mid_r - root_r).length * stretch
    l2 = (end_r - mid_r).length * stretch
    mid_f, end_f = two_bone(root_f, target, l1, l2, pole)
    u0, v0 = mid_r - root_r, end_r - mid_r
    u1, v1 = mid_f - root_f, end_f - mid_f
    b_rest = bend0 - u0.normalized() * bend0.dot(u0.normalized())
    side_now = v1 - u1.normalized() * v1.dot(u1.normalized())
    if side_now.length < .02 * v1.length:
        side_now = R_t @ bend0
    R_up = frame_of(u1, side_now) @ frame_of(u0, b_rest).inverted()
    was = R_up @ v0
    R_lo = was.rotation_difference(v1).to_matrix() @ R_up
    return R_up, R_lo, mid_f, end_f


def place(R, at_rest, at_now):
    return Matrix.Translation(at_now) @ R.to_4x4() @ Matrix.Translation(-at_rest)


# ------------------------------------------------------- the held things
# Each held thing (ITEMS): who holds it at the standing key, its length along
# its axis, and where on it each holding hand grips (the old hand's place
# along the axis). A thing two hands hold (a long gun) is carried as the old
# one was against the chest (the walk keeps the standing carry, so it never
# swings to the face), brought in to the new chest, and the hands are put ON
# it: the palm against it, the fingers round it, in every key it is held. A
# thing one hand holds (a pistol, a jug) rides that hand, fixed in its palm.
WALK = {"w0", "w1", "w2", "w3", "w4"}
# Keys a two-handed gun is shouldered in, and keys it is carried as standing.
AIMS = set(CFG.get("aim_keys", ["aim", "fire", "wind"]))
CARRY = set(CFG.get("carry_keys", ["fidget", "recover"]))


def old_hand(side, name, P):
    """Where the old hand is at key `name` (its skin part, else the arm's end)."""
    if side in GRIP_AT:
        seen = [old_bone(name, i) for i in GRIP_AT[side][0] if old_bone(name, i)[2].x > .2]
        if seen:
            return sum((q[0] for q in seen), Vector()) / len(seen)
    return P[HA_L if side == "l" else HA_R]


def chest(Pt, R=None, at=None):
    """A chest frame: the shoulders' middle and the torso's turn."""
    if R is None:
        R = torso_basis(Pt[HIP_L], Pt[HIP_R], Pt[SH_L], Pt[SH_R])
        at = (Pt[SH_L] + Pt[SH_R]) / 2
    return Matrix.Translation(at) @ R.to_4x4()


ITEMS = []
if gear_obj is not None:
    _gco = numpy.array([v.co[:] for v in gear_obj.data.vertices])
    _vg = numpy.array(vert_gear)
    # How far forward the old trunk came against the new one (the old billy's
    # belly is a ball; a gun carried against it floats off the new chest).
    _T0o = torso_basis(P0[HIP_L], P0[HIP_R], P0[SH_L], P0[SH_R])
    _fwd_o = -Vector(_T0o.col[2])
    _old_front = (P0[13] - (P0[SH_L] + P0[SH_R]) / 2).dot(_fwd_o) + DUMP["radii"][13]
    _band = (co[:, 2] > J["hips"].z + .1) & (co[:, 2] < J["upperarm_l"].z - .05) & (dominant == BONES.index("body"))
    _fwd_n = -Vector(T0.col[2])
    _shm = numpy.array(((J["upperarm_l"] + J["upperarm_r"]) / 2)[:])
    _new_front = float(((co[_band] - _shm) @ numpy.array(_fwd_n[:])).max()) if _band.any() else _old_front
    for gi, (gname, cluster) in enumerate(GEAR):
        pts = _gco[_vg == gi]
        ctr = Vector(pts.mean(axis=0))
        ax = Vector(numpy.linalg.svd(pts - pts.mean(axis=0))[2][0])
        proj = (pts - numpy.array(ctr[:])) @ numpy.array(ax[:])
        perp = (pts - numpy.array(ctr[:])) - numpy.outer(proj, numpy.array(ax[:]))
        # The rear end (lo) is the thicker one: a stock, a grip, a handle.
        pw = numpy.linalg.norm(perp, axis=1)
        if pw[proj > 0].mean() > pw[proj < 0].mean():
            ax = -ax
            proj = -proj
        lo_e, hi_e = ctr + ax * float(proj.min()), ctr + ax * float(proj.max())
        rad = float(numpy.percentile(numpy.linalg.norm(perp, axis=1), 70))
        holds = {}
        for side in ("l", "r"):
            hp = old_hand(side, "0", P0)
            t = max(0.0, min(1.0, (hp - lo_e).dot(hi_e - lo_e) / max((hi_e - lo_e).length_squared, 1e-6)))
            d = (lo_e + (hi_e - lo_e) * t - hp).length
            if d < .2 * OLD_H / 1.7:
                holds[side] = min(.9, max(.1, t))
        if not holds:
            near = min(("l", "r"), key=lambda sd: (old_hand(sd, "0", P0) - ctr).length)
            holds[near] = .5
        it = {"bone": gname, "big": cluster[0], "lo": lo_e, "hi": hi_e, "rad": min(rad, .05), "holds": holds,
              "two": len(holds) == 2,
              # (the hand on the rear end is the gun hand)
              "main": min(holds, key=lambda sd: holds[sd]) if len(holds) == 2 else ("r" if "r" in holds else "l"),
              "fwd": _new_front - _old_front}
        # Handles (kind config "grip_handles": [side]): the hand closes on
        # the part of the thing its old hand held (a Tommy gun's pistol grip
        # and fore-grip, standing off the barrel) - that part's own axis
        # across the palm, its middle in the fist - not on the barrel's line.
        it["handles"] = {}
        for side in CFG.get("grip_handles", []):
            if side not in holds:
                continue
            hp = old_hand(side, "0", P0)
            cl = pts[numpy.linalg.norm(pts - numpy.array(hp[:]), axis=1) < float(CFG.get("handle_reach", .055))]
            if len(cl) < 12:
                print("MESHY handle %s: too few points by the old hand" % side)
                continue
            cm = cl.mean(axis=0)
            hax = Vector(numpy.linalg.svd(cl - cm)[2][0])
            pr = (cl - cm) @ numpy.array(hax[:])
            hr = float(numpy.percentile(numpy.linalg.norm((cl - cm) - numpy.outer(pr, numpy.array(hax[:])), axis=1), 70))
            hlo, hhi = Vector(cm) + hax * float(pr.min()), Vector(cm) + hax * float(pr.max())
            it["handles"][side] = (hlo, hhi, min(hr, .04))
            print("MESHY handle %s: %.3f m long, %.3f thick, %d degrees off the barrel" % (
                side, (hhi - hlo).length, hr * 2, round(math.degrees(hax.angle(ax)))))
        ITEMS.append(it)
        print("MESHY item %s: %.2f m, held %s, forward fix %.3f" % (
            gname, (hi_e - lo_e).length, {k: round(v, 2) for k, v in holds.items()}, it["fwd"]))


# A held thing's bone rests where its main hand's does: posed as that hand,
# the thing (an unskinned mesh hung off the bone) moves with it rigidly.
if ITEMS:
    bpy.ops.object.mode_set(mode="OBJECT")
    select([rig])
    bpy.ops.object.mode_set(mode="EDIT")
    for it in ITEMS:
        eb = data.edit_bones[it["bone"]]
        eb.head = ORIGIN["hand_" + it["main"]]
        eb.tail = eb.head + Vector((0, 0, .08))
    bpy.ops.object.mode_set(mode="POSE")
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"


def _front(z_lo, z_hi):
    """How far forward of the hips' middle the body's front is between two
    heights (rest, the A-pose; the arms left out)."""
    band = (KEEP0[:, 2] > z_lo) & (KEEP0[:, 2] < z_hi)
    if not band.any():
        return .15
    return float(-(KEEP0[band, 1] - J["hips"].y).min())


def gun_pose(it, butt_or_grip, at, G1, up):
    """The move putting the item's point `butt_or_grip` (a share of its length
    from its rear end) at `at`, its axis along G1, its top toward `up`."""
    G0 = (it["hi"] - it["lo"]).normalized()
    wu = Vector((0, 0, 1))
    U0 = (wu - G0 * wu.dot(G0)).normalized()
    U1 = (up - G1 * up.dot(G1)).normalized()
    Rg = Matrix((G1, U1, G1.cross(U1))).transposed() @ Matrix((G0, U0, G0.cross(U0))).transposed().inverted()
    p = it["lo"] + (it["hi"] - it["lo"]) * butt_or_grip
    return Matrix.Translation(at) @ Rg.to_4x4() @ Matrix.Translation(-p)


def item_delta(it, name, P, D, R_t, hipc):
    """The item's move from where the old one stood at the standing key: a
    two-handed gun posed as a man carries and shoots one (authored for this
    body, the old key's meaning kept), a one-handed thing left to its hand."""
    p0, r0, _s0 = old_bone("0", it["big"])
    p1, r1, s1 = old_bone(name, it["big"])
    old_d = Matrix.Translation(p1) @ (r1 @ r0.inverted()).to_4x4() @ Matrix.Translation(-p0)
    if s1.x < .2:
        return old_d, False
    if not it["two"]:
        return None, True
    bare = name.replace("hurt_", "")
    To_now = TWIST.get("fwd", R_t @ T0)
    F = -Vector(To_now.col[2])
    U = Vector(To_now.col[1])
    Rv = Vector(To_now.col[0])  # toward the character's right
    main = it["main"]
    out = Rv if main == "r" else -Rv  # toward the gun hand's side
    hips = hipc
    sh = hipc + R_t @ (J["upperarm_" + main] - J["hips"])
    gr = it["holds"][main]
    if bare in AIMS:
        # Shouldered: the butt in the gun-side shoulder's pocket, the barrel
        # straight out at the target (a hair down), the cheek down on the
        # stock; fire kicks it back and up; the wind-up holds it at the low
        # ready (muzzle dipped).
        front = _front(J["upperarm_l"].z - .12, J["upperarm_l"].z + .02)
        sh_c = J["upperarm_" + main] - J["hips"]
        depth = front + sh_c.dot(Vector((0, -1, 0)))
        # The butt in the shoulder's pocket (inside the joint, on the chest's
        # front, the shoulder rolled forward for the mount), the barrel level
        # at the target under the cheek.
        G1 = (F - U * .03).normalized()
        butt = (sh + F * (max(.02, depth * .7) + PROTRACT) - out * float(CFG.get("aim_in", .03))
                - U * float(CFG.get("aim_drop", .0)))
        if bare == "fire":
            butt = butt - F * .03
            G1 = (G1 + U * .09).normalized()
        if bare == "wind":
            G1 = (F - U * .22).normalized()
        return gun_pose(it, 0.0, butt, G1, U), True
    if bare == "pain":
        # Lowered to the gun side, muzzle down and ahead, in the one hand.
        at = hips + out * .19 + F * (_front(hips.z - .05, hips.z + .15) * .6) + U * .1
        return gun_pose(it, gr, at, (F * .55 - U * .8 - out * .1).normalized(), -out), True
    # The carry ("port arms"): across the body, the grip at the belt on the
    # gun side, the muzzle up past the other shoulder; the walk sways it a
    # touch with the stride.
    beat = {"w0": 0, "w1": 1, "w2": 2, "w3": 3, "w4": 0}.get(bare, -1)
    # (Held high enough that the stock's butt rides by the hip, clear of
    # the thigh's swing in the walk.)
    # (kind config "carry_dir"/"carry_at" [out, up, fwd]: a big belly holds
    # the gun out, so a steeper carry brings the fore-end to the other hand.)
    cd_ = CFG.get("carry_dir", [.8, .5, .05])
    ca_ = CFG.get("carry_at", [.12, .17, .09])
    G1 = (-out * cd_[0] + U * cd_[1] + F * cd_[2]).normalized()
    at = hips + out * ca_[0] + U * ca_[1] + F * (_front(hips.z + .05, hips.z + .3) + ca_[2])
    if beat >= 0:
        G1 = (Matrix.Rotation(.05 * math.sin(beat * math.pi / 2), 3, F) @ G1).normalized()
        at = at + U * (.012 * math.cos(beat * math.pi))
    return gun_pose(it, gr, at, G1, F), True


def hand_on(it, side, Di, R_t, el_guess):
    """The hand's turn and the wrist's place for holding item `it` (moved by
    Di) at its grip: the hand straight on from the forearm, the palm against
    the thing and the thing across the palm (the fingers then close on it)."""
    hd = it.get("handles", {}).get(side)
    if hd is not None:
        it = dict(it, lo=hd[0], hi=hd[1], rad=hd[2], holds=dict(it["holds"], **{side: .5}))
    lo_e, hi_e = Di @ it["lo"], Di @ it["hi"]
    G = (hi_e - lo_e).normalized()
    grip = lo_e + (hi_e - lo_e) * it["holds"][side]
    a1 = (grip - el_guess).normalized()
    n1 = a1.cross(G)
    if n1.length < .2:
        n1 = a1.cross(Vector((0, 0, 1)))
    n1.normalize()
    up = Vector((0, 0, 1))
    mid = R_t @ Vector((-1.0 if side == "l" else 1.0, 0, 0))
    if n1.dot(up) + .5 * n1.dot(mid) < 0:
        n1 = -n1
    wrist0, a0, n0 = HANDF[side]
    R_h = Matrix((a1, n1, a1.cross(n1))).transposed() @ Matrix((a0, n0, a0.cross(n0))).transposed().inverted()
    palm = HANDS[side].thick * .5 if side in HANDS else .014 * OLD_H / 1.7
    # The palm on the thing's own surface under the grip (not a mean radius).
    surf = it["rad"]
    pts = ITEM_PTS.get(it["bone"], [])
    if len(pts):
        ga = it["lo"] + (it["hi"] - it["lo"]) * it["holds"][side]
        ab = (it["hi"] - it["lo"]).normalized()
        n_loc = (Di.to_3x3().inverted() @ n1).normalized()
        best = None
        for g in pts:
            g = Vector(g)
            if abs((g - ga).dot(ab)) < .035:
                o = -(g - ga).dot(n_loc)
                best = o if best is None or o > best else best
        if best is not None:
            surf = max(best, .008)
    hc = grip - n1 * (surf + palm * .9)
    wrist = hc - R_h @ (J["hand_" + side] - wrist0)
    return R_h, wrist, grip


# The body's own surface where a held thing must not go (the torso, the
# head, the legs: not the arms, which hold it): each vertex with its weights
# on those bones, for posing at a key without the arms.
_KEEP_BONES = ["body", "head", "thigh_l", "thigh_r", "shin_l", "shin_r"]
_kb = numpy.isin(dominant, [BONES.index(b) for b in _KEEP_BONES])
KEEP_IDX = numpy.nonzero(_kb)[0][::2]
KEEP_CO = co[KEEP_IDX]
KEEP0 = KEEP_CO
KEEP_N = numpy.array([lo.data.vertices[int(i)].normal[:] for i in KEEP_IDX])
KEEP_W = numpy.stack([W[b][KEEP_IDX] for b in _KEEP_BONES], axis=1)
KEEP_W = KEEP_W / numpy.maximum(KEEP_W.sum(axis=1, keepdims=True), 1e-6)
ITEM_PTS = {}
ITEM_PTS_DENSE = {}
CONTACT = {}
if gear_obj is not None:
    _gco2 = numpy.array([v.co[:] for v in gear_obj.data.vertices])
    _vg2 = numpy.array(vert_gear)
    for gi, (gname, _c) in enumerate(GEAR):
        _p = _gco2[_vg2 == gi]
        ITEM_PTS[gname] = _p[:: max(1, len(_p) // 240)]
        # (The surface finer for the fingers: its vertices and its faces' middles.)
        _dense = [Vector(v) for v in _p]
        for poly in gear_obj.data.polygons:
            if _vg2[poly.vertices[0]] == gi:
                _dense.append(Vector(poly.center))
                for k_ in range(len(poly.vertices)):
                    a_ = gear_obj.data.vertices[poly.vertices[k_]].co
                    b_ = gear_obj.data.vertices[poly.vertices[(k_ + 1) % len(poly.vertices)]].co
                    _dense.append((a_ + b_) / 2)
        ITEM_PTS_DENSE[gname] = _dense


def body_surface(D):
    """The keep-out surface posed by D (the torso, head and legs)."""
    pts = numpy.zeros_like(KEEP_CO)
    nrm = numpy.zeros_like(KEEP_CO)
    h = numpy.hstack([KEEP_CO, numpy.ones((len(KEEP_CO), 1))])
    for k, b in enumerate(_KEEP_BONES):
        M = numpy.array(D[b])
        w = KEEP_W[:, k:k + 1]
        pts += (h @ M.T)[:, :3] * w
        nrm += (KEEP_N @ M[:3, :3].T) * w
    nrm /= numpy.maximum(numpy.linalg.norm(nrm, axis=1, keepdims=True), 1e-6)
    from mathutils.kdtree import KDTree
    tree = KDTree(len(pts))
    for i, p in enumerate(pts):
        tree.insert(p, i)
    tree.balance()
    return tree, pts, nrm


def depth_in(surface, gname, M, skip=0.0):
    """How deep the held thing (its old shape moved by M) goes into the
    body's surface, and the way out (the mean outward normal there); `skip`:
    the share of its length from its rear end left out (a butt set in the
    shoulder)."""
    tree, pts, nrm = surface
    worst = 0.0
    out = Vector()
    it = next((x for x in ITEMS if x["bone"] == gname), None)
    for g in ITEM_PTS.get(gname, []):
        clear = CLEAR
        if skip and it is not None:
            ab = it["hi"] - it["lo"]
            if (Vector(g) - it["lo"]).dot(ab) / max(ab.length_squared, 1e-9) < skip:
                clear = .003  # (the butt against the shoulder: touching, not in)
        q = M @ Vector(g)
        _co, i, dist = tree.find(q)
        if i is None or dist > .14:
            continue
        # (A clearance kept, so the living body's reel has room.)
        d = (q - Vector(pts[i])).dot(Vector(nrm[i])) - clear
        if d < 0:
            if -d > worst and it is not None:
                ab = it["hi"] - it["lo"]
                KEEP_WHY[gname] = (_KEEP_BONES[int(numpy.argmax(KEEP_W[i]))],
                                   (Vector(g) - it["lo"]).dot(ab) / max(ab.length_squared, 1e-9), float(pts[i][2]))
            worst = max(worst, -d)
            out += Vector(nrm[i])
    return worst, (out.normalized() if out.length > 1e-6 else Vector((0, -1, 0)))


def keep_out(surface, gname, M, name, skip=0.0):
    """M moved out of the body until no part of the thing is inside."""
    first, _w = depth_in(surface, gname, M, skip)
    d = first
    for _ in range(12):
        d, way = depth_in(surface, gname, M, skip)
        if d < .004:
            break
        M = Matrix.Translation(way * (d + .012)) @ M
    # Wedged (the way out turns back and forth): straight out ahead.
    for _ in range(8):
        d, way = depth_in(surface, gname, M, skip)
        if d < .004:
            break
        M = Matrix.Translation(-Vector(TWIST["fwd"].col[2]) * (d + .012)) @ M
    if first > .004:
        print("MESHY keep-out %s %s: %.3f m in, %.3f m after" % (name, gname, first, d)
              + (" (worst on %s at %.2f of its length, z %.2f)" % KEEP_WHY[gname]
                 if os.environ.get("MESHY_DEBUG_KEEP") and gname in KEEP_WHY else ""))
    PEN[name + ":" + gname] = d
    return M


PEN = {}
KEEP_WHY = {}
CLEAR = float(CFG.get("clearance", .02))


TWIST = {}
FINGER_STEP = float(CFG.get("finger_step", .2))
# Shouldering a long gun: how far the shoulders roll forward, and how much
# further the arms may reach (a few per cent: readable at 320x200 matters
# more than a short-armed body's exact reach).
PROTRACT = float(CFG.get("protract", .045))
ARM_K = float(CFG.get("arm_stretch", 1.07))
# What each hand holds when it is one-handed: "pistol" (aimed at the eye
# line) or anything else (carried).
ITEM_TYPE = CFG.get("item_types", {})


UPRIGHT = math.radians(float(CFG.get("upright_deg", 5)))
UPRIGHT_AIM = math.radians(float(CFG.get("upright_aim_deg", 14)))
COM = {}


def plumb(Di, amount, up=None):
    """A held model hung from its jaw (HELD_MODEL): Di turned about the grip
    so the fish's length goes `amount` of the way to plumb (its snout up),
    or to point its snout along `up` (a swing)."""
    g_now = (Di.to_3x3() @ HELD_MODEL["G"]).normalized()
    if up is None:
        up = Vector((0, 0, 1))
    q_ = Quaternion().slerp(g_now.rotation_difference(up.normalized()), amount)
    piv = Di @ HELD_MODEL["grip_pt"]
    return Matrix.Translation(piv) @ q_.to_matrix().to_4x4() @ Matrix.Translation(-piv) @ Di


# The cheek on the gun's side at rest: under the cheekbone, over the jaw
# (from the Meshy rig's Head bone, the skull's base at the jaw's height).
CHEEK_K = OLD_H / 1.73


def cheek_rest(side):
    sx = 1.0 if J["upperarm_" + side].x > J["hips"].x else -1.0
    c = CFG.get("cheek_at", [.04, .065, .03])
    return heads["Head"] + Vector((sx * c[0], -c[1], c[2])) * CHEEK_K


def cheek_weld(D, it, Di, R_t, at):
    """Turns D["head"] so the cheek lies on the gun (see solve); returns the
    gap left (m)."""
    main = it["main"]
    Tn = TWIST["fwd"]
    Fw, Rt = -Vector(Tn.col[2]), Vector(Tn.col[0])
    toward = Rt if main == "r" else -Rt
    lo_e, hi_e = Di @ it["lo"], Di @ it["hi"]
    G = (hi_e - lo_e).normalized()
    pts = [Di @ Vector(g) for g in ITEM_PTS.get(it["bone"], [])]
    base = D["head"]
    piv = base @ J["neck"]
    cr = cheek_rest(main)
    best = None
    for pitch in [i * .05 for i in range(0, 11)]:
        for roll in [i * .05 for i in range(-7, 10)]:
            Rq = (Matrix.Rotation(pitch, 3, Rt) @ Matrix.Rotation(roll if main == "r" else -roll, 3, -Fw))
            Dh = Matrix.Translation(piv) @ Rq.to_4x4() @ Matrix.Translation(-piv) @ base
            c = Dh @ cr
            t = (c - lo_e).dot(G)
            ax = lo_e + G * t
            near = [q for q in pts if abs((q - lo_e).dot(G) - t) < .035]
            top = max((q.z for q in near), default=ax.z + it["rad"])
            side_off = (c - ax) - G * (c - ax).dot(G)
            side_off.z = 0
            gap = c.z - (top + .004)
            cost = abs(gap) * (1.0 if gap > 0 else 3.0) + side_off.length * .7 + (pitch + abs(roll)) * .01
            if best is None or cost < best[0]:
                best = (cost, Dh, gap, side_off.length, pitch, roll)
    D["head"] = best[1]
    CHEEK[NAME_NOW[0]] = (round(best[2], 3), round(best[3], 3), round(best[4], 2), round(best[5], 2))
    return abs(best[2]) + best[3] * .5


CHEEK = {}
NAME_NOW = [""]


def solve(name, dz=0.0, held0=None):
    NAME_NOW[0] = name
    P = old_points(name)
    D = {}
    To = torso_basis(P[HIP_L], P[HIP_R], P[SH_L], P[SH_R])
    bare_name = name.replace("hurt_", "")
    if not bare_name.startswith("die") and bare_name != "down":
        # Stood up: the old body's stoop (the spine pitched forward over the
        # feet) taken out, a slight lean left (a little more into a shot).
        upv = Vector(To.col[1])
        tilt = upv.angle(Vector((0, 0, 1)))
        most = UPRIGHT_AIM if bare_name in AIMS else UPRIGHT
        if tilt > most:
            axis = upv.cross(Vector((0, 0, 1)))
            if axis.length > 1e-6:
                To = Matrix.Rotation(tilt - most, 3, axis.normalized()) @ To
    R_t = To @ T0.inverted()
    TWIST["fwd"] = R_t @ T0
    # Shouldering a long gun two-handed, the body turns the gun's side back
    # and the other shoulder forward, so the other hand reaches the fore-end.
    if any(it["two"] for it in ITEMS) and name.replace("hurt_", "") in AIMS:
        main = next(it["main"] for it in ITEMS if it["two"])
        tw = math.radians(float(CFG.get("aim_twist", 30))) * (-1.0 if main == "r" else 1.0)
        R_t = Matrix.Rotation(tw, 3, Vector(TWIST["fwd"].col[1])) @ R_t
    oh = (P[HIP_L] + P[HIP_R]) / 2
    hipc = Vector((oh.x, oh.y, oh.z * HIP_K + dz))
    # A throw with the whole body (a thing thrown overhand, item type
    # "throw"; kind config "throw_body": {key: [twist back, lean forward
    # (degrees), weight forward, weight to the front foot, hips lowered
    # (m)]}): the wind-up
    # turns the throwing side back with the weight over the rear foot, the
    # release drives the trunk round and forward onto the front foot, the
    # follow-through ("recover") carries on over it. The feet stay planted
    # (the legs reach them anew); the head keeps its own turn (on the target).
    thrower = next((it["main"] for it in ITEMS if ITEM_TYPE.get(it["main"]) == "throw"), None)
    tb = CFG.get("throw_body", {"wind": [60, -7, -.05, -.03, .015], "aim": [48, -4, -.04, -.02, .01],
                                "fire": [-28, 12, .07, .04, .035], "recover": [-40, 15, .09, .05, .045]})
    if thrower is not None and tb and bare_name in tb:
        tw_d, lean_d, fwd_m, side_m, drop_m = (list(tb[bare_name]) + [0.0])[:5]
        hipc = hipc - Vector((0, 0, drop_m))
        Tn = TWIST["fwd"]
        Up_t, Fw_t, Rt_t = Vector(Tn.col[1]), -Vector(Tn.col[2]), Vector(Tn.col[0])
        throw_out = Rt_t if thrower == "r" else -Rt_t
        R_t = Matrix.Rotation(math.radians(tw_d) * (-1.0 if thrower == "r" else 1.0), 3, Up_t) @ R_t
        R_t = Matrix.Rotation(math.radians(lean_d), 3, Up_t.cross(Fw_t).normalized()) @ R_t
        hipc = hipc + Fw_t * fwd_m - throw_out * side_m
    D["body"] = place(R_t, J["hips"], hipc)

    def at(rest):
        return hipc + R_t @ (rest - J["hips"])

    # Head: as the old head turned since the standing key, on the new neck;
    # down on the stock when shouldering a long gun (the cheek on it).
    R_h = rel_rot(head_anchor, name) if head_anchor >= 0 else R_t
    aiming = any(it["two"] for it in ITEMS) and name.replace("hurt_", "") in AIMS
    if aiming and not CFG.get("cheek_weld", False):
        main = next(it["main"] for it in ITEMS if it["two"])
        Tn = TWIST["fwd"]
        R_h = (Matrix.Rotation(float(CFG.get("aim_head_pitch", .32)), 3, Vector(Tn.col[0])) @ Matrix.Rotation(
            (.28 if main == "r" else -.28), 3, -Vector(Tn.col[2]))) @ R_h
    # (kind config "head_keys" {key: [pitch, turn, roll] degrees}: the head
    # set on the trunk for that key instead of the old head's turn - Maw's
    # old pain dropped her face out of sight)
    _hk = CFG.get("head_keys", {}).get(name.replace("hurt_", ""))
    if _hk is not None:
        Tn = TWIST["fwd"]
        R_h = (Matrix.Rotation(math.radians(_hk[0]), 3, Vector(Tn.col[0]))
               @ Matrix.Rotation(math.radians(_hk[1]), 3, Vector(Tn.col[1]))
               @ Matrix.Rotation(math.radians(_hk[2]), 3, -Vector(Tn.col[2]))) @ R_t
    D["head"] = place(R_h, J["neck"], at(J["neck"]))
    joints = {"miss": {}}
    for side, hp, kn, ft, li in (("l", HIP_L, KN_L, FT_L, 2), ("r", HIP_R, KN_R, FT_R, 3)):
        out = 1.0 if side == "l" else -1.0
        hip_f = at(J["thigh_" + side])
        R_f = rel_rot(boot[side], name) if boot[side] >= 0 else R_t
        foot_t = Vector((P[ft].x, P[ft].y, P[ft].z + dz))
        ankle_t = foot_t + R_f @ (J["ankle_" + side] - J["foot_" + side])
        okn = P[kn]
        chord = P[ft] - P[hp]
        off = (okn - P[hp]) - chord.normalized() * (okn - P[hp]).dot(chord.normalized())
        pole = R_t @ Vector((out * .15, -1.0, 0.0))
        if DUMP["stiff"] and not DUMP["stiff"][li] and off.length > .03:
            pole = off
        R_u, R_l, kn_f, an_f = limb(R_t, J["thigh_" + side], J["shin_" + side], J["ankle_" + side],
                                    hip_f, ankle_t, pole, Vector((0, 1, 0)))
        D["thigh_" + side] = place(R_u, J["thigh_" + side], hip_f)
        D["shin_" + side] = place(R_l, J["shin_" + side], kn_f)
        D["foot_" + side] = place(R_f, J["ankle_" + side], an_f)
        joints["foot_" + side] = D["foot_" + side] @ J["foot_" + side]
        joints["foot_t_" + side] = foot_t
    surface = body_surface(D) if ITEMS else None
    # Two-handed things first: where the thing is carried (kept out of the
    # body) says where both hands go. The main hand is fixed to it: the hand
    # is where the thing's grip puts it (the thing is a rigid piece ON that
    # hand: it never bends or slides).
    moves = {}
    on = {}
    main_hand = {}
    for it in ITEMS:
        Di, shown = item_delta(it, name, P, D, R_t, hipc)
        if Di is not None and shown and it["two"]:
            # (kind config "wind_clear": the low ready keeps the whole gun,
            # butt too, a clearance off the body - the live reel pushed the
            # shoulder 5 cm into a butt set in it)
            _bare_k = name.replace("hurt_", "")
            _skip = float(CFG.get("aim_skip", .22)) if _bare_k in AIMS else 0.0
            if _bare_k == "wind" and CFG.get("wind_clear"):
                _skip = 0.0
            Di = keep_out(surface, it["bone"], Di, name, _skip)
        moves[it["bone"]] = (Di, shown)
        if Di is not None and shown and it["two"]:
            for side in it["holds"]:
                bare = name.replace("hurt_", "")
                if side != it["main"] and bare not in AIMS:
                    # The other hand only while the old one is on it (as it
                    # stands for a walk or a carry).
                    ref = "0" if bare in WALK or bare in CARRY else name
                    hp = old_hand(side, ref, old_points(ref))
                    p0, r0, _s0 = old_bone("0", it["big"])
                    p1, r1, _s1 = old_bone(ref, it["big"])
                    od = Matrix.Translation(p1) @ (r1 @ r0.inverted()).to_4x4() @ Matrix.Translation(-p0)
                    lo_e, hi_e = od @ it["lo"], od @ it["hi"]
                    t = max(0.0, min(1.0, (hp - lo_e).dot(hi_e - lo_e) / max((hi_e - lo_e).length_squared, 1e-6)))
                    if (lo_e + (hi_e - lo_e) * t - hp).length > .24 * OLD_H / 1.7:
                        continue
                # (kind config "aim_holds" {side: share}: where each hand
                # takes the shouldered gun - the carry's grips from the old
                # model sat a long way up a long gun, so the arms went out
                # straight and the body leaned after them)
                if bare in AIMS and CFG.get("aim_holds"):
                    on[side] = (dict(it, holds=dict(it["holds"], **CFG["aim_holds"])), Di)
                else:
                    on[side] = (it, Di)

    # The cheek down on the stock (kind config "cheek_weld", opt-in):
    # the head pitched and rolled (within a neck's reach) until the cheek on
    # the gun's side lies on the top of the shouldered gun, over its line.
    if aiming and CFG.get("cheek_weld", False):
        it_c = next((x for x in ITEMS if x["two"] and moves[x["bone"]][0] is not None and moves[x["bone"]][1]), None)
        if it_c is not None:
            Di_c = moves[it_c["bone"]][0]
            joints["cheek"] = cheek_weld(D, it_c, Di_c, R_t, at)
    for side, sh, ha, el in (("l", SH_L, HA_L, EL_L), ("r", SH_R, HA_R, EL_R)):
        out = 1.0 if side == "l" else -1.0
        sh_f = at(J["upperarm_" + side])
        pole = R_t @ Vector((out * .3, .3, -1.0))
        if side in on:
            # Holding the gun: the elbows hang down and in; shouldered, the
            # gun arm's elbow comes out a little, the other stays under.
            two_main = on[side][0]["main"] == side
            if aiming and two_main:
                pole = R_t @ Vector((out * 1.0, .1, -1.0))  # the firing elbow out about 45 degrees
            elif aiming:
                pole = R_t @ Vector((out * .05, 0.0, -1.0))  # the support elbow under the gun
            else:
                pole = R_t @ Vector((out * .12, .25, -1.0))
            if aiming:
                # The shoulders rolled forward into the mount.
                sh_f = sh_f + (-Vector((R_t @ T0).col[2])) * PROTRACT + Vector((0, 0, .015))
        oel = P[el]
        chord = P[ha] - P[sh]
        off = (oel - P[sh]) - chord.normalized() * (oel - P[sh]).dot(chord.normalized())
        if DUMP["stiff"] and not DUMP["stiff"][0 if side == "l" else 1] and off.length > .03 and side not in on:
            pole = off
        if (side in WAIST_OFF and side not in on and side not in main_hand and side in HANDF
                and not bare_name.startswith("die") and bare_name != "down"
                and bare_name not in CFG.get("akimbo_skip", [])):
            # The hand on the hip: a fist, its knuckles on the waist's side
            # just over the belt, the palm back, the elbow out to the side and
            # a little back (a lawman's stance).
            Tn = TWIST["fwd"]
            Fw, Up, Rt = -Vector(Tn.col[2]), Vector(Tn.col[1]), Vector(Tn.col[0])
            outward = (D["body"].to_3x3() @ Vector((WAIST_OFF[side].x, 0, 0))).normalized()
            inward = -outward
            surf = D["body"] @ (J["thigh_" + side] + WAIST_OFF[side])
            a1 = (-Up * .7 + inward * .55 - Fw * .1).normalized()
            face = (-Fw * .7 + inward * .3)
            n1 = (face - a1 * face.dot(a1)).normalized()
            wrist0, a0, n0 = HANDF[side]
            R_hand = Matrix((a1, n1, a1.cross(n1))).transposed() @ Matrix((a0, n0, a0.cross(n0))).transposed().inverted()
            hl = (J["hand_" + side] - wrist0).length
            wrist_t = surf - a1 * hl * 1.25 + outward * .02
            pole_t = (outward * 1.0 - Fw * .4 - Up * .15).normalized()
            R_u, R_l, el_f, wr_f = limb(R_t, J["upperarm_" + side], J["forearm_" + side], J["wrist_" + side],
                                        sh_f, wrist_t, pole_t, Vector((0, -1, 0)))
            D["upperarm_" + side] = place(R_u, J["upperarm_" + side], sh_f)
            D["forearm_" + side] = place(R_l, J["forearm_" + side], el_f)
            D["hand_" + side] = place(R_hand, J["wrist_" + side], wr_f)
            joints["miss"][side] = (wr_f - wrist_t).length
            AKIMBO_KEYS.add(name + ":" + side)
        elif side in main_hand:
            Dh = main_hand[side]
            wrist_t = Dh @ J["wrist_" + side]
            R_u, R_l, el_f, wr_f = limb(R_t, J["upperarm_" + side], J["forearm_" + side],
                                        J["wrist_" + side], sh_f, wrist_t, pole, Vector((0, -1, 0)))
            D["upperarm_" + side] = place(R_u, J["upperarm_" + side], sh_f)
            D["forearm_" + side] = place(R_l, J["forearm_" + side], el_f)
            D["hand_" + side] = Dh
            joints["miss"][side] = (wr_f - wrist_t).length
        elif side in on and side in HANDF:
            it, Di = on[side]
            el_guess = sh_f + R_t @ (J["forearm_" + side] - J["upperarm_" + side]) + pole.normalized() * .1
            # A grip out of reach slides back along the thing toward the
            # main hand's (a short arm on the fore-end of a shouldered gun).
            reach = ((J["forearm_" + side] - J["upperarm_" + side]).length
                     + (J["wrist_" + side] - J["forearm_" + side]).length) * .97 * (ARM_K if aiming else 1.0)
            want = it["holds"][side]
            floor = it["holds"][it["main"]] + .06 if side != it["main"] else want
            while True:
                _R, _w, _g = hand_on(dict(it, holds=dict(it["holds"], **{side: want})), side, Di, R_t, el_guess)
                if (_w - sh_f).length <= reach or want <= floor:
                    break
                want = max(floor, want - .03)
            it = dict(it, holds=dict(it["holds"], **{side: want}))
            for _ in range(4):
                R_hand, wrist_t, grip = hand_on(it, side, Di, R_t, el_guess)
                # The elbow where the forearm runs straight into the hand, if
                # the arm can put it there (the bend's side taken from it).
                want_el = wrist_t - (R_hand @ HANDF[side][1]) * (J["wrist_" + side] - J["forearm_" + side]).length
                p2 = want_el - sh_f
                pole_now = p2 if p2.length > .02 else pole
                pole_now = pole_now + pole.normalized() * .25
                R_u, R_l, el_f, wr_f = limb(R_t, J["upperarm_" + side], J["forearm_" + side],
                                            J["wrist_" + side], sh_f, wrist_t, pole_now, Vector((0, -1, 0)),
                                            ARM_K if aiming else 1.0)
                el_guess = el_f
            D["upperarm_" + side] = place(R_u, J["upperarm_" + side], sh_f)
            D["forearm_" + side] = place(R_l, J["forearm_" + side], el_f)
            D["hand_" + side] = place(R_hand, J["wrist_" + side], wr_f)
            joints["miss"][side] = (wr_f - wrist_t).length
        elif ITEM_TYPE.get(side) == "pistol" and name.replace("hurt_", "") in AIMS and any(
                it["main"] == side and not it["two"] and moves[it["bone"]][1] for it in ITEMS):
            # A pistol aimed one-handed: the arm out straight at the eye line
            # (the elbow just soft), the palm in, the barrel at the target;
            # fire flips the muzzle up, the wind-up holds it lower.
            bare = name.replace("hurt_", "")
            Tn = TWIST["fwd"]
            Fw, Up, Rt = -Vector(Tn.col[2]), Vector(Tn.col[1]), Vector(Tn.col[0])
            inward = -Rt if side == "r" else Rt
            reach = ((J["forearm_" + side] - J["upperarm_" + side]).length
                     + (J["wrist_" + side] - J["forearm_" + side]).length)
            eye = (D["head"] @ J["head"]).z - .06
            a1 = (Fw * 1.0 + inward * .12).normalized()
            if bare == "fire":
                a1 = (a1 + Up * .22).normalized()
            if bare == "wind":
                # Brought up to fire: the muzzle raised, the arm drawn in.
                a1 = (a1 + Up * .9).normalized()
            n1 = inward - a1 * inward.dot(a1)
            n1.normalize()
            wrist0, a0, n0 = HANDF[side]
            R_hand = Matrix((a1, n1, a1.cross(n1))).transposed() @ Matrix((a0, n0, a0.cross(n0))).transposed().inverted()
            wrist_t = sh_f + (a1 * .93 * reach)
            wrist_t.z = eye - (J["hand_" + side] - wrist0).length * .2
            if bare == "wind":
                wrist_t = sh_f + Fw * reach * .45 + inward * .05 + Up * reach * .3
            R_u, R_l, el_f, wr_f = limb(R_t, J["upperarm_" + side], J["forearm_" + side], J["wrist_" + side],
                                        sh_f, wrist_t, R_t @ Vector((0, .2, -1.0)), Vector((0, -1, 0)))
            D["upperarm_" + side] = place(R_u, J["upperarm_" + side], sh_f)
            D["forearm_" + side] = place(R_l, J["forearm_" + side], el_f)
            D["hand_" + side] = place(R_hand, J["wrist_" + side], wr_f)
            joints["miss"][side] = (wr_f - wrist_t).length
        elif (ITEM_TYPE.get(side) == "throw" and name.replace("hurt_", "") == "recover"
              and "recover" in (CFG.get("throw_body") or {"recover": 1})):
            # The follow-through: the throwing arm carried on down and across
            # the body past the front knee, the hand open and falling.
            Tn = TWIST["fwd"]
            Fw, Up, Rt = -Vector(Tn.col[2]), Vector(Tn.col[1]), Vector(Tn.col[0])
            inward = -Rt if side == "r" else Rt
            reach = ((J["forearm_" + side] - J["upperarm_" + side]).length
                     + (J["wrist_" + side] - J["forearm_" + side]).length)
            wrist_t = sh_f + Fw * reach * .55 - Up * reach * .62 + inward * reach * .42
            a1 = (Fw * .35 - Up * .85 + inward * .35).normalized()
            face = (-inward * .5 - Fw * .5)
            n1 = (face - a1 * face.dot(a1)).normalized()
            wrist0, a0, n0 = HANDF[side]
            R_hand = Matrix((a1, n1, a1.cross(n1))).transposed() @ Matrix((a0, n0, a0.cross(n0))).transposed().inverted()
            R_u, R_l, el_f, wr_f = limb(R_t, J["upperarm_" + side], J["forearm_" + side], J["wrist_" + side],
                                        sh_f, wrist_t, (-inward * .5 - Up * .3 + Fw * .4).normalized(),
                                        Vector((0, -1, 0)))
            D["upperarm_" + side] = place(R_u, J["upperarm_" + side], sh_f)
            D["forearm_" + side] = place(R_l, J["forearm_" + side], el_f)
            D["hand_" + side] = place(R_hand, J["wrist_" + side], wr_f)
            joints["miss"][side] = (wr_f - wrist_t).length
        elif ITEM_TYPE.get(side) in ("throw", "raise") and name.replace("hurt_", "") in AIMS and any(
                it["main"] == side and moves[it["bone"]][1] for it in ITEMS):
            # "throw": an overhand throw of a bottle or a jar held by its neck
            # - the wind-up cocks the arm back past the head (elbow up and
            # out, the thing trailing behind), the aim holds it cocked at the
            # ear, the fire is the release with the arm driven through
            # forward and down across the body.
            # "raise": a thing raised to the mouth (a megaphone): the fist
            # under the chin, a little out, the thing's mouth forward.
            bare = name.replace("hurt_", "")
            Tn = TWIST["fwd"]
            Fw, Up, Rt = -Vector(Tn.col[2]), Vector(Tn.col[1]), Vector(Tn.col[0])
            inward = -Rt if side == "r" else Rt
            reach = ((J["forearm_" + side] - J["upperarm_" + side]).length
                     + (J["wrist_" + side] - J["forearm_" + side]).length)
            mode = ITEM_TYPE.get(side)
            if mode == "throw":
                if bare == "wind":
                    wrist_t = sh_f - Fw * reach * .32 + Up * reach * .5 - inward * reach * float(CFG.get("throw_out", .12))
                    a1 = (-Fw * .9 + Up * .25 - inward * .1).normalized()
                    face = (Up * .6 + Fw * .4)
                    pole_t = (-inward * .8 + Up * .2 - Fw * .3)
                elif bare == "aim":
                    wrist_t = sh_f - Fw * reach * .12 + Up * reach * .55 - inward * reach * float(CFG.get("throw_out", .12)) * .67
                    a1 = (-Fw * .45 + Up * .9).normalized()
                    face = (Fw * .7 + inward * .3)
                    pole_t = (-inward * .9 - Up * .2)
                else:
                    wrist_t = sh_f + Fw * reach * .82 + Up * reach * .05 + inward * reach * .22
                    a1 = (Fw * 1.0 + Up * .1 + inward * .15).normalized()
                    face = (-Up * .6 + inward * .4)
                    pole_t = (-inward * .4 - Up * .8 - Fw * .2)
            R_hand = None
            if mode == "raise" and held0 is not None:
                # The thing's narrow end at the mouth and its axis straight
                # out ahead, its own up kept up: the hand turned and put
                # wherever that puts the grip.
                it = next(it for it in ITEMS if it["main"] == side)
                pts = numpy.array([g[:] for g in ITEM_PTS.get(it["bone"], [])])
                ax0 = (it["hi"] - it["lo"]).normalized()
                al = (pts - numpy.array(it["lo"][:])) @ numpy.array(ax0[:])
                perp = numpy.linalg.norm((pts - numpy.array(it["lo"][:])) - numpy.outer(al, ax0[:]), axis=1)
                span = max(float(al.max() - al.min()), 1e-4)
                lo_r = float(perp[al < al.min() + span * .2].max())
                hi_r = float(perp[al > al.max() - span * .2].max())
                narrow, wide = (it["lo"], it["hi"]) if lo_r < hi_r else (it["hi"], it["lo"])
                H0 = held0["hand_" + side]
                Rel = H0.inverted() @ held0["@" + it["bone"]]
                ax_h = (Rel.to_3x3() @ (wide - narrow)).normalized()
                up_h = (H0.to_3x3().inverted() @ Vector((0, 0, 1))).normalized()
                up_h = (up_h - ax_h * up_h.dot(ax_h)).normalized()
                want_ax = (Fw + Up * (.12 if bare == "fire" else .05)).normalized()
                want_up = (Up - want_ax * Up.dot(want_ax)).normalized()
                R_hand = (Matrix((want_ax, want_up, want_ax.cross(want_up))).transposed()
                          @ Matrix((ax_h, up_h, ax_h.cross(up_h))).transposed().inverted())
                mouth = D["head"] @ J["head"] + Fw * (.13 if bare != "wind" else .1) - Up * .06
                n_loc = Rel @ narrow
                wrist_t = mouth - R_hand @ (n_loc - J["wrist_" + side])
                # (the elbow where the forearm runs on into the hand, so the
                # wrist stays near straight)
                lf = (J["wrist_" + side] - J["forearm_" + side]).length
                want_el = wrist_t - (R_hand @ HANDF[side][1]).normalized() * lf
                pole_t = (want_el - sh_f) if (want_el - sh_f).length > .02 else (-inward * .6 - Up * 1.0)
                pole_t = pole_t.normalized() - Up * .3
            elif mode == "raise":
                mouth = D["head"] @ J["head"] + Fw * .1 - Up * .1
                wrist_t = mouth - inward * .04
                a1 = Fw
                face = inward
                pole_t = (-inward * .5 - Up * 1.0)
            if R_hand is None:
                n1 = face - a1 * face.dot(a1)
                n1.normalize()
                wrist0, a0, n0 = HANDF[side]
                R_hand = Matrix((a1, n1, a1.cross(n1))).transposed() @ Matrix((a0, n0, a0.cross(n0))).transposed().inverted()
            R_u, R_l, el_f, wr_f = limb(R_t, J["upperarm_" + side], J["forearm_" + side], J["wrist_" + side],
                                        sh_f, wrist_t, pole_t.normalized(), Vector((0, -1, 0)))
            D["upperarm_" + side] = place(R_u, J["upperarm_" + side], sh_f)
            D["forearm_" + side] = place(R_l, J["forearm_" + side], el_f)
            D["hand_" + side] = place(R_hand, J["wrist_" + side], wr_f)
            joints["miss"][side] = (wr_f - wrist_t).length
        else:
            end_r = J["tip_" + side]
            target = sh_f + (P[ha] - P[sh])
            if side in GRIP_AT and side not in CFG.get("grip_skip", []):
                seen = [old_bone(name, i) for i in GRIP_AT[side][0] if old_bone(name, i)[2].x > .2]
                if seen:
                    target = sum((q[0] for q in seen), Vector()) / len(seen)
                    end_r = J["hand_" + side]
            R_u, R_l, el_f, tip_f = limb(R_t, J["upperarm_" + side], J["forearm_" + side], end_r,
                                         sh_f, target, pole, Vector((0, -1, 0)))
            D["upperarm_" + side] = place(R_u, J["upperarm_" + side], sh_f)
            D["forearm_" + side] = place(R_l, J["forearm_" + side], el_f)
            D["hand_" + side] = place(R_l, J["forearm_" + side], el_f)
            if ITEM_TYPE.get(side) == "raise":
                # (a megaphone carried is tipped up at the wrist, its bell
                # up and out as the cel holds it, so it reads as a horn and
                # not end-on as a disc)
                fa_ = (R_l @ (J["wrist_" + side] - J["forearm_" + side])).normalized()
                k_ = fa_.cross(Vector((0, 0, 1)))
                if k_.length > .1:
                    Rk = Matrix.Rotation(math.radians(float(CFG.get("raise_carry_tip", 50))), 3, k_.normalized())
                    wpt = D["hand_" + side] @ J["wrist_" + side]
                    D["hand_" + side] = place(Rk @ R_l, J["wrist_" + side], wpt)
        joints["hand_" + side] = D["hand_" + side] @ J["hand_" + side]
    # Every held thing is a rigid piece on its main hand: its bone is posed as
    # that hand exactly (its mesh hangs off it, unskinned), shrunk away where
    # the old one was gone (the dead keys: the ragdoll drops it as a piece).
    for it in ITEMS:
        Di, shown = moves[it["bone"]]
        side = it["main"]
        if Di is None:
            if held0 is None and ITEM_TYPE.get(side) == "pistol" and side in HANDF:
                # A pistol in the fist as one is held: its grip (the part that
                # stands off the barrel's line) across the palm under the
                # fingers, the barrel along the forearm over the hand, the
                # gun's top toward the thumb.
                pts = numpy.array([g[:] for g in ITEM_PTS.get(it["bone"], [])])
                ctr = pts.mean(axis=0)
                G0 = Vector(numpy.linalg.svd(pts - ctr)[2][0])
                rel = pts - ctr
                along = rel @ numpy.array(G0[:])
                perp = rel - numpy.outer(along, numpy.array(G0[:]))
                pd = numpy.linalg.norm(perp, axis=1)
                far = pd > numpy.percentile(pd, 80)
                grip = Vector(pts[far].mean(axis=0))
                down0 = Vector(perp[far].mean(axis=0)).normalized()
                # the muzzle: the end the old model pointed at the target in
                # its aim key (the model faces -Y); failing that, the
                # barrel's end away from the grip
                decided = False
                if "aim" in FRAMES:
                    _q0, _r0, _s0 = old_bone("0", it["big"])
                    _q1, _r1, _s1 = old_bone("aim", it["big"])
                    if _s1.x > .2:
                        g_aim = (_r1 @ _r0.inverted()) @ G0
                        if abs(g_aim.y) > .3 * g_aim.length:
                            if g_aim.y > 0:
                                G0 = -G0
                            decided = True
                if not decided:
                    g_al = (grip - Vector(ctr)).dot(G0)
                    if g_al > 0:
                        G0 = -G0
                print("MESHY pistol %s: muzzle %s (%s)" % (it["bone"], numpy.round(G0[:], 2),
                                                         "from the old aim" if decided else "away from the grip"))
                U0 = -(down0 - G0 * down0.dot(G0)).normalized()
                wrist0, a0, n0 = HANDF[side]
                t0 = a0.cross(n0).normalized()
                th = HANDS[side].chains.get("th") if side in HANDS else None
                if th is not None and (th[1] - wrist0).dot(t0) < 0:
                    t0 = -t0
                Rh = D["hand_" + side].to_3x3()
                G1 = (Rh @ a0).normalized()
                U1 = (Rh @ t0).normalized()
                Rg = Matrix((G1, U1, G1.cross(U1))).transposed() @ Matrix((G0, U0, G0.cross(U0))).transposed().inverted()
                palm = D["hand_" + side] @ J["hand_" + side] + (Rh @ n0) * (HANDS[side].thick * .55 if side in HANDS else .015)
                Di = Matrix.Translation(palm) @ Rg.to_4x4() @ Matrix.Translation(-grip)
            elif held0 is None and side in HANDF and ITEM_TYPE.get(side) == "raise" and MEGA:
                # The megaphone held as a pistol is: its handle across the
                # palm under the fingers, the horn over the thumb running out
                # along the hand, the bell ahead past the knuckles.
                wrist0, a0, n0 = HANDF[side]
                t0 = a0.cross(n0).normalized()
                th = HANDS[side].chains.get("th") if side in HANDS else None
                if th is not None and (th[1] - wrist0).dot(t0) < 0:
                    t0 = -t0
                Rh = D["hand_" + side].to_3x3()
                G1 = (Rh @ a0).normalized()
                U1 = (Rh @ t0).normalized()
                G0 = -MEGA["axis"]
                U0 = -MEGA["down"]
                Rg = Matrix((G1, U1, G1.cross(U1))).transposed() @ Matrix((G0, U0, G0.cross(U0))).transposed().inverted()
                palm = (D["hand_" + side] @ (J["hand_" + side] + a0 * (HANDS[side].length * .1 if side in HANDS else .02))
                        + (Rh @ n0) * (MEGA["half"] * 1.6 + (HANDS[side].thick * .5 if side in HANDS else .012)))
                Di = Matrix.Translation(palm) @ Rg.to_4x4() @ Matrix.Translation(-MEGA["handle"])
            elif held0 is None and side in HANDF and ITEM_TYPE.get(side) in ("bottle", "throw"):
                # A bottle in the fist as one is held: its neck across the
                # palm under the fingers (along the knuckles, toward the
                # thumb), the body below the little finger, so the fingers
                # close round the neck.
                pts = numpy.array([g[:] for g in ITEM_PTS.get(it["bone"], [])])
                ctr = pts.mean(axis=0)
                G0 = Vector(numpy.linalg.svd(pts - ctr)[2][0])
                al = (pts - ctr) @ numpy.array(G0[:])
                perp = numpy.linalg.norm((pts - ctr) - numpy.outer(al, G0[:]), axis=1)
                span = float(al.max() - al.min())
                r_lo = float(perp[al < al.min() + span * .25].mean())
                r_hi = float(perp[al > al.max() - span * .25].mean())
                if r_hi > r_lo:
                    G0 = -G0
                    al = -al
                # (G0 now from the body toward the neck; the grip a fifth
                # down from the neck's end)
                g_at = float(al.max()) - span * float(CFG.get("bottle_grip", .2))
                grip = Vector(ctr) + G0 * g_at
                near = numpy.abs(al - g_at) < span * .08
                r_g = float(perp[near].mean()) if near.any() else .015
                X0 = Vector((1, 0, 0)) if abs(G0.x) < .9 else Vector((0, 1, 0))
                if HELD_MODEL and it is ITEMS[0]:
                    # The Meshy catfish by its jaw: the snout up through the
                    # fist (the thumb over it, the barbels out), the body
                    # hanging below the little finger; its width along the
                    # fingers, so the palm is on its cheek and the fingers
                    # wrap round its jaws.
                    G0 = HELD_MODEL["G"].copy()
                    X0 = G0.cross(HELD_MODEL["out"]).normalized()
                    grip = HELD_MODEL["front"] - G0 * (HELD_MODEL["length"] * float(CFG["held_model"].get("grip", .05)))
                    rel_ = numpy.array([g[:] for g in ITEM_PTS_DENSE.get(it["bone"], [])]) - numpy.array(grip[:])
                    sl_ = numpy.abs(rel_ @ numpy.array(G0[:])) < HELD_MODEL["length"] * .025
                    dn_ = rel_[sl_] @ numpy.array(HELD_MODEL["out"][:]) if sl_.any() else numpy.array([-.02, .02])
                    # (the jaws' thickness, back to belly, centred in the fist)
                    # (the barbels left out: the lips' own thickness)
                    lo_, hi_ = float(numpy.percentile(dn_, 12)), float(numpy.percentile(dn_, 88))
                    grip = grip + HELD_MODEL["out"] * ((hi_ + lo_) / 2)
                    r_g = (hi_ - lo_) / 2
                    HELD_MODEL["grip_pt"] = grip.copy()
                    print("MESHY held model grip: %.3f m from the snout, jaws %.3f m thick" % (
                        HELD_MODEL["length"] * float(CFG["held_model"].get("grip", .05)), r_g * 2))
                wrist0, a0, n0 = HANDF[side]
                t0 = a0.cross(n0).normalized()
                th = HANDS[side].chains.get("th") if side in HANDS else None
                if th is not None and (th[1] - wrist0).dot(t0) < 0:
                    t0 = -t0
                Rh = D["hand_" + side].to_3x3()
                U1 = (Rh @ t0).normalized()
                A1 = (Rh @ a0).normalized()
                # the bottle's other axis as near the hand's own as it goes
                X0 = (X0 - G0 * X0.dot(G0)).normalized()
                Rg = Matrix((U1, A1, U1.cross(A1))).transposed() @ Matrix((G0, X0, G0.cross(X0))).transposed().inverted()
                if HELD_MODEL and it is ITEMS[0]:
                    # (hung as a heavy thing is, along the hand past the
                    # fingers: the snout up into the fist toward the wrist,
                    # its width across the knuckles; the fish hangs as the
                    # arm does, not out sideways along the thumb's line)
                    # It swings free at the jaw: it hangs (nearly) plumb
                    # whatever the hand's slant.
                    dn_w = (Vector((0, 0, -1)) * (1 - float(CFG["held_model"].get("follow", .15)))
                            + A1 * float(CFG["held_model"].get("follow", .15))).normalized()
                    x_w = (U1 - dn_w * U1.dot(dn_w)).normalized()
                    Rg = (Matrix((-dn_w, x_w, (-dn_w).cross(x_w))).transposed()
                          @ Matrix((G0, X0, G0.cross(X0))).transposed().inverted())
                palm = (D["hand_" + side] @ (J["hand_" + side] + a0 * (HANDS[side].length * .12 if side in HANDS else .02))
                        + (Rh @ n0) * (r_g + (HANDS[side].thick * .5 if side in HANDS else .012)))
                Di = Matrix.Translation(palm) @ Rg.to_4x4() @ Matrix.Translation(-grip)
            elif held0 is None and side in HANDF and ITEM_TYPE.get(side, "carry") == "carry":
                # Carried hanging (a jug, a bottle, a lantern): by its top (the
                # handle or neck) in the fist, the thing hanging below the hand.
                wrist0, a0, n0 = HANDF[side]
                Rh = D["hand_" + side].to_3x3()
                a_w = (Rh @ a0).normalized()
                pts = [Vector(g) for g in ITEM_PTS.get(it["bone"], [])]
                # (its top as it hangs - the highest point, a neck or a
                # handle - not the end nearest the elbow: a forearm held
                # forward put the jug's side against the palm)
                if CFG.get("carry_top", "hand") == "up":
                    top = max(pts, key=lambda g: g.z) if pts else it["lo"]
                else:
                    top = min(pts, key=lambda g: g.dot(a_w)) if pts else it["lo"]
                # (its top a little into the fist, past the palm's middle)
                hold = D["hand_" + side] @ J["hand_" + side] + a_w * (HANDS[side].length * .12 if side in HANDS else .02)
                Di = Matrix.Translation(hold - top)
            elif held0 is None:
                # The standing key: the old thing's grip put into the new palm.
                lo_e, hi_e = it["lo"], it["hi"]
                grip = lo_e + (hi_e - lo_e) * it["holds"][side]
                wrist0, a0, n0 = HANDF.get(side, (None, Vector((0, 0, -1)), Vector((1, 0, 0))))
                Rh = D["hand_" + side].to_3x3()
                palm = D["hand_" + side] @ J["hand_" + side] + (Rh @ n0) * (it["rad"] + .028 * OLD_H / 1.7)
                Di = Matrix.Translation(palm - grip)
            else:
                Di = D["hand_" + side] @ held0["hand_" + side].inverted() @ held0["@" + it["bone"]]
            hang_ = None
            bare_ = name.replace("hurt_", "")
            if (HELD_MODEL and it is ITEMS[0] and "grip_pt" in HELD_MODEL and bare_ not in AIMS
                    and bare_ not in ("pain", "fire", "aim", "wind") and not bare_.startswith("die")
                    and "down" not in bare_):
                # (carried, it swings back toward plumb from the jaw as the
                # arm swings: turned about the grip in the fist)
                hang_ = (float(CFG["held_model"].get("plumb", .75)) if held0 is not None else 1.0, None)
            elif HELD_MODEL and it is ITEMS[0] and "grip_pt" in HELD_MODEL and bare_ in ("wind", "fire"):
                # The slap: the wind-up swings the fish back behind the hip
                # (its tail trailing low), the blow drives it through forward,
                # the tail leading and a little down.
                Fw_ = -Vector(TWIST["fwd"].col[2])
                Up_ = Vector(TWIST["fwd"].col[1])
                hang_ = (1.0, (Fw_ * .5 + Up_ * .87) if bare_ == "wind" else (-Fw_ + Up_ * .35))
            if hang_ is not None:
                Di = plumb(Di, hang_[0], hang_[1])
            if surface is not None and shown:
                # In the body (a jug against a thigh, a pistol in the belly):
                # the hand moves it out, the arm reaching after it.
                first = depth_in(surface, it["bone"], Di)[0]
                for _ in range(8):
                    d, way = depth_in(surface, it["bone"], Di)
                    if d < .004:
                        break
                    move = Matrix.Translation(way * (d + .012))
                    Dh = move @ D["hand_" + side]
                    sh_f = at(J["upperarm_" + side])
                    out = 1.0 if side == "l" else -1.0
                    pole = R_t @ Vector((out * .3, .3, -1.0))
                    R_u, R_l, el_f, wr_f = limb(R_t, J["upperarm_" + side], J["forearm_" + side],
                                                J["wrist_" + side], sh_f, Dh @ J["wrist_" + side], pole,
                                                Vector((0, -1, 0)))
                    D["upperarm_" + side] = place(R_u, J["upperarm_" + side], sh_f)
                    D["forearm_" + side] = place(R_l, J["forearm_" + side], el_f)
                    # The hand straight on from the new forearm, the thing in it.
                    Dh_new = place(R_l, J["forearm_" + side], el_f)
                    if ITEM_TYPE.get(side) == "raise":
                        # (a thing held up to the mouth keeps its aim: the
                        # hand keeps its turn, only moved)
                        Dh_new = place(D["hand_" + side].to_3x3(), J["wrist_" + side], wr_f)
                    Di = Dh_new @ D["hand_" + side].inverted() @ Di
                    D["hand_" + side] = Dh_new
                    if hang_ is not None:
                        # (the fish swings back to its hang from the jaw)
                        Di = plumb(Di, hang_[0], hang_[1])
                d = depth_in(surface, it["bone"], Di)[0]
                if first > .004:
                    print("MESHY keep-out %s %s: %.3f m in, %.3f m after" % (name, it["bone"], first, d))
                PEN[name + ":" + it["bone"]] = d
        D["@" + it["bone"]] = Di
        D[it["bone"]] = D["hand_" + side]
        if (it["two"] or (HELD_MODEL and it is ITEMS[0])) and held0 is not None and Di is not None:
            # A two-handed gun keeps its own place (each hand takes hold of
            # it afresh in each key, the wrists straight): its bone moves as
            # the gun did from the standing key, where it rested on the hand.
            D[it["bone"]] = Di @ held0["@" + it["bone"]].inverted() @ held0["hand_" + side]
        if not shown:
            c = ORIGIN["hand_" + side]
            D[it["bone"]] = (D["hand_" + side] @ Matrix.Translation(c) @ Matrix.Diagonal((1e-3, 1e-3, 1e-3, 1))
                             @ Matrix.Translation(-c))
    # The body's middle over its feet (the hips' and the shoulders' middle,
    # weighted as a trunk is) against the feet's middle, ahead or behind.
    trunk = (D["body"] @ J["hips"]) * .55 + (D["body"] @ ((J["upperarm_l"] + J["upperarm_r"]) / 2)) * .45
    feet = (joints["foot_l"] + joints["foot_r"]) / 2
    fwd_now = -Vector((R_t @ T0).col[2])
    joints["com"] = (trunk - feet).dot(Vector((fwd_now.x, fwd_now.y, 0)).normalized())
    # The fingers: closed round whatever the hand holds (as tight as they go
    # without going into it, the thumb over), else hanging a little curled.
    for side, hnd in HANDS.items():
        held_by = None
        if side in on:
            held_by = (on[side][0], moves[on[side][0]["bone"]][0])
        for it in ITEMS:
            if held_by is None and it["main"] == side and moves[it["bone"]][1] and ("@" + it["bone"]) in D:
                held_by = (it, D["@" + it["bone"]])
        Dh = D["hand_" + side]
        if held_by is not None and held_by[1] is not None:
            it, Di = held_by
            inv = Dh.inverted()
            gp = [inv @ (Di @ Vector(g)) for g in ITEM_PTS_DENSE.get(it["bone"], [])]
            if gp:
                curls, rep = hands.wrap_curls(hnd, gp)
                # A finger the solve left open (short of the surface, or one
                # that began inside it) closes into the fist's grip instead
                # of lying flat: a hand on a thing is never a starfish.
                for c_, (g_, i_) in rep.items():
                    if c_ in curls and (g_ > .008 or i_):
                        fist = hands.spread(c_, 2.2 if c_ != "th" else 1.2)
                        curls[c_] = [max(x_, y_) for x_, y_ in zip(curls[c_], fist)]
                # Neighbouring fingers bend at their roots within a little of
                # each other (the skin between them tore into slivers when one
                # closed far more than the next).
                order = [c_ for c_ in ("ix", "md", "rn", "pk") if c_ in curls]
                for _ in range(3):
                    for a_, b_ in zip(order, order[1:]):
                        for j_ in (0, 1):
                            d_ = curls[a_][j_] - curls[b_][j_]
                            if abs(d_) > FINGER_STEP:
                                fix_ = (abs(d_) - FINGER_STEP) / 2 * (1 if d_ > 0 else -1)
                                curls[a_][j_] -= fix_
                                curls[b_][j_] += fix_
                gaps = [g for c_, (g, _i) in rep.items() if c_ != "pk"]
                inside = [c_ for c_, (_g, i_) in rep.items() if i_]
                touching = sum(1 for g in gaps if g < .004)
                CONTACT[name + ":" + side] = (touching / max(1, len(gaps)), max(gaps), inside)
                if os.environ.get("MESHY_DEBUG") and name in ("0", "aim", "pain"):
                    print("DBG contact", name, side, {c_: (round(g, 3), i_) for c_, (g, i_) in rep.items()},
                          {c_: round(sum(v), 2) if isinstance(v, list) else v for c_, v in curls.items()})
            else:
                curls = hands.grip_curls(hnd, inv @ (Di @ it["lo"]), inv @ (Di @ it["hi"]), it["rad"])
            fm = hands.curl_moves(hnd, curls, hands.THUMB_OPPOSE)
        else:
            # (a free hand hangs relaxed: the fingers softly curled, never
            # flat or splayed)
            rc = float(CFG.get("relaxed_curl", 1.15))
            curls = {c: hands.spread(c, rc if c != "th" else rc * .45) for c in hnd.chains}
            if name + ":" + side in AKIMBO_KEYS:
                # (the hand on the hip a fist, the thumb along the fingers)
                curls = {c: hands.spread(c, 2.1 if c != "th" else .9) for c in hnd.chains}
            fm = hands.curl_moves(hnd, curls)
        for bname, M in fm.items():
            D[bname] = Dh @ M
        # The joints' limits: the wrist's bend off the forearm's line.
        fa = (D["forearm_" + side].to_3x3() @ (J["wrist_" + side] - J["forearm_" + side])).normalized()
        ha = (Dh.to_3x3() @ HANDF[side][1]).normalized()
        joints.setdefault("wrist", {})[side] = math.degrees(fa.angle(ha))
    return D, joints, P


HELD0 = None


AIM_BEST = {}


def pose_key(name):
    bare = name.replace("hurt_", "")
    if any(it["two"] for it in ITEMS) and bare in AIMS and "aim_twist" not in CFG:
        # The shouldered stance that fits this body (how far it is bladed,
        # how low and how far in the butt sits in the shoulder): the one with
        # both hands on the gun and nothing in the body.
        key = name
        if key not in AIM_BEST:
            best = None
            for tw in (30, 40, 50):
                for drop in CFG.get("aim_drops", [-.06, -.03, 0.0, .02, .04] if CFG.get("cheek_weld") else [0.0, .02, .04]):
                    for inn in (0.0, .03, .06):
                        CFG.update(aim_twist=tw, aim_drop=drop, aim_in=inn)
                        _D, jt, _P = solve(key, 0.0, HELD0)
                        miss = sum(jt["miss"].values())
                        pen = max([v for k, v in PEN.items() if k.startswith(key + ":")] or [0.0])
                        score = miss * 4 + pen * 10 + tw * .0006 + abs(drop) * .1 + jt.get("cheek", 0.0) * 3
                        if best is None or score < best[0]:
                            best = (score, tw, drop, inn, miss, pen)
            AIM_BEST[key] = best
            print("MESHY shouldered %s: bladed %d, butt %.2f down, %.2f in (hands %.3f m off, %.3f m in)" % (
                (key,) + best[1:]))
        CHEEK.pop(key, None)
        _s, tw, drop, inn, _m, _p = AIM_BEST[key]
        CFG.update(aim_twist=tw, aim_drop=drop, aim_in=inn)
        D, joints, P = solve(name, 0.0, HELD0)
        for k in ("aim_twist", "aim_drop", "aim_in"):
            del CFG[k]
        if name in CHEEK:
            print("MESHY cheek on the stock %s: gap %.3f m, %.3f m off the line, head pitch %.2f roll %.2f" % (
                (name,) + CHEEK[name]))
        for side, m in joints["miss"].items():
            if m > .03:
                print("MESHY %s: the %s hand is %.2f m short of its grip" % (name, side, m))
        for side, ang in joints.get("wrist", {}).items():
            WRIST[name + ":" + side] = ang
        return D, P
    D, joints, P = solve(name, 0.0, HELD0)
    # Feet that could not reach the floor where the old ones stood: lower
    # the body by what the lower foot fell short.
    short = min(joints["foot_t_l"].z, joints["foot_t_r"].z)
    got = min(joints["foot_l"].z, joints["foot_r"].z)
    if got - short > .005:
        D, joints, P = solve(name, short - got, HELD0)
    for side, m in joints["miss"].items():
        if m > .03:
            print("MESHY %s: the %s hand is %.2f m short of its grip" % (name, side, m))
    for side, ang in joints.get("wrist", {}).items():
        WRIST[name + ":" + side] = ang
        if ang > 60:
            print("MESHY %s: the %s wrist bends %d degrees" % (name, side, round(ang)))
    if not name.replace("hurt_", "").startswith("die") and "down" not in name:
        COM[name] = joints.get("com", 0.0)
    return D, P


WRIST = {}


HELD0 = dict(pose_key("0")[0])
# Each held thing's rest: its standing-key place carried back onto its hand's
# rest (the hand's rest is the bone's), so posed with the hand it is where
# the standing key put it.
ITEM_REST = {}
for it in ITEMS:
    ITEM_REST[it["bone"]] = HELD0["hand_" + it["main"]].inverted() @ HELD0["@" + it["bone"]]
# A held model's tail bones (kind config "held_model" "tails"): each rests on
# its joint (the held piece's rest, where its own rest puts it), keyed with
# the thing's bone in every key (rigid in the keys; ActorView swings them).
if TAIL_AT and ITEMS:
    _ib = ITEMS[0]["bone"]
    bpy.ops.object.mode_set(mode="OBJECT")
    select([rig])
    bpy.ops.object.mode_set(mode="EDIT")
    _prev = _ib
    for _k, _at in enumerate(TAIL_AT):
        _tn = "%s_t%d" % (_ib, _k + 1)
        eb = data.edit_bones.new(_tn)
        eb.head = ITEM_REST[_ib] @ _at
        eb.tail = eb.head + Vector((0, 0, .08))
        TAILS.append((_tn, _prev, _ib))
        _prev = _tn
    bpy.ops.object.mode_set(mode="POSE")
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
    print("MESHY tail bones:", [t[0] for t in TAILS])
ALL_D = {}
for t in KEYS:
    name = BY_KEY[t]
    D, P = pose_key(name)
    ALL_D[t] = D
    for _tn, _tp, _ib in TAILS:
        D[_tn] = D[_ib]
    for b in BONES + [g for g, _c in GEAR] + [t_[0] for t_ in TAILS]:
        pb = rig.pose.bones[b]
        pb.matrix = D[b] @ data.bones[b].matrix_local
        bpy.context.view_layer.update()
        pb.keyframe_insert("location", frame=t)
        pb.keyframe_insert("rotation_quaternion", frame=t)
        if b in BONES:
            pb.scale = (1, 1, 1)
        pb.keyframe_insert("scale", frame=t)
print("MESHY wrists: worst bend %d degrees" % round(max(WRIST.values()) if WRIST else 0))
if CONTACT:
    _wf = min(CONTACT, key=lambda k: CONTACT[k][0])
    _wg = max(CONTACT, key=lambda k: CONTACT[k][1])
    _ins = sorted({k for k, v in CONTACT.items() if v[2]})
    print("MESHY hand contact: worst %.0f%% of fingers touching (%s), worst gap %.3f m (%s), fingers through: %s" % (
        CONTACT[_wf][0] * 100, _wf, CONTACT[_wg][1], _wg, _ins[:6] or "none"))
if COM:
    _k = max(COM, key=lambda k: abs(COM[k]))
    print("MESHY body's middle over the feet: worst %.3f m (%s; + ahead)" % (COM[_k], _k))
_worst = max(PEN.values()) if PEN else 0.0
print("MESHY held things in the body: worst %.3f m over %d keys" % (_worst, len(KEYS)))
action = rig.animation_data.action
action.name = "poses"


def fcurves(act):
    if hasattr(act, "fcurves") and len(act.fcurves):
        return list(act.fcurves)
    out = []
    for layer in getattr(act, "layers", []):
        for strip in layer.strips:
            for bag in strip.channelbags:
                out.extend(bag.fcurves)
    return out


for fc in fcurves(action):
    for kp in fc.keyframe_points:
        kp.interpolation = "LINEAR"
bpy.ops.object.mode_set(mode="OBJECT")
scene.frame_set(0)

# A boss's gear that can be shot off (kind config "shed": shed.py).
import shed  # noqa: E402
SHED = shed.setup(lo, hi, rig, CFG, ALL_D, KEYS, select)

# ----------------------------------------------- join the gear to the body
lo.data.materials.clear()
mat_body = bpy.data.materials.new("body")
mat_body.use_nodes = True
mat_gear = bpy.data.materials.new("gearslot")
mat_gear.use_nodes = True
lo.data.materials.append(mat_body)
lo.data.materials.append(mat_gear)
# The built hands' faces their own slot (2): their skin is baked from the
# hands themselves, not from the Meshy mesh.
mat_hand = bpy.data.materials.new("handslot")
mat_hand.use_nodes = True
lo.data.materials.append(mat_hand)
_ish = lo.data.attributes.get("is_hand")
if _ish is not None:
    for i, poly in enumerate(lo.data.polygons):
        if _ish.data[i].value == 1:
            poly.material_index = 2
if gear_obj is not None:
    gear_lo = gear_obj.copy()
    gear_lo.data = gear_obj.data.copy()
    scene.collection.objects.link(gear_lo)
    gear_lo.data.materials.clear()
    gear_lo.data.materials.append(mat_body)
    gear_lo.data.materials.append(mat_gear)
    # (A held model's faces their own slot, 3: baked lit from its Meshy
    # model with the body, not copied from the old gear.)
    mat_fish = bpy.data.materials.new("heldmodelslot")
    mat_fish.use_nodes = True
    if HELD_MODEL:
        lo.data.materials.append(mat_fish)
        gear_lo.data.materials.append(mat_hand)
        gear_lo.data.materials.append(mat_fish)
    for p in gear_lo.data.polygons:
        p.material_index = 3 if HELD_MODEL else 1
    for g in list(gear_lo.vertex_groups):
        gear_lo.vertex_groups.remove(g)
    for gi, (gname, _c) in enumerate(GEAR):
        vgp = gear_lo.vertex_groups.new(name=gname)
        ids = [i for i, x in enumerate(vert_gear) if x == gi and (not VERT_TAIL or VERT_TAIL[i] == 0)]
        vgp.add(ids, 1.0, "REPLACE")
    for _k, (_tn, _tp, _ib) in enumerate(TAILS):
        vgp = gear_lo.vertex_groups.new(name=_tn)
        vgp.add([i for i, x in enumerate(VERT_TAIL) if x == _k + 1], 1.0, "REPLACE")
    for b in BONES:
        if b not in gear_lo.vertex_groups:
            gear_lo.vertex_groups.new(name=b)
    for gname in [g for g, _c in GEAR] + [t_[0] for t_ in TAILS]:
        if gname not in lo.vertex_groups:
            lo.vertex_groups.new(name=gname)
    select([lo, gear_lo], lo)
    bpy.ops.object.join()

# ------------------------------------------------------------------ unwrap
select([lo])
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.0)
from bpy_extras import bmesh_utils  # noqa: E402

bm = bmesh.from_edit_mesh(lo.data)
uv = bm.loops.layers.uv.active
deform = bm.verts.layers.deform.active
head_gi = lo.vertex_groups["head"].index
# The hands unwrapped again on their own with a wider angle: at 60 degrees
# a finger falls apart into one-triangle islands a texel or two across,
# whose colour is whatever bleeds in from the next island (dark slivers at
# the finger roots up close).
_hand_gi = {g.index for g in lo.vertex_groups if g.name.startswith(("fl_", "fr_", "hand_"))}
_nh = 0
for f in bm.faces:
    hw = sum(sum(w for k, w in v[deform].items() if k in _hand_gi) for v in f.verts) / len(f.verts)
    f.select = hw > .5
    _nh += f.select
bmesh.update_edit_mesh(lo.data)
if _nh:
    bpy.ops.uv.smart_project(angle_limit=math.radians(float(CFG.get("hand_uv_angle", 85))), island_margin=0.0)
    # (one texel density for all, as one smart project would give)
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.average_islands_scale()
    bm = bmesh.from_edit_mesh(lo.data)
    uv = bm.loops.layers.uv.active
    deform = bm.verts.layers.deform.active
    print("MESHY hand faces unwrapped on their own: %d" % _nh)
# A face seen edge-on by its island's projection gets a UV triangle a texel
# or two across and samples whatever bleeds in (a dark sliver): each such
# face gets its own flat projection at the body's texel density.
_dens = []
for f in bm.faces:
    a3 = f.calc_area()
    if a3 < 1e-10:
        _dens.append(-1.0)
        continue
    us = [l_[uv].uv for l_ in f.loops]
    au = 0.0
    for k_ in range(1, len(us) - 1):
        au += abs((us[k_] - us[0]).cross(us[k_ + 1] - us[0])) / 2
    _dens.append(math.sqrt(au / a3))
_dv = numpy.array(_dens)
_dmed = float(numpy.median(_dv[_dv > 0]))
_fixed = 0
for f, dn in zip(bm.faces, _dens):
    if 0 <= dn < _dmed * float(CFG.get("uv_collapse", .35)):
        n_ = f.normal
        t_ = (f.verts[1].co - f.verts[0].co).normalized()
        b_ = n_.cross(t_)
        o_ = f.loops[0][uv].uv.copy()
        p0 = f.verts[0].co
        for l_ in f.loops:
            d_ = l_.vert.co - p0
            l_[uv].uv = o_ + Vector((d_.dot(t_), d_.dot(b_))) * _dmed
        _fixed += 1
bmesh.update_edit_mesh(lo.data)
print("MESHY faces with collapsed UVs given their own: %d (median density %.3f)" % (_fixed, _dmed))
# (kind config "face_uv" {k, brim_k, r, z}: the face's islands - inside
# radius r of the skull's axis, between z[0] and z[1] over the Meshy Head
# bone (m at 1.73) - take k times the texture's scale and a wide hat's brim
# brim_k: a straw hat's brim took twelve times the face's texels, the eyes
# came out a few texels across)
_fuv = CFG.get("face_uv")
_mw = lo.matrix_world
_nf = 0
for island in bmesh_utils.bmesh_linked_uv_islands(bm, uv):
    heady = sum(1 for f in island for v in f.verts if v[deform].get(head_gi, 0) > .5)
    if heady < len(island):
        continue
    k_isl = HEAD_FAVOUR
    if _fuv:
        _hc = heads["Head"]
        _r = float(_fuv.get("r", .17)) * CHEEK_K
        _z0, _z1 = [_hc.z + float(z_) * CHEEK_K for z_ in _fuv.get("z", [-.04, .17])]
        _in = 0
        for f in island:
            c_ = _mw @ f.calc_center_median()
            if math.hypot(c_.x - _hc.x, c_.y - _hc.y) < _r and _z0 < c_.z < _z1:
                _in += 1
        if _in > len(island) * .5:
            k_isl = float(_fuv.get("k", 2.4))
            _nf += len(island)
        elif _in < len(island) * .2:
            k_isl = float(_fuv.get("brim_k", HEAD_FAVOUR))
    loops = [loop for f in island for loop in f.loops]
    mid = sum((loop[uv].uv for loop in loops), Vector((0.0, 0.0))) / len(loops)
    for loop in loops:
        loop[uv].uv = mid + (loop[uv].uv - mid) * k_isl
if _fuv:
    print("MESHY face islands favoured: %d faces" % _nf)
bmesh.update_edit_mesh(lo.data)
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.select_all(action="SELECT")
bpy.ops.uv.pack_islands(rotate=True, margin_method="FRACTION", margin=GAP, shape_method="CONCAVE")
# A hand island of a face or two is a texel or two across and bakes to
# whatever bleeds in from its neighbours (a dark sliver at a finger root up
# close): its UVs moved onto the middle of the biggest hand island's
# biggest face, so it takes the hands' one skin tone.
bm = bmesh.from_edit_mesh(lo.data)
uv = bm.loops.layers.uv.active
deform = bm.verts.layers.deform.active
_hisl = []
for island in bmesh_utils.bmesh_linked_uv_islands(bm, uv):
    hw = sum(sum(w for k, w in v[deform].items() if k in _hand_gi) for f in island for v in f.verts)
    nvv = sum(len(f.verts) for f in island)
    if nvv and hw / nvv > .5:
        _hisl.append(island)
if _hisl:
    def _uv_area(f):
        us = [l_[uv].uv for l_ in f.loops]
        return sum(abs((us[k_] - us[0]).cross(us[k_ + 1] - us[0])) / 2 for k_ in range(1, len(us) - 1))
    big = max(_hisl, key=len)
    bf = max(big, key=_uv_area)
    spot = sum((l_[uv].uv for l_ in bf.loops), Vector((0.0, 0.0))) / len(bf.loops)
    _moved = 0
    for island in _hisl:
        if len(island) <= int(CFG.get("tiny_island", 3)):
            for f in island:
                for l_ in f.loops:
                    l_[uv].uv = spot.copy()
                _moved += 1
    bmesh.update_edit_mesh(lo.data)
    print("MESHY tiny hand islands moved onto the hand's skin: %d faces (%d hand islands)" % (_moved, len(_hisl)))
bpy.ops.object.mode_set(mode="OBJECT")

# -------------------------------------------------------------------- bake
image = bpy.data.images.new("bake", TEXTURE, TEXTURE, alpha=False)
for m in lo.data.materials:
    node = m.node_tree.nodes.new("ShaderNodeTexImage")
    node.name = "bake_target"
    node.image = image
    m.node_tree.nodes.active = node


def skin_texels(rgb):
    """Kind config "skin_texels" {hue, sat, val} (degrees, shares): the
    texels of a skin that is not a person's (Maw's grey-green), by colour
    alone - the people's skin tests want red over green over blue."""
    st = CFG["skin_texels"]
    mx, mn = rgb.max(axis=1), rgb.min(axis=1)
    d = numpy.maximum(mx - mn, 1e-6)
    sat = numpy.where(mx > 1e-4, (mx - mn) / numpy.maximum(mx, 1e-4), 0)
    r, g, b = rgb[:, 0], rgb[:, 1], rgb[:, 2]
    hue = numpy.where(mx == r, (60 * (g - b) / d) % 360, numpy.where(mx == g, 60 * (b - r) / d + 120, 60 * (r - g) / d + 240))
    h0, h1 = st.get("hue", [60, 140])
    s0, s1 = st.get("sat", [.06, .45])
    v0, v1 = st.get("val", [.15, .95])
    return (hue >= h0) & (hue <= h1) & (sat >= s0) & (sat <= s1) & (mx >= v0) & (mx <= v1)


def bake_op(**kw):
    sc = bpy.context.scene
    try:
        bpy.ops.object.bake(**kw)
    except RuntimeError as err:
        if sc.cycles.device != "GPU":
            raise
        print("MESHY BAKE: graphics card failed (%s); on the processor" % str(err).strip())
        sc.cycles.device = "CPU"
        bpy.ops.object.bake(**kw)


def pixels(img):
    px = numpy.empty(len(img.pixels), dtype=numpy.float32)
    img.pixels.foreach_get(px)
    return px.reshape(-1, 4)


# Object-space normals of each texel.
nimg = bpy.data.images.new("normals", TEXTURE, TEXTURE, alpha=False, float_buffer=True)
nimg.colorspace_settings.name = "Non-Color"
for m in lo.data.materials:
    m.node_tree.nodes["bake_target"].image = nimg
scene.cycles.samples = 1
select([lo])
bake_op(type="NORMAL", normal_space="OBJECT", margin=TEXTURE // 128, use_clear=True)
NORMALS = pixels(nimg)

# Where skin can be (head, hands, forearms; a kind may add zones): a vertex
# colour of those bones' weights, baked as emission.
ZONES = CFG.get("skin_zones", ["head", "hand_l", "hand_r", "forearm_l", "forearm_r"])
ZONES = ZONES + [g.name for g in lo.vertex_groups if g.name.startswith(("fl_", "fr_"))]
zattr = lo.data.color_attributes.new("zone", "FLOAT_COLOR", "POINT")
zidx = [lo.vertex_groups[z].index for z in ZONES if z in lo.vertex_groups]
# (blue: the face's front - inside the skull's radius, between the jaw and
# the brow, ahead of the ears; kind config "face_box" {r, z, back} as
# face_uv's, at 1.73 m)
_fb = CFG.get("face_box", {})
_fbr = float(_fb.get("r", .17)) * CHEEK_K
_fbz = [heads["Head"].z + float(z_) * CHEEK_K for z_ in _fb.get("z", [-.16, .16])]
_fby = heads["Head"].y + float(_fb.get("back", -.025)) * CHEEK_K
for v in lo.data.vertices:
    zv = sum(g.weight for g in v.groups if g.group in zidx)
    hv = sum(g.weight for g in v.groups if g.group == lo.vertex_groups["head"].index)
    w_ = lo.matrix_world @ v.co
    # (and the neck all round, down to the collar: blotched as the face)
    _rr = math.hypot(w_.x - heads["Head"].x, w_.y - heads["Head"].y)
    fv = float((hv > .5 and _rr < _fbr and _fbz[0] < w_.z < _fbz[1] and w_.y < _fby)
               or (_rr < .12 * CHEEK_K and _fbz[0] < w_.z < heads["Head"].z))
    if not fv and hv > .5 and _rr < _fbr and _fbz[0] < w_.z < heads["Head"].z + float(_fb.get("back_top", .08)) * CHEEK_K:
        fv = .5  # (behind the ears, under the hair: skin only, not the hair)
    zattr.data[v.index].color = (zv, hv, fv, 1)
saved_trees = {}
for m in lo.data.materials:
    nt = m.node_tree
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    e = nt.nodes.new("ShaderNodeEmission")
    vc = nt.nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "zone"
    nt.links.new(vc.outputs[0], e.inputs[0])
    nt.links.new(e.outputs[0], o.inputs[0])
    o.is_active_output = True
    saved_trees[m.name] = (o, e, vc)
zimg = bpy.data.images.new("zone", TEXTURE, TEXTURE, alpha=False, float_buffer=True)
zimg.colorspace_settings.name = "Non-Color"
for m in lo.data.materials:
    m.node_tree.nodes["bake_target"].image = zimg
    m.node_tree.nodes.active = m.node_tree.nodes["bake_target"]
select([lo])
bake_op(type="EMIT", margin=TEXTURE // 128, use_clear=True)
_zp = pixels(zimg)
ZONE = _zp[:, 0] > .5
HEADZONE = _zp[:, 1] > .5
FACEZONE = _zp[:, 2] > .75
BACKZONE = (_zp[:, 2] > .25) & ~FACEZONE
for m in lo.data.materials:
    for n in saved_trees[m.name]:
        m.node_tree.nodes.remove(n)
    m.node_tree.nodes["bake_target"].image = image
for m in lo.data.materials:
    m.node_tree.nodes["bake_target"].image = image

# The body: Meshy's look lit by the dusk stage, four turns. The low mesh
# (and the gear's source) casts nothing on the Meshy mesh it is baked from.
for o in (lo,):
    o.visible_shadow = False
    o.visible_diffuse = False
    o.visible_glossy = False
    o.visible_transmission = False
    o.visible_volume_scatter = False
if gear_obj is not None:
    gear_obj.hide_render = True
if FISH_HI is not None:
    # (the held model lights as the body does but casts nothing on it)
    FISH_HI.visible_shadow = False
total = None
weight = None
# (kind config "bake_ray": [cage, max ray] as shares of the height; a face
# mask's bars standing a few cm off the face were baked onto the face as
# grey stripes with the default reach)
BAKE_RAY = [float(v) for v in CFG.get("bake_ray", [.012, .05])]
NOSHADOW = None
nx = NORMALS[:, 0] * 2 - 1
ny = NORMALS[:, 1] * 2 - 1
kept = [hi.matrix_world.copy(), lo.matrix_world.copy()]
for k, angle in enumerate(TURNS):
    spin = Matrix.Rotation(math.radians(angle), 4, "Z")
    hi.matrix_world = spin @ kept[0]
    lo.matrix_world = spin @ kept[1]
    if FISH_HI is not None:
        FISH_HI.matrix_world = spin
    bpy.context.view_layer.update()
    scene.cycles.samples = 32 if k == 0 else 20
    select([hi, lo] + ([FISH_HI] if FISH_HI is not None else []), lo)
    bake_op(type="COMBINED", pass_filter={"EMIT", "DIRECT", "INDIRECT", "DIFFUSE"},
            margin=TEXTURE // 128, use_clear=True, use_selected_to_active=True,
            cage_extrusion=OLD_H * BAKE_RAY[0], max_ray_distance=OLD_H * BAKE_RAY[1])
    px = pixels(image)
    c, sn = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    toward = -(sn * nx + c * ny)
    hit = px[:, :3].sum(axis=1) > .003
    w = (numpy.clip(toward, 0, 1) ** 2 + 1e-4) * hit
    if CFG.get("head_noshadow"):
        # (the same turn baked with the Meshy mesh casting no shadow on
        # itself: kept for the head - a helmet's brim and face-mask bars
        # threw hard shadows over the face; Meshy's own painted shading
        # and the light's turn over the face stay)
        hi.visible_shadow = False
        bake_op(type="COMBINED", pass_filter={"EMIT", "DIRECT", "INDIRECT", "DIFFUSE"},
                margin=TEXTURE // 128, use_clear=True, use_selected_to_active=True,
                cage_extrusion=OLD_H * BAKE_RAY[0], max_ray_distance=OLD_H * BAKE_RAY[1])
        hi.visible_shadow = True
        pxn = pixels(image)
        if NOSHADOW is None:
            NOSHADOW = pxn[:, :3] * w[:, None]
        else:
            NOSHADOW += pxn[:, :3] * w[:, None]
    if total is None:
        total = px.copy()
        total[:, :3] *= w[:, None]
        weight = w.copy()
    else:
        total[:, :3] += px[:, :3] * w[:, None]
        weight += w
hi.matrix_world, lo.matrix_world = kept
if FISH_HI is not None:
    FISH_HI.matrix_world = Matrix.Identity(4)
bpy.context.view_layer.update()
# (kind config "face_albedo": Meshy's own unlit colour, for a face shadowed
# by a helmet and its face mask in the lit bake - see face_lift)
ALBEDO = None
if CFG.get("face_albedo") or CFG.get("face_clean"):
    scene.cycles.samples = 8
    select([hi, lo], lo)
    bake_op(type="DIFFUSE", pass_filter={"COLOR"}, margin=TEXTURE // 128, use_clear=True,
            use_selected_to_active=True, cage_extrusion=OLD_H * BAKE_RAY[0], max_ray_distance=OLD_H * BAKE_RAY[1])
    ALBEDO = pixels(image)[:, :3].copy()
found = weight > 0
total[found, :3] /= weight[found, None]
if NOSHADOW is not None:
    NOSHADOW[found] /= weight[found, None]
    total[HEADZONE & found, :3] = NOSHADOW[HEADZONE & found]
    print("MESHY head baked without self-shadow: %d texels" % int((HEADZONE & found).sum()))
inside = NORMALS[:, :3].sum(axis=1) > .05
print("MESHY BAKE: %d of %d texels on the body unreached" % (int((inside & ~found).sum()), int(inside.sum())))
# Fill unreached texels from neighbours.
rgb = total[:, :3].reshape(TEXTURE, TEXTURE, 3)
good = found.reshape(TEXTURE, TEXTURE).copy()
missing = (inside & ~found).reshape(TEXTURE, TEXTURE)
for _ in range(24):
    if not missing.any():
        break
    acc = numpy.zeros_like(rgb)
    cnt = numpy.zeros((TEXTURE, TEXTURE), dtype=numpy.float32)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
        g = numpy.roll(numpy.roll(good, dy, 0), dx, 1)
        acc += numpy.roll(numpy.roll(rgb, dy, 0), dx, 1) * g[:, :, None]
        cnt += g
    take = missing & (cnt > 0)
    rgb[take] = acc[take] / cnt[take][:, None]
    good |= take
    missing &= ~take
total[:, :3] = rgb.reshape(-1, 3)
total[:, 3] = 1

# The built hands: their skin (the Meshy hand's colour, nails lighter, the
# creases at the knuckles darker) lit by the stage, four turns as the body.
if HANDS:
    hi.hide_render = True
    if FISH_HI is not None:
        FISH_HI.hide_render = True
    lo.visible_shadow = True
    lo.visible_diffuse = True
    for m in lo.data.materials:
        nt = m.node_tree
        for nn in list(nt.nodes):
            if nn.name != "bake_target":
                nt.nodes.remove(nn)
        o = nt.nodes.new("ShaderNodeOutputMaterial")
        if m is mat_hand and "handuv" in lo.data.uv_layers and CFG.get("hands_paint", "flat") == "texture":
            # The sculpted hand's own painted skin (its UVs), lit.
            bs = nt.nodes.new("ShaderNodeBsdfDiffuse")
            tx = nt.nodes.new("ShaderNodeTexImage")
            tx.image = bpy.data.images.load(os.path.join(hands.MASTER, "hand_master.png"), check_existing=True)
            uvn = nt.nodes.new("ShaderNodeUVMap")
            uvn.uv_map = "handuv"
            nt.links.new(uvn.outputs[0], tx.inputs[0])
            # Recoloured to this body's own hand colour (the master's painted
            # detail kept): times the body's skin over the master's mean.
            _mpx = numpy.array(tx.image.pixels[:]).reshape(-1, 4)[:, :3]
            _mmean = numpy.median(_mpx[_mpx.sum(axis=1) > .15], axis=0)
            _k = numpy.clip(SKIN / numpy.maximum(_mmean, 1e-3), .2, 3.0)
            mixc = nt.nodes.new("ShaderNodeMix")
            mixc.data_type = "RGBA"
            mixc.blend_type = "MULTIPLY"
            mixc.inputs[0].default_value = 1.0
            mixc.inputs[7].default_value = (float(_k[0]), float(_k[1]), float(_k[2]), 1)
            nt.links.new(tx.outputs[0], mixc.inputs[6])
            nt.links.new(mixc.outputs[2], bs.inputs[0])
            nt.links.new(bs.outputs[0], o.inputs[0])
        elif m is mat_hand and "shade" not in lo.data.color_attributes:
            # One clean skin tone, lit by the stage (its shading and the
            # creases' shadow from the bake itself); matched to the forearm
            # after (hand_match).
            bs = nt.nodes.new("ShaderNodeBsdfDiffuse")
            bs.inputs[0].default_value = (float(SKIN[0]), float(SKIN[1]), float(SKIN[2]), 1)
            nt.links.new(bs.outputs[0], o.inputs[0])
        elif m is mat_hand:
            bs = nt.nodes.new("ShaderNodeBsdfDiffuse")
            vc = nt.nodes.new("ShaderNodeVertexColor")
            vc.layer_name = "shade"
            mixn = nt.nodes.new("ShaderNodeMix")
            mixn.data_type = "RGBA"
            mixn.blend_type = "MULTIPLY"
            mixn.inputs[0].default_value = 1.0
            mixn.inputs[6].default_value = (float(SKIN[0]), float(SKIN[1]), float(SKIN[2]), 1)
            nt.links.new(vc.outputs[0], mixn.inputs[7])
            nt.links.new(mixn.outputs[2], bs.inputs[0])
            nt.links.new(bs.outputs[0], o.inputs[0])
        else:
            e = nt.nodes.new("ShaderNodeEmission")
            e.inputs[0].default_value = (0, 0, 0, 1)
            nt.links.new(e.outputs[0], o.inputs[0])
        nt.nodes["bake_target"].image = image
        nt.nodes.active = nt.nodes["bake_target"]
    htot = None
    hwt = None
    kept_lo = lo.matrix_world.copy()
    for k, angle in enumerate(TURNS):
        lo.matrix_world = Matrix.Rotation(math.radians(angle), 4, "Z") @ kept_lo
        bpy.context.view_layer.update()
        scene.cycles.samples = 24
        select([lo])
        bake_op(type="COMBINED", pass_filter={"EMIT", "DIRECT", "INDIRECT", "DIFFUSE"},
                margin=TEXTURE // 128, use_clear=True)
        px = pixels(image)
        c, sn = math.cos(math.radians(angle)), math.sin(math.radians(angle))
        w = numpy.clip(-(sn * nx + c * ny), 0, 1) ** 2 + 1e-4
        if htot is None:
            htot = px[:, :3] * w[:, None]
            hwt = w.copy()
        else:
            htot += px[:, :3] * w[:, None]
            hwt += w
    lo.matrix_world = kept_lo
    bpy.context.view_layer.update()
    htot /= hwt[:, None]
    # Which texels are the hands': their slot emits white.
    for m in lo.data.materials:
        nt = m.node_tree
        for nn in list(nt.nodes):
            if nn.name != "bake_target":
                nt.nodes.remove(nn)
        o = nt.nodes.new("ShaderNodeOutputMaterial")
        e = nt.nodes.new("ShaderNodeEmission")
        val = 1.0 if m is mat_hand else 0.0
        e.inputs[0].default_value = (val, val, val, 1)
        nt.links.new(e.outputs[0], o.inputs[0])
    select([lo])
    bake_op(type="EMIT", margin=TEXTURE // 128, use_clear=True)
    HANDMASK = pixels(image)[:, 0] > .5
    # The same skin as the arms and face beside them: the hands' light and
    # colour matched to the skin baked on the rest of the body (its median).
    _rgb = total[:, :3]
    _mx, _mn = _rgb.max(axis=1), _rgb.min(axis=1)
    _sat = numpy.where(_mx > 1e-4, (_mx - _mn) / numpy.maximum(_mx, 1e-4), 0)
    _skinlike = ZONE & ~HANDMASK & (_rgb[:, 0] > _rgb[:, 1]) & (_rgb[:, 1] > _rgb[:, 2] * .9) & (_sat > .18) & (_sat < .7) & (_mx > .15)
    # (kind config "hand_hue" [lo, hi] degrees: only skin of that hue - a
    # yellow hard hat and a ginger beard in the head zone made the hands
    # yellow)
    if CFG.get("hand_hue"):
        _d = numpy.maximum(_mx - _mn, 1e-6)
        _hue = (60 * ((_rgb[:, 1] - _rgb[:, 2]) / _d)) % 360
        _skinlike &= (_hue >= float(CFG["hand_hue"][0])) & (_hue <= float(CFG["hand_hue"][1]))
    if CFG.get("skin_texels"):
        _skinlike = ~HANDMASK & skin_texels(_rgb)
    if _skinlike.sum() > 50 and HANDMASK.any():
        _want = numpy.median(_rgb[_skinlike], axis=0)
        _have = numpy.median(htot[HANDMASK], axis=0)
        htot = numpy.clip(htot * (_want / numpy.maximum(_have, 1e-4))[None, :], 0, 1)
        print("MESHY hands' skin matched to the body's", numpy.round(_want * 255).astype(int))
    total[HANDMASK, :3] = htot[HANDMASK]
    # (the baked hand's own light, creases and knuckles - the skin passes
    # after flatten its lit half; gloves() shades a glove from this)
    globals()["HAND_SHADE"] = htot[:, :3] @ numpy.array([.299, .587, .114])
    print("MESHY hands baked: %d texels, mean colour %s" % (int(HANDMASK.sum()),
          numpy.round(htot[HANDMASK].mean(axis=0) * 255).astype(int) if HANDMASK.any() else "-"))
    hi.hide_render = False
    if FISH_HI is not None:
        FISH_HI.hide_render = False
    lo.visible_shadow = False
    lo.visible_diffuse = False


def skin_fix(px):
    """Skin the grade and the palette would turn yellow-orange (Meshy paints
    it at hue 20-35, which digitize() maps onto the palette's tans and
    ochres) is turned toward red before the grade, so it lands on the
    palette's ruddy salmons: in the skin zones only, hue 5-45, not grey."""
    fix = CFG.get("skin_fix", [26, .85, .92])
    if not fix:
        return px
    rgbv = px[:, :3]
    mx = rgbv.max(axis=1)
    mn = rgbv.min(axis=1)
    d = numpy.maximum(mx - mn, 1e-6)
    sat = numpy.where(mx > 1e-4, (mx - mn) / numpy.maximum(mx, 1e-4), 0)
    r, g, b = rgbv[:, 0], rgbv[:, 1], rgbv[:, 2]
    h = numpy.where(mx == r, (60 * ((g - b) / d)) % 360,
                    numpy.where(mx == g, 60 * ((b - r) / d) + 120, 60 * ((r - g) / d) + 240))
    band = ZONE & (h > 5) & (h < 45) & (sat > .18) & (sat < .8) & (mx > .14)
    # Only the colours of this body's own skin (its Meshy hands' colour, lit
    # as the bake lights it): a khaki sleeve or a tan shirt in the same hue
    # band is cloth, not skin.
    sk = SKIN * GAIN
    smx, smn = float(sk.max()), float(sk.min())
    sd = max(smx - smn, 1e-6)
    s_sat = (smx - smn) / max(smx, 1e-4)
    if smx == sk[0]:
        s_h = (60 * ((sk[1] - sk[2]) / sd)) % 360
    elif smx == sk[1]:
        s_h = 60 * ((sk[2] - sk[0]) / sd) + 120
    else:
        s_h = 60 * ((sk[0] - sk[1]) / sd) + 240
    near_h = numpy.abs(((h - s_h + 180) % 360) - 180) < float(CFG.get("skin_hue_band", 9))
    near_s = numpy.abs(sat - s_sat) < float(CFG.get("skin_sat_band", .16))
    band &= near_h & near_s
    nh = (h - fix[0]) % 360
    ns = numpy.clip(sat * fix[1], 0, 1)
    nv = mx * fix[2]
    c = nv * ns
    hp = nh / 60.0
    x = c * (1 - numpy.abs(hp % 2 - 1))
    z = numpy.zeros_like(c)
    out = numpy.zeros_like(rgbv)
    for m, (a1, a2, a3) in ((hp < 1, (c, x, z)), ((hp >= 1) & (hp < 2), (x, c, z)), ((hp >= 2) & (hp < 3), (z, c, x)),
                            ((hp >= 3) & (hp < 4), (z, x, c)), ((hp >= 4) & (hp < 5), (x, z, c)), (hp >= 5, (c, z, x))):
        out[m, 0], out[m, 1], out[m, 2] = a1[m], a2[m], a3[m]
    out += (nv - c)[:, None]
    px = px.copy()
    px[band, :3] = out[band]
    print("MESHY skin fix on %d texels (%d in the zones)" % (int(band.sum()), int(ZONE.sum())))
    return px


# As bright as the old look once graded (photo_grade is about 1.18 x + .024
# on the light): the Meshy bakes came out a fifth brighter than the old ones.
try:
    _oi = bpy.data.images.load(CFG["old_tex"])
    _oi.colorspace_settings.name = "sRGB"
    _old = pixels(_oi)[:, :3]
    _old = _old[_old.sum(axis=1) > .06]
    _l_old = float((_old @ numpy.array([.299, .587, .114])).mean())
except Exception:
    _old = None
if _old is not None and CFG.get("gain", "auto") == "auto":
    _body = inside & found
    _l_new = float((total[_body, :3] @ numpy.array([.299, .587, .114])).mean())
    GAIN = float(numpy.clip(((_l_old - .024) / 1.18) / max(_l_new, 1e-3), .6, 1.4))
else:
    GAIN = float(CFG.get("gain", 1.0)) if CFG.get("gain", "auto") != "auto" else 1.0
# Halfway there in light (the Meshy look's grime reads darker than its mean),
# and a little more colour (the cels' plaid and denim are bold).
GAIN = GAIN ** float(CFG.get("gain_share", .6))
GAIN *= float(CFG.get("light", 1.0))
total[:, :3] *= GAIN
_grey = total[:, :3].mean(axis=1, keepdims=True)
total[:, :3] = numpy.clip(_grey + (total[:, :3] - _grey) * float(CFG.get("colour", 1.2)), 0, 1)
print("MESHY gain %.3f to the old look's light" % GAIN)
def blush_down(px):
    """Meshy paints cheeks and noses a saturated pink-red; at the palette it
    reads as clown blush. In the skin zones, reds much more saturated than
    this body's own skin are eased toward a sunburnt ruddiness (a share of
    their excess saturation kept, the hue pulled a little toward the skin)."""
    keep = float(CFG.get("blush_keep", .35))
    rgbv = px[:, :3]
    mx = rgbv.max(axis=1)
    mn = rgbv.min(axis=1)
    sat = numpy.where(mx > 1e-4, (mx - mn) / numpy.maximum(mx, 1e-4), 0)
    r, g, b = rgbv[:, 0], rgbv[:, 1], rgbv[:, 2]
    d = numpy.maximum(mx - mn, 1e-6)
    h = numpy.where(mx == r, (60 * ((g - b) / d)) % 360,
                    numpy.where(mx == g, 60 * ((b - r) / d) + 120, 60 * ((r - g) / d) + 240))
    sk = SKIN * GAIN
    s_sat = float((sk.max() - sk.min()) / max(sk.max(), 1e-4))
    reddish = ((h < 22) | (h > 330)) & (mx > .15)
    band = ZONE & reddish & (sat > s_sat + .08)
    grey = rgbv.mean(axis=1, keepdims=True)
    target = s_sat + (sat - s_sat) * keep
    k = numpy.where(sat > 1e-4, target / numpy.maximum(sat, 1e-4), 1.0)[:, None]
    toned = grey + (rgbv - grey) * k
    # (a touch toward the skin's own colour, at its light)
    skin_at = sk / max(float(sk.mean()), 1e-4) * grey
    toned = toned * .8 + skin_at * .2
    px = px.copy()
    px[band, :3] = numpy.clip(toned[band], 0, 1)
    print("MESHY blush eased on %d texels" % int(band.sum()))
    return px


def face_lift(px):
    """The face as light as the body's other skin (the hat brim and the dusk
    key from above leave a Meshy face in shadow; the cels lit faces): the head
    zone's skin texels scaled so their median light is the forearms' and
    hands' skin's, at most `face_lift_most` times."""
    rgbv = px[:, :3]
    lum = rgbv @ numpy.array([.299, .587, .114])
    mx = rgbv.max(axis=1)
    mn = rgbv.min(axis=1)
    sat = numpy.where(mx > 1e-4, (mx - mn) / numpy.maximum(mx, 1e-4), 0)
    skinlike = (rgbv[:, 0] > rgbv[:, 2]) & (sat > .12) & (sat < .75) & (mx > .03)
    d = numpy.maximum(mx - mn, 1e-6)
    r, g, b = rgbv[:, 0], rgbv[:, 1], rgbv[:, 2]
    h = numpy.where(mx == r, (60 * ((g - b) / d)) % 360,
                    numpy.where(mx == g, 60 * ((b - r) / d) + 120, 60 * ((r - g) / d) + 240))
    sk = SKIN
    sd = max(float(sk.max() - sk.min()), 1e-6)
    s_h = (60 * ((sk[1] - sk[2]) / sd)) % 360 if sk.max() == sk[0] else 30.0
    skinlike &= numpy.abs(((h - s_h + 180) % 360) - 180) < 14
    face = HEADZONE & skinlike
    rest = ZONE & ~HEADZONE & skinlike
    if "HANDMASK" in globals():
        rest = rest | (HANDMASK & skinlike)
    print("MESHY face check: %d face texels, %d other skin texels" % (int(face.sum()), int(rest.sum())))
    if face.sum() < 50 or rest.sum() < 50:
        return px
    want = float(numpy.median(lum[rest])) * float(CFG.get("face_light", 1.05))
    have = float(numpy.median(lum[face]))
    # As light as the old model's skin (the cels' faces), graded back.
    if _old is not None:
        o = _old
        omx, omn = o.max(axis=1), o.min(axis=1)
        osat = numpy.where(omx > 1e-4, (omx - omn) / numpy.maximum(omx, 1e-4), 0)
        oskin = (o[:, 0] > o[:, 1]) & (o[:, 1] > o[:, 2]) & (osat > .2) & (osat < .6) & (omx > .35)
        if oskin.sum() > 50:
            old_l = float(numpy.median(o[oskin] @ numpy.array([.299, .587, .114])))
            want = max(want, (old_l - .024) / 1.18 * float(CFG.get("face_light", 1.0)))
    # (kind config "face_albedo": share - the face's skin rebuilt from
    # Meshy's unlit colour at the wanted light, shaded only softly by its
    # baked light: a helmet's brim and face-mask bars threw hard shadows
    # across the face, which went grey-lilac under the fill light and kept
    # out of the lift as not skin-coloured)
    if CFG.get("face_albedo") and ALBEDO is not None:
        a = ALBEDO
        amx, amn = a.max(axis=1), a.min(axis=1)
        asat = numpy.where(amx > 1e-4, (amx - amn) / numpy.maximum(amx, 1e-4), 0)
        ad = numpy.maximum(amx - amn, 1e-6)
        ah = numpy.where(amx == a[:, 0], (60 * ((a[:, 1] - a[:, 2]) / ad)) % 360,
                         numpy.where(amx == a[:, 1], 60 * ((a[:, 2] - a[:, 0]) / ad) + 120, 60 * ((a[:, 0] - a[:, 1]) / ad) + 240))
        s_ref = float(numpy.median(asat[HEADZONE & (asat > .12) & (asat < .8) & (a[:, 0] > a[:, 2])])) if (HEADZONE & (asat > .12)).sum() > 50 else .3
        fm = HEADZONE & (a[:, 0] > a[:, 2]) & (asat > float(CFG.get("face_albedo_sat", .12))) & (asat < .8) & (amx > .12) & (
            numpy.abs(((ah - s_h + 180) % 360) - 180) < float(CFG.get("face_albedo_hue", 22)))
        if "HANDMASK" in globals():
            fm &= ~HANDMASK
        if fm.sum() > 50:
            alum = a @ numpy.array([.299, .587, .114])
            fm &= alum > float(numpy.median(alum[fm])) * .5
            # (teeth and eye whites: light and nearly grey - they stay)
            fm &= ~((asat < .14) & (alum > float(numpy.median(alum[fm])) * 1.12))
            L = lum.copy().reshape(TEXTURE, TEXTURE)
            m2 = fm.reshape(TEXTURE, TEXTURE)
            for _ in range(6):
                acc = numpy.zeros_like(L)
                cnt = numpy.zeros_like(L)
                for dy, dx in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
                    mm = numpy.roll(numpy.roll(m2, dy, 0), dx, 1)
                    acc += numpy.roll(numpy.roll(L, dy, 0), dx, 1) * mm
                    cnt += mm
                L[m2] = (acc / numpy.maximum(cnt, 1))[m2]
            L = L.reshape(-1)
            r = numpy.clip(L / max(float(numpy.median(L[fm])), 1e-4), float(CFG.get("face_albedo_shade", .82)), 1.12)
            kf = want / max(float(numpy.median(alum[fm])), 1e-4)
            gk = float(CFG["face_albedo"])
            px = px.copy()
            newc = numpy.clip(a[fm] * kf * r[fm, None], 0, 1)
            # (a stubbled jaw's greyish albedo brought up to most of the
            # skin's colour: grey skin dithers into grey blotches)
            ng = newc.mean(axis=1, keepdims=True)
            nsat = asat[fm][:, None]
            want_s = s_ref * .75
            newc = numpy.clip(ng + (newc - ng) * numpy.maximum(1.0, want_s / numpy.maximum(nsat, .03)), 0, 1)
            px[fm, :3] = px[fm, :3] * (1 - gk) + newc * gk
            rgbv = px[:, :3]
            lum = rgbv @ numpy.array([.299, .587, .114])
            face = face | fm
            have = float(numpy.median(lum[face]))
            print("MESHY face from the albedo: %d texels (light x%.2f)" % (int(fm.sum()), kf))
    skin_all = face | rest
    # (not hair or a beard: a texel much darker than the skin's middle stays)
    skin_all &= lum > float(numpy.median(lum[skin_all])) * .6
    if "HANDMASK" in globals():
        skin_all = skin_all & ~HANDMASK
    k = min(float(CFG.get("face_lift_most", 1.8)), max(1.0, want / max(have, 1e-4)))
    print("MESHY face light %.3f, other skin %.3f; face colour %s" % (have, want, numpy.round(numpy.median(px[face, :3], axis=0) * 255).astype(int)))
    if k > 1.02:
        px = px.copy()
        # (every skin texel, face, hands and arms alike; the hat and cloth stay)
        px[skin_all, :3] = numpy.clip(px[skin_all, :3] * k, 0, 1)
        print("MESHY face lifted x%.2f (face %.3f, other skin %.3f)" % (k, have, want))
    # The lift makes Meshy's skin grain (light hairs, pores) loud: smoothed a
    # little within the skin.
    rgbn = px[:, :3]
    lumn = rgbn @ numpy.array([.299, .587, .114])
    lm = float(numpy.median(lumn[skin_all]))
    hot = skin_all & (lumn > lm * 1.3)
    rgbn[hot] = rgbn[hot] * ((lm * 1.3) / numpy.maximum(lumn[hot], 1e-4))[:, None]
    # (kind config "face_greys": share - grey texels in among the face's
    # skin (Meshy's stubble and grime under a helmet: not skin-coloured
    # enough to be lifted) dither into grey blotches beside the lifted skin;
    # they take the lifted skin's colour at their own light, that share)
    if CFG.get("face_greys"):
        gk = float(CFG["face_greys"])
        m2 = skin_all.reshape(TEXTURE, TEXTURE)
        dil = m2.copy()
        for _ in range(4):
            dil = dil | numpy.roll(dil, 1, 0) | numpy.roll(dil, -1, 0) | numpy.roll(dil, 1, 1) | numpy.roll(dil, -1, 1)
        mxn, mnn = rgbn.max(axis=1), rgbn.min(axis=1)
        satn = numpy.where(mxn > 1e-4, (mxn - mnn) / numpy.maximum(mxn, 1e-4), 0)
        cand = HEADZONE & ~skin_all & dil.reshape(-1) & (satn < .16) & (lumn > lm * .3) & (lumn < lm * 1.25)
        if "HANDMASK" in globals():
            cand &= ~HANDMASK
        if cand.sum() > 10:
            sc = numpy.median(rgbn[skin_all], axis=0)
            scl = max(float(sc @ numpy.array([.299, .587, .114])), 1e-4)
            new = sc[None, :] * (numpy.minimum(lumn[cand] * max(k, 1.0), lm * 1.15) / scl)[:, None]
            rgbn[cand] = numpy.clip(rgbn[cand] * (1 - gk) + new * gk, 0, 1)
            skin_all = skin_all | cand
            print("MESHY face greys: %d texels toward the skin" % int(cand.sum()))
    smooth_in(px, skin_all, 3)
    SKIN_DONE[:] = skin_all
    return px


def smooth_in(px, mask, passes):
    img = px[:, :3].reshape(TEXTURE, TEXTURE, 3)
    m2 = mask.reshape(TEXTURE, TEXTURE)
    for _ in range(passes):
        acc = numpy.zeros_like(img)
        cnt = numpy.zeros((TEXTURE, TEXTURE, 1))
        for dy, dx in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
            mm = numpy.roll(numpy.roll(m2, dy, 0), dx, 1)[:, :, None]
            acc += numpy.roll(numpy.roll(img, dy, 0), dx, 1) * mm
            cnt += mm
        sm = acc / numpy.maximum(cnt, 1)
        img[m2] = sm[m2]
    px[:, :3] = img.reshape(-1, 3)


SKIN_DONE = numpy.zeros(TEXTURE * TEXTURE, dtype=bool)


def hand_match(px):
    """The built hands' skin made the body's own: the speckle of the master
    hand's paint smoothed out (texels far from the hand's median pulled in,
    then a few passes of neighbour averaging within the hands), then its light
    and colour matched channel by channel to the body's other skin (face and
    forearms) as it now is."""
    if "HANDMASK" not in globals() or not HANDMASK.any():
        return px
    px = px.copy()
    hm = HANDMASK
    med = numpy.median(px[hm, :3], axis=0)
    rgb = px[:, :3]
    lum = rgb @ numpy.array([.299, .587, .114])
    mlum = float(med @ numpy.array([.299, .587, .114]))
    over = hm & (lum > mlum * 1.25)
    rgb[over] = rgb[over] * ((mlum * 1.25) / numpy.maximum(lum[over], 1e-4))[:, None]
    img = rgb.reshape(TEXTURE, TEXTURE, 3)
    m2 = hm.reshape(TEXTURE, TEXTURE)
    # (one pass: three blurred the creases and knuckles away, flat paper
    # hands up close - the revenue man's; kind config "hand_smooth")
    for _ in range(int(CFG.get("hand_smooth", 1))):
        acc = numpy.zeros_like(img)
        cnt = numpy.zeros((TEXTURE, TEXTURE, 1))
        for dy, dx in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
            mm = numpy.roll(numpy.roll(m2, dy, 0), dx, 1)[:, :, None]
            acc += numpy.roll(numpy.roll(img, dy, 0), dx, 1) * mm
            cnt += mm
        sm = acc / numpy.maximum(cnt, 1)
        img[m2] = sm[m2]
    rgb = img.reshape(-1, 3)
    mx, mn = rgb.max(axis=1), rgb.min(axis=1)
    sat = numpy.where(mx > 1e-4, (mx - mn) / numpy.maximum(mx, 1e-4), 0)
    other = SKIN_DONE & ~hm & ~HEADZONE
    if other.sum() < 50:
        other = SKIN_DONE & ~hm
    if other.sum() < 50:
        other = ZONE & ~hm & (rgb[:, 0] >= rgb[:, 2]) & (sat > .08) & (sat < .75) & (mx > .05)
    # (the skin proper: its colourful, lit texels, not hair, grime or shade)
    lum2 = rgb @ numpy.array([.299, .587, .114])
    sel = other & (sat > .25)
    if sel.sum() > 50:
        sel &= lum2 >= numpy.percentile(lum2[sel], 40)
        other = sel
    # (Sleeves down to the wrist: the "forearm" is cloth, not skin; then the
    # face's skin is the hands' match.)
    head_sk = SKIN_DONE & HEADZONE & (sat > .2)
    if CFG.get("skin_texels"):
        other = ~hm & skin_texels(rgb)
        head_sk = other[:0]
    if head_sk.sum() > 50 and other.sum() > 50:
        def _hue(c):
            import colorsys
            return colorsys.rgb_to_hsv(*[float(x) for x in c])[0] * 360
        hf = _hue(numpy.median(rgb[other], axis=0))
        hh = _hue(numpy.median(rgb[head_sk], axis=0))
        if abs(((hf - hh + 180) % 360) - 180) > 10:
            print("MESHY hands: the forearms are sleeved (hue %d vs face %d): matched to the face" % (hf, hh))
            other = head_sk & (lum2 >= numpy.percentile(lum2[head_sk], 40))
    if other.sum() > 50:
        want = numpy.median(rgb[other], axis=0)
        hsel = hm & (lum2 >= numpy.percentile(lum2[hm], 40))
        have = numpy.median(rgb[hsel], axis=0)
        rgb[hm] = numpy.clip(rgb[hm] * (want / numpy.maximum(have, 1e-4))[None, :], 0, 1)
        # The hands take only that one tone, shaded by their own light: no
        # hot red or orange texel (blush, bake noise) left on a knuckle.
        wl = float(want @ numpy.array([.299, .587, .114]))
        hl = rgb[hm] @ numpy.array([.299, .587, .114])
        # their own light's relief a little deeper (the creases, the
        # knuckles, the side away from the key; kind config "hand_relief")
        hmed = float(numpy.median(hl))
        hl = hmed + (hl - hmed) * float(CFG.get("hand_relief", 1.35))
        rgb[hm] = numpy.clip(want[None, :] * (numpy.maximum(hl, 0) / max(wl, 1e-4))[:, None], 0, 1)
        print("MESHY hands matched to the body's skin", numpy.round(want * 255).astype(int))
    # Skin a little more coloured than Meshy paints it: a pale, greyish skin
    # falls between the palette's entries and dithers into beige and teal
    # blotches; a third more colour lands on its smooth brown ramp.
    k_s = float(CFG.get("skin_sat", 1.3))
    sk_m = (SKIN_DONE & ~HEADZONE) | hm  # (the face keeps its eased blush)
    grey = rgb[sk_m].mean(axis=1, keepdims=True)
    rgb[sk_m] = numpy.clip(grey + (rgb[sk_m] - grey) * k_s, 0, 1)
    px[:, :3] = rgb
    return px


total = skin_fix(total)
total = blush_down(total)
total = face_lift(total)
total = hand_match(total)


def skin_even(px):
    """Bare arms and hands in one even skin tone (kind config "skin_even"):
    Meshy sometimes paints forearms with hot-pink or red blotches that the
    palette turns into loud specks. The arm skin and the hands take the old
    cel's skin colour (graded back), shaded only by their own smoothed light,
    so no blotch keeps its own hue; the face's hue is drawn a share toward it
    ("face_even") with its ruddy nose and cheeks kept."""
    opt = CFG.get("skin_even")
    if not opt:
        return px
    opt = opt if isinstance(opt, dict) else {}
    px = px.copy(); _before = px[:, :3].copy()
    rgb = px[:, :3]
    LW = numpy.array([.299, .587, .114])
    lum = rgb @ LW
    mx, mn = rgb.max(axis=1), rgb.min(axis=1)
    sat = numpy.where(mx > 1e-4, (mx - mn) / numpy.maximum(mx, 1e-4), 0)
    d = numpy.maximum(mx - mn, 1e-6)
    r, g, b = rgb[:, 0], rgb[:, 1], rgb[:, 2]
    h = numpy.where(mx == r, (60 * ((g - b) / d)) % 360,
                    numpy.where(mx == g, 60 * ((b - r) / d) + 120, 60 * ((r - g) / d) + 240))
    hm = HANDMASK if "HANDMASK" in globals() else numpy.zeros(len(lum), dtype=bool)
    warm = ((h < 45) | (h > 320)) & (mx > .06) & (sat > .1)
    arm = ZONE & ~HEADZONE & ~hm & warm
    # (bare skin outside the forearm zones - an elbow under a short sleeve -
    # found by its colour: near the Meshy skin's hue and colour)
    sk0 = SKIN * GAIN
    s0mx, s0mn = float(sk0.max()), float(sk0.min())
    s0sat = (s0mx - s0mn) / max(s0mx, 1e-4)
    import colorsys
    s0h = colorsys.rgb_to_hsv(*[float(x) for x in sk0])[0] * 360
    near0 = (numpy.abs(((h - s0h + 180) % 360) - 180) < float(opt.get("hue_band", 14))) & (
        numpy.abs(sat - s0sat) < float(opt.get("sat_band", .2)))
    ext = ~HEADZONE & ~hm & warm & near0 & ~arm
    if not opt.get("arms", True):
        # (sleeves to the wrist: only the hands and the face are skin)
        arm[:] = False
    if not opt.get("ext", True):
        # (sleeved arms: no bare elbows to find; pale boots or an apron of
        # the skin's hue must not be taken for skin)
        ext[:] = False
    arm = arm | ext
    ref = arm & SKIN_DONE
    if ref.sum() < 50:
        ref = arm
    if ref.sum() < 50:
        ref = hm
    lm = float(numpy.median(lum[ref]))
    # (cloth in the forearm zone - a rolled plaid cuff - is darker or far
    # more saturated than the skin; it stays)
    # (a dark hair or grime speck on the forearm itself is evened too; the
    # colour-found skin elsewhere only where it is lit skin)
    arm &= ~((sat > .7) & (lum < lm * .9)) & (lum > lm * float(opt.get("dark", 0.0)))
    arm &= ~ext | (lum > lm * .55)
    # The tone: the old cel's skin, graded back (as face_lift's light).
    tone = None
    if _old is not None:
        o = _old
        omx, omn = o.max(axis=1), o.min(axis=1)
        osat = numpy.where(omx > 1e-4, (omx - omn) / numpy.maximum(omx, 1e-4), 0)
        oskin = (o[:, 0] > o[:, 1]) & (o[:, 1] > o[:, 2]) & (osat > .2) & (osat < .6) & (omx > .35)
        if oskin.sum() > 50:
            tone = numpy.clip((numpy.median(o[oskin], axis=0) - .024) / 1.18, 0, 1)
    if "tone" in opt:
        tone = numpy.array(opt["tone"], dtype=float) / 255.0
    if tone is None:
        return px
    tl = float(tone @ LW)
    # The light: each texel's own, its blotches' hot or dark spots clamped
    # to the arm's middle and smoothed, the hands brought to the arms' light.
    L = lum.copy()
    if hm.any():
        L[hm] *= lm / max(float(numpy.median(lum[hm])), 1e-4)
    sk = arm | hm
    L[sk] = numpy.clip(L[sk], lm * float(opt.get("floor", .75)), lm * 1.15)
    Lr = L.reshape(TEXTURE, TEXTURE)
    m2 = sk.reshape(TEXTURE, TEXTURE)
    for _ in range(int(opt.get("smooth", 12))):
        acc = numpy.zeros_like(Lr)
        cnt = numpy.zeros_like(Lr)
        for dy, dx in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
            mm = numpy.roll(numpy.roll(m2, dy, 0), dx, 1)
            acc += numpy.roll(numpy.roll(Lr, dy, 0), dx, 1) * mm
            cnt += mm
        Lr[m2] = (acc / numpy.maximum(cnt, 1))[m2]
    L = Lr.reshape(-1)
    # (the old cel's skin light, a little lifted: "light")
    out = tone[None, :] * (L / max(lm, 1e-4) * float(opt.get("light", 1.1)))[:, None]
    rgb[sk] = numpy.clip(out[sk], 0, 1)
    # The face: hue and colour a share toward the tone, its light kept, the
    # redder-than-skin nose and cheeks keeping their extra red.
    fk = float(opt.get("face_even", .7))
    face = HEADZONE & warm & SKIN_DONE
    if fk > 0 and face.any():
        ft = tone[None, :] * (lum[face] / max(tl, 1e-4))[:, None]
        rgb[face] = numpy.clip(rgb[face] * (1 - fk) + ft * fk, 0, 1)
    if os.environ.get("MESHY_DEBUG"):
        numpy.save(os.path.join(OUT, "dbg_masks.npy"), numpy.stack([ZONE & ~HEADZONE, arm, hm, HEADZONE]))
        numpy.save(os.path.join(OUT, "dbg_before.npy"), _before)
    px[:, :3] = rgb
    print("MESHY skin evened: %d arm texels, %d hand texels, %d face texels to %s" % (
        int(arm.sum()), int(hm.sum()), int(face.sum()), numpy.round(tone * 255).astype(int)))
    return px


total = skin_even(total)


def hand_dilate(px, reach=10):
    """The hands' skin grown outward into the unbaked (black) texels round
    their islands: a thin webbing triangle at a finger root whose UV corner
    falls past the bake margin otherwise samples black (a dark sliver)."""
    if "HANDMASK" not in globals() or not HANDMASK.any():
        return px
    px = px.copy()
    img = px[:, :3].reshape(TEXTURE, TEXTURE, 3)
    have = HANDMASK.reshape(TEXTURE, TEXTURE).copy()
    empty = img.max(axis=2) < .03
    # (only texels no face covers: a black suit's own texels are dark too,
    # and took the hands' skin as tan blotches on the revenue man's trousers)
    if "inside" in globals():
        empty &= ~inside.reshape(TEXTURE, TEXTURE)
    grown = 0
    for _ in range(reach):
        acc = numpy.zeros_like(img)
        cnt = numpy.zeros((TEXTURE, TEXTURE))
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            mm = numpy.roll(numpy.roll(have, dy, 0), dx, 1)
            acc += numpy.roll(numpy.roll(img, dy, 0), dx, 1) * mm[:, :, None]
            cnt += mm
        new = empty & ~have & (cnt > 0)
        img[new] = acc[new] / cnt[new][:, None]
        have |= new
        grown += int(new.sum())
    px[:, :3] = img.reshape(-1, 3)
    print("MESHY hands' skin grown into %d empty texels" % grown)
    return px


total = hand_dilate(total)


def gloves(px):
    """Gloved hands (kind config "gloves": [r, g, b], e.g. yellow rubber):
    with "glove_shade": true the hands take the glove's colour shaded by the
    baked hand's own light
    (the master hand's creases and knuckles, kept from before the skin
    passes flattened it), darker ochre in the folds and between the fingers,
    a soft grime, and a little under the glove colour's full light so they
    sit in the same light as the clothes ("glove_light", default .85)."""
    if not CFG.get("gloves") or "HANDMASK" not in globals() or not HANDMASK.any():
        return px
    px = px.copy()
    g = numpy.array(CFG["gloves"], dtype=float) / 255.0
    if not CFG.get("glove_shade"):
        # (the first way, kept for boss and rudy: glove colour at the
        # hand's light after the skin passes)
        lum = px[:, :3] @ numpy.array([.299, .587, .114])
        lm = float(numpy.median(lum[HANDMASK]))
        k = numpy.clip(lum / max(lm, 1e-4), .55, 1.5) ** 1.3
        px[HANDMASK, :3] = numpy.clip(g[None, :] * k[HANDMASK, None], 0, 1)
        print("MESHY gloves: %d hand texels to %s" % (int(HANDMASK.sum()), CFG["gloves"]))
        return px
    lumw = numpy.array([.299, .587, .114])
    sh = HAND_SHADE if "HAND_SHADE" in globals() else px[:, :3] @ lumw
    s = sh[HANDMASK]
    r = s / max(float(numpy.median(s)), 1e-4)
    print("MESHY gloves: hand light pct 5/25/50/75/95 (share of the median)",
          numpy.round(numpy.percentile(r, [5, 25, 50, 75, 95]), 2))
    # (shade deepened, highlights rolled off rather than clipped flat)
    k = numpy.where(r < 1, numpy.clip(r, .3, 1) ** float(CFG.get("glove_contrast", 1.4)),
                    r / (1 + .5 * numpy.maximum(r - 1, 0)))
    col = g[None, :] * float(CFG.get("glove_light", .85)) * k[:, None]
    # folds: toward a dark yellow-ochre where the hand is in its own shade
    fold = numpy.array(CFG.get("glove_fold", [96, 62, 18]), dtype=float) / 255.0
    t = numpy.clip((1.0 - r) * 1.5, 0, 1)[:, None] ** 1.2
    col = col * (1 - t) + fold[None, :] * numpy.clip(r, .3, 1)[:, None] * t
    # grime: a soft blotch field over the texture (low-frequency noise)
    rng = numpy.random.default_rng(7)
    lo_n = rng.random((TEXTURE // 16 + 2, TEXTURE // 16 + 2))
    yy, xx = numpy.mgrid[0:TEXTURE, 0:TEXTURE] / 16.0
    y0, x0 = yy.astype(int), xx.astype(int)
    fy, fx = yy - y0, xx - x0
    n = (lo_n[y0, x0] * (1 - fx) * (1 - fy) + lo_n[y0, x0 + 1] * fx * (1 - fy)
         + lo_n[y0 + 1, x0] * (1 - fx) * fy + lo_n[y0 + 1, x0 + 1] * fx * fy).ravel()
    grime = numpy.array(CFG.get("glove_grime", [120, 92, 40]), dtype=float) / 255.0
    gm = (numpy.clip(n[HANDMASK] - .45, 0, 1) * float(CFG.get("glove_grime_k", .7)))[:, None]
    col = col * (1 - gm) + grime[None, :] * k[:, None] * gm
    px[HANDMASK, :3] = numpy.clip(col, 0, 1)
    print("MESHY gloves: %d hand texels to %s" % (int(HANDMASK.sum()), CFG["gloves"]))
    return px


def face_clean(px):
    """Kind config "face_clean" (see meshy/tools/face_clean.py)."""
    if not CFG.get("face_clean") or ALBEDO is None:
        return px
    import face_clean as _fc
    out, info = _fc.clean(px, ALBEDO, HEADZONE, FACEZONE | BACKZONE, HANDMASK if "HANDMASK" in globals() else None, TEXTURE,
                          CFG["face_clean"] if isinstance(CFG["face_clean"], dict) else {}, NOSHADOW, BACKZONE)
    print("MESHY face clean: %s" % info)
    return out


total = gloves(total)
if os.environ.get("MESHY_DUMP_FACE"):
    # (scratch: the finished body texels and the masks, to try face passes
    # outside Blender)
    numpy.savez_compressed(os.path.abspath(os.environ["MESHY_DUMP_FACE"]), total=total, headzone=HEADZONE, zone=ZONE,
                           hand=HANDMASK if "HANDMASK" in globals() else numpy.zeros(len(total), bool),
                           skin_done=SKIN_DONE, albedo=ALBEDO if ALBEDO is not None else numpy.zeros((0, 3)),
                           noshadow=NOSHADOW if NOSHADOW is not None else numpy.zeros((0, 3)), tex=TEXTURE,
                           facezone=FACEZONE, backzone=BACKZONE)
total = face_clean(total)
_fsk = HEADZONE & SKIN_DONE if "SKIN_DONE" in globals() else HEADZONE
shed.paint(lo, image, total, CFG, pixels, bake_op, select, TEXTURE,
           skin=numpy.median(total[_fsk, :3], axis=0) if _fsk.sum() > 50 else None)
image.pixels.foreach_set(total.ravel())
image.filepath_raw = os.path.join(OUT, KIND + ".png")
image.file_format = "PNG"
image.save()

# The gear's texels: the old look copied (emission), and a mask of them.
if gear_obj is not None:
    gimg = bpy.data.images.new("gear", TEXTURE, TEXTURE, alpha=False)
    for m in lo.data.materials:
        m.node_tree.nodes["bake_target"].image = gimg
    gear_obj.hide_render = False
    scene.cycles.samples = 4
    select([gear_obj, lo], lo)
    bake_op(type="EMIT", margin=2, use_clear=True, use_selected_to_active=True,
            cage_extrusion=.01, max_ray_distance=.02)
    gimg.filepath_raw = os.path.join(OUT, KIND + "_gear.png")
    gimg.file_format = "PNG"
    gimg.save()
    # (a boss's phase looks: the old phase look's gear texels)
    for _tag in (("p2", "p3") if CFG.get("phases") else ()):
        _op = CFG["old_tex"].replace(".png", "_%s.png" % _tag)
        if not os.path.exists(_op):
            continue
        _oi = bpy.data.images.load(_op)
        for _m in gear_obj.data.materials:
            if _m and _m.use_nodes:
                for _n in _m.node_tree.nodes:
                    if _n.type == "TEX_IMAGE":
                        _n.image = _oi
        _gp = bpy.data.images.new("gear_" + _tag, TEXTURE, TEXTURE, alpha=False)
        for m in lo.data.materials:
            m.node_tree.nodes["bake_target"].image = _gp
        select([gear_obj, lo], lo)
        bake_op(type="EMIT", margin=2, use_clear=True, use_selected_to_active=True,
                cage_extrusion=.01, max_ray_distance=.02)
        _gp.filepath_raw = os.path.join(OUT, KIND + "_gear_" + _tag + ".png")
        _gp.file_format = "PNG"
        _gp.save()
    # Mask: the gear slot emits white, the body black.
    for m, val in ((mat_body, 0.0), (mat_gear, 1.0), (mat_hand, 0.0), (mat_fish, .1)):
        nt = m.node_tree
        for n in list(nt.nodes):
            if n.name != "bake_target":
                nt.nodes.remove(n)
        o = nt.nodes.new("ShaderNodeOutputMaterial")
        e = nt.nodes.new("ShaderNodeEmission")
        e.inputs[0].default_value = (val, val, val, 1)
        nt.links.new(e.outputs[0], o.inputs[0])
    mimg = bpy.data.images.new("gearmask", TEXTURE, TEXTURE, alpha=False)
    for m in lo.data.materials:
        m.node_tree.nodes["bake_target"].image = mimg
        m.node_tree.nodes.active = m.node_tree.nodes["bake_target"]
    select([lo])
    bake_op(type="EMIT", margin=1, use_clear=True)
    mimg.filepath_raw = os.path.join(OUT, KIND + "_gearmask.png")
    mimg.file_format = "PNG"
    mimg.save()
    bpy.data.objects.remove(gear_obj)

# ----------------------------------------------------------------- the hurt
# Blood where the old hurt look bled: the brow, the chest and belly, an arm;
# 3D noise in object space thresholded into splashes, baked as a mask.
for m in lo.data.materials:
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.name != "bake_target":
            nt.nodes.remove(n)
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    e = nt.nodes.new("ShaderNodeEmission")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 9.0
    noise.inputs["Detail"].default_value = 6.0
    nt.links.new(tc.outputs["Object"], noise.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], e.inputs[0])
    nt.links.new(e.outputs[0], o.inputs[0])
nimg2 = bpy.data.images.new("noise", TEXTURE, TEXTURE, alpha=False, float_buffer=True)
nimg2.colorspace_settings.name = "Non-Color"
for m in lo.data.materials:
    m.node_tree.nodes["bake_target"].image = nimg2
    m.node_tree.nodes.active = m.node_tree.nodes["bake_target"]
select([lo])
bake_op(type="EMIT", margin=2, use_clear=True)
noise_px = pixels(nimg2)[:, 0]
# Position of each texel (object space) to weight the wounds.
for m in lo.data.materials:
    nt = m.node_tree
    for n in list(nt.nodes):
        if n.name != "bake_target":
            nt.nodes.remove(n)
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    e = nt.nodes.new("ShaderNodeEmission")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Location"].default_value = (.5, .5, 0)
    mp.inputs["Scale"].default_value = (.5, .5, 1 / OLD_H)
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    nt.links.new(mp.outputs[0], e.inputs[0])
    nt.links.new(e.outputs[0], o.inputs[0])
pimg = bpy.data.images.new("pos", TEXTURE, TEXTURE, alpha=False, float_buffer=True)
pimg.colorspace_settings.name = "Non-Color"
for m in lo.data.materials:
    m.node_tree.nodes["bake_target"].image = pimg
select([lo])
bake_op(type="EMIT", margin=2, use_clear=True)
pos = pixels(pimg)
px_ = (pos[:, 0] - .5) * 2
py_ = (pos[:, 1] - .5) * 2
pz_ = pos[:, 2]
# Recolours a kind asks for (kind config "recolour": a list of rules, each a
# box in model space - "z" [lo, hi] as shares of the height, "x"/"y" [lo, hi]
# in metres - and the colours it takes - hue [lo, hi] (wrapping), "sat" [lo,
# hi], "val" [lo, hi] - turned to "to" [r, g, b] (0-255) at each texel's own
# light relative to the rule's middle light): a Meshy hat painted the wrong
# colour, made the cel's.
for rule in CFG.get("recolour", []):
    rgbv = total[:, :3]
    mx = rgbv.max(axis=1)
    mn = rgbv.min(axis=1)
    sat = numpy.where(mx > 1e-4, (mx - mn) / numpy.maximum(mx, 1e-4), 0)
    dd = numpy.maximum(mx - mn, 1e-6)
    r_, g_, b_ = rgbv[:, 0], rgbv[:, 1], rgbv[:, 2]
    hh = numpy.where(mx == r_, (60 * ((g_ - b_) / dd)) % 360,
                     numpy.where(mx == g_, 60 * ((b_ - r_) / dd) + 120, 60 * ((r_ - g_) / dd) + 240))
    m = (pz_ >= rule.get("z", [0, 2])[0]) & (pz_ <= rule.get("z", [0, 2])[1])
    m &= (px_ >= rule.get("x", [-9, 9])[0]) & (px_ <= rule.get("x", [-9, 9])[1])
    m &= (py_ >= rule.get("y", [-9, 9])[0]) & (py_ <= rule.get("y", [-9, 9])[1])
    if "hue" in rule:
        h0, h1 = rule["hue"]
        m &= ((hh >= h0) & (hh <= h1)) if h0 <= h1 else ((hh >= h0) | (hh <= h1))
    m &= (sat >= rule.get("sat", [0, 1])[0]) & (sat <= rule.get("sat", [0, 1])[1])
    if rule.get("at") == "nose" and NOSE is not None:
        rr = float(rule.get("r", .035)) * OLD_H / 1.7
        m &= numpy.sqrt((px_ - NOSE.x) ** 2 + (py_ - NOSE.y) ** 2 + ((pz_ * OLD_H) - NOSE.z) ** 2) < rr
    m &= (mx >= rule.get("val", [0, 1])[0]) & (mx <= rule.get("val", [0, 1])[1])
    if rule.get("not_skin", True):
        m &= ~SKIN_DONE
        if "HANDMASK" in globals():
            m &= ~HANDMASK
    if m.sum() < 10:
        print("MESHY recolour %s: nothing" % rule.get("name", "?"))
        continue
    lum = rgbv @ numpy.array([.299, .587, .114])
    lmid = float(numpy.median(lum[m]))
    to = numpy.array(rule["to"], dtype=float) / 255.0
    k = numpy.clip(lum / max(lmid, 1e-4), .4, 1.8) ** float(rule.get("contrast", .8))
    total[m, :3] = numpy.clip(to[None, :] * k[m, None], 0, 1)
    print("MESHY recolour %s: %d texels to %s" % (rule.get("name", "?"), int(m.sum()), rule["to"]))
if os.environ.get("MESHY_DEBUG"):
    numpy.save(os.path.join(OUT, "dbg_pos.npy"), numpy.stack([px_, py_, pz_]))
    numpy.save(os.path.join(OUT, "dbg_total.npy"), total[:, :3])
if CFG.get("recolour"):
    image.pixels.foreach_set(total.ravel())
    image.filepath_raw = os.path.join(OUT, KIND + ".png")
    image.save()
front = py_ < 0.02
wounds = numpy.zeros(len(pz_))
# brow/face cut, chest and belly, the gut, one arm (the left upper arm)
for cx, cz, rad, k in ((0.0, .9, .07, 1.0), (.05, .66, .12, 1.0), (-.06, .55, .09, .9), (.2, .72, .07, .7)):
    d = numpy.sqrt(((px_ - cx) / rad) ** 2 + ((pz_ - cz) * OLD_H / OLD_H / rad) ** 2)
    wounds = numpy.maximum(wounds, numpy.clip(1.2 - d, 0, 1) * k)
blood = numpy.clip((noise_px - (1.05 - wounds * .65)) * 6, 0, 1) * front
if gear_obj is not None:
    gm_px = pixels(mimg)[:, 0]
    blood *= gm_px < .2
hurt = total.copy()
dark = numpy.array([.36, .03, .02])
wet = numpy.array([.55, .05, .03])
mixc = dark + (wet - dark) * numpy.clip(noise_px[:, None] * 1.5 - .3, 0, 1)
hurt[:, :3] = hurt[:, :3] * (1 - blood[:, None] * .85) + mixc * blood[:, None] * .85
image.pixels.foreach_set(hurt.ravel())
image.filepath_raw = os.path.join(OUT, KIND + "_hurt.png")
image.save()
# A boss's phase looks (kind config "phases": true; the old ones were every
# material scorched plus his own rags and breakage): p2 under half health
# sooted in blotches and bloodied, p3 under a fifth charred darker all over,
# the blotches spread and the blood heavier. The held gear keeps the old
# phase looks' texels (gear_paste.py) and takes neither.
LOOKS = ["", "hurt"]
if CFG.get("phases"):
    LOOKS = ["", "p2", "p3"]
    _gm = (pixels(mimg)[:, 0] < .2) if gear_obj is not None else numpy.ones(len(noise_px), bool)
    _soot_dark = numpy.array([.07, .055, .045])
    for _tag, _thr, _soot_k, _all, _bk in (("p2", .58, .7, .93, .6), ("p3", .48, .85, .8, 1.0)):
        _soot = numpy.clip((noise_px - _thr) * 5, 0, 1) * _gm
        _ph = total.copy()
        _ph[:, :3] = _ph[:, :3] * numpy.where(_gm, _all, 1.0)[:, None]
        _ph[:, :3] = _ph[:, :3] * (1 - _soot[:, None] * _soot_k) + _soot_dark * _soot[:, None] * _soot_k
        _b = blood * _bk
        _ph[:, :3] = _ph[:, :3] * (1 - _b[:, None] * .85) + mixc * _b[:, None] * .85
        image.pixels.foreach_set(_ph.ravel())
        image.filepath_raw = os.path.join(OUT, KIND + "_" + _tag + ".png")
        image.save()
image.pixels.foreach_set(total.ravel())
image.filepath_raw = os.path.join(OUT, KIND + ".png")

# ------------------------------------------------------------------ export
# Each held thing is cut off the body's mesh into a mesh of its own: no skin
# weights at all, hung off its bone (glTF: a node under the joint; Godot: a
# BoneAttachment3D), moved to its rest on its hand's rest, so it is a solid
# piece that never bends or blends into the arm.
HELD_OBJS = []
if ITEMS:
    rig.data.pose_position = "REST"
    bpy.context.view_layer.update()
    for gi, it in enumerate(ITEMS):
        select([lo])
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="DESELECT")
        bm = bmesh.from_edit_mesh(lo.data)
        dl = bm.verts.layers.deform.active
        gidx = lo.vertex_groups[it["bone"]].index
        for f in bm.faces:
            f.select = f.material_index in (1, 3) and all(v[dl].get(gidx, 0) > .5 for v in f.verts)
        bmesh.update_edit_mesh(lo.data)
        before = set(bpy.data.objects)
        bpy.ops.mesh.separate(type="SELECTED")
        bpy.ops.object.mode_set(mode="OBJECT")
        piece = next(o for o in bpy.data.objects if o not in before)
        piece.name = "held_" + it["bone"]
        piece.vertex_groups.clear()
        for m in list(piece.modifiers):
            piece.modifiers.remove(m)
        piece.data.transform(ITEM_REST[it["bone"]])
        piece.parent = rig
        piece.parent_type = "BONE"
        piece.parent_bone = it["bone"]
        piece.matrix_world = Matrix.Identity(4)
        piece.data.materials.clear()
        HELD_OBJS.append(piece)
        print("MESHY held thing %s: its own mesh, %d triangles, on bone %s" % (
            piece.name, len(piece.data.polygons), it["bone"]))
    # A held model's tail pieces: each its own mesh on its tail bone, at the
    # rest of the thing they belong to (rigid on it until ActorView swings
    # the bone about its joint).
    for _tn, _tp, _ib in TAILS:
        select([lo])
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="DESELECT")
        bm = bmesh.from_edit_mesh(lo.data)
        dl = bm.verts.layers.deform.active
        gidx = lo.vertex_groups[_tn].index
        for f in bm.faces:
            f.select = f.material_index == 3 and all(v[dl].get(gidx, 0) > .5 for v in f.verts)
        bmesh.update_edit_mesh(lo.data)
        before = set(bpy.data.objects)
        bpy.ops.mesh.separate(type="SELECTED")
        bpy.ops.object.mode_set(mode="OBJECT")
        piece = next(o for o in bpy.data.objects if o not in before)
        piece.name = "held_" + _tn
        piece.vertex_groups.clear()
        for m in list(piece.modifiers):
            piece.modifiers.remove(m)
        piece.data.transform(ITEM_REST[_ib])
        piece.parent = rig
        piece.parent_type = "BONE"
        piece.parent_bone = _tn
        piece.matrix_world = Matrix.Identity(4)
        piece.data.materials.clear()
        HELD_OBJS.append(piece)
        print("MESHY held tail piece %s: its own mesh, %d triangles" % (piece.name, len(piece.data.polygons)))
    rig.data.pose_position = "POSE"
    bpy.context.view_layer.update()
    # The body keeps no weights on the held things' bones.
    for b_ in [it["bone"] for it in ITEMS] + [t_[0] for t_ in TAILS]:
        if b_ in lo.vertex_groups:
            lo.vertex_groups.remove(lo.vertex_groups[b_])
if "handuv" in lo.data.uv_layers:
    lo.data.uv_layers.remove(lo.data.uv_layers["handuv"])
lo.parent = rig
mod = lo.modifiers.new("rig", "ARMATURE")
mod.object = rig
lo.data.materials.clear()
# A viewing material for the .blend (the plain look).
view_mat = bpy.data.materials.new(KIND + "_look")
view_mat.use_nodes = True
vt = view_mat.node_tree.nodes.new("ShaderNodeTexImage")
look = bpy.data.images.load(os.path.join(OUT, KIND + ".png"))
vt.image = look
bsdf = view_mat.node_tree.nodes["Principled BSDF"]
view_mat.node_tree.links.new(vt.outputs[0], bsdf.inputs["Base Color"])
bsdf.inputs["Roughness"].default_value = 1.0
# The hands' triangles in every key against their rest: an edge stretched
# past twice its length, or a face turned over, is a tear.
_ish2 = lo.data.attributes.get("is_hand")
_hand_faces = [p_ for p_ in lo.data.polygons if _ish2 is not None and _ish2.data[p_.index].value == 1]


def hand_flips():
    """Hand triangles turned over in some key against how their own bones
    turned them (a finger root folding into the palm shows its inside: a
    dark sliver up close). Returns {vertex: count} and the face count."""
    gname = {g.index: g.name for g in lo.vertex_groups}
    rest = numpy.array([v.co[:] for v in lo.data.vertices])
    tris = [tuple(p_.vertices) for p_ in _hand_faces if len(p_.vertices) == 3]
    tri = numpy.array(tris)
    n0 = numpy.cross(rest[tri[:, 1]] - rest[tri[:, 0]], rest[tri[:, 2]] - rest[tri[:, 0]])
    # each face's own bone: the most weight over its corners
    fb = []
    for t_ in tris:
        acc = {}
        for vi in t_:
            for g in lo.data.vertices[vi].groups:
                acc[g.group] = acc.get(g.group, 0) + g.weight
        fb.append(gname[max(acc, key=acc.get)])
    bad_v = {}
    faces = set()
    for t in KEYS:
        scene.frame_set(t)
        dg = bpy.context.evaluated_depsgraph_get()
        evm = lo.evaluated_get(dg).to_mesh()
        now = numpy.empty_like(rest)
        evm.vertices.foreach_get("co", now.ravel())
        lo.evaluated_get(dg).to_mesh_clear()
        n1 = numpy.cross(now[tri[:, 1]] - now[tri[:, 0]], now[tri[:, 2]] - now[tri[:, 0]])
        rot = {}
        for bn in set(fb):
            pb = rig.pose.bones.get(bn)
            rot[bn] = numpy.array((pb.matrix @ pb.bone.matrix_local.inverted()).to_3x3()) if pb else numpy.eye(3)
        exp = numpy.array([rot[fb[i]] @ n0[i] for i in range(len(tris))])
        dot = (exp * n1).sum(axis=1) / numpy.maximum(numpy.linalg.norm(exp, axis=1) * numpy.linalg.norm(n1, axis=1), 1e-12)
        for i in numpy.nonzero(dot < 0)[0]:
            faces.add(i)
            for vi in tris[i]:
                bad_v[vi] = bad_v.get(vi, 0) + 1
    scene.frame_set(0)
    import collections
    print("MESHY turned-over faces by bone:", collections.Counter(fb[i] for i in faces).most_common(12))
    return bad_v, len(faces)


if _hand_faces:
    hand_flips()


if _hand_faces and CFG.get("unflip", False):
    _adj = {}
    for e_ in lo.data.edges:
        a_, b_ = e_.vertices
        _adj.setdefault(a_, set()).add(b_)
        _adj.setdefault(b_, set()).add(a_)
    for _round in range(int(CFG.get("unflip_rounds", 6))):
        bad_v, nf = hand_flips()
        print("MESHY hand faces turned over: %d (round %d)" % (nf, _round))
        if not bad_v:
            break
        # their corners' weights relaxed toward their neighbours' (and the
        # neighbours a little toward theirs), so the fold spreads out
        grow = set(bad_v)
        for vi in list(bad_v):
            grow |= _adj.get(vi, set())
        old_w = {}
        for vi in grow:
            old_w[vi] = {g.group: g.weight for g in lo.data.vertices[vi].groups}
        for vi in grow:
            acc = {}
            ring = [vi] + list(_adj.get(vi, ()))
            for u in ring:
                for gk, w in old_w.get(u, {g.group: g.weight for g in lo.data.vertices[u].groups}).items():
                    acc[gk] = acc.get(gk, 0) + w
            tot = sum(acc.values())
            share = .7 if vi in bad_v else .35
            mine = old_w[vi]
            for gk in set(acc) | set(mine):
                w = mine.get(gk, 0) * (1 - share) + acc.get(gk, 0) / max(tot, 1e-6) * share
                if w > 1e-4:
                    lo.vertex_groups[gk].add([vi], w, "REPLACE")
                elif gk in mine:
                    lo.vertex_groups[gk].remove([vi])
    else:
        bad_v, nf = hand_flips()
        print("MESHY hand faces turned over: %d (after)" % nf)
print("MESHY hand faces checked: %d" % len(_hand_faces))
BAD_E = [0]
WORST_E = None
if _hand_faces:
    _rest = {v.index: v.co.copy() for v in lo.data.vertices}
    worst_s, worst_k, flips = 1.0, "", 0
    for t in KEYS:
        scene.frame_set(t)
        dg = bpy.context.evaluated_depsgraph_get()
        evm = lo.evaluated_get(dg).to_mesh()
        for p_ in _hand_faces:
            vs = list(p_.vertices)
            for k_ in range(len(vs)):
                a_, b_ = vs[k_], vs[(k_ + 1) % len(vs)]
                r_ = (_rest[a_] - _rest[b_]).length
                if r_ > 1e-5:
                    q_ = (evm.vertices[a_].co - evm.vertices[b_].co).length / r_
                    if q_ > worst_s:
                        worst_s, worst_k = q_, BY_KEY[t]
                        _gn = {g.index: g.name for g in lo.vertex_groups}
                        WORST_E = ([(_gn[g.group], round(g.weight, 2)) for g in lo.data.vertices[a_].groups],
                                   [(_gn[g.group], round(g.weight, 2)) for g in lo.data.vertices[b_].groups],
                                   round(r_, 4))
            if q_ > 2.0:
                BAD_E[0] += 1
            if len(vs) == 3:
                n0 = (_rest[vs[1]] - _rest[vs[0]]).cross(_rest[vs[2]] - _rest[vs[0]])
                n1 = (evm.vertices[vs[1]].co - evm.vertices[vs[0]].co).cross(evm.vertices[vs[2]].co - evm.vertices[vs[0]].co)
                # (a face turned over against how the bones turned it is a
                # flip; measured against the hand bone's turn)
        lo.evaluated_get(dg).to_mesh_clear()
    print("MESHY hand mesh: worst edge stretch x%.2f (%s), %d edge-keys past x2; worst edge %s" % (
        worst_s, worst_k, BAD_E[0], WORST_E if worst_s > 1 else ""))
    scene.frame_set(0)
select([lo, rig] + HELD_OBJS, rig)
bpy.ops.export_scene.gltf(
    filepath=os.path.join(OUT, KIND + ".glb"), export_format="GLB", use_selection=True,
    export_materials="NONE", export_yup=True, export_animations=True, export_skins=True,
    export_morph=False, export_force_sampling=False, export_def_bones=False,
)
lo.data.materials.append(view_mat)
for o in HELD_OBJS:
    o.data.materials.append(view_mat)
hi.hide_render = True
hi.hide_set(True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, KIND + ".blend"))

# --------------------------------------------------------------- actors.json
lo.data.calc_loop_triangles()
labels = {b: LABEL[b] for b in BONES}
for _sb, (_g, _on) in SHED.items():
    labels[_sb] = LABEL[_on]
RIDES = {}
for it in ITEMS:
    labels[it["bone"]] = "arm_" + it["main"]
    # The held thing rides its main hand's forearm in the ragdoll and the
    # living body (RagdollRig segments: 3 the left forearm, 5 the right).
    RIDES[it["bone"]] = 3 if it["main"] == "l" else 5
FLOP = {}
for _tn, _tp, _ib in TAILS:
    _it = next(it for it in ITEMS if it["bone"] == _ib)
    labels[_tn] = "arm_" + _it["main"]
    RIDES[_tn] = 3 if _it["main"] == "l" else 5
    FLOP[_tn] = _tp
old_entry = json.load(open(os.path.join(os.path.dirname(CFG["old_glb"]), "actors.json")))[KIND]
entry = {
    "bones": float(len(BONES) + len(GEAR) + len(TAILS) + len(SHED)),
    "canvas": old_entry.get("canvas", [1.75, 1.86]),
    "faces": float(len(lo.data.loop_triangles)),
    "frames": FRAMES,
    "gear": {b: g for b, (g, _on) in SHED.items()} if "shed" in CFG else old_entry.get("gear", {}),
    "height": OLD_H,
    "labels": labels,
    "lit": old_entry.get("lit", True),
    "parts": float(len(BONES) + len(GEAR) + len(TAILS) + len(SHED)),
    "textures": LOOKS,
    "joints": JOINTS,
    "rides": RIDES,
    **({"flop": FLOP} if FLOP else {}),
    **({"hold_near": float(CFG["hold_near"])} if "hold_near" in CFG else {}),
    **({"hold_legs": True} if CFG.get("hold_legs") else {}),
    "segs": dict({"body": 0, "head": 1, "upperarm_l": 2, "forearm_l": 3, "hand_l": 3, "upperarm_r": 4,
                  "forearm_r": 5, "hand_r": 5, "thigh_l": 6, "shin_l": 7, "foot_l": 7, "thigh_r": 8,
                  "shin_r": 9, "foot_r": 9},
                 **{b: (3 if b.startswith("fl_") else 5) for b in BONES if b.startswith(("fl_", "fr_"))},
                 **{_sb: {"body": 0, "head": 1}[_on] for _sb, (_g, _on) in SHED.items()}),
    "meshy": True,
}
meta_path = os.path.join(OUT, "actors.json")
meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
meta[KIND] = entry
json.dump(meta, open(meta_path, "w"), indent=1, sort_keys=True)
print("MESHY ACTOR %s done: %d tris, %d bones" % (KIND, len(lo.data.loop_triangles), len(BONES) + len(GEAR)))
