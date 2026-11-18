## Frame times of the game's worst moments in a real window (the graphics-card
## view players see), to measure before and after an optimisation. Each
## scenario builds its moment the way the frames tools do, settles a few
## frames, then times `frames` frames as tools/fall_bench.gd does: per frame
## the tick, main.render() and the wait for the frame (vsync off, no fps cap).
##
##   idle     hickston at its spawn, nothing happening (the reference)
##   strike   a ball down the range's Bowl-O-Rama, timed from the throw
##            through the pins going over (range_frames.gd bowling)
##   wreck48  a cluster of hickston's breakables broken at once, about 48
##            wreck pieces flying, the player looking at them
##   fire     hickston's hay set alight and spreading wide, looking at it
##            (live_props_frames.gd)
##   chain6   six blasts going up a few ticks apart in hickston's yard (dynamite
##            and fuel in turn), timed from the first through the smoke
##   arena    maw's arena in the third phase, its wreck steps flung, held at
##            the fight's spot looking at the boss (arena_frames_late.gd bench)
##   fivev5   a 5v5 bomb round on grainyard, ten bots fighting mid-round, the
##            local player one of them (tactical_frames.gd)
##   county   County Run on county_hickston, its clock jumped to 12 minutes:
##            the storm closing in and the horde at its cap (county_frames.gd)
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/stress_bench.gd -- [only=strike,fire] [frames=240]
##       [shots=<dir>]
##   godot --headless --path godot --script res://tools/stress_bench.gd -- check
##       [only=wreck48,arena,county] [frames=40] [hash]
##
## hash prints each scenario's frames as hashes of what was played (the
## state, the wreck pieces, the SIM snapshot every 40 frames): the same
## command on two builds prints the same when play is the same.
##
## shots= saves the window's picture at the end of each scenario
## (<dir>/<name>.png). check (headless, in check_all) holds each scene's tick
## to its budget in TICK_YARDS (yardsticks: _hold_tick), and builds the scenes with a
## 3D view made by hand and holds each, over its frames, to the shader
## instance buffer of WebGL and many phones (WorldView3D.INSTANCE_SLOTS_SMALL:
## the global uniforms and 16 slots a model part with instance uniforms,
## under INSTANCE_ROOM_SMALL parts with INSTANCE_MARGIN to spare); prints
## STRESS CHECK OK.
##
## Prints per scenario: STRESS <name> frame median/p99/max, the tick's and
## render()'s means; the 3D view's parts (WorldView3D.PART_NAMES, ms a frame);
## and what explains the cost (wreck pieces, enemies, sprites, props, actors)
## as the timing starts and as it ends. STRESS DONE at the end. God mode
## where the player could die; effects (lights) on.
##
## Benchmarks are noisy (docs/dev/checks.md): compare old and new back to
## back. Point APPDATA at a scratch folder: it runs the game with the profile
## there.
extends SceneTree

const STEP := 1.0 / 60.0
const SIM := 1.0 / 120.0
const SCENARIOS := ["idle", "strike", "wreck48", "fire", "chain6", "arena", "fivev5", "county"]
## check: each scene's tick budget, in yardsticks (_hold_tick).
const TICK_YARDS := {
	"idle": 1.6,
	"strike": 1.5,
	"wreck48": 13.0,
	"fire": 2.0,
	"chain6": 3.0,
	"arena": 2.2,
	"fivev5": 6.0,
	"county": 7.0
}
const Fire := preload("res://src/features/fire.gd")
const CountyBot := preload("res://tools/county_bot.gd")

