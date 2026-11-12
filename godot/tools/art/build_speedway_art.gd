## Draw the speedway's own flat art (chapter 6, Buzzard Bend Speedway): its
## wall and floor tiles into assets/tiles, its painted signs, sponsor boards
## and the shots its hands throw into assets/art, and its race-night sky.
##
##   godot --headless --path godot --script res://tools/art/build_speedway_art.gd [-- out=<dir>]
##
## Tiles (listed in data/index.json and assets_gen/tiles_index.json):
##   track_dirt, track_chalk   the oval's red clay, and a chalk line across it
##   derby_mud, junk_ground    the figure 8's wet mud, the salvage yard's oily cinders
##   diner_checker             the diner's black and white floor
##   crash_wall, tire_wall     the oval's scuffed concrete wall, stacked painted tyres
##   junk_stack                crushed cars stacked into a wall
##   garage_door, grandstand_riser   a pit bay's roll-up door, a stand row's face
##   speedway_marquee          the lit sign over the gate (buzzes, effects.cfg)
##   diner_steel (+ _win, _lit)   the diner's ribbed steel front
##   checker_band              black and white checks (the flag stand, the line)
## Signs, boards and shots: see SIGNS below. Seeded, so a rerun gives the same
## files. Then run tools/pack_assets.gd.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 6006
	var art := Paint.repo("assets/art")
	var tiles := Paint.repo("assets/tiles")
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			art = String(arg).substr(4)
			tiles = art
	DirAccess.make_dir_recursive_absolute(art)
	DirAccess.make_dir_recursive_absolute(tiles)
	var tile_made := {
		"track_dirt": track_dirt(false),
		"track_chalk": track_dirt(true),
		"derby_mud": derby_mud(),
		"junk_ground": junk_ground(),
		"diner_checker": diner_checker(),
		"crash_wall": crash_wall(),
		"tire_wall": tire_wall(),
		"junk_stack": junk_stack(),
		"garage_door": garage_door(),
		"grandstand_riser": grandstand_riser(),
		"speedway_marquee": marquee(),
		"diner_steel": diner_steel(0),
		"diner_steel_win": diner_steel(1),
		"diner_steel_lit": diner_steel(2),
		"checker_band": checker_band(),
	}
	for name: String in tile_made:
		var sheet: Paint.Sheet = tile_made[name]
		_opaque(sheet).save(tiles.path_join(name + ".png"))
	sky().save(tiles.path_join("speedway_sky.png"))
	var signs := {
		"speedway_entry": entry_sign(),
		"speedway_diner_sign": diner_sign(),
		"speedway_truckstop_sign": truckstop_sign(),
		"speedway_fuel_price": fuel_price(),
		"speedway_pit_row": pit_row_sign(),
		"speedway_no_pass": no_pass_sign(),
		"speedway_junk_sign": junk_sign(),
		"speedway_crusher_warn": crusher_warn(),
		"speedway_turn_1": turn_sign(1),
		"speedway_turn_2": turn_sign(2),
		"speedway_turn_3": turn_sign(3),
		"speedway_turn_4": turn_sign(4),
		"speedway_ad_oil":
		ad_board("HOGBACK", "MOTOR OIL", Color8(26, 70, 40), Color8(240, 204, 70)),
		"speedway_ad_chaw":
		ad_board("GATOR CHAW", "SPIT HAPPENS", Color8(40, 36, 30), Color8(120, 200, 70)),
		"speedway_ad_tires":
		ad_board("BIG RED'S", "TIRES & LUBE", Color8(170, 30, 24), Color8(250, 240, 220)),
		"speedway_ad_bait":
		ad_board("POSSUM BAIT", "& TACKLE", Color8(40, 70, 120), Color8(250, 214, 110)),
		"speedway_standings": standings_board(),
		"speedway_menu": concession_menu(),
		"speedway_figure8": figure8_sign(),
		"speedway_camping": camping_sign(),
		"speedway_jump": jump_sign(),
		"speedway_start_finish": start_finish(),
		"speedway_beer": beer_sign(),
		"speedway_booth_sign": booth_sign(),
		"speedway_salvage_arrow": arrow_sign("SALVAGE", true),
		"speedway_pits_arrow": arrow_sign("PITS", false),
		"speedway_tanks": tanks_sign(),
		"speedway_points": points_board(),
		"fx_wrench": fx_wrench(),
		"fx_tire": fx_tire(),
		"fx_flare": fx_flare(),
	}
	for name: String in signs:
		var sheet: Paint.Sheet = signs[name]
		sheet.save(art.path_join(name + ".png"))
	print(
		(
			"speedway art: %d tiles and the sky to %s, %d signs and shots to %s"
			% [tile_made.size(), tiles, signs.size(), art]
		)
	)
	quit()


