"""The speedway's own cast (chapter 6, Buzzard Bend race night): the pit mechanic
who throws lug wrenches, the tyre roller, the nitro huffer, the flag man and
the derby champ in his armoured car. Exec'd into enemy_actors.py's namespace
(mat, limb, ball, box, person, cast, AVG, ACTORS and the rest are in scope).

The people go through person() with a few things it does not know yet: the
held things are drawn by a wrapped weapon(), and the head, body and skeleton
are wrapped for what only these folk wear (a cap turned backwards, a horseshoe
of hair, a nitrous bottle and its mask, sleeves knotted at the waist, a crouch
before the throw). Each wrapper is a no-op for the rest of the cast.
"""


def _matrix(center, u, n, v):
    """A 4x4 at center whose local x, y, z run along u, n, v."""
    return Matrix(((u.x, n.x, v.x, center.x), (u.y, n.y, v.y, center.y),
                   (u.z, n.z, v.z, center.z), (0, 0, 0, 1)))


def _anchor(table, J, g):
    """The point a hold table's entries are measured from (hold() adds it)."""
    frame = J["frame"]
    return g - Vector(table[frame if frame in table else "ready"][0])


# ---------------------------------------------------------------- hold tables
LUG = {"ready": ((-.30, -.16, -.50), (0, -.3, 1)), "aim": ((-.38, .18, .14), (.15, .7, .6)),
       "fire": ((-.14, -.52, .0), (.1, -1, -.2)), "recover": ((-.22, -.42, -.30), (0, -.8, -.5)),
       "pain": ((-.42, -.1, -.17), (-.4, -.2, .9)), "fidget": ((-.30, -.20, -.48), (.1, -.4, -.9))}
# The tyre roller's right hand; TYRE_POSE gives the tyre and the left hand, from the same anchor.
TYRE = {"ready": ((-.31, -.44, -.30), (1, 0, 0)), "aim": ((-.38, .24, -.37), (0, -.4, -.9)),
        "fire": ((-.17, -.48, -.40), (0, -1, 0)), "recover": ((-.24, -.38, -.40), (0, -1, 0)),
        "pain": ((-.44, -.16, -.30), (-.3, -.3, .9))}
TYRE_POSE = {"ready": ((0., -.46, -.30), (0, 1, 0), (.31, -.44, -.30)),
             "aim": ((-.30, .02, -.60), (1, .35, 0), (-.20, -.22, -.30)),
             "fire": (None, None, (.17, -.48, -.40)), "recover": (None, None, (.24, -.38, -.40)),
             "pain": (None, None, None)}
FLARE = {"ready": ((-.30, -.22, -.42), (0, -.45, 1)), "aim": ((-.20, -.12, .20), (.3, -.35, .9)),
         "fire": ((-.15, -.56, -.02), (0, -1, .18)), "recover": ((-.24, -.42, -.22), (0, -.8, .4)),
         "pain": ((-.42, -.1, -.17), (-.4, -.2, .9))}
FLAG = {"ready": ((-.30, -.20, -.40), (-.05, -.15, 1)), "aim": ((-.26, -.08, .18), (-.25, -.1, .95)),
        "fire": ((-.30, -.16, -.46), (-.25, -.5, -.8)), "recover": ((-.30, -.22, -.38), (0, -.3, 1)),
        "pain": ((-.42, -.1, -.17), (-.4, -.2, .9))}

CHROME = lambda: mat(200, 202, 208, .22, .95, grime=.12)
RUBBER = lambda: mat(28, 26, 26, .9, grime=.25)


# ---------------------------------------------------------------- held things
def _lug_wrench(g, d, J, C):
    if J["frame"] in ("fire", "recover"):
        return None
    chrome = CHROME()
    side = d.cross(Vector((0, -1, 0)))
    side = side.normalized() if side.length > 1e-3 else Vector((1, 0, 0))
    c = g + d * .21
    for a, b in ((g - d * .05, g + d * .47), (c - side * .26, c + side * .26)):
        limb(a, b, .018, .018, chrome, caps=False)
        axis = (b - a).normalized()
        for k, end in enumerate((a, b)):
            out = axis * (-1 if k == 0 else 1)
            limb(end - out * .01, end + out * .05, .03 - .003 * k, .028 - .003 * k, chrome, caps=False, seg=6)
            disc(end + out * .05, out, .02, .006, DARK())
    ball(c, .026, chrome)
    return None


