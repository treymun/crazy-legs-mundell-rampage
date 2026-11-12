"""Gator Bayou's own props: the swamp past the county line, its fish camp and
its gator farm. Loaded by town_props.py after props_more.py (exec'd into the
same namespace, so mat, box, cyl, ball, wheel, place, beam, chain, rock and
the colours are in scope). Everything is modelled here from plain shapes."""


# ----------------------------------------------------------------- the swamp
BARK = (104, 86, 68)
MOSS = (148, 154, 124)
SWAMP_LEAF = (66, 88, 46)
ALUMINUM = (164, 168, 166)
CRAW = (196, 58, 34)


def taper(p0, p1, r0, r1, m, seg=10):
    # A round tapering limb from p0 (r0 thick) to p1 (r1 thick).
    a, b = Vector(p0), Vector(p1)
    d = b - a
    rot = [math.degrees(v) for v in d.normalized().to_track_quat("Z", "Y").to_euler()]
    return cyl(r0, d.length, (a + b) / 2, m, rot, seg=seg, top=r1)


def moss_hang(at, length, m, k=0):
    # Spanish moss: a few grey beards hanging off a limb.
    p = Vector(at)
    for j in range(3):
        off = Vector(((j - 1) * .06, ((j + k) % 2) * .05 - .02, 0))
        taper(p + off, p + off + Vector((.02 * (j - 1), 0, -length * (.7 + .15 * j))), .045, .006, m, seg=5)


def crown(at, size, dark, light):
    # A bald cypress's flat crown: feathery clumps, lit on top.
    c = Vector(at)
    for k in range(12):
        a = k * 2.4
        rad = size * (.15 + (k % 4) * .22)
        lift = (k % 3) * .1 - (.12 if k > 8 else 0)
        ball(size * (.38 + (k % 3) * .1), c + Vector((math.cos(a) * rad, math.sin(a) * rad * .8, lift)),
             dark if k % 3 else light, (1.2, 1.1, .62), (k * 7, k * 5, k * 30), seg=8)


def cypress():
    # A bald cypress standing in the water: the flared, fluted foot, the trunk
    # going up grey and straight, a flat ragged crown and the moss off every limb.
    bark = mat(*BARK, rough=.95, grime=.6, planks=2.5)
    bark_dk = mat(72, 60, 48, rough=.95, grime=.5)
    dark = mat(*SWAMP_LEAF, rough=.9, grime=.5)
    light = mat(92, 112, 60, rough=.9, grime=.45)
    moss = mat(*MOSS, rough=1.0, grime=.35)
    cyl(.6, .9, (0, 0, .45), bark_dk, seg=12, top=.24)
    for k in range(6):
        a = k * math.tau / 6 + .4
        taper((math.cos(a) * .62, math.sin(a) * .62, .02), (math.cos(a) * .12, math.sin(a) * .12, .9), .14, .05, bark_dk, seg=8)
    taper((0, 0, .8), (.06, .04, 3.7), .26, .12, bark, seg=12)
    limbs = [((.04, 0, 2.5), (-.9, .2, 3.3)), ((.05, .02, 2.9), (.85, -.1, 3.6)), ((.06, .03, 3.3), (-.4, -.3, 3.95)),
             ((.06, .03, 3.5), (.5, .35, 4.0))]
    for k, (a, b) in enumerate(limbs):
        taper(a, b, .09, .04, bark, seg=8)
        moss_hang(Vector(a).lerp(Vector(b), .6), .9 - k * .1, moss, k)
        moss_hang(b, .7, moss, k + 1)
    crown((-.75, .15, 3.45), .5, dark, light)
    crown((.7, -.05, 3.7), .55, dark, light)
    crown((0, 0, 4.15), .62, dark, light)
    ROOT.rotation_euler = Euler((0, math.radians(2), 0))
    return 3.0, 4.7


