"""The quest props: everything the objective is done at, modelled whole so it
reads at a glance from any side with nothing behind it. Control boxes on their
posts with a big throw lever, the relay cabinet, the carriage brake, the
midway bell on its frame, the exit signal posts, the gate bolt, the PA rig and
patch board, the kiln belt's knock-off, the quarry's latch, condenser and
relief valves, the bayou's generator, fuel drum, breaker and airboat
ignition, the speedway's fuel dump, starter's stand and checkered flag, the
Mothership's alien consoles, and the keys and the PA patch lead to pick up.

    blender -b -P scripts/blender/quest_props.py -- <out dir> <names|all> [supersample]

Every station prop is rendered twice: <name>_off (still to do: its warning
lamp lit, the lever up, the wheel shut) and <name>_on (done: the lamp dark,
the green pilot lit, the lever thrown and a red tag hung on it). Exits are
lit red and chained until the way is clear, then green and open. It runs
town_props.py's library (materials, shapes, the stage) with its own camera:
the same three-quarter view as the town's props, at a finer grain (they are
walked right up to); the keys and the lead are seen from higher, lying as
they would on the dirt. godot/tools/art/build_quest_art.gd crops each pair
to one frame and shrinks it into assets/art (town_<name>_off/on.png, sizes
in town_props.json; item_<name>.png for the pickups).
Everything is modelled here from scratch; nothing is traced from another game.
"""
import json
import math
import os

_HERE = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(_HERE, "town_props.py"), encoding="utf-8") as _lib:
    _source = _lib.read()
# The library without its last line (main()): this script has its own.
exec(_source[: _source.rstrip().rfind("main()")], globals())
# Its timber, chain and colour helpers (props_more.py defines them for the town).
with open(os.path.join(_HERE, "props_more.py"), encoding="utf-8") as _more:
    exec(_more.read(), globals())

QPPU = 96.0
SOOT = (22, 18, 16)
HAZARD = (232, 180, 30)
RED_LAMP = (255, 70, 36)
AMBER_LAMP = (255, 120, 20)
GREEN_LAMP = (40, 255, 50)
CONCRETE = (150, 146, 136)
TAG_RED = (200, 26, 18)
CREAM = (236, 224, 190)
ALIEN_GLOW = (120, 255, 160)
ALIEN_HULL = (92, 96, 88)


# ------------------------------------------------------------------ helpers
def rod(p0, p1, r, m, seg=10):
    """A round bar from p0 to p1."""
    a, b = Vector(p0), Vector(p1)
    d = b - a
    rot = [math.degrees(v) for v in d.normalized().to_track_quat("Z", "Y").to_euler()]
    return cyl(r, d.length, (a + b) / 2, m, rot, seg=seg)


def hoop(loc, r, t, m, rot=(0, 0, 0), seg=24, minor=8):
    """A ring of round bar, `r` across its middle and `t` thick, lying flat
    until turned by `rot` (degrees)."""
    bm = bmesh.new()
    rings = []
    for i in range(seg):
        a = i / seg * math.tau
        row = []
        for j in range(minor):
            b = j / minor * math.tau
            d = r + math.cos(b) * t / 2
            row.append(bm.verts.new((math.cos(a) * d, math.sin(a) * d, math.sin(b) * t / 2)))
        rings.append(row)
    for i in range(seg):
        for j in range(minor):
            bm.faces.new((rings[i][j], rings[(i + 1) % seg][j], rings[(i + 1) % seg][(j + 1) % minor],
                          rings[i][(j + 1) % minor]))
    return place(bm, m, loc, rot)


def path(points, r, m, seg=8):
    for a, b in zip(points, points[1:]):
        rod(a, b, r, m, seg)
        ball(r, b, m, seg=seg)


