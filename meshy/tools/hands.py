"""Low-poly hands with finger bones for the Meshy actors (build_actor.py).

Meshy's characters come with mitten hands and no finger bones. Every
humanoid gets these instead, sized to its own Meshy hand: a palm, a thumb
and four fingers and a thumb of three joints each, with gaps between them,
knuckles and nails, skinned to bones of their own. The fingers curl about their knuckles toward
the palm, so a hand can wrap a grip (grip_curls() fits the curl to the thing
held) or hang relaxed.

Everything here works in the hand's rest frame (world coordinates of the
A-pose): `a` the hand's axis (wrist to fingertips), `n` the palm's normal
(the palm side), `t` across the hand toward the thumb.
"""

import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

RING = 8  # vertices round a finger
PALM_RING = 10  # round the palm


class Hand:
    """One hand: its mesh object, its bones' rest origins and chains."""

    def __init__(self, side):
        self.side = side
        self.obj = None
        self.wrist = None
        self.a = self.n = self.t = None
        self.length = self.width = self.thick = 0.0
        # chain name -> [joint origins at rest (base first), tip]
        self.chains = {}
        # chain name -> curl axis at rest
        self.axes = {}
        # chain name -> radius of its tube
        self.radius = {}
        self.middle = None  # the palm's middle (the hand bone's origin)

    def bones(self):
        """[(bone name, origin)] for the hand's finger bones."""
        out = []
        for c, (joints, _tip) in self.chains.items():
            for k, p in enumerate(joints):
                out.append(("f%s_%s%d" % (self.side, c, k + 1), p))
        return out


def _ring(bm, centre, u, v, ru, rv, n, groove=None):
    """A ring of n vertices round centre in the plane u, v (radii ru, rv);
    `groove`: [(angle, depth)] dents (the scores between fingers)."""
    out = []
    for k in range(n):
        ang = 2 * math.pi * k / n
        r_u, r_v = ru, rv
        if groove:
            for ga, gd in groove:
                d = abs((ang - ga + math.pi) % (2 * math.pi) - math.pi)
                if d < .35:
                    r_u *= 1 - gd * (1 - d / .35)
        out.append(bm.verts.new(centre + u * (math.cos(ang) * r_u) + v * (math.sin(ang) * r_v)))
    return out


def _bridge(bm, a, b):
    n = len(a)
    for k in range(n):
        bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]))


def _cap(bm, ring, tip):
    t = bm.verts.new(tip)
    n = len(ring)
    for k in range(n):
        bm.faces.new((ring[k], ring[(k + 1) % n], t))
    return t


