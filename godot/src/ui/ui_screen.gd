## One menu screen as a Control tree (src/ui/screens/): its own drawing and
## its own buttons, which take keys, a pad, the pointer and touch through
## Godot's GUI (UiRoot forwards every event to it). The front end asks UiRoot
## for the screen of its state and leaves that state's drawing and input to it.
class_name UiScreen
extends Control

var main: MainInput
## The layer every part of the screen paints on, in screen coordinates (its
## buttons paint here too, so a menu's helpers draw at their own places).
var paint: Painted


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


## The screen is hidden.
func close() -> void:
	pass


## BACK (ESC, a pad's B): true when the screen dealt with it.
func back() -> bool:
	return false


## Draw what is behind the buttons (called every frame while shown).
func draw_back(_c: Canvas) -> void:
	pass


## A button at `rect` that paints with `look` (c, active) on the screen's
## layer and calls `pressed_do` when pressed.
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