def stripes(c1=HAZARD, c2=SOOT, scale=16.0):
    """Hazard paint: hard diagonal bands of two colours."""
    key = ("stripes", c1, c2, scale)
    if key in MATS:
        return MATS[key]
    m = bpy.data.materials.new("stripes%d" % len(MATS))
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    coord = nt.nodes.new("ShaderNodeTexCoord")
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.bands_direction = "DIAGONAL"
    wave.wave_profile = "SAW"
    wave.inputs["Scale"].default_value = scale
    nt.links.new(coord.outputs["Object"], wave.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[1].position = .5
    ramp.color_ramp.elements[0].color = (lin(c1[0]), lin(c1[1]), lin(c1[2]), 1)
    ramp.color_ramp.elements[1].color = (lin(c2[0]), lin(c2[1]), lin(c2[2]), 1)
    nt.links.new(wave.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = .7
    MATS[key] = m
    return m


def glow(colour, strength=5.0):
    # The stage's Standard view clips a hot emitter to white: about half the
    # asked strength keeps a lamp its colour.
    return mat(*colour, rough=.3, emit=strength * .5, grime=0)


def dark_glass(colour):
    return mat(int(colour[0] * .2), int(colour[1] * .2), int(colour[2] * .2), rough=.2, grime=.2)


def lamp(loc, r, colour, lit):
    """A warning lamp: a glass dome in a wire cage on a black base. Lit, it
    glows; dark, smoky glass. Drawn big: it is what tells to-do from done."""
    x, y, z = loc
    r *= 1.3
    cyl(r * 1.25, r * .5, (x, y, z + r * .25), mat(*SOOT, metal=.4, rough=.5))
    ball(r, (x, y, z + r * .5), glow(colour) if lit else dark_glass(colour), (1, 1, 1.15))
    wire = mat(30, 28, 26, metal=.7, rough=.4, grime=.2)
    for a in (0, 60, 120):
        hoop((x, y, z + r * .5), r * 1.12, r * .12, wire, (90, 0, a), seg=16)
    cyl(r * .2, r * .3, (x, y, z + r * 1.75), wire, seg=8)


def pilot(loc, colour, lit, r=.035, face=(90, 0, 0)):
    cyl(r * 1.4, .02, loc, mat(*SOOT, metal=.5), face, seg=12)
    ball(r, (loc[0], loc[1] - .015, loc[2]), glow(colour, 4.0) if lit else dark_glass(colour))


def tag(loc, turn=0):
    """The red tag a hand hangs on a thrown switch."""
    x, y, z = loc
    rod((x, y, z), (x, y - .01, z - .08), .006, mat(220, 214, 196))
    box(.1, .012, .15, (x, y - .01, z - .16), mat(*TAG_RED, rough=.6, grime=.2), (0, turn, 0))
    box(.07, .014, .016, (x, y - .012, z - .13), mat(240, 232, 214, grime=0), (0, turn, 0))
    cyl(.012, .016, (x, y - .013, z - .1), mat(240, 232, 214, grime=0), (90, 0, 0), seg=8)


def plate_bolts(x0, x1, z0, z1, y, m):
    for x in (x0, x1):
        for z in (z0, z1):
            cyl(.014, .02, (x, y, z), m, (90, 0, 0), seg=6)


# The game's own block letters, three wide and five high: only the ones used.
GLYPHS = {
    "E": ["111", "100", "110", "100", "111"],
    "X": ["101", "101", "010", "101", "101"],
    "I": ["111", "010", "010", "010", "111"],
    "T": ["111", "010", "010", "010", "010"],
    "P": ["110", "101", "110", "100", "100"],
    "A": ["010", "101", "111", "101", "101"],
    "O": ["111", "101", "101", "101", "111"],
    "N": ["101", "111", "111", "101", "101"],
    "R": ["110", "101", "110", "101", "101"],
    "U": ["101", "101", "101", "101", "111"],
    "S": ["111", "100", "111", "001", "111"],
    "H": ["101", "101", "111", "101", "101"],
    "F": ["111", "100", "110", "100", "100"],
    "L": ["100", "100", "100", "100", "111"],
    "G": ["111", "100", "101", "101", "111"],
}


def letters(text, cx, y, cz, size, m):
    """Block letters standing proud of a face at depth y (facing -y), `size` a
    glyph pixel, centred on (cx, cz)."""
    width = len(text) * 4 * size - size
    left = cx - width / 2
    for i, ch in enumerate(text):
        rows = GLYPHS.get(ch)
        if rows is None:
            continue
        for r, row in enumerate(rows):
            for c, bit in enumerate(row):
                if bit == "1":
                    box(size * 1.02, size * .6, size * 1.02,
                        (left + (i * 4 + c) * size + size / 2, y - size * .3, cz + (2 - r) * size), m)


def foot(w, d, m=None):
    box(w, d, .07, (0, 0, .035), m or mat(*CONCRETE, grime=.75))


# ------------------------------------------------------------- the switches
SWITCH_STYLES = {
    # body colour, post kind, trim
    "mill": ((70, 108, 100), "timber", (196, 186, 150)),
    "fair": ((168, 40, 30), "steel", (236, 210, 140)),
    "bayou": ((88, 104, 70), "piling", (180, 170, 130)),
    "speedway": ((226, 178, 34), "steel", (30, 28, 26)),
}


def _post(kind, height):
    if kind == "timber":
        foot(.46, .38)
        box(.15, .15, height, (0, .02, height / 2 + .05), mat(*GREY_WOOD, planks=4.0, grime=.6))
        box(.3, .05, .05, (0, .02, .25), mat(*GREY_WOOD, planks=4.0, grime=.6), (0, 30, 0))
    elif kind == "piling":
        cyl(.13, height + .25, (0, .03, (height + .25) / 2 - .1), mat(70, 52, 36, planks=3.0, grime=.7), seg=12)
        rope = mat(186, 160, 110, grime=.4)
        for k in range(4):
            cyl(.137, .025, (0, .03, .3 + k * .035), rope, seg=12)
        cyl(.13, .06, (0, .03, height + .16), mat(52, 40, 30, grime=.6), seg=12)
    else:
        foot(.42, .36)
        steel = mat(70, 72, 74, metal=.7, rough=.4, grime=.5)
        box(.09, .09, height, (0, .02, height / 2 + .05), steel)
        for s in (1, -1):
            box(.03, .12, .14, (s * .06, .06, .12), steel, (0, s * 20, 0))


def quest_switch(done, style="mill"):
    """A junction box on its own post: the knife lever on its front up (live)
    or thrown down (off), the cage lamp on top, the pilots, a hazard band."""
    body, kind, trim = SWITCH_STYLES[style]
    paint = mat(*body, metal=.35, rough=.5, grime=.65)
    _post(kind, .74)
    box(.62, .34, .56, (0, 0, 1.06), paint)
    box(.66, .38, .05, (0, 0, 1.35), mat(*[int(c * .7) for c in body], metal=.4, grime=.6))
    # Door seam, hinges and a pull, all standing proud of the front.
    edge = mat(*trim, metal=.3, rough=.5, grime=.5)
    box(.56, .012, .5, (0, -.172, 1.06), mat(*[int(c * .85) for c in body], metal=.35, grime=.7))
    for z in (.88, 1.24):
        cyl(.018, .06, (-.28, -.18, z), edge, seg=8)
    box(.46, .016, .08, (0, -.18, .86), stripes())
    if style == "speedway":
        box(.46, .016, .08, (0, -.18, 1.27), stripes((30, 28, 26), (236, 232, 220), 9.0))
    elif style == "fair":
        for k in range(6):
            ball(.022, (-.25 + k * .1, -.18, 1.3), glow((255, 226, 150), 3.0) if not done else mat(200, 190, 150, rough=.3))
    # The lever: a slot plate, the hub, the arm up and out or thrown down.
    box(.14, .02, .4, (.1, -.18, 1.07), mat(*SOOT))
    hub = (.1, -.2, 1.06)
    cyl(.05, .06, hub, mat(60, 58, 54, metal=.8, rough=.3), (90, 0, 0), seg=14)
    tip = (.1, -.44, 1.42) if not done else (.1, -.44, .7)
    rod(hub, tip, .022, mat(*CHROME, metal=.9, rough=.25))
    grip0 = Vector(hub).lerp(Vector(tip), .62)
    rod(grip0, tip, .04, stripes(HAZARD, SOOT, 14.0), seg=12)
    ball(.06, tip, mat(200, 28, 20, rough=.35, grime=.1))
    # The pilots: red while live, green once off.
    pilot((-.17, -.18, 1.16), RED_LAMP, not done)
    pilot((-.17, -.18, 1.04), GREEN_LAMP, done)
    lamp((-.16, 0, 1.375), .085, RED_LAMP if style != "speedway" else AMBER_LAMP, not done)
    # The conduit down the post.
    rod((.22, .1, .78), (.22, .1, .2), .025, mat(60, 60, 58, metal=.6))
    if done:
        tag((tip[0] + .02, tip[1] + .02, tip[2] - .05))
    return 1.0, 1.62


# ------------------------------------------------------------ the cabinets
def quest_relay(done):
    """The relay cabinet: three fuse tubes glowing in its window while it runs,
    dark once shut down, and the big handle on its side that does it."""
    body = mat(66, 98, 92, metal=.35, rough=.5, grime=.7)
    box(.8, .5, .1, (0, 0, .05), mat(48, 40, 32, planks=5.0, grime=.6))
    box(.7, .44, 1.2, (0, 0, .7), body)
    box(.76, .5, .06, (0, 0, 1.33), mat(46, 70, 66, metal=.4, grime=.6))
    box(.54, .02, .5, (0, -.225, .92), mat(*SOOT))
    tube_glass = glow((255, 140, 40), 4.5) if not done else mat(70, 62, 54, rough=.25, grime=.3)
    brass = mat(200, 160, 80, metal=.8, rough=.3, grime=.4)
    for k in range(3):
        x = -.17 + k * .17
        cyl(.05, .38, (x, -.24, .92), tube_glass, seg=14)
        if not done:
            cyl(.02, .36, (x, -.25, .92), glow((255, 236, 170), 6.0), seg=8)
        for z in (.71, 1.13):
            cyl(.065, .05, (x, -.24, z), brass, seg=14)
    box(.54, .02, .1, (0, -.225, .5), stripes())
    pilot((-.2, -.23, .3), RED_LAMP, not done)
    pilot((-.08, -.23, .3), GREEN_LAMP, done)
    # The handle on the side facing out.
    box(.03, .14, .5, (.365, -.05, .78), mat(*SOOT))
    hub = (.39, -.05, .8)
    cyl(.05, .05, hub, mat(60, 58, 54, metal=.8), (0, 90, 0), seg=14)
    tip = (.45, -.2, 1.14) if not done else (.45, -.2, .44)
    rod(hub, tip, .024, mat(*CHROME, metal=.9, rough=.25))
    rod(Vector(hub).lerp(Vector(tip), .6), tip, .042, stripes(HAZARD, SOOT, 14.0), seg=12)
    ball(.06, tip, mat(200, 28, 20, rough=.35))
    lamp((-.2, 0, 1.36), .09, AMBER_LAMP, not done)
    # Cable trunk down its back.
    rod((.2, .24, 1.0), (.2, .24, .1), .04, mat(40, 36, 30, rough=.6))
    if done:
        tag((tip[0], tip[1], tip[2] - .03))
    return 1.1, 1.62


def quest_pa_rig(done):
    """A PA rig on a dolly: the amp rack with its glowing meters, the horn up
    on its pole, the ON AIR box lit while it broadcasts and the knife switch
    that cuts it."""
    box(.7, .5, .06, (0, 0, .14), mat(60, 60, 58, metal=.6, grime=.6))
    for x in (-.28, .28):
        for y in (-.18, .18):
            cyl(.07, .05, (x, y, .07), mat(*TIRE), (0, 90, 0), seg=12)
    rack = mat(178, 146, 96, rough=.7, grime=.55, planks=40.0)
    box(.64, .44, .66, (0, 0, .5), rack)
    box(.66, .46, .04, (0, 0, .83), mat(60, 42, 30, rough=.6))
    box(.5, .02, .2, (0, -.225, .4), mat(70, 50, 36, rough=.9, grime=.3, planks=60.0))
    meter = glow((255, 190, 90), 2.5) if not done else mat(90, 80, 60, rough=.3)
    for k in range(2):
        box(.14, .02, .09, (-.2 + k * .17, -.225, .72), meter)
        rod((-.2 + k * .17, -.24, .68), (-.2 + k * .17 + (.04 if not done else -.05), -.24, .75), .005, mat(30, 20, 16))
    for k in range(4):
        cyl(.025, .03, (-.24 + k * .08, -.23, .6), mat(220, 214, 196, metal=.6), (90, 0, 0), seg=10)
    box(.5, .016, .05, (0, -.23, .22), stripes())
    # The pole and the horn.
    pole = mat(80, 82, 84, metal=.7, rough=.4)
    rod((.18, .1, .85), (.18, .1, 1.62), .025, pole)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=20, radius1=.26, radius2=.06, depth=.42)
    place(bm, mat(150, 150, 136, metal=.5, rough=.45, grime=.6), (.36, .06, 1.62), (0, -100, 0))
    cyl(.09, .14, (.1, .1, 1.62), mat(60, 58, 54, metal=.6), (0, 80, 0), seg=14)
    # ON AIR box on top of the rack.
    box(.34, .16, .16, (-.12, -.02, .93), mat(*SOOT))
    box(.3, .02, .12, (-.12, -.105, .93), glow((255, 60, 40), 4.0) if not done else dark_glass((255, 60, 40)))
    letters("PA", -.12, -.115, .93, .02, mat(40, 10, 8) if not done else mat(140, 40, 30))
    # The knife switch on the rack's front.
    box(.1, .02, .26, (.2, -.225, .58), mat(*SOOT))
    hub = (.2, -.24, .58)
    cyl(.035, .04, hub, mat(60, 58, 54, metal=.8), (90, 0, 0), seg=12)
    tip = (.2, -.42, .86) if not done else (.2, -.42, .32)
    rod(hub, tip, .018, mat(*CHROME, metal=.9))
    ball(.045, tip, mat(200, 28, 20, rough=.35))
    pilot((-.24, -.22, .38), GREEN_LAMP, done, .028)
    # Its cable off to the stage.
    path([(-.3, .15, .3), (-.42, .3, .1), (-.5, .4, .04)], .02, mat(30, 30, 30))
    if done:
        tag((tip[0], tip[1], tip[2] - .02))
    return 1.2, 1.95


def quest_patchbay(done):
    """The backstage patch board on its legs: rows of jacks, jack B empty and
    its lamp lit amber until the lead is patched in, then the orange lead
    looped across and the pilot green."""
    legs = mat(56, 54, 52, metal=.6, rough=.4)
    for x in (-.28, .28):
        rod((x, .06, 0), (x, 0, .7), .03, legs)
        rod((x, .06, 0), (x, .2, 0), .03, legs)
    board = mat(52, 46, 40, metal=.2, rough=.6, grime=.5)
    box(.72, .14, .6, (0, 0, 1.0), board, (-8, 0, 0))
    box(.66, .02, .08, (0, -.08, 1.25), mat(196, 170, 90, metal=.6, grime=.4), (-8, 0, 0))
    jack = mat(190, 186, 170, metal=.8, rough=.3)
    for row in range(3):
        for col in range(6):
            x = -.25 + col * .1
            z = 1.12 - row * .13
            y = -.075 - (1.12 - z) * .14
            cyl(.022, .03, (x, y, z), jack, (82, 0, 0), seg=10)
            cyl(.01, .032, (x, y - .002, z), mat(*SOOT), (82, 0, 0), seg=8)
    # Jack B: ringed in yellow.
    cyl(.04, .02, (-.05, -.07, 1.12), mat(*HAZARD, rough=.5), (82, 0, 0), seg=16)
    lamp((.27, .02, 1.3), .07, AMBER_LAMP, not done)
    pilot((.27, -.08, .82), GREEN_LAMP, done, .03, (82, 0, 0))
    lead = mat(240, 108, 26, rough=.45, grime=.2)
    if done:
        path([(-.05, -.13, 1.12), (-.06, -.22, 1.0), (.06, -.24, .86), (.15, -.2, .96), (.15, -.11, .99)], .018, lead)
        for p in ((-.05, -.1, 1.12), (.15, -.09, .99)):
            cyl(.026, .06, p, mat(30, 28, 26), (82, 0, 0), seg=10)
        tag((.0, -.23, .98))
    else:
        # A dead cable hangs from the empty jack's side, nothing on its end.
        path([(-.33, -.04, 1.05), (-.36, -.1, .8), (-.32, -.12, .62)], .015, mat(40, 40, 40))
    return 1.0, 1.5


def quest_estop(done):
    """The kiln belt's knock-off: a yellow post, the box on top with a big red
    mushroom button under its guard, struck down once it has been hit."""
    foot(.44, .36)
    box(.14, .14, .78, (0, .02, .44), stripes(HAZARD, SOOT, 7.0))
    box(.44, .34, .3, (0, 0, .98), mat(226, 178, 34, metal=.3, rough=.5, grime=.6))
    box(.36, .02, .18, (0, -.172, .98), mat(*SOOT))
    # The guard: two hoops round the button.
    guard = mat(200, 196, 180, metal=.8, rough=.35)
    for x in (-.1, .1):
        rod((x, -.12, 1.13), (x, -.12, 1.25), .012, guard)
    rod((-.1, -.12, 1.25), (.1, -.12, 1.25), .012, guard)
    rise = .1 if not done else .03
    cyl(.07, .05, (0, -.06, 1.15), mat(60, 58, 54, metal=.7), seg=16)
    cyl(.05, rise, (0, -.06, 1.16 + rise / 2), mat(150, 150, 146, metal=.7), seg=14)
    cyl(.13, .06, (0, -.06, 1.19 + rise), mat(214, 30, 22, rough=.35, grime=.1), seg=24, top=.11)
    pilot((-.12, -.18, .98), RED_LAMP, not done)
    pilot((.12, -.18, .98), GREEN_LAMP, done)
    lamp((.13, .07, 1.13), .07, AMBER_LAMP, not done)
    # The belt's pulley stub on the post's back.
    cyl(.16, .08, (0, .16, .62), mat(70, 72, 70, metal=.6, grime=.6), (90, 0, 0), seg=18)
    box(.06, .4, .03, (0, .36, .78), mat(40, 34, 28, rough=.8), (-20, 0, 0))
    if done:
        tag((.1, -.14, 1.25))
    return .8, 1.45


# ------------------------------------------------------------ mill & fair
def quest_brake(done):
    """The log carriage brake: a long lever on an iron quadrant in a timber
    stand. Hauled over to BRAKE ON, then thrown across, tagged."""
    wood = mat(*WOOD, planks=6.0, grime=.55)
    box(1.0, .4, .1, (0, 0, .05), wood)
    for x in (-.4, .4):
        box(.11, .11, .7, (x, .05, .4), wood)
    box(.9, .1, .08, (0, .05, .76), wood)
    iron = mat(70, 70, 66, metal=.75, rough=.4, grime=.5)
    pivot = Vector((0, -.04, .3))
    for k in range(13):
        a = math.radians(-60 + k * 10)
        p = pivot + Vector((math.sin(a) * .5, 0, math.cos(a) * .5))
        box(.05, .05, .05, p, iron, (0, math.degrees(a), 0))
        if k < 12:
            b = pivot + Vector((math.sin(a + math.radians(10)) * .46, 0, math.cos(a + math.radians(10)) * .46))
            rod(pivot + Vector((math.sin(a) * .46, 0, math.cos(a) * .46)), b, .02, iron)
    cyl(.07, .1, pivot, iron, (90, 0, 0), seg=16)
    angle = math.radians(-38 if not done else 38)
    tip = pivot + Vector((math.sin(angle) * .98, -.06, math.cos(angle) * .98))
    rod(pivot, tip, .03, mat(*CHROME, metal=.85, rough=.3))
    rod(pivot.lerp(tip, .78), tip, .045, stripes(HAZARD, SOOT, 14.0), seg=12)
    ball(.07, tip, mat(200, 28, 20, rough=.35))
    # The pawl plate, the lamp on its post.
    box(.2, .02, .12, (-.3 if not done else .3, -.08, .9), mat(*SOOT))
    rod((.48, .05, .8), (.48, .05, 1.18), .025, iron)
    lamp((.48, .05, 1.18), .08, RED_LAMP, not done)
    pilot((-.4, -.02, .62), GREEN_LAMP, done)
    if done:
        tag((tip.x - .04, tip.y, tip.z - .04))
    return 1.6, 1.5


def quest_bell(done):
    """The midway bell on its frame: two posts, the beam, the brass bell and
    its striped pull. Rung: swung over, the lamp out, a blue ribbon pinned up."""
    red = mat(170, 48, 34, planks=6.0, grime=.5)
    for x in (-.42, .42):
        box(.1, .1, 1.5, (x, 0, .75), red)
        box(.4, .3, .06, (x, 0, .03), mat(*WOOD, planks=5.0, grime=.6))
        box(.06, .06, .4, (x - .1 * (1 if x > 0 else -1), 0, .2), red, (0, 40 if x > 0 else -40, 0))
    box(1.0, .12, .12, (0, 0, 1.5), mat(236, 204, 120, planks=6.0, grime=.45))
    for k in range(7):
        ball(.025, (-.36 + k * .12, -.07, 1.5), glow((255, 226, 150), 3.0) if not done else mat(196, 186, 150, rough=.3))
    swing = 0 if not done else 28
    brass = mat(214, 160, 60, metal=.9, rough=.25, grime=.35)
    holder = bpy.data.objects.new("bell", None)
    bpy.context.scene.collection.objects.link(holder)
    holder.parent = ROOT
    holder.location = (0, 0, 1.42)
    holder.rotation_euler = Euler((0, math.radians(swing), 0))
    parts = []
    parts.append(box(.1, .08, .1, (0, 0, -.02), mat(40, 36, 32, metal=.6)))
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=24, radius1=.25, radius2=.12, depth=.34)
    parts.append(place(bm, brass, (0, 0, -.27), (0, 0, 0)))
    parts.append(cyl(.27, .05, (0, 0, -.45), brass, seg=24))
    parts.append(ball(.12, (0, 0, -.1), brass, (1, 1, .6)))
    parts.append(ball(.045, (0, 0, -.5), mat(50, 46, 40, metal=.7)))
    for ob in parts:
        ob.parent = holder
    # The rope from the clapper down to its handle (it hangs straight).
    rope = mat(222, 206, 160, grime=.35)
    rod((0, 0, .95), (0, -.02, .5), .012, rope)
    for k in range(4):
        cyl(.03, .045, (0, -.02, .46 - k * .045), mat(*((220, 30, 24) if k % 2 == 0 else (240, 236, 220)), rough=.5), seg=12)
    lamp((0, 0, 1.56), .085, AMBER_LAMP, not done)
    if done:
        ribbon = mat(40, 80, 200, rough=.6, grime=.1)
        cyl(.08, .02, (.42, -.06, 1.15), ribbon, (90, 0, 0), seg=16)
        cyl(.045, .022, (.42, -.07, 1.15), mat(240, 210, 100, rough=.5, grime=0), (90, 0, 0), seg=14)
        for s in (-1, 1):
            box(.04, .01, .14, (.42 + s * .03, -.065, 1.03), ribbon, (0, s * 14, 0))
    return 1.3, 1.85


