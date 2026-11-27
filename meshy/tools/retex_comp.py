"""tex_comp.py <polys.json> <orig.png> <retex.png> <out.png>: original texture inside the UV polygons, the retexture elsewhere."""
import json, sys
from PIL import Image, ImageDraw, ImageFilter
polys = json.load(open(sys.argv[1]))
O = Image.open(sys.argv[2]).convert("RGB"); R = Image.open(sys.argv[3]).convert("RGB")
W, H = O.size
mask = Image.new("L", (W, H), 0); d = ImageDraw.Draw(mask)
for _bi, pl in polys:
    d.polygon([(u * W, (1 - v) * H) for u, v in pl], fill=255)
mask = mask.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(1.5))
Image.composite(O, R, mask).save(sys.argv[4])
mask.save(sys.argv[4].replace(".png", "_mask.png"))
print("comp", len(polys))
