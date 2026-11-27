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
from mathutils import Matrix, Quaternion, Vector
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

# ------------------------------------------------------------ kept old parts
# "keep_parts": old parts kept exactly as they are - rigid on their own
# bones, their old texels pasted into the new atlas (a boss's vehicle and
# weapons: the Swamp King's airboat, punt gun, gig and crown). A list of
# bones, or {"except": [bones]} (every bone but those). The Meshy model is
# fitted onto the other parts only and weighted from them alone. "fit_skip"
# (bones also left out of the fit only: arms the Meshy A-pose does not match).
_gname0 = {g.index: g.name for g in old_mesh.vertex_groups}
OWN0 = numpy.array([(_gname0.get(max(v.groups, key=lambda g: g.weight).group) if len(v.groups) else "") or ""
                    for v in src_me.vertices])
KEEP = set()
if CFG.get("keep_parts"):
    _kp = CFG["keep_parts"]
    KEEP = ({g.name for g in old_mesh.vertex_groups} - set(_kp["except"])) if isinstance(_kp, dict) else set(_kp)
FIT = ~numpy.isin(OWN0, sorted(KEEP | set(CFG.get("fit_skip", []))))
P_FIT = P[FIT]
if KEEP:
    print("BEAST keep_parts: %d old bones kept as they are, the fit on %d of %d old vertices" % (
        len(KEEP), int(FIT.sum()), len(P)))

def part_line(bone):
    pts = P[OWN0 == bone]
    c = pts.mean(axis=0)
    ax = numpy.linalg.svd(pts - c, full_matrices=False)[2][0]
    pr = (pts - c) @ ax
    rad = float(numpy.median(numpy.linalg.norm((pts - c) - numpy.outer(pr, ax), axis=1)))
    return Vector((c + ax * pr.min()).tolist()), Vector((c + ax * pr.max()).tolist()), Vector(c.tolist()), rad


# ------------------------------------------------------------ the new mesh
new = import_glb(CFG["meshy"])
hi = next(o for o in new if o.type == "MESH")
# (a rigged Meshy glb: its bones' heads kept for "pose_arms")
M_HEADS = {}
for o in new:
    if o.type == "ARMATURE":
        M_HEADS = {b.name: o.matrix_world @ b.head_local for b in o.data.bones}
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
Q_FIT = Q0
if CFG.get("pose_arms"):
    # (the A-pose arms left out of the fit: they are posed after it)
    _ag = {g.index for g in hi.vertex_groups if "Arm" in g.name or "Hand" in g.name}
    _qa = numpy.array([sum(g.weight for g in v.groups if g.group in _ag) > .3 for v in hi.data.vertices])
    Q_FIT = Q0[~_qa]


def box_k(A, B):
    """The uniform scale of B's box onto A's ("fit_scale": "z" - by height
    alone: a caped, pot-bellied King measures wide)."""
    if CFG.get("fit_scale") == "z":
        return float(numpy.ptp(A[:, 2]) / max(numpy.ptp(B[:, 2]), 1e-6))
    return float(numpy.mean(numpy.ptp(A, axis=0) / numpy.maximum(numpy.ptp(B, axis=0), 1e-6)))


def tree_of(pts):
    t = KDTree(len(pts))
    for i, p in enumerate(pts):
        t.insert(p, i)
    t.balance()
    return t


