"""A boss's gear that can be shot off (features/boss_gear.gd: a hat, a badge,
armour), for build_actor.py (kind config "shed").

The Meshy body is one surface, so each piece is cut out of it:
- a piece's faces are split from the body along their edge (no triangle spans
  the piece and the body, so a piece shrunk away leaves no stretched faces)
  and weighted wholly to its own bone, keyed with the bone it rides (the head
  or the body) in every key: actors.json "gear" names the bone for the game,
  which flies those triangles off as a piece and shrinks the bone away;
- "hat": the faces above "z" (metres, the rest pose) except what stands
  above "keep_z" further than "keep_x" from the head's middle (an alien's
  antennae poking through the crown stay on the head); a skull cap is built
  under it on the head's ring ("cap": height share of the ring's radius) and
  thin stalks from each kept antenna down into the cap, so a head shot bare
  is whole; they are painted "cap_colour" and "stalk_colour" (0-255) after
  the bake (hidden in the crown while it is worn);
- "badge" (any piece with "box"): the faces in a box (x, y, z ranges in
  metres) whose Meshy colour is in "hue"/"sat"/"val" ranges are copied
  "lift" metres out along their normals as the piece (two-sided), and the
  body's faces under it are painted over from the cloth round them.
Paint ids (face attribute "paint_id") are baked to a mask after the body's
bake: 1 painted over from round about, 2 the cap colour, 3 the stalk colour.
"""

import colorsys
import math

import bmesh
import bpy
import numpy
from mathutils import Matrix, Vector

PAINT_INPAINT = 1
PAINT_CAP = 2
PAINT_STALK = 3
PAINT_SKIN = 7
PAINT_ZONE = 8  # the rest of a face piece's box (where its rim may be)


def _meshy_image(hi):
    for m in hi.data.materials:
        if m and m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image:
                    return n.image
    return None


def _face_colours(lo, img):
    """Each face's Meshy colour (its corners' texels by their UVs)."""
    w, h = img.size
    px = numpy.empty(w * h * 4, dtype=numpy.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(h, w, 4)
    uv = lo.data.uv_layers.active.data
    out = numpy.zeros((len(lo.data.polygons), 3))
    for p in lo.data.polygons:
        acc = numpy.zeros(3)
        for li in p.loop_indices:
            u = uv[li].uv
            acc += px[min(h - 1, max(0, int(u.y * h))), min(w - 1, max(0, int(u.x * w))), :3]
        out[p.index] = acc / max(1, p.loop_total)
    return out


def _in_hsv(rgb, rule):
    hh, ss, vv = colorsys.rgb_to_hsv(*[float(c) for c in rgb])
    hh *= 360
    h0, h1 = rule.get("hue", [0, 360])
    ok_h = (h0 <= hh <= h1) if h0 <= h1 else (hh >= h0 or hh <= h1)
    s0, s1 = rule.get("sat", [0, 1])
    v0, v1 = rule.get("val", [0, 1])
    return ok_h and s0 <= ss <= s1 and v0 <= vv <= v1


def _paint_layer(bm):
    lay = bm.faces.layers.int.get("paint_id")
    return lay if lay is not None else bm.faces.layers.int.new("paint_id")


def _ring(co, z, band, pct=95):
    """The head's ring under a hat: its middle and half-widths."""
    m = (co[:, 2] > z - band) & (co[:, 2] <= z)
    pts = co[m]
    c = pts.mean(axis=0)
    rx = numpy.percentile(numpy.abs(pts[:, 0] - c[0]), pct)
    ry = numpy.percentile(numpy.abs(pts[:, 1] - c[1]), pct)
    return Vector((c[0], c[1], z)), rx, ry


def _dome(bm, c, rx, ry, hz, base, rings=6, segs=16):
    """An ellipsoid cap from `base` below c.z up to hz above it."""
    verts = []
    for i in range(rings + 1):
        a = (math.pi / 2) * i / rings
        row = []
        for j in range(segs):
            t = 2 * math.pi * j / segs
            r = math.cos(a)
            row.append(bm.verts.new((c.x + rx * r * math.cos(t), c.y + ry * r * math.sin(t),
                                     c.z - base + (hz + base) * math.sin(a))))
        verts.append(row)
    faces = []
    for i in range(rings):
        for j in range(segs):
            q = (verts[i][j], verts[i][(j + 1) % segs], verts[i + 1][(j + 1) % segs], verts[i + 1][j])
            if i == rings - 1:
                if q[0] is not q[1]:
                    faces.append(bm.faces.new((q[0], q[1], q[2])))
            else:
                faces.append(bm.faces.new(q))
    return faces


def _tube(bm, a, b, r, segs=6):
    d = (b - a)
    rot = d.normalized().to_track_quat("Z", "Y").to_matrix().to_4x4()
    res = bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r, radius2=r * .8,
                                depth=d.length, matrix=Matrix.Translation((a + b) / 2) @ rot)
    return list({f for v in res["verts"] for f in v.link_faces})


