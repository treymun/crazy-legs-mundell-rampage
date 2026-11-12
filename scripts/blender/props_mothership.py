"""The mothership's own props (chapter 7): what the greys hauled up from the
county and what they run the ship with. Loaded by town_props.py after
props_more.py (exec'd into its namespace, so mat, box, cyl, ball, wheel,
place, ROOT and the colours are in scope). Modelled here from plain shapes;
nothing is traced from another game."""

HULL = (92, 96, 88)
GLOW = (120, 255, 160)
COPPER = (184, 104, 58)


def _glow(r=GLOW[0], g=GLOW[1], b=GLOW[2], strength=4.0):
    return mat(r, g, b, emit=strength, grime=0)


def hung_pickup():
    """The pickup the tractor beam is holding up: nose high, a bale sliding out of the bed."""
    paint = mat(150, 52, 36, metal=.3, rough=.55, grime=.85)
    box(2.0, .9, .42, (0, 0, .62), paint)
    box(.78, .86, .5, (.28, 0, 1.08), paint)
    box(.03, .72, .32, (.68, 0, 1.12), mat(40, 54, 66, rough=.15, metal=.2))
    box(.86, .8, .06, (-.55, 0, .86), mat(70, 56, 40, grime=.7))
    box(.06, .9, .26, (-1.0, 0, .9), paint)
    box(.5, .42, .3, (-.55, .1, 1.04), mat(*STRAW, planks=30.0, grime=.35), (0, 0, 12))
    box(.4, .92, .14, (1.02, 0, .56), mat(*CHROME, metal=.8, grime=.6))
    for x in (-.65, .65):
        for y in (-.42, .42):
            wheel(.3, .2, (x, y, .3), mat(*CHROME, metal=.6), (90, 0, 0))
    ball(.08, (1.01, -.32, .74), mat(255, 230, 160, emit=3.0, grime=0))
    ROOT.rotation_euler = Euler((math.radians(8), math.radians(-18), math.radians(14)))
    return 2.6, 2.2


def cow_tube():
    """A Holstein afloat in green brine between brass rods, bubbles going up past her."""
    brass = mat(176, 140, 66, metal=.85, rough=.3, grime=.5)
    cyl(.64, .22, (0, 0, .11), brass, seg=24)
    cyl(.66, .18, (0, 0, 2.31), brass, seg=24)
    cyl(.2, .3, (0, 0, 2.5), brass, seg=12)
    for k in range(5):
        a = k / 5 * math.tau + .3
        cyl(.03, 2.1, (math.cos(a) * .6, math.sin(a) * .6, 1.2), brass, seg=6)
    cyl(.5, 2.0, (0, .22, 1.2), mat(40, 150, 90, emit=.9, grime=.2), seg=20)
    hide = mat(232, 228, 214, grime=.3)
    patch = mat(24, 22, 22, grime=.2)
    body = Vector((0, -.12, 1.25))
    ball(.36, body, hide, (1.0, .62, .7), (0, 0, 20))
    ball(.16, body + Vector((.18, -.12, .14)), patch, (1.2, .6, .8))
    ball(.14, body + Vector((-.16, -.14, -.05)), patch, (1.0, .6, 1.0))
    ball(.17, body + Vector((.36, -.06, .18)), hide, (1.2, .9, 1.0))
    ball(.08, body + Vector((.5, -.1, .14)), mat(220, 150, 150, grime=.2))
    for s in (1, -1):
        cyl(.05, .08, (body.x + .36, body.y - .02 + s * .1, body.z + .32), mat(220, 216, 200), (0, s * 30, 0), seg=6, top=.01)
        ball(.03, body + Vector((.44, -.17, .22 + s * .0)), mat(10, 10, 10, grime=0))
    for x in (-.2, .18):
        for y in (-.1, .1):
            cyl(.04, .42, (body.x + x, body.y + y, body.z - .34), hide, (12, -10, 0), seg=6)
    ball(.08, body + Vector((-.02, -.02, -.24)), mat(230, 160, 170, grime=.2))
    for k in range(9):
        ball(.025 + .01 * (k % 3), ((k % 3 - 1) * .25, -.4, .35 + k * .22), _glow(200, 255, 220, 2.0))
    return 1.6, 2.8