def cypress_b():
    # A leaner one, half dead on one side, bearded to the waterline.
    bark = mat(116, 100, 82, rough=.95, grime=.65, planks=2.5)
    bark_dk = mat(76, 64, 52, rough=.95, grime=.5)
    dark = mat(58, 80, 42, rough=.9, grime=.5)
    light = mat(86, 104, 56, rough=.9, grime=.45)
    moss = mat(156, 160, 132, rough=1.0, grime=.3)
    cyl(.44, .7, (0, 0, .35), bark_dk, seg=10, top=.18)
    for k in range(5):
        a = k * math.tau / 5
        taper((math.cos(a) * .46, math.sin(a) * .46, .02), (math.cos(a) * .1, math.sin(a) * .1, .7), .11, .04, bark_dk, seg=8)
    taper((0, 0, .6), (.3, 0, 3.0), .2, .09, bark, seg=10)
    for k, (a, b) in enumerate([((.16, 0, 1.8), (-.6, .1, 2.4)), ((.22, 0, 2.3), (.9, .1, 2.7)), ((.28, 0, 2.8), (-.2, 0, 3.3))]):
        taper(a, b, .07, .03, bark, seg=7)
        for t in (.4, .8, 1.0):
            moss_hang(Vector(a).lerp(Vector(b), t), 1.1 - k * .15, moss, k)
    crown((.4, 0, 3.15), .45, dark, light)
    crown((.9, .1, 2.8), .32, dark, light)
    return 2.4, 3.7


def cypress_knees():
    # Cypress knees: the knobby stumps that stand up out of the water round a tree.
    wood = mat(118, 96, 74, rough=.95, grime=.55)
    for k, (x, y, h) in enumerate([(-.4, 0, .5), (-.1, .2, .7), (.15, -.1, .42), (.4, .15, .58), (.05, .35, .34), (-.3, -.25, .3)]):
        cyl(.1 + h * .1, h, (x, y, h / 2), wood, (k * 3 - 6, k * 2 - 4, 0), seg=8, top=.03)
        ball(.05, (x, y, h), wood)
    return 1.3, .8


def dead_snag():
    # A dead cypress, the top snapped off, two bare limbs and a buzzard on one.
    wood = mat(150, 140, 124, rough=.95, grime=.6, planks=3.0)
    moss = mat(*MOSS, rough=1.0, grime=.35)
    cyl(.42, .6, (0, 0, .3), mat(96, 82, 66, rough=.95, grime=.5), seg=10, top=.2)
    taper((0, 0, .5), (-.1, .05, 2.9), .2, .14, wood, seg=9)
    for k in range(4):
        a = k * 1.6
        box(.08, .06, .25, (-.1 + math.cos(a) * .1, .05 + math.sin(a) * .1, 2.95), wood, (k * 20, k * 15, 0))
    taper((-.05, .03, 1.9), (-.9, .1, 2.5), .07, .02, wood, seg=6)
    taper((-.08, .04, 2.4), (.7, 0, 2.9), .06, .02, wood, seg=6)
    moss_hang((-.6, .08, 2.3), .7, moss)
    crow = mat(26, 22, 22, grime=.1)
    ball(.12, (.55, 0, 3.0), crow, (1, 1.3, 1.1))
    ball(.06, (.6, -.1, 3.12), mat(170, 60, 50, grime=.2))
    for s in (1, -1):
        box(.22, .03, .12, (.55 + s * .12, .04, 2.98), crow, (0, s * 30, 0))
    return 2.2, 3.4


