## Draw the mothership's own walls, floors and painted signs (chapter 7): the
## hull the greys riveted together and patched with whatever tin they hauled
## up from the county, their buzzing panels, the tractor beam, and the signs
## they lettered in their own glyphs with the English under it, spelled the
## way they heard it.
##
##   godot --headless --path godot --script res://tools/art/build_ship_art.gd [-- out=<dir>]
##
## Tiles go to assets/tiles (listed in data/index.json and
## assets_gen/tiles_index.json), signs and marks to assets/art. Seeded, so a
## rerun gives the same files. effects.cfg makes the panels, the beam and the
## lit signs glow and buzz. Then run tools/pack_assets.gd.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")
const INK := Color8(236, 226, 196)
const GLYPH := Color8(120, 255, 160)

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 2097
	var art := Paint.repo("assets/art")
	var tiles := Paint.repo("assets/tiles")
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			art = String(arg).substr(4)
			tiles = art
	DirAccess.make_dir_recursive_absolute(art)
	DirAccess.make_dir_recursive_absolute(tiles)
	var made_tiles := {
		"ship_hull": hull(),
		"ship_tin": tin_wall(),
		"ship_rib": rib(),
		"ship_panel": panel_wall(),
		"ship_core": core_wall(),
		"ship_screen": screen(),
		"ship_deck": deck(),
		"ship_grate": grate(),
		"ship_ceiling": ceiling(),
		"ship_door": hatch(),
		"ship_beam": beam(),
		"ship_edge": edge(),
		"ship_pod": pod_wall(),
		"ship_vat": vat(),
		"ship_lino": lino(),
	}
	for name: String in made_tiles:
		(made_tiles[name] as Paint.Sheet).save(tiles.path_join(name + ".png"))
	var signs := {
		"ship_sign_tractor": sign_board("TRACTOR BEAM", "MIND YER TRUCK", Color8(168, 34, 26)),
		"ship_sign_specimens": sign_board("SPECIMENS", "DO NOT TAP GLASS", Color8(40, 92, 70)),
		"ship_sign_probe": sign_board("PROBE LAB", "HOLD STILL HOOMAN", Color8(112, 40, 96)),
		"ship_sign_corn": sign_board("CORN DECK", "NO HUSKIN", Color8(120, 104, 30)),
		"ship_sign_engine": sign_board("ENGINE", "RUNS ON 180 PROOF", Color8(150, 70, 26)),
		"ship_sign_mess": sign_board("CREW MESS", "CORN DOG TUESDAY", Color8(46, 70, 110)),
		"ship_sign_trophy":
		sign_board("TROPHY ROOM", "DO NOT SIT IN EXHIBITS", Color8(110, 84, 30)),
		"ship_sign_bridge": sign_board("BRIDGE", "CAPTAIN NAPPIN", Color8(36, 60, 90)),
		"ship_sign_core": sign_board("THE CORE", "MAWS ROOM. KNOCK", Color8(130, 20, 24)),
		"ship_sign_escape":
		sign_board("ESCAPE OUTHOUSE", "PULL CORD HOLD NOSE", Color8(60, 96, 40)),
		"ship_sign_quarters": sign_board("CREW BUNKS", "LIGHTS OUT AT NINE", Color8(70, 56, 90)),
		"ship_sign_cargo": sign_board("CARGO HOLD", "FINDERS KEEPERS", Color8(96, 80, 50)),
		"ship_sign_ring": sign_board("RING DECK", "THIS WAY ROUND", Color8(50, 82, 86)),
		"ship_arrow_left": arrow(-1),
		"ship_arrow_right": arrow(1),
		"ship_hazard": hazard_sign(),
		"ship_wanted": wanted(),
		"ship_memorial": memorial(),
		"ship_chart": chart(),
		"ship_menu": menu_board(),
		"ship_plaque_outhouse": plaque("OUTHOUSE", "ODOR: YES"),
		"ship_plaque_flamingo": plaque("FLAMINGO", "NOT A REAL BIRD"),
		"ship_plaque_gnome": plaque("LAWN ELF", "WATCHES YOU SLEEP"),
		"ship_plaque_bus": plaque("SCHOOL BUS", "FULL OF GUM"),
		"ship_cow_label": plaque("SPECIMEN 4417", "COW. SAYS MOO"),
		"ship_glyphs_a": glyph_panel(3),
		"ship_glyphs_b": glyph_panel(5),
		"ship_deck_four": sign_board("DECK 4", "YOU ARE HERE", Color8(70, 70, 64)),
		"ship_jukebox_note": note_card("JUKEBOX", "1 COW = 3 SONGS"),
		"ship_shine_note": note_card("FUEL", "SHINE ONLY. NO DIESEL"),
	}
	# The station boards are modelled quest consoles now (build_quest_art.gd).
	# They are still drawn, and dropped, so the pictures after them roll the
	# same dice and come out as they always have.
	for title in ["SHINE VALVE", "TUBE RELEASE", "CORE IRIS", "LAUNCH"]:
		station_board(title, false)
		station_board(title, true)
	signs["mark_slam"] = slam_mark()
	signs["mark_beam"] = beam_mark()
	signs["fx_beam_column"] = beam_column()
	for name: String in signs:
		(signs[name] as Paint.Sheet).save(art.path_join(name + ".png"))
	print(
		(
			"ship art: %d tiles to %s, %d pictures to %s"
			% [made_tiles.size(), tiles, signs.size(), art]
		)
	)
	quit()