var main
var frames := 240
var only: Array = []
var shots := ""
## check: headless, the view made by hand, the instance buffer held.
var checking := false
var hand_view: WorldView3D
var failed := false
## The most model parts with instance uniforms seen in this scenario's frames.
var most_parts := 0
## hash: each frame's play folded into one number (Replay.state_hash, the
## wreck pieces' places and turns) and the SIM snapshot's hash every 40
## frames, printed per scenario: two builds that print the same played the
## same (a speed change must leave them alike).
var hashing := false
var hashes := PackedStringArray()


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a.begins_with("only="):
			only = Array(a.substr(5).split(",", false))
		elif a.begins_with("frames="):
			frames = maxi(10, int(a.substr(7)))
		elif a.begins_with("shots="):
			shots = a.substr(6)
		elif a == "hash":
			hashing = true
		elif a == "check":
			checking = true
			if only.is_empty():
				only = ["wreck48", "arena", "county"]
	if checking and not " ".join(OS.get_cmdline_user_args()).contains("frames="):
		frames = 40
	CountyRecords.folder_override = OS.get_cache_dir().path_join("clmr-stress-bench")
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.touring = true
	Effects.enabled = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for name: String in SCENARIOS:
		if not only.is_empty() and not only.has(name):
			continue
		var why: String = await call("_" + name)
		if why != "":
			print("STRESS %s skipped: %s" % [name, why])
		main.game = null
		await process_frame
	print("STRESS DONE")
	if checking:
		print("STRESS CHECK FAILED" if failed else "STRESS CHECK OK")
	main.queue_free()
	await process_frame
	quit(1 if checking and failed else 0)


# ------------------------------------------------------------------ timing


## One frame's game: a plain tick with nothing held; returns the tick's us.
func _plain(g: Game) -> int:
	var t0 := Time.get_ticks_usec()
	g.tick(STEP, Game.Controls.new())
	return Time.get_ticks_usec() - t0


## `n` frames ticked and drawn, untimed.
func _settle(g: Game, n: int, step: Callable) -> void:
	for i in n:
		step.call(g)
		main.render()
		_by_hand()
		await process_frame


## check: headless the game draws no 3D view; one made by hand draws the frame
## the game just listed, and its model parts with instance uniforms are counted.
func _by_hand() -> void:
	if not checking or main.world_view != null or main.game == null:
		return
	if hand_view == null:
		hand_view = WorldView3D.new(main.game.art)
		main.add_child(hand_view)
	hand_view.frame(main.game)
	most_parts = maxi(most_parts, WorldView3D.instance_uniform_parts(hand_view))


## The view drawing now (the game's own in a window, else the one by hand).
func _view() -> WorldView3D:
	if main.world_view != null:
		return main.world_view
	return hand_view


## Times `frames` frames of `step` (one frame's game, returning its tick's
## microseconds) and prints the scenario's lines; `extra` adds to the counts.
func _time(name: String, g: Game, step: Callable, extra := Callable()) -> void:
	var view = main.world_view
	if view != null:
		view.parts_us.fill(0)
	most_parts = 0
	var start := _counts(g, extra)
	var whole := PackedFloat64Array()
	var each_tick := PackedFloat64Array()
	var ticks := 0
	var renders := 0
	var last := Time.get_ticks_usec()
	for i in frames:
		var tick_us: int = step.call(g)
		var t1 := Time.get_ticks_usec()
		main.render()
		var t2 := Time.get_ticks_usec()
		_by_hand()
		await process_frame
		var now := Time.get_ticks_usec()
		ticks += tick_us
		each_tick.append(tick_us / 1000.0)
		renders += t2 - t1
		if hashing:
			_fold(g, i)
		whole.append((now - last) / 1000.0)
		last = now
	var sorted := whole.duplicate()
	sorted.sort()
	var n := sorted.size()
	print(
		(
			(
				"STRESS %-8s frame median %6.2f  p99 %6.2f  max %6.2f ms"
				+ "  tick mean %5.2f  render mean %5.2f  (%d frames)"
			)
			% [
				name,
				sorted[n / 2],
				sorted[mini(n - 1, int(n * .99))],
				sorted[n - 1],
				ticks / 1000.0 / n,
				renders / 1000.0 / n,
				n
			]
		)
	)
	if view != null:
		var row := "STRESS %-8s view" % name
		for k in WorldView3D.PART_NAMES.size():
			row += "  %s %.2f" % [WorldView3D.PART_NAMES[k], view.parts_us[k] / 1000.0 / n]
		print(row)
	if hashing:
		print("STRESS %-8s hash %s" % [name, " ".join(hashes)])
		hashes.clear()
	if checking:
		_hold(name)
		# The lower quartile of its frames' ticks: the scene's own work, what a
		# busy machine (check_all's other rows) adds now and then left out.
		each_tick.sort()
		_hold_tick(name, each_tick[each_tick.size() / 4])
	if shots != "" and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(shots)
		root.get_texture().get_image().save_png(shots.path_join(name + ".png"))
	if main.overlay != null:
		print(
			(
				"STRESS %-8s HUD draw calls %d (the overlay's, last frame)"
				% [
					name,
					RenderingServer.viewport_get_render_info(
						main.overlay.get_viewport_rid(),
						RenderingServer.VIEWPORT_RENDER_INFO_TYPE_CANVAS,
						RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME
					)
				]
			)
		)
	print("STRESS %-8s start  %s" % [name, start])
	print("STRESS %-8s end    %s" % [name, _counts(g, extra)])
	print(
		(
			(
				"STRESS %-8s memory  static %.0f MB  textures %.0f MB  buffers %.0f MB  video %.0f MB"
				+ "  objects %d  nodes %d"
			)
			% [
				name,
				Performance.get_monitor(Performance.MEMORY_STATIC) / 1e6,
				Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1e6,
				Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1e6,
				Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1e6,
				Performance.get_monitor(Performance.OBJECT_COUNT),
				Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
			]
		)
	)


