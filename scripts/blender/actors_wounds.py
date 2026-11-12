"""The regular hands' hurt look (their `<kind>_hurt_<cel>` set, shown under half
health by src/enemy_looks.gd). Exec'd by enemy_actors.py after the other
actors_<chapter>.py files (mat, ball, limb, rags, sparks, smoke, ACTORS and the
rest in scope). While WOUND is set, mat() calls _wounded() for every material it
makes, and main() calls wound_marks() after each hurt cel is posed; the walk's
limp is skeleton()'s own (enemy_actors.py). Creatures mark their own wounds in
their own functions (they know where their parts are); this dresses the people.

Blood is red, or green for the greys and their crew (enemies.cfg blood="plasma");
tin takes dents, scratches and sparks instead of bleeding.
"""

PLASMA = {"alien", "drone", "tin_guard", "probe", "saucer", "crawler", "lantern"}
# Where the front of the belly is (local y at hip height + .24) for the ones not
# drawn by person(), and the colour of the shirt that tears.
OWN_BODY = {"billy": (-.35, (142, 44, 36), .3, 1.3), "big_billy": (-.4, (142, 44, 36), .36, 1.35),
            "coot": (-.17, (126, 60, 52), .18, 1.0), "drunk_coot": (-.17, (126, 60, 52), .18, 1.0)}


def blood_mats():
    if KIND in PLASMA:
        return mat(110, 200, 70, .25, grime=0), mat(46, 96, 36, .3, grime=0)
    return mat(132, 18, 14, .28, grime=0), mat(70, 8, 8, .35, grime=0)


def _wounded(nt, bsdf, source, base, metal):
    """Blood soaked into cloth and skin in blotches stuck to each part (its own
    generated coordinates, so a stain stays put from cel to cel) with a spray of
    drops; on metal, dents and scorch instead, and bright scratches."""
    def mix(fac, a, b):
        m = nt.nodes.new("ShaderNodeMix")
        m.data_type = "RGBA"
        nt.links.new(fac, m.inputs[0])
        m.inputs[6].default_value = base
        if a is not None:
            nt.links.new(a, m.inputs[6])
        m.inputs[7].default_value = b
        return m.outputs[2]

    def band(scale, lo, hi, detail=5.0):
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = scale
        noise.inputs["Detail"].default_value = detail
        edge = nt.nodes.new("ShaderNodeMapRange")
        edge.inputs[1].default_value = lo
        edge.inputs[2].default_value = hi
        nt.links.new(noise.outputs[0], edge.inputs[0])
        return edge.outputs[0]

    if metal >= .5:
        source = mix(band(2.4, .55, .6), source, (lin(30), lin(26), lin(24), 1))
        source = mix(band(46.0, .7, .72, 2.0), source, (lin(214), lin(210), lin(200), 1))
        return source
    plasma = KIND in PLASMA
    wet = (lin(70), lin(118), lin(44), 1) if plasma else (lin(96), lin(12), lin(10), 1)
    soak = band(2.2, .6, .64) if plasma else band(2.2, .57, .61)
    source = mix(soak, source, wet)
    source = mix(band(38.0, .7, .72, 2.0), source, wet)
    shine = nt.nodes.new("ShaderNodeMapRange")
    shine.inputs[3].default_value = bsdf.inputs["Roughness"].default_value
    shine.inputs[4].default_value = .3
    nt.links.new(soak, shine.inputs[0])
    nt.links.new(shine.outputs[0], bsdf.inputs["Roughness"])
    return source


def splat(c, size, M=None, rot=(0, 0, 0), k0=0):
    """A wet stain standing just proud of a surface (thin along local y): a dark
    heart, a brighter rim, a few drops thrown off it."""
    hi, lo = blood_mats()
    c = Vector(c)
    turn = Euler(rot, "XYZ").to_matrix()
    for k, (m, f) in enumerate(((hi, 1.0), (lo, .6))):
        for j in range(3):
            off = turn @ (Vector(((jitter(j + k0, 1) - .5) * .9, 0, (jitter(j + k0, 2) - .5) * .7)) * size * f)
            r = size * f * (.55 + .4 * jitter(j + k0, 3))
            ball(c + off + turn @ Vector((0, -.004 * k, 0)), (r, size * .3, r * .8), m, M, rot)
    for j in range(4):
        off = turn @ Vector(((jitter(j + k0, 5) - .5) * 1.6, -.002, (jitter(j + k0, 6) - .5) * 1.4)) * size
        ball(c + off, size * (.12 + .1 * jitter(j + k0, 7)), hi, M)


