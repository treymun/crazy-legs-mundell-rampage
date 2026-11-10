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

	print("")
	if failures.is_empty():
		print("PARITY FIXES OK")
	else:
		print("%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)