## This frame's play as one number (hash): the state, every wreck piece.
func _fold(g: Game, i: int) -> void:
	var f := PackedFloat64Array([Replay.state_hash(g)])
	var wreck = g.features.get("wreckage")
	if wreck != null:
		for w in wreck.wrecks:
			var b = w.body
			f.append_array([b.p.x, b.p.y, b.p.z, b.q.x, b.q.y, b.q.z, b.q.w])
	var h := hash(f)
	if i % 40 == 39:
		h = hash([h, hash(GameSnapshot.to_bytes(Replay.capture_quiet(g)))])
	hashes.append("%08x" % (h & 0xFFFFFFFF))


## What explains a frame's cost, now.
func _counts(g: Game, extra: Callable) -> String:
	var pieces := 0
	var awake := 0
	var wreck = g.features.get("wreckage")
	if wreck != null:
		for w in wreck.wrecks:
			pieces += 1
			awake += 1 if w.body.awake else 0
	var alive := 0
	for e: Enemy in g.enemies:
		alive += 1 if e.alive else 0
	var sprites: Array = g.view_frame.get("sprites", [])
	var props := -1
	var actors := -1
	var shown_wrecks := -1
	var drawing := _view()
	if drawing != null:
		props = drawing.props.shown().size()
		actors = drawing.actors.get("_shown").size()
		shown_wrecks = drawing.wrecks.shown().size()
	var text := (
		(
			"wreck pieces %d (awake %d, drawn %d)  enemies alive %d of %d  sprites %d"
			+ "  props shown %d  actors %d"
		)
		% [pieces, awake, shown_wrecks, alive, g.enemies.size(), sprites.size(), props, actors]
	)
	var view := _view()
	if view != null:
		text += (
			"  model parts %d (with instance uniforms %d; parked props %d, models %d)"
			% [
				_slots(view),
				WorldView3D.instance_uniform_parts(view),
				view.props.parked(),
				view.actors.parked()
			]
		)
	if extra.is_valid():
		text += "  " + String(extra.call(g))
	return text


