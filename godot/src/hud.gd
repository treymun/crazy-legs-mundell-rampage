## Port of hud.py: the rusted status plate, ammo rail, meters, mugshot,
## item slot and the title/intermission/tally screens.
##
## The plate is rendered once into an RGB8 strip (the reference bakes its
## headings into a converted copy of status_panel) and blitted under the view
## every frame, exactly like the original.
class_name HUD
extends RefCounted

const INK := Color(250 / 255.0, 232 / 255.0, 193 / 255.0)
const SHADE := Color(27 / 255.0, 19 / 255.0, 15 / 255.0)
const AMBER := Color(251 / 255.0, 183 / 255.0, 98 / 255.0)
const DIM := Color(163 / 255.0, 134 / 255.0, 99 / 255.0)
const LOW := Color(238 / 255.0, 89 / 255.0, 52 / 255.0)
const LOW_HOT := Color(255 / 255.0, 113 / 255.0, 64 / 255.0)

const ITEMS := ["rinds", "beer", "moonshine", "whiskey", "cowpie"]
const ITEM_LABELS := ["PORK RINDS", "BEER", "MOONSHINE", "WHISKEY", "COW PIE"]
const SHORT_LABELS := ["RINDS", "BEER", "SHINE", "WHSKY", "PIE"]
## BELT weapon order: revolver, shotgun, crossbow, rifle, ripsaw, armgun, tnt
const BELT := [1, 2, 3, 4, 5, 6, 7]
const TITLE_FIRST := 101
const TITLE_ROW := 9

var assets: Assets
var plate := PackedByteArray()
var plate_w := 320
var plate_h := 44
var icons := {}
var ammo_icons: Array = []
var face_cache := {}
var dial_cache := {}


func _init(p_assets: Assets) -> void:
	assets = p_assets
	var art := assets.art("status_panel")
	plate_w = int(art["w"])
	plate_h = int(art["h"])
	plate.resize(plate_w * plate_h * 3)
	var data: PackedByteArray = art["data"]
	for i in plate_w * plate_h:
		plate[i * 3] = data[i * 4]
		plate[i * 3 + 1] = data[i * 4 + 1]
		plate[i * 3 + 2] = data[i * 4 + 2]
	# Bake the plate headings (HUD.__init__ draws them into the converted copy).
	var scratch := Canvas.new(plate_w, plate_h)
	scratch.pixels = plate
	for entry: Array in [
		["HEALTH", 29, 13, "body"],
		["AMMO", 77, 13, "body"],
		["KEYS", 115, 13, "body"],
		["YER STUFF", 292, 14, "mini"]
	]:
		scratch.label(
			String(entry[0]), int(entry[1]), int(entry[2]), String(entry[3]), INK, true, true
		)
	plate = scratch.pixels
	_build_ammo_icons()


## Port of HUD.text: blit a label with a one-pixel shade offset.
static func text(
	c: Canvas,
	value: String,
	x: int,
	y: int,
	style := "body",
	color := INK,
	center := false,
	shadow := true,
	right := false
) -> Rect2i:
	return c.label(value, x, y, style, color, center, shadow, right)


## Port of HUD.panel.
static func panel(
	c: Canvas,
	x: int,
	y: int,
	w: int,
	h: int,
	face := Color(40 / 255.0, 29 / 255.0, 23 / 255.0),
	edge := Color(141 / 255.0, 102 / 255.0, 65 / 255.0)
) -> void:
	c.panel(x, y, w, h, face, edge)


## Port of HUD.banner: word-wrapped message panel across the top of the view.
## Returns the y coordinate below the panel.
static func banner(c: Canvas, value: String, top: int, limit := 288, color := INK) -> int:
	# A banner is an opaque plate that says the same thing for seconds on end:
	# it is drawn once, kept as a block of pixels and pasted back each frame.
	var style := text_style
	var key := [value, top, limit, color, style]
	if c.gpu:
		return _banner_texture(c, key, value, top, limit, color)
	var kept = _banners.get(key)
	if kept != null:
		_paste(c, kept)
		return int(kept["bottom"])
	var lines := PixelType.wrap(value, limit - 14, style)
	if lines.is_empty():
		return top
	var widest := 0
	for line in lines:
		widest = maxi(widest, PixelType.text_width(line, style))
	var width := widest + 14
	var line_h := int(PixelType.style_of(style)[1]) + 3
	var height := line_h * lines.size() + 4
	var middle := Canvas.WIDTH / 2
	panel(
		c,
		middle - width / 2,
		top,
		width,
		height,
		Color(32 / 255.0, 23 / 255.0, 19 / 255.0),
		Color(128 / 255.0, 88 / 255.0, 57 / 255.0)
	)
	for i in lines.size():
		text(c, lines[i], middle, top + 4 + i * line_h, style, color, true, false)
	var x := middle - width / 2
	if (
		not c.gpu
		and x >= 0
		and top >= 0
		and x + width <= Canvas.WIDTH
		and top + height <= Canvas.HEIGHT
	):
		var block := PackedByteArray()
		for row in height:
			var from := ((top + row) * Canvas.WIDTH + x) * 3
			block.append_array(c.pixels.slice(from, from + width * 3))
		if _banners.size() > 24:
			_banners.clear()
		_banners[key] = {
			"x": x, "y": top, "w": width, "h": height, "data": block, "bottom": top + height
		}
	return top + height


