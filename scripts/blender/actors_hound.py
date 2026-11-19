"""BLUE, Mundell's bluetick coonhound (src/features/hound.gd), exec'd by
enemy_actors.py into its own namespace after ACTORS is made, so place, mat,
T, R, ik, Vector and the rest are in scope. Built from scratch (pass 10):
nothing is traced from another game or a photograph.

    hound       a lean, deep-chested, muscled bluetick: the coat painted on
                (one pattern laid over every part in the body's own
                coordinates, `coat_co`, so the parts read as one hide): pale
                hair thick with slate-blue ticking and roan, a ragged black
                saddle over the back, black patches and spots, a black hood
                down the skull and neck; tan points on the brows, cheeks and
                muzzle, the chest and the legs; long, low-set, folded black
                ears that hang past the jaw and swing; a long square muzzle
                with droopy flews, a big black nose and brown eyes over red
                haws; a worn red collar with a brass tag; a saber tail
                carried up.
    hound_face  his head alone, three-quarters to the camera, for the HUD's
                badge (src/hound_looks.gd): 0 easy, 1 keen, 2 hurt, down
                out cold.

His model's frames (HOUND "model_frames", keyed at 24 fps one after another;
a run of five, x0..x4, is one motion ActorView plays on the stand-in's gait):

    0               standing easy (the rest frame: the mesh)
    i0..i4          idle: panting, the tail wagging one way then the other
    w0..w4          the walk (four beats; x4 is x0 again where it loops)
    t0..t4          the trot (diagonal pairs)
    r0..r4          the gallop: stretched, front strike, gathered, hind push
    l0..l4          the hurt limp, the right fore held up
    n0..n4          tracking: the walk with his nose down, the head sweeping
    c0..c4          sat scratching an ear with a hind foot
    k0..k4          the shake-off, nose to tail
    f0..f4          going down: the stagger, the front gone, on his chest,
                    over, flat on his side
    o0..o4          down on his side: breathing, the head lifted to whine,
                    a paw paddling
    v0..v4          being got up: on his side, the head up, rolled onto his
                    chest, propped on his forelegs
    u0..u4          getting up from there to his feet
    j0..j4          the lunge and bite: gathered, the spring, the jaws shut,
                    the yank, braced
    p0..p4          holding a hand down: hauling back, the head shaking
    sit, sniff, point, bark, bay (the howl), pain, fetch, rest (lying on his
    belly, chin down), down (flat on his side)

His cels (HOUND_CELS, the 2D pictures the view stands his model in for, and
everything that draws a picture of him) keep their old names: 0, wag, the
walk, the gallop, sit, bark, bay, bite, pin, pin2, fetch, point, sniff,
pain, down, whine (_CEL_POSE maps the ones that are now a motion's key).

Seen side on (x along the body, head to +x, y his left, z up), turned a
little to the camera for the cels; for the model (FOR_MODEL, set by
export_actors.py) square, head toward -y, as the people are. Every leg is
built from pieces of fixed length posed by two-bone IK, and every frame
builds the same parts in the same order (export_actors.py pairs them by
that order, `same_parts`: by shape his toes were paired across feet), so
nothing pops in or out or flies between keys.
"""

_HD_RUNS = ("i", "w", "t", "r", "l", "n", "c", "k", "f", "o", "v", "u", "j", "p")
_HD_SINGLES = ("sit", "sniff", "point", "bark", "bay", "pain", "fetch", "rest", "down")
HOUND = dict(canvas=(1.5, 1.0), px=64,
             model_frames=[0] + ["%s%d" % (s, k) for s in _HD_RUNS for k in range(5)] + list(_HD_SINGLES),
             head_box=.17, same_parts=True)
# The badge is cels only: export_actors.py makes no model of it.
HOUND_FACE = dict(canvas=(.42, .42), px=48, cels_only=True)
HOUND_CELS = [0, "wag", "w0", "w1", "w2", "w3", "w4", "r0", "r1", "r2", "r3", "r4", "sit", "bark", "bay",
              "bite", "pin", "pin2", "fetch", "point", "sniff", "pain", "down", "whine"]
FACE_CELS = [0, 1, 2, "down"]
PLAIN_KINDS = tuple(PLAIN_KINDS) + ("hound", "hound_face")
# The old cels that are now a key of one of his motions.
_CEL_POSE = {"wag": "i1", "bite": "j2", "pin": "p0", "pin2": "p2", "whine": "rest"}

# Leg pieces (metres): the front's upper arm, forearm and pastern; the hind's
# thigh, gaskin and hock-to-foot.
_HD_ARM, _HD_FORE, _HD_PASTERN = .16, .25, .085
_HD_THIGH, _HD_GASKIN, _HD_META = .22, .24, .12
# Where the legs join the body (B: the body's frame standing), and where each
# foot stands at rest.
_HD_SHOULDER = Vector((.30, .075, .45))
_HD_HIP = Vector((-.27, .075, .52))
_HD_FOOT_F = Vector((.31, .08, 0))
_HD_FOOT_H = Vector((-.41, .085, 0))
# The spine bends about his waist.
_HD_WAIST = Vector((-.05, 0, .52))
# His head a touch big for him, as a hound's reads at the view's size.
_HD_HEAD = 1.06
_HD_MATS = {}
# The badge's head is drawn near the stage's floor: no road dirt on it.
_HD_CLEAN = [False]


# ------------------------------------------------------------------ parts


def _hd_coat_co(ob, P):
    """Each vertex's place in its part's coat frame (P @ the unit shape's
    own vertex), as the attribute `coat_co` the coats paint by: the body's
    parts in the body's frame, the head's in the head's, a leg piece by its
    height on the leg standing, so the hide's pattern runs on across parts
    and stays put on each part whatever the pose."""
    me = ob.data
    n = len(me.vertices)
    co = [0.0] * (n * 3)
    me.vertices.foreach_get("co", co)
    out = [0.0] * (n * 3)
    for i in range(n):
        v = P @ Vector((co[i * 3], co[i * 3 + 1], co[i * 3 + 2]))
        out[i * 3], out[i * 3 + 1], out[i * 3 + 2] = v.x, v.y, v.z
    a = me.attributes.new("coat_co", "FLOAT_VECTOR", "POINT")
    a.data.foreach_set("vector", out)


def _hd_ball(c, r, m, F=None, rot=(0, 0, 0), P=None):
    """A ball at c (in F's frame) of radii r, its coat frame F's frame (P
    None) or P @ the ball's own shape (P puts the ball's middle in the coat:
    a joint's cap at its height on the leg)."""
    if isinstance(r, (int, float)):
        r = (r, r, r)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=14, radius=1.0)
    shape = R(*rot) @ Matrix.Diagonal((r[0], r[1], r[2], 1))
    L = T(c) @ shape
    ob = place(bm, (F @ L) if F is not None else L, m)
    _hd_coat_co(ob, L if P is None else P @ shape)
    return ob


def _hd_limb(a, b, ra, rb, m, F=None, P=None, seg=18):
    """A tapered capsule body from a to b (F's frame), uncapped."""
    a, b = Vector(a), Vector(b)
    d = b - a
    if d.length < 1e-5:
        d = Vector((0, 0, 1e-4))
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg,
                          radius1=ra, radius2=rb, depth=d.length)
    L = T((a + b) / 2) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4()
    ob = place(bm, (F @ L) if F is not None else L, m)
    _hd_coat_co(ob, L if P is None else P)
    return ob


def _hd_seg_ball(a, b, t, r, m, F, P=None, side=0.):
    """An ellipsoid laid along the segment a->b at t of the way (radii r:
    across, across, along), pushed `side` off it (a muscle on a bone)."""
    a, b = Vector(a), Vector(b)
    d = b - a
    q = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
    c = a + d * t
    L = T(c) @ q @ T((side, 0, 0)) @ Matrix.Diagonal((r[0], r[1], r[2], 1))
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=14, radius=1.0)
    ob = place(bm, F @ L, m)
    _hd_coat_co(ob, L if P is None else P @ q @ T((side, 0, 0)) @ Matrix.Diagonal((r[0], r[1], r[2], 1)))
    return ob


