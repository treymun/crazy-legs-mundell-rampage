"""Model and render the first-person weapons that are not photographed plates.

    blender -b -P scripts/blender/weapon_views.py -- <out dir> <names|all>

Writes <name>.png (1280x896, transparent) and views.json with where each
weapon's grip and foremost point landed. godot/tools/art/build_weapon_views.gd lays the
photographed hands over them and cuts the animation cels.

The crowbar, revolver and shotgun in the game are photographs, hands included.
Every weapon here is built to be held by one of those same hands, so each rig
reproduces the camera of one plate (see RIGS) and its weapons follow that
plate's layout:
  pistol  the top of the grip at the origin, body above and ahead (revolver)
  long    the breech's top rear at the origin, a fore-end to cup (shotgun)
  bar     a handle along +Y through the origin (crowbar)
  carry   something round, centred on the origin, held from below
A new weapon is a builder function and one line in WEAPONS.
"""
import json
import math
import os
import sys

import bmesh
import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Euler, Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:]
OUT = os.path.abspath(ARGS[0])
WANT = ARGS[1].split(",") if len(ARGS) > 1 and ARGS[1] != "all" else None
MATS = {}
PARTS = []


def lin(c):
    c /= 255.0
    return c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4


def pbr(key, rgb, rough=.5, metal=0., wear=None, grain=None, bump=.25, scale=22., emit=0., blotch=None):
    """A worn surface: two scales of dirt, scuffed roughness, pale wear on raised edges."""
    if key in MATS:
        return MATS[key]
    m = bpy.data.materials.new(key)
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    base = (lin(rgb[0]), lin(rgb[1]), lin(rgb[2]), 1)
    bsdf.inputs["Base Color"].default_value = base
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit:
        bsdf.inputs["Emission Color"].default_value = base
        bsdf.inputs["Emission Strength"].default_value = emit
        MATS[key] = m
        return m
    coord = nt.nodes.new("ShaderNodeTexCoord")
    source = None

    def mix(kind, fac, a, b):
        node = nt.nodes.new("ShaderNodeMix")
        node.data_type = "RGBA"
        node.blend_type = kind
        for slot, value in ((0, fac), (6, a), (7, b)):
            if isinstance(value, (float, int, tuple)):
                node.inputs[slot].default_value = value
            else:
                nt.links.new(value, node.inputs[slot])
        return node.outputs[2]

    def noise(size, detail=4.0, stretch=None):
        node = nt.nodes.new("ShaderNodeTexNoise")
        node.inputs["Scale"].default_value = size
        node.inputs["Detail"].default_value = detail
        if stretch:
            mapping = nt.nodes.new("ShaderNodeMapping")
            mapping.inputs["Scale"].default_value = stretch
            nt.links.new(coord.outputs["Object"], mapping.inputs[0])
            nt.links.new(mapping.outputs[0], node.inputs["Vector"])
        else:
            nt.links.new(coord.outputs["Object"], node.inputs["Vector"])
        return node.outputs[0]

    source = base
    if grain:
        # Wood: long streaks of a second colour along the part's length.
        streak = noise(26., 6.0, (9., .6, 9.))
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = .38
        ramp.color_ramp.elements[1].position = .66
        nt.links.new(streak, ramp.inputs[0])
        source = mix("MIX", ramp.outputs[0], base, (lin(grain[0]), lin(grain[1]), lin(grain[2]), 1))
    if blotch:
        patch = noise(7., 1.0)
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = .44
        ramp.color_ramp.elements[1].position = .70
        nt.links.new(patch, ramp.inputs[0])
        soft = nt.nodes.new("ShaderNodeMath")
        soft.operation = "MULTIPLY"
        soft.inputs[1].default_value = .62
        nt.links.new(ramp.outputs[0], soft.inputs[0])
        source = mix("MIX", soft.outputs[0], source, (lin(blotch[0]), lin(blotch[1]), lin(blotch[2]), 1))
    source = mix("MULTIPLY", .55, source, noise(scale * .35))
    source = mix("MULTIPLY", .40, source, noise(scale * 3.))
    if wear:
        # Scuffs and rubbed patches: sparse, streaked along the part.
        edge = nt.nodes.new("ShaderNodeValToRGB")
        edge.color_ramp.elements[0].position = .60
        edge.color_ramp.elements[1].position = .78
        nt.links.new(noise(scale * .9, 5.0, (1., .22, 1.)), edge.inputs[0])
        scuff = nt.nodes.new("ShaderNodeMath")
        scuff.operation = "MULTIPLY"
        scuff.inputs[1].default_value = .55
        nt.links.new(edge.outputs[0], scuff.inputs[0])
        source = mix("MIX", scuff.outputs[0], source, (lin(wear[0]), lin(wear[1]), lin(wear[2]), 1))
    nt.links.new(source, bsdf.inputs["Base Color"])
    rough_noise = nt.nodes.new("ShaderNodeMapRange")
    rough_noise.inputs[3].default_value = max(.05, rough - .22)
    rough_noise.inputs[4].default_value = min(1., rough + .28)
    nt.links.new(noise(scale * 1.2), rough_noise.inputs[0])
    nt.links.new(rough_noise.outputs[0], bsdf.inputs["Roughness"])
    bumper = nt.nodes.new("ShaderNodeBump")
    bumper.inputs["Strength"].default_value = bump
    bumper.inputs["Distance"].default_value = .004
    nt.links.new(noise(scale * 4., 6.0), bumper.inputs["Height"])
    nt.links.new(bumper.outputs[0], bsdf.inputs["Normal"])
    MATS[key] = m
    return m


STEEL = lambda: pbr("steel", (22, 25, 32), .30, 1., wear=(120, 122, 126))
IRON = lambda: pbr("iron", (18, 18, 20), .5, 1., wear=(90, 86, 80))
RUST = lambda: pbr("rust", (98, 58, 38), .8, .6, wear=(140, 120, 100), blotch=(60, 44, 38))
WOOD = lambda: pbr("wood", (96, 54, 30), .5, 0., grain=(52, 28, 16), wear=(140, 100, 66), scale=14.)
PALE = lambda: pbr("pale", (150, 112, 70), .65, 0., grain=(104, 72, 42), scale=14.)
BRASS = lambda: pbr("brass", (156, 118, 50), .35, 1., wear=(210, 180, 110))
COPPER = lambda: pbr("copper", (150, 80, 46), .34, 1., wear=(214, 150, 110), blotch=(70, 110, 96))
RUBBER = lambda: pbr("rubber", (26, 26, 26), .75, 0.)
RED = lambda: pbr("red", (150, 40, 32), .7, 0., wear=(190, 150, 120))
PAPER = lambda: pbr("paper", (176, 150, 110), .9, 0.)


def T(v):
    return Matrix.Translation(Vector(v))


def R(rx=0., ry=0., rz=0.):
    return Euler((rx, ry, rz), "XYZ").to_matrix().to_4x4()


def place(bm, matrix, material, smooth=True, bevel=0.):
    if bevel:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=2, affect="EDGES")
    me = bpy.data.meshes.new("part")
    bm.to_mesh(me)
    bm.free()
    me.polygons.foreach_set("use_smooth", [True] * len(me.polygons))
    me.set_sharp_from_angle(angle=math.radians(40 if not smooth else 62))
    me.materials.append(material)
    ob = bpy.data.objects.new("part", me)
    bpy.context.scene.collection.objects.link(ob)
    ob.matrix_world = matrix
    PARTS.append(ob)
    return ob


def ball(c, r, material, M=None, rot=(0, 0, 0)):
    if isinstance(r, (int, float)):
        r = (r, r, r)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=40, v_segments=24, radius=1.0)
    matrix = T(c) @ R(*rot) @ Matrix.Diagonal((r[0], r[1], r[2], 1))
    return place(bm, (M @ matrix) if M is not None else matrix, material)


def rod(a, b, ra, rb, material, M=None, seg=40, round_ends=False):
    a, b = Vector(a), Vector(b)
    if M is not None:
        a, b = M @ a, M @ b
    d = b - a
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=ra, radius2=rb, depth=d.length)
    place(bm, T((a + b) / 2) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4(), material)
    if round_ends:
        ball(a, ra, material)
        ball(b, rb, material)


def box(c, size, material, M=None, rot=(0, 0, 0), bevel=.004):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.scale(bm, vec=Vector(size), verts=bm.verts)
    matrix = T(c) @ R(*rot)
    return place(bm, (M @ matrix) if M is not None else matrix, material, smooth=False,
                 bevel=min(bevel, min(size) * .3))


def ring(center, normal, radius, thick, material, n=28):
    c, k = Vector(center), Vector(normal).normalized()
    u = k.orthogonal().normalized()
    v = k.cross(u)
    pts = [c + (u * math.cos(i * math.tau / n) + v * math.sin(i * math.tau / n)) * radius for i in range(n)]
    for i in range(n):
        rod(pts[i], pts[(i + 1) % n], thick, thick, material, seg=10, round_ends=False)


def disc(center, normal, radius, thick, material, seg=48):
    c, k = Vector(center), Vector(normal).normalized()
    rod(c - k * thick / 2, c + k * thick / 2, radius, radius, material, seg=seg)


def pistol_grip(material=None):
    """What the revolver hand closes on: mostly hidden by it."""
    rod((0, -.012, .01), (0, -.045, -.115), .021, .024, material or WOOD(), round_ends=True)


def bolts(center, normal, radius, count, size, material):
    """A ring of rivet heads."""
    c, k = Vector(center), Vector(normal).normalized()
    u = k.orthogonal().normalized()
    v = k.cross(u)
    for i in range(count):
        a = i * math.tau / count
        ball(c + (u * math.cos(a) + v * math.sin(a)) * radius, size, material)


def band(y, z, radius, width, material, rivets=0, seg=40):
    """A hoop round a barrel that runs along +Y, optionally riveted."""
    rod((0, y, z), (0, y + width, z), radius, radius, material, seg=seg)
    if rivets:
        bolts((0, y + width / 2, z), (0, 1, 0), radius + .001, rivets, width * .28, material)


