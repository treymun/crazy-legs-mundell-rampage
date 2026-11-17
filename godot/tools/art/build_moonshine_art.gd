## Draw the Moonshine Run's own flat art (chapter 7, Copperhead Ridge by
## night): its wall and floor tiles into assets/tiles, its painted signs into
## assets/art, and its moonlit sky.
##
##   godot --headless --path godot --script res://tools/art/build_moonshine_art.gd [-- out=<dir>]
##
## Tiles (listed in data/index.json and assets_gen/tiles_index.json):
##   ridge_pines    the woods at night: pine trunks in the dark, needles
##                  catching the moon, leaf litter at their feet
##   ridge_rock     the ridge's sandstone bluff: bedding ledges, cracks,
##                  moss and lichen
##   cave_floor     the still cave's floor: packed damp clay, straw and
##                  spilled mash, pebbles
## Signs: see SIGNS below; and fx_tear_gas, the gas man's canister in flight.
## Signs: Seeded, so a rerun gives the same files. Then run
## tools/pack_assets.gd.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")

## How much wider the view draws the sky than the panorama is drawn.
const SQUEEZE := 3.5

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 7007
	var art := Paint.repo("assets/art")
	var tiles := Paint.repo("assets/tiles")
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			art = String(arg).substr(4)
			tiles = art
	DirAccess.make_dir_recursive_absolute(art)
	DirAccess.make_dir_recursive_absolute(tiles)
	var tile_made := {
		"ridge_pines": ridge_pines(),
		"ridge_rock": ridge_rock(),
		"cave_floor": cave_floor(),
	}
	for name: String in tile_made:
		var sheet: Paint.Sheet = tile_made[name]
		_opaque(sheet).save(tiles.path_join(name + ".png"))
	sky().save(tiles.path_join("moonshine_sky.png"))
	var signs := {
		"moonshine_low_water": low_water(),
		"moonshine_hymn_board": hymn_board(),
		"moonshine_church_sign": church_sign(),
		"moonshine_county_line": county_line(),
		"moonshine_speed_sign": speed_sign(),
		"moonshine_radio_sign": radio_sign(),
		"moonshine_seized_tag": seized_tag(),
		"moonshine_checkpoint": checkpoint(),
		"moonshine_log_gate": log_gate(),
		"moonshine_switchback": switchback(),
		"moonshine_evidence": evidence(),
		"moonshine_keep_out": keep_out(),
		"moonshine_road_closed": road_closed(),
		"fx_tear_gas": fx_tear_gas(),
	}
	for name: String in signs:
		var sheet: Paint.Sheet = signs[name]
		sheet.save(art.path_join(name + ".png"))
	print(
		(
			"moonshine art: %d tiles and the sky to %s, %d signs to %s"
			% [tile_made.size(), tiles, signs.size(), art]
		)
	)
	quit()


## Tiles have no holes: whatever a drawing left clear is made black.
func _opaque(s: Paint.Sheet) -> Paint.Sheet:
	for i in s.w * s.h:
		s.data[i * 4 + 3] = 255
	return s


# ------------------------------------------------------------------ helpers


func _at(s: Paint.Sheet, x: int, y: int) -> Color:
	var o := (y * s.w + x) * 4
	return Color8(s.data[o], s.data[o + 1], s.data[o + 2], s.data[o + 3])


func shade(c: Color, f: float) -> Color:
	return Color(clampf(c.r * f, 0, 1), clampf(c.g * f, 0, 1), clampf(c.b * f, 0, 1), c.a)


func tin(width: int, height: int, base: Color) -> Paint.Sheet:
	var s := Paint.Sheet.new(width, height)
	var blot := Paint.cloud(64, rng.randi())
	var grain := Paint.noise(rng.randi(), width * height, .05)
	for y in height:
		for x in width:
			var edge := minf(minf(x, width - 1 - x), minf(y, height - 1 - y)) / 5.0
			var b := blot[(y * 64 / height) * 64 + (x * 64 / width)]
			var rust := clampf(b * 1.3 - clampf(edge, 0, 1) * .8 - .1, 0, 1)
			var c := base.lerp(Color(.52, .26, .12), rust)
			s.put(x, y, shade(c, 1.0 + grain[y * width + x] + sin(x * 1.4) * .04))
	return s


