"""Paint the gore sprites: gibs, wall and floor splatters, in blood red and alien green.

    python scripts/build_gore_art.py

Everything is drawn by this script at four times its size and shrunk, then given
a hard alpha edge like the rest of the sprites:

  gib_<part>.png / gib_a_<part>.png   chunks thrown by an overkill (human / alien)
  fx_blood_N.png / fx_acid_N.png      splats for walls
  mark_blood_N.png / mark_acid_N.png  pools and drops for the floor
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "assets" / "art"
RNG = np.random.default_rng(1997)
U = 4
FLESH, FLESH_DARK, BONE, MARROW = (150, 30, 26), (92, 14, 14), (222, 206, 170), (160, 120, 90)
SLIME, SLIME_DARK, CHITIN = (96, 168, 60), (44, 96, 34), (200, 214, 150)


def finish(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Shrink, add grit and a dark rim, and cut the alpha hard."""
    small = image.resize(size, Image.Resampling.LANCZOS)
    arr = np.asarray(small, dtype=np.float32)
    solid = arr[..., 3] >= 120
    arr[..., :3] += RNG.normal(0, 7, arr.shape[:2])[..., None]
    mask = Image.fromarray((solid * 255).astype(np.uint8))
    inner = np.asarray(mask.filter(ImageFilter.MinFilter(3))) > 0
    arr[solid & ~inner, :3] *= .55
    arr[..., 3] = solid * 255
    arr[~solid] = 0
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def blob(d: ImageDraw.ImageDraw, cx: float, cy: float, r: float, color, lumps: int = 9, rough: float = .28) -> None:
    pts = []
    for k in range(lumps * 3):
        a = k * math.tau / (lumps * 3)
        rr = r * (1 + rough * math.sin(a * lumps + cx) + RNG.uniform(-rough, rough) * .5)
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr * .86))
    d.polygon(pts, fill=color)


def shade(image: Image.Image, light, dark) -> Image.Image:
    """Round every drawn shape off: lit from the upper left, dark underneath."""
    arr = np.asarray(image, dtype=np.float32)
    alpha = arr[..., 3] / 255
    soft = np.asarray(image.getchannel("A").filter(ImageFilter.GaussianBlur(U * 2.2)), dtype=np.float32) / 255
    gy, gx = np.gradient(soft)
    lit = np.clip(-(gx + gy) * 9, -1, 1)[..., None]
    arr[..., :3] = np.clip(arr[..., :3] * (1 + lit * .55) + lit * 26, 0, 255)
    arr[..., 3] = alpha * 255
    return Image.fromarray(arr.astype(np.uint8))


def gib(part: str, alien: bool) -> Image.Image:
    meat, deep, bone = (SLIME, SLIME_DARK, CHITIN) if alien else (FLESH, FLESH_DARK, BONE)
    size = {"eye": 14, "meat": 22, "chunk": 28, "organ": 26, "rib": 34, "arm": 36, "boot": 34,
            "head": 30, "hand": 18, "gut": 30}[part]
    im = Image.new("RGBA", (size * U, size * U))
    d = ImageDraw.Draw(im)
    s = size * U
    if part == "eye":
        blob(d, s * .45, s * .5, s * .36, (226, 222, 204) if not alien else (30, 34, 30), 5, .05)
        d.ellipse((s * .28, s * .34, s * .56, s * .62), fill=(70, 100, 60) if not alien else (120, 255, 140))
        d.ellipse((s * .36, s * .42, s * .48, s * .54), fill=(8, 8, 8))
        d.line((s * .7, s * .55, s * .96, s * .78), fill=meat, width=U * 2)
    elif part in ("meat", "chunk"):
        blob(d, s * .5, s * .52, s * .36, deep, 7, .32)
        blob(d, s * .46, s * .48, s * .28, meat, 6, .3)
        if part == "chunk":
            d.rounded_rectangle((s * .58, s * .22, s * .86, s * .38), U * 2, fill=bone)
            d.ellipse((s * .78, s * .16, s * .96, s * .44), fill=bone)
    elif part == "organ":
        for k in range(5):
            blob(d, s * (.28 + .11 * k), s * (.5 + .12 * math.sin(k * 1.9)), s * .17, deep if k % 2 else meat, 5, .2)
        d.line((s * .2, s * .7, s * .05, s * .9), fill=deep, width=U * 2)
    elif part == "rib":
        d.rounded_rectangle((s * .44, s * .08, s * .56, s * .92), U * 2, fill=bone)
        for k in range(4):
            y = s * (.2 + k * .19)
            d.arc((s * .1, y - s * .1, s * .9, y + s * .16), 200, 340, fill=bone, width=U * 3)
        blob(d, s * .5, s * .56, s * .2, deep, 6, .35)
        blob(d, s * .42, s * .4, s * .12, meat, 5, .3)
    elif part == "arm":
        skin = (112, 128, 92) if alien else (186, 122, 92)
        cloth = (58, 62, 54) if alien else (126, 48, 42)
        d.line((s * .16, s * .78, s * .52, s * .46), fill=cloth, width=U * 8)
        d.line((s * .5, s * .48, s * .8, s * .22), fill=skin, width=U * 6)
        d.ellipse((s * .72, s * .1, s * .94, s * .32), fill=skin)
        for k in range(3):
            d.line((s * .86, s * .16, s * (.99 - k * .05), s * (.02 + k * .09)), fill=skin, width=U * 2)
        blob(d, s * .16, s * .8, s * .13, deep, 5, .3)
        d.ellipse((s * .11, s * .75, s * .21, s * .85), fill=bone)
    elif part == "head":
        skin = (112, 128, 92) if alien else (186, 122, 92)
        blob(d, s * .5, s * .46, s * .30, skin, 6, .08)
        if alien:
            for sx in (.36, .64):
                d.ellipse((s * (sx - .1), s * .36, s * (sx + .1), s * .56), fill=(8, 10, 12))
        else:
            d.pieslice((s * .18, s * .1, s * .82, s * .6), 180, 360, fill=(70, 50, 34))
            for sx in (.38, .62):
                d.ellipse((s * (sx - .05), s * .42, s * (sx + .05), s * .52), fill=(236, 230, 210))
                d.ellipse((s * (sx - .02), s * .45, s * (sx + .02), s * .5), fill=(10, 10, 10))
            d.ellipse((s * .4, s * .6, s * .6, s * .7), fill=(60, 14, 14))
        blob(d, s * .5, s * .82, s * .17, deep, 6, .4)
        d.ellipse((s * .44, s * .76, s * .56, s * .88), fill=bone)
    elif part == "hand":
        skin = (112, 128, 92) if alien else (186, 122, 92)
        blob(d, s * .45, s * .55, s * .24, skin, 5, .1)
        for k in range(4 if not alien else 3):
            d.line((s * (.3 + k * .12), s * .42, s * (.26 + k * .15), s * .12), fill=skin, width=U * 3)
        blob(d, s * .5, s * .82, s * .14, deep, 5, .4)
    elif part == "gut":
        pink = (150, 210, 120) if alien else (196, 96, 96)
        pts = [(s * (.12 + .76 * t), s * (.5 + .26 * math.sin(t * 9.0))) for t in [k / 14 for k in range(15)]]
        d.line(pts, fill=deep, width=U * 8, joint="curve")
        d.line(pts, fill=pink, width=U * 5, joint="curve")
    elif part == "boot":
        leather = (44, 40, 36) if alien else (70, 48, 32)
        cloth = (52, 56, 50) if alien else (66, 78, 108)
        d.rounded_rectangle((s * .32, s * .12, s * .58, s * .66), U * 3, fill=cloth)
        d.rounded_rectangle((s * .28, s * .5, s * .62, s * .84), U * 3, fill=leather)
        d.rounded_rectangle((s * .28, s * .68, s * .92, s * .88), U * 4, fill=leather)
        d.rectangle((s * .26, s * .86, s * .94, s * .92), fill=(24, 20, 18))
        blob(d, s * .45, s * .13, s * .15, deep, 5, .3)
        d.ellipse((s * .39, s * .06, s * .51, s * .18), fill=bone)
    return finish(shade(im, None, None), (size, size))


