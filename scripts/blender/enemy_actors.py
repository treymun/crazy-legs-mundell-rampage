"""Model, pose and render the remade enemies in Blender.

    blender -b -P scripts/blender/enemy_actors.py -- <out dir> <kinds> <frames> [supersample]

``kinds`` is a comma list from ACTORS, ``frames`` is ``all`` or a comma list of
cel stems (0, w0..w3, aim, fire, pain, recover, fidget, die_0..die_2, down,
quarter_0, side_w1, ...). Each cel is written oversized to <out dir>/<kind>_<stem>.png
with a meta.json; godot/tools/art/build_enemy_actors.gd shrinks them into assets/art.

Every character is built from scratch for every cel: a small skeleton is posed
with two-bone IK, then dressed with capsules and ellipsoids. Nothing here is
traced or sampled from another game.
"""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:]
OUT, KINDS, FRAMES = os.path.abspath(ARGS[0]), ARGS[1].split(","), ARGS[2]
SS = int(ARGS[3]) if len(ARGS) > 3 else 3
TURNS = (("quarter", 45), ("side", 90), ("away", 135), ("back", 180))
ROOT = None
MATS = {}


# ---------------------------------------------------------------- materials
def lin(c):
    c /= 255.0
    return c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4


def mat(r, g, b, rough=.86, metal=0., emit=0., grime=.42, stripes=None, plaid=0.):
    key = (r, g, b, rough, metal, emit, grime, stripes, plaid)
    if key in MATS:
        return MATS[key]
    m = bpy.data.materials.new("m%d" % len(MATS))
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    base = (lin(r), lin(g), lin(b), 1)
    bsdf.inputs["Base Color"].default_value = base
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit:
        bsdf.inputs["Emission Color"].default_value = base
        bsdf.inputs["Emission Strength"].default_value = emit
    source = None
    if stripes:
        freq, (r2, g2, b2) = stripes
        coord = nt.nodes.new("ShaderNodeTexCoord")
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(coord.outputs["Object"], sep.inputs[0])
        mul = nt.nodes.new("ShaderNodeMath")
        mul.operation = "MULTIPLY"
        mul.inputs[1].default_value = freq
        nt.links.new(sep.outputs[0], mul.inputs[0])
        frac = nt.nodes.new("ShaderNodeMath")
        frac.operation = "FRACT"
        nt.links.new(mul.outputs[0], frac.inputs[0])
        gate = nt.nodes.new("ShaderNodeMath")
        gate.operation = "GREATER_THAN"
        gate.inputs[1].default_value = .5
        nt.links.new(frac.outputs[0], gate.inputs[0])
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.inputs[6].default_value = base
        mix.inputs[7].default_value = (lin(r2), lin(g2), lin(b2), 1)
        nt.links.new(gate.outputs[0], mix.inputs[0])
        source = mix.outputs[2]
    if plaid:
        coord = nt.nodes.new("ShaderNodeTexCoord")
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(coord.outputs["Object"], sep.inputs[0])
        source = None
        for axis, shade in ((0, .46), (2, .62)):
            mul = nt.nodes.new("ShaderNodeMath")
            mul.operation = "MULTIPLY"
            mul.inputs[1].default_value = plaid
            nt.links.new(sep.outputs[axis], mul.inputs[0])
            frac = nt.nodes.new("ShaderNodeMath")
            frac.operation = "FRACT"
            nt.links.new(mul.outputs[0], frac.inputs[0])
            gate = nt.nodes.new("ShaderNodeMath")
            gate.operation = "GREATER_THAN"
            gate.inputs[1].default_value = .56
            nt.links.new(frac.outputs[0], gate.inputs[0])
            band = nt.nodes.new("ShaderNodeMix")
            band.data_type = "RGBA"
            band.blend_type = "MULTIPLY"
            band.inputs[6].default_value = base
            band.inputs[7].default_value = (shade, shade, shade, 1)
            if source is not None:
                nt.links.new(source, band.inputs[6])
            nt.links.new(gate.outputs[0], band.inputs[0])
            source = band.outputs[2]
    if grime and not emit:
        # Blotchy wear at two scales, then road dirt climbing up from the boots.
        for scale, amount in ((5.0, grime), (34.0, grime * .7)):
            noise = nt.nodes.new("ShaderNodeTexNoise")
            noise.inputs["Scale"].default_value = scale
            noise.inputs["Detail"].default_value = 4.0
            dirt = nt.nodes.new("ShaderNodeMix")
            dirt.data_type = "RGBA"
            dirt.blend_type = "MULTIPLY"
            dirt.inputs[0].default_value = amount
            dirt.inputs[6].default_value = base
            if source is not None:
                nt.links.new(source, dirt.inputs[6])
            nt.links.new(noise.outputs[0], dirt.inputs[7])
            source = dirt.outputs[2]
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        sepz = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(geo.outputs["Position"], sepz.inputs[0])
        ramp = nt.nodes.new("ShaderNodeMapRange")
        ramp.inputs[1].default_value = .0
        ramp.inputs[2].default_value = .75
        ramp.inputs[3].default_value = .38
        ramp.inputs[4].default_value = .0
        nt.links.new(sepz.outputs[2], ramp.inputs[0])
        mud = nt.nodes.new("ShaderNodeMix")
        mud.data_type = "RGBA"
        mud.inputs[7].default_value = (lin(70), lin(54), lin(38), 1)
        nt.links.new(ramp.outputs[0], mud.inputs[0])
        nt.links.new(source, mud.inputs[6])
        source = mud.outputs[2]
        wrinkle = nt.nodes.new("ShaderNodeTexNoise")
        wrinkle.inputs["Scale"].default_value = 16.0
        wrinkle.inputs["Detail"].default_value = 5.0
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value = .34
        bump.inputs["Distance"].default_value = .03
        nt.links.new(wrinkle.outputs[0], bump.inputs["Height"])
        nt.links.new(bump.outputs[0], bsdf.inputs["Normal"])
    if source is not None:
        nt.links.new(source, bsdf.inputs["Base Color"])
    MATS[key] = m
    return m


STEEL = lambda: mat(70, 72, 78, .45, .85, grime=.3)
DARK = lambda: mat(34, 34, 38, .5, .6, grime=.1)
WOOD = lambda: mat(96, 60, 36, .7)
BRASS = lambda: mat(168, 132, 62, .45, .85, grime=.3)
WHITE = lambda: mat(206, 198, 176, .6, grime=0)
BLACK = lambda: mat(14, 14, 16, .35, grime=0)
MOUTH = lambda: mat(48, 14, 14, .7, grime=0)
TOOTH = lambda: mat(232, 222, 180, .5, grime=0)


# ---------------------------------------------------------------- primitives
def T(v):
    return Matrix.Translation(Vector(v))


def R(rx=0., ry=0., rz=0.):
    return Euler((rx, ry, rz), "XYZ").to_matrix().to_4x4()


def place(bm, matrix, material, smooth=True):
    me = bpy.data.meshes.new("part")
    bm.to_mesh(me)
    bm.free()
    if smooth:
        me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
        me.set_sharp_from_angle(angle=math.radians(55))
    me.materials.append(material)
    ob = bpy.data.objects.new("part", me)
    bpy.context.scene.collection.objects.link(ob)
    ob.parent = ROOT
    ob.matrix_basis = matrix
    return ob


def ball(c, r, material, M=None, rot=(0, 0, 0)):
    if isinstance(r, (int, float)):
        r = (r, r, r)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=14, radius=1.0)
    matrix = T(c) @ R(*rot) @ Matrix.Diagonal((r[0], r[1], r[2], 1))
    place(bm, (M @ matrix) if M is not None else matrix, material)


def limb(a, b, ra, rb, material, M=None, caps=True, seg=18):
    a, b = Vector(a), Vector(b)
    if M is not None:
        a, b = M @ a, M @ b
    d = b - a
    if d.length < 1e-5:
        return
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg,
                          radius1=ra, radius2=rb, depth=d.length)
    place(bm, T((a + b) / 2) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4(), material)
    if caps:
        ball(a, ra * 1.045, material)
        ball(b, rb * 1.045, material)


def disc(center, direction, radius, thick, material):
    c, d = Vector(center), Vector(direction).normalized()
    limb(c - d * thick / 2, c + d * thick / 2, radius, radius, material, caps=False, seg=28)


def ring(center, normal, radius, thick, material, n=18, M=None):
    c, k = Vector(center), Vector(normal).normalized()
    if M is not None:
        c, k = M @ c, (M.to_3x3() @ k).normalized()
    u = k.orthogonal().normalized()
    v = k.cross(u)
    pts = [c + (u * math.cos(i * math.tau / n) + v * math.sin(i * math.tau / n)) * radius for i in range(n)]
    for i in range(n):
        limb(pts[i], pts[(i + 1) % n], thick, thick, material, caps=False, seg=8)


