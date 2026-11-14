## COUNTY RUN play tests (not in CI: minutes per map): the bot plays each map
## until it dies (then a retry, as RETRY does), and a long run in god mode
## times every tick, counts the horde and the XP lying about, and notes when
## each level came, so pacing and performance over a long run can be read.
## Prints a table; md=<file> writes it as Markdown too.
##
##   godot --headless --path godot --script res://tools/county_play.gd
##       -- [maps=county_hickston] [die=<most seconds>] [long=<seconds>] [md=<file>]
extends SceneTree

const Bot := preload("res://tools/county_bot.gd")
const STEP := 1.0 / 60.0

var lines: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	CountyRecords.folder_override = OS.get_cache_dir().path_join("clmr-county-play")
	var maps: Array = CountyData.MAP_IDS.duplicate()
	var die := 900.0
	var long := 900.0
	var md := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("maps="):
			maps = Array(arg.substr(5).split(","))
		elif arg.begins_with("die="):
			die = float(arg.substr(4))
		elif arg.begins_with("long="):
			long = float(arg.substr(5))
		elif arg.begins_with("md="):
			md = arg.substr(3)
	var head := "| map | run | survived | level | kills | spawned | most up | XP left"
	_say(head + " | reached you | time to reach | tick median | p99 | worst | levels at |")
	_say("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	for map_id: String in maps:
		_play(main, map_id, "to death", die, false)
		_play(main, map_id, "retry", minf(die, 120.0), false)
		if long > 0.0:
			_play(main, map_id, "long, god", long, true)
	if md != "":
		var file := FileAccess.open(md, FileAccess.WRITE)
		file.store_string("\n".join(lines) + "\n")
		file.close()
	main.queue_free()
	await process_frame
	quit(0)


func _say(text: String) -> void:
	print(text)
	lines.append(text)


func _play(main, map_id: String, label: String, seconds: float, god: bool) -> void:
	var g: Game = main.make_game(map_id)
	g.configure({"difficulty": 1})
	Modes.setup(g, Modes.COUNTY, 1)
	g.cheats.god = god
	var f = g.features["county"]
	var bot = Bot.new()
	var times: Array = []
	var most := 0
	var at_level := {}
	var born := {}
	var came := {}
	var ticks := 0
	while not g.defeated() and f.run_time < seconds and ticks < int(seconds * 60.0) + 100000:
		if f.on and not f.pending.is_empty():
			CountyMode.choose(g, Bot.pick(g, f), 0)
			continue
		var t0 := Time.get_ticks_usec()
		g.tick(STEP, bot.steer(g))
		times.append((Time.get_ticks_usec() - t0) / 1000.0)
		bot.moved(g)
		ticks += 1
		most = maxi(most, CountySpawner.alive(g))
		# The routes: how soon each hand gets within 4 steps of the player.
		for e: Enemy in g.enemies:
			if not e.hostile or e.hp <= 0.0:
				continue
			var key := e.get_instance_id()
			if not born.has(key):
				born[key] = f.run_time
			if not came.has(key) and Vector2(e.x - g.player.x, e.y - g.player.y).length() < 4.0:
				came[key] = f.run_time - float(born[key])
		if f.level % 10 == 0 and not at_level.has(f.level):
			at_level[f.level] = f.run_time
	times.sort()
	var n := maxi(1, times.size())
	var levels: Array = []
	for lv: int in at_level:
		levels.append("%d@%s" % [lv, CountyRecords.clock_text(float(at_level[lv]))])
	_say(
		(
			"| %s | %s | %s%s | %d | %d | %d | %d | %d | %d%% | %.0fs | %.2f ms | %.2f ms | %.1f ms | %s |"
			% [
				map_id,
				label,
				CountyRecords.clock_text(f.run_time),
				"" if g.defeated() or god else " (alive)",
				f.level,
				g.kills,
				f.spawned,
				most,
				CountyOrbs.total_xp(f),
				roundi(100.0 * came.size() / maxf(1.0, born.size())),
				_median(came.values()),
				times[n / 2] if not times.is_empty() else 0.0,
				times[mini(n - 1, int(n * .99))] if not times.is_empty() else 0.0,
				times[n - 1] if not times.is_empty() else 0.0,
				", ".join(levels)
			]
		)
	)


static func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	values.sort()
	return float(values[values.size() / 2])
