## Drawing for the art tools (tools/art/*.gd), in plain GDScript with no window:
## the shapes Pillow's ImageDraw gave the old Python builders (filled polygons,
## ellipses, rectangles, rounded rectangles, thick lines, arcs, pie slices,
## points), the filters they used (Gaussian blur, a 3x3 minimum, unsharp mask,
## colour, contrast and brightness), seeded noise, and the digitize pass that
## commits a picture to the game's VGA palette.
##
## A Sheet is RGBA bytes. Shapes replace pixels (no blending), as ImageDraw
## does; coordinates follow ImageDraw's: a box (x0, y0, x1, y1) includes its
## right and bottom edges, and a pixel is in a shape when its centre is.
## Nothing here matches Pillow bit for bit (its random numbers and resampling
## are its own), so a rebuilt picture has the same look, not the same bytes.
extends RefCounted

const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]


class Sheet:
	var w := 0
	var h := 0
	var data := PackedByteArray()

	func _init(p_w := 1, p_h := 1, fill := Color(0, 0, 0, 0)) -> void:
		w = p_w
		h = p_h
		data.resize(w * h * 4)
		if fill.a > 0.0 or fill.r > 0.0 or fill.g > 0.0 or fill.b > 0.0:
			var px := PackedByteArray([fill.r8, fill.g8, fill.b8, fill.a8])
			for i in w * h:
				data[i * 4] = px[0]
				data[i * 4 + 1] = px[1]
				data[i * 4 + 2] = px[2]
				data[i * 4 + 3] = px[3]

	static func from_image(image: Image) -> Sheet:
		var copy := image.duplicate() as Image
		copy.convert(Image.FORMAT_RGBA8)
		var sheet := Sheet.new(copy.get_width(), copy.get_height())
		sheet.data = copy.get_data()
		return sheet

	static func load_png(path: String) -> Sheet:
		var image := Image.load_from_file(path)
		return Sheet.from_image(image) if image != null else null

	func to_image() -> Image:
		return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)

	func save(path: String) -> void:
		var error := to_image().save_png(path)
		if error != OK:
			push_error("cannot write %s (error %d)" % [path, error])

	func duplicate_sheet() -> Sheet:
		var copy := Sheet.new(w, h)
		copy.data = data.duplicate()
		return copy

	func put(x: int, y: int, c: Color) -> void:
		if x < 0 or y < 0 or x >= w or y >= h:
			return
		var o := (y * w + x) * 4
		data[o] = c.r8
		data[o + 1] = c.g8
		data[o + 2] = c.b8
		data[o + 3] = c.a8

	func alpha_at(x: int, y: int) -> int:
		return data[(y * w + x) * 4 + 3]

	## Resampled to a new size as Pillow does it: Lanczos (or bicubic) with the
	## filter widened when shrinking, on premultiplied alpha.
	func resized(nw: int, nh: int, mode := Image.INTERPOLATE_LANCZOS) -> Sheet:
		var floats := PackedFloat32Array()
		floats.resize(w * h * 4)
		for i in w * h:
			var a := data[i * 4 + 3] / 255.0
			for k in 3:
				floats[i * 4 + k] = data[i * 4 + k] * a
			floats[i * 4 + 3] = data[i * 4 + 3]
		var cubic := mode == Image.INTERPOLATE_CUBIC
		var out_f := resample(floats, w, h, 4, nw, nh, cubic)
		var out := Sheet.new(nw, nh)
		for i in nw * nh:
			var a := clampf(out_f[i * 4 + 3], 0.0, 255.0)
			for k in 3:
				var v := out_f[i * 4 + k] / (a / 255.0) if a > 0.0 else 0.0
				out.data[i * 4 + k] = clampi(roundi(v), 0, 255)
			out.data[i * 4 + 3] = roundi(a)
		return out

	## Separable resampling of `channels`-channel floats (Pillow's ImagingResample):
	## each output pixel weighs the input over the filter's reach, which grows with
	## the shrink so nothing thin is skipped.
	static func resample(
		values: PackedFloat32Array, w: int, h: int, channels: int, nw: int, nh: int, cubic := false
	) -> PackedFloat32Array:
		var across := _pass(values, w, h, channels, nw, true, cubic)
		return _pass(across, nw, h, channels, nh, false, cubic)

	static func _kernel(x: float, cubic: bool) -> float:
		x = absf(x)
		if cubic:
			# Pillow's bicubic, a = -0.5.
			if x < 1.0:
				return (1.5 * x - 2.5) * x * x + 1.0
			if x < 2.0:
				return ((-.5 * x + 2.5) * x - 4.0) * x + 2.0
			return 0.0
		if x >= 3.0:
			return 0.0
		if x < 1e-8:
			return 1.0
		return sin(PI * x) * sin(PI * x / 3.0) / (PI * PI * x * x / 3.0)

	## One direction of resample(): along rows (`across`) or down columns.
	static func _pass(
		values: PackedFloat32Array,
		w: int,
		h: int,
		channels: int,
		size: int,
		across: bool,
		cubic: bool
	) -> PackedFloat32Array:
		var length := w if across else h
		var scale := float(length) / size
		var filterscale := maxf(scale, 1.0)
		var support := (2.0 if cubic else 3.0) * filterscale
		var starts := PackedInt32Array()
		var counts := PackedInt32Array()
		var weights: Array[PackedFloat32Array] = []
		for o in size:
			var centre := (o + .5) * scale
			var lo := maxi(0, int(centre - support + .5))
			var hi := mini(length, int(centre + support + .5))
			var ws := PackedFloat32Array()
			var total := 0.0
			for i in range(lo, hi):
				var wv := _kernel((i - centre + .5) / filterscale, cubic)
				ws.append(wv)
				total += wv
			for k in ws.size():
				ws[k] /= total if total != 0.0 else 1.0
			starts.append(lo)
			counts.append(ws.size())
			weights.append(ws)
		var ow := size if across else w
		var oh := h if across else size
		var out := PackedFloat32Array()
		out.resize(ow * oh * channels)
		for y in oh:
			for x in ow:
				var o := x if across else y
				var ws: PackedFloat32Array = weights[o]
				var lo := starts[o]
				for c in channels:
					var sum := 0.0
					for k in counts[o]:
						var src := (
							(y * w + lo + k) * channels + c
							if across
							else ((lo + k) * w + x) * channels + c
						)
						sum += values[src] * ws[k]
					out[(y * ow + x) * channels + c] = sum
		return out

	## Another sheet over this one at x, y, by its alpha (Pillow alpha_composite).
	func composite(top: Sheet, x := 0, y := 0) -> void:
		for ty in top.h:
			var sy := y + ty
			if sy < 0 or sy >= h:
				continue
			for tx in top.w:
				var sx := x + tx
				if sx < 0 or sx >= w:
					continue
				var t := (ty * top.w + tx) * 4
				var a := top.data[t + 3] / 255.0
				if a <= 0.0:
					continue
				var o := (sy * w + sx) * 4
				var b := data[o + 3] / 255.0
				var out_a := a + b * (1.0 - a)
				for k in 3:
					var c := (top.data[t + k] * a + data[o + k] * b * (1.0 - a)) / maxf(out_a, 1e-6)
					data[o + k] = clampi(roundi(c), 0, 255)
				data[o + 3] = clampi(roundi(out_a * 255.0), 0, 255)

	## Pasted as it is (no blending), as Image.paste without a mask.
	func paste(top: Sheet, x := 0, y := 0) -> void:
		for ty in top.h:
			var sy := y + ty
			if sy < 0 or sy >= h:
				continue
			for tx in top.w:
				var sx := x + tx
				if sx >= 0 and sx < w:
					var t := (ty * top.w + tx) * 4
					var o := (sy * w + sx) * 4
					for k in 4:
						data[o + k] = top.data[t + k]

	## The smallest box holding every pixel whose alpha passes `above`.
	func bbox(above := 0) -> Rect2i:
		var x0 := w
		var y0 := h
		var x1 := -1
		var y1 := -1
		for y in h:
			for x in w:
				if data[(y * w + x) * 4 + 3] > above:
					x0 = mini(x0, x)
					y0 = mini(y0, y)
					x1 = maxi(x1, x)
					y1 = maxi(y1, y)
		return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1) if x1 >= 0 else Rect2i(0, 0, 0, 0)

	func cropped(r: Rect2i) -> Sheet:
		var out := Sheet.new(maxi(1, r.size.x), maxi(1, r.size.y))
		for y in out.h:
			for x in out.w:
				var sx := r.position.x + x
				var sy := r.position.y + y
				if sx >= 0 and sy >= 0 and sx < w and sy < h:
					var o := (sy * w + sx) * 4
					var t := (y * out.w + x) * 4
					for k in 4:
						out.data[t + k] = data[o + k]
		return out

	func mirrored() -> Sheet:
		var out := Sheet.new(w, h)
		for y in h:
			for x in w:
				var o := (y * w + x) * 4
				var t := (y * w + (w - 1 - x)) * 4
				for k in 4:
					out.data[t + k] = data[o + k]
		return out


