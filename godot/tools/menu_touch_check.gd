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
## screen the BUY plate, a store row (bought) and a tap outside (closed);
## COUNTY RUN's map picker, its reward cards (a pick, a swap, CANCEL), the
## build screen and the end of a run's buttons, and a card picked by mouse;
## CUSTOM MAPS (a map, an action, NEW MAP) and the MAP SHED (a palette item,
## a cell painted, the TEAR OUT tab, BACK twice past the unsaved warning);
## in play, the junk bench's board (a tag tapped buys it, a tap off it shuts
## it) and the USE button held down (a revive, BLUE got up, a plant or a
## defuse: Controls.hold), and a tap skipping a chapter's opener.
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
	_county()
	_maps()
	_play()
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
		if OS.get_environment("GITHUB_ACTIONS") != "":
			# A CI annotation: readable without the run's logs.
			print("::error title=%s::%s" % [get_script().resource_path.get_file(), text])


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
func _tap_zone(id: String, arg := -99) -> bool:
	main.render()
	for z: Array in LobbyScreens.zones:
		if String(z[1]) == id and (arg == -99 or int(z[2]) == arg):
			var r: Rect2i = z[0]
			# A row: on its value, right of the middle (where a < may sit).
			var x := r.size.x * 3 / 4 if id == "row" else r.size.x / 2
			_tap(r.position + Vector2i(x, r.size.y / 2))
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
	var long_was: int = main.showdown_long
	_tap_zone("row", 2)
	_check(main.showdown_row == 2 and main.showdown_long != long_was, "one tap on MATCH changes it")
	var skill_was: int = main.showdown_skill
	_tap_zone("left", 4)
	_check(
		main.showdown_row == 4 and main.showdown_skill != skill_was,
		"BOTS' arrow changes the bots' skill"
	)
	_tap_zone("right", 4)
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
	_tap_zone("mode", 1)
	_check(String(net.settings["mode"]) != mode_was, "MODE: one click changes it")
	_tap_zone("mode", -1)
	_check(String(net.settings["mode"]) == mode_was, "and its < steps it back")
	var team_was := int(net.player_of(net.my_id)["team"])
	_tap_zone("team")
	_check(int(net.player_of(net.my_id)["team"]) != team_was, "TEAM changes the team")
	_tap_zone("more")
	_check(main.state == "lobbyset", "ALL SETTINGS opens the whole list")
	var rounds_was := int(net.settings["rounds"])
	_tap_zone("row", 3)
	_check(
		LobbyScreens.all_row == 3 and int(net.settings["rounds"]) != rounds_was,
		"one click on ROUNDS TO WIN changes it"
	)
	_tap_zone("dec", 3)
	_check(int(net.settings["rounds"]) == rounds_was, "and its < steps it back")
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
	_finger(Vector2i(318, 100))
	_check(not TacticalScreens.open, "a tap outside the store closes it")
	print("\nTHE 5V5 STORE WITH A MOUSE")
	TacticalScreens.touch_on = false
	TacticalScreens.pending_buys.clear()
	main.key(KEY_B)
	main._shop_pointer()
	_check(
		TacticalScreens.open and TacticalScreens.mouse_free,
		"B opens the store and lets the pointer go"
	)
	main.render()
	var gear := _find("item", 100)
	if not gear.is_empty():
		var at: Vector2i = gear[0].position + gear[0].size / 2
		var rect: Rect2 = main.viewport_rect()
		var where := rect.position + (Vector2(at) + Vector2(.5, .5)) * rect.size / Vector2(320, 200)
		var moved := InputEventMouseMotion.new()
		moved.position = where
		main._input(moved)
		_check(
			TacticalScreens.page == 1 and TacticalScreens.cursor == 0,
			"pointing at the vest picks it"
		)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = where
		main._input(click)
	_check(not TacticalScreens.pending_buys.is_empty(), "a click buys it")
	_check(main.block_fire, "and the click does not fire the gun")
	main.key(KEY_B)
	main._shop_pointer()
	_check(
		not TacticalScreens.open and not TacticalScreens.mouse_free,
		"B shuts it and aiming takes the pointer back"
	)
	main.game = null
	main.state = "title"