def probe_table():
    """The examining table: stirrups, a lamp, and an arm of probes in three sizes."""
    steel = mat(150, 156, 160, metal=.7, rough=.35, grime=.5)
    cyl(.18, .7, (0, 0, .35), steel, seg=12)
    box(1.7, .62, .1, (0, 0, .74), mat(176, 176, 160, grime=.45))
    box(1.6, .56, .06, (0, 0, .81), mat(110, 140, 120, rough=.6, grime=.4))
    for s in (1, -1):
        cyl(.02, .5, (.85, s * .2, 1.0), steel, (0, -30, 0), seg=6)
        cyl(.06, .14, (1.02, s * .2, 1.2), steel, (90, 0, 0), seg=10)
    cyl(.04, 1.8, (-.75, -.35, .9), steel, seg=8)
    box(.9, .06, .06, (-.33, -.35, 1.8), steel)
    for k, size in enumerate((.04, .07, .11)):
        x = -.2 + k * .2
        cyl(.015, .2, (x, -.35, 1.68), steel, seg=6)
        cyl(size, size * 4, (x, -.35, 1.48 - size * 1.5), mat(*CHROME, metal=.9, rough=.2), (180, 0, 0), seg=12, top=.005)
    cyl(.22, .1, (.3, -.2, 2.0), steel, (20, 0, 0), seg=14, top=.12)
    ball(.1, (.3, -.22, 1.94), mat(255, 240, 200, emit=4.0, grime=0))
    return 2.2, 2.3


def probe_rack():
    """The probes on the wall, smallest to biggest, the last one a comment."""
    wood = mat(*WOOD, planks=6.0, grime=.6)
    box(1.7, .08, 1.1, (0, .05, .9), mat(64, 70, 66, metal=.4, grime=.6))
    box(1.6, .1, .06, (0, -.02, .5), wood)
    for k in range(5):
        size = .04 + k * .035
        x = -.65 + k * .32
        cyl(.03, .16, (x, -.06, .62), mat(150, 40, 30, rough=.5), seg=8)
        cyl(size, .18 + k * .1, (x, -.06, .8 + k * .05), mat(*CHROME, metal=.9, rough=.2), seg=12, top=.008)
        box(.18, .01, .06, (x, -.04, .4), mat(220, 200, 150, grime=.3))
    return 1.8, 1.5


def corn_tray():
    """A planter of county corn grown under a violet lamp."""
    steel = mat(*HULL, metal=.6, rough=.4, grime=.6)
    box(1.4, .5, .3, (0, 0, .5), steel)
    box(1.34, .44, .04, (0, 0, .66), mat(60, 42, 28, grime=.4))
    for x in (-.6, .6):
        for y in (-.2, .2):
            box(.05, .05, .4, (x, y, .2), steel)
    stalk = mat(110, 150, 60, grime=.4)
    for k in range(6):
        x = -.55 + k * .22
        h = 1.0 + (k % 3) * .14
        cyl(.025, h, (x, (k % 2) * .08 - .04, .66 + h / 2), stalk, seg=6)
        for j in range(3):
            box(.36, .04, .02, (x + (.12 if j % 2 else -.12), 0, .9 + j * .25), stalk, (0, 40 if j % 2 else -40, k * 30))
        box(.06, .06, .18, (x + .04, -.03, 1.25 + (k % 3) * .1), mat(220, 196, 90, grime=.3))
    box(1.5, .3, .06, (0, 0, 2.05), steel)
    box(1.3, .2, .04, (0, 0, 2.0), mat(200, 120, 255, emit=5.0, grime=0))
    for x in (-.7, .7):
        cyl(.02, .6, (x, 0, 1.75), steel, seg=6)
    return 1.8, 2.2


def shine_tank():
    """A fuel tank of moonshine: copper on a cradle, gauges, a funnel, the jugs it came in."""
    copper = mat(*COPPER, metal=.85, rough=.32, grime=.55)
    cyl(.55, 1.6, (0, 0, .8), copper, (0, 90, 0), seg=24)
    for x in (-.6, 0, .6):
        cyl(.57, .06, (x, 0, .8), mat(90, 60, 40, metal=.7), (0, 90, 0), seg=24)
    for x in (-.5, .5):
        box(.12, .9, .3, (x, 0, .15), mat(70, 66, 60, metal=.5))
    cyl(.12, .2, (.2, -.5, .95), mat(220, 216, 200, rough=.3), (90, 0, 0), seg=12)
    cyl(.05, .2, (-.4, 0, 1.45), copper, seg=8)
    cyl(.16, .14, (-.4, 0, 1.6), copper, seg=12, top=.04)
    for k, x in enumerate((-.6, -.35, .5)):
        cyl(.11, .3, (x, -.62, .15), mat(220, 214, 196, rough=.3), seg=12, top=.05)
        box(.1, .01, .06, (x, -.73, .17), mat(30, 20, 16))
    return 2.0, 1.8


