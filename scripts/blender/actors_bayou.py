"""Gator Bayou's cast (chapter five), exec'd by enemy_actors.py into its own
namespace after ACTORS is made, so skeleton, person, cast, limb, ball, ring,
disc, box, flash, puff, mat and the rest are in scope. Built from scratch
like the others: nothing is traced from another game.

    noodler      a hand-fishing brute in chest waders, a catfish by the gills
    chum_tosser  a rubber-aproned bait hand who lobs jugs of chum
    gator        the bayou's own: low, long, all jaw
    swamp_king   the boss: a bearded king in a tin crown at the helm of an
                 armoured airboat, punt gun on the bow, frog gig for a sceptre
"""

_BASE_WEAPON = weapon


# ---------------------------------------------------------------- the hands
# Right-hand holds: where the hand is (from the shoulders' height) and which
# way what it holds points. A catfish hangs by its lip; a chum jug is lobbed.
FISH = {"ready": ((-.30, -.12, -.52), (0, -.15, -1)), "aim": ((-.34, .18, .24), (.1, .55, .8)),
        "fire": ((-.14, -.54, -.06), (.05, -1, -.35)), "recover": ((-.24, -.42, -.32), (0, -.5, -.85)),
        "pain": ((-.42, -.1, -.17), (-.4, -.2, -.9))}
KING_HOLD = {"ready": ((-.30, -.34, -.32), (.05, -1, .02)), "aim": ((-.26, -.42, -.2), (.02, -1, .06)),
             "fire": ((-.26, -.36, -.17), (.02, -1, .16)), "recover": ((-.28, -.38, -.26), (.04, -1, .04)),
             "pain": ((-.44, -.16, -.24), (-.3, -.8, .5))}


def weapon(kind, g, d, J, C):
    frame = J["frame"]
    side = d.cross(Vector((0, 0, 1)))
    side = side.normalized() if side.length > 1e-4 else Vector((1, 0, 0))
    if kind == "catfish":
        # A flathead as long as his arm, held by the lower lip, whiskers and all.
        back = mat(78, 76, 58, .6, grime=.5)
        belly = mat(196, 186, 150, .6, grime=.4)
        ball(g + d * .1, (.12, .12, .12), back)
        limb(g + d * .1, g + d * .52, .11, .045, back)
        limb(g + d * .12 - side * .02, g + d * .48 - side * .02, .085, .03, belly)
        for s in (-1, 1):
            limb(g + d * .02, g + d * .02 + side * s * .16 + Vector((0, 0, -.03)), .008, .003, back, caps=False)
            limb(g + d * .58, g + d * .68 + side * s * .07, .03, .006, back)
            ball(g + d * .06 + side * s * .07, .018, mat(220, 200, 90, .3, grime=0))
        limb(g + d * .3, g + d * .3 + Vector((0, 0, .09)), .025, .004, back, caps=False)
        return None
    if kind == "chum":
        # A milk jug of chum in the throwing hand (gone when thrown), the slop
        # bucket hung from the other.
        if frame not in ("fire", "recover"):
            jug = mat(226, 222, 208, .45, grime=.4)
            ball(g + d * .1, (.085, .085, .1), jug)
            ball(g + d * .1 + Vector((0, 0, -.015)), (.087, .087, .07), mat(132, 52, 40, .5, grime=.3))
            limb(g + d * .18, g + d * .23, .025, .022, jug, caps=False)
            ring(g + d * .1 + side * .07, side, .04, .009, jug, n=10)
        rest = Vector((.30, -.10, .90)) + J["offset"]
        pail = mat(222, 222, 214, .5, grime=.5)
        limb(rest + Vector((0, 0, -.42)), rest + Vector((0, 0, -.16)), .1, .125, pail, caps=False, seg=20)
        disc(rest + Vector((0, 0, -.42)), (0, 0, 1), .1, .01, pail)
        disc(rest + Vector((0, 0, -.18)), (0, 0, 1), .118, .01, mat(124, 46, 36, .5, grime=.3))
        arc(rest + Vector((0, 0, -.16)), (0, 1, 0), (0, 0, 1), .12, -1.5, 1.5, .007, DARK(), n=8)
        return None
    if kind == "puntgun":
        # A punt gun on a swivel: a barrel like a stovepipe, the stock under his arm.
        iron = mat(52, 54, 56, .45, .8, grime=.4)
        limb(g - d * .3, g + d * 1.05, .045, .04, iron, caps=False, seg=16)
        disc(g + d * 1.05, d, .055, .04, iron)
        limb(g - d * .32, g - d * .62 + Vector((0, 0, -.08)), .05, .07, WOOD())
        limb(g + d * .5, g + d * .5 + Vector((0, 0, -.4)), .03, .03, iron)
        ring(g + d * .2, d, .055, .012, BRASS(), n=12)
        if frame == "fire":
            flash(g + d * 1.12, .36, (255, 176, 70))
            puff(g + d * 1.3 + Vector((0, 0, .05)), .1)
        # His left hand holds the frog gig upright: the sceptre of the swamp.
        left = Vector((.44, -.16, 1.5)) + J["offset"]
        pole = mat(120, 92, 60, .7)
        limb(left + Vector((0, 0, -.7)), left + Vector((0, 0, .95)), .022, .02, pole)
        tine = mat(170, 160, 120, .4, .8, grime=.3)
        limb(left + Vector((-.1, 0, .95)), left + Vector((.1, 0, .95)), .016, .016, tine)
        for x in (-.1, 0, .1):
            limb(left + Vector((x, 0, .95)), left + Vector((x * 1.1, 0, 1.2)), .014, .004, tine, caps=False)
        return left
    return _BASE_WEAPON(kind, g, d, J, C)


