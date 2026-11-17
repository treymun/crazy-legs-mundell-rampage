"""The Moonshine Run's own cast (chapter 7, Copperhead Ridge by night): the
revenue men and the Revenue Man himself. Exec'd into enemy_actors.py's
namespace (mat, limb, ball, box, person, cast, AVG, ACTORS and the rest are in
scope).

    revenooer      a federal agent in a dark suit, white shirt and skinny tie,
                   mirrored aviators, a flat-top, the badge on his belt, a snub
                   .38
    still_buster   a raid man in a navy windbreaker with REVENUE across its
                   back, a ball cap, aviators and a red fire axe in both hands
    gas_man        a raid man in an olive field jacket and an old rubber gas
                   mask, a belt of tear gas canisters, one in his hand
    revenue_man    the boss: a big man in a black three-piece suit and a grey
                   fedora, mirrored aviators, a tommy gun with a drum and a
                   fire axe slung on his back; scorched and torn by phase

The people go through person() with a few things it does not know yet: the
held things (a fire axe, a tommy gun, a canister) by a wrapped weapon(), and
the head and body wrapped for what only these men wear (mirrored lenses, a
fedora, a flat-top, a gas mask, a tie, the jacket's lettering). Each wrapper
is a no-op for the rest of the cast. Nothing is traced from another game; no
real agency's badge or lettering is copied (REVENUE is the county's word for
them).
"""

BOSS_PHASES["revenue_man"] = [(2, "revenue_man", ""), (3, "revenue_man", "")]

MIRROR = lambda: mat(176, 196, 222, .06, .95, grime=0)
FRAME = lambda: mat(170, 160, 130, .3, .9, grime=.1)


# ---------------------------------------------------------------- hold tables
# The fire axe in both hands: across the body at the ready, raised over the
# right shoulder to aim, brought down through the swing, high back to wind up.
AXE = {"ready": ((-.22, -.30, -.40), (.55, -.5, .65)), "aim": ((-.30, -.10, .22), (.15, .35, .92)),
       "fire": ((-.12, -.46, -.18), (.15, -.85, -.5)), "recover": ((-.18, -.36, -.42), (.3, -.7, -.6)),
       "pain": ((-.44, -.16, -.30), (-.3, -.3, .9)), "fidget": ((-.25, -.2, -.5), (.2, -.3, -.93)),
       "wind": ((-.34, .14, .28), (-.1, .55, .82))}
TOMMY = {"ready": ((-.22, -.30, -.30), (.6, -.6, .35)), "aim": ((-.20, -.34, -.12), (.35, -1, 0)),
         "fire": ((-.20, -.30, -.10), (.35, -1, .1)), "recover": ((-.21, -.33, -.22), (.45, -.75, .1)),
         "pain": ((-.44, -.16, -.30), (-.3, -.3, .9)), "fidget": ((-.3, -.16, -.46), (.1, -.5, -.85)),
         "wind": ((-.22, -.26, -.18), (.45, -.6, .55))}


# ---------------------------------------------------------------- held things
def _fire_axe(g, d, J, C):
    """A fire axe: a long hickory haft, the red head with its blade and spike."""
    frame = J["frame"]
    haft = mat(150, 104, 58, .7)
    limb(g - d * .16, g + d * .62, .02, .022, haft)
    side = d.cross(Vector((0, 0, 1)))
    side = side.normalized() if side.length > 1e-3 else Vector((1, 0, 0))
    head = g + d * .6
    red = mat(176, 30, 24, .45, .3, grime=.3)
    edge = mat(200, 202, 206, .3, .9, grime=.2)
    box((0, 0, 0), (.04, .11, .13), red, _ms_matrix(head + side * .05, side, d))
    box((0, 0, 0), (.02, .05, .16), edge, _ms_matrix(head + side * .13, side, d))
    limb(head - side * .03, head - side * .16 - d * .02, .02, .006, red)
    if frame == "wind":
        glint(head + side * .15, .06)
    if frame == "fire":
        sparks(head + side * .16 - d * .1, -d, 5, .14)
    return g + d * .3


