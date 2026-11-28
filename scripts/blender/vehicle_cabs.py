"""The vehicles' seat views: what the driver of the bayou's airboat, the
speedway's stock car and Hickston's riding mower sees of their own vehicle
from the seat (godot/src/view3d/cab_layer.gd draws it, close to the eye, over
the world). Each is modelled with the town props' shapes and materials
(town_props.py, which this runs, with every chapter's props), in the same
colours as the vehicle's own model seen from outside (props_bayou.py
airboat, props_speedway.py stock_car, town_props.py tractor), with more of
what a driver sees up close: the airboat's deck, rails, bow, cooler, rope
and the big fan cage behind; the car's hood, scoop, pillars, windscreen
bars, dash, window net and fuzzy dice; the mower's hood, grille, fenders,
deck and its beer. Mundell's hands (his skin, the red and black check of his
sleeves) hold the controls.

    blender -b -P scripts/blender/export_meshes.py -- <out dir> <names|all> vehicle_cabs.py

Coordinates are the driver's eye at the origin (map units, nose to +X, the
driver's left +Y, up +Z), the floor `eye` below (vehicles.cfg). A cab is
several parts (export_meshes.py writes each as mesh `look_<part>` in one glb
with one texture): `body`, which stands still with the vehicle, and moving
parts (the wheel with the hands on it, a stick, needles, a lever, the fan's
prop), each modelled where it sits and moved so its pivot is the origin;
CAB_PIVOTS (written to cabs.json beside the glbs) says where each pivot is
and the axis it turns about. godot/tools/art/build_cab_meshes.gd runs this.
Everything is modelled here from scratch.
"""
import json
import os

_HERE = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(_HERE, "town_props.py"), encoding="utf-8") as _lib:
    _source = _lib.read()
exec(_source[: _source.rstrip().rfind("main()")], globals())
from mathutils import Matrix  # noqa: E402

_town_stage = stage
# The cab's own light, seen from the seat: the key from ahead, right and
# above (the town's comes from behind the camera that drew the sprites,
# which from the seat lights the backs of the hands and the hood flat), a
# fill from the left, a rim from behind.
CAB_LIGHTS = {"key": ((-.55, .45, -.7), 4.4), "fill": ((.3, -.7, -.35), .8), "rim": ((.6, .3, -.5), 1.2)}


def stage():
    scene, camera = _town_stage()
    for name, (travel, power) in CAB_LIGHTS.items():
        ob = bpy.data.objects.get(name)
        if ob is not None:
            ob.rotation_euler = Vector(travel).to_track_quat("-Z", "Y").to_euler()
            ob.data.energy = power
    return scene, camera

CREAM_FACE = (226, 212, 168)
NEEDLE_RED = (206, 44, 26)


# ------------------------------------------------------------------ helpers
def rod(p0, p1, r, m, seg=10, r1=None):
    """A round bar from p0 to p1 (`r1` its radius at p1)."""
    a, b = Vector(p0), Vector(p1)
    d = b - a
    rot = [math.degrees(v) for v in d.normalized().to_track_quat("Z", "Y").to_euler()]
    return cyl(r, d.length, (a + b) / 2, m, rot, seg=seg, top=r1)


def torus(R, r, loc, m, rot=(0, 0, 0), seg=28, minor=8):
    """A ring of round bar `R` across its middle, lying flat until turned."""
    bm = bmesh.new()
    for i in range(seg):
        a = i * math.tau / seg
        for j in range(minor):
            b = j * math.tau / minor
            bm.verts.new(((R + r * math.cos(b)) * math.cos(a), (R + r * math.cos(b)) * math.sin(a), r * math.sin(b)))
    bm.verts.ensure_lookup_table()
    for i in range(seg):
        for j in range(minor):
            i2, j2 = (i + 1) % seg, (j + 1) % minor
            bm.faces.new((bm.verts[i * minor + j], bm.verts[i2 * minor + j],
                          bm.verts[i2 * minor + j2], bm.verts[i * minor + j2]))
    ob = place(bm, m, loc, rot)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def blob(r, loc, m, x_axis, y_axis, scale=(1, 1, 1)):
    """A ball `r` across, stretched by `scale` along its own axes, turned so
    its x and y axes lie along x_axis and y_axis."""
    x = Vector(x_axis).normalized()
    z = x.cross(Vector(y_axis)).normalized()
    y = z.cross(x)
    ob = ball(r, loc, m, scale)
    ob.rotation_euler = Matrix((x, y, z)).transposed().to_euler()
    return ob


def frame(loc, rot):
    """An empty under ROOT at loc turned by rot (degrees): parts built under it
    (ROOT pointed at it for a while) take its place and turn."""
    e = bpy.data.objects.new("sub", None)
    bpy.context.scene.collection.objects.link(e)
    e.parent = ROOT
    e.location = loc
    e.rotation_euler = Euler([math.radians(a) for a in rot])
    return e


class Under:
    """with Under(frame): shapes made inside it hang from that frame."""

    def __init__(self, sub):
        self.sub = sub

    def __enter__(self):
        global ROOT
        self.old = ROOT
        ROOT = self.sub
        return self.sub

    def __exit__(self, *_):
        global ROOT
        ROOT = self.old


def pivot(p):
    """Moves what this part made so its pivot `p` is the origin."""
    ROOT.location = (-p[0], -p[1], -p[2])


