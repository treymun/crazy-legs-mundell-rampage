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
##   arena    maw's arena in the third phase, its wreck steps flung, held at
##            the fight's spot looking at the boss (arena_frames_late.gd bench)
##   fivev5   a 5v5 bomb round on grainyard, ten bots fighting mid-round, the
##            local player one of them (tactical_frames.gd)
##   county   County Run on county_hickston, its clock jumped to 12 minutes:
##            the storm closing in and the horde at its cap (county_frames.gd)
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/stress_bench.gd -- [only=strike,fire] [frames=240]
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
const SCENARIOS := ["idle", "strike", "wreck48", "fire", "arena", "fivev5", "county"]
const Fire := preload("res://src/features/fire.gd")
const CountyBot := preload("res://tools/county_bot.gd")

var main
var frames := 240
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
	main.queue_free()
	await process_frame
	quit()


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
		await process_frame


## Times `frames` frames of `step` (one frame's game, returning its tick's
## microseconds) and prints the scenario's lines; `extra` adds to the counts.
func _time(name: String, g: Game, step: Callable, extra := Callable()) -> void:
	var view = main.world_view
	if view != null:
		view.parts_us.fill(0)
	var start := _counts(g, extra)
	var whole := PackedFloat64Array()
	var ticks := 0
	var renders := 0
	var last := Time.get_ticks_usec()
	for i in frames:
		var tick_us: int = step.call(g)
		var t1 := Time.get_ticks_usec()
		main.render()
		var t2 := Time.get_ticks_usec()
		await process_frame
		var now := Time.get_ticks_usec()
		ticks += tick_us
		renders += t2 - t1
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
	if main.world_view != null:
		props = main.world_view.props.shown().size()
		actors = main.world_view.actors._shown.size()
		shown_wrecks = main.world_view.wrecks.shown().size()
	var text := (
		(
			"wreck pieces %d (awake %d, drawn %d)  enemies alive %d of %d  sprites %d"
			+ "  props shown %d  actors %d"
		)
		% [pieces, awake, shown_wrecks, alive, g.enemies.size(), sprites.size(), props, actors]
	)
	if main.world_view != null:
		var view: WorldView3D = main.world_view
		text += (
			"  instance parts %d of %d (parked props %d, models %d)"
			% [
				_slots(view),
				WorldView3D.instance_parts(),
				view.props.parked(),
				view.actors.parked()
			]
		)
	if extra.is_valid():
		text += "  " + String(extra.call(g))
	return text


## The model parts that hold a block of the shader instance buffer (16 of
## its vec4 slots each, shown or hidden, whatever the shader uses: room for
## WorldView3D.instance_parts(), 250 here, 60 where a uniform block holds
## 16 KB, as on many phones and in WebGL): props, wreck pieces, actors and
## the seat views, every part with instance uniforms.
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
