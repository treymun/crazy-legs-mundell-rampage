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
bm.to_mesh(lo.data)
bm.free()
_keep = ~_cut
co = co[_keep]
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
ORIGIN = {b: J[b] for b in BONES}

# ------------------------------------------------------------------ gear
GEAR = []  # [(bone name, old bone index)]
GRIPS = []
GRIP_AT = {}  # side -> (old bone, the hand's middle at the standing key)
gear_obj = None
# Every part the old body loses when it dies (shrunk at the key "down") that
# is not a piece of its arms, legs or head: the gun and what else it holds.
# One gear bone per old bone, keyed with that bone's own motion.
LOST = []
for _i, _b in enumerate(DUMP["bones"]):
    _lab = DUMP["labels"].get(_b, "body")
    _s0 = DUMP["poses"]["0"][_i][7]
    _sd = DUMP["poses"]["down"][_i][7]
    if _sd >= .2 or _s0 < .2 or _b in CFG.get("gear_skip", []):
        continue
    # Kept when nearer a hand or an elbow than the head, a knee or a foot
    # (RagdollRig._find_gear's rule, per part: a cigarette or a boot's toe
    # still shrinks away).
    _o = g2b(DUMP["poses"]["0"][_i][0:3])
    _p0 = [g2b(q) for q in DUMP["points"]["0"]]
    _held = min((_p0[k] - _o).length for k in (5, 6, 7, 8))
    _other = min((_p0[k] - _o).length for k in (4, 9, 10, 11, 12))
    if _held < _other or _b in CFG.get("gear_extra", []):
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
    _items = []
    for _i in LOST:
        if not any(_i in it for it in _items):
            _items.append(sorted(_link[_i]))
    vert_gear = []
    for _b in _vbone:
        vert_gear.append(next(k for k, it in enumerate(_items) if _b in it))
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
        lo_e, hi_e = ctr + ax * float(proj.min()), ctr + ax * float(proj.max())
        perp = (pts - numpy.array(ctr[:])) - numpy.outer(proj, numpy.array(ax[:]))
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
              "two": len(holds) == 2, "main": "r" if "r" in holds else "l", "fwd": _new_front - _old_front}
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
    G1 = (-out * .8 + U * .5 + F * .05).normalized()
    at = hips + out * .12 + U * .17 + F * (_front(hips.z + .05, hips.z + .3) + .09)
    if beat >= 0:
        G1 = (Matrix.Rotation(.05 * math.sin(beat * math.pi / 2), 3, F) @ G1).normalized()
        at = at + U * (.012 * math.cos(beat * math.pi))
    return gun_pose(it, gr, at, G1, F), True


def hand_on(it, side, Di, R_t, el_guess):
    """The hand's turn and the wrist's place for holding item `it` (moved by
    Di) at its grip: the hand straight on from the forearm, the palm against
    the thing and the thing across the palm (the fingers then close on it)."""
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
        print("MESHY keep-out %s %s: %.3f m in, %.3f m after" % (name, gname, first, d))
    PEN[name + ":" + gname] = d
    return M


PEN = {}
CLEAR = float(CFG.get("clearance", .02))


TWIST = {}
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