static var _banners := {}
static var _banner_textures := {}
## TEXT SIZE: the type banners (notices, prompts, captions, one-liners) use.
static var text_style := "body"


## A banner on a Godot 2D canvas: drawn once in software, drop shadow and all,
## onto a small transparent surface, then shown as one texture.
static func _banner_texture(
	c: Canvas, key: Array, value: String, top: int, limit: int, color: Color
) -> int:
	var kept = _banner_textures.get(key)
	if kept == null:
		var style := text_style
		var lines := PixelType.wrap(value, limit - 14, style)
		if lines.is_empty():
			return top
		var widest := 0
		for line in lines:
			widest = maxi(widest, PixelType.text_width(line, style))
		var width := widest + 14
		var line_h := int(PixelType.style_of(style)[1]) + 3
		var height := line_h * lines.size() + 4
		var plate := Canvas.new(width + 1, height + 2)
		plate.enable_mask()
		panel(
			plate,
			0,
			0,
			width,
			height,
			Color(32 / 255.0, 23 / 255.0, 19 / 255.0),
			Color(128 / 255.0, 88 / 255.0, 57 / 255.0)
		)
		for i in lines.size():
			text(plate, lines[i], width / 2, 4 + i * line_h, style, color, true, false)
		if _banner_textures.size() > 24:
			_banner_textures.clear()
		kept = {
			"x": Canvas.WIDTH / 2 - width / 2,
			"w": width + 1,
			"h": height + 2,
			"bottom": top + height,
			"texture":
			ImageTexture.create_from_image(
				Image.create_from_data(
					width + 1, height + 2, false, Image.FORMAT_RGBA8, plate.to_rgba()
				)
			)
		}
		_banner_textures[key] = kept
	c.gpu_texture(kept["texture"], int(kept["x"]), top, int(kept["w"]), int(kept["h"]))
	return int(kept["bottom"])


## Lay a kept block of pixels back into the frame with whole-row copies.
static func _paste(c: Canvas, kept: Dictionary) -> void:
	var x: int = kept["x"]
	var y: int = kept["y"]
	var w: int = kept["w"]
	var h: int = kept["h"]
	var block: PackedByteArray = kept["data"]
	var pix := c.pixels
	var out := pix.slice(0, (y * Canvas.WIDTH + x) * 3)
	for row in h:
		out.append_array(block.slice(row * w * 3, (row + 1) * w * 3))
		var after := ((y + row) * Canvas.WIDTH + x + w) * 3
		var until := ((y + row + 1) * Canvas.WIDTH + x) * 3 if row < h - 1 else pix.size()
		out.append_array(pix.slice(after, until))
	c.pixels = out
	if c.layer:
		# The same join for the layer's coverage: the block is solid.
		var solid := PackedByteArray()
		solid.resize(w)
		solid.fill(255)
		var cover := c.cover
		var joined := cover.slice(0, y * Canvas.WIDTH + x)
		for row in h:
			joined.append_array(solid)
			var after := (y + row) * Canvas.WIDTH + x + w
			var until := (y + row + 1) * Canvas.WIDTH + x if row < h - 1 else cover.size()
			joined.append_array(cover.slice(after, until))
		c.cover = joined


## Port of HUD.number: the big rust-orange plate numerals.
static func number(c: Canvas, value: String, center: int, y: int, low := false) -> void:
	text(c, value, center, y, "heading", LOW_HOT if low else LOW, true, true)


# ---------------------------------------------------------------- icons


## Crop an RGBA image to its opaque bbox and smoothscale into a width x height box.
func _scaled(art: Dictionary, box_w: int, box_h: int) -> Dictionary:
	var w: int = art["w"]
	var h: int = art["h"]
	var data: PackedByteArray = art["data"]
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in h:
		for x in w:
			if data[(y * w + x) * 4 + 3] >= 128:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	if x1 < x0 or y1 < y0:
		return {"w": 1, "h": 1, "data": PackedByteArray([0, 0, 0, 0])}
	var cw := x1 - x0 + 1
	var ch := y1 - y0 + 1
	var scale := minf(float(box_w) / cw, float(box_h) / ch)
	var tw := maxi(1, int(round(cw * scale)))
	var th := maxi(1, int(round(ch * scale)))
	var sub := _crop(data, w, x0, y0, cw, ch)
	var out := SmoothScale.rgba(sub, cw, ch, tw, th)
	return {"w": tw, "h": th, "data": out}


