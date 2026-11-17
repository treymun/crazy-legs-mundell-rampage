"""The Moonshine Run's own props (chapter 7, Copperhead Ridge by night): the
revenue men's cruisers with their light bars, the striped barricades at
their roadblocks and the flares by them, their wall tents and radio mast, a
lantern hung on a cave timber, and Granny Hooten's big copper still with the
Revenue Man's dynamite wired to it. Loaded by town_props.py after
props_more.py (exec'd into its namespace, so mat, box, cyl, ball, wheel,
beam, chain, ROOT and the colours are in scope). Every piece is modelled here
from plain shapes; nothing is traced from another game, and no real maker's
car or badge is copied: the cruiser is a generic big sedan of the time."""

MS_BLACK = (30, 30, 34)
MS_WHITE = (226, 224, 214)
MS_GOLD = (214, 168, 64)
MS_RED = (255, 40, 30)
MS_BLUE = (40, 90, 255)
MS_COPPER = (190, 108, 60)
MS_CANVAS = (112, 108, 74)

# Block letters three wide and five high, standing proud of a face.
MS_GLYPHS = {
    "A": ["010", "101", "111", "101", "101"],
    "C": ["111", "100", "100", "100", "111"],
    "D": ["110", "101", "101", "101", "110"],
    "E": ["111", "100", "110", "100", "111"],
    "L": ["100", "100", "100", "100", "111"],
    "N": ["101", "111", "111", "101", "101"],
    "O": ["111", "101", "101", "101", "111"],
    "R": ["110", "101", "110", "101", "101"],
    "S": ["111", "100", "111", "001", "111"],
    "T": ["111", "010", "010", "010", "010"],
    "U": ["101", "101", "101", "101", "111"],
    "V": ["101", "101", "101", "101", "010"],
    "X": ["101", "101", "010", "101", "101"],
    ".": ["000", "000", "000", "000", "010"],
}


def _ms_letters(text, cx, y, cz, size, m, facing=-1):
    """Block letters on a face at depth y, read from the side `facing` (-1:
    seen from -Y; 1: from +Y, mirrored so they read right there)."""
    width = len(text) * 4 * size - size
    left = cx - width / 2
    for i, ch in enumerate(text):
        rows = MS_GLYPHS.get(ch)
        if rows is None:
            continue
        for r, row in enumerate(rows):
            for c, bit in enumerate(row):
                if bit != "1":
                    continue
                x = left + (i * 4 + c) * size + size / 2
                if facing > 0:
                    x = 2 * cx - x
                box(size * 1.02, size * .6, size * 1.02, (x, y + facing * size * .3, cz + (2 - r) * size), m)


def _ms_letters_x(text, x, cy, cz, size, m, facing=1):
    """The same letters on a face at x, read from +X (facing 1) or -X."""
    width = len(text) * 4 * size - size
    left = cy - width / 2
    for i, ch in enumerate(text):
        rows = MS_GLYPHS.get(ch)
        if rows is None:
            continue
        for r, row in enumerate(rows):
            for c, bit in enumerate(row):
                if bit != "1":
                    continue
                y = left + (i * 4 + c) * size + size / 2
                if facing > 0:
                    y = 2 * cy - y
                box(size * .6, size * 1.02, size * 1.02, (x + facing * size * .3, y, cz + (2 - r) * size), m)


def _ms_star(cx, y, cz, r, m, facing=-1):
    """A five-point badge star flat on a face at depth y."""
    for k in range(5):
        a = math.radians(90 + k * 72)
        tip = (cx + math.cos(a) * r, cz + math.sin(a) * r)
        box(r * .34, .012, r * 1.05, ((tip[0] + cx) / 2, y + facing * .006, (tip[1] + cz) / 2), m,
            (0, -math.degrees(a) + 90, 0))
    cyl(r * .42, .016, (cx, y + facing * .008, cz), m, (90, 0, 0), seg=10)