def airboat():
    # A swamp airboat at rest: the flat aluminium hull, the high seat on its
    # frame, the caged prop and its engine at the back, the twin rudders.
    alu = mat(*ALUMINUM, metal=.7, rough=.4, grime=.65)
    paint = mat(48, 92, 64, metal=.3, rough=.5, grime=.7)
    dark = mat(40, 40, 42, metal=.5, grime=.5)
    box(2.4, 1.2, .2, (0, 0, .12), alu)
    box(.5, 1.2, .16, (1.3, 0, .2), alu, (0, -22, 0))
    for s in (1, -1):
        box(2.6, .05, .26, (.1, s * .6, .24), paint)
    box(.5, .5, .06, (.5, 0, .3), mat(*GREY_WOOD, planks=6.0))
    for x in (-.15, .15):
        for y in (-.2, .2):
            box(.04, .04, .8, (x, y, .6), alu)
    box(.5, .5, .08, (0, 0, 1.0), alu)
    box(.42, .4, .3, (0, .05, 1.18), mat(120, 40, 34, rough=.7, grime=.5))
    box(.5, .7, .45, (-.8, 0, .55), dark)
    cyl(.07, .3, (-.55, 0, .62), dark, (0, 90, 0), seg=10)
    for k in range(18):
        a0, a1 = k * math.tau / 18, (k + 1) * math.tau / 18
        beam((-1.1, math.cos(a0) * .85, 1.1 + math.sin(a0) * .85), (-1.1, math.cos(a1) * .85, 1.1 + math.sin(a1) * .85), .05, alu)
    for k in range(6):
        a = k * math.tau / 6
        beam((-1.18, 0, 1.1), (-1.18, math.cos(a) * .85, 1.1 + math.sin(a) * .85), .025, alu)
    for k in range(9):
        beam((-1.24, -.85 + k * .21, .3), (-1.24, -.85 + k * .21, 1.9), .015, alu)
    box(.06, 1.5, .12, (-.98, 0, 1.1), mat(150, 120, 80, planks=3.0), (30, 0, 0))
    cyl(.1, .12, (-.98, 0, 1.1), dark, (0, 90, 0), seg=12)
    for s in (1, -1):
        box(.4, .03, .5, (-1.35, s * .3, .5), paint)
    box(.3, .02, .12, (.9, -.62, .26), mat(230, 220, 190))
    ROOT.rotation_euler = Euler((0, 0, math.radians(20)))
    return 3.4, 2.2


def pirogue():
    # A dugout pirogue pulled half up the bank, its paddle laid across.
    wood = mat(92, 66, 44, planks=10.0, grime=.55)
    for k in range(7):
        x = -1.1 + k * .37
        wide = .3 * math.sin((k + .5) / 7 * math.pi) + .06
        box(.38, wide * 2, .22, (x, 0, .13), wood)
    box(2.5, .3, .04, (0, 0, .05), mat(60, 44, 30, grime=.4))
    beam((-.9, .1, .3), (.9, -.15, .32), .04, mat(*WOOD))
    box(.24, .1, .03, (1.0, -.18, .32), mat(*WOOD), (0, 0, -10))
    ROOT.rotation_euler = Euler((0, math.radians(-3), math.radians(-10)))
    return 2.7, .55


def boil_pot():
    # The crawfish boil: a three-legged propane burner, the big pot rolling, a
    # basket in it, the paddle, a sack of mudbugs leant on a leg.
    iron = mat(40, 38, 36, metal=.5, rough=.6, grime=.6)
    pot = mat(178, 180, 176, metal=.75, rough=.35, grime=.55)
    for k in range(3):
        a = k * math.tau / 3
        beam((math.cos(a) * .42, math.sin(a) * .42, 0), (math.cos(a) * .3, math.sin(a) * .3, .5), .04, iron)
    cyl(.32, .05, (0, 0, .52), iron, seg=14)
    cyl(.2, .02, (0, 0, .5), mat(255, 120, 40, emit=4.0, grime=0), seg=14)
    cyl(.4, .62, (0, 0, .86), pot, seg=22)
    cyl(.41, .04, (0, 0, 1.17), pot, seg=22)
    cyl(.36, .02, (0, 0, 1.15), mat(170, 120, 70, rough=.4, grime=.2), seg=20)
    for k in range(5):
        ball(.12 + (k % 2) * .05, (math.cos(k * 1.3) * .18, math.sin(k * 1.3) * .18, 1.28 + k * .07),
             mat(236, 234, 228, rough=1.0, grime=0))
    beam((-.3, .1, 1.2), (.1, -.05, 1.75), .035, mat(*WOOD))
    box(.4, .3, .5, (.6, -.2, .25), mat(150, 120, 80, rough=.95, grime=.5), (0, -10, 20))
    for k in range(3):
        ball(.05, (.62 + k * .05, -.38, .5), mat(*CRAW, rough=.5, grime=.2), (1.6, 1, 1))
    cyl(.18, .6, (-.7, .1, .3), mat(214, 212, 204, metal=.2, rough=.5, grime=.5), seg=14)
    beam((-.7, .1, .6), (-.32, .05, .5), .02, mat(30, 30, 30))
    return 1.8, 1.9


