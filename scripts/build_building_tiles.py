"""Draw the wall tiles that turn a plain box into a building.

    python scripts/build_building_tiles.py

For each building material this writes two window tiles into assets/tiles/:
``<material>_win`` (dark glass) and ``<material>_lit`` (a lamp on inside). It
also writes ``trim_foundation`` and ``trim_eave``, the narrow bands a building
wall stands on and is capped with. The names are listed in
level_buildings.BUILDING_TILES, which level_hickston appends to TILES.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
TILES = ROOT / "assets" / "tiles"
sys.path.insert(0, str(ROOT))
from level_buildings import MATERIALS  # noqa: E402

RNG = np.random.default_rng(1931)
METAL = {"tin", "fair_iron", "mill_tin", "quarry_iron"}


def window(base: Image.Image, lit: bool, metal: bool) -> Image.Image:
    tile = base.convert("RGB").copy()
    draw = ImageDraw.Draw(tile)
    frame = (92, 98, 102) if metal else (66, 48, 34)
    edge = (40, 42, 44) if metal else (34, 24, 18)
    x0, y0, x1, y1 = 30, 34, 97, 86
    # Recess shadow, frame, then the glass.
    draw.rectangle((x0 - 2, y0 - 2, x1 + 2, y1 + 2), fill=edge)
    draw.rectangle((x0, y0, x1, y1), fill=frame)
    gx0, gy0, gx1, gy1 = x0 + 4, y0 + 4, x1 - 4, y1 - 4
    glass = np.zeros((gy1 - gy0 + 1, gx1 - gx0 + 1, 3), dtype=np.float32)
    yy, xx = np.indices(glass.shape[:2])
    if lit:
        glow = 1.0 - .35 * np.hypot((xx - glass.shape[1] * .5) / glass.shape[1],
                                    (yy - glass.shape[0] * .62) / glass.shape[0])
        glass[:] = np.array((238, 184, 92)) * glow[..., None]
        # A sagging curtain across the top and a shade pulled half down one side.
        curtain = yy < 5 + 4 * np.abs(np.sin(xx / 9.0))
        glass[curtain] = (150, 84, 60)
        shade = (xx < glass.shape[1] * .5) & (yy < glass.shape[0] * .45)
        glass[shade] = glass[shade] * .62 + np.array((70, 44, 30)) * .38
    else:
        glass[:] = np.array((30, 38, 48)) + (yy / glass.shape[0])[..., None] * np.array((16, 20, 22))
        streak = ((xx + yy) % 37 < 5) & (yy < glass.shape[0] * .8)
        glass[streak] += (26, 30, 32)
        glass += RNG.normal(0, 2.5, glass.shape)
    tile.paste(Image.fromarray(np.clip(glass, 0, 255).astype(np.uint8)), (gx0, gy0))
    # Muntins: one upright, one rail.
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    draw.rectangle((cx - 1, y0, cx + 1, y1), fill=frame)
    draw.rectangle((x0, cy - 1, x1, cy + 1), fill=frame)
    # Sill with a lit top edge and a shadow under it.
    sill = (124, 130, 132) if metal else (132, 108, 80)
    draw.rectangle((x0 - 5, y1 + 3, x1 + 5, y1 + 7), fill=sill)
    draw.line((x0 - 5, y1 + 3, x1 + 5, y1 + 3), fill=tuple(min(255, c + 34) for c in sill))
    draw.line((x0 - 4, y1 + 8, x1 + 4, y1 + 8), fill=edge)
    return tile


def foundation() -> Image.Image:
    noise = RNG.normal(0, 7, (128, 128))
    grey = 96 + noise + np.linspace(8, -14, 128)[:, None]
    rgb = np.stack((grey * 1.02, grey, grey * .95), axis=-1)
    # Poured in lifts: faint form lines, and block joints every 32 px.
    rgb[40:44] -= 14
    rgb[84:88] -= 12
    for x in range(0, 128, 32):
        rgb[:, x:x + 2] -= 16
    rgb[:10] += 26          # the lip where the wall sits
    rgb[10:14] -= 26
    rgb[-18:] -= np.linspace(0, 26, 18)[:, None, None]     # splash-back dirt
    return Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8))


def eave() -> Image.Image:
    grain = RNG.normal(0, 5, (128, 128)) + 6 * np.sin(np.arange(128) / 3.1)[None, :]
    rgb = np.stack((74 + grain, 54 + grain * .8, 38 + grain * .6), axis=-1)
    rgb[:16] += 30          # the edge of the roofing over the board
    rgb[16:22] -= 30
    rgb[-26:] -= np.linspace(4, 40, 26)[:, None, None]     # shadow thrown down the wall
    for x in range(0, 128, 64):
        rgb[22:, x:x + 2] -= 18                             # board joints
    return Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8))


def main() -> None:
    count = 0
    for material in MATERIALS:
        base = Image.open(TILES / f"{material}.png")
        for suffix, lit in (("win", False), ("lit", True)):
            window(base, lit, material in METAL).save(TILES / f"{material}_{suffix}.png")
            count += 1
    foundation().save(TILES / "trim_foundation.png")
    eave().save(TILES / "trim_eave.png")
    print(f"building tiles: {count} windows for {len(MATERIALS)} materials, 2 trims")


if __name__ == "__main__":
    main()