# ------------------------------------------------------------------ helpers


func _shade(c: Color, f: float) -> Color:
	return Color(clampf(c.r * f, 0, 1), clampf(c.g * f, 0, 1), clampf(c.b * f, 0, 1), c.a)


## Grain over a tile: each texel nudged a little brighter or darker.
func _grain(s: Paint.Sheet, amount: float) -> void:
	var g := Paint.noise(rng.randi(), s.w * s.h, amount)
	for i in s.w * s.h:
		var f := 1.0 + g[i]
		for k in 3:
			s.data[i * 4 + k] = clampi(int(s.data[i * 4 + k] * f), 0, 255)


## Darken (f < 1) or lighten a box of a sheet in place.
func _tone(s: Paint.Sheet, x0: int, y0: int, x1: int, y1: int, f: float) -> void:
	for y in range(maxi(0, y0), mini(s.h, y1 + 1)):
		for x in range(maxi(0, x0), mini(s.w, x1 + 1)):
			var o := (y * s.w + x) * 4
			for k in 3:
				s.data[o + k] = clampi(int(s.data[o + k] * f), 0, 255)


func _rivet(s: Paint.Sheet, x: int, y: int) -> void:
	Paint.point(s, x, y, Color8(176, 172, 156))
	Paint.point(s, x + 1, y + 1, Color8(30, 30, 28))
	Paint.point(s, x + 1, y, Color8(120, 118, 106))


## Rust run down a wall from a point, thinning as it goes.
func _streak(s: Paint.Sheet, x: int, y: int, length: int) -> void:
	for k in length:
		var f := 1.0 - float(k) / length
		var o := (mini(s.h - 1, y + k) * s.w + clampi(x, 0, s.w - 1)) * 4
		s.data[o] = clampi(int(s.data[o] * (1.0 - .3 * f) + 120 * .3 * f), 0, 255)
		s.data[o + 1] = clampi(int(s.data[o + 1] * (1.0 - .3 * f) + 56 * .3 * f), 0, 255)
		s.data[o + 2] = clampi(int(s.data[o + 2] * (1.0 - .3 * f) + 24 * .3 * f), 0, 255)


## Sheet tin: flat colour with ridges, rust creeping in from the edges.
func tin(width: int, height: int, base: Color, ridges := true) -> Paint.Sheet:
	var s := Paint.Sheet.new(width, height)
	var blot := Paint.cloud(64, rng.randi())
	var grit := Paint.noise(rng.randi(), width * height, .05)
	for y in height:
		for x in width:
			var edge := minf(minf(x, width - 1 - x), minf(y, height - 1 - y)) / 5.0
			var b := blot[(y * 64 / height) * 64 + (x * 64 / width)]
			var rust := clampf(b * 1.3 - clampf(edge, 0, 1) * .8 - .1, 0, 1)
			var c := base.lerp(Color(.52, .26, .12), rust)
			var f := 1.0 + grit[y * width + x] + (sin(x * 1.4) * .05 if ridges else 0.0)
			s.put(x, y, Color(c.r * f, c.g * f, c.b * f))
	return s


## Block letters `scale` times their size, with a drop shadow; centred on x.
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
		var colour := Color(.06, .04, .03, .85) if pass_k == 1 else ink
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


## A row of the greys' glyphs: each one a stroke and hooks picked by the
## dice, `count` of them centred on x, `scale` texels a stroke.
func glyphs(s: Paint.Sheet, count: int, x: int, y: int, scale: int, ink: Color) -> void:
	var width := count * 6 * scale - scale
	var at := x - width / 2
	for _k in count:
		var bits := rng.randi()
		# A spine down one side or the middle, then hooks, bars and dots off it.
		var spine: int = [0, 2, 4][bits % 3]
		for r in 7:
			_cell(s, at, y, spine, r, scale, ink)
		for r in 7:
			for c in 5:
				if c == spine:
					continue
				var lit := ((bits >> ((r * 5 + c) % 28)) & 1) == 1
				var keep: bool = (r == 0 or r == 3 or r == 6) or c == 4 - spine
				if lit and keep:
					_cell(s, at, y, c, r, scale, ink)
		at += 6 * scale


func _cell(s: Paint.Sheet, x: int, y: int, c: int, r: int, scale: int, ink: Color) -> void:
	for yy in scale:
		for xx in scale:
			_blend(s, x + c * scale + xx, y + r * scale + yy, ink)


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


func bolts(s: Paint.Sheet) -> void:
	for p in [
		Vector2i(3, 3), Vector2i(s.w - 4, 3), Vector2i(3, s.h - 4), Vector2i(s.w - 4, s.h - 4)
	]:
		_rivet(s, p.x, p.y)


# -------------------------------------------------------------------- walls


