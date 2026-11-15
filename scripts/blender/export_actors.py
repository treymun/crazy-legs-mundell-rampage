"""Export the enemies and bosses as rigged, animated meshes for the 3D view.

    blender -b -P scripts/blender/export_actors.py -- <out dir> <kinds|all>

Every character is still built by enemy_actors.py's own code, a frame at a
time (idle, the four-beat walk, aim, wind-up, fire, pain, recover, fidget and
each kind's extras, the five steps of a fall and the body at rest; the hurt
set's limping frames for the regular hands). Each part it places (a capsule,
a ball, a box: enemy_actors.py place()) is recorded with where it sits in
every frame and matched across frames by its shape. Parts that move together
in every frame (the head and hat, a shin and its boot) become one bone, so
the rig is the character's own; each frame is one key of the action "poses"
(meshes.json says which frame is which).

The rest frame's parts, joined, are the mesh, bound rigidly to those bones,
unwrapped once; its look is baked onto that unwrap from the frame's own
materials (<kind>.png), from the hurt build (<kind>_hurt.png: blood, the split
brow, the gut wound) and, for a boss, from each phase's battle damage
(<kind>_p2.png, <kind>_p3.png). Writes <kind>.glb and actors.json:
{kind: {frames: {name: key}, height, textures: [...], parts, bones}}.
godot/tools/art/build_actor_meshes.gd runs it and commits the textures to the
palette. Nothing here is traced from another game.
"""
import json
import math
import os
import sys

import bpy
import numpy
from mathutils import Matrix, Vector

_ARGS = sys.argv[sys.argv.index("--") + 1:]
_OUT, _KINDS = os.path.abspath(_ARGS[0]), _ARGS[1]
_HERE = os.path.dirname(os.path.abspath(__file__))
sys.argv = [sys.argv[0], "--", _OUT, "billy", "all", "1"]
with open(os.path.join(_HERE, "enemy_actors.py"), encoding="utf-8") as _lib:
    _source = _lib.read()
exec(_source[: _source.rstrip().rfind("main()")], globals())

TEXTURE = 512
RECORD = []
_place = place


def place(bm, matrix, material, smooth=True):  # noqa: F811 - wraps the library's
    ob = _place(bm, matrix, material, smooth)
    RECORD.append(ob)
    return ob


def _root_for(S, frame, own):
    """The whole body's turn for a frame (enemy_actors.py main()): a fall
    topples it, the body at rest lies on its back."""
    upright = S.get("upright", False)
    if own:
        return Matrix.Identity(4)
    if isinstance(frame, str) and frame.startswith("die_") and not upright:
        return R((-.10, -.36, -.74, -1.12, -1.42)[int(frame[4:])], 0, 0)
    if frame == "down" and not upright:
        return R(0, 0, math.pi / 2) @ T((0, 0, S["depth"])) @ R(-math.pi / 2, 0, 0)
    return Matrix.Identity(4)


def _fingerprint(ob):
    """What a part is, whatever frame it is in: its vertex count, its own
    (unplaced) shape's size and the scale it is placed at."""
    me = ob.data
    lo = [min(v.co[i] for v in me.vertices) for i in range(3)]
    hi = [max(v.co[i] for v in me.vertices) for i in range(3)]
    scale = ob.matrix_basis.to_scale()
    return (len(me.vertices),) + tuple(round(hi[i] - lo[i], 3) for i in range(3)) + tuple(
        round(abs(s), 3) for s in scale
    )


def _build(kind, frame, wound, damage):
    """Pose and dress one frame; the parts placed, in order, with their prints
    and where each sits (ROOT included)."""
    global DAMAGE, WOUND, KIND, LAST_J, NOHEAD
    make, S, extra, own = ACTORS[kind]
    clear()
    RECORD.clear()
    DAMAGE, WOUND, KIND, LAST_J, NOHEAD = damage, wound, kind, None, False
    make(frame)
    if wound:
        wound_marks(kind, frame)
    root = _root_for(S, frame, own)
    ROOT.matrix_basis = root
    bpy.context.view_layer.update()
    parts = [(ob, _fingerprint(ob), ob.matrix_world.copy()) for ob in RECORD if ob.name in bpy.data.objects]
    DAMAGE, WOUND = 0, 0
    return parts