func planks(width: int, height: int, base: Color, plank := 6) -> Paint.Sheet:
	var s := Paint.Sheet.new(width, height)
	var grain := Paint.noise(rng.randi(), width * height, .06)
	for y in height:
		var row := y / plank
		for x in width:
			var f := (
				1.0 + sin(row * 2.3) * .06 + grain[y * width + x] + sin(x * .21 + row * 1.7) * .03
			)
			if y % plank == 0:
				f *= .55
			s.put(x, y, shade(base, f))
	return s


## Block letters `scale` times their size with a drop shadow, centred on x.
func letters(
	s: Paint.Sheet, text: String, x: int, y: int, scale: int, ink: Color, shadow := true
) -> int:
	var width := 0
	for c in text:
		width += (int(PixelType.glyph(c, false)[1]) + 1) * scale
	width -= scale
	var left := x - width / 2
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


## Letters painted by hand: each a pixel up or down, a drip under some.
func brushed(s: Paint.Sheet, text: String, x: int, y: int, scale: int, ink: Color) -> void:
	var width := 0
	for c in text:
		width += (int(PixelType.glyph(c, false)[1]) + 1) * scale
	var at := x - (width - scale) / 2
	for c in text:
		var g: Array = PixelType.glyph(c, false)
		var rows: Array = g[0]
		var gw: int = g[1]
		var lift := rng.randi_range(-1, 1)
		for r in rows.size():
			for bx in gw:
				if int(rows[r]) & (1 << (gw - 1 - bx)):
					for yy in scale:
						for xx in scale:
							_blend(s, at + bx * scale + xx, y + lift + r * scale + yy, ink)
		if c != " " and rng.randf() < .35:
			var dx := at + rng.randi_range(0, maxi(0, gw * scale - 1))
			var y0 := y + lift + rows.size() * scale
			for k in rng.randi_range(2, 4):
				_blend(s, dx, y0 + k, ink)
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
		if s.data[o + 3] == 0:
			continue
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
	Paint.outline(s, 1, 1, s.w - 2, s.h - 2, shade(c, 1.5))


## A tile's grit: each texel nudged by noise, so flat paint reads as a surface.
func grit(s: Paint.Sheet, sigma: float) -> void:
	var n := Paint.noise(rng.randi(), s.w * s.h, sigma)
	for i in s.w * s.h:
		for k in 3:
			s.data[i * 4 + k] = clampi(int(s.data[i * 4 + k] * (1.0 + n[i])), 0, 255)


# --------------------------------------------------------------------- tiles


## The woods by night: trunks of pine standing in the dark, needles layered
## over them catching the moon from the upper left, litter at their feet.
## The left and right edges meet, so a wall of it runs on unbroken.
func ridge_pines() -> Paint.Sheet:
	var n := 128
	var s := Paint.Sheet.new(n, n)
	var cloud := Paint.cloud(n, rng.randi())
	for y in n:
		for x in n:
			var d := cloud[y * n + x]
			var c := Color(.05, .07, .07).lerp(Color(.09, .12, .1), d)
			s.put(x, y, c)
	# Trunks, back ones dim, front ones a touch lit on their left.
	for layer in 2:
		for _k in 7 - layer * 2:
			var tx := rng.randi_range(0, n - 1)
			var w := rng.randi_range(3, 5) + layer * 2
			var bark := Color(.08, .07, .06) if layer == 0 else Color(.15, .12, .1)
			for y in n:
				for dx in w:
					var xx := (tx + dx) % n
					var lit := 1.25 if dx == 0 and layer == 1 else (.8 if dx == w - 1 else 1.0)
					var ridge := 1.0 + (.12 if (y + dx * 3) % 7 == 0 else 0.0)
					s.put(xx, y, shade(bark, lit * ridge))
	# Needles: drooping tiers, dark green, moon on their upper edges.
	for _k in 46:
		var cx := rng.randi_range(0, n - 1)
		var cy := rng.randi_range(-6, n - 26)
		var span := rng.randi_range(10, 22)
		var deep := rng.randi_range(5, 9)
		var green := Color(.06, .14, .1).lerp(Color(.1, .2, .14), rng.randf())
		for dy in deep:
			var half := int(span * (.35 + .65 * float(dy) / deep))
			for dx in range(-half, half + 1):
				var xx := posmod(cx + dx, n)
				var yy := cy + dy + int(absf(dx) * .25)
				if yy < 0 or yy >= n:
					continue
				if (dx + dy * 3) % 3 == 0:
					continue
				var c := green
				if dy == 0 or (dy == 1 and dx < 0):
					c = Color(.3, .38, .36)
				s.put(xx, yy, c)
	# Leaf litter and fern along the foot.
	for y in range(n - 14, n):
		for x in n:
			var t := float(y - (n - 14)) / 14.0
			var c := _at(s, x, y).lerp(Color(.16, .12, .08), t * .8)
			if rng.randf() < .08:
				c = Color(.26, .2, .12)
			s.put(x, y, c)
	grit(s, .05)
	return Paint.digitize(s, 6.0)