def setup(lo, hi, rig, cfg, ALL_D, keys, select, log=print):
    """Cut each piece, weight it, add its bone keyed with what it rides.
    Returns {bone: (gear name, the bone it rides)}."""
    shed = cfg.get("shed", {})
    if not shed:
        return {}
    img = _meshy_image(hi)
    cols = _face_colours(lo, img) if img is not None else None
    me = lo.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    dl = bm.verts.layers.deform.verify()
    paint = _paint_layer(bm)
    gidx = {g.name: g.index for g in lo.vertex_groups}
    out = {}
    pieces = {}
    for name, rule in shed.items():
        bone = name + "_gear"
        on = rule.get("on", "head" if name == "hat" else "body")
        g = lo.vertex_groups.get(bone) or lo.vertex_groups.new(name=bone)
        gidx[bone] = g.index
        if "box" in rule:
            bx = rule["box"]
            take = []
            for f in bm.faces:
                c = f.calc_center_median()
                if not (bx["x"][0] <= c.x <= bx["x"][1] and bx["y"][0] <= c.y <= bx["y"][1]
                        and bx["z"][0] <= c.z <= bx["z"][1]):
                    continue
                if cols is not None and not _in_hsv(cols[f.index], rule):
                    continue
                take.append(f)
            if not take:
                log("MESHY shed %s: nothing in its box" % name)
                continue
            # "grow_dark" [rings, val]: dark faces in the box touching the
            # piece join it (a spectacle frame's rim round the lenses, left
            # painted round the eyes otherwise).
            gd = rule.get("grow_dark")
            if gd and cols is not None:
                got = set(f.index for f in take)
                for _ in range(int(gd[0])):
                    ring = []
                    for f in take:
                        for v in f.verts:
                            for f2 in v.link_faces:
                                if f2.index in got:
                                    continue
                                c = f2.calc_center_median()
                                if not (bx["x"][0] <= c.x <= bx["x"][1] and bx["y"][0] <= c.y <= bx["y"][1]
                                        and bx["z"][0] <= c.z <= bx["z"][1]):
                                    continue
                                if max(float(x) for x in cols[f2.index][:3]) <= float(gd[1]):
                                    got.add(f2.index)
                                    ring.append(f2)
                    take += ring
                log("MESHY shed %s: %d faces with the dark rim grown on (%d)" % (name, len(take), len(got)))
            lift = float(rule.get("lift", .006))
            dup = bmesh.ops.duplicate(bm, geom=take)
            new_f = [e for e in dup["geom"] if isinstance(e, bmesh.types.BMFace)]
            new_v = [e for e in dup["geom"] if isinstance(e, bmesh.types.BMVert)]
            for v in new_v:
                v.co += v.normal * lift
            # its back, a little under it (two-sided as it flies)
            back = bmesh.ops.duplicate(bm, geom=new_f)
            back_f = [e for e in back["geom"] if isinstance(e, bmesh.types.BMFace)]
            back_v = [e for e in back["geom"] if isinstance(e, bmesh.types.BMVert)]
            for v in back_v:
                v.co -= v.normal * (lift * .5)
            bmesh.ops.reverse_faces(bm, faces=back_f)
            for v in new_v + back_v:
                for k in list(v[dl].keys()):
                    del v[dl][k]
                v[dl][gidx[bone]] = 1.0
            if rule.get("rim_px"):
                for f in bm.faces:
                    c = f.calc_center_median()
                    if f[paint] == 0 and (bx["x"][0] <= c.x <= bx["x"][1] and bx["y"][0] <= c.y <= bx["y"][1]
                                          and bx["z"][0] <= c.z <= bx["z"][1]):
                        f[paint] = PAINT_ZONE
            for f in take:
                f[paint] = PAINT_SKIN if rule.get("under") == "skin" else PAINT_INPAINT
            for f in new_f + back_f:
                f[paint] = 0
            pieces[bone] = new_v + back_v
            log("MESHY shed %s: %d faces copied %.3f m out (two-sided), the body under it painted over"
                % (name, len(take), lift))
        else:
            z0 = float(rule["z"])
            kz = float(rule.get("keep_z", 9.0))
            kx = float(rule.get("keep_x", 9.0))
            co = numpy.array([v.co[:] for v in bm.verts])
            head = numpy.array([max(v[dl].items(), key=lambda kv: kv[1])[0] == gidx.get(on, -1)
                                if v[dl] else False for v in bm.verts])
            cen, rx, ry = _ring(co[head], z0, float(rule.get("band", .04)), float(rule.get("ring_pct", 95)))
            keep = lambda p: p.z > kz and abs(p.x - cen.x) > kx  # noqa: E731
            hat_f = []
            for f in bm.faces:
                c = f.calc_center_median()
                if c.z > z0 and not keep(c):
                    hat_f.append(f)
            hat_set = set(hat_f)
            edges = [e for e in bm.edges
                     if any(f in hat_set for f in e.link_faces) and any(f not in hat_set for f in e.link_faces)]
            bmesh.ops.split_edges(bm, edges=edges)
            hv = {v for f in hat_f for v in f.verts}
            # The cut's two rims evened onto one level (a ragged edge of
            # triangle tips round the bare head otherwise): the hat's lower
            # edge at z, the head's just under it, where the cap meets it.
            if rule.get("even_rim", True):
                for e in bm.edges:
                    if e.is_boundary:
                        for v in e.verts:
                            if v in hv:
                                v.co.z = max(v.co.z, z0) if v.co.z > z0 - .03 else v.co.z
                            elif abs(v.co.z - z0) < .05:
                                v.co.z = min(v.co.z, z0 - .004)
            for v in hv:
                for k in list(v[dl].keys()):
                    del v[dl][k]
                v[dl][gidx[bone]] = 1.0
            pieces[bone] = list(hv)
            log("MESHY shed %s: %d faces above %.3f m cut off the body (%d edges split)"
                % (name, len(hat_f), z0, len(edges)))
            # The bare head: a cap on the ring, stalks to the kept antennae.
            if rule.get("cap"):
                hz = float(rule["cap"]) * (rx + ry) / 2
                cg = float(rule.get("cap_grow", .97))
                cap_f = _dome(bm, cen, rx * cg, ry * cg, hz, base=float(rule.get("cap_base", .03)))
                tops = []
                kept = [v for v in bm.verts if v not in hv and keep(v.co)]
                for side in (-1, 1):
                    s = [v.co.copy() for v in kept if (v.co.x - cen.x) * side > 0]
                    if len(s) < 5:
                        continue
                    s.sort(key=lambda p: p.z)
                    low = sum(s[:6], Vector()) / 6
                    top = sum(s[-max(6, len(s) // 3):], Vector()) / max(6, len(s) // 3)
                    tops.append((low, top))
                stalk_f = []
                r = float(rule.get("stalk_r", .006))
                for low, top in tops:
                    # on down along the antenna's own line into the cap (inside
                    # the Meshy stalk where the hat still has it)
                    d = (low - top).normalized()
                    foot_z = cen.z + hz * .6
                    t = (low.z - foot_z) / max(-d.z, .2)
                    foot = low + d * t
                    stalk_f += _tube(bm, foot, low - d * .015, r)
                for f in cap_f + stalk_f:
                    for v in f.verts:
                        for kk in list(v[dl].keys()):
                            del v[dl][kk]
                        v[dl][gidx[on]] = 1.0
                for f in cap_f:
                    f[paint] = PAINT_CAP
                for f in stalk_f:
                    f[paint] = PAINT_STALK
                log("MESHY shed %s: skull cap %.3f x %.3f m, %.3f high; %d antenna stalks" % (
                    name, rx, ry, hz, len(tops)))
        out[bone] = (rule.get("gear", name), on)
    bm.to_mesh(me)
    bm.free()
    me.update()
    # Bones: at each piece's middle, keyed with the bone it rides.
    select([rig])
    bpy.ops.object.mode_set(mode="EDIT")
    for bone in out:
        vs = [lo.data.vertices[i].co for i in range(len(lo.data.vertices))
              if any(gg.group == gidx[bone] and gg.weight > .5 for gg in lo.data.vertices[i].groups)]
        c = sum(vs, Vector()) / max(1, len(vs))
        eb = rig.data.edit_bones.new(bone)
        eb.head = c
        eb.tail = c + Vector((0, 0, .08))
    bpy.ops.object.mode_set(mode="POSE")
    for bone, (_g, on) in out.items():
        pb = rig.pose.bones[bone]
        pb.rotation_mode = "QUATERNION"
        for t in keys:
            pb.matrix = ALL_D[t][on] @ rig.data.bones[bone].matrix_local
            bpy.context.view_layer.update()
            pb.keyframe_insert("location", frame=t)
            pb.keyframe_insert("rotation_quaternion", frame=t)
            pb.keyframe_insert("scale", frame=t)
    bpy.ops.object.mode_set(mode="OBJECT")
    return out


def paint(lo, image, total, cfg, pixels, bake_op, select, texture, log=print, skin=None):
    """After the bake: the painted-over faces filled from the cloth round
    them, the cap and stalks their colours. `total` is changed in place."""
    att = lo.data.attributes.get("paint_id")
    if att is None or not any(d.value for d in att.data):
        return
    fimg = bpy.data.images.new("paint_id", texture, texture, alpha=False, float_buffer=True)
    fimg.colorspace_settings.name = "Non-Color"
    for m in lo.data.materials:
        nt = m.node_tree
        for n in list(nt.nodes):
            if n.name != "bake_target":
                nt.nodes.remove(n)
        o = nt.nodes.new("ShaderNodeOutputMaterial")
        e = nt.nodes.new("ShaderNodeEmission")
        a = nt.nodes.new("ShaderNodeAttribute")
        a.attribute_type = "GEOMETRY"
        a.attribute_name = "paint_id"
        mm = nt.nodes.new("ShaderNodeMath")
        mm.operation = "MULTIPLY"
        mm.inputs[1].default_value = .1
        nt.links.new(a.outputs["Fac"], mm.inputs[0])
        nt.links.new(mm.outputs[0], e.inputs[0])
        nt.links.new(e.outputs[0], o.inputs[0])
        nt.nodes["bake_target"].image = fimg
        nt.nodes.active = nt.nodes["bake_target"]
    select([lo])
    bake_op(type="EMIT", margin=2, use_clear=True)
    ids = numpy.rint(pixels(fimg)[:, 0] * 10).astype(int)
    for m in lo.data.materials:
        m.node_tree.nodes["bake_target"].image = image
    rgb = total[:, :3].reshape(texture, texture, 3)
    idm = ids.reshape(texture, texture)
    over = idm == PAINT_INPAINT
    if over.any():
        good = (idm == 0) & (rgb.sum(axis=2) > .003)
        miss = over.copy()
        for _ in range(64):
            if not miss.any():
                break
            acc = numpy.zeros_like(rgb)
            cnt = numpy.zeros(idm.shape, dtype=numpy.float32)
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
                g = numpy.roll(numpy.roll(good, dy, 0), dx, 1)
                acc += numpy.roll(numpy.roll(rgb, dy, 0), dx, 1) * g[:, :, None]
                cnt += g
            take = miss & (cnt > 0)
            rgb[take] = acc[take] / cnt[take][:, None]
            good |= take
            miss &= ~take
        log("MESHY shed: %d texels painted over from round about" % int(over.sum()))
    # plain colours by paint id (kind config "paint" {id: [r, g, b]}: the
    # slung axe's wood, head and edge), a little light from above
    for pid, col in cfg.get("paint", {}).items():
        m = idm == int(pid)
        if m.any():
            c = numpy.array(col, dtype=float) / 255.0
            k = 1.0 + (numpy.random.default_rng(int(pid)).random(m.sum()) - .5) * .08
            rgb[m] = numpy.clip(c[None, :] * k[:, None], 0, 1)
            log("MESHY paint %s: %d texels %s" % (pid, int(m.sum()), col))
    # under a face piece (shades): the face's own skin, a little shaded
    m = idm == PAINT_SKIN
    # The frame's own texels round the painted patch (a spectacle rim the
    # face selection did not take): within "rim_px" texels of it, any texel
    # in the piece's hue range or dark joins the skin paint.
    for rule in cfg.get("shed", {}).values():
        rp = int(rule.get("rim_px", 0))
        if rp and m.any() and rule.get("under") == "skin":
            near = m.copy()
            for _ in range(rp):
                grow = near.copy()
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    grow |= numpy.roll(numpy.roll(near, dy, 0), dx, 1)
                near = grow
            near &= idm == PAINT_ZONE
            mx = rgb.max(axis=2)
            mn = rgb.min(axis=2)
            sat = (mx - mn) / numpy.maximum(mx, 1e-4)
            r_, g_, b_ = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
            blue = (b_ >= r_) & (b_ >= g_ * .95) & (sat > .12)
            dark = mx < float(rule.get("rim_dark", .3))
            add = near & (blue | dark)
            m = m | add
            log("MESHY shed: %d frame texels round a face piece joined its skin paint" % int(add.sum()))
    if m.any() and skin is not None:
        k = 1.0 + (numpy.random.default_rng(5).random(m.sum()) - .5) * .06
        rgb[m] = numpy.clip(numpy.asarray(skin)[None, :3] * .92 * k[:, None], 0, 1)
        log("MESHY shed: %d texels under a face piece the face's skin %s" % (
            int(m.sum()), numpy.round(numpy.asarray(skin)[:3] * 255).astype(int)))
    shed = cfg.get("shed", {})
    for rule in shed.values():
        for pid, key in ((PAINT_CAP, "cap_colour"), (PAINT_STALK, "stalk_colour")):
            if key in rule:
                m = idm == pid
                c = numpy.array(rule[key], dtype=float) / 255.0
                # a little light from above in the texel's own noise
                k = 1.0 + (numpy.random.default_rng(7).random(m.sum()) - .5) * .06
                rgb[m] = numpy.clip(c[None, :] * k[:, None], 0, 1)
                log("MESHY shed: %d texels the %s %s" % (int(m.sum()), key, rule[key]))
    total[:, :3] = rgb.reshape(-1, 3)
