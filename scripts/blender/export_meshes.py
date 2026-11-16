"""Export the props as meshes for the 3D view: each modelled by the same code
that renders its sprite (town_props.py and the scripts it loads, or another
library that runs it), joined into one mesh, unwrapped, its materials and the
dusk stage's light baked into one small texture, then written as a glTF.

    blender -b -P scripts/blender/export_meshes.py -- <out dir> <names|all> <library.py>

<library.py> is town_props.py (the town and every chapter's props, the broken
ones too), props_range.py, quest_props.py, painted_boards.py or
vehicle_cabs.py (the vehicles' seat views: parts in one glb, not dropped to
the ground, up to CAB_MOST texels). Writes
<out dir>/<name>.glb (the mesh, map units, its front toward glTF +Z),
<out dir>/<name>.png (the baked texture) and meshes.json ({name: [width,
depth, height, texture size]}). godot/tools/art/build_prop_meshes.gd runs it
and commits the textures to the palette.

A quest station (quest_props.py STATIONS) is one model with two looks, both
in one glb and one texture: mesh objects `look_off` (still to do) and
`look_on` (done), shrunk by its SCALE as its pictures were; PropView shows
the one its picture names (town_quest_<name>_off / _on). Props drawn flat in
the old game (FLAT: laundry, the shelves and boards) are exported as the
models they are; the range's targets (KEEP_FLAT) stay pictures. These
(stations and FLAT props, modelled after v3.0.0) bake faithfully: their
materials' shine too (painted metal as bright as their pictures showed it)
and each part's patterns (grime, planks, hazard stripes) laid out by that
part's own coordinates, as its sprite was rendered, not the joined mesh's.
The props modelled before them were baked without either.
"""
import json
import math
import os
import sys

import bpy
from mathutils import Matrix

_ARGS = sys.argv[sys.argv.index("--") + 1:]
_OUT, _NAMES, _LIBRARY = os.path.abspath(_ARGS[0]), _ARGS[1], _ARGS[2]
_HERE = os.path.dirname(os.path.abspath(__file__))
# The library reads its own arguments (out dir, names, supersample).
sys.argv = [sys.argv[0], "--", _OUT, _NAMES, "1"]
with open(os.path.join(_HERE, _LIBRARY), encoding="utf-8") as _lib:
    _source = _lib.read().rstrip()
# The library without its last line when that renders (main(), quest_main()):
# this script has its own.
if _source[_source.rfind("\n") + 1:].strip().endswith("main()"):
    _source = _source[: _source.rfind("\n")]
exec(_source, globals())

# Texels per map unit of the baked texture: about what a prop's sprite has
# up close (the sprites are 60 px a unit before shrinking to game size). The
# faithful bakes (stations and FLAT props: walked right up to, read for their
# small lamps, spokes and painted letters) get more.
DENSITY = 64
CLOSE_DENSITY = 160
MOST = 512
# A cab fills the bottom of the driver's view: more texels across.
CAB_MOST = 1024
LEAST = 64
# Drawn by the range's own code as pictures (shot at, marked): not models.
KEEP_FLAT = {"range_target", "range_gong", "range_cow_target", "range_duck"}
# How far apart a station's two looks stand while they bake together.
LOOK_GAP = 30.0
# Each part's own object coordinates, kept through the join (faithful bakes).
PART_CO = "part_co"


def _clear():
    for ob in [o for o in bpy.data.objects if o.type in ("MESH", "EMPTY")]:
        bpy.data.objects.remove(ob)


def _models():
    """name -> [(look, make, scale)]: a station's two looks, a vehicle cab's
    parts (vehicle_cabs.py CABS), or a prop's one."""
    out = {}
    if "CABS" in globals():
        for name, parts in CABS.items():
            out[name] = [(part, make, 1.0) for part, make in parts]
        return out
    if "STATIONS" in globals():
        for name, make in STATIONS.items():
            size = SCALE.get(name, 1.0)
            out[name] = [("off", (lambda m=make: m(False)), size),
                         ("on", (lambda m=make: m(True)), size)]
        return out
    for name, make in PROPS.items():
        if name not in KEEP_FLAT:
            out[name] = [("", make, 1.0)]
    return out


def _joined(scene, done, faithful):
    """Every mesh of the look just built (not those in `done`) as one object,
    in map units, unparented. `faithful`: each part keeps its own object
    coordinates (attribute PART_CO) for the bake, as its sprite was rendered."""
    meshes = [o for o in scene.objects if o.type == "MESH" and o not in done]
    if not meshes:
        return None
    if faithful:
        for ob in meshes:
            co = [0.0] * (len(ob.data.vertices) * 3)
            ob.data.vertices.foreach_get("co", co)
            attr = ob.data.attributes.new(PART_CO, "FLOAT_VECTOR", "POINT")
            attr.data.foreach_set("vector", co)
    # The parts' places (location, rotation, scale under ROOT) reach
    # matrix_world only once the scene is evaluated.
    bpy.context.view_layer.update()
    for ob in meshes:
        world = ob.matrix_world.copy()
        ob.parent = None
        ob.matrix_world = world
    bpy.ops.object.select_all(action="DESELECT")
    for ob in meshes:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return ob


def _select(parts):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in parts:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]


def _shrink(ob, size):
    _select([ob])
    ob.scale = (size, size, size)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)