# ------------------------------------------------------------ the cruiser
def cruiser():
    """The revenue men's cruiser, nose to +X: a long square-cut sedan in black
    with white front doors and the gold star of the revenue on them, REVENUE
    along the rear doors, a push bar on the nose, a spotlight by the
    windscreen and the light bar on the roof, red to the driver's side,
    blue to the other, lit."""
    black = mat(*MS_BLACK, metal=.35, rough=.4, grime=.45)
    white = mat(*MS_WHITE, metal=.3, rough=.45, grime=.45)
    chrome = mat(*CHROME, metal=.85, rough=.3, grime=.4)
    glass = mat(24, 30, 38, rough=.12, metal=.3, grime=.25)
    dark = mat(22, 22, 24, rough=.7, grime=.3)
    gold = mat(*MS_GOLD, metal=.7, rough=.35, grime=.3)
    # The body: a long low slab, the hood and trunk lids a touch lower.
    box(2.5, 1.22, .36, (0, 0, .46), black)
    box(.7, 1.18, .08, (.86, 0, .66), black)
    box(.56, 1.18, .08, (-.94, 0, .66), black)
    # The white doors (the front pair), both sides.
    for s in (1, -1):
        box(.66, .012, .34, (.18, s * .614, .47), white)
        box(.7, .012, .03, (-.5, s * .614, .55), mat(180, 176, 166, metal=.5, rough=.4))
    # The greenhouse: square pillars, the roof, the glass.
    box(1.2, 1.12, .07, (-.2, 0, 1.04), black)
    box(1.1, 1.08, .34, (-.2, 0, .86), glass)
    for s in (1, -1):
        beam((.42, s * .54, .66), (.3, s * .54, 1.03), .07, black)
        beam((-.82, s * .54, .66), (-.74, s * .54, 1.03), .08, black)
        beam((-.2, s * .55, .68), (-.2, s * .55, 1.02), .06, black)
    # Bumpers, grille, the lamps fore and aft.
    box(.08, 1.24, .14, (1.27, 0, .34), chrome)
    box(.08, 1.24, .14, (-1.27, 0, .34), chrome)
    box(.04, .9, .16, (1.26, 0, .5), dark)
    for s in (1, -1):
        box(.04, .22, .12, (1.265, s * .47, .52), mat(250, 244, 210, emit=3.0, grime=0))
        box(.04, .26, .1, (-1.265, s * .44, .52), mat(200, 30, 24, emit=1.2, grime=.1))
    # The push bar: two uprights and a bar across, rubber on the face.
    for s in (1, -1):
        beam((1.31, s * .3, .2), (1.42, s * .3, .66), .06, dark)
    box(.08, .82, .08, (1.43, 0, .62), dark)
    box(.08, .82, .08, (1.42, 0, .36), dark)
    # The wheels with their dog-dish caps.
    for x in (.8, -.8):
        for s in (1, -1):
            cyl(.25, .2, (x, s * .58, .25), mat(*TIRE, rough=.95, grime=.2), (90, 0, 0), seg=20)
            cyl(.13, .21, (x, s * .58, .25), chrome, (90, 0, 0), seg=14)
    # The star on each front door and REVENUE down the back doors.
    for s in (1, -1):
        _ms_star(.18, s * .622, .5, .12, gold, facing=s)
        _ms_letters("REVENUE", -.56, s * .622, .56, .016, white, facing=s)
    _ms_letters_x("U.S.", -1.31, 0, .5, .024, gold, facing=-1)
    # The spotlight by the driver's pillar, the antenna whip on the trunk.
    cyl(.07, .12, (.38, .66, .96), chrome, (0, 90, 0), seg=12)
    cyl(.06, .01, (.45, .66, .96), mat(255, 250, 220, emit=2.0, grime=0), (0, 90, 0), seg=12)
    beam((-1.0, -.3, .7), (-1.08, -.3, 1.7), .012, dark)
    # The light bar across the roof: chrome base, red and blue domes, lit.
    box(.26, 1.0, .07, (-.12, 0, 1.11), chrome)
    for s, colour in ((1, MS_RED), (-1, MS_BLUE)):
        for k in range(2):
            y = s * (.14 + k * .2)
            box(.2, .17, .13, (-.12, y, 1.21), mat(*colour, rough=.25, emit=4.0, grime=0))
    box(.14, .1, .1, (-.12, 0, 1.2), mat(250, 246, 220, emit=2.0, grime=0))
    return 3.0, 1.4


