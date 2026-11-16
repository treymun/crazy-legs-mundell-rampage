## The dev console's tuning and overlays (src/dev_tune.gd, src/dev_overlays.gd;
## check_all runs it):
##
##   godot --headless --path godot --script res://tools/tune_check.gd
##
## `tune set` takes in a running game: a gun's fire time, an enemy kind's hp
## (the enemy in play scaled, a new one made with it), static values read from
## modes.cfg, hits.cfg and difficulty.cfg; `tune get` reads them; `tune reload`
## puts the files' own values back and says each change; a change is a
## keyframe in the run's replay; online it is refused. `tune save` writes a
## copy of a file with only the set keys' lines changed (comments, order, line
## endings kept), and the console's watch reads a saved file again. Then
## every overlay is turned on over a bot's fight drawn headless: the traces,
## tick times and listener times come in, the drawing changes the picture,
## and the run recorded with them on plays back exactly with them off (they
## change nothing in play); turned off, the `ticked` listeners are as before.
extends SceneTree

const Pilot := preload("res://tools/bot_pilot.gd")
const STEP := 1.0 / 60.0

var failures: Array = []
var main: Control


func _init() -> void:
	_run.call_deferred()


func check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var console: DevConsole = main.console
	check(console != null, "the console is there from the project folder")
	if console != null:
		print("TUNE")
		_tune(console)
		_text()
		await _save_and_watch()
		print("OVERLAYS")
		_overlays(console)
	print("")
	print("TUNE CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _tune(console: DevConsole) -> void:
	main.start("hickston")
	var g: Game = main.game
	g.cheats.god = true
	main.replays.enabled = true
	main.advance(STEP, Game.Controls.new())
	var gun := 1
	var gun_name := str(Weapons.NAMES[gun])
	var fire_was: float = Weapons.FIRE_TIME[gun]
	var disk_text := FileAccess.get_file_as_string(Tuning.WEAPONS)
	var said := console.run("tune set weapons %s fire_time %s" % [gun_name, fire_was * 2.0])
	check(
		is_equal_approx(Weapons.FIRE_TIME[gun], fire_was * 2.0) and said.contains("(live)"),
		"tune set: the %s fires every %.2f s (%s)" % [gun_name, Weapons.FIRE_TIME[gun], said]
	)
	check(
		FileAccess.get_file_as_string(Tuning.WEAPONS) == disk_text,
		"tune set leaves the file on disk as it was"
	)
	var got := console.run("tune get %s.fire_time" % gun_name)
	check(got.contains(str(fire_was * 2.0)), "tune get reads the value in play (%s)" % got)
	# An enemy kind's health: the one in play and a new one.
	console.run("spawn billy 1")
	var billy: Enemy = null
	for e: Enemy in g.enemies:
		if e.kind == "billy" and e.alive:
			billy = e
	var hp_was: float = Enemy.KINDS["billy"][0]
	var billy_max := billy.max_hp if billy != null else 0.0
	var rec: Replay = main.replays.rec
	var touches := rec.touches if rec != null else -1
	said = console.run("tune set enemies billy hp %s" % (hp_was * 2.0))
	check(
		billy != null and is_equal_approx(billy.max_hp, billy_max * 2.0),
		"the billy in play takes the new health (%.0f -> %.0f)" % [billy_max, billy.max_hp]
	)
	var fresh := Enemy.new("billy", g.player.x, g.player.y, 0.0)
	check(is_equal_approx(fresh.max_hp, hp_was * 2.0), "a new billy is made with it")
	check(
		rec != null and main.replays.rec.touches == touches + 1,
		"a tune change is a keyframe in the run's replay"
	)
	# Static values read from tuning, set from their own lines.
	said = console.run("tune set modes squad flank_swing 2.5")
	check(
		Squad.FLANK_SWING == 2.5 and said.contains("squad.FLANK_SWING"),
		"a static read with ModeData.get_value takes (%s)" % said.replace("\n", " | ")
	)
	console.run("tune set hits zones arms 0.5")
	check(HitZones.ARMS == .5, "a static read with HitData.value takes")
	console.run("tune set difficulty hands search [1.0, 2.0, 3.0, 4.0]")
	check(Squad.SEARCH == [1.0, 2.0, 3.0, 4.0], "a difficulty table takes")
	said = console.run("tune set modes squad flank_swing 3")
	check(
		typeof(Squad.FLANK_SWING) == TYPE_FLOAT and Squad.FLANK_SWING == 3.0,
		"a whole number for a value that is not keeps the value's type"
	)
	# Online: refused.
	main.net = NetPlay.new()
	said = console.run("tune set modes squad flank_swing 1.0")
	main.net = null
	check(said.begins_with("not online") and Squad.FLANK_SWING == 3.0, "online it is refused")
	# Reload: the files' own values back, each change said.
	said = console.run("tune reload")
	check(
		(
			is_equal_approx(Weapons.FIRE_TIME[gun], fire_was)
			and Enemy.KINDS["billy"][0] == hp_was
			and billy != null
			and is_equal_approx(billy.max_hp, billy_max)
			and Squad.FLANK_SWING == float(ModeData.get_value("squad", "flank_swing"))
			and HitZones.ARMS == float(HitData.value("zones", "arms", 0.0))
			and Squad.SEARCH == Difficulty.table("hands", "search")
			and said.contains("-> %s" % DevTune.shown(fire_was))
		),
		(
			"tune reload puts the files' values back and says them:\n      %s"
			% said.replace("\n", "\n      ")
		)
	)
	check(console.run("tune reload").contains("no changes"), "a second reload changes nothing")
	print("    %d static values read from tuning are watched" % console.tune.static_count())
	var t0 := Time.get_ticks_usec()
	DevTune.new()
	var t1 := Time.get_ticks_usec()
	console.tune.reload(DevTune.files(), g)
	print(
		(
			"    the console's copy of the files takes %.1f ms at start; a reload of all %.1f ms"
			% [(t1 - t0) / 1000.0, (Time.get_ticks_usec() - t1) / 1000.0]
		)
	)
	main.replays.enabled = false


## TuneText.rewrite on the real files' text: only the key's lines change.
func _text() -> void:
	var path := DevTune.path_of("bosses")
	var text := FileAccess.get_file_as_string(path)
	var cfg := ConfigFile.new()
	cfg.parse(text)
	# A plain key, a value over several lines, a new key and a new section.
	var plain_section := ""
	var plain_key := ""
	var long_section := ""
	var long_key := ""
	for section in cfg.get_sections():
		for key in cfg.get_section_keys(section):
			var value: Variant = cfg.get_value(section, key)
			if plain_key == "" and (value is float or value is int):
				plain_section = section
				plain_key = key
			if long_key == "" and value is Dictionary and var_to_str(value).contains("\n"):
				long_section = section
				long_key = key
	var out := TuneText.rewrite(text, plain_section, plain_key, "123.5")
	var long_value := {"a": [1, 2], "b": "x"}
	out = TuneText.rewrite(out, long_section, long_key, var_to_str(long_value))
	out = TuneText.rewrite(out, plain_section, "tune_check_new", "7")
	out = TuneText.rewrite(out, "tune_check", "k", "Vector2(1, 2)")
	var back := ConfigFile.new()
	var good := back.parse(out) == OK
	var others := true
	for section in cfg.get_sections():
		for key in cfg.get_section_keys(section):
			if [section, key] in [[plain_section, plain_key], [long_section, long_key]]:
				continue
			var a: Variant = cfg.get_value(section, key)
			var b: Variant = back.get_value(section, key)
			others = others and typeof(a) == typeof(b) and a == b
	check(
		(
			good
			and back.get_value(plain_section, plain_key) == 123.5
			and back.get_value(long_section, long_key) == long_value
			and back.get_value(plain_section, "tune_check_new") == 7
			and back.get_value("tune_check", "k") == Vector2(1, 2)
			and others
		),
		(
			"tune save's rewrite: [%s] %s, the multi-line [%s] %s, a new key and section"
			% [plain_section, plain_key, long_section, long_key]
		)
	)
	var comments_before := text.count(";")
	check(
		out.count(";") == comments_before and out.count("\r\n") >= text.count("\r\n"),
		"the comments and line endings stay"
	)


## `tune save` on a copy of weapons.cfg in user://, and the watch reading the
## copy again once it changes on disk.
func _save_and_watch() -> void:
	var copy := "user://tune_check_weapons.cfg"
	var source := FileAccess.get_file_as_string(Tuning.WEAPONS)
	var f := FileAccess.open(copy, FileAccess.WRITE)
	f.store_string(source)
	f.close()
	var tune := DevTune.new()
	var gun_name := str(Weapons.NAMES[1])
	var was: float = Tuning.file(copy).get_value(gun_name, "fire_time")
	tune.set_value(copy, gun_name, "fire_time", str(was + 1.0), main.game)
	var said := tune.save(PackedStringArray())
	var saved := FileAccess.get_file_as_string(copy)
	var source_lines := source.split("\n").size()
	check(
		(
			said[0].begins_with("saved 1")
			and saved.split("\n").size() == source_lines
			and saved.count(";") == source.count(";")
		),
		"tune save writes the set key only (%s)" % said[0]
	)
	var back := ConfigFile.new()
	back.load(copy)
	check(
		is_equal_approx(back.get_value(gun_name, "fire_time"), was + 1.0),
		"the file reads back with the new value"
	)
	# The file changed on disk (a second on, so its time differs): the watch
	# reads it again.
	await create_timer(1.2).timeout
	f = FileAccess.open(copy, FileAccess.WRITE)
	f.store_string(source)
	f.close()
	var lines := PackedStringArray()
	for i in 20:
		lines = tune.watch(main.game)
		if not lines.is_empty():
			break
		await create_timer(.1).timeout
	check(
		not lines.is_empty() and lines[0].contains("fire_time"),
		"the watch reads a saved file again (%s)" % (lines[0] if not lines.is_empty() else "")
	)
	# Weapons.load_tuning ran on the real weapons.cfg: nothing changed there.
	check(is_equal_approx(Weapons.FIRE_TIME[1], was), "the game's own file is untouched")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(copy))


