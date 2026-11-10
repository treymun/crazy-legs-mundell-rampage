"""Give a rendered sprite the look of art digitized for a 256-colour game.

The game maps its finished frame onto one VGA palette. Sprites drawn in full
colour only meet that palette after they have been lit, so they shade more
smoothly than scanned art of the period did. `digitize` commits a sprite to
the palette up front, with a light ordered dither, so its colours step the way
a scanned actor's or a photographed prop's do.
"""
from __future__ import annotations

from functools import lru_cache
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
BAYER = np.array(((0, 8, 2, 10), (12, 4, 14, 6), (3, 11, 1, 9), (15, 7, 13, 5)), dtype=np.float32)


@lru_cache(maxsize=1)
def lookup() -> np.ndarray:
    """The game's RGB555 -> palette colour table (32768 x 3)."""
    return np.load(ROOT / "assets" / "tiles" / "vga_rgb555.npy", allow_pickle=False).reshape(-1, 3)


def digitize(image: Image.Image, dither: float = 9.0) -> Image.Image:
    rgba = np.asarray(image.convert("RGBA")).copy()
    h, w = rgba.shape[:2]
    y, x = np.indices((h, w))
    spread = (BAYER[y % 4, x % 4] / 16.0 - .5) * dither
    rgb = np.clip(rgba[..., :3].astype(np.float32) + spread[..., None], 0, 255).astype(np.int32)
    r5 = (rgb[..., 0] * 31 + 127) // 255
    g5 = (rgb[..., 1] * 31 + 127) // 255
    b5 = (rgb[..., 2] * 31 + 127) // 255
    rgba[..., :3] = lookup()[(r5 << 10) | (g5 << 5) | b5]
    rgba[rgba[..., 3] == 0] = 0
    return Image.fromarray(rgba)
