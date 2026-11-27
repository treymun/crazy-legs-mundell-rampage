"""Scratch (meshy track, for 26b chain_hand): a link chain as a glb for
build_actor's "held_model" (it finds the FRONT - the gripped end - as the end
that is wide across, so a bigger grip ring is put there).
  blender -b -P chain_make.py -- <out.glb> [links] [pitch m]
The grip ring lies flat (wide across, in XY): held_model takes the end
that is wide across horizontally as the front; upright, the ring read as
thin and the chain was gripped by its far end (26b's first build)."""
import math
import sys

import bpy

A = sys.argv[sys.argv.index("--") + 1:]
OUT = A[0]
N = int(A[1]) if len(A) > 1 else 24
P = float(A[2]) if len(A) > 2 else .036
bpy.ops.wm.read_factory_settings(use_empty=True)
mat = bpy.data.materials.new("iron")
mat.use_nodes = True
bs = mat.node_tree.nodes["Principled BSDF"]
bs.inputs["Base Color"].default_value = (.09, .085, .08, 1)
bs.inputs["Roughness"].default_value = .8
objs = []
for i in range(N):
    big = i == N - 1
    bpy.ops.mesh.primitive_torus_add(major_radius=(.034 if big else .02), minor_radius=(.007 if big else .0055),
                                     major_segments=10, minor_segments=5,
                                     location=(i * P + (.02 if big else 0), 0, 0),
                                     rotation=(math.pi / 2 if (i % 2 and not big) else 0, 0, 0))
    o = bpy.context.active_object
    o.scale.x = 1.0 if big else 1.35  # long links
    o.data.materials.append(mat)
    objs.append(o)
for o in objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = objs[0]
bpy.ops.object.join()
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB")
print("CHAIN %d links, %.2f m" % (N, N * P))
