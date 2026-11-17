"""The junkyard workbench's duct-tape mods on the guns in first person.

    blender -b -P scripts/blender/weapon_mods.py -- <out dir> <names|all>
    blender -b -P scripts/blender/weapon_mods.py -- <out dir> items

Runs weapon_views.py's library (materials, shapes, the rigs, the stage) and
renders, into the same folder and views.json as weapon_views.py:

  - for the modelled guns (the ranch rifle, the dynamite crossbow, the
    dynamite), each gun again with its mods on: <gun>__<mods>.png, the mods'
    short names in name order joined by "_" (rifle__brake_drum), through the
    gun's own rig, so godot/tools/art/build_weapon_views.gd cuts their cels as
    it cuts the gun's;
  - for the photographed guns (the .38 and the sawed-off), each mod by
    itself: <gun>__<mod>.png, the parts alone on a clear ground, placed on
    the photograph's own gun: PHOTO holds where that gun lies in front of the
    plate's camera (fitted to the photograph's barrel, muzzle, sight and
    strap); a stand-in of the gun's barrel and frame holds out what lies
    behind it. build_weapon_views.gd lays them over the photographed cels.

With `items` it renders the bench's own pictures instead (items_main):
each mod's parts alone, seen from the side, as mod_<short>.png (its tag
on the bench screen and its mark on the HUD), and the three pieces of scrap
lying on the ground seen from above and in front, scrap_<piece>.png (the
pickups): godot/tools/art/build_bench_art.gd shrinks and grades them.

Every mod is the same kind of fix: something off a junk pile, held on with
duct tape, hose clamps and baling wire. Modelled here from plain shapes;
nothing is traced from another game.
"""
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(_HERE, "weapon_views.py"), encoding="utf-8") as _lib:
    _source = _lib.read().rstrip()
# The library without its last line (main()), which runs below with these views.
exec(_source[: _source.rfind("main()")], globals())

DUCT = lambda: pbr("duct_mod", (98, 100, 102), .62, .2, bump=.6, scale=55., blotch=(70, 66, 60))
GALV = lambda: pbr("galv", (150, 152, 148), .38, .9, wear=(206, 206, 200), blotch=(120, 104, 80))
SCOPE = lambda: pbr("scope_black", (22, 22, 24), .42, .6, wear=(110, 106, 100), edge=(150, 146, 140), cavity=.6)
WIRE = lambda: pbr("baling_wire", (120, 118, 112), .45, 1., wear=(170, 168, 160), blotch=(110, 70, 40))

# Where each photographed gun lies in front of its plate's camera: a frame on
# its barrel (origin on the barrel's axis where it meets the frame, +Y to the
# muzzle, +Z up off the top strap), as T(x, y, z) @ Euler(rx, ry, rz); the
# plate's focal length; the barrel's length and radius in that frame.
PHOTO = {
    "revolver": ((-.10555, .05079, .10758), (.30097, -.87483, 1.57506), 604., .101, .0105),
    "shotgun": ((.01386, -.30099, -.00641), (.40422, -.00347, .62504), 462., .708, .0115),
}
# The sawed-off's barrels side by side, each this far off its middle.
SPREAD = .0115


