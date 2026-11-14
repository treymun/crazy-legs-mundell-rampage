"""Export the props as meshes for the 3D view: each modelled by the same code
that renders its sprite (town_props.py and the scripts it loads, or another
library that runs it), joined into one mesh, unwrapped, its materials and the
dusk stage's light baked into one small texture, then written as a glTF.

    blender -b -P scripts/blender/export_meshes.py -- <out dir> <names|all> <library.py>

<library.py> is town_props.py (the town and every chapter's props, the broken
ones too), props_range.py or quest_props.py. Writes <out dir>/<name>.glb (the
mesh, map units, its front toward glTF +Z), <out dir>/<name>.png (the baked
texture) and meshes.json ({name: [width, depth, height, texture size]}).
godot/tools/art/build_prop_meshes.gd runs it and commits the textures to the
palette. Flat props (FLAT, drawn on a plane) are left out.
"""
import json
import math
import os
import sys

import bpy

_ARGS = sys.argv[sys.argv.index("--") + 1:]
_OUT, _NAMES, _LIBRARY = os.path.abspath(_ARGS[0]), _ARGS[1], _ARGS[2]
_HERE = os.path.dirname(os.path.abspath(__file__))
# The library reads its own arguments (out dir, names, supersample).
sys.argv = [sys.argv[0], "--", _OUT, _NAMES, "1"]
with open(os.path.join(_HERE, _LIBRARY), encoding="utf-8") as _lib:
    _source = _lib.read()
exec(_source[: _source.rstrip().rfind("main()")], globals())

# Texels per map unit of the baked texture: about what a prop's sprite has
# up close (the sprites are 60 px a unit before shrinking to game size).
DENSITY = 64
MOST = 512
LEAST = 64


def _clear():
    for ob in [o for o in bpy.data.objects if o.type in ("MESH", "EMPTY")]:
        bpy.data.objects.remove(ob)


def _joined(scene):
    """Every mesh of the prop as one object, in map units, unparented."""
    meshes = [o for o in scene.objects if o.type == "MESH"]
    if not meshes:
        return None
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


def _unwrap(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")


def _bake(ob, size, path):
    image = bpy.data.images.new("bake", size, size, alpha=False)
    for slot in ob.material_slots:
        m = slot.material
        if m is None or m.node_tree is None:
            continue
        node = m.node_tree.nodes.new("ShaderNodeTexImage")
        node.image = image
        m.node_tree.nodes.active = node
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 24
    scene.cycles.device = "CPU"
    scene.render.bake.margin = 4
    bpy.ops.object.bake(
        type="COMBINED",
        pass_filter={"EMIT", "DIRECT", "INDIRECT", "DIFFUSE"},
        margin=4,
        use_clear=True,
    )
    image.filepath_raw = path
    image.file_format = "PNG"
    image.save()
    bpy.data.images.remove(image)


def _export(ob, path):
    # The mesh alone: the game draws it with its own shader and the baked
    # texture (which goes through the palette like every picture).
    ob.data.materials.clear()
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
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
    names = list(PROPS) if _NAMES == "all" else _NAMES.split(",")
    names = [n for n in names if n in PROPS and n not in FLAT]
    meta_path = os.path.join(_OUT, "meshes.json")
    meta = json.load(open(meta_path)) if os.path.exists(meta_path) else {}
    for name in names:
        _clear()
        ROOT = bpy.data.objects.new("root", None)
        scene.collection.objects.link(ROOT)
        PROPS[name]()
        ob = _joined(scene)
        if ob is None:
            continue
        lo = [min(v.co[i] for v in ob.data.vertices) for i in range(3)]
        hi = [max(v.co[i] for v in ob.data.vertices) for i in range(3)]
        dims = [hi[i] - lo[i] for i in range(3)]
        area = dims[0] * dims[1] + dims[1] * dims[2] + dims[0] * dims[2]
        size = 1 << max(0, int(math.ceil(math.log2(max(1.0, math.sqrt(area) * DENSITY)))))
        size = max(LEAST, min(MOST, size))
        _unwrap(ob)
        _bake(ob, size, os.path.join(_OUT, name + ".png"))
        _export(ob, os.path.join(_OUT, name + ".glb"))
        meta[name] = [round(dims[0], 3), round(dims[1], 3), round(hi[2], 3), size]
        print("MESH %s %dpx %.2fx%.2fx%.2f" % (name, size, dims[0], dims[1], hi[2]))
    json.dump(meta, open(meta_path, "w"), indent=1, sort_keys=True)


run()
