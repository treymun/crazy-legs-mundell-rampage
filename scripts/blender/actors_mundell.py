"""Crazy Legs Mundell himself, for the other players' bodies in the 3D view
(co-op partners, deathmatch and team deathmatch opponents, the mirror): the
same man as the player pictures (assets/art/player_*.png). Exec'd into
enemy_actors.py's namespace (mat, limb, ball, box, person, cast, AVG, ACTORS and
the rest are in scope); export_actors.py rigs and bakes him like the enemies.

His face is the face in his front picture: the photograph in player_front_0
is laid on the front of his head (each vertex of the face, brow, nose and
beard takes a "face" texture coordinate where that point falls on the
picture, and a "face_w" weight that fades it into plain skin and beard round
the sides), so the bake carries it onto the model. The rest is modelled to
the picture: the olive cap with its tan patch and dark band, grey beard,
red and black plaid shirt over an orange tee, denim bib overalls with a tan patch
on the right thigh, brown work boots, and the pump gun with three brass
shells in its side saddle, held low across his hips.

The wrappers below (head, body, legs, weapon, arms) are no-ops for the rest of the
cast.
"""

_MUNDELL_ART = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
                            "assets", "art", "player_front_0.png")
# Where his face sits in the front picture (pixels; the picture is 120 x 214):
# the middle of the face across, the cap band's lower edge and the beard's
# lowest point, and the head-space height each of those is modelled at.
_FACE_X, _FACE_TOP, _FACE_LOW = 56.5, 24.5, 51.0
_FACE_Z_TOP, _FACE_Z_LOW = .036, -.168
_FACE_K = (_FACE_Z_TOP - _FACE_Z_LOW) / (_FACE_LOW - _FACE_TOP)
# The photograph's face: these columns and rows (with a soft edge).
_FACE_BOX = (40.0, 73.0, 23.5, 51.5)
_PHOTO = {}


def _photo_image():
    if "image" not in _PHOTO or _PHOTO["image"].name not in bpy.data.images:
        image = bpy.data.images.load(_MUNDELL_ART, check_existing=True)
        image.colorspace_settings.name = "sRGB"
        _PHOTO["image"] = image
        _PHOTO["size"] = tuple(image.size)
    return _PHOTO["image"]


def photo_mat(r, g, b, rough=.8, glow=.32):
    """Plain (r, g, b) where face_w is 0, the front picture where it is 1 (lit
    like skin, a little of its own light kept so the photograph's tones hold)."""
    key = ("photo", r, g, b, rough, glow, WOUND and KIND)
    if key in MATS:
        return MATS[key]
    image = _photo_image()
    m = bpy.data.materials.new("photo%d" % len(MATS))
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    nt.links.new(bsdf.outputs[0], out.inputs[0])
    bsdf.inputs["Roughness"].default_value = rough
    uv = nt.nodes.new("ShaderNodeUVMap")
    uv.uv_map = "face"
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Linear"
    tex.extension = "EXTEND"
    nt.links.new(uv.outputs[0], tex.inputs[0])
    weight = nt.nodes.new("ShaderNodeAttribute")
    weight.attribute_name = "face_w"
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs[6].default_value = (lin(r), lin(g), lin(b), 1)
    nt.links.new(weight.outputs["Fac"], mix.inputs[0])
    nt.links.new(tex.outputs["Color"], mix.inputs[7])
    source = mix.outputs[2]
    if WOUND:
        source = _wounded(nt, bsdf, source, (lin(r), lin(g), lin(b), 1), 0.)
    nt.links.new(source, bsdf.inputs["Base Color"])
    if glow:
        lit = nt.nodes.new("ShaderNodeMath")
        lit.operation = "MULTIPLY"
        lit.inputs[1].default_value = glow
        nt.links.new(weight.outputs["Fac"], lit.inputs[0])
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        nt.links.new(lit.outputs[0], bsdf.inputs["Emission Strength"])
    MATS[key] = m
    return m


def _face_weight(px, py, facing):
    """How much of the photograph a point shows: inside the face's box on the
    picture, and turned toward the front (the sides fade to plain)."""
    x0, x1, y0, y1 = _FACE_BOX
    edge = min(px - x0, x1 - px, py - y0, y1 - py)
    inside = max(0., min(1., edge / 2.5))
    front = max(0., min(1., (facing - .18) / .42))
    return inside * front


