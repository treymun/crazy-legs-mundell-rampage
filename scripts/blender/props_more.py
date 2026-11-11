"""More of the town's props: Hickston's junk and the fair's, the mill's and
the quarry's own things. Loaded by town_props.py (exec'd into its namespace,
so mat, box, cyl, ball, wheel, place and the colours are in scope)."""


# ------------------------------------------------------- more of Hickston
def truck_blocks():
    paint = mat(96, 120, 140, metal=.3, rough=.55, grime=.8)
    box(2.0, .9, .45, (0, 0, .62), paint)
    box(.8, .86, .5, (.3, 0, 1.08), paint)
    box(.7, .9, .3, (-.6, 0, .98), mat(70, 66, 60, metal=.4, grime=.7))
    box(.02, .7, .3, (.71, 0, 1.12), mat(40, 50, 60, rough=.15, metal=.2))
    for x in (-.65, .65):
        for y in (-.36, .36):
            box(.3, .25, .32, (x, y, .16), mat(120, 118, 112, grime=.6))
    wheel(.3, .2, (.65, .5, .5), mat(60, 60, 60, metal=.5), (90, 0, 0))
    ROOT.rotation_euler = Euler((0, math.radians(-3), math.radians(20)))
    return 2.4, 1.4


def porch_couch():
    cloth = mat(120, 74, 44, check=(84, 50, 30), grime=.6)
    box(1.5, .7, .3, (0, 0, .35), cloth)
    box(1.5, .2, .5, (0, .3, .7), cloth)
    for s in (1, -1):
        box(.2, .7, .3, (s * .72, 0, .6), cloth)
    for k in range(3):
        cyl(.04, .12, (-.4 + k * .12, -.4, .06), mat(200, 30, 26, metal=.6, rough=.3), seg=8)
    return 1.7, 1.0


def wheelbarrow():
    rust = mat(110, 120, 80, metal=.3, grime=.75)
    box(.7, .5, .3, (0, 0, .5), rust, (0, -8, 0))
    wheel(.16, .08, (.45, 0, .16), mat(40, 40, 40))
    for s in (1, -1):
        box(.9, .04, .04, (-.15, s * .22, .42), mat(*WOOD), (0, 14, 0))
        box(.04, .04, .4, (-.3, s * .2, .2), mat(*WOOD))
    box(.5, .4, .1, (0, 0, .62), mat(110, 80, 50, grime=.4))
    return 1.1, .8


def chicken_coop():
    wood = mat(*GREY_WOOD, planks=10.0, grime=.6)
    box(1.2, .9, .8, (0, 0, .7), wood)
    box(1.4, 1.1, .06, (0, 0, 1.15), mat(110, 60, 40, metal=.4, grime=.7), (0, 12, 0))
    for x in (-.55, .55):
        for y in (-.4, .4):
            box(.06, .06, .3, (x, y, .15), wood)
    box(.3, .02, .3, (0, -.46, .6), mat(14, 12, 10, grime=0))
    box(.12, .8, .04, (0, -.8, .2), wood, (32, 0, 0))
    ball(.08, (.3, -.7, .1), mat(230, 226, 214), (1.3, 1, 1))
    return 1.6, 1.3


def gas_cans():
    red = mat(190, 40, 30, metal=.4, rough=.4, grime=.5)
    for k, (x, y) in enumerate([(-.18, 0), (.18, .05), (0, .26)]):
        box(.3, .16, .36, (x, y, .18), red, (0, 0, k * 17))
        cyl(.025, .1, (x + .08, y, .4), mat(220, 190, 60, metal=.6), (0, 30, 0), seg=6)
    return .8, .55


def tire_stack():
    for k in range(4):
        cyl(.36, .2, ((k % 2) * .04, 0, .1 + k * .2), mat(*TIRE, grime=.3), seg=20)
        cyl(.2, .21, ((k % 2) * .04, 0, .1 + k * .2), mat(10, 10, 10, grime=0), seg=16)
    return .9, .95