def quest_exit(done, style="mill"):
    """The way out as a signal post: the signal head lit red over a striped
    barrier arm chained shut with a padlock, the EXIT plate on the post; open,
    the head green and the arm swung up."""
    plate_colour = (40, 96, 54) if style == "mill" else (150, 34, 26)
    foot(.5, .44)
    post = mat(60, 62, 62, metal=.6, rough=.45, grime=.55)
    box(.14, .14, 1.5, (0, 0, .8), post)
    rod((0, -.05, .72), (.36, -.05, .72), .03, post)
    # The signal head: a black box, two lenses under visors.
    box(.26, .2, .5, (0, -.03, 1.62), mat(*SOOT, metal=.3))
    for k, (colour, lit) in enumerate(((RED_LAMP, not done), (GREEN_LAMP, done))):
        z = 1.74 - k * .24
        cyl(.1, .03, (0, -.135, z), glow(colour, 6.0) if lit else dark_glass(colour), (90, 0, 0), seg=20)
        box(.24, .1, .02, (0, -.18, z + .11), mat(*SOOT))
    # EXIT on its plate, both faces.
    box(.56, .03, .22, (0, -.085, 1.12), mat(*plate_colour, metal=.3, rough=.5, grime=.4))
    box(.6, .028, .26, (0, -.075, 1.12), mat(220, 210, 180, metal=.3, grime=.4))
    letters("EXIT", 0, -.1, 1.12, .033, mat(*CREAM, rough=.5, grime=.2))
    # The barrier arm on its hub.
    hub = Vector((.36, -.1, .72))
    cyl(.06, .08, hub, mat(200, 30, 24, metal=.4), (90, 0, 0), seg=16)
    arm = stripes((236, 232, 220), (200, 30, 24), 7.0)
    if not done:
        box(.8, .05, .07, (hub.x + .4, hub.y, hub.z), arm)
        box(.08, .1, .62, (1.02, -.1, .31), post)
        chain_mat = mat(170, 166, 156, metal=.85, rough=.35)
        chain((.96, -.13, .72), (.94, -.15, .5), chain_mat, .05)
        rod((.93, -.15, .5), (.93, -.15, .44), .02, chain_mat)
        box(.08, .04, .09, (.93, -.16, .39), mat(214, 160, 60, metal=.8, rough=.3))
        cyl(.012, .05, (.93, -.18, .39), mat(*SOOT), (90, 0, 0), seg=8)
    else:
        box(.07, .05, .8, (hub.x, hub.y, hub.z + .4), arm, (0, 4, 0))
        box(.08, .1, .62, (1.02, -.1, .31), post)
    return 1.4, 2.0


