"""Mundell's junk bench (src/features/bench.gd): a plank top on a cabinet
skinned in corrugated tin, a pegboard behind it hung with tools and duct
tape, a vise on the corner, a coffee can of bolts and a hubcap on the top.
It stands over the Crossroads' yard counter (as wide and deep, a hair
bigger) and alone at a chapter's start. Loaded by town_props.py after
props_more.py (exec'd into its namespace: mat, box, cyl, ball, beam, ROOT and
the colours are in scope). Modelled here from plain shapes; nothing is
traced from another game."""


def junk_bench():
    plank = mat(126, 92, 58, planks=9.0, grime=.55)
    dark = mat(70, 50, 34, planks=6.0, grime=.6)
    tin = mat(150, 148, 140, metal=.6, rough=.5, grime=.65)
    rust = mat(*RUST, metal=.4, rough=.7, grime=.6)
    iron = mat(60, 62, 66, metal=.7, rough=.45, grime=.5)
    vise_blue = mat(56, 82, 104, metal=.4, rough=.5, grime=.6)
    duct = mat(150, 152, 154, metal=.3, rough=.5, grime=.35)
    board = mat(146, 104, 62, grime=.45)
    hole = mat(28, 20, 14, grime=0)
    red = mat(170, 40, 30, metal=.3, rough=.5, grime=.5)
    chrome = mat(*CHROME, metal=.85, rough=.3, grime=.3)
    w, d = 1.66, .66
    # The cabinet: corner posts, tin skin with its ridges, a plank side.
    for x in (-w / 2 + .05, w / 2 - .05):
        for y in (-d / 2 + .05, d / 2 - .05):
            box(.09, .09, .8, (x, y, .4), dark)
    box(w - .06, .02, .7, (0, -d / 2 + .01, .43), tin)
    for k in range(15):
        x = -w / 2 + .1 + k * (w - .2) / 14
        box(.025, .03, .7, (x, -d / 2, .43), tin)
    box(w - .1, .03, .03, (0, -d / 2 - .01, .1), rust)
    box(w - .1, .03, .03, (0, -d / 2 - .01, .76), rust)
    for s in (-1, 1):
        box(.02, d - .06, .72, (s * (w / 2 - .01), 0, .42), plank)
    box(w - .06, d - .06, .04, (0, 0, .08), dark)
    # The plank top, a hair over all round, and a lip at its back.
    box(w + .06, d + .06, .07, (0, 0, .835), plank)
    for k in range(5):
        y = -d / 2 + .04 + k * (d / 5)
        box(w + .06, .006, .072, (0, y, .836), dark)
    # The pegboard, its holes, its frame.
    box(w, .03, .98, (0, d / 2 - .03, 1.36), board)
    for row in range(8):
        for col in range(15):
            x = -w / 2 + .1 + col * (w - .2) / 14
            z = .94 + row * .11
            cyl(.009, .006, (x, d / 2 - .046, z), hole, (90, 0, 0), seg=6)
    for x in (-w / 2, w / 2):
        box(.05, .05, 1.0, (x, d / 2 - .03, 1.36), dark)
    box(w + .05, .05, .05, (0, d / 2 - .03, 1.86), dark)
    # On the board: a hammer, a big wrench, a hand saw, two rolls of tape, a coil of wire.
    box(.04, .02, .3, (-.62, d / 2 - .07, 1.25), mat(*WOOD, grime=.4))
    box(.14, .04, .045, (-.62, d / 2 - .075, 1.41), iron)
    box(.04, .015, .34, (-.42, d / 2 - .07, 1.3), chrome, (0, 12, 0))
    cyl(.045, .02, (-.39, d / 2 - .07, 1.47), chrome, (90, 0, 0), seg=10)
    box(.26, .008, .12, (-.12, d / 2 - .065, 1.32), mat(176, 176, 172, metal=.8, rough=.35, grime=.4))
    box(.08, .03, .1, (.05, d / 2 - .07, 1.32), mat(*WOOD, grime=.4))
    for x, z in ((.3, 1.5), (.48, 1.48)):
        cyl(.07, .05, (x, d / 2 - .09, z), duct, (90, 0, 0), seg=20)
        cyl(.04, .052, (x, d / 2 - .09, z), mat(160, 120, 70, grime=.3), (90, 0, 0), seg=16)
    for k in range(5):
        cyl(.08 - k * .004, .012, (.66, d / 2 - .08 - k * .006, 1.2), mat(168, 92, 52, metal=.8, rough=.35, grime=.4),
            (90, 0, 0), seg=18, top=.078 - k * .004)
    # The vise on the front right corner, its bar through it.
    box(.16, .2, .09, (.6, -d / 2 + .08, .92), vise_blue)
    box(.16, .05, .12, (.6, -d / 2 - .02, .95), vise_blue)
    box(.15, .02, .07, (.6, -d / 2 + .02, .97), iron)
    cyl(.012, .26, (.6, -d / 2 - .07, .93), chrome, (0, 90, 0), seg=10)
    for s in (-1, 1):
        ball(.02, (.6 + s * .13, -d / 2 - .07, .93), chrome)
    # On the top: a coffee can of bolts, a roll of tape, a hubcap, a jug.
    cyl(.07, .14, (-.55, -.1, .94), red, seg=18)
    for k in range(7):
        ball(.02, (-.55 + (k % 3 - 1) * .03, -.1 + (k // 3 - 1) * .03, 1.01), rust, (1, 1, .6))
    cyl(.075, .05, (-.25, .05, .895), duct, seg=20)
    cyl(.04, .052, (-.25, .05, .896), mat(160, 120, 70, grime=.3), seg=16)
    cyl(.15, .025, (.15, .08, .885), chrome, seg=24, top=.1)
    cyl(.06, .03, (.15, .08, .91), chrome, seg=18, top=.03)
    cyl(.06, .2, (.32, .12, .97), mat(200, 190, 150, rough=.4, grime=.4), seg=16)
    cyl(.02, .05, (.32, .12, 1.09), mat(200, 190, 150, rough=.4, grime=.4), seg=10)
    return 1.8, 1.92


MORE.update({"junk_bench": junk_bench})