func _county() -> void:
	print("\nCOUNTY RUN BY TOUCH")
	CountyRecords.folder_override = OS.get_cache_dir().path_join("clmr-county-touch")
	main.state = "title"
	main.game = null
	main.render()
	var titles: Array = main.entries()
	var at: int = titles.find("COUNTY RUN")
	var spot := Vector2i(-1, -1)
	for y in range(30, 200, 2):
		for x in range(10, 310, 4):
			if spot.x < 0 and Menu.title_hit(titles, x, y) == at:
				spot = Vector2i(x, y)
	_tap(spot)
	_check(main.state == "county", "the title's COUNTY RUN opens the map picker (%s)" % main.state)
	_tap_zone("back")
	_check(main.state == "title", "BACK goes back to the title")
	main.state = "county"
	_tap_zone("map", 2)
	var g: Game = main.game
	_check(
		(
			main.state == "play"
			and g != null
			and g.level.id == "county_bayou"
			and CountyMode.active(g)
		),
		"a tap on GATOR BAYOU starts a run there"
	)
	if g == null:
		return
	g.tick(1.0 / 120.0, Game.Controls.new())
	var f = g.features["county"]
	CountyBuild.put_weapon(g, f, Weapons.SHOTGUN, 2)
	f.pending = [[2, false, g.armory.active]]
	var cards := [
		CountyBuild.card("weapon", "", Weapons.RIFLE),
		CountyBuild.card("perk", "good_boots"),
		CountyBuild.card("upgrade", "quick_hands", Weapons.REVOLVER)
	]
	f.offer = cards.duplicate(true)
	main.render()
	CountyScreens._shown_at = -100000
	_tap_zone("card", 0)
	_check(
		CountyScreens.swapping == 0,
		"a tap on a weapon card with every slot full asks which to swap"
	)
	_tap_zone("slot", 2)
	_check(CountyScreens.swap_slot == 2, "a tap picks the slot to swap out")
	_tap_zone("cancel")
	_check(
		CountyScreens.swapping < 0 and f.offer == cards, "CANCEL goes back to the same three cards"
	)
	_tap_zone("build")
	_check(CountyScreens.build_open and f.paused, "BUILD opens the build screen (the world held)")
	_tap_zone("close")
	_check(not CountyScreens.build_open and not f.paused, "CLOSE shuts it")
	CountyScreens._shown_at = -100000
	_tap_zone("card", 1)
	_check(
		f.pending.is_empty() and CountyBuild.perk_rank(f, "good_boots") == 1,
		"a tap on a perk card takes it"
	)
	print("\nCOUNTY RUN WITH A MOUSE")
	f.pending = [[3, false, g.armory.active]]
	f.offer = cards.duplicate(true)
	main.render()
	CountyScreens._shown_at = -100000
	main._shop_pointer()
	_check(CountyScreens.wants_pointer(g), "the cards let the pointer go")
	var card := _find("card", 2)
	if not card.is_empty():
		var p: Vector2i = card[0].position + card[0].size / 2
		var rect: Rect2 = main.viewport_rect()
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = (
			rect.position + (Vector2(p) + Vector2(.5, .5)) * rect.size / Vector2(320, 200)
		)
		main._input(click)
	_check(
		f.pending.is_empty() and CountyBuild.rank(f, Weapons.REVOLVER, "quick_hands") == 1,
		"a click on a card takes it"
	)
	print("\nTHE END OF A RUN BY TOUCH")
	g.damage(9999.0, null, "TEST")
	main.render()
	_check(
		CountyScreens.covering(g) and _find("retry").size() > 0,
		"the end shows RETRY, MAPS and TITLE"
	)
	_tap_zone("retry")
	_check(
		main.game != g and main.game != null and main.game.level.id == "county_bayou",
		"RETRY starts the map again"
	)
	main.game.tick(1.0 / 120.0, Game.Controls.new())
	main.game.damage(9999.0, null, "TEST")
	main.render()
	_tap_zone("maps")
	_check(main.state == "county" and main.game == null, "MAPS goes back to the map picker")
	main.state = "title"
	CountyRecords.folder_override = ""


