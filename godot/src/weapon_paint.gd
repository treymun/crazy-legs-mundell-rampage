## The viewmodel's pixel work, moved out of weapons.gd: lighting and scaling a
## gun cel (grade_cel), its rim and the composed cel, and the blits, fills and
## lines the Armory draws the gun, its flashes and the fuse bar with into the
## 320x200 frame. Static, so the warming thread can use them (Armory._warm_jobs).
class_name WeaponPaint
extends RefCounted


static func blit_rgba(frame: PackedByteArray, image: Dictionary, x: int, y: int) -> void:
	var w: int = image["w"]
	var h: int = image["h"]
	var data: PackedByteArray = image["data"]
	var spans: Variant = image.get("spans")
	var cv := Weapons.covering
	var cover := Weapons.cover
	if spans == null:
		for yy in h:
			var ty := y + yy
			if ty < 0 or ty >= View.VIEW:
				continue
			var row := yy * w * 4
			for xx in w:
				var tx := x + xx
				if tx < 0 or tx >= View.WIDTH:
					continue
				var sp := row + xx * 4
				var a := data[sp + 3]
				if a == 0:
					continue
				var o := (ty * View.WIDTH + tx) * 3
				if cv:
					var p := o / 3
					cover[p] = (255 if a == 255 else cover[p] + (((255 - cover[p]) * a + 255) >> 8))
				if a == 255:
					frame[o] = data[sp]
					frame[o + 1] = data[sp + 1]
					frame[o + 2] = data[sp + 2]
				else:
					var k := a
					frame[o] = clampi(
						frame[o] + (((data[sp] - frame[o]) * k + data[sp]) >> 8), 0, 255
					)
					frame[o + 1] = clampi(
						frame[o + 1] + (((data[sp + 1] - frame[o + 1]) * k + data[sp + 1]) >> 8),
						0,
						255
					)
					frame[o + 2] = clampi(
						frame[o + 2] + (((data[sp + 2] - frame[o + 2]) * k + data[sp + 2]) >> 8),
						0,
						255
					)
		return
	var ty0 := maxi(y, 0)
	var ty1 := mini(y + h, View.VIEW)
	for yy in range(ty0 - y, ty1 - y):
		var first: int = spans[yy * 2]
		if first < 0:
			continue
		var last: int = spans[yy * 2 + 1]
		var ty := y + yy
		var row := yy * w * 4
		var x0 := maxi(x + first, 0)
		var x1 := mini(x + last, View.WIDTH - 1)
		var o := (ty * View.WIDTH + x0) * 3
		var sp := row + (x0 - x) * 4
		for tx in range(x0, x1 + 1):
			var a := data[sp + 3]
			if a != 0:
				if cv:
					var p := o / 3
					cover[p] = (255 if a == 255 else cover[p] + (((255 - cover[p]) * a + 255) >> 8))
				if a == 255:
					frame[o] = data[sp]
					frame[o + 1] = data[sp + 1]
					frame[o + 2] = data[sp + 2]
				else:
					var k := a
					frame[o] = clampi(
						frame[o] + (((data[sp] - frame[o]) * k + data[sp]) >> 8), 0, 255
					)
					frame[o + 1] = clampi(
						frame[o + 1] + (((data[sp + 1] - frame[o + 1]) * k + data[sp + 1]) >> 8),
						0,
						255
					)
					frame[o + 2] = clampi(
						frame[o + 2] + (((data[sp + 2] - frame[o + 2]) * k + data[sp + 2]) >> 8),
						0,
						255
					)
			o += 3
			sp += 4


## Multiply the cel by the graded light, add the warm floor, then smoothscale.
## Where a cel has anything in it (one pixel of margin), found once per cel.
static func opaque_box(
	boxes: Dictionary, name: String, data: PackedByteArray, w: int, h: int
) -> Rect2i:
	if boxes.has(name):
		return boxes[name]
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in h:
		var row := y * w * 4 + 3
		for x in w:
			if data[row + x * 4] != 0:
				if x < x0:
					x0 = x
				if x > x1:
					x1 = x
				if y < y0:
					y0 = y
				y1 = y
	var box := Rect2i(0, 0, 0, 0)
	if x1 >= x0:
		x0 = maxi(0, x0 - 1)
		y0 = maxi(0, y0 - 1)
		box = Rect2i(x0, y0, mini(w - 1, x1 + 1) - x0 + 1, mini(h - 1, y1 + 1) - y0 + 1)
	boxes[name] = box
	return box


