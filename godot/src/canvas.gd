## RGB8 drawing surface for menus, HUD and lettering.
##
## The software renderer owns the view rows; everything here mirrors the
## pygame draw calls the reference makes into its 320x200 canvas (plain rects,
## lines, circles and alpha blits of the art sheets). Small offscreen canvases
## (the 12x6 cartridge tokens) pass their own size to `_init`.
class_name Canvas
extends RefCounted

const WIDTH := 320
const HEIGHT := 200
const TAU_ := 6.283185307179586

const FACE := Color(0.15686275, 0.11372549, 0.09019608)
const EDGE := Color(0.55294118, 0.4, 0.25490196)
const DROP := Color(0.08627451, 0.0627451, 0.05098039)
const UNDERLINE := Color(0.30980393, 0.20784314, 0.14901961)

var pixels := PackedByteArray()
var w := WIDTH
var h := HEIGHT
## Offscreen icon canvases (the 12x6 cartridge tokens) need to know which
## pixels were actually painted, because the reference blits them with alpha.
var use_mask := false
var mask := PackedByteArray()
## Layer mode, for the display shader: the game view is not in `pixels` (the
## graphics card composes it), so the surface starts empty and `cover` records
## how much of each pixel has been painted over (0 nothing, 255 all of it).
## Blends keep working on `pixels` unchanged because an empty pixel is black.
var layer := false
var cover := PackedByteArray()
static var _blank := PackedByteArray()
static var _blank_cover := PackedByteArray()

## Godot 2D mode (main.gd turns it on for the window's canvas). Drawing calls
## become Godot canvas commands on items inside a 320x200 viewport instead of
## writes to `pixels`, and the viewport goes to the display shader over the
## view. Every shape still comes down to the same pixels, spans and
## rectangles as in software (set_pixel, _hspan, _vspan, fill_rect), so the
## pictures are the same; letters are cached glyph textures and pictures are
## cached textures. `pixels` then only carries a software-drawn game view, if
## any. Small offscreen canvases (icons, the status bar) stay in software.
var gpu := false
var gpu_parent := RID()
## Set when `pixels` holds a software-drawn game view this frame.
var base_set := false
var _items: Array[RID] = []
var _item_kinds := PackedInt32Array()
var _items_used := 0
var _item := RID()
const ITEM_NORMAL := 0
const ITEM_ADD := 1
const ITEM_NORMAL_VIEW := 2
const ITEM_ADD_VIEW := 3
static var _add_material: ShaderMaterial
static var _textures := {}
static var _glyphs := {}


## Start a frame's drawing: forget last frame's commands.
func gpu_begin() -> void:
	for i in _items_used:
		RenderingServer.canvas_item_clear(_items[i])
	_items_used = 0
	gpu_item(ITEM_NORMAL)


## Go on drawing on a new item above everything drawn so far: ITEM_ADD adds
## its light to what is under it instead of covering it (muzzle flashes);
## the _VIEW kinds are clipped to the view rows.
func gpu_item(kind: int) -> void:
	if _items_used == _items.size():
		var made := RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(made, gpu_parent)
		_items.append(made)
		_item_kinds.append(-1)
	var item := _items[_items_used]
	if _item_kinds[_items_used] != kind:
		_item_kinds[_items_used] = kind
		var adds := kind == ITEM_ADD or kind == ITEM_ADD_VIEW
		if adds and _add_material == null:
			var shader := Shader.new()
			shader.code = (
				"shader_type canvas_item;\nrender_mode blend_premul_alpha;\n"
				+ "void fragment() {\n\tvec4 t = texture(TEXTURE, UV) * COLOR;\n"
				+ "\tCOLOR = vec4(t.rgb * t.a, 0.0);\n}\n"
			)
			_add_material = ShaderMaterial.new()
			_add_material.shader = shader
		RenderingServer.canvas_item_set_material(item, _add_material.get_rid() if adds else RID())
		var clipped := kind == ITEM_NORMAL_VIEW or kind == ITEM_ADD_VIEW
		RenderingServer.canvas_item_set_clip(item, clipped)
		RenderingServer.canvas_item_set_custom_rect(item, clipped, Rect2(0, 0, WIDTH, 156))
	RenderingServer.canvas_item_set_draw_index(item, _items_used)
	_items_used += 1
	_item = item


func _gpu_rect(x: int, y: int, box_w: int, box_h: int, r: int, g: int, b: int) -> void:
	RenderingServer.canvas_item_add_rect(_item, Rect2(x, y, box_w, box_h), Color8(r, g, b))