def _tyre(center, axis, R=.33, W=.22):
    axis = Vector(axis).normalized()
    limb(center - axis * W / 2, center + axis * W / 2, R, R, RUBBER(), caps=False, seg=28)
    for s in (-1, 1):
        face = center + axis * s * (W / 2 + .004)
        disc(face, axis, R * .82, .008, mat(40, 38, 36, .9, grime=.2))
        ring(face + axis * s * .004, axis, R * .66, .016, mat(226, 194, 52, .55, grime=.2), n=24)
        disc(face, axis, R * .5, .02, mat(150, 152, 156, .35, .85, grime=.3))
        disc(face + axis * s * .01, axis, R * .16, .02, DARK())
    # Grooves round the tread.
    for k in (-1, 1):
        ring(center + axis * k * W * .22, axis, R + .002, .01, mat(12, 12, 12, .9, grime=0), n=28)


def _tyre_hold(g, d, J, C):
    frame = J["frame"]
    key = frame if frame in TYRE_POSE else "ready"
    base = _anchor(TYRE, J, g)
    center, axis, left = TYRE_POSE[key]
    if center is not None:
        _tyre(base + Vector(center), Vector(axis))
    return base + Vector(left) if left is not None else None


def _flare(g, d, J, C):
    frame = J["frame"]
    hot = frame in ("aim", "fire")
    limb(g - d * .07, g + d * .22, .024, .024, mat(196, 36, 30, .6, grime=.2), caps=False)
    disc(g - d * .07, d, .026, .01, mat(40, 40, 40))
    ring(g + d * .1, d, .025, .005, mat(230, 220, 190, .6, grime=0), n=10)
    tip = g + d * .25
    ball(tip, .04 if hot else .03, mat(255, 120, 90, emit=3.0))
    sparks(tip, d, 7 if hot else 4, .18 if hot else .11)
    ball(tip + Vector((0, .02, .1)), .035, mat(150, 146, 140, .95, grime=0))
    if frame == "fire":
        flash(tip + d * .06, .24, (255, 110, 80))
    return None


def _flare_pistol(hand, aim, firing):
    orange = mat(232, 118, 34, .5, grime=.25)
    aim = Vector(aim).normalized()
    limb(hand + aim * .02, hand + aim * .21, .03, .028, orange, caps=False)
    disc(hand + aim * .21, aim, .032, .012, DARK())
    limb(hand + aim * .04, hand + aim * .02 + Vector((0, 0, -.1)), .019, .021, orange)
    limb(hand + aim * .06 + Vector((0, 0, .03)), hand + aim * .12 + Vector((0, 0, .035)), .01, .01, DARK())
    if firing:
        flash(hand + aim * .26, .24, (255, 150, 60))
        ball(hand + aim * .42, .04, mat(255, 90, 60, emit=3.0))


def _flag(g, d, J, C):
    frame = J["frame"]
    top = g + d * .5
    limb(g - d * .1, top, .012, .012, mat(150, 112, 62, .8))
    ball(top + d * .01, .022, mat(206, 182, 70, .45, .8, grime=.2))
    u = d.cross(Vector((0, 1, 0)))
    u = u.normalized() if u.length > 1e-3 else Vector((-1, 0, 0))
    n = d.cross(u).normalized()
    green = mat(36, 150, 58, .8, grime=.2)
    hem = mat(230, 226, 214, .8, grime=.2)
    waving = frame == "aim"
    width, tall, strips = .42, .32, 5
    for k in range(strips):
        t = (k + .5) / strips
        flap = (.07 if waving else .025) * math.sin(k * 1.7 + (1.1 if waving else 0.))
        sag = (.05 if waving else .09) * t * t
        c = top - d * (tall / 2 + .015 + sag) + u * (width * t + .01) + n * flap
        box((0, 0, 0), (width / strips + .006, .014, tall), green, _matrix(c, u, n, d))
    # A white hem along the top so the flag reads against a dark yard.
    box((0, 0, 0), (width, .016, .03), hem, _matrix(top - d * .02 + u * (width / 2 + .01), u, n, d))
    # The flare pistol in the left hand: at his side, or up and firing.
    base = _anchor(FLAG, J, g)
    if frame == "fire":
        hand = base + Vector((FLAGMAN["sw"] + .02, -.46, -.06))
        _flare_pistol(hand, (-.12, -1, .06), True)
        return hand
    if frame == "pain" or J["dead"]:
        return None
    hand = Vector((FLAGMAN["sw"] + .08, -.10, FLAGMAN["hip_h"] + .02 - .02 * J["walk"])) + J["offset"]
    _flare_pistol(hand, (0, -.35, -1), False)
    return hand


_weapon_base = weapon