def crawfish_traps():
    # Pillow traps of green wire stacked on the dock, a sack of bait on top.
    wire = mat(70, 110, 76, metal=.4, rough=.5, grime=.55)
    for k, (x, y, z) in enumerate([(-.35, 0, .17), (.35, .05, .17), (0, 0, .5), (-.3, .02, .82)]):
        ball(.3, (x, y, z), wire, (1.15, .9, .55), (0, 0, k * 17), seg=8)
        cyl(.07, .1, (x, y - .02, z + .16), mat(40, 60, 44, metal=.4), seg=8)
    box(.34, .26, .2, (.2, 0, .86), mat(150, 120, 80, rough=.95, grime=.5), (0, 0, 20))
    for k in range(2):
        cyl(.08, .02, (.5 - k * .2, -.32, .02), mat(220, 80, 40, rough=.4), seg=10)
    return 1.3, 1.1


def bait_tank():
    # The live-bait tank: a long white tank on legs, the aerator rattling,
    # shiners in the green water, a dip net hung on the rim.
    shell = mat(214, 210, 196, rough=.5, grime=.7)
    box(1.5, .6, .5, (0, 0, .7), shell)
    box(1.4, .5, .02, (0, 0, .94), mat(70, 120, 96, rough=.1, grime=.2))
    for k in range(6):
        box(.07, .02, .02, (-.5 + k * .19, -.1 + (k % 3) * .1, .955), mat(210, 214, 220, metal=.6, rough=.2), (0, 0, k * 40))
    for x in (-.65, .65):
        for y in (-.24, .24):
            box(.05, .05, .45, (x, y, .22), mat(150, 150, 146, metal=.6))
    box(.24, .2, .2, (.82, 0, 1.0), mat(60, 70, 80, metal=.4, grime=.5))
    beam((.8, 0, 1.0), (.5, .1, .95), .02, mat(30, 30, 30))
    beam((-.75, -.3, .96), (-.9, -.32, 1.6), .025, mat(*WOOD))
    ball(.14, (-.9, -.34, 1.68), mat(40, 60, 50, metal=.3, rough=.6, grime=.2), (1, .3, 1.2))
    box(.5, .02, .2, (0, -.31, .7), mat(40, 110, 60, grime=.3))
    return 1.9, 1.8


def ice_chest():
    # A marine cooler, white with a red lid, cans of beer sweating on top.
    box(.8, .45, .42, (0, 0, .21), mat(226, 224, 216, rough=.4, grime=.55))
    box(.82, .47, .07, (0, 0, .45), mat(176, 38, 32, rough=.4, grime=.5))
    for s in (1, -1):
        box(.06, .1, .05, (s * .44, 0, .36), mat(40, 40, 40))
    for k in range(3):
        cyl(.04, .12, (-.2 + k * .14, -.05 + (k % 2) * .08, .55), mat(*([200, 200, 210] if k % 2 else [190, 40, 34]), metal=.7, rough=.3), seg=10)
    return .95, .66


