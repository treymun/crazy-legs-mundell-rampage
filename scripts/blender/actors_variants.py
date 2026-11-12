"""Three variants of the county's regulars (enemies.cfg sections with brain= their
base kind; the art is drawn here with the base kind's cels). Exec'd by
enemy_actors.py after the chapters' files (billy, coot, person, cast, DEPUTY,
ACTORS and the rest in scope).

    big_billy      a hulking Billy: a size and a half bigger, sleeves torn off,
                   a scar and a double-barrel with its hammers back
    drunk_coot     the Coot three jugs in: swaying, a red nose, eyes half shut,
                   his hat knocked crooked and a bigger jug held close
    shield_deputy  a yard deputy behind a pickup's door held up as a shield,
                   its window glass still in, his badge's star on the paint
"""

# Big Billy is Billy drawn BIG times over; his gun hold rises with his shoulders.
BIG = 1.15
BIG_RISE = .19
BIG_BILLY = dict(BILLY, hip_h=.78 * BIG, hip_w=.15 * BIG, stance=.24, stride=.22, ankle=.08 * BIG,
                 thigh=.375 * BIG, shin=.36 * BIG, torso_len=.50 * BIG, neck=.16 * BIG, head_fwd=-.04,
                 sw=.30 * BIG, upper=.30 * BIG, fore=.28 * BIG, boot=.068 * BIG, bow=.24,
                 canvas=(1.75 * BIG, 1.86 * BIG), px=round(152 * BIG), depth=.24 * BIG, head_scale=1.12)

# The drunk Coot's sway, by cel (radians about his forward axis: + leans to his left).
DRUNK_COOT = dict(COOT, lean=.14, stance=.21, bow=.5,
                  roll={0: .12, "w0": .17, "w1": .05, "w2": -.1, "w3": .03, "aim": .05, "wind": .12,
                        "fire": .02, "recover": .1, "fidget": -.08, "pain": -.05, "any": .08})


def big_billy(frame):
    billy(frame, big=True)


def drunk_coot(frame):
    coot(frame, drunk=True)


# ---------------------------------------------------------------- the shield deputy
def _door(S, J, g, d):
    """The pickup door on his left arm: a lower panel in faded county green with the
    star, a chrome window frame with the glass in it, mirror and handle; shot up,
    and worse hurt. Returns where his left hand grips it (inside, by the handle)."""
    frame = J["frame"]
    if J["dead"]:
        return None
    Tm = J["torso"]
    at, turn, tip = (.05, -.42, -.36), .14, 0.
    if frame in ("aim", "fire"):
        at, turn = (.1, -.42, -.46), .22
    elif frame == "recover":
        at = (.07, -.42, -.42)
    elif frame == "pain":
        at, turn, tip = (.22, -.34, -.4), .7, -.25
    G = Tm @ T(at) @ R(tip, 0, turn)
    paint = mat(70, 108, 96, .55, .3, grime=.7)
    chrome = mat(176, 180, 184, .25, .9, grime=.3)
    glass = mat(104, 132, 142, .06, .2, grime=0)
    rust = mat(112, 62, 34, .9, grime=.3)
    box((0, 0, .25), (.7, .05, .5), paint, G)
    box((0, -.028, .44), (.66, .012, .04), mat(214, 206, 180, .6, grime=.5), G)
    star((0, -.04, .24), .1, mat(206, 168, 66, .35, .85, grime=.25), G)
    for x, z, r in ((-.28, .06, .06), (.25, .1, .045), (-.05, .02, .05)):
        ball((x, -.027, z), (r, .008, r * .7), rust, G)
    box((.23, -.04, .4), (.08, .016, .022), chrome, G)
    # The window: frame, glass and a glint across it.
    for a, b in (((-.35, 0, .5), (.35, 0, .5)), ((-.35, 0, .5), (-.27, 0, .86)), ((-.27, 0, .86), (.33, 0, .86)),
                 ((.33, 0, .86), (.35, 0, .5))):
        limb(G @ Vector(a), G @ Vector(b), .022, .022, chrome)
    box((.03, 0, .68), (.62, .012, .34), glass, G)
    for x in (-.12, .06):
        box((x, -.009, .7), (.035, .004, .3), mat(226, 238, 240, .08, grime=0), G, (0, -.5, 0))
    limb(G @ Vector((-.34, -.02, .56)), G @ Vector((-.46, -.06, .62)), .012, .012, chrome)
    box((-.5, -.06, .64), (.09, .03, .12), chrome, G)
    # Shot up: holes in the paint, a starred hole in the glass.
    holes = [(-.2, .3), (.12, .16), (.2, .32)] + ([(-.08, .1), (.28, .2), (-.3, .36)] if WOUND else [])
    for x, z in holes:
        ball((x, -.03, z), (.018, .01, .018), BLACK(), G)
        ball((x, -.028, z), (.028, .006, .028), mat(200, 200, 196, .3, .9, grime=0), G)
    cracks = [((.12, .7), 5)] + ([((-.14, .62), 6), ((.0, .76), 4)] if WOUND else [])
    for (x, z), n in cracks:
        ball((x, -.012, z), (.02, .006, .02), BLACK(), G)
        for k in range(n):
            a = k * math.tau / n + .3
            reach = .07 + .06 * jitter(k, int(x * 100))
            limb(G @ Vector((x, -.012, z)), G @ Vector((x + math.cos(a) * reach, -.012, z + math.sin(a) * reach)),
                 .005, .003, mat(240, 244, 244, .2, grime=0), caps=False, seg=5)
    if WOUND:
        dent((-.15, -.03, .25), .08, G)
        dent((.2, -.03, .12), .06, G)
    return G @ Vector((.24, .05, .58))


SHIELD_DEPUTY = cast(AVG, gut=.35, px=152, shirt=(150, 126, 86), pants=(52, 64, 50), belt=(30, 26, 24),
                     badge=(186, 146, 58), hat="brim", hat_c=(46, 56, 42), beard="moustache", hair=(70, 50, 34),
                     collar=(150, 126, 86), weapon="pistol", hold=ONE, grip=_door)


ACTORS.update({
    "big_billy": (big_billy, BIG_BILLY, ("fidget",), None),
    "drunk_coot": (drunk_coot, DRUNK_COOT, ("fidget",), None),
    "shield_deputy": (maker(SHIELD_DEPUTY), SHIELD_DEPUTY, (), None),
})
