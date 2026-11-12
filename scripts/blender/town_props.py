"""Model and render Hickston's props in Blender: the things a hick town leaves
lying about, each built from plain shapes and rendered once, three-quarters
on, as the sprite the game stands up in the world.

    blender -b -P scripts/blender/town_props.py -- <out dir> <names|all> [supersample]

Writes <out dir>/<name>.png oversized, with a margin, and meta.json ({name:
[canvas width, canvas height, px per unit]}, in map units: a door is 1.85
tall); godot/tools/art/build_town_props.gd crops and shrinks them into
assets/art as town_<name>.png and notes their size in town_props.json.
Everything is modelled here from scratch; nothing is traced from another game.
"""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Euler, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:]
OUT, NAMES = os.path.abspath(ARGS[0]), ARGS[1]
SS = int(ARGS[2]) if len(ARGS) > 2 else 4
PPU = 60.0
ROOT = None
MATS = {}


# ---------------------------------------------------------------- materials
def lin(c):
    c /= 255.0
    return c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4


def mat(r, g, b, rough=.85, metal=0., emit=0., grime=.4, planks=0., check=None):
    """A worn surface: its colour, darkened in blotches by `grime`; `planks`
    bands it like boards; `check` (r, g, b) crosses it with a plaid."""
    key = (r, g, b, rough, metal, emit, grime, planks, check)
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
    dark = (lin(r) * .45, lin(g) * .42, lin(b) * .4, 1)
    coord = nt.nodes.new("ShaderNodeTexCoord")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 7.0
    nt.links.new(coord.outputs["Object"], noise.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = .5 - grime * .35
    ramp.color_ramp.elements[1].position = .5 + grime * .2
    ramp.color_ramp.elements[0].color = dark
    ramp.color_ramp.elements[1].color = base
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    colour = ramp.outputs["Color"]
    if planks > 0:
        wave = nt.nodes.new("ShaderNodeTexWave")
        wave.inputs["Scale"].default_value = planks
        wave.inputs["Distortion"].default_value = 2.0
        nt.links.new(coord.outputs["Object"], wave.inputs["Vector"])
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = .45
        nt.links.new(colour, mix.inputs["A"])
        nt.links.new(wave.outputs["Color"], mix.inputs["B"])
        colour = mix.outputs["Result"]
    if check is not None:
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(coord.outputs["Object"], sep.inputs[0])
        stripes = []
        for axis in ("X", "Z"):
            w = nt.nodes.new("ShaderNodeTexWave")
            w.wave_profile = "SAW"
            w.inputs["Scale"].default_value = 6.0
            w.bands_direction = axis
            nt.links.new(coord.outputs["Object"], w.inputs["Vector"])
            stripes.append(w)
        both = nt.nodes.new("ShaderNodeMath")
        both.operation = "MULTIPLY"
        nt.links.new(stripes[0].outputs["Fac"], both.inputs[0])
        nt.links.new(stripes[1].outputs["Fac"], both.inputs[1])
        step = nt.nodes.new("ShaderNodeMath")
        step.operation = "GREATER_THAN"
        step.inputs[1].default_value = .25
        nt.links.new(both.outputs[0], step.inputs[0])
        mix2 = nt.nodes.new("ShaderNodeMix")
        mix2.data_type = "RGBA"
        nt.links.new(step.outputs[0], mix2.inputs["Factor"])
        nt.links.new(colour, mix2.inputs["A"])
        mix2.inputs["B"].default_value = (lin(check[0]), lin(check[1]), lin(check[2]), 1)
        colour = mix2.outputs["Result"]
    nt.links.new(colour, bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit > 0:
        bsdf.inputs["Emission Color"].default_value = base
        bsdf.inputs["Emission Strength"].default_value = emit
    MATS[key] = m
    return m


WOOD = (112, 82, 54)
GREY_WOOD = (118, 110, 96)
RUST = (128, 62, 34)
TIRE = (30, 28, 27)
STRAW = (198, 166, 92)
CHROME = (180, 182, 186)


# ------------------------------------------------------------------- shapes
def place(bm, m, loc, rot, scale=(1, 1, 1)):
    me = bpy.data.meshes.new("me")
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = False
    ob = bpy.data.objects.new("ob", me)
    bpy.context.scene.collection.objects.link(ob)
    ob.data.materials.append(m)
    ob.parent = ROOT
    ob.location = loc
    ob.rotation_euler = Euler([math.radians(a) for a in rot])
    ob.scale = scale
    return ob


def box(sx, sy, sz, loc, m, rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    return place(bm, m, loc, rot, (sx, sy, sz))


def cyl(r, h, loc, m, rot=(0, 0, 0), seg=18, top=None):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r,
                          radius2=r if top is None else top, depth=h)
    return place(bm, m, loc, rot)


def ball(r, loc, m, scale=(1, 1, 1), rot=(0, 0, 0), seg=16):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=seg // 2 + 2, radius=r)
    ob = place(bm, m, loc, rot, scale)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def wheel(r, width, loc, rim, rot=(0, 90, 0)):
    cyl(r, width, loc, mat(*TIRE, rough=.95, grime=.2), rot, seg=24)
    side = 1 if rot[1] else 0
    off = Vector((width * .52, 0, 0)) if side else Vector((0, width * .52, 0))
    for s in (1, -1):
        cyl(r * .55, .02, Vector(loc) + off * s, rim, rot, seg=16)


# -------------------------------------------------------------------- props
def outhouse():
    planks = mat(*GREY_WOOD, planks=9.0, grime=.55)
    box(.92, .9, 2.0, (0, 0, 1.0), planks)
    box(1.12, 1.1, .08, (0, -.04, 2.06), mat(92, 86, 80, metal=.4, grime=.7), (11, 0, 0))
    box(.62, .04, 1.62, (0, -.47, .86), mat(*WOOD, planks=7.0, grime=.5))
    # The moon cut in the door, dark behind.
    ball(.09, (0, -.5, 1.42), mat(18, 14, 12, grime=0), (1, .3, 1))
    ball(.085, (.045, -.52, 1.44), mat(*WOOD, planks=7.0), (1, .3, 1))
    box(.05, .06, .05, (.24, -.5, .9), mat(*CHROME, metal=.8, grime=.6))
    box(.3, .02, .2, (0, -.47, 1.85), mat(220, 210, 180, grime=.6))
    ROOT.rotation_euler = Euler((0, math.radians(3), 0))
    return 1.3, 2.3


def scarecrow():
    post = mat(*WOOD, planks=4.0)
    cyl(.05, 2.0, (0, 0, 1.0), post, seg=8)
    box(1.36, .07, .07, (0, 0, 1.46), post)
    shirt = mat(150, 40, 34, check=(40, 30, 28), grime=.35)
    box(.46, .26, .62, (0, -.02, 1.2), shirt)
    for s in (1, -1):
        cyl(.1, .5, (s * .44, -.02, 1.46), shirt, (0, 90, 0), seg=10)
        for k in range(3):
            cyl(.03, .16, (s * (.72 + k * .02), -.02 + (k - 1) * .05, 1.44), mat(*STRAW), (0, 90 + s * (k - 1) * 20, 0), seg=5, top=.005)
    for k in range(5):
        cyl(.03, .2, (-.16 + k * .08, -.02, .82), mat(*STRAW), (180 + (k - 2) * 8, 0, 0), seg=5, top=.004)
    cyl(.18, .4, (0, -.02, .78), mat(70, 74, 110, grime=.5), seg=10)
    head = mat(176, 148, 102, grime=.5)
    ball(.2, (0, -.02, 1.72), head, (1, .9, 1.05))
    for s in (1, -1):
        box(.05, .02, .05, (s * .07, -.2, 1.76), mat(14, 12, 10, grime=0), (0, 45, 0))
    for k in range(5):
        box(.035, .02, .01, (-.08 + k * .04, -.2, 1.64), mat(30, 22, 18, grime=0), (0, (k % 2) * 40 - 20, 0))
    hat = mat(160, 128, 70, grime=.5)
    cyl(.34, .03, (0, -.02, 1.9), hat, seg=20)
    cyl(.16, .2, (0, -.02, 2.0), hat, seg=16, top=.14)
    # A crow that does not care.
    crow = mat(20, 20, 24, grime=.1)
    ball(.08, (.55, 0, 1.56), crow, (1.5, 1, 1))
    ball(.05, (.66, -.02, 1.6), crow)
    cyl(.02, .07, (.72, -.02, 1.6), mat(170, 150, 60), (0, 90, 0), seg=6, top=.002)
    return 1.6, 2.1


def tractor():
    paint = mat(150, 46, 30, metal=.3, rough=.6, grime=.75)
    rim = mat(196, 170, 90, metal=.4, grime=.6)
    box(1.5, .62, .5, (-.1, 0, .72), paint)
    box(1.0, .58, .44, (.38, 0, 1.08), paint, (0, -4, 0))
    box(.3, .62, .5, (.95, 0, .9), mat(60, 58, 56, metal=.6, grime=.6))
    cyl(.05, .7, (.62, .12, 1.55), mat(26, 24, 22, metal=.5), seg=8)
    box(.4, .44, .1, (-.5, 0, 1.12), mat(40, 36, 30))
    box(.06, .44, .4, (-.72, 0, 1.3), mat(40, 36, 30))
    cyl(.16, .02, (-.2, 0, 1.4), mat(30, 30, 30), (0, -50, 0), seg=14)
    for s in (1, -1):
        wheel(.6, .3, (-.55, s * .5, .6), rim, (90, 0, 0))
        wheel(.32, .18, (.8, s * .42, .32), rim, (90, 0, 0))
        box(.7, .06, .32, (-.55, s * .66, 1.1), paint)
    ROOT.rotation_euler = Euler((0, 0, math.radians(90)))
    return 2.4, 1.75


def hay_wagon():
    bed = mat(*GREY_WOOD, planks=8.0, grime=.5)
    box(2.2, 1.1, .1, (0, 0, .55), bed)
    for s in (1, -1):
        box(2.2, .05, .3, (0, s * .55, .72), bed)
        for x in (-.75, .75):
            wheel(.3, .12, (x, s * .5, .3), mat(*RUST, metal=.4), (90, 0, 0))
    box(.9, .06, .06, (1.5, 0, .45), mat(*RUST, metal=.4))
    hay = mat(*STRAW, planks=30.0, grime=.35)
    for i, (x, y, z) in enumerate([(-.6, -.25, .78), (0, -.25, .78), (.6, -.25, .78), (-.6, .25, .78),
                                    (0, .25, .78), (.6, .25, .78), (-.3, 0, 1.08), (.3, 0, 1.08)]):
        box(.56, .44, .3, (x, y, z), hay, (0, 0, (i * 37) % 9 - 4))
    ROOT.rotation_euler = Euler((0, 0, math.radians(90)))
    return 2.6, 1.4


def picnic_table():
    wood = mat(*GREY_WOOD, planks=12.0, grime=.55)
    box(1.5, .7, .05, (0, 0, .72), wood)
    for s in (1, -1):
        box(1.5, .26, .04, (0, s * .58, .42), wood)
        for x in (-.55, .55):
            box(.06, .06, .78, (x, s * .2, .37), wood, (s * 24, 0, 0))
    box(.18, .12, .12, (.3, 0, .8), mat(178, 30, 26, metal=.5, rough=.4))
    box(.07, .07, .14, (-.2, .1, .82), mat(70, 120, 60, rough=.2))
    ROOT.rotation_euler = Euler((0, 0, math.radians(90)))
    return 1.7, .95


def washer():
    shell = mat(214, 210, 196, rough=.5, grime=.7)
    box(.66, .6, .86, (0, 0, .43), shell)
    cyl(.2, .03, (0, -.31, .45), mat(30, 34, 40, rough=.1, metal=.3), (90, 0, 0), seg=20)
    cyl(.24, .02, (0, -.305, .45), mat(*CHROME, metal=.8), (90, 0, 0), seg=20)
    box(.66, .12, .14, (0, .24, .93), shell)
    for x in (-.18, 0, .18):
        cyl(.03, .03, (x, .17, .95), mat(30, 30, 30), (90, 0, 0), seg=8)
    ROOT.rotation_euler = Euler((0, math.radians(6), 0))
    return .95, 1.05


def fridge():
    shell = mat(150, 160, 84, rough=.45, grime=.75)
    box(.74, .66, 1.6, (0, 0, .8), shell)
    box(.76, .02, .01, (0, -.335, 1.12), mat(30, 30, 30))
    box(.04, .05, .34, (.3, -.36, 1.34), mat(*CHROME, metal=.9, rough=.25))
    box(.04, .05, .5, (.3, -.36, .74), mat(*CHROME, metal=.9, rough=.25))
    ROOT.rotation_euler = Euler((math.radians(-4), math.radians(-3), 0))
    return 1.0, 1.75


def dish():
    metal = mat(170, 172, 168, metal=.5, rough=.5, grime=.6)
    cyl(.04, 1.0, (0, .2, .5), metal, seg=8)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=24, radius1=.62, radius2=.06, depth=.22)
    place(bm, mat(196, 194, 186, rough=.5, grime=.55), (0, 0, 1.05), (-62, 0, 0))
    cyl(.015, .6, (0, -.25, 1.15), metal, (-30, 0, 0), seg=6)
    box(.06, .1, .06, (0, -.5, 1.28), mat(40, 40, 44))
    return 1.4, 1.55


def flamingo():
    pink = mat(236, 104, 150, rough=.35, grime=.25)
    ball(.16, (0, 0, .5), pink, (1.6, .8, .9))
    for k in range(6):
        t = k / 5.0
        ball(.04, (-.18 - math.sin(t * 2.4) * .06, 0, .56 + t * .3), pink)
    ball(.06, (-.2, 0, .9), pink)
    cyl(.03, .1, (-.26, 0, .88), mat(20, 20, 20), (0, -110, 0), seg=6, top=.005)
    for x in (-.02, .06):
        cyl(.008, .5, (x, 0, .2), mat(60, 60, 60, metal=.6), seg=4)
    return .7, 1.0


def still():
    copper = mat(184, 104, 58, metal=.85, rough=.32, grime=.55)
    brick = mat(140, 70, 50, grime=.6, planks=14.0)
    box(.7, .7, .36, (-.25, 0, .18), brick)
    box(.36, .02, .14, (-.25, -.36, .17), mat(255, 120, 40, emit=4.0, grime=0))
    ball(.36, (-.25, 0, .66), copper, (1, 1, .9))
    cyl(.18, .3, (-.25, 0, 1.06), copper, top=.06, seg=16)
    cyl(.03, .7, (.1, 0, 1.12), copper, (0, 70, 0), seg=8)
    barrel = mat(*WOOD, planks=10.0, grime=.5)
    cyl(.26, .62, (.48, 0, .31), barrel, seg=16)
    for k in range(4):
        cyl(.2, .03, (.48, 0, .7 + k * .08), copper, seg=14)
    cyl(.02, .3, (.48, 0, 1.0), copper, seg=6)
    for k, x in enumerate((-.7, -.58)):
        cyl(.07, .26, (x, -.25 + k * .1, .13), mat(220, 216, 200, rough=.3), seg=10, top=.03)
    return 1.6, 1.4


def skull_post():
    cyl(.06, 1.1, (0, 0, .55), mat(*GREY_WOOD, planks=4.0, grime=.6), seg=8)
    bone = mat(226, 216, 190, grime=.45)
    ball(.16, (0, -.08, 1.18), bone, (.75, .7, 1.2))
    ball(.1, (0, -.14, .98), bone, (.7, .7, 1.0))
    for s in (1, -1):
        ball(.04, (s * .06, -.2, 1.2), mat(20, 16, 14, grime=0))
        cyl(.05, .3, (s * .24, -.06, 1.3), bone, (0, s * 70, 0), seg=8, top=.01)
    return .8, 1.45


def rocker():
    wood = mat(*WOOD, planks=6.0, grime=.5)
    box(.5, .46, .05, (0, 0, .46), wood)
    box(.5, .05, .62, (0, .22, .8), wood, (-8, 0, 0))
    for s in (1, -1):
        for y in (-.18, .18):
            box(.04, .04, .46, (s * .22, y, .23), wood)
        box(.04, .9, .05, (s * .22, 0, .05), wood)
        box(.04, .4, .04, (s * .24, -.02, .66), wood)
    ROOT.rotation_euler = Euler((0, 0, math.radians(-30)))
    return .9, 1.15


def grill():
    black = mat(36, 34, 32, metal=.5, rough=.6, grime=.5)
    cyl(.3, .9, (0, 0, .78), black, (0, 90, 0), seg=18)
    box(.9, .44, .04, (0, 0, .82), mat(255, 110, 40, emit=2.5, grime=0))
    box(.9, .3, .3, (0, .12, 1.0), black, (30, 0, 0))
    cyl(.06, .4, (.38, .1, 1.18), black, seg=8)
    for x in (-.35, .35):
        for y in (-.2, .2):
            box(.04, .04, .6, (x, y, .3), black)
    return 1.1, 1.4


def tombstone_a():
    stone = mat(130, 132, 128, grime=.6)
    box(.48, .14, .5, (0, 0, .25), stone)
    cyl(.24, .14, (0, 0, .5), stone, (90, 0, 0), seg=20)
    box(.24, .01, .02, (0, -.075, .52), mat(60, 60, 58))
    box(.3, .01, .02, (0, -.075, .44), mat(60, 60, 58))
    box(.2, .01, .02, (0, -.075, .38), mat(60, 60, 58))
    ROOT.rotation_euler = Euler((math.radians(-5), math.radians(4), 0))
    return .7, .85


def tombstone_b():
    stone = mat(146, 144, 136, grime=.6)
    box(.1, .1, .8, (0, 0, .4), stone)
    box(.44, .1, .1, (0, 0, .58), stone)
    box(.36, .3, .1, (0, 0, .05), mat(110, 112, 106, grime=.6))
    ROOT.rotation_euler = Euler((0, math.radians(8), 0))
    return .6, .9


def tombstone_c():
    stone = mat(118, 126, 116, grime=.8)
    box(.56, .12, .62, (0, 0, .3), stone, (-12, 0, 6))
    for k in range(4):
        ball(.06, (-.2 + k * .12, -.05, .12 + (k % 2) * .2), mat(70, 96, 52, grime=.4))
    return .75, .8


def saucer_wreck():
    hull = mat(150, 158, 164, metal=.75, rough=.35, grime=.55)
    ball(1.9, (0, 0, .55), hull, (1, 1, .2))
    cyl(1.95, .08, (0, 0, .55), mat(90, 96, 104, metal=.8, grime=.5), seg=40)
    ball(.7, (0, 0, .8), mat(110, 220, 150, rough=.1, emit=.6, grime=.2), (1, 1, .7))
    for k in range(10):
        a = k / 10 * math.tau
        ball(.07, (math.cos(a) * 1.85, math.sin(a) * 1.85, .58), mat(120, 255, 140, emit=5.0, grime=0))
    box(.9, .1, .5, (1.1, .4, .9), hull, (20, -30, 40))
    ROOT.rotation_euler = Euler((math.radians(16), math.radians(-10), 0))
    ROOT.location = Vector((0, 0, -.2))
    ball(2.1, (0, 0, -.7), mat(92, 70, 48, grime=.6), (1, 1, .32))
    return 5.0, 2.2


def pylon():
    metal = mat(80, 92, 96, metal=.8, rough=.3, grime=.4)
    cyl(.16, 1.3, (0, 0, .65), metal, seg=6, top=.06)
    cyl(.22, .08, (0, 0, .06), metal, seg=6)
    cyl(.12, .04, (0, 0, .9), mat(120, 255, 150, emit=4.0, grime=0), seg=12)
    ball(.12, (0, 0, 1.42), mat(150, 255, 170, emit=6.0, grime=0))
    return .6, 1.6


def safe_open():
    iron = mat(34, 36, 34, metal=.6, rough=.45, grime=.5)
    box(.62, .58, .78, (0, 0, .39), iron)
    box(.5, .02, .62, (0, -.29, .42), mat(150, 110, 40, emit=.6, grime=.3))
    box(.06, .58, .66, (-.34, -.3, .42), iron, (0, 0, 60))
    cyl(.08, .03, (-.4, -.6, .5), mat(*CHROME, metal=.9), (90, 0, 60), seg=12)
    box(.5, .02, .03, (.0, .2, .82), mat(196, 160, 60, metal=.8))
    return .95, .9


def strongbox():
    steel = mat(96, 110, 124, metal=.8, rough=.35, grime=.5)
    box(.56, .36, .26, (0, 0, .13), steel)
    box(.56, .04, .3, (0, .2, .38), steel, (-28, 0, 0))
    box(.48, .3, .02, (0, 0, .25), mat(150, 190, 240, emit=.8, grime=.2))
    return .7, .62


def engine_hoist():
    rust = mat(*RUST, metal=.5, grime=.6)
    for s in (1, -1):
        box(.08, .08, 2.2, (s * .7, 0, 1.0), rust, (0, s * -14, 0))
    box(1.3, .1, .1, (0, 0, 2.08), rust)
    for k in range(7):
        cyl(.025, .1, (0, 0, 1.98 - k * .1), mat(60, 58, 54, metal=.8), (90 * (k % 2), 0, 0), seg=8)
    block = mat(70, 74, 72, metal=.5, grime=.65)
    box(.62, .44, .42, (0, 0, 1.0), block)
    for x in (-.2, 0, .2):
        cyl(.07, .14, (x, 0, 1.28), block, seg=10)
    return 1.9, 2.3


def doghouse():
    wood = mat(150, 48, 36, planks=10.0, grime=.55)
    box(.8, .9, .6, (0, 0, .3), wood)
    for s in (1, -1):
        box(.52, 1.0, .05, (s * .2, 0, .76), mat(70, 64, 60, grime=.6), (0, s * -38, 0))
    box(.3, .02, .38, (0, -.46, .23), mat(14, 12, 10, grime=0))
    cyl(.12, .06, (-.48, -.6, .03), mat(*CHROME, metal=.7, grime=.6), seg=14)
    ROOT.rotation_euler = Euler((0, 0, math.radians(-25)))
    return 1.4, 1.05


def laundry():
    for k, (colour, w, h) in enumerate([((214, 210, 196), .44, .6), ((180, 40, 36), .5, .9),
                                         ((92, 110, 150), .44, .52), ((214, 210, 196), .16, .3),
                                         ((80, 80, 70), .48, .56)]):
        x = -1.0 + k * .5
        box(w, .02, h, (x, 0, .86 - h / 2), mat(*colour, grime=.35))
    cyl(.008, 2.6, (0, 0, .88), mat(80, 80, 80), (0, 90, 0), seg=4)
    return 2.6, .95


PROPS = {
    "outhouse": outhouse, "scarecrow": scarecrow, "tractor": tractor, "hay_wagon": hay_wagon,
    "picnic_table": picnic_table, "washer": washer, "fridge": fridge, "dish": dish,
    "flamingo": flamingo, "still": still, "skull_post": skull_post, "rocker": rocker,
    "grill": grill, "tombstone_a": tombstone_a, "tombstone_b": tombstone_b,
    "tombstone_c": tombstone_c, "saucer_wreck": saucer_wreck, "pylon": pylon,
    "safe_open": safe_open, "strongbox": strongbox, "engine_hoist": engine_hoist,
    "doghouse": doghouse, "laundry": laundry,
}
# The rest of the props (the chapters' own and more of Hickston's) live next door.
with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "props_more.py"), encoding="utf-8") as _more:
    exec(_more.read(), globals())