def quest_bolt(done):
    """A stout gatepost with a heavy slide bolt: shot home into its keeper
    under a red lamp, then drawn back and the lamp green."""
    wood = mat(*GREY_WOOD, planks=5.0, grime=.6)
    box(.22, .22, 1.2, (0, 0, .6), wood)
    box(.26, .26, .05, (0, 0, 1.22), mat(70, 64, 58, grime=.6))
    rail = mat(*WOOD, planks=8.0, grime=.55)
    for z in (.4, .85):
        box(.5, .08, .12, (-.36, .03, z), rail)
    iron = mat(56, 54, 50, metal=.8, rough=.45, grime=.55)
    # Staples, the keeper on the rail end and the bar.
    for x in (-.02, .1):
        box(.04, .06, .14, (x, -.13, .66), iron)
    box(.06, .08, .16, (-.36, -.07, .66), iron)
    shot = -.22 if not done else .2
    box(.56, .08, .08, (shot, -.17, .66), mat(150, 146, 136, metal=.85, rough=.3))
    rod((shot + .05, -.2, .66), (shot + .05, -.34, .56), .03, iron)
    ball(.06, (shot + .05, -.35, .55), mat(200, 28, 20, rough=.35))
    lamp((0, 0, 1.25), .075, RED_LAMP if not done else GREEN_LAMP, True)
    if done:
        tag((.1, -.16, .62))
    return 1.1, 1.5


