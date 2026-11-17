"""The razorbacks of the county events' stampede (godot/src/event_herd.gd),
exec'd by enemy_actors.py into its own namespace after ACTORS is made, so
ball, limb, mat, T, R, ik, Vector and the rest are in scope. Built from
scratch: nothing is traced from another game or a photograph.

    hog     a feral razorback: wedge-built, the shoulders high and deep and the
            hams small, a long wedge of a head with a flat grey-pink disc of a
            snout and short tusks curling up out of the lower jaw, small mean
            eyes, pricked ears; a coarse coat of black-brown bristles grizzled
            at the tips, a ridge of long bristles standing up along the spine,
            a grey-brown belly, short legs on black cloven hooves, a thin tail
            with a tuft, mud caked up the legs and the belly.

His frames (own, so the cels and the model are just these):

    0               standing, head low, tail down
    r0..r3 (r4)     the gallop, four beats (r4 is r0 again: the loop's end),
                    the tail straight up as a running hog's is
    down            dead on his side, legs out

Every name here starts _hog (actors_hound.py, exec'd after this, has its own
_leg, _body and the rest). Seen side on (x along the body, head to +x, y away
from the camera, z up), turned a little to the camera for the cels; for the
model (FOR_MODEL) square, head toward -y, as the people are. Each leg is built
from pieces of fixed length posed by two-bone IK, so each piece is the same
part in every frame (export_actors.py matches parts by shape).
"""

HOG = dict(canvas=(1.75, 1.0), px=56)
HOG_CELS = [0, "r0", "r1", "r2", "r3", "r4", "down"]
PLAIN_KINDS = tuple(PLAIN_KINDS) + ("hog",)

# Leg pieces (metres): the front's upper arm, forearm and pastern; the hind's
# thigh, gaskin and hock-to-foot. Short and stout.
_HOG_ARM, _HOG_FORE, _HOG_PASTERN = .13, .13, .05
_HOG_THIGH, _HOG_GASKIN, _HOG_META = .14, .12, .08
# His head is big for him: a third of his length.
_HOG_HEAD = Matrix.Diagonal((1.45, 1.3, 1.3, 1))
_HOG_MATS = {}
# The coats: [base, bristle, tips, flecks a metre].
_HOG_COATS = {
    "coat": ((56, 43, 34), (24, 18, 14), (118, 98, 76), 170.),
    "ridge": ((22, 17, 14), (10, 8, 7), (84, 70, 56), 220.),
    "belly": ((78, 64, 52), (40, 32, 26), (112, 96, 80), 150.),
    "head": ((62, 49, 38), (26, 20, 16), (124, 104, 82), 200.),
}