# Mundell's hands: the skin and the flannel cuff of the photographed hand in
# the crowbar's first-person plate (source_art/crowbar_plate.png, the same
# hand every gun cel is held in: godot/tools/art/build_weapon_views.gd), cut
# from it and laid on the cab hands, so they are the same weathered skin and
# the same red and black check.
PLATE = os.path.join(_HERE, "..", "..", "source_art", "crowbar_plate.png")
# Opaque patches of the plate (left, top, right, bottom in its pixels): the
# back of the hand, the flannel at the wrist.
SKIN_CROP = (392, 232, 432, 266)
SLEEVE_CROP = (500, 388, 586, 420)
# How many times a patch repeats a cell (a patch is about 3.6 cm of hand).
SKIN_TILE = 16.0
# The cel hands' mid tone (gun_slingblade_idle's hand, the middle of its
# skin pixels).
CEL_SKIN = (132, 93, 72)
SLEEVE_TILE = 22.0


def _crop(box, name):
    """A patch of the plate as an image of its own (opaque)."""
    if name in bpy.data.images:
        return bpy.data.images[name]
    src = bpy.data.images.load(os.path.abspath(PLATE), check_existing=True)
    w, h = src.size
    px = list(src.pixels)
    x0, y0, x1, y1 = box
    cw, ch = x1 - x0, y1 - y0
    img = bpy.data.images.new(name, cw, ch, alpha=False)
    out = [1.0] * (cw * ch * 4)
    for yy in range(ch):
        sy = h - 1 - (y0 + yy)
        ty = ch - 1 - yy
        for xx in range(cw):
            si = (sy * w + x0 + xx) * 4
            ti = (ty * cw + xx) * 4
            out[ti:ti + 3] = px[si:si + 3]
    img.pixels = out
    return img


