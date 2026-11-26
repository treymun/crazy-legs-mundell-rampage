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
         ("night_idle", "night, standing"), ("night_walk", "night, mid-stride"), ("night_far", "night, a few cells off")]
W1, H1 = 320, 156
CROP = (100, 8, 220, 156)  # the body's middle third of the view
cw, ch = (CROP[2] - CROP[0]) * 3, (CROP[3] - CROP[1]) * 3
row_h = max(H1 * 2 + 6, ch) + 26
width = 10 + (W1 + 10) + (cw + 10) * 2 + 10
sheet = Image.new("RGB", (width, 50 + row_h * len(SHOTS)), (22, 22, 26))
d = ImageDraw.Draw(sheet)
d.text((10, 12), title + "  -  left column: OLD above, NEW below at 320x156 (the game's view); right: 3x crops OLD | NEW",
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
sheet.save(out, optimize=True)
print("ingame sheet", out, sheet.size, os.path.getsize(out) // 1024, "KB")
