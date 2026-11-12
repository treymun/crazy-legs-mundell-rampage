"""The broken states of the props that break when shot or blasted
(godot/data/tuning/breakables.cfg names each whole picture's broken one):
splintered crates and barrels, burst drums and tanks, shattered jars and
jugs, a toppled flamingo, a bear with its stuffing out. Loaded by
town_props.py like a chapter's own file (exec'd into its namespace, so mat,
box, cyl, ball, beam, rock and the colours are in scope). Each is modelled
from plain shapes to stand where the whole one stood, at the same scale, so
the game swaps one picture for the other. Nothing is traced from another game.
"""

SCORCH = (34, 28, 24)
SOOT = (20, 17, 15)
BARREL_OAK = (124, 76, 42)
CRATE_WOOD = (82, 58, 36)
HOOP = (52, 48, 44)
GLASS_GREEN = (118, 176, 140)
JUG_CLAY = (200, 180, 140)


def _rotated(v, rot):
    return Euler([math.radians(a) for a in rot]).to_matrix() @ Vector(v)


def _ring(r, heights, m, z0=0.0, thick=.045, lean=0.0, turn=0.0):
    """Staves or shards stood round a ring of radius r, each its own height
    (0 leaves a gap), leaning out by `lean` degrees: a burst barrel's sides,
    the glass left in a smashed jar."""
    n = len(heights)
    for k, h in enumerate(heights):
        if h <= 0:
            continue
        a = k / n * math.tau + turn
        w = r * math.tau / n * .9
        tilt = lean * (.6 + .4 * ((k * 7) % 5) / 4.0)
        box(w, thick, h, (math.cos(a) * r, math.sin(a) * r, z0 + h / 2), m,
            (tilt, 0, math.degrees(a) + 90))


def _petals(r, z, n, length, out, m, width=None, skip=()):
    """Torn sheet metal curled out from a rim at height z: a drum or tank burst
    from inside. `out` is how far each leans out, in degrees."""
    for k in range(n):
        if k in skip:
            continue
        a = k / n * math.tau
        w = width if width else r * math.tau / n * .85
        lean = out * (.7 + .3 * ((k * 5) % 3) / 2.0)
        ln = length * (.6 + .4 * ((k * 3) % 4) / 3.0)
        # Hinged at the rim: the middle sits half a length up the lean.
        tip = Vector((math.cos(a), math.sin(a), 0)) * math.sin(math.radians(lean)) * ln / 2
        mid = Vector((math.cos(a) * r, math.sin(a) * r, z + math.cos(math.radians(lean)) * ln / 2)) + tip
        box(w, .02, ln, mid, m, (lean, 0, math.degrees(a) + 90))


def _hoop(c, r, m, rot=(0, 0, 0), t=.03, n=16):
    """An iron hoop (a ring of short bars), turned by `rot`."""
    pts = [Vector(c) + _rotated((math.cos(k / n * math.tau) * r, math.sin(k / n * math.tau) * r, 0), rot)
           for k in range(n)]
    for k in range(n):
        beam(pts[k], pts[(k + 1) % n], t, m)


def _plank(length, width, loc, m, rot, thick=.03):
    box(width, length, thick, loc, m, rot)


def _splinters(m, spots):
    for k, (x, y) in enumerate(spots):
        box(.03, .16 + (k % 3) * .05, .02, (x, y, .02), m, (0, 0, k * 47))


# ------------------------------------------------------------ wood and straw
def barrel_broken():
    # prop_barrel staved in: the bottom head and hoop, the staves round it
    # snapped off short, others lying where they fell, the top hoop down.
    oak = mat(*BARREL_OAK, planks=10.0, grime=.55)
    pale = mat(176, 128, 82, grime=.35)
    hoop = mat(*HOOP, metal=.6, grime=.6)
    cyl(.33, .05, (0, 0, .025), oak, seg=20)
    _ring(.31, [.42, .26, .55, 0, .3, .5, .18, 0, .46, .34, .58, .22, 0, .38, .5, .3], oak, lean=8)
    cyl(.335, .05, (0, 0, .14), hoop, seg=20, top=.335)
    for k, (x, y, a) in enumerate([(.55, -.1, 20), (-.5, .25, -35), (.2, -.55, 75), (-.3, -.5, 120)]):
        _plank(.62 - k * .06, .1, (x, y, .025), oak, (0, 6 * (k % 2), a))
    _hoop((.5, .3, .03), .3, mat(96, 90, 84, metal=.6, grime=.5), (10, 0, 30), t=.025)
    _splinters(pale, [(.1, -.4), (-.42, -.1), (.35, .45), (-.1, .5)])
    return 1.7, .9