## check: the scenario's frames held to the small instance buffer: the global
## uniforms (one slot each) and 16 slots a model part with instance uniforms.
func _hold(name: String) -> void:
	var globals := 0
	for key: String in WorldView3D.GLOBALS:
		var setting: Dictionary = ProjectSettings.get_setting("shader_globals/" + key, {})
		if not str(setting.get("type", "")).begins_with("sampler"):
			globals += 1
	var room := WorldView3D.INSTANCE_ROOM_SMALL - WorldView3D.INSTANCE_MARGIN
	var slots := globals + 16 * most_parts
	var ok := (
		most_parts <= room
		and slots <= WorldView3D.INSTANCE_SLOTS_SMALL - 16 * WorldView3D.INSTANCE_MARGIN
	)
	failed = failed or not ok
	print(
		(
			(
				"STRESS %-8s %s instance buffer: at most %d parts with instance uniforms (room %d),"
				+ " %d of %d slots with the %d global uniforms"
			)
			% [
				name,
				"ok  " if ok else "FAIL",
				most_parts,
				room,
				slots,
				WorldView3D.INSTANCE_SLOTS_SMALL,
				globals
			]
		)
	)


## check: the scene's tick (the lower quartile of its frames') inside its budget in
## TICK_YARDS, counted in yardsticks (a fixed piece of GDScript work timed
## here, so a slow or busy machine slows both alike; pass 10, PERFCPU).
func _hold_tick(name: String, tick_ms: float) -> void:
	if not TICK_YARDS.has(name):
		return
	var yard := _yardstick()
	var budget: float = TICK_YARDS[name]
	var ok := tick_ms < budget * yard
	failed = failed or not ok
	print(
		(
			"STRESS %-8s %s tick %.2f ms = %.2f yardsticks (budget %.1f)"
			% [name, "ok  " if ok else "FAIL", tick_ms, tick_ms / yard, budget]
		)
	)


## A fixed piece of plain GDScript work (members, arrays, a dictionary,
## calls), best of five, in ms: the unit of TICK_YARDS (as cpu_check's).
func _yardstick() -> float:
	var best := INF
	var probe: Array[Rect2i] = []
	for batch in 5:
		var t0 := Time.get_ticks_usec()
		var d := {}
		var sum := 0.0
		for i in 4000:
			d[i % 97] = sum
			sum += 160.0 + float(d.get(i % 89, 0.0)) * .001 + sqrt(float(i))
			probe.append(Rect2i(i, 0, 1, 1))
		probe.clear()
		best = minf(best, (Time.get_ticks_usec() - t0) / 1000.0)
	return best


## The model parts drawn (props, wreck pieces, actors and the seat views;
## each held a block of the shader instance buffer until pass 10).
func _slots(view: Node) -> int:
	var total := 0
	for node: Node in view.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var m := mesh.material_override as ShaderMaterial
		if m == null or m.shader == null:
			continue
		var path := m.shader.resource_path
		for kind: String in ["prop", "wreck", "actor", "cab"]:
			if path.ends_with(kind + ".gdshader"):
				total += 1
	return total


# ------------------------------------------------------------------ helpers


## A chapter started as play starts it, quiet: god mode, its hands asleep.
func _level(level_id: String) -> Game:
	main.start(level_id)
	var g: Game = main.game
	main.state = "play"
	g.cheats.god = true
	g.lessons = false
	g.barks.enabled = false
	for e: Enemy in g.enemies:
		e.dormant = true
	g.message_until = 0.0
	g.district_until = 0.0
	return g


## Stands the player at `at` looking at (tx, ty) at height tz.
func _stand(g: Game, at: Vector2, tx: float, ty: float, tz: float, floor_z := NAN) -> void:
	var p := g.player
	p.x = at.x
	p.y = at.y
	p.angle = atan2(ty - at.y, tx - at.x)
	p.floor_z = g.world.elevation(at.x, at.y) if is_nan(floor_z) else floor_z
	p.air = 0.0
	p.vertical_speed = 0.0
	p.eye = .95 + p.floor_z
	var d := Vector2(tx - at.x, ty - at.y).length()
	p.pitch = clampf((tz - p.eye) / maxf(d, .1) * View.base_focal, -50.0, 50.0)
	p.vx = 0.0
	p.vy = 0.0


