## Polish pass 9's BUGS fixes that are not save numbers (save_numbers_check.gd).
## check_fixes step `polish_bugs`.
##
## - A twister lifting past the map's edge (it runs on 8 cells past its end)
##   read the ground off the map: a script error each frame on the quarry
##   and Copperhead Ridge, and its rip and fling skipped. check_all fails a
##   row whose output holds a script error, so this plays one out there.
## - A hand sent running from a barn creaking down (or from lit dynamite)
##   holds a retreat without the once-only fall-back; Python's save check
##   refused such a save, and with it every later campaign save keeping that
##   chapter (seen after a twister on Copperhead Ridge).
## - In co-op the twister and the hogs shoved player two with move_actor,
##   which took any player but the acting one for a hand: a script error a
##   frame and the rest of the twister's pull skipped (the swamp waves of the
##   bayou's arena too).
## - The blackout's word names the FLASHLIGHT key as bound (and none on a pad
##   or a touch screen); the breaker's prompt and the Crossroads' objective
##   and greeting name the USE button (they said E whatever it was).
## - The junk bench's board: USE shut it for a frame and the same press,
##   reaching the game as a use at the bench, put it up again (only ESC
##   shut it); Space, USE's fixed key, bought the tag picked.
## - The revenue raid starts in every chapter that has events (it found a
##   place on the hickston alone: the hands' gathering counted only those
##   awake), its squad set down apart (all four stood on one point).
## - A vehicle coming at BLUE: he jumps aside, never run through or hurt,
##   the same twice; with his player at the wheel he heels behind it.
## - The flashlight and the whistle on a pad and a touch screen: R3 works the
##   light while there is one, BACK held whistles (tapped, the map); the
##   touch LIGHT and WHISTLE buttons show only when they do something.
## - PHOTO MODE never opens over a chapter's opener (the pause screen's Y
##   while one waited behind it flew a camera nobody could see).
extends RefCounted

const STEP := 1.0 / 60.0
const VehicleCheck := preload("res://tools/vehicle_check.gd")


static func run(main: Control, check: Callable) -> void:
	print("\nPOLISH PASS 9 BUGS")
	for id: String in ["quarry", "moonshine"]:
		_twister_edge(main, check, id)
	_flee_save(main, check)
	_coop_shove(main, check)
	_words(main, check)
	_photo_over_opener(main, check)
	_bench_done(main, check)
	_raid_everywhere(main, check)
	_hound_and_car(main, check)
	_pad_and_touch(main, check)


static func _game(main: Control, id: String, events := 2) -> Game:
	var g: Game = main.make_game(id)
	g.configure({"difficulty": 1, "events": events})
	g.lessons = false
	g.cheats.god = true
	var history: Array = []
	for c: String in Campaign.ORDER:
		if c == id:
			break
		history.append([c, 0, 0, 0, 0, 0])
	g.history = history
	return g


static func _twister_edge(main: Control, check: Callable, id: String) -> void:
	# Where a twister wanders is the game's dice; the first game's went past
	# the edge until pass 15's balance step moved the director's draws at a
	# chapter's start (more hands held), so a few other dice are tried too:
	# one twister past the edge is what this holds.
	var played := true
	var off := false
	var w: LevelData = null
	for attempt in 6:
		var g := _game(main, id)
		if attempt > 0:
			g.rng = GameState.Rng.new(7717 * attempt)
		for t in 30:
			g.tick(STEP, Game.Controls.new())
		var ev: CountyEvents = g.features["events"]
		if not ev.begin("twister"):
			check.call(false, "%s: a twister starts" % id)
			return
		w = g.world
		for t in 60 * 180:
			g.tick(STEP, Game.Controls.new())
			var at := ev.tw_at
			off = off or at.x < 0.0 or at.y < 0.0 or at.x >= w.width or at.y >= w.height
			if ev.kind == "":
				break
		played = played and ev.kind == ""
		if off:
			break
	check.call(played, "%s: a twister plays out" % id)
	check.call(off, "%s: it lifts past the map's edge (no script error reading the ground)" % id)
	check.call(
		is_equal_approx(w.elevation_near(-5.0, w.height + 3.0), w.elevation(0.0, w.height - 1.0)),
		"%s: the ground off the map is its nearest cell's" % id
	)


