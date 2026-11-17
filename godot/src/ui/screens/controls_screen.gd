## HOW TO RAISE HELL: a tab per controller (keys, pad, touch), its rows, and
## BACK. LEFT and RIGHT (a pad's shoulders arrive as PAGE keys) or a tab
## changes the page; ENTER or BACK goes back.
class_name ControlsScreen
extends UiScreen

const PAGES := MainState.CONTROL_PAGES
const TAB := MainState.CONTROL_TAB

var _back: PixelButton
var _tabs: Array[PixelButton] = []


func open(m: MainInput) -> void:
	super.open(m)
	clear_buttons()
	_tabs.clear()
	for j in PAGES.size():
		var page := j
		var tab := add_button(
			Rect2i(20 + j * TAB, 32, TAB - 2, 13), "tab%d" % j, Callable(), _turn_to.bind(page)
		)
		tab.focus_entered.connect(_turn_to.bind(page))
		_tabs.append(tab)
	for j in _tabs.size():
		var tab := _tabs[j]
		tab.focus_neighbor_left = tab.get_path_to(_tabs[posmod(j - 1, _tabs.size())])
		tab.focus_neighbor_right = tab.get_path_to(_tabs[posmod(j + 1, _tabs.size())])
		tab.focus_neighbor_top = NodePath(".")
		tab.focus_neighbor_bottom = NodePath(".")
	_back = add_pointer_button(Menu.BACK, "back", back)
	_tabs[posmod(main.controls_page, _tabs.size())].call_deferred("grab_when_shown")


func picked() -> PixelButton:
	return _tabs[posmod(main.controls_page, _tabs.size())]


func _turn_to(page: int) -> void:
	if page != main.controls_page:
		main.controls_page = page
		main.sound.play("menu_move")
	if not _tabs[page].has_focus():
		_tabs[page].grab_focus()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or not is_visible_in_tree():
		return
	var turn := 0
	if key.keycode in [KEY_PAGEUP, KEY_A] or (key.keycode == KEY_TAB and key.shift_pressed):
		turn = -1
	elif key.keycode in [KEY_PAGEDOWN, KEY_D, KEY_TAB]:
		turn = 1
	elif key.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		back()
	else:
		return
	if turn != 0:
		_turn_to(posmod(main.controls_page + turn, PAGES.size()))
	get_viewport().set_input_as_handled()


func back() -> bool:
	main.back_to_title()
	return true


func draw_back(c: Canvas) -> void:
	main.menu.draw_sheet(c, "HOW TO RAISE HELL")
	for j in PAGES.size():
		var on := j == main.controls_page
		c.fill_rect(20 + j * TAB, 32, TAB - 2, 13, Menu.RUST if on else Canvas.rgb(48, 34, 26))
		HUD.text(
			c,
			str(PAGES[j][0]),
			19 + j * TAB + TAB / 2,
			35,
			"body",
			HUD.INK if on else Menu.FADED,
			true
		)
	var rows: Array = PAGES[main.controls_page][1]
	# Eleven rows close up a pixel to keep clear of the line at the foot.
	var step := 12 if rows.size() <= 10 else 11
	for i in rows.size():
		var row: Array = rows[i]
		var y := 51 + i * step
		if i % 2 == 0:
			c.fill_rect(19, y - 2, 282, step, Canvas.rgb(33, 23, 19))
		HUD.text(c, str(row[0]), 24, y, "menu", HUD.INK)
		HUD.text(c, str(row[1]), 136, y, "menu", Canvas.rgb(232, 213, 178))
	var other := (
		"LB RB  OTHER CONTROLLERS"
		if main.input_device == "pad"
		else "LEFT / RIGHT  OTHER CONTROLLERS"
	)
	HUD.text(c, other, 24, 181, "mini", Menu.PAINT, false, false)
	Menu.plate_button(c, Menu.BACK, "BACK", _back.has_focus())
