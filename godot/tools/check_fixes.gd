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
			var row := Menu.row_rect(main.option_slot, main.option_scroll)
			if row.size.y == 0 or row.end.y > Menu.FOOTER_Y - 2 or not Menu.LIST.encloses(row):
				bounded = false
			var hit := Menu.setup_hit(
				row.position.x + 4,
				row.position.y + 4,
				pages.size(),
				settings.size(),
				main.option_scroll
			)
			if String(hit["kind"]) != "row" or int(hit["index"]) != slot:
				bounded = false
			seen[(settings[slot] as SessionStore.Setting).key] = true
	check(
		bounded, "every setting can be selected, stays inside the list and clear of the help text"
	)
	check(
		seen.size() == 48 + KeyBindings.ACTIONS.size(),
		"all 40 settings and every control's key are on a page"
	)
	var stored := SessionStore.settings("")
	var kept := true
	for key in seen:
		if not stored.has(key):
			kept = false
	check(kept, "every setting still has its stored key")
	main.option_page = 2
	main.option_slot = 1
	var was := int(main.options["effects"])
	main.adjust_setting(-1)
	check(int(main.options["effects"]) == was - 10, "a volume step changes the option")
	check(main.sound._preview.player.playing, "and plays a preview")
	main.adjust_setting(1)
	check(main.sound._preview.cue == "shotgun", "a second change restarts the one preview voice")
	main.option_page = 1
	main.option_slot = 1
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

	print("")
	if failures.is_empty():
		print("PARITY FIXES OK")
	else:
		print("%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)
