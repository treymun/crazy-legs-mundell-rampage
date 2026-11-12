"""The mothership's crew and the one who runs it (chapter 7): a grey drone in
county overalls with a cattle prod, a tin guard behind a pickup's tailgate
with a bug zapper the size of a mailbox, a floating probe with one eye, and
Maw Glorb, the Alien Sheriff's mother, in her housecoat and curlers, a
rolling pin in one hand and a salon hair dryer that shoots in the other.
Loaded by enemy_actors.py with the other actors_<chapter>.py (exec'd into its namespace, so mat, ball, limb,
box, ring, disc, flash, skeleton, person, cast and the rest are in scope).
Everything is modelled here from scratch."""

_SHIP_BASE_WEAPON = weapon


def weapon(kind, g, d, J, C):
    """The crew's own tools, then whatever enemy_actors.py already draws."""
    frame = J["frame"]
    up = Vector((0, 0, 1))
    hot = frame in ("aim", "fire")
    if kind == "prod":
        # A yellow cattle prod off somebody's feedlot, two prongs at the end.
        limb(g - d * .12, g + d * .52, .02, .016, mat(196, 166, 52, .5, .2, grime=.4))
        limb(g - d * .15, g + d * .08, .033, .033, mat(36, 36, 36, .6))
        side = d.cross(up).normalized() * .026
        for s in (-1, 1):
            limb(g + d * .52 + side * s, g + d * .63 + side * s, .009, .006, STEEL())
        if hot:
            ball(g + d * .66, .036, mat(150, 220, 255, emit=2.6))
        if frame == "fire":
            flash(g + d * .68, .2, (150, 220, 255))
        return None
    if kind == "zapper":
        # A bug zapper the size of a mailbox: a lit grid, a dish at the muzzle.
        shell = mat(120, 126, 120, .45, .7, grime=.45)
        limb(g - d * .16, g + d * .46, .075, .065, shell)
        grid = mat(150, 120, 255, emit=2.4 if hot else .7)
        for k in range(4):
            ring(g + d * (.04 + k * .1), d, .09, .009, grid, n=12)
        disc(g + d * .5, d, .11, .03, BRASS())
        limb(g + d * .02, g + d * .02 + Vector((0, 0, -.13)), .026, .03, DARK())
        if frame == "fire":
            flash(g + d * .58, .28, (170, 140, 255))
        return g + d * .3
    return _SHIP_BASE_WEAPON(kind, g, d, J, C)


# ---------------------------------------------------------------- grey drone
DRONE = cast(AVG, lean=.12, gut=.05, hip_w=.1, sw=.2, px=150, canvas=(1.6, 1.9), limb=(.07, .058, .048),
             arm=(.05, .042, .036), skin=(150, 160, 140), eyes="alien", shirt=(150, 120, 90), plaid=1,
             bib=(70, 92, 124), pants=(70, 92, 124), sleeve="rolled",
             gloves=(150, 160, 140), boots=(50, 40, 32), weapon="prod", hold=ONE)


def drone(frame):
    """A grey in a dead man's overalls, a feed-store cap jammed down over its dome."""
    person(DRONE, frame)
    Hm = skeleton(DRONE, frame)["head"]
    cap = mat(64, 96, 60, .9)
    ball((0, .01, .13), (.165, .178, .1), cap, Hm)
    ball((0, -.2, .1), (.12, .12, .016), cap, Hm, (-.18, 0, 0))
    box((0, -.165, .17), (.09, .01, .04), mat(230, 220, 190, grime=.3), Hm, (-.4, 0, 0))


# ---------------------------------------------------------------- tin guard
GUARD = cast(AVG, lean=.04, gut=.4, hip_h=.98, hip_w=.15, stance=.22, thigh=.47, shin=.46, torso_len=.58,
             sw=.28, upper=.33, fore=.31, px=196, canvas=(2.1, 2.3), depth=.22, limb=(.11, .09, .074),
             arm=(.082, .07, .056), skin=(120, 134, 110), eyes="visor", mask_c=(96, 98, 92),
             shirt=(70, 74, 66), pants=(64, 66, 60), armor=(156, 144, 116), bands=(92, 80, 64),
             belt=(40, 34, 28), gloves=(70, 60, 48), boots=(40, 38, 36), boot_top=.5, kneepads=1,
             weapon="zapper", hold=TWO)