## A cached texture for a picture, by a name that stands for its contents.
static func texture(key: String, data: PackedByteArray, img_w: int, img_h: int) -> ImageTexture:
	var made: ImageTexture = _textures.get(key)
	if made == null:
		if _textures.size() > 600:
			_textures.clear()
		made = ImageTexture.create_from_image(
			Image.create_from_data(img_w, img_h, false, Image.FORMAT_RGBA8, data)
		)
		_textures[key] = made
	return made


## Draw a cached texture scaled to tw x th, its alpha scaled by `alpha`.
func gpu_texture(made: Texture2D, x: int, y: int, tw: int, th: int, alpha := 255) -> void:
	RenderingServer.canvas_item_add_texture_rect(
		_item, Rect2(x, y, tw, th), made.get_rid(), false, Color(1, 1, 1, alpha / 255.0)
	)


static func _glyph_texture(char: String, mini: bool, sx: int, height: int) -> Array:
	var key := (char.unicode_at(0) << 16) | (int(mini) << 15) | (sx << 8) | height
	var kept = _glyphs.get(key)
	if kept != null:
		return kept
	var info := PixelType.glyph(char, mini)
	var rows: Array = info[0]
	var glyph_w: int = info[1]
	var n := rows.size()
	var image := Image.create_empty(
		maxi(1, glyph_w * sx), maxi(1, height), false, Image.FORMAT_RGBA8
	)
	for yi in n:
		var bits: int = rows[yi]
		for col in glyph_w:
			if bits & (1 << (glyph_w - col - 1)):
				for yy in range(yi * height / n, (yi + 1) * height / n):
					for xx in sx:
						image.set_pixel(col * sx + xx, yy, Color(1, 1, 1, 1))
	kept = [ImageTexture.create_from_image(image), glyph_w]
	_glyphs[key] = kept
	return kept


## Start an empty 320x200 layer: nothing over the view, the status rows solid.
func begin_layer() -> void:
	if gpu:
		# The viewport starts each frame empty; its alpha is the coverage.
		layer = true
		return
	if _blank.is_empty():
		_blank.resize(WIDTH * HEIGHT * 3)
		_blank.fill(0)
		_blank_cover.resize(WIDTH * HEIGHT)
		_blank_cover.fill(255)
		for i in WIDTH * 156:
			_blank_cover[i] = 0
	w = WIDTH
	h = HEIGHT
	pixels = _blank.duplicate()
	cover = _blank_cover.duplicate()
	layer = true


## Turn on coverage tracking for a small offscreen surface.
func enable_mask() -> void:
	use_mask = true
	mask.resize(w * h)
	mask.fill(0)


func _init(pw := WIDTH, ph := HEIGHT) -> void:
	w = pw
	h = ph
	pixels.resize(pw * ph * 3)


static func rgb(r: int, g: int, b: int) -> Color:
	return Color(r / 255.0, g / 255.0, b / 255.0)


## Reallocate for a differently sized surface (the small icon canvases).
func resize(pw: int, ph: int) -> void:
	w = pw
	h = ph
	pixels.resize(pw * ph * 3)
	if use_mask:
		mask.resize(pw * ph)
		mask.fill(0)


func clear(r: int, g: int, b: int) -> void:
	if gpu:
		_gpu_rect(0, 0, w, h, r, g, b)
		return
	var n := w * h
	var i := 0
	for _i in n:
		pixels[i] = r
		pixels[i + 1] = g
		pixels[i + 2] = b
		i += 3
	if layer:
		cover.fill(255)


func set_pixel(x: int, y: int, r: int, g: int, b: int) -> void:
	if x < 0 or y < 0 or x >= w or y >= h:
		return
	if gpu:
		_gpu_rect(x, y, 1, 1, r, g, b)
		return
	var o := (y * w + x) * 3
	pixels[o] = r
	pixels[o + 1] = g
	pixels[o + 2] = b
	if use_mask:
		mask[y * w + x] = 1
	if layer:
		cover[y * w + x] = 255


func get_r(x: int, y: int) -> int:
	return pixels[(y * w + x) * 3]


