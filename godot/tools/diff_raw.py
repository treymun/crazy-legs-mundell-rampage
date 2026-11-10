"""Diff the ungraded frames (before the VGA palette) to isolate draw-order issues."""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

FRAMES = Path(__file__).resolve().parent / "frames"
tag = sys.argv[1] if len(sys.argv) > 1 else "stankys_road"
py = np.asarray(Image.open(FRAMES / f"pyraw_{tag}.png").convert("RGB"), np.int16)
gd = np.asarray(Image.open(FRAMES / f"gdraw_{tag}.png").convert("RGB"), np.int16)
rows = np.abs(py - gd).max(axis=2)
print(f"raw all mean={np.abs(py-gd).mean():.2f} exact={100.0*(rows==0).mean():.2f}%")
print(f"raw view exact={100.0*(rows[:156]==0).mean():.2f}%")
print(f"raw hud exact={100.0*(rows[156:]==0).mean():.2f}%")
ys = np.argwhere(rows.any(axis=1)).ravel()
print("rows differing:", ys[:20], "..." if len(ys) > 20 else "", "count", len(ys))
# top pairs
import collections
pairs = collections.Counter()
for y, x in np.argwhere(rows > 0):
    pairs[(tuple(int(v) for v in py[y, x]), tuple(int(v) for v in gd[y, x]))] += 1
for (p, g), n in pairs.most_common(10):
    print(f"{n:6d}  py={p}  gd={g}")