def build(side, wrist, a, n, t, length, width, thick, wrist_r, name):
    """The hand's mesh and rest bones. a, n, t: the hand's axis, its palm's
    normal and the way across it to the thumb (unit, at right angles; a left
    hand and a right are mirrors, so t is the caller's)."""
    h = Hand(side)
    h.wrist, h.a, h.n, h.t = wrist.copy(), a.copy(), n.copy(), t
    h.length, h.width, h.thick = length, width, thick
    palm_len = length * .5
    knuckle = wrist + a * palm_len
    h.middle = wrist + a * palm_len * .55
    bm = bmesh.new()
    groups = {}  # vertex -> [(group, weight)]

    def tag(vs, wts):
        for v in vs:
            groups[v] = wts

    hb = "hand_" + side
    fb = "forearm_" + side
    # The wrist (as round as the forearm there) to the palm, the knuckles.
    rings = []
    for s, ru, rv, w in ((-.02 * length / .19, wrist_r * 1.02, wrist_r * .82, [(fb, .5), (hb, .5)]),
                         (0.0, wrist_r * 1.04, wrist_r * .8, [(hb, 1.0)]),
                         (palm_len * .2, (wrist_r + width * .5) * .5 * 1.04, (wrist_r * .8 + thick * .5) * .5,
                          [(hb, 1.0)]),
                         (palm_len * .5, width * .48, thick * .5, [(hb, 1.0)]),
                         (palm_len * .8, width * .5, thick * .46, [(hb, 1.0)]),
                         (palm_len * .96, width * .47, thick * .38, [(hb, 1.0)])):
        r = _ring(bm, wrist + a * s, t, n, ru, rv, PALM_RING)
        tag(r, w)
        rings.append(r)
    for k in range(len(rings) - 1):
        _bridge(bm, rings[k], rings[k + 1])
    # (The knuckle end closed, under the fingers.)
    end = bm.verts.new(wrist + a * palm_len * .98)
    tag([end], [(hb, 1.0)])
    for k in range(PALM_RING):
        bm.faces.new((rings[-1][k], rings[-1][(k + 1) % PALM_RING], end))
    first = bm.verts.new(wrist + a * (-.02 * length / .19))
    tag([first], [(fb, .5), (hb, .5)])
    for k in range(PALM_RING):
        bm.faces.new((rings[0][(k + 1) % PALM_RING], rings[0][k], first))

    colour = {}  # vertex -> shade (1 skin, >1 nail, <1 crease)

    def finger(cname, base, direction, lengths, rw, rt, axis):
        """A finger: a tube through its joints (a knuckle bulge at each, a
        crease ring either side), a nail on its last joint, a bone a joint."""
        d = direction.normalized()
        side_v = axis.normalized()
        up_v = d.cross(side_v).normalized()
        if up_v.dot(n) > 0:
            up_v = -up_v  # up_v: the back of the finger (away from the palm)
        joints = [base]
        p = base
        for L in lengths:
            p = p + d * L
            joints.append(p)
        tip = joints[-1]
        h.chains[cname] = (joints[:-1], tip)
        h.axes[cname] = side_v
        h.radius[cname] = max(rw, rt)
        segs = len(lengths)
        prev = None
        root = None
        for k in range(segs):
            bone = "f%s_%s%d" % (side, cname, k + 1)
            last = "f%s_%s%d" % (side, cname, k) if k > 0 else hb
            seg = joints[k + 1] - joints[k]
            taper = 1.0 - .22 * k / segs
            # A ring at the joint (the knuckle, a little wider, the crease
            # darker), then two along the segment.
            for f, bulge, shade, wts in ((0.0, 1.12, .82, [(last, .5), (bone, .5)]),
                                         (.3, 1.0, 1.0, [(bone, 1.0)]),
                                         (.75, .96, 1.0, [(bone, 1.0)])):
                c = joints[k] + seg * f
                r = _ring(bm, c, side_v, up_v, rw * taper * bulge, rt * taper * bulge, RING)
                tag(r, wts)
                for v in r:
                    colour[v] = shade
                if prev is not None:
                    _bridge(bm, prev, r)
                else:
                    root = bm.verts.new(joints[0] - d * rt * 1.2)
                    tag([root], [(hb, 1.0)])
                    for q in range(RING):
                        bm.faces.new((r[(q + 1) % RING], r[q], root))
                prev = r
        # The fingertip, rounded.
        r = _ring(bm, tip - d * rt * .45, side_v, up_v, rw * .7, rt * .7, RING)
        tag(r, [("f%s_%s%d" % (side, cname, segs), 1.0)])
        _bridge(bm, prev, r)
        tv = _cap(bm, r, tip)
        tag([tv], [("f%s_%s%d" % (side, cname, segs), 1.0)])
        # The nail: a thin plate on the back of the last joint.
        j0 = joints[-1]
        L = (tip - j0).length
        nb = "f%s_%s%d" % (side, cname, segs)
        nw, nt = rw * .62, rt * .78
        q = []
        for along in (.35, .95):
            for acr in (-1, 1):
                for lift in (1.0, 1.12):
                    q.append(bm.verts.new(j0 + d * L * along + side_v * nw * acr * (1.0 - .2 * along)
                                          + up_v * nt * lift))
        tag(q, [(nb, 1.0)])
        for v in q:
            colour[v] = 1.35
        # (the plate's top and edges)
        for f in ((1, 3, 7, 5), (0, 1, 5, 4), (2, 6, 7, 3), (4, 5, 7, 6), (0, 2, 3, 1)):
            bm.faces.new([q[i] for i in f])

    # The curl axis of the fingers: across the hand, so a bend takes them
    # toward the palm (rotating a about it toward n).
    curl = a.cross(n).normalized()
    if (Matrix.Rotation(.5, 3, curl) @ a).dot(n) < 0:
        curl = -curl
    fl = length - palm_len
    # Four fingers across the knuckles, gaps between them, the middle the
    # longest; the knuckles on a gentle arc.
    fw = width * .118
    for cname, across, scale, back in (("ix", .38, .93, .03), ("md", .13, 1.0, 0.0),
                                       ("rn", -.13, .95, .03), ("pk", -.37, .78, .1)):
        base = knuckle + t * width * across - a * fl * back
        spread_dir = (a + t * across * .12).normalized()
        finger(cname, base, spread_dir, (fl * .42 * scale, fl * .3 * scale, fl * .25 * scale),
               fw * (1.05 if cname == "ix" else 1.0) * (.88 if cname == "pk" else 1.0), thick * .4, curl)
    # The thumb from the palm's side near the wrist, out and forward, its
    # ball (the muscle at its root) swelling the palm.
    th_base = wrist + a * palm_len * .28 + t * width * .4 + n * thick * .18
    th_dir = (a * .55 + t * .6 + n * .35).normalized()
    th_axis = th_dir.cross(n).normalized()
    if (Matrix.Rotation(.5, 3, th_axis) @ th_dir).dot(n - t * .5) < 0:
        th_axis = -th_axis
    finger("th", th_base, th_dir, (fl * .4, fl * .32, fl * .27), width * .16, thick * .44, th_axis)
    ball = _ring(bm, wrist + a * palm_len * .3 + t * width * .25 + n * thick * .2, a, t,
                 width * .2, width * .18, 8)
    tag(ball, [(hb, 1.0)])
    bc = _cap(bm, ball, wrist + a * palm_len * .3 + t * width * .28 + n * thick * .45)
    tag([bc], [(hb, 1.0)])
    bc2 = _cap(bm, list(reversed(ball)), wrist + a * palm_len * .3 + t * width * .2 - n * thick * .05)
    tag([bc2], [(hb, 1.0)])
    mesh = bpy.data.meshes.new(name)
    bm.normal_update()
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    vlist = list(bm.verts)
    index = {v: i for i, v in enumerate(vlist)}
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    for v, wts in groups.items():
        for g, w in wts:
            vg = obj.vertex_groups.get(g) or obj.vertex_groups.new(name=g)
            vg.add([index[v]], w, "ADD")
    for poly in mesh.polygons:
        poly.use_smooth = True
    col = mesh.color_attributes.new("shade", "FLOAT_COLOR", "POINT")
    for v, i in index.items():
        sh = colour.get(v, 1.0)
        col.data[i].color = (sh, sh, sh, 1.0)
    h.obj = obj
    return h