def bathtub():
    enamel = mat(222, 220, 208, rough=.3, grime=.6)
    box(1.3, .62, .4, (0, 0, .42), enamel)
    box(1.2, .52, .05, (0, 0, .6), mat(70, 120, 90, rough=.1))
    for x in (-.5, .5):
        for y in (-.24, .24):
            ball(.06, (x, y, .12), mat(*CHROME, metal=.8))
    for k in range(3):
        ball(.12, (-.3 + k * .3, -.36, .1), mat(120, 150, 70, grime=.3))
    return 1.5, .8


def mailbox_row():
    colours = [(170, 60, 50), (60, 90, 140), (200, 190, 170), (60, 110, 60)]
    for k in range(4):
        cyl(.03, .9, (-.45 + k * .3, 0, .45), mat(*GREY_WOOD), seg=6)
        box(.2, .34, .16, (-.45 + k * .3, 0, .95), mat(*colours[k], metal=.5, grime=.7))
        box(.02, .03, .12, (-.35 + k * .3, .1, 1.07), mat(200, 40, 30))
    return 1.4, 1.15


# ------------------------------------------------------------ the fair
BULB = (255, 226, 150)
CAR_COLOURS = [(200, 50, 60), (60, 140, 180), (220, 180, 60), (60, 100, 60)]


def ferris_wheel():
    steel = mat(200, 196, 186, metal=.6, rough=.4, grime=.5)
    for s in (1, -1):
        box(.12, .12, 4.0, (s * 1.1, 0, 1.9), steel, (0, s * 16, 0))
    cyl(.18, .4, (0, 0, 3.7), steel, (90, 0, 0), seg=12)
    for ring in (2.0, 1.9):
        for k in range(24):
            a = k / 24 * math.tau
            box(.06, .06, ring * math.tau / 24 * 1.05, (math.cos(a) * ring, 0, 3.7 + math.sin(a) * ring),
                steel, (0, -math.degrees(a), 0))
    for k in range(8):
        a = k / 8 * math.tau
        box(.05, .05, 2.0, (math.cos(a) * 1.0, 0, 3.7 + math.sin(a) * 1.0), steel, (0, 90 - math.degrees(a), 0))
        x, z = math.cos(a) * 2.05, 3.7 + math.sin(a) * 2.05
        box(.5, .4, .34, (x, 0, z - .35), mat(*CAR_COLOURS[k % 4], metal=.3, rough=.4, grime=.4))
        ball(.06, (x, -.08, z), mat(*BULB, emit=6.0, grime=0))
    return 4.8, 6.0


def carousel_horse():
    pole = mat(220, 190, 80, metal=.8, rough=.25, grime=.3)
    cyl(.04, 2.2, (0, 0, 1.1), pole, seg=10)
    body = mat(236, 230, 214, rough=.3, grime=.35)
    ball(.3, (0, 0, 1.1), body, (1.6, .7, .8))
    ball(.15, (.5, 0, 1.45), body, (1.3, .6, .9))
    box(.12, .12, .3, (.38, 0, 1.3), body, (0, -40, 0))
    for x in (-.3, .3):
        for y in (-.1, .1):
            box(.07, .07, .45, (x, y, .78), body, (0, 25 if x > 0 else -25, 0))
    box(.3, .32, .05, (-.05, 0, 1.36), mat(180, 30, 40, rough=.4))
    box(.2, .05, .3, (.42, -.13, 1.5), mat(200, 60, 160, rough=.3))
    return 1.4, 2.25


