## A quick look at a COUNTY RUN with the bot (development aid; the checks are
## tools/county_check.gd):
##
##   godot --headless --path godot --script res://tools/county_probe.gd
##       -- level=<id> seconds=<game seconds> [god]
extends SceneTree

const Bot := preload("res://tools/county_bot.gd")
const STEP := 1.0 / 60.0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	CountyRecords.folder_override = OS.get_cache_dir().path_join("clmr-county-probe")
	var level := "county_hickston"
	var seconds := 120.0
	var god := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("level="):
			level = arg.substr(6)
		elif arg.begins_with("seconds="):
			seconds = float(arg.substr(8))
		elif arg == "god":
			god = true
	var g: Game = main.make_game(level)
	g.configure({"difficulty": 1})
	Modes.setup(g, Modes.COUNTY, 1)
	g.cheats.god = god
	var bot = Bot.new()
	var ticks := 0
	var worst := 0.0
	var spent := 0.0
	var most := 0
	var f = g.features["county"]
	while g.clock < seconds and not g.defeated() and ticks < int(seconds * 60.0) + 200000:
		if f.on and not f.pending.is_empty():
			CountyMode.choose(g, Bot.pick(g, f), 0)
			continue
		var t0 := Time.get_ticks_usec()
		g.tick(STEP, bot.steer(g))
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		bot.moved(g)
		spent += ms
		worst = maxf(worst, ms)
		ticks += 1
		most = maxi(most, CountySpawner.alive(g))
		if ticks % 1800 == 0:
			print(
				(
					"t=%5.1f lv=%d xp=%d hp=%d alive=%d kills=%d orbs=%d slots=%s"
					% [
						f.run_time,
						f.level,
						f.xp,
						g.player.health,
						CountySpawner.alive(g),
						g.kills,
						f.orbs.size(),
						str(f.slots)
					]
				)
			)
	print(
		(
			"END t=%.1f defeated=%s lv=%d kills=%d spawned=%d most alive=%d tick avg %.2f ms max %.2f ms"
			% [
				f.run_time,
				g.defeated(),
				f.level,
				g.kills,
				f.spawned,
				most,
				spent / maxi(1, ticks),
				worst
			]
		)
	)
	print("picks: ", f.picks)
	print("result: ", f.result)
	main.queue_free()
	await process_frame
	quit(0)