func _maps() -> void:
	print("\nCUSTOM MAPS AND THE MAP SHED BY TOUCH")
	UserMaps.folder_override = OS.get_cache_dir().path_join("clmr-maps-touch")
	main.state = "title"
	main.game = null
	main.render()
	var titles: Array = main.entries()
	var at: int = titles.find("CUSTOM MAPS")
	var spot := Vector2i(-1, -1)
	for y in range(30, 200, 2):
		for x in range(10, 310, 4):
			if spot.x < 0 and Menu.title_hit(titles, x, y) == at:
				spot = Vector2i(x, y)
	_tap(spot)
	_check(main.state == "maps", "the title's CUSTOM MAPS opens the list (%s)" % main.state)
	var row := CustomMapsScreen.LIST.position + Vector2i(40, 2 + CustomMapsScreen.ROW_H + 8)
	_tap(row)
	_check(UserMapPlay.row == 1, "a tap on a map picks it (row %d)" % UserMapPlay.row)
	var edit := Rect2i()
	for i in 9:
		var r := Rect2i(
			CustomMapsScreen.PANEL.position.x + 3,
			CustomMapsScreen.ACTIONS_Y + i * CustomMapsScreen.ACTION_H,
			40,
			CustomMapsScreen.ACTION_H - 1
		)
		if i == UserMapPlay.ACTIONS.find("edit"):
			edit = r
	_tap(edit.position + Vector2i(10, 3))
	_check(
		main.state == "mapedit" and UserMapPlay.editor != null,
		"EDIT IN THE SHED opens the map in the shed (%s)" % main.state
	)
	_tap(Vector2i(270, MapEditorScreen.PLATES_Y + 4))
	_check(
		main.state == "maps",
		"the shed's BACK goes back to the list, nothing changed (%s)" % main.state
	)
	UserMapPlay.row = 0
	_tap(CustomMapsScreen.LIST.position + Vector2i(40, 8))
	_check(main.state == "mapedit", "+ NEW MAP opens a blank map in the shed (%s)" % main.state)
	var ed := UserMapPlay.editor
	# PLAIN DIRT, the GROUND tab's second item, then a cell of the plan.
	_tap(Vector2i(MapEditorScreen.PALETTE.position.x + 20, MapEditorScreen.ITEMS_Y + 8 + 3))
	_check(str(ed.item()["label"]) == "PLAIN DIRT", "a tap on the palette picks PLAIN DIRT")
	var px := ed.cells_px()
	var size := Vector2i(UserMap.width(ed.map), UserMap.height(ed.map)) * px
	var origin := (
		MapEditorScreen.VIEW.position + ((MapEditorScreen.VIEW.size - size) / 2).max(Vector2i.ZERO)
	)
	_tap(origin + Vector2i(5, 5) * px + Vector2i(px / 2, px / 2))
	_check(
		UserMap.at(ed.map, 5, 5) == ".",
		"a tap on the plan paints the cell (%s)" % UserMap.at(ed.map, 5, 5)
	)
	for i in 8:
		_tap(Vector2i(MapEditorScreen.PALETTE.end.x - 6, MapEditorScreen.PALETTE.position.y + 6))
	_check(
		str(ed.item()["label"]) == "TEAR IT OUT",
		"the tab arrow reaches TEAR OUT (%s)" % ed.item()["label"]
	)
	_tap(origin + Vector2i(5, 5) * px + Vector2i(px / 2, px / 2))
	_check(UserMap.at(ed.map, 5, 5) == ".", "tearing out bare ground leaves it be")
	var back := Vector2i(270, MapEditorScreen.PLATES_Y + 4)
	_tap(back)
	_check(
		main.state == "mapedit" and ed.note.begins_with("NOT SAVED"),
		"BACK on an unsaved map warns first (%s)" % ed.note
	)
	_tap(back)
	_check(main.state == "maps", "BACK again leaves it (%s)" % main.state)
	UserMaps.folder_override = ""
	main.state = "title"


