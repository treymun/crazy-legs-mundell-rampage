## The frame's and the tick's CPU work outside the 3D view (pass 10's speed
## pass, PERFCPU; tools/check_all.gd runs it):
##
##   godot --headless --path godot --script res://tools/cpu_check.gd [-- report]
##
## - Text: PixelType.text_width() (kept by text) answers as measuring each
##   letter does, in every style and with SMALL TEXT CLEAR either way; the
##   kept glyphs are read-only; measuring the HUD's words 20,000 times stays
##   inside TEXT_BUDGET yardsticks (it took a frame's whole CPU before).
## - Polygons: Canvas._fill_poly (spans kept by shape) sets the very pixels
##   the old scanline fill set, anywhere on the canvas.
## - The Godot canvas: a line's runs (Canvas._gpu_line) cover the pixels the
##   one-pixel Bresenham sets, clipped the same, in fewer rectangles; a
##   label's kept letters stand where the software letters do.
## - Feature hooks: Features.with_hook lists exactly the features with their
##   own sprites/draw_view/hud_*/ground_marks/wall_marks, in order; the
##   others' are GameFeature's empty ones.
## - The tick: every live enemy asked its level of detail once a tick; the
##   bot game's tick (best of three batches) inside TICK_BUDGET and no
##   feature's tick past FEATURE_BUDGET, in yardsticks (CI-scale: they catch
##   a big slowdown, not noise). `report` prints the numbers.
extends SceneTree

const Pilot := preload("res://tools/bot_pilot.gd")
const STEP := 1.0 / 120.0
const TEXT_BUDGET := 40.0
## The tick's budgets, in units of a fixed piece of GDScript work timed just
## before (_yardstick: the same on any machine and as slow under load), so a
## busy CI runner or check_all's other rows do not fail them.
const TICK_BUDGET := 2.0
const FEATURE_BUDGET := .3
const WORDS := [
	"E  OPEN DOOR",
	"FIRE  THROW     ALT  SET DOWN",
	"BLUE'S DOWN! GIT HIM UP!",
	"WINDUP LEFT",
	"FRETTIN'",
	"PATIENT",
	"KEYS IN IT",
	"STEEL KEY NEEDED",
	"THE SHERIFF'S DOWN. HERE COMES JERRY!",
	"123/456",
	"HOG WILD",
]

var failures: Array = []
var report := false


## A canvas whose Godot-canvas rectangles are kept, not drawn.
class RectCanvas:
	extends Canvas
	var rects: Array[Rect2i] = []

	func _gpu_rect(x: int, y: int, box_w: int, box_h: int, _r: int, _g: int, _b: int) -> void:
		rects.append(Rect2i(x, y, box_w, box_h))


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", text])
	if not ok:
		failures.append(text)


