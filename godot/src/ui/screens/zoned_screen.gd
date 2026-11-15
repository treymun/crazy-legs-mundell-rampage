## A screen drawn by its old pixel drawing, which notes where each tap lands
## (LobbyScreens.zone): the screen is one Control over the whole picture that
## takes the pointer and touch from Godot's GUI and hands each to the screen's
## hover and tap rules (OnlineInput, CountyInput), which press the key the
## place stands for, so the keys stay the screen's rules. Keys and a pad go to
## the front end's handler for the state, as they always did.
class_name ZonedScreen
extends UiScreen


func _init() -> void:
	super._init()
	keys_own = false
	mouse_filter = Control.MOUSE_FILTER_STOP


## Draw the screen on the front end's canvas, noting its tap zones.
func draw_zoned(_c: Canvas) -> void:
	pass


## The pointer is over `at` (picture pixels).
func hover_at(_at: Vector2i) -> void:
	pass


## A tap or left click at `at`.
func tap_at(_at: Vector2i) -> void:
	pass


func render(c: Canvas) -> void:
	draw_zoned(c)


func back() -> bool:
	main.key(KEY_ESCAPE)
	return true


func _gui_input(event: InputEvent) -> void:
	if main == null:
		return
	if event is InputEventMouseMotion:
		hover_at(Vector2i((event as InputEventMouseMotion).position))
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed:
			return
		if button.button_index == MOUSE_BUTTON_LEFT:
			tap_at(Vector2i(button.position))
		elif button.button_index == MOUSE_BUTTON_XBUTTON1:
			back()
	accept_event()