# ------------------------------------------------------------------ the coat


def _hd_node(nt, kind, **inputs):
    n = nt.nodes.new(kind)
    for k, v in inputs.items():
        n.inputs[k].default_value = v
    return n


def _hd_math(nt, op, a, b=None, clamp=False):
    n = nt.nodes.new("ShaderNodeMath")
    n.operation = op
    n.use_clamp = clamp
    for i, v in enumerate((a, b)):
        if v is None:
            continue
        if isinstance(v, (int, float)):
            n.inputs[i].default_value = v
        else:
            nt.links.new(v, n.inputs[i])
    return n.outputs[0]


def _hd_ramp(nt, value, lo, hi, to_lo=0., to_hi=1.):
    """value mapped from [lo, hi] onto [to_lo, to_hi], smoothly, clamped."""
    if lo > hi:
        lo, hi, to_lo, to_hi = hi, lo, to_hi, to_lo
    n = nt.nodes.new("ShaderNodeMapRange")
    n.interpolation_type = "SMOOTHSTEP"
    n.inputs[1].default_value = lo
    n.inputs[2].default_value = hi
    n.inputs[3].default_value = to_lo
    n.inputs[4].default_value = to_hi
    nt.links.new(value, n.inputs[0])
    return n.outputs[0]


def _hd_noise(nt, vec, scale, detail=2., offset=(0., 0., 0.)):
    if offset != (0., 0., 0.):
        add = nt.nodes.new("ShaderNodeVectorMath")
        add.operation = "ADD"
        add.inputs[1].default_value = offset
        nt.links.new(vec, add.inputs[0])
        vec = add.outputs[0]
    n = nt.nodes.new("ShaderNodeTexNoise")
    n.inputs["Scale"].default_value = scale
    n.inputs["Detail"].default_value = detail
    nt.links.new(vec, n.inputs["Vector"])
    return n.outputs[0]


def _hd_mix(nt, fac, a, b):
    """Colour a or b (an RGB tuple 0..255 or a socket) by fac."""
    n = nt.nodes.new("ShaderNodeMix")
    n.data_type = "RGBA"
    for i, v in ((6, a), (7, b)):
        if isinstance(v, tuple):
            n.inputs[i].default_value = (lin(v[0]), lin(v[1]), lin(v[2]), 1)
        else:
            nt.links.new(v, n.inputs[i])
    if isinstance(fac, (int, float)):
        n.inputs[0].default_value = fac
    else:
        nt.links.new(fac, n.inputs[0])
    return n.outputs[2]


def _hd_blob(nt, xyz, centre, radius, edge, wobble=None):
    """1 inside the ellipsoid `radius` round `centre` (|y| mirrored), soft by
    `edge`, its rim pushed about by `wobble` (a 0..1 socket)."""
    x, y, z = xyz
    ay = _hd_math(nt, "ABSOLUTE", y)
    d = 0
    terms = []
    for v, c, r in ((x, centre[0], radius[0]), (ay, centre[1], radius[1]), (z, centre[2], radius[2])):
        s = _hd_math(nt, "DIVIDE", _hd_math(nt, "SUBTRACT", v, c), r)
        terms.append(_hd_math(nt, "MULTIPLY", s, s))
    d = _hd_math(nt, "ADD", _hd_math(nt, "ADD", terms[0], terms[1]), terms[2])
    if wobble is not None:
        d = _hd_math(nt, "ADD", d, _hd_math(nt, "MULTIPLY", _hd_math(nt, "SUBTRACT", wobble, .5), 1.2))
    return _hd_ramp(nt, d, 1. + edge, 1. - edge)


# The hide's colours.
_HD_PALE = (172, 180, 194)
_HD_ROAN = (66, 78, 104)
_HD_TICK = (30, 36, 52)
_HD_BLACK = (24, 24, 30)
_HD_TAN = (164, 102, 54)
_HD_TAN_DARK = (104, 62, 34)


def _hd_coat(zone):
    """The painted hide for a zone's parts ("body", "head", "leg", "tail",
    "ear"), by their `coat_co`."""
    key = (zone, _HD_CLEAN[0])
    if key in _HD_MATS and _HD_MATS[key].name in bpy.data.materials:
        return _HD_MATS[key]
    m = bpy.data.materials.new("hd_" + zone)
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    bsdf.inputs["Roughness"].default_value = .8
    for name in ("Specular IOR Level", "Specular"):
        if name in bsdf.inputs:
            bsdf.inputs[name].default_value = .25
    attr = nt.nodes.new("ShaderNodeAttribute")
    attr.attribute_name = "coat_co"
    attr.attribute_type = "GEOMETRY"
    vec = attr.outputs["Vector"]
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(vec, sep.inputs[0])
    xyz = (sep.outputs[0], sep.outputs[1], sep.outputs[2])
    x, y, z = xyz
    # The blue: pale hair, a roan of slate blue through it, small hard ticks.
    roan = _hd_ramp(nt, _hd_noise(nt, vec, 7., 3.), .3, .6, .36, .95)
    ticks_a = _hd_ramp(nt, _hd_noise(nt, vec, 70., 2., (3.1, 1.7, .4)), .565, .6)
    ticks_b = _hd_ramp(nt, _hd_noise(nt, vec, 140., 1., (7.3, 2.2, 5.1)), .57, .61)
    ticks = _hd_math(nt, "MAXIMUM", ticks_a, ticks_b)
    blue = _hd_mix(nt, ticks, _hd_mix(nt, roan, _HD_PALE, _HD_ROAN), _HD_TICK)
    # Tan hair, ticked a little.
    tan = _hd_mix(nt, _hd_math(nt, "MULTIPLY", ticks, .6),
                  _hd_mix(nt, _hd_ramp(nt, _hd_noise(nt, vec, 14.), .35, .7), _HD_TAN, _HD_TAN_DARK), _HD_TICK)
    black = _hd_mix(nt, _hd_math(nt, "MULTIPLY", ticks_b, .35), _HD_BLACK, (52, 56, 70))
    wob = _hd_noise(nt, vec, 7., 3., (11., 4., 2.))
    if zone == "body":
        # The saddle: black over the back from the withers to the croup, its
        # edge ragged down the flanks; the hood down the top of the neck;
        # black patches on the shoulder and the hip; spots through the blue.
        edge = _hd_math(nt, "ADD", z, _hd_math(nt, "MULTIPLY", _hd_math(nt, "SUBTRACT", wob, .5), .09))
        sz = _hd_ramp(nt, edge, .54, .56)
        sx = _hd_math(nt, "MINIMUM", _hd_ramp(nt, x, -.35, -.3), _hd_ramp(nt, x, .2, .14))
        saddle = _hd_math(nt, "MULTIPLY", sz, sx)
        hood = _hd_math(nt, "MULTIPLY", _hd_ramp(nt, x, .3, .36), _hd_ramp(nt, edge, .64, .67))
        patches = _hd_math(nt, "MAXIMUM",
                           _hd_blob(nt, xyz, (.24, .1, .5), (.07, .08, .06), .25, wob),
                           _hd_blob(nt, xyz, (-.31, .09, .49), (.07, .1, .06), .25, wob))
        spots = _hd_ramp(nt, _hd_noise(nt, vec, 6., 3., (2., 9., 4.)), .7, .72)
        dark = _hd_math(nt, "MAXIMUM", _hd_math(nt, "MAXIMUM", saddle, hood),
                        _hd_math(nt, "MAXIMUM", patches, spots))
        hide = _hd_mix(nt, dark, blue, black)
        # Tan on the chest's point and under the tail.
        chest = _hd_math(nt, "MULTIPLY", _hd_ramp(nt, x, .34, .4), _hd_ramp(nt, z, .5, .42))
        under = _hd_math(nt, "MULTIPLY", _hd_math(nt, "MULTIPLY", _hd_ramp(nt, x, -.412, -.425), _hd_ramp(nt, z, .58, .55)),
                              _hd_ramp(nt, _hd_math(nt, "ABSOLUTE", y), .03, .018))
        hide = _hd_mix(nt, _hd_math(nt, "MAXIMUM", chest, under), hide, tan)
    elif zone == "head":
        # The hood: black over the skull and round the eyes, down the cheeks
        # behind them; tan pips over the eyes and tan cheeks; the muzzle
        # ticked blue, tan at its sides, black at the lips' edge.
        stop = _hd_math(nt, "ADD", x, _hd_math(nt, "MULTIPLY", _hd_math(nt, "SUBTRACT", wob, .5), .03))
        muzzle = _hd_ramp(nt, stop, .118, .14)
        # (the badge's head a shade lighter on the muzzle: at 28 pixels it
        # sank into the hood)
        hide = _hd_mix(nt, muzzle, black, _hd_mix(nt, 0. if _HD_CLEAN[0] else .25, blue, (70, 78, 96)))
        pips = _hd_blob(nt, xyz, (.112, .036, .064), (.016, .014, .011), .3)
        cheek = _hd_math(nt, "MAXIMUM",
                         _hd_blob(nt, xyz, (.12, .042, -.004), (.06, .03, .024), .3, wob),
                         _hd_blob(nt, xyz, (.205, .034, -.005), (.06, .03, .02), .3, wob))
        hide = _hd_mix(nt, _hd_math(nt, "MAXIMUM", pips, cheek), hide, tan)
        lips = _hd_ramp(nt, z, -.03, -.042)
        hide = _hd_mix(nt, _hd_math(nt, "MULTIPLY", lips, _hd_ramp(nt, x, .1, .13)), hide, _HD_BLACK)
    elif zone == "leg":
        # By height on the leg: the blue high, tan socks low, darker toes.
        low = _hd_ramp(nt, _hd_math(nt, "ADD", z, _hd_math(nt, "MULTIPLY", _hd_math(nt, "SUBTRACT", wob, .5), .05)),
                       .2, .14)
        spots = _hd_ramp(nt, _hd_noise(nt, vec, 9., 3., (5., 1., 3.)), .71, .73)
        hide = _hd_mix(nt, low, _hd_mix(nt, spots, blue, black), tan)
    elif zone == "tail":
        # Along the tail (z its length): black at the root, the blue, the tip
        # pale.
        root = _hd_ramp(nt, z, .1, .06)
        tip = _hd_ramp(nt, z, .3, .38)
        hide = _hd_mix(nt, root, blue, black)
        hide = _hd_mix(nt, tip, hide, _hd_mix(nt, .4, _HD_PALE, blue))
    else:
        # The ears: black leather with a cool sheen, lighter at the fold.
        # (darker on the badge's head: under its key light a sheen read grey)
        sheen = (36, 38, 48) if _HD_CLEAN[0] else (60, 64, 80)
        hide = _hd_mix(nt, _hd_ramp(nt, _hd_noise(nt, vec, 18.), .3, .75, 0., .5), (26, 27, 34), sheen)
        bsdf.inputs["Roughness"].default_value = .62
    # Road dirt up the legs, as every actor has (none on the badge's head).
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    wz = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Position"], wz.inputs[0])
    mud = _hd_ramp(nt, wz.outputs[2], 0., .16, 0. if _HD_CLEAN[0] else .45, 0.)
    hide = _hd_mix(nt, mud, hide, (82, 64, 46))
    nt.links.new(hide, bsdf.inputs["Base Color"])
    # The lie of the coat: a fine bump.
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = .2
    bump.inputs["Distance"].default_value = .01
    nt.links.new(_hd_noise(nt, vec, 120.), bump.inputs["Height"])
    nt.links.new(bump.outputs[0], bsdf.inputs["Normal"])
    _HD_MATS[key] = m
    return m