## RGBA view of the surface: painted pixels are opaque, the rest transparent.
## This mirrors blitting an SRCALPHA pygame surface into the frame.
func to_rgba() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(w * h * 4)
	for i in w * h:
		out[i * 4] = pixels[i * 3]
		out[i * 4 + 1] = pixels[i * 3 + 1]
		out[i * 4 + 2] = pixels[i * 3 + 2]
		out[i * 4 + 3] = (
			255
			if (use_mask and mask[i]) or not use_mask
			else (255 if pixels[i * 3] or pixels[i * 3 + 1] or pixels[i * 3 + 2] else 0)
		)
	return out


func fill_rect(x: int, y: int, box_w: int, box_h: int, c: Color) -> void:
	var x0 := maxi(0, x)
	var y0 := maxi(0, y)
	var x1 := mini(w, x + box_w)
	var y1 := mini(h, y + box_h)
	if x0 >= x1 or y0 >= y1:
		return
	var r := roundi(c.r * 255.0)
	var g := roundi(c.g * 255.0)
	var b := roundi(c.b * 255.0)
	if gpu:
		_gpu_rect(x0, y0, x1 - x0, y1 - y0, r, g, b)
		return
	var row := PackedByteArray()
	row.resize((x1 - x0) * 3)
	var i := 0
	for _xx in range(x0, x1):
		row[i] = r
		row[i + 1] = g
		row[i + 2] = b
		i += 3
	var span := row.size()
	for yy in range(y0, y1):
		var o := (yy * w + x0) * 3
		for k in span:
			pixels[o + k] = row[k]
		if use_mask:
			for xx in range(x0, x1):
				mask[yy * w + xx] = 1
		if layer:
			for xx in range(x0, x1):
				cover[yy * w + xx] = 255


## Hollow 1px rectangle, matching pygame.draw.rect(..., 1).
func rect_outline(x: int, y: int, box_w: int, box_h: int, c: Color) -> void:
	fill_rect(x, y, box_w, 1, c)
	fill_rect(x, y + box_h - 1, box_w, 1, c)
	fill_rect(x, y, 1, box_h, c)
	fill_rect(x + box_w - 1, y, 1, box_h, c)


## pygame.draw.line, pixel for pixel (checked against pygame-ce 2.5.8 on random
## lines at widths 1-3): the same Bresenham stepping, and for a wider line the
## same one-axis thickening. A width-2 line that runs mostly sideways covers
## rows y and y+1; one that runs mostly up and down covers columns x and x+1.
func line(x0: int, y0: int, x1: int, y1: int, c: Color, width := 1) -> void:
	var dx := absi(x1 - x0)
	var dy := absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := (dx if dx > dy else -dy) / 2
	var r := roundi(c.r * 255.0)
	var g := roundi(c.g * 255.0)
	var b := roundi(c.b * 255.0)
	if width <= 1:
		while x0 != x1 or y0 != y1:
			set_pixel(x0, y0, r, g, b)
			var e1 := err
			if e1 > -dx:
				err -= dy
				x0 += sx
			if e1 < dy:
				err += dx
				y0 += sy
		set_pixel(x1, y1, r, g, b)
		return
	var half := width / 2
	var extra := 1 - (width % 2)
	var span := half * 2 + 1 - extra
	var steep := dx <= dy
	while true:
		if steep:
			fill_rect(x0 - half + extra, y0, span, 1, c)
		else:
			fill_rect(x0, y0 - half + extra, 1, span, c)
		if x0 == x1 and y0 == y1:
			break
		var e2 := err
		if e2 > -dx:
			err -= dy
			x0 += sx
		if e2 < dy:
			err += dx
			y0 += sy


func circle(cx: int, cy: int, radius: int, c: Color, filled := true, width := 0) -> void:
	var r := roundi(c.r * 255.0)
	var g := roundi(c.g * 255.0)
	var b := roundi(c.b * 255.0)
	if filled and width <= 0:
		_circle_filled(cx, cy, radius, r, g, b)
	elif width > 1:
		_circle_thick(cx, cy, radius, width, r, g, b)
	else:
		_circle_thin(cx, cy, radius, r, g, b)


## pygame draw_circle_filled: Bresenham with horizontal spans, x0+x-1 convention.
func _circle_filled(x0: int, y0: int, radius: int, r: int, g: int, b: int) -> void:
	if radius < 0:
		return
	var f := 1 - radius
	var ddf_x := 0
	var ddf_y := -2 * radius
	var x := 0
	var y := radius
	while x < y:
		if f >= 0:
			y -= 1
			ddf_y += 2
			f += ddf_y
		x += 1
		ddf_x += 2
		f += ddf_x + 1
		if f >= 0:
			_hspan(x0 - x, y0 + y - 1, x0 + x - 1, r, g, b)
			_hspan(x0 - x, y0 - y, x0 + x - 1, r, g, b)
		_hspan(x0 - y, y0 + x - 1, x0 + y - 1, r, g, b)
		_hspan(x0 - y, y0 - x, x0 + y - 1, r, g, b)


