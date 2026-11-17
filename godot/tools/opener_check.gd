## The chapter openers, headless (src/opener.gd, src/opener_art.gd,
## data/tuning/openers.json):
##
##   Godot --headless --path <project> --script res://tools/opener_check.gd
##
## - Every campaign chapter has an opener: camera shots inside its map, a
##   tagline, a card style, a boss cel, its growl, sting and line in the bank
##   (the line's caption the boss's own), the narrator's two lines built,
##   STT-matched (the manifest's prompt is the caption, validation ok) and in
##   the bank, its music sting; it lasts 10 to 17 s; every card fits the
##   screen.
## - The OPENERS setting (FIRST TIME, ALWAYS, OFF) is on a settings page and
##   decides: FIRST TIME plays a chapter's once (kept in its own file), ALWAYS
##   every fresh start, OFF never; never the hub, COUNTY RUN, a retry or a
##   loaded save (a game already under way).
## - It plays without ticking the game: the snapshot and the clock are the
##   same after it as before; a key skips it, so does a click; left alone it
##   ends by itself; the camera is never left on the game. A chapter played
##   after its opener is, tick for tick, the chapter played without one.
## - Each chapter's opener draws at its key moments without an error.
## Fails on any script or engine error.
extends SceneTree

var failures: Array = []
var main
var repo := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	repo = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	var op: ChapterOpener = main.opener
	op.tools_write = true
	op.seen_path = OS.get_cache_dir().path_join("clmr_opener_check_seen.json")
	DirAccess.remove_absolute(op.seen_path)
	var tally := CrashLog.tally()
	_data()
	_setting()
	_when()
	_still()
	_exact()
	_draws()
	tally.stop()
	_check(
		tally.errors == 0,
		(
			"no script or engine errors"
			+ ("" if tally.errors == 0 else " (%d: %s)" % [tally.errors, tally.first_errors[0]])
		)
	)
	DirAccess.remove_absolute(op.seen_path)
	print("")
	print("OPENER CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


func _manifest() -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(repo.path_join("audio_src/manifest.json"))
	)
	return (parsed as Dictionary).get("cues", {}) if parsed is Dictionary else {}


# ------------------------------------------------------------------ the data