## Tiles have no holes: whatever a drawing left clear is made black.
func _opaque(s: Paint.Sheet) -> Paint.Sheet:
	for i in s.w * s.h:
		s.data[i * 4 + 3] = 255
	return s


# ------------------------------------------------------------------ surfaces


func shade(c: Color, f: float) -> Color:
	return Color(clampf(c.r * f, 0, 1), clampf(c.g * f, 0, 1), clampf(c.b * f, 0, 1), c.a)


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
			s.put(x, y, shade(c, 1.0 + grit[y * width + x] + sin(x * 1.4) * .04))
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


func bulbs(s: Paint.Sheet, step: int, live := .75) -> void:
	for x in range(3, s.w - 2, step):
		for y in [1, s.h - 2]:
			var on := rng.randf() < live
			Paint.point(s, x, y, Color8(255, 226, 150) if on else Color8(90, 70, 50))
	for y in range(3, s.h - 2, step):
		for x in [1, s.w - 2]:
			var on := rng.randf() < live
			Paint.point(s, x, y, Color8(255, 226, 150) if on else Color8(90, 70, 50))


## A tile's grit: each texel nudged by noise, so flat paint reads as a surface.
func grit(s: Paint.Sheet, sigma: float) -> void:
	var n := Paint.noise(rng.randi(), s.w * s.h, sigma)
	for i in s.w * s.h:
		for k in 3:
			s.data[i * 4 + k] = clampi(int(s.data[i * 4 + k] * (1.0 + n[i])), 0, 255)


# --------------------------------------------------------------------- tiles


## Red clay packed hard by the cars: grooves round the oval, clods, oil.
func track_dirt(chalk: bool) -> Paint.Sheet:
	var s := Paint.Sheet.new(128, 128)
	var cloud := Paint.cloud(128, rng.randi())
	for y in 128:
		for x in 128:
			var d := cloud[y * 128 + x]
			var groove := .06 * sin(y * .55 + sin(x * .05) * 2.0) + .04 * sin(y * 1.9)
			var f := .78 + d * .4 + groove
			s.put(x, y, Color(.5 * f, .28 * f, .17 * f))
	for _k in 60:
		var cx := rng.randi_range(0, 127)
		var cy := rng.randi_range(0, 127)
		var r := rng.randf_range(1.0, 2.6)
		Paint.ellipse(s, cx - r, cy - r * .7, cx + r, cy + r * .7, Color(.42, .24, .15))
		Paint.point(s, cx, cy - 1, Color(.62, .38, .24))
	for _k in 2:
		var cx := rng.randi_range(10, 118)
		var cy := rng.randi_range(10, 118)
		for _j in 5:
			var ox := cx + rng.randi_range(-6, 6)
			var oy := cy + rng.randi_range(-2, 2)
			Paint.ellipse(s, ox - 4, oy - 2, ox + 4, oy + 2, Color(.34, .2, .13))
	if chalk:
		for y in 128:
			for x in range(56, 72):
				var worn := cloud[y * 128 + x] > .62 and rng.randf() < .5
				if not worn:
					s.put(x, y, Color(.86, .84, .78).lerp(Color(.6, .4, .3), rng.randf() * .25))
	grit(s, .05)
	return s


func derby_mud() -> Paint.Sheet:
	var s := Paint.Sheet.new(128, 128)
	var cloud := Paint.cloud(128, rng.randi())
	for y in 128:
		for x in 128:
			var d := cloud[y * 128 + x]
			var f := .55 + d * .5
			var c := Color(.26 * f, .19 * f, .12 * f)
			if d > .62:
				c = c.lerp(Color(.32, .3, .3), (d - .62) * 1.6)
			s.put(x, y, c)
	# Tyre ruts curling through it.
	for k in 4:
		var y0 := rng.randf_range(10, 118)
		var bend := rng.randf_range(-.04, .04)
		for x in 128:
			var y := int(y0 + x * bend * x * .1) % 128
			for w in 5:
				var yy := (y + w + 128) % 128
				var tread := Color(.12, .09, .06) if (x + w) % 4 else Color(.2, .15, .1)
				s.put(x, yy, tread)
	grit(s, .06)
	return s


