## Draw Hickston's hand-painted signs into assets/art: boards and tin the
## town nailed up itself, lettered in the game's own block letters, chipped,
## faded and shot at. And the corn the north pasture grows, a wall tile in
## assets/tiles (listed in data/index.json and assets_gen/tiles_index.json).
##
##   godot --headless --path godot --script res://tools/art/build_town_signs.gd [-- out=<dir>]
##
##   gas_n_gut_sign    the filling station's tin sign (it buzzes at night)
##   bait_ammo_sign    the bait shop's plank over the door
##   lazy_eight_sign   the trailer court's sign by the road
##   town_line_sign    HICKSTON, POP. and a number nobody updates
##   chapel_sign       the chapel's notice board
##   salvage_sign      a car hood with JUNK painted on it
##   corn (tile)       late corn, head high, gone brown at the tassels
##   rodeo_sign        STAMPEDE RODEO over the chute gate (Hickston's rodeo)
##   hogs_sign         the Hickston Hogs' board by their field
##   big_top_sign      RUDY'S BIG TOP over the fair's ring
##   saw_floor_sign    the mill's carriage track warning
## Seeded, so a rerun gives the same files. Then run tools/pack_assets.gd.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 1997
	var out := Paint.repo("assets/art")
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	var made := {
		"gas_n_gut_sign": gas_sign(),
		"bait_ammo_sign": bait_sign(),
		"lazy_eight_sign": trailer_sign(),
		"town_line_sign": town_sign(),
		"chapel_sign": chapel_sign(),
		"salvage_sign": salvage_sign(),
	}
	for name: String in made:
		var sheet: Paint.Sheet = made[name]
		sheet.save(out.path_join(name + ".png"))
	var tiles := Paint.repo("assets/tiles") if out == Paint.repo("assets/art") else out
	corn().save(tiles.path_join("corn.png"))
	# The boss arenas' boards, after the rest so theirs keep their dice.
	var arenas := {
		"rodeo_sign": rodeo_sign(),
		"hogs_sign": hogs_sign(),
		"big_top_sign": big_top_sign(),
		"saw_floor_sign": saw_floor_sign(),
	}
	for name: String in arenas:
		var sheet: Paint.Sheet = arenas[name]
		sheet.save(out.path_join(name + ".png"))
	made.merge(arenas)
	print("town signs: %d written to %s, corn to %s" % [made.size(), out, tiles])
	quit()


# ------------------------------------------------------------------ surfaces


## Painted planks laid across: grain, seams, knots, sun-bleached at the top.
func planks(width: int, height: int, base: Color, plank := 6) -> Paint.Sheet:
	var s := Paint.Sheet.new(width, height)
	var grain := Paint.noise(rng.randi(), width * height, .06)
	for y in height:
		var row := y / plank
		var tone := 1.0 + sin(row * 2.3) * .06
		var seam := y % plank == 0
		for x in width:
			var f := tone + grain[y * width + x] + sin(x * .21 + row * 1.7) * .03
			f *= 1.0 + (1.0 - float(y) / height) * .08
			if seam:
				f *= .55
			s.put(x, y, Color(base.r * f, base.g * f, base.b * f))
	return s


## Sheet tin: flat colour with ridges, rust creeping in from the edges.
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


# ------------------------------------------------------------------ lettering


## Block letters `scale` times their size, with a drop shadow; centred on
## `cx` when `centre`, else from x. Returns the width drawn.
func letters(
	s: Paint.Sheet,
	text: String,
	x: int,
	y: int,
	scale: int,
	ink: Color,
	shadow := true,
	centre := true
) -> int:
	var width := 0
	for c in text:
		width += (int(PixelType.glyph(c, false)[1]) + 1) * scale
	width -= scale
	var left := x - width / 2 if centre else x
	for pass_k in [1, 0] if shadow else [0]:
		var off: int = pass_k * maxi(1, scale / 2)
		var colour := Color(.08, .05, .04, .85) if pass_k == 1 else ink
		var at := left
		for c in text:
			var g: Array = PixelType.glyph(c, false)
			var rows: Array = g[0]
			var gw: int = g[1]
			for r in rows.size():
				for bx in gw:
					if int(rows[r]) & (1 << (gw - 1 - bx)):
						for yy in scale:
							for xx in scale:
								_blend(
									s, at + bx * scale + xx + off, y + r * scale + yy + off, colour
								)
			at += (gw + 1) * scale
	return width