func _find(id: String, arg := -99) -> Array:
	for z: Array in LobbyScreens.zones:
		if String(z[1]) == id and (arg == -99 or int(z[2]) == arg):
			return [z[0]]
	return []


func _play() -> void:
	print("\nPLAY BY TOUCH")
	var g: Game = main.make_game("hickston")
	g.configure({"difficulty": 1, "bench": 1})
	g.cheats.god = true
	g.lessons = false
	g.enemies.clear()
	g.enemy_ids.clear()
	for i in 2:
		g.tick(1.0 / 60.0, Game.Controls.new())
	main.game = g
	main.state = "play"
	var bench: Game.BenchScript = g.features.get("bench")
	if bench == null or bench.benches.is_empty():
		_check(false, "hickston has a junk bench")
		return
	var b: Array = bench.benches[0]
	var p := g.player
	var facing: float = b[2]
	p.x = float(b[0]) + sin(facing) * 1.1
	p.y = float(b[1]) + cos(facing) * 1.1
	p.angle = atan2(float(b[1]) - p.y, float(b[0]) - p.x)
	for gun: String in ["revolver", "shotgun"]:
		p.armory.owned[Weapons.NAMES.find(gun)] = true
	p.armory.scrap = 99
	BenchScreen.reset()
	BenchScreen.show(g)
	main.render()
	var tag := Rect2i()
	for z: Array in BenchScreen._zones:
		if BenchScreen.mod_at(int(z[1]), int(z[2])) != "":
			tag = z[0]
			break
	_check(tag.size.x > 0, "the bench's board shows its tags")
	_finger(tag.position + tag.size / 2)
	_check(not BenchScreen.pending_buys.is_empty(), "tapping a tag on the board buys it")
	_finger(Vector2i(160, 196))
	_check(not BenchScreen.open, "a tap off the board shuts it")
	BenchScreen.reset()
	# The USE button held: Controls.hold for as long as the finger stays.
	main.touch.set_showing(true)
	main.touch.layout(main.viewport_rect())
	var use_at := Vector2.INF
	for button: Array in main.touch.buttons:
		if str(button[0]) == "use":
			use_at = button[1]
	_check(use_at != Vector2.INF, "the overlay has a USE button")
	if use_at != Vector2.INF:
		var down := InputEventScreenTouch.new()
		down.index = 3
		down.position = use_at
		down.pressed = true
		main._input(down)
		var held: Game.Controls = main._controls(
			1.0 / 60.0, main.read_pad(1.0 / 60.0), main.touch.state()
		)
		_check(held.hold, "USE held down on the overlay holds USE (a revive, a plant)")
		var up := InputEventScreenTouch.new()
		up.index = 3
		up.position = use_at
		up.pressed = false
		main._input(up)
		var let_go: Game.Controls = main._controls(
			1.0 / 60.0, main.read_pad(1.0 / 60.0), main.touch.state()
		)
		_check(not let_go.hold, "and lets go with the finger")
	main.touch.release()
	# A chapter's opener: a tap skips it.
	main.opener.begin(main, g)
	if main.opener.playing:
		var tap := InputEventScreenTouch.new()
		tap.index = 0
		tap.position = Vector2(200, 200)
		tap.pressed = true
		main._input(tap)
		_check(not main.opener.playing, "a tap skips a chapter's opener")
	main.game = null
	main.state = "title"


## A quick finger on the play screen's overlay (a tap, not a button), read
## as the frame reads it.
func _finger(p: Vector2i) -> void:
	var rect: Rect2 = main.viewport_rect()
	main.touch.tap = rect.position + (Vector2(p) + Vector2(.5, .5)) * rect.size / Vector2(320, 200)
	main._touch_actions()
