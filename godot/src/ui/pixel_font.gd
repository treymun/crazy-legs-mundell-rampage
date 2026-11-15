## The game's own pixel letters (PixelType's hand-cut glyph tables) as Godot
## fonts, so Control nodes (labels, buttons, the text fields of the online
## forms) letter exactly as the canvas did: no smoothing, the same advances,
## each style's rows stretched to its height (mini 5, body 7, menu 9, heading
## 14 at double width). Made once per style and kept.
class_name PixelFont
extends RefCounted

const CHARS := " ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,:;!?'\"-+/()%#&*<>=_@$[]"

static var _fonts := {}


## The font for a style ("mini", "body", "menu", "heading").
static func of(style: String) -> FontFile:
	var cached: Variant = _fonts.get(style)
	if cached != null:
		return cached
	var spec: Array = PixelType.STYLES.get(style, PixelType.STYLES["body"])
	var sx: int = spec[0]
	var height: int = spec[1]
	var mini := style == "mini"
	var font := FontFile.new()
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.fixed_size = height
	font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
	font.allow_system_fallback = false
	var size := Vector2i(height, 0)
	# One atlas row, each glyph in a cell (5 bits wide at most, times sx).
	var cell := 6 * sx + 1
	var atlas := Image.create_empty(cell * CHARS.length(), height, false, Image.FORMAT_LA8)
	for i in CHARS.length():
		var ch := CHARS[i]
		var info := PixelType.glyph(ch, mini)
		var rows: Array = info[0]
		var w: int = info[1]
		var n := rows.size()
		for yi in n:
			var top := yi * height / n
			var bottom := (yi + 1) * height / n
			var bits: int = rows[yi]
			for col in w:
				if bits & (1 << (w - col - 1)):
					for yy in range(top, bottom):
						for xx in sx:
							atlas.set_pixel(i * cell + col * sx + xx, yy, Color(1, 1, 1, 1))
	font.set_texture_image(0, size, 0, atlas)
	font.set_cache_ascent(0, height, height)
	font.set_cache_descent(0, height, 0)
	for i in CHARS.length():
		var ch := CHARS[i]
		var w: int = PixelType.glyph(ch, mini)[1]
		var code := ch.unicode_at(0)
		for c: int in [code, ch.to_lower().unicode_at(0)]:
			font.set_glyph_advance(0, height, c, Vector2((w + 1) * sx, 0))
			font.set_glyph_offset(0, size, c, Vector2(0, -height))
			font.set_glyph_size(0, size, c, Vector2(w * sx, height))
			font.set_glyph_uv_rect(0, size, c, Rect2(i * cell, 0, w * sx, height))
			font.set_glyph_texture_idx(0, size, c, 0)
	_fonts[style] = font
	return font
