"""Crop the same region out of the py/gd full frames and scale it up for eyeballing."""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

FRAMES = Path(__file__).resolve().parent / "frames"


def main():
    tag = sys.argv[1]
    x, y, w, h = (int(v) for v in sys.argv[2:6])
    scale = int(sys.argv[6]) if len(sys.argv) > 6 else 3
    py = Image.open(FRAMES / f"py_full_{tag}.png").convert("RGB").crop((x, y, x + w, y + h))
    gd = Image.open(FRAMES / f"gd_full_{tag}.png").convert("RGB").crop((x, y, x + w, y + h))
    sheet = Image.new("RGB", (w * scale * 2 + 8, h * scale), (255, 0, 255))
    sheet.paste(py.resize((w * scale, h * scale), Image.NEAREST), (0, 0))
    sheet.paste(gd.resize((w * scale, h * scale), Image.NEAREST), (w * scale + 8, 0))
    out = FRAMES / f"crop_{tag}_{x}_{y}.png"
    sheet.save(out)
    print(out)


if __name__ == "__main__":
    main()