## Copy a cw x ch window out of an RGBA buffer.
static func _crop(
	data: PackedByteArray, w: int, x0: int, y0: int, cw: int, ch: int
) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(cw * ch * 4)
	var row := cw * 4
	for y in ch:
		var src_at := ((y0 + y) * w + x0) * 4
		var dst_at := y * row
		for k in row:
			out[dst_at + k] = data[src_at + k]
	return out


func icon(name: String, box_w: int, box_h: int) -> Dictionary:
	var key := "%s|%d|%d" % [name, box_w, box_h]
	var cached = icons.get(key)
	if cached != null:
		return cached
	var art := assets.art("item_" + name)
	var result := _scaled(art, box_w, box_h)
	icons[key] = result
	return result


func blit_icon(c: Canvas, name: String, box_w: int, box_h: int, cx: int, cy: int) -> void:
	var image := icon(name, box_w, box_h)
	var w: int = image["w"]
	var h: int = image["h"]
	c.blit_rgba(image["data"], w, h, cx - w / 2, cy - h / 2, "icon|%s|%d|%d" % [name, box_w, box_h])


## Port of HUD.make_ammo_icons(): seven 12x6 cartridge tokens.
func _build_ammo_icons() -> void:
	var silver := Color(185 / 255.0, 174 / 255.0, 145 / 255.0)
	var brass := Color(183 / 255.0, 141 / 255.0, 81 / 255.0)
	var lead := Color(115 / 255.0, 119 / 255.0, 107 / 255.0)
	var red := Color(171 / 255.0, 74 / 255.0, 50 / 255.0)
	var green := Color(129 / 255.0, 152 / 255.0, 79 / 255.0)
	ammo_icons.clear()
	for _i in BELT.size():
		var c := Canvas.new(12, 6)
		c.enable_mask()
		ammo_icons.append(c)
	for i in [0, 3]:
		var c: Canvas = ammo_icons[i]
		c.fill_rect(1, 2, 6, 3, brass)
		c.line(1, 2, 6, 2, Color(210 / 255.0, 180 / 255.0, 123 / 255.0))
		var tip := silver if i == 0 else lead
		c.polygon([Vector2(7, 2), Vector2(9, 2), Vector2(11, 3), Vector2(9, 4), Vector2(7, 4)], tip)
		if i == 3:
			c.line(3, 1, 9, 1, lead)
	for i in [1, 2, 6]:
		var c: Canvas = ammo_icons[i]
		c.fill_rect(2, 2, 8, 3, red)
		c.line(1, 2, 1, 4, brass if i == 1 else silver)
		if i != 1:
			c.line(5, 1, 5, 5, brass)
			c.line(10, 2, 11, 1, lead)
		if i == 2:
			c.line(1, 1, 8, 1, silver)
	var c4: Canvas = ammo_icons[4]
	c4.ellipse(1, 0, 10, 6, lead)
	c4.line(3, 1, 8, 1, silver)
	c4.set_pixel(6, 3, 45, 39, 32)
	var c5: Canvas = ammo_icons[5]
	for x in [2, 5, 8]:
		c5.fill_rect(x, 1, 2, 4, green)
		c5.set_pixel(x, 1, 185, 174, 145)


# ---------------------------------------------------------------- rail


func ammo_rail(c: Canvas, armory: Weapons.Armory) -> void:
	for i in BELT.size():
		var slot: int = BELT[i]
		var x := 6 + i * 45
		if (
			slot == Weapons.DYNAMITE
			and (
				armory.active
				in [
					Weapons.SLING,
					Weapons.ROCKET,
					Weapons.RIVETER,
					Weapons.PRESSURE,
					Weapons.BOWLING,
					Weapons.KEG,
					Weapons.COW,
					Weapons.TEAT
				]
			)
		):
			c.fill_rect(x, Renderer.VIEW + 1, 39, 6, Color(51 / 255.0, 33 / 255.0, 25 / 255.0))
			var token := "9"
			match armory.active:
				Weapons.ROCKET:
					token = "0"
				Weapons.RIVETER:
					token = "-"
				Weapons.PRESSURE:
					token = "="
				Weapons.BOWLING:
					token = "-"
				Weapons.KEG:
					token = "="
				Weapons.COW:
					token = "\\"
				Weapons.TEAT:
					token = "`"
			text(c, token, x + 8, Renderer.VIEW + 1, "body", AMBER, true, false)
			var value := (
				"-" if armory.active == Weapons.SLING else str(armory.reserve[armory.active])
			)
			text(c, value, x + 25, Renderer.VIEW + 1, "body", INK, true, false)
			continue
		if armory.active == slot:
			c.line(
				x,
				Renderer.VIEW + 7,
				mini(314, x + 39),
				Renderer.VIEW + 7,
				Color(189 / 255.0, 132 / 255.0, 79 / 255.0)
			)
			c.fill_rect(x, Renderer.VIEW + 1, 39, 6, Color(51 / 255.0, 33 / 255.0, 25 / 255.0))
		if armory.owned[slot]:
			var token: Canvas = ammo_icons[i]
			c.blit_rgba(token.to_rgba(), 12, 6, x + 8 - 6, Renderer.VIEW + 4 - 3)
		var pool := Weapons.CROSSBOW if slot == Weapons.DYNAMITE else slot
		var value2 := str(armory.reserve[pool]) if armory.owned[slot] else "-"
		text(
			c,
			value2,
			x + 25,
			Renderer.VIEW + 1,
			"body",
			INK if armory.owned[slot] else DIM,
			true,
			false
		)