def curl_moves(h, curls, oppose=0.0):
    oppose = curls.get("_oppose", oppose) if isinstance(curls, dict) else oppose
    """Each finger bone's move (rest world -> curled, before the hand's own
    move): curls is {chain: [angle per joint]}; `oppose` swings the thumb
    round under the palm first (about the hand's axis), to close on a grip
    from the far side."""
    out = {}
    for c, (joints, _tip) in h.chains.items():
        M = Matrix.Identity(4)
        if c == "th" and oppose:
            ax = h.a if (Matrix.Rotation(.3, 3, h.a) @ h.t).dot(h.n) > 0 else -h.a
            M = Matrix.Translation(joints[0]) @ Matrix.Rotation(oppose, 4, ax) @ Matrix.Translation(-joints[0])
        for k, p in enumerate(joints):
            ang = curls.get(c, [0, 0, 0])[k] if k < len(curls.get(c, [])) else 0.0
            M = M @ Matrix.Translation(p) @ Matrix.Rotation(ang, 4, h.axes[c]) @ Matrix.Translation(-p)
            out["f%s_%s%d" % (h.side, c, k + 1)] = M.copy()
    return out


SHARE = (.36, .4, .24)


def spread(c, total):
    if c == "th":
        return [total * .2, total * .45, total * .35]
    return [total * SHARE[0], total * SHARE[1], total * SHARE[2]]