## An open spot `gap` from (x, y) that sees it, the nearest way to `prefer`.
func _spot(g: Game, x: float, y: float, gap: float, prefer: float) -> Vector2:
	var w := g.world
	for reach: float in [gap, gap * .8, gap * .6]:
		for k in 32:
			var a := prefer + (k / 2) * TAU / 32.0 * (1.0 if k % 2 == 0 else -1.0)
			var at := Vector2(x + cos(a) * reach, y + sin(a) * reach)
			if (
				at.x > 1.0
				and at.y > 1.0
				and at.x < w.width - 1
				and at.y < w.height - 1
				and not w.blocked(at.x, at.y, .4)
				and absf(w.elevation(at.x, at.y) - w.elevation(x, y)) < .3
				and w.visible(at.x, at.y, x, y, 1.2, 1.0)
			):
				return at
	return Vector2(x + cos(prefer) * gap, y + sin(prefer) * gap)


# ------------------------------------------------------------------ scenarios


func _idle() -> String:
	var g := _level("hickston")
	await _settle(g, 30, _plain)
	await _time("idle", g, _plain)
	return ""


func _strike() -> String:
	var g: Game = main.make_game("range")
	main.game = g
	main.state = "play"
	g.configure(SessionStore.defaults())
	g.barks.enabled = false
	g.cheats.god = true
	if not g.features.has("range"):
		return "no range feature"
	var feature = g.features["range"]
	var bowl = feature.targets.bowling
	g.armory.active = Weapons.BOWLING
	g.armory.holstered = false
	g.armory.lower = 0.0
	var p := g.player
	p.x = 46.58
	p.y = 50.3
	p.angle = -PI / 2.0
	p.floor_z = g.world.floor_under(p.x, p.y, .05)
	p.eye = .95 + g.world.stand(p)
	p.pitch = -4.0
	await _settle(g, 30, _plain)
	g.message_until = 0.0
	feature.targets.last_angle = g.player.angle
	# range_frames.gd's throw a touch left (its 46.62 leaves a pin; 46.55 to
	# 46.6 is a strike): timed from the ball's first tick.
	g.launch(46.58, 49.9, .22, -PI / 2.0, 7.4, "bowling", 0.0, false, 108, 4.5)
	await _time(
		"strike",
		g,
		_plain,
		func(_g: Game) -> String:
			return 'pins down %d  roll "%s"' % [bowl.pins_down(), bowl.last_roll]
	)
	return ""


func _wreck48() -> String:
	var g := _level("hickston")
	var wreck = g.features.get("wreckage")
	var breaks = g.features.get("breakables")
	if wreck == null or breaks == null or not wreck.on:
		return "no wreck pieces on hickston"
	# The densest cluster of breakables that throw pieces.
	var can: Array = []
	for i in breaks.pieces.size():
		var bp = breaks.pieces[i]
		if not bp.broken and str(bp.spec.get("pieces", "")) != "":
			can.append(i)
	if can.is_empty():
		return "nothing breaks into pieces"
	var best := Vector2.ZERO
	var most := -1
	for i: int in can:
		var at := Vector2(breaks.pieces[i].x, breaks.pieces[i].y)
		var n := 0
		for j: int in can:
			if at.distance_to(Vector2(breaks.pieces[j].x, breaks.pieces[j].y)) < 5.0:
				n += 1
		if n > most:
			most = n
			best = at
	can.sort_custom(
		func(a: int, b: int) -> bool:
			return (
				best.distance_squared_to(Vector2(breaks.pieces[a].x, breaks.pieces[a].y))
				< best.distance_squared_to(Vector2(breaks.pieces[b].x, breaks.pieces[b].y))
			)
	)
	var at := _spot(g, best.x, best.y, 6.0, 0.0)
	_stand(g, at, best.x, best.y, g.world.elevation(best.x, best.y) + .6)
	await _settle(g, 20, _plain)
	# Broken nearest first, each thrown away from the player, until ~48 fly.
	var struck := 0
	for i: int in can:
		if wreck.wrecks.size() >= wreck.most:
			break
		var bp = breaks.pieces[i]
		if bp.broken:
			continue
		var away := Vector2(bp.x - at.x, bp.y - at.y).normalized()
		breaks.strike(i, 9999.0, away.x, away.y)
		struck += 1
		if struck % 4 == 0:
			g.tick(STEP, Game.Controls.new())
	print(
		(
			"STRESS wreck48  %d broken round %.1f,%.1f (%d breakables within 5 cells), seen from %.1f,%.1f"
			% [struck, best.x, best.y, most, at.x, at.y]
		)
	)
	await _settle(g, 2, _plain)
	await _time("wreck48", g, _plain)
	return ""