## The ridge's bluff: sandstone in bedding ledges that overhang a little,
## cracks down through them, moss in the seams and pale lichen on the faces.
func ridge_rock() -> Paint.Sheet:
	var n := 128
	var s := Paint.Sheet.new(n, n)
	var cloud := Paint.cloud(n, rng.randi())
	var fine := Paint.cloud(n, rng.randi(), [16, 32])
	var beds := [0, 17, 36, 50, 71, 88, 104, 118]
	var tone: Array = []
	for k in beds.size() * 6:
		tone.append(rng.randf_range(.82, 1.12))
	var joints: Array = []
	for k in beds.size():
		joints.append(rng.randi_range(0, n - 1))
	for y in n:
		for x in n:
			var wave := int(sin(x * .09 + y * .01) * 2.0 + sin(x * .31) * 1.0)
			var yy := posmod(y + wave, n)
			var bed := 0
			for k in beds.size():
				if yy >= int(beds[k]):
					bed = k
			var into := yy - int(beds[bed])
			var block := int(posmod(x - int(joints[bed]), n) / 64)
			var d := cloud[y * n + x]
			var f := fine[y * n + x]
			var c := Color(.33, .27, .21).lerp(Color(.47, .39, .29), d)
			c = shade(c, float(tone[bed * 6 + block]))
			if into == 0:
				c = Color(.07, .06, .05)
			elif into == 1:
				c = shade(c, 1.3)
			elif into < 4:
				c = shade(c, 1.1)
			var jx := int(joints[bed]) + int(sin(y * .7) * 1.5)
			if (posmod(x - jx, n) == 0 or posmod(x - jx - 61 - bed * 7, n) == 0) and into > 2:
				c = Color(.09, .08, .07)
			c = shade(c, .86 + f * .26)
			s.put(x, y, c)
	for _k in 7:
		var x := rng.randi_range(0, n - 1)
		var y := rng.randi_range(0, n - 30)
		var length := rng.randi_range(10, 26)
		for k in length:
			x = posmod(x + rng.randi_range(-1, 1), n)
			s.put(x, y + k, Color(.07, .06, .05))
	for k in beds.size():
		var y0: int = beds[k]
		for x in n:
			if cloud[((y0 + 2) % n) * n + x] > .58:
				var wave := int(sin(x * .09 + y0 * .01) * 2.0 + sin(x * .31) * 1.0)
				for dy in rng.randi_range(1, 3):
					var mc := Color(.16, .22, .1).lerp(Color(.24, .3, .12), rng.randf())
					s.put(x, posmod(y0 - wave + dy + 1, n), mc)
	for _k in 18:
		var cx := rng.randi_range(0, n - 1)
		var cy := rng.randi_range(0, n - 1)
		var r := rng.randi_range(1, 3)
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dy * dy <= r * r and rng.randf() < .6:
					s.put(posmod(cx + dx, n), posmod(cy + dy, n), Color(.52, .54, .44))
	grit(s, .05)
	return Paint.digitize(s, 6.0)


