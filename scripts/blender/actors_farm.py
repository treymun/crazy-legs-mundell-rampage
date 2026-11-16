"""The county's livestock (critters you can shove around, features/critters.gd),
exec'd by enemy_actors.py into its own namespace after ACTORS is made, so
ball, limb, mat, T, R, Vector and the rest are in scope. Built from scratch:
nothing is traced from another game. The mule's are cels only (it stays a
picture in the 3D view, like the chickens and hogs).

    cow   a Holstein in black and white patches: pink nose and udder, stubby
          horns, a yellow ear tag and a cowbell on a strap. Walk cels, and
          `down`: tipped over on her side, legs stuck out stiff.
    mule  a dun mule: long ears, a dark roached mane, pale muzzle and belly,
          a red rope halter. Walk cels, `kick`: head down, rump up, both hind
          hooves lashing out behind; and `down`.

Seen side on and a little from the front, head to the right (the game flips
the cel to walk left): x along the body, y away from the camera, z up.

The cow is a 3D model too (export_actors.py sets FOR_MODEL): built facing the
camera as the people are (head toward -y) with no turn for the camera, lying
`down` square on her left side with her legs stuck out to her right, the top
pair raised a little; the 3D view rolls her standing model over onto that
side as she is tipped (view3d/actor_view.gd).
"""

# Set by export_actors.py: the pose for the model rather than the camera.
FOR_MODEL = False

COW = dict(canvas=(3.3, 1.8), px=96)
MULE = dict(canvas=(3.2, 2.05), px=104)
FARM_CELS = [0, -1, 1, "down"]
MULE_CELS = [0, -1, 1, "down", "kick"]
# Cels only: no wind-up and no hurt copies (jobs_for).
PLAIN_KINDS = ("cow", "mule")


def _hoof_leg(hip, knee, foot, r0, r1, hide, lower, hoof, M):
    """A leg from the hip through the knee (or hock) to the ground: thick
    above, slim below, a dark hoof at the foot."""
    fetlock = foot + Vector((0, 0, .11))
    limb(hip, knee, r0, r0 * .6, hide, M)
    limb(knee, fetlock, r0 * .52, r1, lower, M)
    limb(fetlock, foot + Vector((.02, 0, 0)), r1 * 1.05, r1 * 1.3, hoof, M, caps=False, seg=12)


def _legs(M, phase, dead, kick, look):
    """Four legs walking corner to corner (-1, 0, 1), stiff and splayed when
    `dead` (lying), the hind pair lashed back when `kick`."""
    hide, lower, hoof = look["hide"], look["lower"], look["hoof"]
    front_x, back_x, hip_z, side, r0, r1 = look["legs"]
    for x, s, k in ((front_x, -1, 0), (front_x, 1, 1), (back_x, -1, 1), (back_x, 1, 0)):
        front = x > 0
        swing = .16 * phase * (1 if k else -1)
        hip = Vector((x, s * side, hip_z))
        if dead:
            # Stiff and straight out from the belly, fore and hind pairs
            # apart; the top pair (her right, -y: she lies on her left) raised
            # well off the bottom pair, so all four read from any side. Each piece as long as
            # it is standing (export_actors.py matches the parts by shape: a
            # longer shin would be another part, and the leg would vanish).
            bend = .05 if front else -.12
            knee0 = Vector((x + bend, s * side, hip_z * .45))
            fetlock0 = Vector((x, s * side * .95, .11))
            way = Vector((.18 if front else -.18, s * (.45 if s < 0 else .02), -hip_z + .02)).normalized()
            knee = hip + way * (knee0 - hip).length
            fetlock = knee + way * (fetlock0 - knee0).length
            toe = fetlock + way * Vector((.02, 0, -.11)).length
            limb(hip, knee, r0, r0 * .6, hide, M)
            limb(knee, fetlock, r0 * .52, r1, lower, M)
            limb(fetlock, toe, r1 * 1.05, r1 * 1.3, hoof, M, caps=False, seg=12)
            continue
        if kick and not front:
            # Both hind legs straight out behind, hooves up.
            foot = Vector((x - .92, s * side * .7, hip_z - .02))
            knee = hip.lerp(foot, .45) + Vector((0, 0, -.05))
        elif FOR_MODEL and swing:
            # The model swings each leg whole from the hip: a shin stretched
            # by the stride would be another part to export_actors.py, gone
            # from that walk beat.
            bend = .05 if front else -.12
            turn = Matrix.Rotation(-math.atan2(swing, hip_z), 3, "Y")
            knee = hip + turn @ (Vector((x + bend, s * side, hip_z * .45)) - hip)
            foot = hip + turn @ (Vector((x, s * side * .95, 0)) - hip)
        else:
            reach = .12 if kick and front else 0.
            foot = Vector((x + swing + reach, s * side * .95, 0))
            bend = .05 if front else -.12
            knee = Vector((x + swing * .5 + bend, s * side, hip_z * .45))
        _hoof_leg(hip, knee, foot, r0, r1, hide, lower, hoof, M)


