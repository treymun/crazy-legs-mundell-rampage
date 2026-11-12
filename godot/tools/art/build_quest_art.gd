## The things the objective is done at, for every chapter: modelled in
## Blender (scripts/blender/quest_props.py) as freestanding props that read
## from any side with nothing behind them, each station in its still-to-do and
## done state, plus the keys and the PA patch lead to pick up; and, painted,
## Hickston's pen sign (it switches when Bessie is home) and the locked
## Crossroads gate's barricade (a wall tile).
##
##   godot --headless --path godot --script res://tools/art/build_quest_art.gd \
##       [-- names=quest_switch,item_key_brass] [no-render] [out=<dir>]
##
## Blender writes each prop four times oversized into _preview/quest_props/raw;
## this crops a station's two states to one frame (so the lamp, lever and wheel
## change in place, nothing jumps), shrinks them with the sprites' grade
## (paint.gd photo_shrink) and commits them to the palette as
## town_<name>_off.png (still to do: the warning lamp lit, the lever up) and
## town_<name>_on.png (done: the lamp dark, the green pilot lit, the lever thrown
## and tagged; an exit red and chained, then green and open). Their size in map
## units goes in assets/art/town_props.json under <name>_off and <name>_on for
## the level builder (level_builder.gd quest()). The keys and the lead become
## item_<name>.png, 48 square. BLENDER_PATH overrides where Blender is;
## no-render reuses the last renders. Then run tools/pack_assets.gd.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")
const Actors := preload("res://tools/art/build_enemy_actors.gd")
const SUPERSAMPLE := 4
const ITEM_SIZE := 48

const INK := Color(.96, .9, .74)
const SOOT := Color(.07, .05, .04)
const LAMP_AMBER := Color(1.0, .7, .2)
const PILOT_GREEN := Color(.36, 1.0, .42)

var rng := RandomNumberGenerator.new()


func _init() -> void:
	var names := "all"
	var render := true
	var out := Paint.repo("assets/art")
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text.begins_with("names="):
			names = text.substr(6)
		elif text == "no-render":
			render = false
		elif text.begins_with("out="):
			out = text.substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	var tiles := Paint.repo("assets/tiles") if out == Paint.repo("assets/art") else out
	var raw := Paint.repo("_preview/quest_props/raw")
	DirAccess.make_dir_recursive_absolute(raw)
	if render:
		var wanted := names
		if names != "all":
			# A station's name stands for both its states.
			var listed: PackedStringArray = []
			for name in names.split(","):
				if name.begins_with("item_"):
					listed.append(name)
				else:
					listed.append(name + "_off")
					listed.append(name + "_on")
			wanted = ",".join(listed)
		var code := OS.execute(
			Actors.blender(),
			[
				"-b",
				"-P",
				Paint.repo("scripts/blender/quest_props.py"),
				"--",
				raw,
				wanted,
				str(SUPERSAMPLE)
			]
		)
		if code != 0:
			push_error("Blender failed (exit %d); set BLENDER_PATH if it is elsewhere" % code)
			quit(1)
			return
	var made := _shrink_renders(raw, out, names)
	if made < 0:
		quit(1)
		return
	if names == "all":
		for done in [false, true]:
			rng.seed = hash("wing_town_pen")
			var words: Array = (
				["BESSIE'S HOME", "BACK TO REGULAR RATIONS"]
				if done
				else ["FEED AND BOARD", "BRING YOUR OWN BUCKET"]
			)
			status_sign(Color(.46, .26, .16), String(words[0]), String(words[1]), done).save(
				out.path_join("wing_town_pen" + ("_on" if done else "_off") + ".png")
			)
		rng.seed = 14
		barricade().save(tiles.path_join("route_closed.png"))
		made += 3
	print("quest art: %d pictures written to %s" % [made, out])
	quit()


