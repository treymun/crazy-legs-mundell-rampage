## The chapter openers' pictures (src/opener.gd), made once per opener from
## the game's own letters and cels: the title card in its chapter's style (a
## hand-painted plank sign, a rusted tin sign, a carnival marquee, a
## checkered race board, a B-movie title), and the boss in silhouette with the
## light behind him. Each comes back as an Image; nothing here touches play.
## The dice for grain, rust and drips are seeded by the chapter's name, so a
## card looks the same every time.
class_name OpenerArt
extends RefCounted

## The card styles: board, trim, letters and their colours. A chapter's
## "card" picks one (openers.json).
const STYLES := {
	"plank":
	{
		"board": "plank",
		"trim": "nails",
		"letters": "paint",
		"face": [118, 76, 44],
		"ink": [242, 228, 192],
		"ink_low": [222, 204, 160],
		"ink2": [236, 84, 56],
	},
	"swamp":
	{
		"board": "plank",
		"trim": "nails",
		"letters": "paint",
		"drips": true,
		"face": [70, 84, 62],
		"ink": [236, 232, 204],
		"ink_low": [206, 214, 176],
		"ink2": [232, 178, 64],
	},
	"tin":
	{
		"board": "tin",
		"trim": "rivets",
		"letters": "stencil",
		"face": [150, 118, 82],
		"ink": [30, 22, 18],
		"ink_low": [48, 30, 22],
		"ink2": [214, 52, 36],
	},
	"marquee":
	{
		"board": "panel",
		"trim": "bulbs",
		"letters": "logo",
		"face": [70, 20, 22],
		"ink": [255, 226, 120],
		"ink_low": [236, 112, 40],
		"ink2": [250, 232, 196],
	},
	"checker":
	{
		"board": "panel",
		"trim": "checker",
		"letters": "logo",
		"face": [26, 22, 22],
		"ink": [255, 236, 140],
		"ink_low": [240, 90, 36],
		"ink2": [250, 240, 220],
	},
	"saucer":
	{
		"board": "none",
		"trim": "none",
		"letters": "bmovie",
		"face": [0, 0, 0],
		"ink": [214, 255, 120],
		"ink_low": [64, 196, 70],
		"ink2": [236, 250, 220],
	},
}
const SHADE := Color(27 / 255.0, 19 / 255.0, 15 / 255.0)
## The widest a card's title may be, in canvas pixels, before its letters
## drop from three times the body font's size to two.
const WIDE := 262


static func style_of(name: String) -> Dictionary:
	return STYLES.get(name, STYLES["plank"])


static func color_of(v: Variant) -> Color:
	var a: Array = v
	var r: float = a[0]
	var g: float = a[1]
	var b: float = a[2]
	return Color(r / 255.0, g / 255.0, b / 255.0)


## The letters of `text` in the game's own font, `k` canvas pixels a font
## pixel, as a mask (1 where a letter is) with its size; `jitter` lifts or
## drops each letter a pixel by the dice (a painter's hand).
static func letters(text: String, k: int, jitter := 0, seed_text := "") -> Dictionary:
	var dice := RandomNumberGenerator.new()
	dice.seed = hash(seed_text + text)
	var w := PixelType.text_width(text, "body") * k + 2
	var h := 7 * k + jitter * 2 + 2
	var bits := PackedByteArray()
	bits.resize(w * h)
	var x := 1
	for ch in text.to_upper():
		var info := PixelType.glyph(ch, false)
		var rows: Array = info[0]
		var glyph_w: int = info[1]
		var lift := dice.randi_range(-jitter, jitter) if jitter > 0 else 0
		var n := rows.size()
		for yi in n:
			var top := yi * 7 * k / n
			var bottom := (yi + 1) * 7 * k / n
			var row_bits: int = rows[yi]
			for col in glyph_w:
				if row_bits & (1 << (glyph_w - col - 1)):
					for yy in range(top, bottom):
						for xx in k:
							var px := x + col * k + xx
							var py := 1 + jitter + lift + yy
							if px >= 0 and px < w and py >= 0 and py < h:
								bits[py * w + px] = 1
		x += (glyph_w + 1) * k
	return {"w": w, "h": h, "bits": bits}