def _label(c, skeleton):
    """Which part of the body a bone at c (rest frame) carries: head, an arm or
    a leg (_r is the character's right, at -X) or the body; creatures without
    a skeleton are all body. Limb loss (src/gore_extras.gd) hides a limb's."""
    if skeleton is None:
        return "body"
    S, J = skeleton
    if "torso" not in J or "hipR" not in J:
        return "body"
    neck = J["neck"]
    head = J["head"] @ Vector((0, 0, 0))
    if (c - head).length < .32 and c.z > neck.z - .03:
        return "head"
    if c.z < J["hipR"].z - .06:
        return "leg_r" if c.x < 0 else "leg_l"
    if abs(c.x) > abs(J["shR"].x) * .85 and c.z < neck.z:
        return "arm_r" if c.x < 0 else "arm_l"
    return "body"


def _frames(kind):
    """[(frame to build, wound, key name)]: the rest frame first; the walk's
    first beat again after its last (`w4`) so the walk loops smoothly."""
    make, S, extra, own = ACTORS[kind]
    if own:
        living = [(f, str(f)) for f in own]
        dying = []
    else:
        living = [(0, "0"), ("w0", "w0"), ("w1", "w1"), ("w2", "w2"), ("w3", "w3"), ("w0", "w4")]
        living += [(f, f) for f in ["aim", "wind", "fire", "pain", "recover"] + list(extra)]
        dying = [("die_%d" % k, "die_%d" % k) for k in range(5)] + [("down", "down")]
    out = [(f, 0, n) for f, n in living] + [(f, 0, n) for f, n in dying]
    if kind not in BOSS_PHASES and not own:
        out += [(f, 1, "hurt_" + n) for f, n in living if f != "fidget"]
    return out


def _match(rest, parts):
    """For each rest part, its place in this frame (or None): parts are paired
    in order within each print."""
    pool = {}
    for _ob, fp, world in parts:
        pool.setdefault(fp, []).append(world)
    used = {}
    out = []
    for _ob, fp, _world in rest:
        k = used.get(fp, 0)
        found = pool.get(fp, [])
        out.append(found[k] if k < len(found) else None)
        used[fp] = k + 1
    return out


# The ways round the body faces the stage while its look is baked.
TURNS = (0, 180, 90, 270)
# The body's normal at each texel (_bake_normals), for the turns' weights.
NORMALS = None