def coil(a, b, radius, turns, thick, material):
    """Tubing wound round the line a-b."""
    a, b = Vector(a), Vector(b)
    k = (b - a).normalized()
    u = k.orthogonal().normalized()
    v = k.cross(u)
    steps = int(turns * 14)
    last = None
    for i in range(steps + 1):
        t = i / steps
        ang = t * turns * math.tau
        p = a + (b - a) * t + (u * math.cos(ang) + v * math.sin(ang)) * radius
        if last is not None:
            rod(last, p, thick, thick, material, seg=8, round_ends=False)
        last = p


def saw_teeth(center, normal, radius, count, material):
    c, k = Vector(center), Vector(normal).normalized()
    u = k.orthogonal().normalized()
    v = k.cross(u)
    for i in range(count):
        a = i * math.tau / count
        at = c + (u * math.cos(a) + v * math.sin(a)) * radius
        lean = u * math.cos(a + .45) + v * math.sin(a + .45)
        rod(at, at + lean * radius * .13, radius * .05, .0008, material, seg=6)


# ---------------------------------------------------------------- long guns
# Held like the shotgun: the breech's top rear at the origin, barrel along +Y,
# a fore-end about .12 to .32 along it for the left hand to cup.
def rifle():
    """An AK-47: stamped receiver with a ribbed cover, banana magazine, wooden furniture."""
    blued = STEEL()
    # stock, wrist and pistol grip
    box((0, -.27, -.06), (.038, .26, .075), WOOD(), rot=(-.13, 0, 0), bevel=.014)
    box((0, -.395, -.075), (.04, .014, .10), IRON(), rot=(-.13, 0, 0), bevel=.004)
    box((0, -.115, -.105), (.03, .045, .10), WOOD(), rot=(.32, 0, 0), bevel=.010)
    # receiver, ribbed dust cover, rear trunnion
    box((0, .0, -.04), (.036, .28, .05), blued, bevel=.005)
    rod((0, -.12, -.014), (0, .10, -.014), .019, .019, blued, seg=20)
    for y in (-.09, -.05, -.01, .03, .07):
        box((0, y, .002), (.03, .008, .006), IRON(), bevel=.002)
    box((.0195, -.03, -.04), (.004, .13, .012), IRON(), bevel=.001)
    box((.0195, .06, -.05), (.004, .05, .016), IRON(), bevel=.001)
    for y in (-.11, .10):
        ball((.0195, y, -.055), .0035, IRON())
    # charging handle, trigger guard and trigger, selector
    rod((.018, .05, -.022), (.04, .05, -.022), .005, .005, IRON(), seg=10, round_ends=True)
    box((0, -.045, -.085), (.004, .085, .003), IRON(), bevel=.001)
    box((0, -.003, -.075), (.004, .003, .024), IRON(), bevel=.001)
    rod((0, -.05, -.066), (0, -.058, -.082), .003, .003, IRON(), seg=8)
    # banana magazine
    last = None
    for k in range(9):
        t = k / 8
        y = .035 + .085 * t * t + .02 * t
        z = -.07 - .19 * t
        if last is not None:
            mid = ((last[0] + y) / 2, (last[1] + z) / 2)
            box((0, mid[0], mid[1]), (.026, .062, .034), IRON(), rot=(-.5 * t - .08, 0, 0), bevel=.004)
        last = (y, z)
    for t in (.25, .5, .75):
        y = .035 + .085 * t * t + .02 * t
        box((0, y, -.07 - .19 * t), (.028, .004, .03), blued, rot=(-.5 * t, 0, 0), bevel=.001)
    # rear sight block, wooden handguards, gas tube
    box((0, .13, -.004), (.026, .05, .022), IRON(), bevel=.004)
    box((0, .135, .012), (.012, .05, .006), IRON(), rot=(.12, 0, 0), bevel=.001)
    rod((0, .16, -.036), (0, .36, -.036), .024, .022, WOOD(), seg=24)
    rod((0, .16, -.008), (0, .33, -.008), .017, .016, WOOD(), seg=20)
    for y in (.20, .25, .30):
        for sx in (-1, 1):
            box((sx * .0155, y, -.008), (.004, .022, .008), pbr("vent", (20, 14, 10), .9), bevel=.001)
    band(.155, -.024, .028, .012, IRON(), seg=24)
    band(.355, -.03, .0245, .012, IRON(), seg=24)
    rod((0, .33, -.008), (0, .47, -.008), .0085, .0085, blued, seg=16)
    box((0, .475, -.018), (.022, .03, .034), IRON(), bevel=.004)
    # barrel, cleaning rod, front sight with ears, slant brake
    rod((0, .14, -.032), (0, .66, -.032), .0085, .008, blued, seg=20)
    rod((0, .38, -.048), (0, .63, -.048), .003, .003, blued, seg=8)
    box((0, .60, -.02), (.016, .03, .03), IRON(), bevel=.003)
    for sx in (-1, 1):
        box((sx * .009, .60, .006), (.003, .022, .026), IRON(), rot=(0, sx * .25, 0), bevel=.001)
    rod((0, .60, -.004), (0, .60, .014), .0018, .0018, IRON(), seg=6)
    rod((0, .66, -.032), (0, .70, -.032), .011, .011, IRON(), seg=18)
    box((0, .705, -.03), (.02, .012, .012), IRON(), rot=(.5, 0, 0), bevel=.002)
    # sling loop
    ring((-.02, -.16, -.05), (0, 1, 0), .010, .002, IRON(), n=12)


def crossbow():
    """Leaf-spring crossbow with a dynamite stick on the rail."""
    spring = pbr("spring", (40, 42, 46), .4, 1., wear=(140, 130, 120), blotch=(90, 56, 40))
    rope = pbr("rope", (150, 126, 86), .95, 0., bump=.9, scale=70.)
    box((0, .10, -.035), (.046, .64, .046), WOOD(), bevel=.012)
    box((0, -.28, -.07), (.046, .18, .11), WOOD(), rot=(-.22, 0, 0), bevel=.016)
    box((0, .14, -.009), (.014, .52, .006), BRASS(), bevel=.002)
    box((0, .21, -.035), (.052, .16, .052), rope, bevel=.008)
    for leaf, reach in enumerate((.25, .20, .15)):
        z = -.004 - leaf * .008
        for s in (-1, 1):
            pts = [Vector((s * x, .42 - .12 * (x / .25) ** 2 + leaf * .004, z)) for x in
                   [reach * k / 4 for k in range(5)]]
            for a, b in zip(pts, pts[1:]):
                box(((a.x + b.x) / 2, (a.y + b.y) / 2, z), (abs(b.x - a.x) + .004, .022, .006), spring,
                    rot=(0, 0, -s * math.atan2(a.y - b.y, abs(b.x - a.x))), bevel=.002)
    for s in (-1, 1):
        box((s * .03, .42, -.012), (.012, .05, .04), IRON(), bevel=.003)
        ball((s * .03, .42, .012), .006, STEEL())
        tip = Vector((s * .25, .30, -.004))
        disc(tip, (0, 0, 1), .016, .008, BRASS(), seg=18)
        rod(tip, (0, .0, .004), .0022, .0022, PAPER(), seg=6)
    box((0, .0, .0), (.02, .03, .022), IRON(), bevel=.003)
    rod((0, .03, .012), (0, .36, .012), .0145, .0145, RED(), seg=24)
    disc((0, .362, .012), (0, 1, 0), .013, .004, PAPER(), seg=18)
    for y in (.08, .26):
        band(y, .012, .0155, .016, pbr("tape", (36, 34, 32), .6), seg=24)
    rod((0, .03, .026), (.018, -.02, .05), .0022, .0022, PAPER(), seg=6)
    rod((.018, -.02, .05), (.0, -.05, .07), .0022, .0022, PAPER(), seg=6)
    ring((0, .46, -.035), (1, 0, 0), .04, .005, IRON(), n=18)
    box((0, .34, .0), (.004, .012, .03), IRON(), bevel=.001)
    ring((0, -.12, -.075), (1, 0, 0), .026, .004, IRON(), n=14)


def cow_launcher():
    """Riveted stovepipe cannon with a hide wrap, a pressure bottle and a cowbell."""
    hide = pbr("hide", (206, 196, 176), .85, 0., blotch=(30, 26, 24), scale=8., bump=.6)
    horn = pbr("horn", (206, 190, 150), .45, 0.)
    rod((0, -.02, -.04), (0, .62, -.04), .062, .066, IRON(), seg=48)
    ball((0, -.02, -.04), (.062, .04, .062), IRON())
    for y in (.04, .38, .56):
        band(y, -.04, .068, .02, RUST(), rivets=14, seg=48)
    rod((0, .62, -.04), (0, .72, -.04), .066, .10, IRON(), seg=48)
    band(.715, -.04, .102, .01, RUST(), seg=48)
    rod((0, .12, -.04), (0, .33, -.04), .07, .07, hide, seg=40)
    for y in (.125, .315):
        band(y, -.04, .072, .008, pbr("thong", (60, 40, 26), .8), seg=40)
    box((0, -.22, -.075), (.05, .34, .09), WOOD(), rot=(-.14, 0, 0), bevel=.016)
    rod((0, -.04, -.135), (0, .10, -.135), .034, .034, COPPER(), seg=28)
    ball((0, -.04, -.135), (.034, .024, .034), COPPER())
    ball((0, .10, -.135), (.034, .024, .034), COPPER())
    rod((0, .10, -.135), (0, .16, -.10), .008, .008, BRASS(), seg=10, round_ends=True)
    ball((0, .60, .028), (.03, .036, .026), horn)
    ball((0, .635, .016), (.018, .02, .016), horn)
    for s in (-1, 1):
        rod((s * .02, .59, .04), (s * .07, .60, .075), .009, .002, horn, seg=12, round_ends=True)
        ball((s * .012, .622, .03), .006, pbr("socket", (10, 8, 8), .9))
        rod((s * .066, .68, -.04), (s * .13, .70, .0), .012, .003, horn, seg=12, round_ends=True)
    rod((0, .66, -.106), (0, .66, -.13), .003, .003, IRON(), seg=6)
    rod((0, .66, -.13), (0, .66, -.18), .012, .026, BRASS(), seg=20)
    ball((0, .66, -.19), .007, IRON())
    box((0, .0, .028), (.012, .06, .014), IRON(), bevel=.002)
    rod((.066, .0, -.02), (.10, -.02, .02), .006, .006, BRASS(), seg=10, round_ends=True)
    ball((.103, -.022, .024), .011, pbr("knob", (140, 30, 26), .5))