static func grade_cel(
	boxes: Dictionary, art: Dictionary, name: String, s: float, level: int
) -> Dictionary:
	var w: int = art["w"]
	var h: int = art["h"]
	var data: PackedByteArray = art["data"]
	var tw := roundi(Weapons.GUN_W * s)
	var th := roundi(Weapons.GUN_H * s)
	var spans := PackedInt32Array()
	spans.resize(th * 2)
	spans.fill(-1)
	var box := opaque_box(boxes, name, data, w, h)
	var out := PackedByteArray()
	if box.size.x <= 0:
		out.resize(tw * th * 4)
		return {"w": tw, "h": th, "data": out, "spans": spans}
	var cw := box.size.x
	var ch := box.size.y
	var mul_r := mini(255, level * 15 + 11)
	var mul_g := mini(255, level * 15 + 8)
	var mul_b := mini(255, level * 16 + 3)
	var crop := PackedByteArray()
	crop.resize(cw * ch * 4)
	for y in ch:
		var i := ((box.position.y + y) * w + box.position.x) * 4
		var o := y * cw * 4
		for _x in cw:
			var da := data[i + 3]
			if da != 0:
				var dr := data[i]
				var dg := data[i + 1]
				var db := data[i + 2]
				# pygame BLEND_RGBA_MULT: ((d * s) + 255) >> 8, or 0 when either is 0;
				# then BLEND_RGB_ADD: a saturating add that leaves alpha alone.
				crop[o] = mini(255, (((dr * mul_r) + 255) >> 8 if dr else 0) + 11)
				crop[o + 1] = mini(255, (((dg * mul_g) + 255) >> 8 if dg else 0) + 8)
				crop[o + 2] = mini(255, (((db * mul_b) + 255) >> 8 if db else 0) + 4)
				crop[o + 3] = ((da * 255) + 255) >> 8
			else:
				crop[o] = 11
				crop[o + 1] = 8
				crop[o + 2] = 4
			i += 4
			o += 4
	var sw := clampi(roundi(cw * s), 1, tw)
	var sh := clampi(roundi(ch * s), 1, th)
	var small := SmoothScale.rgba(crop, cw, ch, sw, sh)
	var ox := clampi(roundi(box.position.x * s), 0, tw - sw)
	var oy := clampi(roundi(box.position.y * s), 0, th - sh)
	var left := PackedByteArray()
	left.resize(ox * 4)
	var right := PackedByteArray()
	right.resize((tw - ox - sw) * 4)
	out.resize(oy * tw * 4)
	for y in sh:
		out.append_array(left)
		out.append_array(small.slice(y * sw * 4, (y + 1) * sw * 4))
		out.append_array(right)
		var first := -1
		var last := -1
		var row := y * sw * 4 + 3
		for x in sw:
			if small[row + x * 4] != 0:
				if first < 0:
					first = x
				last = x
		if first >= 0:
			spans[(oy + y) * 2] = ox + first
			spans[(oy + y) * 2 + 1] = ox + last
	out.resize(tw * th * 4)
	return {"w": tw, "h": th, "data": out, "spans": spans}


## mask.from_surface(image).to_surface((205,168,116,42)) over the scaled cel.
static func rim_of(image: Dictionary) -> Dictionary:
	var w: int = image["w"]
	var h: int = image["h"]
	var data: PackedByteArray = image["data"]
	var spans: PackedInt32Array = image["spans"]
	var out := PackedByteArray()
	out.resize(w * h * 4)
	for y in h:
		var first := spans[y * 2]
		if first < 0:
			continue
		for x in range(first, spans[y * 2 + 1] + 1):
			var i := (y * w + x) * 4
			if data[i + 3] >= 128:
				out[i] = 205
				out[i + 1] = 168
				out[i + 2] = 116
				out[i + 3] = 42
	return {"w": w, "h": h, "data": out, "spans": spans}


