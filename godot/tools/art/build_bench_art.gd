## Draw Mundell's junk bench's pictures (src/bench_screen.gd, src/bench_mods.gd):
##
##   bench_board                  the screen's board: pegboard in a two-by-four
##                                frame, MUNDELL'S JUNK BENCH in marker on a strip
##                                of duct tape, a coffee can for the scrap (the
##                                count is lettered on it in play), a strip of
##                                tape along the foot for what a tag does
##   bench_tag_<short>(_dim)      each mod's manila price tag (bench.cfg): a string
##                                through its hole, the part itself, its name and
##                                what it does hand lettered (the price in play);
##                                _dim greyed for one not to be had yet
##   bench_gun_<gun>(_bare)       each gun with mods on its pegs (its pickup
##                                picture), or its whitewash outline when not had
##   bench_stamp                  TAPED ON, a red rubber stamp
##   bench_mod_<short>_hud        each mod's little mark on the status bar, by hand
##   bench_scrap_hud              a hex nut beside the scrap count on the bar
##   item_scrap_<piece>           the scrap pickups: bolts, wire, a hubcap
##
##   godot --headless --path godot --script res://tools/art/build_bench_art.gd \
##       [-- no-render] [out=<dir>]
##
## The parts and the scrap are rendered by Blender (scripts/blender/weapon_mods.py
## items, into _preview/bench_raw), shrunk with the props' grade and committed
## to the palette; the rest is painted here, seeded, so a rerun gives the same
## files. BLENDER_PATH overrides where Blender is. Then run tools/pack_assets.gd.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")
const Actors := preload("res://tools/art/build_enemy_actors.gd")
const BOARD := Vector2i(308, 144)
const TAG := Vector2i(118, 19)
const GUN_BOX := Vector2i(52, 22)
const GUNS := ["revolver", "shotgun", "rifle", "crossbow", "tnt"]
const SCRAP_SIZE := {
	"bolts": Vector2i(32, 22), "wire": Vector2i(32, 24), "hubcap": Vector2i(34, 24)
}
const MARKER := Color8(30, 22, 18)
const RED := Color8(178, 34, 26)
## The status bar's marks, a row of pixels each ("#" ink, "o" shine, "." none).
const HUD_MARKS := {
	"scope": ["..........", "##########", "#oo####o##", "##########", "..#....#..", ".........."],
	"loader": ["...###....", "..#o#o#...", ".##o#o##..", "..#o#o#...", "...###....", "....#....."],
	"bayonet": ["..........", "........##", "....oooo#.", "####oooo..", "####......", ".........."],
	"choke": ["..........", "####oo####", "#ooooooooo", "#ooooooooo", "####oo####", ".........."],
	"drum": ["...####...", "..#oooo#..", ".#oo##oo#.", ".#oo##oo#.", "..#oooo#..", "...####..."],
	"brake": ["..######..", "..#o#o##..", "###o#o####", "###o#o####", "..#o#o##..", "..######.."],
	"flame": ["....#.....", "...#o#....", "..#oo#.#..", "..#ooo#o#.", ".#oooooo#.", "..######.."],
	"spring": ["..........", "##......##", ".##....##.", "..######..", "...#..#...", ".........."],
	"fuse": ["......#...", ".....#.#..", "..##.#.#..", ".#..#..#..", "#.......##", ".........."],
	"bundle": [".###......", "#oo#......", "#oo####...", "####oo#...", "...####...", ".........."],
}

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 5150
	var render := true
	var out := Paint.repo("assets/art")
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text == "no-render":
			render = false
		elif text.begins_with("out="):
			out = text.substr(4)
	var raw := Paint.repo("_preview/bench_raw")
	DirAccess.make_dir_recursive_absolute(raw)
	DirAccess.make_dir_recursive_absolute(out)
	if render:
		var code := OS.execute(
			Actors.blender(),
			["-b", "-P", Paint.repo("scripts/blender/weapon_mods.py"), "--", raw, "items"]
		)
		if code != 0:
			push_error("Blender failed (exit %d); set BLENDER_PATH if it is elsewhere" % code)
			quit(1)
			return
	var cfg := ConfigFile.new()
	cfg.load("res://data/tuning/bench.cfg")
	var made := {"bench_board": board(), "bench_stamp": stamp(), "bench_scrap_hud": nut()}
	for section: String in cfg.get_sections():
		if not section.begins_with("mod."):
			continue
		var short := str(cfg.get_value(section, "short", ""))
		var part := _shrunk(raw.path_join("mod_%s.png" % short), Vector2i(22, 15), short)
		var tag := price_tag(
			part, str(cfg.get_value(section, "label", "")), str(cfg.get_value(section, "line", ""))
		)
		made["bench_tag_" + short] = tag
		made["bench_tag_%s_dim" % short] = dimmed(tag)
		made["bench_mod_%s_hud" % short] = hud_mark(short)
	for gun: String in GUNS:
		var pic := _shrunk(raw.path_join("gun_%s.png" % gun), GUN_BOX - Vector2i(4, 2), gun)
		made["bench_gun_" + gun] = hung(pic, false)
		made["bench_gun_%s_bare" % gun] = hung(pic, true)
	for piece: String in SCRAP_SIZE:
		var size: Vector2i = SCRAP_SIZE[piece]
		var shrunk := _shrunk(raw.path_join("scrap_%s.png" % piece), size, piece)
		var sheet := Paint.Sheet.new(48, 48)
		sheet.paste(shrunk, (48 - shrunk.w) / 2, 39 - shrunk.h)
		made["item_scrap_" + piece] = sheet
	for name: String in made:
		var picture: Paint.Sheet = made[name]
		picture.save(out.path_join(name + ".png"))
	print("bench art: %d to %s" % [made.size(), out])
	quit()