def _bake(ob, image, sources=None):
    for slot in ob.material_slots:
        m = slot.material
        if m is None or m.node_tree is None:
            continue
        node = m.node_tree.nodes.get("bake_target")
        if node is None:
            node = m.node_tree.nodes.new("ShaderNodeTexImage")
            node.name = "bake_target"
        node.image = image
        m.node_tree.nodes.active = node
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 8
    # The device the stage chose (the graphics card when Cycles has one).
    bpy.ops.object.select_all(action="DESELECT")
    if sources:
        for s in sources:
            s.select_set(True)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    # The look as the cels were lit: the dusk stage (light_for) on the body
    # facing it; emissive parts glow; the sheen the grey sky lays on
    # everything (it greys the cels' colours). The cels were all lit from the
    # camera's side, whichever way the body faced (a back cel, a body lying
    # face down): so the body is baked facing the stage four ways round, and
    # each texel takes its light from the turns in which its own surface
    # faced the stage's camera (at -y), weighted by how squarely (its normal,
    # NORMALS, baked once). A texel facing up or down gets the four alike.
    turned = [ob] + list(sources or [])
    kept = [o.matrix_world.copy() for o in turned]
    total = None
    weight = None
    nx = NORMALS[:, 0] * 2.0 - 1.0
    ny = NORMALS[:, 1] * 2.0 - 1.0
    for k, angle in enumerate(TURNS):
        spin = Matrix.Rotation(math.radians(angle), 4, "Z")
        for o, m in zip(turned, kept):
            o.matrix_world = spin @ m
        bpy.context.view_layer.update()
        scene.cycles.samples = 48 if k == 0 else 32
        bpy.ops.object.bake(
            type="COMBINED",
            pass_filter={"EMIT", "DIRECT", "INDIRECT", "DIFFUSE", "GLOSSY"},
            margin=4,
            use_clear=True,
            use_selected_to_active=bool(sources),
            cage_extrusion=.03,
            max_ray_distance=.08,
        )
        px = numpy.empty(len(image.pixels), dtype=numpy.float32)
        image.pixels.foreach_get(px)
        px = px.reshape(-1, 4)
        if sources:
            # Texels the rays missed (a surface of the lighter mesh further
            # than max_ray_distance from its part: inner arms and thighs,
            # undersides, seen when a body lies down) bake black: bake again
            # with longer rays and take those texels from it.
            inside = NORMALS[:, :3].sum(axis=1) > .05
            missed = inside & (px[:, :3].sum(axis=1) < .003)
            if missed.any():
                bpy.ops.object.bake(
                    type="COMBINED",
                    pass_filter={"EMIT", "DIRECT", "INDIRECT", "DIFFUSE", "GLOSSY"},
                    margin=4,
                    use_clear=True,
                    use_selected_to_active=True,
                    cage_extrusion=.12,
                    max_ray_distance=.35,
                )
                far = numpy.empty(len(image.pixels), dtype=numpy.float32)
                image.pixels.foreach_get(far)
                far = far.reshape(-1, 4)
                px[missed, :3] = far[missed, :3]
                still = inside & (px[:, :3].sum(axis=1) < .003)
                if still.any():
                    # What no ray finds (a surface inside another part, or one
                    # the decimation moved far): the body baked onto itself,
                    # its own materials (their colours; a pattern may sit a
                    # little differently). Only the body is selected for it:
                    # the parts have no unwrap of their own.
                    for part in sources:
                        part.select_set(False)
                    bpy.ops.object.bake(
                        type="COMBINED",
                        pass_filter={"EMIT", "DIRECT", "INDIRECT", "DIFFUSE", "GLOSSY"},
                        margin=4,
                        use_clear=True,
                        use_selected_to_active=False,
                    )
                    for part in sources:
                        part.select_set(True)
                    ob.select_set(True)
                    bpy.context.view_layer.objects.active = ob
                    own = numpy.empty(len(image.pixels), dtype=numpy.float32)
                    image.pixels.foreach_get(own)
                    own = own.reshape(-1, 4)
                    px[still, :3] = own[still, :3]
                left = inside & (px[:, :3].sum(axis=1) < .003)
                print(
                    "ACTOR BAKE turn %d: %d texels missed, %d after longer rays, %d after its own"
                    % (angle, int(missed.sum()), int(still.sum()), int(left.sum()))
                )
        # The texel's normal turned with the body, toward the camera (-y).
        c = math.cos(math.radians(angle))
        sn = math.sin(math.radians(angle))
        toward = -(sn * nx + c * ny)
        w = numpy.clip(toward, 0.0, 1.0) ** 2 + 1e-4
        if total is None:
            total = px.copy()
            total[:, :3] *= w[:, None]
            weight = w.copy()
        else:
            total[:, :3] += px[:, :3] * w[:, None]
            weight += w
    for o, m in zip(turned, kept):
        o.matrix_world = m
    bpy.context.view_layer.update()
    total[:, :3] /= weight[:, None]
    image.pixels.foreach_set(total.ravel())


def _bake_normals(ob):
    """The body's object-space normal at each texel (NORMALS, 0..1 per axis)."""
    global NORMALS
    image = bpy.data.images.new("normals", TEXTURE, TEXTURE, alpha=False, float_buffer=True)
    image.colorspace_settings.name = "Non-Color"
    for slot in ob.material_slots:
        m = slot.material
        if m is None or m.node_tree is None:
            continue
        node = m.node_tree.nodes.get("bake_target")
        if node is None:
            node = m.node_tree.nodes.new("ShaderNodeTexImage")
            node.name = "bake_target"
        node.image = image
        m.node_tree.nodes.active = node
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 1
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.bake(type="NORMAL", normal_space="OBJECT", margin=4, use_clear=True)
    px = numpy.empty(len(image.pixels), dtype=numpy.float32)
    image.pixels.foreach_get(px)
    NORMALS = px.reshape(-1, 4)
    bpy.data.images.remove(image)


def _bake_ao(ob, image):
    """Ambient occlusion of the body's own surface into `image`."""
    for slot in ob.material_slots:
        m = slot.material
        if m is None or m.node_tree is None:
            continue
        node = m.node_tree.nodes.get("bake_target")
        if node is None:
            node = m.node_tree.nodes.new("ShaderNodeTexImage")
            node.name = "bake_target"
        node.image = image
        m.node_tree.nodes.active = node
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 32
    scene.world.light_settings.distance = .25
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.bake(type="AO", margin=4, use_clear=True, use_selected_to_active=False)


def _shaded(image, shade):
    """The look times the creases' shade, softened (a crease darkens to 70%)."""
    px = list(image.pixels)
    sh = shade.pixels[:]
    for i in range(0, len(px), 4):
        k = .7 + .3 * sh[i]
        px[i] *= k
        px[i + 1] *= k
        px[i + 2] *= k
    image.pixels[:] = px


def _save(image, path):
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()