## The hull: riveted plates, rust run down from the rivets, and sheet tin
## the crew nailed over the holes (one of them somebody's licence plate).
func hull() -> Paint.Sheet:
	var s := Paint.Sheet.new(128, 128)
	var blot := Paint.cloud(128, rng.randi())
	for y in 128:
		for x in 128:
			var d := blot[y * 128 + x]
			var plate := (x / 64 + y / 43) % 2
			var c := Color8(102, 104, 92) if plate == 0 else Color8(110, 108, 94)
			var f := .82 + d * .3 - (.12 if y > 112 else 0.0)
			s.put(x, y, _shade(c, f))
	_grain(s, .05)
	# Seams between the plates, with a bead of weld under each.
	for y in [0, 43, 86]:
		_tone(s, 0, y, 127, y + 1, .45)
		_tone(s, 0, y + 2, 127, y + 2, 1.25)
	for x in [0, 64]:
		_tone(s, x, 0, x + 1, 127, .45)
		_tone(s, x + 2, 0, x + 2, 127, 1.2)
	for y in [5, 48, 91]:
		for x in range(6, 128, 9):
			_rivet(s, x, y)
			if rng.randf() < .3:
				_streak(s, x, y + 2, rng.randi_range(8, 26))
	for y in [38, 81, 124]:
		for x in range(6, 128, 9):
			_rivet(s, x, y)
	# The patches: a corrugated sheet, a flat one, and the plate.
	var corr := tin(34, 26, Color(.62, .58, .5))
	s.paste(corr, 12, 54)
	for x in range(13, 46, 4):
		Paint.point(s, x, 55, Color8(40, 36, 30))
		Paint.point(s, x, 78, Color8(40, 36, 30))
	var flat := tin(22, 30, Color(.46, .5, .42), false)
	s.paste(flat, 88, 10)
	for p in [Vector2i(89, 11), Vector2i(108, 11), Vector2i(89, 38), Vector2i(108, 38)]:
		Paint.point(s, p.x, p.y, Color8(30, 28, 26))
	Paint.rect(s, 80, 96, 111, 111, Color8(214, 184, 74))
	Paint.outline(s, 80, 96, 111, 111, Color8(70, 50, 24))
	letters(s, "HIK 207", 96, 101, 1, Color8(40, 30, 24), false)
	weather(s, 120, 3)
	return Paint.digitize(s)


## Mismatched tin in strips, ridged, the joins nailed, a glyph daubed on.
func tin_wall() -> Paint.Sheet:
	var s := Paint.Sheet.new(128, 128)
	var colours := [
		Color(.56, .26, .18), Color(.44, .52, .44), Color(.6, .6, .58), Color(.5, .42, .3)
	]
	var x := 0
	var k := 0
	while x < 128:
		var w := [30, 34, 28, 36][k % 4] as int
		var strip := tin(w, 128, colours[k % colours.size()])
		s.paste(strip, x, 0)
		for y in range(4, 128, 12):
			Paint.point(s, x + 2, y, Color8(28, 26, 24))
		_tone(s, x, 0, x, 127, .5)
		x += w
		k += 1
	glyphs(s, 3, 64, 56, 3, Color(.85, .82, .7, .7))
	weather(s, 90, 4)
	return Paint.digitize(s)


## The ring deck's bulkhead: ribs either side, a lit strip along the middle.
func rib() -> Paint.Sheet:
	var s := Paint.Sheet.new(128, 128)
	var blot := Paint.cloud(128, rng.randi())
	for y in 128:
		for x in 128:
			var f := .8 + blot[y * 128 + x] * .3
			s.put(x, y, _shade(Color8(70, 74, 72), f))
	_grain(s, .05)
	for side in [0, 1]:
		var x0 := 0 if side == 0 else 116
		for xx in range(x0, x0 + 12):
			var curve := sin(float(xx - x0) / 12.0 * PI)
			for y in 128:
				var o := (y * 128 + xx) * 4
				for c in 3:
					s.data[o + c] = clampi(int(48 + 70 * curve + (y % 16) * .4), 0, 255)
		for y in range(6, 128, 16):
			_rivet(s, x0 + 5, y)
	# The light strip: a pale green tube behind a grille.
	Paint.rect(s, 12, 52, 115, 63, Color8(24, 30, 28))
	for xx in range(14, 114):
		for yy in range(54, 62):
			var lit := 1.0 - absf(yy - 57.5) / 5.0
			s.put(xx, yy, Paint.rgb(90 + 150 * lit, 200 + 55 * lit, 140 + 90 * lit))
	for xx in range(16, 114, 6):
		Paint.rect(s, xx, 53, xx, 62, Color8(30, 36, 34))
	Paint.rect(s, 12, 96, 115, 99, Color8(40, 42, 40))
	glyphs(s, 4, 64, 104, 2, Color8(180, 200, 170))
	weather(s, 60, 0)
	return Paint.digitize(s)


