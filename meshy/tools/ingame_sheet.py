"""Old vs new in the game's own 3D view (a view tour's 320x156 world
pictures): each shot at the game's resolution, and a 3x crop of the body.

    python meshy/tools/ingame_sheet.py <kind> <old dir> <new dir> <out.png> [title]
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

kind, old, new, out = sys.argv[1:5]
title = sys.argv[5] if len(sys.argv) > 5 else kind
F = ImageFont.truetype("C:/Windows/Fonts/consolab.ttf", 15)
FT = ImageFont.truetype("C:/Windows/Fonts/consolab.ttf", 22)
SHOTS = [("day_idle", "day, standing"), ("day_walk", "day, mid-stride"), ("day_far", "day, a few cells off"),
         ("night_idle", "night, standing"), ("night_walk", "night, mid-stride"), ("night_far", "night, a few cells off"),
         ("day_aim", "day, aiming (gun pose)"), ("day_wind", "day, the wind-up to fire (gun pose)")]
W1, H1 = 320, 156
CROP = (100, 8, 220, 156)  # the body's middle third of the view
if kind in ("cow", "hog", "gator", "crawler", "hound"):
    CROP = (60, 8, 260, 156)  # a long animal side on: wider
cw, ch = (CROP[2] - CROP[0]) * 3, (CROP[3] - CROP[1]) * 3
row_h = max(H1 * 2 + 6, ch) + 26
width = 10 + (W1 + 10) + (cw + 10) * 2 + 10
sheet = Image.new("RGB", (width, 50 + row_h * len(SHOTS)), (22, 22, 26))
d = ImageDraw.Draw(sheet)
d.text((10, 12), title + ": left OLD above NEW at 320x156; right 3x crops OLD | NEW",
       font=FT, fill=(255, 240, 200))
y = 50
for tag, cap in SHOTS:
    po = os.path.join(old, "%s_%s_3d.png" % (kind, tag))
    pn = os.path.join(new, "%s_%s_3d.png" % (kind, tag))
    if not (os.path.exists(po) and os.path.exists(pn)):
        continue
    a = Image.open(po).convert("RGB")
    b = Image.open(pn).convert("RGB")
    d.text((10, y), cap, font=F, fill=(255, 230, 150))
    sheet.paste(a, (10, y + 22))
    sheet.paste(b, (10, y + 22 + H1 + 6))
    x = 10 + W1 + 10
    for im, lab in ((a, "OLD"), (b, "NEW")):
        c = im.crop(CROP).resize((cw, ch), Image.NEAREST)
        sheet.paste(c, (x, y + 22))
        d.text((x + 4, y + 24), lab, font=F, fill=(255, 255, 255))
        x += cw + 10
    y += row_h
# The hands close up (what they hold), at the game's own pixels x4.
HB = tuple(int(v) for v in os.environ.get("HANDS_BOX", "112,46,208,118").split(","))
hw = ((width - 70) // 6) * 2
hh = int(hw * (HB[3] - HB[1]) / (HB[2] - HB[0]))
extra = Image.new("RGB", (width, 40 + hh + 10), (22, 22, 26))
de = ImageDraw.Draw(extra)
de.text((10, 8), "HANDS close up in the game (the view's pixels enlarged): day standing, day mid-stride, night standing - OLD | NEW",
        font=F, fill=(255, 230, 150))
x = 10
for tag in ("day_idle", "day_walk", "night_idle"):
    for who, d_ in (("OLD", old), ("NEW", new)):
        pth = os.path.join(d_, "%s_%s_3d.png" % (kind, tag))
        if os.path.exists(pth) and x + hw // 2 <= width:
            c = Image.open(pth).convert("RGB").crop(HB).resize((hw // 2, hh // 2), Image.NEAREST)
            extra.paste(c, (x, 34))
            de.text((x + 3, 36), "%s %s" % (who, tag), font=F, fill=(255, 255, 255))
            x += hw // 2 + 6
    x += 8
if kind not in ("cow", "hog", "gator", "crawler", "hound"):  # (animals hold nothing)
    full = Image.new("RGB", (width, sheet.size[1] + extra.size[1]), (22, 22, 26))
    full.paste(sheet, (0, 0))
    full.paste(extra, (0, sheet.size[1]))
    sheet = full
sheet.save(out, optimize=True)
print("ingame sheet", out, sheet.size, os.path.getsize(out) // 1024, "KB")