def finger_points(h, c, total, oppose=0.0):
    """Points along chain c curled by `total` (rest world)."""
    joints, tip = h.chains[c]
    moves = curl_moves(h, {c: spread(c, total)}, oppose)
    pts = []
    for k, p in enumerate(joints):
        M = moves["f%s_%s%d" % (h.side, c, k + 1)]
        nxt = joints[k + 1] if k + 1 < len(joints) else tip
        for f in (0.0, .5, 1.0):
            pts.append(M @ (p + (nxt - p) * f))
    return pts


def grip_curls(h, line_a, line_b, radius, relaxed=.35):
    """Each finger's curl to close round a cylinder (axis line_a-line_b in
    the hand's rest world, radius) without going into it: the most curl at
    which no point of the finger (its own thickness kept) is inside, the
    fingertip then against the far side. None of the hand near it: relaxed."""
    ab = line_b - line_a
    L2 = max(ab.length_squared, 1e-9)

    def dist(p):
        t = max(-.2, min(1.2, (p - line_a).dot(ab) / L2))
        return (p - (line_a + ab * t)).length

    out = {}
    for c in h.chains:
        r_f = h.radius[c] * .8
        best = relaxed
        opp = THUMB_OPPOSE if c == "th" else 0.0
        for k in range(0, 46):
            total = k * .045
            pts = finger_points(h, c, total, opp)
            if min(dist(p) for p in pts) < radius + r_f * .9:
                break
            best = total
        out[c] = spread(c, best)
    return out


THUMB_OPPOSE = .5


MASTER = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets")