## A bank of buttons, dials and blinking lights, a CB radio screwed in.
func panel_wall() -> Paint.Sheet:
	var s := Paint.Sheet.new(128, 128, Color8(46, 50, 54))
	_grain(s, .06)
	Paint.rect(s, 4, 4, 123, 123, Color8(34, 38, 42))
	Paint.outline(s, 4, 4, 123, 123, Color8(90, 96, 96))
	var lights := [Color8(255, 70, 50), Color8(255, 200, 70), Color8(110, 255, 140)]
	for row in 4:
		for col in 9:
			var x := 10 + col * 12
			var y := 10 + row * 11
			var lit := rng.randf() < .55
			var c: Color = lights[(row + col * 2) % 3]
			Paint.rect(s, x, y, x + 6, y + 5, c if lit else _shade(c, .3))
			Paint.outline(s, x - 1, y - 1, x + 7, y + 6, Color8(20, 22, 24))
	# Dials with their needles.
	for i in 3:
		var cx := 22 + i * 30
		Paint.ellipse(s, cx - 10, 60, cx + 10, 80, Color8(200, 196, 170))
		Paint.arc(s, cx - 10, 60, cx + 10, 80, 0, 360, Color8(30, 30, 30), 1)
		Paint.line2(s, cx, 70, cx + rng.randi_range(-7, 7), 63, Color8(160, 30, 24), 1)
	# The CB radio, its mic on a coiled cord, held in with duct tape.
	Paint.rect(s, 98, 58, 120, 76, Color8(30, 30, 30))
	Paint.rect(s, 100, 61, 112, 66, Color8(255, 150, 60))
	letters(s, "CB", 108, 69, 1, INK, false)
	Paint.rect(s, 94, 56, 124, 59, Color8(150, 150, 140))
	for k in 8:
		Paint.point(s, 104 + k % 2, 78 + k * 2, Color8(20, 20, 20))
	glyphs(s, 6, 64, 92, 2, GLYPH)
	for k in 6:
		var x := 12 + k * 18
		Paint.rect(s, x, 112, x + 10, 117, lights[k % 3] if k % 2 == 0 else Color8(60, 60, 60))
	weather(s, 50, 2)
	return Paint.digitize(s)


## The core's curved plates with green conduits climbing them.
func core_wall() -> Paint.Sheet:
	# The core's walls are tall (the tile stretches up eight cells of them), so
	# one plate a tile, banded across in four, one fat conduit up its middle.
	var s := Paint.Sheet.new(128, 128)
	var blot := Paint.cloud(128, rng.randi())
	for y in 128:
		for x in 128:
			var curve := .7 + .36 * sin(float(x) / 128.0 * PI)
			s.put(x, y, _shade(Color8(84, 72, 80), curve * (.86 + blot[y * 128 + x] * .24)))
	_grain(s, .05)
	_tone(s, 0, 0, 3, 127, .45)
	_tone(s, 124, 0, 127, 127, .6)
	for y in [0, 32, 64, 96]:
		_tone(s, 0, y, 127, y + 2, .5)
		_tone(s, 0, y + 3, 127, y + 3, 1.25)
		for x in range(10, 120, 14):
			_rivet(s, x, y + 6)
	for y in 128:
		for xx in range(57, 72):
			var lit := 1.0 - absf(xx - 64.0) / 8.0
			if lit < .35:
				s.put(xx, y, Color8(34, 34, 36))
				continue
			s.put(xx, y, Paint.rgb(50 + 80 * lit, 120 + 100 * lit, 80 + 80 * lit))
	for y in [16, 48, 80, 112]:
		Paint.rect(s, 50, y - 4, 78, y + 4, Color8(56, 52, 50))
		Paint.rect(s, 52, y - 2, 76, y + 2, Color8(150, 116, 56))
	weather(s, 50, 0)
	return Paint.digitize(s)


## The viewscreen: the county from orbit, circled.
func screen() -> Paint.Sheet:
	var s := Paint.Sheet.new(128, 128, Color8(6, 8, 16))
	for _k in 70:
		Paint.point(s, rng.randi_range(4, 123), rng.randi_range(4, 80), Paint.rgb(200, 210, 230))
	for y in range(70, 128):
		for x in 128:
			var d := Vector2(x - 64, y - 220).length()
			if d < 150:
				var land := sin(x * .17 + y * .09) + sin(x * .05 - y * .21) > .4
				var c := Color8(70, 120, 60) if land else Color8(40, 70, 130)
				if d > 146:
					c = Color8(150, 190, 230)
				s.put(x, y, c)
	Paint.arc(s, 66, 92, 90, 112, 0, 360, Color8(255, 60, 40), 2)
	Paint.line2(s, 92, 90, 106, 76, Color8(255, 60, 40), 2)
	letters(s, "HICKSTON", 64, 10, 1, Color8(255, 210, 120))
	glyphs(s, 5, 64, 22, 2, GLYPH)
	for y in range(0, 128, 3):
		_tone(s, 0, y, 127, y, .8)
	Paint.outline(s, 0, 0, 127, 127, Color8(80, 84, 88))
	Paint.outline(s, 1, 1, 126, 126, Color8(40, 42, 44))
	return Paint.digitize(s)