static func _flee_save(main: Control, check: Callable) -> void:
	var g := _game(main, "hickston", 0)
	g.tick(STEP, Game.Controls.new())
	var sets: SetPiecesFeature = g.features.get("set_pieces")
	var boxes: Array = sets.get("_boxes")
	var hand: Enemy = null
	for e: Enemy in g.enemies:
		if e.alive and e.tactical() and not Enemy.BOSS_TITLES.has(e.kind) and hand == null:
			hand = e
	if boxes.is_empty() or hand == null:
		check.call(false, "hickston has a set piece and a hand")
		return
	var box: Rect2 = boxes[0]
	hand.x = box.get_center().x
	hand.y = box.position.y - .8
	sets.call("_warn", 0)
	check.call(
		hand.retreat != null and not hand.responded,
		"a hand by a barn creaking down runs (no fall-back used)"
	)
	var text := JSON.stringify(SessionStore.snapshot(g))
	var parsed: Variant = JSON.parse_string(text)
	var doc: Dictionary = parsed if parsed is Dictionary else {}
	SessionStore.last_error = ""
	var back := SessionStore.restore(doc, main.make_game)
	check.call(back != null, "a save with him running loads ('%s')" % SessionStore.last_error)


static func _words(main: Control, check: Callable) -> void:
	var g := _game(main, "hickston")
	g.tick(STEP, Game.Controls.new())
	var ev: CountyEvents = g.features["events"]
	g.torch_key = "K"
	g.use_key = "Y"
	ev.begin("blackout")
	check.call(
		g.notice.ends_with("FLASHLIGHT: K."), "the blackout names the bound key (%s)" % g.notice
	)
	ev.finish()
	g.torch_key = ""
	ev.begin("blackout")
	check.call(g.notice.ends_with("FLASHLIGHT."), "and no key on a pad (%s)" % g.notice)
	g.player.x = ev.breaker.x
	g.player.y = ev.breaker.y
	check.call(
		ev.prompt(g.player) == "Y: THROW THE MAIN BREAKER",
		"the breaker names the USE button (%s)" % ev.prompt(g.player)
	)
	var options: Dictionary = main.options.duplicate()
	main.options[KeyBindings.option_key("flashlight")] = KEY_K
	main.input_device = "keys"
	var keyed: String = main.torch_button()
	main.input_device = "pad"
	var padded: String = main.torch_button()
	main.options = options
	main.input_device = "touch"
	var touched: String = main.torch_button()
	main.input_device = "keys"
	check.call(
		keyed == "K" and padded == "R3" and touched == "LIGHT",
		"the front end names the key, R3 on a pad, LIGHT on touch"
	)
	var hub: Game = main.make_game("hub")
	hub.in_hub = true
	hub.use_key = "E"
	var plain := GameObjective.objective(hub)
	hub.use_key = "Y"
	check.call(
		(
			plain == "FACE A GATE AND PRESS E OR SPACE"
			and GameObjective.objective(hub).ends_with("PRESS Y")
		),
		"the Crossroads' objective names the USE button (%s)" % GameObjective.objective(hub)
	)
	main.input_device = "pad"
	main.open_hub(null)
	main.input_device = "keys"
	check.call(main.game.notice.ends_with("PRESS Y."), "and its greeting (%s)" % main.game.notice)


static func _coop_shove(main: Control, check: Callable) -> void:
	var g := _game(main, "hickston")
	Modes.setup(g, Modes.COOP, 2, {})
	for t in 30:
		g.tick(STEP, Game.Controls.new())
	var one: Player = g.players[0]
	var two: Player = g.players[1]
	g.focus(one)
	var x0 := two.x
	g.move_actor(two, .25, 0.0, GameState.PLAYER_RADIUS)
	g.move_actor(two, -.25, 0.0, GameState.PLAYER_RADIUS)
	g.move_actor(two, .25, 0.0, GameState.PLAYER_RADIUS)
	check.call(
		absf(two.x - x0) > .001 and g.player == one,
		"move_actor shoves player two while player one acts (%.2f)" % (two.x - x0)
	)
	var ev: CountyEvents = g.features["events"]
	if not ev.begin("twister"):
		check.call(false, "a co-op twister starts")
		return
	ev.phase = EventTwister.CROSS
	ev.since = g.clock
	var before := Vector2(two.x, two.y)
	for t in 20:
		two.x = ev.tw_at.x + 1.6
		two.y = ev.tw_at.y
		before = Vector2(two.x, two.y)
		g.tick(STEP, Game.Controls.new())
	check.call(
		Vector2(two.x, two.y).distance_to(before) > .0001 or two.knocked > 0.0,
		"a co-op twister pulls player two too"
	)


static func _photo_over_opener(main: Control, check: Callable) -> void:
	main.start("hickston")
	var open_before: bool = PhotoMode.allowed(main)
	main.opener.begin(main, main.game)
	var during: bool = PhotoMode.allowed(main)
	main.opener.stop(main)
	check.call(
		open_before and not during and PhotoMode.allowed(main),
		"PHOTO MODE waits out a chapter's opener"
	)