def solve(name, dz=0.0, held0=None):
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
    D["body"] = place(R_t, J["hips"], hipc)

    def at(rest):
        return hipc + R_t @ (rest - J["hips"])

    # Head: as the old head turned since the standing key, on the new neck;
    # down on the stock when shouldering a long gun (the cheek on it).
    R_h = rel_rot(head_anchor, name) if head_anchor >= 0 else R_t
    aiming = any(it["two"] for it in ITEMS) and name.replace("hurt_", "") in AIMS
    if aiming:
        main = next(it["main"] for it in ITEMS if it["two"])
        Tn = TWIST["fwd"]
        R_h = (Matrix.Rotation(.32, 3, Vector(Tn.col[0])) @ Matrix.Rotation(
            (.28 if main == "r" else -.28), 3, -Vector(Tn.col[2]))) @ R_h
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
            Di = keep_out(surface, it["bone"], Di, name, .22 if name.replace("hurt_", "") in AIMS else 0.0)
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
                on[side] = (it, Di)

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
        if side in main_hand:
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
        else:
            end_r = J["tip_" + side]
            target = sh_f + (P[ha] - P[sh])
            if side in GRIP_AT:
                seen = [old_bone(name, i) for i in GRIP_AT[side][0] if old_bone(name, i)[2].x > .2]
                if seen:
                    target = sum((q[0] for q in seen), Vector()) / len(seen)
                    end_r = J["hand_" + side]
            R_u, R_l, el_f, tip_f = limb(R_t, J["upperarm_" + side], J["forearm_" + side], end_r,
                                         sh_f, target, pole, Vector((0, -1, 0)))
            D["upperarm_" + side] = place(R_u, J["upperarm_" + side], sh_f)
            D["forearm_" + side] = place(R_l, J["forearm_" + side], el_f)
            D["hand_" + side] = place(R_l, J["forearm_" + side], el_f)
        joints["hand_" + side] = D["hand_" + side] @ J["hand_" + side]
    # Every held thing is a rigid piece on its main hand: its bone is posed as
    # that hand exactly (its mesh hangs off it, unskinned), shrunk away where
    # the old one was gone (the dead keys: the ragdoll drops it as a piece).
    for it in ITEMS:
        Di, shown = moves[it["bone"]]
        side = it["main"]
        if Di is None:
            if held0 is None and ITEM_TYPE.get(side) == "pistol" and side in HANDF:
                # A pistol in the fist: its barrel along the hand (the forearm's
                # line), over the knuckles, the grip in the palm.
                lo_e, hi_e = it["lo"], it["hi"]
                grip = lo_e + (hi_e - lo_e) * it["holds"][side]
                muzzle = lo_e if (lo_e - grip).length > (hi_e - grip).length else hi_e
                G0 = (muzzle - grip).normalized()
                wu = Vector((0, 0, 1))
                U0 = (wu - G0 * wu.dot(G0)).normalized()
                wrist0, a0, n0 = HANDF[side]
                Rh = D["hand_" + side].to_3x3()
                G1 = (Rh @ a0).normalized()
                U1 = -(Rh @ n0).normalized()
                Rg = Matrix((G1, U1, G1.cross(U1))).transposed() @ Matrix((G0, U0, G0.cross(U0))).transposed().inverted()
                palm = D["hand_" + side] @ J["hand_" + side] + (Rh @ n0) * (it["rad"] * .6)
                Di = Matrix.Translation(palm) @ Rg.to_4x4() @ Matrix.Translation(-grip)
            elif held0 is None and side in HANDF and ITEM_TYPE.get(side, "carry") == "carry":
                # Carried hanging (a jug, a bottle, a lantern): by its top (the
                # handle or neck) in the fist, the thing hanging below the hand.
                wrist0, a0, n0 = HANDF[side]
                Rh = D["hand_" + side].to_3x3()
                a_w = (Rh @ a0).normalized()
                pts = [Vector(g) for g in ITEM_PTS.get(it["bone"], [])]
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
                    Di = Dh_new @ D["hand_" + side].inverted() @ Di
                    D["hand_" + side] = Dh_new
                d = depth_in(surface, it["bone"], Di)[0]
                if first > .004:
                    print("MESHY keep-out %s %s: %.3f m in, %.3f m after" % (name, it["bone"], first, d))
                PEN[name + ":" + it["bone"]] = d
        D["@" + it["bone"]] = Di
        D[it["bone"]] = D["hand_" + side]
        if it["two"] and held0 is not None and Di is not None:
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
            curls = {c: hands.spread(c, .55 if c != "th" else .3) for c in hnd.chains}
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
                for drop in (0.0, .02, .04):
                    for inn in (0.0, .03, .06):
                        CFG.update(aim_twist=tw, aim_drop=drop, aim_in=inn)
                        _D, jt, _P = solve(key, 0.0, HELD0)
                        miss = sum(jt["miss"].values())
                        pen = max([v for k, v in PEN.items() if k.startswith(key + ":")] or [0.0])
                        score = miss * 4 + pen * 10 + tw * .0006 + drop * .1
                        if best is None or score < best[0]:
                            best = (score, tw, drop, inn, miss, pen)
            AIM_BEST[key] = best
            print("MESHY shouldered %s: bladed %d, butt %.2f down, %.2f in (hands %.3f m off, %.3f m in)" % (
                (key,) + best[1:]))
        _s, tw, drop, inn, _m, _p = AIM_BEST[key]
        CFG.update(aim_twist=tw, aim_drop=drop, aim_in=inn)
        D, joints, P = solve(name, 0.0, HELD0)
        for k in ("aim_twist", "aim_drop", "aim_in"):
            del CFG[k]
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
for t in KEYS:
    name = BY_KEY[t]
    D, P = pose_key(name)
    for b in BONES + [g for g, _c in GEAR]:
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
    for p in gear_lo.data.polygons:
        p.material_index = 1
    for g in list(gear_lo.vertex_groups):
        gear_lo.vertex_groups.remove(g)
    for gi, (gname, _c) in enumerate(GEAR):
        vgp = gear_lo.vertex_groups.new(name=gname)
        ids = [i for i, x in enumerate(vert_gear) if x == gi]
        vgp.add(ids, 1.0, "REPLACE")
    for b in BONES:
        if b not in gear_lo.vertex_groups:
            gear_lo.vertex_groups.new(name=b)
    for gname, _c in GEAR:
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
for island in bmesh_utils.bmesh_linked_uv_islands(bm, uv):
    heady = sum(1 for f in island for v in f.verts if v[deform].get(head_gi, 0) > .5)
    if heady < len(island):
        continue
    loops = [loop for f in island for loop in f.loops]
    mid = sum((loop[uv].uv for loop in loops), Vector((0.0, 0.0))) / len(loops)
    for loop in loops:
        loop[uv].uv = mid + (loop[uv].uv - mid) * HEAD_FAVOUR
