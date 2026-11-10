"""Set dressing for every chapter: where the breakable furniture goes, and the
clutter, tall silhouettes and ground wear that fill the bare stretches.

Everything here is seeded by the level id, so a level always dresses the same
way. Nothing placed by `dress` collides or blocks a route: clutter is drawn
tight against a wall or in a corner, and the rest is ground decals.
"""
import math
import zlib

import numpy as np

# Furniture that belongs under a roof with its back to a wall.
INDOOR = {"tv", "toilet", "vending", "jukebox", "window"}

# Clutter by chapter: (image, height). Chapter signage keeps the size the
# level's own builders already use for it, read from the world at run time.
LOW = {
    "hickston": (("prop_tire", .40), ("prop_barrel", 1.04), ("prop_crate", .75), ("prop_hay", .91),
                 ("prop_reeds", .58), ("split_feed_sacks", None)),
    "fair": (("prop_crate", .75), ("prop_barrel", 1.04), ("prop_hay", .91), ("prop_tire", .40),
             ("fair_prize_pile", None), ("fair_spill", .16), ("fair_spill", .16)),
    "sawmill": (("prop_crate", .75), ("prop_barrel", 1.04), ("prop_tire", .40), ("prop_reeds", .58),
                ("mill_log_ends", None), ("mill_timber", None)),
    "quarry": (("prop_crate", .75), ("prop_barrel", 1.04), ("prop_tire", .40),
               ("quarry_bottles", None)),
}
TALL = {
    "hickston": (("prop_tree", 3.65), ("prop_tree_b", 3.65), ("prop_utilitypole", 3.85)),
    "fair": (("fair_pylon", None), ("fair_pylon", None), ("prop_utilitypole", 3.85)),
    "sawmill": (("mill_pylon", None), ("mill_pilings", None), ("prop_utilitypole", 3.85)),
    "quarry": (("quarry_tower", None), ("quarry_tower", None), ("mill_pylon", None)),
}
WEAR = {
    "hickston": ("oil", "grain", "silt"),
    "fair": ("soda", "tickets"),
    "sawmill": ("sawdust", "oil"),
    "quarry": ("chalk", "copper", "oil"),
}
# Solid cover for the wide yards: what a firefight there can use.
COVER = {
    "hickston": ("hay", "barrel", "crate", "hay"),
    "fair": ("crate", "barrel", "hay", "crate"),
    "sawmill": ("crate", "barrel", "crate"),
    "quarry": ("crate", "barrel", "crate"),
}
# Where a piece belongs, so each chapter keeps its own look:
#   reeds grow at the water's edge and nowhere else;
#   prize shelves and bottling racks stay on a boardwalk or under a roof;
#   nothing but reeds stands in the water itself.
WATER = ("creek", "mill_water")
SHELTERED = ("fair_prize_pile", "quarry_bottles")
BOARDS = ("porch", "floor_tile", "quarry_shed")
SIDES = ((1, 0), (-1, 0), (0, 1), (0, -1))


def _floor(world, x, y):
    from level_hickston import TILE
    names = getattr(_floor, "names", None)
    if names is None:
        names = _floor.names = {index: name for name, index in TILE.items()}
    h, w = world.solid.shape
    return names.get(int(world.floor[y, x]), "") if 0 <= x < w and 0 <= y < h else ""


def belongs(world, image, cx, cy):
    floor = _floor(world, cx, cy)
    if image == "prop_reeds":
        return any(_floor(world, cx + i, cy + j) in WATER for i in range(-2, 3) for j in range(-2, 3))
    if floor in WATER:
        return False
    if image in SHELTERED:
        return bool(world.roof[cy, cx] > 0) or floor in BOARDS
    if image == "prop_hay":
        return floor not in ("asphalt", "road", "porch", "floor_tile", "concrete")
    return True


def _open(world, x, y):
    h, w = world.solid.shape
    return 0 <= x < w and 0 <= y < h and world.solid[y, x] < 0


def wall_sides(world, cx, cy):
    """Directions from an open cell in which the very next cell is a wall."""
    return [(dx, dy) for dx, dy in SIDES if not _open(world, cx + dx, cy + dy)]


def against_wall(world, cx, cy, inset):
    """A point in the cell pushed toward its wall (or into its corner), and
    whether the cell leaves a clear lane past whatever stands there."""
    sides = wall_sides(world, cx, cy)
    if not sides:
        return None
    x, y = cx + .5, cy + .5
    for dx, dy in sides:
        x += dx * inset
        y += dy * inset
    for dx, dy in sides:
        # The cell across from the wall, and its two neighbours, must be open.
        ox, oy = cx - dx, cy - dy
        lane = [(ox, oy), (ox + dy, oy + dx), (ox - dy, oy - dx)]
        if not all(_open(world, a, b) for a, b in lane):
            return None
    return x, y, len(sides)


