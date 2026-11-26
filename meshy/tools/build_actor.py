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


# ------------------------------------------------ the bones' origins (rest)
J = {}
for side, S in (("l", "Left"), ("r", "Right")):
    J["upperarm_" + side] = heads[S + "Arm"]
    J["forearm_" + side] = heads[S + "ForeArm"]
    J["wrist_" + side] = heads[S + "Hand"]
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
    # One gear bone per old cluster (its biggest old bone's motion).
    for ci, i in enumerate(LOST):
        GEAR.append(("gear%d" % ci, [i]))
    # Which gear bone each kept vertex follows.
    vert_gear = []
    for v in old_mesh.data.vertices:
        if v.index in keep_v:
            best = names.get(max(v.groups, key=lambda g: g.weight).group)
            idx = DUMP["bones"].index(best) if best in DUMP["bones"] else -1
            gi = LOST.index(idx) if idx in LOST else 0
            vert_gear.append(gi)
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


def limb(R_t, root_r, mid_r, end_r, root_f, target, pole, bend0):
    """Upper and lower rotations of a limb (world) and its joints."""
    l1 = (mid_r - root_r).length
    l2 = (end_r - mid_r).length
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


def solve(name, dz=0.0):
    P = old_points(name)
    D = {}
    To = torso_basis(P[HIP_L], P[HIP_R], P[SH_L], P[SH_R])
    R_t = To @ T0.inverted()
    oh = (P[HIP_L] + P[HIP_R]) / 2
    hipc = Vector((oh.x, oh.y, oh.z * HIP_K + dz))
    D["body"] = place(R_t, J["hips"], hipc)

    def at(rest):
        return hipc + R_t @ (rest - J["hips"])

    # Head: as the old head turned since the standing key, on the new neck.
    R_h = rel_rot(head_anchor, name) if head_anchor >= 0 else R_t
    D["head"] = place(R_h, J["neck"], at(J["neck"]))
    joints = {}
    for side, sh, ha, el in (("l", SH_L, HA_L, EL_L), ("r", SH_R, HA_R, EL_R)):
        out = 1.0 if side == "l" else -1.0
        sh_f = at(J["upperarm_" + side])
        end_r = J["tip_" + side]
        target = sh_f + (P[ha] - P[sh])
        if side in GRIP_AT:
            _gb, _gc = GRIP_AT[side]
            _seen = [old_bone(name, i) for i in _gb if old_bone(name, i)[2].x > .2]
            if _seen:
                # The hand's middle where the old hand was.
                _p1 = sum((q[0] for q in _seen), Vector()) / len(_seen)
                target = _p1.copy()
                end_r = J["hand_" + side]
        oel = P[el]
        chord = P[ha] - P[sh]
        off = (oel - P[sh]) - chord.normalized() * (oel - P[sh]).dot(chord.normalized())
        pole = R_t @ Vector((out * .3, .3, -1.0))
        if DUMP["stiff"] and not DUMP["stiff"][0 if side == "l" else 1] and off.length > .03:
            pole = off
        R_u, R_l, el_f, tip_f = limb(R_t, J["upperarm_" + side], J["forearm_" + side], end_r,
                                     sh_f, target, pole, Vector((0, -1, 0)))
        D["upperarm_" + side] = place(R_u, J["upperarm_" + side], sh_f)
        D["forearm_" + side] = place(R_l, J["forearm_" + side], el_f)
        D["hand_" + side] = place(R_l, J["forearm_" + side], el_f)
        joints["hand_" + side] = D["hand_" + side] @ J["hand_" + side]
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
    return D, joints, P


def pose_key(name):
    D, joints, P = solve(name)
    # Feet that could not reach the floor where the old ones stood: lower
    # the body by what the lower foot fell short.
    short = min(joints["foot_t_l"].z, joints["foot_t_r"].z)
    got = min(joints["foot_l"].z, joints["foot_r"].z)
    if got - short > .005:
        D, joints, P = solve(name, short - got)
    return D, P


SIZES = {}
for t in KEYS:
    name = BY_KEY[t]
    D, P = pose_key(name)
    for b in BONES:
        pb = rig.pose.bones[b]
        pb.matrix = D[b] @ data.bones[b].matrix_local
        bpy.context.view_layer.update()
        pb.keyframe_insert("location", frame=t)
        pb.keyframe_insert("rotation_quaternion", frame=t)
        pb.scale = (1, 1, 1)
        pb.keyframe_insert("scale", frame=t)
    for gname, cluster in GEAR:
        # The gear moves exactly as the old one did (its biggest old bone).
        big = cluster[0]
        p0, r0, s0 = old_bone("0", big)
        p1, r1, s1 = old_bone(name, big)
        Dg = Matrix.Translation(p1) @ (r1 @ r0.inverted()).to_4x4() @ Matrix.Translation(-p0)
        pb = rig.pose.bones[gname]
        rest_m = data.bones[gname].matrix_local
        if s1.x < .2:
            c = gear_rest[gname]
            Dg = Dg @ Matrix.Translation(c) @ Matrix.Diagonal((1e-3, 1e-3, 1e-3, 1)) @ Matrix.Translation(-c)
        pb.matrix = Dg @ rest_m
        bpy.context.view_layer.update()
        pb.keyframe_insert("location", frame=t)
        pb.keyframe_insert("rotation_quaternion", frame=t)
        pb.keyframe_insert("scale", frame=t)
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
if gear_obj is not None:
    lo.data.materials.append(mat_gear)
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
zattr = lo.data.color_attributes.new("zone", "FLOAT_COLOR", "POINT")
zidx = [lo.vertex_groups[z].index for z in ZONES if z in lo.vertex_groups]
for v in lo.data.vertices:
    zv = sum(g.weight for g in v.groups if g.group in zidx)
    zattr.data[v.index].color = (zv, zv, zv, 1)
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
ZONE = pixels(zimg)[:, 0] > .5
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
total[:, :3] *= GAIN
_grey = total[:, :3].mean(axis=1, keepdims=True)
total[:, :3] = numpy.clip(_grey + (total[:, :3] - _grey) * float(CFG.get("colour", 1.2)), 0, 1)
print("MESHY gain %.3f to the old look's light" % GAIN)
total = skin_fix(total)
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
    for m, val in ((mat_body, 0.0), (mat_gear, 1.0)):
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
for m in lo.data.materials:
    pass
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
select([lo, rig], rig)
bpy.ops.export_scene.gltf(
    filepath=os.path.join(OUT, KIND + ".glb"), export_format="GLB", use_selection=True,
    export_materials="NONE", export_yup=True, export_animations=True, export_skins=True,
    export_morph=False, export_force_sampling=False, export_def_bones=False,
)
lo.data.materials.append(view_mat)
hi.hide_render = True
hi.hide_set(True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, KIND + ".blend"))

# --------------------------------------------------------------- actors.json
lo.data.calc_loop_triangles()
labels = {b: LABEL[b] for b in BONES}
for gname, _c in GEAR:
    labels[gname] = CFG.get("gear_label", "arm_r")
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
    "meshy": True,
}
meta_path = os.path.join(OUT, "actors.json")
meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
meta[KIND] = entry
json.dump(meta, open(meta_path, "w"), indent=1, sort_keys=True)
print("MESHY ACTOR %s done: %d tris, %d bones" % (KIND, len(lo.data.loop_triangles), len(BONES) + len(GEAR)))