## pygame draw_circle_bresenham_thin: eight symmetric single pixels.
func _circle_thin(x0: int, y0: int, radius: int, r: int, g: int, b: int) -> void:
	var f := 1 - radius
	var ddf_x := 0
	var ddf_y := -2 * radius
	var x := 0
	var y := radius
	while x < y:
		if f >= 0:
			y -= 1
			ddf_y += 2
			f += ddf_y
		x += 1
		ddf_x += 2
		f += ddf_x + 1
		set_pixel(x0 + x - 1, y0 + y - 1, r, g, b)
		set_pixel(x0 - x, y0 + y - 1, r, g, b)
		set_pixel(x0 + x - 1, y0 - y, r, g, b)
		set_pixel(x0 - x, y0 - y, r, g, b)
		set_pixel(x0 + y - 1, y0 + x - 1, r, g, b)
		set_pixel(x0 + y - 1, y0 - x, r, g, b)
		set_pixel(x0 - y, y0 + x - 1, r, g, b)
		set_pixel(x0 - y, y0 - x, r, g, b)


## pygame draw_circle_bresenham: two-pass midpoint ring with an inner edge.
func _circle_thick(x0: int, y0: int, radius: int, thickness: int, r: int, g: int, b: int) -> void:
	var x := 0
	var y := radius
	var rs := radius * radius
	var drs := 2 * rs
	var d1 := float(rs) * (1.25 - (radius + 0.0))
	var dx := 0
	var dy := drs * y
	var line := true
	var ri := radius - thickness + 1
	var x_in := 0
	var y_in := ri
	var ri2 := ri * ri
	var dri2 := 2 * ri2
	var d1_in := float(ri2) * (1.25 - (ri + 0.0))
	var d2_in := 0.0
	var dx_in := 0
	var dy_in := dri2 * y_in
	while dx < dy:
		while d1 < 0:
			x += 1
			dx += drs
			d1 += dx + rs
		if line:
			_hspan(x0 - x, y0 - y, x0 + x - 1, r, g, b)
			_hspan(x0 - x, y0 + y - 1, x0 + x - 1, r, g, b)
		else:
			_hspan(x0 - x, y0 - y, x0 - x_in, r, g, b)
			_hspan(x0 - x, y0 + y - 1, x0 - x_in, r, g, b)
			_hspan(x0 + x_in - 1, y0 - y, x0 + x - 1, r, g, b)
			_hspan(x0 + x_in - 1, y0 + y - 1, x0 + x - 1, r, g, b)
		x += 1
		y -= 1
		dx += drs
		dy -= drs
		d1 += dx - dy + rs
		if line and y < ri:
			line = false
		if not line:
			while d1_in < 0:
				x_in += 1
				dx_in += dri2
				d1_in += dx_in + ri2
			x_in += 1
			y_in -= 1
			dx_in += dri2
			dy_in -= dri2
			d1_in += dx_in - dy_in + ri2
	d1 = float(rs) * ((x + 0.5) * (x + 0.5) + (y - 1.0) * (y - 1.0) - rs)
	while y >= 0:
		if line:
			_hspan(x0 - x, y0 - y, x0 + x - 1, r, g, b)
			_hspan(x0 - x, y0 + y - 1, x0 + x - 1, r, g, b)
		else:
			_hspan(x0 - x, y0 - y, x0 - x_in, r, g, b)
			_hspan(x0 - x, y0 + y - 1, x0 - x_in, r, g, b)
			_hspan(x0 + x_in - 1, y0 - y, x0 + x - 1, r, g, b)
			_hspan(x0 + x_in - 1, y0 + y - 1, x0 + x - 1, r, g, b)
		if d1 > 0:
			y -= 1
			dy -= drs
			d1 += rs - dy
		else:
			y -= 1
			x += 1
			dx += drs
			dy -= drs
			d1 += dx - dy + rs
		if line and y < ri:
			line = false
		if not line:
			if dx_in < dy_in:
				while d1_in < 0:
					x_in += 1
					dx_in += dri2
					d1_in += dx_in + ri2
				x_in += 1
				y_in -= 1
				dx_in += dri2
				dy_in -= dri2
				d1_in += dx_in - dy_in + ri2
			else:
				if d2_in == 0.0:
					d2_in = (
						float(ri2)
						* ((x_in + 0.5) * (x_in + 0.5) + (y_in - 1.0) * (y_in - 1.0) - ri2)
					)
				if d2_in > 0:
					y_in -= 1
					dy_in -= dri2
					d2_in += ri2 - dy_in
				else:
					y_in -= 1
					x_in += 1
					dx_in += dri2
					dy_in -= dri2
					d2_in += dx_in - dy_in + ri2


