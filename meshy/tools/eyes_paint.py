"""Paint open eyes onto a rigged Meshy model's base colour (scratch, meshy track).
  blender -b -P eyes_paint.py -- <rigged.glb> <out.png> '<json spec>'
spec: {"eyes": [[x, z], ...], "w": half width m, "h": half height m, "iris": r m,
       "pupil": r m, "look": [du, dv] (share of w,h), "iris_rgb": [r,g,b]}"""
import bpy, sys, json, math
import numpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.interpolate import poly_3d_calc
import bmesh
A = sys.argv[sys.argv.index("--") + 1:]
S = json.loads(A[2])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=A[0])
for o in bpy.data.objects:
    if o.type == "ARMATURE":
        o.data.pose_position = "REST"
m = max((o for o in bpy.data.objects if o.type == "MESH"), key=lambda o: len(o.data.vertices))
bpy.context.view_layer.update()
me = m.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
bm = bmesh.new(); bm.from_mesh(me); bm.transform(m.matrix_world)
bm.faces.ensure_lookup_table()
bvh = BVHTree.FromBMesh(bm)
uvl = bm.loops.layers.uv.active
img = None
for s in m.data.materials:
    for n in s.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image and n.image.colorspace_settings.name == "sRGB":
            img = n.image
W_, H_ = img.size
px = numpy.empty(W_ * H_ * 4, dtype=numpy.float32); img.pixels.foreach_get(px); px = px.reshape(H_, W_, 4)
w, h = S["w"], S["h"]
ir, pr = S["iris"], S["pupil"]
lu, lv = S.get("look", [0, -.1])
iris_c = numpy.array(S.get("iris_rgb", [70, 46, 32])) / 255.0
white = numpy.array(S.get("white_rgb", [236, 230, 222])) / 255.0
lid = numpy.array([38, 24, 22]) / 255.0
step = S.get("step", .00025)
painted = 0
acc = {}
for k, (ex, ez) in enumerate(S["eyes"]):
    flip = -1.0 if ex < 0 else 1.0  # (the outer corner a little higher: a cocky lift)
    xs = numpy.arange(-w * 1.25, w * 1.25, step)
    zs = numpy.arange(-h * 1.6, h * 1.6, step)
    for dx in xs:
        for dz in zs:
            u = dx / w
            # almond: the upper lid arched, the lower flatter; outer corner lifted
            tilt = .12 * u * flip
            top = (1 - min(1, u * u)) ** .65 * h + tilt * h
            bot = -(1 - min(1, u * u)) ** .9 * h * .75 + tilt * h
            if abs(u) > 1.0:
                continue
            if dz > top + .0012 or dz < bot - .0006:
                continue
            o = Vector((ex + dx, -3.0, ez + dz))
            hit, nrm, fi, d = bvh.ray_cast(o, Vector((0, 1, 0)))
            if hit is None:
                continue
            f = bm.faces[fi]
            wts = poly_3d_calc([l.vert.co for l in f.loops], hit)
            uv = sum((l[uvl].uv * wi for l, wi in zip(f.loops, wts)), Vector((0, 0)))
            tx = int(uv.x % 1.0 * W_); ty = int(uv.y % 1.0 * H_)
            if dz > top:
                c = lid  # the upper lid's line (lashes)
            elif dz < bot:
                c = lid * .5 + px[ty, tx, :3] * .5  # a soft lower lid line
            else:
                ix = dx - lu * w
                iz = dz - lv * h
                rr = math.hypot(ix, iz)
                if rr < pr:
                    c = numpy.array([.04, .03, .03])
                elif rr < ir:
                    c = iris_c * (1.0 - .35 * (rr / ir))
                else:
                    # the white, shaded toward the lids and corners
                    sh = 1.0 - .22 * abs(u) ** 2 - .25 * max(0.0, (dz - (top - h * .35)) / (h * .35))
                    c = white * sh
                hx = ix + ir * .35; hz = iz - ir * .4
                if math.hypot(hx, hz) < ir * .22:
                    c = numpy.array([.97, .97, .97])  # the catch light
            acc.setdefault((ty, tx), []).append(c)
for (ty, tx), cs in acc.items():
    px[ty, tx, :3] = numpy.mean(cs, axis=0)
    painted += 1
img.pixels.foreach_set(px.ravel())
img.filepath_raw = A[1]; img.file_format = "PNG"; img.save()
print("EYES painted %d texels on a %dx%d texture" % (painted, W_, H_))