def photo_mat(box, tile, name, rough=.7, deep=1.0, flat=None):
    """A material painted with a patch of the plate, repeated over each part
    from its own coordinates (box projection)."""
    key = ("photo", name)
    if key in MATS:
        return MATS[key]
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    coord = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (tile, tile, tile)
    nt.links.new(coord.outputs["Object"], mapping.inputs["Vector"])
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = _crop(box, name + "_patch")
    tex.projection = "BOX"
    tex.projection_blend = .35
    try:
        tex.extension = "MIRROR"
    except Exception:
        tex.extension = "REPEAT"
    nt.links.new(mapping.outputs["Vector"], tex.inputs["Vector"])
    shade = nt.nodes.new("ShaderNodeMix")
    shade.data_type = "RGBA"
    shade.blend_type = "MULTIPLY"
    shade.inputs["Factor"].default_value = 1.0
    nt.links.new(tex.outputs["Color"], shade.inputs["A"])
    shade.inputs["B"].default_value = (deep, deep * .96, deep * .94, 1)
    colour = shade.outputs["Result"]
    if flat is not None:
        # Evened toward a flat tone: the photograph's pores and hairs read as
        # grey speckle a few texels across.
        even = nt.nodes.new("ShaderNodeMix")
        even.data_type = "RGBA"
        even.inputs["Factor"].default_value = .5
        nt.links.new(colour, even.inputs["A"])
        even.inputs["B"].default_value = (lin(flat[0]), lin(flat[1]), lin(flat[2]), 1)
        colour = even.outputs["Result"]
    nt.links.new(colour, bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = rough
    for socket in ("Specular IOR Level", "Specular"):
        if socket in bsdf.inputs:
            bsdf.inputs[socket].default_value = .15
    MATS[key] = m
    return m


def skin():
    return photo_mat(SKIN_CROP, SKIN_TILE, "hand_skin", .9, .9, CEL_SKIN)


def sleeve():
    return photo_mat(SLEEVE_CROP, SLEEVE_TILE, "hand_sleeve", .95)


def obox(size, center, x_axis, y_axis, m):
    """A box `size` along its own axes, turned so they lie along x_axis and
    y_axis (z their cross)."""
    x = Vector(x_axis).normalized()
    z = x.cross(Vector(y_axis)).normalized()
    y = z.cross(x)
    ob = box(size[0], size[1], size[2], center, m)
    ob.rotation_euler = Matrix((x, y, z)).transposed().to_euler()
    return ob


def fist(at, bar, elbow, bar_r=.02, k=1.0, face=None):
    """Mundell's hand closed round a bar `bar_r` thick through `at`, running
    along `bar`, its forearm in the checked sleeve off toward `elbow`; the
    back of the hand toward his eye (the origin), or `face`. Four fingers in three
    joints wrap over the bar's far side and curl in under it, knuckles
    standing out, the thumb round under them; the skin and cuff are the
    photographed hand's (photo_mat)."""
    p, d = Vector(at), Vector(bar).normalized()
    e = Vector(elbow) - p
    b = (e - d * e.dot(d)).normalized()
    f = -b
    u = d.cross(f)
    if u.dot(-p if face is None else Vector(face)) < 0:
        d, u = -d, -u
    flesh = skin()

    def round_at(phi, r, along):
        a = math.radians(phi)
        return p + (u * math.cos(a) + f * math.sin(a)) * r + d * along

    # The back of the hand over the bar, and the palm under it.
    blob(1.0, p + u * (bar_r + .012 * k) + b * .036 * k, flesh, d, b, (.046 * k, .052 * k, .017 * k))
    blob(1.0, p - u * bar_r * .3 + b * (bar_r + .028 * k), flesh, d, b, (.044 * k, .034 * k, .022 * k))
    # Four fingers, index to little: knuckle, three joints round the bar.
    for along, size, thick in ((.0285, 1.0, .0105), (.0095, 1.06, .011), (-.0095, 1.0, .0105), (-.028, .84, .0094)):
        rf = thick * k
        a = along * k
        knuckle = round_at(18, bar_r + .02 * k, a) + b * .004 * k
        blob(1.0, knuckle, flesh, d, u, (rf * 1.15, rf * .9, rf * 1.2))
        joints = [knuckle, round_at(18 + 75 * size, bar_r + rf, a), round_at(18 + 140 * size, bar_r + rf, a),
                  round_at(18 + 190 * size, bar_r + rf * .85, a)]
        for j in range(3):
            rod(joints[j], joints[j + 1], rf * (1.0 - .1 * j), flesh, seg=8, r1=rf * (.9 - .1 * j))
            ball(rf * (.95 - .1 * j), joints[j + 1], flesh)
    # The thumb round under the bar toward the index finger.
    t0 = p - u * (bar_r * .4) + b * (bar_r + .02 * k) + d * .03 * k
    t1 = round_at(-150, bar_r + .012 * k, .042 * k)
    t2 = round_at(-205, bar_r + .011 * k, .05 * k)
    for a0, a1, r in ((t0, t1, .012), (t1, t2, .0105)):
        rod(a0, a1, r * k, flesh, seg=8, r1=r * .9 * k)
        ball(r * .95 * k, a1, flesh)
    # The wrist, the cuff and the forearm back to the elbow.
    wrist = p + b * (bar_r + .06 * k) + u * .004
    w2 = Vector(elbow)
    away = (w2 - wrist).normalized()
    rod(wrist - away * .02 * k, wrist + away * .06 * k, .026 * k, flesh, seg=12, r1=.029 * k)
    cuff = wrist + away * .06 * k
    rod(cuff, cuff + away * .03 * k, .039 * k, sleeve(), seg=14, r1=.041 * k)
    rod(cuff + away * .028 * k, w2, .04 * k, sleeve(), seg=14, r1=.05 * k)


def gauge(at, rot, r, m_rim):
    """A round gauge in its pod, its face toward local +Z of `rot` (the
    needle is a part of its own): a lit cream face, ticks round it."""
    sub = frame(at, rot)
    with Under(sub):
        cyl(r * 1.22, .05, (0, 0, -.022), m_rim, seg=20)
        cyl(r, .012, (0, 0, .004), mat(*CREAM_FACE, rough=.5, grime=.2, emit=.35), seg=24)
        tick = mat(30, 26, 22, grime=.1)
        for k in range(9):
            a = math.radians(135 - k * 33.75)
            box(r * .26, r * .08, .006, (math.cos(a) * r * .78, math.sin(a) * r * .78, .011), tick, (0, 0, math.degrees(a)))
        # The red line at the top of the scale.
        a = math.radians(135 - 8 * 33.75)
        box(r * .34, r * .14, .006, (math.cos(a) * r * .76, math.sin(a) * r * .76, .012), mat(*NEEDLE_RED, grime=.1), (0, 0, math.degrees(a)))
    return sub


def needle(at, rot, r):
    """A gauge's needle at rest pointing up the face (local +X of `rot`)."""
    sub = frame(at, rot)
    with Under(sub):
        box(r * .85, r * .12, .006, (r * .36, 0, .018), mat(*NEEDLE_RED, rough=.4, grime=.05, emit=.3))
        cyl(r * .16, .012, (0, 0, .02), mat(30, 28, 26, grime=.1), seg=10)


# ----------------------------------------------------------------- airboat
AB_FLOOR = -1.55
AB_DECK = AB_FLOOR + .36
AB_FAN = (-1.06, 0.0, -.36)
# The rudder stick rises from the deck out on his left, leaning back a
# little; his fist holds it near its top, the black-gripped end and its knob
# standing above the fist, the steel shaft below it.
AB_STICK = (1.0, .45, AB_DECK + .03)
AB_STICK_TOP = (AB_STICK[0] - .04, AB_STICK[1], AB_STICK[2] + .69)
AB_GRIP = (AB_STICK[0] - .031, AB_STICK[1], AB_STICK[2] + .54)
AB_POD = (2.0, .6, -.85)
AB_POD_ROT = (12, -58, 0)


def _ab_mats():
    return (mat(*ALUMINUM, metal=.7, rough=.4, grime=.65), mat(43, 77, 73, metal=.36, rough=.56, grime=.72),
            mat(40, 40, 42, metal=.5, grime=.5))


def cab_airboat_body():
    alu, paint, dark = _ab_mats()
    red = mat(120, 40, 34, rough=.7, grime=.5)
    wood = mat(*GREY_WOOD, planks=6.0, grime=.5)
    deck = AB_DECK
    # The flat aluminium deck, ribbed and riveted.
    box(3.6, 1.32, .05, (.3, 0, deck - .025), alu)
    for x in (-.2, .3, .8, 1.3, 1.75, 2.15, 2.45):
        box(.025, 1.26, .014, (x, 0, deck + .006), alu)
    # The green gunwales down both sides, capped with a rub rail.
    for s in (1, -1):
        box(3.7, .07, .2, (.35, s * .68, deck + .08), paint)
        box(3.72, .11, .026, (.35, s * .68, deck + .19), alu)
        box(.8, .07, .2, (2.56, s * .68, deck + .19), paint, (0, -16, 0))
        box(.82, .11, .026, (2.56, s * .68, deck + .3), alu, (0, -16, 0))
        for x in (.47, .93, 1.39, 1.85):
            cyl(.013, .014, (x, s * .678, deck + .202), dark, seg=6)
        # Cleats, a dent, scuffed paint.
        box(.13, .035, .035, (2.3, s * .6, deck + .03), dark)
        ball(.07, (1.9 - s * .3, s * .64, deck + .1), mat(30, 52, 38, grime=.3), (1.5, .3, 1.0))
    # The bow rising, capped across, a lamp on a short pole.
    box(.8, 1.32, .05, (2.56, 0, deck + .11), alu, (0, -16, 0))
    box(.07, 1.44, .3, (2.95, 0, deck + .28), paint, (0, -16, 0))
    box(.09, 1.46, .03, (2.97, 0, deck + .44), alu, (0, -16, 0))
    rod((2.85, 0, deck + .4), (2.85, 0, deck + .62), .015, dark)
    cyl(.035, .05, (2.85, 0, deck + .64), mat(230, 120, 60, rough=.3, emit=.5), seg=10)
    # A plank deck up front, a cooler strapped down, a coil of rope, a jug.
    box(1.0, .95, .025, (1.85, 0, deck + .012), wood)
    cooler = mat(186, 40, 32, rough=.6, grime=.55)
    box(.48, .34, .28, (2.15, .3, deck + .15), cooler)
    box(.5, .36, .05, (2.15, .3, deck + .31), mat(232, 226, 210, rough=.6, grime=.5))
    box(.04, .37, .3, (2.15, .3, deck + .16), mat(30, 30, 32, grime=.2))
    # The high seat on its frame, the footrest, the throttle pedal.
    box(.5, .56, .05, (-.08, 0, -.97), alu)
    for x in (-.28, .14):
        for y in (-.22, .22):
            box(.04, .04, -.97 - deck, (x, y, (deck - .97) / 2), alu)
    box(.44, .46, .11, (-.1, 0, -.89), red)
    box(.08, .46, .42, (-.34, 0, -.62), red)
    rod((.48, -.3, deck + .2), (.48, .3, deck + .2), .02, alu)
    for s in (1, -1):
        rod((.48, s * .28, deck + .2), (.14, s * .22, -.97), .015, alu)
    box(.11, .13, .03, (.56, -.15, deck + .14), dark, (0, -20, 0))
    # The tach on a bracket off the left rail ahead of the stick (its needle a part).
    rod((AB_POD[0] + .03, .68, deck + .2), (AB_POD[0] + .02, AB_POD[1] + .02, AB_POD[2] - .05), .016, dark)
    gauge(AB_POD, AB_POD_ROT, .055, dark)
    # The rudder stick's bracket on the deck.
    box(.1, .06, .05, (AB_STICK[0], AB_STICK[1], deck + .025), dark)
    # Behind the seat: the engine, its filter and pipes, the caged fan.
    box(.45, .7, .45, (-.8, 0, deck + .26), dark)
    cyl(.12, .09, (-.68, .24, deck + .52), red, seg=14)
    for s in (1, -1):
        rod((-.66, s * .36, deck + .3), (-.9, s * .44, deck + .62), .03, mat(70, 64, 58, metal=.6, grime=.7))
    fx, _fy, fz = AB_FAN
    ring = .92
    for k in range(24):
        a0, a1 = k * math.tau / 24, (k + 1) * math.tau / 24
        beam((fx - .1, math.cos(a0) * ring, fz + math.sin(a0) * ring),
             (fx - .1, math.cos(a1) * ring, fz + math.sin(a1) * ring), .05, alu)
    for k in range(6):
        a = k * math.tau / 6 + .26
        beam((fx - .16, 0, fz), (fx - .16, math.cos(a) * ring, fz + math.sin(a) * ring), .025, alu)
    for k in range(10):
        y = -.9 + k * .2
        top = fz + math.sqrt(max(0.0, ring * ring - y * y))
        bot = max(deck + .05, fz - math.sqrt(max(0.0, ring * ring - y * y)))
        beam((fx - .22, y, bot), (fx - .22, y, top), .015, alu)
    for s in (1, -1):
        beam((fx - .05, s * .5, deck), (fx - .05, s * .62, fz + .2), .05, alu)
        box(.4, .03, .5, (fx - .5, s * .3, deck + .3), paint)
    cyl(.06, .16, (fx + .12, 0, fz), mat(196, 198, 194, metal=.8, rough=.25, grime=.1), (0, 90, 0), seg=16)


def cab_airboat_stick():
    # The rudder stick on his left: a steel shaft up from its bracket, a
    # black rubber grip at its top under his fist, a round black knob.
    p = Vector(AB_STICK)
    top = Vector(AB_STICK_TOP)
    steel = mat(150, 154, 156, metal=.8, rough=.3, grime=.35)
    black = mat(26, 24, 24, rough=.85, grime=.15)
    rod(p, top, .016, steel)
    grip = Vector(AB_GRIP)
    rod(grip - Vector((0, 0, .06)), top + Vector((0, 0, .005)), .024, black, seg=12)
    for k in range(4):
        cyl(.026, .006, grip + (top - grip) * (.2 + k * .22), black, seg=12)
    ball(.034, top + Vector((0, 0, .02)), black)
    cyl(.03, .05, p + Vector((0, 0, .03)), mat(40, 40, 42, metal=.5, grime=.5), seg=12)
    pivot(AB_STICK)


def cab_airboat_hand():
    # His left hand on the stick's grip (it follows the grip, cab_layer.gd).
    fist(AB_GRIP, (0, 0, 1), (.74, .52, -1.3), bar_r=.024)
    pivot(AB_GRIP)


def cab_airboat_needle():
    needle(AB_POD, AB_POD_ROT, .055)
    pivot(AB_POD)


def cab_airboat_prop():
    # The two-bladed varnished wooden prop, red tips, an aluminium hub.
    wood = mat(196, 150, 92, rough=.35, planks=3.0, grime=.25)
    tip = mat(196, 40, 30, rough=.4, grime=.2)
    fx, _fy, fz = AB_FAN
    for s in (1, -1):
        box(.04, .7, .16, (fx, s * .44, fz), wood, (s * 18, 0, 0))
        box(.042, .1, .14, (fx, s * .82, fz), tip, (s * 18, 0, 0))
    cyl(.05, .12, (fx, 0, fz), mat(200, 202, 198, metal=.8, rough=.25, grime=.1), (0, 90, 0), seg=16)
    cyl(.02, .14, (fx, 0, fz), mat(60, 58, 56, metal=.6, grime=.1), (0, 90, 0), seg=10)
    pivot(AB_FAN)


def cab_airboat_blur():
    # The prop spinning: a pale disc of wood streaked round, red at its rim
    # (drawn stippled over the cage, cab.gdshader `opacity`).
    fx, _fy, fz = AB_FAN
    cyl(.8, .006, (fx - .01, 0, fz), mat(176, 140, 96, rough=.6, planks=9.0, grime=.35), (0, 90, 0), seg=40)
    torus(.82, .03, (fx - .01, 0, fz), mat(176, 52, 40, rough=.5, grime=.2), (0, 90, 0), seg=40, minor=6)
    pivot(AB_FAN)


# --------------------------------------------------------------- stock car
CAR_FLOOR = -.82
CAR_HOOD = -.19
CAR_WHEEL = (.5, 0.0, -.25)
CAR_WHEEL_ROT = (0, -62, 0)
CAR_RIM = .17
CAR_GRIP = 60
CAR_SPEEDO = (.665, .3, -.235)
CAR_TACH = (.665, -.3, -.235)
CAR_GAUGE_ROT = (0, -78, 0)


def _car_mats():
    paint = mat(150, 65, 51, metal=.29, rough=.6, grime=.76)
    cream = mat(208, 187, 140, rough=.54, grime=.61)
    dark = mat(44, 42, 42, rough=.6, grime=.3, emit=.08)
    cage = mat(156, 158, 154, metal=.7, rough=.4, grime=.4)
    vinyl = mat(104, 74, 52, rough=.8, grime=.55, emit=.12)
    return paint, cream, dark, cage, vinyl


def _car_frame():
    """The wheel's middle, its up the rim, its left and its face."""
    rot = Euler([math.radians(a) for a in CAR_WHEEL_ROT]).to_matrix()
    return Vector(CAR_WHEEL), rot @ Vector((1, 0, 0)), rot @ Vector((0, 1, 0)), rot @ Vector((0, 0, 1))


def car_grip(side):
    """Where his hand holds the rim: `side` 1 his left (eleven o'clock), -1
    his right (one o'clock)."""
    centre, up, left, _normal = _car_frame()
    a = math.radians(CAR_GRIP)
    return centre + (up * math.cos(a) + left * math.sin(a) * side) * CAR_RIM


def cab_car_body():
    paint, cream, dark, cage, vinyl = _car_mats()
    hood = CAR_HOOD
    primer = mat(118, 116, 108, rough=.95, grime=.6)
    chrome = mat(*CHROME, metal=.8, rough=.3, grime=.4)
    # The long red hood, its nose wedged down, two old cream stripes up it.
    box(1.22, 1.08, .12, (1.445, 0, hood - .06), paint)
    box(.48, 1.04, .1, (2.27, 0, hood - .1), paint, (0, 10, 0))
    for s in (1, -1):
        box(1.5, .14, .012, (1.6, s * .15, hood + .003), cream)
        box(.66, .17, .06, (1.75, s * .48, hood + .02), paint)
        cyl(.022, .025, (2.0, s * .4, hood + .012), chrome, seg=8)
    # A scoop up the middle, a primer patch, a dent.
    box(.42, .32, .07, (1.25, 0, hood + .035), paint)
    box(.025, .27, .05, (1.46, 0, hood + .035), dark)
    box(.5, .4, .01, (1.75, -.26, hood + .006), primer, (0, 0, 8))
    ball(.12, (1.9, .32, hood + .01), mat(160, 156, 146, grime=.6), (1.6, 1.0, .12))
    # Track mud thrown up over the nose, a rust bloom, a number on the scoop.
    mud = mat(96, 78, 58, rough=.95, grime=.6)
    for k, (x, y, r) in enumerate(((2.15, .3, .1), (2.25, -.1, .14), (2.05, -.4, .08), (2.3, .42, .09),
                                   (1.95, .05, .06), (2.4, .15, .12))):
        ball(r, (x, y, hood - .02 - (x - 2.0) * .17), mud, (1.5, 1.1, .1))
    ball(.07, (1.1, .44, hood + .006), mat(128, 66, 36, rough=.9, grime=.5), (1.4, 1.0, .1))
    box(.12, .12, .004, (1.27, 0, hood + .072), mat(236, 232, 220, rough=.6, grime=.4))
    box(.03, .07, .006, (1.27, 0, hood + .075), cream, (0, 0, 15))
    # The cowl, the dash's top, its face with two gauges, switches, tape.
    box(.06, 1.04, .04, (.82, 0, hood + .01), dark)
    box(.14, 1.0, .03, (.75, 0, -.215), vinyl)
    box(.03, .98, .2, (.69, 0, -.31), vinyl, (0, -8, 0))
    gauge(CAR_SPEEDO, CAR_GAUGE_ROT, .036, dark)
    gauge(CAR_TACH, CAR_GAUGE_ROT, .036, dark)
    cyl(.016, .01, (.672, 0, -.225), mat(200, 60, 30, rough=.3, emit=.4), (0, -78, 0), seg=10)
    for k in range(4):
        cyl(.009, .03, (.69, -.3 - k * .04, -.25), chrome, (0, -80, 0), seg=6)
    box(.12, .045, .004, (.76, .33, -.199), mat(170, 166, 156, rough=.6, grime=.3), (0, 0, 12))
    # The windscreen: A-pillars, the header, two steel bars, the roof.
    for s in (1, -1):
        beam((.82, s * .5, hood + .01), (.45, s * .44, .16), .055, paint)
        rod((.82, s * .14, hood + .01), (.45, s * .12, .16), .012, cage)
        box(.95, .06, .05, (.35, s * .5, hood + .02), paint)
        box(.9, .05, .04, (.0, s * .44, .17), paint)
    box(.06, .94, .05, (.45, 0, .17), paint)
    box(.86, .86, .012, (-.02, 0, .15), dark)
    # The mirror on the header, fuzzy dice hung from it.
    box(.03, .22, .065, (.47, 0, .125), dark)
    box(.006, .2, .05, (.453, 0, .125), mat(150, 160, 170, metal=.8, rough=.15))
    dice = mat(236, 232, 220, rough=.9, grime=.3)
    pips = mat(24, 20, 18, grime=.1)
    for k, (y, z, turn) in enumerate(((.035, .045, 20), (-.025, .03, -15))):
        rod((.47, y, .095), (.47, y, z + .02), .002, dark, seg=4)
        box(.024, .024, .024, (.47, y, z), dice, (turn, 10 * k, turn))
        ball(.005, (.457, y, z), pips)
    # The window net on his left, the roll cage round him.
    net = mat(20, 20, 22, rough=.8, grime=.1)
    for k in range(9):
        x = .76 - k * .1
        beam((x, .49, hood + .03), (x - .02, .45, .15), .008, net)
    for k in range(5):
        z = hood + .05 + k * .07
        beam((.78, .49 - k * .008, z), (-.1, .49 - k * .008, z), .008, net)
    for s in (1, -1):
        rod((.7, s * .4, hood + .02), (-.3, s * .4, .14), .022, cage)
        rod((-.3, s * .4, hood - .25), (-.3, s * .4, .14), .022, cage)
        rod((.6, s * .43, hood - .35), (-.25, s * .43, hood + .0), .022, cage)
    rod((-.3, .4, .14), (-.3, -.4, .14), .022, cage)
    # The race seat behind him, low enough to see the cage and the back
    # window over it, its padded shoulders.
    box(.06, .46, .5, (-.42, 0, -.36), vinyl)
    for s in (1, -1):
        box(.2, .05, .3, (-.33, s * .24, -.42), vinyl)
        ball(.06, (-.4, s * .17, -.12), vinyl, (1.0, 1.2, .8))
    # The back window's frame and the trunk lid and spoiler beyond it.
    white = _car_mats()[0]
    box(.05, .86, .04, (-.75, 0, .1), paint)
    for s in (1, -1):
        beam((-.75, s * .43, .1), (-1.0, s * .45, hood + .02), .05, paint)
    box(.5, 1.0, .05, (-1.25, 0, hood - .02), paint)
    box(.06, 1.02, .16, (-1.5, 0, hood + .06), paint, (0, -25, 0))


def cab_car_wheel():
    _white, red, dark, _cage, _vinyl = _car_mats()
    chrome = mat(*CHROME, metal=.8, rough=.3, grime=.4)
    leather = mat(98, 64, 40, rough=.7, grime=.4)
    tape = mat(150, 140, 112, rough=.8, grime=.35)
    R = CAR_RIM
    sub = frame(CAR_WHEEL, CAR_WHEEL_ROT)
    with Under(sub):
        torus(R, .018, (0, 0, 0), leather, seg=36, minor=8)
        for a in (75, -75, 135, -135):
            ra = math.radians(a)
            box(.05, .03, .048, (math.cos(ra) * R, math.sin(ra) * R, 0), tape, (0, 0, a))
        for a in (90, -90, 180):
            ra = math.radians(a)
            beam((0, 0, 0), (math.cos(ra) * R, math.sin(ra) * R, 0), .024, chrome, .008)
        cyl(.045, .03, (0, 0, .01), dark, seg=14)
        cyl(.03, .01, (0, 0, .027), red, seg=12)
    centre, _up, _left, normal = _car_frame()
    rod(centre, centre - normal * .25, .022, dark)
    pivot(CAR_WHEEL)


def _car_hand(side):
    centre, up, left, _normal = _car_frame()
    a = math.radians(CAR_GRIP)
    tangent = -up * math.sin(a) * side + left * math.cos(a)
    at = car_grip(side)
    fist(at, tangent, (.12, side * .32, -.8), bar_r=.018, k=.85)
    pivot(at)


def cab_car_hand_l():
    _car_hand(1)


def cab_car_hand_r():
    _car_hand(-1)


def cab_car_speed():
    needle(CAR_SPEEDO, CAR_GAUGE_ROT, .036)
    pivot(CAR_SPEEDO)


def cab_car_tach():
    needle(CAR_TACH, CAR_GAUGE_ROT, .036)
    pivot(CAR_TACH)


# ------------------------------------------------------------ riding mower
MOW_FLOOR = -1.2
MOW_WHEEL = (.45, 0.0, -.53)
MOW_WHEEL_ROT = (0, -42, 0)
MOW_RIM = .12
MOW_KNOB = -40
MOW_GRIP = 60
MOW_LEVER = (.66, .3, -.84)


def _mow_mats():
    paint = mat(150, 46, 30, metal=.3, rough=.6, grime=.75)
    rim = mat(196, 170, 90, metal=.4, grime=.6)
    dark = mat(60, 58, 56, metal=.6, grime=.6)
    black = mat(30, 30, 30, rough=.8, grime=.2)
    return paint, rim, dark, black


def mow_grip():
    """Where his left hand holds the rim (ten o'clock), and the rim's way there."""
    rot = Euler([math.radians(a) for a in MOW_WHEEL_ROT]).to_matrix()
    a = math.radians(MOW_GRIP)
    at = Vector(MOW_WHEEL) + rot @ Vector((math.cos(a) * MOW_RIM, math.sin(a) * MOW_RIM, 0))
    return at, rot @ Vector((-math.sin(a), math.cos(a), 0))


def cab_mower_body():
    paint, rim, dark, black = _mow_mats()
    floor = MOW_FLOOR
    chrome = mat(*CHROME, metal=.8, rough=.3, grime=.4)
    deck_m = mat(74, 76, 72, metal=.5, rough=.6, grime=.7)
    stripe = mat(206, 176, 70, rough=.5, grime=.3)
    # The hood, sloping a little to the grille, a pinstripe down each side.
    box(.72, .46, .28, (.97, 0, -.73), paint, (0, -4, 0))
    box(.7, .36, .05, (.97, 0, -.585), paint, (0, -4, 0))
    for s in (1, -1):
        box(.7, .006, .025, (.97, s * .232, -.63), stripe, (0, -4, 0))
        box(.7, .006, .02, (.97, s * .181, -.56), stripe, (0, -4, 0))
        # Lamps in pods on the hood's front corners.
        cyl(.042, .07, (1.24, s * .15, -.585), chrome, (0, 80, 0), seg=14)
        cyl(.034, .01, (1.276, s * .15, -.585), mat(240, 226, 170, rough=.3, emit=.5), (0, 80, 0), seg=14)
    ball(.03, (1.31, 0, -.6), chrome, (1.8, .7, 1.0))
    cyl(.035, .02, (.76, .12, -.565), chrome, seg=12)
    # Pressed ribs on the steel hood.
    for y in (-.101, .101):
        box(.52, .014, .008, (.987, y, -.553), paint, (0, -4, 0))
    # The grille at the front.
    box(.03, .42, .24, (1.33, 0, -.76), dark, (0, -4, 0))
    for k in range(5):
        box(.035, .4, .012, (1.34, 0, -.85 + k * .045), chrome, (0, -4, 0))
    # A little exhaust stack on the hood, its rain cap.
    rod((.82, -.17, -.6), (.84, -.17, -.43), .02, black)
    box(.05, .05, .01, (.845, -.17, -.425), dark, (0, -25, 0))
    # The console below the wheel, a key and a choke.
    box(.16, .5, .24, (.56, 0, -.78), paint)
    box(.12, .44, .02, (.56, 0, -.655), black)
    cyl(.012, .03, (.52, .15, -.645), chrome, (0, -60, 0), seg=6)
    box(.025, .02, .03, (.51, .15, -.63), mat(200, 170, 60, metal=.5))
    cyl(.014, .03, (.52, -.15, -.645), black, (0, -60, 0), seg=8)
    # Fenders over the back wheels, the tyres under them, the front wheels.
    for s in (1, -1):
        box(.5, .16, .035, (-.22, s * .38, -.72), paint)
        box(.5, .02, .2, (-.22, s * .46, -.81), paint)
        wheel(.27, .16, (-.25, s * .43, floor + .27), rim, (90, 0, 0))
        wheel(.15, .1, (1.12, s * .27, floor + .15), rim, (90, 0, 0))
    # A beer in the cup holder on the left fender.
    cyl(.045, .03, (-.12, .38, -.7), black, seg=12)
    can = mat(196, 40, 36, metal=.6, rough=.35, grime=.3)
    cyl(.033, .12, (-.12, .38, -.64), can, seg=12)
    cyl(.03, .01, (-.12, .38, -.578), chrome, seg=12)
    # The seat, taped where it split.
    box(.4, .42, .08, (-.26, 0, -.82), black)
    box(.07, .42, .3, (-.48, 0, -.66), black)
    box(.2, .06, .006, (-.2, .1, -.777), mat(170, 166, 156, rough=.6, grime=.3), (0, 0, 30))
    # Footboards, and the cutting deck out in front, wider than the hood,
    # the chute out to the right, its little wheels at the corners.
    for s in (1, -1):
        box(.6, .2, .02, (.35, s * .34, -.98), dark)
        beam((1.3, s * .3, floor + .2), (.95, s * .26, -.97), .04, dark)
        cyl(.045, .04, (1.9, s * .62, floor + .045), black, (90, 0, 0), seg=10)
    box(.62, 1.36, .1, (1.6, 0, floor + .14), deck_m)
    box(.64, 1.38, .03, (1.6, 0, floor + .2), deck_m)
    for s in (1, -1):
        box(.6, .02, .1, (1.6, s * .69, floor + .15), mat(150, 46, 30, metal=.3, rough=.6, grime=.8))
    box(.36, .26, .08, (1.55, -.8, floor + .12), deck_m, (10, 0, 0))
    cyl(.07, .02, (1.6, .2, floor + .22), dark, seg=12)
    cyl(.07, .02, (1.6, -.2, floor + .22), dark, seg=12)


def cab_mower_wheel():
    paint, rim, dark, black = _mow_mats()
    R = MOW_RIM
    sub = frame(MOW_WHEEL, MOW_WHEEL_ROT)
    ka = math.radians(MOW_KNOB)
    with Under(sub):
        torus(R, .016, (0, 0, 0), black, seg=28, minor=8)
        for a in (90, -90, 180):
            ra = math.radians(a)
            beam((0, 0, 0), (math.cos(ra) * R, math.sin(ra) * R, 0), .02, black, .008)
        cyl(.042, .03, (0, 0, .01), paint, seg=14)
        cyl(.024, .012, (0, 0, .03), rim, seg=12)
        # The spinner knob at one o'clock.
        kx, ky = math.cos(ka) * R, math.sin(ka) * R
        cyl(.012, .07, (kx, ky, .035), mat(*CHROME, metal=.8, rough=.3, grime=.4), seg=8)
        ball(.02, (kx, ky, .075), mat(200, 40, 34, rough=.4, grime=.2))
    normal = sub.rotation_euler.to_matrix() @ Vector((0, 0, 1))
    rod(MOW_WHEEL, Vector(MOW_WHEEL) - normal * .2, .025, black)
    pivot(MOW_WHEEL)


def cab_mower_hand():
    at, tangent = mow_grip()
    fist(at, tangent, (.08, .32, -1.05), bar_r=.016)
    pivot(at)


def cab_mower_lever():
    # The blade lever by the hood's left side: yellow knob, forward is on.
    p = Vector(MOW_LEVER)
    top = p + Vector((-.02, -.01, .24))
    rod(p, top, .012, mat(40, 40, 42, metal=.6, grime=.4))
    ball(.026, top, mat(222, 184, 44, rough=.4, grime=.3))
    pivot(MOW_LEVER)


# The cabs: name -> [(part, make)], body first. (Godot's glTF import reads a
# node name ending in "wheel" as a VehicleWheel3D: the wheel is "steer".)
CABS = {
    "cab_airboat": [("body", cab_airboat_body), ("stick", cab_airboat_stick), ("hand", cab_airboat_hand),
                    ("needle", cab_airboat_needle), ("prop", cab_airboat_prop), ("blur", cab_airboat_blur)],
    "cab_car": [("body", cab_car_body), ("steer", cab_car_wheel), ("hand_l", cab_car_hand_l),
                ("hand_r", cab_car_hand_r), ("speed", cab_car_speed), ("tach", cab_car_tach)],
    "cab_mower": [("body", cab_mower_body), ("steer", cab_mower_wheel), ("hand", cab_mower_hand),
                  ("lever", cab_mower_lever)],
}


def _axis_of(rot):
    """The local +Z of a frame turned by rot (degrees): a gauge's face."""
    return list(Euler([math.radians(a) for a in rot]).to_matrix() @ Vector((0, 0, 1)))


def _hand(at, follow, hub, axis, turn):
    """A hand riding a turning part: where it holds at rest, the part it
    follows (its pivot `hub`, its `axis`), how much of the turn its wrist
    takes."""
    return {"at": list(at), "axis": axis, "follow": follow, "hub": list(hub), "turn": turn}


# Each moving part's pivot and the axis it turns about (Blender's axes: x
# ahead, y left, z up), for the game (cabs.json); a hand rides another part.
CAB_PIVOTS = {
    "cab_airboat": {
        "eye": 1.55,
        "stick": {"at": list(AB_STICK), "axis": [1, 0, 0]},
        "hand": _hand(AB_GRIP, "stick", AB_STICK, [1, 0, 0], .5),
        "needle": {"at": list(AB_POD), "axis": _axis_of(AB_POD_ROT)},
        "prop": {"at": list(AB_FAN), "axis": [1, 0, 0]},
        "blur": {"at": list(AB_FAN), "axis": [1, 0, 0]},
    },
    "cab_car": {
        "eye": .82,
        "steer": {"at": list(CAR_WHEEL), "axis": _axis_of(CAR_WHEEL_ROT)},
        "hand_l": _hand(car_grip(1), "steer", CAR_WHEEL, _axis_of(CAR_WHEEL_ROT), .6),
        "hand_r": _hand(car_grip(-1), "steer", CAR_WHEEL, _axis_of(CAR_WHEEL_ROT), .6),
        "speed": {"at": list(CAR_SPEEDO), "axis": _axis_of(CAR_GAUGE_ROT)},
        "tach": {"at": list(CAR_TACH), "axis": _axis_of(CAR_GAUGE_ROT)},
    },
    "cab_mower": {
        "eye": 1.2,
        "steer": {"at": list(MOW_WHEEL), "axis": _axis_of(MOW_WHEEL_ROT)},
        "hand": _hand(mow_grip()[0], "steer", MOW_WHEEL, _axis_of(MOW_WHEEL_ROT), .6),
        "lever": {"at": list(MOW_LEVER), "axis": [0, 1, 0]},
    },
}

if "_OUT" in globals():
    os.makedirs(_OUT, exist_ok=True)
    with open(os.path.join(_OUT, "cabs.json"), "w", encoding="utf-8") as _f:
        json.dump(CAB_PIVOTS, _f, indent=1, sort_keys=True)
