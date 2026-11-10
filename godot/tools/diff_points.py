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

for name, want in (("py51,33,25 gd0", ((51, 33, 25), (0, 0, 0))),
                   ("py25,21,18 gd68,53,43", ((25, 21, 18), (68, 53, 43))),
                   ("pin light", ((244, 194, 116), (38, 27, 21)))):
    pts = [(int(x), int(y)) for y, x in np.argwhere(rows > 0)
           if tuple(int(v) for v in py[y, x]) == want[0]
           and tuple(int(v) for v in gd[y, x]) == want[1]]
    print(name, len(pts), pts[:60])