def bottle_launcher():
    """A length of drain pipe hose-clamped to a two-by-four, with a rocket in the end."""
    plank = pbr("plank", (156, 124, 82), .8, 0., grain=(110, 82, 50), scale=10.)
    pipe = pbr("pipe", (96, 100, 100), .45, .9, wear=(170, 170, 166), blotch=(110, 70, 44))
    tape = pbr("duct", (130, 132, 134), .55, .2, bump=.5, scale=50.)
    glass = pbr("glass", (48, 84, 48), .12, 0., bump=.04)
    can = pbr("can", (170, 172, 174), .3, 1., wear=(220, 220, 220))
    box((0, .04, -.082), (.075, .74, .036), plank, bevel=.006)
    box((0, -.36, -.11), (.075, .12, .10), plank, rot=(-.3, 0, 0), bevel=.008)
    rod((0, -.04, -.03), (0, .56, -.03), .036, .036, pipe, seg=40)
    rod((0, -.06, -.03), (0, -.04, -.03), .041, .041, IRON(), seg=40)
    for y in (.04, .28, .50):
        band(y, -.03, .0385, .014, can, seg=40)
        box((.0, y + .007, .012), (.02, .014, .012), IRON(), bevel=.002)
        rod((.012, y + .007, .012), (.03, y + .007, .012), .0035, .0035, STEEL(), seg=8)
    for y in (.14, .40):
        rod((0, y, -.045), (0, y + .05, -.045), .058, .058, tape, seg=28)
    rod((0, .56, -.03), (0, .65, -.03), .041, .041, can, seg=40)
    band(.59, -.03, .0415, .03, RED(), seg=40)
    rod((0, .62, -.03), (0, .76, -.03), .028, .026, glass, seg=28)
    rod((0, .76, -.03), (0, .80, -.03), .026, .011, glass, seg=28)
    rod((0, .80, -.03), (0, .84, -.03), .011, .011, glass, seg=14)
    rod((0, .84, -.03), (0, .91, -.03), .016, .002, RED(), seg=18)
    rod((0, .66, -.002), (0, 1.0, .012), .0028, .0028, PALE(), seg=8)
    box((0, -.01, .016), (.03, .045, .014), BRASS(), bevel=.003)
    box((0, .012, .03), (.022, .016, .016), BRASS(), bevel=.002)
    rod((0, .03, .02), (.02, .09, .012), .002, .002, PAPER(), seg=6)
    box((0, .26, .012), (.004, .012, .03), IRON(), bevel=.001)


def hunter():
    """A scoped bolt-action deer rifle: walnut Monte Carlo stock taped at the wrist,
    long blued barrel, a big hunting scope in rings, bolt handle out to the right."""
    blued = STEEL()
    walnut = pbr("walnut", (84, 44, 22), .45, 0., grain=(44, 22, 12), wear=(150, 104, 66), scale=12.)
    tape = pbr("duct", (130, 132, 134), .55, .2, bump=.5, scale=50.)
    glass = pbr("lens", (40, 70, 90), .05, .2, bump=.02)
    # buttstock with its comb and recoil pad, wrist, pistol grip cap
    box((0, -.29, -.072), (.036, .24, .07), walnut, rot=(-.10, 0, 0), bevel=.014)
    box((0, -.27, -.025), (.03, .19, .03), walnut, rot=(-.04, 0, 0), bevel=.012)
    box((0, -.415, -.085), (.038, .016, .102), RUBBER(), rot=(-.10, 0, 0), bevel=.005)
    box((0, -.115, -.08), (.03, .07, .045), walnut, rot=(.18, 0, 0), bevel=.010)
    box((0, -.10, -.118), (.026, .032, .05), walnut, rot=(.42, 0, 0), bevel=.010)
    box((0, -.088, -.143), (.024, .012, .006), IRON(), rot=(.42, 0, 0), bevel=.002)
    rod((0, -.16, -.072), (0, -.13, -.07), .028, .028, tape, seg=24)
    # receiver, bolt with its handle and knob, safety
    rod((0, -.10, -.022), (0, .07, -.022), .0175, .0175, blued, seg=28)
    rod((0, -.125, -.022), (0, -.10, -.022), .015, .013, blued, seg=24, round_ends=True)
    rod((.012, -.07, -.016), (.052, -.075, -.045), .0045, .0045, blued, seg=10)
    ball((.055, -.076, -.049), .0085, IRON())
    box((.016, -.045, -.004), (.004, .05, .008), IRON(), bevel=.001)
    box((.0165, -.115, -.01), (.004, .012, .006), IRON(), bevel=.001)
    # stock fore-end under the barrel, trigger guard, trigger, floorplate
    box((0, .14, -.048), (.032, .32, .034), walnut, rot=(.015, 0, 0), bevel=.010)
    box((0, .02, -.068), (.028, .07, .012), IRON(), bevel=.002)
    box((0, -.045, -.088), (.004, .07, .003), IRON(), bevel=.001)
    box((0, -.06, -.072), (.004, .003, .022), IRON(), bevel=.001)
    rod((0, -.048, -.062), (0, -.054, -.08), .0026, .0026, IRON(), seg=8)
    # the long barrel, its crown and front sight base
    rod((0, .07, -.022), (0, .80, -.022), .011, .0078, blued, seg=24)
    rod((0, .80, -.022), (0, .815, -.022), .0086, .0086, IRON(), seg=18)
    box((0, .72, -.011), (.008, .02, .006), IRON(), bevel=.001)
    # scope: low rings, a slim tube, turrets, objective and eyepiece bells
    for y in (-.03, .07):
        box((0, y, -.002), (.014, .014, .01), IRON(), bevel=.002)
        ring((0, y, .022), (0, 1, 0), .0105, .003, IRON(), n=20)
    rod((0, -.055, .022), (0, .14, .022), .009, .009, blued, seg=30)
    rod((0, .14, .022), (0, .17, .022), .009, .0135, blued, seg=30)
    rod((0, .17, .022), (0, .19, .022), .0135, .0135, blued, seg=30)
    disc((0, .191, .022), (0, 1, 0), .0115, .0015, glass)
    rod((0, -.08, .022), (0, -.055, .022), .0115, .009, blued, seg=30)
    rod((0, -.088, .022), (0, -.08, .022), .0115, .0115, RUBBER(), seg=30)
    rod((0, .02, .031), (0, .02, .040), .005, .005, IRON(), seg=14)
    rod((.008, .02, .022), (.018, .02, .022), .005, .005, IRON(), seg=14)
    band(.02, .022, .0095, .009, blued, seg=24)
    # sling swivels
    ring((0, -.25, -.115), (1, 0, 0), .008, .002, IRON(), n=12)
    ring((0, .26, -.07), (1, 0, 0), .008, .002, IRON(), n=12)


def mower():
    """A belt-fed light machine gun gone to seed on a farm: olive-drab receiver and
    feed cover, a can of linked brass slung off the side, perforated heat shield,
    carry handle, folded bipod and a slotted flash hider."""
    drab = pbr("drab", (34, 38, 24), .6, .15, wear=(96, 94, 74), blotch=(26, 30, 18), scale=24.)
    can = pbr("ammo_can", (44, 50, 28), .65, .2, wear=(110, 108, 84), blotch=(70, 46, 30), scale=20.)
    vent = pbr("vent", (14, 12, 10), .9)
    # stock, pistol grip, trigger guard
    box((0, -.27, -.07), (.04, .25, .075), WOOD(), rot=(-.06, 0, 0), bevel=.014)
    box((0, -.395, -.08), (.044, .016, .10), IRON(), rot=(-.06, 0, 0), bevel=.005)
    box((0, -.11, -.11), (.032, .046, .095), WOOD(), rot=(.30, 0, 0), bevel=.010)
    box((0, -.06, -.088), (.004, .085, .003), IRON(), bevel=.001)
    box((0, -.075, -.074), (.004, .003, .024), IRON(), bevel=.001)
    # receiver, feed cover with its latch, rear sight
    box((0, .02, -.035), (.05, .30, .07), drab, bevel=.006)
    box((0, .05, .008), (.052, .17, .018), drab, rot=(-.02, 0, 0), bevel=.004)
    box((0, -.04, .02), (.02, .016, .01), IRON(), bevel=.002)
    box((0, -.09, .012), (.016, .03, .026), IRON(), bevel=.003)
    for y in (-.05, .0, .05, .1):
        box((.0265, y, -.04), (.002, .02, .05), IRON(), bevel=.001)
    rod((.026, .06, -.022), (.05, .06, -.022), .006, .006, IRON(), seg=10, round_ends=True)
    # the ammo can on the left and the belt of brass running up into the feed
    box((-.05, .03, -.115), (.05, .085, .06), can, bevel=.005)
    box((-.05, .03, -.083), (.053, .088, .006), can, bevel=.002)
    rod((-.05, .0, -.078), (-.05, .06, -.078), .003, .003, IRON(), seg=8)
    for k in range(6):
        t = k / 5
        x = -.045 + .02 * t
        z = -.08 + .05 * t
        rod((x, .05, z), (x, .078, z), .0036, .0036, BRASS(), seg=10)
        rod((x, .078, z), (x, .086, z), .0036, .0014, BRASS(), seg=10)
        box((x, .064, z - .004), (.008, .036, .002), IRON(), bevel=.001)
    # barrel jacket, heat shield, gas cylinder, carry handle
    rod((0, .17, -.03), (0, .74, -.03), .0145, .0125, STEEL(), seg=24)
    box((0, .33, -.008), (.036, .26, .024), drab, bevel=.004)
    for y in (.23, .27, .31, .35, .39, .43):
        for sx in (-1, 1):
            box((sx * .018, y, -.008), (.003, .022, .012), vent, bevel=.001)
    rod((0, .2, -.058), (0, .5, -.058), .009, .009, IRON(), seg=14)
    for y in (.22, .34):
        rod((0, y, -.015), (0, y, .04), .004, .004, IRON(), seg=8)
    rod((0, .22, .04), (0, .34, .04), .006, .006, WOOD(), seg=12)
    # folded bipod, front sight, slotted flash hider
    for sx in (-1, 1):
        rod((sx * .012, .5, -.072), (sx * .014, .70, -.074), .0035, .0035, IRON(), seg=8)
        ball((sx * .014, .705, -.074), .006, RUBBER())
    box((0, .5, -.062), (.03, .014, .012), IRON(), bevel=.002)
    box((0, .66, -.008), (.006, .016, .03), IRON(), bevel=.001)
    rod((0, .74, -.03), (0, .80, -.03), .015, .017, IRON(), seg=20)
    for a in range(4):
        ang = a * math.pi / 2 + math.pi / 4
        box((math.cos(ang) * .016, .79, -.03 + math.sin(ang) * .016), (.004, .03, .004), vent, bevel=.001)