def splat(alien: bool, pool: bool, seed: int) -> Image.Image:
    wet, deep = (SLIME, SLIME_DARK) if alien else ((140, 22, 20), (84, 10, 12))
    size = 64 if pool else 48
    s = size * U
    im = Image.new("RGBA", (s, s))
    d = ImageDraw.Draw(im)
    rng = np.random.default_rng(seed)
    if pool:
        blob(d, s * .5, s * .5, s * rng.uniform(.26, .36), deep, 7, .22)
        blob(d, s * .5, s * .5, s * rng.uniform(.18, .26), wet, 6, .2)
        for _ in range(9):
            a, r = rng.uniform(0, math.tau), rng.uniform(.3, .47)
            rr = s * rng.uniform(.012, .04)
            x, y = s * (.5 + math.cos(a) * r), s * (.5 + math.sin(a) * r)
            d.ellipse((x - rr, y - rr, x + rr, y + rr), fill=deep)
    else:
        cx, cy = s * rng.uniform(.4, .6), s * rng.uniform(.3, .45)
        blob(d, cx, cy, s * rng.uniform(.16, .22), deep, 8, .4)
        blob(d, cx, cy, s * rng.uniform(.09, .14), wet, 6, .35)
        for _ in range(14):
            a, r = rng.uniform(0, math.tau), rng.uniform(.18, .46)
            rr = s * rng.uniform(.01, .034)
            x, y = cx + math.cos(a) * r * s, cy + math.sin(a) * r * s * .9
            d.ellipse((x - rr, y - rr, x + rr * 1.4, y + rr), fill=deep)
        for _ in range(4):
            x = cx + rng.uniform(-.16, .16) * s
            length = rng.uniform(.18, .46) * s
            w = max(U, int(s * rng.uniform(.012, .028)))
            d.line((x, cy, x, min(s - U, cy + length)), fill=deep, width=w)
            d.ellipse((x - w, cy + length - w, x + w, cy + length + w), fill=wet)
    out = im.resize((size, size), Image.Resampling.LANCZOS)
    arr = np.asarray(out, dtype=np.float32)
    arr[..., :3] += np.random.default_rng(seed + 9).normal(0, 6, arr.shape[:2])[..., None]
    arr[..., 3] = (arr[..., 3] >= 110) * 255
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def main() -> None:
    count = 0
    for alien, prefix in ((False, "gib_"), (True, "gib_a_")):
        for part in ("arm", "boot", "rib", "eye", "meat", "chunk", "organ", "head", "hand", "gut"):
            gib(part, alien).save(ART / f"{prefix}{part}.png")
            count += 1
    for alien, word in ((False, "blood"), (True, "acid")):
        for k in range(4):
            splat(alien, False, 40 + k + alien * 100).save(ART / f"fx_{word}_{k}.png")
            count += 1
        for k in range(3):
            splat(alien, True, 80 + k + alien * 100).save(ART / f"mark_{word}_{k}.png")
            count += 1
    print(f"gore art: {count} sprites")


if __name__ == "__main__":
    main()
