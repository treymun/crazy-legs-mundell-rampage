"""Blender: an animal or a boss remade with Meshy on its OLD armature.

    blender -b -P meshy/tools/build_beast.py -- meshy/kinds/<kind>.json

The old model keeps its skeleton, every key of its animation and its
actors.json entry (labels, frames, gear): only the mesh and its look are new.
The Meshy mesh (unrigged, standing as the old one stands at its standing
key) is fitted onto the old mesh (turned the best of four ways, scaled and
moved, then a few rounds of closest points), decimated, and given the old
mesh's weights by its nearest old face (the old parts are rigid: one bone a
vertex), softened over a few rings so a knee or a neck bends instead of
splitting, at most four bones a vertex. It is then carried back to the old
rest pose (inverse skinning) and its look baked from the Meshy model lit by
the dusk stage, four turns, matched to the old look's light. Kind config:

  kind, meshy (the Meshy glb), old_glb, old_tex, out, tris, texture,
  smooth (rings of weight softening, default 2), rigid (bones whose
  vertices are not softened), hard (bones whose border is not softened
  from either side), legs [[hip, knee, foot]...] and torso (each old leg
  moved to the Meshy leg's place, keys and all), stand (the key the Meshy model stands as,
  default "0"), icp (rounds of closest points, default 12), gain (times
  the light matched to the old look's), tint [r, g, b] (times the colour),
  weights ("heat" or "nearest"), groups (bones weighted as one).
  Not yet: a boss's old gear kept (its weapon parts), a hurt look.
"""
import json
import math
import os
import sys

import bmesh
import bpy
import numpy
from mathutils import Matrix, Vector
from mathutils.kdtree import KDTree

CFG = json.load(open(sys.argv[sys.argv.index("--") + 1], encoding="utf-8"))
KIND = CFG["kind"]
OUT = os.path.abspath(CFG["out"])
TRIS = int(CFG.get("tris", 9000))
TEX = int(CFG.get("texture", 512))
os.makedirs(OUT, exist_ok=True)
TURNS = (0, 90, 180, 270)


def select(objs, active=None):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or objs[0]


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for o in list(new):
        if o.type == "MESH" and o.name.startswith("Icosphere"):
            bpy.data.objects.remove(o)
            new.remove(o)
    return new


def stage():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    world = bpy.data.worlds.new("world")
    scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
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


bpy.ops.wm.read_factory_settings(use_empty=True)
stage()
scene = bpy.context.scene

# ------------------------------------------------------------ the old model
old = import_glb(CFG["old_glb"])
arm = next(o for o in old if o.type == "ARMATURE")
old_mesh = max((o for o in old if o.type == "MESH"), key=lambda o: len(o.data.vertices))
meta_old = json.load(open(os.path.join(os.path.dirname(CFG["old_glb"]), "actors.json")))[KIND]
FRAMES = meta_old["frames"]
STAND = int(round(FRAMES[CFG.get("stand", "0")]))
scene.frame_set(STAND)
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
src_me = bpy.data.meshes.new_from_object(old_mesh.evaluated_get(dg), preserve_all_data_layers=True, depsgraph=dg)
src_me.transform(old_mesh.matrix_world)
src = bpy.data.objects.new("old_standing", src_me)
scene.collection.objects.link(src)
for g in old_mesh.vertex_groups:
    src.vertex_groups.new(name=g.name)
# (each old bone's move from rest to the standing key, for the way back)
POSE = {pb.name: arm.matrix_world @ pb.matrix @ pb.bone.matrix_local.inverted() @ arm.matrix_world.inverted()
        for pb in arm.pose.bones}
P = numpy.array([v.co[:] for v in src_me.vertices])
OLD_H = float(P[:, 2].max() - P[:, 2].min())

# ------------------------------------------------------------ the new mesh
new = import_glb(CFG["meshy"])
hi = next(o for o in new if o.type == "MESH")
for o in new:
    if o is not hi:
        bpy.data.objects.remove(o)
wm_ = hi.matrix_world.copy()
hi.parent = None
hi.matrix_world = wm_
select([hi])
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
hi.name = KIND + "_hi"
for slot in hi.material_slots:
    m = slot.material
    if m is not None and m.use_nodes:
        for n in m.node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED":
                for inp, val in (("Roughness", 1.0), ("Metallic", 0.0)):
                    for lk in list(n.inputs[inp].links):
                        m.node_tree.links.remove(lk)
                    n.inputs[inp].default_value = val
                if "Specular IOR Level" in n.inputs:
                    n.inputs["Specular IOR Level"].default_value = 0.0
Q0 = numpy.array([v.co[:] for v in hi.data.vertices])


def tree_of(pts):
    t = KDTree(len(pts))
    for i, p in enumerate(pts):
        t.insert(p, i)
    t.balance()
    return t