func junk_ground() -> Paint.Sheet:
	var s := Paint.Sheet.new(128, 128)
	var cloud := Paint.cloud(128, rng.randi())
	for y in 128:
		for x in 128:
			var d := cloud[y * 128 + x]
			var f := .5 + d * .5
			s.put(x, y, Color(.3 * f, .27 * f, .24 * f))
	for _k in 260:
		var x := rng.randi_range(0, 126)
		var y := rng.randi_range(0, 126)
		var c: Color = [Color(.42, .38, .34), Color(.2, .18, .16), Color(.5, .3, .18)][
			rng.randi() % 3
		]
		Paint.rect(s, x, y, x + rng.randi_range(0, 1), y + rng.randi_range(0, 1), c)
	for _k in 6:
		var cx := rng.randi_range(10, 118)
		var cy := rng.randi_range(10, 118)
		for _j in 4:
			var ox := cx + rng.randi_range(-7, 7)
			var oy := cy + rng.randi_range(-3, 3)
			Paint.ellipse(s, ox - 5, oy - 3, ox + 5, oy + 3, Color(.17, .15, .15))
		Paint.ellipse(s, cx - 3, cy - 1, cx + 1, cy, Color(.3, .22, .34))
	for _k in 12:
		var x := rng.randi_range(4, 120)
		var y := rng.randi_range(4, 120)
		Paint.line2(
			s, x, y, x + rng.randi_range(-6, 6), y + rng.randi_range(-6, 6), Color(.46, .26, .14)
		)
	grit(s, .05)
	return s


func diner_checker() -> Paint.Sheet:
	var s := Paint.Sheet.new(128, 128)
	for y in 128:
		for x in 128:
			var light := ((x / 16) + (y / 16)) % 2 == 0
			var c := Color(.82, .8, .72) if light else Color(.1, .1, .11)
			if x % 16 == 0 or y % 16 == 0:
				c = shade(c, .7)
			s.put(x, y, c)
	var cloud := Paint.cloud(128, rng.randi())
	for i in 128 * 128:
		var dirt := clampf(cloud[i] - .55, 0, 1) * .9
		for k in 3:
			s.data[i * 4 + k] = int(s.data[i * 4 + k] * (1.0 - dirt) + [74, 60, 40][k] * dirt)
	grit(s, .04)
	return s


## The oval's wall: poured concrete painted white once, scuffed black by tyres
## along the bottom, a faded red stripe, form joints.
func crash_wall() -> Paint.Sheet:
	var s := Paint.Sheet.new(128, 128)
	var cloud := Paint.cloud(128, rng.randi())
	for y in 128:
		for x in 128:
			var d := cloud[y * 128 + x]
			var c := Color(.78, .77, .72).lerp(Color(.6, .58, .52), d * .6)
			if y < 10:
				c = Color(.66, .65, .6)
			elif y < 13:
				c = Color(.4, .39, .36)
			if y >= 30 and y < 44:
				c = c.lerp(Color(.66, .16, .12), .8 - d * .4)
			if x % 64 < 2:
				c = shade(c, .72)
			# Rubber laid on by the cars, heavy at the bottom.
			var rub := clampf((y - 70) / 50.0, 0, 1) * (.4 + d * .8)
			c = c.lerp(Color(.08, .07, .07), clampf(rub, 0, .92))
			s.put(x, y, c)
	for _k in 9:
		var x := rng.randi_range(0, 120)
		var y := rng.randi_range(60, 110)
		Paint.line2(
			s, x, y, x + rng.randi_range(10, 30), y + rng.randi_range(-3, 3), Color(.1, .08, .08)
		)
	for _k in 5:
		var x := rng.randi_range(6, 120)
		var y := rng.randi_range(46, 100)
		Paint.line2(
			s, x, y, x + rng.randi_range(4, 12), y + rng.randi_range(-2, 2), Color(.2, .32, .62)
		)
	grit(s, .04)
	return s


