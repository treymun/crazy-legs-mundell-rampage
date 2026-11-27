"""Zoom into a live_frames strip (3 lines of 5 frames, 320x200 each): the
body's area of each moment, enlarged, in one row (or two).

    python meshy/tools/strip_zoom.py <strip.png> <out.png> [x0 y0 x1 y1] [frames]
"""
import sys

from PIL import Image

src, out = sys.argv[1], sys.argv[2]
box = tuple(int(v) for v in sys.argv[3:7]) if len(sys.argv) > 6 else (60, 20, 260, 190)
frames = [int(v) for v in sys.argv[7].split(",")] if len(sys.argv) > 7 else list(range(15))
im = Image.open(src).convert("RGB")
fw, fh = im.size[0] // 5, im.size[1] // 3
k = 2
tiles = []
for f in frames:
    x, y = (f % 5) * fw, (f // 5) * fh
    t = im.crop((x + box[0], y + box[1], x + box[2], y + box[3]))
    tiles.append(t.resize((t.size[0] * k, t.size[1] * k), Image.NEAREST))
per = 8
rows = (len(tiles) + per - 1) // per
w, h = tiles[0].size
sheet = Image.new("RGB", (min(per, len(tiles)) * w, rows * h))
for i, t in enumerate(tiles):
    sheet.paste(t, ((i % per) * w, (i // per) * h))
sheet.save(out)
