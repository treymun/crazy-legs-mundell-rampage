## The menus and the play buttons by touch alone, headless, the companion of
## touch_settings_check.gd: every event goes in the way the engine delivers it
## (Input.parse_input_event, then flushed), a finger numbered as a phone's
## browser may number it (a big Touch.identifier), each drag followed by the
## browser's pointermove echo (a MouseMotion with no button held).
##
##   Godot --headless --path <project> --script res://tools/touch_screens_check.gd
##
## From the title, each screen a finger opens and closes again with its BACK:
## SAVE SLOTS from a paused game (SAVE, a slot, the name's CANCEL plate, LOAD
## on a slot), CONTROLS (opens on the TOUCH page; a tab), CREDITS (a tap closes it), REPLAY
## LEVEL, MULTIPLAYER, COUNTY RUN's map, CUSTOM MAPS and BOSS REMATCH. In play
## every on-screen button (the overlay's shown buttons, whatever they are):
## a press lands on it, FIRE ALT JUMP DUCK are held while the finger stays,
## the stick walks, a drag on the right turns, MAP opens the map, NEXT changes
## the gun, PHOTO and then MENU go in and out of PHOTO MODE, MENU pauses to the
## title; and the playing area's top row never overlaps on a phone held
## upright. Fails on any script or engine error. Writes nothing to the profile.
extends SceneTree

const FINGER := 9120