POLY = lambda: pbr("poly", (30, 30, 32), .62, 0., wear=(84, 84, 86), bump=.35, scale=40.)
PARKER = lambda: pbr("parker", (46, 48, 46), .62, .7, wear=(120, 120, 116), scale=30.)
STAINLESS = lambda: pbr("stainless", (150, 152, 156), .28, 1., wear=(210, 210, 214), blotch=(110, 110, 112))


def star_badge(center, normal, radius, material):
    """A five-point lawman's star, flat on a face."""
    c, k = Vector(center), Vector(normal).normalized()
    u = k.orthogonal().normalized()
    v = k.cross(u)
    disc(c, k, radius * .42, .002, material, seg=20)
    for i in range(5):
        a = i * math.tau / 5 + math.pi / 2
        tip = c + (u * math.cos(a) + v * math.sin(a)) * radius
        rod(c, tip, radius * .2, radius * .04, material, seg=6)
        ball(tip, radius * .09, material)


def riot_pump():
    """The county's riot pump: black synthetic stock and slide, a side saddle of
    red shells, magazine tube under the barrel, bead sight, a star on the stock."""
    blued = STEEL()
    shell = pbr("shell_red", (150, 34, 28), .5, 0., wear=(200, 120, 100))
    # stock and wrist
    box((0, -.28, -.07), (.038, .25, .072), POLY(), rot=(-.12, 0, 0), bevel=.014)
    box((0, -.40, -.082), (.04, .018, .10), RUBBER(), rot=(-.12, 0, 0), bevel=.006)
    box((0, -.13, -.085), (.032, .06, .05), POLY(), rot=(.22, 0, 0), bevel=.012)
    star_badge((.02, -.26, -.07), (1, 0, 0), .016, BRASS())
    # receiver, ejection port, safety, trigger guard
    box((0, -.01, -.035), (.042, .22, .066), blued, bevel=.006)
    box((.0215, .0, -.025), (.002, .07, .022), pbr("port", (10, 10, 10), .9), bevel=.001)
    rod((-.02, -.07, -.06), (.02, -.07, -.06), .0035, .0035, IRON(), seg=8)
    box((0, -.07, -.078), (.004, .07, .003), IRON(), bevel=.001)
    box((0, -.085, -.068), (.004, .003, .022), IRON(), bevel=.001)
    # side saddle with four shells
    box((-.024, .0, -.022), (.006, .11, .036), POLY(), bevel=.003)
    for k in range(4):
        y = -.04 + k * .027
        rod((-.032, y, -.04), (-.032, y, -.004), .0085, .0085, shell, seg=14)
        rod((-.032, y, -.044), (-.032, y, -.04), .009, .009, BRASS(), seg=14)
    # barrel and its bead, magazine tube and cap
    rod((0, .1, -.016), (0, .64, -.016), .0118, .0112, blued, seg=24)
    ball((0, .635, -.003), .0035, BRASS())
    rod((0, .1, -.044), (0, .58, -.044), .0115, .0115, blued, seg=20)
    rod((0, .58, -.044), (0, .60, -.044), .0125, .0125, IRON(), seg=20)
    band(.56, -.03, .013, .012, IRON(), seg=20)
    # the slide: ribbed synthetic grip on the tube
    box((0, .30, -.05), (.04, .17, .04), POLY(), bevel=.008)
    for y in (.24, .27, .30, .33, .36):
        box((0, y, -.05), (.042, .006, .032), pbr("rib", (18, 18, 20), .8), bevel=.002)


def tommy():
    """The squad car's drum-fed submachine gun: walnut stock and grips, a ribbed
    barrel with its compensator, the round drum under the receiver."""
    blued = STEEL()
    box((0, -.28, -.068), (.036, .25, .072), WOOD(), rot=(-.1, 0, 0), bevel=.014)
    box((0, -.40, -.08), (.038, .014, .1), IRON(), rot=(-.1, 0, 0), bevel=.004)
    box((0, -.11, -.105), (.03, .045, .10), WOOD(), rot=(.3, 0, 0), bevel=.010)
    # receiver, actuator knob, rear sight, trigger guard
    box((0, .0, -.025), (.042, .26, .058), blued, bevel=.006)
    ball((0, .05, .01), .007, IRON())
    box((0, -.09, .012), (.014, .028, .022), IRON(), bevel=.003)
    box((0, -.045, -.082), (.004, .085, .003), IRON(), bevel=.001)
    # the drum, its winding key and rim
    disc((0, .05, -.11), (1, 0, 0), .064, .052, blued, seg=48)
    ring((0, .05, -.11), (1, 0, 0), .062, .004, IRON(), n=40)
    disc((.03, .05, -.11), (1, 0, 0), .014, .008, IRON(), seg=20)
    box((.036, .05, -.11), (.004, .006, .026), IRON(), bevel=.001)
    # front grip with finger grooves
    rod((0, .2, -.05), (0, .2, -.13), .014, .016, WOOD(), seg=18, round_ends=True)
    for z in (-.075, -.095, -.115):
        ring((0, .2, z), (0, 0, 1), .016, .003, WOOD(), n=16)
    # ribbed barrel, front sight, compensator
    rod((0, .13, -.02), (0, .56, -.02), .011, .010, blued, seg=20)
    for k in range(10):
        ring((0, .15 + k * .022, -.02), (0, 1, 0), .0135, .003, blued, n=20)
    box((0, .52, -.005), (.004, .012, .012), IRON(), bevel=.001)
    box((0, .58, -.02), (.026, .05, .026), IRON(), bevel=.004)
    for k in range(3):
        box((0, .565 + k * .014, -.006), (.018, .005, .004), pbr("port", (10, 10, 10), .9), bevel=.001)


def grease_gun():
    """A stamped steel tube gun the shiners keep in the truck, held one-handed:
    a rusty tube receiver, the long stick magazine ahead of the hand, ejection
    cover and cocking crank, tape round the barrel and a peep sight."""
    tube = pbr("stamped", (66, 62, 56), .55, .8, wear=(150, 138, 120), blotch=(110, 62, 36), scale=26.)
    tape = pbr("duct", (130, 132, 134), .55, .2, bump=.5, scale=50.)
    pistol_grip(tube)
    # the tube receiver, rear cap and a stub of the wire stock
    rod((0, -.09, .05), (0, .13, .05), .027, .027, tube, seg=36)
    disc((0, -.09, .05), (0, -1, 0), .027, .006, IRON(), seg=36)
    for sx in (-1, 1):
        rod((sx * .012, -.09, .04), (sx * .014, -.15, .02), .0035, .0035, IRON(), seg=8)
    for y in (-.06, .0, .06):
        band(y, .05, .0275, .005, IRON(), seg=36)
    # ejection cover, cocking crank, peep sight
    box((.024, .03, .062), (.008, .07, .026), tube, bevel=.003)
    box((.029, .03, .062), (.002, .05, .014), pbr("port", (10, 10, 10), .9), bevel=.001)
    rod((.026, -.05, .04), (.05, -.05, .04), .0035, .0035, IRON(), seg=8)
    rod((.05, -.05, .04), (.05, -.068, .026), .0035, .0035, IRON(), seg=8, round_ends=True)
    ring((0, -.06, .085), (0, 1, 0), .006, .0018, IRON(), n=12)
    rod((0, -.06, .077), (0, -.06, .07), .002, .002, IRON(), seg=6)
    # magazine well and the long stick magazine out ahead of the hand
    box((0, .075, .018), (.022, .032, .03), tube, bevel=.003)
    box((0, .078, -.065), (.018, .026, .15), IRON(), rot=(-.05, 0, 0), bevel=.003)
    box((0, .081, -.142), (.02, .029, .008), IRON(), rot=(-.05, 0, 0), bevel=.002)
    # collar, taped barrel, front sight
    rod((0, .13, .05), (0, .15, .05), .019, .019, IRON(), seg=24)
    rod((0, .15, .05), (0, .275, .05), .0105, .0105, STEEL(), seg=20)
    rod((0, .16, .05), (0, .2, .05), .014, .014, tape, seg=20)
    box((0, .14, .072), (.004, .008, .01), IRON(), bevel=.001)


def patrol_bar():
    """The deputies' automatic rifle: parkerized receiver, walnut stock and fore-end,
    a big box magazine, the bipod folded under the barrel, a slotted flash hider."""
    box((0, -.27, -.07), (.038, .25, .074), WOOD(), rot=(-.08, 0, 0), bevel=.014)
    box((0, -.395, -.08), (.042, .016, .102), IRON(), rot=(-.08, 0, 0), bevel=.005)
    box((0, -.11, -.105), (.03, .045, .098), WOOD(), rot=(.3, 0, 0), bevel=.010)
    # receiver, rear sight leaf, charging handle, trigger guard
    box((0, .02, -.03), (.044, .30, .068), PARKER(), bevel=.006)
    box((0, -.1, .012), (.014, .03, .026), IRON(), bevel=.003)
    rod((-.022, .08, -.03), (-.046, .08, -.03), .005, .005, IRON(), seg=10, round_ends=True)
    box((0, -.06, -.086), (.004, .085, .003), IRON(), bevel=.001)
    # the box magazine, deep
    box((0, .06, -.12), (.034, .07, .13), PARKER(), bevel=.004)
    box((0, .06, -.186), (.038, .074, .008), IRON(), bevel=.002)
    for z in (-.09, -.13, -.16):
        box((.0175, .06, z), (.002, .05, .004), IRON(), bevel=.001)
    # fore-end, gas cylinder, barrel
    box((0, .26, -.045), (.036, .18, .04), WOOD(), bevel=.008)
    rod((0, .17, -.055), (0, .52, -.055), .009, .009, PARKER(), seg=14)
    rod((0, .17, -.022), (0, .70, -.022), .0105, .0095, STEEL(), seg=20)
    # bipod folded back along the barrel, front sight, flash hider
    box((0, .58, -.035), (.024, .014, .02), IRON(), bevel=.002)
    for sx in (-1, 1):
        rod((sx * .01, .58, -.045), (sx * .014, .38, -.06), .0035, .0035, IRON(), seg=8)
        ball((sx * .014, .375, -.06), .006, IRON())
    box((0, .66, -.006), (.006, .014, .026), IRON(), bevel=.001)
    rod((0, .70, -.022), (0, .76, -.022), .013, .015, IRON(), seg=20)
    ring((0, -.16, -.115), (1, 0, 0), .009, .002, IRON(), n=12)