# --------------------------------------------------------------- the quarry
def quest_latch(done):
    """The wash carts' latch: a short rail on its sleepers, the hinged iron
    stop down across it, or lifted clear, and its lever post with a lamp."""
    sleeper = mat(70, 54, 38, planks=4.0, grime=.6)
    for y in (-.3, 0, .3):
        box(.9, .14, .06, (0, y, .03), sleeper)
    rail = mat(110, 100, 92, metal=.8, rough=.4, grime=.6)
    for x in (-.25, .25):
        box(.05, .9, .07, (x, 0, .1), rail)
    iron = mat(70, 66, 60, metal=.8, rough=.4, grime=.5)
    cyl(.05, .1, (-.38, -.05, .2), iron, (0, 90, 0), seg=12)
    stop = stripes(HAZARD, SOOT, 9.0)
    if not done:
        box(.8, .06, .07, (0, -.05, .2), stop)
        box(.06, .1, .12, (.38, -.05, .15), iron)
    else:
        box(.07, .06, .8, (-.38, -.05, .6), stop, (0, -8, 0))
    # The lever post.
    box(.1, .1, .9, (.5, .25, .45), mat(*GREY_WOOD, planks=4.0, grime=.6))
    hub = Vector((.5, .19, .78))
    cyl(.04, .05, hub, iron, (90, 0, 0), seg=12)
    tip = hub + (Vector((.22, -.04, .2)) if not done else Vector((.12, -.04, .3)))
    rod(hub, tip, .02, mat(*CHROME, metal=.9))
    ball(.045, tip, mat(200, 28, 20, rough=.35))
    lamp((.5, .25, .9), .065, AMBER_LAMP, not done)
    pilot((.5, .19, .6), GREEN_LAMP, done, .028)
    return 1.3, 1.2


def _wheel(centre, r, turn, m, face=(90, 0, 0)):
    """A valve wheel facing -y: rim, hub and four spokes turned `turn` degrees."""
    x, y, z = centre
    hoop(centre, r, r * .16, m, face)
    cyl(r * .2, .06, centre, m, face, seg=12)
    for k in range(4):
        a = math.radians(turn + k * 45)
        rod((x, y, z), (x + math.cos(a) * r, y, z + math.sin(a) * r), r * .06, m, seg=6)
        rod((x, y, z), (x - math.cos(a) * r, y, z - math.sin(a) * r), r * .06, m, seg=6)


def _gauge(centre, done):
    x, y, z = centre
    cyl(.07, .04, centre, mat(40, 40, 38, metal=.7), (90, 0, 0), seg=18)
    cyl(.058, .01, (x, y - .02, z), mat(236, 232, 214, rough=.4, grime=0), (90, 0, 0), seg=18)
    cyl(.05, .006, (x, y - .025, z), mat(60, 170, 70, rough=.5, grime=0), (90, 0, 0), seg=18)
    box(.03, .008, .03, (x + .03, y - .028, z + .03), mat(210, 30, 20, grime=0))
    a = math.radians(40 if not done else 150)
    rod((x, y - .03, z), (x + math.cos(a) * .05, y - .03, z + math.sin(a) * .05), .005, mat(*SOOT))


def quest_condenser(done):
    """The copper condenser: the coil and its standpipe, a big red valve
    wheel to divert it, the gauge in the red and an amber lamp; diverted, the
    wheel turned over, the gauge green, a tag on the wheel."""
    copper = mat(190, 110, 62, metal=.85, rough=.3, grime=.5)
    foot(.6, .46)
    cyl(.09, 1.1, (.12, .06, .62), copper, seg=14)
    for k in range(6):
        hoop((-.18, .08, .3 + k * .1), .18, .04, copper, (0, 0, 0), seg=18)
    cyl(.03, .6, (-.18, .08, .55), mat(60, 56, 50, metal=.6), seg=8)
    rod((.12, .06, 1.12), (-.18, .08, .86), .03, copper)
    box(.22, .2, .2, (.12, -.02, .78), mat(70, 64, 56, metal=.7, grime=.6))
    rod((.12, -.12, .78), (.12, -.22, .78), .025, mat(60, 58, 54, metal=.7))
    _wheel((.12, -.24, .78), .17, 0 if not done else 40, mat(200, 30, 24, metal=.4, rough=.4))
    _gauge((.12, -.05, 1.0), done)
    lamp((.12, .06, 1.17), .07, AMBER_LAMP, not done)
    pilot((-.05, -.12, .9), GREEN_LAMP, done, .028)
    # A copper jug catching the drip.
    cyl(.07, .14, (-.2, -.12, .14), mat(222, 214, 196, rough=.35), seg=12, top=.03)
    if done:
        tag((.22, -.27, .9))
    return 1.0, 1.4


def quest_valve(done):
    """A relief valve: an iron standpipe out of a concrete pad, the wheel on
    its top, a gauge, and the vent pipe; opened, the wheel turned, the gauge
    eased into the green."""
    iron = mat(78, 92, 84, metal=.6, rough=.45, grime=.65)
    foot(.5, .5)
    cyl(.08, .8, (0, 0, .45), iron, seg=14)
    cyl(.12, .06, (0, 0, .12), iron, seg=14)
    cyl(.11, .06, (0, 0, .84), iron, seg=14)
    rod((0, 0, .7), (.3, 0, .7), .05, iron)
    rod((.3, 0, .7), (.3, 0, 1.0), .05, iron)
    cyl(.08, .04, (.3, 0, 1.02), mat(40, 40, 38, metal=.7), seg=12)
    cyl(.08, .14, (0, 0, .95), iron, seg=14)
    rod((0, 0, .95), (0, -.2, .95), .03, mat(150, 146, 136, metal=.8))
    _wheel((0, -.22, .95), .2, 0 if not done else 45, mat(200, 30, 24, metal=.4, rough=.4))
    _gauge((-.04, -.1, .62), done)
    lamp((.3, 0, 1.06), .06, AMBER_LAMP, not done)
    pilot((.1, -.08, .45), GREEN_LAMP, done, .028)
    if done:
        tag((.14, -.25, 1.0))
    return .9, 1.25


# ---------------------------------------------------------------- the bayou
def quest_generator(done):
    """The boil yard generator on its skid: a tube frame, the engine, the red
    tank on top, the muffler and the crank on its side; running, its work bulb
    lit and the pilot green."""
    skid = mat(76, 56, 38, planks=5.0, grime=.6)
    for y in (-.18, .18):
        box(.9, .08, .08, (0, y, .04), skid)
    frame = mat(60, 92, 60, metal=.5, rough=.5, grime=.6)
    for x in (-.36, .36):
        for y in (-.2, .2):
            rod((x, y, .08), (x, y, .66), .025, frame)
        rod((x, -.2, .66), (x, .2, .66), .025, frame)
    rod((-.36, -.2, .66), (.36, -.2, .66), .025, frame)
    rod((-.36, .2, .66), (.36, .2, .66), .025, frame)
    engine = mat(70, 72, 70, metal=.6, rough=.45, grime=.6)
    box(.36, .3, .32, (-.1, 0, .3), engine)
    for k in range(5):
        box(.02, .32, .26, (-.24 + k * .06, 0, .32), mat(50, 52, 50, metal=.6))
    box(.26, .3, .3, (.2, 0, .28), mat(170, 160, 120, metal=.4, grime=.6))
    cyl(.15, .5, (0, 0, .8), mat(200, 40, 30, metal=.4, rough=.4, grime=.5), (0, 90, 0), seg=18)
    cyl(.04, .05, (.1, 0, .97), mat(*CHROME, metal=.8), seg=10)
    cyl(.06, .3, (-.3, .12, .5), mat(60, 50, 44, metal=.6, grime=.7), (0, 90, 0), seg=12)
    # The crank: down to start, round once it runs.
    iron = mat(60, 58, 54, metal=.8)
    cyl(.04, .1, (.36, -.08, .3), iron, (0, 90, 0), seg=10)
    arm = Vector((0, -.18, -.0)) if not done else Vector((0, 0, .18))
    rod((.42, -.08, .3), Vector((.42, -.08, .3)) + arm, .02, iron)
    end = Vector((.42, -.08, .3)) + arm
    rod(end, end + Vector((.12, 0, 0)), .025, mat(200, 28, 20, rough=.35))
    pilot((.2, -.16, .34), GREEN_LAMP, done, .03)
    lamp((-.1, -.06, .46), .06, RED_LAMP, not done)
    # The work bulb on its stick.
    rod((-.36, .2, .66), (-.36, .2, 1.2), .015, frame)
    ball(.06, (-.36, .2, 1.24), glow((255, 220, 140), 5.0) if done else mat(150, 146, 130, rough=.25))
    path([(.36, .1, .3), (.5, .2, .1), (.6, .24, .03)], .015, mat(30, 30, 30))
    return 1.3, 1.45


