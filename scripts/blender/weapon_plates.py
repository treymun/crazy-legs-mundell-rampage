"""The .38 and the sawed-off, modelled (polish pass 9): until then the game
showed them as the old photographs, hands and all, a different light, grade
and scale from every other gun. Run inside weapon_views.py (it execs this
file before its WEAPONS table), so the materials, shapes and rigs are its
own, and each is held as the other guns of its rig are:
  revolver  the pistol rig (the revolver plate's hand): the top of the grip
            at the origin, the cylinder above it, the barrel along +Y
  shotgun   the long rig (the shotgun plate's left hand on the fore-end):
            the breech's top rear at the origin, the barrels along +Y

A reload shows the gun's own works (STATE, set by weapon_views.py
render_states() before each render): the .38's cylinder swung out on its
crane (`open`), its empties thrown off the ejector (`eject`), fresh rounds
going in (`load`); the sawed-off broken open on its hinge (`open`), the
empties kicked out (`eject`, `eject_one`), fresh shells going in (`load`,
`load_one`). Everything here is modelled from plain shapes; nothing is traced.
"""

STATE = "closed"

BLUED_38 = lambda: pbr("blued_38", (46, 48, 58), .3, 1., wear=(140, 142, 150), bump=.05, scale=30.,
                       edge=(190, 190, 198), cavity=.6)
BLUED_SG = lambda: pbr("blued_sg", (20, 22, 32), .52, 1., wear=(116, 112, 112), blotch=(54, 42, 38),
                       bump=.06, scale=26., edge=(176, 174, 178), cavity=.6)
CASE_COLOUR = lambda: pbr("case_colour", (78, 70, 74), .34, 1., wear=(160, 130, 98), blotch=(96, 76, 116),
                          bump=.05, edge=(196, 184, 166), cavity=.7)
WALNUT = lambda: pbr("walnut_38", (96, 52, 26), .45, 0., grain=(46, 24, 12), wear=(152, 106, 66), scale=16.,
                     edge=(166, 122, 80), cavity=.5)
HULL = lambda: pbr("shell_hull", (164, 38, 28), .5, 0., wear=(204, 124, 102), bump=.15, scale=40.)
SHELL_BRASS = lambda: pbr("shell_brass", (178, 138, 62), .3, 1., wear=(228, 202, 132), bump=.03)
LEAD = lambda: pbr("lead_38", (124, 120, 116), .5, .7, bump=.05)
KNURL = lambda: pbr("knurl_38", (40, 40, 46), .55, 1., bump=.4, scale=200.)

# The .38: the bore's height, the cylinder's axis height, front and back,
# radius and how far its chambers lie off its axis; the barrel's end.
BORE38, CYL_Z, CYL_Y0, CYL_Y1, CYL_R, CHAMBER = .064, .049, -.006, .05, .0235, .0145
MUZZLE38, R38 = .19, .0102
# The sawed-off: the barrels' axes (each SPREAD_SG off the middle), radius, end.
AXIS_SG, RSG, SPREAD_SG, LSG = -.0125, .0118, .0125, .42
# The reload's frames each gun has a render of (the rest are the gun shut).
STATES = {"revolver": ["open", "eject", "load"], "shotgun": ["open", "eject", "eject_one", "load", "load_one"]}


def cartridge_38(base, axis, spent=False):
    """A .38 round from its rim at `base` along `axis`: brass case and lead
    nose, or the empty case alone."""
    a = Vector(base)
    k = Vector(axis).normalized()
    disc(a + k * .0006, k, .0056, .0012, SHELL_BRASS(), seg=16)
    rod(a + k * .0012, a + k * .03, .0047, .0047, SHELL_BRASS(), seg=14)
    if spent:
        disc(a + k * .0303, k, .0034, .0006, SLOT(), seg=12)
    else:
        rod(a + k * .03, a + k * .038, .0042, .0019, LEAD(), seg=14)