def _hd_matte(m, level=.15):
    """A dark part's sheen turned down: under the stage's rims a shiny black
    reads grey."""
    for node in m.node_tree.nodes:
        if node.type == "BSDF_PRINCIPLED":
            for name in ("Specular IOR Level", "Specular"):
                if name in node.inputs:
                    node.inputs[name].default_value = level
    return m


def _hd_kit():
    """The plain materials and the hide's zones."""
    return dict(
        body=_hd_coat("body"), head=_hd_coat("head"), leg=_hd_coat("leg"), tail=_hd_coat("tail"),
        ear=_hd_coat("ear"),
        nose=_hd_matte(mat(22, 20, 24, .38, grime=0), .4),
        nostril=mat(8, 6, 8, .9, grime=0),
        eye=mat(50, 28, 14, .15, grime=0),
        pupil=mat(10, 8, 8, .1, grime=0),
        glint=mat(246, 240, 228, .2, grime=0, emit=.6),
        lid=_hd_matte(mat(24, 24, 30, .85, grime=0)),
        haw=mat(112, 40, 38, .5, grime=0),
        mouth=MOUTH(),
        tongue=mat(206, 92, 100, .4, grime=0),
        tooth=TOOTH(),
        pad=_hd_matte(mat(30, 28, 30, .7, grime=.2)),
        collar=mat(150, 36, 24, .6, grime=.15),
        buckle=BRASS(),
        tag=BRASS(),
    )


# ------------------------------------------------------------------ poses


def _hd_rest():
    return dict(
        # The body: rise, pitch (+ nose down), roll (+ his right side down),
        # shift forward, the front and back dropped, the spine's flex (+ the
        # back roached, front and back feet drawn together) and bend (+ his
        # head round to his left).
        rise=0., pitch=0., roll=0., shift=0., front_drop=0., rear_drop=0., flex=0., bend=0.,
        # sat, or lying ("low"): lie_roll 0 on his chest, pi/2 flat on his left side
        sat=False, low=False, lie_roll=0.,
        # the neck's lift and turn, the head's nod, roll and turn
        neck=.72, neck_yaw=0., nod=0., head_roll=0., head_yaw=0.,
        jaw=.16, tongue=1., lids=.22, brows=0.,
        # the ears: swung back, flared out, each side's own swing (+ forward)
        ears=0., flare=0., ear_l=0., ear_r=0.,
        # the tail: lift (from straight back), curl, wag (+ to his left)
        tail=(.75, .2), tail_yaw=0., tail_whip=0.,
        # each foot's place from where it stands (dx, dz, dy), a foot curled
        # up (point), a hind foot up at the ear (scratch)
        feet={"lf": (0., 0., 0.), "rf": (0., 0., 0.), "lh": (0., 0., 0.), "rh": (0., 0., 0.)},
        curl=None, scratch=None,
    )


def _hd_cycle(k, table):
    """Key k (0..3; 4 is 0) of a four-beat table of dicts."""
    return table[k % 4]


def _hd_walk_feet(k, stride, lift, offs, k_total=4.):
    feet = {}
    for leg, o in offs.items():
        a = (k / k_total + o) * math.tau
        feet[leg] = (stride * math.sin(a), lift * max(0., math.cos(a)), 0.)
    return feet


_HD_WALK = {"lh": 0., "lf": .25, "rh": .5, "rf": .75}
# The lope's footfalls (pass 12): the key each foot strikes on, how far out
# in front it strikes (it sweeps back _HD_LOPE_SWEEP over the next beat).
_HD_LOPE = {"lh": (0, .15), "rh": (1, .15), "rf": (2, .17), "lf": (3, .17)}
_HD_LOPE_SWEEP = .28


def _hd_lope_foot(leg, k):
    """A foot's place at key k of the lope: struck, swept back on the ground,
    lifted behind, swung forward high."""
    strike, out = _HD_LOPE[leg]
    j = (k - strike) % 4
    back = out - _HD_LOPE_SWEEP
    return [(out, 0., 0.), (back, 0., 0.), (back - .05, .1, 0.), ((out + back) * .5, .16, 0.)][j]
_HD_TROT = {"lf": 0., "rh": 0., "rf": .5, "lh": .5}