func _fire() -> String:
	var g := _level("hickston")
	var fire: Fire = g.features.get("fire")
	if fire == null:
		return "no fire feature"
	var w := g.world
	# The hay with the most that burns round it (live_props_frames.gd).
	var best := -1
	var most := -1
	for c in fire._fuel.size():
		if fire._catch[c] < .9 or fire._fuel[c] <= 0.0:
			continue
		var n := 0
		for d: Vector2i in Fire.NEAR:
			var q := c + d.y * w.width + d.x
			n += 1 if q >= 0 and q < fire._fuel.size() and fire._fuel[q] > 0.0 else 0
		if n > most:
			most = n
			best = c
	if best < 0:
		return "no hay on hickston"
	var x := (best % w.width) + .5
	var y := float(best / w.width) + .5
	var z := fire._z[best]
	# Further off than the pictures' spot, on the same floor, to see it spread.
	var near := Vector2(x + 3.0, y)
	var found := false
	for reach: float in [5.0, 4.2, 3.4, 2.8, 2.2]:
		for k in 16:
			var a := k * TAU / 16.0
			var spot := Vector2(x + cos(a) * reach, y + sin(a) * reach)
			if spot.x < 1.0 or spot.y < 1.0 or w.blocked(spot.x, spot.y, .3, z + .5):
				continue
			if absf(w.floor_under(spot.x, spot.y, z + .3) - z) > .1:
				continue
			if w.visible(spot.x, spot.y, x, y, z + .9, z + .3):
				near = spot
				found = true
				break
		if found:
			break
	var floor_z := w.floor_under(near.x, near.y, z + .3)
	_stand(g, near, x, y, z + .4, floor_z)
	fire.fresh()
	if not fire.ignite(x, y, z):
		return "the hay would not light"
	# Spreading wide: hickston's hay burns most from about 9 s to 15 s after
	# it is lit (some 35 cells at once), so the timing starts 9.5 s in.
	for i in 560:
		g.tick(STEP, Game.Controls.new())
		if i % 60 == 0:
			_stand(g, near, x, y, z + .4, floor_z)
	_stand(g, near, x, y, z + .4, floor_z)
	await _settle(g, 10, _plain)
	await _time(
		"fire", g, _plain, func(_g: Game) -> String: return "cells burning %d" % fire.burning.size()
	)
	return ""