func _run() -> void:
	report = OS.get_cmdline_user_args().has("report")
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	print("\nTEXT")
	_text()
	print("\nPOLYGONS")
	_polygons()
	print("\nTHE GODOT CANVAS")
	_lines()
	_labels()
	print("\nFEATURE HOOKS")
	_hooks(main)
	print("\nTHE TICK")
	_lod(main)
	_tick(main)
	print("")
	print("CPU CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


# ------------------------------------------------------------------- text


func _text() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 10
	var corpus: Array = WORDS.duplicate()
	var letters: Array = PixelType.LETTERS.keys() + PixelType.MINI.keys() + [" ", "~", "a", "z"]
	for i in 300:
		var s := ""
		for k in rng.randi_range(0, 24):
			s += str(letters[rng.randi() % letters.size()])
		corpus.append(s)
	var wrong := 0
	var was_small := PixelType.clear_small
	for small: bool in [false, true, false]:
		PixelType.clear_small = small
		for style: String in ["mini", "body", "menu", "heading", "nonesuch"]:
			for text: String in corpus:
				for twice in 2:
					if PixelType.text_width(text, style) != _width_by_hand(text, style):
						wrong += 1
	PixelType.clear_small = was_small
	_check(wrong == 0, "text_width answers as letter by letter (%d wrong)" % wrong)
	var g: Array = PixelType.glyph("A", false)
	var rows: Array = g[0]
	_check(g.is_read_only() and rows.is_read_only(), "the kept glyphs are read-only")
	var best := INF
	for batch in 3:
		var t0 := Time.get_ticks_usec()
		for i in 20000:
			PixelType.text_width(WORDS[i % WORDS.size()], "mini" if i % 2 else "body")
		best = minf(best, (Time.get_ticks_usec() - t0) / 1000.0)
	var yard := _yardstick()
	if report:
		print("    20,000 measures: %.2f ms (yardstick %.3f ms)" % [best, yard])
	_check(
		best < TEXT_BUDGET * yard,
		"20,000 measures %.1f yardsticks (< %.0f)" % [best / yard, TEXT_BUDGET]
	)


## The width as text_width worked it out before it kept its answers.
func _width_by_hand(text: String, style: String) -> int:
	var sx: int = PixelType.style_of(style)[0]
	var mini := PixelType.is_mini(style)
	var total := 0
	for c in text.to_upper():
		var made: Array = PixelType._make_glyph(c, mini)
		var glyph_width: int = made[1]
		total += glyph_width + 1
	return maxi(0, total - 1) * sx


# --------------------------------------------------------------- polygons


func _polygons() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var wrong := 0
	var shapes := 0
	for i in 160:
		var n := rng.randi_range(4, 9)
		var xs := PackedInt32Array()
		var ys := PackedInt32Array()
		for k in n:
			xs.append(rng.randi_range(-30, 350))
			ys.append(rng.randi_range(-30, 230))
		if i % 4 == 0:
			# A plate's eight corners (round_rect), as the HUD draws them.
			var x := rng.randi_range(-10, 300)
			var y := rng.randi_range(-10, 180)
			xs = PackedInt32Array([x, x + 2, x + 40, x + 42, x + 42, x + 40, x + 2, x])
			ys = PackedInt32Array([y + 2, y, y, y + 2, y + 30, y + 32, y + 32, y + 30])
		for twice in 2:
			var kept := Canvas.new()
			kept._fill_poly(xs, ys, 200, 100, 50)
			var old := Canvas.new()
			_old_fill_poly(old, xs, ys, 200, 100, 50)
			if kept.pixels != old.pixels:
				wrong += 1
			shapes += 1
	_check(wrong == 0, "%d polygons fill the old pixels (%d differ)" % [shapes, wrong])


## Canvas._fill_poly as it was before its spans were kept (reference).
func _old_fill_poly(
	c: Canvas, xs: PackedInt32Array, ys: PackedInt32Array, r: int, g: int, b: int
) -> void:
	var n := xs.size()
	var min_y := ys[0]
	var max_y := ys[0]
	for i in range(1, n):
		min_y = mini(min_y, ys[i])
		max_y = maxi(max_y, ys[i])
	if min_y == max_y:
		var min_x := xs[0]
		var max_x := xs[0]
		for i in range(1, n):
			min_x = mini(min_x, xs[i])
			max_x = maxi(max_x, xs[i])
		c._hspan(min_x, min_y, max_x, r, g, b)
		return
	for y in range(min_y, max_y + 1):
		var hits: Array[int] = []
		for i in n:
			var prev := (i - 1 + n) % n
			var y1 := ys[prev]
			var y2 := ys[i]
			var x1: int
			var x2: int
			if y1 < y2:
				x1 = xs[prev]
				x2 = xs[i]
			elif y1 > y2:
				var t := y2
				y2 = y1
				y1 = t
				x2 = xs[prev]
				x1 = xs[i]
			else:
				continue
			if (y >= y1 and y < y2) or (y == max_y and y2 == max_y):
				var inter := float((y - y1) * (x2 - x1)) / float(y2 - y1)
				if hits.size() % 2 == 0:
					inter = floor(inter)
				else:
					inter = ceil(inter)
				hits.append(int(inter) + x1)
		hits.sort()
		var k := 0
		while k + 1 < hits.size():
			c._hspan(hits[k], y, hits[k + 1], r, g, b)
			k += 2
	for i in n:
		var prev2 := (i - 1 + n) % n
		var yy := ys[i]
		if min_y < yy and ys[prev2] == yy and yy < max_y:
			c._hspan(xs[i], yy, xs[prev2], r, g, b)


# --------------------------------------------------------- the godot canvas


func _lines() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var wrong := 0
	var pixels := 0
	var rects := 0
	for i in 400:
		var a := Vector2i(rng.randi_range(-40, 360), rng.randi_range(-40, 240))
		var b := Vector2i(rng.randi_range(-40, 360), rng.randi_range(-40, 240))
		if i % 5 == 0:
			b = Vector2i(a.x + rng.randi_range(-3, 3), a.y + rng.randi_range(-3, 3))
		var soft := Canvas.new()
		soft.use_mask = true
		soft.mask.resize(soft.w * soft.h)
		soft.line(a.x, a.y, b.x, b.y, Color(1, 1, 1))
		var gpu := RectCanvas.new()
		gpu.gpu = true
		gpu.line(a.x, a.y, b.x, b.y, Color(1, 1, 1))
		var covered := PackedByteArray()
		covered.resize(soft.w * soft.h)
		for r: Rect2i in gpu.rects:
			for yy in range(r.position.y, r.end.y):
				for xx in range(r.position.x, r.end.x):
					covered[yy * soft.w + xx] += 1
		rects += gpu.rects.size()
		for k in covered.size():
			pixels += soft.mask[k]
			if (covered[k] != 0) != (soft.mask[k] != 0) or covered[k] > 1:
				wrong += 1
	_check(wrong == 0, "400 lines' runs cover the Bresenham pixels once (%d differ)" % wrong)
	_check(rects * 2 < pixels, "in fewer rectangles (%d for %d pixels)" % [rects, pixels])


func _labels() -> void:
	var wrong := 0
	for text: String in WORDS:
		for style: String in ["mini", "body", "heading"]:
			var sx: int = PixelType.style_of(style)[0]
			var height: int = PixelType.style_of(style)[1]
			var mini := PixelType.is_mini(style)
			var run := Canvas._glyph_run(text, mini, sx, height)
			if run.size() != text.length():
				wrong += 1
				continue
			var x := 0
			var i := 0
			for ch in text.to_upper():
				var letter: Array = run[i]
				var at: int = letter[1]
				if at != x:
					wrong += 1
				var made: Array = PixelType.glyph(ch, mini)
				var glyph_w: int = made[1]
				x += (glyph_w + 1) * sx
				i += 1
	_check(wrong == 0, "a label's kept letters stand where the software's do (%d wrong)" % wrong)


# ---------------------------------------------------------- feature hooks


func _hooks(main) -> void:
	var g: Game = main.make_game("hickston")
	g.configure({"difficulty": 1, "hound": 1})
	var base: Script = load("res://src/features/game_feature.gd")
	var wrong := 0
	var listed := 0
	var total := 0
	for hook: String in Features.HOOKS:
		var with: Array = Features.with_hook(g, hook)
		listed += with.size()
		var order := 0
		for key: String in g.features:
			var feature: GameFeature = g.features[key]
			total += 1
			var own := _own(feature.get_script(), base, hook)
			var at := with.find(feature)
			if own != (at >= 0):
				wrong += 1
			if at >= 0:
				if at != order:
					wrong += 1
				order += 1
			elif hook in ["sprites", "ground_marks", "wall_marks"]:
				var got: Array = feature.call(hook)
				wrong += 0 if got.is_empty() else 1
	var hound: GameFeature = g.features["hound"]
	for hook: String in ["sprites", "draw_view", "hud_fixed", "hud_flow"]:
		if not Features.with_hook(g, hook).has(hound):
			wrong += 1
	_check(wrong == 0, "the hooks' lists are the features with their own (%d wrong)" % wrong)
	if report:
		print("    %d of %d hook calls a frame" % [listed, total])
	_check(listed * 4 < total, "%d of %d feature hook calls a frame" % [listed, total])
	main.release_games()


func _own(script: Script, base: Script, hook: String) -> bool:
	var mine := 0
	for m: Dictionary in script.get_script_method_list():
		mine += 1 if m["name"] == hook else 0
	var based := 0
	for m: Dictionary in base.get_script_method_list():
		based += 1 if m["name"] == hook else 0
	return mine > based


# -------------------------------------------------------------- the tick


func _lod(main) -> void:
	var g: Game = main.make_game("hickston")
	g.configure({"difficulty": 1})
	# Some of them dead and one dormant: each live one asked once a tick.
	var killed := 0
	for e: Enemy in g.enemies:
		if killed < 12 and e.hostile and not e.dormant:
			e.hp = 0.0
			e.died_at = 0.0
			killed += 1
	var wrong := 0
	for t in 240:
		var before := g.enemy_lod.thought + g.enemy_lod.waited
		var live := 0
		for e: Enemy in g.enemies:
			if e.hp > 0.0 and not e.dormant and e.brain != "bessie":
				live += 1
		g.tick(STEP, Game.Controls.new())
		if g.enemy_lod.thought + g.enemy_lod.waited - before != live:
			wrong += 1
	_check(wrong == 0, "every live enemy asked its level of detail once a tick (%d off)" % wrong)
	main.release_games()


func _tick(main) -> void:
	var best := INF
	var feature_us := {}
	for batch in 3:
		var g: Game = main.make_game("hickston")
		g.configure({"difficulty": 1, "hound": 1})
		g.cheats.god = true
		var pilot := Pilot.new()
		pilot.as_controls = true
		for t in 120:
			g.tick(STEP, pilot.steer(g))
			pilot.moved(g)
		g.events.timing = true
		var t0 := Time.get_ticks_usec()
		for t in 600:
			g.tick(STEP, pilot.steer(g))
			pilot.moved(g)
		var spent := (Time.get_ticks_usec() - t0) / 1000.0 / 600.0
		best = minf(best, spent)
		var list: Array = g.events.tick_list()
		for i in list.size():
			var c: Callable = list[i][0]
			var who := c.get_object()
			var name := (who.get_script() as Script).resource_path.get_file().get_basename()
			var us: float = g.events.tick_us[i] / 600.0
			feature_us[name] = minf(float(feature_us.get(name, INF)), us)
		main.release_games()
	var yard := _yardstick()
	var worst := ""
	var worst_us := 0.0
	for name: String in feature_us:
		if feature_us[name] > worst_us:
			worst_us = feature_us[name]
			worst = name
	if report:
		print(
			(
				"    tick %.3f ms; costliest feature %s %.1f us; yardstick %.3f ms"
				% [best, worst, worst_us, yard]
			)
		)
	_check(
		best < TICK_BUDGET * yard,
		"the bot game's tick %.2f yardsticks (< %.1f)" % [best / yard, TICK_BUDGET]
	)
	_check(
		worst_us / 1000.0 < FEATURE_BUDGET * yard,
		(
			"no feature's tick past %.1f yardsticks (%s %.2f)"
			% [FEATURE_BUDGET, worst, worst_us / 1000.0 / yard]
		)
	)


## A fixed piece of plain GDScript work (members, arrays, a dictionary,
## calls), best of five: the unit the tick's budgets are in.
func _yardstick() -> float:
	var best := INF
	var probe := RectCanvas.new()
	for batch in 5:
		var t0 := Time.get_ticks_usec()
		var d := {}
		var sum := 0.0
		for i in 4000:
			d[i % 97] = sum
			sum += probe.w * .5 + float(d.get(i % 89, 0.0)) * .001 + sqrt(float(i))
			probe.rects.append(Rect2i(i, 0, 1, 1))
		probe.rects.clear()
		best = minf(best, (Time.get_ticks_usec() - t0) / 1000.0)
	return best
