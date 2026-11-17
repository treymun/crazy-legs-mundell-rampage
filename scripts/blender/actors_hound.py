"""BLUE, Mundell's bluetick coonhound (src/features/hound.gd), exec'd by
enemy_actors.py into its own namespace after ACTORS is made, so ball, limb,
mat, T, R, ik, Vector and the rest are in scope. Built from scratch: nothing
is traced from another game or a photograph.

    hound       a lanky bluetick: a white coat thick with slate-blue ticking,
                black saddle patches and a black hood over the ears and eyes,
                tan pips over the eyes, tan cheeks and tan socks, long low-set
                ears that hang past the jaw, a deep chest, a tucked waist and a
                saber tail carried high; a worn red collar with a brass tag.
    hound_face  his head alone, turned three-quarters to the camera, for the
                HUD's badge (src/hound_looks.gd): 0 panting, 1 on the scent,
                2 hurt, down out cold.

His frames (own, so the cels and the model are just these):

    0, wag          standing, panting, the tail one way then the other
    w0..w3 (w4)     the walk, four beats (w4 is w0 again: the loop's end)
    r0..r3 (r4)     the gallop: stretched, front down, gathered, hind push
    sit             sat on his haunches (STAY)
    bark            braced, head out, jaws wide
    bay             head thrown back, baying at a secret or new iron
    bite            the lunge, low and long, jaws wide
    pin, pin2       hauling back on a hand he has by the leg, head shaking
    fetch           head high with something in his mouth
    point           a foreleg up and curled, nose and tail in one line
    sniff           nose to the ground
    pain            the yelp: crouched, tail tucked, head whipped round
    down            out cold on his side, legs loose
    whine           flat on his belly, chin on his paws, brows up

Seen side on (x along the body, head to +x, y away from the camera, z up),
turned a little to the camera for the cels; for the model (FOR_MODEL, set by
export_actors.py) square, head toward -y, as the people are. Every leg is
built from pieces of fixed length posed by two-bone IK, so each piece is the
same part in every frame (export_actors.py matches parts by shape).
"""

HOUND = dict(canvas=(1.5, 1.0), px=60)
# The badge is cels only: export_actors.py makes no model of it.
HOUND_FACE = dict(canvas=(.46, .46), px=40, cels_only=True)
HOUND_CELS = [0, "wag", "w0", "w1", "w2", "w3", "w4", "r0", "r1", "r2", "r3", "r4", "sit", "bark", "bay",
              "bite", "pin", "pin2", "fetch", "point", "sniff", "pain", "down", "whine"]
FACE_CELS = [0, 1, 2, "down"]
PLAIN_KINDS = tuple(PLAIN_KINDS) + ("hound", "hound_face")

# Leg pieces (metres): the front's upper arm, forearm and pastern; the hind's
# thigh, gaskin and hock-to-foot.
_ARM, _FORE, _PASTERN = .21, .26, .08
_THIGH, _GASKIN, _META = .24, .26, .15
_TICK_MATS = {}
# His head is a little big for him: a hound's.
_HEAD = Matrix.Diagonal((1.14, 1.14, 1.14, 1))
# The coats: [base, ticks, flecks a metre, how much of it is ticked].
_COATS = {
    "coat": ((178, 184, 190), (30, 38, 56), 150., .72),
    "fine": ((192, 196, 198), (58, 66, 86), 290., .5),
    "legs": ((176, 180, 186), (36, 44, 60), 170., .72),
    "tan": ((150, 96, 56), (60, 42, 30), 190., .36),
}