## Six blasts going up 9 ticks apart in hickston's yard, five or six cells off.
func _chain6() -> String:
	var g := _level("hickston")
	var w := g.world
	var stand := Vector2.INF
	var way := Vector2.ZERO
	for cy in range(3, w.height - 3, 2):
		for cx in range(3, w.width - 3, 2):
			if stand != Vector2.INF:
				break
			for dir: Vector2 in [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]:
				var at := Vector2(cx + .5, cy + .5)
				var ok := true
				for k in range(0, 8):
					var q := at + dir * k
					for side: int in [-1, 0, 1]:
						var c: Vector2 = q + dir.orthogonal() * side
						if c.x < 1 or c.y < 1 or c.x >= w.width - 1 or c.y >= w.height - 1:
							ok = false
						elif w.solid[int(c.y) * w.width + int(c.x)] >= 0:
							ok = false
						elif absf(w.elevation(c.x, c.y) - w.elevation(at.x, at.y)) > .05:
							ok = false
				if ok:
					stand = at
					way = dir
					break
	if stand == Vector2.INF:
		return "no open yard on hickston"
	var ahead := stand + way * 5.5
	_stand(g, stand, ahead.x, ahead.y, w.elevation(ahead.x, ahead.y) + .9)
	await _settle(g, 10, _plain)
	var count := [0]
	var step := func(game: Game) -> int:
		var t0 := Time.get_ticks_usec()
		var k: int = count[0]
		count[0] = k + 1
		if k % 9 == 0 and k < 54:
			var n := k / 9
			var b := stand + way * (4.6 + n * .3) + way.orthogonal() * ((n % 3) - 1) * 1.1
			var shot := Game.Shot.new(
				b.x, b.y, w.elevation(b.x, b.y) + .15, 0, 0, 0, "fuel" if n % 2 else "tnt"
			)
			shot.owner = -1
			game.explode(shot)
		game.tick(STEP, Game.Controls.new())
		return Time.get_ticks_usec() - t0
	await _time("chain6", g, step)
	return ""


func _arena() -> String:
	var kind := "maw"
	var spot := Vector2(71.5, 48.5)
	var g: Game = BossRematch.build(Callable(main, "make_game"), kind)
	main.game = g
	main.state = "play"
	g.configure(SessionStore.defaults())
	g.cheats.god = true
	g.lessons = false
	g.barks.enabled = false
	g.armory.holstered = false
	g.armory.lower = 0.0
	var boss := BossFight.of_kind(g, kind)
	if boss == null:
		return "no %s in its rematch" % kind
	var hold := func(gg: Game) -> int:
		var t0 := Time.get_ticks_usec()
		gg.tick(STEP, Game.Controls.new())
		var us := Time.get_ticks_usec() - t0
		boss.hp = maxf(boss.hp, boss.max_hp * .1)
		_arena_stand(gg, boss, spot)
		return us
	_arena_stand(g, boss, spot)
	await _settle(g, 20, hold)
	# Down to the third phase: every wreck step above it fires at once.
	boss.hp = boss.max_hp * .19
	g.hit_point = Vector3.INF
	boss.hurt(1.0, g)
	await _settle(g, 10, hold)
	var wreck: ArenaWreckFeature = g.features.get("arena_wreck")
	await _time(
		"arena",
		g,
		hold,
		func(_g: Game) -> String:
			return (
				"boss hp %.0f%% phase %d  arena wreck pieces %d"
				% [
					100.0 * boss.hp / boss.max_hp,
					boss.boss_phase,
					wreck.pieces.size() if wreck != null else -1
				]
			)
	)
	return ""


## Held at the fight's spot looking at the boss (arena_frames_late.gd _hold).
func _arena_stand(g: Game, boss: Enemy, at: Vector2) -> void:
	var p := g.player
	p.x = at.x
	p.y = at.y
	p.vx = 0.0
	p.vy = 0.0
	p.eye = g.world.elevation(at.x, at.y) + .95
	g.district_until = 0.0
	g.message_until = 0.0
	p.angle = atan2(boss.y - p.y, boss.x - p.x)
	var d := Vector2(boss.x - p.x, boss.y - p.y).length()
	var top: float = g.world.elevation(boss.x, boss.y) + boss.height * .45
	p.pitch = minf(clampf((top - p.eye) / maxf(d, .1) * View.base_focal, -40.0, 40.0), 6.0)