def _tommy(g, d, J, C):
    """A drum-fed tommy gun: the finned barrel, the receiver, a drum under it,
    a fore grip and a wooden stock."""
    frame = J["frame"]
    up = Vector((0, 0, 1))
    side = d.cross(up)
    side = side.normalized() if side.length > 1e-3 else Vector((1, 0, 0))
    wood = WOOD()
    steel = STEEL()
    limb(g - d * .04, g + d * .2, .04, .038, DARK())
    limb(g + d * .2, g + d * .58, .022, .022, steel, caps=False)
    for k in range(5):
        ring(g + d * (.24 + k * .055), d, .03, .008, steel, n=10)
    disc(g + d * .58, d, .016, .01, BLACK())
    drum = g + d * .12 - up * .1
    disc(drum, side, .09, .07, DARK())
    disc(drum + side * .036, side, .05, .01, steel)
    limb(g + d * .36, g + d * .36 - up * .1, .02, .022, wood)
    limb(g - d * .03, g - d * .34 - up * .05, .038, .05, wood)
    limb(g + d * .02, g + d * .02 - up * .11, .022, .024, wood)
    if frame == "fire":
        flash(g + d * .63, .26, (255, 176, 70))
    if frame == "wind":
        glint(g + d * .58)
    return g + d * .36 - up * .08


def _canister(g, d, J, C):
    """A tear gas canister in the throwing hand, its pin pulled to throw."""
    frame = J["frame"]
    if frame in ("fire", "recover"):
        return None
    olive = mat(88, 98, 60, .6, .3, grime=.3)
    limb(g, g + d * .17, .042, .042, olive)
    disc(g + d * .17, d, .043, .02, mat(196, 160, 48, .5, .5))
    ring(g + d * .2, d.cross(Vector((0, 0, 1))) + Vector((0, 0, .01)), .022, .005, STEEL(), n=8)
    if frame in ("aim", "wind"):
        ball(g + d * .22, .03, mat(214, 214, 204, .95, grime=0))
        ball(g + d * .25 + Vector((0, .02, .06)), .045, mat(206, 206, 198, .95, grime=0))
    return None


def _ms_matrix(center, side, d):
    """A 4x4 at center whose local x runs along `side`, y along the haft, z out."""
    u = Vector(side).normalized()
    v = Vector(d).normalized()
    n = u.cross(v).normalized()
    return Matrix(((u.x, v.x, n.x, center.x), (u.y, v.y, n.y, center.y),
                   (u.z, v.z, n.z, center.z), (0, 0, 0, 1)))


_ms_weapon_base = weapon


def weapon(kind, g, d, J, C):
    if kind == "fire_axe":
        return _fire_axe(g, d, J, C)
    if kind == "tommy":
        return _tommy(g, d, J, C)
    if kind == "canister":
        return _canister(g, d, J, C)
    return _ms_weapon_base(kind, g, d, J, C)


# ---------------------------------------------------------------- wrappers
_ms_head_base = head