## Old tyres stacked five high and painted white and black, a stripe each.
func tire_wall() -> Paint.Sheet:
	var s := Paint.Sheet.new(128, 128, Color(.05, .05, .05))
	for row in 5:
		var y0 := row * 26 - 2
		var off := 0 if row % 2 == 0 else 16
		for k in 5:
			var x0 := k * 32 - off
			var white := (k + row) % 2 == 0
			var body := Color(.82, .8, .74) if white else Color(.13, .12, .12)
			for xx in range(x0, x0 + 32):
				for yy in range(y0, y0 + 26):
					var u := (xx - x0 - 16.0) / 16.0
					var v := (yy - y0 - 13.0) / 13.0
					var r := u * u + v * v
					if r > 1.0:
						continue
					var c := shade(body, .7 + .4 * (1.0 - absf(v)))
					if absf(v) > .78:
						c = shade(c, .6)
					s.put(posmod(xx, 128), yy, c)
			Paint.rect(s, x0 + 4, y0 + 12, x0 + 27, y0 + 13, Color(.05, .04, .04))
	var cloud := Paint.cloud(128, rng.randi())
	for i in 128 * 128:
		var dirt := clampf(cloud[i] - .5, 0, 1) * .8
		for k in 3:
			s.data[i * 4 + k] = int(s.data[i * 4 + k] * (1.0 - dirt) + [70, 52, 36][k] * dirt)
	grit(s, .05)
	return s


## Crushed cars stacked into a wall: flat slabs of colour, rust, a chrome strip,
## a wheel rim here and there, black gaps between.
func junk_stack() -> Paint.Sheet:
	var s := Paint.Sheet.new(128, 128, Color(.04, .04, .04))
	var paints := [
		Color(.56, .16, .12),
		Color(.2, .32, .5),
		Color(.62, .56, .3),
		Color(.3, .42, .3),
		Color(.62, .6, .56),
		Color(.4, .24, .14),
		Color(.5, .36, .14),
	]
	var y := 0
	while y < 128:
		var tall := rng.randi_range(16, 24)
		var x := -rng.randi_range(0, 30)
		while x < 128:
			var long := rng.randi_range(36, 70)
			var c: Color = paints[rng.randi() % paints.size()]
			var tilt := rng.randf_range(-.06, .06)
			for xx in range(x, x + long):
				var lift := int((xx - x) * tilt)
				for yy in range(y + 2 + lift, y + tall - 1 + lift):
					var f := .75 + .35 * sin((yy - y) / float(tall) * PI)
					s.put(posmod(xx, 128), clampi(yy, 0, 127), shade(c, f))
			var cy := y + tall / 2
			Paint.rect(s, x + 3, cy, x + long - 4, cy, Color(.78, .78, .8))
			if rng.randf() < .45:
				var rx := x + rng.randi_range(8, long - 8)
				Paint.ellipse(s, rx - 6, cy - 4, rx + 6, cy + 4, Color(.1, .1, .1))
				Paint.ellipse(s, rx - 3, cy - 2, rx + 3, cy + 2, Color(.6, .6, .62))
			x += long + rng.randi_range(1, 4)
		y += tall
	var cloud := Paint.cloud(128, rng.randi())
	for i in 128 * 128:
		var rust := clampf(cloud[i] - .5, 0, 1) * 1.4
		for k in 3:
			s.data[i * 4 + k] = int(s.data[i * 4 + k] * (1.0 - rust) + [120, 58, 28][k] * rust)
	grit(s, .07)
	return s


func garage_door() -> Paint.Sheet:
	var s := Paint.Sheet.new(128, 128)
	for y in 128:
		for x in 128:
			var slat := y % 12
			var c := Color(.55, .58, .6)
			if slat < 2:
				c = Color(.3, .32, .34)
			elif slat < 4:
				c = Color(.68, .7, .72)
			if x < 6 or x > 121:
				c = Color(.24, .22, .2)
			s.put(x, y, c)
	Paint.rect(s, 0, 0, 127, 7, Color(.2, .18, .16))
	Paint.rect(s, 54, 112, 74, 116, Color(.2, .2, .22))
	var cloud := Paint.cloud(128, rng.randi())
	for i in 128 * 128:
		var dirt := clampf(cloud[i] - .45, 0, 1) * (.4 + float(i / 128) / 128.0)
		for k in 3:
			s.data[i * 4 + k] = int(s.data[i * 4 + k] * (1.0 - dirt) + [60, 40, 26][k] * dirt)
	letters(s, "PIT", 64, 40, 3, Color8(210, 50, 36))
	grit(s, .04)
	return s


## A grandstand row's face: plank seat backs painted county blue and red.
func grandstand_riser() -> Paint.Sheet:
	var s := planks(128, 128, Color(.3, .38, .56), 16)
	for y in 128:
		for x in 128:
			if (y / 16) % 2 == 1:
				var o := (y * 128 + x) * 4
				s.data[o] = int(s.data[o] * 1.9)
				s.data[o + 1] = int(s.data[o + 1] * .55)
				s.data[o + 2] = int(s.data[o + 2] * .5)
			if x % 32 < 3:
				s.put(x, y, Color(.24, .22, .2))
	weather(s, 700, 0)
	return s


