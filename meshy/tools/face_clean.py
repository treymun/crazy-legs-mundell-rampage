"""Kind config "face_clean": the face's front read clean and healthy.

The skin passes (skin_fix, face_lift, smooth_in) take only texels of the
skin's own colour; Meshy's stubble, grime and wrinkle shadow in a face fall
outside that test and stay as they were, so beside the lifted skin they read
as dark lilac blotches (rot, disease) and the eyes as dark slits.

Here every texel of the face's front (build_actor's FACEZONE: inside the
skull's radius, jaw to brow, ahead of the ears) is rebuilt from Meshy's own
unlit colour (its albedo bake):
- the colour is the finished skin's colour, with the albedo's own variation
  around its median kept a share (lips, eye whites, irises, brows, ruddy
  cheeks), so grey stubble becomes skin with a hint of beard;
- the light is the face's baked light (the head's no-shadow bake, else the
  finished texels, over albedo) taken through a median filter, so its
  shape stays and texel blotches go;
- the albedo's painted detail (wrinkles, grime, stubble) is kept but its
  darks are eased: light grime at most;
- the eyes (pale, grey albedo texels and the ring round them) keep their
  full contrast, the whites a little lifted: readable eyes.
Options {"detail": .55, "hue": .6, "floor": .62, "eye_lift": 1.15,
"blend": 1.0, "hair_hue": 31, "cloth_hue": 55 (albedo hues above it, up to
320, are cloth: lower it for a yellow helmet), "max_sat": off (albedo
saturation above it is cloth: a red jersey)}.

Offline try: python face_clean.py <dump.npz> <out.png> [json options].
"""
import json
import sys

import numpy

LW = numpy.array([.299, .587, .114])


def _hsv(a):
    mx, mn = a.max(axis=1), a.min(axis=1)
    d = numpy.maximum(mx - mn, 1e-6)
    sat = numpy.where(mx > 1e-4, (mx - mn) / numpy.maximum(mx, 1e-4), 0)
    r, g, b = a[:, 0], a[:, 1], a[:, 2]
    h = numpy.where(mx == r, (60 * ((g - b) / d)) % 360,
                    numpy.where(mx == g, 60 * ((b - r) / d) + 120, 60 * ((r - g) / d) + 240))
    return h, sat, mx


def _shifts(r):
    return [(dy, dx) for dy in range(-r, r + 1) for dx in range(-r, r + 1)]


def _masked_median(v, m, tex, r):
    """Median of v over the masked neighbours within r texels (v where m)."""
    img = v.reshape(tex, tex)
    mm = m.reshape(tex, tex)
    stack = []
    for dy, dx in _shifts(r):
        sv = numpy.roll(numpy.roll(img, dy, 0), dx, 1)
        sm = numpy.roll(numpy.roll(mm, dy, 0), dx, 1)
        stack.append(numpy.where(sm, sv, numpy.nan))
    out = numpy.nanmedian(numpy.stack(stack), axis=0)
    out = numpy.where(numpy.isnan(out), img, out)
    return out.reshape(-1)


def _dilate(m, tex, n):
    mm = m.reshape(tex, tex)
    for _ in range(n):
        mm = mm | numpy.roll(mm, 1, 0) | numpy.roll(mm, -1, 0) | numpy.roll(mm, 1, 1) | numpy.roll(mm, -1, 1)
    return mm.reshape(-1)