def weapon(kind, g, d, J, C):
    if kind == "lugwrench":
        return _lug_wrench(g, d, J, C)
    if kind == "tyre":
        return _tyre_hold(g, d, J, C)
    if kind == "flare":
        return _flare(g, d, J, C)
    if kind == "flag":
        return _flag(g, d, J, C)
    return _weapon_base(kind, g, d, J, C)


# ---------------------------------------------------------------- wrappers
_skeleton_base = skeleton


def skeleton(S, frame):
    drop = S.get("crouch", {}).get(frame, 0.) if isinstance(frame, str) else 0.
    if not drop:
        return _skeleton_base(S, frame)
    J = _skeleton_base(dict(S, hip_h=S["hip_h"] - drop), frame)
    J["offset"] = J["offset"] + Vector((0, 0, -drop))
    return J


_head_base = head


def head(Hm, C, J):
    _head_base(Hm, C, J)
    frame = J["frame"]
    if C.get("cap_back"):
        cap = mat(*C["cap_back"], .9)
        ball((0, .005, .065), (.12, .128, .095), cap, Hm)
        ball((0, .17, .045), (.088, .085, .013), cap, Hm, (.18, 0, 0))
        ball((0, -.112, .05), (.045, .02, .028), mat(*C.get("hair", (62, 46, 32)), .95), Hm)
    if C.get("big_tache"):
        tache = mat(*C.get("beard_c", (60, 40, 28)), .95)
        for s in (-1, 1):
            ball((s * .05, -.13, -.055), (.062, .032, .03), tache, Hm, (0, s * .25, 0))
            ball((s * .1, -.112, -.09), (.024, .024, .04), tache, Hm)
    if C.get("horseshoe"):
        fringe = mat(*C["horseshoe"], .95)
        for i in range(9):
            t = -1.9 + i * 3.8 / 8
            ball((.112 * math.sin(t), .02 + .1 * math.cos(t), -.005), (.042, .042, .05), fringe, Hm)
    if C.get("chops"):
        chop = mat(*C["chops"], .95)
        for s in (-1, 1):
            ball((s * .102, -.05, -.07), (.036, .05, .075), chop, Hm)
    if C.get("eyes") == "wild":
        for s in (-1, 1):
            ball((s * .046, -.104, .032), (.028, .02, .028), WHITE(), Hm)
            ball((s * .052, -.122, .036 + .006 * s), .009, BLACK(), Hm)
            limb((s * .085, -.112, .078), (s * .016, -.126, .084), .012, .012, mat(*C.get("hair", (62, 46, 32))), Hm)
    if C.get("goggles_up"):
        band = mat(40, 30, 24, .9)
        ball((0, .0, .085), (.118, .126, .022), band, Hm, (-.35, 0, 0))
        up = (Hm.to_3x3() @ Vector((0, -.55, .83))).normalized()
        for s in (-1, 1):
            c = Hm @ Vector((s * .05, -.075, .125))
            disc(c, up, .042, .035, BRASS())
            disc(c + up * .01, up, .03, .035, mat(60, 120, 110, .1, grime=0))
    if C.get("nitro"):
        rubber = mat(30, 30, 32, .8, grime=.2)
        if frame == "aim":
            limb((0, -.12, -.05), (0, -.19, -.06), .05, .036, rubber, Hm)
            mouth = Hm @ Vector((0, -.2, -.06))
        else:
            limb((0, -.09, -.2), (0, -.15, -.24), .046, .034, rubber, Hm)
            mouth = Hm @ Vector((0, -.16, -.25))
        Tm = J["torso"]
        valve = Tm @ Vector((-.07, .2, AVG["torso_len"] + .06))
        over = Tm @ Vector((-.16, .02, AVG["torso_len"] + .1))
        hose = mat(60, 64, 70, .7, grime=.2)
        for a, b in ((valve, over), (over, over.lerp(mouth, .5) + Vector((0, -.03, -.05))),
                     (over.lerp(mouth, .5) + Vector((0, -.03, -.05)), mouth)):
            limb(a, b, .014, .014, hose)


_body_base = body