def cotton_candy():
    cart = mat(230, 120, 170, rough=.4, grime=.4)
    box(1.0, .6, .8, (0, 0, .6), cart)
    for x in (.35, -.35):
        wheel(.2, .06, (x, .32, .2), mat(220, 220, 220, metal=.5), (90, 0, 0))
    cyl(.26, .2, (0, 0, 1.1), mat(*CHROME, metal=.8), seg=20)
    fluff = [(255, 160, 220), (140, 200, 255), (255, 140, 220), (160, 220, 255)]
    for k in range(4):
        cyl(.012, .4, (-.3 + k * .2, -.2, 1.25), mat(220, 220, 210), seg=4)
        ball(.12, (-.3 + k * .2, -.2, 1.5), mat(*fluff[k], rough=.9, grime=.05))
    box(1.1, .7, .05, (0, 0, 1.85), mat(255, 230, 240, grime=.3))
    for x in (-.5, .5):
        cyl(.02, .8, (x, .3, 1.45), mat(*CHROME, metal=.8), seg=6)
    return 1.3, 1.95


def high_striker():
    wood = mat(200, 60, 40, planks=4.0, grime=.5)
    box(.24, .14, 3.0, (0, 0, 1.5), wood)
    for k in range(6):
        box(.26, .02, .06, (0, -.08, .5 + k * .45), mat(250, 240, 220))
    ball(.16, (0, -.05, 3.08), mat(220, 190, 80, metal=.9, rough=.2))
    box(.6, .5, .12, (0, -.25, .06), mat(80, 70, 60))
    box(.14, .1, .1, (0, -.28, .16), mat(200, 30, 30, rough=.4))
    box(.7, .1, .08, (.1, -.6, .3), mat(*WOOD), (0, 20, 30))
    return 1.0, 3.3


def prize_bear():
    fur = mat(140, 90, 200, rough=.95, grime=.15)
    ball(.4, (0, 0, .45), fur, (1, .9, 1.1))
    ball(.3, (0, 0, 1.05), fur)
    for s in (1, -1):
        ball(.1, (s * .22, 0, 1.3), fur)
        ball(.13, (s * .42, -.05, .62), fur, (1, 1, 1.5))
        ball(.15, (s * .2, -.18, .12), fur, (1, 1.3, .8))
        ball(.04, (s * .1, -.27, 1.1), mat(10, 10, 10, rough=.2, grime=0))
    ball(.08, (0, -.28, 1.0), mat(240, 200, 220))
    box(.4, .05, .08, (0, -.3, .8), mat(250, 220, 60))
    return 1.1, 1.4


def port_a_john():
    shell = mat(60, 110, 190, rough=.5, grime=.6)
    box(1.0, 1.0, 2.1, (0, 0, 1.05), shell)
    cyl(.55, .15, (0, 0, 2.15), mat(230, 230, 228, grime=.5), seg=20)
    box(.7, .02, 1.7, (0, -.51, .95), mat(50, 96, 170, rough=.5, grime=.5))
    box(.2, .02, .08, (.2, -.52, 1.2), mat(200, 40, 30))
    return 1.4, 2.35


def giant_hog():
    pink = mat(236, 150, 150, rough=.35, grime=.4)
    ball(.9, (0, 0, 1.4), pink, (1.5, .9, .9))
    ball(.55, (1.25, 0, 1.6), pink)
    cyl(.22, .2, (1.75, 0, 1.55), pink, (0, 90, 0), seg=16)
    for s in (1, -1):
        cyl(.16, .3, (1.2, s * .3, 2.15), pink, (s * 20, 0, 0), seg=8, top=.02)
        for x in (-.7, .7):
            cyl(.15, .7, (x, s * .45, .45), pink, seg=12)
        ball(.06, (1.65, s * .2, 1.75), mat(10, 10, 10, rough=.2, grime=0))
    box(2.2, 1.2, .3, (0, 0, .1), mat(120, 120, 116, grime=.6))
    box(.8, .05, .3, (0, -.62, .1), mat(40, 90, 200))
    return 3.2, 2.5