func _data() -> void:
	print("THE OPENERS' DATA")
	var art: Assets = main.art
	var cues := _manifest()
	var bosses = load("res://src/features/boss_voices.gd")
	var said := {}
	for who: String in bosses.LINES:
		var lines: Array = bosses.LINES[who]
		for i in mini(lines.size(), bosses.MOMENTS.size()):
			said["boss_%s_%s" % [who, bosses.MOMENTS[i]]] = str(lines[i])
	var missing: Array = []
	var bad_shots: Array = []
	var bad_audio: Array = []
	var bad_lines: Array = []
	var bad_cards: Array = []
	for id: String in Campaign.ORDER:
		if not ChapterOpener.has_opener(id):
			missing.append(id)
			continue
		var e := ChapterOpener.entry(id)
		var level := LevelData.load_level(id, art)
		var shots := ChapterOpener.shots_of(id)
		if shots.size() < 2:
			bad_shots.append("%s (%d shots)" % [id, shots.size()])
		for shot: Dictionary in shots:
			var secs: float = shot.get("secs", 0.0)
			for key: String in ["from", "to", "look", "look_to"]:
				var at: Array = shot.get(key, [])
				var x: float = at[0] if at.size() > 2 else -1.0
				var y: float = at[1] if at.size() > 2 else -1.0
				if x < 0.0 or y < 0.0 or x > level.width or y > level.height or secs <= 0.0:
					bad_shots.append("%s %s %s" % [id, key, at])
		if str(e.get("tagline", "")) == "" or not OpenerArt.STYLES.has(str(e.get("card", ""))):
			bad_cards.append(id + " (tagline or card style)")
		var boss: Dictionary = e.get("boss", {})
		var cel := art.art(str(boss.get("cel", "")))
		var cel_w: int = cel["w"]
		if cel_w < 8:
			bad_audio.append(id + " cel " + str(boss.get("cel", "")))
		var wanted := [
			str(boss.get("growl", "")),
			str(boss.get("sting", "")),
			str(boss.get("line", "")),
			"sting_open_" + id
		]
		var lines := ChapterOpener.lines_of(id)
		if lines.size() != 2:
			bad_lines.append("%s has %d lines" % [id, lines.size()])
		for n in lines.size():
			var cue := "narr_%s_%d" % [id, n]
			wanted.append(cue)
			var made: Dictionary = cues.get(cue, {})
			if str(made.get("validation", "")) != "ok" or str(made.get("prompt", "")) != lines[n]:
				bad_lines.append("%s (%s)" % [cue, made.get("validation", "not made")])
			if str(made.get("voice", made.get("speaker", "narrator"))) == "":
				bad_lines.append(cue + " (no voice)")
		for cue: String in wanted:
			if cue == "" or art.cue(cue) == null:
				bad_audio.append("%s %s" % [id, cue])
		if str(said.get(str(boss.get("line", "")), "")) != str(boss.get("say", "")):
			bad_lines.append("%s boss caption %s" % [id, boss.get("say", "")])
		var card := OpenerArt.card(
			str(e.get("card", "")), ChapterOpener.number_of(id), Campaign.title_of(id), id
		)
		var img: Image = card["image"]
		if img.get_width() > 316 or img.get_height() > 70:
			bad_cards.append("%s card %dx%d" % [id, img.get_width(), img.get_height()])
	_check(missing.is_empty(), "every campaign chapter has an opener %s" % [missing])
	_check(bad_shots.is_empty(), "every shot is timed and inside its map %s" % [bad_shots])
	_check(bad_cards.is_empty(), "every card has its style and tagline and fits %s" % [bad_cards])
	_check(
		bad_audio.is_empty(),
		(
			"every boss cel, growl, sting, line, opener sting and narrator line is in the bank %s"
			% [bad_audio]
		)
	)
	_check(
		bad_lines.is_empty(),
		"the narrator's lines are built from STT-matched takes of their captions %s" % [bad_lines]
	)


# ------------------------------------------------------------------ the setting


func _setting() -> void:
	print("THE SETTING")
	var found := false
	for page: Array in SessionStore.setup_pages():
		for row: SessionStore.Setting in page[1]:
			if row.key == "openers" and row.choices == ["FIRST TIME", "ALWAYS", "OFF"]:
				found = row.default_value == ChapterOpener.FIRST_TIME
	_check(found, "OPENERS is on a settings page: FIRST TIME (the default), ALWAYS, OFF")
	for mode: int in [ChapterOpener.FIRST_TIME, ChapterOpener.ALWAYS, ChapterOpener.OFF]:
		main.options["openers"] = mode
		main.apply_options()
		_check(main.opener.mode == mode, "the setting reaches the opener (%d)" % mode)


func _fresh(id := "hickston") -> Game:
	main.start(id)
	main.state = "play"
	return main.game


# ------------------------------------------------------------------ when


func _when() -> void:
	print("WHEN IT PLAYS")
	var op: ChapterOpener = main.opener
	main.options["openers"] = ChapterOpener.FIRST_TIME
	main.apply_options()
	var g := _fresh("fair")
	_check(op.pending == g, "FIRST TIME: a chapter's first start has its opener due")
	_check(op.start(main) and op.playing, "it starts on the first play frame")
	main.key(KEY_SPACE)
	_check(not op.playing, "a key skips it")
	_check(
		FileAccess.file_exists(op.seen_path) and op.seen.has("fair"), "the chapter is noted as seen"
	)
	g = _fresh("fair")
	_check(op.pending == null, "FIRST TIME: not again for that chapter")
	main.options["openers"] = ChapterOpener.ALWAYS
	main.apply_options()
	g = _fresh("fair")
	_check(op.pending == g, "ALWAYS: every fresh start")
	main.restart_chapter(g)
	_check(op.pending == null, "never on the death screen's retry")
	main.options["openers"] = ChapterOpener.OFF
	main.apply_options()
	g = _fresh("fair")
	_check(op.pending == null, "OFF: never")
	main.options["openers"] = ChapterOpener.ALWAYS
	main.apply_options()
	main.open_hub()
	_check(op.pending == null, "never in the hub")
	main.start_county("county_hickston")
	_check(op.pending == null, "never in COUNTY RUN")
	main.mode_name = ""
	main.showdown_on = false
	var loaded: Game = main.make_game("sawmill")
	loaded.clock = 42.0
	_check(not op.due(main, loaded, true), "never for a game already under way (a loaded save)")
	_check(not op.due(main, main.make_game("sawmill"), false), "never off the campaign")
	g = _fresh("quarry")
	_check(op.start(main), "a click skips it too")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	main._input(click)
	_check(not op.playing and main.block_fire, "(and the click does not fire)")