## BUZZARD BEND SPEEDWAY in bulbs on red tin: the gate's marquee tile.
func marquee() -> Paint.Sheet:
	var s := tin(128, 128, Color(.6, .1, .08))
	Paint.rect(s, 4, 22, 123, 105, Color(.12, .08, .06))
	letters(s, "BUZZARD", 64, 30, 2, Color8(255, 222, 120))
	letters(s, "BEND", 64, 50, 3, Color8(255, 240, 200))
	letters(s, "SPEEDWAY", 64, 80, 2, Color8(255, 222, 120))
	for x in range(6, 124, 6):
		for y in [12, 114]:
			Paint.ellipse(s, x - 2, y - 2, x + 2, y + 2, Color8(255, 236, 170))
	weather(s, 160, 4)
	return s


## The diner's front: ribbed stainless with a red band; 1 dark window, 2 lit.
func diner_steel(window: int) -> Paint.Sheet:
	var s := Paint.Sheet.new(128, 128)
	for y in 128:
		for x in 128:
			var rib := .82 + .18 * sin(x * .9)
			var c := shade(Color(.66, .68, .7), rib)
			if y >= 100 and y < 112:
				c = Color(.7, .12, .1)
			if y >= 18 and y < 22:
				c = Color(.86, .86, .88)
			s.put(x, y, c)
	if window > 0:
		Paint.rect(s, 20, 30, 107, 92, Color(.86, .86, .88))
		for yy in range(34, 89):
			for xx in range(24, 104):
				var c := Color(.12, .16, .2).lerp(Color(.2, .26, .3), (yy - 34) / 55.0)
				if window == 2:
					c = Color(.96, .76, .42) * (1.0 - .3 * absf(xx - 64.0) / 40.0)
					if yy < 42:
						c = Color(.7, .2, .16)
				s.put(xx, yy, Color(c.r, c.g, c.b))
		Paint.rect(s, 62, 30, 65, 92, Color(.86, .86, .88))
	grit(s, .03)
	return s


func checker_band() -> Paint.Sheet:
	var s := Paint.Sheet.new(128, 128)
	for y in 128:
		for x in 128:
			var light := ((x / 32) + (y / 32)) % 2 == 0
			s.put(x, y, Color(.86, .85, .8) if light else Color(.08, .08, .08))
	weather(s, 900, 0)
	grit(s, .04)
	return s


## Race night: a bruised purple sky, a last orange band low in the west, the
## floodlights' haze rising off the oval, pines and the grain elevator black
## against it.
func sky() -> Paint.Sheet:
	var w := 512
	var h := 116
	var s := Paint.Sheet.new(w, h)
	var cloud := Paint.cloud(128, rng.randi())
	for y in h:
		for x in w:
			var t := float(y) / h
			var c := Color(.09, .07, .13).lerp(Color(.28, .14, .2), t * t)
			var dusk := clampf(1.0 - absf(x - 120.0) / 170.0, 0, 1) * clampf((t - .5) * 2.2, 0, 1)
			c = c.lerp(Color(.62, .3, .14), dusk * .7)
			for haze_x: float in [260.0, 330.0, 420.0]:
				var hz := (
					clampf(1.0 - absf(x - haze_x) / 60.0, 0, 1) * clampf((t - .55) * 2.0, 0, 1)
				)
				c = c.lerp(Color(.62, .56, .42), hz * .35)
			var cl := cloud[(y * 128 / h) * 128 + (x * 128 / w) % 128]
			c = c.lerp(Color(.16, .12, .18), clampf(cl - .5, 0, 1) * 1.2)
			s.put(x, y, c)
	for _k in 70:
		Paint.point(s, rng.randi_range(0, w - 1), rng.randi_range(0, 40), Color(.7, .7, .76))
	var ground := Color(.03, .03, .04)
	var x := 0
	while x < w:
		var top := 96 + int(sin(x * .03) * 3.0)
		var tall := rng.randi_range(6, 18)
		for xx in range(x, mini(w, x + 6)):
			var spread := absf(xx - x - 3.0)
			for yy in range(top - tall + int(spread * 2.0), h):
				s.put(xx, yy, ground)
		x += rng.randi_range(3, 7)
	for xx in range(w):
		for yy in range(100, h):
			s.put(xx, yy, ground)
	# The grain elevator and two floodlight towers on the skyline.
	Paint.rect(s, 180, 66, 196, 101, ground)
	Paint.rect(s, 176, 60, 200, 66, ground)
	Paint.rect(s, 197, 76, 204, 101, ground)
	for fx: int in [300, 380]:
		Paint.rect(s, fx, 58, fx + 1, 101, ground)
		Paint.rect(s, fx - 5, 54, fx + 6, 58, Color(.98, .92, .7))
	return Paint.digitize(s, 6.0)


