"""Create original low-resolution game art from four supplied photos.

The landmarks and cutout outlines are calibrated for the four reference photos.
Point coordinates are relative to the sizes recorded in CALIBRATION.
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parent
ART = ROOT / "assets" / "art"
BODY_PLATE = ROOT / "source_art" / "body_plate.png"
SIZE = (144, 180)
ANCHORS = np.array([[45, 73, 1], [94, 72, 1], [70, 113, 1]])
CALIBRATION = (
    ((351, 528), [(129, 264), (240, 251), (191, 367)],
     [(29, 157), (40, 114), (79, 71), (153, 49), (223, 54), (271, 91),
      (292, 164), (299, 244), (296, 316), (280, 388), (247, 448), (204, 478),
      (157, 467), (116, 430), (83, 386), (58, 333), (39, 261)]),
    ((232, 332), [(53, 127), (128, 117), (88, 190)],
     [(8, 98), (15, 59), (36, 30), (75, 5), (118, 0), (157, 13), (179, 41),
      (192, 80), (193, 121), (201, 145), (198, 183), (185, 224), (165, 260),
      (143, 282), (112, 302), (83, 297), (56, 273), (37, 241), (25, 204),
      (16, 174), (11, 141)]),
    ((180, 180), [(73, 79), (99, 78), (86, 103)],
     [(54, 77), (58, 60), (68, 49), (89, 46), (106, 50), (116, 62),
      (119, 83), (116, 105), (108, 122), (98, 135), (86, 139), (72, 134),
      (62, 121), (54, 104), (51, 89)]),
    ((180, 214), [(39, 76), (85, 74), (63, 114)],
     [(13, 42), (20, 26), (37, 12), (60, 8), (84, 16), (103, 34), (111, 56),
      (115, 83), (111, 110), (102, 141), (90, 160), (69, 179), (47, 174),
      (32, 161), (21, 145), (15, 118), (9, 90), (8, 62)]),
)
FRAMES = ("idle_center", "idle_blink", "look_left", "look_right", "grin_rampage",
          "yell_fire", "drunk_dizzy", "ouch_shock", "hurt_25", "hurt_50", "hurt_75", "dead")

# A single shared 8-bit color table, tuned for the portrait, clothing and prop art.
RAMPS = [
    ((13, 9, 8), (248, 224, 184), 32), ((29, 14, 11), (249, 185, 151), 42),
    ((19, 13, 12), (177, 92, 57), 32), ((14, 12, 17), (167, 167, 175), 25),
    ((10, 15, 18), (125, 158, 178), 24), ((17, 16, 9), (148, 157, 89), 20),
    ((17, 5, 9), (209, 56, 41), 27), ((22, 9, 24), (154, 109, 138), 16),
    ((33, 20, 12), (244, 188, 86), 18), ((7, 7, 7), (248, 246, 237), 20),
]
PALETTE = np.concatenate([np.linspace(a, b, n) for a, b, n in RAMPS]).astype(np.uint8)
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]])


def digitize(image, size, border=True, legacy=False):
    image = image.resize(size, Image.Resampling.LANCZOS)
    rgba = np.asarray(image).copy()
    sharpen = ImageFilter.UnsharpMask(1.05, 155, 2) if legacy else ImageFilter.UnsharpMask(.8, 72, 4)
    rgb = np.asarray(image.convert("RGB").filter(sharpen))
    y, x = np.indices(rgba.shape[:2])
    samples = rgb.astype(np.int16) + (BAYER[y % 4, x % 4, None] - 7.5) * (.52 if legacy else .36)
    palette = PALETTE.copy() if legacy else PALETTE
    if legacy:
        palette[155:175] = np.linspace((17, 16, 9), (181, 182, 100), 20).astype(np.uint8)
    flat = samples.reshape(-1, 3).astype(np.float32)
    for i in range(0, len(flat), 4096):
        batch = flat[i:i + 4096]
        dist = np.square(batch[:, None] - palette[None]).sum(axis=-1)
        rgba.reshape(-1, 4)[i:i + len(batch), :3] = palette[dist.argmin(axis=1)]
    alpha = Image.fromarray(np.where(rgba[:, :, 3] >= 108, 255, 0).astype(np.uint8))
    rgba[:, :, 3] = np.asarray(alpha)
    if border:
        expanded = np.asarray(alpha.filter(ImageFilter.MaxFilter(3)))
        fringe = (expanded > 0) & (rgba[:, :, 3] == 0)
        rgba[fringe] = (21, 13, 12, 255)
    return Image.fromarray(rgba)


def aligned(path, calibration):
    reference, marks, outline = calibration
    photo = ImageOps.exif_transpose(Image.open(path)).convert("RGBA")
    photo = photo.resize(reference, Image.Resampling.LANCZOS)
    mask = Image.new("L", reference)
    ImageDraw.Draw(mask).polygon(outline, fill=255)
    photo.putalpha(mask.filter(ImageFilter.GaussianBlur(.8)))
    transform = np.linalg.solve(ANCHORS, np.array(marks)).T.ravel()
    return photo.transform(SIZE, Image.Transform.AFFINE, transform, Image.Resampling.BICUBIC)


def morph(image, controls):
    y, x = np.indices((SIZE[1], SIZE[0]), dtype=np.float32)
    dx = np.zeros_like(x)
    dy = np.zeros_like(y)
    for cx, cy, rx, ry, vx, vy, sx, sy in controls:
        weight = np.exp(-.5 * (((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2))
        dx += weight * (vx + (x - cx) * sx)
        dy += weight * (vy + (y - cy) * sy)
    xf = np.clip(x + dx, 0, SIZE[0] - 1.01)
    yf = np.clip(y + dy, 0, SIZE[1] - 1.01)
    x0, y0 = xf.astype(int), yf.astype(int)
    a, b = (xf - x0)[..., None], (yf - y0)[..., None]
    px = np.asarray(image).astype(np.float32)
    result = ((px[y0, x0] * (1 - a) + px[y0, x0 + 1] * a) * (1 - b)
              + (px[y0 + 1, x0] * (1 - a) + px[y0 + 1, x0 + 1] * a) * b)
    return Image.fromarray(result.astype(np.uint8))


def blend_photo(base, donor, regions):
    """Use donor pixels where the expression changes while keeping base lighting."""
    y, x = np.indices((SIZE[1], SIZE[0]), dtype=np.float32)
    dest = np.array(base).astype(np.float32)
    source = np.array(donor).astype(np.float32)
    for cx, cy, rx, ry, strength in regions:
        distance = ((x - cx) / rx)**2 + ((y - cy) / ry)**2
        ring = (distance >= .85) & (distance < 1.3) & (source[:, :, 3] > 200)
        source_mean = np.median(source[ring, :3], axis=0)
        dest_mean = np.median(dest[ring, :3], axis=0)
        matched = np.clip((source[:, :, :3] - source_mean) * .86 + dest_mean, 0, 255)
        weight = (np.clip(1 - distance, 0, 1)**.72 * strength * source[:, :, 3] / 255)[..., None]
        dest[:, :, :3] += (matched - dest[:, :, :3]) * weight
    return Image.fromarray(dest.astype(np.uint8))


def mouth_open(image, wide, dead=False):
    """Shade the mouth opening between the original lip and beard pixels."""
    layer = Image.new("RGBA", SIZE)
    d = ImageDraw.Draw(layer)
    top = [(49, 121), (54, 117), (63, 116), (71, 117), (79, 115), (87, 116), (94, 119)]
    bottom = [(91, 125), (84, 131), (76, 135), (66, 136), (57, 132), (52, 128)]
    if not wide:
        top = [(x, y + 1) for x, y in top]
        bottom = [(x, round(121 + (y - 121) * .62)) for x, y in bottom]
    d.polygon(top + bottom, fill=(71, 31, 28, 229))
    d.polygon([(54, 121), (62, 119), (77, 119), (88, 119), (88, 124),
               (77, 128 if wide else 125), (63, 128 if wide else 126), (57, 126)],
              fill=(38, 17, 15, 248))
    if wide:
        d.polygon([(60, 129), (65, 128), (76, 129), (82, 127), (80, 131),
                   (73, 133), (64, 132)], fill=(137, 64, 57, 230))
    if not dead:
        d.polygon([(55, 120), (62, 118), (77, 118), (89, 118), (86, 121),
                   (78, 122), (64, 123), (58, 122)], fill=(176, 140, 108, 224))
        for x, y in ((63, 122), (68, 122), (74, 121), (80, 121), (85, 120)):
            d.line((x, y - 1, x, y), fill=(116, 80, 62, 178))
    d.line(bottom[1:-1], fill=(158, 83, 72, 170), width=1)
    return Image.alpha_composite(image, layer.filter(ImageFilter.GaussianBlur(.7)))


def yell_fire(base):
    """Separate the photographed lips and stretch the jaw beneath the opening."""
    tense = morph(base, [(56, 62, 12, 5, -2, -3, 0, 0),
                         (87, 57, 12, 5, 2, -3, 0, 0)])
    y, x = np.indices((SIZE[1], SIZE[0]), dtype=np.float32)
    seam = np.interp(x, [48, 55, 62, 70, 78, 86, 94], [121, 123, 122, 122, 120, 119, 118])
    shape = np.maximum(0, np.sin(np.pi * np.clip((x - 48) / 46, 0, 1))) ** 1.05
    upper = seam - shape * 2.6
    lower = seam + shape * 15.5
    below = np.maximum(0, y - lower)
    above = np.maximum(0, upper - y)
    sample_y = y + np.where(y > seam, -15.5 * shape * np.exp(-below / 37),
                            2.6 * shape * np.exp(-above / 13))
    px = np.asarray(tense).astype(np.float32)
    sx = x.astype(int)
    sy = np.clip(sample_y, 0, SIZE[1] - 1.01)
    y0 = sy.astype(int)
    blend = (sy - y0)[..., None]
    out = px[y0, sx] * (1 - blend) + px[y0 + 1, sx] * blend
    depth = np.clip((y - upper) / np.maximum(1, lower - upper), 0, 1)
    lip = px[np.clip(np.rint(seam).astype(int), 0, SIZE[1] - 1), sx, :3]
    cavity = lip * .24 + np.array([13, 3, 2])
    tongue = np.exp(-(((x - 71) / 11)**2 + ((depth - .81) / .15)**2))
    cavity += tongue[..., None] * np.array([36, 13, 12])
    light = np.exp(-(((x - 70) / 13)**4 + ((depth - .13) / .09)**2))
    cavity += light[..., None] * np.array([31, 21, 12])
    edge = np.clip(np.minimum(y - upper, lower - y) / 1.4, 0, 1)[..., None]
    out[:, :, :3] += (cavity - out[:, :, :3]) * edge
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8))


def expression(base, name, sun, smile):
    eyes = ((48, 74), (97, 68))
    if name.startswith("look"):
        direction = 1 if name.endswith("right") else -1
        controls = [(70, 84, 50, 72, -direction * 2.2, 0, direction * .045, 0),
                    (73, 96, 20, 22, -direction * 3.1, 0, 0, 0)]
        controls.extend((x, y, 7, 3.1, -direction * 6.5, 0, 0, 0) for x, y in eyes)
        return morph(base, controls)
    if name == "idle_blink":
        out = morph(base, [(x, y, 10, 4.2, 0, -4, 0, 1.7) for x, y in eyes])
        d = ImageDraw.Draw(out)
        for x, y in eyes:
            d.line([(x - 9, y + 1), (x - 5, y + 2), (x + 3, y + 2), (x + 9, y)],
                   fill=(90, 58, 43, 255), width=1)
        return out
    if name == "grin_rampage":
        return morph(sun, [(50, 111, 10, 8, 5, 6, -.22, 0),
                           (90, 110, 10, 8, -5, 7, -.22, 0),
                           (70, 114, 15, 7, 0, 0, -.2, -.28),
                           (46, 60, 11, 6, 0, 4, 0, 0), (94, 60, 11, 6, 0, 5, 0, 0)])
    if name == "yell_fire":
        return yell_fire(base)
    if name == "dead":
        out = morph(base, [(70, 132, 25, 12, 0, -6, .12, -.24),
                           (70, 151, 34, 21, 0, -5, 0, 0),
                           (57, 65, 13, 9, -2, 2, 0, 0),
                           (87, 60, 13, 9, 2, 2, 0, 0)])
        out = morph(out, [(x, y, 10, 4, 0, -3.4, 0, .92) for x, y in eyes])
        out = injury(mouth_open(out, False, True), 4)
        faded = ImageOps.colorize(out.convert("L"), "#242127", "#d8bd9d").convert("RGBA")
        faded.putalpha(out.getchannel("A"))
        return Image.blend(out, faded, .51).rotate(-6, Image.Resampling.BICUBIC)
    if name == "drunk_dizzy":
        out = morph(base, [(48, 74, 8, 4, -6, 3.6, 0, .17), (97, 68, 8, 4, 6, -4, 0, .38)])
        y, x = np.indices((SIZE[1], SIZE[0]))
        amount = np.zeros_like(x, dtype=float)
        for cx, cy in ((43, 92), (73, 100), (101, 92)):
            amount += np.exp(-((x - cx)**2 / 420 + (y - cy)**2 / 180)) * .27
        px = np.array(out)
        px[..., :3] = px[..., :3] * (1 - amount[..., None]) + np.array([186, 66, 47]) * amount[..., None]
        return Image.fromarray(px).rotate(6, Image.Resampling.BICUBIC)
    if name == "ouch_shock":
        out = blend_photo(base, smile, [(47, 72, 13, 6, .35), (96, 70, 13, 6, .35)])
        out = morph(out, [(x, y, 12, 4.7, 0, .4, -.07, -.31) for x, y in eyes]
                    + [(x, y - 13, 13, 4, 0, 3, 0, 0) for x, y in eyes]
                    + [(47, 96, 15, 12, -3, 0, .25, 0), (98, 93, 15, 12, 3, 0, .25, 0)])
        return out
    if name.startswith("hurt"):
        stage = int(name[-2:]) // 25
        out = morph(base, [(94, 73, 14, 7, 0, -1.5 * stage, 0, .17 * stage),
                           (52, 111, 15, 10, -1, -2 * stage, 0, 0)])
        return injury(out, stage)
    return base


def injury(image, stage):
    rng = np.random.default_rng(731)
    y, x = np.indices((SIZE[1], SIZE[0]))
    pixels = np.array(image)
    for cx, cy, rx, ry, shade, weight in (
            (100, 75, 19, 13, (63, 34, 54), .09 + .16 * stage),
            (41, 101, 13, 17, (126, 44, 39), .09 * stage),
            (70, 105, 8, 13, (130, 28, 24), .1 * stage)):
        a = np.exp(-((x - cx) / rx)**2 - ((y - cy) / ry)**2) * weight
        a *= rng.uniform(.61, 1.12, x.shape)
        pixels[..., :3] = pixels[..., :3] * (1 - a[..., None]) + np.array(shade) * a[..., None]
    image = Image.fromarray(pixels)
    d = ImageDraw.Draw(image)
    for cx, cy, width, length in [(34, 96, 4, 15), (91, 121, 5, 20),
                                   (66, 105, 4, 20), (94, 47, 7, 30)][:stage]:
        for _ in range(16 + stage * 7):
            x = int(cx + rng.normal(0, width))
            y = int(cy + rng.uniform(0, length))
            if image.getpixel((x, y))[3] > 128:
                d.point((x, y), fill=(int(rng.integers(88, 150)), 30, 22, 255))
        d.line([(cx - 3, cy), (cx + 1, cy + 5), (cx - 1, cy + length - 2)],
               fill=(110, 28, 23, 255), width=stage // 2 + 1)
        d.line((cx, cy + 4, cx - 1, cy + length - 5), fill=(166, 45, 31, 255), width=1)
    if stage >= 2:
        d.polygon([(96, 47), (115, 56), (112, 63), (93, 54)], fill=(207, 157, 112, 255))
        d.polygon([(102, 50), (109, 53), (106, 60), (99, 57)], fill=(235, 184, 135, 255))
        for point in [(97, 52), (99, 53), (111, 56), (113, 57)]:
            d.point(point, fill=(154, 98, 72, 255))
    return image


def font(size, condensed=False):
    for name in ("impact.ttf", "bahnschrift.ttf") if condensed else ("consolab.ttf", "DejaVuSansMono.ttf"):
        for path in (Path("C:/Windows/Fonts") / name, name):
            try:
                return ImageFont.truetype(str(path), size)
            except OSError:
                pass
    return ImageFont.load_default(size=size)


def wanted_art(player):
    poster = Image.new("RGBA", (128, 160), (184, 147, 98, 255))
    p = ImageDraw.Draw(poster)
    p.rectangle((4, 4, 123, 155), outline=(83, 55, 32, 255), width=2)
    p.text((64, 6), "WANTED", font=font(35, True), fill=(54, 26, 18), anchor="mt")
    portrait = ImageOps.colorize(player.convert("L"), "#372418", "#d4ac67").convert("RGBA")
    portrait.putalpha(player.getchannel("A"))
    portrait.thumbnail((88, 97), Image.Resampling.LANCZOS)
    poster.alpha_composite(portrait, ((128 - portrait.width) // 2, 41))
    p.line((12,137,115,137), fill="#865e39")
    p.text((64, 141), "HICKSTON COUNTY", font=font(14, True), fill=(54, 26, 18), anchor="mt")
    return digitize(poster,(128,160),border=False)


def make_assets(paths):
    ART.mkdir(parents=True, exist_ok=True)
    faces = [aligned(path, marks) for path, marks in zip(paths, CALIBRATION, strict=True)]
    base = faces[1]
    sheet = Image.new("RGB", (936, 786), "#1a1614")
    sd = ImageDraw.Draw(sheet)
    sd.rectangle((16, 15, 919, 81), fill="#30241d", outline="#73563a", width=2)
    sd.text((32, 23), "HICKSTON / DIGITIZED MUGSHOTS", font=font(32, True), fill="#e0bb7d")
    sd.text((33, 59), "4 PHOTO SOURCES  /  12 HUD FRAMES  /  256-COLOR PALETTE", font=font(12), fill="#c6b196")
    for i, name in enumerate(FRAMES):
        face = expression(base, name, faces[0], faces[3])
        legacy = name == "grin_rampage"
        image = digitize(face, (60, 72) if legacy else (76, 98), legacy=legacy)
        image.save(ART / f"face_{name}.png")
        x, y = 17 + i % 4 * 229, 97 + i // 4 * 229
        sd.rectangle((x, y, x + 215, y + 217), fill="#30241d", outline="#6b513d")
        sd.rectangle((x + 6, y + 6, x + 209, y + 191), fill="#201814")
        display = image.resize((152, 196), Image.Resampling.NEAREST)
        sheet.paste(display, (x + 31, y + (20 if legacy else 1)), display)
        sd.text((x + 12, y + 199), f"{i + 1:02d}  {name.upper().replace('_', ' ')}", font=font(14), fill="#e0bb7d")
    sheet.save(ROOT / "expression_sheet.png")
    from player_art import make_player

    make_player()
    PALETTE.tofile(ART / "hickston.pal")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("photos", nargs=4, type=Path, metavar="PHOTO")
    make_assets(parser.parse_args().photos)

