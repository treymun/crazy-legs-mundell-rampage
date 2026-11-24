## SETTINGS by touch alone, headless (pass 14: on the owner's phone the
## browser build's SETTINGS took no finger). Every event goes in the way the
## engine delivers it (Input.parse_input_event, then flushed), with the mouse
## emulation the export has (none, project.godot), and after each finger drag
## the MouseMotion echo the web build makes of the page's pointermove (Godot
## reads pointermove as the mouse, and a finger is a pointer). Fingers are
## numbered as a phone browser may number them (a big Touch.identifier) and,
## for a second pass, as Android does (0, and no echo).
##
##   Godot --headless --path <project> --script res://tools/touch_settings_check.gd
##
## Data-driven over SessionStore.setup_pages(), so a setting added later is
## covered without touching this file: SETTINGS opened by a tap on the
## title; on every page its tab, and a drag that scrolls a list longer than
## its window down and back; every setting scrolled into view by dragging the
## list, picked by a tap and changed: a choice by its arrow, a switch also by a
## second tap on its name, a bar dragged from end to end, a KEYS row tapped
## (it waits for a key; the footer says a keyboard does that) and a tap that
## keeps the old key, a display change answered UNDO and then KEEP, MOVE THEM
## closed with DONE. Then RESET PAGE (tapped twice) puts the page's defaults
## back. A second finger is ignored while the first drives the menu; BACK goes
## to the title. A setting a finger cannot change fails naming its page and
## label. Settings stay in memory (a tool never writes the profile, nor the
## touch layout); check_all gives the run a scratch profile as well.
extends SceneTree

## A finger number as a phone's browser may send it (an iPhone's
## Touch.identifier; Godot's web build passes it on as the index).
const BROWSER_FINGER := 7340
const ANDROID_FINGER := 0