def box(c, size, material, M=None, rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    matrix = T(c) @ R(*rot) @ Matrix.Diagonal((size[0], size[1], size[2], 1))
    place(bm, (M @ matrix) if M is not None else matrix, material, smooth=False)


def star(c, radius, material, M):
    bm = bmesh.new()
    hub = bm.verts.new((0, -.02, 0))
    rim = [bm.verts.new((math.sin(i * math.tau / 10) * radius * (1 if i % 2 == 0 else .45), 0,
                         math.cos(i * math.tau / 10) * radius * (1 if i % 2 == 0 else .45)))
           for i in range(10)]
    for i in range(10):
        bm.faces.new((hub, rim[(i + 1) % 10], rim[i]))
    place(bm, M @ T(c), material, smooth=False)


def flash(at, size, rgb):
    glow = mat(*rgb, emit=2.4)
    core = mat(255, 244, 190, emit=2.6)
    at = Vector(at)
    for i in range(8):
        a = i * math.tau / 8 + .2
        reach = size * (1.0 if i % 2 == 0 else .58)
        limb(at, at + Vector((math.cos(a), -.15, math.sin(a))) * reach, size * .17, .004, glow, caps=False)
    ball(at + Vector((0, -.03, 0)), size * .30, core)


def ik(a, c, l1, l2, pole):
    a, c = Vector(a), Vector(c)
    d = c - a
    reach = l1 + l2 - 1e-3
    if d.length > reach:
        c = a + d * (reach / d.length)
        d = c - a
    span = max(d.length, abs(l1 - l2) + 1e-3)
    x = (l1 * l1 - l2 * l2 + span * span) / (2 * span)
    h = math.sqrt(max(l1 * l1 - x * x, 0.))
    n = d.normalized()
    p = Vector(pole)
    p = p - n * p.dot(n)
    p = p.normalized() if p.length > 1e-6 else Vector((0, -1, 0))
    return a + n * x + p * h, c


def unit(*v):
    return Vector(v).normalized()


# ---------------------------------------------------------------- skeleton
def skeleton(S, frame):
    """Pose the joints. The character faces -Y; its right hand is at -X."""
    walk = frame if isinstance(frame, int) else 0
    swing = None
    stepping = isinstance(frame, str) and frame[0] == "w" and frame[1:].isdigit()
    if stepping:
        # Four-beat walk: left contact, right leg passing, right contact, left leg passing.
        beat = int(frame[1:])
        walk = (1, 0, -1, 0)[beat]
        swing = (None, "R", None, "L")[beat]
    dead = frame == "down" or (isinstance(frame, str) and frame.startswith("die_"))
    stage = int(frame[4:]) if dead and frame != "down" else 5
    lean, twist, bob, sway, head = S["lean"], 0., 0., 0., (0., 0., 0.)
    if isinstance(frame, int) or stepping:
        bob, twist, sway = -.03 * abs(walk), .14 * walk, .025 * walk
        if swing:
            bob, sway = .012, (.035 if swing == "R" else -.035)
    elif frame == "aim":
        lean, twist = lean + .07, -.14
    elif frame == "fire":
        lean, twist, head = lean - .11, -.10, (-.08, 0, 0)
    elif frame == "pain":
        lean, twist, bob, sway, head = -.30, .38, -.06, -.06, (-.38, 0, .30)
    elif frame == "recover":
        lean, bob = lean + .15, -.035
    elif frame == "fidget":
        head = S.get("fidget_head", (0., .12, .28))
    elif dead:
        # Jolt, stagger, buckle, topple, land; stage 5 is the body at rest.
        lean = (-.20, -.30, -.34, -.28, -.20, -.22)[stage]
        twist = (.34, .26, .16, .10, .05, .22)[stage]
        bob = (-.04, -.11, -.17, -.12, -.05, -.03)[stage]
        head = ((-.2, 0, .3), (-.42, 0, .25), (-.5, 0, .1), (-.4, 0, -.1), (-.25, 0, -.2), (-.45, 0, .25))[stage]
    J = {"frame": frame, "walk": walk, "dead": dead, "stage": stage}
    pel = Vector((sway, 0, S["hip_h"] + bob))
    J["offset"] = Vector((sway, 0, bob))
    J["torso"] = Tm = T(pel) @ R(0, 0, twist) @ R(lean, 0, 0)
    J["head"] = Tm @ T((0, S["head_fwd"], S["torso_len"] + S["neck"])) @ R(*head) @ Matrix.Scale(S.get("head_scale", 1.), 4)
    for side, tag in ((-1, "R"), (1, "L")):
        hip = pel + Vector((side * S["hip_w"], 0, 0))
        step = walk * side
        foot = Vector((side * S["stance"] + sway * .3, -step * S["stride"],
                       S["ankle"] + (.055 if step < 0 else 0.)))
        if dead and 2 <= stage <= 4:
            # The legs come off the ground as the body goes over.
            kick = (stage - 1) * (.07 if tag == "L" else .04)
            foot.y -= kick * 1.6
            foot.z += kick
        if swing == tag:
            foot.y, foot.z = -.06, S["ankle"] + .13
        elif swing:
            foot.y = .05
        if frame == "pain":
            foot.y += .10 * side
        if frame == "down":
            foot = Vector((side * (S["stance"] + .10), -.04 * side, S["ankle"]))
        knee, foot = ik(hip, foot, S["thigh"], S["shin"], (side * S.get("bow", .12), -1, 0))
        J["hip" + tag], J["knee" + tag], J["foot" + tag] = hip, knee, foot
        J["toe" + tag] = -1 if swing == tag else step
        J["sh" + tag] = Tm @ Vector((side * S["sw"], 0, S["torso_len"]))
    return J


def arms(S, J, hands, sleeve, palm=None):
    """sleeve(tag, shoulder, elbow, hand) draws one arm; palm=(material, radius) adds fingers and a thumb."""
    for side, tag in ((-1, "R"), (1, "L")):
        elbow, hand = ik(J["sh" + tag], hands[tag], S["upper"], S["fore"], (side * .7, .55, -.8))
        sleeve(tag, J["sh" + tag], elbow, hand)
        if palm:
            material, r = palm
            reach = (hand - elbow).normalized()
            ball(hand + reach * r * .95, r * .88, material)
            ball(hand + reach * r * 1.7, r * .62, material)
            ball(hand + reach * r * .35 + Vector((-side * r * .95, 0, r * .35)), r * .46, material)


def legs(S, J, cloth, radii, boot, cuff=None, boot_top=0.):
    r0, r1, r2 = radii
    for side, tag in ((-1, "R"), (1, "L")):
        hip, knee, foot = J["hip" + tag], J["knee" + tag], J["foot" + tag]
        limb(hip, knee, r0, r1, cloth)
        limb(knee, foot, r1, r2, cloth)
        if boot_top:
            limb(knee.lerp(foot, 1 - boot_top), foot, r1 * (1 - boot_top) + r2 * boot_top + .008, r2 + .008, boot)
        if cuff:
            limb(foot + Vector((0, 0, .05)), foot + Vector((0, 0, .0)), r2 + .012, r2 + .016, cuff, caps=False)
        drop = -.05 if J["toe" + tag] < 0 else 0.
        heel = Vector((foot.x, foot.y + .035, foot.z - S["ankle"] + .045))
        toe = Vector((foot.x + side * .035, foot.y - .17, foot.z - S["ankle"] + .04 + drop))
        limb(heel, toe, S["boot"], S["boot"] * .86, boot)
        low = Vector((0, 0, -S["boot"] * .55))
        limb(heel + low, toe + low, S["boot"] * .62, S["boot"] * .56, mat(24, 20, 18, .9, grime=.2))
        limb(foot, heel, r2 + .006, S["boot"], boot)


# ---------------------------------------------------------------- billy
BILLY = dict(lean=.10, hip_h=.78, hip_w=.15, stance=.20, stride=.21, ankle=.08, thigh=.375, shin=.36,
             torso_len=.50, neck=.16, head_fwd=-.035, sw=.30, upper=.30, fore=.28, boot=.068, bow=.2,
             canvas=(1.75, 1.86), px=152, depth=.24, head_scale=1.0)


def gun_hold(table, J, default="ready"):
    frame = J["frame"]
    key = frame if frame in table else default
    g, d = table[key]
    g = Vector(g) + J["offset"]
    g = g + Vector((0, 0, .018 * J["walk"]))
    return g, unit(*d)


def billy(frame):
    S = BILLY
    J = skeleton(S, frame)
    Tm, Hm = J["torso"], J["head"]
    skin = mat(186, 118, 86, .75, grime=.42)
    denim, denim_dark = mat(66, 78, 108), mat(44, 52, 76)
    shirt = mat(142, 44, 36, .9, plaid=3.6)
    flannel = mat(142, 44, 36, .9, plaid=13.0)
    cap, beard = mat(92, 88, 58, .9), mat(64, 44, 28, .95)
    boot = mat(70, 48, 32, .8)
    # torso
    ball((0, .01, .02), (.27, .21, .17), denim, Tm)
    ball((0, -.05, .23), (.318, .25, .20), shirt, Tm)
    ball((0, -.095, .16), (.31, .27, .24), denim, Tm)
    ball((0, 0, .38), (.29, .20, .19), shirt, Tm)
    ball((0, -.135, .35), (.175, .085, .16), denim, Tm)
    ball((0, .075, .20), (.27, .17, .22), denim, Tm)
    box((.13, .215, .06), (.11, .03, .11), denim_dark, Tm, (-.2, 0, 0))
    box((-.11, .235, .16), (.09, .03, .09), mat(126, 104, 70, .95), Tm, (-.1, 0, .2))
    limb((-.2, -.02, .575), (.2, .16, .34), .028, .028, denim, Tm)
    box((0, -.222, .355), (.15, .02, .10), denim_dark, Tm, (.12, 0, 0))
    for s in (-1, 1):
        ball((s * .13, -.195, .465), .024, BRASS(), Tm)
        limb((s * .13, -.19, .46), (s * .175, -.02, .575), .03, .03, denim, Tm)
        limb((s * .175, -.02, .575), (s * .10, .18, .38), .03, .03, denim, Tm)
    limb((0, -.01, .50), (0, -.03, .62), .095, .085, skin, Tm)
    # head
    ball((0, 0, 0), (.145, .155, .16), skin, Hm)
    ball((0, -.02, -.08), (.158, .14, .10), skin, Hm)
    ball((0, -.07, -.135), (.15, .12, .13), beard, Hm)
    for s in (-1, 1):
        ball((s * .13, -.02, -.05), .062, beard, Hm)
        ball((s * .048, -.165, -.058), (.052, .026, .026), beard, Hm)
        ball((s * .056, -.138, .040), .021, WHITE(), Hm)
        ball((s * .056, -.152, .039), .011, BLACK(), Hm)
        limb((s * .10, -.142, .078), (s * .018, -.160, .060), .017, .017, mat(50, 34, 22), Hm)
        ball((s * .152, .01, 0), (.025, .035, .046), skin, Hm)
    ball((0, -.166, -.004), (.04, .046, .04), mat(190, 108, 86, .7, grime=.3), Hm)
    wide = frame in ("pain", "fire") or J["dead"]
    ball((0, -.178, -.105), (.05, .022, .034 if wide else .02), MOUTH(), Hm)
    box((.014, -.196, -.092), (.02, .012, .022), TOOTH(), Hm)
    ball((0, .005, .075), (.156, .166, .115), cap, Hm)
    ball((0, -.078, .10), (.105, .09, .085), mat(150, 140, 108, .9), Hm)
    ball((0, -.205, .068), (.118, .115, .016), cap, Hm, (-.16, 0, 0))
    ball((0, .005, .19), .02, cap, Hm)
    # shotgun
    hold = {"ready": ((-.23, -.31, .92), (.78, -.34, .46)), "aim": ((-.22, -.34, 1.13), (.46, -1, .0)),
            "fire": ((-.22, -.30, 1.16), (.46, -1, .13)), "recover": ((-.21, -.33, 1.02), (.5, -.7, .12)),
            "pain": ((-.44, -.16, .98), (-.3, -.3, .9)), "fidget": ((-.32, -.16, .80), (.1, -.5, -.85))}
    g, d = gun_hold(hold, J)
    shoulder_z = (Tm @ Vector((0, 0, S["torso_len"]))).z
    hands = {"R": g, "L": g + d * .37}
    if frame == "pain":
        hands["L"] = Vector((.46, -.12, shoulder_z + .16))
    if frame == "fidget":
        hands["L"] = Hm @ Vector((.13, -.10, .16))
    if J["dead"]:
        hands = flung(J, S, .52)
    else:
        side = d.cross(Vector((0, 0, 1))).normalized() * .021
        for off in (side, -side):
            limb(g + d * .09 + off, g + d * .66 + off, .019, .019, STEEL(), caps=False)
        limb(g - d * .02, g + d * .13, .036, .034, DARK())
        limb(g - d * .03, g - d * .30 + Vector((0, 0, -.07)), .034, .05, WOOD())
        limb(g + d * .28, g + d * .46, .032, .03, WOOD())
        if frame == "fire":
            flash(g + d * .70, .21, (255, 168, 60))

    def sleeve(tag, sh, el, hand):
        ball(sh, .112, flannel)
        limb(sh, el, .104, .09, flannel)
        limb(el, el.lerp(hand, .22), .092, .088, flannel)
        limb(el.lerp(hand, .2), hand, .08, .06, skin)
        ball(hand, (.066, .066, .07), skin)

    arms(S, J, hands, sleeve, (skin, .058))
    legs(S, J, denim, (.138, .112, .096), boot, cuff=denim_dark)


# ---------------------------------------------------------------- coot
COOT = dict(lean=.20, hip_h=.92, hip_w=.095, stance=.17, stride=.20, ankle=.07, thigh=.45, shin=.435,
            torso_len=.50, neck=.14, head_fwd=-.07, sw=.19, upper=.31, fore=.29, boot=.05, bow=.42,
            canvas=(1.6, 1.98), px=156, depth=.14, head_scale=1.0, fidget_head=(-.38, 0, -.1))


def coot(frame):
    S = COOT
    J = skeleton(S, frame)
    Tm, Hm = J["torso"], J["head"]
    skin = mat(176, 124, 92, .8, grime=.45)
    red = mat(126, 60, 52, .95)
    pants, patch = mat(72, 66, 50, .95), mat(112, 96, 62, .95)
    brace = mat(58, 42, 32)
    white = mat(170, 166, 152, .95, grime=.4)
    felt = mat(74, 60, 42, .95)
    boot = mat(58, 44, 34, .7)
    stone, glaze = mat(150, 130, 96, .6), mat(78, 50, 32, .5)
    # torso
    ball((0, 0, 0), (.17, .13, .13), pants, Tm)
    ball((0, -.01, .13), (.162, .126, .14), pants, Tm)
    ball((0, -.05, .22), (.15, .12, .11), red, Tm)
    ball((0, 0, .36), (.18, .12, .17), red, Tm)
    ball((0, .06, .42), (.16, .11, .11), red, Tm)
    for k in range(4):
        ball((0, -.122 - .012 * (k < 2), .23 + k * .065), .014, WHITE(), Tm)
    for s in (-1, 1):
        limb((s * .09, -.118, .19), (s * .115, -.03, .525), .018, .018, brace, Tm)
        limb((s * .115, -.03, .525), (s * .08, .13, .24), .018, .018, brace, Tm)
    limb((0, -.01, .48), (0, S["head_fwd"], .58), .048, .042, skin, Tm)
    # head
    ball((0, 0, 0), (.105, .12, .13), skin, Hm)
    ball((0, -.03, -.07), (.085, .095, .08), skin, Hm)
    limb((0, -.065, -.09), (0, -.135, -.44), .10, .018, white, Hm)
    for s in (-1, 1):
        ball((s * .08, -.05, -.075), .062, white, Hm)
        ball((s * .04, -.135, -.052), (.045, .024, .024), white, Hm)
        ball((s * .112, 0, .0), (.02, .035, .052), skin, Hm)
        ball((s * .10, .03, .01), .05, white, Hm)
        ball((s * .05, -.105, .062), (.036, .02, .016), white, Hm, (0, -s * .35, 0))
    ball((-.044, -.098, .030), .019, WHITE(), Hm)
    ball((-.044, -.113, .030), .010, BLACK(), Hm)
    ball((.046, -.100, .034), .021, WHITE(), Hm)
    ball((.046, -.116, .034), .010, BLACK(), Hm)
    ball((0, -.135, -.012), (.034, .052, .042), mat(180, 108, 88, .7, grime=.3), Hm)
    wide = frame in ("pain", "fire") or J["dead"]
    ball((0, -.135, -.092), (.03, .02, .028 if wide else .014), MOUTH(), Hm)
    box((-.008, -.15, -.082), (.014, .01, .018), TOOTH(), Hm)
    ball((0, 0, .088), (.215, .225, .02), felt, Hm, (.10, .14, 0))
    ball((0, .01, .14), (.112, .122, .10), felt, Hm)
    ball((0, .01, .105), (.116, .126, .028), brace, Hm)
    # revolver and jug
    hold = {"ready": ((-.29, -.19, .88), (.1, -.8, -.5)), "aim": ((-.36, -.50, 1.33), (.3, -1, 0)),
            "fire": ((-.36, -.45, 1.40), (.3, -1, .26)), "recover": ((-.27, -.39, 1.15), (.2, -.9, -.2)),
            "pain": ((-.42, -.1, 1.25), (-.4, -.2, .9))}
    g, d = gun_hold(hold, J)
    jug = Vector((.28, -.06, .82)) + J["offset"] + Vector((0, 0, -.02 * J["walk"]))
    if frame == "fidget":
        jug = Hm @ Vector((.07, -.21, -.10))
    if frame == "pain":
        jug = Vector((.42, -.12, 1.18))
    shoulder_z = (Tm @ Vector((0, 0, S["torso_len"]))).z
    hands = {"R": g, "L": jug}
    if J["dead"]:
        hands = flung(J, S, .44)
    else:
        limb(g + d * .05, g + d * .30, .015, .014, STEEL(), caps=False)
        limb(g + d * .0, g + d * .075, .03, .03, DARK(), caps=False)
        limb(g - d * .02, g + d * .09 + Vector((0, 0, .028)), .016, .016, STEEL())
        limb(g, g - d * .03 + Vector((0, 0, -.09)), .02, .024, WOOD())
        if frame == "fire":
            flash(g + d * .34, .17, (255, 168, 60))
        tip = Vector((0, 0, 1)) if frame != "fidget" else unit(-.5, .3, .6)
        body = jug - tip * .17 if frame != "fidget" else jug + unit(.5, -.3, -.2) * .15
        ball(body, (.105, .105, .115), stone)
        ball(body + tip * .045, (.098, .098, .075), glaze)
        limb(body + tip * .09, body + tip * .17, .04, .032, glaze, caps=False)
        ring(body + tip * .12 + Vector((.045, 0, 0)), (0, 1, 0), .034, .011, glaze, n=10)

    def sleeve(tag, sh, el, hand):
        ball(sh, .062, red)
        limb(sh, el, .054, .046, red)
        limb(el, el.lerp(hand, .3), .05, .046, red)
        limb(el.lerp(hand, .25), hand, .038, .03, skin)
        ball(hand, .043, skin)

    arms(S, J, hands, sleeve, (skin, .038))
    legs(S, J, pants, (.098, .072, .056), boot, boot_top=.3)
    k = J["kneeL"]
    ball((k.x, k.y - .04, k.z - .01), (.058, .04, .066), patch)


# ---------------------------------------------------------------- alien sheriff
BOSS = dict(lean=.03, hip_h=1.02, hip_w=.13, stance=.21, stride=.22, ankle=.08, thigh=.49, shin=.48,
            torso_len=.60, neck=.25, head_fwd=-.02, sw=.31, upper=.37, fore=.37, boot=.066, bow=.1,
            canvas=(1.9, 2.42), px=184, depth=.2, head_scale=1.0)


def boss(frame):
    S = BOSS
    J = skeleton(S, frame)
    Tm, Hm = J["torso"], J["head"]
    green = mat(112, 128, 92, .6, grime=.45)
    eye = mat(8, 10, 12, .08, grime=0)
    tan, tan_dark = mat(150, 126, 86, .9), mat(118, 98, 64, .9)
    trouser = mat(58, 50, 42, .9)
    belt = mat(26, 24, 22, .45, grime=.1)
    gold = mat(186, 146, 58, .4, .85, grime=.25)
    felt, band = mat(98, 78, 52, .95), mat(44, 32, 24, .9)
    boot = mat(34, 30, 28, .4, grime=.1)
    chrome = mat(120, 126, 132, .35, .9, grime=.3)
    glow = mat(120, 255, 140, emit=2.4)
    hot = frame in ("aim", "fire")
    # torso
    ball((0, 0, .02), (.22, .16, .15), trouser, Tm)
    ball((0, 0, .10), (.228, .172, .048), belt, Tm)
    box((0, -.172, .10), (.075, .02, .065), gold, Tm)
    ball((0, -.01, .23), (.21, .155, .16), tan, Tm)
    ball((0, -.01, .44), (.29, .162, .20), tan, Tm)
    limb((-.2, .155, .50), (.2, .155, .50), .009, .009, tan_dark, Tm, caps=False)
    for k in range(-3, 4):
        limb((k * .055, .165, .085), (k * .055, .165, .12), .011, .011, gold, Tm)
    limb((-.27, 0, .575), (.27, 0, .575), .09, .09, tan, Tm)
    for s in (-1, 1):
        box((s * .135, -.178, .44), (.115, .02, .095), tan_dark, Tm)
        ball((s * .065, -.125, .615), (.06, .04, .035), tan, Tm, (0, s * .5, 0))
        box((s * .25, 0, .668), (.13, .09, .02), band, Tm)
    star((.135, -.20, .455), .062, gold, Tm)
    limb((0, -.19, .585), (0, -.205, .33), .024, .03, belt, Tm)
    box((-.25, .01, .0), (.07, .13, .22), band, Tm)
    limb((0, 0, .60), (0, -.015, .82), .052, .045, green, Tm)
    # head
    ball((0, .02, .06), (.17, .185, .17), green, Hm)
    ball((0, -.03, -.08), (.11, .12, .12), green, Hm)
    ball((0, -.06, -.165), (.055, .06, .05), green, Hm)
    for s in (-1, 1):
        ball((s * .08, -.128, -.015), (.076, .038, .048), eye, Hm, (0, s * .62, 0))
        limb((s * .15, -.135, .055), (s * .03, -.17, .018), .02, .016, green, Hm)
        ball((s * .014, -.148, -.095), .006, band, Hm)
    limb((-.032, -.132, -.14), (.032, -.132, -.14), .008, .008, band, Hm)
    ball((0, 0, .168), (.31, .31, .02), felt, Hm, (.07, 0, 0))
    for s in (-1, 1):
        ball((s * .27, 0, .19), (.06, .26, .022), felt, Hm, (.07, -s * .5, 0))
    ball((0, 0, .255), (.152, .166, .12), felt, Hm)
    ball((0, 0, .192), (.158, .172, .032), band, Hm)
    star((0, -.172, .235), .034, gold, Hm)
    # blaster
    hold = {"ready": ((-.37, -.14, 1.04), (.0, -.75, -.65)), "aim": ((-.46, -.52, 1.50), (.5, -1, -.03)),
            "fire": ((-.46, -.47, 1.56), (.5, -1, .2)), "recover": ((-.31, -.42, 1.32), (.1, -.9, -.35)),
            "pain": ((-.52, -.1, 1.5), (-.4, -.2, .9))}
    g, d = gun_hold(hold, J)
    shoulder_z = (Tm @ Vector((0, 0, S["torso_len"]))).z
    hands = {"R": g, "L": Tm @ Vector((.23, -.15, .11))}
    if frame == "pain":
        hands["L"] = Vector((.52, -.1, shoulder_z + .1))
    if J["dead"]:
        hands = flung(J, S, .6)
    else:
        limb(g - d * .05, g + d * .24, .052, .046, chrome)
        box(g + d * .08 + Vector((0, 0, .06)), (.02, .02, .05), chrome)
        limb(g + d * .02, g + d * .02 + Vector((0, 0, -.11)), .024, .026, belt)
        for k, radius in enumerate((.058, .046, .034)):
            disc(g + d * (.28 + k * .05), d, radius, .018, glow if hot else chrome)
        ball(g + d * .43, .024, glow)
        if frame == "fire":
            flash(g + d * .48, .24, (130, 255, 120))

    def sleeve(tag, sh, el, hand):
        ball(sh, .095, tan)
        limb(sh, el, .08, .064, tan)
        limb(el, el.lerp(hand, .78), .064, .05, tan)
        limb(el.lerp(hand, .74), el.lerp(hand, .80), .056, .056, tan_dark, caps=False)
        limb(el.lerp(hand, .78), hand, .036, .034, green)
        ball(hand, (.05, .05, .055), green)
        reach = (hand - el).normalized()
        if not J["dead"] and tag == "R":
            return
        for k in (-1, 0, 1):
            tip = hand + reach * .11 + Vector((k * .035, 0, 0))
            limb(hand, tip, .016, .012, green)

    arms(S, J, hands, sleeve)
    legs(S, J, trouser, (.105, .088, .072), boot, boot_top=.62)


# ---------------------------------------------------------------- rudy racket
RUDY = dict(lean=.04, hip_h=.88, hip_w=.14, stance=.21, stride=.20, ankle=.08, thigh=.42, shin=.41,
            torso_len=.56, neck=.16, head_fwd=-.03, sw=.31, upper=.32, fore=.30, boot=.066, bow=.14,
            canvas=(2.0, 2.22), px=172, depth=.26, head_scale=1.0)


def rudy(frame):
    S = RUDY
    J = skeleton(S, frame)
    Tm, Hm = J["torso"], J["head"]
    skin = mat(190, 126, 98, .75, grime=.4)
    coat = mat(124, 34, 38, .9)
    black = mat(30, 28, 30, .7, grime=.35)
    gold = mat(176, 138, 58, .45, .85, grime=.3)
    vest = mat(142, 116, 60, .9)
    stripe = mat(186, 174, 142, .9, stripes=(11.0, (86, 50, 46)))
    stripe_ball = mat(186, 174, 142, .9, stripes=(2.6, (86, 50, 46)))
    glove = mat(190, 184, 164, .85)
    hair = mat(24, 20, 18, .6, grime=0)
    horn_in = mat(70, 34, 20, .7, grime=.1)
    # torso
    ball((0, 0, .02), (.23, .18, .16), stripe_ball, Tm)
    ball((0, -.065, .21), (.265, .235, .22), vest, Tm)
    ball((0, -.01, .43), (.30, .21, .20), coat, Tm)
    ball((0, .075, .24), (.27, .2, .30), coat, Tm)
    for s in (-1, 1):
        ball((s * .205, .01, .22), (.14, .2, .26), coat, Tm)
        ball((s * .13, .215, -.15), (.115, .05, .31), coat, Tm, (.14, 0, s * .08))
        ball((s * .07, .275, .13), .022, gold, Tm)
        ball((s * .16, -.235, .40), .017, gold, Tm)
        limb((s * .065, -.205, .56), (s * .155, -.215, .32), .034, .028, black, Tm)
        ball((s * .32, 0, .585), (.10, .09, .036), gold, Tm)
        ball((s * .052, -.205, .575), (.05, .02, .034), black, Tm)
    for k in range(3):
        ball((0, -.295 + .012 * k, .14 + k * .085), .022, gold, Tm)
    ball((0, -.19, .50), (.075, .04, .07), WHITE(), Tm)
    ball((0, -.212, .575), .022, black, Tm)
    limb((0, -.01, .56), (0, -.03, .66), .085, .08, skin, Tm)
    # head
    ball((0, 0, 0), (.14, .15, .155), skin, Hm)
    ball((0, -.03, -.09), (.13, .12, .09), skin, Hm)
    ball((0, -.10, -.135), (.07, .06, .05), skin, Hm)
    for s in (-1, 1):
        ball((s * .078, -.10, -.035), .054, mat(196, 116, 96, .75, grime=.35), Hm)
        ball((s * .056, -.136, .04), .02, WHITE(), Hm)
        ball((s * .056, -.150, .04), .011, BLACK(), Hm)
        limb((s * .10, -.14, .078), (s * .055, -.15, .098), .017, .017, hair, Hm)
        limb((s * .055, -.15, .098), (s * .015, -.152, .082), .017, .017, hair, Hm)
        limb((0, -.168, -.055), (s * .10, -.155, -.068), .028, .02, hair, Hm)
        limb((s * .10, -.155, -.068), (s * .165, -.13, -.005), .02, .007, hair, Hm)
        ball((s * .148, .01, 0), (.024, .034, .045), skin, Hm)
        ball((s * .135, .0, -.04), (.03, .06, .07), hair, Hm)
    ring((-.056, -.156, .04), (0, 1, 0), .03, .006, gold, n=14, M=Hm)
    ball((0, -.166, -.005), (.04, .044, .04), mat(194, 104, 88, .7, grime=.3), Hm)
    wide = frame in ("pain", "fire", "aim") or J["dead"]
    ball((0, -.158, -.105), (.052, .02, .034 if wide else .02), MOUTH(), Hm)
    box((0, -.176, -.092), (.07, .01, .016), TOOTH(), Hm)
    Hat = Hm @ T((0, 0, .115)) @ R(.05, .12, 0)
    ball((0, 0, 0), (.215, .215, .016), black, Hat)
    limb((0, 0, 0), (0, 0, .30), .136, .154, black, Hat, caps=False, seg=28)
    limb((0, 0, .012), (0, 0, .07), .140, .144, coat, Hat, caps=False, seg=28)
    # megaphone and cane
    hold = {"ready": ((-.36, -.22, 1.04), (-.3, -.6, .75)), "aim": ((-.11, -.24, 1.47), (-.36, -.93, -.04)),
            "fire": ((-.11, -.22, 1.50), (-.36, -.93, .06)), "recover": ((-.27, -.31, 1.26), (-.3, -.8, .4)),
            "pain": ((-.5, -.1, 1.22), (-.5, -.2, .85))}
    p, d = gun_hold(hold, J)
    shoulder_z = (Tm @ Vector((0, 0, S["torso_len"]))).z
    grip = p + d * .16 + Vector((0, 0, -.11))
    cane_hand = Vector((.37, -.16, .96)) + J["offset"]
    cane_dir = unit(.08, -.12 - .1 * J["walk"], -1)
    if frame in ("aim", "fire"):
        cane_hand, cane_dir = Vector((.34, -.46, 1.30)), unit(.12, -.9, .32)
    if frame == "pain":
        cane_hand, cane_dir = Vector((.5, -.1, shoulder_z + .12)), unit(.5, -.2, .8)
    hands = {"R": grip, "L": cane_hand}
    if J["dead"]:
        hands = flung(J, S, .56)
    else:
        limb(p, p + d * .47, .03, .195, gold, caps=False, seg=30)
        disc(p + d * .472, d, .205, .014, gold)
        disc(p + d * .482, d, .178, .006, horn_in)
        limb(p - d * .03, p, .04, .03, gold, caps=False)
        limb(p + d * .16, grip, .02, .02, black)
        if frame == "fire":
            wave = mat(255, 226, 110, emit=2.2)
            for k, radius in enumerate((.25, .34, .44)):
                ring(p + d * (.60 + k * .16), d, radius, .011, wave, n=26)
        limb(cane_hand - cane_dir * .12, cane_hand + cane_dir * .86, .017, .013, black)
        ball(cane_hand - cane_dir * .14, .036, gold)

    def sleeve(tag, sh, el, hand):
        ball(sh, .105, coat)
        limb(sh, el, .092, .076, coat)
        limb(el, el.lerp(hand, .8), .076, .062, coat)
        limb(el.lerp(hand, .70), el.lerp(hand, .84), .068, .068, black, caps=False)
        ring(el.lerp(hand, .72), hand - el, .068, .008, gold, n=12)
        ball(hand, (.062, .062, .066), glove)

    arms(S, J, hands, sleeve, (glove, .054))
    legs(S, J, stripe, (.118, .096, .078), black, boot_top=.5)


# ---------------------------------------------------------------- the rest of the cast
AVG = dict(lean=.06, hip_h=.88, hip_w=.11, stance=.17, stride=.21, ankle=.075, thigh=.42, shin=.41,
           torso_len=.52, neck=.15, head_fwd=-.035, sw=.22, upper=.30, fore=.28, boot=.058, bow=.14,
           depth=.17, gut=.2, limb=(.086, .07, .058), arm=(.064, .054, .043), canvas=(1.6, 1.96), px=158)
BIG = dict(AVG, hip_h=.95, hip_w=.15, stance=.22, thigh=.455, shin=.445, torso_len=.60, neck=.17, sw=.32,
           upper=.34, fore=.32, boot=.07, depth=.24, gut=.5, limb=(.125, .10, .084), arm=(.095, .08, .064),
           canvas=(2.1, 2.26), px=172)
TWO = {"ready": ((-.23, -.31, -.36), (.78, -.34, .46)), "aim": ((-.22, -.34, -.15), (.46, -1, 0)),
       "fire": ((-.22, -.30, -.12), (.46, -1, .13)), "recover": ((-.21, -.33, -.26), (.5, -.7, .12)),
       "pain": ((-.44, -.16, -.30), (-.3, -.3, .9)), "fidget": ((-.32, -.16, -.48), (.1, -.5, -.85))}
ONE = {"ready": ((-.29, -.19, -.54), (.1, -.8, -.5)), "aim": ((-.36, -.50, -.09), (.3, -1, 0)),
       "fire": ((-.36, -.45, -.02), (.3, -1, .26)), "recover": ((-.27, -.39, -.27), (.2, -.9, -.2)),
       "pain": ((-.42, -.1, -.17), (-.4, -.2, .9))}
THROW = {"ready": ((-.30, -.14, -.50), (0, -.3, 1)), "aim": ((-.40, .14, .26), (.1, .5, .85)),
         "fire": ((-.14, -.50, .0), (.1, -1, -.2)), "recover": ((-.2, -.4, -.3), (0, -.8, -.5)),
         "pain": ((-.42, -.1, -.17), (-.4, -.2, .9))}
MEGA = {"ready": ((-.34, -.2, -.38), (-.3, -.6, .75)), "aim": ((-.10, -.21, .07), (-.36, -.93, -.04)),
        "fire": ((-.10, -.19, .10), (-.36, -.93, .06)), "recover": ((-.27, -.31, -.18), (-.3, -.8, .4)),
        "pain": ((-.5, -.1, -.22), (-.5, -.2, .85))}
SAW = dict(TWO, ready=((-.2, -.3, -.42), (.7, -.5, .2)), aim=((-.18, -.3, -.2), (.3, -.8, .5)),
           fire=((-.15, -.42, -.25), (.25, -1, -.1)))
CHAIN = {"ready": ((-.30, -.12, -.46), (0, 0, -1)), "aim": ((-.26, -.05, .38), (1, 0, 0)),
         "fire": ((-.16, -.50, -.05), (.55, -.6, -.6)), "recover": ((-.22, -.38, -.3), (.3, -.4, -.85)),
         "pain": ((-.42, -.1, -.17), (-.2, -.2, -.9))}
CLAW = {"ready": ((-.30, -.16, -.50), (0, -1, 0)), "aim": ((-.30, -.22, -.05), (0, -1, 0)),
        "fire": ((-.36, -.34, -.24), (0, -1, 0)), "recover": ((-.3, -.25, -.4), (0, -1, 0)),
        "pain": ((-.42, -.1, -.1), (0, -1, 0))}


def hold(table, J, S):
    frame = J["frame"]
    g, d = table[frame if frame in table else "ready"]
    g = Vector(g) + Vector((0, 0, S["hip_h"] + S["torso_len"] + .018 * J["walk"])) + J["offset"]
    return g, unit(*d)


def flung(J, S, reach):
    zs = (J["torso"] @ Vector((0, 0, S["torso_len"]))).z
    stage = J["stage"]
    if stage == 5:
        return {"R": Vector((-reach, 0, zs - .15)), "L": Vector((reach - .02, 0, zs - .22))}
    up = (.02, .22, .32, .22, .04)[stage]
    fwd = (-.14, -.08, -.20, -.32, -.26)[stage]
    out = reach * (.72, 1., .9, .8, .95)[stage]
    return {"R": Vector((-out + .04, fwd, zs + up + .05)), "L": Vector((out - .06, fwd + .05, zs + up - .07))}


def head(Hm, C, J):
    frame = J["frame"]
    skin = mat(*C.get("skin", (186, 122, 92)), .75, grime=.42)
    hair = mat(*C.get("hair", (62, 46, 32)), .95)
    eyes, hat = C.get("eyes", "normal"), C.get("hat", "none")
    hc = mat(*C.get("hat_c", (84, 80, 60)), .9)
    band = mat(40, 30, 24, .9)
    fwd = (Hm.to_3x3() @ Vector((0, -1, 0))).normalized()
    wide = frame in ("pain", "fire") or J["dead"]
    if eyes == "alien":
        ball((0, .02, .06), (.15, .165, .15), skin, Hm)
        ball((0, -.03, -.07), (.10, .11, .11), skin, Hm)
        ball((0, -.055, -.15), (.05, .055, .045), skin, Hm)
        for s in (-1, 1):
            ball((s * .072, -.112, -.012), (.078, .038, .05), mat(8, 10, 12, .08, grime=0), Hm, (0, s * .62, 0))
        limb((-.028, -.118, -.125), (.028, -.118, -.125), .008, .008, band, Hm)
    elif eyes == "mask":
        sack = mat(*C.get("mask_c", (160, 146, 112)), .95)
        ball((0, 0, -.01), (.125, .135, .16), sack, Hm)
        ball((0, -.06, -.11), (.085, .09, .08), sack, Hm)
        for s in (-1, 1):
            ball((s * .046, -.123, .03), (.024, .014, .02), BLACK(), Hm)
        limb((-.04, -.135, -.07), (.04, -.135, -.075), .012, .012, band, Hm)
        ball((0, -.01, -.15), (.10, .11, .028), band, Hm)
    elif eyes == "visor":
        shell = mat(*C.get("mask_c", (130, 84, 50)), .5, .7, grime=.4)
        ball((0, 0, 0), (.13, .14, .15), shell, Hm)
        ball((0, -.03, -.10), (.11, .11, .07), shell, Hm)
        box((0, -.128, .028), (.16, .03, .026), mat(255, 176, 70, emit=1.6 if frame in ("aim", "fire") else .9), Hm)
        for s in (-1, 1):
            ball((s * .09, -.115, -.05), .014, BRASS(), Hm)
    else:
        ball((0, 0, 0), (.11, .12, .13), skin, Hm)
        ball((0, -.02, -.07), (.10, .105, .085), skin, Hm)
        ball((0, -.128, -.01), (.03, .04, .035), mat(184, 108, 88, .7, grime=.3), Hm)
        ball((0, -.122, -.075), (.036, .016, .026 if wide else .012), MOUTH(), Hm)
        for s in (-1, 1):
            ball((s * .112, .01, 0), (.02, .03, .04), skin, Hm)
        if eyes in ("normal", "glasses"):
            for s in (-1, 1):
                ball((s * .045, -.106, .03), .016, WHITE(), Hm)
                ball((s * .045, -.117, .03), .009, BLACK(), Hm)
                limb((s * .08, -.112, .06), (s * .015, -.125, .046), .013, .013, hair, Hm)
                if eyes == "glasses":
                    ring((s * .045, -.124, .03), (0, 1, 0), .028, .005, mat(150, 150, 150, .4, .8, grime=.1), n=12, M=Hm)
        elif eyes == "goggles":
            ball((0, 0, .03), (.114, .124, .022), band, Hm)
            for s in (-1, 1):
                c = Hm @ Vector((s * .05, -.112, .03))
                disc(c, fwd, .042, .04, BRASS())
                disc(c + fwd * .006, fwd, .031, .04, mat(20, 26, 28, .1, grime=0))
        elif eyes == "shades":
            limb((-.085, -.115, .032), (.085, -.115, .032), .024, .024, BLACK(), Hm)
        style = C.get("beard", "none")
        bc = mat(*C.get("beard_c", C.get("hair", (62, 46, 32))), .95)
        if style in ("full", "long"):
            ball((0, -.055, -.105), (.105, .092, .10), bc, Hm)
            for s in (-1, 1):
                ball((s * .095, -.02, -.04), .045, bc, Hm)
        if style == "long":
            limb((0, -.06, -.10), (0, -.11, -.36), .085, .02, bc, Hm)
        if style in ("full", "long", "moustache"):
            for s in (-1, 1):
                ball((s * .038, -.128, -.05), (.044, .022, .02), bc, Hm)
        if style == "stubble":
            ball((0, -.024, -.076), (.103, .107, .086), mat(*[v * .72 for v in C.get("skin", (186, 122, 92))], .9), Hm)
        if hat != "hood" and C.get("hair_show", True):
            ball((0, .032, .015), (.113, .116, .125), hair, Hm)
    if hat == "cap":
        ball((0, .005, .06), (.118, .126, .095), hc, Hm)
        ball((0, -.16, .055), (.09, .09, .013), hc, Hm, (-.16, 0, 0))
        if C.get("cap_star"):
            star((0, -.128, .085), .034, mat(200, 204, 208, .4, .7, grime=.1), Hm)
    elif hat in ("brim", "straw"):
        wide_brim = .23 if hat == "straw" else .19
        ball((0, 0, .07), (wide_brim, wide_brim + .01, .017), hc, Hm, (.08, .1, 0))
        ball((0, .01, .12), (.112, .12, .09), hc, Hm)
        ball((0, .01, .088), (.116, .124, .024), band, Hm)
    elif hat == "boater":
        ball((0, 0, .075), (.17, .17, .012), hc, Hm)
        limb((0, 0, .075), (0, 0, .15), .112, .112, hc, Hm, caps=False, seg=24)
        limb((0, 0, .08), (0, 0, .11), .115, .115, mat(*C.get("band_c", (112, 44, 60)), .9), Hm, caps=False, seg=24)
    elif hat == "bowler":
        ball((0, 0, .07), (.15, .16, .014), hc, Hm)
        ball((0, 0, .10), (.115, .122, .105), hc, Hm)
    elif hat == "hardhat":
        ball((0, 0, .055), (.135, .145, .11), hc, Hm)
        ball((0, -.1, .04), (.115, .10, .014), hc, Hm)
        limb((0, -.12, .14), (0, .12, .14), .02, .02, hc, Hm)
    elif hat == "hood":
        ball((0, .038, .015), (.136, .14, .16), hc, Hm)
        ball((0, .02, -.14), (.15, .14, .07), hc, Hm)
    elif hat == "flat":
        ball((0, -.01, .085), (.125, .14, .04), hc, Hm, (-.12, 0, 0))
        ball((0, -.13, .07), (.07, .05, .012), hc, Hm, (-.2, 0, 0))
    elif hat == "pipes":
        ball((0, 0, .09), (.12, .13, .08), hc, Hm)
        for s in (-1, 1):
            limb((s * .08, .05, .1), (s * .09, .06, .32), .028, .028, hc, Hm, caps=False)


def body(Tm, S, C, J):
    L, sw, g = S["torso_len"], S["sw"], S["gut"]
    skin = mat(*C.get("skin", (186, 122, 92)), .75, grime=.42)
    plaid = C.get("plaid")
    shirt = mat(*C["shirt"], .9, plaid=3.6 if plaid else 0.)
    pants = mat(*C["pants"], .92)
    front = -(.17 + .03 * g)
    ball((0, 0, .02), (sw * .82, .17 + .05 * g, .16), pants, Tm)
    ball((0, -.03 - .07 * g, .20), (sw * .85 + .06 * g, .16 + .10 * g, .19 + .03 * g), shirt, Tm)
    ball((0, -.01, L - .14), (sw * .98, .17 + .03 * g, .19), shirt, Tm)
    limb((-sw * .8, 0, L - .02), (sw * .8, 0, L - .02), .085, .085, shirt, Tm)
    limb((0, -.01, L), (0, S["head_fwd"], L + .11), .065, .06,
         mat(*C["shirt"], .9) if C.get("eyes") in ("visor",) else skin, Tm)
    seam = mat(*[v * .62 for v in C["pants"]], .95)
    for s_ in (-1, 1):
        box((s_ * sw * .42, .165 + .045 * g, .0), (.09, .03, .09), seam, Tm, (-.15, 0, 0))
    if not any(k in C for k in ("bib", "apron", "armor", "vest")):
        y0, y1 = -(.19 + .17 * g), front - .008
        button = mat(*[v * .5 for v in C["shirt"]], .7, grime=.2)
        for k in range(4):
            t = k / 3
            ball((0, y0 + (y1 - y0) * t - .012 * math.sin(t * math.pi), .2 + (L - .34) * t), .012, button, Tm)
        if "badge" not in C:
            box((-sw * .45, front - .004, L - .13), (.085, .02, .075), mat(*[v * .8 for v in C["shirt"]], .9), Tm)
    if C.get("bands"):
        hoop = mat(*C["bands"], .5, .7, grime=.4)
        ball((0, -.03 - .07 * g, .20), (sw * .87 + .06 * g, .168 + .10 * g, .028), hoop, Tm)
        ball((0, -.01, L - .14), (sw * 1.0, .178 + .03 * g, .024), hoop, Tm)
    if "belt" in C:
        ball((0, 0, .09), (sw * .86, .178 + .05 * g, .04), mat(*C["belt"], .6), Tm)
        box((0, -.18 - .05 * g, .09), (.06, .02, .05), BRASS(), Tm)
    if "bib" in C:
        bib = mat(*C["bib"], .92)
        ball((0, -.04 - .07 * g, .15), (sw * .87 + .06 * g, .168 + .10 * g, .2), bib, Tm)
        ball((0, .06, .2), (sw * .84, .15, .2), bib, Tm)
        ball((0, front + .05, L - .18), (.15, .08, .15), bib, Tm)
        for s in (-1, 1):
            ball((s * .11, front - .005, L - .07), .02, BRASS(), Tm)
            limb((s * .11, front, L - .08), (s * .14, -.02, L + .05), .026, .026, bib, Tm)
            limb((s * .14, -.02, L + .05), (s * .09, .16, L - .14), .026, .026, bib, Tm)
    if "braces" in C:
        br = mat(*C["braces"], .8)
        for s in (-1, 1):
            limb((s * .09, front - .01, .12), (s * .12, -.02, L + .055), .02, .02, br, Tm)
            limb((s * .12, -.02, L + .055), (s * .08, .15, .14), .02, .02, br, Tm)
    if "vest" in C:
        vest = mat(*C["vest"], .9, stripes=C.get("vest_stripes"))
        for s in (-1, 1):
            ball((s * sw * .6, -.025 - .03 * g, L - .24), (sw * .46, .19 + .06 * g, .27), vest, Tm)
        ball((0, .05, L - .22), (sw * .9, .16, .27), vest, Tm)
    if "coat" in C:
        coat = mat(*C["coat"], .9)
        for s in (-1, 1):
            ball((s * sw * .72, .01, .2), (sw * .5, .19 + .05 * g, .28), coat, Tm)
            if C.get("coat_long"):
                limb((s * .1, .03, .06), (s * .17, .05, -.34), .16, .13, coat, Tm)
        ball((0, .07, .24), (sw * .92, .19, .3), coat, Tm)
        dark = mat(*[v * .6 for v in C["coat"]], .9)
        limb((0, .262, L - .08), (0, .268, -.02), .009, .009, dark, Tm, caps=False)
        for s in (-1, 1):
            ball((s * .075, -.05, L + .03), (.065, .055, .034), coat, Tm, (0, s * .5, 0))
            limb((s * .05, front - .02, L - .03), (s * sw * .45, front - .035, L - .26), .024, .02, dark, Tm)
        for k in range(2):
            ball((sw * .5, front - .05 - .03 * g, L - .32 - k * .1), .016, BRASS(), Tm)
    if "apron" in C:
        ball((0, -.09 - .08 * g, .13), (sw * .72, .11 + .08 * g, .33), mat(*C["apron"], .9), Tm)
    if "armor" in C:
        plate = mat(*C["armor"], .5, .7, grime=.4)
        ball((0, -.06, L - .17), (sw * .82, .15, .21), plate, Tm)
        ball((0, -.05, .14), (sw * .6, .15, .12), plate, Tm)
    if C.get("collar"):
        for s in (-1, 1):
            ball((s * .05, -.1, L + .035), (.05, .04, .03), mat(*C["collar"], .8, grime=.2), Tm, (0, s * .5, 0))
    if "badge" in C:
        star((sw * .45, front - .035, L - .12), .05, mat(*C["badge"], .4, .8, grime=.2), Tm)
    if C.get("gauge"):
        for k, x in enumerate(C["gauge"]):
            c = Tm @ Vector((x, front - .04, L - .16 - .0 * k))
            n = (Tm.to_3x3() @ Vector((0, -1, 0))).normalized()
            disc(c, n, .055, .03, BRASS())
            disc(c + n * .004, n, .042, .03, mat(206, 198, 170, .5, grime=.2))
            limb(c + n * .02, c + n * .02 + Vector((.02, 0, .03)), .006, .006, BLACK(), caps=False)
    if "bandolier" in C:
        strap = mat(70, 48, 32, .8)
        a, b = Vector((-sw * .8, -.10, L - .03)), Vector((sw * .7, front - .06, .13))
        limb(a, b, .03, .03, strap, Tm)
        glass = mat(*C["bandolier"], .25, grime=.2)
        for k in range(4):
            p = a.lerp(b, .25 + k * .2) + Vector((0, -.045, 0))
            limb(p + Vector((0, 0, -.05)), p + Vector((0, 0, .05)), .026, .022, glass, Tm)
            limb(p + Vector((0, 0, .05)), p + Vector((0, 0, .09)), .011, .011, glass, Tm, caps=False)
    if "tanks" in C:
        tank = mat(*C["tanks"], .5, .7, grime=.45)
        tall = C.get("stacks", 0.)
        for s in (-1, 1):
            limb((s * .12, .22, .04), (s * .12, .22, L - .04), .09, .09, tank, Tm)
            limb((s * .12, .22, L - .04), (s * .13, .2, L + .14 + tall), .026 + tall * .05, .026 + tall * .07, tank, Tm, caps=False)
            if tall:
                disc(Tm @ Vector((s * .13, .2, L + .14 + tall)), (0, 0, 1), .06 + tall * .07, .03, tank)
            limb((s * .12, .12, L - .1), (s * .1, -.02, L + .05), .022, .022, BRASS(), Tm)
        limb((-.12, .22, .3), (.12, .22, .3), .03, .03, BRASS(), Tm)
    if C.get("pack"):
        box((0, .2, L - .26), (.26, .14, .34), mat(*C["pack"], .9), Tm)


def weapon(kind, g, d, J, C):
    """Draw what the right hand holds; return where the left hand goes (or None)."""
    frame = J["frame"]
    up = Vector((0, 0, 1))
    if kind in ("shotgun", "rifle"):
        side = d.cross(up).normalized() * .021
        for off in ((side, -side) if kind == "shotgun" else (side * 0,)):
            limb(g + d * .09 + off, g + d * .66 + off, .019, .019, STEEL(), caps=False)
        limb(g - d * .02, g + d * .13, .036, .034, DARK())
        limb(g - d * .03, g - d * .30 + Vector((0, 0, -.07)), .034, .05, WOOD())
        limb(g + d * .28, g + d * .46, .032, .03, WOOD())
        if frame == "fire":
            flash(g + d * .70, .21, (255, 168, 60))
        return g + d * .37
    if kind == "pistol":
        limb(g + d * .05, g + d * .30, .015, .014, STEEL(), caps=False)
        limb(g, g + d * .075, .03, .03, DARK(), caps=False)
        limb(g, g - d * .03 + Vector((0, 0, -.09)), .02, .024, WOOD())
        if frame == "fire":
            flash(g + d * .34, .17, (255, 168, 60))
        return None
    if kind == "blaster":
        metal = mat(120, 126, 132, .35, .9, grime=.3)
        glow = mat(120, 255, 140, emit=2.4)
        limb(g - d * .05, g + d * .24, .048, .042, metal)
        limb(g + d * .02, g + d * .02 + Vector((0, 0, -.11)), .024, .026, DARK())
        for k, radius in enumerate((.054, .042, .03)):
            disc(g + d * (.28 + k * .05), d, radius, .018, glow if frame in ("aim", "fire") else metal)
        ball(g + d * .43, .022, glow)
        if frame == "fire":
            flash(g + d * .48, .22, (130, 255, 120))
        return g + d * .16 + Vector((.04, 0, -.03)) if C.get("two_hand") else None
    if kind == "megaphone":
        horn = mat(150, 60, 44, .6, grime=.4)
        limb(g, g + d * .34, .024, .13, horn, caps=False, seg=26)
        disc(g + d * .345, d, .138, .012, BRASS())
        disc(g + d * .352, d, .118, .006, mat(60, 30, 20, .8))
        if frame == "fire":
            wave = mat(255, 226, 110, emit=2.2)
            for k, radius in enumerate((.18, .25, .32)):
                ring(g + d * (.46 + k * .14), d, radius, .009, wave, n=24)
        return None
    if kind == "chainsaw":
        body_c = mat(168, 92, 40, .6, grime=.5)
        limb(g - d * .06, g + d * .2, .075, .07, body_c)
        blade = T(g + d * .47) @ d.to_track_quat("Y", "Z").to_matrix().to_4x4()
        box((0, 0, 0), (.022, .56, .10), STEEL(), blade)
        ball((0, .28, 0), (.014, .05, .05), STEEL(), blade)
        box((0, 0, 0), (.03, .50, .05), DARK(), blade)
        ring(g + d * .10 + Vector((0, 0, .09)), d.cross(up), .06, .013, DARK(), n=10)
        if frame in ("aim", "fire"):
            for k in range(5):
                ball(g + d * (.3 + k * .1) + Vector((0, 0, .05)), .012, mat(255, 210, 120, emit=2.0))
        return g + d * .10 + Vector((.02, 0, .13))
    if kind in ("bottle", "football"):
        if frame in ("fire", "recover"):
            return None
        if kind == "bottle":
            glass = mat(*C.get("bandolier", (60, 96, 60)), .25, grime=.2)
            limb(g, g + d * .16, .03, .028, glass)
            limb(g + d * .16, g + d * .25, .012, .012, glass, caps=False)
            if frame == "aim":
                ball(g + d * .28, .02, mat(255, 170, 70, emit=2.2))
        else:
            leather = mat(110, 62, 36, .7)
            limb(g + d * .0, g + d * .09, .058, .02, leather)
            limb(g + d * .0, g - d * .09, .058, .02, leather)
            ring(g + d * .05, d, .042, .006, WHITE(), n=10)
            ring(g - d * .05, d, .042, .006, WHITE(), n=10)
        return None
    if kind == "chain":
        link = mat(60, 62, 66, .45, .85, grime=.4)
        if frame == "aim":
            other = Vector((-g.x, g.y, g.z))
            limb(g, other, .016, .016, link)
            limb(other, other + Vector((.1, .05, -.45)), .016, .016, link)
            return other
        pts = [g, g + d * .35 + Vector((.02, 0, -.06)), g + d * .7 + Vector((.06, -.05, -.02))]
        if frame == "fire":
            pts.append(g + d * 1.05 + Vector((.12, -.1, .1)))
        for a, b in zip(pts, pts[1:]):
            limb(a, b, .017, .017, link)
        ball(pts[-1], .04, link)
        return None
    if kind == "pipe":
        tube = mat(*C.get("pipe_c", (160, 124, 58)), .45, .85, grime=.4)
        limb(g - d * .1, g + d * .42, .04, .04, tube)
        disc(g + d * .43, d, .055, .03, tube)
        ring(g + d * .12 + Vector((0, 0, .07)), up, .045, .009, mat(140, 40, 34, .6), n=10)
        limb(g + d * .12, g + d * .12 + Vector((0, 0, .07)), .012, .012, DARK(), caps=False)
        if frame == "fire":
            flash(g + d * .5, .2, (236, 232, 214))
        return g + d * .26
    if kind == "sawgun":
        limb(g - d * .12, g + d * .34, .05, .045, DARK())
        limb(g + d * .1, g + d * .1 + Vector((0, 0, -.12)), .026, .028, WOOD())
        tilt = (up + d * .25).normalized()
        if frame != "fire" and frame != "recover":
            disc(g + d * .50, tilt, .21, .012, mat(150, 152, 150, .3, .9, grime=.35))
            disc(g + d * .50, tilt, .06, .03, BRASS())
            for k in range(12):
                a = k * math.tau / 12
                u = tilt.orthogonal().normalized()
                v = tilt.cross(u)
                ball(g + d * .50 + (u * math.cos(a) + v * math.sin(a)) * .215, .02, STEEL())
        if frame == "fire":
            flash(g + d * .52, .24, (255, 190, 90))
        return g + d * .22
    if kind == "cannon":
        copper = mat(150, 88, 50, .45, .8, grime=.45)
        limb(g - d * .15, g + d * .5, .078, .07, copper)
        disc(g + d * .51, d, .095, .05, BRASS())
        disc(g + d * .54, d, .06, .01, BLACK())
        limb(g - d * .15, g - d * .3 + Vector((.1, .2, .05)), .035, .035, DARK())
        if frame == "fire":
            flash(g + d * .6, .28, (255, 170, 70))
        return g + d * .28
    return None


def person(S, frame):
    C = S["look"]
    J = skeleton(S, frame)
    Tm, Hm = J["torso"], J["head"]
    body(Tm, S, C, J)
    head(Hm, C, J)
    skin = mat(*C.get("skin", (186, 122, 92)), .75, grime=.42)
    sleeve_c = mat(*C.get("coat", C["shirt"]), .9, plaid=13.0 if C.get("plaid") and "coat" not in C else 0.)
    glove = mat(*C["gloves"], .85) if "gloves" in C else skin
    kind = C["weapon"]
    table = C["hold"]
    g, d = hold(table, J, S)
    zs = (Tm @ Vector((0, 0, S["torso_len"]))).z
    rest = Vector((S["sw"] + .08, -.10, S["hip_h"] + .02 - .02 * J["walk"])) + J["offset"]
    hands = {"R": g, "L": rest}
    if J["dead"]:
        hands = flung(J, S, S["sw"] + S["upper"] * .9)
    else:
        if kind == "megaphone":
            hands["R"] = g + d * .12 + Vector((0, 0, -.08))
        if kind == "claw":
            hands["L"] = Vector((-g.x, g.y, g.z))
            if frame == "fire":
                at = Hm @ Vector((0, -.2, -.07))
                flash(at, .16, (190, 220, 150))
                ball(at + Vector((0, -.05, -.02)), .04, mat(206, 214, 170, emit=1.2))
        else:
            left = weapon(kind, g, d, J, C)
            if left is not None:
                hands["L"] = left
        if kind == "football" and frame != "pain":
            radio = hands["L"] = Tm @ Vector((S["sw"] * .9, -.24, .22))
            box(radio + Vector((0, -.02, .05)), (.07, .04, .13), DARK())
            limb(radio + Vector((.02, -.02, .11)), radio + Vector((.03, -.02, .30)), .005, .005, STEEL(), caps=False)
        if kind == "bottle" and frame != "pain":
            glass = mat(*C.get("bandolier", (60, 96, 60)), .25, grime=.2)
            limb(rest, rest + Vector((0, 0, .17)), .03, .026, glass)
        if frame == "pain":
            hands["L"] = Vector((S["sw"] + .22, -.12, zs + .14))
        if frame == "fidget":
            hands["L"] = Hm @ Vector((.12, -.09, .13))
    r0, r1, r2 = S["arm"]
    mode = C.get("sleeve", "long")

    def sleeve(tag, sh, el, hand):
        cloth = skin if mode == "bare" else sleeve_c
        ball(sh, r0 * 1.15, cloth)
        limb(sh, el, r0, r1, cloth)
        cut = .25 if mode == "rolled" else .82
        if mode == "bare":
            limb(el, hand, r1, r2, skin)
        else:
            limb(el, el.lerp(hand, cut), r1, r1 * (1 - cut) + r2 * cut + .004, cloth)
            limb(el.lerp(hand, cut - .04), hand, r1 * (1 - cut) + r2 * cut - .004, r2 * .9, skin if mode == "rolled" else glove)
        ball(hand, r2 * 1.12, glove)
        if "trim" in C:
            for t in (.5, .62):
                ring(sh.lerp(el, t), el - sh, r0 * (1 - t) + r1 * t + .004, .008, mat(*C["trim"], .8, grime=.2), n=12)
        if "armor" in C:
            ball(sh + Vector((0, 0, .03)), r0 * 1.4, mat(*C["armor"], .5, .7, grime=.4))
        if C.get("eyes") == "mask" or C.get("claws"):
            reach = (hand - el).normalized()
            for k in (-1, 0, 1):
                limb(hand, hand + reach * .09 + Vector((k * .03, 0, 0)), .013, .008, glove)

    arms(S, J, hands, sleeve, (glove, r2))
    legs(S, J, mat(*C["pants"], .92), S["limb"], mat(*C.get("boots", (58, 44, 34)), .8),
         boot_top=C.get("boot_top", .26))
    if "armor" in C or C.get("kneepads"):
        pad = mat(*C.get("armor", (150, 120, 60)), .5, .7, grime=.4)
        for tag in ("R", "L"):
            k = J["knee" + tag]
            ball((k.x, k.y - .04, k.z), (S["limb"][1] * .9, .05, S["limb"][1] * 1.1), pad)


def cast(base, **look):
    over = {k: look.pop(k) for k in list(look) if k in base or k == "fidget_head"}
    return dict(base, **over, look=look)


CLONE = cast(AVG, gut=.25, shirt=(96, 104, 62), plaid=1, bib=(66, 78, 108), pants=(66, 78, 108), sleeve="rolled",
             hat="straw", hat_c=(166, 138, 82), beard="stubble", weapon="rifle", hold=TWO)
ALIEN = cast(AVG, bands=(40, 42, 38), belt=(34, 34, 32), hip_h=.92, thigh=.44, shin=.43, canvas=(1.6, 2.0), skin=(112, 128, 92), eyes="alien",
             shirt=(58, 62, 54), pants=(52, 56, 50), armor=(98, 106, 94), gloves=(112, 128, 92), boots=(38, 38, 36),
             boot_top=.5, weapon="blaster", hold=ONE, two_hand=0)
BARKER = cast(AVG, gut=.5, px=164, shirt=(176, 166, 140), vest=(118, 44, 58), vest_stripes=(5.0, (170, 150, 96)),
              pants=(70, 62, 48), braces=(40, 34, 30), hat="boater", hat_c=(176, 156, 104), beard="moustache",
              hair=(40, 32, 26), sleeve="rolled", weapon="megaphone", hold=MEGA)
MILLHAND = cast(AVG, gut=.4, sw=.25, px=164, limb=(.098, .08, .066), arm=(.074, .062, .05), shirt=(172, 142, 48),
                coat=(172, 142, 48), coat_long=1, pants=(58, 68, 84), hat="hood", hat_c=(172, 142, 48), beard="full",
                hair=(50, 38, 28), gloves=(80, 60, 40), boots=(36, 36, 34), boot_top=.5, weapon="chainsaw", hold=SAW)
BOILERBACK = cast(AVG, bands=(70, 54, 40), gut=.45, sw=.26, px=166, canvas=(1.7, 2.0), limb=(.098, .08, .066), arm=(.074, .062, .05),
                  shirt=(90, 108, 80), pants=(78, 92, 72), tanks=(112, 114, 104), gauge=(.0,), eyes="goggles",
                  hat="flat", hat_c=(64, 50, 38), beard="stubble", gloves=(70, 54, 40), kneepads=1,
                  weapon="pipe", hold=TWO)
CHALK = cast(AVG, lean=.26, gut=.05, hip_w=.09, sw=.19, upper=.34, fore=.33, px=166, limb=(.07, .056, .046),
             arm=(.05, .042, .034), skin=(190, 182, 158), eyes="mask", mask_c=(168, 156, 124), shirt=(182, 172, 144),
             pants=(150, 140, 116), sleeve="bare", boots=(126, 116, 96), weapon="claw", hold=CLAW)
DEPUTY = cast(AVG, gut=.35, px=152, shirt=(150, 126, 86), pants=(52, 64, 50), belt=(30, 26, 24), badge=(186, 146, 58),
              hat="brim", hat_c=(58, 70, 54), beard="moustache", hair=(70, 50, 34), collar=(150, 126, 86),
              weapon="pistol", hold=ONE)
TOSSER = cast(AVG, gut=.15, px=164, shirt=(112, 48, 54), plaid=1, pants=(86, 76, 56), bandolier=(64, 98, 62),
              hat="cap", hat_c=(84, 80, 60), beard="stubble", sleeve="rolled", weapon="bottle", hold=THROW)
CHAINHAND = cast(AVG, gut=.35, sw=.25, px=152, limb=(.096, .078, .064), arm=(.076, .064, .05), shirt=(62, 104, 100),
                 pants=(84, 60, 40), braces=(60, 44, 32), hat="flat", hat_c=(170, 150, 98), eyes="shades",
                 beard="moustache", hair=(150, 124, 70), sleeve="rolled", gloves=(70, 54, 40), boot_top=.4,
                 weapon="chain", hold=CHAIN)
VALVERAT = cast(AVG, lean=.30, hip_h=.56, thigh=.27, shin=.26, torso_len=.40, neck=.13, sw=.21, upper=.25, fore=.24,
                stride=.15, gut=.3, canvas=(1.5, 1.38), px=118, shirt=(104, 84, 56), coat=(104, 84, 56),
                pants=(60, 66, 72), eyes="goggles", hat="flat", hat_c=(70, 54, 40), tanks=(124, 96, 52),
                beard="stubble", gloves=(60, 46, 36), weapon="pipe", hold=TWO)
FOREMAN = cast(BIG, bandolier=(150, 152, 150), shirt=(92, 96, 88), coat=(56, 98, 102), coat_long=1, pants=(72, 76, 72), hat="hardhat",
               hat_c=(132, 134, 126), eyes="goggles", beard="full", hair=(120, 118, 110), gloves=(70, 54, 40),
               kneepads=1, belt=(40, 32, 26), boot_top=.45, weapon="sawgun", hold=TWO)
BARON = cast(BIG, bands=(168, 132, 62), gut=.8, sw=.36, canvas=(2.3, 2.42), px=176, limb=(.135, .108, .09), shirt=(150, 90, 52),
             pants=(70, 72, 68), armor=(150, 90, 52), tanks=(140, 84, 48), stacks=.32, gauge=(-.1, .1), eyes="visor",
             mask_c=(140, 86, 50), hat="pipes", hat_c=(140, 84, 48), gloves=(60, 46, 36), boot_top=.5,
             weapon="cannon", hold=TWO)
JERRY = cast(AVG, trim=(206, 204, 196), hip_h=.92, thigh=.44, shin=.43, torso_len=.56, sw=.27, gut=.55, canvas=(1.8, 2.08), px=184,
             limb=(.10, .082, .066), arm=(.078, .066, .052), skin=(204, 150, 124), shirt=(44, 58, 88),
             coat=(44, 58, 88), pants=(62, 72, 94), collar=(206, 204, 196), badge=(196, 200, 206), belt=(30, 26, 24),
             hat="cap", hat_c=(40, 54, 86), cap_star=1, hair=(212, 210, 202), eyes="glasses", boots=(34, 30, 28),
             weapon="football", hold=THROW)


def maker(S):
    return lambda frame: person(S, frame)


# ---------------------------------------------------------------- creatures
SKEETER = dict(canvas=(1.0, .76), px=84)
SAUCER = dict(canvas=(2.0, .86), px=62)
CRAWLER = dict(canvas=(1.5, .96), px=80)
LANTERN = dict(canvas=(1.4, 1.1), px=84)
FLYER = [-1, 0, 1, "aim", "fire", "pain"]
GROUND = [-1, 0, 1, "aim", "fire", "pain", "die_0", "die_1", "down"]


def skeeter(frame):
    phase = frame if isinstance(frame, int) else 0
    hide = mat(100, 86, 44, .7)
    dark = mat(44, 36, 26, .7)
    tilt = R(.5, 0, .35) if frame == "pain" else R(-.25 if frame in ("aim", "fire") else 0, 0, 0)
    M = T((0, 0, .40)) @ tilt
    ball((0, 0, 0), (.075, .095, .075), hide, M)
    limb((0, .06, -.01), (0, .26, -.14), .062, .018, mat(150, 124, 52, .7, stripes=(14.0, (40, 32, 24))), M)
    ball((0, -.11, .02), .052, dark, M)
    for s in (-1, 1):
        ball((s * .036, -.14, .035), .024, mat(150, 36, 30, .3, grime=.1), M)
        flap = (-.55, 0., .55)[phase + 1] if frame != "pain" else -.9
        ball((s * .2, .02, .09 + .08 * flap), (.19, .06, .008), mat(176, 180, 172, .5, grime=.25), M, (0, -s * (.25 + flap), s * .3))
        for k in range(3):
            root = Vector((s * .05, -.04 + k * .05, -.05))
            knee = root + Vector((s * .13, -.03 + k * .03, -.02))
            limb(root, knee, .009, .008, dark, M)
            limb(knee, knee + Vector((s * .04, .02, -.2 - .03 * k)), .008, .005, dark, M)
    reach = .34 if frame == "fire" else .26 if frame == "aim" else .2
    limb((0, -.15, 0), (0, -.15 - reach * .7, -reach * .7), .012, .004, dark, M)
    if frame == "fire":
        ball((0, -.15 - reach * .7, -reach * .7), .022, mat(200, 40, 36, emit=1.5), M)


def saucer(frame):
    phase = frame if isinstance(frame, int) else 0
    hot = frame in ("aim", "fire")
    hull = mat(124, 126, 114, .4, .8, grime=.5)
    trim = mat(64, 72, 70, .5, .7, grime=.4)
    M = T((0, 0, .42)) @ (R(0, .22, 0) if frame == "pain" else R(0, 0, 0))
    ball((0, 0, 0), (.92, .92, .12), hull, M)
    ball((0, 0, -.01), (.95, .95, .035), trim, M)
    ball((0, 0, .08), (.38, .38, .24), mat(70, 104, 112, .15, .3, grime=.3), M)
    ball((0, 0, -.1), (.42, .42, .1), trim, M)
    ball((0, 0, -.18 if hot else -.14), (.2, .2, .07), mat(255, 150, 70, emit=2.2) if hot else trim, M)
    for i in range(14):
        a = i * math.tau / 14
        lit = hot or (frame != "pain" and i % 3 == phase + 1)
        ball((.9 * math.cos(a), .9 * math.sin(a), .025), .04, mat(255, 196, 96, emit=2.0) if lit else BRASS(), M)
    if frame == "fire":
        flash(M @ Vector((0, -.25, -.26)), .2, (255, 160, 70))


def crawler(frame):
    phase = frame if isinstance(frame, int) else 0
    down = frame == "down"
    flesh = mat(140, 96, 70, .7, grime=.5)
    shell = mat(104, 68, 50, .6, grime=.5)
    dying = frame in ("die_0", "die_1")
    rise = .12 if frame == "aim" else .06 if frame == "fire" else -.05 if frame == "pain" else 0.
    if frame == "die_0":
        rise = .22
    M = T((0, -.1 if frame == "fire" else 0, .3 + rise))
    if frame == "die_0":
        M = M @ R(.5, .35, 0)
    if frame == "die_1":
        M = T((0, 0, .36)) @ R(math.pi * .62, 0, .2)
        down = True
    if frame == "down":
        M = T((0, 0, .2)) @ R(math.pi, 0, .3)
    if frame == "aim":
        M = M @ R(-.35, 0, 0)
    ball((0, 0, 0), (.3, .27, .16), shell, M)
    ball((0, -.1, -.04), (.22, .2, .12), flesh, M)
    for s in (-1, 1):
        ball((s * .1, -.24, .03), .05, mat(10, 10, 12, .08, grime=0), M)
        open_jaw = .1 if frame in ("fire", "aim") else .03
        limb((s * .05, -.26, -.06), (s * (.05 + open_jaw), -.4, -.1), .03, .008, mat(206, 190, 150, .5), M)
        for k in range(3):
            y = -.14 + k * .15
            swing = .09 * phase * (1 if (k + (s > 0)) % 2 else -1)
            root = M @ Vector((s * .24, y, 0))
            if down:
                foot = root + Vector((s * .12, 0, .3))
                knee = root + Vector((s * .25, 0, .2))
            else:
                spread = .72 if frame in ("pain", "die_0") else .6
                lift = .25 if (frame == "aim" and k == 0) else 0.
                foot = Vector((s * spread, y + swing - (.1 if frame == "fire" else 0), .03 + lift))
                knee = Vector((s * .46, y + swing * .5, .5 + rise * .5))
            limb(root, knee, .04, .03, flesh)
            limb(knee, foot, .03, .012, shell)
    if frame == "fire":
        flash(M @ Vector((0, -.42, -.05)), .15, (130, 255, 120))


def lantern(frame):
    phase = frame if isinstance(frame, int) else 0
    hot = frame in ("aim", "fire")
    down = frame in ("down", "die_1")
    hide = mat(72, 94, 70, .65, grime=.5)
    iron = mat(46, 46, 44, .5, .7, grime=.4)
    M = T((0, 0, .68)) @ (R(0, .3, 0) if frame == "pain" else R(.3, -.45, 0) if frame == "die_0" else R(0, 0, 0))
    if frame == "die_1":
        M = T((0, 0, .46)) @ R(.2, .95, 0)
    elif down:
        M = T((0, 0, .28)) @ R(0, 1.4, 0)
    ball((0, 0, 0), (.3, .28, .3), hide, M)
    ball((0, 0, .2), (.2, .19, .16), hide, M)
    glow = mat(255, 176, 70, emit=0 if down else 2.6 if hot else 1.0) if not down else mat(90, 70, 40)
    ball((0, -.12, -.02), (.2, .17, .16), glow, M)
    for k in (-1, 0, 1):
        limb((k * .09, -.3, -.16), (k * .09, -.26, .13), .016, .016, iron, M)
    limb((-.18, -.25, .13), (.18, -.25, .13), .018, .018, iron, M)
    limb((-.18, -.27, -.16), (.18, -.27, -.16), .018, .018, iron, M)
    ring(M @ Vector((0, 0, .38)), (0, 1, 0), .07, .014, iron, n=12)
    if not down:
        for i, x in enumerate((-.14, 0, .14)):
            sway = .07 * phase * (1 if i % 2 else -1)
            a = M @ Vector((x, .02, -.27))
            b = a + Vector((sway, .03, -.2))
            limb(a, b, .03, .022, hide)
            limb(b, b + Vector((-sway * 1.4, 0, -.2)), .022, .008, hide)
    if frame == "fire":
        flash(M @ Vector((0, -.34, -.02)), .2, (255, 170, 70))


ACTORS = {"billy": (billy, BILLY, ("fidget",), None), "coot": (coot, COOT, ("fidget",), None),
          "boss": (boss, BOSS, (), None), "rudy": (rudy, RUDY, (), None),
          "clone": (maker(CLONE), CLONE, ("fidget",), None), "alien": (maker(ALIEN), ALIEN, (), None),
          "barker": (maker(BARKER), BARKER, (), None), "millhand": (maker(MILLHAND), MILLHAND, (), None),
          "boilerback": (maker(BOILERBACK), BOILERBACK, (), None),
          "chalk_spitter": (maker(CHALK), CHALK, (), None), "yard_deputy": (maker(DEPUTY), DEPUTY, (), None),
          "bottle_tosser": (maker(TOSSER), TOSSER, (), None), "chain_hand": (maker(CHAINHAND), CHAINHAND, (), None),
          "valve_rat": (maker(VALVERAT), VALVERAT, (), None), "foreman": (maker(FOREMAN), FOREMAN, (), None),
          "baron": (maker(BARON), BARON, (), None), "jerry": (maker(JERRY), JERRY, (), None),
          "skeeter": (skeeter, SKEETER, (), FLYER), "saucer": (saucer, SAUCER, (), FLYER),
          "crawler": (crawler, CRAWLER, (), GROUND), "lantern": (lantern, LANTERN, (), GROUND)}


# ---------------------------------------------------------------- stage
def stage():
    global ROOT
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 28
    scene.cycles.use_denoising = False
    scene.cycles.device = "CPU"
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("world")
    scene.world = world
    try:
        world.use_nodes = True
    except Exception:
        pass
    nt = world.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs[0].default_value = (.62, .60, .56, 1)
    bg.inputs[1].default_value = .50
    nt.links.new(bg.outputs[0], out.inputs[0])
    for name, travel, power, color in (("key", (.50, .58, -.70), 4.4, (1, .94, .84)),
                                       ("fill", (-.7, .55, -.25), .8, (.80, .86, 1)),
                                       ("rim", (-.35, -.75, -.55), 1.5, (1, .95, .85))):
        light = bpy.data.lights.new(name, "SUN")
        light.energy = power
        light.color = color
        light.angle = math.radians(6)
        ob = bpy.data.objects.new(name, light)
        ob.rotation_euler = Vector(travel).to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(ob)
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    camera = bpy.data.objects.new("cam", cam)
    scene.collection.objects.link(camera)
    scene.camera = camera
    ROOT = bpy.data.objects.new("root", None)
    scene.collection.objects.link(ROOT)
    return scene, camera


def clear():
    doomed = [ob for ob in bpy.data.objects if ob.parent is ROOT]
    meshes = [ob.data for ob in doomed]
    bpy.data.batch_remove(doomed)
    bpy.data.batch_remove([me for me in meshes if me.users == 0])


def frames_for(extra):
    walk = ["w0", "w1", "w2", "w3"]
    stems = [0, *walk, "aim", "fire", "pain", "recover", *["die_%d" % k for k in range(5)], "down", *extra]
    stems += [(name, step) for name, _ in TURNS for step in (0, *walk)]
    return stems


def stem_of(item):
    return "%s_%s" % item if isinstance(item, tuple) else str(item)


def main():
    scene, camera = stage()
    os.makedirs(OUT, exist_ok=True)
    meta = {}
    for kind in KINDS:
        make, S, extra, own = ACTORS[kind]
        width, height = S["canvas"]
        scale = S["px"] / height * SS
        wanted = list(own) if own else frames_for(extra)
        if FRAMES != "all":
            wanted = [f for f in wanted if stem_of(f) in FRAMES.split(",")]
        meta[kind] = {"size": [round(width * S["px"] / height), S["px"]], "walk": not own}
        for item in wanted:
            clear()
            yaw = 0.
            frame = item
            if isinstance(item, tuple):
                yaw = math.radians(dict(TURNS)[item[0]])
                frame = item[1]
            make(frame)
            root = R(0, 0, yaw)
            pitch = math.radians(4)
            w, h = width, height
            if own:
                if frame == "down":
                    pitch = math.radians(20)
            elif isinstance(frame, str) and frame.startswith("die_"):
                root = R((-.10, -.36, -.74, -1.12, -1.42)[int(frame[4:])], 0, 0)
            elif frame == "down":
                root = R(0, 0, math.pi / 2) @ T((0, 0, S["depth"])) @ R(-math.pi / 2, 0, 0)
                pitch = math.radians(26)
                w, h = 2.9, 1.5
            ROOT.matrix_basis = root
            scene.render.resolution_x = round(w * scale)
            scene.render.resolution_y = round(h * scale)
            camera.data.ortho_scale = max(w, h)
            look = Vector((0, 0, h / 2 - .04)) if (frame != "down" or own) else Vector((0, 0, .25))
            back = Vector((0, -math.cos(pitch), math.sin(pitch)))
            camera.location = look + back * 12
            camera.rotation_euler = (math.pi / 2 - pitch, 0, 0)
            scene.render.filepath = os.path.join(OUT, "%s_%s.png" % (kind, stem_of(item)))
            bpy.ops.render.render(write_still=True)
    path = os.path.join(OUT, "meta.json")
    old = json.load(open(path)) if os.path.exists(path) else {}
    old.update(meta)
    json.dump(old, open(path, "w"))


main()