def balloons():
    colours = [(230, 50, 50), (60, 140, 220), (250, 220, 60), (80, 200, 100), (240, 120, 220)]
    for k in range(9):
        a = k * 2.4
        x, z = math.cos(a) * .3 * (k % 3), 1.5 + math.sin(a) * .25 + (k % 3) * .15
        ball(.17, (x, -.1, z), mat(*colours[k % 5], rough=.2, grime=.05))
        cyl(.004, 1.2, (x * .5, -.05, .7 + (z - 1.5) * .5), mat(240, 240, 240), seg=3)
    cyl(.04, .5, (0, 0, .25), mat(*WOOD), seg=6)
    return 1.3, 2.0


def searchlight():
    iron = mat(70, 74, 70, metal=.6, grime=.6)
    box(.7, .7, .3, (0, 0, .15), iron)
    for s in (1, -1):
        box(.06, .06, .6, (s * .3, 0, .5), iron)
    cyl(.3, .6, (0, 0, .85), iron, (-60, 0, 0), seg=18)
    cyl(.27, .02, (0, -.27, 1.0), mat(255, 250, 220, emit=8.0, grime=0), (-60, 0, 0), seg=18)
    return 1.0, 1.3


def generator():
    yellow = mat(220, 170, 40, metal=.3, rough=.5, grime=.65)
    box(1.4, .8, .8, (0, 0, .5), yellow)
    box(1.5, .9, .1, (0, 0, .05), mat(50, 50, 50, metal=.5))
    cyl(.06, .5, (.5, .2, 1.1), mat(30, 30, 30, metal=.5), seg=8)
    box(.4, .02, .3, (-.3, -.41, .6), mat(30, 30, 34))
    for x in (-.4, -.3):
        ball(.03, (x, -.43, .7), mat(255, 60, 40, emit=4.0, grime=0))
    for k in range(4):
        cyl(.03, .9, (.4 + k * .1, -.5, .03), mat(20, 20, 20), (0, 90, k * 20), seg=6)
    return 1.8, 1.3


# -------------------------------------------------------------- the mill
BARK = (88, 62, 42)


def log_pile():
    for k, (y, z) in enumerate([(-.45, .25), (0, .25), (.45, .25), (-.22, .66), (.22, .66), (0, 1.05)]):
        cyl(.22, 2.4, ((k % 2) * .1, y, z), mat(*BARK, grime=.5), (0, 90, 0), seg=14)
        for s in (1, -1):
            cyl(.2, .01, ((k % 2) * .1 + s * 1.2, y, z), mat(196, 160, 110, grime=.3), (0, 90, 0), seg=14)
    for s in (1, -1):
        box(.08, .08, 1.3, (s * .9, -.75, .65), mat(*WOOD))
    return 2.7, 1.4


def saw_blade():
    steel = mat(190, 194, 196, metal=.9, rough=.3, grime=.4)
    cyl(1.0, .04, (0, 0, 1.2), steel, (90, 0, 0), seg=40)
    for k in range(24):
        a = k / 24 * math.tau
        box(.12, .05, .12, (math.cos(a) * 1.02, 0, 1.2 + math.sin(a) * 1.02), steel, (0, -math.degrees(a) + 45, 0))
    cyl(.15, .1, (0, 0, 1.2), mat(60, 60, 60, metal=.6), (90, 0, 0), seg=12)
    box(.3, .3, 1.2, (0, .2, .6), mat(70, 74, 70, metal=.5, grime=.6))
    box(1.6, .5, .2, (0, .2, .1), mat(70, 74, 70, metal=.5, grime=.6))
    return 2.2, 2.3


def forklift():
    paint = mat(220, 160, 30, metal=.3, rough=.5, grime=.7)
    box(1.2, .9, .6, (0, 0, .6), paint)
    box(.6, .9, .06, (-.1, 0, 1.75), mat(40, 40, 40, metal=.5))
    for x in (-.4, .2):
        for y in (-.42, .42):
            box(.05, .05, 1.2, (x, y, 1.2), mat(40, 40, 40, metal=.5))
    box(.4, .3, .1, (-.1, 0, .98), mat(30, 30, 30))
    for y in (-.3, .3):
        box(.1, .9, .05, (.8, y, .08), mat(60, 60, 60, metal=.7))
        box(.1, .06, 1.5, (.65, y, .8), mat(60, 60, 60, metal=.7))
    for x in (-.4, .4):
        wheel(.24, .16, (x, .5, .24), mat(80, 80, 80, metal=.5), (90, 0, 0))
    box(.9, .7, .12, (.95, 0, .2), mat(*GREY_WOOD, planks=8.0))
    ROOT.rotation_euler = Euler((0, 0, math.radians(40)))
    return 2.2, 1.9


