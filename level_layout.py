"""Break the wide, empty yards of every chapter (and the county hub) into lanes.

The chapters were authored as rooms and long open yards. The rooms loop well;
the yards were flat fields where a fight had no shape. This pass adds real
geometry there: low walls to fight over, and tall blocks that cut sightlines
and make a second way round.

Rules that keep it safe:
  * a structure only goes where the ground for two cells around it is open,
    flat, dry and unroofed, so every lane past it is at least two cells wide
    and no route can close;
  * nothing is built near a door, gate, station, pickup, enemy, patrol path,
    prop or sign;
  * it is deterministic: the same level always gets the same structures.

`rework` runs before anything else is placed by populate2, and rebuilds only
the wall segments its own cells change.
"""
import math

import numpy as np

# (texture, height) by chapter: low pieces are cover, tall pieces block the view.
LOW = {
    "hickston": (("stockyard", .86), ("crate_side", .80), ("cinder", .90)),
    "hub": (("stockyard", .86), ("crate_side", .80)),
    "fair": (("fair_booth", .82), ("crate_side", .80), ("fair_prize", .83)),
    "sawmill": (("mill_log", .92), ("crate_side", .80)),
    "quarry": (("quarry_face", .88), ("crate_side", .80)),
}
TALL = {
    "hickston": (("tin", 2.05), ("cinder", 2.10), ("barn", 2.20)),
    "hub": (("tin", 2.05), ("crate_side", 1.70)),
    "fair": (("fair_booth", 2.10), ("fair_iron", 2.10)),
    "sawmill": (("mill_log", 1.75), ("mill_tin", 2.10)),
    "quarry": (("quarry_face", 1.85), ("quarry_shed", 2.05)),
}
# Footprints in cells, biggest first; each needs `need` cells of clearance.
SHAPES = (
    (4, ((0, 0), (1, 0), (2, 0), (0, 1), (1, 1), (2, 1)), "tall"),      # 3x2 shed
    (4, ((0, 0), (1, 0), (2, 0), (3, 0), (0, 1)), "low"),               # long L wall
    (3, ((0, 0), (1, 0), (0, 1), (1, 1)), "tall"),                      # 2x2 block
    (3, ((0, 0), (1, 0), (2, 0)), "low"),                               # 3-long wall
    (3, ((0, 0), (0, 1), (0, 2)), "low"),                               # 3-tall wall
    (2, ((0, 0), (1, 0)), "low"),                                       # short wall
)
WATER = ("creek", "mill_water")
# Roads and rail stay clear: nobody builds a shed in the street.
ROADS = ("road", "asphalt", "oil_asphalt", "shoulder", "tracks", "route_threshold")


def _points(world, level):
    """Everything a structure has to keep clear of, as (x, y, radius)."""
    pts = [(level.spawn[0], level.spawn[1], 3.0)]
    pts += [(x, y, 2.0) for _, x, y in world.enemies]
    pts += [(x, y, 1.6) for _, x, y in world.pickups]
    pts += [(x, y, 1.6) for _, x, y in world.props]
    pts += [(x + .5, y + .5, 1.8) for x, y in world.fuel_drums]
    pts += [(s.x, s.y, 2.2) for s in world.stations]
    pts += [(s.x, s.y, 1.6) for s in world.scenery]
    pts += [(b.x, b.y, 1.5) for b in world.billboards]
    pts += [(d.x + .5, d.y + .5, 3.0) for d in world.doors]
    pts += [(m.x, m.y, 1.2) for m in world.dress_marks]
    for route in world.patrols.values():
        for (ax, ay), (bx, by) in zip(route, list(route[1:]) + [route[0]]):
            steps = max(1, int(math.hypot(bx - ax, by - ay) * 2))
            pts += [(ax + (bx - ax) * k / steps, ay + (by - ay) * k / steps, 1.7)
                    for k in range(steps + 1)]
    gates = list(getattr(world, "hub_gates", ())) + list(getattr(world, "locked_gates", ()))
    if world.return_gate is not None:
        gates.append(world.return_gate)
    pts += [(g.x, g.y, 4.5) for g in gates]
    for name in ("hub_clues", "notes", "interiors"):
        for item in getattr(world, name, ()):
            pts.append((float(item[1]), float(item[2]), 2.0))
    for item in getattr(world, "exchanges", ()):
        pts.append((item.x, item.y, 2.0) if hasattr(item, "x") else (item["x"], item["y"], 2.0))
    for f in world.collision_volumes:
        pts.append(((f.x0 + f.x1) / 2, (f.y0 + f.y1) / 2, 1.2 + max(f.x1 - f.x0, f.y1 - f.y0) / 2))
    ext = getattr(world, "extraction", None)
    if ext is not None and hasattr(ext, "x"):
        pts.append((ext.x, ext.y, 3.0))
    return pts


