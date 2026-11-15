## Where the menu screens live: a Control the size of the canvas (320x200)
## inside the UI viewport (the overlay the display shader lays over the view,
## or a viewport of its own in a headless run, so the checks drive the same
## screens). The front end shows the screen of its state here (show()) and
## hands it every input event (take()): touch becomes the pointer, the
## window's coordinates become the canvas's, keys and pads go as they are, so
## Godot's GUI does the focus, hover, clicks and taps.
class_name UiRoot
extends Control

const _TITLE_SCREEN := preload("res://src/ui/screens/title_screen.gd")
const _REPLAYS_SCREEN := preload("res://src/ui/screens/replays_screen.gd")
const _REMATCH_SCREEN := preload("res://src/ui/screens/rematch_screen.gd")
const _REMATCH_DONE_SCREEN := preload("res://src/ui/screens/rematch_done_screen.gd")
const _CONTROLS_SCREEN := preload("res://src/ui/screens/controls_screen.gd")
const _CREDITS_SCREEN := preload("res://src/ui/screens/credits_screen.gd")
const _KEYED_SCREEN := preload("res://src/ui/screens/keyed_screen.gd")
const _COUNTY_MAPS_SCREEN := preload("res://src/ui/screens/county_maps_screen.gd")
const _ONLINE_SCREEN := preload("res://src/ui/screens/online_screen.gd")
## Front-end state -> screen script.
const SCREENS := {
	"title": _TITLE_SCREEN,
	"replays": _REPLAYS_SCREEN,
	"rematch": _REMATCH_SCREEN,
	"rematch_done": _REMATCH_DONE_SCREEN,
	"controls": _CONTROLS_SCREEN,
	"credits": _CREDITS_SCREEN,
	"setup": _KEYED_SCREEN,
	"slots": _KEYED_SCREEN,
	"county": _COUNTY_MAPS_SCREEN,
	"multi": _ONLINE_SCREEN,
	"showdown": _ONLINE_SCREEN,
	"servers": _ONLINE_SCREEN,
	"nethost": _ONLINE_SCREEN,
	"netjoin": _ONLINE_SCREEN,
	"lobby": _ONLINE_SCREEN,
	"lobbyset": _ONLINE_SCREEN,
}

var main: MainInput
var holder: SubViewport
var _screens: Dictionary = {}
var _shown: UiScreen
var _shown_state := ""


func _init(m: MainInput, viewport: SubViewport) -> void:
	main = m
	size = Vector2(320, 200)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.get_theme()
	holder = viewport
	if holder == null:
		# Headless: a viewport of its own that nothing shows.
		holder = SubViewport.new()
		holder.size = Vector2i(320, 200)
		holder.disable_3d = true
		holder.render_target_update_mode = SubViewport.UPDATE_DISABLED
		holder.gui_disable_input = false
		main.add_child(holder)
	holder.add_child(self)


## Whether `state` has a screen here.
func handles(state: String) -> bool:
	return SCREENS.has(state)


## The screen shown now (null when the state draws itself the old way).
func shown() -> UiScreen:
	return _shown


## The screen of `state` (made the first time; null when it has none).
func screen_for(state: String) -> UiScreen:
	if not SCREENS.has(state):
		return null
	var screen: UiScreen = _screens.get(state)
	if screen == null:
		screen = (SCREENS[state] as GDScript).new()
		screen.visible = false
		_screens[state] = screen
		add_child(screen)
	return screen


## Whether keys on `state`'s screen go to its controls (else to the front
## end's handler for the state).
func takes_keys(state: String) -> bool:
	var screen := screen_for(state)
	return screen != null and screen.keys_own


## Whether the pointer and touch on `state`'s screen go to its controls.
func takes_pointer(state: String) -> bool:
	var screen := screen_for(state)
	return screen != null and screen.pointer_own


## Show the screen of `state` (true), or none when it has no screen (false).
func show_state(state: String) -> bool:
	if state == _shown_state and _shown != null:
		return true
	if _shown != null:
		_shown.close()
		_shown.visible = false
		_shown = null
	_shown_state = state
	if not SCREENS.has(state):
		return false
	var screen := screen_for(state)
	screen.visible = true
	_shown = screen
	screen.open(main)
	return true


## Hand an input event to the screen shown: true when it took it. Positions
## go from the window's pixels to the canvas's; a finger is the pointer.
func take(event: InputEvent) -> bool:
	if _shown == null:
		return false
	var ev := event
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = touch.pressed
		click.position = _to_canvas(touch.position)
		click.global_position = click.position
		# The pointer comes to the finger first, so the button under it is
		# the one hovered and picked.
		var move := InputEventMouseMotion.new()
		move.position = click.position
		move.global_position = click.position
		holder.push_input(move, true)
		ev = click
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		var motion := InputEventMouseMotion.new()
		motion.position = _to_canvas(drag.position)
		motion.global_position = motion.position
		motion.relative = drag.relative
		ev = motion
	elif _wheel_step(event) != 0 and _shown.keys_own:
		var arrow := InputEventKey.new()
		arrow.keycode = KEY_UP if _wheel_step(event) < 0 else KEY_DOWN
		arrow.physical_keycode = arrow.keycode
		for down: bool in [true, false]:
			var press := arrow.duplicate() as InputEventKey
			press.pressed = down
			holder.push_input(press, true)
		return true
	elif event is InputEventMouse:
		var mouse := (event as InputEventMouse).duplicate() as InputEventMouse
		mouse.position = _to_canvas(mouse.position)
		mouse.global_position = mouse.position
		ev = mouse
	elif event.is_action_pressed("ui_cancel"):
		if _shown.back():
			return true
	if event is InputEventKey:
		_follow_selection()
	if (
		ev is InputEventMouseButton
		and (ev as InputEventMouseButton).pressed
		and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_XBUTTON1
		and not _shown is ZonedScreen
	):
		# The mouse's back button goes back on every menu.
		_shown.back()
		return true
	holder.push_input(ev, true)
	return true


## Put the focus on the button the front end's selection names, unless the
## pointer has it on a button the keys skip (BACK: ENTER presses that).
func _follow_selection() -> void:
	var want := _shown.picked()
	if want == null or not want.is_inside_tree():
		return
	var owner := holder.gui_get_focus_owner()
	if owner == want:
		return
	if owner is PixelButton and owner.get_parent() == _shown and owner.focus_mode == FOCUS_CLICK:
		return
	want.grab_focus()


## -1 for the wheel turned up, 1 down, 0 for anything else.
static func _wheel_step(event: InputEvent) -> int:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return 0
	if button.button_index == MOUSE_BUTTON_WHEEL_UP:
		return -1
	if button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		return 1
	return 0


func _to_canvas(at: Vector2) -> Vector2:
	var rect: Rect2 = main.viewport_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return at
	return (at - rect.position) / rect.size * Vector2(320, 200)