def cylinder_38(c, loaded, ejected=0.):
    """The .38's fluted cylinder, its back face's middle at `c`, its axis
    along +Y; `loaded` chambers show a case rim at the back, the ejector star
    stands `ejected` proud of it with the rounds riding out on it."""
    c = Vector(c)
    k = Vector((0, 1, 0))
    u = Vector((0, 0, 1))
    v = Vector((1, 0, 0))
    blued = BLUED_38()
    length = CYL_Y1 - CYL_Y0
    rod(c, c + k * (length - .002), CYL_R, CYL_R, blued, seg=48)
    rod(c + k * (length - .002), c + k * length, CYL_R, CYL_R - .003, blued, seg=48)
    rod(c - k * .0015, c, CYL_R - .0025, CYL_R, blued, seg=48)
    for n in range(6):
        a = n * math.tau / 6 + math.tau / 12
        out = u * math.cos(a) + v * math.sin(a)
        rod(c + k * .016 + out * (CYL_R - .0006), c + k * (length - .006) + out * (CYL_R - .0006), .0044, .0044,
            pbr("flute_38", (16, 16, 20), .45, 1.), seg=12, round_ends=True)
        box(c + k * .007 + out * CYL_R, (.0042, .0042, .0042), SLOT(), bevel=.001)
    for n in range(6):
        a = n * math.tau / 6
        out = u * math.cos(a) + v * math.sin(a)
        at = c + out * CHAMBER
        disc(at + k * (length + .0003), k, .0049, .0012, SLOT(), seg=14)
        disc(at - k * .0016, k, .0049, .0008, SLOT(), seg=14)
        if n in loaded:
            disc(at - k * (.0021 + ejected), k, .0057, .0012, SHELL_BRASS(), seg=16)
            if ejected:
                rod(at - k * ejected, at, .0047, .0047, SHELL_BRASS(), seg=14)
    if ejected:
        disc(c - k * (.0016 + ejected * .5), k, .0108, ejected, blued, seg=18)
    # the centre pin and the ejector rod out the front, pushed in as it ejects
    reach = .05 - ejected
    rod(c + k * length, c + k * (length + reach), .0036, .0036, blued, seg=14)
    ball(c + k * (length + reach), .0043, KNURL())