def body(Tm, S, C, J):
    _body_base(Tm, S, C, J)
    L, sw, g = S["torso_len"], S["sw"], S["gut"]
    front = -(.17 + .03 * g)
    if C.get("patch"):
        box((sw * .45, front - .02, L - .12), (.11, .016, .065), mat(*C["patch"], .8, grime=.2), Tm)
        box((sw * .45, front - .028, L - .12), (.085, .012, .042), mat(232, 226, 210, .8, grime=.15), Tm)
    if C.get("rag"):
        box((.11, .17 + .05 * g + .025, -.06), (.08, .02, .16), mat(*C["rag"], .9), Tm, (0, 0, .2))
    if C.get("nitro"):
        bottle = mat(*C["nitro"], .4, .5, grime=.3)
        limb((-.07, .22, .1), (-.07, .22, L - .04), .072, .072, bottle, Tm)
        ball((-.07, .22, L - .04), .074, bottle, Tm)
        limb((-.07, .22, L), (-.07, .2, L + .06), .022, .022, BRASS(), Tm)
        box((-.07, .295, L - .2), (.07, .01, .09), mat(230, 230, 220, .7, grime=.2), Tm)
        strap = mat(40, 36, 32, .8)
        for s in (-1, 1):
            limb((s * .1, .2, L - .02), (s * .12, front + .02, L - .26), .016, .016, strap, Tm)
    if C.get("suit_tie"):
        suit = mat(*C["suit_tie"], .9)
        for s in (-1, 1):
            limb((s * sw * .9, .05, .1), (s * .05, front - .04, .08), .045, .04, suit, Tm)
            limb((s * .04, front - .05, .07), (s * .09, front - .06, -.2), .04, .034, suit, Tm)
        ball((0, front - .05, .08), .05, suit, Tm)
    if C.get("pads"):
        pad = mat(30, 30, 30, .6, grime=.3)
        for tag in ("R", "L"):
            k = J["knee" + tag]
            ball((k.x, k.y - .05, k.z), (S["limb"][1] * .95, .05, S["limb"][1] * 1.15), pad)
    if C.get("stains"):
        stain = mat(120, 96, 60, .9, grime=.2)
        for x, z in ((-.19, L - .06), (.2, L - .1), (-.17, L - .2)):
            ball((x, front + .02, z), (.035, .012, .028), stain, Tm)


# ---------------------------------------------------------------- the people
PIT_MECHANIC = cast(AVG, gut=.35, sw=.25, px=156, hip_h=.84, thigh=.40, shin=.39, limb=(.094, .076, .062),
                    arm=(.07, .058, .046), shirt=(40, 46, 66), pants=(40, 46, 66), sleeve="rolled",
                    cap_back=(176, 40, 34), hair=(70, 50, 34), beard="moustache", beard_c=(60, 40, 28),
                    big_tache=1, skin=(190, 128, 96), boots=(40, 34, 30), patch=(196, 50, 40),
                    rag=(176, 40, 34), weapon="lugwrench", hold=LUG)
TIRE_ROLLER = cast(AVG, gut=.55, sw=.29, px=166, canvas=(1.8, 2.0), hip_w=.13, stance=.21, depth=.2,
                   limb=(.11, .09, .074), arm=(.09, .076, .06), upper=.32, fore=.30, boot=.066,
                   shirt=(206, 196, 168), pants=(200, 112, 40),
                   bib=(200, 112, 40), sleeve="bare", skin=(196, 128, 94), hair_show=False,
                   horseshoe=(70, 52, 36), chops=(70, 52, 36), pads=1, stains=1, boots=(52, 40, 30),
                   weapon="tyre", hold=TYRE)
NITRO_HUFFER = cast(AVG, lean=.16, gut=.0, sw=.18, hip_w=.09, px=150, limb=(.07, .058, .048),
                    arm=(.05, .044, .036), upper=.31, fore=.30, shirt=(206, 198, 170), pants=(176, 36, 30),
                    sleeve="bare", skin=(198, 156, 126), eyes="wild", hair=(150, 112, 62), beard="stubble",
                    goggles_up=1, nitro=(40, 92, 190), suit_tie=(176, 36, 30), boots=(30, 30, 30),
                    weapon="flare", hold=FLARE)
TIRE_ROLLER["crouch"] = {"aim": .11, "fire": .06}
FLAGMAN = cast(AVG, lean=.08, gut=.1, sw=.2, hip_h=.94, thigh=.45, shin=.44, torso_len=.54, px=178,
               canvas=(1.8, 2.2), limb=(.078, .064, .052), arm=(.058, .05, .04), upper=.32, fore=.30,
               shirt=(214, 210, 198), vest=(30, 30, 32), collar=(214, 210, 198), pants=(46, 44, 42),
               hat="cap", hat_c=(176, 36, 30), eyes="shades", beard="moustache", beard_c=(170, 166, 158),
               hair=(150, 146, 140), skin=(188, 138, 108), boots=(30, 26, 24), weapon="flag", hold=FLAG)


# ---------------------------------------------------------------- the derby champ
DERBY = dict(canvas=(3.1, 1.9), px=150, upright=True, depth=.3)
SHIFT = .1  # the car slides back a little so the ram and the spikes fit the frame