## The still cave's floor: damp red clay trodden hard, straw spread for the
## jars, mash slopped dark, pebbles.
func cave_floor() -> Paint.Sheet:
	var n := 128
	var s := Paint.Sheet.new(n, n)
	var cloud := Paint.cloud(n, rng.randi())
	for y in n:
		for x in n:
			var d := cloud[y * n + x]
			var c := Color(.34, .22, .15).lerp(Color(.44, .3, .2), d)
			if d < .3:
				c = c.lerp(Color(.16, .1, .07), (.3 - d) * 2.4)
			s.put(x, y, c)
	for _k in 90:
		var x := rng.randi_range(0, n - 1)
		var y := rng.randi_range(0, n - 1)
		var a := rng.randf() * TAU
		var length := rng.randi_range(4, 9)
		var straw := Color(.7, .58, .3).lerp(Color(.54, .42, .2), rng.randf())
		for k in length:
			s.put(posmod(x + int(cos(a) * k), n), posmod(y + int(sin(a) * k), n), straw)
	for _k in 60:
		var x := rng.randi_range(0, n - 2)
		var y := rng.randi_range(0, n - 2)
		var g := Color(.5, .46, .4).lerp(Color(.3, .28, .26), rng.randf())
		Paint.rect(s, x, y, x + 1, y + 1, g)
		s.put(x + 1, y + 1, Color(.12, .1, .08))
	grit(s, .06)
	return Paint.digitize(s, 6.0)


# ----------------------------------------------------------------------- sky


## A clear night over the ridge: deep blue going to black overhead, stars,
## the full moon low over the hills with a ring round it, the ridge's pines
## black along the bottom and the radio mast's red lamp on its knob.
func sky() -> Paint.Sheet:
	var w := 512
	var h := 116
	var s := Paint.Sheet.new(w, h)
	var cloud := Paint.cloud(128, rng.randi())
	var moon := Vector2(352.0, 44.0)
	for y in h:
		for x in w:
			var t := float(y) / h
			var c := Color(.02, .025, .06).lerp(Color(.07, .1, .2), t * t)
			# The panorama is stretched round the whole sky: the moon and its
			# glow are drawn narrow so they come out round in the view.
			var d := Vector2((x - moon.x) * SQUEEZE, y - moon.y).length()
			c = c.lerp(Color(.26, .3, .4), clampf(1.0 - d / 40.0, 0, 1) * .4)
			var cl := cloud[(y * 128 / h) * 128 + (x * 128 / w) % 128]
			if t < .7:
				c = c.lerp(Color(.12, .14, .2), clampf(cl - .62, 0, 1) * 1.6)
			s.put(x, y, c)
	for _k in 160:
		var sx := rng.randi_range(0, w - 1)
		var sy := rng.randi_range(0, 70)
		if Vector2((sx - moon.x) * SQUEEZE, sy - moon.y).length() < 20.0:
			continue
		var b := rng.randf()
		Paint.point(s, sx, sy, Color(.55, .58, .66).lerp(Color(.95, .95, .88), b))
	# The moon itself, its seas.
	for y in range(int(moon.y) - 12, int(moon.y) + 13):
		for x in range(int(moon.x) - 4, int(moon.x) + 5):
			var d := Vector2((x - moon.x) * SQUEEZE, y - moon.y).length()
			if d <= 11.0:
				var sea := cloud[(y % 128) * 128 + (x % 128)]
				var c := Color(.94, .92, .82).lerp(
					Color(.7, .7, .66), clampf(sea - .45, 0, 1) * 1.8
				)
				s.put(x, y, shade(c, 1.0 - d / 40.0))
	# The hills and the pines along their tops.
	var ground := Color(.015, .02, .03)
	var x := 0
	while x < w:
		var top := 92 + int(sin(x * .021) * 5.0 + sin(x * .053) * 3.0)
		var tall := rng.randi_range(8, 20)
		for xx in range(x, mini(w, x + 7)):
			var spread := absf(xx - x - 3.0)
			for yy in range(top - tall + int(spread * 2.6), h):
				s.put(xx, yy, ground)
		x += rng.randi_range(3, 6)
	for xx in range(w):
		for yy in range(100, h):
			s.put(xx, yy, ground)
	# The knob's mast, its lamp lit.
	Paint.rect(s, 140, 52, 141, 92, ground)
	Paint.point(s, 140, 50, Color(1.0, .2, .14))
	Paint.point(s, 141, 50, Color(1.0, .2, .14))
	Paint.point(s, 140, 51, Color(.8, .1, .08))
	return Paint.digitize(s, 6.0)