func _hspan(x0: int, y: int, x1: int, r: int, g: int, b: int) -> void:
	if y < 0 or y >= h:
		return
	var lo := mini(x0, x1)
	var hi := maxi(x0, x1)
	lo = maxi(0, lo)
	hi = mini(w - 1, hi)
	if lo > hi:
		return
	if gpu:
		_gpu_rect(lo, y, hi - lo + 1, 1, r, g, b)
		return
	var o := (y * w + lo) * 3
	for _x in range(lo, hi + 1):
		pixels[o] = r
		pixels[o + 1] = g
		pixels[o + 2] = b
		if use_mask:
			mask[y * w + _x] = 1
		if layer:
			cover[y * w + _x] = 255
		o += 3


## pygame draw.ellipse: filled uses the midpoint ellipse with an x/y offset parity.
func ellipse(x0: int, y0: int, box_w: int, box_h: int, c: Color) -> void:
	var r := roundi(c.r * 255.0)
	var g := roundi(c.g * 255.0)
	var b := roundi(c.b * 255.0)
	if box_w == 1:
		line(x0, y0, x0, y0 + box_h - 1, c)
		return
	if box_h == 1:
		_hspan(x0, y0, x0 + box_w - 1, r, g, b)
		return
	var cx := x0 + box_w / 2
	var cy := y0 + box_h / 2
	var x_off := (box_w + 1) % 2
	var y_off := (box_h + 1) % 2
	var w2 := box_w / 2
	var h2 := box_h / 2
	var x := 0.0
	var y := float(h2)
	var d1 := float(h2 * h2) - float(w2 * w2 * h2) + .25 * float(w2 * w2)
	var dx := 2.0 * h2 * h2 * x
	var dy := 2.0 * w2 * w2 * y
	var hh := float(2 * h2 * h2)
	var ww := float(2 * w2 * w2)
	var h2f := float(h2 * h2)
	var w2f := float(w2 * w2)
	while dx < dy:
		_hspan(cx - int(x), cy - int(y), cx + int(x) - x_off, r, g, b)
		_hspan(cx - int(x), cy + int(y) - y_off, cx + int(x) - x_off, r, g, b)
		if d1 < 0.0:
			x += 1.0
			dx += hh
			d1 += dx + h2f
		else:
			x += 1.0
			y -= 1.0
			dx += hh
			dy -= ww
			d1 += dx - dy + h2f
	var d2 := (
		(h2f * ((x + .5) * (x + .5))) + (w2f * ((y - 1.0) * (y - 1.0))) - float(w2 * w2 * h2 * h2)
	)
	while y >= 0.0:
		_hspan(cx - int(x), cy - int(y), cx + int(x) - x_off, r, g, b)
		_hspan(cx - int(x), cy + int(y) - y_off, cx + int(x) - x_off, r, g, b)
		if d2 > 0.0:
			y -= 1.0
			dy -= ww
			d2 += w2f - dy
		else:
			y -= 1.0
			x += 1.0
			dx += hh
			dy -= ww
			d2 += dx - dy + w2f