def photo_ball(c, r, material, M, rot=(0, 0, 0)):
    """ball() with the front picture's face laid on it: c, r, rot in head space."""
    if isinstance(r, (int, float)):
        r = (r, r, r)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=24, v_segments=14, radius=1.0)
    local = T(c) @ R(*rot) @ Matrix.Diagonal((r[0], r[1], r[2], 1))
    turn = local.to_3x3().inverted().transposed()
    _photo_image()
    w, h = _PHOTO["size"]
    uv_layer = bm.loops.layers.uv.new("face")
    weight_layer = bm.loops.layers.float_color.new("face_w")
    for face in bm.faces:
        for loop in face.loops:
            p = local @ loop.vert.co
            n = (turn @ loop.vert.co).normalized()
            px = _FACE_X + p.x / _FACE_K
            py = _FACE_TOP + (_FACE_Z_TOP - p.z) / _FACE_K
            loop[uv_layer].uv = (px / w, 1. - py / h)
            k = _face_weight(px, py, -n.y)
            loop[weight_layer] = (k, k, k, 1.)
    matrix = M @ local
    place(bm, matrix, material)


def mundell_head(Hm, C, J):
    skin = photo_mat(*C["skin"], .75)
    beard = photo_mat(*C["beard_c"], .95)
    hair = mat(*C["hair"], .95)
    cap = mat(*C["hat_c"], .9)
    # The face, cheek to cheek and brow to chin, then the jaw under the
    # beard, the nose standing off the photograph, the ears; short grey hair
    # round the back under the cap.
    photo_ball((0, -.012, -.03), (.112, .118, .132), skin, Hm)
    photo_ball((0, -.03, -.104), (.1, .094, .066), beard, Hm)
    photo_ball((0, -.042, -.128), (.072, .076, .044), beard, Hm)
    photo_ball((0, -.114, -.036), (.024, .03, .026), skin, Hm)
    for s in (-1, 1):
        ball((s * .108, .014, -.032), (.011, .026, .034), mat(*C["skin"], .75, grime=.42), Hm, (0, 0, s * .25))
    ball((0, .036, -.004), (.108, .106, .112), hair, Hm)
    # The cap: an olive crown, the dark band round its foot, a curved peak and
    # the tan patch on the front panel with its pale stripe.
    ball((0, .004, .07), (.122, .13, .094), cap, Hm)
    ball((0, .004, .04), (.124, .132, .022), mat(*C["band_c"], .9), Hm)
    ball((0, -.162, .046), (.096, .094, .013), cap, Hm, (-.2, 0, 0))
    box((0, -.116, .098), (.064, .012, .03), mat(*C["patch_c"], .9, grime=.2), Hm, (-.42, 0, 0))
    box((0, -.122, .098), (.044, .008, .009), mat(220, 212, 186, .8, grime=.1), Hm, (-.42, 0, 0))
    ball((0, .004, .164), .016, cap, Hm)


_mundell_head_base = head


def head(Hm, C, J):
    if C.get("photo"):
        mundell_head(Hm, C, J)
        return
    _mundell_head_base(Hm, C, J)


_mundell_body_base = body
# The gun this frame's hands hold: (grip point, direction), or None (set by
# weapon(), read by arms(); body() runs first in each frame and clears it).
_GUN = {"now": None}


def _checked(m):
    """A plaid material's check made dark and hard (red and near-black, like
    his shirt), not the cast's soft brown bands. Edits the cached material."""
    for node in m.node_tree.nodes:
        if node.bl_idname == "ShaderNodeMix" and node.blend_type == "MULTIPLY":
            shade = node.inputs[7].default_value[0]
            if abs(shade - .46) < .01 or abs(shade - .62) < .01:
                k = .24 if shade < .5 else .4
                node.inputs[7].default_value = (k, k, k, 1)
    return m


def body(Tm, S, C, J):
    if not C.get("photo"):
        _mundell_body_base(Tm, S, C, J)
        return
    _GUN["now"] = None
    # Slimmer front to back than the cast's barrels (his side pictures), and
    # his own bib: the overalls are low at the back, the shirt hanging to
    # the waist with the straps crossing over it (the cast's back panel
    # comes up to his shoulder blades).
    slim = Tm @ Matrix.Diagonal((1, C["depth_k"], 1, 1))
    _mundell_body_base(slim, S, {k: v for k, v in C.items() if k != "bib"}, J)
    L, sw, g = S["torso_len"], S["sw"], S["gut"]
    _checked(mat(*C["shirt"], .9, plaid=3.6 / C["plaid_size"]))
    bib = mat(*C["bib"], .92)
    front = -(.17 + .03 * g)
    ball((0, -.1 - .07 * g, .15), (sw * .87 + .06 * g, .15 + .06 * g, .2), bib, slim)
    ball((0, front + .05, L - .18), (.15, .08, .15), bib, slim)
    for s in (-1, 1):
        ball((s * .11, front - .005, L - .07), .02, BRASS(), slim)
        limb((s * .11, front, L - .08), (s * .14, -.02, L + .05), .026, .026, bib, slim)
        limb((s * .14, -.02, L + .05), (s * .03, .155, L - .2), .026, .026, bib, slim)
    limb((0, .155, L - .2), (0, .16, .1), .03, .028, bib, slim)
    # The orange tee in the open collar, the shirt's collar points over it.
    ball((0, -.07, L - .005), (.085, .07, .04), mat(*C["tee"], .9), Tm)
    collar = _checked(mat(*C["shirt"], .9, plaid=C["sleeve_plaid"]))
    for s in (-1, 1):
        ball((s * .06, -.1, L + .01), (.055, .035, .03), collar, Tm, (0, s * .55, 0))