def marksman():
    """The county marksman's semi-automatic: black synthetic stock with a cheek
    riser, a twenty-round box, a long scope with its sunshade and flip caps."""
    blued = STEEL()
    glass = pbr("lens", (40, 70, 90), .05, .2, bump=.02)
    cap = pbr("flip_cap", (170, 130, 40), .5, 0.)
    box((0, -.29, -.072), (.036, .24, .07), POLY(), rot=(-.10, 0, 0), bevel=.014)
    box((0, -.28, -.026), (.03, .14, .028), POLY(), rot=(-.04, 0, 0), bevel=.010)
    box((0, -.415, -.085), (.038, .016, .102), RUBBER(), rot=(-.10, 0, 0), bevel=.005)
    box((0, -.115, -.105), (.03, .045, .095), POLY(), rot=(.3, 0, 0), bevel=.010)
    star_badge((.019, -.3, -.075), (1, 0, 0), .014, pbr("silver", (190, 190, 196), .3, 1.))
    # receiver, operating rod handle, magazine, trigger guard
    box((0, -.01, -.03), (.036, .2, .056), blued, bevel=.005)
    box((.021, .06, -.02), (.006, .1, .01), IRON(), bevel=.002)
    box((.024, .015, -.02), (.012, .012, .014), IRON(), bevel=.002)
    box((0, .03, -.1), (.026, .05, .09), IRON(), rot=(-.15, 0, 0), bevel=.003)
    box((0, -.06, -.072), (.004, .07, .003), IRON(), bevel=.001)
    # fore-end, barrel, muzzle brake
    box((0, .17, -.046), (.032, .26, .034), POLY(), bevel=.010)
    rod((0, .09, -.022), (0, .76, -.022), .0112, .0088, blued, seg=24)
    box((0, .775, -.022), (.022, .04, .022), IRON(), bevel=.004)
    for k in range(3):
        box((0, .762 + k * .012, -.022), (.024, .004, .006), pbr("port", (10, 10, 10), .9), bevel=.001)
    # the scope: rings, tube, turrets, sunshade, flip caps
    for y in (-.03, .07):
        box((0, y, -.002), (.014, .014, .01), IRON(), bevel=.002)
        ring((0, y, .022), (0, 1, 0), .0105, .003, IRON(), n=20)
    rod((0, -.06, .022), (0, .14, .022), .009, .009, blued, seg=30)
    rod((0, .14, .022), (0, .17, .022), .009, .0135, blued, seg=30)
    rod((0, .17, .022), (0, .23, .022), .0135, .0135, blued, seg=30)
    disc((0, .231, .022), (0, 1, 0), .0115, .0015, glass)
    rod((0, -.09, .022), (0, -.06, .022), .0115, .009, blued, seg=30)
    box((0, .235, .038), (.026, .004, .02), cap, rot=(-1.1, 0, 0), bevel=.002)
    box((0, -.093, .038), (.022, .004, .018), cap, rot=(1.1, 0, 0), bevel=.002)
    rod((0, .02, .031), (0, .02, .040), .005, .005, IRON(), seg=14)
    rod((.008, .02, .022), (.018, .02, .022), .005, .005, IRON(), seg=14)


# ---------------------------------------------------------------- one-handed
# Held like the revolver: the top of the grip at the origin, the body above and
# ahead of it, short enough to stay in the picture.
def armgun():
    """A living alien forearm cannon: plated, veined, with an eye and a three-claw muzzle."""
    flesh = pbr("carapace", (62, 84, 56), .30, .2, wear=(140, 160, 104), blotch=(40, 50, 40), bump=.9, scale=26.)
    plate = pbr("chitin", (96, 104, 70), .35, .3, wear=(170, 176, 120), bump=.5, scale=30.)
    vein = pbr("vein", (120, 52, 64), .35, 0., bump=.6)
    glow = pbr("glow", (120, 255, 140), emit=3.0)
    claw = pbr("claw", (196, 186, 146), .3, 0.)
    pistol_grip(flesh)
    for k in range(6):
        y = -.05 + k * .048
        ball((0, y, .05), (.05 - .004 * k, .034, .047 - .003 * k), flesh)
        ball((0, y + .004, .082 - .002 * k), (.034 - .003 * k, .03, .018), plate)
        if k < 5:
            rod((0, y - .005, .095 - .002 * k), (0, y - .03, .13 - .004 * k), .008, .001, claw, seg=10)
    for s in (-1, 1):
        rod((s * .046, -.04, .05), (s * .034, .19, .062), .007, .006, vein, seg=10, round_ends=True)
        rod((s * .03, -.03, .018), (s * .028, .16, .03), .005, .005, vein, seg=10, round_ends=True)
        for y in (.0, .09):
            ball((s * .05, y, .05), .014, pbr("sac", (150, 190, 110), .2, bump=.2))
            ball((s * .056, y, .05), .008, glow)
    ball((0, .02, .096), .02, pbr("eyeball", (206, 200, 170), .15, bump=.05))
    ball((0, .008, .103), (.009, .012, .014), pbr("pupil", (10, 12, 8), .1))
    rod((0, .22, .05), (0, .30, .05), .03, .022, flesh, seg=24)
    ball((0, .31, .05), .02, glow)
    for a in (math.pi / 2, math.pi * 7 / 6, math.pi * 11 / 6):
        base = Vector((math.cos(a) * .034, .22, .05 + math.sin(a) * .034))
        mid = Vector((math.cos(a) * .058, .31, .05 + math.sin(a) * .058))
        tip = Vector((math.cos(a) * .024, .39, .05 + math.sin(a) * .024))
        rod(base, mid, .013, .011, flesh, seg=14, round_ends=True)
        rod(mid, tip, .011, .002, claw, seg=14, round_ends=True)
    rod((0, -.09, .05), (.04, -.16, .0), .012, .008, vein, seg=12, round_ends=True)


def riveter():
    """A pneumatic rivet gun: finned housing, side drum of rivets, gauge and air hose."""
    paint = pbr("yellow", (164, 124, 34), .55, 0., wear=(60, 60, 64), blotch=(110, 80, 28))
    pistol_grip(RUBBER())
    ring((0, .028, -.03), (1, 0, 0), .026, .004, IRON(), n=14)
    rod((0, -.06, .05), (0, .10, .05), .044, .044, paint, seg=44)
    ball((0, -.06, .05), (.044, .03, .044), paint)
    for y in (-.035, -.02, -.005, .01):
        band(y, .05, .05, .006, IRON(), seg=44)
    band(.085, .05, .0465, .014, IRON(), rivets=10, seg=44)
    rod((0, .10, .05), (0, .16, .05), .034, .022, STEEL(), seg=32)
    rod((0, .16, .05), (0, .245, .05), .0135, .0125, STEEL(), seg=24)
    band(.235, .05, .019, .012, IRON(), seg=24)
    disc((.052, .045, .03), (1, 0, 0), .046, .028, IRON(), seg=40)
    disc((.068, .045, .03), (1, 0, 0), .012, .006, BRASS(), seg=16)
    bolts((.0675, .045, .03), (1, 0, 0), .033, 9, .0065, STEEL())
    box((.03, .11, .036), (.03, .08, .014), IRON(), rot=(0, 0, -.3), bevel=.003)
    for post in (-.03, .06):
        rod((0, post, .09), (0, post, .112), .006, .006, IRON(), seg=10)
    rod((0, -.04, .112), (0, .07, .112), .008, .008, RUBBER(), seg=14, round_ends=True)
    disc((-.03, -.075, .085), (-.5, -1, .4), .02, .012, BRASS(), seg=24)
    disc((-.032, -.081, .0875), (-.5, -1, .4), .016, .003, pbr("dial", (214, 206, 180), .4), seg=24)
    box((.0, .02, .0965), (.03, .05, .003), pbr("plate", (190, 190, 180), .5, .8), bevel=.001)
    rod((0, -.05, -.118), (0, -.05, -.14), .014, .014, BRASS(), seg=16)
    last = Vector((0, -.05, -.14))
    for k in range(1, 7):
        nxt = Vector((.012 * k * k * .35, -.05 - .012 * k, -.14 - .028 * k))
        rod(last, nxt, .011, .011, RUBBER(), seg=12, round_ends=True)
        last = nxt