def _hd_pose(frame):
    """Everything a frame poses (see _hd_rest)."""
    P = _hd_rest()
    name = str(frame)
    name = _CEL_POSE.get(name, name)
    run, k = None, 0
    if len(name) == 2 and name[0] in _HD_RUNS and name[1].isdigit():
        run, k = name[0], int(name[1])
        if run not in ("f", "v", "u", "j") and k == 4:
            k = 0
    s = math.sin(k / 4. * math.tau)
    c = math.cos(k / 4. * math.tau)
    if name == "0" and FOR_MODEL:
        # The model's rest frame, the one its looks are baked in: every part
        # out in the stage's light (the legs spread clear of the trunk, the
        # jaws open on the tongue and teeth, the ears out from the head, the
        # lids half down), so no surface that shows in another frame was
        # baked buried in the dark. The game never shows it.
        P.update(jaw=.5, tongue=1., lids=.5, flare=.55, ears=-.2, neck=.9, tail=(1.15, .05), tail_yaw=0.)
        P["feet"] = {"lf": (.08, 0., .13), "rf": (.08, 0., -.13), "lh": (-.08, 0., .14), "rh": (-.08, 0., -.14)}
    elif name == "0":
        P.update(jaw=.2, tongue=1.)
    elif run == "i":
        # Easy, panting, the tail wagging wide one way then the other.
        P.update(jaw=.22 + .06 * (k % 2), tongue=1., tail_yaw=.5 * s, tail_whip=-.35 * s,
                 tail=(1.1, .26), nod=-.04 * c, neck=.82 + .03 * c, rise=.004 * c, ear_l=.05 * s, ear_r=-.05 * s)
    elif run == "w":
        # (pass 12: strides lengthened, .11 to .15, so his feet keep to the
        # ground at the pace he walks; the shoulder blade swings with the
        # foreleg, `reach`, so the forefoot gets there)
        P["feet"] = _hd_walk_feet(k, .15, .07, _HD_WALK)
        P["reach"] = .3
        P.update(tail_yaw=.3 * s, tail_whip=-.2 * s, nod=.05 * math.sin(k / 2. * math.tau),
                 rise=.01 * math.cos(k / 2. * math.tau), roll=.025 * s, bend=.04 * s,
                 ear_l=.14 * s, ear_r=.14 * s, jaw=.18, tongue=1.)
    elif run == "t":
        P["feet"] = _hd_walk_feet(k, .21, .09, _HD_TROT)
        P["reach"] = .3
        P.update(neck=.7, nod=.05 + .03 * math.cos(k / 2. * math.tau), rise=.015 * math.cos(k / 2. * math.tau),
                 roll=.03 * s, tail=(.95, .2), tail_yaw=.15 * s, ears=.25, ear_l=.2 * c, ear_r=-.2 * c,
                 jaw=.25, tongue=1.)
    elif run == "r":
        # The lope, his rotary gallop at an easy pace (pass 12: it was a
        # flat-out run with each foot down a sixteenth of the stride, so his
        # feet skated at any pace): each foot down a whole beat, struck out
        # in front and swept back under him over the ground he covers, in
        # turn left hind, right hind, right fore, left fore; the back
        # stretching as the hind feet drive and gathering as the fore land.
        P.update(neck=.55, ears=.7, flare=.12, tail=(.55, .14), jaw=.3, tongue=1., head_yaw=0.)
        P["feet"] = {leg: _hd_lope_foot(leg, k) for leg in ("lf", "rf", "lh", "rh")}
        P["reach"] = .3
        P["rise"] = [-.012, .018, -.006, .016][k]
        P["pitch"] = [.04, -.01, -.045, .015][k]
        P["flex"] = [-.07, .03, .09, -.02][k]
        P["nod"] = [-.04, .05, .07, -.03][k]
        P["ear_l"] = P["ear_r"] = [-.12, .08, .15, -.04][k]
    elif run == "l":
        # The limp: the right fore carried, only touched down; the head nods
        # up as it comes down, the rump rolls.
        feet = _hd_walk_feet(k, .13, .06, _HD_WALK)
        feet["rf"] = (.05 + .03 * s, .07 + .03 * c, 0.)
        P["feet"] = feet
        P["reach"] = .3
        P.update(nod=.1 + .08 * c, neck=.7, rise=-.03 + .012 * c, roll=-.05 + .03 * s, pitch=.04,
                 tail=(.35, .1), tail_yaw=.08 * s, ears=.35, brows=1., jaw=.08, tongue=0., lids=.25,
                 ear_l=.1 * s, ear_r=.1 * s)
    elif run == "n":
        # Tracking: walking with his nose to the ground, sweeping side to side.
        P["feet"] = _hd_walk_feet(k, .13, .05, _HD_WALK)
        P["reach"] = .3
        P.update(neck=-.55, nod=.5, neck_yaw=.28 * s, head_yaw=.12 * s, pitch=.08, rise=-.02,
                 front_drop=.03, tail=(1.15, .3), tail_yaw=.2 * c, jaw=0., tongue=0., ears=-.1,
                 ear_l=-.15 * s, ear_r=.15 * s)
    elif run == "c":
        # Sat, scratching behind his left ear with the left hind foot.
        up = k % 2 == 0
        P.update(sat=True, neck=.45, neck_yaw=.85, head_roll=.6, nod=.25, lids=.7, jaw=.12, tongue=1.,
                 tail=(-.4, .2), tail_yaw=.4, roll=.1, ear_l=.3 if up else .1, flare=.1,
                 scratch=(.16 if up else .09))
    elif run == "k":
        # The shake: the body wrung one way and the other, nose to tail,
        # ears flung out.
        w = [1., 0., -1., 0.][k]
        P.update(head_roll=.7 * w, neck_yaw=.25 * w, roll=.12 * w, bend=-.12 * w, flare=.6 * abs(w) + .2,
                 ears=-.2, ear_l=.35 * w, ear_r=-.35 * w, tail_yaw=-.6 * w, tail=(.8, .1), lids=.6,
                 jaw=.05, tongue=0., neck=.75, rise=.01)
        P["feet"] = {"lf": (.03, 0., .02), "rf": (.03, 0., -.02), "lh": (-.03, 0., .02), "rh": (-.03, 0., -.02)}
    elif run == "f":
        # Going down: legs going, the front first, onto his chest, over,
        # flat on his side.
        if k == 0:
            P.update(front_drop=.08, rear_drop=.04, roll=-.08, neck=.4, nod=.2, jaw=.4, tongue=0., ears=.6,
                     lids=.5, brows=1., tail=(-.6, -.3))
            P["feet"] = {"lf": (.06, 0., .03), "rf": (-.02, 0., -.04), "lh": (.04, 0., .03), "rh": (.06, 0., -.03)}
        elif k == 1:
            P.update(front_drop=.26, rear_drop=.1, pitch=0., neck=.2, nod=.25, jaw=.2, tongue=0., ears=.5,
                     lids=.8, tail=(-.5, -.3))
            P["feet"] = {"lf": (.14, 0., .02), "rf": (.1, 0., -.02), "lh": (.06, 0., .02), "rh": (.04, 0., -.02)}
        else:
            P.update(low=True, lie_roll=[0., 0., .2, .85, 1.5][k], neck=[0, 0, .3, .1, .02][k],
                     nod=[0, 0, .25, .2, .1][k], jaw=.12, tongue=.4 if k == 4 else 0., ears=.2, lids=[0, 0, .7, .9, 1.][k],
                     tail=(-.15, -.05))
    elif run == "o":
        # Down on his side: breathing, the head lifted to whine, a paw going.
        lift = [0., .35, .5, .2][k]
        # (lying on his left side, his head comes up off the ground by
        # turning to his right)
        P.update(low=True, lie_roll=1.5 - .1 * lift, neck=.05, neck_yaw=-1.1 * lift, head_yaw=-.5 * lift,
                 nod=.1,
                 jaw=.1 if k != 2 else .26, tongue=.5 if k == 0 else 0., brows=lift * 2, lids=1. - lift * 1.4,
                 ears=.2, tail=(-.15, -.05), tail_yaw=[0., .15, 0., -.1][k])
        P["feet"] = {"lf": (.06 * s, .03 * c, 0.), "rf": (0., 0., 0.), "lh": (0., 0., 0.), "rh": (.03 * c, 0., 0.)}
    elif run == "v":
        # Got up by a hand on him: the head up, rolled onto his chest,
        # propped up on his forelegs.
        P.update(low=True, lie_roll=[1.5, 1.35, .7, .05, 0.][k], neck=[.1, .2, .45, .75, .85][k],
                 neck_yaw=[0., -.55, -.25, 0., 0.][k], head_yaw=[0., -.25, -.1, 0., 0.][k],
                 nod=[.1, -.1, 0., .05, .1][k], jaw=.12, tongue=[0, 0, 0, 1., 1.][k], brows=[1, 1, .6, .2, 0][k],
                 lids=[.8, .3, .1, 0, 0][k], ears=.1, tail=(-.2, 0.), tail_yaw=[0, 0, .2, -.2, .3][k],
                 rise=[0, 0, 0, .02, .1][k])
        if k == 4:
            P["front_up"] = True
    elif run == "u":
        # Up from his chest to his feet.
        if k == 0:
            P.update(low=True, lie_roll=0., neck=.85, nod=.1, rise=.1, jaw=.15, tongue=1., tail=(-.1, .1))
            P["front_up"] = True
        elif k == 1:
            P.update(sat=True, neck=.8, nod=.05, jaw=.15, tongue=1., tail=(-.3, .2), tail_yaw=.3)
        else:
            P.update(rear_drop=[0, 0, .22, .06, 0.][k], front_drop=[0, 0, -.02, 0, 0][k],
                     neck=[0, 0, .72, .8, .82][k], tail=[(0, 0), (0, 0), (.5, .15), (.85, .2), (1.0, .24)][k],
                     jaw=.18, tongue=1.)
            P["feet"] = {"lf": (0., 0., 0.), "rf": (0., 0., 0.), "lh": (.1, 0., 0.) if k == 2 else (0., 0., 0.),
                         "rh": (.12, 0., 0.) if k == 2 else (0., 0., 0.)}
    elif run == "j":
        # The lunge and bite: gathered low, the spring, the jaws clamped,
        # the yank back, braced to go again.
        P.update(**[
            dict(front_drop=.08, rear_drop=.1, neck=.35, nod=0., jaw=.25, tongue=0., ears=-.25, brows=1.,
                 tail=(.6, .2), flex=.12),
            dict(rise=.05, pitch=-.06, neck=.2, nod=.05, jaw=.8, tongue=0., ears=.5, brows=1., tail=(.4, .1),
                 flex=-.18, shift=.1),
            dict(front_drop=.06, pitch=.1, neck=.05, nod=.25, jaw=.05, tongue=0., ears=.2, brows=1.,
                 tail=(.5, .1), shift=.12),
            dict(rear_drop=.06, pitch=.04, neck=.25, nod=.0, head_yaw=.25, head_roll=-.3, jaw=.05, tongue=0.,
                 ears=-.1, ear_l=.3, ear_r=-.3, brows=1., tail=(.6, .2), shift=.04),
            dict(front_drop=.03, neck=.4, nod=-.12, jaw=.55, tongue=0., ears=-.2, brows=1., tail=(1.0, .5)),
        ][k])
        P["feet"] = [
            {"lf": (.06, 0., 0.), "rf": (.02, 0., 0.), "lh": (.06, 0., 0.), "rh": (.02, 0., 0.)},
            {"lf": (.34, .13, 0.), "rf": (.28, .1, 0.), "lh": (-.1, 0., 0.), "rh": (-.14, 0., 0.)},
            {"lf": (.24, 0., 0.), "rf": (.2, 0., 0.), "lh": (.02, 0., 0.), "rh": (-.04, 0., 0.)},
            {"lf": (.16, 0., 0.), "rf": (.2, 0., 0.), "lh": (-.04, 0., 0.), "rh": (-.08, 0., 0.)},
            {"lf": (.1, 0., 0.), "rf": (.06, 0., 0.), "lh": (-.04, 0., 0.), "rh": (-.07, 0., 0.)},
        ][k]
    elif run == "p":
        # Jaws clamped on a leg, hauling back: forelegs planted out in
        # front, hind legs braced under him, rump low, the head shaking.
        w = [1., 0., -1., 0.][k]
        P.update(rear_drop=.14, front_drop=.02, pitch=-.06, neck=.05, nod=.32, neck_yaw=.12 * w, head_yaw=.2 * w,
                 head_roll=.25 * w, jaw=.06, tongue=0., ears=.3, ear_l=.3 * w, ear_r=.3 * w, brows=1.,
                 tail=(.8, .25), tail_yaw=-.3 * w, roll=.04 * w, shift=-.04)
        P["feet"] = {"lf": (.2, 0., 0.), "rf": (.16, 0., 0.), "lh": (.02, 0., 0.), "rh": (.06, 0., 0.)}
    elif name == "sit":
        P.update(sat=True, neck=.95, nod=.15, jaw=.18, tongue=1., tail=(-.5, .3), tail_yaw=.45)
    elif name == "sniff":
        P.update(neck=-.75, nod=.55, pitch=.1, front_drop=.04, rise=-.02, jaw=0., tongue=0., tail=(1.1, .3),
                 tail_yaw=.25, ears=-.1)
        P["feet"] = {"lf": (.05, 0., 0.), "rf": (-.02, 0., 0.), "lh": (-.03, 0., 0.), "rh": (.02, 0., 0.)}
    elif name == "point":
        # Rigid: a foreleg up and curled, nose, back and tail in one line.
        P.update(neck=.38, nod=.12, jaw=0., tongue=0., pitch=.05, front_drop=.02, ears=-.15, brows=1.,
                 tail=(.25, .02), curl="lf")
        P["feet"] = {"lf": (.03, .18, 0.), "rf": (.03, 0., 0.), "lh": (-.08, 0., 0.), "rh": (-.05, 0., 0.)}
    elif name == "bark":
        P.update(neck=.6, nod=-.15, jaw=.65, tongue=0., ears=-.25, pitch=.06, front_drop=.04, brows=1.,
                 tail=(.95, .28))
        P["feet"] = {"lf": (.09, 0., 0.), "rf": (.06, 0., 0.), "lh": (-.04, 0., 0.), "rh": (-.07, 0., 0.)}
    elif name == "bay":
        # The howl: head thrown back, muzzle to the sky, the jaws open.
        P.update(neck=1.25, nod=-.85, jaw=.5, tongue=0., ears=.55, rise=.02, pitch=-.1, rear_drop=.04,
                 lids=.55, tail=(1.0, .3))
    elif name == "pain":
        # The yelp: crouched, tail clamped, head whipped round toward it.
        P.update(neck=.45, neck_yaw=-.7, head_yaw=-.3, nod=-.15, jaw=.5, tongue=0., ears=.9, rise=-.02,
                 front_drop=.08, rear_drop=.12, roll=-.06, bend=-.15, tail=(-1.0, -.4), lids=.6, brows=1.)
        P["feet"] = {"lf": (.06, 0., 0.), "rf": (.02, 0., 0.), "lh": (.1, 0., 0.), "rh": (.06, 0., 0.)}
    elif name == "fetch":
        P.update(neck=1.0, nod=-.05, jaw=.14, tongue=0., tail=(1.2, .4), tail_yaw=.35, ears=-.1)
    elif name == "rest":
        # Lying on his chest, chin down between his paws.
        P.update(low=True, lie_roll=0., neck=.05, nod=.42, jaw=0., tongue=0., lids=.45, brows=1., ears=.1,
                 tail=(-.2, -.05), tail_yaw=.35)
    elif name == "down":
        P.update(low=True, lie_roll=1.5, neck=.02, nod=.1, jaw=.1, tongue=.5, ears=.2, lids=1., tail=(-.15, -.05))
    return P