def _hog_coat(which, size):
    """The bristle coat `which` for a part `size` across in its own
    coordinates: dark hair, darker streaks of bristle along the body, the
    tips grizzled pale here and there, mud caked up from the ground."""
    base, dark, tips, per_metre = _HOG_COATS[which]
    density = round(per_metre * size * 2) / 2
    key = (which, density)
    if key in _HOG_MATS and _HOG_MATS[key].name in bpy.data.materials:
        return _HOG_MATS[key]
    m = bpy.data.materials.new("hog%d" % len(_HOG_MATS))
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    bsdf.inputs["Roughness"].default_value = .92
    for name in ("Specular IOR Level", "Specular"):
        if name in bsdf.inputs:
            bsdf.inputs[name].default_value = .15
    coord = nt.nodes.new("ShaderNodeTexCoord")
    lb = tuple(lin(c) for c in base) + (1,)
    ld = tuple(lin(c) for c in dark) + (1,)
    lt = tuple(lin(c) for c in tips) + (1,)
    # streaks of bristle: noise stretched along the body
    stretch = nt.nodes.new("ShaderNodeMapping")
    stretch.inputs["Scale"].default_value = (.35, 1.0, 1.0)
    nt.links.new(coord.outputs["Object"], stretch.inputs["Vector"])
    streak = nt.nodes.new("ShaderNodeTexNoise")
    streak.inputs["Scale"].default_value = max(1., density * .9)
    streak.inputs["Detail"].default_value = 4.0
    nt.links.new(stretch.outputs[0], streak.inputs["Vector"])
    s_ramp = nt.nodes.new("ShaderNodeMapRange")
    s_ramp.inputs[1].default_value = .42
    s_ramp.inputs[2].default_value = .6
    nt.links.new(streak.outputs[0], s_ramp.inputs[0])
    mix1 = nt.nodes.new("ShaderNodeMix")
    mix1.data_type = "RGBA"
    mix1.inputs[6].default_value = lb
    mix1.inputs[7].default_value = ld
    nt.links.new(s_ramp.outputs[0], mix1.inputs[0])
    # grizzled tips: small pale flecks, in soft patches
    fleck = nt.nodes.new("ShaderNodeTexNoise")
    fleck.inputs["Scale"].default_value = max(1., density * 1.6)
    fleck.inputs["Detail"].default_value = 2.0
    nt.links.new(coord.outputs["Object"], fleck.inputs["Vector"])
    patch = nt.nodes.new("ShaderNodeTexNoise")
    patch.inputs["Scale"].default_value = max(.5, density * .15)
    nt.links.new(coord.outputs["Object"], patch.inputs["Vector"])
    gate = nt.nodes.new("ShaderNodeMath")
    gate.operation = "MULTIPLY"
    nt.links.new(fleck.outputs[0], gate.inputs[0])
    nt.links.new(patch.outputs[0], gate.inputs[1])
    g_ramp = nt.nodes.new("ShaderNodeMapRange")
    g_ramp.inputs[1].default_value = .33
    g_ramp.inputs[2].default_value = .38
    g_ramp.inputs[4].default_value = .38
    nt.links.new(gate.outputs[0], g_ramp.inputs[0])
    mix2 = nt.nodes.new("ShaderNodeMix")
    mix2.data_type = "RGBA"
    mix2.inputs[7].default_value = lt
    nt.links.new(mix1.outputs[2], mix2.inputs[6])
    nt.links.new(g_ramp.outputs[0], mix2.inputs[0])
    # mud caked up the legs and the belly
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sepz = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Position"], sepz.inputs[0])
    clump = nt.nodes.new("ShaderNodeTexNoise")
    clump.inputs["Scale"].default_value = 9.0
    nt.links.new(geo.outputs["Position"], clump.inputs["Vector"])
    add = nt.nodes.new("ShaderNodeMath")
    add.operation = "MULTIPLY_ADD"
    add.inputs[1].default_value = .14
    nt.links.new(clump.outputs[0], add.inputs[0])
    nt.links.new(sepz.outputs[2], add.inputs[2])
    ramp = nt.nodes.new("ShaderNodeMapRange")
    ramp.inputs[1].default_value = .12
    ramp.inputs[2].default_value = .3
    ramp.inputs[3].default_value = .85
    ramp.inputs[4].default_value = 0.
    nt.links.new(add.outputs[0], ramp.inputs[0])
    mud = nt.nodes.new("ShaderNodeMix")
    mud.data_type = "RGBA"
    mud.inputs[7].default_value = (lin(92), lin(72), lin(50), 1)
    nt.links.new(ramp.outputs[0], mud.inputs[0])
    nt.links.new(mix2.outputs[2], mud.inputs[6])
    nt.links.new(mud.outputs[2], bsdf.inputs["Base Color"])
    # the lie of the bristles: a coarse bump
    hair = nt.nodes.new("ShaderNodeTexNoise")
    hair.inputs["Scale"].default_value = max(1., density * 2.2)
    hair.inputs["Detail"].default_value = 2.0
    nt.links.new(stretch.outputs[0], hair.inputs["Vector"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = .45
    bump.inputs["Distance"].default_value = .02
    nt.links.new(hair.outputs[0], bump.inputs["Height"])
    nt.links.new(bump.outputs[0], bsdf.inputs["Normal"])
    _HOG_MATS[key] = m
    return m


def _hog_sphere(c, r, material, M=None, rot=(0, 0, 0)):
    """A ball with fewer faces than enemy_actors.py's (16 x 10): a hog is
    one of a herd and its model is kept light for the browser's download."""
    if isinstance(r, (int, float)):
        r = (r, r, r)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=1.0)
    matrix = T(c) @ R(*rot) @ Matrix.Diagonal((r[0], r[1], r[2], 1))
    place(bm, (M @ matrix) if M is not None else matrix, material)


def _hog_ball(c, r, which, M=None, rot=(0, 0, 0)):
    size = (sum(r) / 3) if isinstance(r, (tuple, list)) else r
    _hog_sphere(c, r, _hog_coat(which, size), M, rot)


def _hog_limb(a, b, ra, rb, which, M=None, caps=True, seg=12):
    a, b = Vector(a), Vector(b)
    if M is not None:
        a, b = M @ a, M @ b
    limb(a, b, ra, rb, _hog_coat(which, 1.), None, caps=False, seg=seg)
    if caps:
        _hog_ball(a, ra * 1.045, which)
        _hog_ball(b, rb * 1.045, which)


def _hog_plain():
    """The plain materials: snout, nostrils, eyes, tusks, hooves, mouth."""
    return dict(
        snout=mat(132, 104, 96, .6, grime=.25),
        nostril=mat(30, 20, 20, .5, grime=0),
        eye=mat(40, 18, 12, .15, grime=0),
        glint=mat(236, 228, 214, .2, grime=0),
        tusk=mat(222, 208, 170, .45, grime=.2),
        hoof=mat(24, 20, 18, .5, grime=.15),
        mouth=MOUTH(),
        ear=mat(60, 40, 36, .8, grime=.2),
    )


def _hog_pose(frame):
    """Everything a frame poses: the body's rise and pitch, the head's nod,
    the tail, the feet's places; the gallop from its beat."""
    P = dict(rise=0., pitch=0., nod=.05, jaw=.06, tail=(-1.35, .1), ears=0., lie=False,
             feet={"lf": (.0, .0), "rf": (.0, .0), "lh": (.0, .0), "rh": (.0, .0)})
    name = str(frame)
    if name == "r4":
        name = "r0"
    if name.startswith("r") and name[1:].isdigit():
        # The rotary gallop, four beats, the hound's shortened: stretched out,
        # the fore feet striking, gathered with the hind feet under him, the
        # hind push. The tail straight up, the head down and driving.
        k = int(name[1:])
        P["feet"] = [
            {"lf": (.2, .07), "rf": (.16, .1), "lh": (-.2, .07), "rh": (-.16, .1)},
            {"lf": (.07, 0.), "rf": (.12, .02), "lh": (-.15, .11), "rh": (-.09, .14)},
            {"lf": (-.12, .08), "rf": (-.07, .04), "lh": (.08, .03), "rh": (.13, .07)},
            {"lf": (.01, .16), "rf": (-.04, .13), "lh": (-.01, 0.), "rh": (.04, .02)},
        ][k]
        P["rise"] = [.045, -.015, -.03, .015][k]
        P["pitch"] = [0., .08, -.05, -.08][k]
        P["nod"] = [.1, .2, .14, .06][k]
        P["tail"] = (1.35, -.25)
        P["ears"] = .7
        P["jaw"] = .2
    elif name == "down":
        P["lie"] = True
        P["nod"] = -.1
        P["jaw"] = .3
        P["tail"] = (-.2, .0)
        P["feet"] = {"lf": (.12, .02), "rf": (.2, .02), "lh": (-.1, .02), "rh": (-.02, .02)}
    return P


def _hog_hoof(foot, C, M):
    """A cloven hoof: two black toes and the dew claws behind."""
    for s in (-1, 1):
        _hog_sphere(foot + Vector((.022, s * .014, .016)), (.028, .014, .02), C["hoof"], M)
    _hog_sphere(foot + Vector((-.02, 0, .04)), (.012, .02, .01), C["hoof"], M)


def _hog_leg(hip, foot, l1, l2, low_len, low_back, pole, r, C):
    """One leg: two IK pieces from `hip` to the joint above the foot, then the
    low piece of fixed length to the hoof (world places)."""
    foot = Vector(foot)
    low = Vector((low_back, 0, 1)).normalized() * low_len
    knee, wrist = ik(hip, foot + low, l1, l2, pole)
    hoof = wrist - low
    r0, r1, r2, r3 = r
    _hog_limb(hip, knee, r0, r1, "coat")
    _hog_limb(knee, wrist, r1 * .82, r2, "coat")
    _hog_limb(wrist, hoof, r2 * .95, r3, "coat", caps=False, seg=12)
    _hog_hoof(hoof, C, None)


def _hog_head(Hm, P, C):
    """The head in its own frame Hm: the neck's top at the origin, +x down the
    snout. A long wedge, the flat snout disc at its end, tusks curling up out
    of the lower jaw, small eyes set high, pricked ears."""
    _hog_ball((.03, 0, .03), (.13, .1, .11), "head", Hm)
    _hog_ball((-.04, 0, .1), (.07, .07, .05), "ridge", Hm)
    # the wedge of the face down to the snout
    _hog_limb((.06, 0, .03), (.3, 0, -.01), .085, .05, "head", Hm)
    _hog_ball((.17, 0, .055), (.11, .055, .04), "head", Hm, rot=(0, .15, 0))
    for s in (-1, 1):
        _hog_ball((.1, s * .07, -.01), (.07, .03, .06), "head", Hm)
    # the snout: a flat disc, two nostrils
    nose = Vector((.33, 0, -.01))
    _hog_sphere(nose, (.02, .05, .042), C["snout"], Hm)
    for s in (-1, 1):
        _hog_sphere(nose + Vector((.016, s * .018, -.004)), (.006, .011, .014), C["nostril"], Hm)
    # the lower jaw on its hinge, a mouth, the tusks curling up and out
    J = Hm @ T((.07, 0, -.05)) @ R(0, P["jaw"], 0)
    _hog_limb((0, 0, 0), (.21, 0, .005), .045, .028, "head", J)
    _hog_sphere((.12, 0, .025), (.08, .028, .012), C["mouth"], J)
    for s in (-1, 1):
        root = Vector((.17, s * .035, .02))
        tip = root + Vector((.03, s * .03, .06))
        limb(J @ root, J @ ((root + tip) * .5 + Vector((-.012, 0, .004))), .011, .008, C["tusk"], None, caps=False, seg=8)
        limb(J @ ((root + tip) * .5 + Vector((-.012, 0, .004))), J @ tip, .008, .002, C["tusk"], None, caps=False, seg=8)
    # small mean eyes set high, a heavy brow over each
    for s in (-1, 1):
        eye = Vector((.13, s * .072, .07))
        _hog_sphere(eye, .014, C["eye"], Hm)
        _hog_sphere(eye + Vector((.007, s * .006, .005)), .004, C["glint"], Hm)
        _hog_ball(eye + Vector((.0, 0, .016)), (.026, .016, .01), "ridge", Hm, rot=(0, -.25, 0))
    # pricked ears, swept back on the run
    back = P["ears"]
    for s in (-1, 1):
        E = Hm @ T((-.02, s * .07, .11)) @ R(s * .35, -.35 - back * .5, s * .3)
        _hog_sphere((0, 0, .045), (.022, .012, .055), C["ear"], E)
        _hog_ball((-.004, s * .004, .04), (.026, .008, .058), "ridge", E)
    return J


def _hog_body(P, C, M):
    """The body, the ridge of bristles, neck, head, legs and tail in M."""
    hip_rest = Vector((-.3, 0, .37))
    if P["lie"]:
        Tb = Matrix.Identity(4)
    else:
        Tb = T(hip_rest + Vector((0, 0, P["rise"]))) @ R(0, P["pitch"], 0) @ T(-hip_rest)
    B = M @ Tb
    # wedge-built: the shoulders high and deep, the barrel, small hams
    _hog_ball((.2, 0, .43), (.24, .17, .24), "coat", B)
    _hog_ball((.32, 0, .39), (.13, .14, .17), "coat", B)
    _hog_ball((-.02, 0, .4), (.28, .16, .18), "coat", B)
    _hog_ball((-.27, 0, .38), (.17, .14, .16), "coat", B)
    _hog_ball((-.36, 0, .36), (.1, .11, .11), "coat", B)
    # the grey-brown belly under the barrel
    _hog_ball((.02, 0, .28), (.24, .12, .08), "belly", B)
    # the ridge: long bristles standing along the spine, tallest at the
    # withers, a little ragged
    for k in range(34):
        t = k / 33.0
        x = .46 - t * .72
        top = .655 - .13 * t * t - (.04 if x > .38 else 0.)
        tall = .075 - .045 * t + .018 * ((k * 5) % 3) / 2.0
        lean = -.45 - .25 * t + .18 * (((k * 7) % 5) - 2) / 2.0
        side = .012 * (((k * 3) % 3) - 1)
        base = B @ Vector((x, side, top - .03))
        tip = B @ Vector((x - math.sin(-lean) * tall, side * 2, top - .03 + math.cos(lean) * tall))
        limb(base, tip, .022, .004, _hog_coat("ridge", 1.), None, caps=False, seg=5)
    # the neck: thick and short, low
    neck_base = Vector((.36, 0, .45))
    neck_top = neck_base + Vector((.13, 0, -.02))
    _hog_limb(neck_base, neck_top, .13, .11, "coat", B)
    Hm = B @ T(neck_top) @ R(0, .18 + P["nod"], 0) @ _HOG_HEAD
    _hog_head(Hm, P, C)
    # the legs: the feet's places on the ground (hog space, under M)
    for leg, s, front in (("lf", 1, True), ("rf", -1, True), ("lh", 1, False), ("rh", -1, False)):
        fx, fz = P["feet"][leg]
        if front:
            hip = B @ Vector((.24, s * .08, .33))
            foot = Vector((.26 + fx, s * .085, fz))
            if P["lie"]:
                foot = Vector((.38 + fx, s * .09, .03))
            _hog_leg(hip, M @ foot, _HOG_ARM, _HOG_FORE, _HOG_PASTERN, -.2,
                     B.to_3x3() @ Vector((-1, 0, -.15)), (.06, .042, .03, .025), C)
        else:
            hip = B @ Vector((-.3, s * .075, .35))
            foot = Vector((-.32 + fx, s * .08, fz))
            if P["lie"]:
                foot = Vector((-.5 + fx, s * .09, .03))
            _hog_leg(hip, M @ foot, _HOG_THIGH, _HOG_GASKIN, _HOG_META, .45,
                     B.to_3x3() @ Vector((1, 0, -.1)), (.075, .05, .03, .025), C)
    # the tail: thin, a tuft at its end; up and stiff on the run
    a0, a1 = P["tail"]
    R3 = B.to_3x3().normalized()
    root = B @ Vector((-.44, 0, .43))
    at = Vector(root)
    for k, (length, a) in enumerate(((.09, a0), (.08, a0 + a1))):
        d = R3 @ Vector((-math.cos(a), 0, math.sin(a)))
        end = at + d * length
        _hog_limb(at, end, .016 - k * .004, .012 - k * .004, "coat", caps=k == 0, seg=8)
        at = end
    _hog_ball(at, (.022, .018, .03), "ridge")


def _hog_matrix(frame, lie):
    """Where the whole hog stands: for the model square, head toward -y; for
    the cels turned a little to the camera. Dead, he lies on his left side
    (+y), legs out to his right."""
    G = Matrix.Identity(4)
    if lie:
        G = T((0, 0, .12)) @ R(-math.pi / 2 + .08, 0, 0) @ T((0, 0, -.44))
    if FOR_MODEL:
        return R(0, 0, -math.pi / 2) @ G
    return R(0, 0, -.32) @ G


def hog(frame):
    P = _hog_pose(frame)
    C = _hog_plain()
    _hog_body(P, C, _hog_matrix(frame, P["lie"]))


ACTORS.update({
    "hog": (hog, HOG, (), HOG_CELS),
})
