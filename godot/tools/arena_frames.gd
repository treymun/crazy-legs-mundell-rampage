## Pictures of the last four bosses' arenas in a real window (the graphics-card
## view players see): for each, the way in before the boss's station, the
## reveal as it is thrown, the fight with its hazards from a spot in the arena
## (god mode), and the third phase with its arena change.
## Each is <boss>_<shot>.png in out=<dir>.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/arena_frames.gd -- out=<dir> [kinds=baron,maw] [bench]
##
## bench: no pictures; frame times instead (vsync off), at the chapter's start
## and in the arena in the third phase with all of it going, side by side.
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

const STEP := 1.0 / 60.0
## kind -> [the station that lets the boss in, where to stand for the way in,
## where to look, where to stand for the reveal once it is thrown, where to
## stand for the fight (held there, god mode, looking at the boss)].
const ARENAS := {
	"baron":
	[
		"bottling",
		Vector2(62.5, 25.5),
		Vector3(64.5, 10.5, 1.6),
		Vector2(64.5, 19.5),
		Vector2(70.5, 15.5)
	],
	"swamp_king":
	[
		"fuel",
		Vector2(109.5, 15.5),
		Vector3(99.5, 21.0, .8),
		Vector2(106.5, 18.5),
		Vector2(110.5, 18.5)
	],
	"derby_champ":
	[
		"flag",
		Vector2(89.5, 29.5),
		Vector3(89.5, 52.5, .6),
		Vector2(89.5, 33.5),
		Vector2(74.5, 42.5)
	],
	"maw":
	[
		"iris",
		Vector2(64.5, 35.5),
		Vector3(60.5, 58.5, 3.0),
		Vector2(64.5, 40.5),
		Vector2(71.5, 48.5)
	],
}

