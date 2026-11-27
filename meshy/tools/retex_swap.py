"""tex_swap.py (Blender) -- polys <rigged.glb> <out.json> '<json boxes>'  |  swap <rigged.glb> <tex.png> <out.glb>
polys: UV polygons of the faces whose centre lies in any box (build space:
x, y metres at 1.873 height, z share of the height from the feet).
swap: the rigged glb with its base colour image replaced."""
import bpy, sys, os, json
from mathutils import Vector
A = sys.argv[sys.argv.index("--") + 1:]
mode = A[0]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=os.path.abspath(A[1]))
me = max((o for o in bpy.data.objects if o.type == "MESH"), key=lambda o: len(o.data.polygons))
bpy.context.view_layer.update()
if mode == "polys":
    boxes = json.loads(A[3])
    pts = [me.matrix_world @ v.co for v in me.data.vertices]
    zs = [p.z for p in pts]; z0, z1 = min(zs), max(zs); H = z1 - z0
    k = 1.873 / H
    uv = me.data.uv_layers.active.data
    polys = []
    for p in me.data.polygons:
        c = sum((pts[i] for i in p.vertices), Vector()) / len(p.vertices)
        x, y, zs_ = c.x * k, c.y * k, (c.z - z0) / H
        for bi, b in enumerate(boxes):
            if (b["x"][0] <= x <= b["x"][1] and b.get("y", [-9, 9])[0] <= y <= b.get("y", [-9, 9])[1]
                    and b["z"][0] <= zs_ <= b["z"][1]):
                polys.append([bi, [[uv[li].uv.x, uv[li].uv.y] for li in p.loop_indices]])
                break
    json.dump(polys, open(os.path.abspath(A[2]), "w"))
    print("SWAP polys", len(polys), "height", H)
else:
    new = bpy.data.images.load(os.path.abspath(A[2]))
    for m in me.data.materials:
        for nd in m.node_tree.nodes:
            if nd.type == "TEX_IMAGE" and nd.image and nd.image.size[0] > 0:
                print("SWAP image", nd.image.name, nd.image.size[:])
                nd.image = new
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(A[3]), export_format="GLB")
    print("SWAP wrote", A[3])