# ------------------------------------------------------------ the roadblock
def _ms_sawhorse(broken=False):
    """A barricade: two splayed A-frame legs, the striped rail and a plank
    painted ROAD CLOSED across them, an amber flasher on the end."""
    wood = mat(*GREY_WOOD, planks=4.0, grime=.6)
    stripe_a = mat(232, 104, 26, rough=.5, grime=.45)
    stripe_b = mat(*MS_WHITE, rough=.5, grime=.45)
    for x in (-.48, .48):
        for s in (1, -1):
            if broken and x > 0 and s > 0:
                box(.05, .05, .6, (x + .2, s * .2, .06), wood, (90, 0, 30))
                continue
            beam((x, 0, .82), (x, s * .26, 0), .05, wood)
        box(.04, .5, .04, (x, 0, .3), wood)
    if broken:
        # Split down the middle: one half hanging, one on the ground.
        for k in range(4):
            colour = stripe_a if k % 2 == 0 else stripe_b
            box(.17, .05, .14, (-.48 + k * .16, -.04, .79 - k * .07), colour, (0, 18, 0))
        box(.62, .04, .2, (.4, -.3, .1), stripe_b, (80, 0, 12))
        box(.14, .14, .14, (-.48, 0, .92), mat(120, 90, 20, rough=.5))
        return 1.4, 1.1
    for k in range(7):
        colour = stripe_a if k % 2 == 0 else stripe_b
        box(.17, .06, .14, (-.51 + k * .17, -.04, .84), colour)
    box(1.1, .04, .3, (0, -.05, .52), stripe_b)
    ink = mat(196, 40, 26, rough=.5, grime=.3)
    _ms_letters("ROAD", 0, -.075, .59, .024, ink)
    _ms_letters("CLOSED", 0, -.075, .45, .024, ink)
    box(.12, .12, .1, (-.48, 0, .96), mat(*TIRE))
    ball(.08, (-.48, 0, 1.06), mat(255, 160, 30, emit=4.0, grime=0), (1, 1, .8))
    return 1.4, 1.2


def sawhorse():
    return _ms_sawhorse(False)


def road_flare():
    """A road flare spitting red on the asphalt, its cap kicked off beside it."""
    paper = mat(176, 34, 28, rough=.6, grime=.3)
    cyl(.035, .36, (0, 0, .03), paper, (0, 90, 8), seg=10)
    ball(.06, (.2, 0, .06), mat(255, 70, 40, emit=6.0, grime=0), (1.4, 1, 1))
    ball(.035, (.25, 0, .09), mat(255, 210, 160, emit=8.0, grime=0))
    cyl(.04, .05, (-.24, .12, .02), paper, (90, 0, 0), seg=10)
    for k in range(3):
        ball(.05 + k * .02, (.22 + k * .03, 0, .16 + k * .1), mat(160, 150, 150, rough=.95, grime=0))
    return .7, .4


# ------------------------------------------------------------ the camp
def _ms_gable(x, width, low, high, m):
    """A triangle of canvas across the tent's end at x."""
    bm = bmesh.new()
    t = .015
    pts = [(-width / 2, low), (width / 2, low), (0, high)]
    front = [bm.verts.new((x - t, py, pz)) for py, pz in pts]
    back = [bm.verts.new((x + t, py, pz)) for py, pz in pts]
    bm.faces.new(front)
    bm.faces.new(list(reversed(back)))
    for k in range(3):
        j = (k + 1) % 3
        bm.faces.new((front[k], front[j], back[j], back[k]))
    return place(bm, m, (0, 0, 0), (0, 0, 0))