## The cel with its rim under it, composed once: for each row the first
## column painted, then the run of colour and coverage from there. Laid into
## the empty layer canvas (_lay_cel) it gives exactly what blitting the rim
## and then the cel would have, at a fraction of the cost.
static func compose(image: Dictionary, rim: Dictionary) -> Dictionary:
	var w: int = image["w"]
	var h: int = image["h"]
	var cel: PackedByteArray = image["data"]
	var edge: PackedByteArray = rim["data"]
	var first := PackedInt32Array()
	first.resize(h + 1)
	var colours: Array = []
	var covers: Array = []
	var row_rgb := PackedByteArray()
	row_rgb.resize(w * 3)
	var row_cover := PackedByteArray()
	row_cover.resize(w)
	for y in h + 1:
		row_rgb.fill(0)
		row_cover.fill(0)
		var lo := w
		var hi := -1
		for x in w:
			var r := 0
			var g := 0
			var b := 0
			var c := 0
			if y < h:
				# The rim sits one row above the cel.
				var e := (y * w + x) * 4
				var a := edge[e + 3]
				if a == 255:
					r = edge[e]
					g = edge[e + 1]
					b = edge[e + 2]
					c = 255
				elif a != 0:
					r = clampi((edge[e] * a + edge[e]) >> 8, 0, 255)
					g = clampi((edge[e + 1] * a + edge[e + 1]) >> 8, 0, 255)
					b = clampi((edge[e + 2] * a + edge[e + 2]) >> 8, 0, 255)
					c = (255 * a + 255) >> 8
			if y >= 1:
				var q := ((y - 1) * w + x) * 4
				var a := cel[q + 3]
				if a == 255:
					r = cel[q]
					g = cel[q + 1]
					b = cel[q + 2]
					c = 255
				elif a != 0:
					r = clampi(r + (((cel[q] - r) * a + cel[q]) >> 8), 0, 255)
					g = clampi(g + (((cel[q + 1] - g) * a + cel[q + 1]) >> 8), 0, 255)
					b = clampi(b + (((cel[q + 2] - b) * a + cel[q + 2]) >> 8), 0, 255)
					c = c + (((255 - c) * a + 255) >> 8)
			if c == 0:
				continue
			row_rgb[x * 3] = r
			row_rgb[x * 3 + 1] = g
			row_rgb[x * 3 + 2] = b
			row_cover[x] = c
			if x < lo:
				lo = x
			hi = x
		if hi < 0:
			first[y] = -1
			colours.append(PackedByteArray())
			covers.append(PackedByteArray())
		else:
			first[y] = lo
			colours.append(row_rgb.slice(lo * 3, (hi + 1) * 3))
			covers.append(row_cover.slice(lo, hi + 1))
	return {"first": first, "rgb": colours, "cover": covers}


## Lay a composed cel (_compose) into the still empty layer canvas, its top
## left at x, y: each row's run goes in with one copy.
static func lay_cel(canvas: Canvas, whole: Dictionary, x: int, y: int) -> void:
	var first: PackedInt32Array = whole["first"]
	var colours: Array = whole["rgb"]
	var covers: Array = whole["cover"]
	var pix := canvas.pixels
	var cov := canvas.cover
	var out := PackedByteArray()
	var out_cover := PackedByteArray()
	var done := 0
	for row in first.size():
		var ty := y + row
		if ty < 0 or first[row] < 0:
			continue
		if ty >= View.VIEW:
			break
		var run: PackedByteArray = covers[row]
		var left := x + first[row]
		var skip := maxi(0, -left)
		var stop := mini(run.size(), View.WIDTH - left)
		if skip >= stop:
			continue
		var at := ty * View.WIDTH + left + skip
		out.append_array(pix.slice(done * 3, at * 3))
		var hue: PackedByteArray = colours[row]
		out.append_array(hue.slice(skip * 3, stop * 3))
		out_cover.append_array(cov.slice(done, at))
		out_cover.append_array(run.slice(skip, stop))
		done = at + stop - skip
	out.append_array(pix.slice(done * 3))
	out_cover.append_array(cov.slice(done))
	canvas.pixels = out
	canvas.cover = out_cover