def crate_broken():
    # prop_crate stove in: the base, the back and one side left standing
    # ragged, the front and lid planks thrown down, the brace snapped.
    wood = mat(*CRATE_WOOD, planks=7.0, grime=.55)
    pale = mat(170, 124, 80, grime=.35)
    box(.62, .62, .05, (0, 0, .025), wood)
    for k, h in enumerate([.6, .44, .62, .3]):
        box(.15, .04, h, (-.23 + k * .155, .29, h / 2), wood)
    for k, h in enumerate([.5, .22, .38]):
        box(.04, .15, h, (-.29, -.15 + k * .16, h / 2), wood)
    beam((-.25, .27, .08), (.05, .27, .4), .05, pale)
    beam((.12, .26, .46), (.24, .26, .6), .05, pale)
    for k, (x, y, a) in enumerate([(.2, -.5, 15), (-.15, -.62, -20), (.55, -.15, 80), (.48, .3, 104), (-.6, -.3, 60)]):
        _plank(.58 - (k % 3) * .12, .15, (x, y, .02 + (k % 2) * .03), wood, (4 * (k % 2), 0, a))
    _splinters(pale, [(.0, -.3), (.32, -.38), (-.4, .1), (.4, .1)])
    return 1.6, .8


def pallet_stack_broken():
    # The stack knocked down to two, the rest slid off and split.
    grey = mat(*GREY_WOOD, planks=16.0, grime=.5)
    pale = mat(176, 164, 140, grime=.35)
    for k in range(2):
        box(1.1, .9, .12, ((k % 2) * .04, 0, .06 + k * .14), grey, (0, 0, k * 3))
    box(1.1, .9, .12, (.35, -.45, .2), grey, (0, -16, 22))
    for k, (x, y, a) in enumerate([(-.7, .2, 70), (.8, .3, -10), (-.5, -.6, 30), (.2, .7, 95)]):
        _plank(.9 - (k % 2) * .3, .14, (x, y, .02), grey, (0, 5 * (k % 2), a))
    _splinters(pale, [(-.3, -.55), (.6, -.5), (-.75, -.1)])
    return 1.9, .6


def tnt_crate_broken():
    # What a crate of dynamite leaves: a charred, splintered box and a few
    # blackened sticks thrown clear.
    char = mat(64, 46, 32, planks=8.0, grime=.85)
    soot = mat(*SOOT, grime=.6)
    box(.82, .62, .05, (0, 0, .025), char)
    for k, h in enumerate([.3, .12, .4, .2, .08]):
        box(.17, .04, h, (-.34 + k * .17, .3, h / 2), char)
    for k, h in enumerate([.25, .1, .32]):
        box(.04, .2, h, (.4, -.2 + k * .2, h / 2), char)
    box(.6, .5, .02, (0, 0, .06), soot)
    for k, (x, y, a) in enumerate([(-.5, -.4, 30), (.5, .45, -60), (.1, -.55, 100)]):
        cyl(.05, .38, (x, y, .05), mat(150, 40, 34, rough=.5, grime=.7), (90, 0, a), seg=8)
        cyl(.052, .12, (x + math.cos(math.radians(a + 90)) * .14, y + math.sin(math.radians(a + 90)) * .14, .05),
            soot, (90, 0, a), seg=8)
    for k, (x, y, a) in enumerate([(-.6, .2, 70), (.65, -.15, 10)]):
        _plank(.45, .14, (x, y, .02), char, (0, 0, a))
    return 1.5, .5