var failures: Array = []
var main
var finger := BROWSER_FINGER
## The browser's pointermove echo of a dragged finger (not on Android).
var echo := true
var _last := Vector2.ZERO


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	var tally := CrashLog.tally()
	print("\nTHE PROJECT")
	_check(
		not bool(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch")),
		"a finger is not also a mouse (emulate_mouse_from_touch off: a tap would click twice)"
	)
	print("\nSETTINGS BY A BROWSER'S FINGER (index %d)" % BROWSER_FINGER)
	finger = BROWSER_FINGER
	await _open_settings()
	await _second_finger()
	var pages := SessionStore.setup_pages()
	for page in pages.size():
		await _page(page)
	await _back()
	print("\nSETTINGS BY ANDROID'S FINGER (index %d)" % ANDROID_FINGER)
	finger = ANDROID_FINGER
	echo = false
	await _open_settings()
	await _android_pass()
	await _back()
	tally.stop()
	_check(
		tally.errors == 0,
		(
			"no script or engine errors"
			+ ("" if tally.errors == 0 else " (%d: %s)" % [tally.errors, tally.first_errors[0]])
		)
	)
	print("")
	print("TOUCH SETTINGS OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
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


## The window's point over the middle of the picture's pixel `p`.
func _at(p: Vector2) -> Vector2:
	var rect: Rect2 = main.viewport_rect()
	return rect.position + (p + Vector2(.5, .5)) * rect.size / Vector2(320, 200)


## A frame of the front end's. Main's own _process is off: the settings
## screen takes each finger as it comes (its rules are all geometry), so only
## another screen needs a frame, drawn, which shows it and puts its focus
## (deferred) as each real frame does.
func _frame() -> void:
	if main.state == "setup" and not main.touch.editing:
		return
	main.render()
	await process_frame


func _send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await _frame()


func _down(p: Vector2, index := -1) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = finger if index < 0 else index
	touch.position = _at(p)
	touch.pressed = true
	_last = touch.position
	await _send(touch)


func _up(p: Vector2, index := -1) -> void:
	var touch := InputEventScreenTouch.new()
	touch.index = finger if index < 0 else index
	touch.position = _at(p)
	touch.pressed = false
	await _send(touch)


## The finger slides to `p`: the drag, then (a browser) the pointermove echo.
func _move(p: Vector2) -> void:
	var drag := InputEventScreenDrag.new()
	drag.index = finger
	drag.position = _at(p)
	drag.relative = drag.position - _last
	_last = drag.position
	Input.parse_input_event(drag)
	if echo:
		var motion := InputEventMouseMotion.new()
		motion.position = drag.position
		motion.global_position = drag.position
		motion.relative = drag.relative
		Input.parse_input_event(motion)
	Input.flush_buffered_events()
	await _frame()


func _tap(p: Vector2) -> void:
	await _down(p)
	await _up(p)


func _drag(from: Vector2, to: Vector2, steps := 8) -> void:
	await _down(from)
	for i in steps:
		await _move(from.lerp(to, float(i + 1) / steps))
	await _up(to)


static func _mid(r: Rect2i) -> Vector2:
	return Vector2(r.position) + Vector2(r.size) * .5


# ---------------------------------------------------------------- settings


func _open_settings() -> void:
	main.state = "title"
	await _frame()
	var items: Array = Menu.title_items(main.entries())
	var spot := Vector2(-1, -1)
	for item: Dictionary in items:
		if str(item["id"]) == "SETUP":
			spot = _mid(item["rect"])
	_check(spot.x >= 0, "the title has SETTINGS")
	await _tap(spot)
	_check(main.state == "setup", "a tap on the title's SETTINGS opens it (%s)" % main.state)
	main.option_page = 0
	main.option_slot = 0
	main.option_scroll = 0
	await process_frame


func _back() -> void:
	await _tap(_mid(Menu.BACK))
	_check(main.state == "title", "BACK by a tap goes to the title (%s)" % main.state)


func _tab(page: int) -> void:
	var count: int = SessionStore.setup_pages().size()
	await _tap(_mid(Menu.tab_rect(page, count)))


## A palm on one row while a thumb taps a tab: the first finger drives the menu.
func _second_finger() -> void:
	var count: int = SessionStore.setup_pages().size()
	var row: Rect2i = Menu.row_rect(0, 1, main.option_scroll)
	var rest := Vector2(row.position.x + 20, row.position.y + Menu.SET_ROW / 2)
	await _down(rest)
	var other := finger + 1
	await _down(_mid(Menu.tab_rect(1, count)), other)
	await _up(_mid(Menu.tab_rect(1, count)), other)
	_check(main.option_page == 0, "a second finger's tap is ignored while the first is down")
	await _up(rest)
	_check(main.option_slot == 1, "the first finger's tap still counts when it lifts")


func _page(page: int) -> void:
	var pages := SessionStore.setup_pages()
	var page_name := str(pages[page][0])
	await _tab(page)
	_check(main.option_page == page, "%s: its tab by a tap" % page_name)
	if main.option_page != page:
		return
	if Menu.max_scroll(page) > 0:
		await _scroll_by(2)
		var went: int = main.option_scroll
		await _scroll_by(-2)
		_check(
			went > 0 and main.option_scroll == 0,
			(
				"%s: a finger dragging the list scrolls it down and back (%d, %d)"
				% [page_name, went, main.option_scroll]
			)
		)
	var items: Array = pages[page][1]
	var bad: Array[String] = []
	for slot in items.size():
		var item: SessionStore.Setting = items[slot]
		var why: String = await _setting(page, slot, item)
		if why != "":
			bad.append("%s / %s (%s): %s" % [page_name, item.label, item.key, why])
	for line in bad:
		_check(false, "SETTING " + line)
	_check(bad.is_empty(), "%s: all %d settings changed by touch" % [page_name, items.size()])
	await _tap(_mid(Menu.RESET))
	await _tap(_mid(Menu.RESET))
	var kept: Array[String] = []
	for raw: SessionStore.Setting in items:
		var value: int = main.options[raw.key]
		if value != raw.default_value:
			kept.append(raw.label)
	_check(
		kept.is_empty(), "%s: RESET PAGE tapped twice puts the defaults back %s" % [page_name, kept]
	)


## Drag the list by `rows` rows (positive: the list moves up, showing rows below).
func _scroll_by(rows: int) -> void:
	var x := Menu.LIST.position.x + 60
	var from := Menu.LIST.position.y + Menu.LIST.size.y / 2 + rows * Menu.SET_ROW / 2
	var to := from - rows * Menu.SET_ROW - signi(rows) * 6
	await _drag(Vector2(x, from), Vector2(x, to), 6)


## Scroll `slot`'s row into the window by dragging the list.
func _into_view(page: int, slot: int) -> bool:
	for _try in 20:
		if Menu.row_rect(page, slot, main.option_scroll).size.y > 0:
			return true
		var shown: Array = Menu.shown_rows(page, main.option_scroll)
		var first: int = shown[0][0] if not shown.is_empty() else 0
		await _scroll_by(2 if slot > first else -2)
	return Menu.row_rect(page, slot, main.option_scroll).size.y > 0


## Pick and change one setting by touch; "" when it worked, else why not.
func _setting(page: int, slot: int, item: SessionStore.Setting) -> String:
	if not await _into_view(page, slot):
		return "a drag cannot scroll it into view"
	var row: Rect2i = Menu.row_rect(page, slot, main.option_scroll)
	var label := Vector2(row.position.x + 20, row.position.y + Menu.SET_ROW / 2)
	await _tap(label)
	if main.option_slot != slot:
		return "a tap on its name does not pick it"
	var before: int = main.options[item.key]
	if item is SessionStore.KeySetting:
		var action := (item as SessionStore.KeySetting).action
		if main.binding_action != action:
			return "a tap does not ready it for a key"
		if not str(main.menu_note).contains("A TAP KEEPS"):
			return "it does not say a tap keeps the old key (%s)" % main.menu_note
		await _tap(label)
		if main.binding_action != "" or int(main.options[item.key]) != before:
			return "a second tap does not keep the old key"
		return ""
	if Menu.is_bar(item):
		return await _slide(page, slot, item, row)
	if Menu.is_toggle(item):
		await _tap(label)
		if int(main.options[item.key]) == before:
			return "a second tap on its name does not flip it"
		before = main.options[item.key]
	var arrow := _arrow(page, row)
	if arrow.x < 0:
		return "no arrow to tap"
	await _tap(arrow)
	if int(main.options[item.key]) == before:
		return "a tap on its arrow does not change it"
	if not main.display_trial.is_empty():
		var why: String = await _trial(item, before, arrow)
		if why != "":
			return why
	if item.choices.has("MOVE THEM"):
		# Stepped round to MOVE THEM, the touch buttons' editor comes up.
		for _step in item.choices.size():
			if not main.touch.editing:
				await _tap(arrow)
		if not main.touch.editing:
			return "stepping it to MOVE THEM does not bring up the editor"
	if main.touch.editing:
		await _done_moving()
		if main.touch.editing:
			return "MOVE THEM's DONE does not close it"
	return ""


## The right arrow of a choice row: the right-most point that steps it up.
func _arrow(page: int, row: Rect2i) -> Vector2:
	var y := row.position.y + Menu.SET_ROW / 2
	for x in range(row.end.x - 1, Menu.VALUE_X - 3, -1):
		var hit: Dictionary = Menu.setup_hit(x, y, page, main.option_scroll)
		if str(hit["kind"]) == "row" and int(hit["direction"]) == 1 and not bool(hit["bar"]):
			return Vector2(x, y)
	return Vector2(-1, -1)


## A level's bar: a finger set down at its left end slides to its right end,
## the value following the whole way (the browser's echo must not stop it).
func _slide(page: int, slot: int, item: SessionStore.Setting, row: Rect2i) -> String:
	var shape := Menu.bar_shape(item)
	var left := int(shape[0])
	var span := int(shape[2]) * (int(shape[1]) + 1) - 1
	var y := row.position.y + Menu.SET_ROW / 2
	var hit: Dictionary = Menu.setup_hit(left + 1, y, page, main.option_scroll)
	if not bool(hit["bar"]):
		return "its bar is not where a finger finds it"
	var from := Vector2(left, y)
	var to := Vector2(left + span - 1, y)
	await _down(from)
	if int(main.options[item.key]) != item.low:
		await _up(from)
		return "a finger set on its bar's left end does not set the lowest value"
	var steps := 8
	var followed := true
	for i in steps:
		var p := from.lerp(to, float(i + 1) / steps)
		await _move(p)
		var want := Menu.bar_value(item, int(_picture(p).x))
		if int(main.options[item.key]) != want:
			followed = false
	await _up(to)
	if main.option_slot != slot:
		return "sliding its bar picked another row"
	if not followed:
		return "its bar does not follow a dragged finger"
	if int(main.options[item.key]) != item.high:
		return "dragged to its right end it is not the highest value (%d)" % main.options[item.key]
	return ""


## A picture point back from a window point the way the game reads it.
func _picture(p: Vector2) -> Vector2i:
	return main.picture_point(_at(p))


## A display change waits for KEEP or UNDO: UNDO by a tap puts it back, then
## the same change again and KEEP by a tap keeps it.
func _trial(item: SessionStore.Setting, before: int, arrow: Vector2) -> String:
	await _tap(_mid(Menu.CONFIRM_UNDO))
	if not main.display_trial.is_empty() or int(main.options[item.key]) != before:
		return "a tap on UNDO does not put the display back"
	await _tap(arrow)
	var changed: int = main.options[item.key]
	if main.display_trial.is_empty() or changed == before:
		return "the second tap on its arrow does not change it again"
	await _tap(_mid(Menu.CONFIRM_KEEP))
	if not main.display_trial.is_empty() or int(main.options[item.key]) != changed:
		return "a tap on KEEP does not keep the display"
	return ""


## MOVE THEM is up over the settings: a button dragged by a finger, then DONE.
func _done_moving() -> void:
	var touch: TouchControls = main.touch
	var alt: Array = []
	for button: Array in touch.buttons:
		if str(button[0]) == "alt":
			alt = button
	if not alt.is_empty():
		var start: Vector2 = alt[1]
		var press := InputEventScreenTouch.new()
		press.index = finger
		press.position = start
		press.pressed = true
		await _send(press)
		var drag := InputEventScreenDrag.new()
		drag.index = finger
		drag.position = start + Vector2(-40, 30)
		drag.relative = Vector2(-40, 30)
		await _send(drag)
		press = press.duplicate() as InputEventScreenTouch
		press.pressed = false
		press.position = drag.position
		await _send(press)
		var moved: Vector2 = touch.custom.get("alt", Vector2(-1, -1))
		_check(moved.x >= 0, "MOVE THEM: a finger drags ALT to a new place")
	var done: Rect2 = touch.get("_done_rect")
	var tap := InputEventScreenTouch.new()
	tap.index = finger
	tap.position = done.get_center()
	tap.pressed = true
	await _send(tap)
	tap = tap.duplicate() as InputEventScreenTouch
	tap.pressed = false
	await _send(tap)


## Android numbers the first finger 0: a tab, a bar slid and a choice stepped.
func _android_pass() -> void:
	var pages := SessionStore.setup_pages()
	for page in pages.size():
		var items: Array = pages[page][1]
		var bar := -1
		var choice := -1
		for slot in items.size():
			var item: SessionStore.Setting = items[slot]
			if bar < 0 and Menu.is_bar(item):
				bar = slot
			if choice < 0 and not item.choices.is_empty() and not _trial_key(item.key):
				choice = slot
		await _tab(page)
		_check(main.option_page == page, "%s: its tab by a tap" % pages[page][0])
		for slot: int in [bar, choice]:
			if slot < 0:
				continue
			var item: SessionStore.Setting = items[slot]
			var why: String = await _setting(page, slot, item)
			_check(why == "", "%s / %s by touch %s" % [pages[page][0], item.label, why])


static func _trial_key(key: String) -> bool:
	return key == "window_mode" or key == "aspect" or key == "touch_layout"
