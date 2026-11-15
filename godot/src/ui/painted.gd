## A Control that paints itself with the game's own pixel drawing (Canvas:
## rectangles, pixel letters, pictures, the menus' and HUD's helpers), so a
## screen built from Control nodes looks exactly as the hand-drawn one did.
## Everything is drawn in the control's own coordinates, a canvas pixel per
## unit, inside the 320x200 UI viewport. Override paint(); call repaint()
## when what it shows changes (or set `animated` to repaint every frame).
class_name Painted
extends Control

## Repaint every frame (a lamp that flickers, bulbs that chase).
@export var animated := false
var canvas: Canvas
var _dirty := true


func _ready() -> void:
	canvas = Canvas.new()
	canvas.gpu = true
	canvas.gpu_parent = get_canvas_item()
	# Decoration lets the pointer through to the buttons under and over it.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(repaint)
	visibility_changed.connect(repaint)


func _exit_tree() -> void:
	if canvas != null:
		canvas.gpu_free()


func repaint() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if canvas == null or not is_visible_in_tree():
		return
	if _dirty or animated:
		_dirty = false
		canvas.gpu_begin()
		paint(canvas)


## Draw the control on `c` (0, 0 is its top left).
func paint(_c: Canvas) -> void:
	pass