def sawdust_pile():
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=24, radius1=1.0, radius2=.15, depth=.8)
    place(bm, mat(206, 168, 112, rough=1.0, grime=.25), (0, 0, .4), (0, 0, 0))
    box(.05, .05, .8, (.6, -.3, .5), mat(*WOOD), (0, 30, 0))
    box(.25, .02, .3, (.75, -.3, .25), mat(150, 150, 150, metal=.7), (0, 30, 0))
    return 2.2, 1.0


def lumber_cart():
    iron = mat(70, 70, 66, metal=.6, grime=.7)
    box(1.8, .9, .1, (0, 0, .4), iron)
    for x in (-.6, .6):
        for y in (-.45, .45):
            wheel(.16, .08, (x, y, .16), iron, (90, 0, 0))
    for k in range(5):
        box(1.7, .8, .1, (0, 0, .5 + k * .11), mat(196, 160, 110, planks=20.0, grime=.3))
    box(.05, .9, .7, (-.85, 0, .75), iron)
    ROOT.rotation_euler = Euler((0, 0, math.radians(70)))
    return 2.1, 1.2


def axe_stump():
    cyl(.35, .5, (0, 0, .25), mat(*BARK, grime=.5), seg=16)
    cyl(.33, .01, (0, 0, .5), mat(190, 150, 100, grime=.35), seg=16)
    box(.04, .04, .7, (.05, 0, .8), mat(*WOOD), (0, -20, 0))
    box(.2, .03, .14, (-.03, 0, .52), mat(170, 172, 170, metal=.8), (0, -20, 0))
    for k in range(4):
        box(.4, .1, .1, (-.4 + k * .1, .4 + (k % 2) * .1, .05), mat(190, 150, 100), (0, 0, k * 40))
    return 1.1, 1.25


def lantern_post():
    cyl(.05, 1.6, (0, 0, .8), mat(*WOOD), seg=8)
    box(.4, .05, .05, (.18, 0, 1.55), mat(*WOOD))
    cyl(.1, .22, (.34, 0, 1.36), mat(60, 50, 30, metal=.6), seg=8)
    ball(.08, (.34, 0, 1.36), mat(255, 190, 90, emit=7.0, grime=0))
    return .8, 1.7


def pallet_stack():
    for k in range(5):
        box(1.1, .9, .12, ((k % 2) * .04, 0, .06 + k * .14), mat(*GREY_WOOD, planks=16.0, grime=.5), (0, 0, k * 3))
    return 1.4, .85


# ------------------------------------------------------------- the quarry
STONE = (190, 184, 168)


def mine_cart():
    iron = mat(110, 70, 44, metal=.6, grime=.75)
    box(1.1, .7, .55, (0, 0, .55), iron)
    for x in (-.35, .35):
        for y in (-.3, .3):
            wheel(.14, .06, (x, y, .14), mat(50, 50, 50, metal=.7), (90, 0, 0))
    for k in range(5):
        ball(.18, (-.3 + k * .15, (k % 2) * .1, .86), mat(*STONE, grime=.5), (1.2, 1, .8))
    for y in (-.3, .3):
        box(2.4, .06, .05, (0, y, .02), mat(80, 70, 60, metal=.6))
    return 2.5, 1.05