def net_rack():
    # Two poles and a pole across, cast nets hung to dry, a string of floats.
    wood = mat(*GREY_WOOD, planks=4.0, grime=.6)
    net = mat(96, 104, 92, rough=1.0, grime=.4)
    for x in (-.95, .95):
        cyl(.05, 2.0, (x, 0, 1.0), wood, seg=8)
    beam((-1.0, 0, 1.85), (1.0, 0, 1.85), .06, wood)
    for k, x in enumerate((-.55, 0, .55)):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=False, segments=14, radius1=.32, radius2=.03, depth=1.1)
        place(bm, net, (x, 0, 1.3), (0, 0, k * 20))
        for j in range(5):
            a = j * math.tau / 5
            ball(.025, (x + math.cos(a) * .3, math.sin(a) * .3, .76), mat(80, 80, 84, metal=.6))
    for k in range(6):
        ball(.05, (-.85 + k * .34, -.05, 1.7 - abs(k - 2.5) * .03), mat(*((230, 200, 60) if k % 2 else (220, 80, 40)), rough=.4))
    return 2.2, 2.1


def gator_hide():
    # A gator hide tacked out on a plank frame to cure, belly up.
    wood = mat(*GREY_WOOD, planks=4.0, grime=.6)
    for x in (-.9, .9):
        box(.08, .08, 1.8, (x, 0, .9), wood)
    for z in (.3, 1.65):
        box(1.9, .07, .07, (0, 0, z), wood)
    hide = mat(190, 176, 128, rough=.8, grime=.5, planks=22.0)
    back = mat(58, 72, 46, rough=.8, grime=.55, planks=12.0)
    ball(.62, (0, -.02, .98), back, (1.0, .04, .5))
    ball(.5, (0, -.04, .98), hide, (1.0, .04, .44))
    ball(.26, (.72, -.03, .98), back, (1.3, .04, .62))
    box(.62, .03, .12, (-.86, -.02, .98), back, (0, 4, 0))
    for s in (1, -1):
        for x in (-.32, .36):
            box(.08, .03, .34, (x, -.04, .98 + s * .42), back, (0, s * 28, 0))
    for k in range(9):
        box(.05, .02, .05, (-.5 + k * .12, -.07, .98 + ((k % 2) * 2 - 1) * .04), mat(40, 48, 32), (0, 45, 0))
    for k in range(6):
        cyl(.012, .1, (-.6 + k * .24, -.08, .98 + ((k % 2) * 2 - 1) * .3), mat(180, 180, 176, metal=.8), (90, 0, 0), seg=4)
    return 2.0, 1.85


def marina_pump():
    # The marina pump (not the speedway's fuel_pump): a round-shouldered red pump, its glass globe, the hose.
    red = mat(176, 40, 32, metal=.3, rough=.5, grime=.7)
    box(.5, .4, 1.3, (0, 0, .65), red)
    cyl(.25, .4, (0, 0, 1.3), red, (90, 0, 0), seg=18)
    box(.36, .02, .26, (0, -.205, 1.05), mat(220, 216, 196, rough=.3, grime=.4))
    for k in range(3):
        box(.06, .01, .08, (-.1 + k * .1, -.215, 1.05), mat(30, 30, 30))
    ball(.18, (0, 0, 1.68), mat(250, 236, 200, rough=.2, emit=.8, grime=.2), (1, 1, .9))
    box(.3, .02, .1, (0, -.17, 1.68), mat(176, 40, 32))
    box(.56, .46, .08, (0, 0, .04), mat(80, 80, 80, metal=.5))
    beam((.25, -.1, .9), (.45, -.4, .3), .03, mat(30, 30, 30))
    beam((.45, -.4, .3), (.3, -.5, .05), .03, mat(30, 30, 30))
    box(.06, .14, .18, (.28, -.06, .95), mat(160, 160, 160, metal=.8))
    return .9, 1.95