static func _frames(main: Control, n: int) -> void:
	for f in n:
		main._process(STEP)


static func _use_key(main: Control, code: int) -> void:
	main.key(code)
	Input.action_press("use")
	_frames(main, 3)
	Input.action_release("use")
	_frames(main, 3)


static func _bench_done(main: Control, check: Callable) -> void:
	var options: Dictionary = main.options.duplicate()
	main.options["bench"] = 1
	main.start("hickston")
	main.focused = true
	var g: Game = main.game
	g.cheats.god = true
	_frames(main, 3)
	var bench: GameFeature = g.features.get("bench")
	var benches: Array = bench.get("benches")
	var b: Array = benches[0]
	g.player.x = float(b[0]) + 1.0
	g.player.y = float(b[1])
	g.player.angle = PI
	for k in 8:
		if bench.call("at_bench", g.player) >= 0:
			break
		g.player.angle += PI / 4.0
	g.armory.scrap = 40
	g.armory.owned[Weapons.NAMES.find("revolver")] = true
	_use_key(main, KEY_E)
	var up := BenchScreen.open
	_use_key(main, KEY_E)
	check.call(up and not BenchScreen.open, "USE puts the bench's board up and USE again shuts it")
	_use_key(main, KEY_E)
	BenchScreen.row = 0
	BenchScreen.column = 0
	_use_key(main, KEY_SPACE)
	_frames(main, 3)
	check.call(
		not BenchScreen.open and g.armory.scrap == 40 and g.armory.mods.is_empty(),
		"Space (USE's own key) shuts it and buys nothing"
	)
	BenchScreen.reset()
	main.options = options
	main.return_to_title(true)


static func _raid_everywhere(main: Control, check: Callable) -> void:
	var started: Array = []
	var missed: Array = []
	for id: String in Campaign.ORDER:
		var g := _game(main, id)
		for t in 30:
			g.tick(STEP, Game.Controls.new())
		var ev: CountyEvents = g.features["events"]
		if not ev.allowed() or not ev.kinds_here().has("raid"):
			continue
		# As play tries it (CountyEvents.TRIES), a second between.
		var began := false
		for attempt in CountyEvents.TRIES:
			began = ev.begin("raid")
			if began:
				break
			for t in 60:
				g.tick(STEP, Game.Controls.new())
		if not began:
			missed.append(id)
			continue
		# The squad set down round its way in, not all on one point.
		var at := _squad_at(g, ev)
		var apart := true
		for a in at.size():
			for b in range(a + 1, at.size()):
				apart = apart and at[a].distance_to(at[b]) > .3
		if not apart:
			missed.append(id + " (squad on one point)")
		else:
			started.append(id)
	check.call(
		missed.is_empty() and started.size() >= 7,
		(
			"a revenue raid starts in every chapter with events, its squad apart %s %s"
			% [started, missed]
		)
	)


## Where each of the squad stands.
static func _squad_at(g: Game, ev: CountyEvents) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i: int in ev.raiders:
		var e: Enemy = g.enemies[i]
		out.append(Vector2(e.x, e.y))
	return out


static func _hound_and_car(main: Control, check: Callable) -> void:
	var runs: Array = []
	for twice in 2:
		runs.append(_car_at_hound(main))
	var first: Dictionary = runs[0]
	check.call(
		first["started"] and first["inside"] == 0 and first["hurt"] == 0.0,
		(
			"a car driven at BLUE never runs through him nor hurts him (inside %d ticks)"
			% first["inside"]
		)
	)
	check.call(first["aside"] > .5, "he jumps off its line (%.2f aside)" % first["aside"])
	check.call(first["end"] == runs[1]["end"], "the same twice")
	check.call(first["heel"] > .0, "at the wheel, his heel spot is behind the car")