static func _rgb_to_rgba(rgb: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(rgb.size() / 3 * 4)
	var o := 0
	for i in range(0, rgb.size(), 3):
		out[o] = rgb[i]
		out[o + 1] = rgb[i + 1]
		out[o + 2] = rgb[i + 2]
		out[o + 3] = 255
		o += 4
	return out


# ---------------------------------------------------------------- meters


func meter(c: Canvas, x: int, y: int, caption: String, value: float, colors: Array) -> void:
	c.round_rect(x, y, 91, 12, 2, Color(57 / 255.0, 46 / 255.0, 38 / 255.0))
	c.line(x + 2, y, x + 88, y, Color(172 / 255.0, 159 / 255.0, 132 / 255.0))
	c.line(x + 1, y + 1, x + 1, y + 9, Color(100 / 255.0, 92 / 255.0, 76 / 255.0))
	c.line(x + 2, y + 10, x + 88, y + 10, Color(125 / 255.0, 111 / 255.0, 92 / 255.0))
	text(c, caption, x + 4, y + 2, "body", INK, false, false)
	x += 32
	c.fill_rect(x - 2, y + 2, 58, 8, Color(29 / 255.0, 23 / 255.0, 19 / 255.0))
	for i in 11:
		var active := value > i * 9
		var ink: Color = colors[mini(2, i / 4)]
		# The reference keeps plain 0-255 ints here and shifts them, so do the
		# same rather than round-tripping through Color floats.
		var ir := roundi(ink.r * 255.0)
		var ig := roundi(ink.g * 255.0)
		var ib := roundi(ink.b * 255.0)
		var sr := ir if active else ir / 4
		var sg := ig if active else ig / 4
		var sb := ib if active else ib / 4
		c.fill_rect(x + i * 5, y + 3, 4, 6, Canvas.rgb(sr, sg, sb))
		if active:
			c.line(
				x + i * 5,
				y + 3,
				x + i * 5 + 3,
				y + 3,
				Canvas.rgb(mini(255, sr + 24), mini(255, sg + 24), mini(255, sb + 24))
			)


func gauge(c: Canvas, x: int, y: int, caption: String, value: float) -> void:
	# The reference builds the dial on a 44x31 SRCALPHA surface and blits it, so
	# undrawn pixels keep whatever is behind. Drawing straight into the canvas
	# reproduces that exactly without needing a mask.
	var body: Array = []
	for corner: Vector2 in [
		Vector2(0, 23),
		Vector2(4, 5),
		Vector2(9, 0),
		Vector2(35, 0),
		Vector2(41, 6),
		Vector2(43, 23),
		Vector2(38, 27),
		Vector2(6, 27)
	]:
		body.append(corner + Vector2(x, y))
	c.polygon(body, Color(128 / 255.0, 124 / 255.0, 106 / 255.0))
	c.line(x + 7, y + 1, x + 36, y + 1, Color(192 / 255.0, 180 / 255.0, 146 / 255.0))
	c.line(x + 4, y + 26, x + 39, y + 26, Color(62 / 255.0, 54 / 255.0, 44 / 255.0))
	c.round_rect(x + 5, y + 3, 34, 20, 5, Color(50 / 255.0, 43 / 255.0, 37 / 255.0))
	c.ellipse(x + 6, y + 4, 32, 21, Color(189 / 255.0, 172 / 255.0, 132 / 255.0))
	c.fill_rect(x + 5, y + 17, 34, 6, Color(50 / 255.0, 43 / 255.0, 37 / 255.0))
	var colors: Array = [
		Color(167 / 255.0, 152 / 255.0, 57 / 255.0),
		Color(109 / 255.0, 139 / 255.0, 68 / 255.0),
		Color(163 / 255.0, 68 / 255.0, 48 / 255.0)
	]
	if caption == "DRUNK":
		colors = [
			Color(170 / 255.0, 151 / 255.0, 65 / 255.0),
			Color(180 / 255.0, 125 / 255.0, 60 / 255.0),
			Color(172 / 255.0, 62 / 255.0, 42 / 255.0)
		]
	for i in 30:
		var a := deg_to_rad(153.0 - 126.0 * i / 30.0)
		var b := deg_to_rad(153.0 - 126.0 * (i + 1) / 30.0)
		_tri(
			c,
			_ring(x, y, a, 16),
			_ring(x, y, b, 16),
			_ring(x, y, b, 10),
			_ring(x, y, a, 10),
			colors[mini(2, i / 10)]
		)
	for i in range(0, 31, 5):
		var a2 := deg_to_rad(153.0 - 126.0 * i / 30.0)
		var outer := _ring(x, y, a2, 17)
		var inner := _ring(x, y, a2, 15)
		c.line(
			int(outer.x),
			int(outer.y),
			int(inner.x),
			int(inner.y),
			Color(69 / 255.0, 59 / 255.0, 42 / 255.0)
		)
	text(c, caption, x + 22, y + 19, "mini", INK, true, false)
	for v in [3, 40]:
		c.circle(x + v, y + 22, 2, Color(72 / 255.0, 57 / 255.0, 42 / 255.0))
		c.set_pixel(x + v - 1, y + 21, 170, 149, 102)
	var a3 := deg_to_rad(153.0 - 126.0 * clampf(value, 0.0, 100.0) / 100.0)
	var cx := x + 22
	var cy := y + 17
	var ex := cx + int(round(cos(a3) * 16.0))
	var ey := cy - int(round(sin(a3) * 12.0))
	c.line(cx, cy, ex, ey, Color(68 / 255.0, 45 / 255.0, 34 / 255.0), 2)
	c.line(cx, cy, ex, ey, Color(235 / 255.0, 194 / 255.0, 116 / 255.0))
	c.circle(cx, cy, 2, Color(102 / 255.0, 84 / 255.0, 57 / 255.0))
	var lamps: Array = [
		Color(162 / 255.0, 141 / 255.0, 66 / 255.0),
		Color(127 / 255.0, 145 / 255.0, 68 / 255.0),
		Color(184 / 255.0, 108 / 255.0, 55 / 255.0),
		Color(191 / 255.0, 65 / 255.0, 42 / 255.0)
	]
	for i in lamps.size():
		var px := x + 10 + 8 * i
		var py := y + 29
		c.circle(px, py, 3, Color(50 / 255.0, 36 / 255.0, 28 / 255.0))
		c.circle(
			px,
			py,
			2,
			lamps[i] if mini(3, int(value / 25)) == i else Color(77 / 255.0, 60 / 255.0, 46 / 255.0)
		)


## pygame.draw.polygon with four float points (a dial wedge).
static func _tri(c: Canvas, p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, col: Color) -> void:
	c.polygon([p0, p1, p2, p3], col)


static func _ring(ox: int, oy: int, a: float, radius: float) -> Vector2:
	return Vector2(ox + 22.0 + round(cos(a) * radius), oy + 17.0 - round(sin(a) * radius * .80))


## Copy an RGB8 image into the canvas (the dials are drawn on transparent masks
## in the reference; they always sit on the plate, so an opaque copy matches).
static func _blit_rgb(c: Canvas, src: PackedByteArray, w: int, h: int, x: int, y: int) -> void:
	if x == 0 and w == Canvas.WIDTH and y >= 0 and y + h <= Canvas.HEIGHT and not c.layer:
		# Whole rows (the status plate): spliced in at once, not pixel by pixel.
		var row := Canvas.WIDTH * 3
		var joined := c.pixels.slice(0, y * row)
		joined.append_array(src.slice(0, h * row))
		joined.append_array(c.pixels.slice((y + h) * row))
		c.pixels = joined
		return
	for yy in h:
		var ty := y + yy
		if ty < 0 or ty >= Canvas.HEIGHT:
			continue
		for xx in w:
			var tx := x + xx
			if tx < 0 or tx >= Canvas.WIDTH:
				continue
			var sp := (yy * w + xx) * 3
			var o := (ty * Canvas.WIDTH + tx) * 3
			c.pixels[o] = src[sp]
			c.pixels[o + 1] = src[sp + 1]
			c.pixels[o + 2] = src[sp + 2]
			if c.layer:
				c.cover[ty * Canvas.WIDTH + tx] = 255


# ---------------------------------------------------------------- objective


func objective_pin(c: Canvas, game: Game) -> void:
	var target = game.objective_target()
	if target == null:
		return
	var p: Player = game.player
	var dx: float = target[0] - p.x
	var dy: float = target[1] - p.y
	var distance := sqrt(dx * dx + dy * dy)
	if distance < .8:
		return
	# Point along the walk there, and count its steps, not the crow's flight.
	var way: Array = game.objective_route(target)
	if int(way[1]) >= 0:
		var lead: Vector2 = way[0]
		dx = lead.x - p.x
		dy = lead.y - p.y
		distance = float(way[1])
	var rel := fposmod(atan2(dy, dx) - p.view_angle() + PI, TAU) - PI
	var x := int(160.0 + clampf(rel / PI, -1.0, 1.0) * 118.0)
	var color := Color(244 / 255.0, 194 / 255.0, 116 / 255.0)
	c.polygon(
		[Vector2(x, 7), Vector2(x - 4, 13), Vector2(x + 4, 13)],
		Color(38 / 255.0, 27 / 255.0, 21 / 255.0)
	)
	c.polygon([Vector2(x, 8), Vector2(x - 3, 12), Vector2(x + 3, 12)], color)
	text(c, str(int(distance)), x, 14, "mini", color, true, true)


# ---------------------------------------------------------------- main draw

## The status bar only changes when something it shows changes, so it is drawn
## once and pasted back as a block until then; the objective pin sits in the
## view and is drawn every frame.
var _bar := PackedByteArray()
var _bar_key := 0
var _bar_texture: ImageTexture
var _bar_scratch: Canvas

## The health shown, ticking toward the real one at TICK_RATE a second of play.
const TICK_RATE := 45.0
var _shown_health := -1.0
var _shown_for: Game = null
var _shown_clock := 0.0


func draw(c: Canvas, game: Game, armory: Weapons.Armory) -> void:
	var real := maxi(0, game.player.health)
	if game != _shown_for or _shown_health < 0.0:
		_shown_for = game
		_shown_health = real
	else:
		_shown_health = move_toward(
			_shown_health, real, maxf(0.0, game.clock - _shown_clock) * TICK_RATE
		)
	_shown_clock = game.clock
	var health := roundi(_shown_health)
	var item: String = ITEMS[game.inventory_slot]
	var key := hash(
		[
			armory.active,
			armory.owned,
			armory.loaded,
			armory.reserve,
			health,
			health <= 25 and int(game.clock * 3) % 2 == 0,
			game.keys.has("key_brass"),
			game.keys.has("key_steel"),
			game.face_name(),
			game.hud_style,
			snappedf(game.player.gut, .25),
			snappedf(game.player.drunk, .25),
			game.inventory_slot,
			game.inventory.get(item, 0)
		]
	)
	var head := Renderer.VIEW * Canvas.WIDTH * 3
	if c.gpu:
		# Drawn in software only when it changes, then shown as one texture.
		if key != _bar_key or _bar_texture == null:
			if _bar_scratch == null:
				_bar_scratch = Canvas.new()
			var scratch := _bar_scratch
			_draw_bar(scratch, game, armory)
			var rows := Image.create_from_data(
				Canvas.WIDTH,
				Canvas.HEIGHT - Renderer.VIEW,
				false,
				Image.FORMAT_RGB8,
				scratch.pixels.slice(head)
			)
			if _bar_texture == null:
				_bar_texture = ImageTexture.create_from_image(rows)
			else:
				_bar_texture.update(rows)
			_bar_key = key
		c.gpu_texture(_bar_texture, 0, Renderer.VIEW, Canvas.WIDTH, Canvas.HEIGHT - Renderer.VIEW)
	elif key == _bar_key and _bar.size() == c.pixels.size() - head:
		var joined := c.pixels.slice(0, head)
		joined.append_array(_bar)
		c.pixels = joined
	else:
		_draw_bar(c, game, armory)
		_bar = c.pixels.slice(head)
		_bar_key = key
	if (
		game.hints
		and not game.map
		and game.clock > game.message_until
		and game.clock > game.district_until
	):
		objective_pin(c, game)


func _draw_bar(c: Canvas, game: Game, armory: Weapons.Armory) -> void:
	_blit_rgb(c, plate, plate_w, plate_h, 0, Renderer.VIEW)
	ammo_rail(c, armory)
	var slot := armory.active
	var amount := "-"
	if slot == Weapons.DYNAMITE:
		amount = str(armory.reserve[Weapons.CROSSBOW])
	elif Weapons.pool_fed(slot):
		amount = str(armory.reserve[slot])
	elif slot not in [Weapons.CROWBAR, Weapons.SLING]:
		amount = str(armory.loaded[slot])
	var health := roundi(_shown_health) if _shown_for == game else maxi(0, game.player.health)
	number(c, str(health), 29, Renderer.VIEW + 23, health <= 25)
	if health <= 25 and int(game.clock * 3) % 2 == 0:
		c.line(
			14,
			Renderer.VIEW + 37,
			44,
			Renderer.VIEW + 37,
			Color(214 / 255.0, 74 / 255.0, 48 / 255.0),
			2
		)
	number(c, amount, 77, Renderer.VIEW + 23, amount == "0")
	if Weapons.CAPACITY[slot] > 0 and armory.loaded[slot] == 0 and armory.reserve[slot] > 0:
		text(c, "RELOAD", 77, Renderer.VIEW + 36, "mini", AMBER, true, false)
	for i in 2:
		var name := "key_brass" if i == 0 else "key_steel"
		var cx := 111 + 8 * i
		var cy := Renderer.VIEW + 28 + 3 * i
		if game.keys.has(name):
			var image := icon(name, 9, 12)
			c.blit_rgba(
				image["data"],
				image["w"],
				image["h"],
				cx - image["w"] / 2,
				cy - image["h"] / 2,
				"icon|%s|9|12" % name
			)
		else:
			c.circle(cx, cy, 2, Color(68 / 255.0, 53 / 255.0, 43 / 255.0), false)
			c.line(cx, cy, cx, cy + 4, Color(68 / 255.0, 53 / 255.0, 43 / 255.0))
	_draw_face(c, game.face_name())
	if game.hud_style:
		gauge(c, 176, Renderer.VIEW + 10, "GUT", game.player.gut)
		gauge(c, 222, Renderer.VIEW + 10, "DRUNK", game.player.drunk)
	else:
		meter(
			c,
			176,
			Renderer.VIEW + 12,
			"GUT",
			game.player.gut,
			[
				Color(104 / 255.0, 132 / 255.0, 65 / 255.0),
				Color(155 / 255.0, 149 / 255.0, 67 / 255.0),
				Color(188 / 255.0, 146 / 255.0, 65 / 255.0)
			]
		)
		meter(
			c,
			176,
			Renderer.VIEW + 27,
			"DRUNK",
			game.player.drunk,
			[
				Color(180 / 255.0, 131 / 255.0, 54 / 255.0),
				Color(193 / 255.0, 100 / 255.0, 46 / 255.0),
				Color(182 / 255.0, 60 / 255.0, 46 / 255.0)
			]
		)
	var active: String = ITEMS[game.inventory_slot]
	blit_icon(c, active, 13, 13, 283, Renderer.VIEW + 27)
	var count: int = game.inventory.get(active, 0)
	text(
		c,
		str(count),
		300,
		Renderer.VIEW + 24,
		"body",
		AMBER if count else Color(191 / 255.0, 161 / 255.0, 119 / 255.0),
		true,
		true
	)
	text(c, SHORT_LABELS[game.inventory_slot], 291, Renderer.VIEW + 34, "mini", INK, true, false)


func _draw_face(c: Canvas, face_name: String) -> void:
	var scaled: Dictionary = face_cache.get(face_name, {})
	if scaled.is_empty():
		var art := assets.art("face_" + face_name)
		var w: int = art["w"]
		var h: int = art["h"]
		var data: PackedByteArray = art["data"]
		var x0 := w
		var y0 := h
		var x1 := -1
		var y1 := -1
		for y in h:
			for x in w:
				if data[(y * w + x) * 4 + 3] >= 128:
					x0 = mini(x0, x)
					x1 = maxi(x1, x)
					y0 = mini(y0, y)
					y1 = maxi(y1, y)
		scaled = {"w": 0, "h": 0, "data": PackedByteArray(), "x": 0, "y": 0}
		if x1 >= x0 and y1 >= y0:
			var cw := x1 - x0 + 1
			var ch := y1 - y0 + 1
			var tw := maxi(1, int(round(cw * 35.0 / ch)))
			var sub := _crop(data, w, x0, y0, cw, ch)
			scaled = {
				"w": tw,
				"h": 35,
				"data": SmoothScale.rgba(sub, cw, ch, tw, 35),
				"x": 20 - tw / 2,
				"y": 18 - 35 / 2
			}
		face_cache[face_name] = scaled
	if int(scaled["w"]) > 0:
		c.blit_rgba(
			scaled["data"],
			int(scaled["w"]),
			int(scaled["h"]),
			129 + int(scaled["x"]),
			Renderer.VIEW + 7 + int(scaled["y"]),
			"face|" + face_name
		)


# ---------------------------------------------------------------- menus


func title(c: Canvas, index: int, entries: PackedStringArray, note := "") -> void:
	_blit_art(c, "title_backdrop", 0, 0)
	_blit_art(c, "title_logo", 9, 9)
	panel(c, 16, 85, 154, 14, Color(42 / 255.0, 28 / 255.0, 21 / 255.0))
	text(c, "THE HICKSTON INCIDENT", 23, 89, "body", INK, false, false)
	var row := TITLE_ROW - (1 if entries.size() > 9 else 0)
	panel(
		c,
		16,
		100,
		174,
		entries.size() * row + 3,
		Color(38 / 255.0, 26 / 255.0, 22 / 255.0),
		Color(115 / 255.0, 79 / 255.0, 53 / 255.0)
	)
	for i in entries.size():
		var y := TITLE_FIRST + row * i
		if i == index:
			c.fill_rect(17, y, 172, row, Color(94 / 255.0, 56 / 255.0, 31 / 255.0))
			c.line(17, y, 188, y, Color(181 / 255.0, 125 / 255.0, 72 / 255.0))
			text(c, ">", 24, y + 1, "body", AMBER)
		text(c, entries[i], 37, y + 1, "body", AMBER if i == index else INK)
	if note != "":
		banner(c, note, 185)
	else:
		panel(c, 16, 187, 123, 12, Color(37 / 255.0, 26 / 255.0, 21 / 255.0))
		text(c, "ARROWS / ENTER", 22, 190, "body", INK, false, false)


func intermission(c: Canvas, game: Game) -> void:
	var following := Campaign.next_level(game.level.id)
	if following == "" and not game.history.is_empty() and not game.replay:
		campaign_report(c, game)
		return
	_blit_art(c, "title_backdrop", 0, 0)
	panel(c, 10, 9, 211, 177)
	var ys := [20, 38]
	for i in mini(2, game.level.heading.size()):
		text(c, game.level.heading[i], 21, ys[i], "heading", AMBER)
	text(c, game.level.title, 21, 61, "body", INK)
	c.line(21, 72, 208, 72, Color(135 / 255.0, 95 / 255.0, 63 / 255.0))
	var minutes := int(game.clock) / 60
	var seconds := int(game.clock) % 60
	var rows := [
		["VARMINTS", "%02d / %02d" % [game.kills, game.total_kills]],
		["SECRETS", "%02d / %02d" % [game.secrets, game.total_secrets]],
		["TIME", "%02d:%02d" % [minutes, seconds]]
	]
	# Features add their own rows (features.gd); room for one more.
	rows.append_array(Features.tally_rows(game).slice(0, 1))
	var gap := 18 if rows.size() <= 3 else 16
	# The rows come down one at a time with a thud, then the ribbon (tally.gd).
	var show = game.features.get("tally")
	var shown: int = show.rows_shown(rows.size()) if show != null else rows.size() + 1
	for i in mini(shown, rows.size()):
		var y := 79 + i * gap
		c.fill_rect(21, y, 187, 15, Color(30 / 255.0, 21 / 255.0, 17 / 255.0))
		text(c, String(rows[i][0]), 26, y + 4, "body", INK)
		text(c, String(rows[i][1]), 202, y + 4, "body", AMBER, false, true, true)
	text(c, game.level.ending, 22, 142 if rows.size() <= 3 else 146, "body", AMBER)
	if show != null and shown > rows.size():
		_ribbon(c, show.ribbon())
	var action := (
		"ENTER  CONTINUE TO CROSSROADS"
		if following != "" and not game.replay
		else "ENTER  RETURN TO TITLE"
	)
	text(c, action, 22, 165, "body", INK)


## The county fair ribbon pinned beside the tally: how the chapter went.
func _ribbon(c: Canvas, word: String) -> void:
	var red := Color(150 / 255.0, 30 / 255.0, 24 / 255.0)
	var gold := Color(236 / 255.0, 196 / 255.0, 104 / 255.0)
	c.fill_rect(229, 58, 84, 34, Color(.08, .05, .04))
	c.fill_rect(228, 56, 84, 34, red)
	c.fill_rect(230, 58, 80, 1, gold)
	c.fill_rect(230, 87, 80, 1, gold)
	text(c, "RANKED", 270, 61, "mini", gold, true)
	text(c, word, 270, 72, "body", INK, true)
	# The ribbon's two tails.
	for x in [248, 288]:
		c.fill_rect(x, 90, 8, 14, red)
		c.fill_rect(x + 2, 104, 4, 3, red)


## After the last chapter: the true finale, the campaign's tally and the
## credits (finale.gd).
func campaign_report(c: Canvas, game: Game) -> void:
	_blit_art(c, "title_backdrop", 0, 0)
	Finale.draw(c, game)


func _blit_art(c: Canvas, name: String, x: int, y: int) -> void:
	var art := assets.art(name)
	c.blit_rgba(art["data"], art["w"], art["h"], x, y, "art|" + name)