# --------------------------------------------------------------------- signs


func entry_sign() -> Paint.Sheet:
	var s := tin(150, 56, Color(.86, .82, .7))
	Paint.rect(s, 3, 3, 146, 25, Color8(168, 34, 26))
	letters(s, "BUZZARD BEND", 75, 6, 2, Color8(250, 236, 196))
	letters(s, "SPEEDWAY", 75, 29, 2, Color8(30, 26, 22), false)
	letters(s, "RACE NITE - DERBY 9PM", 75, 46, 1, Color8(168, 34, 26), false)
	bulbs(s, 6)
	frame(s, Color8(46, 34, 26))
	weather(s, 80, 6)
	return Paint.digitize(s)


func diner_sign() -> Paint.Sheet:
	var s := tin(120, 40, Color(.78, .8, .82))
	Paint.rect(s, 3, 3, 116, 22, Color8(176, 36, 30))
	letters(s, "LUGNUT'S", 60, 5, 2, Color8(255, 240, 200))
	letters(s, "EATS  PIE  COFFEE", 60, 27, 1, Color8(30, 30, 34), false)
	bulbs(s, 6, .8)
	frame(s, Color8(40, 40, 44))
	weather(s, 60, 3)
	return Paint.digitize(s)


func truckstop_sign() -> Paint.Sheet:
	var s := tin(110, 44, Color(.94, .78, .22))
	letters(s, "DIESEL", 55, 4, 2, Color8(30, 24, 20))
	letters(s, "SHOWERS  CB  ICE", 55, 22, 1, Color8(150, 30, 24), false)
	letters(s, "OPEN 24 HRS", 55, 32, 1, Color8(30, 24, 20), false)
	frame(s, Color8(60, 44, 20))
	weather(s, 70, 5)
	return Paint.digitize(s)


func fuel_price() -> Paint.Sheet:
	var s := Paint.Sheet.new(48, 56, Color8(232, 228, 214))
	frame(s, Color8(40, 40, 40))
	letters(s, "GAS", 24, 4, 1, Color8(168, 34, 26), false)
	letters(s, "59", 24, 13, 2, Color8(20, 20, 20), false)
	letters(s, "DSL", 24, 31, 1, Color8(168, 34, 26), false)
	letters(s, "64", 24, 40, 2, Color8(20, 20, 20), false)
	weather(s, 40, 2)
	return Paint.digitize(s)


func pit_row_sign() -> Paint.Sheet:
	var s := planks(120, 26, Color(.86, .82, .7), 13)
	letters(s, "PIT ROW", 60, 5, 2, Color8(168, 34, 26))
	frame(s, Color8(40, 28, 20))
	weather(s, 80, 3)
	return Paint.digitize(s)


func no_pass_sign() -> Paint.Sheet:
	var s := tin(70, 40, Color(.9, .88, .82))
	Paint.rect(s, 3, 3, 66, 14, Color8(168, 34, 26))
	letters(s, "NO PIT PASS", 35, 5, 1, Color8(250, 240, 220), false)
	letters(s, "NO ENTRY", 35, 18, 1, Color8(20, 20, 20), false)
	letters(s, "-MGMT", 35, 28, 1, Color8(20, 20, 20), false)
	weather(s, 50, 6)
	return Paint.digitize(s)


func junk_sign() -> Paint.Sheet:
	var s := tin(110, 40, Color(.42, .48, .3))
	letters(s, "BOGGS", 55, 3, 2, Color8(240, 236, 220))
	letters(s, "SALVAGE", 55, 19, 1, Color8(240, 236, 220), false)
	letters(s, "U-PULL-IT  NO REFUNDS", 55, 29, 1, Color8(250, 210, 90), false)
	frame(s, Color8(30, 30, 24))
	weather(s, 100, 9)
	return Paint.digitize(s)


