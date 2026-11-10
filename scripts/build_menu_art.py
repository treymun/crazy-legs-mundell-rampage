"""Draw the front end's supporting artwork into assets/art (Pillow, deterministic).

    python scripts/build_menu_art.py

The title screen keeps the established backdrop and protagonist
(title_backdrop.png, title_logo.png) and adds, at the game's own 320x200:

  menu_board.png     weathered timber the menu is painted on
  menu_sign.png      rusted tin header for the settings and other sub-screens
  menu_sheet.png     the darkened yard with a timber frame those screens sit in
  menu_glow.png      warm lamp light that falls on the board (flickers in game)
  menu_wanted.png    the county wanted poster, nailed to the fence
  menu_bessie.png    the MISSING notice for Bessie
  menu_saucer.png    the thing in the sky

Everything is drawn from seeded noise and the game's existing art, so a rerun
reproduces the same files byte for byte.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ART = Path(__file__).resolve().parent.parent / "assets" / "art"


def noise(shape, seed, scale=1.0):
    return np.random.default_rng(seed).standard_normal(shape) * scale


def timber(width: int, height: int, seed: int, plank: int = 23) -> Image.Image:
    """Vertical boards: grain streaks, seams, knots and nail heads."""
    base = np.array([96, 66, 42], float)
    img = np.zeros((height, width, 3))
    x = 0
    index = 0
    while x < width:
        w = plank + int(np.random.default_rng(seed + index).integers(-4, 5))
        tone = 1 + noise((), seed * 7 + index, .09)
        grain = noise((1, max(w, 1)), seed * 13 + index, .07).repeat(height, 0)
        streak = noise((height, max(w, 1)), seed * 17 + index, .035)
        img[:, x:x + w] = (base * tone)[None, None] * (1 + grain + streak)[:, :width - x, None]
        img[:, x:x + 1] *= .45                                   # the seam
        if x + 1 < width:
            img[:, x + 1:x + 2] *= 1.12
        x += w
        index += 1
    rng = np.random.default_rng(seed + 99)
    for _ in range(max(2, width * height // 2600)):               # knots
        cx, cy = int(rng.integers(3, width - 3)), int(rng.integers(3, height - 3))
        yy, xx = np.ogrid[:height, :width]
        d = ((xx - cx) / 2.6) ** 2 + ((yy - cy) / 1.6) ** 2
        img *= (1 - .45 * np.exp(-d))[..., None]
    img[:2] *= .6
    img[-2:] *= .5
    out = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB")
    draw = ImageDraw.Draw(out)
    for nx in range(6, width - 4, 44):
        for ny in (4, height - 6):
            draw.point((nx, ny), (40, 30, 24))
            draw.point((nx, ny - 1), (150, 140, 128))
    return out


def rust(width: int, height: int, seed: int) -> Image.Image:
    """Corrugated tin gone to rust at the edges."""
    ridges = (np.sin(np.arange(width) * .9) * .5 + .5)[None, :, None]
    tin = np.array([132, 138, 136], float) * (.72 + .28 * ridges)
    tin = np.broadcast_to(tin, (height, width, 3)).copy()
    blot = Image.fromarray((np.random.default_rng(seed).random((height // 3 + 2, width // 5 + 2)) * 255).astype(np.uint8))
    blot = np.asarray(blot.resize((width, height), Image.BICUBIC), float) / 255
    rows = np.arange(height)[:, None] * np.ones((1, width))
    cols = np.arange(width)[None, :] * np.ones((height, 1))
    edge = np.minimum(np.minimum(rows, height - 1 - rows) / 4.0,
                      np.minimum(cols, width - 1 - cols) / 10.0)
    amount = np.clip(blot * 1.5 - np.clip(edge, 0, 1) * .75, 0, 1)[..., None]
    orange = np.array([150, 72, 34], float) * (.8 + .2 * ridges)
    img = tin * (1 - amount) + orange * amount + noise((height, width, 1), seed + 1, 5)
    out = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB")
    draw = ImageDraw.Draw(out)
    draw.rectangle((0, 0, width - 1, height - 1), outline=(34, 24, 18))
    for nx in (4, width - 5):
        draw.point((nx, height // 2), (222, 226, 224))
        draw.point((nx, height // 2 + 1), (40, 34, 30))
    return out


def glow(width: int, height: int) -> Image.Image:
    yy, xx = np.mgrid[:height, :width]
    d = np.hypot((xx - width * .5) / (width * .5), (yy - height * .18) / (height * .9))
    alpha = np.clip(1 - d, 0, 1) ** 2 * 86
    img = np.zeros((height, width, 4), np.uint8)
    img[..., :3] = (255, 196, 112)
    img[..., 3] = alpha.astype(np.uint8)
    return Image.fromarray(img, "RGBA")


def paper(width: int, height: int, seed: int, colour=(214, 196, 158)) -> Image.Image:
    img = np.array(colour, float)[None, None] + noise((height, width, 1), seed, 7)
    stain = Image.fromarray((np.random.default_rng(seed + 5).random((4, 4)) * 255).astype(np.uint8)).resize((width, height), Image.BICUBIC)
    img -= (np.asarray(stain, float)[..., None] / 255) * 22
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB")


def pinned(sheet: Image.Image) -> Image.Image:
    """A sheet of paper with a drop shadow and a nail, on transparency."""
    out = Image.new("RGBA", (sheet.width + 2, sheet.height + 2), (0, 0, 0, 0))
    out.paste(Image.new("RGBA", sheet.size, (10, 7, 5, 150)), (2, 2))
    out.paste(sheet.convert("RGBA"), (0, 0))
    draw = ImageDraw.Draw(out)
    draw.point((sheet.width // 2, 1), (40, 34, 30, 255))
    draw.point((sheet.width // 2, 0), (200, 200, 196, 255))
    return out


def main() -> None:
    board = timber(188, 112, 11)
    ImageDraw.Draw(board).rectangle((0, 0, 187, 111), outline=(30, 20, 14))
    board.save(ART / "menu_board.png")

    rust(296, 20, 3).save(ART / "menu_sign.png")

    # Sub-screens: the same yard, pushed back and dimmed, inside a timber frame.
    yard = Image.open(ART / "title_backdrop.png").convert("RGB").filter(ImageFilter.GaussianBlur(1.4))
    yard = Image.eval(yard, lambda v: int(v * .34))
    frame = timber(320, 200, 21, 29)
    mask = Image.new("L", (320, 200), 255)
    ImageDraw.Draw(mask).rectangle((7, 7, 312, 192), fill=0)
    sheet = Image.composite(frame, yard, mask)
    draw = ImageDraw.Draw(sheet)
    draw.rectangle((7, 7, 312, 192), outline=(24, 16, 12))
    draw.rectangle((8, 8, 311, 191), outline=(120, 86, 56))
    sheet.save(ART / "menu_sheet.png")

    glow(188, 120).save(ART / "menu_glow.png")

    poster = Image.open(ART / "wanted_poster.png").convert("RGB").resize((38, 48), Image.LANCZOS)
    pinned(poster).save(ART / "menu_wanted.png")

    notice = paper(46, 40, 8)
    draw = ImageDraw.Draw(notice)
    draw.rectangle((0, 0, 45, 39), outline=(70, 52, 38))
    draw.rectangle((3, 3, 42, 9), fill=(150, 34, 24))             # the MISSING banner
    pig = Image.open(ART / "bessie_0.png").convert("RGBA")
    pig = pig.resize((38, 24), Image.LANCZOS)
    notice.paste(pig, (4, 11), pig)
    draw.line((6, 37, 39, 37), fill=(70, 52, 38))
    pinned(notice).save(ART / "menu_bessie.png")

    saucer = Image.new("RGBA", (17, 8), (0, 0, 0, 0))
    draw = ImageDraw.Draw(saucer)
    draw.ellipse((5, 0, 11, 5), fill=(120, 190, 150, 255))
    draw.ellipse((0, 3, 16, 7), fill=(92, 100, 104, 255))
    draw.line((2, 5, 14, 5), fill=(190, 200, 198, 255))
    for x in (3, 8, 13):
        draw.point((x, 6), (160, 255, 150, 255))
    saucer.save(ART / "menu_saucer.png")
    print("menu art written to", ART)


if __name__ == "__main__":
    main()