def build_meshy(side, wrist, a, n, t, length, width, thick, wrist_r, name, fingers=None):
    """The sculpted master hand (meshy/assets, made once from Meshy's hand by
    hand_master.py) put on this body: in the hand's frame (a, n, t), its
    length this hand's, its width and depth eased toward this hand's; the
    left hand its mirror. Bones and chains as build() makes them."""
    import json

    info = json.load(open(os.path.join(MASTER, "hand_master.json")))
    with bpy.data.libraries.load(os.path.join(MASTER, "hand_master.blend")) as (src, dst):
        dst.objects = ["hand_master"]
    obj = dst.objects[0]
    obj.data = obj.data.copy()
    obj.name = name
    bpy.context.scene.collection.objects.link(obj)
    kw = max(1.0, min(1.3, (width / length) / max(info["width"], 1e-3)))
    kt = max(1.0, min(1.3, (thick / length) / max(info["thick"], 1e-3)))
    # As thick at the wrist as the forearm it joins (a chunky body's hands).
    kw = max(kw, min(1.35, wrist_r * 2.0 / (length * info["width"] * .62)))
    kt = max(kt, min(1.35, wrist_r * 1.6 / (length * info["thick"] * 1.1)))
    # The wrist sleeved a little way up into the forearm (no gap at the seam
    # however the forearm's cut runs), its ring narrowed toward the forearm.
    gh = obj.vertex_groups.get("hand")
    gf = obj.vertex_groups.get("forearm") or obj.vertex_groups.new(name="forearm")
    finger_groups = {g.index for g in obj.vertex_groups if g.name not in ("hand", "forearm")}
    for v in obj.data.vertices:
        z = v.co.z
        if z < .07:
            k = (.07 - z) / .07
            v.co.z = z - k * .09
            v.co.x *= 1.0 - .18 * k
            v.co.y *= 1.0 - .18 * k

    # The sleeve rides the forearm and the wrist blends from forearm to hand
    # over a fifth of the hand's length (a hard step there tore when the hand
    # turned on the wrist).
    for v in obj.data.vertices:
        if any(g.group in finger_groups and g.weight > .05 for g in v.groups):
            continue
        z = v.co.z
        if z < .2:
            wf = min(1.0, max(0.0, (.2 - z) / .25))
            gf.add([v.index], wf, "REPLACE")
            if gh is not None:
                gh.add([v.index], 1.0 - wf, "REPLACE")
    S = Matrix.Diagonal((length * kt, length * kw, length, 1))
    M = Matrix((n, t, a)).transposed().to_4x4()
    X = Matrix.Translation(wrist) @ M @ S
    obj.data.transform(X)
    if X.to_3x3().determinant() < 0:
        obj.data.flip_normals()
    obj.matrix_world = Matrix.Identity(4)
    # A hand of fewer fingers (an alien's three): the others' vertices gone.
    if fingers is not None:
        gone = {obj.vertex_groups[g].index for g in ("rn1", "rn2", "rn3", "pk1", "pk2", "pk3", "ix1", "ix2",
                                                     "ix3", "md1", "md2", "md3", "th1", "th2", "th3")
                if g in obj.vertex_groups and g[:2] not in fingers}
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        dl = bm.verts.layers.deform.active
        doomed = [v for v in bm.verts if dl is not None and v[dl] and
                  max(v[dl].items(), key=lambda kv: kv[1])[0] in gone]
        bmesh.ops.delete(bm, geom=doomed, context="VERTS")
        bm.to_mesh(obj.data)
        bm.free()
    # Its groups named for this side's bones.
    for g in obj.vertex_groups:
        if g.name == "hand":
            g.name = "hand_" + side
        elif g.name == "forearm":
            g.name = "forearm_" + side
        else:
            g.name = "f%s_%s" % (side, g.name)
    me = obj.data
    if "handuv" in me.uv_layers and "UVMap" not in me.uv_layers:
        uvm = me.uv_layers.new(name="UVMap")
        me.uv_layers.active = uvm
    h = Hand(side)
    h.wrist, h.a, h.n, h.t = wrist.copy(), a.copy(), n.copy(), t.copy()
    h.length, h.width, h.thick = length, width, thick
    h.middle = wrist + a * (info["palm"] * length * .55)
    for cname, ch in info["chains"].items():
        if fingers is not None and cname not in fingers:
            continue
        joints = [X @ Vector(j) for j in ch["joints"]]
        tip = X @ Vector(ch["tip"])
        h.chains[cname] = (joints, tip)
        d = (joints[1] - joints[0]).normalized()
        to = (n - t * .5).normalized() if cname == "th" else n
        axis = d.cross(to)
        if axis.length < 1e-6:
            axis = t.cross(d)
        h.axes[cname] = axis.normalized()
        h.radius[cname] = width * (.13 if cname == "th" else .1)
    h.obj = obj
    h.meshy = True
    return h


