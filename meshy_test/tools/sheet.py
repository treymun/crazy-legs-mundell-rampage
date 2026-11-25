import sys
from PIL import Image
out, files = sys.argv[1], sys.argv[2:]
ims = [Image.open(f).convert("RGB") for f in files]
h = max(i.height for i in ims)
c = Image.new("RGB", (sum(i.width for i in ims), h), (40, 40, 44))
x = 0
for i in ims:
    c.paste(i, (x, 0)); x += i.width
c.save(out)