def revenue_tent():
    """An army-surplus wall tent the agents sleep in: canvas walls and a
    ridge roof on poles, guy ropes to stakes, U.S. stencilled on the end,
    the flap tied back on a cot and a lantern burning inside."""
    canvas = mat(*MS_CANVAS, rough=.95, grime=.55)
    roof = mat(98, 96, 64, rough=.95, grime=.6)
    pole = mat(*WOOD, grime=.5)
    rope = mat(196, 182, 140, grime=.4)
    L, W, wall, ridge = 1.9, 1.5, .78, 1.42
    # The walls: back and both sides whole, the front with its flap open.
    for s in (1, -1):
        box(L, .03, wall, (0, s * W / 2, wall / 2), canvas)
    box(.03, W, wall, (-L / 2, 0, wall / 2), canvas)
    # The end gables.
    for x in (-L / 2, L / 2):
        _ms_gable(x, W, wall, ridge, canvas)
    # The front: one flap tied back, the other half across.
    box(.03, W / 2, wall, (L / 2, W / 4, wall / 2), canvas)
    rolled = mat(96, 92, 60, rough=.95, grime=.6)
    cyl(.07, wall * .9, (L / 2 + .02, -W / 2 + .1, wall * .5), rolled, seg=10)
    beam((L / 2 + .06, -W / 2 + .1, wall * .62), (L / 2 + .06, -W / 2 + .1, wall * .62 + .01), .16, rope)
    # The roof, two pitches.
    slope = math.degrees(math.atan2(ridge - wall, W / 2))
    run = math.hypot(ridge - wall, W / 2) + .06
    for s in (1, -1):
        box(L + .12, run, .03, (0, s * W / 4, (ridge + wall) / 2), roof, (s * -slope, 0, 0))
    # The poles and the ridge pole showing at the ends.
    for x in (-L / 2 - .02, L / 2 + .02):
        cyl(.03, ridge + .12, (x, 0, (ridge + .12) / 2), pole, seg=8)
    cyl(.025, L + .3, (0, 0, ridge + .02), pole, (0, 90, 0), seg=8)
    # Guy ropes out to stakes.
    for x in (-L / 2 + .1, 0, L / 2 - .1):
        for s in (1, -1):
            beam((x, s * W / 2, wall), (x, s * (W / 2 + .45), 0), .012, rope)
            box(.04, .04, .14, (x, s * (W / 2 + .45), .05), pole)
    # U.S. on the back end; inside, the cot and the lantern.
    _ms_letters_x("U.S.", -L / 2 - .02, 0, wall + .18, .045, mat(30, 30, 26, rough=.8), facing=-1)
    box(.9, .4, .06, (.1, -.3, .3), mat(80, 92, 60, rough=.9))
    for x in (-.32, .52):
        box(.04, .42, .3, (x, -.3, .15), pole)
    cyl(.06, .14, (.6, .3, .07), mat(60, 50, 30, metal=.6), seg=8)
    ball(.05, (.6, .3, .17), mat(255, 190, 90, emit=6.0, grime=0))
    return 2.6, 1.7


def radio_mast():
    """The agents' radio mast on the knob: a three-sided lattice on a
    concrete pad, guy wires to their anchors, the whip and the dipoles up
    top, a red lamp on its tip, the coax down to a box at its foot."""
    steel = mat(170, 172, 168, metal=.6, rough=.45, grime=.55)
    box(.8, .8, .16, (0, 0, .08), mat(150, 146, 136, grime=.75))
    height, r = 6.6, .2
    legs = [(r * math.cos(math.radians(a)), r * math.sin(math.radians(a))) for a in (90, 210, 330)]
    for k in range(3):
        beam((*legs[k], .16), (*legs[k], height), .04, steel)
    steps = 13
    for i in range(steps):
        z0 = .16 + (height - .16) * i / steps
        z1 = .16 + (height - .16) * (i + 1) / steps
        for k in range(3):
            j = (k + 1) % 3
            beam((*legs[k], z0), (*legs[j], z1), .016, steel)
            beam((*legs[k], z1), (*legs[j], z1), .016, steel)
    # The whip, the dipoles, the lamp.
    beam((0, 0, height), (0, 0, height + 1.0), .02, steel)
    for z in (height - .4, height - 1.0):
        beam((-.6, 0, z), (.6, 0, z), .018, steel)
        for x in (-.6, .6):
            beam((x, 0, z - .25), (x, 0, z + .25), .016, steel)
    cyl(.06, .08, (0, 0, height + 1.04), mat(*TIRE), seg=10)
    ball(.08, (0, 0, height + 1.12), mat(*MS_RED, emit=6.0, grime=0))
    ball(.06, (0, 0, height * .55), mat(*MS_RED, emit=4.0, grime=0))
    # Guy wires from two heights out to their anchors.
    wire = mat(60, 60, 60, metal=.6)
    for a in (30, 150, 270):
        out = (math.cos(math.radians(a)) * 1.5, math.sin(math.radians(a)) * 1.5)
        for z in (height * .5, height * .9):
            beam((0, 0, z), (out[0], out[1], .05), .01, wire)
        box(.16, .16, .1, (out[0], out[1], .05), mat(150, 146, 136, grime=.7))
    # The box at its foot and the cable up.
    box(.34, .24, .4, (.36, -.36, .36), mat(92, 98, 72, metal=.3, grime=.6))
    beam((.36, -.3, .5), (0, -.1, 1.4), .02, mat(*TIRE))
    return 3.4, 7.9