## pygame draw.rect(..., border_radius=r), filled: an 8-gon body plus four
## filled quadrants. Exactly the reference's HUD plate and meter styling.
func round_rect(x: int, y: int, box_w: int, box_h: int, radius: int, c: Color) -> void:
	var tl := radius
	var tr := radius
	var bl := radius
	var br := radius
	var x2 := x + box_w - 1
	var y2 := y + box_h - 1
	if tl + tr > box_w or bl + br > box_w or tl + bl > box_h or tr + br > box_h:
		var q_top := float(box_w) / float(tl + tr)
		var q_left := float(box_h) / float(tl + bl)
		var q_bottom := float(box_w) / float(bl + br)
		var q_right := float(box_h) / float(tr + br)
		var f := minf(minf(q_top, q_left), minf(q_bottom, q_right))
		tl = int(tl * f)
		tr = int(tr * f)
		bl = int(bl * f)
		br = int(br * f)
	var r := roundi(c.r * 255.0)
	var g := roundi(c.g * 255.0)
	var b := roundi(c.b * 255.0)
	if box_w <= 0 or box_h <= 0:
		return
	polygon(
		[
			Vector2(x, y + tl),
			Vector2(x + tl, y),
			Vector2(x2 - tr, y),
			Vector2(x2, y + tr),
			Vector2(x2, y2 - br),
			Vector2(x2 - br, y2),
			Vector2(x + bl, y2),
			Vector2(x, y2 - bl)
		],
		c
	)
	_quadrant(x2 - tr + 1, y + tr, tr, r, g, b, true, false, false, false)
	_quadrant(x + tl, y + tl, tl, r, g, b, false, true, false, false)
	_quadrant(x + bl, y2 - bl + 1, bl, r, g, b, false, false, true, false)
	_quadrant(x2 - br + 1, y2 - br + 1, br, r, g, b, false, false, false, true)


## pygame draw_circle_quadrant with thickness 0 (a filled corner wedge).
func _quadrant(
	x0: int,
	y0: int,
	radius: int,
	r: int,
	g: int,
	b: int,
	top_right: bool,
	top_left: bool,
	bottom_left: bool,
	bottom_right: bool
) -> void:
	if radius == 1:
		if top_right:
			set_pixel(x0, y0 - 1, r, g, b)
		if top_left:
			set_pixel(x0 - 1, y0 - 1, r, g, b)
		if bottom_left:
			set_pixel(x0 - 1, y0, r, g, b)
		if bottom_right:
			set_pixel(x0, y0, r, g, b)
		return
	var f := 1 - radius
	var ddf_x := 0
	var ddf_y := -2 * radius
	var x := 0
	var y := radius
	while x < y:
		if f >= 0:
			y -= 1
			ddf_y += 2
			f += ddf_y
		x += 1
		ddf_x += 2
		f += ddf_x + 1
		if top_right:
			_vspan(x0 + y - 1, y0 - x, y0, r, g, b)
			_vspan(x0 + x - 1, y0 - y, y0, r, g, b)
		if top_left:
			_vspan(x0 - y, y0 - x, y0, r, g, b)
			_vspan(x0 - x, y0 - y, y0, r, g, b)
		if bottom_left:
			_vspan(x0 - y, y0, y0 + x - 1, r, g, b)
			_vspan(x0 - x, y0, y0 + y - 1, r, g, b)
		if bottom_right:
			_vspan(x0 + y - 1, y0, y0 + x - 1, r, g, b)
			_vspan(x0 + x - 1, y0, y0 + y - 1, r, g, b)


func _vspan(x: int, y0: int, y1: int, r: int, g: int, b: int) -> void:
	if x < 0 or x >= w:
		return
	var lo := maxi(0, mini(y0, y1))
	var hi := mini(h - 1, maxi(y0, y1))
	if gpu:
		if lo <= hi:
			_gpu_rect(x, lo, 1, hi - lo + 1, r, g, b)
		return
	for y in range(lo, hi + 1):
		var o := (y * w + x) * 3
		pixels[o] = r
		pixels[o + 1] = g
		pixels[o + 2] = b
		if use_mask:
			mask[y * w + x] = 1
		if layer:
			cover[y * w + x] = 255


## pygame draw.polygon: 3 points use draw_filltri, more use draw_fillpoly.
func polygon(points: Array, c: Color) -> void:
	if points.size() < 3:
		return
	var r := roundi(c.r * 255.0)
	var g := roundi(c.g * 255.0)
	var b := roundi(c.b * 255.0)
	var xs := PackedInt32Array()
	var ys := PackedInt32Array()
	xs.resize(points.size())
	ys.resize(points.size())
	for i in points.size():
		var pv: Vector2 = points[i]
		xs[i] = int(pv.x)
		ys[i] = int(pv.y)
	if points.size() == 3:
		_fill_tri(xs, ys, r, g, b)
	else:
		_fill_poly(xs, ys, r, g, b)


