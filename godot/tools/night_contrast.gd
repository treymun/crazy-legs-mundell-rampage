## How well a figure reads against what it stands in front of: two pictures
## of one view, with the figure and without it. The 3D view's pictures
## (320x156, no grain) say which pixels are the figure (any channel more than
## MASK apart); the finished frames (palette, dither, grain) say what the
## player sees there. Lightness is CIE L* (0 black to 100 white), which follows
## the eye: ten L* in the dark reads as plainly as ten in the light.
## Used by night_frames.gd (the audit) and compare_3d.gd (the floor on the
## tour's `contrast` viewpoints).
extends RefCounted

const MASK := 3.0


static func lightness(c: Color) -> float:
	var y := 0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b)
	return 116.0 * pow(y, 1.0 / 3.0) - 16.0 if y > 0.008856 else 903.3 * y


static func _linear(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)


## {px, foe, behind, delta}: the figure's pixels, its mean L*, the mean L* of
## what it hides, and the mean |dL*| pixel by pixel. `with`/`bare` are the 3D
## view's pictures; `with_frame`/`bare_frame` the finished frames (any size:
## the 320x200 picture fitted 4:3 in the middle, the view its top 156 rows),
## or null to measure the 3D pictures themselves.
static func measure(with: Image, bare: Image, with_frame: Image, bare_frame: Image) -> Dictionary:
	var count := 0
	var foe := 0.0
	var behind := 0.0
	var delta := 0.0
	var w := with.get_width()
	var h := with.get_height()
	var fw := 0
	var fh := 0
	var sy := 1.0
	var sx := 1.0
	var ox := 0.0
	if with_frame != null:
		fw = with_frame.get_width()
		fh = with_frame.get_height()
		sy = fh / 200.0
		sx = minf(fh * 4.0 / 3.0, fw) / 320.0
		ox = (fw - 320.0 * sx) * .5
	for y in h:
		for x in w:
			var a := with.get_pixel(x, y)
			var b := bare.get_pixel(x, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) * 255.0 < MASK:
				continue
			if with_frame != null:
				var fx := clampi(int(ox + (x + .5) * 320.0 / w * sx), 0, fw - 1)
				var fy := clampi(int((y + .5) * 156.0 / h * sy), 0, fh - 1)
				a = with_frame.get_pixel(fx, fy)
				b = bare_frame.get_pixel(fx, fy)
			var la := lightness(a)
			var lb := lightness(b)
			count += 1
			foe += la
			behind += lb
			delta += absf(la - lb)
	var n := maxf(count, 1.0)
	return {"px": count, "foe": foe / n, "behind": behind / n, "delta": delta / n}
