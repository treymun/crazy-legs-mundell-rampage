"""Reference pictures of the current models for Meshy's concept step: each
kind's model at its standing key, front and three-quarter, its look drawn as
baked, on plain grey.

    blender -b -P meshy/tools/ref_render.py -- <old dir> <out dir> <kind,kind...>
"""
import math
import os
import sys

import bpy
from mathutils import Vector

A = sys.argv[sys.argv.index("--") + 1:]
OLD, OUT = os.path.abspath(A[0]), os.path.abspath(A[1])
os.makedirs(OUT, exist_ok=True)
for kind in A[2].split(","):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE"
    sc.view_settings.view_transform = "Standard"
    sc.render.resolution_x = 512
    sc.render.resolution_y = 640
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (.55, .55, .56, 1)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OLD, kind + ".glb"))
    img = bpy.data.images.load(os.path.join(OLD, "actor3d_%s.png" % kind))
    m = bpy.data.materials.new("m")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    e = nt.nodes.new("ShaderNodeEmission")
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = img
    nt.links.new(t.outputs[0], e.inputs[0])
    nt.links.new(e.outputs[0], o.inputs[0])
    meshes = []
    for ob in sc.objects:
        if ob.type == "MESH":
            if ob.name.startswith("Icosphere"):
                ob.hide_render = True
                continue
            ob.data.materials.clear()
            ob.data.materials.append(m)
            meshes.append(ob)
    sc.frame_set(0)
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for ob in meshes:
        ev = ob.evaluated_get(dg).to_mesh()
        pts += [ob.matrix_world @ v.co for v in ev.vertices]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    mid = (lo + hi) / 2
    size = max(hi.z - lo.z, (hi.x - lo.x) * 1.25, (hi.y - lo.y) * 1.25)
    cd = bpy.data.cameras.new("c")
    cd.type = "ORTHO"
    cd.ortho_scale = size * 1.15
    cam = bpy.data.objects.new("c", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    for tag, ang in (("front", 0), ("three", 35), ("side", 90)):
        a = math.radians(ang)
        cam.location = mid + Vector((math.sin(a) * 8, -math.cos(a) * 8, 0))
        cam.rotation_euler = (mid - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(OUT, "%s_%s.png" % (kind, tag))
        bpy.ops.render.render(write_still=True)
    print("REF", kind, round(hi.z - lo.z, 3))