# ------------------------------------------------------------------ the dog


def _hd_lie_matrix(roll):
    """Lying low: on his chest (roll 0) or rolled over onto his left side
    (pi/2), resting on the ground either way."""
    # How high the body's middle rides off the ground at this roll: the
    # chest's depth below it, the ribs' half-width beside it.
    low = .035 + math.sqrt((.165 * math.cos(roll)) ** 2 + (.122 * math.sin(roll)) ** 2)
    return T((0, 0, low)) @ R(-roll, 0, 0) @ T((0, 0, -.5))


def _hd_body_frames(P):
    """The body's frames in the dog's (D) space: the whole body, its front
    half and its back half (the spine's flex and bend split between them)."""
    hip = Vector((_HD_HIP.x, 0, _HD_HIP.z))
    if P["sat"]:
        # On his haunches: the hips down by his hocks, the body tipped up.
        Tb = T((-.24, 0, .2)) @ R(0, -.68, 0) @ T(-hip)
        P["tilt"] = -.68
    elif P["low"]:
        Tb = _hd_lie_matrix(P["lie_roll"])
        if P.get("front_up"):
            # Propped on his forelegs, the hips still down.
            Tb = Tb @ T(hip) @ R(0, -.32, 0) @ T(-hip)
            P["tilt"] = -.32
    else:
        sh = Vector((_HD_SHOULDER.x, 0, _HD_SHOULDER.z))
        front, rear = P["front_drop"], P["rear_drop"]
        tip = math.atan2(front - rear, sh.x - hip.x)
        Tb = (T((P["shift"], 0, P["rise"] - rear)) @ T(hip) @ R(0, P["pitch"] + tip, 0) @ R(P["roll"], 0, 0)
              @ T(-hip))
        P["tilt"] = (P["pitch"] + tip - P["flex"] * .5) * .6
    w = _HD_WAIST
    Bf = Tb @ T(w) @ R(0, -P["flex"] * .5, P["bend"] * .5) @ T(-w)
    Br = Tb @ T(w) @ R(0, P["flex"] * .5, -P["bend"] * .5) @ T(-w)
    return Tb, Bf, Br


