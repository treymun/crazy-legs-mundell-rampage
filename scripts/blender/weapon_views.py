"""Model and render the first-person weapons that are not photographed plates.

    blender -b -P scripts/blender/weapon_views.py -- <out dir> <names|all>

Writes <name>.png (640x448, transparent) and views.json with, per weapon, where
its grip point landed in the picture. scripts/build_weapon_views.py lays the
photographed hands from the shotgun, revolver and crowbar plates over those
grips and cuts the animation cels.

Each weapon is built so its grip sits at the origin and it points along +Y;
four camera rigs match the angle of the plate whose hand it borrows:
  pistol   the revolver's gripping hand        long    the shotgun's cupping hand
  bar      the crowbar's fist                  carry   two cupped hands below
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


# ---------------------------------------------------------------- weapons
def rifle():
    box((0, -.20, -.035), (.042, .34, .075), WOOD(), rot=(-.10, 0, 0), bevel=.014)
    box((0, .20, .0), (.040, .30, .042), WOOD(), bevel=.012)
    rod((0, -.12, .034), (0, .14, .034), .021, .021, STEEL())
    box((0, .0, .012), (.038, .24, .03), STEEL(), bevel=.006)
    box((.017, .02, .04), (.012, .07, .014), IRON(), bevel=.002)
    ball((0, -.12, .034), (.021, .012, .021), STEEL())
    rod((0, .12, .034), (0, .80, .034), .0105, .0095, STEEL())
    rod((0, .12, .012), (0, .52, .012), .008, .008, IRON())
    box((0, .03, -.055), (.022, .07, .09), IRON(), rot=(.12, 0, 0), bevel=.004)
    box((0, .775, .054), (.004, .012, .02), IRON(), bevel=.001)
    box((0, .10, .058), (.02, .02, .014), IRON(), bevel=.002)
    rod((.02, -.03, .04), (.05, -.04, .03), .005, .005, STEEL())
    ball((.056, -.042, .028), .011, IRON())
    ring((0, -.03, -.075), (1, 0, 0), .03, .004, IRON(), n=16)
    for y in (.09, .30):
        rod((-.022, y, 0), (.022, y, 0), .004, .004, BRASS())
    return (0, .22, -.02)


def crossbow():
    box((0, .05, -.01), (.045, .78, .05), WOOD(), bevel=.012)
    box((0, -.30, -.045), (.045, .20, .11), WOOD(), rot=(-.2, 0, 0), bevel=.016)
    box((0, .12, .02), (.016, .52, .012), STEEL(), bevel=.002)
    for s in (-1, 1):
        pts = [Vector((s * x, .42 - .22 * (x / .34) ** 2, .012)) for x in (0, .09, .18, .26, .34)]
        for a, b in zip(pts, pts[1:]):
            rod(a, b, .011 - .004 * (abs(a.x) / .34), .010 - .004 * (abs(b.x) / .34), STEEL(), seg=14, round_ends=True)
        rod(pts[-1], (0, -.06, .03), .0022, .0022, PAPER(), seg=6)
    box((0, .42, .012), (.07, .04, .034), IRON(), bevel=.004)
    ring((0, .47, -.01), (1, 0, 0), .035, .005, IRON(), n=16)
    box((0, -.06, .034), (.02, .03, .02), IRON(), bevel=.002)
    for k, x in enumerate((-.014, .014, 0)):
        z = .046 + (.022 if k == 2 else 0)
        rod((x, .06, z), (x, .34, z), .0125, .0125, RED(), seg=20)
        disc((x, .345, z), (0, 1, 0), .011, .004, PAPER(), seg=16)
    rod((0, .06, .068), (.03, -.01, .10), .002, .002, PAPER(), seg=6)
    for y in (.12, .28):
        ring((0, y, .052), (0, 1, 0), .03, .003, IRON(), n=14)
    return (0, .24, -.035)


def cow_launcher():
    hide = pbr("hide", (214, 206, 190), .8, 0., blotch=(34, 30, 28), scale=10.)
    rod((0, .02, .03), (0, .70, .03), .072, .078, IRON(), seg=48)
    ball((0, .02, .03), (.072, .045, .072), IRON())
    rod((0, .70, .03), (0, .74, .03), .084, .084, IRON(), seg=48)
    for y in (.08, .30, .52):
        rod((0, y, .03), (0, y + .025, .03), .080, .080, RUST(), seg=48)
    box((0, -.20, -.02), (.05, .40, .09), WOOD(), rot=(-.12, 0, 0), bevel=.016)
    box((0, .25, -.055), (.05, .22, .05), WOOD(), bevel=.014)
    rod((0, .18, .10), (0, .34, .10), .05, .07, hide, seg=32)
    ball((0, .72, .035), (.058, .06, .055), hide)
    ball((0, .775, .015), (.036, .03, .028), pbr("snout", (206, 150, 140), .6))
    for s in (-1, 1):
        rod((s * .04, .73, .075), (s * .085, .76, .115), .011, .003, pbr("horn", (214, 200, 160), .5), seg=12, round_ends=True)
        ball((s * .058, .715, .06), (.02, .008, .014), hide, rot=(0, s * .5, 0))
        ball((s * .022, .768, .05), .008, pbr("eye", (10, 10, 10), .1))
    rod((.074, .12, .06), (.11, .12, .10), .006, .006, BRASS(), round_ends=True)
    return (0, .26, -.07)


def bottle_launcher():
    glass = pbr("glass", (52, 86, 50), .12, 0., bump=.05)
    rod((0, -.02, .03), (0, .62, .03), .04, .04, STEEL(), seg=40)
    ball((0, -.02, .03), (.04, .028, .04), STEEL())
    rod((0, .62, .03), (0, .65, .03), .046, .046, IRON(), seg=40)
    for y in (.05, .34):
        rod((0, y, .03), (0, y + .03, .03), .045, .045, RUST(), seg=40)
    box((0, -.16, -.01), (.045, .30, .07), WOOD(), rot=(-.12, 0, 0), bevel=.014)
    box((0, .26, -.035), (.036, .11, .07), WOOD(), bevel=.012)
    rod((0, .60, .03), (0, .74, .03), .03, .028, glass, seg=28)
    rod((0, .74, .03), (0, .79, .03), .028, .011, glass, seg=28)
    rod((0, .79, .03), (0, .83, .03), .011, .011, glass, seg=16)
    rod((0, .83, .03), (0, .90, .03), .017, .002, RED(), seg=20)
    rod((0, .66, .058), (0, .96, .075), .003, .003, PALE(), seg=8)
    rod((.03, .0, .075), (.05, -.06, .10), .002, .002, PAPER(), seg=6)
    box((0, .10, .076), (.012, .05, .014), IRON(), bevel=.002)
    return (0, .26, -.07)


def armgun():
    flesh = pbr("carapace", (70, 92, 62), .28, .2, wear=(150, 170, 110), blotch=(46, 56, 44), bump=.9, scale=30.)
    vein = pbr("vein", (120, 60, 70), .35, 0., bump=.6)
    glow = pbr("glow", (120, 255, 140), emit=3.0)
    pistol_grip(flesh)
    for k in range(6):
        y = -.03 + k * .055
        ball((0, y, .05), (.052 - .004 * k, .04, .05 - .003 * k), flesh)
    for k in range(5):
        ring((0, -.005 + k * .055, .05), (0, 1, 0), .046 - .004 * k, .006, vein, n=18)
    rod((0, .26, .05), (0, .36, .05), .03, .022, flesh, seg=24)
    ball((0, .37, .05), .02, glow)
    for a in (math.pi / 2, math.pi * 7 / 6, math.pi * 11 / 6):
        base = Vector((math.cos(a) * .04, .24, .05 + math.sin(a) * .04))
        mid = Vector((math.cos(a) * .062, .36, .05 + math.sin(a) * .062))
        tip = Vector((math.cos(a) * .03, .46, .05 + math.sin(a) * .03))
        rod(base, mid, .014, .011, flesh, seg=14, round_ends=True)
        rod(mid, tip, .011, .003, pbr("claw", (190, 180, 140), .3), seg=14, round_ends=True)
    for s in (-1, 1):
        rod((s * .045, .0, .075), (s * .04, .2, .085), .008, .008, vein, seg=10, round_ends=True)
        ball((s * .05, .10, .04), .012, glow)
    return (0, .0, 0)


def riveter():
    paint = pbr("yellow", (160, 122, 36), .55, 0., wear=(70, 70, 74), blotch=(110, 84, 30))
    pistol_grip(RUBBER())
    rod((0, -.07, .055), (0, .16, .055), .048, .048, paint, seg=40)
    ball((0, -.07, .055), (.048, .032, .048), paint)
    rod((0, .16, .055), (0, .22, .055), .034, .028, STEEL(), seg=32)
    rod((0, .22, .055), (0, .33, .055), .016, .014, STEEL(), seg=24)
    rod((0, .33, .055), (0, .345, .055), .02, .02, IRON(), seg=24)
    for y in (-.03, .12):
        rod((0, y, .055), (0, y + .016, .055), .051, .051, IRON(), seg=40)
    box((0, .10, -.02), (.026, .16, .05), IRON(), bevel=.004)
    for k in range(6):
        rod((.0, .03 + k * .026, -.05), (0, .03 + k * .026, -.072), .006, .006, STEEL(), seg=10)
    rod((0, -.05, -.11), (.03, -.10, -.22), .011, .011, RUBBER(), seg=14, round_ends=True)
    rod((0, -.05, -.105), (0, -.05, -.125), .015, .015, BRASS(), seg=16)
    box((0, .02, .11), (.012, .09, .014), IRON(), bevel=.002)
    return (0, 0, 0)


def pressure_gun():
    pistol_grip(WOOD())
    rod((0, -.08, .06), (0, .18, .06), .05, .05, COPPER(), seg=44)
    ball((0, -.08, .06), (.05, .035, .05), COPPER())
    rod((0, .18, .06), (0, .24, .06), .05, .026, COPPER(), seg=44)
    rod((0, .24, .06), (0, .40, .06), .02, .017, BRASS(), seg=28)
    rod((0, .40, .06), (0, .43, .06), .017, .028, BRASS(), seg=28)
    for y in (-.03, .06, .15):
        rod((0, y, .06), (0, y + .012, .06), .0525, .0525, BRASS(), seg=44)
        for k in range(10):
            a = k * math.tau / 10
            ball((math.cos(a) * .0535, y + .006, .06 + math.sin(a) * .0535), .004, BRASS())
    rod((0, .02, .11), (0, .02, .135), .008, .008, BRASS(), seg=12)
    disc((0, .02, .16), (0, -1, .25), .032, .014, BRASS())
    disc((0, .0125, .162), (0, -1, .25), .026, .004, pbr("dial", (214, 206, 180), .4))
    rod((0, .008, .163), (.012, .006, .178), .0015, .0015, pbr("needle", (150, 20, 20), .4), seg=6)
    rod((0, .11, .11), (0, .11, .13), .006, .006, BRASS(), seg=10)
    ring((0, .11, .135), (0, 0, 1), .024, .004, pbr("valve", (140, 36, 30), .5, .3), n=16)
    for a in (0, math.pi / 2):
        rod((math.cos(a) * -.024, .11 - math.sin(a) * .024, .135), (math.cos(a) * .024, .11 + math.sin(a) * .024, .135), .003, .003, IRON(), seg=6)
    rod((.03, -.05, .02), (.035, .16, .03), .007, .007, COPPER(), seg=10, round_ends=True)
    return (0, 0, 0)


def teat_gun():
    udder = pbr("udder", (216, 150, 146), .42, 0., bump=.5, blotch=(228, 176, 168), scale=16.)
    can = pbr("can", (120, 126, 130), .4, 1., wear=(190, 190, 186), blotch=(90, 80, 70))
    pistol_grip(WOOD())
    rod((0, -.08, .06), (0, .12, .06), .052, .052, can, seg=44)
    rod((0, -.10, .06), (0, -.08, .06), .04, .052, can, seg=44)
    for y in (-.05, .09):
        rod((0, y, .06), (0, y + .012, .06), .055, .055, IRON(), seg=44)
    ball((0, .16, .06), (.062, .075, .06), udder)
    for dx, dz in ((-.028, .028), (.028, .028), (-.028, -.022), (.028, -.022)):
        rod((dx, .20, .06 + dz), (dx * 1.25, .30, .06 + dz * 1.2), .016, .012, udder, seg=18, round_ends=True)
        ball((dx * 1.25, .31, .06 + dz * 1.2), .008, pbr("tip", (190, 110, 110), .4))
    ring((0, -.02, .125), (1, 0, 0), .028, .004, IRON(), n=16)
    rod((.05, .0, .03), (.06, .12, .04), .006, .006, RUBBER(), seg=10, round_ends=True)
    return (0, 0, 0)


def ripsaw():
    blade = pbr("blade", (120, 124, 126), .25, 1., wear=(220, 220, 220), blotch=(84, 70, 60))
    housing = pbr("housing", (130, 60, 34), .6, 0., wear=(70, 70, 74), blotch=(100, 44, 28))
    pistol_grip(RUBBER())
    box((0, .03, .05), (.085, .19, .075), housing, bevel=.012)
    rod((-.055, .0, .05), (.055, .0, .05), .034, .034, IRON(), seg=28)
    box((0, .16, .05), (.03, .10, .03), IRON(), bevel=.004)
    tilt = Vector((.18, 0, 1)).normalized()
    disc((0, .30, .06), tilt, .125, .004, blade, seg=64)
    disc((0, .30, .06), tilt, .03, .012, IRON())
    u = tilt.orthogonal().normalized()
    v = tilt.cross(u)
    for k in range(28):
        a = k * math.tau / 28
        at = Vector((0, .30, .06)) + (u * math.cos(a) + v * math.sin(a)) * .128
        out = (u * math.cos(a + .35) + v * math.sin(a + .35))
        rod(at, at + out * .014, .006, .001, blade, seg=6)
    rod((0, -.06, .09), (0, .06, .12), .007, .007, IRON(), seg=10, round_ends=True)
    rod((.03, -.05, .02), (.06, -.12, -.06), .006, .006, RUBBER(), seg=10, round_ends=True)
    return (0, 0, 0)


def slingblade():
    rod((0, -.12, 0), (0, .38, 0), .017, .015, PALE(), seg=24, round_ends=True)
    rod((0, .33, 0), (0, .42, 0), .019, .019, IRON(), seg=24)
    edge = pbr("edge", (96, 98, 100), .3, 1., wear=(210, 210, 210), blotch=(84, 58, 44))
    box((0, .52, .0), (.006, .22, .085), edge, rot=(0, 0, 0), bevel=.002)
    box((0, .65, .045), (.006, .10, .05), edge, rot=(.9, 0, 0), bevel=.002)
    box((0, .68, .10), (.006, .09, .035), edge, rot=(1.5, 0, 0), bevel=.002)
    for y in (.36, .40):
        rod((-.021, y, 0), (.021, y, 0), .004, .004, BRASS(), seg=10)
    return (0, 0, 0)


def tnt():
    for dx, dz in ((0, .0), (.027, .0), (.0135, .023)):
        rod((dx - .0135, -.10, dz - .008), (dx - .0135, .16, dz - .008), .013, .013, RED(), seg=24)
        disc((dx - .0135, .162, dz - .008), (0, 1, 0), .012, .004, PAPER(), seg=20)
    for y in (-.05, .10):
        rod((0, y, 0), (0, y + .02, 0), .031, .031, pbr("tape", (40, 38, 36), .6), seg=28)
    rod((0, .16, .02), (.02, .23, .05), .0025, .0025, PAPER(), seg=6)
    rod((.02, .23, .05), (.0, .28, .07), .0025, .0025, PAPER(), seg=6)
    return (0, 0, 0)


def bowling_ball():
    marble = pbr("marble", (26, 44, 104), .08, 0., blotch=(60, 96, 170), bump=.02, scale=9.)
    ball((0, 0, 0), .108, marble)
    for dx, dz in ((-.022, .05), (.022, .05), (0, .012)):
        v = Vector((dx, -.1, dz)).normalized()
        disc(v * .1065, v, .0135, .006, pbr("hole", (4, 4, 6), .9))
    return (0, 0, -.09)


def powder_keg():
    for k in range(7):
        z0, z1 = -.11 + k * .0315, -.11 + (k + 1) * .0315
        r0 = .078 + .022 * math.sin((k / 7) * math.pi)
        r1 = .078 + .022 * math.sin(((k + 1) / 7) * math.pi)
        rod((0, 0, z0), (0, 0, z1), r0, r1, WOOD(), seg=48)
    for z in (-.085, -.03, .04, .09):
        r = .08 + .022 * math.sin(((z + .11) / .22) * math.pi)
        rod((0, 0, z), (0, 0, z + .014), r + .002, r + .002, IRON(), seg=48)
    disc((0, 0, .112), (0, 0, 1), .074, .006, PALE())
    rod((0, 0, .112), (0, 0, .13), .012, .010, PALE(), seg=16)
    rod((0, 0, .13), (.02, -.02, .17), .003, .003, PAPER(), seg=6)
    rod((.02, -.02, .17), (.0, -.04, .20), .003, .003, PAPER(), seg=6)
    box((0, -.098, .005), (.07, .004, .03), PAPER(), bevel=.001)
    return (0, 0, -.12)


# The foremost point of each weapon (its muzzle, blade tip or top), in its own space.
FRONT = {"rifle": (0, .80, .034), "crossbow": (0, .46, .03), "cow_launcher": (0, .76, .03),
         "bottle_launcher": (0, .90, .03), "armgun": (0, .46, .05), "riveter": (0, .345, .055),
         "pressure_gun": (0, .43, .06), "teat_gun": (0, .32, .06), "ripsaw": (0, .42, .06),
         "slingblade": (0, .70, .12), "tnt": (0, .28, .07), "bowling_ball": (0, 0, .108),
         "powder_keg": (0, 0, .20)}
# name -> (builder, rig)
# Long guns held at the wrist of the stock sit forward of their own origin (see SEAT).
SEAT = {"rifle": (0, .13, .035), "cow_launcher": (0, .06, .07), "bottle_launcher": (0, .06, .035)}
WEAPONS = {"rifle": (rifle, "pistol"), "crossbow": (crossbow, "long"), "cow_launcher": (cow_launcher, "pistol"),
           "bottle_launcher": (bottle_launcher, "pistol"), "armgun": (armgun, "pistol"), "riveter": (riveter, "pistol"),
           "pressure_gun": (pressure_gun, "pistol"), "teat_gun": (teat_gun, "pistol"), "ripsaw": (ripsaw, "pistol"),
           "slingblade": (slingblade, "bar"), "tnt": (tnt, "bar"), "bowling_ball": (bowling_ball, "carry"),
           "powder_keg": (powder_keg, "carry")}
# rig -> (lens mm, model matrix); the camera sits behind the origin looking along +Y
RIGS = {
    "pistol": (34, T((.0834, .06, -.0737)) @ R(.28, 0, .50)),
    "long": (26, T((-.0322, -.0763, -.073)) @ R(.05, 0, .20)),
    "bar": (34, T((.113, .26, -.109)) @ R(.45, 0, .90)),
    "carry": (42, T((0, .37, -.016))),
}


def stage():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 64
    scene.cycles.use_denoising = True
    scene.cycles.device = "CPU"
    scene.render.film_transparent = True
    scene.render.resolution_x = 640
    scene.render.resolution_y = 448
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
    # An overcast yard: a broad soft key from the upper left, a cool fill, a low warm kicker.
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
    camera = bpy.data.objects.new("cam", cam)
    scene.collection.objects.link(camera)
    scene.camera = camera
    return scene, camera


def main():
    scene, camera = stage()
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "views.json")
    views = json.load(open(path)) if os.path.exists(path) else {}
    for name, (build, rig) in WEAPONS.items():
        if WANT and name not in WANT:
            continue
        doomed = list(PARTS)
        meshes = [ob.data for ob in doomed]
        PARTS.clear()
        bpy.data.batch_remove(doomed)
        bpy.data.batch_remove([me for me in meshes if me.users == 0])
        support = Vector(build())
        lens, model = RIGS[rig]
        if name in SEAT:
            pistol_grip()
            model = model @ T(SEAT[name])
            for ob in PARTS[-3:]:
                ob.matrix_world = T(SEAT[name]).inverted() @ ob.matrix_world
        for ob in PARTS:
            ob.matrix_world = model @ ob.matrix_world
        camera.data.lens = lens
        camera.location = (0, -.36, 0)
        camera.rotation_euler = (math.pi / 2, 0, 0)
        bpy.context.view_layer.update()

        def screen(point):
            v = world_to_camera_view(scene, camera, model @ Vector(point))
            return [round(v.x * 640, 1), round((1 - v.y) * 448, 1)]

        seat = Vector(SEAT.get(name, (0, 0, 0)))
        views[name] = {"rig": rig, "grip": screen(-seat), "support": screen(support),
                       "front": screen(FRONT[name])}
        scene.render.filepath = os.path.join(OUT, name + ".png")
        bpy.ops.render.render(write_still=True)
    json.dump(views, open(path, "w"), indent=1)


main()
