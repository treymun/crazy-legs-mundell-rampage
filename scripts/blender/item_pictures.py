"""Every gun's pickup and wall picture (the HUD's gun icon too): each
weapon's own first-person model (weapon_views.py), laid on its side and seen
square on, barrel to the left like the ranch rifle's picture. The first
sixteen guns keep the old game's painted pickups, but for those cut out of
the first-person photographs with the hand still on them (the crowbar, the
.38, the sawed-off, the dynamite) and the dynamite sticks lying about, which
showed a box of shells: those are made here since polish pass 9, the crowbar
and the sticks modelled here (they have no first-person model of their own).

    blender -b -P scripts/blender/item_pictures.py -- <out dir> <names|all> [supersample]

Writes item_<name>.png (transparent, with a margin) and items.json (each
picture's width and height in metres, the pixels a metre). The range's racks
show them (tools/levels/range_plan.gd); godot/tools/art/build_item_art.gd crops,
shrinks and grades them into assets/art. Every model is weapon_views.py's own,
modelled there from scratch.
"""
import json
import math
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_ARGS = sys.argv[sys.argv.index("--") + 1:]
# weapon_views.py reads its own arguments: hand it a folder and no names.
sys.argv = sys.argv[: sys.argv.index("--") + 1] + [_ARGS[0], "none"]
with open(os.path.join(_HERE, "weapon_views.py"), encoding="utf-8") as _lib:
    _source = _lib.read()
exec(_source[: _source.rstrip().rfind("main()")], globals())

import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

OUT_DIR = os.path.abspath(_ARGS[0])
NAMES = _ARGS[1] if len(_ARGS) > 1 else "all"
SS = int(_ARGS[2]) if len(_ARGS) > 2 else 4
# Pixels a metre rendered (before the supersample): build_item_art.gd shrinks
# each to its own size in the game.
PPM = 200.0
# Every gun with a picture made here (weapons.cfg order), and the dynamite
# sticks lying about to pick up (item_dynamite).
ITEMS = [
    "crowbar", "revolver", "shotgun", "tnt", "dynamite",
    "hunter", "mower", "county45", "star357", "hogleg", "riot_pump", "tommy",
    "grease_gun", "patrol_bar", "marksman", "flash_jar", "smudge_pot",
    "shine_cocktail", "firecracker_can",
]
# Throwables stand up (a jar, a pot, a bottle, a can); the guns lie on their side.
STANDING = {"flash_jar", "smudge_pot", "shine_cocktail", "firecracker_can"}


def crowbar():
    """The crowbar lying about: a hex bar gone to rust at the ends, a
    goose-neck claw at one end and a flat chisel at the other."""
    iron = pbr("crowbar_iron", (64, 40, 32), .6, .8, wear=(150, 118, 96), blotch=(110, 58, 34), edge=(170, 140, 116))
    rod((0, -.24, 0), (0, .2, 0), .011, .011, iron, seg=6)
    box((0, -.258, -.004), (.02, .04, .008), iron, rot=(.25, 0, 0), bevel=.003)
    pts = [Vector((0, .2, 0))]
    for k in range(1, 9):
        a = k / 8 * math.pi * 1.05
        pts.append(Vector((0, .2 + math.sin(a) * .045, .045 - math.cos(a) * .045)))
    for a, b in zip(pts, pts[1:]):
        rod(a, b, .011, .011, iron, seg=6, round_ends=True)
    for s in (-1, 1):
        box((s * .006, .165, .09), (.008, .05, .01), iron, rot=(.35, 0, 0), bevel=.002)


def dynamite_sticks():
    """Three sticks of dynamite taped up together, a fuse in the middle one."""
    tape = pbr("tape", (30, 28, 28), .7, 0., bump=.5, scale=50.)
    for x, z in ((0, 0), (.036, -.004), (.018, .028)):
        rod((x, -.12, z), (x, .15, z), .0185, .0185, RED(), seg=28)
        for y in (-.122, .15):
            disc((x, y, z), (0, 1, 0), .017, .005, PAPER(), seg=22)
        rod((x, .055, z), (x, .11, z), .019, .019, PAPER(), seg=28)
        for y in (.062, .082, .10):
            rod((x, y, z), (x, y + .003, z), .0193, .0193, pbr("ink", (60, 20, 16), .8), seg=28)
    for y in (-.07, .02):
        rod((.018, y, .008), (.018, y + .022, .008), .041, .041, tape, seg=32)
    pts = [Vector((.018, .152, .028)), Vector((.02, .19, .04)), Vector((.0, .22, .03)), Vector((-.01, .25, .05))]
    for a, b in zip(pts, pts[1:]):
        rod(a, b, .0026, .0026, PAPER(), seg=6)