def clean(px, albedo, headzone, facezone, hand, tex, opt, lit=None, back=None, upper=None, chin=None):
    px = px.copy()
    a = numpy.clip(albedo, 0, 1)
    face = facezone & headzone & (a.max(axis=1) > .02)
    if hand is not None:
        face &= ~hand
    if face.sum() < 50:
        return px, "no face texels"
    rgb = px[:, :3]
    h, sat, mx = _hsv(a)
    # (cloth in the zone - a collar, a strap: not skin-coloured - stays)
    face &= ~((sat > .15) & (h > float(opt.get("cloth_hue", 55))) & (h < 320))
    # (a red jersey at the neck, a helmet's lining: too strong for skin)
    face &= ~(sat > float(opt.get("max_sat", 1.01)))
    # (behind the ears only the skin: not hair - yellower, or dark)
    if back is not None:
        face &= ~(back & ((h > float(opt.get("hair_hue", 31))) | (mx < .18)))
    al = numpy.maximum(a @ LW, 1e-3)
    # The finished skin's colour: the face's skin-hued, lit texels as they are.
    ph, ps, pm = _hsv(rgb)
    sk = face & (ps > .2) & (ps < .75) & ((ph < 40) | (ph > 345))
    pl = rgb @ LW
    if sk.sum() > 50:
        sk &= pl >= numpy.percentile(pl[sk], 40)
    tgt = numpy.median(rgb[sk], axis=0) if sk.sum() > 30 else numpy.median(rgb[face], axis=0)
    tl = max(float(tgt @ LW), 1e-3)
    # ("keep_white": k - white whiskers (pale grey albedo, lighter than k
    # times the face's middle) below the eye line keep their own look)
    if opt.get("keep_white"):
        med0 = float(numpy.median(al[face]))
        wh = face & (sat < .18) & (al > med0 * float(opt["keep_white"]))
        if upper is not None:
            wh &= ~upper
        face &= ~wh
    # The eyes: pale grey albedo texels (whites) and a ring round them
    # (irises, lids, lashes) keep their contrast.
    med_al = float(numpy.median(al[face]))
    whites = face & (sat < .2) & (al > med_al * float(opt.get("white_k", 1.05)))
    if upper is not None:
        whites &= upper
    # (the ring round them only where darker than the skin: irises, lids,
    # lashes - not the skin beside white whiskers)
    eyes = (whites | (_dilate(whites, tex, 2) & (al < med_al * float(opt.get("ring_k", 9.0))))) & face
    # The light: finished light over albedo, median-filtered within the face.
    # (the head's own no-shadow bake when there is one: the finished
    # texels carry the blotches)
    src = (numpy.clip(lit, 0, None) @ LW) if lit is not None and len(lit) == len(px) else pl
    shade = src / al
    shade = _masked_median(shade, face, tex, 2)
    shade = shade / max(float(numpy.median(shade[face])), 1e-4)
    shade = numpy.clip(shade, .55, 1.35)
    # The painted detail, darks eased.
    det = al / med_al
    k_d = float(opt.get("detail", .55))
    det_e = 1 + (det - 1) * k_d
    det_e = numpy.maximum(det_e, float(opt.get("floor", .62)))
    det_e = numpy.where(eyes, det, det_e)
    # The colour: the skin's chroma, the albedo's own variation a share.
    chroma = a / al[:, None]
    c_med = numpy.median(chroma[face & ~eyes], axis=0)
    k_h = float(opt.get("hue", .6))
    chroma_n = tgt / tl + (chroma - c_med) * k_h
    chroma_n = numpy.where(eyes[:, None], tgt / tl * .35 + chroma * .65, chroma_n)
    # (under the mouth pale grey paint - a face mask's bars - is skin)
    if chin is not None:
        pale = chin & (sat < .2) & (det_e > 1.0)
        det_e = numpy.where(pale, 1.0, det_e)
        chroma_n = numpy.where(pale[:, None], tgt / tl, chroma_n)
    lum_n = tl * det_e * shade
    lum_n = numpy.where(whites, lum_n * float(opt.get("eye_lift", 1.15)), lum_n)
    new = numpy.clip(chroma_n * lum_n[:, None], 0, 1)
    k_b = float(opt.get("blend", 1.0))
    rgb[face] = rgb[face] * (1 - k_b) + new[face] * k_b
    # ("paint_hue" {hue, sat, to}: texels of that colour in the upper face
    # zone painted `to` at their light - a helmet's edge painted onto the
    # forehead by Meshy, bare once the helmet is shot off)
    ph_ = opt.get("paint_hue")
    if ph_ and upper is not None:
        zone = upper & headzone & (mx > .05)
        if hand is not None:
            zone &= ~hand
        h0, h1 = ph_.get("hue", [36, 70])
        m_ = zone & (h >= h0) & (h <= h1) & (sat >= float(ph_.get("sat", .3)))
        m_ = _dilate(m_, tex, int(ph_.get("grow", 1))) & zone & ~(face & (sat < .3))
        to = numpy.array(ph_.get("to", [66, 50, 40]), dtype=float) / 255.0
        k_ = numpy.clip(al / max(float(numpy.median(al[m_])) if m_.any() else 1.0, 1e-3), .6, 1.3)
        rgb[m_] = numpy.clip(to[None, :] * k_[m_, None], 0, 1)
    px[:, :3] = rgb
    return px, "%d face texels (%d eye texels), skin %s" % (int(face.sum()), int(eyes.sum()),
                                                           numpy.round(tgt * 255).astype(int).tolist())


if __name__ == "__main__":
    from PIL import Image
    d = numpy.load(sys.argv[1])
    T = int(d["tex"])
    o = json.loads(sys.argv[3]) if len(sys.argv) > 3 else {}
    fz = d["facezone"] | (d["backzone"] if "backzone" in d.files else False)
    out, info = clean(d["total"], d["albedo"], d["headzone"], fz, d["hand"], T, o,
                      d["noshadow"] if len(d["noshadow"]) else None, d["backzone"] if "backzone" in d.files else None,
                      d["upperzone"] if "upperzone" in d.files else None,
                      d["chinzone"] if "chinzone" in d.files else None)
    print(info)
    img = numpy.clip(out[:, :3].reshape(T, T, 3), 0, 1)
    Image.fromarray((img[::-1] * 255 + .5).astype(numpy.uint8)).save(sys.argv[2])