def export(kind, meta):
    make, S, extra, own = ACTORS[kind]
    frames = _frames(kind)
    # Every frame but the rest one first (their parts are only measured); the
    # rest frame last, whose parts are kept as the mesh.
    places = {}
    for frame, wound, name in frames[1:]:
        if (frame, wound) not in places:
            places[(frame, wound)] = _build(kind, frame, wound, 0)
    rest = _build(kind, frames[0][0], 0, 0)
    skeleton = LAST_J
    tracks = [[w for _ob, _fp, w in rest]]
    for frame, wound, name in frames[1:]:
        tracks.append(_match(rest, places[(frame, wound)]))
    # Bones: parts whose motion from the rest frame is the same in every frame.
    clusters = {}
    order = []
    for i, (ob, fp, w0) in enumerate(rest):
        inv = w0.inverted()
        key = []
        for t in range(len(frames)):
            w = tracks[t][i]
            if w is None:
                key.append(("gone", i))
                continue
            d = w @ inv
            key.append(tuple(round(d[r][c], 2) for r in range(3) for c in range(4)))
        key = tuple(key)
        if key not in clusters:
            clusters[key] = []
            order.append(key)
        clusters[key].append(i)
    # A round ball (a joint's cap, an eye) looks the same however it turns:
    # it joins any bigger cluster that carries its centre where it goes.
    def _round(i):
        fp = rest[i][1]
        return abs(fp[4] - fp[5]) < .002 and abs(fp[5] - fp[6]) < .002 and abs(fp[1] - fp[2]) < .01 and abs(fp[2] - fp[3]) < .01

    def _carries(key, i):
        j = clusters[key][0]
        c0 = rest[i][2].translation
        inv = rest[j][2].inverted()
        for t in range(len(frames)):
            wj, wi = tracks[t][j], tracks[t][i]
            if (wj is None) != (wi is None):
                return False
            if wi is None:
                continue
            if ((wj @ inv) @ c0 - wi.translation).length > .004:
                return False
        return True

    for key in list(order):
        members = clusters[key]
        if not all(_round(i) for i in members):
            continue
        for other in order:
            if other == key or other not in clusters or all(_round(i) for i in clusters[other]):
                continue
            if all(_carries(other, i) for i in members):
                clusters[other].extend(members)
                del clusters[key]
                order.remove(key)
                break
    centres = []
    for key in order:
        c = Vector()
        for i in clusters[key]:
            c += rest[i][2].translation
        centres.append(c / len(clusters[key]))
    # The mesh: the rest frame's parts, each in its bone's group, joined.
    for b, key in enumerate(order):
        for i in clusters[key]:
            ob = rest[i][0]
            group = ob.vertex_groups.new(name="b%d" % b)
            group.add(list(range(len(ob.data.vertices))), 1.0, "REPLACE")
    objs = [ob for ob, _fp, _w in rest]
    for ob in objs:
        world = ob.matrix_world.copy()
        ob.parent = None
        ob.matrix_world = world
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = kind
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    height = max(v.co.z for v in body.data.vertices)
    # The parts were made for big renders: two fifths of the faces reads the same
    # at the view's size (vertex groups survive the collapse); the game makes
    # lighter copies of the mesh for distance itself.
    decimate = body.modifiers.new("fewer", "DECIMATE")
    decimate.ratio = .4
    bpy.ops.object.modifier_apply(modifier="fewer")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.01)
    bpy.ops.object.mode_set(mode="OBJECT")
    textures = []
    light_for(bpy.context.scene, kind in BOSS_PHASES)
    image = bpy.data.images.new("bake", TEXTURE, TEXTURE, alpha=False)
    # The creases' shade (eye sockets, under a brim, between fingers), the
    # soft part of the cels' lighting that does not turn with the camera.
    shade = bpy.data.images.new("shade", TEXTURE, TEXTURE, alpha=False)
    _bake_ao(body, shade)
    _bake_normals(body)
    # Each look is baked from its own build's separate parts: the materials'
    # patterns (plaid, grime, stripes) sit on each part's own coordinates,
    # which the joined mesh no longer has.
    source = [ob for ob, _fp, _w in _build_kept(kind, frames[0][0], 0, 0)]
    _bake(body, image, source)
    for ob in source:
        bpy.data.objects.remove(ob)
    _shaded(image, shade)
    _save(image, os.path.join(_OUT, "%s.png" % kind))
    textures.append("")
    # The hurt set and a boss's phases, baked from their own build onto the
    # same unwrap.
    looks = []
    if kind in BOSS_PHASES:
        looks = [("p2", 0, 1), ("p3", 0, 2)]
    elif not own:
        looks = [("hurt", 1, 0)]
    for tag, wound, damage in looks:
        source = [ob for ob, _fp, _w in _build_kept(kind, frames[0][0], wound, damage)]
        _bake(body, image, source)
        _shaded(image, shade)
        _save(image, os.path.join(_OUT, "%s_%s.png" % (kind, tag)))
        textures.append(tag)
        for ob in source:
            bpy.data.objects.remove(ob)
    bpy.data.images.remove(image)
    bpy.data.images.remove(shade)
    # The rig: one bone a cluster, each frame a key.
    data = bpy.data.armatures.new("rig")
    rig = bpy.data.objects.new("rig_" + kind, data)
    bpy.context.scene.collection.objects.link(rig)
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    for b, c in enumerate(centres):
        bone = data.edit_bones.new("b%d" % b)
        bone.head = c
        bone.tail = c + Vector((0, 0, .08))
    bpy.ops.object.mode_set(mode="POSE")
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
    rig.animation_data_create()
    action = bpy.data.actions.new("poses")
    rig.animation_data.action = action
    names = {}
    for t, (frame, wound, name) in enumerate(frames):
        names[name] = t
        for b, key in enumerate(order):
            i = clusters[key][0]
            pb = rig.pose.bones["b%d" % b]
            rest_m = data.bones["b%d" % b].matrix_local
            w = tracks[t][i]
            if w is None:
                d = Matrix.Translation(centres[b]) @ Matrix.Diagonal((1e-4, 1e-4, 1e-4, 1)) @ Matrix.Translation(-centres[b])
            else:
                d = w @ rest[i][2].inverted()
            pb.matrix = d @ rest_m
            bpy.context.view_layer.update()
            pb.keyframe_insert("location", frame=t)
            pb.keyframe_insert("rotation_quaternion", frame=t)
            pb.keyframe_insert("scale", frame=t)
    bpy.ops.object.mode_set(mode="OBJECT")
    body.parent = rig
    mod = body.modifiers.new("rig", "ARMATURE")
    mod.object = rig
    body.data.materials.clear()
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(_OUT, kind + ".glb"),
        export_format="GLB",
        use_selection=True,
        export_materials="NONE",
        export_yup=True,
        export_animations=True,
        export_skins=True,
        export_morph=False,
        export_force_sampling=False,
        export_def_bones=False,
    )
    meta[kind] = {
        "frames": names,
        "height": round(height, 3),
        "textures": textures,
        "parts": len(rest),
        "bones": len(order),
        "faces": len(body.data.polygons),
        # The looks carry the dusk stage's light (the game adds only a turn's shade).
        "lit": True,
        "labels": {"b%d" % b: _label(c, skeleton) for b, c in enumerate(centres)},
        # The cels' canvas (map units): the game draws a kind enemies.cfg
        # height tall for this canvas height, so a model is scaled by the same.
        "canvas": [S["canvas"][0], S["canvas"][1]],
    }
    print("ACTOR %s: %d parts, %d bones, %d frames" % (kind, len(rest), len(order), len(frames)))
    for ob in [o for o in bpy.data.objects if o.type in ("MESH", "ARMATURE")]:
        bpy.data.objects.remove(ob)
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)