Ps = P[:: max(1, len(P) // 3000)]
Qs = Q0[:: max(1, len(Q0) // 3000)]
TP = tree_of(Ps)


def chamfer(Qx):
    tq = tree_of(Qx)
    a = numpy.mean([TP.find(q)[2] for q in Qx])
    b = numpy.mean([tq.find(p)[2] for p in Ps])
    return a + b


def floor_fit(Qx):
    """Uniform scale by height and length, the boxes' middles together, on the floor."""
    k = float(numpy.mean(numpy.ptp(Ps, axis=0)[[0, 1, 2]] / numpy.maximum(numpy.ptp(Qx, axis=0), 1e-6)))
    Qx = (Qx - Qx.mean(axis=0)) * k
    Qx = Qx + (Ps.min(axis=0) + Ps.max(axis=0)) / 2 - (Qx.min(axis=0) + Qx.max(axis=0)) / 2
    Qx[:, 2] += Ps[:, 2].min() - Qx[:, 2].min()
    return Qx, k


best = None
for yaw in (0, 90, 180, 270):
    R = numpy.array(Matrix.Rotation(math.radians(yaw), 3, "Z"))
    Qr = Qs @ R.T
    # (the length matched first: the four turns give different boxes)
    Qf, _k = floor_fit(Qr)
    c = chamfer(Qf)
    print("BEAST fit turn %d: %.4f" % (yaw, c))
    if best is None or c < best[0]:
        best = (c, yaw)
_c, YAW = best
R0 = numpy.array(Matrix.Rotation(math.radians(YAW), 3, "Z"))
Qr = Qs @ R0.T
ctr0 = Qr.mean(axis=0)
k0 = float(numpy.mean(numpy.ptp(Ps, axis=0) / numpy.maximum(numpy.ptp(Qr, axis=0), 1e-6)))
# The similarity so far as a matrix: x -> s R x + t
S = k0
Rm = R0.copy()
Qf, _ = floor_fit(Qr)
T = Qf.mean(axis=0) - S * (Rm @ Qs.mean(axis=0))
# A few rounds of closest points (scale, a turn about the upright, a move).
for it in range(int(CFG.get("icp", 12))):
    Qx = (Qs @ Rm.T) * S + T
    near = numpy.array([Ps[TP.find(q)[1]] for q in Qx])
    mq, mp = Qx.mean(axis=0), near.mean(axis=0)
    A, B = Qx - mq, near - mp
    # (turn about Z only: 2D Procrustes in the floor plane)
    hxy = (A[:, :2].T @ B[:, :2])
    ang = math.atan2(hxy[0, 1] - hxy[1, 0], hxy[0, 0] + hxy[1, 1])
    Rz = numpy.array(Matrix.Rotation(ang, 3, "Z"))
    # (the scale stays the boxes': closest points pull a shape small)
    Rm = Rz @ Rm
    T = Rz @ (T - mq) + mp
Qx = (Qs @ Rm.T) * S + T
T[2] += Ps[:, 2].min() - Qx[:, 2].min()
print("BEAST fit: turn %d, scale %.4f, chamfer %.4f -> %.4f" % (YAW, S, _c, chamfer((Qs @ Rm.T) * S + T)))
M = Matrix.Translation(Vector(T.tolist())) @ (Matrix(Rm.tolist()).to_4x4() @ Matrix.Diagonal((S, S, S, 1)))
hi.data.transform(M)


# ------------------------------------------------------------ the legs
def group_of(me, names):
    """Each vertex's strongest group's name (None without one)."""
    gname = {g.index: g.name for g in old_mesh.vertex_groups}
    out = []
    for v in me.vertices:
        best = max(v.groups, key=lambda g: g.weight, default=None)
        out.append(gname.get(best.group) if best is not None else None)
    return out


def square_feet(legs, old_feet, shift, floor):
    """The Meshy model stands square, as the old one does (its walk keys
    swing each leg from a square stance; a Meshy cow came with a hind foot
    stepped 16 cm ahead of the other, and the ragdoll's hip found between
    them pulled a leg off the body as it lay). Each pair of legs (left and
    right, as listed) is put level: each foot moved to the pair's mean
    front-back place and the same width out, its lower leg bent there from
    the hock down (the hi mesh: the bake follows), shift updated."""
    QH = numpy.array([v.co[:] for v in hi.data.vertices])
    feet = old_feet + shift
    mid = feet.mean(axis=0)
    target = feet.copy()
    for a_ in range(0, len(legs), 2):
        b_ = a_ + 1
        along = (feet[a_][1] + feet[b_][1]) / 2
        out = (abs(feet[a_][0] - mid[0]) + abs(feet[b_][0] - mid[0])) / 2
        for k in (a_, b_):
            target[k] = (mid[0] + math.copysign(out, feet[k][0] - mid[0]), along)
    top = floor + OLD_H * float(CFG.get("hock", .33))
    near = numpy.linalg.norm(QH[:, None, :2] - feet[None, :, :2], axis=2)
    leg = near.argmin(axis=1)
    reach = near.min(axis=1) < OLD_H * .11
    t = numpy.clip((top - QH[:, 2]) / (top - floor), 0, 1)
    w = t * t * (3 - 2 * t) * reach * (QH[:, 2] < top)
    delta = (target - feet)[leg] * w[:, None]
    for i in numpy.nonzero(w > 0)[0]:
        v = hi.data.vertices[int(i)]
        v.co.x += float(delta[i][0])
        v.co.y += float(delta[i][1])
    hi.data.update()
    for k in range(len(legs)):
        print("BEAST leg %s: foot set square, %.3f, %.3f m" % (legs[k][-1], *(target[k] - feet[k])))
        shift[k] = target[k] - old_feet[k]


def realign_legs():
    """Each old leg moved (bones, keys and the old mesh the weights come
    from) to stand where the Meshy model's own leg stands: Meshy's legs are
    seldom at the old block legs' place, and a leg weighted by the nearest
    old face then rides the body or the wrong leg (stretching in the dead
    key). Config "legs": [[hip, knee, foot], ...] (old bone names), "torso"
    (the bone the legs hang from)."""
    legs = CFG.get("legs", [])
    if not legs or not CFG.get("realign", True):
        return
    torso = CFG.get("torso", "b0")
    owner = group_of(src_me, None)
    PV = numpy.array([v.co[:] for v in src_me.vertices])
    QH = numpy.array([v.co[:] for v in hi.data.vertices])
    floor = PV[:, 2].min()
    low_new = QH[QH[:, 2] < floor + OLD_H * .12]
    old_feet = []
    for chain in legs:
        ids = [i for i, n in enumerate(owner) if n == chain[-1] and PV[i, 2] < floor + OLD_H * .12]
        if not ids:
            ids = [i for i, n in enumerate(owner) if n == chain[-1]]
        old_feet.append(PV[ids, :2].mean(axis=0))
    old_feet = numpy.array(old_feet)
    shift = numpy.zeros_like(old_feet)
    for _ in range(4):
        at = old_feet + shift
        near = numpy.linalg.norm(low_new[:, None, :2] - at[None, :, :2], axis=2).argmin(axis=1)
        for k in range(len(legs)):
            mine = low_new[near == k]
            if len(mine):
                shift[k] = mine[:, :2].mean(axis=0) - old_feet[k]
    if CFG.get("square", True) and len(legs) % 2 == 0:
        square_feet(legs, old_feet, shift, floor)
    for k, chain in enumerate(legs):
        print("BEAST leg %s moved %.3f, %.3f m to the Meshy leg" % ("/".join(chain), shift[k][0], shift[k][1]))
    # The old mesh's legs (the weights' source) moved with them.
    for i, n in enumerate(owner):
        for k, chain in enumerate(legs):
            if n in chain:
                src_me.vertices[i].co.x += float(shift[k][0])
                src_me.vertices[i].co.y += float(shift[k][1])
    src_me.update()
    # The keys: each leg turns as before about its hip, now at its new place,
    # carried by the torso as if it had always hung there.
    pbs = arm.pose.bones
    AW = arm.matrix_world
    frames = sorted({int(round(f)) for f in FRAMES.values()})
    world = {}
    for f in frames:
        scene.frame_set(f)
        bpy.context.view_layer.update()
        world[f] = {pb.name: AW @ pb.matrix for pb in pbs}
    stand = world[STAND]
    want = {}
    for k, chain in enumerate(legs):
        d = Vector((float(shift[k][0]), float(shift[k][1]), 0.0))
        q = stand[chain[0]].translation + d
        for f in frames:
            q_f = world[f][torso] @ stand[torso].inverted() @ q
            s_f = q_f - world[f][chain[0]] @ stand[chain[0]].inverted() @ q
            for name in chain:
                want[(f, name)] = Matrix.Translation(s_f) @ world[f][name]
    for f in frames:
        scene.frame_set(f)
        for (ff, name), mw in want.items():
            if ff != f:
                continue
            pb = pbs[name]
            pb.matrix = AW.inverted() @ mw
            bpy.context.view_layer.update()
            for path in ("location", "rotation_quaternion", "scale"):
                pb.keyframe_insert(path, frame=f)
    act = arm.animation_data.action
    try:
        fcs = list(act.fcurves)
    except Exception:
        fcs = [fc for la in act.layers for st in la.strips for cb in st.channelbags for fc in cb.fcurves]
    for fc in fcs:
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    scene.frame_set(STAND)
    bpy.context.view_layer.update()


realign_legs()
OWNER = group_of(src_me, None)

# ------------------------------------------------------------ the game mesh
lo = hi.copy()
lo.data = hi.data.copy()
lo.name = KIND
scene.collection.objects.link(lo)
select([lo])
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.remove_doubles(threshold=0.0003)
bpy.ops.object.mode_set(mode="OBJECT")
for _ in range(5):
    lo.data.calc_loop_triangles()
    now = len(lo.data.loop_triangles)
    if now <= TRIS * 1.03:
        break
    d_ = lo.modifiers.new("dec", "DECIMATE")
    d_.ratio = TRIS / now
    bpy.ops.object.modifier_apply(modifier="dec")
lo.data.calc_loop_triangles()
print("BEAST mesh: %d triangles" % len(lo.data.loop_triangles))

# ------------------------------------------------------------ the weights
for g in old_mesh.vertex_groups:
    lo.vertex_groups.new(name=g.name)
dt = lo.modifiers.new("weights", "DATA_TRANSFER")
dt.object = src
dt.use_vert_data = True
dt.data_types_verts = {"VGROUP_WEIGHTS"}
dt.vert_mapping = "POLYINTERP_NEAREST"
dt.layers_vgroup_select_src = "ALL"
dt.layers_vgroup_select_dst = "NAME"
select([lo])
bpy.ops.object.modifier_apply(modifier="weights")
NB = len(lo.vertex_groups)
W = numpy.zeros((len(lo.data.vertices), NB))
for v in lo.data.vertices:
    for g in v.groups:
        W[v.index, g.group] = g.weight
# Each vertex its nearest old part's bone outright (the transfer blends
# across faces of two parts), then softened over a few rings.
W = (W == W.max(axis=1, keepdims=True)) * (W.max(axis=1, keepdims=True) > 0)
W = W / numpy.maximum(W.sum(axis=1, keepdims=True), 1e-9)
nbr = [[] for _ in range(len(lo.data.vertices))]
for e in lo.data.edges:
    a, b = e.vertices
    nbr[a].append(b)
    nbr[b].append(a)

# A bone's vertices in one piece: where the Meshy shape reaches past the old
# one (a long tail down by the hocks) the nearest old face is another part's
# (the tail's tip ridden by a hind leg, stretched into a blade when the legs
# go up). Each bone keeps its biggest connected piece (and any other at
# least 40% of it); the rest take their neighbours' bone, grown inward.
def one_piece(W):
    lab = numpy.where(W.max(axis=1) > 0, W.argmax(axis=1), -1)
    n = len(lab)
    moved = 0
    for g in numpy.unique(lab[lab >= 0]):
        seen = numpy.zeros(n, dtype=bool)
        parts = []
        for s in numpy.nonzero(lab == g)[0]:
            if seen[s]:
                continue
            stack, part = [s], []
            seen[s] = True
            while stack:
                i = stack.pop()
                part.append(i)
                for j in nbr[i]:
                    if not seen[j] and lab[j] == g:
                        seen[j] = True
                        stack.append(j)
            parts.append(part)
        big = max(len(p) for p in parts)
        for p in parts:
            if len(p) < big * .4:
                lab[p] = -1
                moved += len(p)
    while (lab < 0).any():
        took = 0
        new_lab = lab.copy()
        for i in numpy.nonzero(lab < 0)[0]:
            got = [lab[j] for j in nbr[i] if lab[j] >= 0]
            if got:
                new_lab[i] = max(set(got), key=got.count)
                took += 1
        lab = new_lab
        if not took:
            break
    out = numpy.zeros_like(W)
    ok = lab >= 0
    out[numpy.nonzero(ok)[0], lab[ok]] = 1
    print("BEAST weights: %d vertices off their bone's piece given their neighbours' bone" % moved)
    return out




def legs_below_hips(W):
    """No leg bone above its hip: the Meshy barrel is wider than the old
    block body, so its rump's and chest's sides lie nearest the old legs'
    outer faces and would swing out with the legs (a blade in the dead key).
    A leg's vertex higher than the old leg's top (and "leg_top" of the
    height more) is the torso's."""
    legs = CFG.get("legs", [])
    if not legs:
        return W
    torso = lo.vertex_groups[CFG.get("torso", "b0")].index
    co_ = numpy.array([v.co[:] for v in lo.data.vertices])
    scene.frame_set(STAND)
    bpy.context.view_layer.update()
    lab = W.argmax(axis=1)
    took = 0
    for chain in legs:
        top = max(src_me.vertices[i].co.z for i, n in enumerate(OWNER) if n == chain[0])
        top += OLD_H * float(CFG.get("leg_top", 0.0))
        ids = [lo.vertex_groups[n].index for n in chain]
        mask = numpy.isin(lab, ids) & (co_[:, 2] > top)
        W[mask] = 0
        W[mask, torso] = 1
        took += int(mask.sum())
        print("BEAST leg %s: top at %.3f m (standing %.3f)" % (chain[0], top, OLD_H))
    print("BEAST weights: %d vertices above their hips given to the torso" % took)
    return W




def split_moving(groups, pv, names):
    """A group's parts that the live keys move apart (a gator's jaw opening
    to bite, in the same ragdoll segment as its skull) are split off into
    their own group, parts that move together staying together. The dead
    keys ("down", "die_*") are not asked: the old block bodies come apart
    there and a smooth skin must not follow."""
    live = sorted({int(round(f)) for k, f in FRAMES.items() if k != "down" and not k.startswith("die")})
    mats = {}
    for f in live:
        scene.frame_set(f)
        bpy.context.view_layer.update()
        mats[f] = {pb.name: arm.matrix_world @ pb.matrix for pb in arm.pose.bones}
    scene.frame_set(STAND)
    bpy.context.view_layer.update()
    st = mats.get(STAND) or {pb.name: arm.matrix_world @ pb.matrix for pb in arm.pose.bones}
    tol = OLD_H * float(CFG.get("split_tol", .03))

    def apart(a_, b_):
        pts = pv[names == b_]
        if not len(pts):
            return 0.0
        c = Vector(pts.mean(axis=0).tolist())
        return max(((mats[f][a_] @ st[a_].inverted() @ c) - (mats[f][b_] @ st[b_].inverted() @ c)).length
                   for f in live)

    out = []
    for grp in groups:
        subs = []
        for b_ in grp:
            for sub in subs:
                if apart(sub[0], b_) < tol:
                    sub.append(b_)
                    break
            else:
                subs.append([b_])
        if len(subs) > 1:
            print("BEAST group %s split by the keys into %s" % (grp[0], [x[0] for x in subs]))
        out.extend(subs)
    return out


def heat_weights():
    """Weights by Blender's bone heat over a stand-in skeleton: each old part
    a bone along its own long axis (its vertices' main direction, end to
    end, the legs where realign_legs moved them). The old parts are blocks
    and the Meshy shape reaches past them (a long tail, a wider barrel), so
    the nearest old face is often another part's; heat follows the mesh
    itself, smooth over a joint and nothing across the body. Kind config
    "weights": "heat"."""
    pv = numpy.array([v.co[:] for v in src_me.vertices])
    names = numpy.array([n or "" for n in OWNER])
    tdata = bpy.data.armatures.new("heat")
    tarm = bpy.data.objects.new("heat", tdata)
    scene.collection.objects.link(tarm)
    select([tarm])
    bpy.ops.object.mode_set(mode="EDIT")
    made = 0
    # "groups": each a list of old bones that move as one in the ragdoll (a
    # BeastRig segment; the first, its biggest part, takes the weights): a
    # body built of many small blocks (the hog's bristles and slabs) whose
    # keys do not move them as one would tear a smooth skin apart.
    groups = CFG.get("groups") or [[g.name] for g in old_mesh.vertex_groups]
    if CFG.get("groups"):
        groups = split_moving(groups, pv, names)
    for grp in groups:
        if not grp:
            continue
        pts = pv[numpy.isin(names, grp)]
        if len(pts) < 4:
            continue
        g = old_mesh.vertex_groups[grp[0]]
        c = pts.mean(axis=0)
        ax = numpy.linalg.svd(pts - c, full_matrices=False)[2][0]
        pr = (pts - c) @ ax
        a_, b_ = c + ax * pr.min(), c + ax * pr.max()
        if numpy.linalg.norm(b_ - a_) < OLD_H * .01:
            b_ = a_ + numpy.array([0, 0, OLD_H * .01])
        eb = tdata.edit_bones.new(g.name)
        eb.head = Vector(a_.tolist())
        eb.tail = Vector(b_.tolist())
        made += 1
    bpy.ops.object.mode_set(mode="OBJECT")
    for g in lo.vertex_groups:
        g.remove(list(range(len(lo.data.vertices))))
    select([lo, tarm], tarm)
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    out = numpy.zeros((len(lo.data.vertices), len(lo.vertex_groups)))
    index = {g.name: i for i, g in enumerate(old_mesh.vertex_groups)}
    for v in lo.data.vertices:
        for g in v.groups:
            k = index.get(lo.vertex_groups[g.group].name)
            if k is not None:
                out[v.index, k] = g.weight
    for m in list(lo.modifiers):
        lo.modifiers.remove(m)
    wm2 = lo.matrix_world.copy()
    lo.parent = None
    lo.matrix_world = wm2
    bpy.data.objects.remove(tarm)
    # (groups the heat made beyond the old ones, none expected)
    for g in list(lo.vertex_groups)[len(old_mesh.vertex_groups):]:
        lo.vertex_groups.remove(g)
    bare = out.sum(axis=1) <= 0
    if bare.any():
        # (no heat reached: the old way, the nearest old part)
        out[bare] = W[bare]
    print("BEAST weights by heat: %d stand-in bones, %d vertices left to the nearest part" % (made, int(bare.sum())))
    return out / numpy.maximum(out.sum(axis=1, keepdims=True), 1e-9)


WEIGHTS = CFG.get("weights", "nearest")
if WEIGHTS == "heat":
    W = heat_weights()
else:
    W = legs_below_hips(W)
    W = one_piece(W)
keep = {lo.vertex_groups[n].index for n in CFG.get("rigid", []) if n in lo.vertex_groups}
# "hard": bones whose border is not softened from either side (a tail that
# turns square to the rump in the dead key: a soft root stretched into a blade).
hard = {lo.vertex_groups[n].index for n in CFG.get("hard", []) if n in lo.vertex_groups}
own = W.argmax(axis=1)
for _ in range(0 if WEIGHTS == "heat" else int(CFG.get("smooth", 2))):
    W2 = W.copy()
    for i, ns in enumerate(nbr):
        if ns and not (keep and own[i] in keep):
            if hard:
                ns = [j for j in ns if (own[j] in hard) == (own[i] in hard)]
                if not ns:
                    continue
            W2[i] = W[i] * .5 + W[ns].mean(axis=0) * .5
    W = W2
for i in range(len(W)):
    row = W[i]
    if (row > 0).sum() > 4:
        row[numpy.argsort(row)[:-4]] = 0
    W[i] = row / max(row.sum(), 1e-9)


def jaw_sides(W):
    """A jaw that opens (kind config "jaw": {"upper": bone, "lower": bone}):
    the Meshy head's closed mouth is cut along its lips. Each head vertex
    ahead of the old lower jaw's hinge goes wholly to the old part it is
    nearest of the two (the old jaws' own shape gives the mouth line).
    Returns each vertex's side (0 none, 1 upper, 2 lower)."""
    jaw = CFG.get("jaw")
    side = numpy.zeros(len(W), dtype=numpy.int32)
    if not jaw:
        return side
    up = lo.vertex_groups[jaw["upper"]].index
    dn = lo.vertex_groups[jaw["lower"]].index
    pv = numpy.array([v.co[:] for v in src_me.vertices])
    own = numpy.array([n or "" for n in OWNER])
    pu, pd = pv[own == jaw["upper"]], pv[own == jaw["lower"]]
    fr = CFG.get("front", [0.0, 1.0])
    fwd = numpy.array([fr[0], -fr[1], 0.0])
    fwd /= numpy.linalg.norm(fwd)
    hinge = float((pd @ fwd).min()) + OLD_H * float(jaw.get("hinge", 0.0))
    co_ = numpy.array([v.co[:] for v in lo.data.vertices])
    head = numpy.isin(W.argmax(axis=1), [up, dn]) & (co_ @ fwd > hinge)
    # The mouth line: in each slice along the snout, the old lower jaw's top
    # as a share of the old head's height there, put on the new head's.
    po = numpy.vstack([pu, pd])
    tip = float(max((po @ fwd).max(), (co_[head] @ fwd).max()))
    bins = numpy.linspace(hinge, tip, 9)
    share = []
    for k in range(8):
        a_, b_ = bins[k], bins[k + 1]
        so = po[(po @ fwd >= a_) & (po @ fwd <= b_)]
        sd = pd[(pd @ fwd >= a_) & (pd @ fwd <= b_)]
        if len(so) and len(sd):
            share.append((sd[:, 2].max() - so[:, 2].min()) / max(float(numpy.ptp(so[:, 2])), 1e-6))
        else:
            share.append(share[-1] if share else .4)
    share = numpy.clip(numpy.array(share) + float(jaw.get("lift", 0.0)), .1, .9)
    for k in range(8):
        a_, b_ = bins[k], bins[k + 1] + (1e-3 if k == 7 else 0)
        inb = head & (co_ @ fwd >= a_) & (co_ @ fwd < b_)
        if not inb.any():
            continue
        z0, z1 = co_[inb, 2].min(), co_[inb, 2].max()
        cut_z = z0 + share[k] * (z1 - z0)
        for i in numpy.nonzero(inb)[0]:
            side[i] = 2 if co_[i, 2] < cut_z else 1
    print("BEAST jaw line: %s of the head's height" % numpy.round(share, 2).tolist())
    for i in numpy.nonzero(head)[0]:
        lower = side[i] == 2
        side[i] = 2 if lower else 1
        W[i] = 0
        W[i, dn if lower else up] = 1
    print("BEAST jaw: %d upper and %d lower vertices ahead of the hinge" % ((side == 1).sum(), (side == 2).sum()))
    return side


JAW_SIDE = jaw_sides(W)
for g in lo.vertex_groups:
    g.remove(list(range(len(lo.data.vertices))))
for gi in range(NB):
    ids = numpy.nonzero(W[:, gi] > 1e-4)[0]
    for i in ids:
        lo.vertex_groups[gi].add([int(i)], float(W[i, gi]), "REPLACE")
print("BEAST weights: %d bones used" % int((W.max(axis=0) > .5).sum()))
# Back to the old rest pose: each vertex by its bones' moves undone.
Minv = {gi: numpy.array(POSE[lo.vertex_groups[gi].name].inverted()) for gi in range(NB)
        if lo.vertex_groups[gi].name in POSE}
co = numpy.array([v.co[:] for v in lo.data.vertices])
h = numpy.hstack([co, numpy.ones((len(co), 1))])
rest = numpy.zeros_like(co)
for gi, Mi in Minv.items():
    w = W[:, gi:gi + 1]
    if w.max() > 0:
        rest += (h @ Mi.T)[:, :3] * w
moved = float(numpy.linalg.norm(rest - co, axis=1).max())
for i, v in enumerate(lo.data.vertices):
    v.co = rest[i]
print("BEAST carried back to rest: %.3f m at most" % moved)


def cut_mouth():
    """The lips parted (jaw_sides) and each side's open edge capped, the caps
    marked (material 1) to be painted as the inside of the mouth."""
    if not JAW_SIDE.any():
        return
    bm = bmesh.new()
    bm.from_mesh(lo.data)
    bm.verts.ensure_lookup_table()
    lay = [int(x) for x in JAW_SIDE]

    def face_side(f):
        got = [lay[v.index] for v in f.verts]
        if not any(got):
            return 0
        return 2 if got.count(2) > got.count(1) else 1

    fs = {f: face_side(f) for f in bm.faces}
    cut = []
    for e in bm.edges:
        if len(e.link_faces) == 2:
            a_, b_ = (fs[f] for f in e.link_faces)
            if {a_, b_} == {1, 2} and all(lay[v.index] in (1, 2) for v in e.verts):
                cut.append(e)
    bmesh.ops.split_edges(bm, edges=cut)
    # (each parted vertex rides the jaw its faces are on)
    jaw = CFG["jaw"]
    gi = {1: lo.vertex_groups[jaw["upper"]].index, 2: lo.vertex_groups[jaw["lower"]].index}
    dl = bm.verts.layers.deform.active
    for v in bm.verts:
        sides = {fs.get(f, 0) for f in v.link_faces} - {0}
        if len(sides) == 1:
            sd = sides.pop()
            if v.is_valid and (lay[v.index] if v.index < len(lay) else 0) != sd or v.index >= len(lay):
                v[dl].clear()
                v[dl][gi[sd]] = 1.0
    # The mouth's inside: a bag from every lip edge back to a throat point
    # by the hinge (the upper lip's edges make the palate, the lower's the
    # floor and tongue), each lip vertex's place along its lip kept (teeth).
    t_lay = bm.verts.layers.float.new("mouth_t")
    s_lay = bm.verts.layers.float.new("mouth_s")
    dl = bm.verts.layers.deform.active
    open_edges = [e for e in bm.edges if e.is_boundary]
    lipv = {v for e in open_edges for v in e.verts}
    pts = numpy.array([v.co[:] for v in lipv])
    fr = CFG.get("front", [0.0, 1.0])
    fwd = numpy.array([fr[0], -fr[1], 0.0])
    fwd /= numpy.linalg.norm(fwd)
    along = pts @ fwd
    throat = pts.mean(axis=0) - fwd * (along.mean() - along.min()) * float(jaw.get("throat", .9))
    # (low in the head and riding the lower jaw: held between the jaws it
    # rose through the neck's top when the upper jaw lifted)
    throat[2] -= float(numpy.ptp(pts[:, 2])) * float(jaw.get("throat_low", .5))
    tv = bm.verts.new(Vector(throat.tolist()))
    tv[dl][gi[2]] = 1.0
    tv[t_lay] = 1.0
    for v in lipv:
        v[s_lay] = float(numpy.dot(numpy.array(v.co[:]), fwd))
    caps = []
    for e in open_edges:
        a_, b_ = e.verts
        f0 = e.link_faces[0] if e.link_faces else None
        sd = fs.get(f0, 1) or 1
        # (wound so it faces into the mouth: against the lip face's own loop)
        loop_ab = f0 is not None and any(l_.vert == a_ and l_.link_loop_next.vert == b_ for l_ in f0.loops)
        try:
            f = bm.faces.new((b_, a_, tv) if loop_ab else (a_, b_, tv))
        except ValueError:
            continue
        f.material_index = sd
        caps.append(f)
    for f in bm.faces:
        if f not in set(caps):
            f.material_index = 0
    n_caps = len(caps)
    bm.to_mesh(lo.data)
    bm.free()
    lo.data.update()
    print("BEAST mouth cut: %d edges parted, %d cap faces" % (len(cut), n_caps))


cut_mouth()

# ------------------------------------------------------------ unwrap, bake
# (baked at the standing key: the low mesh posed as the Meshy one stands)
select([lo])
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.0)
bpy.ops.uv.pack_islands(rotate=True, margin_method="FRACTION", margin=.004, shape_method="CONCAVE")
bpy.ops.object.mode_set(mode="OBJECT")
lo.parent = arm
mod = lo.modifiers.new("rig", "ARMATURE")
mod.object = arm
scene.frame_set(STAND)
bpy.context.view_layer.update()
old_mesh.hide_render = True
src.hide_render = True
CAPS = [(p_.index, p_.material_index) for p_ in lo.data.polygons if p_.material_index in (1, 2)]
lo.data.materials.clear()
mat = bpy.data.materials.new("bake")
mat.use_nodes = True
lo.data.materials.append(mat)
img = bpy.data.images.new("bake", TEX, TEX, alpha=False)
node = mat.node_tree.nodes.new("ShaderNodeTexImage")
node.image = img
mat.node_tree.nodes.active = node


def pixels(im):
    px = numpy.empty(len(im.pixels), dtype=numpy.float32)
    im.pixels.foreach_get(px)
    return px.reshape(-1, 4)


nimg = bpy.data.images.new("normals", TEX, TEX, alpha=False, float_buffer=True)
nimg.colorspace_settings.name = "Non-Color"
node.image = nimg
scene.cycles.samples = 1
select([lo])
bpy.ops.object.bake(type="NORMAL", normal_space="OBJECT", margin=TEX // 128, use_clear=True)
NORMALS = pixels(nimg)
node.image = img
for flag in ("visible_shadow", "visible_diffuse", "visible_glossy", "visible_transmission", "visible_volume_scatter"):
    setattr(lo, flag, False)
nx = NORMALS[:, 0] * 2 - 1
ny = NORMALS[:, 1] * 2 - 1
total = None
weight = None
kept = [hi.matrix_world.copy(), arm.matrix_world.copy()]
for k, angle in enumerate(TURNS):
    spin = Matrix.Rotation(math.radians(angle), 4, "Z")
    hi.matrix_world = spin @ kept[0]
    arm.matrix_world = spin @ kept[1]
    bpy.context.view_layer.update()
    scene.cycles.samples = 32 if k == 0 else 20
    select([hi, lo], lo)
    bpy.ops.object.bake(type="COMBINED", pass_filter={"EMIT", "DIRECT", "INDIRECT", "DIFFUSE"},
                        margin=TEX // 128, use_clear=True, use_selected_to_active=True,
                        cage_extrusion=OLD_H * .012, max_ray_distance=OLD_H * .05)
    px = pixels(img)
    c, sn = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    w = (numpy.clip(-(sn * nx + c * ny), 0, 1) ** 2 + 1e-4) * (px[:, :3].sum(axis=1) > .003)
    if total is None:
        total = px.copy()
        total[:, :3] *= w[:, None]
        weight = w.copy()
    else:
        total[:, :3] += px[:, :3] * w[:, None]
        weight += w
hi.matrix_world, arm.matrix_world = kept
bpy.context.view_layer.update()
found = weight > 0
total[found, :3] /= weight[found, None]
inside = NORMALS[:, :3].sum(axis=1) > .05
# The underside: the stage lights it from above and the sides only, so a
# belly baked near-black (a gator on its back showed a dark grey slab). Its
# own colour (the Meshy albedo) at the light the sides have, a little shaded.
select([hi, lo], lo)
bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, margin=TEX // 128, use_clear=True,
                    use_selected_to_active=True, cage_extrusion=OLD_H * .012, max_ray_distance=OLD_H * .05)
ALBEDO = pixels(img)[:, :3].copy()
nz = NORMALS[:, 2] * 2 - 1
lum3 = numpy.array([.299, .587, .114])
side_ok = found & inside & (nz > -.2) & (ALBEDO @ lum3 > .03)
ratio = float(numpy.median((total[side_ok, :3] @ lum3) / (ALBEDO[side_ok] @ lum3))) if side_ok.any() else 1.0
down = numpy.clip((-nz - .2) / .6, 0, 1)[:, None] * (inside & (ALBEDO.sum(axis=1) > .01))[:, None]
total[:, :3] = total[:, :3] * (1 - down) + ALBEDO * ratio * float(CFG.get("belly_light", .8)) * down
found = found | (down[:, 0] > 0)
print("BEAST underside: %d texels from the albedo at %.2f of its light" % (int((down > 0).sum()), ratio))
print("BEAST bake: %d of %d texels unreached" % (int((inside & ~found).sum()), int(inside.sum())))
rgb = total[:, :3].reshape(TEX, TEX, 3)
good = found.reshape(TEX, TEX).copy()
missing = (inside & ~found).reshape(TEX, TEX)
for _ in range(24):
    if not missing.any():
        break
    acc = numpy.zeros_like(rgb)
    cnt = numpy.zeros((TEX, TEX), dtype=numpy.float32)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
        g_ = numpy.roll(numpy.roll(good, dy, 0), dx, 1)
        acc += numpy.roll(numpy.roll(rgb, dy, 0), dx, 1) * g_[:, :, None]
        cnt += g_
    take = missing & (cnt > 0)
    rgb[take] = acc[take] / cnt[take][:, None]
    good |= take
    missing &= ~take
total[:, :3] = rgb.reshape(-1, 3)
total[:, 3] = 1
# The old look's light: the baked texels' middle light matched to the old
# texture's (both before the game's grade).
oimg = bpy.data.images.load(os.path.abspath(CFG["old_tex"]))
op = pixels(oimg)[:, :3]
lum = lambda a: a @ numpy.array([.299, .587, .114])  # noqa: E731
o_l = float(numpy.median(lum(op[op.sum(axis=1) > .03])))
n_l = float(numpy.median(lum(total[inside, :3])))
gain = float(numpy.clip(o_l / max(n_l, 1e-4), .6, 1.6)) * float(CFG.get("gain", 1.0))
total[:, :3] = numpy.clip(total[:, :3] * gain * numpy.array(CFG.get("tint", [1, 1, 1])), 0, 1)
print("BEAST gain %.3f to the old look's light" % gain)


def paint_mouth():
    """The mouth's inside painted: teeth along both lips (ivory, a tooth a
    pitch, upper ones hanging, lower ones standing), pale pink-cream palate
    above, a pink tongue below, the throat dark; colours dull enough for the
    game's palette."""
    if not CAPS:
        return
    uv = lo.data.uv_layers.active.data
    me_ = lo.data
    tl = me_.attributes.get("mouth_t")
    sl = me_.attributes.get("mouth_s")
    rgb = total[:, :3].reshape(TEX, TEX, 3)
    pitch = OLD_H * float(CFG["jaw"].get("pitch", .045))
    ivory, gum = numpy.array([.78, .74, .6]), numpy.array([.42, .22, .2])
    palate, tongue, throat_c = numpy.array([.66, .5, .45]), numpy.array([.55, .3, .29]), numpy.array([.12, .04, .04])
    n = 0
    for k, sd in CAPS:
        p_ = me_.polygons[k]
        vs = list(p_.vertices)
        pts = numpy.array([uv[li].uv[:] for li in p_.loop_indices]) * TEX
        tt = numpy.array([tl.data[v].value for v in vs])
        ss = numpy.array([sl.data[v].value for v in vs])
        a_, b_, c_ = pts[0], pts[1], pts[2]
        den = (b_[1] - c_[1]) * (a_[0] - c_[0]) + (c_[0] - b_[0]) * (a_[1] - c_[1])
        if abs(den) < 1e-9:
            continue
        lo_ = numpy.floor(pts.min(axis=0)).astype(int)
        hi_ = numpy.ceil(pts.max(axis=0)).astype(int) + 1
        for y in range(max(lo_[1], 0), min(hi_[1], TEX)):
            for x in range(max(lo_[0], 0), min(hi_[0], TEX)):
                px, py = x + .5, y + .5
                l1 = ((b_[1] - c_[1]) * (px - c_[0]) + (c_[0] - b_[0]) * (py - c_[1])) / den
                l2 = ((c_[1] - a_[1]) * (px - c_[0]) + (a_[0] - c_[0]) * (py - c_[1])) / den
                l3 = 1 - l1 - l2
                if min(l1, l2, l3) < -.05:
                    continue
                bw = numpy.clip(numpy.array([l1, l2, l3]), 0, 1)
                bw /= bw.sum()
                t = float(bw @ tt)
                lipw = bw * (tt < .5)
                sv = float(lipw @ ss / max(lipw.sum(), 1e-6))
                ph = (sv / pitch) % 1.0
                tooth = (1 - abs(2 * ph - 1))  # 0 at the gaps, 1 at a tooth's middle
                if t < .1 * tooth + .01:
                    col = ivory
                elif t < .16:
                    col = gum
                elif t > .72:
                    col = throat_c
                else:
                    col = palate if sd == 1 else tongue
                    col = col * (1 - .6 * (t - .26) / .46)
                rgb[y, x] = col
                n += 1
    total[:, :3] = rgb.reshape(-1, 3)
    print("BEAST mouth painted: %d texels" % n)


paint_mouth()
img.pixels.foreach_set(total.ravel())
img.filepath_raw = os.path.join(OUT, KIND + ".png")
img.file_format = "PNG"
img.save()
if "hurt" in meta_old.get("textures", []):
    # TODO: a hurt look (the people's blood splashes); the plain one for now.
    print("BEAST NOTE: %s has a hurt look; written as the plain look (no blood yet)" % KIND)
    img.filepath_raw = os.path.join(OUT, KIND + "_hurt.png")
    img.save()

# ------------------------------------------------------------ export
lo.data.materials.clear()
bpy.data.objects.remove(old_mesh)
bpy.data.objects.remove(src)
scene.frame_set(0)
select([lo, arm], arm)
bpy.ops.export_scene.gltf(
    filepath=os.path.join(OUT, KIND + ".glb"), export_format="GLB", use_selection=True,
    export_materials="NONE", export_yup=True, export_animations=True, export_skins=True,
    export_morph=False, export_force_sampling=False, export_def_bones=False,
)
view = bpy.data.materials.new(KIND + "_look")
view.use_nodes = True
vt = view.node_tree.nodes.new("ShaderNodeTexImage")
vt.image = bpy.data.images.load(os.path.join(OUT, KIND + ".png"))
view.node_tree.links.new(vt.outputs[0], view.node_tree.nodes["Principled BSDF"].inputs["Base Color"])
lo.data.materials.append(view)
hi.hide_render = True
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, KIND + ".blend"))
lo.data.calc_loop_triangles()
entry = dict(meta_old)
entry["faces"] = float(len(lo.data.loop_triangles))
entry["meshy"] = True
if CFG.get("legs"):
    # (BeastRig takes the legs' bones from here: a smooth skin has no blocks)
    entry["beast_legs"] = CFG["legs"]
meta_path = os.path.join(OUT, "actors.json")
meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
meta[KIND] = entry
json.dump(meta, open(meta_path, "w"), indent=1, sort_keys=True)
print("BEAST %s done: %d triangles on the old %d-bone armature" % (KIND, len(lo.data.loop_triangles), len(arm.data.bones)))