def propane_tank():
    # A propane pig on its legs, the dial on top, a chain round it.
    tank = mat(222, 220, 212, metal=.3, rough=.4, grime=.6)
    cyl(.4, 1.5, (0, 0, .62), tank, (0, 90, 0), seg=20)
    for s in (1, -1):
        ball(.4, (s * .75, 0, .62), tank, (.4, 1, 1))
        for y in (-.2, .2):
            box(.05, .05, .3, (s * .5, y, .15), mat(70, 70, 70, metal=.5))
    cyl(.1, .14, (0, 0, 1.06), mat(160, 160, 158, metal=.7), seg=10)
    cyl(.05, .02, (0, -.06, 1.12), mat(220, 60, 40), (90, 0, 0), seg=10)
    box(.6, .02, .14, (0, -.41, .65), mat(30, 60, 140, grime=.3))
    return 2.0, 1.25


def heron():
    # A great blue heron, stood in the shallows on one leg, neck in an S.
    blue = mat(116, 130, 150, rough=.8, grime=.3)
    pale = mat(206, 206, 196, rough=.8, grime=.2)
    ball(.18, (0, 0, .78), blue, (1.6, .7, .9))
    ball(.1, (-.3, 0, .74), mat(90, 100, 120), (1.6, .5, .5))
    taper((.15, 0, .85), (.25, 0, 1.0), .06, .045, pale, seg=8)
    taper((.25, 0, 1.0), (.14, 0, 1.15), .045, .04, pale, seg=8)
    taper((.14, 0, 1.15), (.22, 0, 1.28), .04, .035, pale, seg=8)
    ball(.06, (.24, 0, 1.3), pale, (1.2, .8, .9))
    taper((.28, 0, 1.3), (.5, 0, 1.27), .02, .004, mat(200, 170, 60, rough=.4), seg=6)
    box(.18, .02, .02, (.2, 0, 1.34), mat(30, 30, 40), (0, -10, 0))
    taper((0, 0, .66), (.02, 0, .02), .015, .012, mat(150, 130, 70), seg=6)
    taper((-.03, 0, .66), (-.08, 0, .44), .015, .012, mat(150, 130, 70), seg=6)
    taper((-.08, 0, .44), (-.01, 0, .4), .012, .01, mat(150, 130, 70), seg=6)
    return .9, 1.4


def boil_table():
    # A long table under newspaper, a boil dumped down the middle: crawfish,
    # corn, potatoes and lemons, a roll of paper towels.
    wood = mat(*GREY_WOOD, planks=10.0, grime=.6)
    box(2.0, .7, .05, (0, 0, .74), wood)
    for x in (-.85, .85):
        for y in (-.28, .28):
            box(.06, .06, .72, (x, y, .36), wood)
    box(1.9, .62, .01, (0, 0, .77), mat(212, 206, 186, rough=1.0, grime=.5))
    for k in range(22):
        a = k * 2.39
        r = (k % 5) * .06
        ball(.05, (math.cos(a) * r * 2.4, math.sin(a) * r * .6, .8 + (k % 3) * .03), mat(*CRAW, rough=.5, grime=.25), (1.6, .8, .8), (0, 0, k * 40))
    for k in range(3):
        cyl(.05, .2, (-.4 + k * .4, .15, .82), mat(230, 200, 80, rough=.6, grime=.2), (0, 90, k * 30), seg=8)
        ball(.06, (-.2 + k * .4, -.15, .82), mat(180, 150, 100, rough=.8, grime=.3))
    for k in range(2):
        ball(.045, (.7 - k * .12, .2, .81), mat(240, 230, 80, rough=.4, grime=.2), (1.2, 1, 1))
    cyl(.07, .26, (-.8, .2, .9), mat(240, 240, 236, grime=.3), (90, 0, 0), seg=12)
    return 2.2, 1.0


def outboard_stand():
    # An outboard motor clamped to a sawhorse for the winter it never got.
    wood = mat(*WOOD, planks=4.0, grime=.6)
    box(1.0, .08, .08, (0, 0, .75), wood)
    for s in (1, -1):
        for y in (-.2, .2):
            beam((s * .4, 0, .75), (s * .45, y, 0), .05, wood)
    cowl = mat(30, 70, 140, metal=.3, rough=.45, grime=.6)
    ball(.2, (0, -.15, 1.0), cowl, (1.0, 1.4, .9))
    box(.12, .1, .7, (0, -.08, .5), mat(60, 60, 64, metal=.6))
    box(.3, .1, .04, (0, -.08, .17), mat(60, 60, 64, metal=.6))
    cyl(.1, .03, (0, -.08, .1), mat(160, 160, 150, metal=.8), (0, 90, 0), seg=3)
    beam((0, -.25, 1.0), (0, -.6, .95), .03, mat(30, 30, 30))
    return 1.3, 1.3