func _fivev5() -> String:
	var id := "grainyard"
	var g: Game = main.make_game(id)
	main.game = g
	main.state = "play"
	g.configure(SessionStore.defaults())
	Modes.setup(g, Modes.BOMB, 10, {"arena": id})
	g.barks.enabled = false
	# Nobody falls, so all ten keep fighting through the timing.
	g.cheats.god = true
	TacticalScreens.reset()
	TacticalScreens.human = 0
	TacticalScreens.open = false
	var pilots := {}
	for p: Player in g.players:
		pilots[p.slot] = TacticalBot.new(p.slot)
	# Trigger pulls (a bot's fire held, a step): [counted, pulls in each frame].
	var pulls := [0, []]
	# Every player, this one too, played by its bot (the bots' thinking is the
	# game's in a 5v5 too, so it is in the tick's time); two game steps a
	# frame (the game's own 120 a second, as tactical_frames.gd plays it).
	var play := func(gg: Game) -> int:
		var t0 := Time.get_ticks_usec()
		var fired := 0
		for k in 2:
			var given := {}
			for p: Player in gg.players:
				if p.health > 0:
					gg.focus(p)
					var c: Game.Controls = pilots[p.slot].steer(gg)
					fired += 1 if c.fire or c.alt_fire else 0
					given[p.slot] = c
			gg.focus(gg.local_player)
			gg.tick(SIM, given)
		pulls[0] += fired
		pulls[1].append(fired)
		return Time.get_ticks_usec() - t0
	# The freeze, then into the round until the fighting is on (bots pulling
	# their triggers a second running), at least 5 s in, at most 40 s.
	var st = Modes.feature(g)
	for i in int(TacticalMode.FREEZE * 60.0):
		play.call(g)
	var since := 0
	for i in 60 * 40:
		play.call(g)
		since += 1
		var window: Array = pulls[1].slice(-60)
		var busy := 0
		for n: int in window:
			busy += n
		if since > 60 * 5 and busy >= 12:
			break
	g.message_until = 0.0
	await _settle(g, 10, play)
	print("STRESS fivev5  %.1f s into the round, phase %s" % [since / 60.0, st.phase])
	pulls[0] = 0
	await _time(
		"fivev5",
		g,
		play,
		func(gg: Game) -> String:
			var up := 0
			for p: Player in gg.players:
				up += 1 if p.health > 0 else 0
			return (
				"players up %d/%d  phase %s  trigger pulls since the timing began %d"
				% [up, gg.players.size(), st.phase, pulls[0]]
			)
	)
	return ""


func _county() -> String:
	var id := "county_hickston"
	var g: Game = main.make_game(id)
	main.game = g
	main.state = "play"
	g.configure(SessionStore.defaults())
	Modes.setup(g, Modes.COUNTY, 1)
	g.barks.enabled = false
	g.cheats.god = true
	CountyScreens.reset()
	var f = g.features.get("county")
	if f == null:
		return "no county feature"
	var bot = CountyBot.new()
	# The bot plays (its cards picked as it likes); its own steering is the
	# stand-in for a player's hands, so it is left out of the tick's time.
	var play := func(gg: Game) -> int:
		while f.on and not f.pending.is_empty():
			CountyMode.choose(gg, CountyBot.pick(gg, f), 0)
		var held = bot.steer(gg)
		var t0 := Time.get_ticks_usec()
		gg.tick(STEP, held)
		var us := Time.get_ticks_usec() - t0
		bot.moved(gg)
		return us
	# Half a minute in as play has it, then the clock jumped to 12 minutes
	# (the cap at its most, the storm due); its lull moved on with it.
	while f.run_time < 30.0:
		play.call(g)
	var jump: float = 12.0 * 60.0 - f.run_time
	f.run_time += jump
	f.next_lull += jump
	f.lull_until = 0.0
	# Into the storm's first stage closing and the horde filling up.
	for i in 60 * 12:
		play.call(g)
	if not f.storm_on:
		return "the storm is off (COUNTY STORM setting)"
	g.message_until = 0.0
	await _settle(g, 10, play)
	await _time(
		"county",
		g,
		play,
		func(gg: Game) -> String:
			return (
				"run %s  storm stage %d (closing %s)  storm bits %d  horde %d (cap %d)  level %d"
				% [
					CountyRecords.clock_text(f.run_time),
					f.storm_stage,
					str(f.storm_moving.x >= 0.0),
					f.storm_bits.size(),
					CountySpawner.alive(gg),
					CountySpawner.cap(f),
					f.level
				]
			)
	)
	return ""
