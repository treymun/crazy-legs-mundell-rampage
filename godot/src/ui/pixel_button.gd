## A button of the game's menus as a real Control: it takes focus (arrow
## keys, a pad's stick or d-pad), the pointer (a hover picks it, as the old
## menus did) and touch, and presses on ENTER, a pad's A, a click or a tap.
## It is drawn by its screen's painting layer with `look`, a Callable
## (c: Canvas, active: bool) in screen coordinates, so each screen keeps its
## drawing (Menu's plates and rows) and gains real input.
class_name PixelButton
extends BaseButton

## What the button stands for (a menu entry's id, a row's key).
@export var id := ""
var look: Callable
var paint_layer: Painted
## LEFT and RIGHT on a row that changes a value: called with -1 or 1.
var step: Callable


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	mouse_entered.connect(_hover)


func _hover() -> void:
	if not disabled and get_viewport().gui_get_focus_owner() != self:
		grab_focus()


func _gui_input(event: InputEvent) -> void:
	if not step.is_valid() or not has_focus():
		return
	if event.is_action_pressed("ui_left"):
		step.call(-1)
		accept_event()
	elif event.is_action_pressed("ui_right"):
		step.call(1)
		accept_event()


## Take the focus once the button is shown (a screen picks its button as it
## is built, before its first frame); nothing if it was taken off since.
func grab_when_shown() -> void:
	if is_inside_tree() and is_visible_in_tree():
		grab_focus()