# ----------------------------------------------------------------- shapes


static func rect(s: Sheet, x0: float, y0: float, x1: float, y1: float, c: Color) -> void:
	for y in range(maxi(0, ceili(y0 - .5)), mini(s.h, floori(y1 + .5) + 1)):
		for x in range(maxi(0, ceili(x0 - .5)), mini(s.w, floori(x1 + .5) + 1)):
			s.put(x, y, c)


static func outline(s: Sheet, x0: float, y0: float, x1: float, y1: float, c: Color) -> void:
	rect(s, x0, y0, x1, y0, c)
	rect(s, x0, y1, x1, y1, c)
	rect(s, x0, y0, x0, y1, c)
	rect(s, x1, y0, x1, y1, c)


static func point(s: Sheet, x: float, y: float, c: Color) -> void:
	s.put(int(x), int(y), c)


## Inside the ellipse of the box (edges included, as ImageDraw.ellipse).
static func _in_ellipse(px: float, py: float, x0: float, y0: float, x1: float, y1: float) -> float:
	var rx := (x1 - x0 + 1.0) * .5
	var ry := (y1 - y0 + 1.0) * .5
	var dx := (px - (x0 + rx)) / maxf(rx, .01)
	var dy := (py - (y0 + ry)) / maxf(ry, .01)
	return dx * dx + dy * dy


