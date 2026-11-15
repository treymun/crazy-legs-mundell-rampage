## One menu screen as a Control tree (src/ui/screens/): its own drawing and
## its own buttons, which take keys, a pad, the pointer and touch through
## Godot's GUI (UiRoot forwards every event to it). The front end asks UiRoot
## for the screen of its state and leaves that state's drawing and input to it.
##
## A screen built from buttons (TitleScreen, ReplaysScreen...) keeps
## `keys_own` and `pointer_own` on: Godot's focus moves between its buttons
## and presses them. A screen whose rules are its keys (a settings list, a
## form) turns `keys_own` off and the front end's key handler for its state
## runs as before; one that takes the pointer itself overrides pointer().
class_name UiScreen
extends Control

var main: MainInput
## The layer every part of the screen paints on, in screen coordinates (its
## buttons paint here too, so a menu's helpers draw at their own places).
var paint: Painted
## Keys and a pad's buttons (which arrive as keys) go to Godot's focus here.
var keys_own := true
## The pointer and touch go to the screen's controls (UiRoot.take).
var pointer_own := true


func _init() -> void:
	size = Vector2(320, 200)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	paint = ScreenPaint.new()
	paint.size = size
	(paint as ScreenPaint).screen = self
	add_child(paint)


## The screen is shown for `m` (build or refresh what it shows).
func open(m: MainInput) -> void:
	main = m


## The button the front end's selection names (a row, an entry): keys go to
## it, so the focus always follows the selection, whoever moved it (a tool,
## a script, the last screen). Null: leave the focus where it is.
func picked() -> PixelButton:
	return null


## The screen is hidden.
func close() -> void:
	pass


## BACK (ESC, a pad's B): true when the screen dealt with it.
func back() -> bool:
	return false


## Draw what is behind the buttons (called every frame while shown, on the
## screen's own layer).
func draw_back(_c: Canvas) -> void:
	pass


## Draw on the front end's canvas, every frame while shown (main_state.gd
## render): for a screen whose drawing notes where taps land
## (LobbyScreens.zones), which must happen in a headless run too.
func render(_c: Canvas) -> void:
	pass


## A button at `rect` that paints with `look` (c, active) on the screen's
## layer and calls `pressed_do` when pressed. An empty `look` paints nothing:
## draw_back draws the whole screen, from what the focus picked.
func add_button(rect: Rect2i, id: String, look: Callable, pressed_do: Callable) -> PixelButton:
	var b := PixelButton.new()
	b.id = id
	b.position = rect.position
	b.size = rect.size
	b.look = look
	b.paint_layer = paint
	b.pressed.connect(pressed_do)
	add_child(b)
	return b


## A button the keys skip (BACK): the pointer and touch reach it, ESC does
## what it does.
func add_pointer_button(rect: Rect2i, id: String, pressed_do: Callable) -> PixelButton:
	var b := add_button(rect, id, Callable(), pressed_do)
	b.focus_mode = Control.FOCUS_CLICK
	return b


## Up and down walk `buttons` in order, round from the last to the first.
static func chain(buttons: Array[PixelButton]) -> void:
	for i in buttons.size():
		var b := buttons[i]
		var up := buttons[posmod(i - 1, buttons.size())]
		var down := buttons[posmod(i + 1, buttons.size())]
		b.focus_neighbor_top = b.get_path_to(up)
		b.focus_neighbor_bottom = b.get_path_to(down)
		b.focus_neighbor_left = NodePath(".")
		b.focus_neighbor_right = NodePath(".")


## Take every button off the screen (to build them again).
func clear_buttons() -> void:
	for child in get_children():
		if child is PixelButton:
			remove_child(child)
			child.queue_free()


## The screen's painting layer: what is behind, then each button's look in
## tree order (a button paints itself on this layer, not its own).
class ScreenPaint:
	extends Painted

	var screen: UiScreen

	func _ready() -> void:
		super._ready()
		animated = true

	func paint(c: Canvas) -> void:
		screen.draw_back(c)
		for child in screen.get_children():
			if child is PixelButton and (child as PixelButton).visible:
				var b := child as PixelButton
				if b.look.is_valid():
					b.look.call(c, b.has_focus())
