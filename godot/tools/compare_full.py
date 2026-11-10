"""Compare full-frame reference renders (view + weapon + HUD) with the port.

  <venv python> tools/compare_full.py [tag ...]
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

FRAMES = Path(__file__).resolve().parent / "frames"
TAGS = ("stankys_road", "stankys_bar", "stankys_shotgun", "stankys_enemy",
        "stankys_hub", "fair_gate_full", "mill_yard_full", "quarry_yard_full")


def main():
    tags = sys.argv[1:] or list(TAGS)
    for tag in tags:
        py_path = FRAMES / f"py_full_{tag}.png"
        gd_path = FRAMES / f"gd_full_{tag}.png"
        if not py_path.exists() or not gd_path.exists():
            print(f"{tag:18s} missing")
            continue
        py = np.asarray(Image.open(py_path).convert("RGB"), np.int16)
        gd = np.asarray(Image.open(gd_path).convert("RGB"), np.int16)
        diff = np.abs(py - gd)
        rows = diff.max(axis=2)
        view = rows[:156]
        bar = rows[156:]
        print(f"{tag:18s} all mean={diff.mean():6.2f} exact={100.0 * (rows == 0).mean():5.1f}%"
              f" | view exact={100.0 * (view == 0).mean():5.1f}%"
              f" | hud exact={100.0 * (bar == 0).mean():5.1f}%")
        out = np.clip(diff * 4, 0, 255).astype(np.uint8)
        Image.fromarray(out, "RGB").save(FRAMES / f"difffull_{tag}.png")


if __name__ == "__main__":
    main()
