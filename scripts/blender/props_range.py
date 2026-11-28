"""The firing range's props: Mundell's Proving Grounds, a county-fair shooting
range out past the hog lots. Gun racks, release levers, straw whuppin'
dummies, bowling pins, bullseyes, gongs, sandbags, floodlight poles, the PA
pole and the plywood cows.

    blender -b -P scripts/blender/props_range.py -- <out dir> <names|all> [supersample]

It runs town_props.py's library (materials, shapes, the stage and main())
with these props in place of the town's, so the renders land beside the
town's in the same folder and meta.json; godot/tools/art/build_town_props.gd
lists this script and shrinks them into assets/art as town_<name>.png.
Everything is modelled here from scratch; nothing is traced from another game.
"""
import os

_HERE = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(_HERE, "town_props.py"), encoding="utf-8") as _lib:
    _source = _lib.read()
# The library without its last line (main()), which runs below with this
# script's props.
exec(_source[: _source.rstrip().rfind("main()")], globals())

RED = (176, 40, 30)
CREAM = (232, 222, 196)
GREEN_PAINT = (52, 92, 60)
STEEL = (150, 152, 150)


def _rounded_box(dims, loc, material, radius, rot=(0, 0, 0)):
    mesh = bmesh.new()
    bmesh.ops.create_cube(mesh, size=1.0)
    for vert in mesh.verts:
        vert.co = Vector(tuple(vert.co[i] * dims[i] for i in range(3)))
    bmesh.ops.bevel(mesh, geom=list(mesh.edges), offset=radius, segments=2, affect="EDGES")
    return place(mesh, material, loc, rot)


def _rings(r, loc, rot, colours, depth=.02):
    """A painted bullseye: flat discs, each smaller ring a hair in front."""
    for k, colour in enumerate(colours):
        rr = r * (1.0 - k / len(colours))
        y = loc[1] - (k + 1) * .004
        cyl(rr, depth, (loc[0], y, loc[2]), mat(*colour, rough=.7, grime=.35), rot, seg=28)


def range_gun_rack():
    wood = mat(*WOOD, planks=6.0, grime=.45)
    dark = mat(70, 48, 32, planks=5.0, grime=.5)
    box(1.5, .4, .1, (0, 0, .08), dark)
    box(1.5, .12, .1, (0, .1, 1.05), wood)
    box(1.5, .3, .06, (0, 0, .42), wood)
    for x in (-.72, .72):
        box(.08, .4, 1.4, (x, 0, .72), dark)
    _rounded_box((1.6, .11, .22), (0, .15, 1.45), dark, .025)
    band = mat(124, 99, 69, metal=.62, rough=.6, grime=.62)
    for x in (-.72, .72):
        box(.11, .04, .19, (x, -.215, .154), band)
        cyl(.018, .016, (x, -.239, .175), mat(*STEEL, metal=.6), (90, 0, 0), seg=6)
    # Five long guns standing in the slots: stocks down, barrels up.
    stock = mat(118, 70, 40, rough=.5, grime=.35)
    blued = mat(46, 48, 52, metal=.8, rough=.3, grime=.4)
    for k in range(5):
        x = -.56 + k * .28
        lean = (k - 2) * 2.0
        box(.09, .07, .36, (x, -.02, .3), stock, (0, lean, 0))
        box(.04, .05, .7, (x + lean * .004, -.04, .82), blued, (0, lean, 0))
        box(.06, .06, .14, (x, -.03, .52), blued, (0, lean, 0))
    # A box of shells on the shelf and the rack's tin plate.
    box(.24, .14, .1, (.45, -.04, .5), mat(*RED, rough=.5))
    box(.4, .02, .12, (0, -.21, 1.45), mat(196, 164, 88, metal=.7, rough=.35, grime=.4))
    return 1.8, 1.7


def range_lever():
    post = mat(*GREY_WOOD, planks=4.0, grime=.6)
    box(.12, .12, 1.0, (0, .08, .5), post)
    box(.36, .2, .34, (0, 0, .92), mat(*GREEN_PAINT, metal=.3, rough=.5, grime=.65))
    box(.3, .02, .2, (0, -.105, .94), mat(220, 200, 120, rough=.6, grime=.4))
    # The handle thrown forward, a red knob on its end, and the quadrant.
    cyl(.05, .06, (0, -.12, .98), mat(40, 40, 40, metal=.7), (90, 0, 0), seg=12)
    box(.04, .04, .5, (0, -.22, 1.18), mat(*CHROME, metal=.9, rough=.25), (-28, 0, 0))
    ball(.07, (0, -.34, 1.4), mat(200, 30, 24, rough=.3))
    for x in (-.12, .12):
        box(.02, .02, .02, (x, -.11, 1.04), mat(250, 220, 120, emit=3.0, grime=0))
    return .7, 1.6


