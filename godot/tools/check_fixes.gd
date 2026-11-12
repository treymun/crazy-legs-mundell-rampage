## Regression checks for the porting bugs found in the parity audit against the
## Python original. Each block fails if the bug it names comes back.
##
##   Godot --headless --path <project> --script res://tools/check_fixes.gd
##
## Like bot_campaign.gd this writes saves into the game's user:// profile; point
## APPDATA at a scratch folder first if the real profile must stay untouched.
extends SceneTree

var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, text: String) -> void:
	if condition:
		print("  ok   ", text)
	else:
		print("  FAIL ", text)
		failures.append(text)


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"

	print("RANDOM RANGE (was [0, 0.5): one-sided spread, doubled hit and drop odds)")
	var rng := Game.Rng.new(1997)
	var low := 1.0
	var high := 0.0
	var total := 0.0
	var picks := {}
	for i in 20000:
		var value := rng.random()
		low = minf(low, value)
		high = maxf(high, value)
		total += value
		picks[rng.choice([0, 1, 2, 3, 4])] = true
	check(low >= 0.0 and high < 1.0, "values stay inside [0, 1)")
	check(high > 0.99 and low < 0.01, "values reach both ends (max %.4f)" % high)
	check(absf(total / 20000.0 - 0.5) < 0.01, "mean is one half (%.4f)" % (total / 20000.0))
	check(picks.size() == 5, "choice() reaches every element of a list of five")
	var spread_low := 0.0
	var spread_high := 0.0
	for i in 2000:
		var offset := rng.uniform(-.135, .135)
		spread_low = minf(spread_low, offset)
		spread_high = maxf(spread_high, offset)
	check(spread_low < -.12 and spread_high > .12, "shotgun spread covers both sides")

	print("\nDAMAGE ROUNDING (Python rounds exact halves to the even neighbour)")
	check(Game.round_even(22.5) == 22.0, "22.5 -> 22")
	check(Game.round_even(4.5) == 4.0, "4.5 -> 4")
	check(Game.round_even(23.5) == 24.0, "23.5 -> 24")
	check(
		Game.round_even(16.49) == 16.0 and Game.round_even(16.51) == 17.0,
		"non-halves round normally"
	)

	print("\nCROSSROADS SURFACES (were missing from the renderer)")
	check(not Renderer.screen_hole(3, 60), "screen frame is solid")
	check(not Renderer.screen_hole(50, 30), "screen centre post is solid")
	check(not Renderer.screen_hole(20, 110), "boarded repair is solid")
	check(Renderer.screen_hole(30, 25), "open mesh is see-through")
	main.start("hickston")
	var hub_renderer: Renderer = main.game.renderer
	hub_renderer.world_motion = 0
	hub_renderer.time = 0.0
	hub_renderer._prepare_hub(true)
	check(hub_renderer.hub_fx, "effects switch on in the hub half of the map")
	check(
		hub_renderer.tower_shadow(23.45, 47.95, 0.0) < 0.7, "tank shadow darkens the service road"
	)
	check(hub_renderer.tower_shadow(12.0, 46.5, 0.0) == 1.0, "road away from the tower is unshaded")
	hub_renderer._prepare_hub(false)
	check(not hub_renderer.hub_fx, "effects stay off on the Hickston side")

	print("\nCOPPER BARON PIPE OUTLETS (was a type error: no steam, no cooldown)")
	main.start("quarry")
	var quarry: Game = main.game
	var baron: Enemy = null
	for enemy: Enemy in quarry.enemies:
		if enemy.kind == "baron":
			baron = enemy
	check(baron != null, "quarry has the Copper Baron")
	if baron != null:
		baron.attacks = 1
		baron.cooldown = 0.0
		var before := quarry.hazards.size()
		baron.special_attack(quarry, 0.0, 6.0, 1.2, null)
		check(quarry.hazards.size() == before + 2, "two steam outlets open")
		check(is_equal_approx(baron.cooldown, 1.58), "attack sets its 1.58 s cooldown")

	print("\nGATOR BAYOU: DEEP WATER, THE KING'S AIRBOAT RUN")
	main.start("bayou")
	var bayou: Game = main.game
	var king: Enemy = null
	for enemy: Enemy in bayou.enemies:
		if enemy.kind == "swamp_king":
			king = enemy
	check(king != null, "the bayou has the Swamp King")
	check(bayou.world.deep_at(20.5, 39.5), "the west channel is deep water")
	var wader := Enemy.new("billy", 20.5, 43.5)
	bayou.move_actor(wader, 0.0, -1.0, wader.radius)
	check(wader.y > 43.0, "a walker cannot wade into the deep channel")
	var gator := Enemy.new("gator", 20.5, 43.5)
	bayou.move_actor(gator, 0.0, -1.0, gator.radius)
	check(gator.y < 43.0, "a gator swims into it")
	if king != null:
		king.dormant = false
		king.alerted = true
		king.attacks = 0
		bayou.player.x = king.x + 6.0
		bayou.player.y = king.y
		var toward := atan2(bayou.player.y - king.y, bayou.player.x - king.x)
		check(BayouBrains.runs_on(king, 1, bayou.world, toward), "the king's first attack is a run")
		king.attack(bayou, toward, 6.0, 1.2, null)
		check(king.has_meta("run"), "the attack starts an airboat run")
		king.attack(bayou, toward, 6.0, 1.2, null)
		check(not king.has_meta("pair"), "a calm king makes no second run")

	print("\nSTATION LIGHTS AFTER A LOAD (were lost on quickload and slot load)")
	# A campaign run in chapter two carries one finished chapter in its history;
	# the loader rejects a save without it.
	main.start("fair", null, [["hickston", 0, 0, 0, 0, 0]], false, null)
	var fair: Game = main.game
	var station: LevelData.Station = null
	for candidate: LevelData.Station in fair.world.stations:
		if candidate.requires.is_empty() and not candidate.sectors.is_empty():
			station = candidate
			break
	check(station != null, "fair has a station that lights a sector")
	if station != null:
		var sector := int(station.sectors[0])
		var cell := -1
		for i in fair.world.area.size():
			if int(fair.world.area[i]) == sector:
				cell = i
				break
		var dark: float = fair.world.light[cell]
		fair.activate_station(station)
		var lit: float = fair.world.light[cell]
		check(is_equal_approx(lit - dark, .26), "finishing the station adds .26")
		var path := "user://probe-lights.json"
		check(SessionStore.save(fair, path), "save written")
		var loaded: Game = SessionStore.read(path, Callable(main, "make_game"), false)
		check(loaded != null, "save reloads (%s)" % SessionStore.last_error)
		if loaded != null:
			check(
				is_equal_approx(loaded.world.light[cell], lit), "sector is still lit after the load"
			)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	print("\nCAMPAIGN SAVE SLOTS (were unreadable once written)")
	main.start("hickston")
	main.game.kills = 7
	main.show_slots("save")
	check(main.slot_replay == "", "campaign slots use the empty replay tag")
	var slot_path := String(main.slots[3][0])
	if FileAccess.file_exists(slot_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path))
		main.refresh_slots()
	main.slot_index = 3
	main.slot_name = "AUDIT PROBE"
	main.slot_commit()
	main.refresh_slots()
	var entry: Array = main.slots[3]
	check(entry[1] is String and String(entry[1]) != "", "written slot has a fingerprint")
	check(entry[2] != null, "written slot lists its label")
	if entry[2] != null:
		check(String(entry[2][0]) == "AUDIT PROBE", "label reads back")
	main.game.kills = 0
	main.slot_mode = "load"
	main.slot_stage = "choose"
	main.key_slots(KEY_ENTER)
	check(main.state == "play" and main.game != null, "slot loads back into play")
	check(main.game.kills == 7, "loaded run is the saved one")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path))

	print("\nINPUT")
	main.start("hickston")
	var idle := {
		"forward": 0.0,
		"strafe": 0.0,
		"turn": 0.0,
		"look": 0.0,
		"run": false,
		"fire": false,
		"alt": false,
		"jump": false,
		"crouch": true
	}
	main.options["crouch"] = 0
	var held: Game.Controls = main._controls(1.0 / 60.0, idle, main.touch.state())
	check(held.crouch, "pad crouch reaches the game in HOLD mode")
	var finger := InputEventScreenTouch.new()
	finger.index = 0
	finger.pressed = true
	finger.position = main.touch.buttons[0][1]
	main._input(finger)
	check(main.touch.active and main.touch.fire, "a finger on FIRE holds fire")
	finger.pressed = false
	main._input(finger)
	check(not main.touch.fire, "lifting the finger releases fire")

	print("\nFRONT END (title and settings share one layout for drawing and pointing)")
	main.return_to_title(true)
	var rows: PackedStringArray = main.entries()
	var items := Menu.title_items(rows)
	check(items.size() == rows.size(), "every title entry has a place")
	var clear := true
	for i in items.size():
		var rect: Rect2i = items[i]["rect"]
		if Menu.title_hit(rows, rect.position.x + 2, rect.position.y + 2) != i:
			clear = false
		for j in i:
			if rect.intersects(items[j]["rect"]):
				clear = false
		if not Menu.BOARD.encloses(rect) or rect.size.y < 11:
			clear = false
	check(clear, "title rows do not overlap, sit on the board and are 11+ px tall")
	# CONTINUE CAMPAIGN once a campaign exists, NEW GAME on a fresh profile.
	check(bool(items[0]["primary"]), "the first entry takes the big plate")
	main.start("hickston")
	main.return_to_title()
	check(String(main.entries()[0]) == "RESUME", "RESUME leads while a game is paused")
	check(bool(Menu.title_items(main.entries())[0]["primary"]), "and takes the big plate")
	check(main.sound.score == "title", "the menu theme plays on the pause menu")
	main.key(KEY_ESCAPE)
	check(
		main.state == "play" and main.sound.score == main.game.level.score,
		"resume returns to the chapter score"
	)
	main.return_to_title()
	var pages := SessionStore.setup_pages()
	var seen := {}
	var bounded := true
	main.state = "setup"
	for page_index in pages.size():
		main.option_page = page_index
		main.option_slot = 0
		main.option_scroll = 0
		var settings: Array = pages[page_index][1]
		for slot in settings.size():
			main.setup_select(slot)
			var row := Menu.row_rect(page_index, main.option_slot, main.option_scroll)
			if row.size.y == 0 or row.end.y > Menu.FOOTER_Y - 2 or not Menu.LIST.encloses(row):
				bounded = false
			var hit := Menu.setup_hit(
				row.position.x + 4, row.position.y + 4, page_index, main.option_scroll
			)
			if String(hit["kind"]) != "row" or int(hit["index"]) != slot:
				bounded = false
			seen[(settings[slot] as SessionStore.Setting).key] = true
	check(
		bounded, "every setting can be selected, stays inside the list and clear of the help text"
	)
	check(
		seen.size() == 56 + KeyBindings.ACTIONS.size(),
		"all 56 settings and every control's key are on a page"
	)
	var stored := SessionStore.settings("")
	var kept := true
	for key in seen:
		if not stored.has(key):
			kept = false
	check(kept, "every setting still has its stored key")
	_check_setup_fits(pages)
	_check_setup_moves(main)
	main.option_page = _place_of("effects").x
	main.option_slot = _place_of("effects").y
	var was := int(main.options["effects"])
	main.adjust_setting(-1)
	check(int(main.options["effects"]) == was - 10, "a volume step changes the option")
	check(main.sound._preview.player.playing, "and plays a preview")
	main.adjust_setting(1)
	check(main.sound._preview.cue == "shotgun", "a second change restarts the one preview voice")
	main.option_page = _place_of("aspect").x
	main.option_slot = _place_of("aspect").y
	var aspect := int(main.options["aspect"])
	main.smoke = false
	main.adjust_setting(1)
	check(not main.display_trial.is_empty(), "a scaling change goes on trial")
	main.key(KEY_ESCAPE)
	check(
		int(main.options["aspect"]) == aspect and main.state == "setup",
		"Esc undoes it and stays on the page"
	)
	main.adjust_setting(1)
	main.key(KEY_ENTER)
	check(int(main.options["aspect"]) != aspect and main.display_trial.is_empty(), "Enter keeps it")
	main.options["aspect"] = aspect
	main.persist_options()
	main.reset_page()
	check(main.reset_armed > 0.0, "reset asks before it acts")
	main.selection = 5
	main.key(KEY_ESCAPE)
	check(
		main.state == "title" and main.selection == 5,
		"back returns to the title with the cursor where it was"
	)

	# An enemy kind defined only by data: it takes its brain's behaviour and
	# values, and keeps what it sets itself.
	var defs := ConfigFile.new()
	defs.load(Tuning.ENEMIES)
	defs.set_value("test_hick", "brain", "billy")
	defs.set_value("test_hick", "hp", 99)
	var made := Enemy._definition(defs, "test_hick", 0)
	check(
		(
			made.get("brain") == "billy"
			and made.get("hp") == 99
			and made.get("speed") == defs.get_value("billy", "speed")
			and made.get("voice") == "hick"
		),
		"a data-only enemy kind takes its brain's values under its own"
	)
	check(
		Array(Tuning.sections(Tuning.WEAPONS)) == Weapons.NAMES,
		"weapons.cfg has a section for each gun, in Weapons.NAMES order"
	)
	check(
		Weapons.LABELS[Weapons.SHOTGUN] == "SAWED-OFF" and Weapons.CYCLE_GUNS.has(Weapons.COW),
		"gun definitions load from weapons.cfg"
	)

	# Rebinding a control on the KEYS page: Enter, then the new key.
	var kept_options: Dictionary = main.options.duplicate()
	var key_pages := SessionStore.setup_pages()
	main.state = "setup"
	for index in key_pages.size():
		if String(key_pages[index][0]) == "KEYS":
			main.option_page = index
	main.option_scroll = 0
	main.setup_select(0)
	main.key(KEY_ENTER)
	var armed: bool = main.binding_action == "forward"
	main.key(KEY_I)
	check(
		armed and int(main.options["key_forward"]) == KEY_I,
		"a KEYS page row waits for a key and takes it"
	)
	KeyBindings.bind(main.options, "forward", KEY_E)
	main.apply_options()
	check(
		int(main.options["key_use"]) == KEY_I and KeyBindings.translate(KEY_I) == KEY_E,
		"a key given to another control swaps with it, and play hears the default key"
	)
	var press := InputEventKey.new()
	press.keycode = KEY_E
	press.pressed = true
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	var moving := KeyBindings.held("forward")
	press.pressed = false
	Input.parse_input_event(press)
	Input.flush_buffered_events()
	check(moving and not KeyBindings.held("forward"), "a rebound key moves through the InputMap")
	main.options = kept_options
	main.apply_options()
	main.persist_options()
	main.state = "title"

	print("GAME FEEL, PATHS AND THE PIN")
	var felt: Game = main.make_game("fair")
	felt.configure({})
	var foe: Enemy = null
	for e: Enemy in felt.enemies:
		if e.hostile and not Enemy.BOSS_TITLES.has(e.kind):
			foe = e
			break
	foe.hurt(9999.0, felt)
	var frozen_at := felt.clock
	felt.tick(1.0 / 60.0, Game.Controls.new())
	check(
		felt.hit_mark_until > felt.clock and felt.hit_mark_kill and felt.clock == frozen_at,
		"a kill marks the crosshair red and holds the world a moment"
	)
	for i in 10:
		felt.tick(1.0 / 60.0, Game.Controls.new())
	check(felt.clock > frozen_at, "the world moves again after the hold")
	# An enemy on the far side of a wall from the player walks round it.
	var field := FlowField.new(felt.level)
	var px := felt.player.x
	var py := felt.player.y
	field.update(px, py, 0.0)
	var around := false
	for e: Enemy in felt.enemies:
		var steps := field.distance(e.x, e.y)
		if steps < FlowField.FAR and steps > 4 and not felt.world.visible(px, py, e.x, e.y):
			var lead := field.heading(e.x, e.y)
			var straight := atan2(py - e.y, px - e.x)
			if not is_nan(lead) and absf(Enemy.angle_delta(lead, straight)) > .3:
				around = true
				break
	check(around, "an enemy out of sight is led round the walls, not straight at the player")
	_tactics(main)
	var town: Game = main.make_game("hickston")
	town.configure({})
	var pin = town.objective_target()
	var brass := Vector2.ZERO
	for found: Array in town.pickups:
		if String(found[0]) == "key_brass":
			brass = Vector2(float(found[1]), float(found[2]))
	check(
		pin is Vector2 and pin == brass, "Hickston's pin starts on the brass key, as its words do"
	)
	var way: Array = town.objective_route(brass)
	check(int(way[1]) > 0 and int(way[1]) < FlowField.FAR, "the pin counts the walk to the key")
	check(
		int(way[1]) >= int(Vector2(town.player.x, town.player.y).distance_to(brass)),
		"the walk is never shorter than the straight line"
	)

	# TOUCH AUTO FIRE: a foe square in the sights fires a straight gun.
	var sights: Game = main.make_game("fair")
	sights.configure({})
	var aimed_at: Enemy = null
	for e: Enemy in sights.enemies:
		if e.hostile and not Enemy.BOSS_TITLES.has(e.kind):
			aimed_at = e
			break
	var sp := sights.player
	sp.x = aimed_at.x - 3.0
	sp.y = aimed_at.y
	while (
		sights.world.blocked(sp.x, sp.y, .2)
		or not sights.world.visible(sp.x, sp.y, aimed_at.x, aimed_at.y)
	):
		sp.x += .25
	sp.angle = atan2(aimed_at.y - sp.y, aimed_at.x - sp.x)
	sp.eye = .95 + sights.world.elevation(sp.x, sp.y)
	sp.pitch = 0.0
	sights.armory.active = Weapons.REVOLVER
	var on_target := sights.sights_on_enemy()
	sights.sights_next = 0.0
	sp.angle += 1.2
	check(
		on_target and not sights.sights_on_enemy(),
		"touch auto fire sees a foe in the sights, and only then"
	)
	var kept_game: Game = main.game
	main.game = sights
	main.state = "play"
	main.touch.active = true
	main.block_fire = false
	sp.angle -= 1.2
	sights.sights_next = 0.0
	var fired: bool = main._controls(1.0 / 60.0, main.read_pad(1.0 / 60.0), main.touch.state()).fire
	main.touch.active = false
	main.game = kept_game
	main.state = "title"
	check(fired, "on touch, a foe in the sights pulls the trigger")

	# Level triggers: Hickston's dispatch safe rings when the brass key is taken.
	var alarm: Game = main.make_game("hickston")
	alarm.configure({})
	alarm.spawn_grace = 0.0
	alarm.player.x = 34.5
	alarm.player.y = 34.5
	var awake_before := 0
	for e: Enemy in alarm.enemies:
		if e.alerted:
			awake_before += 1
	alarm.keys["key_brass"] = true
	alarm.tick(1.0 / 60.0, Game.Controls.new())
	var awake_after := 0
	for e: Enemy in alarm.enemies:
		if e.alerted:
			awake_after += 1
	check(
		(
			alarm.triggers_fired.has("dispatch-alarm")
			and alarm.notice.begins_with("THE DISPATCH SAFE")
		),
		"a trigger fires on its condition and shows its message"
	)
	check(
		awake_after > awake_before and not alarm.trigger_lights.is_empty(),
		"its alert wakes the enemies near and its light goes up"
	)
	var alarm_path := OS.get_user_data_dir().path_join("trigger-check.json")
	SessionStore.save(alarm, alarm_path)
	var alarm_back: Game = SessionStore.read(alarm_path, Callable(main, "make_game"), false)
	check(
		alarm_back != null and alarm_back.triggers_fired.has("dispatch-alarm"),
		"a fired trigger stays fired after a save and a load"
	)

	# The developer console, driven as a script would.
	print("DEVELOPER CONSOLE")
	var console := DevConsole.new(main)
	var kept_game2: Game = main.game
	main.game = main.make_game("hickston")
	main.game.configure({})
	var before := int(main.game.enemies.size())
	console.run("spawn billy 3")
	check(main.game.enemies.size() > before, "spawn puts awake enemies in front of the player")
	console.run("give all")
	var all_guns := true
	for owned: bool in main.game.armory.owned:
		all_guns = all_guns and owned
	check(all_guns, "give all hands over every gun")
	console.run("god")
	check(main.game.cheats.god, "god turns on taking no damage")
	console.run("trigger dispatch-alarm")
	check(main.game.triggers_fired.has("dispatch-alarm"), "trigger runs a level trigger by its id")
	console.run("tp 20 30")
	check(
		absf(main.game.player.x - 20.5) < .01 and absf(main.game.player.y - 30.5) < .01,
		"tp moves the player to the middle of a cell"
	)
	console.run("time 2")
	var scaled: float = main.time_scale
	console.run("time 1")
	check(scaled == 2.0 and main.time_scale == 1.0, "time sets how fast play runs")
	check(console.run("frobnicate").begins_with("unknown"), "an unknown command says so")
	main.game = kept_game2

	# Events and features: the chapter's stats come from events alone and
	# survive a save, and a save without them starts them afresh.
	print("EVENTS, FEATURES AND DATA GUNS")
	var eventful: Game = main.make_game("hickston")
	eventful.configure({})
	var heard := []
	eventful.enemy_killed.connect(func(e: Enemy) -> void: heard.append(e.kind))
	var target: Enemy = null
	for e: Enemy in eventful.enemies:
		if e.hostile and not Enemy.BOSS_TITLES.has(e.kind):
			target = e
			break
	eventful.shot_fired.emit(Weapons.REVOLVER)
	target.hurt(9999.0, eventful)
	var stats = eventful.features["stats"]
	check(heard == [target.kind], "a kill is announced to whoever listens")
	check(stats.shots == 1 and stats.landed == 1, "the stats feature counts a shot and its hit")
	var stats_path := OS.get_user_data_dir().path_join("features-check.json")
	SessionStore.save(eventful, stats_path)
	var stats_back: Game = SessionStore.read(stats_path, Callable(main, "make_game"), false)
	check(
		stats_back != null and stats_back.features["stats"].shots == 1,
		(
			"a feature's state comes back from a save"
			+ ("" if stats_back != null else " (%s)" % SessionStore.last_error)
		)
	)
	if stats_back != null:
		stats_back.features["stats"].restore({})
		check(
			stats_back.features["stats"].shots == 0, "a save without it starts the feature afresh"
		)
	# A gun from weapons.cfg alone: a copy of the revolver's section at the end.
	var guns := Tuning.file(Tuning.WEAPONS)
	for key in guns.get_section_keys("revolver"):
		guns.set_value("test_gun", key, guns.get_value("revolver", key))
	Weapons.load_tuning()
	var gunner: Game = main.make_game("fair")
	gunner.configure({})
	var slot: int = Weapons.COUNT - 1
	gunner.armory.pickup(slot, gunner)
	gunner.armory.select(slot, gunner)
	gunner.armory.switch = 0.0
	gunner.armory.fire(gunner)
	check(
		(
			Weapons.NAMES[slot] == "test_gun"
			and gunner.armory.loaded[slot] == Weapons.CAPACITY[slot] - 1
		),
		"a section added to weapons.cfg is a gun that fires"
	)
	var older: Game = SessionStore.read(
		"res://tools/saves/v6_hickston_fight.json", Callable(main, "make_game"), false
	)
	check(
		older != null and older.armory.owned.size() == Weapons.COUNT,
		"a save from before the gun existed still loads, the new gun empty"
	)
	guns.erase_section("test_gun")
	Weapons.load_tuning()

	# The polish: what fights leave, kill calls, the tally's ribbon, the weather.
	print("POLISH")
	var fx_game: Game = main.make_game("hickston")
	fx_game.configure({})
	fx_game.exploded.emit(fx_game.player.x + 2.0, fx_game.player.y, .3, false)
	var debris = fx_game.features["debris"]
	check(
		(
			debris.scorches.size() == 1
			and debris.bits.size() > 3
			and not debris.ground_marks().is_empty()
		),
		"a blast leaves a scorch, embers and smoke"
	)
	fx_game.gun_reloading.emit(Weapons.REVOLVER)
	check(debris.sprites().size() > 6, "a revolver reload dumps its brass")
	var sweep: Array = []
	for e: Enemy in fx_game.enemies:
		if e.hostile and not Enemy.BOSS_TITLES.has(e.kind) and sweep.size() < 3:
			sweep.append(e)
	for e: Enemy in sweep:
		e.hurt(9999.0, fx_game)
	check(fx_game.callout == "HAT TRICK!", "three quick kills are called a hat trick")
	fx_game.total_kills = 3
	fx_game.kills = 3
	check(fx_game.features["tally"].ribbon() != "", "the tally has a ribbon to stamp")
	var stormy: Game = main.make_game("sawmill")
	stormy.configure({})
	stormy.replay = true
	var weather = stormy.features["weather"]
	weather.next_flash = 0.0
	stormy.ticked.emit(1.0 / 60.0)
	check(stormy.lightning > .5, "a stormy level's lightning lights the yard")
	_quest_props(main)

	# The firing range: its title entry, its way out, the campaign untouched.
	preload("res://tools/range_check.gd").run(main, check)

	# The Mothership, the last chapter, and the true finale after it.
	_mothership(main)

	print("")
	if failures.is_empty():
		print("PARITY FIXES OK")
	else:
		print("%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


## The county's hands fight smarter: a stray shot starts a brawl, the hurt
## duck out of sight, the badly hurt run for a friend.
func _tactics(main) -> void:
	print("TACTICS")
	var town: Game = main.make_game("hickston")
	town.configure({})
	town.spawn_grace = 0.0
	var p := town.player
	# A clear stretch of road east of the start: the player, then two hands.
	var row := Vector2(p.x, p.y)
	var hands: Array[Enemy] = []
	for e: Enemy in town.enemies:
		if e.tactical() and e.brain == "billy":
			hands.append(e)
		if hands.size() == 4:
			break
	var shooter := hands[0]
	var friend := hands[1]
	shooter.x = row.x + 5.0
	shooter.y = row.y
	friend.x = row.x + 2.6
	friend.y = row.y
	for e: Enemy in [shooter, friend]:
		e.alerted = true
	var start_hp := friend.hp
	var eye: float = town.world.elevation(shooter.x, shooter.y) + .9
	for i in 30:
		if friend.hp < start_hp:
			break
		shooter.attack(town, PI, 5.0, eye)
	check(
		friend.hp < start_hp and friend.grudge == shooter,
		"a friend in the line of fire takes the shot and turns on the shooter"
	)
	var shooter_hp := shooter.hp
	for i in 300:
		town.tick(1.0 / 60.0, Game.Controls.new())
		if shooter.hp < shooter_hp:
			break
	check(shooter.hp < shooter_hp, "the brawl lands punches")
	# A hurt hand ducks out of the player's sight when there is cover near.
	var ducked := false
	for e: Enemy in town.enemies:
		if not e.tactical() or not e.alive or e == shooter or e == friend:
			continue
		var spot = e.find_cover(town)
		if spot != null:
			var head: float = town.world.elevation(spot.x, spot.y) + .9
			ducked = not town.world.visible(p.x, p.y, spot.x, spot.y, p.eye, head)
			break
	check(ducked, "a hand finds a spot out of the player's sight")
	# The badly hurt run for a friend who has not seen the fight, and bring them.
	var runner := hands[2]
	var helper := hands[3]
	helper.alerted = false
	helper.dormant = false
	runner.x = row.x + 3.0
	runner.y = row.y
	helper.x = row.x + 7.0
	helper.y = row.y
	runner.alerted = true
	runner.target = [p.x, p.y]
	check(runner.fetch_help(town) and runner.fetching != null, "a badly hurt hand runs for help")
	for i in 400:
		town.tick(1.0 / 60.0, Game.Controls.new())
		if runner.fetching == null:
			break
	check(runner.fetching == null and helper.alerted, "the friend comes back with them")
	# Each gun moves what it hits its own way.
	var target := hands[1] if hands[1].alive else hands[0]
	for e: Enemy in town.enemies:
		if e.tactical() and e.alive and e != runner and e != helper:
			target = e
			break
	target.hp = 999.0
	target.x = p.x + 2.0
	target.y = p.y
	var before := Vector2(target.x, target.y)
	for i in 8:
		target.hurt(6.0, town, false, false, null, "shotgun")
	check(
		Vector2(target.x, target.y).distance_to(before) > .3 and target.stun > .2,
		"a full load of the sawed-off throws a body back"
	)
	for i in 4:
		target.hurt(2.0, town, false, false, null, "teat_gun")
	check(target.soak > .4, "the teat gun soaks them")
	target.stun = 0.0
	target.hurt(10.0, town, false, false, null, "bowling")
	check(target.stun > .8, "a bowling ball bowls them over")
	# Bosses: fightin' mad at half health, a harder pattern, a death that lands.
	var mill: Game = main.make_game("sawmill")
	mill.configure({})
	var boss_man: Enemy = null
	for e: Enemy in mill.enemies:
		if e.brain == "foreman":
			boss_man = e
	boss_man.dormant = false  # the finale wakes him in play
	var calm_lanes := boss_man.saw_lanes(0.0, 1).size()
	boss_man.hurt(boss_man.max_hp * .55, mill)
	check(boss_man.enraged and boss_man.stun > .5, "a boss goes fightin' mad at half health")
	check(boss_man.saw_lanes(0.0, 1).size() > calm_lanes, "the mad foreman cuts more lanes")
	boss_man.hurt(99999.0, mill)
	check(not boss_man.alive and mill.hitstop > .3, "a boss going down holds the world a beat")
	# HOG WILD: a bigger posse, sharper hands, less from an ammo pickup.
	var wild: Game = main.make_game("hickston")
	wild.configure({"difficulty": 3})
	var own := wild.enemies.size()
	wild.tick(1.0 / 60.0, Game.Controls.new())
	check(
		wild.enemies.size() > own and wild.sharpness > 1.2,
		"HOG WILD brings a bigger, sharper posse"
	)
	var shells := wild.armory.reserve[Weapons.REVOLVER]
	wild.collect("bullets")
	var got := wild.armory.reserve[Weapons.REVOLVER] - shells
	var tame: Game = main.make_game("hickston")
	tame.configure({"difficulty": 1})
	var tame_shells := tame.armory.reserve[Weapons.REVOLVER]
	tame.collect("bullets")
	check(
		got < tame.armory.reserve[Weapons.REVOLVER] - tame_shells,
		"HOG WILD gives less from an ammo pickup"
	)
	var wild_path := OS.get_cache_dir().path_join("clmr-posse-check.json")
	SessionStore.save(wild, wild_path)
	var wild_back: Game = SessionStore.read(wild_path, Callable(main, "make_game"), false)
	check(
		wild_back != null and wild_back.enemies.size() == wild.enemies.size(),
		"the posse is still there after a save and a load"
	)


## Where a setting lives: (page, slot).
func _place_of(key: String) -> Vector2i:
	var pages := SessionStore.setup_pages()
	for p in pages.size():
		var items: Array = pages[p][1]
		for s in items.size():
			if (items[s] as SessionStore.Setting).key == key:
				return Vector2i(p, s)
	return Vector2i(-1, -1)


## Nothing on the settings pages is cut off: every name clears the value
## column, every value fits it, every help text fits its two lines, and the
## stored settings stay well inside what the loader reads.
func _check_setup_fits(pages: Array) -> void:
	var names := true
	var values := true
	var hints := true
	var long := ""
	for page: Array in pages:
		for raw in page[1]:
			var item: SessionStore.Setting = raw
			if Menu.LABEL_X + PixelType.text_width(item.label) > Menu.VALUE_X - 4:
				names = false
				long = item.label
			if PixelType.wrap(item.hint, Menu.HINT.size.x - 14).size() > 2:
				hints = false
				long = item.hint
			if item is SessionStore.KeySetting:
				continue
			var shown: Array = (
				item.choices if not item.choices.is_empty() else [item.format_value(item.high)]
			)
			for value in shown:
				var room := Menu.VALUE_END - 4 - (Menu.VALUE_X + 5)
				if Menu.is_bar(item):
					room = Menu.VALUE_END - (Menu.BAR_X + Menu.BAR_W + 8)
				if PixelType.text_width(String(value)) > room:
					values = false
					long = String(value)
	check(names, "every setting's name clears the value column %s" % long)
	check(values, "every value fits its column %s" % long)
	check(hints, "every help text fits its two lines %s" % long)
	var blurbs := true
	for id in Menu.BLURBS:
		if PixelType.text_width(String(Menu.BLURBS[id]), "mini") > Menu.BOARD.size.x - 12:
			blurbs = false
	check(blurbs, "every title entry's line fits under the board")
	var widest := 0
	for p in pages.size():
		widest = maxi(widest, Menu.tab_rect(p, pages.size()).end.x)
		var name := String(pages[p][0])
		if Menu.tab_rect(p, pages.size()).size.x < PixelType.text_width(name) + 4:
			widest = 999
	check(widest <= Menu.PANEL.end.x, "every tab's name fits and the row of tabs fits the frame")
	# Every setting at its longest value (a key at the largest code there is).
	var everything := {}
	for raw in SessionStore.options_list():
		everything[(raw as SessionStore.Setting).key] = (raw as SessionStore.Setting).high
	var size := JSON.stringify(everything, "", false).length()
	check(size < 3000, "the stored settings stay well under the 4 KB the loader reads (%d)" % size)
	var defaults := SessionStore.defaults()
	check(
		(
			int(defaults["master"]) == 100
			and int(defaults["menu_music"]) == 1
			and int(defaults["bg_mute"]) == 0
			and int(defaults["crosshair"]) == 1
			and int(defaults["crosshair_color"]) == 0
			and int(defaults["show_fps"]) == 0
			and int(defaults["pad_look"]) == 100
			and int(defaults["pad_deadzone"]) == 1
			and int(defaults["pad_invert"]) == 0
		),
		"the new settings' defaults leave the game as it played"
	)


## Moving round a long settings page with the wheel, held keys, a finger and
## the scroll bar keeps the picked row in the window.
func _check_setup_moves(main: Control) -> void:
	var keys_page := _place_of("key_forward").x
	main.state = "setup"
	main.option_page = keys_page
	main.option_slot = 0
	main.option_scroll = 0
	main.setup_select(0)
	var last: int = Menu.max_scroll(keys_page)
	check(last > 0, "the KEYS page is long enough to scroll")
	for i in 3:
		main.setup_scroll_to(main.option_scroll + 1)
	var shown: Rect2i = Menu.row_rect(keys_page, main.option_slot, main.option_scroll)
	check(
		main.option_scroll > 0 and shown.size.y > 0,
		"the wheel scrolls the list and the pick follows into the window"
	)
	main.setup_scroll_to(999)
	check(main.option_scroll == last, "the list stops at its end")
	var count: int = main.option_items().size()
	main.setup_select(count - 1)
	main.key_echo = true
	main.key(KEY_DOWN)
	main.key_echo = false
	check(main.option_slot == count - 1, "a held key stops at the bottom instead of wrapping")
	main.key(KEY_DOWN)
	check(main.option_slot == 0 and main.option_scroll == 0, "a fresh press wraps to the top")
	main.key(KEY_END)
	check(
		(
			main.option_slot == count - 1
			and Menu.row_rect(keys_page, count - 1, main.option_scroll).size.y > 0
		),
		"End jumps to the last row and shows it"
	)
	main.key(KEY_HOME)
	check(main.option_slot == 0 and main.option_scroll == 0, "Home jumps back to the first")
	# The scroll groove: a point near its bottom scrolls near the end.
	var track: Rect2i = Menu.track_rect()
	var hit: Dictionary = Menu.setup_hit(
		track.position.x + 1, track.end.y - 1, keys_page, main.option_scroll
	)
	check(String(hit["kind"]) == "track", "the scroll groove can be clicked")
	main.setup_scroll_to(Menu.scroll_at(keys_page, float(hit["share"])))
	check(main.option_scroll == last, "the bottom of the groove is the end of the page")
	main.setup_scroll_to(0)
	# A level setting's bar: a click at its right end sets the top value.
	var volume := _place_of("effects")
	main.option_page = volume.x
	main.option_scroll = 0
	main.setup_select(volume.y)
	var item: SessionStore.Setting = main.option_items()[volume.y]
	var row: Rect2i = Menu.row_rect(volume.x, volume.y, main.option_scroll)
	var shape: Array = Menu.bar_shape(item)
	var bar_hit: Dictionary = Menu.setup_hit(int(shape[0]) + 2, row.position.y + 5, volume.x, 0)
	check(bool(bar_hit["bar"]), "a level setting's bar can be clicked")
	check(
		(
			Menu.bar_value(item, int(shape[0])) == item.low
			and Menu.bar_value(item, int(shape[0]) + Menu.BAR_W) == item.high
		),
		"the bar runs from the lowest value to the highest"
	)
	# A toggle held sideways does not flicker.
	var lamp := _place_of("voice_captions")
	main.option_page = lamp.x
	main.setup_select(lamp.y)
	var before := int(main.options["voice_captions"])
	main.key_echo = true
	main.key(KEY_RIGHT)
	main.key_echo = false
	check(int(main.options["voice_captions"]) == before, "a held arrow does not flicker a switch")
	# A finger: dragged up the list it scrolls and picks nothing; a tap on a
	# row's right side steps that setting.
	var view: Rect2 = main.viewport_rect()
	var scale := view.size / Vector2(320, 200)
	main.option_page = keys_page
	main.option_slot = 0
	main.option_scroll = 0
	var finger := InputEventScreenTouch.new()
	finger.index = 0
	finger.pressed = true
	finger.position = view.position + Vector2(100, 120) * scale
	main._input(finger)
	var swipe := InputEventScreenDrag.new()
	swipe.index = 0
	swipe.position = view.position + Vector2(100, 80) * scale
	swipe.relative = Vector2(0, -40) * scale
	main._input(swipe)
	var lift := InputEventScreenTouch.new()
	lift.index = 0
	lift.position = swipe.position
	main._input(lift)
	check(
		main.option_scroll >= 2 and main.binding_action == "",
		"a finger dragged up the list scrolls it and picks nothing"
	)
	var width := _place_of("stereo")
	main.option_page = width.x
	main.option_scroll = 0
	main.setup_select(width.y)
	main.setup_select(width.y - 1)
	var width_row: Rect2i = Menu.row_rect(width.x, width.y, main.option_scroll)
	var stereo := int(main.options["stereo"])
	for down: bool in [true, false]:
		var tap := InputEventScreenTouch.new()
		tap.index = 0
		tap.pressed = down
		tap.position = view.position + Vector2(286, width_row.position.y + 5) * scale
		main._input(tap)
	check(
		main.option_slot == width.y and int(main.options["stereo"]) == (stereo + 1) % 4,
		"a tap on a row's right side picks it and steps it"
	)
	main.options["stereo"] = stereo
	main.apply_options()
	main.persist_options()
	main.touch.active = false
	main.hover(view.position + Vector2(Menu.BACK.position.x + 4, Menu.BACK.position.y + 4) * scale)
	check(main.hover_part == "back", "the pointer lights the BACK plate it is over")
	main.hover_part = ""
	var plain: Game = main.make_game("hickston")
	plain.configure(SessionStore.defaults())
	check(
		plain.crosshair_tint == Color8(188, 168, 132) and main._deadzone(.17) == 0.0,
		"by default the aiming mark keeps its bone colour and the sticks their deadzone"
	)
	main.option_page = 0
	main.option_slot = 0
	main.option_scroll = 0


## Quest props and items: forgiving to use, never through a wall (game_world.gd
## use_target, seen_at, reaches_pickup; tools/quest_reach.gd checks them all).
func _quest_props(main: Control) -> void:
	print("QUEST PROPS")
	var mill: Game = main.make_game("sawmill")
	mill.configure({})
	var west: LevelData.Station = null
	for station: LevelData.Station in mill.world.stations:
		if station.id == "west":
			west = station
	# The west feed's box stands 1.6 south of its point: a player at the box,
	# facing it, used to have the point behind them.
	_stand(mill, 9.5, 23.3, PI / 2)
	var found = mill.use_target()
	check(
		found != null and found[0] == west,
		"the box a station lights up answers USE from in front of it (was: its point only)"
	)
	var town: Game = main.make_game("hickston")
	town.configure({})
	_stand(town, 34.0, 32.4, PI / 2)
	found = town.use_target()
	check(
		found != null and found[0] is LevelData.Note,
		"a note lying on a table is read from beside it (the table hid it)"
	)
	_stand(town, 80.5, 23.5, -PI / 2)
	found = town.use_target()
	check(
		found == null or not (found[0] is LevelData.Station),
		"the stock gate's bolt does not answer through the fence from the lane"
	)
	# The thing under the crosshair wins over a nearer one off to the side.
	var front: LevelData.Door = null
	for door: LevelData.Door in town.world.doors:
		if door.id == "front":
			front = door
	var slip := LevelData.Note.new()
	slip.x = 52.75
	slip.y = 43.35
	slip.label = "TEST SLIP"
	town.level.notes.append(slip)
	_stand(town, 52.25, 42.5, 0.0)
	found = town.use_target()
	check(
		found != null and found[0] == front,
		"facing the door opens the door, not the slip beside it"
	)
	_stand(town, 52.25, 42.5, atan2(43.35 - 42.5, 52.75 - 52.25))
	found = town.use_target()
	check(found != null and found[0] == slip, "facing the slip reads it, with the door still near")
	town.level.notes.erase(slip)
	_stand(town, 34.0, 32.6, PI / 2)
	check(
		town.reaches_pickup(["key_brass", 34.0, 33.2]),
		"a key lying over the edge of a table is taken by walking up to it"
	)
	check(not town.reaches_pickup(["bullets", 34.0, 33.2]), "ammo keeps its own short reach")
	var kept_device: String = main.input_device
	main.input_device = "pad"
	var pad: String = main.use_button()
	main.input_device = "touch"
	var finger: String = main.use_button()
	main.input_device = kept_device
	check(
		pad == "Y" and finger == "USE", "the use prompt names the controller's and the touch button"
	)
	var hub: Game = main.make_game("hub")
	hub.in_hub = true
	hub.world.locked_gates = [hub.world.hub_gates[0]]
	var walls: PackedFloat32Array = hub.world.active_walls(false)
	var barred := false
	var closed := hub.world.tile_id("route_closed")
	for i in walls.size() / LevelData.WALL_STRIDE:
		barred = barred or int(walls[i * LevelData.WALL_STRIDE + 4]) == closed
	check(barred, "a locked Crossroads gate shows its barricade (the rebuilt hub never did)")
	var gate: LevelData.Gate = hub.world.hub_gates[0]
	_stand(hub, gate.x - 1.1, gate.y + .5, -PI / 2 + 1.2)
	check(
		hub.portal_target() == gate, "a gate answers with the crosshair on its opening, at a slant"
	)
	var facing_hub := false
	var face_tile := hub.world.tile_id("route_" + gate.destination)
	for i in hub.world.wall_count:
		var o := i * LevelData.WALL_STRIDE
		if int(hub.world.walls[o + 4]) == face_tile and hub.world.walls[o + 1] > gate.y:
			facing_hub = true
	check(facing_hub, "a Crossroads gate's name board faces the Crossroads, not the hedge")
	# The fingerpost: an arm for every gate, its point (the picture's right, as
	# the arm's plane runs) toward that gate. It used to send players the wrong way.
	var pointed := 0
	for each: LevelData.Gate in hub.world.hub_gates:
		for board: LevelData.Billboard in hub.world.billboards:
			if board.image != "hub_arm_" + each.destination or is_nan(float(board.plane)):
				continue
			var way := Vector2(cos(float(board.plane)), sin(float(board.plane)))
			var to_gate := (Vector2(each.x, each.y) - Vector2(board.x, board.y)).normalized()
			if way.dot(to_gate) > cos(deg_to_rad(1.5)):
				pointed += 1
	check(
		pointed == hub.world.hub_gates.size() and pointed == Campaign.ORDER.size(),
		"every chapter has a Crossroads gate and a fingerpost arm pointing at it"
	)


func _stand(g: Game, x: float, y: float, angle: float) -> void:
	var p := g.player
	p.x = x
	p.y = y
	p.angle = angle
	p.pitch = 0.0
	p.eye = g.world.elevation(x, y) + .95


## The Mothership, the last chapter: the tin guard's tailgate, Maw Glorb's
## phases, telegraphs, pod crew and fall, and the true finale after it.
func _mothership(main) -> void:
	print("\nTHE MOTHERSHIP")
	var ship: Game = main.make_game("mothership")
	ship.configure({})
	ship.spawn_grace = 0.0
	var fight = ship.features.get("mothership")
	check(fight != null and fight.maw != null, "the ship's finale is Maw Glorb")
	check(ship.finale != null and ship.finale.kind == "maw", "Maw is the chapter's finale boss")
	check(fight.pods.size() == 8, "eight pods round the core (%d)" % fight.pods.size())
	var guard := Enemy.new("tin_guard", 30.0, 30.0, 0.0)
	ship.enemies.append(guard)
	ship.player.x = 33.0
	ship.player.y = 30.0
	var whole := guard.hp
	guard.hurt(40.0, ship, false, false, null, "revolver")
	check(absf(whole - guard.hp - 12.0) < .01, "the tailgate stops most of a shot from the front")
	guard.angle = PI
	var before := guard.hp
	guard.hurt(40.0, ship, false, false, null, "revolver")
	check(absf(before - guard.hp - 40.0) < .01, "from behind it takes the whole shot")
	ship.enemies.erase(guard)
	var maw: Enemy = fight.maw
	check(maw.dormant, "Maw sleeps till the iris opens")
	for id in ["drive", "tubes", "iris"]:
		for station: LevelData.Station in ship.world.stations:
			if station.id == id:
				ship.activate_station(station)
	check(not maw.dormant, "the iris wakes her")
	ship.player.x = 64.5
	ship.player.y = 41.5
	ship.player.angle = PI / 2
	maw.hurt(maw.max_hp * .4, ship)
	ship.ticked.emit(1.0 / 60.0)
	check(fight.phase == 2 and maw.enraged, "two thirds down she is fightin' mad (phase two)")
	check(fight.beam_count() > 0, "the tractor beam comes loose in phase two")
	maw.windup = 0.0
	maw.attacks = 0
	maw.cooldown = 0.0
	maw.windup = .5
	maw.aim_mark = [ship.player.x, ship.player.y, ship.player.eye]
	fight.winding = false
	ship.ticked.emit(1.0 / 60.0)
	check(fight.pending != "", "her wind-up picks an attack (%s)" % fight.pending)
	check(fight.ground_marks().size() > 0, "and marks the floor for it")
	var crew_before := ship.enemies.size()
	fight.phase = 2
	fight._call_crew()
	check(ship.enemies.size() > crew_before, "her holler brings crew out of the pods")
	maw.hurt(maw.hp - maw.max_hp * .2, ship)
	ship.ticked.emit(1.0 / 60.0)
	check(fight.phase == 3, "a third left she is out of the housecoat (phase three)")
	check(ShipAliens.skin(maw) == "_bare", "and drawn in her second set of pictures")
	maw.hurt(99999.0, ship)
	check(fight.fallen_at >= 0.0, "her fall starts the ship coming apart")
	var crew_left := 0
	for i in range(ship.enemy_ids.size(), ship.enemies.size()):
		if ship.enemies[i].alive:
			crew_left += 1
	check(crew_left == 0, "her pod crew drop with her")
	for e: Enemy in ship.wave:
		e.hurt(99999.0, ship)
	Triggers.tick(ship)
	var hatch_open := false
	for door: LevelData.Door in ship.world.doors:
		if door.x == 64 and door.y == 62:
			hatch_open = door.opened
	check(hatch_open, "the core's hatch opens the way out")
	check(ship.exit_ready(), "the escape outhouse is ready")
	ship.history = [["hickston", 1, 2, 0, 1, 60], ["fair", 1, 2, 0, 1, 60]]
	ship.finish_level("gate")
	var canvas := Canvas.new()
	ship.draw(canvas, 1, true)
	var lit := 0
	for i in range(0, canvas.pixels.size(), 3):
		if canvas.pixels[i] != 0 or canvas.pixels[i + 1] != 0:
			lit += 1
	check(lit > 4000, "the finale's tally draws after the last chapter (%d lit)" % lit)
	check(Campaign.next_level("mothership") == "", "the Mothership is the last chapter")
