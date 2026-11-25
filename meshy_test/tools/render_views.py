"""Render a glb from several angles with Blender (bpy module, Cycles CPU).

  python render_views.py <model.glb> <out_prefix> [size=900] [samples=48] [angles=front,q,side,back,bq]
Also prints triangle count and texture sizes.
"""

import math
import sys

import bpy
from mathutils import Vector

pos = [a for a in sys.argv[1:] if "=" not in a]
opt = dict(a.split("=", 1) for a in sys.argv[1:] if "=" in a)
glb, out = pos[0], pos[1]
size = int(pos[2]) if len(pos) > 2 else 900
samples = int(pos[3]) if len(pos) > 3 else 48
angles = (pos[4] if len(pos) > 4 else "front,q,side,back,bq").split(",")
TEX = opt.get("tex", "")
UNLIT = opt.get("unlit", "0") == "1"
FIX_R = float(opt.get("radius", "0"))
WIDTH = int(opt.get("width", "0")) or size
YAW = {"front": 0, "q": 40, "side": 90, "back": 180, "bq": 220, "qr": -40, "sider": -90}

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
for o in bpy.context.scene.objects:
    if o.animation_data and o.animation_data.action:
        bpy.context.scene.frame_set(int(opt.get("frame", "0")))
if TEX or UNLIT:
    img = bpy.data.images.load(TEX) if TEX else None
    for o in meshes:
        mats = [s.material for s in o.material_slots if s.material] or []
        if not mats:
            m = bpy.data.materials.new("m"); o.data.materials.append(m); mats = [m]
        for m in mats:
            m.use_nodes = True
            nt = m.node_tree
            tn = img and nt.nodes.new("ShaderNodeTexImage")
            if tn:
                tn.image = img
                tn.interpolation = "Closest"
            else:
                tn = next(n for n in nt.nodes if n.type == "TEX_IMAGE")
            bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
            outn = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
            if UNLIT:
                em = nt.nodes.new("ShaderNodeEmission")
                nt.links.new(tn.outputs["Color"], em.inputs["Color"])
                nt.links.new(em.outputs[0], outn.inputs["Surface"])
            elif bsdf:
                nt.links.new(tn.outputs["Color"], bsdf.inputs["Base Color"])
tris = 0
dg = bpy.context.evaluated_depsgraph_get()
for o in meshes:
    m = o.evaluated_get(dg).to_mesh()
    m.calc_loop_triangles()
    tris += len(m.loop_triangles)
print("TRIS", tris)
for img in bpy.data.images:
    if img.size[0]:
        print("TEX", img.name, img.size[0], img.size[1])

lo = Vector((1e9,) * 3)
hi = Vector((-1e9,) * 3)
for o in meshes:
    for c in o.bound_box:
        w = o.matrix_world @ Vector(c)
        lo = Vector(map(min, lo, w))
        hi = Vector(map(max, hi, w))
center = (lo + hi) / 2
dims = hi - lo
print("DIMS", tuple(round(d, 3) for d in dims))
radius = FIX_R or max(dims) * 0.5
if FIX_R:
    center = Vector((0, 0, FIX_R * 0.9))

sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = samples
sc.cycles.use_denoising = True
sc.render.resolution_x = WIDTH
sc.render.resolution_y = size
sc.render.film_transparent = False
sc.view_settings.view_transform = "Standard"
world = bpy.data.worlds.new("w")
sc.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.42, 0.42, 0.45, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 0.55

# ground plane
bpy.ops.mesh.primitive_plane_add(size=radius * 12, location=(center.x, center.y, lo.z))
ground = bpy.context.object
gm = bpy.data.materials.new("ground")
gm.use_nodes = True
gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.3, 0.3, 0.32, 1)
ground.data.materials.append(gm)


def light(name, rot, energy):
    ld = bpy.data.lights.new(name, "SUN")
    ld.energy = energy
    ld.angle = math.radians(8)
    ob = bpy.data.objects.new(name, ld)
    sc.collection.objects.link(ob)
    ob.rotation_euler = [math.radians(a) for a in rot]


light("key", (50, 0, -35), 3.2)
light("fill", (65, 0, 140), 0.9)

cam_d = bpy.data.cameras.new("cam")
cam_d.lens = 70
cam = bpy.data.objects.new("cam", cam_d)
sc.collection.objects.link(cam)
sc.camera = cam
# glTF imports with -Y forward in Blender; the model's front faces -Y.
dist = radius * 2 / math.tan(cam_d.angle / 2) * 0.62
for name in angles:
    yaw = math.radians(YAW[name])
    d = Vector((math.sin(yaw), -math.cos(yaw), 0.18)).normalized() * dist
    cam.location = center + d
    direction = center - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = f"{out}_{name}.png"
    bpy.ops.render.render(write_still=True)
    print("WROTE", sc.render.filepath)