bmesh.update_edit_mesh(lo.data)
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.uv.select_all(action="SELECT")
bpy.ops.uv.pack_islands(rotate=True, margin_method="FRACTION", margin=GAP, shape_method="CONCAVE")
bpy.ops.object.mode_set(mode="OBJECT")

# -------------------------------------------------------------------- bake
image = bpy.data.images.new("bake", TEXTURE, TEXTURE, alpha=False)
for m in lo.data.materials:
    node = m.node_tree.nodes.new("ShaderNodeTexImage")
    node.name = "bake_target"
    node.image = image
    m.node_tree.nodes.active = node


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
for v in lo.data.vertices:
    zv = sum(g.weight for g in v.groups if g.group in zidx)
    hv = sum(g.weight for g in v.groups if g.group == lo.vertex_groups["head"].index)
    zattr.data[v.index].color = (zv, hv, 0, 1)
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
total = None
weight = None
nx = NORMALS[:, 0] * 2 - 1
ny = NORMALS[:, 1] * 2 - 1
kept = [hi.matrix_world.copy(), lo.matrix_world.copy()]
for k, angle in enumerate(TURNS):
    spin = Matrix.Rotation(math.radians(angle), 4, "Z")
    hi.matrix_world = spin @ kept[0]
    lo.matrix_world = spin @ kept[1]
    bpy.context.view_layer.update()
    scene.cycles.samples = 32 if k == 0 else 20
    select([hi, lo], lo)
    bake_op(type="COMBINED", pass_filter={"EMIT", "DIRECT", "INDIRECT", "DIFFUSE"},
            margin=TEXTURE // 128, use_clear=True, use_selected_to_active=True,
            cage_extrusion=OLD_H * .012, max_ray_distance=OLD_H * .05)
    px = pixels(image)
    c, sn = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    toward = -(sn * nx + c * ny)
    hit = px[:, :3].sum(axis=1) > .003
    w = (numpy.clip(toward, 0, 1) ** 2 + 1e-4) * hit
    if total is None:
        total = px.copy()
        total[:, :3] *= w[:, None]
        weight = w.copy()
    else:
        total[:, :3] += px[:, :3] * w[:, None]
        weight += w
hi.matrix_world, lo.matrix_world = kept
bpy.context.view_layer.update()
found = weight > 0
total[found, :3] /= weight[found, None]
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
    lo.visible_shadow = True
    lo.visible_diffuse = True
    for m in lo.data.materials:
        nt = m.node_tree
        for nn in list(nt.nodes):
            if nn.name != "bake_target":
                nt.nodes.remove(nn)
        o = nt.nodes.new("ShaderNodeOutputMaterial")
        if m is mat_hand and "handuv" in lo.data.uv_layers:
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
    if _skinlike.sum() > 50 and HANDMASK.any():
        _want = numpy.median(_rgb[_skinlike], axis=0)
        _have = numpy.median(htot[HANDMASK], axis=0)
        htot = numpy.clip(htot * (_want / numpy.maximum(_have, 1e-4))[None, :], 0, 1)
        print("MESHY hands' skin matched to the body's", numpy.round(_want * 255).astype(int))
    total[HANDMASK, :3] = htot[HANDMASK]
    print("MESHY hands baked: %d texels, mean colour %s" % (int(HANDMASK.sum()),
          numpy.round(htot[HANDMASK].mean(axis=0) * 255).astype(int) if HANDMASK.any() else "-"))
    hi.hide_render = False
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
    skin_all = face | rest
    if "HANDMASK" in globals():
        skin_all = skin_all & ~HANDMASK
    k = min(float(CFG.get("face_lift_most", 1.8)), max(1.0, want / max(have, 1e-4)))
    print("MESHY face light %.3f, other skin %.3f" % (have, want))
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
    for _ in range(3):
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
    if other.sum() > 50:
        want = numpy.median(rgb[other], axis=0)
        hsel = hm & (lum2 >= numpy.percentile(lum2[hm], 40))
        have = numpy.median(rgb[hsel], axis=0)
        rgb[hm] = numpy.clip(rgb[hm] * (want / numpy.maximum(have, 1e-4))[None, :], 0, 1)
        print("MESHY hands matched to the body's skin", numpy.round(want * 255).astype(int))
    px[:, :3] = rgb
    return px