## The deck plates: tread, seams, spilt shine.
func deck() -> Paint.Sheet:
	var s := Paint.Sheet.new(128, 128)
	var blot := Paint.cloud(128, rng.randi())
	for y in 128:
		for x in 128:
			var tread := 1.08 if ((x + y) % 8 < 2 and (x / 4 + y / 4) % 2 == 0) else 1.0
			var f := (.8 + blot[y * 128 + x] * .3) * tread
			s.put(x, y, _shade(Color8(88, 86, 78), f))
	_grain(s, .05)
	for v in [0, 64]:
		_tone(s, v, 0, v + 1, 127, .5)
		_tone(s, 0, v, 127, v + 1, .5)
	for p in [Vector2i(4, 4), Vector2i(60, 4), Vector2i(4, 60), Vector2i(60, 60)]:
		for q in [Vector2i(0, 0), Vector2i(64, 0), Vector2i(0, 64), Vector2i(64, 64)]:
			_rivet(s, p.x + q.x, p.y + q.y)
	for _k in 3:
		var cx := rng.randi_range(10, 118)
		var cy := rng.randi_range(10, 118)
		for y in range(cy - 9, cy + 9):
			for x in range(cx - 12, cx + 12):
				if Vector2((x - cx) / 12.0, (y - cy) / 9.0).length() < .9 + .1 * sin(x + y):
					_tone(s, posmod(x, 128), posmod(y, 128), posmod(x, 128), posmod(y, 128), .78)
	return Paint.digitize(s)


## Grating over a glow below.
func grate() -> Paint.Sheet:
	var s := Paint.Sheet.new(128, 128)
	for y in 128:
		for x in 128:
			var glow := .5 + .5 * sin(x * .05) * sin(y * .07)
			s.put(x, y, Paint.rgb(20 + 30 * glow, 40 + 70 * glow, 30 + 40 * glow))
	for v in range(0, 128, 8):
		Paint.rect(s, v, 0, v + 2, 127, Color8(96, 98, 92))
		Paint.rect(s, 0, v, 127, v + 1, Color8(80, 82, 76))
		_tone(s, v + 2, 0, v + 2, 127, .6)
	_grain(s, .06)
	return Paint.digitize(s)


## Ceiling plates crossed by pipes, a lamp grille between them.
func ceiling() -> Paint.Sheet:
	var s := Paint.Sheet.new(128, 128)
	var blot := Paint.cloud(128, rng.randi())
	for y in 128:
		for x in 128:
			s.put(x, y, _shade(Color8(58, 58, 56), .8 + blot[y * 128 + x] * .3))
	_grain(s, .05)
	for py in [18, 92]:
		for y in range(py - 6, py + 7):
			var round_f := cos(float(y - py) / 7.0 * PI * .5)
			for x in 128:
				s.put(x, y, Paint.rgb(70 + 70 * round_f, 66 + 60 * round_f, 58 + 44 * round_f))
		for x in range(8, 128, 32):
			Paint.rect(s, x, py - 7, x + 3, py + 7, Color8(40, 38, 34))
	Paint.rect(s, 44, 44, 84, 66, Color8(30, 30, 30))
	for x in range(46, 84, 4):
		Paint.rect(s, x, 46, x + 1, 64, Color8(200, 190, 150))
	_tone(s, 0, 0, 127, 1, .5)
	return Paint.digitize(s)


## A hatch: hazard stripes along the foot, a porthole, PUSH crossed out for PULL.
func hatch() -> Paint.Sheet:
	var s := tin(128, 128, Color(.42, .44, .4), false)
	Paint.outline(s, 6, 4, 121, 127, Color8(30, 30, 28))
	Paint.outline(s, 8, 6, 119, 125, Color8(110, 112, 100))
	for y in range(104, 124):
		for x in range(9, 119):
			var band := ((x + y) / 8) % 2 == 0
			s.put(x, y, Color8(220, 180, 40) if band else Color8(30, 26, 20))
	Paint.ellipse(s, 44, 16, 84, 52, Color8(40, 40, 38))
	Paint.ellipse(s, 48, 20, 80, 48, Color8(60, 140, 100))
	Paint.ellipse(s, 52, 24, 62, 32, Color8(170, 230, 190))
	letters(s, "PUSH", 64, 62, 2, Color8(220, 216, 200))
	Paint.line2(s, 40, 72, 88, 62, Color8(170, 30, 24), 2)
	letters(s, "PULL", 64, 80, 2, Color8(200, 40, 30))
	for y in [10, 64, 118]:
		_rivet(s, 12, y)
		_rivet(s, 114, y)
	weather(s, 80, 3)
	return Paint.digitize(s)


## The tractor beam: pale green light streaming up, motes caught in it.
func beam() -> Paint.Sheet:
	var s := Paint.Sheet.new(128, 128)
	for y in 128:
		for x in 128:
			var band := .55 + .45 * sin(x * .19 + sin(y * .03) * 2.0)
			var core := .6 + .4 * sin(float(x) / 128.0 * PI * 4.0)
			var v := band * core
			s.put(x, y, Paint.rgb(80 + 120 * v, 190 + 65 * v, 140 + 90 * v))
	for _k in 60:
		var x := rng.randi_range(0, 127)
		var y := rng.randi_range(0, 125)
		Paint.rect(s, x, y, x, y + 2, Color8(240, 255, 240))
	return Paint.digitize(s)