func crusher_warn() -> Paint.Sheet:
	var s := tin(64, 44, Color(.96, .78, .16))
	for x in 64:
		for y in range(0, 6):
			if (x + y) / 4 % 2 == 0:
				s.put(x, y, Color8(20, 20, 20))
				s.put(x, 43 - y, Color8(20, 20, 20))
	letters(s, "KEEP", 32, 9, 1, Color8(20, 20, 20), false)
	letters(s, "CLEAR", 32, 18, 1, Color8(20, 20, 20), false)
	letters(s, "CRUSHER", 32, 28, 1, Color8(168, 34, 26), false)
	weather(s, 40, 3)
	return Paint.digitize(s)


func turn_sign(n: int) -> Paint.Sheet:
	var s := Paint.Sheet.new(40, 40, Color8(20, 20, 22))
	Paint.ellipse(s, 2, 2, 37, 37, Color8(236, 232, 220))
	Paint.ellipse(s, 5, 5, 34, 34, Color8(20, 20, 22))
	letters(s, "T" + str(n), 20, 14, 2, Color8(250, 214, 90))
	weather(s, 30, 2)
	return Paint.digitize(s)


func ad_board(top: String, bottom: String, ground: Color, ink: Color) -> Paint.Sheet:
	var s := tin(128, 30, ground)
	letters(s, top, 64, 3, 2, ink)
	letters(s, bottom, 64, 20, 1, Color8(240, 236, 224), false)
	frame(s, shade(ground, .5))
	weather(s, 60, 4)
	return Paint.digitize(s)


func standings_board() -> Paint.Sheet:
	var s := Paint.Sheet.new(90, 64, Color8(24, 30, 26))
	frame(s, Color8(90, 70, 40))
	letters(s, "LAP 47/50", 45, 4, 1, Color8(250, 214, 90), false)
	var rows := ["1  00 BOGGS", "2  42 PRUITT", "3   7 LEDOUX", "4  13 SKAGGS"]
	for i in rows.size():
		letters(s, rows[i], 45, 16 + i * 11, 1, Color8(236, 232, 220), false)
	weather(s, 40, 2)
	return Paint.digitize(s)


func concession_menu() -> Paint.Sheet:
	var s := planks(80, 60, Color(.24, .18, .14), 10)
	letters(s, "SNAX", 40, 3, 2, Color8(250, 214, 90))
	var rows := ["CORN DOG  1", "CHILI DOG 1", "NACHOS   75", "BEER  WARM"]
	for i in rows.size():
		letters(s, rows[i], 40, 21 + i * 9, 1, Color8(236, 232, 220), false)
	frame(s, Color8(30, 20, 14))
	weather(s, 50, 2)
	return Paint.digitize(s)


func figure8_sign() -> Paint.Sheet:
	var s := tin(100, 44, Color(.14, .14, .16))
	letters(s, "FIGURE 8", 50, 3, 2, Color8(250, 214, 90))
	letters(s, "DEMOLITION DERBY", 50, 21, 1, Color8(236, 60, 40), false)
	letters(s, "LAST CAR RUNNIN' WINS", 50, 31, 1, Color8(236, 232, 220), false)
	bulbs(s, 5, .6)
	weather(s, 60, 6)
	return Paint.digitize(s)


func camping_sign() -> Paint.Sheet:
	var s := planks(80, 30, Color(.6, .44, .28), 10)
	letters(s, "INFIELD", 40, 3, 1, Color8(240, 236, 220), false)
	letters(s, "CAMPING 5 BUX", 40, 13, 1, Color8(240, 236, 220), false)
	letters(s, "NO GLASS", 40, 22, 1, Color8(168, 34, 26), false)
	frame(s, Color8(40, 28, 20))
	weather(s, 60, 3)
	return Paint.digitize(s)


func jump_sign() -> Paint.Sheet:
	var s := tin(80, 36, Color(.46, .2, .5))
	letters(s, "MONSTER", 40, 3, 1, Color8(250, 214, 90), false)
	letters(s, "JUMP", 40, 13, 2, Color8(255, 240, 200))
	weather(s, 70, 5)
	return Paint.digitize(s)


func start_finish() -> Paint.Sheet:
	var s := Paint.Sheet.new(160, 30)
	for y in 30:
		for x in 160:
			var light := ((x / 6) + (y / 6)) % 2 == 0
			s.put(x, y, Color8(230, 228, 220) if light else Color8(16, 16, 16))
	Paint.rect(s, 30, 6, 129, 23, Color8(168, 34, 26))
	letters(s, "START / FINISH", 80, 11, 1, Color8(250, 240, 220), false)
	weather(s, 100, 4)
	return Paint.digitize(s)


