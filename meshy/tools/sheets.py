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
    hand_keys = [k for k in ("0", "w1", "aim", "fire") if tile("new_hands_%s_front" % k)]
    tw, th = 360, 440
    sc = .62
    tw2, th2 = int(tw * sc), int(th * sc)
    width = max(4 * tw, 2 * tw + 10, len(keys) * tw2, len(hand_keys) * (2 * 194 + 10), 8 * 184 + 40) + 20
    hs = 190
    gun_keys = [k for k in ("0", "w1", "aim", "fire") if tile("gun_%s_front" % k)]
    gw, gh = int(tw * .5), int(th * .5)
    height = (60 + 2 * (th + 30) + (th + 30) + 2 * (th2 + 30) + 20 + (2 * hs + 60 if hand_keys else 0)
              + (gh + 40 if gun_keys else 0))
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
    if gun_keys:
        names = {"0": "carry", "w1": "walk", "aim": "aim", "fire": "fire (recoil)"}
        label(sheet, "GUN POSES (new): " + ", ".join(names[k] for k in gun_keys) + " - front and side each", 16, (10, y))
        y += 24
        x = 10
        for k in gun_keys:
            for v in ("front", "side"):
                im = tile("gun_%s_%s" % (k, v))
                if im:
                    sheet.paste(im.resize((gw, gh), Image.LANCZOS), (x, y))
                    label(sheet, "%s %s" % (names[k], v), 12, (x + 3, y + 2))
                x += gw + 4
            x += 8
        y += gh + 16
    if hand_keys:
        label(sheet, "HANDS close up (what they hold): " + ", ".join("key " + k for k in hand_keys)
              + " - each key front and side; NEW above, OLD below", 16, (10, y))
        y += 24
        for row, who in enumerate(("new", "old")):
            x = 10
            for k in hand_keys:
                for v in ("front", "side"):
                    im = tile("%s_hands_%s_%s" % (who, k, v))
                    if im:
                        sheet.paste(im.resize((hs, hs), Image.LANCZOS), (x, y))
                        label(sheet, "%s %s %s" % (who.upper(), k, v), 12, (x + 3, y + 2))
                    x += hs + 4
                x += 10
            y += hs + 6
    sheet.save(out, optimize=True)
    print("sheet", out, sheet.size, os.path.getsize(out) // 1024, "KB")


if __name__ == "__main__":
    if sys.argv[1] == "make":
        keys = sys.argv[6].split(",") if len(sys.argv) > 6 else []
        make(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], keys)