_mundell_legs_base = legs


def legs(S, J, cloth, radii, boot, cuff=None, boot_top=0.):
    _mundell_legs_base(S, J, cloth, radii, boot, cuff, boot_top)
    C = S.get("look", {})
    if not C.get("photo"):
        return
    # The tan patch sewn on the right thigh, out front and to the outside.
    hip, knee = J["hipR"], J["kneeR"]
    along = (knee - hip).normalized()
    out = Vector((-1, -1.1, 0))
    out = (out - along * out.dot(along)).normalized()
    c = hip.lerp(knee, .62) + out * (radii[0] * .55 + radii[1] * .45 + .002)
    M = T(c) @ _frame_on(out, along)
    box((0, 0, 0), (.11, .012, .1), mat(*C["patch_c"], .9, grime=.3), M)


def _frame_on(normal, up):
    """A turn whose local y runs along -normal (the face of a thing laid on a
    surface) and z along up."""
    y = -normal.normalized()
    z = (up - y * up.dot(y)).normalized()
    x = y.cross(z)
    return Matrix(((x.x, y.x, z.x, 0), (x.y, y.y, z.y, 0), (x.z, y.z, z.z, 0), (0, 0, 0, 1)))


_mundell_weapon_base = weapon


def weapon(kind, g, d, J, C):
    if kind != "pump":
        return _mundell_weapon_base(kind, g, d, J, C)
    frame = J["frame"]
    up = Vector((0, 0, 1))
    side = d.cross(up).normalized()
    over = side.cross(d).normalized()
    # A pump gun: the barrel over its magazine tube, a dark receiver with
    # three brass shells in the side saddle, a wooden pump and stock.
    limb(g + d * .1, g + d * .72, .02, .02, STEEL(), caps=False)
    disc(g + d * .72, d, .014, .01, BLACK())
    limb(g + d * .12 - over * .034, g + d * .62 - over * .034, .016, .016, DARK(), caps=False)
    limb(g - d * .03, g + d * .16, .046, .042, DARK())
    for k in range(3):
        at = g + d * (.03 + .045 * k) + side * .044
        limb(at - over * .04, at + over * .03, .012, .012, BRASS(), caps=False)
        disc(at - over * .042, over, .014, .006, mat(150, 110, 52, .5, .8, grime=.2))
    limb(g - d * .03, g - d * .22 + Vector((0, 0, -.05)), .036, .05, WOOD())
    limb(g + d * .3, g + d * .5 - over * .02, .036, .034, WOOD())
    if frame == "fire":
        flash(g + d * .76, .24, (255, 168, 60))
    if frame == "wind":
        glint(g + d * .72)
    _GUN["now"] = (g.copy(), d.copy())
    return g + d * (.32 if frame == "wind" else .4)


# ---------------------------------------------------------------- arms and hands
# How far the fingers wrap round from the gun's axis (the pump's and the
# receiver's radius and a finger's), and the hand's pieces (the same shapes
# closed or open, so the rig pairs them frame to frame).
_WRAP = .05
_PALM = (.031, .014, .031)
_KNUCKLE = (.0105, .0105, .02)
_TIP = (.0098, .0098, .016)
_THUMB = (.011, .011, .022)


def _axes(c, x, y):
    """A turn whose local x runs along x, y along y (made square to x) and z
    along their cross, standing at c."""
    x = x.normalized()
    y = (y - x * y.dot(x)).normalized()
    z = x.cross(y)
    return Matrix(((x.x, y.x, z.x, c.x), (x.y, y.y, z.y, c.y), (x.z, y.z, z.z, c.z), (0, 0, 0, 1)))


def _on_gun(p, gun):
    if gun is None:
        return False
    g, d = gun
    t = (p - g).dot(d)
    return (p - g - d * t).length < .02 and -.3 < t < .8