NOODLER = cast(AVG, gut=.55, sw=.28, px=168, canvas=(1.8, 2.02), hip_h=.86, limb=(.106, .088, .072),
               arm=(.086, .072, .058), upper=.31, fore=.29, skin=(178, 118, 86), shirt=(204, 194, 166),
               bib=(72, 82, 54), pants=(72, 82, 54), sleeve="bare", hat="cap", hat_c=(92, 100, 60),
               beard="long", beard_c=(112, 72, 42), hair=(96, 62, 38), boots=(60, 68, 44), boot_top=.62,
               weapon="catfish", hold=FISH)
CHUMMER = cast(AVG, gut=.3, px=160, shirt=(90, 116, 140), plaid=1, apron=(214, 188, 56),
               pants=(72, 64, 52), boots=(222, 218, 206), boot_top=.6, hat="cap", hat_c=(150, 42, 36),
               beard="stubble", sleeve="rolled", gloves=(200, 164, 56), weapon="chum", hold=THROW)


# ---------------------------------------------------------------- the gator
GATOR = dict(canvas=(2.9, .64), px=54)


def gator(frame):
    """Long, low and all jaw, seen side on and a little from the front: head to
    the right (the game flips it to walk left). Walk cels swing the legs and
    the tail; aim opens the jaw wide, fire snaps it on a lunge."""
    phase = frame if isinstance(frame, int) else 0
    hide = mat(56, 68, 42, .7, grime=.5)
    scute = mat(38, 48, 30, .7, grime=.4)
    belly = mat(196, 184, 140, .7, grime=.4)
    mouth = mat(196, 96, 90, .6, grime=.2)
    open_jaw = {"aim": .62, "fire": .22, "pain": .4}.get(frame, .06)
    lift = {"aim": .14, "fire": .04}.get(frame, 0.)
    reach = .16 if frame == "fire" else 0.
    M = R(0, 0, -.35) @ T((reach, 0, 0))
    if frame == "pain":
        M = M @ R(.25, 0, .18)
    elif frame == "die_0":
        M = T((0, 0, .1)) @ R(0, 0, -.35) @ R(1.0, 0, .1)
    elif frame == "die_1":
        M = T((0, 0, .14)) @ R(0, 0, -.35) @ R(2.1, 0, .15)
    elif frame == "down":
        M = T((0, 0, .26)) @ R(0, 0, -.3) @ R(math.pi, 0, .1)
    dead = frame in ("die_0", "die_1", "down")
    # body: a long low hull of hide, rows of scutes down the back
    ball((0, 0, .2), (.62, .27, .15), hide, M)
    ball((0, 0, .15), (.58, .24, .1), belly, M)
    for k in range(9):
        x = -.5 + k * .13
        for s in (-1, 1):
            limb((x, s * .07, .32), (x, s * .07, .37), .028, .006, scute, M, caps=False, seg=5)
    # head: rises a little to bite, the jaw drops open
    H = M @ T((.55, 0, .22 + lift * .5)) @ R(0, -lift * 1.4, 0)
    ball((.14, 0, .02), (.2, .17, .09), hide, H)
    ball((.42, 0, .02), (.3, .12, .055), hide, H)
    ball((.6, 0, .04), (.05, .06, .03), scute, H)
    J = H @ T((.08, 0, -.02)) @ R(0, open_jaw, 0)
    ball((.32, 0, -.03), (.32, .11, .04), hide, J)
    ball((.3, 0, -.005), (.28, .09, .015), mouth, J)
    if open_jaw > .1:
        ball((.3, 0, .0), (.27, .09, .012), mouth, H)
    tooth = TOOTH()
    for k in range(7):
        x = .16 + k * .07
        for s in (-1, 1):
            limb((x, s * .1, -.02), (x, s * .1, -.06), .012, .002, tooth, H, caps=False, seg=4)
            limb((x, s * .085, .0), (x, s * .085, .035), .011, .002, tooth, J, caps=False, seg=4)
    for s in (-1, 1):
        ball((.12, s * .08, .1), (.05, .045, .045), hide, H)
        ball((.135, s * .09, .115), .028, mat(214, 180, 50, .3, grime=0) if not dead else scute, H)
        ball((.15, s * .1, .118), (.006, .006, .02), BLACK(), H)
    # tail: tapering, swinging with the walk
    pts = []
    for k in range(9):
        t = k / 8
        pts.append(Vector((-.5 - t * 1.0, .1 * phase * math.sin(t * 2.5) + (.08 if frame == "pain" else 0) * t, .18 - t * .1)))
    for k, (a, b) in enumerate(zip(pts, pts[1:])):
        limb(M @ a, M @ b, .14 * (1 - k / 9) + .02, .14 * (1 - (k + 1) / 9) + .02, hide)
        limb(M @ (a + Vector((0, 0, .1 - k * .01))), M @ (b + Vector((0, 0, .1 - k * .01))), .02, .005, scute, caps=False, seg=5)
    # legs: short, splayed, walking corner to corner
    for x, s, k in ((.32, 1, 0), (.32, -1, 1), (-.36, 1, 1), (-.36, -1, 0)):
        swing = .12 * phase * (1 if k else -1)
        hip = M @ Vector((x, s * .2, .2))
        if dead:
            knee = M @ Vector((x + .05, s * .34, .34))
            foot = M @ Vector((x + .1, s * .36, .5))
        else:
            spread = .42 if frame in ("pain", "aim") else .36
            knee = M @ Vector((x + swing * .5, s * .34, .14))
            foot = M @ Vector((x + swing + .06, s * spread, .0))
        limb(hip, knee, .07, .05, hide)
        limb(knee, foot, .05, .035, hide)
        for t in (-1, 0, 1):
            limb(foot, foot + (M.to_3x3() @ Vector((.07, t * .04, 0))), .015, .006, scute, caps=False)
    if frame == "fire":
        white = mat(220, 226, 220, .9, grime=0)
        for k in range(4):
            ball(M @ Vector((.9 + k * .05, (k % 2 - .5) * .3, .05 + k * .03)), .05 + k * .01, white)