var failures: Array = []
var main
var _last := Vector2.ZERO


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	var tally := CrashLog.tally()
	await _menus()
	await _play()
	_upright()
	tally.stop()
	_check(
		tally.errors == 0,
		(
			"no script or engine errors"
			+ ("" if tally.errors == 0 else " (%d: %s)" % [tally.errors, tally.first_errors[0]])
		)
	)
	print("")
	print("TOUCH SCREENS OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
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


# ----------------------------------------------------------------- fingers


func _at(p: Vector2) -> Vector2:
	var rect: Rect2 = main.viewport_rect()
	return rect.position + (p + Vector2(.5, .5)) * rect.size / Vector2(320, 200)


## A frame of the front end's: a menu's screen is shown (and its focus put,
## deferred) and a zoned screen notes its taps as it draws.
func _frame() -> void:
	if main.state != "play":
		main.render()
	await process_frame


func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _frame()


## A finger down (or up) at the window's point `w`.
func _finger(w: Vector2, pressed: bool, index := FINGER) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = index
	touch.position = w
	touch.pressed = pressed
	_last = w
	await _send(touch)


func _slide(w: Vector2, index := FINGER) -> void:
	var drag := InputEventScreenDrag.new()
	drag.index = index
	drag.position = w
	drag.relative = w - _last
	_last = w
	Input.parse_input_event(drag)
	var echo := InputEventMouseMotion.new()
	echo.position = w
	echo.global_position = w
	echo.relative = drag.relative
	Input.parse_input_event(echo)
	Input.flush_buffered_events()
	await _frame()


## A tap on the picture's pixel `p`.
func _tap(p: Vector2) -> void:
	await _finger(_at(p), true)
	await _finger(_at(p), false)


static func _mid(r: Rect2i) -> Vector2:
	return Vector2(r.position) + Vector2(r.size) * .5


# ------------------------------------------------------------------- menus


## Tap the title's `id` entry; true when it left the title.
func _title_tap(id: String) -> bool:
	main.state = "title"
	main.menu_note = ""
	await _frame()
	for item: Dictionary in Menu.title_items(main.entries()):
		if str(item["id"]) == id:
			await _tap(_mid(item["rect"]))
			return main.state != "title"
	return false


func _back(what: String) -> void:
	await _tap(_mid(Menu.BACK))
	_check(main.state == "title", "%s: BACK by a tap goes to the title (%s)" % [what, main.state])


func _menus() -> void:
	print("\nMENUS BY A FINGER (index %d)" % FINGER)
	_check(await _title_tap("CONTROLS"), "the title's CONTROLS by a tap")
	if main.state == "controls":
		_check(main.controls_page == 2, "CONTROLS: a finger opens it on the TOUCH page")
		await _tap(Vector2(20 + MainState.CONTROL_TAB / 2, 38))
		_check(main.controls_page == 0, "CONTROLS: a tab by a tap")
		await _back("CONTROLS")
	_check(await _title_tap("CREDITS"), "the title's CREDITS by a tap")
	if main.state == "credits":
		await _tap(Vector2(160, 100))
		_check(main.state == "title", "CREDITS: a tap anywhere goes back (%s)" % main.state)
	for pair: Array in [
		["REPLAY LEVEL", "replays"],
		["MULTIPLAYER", "multi"],
		["COUNTY RUN", "county"],
		["CUSTOM MAPS", "maps"],
		["BOSS REMATCH", "rematch"],
	]:
		var id := str(pair[0])
		var opened := await _title_tap(id)
		_check(
			opened and main.state == str(pair[1]), "the title's %s by a tap (%s)" % [id, main.state]
		)
		if main.state != "title":
			await _back(id)


# -------------------------------------------------------------------- play
## LOAD / SAVE from a paused game: SAVE, a slot (it asks for a name), the
## CANCEL plate, LOAD, a slot (empty in a scratch profile: it says so), BACK.
func _slots() -> void:
	_check(await _title_tap("SAVE SLOTS"), "the title's LOAD / SAVE by a tap")
	if main.state == "slots":
		await _tap(Vector2(90, 41))
		_check(main.slot_mode == "save", "SAVE SLOTS: the SAVE tab by a tap")
		await _tap(Vector2(150, MainState.SLOT_TOP + 8))
		_check(main.slot_stage == "edit", "SAVE SLOTS: a slot by a tap asks for a name")
		await _tap(_mid(MainState.SLOT_STOP))
		_check(main.slot_stage == "choose", "SAVE SLOTS: the CANCEL plate by a tap")
		await _tap(Vector2(230, 41))
		_check(main.slot_mode == "load", "SAVE SLOTS: the LOAD tab by a tap")
		await _tap(Vector2(150, MainState.SLOT_TOP + MainState.SLOT_ROW * 3 + 8))
		_check(
			main.state != "slots" or str(main.menu_note) != "",
			"SAVE SLOTS: LOAD on a slot by a tap answers (%s)" % main.menu_note
		)
		if main.state == "slots":
			await _back("SAVE SLOTS")


func _play() -> void:
	print("\nPLAY BUTTONS BY A FINGER")
	var g: Game = main.make_game("hickston")
	g.configure({"difficulty": 1})
	g.cheats.god = true
	g.lessons = false
	g.enemies.clear()
	g.enemy_ids.clear()
	for i in 2:
		g.tick(1.0 / 60.0, Game.Controls.new())
	for gun: String in ["revolver", "shotgun"]:
		g.player.armory.owned[Weapons.NAMES.find(gun)] = true
	main.game = g
	await _slots()
	main.state = "play"
	var touch: TouchControls = main.touch
	touch.active = true
	main._apply_view()
	_check(touch.showing, "the touch buttons show in play")
	var roles: Array[String] = []
	for button: Array in touch.shown_buttons():
		roles.append(str(button[0]))
	_check(roles.size() >= 12, "the overlay shows its buttons (%s)" % ", ".join(roles))
	for button: Array in touch.shown_buttons():
		await _button(str(button[0]), button[1])
	await _stick()
	await _turn()
	main.state = "play"
	touch.release()
	main.game = null
	main.state = "title"


## One button: a finger lands on it and does what it says.
func _button(role: String, center: Vector2) -> void:
	var touch: TouchControls = main.touch
	main.state = "play"
	await _finger(center, true)
	var landed := touch.pressing(role) or int(touch.counts.get(role, 0)) > 0
	_check(landed, "%s: a finger lands on it" % TouchControls.LABELS[role])
	var held := {"fire": "fire", "alt": "alt", "jump": "jump", "crouch": "crouch"}
	if held.has(role):
		touch._refresh()
		var now: Dictionary = touch.state()
		_check(
			bool(now[held[role]]), "%s: held while the finger stays" % TouchControls.LABELS[role]
		)
	await _finger(center, false)
	var gun_was: int = main.game.player.armory.active
	var map_was: bool = main.game.map
	main._touch_actions()
	match role:
		"map":
			_check(main.game.map != map_was, "MAP: opens the map")
			main.game.map = false
		"next":
			for _t in 30:
				main.game.tick(1.0 / 60.0, Game.Controls.new())
			_check(main.game.player.armory.active != gun_was, "NEXT: changes the gun")
		"menu":
			_check(main.state == "title", "MENU: pauses to the title (%s)" % main.state)
		"photo":
			_check(main.photo.on, "PHOTO: goes into PHOTO MODE")
			var menu_at := _button_at("menu")
			await _finger(menu_at, true)
			await _finger(menu_at, false)
			main._touch_actions()
			_check(not main.photo.on, "PHOTO MODE: MENU comes back out")
	touch.release()


func _button_at(role: String) -> Vector2:
	for button: Array in main.touch.buttons:
		if str(button[0]) == role:
			return button[1]
	return Vector2.ZERO


func _stick() -> void:
	var touch: TouchControls = main.touch
	var c := touch.stick_center
	await _finger(c, true)
	await _slide(c + Vector2(0, -touch.stick_radius * .8))
	var now: Dictionary = touch.state()
	_check(float(now["forward"]) > .5, "the stick: pushed up walks forward (%.2f)" % now["forward"])
	await _finger(c, false)
	touch.release()


func _turn() -> void:
	var touch: TouchControls = main.touch
	var from := touch.area.position + touch.area.size * Vector2(.6, .45)
	await _finger(from, true)
	for i in 4:
		await _slide(from + Vector2(20 * (i + 1), 0))
	var now: Dictionary = touch.state()
	_check(float(now["turn"]) > 0.0, "a drag on the right turns the view (%.3f)" % now["turn"])
	await _finger(from + Vector2(80, 0), false)
	touch.release()


## A phone held upright (a browser): the top row's rings stay apart.
func _upright() -> void:
	print("\nA PHONE HELD UPRIGHT")
	var touch: TouchControls = main.touch
	touch.layout(Rect2(0, 0, 390, 844), true)
	var worst := INF
	for a: Array in touch.buttons:
		for b: Array in touch.buttons:
			if str(a[0]) < str(b[0]):
				var ca: Vector2 = a[1]
				var cb: Vector2 = b[1]
				var gap: float = ca.distance_to(cb) - float(a[2]) - float(b[2])
				worst = minf(worst, gap)
	_check(worst >= 0.0, "no two buttons overlap at 390x844 (closest gap %.1f px)" % worst)
	touch.layout(main.safe_rect(), true)