def hung_lantern():
    """A kerosene lantern hung off a hook driven into a timber: its bail, the
    tin top and bottom, the chimney glass with the flame burning in it."""
    tin = mat(88, 70, 48, metal=.55, rough=.45, grime=.6)
    wire = mat(60, 56, 50, metal=.7)
    box(.04, .04, .12, (0, .1, .48), wire)
    beam((0, .1, .42), (0, 0, .38), .012, wire)
    for s in (1, -1):
        beam((0, 0, .38), (s * .09, 0, .26), .01, wire)
    cyl(.09, .06, (0, 0, .25), tin, seg=12, top=.04)
    cyl(.07, .14, (0, 0, .15), mat(255, 200, 120, emit=3.0, rough=.2, grime=.2), seg=12)
    ball(.035, (0, 0, .15), mat(255, 230, 160, emit=9.0, grime=0), (1, 1, 1.4))
    for a in (0, 120, 240):
        beam((.08 * math.cos(math.radians(a)), .08 * math.sin(math.radians(a)), .07),
             (.08 * math.cos(math.radians(a)), .08 * math.sin(math.radians(a)), .23), .01, wire)
    cyl(.1, .08, (0, 0, .04), tin, seg=12)
    return .5, .56


# ------------------------------------------------------------ Granny's still
def big_still():
    """Granny Hooten's still in the cave: the copper pot on its stone firebox
    with the fire going, the cap and the swan neck over to the thump keg,
    the worm coiled in its water barrel and the jar under the spout, the
    mash barrels ranged behind; and the Revenue Man's bundle of dynamite
    wired to the firebox with an alarm clock on it."""
    copper = mat(*MS_COPPER, metal=.85, rough=.3, grime=.5)
    stone = mat(118, 106, 92, grime=.75)
    soot = mat(30, 26, 24, grime=.3)
    wood = mat(*WOOD, planks=10.0, grime=.55)
    hoopm = mat(70, 62, 54, metal=.6, rough=.5, grime=.5)
    # The firebox: laid stone, its mouth glowing, ashes before it.
    box(1.3, 1.2, .7, (-.5, 0, .35), stone)
    for k in range(4):
        box(1.32, 1.22, .02, (-.5, 0, .12 + k * .17), mat(96, 86, 74, grime=.6))
    box(.5, .04, .34, (-.5, -.61, .26), soot)
    box(.42, .03, .24, (-.5, -.62, .24), mat(255, 110, 30, emit=5.0, grime=0))
    for k in range(5):
        ball(.06, (-.68 + k * .09, -.66, .14), mat(255, 150, 50, emit=4.0, grime=0), (1.4, 1, .5))
    box(.6, .3, .03, (-.5, -.8, .015), mat(60, 56, 52, grime=.4))
    # The pot: a big copper belly on the firebox, its cap and swan neck.
    ball(.66, (-.5, 0, 1.18), copper, (1, 1, .82))
    cyl(.68, .1, (-.5, 0, .78), copper, seg=28)
    for z in (.95, 1.25):
        cyl(.665, .03, (-.5, 0, z), hoopm, seg=28)
    cyl(.3, .4, (-.5, 0, 1.82), copper, seg=20, top=.12)
    ball(.14, (-.5, 0, 2.06), copper)
    beam((-.42, 0, 2.08), (.2, 0, 2.16), .07, copper)
    beam((.2, 0, 2.16), (.62, 0, 1.36), .06, copper)
    # The thump keg: a barrel in copper hoops, a copper lid and its line on.
    cyl(.32, .8, (.66, 0, .4), wood, seg=20)
    for z in (.12, .4, .68):
        cyl(.33, .04, (.66, 0, z), copper, seg=20)
    cyl(.3, .06, (.66, 0, .83), copper, seg=20)
    cyl(.06, .5, (.66, 0, 1.1), copper, seg=10)
    beam((.66, 0, 1.3), (1.18, .15, 1.36), .05, copper)
    # The worm barrel: water in it, the copper coil showing over the rim.
    cyl(.38, 1.0, (1.3, .2, .5), wood, seg=20)
    for z in (.15, .5, .85):
        cyl(.39, .04, (1.3, .2, z), hoopm, seg=20)
    cyl(.35, .02, (1.3, .2, .96), mat(40, 60, 70, rough=.1, metal=.2, grime=.2), seg=20)
    for k in range(3):
        ring = []
        for a in range(0, 360, 30):
            ring.append((1.3 + .24 * math.cos(math.radians(a)), .2 + .24 * math.sin(math.radians(a)),
                         1.02 + k * .07 + a / 360 * .07))
        for p, q in zip(ring, ring[1:]):
            beam(p, q, .04, copper)
    beam((1.3, -.18, .3), (1.3, -.36, .26), .03, copper)
    # The jar filling under the spout, and full ones by it.
    for k, (x, y) in enumerate(((1.3, -.44), (1.0, -.5), (1.6, -.4), (.9, -.32))):
        cyl(.08, .2, (x, y, .1), mat(212, 214, 196, rough=.12, metal=.1, grime=.2), seg=12)
        cyl(.06, .02, (x, y, .21), mat(196, 180, 120, metal=.6), seg=10)
    # The mash barrels behind it, a paddle across one.
    for x, y in ((-.9, .78), (-.2, .82)):
        cyl(.3, .78, (x, y, .39), wood, seg=18)
        cyl(.3, .02, (x, y, .78), mat(170, 150, 90, rough=.9, grime=.5), seg=18)
    box(.08, .9, .03, (-.55, .8, .8), wood, (0, 0, 35))
    # The Revenue Man's charge: six sticks taped to the firebox's corner, red
    # wire to a wind-up clock on top of it.
    red = mat(196, 40, 30, rough=.6, grime=.3)
    for k in range(6):
        cyl(.05, .44, (-1.0 + (k % 3) * .1, -.66 - (k // 3) * .08, .3), red, seg=10)
    box(.34, .2, .06, (-.9, -.7, .36), mat(200, 196, 180, rough=.5))
    box(.34, .2, .06, (-.9, -.7, .2), mat(200, 196, 180, rough=.5))
    beam((-.9, -.72, .52), (-.7, -.66, .8), .014, mat(220, 30, 24, rough=.5))
    cyl(.11, .07, (-.68, -.62, .82), mat(*CHROME, metal=.8, rough=.3), (90, 0, 0), seg=16)
    cyl(.09, .02, (-.68, -.665, .82), mat(240, 236, 220, rough=.4), (90, 0, 0), seg=16)
    beam((-.68, -.68, .82), (-.66, -.68, .88), .01, mat(20, 20, 20))
    for s in (1, -1):
        ball(.04, (-.68 + s * .08, -.62, .92), mat(*CHROME, metal=.8, rough=.3))
    return 3.4, 2.4


MORE.update({
    "cruiser": cruiser, "sawhorse": sawhorse, "road_flare": road_flare,
    "revenue_tent": revenue_tent, "radio_mast": radio_mast, "hung_lantern": hung_lantern,
    "big_still": big_still, "sawhorse_broken": lambda: _ms_sawhorse(True),
})
