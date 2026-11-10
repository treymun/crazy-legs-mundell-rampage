"""Compare reference Python frames with Godot frames.

  <venv python> tools/compare_frames.py [tag ...]
Prints mean abs error and sample pixels, and writes diff_<tag>.png.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

FRAMES = Path(__file__).resolve().parent / "frames"
TAGS = ("spawn", "road_east", "road_west", "bar_inside", "bar_mirror", "barn",
        "pasture", "creek", "hub", "hub_north", "fair_gate", "fair_mid",
        "mill_yard", "quarry_yard", "hub_tower", "hub_wall", "hub_screen",
        "hub_runoff")
POINTS = ((0, 0), (160, 20), (160, 40), (160, 78), (160, 100), (160, 140),
          (40, 60), (280, 60), (100, 90))


def main():
    tags = sys.argv[1:] or list(TAGS)
    for tag in tags:
        py = np.asarray(Image.open(FRAMES / f"py_{tag}.png").convert("RGB"), np.int16)
        gd = np.asarray(Image.open(FRAMES / f"gd_{tag}.png").convert("RGB"), np.int16)
        diff = np.abs(py - gd)
        print(f"{tag:12s} mean={diff.mean():6.2f}  p95={np.percentile(diff, 95):5.1f}"
              f"  max={diff.max():3d}  exact={100.0 * (diff.max(axis=2) == 0).mean():5.1f}%")
        for x, y in POINTS:
            p = py[y, x]
            g = gd[y, x]
            if np.abs(p - g).max() > 2:
                print(f"    ({x:3d},{y:3d}) py={tuple(int(v) for v in p)} gd={tuple(int(v) for v in g)}")
        out = np.clip(diff * 4, 0, 255).astype(np.uint8)
        Image.fromarray(out, "RGB").save(FRAMES / f"diff_{tag}.png")


if __name__ == "__main__":
    main()