def _pose(frame, shift):
    """The body's matrix: walking (a slight turn to the camera), lying on its
    side (`down`), or rearing its rump up to kick; `shift` centres it."""
    phase = frame if isinstance(frame, int) else 0
    C = T((shift, 0, 0))
    if FOR_MODEL:
        # Head toward -y, square, and lying flat on her left side.
        M = R(0, 0, -math.pi / 2) @ C
        if frame == "down":
            M = R(0, 0, -math.pi / 2) @ T((0, 0, .39)) @ R(-math.pi / 2, 0, 0) @ T((0, 0, -1.0)) @ C
        return M, phase
    M = R(0, 0, -.3) @ C
    if frame == "down":
        # Turned more to the camera than she walks, so her stiff legs show
        # their length rather than pointing at the eye.
        M = T((0, 0, .36)) @ R(0, 0, -.62) @ R(-1.82, 0, 0) @ C
    elif frame == "kick":
        M = R(0, 0, -.3) @ T((0, 0, .1)) @ R(0, .18, 0) @ C
    return M, phase


def _flank(x, z, cz, ry, rz):
    """Where the barrel's near side is at (x, z): y of its surface."""
    return -(ry * math.sqrt(max(0., 1. - ((z - cz) / rz) ** 2)))


def cow(frame):
    M, phase = _pose(frame, -.3)
    dead = frame == "down"
    white = mat(228, 224, 212, .8, grime=.45)
    black = mat(32, 30, 32, .8, grime=.3)
    pink = mat(214, 150, 146, .6, grime=.25)
    hoof = mat(46, 40, 34, .5, grime=.3)
    horn = mat(222, 208, 170, .5, grime=.3)
    look = dict(hide=white, lower=white, hoof=hoof, legs=(.66, -.66, .84, .2, .12, .062))
    # the barrel, shoulder, brisket, hip bones and rump: a flat back
    ball((0, 0, 1.0), (.92, .38, .4), white, M)
    ball((.6, 0, 1.05), (.38, .35, .4), white, M)
    ball((.72, 0, .84), (.26, .27, .24), white, M)
    ball((-.68, 0, 1.12), (.34, .35, .3), white, M)
    ball((-.88, 0, 1.12), (.2, .28, .24), white, M)
    ball((-.05, 0, .82), (.64, .35, .3), white, M)
    # her black patches: each a few flat lobes on the near flank (and far)
    patches = ((.2, 1.08, .26, .2), (.36, .95, .18, .14), (-.42, .98, .2, .18), (-.3, 1.16, .16, .12),
               (.62, 1.16, .16, .13), (-.75, 1.2, .14, .11))
    for x, z, rx, rz in patches:
        y = _flank(x, z, 1.0, .38, .42)
        for s in (-1, 1):
            ball((x, s * (-y - .02), z), (rx, .05, rz), black, M, rot=(0, .3 * s, 0))
    ball((-.25, 0, 1.38), (.3, .2, .05), black, M)
    # neck, dewlap and the long face: black with a white blaze
    neck_a, neck_b = Vector((.85, 0, 1.13)), Vector((1.24, 0, 1.06))
    limb(neck_a, neck_b, .27, .19, white, M)
    ball((1.02, 0, .9), (.2, .13, .17), white, M)
    skull = Vector((1.36, 0, 1.03))
    ball(skull, (.2, .15, .17), black, M)
    limb(skull, skull + Vector((.24, 0, -.2)), .15, .12, black, M)
    limb(skull + Vector((.08, -.02, .06)), skull + Vector((.24, -.02, -.17)), .1, .09, white, M)
    nose = skull + Vector((.28, 0, -.23))
    ball(nose, (.12, .13, .11), pink, M)
    for s in (-1, 1):
        ball(nose + Vector((.09, s * .055, 0)), (.02, .022, .026), mat(70, 40, 40, .5, grime=0), M)
        ball(skull + Vector((.06, s * .14, .03)), .032, BLACK(), M)
        ball(skull + Vector((.07, s * .15, .045)), .011, mat(230, 230, 230, .3, grime=0), M)
        ear = skull + Vector((-.06, s * .14, .07))
        limb(ear, ear + Vector((-.04, s * .2, -.01)), .06, .03, black, M)
        limb(skull + Vector((-.04, s * .1, .14)), skull + Vector((-.01, s * .21, .23)), .03, .012, horn, M)
    ball(skull + Vector((-.1, -.33, .06)), (.03, .012, .036), mat(232, 196, 40, .5, grime=.2), M)
    # the cowbell on its strap
    strap = mat(92, 58, 34, .7)
    collar = neck_a.lerp(neck_b, .55)
    for k in range(12):
        a, b = k / 12 * math.tau, (k + 1) / 12 * math.tau
        limb(collar + Vector((0, .22 * math.sin(a), .22 * math.cos(a))),
             collar + Vector((0, .22 * math.sin(b), .22 * math.cos(b))), .018, .018, strap, M, caps=False, seg=6)
    bell = collar + Vector((.02, -.03, -.32))
    limb(bell + Vector((0, 0, .06)), bell + Vector((0, 0, -.07)), .045, .068, BRASS(), M)
    # the udder
    ball((-.44, 0, .6), (.19, .16, .13), pink, M)
    for dx in (-.07, .07):
        for s in (-1, 1):
            limb((-.44 + dx, s * .06, .52), (-.44 + dx, s * .06, .44), .024, .017, pink, M)
    # the tail and its tuft, swinging with the walk
    root = Vector((-1.04, 0, 1.24))
    end = Vector((-1.12 - .05 * phase, .04 * phase, .52))
    if dead:
        # Out stiff behind her, as long as it hangs (the same part).
        end = root + Vector((-.41, -.02, -.24)).normalized() * (Vector((-1.12, 0, .52)) - root).length
    limb(root, end, .03, .02, white, M)
    ball(end, (.05, .05, .1), black, M)
    _legs(M, phase, dead, False, look)


