## ASPECT / SCALING (DISPLAY): the picture's size on a screen, and WIDE's
## columns: the picture as wide as the screen's shape, the 200 rows kept
## (View.cols; docs/dev/view3d.md "ASPECT WIDE").
class_name PictureShape
extends RefCounted

const WIDTH := 320
const HEIGHT := 200
const ASPECT_WIDE := 3
## At most this many columns (32:9 is 712).
const MOST_COLS := 720


## WIDE's columns for a picture filling width x height with square pixels,
## as SQUARE 8:5 shows them: 320 at 8:5 or narrower, 356 at 16:9, 474 at
## 21:9, 712 at 32:9; always even (LOW draws half as many).
static func wide_cols(width: int, height: int) -> int:
	if height <= 0:
		return WIDTH
	return clampi(2 * roundi(100.0 * width / height), WIDTH, MOST_COLS)


## The picture's size in a width x height window: the whole window (FILL),
## the largest of its shape (DOS 4:3, SQUARE 8:5, WIDE) or the largest
## whole multiple (INTEGER 8:5).
static func size_for(width: int, height: int, aspect: int, fill := false) -> PackedInt32Array:
	if fill:
		return PackedInt32Array([width, height])
	if aspect == ASPECT_WIDE:
		var cols := wide_cols(width, height)
		return PackedInt32Array(
			[
				maxi(1, mini(width, height * cols / HEIGHT)),
				maxi(1, mini(height, width * HEIGHT / cols))
			]
		)
	if aspect == 2 and width >= WIDTH and height >= HEIGHT:
		var step := mini(width / WIDTH, height / HEIGHT)
		return PackedInt32Array([WIDTH * step, HEIGHT * step])
	var a := 8 if aspect != 0 else 4
	var b := 5 if aspect != 0 else 3
	return PackedInt32Array(
		[maxi(1, mini(width, height * a / b)), maxi(1, mini(height, width * b / a))]
	)


## WIDE: the overlay, the canvas, the HUD's Controls, the menus and the
## display shader take the picture's new width (from the next frame drawn).
static func fit(m: MainState, cols: int) -> void:
	View.cols = cols
	View.shift = (cols - WIDTH) / 2
	Scope.forget()
	m.palette_material.set_shader_parameter("cols", cols)
	if m.overlay != null:
		m.overlay.size = Vector2i(cols, HEIGHT)
		m.painter.position.x = View.shift
		m.canvas.fit_wide()
	if m.hud_layer != null:
		m.hud_layer.fit()
	if m.ui != null:
		m.ui.position.x = View.shift
