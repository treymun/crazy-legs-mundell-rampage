"""The county's hazards a man can be booted into (content pass 8,
godot/src/features/brawl.gd): a tow-behind wood chipper, a bug zapper on its
post, a run of hot fence with its charger, a stone well and a cattle guard.
Loaded by town_props.py (exec'd into its namespace, so mat, box, cyl, ball,
wheel, ROOT and the colours are in scope). The burn barrels, the mill's saws
and the crushers were props already. All original, modelled from plain
shapes like the rest of the town's."""

HAZARD_ORANGE = (214, 112, 34)
HAZARD_YELLOW = (226, 186, 52)


def wood_chipper():
    paint = mat(*HAZARD_ORANGE, metal=.3, rough=.5, grime=.45)
    steel = mat(96, 98, 96, metal=.7, rough=.45, grime=.6)
    dark = mat(16, 14, 12, grime=.1)
    # The body on its axle and the drum's housing, a fat round drum across it.
    box(.9, .7, .5, (.15, 0, .7), paint)
    cyl(.4, .74, (-.15, 0, .92), paint, (90, 0, 0), seg=24)
    cyl(.16, .76, (-.15, 0, .92), steel, (90, 0, 0), seg=16)
    # The feed chute: a square hopper out front, its mouth toward you dark
    # behind a rubber flap curtain, a yellow lip round it.
    box(.56, .62, .5, (-.72, 0, 1.0), paint, (0, 25, 0))
    box(.04, .5, .38, (-1.0, 0, 1.12), dark, (0, 25, 0))
    for k in range(5):
        box(.02, .09, .34, (-1.02, -.2 + k * .1, 1.1), mat(40, 38, 34, rough=.95, grime=.3), (0, 25, 0))
    for s in (1, -1):
        box(.08, .04, .52, (-1.0, s * .3, 1.12), mat(*HAZARD_YELLOW, grime=.4), (0, 25, 0))
    box(.08, .64, .05, (-.9, 0, 1.37), mat(*HAZARD_YELLOW, grime=.4), (0, 25, 0))
    # The discharge chute: a pipe up and back with a hood turned over.
    cyl(.13, .9, (.35, 0, 1.45), paint, (0, 25, 0), seg=12)
    box(.42, .3, .22, (.62, 0, 1.88), paint, (0, -25, 0))
    ball(.07, (.86, 0, 1.78), mat(196, 160, 110, grime=.5), (1.4, 1, .6))
    # The engine behind, its tank and the pull start.
    box(.4, .46, .36, (.62, .05, 1.1), mat(40, 42, 44, metal=.5, grime=.6))
    box(.22, .3, .12, (.62, .05, 1.34), mat(170, 30, 26, metal=.3, grime=.5))
    ball(.04, (.45, -.2, 1.15), mat(200, 30, 26, grime=.4))
    # Two wheels and the tow tongue with its hitch.
    for s in (1, -1):
        wheel(.32, .16, (.25, s * .48, .32), mat(60, 60, 60, metal=.5), (90, 0, 0))
    box(1.0, .08, .08, (1.1, 0, .52), steel, (0, 10, 0))
    cyl(.07, .08, (1.6, 0, .44), steel, (0, 0, 0), seg=10)
    box(.08, .08, .5, (.65, 0, .22), steel)
    # A warning plate on its side: a white panel over stripes.
    box(.34, .015, .16, (.15, -.36, .82), mat(220, 214, 196, grime=.4))
    for k in range(6):
        colour = (30, 28, 26) if k % 2 else HAZARD_YELLOW
        box(.05, .015, .07, (.0 + k * .06, -.365, .68), mat(*colour, grime=.4), (0, 30, 0))
    ROOT.rotation_euler = Euler((0, 0, math.radians(-12)))
    return 2.6, 2.1