# ------------------------------------------------------------------ holds still


func _still() -> void:
	print("THE GAME HOLDS STILL")
	var op: ChapterOpener = main.opener
	var g := _fresh("hickston")
	var before := GameSnapshot.capture(g)
	var clock: float = g.clock
	_check(op.start(main), "the opener starts")
	var frames := 0
	while op.playing and frames < 60 * 30:
		op.frame(main, 1.0 / 30.0)
		if frames % 10 == 0:
			main.render()
		frames += 1
	_check(not op.playing, "left alone it ends by itself (%.1f s)" % (frames / 30.0))
	_check(op.length >= 10.0 and op.length <= 17.0, "it lasts %.1f s (10 to 17)" % op.length)
	_check(g.eye_override.is_empty(), "the camera is not left on the game")
	var after := GameSnapshot.capture(g)
	_check(
		GameSnapshot.same(before, after),
		"nothing of play moved: " + GameSnapshot.first_difference(before, after)
	)
	_check(g.clock == clock, "the game's clock held still")
	var moved: Array = []
	for id: String in Campaign.ORDER:
		g = _fresh(id)
		before = GameSnapshot.capture(g)
		if not op.start(main):
			moved.append(id + " (no opener)")
			continue
		for k: Array in op.key_times():
			op.frame(main, float(k[1]) - op.at)
			main.render()
		op.stop(main)
		after = GameSnapshot.capture(g)
		if not GameSnapshot.same(before, after):
			moved.append(id + " " + GameSnapshot.first_difference(before, after))
	_check(moved.is_empty(), "nor in any chapter %s" % [moved])


## The same chapter played from its start for two seconds, once after its
## opener and once with none: the same game.
func _exact() -> void:
	print("PLAY IS THE SAME AFTER IT")
	var op: ChapterOpener = main.opener
	main.options["openers"] = ChapterOpener.OFF
	main.apply_options()
	var plain := _fresh("hickston")
	var held := Game.Controls.new()
	held.forward = 1.0
	for i in 120:
		plain.tick(1.0 / 60.0, held)
	var without := GameSnapshot.capture(plain)
	main.options["openers"] = ChapterOpener.ALWAYS
	main.apply_options()
	var g := _fresh("hickston")
	op.start(main)
	while op.playing:
		main.render()  # only opener frames: play itself draws nothing here
		op.frame(main, .25)
	for i in 120:
		g.tick(1.0 / 60.0, held)
	var with := GameSnapshot.capture(g)
	_check(
		GameSnapshot.same(without, with),
		"two seconds of play match tick for tick: " + GameSnapshot.first_difference(without, with)
	)


# ------------------------------------------------------------------ drawing


func _draws() -> void:
	print("EVERY OPENER DRAWS")
	var op: ChapterOpener = main.opener
	main.options["openers"] = ChapterOpener.ALWAYS
	main.apply_options()
	var short: Array = []
	for id: String in Campaign.ORDER:
		_fresh(id)
		if not op.start(main):
			short.append(id + " (did not start)")
			continue
		var keys := op.key_times()
		if keys.size() < 5:
			short.append("%s (%d key moments)" % [id, keys.size()])
		for k: Array in keys:
			op.at = float(k[1])
			main.render()
		op.stop(main)
	_check(short.is_empty(), "every chapter's opener starts and draws its key moments %s" % [short])