def hull_band(y, width, shapes, material, grow=.0016, seg=20):
    """A wrap of tape (or a clamp) round several things at once along +Y: the
    convex hull, in XZ, of circles (x, z, r) and boxes (x, z, w, h), grown a
    hair, made a prism `width` long centred on y."""
    import math as _m
    pts = []
    for s in shapes:
        if len(s) == 3:
            x, z, r = s
            for k in range(seg):
                a = k * _m.tau / seg
                pts.append((x + _m.cos(a) * (r + grow), z + _m.sin(a) * (r + grow)))
        else:
            x, z, w, h = s
            for dx in (-w / 2 - grow, w / 2 + grow):
                for dz in (-h / 2 - grow, h / 2 + grow):
                    pts.append((x + dx, z + dz))
    pts = sorted(set(pts))

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    ring_pts = lower[:-1] + upper[:-1]
    bm = bmesh.new()
    front = [bm.verts.new((x, y + width / 2, z)) for x, z in ring_pts]
    back = [bm.verts.new((x, y - width / 2, z)) for x, z in ring_pts]
    n = len(ring_pts)
    bm.faces.new(list(reversed(front)))
    bm.faces.new(back)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[i], front[j], back[j], back[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return place(bm, Matrix.Identity(4), material, smooth=True)


def tape_ends(y, width, at, material):
    """The torn tail of a wrap, a little flap standing off it at `at` (x, z)."""
    box((at[0], y, at[1]), (.0016, width * .9, .007), material, bevel=.0004)


# ---------------------------------------------------------------- the .38


def revolver_holdout():
    """The photograph's .38 as a stand-in: what hides the far side of a wrap."""
    hold = HOLD()
    L, r = PHOTO["revolver"][3], PHOTO["revolver"][4]
    rod((0, -.005, 0), (0, L, 0), r, r, hold, seg=24)
    box((0, -.045, -.004), (.024, .09, .034), hold, bevel=.004)
    rod((0, -.085, -.018), (0, -.01, -.018), .021, .021, hold, seg=24)


def revolver_scope():
    """A pawn-shop scope off a .22, its rings wired on and the whole thing
    taped down along the top strap and the barrel."""
    black = SCOPE()
    z = .03
    rod((0, -.07, z), (0, .07, z), .0088, .0088, black, seg=28)
    rod((0, .07, z), (0, .086, z), .0088, .0128, black, seg=28)
    rod((0, .086, z), (0, .1, z), .0132, .0132, black, seg=28)
    disc((0, .1005, z), (0, 1, 0), .0108, .001, pbr("scope_glass", (70, 110, 136), .08, .2, bump=.02), seg=28)
    ring((0, .1, z), (0, 1, 0), .0132, .0012, IRON(), n=24)
    rod((0, -.07, z), (0, -.084, z), .0088, .011, black, seg=28)
    rod((0, -.084, z), (0, -.098, z), .0112, .0112, RUBBER(), seg=28)
    # the turret and its two knobs, a brass screw on the side
    rod((0, -.004, z), (0, -.004, z + .013), .0048, .0048, black, seg=16)
    rod((0, -.004, z), (-.012, -.004, z), .0042, .0042, black, seg=16)
    disc((0, -.004, z + .013), (0, 0, 1), .0049, .001, BRASS(), seg=16)
    # rings on stubby legs, a twist of baling wire round each
    for y, foot in ((-.046, .012), (.05, .0108)):
        ring((0, y, z), (0, 1, 0), .0081, .0015, IRON(), n=20)
        box((0, y, (z + foot) / 2), (.006, .006, z - foot), IRON(), bevel=.001)
        for k in range(3):
            ring((0, y - .004 + k * .0035, z), (0, 1, 0), .0089, .0007, WIRE(), n=16)
    # duct tape: the back ring to the top strap, the front ring to the barrel
    tape = DUCT()
    hull_band(-.03, .016, [(0, z, .0074), (0, .006, .024, .014)], tape)
    hull_band(.062, .018, [(0, z, .0074), (0, 0, PHOTO["revolver"][4])], tape)
    tape_ends(.062, .018, (.012, .02), tape)


def revolver_loader():
    """A speed loader of six fresh .38s taped flat along the left of the
    barrel, ready to slap in."""
    r = PHOTO["revolver"][4]
    x, z = -.024, -.004
    body = pbr("loader", (30, 28, 26), .55, .3, wear=(120, 110, 96), edge=(150, 140, 120))
    rod((x, .018, z), (x, .034, z), .0148, .0148, body, seg=28)
    rod((x, .006, z), (x, .018, z), .006, .006, body, seg=16)
    ball((x, .005, z), .0062, body)
    for k in range(6):
        a = k * math.tau / 6 + .3
        cx, cz = x + math.cos(a) * .0088, z + math.sin(a) * .0088
        rod((cx, .034, cz), (cx, .058, cz), .0043, .0043, BRASS(), seg=12)
        rod((cx, .058, cz), (cx, .064, cz), .0043, .0026, pbr("lead", (120, 118, 116), .5, .7), seg=12)
        disc((cx, .0338, cz), (0, 1, 0), .0049, .0012, BRASS(), seg=12)
    tape = DUCT()
    hull_band(.026, .014, [(x, z, .0152), (0, 0, r)], tape)
    hull_band(.05, .012, [(x, z, .0128), (0, 0, r)], tape)
    tape_ends(.05, .012, (x - .012, z - .012), tape)


# ---------------------------------------------------------------- the sawed-off


def shotgun_holdout():
    hold = HOLD()
    L, r = PHOTO["shotgun"][3], PHOTO["shotgun"][4]
    for s in (-1, 1):
        rod((s * SPREAD, -.05, 0), (s * SPREAD, L, 0), r, r, hold, seg=28)
    box((0, .2, -.02), (.03, .6, .02), hold, bevel=.002)


def shotgun_bayonet():
    """A corn knife taped along the outside of the near barrel, its handle
    back by the fore-end and its blade out past the muzzles, canted out a
    hair: a jab when the shells run out."""
    L, r = PHOTO["shotgun"][3], PHOTO["shotgun"][4]
    x = -(SPREAD + r + .0045)
    z = .002
    handle = pbr("knife_handle", (64, 40, 24), .6, 0., grain=(30, 18, 10), scale=24., edge=(130, 96, 62))
    steel = pbr("knife_steel", (182, 184, 188), .18, 1., wear=(232, 234, 238), blotch=(120, 84, 50),
                edge=(246, 246, 248))
    box((x, .2, z), (.009, .16, .026), handle, bevel=.004)
    for y in (.14, .2, .26):
        disc((x - .0048, y, z), (1, 0, 0), .0036, .001, BRASS(), seg=10)
    box((x, .286, z), (.011, .012, .036), steel, bevel=.0015)
    # the blade: a long flat wedge, broad side out, its edge down, the point
    # turned up and out
    bm = bmesh.new()
    t = .0016
    prof = [(0, .014), (0, -.014), (.55, -.014), (.66, -.004), (.69, .008), (.55, .015)]
    vs = []
    for side in (-t, t):
        row = []
        for py, pz in prof:
            out = -.06 * (py / .69) ** 2
            row.append(bm.verts.new((x + side + out, .292 + py, z + pz + .02 * (py / .69) ** 2)))
        vs.append(row)
    bm.faces.new(vs[0])
    bm.faces.new(list(reversed(vs[1])))
    n = len(prof)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((vs[0][i], vs[0][j], vs[1][j], vs[1][i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    place(bm, Matrix.Identity(4), steel, smooth=False)
    tape = DUCT()
    for y, w in ((.16, .05), (.25, .04), (.42, .04)):
        hull_band(y, w, [(-SPREAD, 0, r), (SPREAD, 0, r), (x, z, .0045, .028)], tape)
    tape_ends(.25, .04, (x - .008, z - .016), tape)


def shotgun_choke():
    """A length of galvanized pipe slid over each barrel's front third,
    hose-clamped to the pair with a bell reducer on the end: the shot holds
    together further out."""
    L, r = PHOTO["shotgun"][3], PHOTO["shotgun"][4]
    galv = GALV()
    grow = .0065
    y0 = .22
    for s in (-1, 1):
        x = s * SPREAD
        rod((x, y0, 0), (x, L + .03, 0), r + grow, r + grow, galv, seg=32)
        for y in (y0, y0 + .02, L + .01, L + .028):
            ring((x, y, 0), (0, 1, 0), r + grow + .0004, .0018, galv, n=28)
        rod((x, L + .03, 0), (x, L + .06, 0), r + grow + .002, r + .002, galv, seg=32)
        disc((x, L + .0605, 0), (0, 1, 0), r - .0006, .0009, SLOT(), seg=24)
    clamp = pbr("clamp", (196, 198, 200), .28, 1., wear=(236, 236, 236))
    for y in (y0 + .06, .45, L - .07):
        hull_band(y, .016, [(-SPREAD, 0, r + grow), (SPREAD, 0, r + grow)], clamp, grow=.0016)
        box((0, y, r + grow + .004), (.012, .018, .009), clamp, bevel=.001)
        rod((-.012, y, r + grow + .004), (.012, y, r + grow + .004), .0026, .0026, STEEL(), seg=8)
    hull_band(y0 - .03, .045, [(-SPREAD, 0, r), (SPREAD, 0, r)], DUCT())


# ---------------------------------------------------------------- the modelled guns


def _drop(test):
    """Take back the parts already built that `test` picks by their middle."""
    gone = [ob for ob in PARTS if test(ob.matrix_world.translation)]
    for ob in gone:
        PARTS.remove(ob)
    meshes = [ob.data for ob in gone]
    bpy.data.batch_remove(gone)
    bpy.data.batch_remove([me for me in meshes if me.users == 0])


def rifle_drum():
    """A war-surplus drum hung on the left of the handguard, its face turned
    back to the shooter, a feed chute bent from it into the magazine well,
    wired and taped on: the banana magazine is gone."""
    _drop(lambda c: .02 < c.y < .16 and c.z < -.072)
    iron = IRON()
    drum = pbr("pan_drum", (70, 74, 56), .5, .7, wear=(150, 146, 124), blotch=(116, 70, 38), edge=(186, 180, 160),
               cavity=.6)
    c = Vector((-.042, .24, -.042))
    k = Vector((-.35, -.9, .25)).normalized()
    R, T2 = .034, .012
    rod(c + k * T2, c - k * T2, R, R, drum, seg=56)
    rod(c + k * (T2 + .007), c + k * T2, R * .55, R, drum, seg=56)
    rod(c + k * (T2 + .013), c + k * (T2 + .007), .012, .012, iron, seg=28)
    disc(c + k * (T2 + .0135), k, .008, .0015, BRASS(), seg=24)
    u = k.orthogonal().normalized()
    v = k.cross(u)
    rod(c + k * (T2 + .015) - u * .012, c + k * (T2 + .015) + u * .012, .0025, .0025, BRASS(), seg=8)
    for n in range(12):
        a = n * math.tau / 12
        spot = c + k * (T2 + .0035) + (u * math.cos(a) + v * math.sin(a)) * .022
        ball(spot, .0028, iron)
    for x in (T2, -T2):
        ring(c + k * x, k, R, .0016, iron, n=40)
    disc(c + k * (T2 + .004) + v * .017, k, .006, .001, pbr("pan_paint", (206, 194, 150), .8), seg=12)
    # the chute into the well, baling wire and tape holding it all on
    rod(c - k * .01, Vector((0, .08, -.08)), .009, .011, iron, seg=12)
    box((0, .08, -.085), (.028, .034, .04), iron, bevel=.003)
    hull_band(.24, .02, [(c.x, c.z, .024, .04), (0, -.036, .034, .03)], DUCT())
    hull_band(.28, .005, [(c.x, c.z, .024, .024), (0, -.03, .036, .04)], WIRE(), grow=.0008)


def rifle_brake():
    """A coffee can with holes punched round it, hose-clamped over the
    muzzle: it eats the climb and it is loud."""
    can = pbr("coffee_can", (126, 40, 30), .45, .7, wear=(200, 190, 170), blotch=(80, 60, 40))
    tin = pbr("can_tin", (176, 176, 170), .3, 1., wear=(220, 220, 214))
    y0, y1, z, R = .64, .82, -.032, .042
    rod((0, y0, z), (0, y1, z), R, R, can, seg=44)
    for y in (y0 + .007, y1 - .007):
        ring((0, y, z), (0, 1, 0), R + .0003, .0022, tin, n=36)
    band(.73, z, R + .0006, .05, pbr("can_label", (214, 192, 116), .7), seg=44)
    band(.73, z, R + .0009, .008, pbr("can_stripe", (40, 30, 24), .7), seg=44)
    for k in range(10):
        a = k * math.tau / 10
        for y in (.67, .79):
            disc((math.cos(a) * (R + .0003), y, z + math.sin(a) * (R + .0003)), (math.cos(a), 0, math.sin(a)),
                 .006, .0014, SLOT(), seg=10)
    disc((0, y1 + .0006, z), (0, 1, 0), R, .001, tin, seg=44)
    disc((0, y1 + .0014, z), (0, 1, 0), .013, .001, SLOT(), seg=20)
    rod((0, .6, z), (0, y0, z), .016, R * .9, tin, seg=32)
    hull_band(.6, .022, [(0, z, .012)], DUCT(), grow=.006)


def crossbow_flame():
    """The stick on the rail wrapped in a rag soaked in coal oil and wired on:
    lit off the match as it goes, it sets what it hits burning."""
    rag = pbr("oily_rag", (150, 112, 62), .9, 0., bump=1.0, scale=60., blotch=(26, 20, 16))
    for k in range(6):
        y = .24 + k * .022
        rod((0, y, .012), (0, y + .026, .012), .027 - k * .0009, .026 - k * .0009, rag, seg=20)
    rod((0, .37, .012), (0, .388, .012), .02, .008, rag, seg=20)
    for y in (.255, .31, .36):
        ring((0, y, .012), (0, 1, 0), .0262 - (y - .25) * .05, .0014, WIRE(), n=20)
    # a rag tail hanging off it
    box((.014, .3, -.002), (.004, .018, .028), rag, rot=(.3, 0, .2), bevel=.002)


def crossbow_spring():
    """Two more leaves out of a pickup's rear spring under the bow, U-bolted
    on: the bolt goes faster and flatter and it cocks quicker."""
    leafs = pbr("truck_leaf", (60, 46, 36), .55, .9, wear=(150, 120, 96), blotch=(110, 58, 30), edge=(170, 150, 130))
    for leaf, reach in enumerate((.28, .23)):
        z = -.028 - leaf * .009
        for s in (-1, 1):
            pts = [Vector((s * x, .42 - .11 * (x / .28) ** 2, z)) for x in [reach * k / 5 for k in range(6)]]
            for a, b in zip(pts, pts[1:]):
                box(((a.x + b.x) / 2, (a.y + b.y) / 2, z), (abs(b.x - a.x) + .005, .03, .0085), leafs,
                    rot=(0, 0, -s * math.atan2(a.y - b.y, abs(b.x - a.x))), bevel=.002)
    for s in (-1, 1):
        for x in (.045, .075):
            for side in (-1, 1):
                rod((s * x, .42 + side * .019, .012), (s * x, .42 + side * .019, -.05), .0028, .0028, STEEL(), seg=8)
            box((s * x, .42, .014), (.012, .046, .006), IRON(), bevel=.001)
            box((s * x, .42, -.052), (.012, .046, .006), IRON(), bevel=.001)


def tnt_fuse():
    """A yard of fuse in a coil taped to the stick: it burns a long while."""
    _drop(lambda c: c.y > .165 and c.z > .02)
    pts = [Vector((.012, .17, .016)), Vector((.022, .2, .03))]
    import math as _m
    for k in range(26):
        a = k * .55
        pts.append(Vector((.024 + _m.cos(a) * .022, .215 + k * .0035, .04 + _m.sin(a) * .022)))
    pts += [Vector((.0, .32, .07)), Vector((-.02, .35, .1)), Vector((-.01, .38, .13))]
    for a, b in zip(pts, pts[1:]):
        rod(a, b, .0026, .0026, PAPER(), seg=6)


def tnt_bundle():
    """Two more sticks taped up with the first: a bundle, three times the bang
    and then some."""
    tape = DUCT()
    for x, z in ((-.034, -.008), (-.017, -.034)):
        rod((x, -.118, z), (x, .148, z), .0185, .0185, RED(), seg=28)
        for y in (-.12, .148):
            disc((x, y, z), (0, 1, 0), .017, .005, PAPER(), seg=22)
        rod((x, .055, z), (x, .11, z), .019, .019, PAPER(), seg=28)
        for y in (.062, .082, .10):
            rod((x, y, z), (x, y + .003, z), .0193, .0193, pbr("ink", (60, 20, 16), .8), seg=28)
    for y, w in ((-.02, .024), (.12, .02)):
        hull_band(y, w, [(0, 0, .0185), (-.034, -.008, .0185), (-.017, -.034, .0185)], tape)
    tape_ends(.12, .02, (-.05, -.02), tape)


def HOLD():
    """A holdout: pixels where it is in front come out clear."""
    if "holdout" in MATS:
        return MATS["holdout"]
    m = bpy.data.materials.new("holdout")
    try:
        m.use_nodes = True
    except Exception:
        pass
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    hold = nt.nodes.new("ShaderNodeHoldout")
    nt.links.new(hold.outputs[0], out.inputs[0])
    MATS["holdout"] = m
    return m


# Each mod: (its gun, its short name, the builder). A photographed gun's mods
# render alone; a modelled gun's render on the gun, every combination.
MODS = [
    ("revolver", "scope", revolver_scope), ("revolver", "loader", revolver_loader),
    ("shotgun", "bayonet", shotgun_bayonet), ("shotgun", "choke", shotgun_choke),
    ("rifle", "brake", rifle_brake), ("rifle", "drum", rifle_drum),
    ("crossbow", "flame", crossbow_flame), ("crossbow", "spring", crossbow_spring),
    ("tnt", "bundle", tnt_bundle), ("tnt", "fuse", tnt_fuse),
]
# A mod that moves the muzzle: where the flash comes from with it on.
FRONTS = {"brake": (0, .83, -.032)}
HOLDOUTS = {"revolver": revolver_holdout, "shotgun": shotgun_holdout}


def _clear():
    doomed = list(PARTS)
    meshes = [ob.data for ob in doomed]
    PARTS.clear()
    bpy.data.batch_remove(doomed)
    bpy.data.batch_remove([me for me in meshes if me.users == 0])


def mod_views():
    """name -> (gun, [(short, builder)])."""
    out = {}
    guns = []
    for gun, _short, _build in MODS:
        if gun not in guns:
            guns.append(gun)
    for gun in guns:
        mine = sorted([(s, b) for g, s, b in MODS if g == gun])
        if gun in PHOTO:
            for s, b in mine:
                out["%s__%s" % (gun, s)] = (gun, [(s, b)])
        else:
            for pick in range(1, 1 << len(mine)):
                chosen = [mine[k] for k in range(len(mine)) if pick >> k & 1]
                out["%s__%s" % (gun, "_".join(s for s, _b in chosen))] = (gun, chosen)
    return out


def mods_main():
    scene, camera = stage()
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "views.json")
    views = json.load(open(path)) if os.path.exists(path) else {}
    for name, (gun, chosen) in mod_views().items():
        if WANT and name not in WANT and gun not in WANT:
            continue
        _clear()
        if gun in PHOTO:
            HOLDOUTS[gun]()
            for _s, build in chosen:
                build()
            spot, turn, focal = PHOTO[gun][0], PHOTO[gun][1], PHOTO[gun][2]
            model = T(spot) @ Euler(turn, "XYZ").to_matrix().to_4x4()
            rig = "pistol" if gun == "revolver" else "long"
            front = (0, PHOTO[gun][3], 0)
        else:
            build_gun, rig, front = WEAPONS[gun]
            for s, _b in chosen:
                front = FRONTS.get(s, front)
            build_gun()
            for _s, build in chosen:
                build()
            focal, model = RIGS[rig]
            model = model @ Matrix.Scale(TRIM.get(gun, 1.0), 4)
            model = model @ T(SHIFT.get(gun, (0, 0, 0)))
        for ob in PARTS:
            ob.matrix_world = model @ ob.matrix_world
        camera.data.lens = focal * 36.0 / CANVAS[0]
        bpy.context.view_layer.update()

        def screen(point):
            v = world_to_camera_view(scene, camera, model @ Vector(point))
            return [round(v.x * CANVAS[0], 1), round((1 - v.y) * CANVAS[1], 1)]

        views[name] = {"rig": rig, "grip": screen((0, 0, 0)), "front": screen(front), "photo": gun in PHOTO}
        scene.render.filepath = os.path.join(OUT, name + ".png")
        bpy.ops.render.render(write_still=True)
    json.dump(views, open(path, "w"), indent=1)



# ---------------------------------------------------------------- the scrap


def scrap_bolts():
    """A handful of rusty bolts, nuts and washers off a junked truck."""
    rusty = pbr("bolt_rust", (96, 70, 52), .6, .8, wear=(160, 140, 116), blotch=(120, 60, 30), edge=(176, 160, 140))
    zinc = pbr("bolt_zinc", (150, 148, 136), .4, 1., wear=(200, 198, 186), blotch=(130, 90, 50))
    for (x, y, a, length, mat) in ((0, 0, .3, .062, rusty), (.018, .016, 1.9, .05, zinc),
                                   (-.02, .012, 2.6, .055, rusty), (.006, -.02, -.6, .045, zinc)):
        d = Vector((math.cos(a), math.sin(a), 0))
        head = Vector((x, y, .007))
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=.009, radius2=.009, depth=.006)
        place(bm, T(head) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4(), mat, smooth=False)
        rod(head + d * .003, head + d * length, .0045, .0045, mat, seg=12)
        for k in range(int(length / .006)):
            ring(head + d * (.012 + k * .006), d, .0046, .0008, mat, n=10)
    for (x, y) in ((-.006, .03), (.03, -.004), (-.03, -.014)):
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=6, radius1=.008, radius2=.008, depth=.006)
        place(bm, T((x, y, .003)), rusty, smooth=False)
        disc((x, y, .0062), (0, 0, 1), .0042, .0008, SLOT(), seg=12)
    for (x, y) in ((.016, .03), (-.032, .008)):
        ring((x, y, .001), (0, 0, 1), .009, .0018, zinc, n=20)


def scrap_wire():
    """A coil of copper wire pulled out of a motor, a tail sticking out."""
    copper = pbr("wire_copper", (168, 92, 52), .32, 1., wear=(230, 170, 120), blotch=(70, 110, 90))
    red = pbr("wire_red", (150, 36, 28), .6, 0.)
    for k in range(7):
        a = k * .5
        ring((math.cos(a) * .004, math.sin(a) * .004, .004 + k * .0028), (math.sin(a) * .2, .25, 1), .036 - k * .0006,
             .0022, copper, n=30)
    pts = [Vector((.036, 0, .02)), Vector((.05, .012, .03)), Vector((.062, .03, .026)), Vector((.07, .04, .012))]
    for a, b in zip(pts, pts[1:]):
        rod(a, b, .0024, .0024, copper, seg=8)
    pts = [Vector((-.034, .01, .012)), Vector((-.05, -.004, .01)), Vector((-.058, -.022, .004))]
    for a, b in zip(pts, pts[1:]):
        rod(a, b, .003, .003, red, seg=8)


def scrap_hubcap():
    """A dented chrome hubcap, rolled off somebody's sedan."""
    chrome = pbr("hub_chrome", (182, 184, 188), .16, 1., wear=(236, 236, 238), blotch=(120, 96, 70),
                 edge=(244, 244, 246))
    dark = pbr("hub_dark", (40, 40, 42), .5, .8)
    rod((0, 0, 0), (0, 0, .008), .07, .066, chrome, seg=48)
    rod((0, 0, .008), (0, 0, .018), .05, .036, chrome, seg=48)
    rod((0, 0, .018), (0, 0, .026), .02, .012, chrome, seg=32)
    for k in range(10):
        a = k * math.tau / 10
        box((math.cos(a) * .043, math.sin(a) * .043, .012), (.024, .006, .004), dark, rot=(0, 0, a), bevel=.001)
    disc((0, 0, .0264), (0, 0, 1), .009, .001, pbr("hub_badge", (170, 40, 30), .4), seg=20)
    ring((0, 0, .004), (0, 0, 1), .07, .002, chrome, n=48)


SCRAP = {"bolts": scrap_bolts, "wire": scrap_wire, "hubcap": scrap_hubcap}
# How each mod's parts are seen on their tag: the way the camera looks from
# (towards the parts' middle), in the parts' own frame.
MOD_VIEW = {"spring": (0, -.25, 1), "drum": (-1, -1.2, .3), "bundle": (-.6, .35, .5), "fuse": (-.8, .3, .4),
            "flame": (-1, .2, .35)}


def _look(scene, camera, toward, pad=.012, ppm=400.):
    """An orthographic look at every part from direction `toward`, framed."""
    bpy.context.view_layer.update()
    k = Vector(toward).normalized()
    rot = (-k).to_track_quat("-Z", "Y")
    camera.rotation_euler = rot.to_euler()
    cam_m = rot.to_matrix()
    pts = []
    for ob in PARTS:
        for corner in ob.bound_box:
            pts.append(ob.matrix_world @ Vector(corner))
    local = [cam_m.transposed() @ p for p in pts]
    lo = Vector((min(p.x for p in local), min(p.y for p in local), min(p.z for p in local)))
    hi = Vector((max(p.x for p in local), max(p.y for p in local), max(p.z for p in local)))
    mid = cam_m @ ((lo + hi) / 2)
    camera.location = mid + k * 3.0
    w, h = hi.x - lo.x + pad, hi.y - lo.y + pad
    camera.data.ortho_scale = max(w, h)
    scene.render.resolution_x = max(16, round(w * ppm))
    scene.render.resolution_y = max(16, round(h * ppm))


def gun_38():
    """The .38 on the bench's board (the game's own is a photograph): a
    six-inch blued revolver with walnut grips, built on the deputies' .357."""
    MATS["d_stainless"] = pbr("blued_38", (30, 32, 38), .32, 1., wear=(130, 130, 136), edge=(160, 160, 166),
                              cavity=.7)
    MATS["d_poly"] = WOOD()
    MATS["d_silver"] = WOOD()
    MATS["ramp"] = MATS["d_stainless"]
    star357()
    for key in ("d_stainless", "d_poly", "d_silver", "ramp"):
        MATS.pop(key)
    # A real grip where the hand would be: walnut, its butt rounded.
    _drop(lambda c: c.z < -.02 and -.07 < c.y < .01)
    box((0, -.038, -.06), (.026, .036, .11), WOOD(), rot=(.32, 0, 0), bevel=.01)
    ball((0, -.055, -.112), .016, WOOD())


def gun_sawed_off():
    """The sawed-off on the bench's board (the game's own is a photograph):
    side-by-side barrels cut short, a split fore-end, the stock sawn to a grip."""
    blued = pbr("blued_sg", (28, 30, 36), .3, 1., wear=(130, 128, 130), edge=(170, 168, 168), cavity=.6)
    wood = WOOD()
    for s in (-1, 1):
        rod((s * .0115, -.02, 0), (s * .0115, .36, 0), .0115, .0112, blued, seg=24)
        disc((s * .0115, .3605, 0), (0, 1, 0), .0085, .001, SLOT(), seg=20)
    box((0, .17, .012), (.006, .38, .004), blued, bevel=.001)
    box((0, .12, -.02), (.026, .16, .022), wood, bevel=.006)
    box((0, -.05, -.012), (.03, .07, .04), blued, bevel=.004)
    box((0, -.13, -.04), (.028, .12, .05), wood, rot=(.5, 0, 0), bevel=.008)
    box((0, -.035, -.042), (.004, .05, .003), blued, bevel=.001)
    for s in (-1, 1):
        box((s * .008, -.085, .012), (.004, .014, .02), blued, rot=(-.6, 0, 0), bevel=.001)


GUN_PICTURES = {"revolver": gun_38, "shotgun": gun_sawed_off, "rifle": rifle, "crossbow": crossbow, "tnt": tnt}
# Long thin parts laid at a slant on their tags, to read bigger.
SLANT = {"bayonet": .45, "choke": .5, "scope": .25, "brake": .2}


def items_main():
    scene, camera = stage()
    scene.cycles.samples = 48
    camera.data.type = "ORTHO"
    camera.data.shift_x = 0.0
    camera.data.shift_y = 0.0
    os.makedirs(OUT, exist_ok=True)
    for gun, short, build in MODS:
        _clear()
        build()
        if short in SLANT:
            tilt = Matrix.Rotation(SLANT[short], 4, "X")
            for ob in PARTS:
                ob.matrix_world = tilt @ ob.matrix_world
        _look(scene, camera, MOD_VIEW.get(short, (-1, .25, .45)))
        scene.render.filepath = os.path.join(OUT, "mod_%s.png" % short)
        bpy.ops.render.render(write_still=True)
    for gun, build in GUN_PICTURES.items():
        _clear()
        build()
        _look(scene, camera, (-.3, .05, 1) if gun == "crossbow" else (-1, 0, .12))
        scene.render.filepath = os.path.join(OUT, "gun_%s.png" % gun)
        bpy.ops.render.render(write_still=True)
    for piece, build in SCRAP.items():
        _clear()
        build()
        _look(scene, camera, (-.45, -.7, .75), ppm=900.)
        scene.render.filepath = os.path.join(OUT, "scrap_%s.png" % piece)
        bpy.ops.render.render(write_still=True)


if WANT == ["items"]:
    items_main()
else:
    mods_main()