def furniture_spot(world, kind, cx, cy):
    """Where a breakable of this kind may stand in this cell, or None."""
    spot = against_wall(world, cx, cy, .12)
    if spot is None:
        return None
    roofed = bool(world.roof[cy, cx] > 0)
    if kind == "toilet" and not roofed:
        return None
    if kind in INDOOR and not roofed and kind not in ("vending", "window"):
        return None
    return spot[0], spot[1]


def dress(world, level, cells, taken):
    """Fill the bare stretches. `cells` are reachable (x, y) cells and `taken`
    the positions of everything already standing in the level."""
    from campaign import Billboard
    from engine import GroundMark

    chapter = level.id if level.id in LOW else "hickston"
    rng = np.random.default_rng(zlib.crc32((level.id + ":dressing").encode()))
    known = {}
    for board in world.billboards:
        known.setdefault(board.image, (board.height, board.z))
    taken = [(spot[0], spot[1]) for spot in taken] + [(b.x, b.y) for b in world.billboards]
    taken += [(s.x, s.y) for s in world.scenery]
    taken += [(x, y) for _, x, y in world.props]

    def clear(x, y, gap):
        return all(math.hypot(x - tx, y - ty) >= gap for tx, ty in taken)

    def pick(table, cx, cy):
        usable = [(image, height if height else known.get(image, (None,))[0])
                  for image, height in table]
        usable = [(image, height) for image, height in usable
                  if height and belongs(world, image, cx, cy)]
        return usable[int(rng.integers(len(usable)))] if usable else None

    order = [cells[i] for i in rng.permutation(len(cells))]
    boards = []
    low_budget = max(8, len(cells) // 38)
    tall_budget = max(5, len(cells) // 200)
    for cx, cy in order:
        if low_budget <= 0 and tall_budget <= 0:
            break
        roofed = bool(world.roof[cy, cx] > 0)
        sides = wall_sides(world, cx, cy)
        if not sides:
            continue
        corner = len(sides) >= 2
        x, y = cx + .5, cy + .5
        for dx, dy in sides:
            x += dx * .30
            y += dy * .30
        if tall_budget > 0 and not roofed and clear(x, y, 3.6):
            choice = pick(TALL[chapter], cx, cy)
            if choice:
                boards.append(Billboard(x, y, choice[0], choice[1]))
                taken.append((x, y))
                tall_budget -= 1
                continue
        if low_budget > 0 and clear(x, y, 2.8):
            table = LOW[chapter]
            if roofed:
                table = tuple(row for row in table if row[0] not in ("prop_reeds", "prop_hay"))
            choice = pick(table, cx, cy)
            if choice:
                boards.append(Billboard(x, y, choice[0], choice[1] * float(rng.uniform(.9, 1.06))))
                taken.append((x, y))
                low_budget -= 1
    world.billboards += tuple(boards)

    # Cover: small stacks in the middle of open ground, only where every cell
    # for two around is open, so a stack can never close a route.
    cover = []
    cover_budget = max(4, len(cells) // 140)
    for cx, cy in order:
        if cover_budget <= 0:
            break
        if not all(_open(world, cx + i, cy + j) for i in range(-2, 3) for j in range(-2, 3)):
            continue
        x, y = cx + .5, cy + .5
        if not clear(x, y, 3.6) or any(_floor(world, cx + i, cy + j) in WATER
                                       for i in (-1, 0, 1) for j in (-1, 0, 1)):
            continue
        kinds = COVER[chapter]
        first = kinds[int(rng.integers(len(kinds)))]
        cover.append((first, x, y))
        angle = float(rng.uniform(0, math.tau))
        second = kinds[int(rng.integers(len(kinds)))]
        cover.append((second, x + math.cos(angle) * .78, y + math.sin(angle) * .78))
        taken.append((x, y))
        cover_budget -= 1
    world.props = type(world.props)(list(world.props) + cover)

    marks = []
    wear_budget = max(6, len(cells) // 60)
    spots = [(x, y) for x, y in world_marks(world)]
    for cx, cy in order:
        if wear_budget <= 0:
            break
        if world.roof[cy, cx] > 0 or len(wall_sides(world, cx, cy)) > 1:
            continue
        if _floor(world, cx, cy) in WATER:
            continue
        x = cx + float(rng.uniform(.25, .75))
        y = cy + float(rng.uniform(.25, .75))
        if any(math.hypot(x - mx, y - my) < 4.0 for mx, my in spots):
            continue
        kind = WEAR[chapter][int(rng.integers(len(WEAR[chapter])))]
        marks.append(GroundMark(x, y, world.elevation(x, y) + .003, float(rng.uniform(-math.pi, math.pi)),
                                float(rng.uniform(.8, 1.3)), float(rng.uniform(.38, .56)),
                                f"detail_wear_{kind}"))
        spots.append((x, y))
        wear_budget -= 1
    world.dress_marks = tuple(world.dress_marks) + tuple(marks)
    return len(boards), len(marks), len(cover)


def world_marks(world):
    return [(mark.x, mark.y) for mark in world.dress_marks]