func _listeners(g: Game) -> Array:
	var out: Array = []
	for link: Dictionary in g.events.ticked.get_connections():
		out.append(link["callable"])
	return out


func _overlays(console: DevConsole) -> void:
	main.start("hickston")
	var g: Game = main.game
	g.cheats.god = true
	main.state = "play"
	var before := _listeners(g)
	main.replays.enabled = true
	console.run("give all")
	console.run("spawn billy 3")
	# The picture without overlays, then with every one on.
	g.draw(main.canvas)
	console.draw(main.canvas)
	var canvas: Canvas = main.canvas
	var plain: PackedByteArray = canvas.pixels.duplicate()
	for what: String in ["ai", "paths", "hits", "net", "ticks", "map", "fps"]:
		console.run("show " + what)
	check(console.overlays.any() and console.show_map, "every overlay turns on")
	var pilot := Pilot.new()
	pilot.as_controls = true
	var drawn := 0
	g.armory.active = Weapons.NAMES.find("revolver")
	for t in 600:
		var c: Game.Controls = pilot.steer(g)
		c.use = false
		c.cycle = 0
		if t < 120:
			c.fire = t % 20 < 2  # a few rounds of the revolver: hitscan traces
			c.weapon = -1
		main.advance(STEP, c)
		pilot.moved(g)
		console.tick(STEP)
		if t % 20 == 0:
			g.draw(main.canvas)
			console.draw(main.canvas)
			drawn += 1
	g.draw(main.canvas)
	console.draw(main.canvas)
	var over: PackedByteArray = canvas.pixels
	var o := console.overlays
	check(o.tick_ms.size() > 0, "ticks: the tick times come in (%d)" % o.tick_ms.size())
	check(
		o.listener_ms.size() >= before.size() - 1,
		"ticks: each listener is timed (%d of %d)" % [o.listener_ms.size(), before.size()]
	)
	check(o.traces.size() > 0, "hits: the hitscan traces come in (%d)" % o.traces.size())
	check(over != plain, "the overlays draw over the view (%d frames headless)" % drawn)
	var rec: Replay = main.replays.rec
	if rec != null:
		var pb := Replay.Playback.new(Replay.from_bytes(rec.to_bytes()))
		pb.start(Callable(main, "make_game"))
		pb.run()
		check(
			pb.diverged < 0 and pb.end_matches() and rec.touches <= 2,
			(
				"a run with every overlay on plays back exactly without them (%d ticks%s)"
				% [pb.tick, "" if pb.diverged < 0 else ", parted at %d" % pb.diverged]
			)
		)
	else:
		check(false, "the run was recorded")
	console.run("show off")
	console.tick(STEP)
	var after := _listeners(g)
	check(
		not console.overlays.any() and after == before,
		"turned off, the ticked listeners are as before, in order (%d)" % after.size()
	)
	main.replays.enabled = false
	main.return_to_title()