def quest_fuel_drum(done):
    """The airboat's fuel drum on its dock skid, a sack of sugar leaning on it;
    spiked, the cap off, the sack slumped empty, sugar in the planks."""
    deck = mat(*GREY_WOOD, planks=10.0, grime=.6)
    box(.9, .7, .06, (0, 0, .03), deck)
    drum = mat(196, 40, 30, metal=.5, rough=.4, grime=.55)
    cyl(.24, .7, (-.08, .04, .41), drum, seg=22)
    for z in (.2, .62):
        cyl(.25, .03, (-.08, .04, z), mat(150, 30, 24, metal=.5), seg=22)
    box(.2, .02, .14, (-.08, -.2, .44), mat(236, 214, 150, rough=.5))
    cap = mat(200, 196, 180, metal=.8, rough=.3)
    if not done:
        cyl(.05, .05, (.0, .1, .79), cap, seg=12)
    else:
        cyl(.05, .05, (.25, -.22, .09), cap, (60, 0, 20), seg=12)
        cyl(.04, .02, (.0, .1, .77), mat(*SOOT), seg=12)
    sack = mat(226, 220, 204, rough=.9, grime=.35, planks=30.0)
    if not done:
        box(.3, .2, .42, (.28, -.12, .27), sack, (0, -8, 0))
        box(.16, .14, .1, (.3, -.12, .53), sack, (0, -8, 0))
        cyl(.06, .03, (.3, -.12, .5), mat(150, 110, 60), seg=10)
        letters("SUGAR", .28, -.225, .27, .014, mat(40, 70, 150, rough=.7))
    else:
        ball(.17, (.28, -.06, .12), sack, (1.3, 1, .5))
        for k in range(6):
            box(.06, .05, .02, (.1 + k * .06, -.22 + (k % 2) * .05, .07), mat(250, 250, 244, rough=.5, grime=0), (0, 0, k * 30))
    # Its stake and lamp.
    rod((-.38, -.22, .06), (-.38, -.22, .9), .025, mat(*WOOD, grime=.6))
    lamp((-.38, -.22, .9), .065, RED_LAMP, not done)
    pilot((-.08, -.21, .3), GREEN_LAMP, done, .03)
    return 1.1, 1.15


def quest_ignition(done):
    """The King's airboat ignition, wired to a piling on the dock: a marine
    switch box, its key, two wires hanging apart under a red lamp; hot-wired,
    twisted together, a spark, the lamp green."""
    cyl(.14, 1.25, (0, .05, .6), mat(70, 52, 36, planks=3.0, grime=.7), seg=12)
    rope = mat(186, 160, 110, grime=.4)
    for k in range(4):
        cyl(.147, .025, (0, .05, .28 + k * .035), rope, seg=12)
    box(.34, .2, .28, (0, -.12, .96), mat(226, 222, 206, metal=.3, rough=.45, grime=.6))
    box(.3, .02, .2, (0, -.225, .96), mat(40, 110, 120, metal=.3, rough=.45, grime=.5))
    cyl(.04, .03, (-.07, -.24, 1.0), mat(*CHROME, metal=.9), (90, 0, 0), seg=14)
    box(.02, .03, .06, (-.07, -.26, 1.0), mat(196, 160, 60, metal=.8), (0, 30, 0))
    cyl(.035, .03, (.07, -.24, 1.0), mat(200, 30, 24, rough=.4), (90, 0, 0), seg=14)
    red = mat(210, 36, 28, rough=.5, grime=.1)
    black = mat(30, 30, 30, rough=.5)
    if not done:
        path([(-.04, -.22, .82), (-.1, -.26, .6), (-.16, -.28, .44)], .012, red)
        path([(.04, -.22, .82), (.1, -.26, .6), (.14, -.27, .46)], .012, black)
        lamp((0, -.12, 1.1), .07, RED_LAMP, True)
    else:
        path([(-.04, -.22, .82), (-.01, -.27, .66), (.0, -.28, .6)], .012, red)
        path([(.04, -.22, .82), (.01, -.27, .66), (.0, -.285, .6)], .012, black)
        for k in range(4):
            a = math.radians(k * 45)
            box(.1, .01, .012, (0, -.3, .6), glow((255, 236, 140), 8.0), (0, math.degrees(a), 0))
        lamp((0, -.12, 1.1), .07, GREEN_LAMP, True)
    return 1.3, 1.4


# ------------------------------------------------------------- the speedway
def quest_fuel_dump(done):
    """The pit lane's fuel: a tall red tank on legs, its yellow dump valve
    shut along the pipe, then thrown across and the pit hose spilling."""
    legs = mat(70, 72, 74, metal=.6, rough=.4)
    for x in (-.2, .2):
        for y in (-.15, .15):
            rod((x, y, 0), (x * .8, y * .8, .5), .025, legs)
    tank = mat(196, 38, 30, metal=.45, rough=.4, grime=.5)
    cyl(.26, .8, (0, 0, .9), tank, seg=22)
    ball(.26, (0, 0, 1.3), tank, (1, 1, .35))
    for z in (.6, 1.2):
        cyl(.265, .03, (0, 0, z), mat(236, 232, 220, metal=.3), seg=22)
    box(.26, .02, .16, (0, -.26, .95), mat(236, 222, 160, rough=.5))
    letters("FUEL", 0, -.27, .95, .02, mat(30, 26, 22))
    pipe = mat(60, 58, 54, metal=.7)
    rod((0, -.1, .52), (0, -.1, .34), .035, pipe)
    rod((0, -.1, .34), (0, -.4, .34), .035, pipe)
    cyl(.06, .1, (0, -.3, .34), mat(200, 196, 180, metal=.7), (90, 0, 0), seg=12)
    handle = stripes(HAZARD, SOOT, 12.0)
    if not done:
        box(.05, .3, .04, (0, -.3, .41), handle)
    else:
        box(.3, .05, .04, (.12, -.3, .41), handle)
        for k in range(5):
            box(.08, .06, .01, (-.05 + k * .05, -.48 - k * .04, .01), mat(80, 60, 30, rough=.1, grime=0), (0, 0, k * 25))
    path([(0, -.4, .34), (-.05, -.5, .18), (-.15, -.55, .03), (-.35, -.5, .02)], .025, mat(30, 30, 30))
    lamp((0, 0, 1.38), .075, RED_LAMP, not done)
    pilot((.15, -.22, .8), GREEN_LAMP, done, .03, (90, 0, -30))
    if done:
        tag((.27, -.3, .4))
    return 1.0, 1.6


def _checker(x0, z0, cols, rows, cell, y, wave=0.0, drop=False):
    white = mat(236, 232, 220, rough=.6, grime=.2)
    black = mat(26, 24, 22, rough=.6, grime=.2)
    for c in range(cols):
        for r in range(rows):
            off = math.sin(c * .9) * wave
            if drop:
                box(cell, .012, cell, (x0 + r * cell * .35, y + off - c * cell * .2, z0 - c * cell), white if (c + r) % 2 else black, (0, 12, 0))
            else:
                box(cell, .012, cell, (x0 + c * cell, y + off, z0 - r * cell), white if (c + r) % 2 else black)