def pressure_gun():
    """The Copperhead: a riveted copper boiler ending in a cast snake's head."""
    glass = pbr("sight", (120, 170, 150), .08, 0., bump=.02)
    pistol_grip(WOOD())
    rod((0, -.07, .055), (0, .12, .055), .046, .046, COPPER(), seg=44)
    ball((0, -.07, .055), (.046, .034, .046), COPPER())
    rod((0, .12, .055), (0, .16, .055), .046, .024, COPPER(), seg=44)
    for y in (-.045, .03, .105):
        band(y, .055, .048, .012, BRASS(), rivets=12, seg=44)
    rod((.05, -.03, .055), (.05, .07, .055), .0065, .0065, glass, seg=12)
    for y in (-.035, .07):
        rod((.05, y, .055), (.05, y + .008, .055), .009, .009, BRASS(), seg=12)
    for y in (-.02, .045):
        rod((0, y, .10), (0, y, .125), .008, .008, BRASS(), seg=12)
        rod((0, y, .125), (0, y, .14), .012, .009, pbr("cap", (150, 34, 28), .5, .3), seg=12)
    rod((0, .16, .055), (0, .27, .055), .013, .013, BRASS(), seg=20)
    coil((0, .165, .055), (0, .255, .055), .021, 5.5, .005, COPPER())
    ball((0, .295, .058), (.027, .042, .02), COPPER())
    ball((0, .30, .042), (.022, .036, .011), COPPER())
    ball((0, .325, .05), (.012, .012, .007), pbr("maw", (30, 8, 8), .6))
    for s in (-1, 1):
        ball((s * .017, .29, .07), .0055, pbr("snake_eye", (220, 170, 30), .2, emit=.6))
        rod((s * .009, .327, .054), (s * .009, .33, .034), .003, .0006, pbr("fang", (230, 226, 200), .3), seg=8)
    disc((-.042, .02, .095), (-.8, -.3, .5), .026, .012, BRASS(), seg=28)
    disc((-.0465, .0185, .098), (-.8, -.3, .5), .021, .003, pbr("dial", (214, 206, 180), .4), seg=28)
    rod((.03, -.06, .02), (.034, .14, .03), .006, .006, COPPER(), seg=10, round_ends=True)


def teat_gun():
    """A milking machine turned pistol: pail-lid receiver, milk claw, four teat cups, a jar of milk."""
    steel = pbr("stainless", (120, 126, 130), .35, 1., wear=(200, 200, 196), blotch=(90, 84, 76))
    liner = pbr("liner", (196, 120, 116), .5, 0., bump=.3)
    glass = pbr("jar", (150, 176, 170), .06, 0., bump=.02)
    milk = pbr("milk", (232, 228, 214), .4, 0., bump=.02)
    pistol_grip(WOOD())
    rod((0, -.06, .05), (0, .02, .05), .048, .048, steel, seg=44)
    ball((0, -.06, .05), (.048, .02, .048), steel)
    band(-.02, .05, .05, .008, IRON(), seg=44)
    ball((0, -.082, .05), .012, pbr("knob", (20, 20, 20), .5))
    ball((0, .06, .05), (.038, .046, .038), steel)
    for dx, dz in ((-.024, .024), (.024, .024), (-.024, -.02), (.024, -.02)):
        a = Vector((dx, .085, .05 + dz))
        b = Vector((dx * 1.25, .21, .05 + dz * 1.25))
        rod(a, b, .0135, .0155, steel, seg=20)
        rod(b, b + (b - a).normalized() * .02, .017, .0185, liner, seg=20)
        disc(b + (b - a).normalized() * .021, b - a, .011, .002, pbr("bore", (30, 12, 12), .8), seg=16)
        rod(a, (dx * .5, .03, .05 + dz * .5), .006, .006, RUBBER(), seg=10, round_ends=True)
    rod((0, -.02, .096), (0, -.02, .104), .02, .02, IRON(), seg=24)
    ball((0, -.02, .128), (.03, .03, .028), glass)
    ball((0, -.02, .121), (.026, .026, .018), milk)
    box((0, -.066, .104), (.028, .03, .022), IRON(), bevel=.003)
    rod((0, -.066, .115), (0, -.066, .13), .004, .004, BRASS(), seg=8)
    last = Vector((.04, .0, .03))
    for k in range(1, 7):
        a = k * .5
        nxt = Vector((.04 + math.sin(a) * .03, -.02 * k, .03 - .016 * k + math.cos(a) * .008))
        rod(last, nxt, .0065, .0065, RUBBER(), seg=10, round_ends=True)
        last = nxt


def county45():
    """The deputies' issue .45 automatic: blued slide with its serrations and
    sights, walnut grips with a county star, hammer, safety, lanyard ring."""
    blued = pbr("service_blue", (52, 58, 70), .32, 1., wear=(150, 152, 160))
    pistol_grip(WOOD())
    star_badge((.021, -.03, -.05), (1, 0, 0), .009, BRASS())
    box((0, -.045, -.122), (.026, .03, .006), IRON(), rot=(.3, 0, 0), bevel=.002)
    ring((0, -.06, -.13), (1, 0, 0), .006, .0016, IRON(), n=10)
    # frame, dust cover, trigger guard and trigger
    box((0, .03, .022), (.026, .12, .024), blued, bevel=.003)
    box((0, .005, -.004), (.004, .05, .003), blued, bevel=.001)
    box((0, .03, -.006), (.004, .003, .026), blued, bevel=.001)
    rod((0, .0, .006), (0, -.004, -.012), .0028, .0028, IRON(), seg=8)
    # slide, serrations, ejection port, sights, barrel bushing
    box((0, .045, .052), (.028, .2, .034), blued, bevel=.004)
    for k in range(6):
        box((.0145, -.04 + k * .006, .052), (.002, .0025, .026), IRON(), bevel=.0005)
    box((.0142, .06, .06), (.002, .03, .012), pbr("port", (10, 10, 10), .9), bevel=.001)
    box((0, -.048, .074), (.014, .008, .008), IRON(), bevel=.001)
    box((0, .135, .072), (.004, .008, .008), IRON(), bevel=.001)
    rod((0, .145, .05), (0, .152, .05), .0095, .0095, IRON(), seg=18)
    # hammer, thumb safety, slide stop
    box((0, -.063, .062), (.008, .012, .016), IRON(), rot=(.4, 0, 0), bevel=.002)
    box((.015, -.04, .04), (.004, .018, .006), IRON(), bevel=.001)
    box((.015, .02, .034), (.004, .022, .006), IRON(), bevel=.001)


def star357():
    """A stainless .357 magnum with a six-inch full-lug barrel, ventilated rib,
    rubber grips and a sheriff's star inlaid in them."""
    pistol_grip(RUBBER())
    star_badge((.024, -.03, -.05), (1, 0, 0), .010, pbr("silver", (190, 190, 196), .3, 1.))
    steel = STAINLESS()
    # frame, trigger guard, trigger, hammer spur
    box((0, .01, .035), (.026, .09, .05), steel, bevel=.005)
    rod((0, .04, .008), (0, -.01, -.006), .0032, .0032, steel, seg=10)
    box((0, .02, -.006), (.004, .003, .024), steel, bevel=.001)
    box((0, -.05, .07), (.008, .02, .012), steel, rot=(.5, 0, 0), bevel=.002)
    # cylinder with its flutes, the crane latch
    rod((0, -.005, .05), (0, .05, .05), .026, .026, steel, seg=36)
    for k in range(6):
        a = k * math.tau / 6
        box((math.cos(a) * .025, .0225, .05 + math.sin(a) * .025), (.006, .04, .006),
            pbr("flute", (60, 60, 62), .5, 1.), rot=(0, a, 0), bevel=.002)
    box((.014, -.02, .062), (.004, .01, .008), steel, bevel=.001)
    # full-lug barrel, vent rib, red ramp front sight, ejector shroud
    box((0, .16, .058), (.02, .22, .026), steel, bevel=.004)
    box((0, .16, .074), (.008, .22, .006), steel, bevel=.001)
    for y in (.08, .11, .14, .17, .2, .23):
        box((0, y, .074), (.009, .012, .002), pbr("port", (10, 10, 10), .9), bevel=.0005)
    rod((0, .05, .058), (0, .272, .058), .0105, .0105, steel, seg=20)
    box((0, .26, .082), (.004, .016, .01), pbr("ramp", (200, 40, 30), .4), rot=(.3, 0, 0), bevel=.001)
    box((0, .14, .04), (.016, .17, .014), steel, bevel=.003)
    box((0, -.035, .08), (.012, .01, .006), IRON(), bevel=.001)


def hogleg():
    """An old single-action .44: brass frame and trigger guard, case-hardened
    cylinder, a long blued barrel with its ejector rod, worn walnut grips
    wrapped in rawhide."""
    hide = pbr("rawhide", (150, 112, 70), .85, 0., bump=.7, scale=40.)
    pistol_grip(WOOD())
    for z in (-.04, -.06, -.08):
        ring((0, -.03, z), (0, .3, 1), .025, .0035, hide, n=18)
    # brass frame, backstrap, trigger guard, trigger
    box((0, .0, .03), (.026, .08, .04), BRASS(), bevel=.004)
    rod((0, -.03, .03), (0, -.05, -.06), .006, .008, BRASS(), seg=12)
    rod((0, .03, .01), (0, -.02, -.004), .0035, .0035, BRASS(), seg=10)
    box((0, .01, -.002), (.004, .003, .022), IRON(), bevel=.001)
    # hammer spur cocked back, loading gate
    box((0, -.045, .072), (.007, .022, .01), IRON(), rot=(.7, 0, 0), bevel=.002)
    for k in range(4):
        box((0, -.054 + k * .004, .08 + k * .002), (.008, .0015, .003), pbr("port", (10, 10, 10), .9), bevel=.0003)
    box((.0135, -.015, .045), (.003, .018, .02), BRASS(), bevel=.001)
    # case-hardened cylinder with its stop notches
    rod((0, -.012, .05), (0, .048, .05), .025, .025, pbr("case", (70, 64, 70), .35, 1., wear=(150, 120, 90), blotch=(90, 70, 110)), seg=36)
    for k in range(6):
        a = k * math.tau / 6
        box((math.cos(a) * .025, .03, .05 + math.sin(a) * .025), (.004, .006, .004), IRON(), rot=(0, a, 0), bevel=.001)
    # long round barrel, blade front sight, ejector rod and housing
    rod((0, .048, .062), (0, .31, .062), .0105, .0098, STEEL(), seg=22)
    box((0, .3, .075), (.002, .012, .008), BRASS(), bevel=.0005)
    rod((.009, .05, .045), (.009, .18, .046), .0055, .0055, STEEL(), seg=12)
    rod((.009, .18, .046), (.009, .19, .046), .004, .004, IRON(), seg=10, round_ends=True)
    box((0, .04, .072), (.004, .012, .004), IRON(), bevel=.0005)