def range_ammo_crate_broken():
    # The range's shell crate split open, its shells rolled out.
    crate = mat(*WOOD, planks=8.0, grime=.55)
    pale = mat(176, 130, 86, grime=.35)
    shell = mat(176, 40, 30, rough=.4, grime=.25)
    brass = mat(212, 170, 80, metal=.8, rough=.3)
    box(.8, .5, .05, (0, 0, .025), crate)
    for k, h in enumerate([.34, .2, .36, .1]):
        box(.2, .04, h, (-.3 + k * .2, .24, h / 2), crate)
    box(.04, .5, .22, (-.4, 0, .11), crate)
    _plank(.75, .3, (.15, -.48, .02), crate, (0, 0, 8))
    box(.8, .04, .4, (.5, .35, .12), crate, (-70, 0, 20))
    for k in range(14):
        x = -.55 + (k * 37 % 110) / 100.0
        y = -.45 + (k * 53 % 90) / 100.0
        cyl(.035, .14, (x, y, .035), shell, (90, 0, k * 41), seg=10)
        cyl(.037, .03, (x + math.cos(math.radians(k * 41 + 90)) * .07, y + math.sin(math.radians(k * 41 + 90)) * .07, .037),
            brass, (90, 0, k * 41), seg=10)
    _splinters(pale, [(.3, .0), (-.2, -.25)])
    return 1.5, .6


def range_hay_bale_broken():
    # A bale blown loose: a slumped heap, the twine snapped, wisps about.
    hay = mat(168, 128, 52, planks=30.0, grime=.55)
    loose = mat(196, 160, 84, grime=.4)
    box(.9, .5, .3, (0, 0, .15), hay)
    for x in (-.25, .25):
        box(.02, .52, .32, (x, 0, .15), mat(90, 70, 40))
    for k, (x, y, r, s) in enumerate([(.15, .05, .36, (1.3, 1.0, .5)), (.5, -.25, .28, (1.2, 1, .55)),
                                      (-.45, -.3, .26, (1.1, 1, .5))]):
        ball(r, (x, y, .3 + r * s[2] * .3 if k == 0 else r * s[2] * .7), hay, s, (0, 0, k * 40), seg=10)
    for k in range(9):
        a = k * .7
        box(.02, .26, .01, (math.cos(a) * (.55 + (k % 3) * .1), math.sin(a) * .5, .01), loose, (0, 0, k * 33))
    beam((-.4, -.3, .05), (.1, -.42, .12), .015, mat(90, 70, 40))
    beam((.2, .35, .3), (.55, .45, .05), .015, mat(90, 70, 40))
    return 1.6, .55


def mash_barrel_broken():
    # The mash barrel shot through: staves split, the mash out in a sour
    # puddle, the paddle down, the sacks still leant there.
    oak = mat(132, 92, 56, planks=14.0, grime=.6)
    hoop = mat(56, 50, 46, metal=.6, grime=.6)
    mash = mat(190, 160, 84, rough=.6, grime=.35)
    cyl(.44, .05, (0, 0, .025), oak, seg=20)
    _ring(.42, [.5, .7, .3, 0, .62, .45, .8, .2, 0, .55, .72, .4, .25, 0, .66, .5, .35, .6], oak, lean=10)
    cyl(.45, .05, (0, 0, .12), hoop, seg=20)
    cyl(.8, .012, (-.1, -.35, .006), mash, seg=24)
    for k in range(5):
        ball(.05 + (k % 3) * .015, (-.4 + k * .17, -.55 + (k % 2) * .1, .03), mat(220, 204, 150, rough=.4, grime=.1))
    beam((.2, -.5, .03), (.7, -.95, .05), .05, mat(*WOOD))
    _hoop((-.65, .3, .03), .42, mat(96, 90, 84, metal=.6, grime=.5), (8, 0, -20), t=.025)
    for k, (x, y, a) in enumerate([(.65, .5, 40), (-.75, -.1, 100)]):
        _plank(.7, .12, (x, y, .02), oak, (0, 0, a))
    sack = mat(170, 140, 92, rough=.95, grime=.5)
    box(.44, .3, .5, (.7, -.2, .25), sack, (0, -30, 6))
    box(.36, .24, .14, (.86, -.22, .52), sack, (0, -50, 6))
    return 2.0, .95