def guard(frame):
    """A grey in riveted tin with a pickup's tailgate for a shield; it swings the
    tailgate aside to shoot."""
    person(GUARD, frame)
    J = skeleton(GUARD, frame)
    if J["dead"]:
        return
    Tm = J["torso"]
    open_up = frame in ("aim", "fire")
    at = (.34, -.36, .26) if not open_up else (.5, -.06, .28)
    turn = (0, 0, 0) if not open_up else (0, 0, -1.15)
    if frame == "pain":
        at, turn = (.4, -.3, .2), (.3, .2, -.4)
    gate = mat(150, 52, 36, .5, .3, grime=.75)
    box(at, (.64, .05, .8), gate, Tm, turn)
    box((at[0], at[1] - .03, at[2] + .3), (.6, .02, .06), mat(176, 180, 184, .25, .9, grime=.4), Tm, turn)
    box((at[0], at[1] - .03, at[2] - .32), (.6, .02, .05), mat(176, 180, 184, .25, .9, grime=.4), Tm, turn)
    for k in range(3):
        ball((at[0] - .2 + k * .2, at[1] - .03, at[2] + .05 - (k % 2) * .12), .03, mat(90, 40, 30, grime=.5), Tm)


# ---------------------------------------------------------------- floating probe
PROBE = dict(canvas=(1.2, 1.2), px=76)


def probe(frame):
    """A chrome ball with one eye, a rotor for a hat and a probe hanging off a hose."""
    phase = frame if isinstance(frame, int) else 0
    hot = frame in ("aim", "fire")
    chrome = mat(176, 180, 184, .25, .9, grime=.35)
    tilt = R(.45, 0, .35) if frame == "pain" else R(-.22 if hot else 0, 0, 0)
    M = T((0, 0, .62)) @ tilt
    ball((0, 0, 0), (.28, .28, .26), chrome, M)
    ball((0, 0, -.02), (.29, .29, .05), mat(70, 74, 72, .5, .7), M)
    ball((0, -.19, .02), (.17, .1, .17), WHITE(), M)
    ball((0, -.265, .02), (.09, .05, .09), mat(255, 90, 60, emit=2.6 if hot else 1.0), M)
    ball((0, -.3, .02), (.04, .03, .04), BLACK(), M)
    limb((0, 0, .24), (0, 0, .36), .02, .02, DARK(), M)
    box((0, 0, .37), (.62, .06, .012), mat(200, 190, 150, .5, grime=.3), M, (0, 0, phase * .9 + .3))
    hose = mat(40, 40, 40, .6)
    sway = .07 * phase
    limb((0, .05, -.24), (sway, .09, -.4), .02, .018, hose, M)
    limb((sway, .09, -.4), (sway, .09, -.58), .036, .004, chrome, M)
    for s in (-1, 1):
        limb((s * .14, 0, .2), (s * .25, .02, .34), .008, .006, DARK(), M)
        ball((s * .25, .02, .34), .026, mat(120, 255, 160, emit=2.0), M)
    if frame == "aim":
        ring(M @ Vector((0, -.29, .02)), M.to_3x3() @ Vector((0, 1, 0)), .13, .014, mat(120, 255, 160, emit=2.6), n=16)
    if frame == "fire":
        limb(M @ Vector((0, -.3, .02)), M @ Vector((0, -.62, -.08)), .05, .12, mat(140, 255, 180, emit=2.2), caps=False)
        flash(M @ Vector((0, -.34, .02)), .2, (140, 255, 180))


# ---------------------------------------------------------------- Maw Glorb
MAW = dict(lean=.05, hip_h=1.72, hip_w=.3, stance=.46, stride=.3, ankle=.13, thigh=.86, shin=.84,
           torso_len=1.12, neck=.22, head_fwd=-.04, sw=.62, upper=.72, fore=.68, boot=.14, bow=.12,
           canvas=(3.8, 4.9), px=300, depth=.55, head_scale=2.5, down_frame=(7.4, 3.0), down_x=-1.6)