## pygame draw_filltri: sorts the three vertices by y, then spans between the
## two outer edges. Mirroring the C code's float casts matters for the exact
## pixel coverage of the sloped edges.
func _fill_tri(xs: PackedInt32Array, ys: PackedInt32Array, r: int, g: int, b: int) -> void:
	var p0x := xs[0]
	var p0y := ys[0]
	var p1x := xs[1]
	var p1y := ys[1]
	var p2x := xs[2]
	var p2y := ys[2]
	if p1y < p0y:
		var t := p0x
		p0x = p1x
		p1x = t
		t = p0y
		p0y = p1y
		p1y = t
	if p2y < p1y:
		var t2 := p1x
		p1x = p2x
		p2x = t2
		t2 = p1y
		p1y = p2y
		p2y = t2
		if p1y < p0y:
			var t3 := p1x
			p1x = p0x
			p0x = t3
			t3 = p1y
			p1y = p0y
			p0y = t3
	if p0y == p1y and p1y == p2y and p0x == p1x and p1x != p2x:
		var t4 := p1x
		p1x = p2x
		p2x = t4
		t4 = p1y
		p1y = p2y
		p2y = t4
	var d1 := float(p2x - p0x) / (float(p2y - p0y) + 1e-17)
	var d2 := float(p1x - p0x) / (float(p1y - p0y) + 1e-17)
	var d3 := float(p2x - p1x) / (float(p2y - p1y) + 1e-17)
	for y in range(p0y, p2y + 1):
		var x1 := p0x + int((y - p0y) * d1)
		var x2: int
		if y < p1y:
			x2 = p0x + int((y - p0y) * d2)
		else:
			x2 = p1x + int((y - p1y) * d3)
		_hspan(x1, y, x2, r, g, b)


## pygame draw_fillpoly: scanline intersections with floor/ceil alternation.
func _fill_poly(xs: PackedInt32Array, ys: PackedInt32Array, r: int, g: int, b: int) -> void:
	var n := xs.size()
	var min_y := ys[0]
	var max_y := ys[0]
	for i in range(1, n):
		min_y = mini(min_y, ys[i])
		max_y = maxi(max_y, ys[i])
	if min_y == max_y:
		var min_x := xs[0]
		var max_x := xs[0]
		for i in range(1, n):
			min_x = mini(min_x, xs[i])
			max_x = maxi(max_x, xs[i])
		_hspan(min_x, min_y, max_x, r, g, b)
		return
	for y in range(min_y, max_y + 1):
		var hits: Array[int] = []
		for i in n:
			var prev := (i - 1 + n) % n
			var y1 := ys[prev]
			var y2 := ys[i]
			var x1: int
			var x2: int
			if y1 < y2:
				x1 = xs[prev]
				x2 = xs[i]
			elif y1 > y2:
				var t := y2
				y2 = y1
				y1 = t
				x2 = xs[prev]
				x1 = xs[i]
			else:
				continue
			if (y >= y1 and y < y2) or (y == max_y and y2 == max_y):
				var inter := float((y - y1) * (x2 - x1)) / float(y2 - y1)
				if hits.size() % 2 == 0:
					inter = floor(inter)
				else:
					inter = ceil(inter)
				hits.append(int(inter) + x1)
		hits.sort()
		var k := 0
		while k + 1 < hits.size():
			_hspan(hits[k], y, hits[k + 1], r, g, b)
			k += 2
	for i in n:
		var prev2 := (i - 1 + n) % n
		var yy := ys[i]
		if min_y < yy and ys[prev2] == yy and yy < max_y:
			_hspan(xs[i], yy, xs[prev2], r, g, b)


## Alpha-blend an RGBA image (assets.art format) with its top-left at x,y.
## The destination is an opaque RGB surface, so pygame runs
## ALPHA_BLEND_COMP ((s-d)*a+s)>>8 + d for every channel.
func blit_rgba(data: PackedByteArray, img_w: int, img_h: int, x: int, y: int, key := "") -> void:
	if gpu:
		# Pictures are cached by name; one without a name is made afresh.
		var made: ImageTexture
		if key == "":
			made = ImageTexture.create_from_image(
				Image.create_from_data(img_w, img_h, false, Image.FORMAT_RGBA8, data)
			)
		else:
			made = texture(key, data, img_w, img_h)
		gpu_texture(made, x, y, img_w, img_h)
		return
	for yy in img_h:
		var ty := y + yy
		if ty < 0 or ty >= h:
			continue
		var row := yy * img_w * 4
		for xx in img_w:
			var tx := x + xx
			if tx < 0 or tx >= w:
				continue
			var sp := row + xx * 4
			var a := data[sp + 3]
			if a == 0:
				continue
			var o := (ty * w + tx) * 3
			if layer:
				var p := ty * w + tx
				cover[p] = 255 if a == 255 else cover[p] + (((255 - cover[p]) * a + 255) >> 8)
			if a == 255:
				pixels[o] = data[sp]
				pixels[o + 1] = data[sp + 1]
				pixels[o + 2] = data[sp + 2]
			else:
				pixels[o] = clampi(
					pixels[o] + (((data[sp] - pixels[o]) * a + data[sp]) >> 8), 0, 255
				)
				pixels[o + 1] = clampi(
					pixels[o + 1] + (((data[sp + 1] - pixels[o + 1]) * a + data[sp + 1]) >> 8),
					0,
					255
				)
				pixels[o + 2] = clampi(
					pixels[o + 2] + (((data[sp + 2] - pixels[o + 2]) * a + data[sp + 2]) >> 8),
					0,
					255
				)