func _blend(s: Paint.Sheet, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= s.w or y >= s.h:
		return
	var o := (y * s.w + x) * 4
	var a := c.a
	for k in 3:
		s.data[o + k] = int(s.data[o + k] * (1.0 - a) + c[k] * 255.0 * a)
	s.data[o + 3] = maxi(s.data[o + 3], int(a * 255))


## Weather it: chips where the paint came off, a few bullet holes.
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


# --------------------------------------------------------------------- signs


func gas_sign() -> Paint.Sheet:
	var s := tin(120, 44, Color(.86, .82, .7))
	Paint.rect(s, 3, 3, 116, 21, Color8(168, 34, 26))
	letters(s, "GAS-N-GUT", 60, 5, 2, Color8(250, 236, 196))
	letters(s, "EATS  BEER", 60, 25, 1, Color8(40, 30, 24), false)
	letters(s, "LIVE BAIT", 60, 34, 1, Color8(168, 34, 26), false)
	# A bulb border: the bulbs that still work glow (the tile's bright texels).
	for x in range(4, 116, 6):
		for y in [1, 42]:
			var on := rng.randf() < .75
			Paint.point(s, x, y, Color8(255, 226, 150) if on else Color8(90, 70, 50))
	frame(s, Color8(46, 34, 26))
	weather(s, 70, 5)
	return Paint.digitize(s)


func bait_sign() -> Paint.Sheet:
	var s := planks(140, 20, Color(.5, .36, .24), 7)
	letters(s, "BAIT N AMMO", 70, 3, 2, Color8(236, 226, 196))
	frame(s, Color8(40, 28, 20))
	nails(s)
	weather(s, 90, 3)
	return Paint.digitize(s)


func trailer_sign() -> Paint.Sheet:
	var s := tin(92, 36, Color(.36, .52, .58))
	letters(s, "LAZY 8", 46, 3, 2, Color8(246, 214, 120))
	Paint.rect(s, 6, 19, 85, 20, Color8(246, 214, 120))
	letters(s, "TRAILER COURT", 46, 23, 1, Color8(236, 232, 220), false)
	frame(s, Color8(30, 34, 36))
	weather(s, 60, 7)
	return Paint.digitize(s)


func town_sign() -> Paint.Sheet:
	var s := Paint.Sheet.new(56, 26, Color8(40, 104, 64))
	var grit := Paint.noise(rng.randi(), 56 * 26, .05)
	for i in 56 * 26:
		var f := 1.0 + grit[i]
		for k in 3:
			s.data[i * 4 + k] = clampi(int(s.data[i * 4 + k] * f), 0, 255)
	Paint.outline(s, 1, 1, 54, 24, Color8(232, 236, 228))
	letters(s, "HICKSTON", 28, 4, 1, Color8(240, 242, 236), false)
	letters(s, "POP. 212", 28, 14, 1, Color8(240, 242, 236), false)
	# Somebody crossed it out and wrote a smaller number.
	Paint.line2(s, 33, 17, 48, 15, Color8(200, 40, 30))
	weather(s, 30, 9)
	return Paint.digitize(s)


func chapel_sign() -> Paint.Sheet:
	var s := planks(60, 32, Color(.84, .82, .76), 8)
	letters(s, "OPEN ROAD", 30, 3, 1, Color8(40, 30, 26), false)
	letters(s, "CHAPEL", 30, 12, 1, Color8(150, 30, 24), false)
	letters(s, "BINGO TUES", 30, 22, 1, Color8(40, 30, 26), false)
	frame(s, Color8(60, 48, 40))
	nails(s)
	weather(s, 50, 2)
	return Paint.digitize(s)


func salvage_sign() -> Paint.Sheet:
	var s := tin(52, 22, Color(.42, .48, .3))
	letters(s, "JUNK", 26, 2, 2, Color8(240, 236, 220))
	letters(s, "4 SALE", 26, 14, 1, Color8(240, 236, 220), false)
	weather(s, 80, 11)
	return Paint.digitize(s)


## Over the chute gate at the rodeo grounds: red planks, cream letters, a
## string of bulbs along the top, half of them dead.
func rodeo_sign() -> Paint.Sheet:
	var s := planks(210, 30, Color(.56, .16, .12), 6)
	letters(s, "STAMPEDE RODEO", 105, 5, 2, Color8(244, 228, 186))
	letters(s, "FRI NITE  -  BRING A COW", 105, 21, 1, Color8(236, 196, 104), false)
	for x in range(4, 206, 7):
		var on := rng.randf() < .55
		Paint.point(s, x, 1, Color8(255, 228, 150) if on else Color8(80, 60, 44))
	frame(s, Color8(42, 22, 16))
	nails(s)
	weather(s, 110, 6)
	return Paint.digitize(s)


## The football field's board on the stock fence: the Hogs' colours, a hog's
## snout for a crest, the season nobody wants to talk about.
func hogs_sign() -> Paint.Sheet:
	var s := tin(100, 40, Color(.18, .3, .52))
	Paint.rect(s, 3, 3, 96, 11, Color8(196, 150, 44))
	letters(s, "HOME OF THE", 50, 5, 1, Color8(30, 26, 40), false)
	letters(s, "HOGS", 50, 15, 2, Color8(246, 240, 226))
	letters(s, "0 AND 9", 50, 31, 1, Color8(196, 150, 44), false)
	# The snout, either side of the name.
	for cx in [14, 85]:
		Paint.rect(s, cx - 6, 17, cx + 6, 26, Color8(228, 150, 150))
		Paint.rect(s, cx - 3, 20, cx - 2, 23, Color8(90, 40, 44))
		Paint.rect(s, cx + 2, 20, cx + 3, 23, Color8(90, 40, 44))
	frame(s, Color8(20, 24, 34))
	weather(s, 80, 9)
	return Paint.digitize(s)


## Over the big top's ring: a gilt circus board, RUDY'S in red on cream.
func big_top_sign() -> Paint.Sheet:
	var s := planks(212, 34, Color(.86, .8, .64), 5)
	Paint.rect(s, 3, 3, 208, 4, Color8(200, 160, 60))
	Paint.rect(s, 3, 29, 208, 30, Color8(200, 160, 60))
	letters(s, "RUDY'S BIG TOP", 106, 7, 2, Color8(170, 30, 26))
	letters(s, "ONE NITE ONLY", 106, 21, 1, Color8(40, 30, 26), false)
	for x in range(5, 208, 8):
		Paint.point(s, x, 1, Color8(255, 226, 150) if rng.randf() < .7 else Color8(90, 70, 50))
		Paint.point(s, x, 32, Color8(255, 226, 150) if rng.randf() < .7 else Color8(90, 70, 50))
	frame(s, Color8(60, 40, 22))
	weather(s, 60, 2)
	return Paint.digitize(s)


## On the saw floor: the carriage track's warning, stencilled on tin.
func saw_floor_sign() -> Paint.Sheet:
	var s := tin(200, 30, Color(.86, .7, .2))
	for x in range(0, 200, 10):
		Paint.rect(s, x, 0, x + 4, 3, Color8(30, 26, 22))
		Paint.rect(s, x + 5, 26, x + 9, 29, Color8(30, 26, 22))
	letters(s, "HEAD SAW", 100, 6, 2, Color8(30, 26, 22))
	letters(s, "STAY OFF THE CARRIAGE TRACK", 100, 19, 1, Color8(120, 30, 20), false)
	weather(s, 70, 8)
	return Paint.digitize(s)


## Corn: stalks close together, leaves arching off them, ears in husk, the
## tassels dry against the dusk; dark between the rows.
func corn() -> Paint.Sheet:
	var s := Paint.Sheet.new(128, 128, Color8(14, 20, 12))
	var depth := Paint.cloud(128, rng.randi())
	for y in 128:
		for x in 128:
			var d := depth[y * 128 + x]
			s.put(x, y, Color(.05 + d * .05, .08 + d * .07, .04 + d * .03))
	# Back rows dim, front rows bright: three passes of stalks.
	for layer in 3:
		var shade: float = [.45, .7, 1.0][layer]
		var x := float(rng.randi_range(0, 6))
		while x < 128.0:
			var lean := rng.randf_range(-.08, .08)
			var green: Color = Color(.36, .5, .2).lerp(Color(.5, .52, .24), rng.randf()) * shade
			green.a = 1.0
			for y in range(8, 128):
				var sx := int(x + lean * (128 - y)) % 128
				Paint.point(s, sx, y, green)
				Paint.point(s, (sx + 1) % 128, y, green.darkened(.25))
			# Leaves: long arcs falling off either side.
			for k in rng.randi_range(3, 5):
				var y0 := rng.randi_range(24, 110)
				var dir := 1 if rng.randf() < .5 else -1
				var length := rng.randi_range(10, 22)
				for t in length:
					var lx := int(x + lean * (128 - y0) + dir * t) % 128
					var ly := y0 - int(sin(float(t) / length * PI) * 7.0) + t / 4
					var leaf: Color = green.lightened(.12) if t < length / 2 else green.darkened(.1)
					Paint.point(s, (lx + 128) % 128, clampi(ly, 0, 127), leaf)
			# An ear in its husk, now and then.
			if rng.randf() < .45:
				var ey := rng.randi_range(56, 90)
				var ex := int(x + lean * (128 - ey) + 2) % 128
				for t in 9:
					Paint.point(s, ex, ey + t, Color(.62, .6, .32) * shade)
					Paint.point(s, (ex + 1) % 128, ey + t, Color(.5, .5, .26) * shade)
			# The tassel at the top, dried out.
			for t in 7:
				var tx := int(x + lean * 128 + rng.randi_range(-2, 2)) % 128
				Paint.point(s, (tx + 128) % 128, 8 - t, Color(.7, .58, .32) * shade)
			x += rng.randf_range(4.0, 9.0) - layer
	# The top rows fade so a field's edge reads against the sky.
	for y in 6:
		for x in 128:
			var o := (y * 128 + x) * 4
			for k in 3:
				s.data[o + k] = int(s.data[o + k] * (.55 + y * .075))
	return Paint.digitize(s)