var main
var out := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var kinds: Array = ARENAS.keys()
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
		elif String(arg).begins_with("kinds="):
			kinds = Array(String(arg).substr(6).split(",", false))
	if out == "":
		push_error("out=<dir> is needed")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.touring = true
	Effects.enabled = true
	var bench := OS.get_cmdline_user_args().has("bench")
	if bench:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	for kind: String in kinds:
		if bench:
			await _bench(kind)
			continue
		await _reveal(kind)
		await _fight(kind)
	print("arena frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _snap(name: String) -> void:
	if main.game != null:
		main.game.message_until = 0.0
		main.game.barks.until = 0.0
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


func _look(g: Game, at: Vector3) -> void:
	var p := g.player
	p.angle = atan2(at.y - p.y, at.x - p.x)
	var d := Vector2(at.x - p.x, at.y - p.y).length()
	var top: float = g.world.elevation(at.x, at.y) + at.z
	p.pitch = clampf((top - p.eye) / maxf(d, .1) * Renderer.base_focal, -40.0, 40.0)


func _ticks(g: Game, n: int) -> void:
	for i in n:
		g.tick(STEP, Game.Controls.new())


## The way in, then the station thrown and the boss let in.
func _reveal(kind: String) -> void:
	var spec: Array = ARENAS[kind]
	var level_id := String(BossRematch.LEVEL_OF[kind])
	main.start(level_id)
	var g: Game = main.game
	g.cheats.god = true
	g.lessons = false
	g.barks.enabled = false
	var boss := BossFight.of_kind(g, kind)
	for e: Enemy in g.enemies:
		if e != boss:
			e.dormant = true
	var left: Array = g.world.stations.filter(
		func(s: LevelData.Station) -> bool: return s.id != String(spec[0])
	)
	var moved := true
	while moved:
		moved = false
		for station: LevelData.Station in left.duplicate():
			var ready := true
			for key in station.requires:
				ready = ready and g.stations_done.has(String(key))
			if ready and not station.hidden:
				g.activate_station(station)
				left.erase(station)
				moved = true
	_stand(g, spec[1])
	_look(g, spec[2])
	g.armory.holstered = false
	g.armory.lower = 0.0
	_ticks(g, 2)
	await _snap("%s_approach" % kind)
	for station: LevelData.Station in g.world.stations:
		if station.id == String(spec[0]):
			g.activate_station(station)
	boss.alerted = true
	boss.cooldown = 99.0
	_ticks(g, 40)
	_stand(g, spec[3])
	for k in 2:
		_ticks(g, 20)
		_look(g, Vector3(boss.x, boss.y, float(spec[2].z)))
		await _snap("%s_reveal_%d" % [kind, k])


func _stand(g: Game, at: Vector2) -> void:
	var p := g.player
	p.x = at.x
	p.y = at.y
	p.vx = 0.0
	p.vy = 0.0
	p.eye = g.world.elevation(at.x, at.y) + .95
	g.district_until = 0.0
	g.message_until = 0.0


## The fight from a vantage point (held there, looking at the boss), then the
## third phase from the same spot.
func _fight(kind: String) -> void:
	var spec: Array = ARENAS[kind]
	var g: Game = BossRematch.build(Callable(main, "make_game"), kind)
	main.game = g
	g.configure(SessionStore.defaults())
	g.cheats.god = true
	g.lessons = false
	g.barks.enabled = false
	g.armory.holstered = false
	g.armory.lower = 0.0
	var boss := BossFight.of_kind(g, kind)
	_stand(g, spec[4])
	boss.hp = boss.max_hp * .6
	await _hold(g, boss, spec[4], 3.0)
	for k in 3:
		await _hold(g, boss, spec[4], 1.1)
		await _snap("%s_fight_%d" % [kind, k])
	boss.hp = boss.max_hp * .19
	g.hit_point = Vector3.INF
	boss.hurt(1.0, g)
	await _hold(g, boss, spec[4], 2.0)
	for k in 4:
		await _hold(g, boss, spec[4], .9)
		boss.hp = maxf(boss.hp, boss.max_hp * .1)
		await _snap("%s_phase3_%d" % [kind, k])


## Frame times at the chapter's start (looking the start's way) and in the
## arena in the third phase (held at the fight's spot, looking at the boss).
func _bench(kind: String) -> void:
	var spec: Array = ARENAS[kind]
	main.start(String(BossRematch.LEVEL_OF[kind]))
	var start: Game = main.game
	start.cheats.god = true
	start.spawn_grace = 99.0
	var plain := await _time(start, null, Vector2.INF, 240)
	var g: Game = BossRematch.build(Callable(main, "make_game"), kind)
	main.game = g
	g.configure(SessionStore.defaults())
	g.cheats.god = true
	var boss := BossFight.of_kind(g, kind)
	_stand(g, spec[4])
	boss.hp = boss.max_hp * .19
	g.hit_point = Vector3.INF
	boss.hurt(1.0, g)
	await _hold(g, boss, spec[4], 2.0)
	var arena := await _time(g, boss, spec[4], 240)
	print(
		(
			"BENCH %-12s start %5.2f ms (worst %5.2f)   arena, phase 3 %5.2f ms (worst %5.2f)"
			% [kind, plain[0], plain[1], arena[0], arena[1]]
		)
	)


## [mean, worst] milliseconds a frame over `frames` (each ticked and drawn).
func _time(g: Game, boss: Enemy, at: Vector2, frames: int) -> Array:
	for i in 20:
		await process_frame
	var total := 0.0
	var worst := 0.0
	var last := Time.get_ticks_usec()
	for i in frames:
		g.tick(STEP, Game.Controls.new())
		if boss != null:
			boss.hp = maxf(boss.hp, boss.max_hp * .1)
			_stand(g, at)
			_look(g, Vector3(boss.x, boss.y, boss.height * .45))
		main.render()
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		total += ms
		worst = maxf(worst, ms)
	return [total / frames, worst]


## Seconds of the fight with the player held at `at`, the view on the boss.
func _hold(g: Game, boss: Enemy, at: Vector2, seconds: float) -> void:
	for i in int(seconds / STEP):
		g.tick(STEP, Game.Controls.new())
		_stand(g, at)
		_look(g, Vector3(boss.x, boss.y, boss.height * .45))
		g.player.pitch = minf(g.player.pitch, 6.0)
		if not boss.alive:
			return
	await process_frame