# The pickups with no first-person model of their own.
OWN = {"crowbar": crowbar, "dynamite": dynamite_sticks}
# Sticks laid across the picture (turned about the view's axis, then their
# own), so they read bigger than a stick seen end to end along the ground.
SLANTED = {"tnt": (-32, 0), "dynamite": (-32, 35)}


def side_stage():
    scene, camera = stage()
    scene.cycles.samples = 48
    camera.data.type = "ORTHO"
    camera.data.shift_x = 0.0
    camera.data.shift_y = 0.0
    return scene, camera


def bounds():
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for ob in PARTS:
        for corner in ob.bound_box:
            p = ob.matrix_world @ Vector(corner)
            lo = Vector((min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z)))
            hi = Vector((max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z)))
    return lo, hi


def _box_of(ob):
    ps = [ob.matrix_world @ Vector(c) for c in ob.bound_box]
    lo = Vector((min(p.x for p in ps), min(p.y for p in ps), min(p.z for p in ps)))
    hi = Vector((max(p.x for p in ps), max(p.y for p in ps), max(p.z for p in ps)))
    return lo, hi


def wrist():
    """A long gun's wrist, in its stock's own wood or polymer: the views'
    models leave it out (the hand covers it) and stand the stock off below and
    behind the breech, which a side view would show as a gap."""
    boxes = [(ob,) + _box_of(ob) for ob in PARTS]

    def volume(b):
        d = b[2] - b[1]
        return d.x * d.y * d.z

    big = [b for b in boxes if volume(b) > 2e-6]
    stock = min(big, key=lambda b: b[1].y)
    body = max([b for b in big if b[2].y > 0.0 and b[1].y < 0.0], key=volume)
    a = Vector(((body[1].x + body[2].x) / 2, body[1].y + .012, body[1].z + .4 * (body[2].z - body[1].z)))
    b = Vector((a.x, stock[2].y - .012, stock[2].z - .3 * (stock[2].z - stock[1].z)))
    if (b - a).length < .01:
        return
    r = max(.009, .17 * (stock[2].z - stock[1].z))
    rod(tuple(a), tuple(b), r * .8, r, stock[0].active_material, round_ends=True)


def main_items():
    scene, camera = side_stage()
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, "items.json")
    sizes = json.load(open(path)) if os.path.exists(path) else {}
    for name in ITEMS:
        if NAMES != "all" and name not in NAMES.split(","):
            continue
        doomed = list(PARTS)
        meshes = [ob.data for ob in doomed]
        PARTS.clear()
        bpy.data.batch_remove(doomed)
        bpy.data.batch_remove([me for me in meshes if me.users == 0])
        (OWN[name] if name in OWN else WEAPONS[name][0])()
        # Seen from the gun's left (-X): forward (+Y) runs to the screen's left.
        # A throwable is turned a little so it reads round.
        turn = Matrix.Rotation(0.0, 4, "Z")
        if name in STANDING:
            # Its length (+Y, the hand's) stood up, then turned to show its side.
            turn = Matrix.Rotation(math.radians(-25), 4, "Z") @ Matrix.Rotation(
                math.radians(90), 4, "X"
            )
        if name in SLANTED:
            tilt, roll = SLANTED[name]
            turn = Matrix.Rotation(math.radians(tilt), 4, "X") @ Matrix.Rotation(math.radians(roll), 4, "Y")
        if name in WEAPONS and WEAPONS[name][1] == "long" and name not in ("crossbow", "shotgun"):
            wrist()
        for ob in PARTS:
            ob.matrix_world = turn @ ob.matrix_world
        bpy.context.view_layer.update()
        lo, hi = bounds()
        middle = (lo + hi) / 2
        w, h = (hi.y - lo.y) + .04, (hi.z - lo.z) + .04
        camera.location = (middle.x - 3.0, middle.y, middle.z)
        camera.rotation_euler = (math.pi / 2, 0, -math.pi / 2)
        camera.data.ortho_scale = max(w, h)
        scene.render.resolution_x = max(8, round(w * PPM * SS))
        scene.render.resolution_y = max(8, round(h * PPM * SS))
        scene.render.filepath = os.path.join(OUT_DIR, "item_%s.png" % name)
        bpy.ops.render.render(write_still=True)
        sizes[name] = [round(w, 3), round(h, 3), PPM]
    json.dump(sizes, open(path, "w"), indent=1)


main_items()