# ---------------------------------------------------------------- the swamp king
KING = dict(lean=.04, hip_h=1.25, hip_w=.16, stance=.22, stride=.06, ankle=.43, thigh=.42, shin=.40,
            torso_len=.6, neck=.1, head_fwd=-.06, sw=.36, upper=.33, fore=.31, boot=.08, bow=.2,
            gut=.8, limb=(.12, .1, .08), arm=(.09, .076, .06), depth=.3, head_scale=1.12,
            canvas=(3.4, 2.62), px=172)
KING_LOOK = dict(skin=(196, 126, 92), shirt=(196, 188, 164), vest=(70, 82, 50), pants=(84, 76, 60),
                 sleeve="bare", hat="cap", hat_c=(66, 74, 52), beard="full", beard_c=(170, 76, 40),
                 hair=(160, 72, 38), boots=(56, 50, 40), boot_top=.4, eyes="shades",
                 weapon="puntgun", hold=KING_HOLD)


def swamp_king(frame):
    """The King of the Swamp at the helm of his armoured airboat: a riveted hull
    with a steel bow shield painted into a gator's grin, the punt gun on its
    swivel over it, the engine and its caged prop behind him. He wears a tin
    crown jammed over a mesh cap, a gator hide for a cape with its head on his
    shoulder, red airboat muffs, a cigar and a beard like a brush fire."""
    S = dict(KING, look=KING_LOOK)
    dead = isinstance(frame, str) and frame.startswith("die_")
    stage = int(frame[4:]) if dead else -1
    beat = beat_of(frame)
    hot = frame in ("aim", "fire")
    steel = mat(96, 100, 98, .45, .75, grime=.6)
    rust = mat(128, 66, 38, .6, .4, grime=.6)
    alu = mat(170, 172, 168, .4, .7, grime=.6)
    dark = mat(36, 36, 38, .5, .6, grime=.4)
    red = mat(170, 40, 30, .5, grime=.4)
    if frame == "down":
        king_wreck(steel, rust, alu, dark, red)
        return
    B = T((0, 0, 0))
    bob = .015 * math.sin(beat * math.pi / 2) if not dead else 0.
    # hull: flat riveted steel, the bow raked up, rust where the water sits
    box((0, 0, .14 + bob), (1.3, 2.7, .26), steel, B)
    box((0, -1.45, .26 + bob), (1.28, .5, .12), steel, B, (-.5, 0, 0))
    for s in (-1, 1):
        box((s * .66, 0, .2 + bob), (.04, 2.8, .36), rust, B)
        for k in range(10):
            ball((s * .69, -1.25 + k * .28, .32 + bob), .022, BRASS(), B)
    box((0, .1, .29 + bob), (1.2, 1.6, .04), mat(*GREY_WOOD_A, .9, grime=.5), B)
    # the bow shield: a steel plate painted into a grin
    box((0, -.95, .62 + bob), (1.25, .07, .62), steel, B)
    box((0, -.99, .62 + bob), (1.1, .02, .26), red, B)
    for k in range(8):
        x = -.48 + k * .137
        limb((x, -1.0, .76 + bob), (x + .04, -1.0, .64 + bob), .03, .004, WHITE(), B, caps=False, seg=4)
        limb((x + .06, -1.0, .49 + bob), (x + .03, -1.0, .6 + bob), .03, .004, WHITE(), B, caps=False, seg=4)
    for s in (-1, 1):
        ball((s * .42, -1.0, .86 + bob), (.08, .02, .06), mat(220, 196, 60, .3, emit=.6 if hot else 0.), B)
        ball((s * .42, -1.01, .86 + bob), (.02, .01, .05), BLACK(), B)
    # engine, exhaust and the caged prop behind him
    box((0, .95, .62 + bob), (.6, .5, .5), dark, B)
    box((0, .95, .9 + bob), (.5, .4, .1), red, B)
    for s in (-1, 1):
        limb(B @ Vector((s * .22, .85, .9 + bob)), B @ Vector((s * .26, .8, 1.4 + bob)), .04, .05, dark, caps=False)
        if hot or (beat % 2 == (0 if s < 0 else 1) and not dead):
            puff(B @ Vector((s * .3, .8, 1.5 + bob)), .07 if hot else .05, turn=s > 0)
    cage_c = Vector((0, 1.32, 1.18 + bob))
    pts = []
    for k in range(20):
        a = k * math.tau / 20
        pts.append(B @ (cage_c + Vector((math.cos(a) * .98, 0, math.sin(a) * .98))))
    for a, b in zip(pts, pts[1:] + pts[:1]):
        limb(a, b, .025, .025, alu, caps=False, seg=8)
    for k in range(8):
        a = k * math.tau / 8
        limb(B @ cage_c, B @ (cage_c + Vector((math.cos(a) * .98, .06, math.sin(a) * .98))), .012, .012, alu, caps=False)
    spin = beat * .7 + (.35 if hot else 0)
    for k in range(2):
        a = spin + k * math.pi
        limb(B @ (cage_c + Vector((0, -.08, 0))), B @ (cage_c + Vector((math.cos(a) * .88, -.08, math.sin(a) * .88))), .05, .03,
             mat(150, 116, 72, .7, grime=.4), caps=False)
    disc(B @ (cage_c + Vector((0, -.1, 0))), (0, 1, 0), .1, .08, dark)
    for s in (-1, 1):
        box((s * .3, 1.55, .55 + bob), (.04, .32, .6), steel, B)
    # a pennant on a whip off the cage: a gator skull on red
    limb(B @ (cage_c + Vector((.6, 0, .75))), B @ (cage_c + Vector((.7, 0, 1.35))), .01, .008, dark)
    box((.86, 1.32, 2.42 + bob), (.3, .01, .16), red, B, (0, 0, 0))
    if frame == "fire":
        white = mat(226, 230, 224, .9, grime=0)
        for k in range(6):
            ball(B @ Vector(((k % 3 - 1) * .5, -1.65 - (k // 3) * .2, .15 + (k % 2) * .1)), .14 + (k % 3) * .04, white)
    if dead:
        fire = mat(255, 130, 40, emit=3.0)
        for k in range(2 + stage):
            ball(B @ Vector(((jitter(k) - .5) * .8, .9 + jitter(k, 1) * .4, .9 + jitter(k, 2) * .4)), .1 + jitter(k, 3) * .1, fire)
        if stage >= 2:
            puff(B @ Vector((0, .9, 1.6)), .12 + stage * .02)
    # the king himself, stood at the helm
    pose = frame if not dead else ("pain" if stage < 2 else "die_%d" % (stage - 1))
    person(S, pose)
    J = skeleton(S, pose)
    Tm, Hm = J["torso"], J["head"]
    tin = mat(200, 168, 70, .35, .85, grime=.45)
    crown = Hm @ T((0, .0, .15))
    limb(crown @ Vector((0, 0, 0)), crown @ Vector((0, 0, .07)), .135, .14, tin, caps=False, seg=24)
    for k in range(7):
        a = k * math.tau / 7
        p = crown @ Vector((math.sin(a) * .135, -math.cos(a) * .135, .06))
        limb(p, p + Vector((0, 0, .1)), .03, .004, tin, caps=False, seg=5)
        ball(crown @ Vector((math.sin(a) * .14, -math.cos(a) * .14, .03)), .016, mat(*((170, 30, 30) if k % 2 else (40, 120, 60)), .3, grime=0))
    for s in (-1, 1):
        ball(Hm @ Vector((s * .135, 0, .01)), (.04, .06, .065), red)
    limb(Hm @ Vector((-.13, 0, .06)), Hm @ Vector((.13, 0, .06)), .012, .012, dark)
    cig = Hm @ Vector((.03, -.14, -.07))
    limb(cig, cig + Vector((.09, -.06, -.01)), .014, .012, mat(110, 70, 40, .8))
    ball(cig + Vector((.095, -.065, -.01)), .016, mat(255, 120, 40, emit=2.0))
    cape = mat(60, 76, 46, .7, grime=.5)
    ball(Tm @ Vector((0, .14, S["torso_len"] - .2)), (.38, .12, .3), cape)
    ball(Tm @ Vector((0, .2, S["torso_len"] - .5)), (.34, .08, .3), cape)
    snout = Tm @ Vector((-.28, -.04, S["torso_len"] + .06))
    ball(snout, (.12, .1, .07), cape)
    limb(snout, Tm @ Vector((-.3, -.38, S["torso_len"] + .02)), .07, .035, cape)
    for k in range(4):
        limb(Tm @ Vector((-.3, -.12 - k * .06, S["torso_len"] - .02)), Tm @ Vector((-.3, -.12 - k * .06, S["torso_len"] - .06)),
             .01, .002, TOOTH(), caps=False, seg=4)
    ball(Tm @ Vector((-.24, -.1, S["torso_len"] + .12)), .02, mat(214, 180, 50, .3, grime=0))


def king_wreck(steel, rust, alu, dark, red):
    # What is left: the hull half under, the cage fallen across it, fire in the
    # engine, the tin crown floating off on its own.
    M = T((0, 0, -.12)) @ R(.08, .22, .4)
    box((0, 0, .14), (1.3, 2.7, .26), steel, M)
    box((.66, 0, .2), (.04, 2.8, .36), rust, M)
    box((0, -.95, .3), (1.25, .07, .3), steel, M, (.9, 0, 0))
    box((0, .95, .4), (.6, .5, .4), dark, M)
    c = Vector((.5, 1.2, .3))
    pts = [M @ (c + Vector((math.cos(k * math.tau / 16) * .9, math.sin(k * math.tau / 16) * .9, 0))) for k in range(16)]
    for a, b in zip(pts, pts[1:] + pts[:1]):
        limb(a, b, .025, .025, alu, caps=False, seg=8)
    fire = mat(255, 130, 40, emit=3.0)
    for k in range(5):
        ball(M @ Vector(((jitter(k) - .5) * .6, .8 + jitter(k, 1) * .4, .5 + jitter(k, 2) * .3)), .1 + jitter(k, 3) * .08, fire)
    puff(M @ Vector((0, .9, .9)), .14)
    tin = mat(200, 168, 70, .35, .85, grime=.45)
    limb((-1.0, -.9, .02), (-1.0, -.9, .09), .135, .14, tin, caps=False, seg=24)
    for k in range(7):
        a = k * math.tau / 7
        p = Vector((-1.0 + math.sin(a) * .135, -.9 - math.cos(a) * .135, .08))
        limb(p, p + Vector((0, 0, .1)), .03, .004, tin, caps=False, seg=5)


GREY_WOOD_A = (116, 108, 94)
# The king has every cel a turning boss has, but poses his own death (the boat
# burns where it sits), so he lists them himself (no fall-over transform).
_WALK = ["w0", "w1", "w2", "w3"]
KING_CELS = ([0, *_WALK, "aim", "fire", "pain", "recover", *["die_%d" % k for k in range(5)], "down"]
             + [(name, step) for name, _ in TURNS for step in (0, *_WALK)])
ACTORS.update({
    "noodler": (maker(NOODLER), NOODLER, (), None),
    "chum_tosser": (maker(CHUMMER), CHUMMER, (), None),
    "gator": (gator, GATOR, (), GROUND),
    "swamp_king": (swamp_king, KING, (), KING_CELS),
})