DYING = ("die_0", "die_1", "die_2", "die_3", "die_4", "down")


def maw(frame, bare=False):
    """Maw Glorb. Bare: the housecoat burnt off her, a tin girdle of power cells
    under it, the curlers gone and the dome cracked and glowing."""
    S = MAW
    J = skeleton(S, frame)
    Tm, Hm = J["torso"], J["head"]
    hot = frame in ("aim", "wind", "fire")
    # Phase two (her housecoat's on fire) and, out of it, the beaten bare set.
    burning = DAMAGE and not bare and not J["dead"]
    grey = mat(150, 166, 128, .55, grime=.35)
    eye = mat(8, 10, 12, .08, grime=0)
    iris = mat(255, 60, 40, emit=2.6 if (hot or bare) else 1.2)
    coat = mat(206, 120, 150, .9, plaid=2.2, grime=.4)
    coat_dark = mat(150, 80, 104, .9)
    ruffle = mat(236, 230, 214, .8, grime=.2)
    tin = mat(160, 150, 124, .45, .7, grime=.55)
    cell = mat(120, 255, 160, emit=2.2)
    slipper = mat(240, 150, 190, .95, grime=.25)
    L = S["torso_len"]
    # The body: a grey pear, a housecoat over it to the knee, a ruffled collar.
    ball((0, 0, .1), (.6, .48, .45), grey, Tm)
    ball((0, -.04, .55), (.66, .5, .55), grey, Tm)
    if not bare:
        ball((0, -.02, -.25), (.78, .6, .75), coat, Tm)
        ball((0, -.04, .5), (.72, .55, .62), coat, Tm)
        for s in (-1, 1):
            ball((s * .26, -.4, .66), (.26, .2, .22), coat, Tm)
            box((s * .4, -.5, -.05), (.24, .06, .22), coat_dark, Tm, (0, 0, s * .2))
        ball((0, -.03, .1), (.7, .56, .07), coat_dark, Tm)
        for k in range(14):
            a = k / 14 * math.tau
            ball((math.cos(a) * .26, math.sin(a) * .2 - .02, L - .02), .07, ruffle, Tm)
        box((.42, -.56, -.02), (.12, .03, .14), WHITE(), Tm, (0, 0, .2))
    else:
        # The girdle: tin hoops riveted round her, cells glowing in it.
        for z, r in ((-.05, .64), (.2, .66), (.45, .7), (.7, .66)):
            ball((0, -.03, z), (r, r * .78, .07), tin, Tm)
        for k in range(8):
            a = -2.2 + k * .63
            limb((math.sin(a) * .62, -math.cos(a) * .5, .28), (math.sin(a) * .62, -math.cos(a) * .5, .4), .05, .05, cell, Tm)
        ball((0, -.02, -.3), (.6, .5, .32), mat(70, 60, 50, .8), Tm)
    limb((0, 0, L - .06), (0, -.02, L + .2), .2, .17, grey, Tm)
    # The head: the boy's dome, bigger; cat-eye glasses on a chain, lipstick.
    ball((0, .03, .07), (.21, .225, .21), grey, Hm)
    ball((0, -.03, -.07), (.13, .14, .13), grey, Hm)
    ball((0, -.065, -.16), (.06, .065, .055), grey, Hm)
    for s in (-1, 1):
        ball((s * .088, -.145, -.01), (.088, .044, .056), eye, Hm, (0, s * .6, 0))
        ball((s * .098, -.18, -.002), (.032, .014, .022), iris, Hm, (0, s * .6, 0))
    ball((0, -.165, -.15), (.04, .016, .016 if frame not in ("pain", "fire") else .03), mat(196, 30, 40, .4), Hm)
    if not bare:
        frames_c = mat(240, 120, 200, .4, .3, grime=.1)
        for s in (-1, 1):
            ring(Hm @ Vector((s * .09, -.19, 0)), Hm.to_3x3() @ Vector((0, 1, 0)), .07, .008, frames_c, n=14)
            limb((s * .15, -.19, .02), (s * .2, -.2, .07), .01, .006, frames_c, Hm)
            ball((s * .2, -.2, .07), .012, mat(255, 255, 240, emit=1.2), Hm)
        limb((-.16, -.19, -.01), (0, -.24, -.3), .004, .004, frames_c, Hm)
        limb((0, -.24, -.3), (.16, -.19, -.01), .004, .004, frames_c, Hm)
        # Curlers: soup cans and pink rollers round the crown under a hairnet.
        for k in range(9):
            a = k / 9 * math.pi * 1.6 - math.pi * .8
            at = Vector((math.sin(a) * .17, .06 + math.cos(a) * .08, .2 + .05 * math.cos(a)))
            roll = mat(176, 180, 184, .3, .9) if k % 2 else mat(240, 150, 190, .7)
            if burning and k == 1:
                # shaken loose: one hangs by a strand past her ear
                at = Vector((-.25, .0, -.08))
                limb(Vector((-.16, .04, .14)), at, .005, .005, mat(80, 60, 50, .9, grime=0), Hm)
            elif burning and k == 6:
                at = Vector((.34, -.12, .36))  # and one flies off
            limb(at + Vector((-.05, 0, 0)), at + Vector((.05, 0, 0)), .05, .05, roll, Hm)
        ring(Hm @ Vector((0, .04, .17)), Hm.to_3x3() @ Vector((0, 0, 1)), .2, .006, mat(80, 60, 50, .9, grime=0), n=20)
    else:
        for k in range(5):
            a = k * 1.3
            limb((math.sin(a) * .12, .02, .27), (math.sin(a + .7) * .19, .1, .1), .008, .006, cell, Hm)
    # The feelers, the family's, through the net.
    for s in (-1, 1):
        knee = Vector((s * .12, 0, .38))
        tip = Vector((s * .22, -.02, .5))
        limb((s * .06, .03, .22), knee, .016, .013, grey, Hm)
        limb(knee, tip, .013, .01, grey, Hm)
        ball(tip, .04, iris if bare else mat(70, 255, 100, emit=1.4), Hm)
    # Right hand: the hair dryer that shoots. Left: the rolling pin.
    dryer = {"ready": ((-.86, -.45, 2.25), (.2, -.9, -.4)), "aim": ((-.95, -1.0, 3.1), (.35, -1, -.12)),
             "fire": ((-.9, -.95, 3.05), (.35, -1, .05)), "recover": ((-.84, -.7, 2.6), (.2, -.9, -.3)),
             "pain": ((-1.1, -.2, 2.9), (-.4, -.2, .9))}
    pin = {"ready": ((.95, -.4, 2.1), (0, -.3, -1)), "aim": ((.7, -.4, 4.15), (-1, -.1, .15)),
           "fire": ((.8, -1.2, 2.2), (-1, -.3, -.2)), "recover": ((.9, -.8, 2.4), (-1, -.2, -.5)),
           "pain": ((1.15, -.2, 3.0), (.2, -.2, 1))}
    g, d = gun_hold(dryer, J)
    p, q = gun_hold(pin, J)
    hands = {"R": g, "L": p}
    if J["dead"]:
        hands = flung(J, S, 1.6)
    else:
        shell = mat(240, 160, 200, .4, .2, grime=.35) if not bare else mat(130, 130, 136, .35, .8, grime=.45)
        limb(g - d * .1, g + d * .55, .16, .14, shell)
        limb(g + d * .55, g + d * .75, .14, .2, shell, caps=False)
        disc(g + d * .76, d, .2, .03, mat(60, 60, 60, .5, .6))
        disc(g + d * .78, d, .15, .02, mat(255, 120, 60, emit=2.6 if hot else .9))
        limb(g, g + Vector((0, 0, -.38)) - d * .05, .07, .08, shell)
        limb(g + Vector((0, 0, -.38)), g + Vector((.1, .3, -.6)), .02, .02, BLACK(), caps=False)
        if frame == "fire":
            flash(g + d * .9, .7, (255, 140, 70))
        wood = mat(176, 130, 80, .7, grime=.35) if not bare else mat(120, 90, 60, .7, grime=.6)
        a, b = p - q * 1.1, p + q * .2
        limb(a, b, .17, .17, wood, caps=False, seg=20)
        disc(a, q, .17, .02, mat(150, 110, 66, .7))
        limb(b, b + q * .3, .05, .05, wood)
        limb(a, a - q * .3, .05, .05, wood)
        if bare:
            for k in range(6):
                ring(a.lerp(b, .1 + k * .16), q, .18, .012, STEEL(), n=12)

    def sleeve(tag, sh, el, hand):
        if bare:
            ball(sh, .2, tin)
            limb(sh, el, .17, .14, grey)
        else:
            ball(sh, .24, coat)
            limb(sh, el, .22, .2, coat)
            limb(el.lerp(sh, .1), el.lerp(hand, .2), .2, .18, ruffle)
        limb(el, hand, .14, .11, grey)
        ball(hand, (.13, .13, .14), grey)
        fingers(hand, el, grey, r=.04, spread=.08, length=.24)

    arms(S, J, hands, sleeve)
    legs(S, J, grey, (.22, .17, .13), slipper)
    for tag in ("R", "L"):
        foot = J["foot" + tag]
        ball((foot.x, foot.y - .12, foot.z - S["ankle"] + .1), (.2, .3, .14), slipper)
        ball((foot.x, foot.y - .3, foot.z - S["ankle"] + .16), .1, mat(255, 210, 230, .95, grime=.1))
    if burning:
        # HOUSECOAT'S ON FIRE: the hem and a shoulder alight, scorch spreading,
        # smoke off her back, one lens starred
        for k, (x, y, z, r) in enumerate(((-.42, -.52, -.9, .62), (.3, -.56, -.92, .5), (.72, -.2, -.72, .46),
                                            (-.52, -.38, .74, .4))):
            flames(Tm @ Vector((x, y, z)), r, 4, k0=k * 3)
        smoke(Tm @ Vector((-.3, .3, 1.0)), .14, (-.4, .5))
        embers(Tm @ Vector((0, -.4, -.4)), .9, 10)
        crack([(.04, -.2, .03), (.09, -.205, -.01), (.07, -.205, -.05), (.12, -.2, -.03)], Hm, WHITE(), .005)
    if bare and DAMAGE == 2 and not J["dead"]:
        # beaten: two curlers still snarled in her feelers, the housecoat's last
        # charred rags hanging off the girdle, cells shorting, the dome split
        for at, roll in ((Vector((-.2, .02, .2)), mat(240, 150, 190, .7)), (Vector((.16, .1, .26)), mat(176, 180, 184, .3, .9))):
            limb(at + Vector((-.05, 0, -.02)), at + Vector((.05, 0, .02)), .05, .05, roll, Hm)
        rag = mat(70, 44, 52, .95, plaid=2.2, grime=.6)
        rags(Tm @ Vector((0, -.5, -.36)), Tm.to_3x3() @ Vector((0, -1, 0)), 7, .5, .9, rag, k0=1)
        rags(Tm @ Vector((0, .45, -.36)), Tm.to_3x3() @ Vector((0, 1, 0)), 5, .4, .8, rag, k0=9)
        crack([(-.05, -.12, .2), (.02, -.17, .12), (-.03, -.2, .05), (.04, -.21, -.02)], Hm, mat(255, 70, 40, emit=2.6), .012)
        sparks(Tm @ Vector((.5, -.4, .34)), (.6, -.6, .3), 9, .5)
        sparks(Tm @ Vector((-.55, -.3, .34)), (-.6, -.6, .3), 7, .45)
        smoke(Tm @ Vector((.2, .2, .9)), .14, (.4, .5))


def maw_cels(frame):
    maw(frame, frame in DYING)


def maw_bare(frame):
    maw(frame, True)


# The bare set needs no falling cels: she falls in the first set's name.
BARE_CELS = [0, "w0", "w1", "w2", "w3", "aim", "fire", "pain", "recover"]
BARE_CELS += [(name, step) for name, _ in TURNS for step in (0, "w0", "w1", "w2", "w3")]

SHIP_ACTORS = {
    "drone": (drone, DRONE, (), None),
    "tin_guard": (guard, GUARD, (), None),
    "probe": (probe, PROBE, (), FLYER),
    "maw": (maw_cels, MAW, (), None),
    "maw_bare": (maw_bare, MAW, (), BARE_CELS),
}
ACTORS.update(SHIP_ACTORS)
