"""Make a game-ready version of a Meshy model, the way the game's own
exporter (scripts/blender/export_meshes.py) makes its props: reduced mesh,
the dusk stage's light (town_props.py stage()) baked into one small texture.

  python optimize.py <in.glb> <out_dir> <name> <turn_deg> <height_m> <tris> <tex>

Writes <out_dir>/<name>_game.glb (mesh + baked texture, for viewing),
<name>_mesh.glb (mesh only, as the game's pipeline wants it) and
<name>_bake.png (the baked texture before the game's grading).
"""

import math
import os
import sys

import bpy
from mathutils import Vector

src, out, name = sys.argv[1], sys.argv[2], sys.argv[3]
turn, height, tris, tex = float(sys.argv[4]), float(sys.argv[5]), int(sys.argv[6]), int(sys.argv[7])
lo_src = sys.argv[8] if len(sys.argv) > 8 else ""
os.makedirs(out, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
world = bpy.data.worlds.new("world")
scene.world = world
world.use_nodes = True
nt = world.node_tree
nt.nodes.clear()
wout = nt.nodes.new("ShaderNodeOutputWorld")
bg = nt.nodes.new("ShaderNodeBackground")
bg.inputs[0].default_value = (0.62, 0.60, 0.56, 1)
bg.inputs[1].default_value = 0.5
nt.links.new(bg.outputs[0], wout.inputs[0])
# The game's dusk stage (scripts/blender/town_props.py stage()).
for lname, travel, power, color in (
    ("key", (0.50, 0.58, -0.70), 4.4, (1, 0.94, 0.84)),
    ("fill", (-0.7, 0.55, -0.25), 0.8, (0.80, 0.86, 1)),
    ("rim", (-0.35, -0.75, -0.55), 1.5, (1, 0.95, 0.85)),
):
    light = bpy.data.lights.new(lname, "SUN")
    light.energy = power
    light.color = color
    light.angle = math.radians(6)
    ob = bpy.data.objects.new(lname, light)
    ob.rotation_euler = Vector(travel).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(ob)

def load(path):
    before = set(scene.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    parts = [o for o in scene.objects if o.type == "MESH" and o not in before]
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.parent = None
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    ob.rotation_mode = "XYZ"
    ob.rotation_euler = (0, 0, math.radians(turn))
    bpy.ops.object.transform_apply(rotation=True)
    return ob


def place(ob, frame):
    lo_v, hi_v = frame
    s = height / (hi_v.z - lo_v.z)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    ob.scale = (s, s, s)
    bpy.ops.object.transform_apply(scale=True)
    ob.location = (-(lo_v.x + hi_v.x) / 2 * s, -(lo_v.y + hi_v.y) / 2 * s, -lo_v.z * s)
    bpy.ops.object.transform_apply(location=True)


def bounds(ob):
    co = [v.co for v in ob.data.vertices]
    return (Vector([min(c[i] for c in co) for i in range(3)]), Vector([max(c[i] for c in co) for i in range(3)]))


hi = load(src)
frame = bounds(hi)
place(hi, frame)
dims = hi.dimensions.copy()
print("DIMS", round(dims.x, 3), round(dims.y, 3), round(dims.z, 3))

# Matte, as the game's plain bakes are (no glossy pass).
for slot in hi.material_slots:
    m = slot.material
    for n in m.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            n.inputs["Roughness"].default_value = 1.0
            n.inputs["Metallic"].default_value = 0.0
            for link in list(n.inputs["Roughness"].links) + list(n.inputs["Metallic"].links):
                m.node_tree.links.remove(link)

hi.data.calc_loop_triangles()
src_tris = len(hi.data.loop_triangles)
if lo_src:
    lo = load(lo_src)
    print("LO BOUNDS", bounds(lo), "HI FRAME", frame)
    place(lo, frame)
    lo.name = name
else:
    lo = hi.copy()
    lo.data = hi.data.copy()
    lo.name = name
    scene.collection.objects.link(lo)
bpy.ops.object.select_all(action="DESELECT")
lo.select_set(True)
bpy.context.view_layer.objects.active = lo
bpy.ops.object.mode_set(mode="EDIT")
bpy.ops.mesh.select_all(action="SELECT")
bpy.ops.mesh.remove_doubles(threshold=0.0002)
bpy.ops.object.mode_set(mode="OBJECT")
for _ in range(4):
    lo.data.calc_loop_triangles()
    now = len(lo.data.loop_triangles)
    if now <= tris * 1.03:
        break
    dec = lo.modifiers.new("dec", "DECIMATE")
    dec.decimate_type = "COLLAPSE"
    dec.ratio = min(1.0, tris / now)
    bpy.ops.object.modifier_apply(modifier="dec")
tri = lo.modifiers.new("tri", "TRIANGULATE")
bpy.ops.object.modifier_apply(modifier="tri")
lo.data.calc_loop_triangles()
print("TRIS", src_tris, "->", len(lo.data.loop_triangles))

# Bake the high model, lit by the dusk stage, onto the reduced one's UVs.
image = bpy.data.images.new("bake", tex, tex, alpha=False)
mat = bpy.data.materials.new(name + "_mat")
mat.use_nodes = True
tn = mat.node_tree.nodes.new("ShaderNodeTexImage")
tn.image = image
mat.node_tree.nodes.active = tn
lo.data.materials.clear()
lo.data.materials.append(mat)
scene.cycles.samples = 48
bpy.ops.object.select_all(action="DESELECT")
hi.select_set(True)
lo.select_set(True)
bpy.context.view_layer.objects.active = lo
bpy.ops.object.bake(
    type="COMBINED",
    pass_filter={"EMIT", "DIRECT", "INDIRECT", "DIFFUSE"},
    use_selected_to_active=True,
    cage_extrusion=height * 0.012,
    max_ray_distance=height * 0.05,
    margin=4,
    use_clear=True,
)
bake_path = os.path.join(out, name + "_bake.png")
image.filepath_raw = bake_path
image.file_format = "PNG"
image.save()
print("BAKED", bake_path)

# The viewing copy: the baked texture as plain colour.
bsdf = mat.node_tree.nodes["Principled BSDF"]
mat.node_tree.links.new(tn.outputs["Color"], bsdf.inputs["Base Color"])
bsdf.inputs["Roughness"].default_value = 1.0
bpy.ops.object.select_all(action="DESELECT")
lo.select_set(True)
bpy.context.view_layer.objects.active = lo
common = dict(export_format="GLB", use_selection=True, export_yup=True, export_apply=True,
              export_normals=True, export_texcoords=True)
bpy.ops.export_scene.gltf(filepath=os.path.join(out, name + "_game.glb"), export_materials="EXPORT",
                          export_image_format="JPEG", **common)
bpy.ops.export_scene.gltf(filepath=os.path.join(out, name + "_mesh.glb"), export_materials="NONE", **common)
print("DONE")
