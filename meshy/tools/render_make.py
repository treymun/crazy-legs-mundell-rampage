"""The 'make' turnaround of an actor: the old model and the new one at the
standing key from four sides, the new one's A-pose rest with its skeleton
and ragdoll points, and a few keys of the action side by side.

    blender -b -P meshy/tools/render_make.py -- <kind> <old.glb> <old.png> <new.glb> <new.png> <out_dir> [frames]

Writes <out_dir>/<kind>_*.png tiles (meshy/tools/sheets.py lays them out).
The looks are drawn as they are baked (emission): what the game's texture
holds, before the view's own light.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

A = sys.argv[sys.argv.index("--") + 1:]
KIND, OLD_GLB, OLD_PNG, NEW_GLB, NEW_PNG, OUT = A[0], *[os.path.abspath(x) for x in A[1:6]]
KEYS = A[6].split(",") if len(A) > 6 else []
os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
    try:
        sc.render.engine = eng
        break
    except TypeError:
        continue
sc.render.film_transparent = False
sc.view_settings.view_transform = "Standard"
w = bpy.data.worlds.new("w")
sc.world = w
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (.30, .30, .33, 1)
sc.render.resolution_x = 360
sc.render.resolution_y = 440


def load(path, png, name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for o in list(new):
        if o.type == "MESH" and o.name.startswith("Icosphere"):
            bpy.data.objects.remove(o)
            new.remove(o)
    img = bpy.data.images.load(png)
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    e = nt.nodes.new("ShaderNodeEmission")
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = img
    t.interpolation = "Closest"
    nt.links.new(t.outputs[0], e.inputs[0])
    nt.links.new(e.outputs[0], o.inputs[0])
    arm = next(o for o in new if o.type == "ARMATURE")
    for ob in new:
        if ob.type == "MESH":
            ob.data.materials.clear()
            ob.data.materials.append(m)
    return arm, [o for o in new if o.type == "MESH"], m


old_arm, old_meshes, _ = load(OLD_GLB, OLD_PNG, "old")
new_arm, new_meshes, new_mat = load(NEW_GLB, NEW_PNG, "new")
H = max(o.dimensions.z for o in new_meshes + old_meshes)

cd = bpy.data.cameras.new("cam")
cd.type = "ORTHO"
cd.ortho_scale = H * 1.22
cam = bpy.data.objects.new("cam", cd)
sc.collection.objects.link(cam)
sc.camera = cam
VIEWS = (("front", 0), ("three", 35), ("side", 90), ("back", 180))


def aim(angle, h=H):
    a = math.radians(angle)
    d = 6.0
    cam.location = Vector((math.sin(a) * d, -math.cos(a) * d, h * .5))
    cam.rotation_euler = (Vector((0, 0, h * .5)) - cam.location).to_track_quat("-Z", "Y").to_euler()


def show(objs, on):
    for o in objs:
        o.hide_render = not on


def render(path):
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def key_of(arm, name):
    return None


import json  # noqa: E402

meta = json.load(open(os.path.join(os.path.dirname(NEW_GLB), "actors.json")))
frames = meta[KIND]["frames"]
oldmeta_p = os.path.join(os.path.dirname(OLD_GLB), "actors.json")
old_frames = json.load(open(oldmeta_p))[KIND]["frames"] if os.path.exists(oldmeta_p) else frames

# The standing key, four sides each.
for who, arm, meshes, fr in (("old", old_arm, old_meshes, old_frames), ("new", new_arm, new_meshes, frames)):
    show(old_meshes, who == "old")
    show(new_meshes, who == "new")
    sc.frame_set(int(fr["0"]))
    for vname, ang in VIEWS:
        aim(ang)
        render(os.path.join(OUT, "%s_%s_%s.png" % (KIND, who, vname)))
# Keys of the action, three-quarter view.
for k in KEYS:
    if k not in frames:
        continue
    for who, meshes, fr in (("old", old_meshes, old_frames), ("new", new_meshes, frames)):
        show(old_meshes, who == "old")
        show(new_meshes, who == "new")
        sc.frame_set(int(fr.get(k, fr["0"])))
        aim(35 if not k.startswith("d") else 90)
        render(os.path.join(OUT, "%s_%s_key_%s.png" % (KIND, who, k)))

# The gun poses: carry, walk, aim, fire (its recoil), front and side, new.
show(old_meshes, False)
show(new_meshes, True)
cd.ortho_scale = H * 1.22
for k in ["0", "w1", "aim", "fire"]:
    if k in frames:
        sc.frame_set(int(frames[k]))
        for vname, ang in (("front", 0), ("side", 90)):
            aim(ang)
            render(os.path.join(OUT, "%s_gun_%s_%s.png" % (KIND, k, vname)))

# The hands close up (what they hold), new and old, at a few keys: framed
# on the new model's hands.
for k in ["0", "w1", "aim", "fire"]:
    if k not in frames:
        continue
    sc.frame_set(int(frames[k]))
    bpy.context.view_layer.update()
    hl = new_arm.matrix_world @ new_arm.pose.bones["hand_l"].head if "hand_l" in new_arm.pose.bones else None
    hr = new_arm.matrix_world @ new_arm.pose.bones["hand_r"].head if "hand_r" in new_arm.pose.bones else None
    mid = (hl + hr) / 2 if hl and hr else Vector((0, 0, H * .55))
    span = max(.42, (hl - hr).length * 1.5) if hl and hr else .5
    cd.ortho_scale = span
    for who, meshes, fr in (("new", new_meshes, frames), ("old", old_meshes, old_frames)):
        show(old_meshes, who == "old")
        show(new_meshes, who == "new")
        sc.frame_set(int(fr.get(k, fr["0"])))
        for vname, ang in (("front", 15), ("side", 70)):
            a = math.radians(ang)
            cam.location = mid + Vector((math.sin(a) * 6, -math.cos(a) * 6, 0))
            cam.rotation_euler = (mid - cam.location).to_track_quat("-Z", "Y").to_euler()
            sc.render.resolution_x = 300
            sc.render.resolution_y = 300
            render(os.path.join(OUT, "%s_%s_hands_%s_%s.png" % (KIND, who, k, vname)))
sc.render.resolution_x = 360
sc.render.resolution_y = 440
cd.ortho_scale = H * 1.22

# The rest (A-pose) with its skeleton and the ragdoll's points.
show(old_meshes, False)
show(new_meshes, True)
new_arm.animation_data.action = None
for pb in new_arm.pose.bones:
    pb.location = (0, 0, 0)
    pb.rotation_quaternion = (1, 0, 0, 0)
    pb.scale = (1, 1, 1)
bpy.context.view_layer.update()
# See-through body.
nt = new_mat.node_tree
outn = nt.nodes["Material Output"]
emi = nt.nodes["Emission"]
tr = nt.nodes.new("ShaderNodeBsdfTransparent")
mix = nt.nodes.new("ShaderNodeMixShader")
mix.inputs[0].default_value = .55
nt.links.new(emi.outputs[0], mix.inputs[1])
nt.links.new(tr.outputs[0], mix.inputs[2])
nt.links.new(mix.outputs[0], outn.inputs[0])
try:
    new_mat.surface_render_method = "BLENDED"
except Exception:
    new_mat.blend_method = "BLEND"


def stick_mat(name, rgb):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    t = m.node_tree
    t.nodes.clear()
    o = t.nodes.new("ShaderNodeOutputMaterial")
    e = t.nodes.new("ShaderNodeEmission")
    e.inputs[0].default_value = (*rgb, 1)
    t.links.new(e.outputs[0], o.inputs[0])
    return m


bone_m = stick_mat("bone", (1.0, .55, .1))
joint_m = stick_mat("joint", (1.0, .95, .2))
gear_m = stick_mat("gear", (.2, .9, 1.0))
heads = {b.name: new_arm.matrix_world @ b.head_local for b in new_arm.data.bones}
LINKS = [("body", "head"), ("body", "upperarm_l"), ("upperarm_l", "forearm_l"), ("forearm_l", "hand_l"),
         ("body", "upperarm_r"), ("upperarm_r", "forearm_r"), ("forearm_r", "hand_r"),
         ("body", "thigh_l"), ("thigh_l", "shin_l"), ("shin_l", "foot_l"),
         ("body", "thigh_r"), ("thigh_r", "shin_r"), ("shin_r", "foot_r")]


def cyl(a, b, r, m):
    d = b - a
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=d.length, location=(a + b) / 2, vertices=10)
    o = bpy.context.object
    o.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    o.data.materials.append(m)
    o.show_in_front = True


def ball(p, r, m):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=p, segments=12, ring_count=8)
    o = bpy.context.object
    o.data.materials.append(m)


for a, b in LINKS:
    if a in heads and b in heads:
        cyl(heads[a], heads[b], .012, bone_m)
for n, p in heads.items():
    ball(p, .03 if not n.startswith("gear") else .04, gear_m if n.startswith("gear") else joint_m)
for vname, ang in (("front", 0), ("side", 90)):
    aim(ang)
    render(os.path.join(OUT, "%s_rig_%s.png" % (KIND, vname)))
print("MAKE RENDERS DONE")