static func ellipse(s: Sheet, x0: float, y0: float, x1: float, y1: float, c: Color) -> void:
	for y in range(maxi(0, floori(y0)), mini(s.h, ceili(y1) + 1)):
		for x in range(maxi(0, floori(x0)), mini(s.w, ceili(x1) + 1)):
			if _in_ellipse(x + .5, y + .5, x0, y0, x1, y1) <= 1.0:
				s.put(x, y, c)


## Angles in degrees, clockwise from three o'clock (y grows down), measured
## round the ellipse's own shape (its parameter), as ImageDraw does.
static func _in_span(
	px: float, py: float, cx: float, cy: float, rx: float, ry: float, start: float, end: float
) -> bool:
	var a := fposmod(rad_to_deg(atan2((py - cy) / maxf(ry, .01), (px - cx) / maxf(rx, .01))), 360.0)
	var s0 := fposmod(start, 360.0)
	var e0 := fposmod(end, 360.0)
	if end - start >= 360.0:
		return true
	return (a >= s0 and a <= e0) if s0 <= e0 else (a >= s0 or a <= e0)


static func pieslice(
	s: Sheet, x0: float, y0: float, x1: float, y1: float, start: float, end: float, c: Color
) -> void:
	var cx := (x0 + x1 + 1.0) * .5
	var cy := (y0 + y1 + 1.0) * .5
	for y in range(maxi(0, floori(y0)), mini(s.h, ceili(y1) + 1)):
		for x in range(maxi(0, floori(x0)), mini(s.w, ceili(x1) + 1)):
			if (
				_in_ellipse(x + .5, y + .5, x0, y0, x1, y1) <= 1.0
				and _in_span(
					x + .5, y + .5, cx, cy, (x1 - x0 + 1) * .5, (y1 - y0 + 1) * .5, start, end
				)
			):
				s.put(x, y, c)