total = skin_fix(total)
total = blush_down(total)
total = face_lift(total)
total = hand_match(total)
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
    # Mask: the gear slot emits white, the body black.
    for m, val in ((mat_body, 0.0), (mat_gear, 1.0), (mat_hand, 0.0)):
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
front = py_ < 0.02
wounds = numpy.zeros(len(pz_))
# brow/face cut, chest and belly, the gut, one arm (the left upper arm)
for cx, cz, rad, k in ((0.0, .9, .07, 1.0), (.05, .66, .12, 1.0), (-.06, .55, .09, .9), (.2, .72, .07, .7)):
    d = numpy.sqrt(((px_ - cx) / rad) ** 2 + ((pz_ - cz) * OLD_H / OLD_H / rad) ** 2)
    wounds = numpy.maximum(wounds, numpy.clip(1.2 - d, 0, 1) * k)
blood = numpy.clip((noise_px - (1.05 - wounds * .65)) * 6, 0, 1) * front
if gear_obj is not None:
    gm_px = pixels(mimg)[:, 0]
    blood *= gm_px < .5
hurt = total.copy()
dark = numpy.array([.36, .03, .02])
wet = numpy.array([.55, .05, .03])
mixc = dark + (wet - dark) * numpy.clip(noise_px[:, None] * 1.5 - .3, 0, 1)
hurt[:, :3] = hurt[:, :3] * (1 - blood[:, None] * .85) + mixc * blood[:, None] * .85
image.pixels.foreach_set(hurt.ravel())
image.filepath_raw = os.path.join(OUT, KIND + "_hurt.png")
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
            f.select = f.material_index == 1 and all(v[dl].get(gidx, 0) > .5 for v in f.verts)
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
    rig.data.pose_position = "POSE"
    bpy.context.view_layer.update()
    # The body keeps no weights on the held things' bones.
    for it in ITEMS:
        if it["bone"] in lo.vertex_groups:
            lo.vertex_groups.remove(lo.vertex_groups[it["bone"]])
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
RIDES = {}
for it in ITEMS:
    labels[it["bone"]] = "arm_" + it["main"]
    # The held thing rides its main hand's forearm in the ragdoll and the
    # living body (RagdollRig segments: 3 the left forearm, 5 the right).
    RIDES[it["bone"]] = 3 if it["main"] == "l" else 5
old_entry = json.load(open(os.path.join(os.path.dirname(CFG["old_glb"]), "actors.json")))[KIND]
entry = {
    "bones": float(len(BONES) + len(GEAR)),
    "canvas": old_entry.get("canvas", [1.75, 1.86]),
    "faces": float(len(lo.data.loop_triangles)),
    "frames": FRAMES,
    "gear": old_entry.get("gear", {}),
    "height": OLD_H,
    "labels": labels,
    "lit": old_entry.get("lit", True),
    "parts": float(len(BONES) + len(GEAR)),
    "textures": ["", "hurt"],
    "joints": JOINTS,
    "rides": RIDES,
    "segs": dict({"body": 0, "head": 1, "upperarm_l": 2, "forearm_l": 3, "hand_l": 3, "upperarm_r": 4,
                  "forearm_r": 5, "hand_r": 5, "thigh_l": 6, "shin_l": 7, "foot_l": 7, "thigh_r": 8,
                  "shin_r": 9, "foot_r": 9},
                 **{b: (3 if b.startswith("fl_") else 5) for b in BONES if b.startswith(("fl_", "fr_"))}),
    "meshy": True,
}
meta_path = os.path.join(OUT, "actors.json")
meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
meta[KIND] = entry
json.dump(meta, open(meta_path, "w"), indent=1, sort_keys=True)
print("MESHY ACTOR %s done: %d tris, %d bones" % (KIND, len(lo.data.loop_triangles), len(BONES) + len(GEAR)))