def range_dummy():
    post = mat(*WOOD, planks=4.0, grime=.55)
    cyl(.06, 1.7, (0, .02, .85), post, seg=8)
    box(.9, .08, .08, (0, .02, 1.28), post)
    sack = mat(176, 150, 102, planks=18.0, grime=.6)
    _rounded_box((.50, .32, .70), (0, 0, 1.0), sack, .068, (0, 3, 0))
    cyl(.18, .2, (0, 0, .6), mat(*STRAW, planks=30.0, grime=.4), seg=10, top=.24)
    # The target painted on its chest, the rope at the waist.
    _rings(.15, (0, -.16, 1.08), (90, 0, 0), [CREAM, RED, CREAM, RED])
    cord = mat(119, 91, 55, planks=8.0, grime=.52)
    for z in (.69, .715):
        _rounded_box((.512, .332, .022), (0, 0, z), cord, .008, (0, 3, 0))
    box(.088, .025, .092, (.16, -.164, .874), mat(134, 112, 74, planks=8.0, grime=.58), (0, -12, 0))
    for s in (1, -1):
        cyl(.08, .38, (s * .38, 0, 1.28), sack, (0, 90, 0), seg=8)
        for k in range(3):
            cyl(.025, .16, (s * (.6 + k * .02), (k - 1) * .04, 1.27), mat(*STRAW), (0, 90 + s * (k - 1) * 22, 0), seg=5, top=.004)
    # A dented bucket for a head, a bullet hole or two.
    bucket = mat(150, 156, 150, metal=.6, rough=.5, grime=.7)
    cyl(.17, .3, (0, 0, 1.52), bucket, (8, -6, 0), seg=16, top=.14)
    cyl(.18, .02, (0, 0, 1.67), bucket, (8, -6, 0), seg=16)
    for x, z in ((-.06, 1.55), (.07, 1.48)):
        ball(.022, (x, -.17, z), mat(14, 12, 10, grime=0))
    return 1.3, 1.9


def _pin_shape():
    white = mat(227, 217, 194, rough=.34, grime=.32)
    red = mat(178, 43, 31, rough=.42, grime=.22)
    heel = mat(129, 106, 79, rough=.62, grime=.48)
    profile = (
        (0.0, .040), (.010, .049), (.025, .057), (.053, .066), (.100, .067),
        (.140, .060), (.180, .047), (.216, .034), (.238, .028), (.249, .027),
        (.258, .028), (.270, .030), (.281, .032), (.296, .036), (.321, .041),
        (.344, .035), (.359, .023), (.367, .008),
    )
    sides = 16
    pin = bmesh.new()
    rows = []
    for z, radius in profile:
        rows.append([
            pin.verts.new((radius * math.cos(i * math.tau / sides),
                           radius * math.sin(i * math.tau / sides), z))
            for i in range(sides)
        ])
    for low, high in zip(rows, rows[1:]):
        for i in range(sides):
            j = (i + 1) % sides
            pin.faces.new((low[i], low[j], high[j], high[i]))
    pin.faces.new(tuple(reversed(rows[0])))
    pin.faces.new(rows[-1])
    ob = place(pin, white, (0, 0, 0), (0, 0, 0))
    ob.data.materials.append(red)
    ob.data.materials.append(heel)
    for face in ob.data.polygons:
        z = face.center.z
        if .238 < z < .249 or .258 < z < .270:
            face.material_index = 1
        elif z < .010:
            face.material_index = 2
        face.use_smooth = len(face.vertices) == 4
    return ob


def range_pin():
    _pin_shape()
    return .25, .4


# The pins in play (src/range_bowling.gd): tipped PIN_TILTS degrees with the
# head toward PIN_YAWS degrees, measured from the viewer's right toward away
# from the viewer (0 side on, head right; 90 head away; -90 head toward the
# viewer). Heads to the left are the game's flip of these. The last tilt is a
# pin lying on its belly and head.
PIN_TILTS = (22, 50, 90)
PIN_YAWS = (-90, -60, -30, 0, 30, 60, 90)


