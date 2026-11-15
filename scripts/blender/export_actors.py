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
# "rig": the mesh, unwrap and rig again without baking the looks (the unwrap
# is the same every run, so the committed textures still fit).
_RIG_ONLY = "rig" in _ARGS[2:]
_HERE = os.path.dirname(os.path.abspath(__file__))
sys.argv = [sys.argv[0], "--", _OUT, "billy", "all", "1"]
with open(os.path.join(_HERE, "enemy_actors.py"), encoding="utf-8") as _lib:
    _source = _lib.read()
exec(_source[: _source.rstrip().rfind("main()")], globals())

TEXTURE = 512
# The bosses with the most parts bake their looks twice as fine: at 512 their
# hundreds of parts each got a few texels, blocky and dark at the seams up
# close against their cels.
FINE = {"baron": 1024}
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


# How far a part's print may stray between frames and still be the same part
# (its largest difference, as a share of the size): the rounding of a placed
# scale that turned with the torso, a shin stretched by the walk, a finger
# curled in a fall.
NEAR = .1


def _match(rest, parts, root):
    """For each rest part, its place in this frame (or None): parts are paired
    in order within each print; a part left over then takes the nearest
    left-over print within NEAR of its own, the nearest to where it sits on
    the body (under the frame's `root`) when there are more."""
    pool = {}
    for _ob, fp, world in parts:
        pool.setdefault(fp, []).append(world)
    used = {}
    out = []
    taken = set()
    for _ob, fp, _world in rest:
        k = used.get(fp, 0)
        found = pool.get(fp, [])
        out.append(found[k] if k < len(found) else None)
        if k < len(found):
            taken.add((fp, k))
        used[fp] = k + 1
    spare = [(fp, w) for fp, ws in pool.items() for k, w in enumerate(ws) if (fp, k) not in taken]
    inv = root.inverted()
    for i, (_ob, fp, w0) in enumerate(rest):
        if out[i] is not None:
            continue
        best = None
        for n, (fq, w) in enumerate(spare):
            if fq[0] != fp[0]:
                continue
            stray = max(abs(a - b) / max(abs(a), abs(b), .02) for a, b in zip(fp[1:], fq[1:]))
            if stray > NEAR:
                continue
            cost = stray + ((inv @ w).translation - w0.translation).length
            if best is None or cost < best[0]:
                best = (cost, n)
        if best is not None:
            out[i] = spare.pop(best[1])[1]
    return out


def _chain(name):
    """The frames a key is blended with (the walk's beats, a fall's steps):
    a part missing from one is shrunk where it was in its neighbour."""
    if name.startswith("die_") or name == "down":
        return "fall"
    bare = name[5:] if name.startswith("hurt_") else name
    if len(bare) == 2 and bare[0] == "w" and bare[1].isdigit():
        return name[:-2] + "walk"
    return name


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
        # One bake a turn. The rays reach well past the lighter mesh's surface
        # (it sits inside or outside its parts after the decimation: inner
        # arms and thighs and undersides, seen when a body lies down, baked
        # black with short ones); the nearest hit still wins. Fewer samples
        # than a render: the palette and the grain take the noise.
        # A finer texture takes fewer samples a texel (four texels share a
        # pixel of the coarse one; the palette takes the rest of the noise).
        scene.cycles.samples = (24 if k == 0 else 16) * 512 // TEXTURE + 4 * (TEXTURE > 512)
        bpy.ops.object.bake(
            type="COMBINED",
            pass_filter={"EMIT", "DIRECT", "INDIRECT", "DIFFUSE", "GLOSSY"},
            margin=TEXTURE // 128,
            use_clear=True,
            use_selected_to_active=bool(sources),
            cage_extrusion=.1,
            max_ray_distance=.3,
        )
        px = numpy.empty(len(image.pixels), dtype=numpy.float32)
        image.pixels.foreach_get(px)
        px = px.reshape(-1, 4)
        if k == 0:
            inside = NORMALS[:, :3].sum(axis=1) > .05
            dark = int((inside & (px[:, :3].sum(axis=1) < .003)).sum())
            print("ACTOR BAKE on %s: %d black texels of %d" % (scene.cycles.device, dark, int(inside.sum())))
        # The texel's normal turned with the body, toward the camera (-y).
        c = math.cos(math.radians(angle))
        sn = math.sin(math.radians(angle))
        toward = -(sn * nx + c * ny)
        # A texel whose ray found nothing in this turn bakes black: it takes
        # no part in the blend (it would darken the texel, speckling faces).
        hit = px[:, :3].sum(axis=1) > .003
        w = (numpy.clip(toward, 0.0, 1.0) ** 2 + 1e-4) * hit
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
    found = weight > 0.0
    total[found, :3] /= weight[found, None]
    _fill_missed(total, found & (NORMALS[:, :3].sum(axis=1) > .05))
    image.pixels.foreach_set(total.ravel())