def mule(frame):
    M, phase = _pose(frame, -.22)
    dead = frame == "down"
    kick = frame == "kick"
    dun = mat(134, 110, 86, .85, grime=.45)
    pale = mat(208, 192, 166, .8, grime=.4)
    dark = mat(72, 58, 48, .8, grime=.35)
    hoof = mat(40, 36, 32, .5, grime=.3)
    rope = mat(168, 46, 36, .7, grime=.3)
    look = dict(hide=dun, lower=dark, hoof=hoof, legs=(.56, -.6, .9, .17, .1, .05))
    # a lean barrel, a deep chest, high hips and a goose rump
    ball((0, 0, 1.08), (.8, .3, .33), dun, M)
    ball((.55, 0, 1.12), (.32, .29, .36), dun, M)
    ball((-.6, 0, 1.16), (.32, .3, .32), dun, M)
    ball((-.78, 0, 1.12), (.22, .26, .26), dun, M)
    ball((0, 0, .9), (.55, .27, .22), pale, M)
    # the dark stripe down the back
    ball((0, 0, 1.38), (.72, .07, .03), dark, M)
    # the neck held up and long, the big head, the pale muzzle
    drop = -.32 if kick else 0.
    neck_a = Vector((.72, 0, 1.25))
    neck_b = Vector((1.04, 0, 1.45 + drop * .6))
    skull = Vector((1.13, 0, 1.42 + drop))
    limb(neck_a, neck_b, .21, .13, dun, M)
    ball(skull, (.16, .11, .13), dun, M)
    limb(skull, skull + Vector((.3, 0, -.22)), .11, .085, dun, M)
    nose = skull + Vector((.33, 0, -.25))
    ball(nose, (.09, .09, .085), pale, M)
    for s in (-1, 1):
        ball(nose + Vector((.07, s * .04, -.01)), (.016, .016, .02), mat(40, 30, 28, .5, grime=0), M)
        ball(skull + Vector((.03, s * .11, .03)), .026, BLACK(), M)
        ball(skull + Vector((.04, s * .12, .045)), .009, mat(220, 220, 220, .3, grime=0), M)
        # the ears: long, up and a little apart (laid back in a kick)
        base = skull + Vector((-.07, s * .07, .1))
        tip = base + (Vector((-.3, s * .1, .14)) if kick else Vector((-.04, s * .12, .4)))
        limb(base, tip, .05, .018, dun, M)
        limb(base + Vector((0, -.012, .02)), tip + Vector((0, -.006, -.02)), .028, .008, pale, M)
        ball(tip, .02, dark, M)
    # the roached mane, a crest of short dark hair up the neck
    for k in range(7):
        a = neck_a.lerp(neck_b, k / 6) + Vector((-.05, 0, .15 - k * .012))
        limb(a, a + Vector((.02, 0, .06)), .028, .018, dark, M, caps=False, seg=8)
    # the rope halter: round the nose, behind the ears, a lead hanging
    for c, r_y, r_z in ((skull + Vector((.24, 0, -.17)), .1, .09), (skull + Vector((-.05, 0, .01)), .13, .15)):
        for k in range(10):
            a, b = k / 10 * math.tau, (k + 1) / 10 * math.tau
            limb(c + Vector((0, r_y * math.sin(a), r_z * math.cos(a))),
                 c + Vector((0, r_y * math.sin(b), r_z * math.cos(b))), .014, .014, rope, M, caps=False, seg=6)
    lead_top = skull + Vector((.2, -.07, -.27))
    limb(lead_top, lead_top + Vector((-.08, -.02, -.36)), .013, .013, rope, M)
    # the tail: a slim dock and a dark switch (up and out in a kick)
    root = Vector((-.94, 0, 1.28))
    if kick:
        end = Vector((-1.28, 0, 1.5))
    elif dead:
        end = Vector((-1.42, -.02, 1.1))
    else:
        end = Vector((-1.02 - .05 * phase, .04 * phase, .6))
    limb(root, root.lerp(end, .35), .035, .028, dun, M)
    limb(root.lerp(end, .3), end, .042, .016, dark, M)
    _legs(M, phase, dead, kick, look)


ACTORS.update({
    "cow": (cow, COW, (), FARM_CELS),
    "mule": (mule, MULE, (), MULE_CELS),
})