def _pin_pose(tilt, yaw):
    def build():
        _pin_shape()
        # The stage turns every prop -28 degrees about the vertical: undo it so
        # the yaw is the viewer's. Tip about the rim of the base on that side.
        a = math.radians(yaw + 28)
        t = math.radians(tilt)
        ROOT.rotation_mode = "AXIS_ANGLE"
        ROOT.rotation_axis_angle = (t, -math.sin(a), math.cos(a), 0)
        ROOT.location = (0, 0, .062 * math.sin(t) if tilt >= 90 else .0)
        return .5, .45

    return build


def range_pin_down():
    pin = _pin_shape()
    pin.location = (-.168, 0, .067)
    pin.rotation_euler.y = math.pi / 2
    ROOT.rotation_euler.z = math.radians(30)
    return .45, .2


def range_target():
    frame = mat(*WOOD, planks=5.0, grime=.5)
    for s in (1, -1):
        box(.06, .06, 1.3, (s * .38, .14, .6), frame, (14, s * 10, 0))
    box(.06, .06, 1.2, (0, .4, .56), frame, (-22, 0, 0))
    box(.86, .07, .07, (0, .1, .56), frame)
    box(.86, .07, .07, (0, .1, 1.08), frame)
    board = mat(214, 206, 180, planks=7.0, grime=.5)
    box(.82, .04, .82, (0, .06, .9), board)
    _rings(.38, (0, .03, .9), (90, 0, 0), [CREAM, RED, CREAM, RED, CREAM, RED])
    # Holes where the county has already had a go.
    for x, z in ((-.2, 1.05), (.1, .78), (.25, .96), (-.05, .88)):
        ball(.018, (x, -.03, z), mat(14, 12, 10, grime=0))
    return 1.1, 1.45


def range_gong():
    frame = mat(*GREY_WOOD, planks=5.0, grime=.6)
    for s in (1, -1):
        box(.08, .08, 1.5, (s * .55, 0, .72), frame, (0, s * 8, 0))
    box(1.3, .1, .1, (0, 0, 1.45), frame)
    steel = mat(*STEEL, metal=.85, rough=.35, grime=.55)
    cyl(.32, .04, (0, 0, .92), steel, (90, 0, 0), seg=28)
    cyl(.12, .045, (0, -.006, .92), mat(*RED, rough=.5, grime=.3), (90, 0, 0), seg=24)
    iron = mat(60, 58, 54, metal=.8, rough=.4)
    for x in (-.2, .2):
        chain((x, 0, 1.4), (x * .8, 0, 1.2), iron, .05)
    for x, z in ((.14, 1.0), (-.08, .8), (.04, .96)):
        ball(.025, (x, -.03, z), mat(220, 220, 214, metal=.9, rough=.2))
    return 1.5, 1.6


def range_sandbags():
    burlap = mat(161, 138, 96, planks=15.0, grime=.68)
    cord = mat(125, 106, 70, planks=13.0, grime=.45)
    for row in range(3):
        for k in range(4 - (row % 2)):
            x = -.6 + k * .4 + (row % 2) * .2
            z = .1 + row * .19
            turn = (0, (k * 7 + row * 3) % 5 - 2, (k * 11) % 7 - 3)
            _rounded_box((.421, .30, .20), (x, 0, z), burlap, .064, turn)
            _rounded_box((.33, .302, .026), (x, 0, z + .012), cord, .011, turn)
    return 1.7, .8


def range_floodlight():
    pole = mat(*GREY_WOOD, planks=3.0, grime=.6)
    cyl(.1, 4.4, (0, .1, 2.2), pole, seg=10, top=.07)
    box(1.3, .1, .1, (0, .05, 4.1), pole)
    box(1.1, .08, .08, (0, .05, 3.7), pole)
    can = mat(40, 42, 40, metal=.6, rough=.4, grime=.5)
    glow = mat(255, 238, 190, emit=9.0, grime=0)
    for x in (-.45, -.15, .15, .45):
        for z in (4.25, 3.85):
            cyl(.13, .16, (x, -.08, z), can, (90, 0, 0), seg=14)
            cyl(.1, .02, (x, -.17, z), glow, (90, 0, 0), seg=14)
    # The conduit down the pole, a junction box and the climbing pegs.
    cyl(.02, 4.0, (.11, .0, 2.0), mat(70, 70, 70, metal=.6), seg=6)
    box(.22, .14, .3, (.12, -.06, 1.4), mat(*GREEN_PAINT, metal=.3, grime=.6))
    for k in range(6):
        box(.18, .03, .03, (0, .1, .8 + k * .45), mat(60, 58, 54, metal=.7), (0, 0, (k % 2) * 180 - 90))
    return 1.6, 4.5