def _tongue(c, u, n, v, length, width, red, orange):
    """A painted flame licking along u from c (n points out of the panel)."""
    box((0, 0, 0), (length, .008, width), red, _matrix(c + u * length / 2, u, n, v))
    box((0, 0, 0), (length * .6, .009, width * .45), orange, _matrix(c + u * length * .32 - n * .002, u, n, v))


def _derby_wheel(center, yaw, spin, side, burnt=False):
    axis = Vector((math.cos(yaw), math.sin(yaw), 0))
    if not burnt:
        limb(center - axis * .11, center + axis * .11, .3, .3, RUBBER(), caps=False, seg=24)
        ring(center + axis * side * .11, axis, .26, .02, mat(20, 20, 20, .9, grime=0), n=20)
    rim = mat(60, 56, 52, .6, .5, grime=.6) if burnt else mat(150, 150, 154, .4, .8, grime=.5)
    disc(center + axis * side * .115, axis * side, .17, .02, rim)
    disc(center + axis * side * .13, axis * side, .07, .02, DARK())
    up = Vector((0, 0, 1))
    across = axis.cross(up).normalized()
    for k in range(5):
        a = spin + k * math.tau / 5
        p = center + axis * side * .135 + (up * math.cos(a) + across * math.sin(a)) * .11
        ball(p, .016, mat(200, 200, 196, .4, .8, grime=.2))