# ------------------------------------------------------------------ helpers


func _blend(s: Paint.Sheet, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= s.w or y >= s.h:
		return
	var o := (y * s.w + x) * 4
	var a := c.a
	for k in 3:
		s.data[o + k] = int(s.data[o + k] * (1.0 - a) + c[k] * 255.0 * a)
	s.data[o + 3] = maxi(s.data[o + 3], int(a * 255))


## Letters by hand in marker: each a pixel up or down now and then, the ink
## a little uneven, a bleed beside the strokes now and then. `mini` the small
## letters. Returns how wide it went.
func lettered(s: Paint.Sheet, text: String, x: int, y: int, ink: Color, mini := false) -> int:
	var at := x
	for c in text:
		var g: Array = PixelType.glyph(c, mini)
		var rows: Array = g[0]
		var gw: int = g[1]
		var lift := 1 if rng.randf() < .18 else (-1 if rng.randf() < .12 else 0)
		var tone := ink.darkened(rng.randf_range(0.0, .15))
		for r in rows.size():
			for bx in gw:
				if int(rows[r]) & (1 << (gw - 1 - bx)):
					_blend(s, at + bx, y + r + lift, Color(tone, .96))
					if rng.randf() < .12:
						_blend(s, at + bx + 1, y + r + lift, Color(tone, .4))
		at += gw + 1
	return at - x


static func text_width(text: String, mini := false) -> int:
	var w := 0
	for c in text:
		w += int(PixelType.glyph(c, mini)[1]) + 1
	return w - 1


## A rendered picture cropped to its edges and shrunk to fit `box`, graded
## as the props are and committed to the palette.
func _shrunk(path: String, box: Vector2i, name: String) -> Paint.Sheet:
	var image := Paint.Sheet.load_png(path)
	if image == null:
		push_error("no render %s: run without no-render" % path)
		return Paint.Sheet.new(box.x, box.y)
	var cut := image.cropped(image.bbox(100))
	var k := minf(float(box.x) / cut.w, float(box.y) / cut.h)
	var size := Vector2i(maxi(1, roundi(cut.w * k)), maxi(1, roundi(cut.h * k)))
	var seed := 0
	for ch in name.to_utf8_buffer():
		seed += ch
	return Paint.digitize(Paint.photo_shrink(cut, size, seed))


func _tape(s: Paint.Sheet, x0: int, y0: int, w: int, h: int) -> void:
	# Grey cloth tape: a weave, a shine along it, torn ends.
	var weave := Paint.noise(rng.randi(), w * h, .05)
	var left := []
	var right := []
	for y in h:
		left.append(rng.randi_range(0, 2))
		right.append(rng.randi_range(0, 2))
	for y in h:
		for x in w:
			if x < int(left[y]) or x >= w - int(right[y]):
				continue
			var f := 1.0 + weave[y * w + x] + (.05 if (x + y) % 3 == 0 else 0.0)
			if y == 1:
				f += .18
			if y == h - 1:
				f -= .2
			var c := Color(.55 * f, .56 * f, .55 * f)
			Paint.point(s, x0 + x, y0 + y, c)


# ------------------------------------------------------------------ the board


func board() -> Paint.Sheet:
	var s := Paint.Sheet.new(BOARD.x, BOARD.y)
	var grit := Paint.noise(rng.randi(), BOARD.x * BOARD.y, .045)
	var blot := Paint.cloud(64, rng.randi())
	for y in BOARD.y:
		for x in BOARD.x:
			var f := 1.0 + grit[y * BOARD.x + x]
			f -= blot[(y * 64 / BOARD.y) * 64 + x * 64 / BOARD.x] * .14
			var edge := minf(minf(x, BOARD.x - 1 - x), minf(y, BOARD.y - 1 - y))
			f *= .82 + .18 * clampf(edge / 14.0, 0.0, 1.0)
			var c := Color(.6 * f, .45 * f, .29 * f)
			if (x - 4) % 7 == 0 and (y - 4) % 7 == 0:
				c = c.darkened(.55)
			elif (x - 5) % 7 == 0 and (y - 5) % 7 == 0:
				c = c.lightened(.08)
			s.put(x, y, c)
	# The two-by-four frame round it.
	var wood := Color8(108, 76, 46)
	for k in 4:
		var c := wood.darkened(.12 * k) if k > 1 else wood.lightened(.1 - .05 * k)
		Paint.outline(s, k, k, BOARD.x - 1 - k, BOARD.y - 1 - k, c)
	for p in [Vector2i(2, 2), Vector2i(BOARD.x - 3, 2), Vector2i(2, BOARD.y - 3)]:
		Paint.point(s, p.x, p.y, Color8(200, 196, 186))
	Paint.point(s, BOARD.x - 3, BOARD.y - 3, Color8(200, 196, 186))
	# The title on its tape, top left.
	var title := "MUNDELL'S JUNK BENCH"
	var tw := text_width(title)
	_tape(s, 8, 5, tw + 16, 13)
	lettered(s, title, 16, 8, MARKER)
	# The coffee can for the scrap, top right: red, ribbed, a cream label.
	var can := Rect2i(266, 3, 40, 21)
	for y in can.size.y:
		for x in can.size.x:
			var shade := 1.0 - absf(x - can.size.x * .4) / can.size.x * .9
			var c := Color8(150, 36, 28)
			if y >= 6 and y <= 16:
				c = Color8(214, 196, 150)
			if y == 1 or y == 19 or y == 3:
				c = Color8(176, 172, 160)
			c = Color(c.r * shade, c.g * shade, c.b * shade)
			Paint.point(s, can.position.x + x, can.position.y + y, c)
	lettered(s, "SCRAP", can.position.x + 6, can.position.y - 1 + 21, Color8(240, 230, 200), true)
	# The strip of tape along the foot.
	_tape(s, 6, BOARD.y - 17, BOARD.x - 12, 13)
	return Paint.digitize(s)


func price_tag(part: Paint.Sheet, label: String, line: String) -> Paint.Sheet:
	var s := Paint.Sheet.new(TAG.x, TAG.y)
	var grit := Paint.noise(rng.randi(), TAG.x * TAG.y, .05)
	for y in TAG.y:
		for x in TAG.x:
			# The left end cut to a point, the hole in it.
			var cut := absf(y - TAG.y * .5) - (x + 1) * .9
			if cut > 0.0:
				continue
			var f := 1.0 + grit[y * TAG.x + x] - (.1 if x > TAG.x - 3 or y > TAG.y - 2 else 0.0)
			var c := Color(.84 * f, .72 * f, .5 * f)
			if y == 0 or (cut > -1.2):
				c = c.darkened(.25)
			s.put(x, y, c)
	Paint.ellipse(s, 4, 8, 7, 11, Color8(60, 44, 30))
	Paint.ellipse(s, 3, 7, 8, 12, Color(0, 0, 0, 0))
	Paint.ellipse(s, 4, 8, 7, 11, Color8(70, 50, 34))
	# A twist of string out through the hole.
	for k in 6:
		_blend(s, 3 - k / 3, 9 - k, Color8(220, 210, 180))
	# The part, the price's ring, the words.
	s.composite(part, 10 + (22 - part.w) / 2, (TAG.y - part.h) / 2)
	Paint.ellipse(s, 100, 0, 116, 10, Color8(150, 40, 30, 130))
	Paint.ellipse(s, 101, 1, 115, 9, Color(.84, .72, .5))
	var room := 98 - 34
	var mini := text_width(label) > room
	lettered(s, label, 34, 1 if not mini else 3, MARKER, mini)
	lettered(s, line, 34, 12, Color8(96, 52, 30), true)
	return Paint.digitize(s, 6.0)


func dimmed(tag: Paint.Sheet) -> Paint.Sheet:
	var out := tag.duplicate_sheet()
	for i in out.w * out.h:
		var o := i * 4
		var grey := (out.data[o] + out.data[o + 1] + out.data[o + 2]) / 3.0
		for k in 3:
			out.data[o + k] = int(lerpf(out.data[o + k], grey, .6) * .58)
	return Paint.digitize(out, 0.0)


## A gun hung on two pegs, or its whitewash outline when not had yet.
func hung(pic: Paint.Sheet, bare: bool) -> Paint.Sheet:
	var s := Paint.Sheet.new(GUN_BOX.x, GUN_BOX.y)
	var cut := pic.cropped(pic.bbox(100))
	var k := minf(1.0, minf(float(GUN_BOX.x - 4) / cut.w, float(GUN_BOX.y - 2) / cut.h))
	var size := Vector2i(maxi(1, roundi(cut.w * k)), maxi(1, roundi(cut.h * k)))
	var small := cut.resized(size.x, size.y) if k < 1.0 else cut
	var at := (GUN_BOX - size) / 2
	if bare:
		var paint := Color8(236, 232, 214)
		for y in range(-1, size.y + 1):
			for x in range(-1, size.x + 1):
				if _solid(small, x, y):
					continue
				for d: Vector2i in [
					Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
				]:
					if _solid(small, x + d.x, y + d.y):
						_blend(s, at.x + x, at.y + y, Color(paint, .92 if rng.randf() > .1 else .6))
						break
	else:
		# Its shadow on the board, then the gun.
		for y in size.y:
			for x in size.x:
				if _solid(small, x, y):
					_blend(s, at.x + x + 1, at.y + y + 1, Color(0, 0, 0, .45))
		s.composite(small, at.x, at.y)
	for px: int in [at.x + size.x / 4, at.x + size.x * 3 / 4]:
		Paint.rect(s, px, at.y + size.y / 2, px + 1, at.y + size.y / 2 + 1, Color8(170, 160, 140))
	return Paint.digitize(s, 0.0)


func _solid(s: Paint.Sheet, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < s.w and y < s.h and s.data[(y * s.w + x) * 4 + 3] > 100


## The price ring stamped over once the mod is on: ON in red in a ring.
func stamp() -> Paint.Sheet:
	var w := 20
	var h := 13
	var s := Paint.Sheet.new(w, h)
	var ink := Color8(196, 32, 24)
	Paint.ellipse(s, 0, 0, w - 1, h - 1, ink)
	Paint.ellipse(s, 2, 2, w - 3, h - 3, Color(0, 0, 0, 0))
	for i in s.w * s.h:
		var x := i % w
		var y := i / w
		var dx := (x - (w - 1) * .5) / ((w - 1) * .5)
		var dy := (y - (h - 1) * .5) / ((h - 1) * .5)
		var r := dx * dx + dy * dy
		if r < .55:
			s.data[i * 4 + 3] = 0
	var at := 4
	for c in "ON":
		var g: Array = PixelType.glyph(c, false)
		var rows: Array = g[0]
		var gw: int = g[1]
		for row in rows.size():
			for bx in gw:
				if int(rows[row]) & (1 << (gw - 1 - bx)):
					Paint.point(s, at + bx, 3 + row, ink)
		at += gw + 2
	for i in s.w * s.h:
		if s.data[i * 4 + 3] > 0 and rng.randf() < .06:
			s.data[i * 4 + 3] = 0
	return Paint.digitize(s, 0.0)


func hud_mark(short: String) -> Paint.Sheet:
	var rows: Array = HUD_MARKS.get(short, HUD_MARKS["scope"])
	var s := Paint.Sheet.new(10, 6)
	for y in rows.size():
		var row: String = rows[y]
		for x in row.length():
			if row[x] == "#":
				s.put(x, y, Color8(34, 30, 28))
			elif row[x] == "o":
				s.put(x, y, Color8(236, 196, 96))
	return s


func nut() -> Paint.Sheet:
	var rows := [".###.", "#ooo#", "#o.o#", "#ooo#", ".###."]
	var s := Paint.Sheet.new(5, 5)
	for y in 5:
		var row: String = rows[y]
		for x in 5:
			if row[x] == "#":
				s.put(x, y, Color8(70, 66, 60))
			elif row[x] == "o":
				s.put(x, y, Color8(176, 172, 160))
	return s
