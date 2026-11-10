"""Pack the 512x116 sky panoramas and the level index's tile metadata.

Run with any Python that has Pillow (the reference venv works):
  <venv python> tools/pack_skies.py
"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


def _find_ref() -> Path:
    """Reference project: env override, then the repository this folder sits in."""
    import os
    env = os.environ.get("CRAZY_LEGS_REF")
    if env:
        return Path(env)
    here = Path(__file__).resolve().parent
    # godot/tools/ lives inside the Python project it is ported from; the
    # reference/ candidates cover a standalone copy of the godot folder.
    for candidate in (here.parent.parent, here.parent / "reference",
                      here.parent.parent / "reference"):
        if (candidate / "main.py").is_file():
            return candidate
    raise SystemExit("Python reference project not found: set CRAZY_LEGS_REF to its folder.")


PROJECT = Path(__file__).resolve().parent.parent
REF = _find_ref()
SRC = REF / "assets" / "tiles"
OUT = PROJECT / "assets_gen"
SKIES = ("sky", "fair_sky", "mill_sky", "quarry_sky")


def main():
    index = {}
    blob = bytearray()
    for name in SKIES:
        image = Image.open(SRC / f"{name}.png").convert("RGB")
        data = image.tobytes()
        index[name] = {"offset": len(blob), "w": image.width, "h": image.height}
        blob += data
    (OUT / "sky.bin").write_bytes(blob)
    (OUT / "sky_index.json").write_text(json.dumps(index, separators=(",", ":")))
    print(f"sky.bin {len(blob)/1e6:.2f} MB, {len(index)} skies")


if __name__ == "__main__":
    main()
