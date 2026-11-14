## Fingers on the menus (src/net/online_input.gd, LobbyScreens.zones,
## TacticalScreens.tap), headless: every tap goes in as a real touch event
## through Main._input, as a phone or a touch browser sends it.
##
##   Godot --headless --path <project> --script res://tools/menu_touch_check.gd
##
## The title's MULTIPLAYER; MULTIPLAYER's four choices; PLAY VS BOTS's arrows,
## a tap on a picked row, BACK; the server list's name field and BACK; the
## host and join forms' rows and BACK; a hosted lobby's settings, ALL
## SETTINGS (a row, >, DONE), TEAM and CLOSE; and in a 5v5 freeze on a touch
## screen the BUY plate, a store row (bought) and a tap outside (closed).
## Fails on any script or engine error.
extends SceneTree

var failures: Array = []
var main


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var tally := CrashLog.tally()
	_menus()
	_lobby()
	_store()
	tally.stop()
	_check(
		tally.errors == 0,
		(
			"no script or engine errors"
			+ ("" if tally.errors == 0 else " (%d: %s)" % [tally.errors, tally.first_errors[0]])
		)
	)
	print("")
	print("MENU TOUCH OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


## A finger down and up on the picture's pixel `p`.
func _tap(p: Vector2i) -> void:
	var rect: Rect2 = main.viewport_rect()
	var at := rect.position + (Vector2(p) + Vector2(.5, .5)) * rect.size / Vector2(320, 200)
	for pressed in [true, false]:
		var finger := InputEventScreenTouch.new()
		finger.index = 0
		finger.position = at
		finger.pressed = pressed
		main._input(finger)


## Draws the screen (its taps are noted as it draws), then taps the middle of
## the place noted as `id` (and `arg`). False when the screen has no such place.
func _tap_zone(id: String, arg := -1) -> bool:
	main.render()
	for z: Array in LobbyScreens.zones:
		if String(z[1]) == id and (arg < 0 or int(z[2]) == arg):
			var r: Rect2i = z[0]
			_tap(r.position + r.size / 2)
			return true
	return false


func _menus() -> void:
	print("\nMENUS BY TOUCH")
	main.state = "title"
	main.render()
	var at := -1
	var titles: Array = main.entries()
	at = titles.find("MULTIPLAYER")
	var spot := Vector2i(-1, -1)
	for y in range(30, 200, 2):
		for x in range(10, 310, 4):
			if spot.x < 0 and Menu.title_hit(titles, x, y) == at:
				spot = Vector2i(x, y)
	_tap(spot)
	_check(main.state == "multi", "the title's MULTIPLAYER opens MULTIPLAYER (%s)" % main.state)
	_tap_zone("row", 1)
	_check(main.state == "showdown", "PLAY VS BOTS opens the bots' match")
	var mode_was: int = main.showdown_mode
	_tap_zone("right", 0)
	_check(main.showdown_mode != mode_was, "MODE's arrow changes the mode")
	_tap_zone("row", 2)
	var long_was: int = main.showdown_long
	_tap_zone("row", 2)
	_check(
		main.showdown_row == 2 and main.showdown_long != long_was,
		"a tap picks MATCH, a second tap changes it"
	)
	_tap_zone("back")
	_check(main.state == "multi", "BACK goes back to MULTIPLAYER")
	_tap_zone("row", 0)
	_check(main.state == "servers" and main.browser != null, "PLAY ONLINE opens the servers")
	_tap_zone("name")
	_check(main.browser != null and main.browser.row == 0, "a tap on YOUR NAME picks it to type")
	_tap_zone("back")
	_check(main.state == "multi" and main.browser == null, "BACK leaves the list (it stops asking)")
	_tap_zone("row", 2)
	_check(main.state == "nethost", "HOST A GAME opens its form")
	_tap_zone("row", 1)
	_check(main.net_row == 1, "a tap picks a form's field")
	_tap_zone("back")
	_tap_zone("row", 3)
	_check(main.state == "netjoin", "JOIN WITH A CODE opens its form")
	_tap_zone("back")
	_check(main.state == "multi", "and BACK again")


func _lobby() -> void:
	print("\nTHE LOBBY BY TOUCH")
	var net := NetPlay.host_lobby(
		41000 + OS.get_process_id() % 9000, "TREY", {}, false, "127.0.0.1"
	)
	if net == null:
		_check(false, "a lobby to host")
		return
	main._net_ready(net)
	_check(main.state == "lobby", "a hosted lobby")
	var mode_was := String(net.settings["mode"])
	_tap_zone("mode")
	_tap_zone("mode")
	_check(String(net.settings["mode"]) != mode_was, "MODE: a tap picks it, a second changes it")
	var team_was := int(net.player_of(net.my_id)["team"])
	_tap_zone("team")
	_check(int(net.player_of(net.my_id)["team"]) != team_was, "TEAM changes the team")
	_tap_zone("more")
	_check(main.state == "lobbyset", "ALL SETTINGS opens the whole list")
	_tap_zone("row", 3)
	var rounds_was := int(net.settings["rounds"])
	_tap_zone("right")
	_check(
		LobbyScreens.all_row == 3 and int(net.settings["rounds"]) != rounds_was,
		"a row and > change ROUNDS TO WIN"
	)
	_tap_zone("back")
	_check(main.state == "lobby", "DONE goes back to the lobby")
	_tap_zone("back")
	_check(main.net == null or main.net.phase == "closed", "CLOSE closes the lobby")
	net.finish()


func _store() -> void:
	print("\nTHE 5V5 STORE BY TOUCH")
	var g: Game = main.make_game("grainyard")
	g.configure({"difficulty": 1})
	Modes.setup(g, Modes.BOMB, 10, {"arena": "grainyard"})
	for i in 30:
		g.tick(1.0 / 120.0, {})
	main.game = g
	main.state = "play"
	TacticalScreens.human = 0
	TacticalScreens.open = false
	TacticalScreens.touch_on = true
	TacticalScreens.pending_buys.clear()
	main.render()
	var plate := _find("buy")
	_check(plate.size() > 0, "a BUY plate in the freeze on a touch screen")
	if plate.is_empty():
		return
	_finger(plate[0].position + plate[0].size / 2)
	_check(TacticalScreens.open, "tapping BUY opens the store")
	main.render()
	var row := _find("item", 0)
	if not row.is_empty():
		_finger(row[0].position + row[0].size / 2)
	_check(not TacticalScreens.pending_buys.is_empty(), "tapping a row buys it")
	main.render()
	_finger(Vector2i(250, 100))
	_check(not TacticalScreens.open, "a tap outside the store closes it")
	TacticalScreens.touch_on = false
	main.game = null
	main.state = "title"


func _find(id: String, arg := -1) -> Array:
	for z: Array in LobbyScreens.zones:
		if String(z[1]) == id and (arg < 0 or int(z[2]) == arg):
			return [z[0]]
	return []


## A quick finger on the play screen's overlay (a tap, not a button), read
## as the frame reads it.
func _finger(p: Vector2i) -> void:
	var rect: Rect2 = main.viewport_rect()
	main.touch.tap = rect.position + (Vector2(p) + Vector2(.5, .5)) * rect.size / Vector2(320, 200)
	main._touch_actions()