# The trunk's sections (B, standing): x, the back's top, the belly's
# bottom, the half width; the front and the back hides.
_HD_FRONT = ((.445, .54, .45, .022), (.43, .585, .4, .055), (.39, .63, .355, .085), (.32, .655, .33, .102),
             (.22, .665, .318, .112), (.1, .66, .33, .114), (0., .65, .37, .108), (-.09, .645, .41, .098),
             (-.12, .615, .46, .045))
_HD_BACK = ((.05, .62, .41, .045), (.01, .648, .38, .1), (-.08, .64, .425, .094), (-.16, .638, .45, .09),
            (-.24, .648, .445, .1), (-.31, .645, .43, .102), (-.37, .625, .435, .09), (-.41, .59, .46, .06),
            (-.428, .555, .49, .025))


def _hd_loft(sections, m, F):
    """A smooth closed hide through `sections` (x, top, bottom, half width):
    each an egg's section, broad over the back and narrowing to the keel
    of the chest, its coat in the body's frame (its own coordinates)."""
    n = 20
    bm = bmesh.new()
    rings = []
    for x, top, bottom, half in sections:
        zc, hz = (top + bottom) / 2, (top - bottom) / 2
        ring = []
        for i in range(n):
            t = i / n * math.tau
            c, s_ = math.cos(t), math.sin(t)
            # narrower toward the keel (the bottom: cos < 0)
            w = half * (1. - .28 * max(0., -c) ** 1.5)
            ring.append(bm.verts.new((x, s_ * w, zc + c * hz)))
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    for ring, flip in ((rings[0], False), (rings[-1], True)):
        mid = bm.verts.new((sum(v.co.x for v in ring) / n, 0, sum(v.co.z for v in ring) / n))
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((ring[i], ring[j], mid) if not flip else (ring[j], ring[i], mid))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = place(bm, F, m)
    _hd_coat_co(ob, Matrix.Identity(4))
    return ob


def _hd_paw(at, along, F, K, P_h):
    """A tight cat foot at `at` (D space), its toes toward `along`, its pads
    under: the main pad's ball, four toes, dark nails."""
    fwd = Vector(along).normalized()
    up = Vector((0, 0, 1)) if abs(fwd.z) < .9 else Vector((1, 0, 0))
    side = up.cross(fwd).normalized()
    up = fwd.cross(side).normalized()
    Mf = Matrix((
        (fwd.x, side.x, up.x, at.x),
        (fwd.y, side.y, up.y, at.y),
        (fwd.z, side.z, up.z, at.z),
        (0, 0, 0, 1)))
    leg = K["leg"]
    _hd_ball((.012, 0, .02), (.046, .035, .026), leg, F @ Mf, P=T((0, 0, P_h)))
    for t, (dy, dx) in enumerate(((-.022, .036), (-.008, .046), (.008, .046), (.022, .036))):
        _hd_ball((dx, dy, .016), (.018, .0135, .016), leg, F @ Mf, P=T((0, 0, P_h)))
        _hd_ball((dx + .016, dy, .008), (.007, .005, .006), K["pad"], F @ Mf)


def _hd_leg(F, K, hip, foot, lens, radii, front, pole, mode, P_h, curl=False, along=None, lie=None):
    """One leg from the joint at the body (`hip`, D space) to its foot:
    upper and middle pieces by IK, the low piece (pastern or hock) of fixed
    length, a muscle on the upper piece and the middle one, the paw. Modes:
    "stand" (the foot on `foot`), "fold" (a hind leg folded under him, the
    hock flat behind the foot), "lifted" (the foot carried: the low piece
    folds back)."""
    l1, l2, l3 = lens
    r0, r1, r2, r3 = radii
    foot = Vector(foot)
    fwd = Vector(along) if along is not None else Vector((1, 0, 0))
    if mode == "fold":
        hock = foot - fwd * l3 + Vector((0, 0, .03))
        knee, hock = ik(hip, hock, l1, l2, fwd + Vector((0, 0, .7)))
        wrist, paw = hock, hock + (foot - hock).normalized() * l3
    else:
        if curl:
            low = Vector((-.5, 0, -1)).normalized() * l3 if front else Vector((.3, 0, -1)).normalized() * l3
            knee, wrist = ik(hip, foot - low, l1, l2, pole)
            paw = wrist + low
        else:
            lift = max(0., min(1., foot.z / .12))
            if front:
                low = (Vector((-.12, 0, 1)).lerp(Vector((.9, 0, .5)), lift)).normalized() * l3
            else:
                low = (Vector((.62, 0, 1)).lerp(Vector((.3, 0, 1)), lift)).normalized() * l3
            # the low piece points up from the foot along the leg (a lying
            # dog's "up" is his own)
            if lie is not None:
                low = lie @ low
            knee, wrist = ik(hip, foot + low, l1, l2, pole)
            paw = wrist - low
    leg = K["leg"]
    flip = Matrix.Diagonal((1, 1, -1, 1))
    hh = P_h
    # each piece as wide where it starts as the last where it ends, the
    # joints capped flush: one tapering leg, no knobs at the joints
    _hd_limb(hip, knee, r0, r1, leg, F, P=T((0, 0, hh[0])) @ flip)
    _hd_limb(knee, wrist, r1, r2, leg, F, P=T((0, 0, hh[1])) @ flip)
    _hd_limb(wrist, paw, r2, r3, leg, F, P=T((0, 0, hh[2])) @ flip, seg=12)
    _hd_ball(knee, r1, leg, F, P=T((0, 0, hh[1] + l2 * .5)))
    _hd_ball(wrist, r2, leg, F, P=T((0, 0, hh[2] + l3 * .5)))
    if front:
        # the shoulder's mass on the upper arm, the forearm's muscle
        _hd_seg_ball(hip, knee, .35, (.055, .05, .11), leg, F, P=T((0, 0, hh[0])) @ flip)
        _hd_seg_ball(knee, wrist, .3, (.034, .041, .13), leg, F, P=T((0, 0, hh[1])) @ flip)
    else:
        # the ham: the big muscle of the thigh, and the second thigh
        _hd_seg_ball(hip, knee, .45, (.072, .082, .16), leg, F, P=T((0, 0, hh[0])) @ flip, side=-.01)
        _hd_seg_ball(knee, wrist, .33, (.036, .042, .13), leg, F, P=T((0, 0, hh[1])) @ flip, side=-.008)
    toes = Vector((fwd.x, fwd.y, 0)) if mode != "lifted" else (Vector((fwd.x, fwd.y, 0)) * .3 + (paw - wrist).normalized())
    if curl:
        toes = (paw - wrist).normalized() + Vector((0, 0, -.6))
    _hd_paw(paw, toes, F, K, hh[2] - l3 * .5)