def _fill_missed(px, found):
    """Texels on the body no turn's ray reached take their neighbours' colour."""
    size = TEXTURE
    rgb = px[:, :3].reshape(size, size, 3)
    have = found.reshape(size, size) | (NORMALS[:, :3].sum(axis=1) <= .05).reshape(size, size)
    # Texels off the body count as found only for the margin's sake: they
    # never feed a fill (their colour is the bake's padding).
    good = found.reshape(size, size).copy()
    missing = ~have
    print("ACTOR BAKE: %d texels no turn reached" % int(missing.sum()))
    for _ in range(24):
        if not missing.any():
            break
        acc = numpy.zeros_like(rgb)
        cnt = numpy.zeros((size, size), dtype=numpy.float32)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
            g = numpy.roll(numpy.roll(good, dy, 0), dx, 1)
            acc += numpy.roll(numpy.roll(rgb, dy, 0), dx, 1) * g[:, :, None]
            cnt += g
        take = missing & (cnt > 0)
        rgb[take] = acc[take] / cnt[take][:, None]
        good |= take
        missing &= ~take
    px[:, :3] = rgb.reshape(-1, 3)


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
    bpy.ops.object.bake(type="NORMAL", normal_space="OBJECT", margin=TEXTURE // 128, use_clear=True)
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
    bpy.ops.object.bake(type="AO", margin=TEXTURE // 128, use_clear=True, use_selected_to_active=False)


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
    global TEXTURE
    make, S, extra, own = ACTORS[kind]
    TEXTURE = FINE.get(kind, 512)
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
        tracks.append(_match(rest, places[(frame, wound)], _root_for(S, frame, own)))
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
    if _RIG_ONLY:
        _carry_uvs(body, kind)
    else:
        _unwrap(body, kind)
    textures = [""]
    looks = []
    if kind in BOSS_PHASES:
        looks = [("p2", 0, 1), ("p3", 0, 2)]
    elif not own:
        looks = [("hurt", 1, 0)]
    textures += [tag for tag, _w, _d in looks]
    if not _RIG_ONLY:
        _bake_looks(kind, body, frames[0][0], looks)
    _rig(kind, body, frames, order, clusters, centres, tracks, rest)
    meta[kind] = {
        "frames": {name: t for t, (_f, _w, name) in enumerate(frames)},
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


# The packing's gap between islands, a share of the texture (two texels at
# 1024). It was .01 in smart_project: a boss's hundreds of rivets, each cut in
# several islands, then took most of the texture in gaps and his belly a
# corner of it.
GAP = .002


def _unwrap(body, kind):
    """Cut the body into islands (smart project) and pack them tightly by
    their shapes, each the same texels a metre."""
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.0)
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(rotate=True, margin_method="FRACTION", margin=GAP, shape_method="CONCAVE")
    bpy.ops.object.mode_set(mode="OBJECT")
    import bmesh as _bm

    bm = _bm.new()
    bm.from_mesh(body.data)
    uv = bm.loops.layers.uv.active
    area = 0.0
    for face in bm.faces:
        pts = [loop[uv].uv for loop in face.loops]
        area += abs(sum(pts[k].x * pts[k - 1].y - pts[k - 1].x * pts[k].y for k in range(len(pts)))) / 2
    bm.free()
    print("ACTOR %s: unwrap covers %d%% of the texture" % (kind, round(area * 100)))


def _carry_uvs(body, kind):
    """The committed model's unwrap onto this body (the same parts, decimated
    alike), so its baked looks still fit: each face takes the corners of the
    old face nearest its centre, each corner the nearest of them."""
    from mathutils.kdtree import KDTree

    # Faces as the old model has them (glTF keeps triangles).
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.quads_convert_to_tris(quad_method="FIXED", ngon_method="CLIP")
    bpy.ops.object.mode_set(mode="OBJECT")
    path = os.path.join(_HERE, "..", "..", "godot", "assets3d", "actors", kind + ".glb")
    objects = set(bpy.data.objects)
    actions = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in objects]
    # The body (the importer adds a little sphere of its own to draw bones).
    old = max((o for o in new if o.type == "MESH"), key=lambda o: len(o.data.polygons))
    om, mw = old.data, old.matrix_world
    ouv = om.uv_layers.active.data
    near = KDTree(len(om.polygons))
    for poly in om.polygons:
        near.insert(mw @ poly.center, poly.index)
    near.balance()
    me = body.data
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    uv = me.uv_layers.new(name="UVMap").data
    exact = 0
    for poly in me.polygons:
        _co, j, dist = near.find(poly.center)
        exact += dist < 1e-4
        corners = [(mw @ om.vertices[om.loops[k].vertex_index].co, k) for k in om.polygons[j].loop_indices]
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            uv[li].uv = ouv[min(corners, key=lambda c: (c[0] - v).length_squared)[1]].uv
    print("ACTOR %s: unwrap carried, %d of %d faces exact" % (kind, exact, len(me.polygons)))
    for o in new:
        bpy.data.objects.remove(o)
    for a in [a for a in bpy.data.actions if a not in actions]:
        bpy.data.actions.remove(a)
    bpy.context.view_layer.objects.active = body


def _bake_looks(kind, body, rest_frame, looks):
    """Bake the plain look and each of `looks` ([(tag, wound, damage)]) onto the
    body's unwrap, as <kind>[_<tag>].png."""
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
    source = [ob for ob, _fp, _w in _build_kept(kind, rest_frame, 0, 0)]
    _bake(body, image, source)
    for ob in source:
        bpy.data.objects.remove(ob)
    _shaded(image, shade)
    _save(image, os.path.join(_OUT, "%s.png" % kind))
    # The hurt set and a boss's phases, baked from their own build onto the
    # same unwrap.
    for tag, wound, damage in looks:
        source = [ob for ob, _fp, _w in _build_kept(kind, rest_frame, wound, damage)]
        _bake(body, image, source)
        _shaded(image, shade)
        _save(image, os.path.join(_OUT, "%s_%s.png" % (kind, tag)))
        for ob in source:
            bpy.data.objects.remove(ob)
    bpy.data.images.remove(image)
    bpy.data.images.remove(shade)


def _rig(kind, body, frames, order, clusters, centres, tracks, rest):
    """The rig: one bone a cluster, each frame a key; exported with the body
    as <kind>.glb."""
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
    # Keys meet in straight lines: Godot samples the action between keys, and
    # a curve overshoots there (a part shrunk away in one key and whole in the
    # next came back as a speck in mid-air).
    for t, (frame, wound, name) in enumerate(frames):
        # A frame built of other parts altogether (the derby champ's wreck
        # keeps a few wheels of his truck) holds the rest where the frame
        # before it had them, whole, rather than leaving a few parts.
        held = sum(w is not None for w in tracks[t]) < len(rest) / 2
        for b, key in enumerate(order):
            i = clusters[key][0]
            pb = rig.pose.bones["b%d" % b]
            rest_m = data.bones["b%d" % b].matrix_local
            w = tracks[t][i]
            if w is None:
                # Gone from this frame: shrunk where it is in the nearest
                # frame it is blended with (so it never flies off to where
                # it stood while it shrinks), else where it stands.
                near = None
                chain = _chain(name)
                for u in sorted(range(len(frames)), key=lambda u: abs(u - t)):
                    if tracks[u][i] is not None and _chain(frames[u][2]) == chain:
                        near = tracks[u][i] @ rest[i][2].inverted()
                        break
                c = centres[b]
                if near is not None and held:
                    d = near
                else:
                    near = near or Matrix.Identity(4)
                    d = near @ Matrix.Translation(c) @ Matrix.Diagonal((1e-4, 1e-4, 1e-4, 1)) @ Matrix.Translation(-c)
            else:
                d = w @ rest[i][2].inverted()
            pb.matrix = d @ rest_m
            bpy.context.view_layer.update()
            pb.keyframe_insert("location", frame=t)
            pb.keyframe_insert("rotation_quaternion", frame=t)
            pb.keyframe_insert("scale", frame=t)
    for fc in _fcurves(action):
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
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


def _fcurves(action):
    """An action's curves (Blender 4.4 and later keep them in slots' bags)."""
    if hasattr(action, "fcurves"):
        return list(action.fcurves)
    out = []
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                out += list(bag.fcurves)
    return out


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
