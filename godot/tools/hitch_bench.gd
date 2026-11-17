## The first-time hitches in a real window: the frame in which something is
## drawn for the first time in a run (its shader compiled then, unless the
## view warmed it up: WorldView3D.warm_up) and the frames of the big moments
## that come once (a barn or a water tower coming down, a twister crossing,
## the hogs stampeding, a finisher's slow motion, a chapter's pack mounted
## mid-play). Each moment is set up quiet, the view settled `settle` frames,
## then the moment started and `frames` frames timed as stress_bench.gd
## does (the tick, main.render() and the wait for the frame, vsync off).
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/hitch_bench.gd -- [only=twister,rain] [frames=90]
##
## Prints per moment: HITCH <name> first <the first frame's ms> worst <ms>
## p99 <ms> median <ms> (settled median <ms>), then HITCH DONE. The firsts
## (twister, rain, wreck, cab) only mean something the first time in
## a process whose shader cache is cold: point APPDATA at a new empty scratch
## folder each run (the browser never keeps one; a desktop or phone keeps
## its compiled shaders after the first time). Noisy like every bench here
## (docs/dev/checks.md): compare old and new back to back, more than once.
extends SceneTree

const STEP := 1.0 / 60.0
const MOMENTS := ["turn", "twister", "rain", "wreck", "cab", "barn", "tower", "hogs", "finisher"]
const SetPieces := preload("res://src/features/set_pieces.gd")
const Shape := preload("res://src/set_piece_shape.gd")

var main
var frames := 90
var settle := 30
var only: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a.begins_with("only="):
			only = Array(a.substr(5).split(",", false))
		elif a.begins_with("frames="):
			frames = maxi(10, int(a.substr(7)))
	CountyRecords.folder_override = OS.get_cache_dir().path_join("clmr-hitch-bench")
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.touring = true
	Effects.enabled = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for name: String in MOMENTS:
		if not only.is_empty() and not only.has(name):
			continue
		var why: String = await call("_" + name)
		if why != "":
			print("HITCH %s skipped: %s" % [name, why])
		main.game = null
		await process_frame
	print("HITCH DONE")
	main.queue_free()
	await process_frame
	quit()


# ------------------------------------------------------------------ timing


func _plain(g: Game) -> void:
	g.tick(STEP, Game.Controls.new())


## The first timed frame's tick and render() (ms), and the view's parts in it.
var _first_split := ""


## `n` frames of `step`, each timed (tick, render, the frame): ms.
func _frames(g: Game, n: int, step: Callable) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var last := Time.get_ticks_usec()
	for i in n:
		var view = main.world_view
		if i == 0 and view != null:
			view.parts_us.fill(0)
		var t0 := Time.get_ticks_usec()
		step.call(g)
		var t1 := Time.get_ticks_usec()
		main.render()
		var t2 := Time.get_ticks_usec()
		await process_frame
		var now := Time.get_ticks_usec()
		out.append((now - last) / 1000.0)
		if i == 0:
			_first_split = "tick %.1f render %.1f" % [(t1 - t0) / 1000.0, (t2 - t1) / 1000.0]
			if view != null:
				for k in WorldView3D.PART_NAMES.size():
					if view.parts_us[k] > 2000:
						_first_split += (
							" %s %.1f" % [WorldView3D.PART_NAMES[k], view.parts_us[k] / 1000.0]
						)
				for made in view.props.made:
					_first_split += " +" + str(made.prop)
		last = now
	return out


static func _median(times: PackedFloat64Array) -> float:
	var s := times.duplicate()
	s.sort()
	return s[s.size() / 2] if not s.is_empty() else 0.0


## Settles the view, then times the moment `start` begins (called once,
## before the first timed frame) through `frames` frames of `step`.
func _moment(name: String, g: Game, start: Callable, step := Callable()) -> void:
	var tick := step if step.is_valid() else Callable(self, "_plain")
	var calm := await _frames(g, settle, Callable(self, "_plain"))
	start.call(g)
	var times := await _frames(g, frames, tick)
	var sorted := times.duplicate()
	sorted.sort()
	var n := sorted.size()
	print(
		(
			(
				"HITCH %-9s first %7.2f  worst %7.2f  p99 %7.2f  median %6.2f ms"
				+ "  (settled median %5.2f)  first: %s"
			)
			% [
				name,
				times[0],
				sorted[n - 1],
				sorted[mini(n - 1, int(n * .99))],
				sorted[n / 2],
				_median(calm),
				_first_split
			]
		)
	)


