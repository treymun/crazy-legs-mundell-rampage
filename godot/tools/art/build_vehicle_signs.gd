## Draw the hand-painted signs left by the vehicles (feature pass 7,
## src/vehicle_finder.gd): KEYS IN IT, slapped on a board by whoever left
## the keys, with a line for what the vehicle is good for. Gator Bayou's on
## sun-bleached planks with a bite out of a corner, the speedway's on a
## checkered tin plate, Hickston's on the church's whitewashed boards.
##
##   godot --headless --path godot --script res://tools/art/build_vehicle_signs.gd [-- out=<dir>]
##
## Writes assets/art/vehicle_sign_<kind>.png (the plans hang them by each
## vehicle; county_kit.gd takes them off the County Run maps, which have no
## vehicles). Seeded with its own generator, so a rerun gives the same files
## and no other art moves. Then run tools/pack_assets.gd.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 7707
	var art := Paint.repo("assets/art")
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			art = String(arg).substr(4)
	DirAccess.make_dir_recursive_absolute(art)
	var made := {
		"vehicle_sign_airboat": sign_airboat(),
		"vehicle_sign_car": sign_car(),
		"vehicle_sign_mower": sign_mower(),
	}
	for name: String in made:
		var sheet: Paint.Sheet = made[name]
		sheet.save(art.path_join(name + ".png"))
	print("vehicle signs: %d to %s" % [made.size(), art])
	quit()


# ---------------------------------------------------------------- the boards


func planks(width: int, height: int, base: Color, plank := 6) -> Paint.Sheet:
	var s := Paint.Sheet.new(width, height)
	var grain := Paint.noise(rng.randi(), width * height, .06)
	for y in height:
		var row := y / plank
		var tone := 1.0 + sin(row * 2.3) * .07
		var seam := y % plank == 0
		for x in width:
			var f := tone + grain[y * width + x] + sin(x * .21 + row * 1.7) * .03
			f *= 1.0 + (1.0 - float(y) / height) * .08
			if seam:
				f *= .55
			s.put(x, y, Color(base.r * f, base.g * f, base.b * f))
	return s


func tin(width: int, height: int, base: Color) -> Paint.Sheet:
	var s := Paint.Sheet.new(width, height)
	var blot := Paint.cloud(64, rng.randi())
	var grit := Paint.noise(rng.randi(), width * height, .05)
	for y in height:
		for x in width:
			var edge := minf(minf(x, width - 1 - x), minf(y, height - 1 - y)) / 5.0
			var b := blot[(y * 64 / height) * 64 + (x * 64 / width)]
			var rust := clampf(b * 1.3 - clampf(edge, 0, 1) * .8 - .1, 0, 1)
			var c := base.lerp(Color(.52, .26, .12), rust)
			var f := 1.0 + grit[y * width + x] + (sin(x * 1.4) * .04)
			s.put(x, y, Color(c.r * f, c.g * f, c.b * f))
	return s


## Block letters `scale` times their size, centred on x, painted by hand:
## each letter sits a pixel up or down, the brush thins at its edges, and
## paint runs down from a few of them (`drips` in a hundred).
func painted(
	s: Paint.Sheet, text: String, x: int, y: int, scale: int, ink: Color, drips := 0
) -> void:
	var width := 0
	for c in text:
		width += (int(PixelType.glyph(c, false)[1]) + 1) * scale
	width -= scale
	var at := x - width / 2
	for c in text:
		var g: Array = PixelType.glyph(c, false)
		var rows: Array = g[0]
		var gw: int = g[1]
		var lift := rng.randi_range(-1, 1) if scale > 1 else 0
		var tone := ink.darkened(rng.randf_range(0.0, .12))
		var lowest := {}
		for r in rows.size():
			for bx in gw:
				if int(rows[r]) & (1 << (gw - 1 - bx)):
					for yy in scale:
						for xx in scale:
							var px := at + bx * scale + xx
							var py := y + r * scale + yy + lift
							var thin := (
								scale > 1
								and (xx == scale - 1 or yy == scale - 1)
								and rng.randf() < .3
							)
							_blend(s, px, py, tone if not thin else Color(tone, .55))
							lowest[px] = maxi(int(lowest.get(px, 0)), py)
		for px: int in lowest:
			if rng.randi_range(0, 99) < drips:
				var run := rng.randi_range(2, 5)
				for k in run:
					_blend(s, px, int(lowest[px]) + 1 + k, Color(tone, .85 - k * .14))
		at += (gw + 1) * scale