def _gripping_hand(p, u, d, skin):
    """A hand closed round the gun at p (on its axis): the palm against it on
    the side u (toward the forearm), four fingers wrapped round the near side
    and the thumb laid along the other."""
    v = d.cross(u).normalized()
    if v.y > 0:
        v = -v
    ball((0, 0, 0), _PALM, skin, _axes(p + u * (_WRAP + .01), d, u))
    for k in range(4):
        along = d * ((k - 1.5) * .017)
        for a, size in ((1.15, _KNUCKLE), (2.15, _TIP)):
            radial = u * math.cos(a) + v * math.sin(a)
            ball((0, 0, 0), size, skin, _axes(p + along + radial * _WRAP, d, radial))
    for k, a in enumerate((-.75, -1.25)):
        radial = u * math.cos(a) + v * math.sin(a)
        at = p + radial * (_WRAP + .004) + d * (.012 + .03 * k)
        ball((0, 0, 0), _THUMB, skin, _axes(at, radial, d.cross(radial)))


def _open_hand(elbow, wrist, side, skin):
    """A hand not on the gun (thrown up, flung out falling): palm on from the
    wrist, the fingers a little curled, the thumb out to the side."""
    f = (wrist - elbow).normalized()
    across = f.cross(Vector((0, 0, 1)))
    if across.length < .1:
        across = f.cross(Vector((0, 1, 0)))
    across.normalize()
    n = across.cross(f).normalized()
    ball((0, 0, 0), _PALM, skin, _axes(wrist + f * .03, across, n))
    for k in range(4):
        off = across * ((k - 1.5) * .016)
        ball((0, 0, 0), _KNUCKLE, skin, _axes(wrist + f * .068 + off + n * .004, across, n))
        ball((0, 0, 0), _TIP, skin, _axes(wrist + f * .097 + off + n * .014, across, n))
    for k in range(2):
        at = wrist + f * (.02 + .022 * k) - across * side * (.036 + .012 * k) + n * .006
        ball((0, 0, 0), _THUMB, skin, _axes(at, n, n.cross(f - across * side)))


_mundell_arms_base = arms


def arms(S, J, hands, sleeve, palm=None):
    C = S.get("look", {})
    if not C.get("photo"):
        return _mundell_arms_base(S, J, hands, sleeve, palm)
    # Slim plaid sleeves on ordinary shoulders, cuffs at the wrist, real hands.
    r0, r1, r2 = S["arm"]
    cloth = _checked(mat(*C["shirt"], .9, plaid=C["sleeve_plaid"]))
    skin = mat(*C["skin"], .75, grime=.42)
    gun = _GUN["now"]
    for side, tag in ((-1, "R"), (1, "L")):
        target, sh = hands[tag], J["sh" + tag]
        grip = _on_gun(target, gun)
        u = None
        wrist = target
        if grip:
            d = gun[1]
            away = sh - target
            away = away - d * away.dot(d)
            u = away.normalized() if away.length > 1e-4 else Vector((0, 0, -1))
            wrist = target + u * (_WRAP + .03)
        elbow, wrist = ik(sh, wrist, S["upper"], S["fore"], (side * .7, .55, -.8))
        ball(sh, r0 * 1.02, cloth)
        limb(sh, elbow, r0, r1, cloth)
        cuff = elbow.lerp(wrist, .86)
        limb(elbow, cuff, r1, r2 + .008, cloth)
        limb(cuff, wrist, r2 * .82, r2 * .74, skin, caps=False)
        if grip:
            _gripping_hand(target, u, gun[1], skin)
        else:
            _open_hand(elbow, wrist, side, skin)


# Held low across his hips, the barrel out to his left (the front picture);
# shouldered to aim and fire.
MUNDELL_HOLD = dict(TWO, ready=((-.15, -.31, -.47), (.92, -.2, .24)),
                    recover=((-.19, -.34, -.38), (.7, -.6, .12)))
# canvas: his model (1.774 tall to the cap's button) fills it as he fills his
# pictures (203 of their 214 rows), so the 3D view draws him the picture's size.
MUNDELL = cast(AVG, gut=.18, sw=.235, head_scale=1.28, canvas=(1.6, 1.87), px=160,
               limb=(.1, .092, .082), stance=.22, arm=(.056, .05, .036), uv_head=1.6, uv_face=2.6,
               plaid_size=1.5, sleeve_plaid=8.5,
               photo=1, skin=(198, 146, 116), beard_c=(150, 140, 124), hair=(132, 116, 100),
               hat_c=(96, 104, 54), band_c=(48, 50, 34), patch_c=(176, 160, 124), tee=(196, 104, 46), depth_k=.7,
               shirt=(138, 46, 36), plaid=1, bib=(60, 70, 94), pants=(60, 70, 94),
               boots=(80, 54, 36), boot_top=.22, weapon="pump", hold=MUNDELL_HOLD)
# "sit": a partner in an open seat (the riding mower: ModeBodies.player_pose).
ACTORS["mundell"] = (maker(MUNDELL), MUNDELL, ("sit",), None)