def head(Hm, C, J):
    _ms_head_base(Hm, C, J)
    frame = J["frame"]
    if C.get("flattop"):
        hair = mat(*C.get("hair", (62, 46, 32)), .95)
        box((0, .02, .1), (.19, .19, .035), hair, Hm)
    if C.get("fedora"):
        gear("hat")
        felt = mat(*C["fedora"], .85)
        band = mat(26, 22, 22, .8)
        ball((0, 0, .085), (.2, .21, .016), felt, Hm, (.06, 0, 0))
        ball((0, .005, .14), (.115, .125, .085), felt, Hm)
        ball((0, .005, .19), (.09, .1, .03), mat(*[int(v * .8) for v in C["fedora"]], .85), Hm)
        limb((0, .005, .1), (0, .005, .125), .118, .118, band, Hm, caps=False, seg=24)
        gear("")
    if C.get("mirrors"):
        # Mirrored aviators: two teardrop lenses in a thin gold frame.
        gear("shades")
        lens = MIRROR() if not (DAMAGE >= 2 and C.get("cracks")) else mat(120, 130, 150, .4, .7, grime=.2)
        for s in (-1, 1):
            ball((s * .048, -.118, .028), (.04, .012, .032), lens, Hm, (0, s * .15, 0))
            limb((s * .085, -.112, .042), (s * .118, -.02, .04), .005, .005, FRAME(), Hm)
        limb((-.012, -.13, .042), (.012, -.13, .042), .006, .006, FRAME(), Hm)
        if DAMAGE >= 2 and C.get("cracks"):
            limb((.02, -.132, .05), (.07, -.132, .01), .003, .003, WHITE(), Hm)
        gear("")
    if C.get("gasmask"):
        rubber = mat(46, 50, 44, .7, grime=.3)
        ball((0, -.04, -.015), (.118, .118, .132), rubber, Hm)
        for s in (-1, 1):
            c = Hm @ Vector((s * .046, -.135, .03))
            n = (Hm.to_3x3() @ Vector((s * .18, -1, 0))).normalized()
            disc(c, n, .036, .02, mat(120, 116, 104, .4, .7))
            disc(c + n * .008, n, .028, .02, mat(150, 170, 160, .06, .5, grime=0))
        snout = Hm @ Vector((0, -.17, -.08))
        limb(Hm @ Vector((0, -.12, -.05)), snout, .045, .04, rubber)
        disc(snout, (Hm.to_3x3() @ Vector((0, -1, -.4))).normalized(), .05, .06, mat(88, 98, 60, .6, .3))
        limb(Hm @ Vector((-.11, -.02, .02)), Hm @ Vector((.11, -.02, .02)), .012, .012, rubber)
        if frame in ("aim", "fire"):
            ball(snout + Vector((0, -.05, -.02)), .03, mat(200, 200, 196, .95, grime=0))


_ms_body_base = body


def body(Tm, S, C, J):
    _ms_body_base(Tm, S, C, J)
    L, sw, g = S["torso_len"], S["sw"], S["gut"]
    front = -(.17 + .03 * g)
    if C.get("tie"):
        tie = mat(*C["tie"], .7)
        knot = Vector((0, front - .045, L - .02))
        ball(knot, (.024, .016, .022), tie, Tm)
        loose = .04 if DAMAGE >= 1 else 0.
        limb(knot, (loose, front - .05 - .02 * g, L - .3), .02, .03, tie, Tm)
        ball((loose, front - .05 - .02 * g, L - .32), (.03, .012, .02), tie, Tm)
        white = mat(*C["shirt"], .7, grime=.2)
        for s in (-1, 1):
            limb((s * .015, front - .04, L - .01), (s * .06, front - .05, L - .05), .014, .01, white, Tm)
    if C.get("lapels"):
        # The suit coat over the shoulders and the upper back (the shirt shows
        # only at the front, under the tie).
        coat = mat(*C["coat"], .9)
        limb((-sw * .82, .01, L - .02), (sw * .82, .01, L - .02), .092, .092, coat, Tm)
        ball((0, .04, L - .14), (sw * 1.0, .17 + .03 * g, .2), coat, Tm)
        lap = mat(*[int(v * .85) for v in C["coat"]], .8)
        for s in (-1, 1):
            limb((s * .06, front - .045, L - .02), (s * .1, front - .045, L - .28), .028, .012, lap, Tm)
    if C.get("belt_badge"):
        box((sw * .55, front - .02, .1), (.05, .02, .06), mat(214, 168, 64, .35, .85, grime=.2), Tm)
    if C.get("raid"):
        # The windbreaker's lettering across the back, big enough to read.
        ink = mat(*C["raid"], .7, grime=.2)
        back = .19 + .05 * g
        for k in range(7):
            box((-.16 + k * .053, back + .01, L - .14), (.034, .01, .07), ink, Tm)
        box((0, back + .01, L - .24), (.36, .01, .012), ink, Tm)
    if C.get("canisters"):
        olive = mat(88, 98, 60, .6, .3, grime=.3)
        for k in range(4):
            limb((-.16 + k * .1, front - .03, .06), (-.16 + k * .1, front - .03, .16), .032, .032, olive, Tm)
    if C.get("axe_back"):
        # The fire axe slung across his back on its strap.
        haft = mat(150, 104, 58, .7)
        red = mat(176, 30, 24, .45, .3, grime=.3)
        a = Vector((-.2, .22 + .04 * g, .0))
        b = Vector((.22, .22 + .04 * g, L + .14))
        limb(a, b, .022, .022, haft, Tm)
        box((.24, .245 + .04 * g, L + .14), (.16, .04, .11), red, Tm, (0, .7, 0))
        limb((-.1, front, L), (.2, .2, -.0), .014, .014, mat(40, 34, 30, .8), Tm)
    if DAMAGE and C.get("boss_wear"):
        # The fight on him: soot and a torn sleeve seam, then a coat smouldering.
        for x, z in ((-.18, L - .1), (.15, .25), (-.1, .1))[:1 + DAMAGE]:
            char_patch(Tm @ Vector((x, front - .03, z)), .06, None, (math.pi / 2, 0, 0))
        if DAMAGE >= 2:
            smoke(Tm @ Vector((.2, .1, L + .05)), .07, (.15, .4))
            embers(Tm @ Vector((.15, .0, L - .1)), .2, 5, k0=1)