# --------------------------------------------------------------------- signs


func low_water() -> Paint.Sheet:
	var s := tin(84, 40, Color(.9, .74, .14))
	letters(s, "LOW WATER", 42, 5, 1, Color8(20, 18, 16), false)
	letters(s, "CROSSING", 42, 15, 1, Color8(20, 18, 16), false)
	letters(s, "WHEN FLOODED", 42, 26, 1, Color8(150, 30, 24), false)
	frame(s, Color8(30, 24, 16))
	weather(s, 90, 6)
	return Paint.digitize(s)


func hymn_board() -> Paint.Sheet:
	var s := planks(56, 64, Color(.38, .24, .14), 8)
	frame(s, Color8(40, 26, 16))
	letters(s, "HYMNS", 28, 4, 1, Color8(236, 226, 196), false)
	for k in 3:
		Paint.rect(s, 10, 15 + k * 11, 45, 23 + k * 11, Color8(24, 20, 16))
	letters(s, "112", 28, 16, 1, Color8(236, 226, 196), false)
	letters(s, "47", 28, 27, 1, Color8(236, 226, 196), false)
	letters(s, "230", 28, 38, 1, Color8(236, 226, 196), false)
	letters(s, "NO JARS", 28, 52, 1, Color8(220, 190, 110), false)
	weather(s, 30, 2)
	return Paint.digitize(s)


func church_sign() -> Paint.Sheet:
	var s := planks(156, 54, Color(.9, .88, .82), 13)
	frame(s, Color8(40, 34, 30))
	letters(s, "LITTLE BETHEL", 78, 4, 2, Color8(30, 40, 90))
	letters(s, "FREE WILL CHURCH", 78, 22, 1, Color8(30, 26, 22), false)
	letters(s, "SUN 10 AM", 78, 32, 1, Color8(30, 26, 22), false)
	letters(s, "REVENUERS TOO", 78, 42, 1, Color8(150, 30, 24), false)
	weather(s, 110, 5)
	return Paint.digitize(s)


func county_line() -> Paint.Sheet:
	var s := tin(96, 40, Color(.12, .34, .2))
	frame(s, Color8(220, 220, 210))
	letters(s, "COUNTY LINE", 48, 6, 1, Color8(236, 236, 226), false)
	letters(s, "POSSUM CO.", 48, 17, 2, Color8(236, 236, 226))
	weather(s, 60, 5)
	return Paint.digitize(s)


func speed_sign() -> Paint.Sheet:
	var s := tin(48, 60, Color(.88, .88, .84))
	frame(s, Color8(24, 24, 24))
	letters(s, "SPEED", 24, 6, 1, Color8(20, 20, 20), false)
	letters(s, "LIMIT", 24, 15, 1, Color8(20, 20, 20), false)
	letters(s, "45", 24, 27, 3, Color8(20, 20, 20), false)
	for k in 6:
		Paint.point(s, 10 + k * 5, 45 + k % 2, Color8(20, 18, 16))
	weather(s, 40, 9)
	return Paint.digitize(s)


func radio_sign() -> Paint.Sheet:
	var s := tin(84, 34, Color(.86, .84, .78))
	Paint.rect(s, 3, 3, 80, 14, Color8(30, 40, 90))
	letters(s, "U.S. PROPERTY", 42, 5, 1, Color8(240, 236, 220), false)
	letters(s, "KEEP OFF", 42, 19, 1, Color8(150, 30, 24), false)
	weather(s, 50, 3)
	return Paint.digitize(s)