def bug_zapper():
    post = mat(*WOOD, grime=.6)
    tin = mat(84, 82, 76, metal=.6, rough=.5, grime=.5)
    # The hot grid glows too: a fine violet mesh round the tubes.
    grid = mat(120, 96, 230, emit=.7, metal=.4, rough=.4, grime=0)
    glow = mat(104, 72, 255, emit=2.6, grime=0)
    # A cedar post and the arm the lantern hangs from.
    box(.12, .12, 2.0, (0, 0, 1.0), post)
    box(.6, .09, .09, (.26, 0, 1.92), post)
    cyl(.014, .14, (.5, 0, 1.82), tin, seg=6)
    # The lantern, big enough to read: a pressed-tin hood and catch tray,
    # four bright violet tubes inside a glowing wire grid.
    cyl(.3, .1, (.5, 0, 1.72), tin, seg=20, top=.12)
    cyl(.26, .05, (.5, 0, 1.06), tin, seg=20)
    cyl(.27, .02, (.5, 0, 1.03), mat(40, 36, 30, grime=.2), seg=20)
    for k in range(4):
        a = k / 4 * math.tau + .4
        cyl(.04, .58, (.5 + math.cos(a) * .1, math.sin(a) * .1, 1.38), glow, seg=10)
    for k in range(18):
        a = k / 18 * math.tau
        cyl(.007, .62, (.5 + math.cos(a) * .24, math.sin(a) * .24, 1.38), grid, seg=4)
    for z in (1.12, 1.26, 1.4, 1.54, 1.66):
        cyl(.24, .012, (.5, 0, z), grid, seg=20)
    # Fried bugs heaped on the tray, a moth stuck to the grid, the cord down
    # the post to its plug box.
    for k in range(9):
        a = k * 2.4
        ball(.016, (.5 + math.cos(a) * (.05 + k * .015), math.sin(a) * (.05 + k * .015), 1.09),
             mat(26, 22, 16, grime=.1), (1.4, 1, .6))
    ball(.03, (.5, -.25, 1.48), mat(150, 130, 100, grime=.3), (1.6, .3, 1))
    cyl(.01, 1.1, (.06, -.07, 1.0), mat(20, 20, 20), (0, 0, 0), seg=4)
    box(.14, .08, .18, (0, -.1, .5), mat(160, 154, 140, metal=.3, grime=.7))
    return 1.4, 2.2


def electric_fence():
    post = mat(*GREY_WOOD, grime=.6)
    white = mat(226, 220, 204, rough=.4, grime=.3)
    wire = mat(170, 172, 176, metal=.9, rough=.3, grime=.4)
    # Two posts, white insulators, three strands of hot wire.
    for x in (-.95, .95):
        box(.1, .1, 1.3, (x, 0, .65), post)
        for z in (.4, .75, 1.1):
            cyl(.03, .06, (x, -.07, z), white, (90, 0, 0), seg=8)
    for k, z in enumerate((.4, .75, 1.1)):
        nodes = [(-.95, -.093, z), (-.48, -.098, z - .025),
                 (0.03, -.094, z - .038), (.51, -.087, z - .024), (.95, -.093, z)]
        for a, b in zip(nodes, nodes[1:]):
            beam(a, b, .013, wire)
        for x in (-.903, .903):
            cyl(.027, .023, (x, -.092, z), wire, (0, 90, 0), seg=8)
    for x in (-.95, .95):
        box(.139, .131, .037, (x, 0, 1.28), mat(94, 91, 72, metal=.45, grime=.7))
    # The charger on the near post: a grey box, its red pulse lamp, the
    # ground rod and lead, a yellow warning sign hung off the top strand.
    box(.26, .14, .3, (-.95, -.16, .95), mat(110, 112, 108, metal=.4, grime=.6))
    ball(.035, (-.88, -.24, 1.02), mat(255, 50, 30, emit=6.0, grime=0))
    box(.12, .02, .05, (-1.0, -.24, .88), mat(30, 30, 30))
    cyl(.012, .5, (-.82, -.2, .3), mat(130, 90, 50, metal=.7), seg=6)
    box(.36, .015, .22, (.1, -.1, .98), mat(*HAZARD_YELLOW, grime=.55))
    for k in range(3):
        box(.04 + k * .02, .016, .02, (.1, -.11, 1.04 - k * .045), mat(30, 28, 26))
    ball(.025, (.1, -.112, .91), mat(30, 28, 26), (1, .3, 1.6))
    lead = mat(75, 64, 53, rough=.8, grime=.47)
    beam((-.855, -.219, .895), (-.86, -.241, .426), .015, lead)
    beam((-.86, -.241, .426), (-.82, -.2, .27), .015, lead)
    for x in (-.049, .247):
        beam((x, -.111, 1.071), (x, -.112, 1.133), .013, wire)
    return 2.4, 1.4