def _derby_car(frame):
    beat = beat_of(frame) if isinstance(frame, str) and frame[:1] == "w" else -1
    dead = isinstance(frame, str) and frame.startswith("die_")
    stage = int(frame[4:]) if dead else -1
    roll = pitch = lift = fwd = 0.
    if beat >= 0:
        roll = (.035, 0., -.035, 0.)[beat]
        pitch = (0., .02, 0., -.02)[beat]
        lift = (0., .012, 0., .012)[beat]
    elif frame == "aim":
        pitch, lift = -.035, .01
    elif frame == "fire":
        pitch, fwd = .06, -.06
    elif frame == "pain":
        roll, pitch = .06, -.02
    elif frame == "recover":
        pitch = .025
    elif dead:
        roll = (.04, -.06, .08, -.05, .03)[stage]
        pitch = (.03, .06, .09, .11, .13)[stage]
        lift = -.015 * stage
    M = T((0, SHIFT + fwd, lift)) @ R(pitch, roll, 0)
    burn = stage + 1 if dead else 0
    crumple = .03 * burn
    primer = mat(116, 116, 108, .7, .2, grime=.7)
    if burn >= 3:
        primer = mat(70, 64, 58, .8, .2, grime=.8)
    rust = mat(126, 66, 36, .85, .3, grime=.6)
    plate = mat(84, 86, 90, .5, .7, grime=.5)
    steel = mat(60, 62, 66, .5, .7, grime=.5)
    red, orange = mat(200, 46, 28, .6, grime=.25), mat(238, 140, 40, .6, grime=.2)
    chrome = mat(186, 188, 194, .25, .9, grime=.25)
    ivory = mat(226, 214, 178, .6, grime=.3)
    fire = mat(255, 104, 30, emit=1.5)
    core = mat(255, 214, 120, emit=2.4)
    hazard = mat(222, 176, 32, .55, .3, grime=.45, stripes=(7.0, (26, 24, 22)))

    # Wheels stay on the ground; the front pair cocks over when it revs for a charge.
    spin = (.0, .6, 1.2, 1.8)[beat] if beat >= 0 else (.9 if frame == "fire" else .3)
    for y, front in ((-.70, True), (.88, False)):
        for s in (-1, 1):
            yaw = (.32 if frame == "aim" and front else 0.) + (.08 * s * (stage % 2) if dead else 0.)
            _derby_wheel(Vector((s * .64, y + SHIFT, .3)), yaw, spin + s, s)

    # The body: a boxy sedan in primer, fenders over the wheels, hood and trunk lids.
    box((0, .05, .52 - crumple), (1.36, 2.26, .52 - crumple), primer, M)
    for y in (-.70, .88):
        for s in (-1, 1):
            box((s * .67, y, .64 - crumple), (.08, .76, .26), primer, M)
            box((s * .712, y, .47), (.012, .7, .3), mat(24, 22, 20, .9, grime=0), M)
    hood_open = .2 if frame == "recover" else (.12 * min(burn, 3) if dead else 0.)
    hinge = Vector((0, -.32, .79 - crumple))
    box((0, -.37, -.0), (1.28, .74, .05), primer, M @ T(hinge) @ R(-hood_open, 0, 0))
    box((0, .95, .80 - crumple), (1.28, .48, .05), primer, M)
    box((0, 1.19, .46), (1.42, .08, .14), chrome, M)
    for s in (-1, 1):
        box((s * .5, 1.2, .64), (.2, .04, .08), mat(200, 30, 26, emit=.6 if frame == "aim" else .2), M)
    # The grille and headlights, and rust where the paint gave up.
    box((0, -1.08, .58), (1.18, .04, .26), DARK(), M)
    box((0, -1.09, .75), (1.3, .03, .07), red, M)
    if burn < 3:
        fwd_n = (M.to_3x3() @ Vector((0, -1, 0))).normalized()
        up = (M.to_3x3() @ Vector((0, 0, 1))).normalized()
        for k, x in enumerate((-.5, -.25, 0., .25, .5)):
            u = (M.to_3x3() @ Vector((.25 * (k - 2) / 2, 0, 1))).normalized()
            _tongue(M @ Vector((x, -1.106, .73)), u, fwd_n, fwd_n.cross(u).normalized(), .12 + .05 * (k % 2),
                    .07, red, orange)
    for k in range(6):
        box((-.48 + k * .19, -1.1, .58), (.03, .03, .22), steel, M)
    for s in (-1, 1):
        c = M @ Vector((s * .48, -1.11, .6))
        disc(c, M.to_3x3() @ Vector((0, -1, 0)), .08, .03, mat(232, 222, 168, emit=.9 if frame == "aim" else .35))
    for x, y, z, sx, sz, side in ((.69, -.2, .44, .3, .14, 1), (-.69, .6, .5, .36, .12, -1),
                                  (.69, .9, .62, .2, .1, 1), (-.69, -.75, .42, .22, .12, -1)):
        box((x + side * .004, y, z), (.01, sx, sz), rust, M)
    box((.2, .9, .826), (.4, .25, .01), rust, M)

    # Crude flames up the hood and down both sides, and the double-nought on the doors.
    if burn < 3:
        hood_m = M @ T(hinge) @ R(-hood_open, 0, 0)
        for k, x in enumerate((-.45, -.18, .1, .38)):
            ang = (-.25, .1, -.1, .22)[k]
            u = (hood_m.to_3x3() @ Vector((math.sin(ang), 1, 0))).normalized()
            n = (hood_m.to_3x3() @ Vector((0, 0, 1))).normalized()
            _tongue(hood_m @ Vector((x, -.7, .03)), u, n, n.cross(u).normalized(), .5 + .1 * (k % 2), .07,
                    red, orange)
        for s in (-1, 1):
            n = (M.to_3x3() @ Vector((s, 0, 0))).normalized()
            for k, z in enumerate((.52, .64, .74)):
                u = (M.to_3x3() @ Vector((0, 1, .22 * (k - 1)))).normalized()
                _tongue(M @ Vector((s * .716, -1.06 + .05 * k, z)), u, n, u.cross(n).normalized() * s,
                        .66 - .1 * k, .09, red, orange)
            c = M @ Vector((s * .69, .2, .58))
            disc(c, n, .2, .012, mat(222, 216, 198, .7, grime=.35))
            for dy in (-.075, .075):
                ring(c + n * .012 + (M.to_3x3() @ Vector((0, dy, 0))), n, .055, .015, BLACK(), n=14)

    # The armoured cabin: plates welded over the glass, the driver behind a slot.
    cab = M @ T((0, .18, 0))
    for s in (-1, 1):
        box((s * .57, 0, 1.03 - crumple), (.04, .9, .42 - crumple), plate, cab)
    box((0, .45, 1.03 - crumple), (1.12, .04, .42 - crumple), plate, cab)
    box((0, .055, 1.25 - 2 * crumple), (1.14, .83, .05), plate, cab)
    lean = R(-.42, 0, 0)
    box((0, 0, 0), (1.12, .05, .2), plate, cab @ T((0, -.479, .931 - crumple)) @ lean)
    box((0, 0, 0), (1.12, .05, .15), plate, cab @ T((0, -.379, 1.154 - crumple)) @ lean)
    for x in (-.4, -.2, 0., .2, .4):
        for y, z in ((-.505, .93), (-.405, 1.16)):
            ball((x, y, z - crumple), .016, steel, cab)
    for s in (-1, 1):
        for y in (-.3, 0., .3):
            for z in (.88, 1.18):
                ball((s * .595, y, z - crumple), .016, steel, cab)
    if burn < 4:
        helmet = mat(176, 34, 30, .35, .2, grime=.2)
        ball((0, -.18, 1.06 - crumple), (.13, .14, .14), helmet, cab)
        box((0, -.3, 1.09 - crumple), (.04, .03, .2), mat(232, 228, 214, .5, grime=.1), cab, (-.4, 0, 0))
        ball((0, -.27, 1.04 - crumple), (.09, .05, .07), mat(186, 124, 92, .75), cab)
        box((0, -.33, 1.065 - crumple), (.17, .02, .035), BLACK(), cab)
        for z in (.99, 1.02):
            limb((-.09, -.33, z - crumple), (.09, -.33, z - crumple), .008, .008, mat(150, 150, 150, .4, .8), cab)

    # Chains across the door seams.
    for s in (-1, 1):
        for k in range(8):
            p = M @ Vector((s * .705, -.28 + k * .1, .78 - .03 * math.sin(k * .8) - crumple))
            normal = (M.to_3x3() @ (Vector((0, 1, 0)) if k % 2 else Vector((0, 0, 1)))).normalized()
            ring(p, normal, .03, .008, mat(70, 72, 76, .45, .85, grime=.4), n=8)

    # Exhaust stacks through the hood, the rebar cage on the roof.
    for s in (-1, 1):
        base = M @ Vector((s * .44, -.62, .8 - crumple))
        top = M @ Vector((s * .44, -.62, 1.3 - crumple))
        limb(base, top, .045, .05, mat(120, 92, 70, .5, .7, grime=.6), caps=False)
        disc(top, Vector((0, 0, 1)), .052, .02, BLACK())
        if frame == "aim" or (dead and stage >= 1):
            limb(top, top + Vector((0, .04, .38)), .07, .01, fire, caps=False)
            limb(top, top + Vector((0, .02, .24)), .035, .006, core, caps=False)
        elif frame == "fire":
            limb(top, top + Vector((0, .3, .2)), .06, .01, fire, caps=False)
        elif beat >= 0 or frame == 0:
            k = beat if beat >= 0 else 0
            ball(top + Vector((0, .05 * k, .12 + .08 * ((k + (s > 0)) % 3))), .05 + .01 * k,
                 mat(120, 116, 110, .95, grime=0))
    if burn < 4:
        board = cab @ T((0, .12, 1.36 - 2 * crumple))
        box((0, 0, 0), (.62, .03, .18), mat(222, 216, 198, .7, grime=.35), board)
        for s in (-1, 1):
            for side in (-1, 1):
                ring((s * .1, side * .018, 0), (0, 1, 0), .055, .016, red, n=14, M=board)
    rebar = mat(98, 64, 42, .8, .3, grime=.5)
    corners = [Vector((x, y, 1.27 - 2 * crumple)) for x in (-.5, .5) for y in (-.25, .6)]
    tops = [c + Vector((0, 0, .15)) for c in corners]
    for c, t in zip(corners, tops):
        limb(cab @ c, cab @ t, .014, .014, rebar)
    for a, b in ((0, 1), (2, 3), (0, 2), (1, 3), (0, 3)):
        limb(cab @ tops[a], cab @ tops[b], .014, .014, rebar)

    # The push-bar ram: I-beams, spikes, the steer horns over it.
    bent = R(0, 0, .05 * burn)
    ram = M @ bent
    for z in (.44, .76):
        box((0, -1.25, z), (1.62, .05, .1), hazard if burn < 3 else steel, ram)
        box((0, -1.22, z), (1.62, .04, .1), steel, ram)
        box((0, -1.24, z + .055), (1.62, .12, .02), steel, ram)
        box((0, -1.24, z - .055), (1.62, .12, .02), steel, ram)
    for x in (-.55, 0., .55):
        box((x, -1.18, .6), (.07, .12, .44), steel, ram)
    for x, z in ((-.6, .78), (-.2, .78), (.2, .78), (.6, .78), (-.4, .46), (.4, .46)):
        limb(ram @ Vector((x, -1.29, z)), ram @ Vector((x, -1.44, z)), .034, .003, chrome, caps=False, seg=10)
    ball((0, -1.3, .9), (.12, .05, .1), ivory, ram)
    for s in (-1, 1):
        ball((s * .045, -1.345, .92), .018, BLACK(), ram)
        pts = [Vector((s * .08, -1.29, .92)), Vector((s * .36, -1.31, .95)),
               Vector((s * .6, -1.34, 1.04)), Vector((s * .74, -1.38, 1.17))]
        for k, (a, b) in enumerate(zip(pts, pts[1:])):
            limb(ram @ a, ram @ b, .046 - .012 * k, .034 - .012 * k,
                 mat(70, 50, 34, .7) if k == 2 else ivory)

    # What each frame adds: dust when it revs or lurches, sparks and steam when hurt, fire as it dies.
    if frame in ("aim", "fire"):
        dust = mat(168, 140, 104, .95, grime=0)
        for k, s in enumerate((-1, 1, -1, 1)):
            at = Vector((s * (.74 + .1 * (k // 2)), 1.0 + SHIFT + .14 * (k // 2), .12))
            for x, y, z, r in ((0, 0, 0, 1.), (.6 * s, .1, .4, .8), (-.3 * s, .3, .7, .7), (.2 * s, -.2, .9, .55)):
                ball(at + Vector((x, y, z)) * (.16 + .03 * k), (.16 + .03 * k) * r, dust)
    if frame == "pain":
        sparks(M @ Vector((0, -1.12, .62)), (0, -1, .3), 12, .5)
        puff(M @ Vector((.15, -1.2, .7)), .13)
    if frame == "recover":
        puff(M @ Vector((0, -.7, .95)), .16, True)
    if dead:
        for k in range(burn + 1):
            x = (-.3, .25, -.05, .4, -.45, .1)[k]
            y = (-.6, -.3, .2, .6, -.1, .9)[k]
            at = M @ Vector((x, y, 1.0 if y < -.25 or y > .7 else 1.3))
            tall = .22 + .06 * burn
            # A ragged fire: a few tongues leaning every way, a hot core low in them.
            for j in range(3):
                lean = Vector(((jitter(k, j) - .5) * .25, (jitter(k, j + 3) - .5) * .2, 0))
                reach = tall * (.65 + .5 * jitter(k, j + 6))
                limb(at + lean * .3, at + lean + Vector((0, 0, reach)), .07, .006, fire, caps=False, seg=8)
            limb(at, at + Vector((0, 0, tall * .45)), .06, .005, core, caps=False)
        if stage >= 2:
            sparks(M @ Vector((0, -1.0, .8)), (0, -.5, 1), 6 + stage * 2, .45)


def _derby_hulk():
    """The champ's car burnt out: flattened onto its rims, turned to show its length."""
    M = R(0, 0, math.radians(72)) @ T((0, .05, 0))
    char = mat(44, 40, 38, .85, .3, grime=.6)
    rust = mat(110, 56, 30, .85, .3, grime=.6)
    steel = mat(52, 52, 54, .6, .6, grime=.6)
    for y, front in ((-.72, True), (.86, False)):
        for s in (-1, 1):
            c = M @ Vector((s * .62, y, .17))
            yaw = math.radians(72) + (.2 * s if front else 0.)
            _derby_wheel(Vector((c.x, c.y, .17)), yaw, s, s, burnt=True)
    box((0, .05, .32), (1.36, 2.3, .26), char, M, (0, .03, 0))
    box((0, .2, .54), (1.1, .9, .16), char, M, (.04, -.06, .02))
    box((0, -.75, .47), (1.2, .7, .04), rust, M, (-.12, .05, 0))
    box((0, .95, .47), (1.24, .46, .04), char, M, (.05, 0, .03))
    for x, y in ((-.3, -.2), (.35, .55), (-.4, .8), (.2, -.6)):
        box((x, y, .63), (.22, .2, .02), rust, M, (0, 0, .4))
    box((0, -1.22, .36), (1.5, .06, .1), steel, M, (0, 0, .12))
    box((0, -1.2, .58), (1.3, .06, .1), steel, M, (0, .25, .2))
    for s in (-1, 1):
        limb(M @ Vector((s * .1, -1.26, .62)), M @ Vector((s * .5, -1.3, .76)), .04, .02,
             mat(150, 140, 120, .7, grime=.6))
    limb(M @ Vector((.3, -.6, .5)), M @ Vector((.36, -.62, .78)), .045, .04, steel, caps=False)
    for k in range(5):
        ball(M @ Vector((-.4 + .2 * k, .3 + .1 * (k % 2), .64)), .03, mat(255, 130, 50, emit=1.6))


def derby_champ(frame):
    if frame == "down":
        _derby_hulk()
    else:
        _derby_car(frame)


ACTORS.update({
    "pit_mechanic": (maker(PIT_MECHANIC), PIT_MECHANIC, ("fidget",), None),
    "tire_roller": (maker(TIRE_ROLLER), TIRE_ROLLER, (), None),
    "nitro_huffer": (maker(NITRO_HUFFER), NITRO_HUFFER, (), None),
    "flagman": (maker(FLAGMAN), FLAGMAN, (), None),
    "derby_champ": (derby_champ, DERBY, (), None),
})
