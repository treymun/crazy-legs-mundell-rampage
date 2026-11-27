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
# (kind config "gear_even": {to [r,g,b], hue [lo,hi], sat_min, val_min,
# smooth px, keep_light k} - opt-in: the old gear's speckled texels of that
# hue (old low-res brass dithered into yellow noise; "pale_reds") set to one colour at
# their own light, the light itself box-smoothed over the gear's texels;
# other hues (a red valve wheel, dark bands) stay)
_kc = os.path.join("meshy", "kinds", kind + ".json")
GE = __import__("json").load(open(_kc)).get("gear_even") if os.path.exists(_kc) else None


def even(g):
    if not GE:
        return g
    a = g.astype(float) / 255.0
    mx, mn = a.max(axis=2), a.min(axis=2)
    d = numpy.maximum(mx - mn, 1e-6)
    r_, g_, b_ = a[..., 0], a[..., 1], a[..., 2]
    h = numpy.where(mx == r_, (60 * ((g_ - b_) / d)) % 360,
                    numpy.where(mx == g_, 60 * ((b_ - r_) / d) + 120, 60 * ((r_ - g_) / d) + 240))
    sat = numpy.where(mx > 1e-4, (mx - mn) / numpy.maximum(mx, 1e-4), 0)
    lo, hi = GE.get("hue", [18, 62])
    sel = mask & (h >= lo) & (h <= hi) & (sat >= float(GE.get("sat_min", .2))) & (mx >= float(GE.get("val_min", .15)))
    # ("pale_reds": sat - pinkish specks (reddish hue below "hue", paler than
    # that saturation) taken too; a saturated red wheel stays)
    if GE.get("pale_reds"):
        sel |= mask & ((h < lo) | (h > 330)) & (sat < float(GE["pale_reds"])) & (mx >= float(GE.get("val_min", .15)))
    # ("specks": n - any other gear texel with at least n of its 8 neighbours
    # taken is a speck inside the brass and taken too, twice over)
    if GE.get("specks"):
        for _ in range(2):
            nb = sum(numpy.roll(numpy.roll(sel, dy, 0), dx, 1).astype(int)
                     for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx)
            sel = sel | (mask & (nb >= int(GE["specks"])) & (mx >= float(GE.get("val_min", .15))))
    lw = numpy.array([.299, .587, .114])
    lum = a @ lw
    n = int(GE.get("smooth", 2))
    acc = numpy.zeros_like(lum)
    cnt = numpy.zeros_like(lum)
    for dy in range(-n, n + 1):
        for dx in range(-n, n + 1):
            m2 = numpy.roll(numpy.roll(sel, dy, 0), dx, 1)
            acc += numpy.where(m2, numpy.roll(numpy.roll(lum, dy, 0), dx, 1), 0)
            cnt += m2
    ls = numpy.where(cnt > 0, acc / numpy.maximum(cnt, 1), lum)
    to = numpy.array(GE["to"], float) / 255.0
    k = ls / max(float(to @ lw), 1e-4) * float(GE.get("keep_light", 1.0))
    out = a.copy()
    out[sel] = numpy.clip(to[None, :] * k[sel, None], 0, 1)
    print("gear texels evened:", int(sel.sum()))
    return (out * 255 + .5).astype(numpy.uint8)


gear0 = even(gear0)
for look in ("", "_hurt", "_p2", "_p3"):
    p = os.path.join("assets", "art", "actor3d_%s%s.png" % (kind, look))
    if not os.path.exists(p):
        continue
    # (a boss's phase looks have the old phase looks' gear texels)
    gp = os.path.join(raw, kind + "_gear" + look + ".png")
    gear = even(numpy.asarray(Image.open(gp).convert("RGB"))) if look and os.path.exists(gp) else gear0
    im = Image.open(p).convert("RGBA")
    a = numpy.array(im)
    a[mask, :3] = gear[mask]
    Image.fromarray(a).save(p)
    print("gear texels pasted:", p, int(mask.sum()))