def _unwrap(parts, tight=False):
    # Every look at once (multi-object editing): their islands share one map.
    # `tight` (a cab: hundreds of small parts seen up close) packs the islands
    # with a hair's gap instead of smart project's own wide margins.
    _select(parts)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.0 if tight else 0.02)
    if tight:
        bpy.ops.uv.select_all(action="SELECT")
        bpy.ops.uv.pack_islands(rotate=True, margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")


def _part_coords(materials):
    """Point every material's object coordinates at PART_CO (each part's own,
    as in its sprite render, not the joined mesh's); returns how to undo it."""
    undo = []
    for m in materials:
        nt = m.node_tree
        for link in [lk for lk in nt.links if lk.from_node.type == "TEX_COORD" and lk.from_socket.name == "Object"]:
            attr = nt.nodes.new("ShaderNodeAttribute")
            attr.attribute_type = "GEOMETRY"
            attr.attribute_name = PART_CO
            to = link.to_socket
            nt.links.remove(link)
            nt.links.new(attr.outputs["Vector"], to)
            undo.append((m, attr, to))
    return undo


def _undo_coords(undo):
    for m, attr, to in undo:
        nt = m.node_tree
        coord = next(n for n in nt.nodes if n.type == "TEX_COORD")
        nt.nodes.remove(attr)
        nt.links.new(coord.outputs["Object"], to)


def _bake(parts, size, path, faithful):
    image = bpy.data.images.new("bake", size, size, alpha=False)
    seen = set()
    materials = []
    for ob in parts:
        for slot in ob.material_slots:
            m = slot.material
            if m is None or m.node_tree is None or m.name in seen:
                continue
            seen.add(m.name)
            materials.append(m)
            node = m.node_tree.nodes.new("ShaderNodeTexImage")
            node.image = image
            m.node_tree.nodes.active = node
    undo = _part_coords(materials) if faithful else []
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 24
    scene.cycles.device = "CPU"
    scene.render.bake.margin = 4
    _select(parts)
    bpy.ops.object.bake(
        type="COMBINED",
        pass_filter={"EMIT", "DIRECT", "INDIRECT", "DIFFUSE"} | ({"GLOSSY"} if faithful else set()),
        margin=4,
        use_clear=True,
    )
    _undo_coords(undo)
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)
    # The image nodes go again: the next prop may share these materials.
    for m in bpy.data.materials:
        if m.node_tree is not None:
            for node in [n for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image is None]:
                m.node_tree.nodes.remove(node)


def _export(parts, path):
    # The mesh alone: the game draws it with its own shader and the baked
    # texture (which goes through the palette like every picture).
    for ob in parts:
        ob.data.materials.clear()
    _select(parts)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_materials="NONE",
        export_yup=True,
        export_apply=True,
        export_normals=True,
        export_texcoords=True,
    )


def run():
    global ROOT
    scene, _camera = stage()
    os.makedirs(_OUT, exist_ok=True)
    table = _models()
    names = list(table) if _NAMES == "all" else [n for n in _NAMES.split(",") if n in table]
    meta_path = os.path.join(_OUT, "meshes.json")
    meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
    for name in names:
        _clear()
        parts = []
        faithful = len(table[name]) > 1 or name in FLAT
        for look, make, size in table[name]:
            ROOT = bpy.data.objects.new("root", None)
            scene.collection.objects.link(ROOT)
            make()
            ob = _joined(scene, parts, faithful)
            if ob is None:
                break
            if size != 1.0:
                _shrink(ob, size)
            ob.name = "look_" + look if look else name
            parts.append(ob)
        if not parts or len(parts) != len(table[name]):
            continue
        # Feet on the ground: the sprite was cropped to its lowest pixel and
        # stood there (a rack modelled up a wall stands at its own bottom).
        # A cab stays where it was modelled (the driver's eye at the origin,
        # each moving part about its pivot).
        cab = "CABS" in globals()
        drop = 0.0 if cab else min(v.co[2] for ob in parts for v in ob.data.vertices)
        if abs(drop) > 1e-4:
            for ob in parts:
                ob.data.transform(Matrix.Translation((0, 0, -drop)))
        verts = [v.co for ob in parts for v in ob.data.vertices]
        lo = [min(v[i] for v in verts) for i in range(3)]
        hi = [max(v[i] for v in verts) for i in range(3)]
        dims = [hi[i] - lo[i] for i in range(3)]
        area = (dims[0] * dims[1] + dims[1] * dims[2] + dims[0] * dims[2]) * len(parts)
        density = CLOSE_DENSITY if faithful else DENSITY
        size = 1 << max(0, int(math.ceil(math.log2(max(1.0, math.sqrt(area) * density)))))
        size = max(LEAST, min(CAB_MOST if cab else MOST, size))
        # The looks bake side by side (far enough apart not to shade each other).
        for k, ob in enumerate(parts):
            ob.location = (k * LOOK_GAP, 0, 0)
        _unwrap(parts, cab)
        _bake(parts, size, os.path.join(_OUT, name + ".png"), faithful)
        for ob in parts:
            ob.location = (0, 0, 0)
        _export(parts, os.path.join(_OUT, name + ".glb"))
        meta[name] = [round(dims[0], 3), round(dims[1], 3), round(hi[2], 3), size]
        print("MESH %s %dpx %.2fx%.2fx%.2f %d look(s)" % (name, size, dims[0], dims[1], hi[2], len(parts)))
    json.dump(meta, open(meta_path, "w"), indent=1, sort_keys=True)


run()