PROPS.update(MORE)
# The mothership's own (chapter 7).
with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "props_mothership.py"), encoding="utf-8") as _ship:
    exec(_ship.read(), globals())
PROPS.update(SHIP)
# Drawn flat on a plane in the game: rendered face on.
FLAT = {"laundry", "powder_shelf"} | SHIP_FLAT


# ---------------------------------------------------------------- stage
def stage():
    global ROOT
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 32
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
    bg.inputs[1].default_value = .5
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
    return scene, camera


def main():
    global ROOT
    scene, camera = stage()
    os.makedirs(OUT, exist_ok=True)
    names = list(PROPS) if NAMES == "all" else NAMES.split(",")
    meta = {}
    for name in names:
        for ob in [o for o in bpy.data.objects if o.type == "MESH" or o.name.startswith("root")]:
            bpy.data.objects.remove(ob)
        ROOT = bpy.data.objects.new("root", None)
        scene.collection.objects.link(ROOT)
        holder = bpy.data.objects.new("root_turn", None)
        scene.collection.objects.link(holder)
        w, h = PROPS[name]()
        flat = name in FLAT
        holder.rotation_euler = Euler((0, 0, 0 if flat else math.radians(-28)))
        ROOT.parent = holder
        pitch = 0.0 if flat else math.radians(8)
        # A margin all round: the shrinking tool crops each sprite to its edges.
        cw, ch = w + 1.2, h + .8
        scene.render.resolution_x = round(cw * PPU * SS)
        scene.render.resolution_y = round(ch * PPU * SS)
        camera.data.ortho_scale = max(cw, ch)
        look = Vector((0, 0, h / 2))
        back = Vector((0, -math.cos(pitch), math.sin(pitch)))
        camera.location = look + back * 12
        camera.rotation_euler = (math.pi / 2 - pitch, 0, 0)
        scene.render.filepath = os.path.join(OUT, "%s.png" % name)
        bpy.ops.render.render(write_still=True)
        meta[name] = [cw, ch, PPU]
    path = os.path.join(OUT, "meta.json")
    old = json.load(open(path)) if os.path.exists(path) else {}
    old.update(meta)
    json.dump(old, open(path, "w"))


main()