func _blend(s: Paint.Sheet, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= s.w or y >= s.h:
		return
	var o := (y * s.w + x) * 4
	var a := c.a
	for k in 3:
		s.data[o + k] = int(s.data[o + k] * (1.0 - a) + c[k] * 255.0 * a)
	s.data[o + 3] = maxi(s.data[o + 3], int(a * 255))


func weather(s: Paint.Sheet, chips: int, holes: int) -> void:
	for _k in chips:
		var x := rng.randi_range(1, s.w - 2)
		var y := rng.randi_range(1, s.h - 2)
		var o := (y * s.w + x) * 4
		for k in 3:
			s.data[o + k] = int(s.data[o + k] * .72)
	for _k in holes:
		var x := rng.randi_range(3, s.w - 4)
		var y := rng.randi_range(3, s.h - 4)
		Paint.point(s, x, y, Color8(14, 10, 8))
		Paint.point(s, x + 1, y, Color8(150, 140, 128))
		Paint.point(s, x, y - 1, Color8(150, 140, 128))


func frame(s: Paint.Sheet, c: Color) -> void:
	Paint.outline(s, 0, 0, s.w - 1, s.h - 1, c)
	Paint.outline(s, 1, 1, s.w - 2, s.h - 2, c.lightened(.25))


func nails(s: Paint.Sheet) -> void:
	for p in [
		Vector2i(2, 2), Vector2i(s.w - 3, 2), Vector2i(2, s.h - 3), Vector2i(s.w - 3, s.h - 3)
	]:
		Paint.point(s, p.x, p.y, Color8(200, 196, 186))


## A key on a ring, painted beside the words (a crude brush outline): the
## ring's bow, the shank and two teeth.
func key(s: Paint.Sheet, x: int, y: int, ink: Color) -> void:
	for yy in range(-4, 5):
		for xx in range(-4, 5):
			var d := Vector2(xx, yy).length()
			if d >= 1.7 and d <= 3.6:
				_blend(s, x + 3 + xx, y + 3 + yy, ink)
	Paint.rect(s, x + 7, y + 2, x + 16, y + 3, ink)
	Paint.rect(s, x + 13, y + 4, x + 14, y + 6, ink)
	Paint.rect(s, x + 10, y + 4, x + 11, y + 5, ink)


## Teeth marks bitten out of a corner: the swamp's own comment on a sign.
func bitten(s: Paint.Sheet, right: bool) -> void:
	var cx := s.w - 1 if right else 0
	for k in 3:
		var r := 3 + (k % 2) * 2
		var cy := s.h - 4 - k * 5
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				if Vector2(x, y).length() <= r and cy + y >= 0 and cy + y < s.h:
					var px := cx + x
					if px >= 0 and px < s.w:
						var o := ((cy + y) * s.w + px) * 4
						s.data[o + 3] = 0


# --------------------------------------------------------------------- signs


func sign_airboat() -> Paint.Sheet:
	var s := planks(150, 46, Color(.7, .64, .5), 9)
	painted(s, "KEYS IN IT", 84, 4, 2, Color8(176, 34, 24), 18)
	key(s, 7, 6, Color8(176, 34, 24))
	painted(s, "AIRBOAT - HONOR SYSTEM", 75, 23, 1, Color8(36, 28, 22))
	painted(s, "LAGOON OR BUST", 75, 33, 1, Color8(150, 30, 22))
	frame(s, Color8(52, 40, 28))
	nails(s)
	weather(s, 110, 4)
	bitten(s, true)
	return Paint.digitize(s)


func sign_car() -> Paint.Sheet:
	var s := tin(140, 46, Color(.86, .84, .78))
	# A strip of checkers along the top, as on the start/finish banner.
	for x in range(3, 137):
		for y in range(3, 8):
			var dark := ((x - 3) / 5 + (y - 3) / 3) % 2 == 0
			s.put(x, y, Color8(26, 22, 20) if dark else Color8(232, 228, 214))
	painted(s, "KEYS IN IT", 70, 11, 2, Color8(184, 30, 22), 12)
	painted(s, "HEAT RACE - THREE LAPS", 70, 28, 1, Color8(30, 26, 24))
	painted(s, "BEAT THE BOGGS BOYS", 70, 37, 1, Color8(30, 60, 120))
	frame(s, Color8(46, 40, 34))
	weather(s, 80, 6)
	return Paint.digitize(s)


func sign_mower() -> Paint.Sheet:
	var s := planks(132, 42, Color(.86, .84, .78), 7)
	painted(s, "KEYS IN IT", 76, 4, 2, Color8(40, 70, 40), 10)
	key(s, 6, 6, Color8(40, 70, 40))
	painted(s, "CHURCH MOWER", 66, 22, 1, Color8(36, 30, 26))
	painted(s, "MIND THE STONES", 66, 31, 1, Color8(150, 30, 24))
	frame(s, Color8(70, 60, 48))
	nails(s)
	weather(s, 70, 2)
	return Paint.digitize(s)
