"""Finish the buildings: a footing, an eave, and windows.

Every building in the campaign was a box in one texture from the dirt to the
roofline. This pass works on the finished wall list and touches nothing a
player can collide with:

  * a full-height wall in a building material is cut into three bands: a
    poured footing, the wall itself, and an eave board under the roofline;
  * along a straight run of three or more such walls, every third one gets a
    window, dark or lamp-lit, in that material.

Fences, hedges, log piles, rock faces and signs are left alone: only the
materials in MATERIALS count as a building.
"""
import zlib

import numpy as np

# Materials a building is made of. Each has <name>_win and <name>_lit tiles,
# drawn by scripts/build_building_tiles.py.
MATERIALS = ("barn", "tin", "brick", "plaster", "cinder", "office_wall", "fair_booth", "fair_iron",
             "mill_tin", "quarry_iron", "quarry_shed", "hub_service_wall")
BUILDING_TILES = tuple(f"{m}_{s}" for m in MATERIALS for s in ("win", "lit")) + (
    "trim_foundation", "trim_eave")
FOOTING = .20
EAVE = .15
MIN_HEIGHT = 1.70


def finish(world, level):
    """Rewrite world.walls with footings, eaves and windows. Returns counts."""
    from level_hickston import TILE

    building = {TILE[name]: name for name in MATERIALS}
    walls = [tuple(float(v) for v in row) for row in np.asarray(world.walls)]
    rng = np.random.default_rng(zlib.crc32((level.id + ":buildings").encode()))
    doors = [(d.x + .5, d.y + .5) for d in world.doors]
    # Signs and notices already hang on some walls: no window behind them.
    signs = [(b.x, b.y) for b in world.billboards] + [(s.x, s.y) for s in world.stations]
    panes = {(int(x), int(y)) for x, y in world.pane_tiles}
    h, w = world.solid.shape

    def owner(seg):
        """The solid cell a unit wall segment is the face of, or None."""
        x0, y0, x1, y1 = seg[:4]
        if abs(abs(x1 - x0) + abs(y1 - y0) - 1.0) > 1e-3:
            return None
        mx, my = (x0 + x1) / 2, (y0 + y1) / 2
        if abs(y0 - y1) < 1e-6:        # runs along x: cells above and below
            cells = ((int(mx), int(round(my)) - 1), (int(mx), int(round(my))))
        else:
            cells = ((int(round(mx)) - 1, int(my)), (int(round(mx)), int(my)))
        for cx, cy in cells:
            if 0 <= cx < w and 0 <= cy < h and world.solid[cy, cx] == int(seg[4]):
                return cx, cy
        return None

    faces = {}
    for index, seg in enumerate(walls):
        material = int(seg[4])
        if material not in building or seg[7] - seg[6] < MIN_HEIGHT:
            continue
        cell = owner(seg)
        if cell is None or cell in panes:
            continue
        faces[index] = cell

    # Straight runs of building cells, by row and by column.
    cells = set(faces.values())
    windows = {}
    for horizontal in (True, False):
        seen = set()
        for cell in sorted(cells):
            if cell in seen:
                continue
            step = (1, 0) if horizontal else (0, 1)
            run = [cell]
            while (run[-1][0] + step[0], run[-1][1] + step[1]) in cells and \
                    world.solid[run[-1][1] + step[1], run[-1][0] + step[0]] == world.solid[cell[1], cell[0]]:
                run.append((run[-1][0] + step[0], run[-1][1] + step[1]))
            seen.update(run)
            if len(run) < 3:
                continue
            for k in range(1, len(run) - 1, 3):
                cx, cy = run[k]
                if any(abs(cx + .5 - dx) < 1.6 and abs(cy + .5 - dy) < 1.6 for dx, dy in doors):
                    continue
                if any(abs(cx + .5 - sx) < 1.25 and abs(cy + .5 - sy) < 1.25 for sx, sy in signs):
                    continue
                windows.setdefault((cx, cy), "lit" if rng.random() < .38 else "win")

    out = []
    banded = 0
    for index, seg in enumerate(walls):
        if index not in faces:
            out.append(seg)
            continue
        x0, y0, x1, y1, material, light, base, top, area = seg
        name = building[int(material)]
        middle = material
        kind = windows.get(faces[index])
        if kind:
            # A window only shows on a face that runs along its wall, not on an end.
            middle = float(TILE[f"{name}_{kind}"])
        out.append((x0, y0, x1, y1, float(TILE["trim_foundation"]), light * .92, base, base + FOOTING, area))
        out.append((x0, y0, x1, y1, middle, light, base + FOOTING, top - EAVE, area))
        out.append((x0, y0, x1, y1, float(TILE["trim_eave"]), light, top - EAVE, top, area))
        banded += 1
    world.walls = np.asarray(out, dtype=np.float32)
    return banded, len(windows)