## Nearest-neighbour scale blit (pygame.transform.scale), alpha scaled.
## _blit_scaled, but adding light: a flash brightens what is behind it.
static func blit_glow(
	frame: PackedByteArray,
	art: Dictionary,
	tw: int,
	th: int,
	x: int,
	y: int,
	alpha: int,
	art_name := ""
) -> void:
	var w: int = art["w"]
	var h: int = art["h"]
	var data: PackedByteArray = art["data"]
	if tw <= 0 or th <= 0:
		return
	if Weapons.painter != null:
		Weapons.painter.gpu_item(Canvas.ITEM_ADD_VIEW)
		Weapons.painter.gpu_texture(
			Canvas.texture("art|" + art_name, data, w, h), x, y, tw, th, alpha
		)
		Weapons.painter.gpu_item(Canvas.ITEM_NORMAL_VIEW)
		return
	for ty in th:
		var gy := y + ty
		if gy < 0 or gy >= View.VIEW:
			continue
		var sy := clampi(ty * h / th, 0, h - 1)
		for tx in tw:
			var gx := x + tx
			if gx < 0 or gx >= View.WIDTH:
				continue
			var sp := (sy * w + clampi(tx * w / tw, 0, w - 1)) * 4
			var a := data[sp + 3] * alpha / 255
			if a == 0:
				continue
			var o := (gy * View.WIDTH + gx) * 3
			if Weapons.under:
				# What is already painted here (the gun) is in front of the flash.
				a = a * (255 - Weapons.cover[o / 3]) / 255
				if a == 0:
					continue
			frame[o] = mini(255, frame[o] + data[sp] * a / 255)
			frame[o + 1] = mini(255, frame[o + 1] + data[sp + 1] * a / 255)
			frame[o + 2] = mini(255, frame[o + 2] + data[sp + 2] * a / 255)


static func blit_scaled(
	frame: PackedByteArray,
	art: Dictionary,
	tw: int,
	th: int,
	x: int,
	y: int,
	alpha: int,
	art_name := ""
) -> void:
	var w: int = art["w"]
	var h: int = art["h"]
	var data: PackedByteArray = art["data"]
	if tw <= 0 or th <= 0:
		return
	if Weapons.painter != null:
		Weapons.painter.gpu_texture(
			Canvas.texture("art|" + art_name, data, w, h), x, y, tw, th, alpha
		)
		return
	for ty in th:
		var sy := clampi(ty * h / th, 0, h - 1)
		var gy := y + ty
		if gy < 0 or gy >= View.VIEW:
			continue
		for tx in tw:
			var sx := clampi(tx * w / tw, 0, w - 1)
			var gx := x + tx
			if gx < 0 or gx >= View.WIDTH:
				continue
			var sp := (sy * w + sx) * 4
			var a := data[sp + 3]
			if a == 0:
				continue
			if alpha < 255:
				a = a * alpha / 255
			var o := (gy * View.WIDTH + gx) * 3
			if Weapons.under:
				# Behind what is already painted: only what shows past it.
				var front := Weapons.cover[o / 3]
				var k := a * (255 - front) / 255
				if k != 0:
					frame[o] = mini(255, frame[o] + data[sp] * k / 255)
					frame[o + 1] = mini(255, frame[o + 1] + data[sp + 1] * k / 255)
					frame[o + 2] = mini(255, frame[o + 2] + data[sp + 2] * k / 255)
					Weapons.cover[o / 3] = mini(255, front + k)
				continue
			if Weapons.covering:
				var p := o / 3
				var had := Weapons.cover[p]
				Weapons.cover[p] = 255 if a == 255 else had + (((255 - had) * a + 255) >> 8)
			if a == 255:
				frame[o] = data[sp]
				frame[o + 1] = data[sp + 1]
				frame[o + 2] = data[sp + 2]
			else:
				frame[o] = clampi(frame[o] + (((data[sp] - frame[o]) * a + data[sp]) >> 8), 0, 255)
				frame[o + 1] = clampi(
					frame[o + 1] + (((data[sp + 1] - frame[o + 1]) * a + data[sp + 1]) >> 8), 0, 255
				)
				frame[o + 2] = clampi(
					frame[o + 2] + (((data[sp + 2] - frame[o + 2]) * a + data[sp + 2]) >> 8), 0, 255
				)