func beer_sign() -> Paint.Sheet:
	var s := Paint.Sheet.new(60, 26, Color8(14, 12, 16))
	Paint.rounded_rect(s, 1, 1, 58, 24, 6, Color8(40, 18, 30))
	letters(s, "COLD BEER", 30, 9, 1, Color8(255, 90, 120), false)
	Paint.outline(s, 3, 3, 56, 22, Color8(120, 220, 255))
	return Paint.digitize(s)


func booth_sign() -> Paint.Sheet:
	var s := tin(100, 26, Color(.2, .3, .5))
	letters(s, "ANNOUNCER", 50, 3, 1, Color8(240, 236, 220), false)
	letters(s, "WSPD AM 1390", 50, 14, 1, Color8(250, 214, 90), false)
	frame(s, Color8(20, 24, 30))
	weather(s, 40, 3)
	return Paint.digitize(s)


func arrow_sign(text: String, right: bool) -> Paint.Sheet:
	var s := Paint.Sheet.new(84, 24)
	var pts := PackedVector2Array(
		[Vector2(0, 3), Vector2(66, 3), Vector2(83, 12), Vector2(66, 21), Vector2(0, 21)]
	)
	if not right:
		for i in pts.size():
			pts[i] = Vector2(83 - pts[i].x, pts[i].y)
	Paint.polygon(s, pts, Color8(226, 220, 200))
	letters(s, text, 42 + (-4 if right else 4), 8, 1, Color8(150, 30, 24), false)
	weather(s, 40, 3)
	return Paint.digitize(s)


func tanks_sign() -> Paint.Sheet:
	var s := tin(90, 34, Color(.86, .84, .76))
	Paint.rect(s, 3, 3, 86, 14, Color8(168, 34, 26))
	letters(s, "RACE FUEL", 45, 5, 1, Color8(250, 240, 220), false)
	letters(s, "110 PROOF", 45, 18, 1, Color8(20, 20, 20), false)
	letters(s, "NO SMOKIN", 45, 26, 1, Color8(168, 34, 26), false)
	weather(s, 50, 7)
	return Paint.digitize(s)


func points_board() -> Paint.Sheet:
	var s := planks(70, 50, Color(.82, .8, .72), 10)
	letters(s, "POINTS", 35, 3, 1, Color8(150, 30, 24), false)
	var rows := ["BOGGS  412", "PRUITT 388", "LEDOUX 301"]
	for i in rows.size():
		letters(s, rows[i], 35, 15 + i * 10, 1, Color8(30, 24, 20), false)
	frame(s, Color8(40, 28, 20))
	weather(s, 60, 2)
	return Paint.digitize(s)


# --------------------------------------------------------------------- shots


func fx_wrench() -> Paint.Sheet:
	var s := Paint.Sheet.new(24, 24)
	Paint.line(s, PackedVector2Array([Vector2(3, 3), Vector2(20, 20)]), Color8(200, 202, 206), 3.0)
	Paint.line(s, PackedVector2Array([Vector2(20, 3), Vector2(3, 20)]), Color8(170, 172, 178), 3.0)
	for p: Vector2i in [Vector2i(3, 3), Vector2i(20, 20), Vector2i(20, 3), Vector2i(3, 20)]:
		Paint.ellipse(s, p.x - 2, p.y - 2, p.x + 2, p.y + 2, Color8(120, 122, 128))
	Paint.point(s, 11, 11, Color8(250, 250, 250))
	return Paint.digitize(s)


func fx_tire() -> Paint.Sheet:
	var s := Paint.Sheet.new(24, 24)
	Paint.ellipse(s, 1, 1, 22, 22, Color8(22, 22, 22))
	Paint.ellipse(s, 3, 3, 20, 20, Color8(46, 44, 42))
	Paint.ellipse(s, 7, 7, 16, 16, Color8(196, 190, 170))
	Paint.ellipse(s, 9, 9, 14, 14, Color8(90, 88, 84))
	for k in 8:
		var a := k * TAU / 8.0
		Paint.point(s, 11.5 + cos(a) * 9.5, 11.5 + sin(a) * 9.5, Color8(70, 66, 60))
	return Paint.digitize(s)


func fx_flare() -> Paint.Sheet:
	var s := Paint.Sheet.new(24, 24)
	Paint.ellipse(s, 2, 2, 21, 21, Color8(200, 60, 30))
	Paint.ellipse(s, 5, 5, 18, 18, Color8(255, 140, 60))
	Paint.ellipse(s, 8, 8, 15, 15, Color8(255, 236, 170))
	return Paint.digitize(s)
