"""Render the remade enemies in Blender and shrink them into assets/art.

    python scripts/build_enemy_actors.py [--kinds billy,coot,boss,rudy] [--no-render]

Blender (scripts/blender/enemy_actors.py) writes each cel three times oversized
into _preview/enemies/raw; this shrinks them to game size, hardens the alpha
edge the sprite renderer expects and darkens the silhouette by one pixel so a
figure reads against any wall. BLENDER_PATH overrides the Blender executable.

The older generators (encounter_art.py, expansion_enemies.py, quarry_actors.py,
signature_art.py) still know how to draw these characters; running them
overwrites these cels.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
from digitize import digitize  # noqa: E402

RAW = ROOT / "_preview" / "enemies" / "raw"
ART = ROOT / "assets" / "art"
BLENDER = os.environ.get("BLENDER_PATH") or str(
    Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "Blender" / "blender.exe")
SUPERSAMPLE = 4
KINDS = ("billy", "coot", "boss", "rudy", "clone", "alien", "barker", "millhand", "boilerback", "chalk_spitter",
         "yard_deputy", "bottle_tosser", "chain_hand", "valve_rat", "foreman", "baron", "jerry", "skeeter", "saucer",
         "crawler", "lantern")


def shrink(image: Image.Image, size: tuple[int, int], seed: int = 0) -> Image.Image:
    rgba = np.asarray(image.convert("RGBA"), dtype=np.float32) / 255
    rgba[..., :3] *= rgba[..., 3:]
    small = np.asarray(Image.fromarray((rgba * 255).astype(np.uint8)).resize(size, Image.Resampling.LANCZOS),
                       dtype=np.float32) / 255
    alpha = small[..., 3]
    rgb = np.where(alpha[..., None] > .02, small[..., :3] / np.maximum(alpha[..., None], .02), 0)
    solid = alpha >= .5
    # One-pixel contour: pixels of the figure that touch the outside.
    mask = Image.fromarray((solid * 255).astype(np.uint8))
    inner = np.asarray(mask.filter(ImageFilter.MinFilter(3))) > 0
    rim = solid & ~inner
    bright = rgb.max(axis=2) > .93            # muzzle flash and glow keep their edge
    # Grade toward a worn photograph: less colour, harder contrast, film grain.
    grey = rgb.mean(axis=2, keepdims=True)
    graded = grey + (rgb - grey) * .86
    graded = (graded - .42) * 1.18 + .52
    graded += np.random.default_rng(seed).normal(0, .026, grey.shape)
    rgb = np.where(bright[..., None], rgb, graded)
    rgb[rim & ~bright] *= .55
    out = np.zeros(small.shape, dtype=np.uint8)
    out[..., :3] = np.clip(rgb * 255, 0, 255)
    out[..., 3] = solid * 255
    out[~solid] = 0
    return Image.fromarray(out)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--kinds", default=",".join(KINDS))
    parser.add_argument("--no-render", action="store_true")
    args = parser.parse_args()
    if not args.no_render:
        subprocess.run([BLENDER, "-b", "-P", str(ROOT / "scripts" / "blender" / "enemy_actors.py"), "--",
                        str(RAW), args.kinds, "all", str(SUPERSAMPLE)], check=True,
                       stdout=subprocess.DEVNULL)
    meta = json.loads((RAW / "meta.json").read_text())
    count = 0
    for kind in args.kinds.split(","):
        size = tuple(meta[kind]["size"])
        for path in sorted(RAW.glob(f"{kind}_*.png")):
            image = Image.open(path)
            if path.stem.endswith("_down"):
                box = image.getchannel("A").point(lambda v: 255 if v > 127 else 0).getbbox()
                image = image.crop(box)
                target = (max(1, round(image.width / SUPERSAMPLE)), max(1, round(image.height / SUPERSAMPLE)))
            else:
                target = size
            cel = digitize(shrink(image, target, sum(map(ord, path.stem))))
            cel.save(ART / path.name)
            count += 1
            # The first build of the game still asks for the old three-cel walk by name.
            for beat, legacy in (("_w0", "_1"), ("_w2", "_-1")):
                if path.stem.endswith(beat):
                    cel.save(ART / (path.stem[:-3] + legacy + ".png"))
    print(f"enemy actors: {count} cels for {args.kinds}")


if __name__ == "__main__":
    main()