def _ticked(which, size):
    """The bluetick coat `which` for a part `size` across in its own
    coordinates (1 for a limb, which is made at its size; a ball's radius, as
    a ball is a unit sphere scaled): pale hair thick with small dark flecks,
    and a soft roan of the same blue through it, so it reads slate-blue from
    across a yard and ticked up close."""
    base, dark, per_metre, amount = _COATS[which]
    density = round(per_metre * size * 2) / 2
    key = (which, density)
    if key in _TICK_MATS and _TICK_MATS[key].name in bpy.data.materials:
        return _TICK_MATS[key]
    m = bpy.data.materials.new("tick%d" % len(_TICK_MATS))
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    bsdf.inputs["Roughness"].default_value = .86
    coord = nt.nodes.new("ShaderNodeTexCoord")
    lb = tuple(lin(c) for c in base) + (1,)
    ld = tuple(lin(c) for c in dark) + (1,)
    roan = tuple(lin(a * .4 + b * .6) for a, b in zip(base, dark)) + (1,)
    # the roan: soft blotches of blue-grey through the pale hair
    soft = nt.nodes.new("ShaderNodeTexNoise")
    soft.inputs["Scale"].default_value = max(.5, density * .22)
    soft.inputs["Detail"].default_value = 3.0
    nt.links.new(coord.outputs["Object"], soft.inputs["Vector"])
    soft_ramp = nt.nodes.new("ShaderNodeMapRange")
    soft_ramp.inputs[1].default_value = .38
    soft_ramp.inputs[2].default_value = .66
    soft_ramp.inputs[4].default_value = .9
    nt.links.new(soft.outputs[0], soft_ramp.inputs[0])
    mix1 = nt.nodes.new("ShaderNodeMix")
    mix1.data_type = "RGBA"
    mix1.inputs[6].default_value = lb
    mix1.inputs[7].default_value = roan
    nt.links.new(soft_ramp.outputs[0], mix1.inputs[0])
    # the ticks: small hard flecks
    fleck = nt.nodes.new("ShaderNodeTexNoise")
    fleck.inputs["Scale"].default_value = max(1., density)
    fleck.inputs["Detail"].default_value = 2.0
    nt.links.new(coord.outputs["Object"], fleck.inputs["Vector"])
    gate = nt.nodes.new("ShaderNodeMapRange")
    gate.inputs[1].default_value = .6 - amount * .16
    gate.inputs[2].default_value = .63 - amount * .16
    nt.links.new(fleck.outputs[0], gate.inputs[0])
    mix2 = nt.nodes.new("ShaderNodeMix")
    mix2.data_type = "RGBA"
    mix2.inputs[7].default_value = ld
    nt.links.new(mix1.outputs[2], mix2.inputs[6])
    nt.links.new(gate.outputs[0], mix2.inputs[0])
    # road dirt up the legs, as every actor has
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sepz = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Position"], sepz.inputs[0])
    ramp = nt.nodes.new("ShaderNodeMapRange")
    ramp.inputs[1].default_value = .0
    ramp.inputs[2].default_value = .22
    ramp.inputs[3].default_value = .5
    ramp.inputs[4].default_value = .0
    nt.links.new(sepz.outputs[2], ramp.inputs[0])
    mud = nt.nodes.new("ShaderNodeMix")
    mud.data_type = "RGBA"
    mud.inputs[7].default_value = (lin(80), lin(62), lin(44), 1)
    nt.links.new(ramp.outputs[0], mud.inputs[0])
    nt.links.new(mix2.outputs[2], mud.inputs[6])
    nt.links.new(mud.outputs[2], bsdf.inputs["Base Color"])
    # the lie of the coat: a fine bump
    hair = nt.nodes.new("ShaderNodeTexNoise")
    hair.inputs["Scale"].default_value = max(1., density * 1.7)
    hair.inputs["Detail"].default_value = 2.0
    nt.links.new(coord.outputs["Object"], hair.inputs["Vector"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = .25
    bump.inputs["Distance"].default_value = .02
    nt.links.new(hair.outputs[0], bump.inputs["Height"])
    nt.links.new(bump.outputs[0], bsdf.inputs["Normal"])
    _TICK_MATS[key] = m
    return m


def _tb(c, r, which, M=None, rot=(0, 0, 0)):
    """A ball in coat `which`, its ticks the size of the rest."""
    size = (sum(r) / 3) if isinstance(r, (tuple, list)) else r
    ball(c, r, _ticked(which, size), M, rot)


def _tl(a, b, ra, rb, which, M=None, caps=True, seg=18):
    """A limb in coat `which` (its caps ticked to match)."""
    a, b = Vector(a), Vector(b)
    if M is not None:
        a, b = M @ a, M @ b
    limb(a, b, ra, rb, _ticked(which, 1.), None, caps=False, seg=seg)
    if caps:
        _tb(a, ra * 1.045, which)
        _tb(b, rb * 1.045, which)


def _coat():
    """The plain materials: the black of his saddle and hood, the eyes, nose,
    mouth, collar and tag."""
    return dict(
        black=mat(30, 32, 40, .82, grime=.2),
        tan=mat(136, 84, 48, .82, grime=.35),
        nose=mat(26, 22, 24, .32, grime=0),
        eye=mat(58, 32, 18, .12, grime=0),
        glint=mat(240, 236, 226, .2, grime=0),
        lid=mat(84, 86, 96, .82, grime=.2),
        mouth=MOUTH(),
        tongue=mat(198, 88, 96, .4, grime=0),
        haw=mat(96, 46, 44, .5, grime=0),
        tooth=TOOTH(),
        pad=mat(36, 32, 32, .7, grime=.2),
        collar=mat(146, 40, 28, .62, grime=.5),
        tag=BRASS(),
        tip=mat(214, 212, 204, .86, grime=.35),
    )


def _pose_of(frame):
    """Everything a frame poses: the body's height and pitch, the neck's lift
    and turn, the jaw, ears and tail, each foot's place; walk and gallop beats
    from their phase."""
    P = dict(rise=0., pitch=0., lift=0., neck=.45, yaw=0., nod=0., jaw=.22, tongue=True,
             ears=0., ears_up=0., tail=(.9, .3, .15), tail_yaw=.18, crouch=0.,
             feet={"lf": (.0, .0), "rf": (.0, .0), "lh": (.0, .0), "rh": (.0, .0)},
             paw_curl=None, lids=0., brows=0., sat=False, lie=None, stretch=0.)
    name = str(frame)
    if name == "w4":
        name = "w0"
    if name == "r4":
        name = "r0"
    if name == "wag":
        P["tail_yaw"] = -.3
    elif name.startswith("w") and name[1:].isdigit():
        k = int(name[1:])
        # A four-beat walk: each foot a quarter of a stride after the last
        # (left hind, left fore, right hind, right fore).
        offs = {"lh": 0., "lf": .25, "rh": .5, "rf": .75}
        feet = {}
        for leg, o in offs.items():
            a = (k / 4.0 + o) * math.tau
            feet[leg] = (.13 * math.sin(a), .07 * max(0., math.cos(a)))
        P["feet"] = feet
        P["tail_yaw"] = .25 * math.sin(k / 4.0 * math.tau)
        P["nod"] = .04 * math.sin(k / 2.0 * math.tau)
        P["rise"] = .012 * math.cos(k / 2.0 * math.tau)
    elif name.startswith("r") and name[1:].isdigit():
        # The rotary gallop, four beats: stretched out in the air, the fore
        # feet striking, gathered with the hind feet under him, the hind push.
        k = int(name[1:])
        P["neck"] = .2
        P["ears"] = .9
        P["tail"] = (.25, .1, .05)
        P["tail_yaw"] = 0.
        P["jaw"] = .3
        P["feet"] = [
            {"lf": (.3, .1), "rf": (.24, .14), "lh": (-.3, .1), "rh": (-.24, .14)},
            {"lf": (.1, 0.), "rf": (.18, .03), "lh": (-.22, .16), "rh": (-.14, .2)},
            {"lf": (-.18, .12), "rf": (-.1, .06), "lh": (.12, .04), "rh": (.2, .1)},
            {"lf": (.02, .24), "rf": (-.06, .2), "lh": (-.02, 0.), "rh": (.06, .03)},
        ][k]
        P["rise"] = [.06, -.02, -.04, .02][k]
        P["pitch"] = [0., .1, -.06, -.1][k]
        P["stretch"] = [.05, 0., -.05, 0.][k]
        P["nod"] = [-.05, .1, .05, -.08][k]
    elif name == "sit":
        P["sat"] = True
        P["neck"] = .7
        P["tail"] = (-.6, .4, .2)
        P["tail_yaw"] = .5
        P["jaw"] = .18
    elif name == "bark":
        P["neck"] = .35
        P["nod"] = -.15
        P["jaw"] = .62
        P["tongue"] = False
        P["ears_up"] = .35
        P["pitch"] = .08
        P["rise"] = -.03
        P["feet"] = {"lf": (.09, 0.), "rf": (.06, 0.), "lh": (-.04, 0.), "rh": (-.07, 0.)}
        P["tail"] = (1.1, .7, .45)
        P["brows"] = 1.
    elif name == "bay":
        P["neck"] = 1.05
        P["nod"] = -.75
        P["jaw"] = .55
        P["tongue"] = False
        P["ears"] = .5
        P["tail"] = (1.25, .9, .7)
        P["tail_yaw"] = 0.
        P["rise"] = .02
        P["pitch"] = -.08
        P["lids"] = .5
    elif name == "bite":
        P["neck"] = -.05
        P["nod"] = .1
        P["jaw"] = .75
        P["tongue"] = False
        P["pitch"] = .16
        P["rise"] = -.08
        P["stretch"] = .06
        P["ears_up"] = .2
        P["feet"] = {"lf": (.16, 0.), "rf": (.1, 0.), "lh": (-.16, 0.), "rh": (-.2, 0.)}
        P["tail"] = (.6, .3, .15)
        P["tail_yaw"] = 0.
        P["brows"] = 1.
    elif name in ("pin", "pin2"):
        side = 1 if name == "pin" else -1
        P["neck"] = -.35
        P["nod"] = .35
        P["yaw"] = .32 * side
        P["jaw"] = .1
        P["tongue"] = False
        P["pitch"] = .2 if name == "pin" else .15
        P["rise"] = -.1
        P["crouch"] = .07
        P["feet"] = {"lf": (.16, 0.), "rf": (.12, 0.), "lh": (-.2, 0.), "rh": (-.16, 0.)}
        P["tail"] = (.9, .55, .3)
        P["tail_yaw"] = -.35 * side
        P["ears"] = .35
        P["brows"] = 1.
    elif name == "fetch":
        P["neck"] = .75
        P["nod"] = -.1
        P["jaw"] = .12
        P["tongue"] = False
        P["tail"] = (1.15, .75, .5)
        P["tail_yaw"] = .35
        P["ears_up"] = .15
    elif name == "point":
        P["neck"] = .2
        P["nod"] = .02
        P["jaw"] = 0.
        P["tongue"] = False
        P["pitch"] = .06
        P["rise"] = -.02
        P["ears_up"] = .35
        P["feet"] = {"lf": (.04, 0.), "rf": (.04, .2), "lh": (-.08, 0.), "rh": (-.05, 0.)}
        P["paw_curl"] = "rf"
        P["tail"] = (.18, .1, .05)
        P["tail_yaw"] = 0.
        P["brows"] = 1.
    elif name == "sniff":
        P["neck"] = -.9
        P["nod"] = .55
        P["jaw"] = 0.
        P["tongue"] = False
        P["pitch"] = .12
        P["rise"] = -.04
        P["feet"] = {"lf": (.06, 0.), "rf": (-.02, 0.), "lh": (-.04, 0.), "rh": (.02, 0.)}
        P["tail"] = (.85, .5, .3)
        P["tail_yaw"] = .3
    elif name == "pain":
        # Cowering from the hit: low at the front, rump tucked, tail clamped
        # between his legs, head whipped round toward it, yelping.
        P["neck"] = .3
        P["yaw"] = -1.1
        P["nod"] = -.2
        P["jaw"] = .5
        P["tongue"] = False
        P["ears"] = .9
        P["rise"] = -.1
        P["pitch"] = .12
        P["crouch"] = .04
        P["tail"] = (-1.2, -.5, .3)
        P["tail_yaw"] = 0.
        P["lids"] = .6
        P["brows"] = 1.
        P["feet"] = {"lf": (.06, 0.), "rf": (.02, 0.), "lh": (.1, 0.), "rh": (.06, 0.)}
    elif name == "down":
        P["lie"] = "side"
        P["neck"] = .05
        P["nod"] = .2
        P["jaw"] = .12
        P["tongue"] = True
        P["ears"] = .2
        P["tail"] = (-.2, -.1, -.05)
        P["tail_yaw"] = 0.
        P["lids"] = 1.
    elif name == "whine":
        P["lie"] = "belly"
        P["neck"] = -.2
        P["nod"] = .35
        P["jaw"] = 0.
        P["tongue"] = False
        P["ears"] = .55
        P["tail"] = (-.15, -.1, -.05)
        P["tail_yaw"] = .2
        P["lids"] = .35
        P["brows"] = 1.
    return P


def _paw(paw, which, C, M):
    """A hound's foot: a tight cat foot, toes and dark nails at the front."""
    _tb(paw + Vector((.02, 0, .018)), (.042, .03, .022), which, M)
    for k in (-1, 0, 1):
        _tb(paw + Vector((.05, k * .016, .012)), (.016, .012, .013), which, M)
        ball(paw + Vector((.066, k * .016, .006)), (.006, .005, .005), C["pad"], M)


def _leg(hip, foot, l1, l2, low_len, low_back, pole, r, C, curl=False):
    """One leg: two IK pieces from `hip` to the joint above the foot, then the
    low piece (pastern or hock) of fixed length to the paw (world places)."""
    foot = Vector(foot)
    if curl:
        # The pointing foreleg: lifted, the paw folded back under the wrist.
        low = Vector((-.35, 0, -1)).normalized() * low_len
        knee, wrist = ik(hip, foot, l1, l2, pole)
        paw = wrist + low
    else:
        low = Vector((low_back, 0, 1)).normalized() * low_len
        knee, wrist = ik(hip, foot + low, l1, l2, pole)
        paw = wrist - low
    r0, r1, r2, r3 = r
    _tl(hip, knee, r0, r1, "legs")
    _tl(knee, wrist, r1 * .8, r2, "legs")
    _tl(wrist, paw, r2 * .95, r3, "tan", caps=False, seg=12)
    _paw(paw, "tan", C, None)


def _leg_fold(hip, foot, fwd, C):
    """A hind leg folded under him (sitting, lying on his belly): the hock
    flat on the ground behind the paw, the stifle up by his side; each piece
    its standing length."""
    foot = Vector(foot)
    hock = foot - fwd * _META + Vector((0, 0, .035))
    knee, hock = ik(hip, hock, _THIGH, _GASKIN, fwd + Vector((0, 0, .6)))
    paw = hock + (foot - hock).normalized() * _META
    _tl(hip, knee, .078, .05, "legs")
    _tl(knee, hock, .05 * .8, .03, "legs")
    _tl(hock, paw, .03 * .95, .025, "tan", caps=False, seg=12)
    _paw(paw, "tan", C, None)


def _head(Hm, P, C):
    """The head in its own frame Hm: the neck's top at the origin, +x down the
    muzzle. A long square muzzle and hanging flews, a domed skull under the
    black hood, tan pips, brown eyes, ears to below the jaw."""
    black = C["black"]
    # the skull, its peak at the back, the black hood over it and the cheeks
    _tb((.06, 0, .045), (.115, .085, .088), "fine", Hm)
    ball((.0, 0, .075), (.09, .083, .06), black, Hm)
    ball((-.04, 0, .1), (.04, .036, .036), black, Hm)
    for s in (-1, 1):
        # the hood round each eye and down the cheek behind it
        ball((.14, s * .047, .066), (.042, .027, .03), black, Hm, rot=(s * .3, -.1, 0))
        ball((.06, s * .062, .035), (.06, .03, .05), black, Hm, rot=(s * .2, 0, 0))
    # the stop and brows, a tan pip over each eye (raised when worried)
    brow = .01 * P["brows"]
    for s in (-1, 1):
        ball((.158, s * .042, .088 + brow), (.019, .016, .009), C["tan"], Hm, rot=(s * .3, -.35, 0))
    # the muzzle, long and square, ticked, tan along the cheeks and lips
    _tl((.12, 0, .035), (.27, 0, .012), .055, .046, "fine", Hm)
    _tb((.19, 0, .05), (.085, .042, .022), "fine", Hm)
    for s in (-1, 1):
        ball((.17, s * .042, .006), (.04, .014, .02), C["tan"], Hm, rot=(0, -.1, 0))
    nose = Vector((.295, 0, .025))
    ball(nose, (.03, .042, .03), C["nose"], Hm)
    for s in (-1, 1):
        ball(nose + Vector((.022, s * .017, -.004)), (.008, .009, .009), C["mouth"], Hm)
    # the flews: the upper lips hanging past the lower jaw, dark at the edge
    for s in (-1, 1):
        _tb((.22, s * .037, -.022), (.075, .02, .036), "fine", Hm, rot=(0, -.1, 0))
        ball((.245, s * .036, -.045), (.04, .016, .016), black, Hm)
    # the lower jaw on its hinge, the mouth inside, teeth and tongue
    J = Hm @ T((.08, 0, -.02)) @ R(0, P["jaw"], 0)
    _tl((0, 0, 0), (.18, 0, -.012), .036, .027, "fine", J)
    ball((.09, 0, .014), (.08, .028, .016), C["mouth"], J)
    for s in (-1, 1):
        ball((.16, s * .02, .022), (.007, .007, .014), C["tooth"], J)
        ball((.17, s * .026, -.03), (.007, .007, .014), C["tooth"], Hm)
    if P["tongue"]:
        # lolling out past his teeth, as a hound pants
        ball((.17, .0, .008), (.058, .025, .009), C["tongue"], J, rot=(0, .45, 0))
    else:
        ball((.09, .0, .016), (.055, .021, .008), C["tongue"], J)
    # the eyes: dark brown, a glint, a red haw under each; lids that close
    # (up inside the hood while open)
    for s in (-1, 1):
        eye = Vector((.162, s * .06, .066))
        ball(eye, .022, C["eye"], Hm)
        ball(eye + Vector((.012, s * .007, .008)), .006, C["glint"], Hm)
        shut = P["lids"]
        lid = eye + Vector((.004 - .02 * (1 - shut), -s * .003, .012 - .008 * shut + .012 * (1 - shut)))
        ball(lid, (.022, .02, .012 + .008 * shut), C["lid"], Hm)
        ball(eye + Vector((.0, s * .0, -.02)), (.012, .01, .004), C["haw"], Hm)
    # the ears: long and low-set behind the eyes, soft, hanging past the
    # jaw; swung back by speed or a yelp, up a little when he is keen
    back, up = P["ears"], P["ears_up"]
    for s in (-1, 1):
        root = Vector((.035, s * .074, .075))
        E = Hm @ T(root) @ R(s * (.08 + up * .55), .3 * back - up * .2, 0)
        ball((0, s * .01, -.015), (.045, .022, .04), black, E)
        ball((-.006, s * .016, -.1), (.058, .015, .1), black, E, rot=(s * .04, .08, 0))
        ball((-.012, s * .018, -.19), (.048, .013, .05), black, E)
    return J


def _body(P, C, M):
    """The body, neck, head, legs and tail in M (the whole dog's frame)."""
    rise, pitch = P["rise"], P["pitch"]
    sat, lie = P["sat"], P["lie"]
    hip_rest = Vector((-.33, 0, .6))
    if sat:
        # On his haunches: the rump down by the hocks, the body up at the front.
        Tb = T((-.22, 0, .26)) @ R(0, -.6, 0) @ T(-hip_rest)
    elif lie == "belly":
        Tb = T((0, 0, -.4))
    else:
        Tb = T(hip_rest + Vector((0, 0, rise - P["crouch"]))) @ R(0, pitch, 0) @ T(-hip_rest)
    B = M @ Tb
    s_ = P["stretch"]
    black = C["black"]
    # a deep narrow chest and prosternum, the ribs back to a tucked loin, a
    # lean rump, the withers a little over the croup
    _tb((.27 + s_, 0, .6), (.18, .128, .19), "coat", B)
    _tb((.37 + s_, 0, .55), (.1, .095, .12), "coat", B)
    _tb((.05, 0, .63), (.29, .122, .13), "coat", B)
    _tb((.06, 0, .54), (.2, .096, .06), "coat", B, rot=(0, .12, 0))
    _tb((-.18, 0, .64), (.15, .1, .1), "coat", B)
    _tb((-.33 - s_, 0, .64), (.125, .112, .115), "coat", B)
    _tb((-.36 - s_, 0, .69), (.085, .09, .05), "coat", B)
    _tb((.25 + s_, 0, .73), (.12, .1, .05), "coat", B)
    # the black saddle: ragged, over the back and down the flanks
    for x, z, rx, rz, ry, tilt in (
        (.06, .728, .2, .036, .1, 0.), (-.12, .72, .1, .03, .082, .1), (.2, .74, .08, .03, .085, -.1),
        (-.25, .71, .06, .026, .07, .2),
    ):
        ball((x, 0, z), (rx, ry, rz), black, B, rot=(0, tilt, 0))
    for x, z, rx, rz, rot in (
        (.1, .66, .09, .06, .3), (-.04, .69, .07, .05, -.2), (.2, .66, .05, .045, .5),
        (-.24, .66, .055, .04, -.4), (-.36, .63, .04, .035, .2),
    ):
        for s in (-1, 1):
            y = s * (.104 if x > -.15 else .092)
            ball((x, y, z), (rx, .024, rz), black, B, rot=(s * .28, rot, 0))
    # tan under the tail
    ball((-.455 - s_, 0, .6), (.03, .055, .045), C["tan"], B)
    # the neck: up from the withers, thick, the dewlap under it
    neck = P["neck"]
    base = Vector((.35 + s_, 0, .7))
    top = base + Vector((math.cos(neck) * .2, 0, math.sin(neck) * .2))
    _tl(base, top, .1, .075, "coat", B)
    _tb(base.lerp(top, .6) + Vector((.035, 0, -.055)), (.07, .055, .05), "coat", B)
    # the collar, a worn red strap round the neck's root, a brass tag
    collar = base.lerp(top, .35)
    d = (top - base).normalized()
    u = Vector((0, 1, 0))
    v = d.cross(u)
    for k in range(14):
        a, b = k / 14 * math.tau, (k + 1) / 14 * math.tau
        p0 = collar + (u * math.cos(a) + v * math.sin(a)) * .093
        p1 = collar + (u * math.cos(b) + v * math.sin(b)) * .093
        limb(p0, p1, .015, .015, C["collar"], B, caps=False, seg=6)
    tag = collar + v * .105 + Vector((.015, 0, -.035))
    ring(tag + Vector((0, 0, .022)), (0, 1, 0), .011, .003, C["tag"], n=8, M=B)
    ball(tag, (.02, .006, .022), C["tag"], B)
    # the head on the neck's top: lifted, nodded, turned
    Hm = B @ T(top) @ R(0, 0, P["yaw"]) @ R(0, -neck * .55 + .25 + P["nod"], 0) @ _HEAD
    _head(Hm, P, C)
    # the legs: the feet's places on the ground (dog space, under M)
    fwd = (M.to_3x3() @ Vector((1, 0, 0))).normalized()
    for leg, s, front in (("lf", 1, True), ("rf", -1, True), ("lh", 1, False), ("rh", -1, False)):
        fx, fz = P["feet"][leg]
        if front:
            hip = B @ Vector((.3 + s_, s * .08, .55))
            if sat:
                foot = Vector((.24, s * .09, 0))
            elif lie == "belly":
                foot = Vector((.6, s * .07, .025))
            elif lie == "side":
                foot = Vector((.46 + fx, s * .09, .02))
            else:
                foot = Vector((.3 + fx, s * .09, fz))
            pole = (-1, 0, -.15) if lie != "belly" else (-1, 0, -.6)
            _leg(hip, M @ foot, _ARM, _FORE, _PASTERN, -.2, B.to_3x3() @ Vector(pole),
                 (.052, .036, .026, .022), C, curl=P["paw_curl"] == leg)
        else:
            hip = B @ Vector((-.34 - s_, s * .085, .6))
            if sat:
                foot = Vector((-.02, s * .12, 0))
            elif lie == "belly":
                foot = Vector((-.04, s * .16, .02))
            elif lie == "side":
                foot = Vector((-.58 + fx, s * .09, .02))
            else:
                foot = Vector((-.37 + fx, s * .09, fz))
            if sat or lie == "belly":
                _leg_fold(hip, M @ foot, fwd, C)
                continue
            _leg(hip, M @ foot, _THIGH, _GASKIN, _META, .45, B.to_3x3() @ Vector((1, 0, -.1)),
                 (.078, .05, .03, .025), C)
    # the tail from the top of the rump
    a0, a1, a2 = P["tail"]
    turn = 0. if sat or lie else pitch
    tail_root = B @ Vector((-.45 - s_, 0, .69))
    angles = (a0 + turn, a0 + a1 + turn, a0 + a1 + a2 + turn)
    _tail_in(M, B, tail_root, angles, P["tail_yaw"])


def _tail_in(M, B, root, angles, yaw):
    """The tail laid out in the body's frame (so it turns with him)."""
    R3 = B.to_3x3().normalized()
    pieces = (.14, .13, .11)
    radii = (.036, .027, .019, .01)
    at = Vector(root)
    pitch_back = 0.
    for k, (length, a) in enumerate(zip(pieces, angles)):
        d = R3 @ Vector((-math.cos(a) * math.cos(yaw), math.sin(yaw) * math.cos(a), math.sin(a)))
        end = at + d * length
        _tl(at, end, radii[k], radii[k + 1], "coat", caps=k == 0)
        _tb(end, radii[k + 1] * 1.05, "fine" if k < 2 else "coat")
        at = end
    ball(at, (.012, .012, .012), C_TIP[0], None)


C_TIP = [None]


def _frame_matrix(frame, lie):
    """Where the whole dog stands: for the model square, head toward -y; for
    the cels turned a little to the camera. Out cold, he lies on his left
    side (+y), legs out to his right."""
    G = Matrix.Identity(4)
    if lie == "side":
        G = T((0, 0, .15)) @ R(-math.pi / 2 + .08, 0, 0) @ T((0, 0, -.55))
    if FOR_MODEL:
        return R(0, 0, -math.pi / 2) @ G
    return R(0, 0, -.32) @ G


def hound(frame):
    P = _pose_of(frame)
    C = _coat()
    C_TIP[0] = C["tip"]
    _body(P, C, _frame_matrix(frame, P["lie"]))


def hound_face(frame):
    """The badge's head: turned three-quarters to the camera and a little down
    at it, the neck under it."""
    C = _coat()
    P = _pose_of(0)
    if frame == 1:
        P.update(jaw=.04, tongue=False, ears_up=.4, brows=1.)
    elif frame == 2:
        P.update(jaw=.32, tongue=False, ears=.7, lids=.55, brows=1.)
    elif frame == "down":
        P.update(jaw=.1, tongue=True, ears=.3, lids=1.)
    Hm = T((.03, 0, .17)) @ R(0, 0, -.62) @ R(0, .12, 0) @ T((-.13, 0, 0))
    _head(Hm, P, C)
    _tl(Hm @ Vector((-.03, 0, -.01)), Hm @ Vector((-.09, 0, -.24)), .085, .1, "coat")
    collar = Hm @ Vector((-.07, 0, -.16))
    for k in range(14):
        a, b = k / 14 * math.tau, (k + 1) / 14 * math.tau
        p0 = collar + Vector((math.cos(a), math.sin(a), 0)) * .1
        p1 = collar + Vector((math.cos(b), math.sin(b), 0)) * .1
        limb(p0, p1, .016, .016, C["collar"], None, caps=False, seg=6)


ACTORS.update({
    "hound": (hound, HOUND, (), HOUND_CELS),
    "hound_face": (hound_face, HOUND_FACE, (), FACE_CELS),
})
