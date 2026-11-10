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

for lo, hi in ((156, 163), (163, 176), (176, 200)):
    band = rows[lo:hi]
    cols = np.argwhere(band.any(axis=0)).ravel()
    print(f"rows {lo}-{hi - 1}: {int(band.sum())} diffs across {len(cols)} cols")
    if len(cols):
        # summarize ranges
        start = cols[0]
        prev = cols[0]
        for c in cols[1:]:
            if c != prev + 1:
                print(f"   cols {start}-{prev}")
                start = c
            prev = c
        print(f"   cols {start}-{prev}")
