import sys, math, bpy
from mathutils import Vector
glb, out, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=glb)
sc = bpy.context.scene
acts = [o.animation_data.action for o in sc.objects if o.animation_data and o.animation_data.action]
fr = acts[0].frame_range if acts else (0, 0)
print("RANGE", fr, "BONES", sum(len(o.data.bones) for o in sc.objects if o.type == "ARMATURE"))
sc.render.engine = "CYCLES"; sc.cycles.samples = 24; sc.cycles.use_denoising = True
sc.render.resolution_x = 420; sc.render.resolution_y = 600
w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.42, 0.42, 0.45, 1)
w.node_tree.nodes["Background"].inputs[1].default_value = 0.6
ld = bpy.data.lights.new("k", "SUN"); ld.energy = 3; o = bpy.data.objects.new("k", ld); sc.collection.objects.link(o)
o.rotation_euler = (math.radians(50), 0, math.radians(-35))
cd = bpy.data.cameras.new("c"); cd.lens = 60; cam = bpy.data.objects.new("c", cd); sc.collection.objects.link(cam); sc.camera = cam
cam.location = Vector((2.6, -3.6, 1.2)); cam.rotation_euler = (Vector((0, 0, 0.85)) - cam.location).to_track_quat("-Z", "Y").to_euler()
for i in range(n):
    f = int(fr[0] + (fr[1] - fr[0]) * i / n)
    sc.frame_set(f)
    sc.render.filepath = f"{out}_{i}.png"
    bpy.ops.render.render(write_still=True)
