class_name SmoothScale
extends RefCounted

## Exact port of pygame-ce's pg.transform.smoothscale for 32-bit RGBA
## surfaces. The reference build selects the SSE2 filters
## (get_smoothscale_backend() == "SSE2"), so the fixed-point maths below is the
## SSE2 variant, not the plain C one: area averaging with 0x4000 steps for
## shrinking and two-tap 8-bit bilinear with the (n-1) endpoint mapping for
## expanding. tools/py_smooth_model.py validates this model byte-for-byte
## against the real pygame for the portrait, the item icons and the weapon
## view models.

const SSE_ONE := 0x4000


## Scale an RGBA8 buffer (sw*sh*4 bytes) to dw*dh, exactly like smoothscale.
static func rgba(src: PackedByteArray, sw: int, sh: int, dw: int, dh: int) -> PackedByteArray:
	if sw <= 0 or sh <= 0 or dw <= 0 or dh <= 0:
		return PackedByteArray()
	if sw == dw and sh == dh:
		return src.duplicate()
	var width := sw
	var current := src
	if dw != sw:
		if sh != dh:
			current = _scale_x(current, sw, sh, dw)
			width = dw
		else:
			return _scale_x(current, sw, sh, dw)
	if dh != sh:
		return _scale_y(current, width, sh, dh)
	return current.duplicate()


static func _scale_x(src: PackedByteArray, sw: int, sh: int, dw: int) -> PackedByteArray:
	if dw < sw:
		return _shrink_x(src, sw, sh, dw)
	return _expand_x(src, sw, sh, dw)


static func _scale_y(src: PackedByteArray, sw: int, sh: int, dh: int) -> PackedByteArray:
	if dh < sh:
		return _shrink_y(src, sw, sh, dh)
	return _expand_y(src, sw, sh, dh)


## filter_shrink_X_SSE2: area-average along X.
static func _shrink_x(src: PackedByteArray, sw: int, sh: int, dw: int) -> PackedByteArray:
	var xspace := SSE_ONE * sw / dw
	var xrecip := (0x40000000 / xspace) & 0xFFFF
	var out := PackedByteArray()
	out.resize(dw * sh * 4)
	var s := 0
	var d := 0
	for _y in sh:
		var acc := PackedInt32Array([0, 0, 0, 0])
		var xcounter := xspace
		for _x in sw:
			if xcounter > SSE_ONE:
				acc[0] = (acc[0] + src[s]) & 0xFFFF
				acc[1] = (acc[1] + src[s + 1]) & 0xFFFF
				acc[2] = (acc[2] + src[s + 2]) & 0xFFFF
				acc[3] = (acc[3] + src[s + 3]) & 0xFFFF
				s += 4
				xcounter -= SSE_ONE
			else:
				var xfrac := SSE_ONE - xcounter
				for k in 4:
					var value := ((((src[s + k] * 4 * xcounter) >> 16) + acc[k]) * xrecip) >> 16
					out[d + k] = 0 if value < 0 else (255 if value > 255 else value)
					acc[k] = (src[s + k] * 4 * xfrac) >> 16
				s += 4
				d += 4
				xcounter = xspace - xfrac
	return out


## filter_expand_X_SSE2: two-tap bilinear along X.
static func _expand_x(src: PackedByteArray, sw: int, sh: int, dw: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(dw * sh * 4)
	var idx := PackedInt32Array()
	idx.resize(dw)
	var m0 := PackedInt32Array()
	m0.resize(dw)
	var m1 := PackedInt32Array()
	m1.resize(dw)
	for x in dw:
		idx[x] = x * (sw - 1) / dw
		m1[x] = 0x100 * ((x * (sw - 1)) % dw) / dw
		m0[x] = 0x100 - m1[x]
	var s := 0
	var d := 0
	for _y in sh:
		for x in dw:
			var a := s + idx[x] * 4
			var w0 := m0[x]
			var w1 := m1[x]
			for k in 4:
				var value := (src[a + k] * w0 + src[a + 4 + k] * w1) >> 8
				out[d + k] = 0 if value < 0 else (255 if value > 255 else value)
			d += 4
		s += sw * 4
	return out


## filter_shrink_Y_SSE2: area-average along Y over an accumulator line.
static func _shrink_y(src: PackedByteArray, sw: int, sh: int, dh: int) -> PackedByteArray:
	var yspace := SSE_ONE * sh / dh
	var yrecip := (0x40000000 / yspace) & 0xFFFF
	var out := PackedByteArray()
	out.resize(sw * dh * 4)
	var acc := PackedInt32Array()
	acc.resize(sw * 4)
	acc.fill(0)
	var stride := sw * 4
	var ycounter := yspace
	var s := 0
	var d := 0
	for _y in sh:
		if ycounter > SSE_ONE:
			for k in stride:
				acc[k] = (acc[k] + src[s + k]) & 0xFFFF
			s += stride
			ycounter -= SSE_ONE
		else:
			var yfrac := SSE_ONE - ycounter
			for k in stride:
				var value := ((((src[s + k] * 4 * ycounter) >> 16) + acc[k]) * yrecip) >> 16
				out[d + k] = 0 if value < 0 else (255 if value > 255 else value)
				acc[k] = (src[s + k] * 4 * yfrac) >> 16
			s += stride
			d += stride
			ycounter = yspace - yfrac
	return out


## filter_expand_Y_SSE2: two-tap bilinear along Y.
static func _expand_y(src: PackedByteArray, sw: int, sh: int, dh: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(sw * dh * 4)
	var stride := sw * 4
	for y in dh:
		var yidx0 := y * (sh - 1) / dh
		var y1 := 0x100 * ((y * (sh - 1)) % dh) / dh
		var y0 := 0x100 - y1
		var a := yidx0 * stride
		var b := a + stride
		var d := y * stride
		for k in stride:
			var value := (src[a + k] * y0 + src[b + k] * y1) >> 8
			out[d + k] = 0 if value < 0 else (255 if value > 255 else value)
	return out