def _clearance(world, names):
    """For each open cell: how many cells of open, flat, dry, unroofed ground
    surround it (Chebyshev distance to the nearest cell that is not)."""
    h, w = world.solid.shape
    good = (world.solid < 0) & (world.roof <= 0)
    road = np.zeros((h, w), dtype=bool)
    for y in range(h):
        for x in range(w):
            floor = names.get(int(world.floor[y, x]), "")
            if good[y, x] and floor in WATER:
                good[y, x] = False
            if good[y, x] and (floor in ROADS or floor.startswith("route")):
                road[y, x] = True
    out = np.zeros((h, w), dtype=np.int16)
    for y in range(h):
        for x in range(w):
            if not good[y, x]:
                continue
            r = 0
            while r < 8:
                y0, y1, x0, x1 = y - r - 1, y + r + 1, x - r - 1, x + r + 1
                if y0 < 0 or x0 < 0 or y1 >= h or x1 >= w:
                    break
                block = good[y0:y1 + 1, x0:x1 + 1]
                if not block.all() or np.ptp(world.ground[y0:y1 + 1, x0:x1 + 1]) > 1e-4:
                    break
                r += 1
            out[y, x] = r
    return out, road


def rework(world, level):
    """Add the structures and patch the wall list. Returns how many were built."""
    from level_hickston import TILE

    names = {index: name for name, index in TILE.items()}
    facades = level.id == "hickston"
    before = {tuple(np.round(np.asarray(seg, dtype=np.float64), 3)) for seg in world.wall_segments(facades)}
    points = _points(world, level)
    h, w = world.solid.shape
    built = 0
    budget = max(4, int((world.solid < 0).sum()) // 120)
    while built < budget:
        clear, road = _clearance(world, names)
        best = None
        # Alternate cover and view-blockers so a yard gets both.
        order = sorted(SHAPES, key=lambda shape: (shape[2] != ("tall", "low")[built % 2], -shape[0]))
        for need, cells, kind in order:
            # A footprint fits where every one of its cells has two open cells around it.
            for y in range(2, h - 4):
                for x in range(2, w - 5):
                    if clear[y, x] < need:
                        continue
                    spots = [(x + dx, y + dy) for dx, dy in cells]
                    if any(clear[cy, cx] < 2 or road[cy - 1:cy + 2, cx - 1:cx + 2].any()
                           for cx, cy in spots):
                        continue
                    if any(math.hypot(cx + .5 - px, cy + .5 - py) < pr
                           for cx, cy in spots for px, py, pr in points):
                        continue
                    score = int(sum(clear[cy, cx] for cx, cy in spots)) * 10 + need
                    if best is None or score > best[0]:
                        best = (score, spots, kind)
            if best is not None:
                break
        if best is None:
            break
        _, spots, kind = best
        # The hub shares the first chapter's map: it starts below row 33.
        chapter = "hub" if facades and spots[0][1] >= 33 else level.id
        table = (TALL if kind == "tall" else LOW).get(chapter, LOW["hickston"])
        texture, height = table[built % len(table)]
        for cx, cy in spots:
            world.solid[cy, cx] = TILE[texture]
            world.wall_height[cy, cx] = height
            points.append((cx + .5, cy + .5, 3.2))      # keep the next one off this one
        built += 1
    if built:
        after_list = world.wall_segments(facades)
        after = {tuple(np.round(np.asarray(seg, dtype=np.float64), 3)): seg for seg in after_list}
        gone = before - set(after)
        kept = [seg for seg in world.walls
                if tuple(np.round(np.asarray(seg, dtype=np.float64), 3)) not in gone]
        fresh = [seg for key, seg in after.items() if key not in before]
        world.walls = np.asarray(kept + [tuple(float(v) for v in seg) for seg in fresh], dtype=np.float32)
    return built