# ---------------------------------------------------------------- the people
SUIT = (34, 34, 40)
SHIRT = (224, 222, 212)
REVENOOER = cast(AVG, gut=.2, px=160, hip_h=.9, shirt=SHIRT, coat=SUIT, pants=SUIT,
                 tie=(24, 22, 26), lapels=1, belt_badge=1, skin=(198, 150, 118), hair=(58, 44, 34),
                 hair_show=True, flattop=1, mirrors=1, boots=(20, 18, 18), boot_top=.12,
                 weapon="pistol", hold=ONE)
STILL_BUSTER = cast(AVG, gut=.35, sw=.25, px=164, limb=(.094, .076, .062), arm=(.072, .06, .048),
                    shirt=(36, 44, 74), coat=(36, 44, 74), pants=(70, 66, 58), raid=(232, 200, 64),
                    hat="cap", hat_c=(36, 44, 74), mirrors=1, beard="moustache", hair=(80, 58, 40),
                    skin=(190, 140, 108), gloves=(80, 62, 44), boots=(30, 26, 24), boot_top=.4,
                    weapon="fire_axe", hold=AXE)
GAS_MAN = cast(AVG, gut=.15, px=158, shirt=(90, 96, 66), coat=(90, 96, 66), pants=(64, 62, 52),
               gasmask=1, hair_show=False, hat="hood", hat_c=(52, 56, 48), canisters=1, belt=(40, 34, 28), gloves=(54, 48, 40),
               boots=(28, 24, 22), boot_top=.42, weapon="canister", hold=THROW)
REVENUE = cast(AVG, gut=.3, sw=.26, px=184, canvas=(1.9, 2.3), hip_h=.96, thigh=.46, shin=.45,
               torso_len=.58, limb=(.1, .082, .066), arm=(.078, .064, .05), upper=.32, fore=.3, head_scale=1.15,
               shirt=SHIRT, coat=(22, 22, 26), coat_long=1, pants=(22, 22, 26),
               tie=(120, 20, 22), lapels=1, belt_badge=1, skin=(204, 156, 124), hair=(120, 116, 110),
               hair_show=True, fedora=(110, 108, 104), mirrors=1, cracks=1, axe_back=1, boss_wear=1,
               boots=(16, 14, 14), boot_top=.12, weapon="tommy", hold=TOMMY, two_hand=1)
REVENUE["down_frame"] = (3.2, 1.6)

ACTORS.update({
    "revenooer": (maker(REVENOOER), REVENOOER, ("fidget",), None),
    "still_buster": (maker(STILL_BUSTER), STILL_BUSTER, (), None),
    "gas_man": (maker(GAS_MAN), GAS_MAN, ("fidget",), None),
    "revenue_man": (maker(REVENUE), REVENUE, (), None),
})