def drill_rig():
    yellow = mat(210, 160, 40, metal=.3, grime=.75)
    box(1.4, 1.0, .5, (0, 0, .45), yellow)
    for y in (-.5, .5):
        box(1.5, .2, .3, (0, y, .15), mat(40, 40, 40, metal=.5))
    box(.2, .2, 2.6, (.6, 0, 1.8), mat(90, 90, 86, metal=.7, grime=.5), (0, 10, 0))
    cyl(.05, 1.0, (.7, 0, .3), mat(170, 170, 170, metal=.8), seg=8)
    box(.5, .5, .5, (-.3, 0, .95), mat(40, 50, 60, rough=.2))
    return 2.0, 3.0


def rock(r, loc, colour, scale, rot):
    # A faceted lump: a coarse sphere left flat-shaded, so it reads as stone.
    ob = ball(r, loc, mat(*colour, rough=.95, grime=.85), scale, rot, seg=6)
    for p in ob.data.polygons:
        p.use_smooth = False
    return ob


def boulder_a():
    rock(.6, (0, 0, .45), (128, 120, 106), (1.3, 1, .9), (10, 20, 0))
    rock(.35, (.6, .2, .25), (112, 106, 94), (1, 1, .9), (0, 30, 40))
    return 2.0, 1.1


def boulder_b():
    rock(.5, (0, 0, .5), (120, 112, 98), (1, 1, 1.3), (30, 10, 50))
    return 1.3, 1.3


def tnt_crate():
    crate = mat(150, 110, 70, planks=8.0, grime=.5)
    box(.8, .6, .5, (0, 0, .25), crate)
    box(.6, .02, .2, (0, -.31, .3), mat(200, 30, 26))
    for k in range(4):
        cyl(.05, .4, (-.2 + k * .13, 0, .6), mat(210, 50, 40, rough=.4), (0, 70, 0), seg=8)
    cyl(.004, .4, (.3, 0, .7), mat(240, 240, 220), (0, 30, 0), seg=3)
    return 1.0, .85


def copper_vat():
    copper = mat(184, 104, 58, metal=.85, rough=.32, grime=.6)
    cyl(.7, 1.6, (0, 0, .8), copper, seg=24)
    for z in (.3, 1.3):
        cyl(.72, .06, (0, 0, z), mat(60, 50, 40, metal=.6), seg=24)
    cyl(.2, .5, (0, 0, 1.85), copper, seg=16, top=.08)
    cyl(.05, 1.2, (.6, 0, 1.9), copper, (0, 60, 0), seg=8)
    ball(.08, (.45, -.6, .9), mat(255, 255, 255, metal=.3, rough=.2))
    for s in (1, -1):
        box(.08, .08, .4, (s * .5, s * .3, .2), mat(60, 60, 60, metal=.6))
    return 2.0, 2.4


def crusher():
    iron = mat(120, 96, 70, metal=.6, grime=.8)
    box(1.6, 1.4, 1.2, (0, 0, .9), iron)
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=4, radius1=1.2, radius2=.6, depth=.8)
    place(bm, iron, (0, 0, 1.9), (180, 0, 45))
    for s in (1, -1):
        box(.15, .15, .9, (s * .7, s * .6, .3), mat(60, 60, 60, metal=.6))
    cyl(.4, .2, (.9, 0, 1.0), mat(50, 50, 50, metal=.6), (0, 90, 0), seg=16)
    return 2.4, 2.6