def range_loudspeaker():
    pole = mat(*GREY_WOOD, planks=3.0, grime=.6)
    cyl(.07, 3.2, (0, .05, 1.6), pole, seg=8)
    sill = mat(64, 69, 59, metal=.6, rough=.55, grime=.62)
    cyl(.14, .065, (0, .05, .0325), sill, seg=8)
    _rounded_box((.20, .155, .23), (0, -.02, 1.15), sill, .024)
    horn = mat(96, 112, 92, metal=.5, rough=.45, grime=.6)
    mouth = mat(30, 30, 28, rough=.9, grime=0)
    for s in (1, -1):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=.2, radius2=.05, depth=.42)
        place(bm, horn, (s * .24, -.16, 2.88), (-80, 0, s * 25))
        cyl(.17, .01, (s * .33, -.36, 2.84), mouth, (-80, 0, s * 25), seg=16)
        cyl(.07, .14, (s * .14, -.0, 2.9), mat(50, 50, 50, metal=.6), (-80, 0, s * 25), seg=10)
    box(.5, .06, .06, (0, 0, 2.9), mat(50, 50, 50, metal=.6))
    # The red range flag: up means the range is hot.
    cyl(.015, 1.0, (.0, .0, 3.6), mat(60, 60, 60, metal=.6), seg=6)
    box(.5, .01, .3, (.26, 0, 3.92), mat(210, 36, 28, rough=.6, grime=.3), (0, 0, -8))
    return 1.0, 4.2