## A step's edge: hazard stripes worn through to the steel.
func edge() -> Paint.Sheet:
	var s := Paint.Sheet.new(128, 128)
	for y in 128:
		for x in 128:
			var band := ((x + y) / 16) % 2 == 0
			s.put(x, y, Color8(196, 160, 40) if band else Color8(34, 30, 24))
	var blot := Paint.cloud(64, rng.randi())
	for y in 128:
		for x in 128:
			if blot[(y / 2) * 64 + x / 2] > .7:
				s.put(x, y, Color8(96, 96, 90))
	_grain(s, .07)
	_tone(s, 0, 0, 127, 6, 1.3)
	return Paint.digitize(s)


## A pod in the wall: a rounded door with a lit porthole and somebody in it.
func pod_wall() -> Paint.Sheet:
	var s := Paint.Sheet.new(128, 128, Color8(52, 54, 56))
	_grain(s, .05)
	Paint.rounded_rect(s, 18, 6, 110, 124, 40, Color8(70, 74, 72))
	Paint.rounded_rect(s, 24, 12, 104, 118, 36, Color8(84, 88, 84))
	Paint.ellipse(s, 40, 28, 88, 76, Color8(30, 34, 30))
	Paint.ellipse(s, 44, 32, 84, 72, Color8(90, 230, 140))
	# A grey waiting its turn, pressed to the glass.
	Paint.ellipse(s, 54, 38, 74, 62, Color8(60, 90, 70))
	Paint.ellipse(s, 57, 46, 63, 52, Color8(10, 20, 14))
	Paint.ellipse(s, 65, 46, 71, 52, Color8(10, 20, 14))
	Paint.rect(s, 30, 92, 98, 96, Color8(196, 160, 40))
	glyphs(s, 3, 64, 100, 2, GLYPH)
	for y in [16, 64, 112]:
		_rivet(s, 10, y)
		_rivet(s, 116, y)
	return Paint.digitize(s)


## Green glass: a vat or a tank's side, bubbles rising, brass bands.
func vat() -> Paint.Sheet:
	var s := Paint.Sheet.new(128, 128)
	for y in 128:
		for x in 128:
			var curve := .6 + .5 * sin(float(x) / 128.0 * PI)
			s.put(x, y, Paint.rgb(40 * curve, 150 * curve, 90 * curve))
	for _k in 40:
		var x := rng.randi_range(6, 120)
		var y := rng.randi_range(14, 110)
		var r := rng.randi_range(1, 3)
		Paint.ellipse(s, x - r, y - r, x + r, y + r, Color8(170, 255, 200))
	for y0 in [0, 116]:
		Paint.rect(s, 0, y0, 127, y0 + 11, Color8(150, 116, 56))
		_tone(s, 0, y0 + 9, 127, y0 + 11, .6)
		for x in range(6, 128, 12):
			_rivet(s, x, y0 + 5)
	Paint.rect(s, 20, 12, 27, 115, Color8(150, 230, 190))
	return Paint.digitize(s)


## Somebody's kitchen linoleum, hauled up and laid crooked.
func lino() -> Paint.Sheet:
	var s := Paint.Sheet.new(128, 128)
	for y in 128:
		for x in 128:
			var check := (x / 16 + y / 16) % 2 == 0
			s.put(x, y, Color8(196, 170, 96) if check else Color8(112, 76, 46))
	_grain(s, .06)
	var blot := Paint.cloud(128, rng.randi())
	for i in 128 * 128:
		var f := .78 + blot[i] * .3
		for k in 3:
			s.data[i * 4 + k] = clampi(int(s.data[i * 4 + k] * f), 0, 255)
	for _k in 6:
		var x := rng.randi_range(4, 123)
		var y := rng.randi_range(4, 123)
		Paint.ellipse(s, x - 2, y - 1, x + 2, y + 1, Color8(40, 28, 20))
	return Paint.digitize(s)


# -------------------------------------------------------------------- signs


## A painted tin board: glyphs up top, the English big under them, a smaller
## line under that, bolted at the corners, shot at.
func sign_board(title: String, line: String, ground: Color) -> Paint.Sheet:
	var wide := maxi(PixelType.text_width(title) * 2, PixelType.text_width(line)) + 16
	var s := tin(wide, 40, Color(ground.r, ground.g, ground.b), false)
	glyphs(s, mini(8, title.length()), wide / 2, 3, 1, Color(.6, 1.0, .7))
	letters(s, title, wide / 2, 12, 2, INK)
	letters(s, line, wide / 2, 29, 1, Color8(250, 220, 140), false)
	frame(s, _shade(ground, .4))
	bolts(s)
	weather(s, wide / 2, 2)
	return Paint.digitize(s)