def contact_curls(h, gear_pts, relaxed=.3):
    """Each finger closed until it touches the held thing's own surface
    (gear_pts: its vertices in the hand's rest world): the most curl at which
    no point of the finger (its thickness kept) is inside, so it rests on
    the surface; the thumb swung round under first. Returns (curls, report):
    report per finger [gap to the surface at the curl chosen (m), whether it
    started inside]."""
    from mathutils.kdtree import KDTree

    tree = KDTree(len(gear_pts))
    for i, p in enumerate(gear_pts):
        tree.insert(p, i)
    tree.balance()

    def near(pts):
        return min(tree.find(p)[2] for p in pts)

    out = {}
    report = {}
    for c in h.chains:
        r_f = h.radius[c]
        opp = 0.0
        if c == "th":
            # The thumb swung round as far under as it goes clear of the thing.
            for o in (THUMB_OPPOSE, .3, .1, 0.0, -.2, -.4):
                opp = o
                if near(finger_points(h, c, 0.0, o)) >= r_f * .8:
                    break
        best = None
        gap = None
        start_in = near(finger_points(h, c, 0.0, opp)) < r_f * .8
        for k in range(0, 75):
            total = k * .04
            d = near(finger_points(h, c, total, opp))
            if d < r_f * .95 and not start_in:
                break
            if start_in and d >= r_f * .95:
                start_in = False
            best = total
            gap = d - r_f
        if best is None:
            best, gap = 0.0, near(finger_points(h, c, 0.0, opp)) - r_f
        out[c] = spread(c, best)
        report[c] = (gap, start_in)
        if c == "th":
            out["_oppose"] = opp
    return out, report


def wrap_curls(h, gear_pts, most=(2.0, 2.1, 1.7)):
    """Each finger wrapped round the held thing joint by joint: the first
    joint bends until its own segment rests on the surface (or, if it begins
    inside, until it is out), then the next joint the same with its segment,
    then the last: so the fingers follow the thing's shape (a thick stock, a
    thin barrel) instead of one curl for the whole finger. The thumb is
    swung round first as far as it goes clear. Returns (curls, report)."""
    from mathutils.kdtree import KDTree

    tree = KDTree(len(gear_pts))
    for i, p in enumerate(gear_pts):
        tree.insert(p, i)
    tree.balance()
    out = {}
    report = {}
    for c, (joints, tip) in h.chains.items():
        r_f = h.radius[c]
        opp = 0.0
        if c == "th":
            for o in (THUMB_OPPOSE, .3, .1, 0.0, -.2, -.4):
                opp = o
                if min(tree.find(p)[2] for p in finger_points(h, c, 0.0, o)) >= r_f * .8:
                    break
        angles = [0.0, 0.0, 0.0]
        inside_any = False
        lim = (.5, .9, .8) if c == "th" else most
        for k in range(3):
            def seg_pts(ang_k, k=k):
                a = list(angles)
                a[k] = ang_k
                moves = curl_moves(h, {c: a, "_oppose": opp})
                p0 = joints[k]
                p1 = joints[k + 1] if k + 1 < len(joints) else tip
                M = moves["f%s_%s%d" % (h.side, c, k + 1)]
                return [M @ (p0 + (p1 - p0) * f) for f in (.35, .7, 1.0)]

            def dist(ang_k):
                return min(tree.find(p)[2] for p in seg_pts(ang_k))

            start_in = dist(0.0) < r_f * .9
            best = 0.0
            steps = 40
            for j in range(1, steps + 1):
                a_k = lim[k] * j / steps
                d = dist(a_k)
                if start_in:
                    best = a_k
                    if d >= r_f * .9:
                        start_in = False
                        break
                else:
                    if d < r_f * .9:
                        break
                    best = a_k
            if start_in:
                inside_any = True
            angles[k] = best
        moves = curl_moves(h, {c: angles, "_oppose": opp})
        pts = []
        for k, p0 in enumerate(joints):
            p1 = joints[k + 1] if k + 1 < len(joints) else tip
            M = moves["f%s_%s%d" % (h.side, c, k + 1)]
            pts += [M @ (p0 + (p1 - p0) * f) for f in (.5, 1.0)]
        gap = min(tree.find(p)[2] for p in pts) - r_f
        out[c] = angles
        report[c] = (gap, inside_any)
        if c == "th":
            out["_oppose"] = opp
    return out, report