## Paint a letter mask onto `img` at (ox, oy) in the style's way.
static func paint_letters(
	img: Image,
	mask: Dictionary,
	ox: int,
	oy: int,
	look: String,
	top: Color,
	low: Color,
	dice_seed: int
) -> void:
	var w: int = mask["w"]
	var h: int = mask["h"]
	var bits: PackedByteArray = mask["bits"]
	var dice := RandomNumberGenerator.new()
	dice.seed = dice_seed
	var dark := SHADE
	if look == "outline":
		# Small letters: a dark outline all round so they read on any board.
		_stamp(img, bits, w, h, ox, oy, dark, 1)
	elif look == "logo" or look == "bmovie":
		# A deep extrusion down and right, then a dark outline round it all.
		var depth := 4 if look == "bmovie" else 2
		var deep := low.darkened(.55) if look == "bmovie" else low.darkened(.45)
		for d in range(depth, 0, -1):
			_stamp(img, bits, w, h, ox + d, oy + d, deep.darkened(.12 * d), 0)
		_stamp(img, bits, w, h, ox, oy, dark, 1)
		for d in range(depth, 0, -1):
			_stamp(img, bits, w, h, ox + d, oy + d, deep, 0)
	elif look == "stencil":
		# Sprayed through a stencil: a soft overspray round the letters.
		for y in range(-2, h + 2):
			for x in range(-2, w + 2):
				if _near(bits, w, h, x, y, 2) and not _at(bits, w, h, x, y):
					if dice.randf() < .16:
						_blend(img, ox + x, oy + y, top, .55)
	else:
		# Brush paint: a faint shadow where the paint sits thick.
		_stamp(img, bits, w, h, ox + 1, oy + 1, Color(0, 0, 0, .35), 0)
	for y in h:
		var share := float(y) / maxf(1.0, h - 1.0)
		var ink := top.lerp(low, share)
		if look == "logo" or look == "bmovie":
			# A bright band across the top third, like the title's lettering.
			ink = top.lerp(Color(1, 1, .92), .35) if share < .28 else top.lerp(low, share)
		for x in w:
			if bits[y * w + x] == 0:
				continue
			var col := ink
			if look == "paint":
				# Brush strokes: some rows a shade lighter or darker, worn spots.
				col = col.darkened(.06) if (y + x / 3) % 4 == 0 else col
				if dice.randf() < .05:
					col = col.darkened(.22)
			elif look == "stencil" and dice.randf() < .08:
				col = col.lightened(.25)
			img.set_pixel(ox + x, oy + y, col)


## Paint drips under a mask's letters (the bayou's sign).
static func drips(
	img: Image, mask: Dictionary, ox: int, oy: int, ink: Color, dice_seed: int
) -> void:
	var w: int = mask["w"]
	var h: int = mask["h"]
	var bits: PackedByteArray = mask["bits"]
	var dice := RandomNumberGenerator.new()
	dice.seed = dice_seed
	for x in w:
		for y in range(h - 1, -1, -1):
			if bits[y * w + x] == 0:
				continue
			if dice.randf() < .13:
				var run := dice.randi_range(1, 5)
				for d in range(1, run + 1):
					_blend(img, ox + x, oy + y + d, ink, 1.0 - d * .12)
			break