func arrow(way: int) -> Paint.Sheet:
	var s := tin(48, 22, Color(.3, .34, .32), false)
	var tip := 44 if way > 0 else 3
	var tail := 6 if way > 0 else 41
	Paint.rect(s, mini(tip, tail) + 6, 8, maxi(tip, tail) - 6, 13, GLYPH)
	Paint.polygon(
		s,
		PackedVector2Array(
			[Vector2(tip, 11), Vector2(tip - way * 12, 2), Vector2(tip - way * 12, 19)]
		),
		GLYPH
	)
	frame(s, Color8(20, 24, 22))
	weather(s, 20, 1)
	return Paint.digitize(s)


func hazard_sign() -> Paint.Sheet:
	var s := Paint.Sheet.new(70, 40)
	for y in 40:
		for x in 70:
			var band := ((x + y) / 6) % 2 == 0
			s.put(x, y, Color8(220, 180, 40) if band else Color8(30, 26, 20))
	Paint.rect(s, 5, 6, 64, 33, Color8(230, 220, 190))
	letters(s, "BEAM ZONE", 35, 9, 1, Color8(160, 30, 24), false)
	letters(s, "NO STANDIN", 35, 18, 1, Color8(40, 30, 24), false)
	glyphs(s, 6, 35, 26, 1, Color8(40, 90, 50))
	weather(s, 30, 1)
	return Paint.digitize(s)


## WANTED: the Legs, drawn by somebody who only ever saw them from the knee down.
func wanted() -> Paint.Sheet:
	var s := Paint.Sheet.new(48, 72, Color8(214, 200, 160))
	_grain(s, .06)
	letters(s, "WANTED", 24, 3, 1, Color8(120, 24, 20), false)
	glyphs(s, 4, 24, 12, 1, Color8(40, 70, 40))
	# The legs: overalls, two boots.
	Paint.rect(s, 15, 26, 22, 50, Color8(60, 80, 130))
	Paint.rect(s, 26, 26, 33, 50, Color8(60, 80, 130))
	Paint.rect(s, 15, 24, 33, 28, Color8(60, 80, 130))
	Paint.rect(s, 12, 50, 22, 54, Color8(70, 46, 30))
	Paint.rect(s, 26, 50, 36, 54, Color8(70, 46, 30))
	letters(s, "THE LEGS", 24, 57, 1, Color8(40, 30, 24), false)
	letters(s, "REWARD 1 COW", 24, 64, 1, Color8(120, 24, 20), false)
	weather(s, 30, 2)
	return Paint.digitize(s)


## The late sheriff, framed, a black ribbon across the corner.
func memorial() -> Paint.Sheet:
	var s := Paint.Sheet.new(60, 64, Color8(70, 46, 30))
	Paint.rect(s, 4, 4, 55, 47, Color8(30, 40, 34))
	# The grey face under the hat, moustache and all.
	Paint.ellipse(s, 18, 14, 42, 44, Color8(150, 170, 130))
	Paint.ellipse(s, 21, 24, 28, 31, Color8(10, 12, 12))
	Paint.ellipse(s, 32, 24, 39, 31, Color8(10, 12, 12))
	Paint.rect(s, 24, 36, 36, 38, Color8(50, 34, 24))
	Paint.rect(s, 10, 12, 50, 15, Color8(200, 180, 140))
	Paint.rect(s, 19, 5, 41, 12, Color8(200, 180, 140))
	Paint.polygon(
		s,
		PackedVector2Array([Vector2(44, 4), Vector2(55, 4), Vector2(55, 15), Vector2(36, 4)]),
		Color8(12, 10, 10)
	)
	Paint.rect(s, 4, 49, 55, 61, Color8(40, 28, 20))
	letters(s, "OUR BOY", 30, 50, 1, Color8(230, 200, 120), false)
	frame(s, Color8(150, 110, 50))
	return Paint.digitize(s)


## HOOMAN, RURAL MODEL: what the probe lab thinks it knows.
func chart() -> Paint.Sheet:
	var s := Paint.Sheet.new(60, 84, Color8(220, 214, 190))
	_grain(s, .05)
	letters(s, "HOOMAN", 30, 2, 1, Color8(40, 30, 24), false)
	letters(s, "RURAL MODEL", 30, 10, 1, Color8(120, 30, 24), false)
	var ink := Color8(40, 30, 24)
	var red := Color8(120, 30, 24)
	# A cap, a head, a gut, four sticks.
	Paint.rect(s, 22, 22, 38, 24, red)
	Paint.rect(s, 25, 19, 35, 22, red)
	Paint.ellipse(s, 24, 24, 36, 36, ink)
	Paint.ellipse(s, 25, 25, 35, 35, Color8(220, 214, 190))
	Paint.ellipse(s, 20, 37, 40, 60, ink)
	Paint.ellipse(s, 21, 38, 39, 59, Color8(220, 214, 190))
	Paint.line2(s, 25, 59, 22, 74, ink, 1)
	Paint.line2(s, 35, 59, 38, 74, ink, 1)
	Paint.line2(s, 21, 41, 12, 52, ink, 1)
	Paint.line2(s, 39, 41, 48, 52, ink, 1)
	Paint.line2(s, 30, 49, 50, 46, red, 1)
	letters(s, "GUT", 51, 39, 1, red, false)
	Paint.line2(s, 30, 30, 10, 28, red, 1)
	letters(s, "CAP", 9, 20, 1, red, false)
	glyphs(s, 6, 30, 76, 1, Color8(40, 90, 50))
	weather(s, 30, 1)
	return Paint.digitize(s)