def jug_stack():
    crate = mat(*GREY_WOOD, planks=8.0, grime=.6)
    box(.9, .6, .3, (0, 0, .15), crate)
    for k in range(6):
        x, y = -.3 + (k % 3) * .3, -.13 + (k // 3) * .26
        ball(.12, (x, y, .42), mat(200, 180, 140, rough=.4, grime=.4), (1, 1, 1.1))
        cyl(.04, .1, (x, y, .58), mat(200, 180, 140), seg=8)
        cyl(.012, .06, (x + .06, y, .55), mat(220, 220, 220), (0, 90, 0), seg=6)
    box(.2, .02, .14, (0, -.31, .15), mat(240, 230, 200))
    return 1.1, .75


def dump_truck():
    paint = mat(200, 140, 40, metal=.3, grime=.8)
    box(1.4, 1.4, .9, (-.4, 0, 1.2), paint, (0, -8, 0))
    box(.9, 1.3, .9, (.8, 0, 1.1), paint)
    box(.02, 1.0, .4, (1.26, 0, 1.3), mat(40, 50, 60, rough=.15))
    for x in (-.6, .8):
        for y in (-.62, .62):
            wheel(.38, .3, (x, y, .38), mat(70, 70, 70, metal=.5), (90, 0, 0))
    for k in range(4):
        ball(.3, (-.5 + k * .2, (k % 2) * .3 - .15, 1.7), mat(*STONE, grime=.5), (1.2, 1, .7))
    ROOT.rotation_euler = Euler((0, 0, math.radians(25)))
    return 3.0, 2.2


def cable_spool():
    wood = mat(*WOOD, planks=6.0, grime=.6)
    for x in (-.35, .35):
        cyl(.6, .06, (x, 0, .6), wood, (0, 90, 0), seg=24)
    cyl(.4, .64, (0, 0, .6), mat(30, 30, 30, metal=.4), (0, 90, 0), seg=20)
    return 1.4, 1.25


def warning_barrel():
    cyl(.3, .9, (0, 0, .45), mat(240, 120, 30, rough=.5, grime=.5), seg=18)
    for z in (.3, .6):
        cyl(.305, .1, (0, 0, z), mat(250, 250, 240, rough=.5, grime=.4), seg=18)
    return .8, 1.0


MORE = {
    "truck_blocks": truck_blocks, "porch_couch": porch_couch, "wheelbarrow": wheelbarrow,
    "chicken_coop": chicken_coop, "gas_cans": gas_cans, "tire_stack": tire_stack,
    "bathtub": bathtub, "mailbox_row": mailbox_row,
    "ferris_wheel": ferris_wheel, "carousel_horse": carousel_horse, "cotton_candy": cotton_candy,
    "high_striker": high_striker, "prize_bear": prize_bear, "port_a_john": port_a_john,
    "giant_hog": giant_hog, "balloons": balloons, "searchlight": searchlight, "generator": generator,
    "log_pile": log_pile, "saw_blade": saw_blade, "forklift": forklift, "sawdust_pile": sawdust_pile,
    "lumber_cart": lumber_cart, "axe_stump": axe_stump, "lantern_post": lantern_post,
    "pallet_stack": pallet_stack,
    "mine_cart": mine_cart, "drill_rig": drill_rig, "boulder_a": boulder_a, "boulder_b": boulder_b,
    "tnt_crate": tnt_crate, "copper_vat": copper_vat, "crusher": crusher, "jug_stack": jug_stack,
    "dump_truck": dump_truck, "cable_spool": cable_spool, "warning_barrel": warning_barrel,
}


# --------------------------------------------------------------- the wrecks
def _car_body(paint, length=1.9, cab=(.95, .45), roof_y=1.12, pickup=False):
    rust = mat(126, 64, 36, metal=.4, grime=.8)
    glass = mat(30, 38, 44, rough=.15, metal=.2, grime=.3)
    box(length, .86, .42, (0, 0, .5), paint)
    box(length * .18, .84, .2, (length * .41, 0, .76), paint, (0, 6, 0))
    box(cab[0], .82, cab[1], (-.05 if not pickup else .18, 0, .72 + cab[1] / 2), paint)
    box(cab[0] - .1, .84, cab[1] - .14, (-.05 if not pickup else .18, 0, .74 + cab[1] / 2), glass)
    box(.06, .8, .28, (length / 2 + .02, 0, .5), mat(*CHROME, metal=.8, grime=.6))
    box(.06, .8, .2, (-length / 2 - .02, 0, .45), mat(*CHROME, metal=.8, grime=.6))
    for k in range(5):
        ball(.1, (-.6 + k * .3, -.425, .42 + (k % 2) * .12), rust, (1.5, .06, .8))
    if pickup:
        box(.9, .84, .1, (-.55, 0, .76), rust)
        for s in (1, -1):
            box(.9, .05, .22, (-.55, s * .41, .86), paint)
    return rust


def wreck_sedan():
    paint = mat(150, 120, 80, metal=.3, rough=.6, grime=.85)
    _car_body(paint)
    wheel(.24, .16, (.62, .44, .26), mat(60, 60, 60, metal=.5), (90, 0, 0))
    wheel(.24, .16, (-.62, -.44, .26), mat(60, 60, 60, metal=.5), (90, 0, 0))
    box(.3, .25, .3, (.62, -.36, .15), mat(120, 118, 112, grime=.6))
    box(.3, .25, .3, (-.62, .36, .15), mat(120, 118, 112, grime=.6))
    box(.5, .86, .05, (.78, 0, .95), mat(110, 140, 90, metal=.3, grime=.8), (0, -50, 0))
    ROOT.rotation_euler = Euler((0, math.radians(-2), math.radians(15)))
    return 2.3, 1.4


def wreck_pickup():
    paint = mat(70, 100, 130, metal=.3, rough=.6, grime=.85)
    _car_body(paint, 2.1, (.7, .48), pickup=True)
    for x, y in [(.7, .44), (.7, -.44), (-.65, .44)]:
        wheel(.26, .17, (x, y, .27), mat(60, 60, 60, metal=.5), (90, 0, 0))
    box(.3, .25, .3, (-.65, -.36, .15), mat(120, 118, 112, grime=.6))
    for k in range(3):
        cyl(.18, .14, (-.6 + k * .18, 0, .92), mat(*TIRE), seg=14)
    ROOT.rotation_euler = Euler((0, math.radians(3), math.radians(-20)))
    return 2.5, 1.5


def derby_car():
    paint = mat(220, 70, 40, metal=.2, rough=.5, grime=.55)
    _car_body(paint, 1.9, (.95, .42))
    cyl(.22, .02, (0, -.44, .58), mat(250, 240, 220), (90, 0, 0), seg=18)
    box(.08, .02, .22, (0, -.455, .58), mat(20, 20, 20))
    for x in (.62, -.62):
        for y in (.44, -.44):
            wheel(.24, .16, (x, y, .26), mat(70, 70, 70, metal=.5), (90, 0, 0))
    box(.5, .86, .05, (.8, 0, .82), paint, (0, -25, 18))
    box(.4, .3, .25, (-.95, .3, .55), paint, (30, 0, 40))
    ROOT.rotation_euler = Euler((math.radians(3), 0, math.radians(30)))
    return 2.4, 1.4


def school_bus():
    yellow = mat(220, 170, 40, metal=.2, rough=.55, grime=.8)
    box(5.0, 1.2, 1.4, (0, 0, 1.05), yellow)
    box(.9, 1.1, .7, (2.9, 0, .7), yellow)
    for k in range(8):
        box(.42, 1.22, .42, (-2.1 + k * .55, 0, 1.38), mat(30, 38, 44, rough=.15, grime=.4))
    box(5.02, 1.22, .06, (0, 0, .95), mat(20, 20, 20))
    box(5.02, 1.22, .06, (0, 0, 1.12), mat(20, 20, 20))
    for x, y in [(2.6, .6), (-1.8, .6), (2.6, -.6), (-1.8, -.6)]:
        box(.3, .3, .35, (x, y, .17), mat(120, 118, 112, grime=.6))
    for k in range(6):
        ball(.16, (-2.0 + k * .8, -.6, .8 + (k % 3) * .25), mat(126, 64, 36, metal=.4, grime=.8), (1.6, .05, .8))
    ROOT.rotation_euler = Euler((0, 0, math.radians(15)))
    return 6.0, 2.2


MORE.update({"wreck_sedan": wreck_sedan, "wreck_pickup": wreck_pickup, "derby_car": derby_car, "school_bus": school_bus})