def range_ammo_crate():
    crate = mat(*WOOD, planks=8.0, grime=.5)
    box(.8, .5, .055, (0, 0, .028), crate)
    for x in (-.374, .374):
        _rounded_box((.052, .50, .36), (x, 0, .18), crate, .011)
    for y in (-.223, .223):
        _rounded_box((.723, .052, .36), (0, y, .18), crate, .012)
    box(.70, .41, .11, (0, 0, .277), mat(92, 65, 41, planks=9.0, grime=.58))
    box(.8, .04, .4, (0, .3, .5), crate, (-30, 0, 0))
    box(.5, .02, .14, (0, -.26, .2), mat(220, 200, 150, grime=.4))
    shell = mat(*RED, rough=.4, grime=.2)
    brass = mat(212, 170, 80, metal=.8, rough=.3)
    for k in range(18):
        x = -.32 + (k % 6) * .13
        y = -.16 + (k // 6) * .15
        cyl(.035, .14, (x, y, .4), shell, (0, (k * 13) % 30 - 15, 0), seg=10)
        cyl(.037, .03, (x, y, .34), brass, seg=10)
    return 1.0, .8


def range_cow_target():
    ply = mat(232, 226, 210, rough=.8, grime=.45)
    spot = mat(30, 26, 24, rough=.8, grime=.3)
    box(1.3, .04, .62, (0, 0, .92), ply)
    box(.34, .04, .36, (.78, 0, 1.12), ply)
    for x, z, sx in ((-.35, 1.0, .3), (.15, .82, .26), (.4, 1.06, .2)):
        box(sx, .045, sx * .7, (x, -.004, z), spot, (0, (x * 90) % 40 - 20, 0))
    box(.1, .045, .06, (.86, -.004, 1.22), spot)
    box(.18, .045, .1, (.9, -.004, .98), mat(230, 160, 160))
    for x in (-.5, -.3, .3, .5):
        box(.08, .04, .6, (x, 0, .3), ply)
    _rings(.17, (-.05, -.02, .94), (90, 0, 0), [RED, CREAM, RED])
    for x in (-.45, .45):
        box(.06, .06, .9, (x, .1, .45), mat(*WOOD, planks=4.0), (20, 0, 0))
    return 1.7, 1.55


def range_duck():
    tin = mat(232, 190, 60, metal=.5, rough=.45, grime=.35)
    ball(.2, (0, 0, .26), tin, (1.4, .12, .8))
    ball(.11, (.24, 0, .44), tin, (1, .12, 1))
    box(.12, .02, .05, (.38, 0, .42), mat(230, 110, 30, metal=.4))
    ball(.025, (.27, -.03, .48), mat(20, 20, 20, grime=0))
    box(.05, .02, .14, (0, 0, .06), mat(80, 80, 80, metal=.6))
    _rings(.06, (-.05, -.03, .26), (90, 0, 0), [RED, CREAM])
    return .8, .7


def range_bench():
    wood = mat(*GREY_WOOD, planks=9.0, grime=.55)
    for y in (-.205, 0, .205):
        _rounded_box((1.4, .19, .062), (0, y, .72), wood, .013)
    for x in (-.6, .6):
        for y in (-.24, .24):
            box(.07, .07, .72, (x, y, .36), wood)
    box(1.3, .06, .1, (0, .25, .2), wood)
    burlap = mat(160, 136, 92, planks=20.0, grime=.6)
    _rounded_box((.34, .22, .14), (-.3, -.05, .82), burlap, .043)
    _rounded_box((.20, .18, .12), (.25, .05, .81), burlap, .034)
    # A spotting scope on its legs and a coffee can of brass.
    cyl(.035, .3, (.45, -.05, .9), mat(40, 40, 44, metal=.7, rough=.3), (0, 75, 20), seg=10)
    for k in range(3):
        cyl(.008, .18, (.45 + (k - 1) * .04, -.05, .8), mat(40, 40, 40), (0, (k - 1) * 20, 0), seg=4)
    cyl(.07, .14, (-.55, .1, .82), mat(*RED, metal=.4), seg=12)
    for k in range(4):
        cyl(.012, .05, (-.55 + (k - 1.5) * .025, .1, .9), mat(212, 170, 80, metal=.8), seg=6)
    return 1.6, 1.05


def range_scoreboard():
    frame = mat(*WOOD, planks=5.0, grime=.5)
    for s in (1, -1):
        box(.1, .1, 2.4, (s * .9, .05, 1.2), frame)
    board = mat(36, 46, 38, rough=.9, grime=.3)
    box(1.8, .06, 1.0, (0, 0, 1.7), board)
    box(1.9, .1, .08, (0, 0, 2.24), frame)
    box(1.9, .1, .08, (0, 0, 1.16), frame)
    brass = mat(154, 123, 74, metal=.47, rough=.57, grime=.54)
    for x in (-.91, .91):
        for z in (1.18, 2.2):
            box(.096, .033, .101, (x, -.068, z), brass)
            cyl(.018, .02, (x, -.087, z), mat(*STEEL, metal=.68), (90, 0, 0), seg=6)
    for x in (-.59, -.30, 0, .29, .58):
        box(.016, .016, .79, (x + .09, -.036, 1.70), mat(78, 87, 66, rough=.6, grime=.5))
    chalk = mat(230, 230, 220, rough=.9, grime=.2)
    for row in range(4):
        for k in range(5):
            box(.12 + (k * 7 % 3) * .05, .01, .025, (-.7 + k * .3, -.035, 2.05 - row * .22), chalk)
    box(.5, .1, .06, (0, -.05, 1.1), mat(150, 120, 80))
    return 2.1, 2.5


def range_hay_bale():
    hay = mat(168, 128, 52, planks=30.0, grime=.55)
    box(.9, .5, .45, (0, 0, .23), hay)
    for x in (-.25, .25):
        box(.02, .52, .47, (x, 0, .23), mat(90, 70, 40))
    box(.9, .5, .45, (.1, .05, .68), hay, (0, 0, 12))
    return 1.2, 1.05


RANGE = {
    "range_gun_rack": range_gun_rack, "range_lever": range_lever, "range_dummy": range_dummy,
    "range_pin": range_pin, "range_pin_down": range_pin_down, "range_target": range_target,
    "range_gong": range_gong, "range_sandbags": range_sandbags,
    "range_floodlight": range_floodlight, "range_loudspeaker": range_loudspeaker,
    "range_ammo_crate": range_ammo_crate, "range_cow_target": range_cow_target,
    "range_duck": range_duck, "range_bench": range_bench, "range_scoreboard": range_scoreboard,
    "range_hay_bale": range_hay_bale,
}
for _k, _tilt in enumerate(PIN_TILTS):
    for _j, _yaw in enumerate(PIN_YAWS):
        RANGE["range_pin_t%d_%d" % (_k + 1, _j)] = _pin_pose(_tilt, _yaw)
PROPS.clear()
PROPS.update(RANGE)
# Targets face the shooter: rendered face on, stood up in the game facing the
# player (or flat on a plane, as the cows are).
FLAT.update({"range_target", "range_gong", "range_cow_target", "range_duck", "range_scoreboard"})
main()