def ripsaw():
    """A two-stroke saw motor with a stack of blades on its arbor."""
    blade = pbr("blade", (124, 128, 130), .25, 1., wear=(226, 226, 226), blotch=(84, 66, 54))
    housing = pbr("housing", (140, 54, 30), .6, 0., wear=(70, 70, 74), blotch=(100, 40, 24))
    pistol_grip(RUBBER())
    box((0, -.02, .05), (.082, .13, .072), housing, bevel=.012)
    rod((0, -.03, .086), (0, -.03, .135), .027, .027, IRON(), seg=28)
    for z in (.094, .104, .114, .124):
        rod((0, -.03, z), (0, -.03, z + .004), .034, .034, STEEL(), seg=28)
    rod((0, -.03, .135), (0, -.03, .152), .006, .006, pbr("plug", (226, 222, 210), .4), seg=10)
    rod((0, -.03, .152), (.02, -.05, .15), .0025, .0025, RUBBER(), seg=6)
    disc((-.046, -.02, .05), (-1, 0, 0), .032, .012, IRON(), seg=28)
    rod((-.052, -.02, .05), (-.08, -.03, .07), .003, .003, PAPER(), seg=6)
    rod((-.085, -.045, .07), (-.075, -.015, .07), .006, .006, RUBBER(), seg=10, round_ends=True)
    disc((.043, -.04, .07), (1, 0, 0), .016, .008, BRASS(), seg=20)
    rod((.03, -.07, .03), (.07, -.11, .02), .011, .013, IRON(), seg=14)
    box((0, .075, .05), (.03, .09, .026), IRON(), bevel=.004)
    tilt = Vector((1, 0, .12)).normalized()
    hub = Vector((0, .21, .075))
    for k in range(3):
        at = hub - tilt * (k * .009)
        disc(at, tilt, .094, .003, blade, seg=64)
        if k == 0:
            saw_teeth(at, tilt, .095, 30, blade)
    disc(hub + tilt * .006, tilt, .024, .012, BRASS(), seg=24)
    ball(hub + tilt * .014, .008, STEEL())
    u = tilt.orthogonal().normalized()
    v = tilt.cross(u)
    arc = [hub + tilt * .014 + (u * math.cos(a) + v * math.sin(a)) * .104
           for a in [math.radians(x) for x in range(100, 261, 16)]]
    for a, b in zip(arc, arc[1:]):
        rod(a, b, .007, .007, housing, seg=10, round_ends=True)
    rod((0, -.07, .09), (0, .04, .118), .007, .007, IRON(), seg=10, round_ends=True)


# ---------------------------------------------------------------- handles
# Held like the crowbar: the handle runs along +Y through the origin.
def slingblade():
    """A kaiser blade: taped hickory handle, riveted ferrule, hooked two-edged blade."""
    edge = pbr("edge", (92, 94, 96), .3, 1., wear=(214, 214, 214), blotch=(84, 56, 42))
    tape = pbr("tape", (30, 28, 28), .7, 0., bump=.5, scale=50.)
    rod((0, -.16, 0), (0, .34, 0), .0115, .0105, PALE(), seg=24, round_ends=True)
    rod((0, -.07, 0), (0, .06, 0), .0128, .0128, tape, seg=24)
    rod((0, .14, 0), (0, .17, 0), .0125, .0125, tape, seg=24)
    rod((0, .30, 0), (0, .39, 0), .014, .014, IRON(), seg=24)
    for y in (.32, .36):
        rod((-.016, y, 0), (.016, y, 0), .0035, .0035, BRASS(), seg=10)
    for k in range(22):
        t = k / 21
        y = .40 + t * .27
        z = .006 + (t ** 2) * .16
        box((0, y, z), (.005, .03, .078 - .052 * t), edge, rot=(.08 + 1.05 * t, 0, 0), bevel=.0015)
    box((0, .43, -.03), (.005, .05, .03), edge, rot=(-.5, 0, 0), bevel=.002)


def tnt():
    """One fat stick of dynamite with a taped blasting cap and a long fuse."""
    tape = pbr("tape", (30, 28, 28), .7, 0., bump=.5, scale=50.)
    rod((0, -.12, 0), (0, .15, 0), .0185, .0185, RED(), seg=28)
    for y in (-.122, .15):
        disc((0, y, 0), (0, 1, 0), .017, .005, PAPER(), seg=22)
    rod((0, .055, 0), (0, .11, 0), .019, .019, PAPER(), seg=28)
    for y in (.062, .082, .10):
        rod((0, y, 0), (0, y + .003, 0), .0193, .0193, pbr("ink", (60, 20, 16), .8), seg=28)
    rod((0, -.085, 0), (0, -.06, 0), .0196, .0196, tape, seg=28)
    rod((.012, .09, .016), (.012, .17, .016), .0045, .0045, BRASS(), seg=10)
    rod((0, .118, 0), (0, .132, 0), .0205, .0205, tape, seg=28)
    pts = [Vector((.012, .17, .016)), Vector((.02, .21, .04)), Vector((.0, .25, .05)), Vector((-.02, .27, .08)),
           Vector((-.01, .30, .11))]
    for a, b in zip(pts, pts[1:]):
        rod(a, b, .0026, .0026, PAPER(), seg=6)


# The 5v5 store's throwables, held like the dynamite: along the hand, the
# business end (fuse, rag, ring) out at +Y.
def _fuse(start, bend):
    pts = [Vector(start)] + [Vector(start) + Vector(b) for b in bend]
    for a, b in zip(pts, pts[1:]):
        rod(a, b, .0026, .0026, PAPER(), seg=6)


def flash_jar():
    """A quart mason jar packed with magnesium flash powder: zinc lid and band,
    a fuse through the lid, a paper label with a lightning bolt."""
    glass = pbr("jar_glass", (150, 186, 176), .06, 0., bump=.02)
    powder = pbr("flash_powder", (236, 236, 228), .5, 0., emit=.35)
    zinc = pbr("zinc", (150, 150, 146), .35, 1., wear=(200, 200, 196), blotch=(110, 104, 96))
    rod((0, -.08, 0), (0, .07, 0), .034, .034, glass, seg=40)
    rod((0, -.075, 0), (0, .05, 0), .03, .03, powder, seg=32)
    disc((0, -.082, 0), (0, -1, 0), .034, .004, glass, seg=40)
    rod((0, .07, 0), (0, .09, 0), .027, .027, glass, seg=32)
    rod((0, .085, 0), (0, .105, 0), .03, .03, zinc, seg=36)
    for y in (.088, .094, .1):
        ring((0, y, 0), (0, 1, 0), .0302, .0012, zinc, n=36)
    rod((0, -.02, .0), (0, .03, .0), .0345, .0345, PAPER(), seg=40)
    box((0, .005, .0352), (.012, .03, .001), pbr("bolt_ink", (180, 40, 30), .8), rot=(0, 0, .5), bevel=.0005)
    _fuse((0, .105, .006), [(.006, .03, .012), (-.004, .06, .03), (.004, .09, .05)])


def smudge_pot():
    """A gallon paint can turned smoke bomb: wire bail, a lid hammered on with a
    fuse and a pull ring, drips of grey paint, SMOKE stencilled on it."""
    tin = pbr("paint_can", (150, 152, 150), .4, .9, wear=(200, 200, 196), blotch=(120, 100, 80))
    paint = pbr("grey_paint", (120, 124, 120), .6, 0.)
    rod((0, -.07, 0), (0, .06, 0), .042, .042, tin, seg=44)
    for y in (-.068, .058):
        ring((0, y, 0), (0, 1, 0), .043, .003, tin, n=40)
    disc((0, .062, 0), (0, 1, 0), .04, .004, paint, seg=40)
    for k in range(5):
        a = k * 1.3
        box((math.cos(a) * .0425, .045 - k * .012, math.sin(a) * .0425), (.006, .03, .002), paint,
            rot=(0, a, 0), bevel=.001)
    box((0, -.01, .043), (.04, .02, .001), pbr("stencil", (30, 28, 26), .9), bevel=.0005)
    rod((-.042, .0, 0), (-.03, .0, .05), .0018, .0018, IRON(), seg=6)
    rod((.042, .0, 0), (.03, .0, .05), .0018, .0018, IRON(), seg=6)
    rod((-.03, .0, .05), (.03, .0, .05), .0018, .0018, IRON(), seg=6)
    ring((.015, .07, .0), (0, 1, 0), .009, .0018, IRON(), n=14)
    _fuse((-.01, .066, 0), [(.0, .03, .01), (-.01, .06, .025), (.0, .08, .045)])


def shine_cocktail():
    """A brown jug-glass bottle of moonshine with a rag stuffed in the neck,
    already lit: amber shine sloshing inside, an XXX label, the rag burning."""
    glass = pbr("bottle_glass", (110, 70, 34), .06, 0., bump=.02)
    shine = pbr("shine", (200, 150, 60), .2, 0., emit=.15)
    rag = pbr("rag", (170, 150, 120), .95, 0., bump=.8, scale=40.)
    flame = pbr("flame", (255, 170, 60), emit=6.0)
    rod((0, -.1, 0), (0, .03, 0), .031, .031, glass, seg=36)
    rod((0, -.095, 0), (0, -.01, 0), .027, .027, shine, seg=30)
    disc((0, -.102, 0), (0, -1, 0), .031, .004, glass, seg=36)
    rod((0, .03, 0), (0, .07, 0), .031, .012, glass, seg=36)
    rod((0, .07, 0), (0, .11, 0), .012, .012, glass, seg=24)
    rod((0, -.07, 0), (0, -.02, 0), .0315, .0315, PAPER(), seg=36)
    for k in range(3):
        box((-.01 + k * .01, -.045, .0318), (.006, .02, .001), pbr("xxx", (40, 20, 14), .8), rot=(0, 0, .7), bevel=.0003)
    rod((0, .1, 0), (0, .15, .01), .011, .013, rag, seg=14, round_ends=True)
    rod((0, .14, .01), (.02, .17, .02), .006, .004, rag, seg=10, round_ends=True)
    for k in range(4):
        a = k * 1.7
        rod((math.cos(a) * .006, .145, .01 + math.sin(a) * .006),
            (math.cos(a) * .012, .2 + k * .012, .03 + math.sin(a) * .01), .009, .001, flame, seg=10)