## Every render in raw/meta.json into the game: station pairs cropped to one
## frame, items fitted to a square. Returns how many were written, -1 on error.
func _shrink_renders(raw: String, out: String, names: String) -> int:
	var meta = JSON.parse_string(FileAccess.get_file_as_string(raw.path_join("meta.json")))
	if not meta is Dictionary:
		push_error("no %s/meta.json: render first" % raw)
		return -1
	var sizes_path := out.path_join("town_props.json")
	var sizes := {}
	if FileAccess.file_exists(sizes_path):
		sizes = JSON.parse_string(FileAccess.get_file_as_string(sizes_path))
	var count := 0
	var listed := names.split(",")
	for name: String in meta:
		if name.ends_with("_on"):
			continue
		var base := name.trim_suffix("_off")
		if names != "all" and not (base in listed) and not (name in listed):
			continue
		var seed := 0
		for c in base.to_utf8_buffer():
			seed += c
		if name.begins_with("item_"):
			var image := Paint.Sheet.load_png(raw.path_join(name + ".png"))
			var cut := image.cropped(image.bbox(127))
			var scale := float(ITEM_SIZE) / maxi(cut.w, cut.h)
			var fit := Vector2i(maxi(1, roundi(cut.w * scale)), maxi(1, roundi(cut.h * scale)))
			var small := Paint.digitize(Paint.photo_shrink(cut, fit, seed), 5.0)
			var square := Paint.Sheet.new(ITEM_SIZE, ITEM_SIZE)
			square.paste(small, (ITEM_SIZE - fit.x) / 2, (ITEM_SIZE - fit.y) / 2)
			square.save(out.path_join(name + ".png"))
			count += 1
			continue
		if not meta.has(base + "_on"):
			push_error("%s has no _on render" % base)
			return -1
		var pair := [
			Paint.Sheet.load_png(raw.path_join(base + "_off.png")),
			Paint.Sheet.load_png(raw.path_join(base + "_on.png"))
		]
		# One frame round both states: the prop stands still while it changes.
		var box: Rect2i = pair[0].bbox(127).merge(pair[1].bbox(127))
		if box.size.x <= 0 or box.size.y <= 0:
			push_error("%s rendered empty" % base)
			return -1
		var ppu := float(meta[name][2]) * SUPERSAMPLE
		var target := Vector2i(
			maxi(1, roundi(box.size.x / float(SUPERSAMPLE))),
			maxi(1, roundi(box.size.y / float(SUPERSAMPLE)))
		)
		for k in 2:
			var state := "_off" if k == 0 else "_on"
			var cut: Paint.Sheet = pair[k].cropped(box)
			Paint.digitize(Paint.photo_shrink(cut, target, seed)).save(
				out.path_join("town_%s%s.png" % [base, state])
			)
			sizes[base + state] = [snappedf(box.size.x / ppu, .01), snappedf(box.size.y / ppu, .01)]
			count += 1
	var file := FileAccess.open(sizes_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(sizes, "\t", true))
	file.close()
	return count


# ------------------------------------------------------- the painted pieces


## Planks laid across, as the town paints them.
func planks(s: Paint.Sheet, x0: int, y0: int, x1: int, y1: int, base: Color, plank := 14) -> void:
	var grain := Paint.noise(rng.randi(), (x1 - x0 + 1) * (y1 - y0 + 1), .05)
	var bw := x1 - x0 + 1
	for y in range(y0, y1 + 1):
		var row := (y - y0) / plank
		var tone := 1.0 + sin(row * 2.3) * .07
		var seam := (y - y0) % plank == 0
		for x in range(x0, x1 + 1):
			var f := tone + grain[(y - y0) * bw + (x - x0)] + sin(x * .11 + row * 1.7) * .035
			if seam:
				f *= .5
			s.put(x, y, Color(base.r * f, base.g * f, base.b * f))


func rivet(s: Paint.Sheet, x: int, y: int) -> void:
	Paint.ellipse(s, x - 2, y - 2, x + 2, y + 2, Color(.16, .14, .12))
	Paint.ellipse(s, x - 2, y - 2, x + 1, y + 1, Color(.74, .7, .6))
	Paint.point(s, x - 1, y - 1, Color(.95, .92, .82))


## A lamp: a glass dome in a wire cage on a black base, lit.
func lamp(s: Paint.Sheet, cx: int, cy: int, r: int, colour: Color) -> void:
	Paint.rect(s, cx - r - 3, cy, cx + r + 3, cy + r / 2 + 3, SOOT)
	Paint.rect(s, cx - r - 3, cy, cx + r + 3, cy + 2, Color(.3, .28, .26))
	Paint.pieslice(s, cx - r, cy - r, cx + r, cy + r, 180, 360, colour)
	var hot := colour.lerp(Color(1, 1, .86), .65)
	Paint.pieslice(s, cx - r * .55, cy - r * .7, cx + r * .4, cy + r * .2, 180, 360, hot)
	Paint.ellipse(s, cx - r * .45, cy - r * .75, cx - r * .1, cy - r * .45, Color(1, 1, .95))
	var wire := Color(.1, .09, .08)
	Paint.arc(s, cx - r - 1, cy - r - 1, cx + r + 1, cy + r + 1, 180, 360, wire, 2)
	for k in [-.5, 0.0, .5]:
		var x := cx + int(k * r)
		var top := cy - int(sqrt(maxf(0.0, 1.0 - k * k)) * r)
		Paint.rect(s, x - 1, top, x, cy, wire)


## Block letters (the game's own), `sx` wide and `sy` tall per glyph pixel,
## with a drop shadow, centred on cx.
func letters(
	s: Paint.Sheet, text: String, cx: int, y: int, sx: int, sy: int, ink: Color, shadow := true
) -> void:
	var left := cx - text_width(text, sx) / 2
	for pass_k in [1, 0] if shadow else [0]:
		var off: int = pass_k * maxi(2, sy / 2)
		var colour := Color(.05, .03, .02, .85) if pass_k == 1 else ink
		var at := left
		for c in text:
			var g: Array = PixelType.glyph(c, false)
			var rows: Array = g[0]
			var gw: int = g[1]
			for r in rows.size():
				for bx in gw:
					if int(rows[r]) & (1 << (gw - 1 - bx)):
						for yy in sy:
							for xx in sx:
								_blend(s, at + bx * sx + xx + off, y + r * sy + yy + off, colour)
			at += (gw + 1) * sx