static func _car_at_hound(main: Control) -> Dictionary:
	var out := {"started": false, "inside": 0, "hurt": 0.0, "aside": 0.0, "end": Vector2.ZERO}
	out["heel"] = 0.0
	var g := _game(main, "speedway", 0)
	g.configure({"difficulty": 1, "events": 0, "hound": 1})
	g.enemies.clear()
	g.enemy_ids.clear()
	for t in 10:
		g.tick(STEP, Game.Controls.new())
	var hound: GameFeature = g.features.get("hound")
	var dogs: Array = hound.get("dogs")
	if dogs.is_empty() or not VehicleCheck.walk_up(g):
		return out
	g.interact()
	var rides: GameFeature = g.features.get("vehicles")
	if not rides.call("seated", g.player):
		return out
	out["started"] = true
	var v: VehicleDrive.Ride = rides.get("rides")[0]
	var s := VehicleDrive.spec(v.kind)
	var d: Object = dogs[0]
	# His heel spot with his player at the wheel: past the car's tail.
	var back: float = hound.call("n", "heel")
	var radius: float = hound.call("n", "radius")
	var spot := HoundLegs.heel_spot(g, d, g.player, back, radius)
	var rel := spot - Vector2(v.x, v.y)
	out["heel"] = -rel.dot(Vector2(cos(v.h), sin(v.h))) - s.length * .5
	# Told to stay, right on the car's line ahead of it.
	d.set("state", 1)
	var ahead := s.length * .5 + 4.0
	d.set("x", v.x + cos(v.h) * ahead)
	d.set("y", v.y + sin(v.h) * ahead)
	var health: float = d.get("health")
	for t in 90:
		var c := Game.Controls.new()
		c.forward = 1.0
		g.tick(STEP, c)
		if VehicleDrive.out_of(s, v, d.get("x"), d.get("y"), 0.0) != Vector2.INF:
			out["inside"] += 1
	out["hurt"] = health - float(d.get("health"))
	var line := Vector2(cos(v.h), sin(v.h))
	var from_car := Vector2(d.get("x"), d.get("y")) - Vector2(v.x, v.y)
	out["aside"] = absf(from_car.dot(Vector2(-line.y, line.x)))
	out["end"] = Vector2(d.get("x"), d.get("y"))
	return out


static func _joy(button: int, down: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = 0
	ev.button_index = button as JoyButton
	ev.pressed = down
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


static func _pad_and_touch(main: Control, check: Callable) -> void:
	var options: Dictionary = main.options.duplicate()
	main.options["events"] = 2
	main.options["hound"] = 1
	main.start("hickston")
	main.focused = true
	var g: Game = main.game
	g.cheats.god = true
	for t in 5:
		g.tick(STEP, Game.Controls.new())
	var ev: CountyEvents = g.features["events"]
	var touch: TouchControls = main.touch
	main._process(STEP)
	# Only LIGHT hidden (and TALK: voice chat's, online only).
	var none_shown := touch.shown_buttons().size() == touch.buttons.size() - 2
	ev.begin("blackout")
	main._process(STEP)
	var roles: Array = touch.shown_buttons().map(func(b: Array) -> String: return str(b[0]))
	check.call(
		none_shown and roles.has("torch") and roles.has("whistle"),
		"the touch LIGHT shows in a blackout, WHISTLE with BLUE along, neither before"
	)
	var lit: bool = ev.torch_of(g.local_player)[0]
	touch.counts["torch"] = 1
	main._touch_actions()
	_flush(main, g)
	var after_touch: bool = ev.torch_of(g.local_player)[0]
	main._pad_play_extras(0, {JOY_BUTTON_RIGHT_STICK: true}, STEP)
	_flush(main, g)
	var after_pad: bool = ev.torch_of(g.local_player)[0]
	check.call(
		after_touch != lit and after_pad == lit, "the touch LIGHT and R3 switch the flashlight"
	)
	# BACK tapped: the map; held: the whistle (BLUE told to stay).
	var hound: GameFeature = g.features.get("hound")
	var dog: Object = hound.call("dog_of", g.local_player)
	var map_was := g.map
	_joy(JOY_BUTTON_BACK, true)
	main._pad_play_extras(0, {JOY_BUTTON_BACK: true}, STEP)
	_joy(JOY_BUTTON_BACK, false)
	main._pad_play_extras(0, {}, STEP)
	_flush(main, g)
	var tapped := g.map != map_was
	var state_was: int = dog.get("state")
	_joy(JOY_BUTTON_BACK, true)
	main._pad_play_extras(0, {JOY_BUTTON_BACK: true}, STEP)
	for t in 40:
		main._pad_play_extras(0, {}, STEP)
	_joy(JOY_BUTTON_BACK, false)
	main._pad_play_extras(0, {}, STEP)
	_flush(main, g)
	check.call(
		tapped and g.map != map_was and int(dog.get("state")) != state_was,
		"BACK tapped opens the map, held whistles for BLUE (and leaves the map be)"
	)
	ev.finish()
	main._process(STEP)
	roles = touch.shown_buttons().map(func(b: Array) -> String: return str(b[0]))
	check.call(not roles.has("torch"), "the power back, the LIGHT button goes")
	main.options = options
	main.return_to_title(true)


## The replay ops the front end acted with reach the game on its next tick.
static func _flush(_main: Control, g: Game) -> void:
	g.tick(STEP, Game.Controls.new())