def firecracker_can():
    """A soup can wound round with a string of firecrackers, a bundle of fuses
    twisted together on top: it rattles off like a gunfight."""
    tin = pbr("soup_can", (170, 172, 170), .3, 1., wear=(210, 210, 206))
    label = pbr("soup_label", (170, 40, 34), .7, 0., wear=(220, 200, 180))
    cracker = pbr("cracker", (196, 40, 30), .7, 0.)
    rod((0, -.05, 0), (0, .05, 0), .03, .03, tin, seg=36)
    rod((0, -.035, 0), (0, .035, 0), .0305, .0305, label, seg=36)
    for y in (-.05, .05):
        ring((0, y, 0), (0, 1, 0), .031, .0025, tin, n=36)
    for k in range(9):
        a = k * math.tau / 9
        c = Vector((math.cos(a) * .036, .0, math.sin(a) * .036))
        rod(c + Vector((0, -.02, 0)), c + Vector((0, .02, 0)), .005, .005, cracker, seg=10)
    rod((0, .0, .0), (0, .0, .0), .001, .001, cracker, seg=6)
    for k in range(3):
        _fuse((.006 * k - .006, .05, .0), [(.0, .02, .006 * k), (.004, .045, .012 + .004 * k)])


# ---------------------------------------------------------------- carried
def bowling_ball():
    marble = pbr("marble", (22, 40, 100), .07, 0., blotch=(70, 104, 176), bump=.02, scale=7.)
    ball((0, 0, 0), .108, marble)
    for dx, dz in ((-.022, .05), (.022, .05), (0, .012)):
        v = Vector((dx, -.1, dz)).normalized()
        disc(v * .1066, v, .0135, .006, pbr("hole", (4, 4, 6), .9))
        ring(v * .1072, v, .0142, .0012, pbr("rim", (150, 160, 200), .2), n=14)
    ring((0, 0, 0), (0, .2, 1), .1083, .0016, pbr("gilt", (196, 160, 70), .3, .9), n=40)


def powder_keg():
    oak = pbr("oak", (104, 62, 34), .6, 0., grain=(56, 32, 18), wear=(150, 110, 70), scale=12.)
    for k in range(8):
        z0, z1 = -.11 + k * .0275, -.11 + (k + 1) * .0275
        r0 = .076 + .024 * math.sin((k / 8) * math.pi)
        r1 = .076 + .024 * math.sin(((k + 1) / 8) * math.pi)
        rod((0, 0, z0), (0, 0, z1), r0, r1, oak, seg=18)
    for z in (-.09, -.035, .035, .088):
        r = .078 + .024 * math.sin(((z + .11) / .22) * math.pi)
        rod((0, 0, z), (0, 0, z + .014), r + .0022, r + .0022, IRON(), seg=48)
        bolts((0, 0, z + .007), (0, 0, 1), r + .003, 3, .004, STEEL())
    disc((0, 0, .112), (0, 0, 1), .072, .006, oak)
    rod((.03, -.02, .112), (.03, -.02, .128), .012, .010, PALE(), seg=16)
    rod((.03, -.02, .128), (.045, -.04, .17), .003, .003, PAPER(), seg=6)
    rod((.045, -.04, .17), (.02, -.06, .2), .003, .003, PAPER(), seg=6)
    rod((0, -.1, .0), (0, -.115, .0), .012, .010, PALE(), seg=14)
    box((0, -.099, .045), (.07, .004, .03), PAPER(), bevel=.001)
    for s in (-1, 1):
        rod((s * .04, -.02, .115), (s * .02, -.02, .15), .005, .005, pbr("rope", (150, 126, 86), .95, bump=.9, scale=70.), seg=8, round_ends=True)
    rod((-.02, -.02, .15), (.02, -.02, .15), .005, .005, pbr("rope", (150, 126, 86), .95, bump=.9, scale=70.), seg=8, round_ends=True)


# name -> (builder, rig, foremost point)
WEAPONS = {
    "rifle": (rifle, "long", (0, .71, -.03)), "crossbow": (crossbow, "long", (0, .46, .0)),
    "cow_launcher": (cow_launcher, "long", (0, .72, -.04)), "bottle_launcher": (bottle_launcher, "long", (0, .91, -.03)),
    "armgun": (armgun, "pistol", (0, .39, .05)), "riveter": (riveter, "pistol", (0, .25, .05)),
    "pressure_gun": (pressure_gun, "pistol", (0, .33, .054)), "teat_gun": (teat_gun, "pistol", (0, .235, .05)),
    "ripsaw": (ripsaw, "pistol", (0, .30, .058)), "slingblade": (slingblade, "bar", (0, .68, .17)),
    "tnt": (tnt, "bar", (-.01, .30, .11)), "bowling_ball": (bowling_ball, "carry", (0, 0, .108)),
    "powder_keg": (powder_keg, "carry", (0, 0, .2)),
    "hunter": (hunter, "long", (0, .815, -.022)), "mower": (mower, "long", (0, .80, -.03)),
    "county45": (county45, "pistol", (0, .152, .05)), "star357": (star357, "pistol", (0, .272, .058)),
    "hogleg": (hogleg, "pistol", (0, .31, .062)), "riot_pump": (riot_pump, "long", (0, .64, -.016)),
    "tommy": (tommy, "long", (0, .605, -.02)), "grease_gun": (grease_gun, "pistol", (0, .275, .05)),
    "patrol_bar": (patrol_bar, "long", (0, .76, -.022)), "marksman": (marksman, "long", (0, .795, -.022)),
    "flash_jar": (flash_jar, "bar", (0, .2, .05)), "smudge_pot": (smudge_pot, "bar", (0, .15, .045)),
    "shine_cocktail": (shine_cocktail, "bar", (0, .24, .04)),
    "firecracker_can": (firecracker_can, "bar", (0, .1, .02)),
}
# Each rig reproduces the camera of one photographed plate, so that plate's hand
# drops onto the weapon at its own size. Values: focal length in plate pixels,
# then where the weapon's origin sits and how it is turned (pitch, yaw).
RIGS = {
    "pistol": (604., T((-.0083, -.11, -.005)) @ R(.60, 0, 1.05) @ Matrix.Scale(.72, 4)),   # the revolver plate
    "long": (462., T((.0216, -.26, -.0165)) @ R(.447, 0, .70)),       # the shotgun plate
    "bar": (604., T((.0516, .05, -.0516)) @ R(.54, 0, 1.20)),         # the crowbar plate
    "carry": (746., T((0, .37, -.016))),
}
# Big props brought down so their muzzle ends short of the crosshair, as the shotgun's does.
TRIM = {"cow_launcher": .74, "bottle_launcher": .86, "crossbow": .84, "hunter": .82, "mower": .84,
        "riot_pump": .92, "patrol_bar": .86, "marksman": .83, "county45": 1.15}
# Short things slid out along the hand so the fist does not swallow them.
SHIFT = {"smudge_pot": (0, .075, .0), "firecracker_can": (0, .09, .0), "flash_jar": (0, .03, .0)}
CANVAS = (1280, 896)        # the plate's 640x448 frame is the lower right quarter
PLATE_AT = (640, 448)


def stage():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 64
    scene.cycles.use_denoising = True
    scene.cycles.device = "CPU"
    scene.render.film_transparent = True
    scene.render.resolution_x, scene.render.resolution_y = CANVAS
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
    bg.inputs[0].default_value = (.60, .58, .54, 1)
    bg.inputs[1].default_value = .9
    nt.links.new(bg.outputs[0], out.inputs[0])
    for name, travel, power, color, spread in (("key", (.45, .35, -.82), 3.2, (1, .95, .86), 40),
                                               ("fill", (-.75, .45, -.3), 1.0, (.82, .88, 1), 60),
                                               ("kick", (-.3, -.8, -.35), 1.2, (1, .92, .8), 30)):
        light = bpy.data.lights.new(name, "SUN")
        light.energy = power
        light.color = color
        light.angle = math.radians(spread)
        ob = bpy.data.objects.new(name, light)
        ob.rotation_euler = Vector(travel).to_track_quat("-Z", "Y").to_euler()
        scene.collection.objects.link(ob)
    cam = bpy.data.cameras.new("cam")
    cam.clip_start = .004
    cam.sensor_width = 36.0
    # Keep the plate's optical centre (320, 224 of its frame) while widening the canvas up and left.
    cam.shift_x = -(PLATE_AT[0] + 320 - CANVAS[0] / 2) / CANVAS[0]
    cam.shift_y = (PLATE_AT[1] + 224 - CANVAS[1] / 2) / CANVAS[0]
    camera = bpy.data.objects.new("cam", cam)
    camera.location = (0, -.36, 0)
    camera.rotation_euler = (math.pi / 2, 0, 0)
    scene.collection.objects.link(camera)
    scene.camera = camera
    return scene, camera


def main():
    scene, camera = stage()
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "views.json")
    views = json.load(open(path)) if os.path.exists(path) else {}
    for name, (build, rig, front) in WEAPONS.items():
        if WANT and name not in WANT:
            continue
        doomed = list(PARTS)
        meshes = [ob.data for ob in doomed]
        PARTS.clear()
        bpy.data.batch_remove(doomed)
        bpy.data.batch_remove([me for me in meshes if me.users == 0])
        build()
        focal, model = RIGS[rig]
        model = model @ Matrix.Scale(TRIM.get(name, 1.0), 4)
        model = model @ T(SHIFT.get(name, (0, 0, 0)))
        for ob in PARTS:
            ob.matrix_world = model @ ob.matrix_world
        camera.data.lens = focal * 36.0 / CANVAS[0]
        bpy.context.view_layer.update()

        def screen(point):
            v = world_to_camera_view(scene, camera, model @ Vector(point))
            return [round(v.x * CANVAS[0], 1), round((1 - v.y) * CANVAS[1], 1)]

        views[name] = {"rig": rig, "grip": screen((0, 0, 0)), "front": screen(front)}
        scene.render.filepath = os.path.join(OUT, name + ".png")
        bpy.ops.render.render(write_still=True)
    json.dump(views, open(path, "w"), indent=1)


main()