def revolver():
    """The .38: a four-inch service revolver of the Model 10 kind, bluing
    gone grey on the edges, walnut stocks with their checkering showing over
    the hand, a ramp front sight, the ejector rod under the barrel in its lug,
    the hammer back."""
    blued = BLUED_38()
    walnut = WALNUT()
    # the grip the hand closes on, its round butt (shorter than the other
    # pistols' stand-in: it shows whole on the pickup)
    rod((0, -.02, -.004), (0, -.042, -.09), .02, .023, walnut, round_ends=True)
    # the walnut stocks' screw and a little checkering above the hand
    for side in (-1, 1):
        screw((side * .021, -.02, -.02), (side, 0, 0), .0026, blued)
        for k in range(3):
            box((side * .0205, -.024 + k * .004, -.036 + k * .005), (.0008, .014, .0012), SLOT(), rot=(-.9, 0, 0),
                bevel=.0002)
    # the frame round the cylinder: the top strap with the rear sight's
    # groove, the bottom under it, the shank the barrel screws into, the
    # recoil shield, the back of the frame with the hammer
    box((0, .022, CYL_Z + CYL_R + .004), (.019, .068, .008), blued, bevel=.0025)
    box((0, .02, CYL_Z + CYL_R + .0082), (.004, .06, .0012), SLOT(), bevel=.0003)
    box((0, .022, CYL_Z - CYL_R - .006), (.025, .07, .013), blued, bevel=.003)
    box((0, CYL_Y1 + .004, CYL_Z + .004), (.024, .008, .056), blued, bevel=.003)
    box((0, CYL_Y0 - .005, CYL_Z + .002), (.026, .01, .058), blued, bevel=.003)
    box((0, -.026, .046), (.022, .03, .05), blued, bevel=.004)
    box((0, -.012, .016), (.024, .04, .022), blued, bevel=.004)
    # the side plate's screws and the cylinder latch on the left
    for y, z in ((.028, .022), (-.026, .062), (-.032, .03)):
        screw((-.0122 if y > 0 else -.0112, y, z), (-1, 0, 0), .0022, blued)
    box((-.0128, -.02, .05), (.003, .013, .007), blued, bevel=.001)
    for k in range(4):
        box((-.0144, -.025 + k * .0032, .05), (.0008, .0011, .0062), SLOT(), bevel=.0002)
    # the hammer back at full cock, its checkered spur; the trigger guard, the trigger
    box((0, -.046, .068), (.0072, .02, .018), blued, rot=(-.55, 0, 0), bevel=.002)
    box((0, -.056, .081), (.0084, .013, .006), blued, rot=(-.3, 0, 0), bevel=.0015)
    for k in range(3):
        box((0, -.06 + k * .004, .0842 - k * .0012), (.0086, .0012, .0008), SLOT(), rot=(-.3, 0, 0), bevel=.0002)
    for n in range(20):
        a, b = n * math.tau / 20, (n + 1) * math.tau / 20
        if math.sin(a) > .3 and math.sin(b) > .3:
            continue
        rod((0, .016 + math.cos(a) * .017, .0 + math.sin(a) * .014),
            (0, .016 + math.cos(b) * .017, .0 + math.sin(b) * .014), .0024, .0024, blued, seg=8)
    box((0, .012, .0), (.0046, .005, .022), blued, rot=(.3, 0, 0), bevel=.0012)
    # the barrel, its rib, ramp front sight, the ejector rod's lug, the crown
    rod((0, CYL_Y1, BORE38), (0, MUZZLE38, BORE38), R38 + .0006, R38, blued, seg=36)
    box((0, (CYL_Y1 + MUZZLE38) / 2, BORE38 + R38 - .001), (.0055, MUZZLE38 - CYL_Y1, .004), blued, bevel=.001)
    box((0, MUZZLE38 - .008, BORE38 + R38 + .004), (.0032, .016, .008), blued, rot=(.32, 0, 0), bevel=.0008)
    box((0, MUZZLE38 - .012, CYL_Z + .003), (.0085, .018, .012), blued, bevel=.002)
    disc((0, MUZZLE38 + .0004, BORE38), (0, 1, 0), .0046, .0012, SLOT(), seg=20)
    ring((0, MUZZLE38 - .0006, BORE38), (0, 1, 0), .0068, .0011, blued, n=24)
    if STATE == "closed":
        cylinder_38((0, CYL_Y0, CYL_Z), range(6))
        return
    # Swung out on its crane to the left and down, its back face to the eye.
    centre = Vector((-.05, CYL_Y0 + .004, CYL_Z - .016))
    crane = Vector((-.011, CYL_Y1 + .002, CYL_Z - CYL_R + .002))
    mid = (crane + Vector((centre.x, crane.y, centre.z))) / 2
    box(tuple(mid), ((Vector((centre.x, 0, centre.z)) - Vector((crane.x, 0, crane.z))).length + .01, .008, .01),
        blued, rot=(0, -math.atan2(centre.z - crane.z, centre.x - crane.x), 0), bevel=.002)
    rod(tuple(crane), (crane.x, crane.y + .01, crane.z), .0042, .0042, blued, seg=12)
    if STATE == "open":
        cylinder_38(centre, [])
    elif STATE == "eject":
        cylinder_38(centre, [0, 2, 5], ejected=.016)
        # the empties thrown off the star, tumbling back and down
        for at, axis in (((-.075, -.05, .02), (.4, -1, .5)), ((-.035, -.075, -.006), (-.3, -1, .9)),
                         ((-.098, -.09, .052), (.9, -.6, -.3)), ((-.06, -.11, -.03), (.2, -.4, 1))):
            cartridge_38(at, axis, spent=True)
    elif STATE == "load":
        cylinder_38(centre, [0, 1, 2, 5])
        # one going in, one more coming in the fingers' way
        a = math.tau * 3 / 6
        hole = centre + Vector((math.sin(a), 0, math.cos(a))) * CHAMBER
        cartridge_38(hole - Vector((0, .024, 0)), (0, 1, 0))
        a = math.tau * 4 / 6
        hole = centre + Vector((math.sin(a), 0, math.cos(a))) * CHAMBER
        cartridge_38(hole + Vector((-.008, -.06, -.006)), (.15, 1, .1))


