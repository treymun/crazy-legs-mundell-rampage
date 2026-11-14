## The CHATTER setting and the cuss pack (src/cuss_lines.gd,
## features/enemy_barks.gd, game_state.gd Barks), headless, with an ear that
## says every cue is made and writes down what is played (no recordings
## needed; tools/check_fixes.gd runs it; this also runs on its own):
##
##   Godot --headless --path <project> --script res://tools/chatter_check.gd
##
## Every line has a cuss word and its CLEAN caption hides it; a hand mixes the
## cuss pack's lines with its old ones under CUSSIN', says the CLEAN copies
## under CLEAN and nothing under OFF; Mundell says his aloud with the caption
## to match, and falls back to his old wisecracks with CHATTER OFF; in a 2v2 a
## bot crows over a kill and talks at the plant, never this machine's player.
extends SceneTree

var failures: Array = []


## Says every cue is there and keeps what was played.
class Ear:
	extends QuietSound
	var played: Array = []

	func has(_cue: String) -> bool:
		return true

	func play(name: String, _volume := 1.0, _pan := 0.0, _cutoff := 0.0) -> void:
		played.append(name)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	run(
		main,
		func(ok: bool, text: String) -> void:
			print("  ok   " if ok else "  FAIL ", text)
			if not ok:
				failures.append(text)
	)
	print("")
	print("CHATTER CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


static func run(main, check: Callable) -> void:
	print("\nCHATTER (THE CUSS PACK)")
	_lines(check)
	_hands(main, check)
	_mundell(main, check)
	_bots(main, check)


static func _lines(check: Callable) -> void:
	var data := CussLines.data()
	var count := 0
	var starred := true
	var hidden := true
	for group: String in ["enemies", "mundell", "tactical"]:
		var part: Dictionary = data.get(group, {})
		var sets: Array = [part] if group == "mundell" else part.values()
		for moments: Dictionary in sets:
			for moment: String in moments:
				for text: String in moments[moment]:
					count += 1
					starred = starred and text.count("*") >= 2 and text.count("*") % 2 == 0
					var word := text.get_slice("*", 1)
					hidden = (
						hidden
						and not CussLines.caption(text, CussLines.CLEAN).contains(word)
						and CussLines.caption(text, CussLines.CUSSIN).contains(word)
					)
	check.call(count >= 100, "the cuss pack has its lines (%d)" % count)
	check.call(starred, "every line marks its cuss words")
	check.call(hidden, "a CLEAN caption hides them, CUSSIN' shows them")


static func _game(main, level: String, setup := Callable()) -> Array:
	var g: Game = main.make_game(level)
	g.configure({"difficulty": 1})
	if setup.is_valid():
		setup.call(g)
	var ear := Ear.new()
	g.sound = ear
	g.speaker = ear
	return [g, ear]


static func _hands(main, check: Callable) -> void:
	var made := _game(main, "hickston")
	var g: Game = made[0]
	var ear: Ear = made[1]
	var barks = g.features["enemy_barks"]
	var hand: Enemy = null
	for e: Enemy in g.enemies:
		if e.alive and barks.voice_of(e) == "hick":
			hand = e
			break
	if hand == null:
		check.call(false, "a hick to listen to in Hickston")
		return
	hand.x = g.player.x + 2.0
	hand.y = g.player.y
	var heard := {}
	for chatter in [CussLines.CUSSIN, CussLines.CLEAN, CussLines.OFF]:
		g.chatter = chatter
		ear.played.clear()
		var captions: Array = []
		for i in 40:
			barks._next = 0.0
			barks._own = {}
			g.caption_until = 0.0
			barks._bark(hand, "spot")
			captions.append(g.caption)
		heard[chatter] = [ear.played.duplicate(), captions]
	var cussin: Array = heard[CussLines.CUSSIN][0]
	var clean: Array = heard[CussLines.CLEAN][0]
	var cuss := cussin.filter(func(c: String) -> bool: return c.begins_with("cuss_"))
	check.call(
		cuss.size() > 10 and cuss.size() < cussin.size(),
		(
			"CUSSIN': a hand mixes the cuss pack with its old lines (%d of %d)"
			% [cuss.size(), cussin.size()]
		)
	)
	check.call(
		(
			clean
			. filter(func(c: String) -> bool: return c.begins_with("cuss_"))
			. all(func(c: String) -> bool: return c.ends_with("_clean"))
		),
		"CLEAN: only the quacked-over copies"
	)
	check.call(
		(heard[CussLines.CLEAN][1] as Array).any(func(t: String) -> bool: return t.contains("#")),
		"CLEAN: the captions show #@!%"
	)
	check.call(heard[CussLines.OFF][0].is_empty(), "OFF: the hands say nothing")


static func _mundell(main, check: Callable) -> void:
	var made := _game(main, "hickston")
	var g: Game = made[0]
	var ear: Ear = made[1]
	g.barks.enabled = true
	var same := true
	var spoken := Game.Barks.spoken_lines()
	for moment: String in Game.Barks.LINES:
		var said: Array = spoken.get(moment, [])
		var shown: Array = Game.Barks.LINES[moment]
		same = same and said.size() == shown.size()
		for i in mini(said.size(), shown.size()):
			same = same and String(said[i]).to_upper() == String(shown[i])
	check.call(
		same and spoken.size() == Game.Barks.LINES.size(),
		"every one of Mundell's wisecracks is spoken as it is shown"
	)
	var heard := {}
	for chatter in [CussLines.CUSSIN, CussLines.CLEAN]:
		g.chatter = chatter
		ear.played.clear()
		var shown: Array = []
		for i in 40:
			g.barks.say(g, "kill", true)
			shown.append(g.barks.text)
		heard[chatter] = [ear.played.duplicate(), shown]
	var cussin: Array = heard[CussLines.CUSSIN][0]
	var cuss := cussin.filter(func(c: String) -> bool: return c.begins_with("cuss_mundell_kill_"))
	var plain := cussin.filter(func(c: String) -> bool: return c.begins_with("mundell_kill_"))
	check.call(
		cussin.size() == 40 and cuss.size() > 5 and plain.size() > 5,
		(
			"CUSSIN': Mundell says every kill line aloud, cussin' and not (%d and %d)"
			% [cuss.size(), plain.size()]
		)
	)
	var clean: Array = heard[CussLines.CLEAN][0]
	check.call(
		(
			clean
			. filter(func(c: String) -> bool: return c.begins_with("cuss_"))
			. all(func(c: String) -> bool: return c.ends_with("_clean"))
		),
		"CLEAN: only his quacked-over copies of the cussin' ones"
	)
	check.call(
		(heard[CussLines.CLEAN][1] as Array).any(func(t: String) -> bool: return t.contains("#")),
		"CLEAN: their captions show grawlix"
	)
	ear.played.clear()
	g.chatter = CussLines.CUSSIN
	g.barks.next_any = 0.0
	g.barks.last_at = {}
	g.barks.kill(g, true)
	check.call(
		ear.played.size() == 1 and String(ear.played[0]).contains("headshot"),
		"a headshot gets its own line (%s)" % [ear.played]
	)
	g.chatter = CussLines.OFF
	ear.played.clear()
	g.barks.say(g, "kill", true)
	check.call(
		ear.played.is_empty() and Game.Barks.LINES["kill"].has(g.barks.text),
		"OFF: his old wisecracks, on the screen only"
	)


static func _bots(main, check: Callable) -> void:
	var made := _game(
		main,
		"pumpngo",
		func(g: Game) -> void:
			var options := Modes.TAGTEAM_OPTIONS.duplicate()
			options["arena"] = "pumpngo"
			Modes.setup(g, Modes.BOMB, Modes.TAGTEAM_PLAYERS, options)
			g.tick(1.0 / 120.0, {})
	)
	var g: Game = made[0]
	var ear: Ear = made[1]
	g.chatter = CussLines.CUSSIN
	var st = Modes.feature(g)
	var barks = g.features["enemy_barks"]
	var me: Player = g.local_player
	var mate: Player = g.players[2]
	var foe: Player = g.players[1]
	for p: Player in [mate, foe]:
		p.x = me.x + 1.0
		p.y = me.y
	barks._tactical(0.0)
	ear.played.clear()
	st.killed_by[foe.slot] = [Modes.tag(mate), "TEST", false]
	foe.health = 0
	barks._next = 0.0
	barks._tactical(0.0)
	var voice := "hick" if TacticalMode.side_of(st, mate) == 0 else "deputy"
	check.call(
		ear.played.size() == 1 and String(ear.played[0]).begins_with("cuss_%s_kill_" % voice),
		"a bot crows over its kill in its side's voice (%s)" % [ear.played]
	)
	ear.played.clear()
	foe.health = 100
	barks._tactical(0.0)
	st.killed_by[foe.slot] = [Modes.tag(me), "TEST", false]
	foe.health = 0
	barks._next = 0.0
	barks._own = {}
	barks._tactical(0.0)
	check.call(ear.played.is_empty(), "this machine's own player says nothing")
	var planter: Player = null
	for p: Player in g.players:
		if p != me and TacticalMode.side_of(st, p) == 0:
			planter = p
	planter.health = 100
	planter.x = me.x + 1.5
	planter.y = me.y
	st.bomb = {"state": "planted", "slot": planter.slot, "x": planter.x, "y": planter.y}
	barks._next = 0.0
	barks._own = {}
	barks._tactical(0.0)
	check.call(
		ear.played.size() == 1 and String(ear.played[0]).contains("_plant_"),
		"the planter says so (%s)" % [ear.played]
	)