Ps = P_FIT[:: max(1, len(P_FIT) // 3000)]
Qs = Q_FIT[:: max(1, len(Q_FIT) // 3000)]
TP = tree_of(Ps)


def chamfer(Qx):
    tq = tree_of(Qx)
    a = numpy.mean([TP.find(q)[2] for q in Qx])
    b = numpy.mean([tq.find(p)[2] for p in Ps])
    return a + b


def floor_fit(Qx):
    """Uniform scale by height and length, the boxes' middles together, on the floor."""
    k = box_k(Ps, Qx)
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
k0 = box_k(Ps, Qr)
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
M_HEADS = {n_: M @ h_ for n_, h_ in M_HEADS.items()}
if float(CFG.get("scale", 1.0)) != 1.0:
    # (a box fit counts an upright tail: BLUE came out 7% taller at the
    # shoulder than a hound stands beside Mundell, actor_check)
    q_ = numpy.array([v.co[:] for v in hi.data.vertices])
    piv = Vector(((q_[:, 0].min() + q_[:, 0].max()) / 2, (q_[:, 1].min() + q_[:, 1].max()) / 2, q_[:, 2].min()))
    k_ = float(CFG["scale"])
    hi.data.transform(Matrix.Translation(piv) @ Matrix.Diagonal((k_, k_, k_, 1)) @ Matrix.Translation(-piv))
    print("BEAST scaled %.3f about its feet" % k_)


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
    if CFG.get("realign") == "mesh":
        # The Meshy legs moved onto the old ones instead (bones and keys left
        # as they are): a gait whose speed was tuned to the old feet's paths
        # (BLUE's, hound_pace) keeps them. Each leg's column shifted whole
        # below the old leg's top, fading out over a band above it.
        QH = numpy.array([v.co[:] for v in hi.data.vertices])
        feet = old_feet + shift
        near = numpy.linalg.norm(QH[:, None, :2] - feet[None, :, :2], axis=2)
        # (each leg's move fades out smoothly up its haunch or shoulder and
        # out across the body; the legs' moves add up, so the left and right
        # moves meet without a seam at the middle: a hard edge streaked the
        # texture)
        band = OLD_H * float(CFG.get("mesh_band", .15))
        r1, r2 = OLD_H * .07, OLD_H * float(CFG.get("mesh_reach", .2))
        delta = numpy.zeros((len(QH), 2))
        for k, chain in enumerate(legs):
            top = max(PV[i_, 2] for i_, n in enumerate(owner) if n == chain[0])
            t_ = numpy.clip((top + band - QH[:, 2]) / (2 * band), 0, 1)
            h_ = numpy.clip((r2 - near[:, k]) / (r2 - r1), 0, 1)
            w = (t_ * t_ * (3 - 2 * t_)) * (h_ * h_ * (3 - 2 * h_))
            delta -= w[:, None] * shift[k][None, :2]
            print("BEAST leg %s: the Meshy leg moved %.3f, %.3f m onto the old one" % (chain[-1], -shift[k][0], -shift[k][1]))
        for i_ in numpy.nonzero(numpy.abs(delta).sum(axis=1) > 1e-6)[0]:
            v = hi.data.vertices[int(i_)]
            v.co.x += float(delta[i_][0])
            v.co.y += float(delta[i_][1])
        hi.data.update()
        return
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
        for f in frames:
            # (the old leg's own motion, done where it stood, then carried
            # the step d over by the torso's turn: no joint is assumed, the
            # old block legs turn about their parts' own middles)
            r_f = (world[f][torso] @ stand[torso].inverted()).to_3x3()
            # (a small turn of the torso - a gait's bob - is left out: the
            # feet then tread exactly the old paths, which the gaits' speeds
            # were tuned to; a big one - sitting, lying - carries the leg)
            if r_f.to_quaternion().angle < math.radians(float(CFG.get("carry_turn", 15))):
                r_f = Matrix.Identity(3)
            for name in chain:
                want[(f, name)] = Matrix.Translation(r_f @ d) @ world[f][name] @ Matrix.Translation(-d)
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


def attach_chains():
    """ "attach" [{chain [upper, fore, hand], parent, follow [bones]}]: an old
    block arm's keys re-made so each part hangs from the one above at its
    joint (the old parts turn about their own middles: a raised block arm's
    top swung clear of the trunk, and a smooth skin tore open at the
    shoulder). Each part's turn is kept; it is moved so its joint end meets
    the part above at that joint, every key; "follow" bones (the gun in the
    hand) moved with the hand."""
    if not CFG.get("attach"):
        return
    pbs = arm.pose.bones
    AW = arm.matrix_world
    rest = {pb.name: AW @ pb.bone.matrix_local for pb in pbs}
    frames = sorted({int(round(f)) for f in FRAMES.values()})
    D = {}
    for f in frames:
        scene.frame_set(f)
        bpy.context.view_layer.update()
        D[f] = {pb.name: (AW @ pb.matrix) @ rest[pb.name].inverted() for pb in pbs}
    for at in CFG["attach"]:
        ch = at["chain"]
        # "ease" {key: share}: that key's arm turns eased that share back
        # toward the standing key's (the pain key's raised arm swept across
        # the face)
        for kname, share in at.get("ease", {}).items():
            if kname not in FRAMES:
                continue
            f_ = int(round(FRAMES[kname]))
            for b_ in ch:
                q_ = D[f_][b_].to_quaternion()
                D[f_][b_] = Quaternion().slerp(q_, 1.0 - float(share)).to_matrix().to_4x4()
        lines = [part_line(b_) for b_ in ch]
        ua, ub = lines[0][0], lines[0][1]
        sh = ua if ua.z > ub.z else ub
        u_lo = ub if sh is ua else ua
        joints = [sh]
        prev_lo = u_lo
        for k in range(1, len(ch)):
            a_, b_ = lines[k][0], lines[k][1]
            near_, far_ = (a_, b_) if (a_ - prev_lo).length < (b_ - prev_lo).length else (b_, a_)
            joints.append((prev_lo + near_) / 2)
            prev_lo = far_
        worst = 0.0
        ride = at.get("ride")
        if ride and len(ch) == 3:
            # "ride": the hand keeps its grip on that old part (the punt gun)
            # in every key - it rides the gun exactly as at the standing key -
            # and the arm reaches it, the elbow toward the old elbow (two
            # bones from the joined shoulder).
            S0 = D[STAND]
            L1 = (joints[1] - joints[0]).length
            L2 = (joints[2] - joints[1]).length
            gap = 0.0
            # (the live keys only: in the falls the gun flies from his hand)
            dead = {int(round(v)) for k, v in FRAMES.items() if k == "down" or k.startswith("die")}
            for f in frames:
                if f in dead:
                    up = D[f][at["parent"]]
                    new = {}
                    for k, b_ in enumerate(ch):
                        above = up if k == 0 else new[ch[k - 1]]
                        new[b_] = Matrix.Translation(above @ joints[k] - D[f][b_] @ joints[k]) @ D[f][b_]
                    scene.frame_set(f)
                    for b_, Dn in new.items():
                        pb = pbs[b_]
                        pb.matrix = AW.inverted() @ Dn @ rest[b_]
                        bpy.context.view_layer.update()
                        for path in ("location", "rotation_quaternion", "scale"):
                            pb.keyframe_insert(path, frame=f)
                    continue
                Dh = D[f][ride] @ S0[ride].inverted() @ S0[ch[2]]
                sh_f = D[f][at["parent"]] @ joints[0]
                wr_f = Dh @ joints[2]
                pole = D[f][ch[0]] @ joints[1]
                d_ = wr_f - sh_f
                dist = min(max(d_.length, .3 * (L1 + L2)), .999 * (L1 + L2))
                gap = max(gap, d_.length - dist)
                dn = d_.normalized()
                x_ = (L1 * L1 - L2 * L2 + dist * dist) / (2 * dist)
                h_ = math.sqrt(max(L1 * L1 - x_ * x_, 0.0))
                u = (pole - sh_f) - dn * (pole - sh_f).dot(dn)
                u = u.normalized() if u.length > 1e-6 else Vector((0, 0, -1))
                el_f = sh_f + dn * x_ + u * h_
                ru = D[f][ch[0]].to_quaternion()
                ru = (ru @ (joints[1] - joints[0])).rotation_difference(el_f - sh_f) @ ru
                rf = D[f][ch[1]].to_quaternion()
                rf = (rf @ (joints[2] - joints[1])).rotation_difference(wr_f - el_f) @ rf
                new = {ch[0]: Matrix.Translation(sh_f) @ ru.to_matrix().to_4x4() @ Matrix.Translation(-joints[0]),
                       ch[1]: Matrix.Translation(el_f) @ rf.to_matrix().to_4x4() @ Matrix.Translation(-joints[1]),
                       ch[2]: Dh}
                scene.frame_set(f)
                for b_, Dn in new.items():
                    pb = pbs[b_]
                    pb.matrix = AW.inverted() @ Dn @ rest[b_]
                    bpy.context.view_layer.update()
                    for path in ("location", "rotation_quaternion", "scale"):
                        pb.keyframe_insert(path, frame=f)
            print("BEAST attach %s riding %s: the arm reaches it, %.3f m short at most" % ("/".join(ch), ride, gap))
            continue
        for f in frames:
            up = D[f][at["parent"]]
            new = {}
            for k, b_ in enumerate(ch):
                above = up if k == 0 else new[ch[k - 1]]
                d = above @ joints[k] - D[f][b_] @ joints[k]
                worst = max(worst, d.length)
                new[b_] = Matrix.Translation(d) @ D[f][b_]
            dh = new[ch[-1]].to_translation() - D[f][ch[-1]].to_translation()
            for b_ in at.get("follow", []):
                new[b_] = Matrix.Translation(dh) @ D[f][b_]
            scene.frame_set(f)
            for b_, Dn in new.items():
                pb = pbs[b_]
                pb.matrix = AW.inverted() @ Dn @ rest[b_]
                bpy.context.view_layer.update()
                for path in ("location", "rotation_quaternion", "scale"):
                    pb.keyframe_insert(path, frame=f)
        print("BEAST attach %s to %s: joints met, moved up to %.3f m" % ("/".join(ch), at["parent"], worst))
    scene.frame_set(STAND)
    bpy.context.view_layer.update()


attach_chains()
OWNER = group_of(src_me, None)
# (the standing key's moves again: the legs' changed with the realignment)
scene.frame_set(STAND)
bpy.context.view_layer.update()
POSE = {pb.name: arm.matrix_world @ pb.matrix @ pb.bone.matrix_local.inverted() @ arm.matrix_world.inverted()
        for pb in arm.pose.bones}

# ------------------------------------------------------------ arms and hands
# "pose_arms" {side: {upper, fore, hand}} (old bones): the Meshy A-pose arms
# (a rigged Meshy glb, its own weights) bent onto the old arm parts at the
# standing key - the elbow toward the old one, the wrist onto its target -
# so each vertex is weighted from the old part it lies on. "grip_hands"
# {side: {gear [old bones], palm [x,y,z], cross deg} | {curl}}: Meshy's
# mitten hand cut off and a hands.py hand put on: closed round the old held
# thing (palm toward it from "palm", across its axis at least "cross"
# degrees, every finger wrapped joint by joint), or hanging relaxed ("curl").
# The hands ride their old hand bones rigidly (fingers set, no bones).
HAND_OBJS = {}
HAND_BONES = {}
ARM_SEGS = {}


def pose_and_hands():
    if not CFG.get("pose_arms"):
        return
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import hands  # noqa: E402

    me = hi.data
    # (the glb's vertices split at its UV seams welded first: their weights
    # differ a little, so the posed arm opened cracks along the seams, which
    # the lit bake drew as dark stitch lines)
    _bw = bmesh.new()
    _bw.from_mesh(me)
    _nv = len(_bw.verts)
    bmesh.ops.remove_doubles(_bw, verts=_bw.verts, dist=1e-5)
    print("BEAST Meshy seams welded: %d vertices" % (_nv - len(_bw.verts)))
    _bw.to_mesh(me)
    _bw.free()
    me.update()
    co = numpy.array([v.co[:] for v in me.vertices])
    gidx = {g.name: g.index for g in hi.vertex_groups}
    Wg = numpy.zeros((len(co), len(gidx)))
    for v in me.vertices:
        for g in v.groups:
            Wg[v.index, g.group] = g.weight
    Wg /= numpy.maximum(Wg.sum(axis=1, keepdims=True), 1e-9)
    # The Meshy texture, for the hands' skin colour.
    img_ = None
    for m_ in me.materials:
        if m_ and m_.use_nodes:
            for n_ in m_.node_tree.nodes:
                if n_.type == "TEX_IMAGE" and n_.image:
                    img_ = n_.image
    cut = numpy.zeros(len(co), dtype=bool)
    grip = CFG.get("grip_hands", {})
    for side, cfg in CFG["pose_arms"].items():
        S_ = "Left" if side == "l" else "Right"
        sh, el, wr = (Vector(M_HEADS[S_ + n_]) for n_ in ("Arm", "ForeArm", "Hand"))
        L1, L2 = (el - sh).length, (wr - el).length
        ua, ub, _uc, _ur = part_line(cfg["upper"])
        fa, fb, _fc, _fr = part_line(cfg["fore"])
        u_lo = ua if ua.z < ub.z else ub
        f_near, f_far = (fa, fb) if (fa - u_lo).length < (fb - u_lo).length else (fb, fa)
        e_old = (u_lo + f_near) / 2
        w_old = f_far
        _ha, _hb, h_c, _hr = part_line(cfg["hand"])
        fdir = (w_old - e_old).normalized()
        g = grip.get(side, {})
        hsel = Wg[:, gidx[S_ + "Hand"]] > .5
        hc0 = Vector(co[hsel].mean(axis=0).tolist())
        # (the Meshy hand's own size, before posing: build_actor's measure)
        a_m = (hc0 - wr).normalized()
        mid = Vector((-1.0 if side == "l" else 1.0, 0.0, 0.0))
        n_m = (mid - a_m * mid.dot(a_m)).normalized()
        t_m = (Vector((0, -1, 0)) - a_m * (-a_m.y) - n_m * (-n_m.y)).normalized()
        rel = co[hsel] - numpy.array(wr[:])
        length = float((rel @ numpy.array(a_m[:])).max())
        width = float(numpy.ptp(numpy.percentile(rel @ numpy.array(t_m[:]), [5, 95])))
        thick = float(numpy.ptp(numpy.percentile(rel @ numpy.array(n_m[:]), [5, 95])))
        fsel = Wg[:, gidx[S_ + "ForeArm"]] > .5
        rf = co[fsel] - numpy.array(wr[:])
        near = rf[numpy.abs(rf @ numpy.array(a_m[:])) < .025]
        wrist_r = float(numpy.median(numpy.linalg.norm(near - numpy.outer(near @ numpy.array(a_m[:]), numpy.array(a_m[:])), axis=1))) if len(near) else width * .3
        length = min(length, float(numpy.ptp(P_FIT[:, 2])) * float(CFG.get("hand_share", .11)))
        width = min(width, length * .5)
        thick = min(thick, length * .2)
        if g.get("gear"):
            gpts = P[numpy.isin(OWN0, g["gear"])]
            ga, gb, _gc, grad = part_line(g["gear"][0])
            gax = (gb - ga).normalized()
            C = ga + gax * (h_c - ga).dot(gax)
            n = Vector(g.get("palm", [0, 0, 1]))
            n = (n - gax * n.dot(gax)).normalized()
            a0 = (fdir - n * fdir.dot(n)).normalized()
            gp = (gax - n * gax.dot(n)).normalized()
            if gp.dot(a0) < 0:
                gp = -gp
            q = n.cross(gp)
            if q.dot(a0) < 0:
                q = -q
            th = math.atan2(a0.dot(q), a0.dot(gp))
            th = max(th, math.radians(float(g.get("cross", 55))))
            a = (gp * math.cos(th) + q * math.sin(th)).normalized()
            wt = C - n * (grad + thick * .5) - a * (.585 * length * float(g.get("along", .85)))
        else:
            a = fdir
            n = (mid - a * mid.dot(a)).normalized()
            wt = w_old
        t = a.cross(n) if side == "r" else n.cross(a)
        # Two bones to the wrist target, the elbow toward the old elbow.
        d = wt - sh
        dist = min(max(d.length, .3 * (L1 + L2)), .995 * (L1 + L2))
        dn = d.normalized()
        x_ = (L1 * L1 - L2 * L2 + dist * dist) / (2 * dist)
        h_ = math.sqrt(max(L1 * L1 - x_ * x_, 0.0))
        e_old = e_old + Vector(cfg.get("elbow_shift", [0, 0, 0]))
        u = (e_old - sh) - dn * (e_old - sh).dot(dn)
        u = u.normalized() if u.length > 1e-6 else Vector((0, 0, -1))
        el2 = sh + dn * x_ + u * h_
        R1 = (el - sh).rotation_difference(el2 - sh)
        w1 = el2 + R1 @ (wr - el)
        R2 = (w1 - el2).rotation_difference(wt - el2) @ R1
        w2 = el2 + R2 @ (wr - el)
        stretch = wt - w2
        print("BEAST arm %s: upper %.3f, fore %.3f m; wrist target %.3f m off reach, the forearm stretched %.3f m" % (
            side, L1, L2, d.length - dist, stretch.length))
        print("BEAST arm %s: the wrist bent %.0f degrees" % (side, math.degrees((R2 @ (wr - el)).angle(a))))
        R1m, R2m = R1.to_matrix(), R2.to_matrix()
        fa_ = (wr - el)
        for i in numpy.nonzero(Wg[:, [gidx[S_ + "Arm"], gidx[S_ + "ForeArm"], gidx[S_ + "Hand"]]].sum(axis=1) > 0)[0]:
            v = Vector(co[i].tolist())
            wu, wf, wh = Wg[i, gidx[S_ + "Arm"]], Wg[i, gidx[S_ + "ForeArm"]], Wg[i, gidx[S_ + "Hand"]]
            pu = sh + R1m @ (v - sh)
            s_ = min(max((v - el).dot(fa_) / max(fa_.length_squared, 1e-9), 0.0), 1.0)
            pf = el2 + R2m @ (v - el) + stretch * s_
            ph = el2 + R2m @ (v - el) + stretch
            co[i] = numpy.array((v * (1 - wu - wf - wh) + pu * wu + pf * wf + ph * wh)[:])
        # (the posed Meshy arm's bones and girth, for "arm_reach")
        for b_, (p0, p1), gname in ((cfg["upper"], (sh, el2), "Arm"), (cfg["fore"], (el2, wt), "ForeArm")):
            sel_ = Wg[:, gidx[S_ + gname]] > .5
            ab_ = numpy.array((p1 - p0)[:])
            t_ = numpy.clip((co[sel_] - numpy.array(p0[:])) @ ab_ / max(float(ab_ @ ab_), 1e-9), 0, 1)
            d_ = numpy.linalg.norm(co[sel_] - (numpy.array(p0[:]) + t_[:, None] * ab_), axis=1)
            ARM_SEGS[b_] = (p0.copy(), p1.copy(), float(numpy.percentile(d_, 20)) if len(d_) else .06)
            print("BEAST arm %s %s: girth %.3f m" % (side, gname, ARM_SEGS[b_][2]))
        # The Meshy mitten cut off past the wrist (now at the target).
        a_p = (R2m @ a_m).normalized()
        cut |= (Wg[:, gidx[S_ + "Hand"]] > .35) & (((co - numpy.array(wt[:])) @ numpy.array(a_p[:])) > .004)
        # Its skin colour from the Meshy texture under the hand.
        skin = numpy.array([.62, .42, .33])
        if img_ is not None:
            iw, ih = img_.size
            ipx = numpy.empty(iw * ih * 4, dtype=numpy.float32)
            img_.pixels.foreach_get(ipx)
            ipx = ipx.reshape(ih, iw, 4)
            uvl = me.uv_layers.active.data
            cols = []
            for poly in me.polygons:
                if hsel[poly.vertices[0]]:
                    uv_ = uvl[poly.loop_indices[0]].uv
                    cols.append(ipx[min(ih - 1, int(uv_.y * ih)), min(iw - 1, int(uv_.x * iw)), :3])
            if cols:
                skin = numpy.median(numpy.array(cols), axis=0)
        if g.get("skin_rgb"):
            skin = numpy.array(g["skin_rgb"], dtype=float) / 255.0
        hnd = hands.build_meshy(side, wt, a, n, t, length, width, thick, wrist_r, "hand_" + side)
        if g.get("gear"):
            gp_ = [Vector(p_.tolist()) for p_ in gpts if (Vector(p_.tolist()) - hnd.middle).length < .3]
            curls, rep_ = hands.wrap_curls(hnd, gp_)
            print("BEAST hand %s: wrapped round %s, finger gaps %s" % (side, g["gear"][0], {
                c_: round(float(r_[0]) * 100, 1) for c_, r_ in rep_.items()}))
        else:
            rc = float(g.get("curl", 1.0))
            curls = {c_: hands.spread(c_, rc if c_ != "th" else rc * .45) for c_ in hnd.chains}
        moves = hands.curl_moves(hnd, curls)
        hm = hnd.obj.data
        hg = {gg.index: gg.name for gg in hnd.obj.vertex_groups}
        for v in hm.vertices:
            acc = Vector((0, 0, 0))
            tw = 0.0
            for gg in v.groups:
                Mv = moves.get(hg[gg.group])
                if Mv is not None and gg.weight > 0:
                    acc += (Mv @ v.co) * gg.weight
                    tw += gg.weight
            if tw > 0:
                v.co = acc + v.co * max(0.0, 1 - tw) if tw < 1 else acc / tw
        hm.update()
        # Its look: the sculpted hand's painted skin (its own UVs) turned to
        # this body's skin, lit by the bake's stage like the rest.
        mat = bpy.data.materials.new("hand_" + side)
        mat.use_nodes = True
        nt = mat.node_tree
        nt.nodes.clear()
        o_ = nt.nodes.new("ShaderNodeOutputMaterial")
        bs = nt.nodes.new("ShaderNodeBsdfDiffuse")
        tx = nt.nodes.new("ShaderNodeTexImage")
        tx.image = bpy.data.images.load(os.path.join(hands.MASTER, "hand_master.png"), check_existing=True)
        uvn = nt.nodes.new("ShaderNodeUVMap")
        uvn.uv_map = "handuv"
        nt.links.new(uvn.outputs[0], tx.inputs[0])
        mpx = numpy.array(tx.image.pixels[:]).reshape(-1, 4)[:, :3]
        kk = numpy.clip(skin / numpy.maximum(numpy.median(mpx[mpx.sum(axis=1) > .15], axis=0), 1e-3), .2, 3.0)
        mx_ = nt.nodes.new("ShaderNodeMix")
        mx_.data_type = "RGBA"
        mx_.blend_type = "MULTIPLY"
        mx_.inputs[0].default_value = 1.0
        mx_.inputs[7].default_value = (float(kk[0]), float(kk[1]), float(kk[2]), 1)
        nt.links.new(tx.outputs[0], mx_.inputs[6])
        nt.links.new(mx_.outputs[2], bs.inputs[0])
        nt.links.new(bs.outputs[0], o_.inputs[0])
        hm.materials.clear()
        hm.materials.append(mat)
        HAND_OBJS[side] = hnd.obj
        HAND_BONES[side] = (cfg["fore"], cfg["hand"])
        print("BEAST hand %s: %.3f m long, %.3f wide, %.3f thick, skin %s" % (
            side, length, width, thick, numpy.round(skin * 255).astype(int).tolist()))
    for i, v in enumerate(me.vertices):
        v.co = co[i]
    bm_ = bmesh.new()
    bm_.from_mesh(me)
    bm_.verts.ensure_lookup_table()
    bmesh.ops.delete(bm_, geom=[bm_.verts[int(i)] for i in numpy.nonzero(cut)[0]], context="VERTS")
    bm_.to_mesh(me)
    bm_.free()
    me.update()
    print("BEAST Meshy mittens cut off: %d vertices" % int(cut.sum()))


pose_and_hands()
if M_HEADS:
    # (a rigged Meshy glb's own weights are done with: left on, they would
    # outweigh the old parts' and ride no old bone - but for "arm_weights":
    # "meshy" the arms' are kept as mw_<old bone> groups)
    _keep_mw = {}
    if CFG.get("arm_weights") == "meshy":
        for _sd, _c in CFG.get("pose_arms", {}).items():
            _S = "Left" if _sd == "l" else "Right"
            _keep_mw.update({_S + "Arm": _c["upper"], _S + "ForeArm": _c["fore"], _S + "Hand": _c["hand"]})
    for _g in list(hi.vertex_groups):
        if _g.name in _keep_mw:
            _g.name = "mw_" + _keep_mw[_g.name]
        else:
            hi.vertex_groups.remove(_g)

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
if CFG.get("smooth_normals"):
    # (the Meshy glb's custom split normals, carried through the decimation,
    # were hard at many edges: the bake's rays parted there - stitch-like
    # dark seams along the arms - and the game drew facets)
    for _ob in (lo, hi):
        select([_ob])
        try:
            bpy.ops.mesh.customdata_custom_splitnormals_clear()
        except RuntimeError:
            pass
        for _p in _ob.data.polygons:
            _p.use_smooth = True
for _side, _ho in HAND_OBJS.items():
    # (a copy into the bake source: the hand lit with the body)
    _hc = _ho.copy()
    _hc.data = _ho.data.copy()
    scene.collection.objects.link(_hc)
    if "handuv" not in hi.data.uv_layers:
        hi.data.uv_layers.new(name="handuv")
        hi.data.uv_layers.active = hi.data.uv_layers[0]
    select([hi, _hc], hi)
    bpy.ops.object.join()

# ------------------------------------------------------------ the weights
for g in old_mesh.vertex_groups:
    lo.vertex_groups.new(name=g.name)
dt = lo.modifiers.new("weights", "DATA_TRANSFER")
if KEEP:
    # (weights from the fitted parts alone: the kept ones are not skin)
    src_fit = src.copy()
    src_fit.data = src.data.copy()
    scene.collection.objects.link(src_fit)
    _b = bmesh.new()
    _b.from_mesh(src_fit.data)
    _b.verts.ensure_lookup_table()
    bmesh.ops.delete(_b, geom=[_b.verts[int(i)] for i in numpy.nonzero(numpy.isin(OWN0, sorted(KEEP)))[0]],
                     context="VERTS")
    _b.to_mesh(src_fit.data)
    _b.free()
    src_fit.hide_render = True
    dt.object = src_fit
else:
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
# (the Meshy rig's arm weights, "arm_weights", taken out before the old
# parts' nearest bone is chosen)
MW = {g.name[3:]: W[:, g.index].copy() for g in lo.vertex_groups if g.name.startswith("mw_")}
for _g in lo.vertex_groups:
    if _g.name.startswith("mw_"):
        W[:, _g.index] = 0
W = (W == W.max(axis=1, keepdims=True)) * (W.max(axis=1, keepdims=True) > 0)
W = W / numpy.maximum(W.sum(axis=1, keepdims=True), 1e-9)
# "reach" {bone: m}: a vertex of that bone farther than m from the old
# part's own axis goes to "reach_to" (the torso): a cape or vest lying
# nearest an arm block swung out with the raised arm as a blade.
for _rb, _rr in CFG.get("reach", {}).items():
    _a, _b2, _c, _r = part_line(_rb)
    _ab = numpy.array((_b2 - _a)[:])
    _co = numpy.array([v.co[:] for v in lo.data.vertices])
    _t = numpy.clip((_co - numpy.array(_a[:])) @ _ab / max(float(_ab @ _ab), 1e-9), 0, 1)
    _d = numpy.linalg.norm(_co - (numpy.array(_a[:]) + _t[:, None] * _ab), axis=1)
    _bi = lo.vertex_groups[_rb].index
    _to = lo.vertex_groups[CFG.get("reach_to", CFG.get("torso", "b0"))].index
    _m = (W[:, _bi] > .5) & (_d > float(_rr))
    W[_m] = 0
    W[_m, _to] = 1
    print("BEAST reach %s: %d vertices beyond %.2f m given to the torso" % (_rb, int(_m.sum()), float(_rr)))
# "arm_weights": "meshy": the arms skinned by the Meshy rig's own smooth
# arm weights (mapped onto the old arm parts) where it has them, the old
# parts' nearest weights elsewhere: the old blocks gave a hard, torn
# shoulder and elbow.
if MW:
    _ms = numpy.zeros(len(W))
    _add = numpy.zeros_like(W)
    for _b, _col in MW.items():
        _add[:, lo.vertex_groups[_b].index] += _col
        _ms += _col
    _ms = numpy.clip(_ms, 0, 1)
    W = W * (1 - _ms)[:, None] + _add
    W = W / numpy.maximum(W.sum(axis=1, keepdims=True), 1e-9)
    print("BEAST arm weights from the Meshy rig: %d vertices" % int((_ms > .05).sum()))
# "arm_reach" k: an arm vertex farther than k times the posed Meshy arm's
# own girth from its bone goes to "reach_to" (a cape lying beside the arm).
if CFG.get("arm_reach") and ARM_SEGS:
    _co = numpy.array([v.co[:] for v in lo.data.vertices])
    _to = lo.vertex_groups[CFG.get("reach_to", CFG.get("torso", "b0"))].index
    for _rb, (_p0, _p1, _gr) in ARM_SEGS.items():
        _ab = numpy.array((_p1 - _p0)[:])
        _t = numpy.clip((_co - numpy.array(_p0[:])) @ _ab / max(float(_ab @ _ab), 1e-9), 0, 1)
        _d = numpy.linalg.norm(_co - (numpy.array(_p0[:]) + _t[:, None] * _ab), axis=1)
        _bi = lo.vertex_groups[_rb].index
        _m = (W[:, _bi] > .5) & (_d > _gr * float(CFG["arm_reach"]))
        W[_m] = 0
        W[_m, _to] = 1
        print("BEAST arm_reach %s: %d vertices beyond %.3f m given to the torso" % (_rb, int(_m.sum()), _gr * float(CFG["arm_reach"])))
# "merge" {bone: [bones]}: old parts that move as one (a trunk of many
# blocks, a face of many pieces) weighted as their first.
for _t, _ss in CFG.get("merge", {}).items():
    _ti = lo.vertex_groups[_t].index
    for _s in _ss:
        if _s in lo.vertex_groups and _s != _t:
            _si = lo.vertex_groups[_s].index
            W[:, _ti] += W[:, _si]
            W[:, _si] = 0
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
    if CFG.get("groups") and CFG.get("split", True):
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




def legs_capped(W):
    """Heat spreads a leg's bone over the shoulder and haunch (the hog's
    front leg took its whole shoulder, and the ragdoll's leg root found from
    it stood high and wide, its link torn by a blast): above the old leg's
    top a leg's weight fades to the torso over "leg_band" of the height."""
    legs = CFG.get("legs", [])
    if not legs or CFG.get("leg_band", .06) <= 0:
        return W
    torso = lo.vertex_groups[CFG.get("torso", "b0")].index
    co_ = numpy.array([v.co[:] for v in lo.data.vertices])
    band = OLD_H * float(CFG.get("leg_band", .06))
    moved = 0
    for chain in legs:
        top = max(src_me.vertices[i].co.z for i, n in enumerate(OWNER) if n == chain[0])
        keep = numpy.clip((top + band - co_[:, 2]) / band, 0, 1)
        for name in chain:
            k = lo.vertex_groups[name].index
            give = W[:, k] * (1 - keep)
            W[:, k] -= give
            W[:, torso] += give
            moved += int((give > .5).sum())
    print("BEAST legs capped at their old tops: %d vertices given to the torso" % moved)
    return W


WEIGHTS = CFG.get("weights", "nearest")
if WEIGHTS == "heat":
    W = legs_capped(heat_weights())
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


def join_kept():
    """The kept old parts (rest pose, old weights, old UVs as "old_uv") and
    the hands (carried to rest on their old bones) joined into the game
    mesh. Face attribute "kept": 1 old part, 2 hand."""
    if not KEEP and not HAND_OBJS:
        return
    main = lo.data.uv_layers.active.name
    objs = []
    if KEEP:
        kp = old_mesh.copy()
        kp.data = old_mesh.data.copy()
        scene.collection.objects.link(kp)
        for m_ in list(kp.modifiers):
            kp.modifiers.remove(m_)
        mw = old_mesh.matrix_world.copy()
        kp.parent = None
        kp.data.transform(mw)
        kp.matrix_world = Matrix.Identity(4)
        b_ = bmesh.new()
        b_.from_mesh(kp.data)
        dl = b_.verts.layers.deform.active
        gn = {g.index: g.name for g in kp.vertex_groups}
        gone = [v for v in b_.verts if not (dl and v[dl] and gn[max(v[dl].items(), key=lambda kv: kv[1])[0]] in KEEP)]
        bmesh.ops.delete(b_, geom=gone, context="VERTS")
        b_.to_mesh(kp.data)
        b_.free()
        # "keep_fit" [{bones, scale, drop}]: kept parts re-seated on the new
        # body (the old crown's ring stood round a wider head), scaled about
        # their bottom middle and lowered.
        for kf in CFG.get("keep_fit", []):
            gi_ = {kp.vertex_groups[n_].index for n_ in kf["bones"] if n_ in kp.vertex_groups}
            vs = [v for v in kp.data.vertices if v.groups and max(v.groups, key=lambda g: g.weight).group in gi_]
            if not vs:
                continue
            pc = numpy.array([v.co[:] for v in vs])
            piv = Vector(((pc[:, 0].min() + pc[:, 0].max()) / 2, (pc[:, 1].min() + pc[:, 1].max()) / 2, pc[:, 2].min()))
            k_ = float(kf.get("scale", 1.0))
            off = Vector(kf.get("move", [0, 0, -float(kf.get("drop", 0.0))]))
            for v in vs:
                v.co = piv + (v.co - piv) * k_ + off
            print("BEAST keep_fit: %d vertices scaled %.2f, moved %s" % (len(vs), k_, tuple(round(x, 3) for x in off)))
        kp.data.uv_layers.active.name = "old_uv"
        kp.data.uv_layers.new(name=main)
        kp.data.uv_layers.new(name="handuv")
        objs.append((kp, 1))
        print("BEAST kept old parts: %d faces" % len(kp.data.polygons))
    for side, ho in HAND_OBJS.items():
        fore, hand = HAND_BONES[side]
        gn = {g.index: g.name for g in ho.vertex_groups}
        Mf, Mh = POSE[fore].inverted(), POSE[hand].inverted()
        wts = []
        for v in ho.data.vertices:
            wf = sum(g.weight for g in v.groups if gn[g.group].startswith("forearm"))
            tot = sum(g.weight for g in v.groups)
            wf = wf / tot if tot > 0 else 0.0
            v.co = (Mf @ v.co) * wf + (Mh @ v.co) * (1 - wf)
            wts.append(wf)
        ho.vertex_groups.clear()
        gf, gh = ho.vertex_groups.new(name=fore), ho.vertex_groups.new(name=hand)
        for i, wf in enumerate(wts):
            if wf > 1e-4:
                gf.add([i], wf, "REPLACE")
            if wf < 1 - 1e-4:
                gh.add([i], 1 - wf, "REPLACE")
        uvs = ho.data.uv_layers
        for nm in (main, "old_uv", "handuv"):
            if nm not in uvs:
                uvs.new(name=nm)
        objs.append((ho, 2))
    for nm in ("old_uv", "handuv"):
        if nm not in lo.data.uv_layers:
            lo.data.uv_layers.new(name=nm)
    for ob, flag in [(lo, 0)] + objs:
        at = ob.data.attributes.get("kept") or ob.data.attributes.new("kept", "FLOAT", "FACE")
        for i in range(len(ob.data.polygons)):
            at.data[i].value = flag
        if ob is not lo:
            ob.data.materials.clear()
            for g in lo.vertex_groups:
                if g.name not in ob.vertex_groups:
                    ob.vertex_groups.new(name=g.name)
    select([lo] + [o_ for o_, _f in objs], lo)
    bpy.ops.object.join()
    for p_ in lo.data.polygons:
        p_.material_index = 0
    lo.data.uv_layers.active = lo.data.uv_layers[main]
    print("BEAST joined: %d kept-part faces, %d hand faces" % (
        sum(1 for a_ in lo.data.attributes["kept"].data if a_.value == 1),
        sum(1 for a_ in lo.data.attributes["kept"].data if a_.value == 2)))


join_kept()


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
if CFG.get("meshy_uv") and "kept" in lo.data.attributes:
    # "meshy_uv": the Meshy body keeps Meshy's own UV islands (a smart
    # unwrap of the decimated body cut it into confetti: jagged seams, flat
    # smeared arms); the kept parts and the hands are unwrapped; then every
    # island is scaled to its surface ("kept_uv"/"hand_uv" times) and all
    # are packed together.
    _bm = bmesh.from_edit_mesh(lo.data)
    _kl = _bm.faces.layers.float.get("kept")
    for _f in _bm.faces:
        _f.select = _f[_kl] > .5
    bmesh.update_edit_mesh(lo.data)
    scene.tool_settings.use_uv_select_sync = True
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.0)
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.average_islands_scale()
    bpy.ops.object.mode_set(mode="OBJECT")
    _ka = lo.data.attributes["kept"].data
    _uvd = lo.data.uv_layers.active.data
    for _p in lo.data.polygons:
        _f = _ka[_p.index].value
        if _f > .5:
            _k = float(CFG.get("kept_uv", .6)) if _f < 1.5 else float(CFG.get("hand_uv", 1.5))
            for _li in _p.loop_indices:
                _uvd[_li].uv = _uvd[_li].uv * _k
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(rotate=True, margin_method="FRACTION", margin=float(CFG.get("uv_margin", .004)),
                            shape_method="CONCAVE")
    scene.tool_settings.use_uv_select_sync = False
else:
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.0)
    if "kept" in lo.data.attributes:
        # (the kept parts' islands drawn smaller - a big airboat took most of
        # the atlas from the King - and the hands' bigger, before the
        # packing: "kept_uv" k, "hand_uv" k)
        bpy.ops.object.mode_set(mode="OBJECT")
        _ka = lo.data.attributes["kept"].data
        _uvd = lo.data.uv_layers.active.data
        for _p in lo.data.polygons:
            _f = _ka[_p.index].value
            _k = float(CFG.get("kept_uv", .35)) if _f > .5 and _f < 1.5 else (float(CFG.get("hand_uv", 1.5)) if _f > 1.5 else 1.0)
            if _k != 1.0:
                for _li in _p.loop_indices:
                    _uvd[_li].uv = _uvd[_li].uv * _k
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(rotate=True, margin_method="FRACTION", margin=float(CFG.get("uv_margin", .004)),
                            shape_method="CONCAVE")
bpy.ops.object.mode_set(mode="OBJECT")
# (actor_check's measure: texels a metre over the whole body)
_uva = _wa = 0.0
_uvd = lo.data.uv_layers.active.data
for _p in lo.data.polygons:
    _ls = list(_p.loop_indices)
    for _k in range(1, len(_ls) - 1):
        _a, _b, _c = (_uvd[_ls[0]].uv, _uvd[_ls[_k]].uv, _uvd[_ls[_k + 1]].uv)
        _uva += abs((_b - _a).cross(_c - _a)) / 2
    _wa += _p.area
print("BEAST texels a metre: %.0f (uv use %.0f%%)" % (math.sqrt(_uva / max(_wa, 1e-9)) * TEX, _uva * 100))
if "kept" in lo.data.attributes:
    _ka = lo.data.attributes["kept"].data
    for _fl, _nm in ((0, "Meshy body"), (1, "kept parts"), (2, "hands")):
        _u = _w = 0.0
        for _p in lo.data.polygons:
            if abs(_ka[_p.index].value - _fl) < .5:
                _ls = list(_p.loop_indices)
                for _k in range(1, len(_ls) - 1):
                    _a, _b, _c = (_uvd[_ls[0]].uv, _uvd[_ls[_k]].uv, _uvd[_ls[_k + 1]].uv)
                    _u += abs((_b - _a).cross(_c - _a)) / 2
                _w += _p.area
        print("BEAST texels a metre on the %s: %.0f" % (_nm, math.sqrt(_u / max(_w, 1e-9)) * TEX))
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


# ("bake_margin" px: islands packed close - "uv_margin" - must not bleed)
MARGIN = int(CFG.get("bake_margin", TEX // 128))
nimg = bpy.data.images.new("normals", TEX, TEX, alpha=False, float_buffer=True)
nimg.colorspace_settings.name = "Non-Color"
node.image = nimg
scene.cycles.samples = 1
select([lo])
bpy.ops.object.bake(type="NORMAL", normal_space="OBJECT", margin=MARGIN, use_clear=True)
NORMALS = pixels(nimg)
node.image = img
for flag in ("visible_shadow", "visible_diffuse", "visible_glossy", "visible_transmission", "visible_volume_scatter"):
    setattr(lo, flag, False)
nx = NORMALS[:, 0] * 2 - 1
ny = NORMALS[:, 1] * 2 - 1
total = None
weight = None
# "terminator" [geometry, shading, normal]: Cycles' shadow terminator offsets
# on the bake source (its smooth normals over big triangles drew jagged
# stitch-like shadow lines along the triangle edges of the sunburnt arms).
if CFG.get("terminator"):
    _t = CFG["terminator"]
    hi.shadow_terminator_geometry_offset = float(_t[0])
    hi.shadow_terminator_shading_offset = float(_t[1])
    if len(_t) > 2:
        hi.shadow_terminator_normal_offset = float(_t[2])
kept = [hi.matrix_world.copy(), arm.matrix_world.copy()]
for k, angle in enumerate(TURNS):
    spin = Matrix.Rotation(math.radians(angle), 4, "Z")
    hi.matrix_world = spin @ kept[0]
    arm.matrix_world = spin @ kept[1]
    bpy.context.view_layer.update()
    scene.cycles.samples = 32 if k == 0 else 20
    select([hi, lo], lo)
    bpy.ops.object.bake(type="COMBINED", pass_filter={"EMIT", "DIRECT", "INDIRECT", "DIFFUSE"},
                        margin=MARGIN, use_clear=True, use_selected_to_active=True,
                        cage_extrusion=OLD_H * float(CFG.get("cage", .012)), max_ray_distance=OLD_H * float(CFG.get("ray", .05)))
    px = pixels(img)
    c, sn = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    if os.environ.get("BEAST_DEBUG_ALBEDO") and k == 0:
        for _nm, _arr in (("turn0", px[:, :3]), ("normals", NORMALS[:, :3])):
            _di = bpy.data.images.new("dbg_" + _nm, TEX, TEX, alpha=False)
            _dp = numpy.ones((TEX * TEX, 4), dtype=numpy.float32)
            _dp[:, :3] = _arr
            _di.pixels.foreach_set(_dp.ravel())
            _di.filepath_raw = os.path.join(OUT, KIND + "_dbg_%s.png" % _nm)
            _di.file_format = "PNG"
            _di.save()
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
bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, margin=MARGIN, use_clear=True,
                    use_selected_to_active=True, cage_extrusion=OLD_H * float(CFG.get("cage", .012)), max_ray_distance=OLD_H * float(CFG.get("ray", .05)))
ALBEDO = pixels(img)[:, :3].copy()
if os.environ.get("BEAST_DEBUG_ALBEDO"):
    _di = bpy.data.images.new("dbg_albedo", TEX, TEX, alpha=False)
    _dp = numpy.ones((TEX * TEX, 4), dtype=numpy.float32)
    _dp[:, :3] = ALBEDO
    _di.pixels.foreach_set(_dp.ravel())
    _di.filepath_raw = os.path.join(OUT, KIND + "_dbg_albedo.png")
    _di.file_format = "PNG"
    _di.save()
nz = NORMALS[:, 2] * 2 - 1
if CFG.get("light") == "hemi":
    # "light": "hemi" - the body lit from its own albedo and normals (a warm
    # sky above, a dim ground below) instead of the stage's shadows on the
    # Meshy mesh: those drew dark stitch lines along its triangles over the
    # posed arms. Form kept, every side evenly lit as the four turns meant.
    _sky, _gnd = numpy.array(CFG.get("sky", [1.0, .93, .82])), numpy.array(CFG.get("ground", [.42, .4, .44]))
    _t = numpy.clip(nz * .5 + .5, 0, 1)[:, None] ** float(CFG.get("hemi_k", 1.3))
    _ok = inside & (ALBEDO.sum(axis=1) > .003)
    total[_ok, :3] = (ALBEDO * (_gnd + (_sky - _gnd) * _t))[_ok]
    found = found | _ok
    print("BEAST hemi light: %d texels" % int(_ok.sum()))
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
# (with kept parts: their texels unreached by the Meshy bake left out)
n_l = float(numpy.median(lum(total[(inside & found) if KEEP else inside, :3])))
gain = float(numpy.clip(o_l / max(n_l, 1e-4), .6, 1.6)) * float(CFG.get("gain", 1.0))
total[:, :3] = numpy.clip(total[:, :3] * gain * numpy.array(CFG.get("tint", [1, 1, 1])), 0, 1)
if CFG.get("greys"):
    # "greys": {rgb, sat}: the greys (saturation under sat) turned by rgb, the
    # coloured parts left (BLUE's ticked coat bluer, his tan points and red
    # collar as they are).
    g_ = CFG["greys"]
    mx, mn = total[:, :3].max(axis=1), total[:, :3].min(axis=1)
    sat = (mx - mn) / numpy.maximum(mx, 1e-4)
    k_ = numpy.clip(1 - sat / float(g_.get("sat", .25)), 0, 1)[:, None]
    total[:, :3] = numpy.clip(total[:, :3] * (1 + (numpy.array(g_["rgb"]) - 1) * k_), 0, 1)
print("BEAST gain %.3f to the old look's light" % gain)
KEPT_PX = {}


def keep_texels():
    """The kept parts' old texels baked into the new atlas through their old
    UVs (an emission bake, the old look and each phase look), pasted over the
    bake; written as <kind>_gearmask/_gear*.png too, so gear_paste.py puts
    them back after the game's grade (they were graded once already)."""
    if not KEEP:
        return
    nt = mat.node_tree
    tgt = nt.nodes.new("ShaderNodeTexImage")
    # (a fresh output: relinking the old one baked black)
    for n_ in [n_ for n_ in nt.nodes if n_.type == "OUTPUT_MATERIAL"]:
        nt.nodes.remove(n_)
    out_ = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    at = nt.nodes.new("ShaderNodeAttribute")
    at.attribute_type = "GEOMETRY"
    at.attribute_name = "kept"
    cmp_ = nt.nodes.new("ShaderNodeMath")
    cmp_.operation = "COMPARE"
    cmp_.inputs[1].default_value = 1.0
    cmp_.inputs[2].default_value = .1
    nt.links.new(at.outputs["Fac"], cmp_.inputs[0])
    uvn = nt.nodes.new("ShaderNodeUVMap")
    uvn.uv_map = "old_uv"
    tx = nt.nodes.new("ShaderNodeTexImage")
    nt.links.new(uvn.outputs[0], tx.inputs[0])
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs[0].default_value = 1.0
    nt.links.new(tx.outputs[0], mul.inputs[6])
    nt.links.new(cmp_.outputs[0], mul.inputs[7])
    nt.links.new(em.outputs[0], out_.inputs[0])
    nt.nodes.active = tgt
    select([lo])
    hi.hide_render = True
    scene.cycles.samples = 1

    def bake_to(name, link_from):
        im = bpy.data.images.new(name, TEX, TEX, alpha=False)
        tgt.image = im
        for lk in list(em.inputs[0].links):
            nt.links.remove(lk)
        nt.links.new(link_from, em.inputs[0])
        bpy.ops.object.bake(type="EMIT", margin=2, use_clear=True, use_selected_to_active=False)
        px_ = pixels(im)[:, :3].copy()
        print("BEAST keep bake %s: max %.3f, %d lit" % (name, float(px_.max()), int((px_.max(axis=1) > .02).sum())))
        return px_

    mask = bake_to("keepmask", cmp_.outputs[0])[:, 0] > .5
    looks = [("", CFG["old_tex"])]
    if "p2" in meta_old.get("textures", []):
        looks += [(t_, CFG["old_tex"].replace(".png", "_%s.png" % t_)) for t_ in ("p2", "p3")]
    for tag, path in looks:
        if not os.path.exists(path):
            continue
        tx.image = bpy.data.images.load(os.path.abspath(path), check_existing=True)
        KEPT_PX[tag] = bake_to("keep" + tag, mul.outputs[2])
    hi.hide_render = False
    total[mask, :3] = KEPT_PX[""][mask]
    KEPT_PX["mask"] = mask
    def save(arr, name):
        im = bpy.data.images.new(name, TEX, TEX, alpha=False)
        a_ = numpy.ones((TEX * TEX, 4), dtype=numpy.float32)
        a_[:, :3] = arr if arr.shape[1] == 3 else arr[:, :1]
        im.pixels.foreach_set(a_.ravel())
        im.filepath_raw = os.path.join(OUT, name)
        im.file_format = "PNG"
        im.save()

    save(mask.astype(numpy.float32)[:, None], KIND + "_gearmask.png")
    for tag, px_ in KEPT_PX.items():
        if tag != "mask":
            save(px_, KIND + "_gear%s.png" % (("_" + tag) if tag else ""))
    print("BEAST kept parts' old texels: %d texels, looks %s" % (int(mask.sum()), [t_ for t_ in KEPT_PX if t_ != "mask"]))


keep_texels()


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
if "p2" in meta_old.get("textures", []):
    # A boss's phase looks (build_actor's way): p2 sooted in blotches and
    # bloodied on the front, p3 charred darker all over, more blood; the kept
    # parts take the old phase looks' texels.
    _rng = numpy.random.default_rng(7)
    _nz = numpy.zeros((TEX, TEX))
    for _sc, _amp in ((TEX // 32, .5), (TEX // 12, .3), (TEX // 4, .2)):
        _small = _rng.random((TEX // _sc + 2, TEX // _sc + 2))
        _rep = numpy.kron(_small, numpy.ones((_sc, _sc)))[:TEX, :TEX]
        _k = max(1, _sc // 2)
        for _ax in (0, 1):
            _rep = sum(numpy.roll(_rep, _d, _ax) for _d in range(-_k, _k + 1)) / (2 * _k + 1)
        _nz += _rep * _amp
    _nz = ((_nz - _nz.min()) / max(numpy.ptp(_nz), 1e-6)).ravel()
    _front = numpy.clip((-(NORMALS[:, 1] * 2 - 1) - .1) * 2, 0, 1) * inside
    _skin = ~KEPT_PX.get("mask", numpy.zeros(len(total), bool))
    _soot_dark = numpy.array([.07, .055, .045])
    _dark, _wet = numpy.array([.36, .03, .02]), numpy.array([.55, .05, .03])
    for _tag, _thr, _soot_k, _all, _bk in (("p2", .58, .7, .93, .6), ("p3", .48, .85, .8, 1.0)):
        _soot = numpy.clip((_nz - _thr) * 5, 0, 1) * _skin
        _ph = total.copy()
        _ph[:, :3] *= numpy.where(_skin, _all, 1.0)[:, None]
        _ph[:, :3] = _ph[:, :3] * (1 - _soot[:, None] * _soot_k) + _soot_dark * _soot[:, None] * _soot_k
        _bl = numpy.clip((numpy.roll(_nz, TEX * 37 + 11) - (1.0 - .35 * _bk)) * 6, 0, 1) * _front * _skin * _bk
        _mc = _dark + (_wet - _dark) * numpy.clip(_nz[:, None] * 1.5 - .3, 0, 1)
        _ph[:, :3] = _ph[:, :3] * (1 - _bl[:, None] * .85) + _mc * _bl[:, None] * .85
        if _tag in KEPT_PX:
            _ph[KEPT_PX["mask"], :3] = KEPT_PX[_tag][KEPT_PX["mask"]]
        img.pixels.foreach_set(_ph.ravel())
        img.filepath_raw = os.path.join(OUT, KIND + "_" + _tag + ".png")
        img.save()
    img.pixels.foreach_set(total.ravel())
    print("BEAST phase looks p2, p3 written")
if "hurt" in meta_old.get("textures", []):
    # TODO: a hurt look (the people's blood splashes); the plain one for now.
    print("BEAST NOTE: %s has a hurt look; written as the plain look (no blood yet)" % KIND)
    img.filepath_raw = os.path.join(OUT, KIND + "_hurt.png")
    img.save()

# ------------------------------------------------------------ export
lo.data.materials.clear()
bpy.data.objects.remove(old_mesh)
bpy.data.objects.remove(src)
if "src_fit" in globals():
    bpy.data.objects.remove(src_fit)
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