def quest_flag(done):
    """The starter's stand: a box on legs and the green flag up in its holder
    under a red lamp; dropped, the flag hangs down off the rail, the lamp
    green."""
    wood = mat(190, 40, 30, metal=.3, rough=.5, grime=.55)
    for x in (-.3, .3):
        rod((x, .1, 0), (x * .8, 0, .9), .03, mat(60, 62, 64, metal=.6))
    box(.66, .4, .5, (0, 0, .9), wood)
    box(.66, .016, .1, (0, -.205, 1.08), stripes((26, 24, 22), (236, 232, 220), 10.0))
    box(.7, .44, .04, (0, 0, 1.17), mat(70, 72, 74, metal=.6))
    green = mat(40, 170, 60, rough=.6, grime=.2)
    staff = mat(120, 82, 50, rough=.5)
    if not done:
        rod((.2, -.12, 1.0), (.2, -.12, 1.75), .02, staff)
        for k in range(5):
            box(.08, .012, .32, (.24 + k * .075, -.12 + math.sin(k) * .03, 1.6), green)
        lamp((-.2, 0, 1.19), .08, RED_LAMP, True)
    else:
        rod((.33, -.24, 1.1), (.55, -.3, .7), .02, staff)
        for k in range(5):
            box(.3, .012, .08, (.47 + math.sin(k) * .02, -.3, 1.08 - k * .075), green, (0, -25, 0))
        lamp((-.2, 0, 1.19), .08, GREEN_LAMP, True)
    # The checkered flag rolled in its holder for later.
    rod((-.28, -.15, .7), (-.28, -.15, 1.35), .015, staff)
    for k in range(6):
        cyl(.035, .06, (-.28, -.15, 1.0 + k * .06), mat(*((26, 24, 22) if k % 2 else (236, 232, 220)), rough=.6), seg=10)
    return 1.2, 1.85


def quest_exit_flag(done):
    """The finish: the checkered flag on its pole by the starter's lamp,
    furled and chained to the pole under red until the way is clear, then
    flying, the lamp green."""
    foot(.5, .5)
    pole = mat(214, 210, 200, metal=.6, rough=.35, grime=.4)
    rod((0, 0, .05), (0, 0, 1.95), .035, pole)
    ball(.05, (0, 0, 1.97), mat(214, 160, 60, metal=.85, rough=.3))
    if not done:
        for k in range(10):
            cyl(.06 - k * .003, .1, (.04, -.02, 1.8 - k * .1), mat(*((26, 24, 22) if k % 2 else (236, 232, 220)), rough=.6), seg=12)
        chain_mat = mat(170, 166, 156, metal=.85, rough=.35)
        for z in (1.4, .95):
            hoop((.02, -.01, z), .08, .02, chain_mat, (0, 0, 0), seg=14)
        box(.08, .04, .09, (.1, -.08, .88), mat(214, 160, 60, metal=.8, rough=.3))
    else:
        _checker(.08, 1.88, 7, 5, .1, -.01, wave=.04)
    # The signal on a short post beside.
    rod((-.32, .05, .05), (-.32, .05, 1.0), .03, mat(60, 62, 62, metal=.6))
    box(.16, .14, .3, (-.32, .02, 1.12), mat(*SOOT))
    cyl(.06, .03, (-.32, -.06, 1.18), glow(RED_LAMP, 6.0) if not done else dark_glass(RED_LAMP), (90, 0, 0), seg=18)
    cyl(.06, .03, (-.32, -.06, 1.04), glow(GREEN_LAMP, 6.0) if done else dark_glass(GREEN_LAMP), (90, 0, 0), seg=18)
    return 1.3, 2.1


# ----------------------------------------------------------- the mothership
def _pedestal(h=.75):
    hull = mat(*ALIEN_HULL, metal=.55, rough=.4, grime=.55)
    cyl(.34, .08, (0, 0, .04), hull, seg=8)
    cyl(.22, h, (0, 0, h / 2 + .08), hull, seg=8, top=.16)
    cyl(.27, .04, (0, 0, h * .5), glow(ALIEN_GLOW, 3.0), seg=8)
    return hull


def quest_ship_drive(done):
    """The drive's feed: a socket glowing on a ribbed pedestal, a moonshine
    jug beside it under a pink glyph lamp; spiked, the jug upended in the
    socket and the glow gone green."""
    hull = _pedestal(.8)
    cyl(.24, .12, (0, 0, .94), hull, seg=12)
    socket_glow = (255, 90, 200) if not done else ALIEN_GLOW
    cyl(.13, .03, (0, 0, 1.01), glow(socket_glow, 4.0), seg=16)
    jug = mat(150, 104, 62, rough=.4, grime=.4)
    cream = mat(226, 214, 180, rough=.4, grime=.3)
    if not done:
        ball(.12, (.4, -.1, .14), jug, (1, 1, 1.15))
        cyl(.04, .1, (.4, -.1, .3), cream, seg=10)
        ring = cyl(.025, .02, (.46, -.1, .3), cream, (0, 90, 0), seg=8)
        box(.08, .01, .05, (.4, -.22, .14), mat(30, 26, 22))
    else:
        ball(.12, (0, 0, 1.2), jug, (1, 1, 1.15))
        cyl(.04, .1, (0, 0, 1.05), cream, seg=10)
        box(.08, .01, .05, (0, -.12, 1.22), mat(30, 26, 22), (180, 0, 0))
    for k in range(3):
        rod((-.12 + k * .12, .2, .4), (-.12 + k * .12, .4, .02), .03, mat(80, 84, 80, metal=.6))
    lamp((-.24, -.05, .95), .07, (255, 90, 200), not done)
    pilot((.0, -.21, .7), ALIEN_GLOW, done, .03)
    return 1.1, 1.5


def quest_ship_drain(done):
    """The cow tubes' drain: a glass tank of green coolant on a pedestal with
    a chrome lever; drained, the tank all but empty and the lever down."""
    hull = _pedestal(.55)
    cyl(.24, .06, (0, 0, .66), hull, seg=12)
    for k in range(4):
        a = k * math.tau / 4 + .4
        rod((math.cos(a) * .2, math.sin(a) * .2, .68), (math.cos(a) * .2, math.sin(a) * .2, 1.3), .015, mat(*CHROME, metal=.9))
    level = .5 if not done else .07
    cyl(.18, level, (0, 0, .7 + level / 2), glow(ALIEN_GLOW, 2.5), seg=20)
    cyl(.24, .06, (0, 0, 1.32), hull, seg=12)
    hub = (.26, -.06, .86)
    cyl(.05, .05, hub, mat(*CHROME, metal=.9), (0, 90, 0), seg=12)
    tip = (.32, -.24, 1.18) if not done else (.32, -.24, .54)
    rod(hub, tip, .022, mat(*CHROME, metal=.9, rough=.2))
    ball(.06, tip, glow((255, 90, 200), 2.5))
    lamp((-.1, 0, 1.35), .07, RED_LAMP, not done)
    pilot((0, -.2, .45), ALIEN_GLOW, done, .03)
    return 1.0, 1.6


def quest_ship_iris(done):
    """The captain's iris control: a tilted desk on its pedestal, the big dome
    button and the little iris rings glowing red, then pressed and green."""
    hull = _pedestal(.7)
    box(.6, .4, .08, (0, -.04, .86), hull, (-24, 0, 0))
    colour = (255, 60, 40) if not done else ALIEN_GLOW
    press = 0 if not done else -.035
    cyl(.15, .05, (0, -.06, .9), mat(40, 44, 46, metal=.6), (-24, 0, 0), seg=18)
    ball(.13, (0, -.07, .93 + press), glow(colour, 4.0), (1, 1, .6))
    for k in range(3):
        hoop((.2, -.12, .9), .04 + k * .03, .01, glow(colour, 3.0), (66, 0, 0), seg=16)
    for x in (-.22, -.15):
        box(.05, .04, .03, (x, -.14, .9), glow((255, 200, 70), 3.0), (-24, 0, 0))
    lamp((0, .16, .92), .07, RED_LAMP, not done)
    return 1.0, 1.3