def well():
    stone = mat(150, 144, 132, rough=.95, grime=.7)
    mortar = mat(110, 104, 92, rough=1., grime=.5)
    post = mat(*WOOD, grime=.6)
    # The ring of stone, courses of blocks round it, dark water down inside.
    cyl(.62, .8, (0, 0, .4), mortar, seg=24)
    for course in range(3):
        for k in range(10):
            a = (k + course * .5) / 10 * math.tau
            box(.36, .2, .24, (math.cos(a) * .6, math.sin(a) * .6, .14 + course * .26), stone,
                (0, 0, math.degrees(a) + 90))
    cyl(.5, .02, (0, 0, .78), mat(14, 18, 22, rough=.1, grime=0), seg=24)
    # Two posts and a little shingled roof, the crank and its rope, a pail.
    for s in (1, -1):
        box(.1, .1, 1.5, (s * .62, 0, 1.3), post)
    for s in (1, -1):
        box(1.6, .6, .05, (0, s * .26, 2.12), mat(96, 64, 40, planks=14.0, grime=.6), (s * 32, 0, 0))
    cyl(.05, 1.3, (0, 0, 1.6), post, (0, 90, 0), seg=10)
    box(.04, .25, .04, (.7, -.12, 1.6), post)
    cyl(.012, .5, (0, 0, 1.33), mat(176, 146, 84, rough=.95), seg=4)
    cyl(.1, .16, (0, 0, 1.0), mat(110, 112, 110, metal=.6, rough=.5, grime=.7), seg=12, top=.08)
    return 1.9, 2.4


def cattle_guard():
    steel = mat(80, 82, 80, metal=.7, rough=.5, grime=.8)
    rust = mat(*RUST, metal=.4, rough=.8, grime=.7)
    # A dark pit under a grate of round pipes across a road, the frame round it
    # and the wings off each side.
    box(1.8, 1.3, .02, (0, 0, .01), mat(18, 16, 14, grime=.1))
    for k in range(9):
        x = -.8 + k * .2
        box(.102, 1.34, .072, (x, 0, .078), steel if k % 3 else rust)
        box(.061, 1.33, .02, (x - .012, 0, .116), mat(117, 107, 85, metal=.63, grime=.6))
        for y in (-.597, .597):
            cyl(.021, .011, (x, y, .126), steel, seg=6)
    for y in (-.46, .46):
        box(1.79, .077, .029, (0, y, .038), steel)
    for s in (1, -1):
        box(1.86, .1, .12, (0, s * .68, .06), steel)
        box(.1, 1.36, .12, (s * .93, 0, .06), steel)
    for s in (1, -1):
        box(.08, .08, .5, (s * .97, .7, .25), rust)
        box(.08, .7, .06, (s * .97, .35, .45), rust, (-30, 0, 0))
    return 2.2, .7


MORE.update({"wood_chipper": wood_chipper, "bug_zapper": bug_zapper, "electric_fence": electric_fence,
             "well": well, "cattle_guard": cattle_guard})