static func set_pixel(frame: PackedByteArray, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= View.WIDTH or y >= View.VIEW:
		return
	if Weapons.painter != null:
		Weapons.painter.set_pixel(
			x, y, roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0)
		)
		return
	var o := (y * View.WIDTH + x) * 3
	frame[o] = roundi(c.r * 255.0)
	frame[o + 1] = roundi(c.g * 255.0)
	frame[o + 2] = roundi(c.b * 255.0)
	if Weapons.covering:
		Weapons.cover[o / 3] = 255


static func fill_rect(frame: PackedByteArray, x: int, y: int, w: int, h: int, c: Color) -> void:
	var r := roundi(c.r * 255.0)
	var g := roundi(c.g * 255.0)
	var b := roundi(c.b * 255.0)
	if Weapons.painter != null:
		var x0 := maxi(0, x)
		var y0 := maxi(0, y)
		var x1 := mini(View.WIDTH, x + w)
		var y1 := mini(View.VIEW, y + h)
		if x0 < x1 and y0 < y1:
			Weapons.painter.fill_rect(x0, y0, x1 - x0, y1 - y0, Color8(r, g, b))
		return
	for yy in range(maxi(0, y), mini(View.VIEW, y + h)):
		for xx in range(maxi(0, x), mini(View.WIDTH, x + w)):
			var o := (yy * View.WIDTH + xx) * 3
			if Weapons.under:
				var k := 255 - Weapons.cover[o / 3]
				frame[o] = mini(255, frame[o] + r * k / 255)
				frame[o + 1] = mini(255, frame[o + 1] + g * k / 255)
				frame[o + 2] = mini(255, frame[o + 2] + b * k / 255)
				Weapons.cover[o / 3] = 255
				continue
			frame[o] = r
			frame[o + 1] = g
			frame[o + 2] = b
			if Weapons.covering:
				Weapons.cover[o / 3] = 255


## Bresenham line with an optional square width, matching pg.draw.line.
static func draw_line(
	frame: PackedByteArray, x0: int, y0: int, x1: int, y1: int, c: Color, width := 1
) -> void:
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy
	var r := roundi(c.r * 255.0)
	var g := roundi(c.g * 255.0)
	var b := roundi(c.b * 255.0)
	while true:
		if width <= 1:
			if Weapons.painter != null:
				if x0 >= 0 and y0 >= 0 and x0 < View.WIDTH and y0 < View.VIEW:
					Weapons.painter.set_pixel(x0, y0, r, g, b)
			elif x0 >= 0 and y0 >= 0 and x0 < View.WIDTH and y0 < View.VIEW:
				var o := (y0 * View.WIDTH + x0) * 3
				if Weapons.under:
					var k := 255 - Weapons.cover[o / 3]
					frame[o] = mini(255, frame[o] + r * k / 255)
					frame[o + 1] = mini(255, frame[o + 1] + g * k / 255)
					frame[o + 2] = mini(255, frame[o + 2] + b * k / 255)
				else:
					frame[o] = r
					frame[o + 1] = g
					frame[o + 2] = b
				if Weapons.covering:
					Weapons.cover[o / 3] = 255
		else:
			fill_rect(frame, x0, y0, width, width, c)
		if x0 == x1 and y0 == y1:
			break
		var e2 := err * 2
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy
