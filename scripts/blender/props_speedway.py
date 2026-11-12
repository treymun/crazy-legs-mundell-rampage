"""The speedway's own props (chapter 6, Buzzard Bend): the truck stop and
its fuel island, the pits, the race cars, the junkyard's crusher and crane,
the infield camp and the floodlights over it all. Loaded by town_props.py
after props_more.py (exec'd into its namespace, so mat, box, cyl, ball,
wheel, beam, chain, _car_body, ROOT and the colours are in scope). Every
piece is modelled here from plain shapes; nothing is traced from another
game, and no real brand is painted on anything."""

SW_STEEL = (84, 86, 90)
SW_YELLOW = (212, 164, 40)
SW_CONCRETE = (150, 146, 136)
SW_SEG = {"0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd",
          "6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg"}


# ------------------------------------------------------------ helpers
def _sw_digits(text, cx, y, cz, h, m, mirror=False):
    """Block numbers painted on a side at y, centred on (cx, cz), h tall:
    seven-segment strokes, read from -Y (mirror: read from +Y)."""
    w, t = h * .52, h * .17
    gap = w + h * .4
    n = len(text)
    for i, ch in enumerate(text):
        k = (i - (n - 1) / 2) * gap
        # Seen from +Y the world's +X is screen left: the strokes' places are
        # mirrored, which mirrors each figure back the right way round.
        x0 = cx - k if mirror else cx + k
        segs = SW_SEG.get(ch, "")
        spots = {
            "a": (0, h / 2, w, t), "g": (0, 0, w, t), "d": (0, -h / 2, w, t),
            "f": (-w / 2, h / 4, t, h / 2 + t), "b": (w / 2, h / 4, t, h / 2 + t),
            "e": (-w / 2, -h / 4, t, h / 2 + t), "c": (w / 2, -h / 4, t, h / 2 + t),
        }
        for s in segs:
            dx, dz, sx, sz = spots[s]
            box(sx, .014, sz, (x0 + (-dx if mirror else dx), y, cz + dz), m)


def _sw_roundel(cx, y, cz, r, m, digits=1):
    """The white number circle on a door, stretched to a lozenge for two figures."""
    ball(r, (cx, y, cz), m, (1.0 + .45 * (digits - 1), .04, 1.0), seg=20)


def _sw_stock_car(body, stripe, number, ink, dents=0, rims=(220, 220, 214)):
    """A 1970s dirt-track stock car, nose to +X: slab sides, an open
    greenhouse with the cage inside, wide tyres, a spoiler, the number on
    both doors."""
    dark = mat(28, 28, 30, rough=.6, grime=.2)
    cage = mat(150, 152, 150, metal=.7, rough=.4, grime=.4)
    primer = mat(118, 116, 108, rough=.95, grime=.6)
    # A long, low slab: the deck and sides, the nose wedged down at the front.
    box(2.3, .9, .3, (0, 0, .39), body)
    box(.5, .86, .18, (1.06, 0, .37), body, (0, 10, 0))
    # The greenhouse set back: sloped pillars, a low roof, the cage inside.
    for s in (1, -1):
        beam((.2, s * .37, .54), (-.05, s * .37, .86), .06, body)
        beam((-.74, s * .37, .54), (-.6, s * .37, .86), .06, body)
    box(.66, .8, .05, (-.33, 0, .87), body)
    box(.84, .72, .26, (-.27, 0, .68), dark)
    for s in (1, -1):
        beam((.12, s * .4, .56), (-.62, s * .4, .84), .03, cage)
        beam((-.66, s * .4, .56), (.06, s * .4, .84), .03, cage)
    # The windscreen is a screen of mesh.
    mesh = mat(40, 42, 44, metal=.5, rough=.5)
    box(.03, .74, .4, (.075, 0, .7), mesh, (0, -40, 0))
    for t in (-.12, 0, .12):
        box(.035, .74, .012, (.075 - t * .64, 0, .7 + t * .77), cage, (0, -40, 0))
    # Stripes over the top, down the side.
    for s in (1, -1):
        box(2.32, .12, .012, (0, s * .13, .545), stripe)
        box(.68, .12, .012, (-.33, s * .13, .897), stripe)
        box(2.2, .012, .06, (0, s * .452, .47), stripe)
    # The number on each door, on a white roundel.
    white = mat(236, 232, 220, rough=.6, grime=.3)
    for s, mirror in ((-1, False), (1, True)):
        _sw_roundel(-.27, s * .455, .38, .135, white, len(number))
        _sw_digits(number, -.27, s * .466, .38, .14, ink, mirror)
    # Wide tyres, painted rims, a spoiler, bumpers, a side pipe.
    rim = mat(*rims, metal=.4, rough=.5, grime=.4)
    for x in (.72, -.72):
        for s in (1, -1):
            wheel(.27, .24, (x, s * .47, .27), rim, (90, 0, 0))
    box(.05, .92, .2, (-1.14, 0, .62), body, (0, -25, 0))
    for s in (1, -1):
        box(.28, .02, .2, (-1.06, s * .45, .6), body)
    box(.08, .9, .1, (1.33, 0, .28), dark)
    box(.08, .9, .1, (-1.18, 0, .3), dark)
    cyl(.04, .7, (.05, -.47, .2), mat(60, 56, 52, metal=.6, grime=.6), (0, 90, 0), seg=8)
    box(.46, .4, .02, (.8, -.15, .48), primer, (0, 10, 0))
    box(.3, .02, .16, (.6, -.452, .36), primer)
    for k in range(dents):
        ball(.12, (-.9 + k * .45, -.44, .34 + (k % 2) * .1), mat(40, 36, 32, grime=.3), (1.4, .1, .9))


# ------------------------------------------------------------ the truck stop
def fuel_pump():
    red = mat(190, 38, 30, metal=.3, rough=.45, grime=.55)
    trim = mat(*CHROME, metal=.8, rough=.3, grime=.4)
    box(.66, .52, .08, (0, 0, .04), mat(*SW_CONCRETE, grime=.7))
    box(.5, .38, 1.25, (0, 0, .705), red)
    box(.55, .43, .12, (0, 0, 1.39), mat(160, 30, 26, metal=.3, rough=.45, grime=.6))
    for z in (.5, 1.32):
        box(.52, .4, .03, (0, 0, z), trim)
    box(.34, .02, .3, (0, -.2, 1.06), mat(232, 222, 192, rough=.5, grime=.3))
    for k in range(3):
        box(.06, .022, .07, (-.1 + k * .1, -.205, 1.1), mat(30, 28, 26))
    box(.012, .024, .12, (.03, -.207, 1.0), mat(200, 30, 26), (0, 30, 0))
    box(.3, .02, .1, (0, -.2, .8), mat(26, 28, 30, rough=.2))
    cyl(.05, .12, (0, 0, 1.51), trim, seg=10)
    # The lit glass globe: a red rim and a red diamond on it, no lettering.
    globe = mat(246, 222, 150, rough=.3, emit=1.6, grime=0)
    ball(.2, (0, 0, 1.76), globe, (1, .6, 1), seg=20)
    cyl(.205, .05, (0, 0, 1.76), red, (90, 0, 0), seg=22)
    box(.11, .26, .11, (0, 0, 1.76), mat(200, 34, 28, emit=.6, grime=0), (0, 45, 0))
    box(.06, .12, .2, (.28, 0, .98), mat(30, 30, 30, metal=.5))
    hose = mat(24, 24, 24, rough=.7, grime=.2)
    pts = [(.28, 0, .9), (.34, -.04, .6), (.33, -.1, .32), (.3, -.14, .55), (.28, -.1, .92)]
    for a, b in zip(pts, pts[1:]):
        beam(a, b, .035, hose)
    for k in range(3):
        ball(.07, (-.2 + k * .18, -.19, .22), mat(*RUST, grime=.7), (1.3, .1, .9))
    return .9, 2.0


def semi_tractor():
    red = mat(168, 44, 36, metal=.35, rough=.55, grime=.7)
    dark_red = mat(128, 34, 30, metal=.3, rough=.6, grime=.75)
    trim = mat(*CHROME, metal=.85, rough=.3, grime=.4)
    glass = mat(30, 38, 46, rough=.15, metal=.2, grime=.3)
    steel = mat(40, 40, 42, metal=.5, grime=.5)
    box(3.0, .7, .2, (0, 0, .55), steel)
    box(1.0, 1.0, .72, (.95, 0, 1.08), red)
    box(.06, .82, .66, (1.47, 0, 1.06), trim)
    for z in (.84, .96, 1.08, 1.2, 1.32):
        box(.07, .78, .04, (1.48, 0, z), mat(20, 20, 22))
    box(.22, 1.12, .2, (1.56, 0, .56), trim)
    for s in (1, -1):
        cyl(.09, .04, (1.5, s * .38, 1.32), mat(250, 236, 180, emit=1.2, grime=0), (0, 90, 0), seg=12)
    box(.9, 1.16, 1.26, (.05, 0, 1.43), red)
    box(.05, 1.0, .46, (.5, 0, 1.76), glass, (0, -10, 0))
    box(.44, 1.18, .36, (.14, 0, 1.76), glass)
    box(.78, 1.16, 1.42, (-.78, 0, 1.51), dark_red)
    box(.7, 1.1, .18, (-.78, 0, 2.28), dark_red, (0, -8, 0))
    box(1.8, 1.18, .07, (.1, 0, 1.2), mat(226, 214, 180, grime=.5))
    for s in (1, -1):
        cyl(.07, 1.7, (-.34, s * .64, 1.95), trim, seg=12)
        cyl(.075, .04, (-.34, s * .64, 2.82), mat(30, 30, 30, metal=.5), (0, 30, 0), seg=12)
        cyl(.22, .72, (-.12, s * .63, .72), trim, (0, 90, 0), seg=16)
        box(.04, .32, .42, (-1.42, s * .46, .5), mat(20, 20, 20, rough=.8))
        box(.04, .26, .32, (.55, s * .6, 1.05), trim)
    box(.6, .8, .08, (-1.15, 0, .7), mat(22, 22, 22, metal=.4))
    rim = mat(170, 170, 166, metal=.6, rough=.4, grime=.5)
    for s in (1, -1):
        wheel(.42, .28, (1.05, s * .52, .42), rim, (90, 0, 0))
        for x in (-.55, -1.05):
            wheel(.42, .4, (x, s * .5, .42), rim, (90, 0, 0))
    for k in range(4):
        ball(.12, (-1.0 + k * .55, -.585, .9 + (k % 2) * .25), mat(*RUST, grime=.75), (1.6, .05, .7))
    ROOT.rotation_euler = Euler((0, 0, math.radians(20)))
    return 3.6, 2.9


def fuel_tank():
    shell = mat(204, 198, 184, metal=.3, rough=.6, grime=.75)
    steel = mat(*SW_STEEL, metal=.5, grime=.6)
    for x in (-.75, .75):
        for s in (1, -1):
            beam((x, s * .55, .02), (x, s * .2, .78), .08, steel)
        box(.16, .9, .1, (x, 0, .78), steel)
    cyl(.56, 2.2, (0, 0, 1.24), shell, (0, 90, 0), seg=24)
    for s in (1, -1):
        ball(.56, (s * 1.1, 0, 1.24), shell, (.18, 1, 1), seg=20)
    cyl(.565, .14, (0, 0, 1.24), mat(170, 40, 30, rough=.6, grime=.5), (0, 90, 0), seg=24)
    for k in range(5):
        box(.05, .02, .5, (-.9 + k * .42, -.55, 1.05), mat(*RUST, grime=.7))
    box(.24, .2, .34, (.4, 0, 1.95), mat(120, 40, 30, metal=.4, grime=.6))
    beam((.48, 0, 2.08), (.62, 0, 2.3), .03, mat(*CHROME, metal=.8))
    hose = mat(24, 24, 24, rough=.7, grime=.2)
    for a, b in [((.4, -.1, 1.85), (.62, -.6, 1.2)), ((.62, -.6, 1.2), (.7, -.62, .4))]:
        beam(a, b, .035, hose)
    box(.12, .14, .18, (.7, -.62, .32), mat(40, 40, 40, metal=.5))
    return 2.8, 2.1


def tow_truck():
    paint = mat(212, 120, 40, metal=.3, rough=.6, grime=.8)
    steel = mat(*SW_STEEL, metal=.5, grime=.6)
    glass = mat(30, 38, 46, rough=.15, metal=.2, grime=.3)
    box(2.8, .7, .18, (0, 0, .5), steel)
    box(.9, .96, .6, (.95, 0, .9), paint)
    box(.06, .78, .5, (1.41, 0, .86), mat(*CHROME, metal=.8, grime=.5))
    box(.2, 1.02, .18, (1.48, 0, .5), mat(*CHROME, metal=.8, grime=.5))
    box(.75, 1.0, .72, (.18, 0, 1.25), paint)
    box(.05, .86, .32, (.56, 0, 1.4), glass, (0, -14, 0))
    box(.4, 1.02, .3, (.22, 0, 1.4), glass)
    box(.5, .2, .1, (.18, 0, 1.66), mat(255, 160, 40, emit=2.2, grime=0))
    box(1.4, 1.0, .1, (-.75, 0, .66), steel)
    for s in (1, -1):
        box(1.1, .22, .36, (-.7, s * .44, .88), paint)
    beam((-.35, -.3, .7), (-1.1, -.05, 1.75), .1, steel)
    beam((-.35, .3, .7), (-1.1, .05, 1.75), .1, steel)
    beam((-1.1, 0, 1.75), (-1.45, 0, 1.6), .08, steel)
    cyl(.14, .5, (-.4, 0, .86), mat(40, 40, 40, metal=.6), (90, 0, 0), seg=12)
    beam((-1.45, 0, 1.55), (-1.45, 0, .7), .02, mat(30, 30, 30, metal=.6))
    hook = mat(*RUST, metal=.5, grime=.7)
    box(.12, .08, .16, (-1.45, 0, .64), hook)
    for k in range(7):
        a = math.radians(200 - k * 30)
        b = math.radians(170 - k * 30)
        beam((-1.45 + math.cos(a) * .1, 0, .45 + math.sin(a) * .1),
             (-1.45 + math.cos(b) * .1, 0, .45 + math.sin(b) * .1), .04, hook)
    rim = mat(170, 170, 166, metal=.6, rough=.4, grime=.5)
    for s in (1, -1):
        wheel(.36, .26, (.95, s * .5, .36), rim, (90, 0, 0))
        wheel(.36, .34, (-.75, s * .5, .36), rim, (90, 0, 0))
    for k in range(4):
        ball(.1, (-1.0 + k * .6, -.5, .8 + (k % 2) * .1), mat(*RUST, grime=.8), (1.5, .05, .7))
    ROOT.rotation_euler = Euler((0, 0, math.radians(20)))
    return 3.3, 2.3


# ------------------------------------------------------------ the race cars
def stock_car():
    _sw_stock_car(mat(222, 218, 206, metal=.25, rough=.5, grime=.6), mat(186, 34, 30, rough=.5),
                  "7", mat(186, 34, 30, rough=.5, grime=.2), dents=2, rims=(200, 40, 34))
    ROOT.rotation_euler = Euler((0, 0, math.radians(18)))
    return 2.6, 1.3


def stock_car_b():
    _sw_stock_car(mat(222, 184, 44, metal=.25, rough=.5, grime=.65), mat(26, 26, 28, rough=.5),
                  "13", mat(26, 26, 28, rough=.5, grime=.2), dents=4, rims=(30, 30, 30))
    ROOT.rotation_euler = Euler((math.radians(1.5), 0, math.radians(-16)))
    return 2.6, 1.3


def _sw_race(k):
    def make():
        _sw_stock_car(mat(46, 92, 176, metal=.3, rough=.45, grime=.5), mat(236, 128, 36, rough=.5),
                      "42", mat(236, 128, 36, rough=.5, grime=.15), dents=1, rims=(236, 128, 36))
        # The nose (+X) turned to camera-relative angle k*45 degrees (0: at the
        # viewer, 2: screen right); the stage then turns the whole prop -28.
        ROOT.rotation_euler = Euler((0, 0, math.radians(k * 45 - 90 + 28)))
        return 2.6, 1.3
    return make


def wrecked_derby():
    paint = mat(96, 128, 76, metal=.25, rough=.6, grime=.85)
    rust = _car_body(paint, 1.9, (.9, .42))
    crumple = mat(84, 110, 66, metal=.3, rough=.65, grime=.9)
    for k, (x, z, r) in enumerate([(.82, .78, 28), (.95, .66, -20), (.74, .9, 50)]):
        box(.42, .8, .06, (x, (k - 1) * .12, z), crumple, (k * 9, r, 12 - k * 10))
    box(.3, .9, .3, (.98, 0, .42), mat(70, 70, 68, metal=.5, grime=.8), (0, 0, 8))
    for s, mirror in ((-1, False), (1, True)):
        _sw_roundel(-.05, s * .44, .52, .14, mat(232, 228, 214, rough=.6, grime=.5), 2)
        _sw_digits("00", -.05, s * .449, .52, .14, mat(24, 24, 24, grime=.2), mirror)
    link = mat(70, 70, 72, metal=.7, rough=.4, grime=.5)
    chain((-.42, -.445, .66), (-.42, -.445, .32), link)
    chain((.32, -.445, .66), (.32, -.445, .32), link)
    rim = mat(60, 60, 60, metal=.5, grime=.6)
    for x, y in [(.62, .44), (-.62, .44), (-.62, -.44)]:
        wheel(.24, .16, (x, y, .26), rim, (90, 0, 0))
    box(.3, .25, .24, (.62, -.36, .12), mat(120, 118, 112, grime=.7))
    for k in range(4):
        ball(.12, (-.7 + k * .45, -.43, .55 + (k % 2) * .1), rust, (1.3, .1, .9))
    ROOT.rotation_euler = Euler((math.radians(4), math.radians(-5), math.radians(24)))
    return 2.5, 1.3


def monster_truck():
    purple = mat(104, 46, 132, metal=.3, rough=.5, grime=.6)
    primer = mat(118, 116, 108, rough=.95, grime=.6)
    glass = mat(30, 38, 46, rough=.15, metal=.2, grime=.3)
    steel = mat(40, 40, 42, metal=.5, grime=.5)
    rim = mat(*CHROME, metal=.8, rough=.3, grime=.4)
    for x in (.85, -.85):
        for s in (1, -1):
            wheel(.62, .5, (x, s * .76, .62), rim, (90, 0, 0))
            beam((x, s * .5, .62), (x * .8, s * .3, 1.15), .07, steel)
            cyl(.06, .5, (x * .7, s * .42, .95), mat(200, 40, 34, metal=.4), (0, 20 * s, 0), seg=8)
        box(.12, 1.2, .12, (x, 0, .62), steel)
    box(2.2, .9, .16, (0, 0, 1.2), steel)
    box(2.3, 1.02, .44, (0, 0, 1.5), purple)
    box(.85, .96, .5, (.12, 0, 1.97), purple)
    box(.75, .98, .34, (.12, 0, 2.0), glass)
    box(.06, .9, .34, (.56, 0, 2.0), glass, (0, -14, 0))
    box(.4, .3, .14, (.8, 0, 1.78), rim)
    for s in (1, -1):
        box(.9, .06, .22, (-.72, s * .48, 1.82), purple)
    flame = [mat(250, 150, 40, rough=.5, grime=.2), mat(250, 220, 70, rough=.5, grime=.2)]
    for s in (1, -1):
        for k in range(4):
            ball(.2, (.95 - k * .22, s * .515, 1.48 + (k % 2) * .06), flame[k % 2],
                 (1.6 - k * .25, .04, .32), (0, -8 + k * 6, 0))
    box(.5, .02, .25, (-.5, -.515, 1.5), primer)
    for x in (-.35, -1.0):
        for s in (1, -1):
            beam((x, s * .42, 1.72), (x, s * .42, 2.35), .06, steel)
        beam((x, -.42, 2.35), (x, .42, 2.35), .06, steel)
    for k in range(4):
        cyl(.08, .08, (-.35, -.3 + k * .2, 2.46), mat(250, 236, 180, emit=1.5, grime=0), (0, 90, 0), seg=12)
    box(.2, 1.0, .2, (1.22, 0, 1.3), steel)
    ROOT.rotation_euler = Euler((0, 0, math.radians(22)))
    return 3.3, 2.7


# ------------------------------------------------------------ the junkyard
def car_crusher():
    yellow = mat(*SW_YELLOW, metal=.35, rough=.5, grime=.75)
    dark_yellow = mat(170, 128, 30, metal=.35, rough=.55, grime=.8)
    steel = mat(*SW_STEEL, metal=.5, grime=.6)
    chrome = mat(*CHROME, metal=.85, rough=.3, grime=.3)
    box(3.0, 1.7, .15, (.2, 0, .075), mat(*SW_CONCRETE, grime=.8))
    for k in range(3):
        cyl(.28 + k * .1, .01, (-.4 + k * .7, .2 - k * .2, .16), mat(18, 16, 14, rough=.3, grime=0), seg=16)
    box(2.4, 1.4, 1.2, (0, 0, .75), yellow)
    for x in (-.9, -.3, .3, .9):
        box(.08, 1.44, 1.2, (x, 0, .75), dark_yellow)
    box(2.44, 1.44, .1, (0, 0, 1.35), dark_yellow)
    car = mat(70, 90, 120, metal=.3, grime=.85)
    box(2.2, 1.2, .2, (0, 0, 1.42), car, (0, 2, 0))
    for k in range(4):
        ball(.16, (-.8 + k * .5, -.2 + (k % 2) * .3, 1.5), car, (1.4, 1, .4))
    box(1.8, .02, .12, (0, -.61, 1.46), mat(30, 38, 46, rough=.2, grime=.5))
    for x in (-1.1, 1.1):
        for s in (1, -1):
            box(.2, .2, 2.1, (x, s * .62, 1.2), dark_yellow)
    for x in (-.75, .75):
        cyl(.07, .5, (x, 0, 1.95), chrome, seg=10)
        cyl(.15, .5, (x, 0, 2.45), steel, seg=12)
    box(2.5, 1.5, .26, (0, 0, 1.82), yellow)
    for k in range(10):
        box(.25, .02, .2, (-1.12 + k * .25, -.76, 1.82), mat(24, 22, 20) if k % 2 else yellow)
    box(.7, .6, .6, (-1.5, .4, .45), mat(70, 92, 66, metal=.3, grime=.7))
    beam((-1.15, .3, .6), (-.8, 0, 1.4), .06, mat(30, 30, 30, metal=.5))
    box(.08, .08, 1.0, (1.42, -.62, .5), steel)
    box(.3, .2, .38, (1.42, -.62, 1.15), mat(110, 110, 104, metal=.4, grime=.6))
    ball(.05, (1.42, -.73, 1.2), mat(255, 40, 30, emit=3.0, grime=0))
    slab = mat(150, 60, 50, metal=.3, rough=.6, grime=.85)
    box(1.9, .9, .22, (.15, -1.22, .12), slab, (0, 2, -6))
    for k in range(4):
        ball(.14, (-.6 + k * .45, -1.22 + (k % 2) * .25, .24), mat(*RUST, grime=.7), (1.4, 1, .25))
    cyl(.22, .06, (.95, -1.55, .05), mat(*TIRE), seg=16)
    ROOT.rotation_euler = Euler((0, 0, math.radians(15)))
    return 3.8, 2.6


def magnet_crane():
    o = -.9  # the model drawn round its middle, not round the turntable
    rusty = mat(196, 112, 40, metal=.35, rough=.6, grime=.85)
    steel = mat(*SW_STEEL, metal=.5, grime=.6)
    dark = mat(36, 36, 38, metal=.5, grime=.5)
    glass = mat(30, 38, 46, rough=.15, metal=.2, grime=.3)
    for s in (1, -1):
        box(2.0, .5, .42, (o, s * .66, .26), dark)
        for x in (-1.0, 1.0):
            cyl(.21, .5, (o + x, s * .66, .26), dark, (90, 0, 0), seg=14)
    cyl(.7, .2, (o, 0, .6), steel, seg=20)
    box(1.6, 1.3, 1.0, (o - .2, 0, 1.2), rusty)
    box(.66, .62, .8, (o + .55, -.34, 1.6), rusty)
    box(.6, .64, .4, (o + .58, -.34, 1.72), glass)
    box(.5, 1.2, .7, (o - 1.15, 0, 1.05), dark)
    p0, p1 = Vector((o + .45, 0, 1.6)), Vector((o + 2.6, 0, 5.15))
    for s in (1, -1):
        beam(p0 + Vector((0, s * .2, 0)), p1 + Vector((0, s * .1, 0)), .11, rusty)
        beam(p0 + Vector((0, s * .2, .3)), p1 + Vector((0, s * .1, .1)), .09, rusty)
    for k in range(10):
        a = p0.lerp(p1, k / 10)
        b = p0.lerp(p1, (k + 1) / 10)
        for s in (1, -1):
            beam(a + Vector((0, s * .18, 0)), b + Vector((0, s * .17, .25)), .03, steel)
    cyl(.14, .3, (o + 2.6, 0, 5.2), dark, (90, 0, 0), seg=14)
    beam((o - .9, 0, 2.0), (o + 2.6, 0, 5.2), .02, mat(30, 30, 30, metal=.6))
    beam((o + 2.6, 0, 5.1), (o + 2.6, 0, 2.55), .025, mat(30, 30, 30, metal=.6))
    box(.22, .16, .2, (o + 2.6, 0, 2.5), rusty)
    cyl(.56, .3, (o + 2.6, 0, 2.22), mat(70, 70, 72, metal=.6, grime=.7), seg=22)
    for k in range(6):
        a = k * math.tau / 6
        box(.1, .1, .32, (o + 2.6 + math.cos(a) * .5, math.sin(a) * .5, 2.22), dark)
    slab = mat(150, 52, 40, metal=.3, grime=.85)
    box(1.3, .5, .3, (o + 2.62, 0, 1.86), slab, (0, -8, 0))
    box(.7, .52, .08, (o + 2.5, 0, 2.03), mat(30, 38, 46, rough=.15, grime=.5), (0, -8, 0))
    for x in (-.45, .45):
        cyl(.16, .06, (o + 2.62 + x, -.26, 1.82 - x * .1), mat(*TIRE), (90, 0, 0), seg=14)
    return 4.8, 5.6


def crushed_stack():
    colours = [(150, 52, 44), (60, 96, 140), (196, 176, 120), (78, 110, 70)]
    for k in range(4):
        slab = mat(*colours[k], metal=.3, rough=.65, grime=.85)
        x = (.08, -.1, .12, -.04)[k]
        box(2.0, .92, .28, (x, 0, .15 + k * .3), slab, ((k % 2) * 3 - 1.5, (k % 3 - 1) * 2, (-6, 5, -3, 7)[k]))
        box(1.9, .94, .05, (x, 0, .27 + k * .3), mat(30, 38, 44, rough=.2, grime=.5), (0, 0, (-6, 5, -3, 7)[k]))
        for j in range(3):
            ball(.13, (x - .7 + j * .6, -.46, .16 + k * .3), mat(*RUST, grime=.75), (1.5, .08, .6))
        cyl(.2, .06, (x + (.7 if k % 2 else -.7), -.47, .12 + k * .3), mat(*TIRE), (90, 0, 0), seg=14)
    return 2.4, 1.5


def tire_pile():
    tyre = mat(52, 50, 48, rough=.9, grime=.35)
    hole = mat(10, 10, 10, grime=0)
    flat = [(-.5, 0, .1, 0), (.15, .1, .1, 15), (.6, -.1, .1, 0), (-.15, -.15, .3, 25),
            (.35, .05, .3, -10), (-.6, .1, .3, 0)]
    for x, y, z, tilt in flat:
        cyl(.34, .2, (x, y, z), tyre, (tilt, 0, 0), seg=20)
        cyl(.19, .215, (x, y, z), hole, (tilt, 0, 0), seg=16)
        cyl(.27, .205, (x, y, z), mat(196, 192, 180, rough=.7, grime=.5), (tilt, 0, 0), seg=18)
        cyl(.24, .21, (x, y, z), tyre, (tilt, 0, 0), seg=18)
    cyl(.34, .2, (.0, .05, .76), tyre, (90, 0, 20), seg=20)
    cyl(.19, .21, (.0, .05, .76), hole, (90, 0, 20), seg=16)
    cyl(.34, .2, (.82, .2, .36), tyre, (70, 0, -30), seg=20)
    cyl(.19, .21, (.82, .2, .36), hole, (70, 0, -30), seg=16)
    return 2.0, 1.1


def hubcap_board():
    tin = mat(120, 118, 110, metal=.4, rough=.6, grime=.8)
    box(1.8, .05, 1.0, (0, 0, .5), tin)
    for z in (.02, .98):
        box(1.82, .06, .04, (0, 0, z), mat(*WOOD, grime=.6))
    caps = [(-.68, .74, .15), (-.3, .76, .13), (.08, .72, .16), (.48, .75, .14), (.78, .7, .1),
            (-.72, .32, .13), (-.32, .28, .16), (.1, .3, .13), (.5, .26, .15),
            (-.05, .52, .09), (.82, .34, .11)]
    for k, (x, z, r) in enumerate(caps):
        face = mat(*CHROME, metal=.85, rough=.3, grime=.45) if k % 4 else mat(200, 40, 34, metal=.4, rough=.5)
        cyl(r, .03, (x, -.04, z), face, (90, 0, 0), seg=18)
        cyl(r * .45, .04, (x, -.05, z), mat(150, 150, 150, metal=.8, rough=.3, grime=.3), (90, 0, 0), seg=12)
        ball(.012, (x, -.07, z), mat(20, 20, 20))
    for k in range(5):
        ball(.08, (-.8 + k * .4, -.03, .1 + (k % 2) * .8), mat(*RUST, grime=.7), (1.4, .1, .8))
    return 1.9, 1.05


# ------------------------------------------------------------ the pits
def tool_chest():
    red = mat(184, 34, 30, metal=.35, rough=.4, grime=.5)
    chrome = mat(*CHROME, metal=.85, rough=.3, grime=.3)
    for x in (-.32, .32):
        for y in (-.16, .16):
            cyl(.05, .05, (x, y, .05), mat(30, 30, 30), (90, 0, 0), seg=10)
    box(.8, .45, .82, (0, 0, .52), red)
    box(.82, .47, .3, (0, 0, 1.08), red)
    box(.84, .49, .04, (0, 0, .93), chrome)
    for z in (.2, .35, .5, .65, .8, 1.0, 1.13):
        box(.6, .02, .025, (0, -.24, z), chrome)
    beam((-.3, -.05, 1.25), (.05, .1, 1.25), .035, chrome)
    box(.08, .06, .05, (.05, .1, 1.26), chrome)
    beam((.15, -.1, 1.25), (.35, .05, 1.25), .03, mat(*WOOD))
    box(.06, .14, .06, (.35, .05, 1.27), mat(60, 60, 64, metal=.6))
    box(.4, .015, .1, (0, -.25, 1.05), mat(230, 220, 190, grime=.3))
    return 1.0, 1.3


def engine_stand():
    red = mat(184, 40, 32, metal=.35, rough=.45, grime=.6)
    block = mat(196, 92, 40, metal=.35, rough=.55, grime=.7)
    chrome = mat(*CHROME, metal=.85, rough=.3, grime=.3)
    beam((-.45, 0, .05), (.4, 0, .05), .07, red)
    beam((-.3, -.35, .05), (-.3, .35, .05), .07, red)
    for p in [(.4, 0), (-.3, -.35), (-.3, .35)]:
        cyl(.04, .05, (p[0], p[1], .02), mat(30, 30, 30), (90, 0, 0), seg=8)
    beam((-.3, 0, .05), (-.3, 0, .7), .08, red)
    beam((-.3, 0, .7), (-.1, 0, .7), .06, red)
    box(.5, .44, .38, (.15, 0, .7), block)
    for s in (1, -1):
        box(.5, .2, .24, (.15, s * .2, .96), block, (s * 32, 0, 0))
        box(.48, .1, .08, (.15, s * .26, 1.06), chrome, (s * 32, 0, 0))
    box(.4, .16, .12, (.15, 0, 1.0), mat(90, 90, 92, metal=.6, grime=.6))
    cyl(.12, .06, (.43, 0, .66), mat(40, 40, 40, metal=.5), (0, 90, 0), seg=14)
    box(.36, .3, .1, (.15, 0, .48), mat(40, 40, 40, metal=.4))
    return 1.2, 1.25


def nitro_rack():
    steel = mat(*SW_STEEL, metal=.5, grime=.6)
    blue = mat(70, 120, 230, metal=.2, rough=.35, grime=.3)
    for x in (-.42, .42):
        box(.06, .3, 1.2, (x, 0, .6), steel)
    for z in (.08, .62, 1.08):
        box(.9, .3, .05, (0, 0, z), steel)
    for k in range(4):
        x = -.3 + k * .2
        cyl(.085, .95, (x, .04, .58), blue, seg=14)
        ball(.085, (x, .04, 1.06), blue, (1, 1, .6), seg=12)
        cyl(.04, .1, (x, .04, 1.14), mat(*CHROME, metal=.8), seg=8)
        cyl(.05, .05, (x, .04, 1.2), mat(200, 34, 28, rough=.5), seg=10)
        box(.1, .012, .16, (x, -.045, .65), mat(236, 232, 220, grime=.3))
    chain((-.42, -.11, .85), (.42, -.11, .85), mat(70, 70, 72, metal=.7, rough=.4))
    return 1.1, 1.4


def trophy():
    gold = mat(214, 170, 60, metal=.85, rough=.3, grime=.25)
    box(.6, .6, .45, (0, 0, .225), mat(*WOOD, planks=7.0, grime=.6))
    box(.4, .4, .15, (0, 0, .525), mat(30, 28, 26, rough=.4, grime=.2))
    box(.3, .012, .08, (0, -.205, .525), gold)
    cyl(.05, .22, (0, 0, .71), gold, seg=12)
    cyl(.14, .06, (0, 0, .62), gold, seg=16)
    cyl(.12, .42, (0, 0, 1.03), gold, seg=20, top=.26)
    for s in (1, -1):
        beam((s * .15, 0, .96), (s * .32, 0, 1.05), .035, gold)
        beam((s * .32, 0, 1.05), (s * .24, 0, 1.22), .035, gold)
    box(.3, .14, .08, (0, 0, 1.3), gold)
    box(.14, .12, .06, (-.02, 0, 1.37), gold)
    for x in (-.1, .1):
        for s in (1, -1):
            cyl(.035, .03, (x, s * .075, 1.27), gold, (90, 0, 0), seg=8)
    return .9, 1.6


def pa_horns():
    wood = mat(*GREY_WOOD, planks=5.0, grime=.6)
    grey = mat(150, 152, 148, metal=.5, rough=.5, grime=.6)
    cyl(.07, 3.3, (0, 0, 1.65), wood, seg=10)
    box(1.0, .1, .1, (0, 0, 3.0), wood)
    for x, z, d in [(-.42, 3.12, (0, 1, 0)), (.42, 3.12, (0, 1, 0)), (-.2, 2.78, (-1, .8, 0)), (.2, 2.78, (1, .8, 0))]:
        v = Vector((d[0] * .4, -1, -.15)).normalized()
        rot = [math.degrees(a) for a in v.to_track_quat("Z", "Y").to_euler()]
        cyl(.06, .44, Vector((x, 0, z)) + v * .2, grey, rot, seg=14, top=.22)
        cyl(.08, .14, Vector((x, 0, z)) - v * .05, mat(60, 62, 60, metal=.5), rot, seg=10)
        cyl(.19, .012, Vector((x, 0, z)) + v * .425, mat(26, 26, 28, grime=0), rot, seg=14)
    beam((0, -.08, 2.9), (0, -.08, .2), .02, mat(20, 20, 20))
    box(.18, .12, .24, (0, -.1, 1.4), mat(110, 110, 104, metal=.4, grime=.6))
    return 1.3, 3.5


def flag_stand():
    wood = mat(*GREY_WOOD, planks=6.0, grime=.6)
    for x in (-.6, .6):
        for y in (-.6, .6):
            beam((x * 1.08, y * 1.08, 0), (x, y, 2.25), .1, wood)
    for y in (-.6, .6):
        beam((-.62, y, .3), (.62, y, 1.8), .06, wood)
    beam((-.62, -.6, 1.2), (-.62, .6, 1.2), .06, wood)
    box(1.5, 1.5, .1, (0, 0, 2.28), mat(*WOOD, planks=8.0, grime=.6))
    for x in (-.72, .72):
        for y in (-.72, .72):
            box(.07, .07, .9, (x, y, 2.78), wood)
    for z in (2.85, 3.18):
        box(1.5, .05, .06, (0, -.72, z), wood)
        box(.05, 1.5, .06, (.72, 0, z), wood)
        box(1.5, .05, .06, (0, .72, z), wood)
    for s in (1, -1):
        beam((-.95, s * .2, 0), (-.72, s * .2, 2.3), .05, wood)
    for k in range(9):
        z = .25 + k * .24
        box(.05, .44, .04, (-.95 + (z / 2.3) * .23, 0, z), wood)
    box(.12, .12, .4, (.4, -.78, 2.6), mat(60, 60, 60, metal=.5))
    flags = [mat(40, 160, 60, rough=.7, grime=.2), mat(232, 200, 40, rough=.7, grime=.2),
             mat(236, 236, 230, rough=.7, grime=.2, check=(20, 20, 20))]
    for k, f in enumerate(flags):
        lean = (-12 + k * 12)
        top = Vector((.4 + math.sin(math.radians(lean)) * .7, -.8, 2.45 + .7))
        beam((.4, -.8, 2.45), top, .02, mat(*WOOD))
        box(.56, .02, .4, top + Vector((.28 if k != 0 else -.28, 0, -.2)), f, (0, -lean * .5, 0))
    return 2.2, 3.5


# ------------------------------------------------------------ the infield camp
def cooler():
    white = mat(226, 224, 214, rough=.5, grime=.5)
    blue = mat(50, 90, 170, rough=.5, grime=.45)
    box(.7, .42, .34, (0, 0, .19), white)
    box(.72, .44, .06, (0, 0, .05), blue)
    box(.72, .44, .07, (0, .02, .4), blue, (-5, 0, 0))
    for s in (1, -1):
        box(.04, .14, .05, (s * .37, 0, .3), mat(40, 40, 40))
    for k, (x, y) in enumerate([(-.15, -.02), (.12, .06)]):
        cyl(.04, .12, (x, y, .52 + k * .02), mat(190, 190, 194, metal=.8, rough=.3) if k else mat(190, 40, 34, metal=.6), seg=10)
    cyl(.03, .02, (.3, -.22, .08), mat(30, 30, 30), (90, 0, 0), seg=8)
    return .9, .6


def _sw_chair(x, turn, web):
    frame = mat(190, 192, 194, metal=.7, rough=.3, grime=.4)
    rz = math.radians(turn)
    def at(px, py, pz):
        return (x + px * math.cos(rz) - py * math.sin(rz), px * math.sin(rz) + py * math.cos(rz), pz)
    box(.48, .42, .03, at(0, 0, .38), web, (0, 0, turn))
    box(.48, .03, .48, at(0, .22, .64), web, (-12, 0, turn))
    for sx in (-.24, .24):
        beam(at(sx, -.2, 0), at(sx, .2, .38), .025, frame)
        beam(at(sx, .2, 0), at(sx, -.2, .38), .025, frame)
        beam(at(sx, .2, .38), at(sx, .26, .9), .025, frame)
        beam(at(sx, -.2, .55), at(sx, .2, .55), .03, frame)


def camp_chairs():
    _sw_chair(-.5, 18, mat(70, 140, 70, rough=.8, grime=.4, check=(226, 226, 214)))
    _sw_chair(.5, -18, mat(196, 64, 50, rough=.8, grime=.4, check=(226, 226, 214)))
    box(.34, .24, .24, (0, -.1, .12), mat(190, 40, 34, rough=.5, grime=.4))
    box(.36, .26, .05, (0, -.1, .26), mat(226, 224, 214, rough=.5, grime=.4))
    cyl(.035, .11, (.06, -.12, .34), mat(190, 190, 194, metal=.8, rough=.3), seg=10)
    return 1.7, 1.0


def burn_barrel():
    rust = mat(*RUST, metal=.4, rough=.7, grime=.85)
    cyl(.3, .9, (0, 0, .45), rust, seg=18)
    for z in (.02, .3, .6, .89):
        cyl(.31, .04, (0, 0, z), mat(90, 46, 26, metal=.5, grime=.8), seg=18)
    hot = mat(255, 140, 40, emit=4.0, grime=0)
    for k in range(5):
        a = math.radians(-120 + k * 20)
        ball(.03, (math.cos(a) * .3, math.sin(a) * .3, .2 + (k % 2) * .25), hot)
    flames = [mat(255, 120, 30, emit=5.0, grime=0), mat(255, 200, 70, emit=6.0, grime=0)]
    for k, (x, y, r, h, tilt) in enumerate([(0, 0, .22, .45, 0), (-.1, .05, .14, .35, -14),
                                             (.12, -.04, .13, .3, 16), (.02, -.08, .1, .25, 6)]):
        cyl(r, h, (x, y, .92 + h / 2), flames[k % 2], (0, tilt, 0), seg=10, top=.0)
    for k in range(4):
        ball(.015, (-.15 + k * .1, -.05, 1.25 + (k % 2) * .08), hot)
    return .8, 1.35


def canned_ham():
    cream = mat(226, 214, 180, rough=.55, grime=.6)
    teal = mat(70, 168, 160, rough=.5, grime=.6)
    glass = mat(30, 38, 46, rough=.15, metal=.2, grime=.3)
    box(1.9, 1.0, .9, (0, 0, .95), cream)
    for s in (1, -1):
        cyl(.45, 1.0, (s * .95, 0, .95), cream, (90, 0, 0), seg=24)
    box(2.4, 1.02, .3, (0, 0, .62), teal)
    for s in (1, -1):
        box(2.84, .012, .1, (0, s * .506, 1.05), teal)
    box(.5, .02, .34, (.45, -.51, 1.08), glass)
    box(.56, .1, .05, (.45, -.55, 1.29), teal, (20, 0, 0))
    box(.36, .02, .66, (-.45, -.51, .88), mat(206, 196, 166, rough=.55, grime=.6))
    ball(.025, (-.34, -.525, .85), mat(*CHROME, metal=.8))
    box(.02, .6, .3, (1.38, 0, 1.0), glass, (0, 25, 0))
    for k in range(4):
        box(.03, .014, .3, (.25 + k * .1, -.51, .8), mat(140, 80, 40, grime=.7))
    rim = mat(200, 196, 186, metal=.5, grime=.5)
    for s in (1, -1):
        wheel(.22, .14, (.1, s * .5, .22), rim, (90, 0, 0))
    for s in (1, -1):
        beam((1.3, s * .35, .48), (1.85, 0, .42), .05, mat(40, 40, 42, metal=.5))
    box(.06, .06, .4, (1.8, 0, .22), mat(40, 40, 42, metal=.5))
    cyl(.12, .36, (1.55, 0, .7), mat(236, 232, 220, metal=.3, grime=.4), seg=14)
    ROOT.rotation_euler = Euler((0, 0, math.radians(10)))
    return 3.2, 1.9


# ------------------------------------------------------------ the floodlights
def floodlight_tower():
    steel = mat(150, 152, 150, metal=.6, rough=.45, grime=.6)
    box(.7, .7, .2, (0, 0, .1), mat(*SW_CONCRETE, grime=.75))
    base, top = .3, .14
    levels = 12
    for i in range(levels):
        z0 = .2 + i * .5
        z1 = z0 + .5
        r0 = base + (top - base) * i / levels
        r1 = base + (top - base) * (i + 1) / levels
        corners0 = [(r0, r0), (-r0, r0), (-r0, -r0), (r0, -r0)]
        corners1 = [(r1, r1), (-r1, r1), (-r1, -r1), (r1, -r1)]
        for k in range(4):
            beam((*corners0[k], z0), (*corners1[k], z1), .05, steel)
            j = (k + 1) % 4
            if (i + k) % 2:
                beam((*corners0[k], z0), (*corners1[j], z1), .02, steel)
            else:
                beam((*corners0[j], z0), (*corners1[k], z1), .02, steel)
    box(1.6, .12, .12, (0, 0, 6.25), steel)
    box(1.6, .12, .12, (0, 0, 6.85), steel)
    for x in (-.75, .75):
        box(.08, .08, .7, (x, 0, 6.55), steel)
    housing = mat(60, 62, 64, metal=.5, grime=.5)
    lamp = mat(255, 244, 210, emit=7.0, grime=0)
    for z in (6.48, 7.06):
        for x in (-.5, 0, .5):
            box(.42, .24, .36, (x, .02, z), housing, (12, 0, 0))
            box(.36, .02, .3, (x, -.11, z - .02), lamp, (12, 0, 0))
    box(.16, .12, .24, (0, -.2, 1.4), mat(110, 110, 104, metal=.4, grime=.6))
    beam((0, -.2, 1.5), (0, -.16, 6.2), .025, mat(30, 30, 30))
    return 1.8, 7.4


def _sw_props():
    out = {
        "fuel_pump": fuel_pump, "semi_tractor": semi_tractor, "stock_car": stock_car,
        "stock_car_b": stock_car_b, "car_crusher": car_crusher, "magnet_crane": magnet_crane,
        "crushed_stack": crushed_stack, "monster_truck": monster_truck, "cooler": cooler,
        "camp_chairs": camp_chairs, "burn_barrel": burn_barrel, "floodlight_tower": floodlight_tower,
        "canned_ham": canned_ham, "tool_chest": tool_chest, "engine_stand": engine_stand,
        "trophy": trophy, "pa_horns": pa_horns, "flag_stand": flag_stand, "fuel_tank": fuel_tank,
        "tow_truck": tow_truck, "nitro_rack": nitro_rack, "wrecked_derby": wrecked_derby,
        "hubcap_board": hubcap_board, "tire_pile": tire_pile,
    }
    for k in range(8):
        out["race_car_%d" % k] = _sw_race(k)
    return out


MORE.update(_sw_props())