## The ring of the ellipse `width` pixels thick, between the two angles.
static func arc(
	s: Sheet,
	x0: float,
	y0: float,
	x1: float,
	y1: float,
	start: float,
	end: float,
	c: Color,
	width := 1.0
) -> void:
	var cx := (x0 + x1 + 1.0) * .5
	var cy := (y0 + y1 + 1.0) * .5
	for y in range(maxi(0, floori(y0)), mini(s.h, ceili(y1) + 1)):
		for x in range(maxi(0, floori(x0)), mini(s.w, ceili(x1) + 1)):
			var px := x + .5
			var py := y + .5
			if (
				_in_ellipse(px, py, x0, y0, x1, y1) <= 1.0
				and _in_ellipse(px, py, x0 + width, y0 + width, x1 - width, y1 - width) > 1.0
				and _in_span(px, py, cx, cy, (x1 - x0 + 1) * .5, (y1 - y0 + 1) * .5, start, end)
			):
				s.put(x, y, c)


static func rounded_rect(
	s: Sheet, x0: float, y0: float, x1: float, y1: float, radius: float, c: Color
) -> void:
	var r := minf(radius, minf((x1 - x0) * .5, (y1 - y0) * .5))
	for y in range(maxi(0, floori(y0)), mini(s.h, ceili(y1) + 1)):
		for x in range(maxi(0, floori(x0)), mini(s.w, ceili(x1) + 1)):
			var px := clampf(x + .5, x0 + r, x1 + 1.0 - r)
			var py := clampf(y + .5, y0 + r, y1 + 1.0 - r)
			if Vector2(x + .5 - px, y + .5 - py).length() <= r + .001:
				s.put(x, y, c)