func seized_tag() -> Paint.Sheet:
	var s := Paint.Sheet.new(48, 28, Color8(236, 196, 60))
	frame(s, Color8(60, 44, 20))
	letters(s, "SEIZED", 24, 5, 1, Color8(20, 18, 16), false)
	letters(s, "U.S. REV.", 24, 15, 1, Color8(150, 30, 24), false)
	weather(s, 20, 1)
	return Paint.digitize(s)


func checkpoint() -> Paint.Sheet:
	var s := tin(120, 40, Color(.86, .84, .8))
	Paint.rect(s, 3, 3, 116, 20, Color8(168, 30, 24))
	letters(s, "CHECKPOINT", 60, 5, 2, Color8(250, 244, 230))
	letters(s, "ALL VEHICLES STOP", 60, 26, 1, Color8(20, 20, 20), false)
	frame(s, Color8(40, 36, 32))
	weather(s, 60, 4)
	return Paint.digitize(s)


func log_gate() -> Paint.Sheet:
	var s := planks(80, 44, Color(.46, .34, .22), 11)
	brushed(s, "HOOTEN", 40, 4, 2, Color8(232, 228, 214))
	brushed(s, "LAND", 40, 20, 1, Color8(232, 228, 214))
	brushed(s, "GIT", 40, 31, 1, Color8(250, 210, 70))
	weather(s, 70, 4)
	return Paint.digitize(s)


func switchback() -> Paint.Sheet:
	var s := tin(64, 40, Color(.9, .74, .14))
	letters(s, "SLOW", 32, 4, 2, Color8(20, 18, 16), false)
	letters(s, "SWITCHBACKS", 32, 24, 1, Color8(20, 18, 16), false)
	frame(s, Color8(30, 24, 16))
	weather(s, 50, 4)
	return Paint.digitize(s)


func evidence() -> Paint.Sheet:
	var s := Paint.Sheet.new(90, 30, Color8(236, 232, 218))
	frame(s, Color8(40, 40, 44))
	letters(s, "EVIDENCE", 45, 4, 1, Color8(30, 40, 90), false)
	letters(s, "DO NOT DRINK", 45, 14, 1, Color8(168, 30, 24), false)
	Paint.line2(s, 6, 25, 84, 23, Color8(30, 40, 90))
	weather(s, 30, 1)
	return Paint.digitize(s)


func keep_out() -> Paint.Sheet:
	var s := planks(80, 52, Color(.36, .26, .18), 13)
	brushed(s, "KEEP OUT", 40, 5, 1, Color8(232, 228, 214))
	brushed(s, "THIS MEANS", 40, 17, 1, Color8(232, 228, 214))
	brushed(s, "YOU", 40, 28, 2, Color8(210, 40, 30))
	Paint.rect(s, 8, 42, 72, 50, Color8(236, 232, 218))
	letters(s, "SEIZED U.S.", 40, 43, 1, Color8(30, 40, 90), false)
	weather(s, 80, 5)
	return Paint.digitize(s)


func road_closed() -> Paint.Sheet:
	var s := tin(80, 36, Color(.9, .88, .84))
	frame(s, Color8(30, 30, 30))
	letters(s, "ROAD CLOSED", 40, 6, 1, Color8(20, 20, 20), false)
	letters(s, "BY ORDER", 40, 16, 1, Color8(168, 30, 24), false)
	letters(s, "U.S. REVENUE", 40, 25, 1, Color8(30, 40, 90), false)
	weather(s, 40, 4)
	return Paint.digitize(s)


## The gas man's canister tumbling through the air, smoke leaking out of it.
func fx_tear_gas() -> Paint.Sheet:
	var s := Paint.Sheet.new(24, 24)
	Paint.ellipse(s, 1, 2, 13, 13, Color8(210, 210, 200, 200))
	Paint.ellipse(s, 3, 1, 10, 8, Color8(236, 236, 228, 220))
	Paint.rect(s, 9, 10, 20, 17, Color8(70, 80, 50))
	Paint.rect(s, 9, 10, 20, 11, Color8(110, 120, 80))
	Paint.rect(s, 18, 9, 21, 18, Color8(40, 40, 36))
	Paint.rect(s, 12, 13, 16, 14, Color8(236, 196, 60))
	return Paint.digitize(s)