func text_width(text: String, sx: int) -> int:
	var width := 0
	for c in text:
		width += (int(PixelType.glyph(c, false)[1]) + 1) * sx
	return width - sx


func _blend(s: Paint.Sheet, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= s.w or y >= s.h:
		return
	var o := (y * s.w + x) * 4
	if s.data[o + 3] == 0:
		return
	for k in 3:
		s.data[o + k] = int(s.data[o + k] * (1.0 - c.a) + c[k] * 255.0 * c.a)


## Chips where the paint came off and a few bullet holes.
func weather(s: Paint.Sheet, chips: int, holes: int) -> void:
	for _k in chips:
		var x := rng.randi_range(2, s.w - 3)
		var y := rng.randi_range(2, s.h - 3)
		for d: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
			var o := ((y + d.y) * s.w + x + d.x) * 4
			if s.data[o + 3] > 0:
				for k in 3:
					s.data[o + k] = int(s.data[o + k] * .7)
	for _k in holes:
		var x := rng.randi_range(8, s.w - 9)
		var y := rng.randi_range(8, s.h - 9)
		if s.alpha_at(x, y) == 0:
			continue
		Paint.ellipse(s, x - 2, y - 2, x + 2, y + 2, Color(.05, .04, .03))
		Paint.arc(s, x - 3, y - 3, x + 3, y + 3, 180, 300, Color(.7, .66, .58))


## Hickston's pen sign: its words and a lamp on the left (amber while Bessie is
## still out there, green once she is home). Painted twice size, shrunk, a hard
## edge and the palette.
func status_sign(base: Color, title: String, under: String, done: bool) -> Paint.Sheet:
	var s := Paint.Sheet.new(352, 134)
	planks(s, 4, 4, 347, 129, base if not done else base.lerp(Color(.22, .34, .22), .45), 16)
	Paint.outline(s, 4, 4, 347, 129, SOOT)
	Paint.outline(s, 8, 8, 343, 125, Color(.82, .72, .5))
	lamp(s, 36, 70, 18, PILOT_GREEN if done else LAMP_AMBER)
	var room := 262
	var sx := 4
	while sx > 2 and text_width(title, sx) > room:
		sx -= 1
	letters(s, title, 202, 22, sx, 6, INK)
	var ux := 3 if text_width(under, 3) <= room else 2
	letters(s, under, 202, 84, ux, 3, Color(.98, .86, .5) if not done else Color(.8, .96, .7))
	for p in [Vector2i(14, 14), Vector2i(337, 14), Vector2i(14, 119), Vector2i(337, 119)]:
		rivet(s, p.x, p.y)
	weather(s, 150, 3)
	var small := s.resized(176, 67)
	for i in 176 * 67:
		small.data[i * 4 + 3] = 255 if small.data[i * 4 + 3] >= 120 else 0
	return Paint.digitize(small, 7.0)


## A locked gate's barricade (route_closed), laid once across the gate: it is
## about three times wider in the world than it is here, so the lettering is
## drawn tall and narrow. Two striped rails, a tin plate CLOSED and the lock.
func barricade() -> Paint.Sheet:
	var s := Paint.Sheet.new(128, 128)
	planks(s, 0, 0, 127, 127, Color(.3, .22, .15), 12)
	for rail in [[12, 34], [92, 114]]:
		for y in range(int(rail[0]), int(rail[1]) + 1):
			for x in 128:
				var band := posmod(x * 3 + y, 36) < 18
				var c := Color(.88, .84, .76) if band else Color(.74, .1, .07)
				var f := .92 + .08 * sin(x * .9 + y * .4)
				s.put(x, y, Color(c.r * f, c.g * f, c.b * f))
		Paint.rect(s, 0, int(rail[0]) - 1, 127, int(rail[0]), SOOT)
		Paint.rect(s, 0, int(rail[1]), 127, int(rail[1]) + 1, SOOT)
	# The plate in the middle, and the chain and lock hanging off it.
	Paint.rect(s, 30, 40, 98, 86, Color(.9, .86, .74))
	Paint.outline(s, 30, 40, 98, 86, SOOT)
	Paint.outline(s, 32, 42, 96, 84, Color(.74, .1, .07))
	letters(s, "CLOSED", 64, 46, 2, 5, Color(.72, .08, .06), false)
	Paint.line2(s, 58, 86, 52, 100, Color(.55, .53, .5), 2)
	Paint.line2(s, 70, 86, 76, 100, Color(.55, .53, .5), 2)
	Paint.arc(s, 58, 96, 70, 110, 180, 360, Color(.6, .58, .54), 2)
	Paint.rect(s, 55, 103, 73, 118, Color(.82, .62, .22))
	Paint.rect(s, 63, 107, 65, 113, SOOT)
	weather(s, 120, 2)
	return Paint.digitize(s, 6.0)