## A filled polygon (even-odd, by pixel centres), as ImageDraw.polygon.
static func polygon(s: Sheet, pts: PackedVector2Array, c: Color) -> void:
	if pts.size() < 3:
		return
	var top := INF
	var bottom := -INF
	for p in pts:
		top = minf(top, p.y)
		bottom = maxf(bottom, p.y)
	for y in range(maxi(0, floori(top)), mini(s.h, ceili(bottom) + 1)):
		var fy := y + .5
		var xs: Array[float] = []
		for i in pts.size():
			var a := pts[i]
			var b := pts[(i + 1) % pts.size()]
			if (a.y <= fy and b.y > fy) or (b.y <= fy and a.y > fy):
				xs.append(a.x + (fy - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		for k in range(0, xs.size() - 1, 2):
			for x in range(maxi(0, ceili(xs[k] - .5)), mini(s.w, floori(xs[k + 1] - .5) + 1)):
				s.put(x, y, c)


## A line through the points; wider than one pixel it is a band, with round
## joints when `round_joints` (ImageDraw's joint="curve").
static func line(
	s: Sheet, pts: PackedVector2Array, c: Color, width := 1.0, round_joints := false
) -> void:
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		if width <= 1.0:
			var steps := maxi(1, ceili(maxf(absf(b.x - a.x), absf(b.y - a.y))))
			for k in steps + 1:
				var p := a.lerp(b, float(k) / steps)
				s.put(roundi(p.x), roundi(p.y), c)
			continue
		var along := (b - a).normalized() if a != b else Vector2.RIGHT
		var side := Vector2(-along.y, along.x) * width * .5
		polygon(s, PackedVector2Array([a + side, b + side, b - side, a - side]), c)
		if round_joints and i > 0:
			var r := width * .5
			ellipse(s, a.x - r, a.y - r, a.x + r - 1.0, a.y + r - 1.0, c)


static func line2(
	s: Sheet, x0: float, y0: float, x1: float, y1: float, c: Color, width := 1.0
) -> void:
	line(s, PackedVector2Array([Vector2(x0, y0), Vector2(x1, y1)]), c, width)


# ---------------------------------------------------------------- filters


## Gaussian blur of one channel (values w*h), sigma `radius` (Pillow's radius).
static func blur(values: PackedFloat32Array, w: int, h: int, radius: float) -> PackedFloat32Array:
	var reach := maxi(1, ceili(radius * 3.0))
	var kernel := PackedFloat32Array()
	var total := 0.0
	for k in range(-reach, reach + 1):
		var v := exp(-float(k * k) / (2.0 * radius * radius))
		kernel.append(v)
		total += v
	for k in kernel.size():
		kernel[k] /= total
	var across := PackedFloat32Array()
	across.resize(w * h)
	for y in h:
		for x in w:
			var sum := 0.0
			for k in kernel.size():
				sum += values[y * w + clampi(x + k - reach, 0, w - 1)] * kernel[k]
			across[y * w + x] = sum
	var out := PackedFloat32Array()
	out.resize(w * h)
	for y in h:
		for x in w:
			var sum := 0.0
			for k in kernel.size():
				sum += across[clampi(y + k - reach, 0, h - 1) * w + x] * kernel[k]
			out[y * w + x] = sum
	return out


## True where a 3x3 neighbourhood is all true (Pillow's MinFilter(3) on a mask).
static func shrink_mask(mask: PackedByteArray, w: int, h: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(w * h)
	for y in h:
		for x in w:
			var all := 1
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := clampi(x + dx, 0, w - 1)
					var ny := clampi(y + dy, 0, h - 1)
					if mask[ny * w + nx] == 0:
						all = 0
			out[y * w + x] = all
	return out


## One channel of a sheet as floats (0 red ... 3 alpha).
static func channel(s: Sheet, k: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(s.w * s.h)
	for i in s.w * s.h:
		out[i] = s.data[i * 4 + k]
	return out


## Colour (saturation), contrast and brightness as ImageEnhance does them.
static func enhance(s: Sheet, colour: float, contrast: float, brightness: float) -> void:
	var n := s.w * s.h
	var mean := 0.0
	for i in n:
		var o := i * 4
		mean += .299 * s.data[o] + .587 * s.data[o + 1] + .114 * s.data[o + 2]
	mean = roundf(mean / maxf(1.0, n))
	for i in n:
		var o := i * 4
		var grey := .299 * s.data[o] + .587 * s.data[o + 1] + .114 * s.data[o + 2]
		for k in 3:
			var v := grey + (s.data[o + k] - grey) * colour
			v = mean + (v - mean) * contrast
			s.data[o + k] = clampi(roundi(v * brightness), 0, 255)


## Unsharp mask on the colour (Pillow's radius, percent and threshold).
static func unsharp(s: Sheet, radius: float, percent: float, threshold: int) -> void:
	for k in 3:
		var values := channel(s, k)
		var soft := blur(values, s.w, s.h, radius)
		for i in s.w * s.h:
			var diff := values[i] - soft[i]
			if absf(diff) >= threshold:
				s.data[i * 4 + k] = clampi(roundi(values[i] + diff * percent / 100.0), 0, 255)


## Seeded Gaussian noise, n values.
static func noise(seed: int, n: int, sigma: float) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = rng.randfn(0.0, sigma)
	return out


## Soft fractal noise in 0..1 (size x size): random grids blown up smoothly.
static func cloud(size: int, seed: int, octaves := [4, 8, 16, 32]) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var total := PackedFloat32Array()
	total.resize(size * size)
	var weight := 0.0
	for k in octaves.size():
		var cells: int = octaves[k]
		var grid := PackedByteArray()
		grid.resize(cells * cells)
		for i in grid.size():
			grid[i] = int(rng.randf() * 255.0)
		var image := Image.create_from_data(cells, cells, false, Image.FORMAT_L8, grid)
		image.resize(size, size, Image.INTERPOLATE_CUBIC)
		var layer := image.get_data()
		var gain := pow(.5, k)
		for i in size * size:
			total[i] += layer[i] / 255.0 * gain
		weight += gain
	for i in size * size:
		total[i] /= weight
	return total


# --------------------------------------------------------------- digitize

static var _lookup := PackedByteArray()


## Commit a picture to the game's VGA palette with a light ordered dither, so
## its colours step as scanned art of the period did (the Python digitize()).
static func digitize(s: Sheet, dither := 9.0) -> Sheet:
	if _lookup.is_empty():
		_lookup = FileAccess.get_file_as_bytes(
			ProjectSettings.globalize_path("res://").path_join("../assets/tiles/vga_rgb555.bin")
		)
	var out := s.duplicate_sheet()
	for y in s.h:
		for x in s.w:
			var o := (y * s.w + x) * 4
			if out.data[o + 3] == 0:
				out.data[o] = 0
				out.data[o + 1] = 0
				out.data[o + 2] = 0
				continue
			var spread: float = (BAYER[(y % 4) * 4 + x % 4] / 16.0 - .5) * dither
			var r := clampi(int(out.data[o] + spread), 0, 255)
			var g := clampi(int(out.data[o + 1] + spread), 0, 255)
			var b := clampi(int(out.data[o + 2] + spread), 0, 255)
			var code := (
				(((r * 31 + 127) / 255) << 10)
				| (((g * 31 + 127) / 255) << 5)
				| ((b * 31 + 127) / 255)
			)
			out.data[o] = _lookup[code * 3]
			out.data[o + 1] = _lookup[code * 3 + 1]
			out.data[o + 2] = _lookup[code * 3 + 2]
	return out


## Where the repository's art lives (godot/ is the project; assets/ is beside it).
static func repo(path: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").path_join(path).simplify_path()


static func rgb(r: float, g: float, b: float, a := 255.0) -> Color:
	return Color8(
		clampi(int(r), 0, 255),
		clampi(int(g), 0, 255),
		clampi(int(b), 0, 255),
		clampi(int(a), 0, 255)
	)


## Down to game size with premultiplied alpha, a hard edge, a dark rim, and a
## grade toward a worn photograph (muzzle flashes and glows keep theirs).
## `grain_sigma` is the photograph's speckle (the bosses take less: cleaner).
static func photo_shrink(image: Sheet, size: Vector2i, seed: int, grain_sigma := .026) -> Sheet:
	# Colour weighed by alpha twice over, as the Python builder's own premultiply
	# followed by Pillow's did: a thin wing keeps its bright core over its dark
	# render edge, which is the look the cels were tuned with.
	var floats := PackedFloat32Array()
	floats.resize(image.w * image.h * 4)
	for i in image.w * image.h:
		var a := image.data[i * 4 + 3] / 255.0
		for k in 3:
			floats[i * 4 + k] = image.data[i * 4 + k] / 255.0 * a * a
		floats[i * 4 + 3] = a
	var small := Sheet.resample(floats, image.w, image.h, 4, size.x, size.y)
	var n := size.x * size.y
	var solid := PackedByteArray()
	solid.resize(n)
	for i in n:
		solid[i] = 1 if small[i * 4 + 3] >= .5 else 0
	var inner := shrink_mask(solid, size.x, size.y)
	var grain := noise(seed, n, grain_sigma)
	var out := Sheet.new(size.x, size.y)
	for i in n:
		if solid[i] == 0:
			continue
		var o := i * 4
		var alpha := maxf(small[o + 3], .02)
		var c := Vector3(small[o], small[o + 1], small[o + 2]) / (alpha * alpha)
		var bright := maxf(c.x, maxf(c.y, c.z)) > .93
		if not bright:
			var grey := (c.x + c.y + c.z) / 3.0
			c = Vector3.ONE * grey + (c - Vector3.ONE * grey) * .86
			c = (c - Vector3.ONE * .42) * 1.18 + Vector3.ONE * .52 + Vector3.ONE * grain[i]
			if inner[i] == 0:
				c *= .55
		out.data[o] = clampi(int(c.x * 255), 0, 255)
		out.data[o + 1] = clampi(int(c.y * 255), 0, 255)
		out.data[o + 2] = clampi(int(c.z * 255), 0, 255)
		out.data[o + 3] = 255
	return out
