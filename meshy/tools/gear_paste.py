"""After build_actor_meshes.gd grades a Meshy actor's looks: put the gear's
texels back as the old look had them (they were copied from the old, already
graded look; grading them twice would darken them).

    python meshy/tools/gear_paste.py <raw dir> <kind>
"""
import os
import sys

import numpy
from PIL import Image

raw, kind = sys.argv[1], sys.argv[2]
mask_p = os.path.join(raw, kind + "_gearmask.png")
if not os.path.exists(mask_p):
    sys.exit(0)
mask = numpy.asarray(Image.open(mask_p).convert("L")) > 127
gear0 = numpy.asarray(Image.open(os.path.join(raw, kind + "_gear.png")).convert("RGB"))
for look in ("", "_hurt", "_p2", "_p3"):
    p = os.path.join("assets", "art", "actor3d_%s%s.png" % (kind, look))
    if not os.path.exists(p):
        continue
    # (a boss's phase looks have the old phase looks' gear texels)
    gp = os.path.join(raw, kind + "_gear" + look + ".png")
    gear = numpy.asarray(Image.open(gp).convert("RGB")) if look and os.path.exists(gp) else gear0
    im = Image.open(p).convert("RGBA")
    a = numpy.array(im)
    a[mask, :3] = gear[mask]
    Image.fromarray(a).save(p)
    print("gear texels pasted:", p, int(mask.sum()))
