"""The armory's wall pictures for the guns that have no photographed pickup:
each weapon's own first-person model (weapon_views.py), laid on its side and
seen square on, barrel to the left like the ranch rifle's picture.

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
# The guns the range racks with these pictures (weapons.cfg order from 16).
ITEMS = [
    "hunter", "mower", "county45", "star357", "hogleg", "riot_pump", "tommy",
    "grease_gun", "patrol_bar", "marksman", "flash_jar", "smudge_pot",
    "shine_cocktail", "firecracker_can",
]
# Throwables stand up (a jar, a pot, a bottle, a can); the guns lie on their side.
STANDING = {"flash_jar", "smudge_pot", "shine_cocktail", "firecracker_can"}


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
        WEAPONS[name][0]()
        # Seen from the gun's left (-X): forward (+Y) runs to the screen's left.
        # A throwable is turned a little so it reads round.
        turn = Matrix.Rotation(0.0, 4, "Z")
        if name in STANDING:
            # Its length (+Y, the hand's) stood up, then turned to show its side.
            turn = Matrix.Rotation(math.radians(-25), 4, "Z") @ Matrix.Rotation(
                math.radians(90), 4, "X"
            )
        if WEAPONS[name][1] == "long":
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