def shell_12(base, axis):
    """A 12 bore shell from its brass head at `base` along `axis`."""
    a = Vector(base)
    k = Vector(axis).normalized()
    disc(a + k * .001, k, .0122, .002, SHELL_BRASS(), seg=24)
    rod(a + k * .002, a + k * .016, .0109, .0109, SHELL_BRASS(), seg=24)
    rod(a + k * .016, a + k * .068, .0107, .0107, HULL(), seg=24)
    disc(a + k * .0683, k, .0096, .0008, pbr("crimp", (122, 30, 22), .6), seg=20)
    disc(a - k * .0002, k, .0033, .0006, pbr("primer", (192, 172, 122), .3, 1.), seg=12)
    for n in range(8):
        t = n * math.tau / 8
        u = k.orthogonal().normalized()
        w = k.cross(u)
        rod(a + k * .0668 + (u * math.cos(t) + w * math.sin(t)) * .0055,
            a + k * .0668 + (u * math.cos(t) + w * math.sin(t)) * .0098, .0007, .0007, SLOT(), seg=4)


def shotgun():
    """The sawed-off: an old side-by-side coach gun cut down, its
    case-coloured action and rabbit-ear hammers, the barrels' bluing rubbed
    brown, a split walnut fore-end wrapped in friction tape, the stock sawn
    off to a pistol grip."""
    blued = BLUED_SG()
    walnut = WALNUT()
    case = CASE_COLOUR()
    z = AXIS_SG
    # the barrels side by side, the rib between them and its bead, the bores,
    # the ends filed square where they were sawn
    for s in (-1, 1):
        x = s * SPREAD_SG
        rod((x, 0, z), (x, LSG, z), RSG + .0008, RSG, blued, seg=36)
        disc((x, LSG + .0004, z), (0, 1, 0), RSG * .74, .0012, SLOT(), seg=28)
        ring((x, LSG - .001, z), (0, 1, 0), RSG * .92, .0012, pbr("filed", (120, 116, 112), .3, 1.), n=26)
    box((0, LSG / 2, z + RSG * .78), (.009, LSG, .006), blued, bevel=.0015)
    box((0, LSG / 2, z - RSG * .78), (.009, LSG - .02, .006), blued, bevel=.0015)
    ball((0, LSG - .014, z + RSG * .78 + .004), .0026, SHELL_BRASS())
    # the split fore-end under the barrels where the hand cups it, its iron,
    # the crack and the friction tape holding it
    box((0, .22, z - .021), (.036, .24, .022), walnut, bevel=.007)
    box((0, .095, z - .024), (.03, .02, .016), case, bevel=.003)
    box((-.0182, .25, z - .021), (.0012, .08, .003), SLOT(), bevel=.0003)
    rod((0, .3, z - .018), (0, .322, z - .018), .0272, .0272,
        pbr("friction_tape", (30, 30, 30), .9, bump=.6, scale=70.), seg=28)
    # the action, breech and stock: shut, or broken open on the hinge pin
    # (the barrels stay in the hand, the action drops away under them)
    hinge = Vector((0, .002, z - .016))
    drop = 0. if STATE == "closed" else .5
    M = T(hinge) @ Matrix.Rotation(drop, 4, "X") @ T(-hinge)
    box((0, -.045, z + .001), (.054, .09, .036), case, M=M, bevel=.004)
    box((0, .002, z - .016), (.054, .01, .016), case, M=M, bevel=.002)
    rod(M @ Vector((-.028, .002, z - .016)), M @ Vector((.028, .002, z - .016)), .0055, .0055, case, seg=16)
    # the lock plates' scroll on the near side
    for k in range(3):
        box((-.0272, -.06 + k * .016, z + .004 - k * .002), (.0008, .01, .0016), SLOT(), M=M, rot=(.4 * k, 0, 0),
            bevel=.0002)
    for s in (-1, 1):
        # the rabbit-ear hammers back at full cock, out of the lock plates
        rod(M @ Vector((s * .018, -.07, z + .012)), M @ Vector((s * .02, -.092, z + .034)), .0042, .0036, case,
            seg=10)
        ball(M @ Vector((s * .021, -.096, z + .037)), (.0062, .0062, .0032), case)
        for k in range(3):
            box((s * .021, -.0975 + k * .0028, z + .0402), (.009, .0008, .0008), SLOT(), M=M, bevel=.0002)
    # the top lever, swung over as the action opens
    box((.006 if STATE == "closed" else .016, -.072, z + .0205), (.016, .03, .006), case, M=M,
        rot=(0, 0, .2 if STATE == "closed" else .6), bevel=.002)
    # the trigger guard under the action and its two triggers
    for n in range(20):
        a, b = n * math.tau / 20, (n + 1) * math.tau / 20
        if math.sin(a) > -.1 and math.sin(b) > -.1:
            continue
        rod(M @ Vector((0, -.055 + math.cos(a) * .022, z - .017 + math.sin(a) * .015)),
            M @ Vector((0, -.055 + math.cos(b) * .022, z - .017 + math.sin(b) * .015)), .0026, .0026, blued, seg=8)
    for y in (-.05, -.064):
        rod(M @ Vector((0, y, z - .017)), M @ Vector((0, y - .004, z - .03)), .0021, .0019, case, seg=8)
    # the wrist out of the action and the stock sawn to a grip, its butt
    # taped where the saw left it rough
    rod(M @ Vector((0, -.086, z - .001)), M @ Vector((0, -.15, z - .03)), .019, .02, walnut, seg=28)
    rod(M @ Vector((0, -.145, z - .028)), M @ Vector((0, -.2, z - .095)), .02, .022, walnut, seg=28,
        round_ends=True)
    rod(M @ Vector((0, -.175, z - .062)), M @ Vector((0, -.2, z - .095)), .0232, .0232,
        pbr("grip_tape", (40, 40, 42), .85, bump=.7, scale=60.), seg=24)
    box((0, -.092, z - .001), (.04, .016, .032), case, M=M, bevel=.004)
    if STATE == "closed":
        return
    # Broken open: the breech ends of the barrels bare, the extractor up
    for s in (-1, 1):
        disc((s * SPREAD_SG, -.0006, z), (0, 1, 0), RSG + .0006, .0012, blued, seg=28)
        disc((s * SPREAD_SG, -.0014, z), (0, 1, 0), RSG * .8, .0008, SLOT(), seg=24)
    box((0, -.002, z - .012), (.03, .006, .012), case, bevel=.0015)
    for s in {"eject_one": [-1], "load_one": [-1]}.get(STATE, []):
        # the other barrel's shell left in it
        disc((s * SPREAD_SG, -.0022, z), (0, 1, 0), .0122, .002, SHELL_BRASS(), seg=24)
        disc((s * SPREAD_SG, -.0034, z), (0, 1, 0), .0033, .0006, pbr("primer", (192, 172, 122), .3, 1.),
             seg=12)
    # the empties kicked up and out to the right, over the breech
    if STATE == "eject":
        shell_12((.05, .03, z + .07), (.3, -.5, -.8))
        shell_12((.1, .0, z + .03), (.8, -.3, .5))
    elif STATE == "eject_one":
        shell_12((.07, .02, z + .06), (.5, -.5, -.7))
    elif STATE == "load":
        shell_12((-SPREAD_SG, -.032, z), (0, 1, 0))
        shell_12((SPREAD_SG, -.064, z + .006), (0, 1, .06))
    elif STATE == "load_one":
        shell_12((SPREAD_SG, -.032, z), (0, 1, 0))