## Copy an RGBA image, flattening it onto an opaque colour first (art sheets are
## alpha-cut, the reference converts them with .convert() for plates).
func blit_rgba_opaque(
	data: PackedByteArray, img_w: int, img_h: int, x: int, y: int, bg: Color
) -> void:
	var br := roundi(bg.r * 255.0)
	var bgc := roundi(bg.g * 255.0)
	var bb := roundi(bg.b * 255.0)
	for yy in img_h:
		var ty := y + yy
		if ty < 0 or ty >= h:
			continue
		var row := yy * img_w * 4
		for xx in img_w:
			var tx := x + xx
			if tx < 0 or tx >= w:
				continue
			var sp := row + xx * 4
			var a := data[sp + 3] / 255.0
			var o := (ty * w + tx) * 3
			pixels[o] = int(br * (1.0 - a) + data[sp] * a)
			pixels[o + 1] = int(bgc * (1.0 - a) + data[sp + 1] * a)
			pixels[o + 2] = int(bb * (1.0 - a) + data[sp + 2] * a)
			if layer:
				cover[ty * w + tx] = 255


## Text drawn with pixel_type glyphs; returns the rect as Rect2i.
func label(
	text: String,
	x: int,
	y: int,
	style := "body",
	color := PixelType.INK,
	center := false,
	shadow := true,
	right := false
) -> Rect2i:
	var sx: int = PixelType.style_of(style)[0]
	var height: int = PixelType.style_of(style)[1]
	var mini := style == "mini"
	var width := PixelType.text_width(text, style)
	var px := x
	if center:
		px = x - width / 2
	elif right:
		px = x - width
	var rect := Rect2i(px, y, width, height)
	if shadow:
		_draw_glyphs(
			text, rect.position.x + 1, rect.position.y + 1, sx, height, mini, PixelType.SHADE
		)
	_draw_glyphs(text, rect.position.x, rect.position.y, sx, height, mini, color)
	return rect


func _draw_glyphs(
	text: String, x0: int, y0: int, sx: int, height: int, mini: bool, color: Color
) -> void:
	var x := x0
	var r := roundi(color.r * 255.0)
	var g := roundi(color.g * 255.0)
	var b := roundi(color.b * 255.0)
	if gpu:
		var tint := Color8(r, g, b)
		for ch in text.to_upper():
			var kept := _glyph_texture(ch, mini, sx, height)
			var made: ImageTexture = kept[0]
			RenderingServer.canvas_item_add_texture_rect(
				_item,
				Rect2(x, y0, made.get_width(), made.get_height()),
				made.get_rid(),
				false,
				tint
			)
			x += (int(kept[1]) + 1) * sx
		return
	for ch in text.to_upper():
		var info := PixelType.glyph(ch, mini)
		var rows: Array = info[0]
		var glyph_w: int = info[1]
		var n := rows.size()
		for yi in n:
			var top := yi * height / n
			var bottom := (yi + 1) * height / n
			var bits: int = rows[yi]
			for col in glyph_w:
				if bits & (1 << (glyph_w - col - 1)):
					var px := x + col * sx
					for yy in range(top, bottom):
						for xx in sx:
							set_pixel(px + xx, y0 + yy, r, g, b)
		x += (glyph_w + 1) * sx


## pygame HUD.panel(): drop shadow, face, 1px edge and a bottom inner line.
func panel(x: int, y: int, box_w: int, box_h: int, face := FACE, edge := EDGE) -> void:
	fill_rect(x + 1, y + 2, box_w, box_h, DROP)
	fill_rect(x, y, box_w, box_h, face)
	rect_outline(x, y, box_w, box_h, edge)
	line(x + 2, y + box_h - 2, x + box_w - 3, y + box_h - 2, UNDERLINE)