def giant_gator():
    # The gator farm's fiberglass gator: a roadside giant, mouth wide open,
    # painted teeth, a fading green and a ladder somebody left against it.
    green = mat(70, 120, 60, rough=.4, grime=.55)
    belly = mat(206, 196, 120, rough=.4, grime=.5)
    ball(.6, (0, 0, .7), green, (2.2, .9, .6))
    ball(.45, (1.4, 0, .74), green, (1.3, .8, .5))
    box(.9, .55, .14, (2.2, 0, .82), green, (0, -12, 0))
    box(.9, .5, .1, (2.15, 0, .58), belly, (0, 10, 0))
    for k in range(7):
        x = 1.85 + k * .12
        for z, flip in ((.74, 0), (.66, 180)):
            cyl(.03, .08, (x, -.24, z), mat(246, 240, 220), (flip, 0, 0), seg=4, top=.002)
    for s in (1, -1):
        ball(.1, (1.6, s * .22, 1.02), mat(220, 200, 60, emit=.3), (1, 1, 1))
        ball(.04, (1.66, s * .24, 1.04), mat(10, 10, 10))
    for k in range(6):
        x = -1.9 - k * .32
        ball(.3 - k * .04, (x, 0, .6 - k * .06), green, (1.4, .7, .5))
    for k in range(9):
        cyl(.06, .14, (-.9 + k * .3, 0, 1.05 - abs(k - 4) * .02), mat(50, 92, 46, rough=.4, grime=.5), seg=4, top=.01)
    for x in (-.7, .9):
        for s in (1, -1):
            beam((x, s * .4, .5), (x + .15, s * .7, 0), .12, green)
    box(1.2, .9, .3, (0, 0, .15), mat(150, 150, 146, grime=.6))
    ROOT.rotation_euler = Euler((0, 0, math.radians(-15)))
    return 4.8, 1.6


def bait_cooler_rack():
    # The bait shop's rack outside: a cricket box, minnow buckets, cane poles.
    wood = mat(*GREY_WOOD, planks=6.0, grime=.6)
    box(1.1, .4, .06, (0, 0, .5), wood)
    for x in (-.5, .5):
        box(.05, .4, .5, (x, 0, .25), wood)
    box(.4, .3, .3, (-.25, 0, .68), mat(150, 120, 80, planks=6.0, grime=.5))
    box(.3, .02, .14, (-.25, -.16, .7), mat(220, 210, 160))
    for k in range(2):
        cyl(.12, .22, (.15 + k * .26, 0, .64), mat(220, 200, 60 + k * 100, metal=.3, rough=.4, grime=.4), seg=12)
    for k in range(4):
        beam((.55 + k * .04, .15, 0), (.3 + k * .1, .2, 2.0), .02, mat(176, 150, 90))
    return 1.4, 2.1


MORE.update({
    "cypress": cypress, "cypress_b": cypress_b, "cypress_knees": cypress_knees, "dead_snag": dead_snag,
    "airboat": airboat, "pirogue": pirogue, "boil_pot": boil_pot, "crawfish_traps": crawfish_traps,
    "bait_tank": bait_tank, "ice_chest": ice_chest, "net_rack": net_rack, "gator_hide": gator_hide,
    "marina_pump": marina_pump, "propane_tank": propane_tank, "heron": heron, "boil_table": boil_table,
    "outboard_stand": outboard_stand, "giant_gator": giant_gator, "bait_cooler_rack": bait_cooler_rack,
})