def drip(top, length, M=None, k0=0):
    """A run of blood down from `top` (in M's frame), thinning as it goes."""
    hi, lo = blood_mats()
    top = Vector(top)
    for j in range(2):
        a = top + Vector(((jitter(j + k0, 1) - .5) * .05, -.004, 0))
        b = a + Vector(((jitter(j + k0, 2) - .5) * .02, 0, -length * (.6 + .5 * jitter(j + k0, 3))))
        if M is not None:
            a, b = M @ a, M @ b
        limb(a, b, .014, .005, hi if j == 0 else lo, seg=8)


def hole(c, M, rot=(0, 0, 0)):
    """A bullet hole: a black pit ringed with blood."""
    hi, _ = blood_mats()
    ball(c, (.026, .012, .026), hi, M, rot)
    ball(Vector(c) + Euler(rot, "XYZ").to_matrix() @ Vector((0, -.006, 0)), (.013, .01, .013), BLACK(), M, rot)


def dent(c, size, M, rot=(0, 0, 0)):
    """A dent knocked into tin: a dark scuffed hollow with a bright scrape above it."""
    c = Vector(c)
    ball(c, (size, size * .25, size * .8), mat(26, 24, 22, .7, grime=0), M, rot)
    ball(c + Vector((size * .3, -.004, size * .7)), (size * .7, size * .2, size * .18),
         mat(214, 210, 200, .3, .9, grime=0), M, rot)


def head_wound(S, J, C, f=1.0):
    """A split brow bleeding down the face (a cracked visor on tin, a soaked sack);
    f scales the spot to a bigger head than person()'s."""
    Hm = J["head"] @ Matrix.Scale(f, 4)
    eyes = C.get("eyes", "normal")
    if eyes == "visor":
        crack([(-.05, -.135, .04), (-.01, -.14, .028), (.02, -.138, .036), (.06, -.134, .02)], Hm,
              mat(255, 230, 160, emit=2.4), .006)
        sparks(Hm @ Vector((.08, -.13, .03)), (1, -.6, .4), 5, .16)
        return
    if eyes == "mask":
        splat((.05, -.13, .02), .045, Hm, (0, 0, 0), 3)
        drip((.05, -.135, -.0), .12, Hm, 2)
        return
    splat((.05, -.1, .055), .03, Hm, (-.5, 0, 0), 1)
    drip((.055, -.118, .045), .13, Hm, 4)


def belly_wound(Tm, front, g, k0=0):
    """Shot in the side: the stain under the clutching hand, holes, runs down the hip."""
    splat((.12, front - .01, .24), .085, Tm, (0, 0, 0), k0)
    hole((.16, front - .016, .27), Tm)
    hole((-.08, front - .012, .36), Tm)
    drip((.12, front - .02, .16), .26, Tm, k0 + 2)


def torn_hem(Tm, front, sw, shirt, k0=0):
    """The shirt hanging in strips where it was ripped."""
    cloth = mat(*shirt, .9)
    rags(Tm @ Vector((-sw * .3, front + .01, .08)), Tm.to_3x3() @ Vector((0, -1, 0)), 4, .1, sw * .7, cloth, k0)


def wound_marks(kind, frame):
    """Dress the cel just posed for its hurt set (people; creatures do their own)."""
    if LAST_J is None or kind not in ACTORS:
        return
    S, J = LAST_J
    if J["dead"] or "torso" not in J:
        return
    Tm = J["torso"]
    f = 1.0
    if kind in OWN_BODY:
        front, shirt, sw, f = OWN_BODY[kind]
        C = {"eyes": "normal"}
    elif "look" in S:
        C = S["look"]
        front = -(.21 + .17 * S["gut"])
        shirt = C.get("coat", C["shirt"])
        sw = S["sw"]
    else:
        return
    head_wound(S, J, C, f)
    if kind in ("tin_guard",):
        for x, z in ((-.12, .42), (.14, .3), (.02, .16)):
            dent((x, -.21, z), .045, Tm)
        sparks(Tm @ Vector((-.15, -.22, .4)), (-.6, -.7, .3), 6, .2)
        smoke(Tm @ Vector((.2, .1, S["torso_len"] + .1)), .045, (.2, .1))
        splat((.14, -.22, .2), .05, Tm, (0, 0, 0), 5)
        return
    belly_wound(Tm, front, S.get("gut", .3), len(kind))
    if not any(k in C for k in ("bib", "apron", "armor")) and kind not in OWN_BODY:
        torn_hem(Tm, front, sw, shirt, len(kind) + 3)
    if "tanks" in S.get("look", {}):
        # A tank holed and hissing steam.
        puff(Tm @ Vector((.18, .34, .32)), .045)
        hole((.12, .31, .32), Tm, (0, 0, math.pi))