# ------------------------------------------------------------------ helpers


func _level(level_id: String, events := false) -> Game:
	main.options["events"] = 2 if events else 0
	main.start(level_id)
	var g: Game = main.game
	main.state = "play"
	g.cheats.god = true
	g.lessons = false
	g.barks.enabled = false
	for e: Enemy in g.enemies:
		e.dormant = true
	g.spawn_grace = 99.0
	g.message_until = 0.0
	g.district_until = 0.0
	return g


func _stand(g: Game, at: Vector2, tx: float, ty: float, tz: float) -> void:
	var p := g.player
	p.x = at.x
	p.y = at.y
	p.angle = atan2(ty - at.y, tx - at.x)
	p.floor_z = g.world.elevation(at.x, at.y)
	p.air = 0.0
	p.vertical_speed = 0.0
	p.eye = .95 + p.floor_z
	var d := Vector2(tx - at.x, ty - at.y).length()
	p.pitch = clampf((tz - p.eye) / maxf(d, .1) * View.base_focal, -50.0, 50.0)
	p.vx = 0.0
	p.vy = 0.0
	p.knocked = 0.0


## An open spot `far` from `at` that sees its foot, or `at` itself.
func _vantage(g: Game, at: Vector2, far: float) -> Vector2:
	var ground := g.world.elevation(at.x, at.y)
	for ring: float in [far, far * .8, far * 1.25, far * .6]:
		for k in 32:
			var q := at + Vector2.from_angle(k * TAU / 32.0) * ring
			if q.x < 2 or q.y < 2 or q.x > g.world.width - 2 or q.y > g.world.height - 2:
				continue
			if g.world.blocked(q.x, q.y, .3):
				continue
			var z := g.world.elevation(q.x, q.y)
			if g.world.visible(q.x, q.y, at.x, at.y, z + .95, ground + 1.0):
				return q
	return at


# ------------------------------------------------------------------ moments


## The player turned round in one frame (a flick of the mouse) at the spawn.
func _turn() -> String:
	var g := _level("hickston")
	await _moment("turn", g, func(game: Game) -> void: game.player.angle += PI)
	return ""


func _twister() -> String:
	var g := _level("hickston", true)
	var ev: CountyEvents = g.features.get("events")
	if ev == null:
		return "no county events"
	ev.begin("twister")
	# Ticked on, undrawn, till the rope is all but down, then watched from off.
	while ev.tw_k <= 0.0 and g.clock < 60.0:
		g.tick(STEP, Game.Controls.new())
	var watch := _vantage(g, ev.tw_at, 22.0)
	_stand(g, watch, ev.tw_at.x, ev.tw_at.y, g.world.elevation(watch.x, watch.y) + 8.0)
	# Hidden for the settling (it was never drawn), shown from the first timed frame.
	ev.kind = ""
	var follow := func(game: Game) -> void:
		game.tick(STEP, Game.Controls.new())
		_stand(game, watch, ev.tw_at.x, ev.tw_at.y, game.world.elevation(watch.x, watch.y) + 8.0)
	await _moment("twister", g, func(_game: Game) -> void: ev.kind = "twister", follow)
	return ""


func _rain() -> String:
	var g := _level("hickston")
	var weather = g.features.get("weather")
	if weather == null:
		return "no weather"
	weather.hold(0.0, 0.0)
	await _moment("rain", g, func(_game: Game) -> void: weather.hold(1.0, .6))
	return ""


func _wreck() -> String:
	var g := _level("hickston")
	var breaks = g.features.get("breakables")
	var wreck = g.features.get("wreckage")
	if breaks == null or wreck == null or not wreck.on:
		return "no wreck pieces"
	var pick := -1
	for i in breaks.pieces.size():
		var bp = breaks.pieces[i]
		if not bp.broken and str(bp.spec.get("pieces", "")) != "":
			pick = i
			break
	if pick < 0:
		return "nothing breaks into pieces"
	var bp = breaks.pieces[pick]
	var at := _vantage(g, Vector2(bp.x, bp.y), 4.0)
	_stand(g, at, bp.x, bp.y, g.world.elevation(bp.x, bp.y) + .5)
	var hit := func(game: Game) -> void:
		var away := Vector2(bp.x - game.player.x, bp.y - game.player.y).normalized()
		breaks.strike(pick, 9999.0, away.x, away.y)
	await _moment("wreck", g, hit)
	return ""