func menu_board() -> Paint.Sheet:
	var s := Paint.Sheet.new(84, 52, Color8(30, 40, 34))
	_grain(s, .06)
	letters(s, "TODAY", 42, 3, 1, Color8(250, 220, 140), false)
	glyphs(s, 5, 42, 11, 1, GLYPH)
	var lines := ["CORN DOG", "CORN DOG 2", "HOOMAN SURPRISE", "PIE (HOG)"]
	for i in lines.size():
		letters(s, String(lines[i]), 42, 20 + i * 7, 1, Color8(230, 226, 210), false)
	frame(s, Color8(110, 80, 50))
	return Paint.digitize(s)


func plaque(title: String, line: String) -> Paint.Sheet:
	var wide := maxi(PixelType.text_width(title), PixelType.text_width(line)) + 10
	var s := Paint.Sheet.new(wide, 20, Color8(176, 140, 60))
	_grain(s, .05)
	letters(s, title, wide / 2, 3, 1, Color8(40, 28, 16), false)
	letters(s, line, wide / 2, 11, 1, Color8(70, 50, 26), false)
	frame(s, Color8(100, 76, 30))
	return Paint.digitize(s)


## A pane of nothing but glyphs, lit from behind.
func glyph_panel(rows: int) -> Paint.Sheet:
	var s := Paint.Sheet.new(52, rows * 9 + 6, Color8(20, 28, 24))
	for r in rows:
		glyphs(s, 6, 26, 4 + r * 9, 1, GLYPH if r % 2 == 0 else Color8(255, 200, 90))
	frame(s, Color8(70, 74, 72))
	return Paint.digitize(s)


func note_card(title: String, line: String) -> Paint.Sheet:
	var wide := maxi(PixelType.text_width(title), PixelType.text_width(line)) + 10
	var s := Paint.Sheet.new(wide, 22, Color8(226, 220, 196))
	_grain(s, .05)
	letters(s, title, wide / 2, 3, 1, Color8(150, 30, 24), false)
	letters(s, line, wide / 2, 12, 1, Color8(40, 30, 24), false)
	Paint.rect(s, wide / 2 - 4, 0, wide / 2 + 4, 1, Color8(200, 190, 120))
	return Paint.digitize(s)


## A station's board: a glyph plate with a lamp that lights when it is done.
func station_board(title: String, lit: bool) -> Paint.Sheet:
	var wide := PixelType.text_width(title) + 24
	var s := Paint.Sheet.new(wide, 30, Color8(40, 44, 46))
	_grain(s, .05)
	glyphs(s, mini(6, title.length()), wide / 2, 3, 1, GLYPH if lit else Color8(60, 90, 70))
	letters(s, title, wide / 2, 13, 1, INK if lit else Color8(150, 146, 130), false)
	var lamp := Color8(110, 255, 140) if lit else Color8(150, 30, 24)
	Paint.ellipse(s, wide / 2 - 4, 21, wide / 2 + 4, 27, lamp)
	Paint.point(s, wide / 2 - 1, 23, Color8(255, 255, 255) if lit else Color8(220, 120, 100))
	frame(s, Color8(90, 96, 96))
	bolts(s)
	return Paint.digitize(s)


# -------------------------------------------------------------------- marks


## Where Maw's rolling pin is coming down: a cracked red ring.
func slam_mark() -> Paint.Sheet:
	var s := Paint.Sheet.new(64, 64)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
			if d > 1.0:
				continue
			var ring := absf(d - .85) < .08 or absf(d - .45) < .05
			var crack := absf(sin(atan2(y - 31.5, x - 31.5) * 5.0)) < .08 and d < .8
			if ring or crack:
				s.put(x, y, Color(1.0, .3, .15, .9))
			elif d < .85:
				s.put(x, y, Color(.8, .15, .05, .28))
	return s


## The pool the tractor beam throws on the deck.
func beam_mark() -> Paint.Sheet:
	var s := Paint.Sheet.new(64, 64)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
			if d < 1.0:
				var a := (1.0 - d) * .6 + (.25 if absf(d - .9) < .05 else 0.0)
				s.put(x, y, Color(.55, 1.0, .7, clampf(a, 0, 1)))
	return s


## The tractor beam loose on the floor, seen from the side: a column of light,
## brightest down its middle, motes going up it.
func beam_column() -> Paint.Sheet:
	var s := Paint.Sheet.new(32, 128)
	for y in 128:
		for x in 32:
			var across := 1.0 - absf(x - 15.5) / 16.0
			var band := .7 + .3 * sin(y * .21 + x * .4)
			var a := clampf(across * across * band * .75, 0.0, .8)
			s.put(x, y, Color(.55 + .4 * across, 1.0, .7 + .25 * across, a))
	for _k in 26:
		var x := rng.randi_range(6, 25)
		var y := rng.randi_range(0, 124)
		Paint.rect(s, x, y, x, y + 2, Color(.95, 1.0, .95, .95))
	return s
