"""The make sheet of an animal or a boss (the beast path): old and new at the
standing key from four sides, then every key of the action from the side
and three-quarter, old above new, framed for a long body.

    blender -b -P meshy/tools/beast_sheet.py -- <kind> <old.glb> <old.png> <new.glb> <new.png> <tiles dir>
    python meshy/tools/beast_sheet.py sheet <tiles dir> <kind> <out.png> <title>

The looks are drawn as baked (emission), before the view's own light.
"""
import json
import os
import sys

TW, TH = 480, 330
VIEWS = (("front", 0), ("three", 35), ("side", 90), ("back", 180))


def blender_tiles():
    import math

    import bpy
    from mathutils import Vector

    a = sys.argv[sys.argv.index("--") + 1:]
    kind, old_glb, old_png, new_glb, new_png, out = a[0], *[os.path.abspath(x) for x in a[1:6]]
    os.makedirs(out, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            continue
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w")
    sc.world = w
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (.30, .30, .33, 1)
    sc.render.resolution_x = TW
    sc.render.resolution_y = TH

    def load(path, png, name):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=path)
        new = [o for o in bpy.data.objects if o not in before]
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
        for ob in [o for o in new if o.type == "MESH" and o.name.startswith("Icosphere")]:
            bpy.data.objects.remove(ob)
        meshes = [o for o in bpy.data.objects if o in new and o.type == "MESH"]
        for ob in meshes:
            ob.data.materials.clear()
            ob.data.materials.append(m)
        return meshes

    old = load(old_glb, old_png, "old")
    new = load(new_glb, new_png, "new")

    def frames_of(glb):
        p = os.path.join(os.path.dirname(glb), "actors.json")
        return json.load(open(p))[kind]["frames"]

    fr = {"old": frames_of(old_glb), "new": frames_of(new_glb)}

    def box(meshes):
        dg = bpy.context.evaluated_depsgraph_get()
        lo = Vector((1e9, 1e9, 1e9))
        hi = -lo
        for ob in meshes:
            if ob.hide_render:
                continue
            ev = ob.evaluated_get(dg)
            me = ev.to_mesh()
            for v in me.vertices:
                p = ev.matrix_world @ v.co
                lo = Vector(map(min, lo, p))
                hi = Vector(map(max, hi, p))
            ev.to_mesh_clear()
        return lo, hi

    cd = bpy.data.cameras.new("cam")
    cd.type = "ORTHO"
    cam = bpy.data.objects.new("cam", cd)
    sc.collection.objects.link(cam)
    sc.camera = cam
    sc.frame_set(int(fr["new"]["0"]))
    for o in old:
        o.hide_render = True
    lo, hi = box(new)
    reach = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z)
    cd.ortho_scale = reach * 1.12

    # (A beast facing another way than +z, fit.json "beast" "front": the
    # views turned with it.)
    fit_p = os.path.join(os.path.dirname(new_glb), "fit.json")
    front = [0.0, 1.0]
    if os.path.exists(fit_p):
        front = json.load(open(fit_p)).get(kind, {}).get("beast", {}).get("front", front)
    yaw = math.degrees(math.atan2(front[0], front[1]))

    def shoot(path, angle, mid, up=0.0):
        a_ = math.radians(angle + yaw)
        e_ = math.radians(up)
        d = 12.0
        cam.location = mid + Vector((math.sin(a_) * math.cos(e_), -math.cos(a_) * math.cos(e_), math.sin(e_))) * d
        cam.rotation_euler = (mid - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)

    keys = list(fr["new"].keys())
    for who, meshes in (("old", old), ("new", new)):
        for o in old:
            o.hide_render = who != "old"
        for o in new:
            o.hide_render = who != "new"
        for k in keys:
            if k not in fr[who]:
                continue
            sc.frame_set(int(round(fr[who][k])))
            bl, bh = box(meshes)
            mid = (bl + bh) / 2
            if k == "0":
                for vname, ang in VIEWS:
                    shoot(os.path.join(out, "%s_%s_%s.png" % (kind, who, vname)), ang, mid, 8)
            shoot(os.path.join(out, "%s_%s_key_%s_side.png" % (kind, who, k)), 90, mid, 8)
            shoot(os.path.join(out, "%s_%s_key_%s_three.png" % (kind, who, k)), 35, mid, 25)
    json.dump(keys, open(os.path.join(out, "keys.json"), "w"))
    print("BEAST SHEET tiles done")


def sheet(tiles, kind, out, title):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from PIL import Image
    from sheets import label

    keys = json.load(open(os.path.join(tiles, "keys.json")))

    def tile(name):
        p = os.path.join(tiles, "%s_%s.png" % (kind, name))
        return Image.open(p).convert("RGB") if os.path.exists(p) else None

    rows = []
    for who, cap in (("old", "OLD model (current game)"), ("new", "NEW Meshy model")):
        rows.append((cap + ": standing key, front / three-quarter / side / back",
                     [tile("%s_%s" % (who, v)) for v, _a in VIEWS], 1.0))
    sc = .62
    for view in ("side", "three"):
        for who in ("old", "new"):
            rows.append(("%s keys (%s): %s" % (who.upper(), view, ", ".join(keys)),
                         [tile("%s_key_%s_%s" % (who, k, view)) for k in keys], sc))
    width = max(int(len(r[1]) * TW * r[2]) for r in rows) + 20
    height = 40 + sum(int(TH * r[2]) + 30 for r in rows)
    im = Image.new("RGB", (width, height), (24, 24, 28))
    label(im, title, 20, (10, 8))
    y = 40
    for cap, tiles_, s in rows:
        label(im, cap, 14, (10, y))
        y += 22
        for i, t in enumerate(tiles_):
            if t is None:
                continue
            t = t.resize((int(TW * s), int(TH * s)))
            im.paste(t, (10 + i * int(TW * s), y))
        if s < 1:
            for i, k in enumerate(keys):
                label(im, k, 13, (14 + i * int(TW * s), y + 2))
        y += int(TH * s) + 8
    im.save(out)
    print("sheet", out)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "sheet":
        sheet(*sys.argv[2:6])
    else:
        blender_tiles()
