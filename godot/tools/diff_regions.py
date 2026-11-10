"""Localise differences in the full-frame comparison by region."""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

FRAMES = Path(__file__).resolve().parent / "frames"
tag = sys.argv[1] if len(sys.argv) > 1 else "stankys_road"
py = np.asarray(Image.open(FRAMES / f"py_full_{tag}.png").convert("RGB"), np.int16)
gd = np.asarray(Image.open(FRAMES / f"gd_full_{tag}.png").convert("RGB"), np.int16)
rows = np.abs(py - gd).max(axis=2)

print("row bands (rows with any diff):")
cur = None
start = 0
counts = rows.any(axis=1)
for y in range(200):
    if counts[y] and cur is None:
        cur = y
    elif not counts[y] and cur is not None:
        print(f"  rows {cur}-{y - 1}: {rows[cur:y].sum()} diffs, max {rows[cur:y].max()}")
        cur = None
if cur is not None:
    print(f"  rows {cur}-199: {rows[cur:200].sum()} diffs")

print("\ncolumn bands:")
counts = rows.any(axis=0)
cur = None
for x in range(320):
    if counts[x] and cur is None:
        cur = x
    elif not counts[x] and cur is not None:
        print(f"  cols {cur}-{x - 1}")
        cur = None
if cur is not None:
    print(f"  cols {cur}-319")

print("\nsample differing pixels:")
idx = np.argwhere(rows > 0)
for y, x in idx[:: max(1, len(idx) // 30)][:30]:
    print(f"  ({x:3d},{y:3d}) py={tuple(int(v) for v in py[y, x])} gd={tuple(int(v) for v in gd[y, x])}")
