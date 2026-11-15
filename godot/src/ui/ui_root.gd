## Where the menu screens live: a Control the size of the canvas (320x200)
## inside the UI viewport (the overlay the display shader lays over the view,
## or a viewport of its own in a headless run, so the checks drive the same
## screens). The front end shows the screen of its state here (show()) and
## hands it every input event (take()): touch becomes the pointer, the
## window's coordinates become the canvas's, keys and pads go as they are, so
## Godot's GUI does the focus, hover, clicks and taps.
class_name UiRoot
extends Control

## Front-end state -> screen script.
const SCREENS := {
	"title": preload("res://src/ui/screens/title_screen.gd"),
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
	var screen: UiScreen = _screens.get(state)
	if screen == null:
		screen = (SCREENS[state] as GDScript).new()
		_screens[state] = screen
		add_child(screen)
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
	elif event is InputEventMouse:
		var mouse := (event as InputEventMouse).duplicate() as InputEventMouse
		mouse.position = _to_canvas(mouse.position)
		mouse.global_position = mouse.position
		ev = mouse
	elif event.is_action_pressed("ui_cancel"):
		if _shown.back():
			return true
	holder.push_input(ev, true)
	return true


func _to_canvas(at: Vector2) -> Vector2:
	var rect: Rect2 = main.viewport_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return at
	return (at - rect.position) / rect.size * Vector2(320, 200)