func _cab() -> String:
	var g := _level("hickston")
	var cars = g.features.get("vehicles")
	if cars == null or cars.rides.is_empty():
		return "no vehicles on hickston"
	var ride = cars.rides[0]
	var at := _vantage(g, Vector2(ride.x, ride.y), 2.0)
	_stand(g, at, ride.x, ride.y, g.world.elevation(ride.x, ride.y) + .5)
	await _moment("cab", g, func(game: Game) -> void: cars.seat_in(game.player, 0))
	return ""


## The first set piece of `kind` on `level_id` brought down (set_piece_frames.gd bench).
func _piece(name: String, level_id: String, kind: String) -> String:
	var g := _level(level_id)
	var sp: SetPieces = g.features.get("set_pieces")
	if sp == null:
		return "no set pieces on " + level_id
	var i := -1
	for k in sp.pieces.size():
		if str(sp.spec_of(k)["kind"]) == kind:
			i = k
			break
	if i < 0:
		return "no %s on %s" % [kind, level_id]
	var box: Rect2 = sp._boxes[i]
	var mid := box.get_center()
	var eye := _vantage(g, mid, 10.0)
	_stand(g, eye, mid.x, mid.y, g.world.elevation(mid.x, mid.y) + 2.0)
	var spec: Dictionary = sp.spec_of(i)
	var bring := func(_game: Game) -> void:
		if kind == "barn":
			var posts: Array = []
			for j in sp.shapes[i].size():
				var part: Shape.Part = sp.shapes[i][j]
				if part.role == "post":
					posts.append(i * 1000 + j)
			for code: int in posts.slice(0, 2):
				sp.strike(code, 300.0, 0.0, 1.0)
		else:
			var falls: Array = spec.get("falls", [3])
			var way := (
				Vector2.from_angle(roundi(Shape.f(falls[falls.size() - 1])) * PI * .5).round()
			)
			for j in sp.shapes[i].size():
				var part: Shape.Part = sp.shapes[i][j]
				if part.role == "leg" and part.side.dot(way) > 0.0:
					sp.strike(i * 1000 + j, 400.0, way.x, way.y)
	await _moment(name, g, bring)
	return ""


func _barn() -> String:
	return await _piece("barn", "hickston", "barn")


func _tower() -> String:
	return await _piece("tower", "hickston", "tower")


func _hogs() -> String:
	var g := _level("hickston", true)
	var ev: CountyEvents = g.features.get("events")
	if ev == null:
		return "no county events"
	var started := func(_game: Game) -> void:
		ev.begin("hogs")
		var mid := ev.herd_from + ev.herd_way * minf(ev.herd_len * .5, 10.0)
		var side := Vector2(-ev.herd_way.y, ev.herd_way.x)
		var watch := mid + side * 3.4
		if g.world.blocked(watch.x, watch.y, .3):
			watch = mid - side * 3.4
		_stand(g, watch, mid.x, mid.y, g.world.elevation(mid.x, mid.y) + .4)
	var follow := func(game: Game) -> void:
		var p := game.player
		var keep := Vector2(p.x, p.y)
		var angle := p.angle
		var pitch := p.pitch
		game.tick(STEP, Game.Controls.new())
		p.x = keep.x
		p.y = keep.y
		p.angle = angle
		p.pitch = pitch
		p.knocked = 0.0
	await _moment("hogs", g, started, follow)
	return ""


func _finisher() -> String:
	var g := _level("hickston")
	var p := g.player
	var at := Vector2(p.x, p.y)
	var ahead := at + Vector2.from_angle(p.angle) * 1.4
	if g.world.blocked(ahead.x, ahead.y, .3):
		return "no room in front of the spawn"
	var e := Enemy.new("billy", ahead.x, ahead.y, p.angle + PI)
	e.dormant = false
	e.uid = g.take_uid()
	e.alerted = true
	e.floor_z = g.world.elevation(ahead.x, ahead.y)
	e.hp = e.max_hp * .2
	g.enemies.append(e)
	var used := [false]
	var use := func(game: Game) -> void:
		var c := Game.Controls.new()
		c.use = not used[0]
		used[0] = true
		game.tick(STEP, c)
	await _moment("finisher", g, func(_game: Game) -> void: pass, use)
	return ""