def _hd_head(Hm, P, K):
    """The head in its frame Hm: the neck's top at the origin, +x down the
    muzzle, z up. Returns the jaw's frame."""
    h = K["head"]
    # the skull: domed, narrow, the peak of the occiput behind
    _hd_ball((.04, 0, .03), (.092, .055, .056), h, Hm)
    # cheeks, the brow ridges, the stop
    for sd in (-1, 1):
        _hd_ball((.07, sd * .036, .008), (.062, .026, .042), h, Hm)
        _hd_ball((.104, sd * .033, .052), (.027, .018, .011), h, Hm, rot=(0, -.15, 0))
    _hd_ball((.122, 0, .045), (.036, .032, .03), h, Hm)
    # the muzzle: long and square, the bridge over it
    _hd_limb((.115, 0, .018), (.238, 0, .012), .041, .035, h, Hm)
    _hd_ball((.238, 0, .012), (.035, .035, .035), h, Hm)
    _hd_ball((.18, 0, .04), (.074, .03, .016), h, Hm)
    # the flews hanging past the lower jaw, the lips' corners
    for sd in (-1, 1):
        _hd_ball((.185, sd * .029, -.018), (.068, .015, .034), h, Hm, rot=(sd * .06, -.08, 0))
        _hd_ball((.112, sd * .034, -.018), (.032, .016, .026), h, Hm)
    # the nose, big and black, its nostrils
    _hd_ball((.262, 0, .024), (.022, .03, .022), K["nose"], Hm)
    for sd in (-1, 1):
        _hd_ball((.281, sd * .012, .021), (.006, .007, .006), K["nostril"], Hm)
    # canines under the flews
    for sd in (-1, 1):
        _hd_ball((.205, sd * .02, -.022), (.005, .005, .011), K["tooth"], Hm)
    # the lower jaw on its hinge: the mouth inside, the teeth, the tongue
    J = Hm @ T((.068, 0, -.016)) @ R(0, P["jaw"], 0)
    _hd_limb((0, 0, 0), (.165, 0, -.008), .026, .019, h, J, P=T((.068, 0, -.016)))
    _hd_ball((.165, 0, -.008), (.02, .02, .02), h, J, P=T((.068, 0, -.016)))
    _hd_ball((.09, 0, .011), (.075, .021, .01), K["mouth"], J)
    for sd in (-1, 1):
        _hd_ball((.158, sd * .016, .016), (.005, .005, .01), K["tooth"], J)
    # one tongue: in the mouth, or lolling out over the teeth as he pants
    t = P["tongue"]
    tongue_at = Vector((.085, 0, .014)).lerp(Vector((.16, -.012, -.004)), t)
    _hd_ball(tongue_at, (.052, .021, .007), K["tongue"], J, rot=(0, .55 * t, 0))
    # the eyes: brown, a glint, the haw under each, the upper lid that
    # closes down over it (swung up under the brow while open)
    for sd in (-1, 1):
        # set into the head under the brow, looking out and forward
        eye = Vector((.11, sd * .037, .04))
        E = Hm @ T(eye) @ R(0, 0, sd * .45)
        _hd_ball((0, 0, 0), .013, K["eye"], E)
        _hd_ball((.0075, 0, .001), (.005, .0062, .0062), K["pupil"], E)
        _hd_ball((.0095, sd * -.003, .006), .0026, K["glint"], E)
        # the droop of the lower lid: the red haw, a dark rim over it
        _hd_ball((.002, 0, -.0115), (.011, .0095, .005), K["haw"], E)
        _hd_ball((.001, 0, -.0145), (.0125, .0105, .0042), K["lid"], E)
        shut = P["lids"]
        lid = E @ R(0, -.9 + 1.25 * shut, 0)
        _hd_ball((.0, 0, .009), (.0165, .0158, .0075), K["lid"], lid)
        # the brow's tan pip, lifted when he frets
        pip = Vector((-.004, 0, .02 + .006 * P["brows"]))
        _hd_ball(pip, (.012, .011, .006), h, E, P=T(eye) @ R(0, 0, sd * .5) @ T(pip))
    return J


def _hd_ears(Hm, P, K):
    """The ears: low-set behind the eyes, long, folded at the top, hanging
    well past the jaw; swung back by speed or a yelp, flared by a shake,
    each side its own swing, the lower leather lagging the upper."""
    ear = K["ear"]
    for sd, own in ((1, P["ear_l"]), (-1, P["ear_r"])):
        swing = .35 * P["ears"] - own
        E = Hm @ T((.036, sd * .057, .036)) @ R(sd * (-.05 + .8 * P["flare"]), swing, 0)
        # set on at eye level, the leather folded over at the top
        _hd_ball((.0, sd * .003, -.014), (.024, .008, .02), ear, E)
        _hd_ball((-.004, sd * .004, -.048), (.04, .005, .05), ear, E, rot=(0, .08, 0))
        # its front edge rolled in, as a hound's ear hangs
        _hd_ball((.03, sd * -.001, -.05), (.009, .008, .046), ear, E, rot=(0, .08, 0))
        E2 = E @ T((-.008, sd * .004, -.08)) @ R(-sd * .28, swing * .4, 0)
        _hd_ball((-.004, 0, -.03), (.044, .0048, .042), ear, E2, rot=(0, .05, 0))
        _hd_ball((.032, sd * -.004, -.026), (.008, .008, .034), ear, E2, rot=(0, .05, 0))