static func _at(bits: PackedByteArray, w: int, h: int, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h and bits[y * w + x] != 0


static func _near(bits: PackedByteArray, w: int, h: int, x: int, y: int, r: int) -> bool:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if _at(bits, w, h, x + dx, y + dy):
				return true
	return false


## The mask's shape at (ox, oy) in one colour, grown by `grow` pixels.
static func _stamp(
	img: Image, bits: PackedByteArray, w: int, h: int, ox: int, oy: int, col: Color, grow: int
) -> void:
	for y in range(-grow, h + grow):
		for x in range(-grow, w + grow):
			var hit := _at(bits, w, h, x, y) if grow == 0 else _near(bits, w, h, x, y, grow)
			if hit:
				_blend(img, ox + x, oy + y, col, col.a)


static func _blend(img: Image, x: int, y: int, col: Color, a: float) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height() or a <= 0.0:
		return
	var under := img.get_pixel(x, y)
	var out := Color(
		lerpf(under.r, col.r, a), lerpf(under.g, col.g, a), lerpf(under.b, col.b, a), 1.0
	)
	out.a = maxf(under.a, a)
	if under.a <= 0.0:
		out = Color(col.r, col.g, col.b, a)
	img.set_pixel(x, y, out)


# ------------------------------------------------------------------ the card


## The title card: the board in the style's way with CHAPTER <N> and the
## chapter's title on it. Returns {image, bulbs: [[x, y]...] (the marquee's,
## lit by the opener frame by frame), ropes: [x, x] (where a hung sign's
## ropes meet it)}.
static func card(
	style_name: String, number: String, title: String, seed_text: String
) -> Dictionary:
	var st := style_of(style_name)
	var board := str(st["board"])
	var look := str(st["letters"])
	var k := 3 if PixelType.text_width(title, "body") * 3 <= WIDE else 2
	var jitter := 1 if look == "paint" else 0
	var big := letters(title, k, jitter, seed_text)
	var small := letters(number, 1, 0, seed_text)
	var pad := 12 if board != "none" else 4
	var big_w: int = big["w"]
	var big_h: int = big["h"]
	var small_w: int = small["w"]
	var small_h: int = small["h"]
	var w := maxi(big_w + pad * 2 + 4, small_w + pad * 2)
	var top_pad := 7 if board != "none" else 2
	var gap := 4
	var h := top_pad + small_h + gap + big_h + (8 if board != "none" else 6)
	var img := Image.create_empty(w + 2, h + 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var dice := RandomNumberGenerator.new()
	dice.seed = hash(seed_text)
	var face := color_of(st["face"])
	var bulbs: Array = []
	match board:
		"plank":
			_plank(img, w, h, face, dice)
		"tin":
			_tin(img, w, h, face, dice)
		"panel":
			_panel(img, w, h, face, str(st["trim"]), bulbs)
	if str(st["trim"]) == "nails":
		for at: Vector2i in [
			Vector2i(4, 4), Vector2i(w - 6, 4), Vector2i(4, h - 6), Vector2i(w - 6, h - 6)
		]:
			_stud(img, at.x, at.y, Color(.42, .4, .38), true)
	elif str(st["trim"]) == "rivets":
		for at: Vector2i in [
			Vector2i(4, 4),
			Vector2i(w / 2, 3),
			Vector2i(w - 6, 4),
			Vector2i(4, h - 6),
			Vector2i(w / 2, h - 5),
			Vector2i(w - 6, h - 6)
		]:
			_stud(img, at.x, at.y, Color(.5, .44, .38), false)
	var ink := color_of(st["ink"])
	var ink_low := color_of(st["ink_low"])
	var ink2 := color_of(st["ink2"])
	var sx := (w - small_w) / 2
	var small_look := "outline"
	paint_letters(img, small, sx, top_pad, small_look, ink2, ink2.darkened(.2), hash(seed_text) + 7)
	var bx := (w - big_w) / 2
	var by := top_pad + small_h + gap
	paint_letters(img, big, bx, by, look, ink, ink_low, hash(seed_text) + 11)
	if st.get("drips", false):
		drips(img, big, bx, by, ink_low, hash(seed_text) + 13)
	return {"image": img, "bulbs": bulbs, "ropes": [10, w - 11], "board": board != "none"}


## Three planks across with seams, grain and a darker rim.
static func _plank(img: Image, w: int, h: int, face: Color, dice: RandomNumberGenerator) -> void:
	var planks := 3
	for p in planks:
		var y0 := h * p / planks
		var y1 := h * (p + 1) / planks
		var tone := face.lightened(dice.randf_range(-.04, .1)) if p % 2 == 0 else face.darkened(.08)
		for y in range(y0, y1):
			for x in w:
				img.set_pixel(x, y, tone)
		# Grain: long thin streaks a shade off the plank's colour.
		for _i in w / 5:
			var gy := dice.randi_range(y0 + 1, maxi(y0 + 1, y1 - 2))
			var gx := dice.randi_range(0, w - 1)
			var run := dice.randi_range(8, 40)
			var streak := tone.darkened(.16) if dice.randf() < .7 else tone.lightened(.08)
			for x in range(gx, mini(w, gx + run)):
				img.set_pixel(x, gy, streak)
		if p > 0:
			for x in w:
				img.set_pixel(x, y0, face.darkened(.55))
	# Weathered: the odd knot and a darker rim all round.
	for _i in 3:
		var kx := dice.randi_range(6, w - 8)
		var ky := dice.randi_range(3, h - 4)
		_blend(img, kx, ky, face.darkened(.5), 1.0)
		_blend(img, kx + 1, ky, face.darkened(.35), 1.0)
	_rim(img, w, h, face.darkened(.6), face.lightened(.12))


## Corrugated tin gone to rust: ribs, blotches, a bevelled edge.
static func _tin(img: Image, w: int, h: int, face: Color, dice: RandomNumberGenerator) -> void:
	for y in h:
		for x in w:
			var rib := x % 6
			var col := face.lightened(.1) if rib == 0 else (face.darkened(.1) if rib == 3 else face)
			img.set_pixel(x, y, col)
	var rust := Color(.46, .22, .1)
	for _i in w * h / 90:
		var cx := dice.randi_range(0, w - 1)
		var cy := dice.randi_range(0, h - 1)
		var r := dice.randi_range(1, 4)
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if dx * dx + dy * dy <= r * r and dice.randf() < .8:
					_blend(img, cx + dx, cy + dy, rust, dice.randf_range(.25, .6))
	# Rust running down from the top edge.
	for x in w:
		if dice.randf() < .2:
			var run := dice.randi_range(2, 9)
			for d in run:
				_blend(img, x, 1 + d, rust.darkened(.2), .55 - d * .05)
	_rim(img, w, h, face.darkened(.55), face.lightened(.28))


## A dark panel with a gold inner line: a marquee's bulbs sit round it (the
## places come back in `bulbs`), or a checkered strip runs top and bottom.
static func _panel(img: Image, w: int, h: int, face: Color, trim: String, bulbs: Array) -> void:
	for y in h:
		for x in w:
			img.set_pixel(x, y, face.darkened(.15 * float(y) / h))
	var gold := Color(.86, .66, .3)
	if trim == "checker":
		for y in 4:
			for x in w:
				var light := ((x / 4) + (y / 4)) % 2 == 0
				img.set_pixel(x, y + 1, Color(.94, .92, .86) if light else Color(.06, .05, .05))
				img.set_pixel(x, h - 5 + y, Color(.06, .05, .05) if light else Color(.94, .92, .86))
	else:
		for x in range(4, w - 4):
			img.set_pixel(x, 4, gold)
			img.set_pixel(x, h - 5, gold)
		for y in range(4, h - 4):
			img.set_pixel(4, y, gold)
			img.set_pixel(w - 5, y, gold)
		var step := 8
		for x in range(6, w - 4, step):
			bulbs.append([x, 1])
			bulbs.append([x, h - 3])
		for y in range(9, h - 6, step):
			bulbs.append([1, y])
			bulbs.append([w - 3, y])
	_rim(img, w, h, Color(.05, .03, .03), gold.darkened(.2))


static func _rim(img: Image, w: int, h: int, dark: Color, light: Color) -> void:
	for x in w:
		img.set_pixel(x, 0, light)
		img.set_pixel(x, h - 1, dark)
		_blend(img, x, h, Color(0, 0, 0, .6), .6)
		_blend(img, x + 1, h + 1, Color(0, 0, 0, .35), .35)
	for y in h:
		img.set_pixel(0, y, light)
		img.set_pixel(w - 1, y, dark)
		_blend(img, w, y + 1, Color(0, 0, 0, .6), .6)


## A nail head or a rivet: a dark ring, a lit top.
static func _stud(img: Image, x: int, y: int, col: Color, square: bool) -> void:
	_blend(img, x, y, col.lightened(.45), 1.0)
	_blend(img, x + 1, y, col, 1.0)
	_blend(img, x, y + 1, col, 1.0)
	_blend(img, x + 1, y + 1, col.darkened(.5), 1.0)
	if not square:
		_blend(img, x + 2, y + 1, Color(0, 0, 0, .4), .4)
		_blend(img, x + 1, y + 2, Color(0, 0, 0, .4), .4)


# ------------------------------------------------------------------ the boss


## The boss's cel as a silhouette `tall` canvas pixels high: near-black, with
## a thin rim of the light catching his edges (none along the bottom).
static func silhouette(cel: Dictionary, tall: int, rim: Color) -> Image:
	var cw: int = cel["w"]
	var ch: int = cel["h"]
	var data: PackedByteArray = cel["data"]
	var src := Image.create_from_data(cw, ch, false, Image.FORMAT_RGBA8, data)
	var used := src.get_used_rect()
	if used.size.x < 2 or used.size.y < 2:
		used = Rect2i(0, 0, cw, ch)
	src = src.get_region(used)
	var wide := maxi(2, roundi(used.size.x * float(tall) / used.size.y))
	src.resize(wide, tall, Image.INTERPOLATE_BILINEAR)
	var out := Image.create_empty(wide + 2, tall + 1, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var inside := PackedByteArray()
	inside.resize(wide * tall)
	for y in tall:
		for x in wide:
			inside[y * wide + x] = 1 if src.get_pixel(x, y).a >= .5 else 0
	var body := Color(.035, .028, .03)
	for y in tall:
		for x in wide:
			if inside[y * wide + x] == 0:
				continue
			var edge := false
			for d: Vector2i in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]:
				var nx := x + d.x
				var ny := y + d.y
				if nx < 0 or nx >= wide or ny < 0 or inside[ny * wide + nx] == 0:
					edge = true
			var lit := float(tall - y) / tall
			out.set_pixel(x + 1, y, rim.lerp(body, .25 + .45 * (1.0 - lit)) if edge else body)
	return out


## The light behind the boss: `kind` cone (a beam from above), glow (a fire
## behind), door (a lit doorway), moon (a big moon), headlights (two lamps),
## flasher (one side of a light bar: `side` -1 or 1). Made at half the view's
## size (160 x 64), drawn at twice that.
static func backlight(kind: String, col: Color, side := 0) -> Image:
	var w := 160
	var h := 64
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var u := (x - w * .5 + .5) / (w * .5)  # -1 .. 1 across
			var v := (y + .5) / h  # 0 top .. 1 the feet
			var lit := _light(kind, u, v, side)
			if lit <= .004:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var hot := col.lerp(Color(1, 1, .96), clampf(lit * lit * lit, 0.0, .8))
			img.set_pixel(x, y, Color(hot.r, hot.g, hot.b, clampf(lit, 0.0, 1.0)))
	return img


static func _light(kind: String, u: float, v: float, side: int) -> float:
	var lit := 0.0
	match kind:
		"cone":
			var half := lerpf(.1, .42, v)
			var across := 1.0 - absf(u) / half
			if across > 0.0:
				lit = pow(across, .7) * lerpf(.55, .95, v)
			lit = maxf(lit, _blob(u, v, 0.0, .97, .5, .07) * .9)
		"glow":
			lit = pow(_blob(u, v, 0.0, .58, .8, .62), 1.4)
		"door":
			var dx := absf(u) - .26
			var dy := maxf(.06 - v, 0.0)
			var out := maxf(dx, 0.0) * 3.0 + dy * 6.0
			lit = .95 if out <= 0.0 else .95 * exp(-out * 6.0)
			lit = maxf(lit, _blob(u, v, 0.0, .99, .7, .05) * .7)
		"moon":
			var d := Vector2(u * 2.5, (v - .4) * 1.0).length()
			lit = .95 if d < .5 else .95 * exp(-(d - .5) * 5.0) * .55
		"headlights":
			for sx: float in [-.34, .34]:
				lit = maxf(lit, pow(_blob(u, v, sx, .8, .13, .3), .8))
				lit = maxf(lit, _blob(u, v, sx, .8, .5, .9) * .35)
			lit = maxf(lit, _blob(u, v, 0.0, .86, 1.2, .05) * .5)
		"flasher":
			lit = pow(_blob(u, v, .45 * side, .42, .7, .7), 1.2)
	return clampf(lit, 0.0, 1.0)


## 1 at (cx, cy) falling to 0 at an ellipse of radii (rx, ry).
static func _blob(u: float, v: float, cx: float, cy: float, rx: float, ry: float) -> float:
	var d := Vector2((u - cx) / rx, (v - cy) / ry).length()
	return clampf(1.0 - d, 0.0, 1.0)