def ship_engine():
    """The drive: a green star in a cage of rings, sat on a tractor engine block, drinking shine."""
    block = mat(70, 74, 72, metal=.5, grime=.75)
    box(1.4, 1.0, .7, (0, 0, .35), block)
    for x in (-.45, -.15, .15, .45):
        cyl(.1, .2, (x, 0, .8), block, seg=10)
    cyl(.06, 1.0, (-.6, .3, 1.2), mat(*COPPER, metal=.8), (0, 30, 0), seg=8)
    ball(.55, (0, 0, 1.75), _glow(90, 230, 120, 1.6))
    for k, rot in enumerate(((90, 0, 0), (0, 90, 0), (45, 45, 0))):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=False, segments=32, radius1=.86, radius2=.86, depth=.08)
        place(bm, mat(120, 116, 104, metal=.8, rough=.3, grime=.5), (0, 0, 1.75), rot)
    for s in (1, -1):
        cyl(.18, .5, (s * .9, -.2, .25), mat(220, 214, 196, rough=.3), seg=12, top=.07)
        cyl(.04, .9, (s * .7, -.2, .75), mat(*COPPER, metal=.8), (0, s * 35, 0), seg=8)
    return 2.4, 2.8


def alien_console():
    """A sloped desk of lit buttons with a stolen TV set on it and a CB mic on its cord."""
    shell = mat(*HULL, metal=.5, rough=.45, grime=.6)
    box(1.2, .6, .7, (0, 0, .35), shell)
    box(1.2, .5, .06, (0, -.08, .78), mat(40, 44, 46), (-26, 0, 0))
    for k in range(10):
        colour = [(255, 70, 50), (255, 200, 70), (120, 255, 160)][k % 3]
        box(.08, .06, .03, (-.45 + (k % 5) * .22, -.1 - (k // 5) * .14, .82 + (k // 5) * .06), mat(*colour, emit=3.5, grime=0), (-26, 0, 0))
    tv = mat(96, 70, 44, planks=8.0, grime=.6)
    box(.5, .4, .4, (.25, .1, 1.0), tv)
    box(.36, .02, .28, (.22, -.1, 1.02), mat(120, 200, 180, emit=1.6, grime=.1))
    cyl(.01, .3, (.38, .2, 1.32), mat(*CHROME, metal=.8), (0, 30, 0), seg=4)
    cyl(.01, .3, (.12, .2, 1.32), mat(*CHROME, metal=.8), (0, -30, 0), seg=4)
    box(.1, .06, .14, (-.4, -.32, .9), mat(30, 30, 30))
    return 1.5, 1.5


def captain_chair():
    """The captain's chair: somebody's corduroy recliner, bolted to a chrome post."""
    cord = mat(130, 86, 50, grime=.5, planks=40.0)
    cyl(.1, .5, (0, 0, .25), mat(*CHROME, metal=.9, rough=.2), seg=12)
    cyl(.4, .06, (0, 0, .03), mat(*CHROME, metal=.9, rough=.2), seg=16)
    box(.8, .7, .3, (0, 0, .62), cord)
    box(.8, .25, .8, (0, .32, 1.05), cord, (-12, 0, 0))
    for s in (1, -1):
        box(.18, .72, .3, (s * .42, 0, .82), cord)
    box(.7, .5, .14, (0, -.55, .5), cord, (20, 0, 0))
    cyl(.05, .12, (.42, -.25, 1.02), mat(200, 40, 30, metal=.6, rough=.3), seg=8)
    box(.12, .08, .05, (-.42, -.25, .99), mat(255, 70, 50, emit=3.0, grime=0))
    ROOT.rotation_euler = Euler((0, 0, math.radians(-20)))
    return 1.2, 1.6


def trophy_gnome():
    """A lawn elf on a plinth with a brass plate, kept like a saint."""
    stone = mat(176, 170, 156, grime=.5)
    box(.6, .6, .7, (0, 0, .35), mat(70, 46, 30, planks=8.0, grime=.4))
    box(.66, .66, .06, (0, 0, .72), mat(176, 140, 66, metal=.8, rough=.3))
    cyl(.16, .3, (0, 0, .92), mat(70, 110, 170, grime=.4), seg=12, top=.13)
    ball(.12, (0, 0, 1.14), mat(230, 190, 160, grime=.3))
    ball(.11, (0, -.05, 1.06), mat(236, 236, 230, grime=.2), (1, .8, 1.2))
    cyl(.13, .34, (0, 0, 1.38), mat(200, 40, 34, grime=.3), seg=12, top=.005)
    box(.3, .01, .08, (0, -.31, .45), mat(176, 140, 66, metal=.8))
    return .9, 1.7


def deer_target():
    """A foam deer from somebody's back forty, three arrows in it."""
    foam = mat(150, 110, 70, grime=.5)
    ball(.36, (0, 0, .75), foam, (1.5, .7, .8))
    ball(.16, (.55, 0, 1.12), foam, (1.2, .7, .9))
    cyl(.07, .3, (.42, 0, .95), foam, (0, 50, 0), seg=8)
    for x in (-.35, .35):
        for y in (-.12, .12):
            cyl(.04, .55, (x, y, .3), foam, seg=6)
    for s in (1, -1):
        cyl(.015, .3, (.6, s * .06, 1.3), mat(90, 70, 50), (s * 30, -20, 0), seg=4)
    for k in range(3):
        cyl(.012, .5, (-.1 + k * .15, -.3, .8 + k * .05), mat(60, 50, 40), (70, 0, 10 * k), seg=4)
        cyl(.03, .06, (-.1 + k * .15, -.53, .78 + k * .05), mat(220, 40, 30), (70, 0, 0), seg=6)
    box(.6, .3, .04, (0, 0, .02), mat(40, 90, 40))
    return 1.6, 1.5


def pod():
    """A crew pod in its cradle: a grey asleep behind the glass till Maw calls it."""
    shell = mat(118, 124, 116, metal=.7, rough=.35, grime=.55)
    ball(.6, (0, 0, 1.15), shell, (1.0, 1.0, 1.55))
    ball(.4, (0, -.44, 1.25), _glow(110, 230, 150, 1.4), (1.0, .5, 1.3))
    ball(.15, (0, -.6, 1.34), mat(60, 90, 70, grime=.2), (1, .7, 1.15))
    for s in (1, -1):
        ball(.045, (s * .06, -.7, 1.37), mat(10, 14, 12, grime=0), (1, .6, 1.4))
    box(1.0, 1.0, .2, (0, 0, .1), mat(60, 62, 60, metal=.6))
    for k in range(4):
        a = k / 4 * math.tau + .78
        box(.1, .1, .7, (math.cos(a) * .5, math.sin(a) * .5, .4), shell, (0, 0, math.degrees(a)))
    return 1.4, 2.2


def jukebox_rig():
    """The county jukebox, wired into the ship: bubble tubes lit, cables to a dish."""
    wood = mat(130, 70, 40, planks=6.0, grime=.5)
    box(.9, .6, 1.1, (0, 0, .55), wood)
    cyl(.45, .6, (0, 0, 1.1), wood, (90, 0, 0), seg=24)
    box(.7, .02, .4, (0, -.31, .95), mat(255, 200, 120, emit=2.0, grime=.1))
    for s in (1, -1):
        cyl(.05, 1.0, (s * .4, -.3, .7), mat(255, 120, 200, emit=1.4, grime=0), seg=10)
    box(.6, .02, .2, (0, -.31, .45), mat(*CHROME, metal=.8))
    cyl(.03, 1.2, (.6, .2, .6), mat(30, 30, 30), (0, 40, 30), seg=6)
    cyl(.03, 1.2, (-.6, .2, .7), mat(30, 30, 30), (0, -40, -30), seg=6)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=False, segments=20, radius1=.34, radius2=.04, depth=.12)
    place(bm, mat(196, 194, 186, rough=.5, grime=.55), (0, .1, 1.75), (-60, 0, 0))
    return 1.6, 2.1


def escape_outhouse():
    """The way home: an outhouse strapped to a rocket, fins and all."""
    planks = mat(*GREY_WOOD, planks=9.0, grime=.55)
    box(.92, .9, 1.8, (0, 0, 1.3), planks)
    box(1.1, 1.1, .08, (0, -.04, 2.24), mat(92, 86, 80, metal=.4, grime=.7), (11, 0, 0))
    box(.62, .04, 1.4, (0, -.47, 1.15), mat(*WOOD, planks=7.0, grime=.5))
    ball(.09, (0, -.5, 1.6), mat(18, 14, 12, grime=0), (1, .3, 1))
    rocket = mat(200, 46, 36, metal=.5, rough=.35, grime=.5)
    cyl(.22, 2.2, (.62, .1, 1.3), rocket, seg=16)
    cyl(.22, .5, (.62, .1, 2.65), rocket, seg=16, top=.01)
    for k in range(3):
        a = k / 3 * math.tau
        box(.04, .4, .5, (.62 + math.cos(a) * .2, .1 + math.sin(a) * .2, .4), mat(220, 216, 200, metal=.4), (0, 0, math.degrees(a)))
    for z in (.8, 1.8):
        cyl(.5, .05, (.32, .05, z), mat(60, 60, 58, metal=.7), seg=20)
    cyl(.16, .3, (.62, .1, .05), mat(40, 38, 36, metal=.7), seg=12, top=.22)
    box(.3, .02, .2, (0, -.47, 2.0), mat(220, 210, 180, grime=.6))
    return 2.1, 3.0


def alien_crate():
    """A cargo pod: dented, banded, a glyph stencilled on and a county tag stuck over it."""
    shell = mat(*HULL, metal=.6, rough=.4, grime=.65)
    box(.9, .8, .7, (0, 0, .35), shell)
    for z in (.12, .58):
        box(.94, .84, .06, (0, 0, z), mat(196, 160, 40, metal=.4, grime=.5))
    box(.3, .02, .2, (-.15, -.41, .38), _glow(120, 255, 160, 1.2))
    box(.18, .02, .12, (.25, -.41, .3), mat(230, 220, 190, grime=.4))
    return 1.1, .9


def bunk():
    """A crew bunk: a steel shelf with somebody's grandma's quilt on it."""
    steel = mat(*HULL, metal=.6, rough=.4, grime=.6)
    for z in (.4, 1.3):
        box(1.8, .8, .1, (0, 0, z), steel)
        box(1.7, .74, .12, (0, 0, z + .1), mat(170, 60, 50, check=(70, 90, 140), grime=.4))
        box(.4, .5, .1, (-.6, 0, z + .2), mat(226, 220, 200, grime=.3))
    for x in (-.88, .88):
        for y in (-.36, .36):
            box(.06, .06, 1.7, (x, y, .85), steel)
    return 2.1, 1.9


def specimen_jar():
    """A possum in a jar on a stand, looking put out."""
    stand = mat(70, 46, 30, planks=6.0, grime=.5)
    box(.4, .4, .7, (0, 0, .35), stand)
    cyl(.22, .5, (0, 0, .98), mat(60, 150, 100, emit=.9, grime=.2), seg=16)
    ball(.14, (0, -.04, .95), mat(150, 146, 136, grime=.4), (1.2, .9, .9))
    ball(.06, (.13, -.1, 1.0), mat(220, 200, 196, grime=.3))
    cyl(.24, .06, (0, 0, 1.26), mat(176, 140, 66, metal=.8), seg=16)
    return .7, 1.4


def beam_emitter():
    """The tractor beam's head: a ring of lamps round a lens, hung from the ceiling."""
    steel = mat(*HULL, metal=.7, rough=.35, grime=.5)
    cyl(.9, .3, (0, 0, 1.0), steel, seg=24, top=.7)
    cyl(.6, .06, (0, 0, .84), _glow(170, 255, 200, 6.0), seg=24)
    for k in range(8):
        a = k / 8 * math.tau
        ball(.07, (math.cos(a) * .8, math.sin(a) * .8, .86), mat(255, 200, 80, emit=5.0, grime=0))
    cyl(.15, .4, (0, 0, 1.35), steel, seg=12)
    return 2.0, 1.6


SHIP = {
    "hung_pickup": hung_pickup, "cow_tube": cow_tube, "probe_table": probe_table,
    "probe_rack": probe_rack, "corn_tray": corn_tray, "shine_tank": shine_tank,
    "ship_engine": ship_engine, "alien_console": alien_console, "captain_chair": captain_chair,
    "trophy_gnome": trophy_gnome, "deer_target": deer_target, "pod": pod,
    "jukebox_rig": jukebox_rig, "escape_outhouse": escape_outhouse, "alien_crate": alien_crate,
    "bunk": bunk, "specimen_jar": specimen_jar, "beam_emitter": beam_emitter,
}
# Drawn flat on a wall in the game: rendered face on.
SHIP_FLAT = {"probe_rack"}