def _hd_body(P, K, M):
    """The body, neck, head, legs and tail; M the dog's frame (D -> world)."""
    Tb, Bf, Br = _hd_body_frames(P)
    b = K["body"]
    Ff = M @ Bf
    Fr = M @ Br
    # The trunk: two smooth hides lofted through the body's sections (the
    # front from the chest's point back past the waist, the back from the
    # ribs to the buttocks, overlapping where the spine bends): a deep
    # narrow chest down to the elbows, the withers a little over the croup,
    # the belly tucked up under the loin. The shoulder blades over it.
    _hd_loft(_HD_FRONT, b, Ff)
    _hd_loft(_HD_BACK, b, Fr)
    for sd in (-1, 1):
        _hd_ball((.27, sd * .07, .53), (.095, .04, .07), b, Ff, rot=(0, -.6, 0))
    # the neck: up from the withers, muscled along its crest, the hound's
    # dewlap loose under the throat
    base = Vector((.32, 0, .58))
    top = base + Vector((math.cos(P["neck"]), 0, math.sin(P["neck"]))) * .23
    N = Ff @ T(base) @ R(0, 0, P["neck_yaw"]) @ T(-base)
    _hd_limb(base, top, .078, .06, b, N, P=None)
    _hd_seg_ball(base, top, .45, (.07, .066, .12), b, N, side=0)
    _hd_seg_ball(base, top, .6, (.045, .05, .09), b, N, side=.04)
    # the collar: a worn red strap round the neck's root, its buckle, a
    # brass tag
    collar = base.lerp(top, .38)
    d = (top - base).normalized()
    u = Vector((0, 1, 0))
    v = d.cross(u)
    for k in range(24):
        a0, a1 = k / 24 * math.tau, (k + 1) / 24 * math.tau
        p0 = collar + (u * math.cos(a0) + v * math.sin(a0)) * .083
        p1 = collar + (u * math.cos(a1) + v * math.sin(a1)) * .083
        _hd_limb(p0, p1, .016, .016, K["collar"], N, seg=8)
    _hd_ball(collar + v * -.086, (.012, .016, .01), K["buckle"], N)
    tag = collar + v * .094 + Vector((.012, 0, -.03))
    _hd_ball(tag, (.018, .005, .02), K["tag"], N)
    # the head on the neck's top: lifted, nodded, turned, rolled
    Hm = (N @ T(top) @ R(0, 0, P["head_yaw"]) @ R(0, -P["neck"] * .3 + .45 + P["nod"] - P.get("tilt", 0.), 0)
          @ R(P["head_roll"], 0, 0) @ Matrix.Diagonal((_HD_HEAD, _HD_HEAD, _HD_HEAD, 1)))
    _hd_head(Hm, P, K)
    _hd_ears(Hm, P, K)
    # the legs
    fwd = Vector((1, 0, 0))
    lie = Matrix.Identity(3)
    if P["low"]:
        L = _hd_lie_matrix(P["lie_roll"])
        lie = L.to_3x3()
        k_side = max(0., min(1., (P["lie_roll"] - .3) / .9))
    for leg, sd, front in (("lf", 1, True), ("rf", -1, True), ("lh", 1, False), ("rh", -1, False)):
        dx, dz, dy = P["feet"][leg]
        joint = Vector((_HD_SHOULDER.x, sd * _HD_SHOULDER.y, _HD_SHOULDER.z)) if front else             Vector((_HD_HIP.x, sd * _HD_HIP.y, _HD_HIP.z))
        if front and not P["sat"] and not P["low"]:
            # the shoulder blade swinging with the foreleg (pass 12)
            joint.x += P.get("reach", 0.) * dx
        hip = (Bf if front else Br) @ joint
        rest = _HD_FOOT_F if front else _HD_FOOT_H
        foot = Vector((rest.x + dx, sd * rest.y + dy, rest.z + dz))
        mode = "stand"
        if P["sat"]:
            foot = Vector((.14, sd * .085, 0)) if front else Vector((-.06, sd * .12, 0))
            if not front:
                mode = "fold"
            if not front and P["scratch"] is not None and leg == "lh":
                # the scratching foot up at the left ear
                foot = Vector((.02, .17, .22 + P["scratch"]))
                mode = "lifted"
        elif P["low"]:
            # On his chest the feet lie on the ground (D space): the forelegs
            # out in front, the hind folded at his sides; rolled onto his side
            # they stick out from him, a little bent (his own frame, carried
            # by the lie).
            if front:
                tuck = Vector((.33, sd * .08, 0)) if P.get("front_up") else Vector((.62, sd * .075, .02))
                out = L @ Vector((.47 + dx, sd * .07, .08 + dz))
            else:
                tuck = Vector((-.1, sd * .15, .02))
                out = L @ Vector((-.58 + dx, sd * .09, .1 + dz))
            foot = tuck.lerp(out, k_side)
            foot.z = max(.025, foot.z)
            if not front and k_side < .5:
                mode = "fold"
        elif front and P["curl"] == leg:
            mode = "lifted"
        elif foot.z > .02:
            mode = "lifted"
        if front:
            pole = lie @ (Vector((-1, 0, -.15)) if not P["low"] or P.get("front_up") else Vector((-1, 0, -.6)))
            _hd_leg(M, K, hip, foot, (_HD_ARM, _HD_FORE, _HD_PASTERN), (.058, .05, .033, .03), True, pole,
                    mode, (.37, .2, .05), curl=P["curl"] == leg, along=fwd, lie=lie)
        else:
            pole = lie @ Vector((1, 0, -.1))
            _hd_leg(M, K, hip, foot, (_HD_THIGH, _HD_GASKIN, _HD_META), (.072, .054, .034, .03), False, pole,
                    mode, (.42, .24, .07), along=fwd, lie=lie)
    # the tail from the top of the rump: a saber, up and curving forward
    _hd_tail(Fr, P, K)


def _hd_tail(Fr, P, K):
    root = Vector((-.395, 0, .615))
    lift, curl = P["tail"]
    yaw, whip = P["tail_yaw"], P["tail_whip"]
    pieces = (.08, .075, .07, .065, .055)
    radii = (.036, .031, .026, .02, .014, .007)
    at = root
    along = 0.
    t = K["tail"]
    for k, length in enumerate(pieces):
        a = lift + curl * k
        y = yaw + whip * k / 4.
        d = Vector((-math.cos(a) * math.cos(y), math.sin(y) * math.cos(a), math.sin(a)))
        end = at + d * length
        mid = along + length * .5
        L = T((at + end) / 2) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        _hd_limb(at, end, radii[k], radii[k + 1], t, Fr, P=T((0, 0, mid)))
        _hd_ball(end, radii[k + 1] * 1.04, t, Fr, P=T((0, 0, along + length)))
        at = end
        along += length
    _hd_ball(root, radii[0] * 1.08, t, Fr, P=T((0, 0, 0)))


def _hd_frame_matrix():
    """Where the whole dog stands: for the model square, head toward -y; for
    the cels turned a little to the camera."""
    if FOR_MODEL:
        return R(0, 0, -math.pi / 2)
    return R(0, 0, -.32)


def hound(frame):
    global LAST_J
    P = _hd_pose(frame)
    K = _hd_kit()
    M = _hd_frame_matrix()
    _hd_body(P, K, M)
    # Where his head is standing (export_actors.py labels the parts near it
    # "head" and gives them more of the texture).
    if str(frame) == "0":
        LAST_J = (HOUND, {"dog_head": M @ Vector((.6, 0, .72))})


def hound_face(frame):
    """The badge's head: turned most of the way to profile and a little to
    the camera, so the long muzzle, the hound's droop, an eye and the long
    ear read at 28 pixels; the red collar's edge under the jaw."""
    # A portrait's light: the dusk stage's rims turned down, so his black
    # hood and ears read black at the badge's size, not rim-lit grey.
    if "rim" in LIGHTS:
        LIGHTS["rim"][0].energy = 2.2
        LIGHTS["rim2"][0].energy = 1.4
        LIGHTS["key"][0].energy = 5.4
        LIGHTS["bg"].inputs[1].default_value = .3
    _HD_CLEAN[0] = True
    K = _hd_kit()
    P = _hd_rest()
    P.update(ears=.1, flare=.0, jaw=.2, tongue=1.)
    if frame == 1:
        P.update(jaw=.04, tongue=0., ears=-.15, brows=1.)
    elif frame == 2:
        P.update(jaw=.34, tongue=0., ears=.5, lids=.55, brows=1.)
    elif frame == "down":
        P.update(jaw=.1, tongue=.5, ears=.25, lids=1.)
    # (the camera looks along +y; his muzzle to the right, toward it a touch)
    Hm = (T((-.0, 0, .215)) @ R(0, 0, -.62) @ R(0, .14, 0) @ T((-.12, 0, 0))
          @ Matrix.Diagonal((.86, .86, .86, 1)))
    _hd_head(Hm, P, K)
    _hd_ears(Hm, P, K)
    # a short stump of the neck under it, the red collar's edge round it
    neck = Hm @ Vector((-.02, 0, -.03))
    _hd_limb(neck + Vector((-.01, .02, -.09)), neck, .076, .066, K["body"], None, P=T((.4, 0, .66)))
    collar = neck + Vector((-.005, .01, -.075))
    for k in range(24):
        a0, a1 = k / 24 * math.tau, (k + 1) / 24 * math.tau
        p0 = collar + Vector((math.cos(a0), math.sin(a0), 0)) * .078
        p1 = collar + Vector((math.cos(a1), math.sin(a1), 0)) * .078
        _hd_limb(p0, p1, .013, .013, K["collar"], None, seg=8)
    _hd_ball(collar + Vector((.035, -.074, -.022)), (.015, .006, .017), K["tag"])
    _HD_CLEAN[0] = False


ACTORS.update({
    "hound": (hound, HOUND, (), HOUND_CELS),
    "hound_face": (hound_face, HOUND_FACE, (), FACE_CELS),
})
