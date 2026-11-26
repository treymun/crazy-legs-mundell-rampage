"""Lay out preview sheets from tiles.

    python meshy/tools/sheets.py make <tiles dir> <kind> <out.png> <title> [keys]
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont


def font(size):
    for f in ("C:/Windows/Fonts/consolab.ttf", "C:/Windows/Fonts/arialbd.ttf"):
        if os.path.exists(f):
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def label(im, text, size=16, at=(6, 4), fill=(255, 240, 200)):
    d = ImageDraw.Draw(im)
    d.text((at[0] + 1, at[1] + 1), text, font=font(size), fill=(0, 0, 0))
    d.text(at, text, font=font(size), fill=fill)


def make(tiles, kind, out, title, keys):
    def tile(name):
        p = os.path.join(tiles, "%s_%s.png" % (kind, name))
        return Image.open(p).convert("RGB") if os.path.exists(p) else None

    rows = []
    for who, cap in (("old", "OLD model (current game)"), ("new", "NEW Meshy model")):
        ims = [tile("%s_%s" % (who, v)) for v in ("front", "three", "side", "back")]
        rows.append((cap + ": standing key, front / three-quarter / side / back", ims))
    rig = [tile("rig_front"), tile("rig_side")]
    keyrow_old = [tile("old_key_" + k) for k in keys]
    keyrow_new = [tile("new_key_" + k) for k in keys]
    tw, th = 360, 440
    sc = .62
    tw2, th2 = int(tw * sc), int(th * sc)
    width = max(4 * tw, 2 * tw + 10, len(keys) * tw2) + 20
    height = 60 + 2 * (th + 30) + (th + 30) + 2 * (th2 + 30) + 20
    sheet = Image.new("RGB", (width, height), (24, 24, 28))
    label(sheet, title, 24, (10, 12))
    y = 56
    for cap, ims in rows:
        label(sheet, cap, 16, (10, y))
        y += 24
        for i, im in enumerate(ims):
            if im:
                sheet.paste(im, (10 + i * tw, y))
        y += th + 6
    label(sheet, "NEW: A-pose rest, its bones (orange) and ragdoll points (yellow); gear bones cyan (the gun, held at the standing key)", 16, (10, y))
    y += 24
    for i, im in enumerate(rig):
        if im:
            sheet.paste(im, (10 + i * tw, y))
    y += th + 6
    for cap, ims in (("OLD keys: " + ", ".join(keys), keyrow_old), ("NEW keys (retargeted from the old keys)", keyrow_new)):
        label(sheet, cap, 16, (10, y))
        y += 24
        for i, im in enumerate(ims):
            if im:
                sheet.paste(im.resize((tw2, th2), Image.LANCZOS), (10 + i * tw2, y))
                label(sheet, keys[i], 13, (14 + i * tw2, y + 2))
        y += th2 + 6
    sheet.save(out, optimize=True)
    print("sheet", out, sheet.size, os.path.getsize(out) // 1024, "KB")


if __name__ == "__main__":
    if sys.argv[1] == "make":
        keys = sys.argv[6].split(",") if len(sys.argv) > 6 else []
        make(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], keys)