def quest_ship_launch(done):
    """The escape outhouse's launch post: a big button under a glass cover
    lit red until the core is quiet, then the cover up and the button green."""
    hull = _pedestal(.8)
    box(.34, .34, .1, (0, 0, .93), hull)
    box(.3, .3, .03, (0, 0, .99), stripes(HAZARD, SOOT, 8.0))
    lit = (255, 60, 40) if not done else ALIEN_GLOW
    cyl(.1, .06, (0, 0, 1.04), glow(lit, 4.0), seg=20)
    frame = mat(*CHROME, metal=.9, rough=.2)
    lid = mat(60, 96, 120, rough=.15, grime=0)
    if not done:
        for x in (-.13, .13):
            for y in (-.13, .13):
                rod((x, y, 1.0), (x, y, 1.18), .01, frame)
        box(.26, .26, .012, (0, 0, 1.18), lid)
    else:
        for x in (-.13, .13):
            rod((x, .13, 1.0), (x, .2, 1.26), .01, frame)
        box(.26, .012, .26, (0, .17, 1.13), lid, (-12, 0, 0))
    lamp((.2, .14, 1.0), .06, RED_LAMP if not done else GREEN_LAMP, True)
    return 1.0, 1.4


# ------------------------------------------------------------------- items
def item_key(metal, cloth):
    """A big old barn key with a cloth tag knotted to its bow."""
    m = mat(*metal, metal=.85, rough=.3, grime=.35)
    hoop((-.2, 0, .3), .12, .08, m, (90, 0, 0), seg=20)
    rod((-.1, 0, .3), (.32, 0, .3), .05, m)
    box(.07, .07, .18, (.26, 0, .21), m)
    box(.07, .07, .13, (.15, 0, .23), m)
    cyl(.07, .05, (-.05, 0, .3), m, (0, 90, 0), seg=12)
    c = mat(*cloth, rough=.7, grime=.2)
    rod((-.3, 0, .24), (-.38, -.02, .15), .014, mat(230, 220, 190))
    box(.18, .03, .24, (-.43, -.02, .04), c, (0, -18, 0))
    box(.13, .032, .06, (-.43, -.025, .08), mat(240, 232, 214, grime=0), (0, -18, 0))
    ROOT.rotation_euler = Euler((0, math.radians(-14), math.radians(-10)))
    return .9, .6


def item_pa_patch():
    """The PA patch lead: a coil of orange cable, a jack plug at each end and a
    yellow tag marked PA."""
    cable = mat(240, 108, 26, rough=.45, grime=.2)
    for k in range(3):
        hoop((0, 0, .1 + k * .035), .22 - k * .02, .04, cable, (0, 0, k * 20), seg=24)
    plug = mat(30, 28, 26, rough=.5)
    tip = mat(*CHROME, metal=.9, rough=.25)
    for (a, b) in (((.2, -.05, .14), (.36, -.16, .2)), ((-.18, .1, .1), (-.34, .2, .06))):
        rod(a, b, .02, cable)
        d = (Vector(b) - Vector(a)).normalized()
        rod(b, Vector(b) + d * .1, .032, plug)
        rod(Vector(b) + d * .1, Vector(b) + d * .16, .012, tip)
    box(.16, .02, .11, (0, -.18, .3), mat(250, 210, 40, rough=.5, grime=.1), (0, 0, 0))
    letters("PA", 0, -.19, .3, .018, mat(36, 26, 14))
    rod((0, -.17, .24), (0, -.12, .17), .006, mat(230, 220, 190))
    ROOT.rotation_euler = Euler((math.radians(18), 0, 0))
    return .9, .6


# ------------------------------------------------------------------- table
STATIONS = {
    "quest_switch": lambda d: quest_switch(d, "mill"),
    "quest_switch_fair": lambda d: quest_switch(d, "fair"),
    "quest_switch_bayou": lambda d: quest_switch(d, "bayou"),
    "quest_switch_speedway": lambda d: quest_switch(d, "speedway"),
    "quest_relay": quest_relay,
    "quest_pa_rig": quest_pa_rig,
    "quest_patchbay": quest_patchbay,
    "quest_estop": quest_estop,
    "quest_brake": quest_brake,
    "quest_bell": quest_bell,
    "quest_exit": lambda d: quest_exit(d, "mill"),
    "quest_exit_fair": lambda d: quest_exit(d, "fair"),
    "quest_bolt": quest_bolt,
    "quest_latch": quest_latch,
    "quest_condenser": quest_condenser,
    "quest_valve": quest_valve,
    "quest_generator": quest_generator,
    "quest_fuel_drum": quest_fuel_drum,
    "quest_ignition": quest_ignition,
    "quest_fuel_dump": quest_fuel_dump,
    "quest_flag": quest_flag,
    "quest_exit_flag": quest_exit_flag,
    "quest_ship_drive": quest_ship_drive,
    "quest_ship_drain": quest_ship_drain,
    "quest_ship_iris": quest_ship_iris,
    "quest_ship_launch": quest_ship_launch,
}
# Shrunk to stand about chest high, the lamp within sight of a player
# standing at the lever (an exit and the bell a little taller).
SCALE = {
    "quest_switch": .83, "quest_switch_fair": .83, "quest_switch_bayou": .8,
    "quest_switch_speedway": .83, "quest_relay": .82, "quest_pa_rig": .8,
    "quest_patchbay": .9, "quest_brake": .95, "quest_bell": .82, "quest_exit": .86,
    "quest_exit_fair": .86, "quest_exit_flag": .83, "quest_bolt": .93,
    "quest_condenser": .97, "quest_fuel_dump": .82, "quest_flag": .8,
    "quest_ship_drain": .87,
}
ITEMS = {
    "item_key_brass": lambda: item_key((214, 160, 64), (210, 30, 22)),
    "item_key_steel": lambda: item_key((170, 178, 186), (240, 196, 30)),
    "item_pa_patch": item_pa_patch,
}


def renders():
    """Every picture this script makes: name -> (model, turn, pitch, scale)."""
    out = {}
    for name, make in STATIONS.items():
        for state, done in (("_off", False), ("_on", True)):
            out[name + state] = ((lambda m=make, d=done: m(d)), -28, 8, SCALE.get(name, 1.0))
    for name, make in ITEMS.items():
        out[name] = (make, -20, 34, 1.0)
    return out


def quest_main():
    global ROOT
    scene, camera = stage()
    os.makedirs(OUT, exist_ok=True)
    table = renders()
    names = list(table) if NAMES == "all" else [n for n in NAMES.split(",") if n in table]
    meta = {}
    for name in names:
        for ob in [o for o in bpy.data.objects if o.type in ("MESH", "EMPTY") and o.name != "cam"]:
            bpy.data.objects.remove(ob)
        ROOT = bpy.data.objects.new("root", None)
        scene.collection.objects.link(ROOT)
        holder = bpy.data.objects.new("root_turn", None)
        scene.collection.objects.link(holder)
        make, turn, pitch_deg, size = table[name]
        w, h = make()
        w, h = w * size, h * size
        holder.rotation_euler = Euler((0, 0, math.radians(turn)))
        holder.scale = (size, size, size)
        ROOT.parent = holder
        pitch = math.radians(pitch_deg)
        cw, ch = w + 1.2, h + .8
        scene.render.resolution_x = round(cw * QPPU * SS)
        scene.render.resolution_y = round(ch * QPPU * SS)
        camera.data.ortho_scale = max(cw, ch)
        look = Vector((0, 0, h / 2))
        back = Vector((0, -math.cos(pitch), math.sin(pitch)))
        camera.location = look + back * 12
        camera.rotation_euler = (math.pi / 2 - pitch, 0, 0)
        scene.render.filepath = os.path.join(OUT, "%s.png" % name)
        bpy.ops.render.render(write_still=True)
        meta[name] = [cw, ch, QPPU]
    path_ = os.path.join(OUT, "meta.json")
    old = json.load(open(path_)) if os.path.exists(path_) else {}
    old.update(meta)
    json.dump(old, open(path_, "w"))


quest_main()