# ------------------------------------------------------------ glass and jugs
def jug_stack_broken():
    # The jug crate shot up: jug bottoms in the slats, shards about, one jug
    # knocked over whole.
    crate = mat(*GREY_WOOD, planks=8.0, grime=.6)
    clay = mat(*JUG_CLAY, rough=.4, grime=.4)
    box(.9, .6, .3, (0, 0, .15), crate)
    for k in range(6):
        x, y = -.3 + (k % 3) * .3, -.13 + (k // 3) * .26
        if k == 4:
            continue
        cyl(.12, .08 + (k % 3) * .04, (x, y, .34 + (k % 3) * .02), clay, seg=10)
    _ring(.11, [.12, 0, .2, .08, .16, 0], clay, z0=.34, thick=.02, turn=.4)
    for k in range(8):
        a = k * .85
        box(.06, .05, .02, (math.cos(a) * (.5 + (k % 3) * .08), math.sin(a) * .42, .02), clay, (0, 0, k * 29))
    ball(.12, (.55, -.35, .12), clay, (1.1, 1, 1), (0, 80, 30))
    cyl(.04, .1, (.66, -.4, .12), clay, (0, 80, 30), seg=8)
    return 1.4, .6


def specimen_jar_broken():
    # The jar shot through: a ring of glass teeth on the stand, the possum
    # slumped over the rim, the brine down the stand and out on the deck.
    stand = mat(70, 46, 30, planks=6.0, grime=.5)
    glass = mat(*GLASS_GREEN, rough=.15, metal=.1, grime=.2)
    brine = mat(60, 150, 100, emit=.5, grime=.2)
    box(.4, .4, .7, (0, 0, .35), stand)
    cyl(.24, .04, (0, 0, .72), mat(176, 140, 66, metal=.8), seg=16)
    _ring(.22, [.18, .08, .26, 0, .12, .2, 0, .16, .06, .22], glass, z0=.74, thick=.015, lean=-6)
    ball(.14, (.12, -.12, .86), mat(150, 146, 136, grime=.4), (1.2, .9, .8), (0, 30, 20))
    ball(.06, (.26, -.18, .8), mat(220, 200, 196, grime=.3))
    box(.1, .01, .5, (.05, -.205, .45), brine)
    cyl(.5, .01, (.1, -.25, .005), brine, seg=20)
    cyl(.24, .05, (-.45, .3, .03), mat(176, 140, 66, metal=.8), (70, 0, 20), seg=16)
    for k in range(6):
        box(.05, .04, .015, (-.3 + k * .13, -.45 + (k % 2) * .12, .01), glass, (0, 0, k * 37))
    return 1.3, 1.1


def cow_tube_broken():
    # The tube's glass gone but for its teeth, the Holstein slid down onto
    # the base, brine across the deck, the brass rods still standing.
    brass = mat(176, 140, 66, metal=.85, rough=.3, grime=.5)
    glass = mat(*GLASS_GREEN, rough=.15, metal=.1, grime=.2)
    brine = mat(40, 150, 90, emit=.6, grime=.2)
    cyl(.64, .22, (0, 0, .11), brass, seg=24)
    cyl(.66, .18, (0, 0, 2.31), brass, seg=24)
    cyl(.2, .3, (0, 0, 2.5), brass, seg=12)
    for k in range(5):
        a = k / 5 * math.tau + .3
        cyl(.03, 2.1, (math.cos(a) * .6, math.sin(a) * .6, 1.2), brass, seg=6)
    _ring(.5, [.4, .15, .55, .25, 0, .3, .1, .45, 0, .2, .5, .35, .12, 0, .28, .42], glass, z0=.22, thick=.02, lean=-8)
    _ring(.5, [0, .2, 0, .1, .25, 0, 0, .15, .3, 0, 0, .12, 0, .22, 0, 0], glass, z0=2.02, thick=.02)
    cyl(1.0, .012, (0, -.2, .006), brine, seg=28)
    hide = mat(232, 228, 214, grime=.3)
    patch = mat(24, 22, 22, grime=.2)
    body = Vector((0, -.1, .48))
    ball(.36, body, hide, (1.0, .62, .62), (0, 18, 20))
    ball(.16, body + Vector((.18, -.12, .1)), patch, (1.2, .6, .7))
    ball(.17, body + Vector((.38, -.2, -.12)), hide, (1.2, .9, 1.0))
    ball(.08, body + Vector((.52, -.26, -.16)), mat(220, 150, 150, grime=.2))
    for s in (1, -1):
        ball(.03, body + Vector((.44, -.32, -.06 + s * .05)), mat(10, 10, 10, grime=0))
    for k, (x, y, a) in enumerate([(-.2, -.1, 60), (.15, .1, 120), (-.25, .12, 20), (.2, -.12, 150)]):
        cyl(.04, .42, (body.x + x * 1.3, body.y + y - .1, .3), hide, (75, 0, a), seg=6)
    for k in range(8):
        box(.09, .06, .015, (-.8 + k * .22, -.6 + (k % 3) * .25, .015), glass, (0, 0, k * 31))
    return 2.2, 2.8


def nitro_rack_broken():
    # The rack shot up: two bottles blown to stubs, one down on the deck,
    # the top shelf knocked crooked.
    steel = mat(150, 152, 156, metal=.5, grime=.6)
    blue = mat(70, 120, 230, metal=.2, rough=.35, grime=.3)
    soot = mat(*SOOT, grime=.6)
    for x in (-.42, .42):
        box(.06, .3, 1.2 if x < 0 else 1.0, (x, 0, .6 if x < 0 else .5), steel)
    box(.9, .3, .05, (0, 0, .08), steel)
    box(.9, .3, .05, (0, 0, .62), steel)
    box(.92, .3, .05, (.0, 0, 1.0), steel, (0, 12, 0))
    for k, h in enumerate([.95, .22, .3, .95]):
        x = -.3 + k * .2
        if k == 3:
            continue
        cyl(.085, h, (x, .04, .1 + h / 2), blue if h > .5 else mat(70, 120, 230, metal=.2, rough=.6, grime=.7), seg=14)
        if h > .5:
            ball(.085, (x, .04, 1.06), blue, (1, 1, .6), seg=12)
            cyl(.05, .05, (x, .04, 1.14), mat(200, 34, 28, rough=.5), seg=10)
        else:
            _ring(.085, [.08, 0, .12, .05, 0, .1], blue, z0=.1 + h, thick=.015)
    cyl(.085, .9, (.5, -.45, .09), blue, (90, 0, 70), seg=14)
    cyl(.05, .05, (.66, -.88, .09), mat(200, 34, 28, rough=.5), (90, 0, 70), seg=10)
    box(.5, .4, .01, (-.05, -.1, .11), soot)
    return 1.6, 1.25


# ------------------------------------------------------ burst drums and tanks
def fuel_drum_burst():
    # A red fuel drum after it went up: split from the inside, the top torn
    # into curled petals, scorched black, the yellow band still on it.
    red = mat(176, 36, 28, metal=.5, rough=.5, grime=.7)
    band = mat(220, 180, 40, metal=.4, grime=.6)
    soot = mat(*SOOT, grime=.6)
    cyl(.33, .5, (0, 0, .25), red, seg=20)
    cyl(.335, .1, (0, 0, .3), band, seg=20)
    cyl(.335, .08, (0, 0, .06), soot, seg=20)
    cyl(.3, .02, (0, 0, .42), soot, seg=20)
    _petals(.33, .5, 10, .42, 58, red, skip=(3,))
    _petals(.335, .5, 10, .25, 75, soot, width=.08)
    box(.34, .02, .5, (.62, -.2, .02), red, (90, 0, 30))
    return 1.6, .95


def warning_barrel_broken():
    # The hazard barrel blown open: its lower half left, the top torn out in
    # orange and white tatters, scorched through.
    orange = mat(240, 120, 30, rough=.5, grime=.65)
    white = mat(250, 250, 240, rough=.5, grime=.55)
    soot = mat(*SOOT, grime=.6)
    cyl(.3, .36, (0, 0, .18), orange, seg=18)
    cyl(.305, .1, (0, 0, .3), white, seg=18)
    cyl(.27, .02, (0, 0, .34), soot, seg=18)
    _petals(.3, .36, 9, .36, 62, orange, skip=(2, 6))
    _petals(.302, .36, 9, .2, 80, soot, width=.07)
    box(.3, .02, .32, (-.5, .3, .02), white, (90, 0, -40))
    box(.25, .02, .28, (.45, .35, .02), orange, (90, 0, 25))
    return 1.4, .75


def propane_tank_broken():
    # The propane pig split along its top and scorched, sagged onto a
    # buckled leg, the dial blown off.
    tank = mat(222, 220, 212, metal=.3, rough=.4, grime=.75)
    soot = mat(*SOOT, grime=.6)
    tilt = (0, 7, 0)
    cyl(.4, 1.5, (0, 0, .56), tank, (0, 90 + tilt[1], 0), seg=20)
    for s in (1, -1):
        ball(.4, (s * .74, 0, .56 - s * .09), tank, (.4, 1, 1))
    for s in (1, -1):
        for y in (-.2, .2):
            h = .3 if s > 0 else .18
            box(.05, .05, h, (s * .5, y, h / 2), mat(70, 70, 70, metal=.5), (0, 0 if s > 0 else 25, 0))
    ball(.36, (.05, 0, .92), soot, (2.2, .5, .25))
    for k in range(7):
        x = -.55 + k * .18
        for s in (1, -1):
            box(.15, .02, .22, (x, s * .17, 1.0 - abs(x) * .06), tank, (s * -55, 7, 0))
    for k, (x, z, a) in enumerate([(-.45, .75, 20), (-.1, .82, -15), (.3, .7, 35)]):
        box(.26, .02, .07, (x, -.395, z), soot, (0, a, 0))
    cyl(.1, .14, (.85, -.6, .07), mat(160, 160, 158, metal=.7), (90, 0, 30), seg=10)
    return 2.1, 1.15


def gas_cans_broken():
    # The jerry cans shot through: one split and burnt, one on its side,
    # one holed and leaking, the caps knocked off.
    red = mat(190, 40, 30, metal=.4, rough=.4, grime=.6)
    soot = mat(*SOOT, grime=.6)
    box(.3, .16, .36, (-.18, 0, .18), red)
    for k in range(3):
        cyl(.018, .01, (-.25 + k * .07, -.085, .1 + k * .07), soot, (90, 0, 0), seg=8)
    box(.3, .16, .36, (.25, .1, .08), red, (90, 0, 17))
    box(.3, .16, .14, (0, .3, .07), soot)
    _ring(.12, [.2, .08, .15, 0, .12, .05], red, z0=.14, thick=.015, turn=.3)
    cyl(.5, .008, (.1, -.15, .004), mat(60, 50, 40, rough=.2, grime=.2), seg=18)
    cyl(.025, .1, (.45, -.3, .02), mat(220, 190, 60, metal=.6), (90, 0, 40), seg=6)
    return 1.0, .45


# --------------------------------------------------- coolers, crates, cargo
def cooler_broken():
    # The cooler kicked open: lid off and leant against it, a split in the
    # side, the cans rolled out.
    white = mat(226, 224, 214, rough=.5, grime=.55)
    blue = mat(50, 90, 170, rough=.5, grime=.45)
    box(.7, .42, .34, (0, 0, .19), white)
    box(.72, .44, .06, (0, 0, .05), blue)
    box(.04, .02, .3, (.1, -.215, .2), mat(30, 30, 34), (0, 18, 0))
    box(.72, .44, .07, (.0, .42, .25), blue, (-70, 0, 6))
    for k, (x, y) in enumerate([(-.45, -.35), (.4, -.4), (.6, .1)]):
        cyl(.04, .12, (x, y, .04), mat(190, 190, 194, metal=.8, rough=.3) if k % 2 else mat(190, 40, 34, metal=.6), (90, 0, k * 50), seg=10)
    cyl(.4, .008, (-.1, -.3, .004), mat(160, 180, 200, rough=.1, grime=.1), seg=16)
    return 1.3, .65


def ice_chest_broken():
    # The marine cooler busted: red lid knocked off on the boards, a crack
    # down the white, the beer out.
    box(.8, .45, .42, (0, 0, .21), mat(226, 224, 216, rough=.4, grime=.6))
    box(.04, .02, .36, (-.15, -.23, .2), mat(30, 30, 34), (0, -15, 0))
    box(.82, .47, .07, (.25, -.55, .04), mat(176, 38, 32, rough=.4, grime=.55), (0, 8, 25))
    for k, (x, y) in enumerate([(-.55, -.3), (.6, .2), (-.4, .4)]):
        cyl(.04, .12, (x, y, .04), mat(*([200, 200, 210] if k % 2 else [190, 40, 34]), metal=.7, rough=.3), (90, 0, k * 60), seg=10)
    cyl(.45, .008, (0, -.35, .004), mat(160, 180, 200, rough=.1, grime=.1), seg=16)
    return 1.5, .5


def alien_crate_broken():
    # The cargo pod burst: its lid blown off and down, the front staved in,
    # the glyph light gone dim and cracked, green muck inside.
    shell = mat(78, 92, 96, metal=.6, rough=.4, grime=.7)
    band = mat(196, 160, 40, metal=.4, grime=.55)
    box(.9, .8, .05, (0, 0, .025), shell)
    box(.9, .05, .7, (0, .38, .35), shell)
    for s in (1, -1):
        box(.05, .8, .55 if s > 0 else .4, (s * .43, 0, .27 if s > 0 else .2), shell)
    box(.9, .05, .3, (0, -.5, .2), shell, (-50, 0, 4))
    box(.94, .06, .06, (0, .4, .58), band)
    box(.94, .84, .06, (.0, 0, .12), band)
    box(.3, .02, .2, (-.15, -.6, .3), mat(60, 110, 80, emit=.3, grime=.4), (-50, 0, 4))
    box(.75, .6, .02, (0, 0, .07), mat(60, 150, 90, emit=.4, grime=.3))
    box(.7, .6, .05, (.55, .55, .04), shell, (4, 6, 30))
    return 1.8, .8


def mailbox_row_broken():
    # The row of mailboxes shot up: two knocked off into the dirt, one
    # hanging off its post, the last holed through.
    colours = [(170, 60, 50), (60, 90, 140), (200, 190, 170), (60, 110, 60)]
    for k in range(4):
        cyl(.03, .9, (-.45 + k * .3, 0, .45), mat(*GREY_WOOD), seg=6)
    box(.2, .34, .16, (-.55, -.4, .08), mat(*colours[0], metal=.5, grime=.75), (8, 0, 60))
    box(.2, .34, .16, (-.2, .05, .9), mat(*colours[1], metal=.5, grime=.75), (35, 0, 15))
    box(.2, .34, .16, (.25, -.45, .08), mat(*colours[2], metal=.5, grime=.75), (0, 90, -20))
    box(.2, .34, .16, (.45, 0, .95), mat(*colours[3], metal=.5, grime=.75))
    for k in range(3):
        cyl(.015, .01, (.42 + k * .03, -.175, .92 + k * .02), mat(*SOOT), (90, 0, 0), seg=6)
    box(.02, .03, .12, (-.62, -.25, .04), mat(200, 40, 30), (90, 0, 30))
    return 1.6, 1.05


# ------------------------------------------------------ the fair's and yards
def flamingo_broken():
    # The lawn flamingo shot off its legs: down on its side in the dirt.
    pink = mat(236, 104, 150, rough=.35, grime=.35)
    ball(.16, (0, 0, .13), pink, (1.6, .9, .8), (90, 0, 10))
    for k in range(6):
        t = k / 5.0
        ball(.04, (-.2 - t * .3, -.05 + math.sin(t * 2.4) * .06, .05), pink)
    ball(.06, (-.55, -.02, .06), pink)
    cyl(.03, .1, (-.62, -.02, .06), mat(20, 20, 20), (0, -90, 0), seg=6, top=.005)
    cyl(.008, .5, (.2, .12, .03), mat(60, 60, 60, metal=.6), (80, 0, 70), seg=4)
    cyl(.008, .3, (.05, .0, .14), mat(60, 60, 60, metal=.6), (0, 50, 10), seg=4)
    return 1.1, .35


def prize_bear_broken():
    # The prize bear burst at the seams: slumped, its head off beside it, an
    # arm gone, white stuffing out.
    fur = mat(140, 90, 200, rough=.95, grime=.2)
    stuff = mat(240, 236, 226, rough=.95, grime=.1)
    ball(.4, (0, 0, .34), fur, (1.05, .95, .8), (0, 14, 0))
    ball(.3, (.55, -.3, .27), fur, (1, 1, .9), (0, 60, 30))
    ball(.1, (.72, -.2, .5), fur)
    ball(.04, (.6, -.55, .3), mat(10, 10, 10, rough=.2, grime=0))
    ball(.08, (.5, -.58, .2), mat(240, 200, 220))
    ball(.13, (-.42, -.05, .45), fur, (1, 1, 1.5))
    ball(.15, (.2, -.18, .1), fur, (1, 1.3, .8))
    ball(.15, (-.2, -.2, .1), fur, (1, 1.3, .8))
    ball(.13, (-.7, -.4, .1), fur, (1.5, 1, 1), (0, 0, 40))
    for k in range(9):
        a = k * .8
        ball(.07 + (k % 3) * .03, (math.cos(a) * .22, -.25 + math.sin(a) * .1, .5 + (k % 4) * .08), stuff)
    for k in range(5):
        ball(.06, (-.4 + k * .25, -.6 + (k % 2) * .15, .04), stuff)
    box(.4, .05, .08, (-.1, -.42, .03), mat(250, 220, 60), (0, 0, 20))
    return 1.7, .85


def balloons_broken():
    # Most of the bunch popped: two left bobbing, limp strings, scraps of
    # rubber on the ground.
    colours = [(230, 50, 50), (60, 140, 220), (250, 220, 60), (80, 200, 100), (240, 120, 220)]
    for k, (x, z) in enumerate([(-.25, 1.75), (.2, 1.6)]):
        ball(.17, (x, -.1, z), mat(*colours[k * 2], rough=.2, grime=.05))
        cyl(.004, 1.1, (x * .5, -.05, .7 + (z - 1.5) * .5), mat(240, 240, 240), seg=3)
    for k in range(5):
        x = (k - 2) * .12
        beam((x * .4, -.05, .5), (x, -.08, 1.05 - (k % 2) * .2), .006, mat(240, 240, 240))
        box(.06, .02, .04, (x, -.08, 1.05 - (k % 2) * .2), mat(*colours[(k + 1) % 5], rough=.3), (0, 30 * k, 0))
    cyl(.04, .5, (0, 0, .25), mat(*WOOD), seg=6)
    for k in range(4):
        box(.07, .05, .01, (-.3 + k * .2, -.3 + (k % 2) * .2, .01), mat(*colours[k], rough=.3), (0, 0, k * 40))
    return 1.3, 1.95


MORE.update({
    "barrel_broken": barrel_broken, "crate_broken": crate_broken,
    "pallet_stack_broken": pallet_stack_broken, "tnt_crate_broken": tnt_crate_broken,
    "range_ammo_crate_broken": range_ammo_crate_broken, "range_hay_bale_broken": range_hay_bale_broken,
    "mash_barrel_broken": mash_barrel_broken, "jug_stack_broken": jug_stack_broken,
    "specimen_jar_broken": specimen_jar_broken, "cow_tube_broken": cow_tube_broken,
    "nitro_rack_broken": nitro_rack_broken, "fuel_drum_burst": fuel_drum_burst,
    "warning_barrel_broken": warning_barrel_broken, "propane_tank_broken": propane_tank_broken,
    "gas_cans_broken": gas_cans_broken, "cooler_broken": cooler_broken,
    "ice_chest_broken": ice_chest_broken, "alien_crate_broken": alien_crate_broken,
    "mailbox_row_broken": mailbox_row_broken, "flamingo_broken": flamingo_broken,
    "prize_bear_broken": prize_bear_broken, "balloons_broken": balloons_broken,
})