def _build_kept(kind, frame, wound, damage):
    """A frame built and kept apart from ROOT (a bake's source). The hurt
    build stands as the rest frame does (no limp, which skeleton() would
    lean it into), so its wounds land where the mesh's surface is; the limp
    is the hurt frames' own pose in the action."""
    S = ACTORS[kind][1]
    limps = S.get("limps", None)
    S["limps"] = False
    parts = _build(kind, frame, wound, damage)
    if limps is None:
        del S["limps"]
    else:
        S["limps"] = limps
    for ob, _fp, _w in parts:
        world = ob.matrix_world.copy()
        ob.parent = None
        ob.matrix_world = world
    return parts


def run():
    stage()
    os.makedirs(_OUT, exist_ok=True)
    kinds = list(ACTORS) if _KINDS == "all" else _KINDS.split(",")
    meta_path = os.path.join(_OUT, "actors.json")
    meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
    for kind in kinds:
        if kind not in ACTORS:
            print("ACTOR %s: not a kind" % kind)
            continue
        export(kind, meta)
        json.dump(meta, open(meta_path, "w"), indent=1, sort_keys=True)


try:
    run()
except Exception:
    # Blender exits 0 after a script's error; the build tool must know.
    import traceback

    traceback.print_exc()
    sys.stdout.flush()
    os._exit(1)
