## Pictures of a built map from above, for a person or an agent to look at:
## the whole plan with every piece labelled by its id, then one picture a
## floor (the ground, then each deck height) with what can be walked there
## bright and the rest dimmed. Overlays (any of): nav (the graph's nodes,
## green reached from the spawn, red not; links between floors cyan),
## collision (where a body cannot stand on that floor, red), spawns, objects
## (hands red, pickups yellow, objectives white), unreachable (red crosses on
## places the spawn cannot walk to). North is up, a cell is `scale` pixels,
## the grid lines every 4 cells numbered every 8.
extends RefCounted

const Source := preload("res://tools/map/map_source.gd")

const INK := Color(1, .95, .8)
const GRID := Color(1, 1, 1, .10)


## Writes the pictures into `dir` (made if needed) and returns their paths.
static func render(
	doc: Dictionary,
	built: Dictionary,
	lv: LevelData,
	dir: String,
	overlays: Array,
	scale := 16,
	only_floor := NAN
) -> Array:
	DirAccess.make_dir_recursive_absolute(dir)
	var out: Array = []
	var field: FlowField = null
	if lv.geo != null or overlays.has("nav") or overlays.has("unreachable"):
		field = FlowField.new(lv)
		field.reach = 1 << 20
		field.doors_open = true
		field.every_door = true
		var spawn: Array = built["spawn"]
		var sz := float(spawn[3]) if spawn.size() > 3 else 0.0
		field.update(spawn[0], spawn[1], 0.0, lv.floor_under(spawn[0], spawn[1], sz + .05))
	var floors := floors_of(lv, field)
	var id := String(doc.get("id", lv.id))
	if is_nan(only_floor):
		var plan := _picture(doc, built, lv, field, NAN, overlays, scale)
		var path := dir.path_join("%s_plan.png" % id)
		plan.save_png(path)
		out.append(path)
	for k in floors.size():
		var z: float = floors[k]
		if not is_nan(only_floor) and absf(z - only_floor) > .05:
			continue
		var img := _picture(doc, built, lv, field, z, overlays, scale)
		var path := dir.path_join(
			"%s_floor%d_z%s.png" % [id, k, str(snappedf(z, .01)).replace(".", "_")]
		)
		img.save_png(path)
		out.append(path)
	return out


## The heights people stand at: the ground (0 or the lowest), then each deck.
static func floors_of(_lv: LevelData, field: FlowField) -> Array:
	var heights := {0.0: true}
	if field != null and field.graph != null:
		for n in range(field.graph.cells, field.graph.count):
			heights[snappedf(field.graph.z[n], .05)] = true
	var list := heights.keys()
	list.sort()
	return list


static func _picture(
	doc: Dictionary,
	built: Dictionary,
	lv: LevelData,
	field: FlowField,
	z: float,
	overlays: Array,
	s: int
) -> Image:
	var w := lv.width
	var h := lv.height
	var legend := 26
	var img := Image.create(w * s, h * s + legend, false, Image.FORMAT_RGBA8)
	img.fill(Color(.08, .07, .06))
	var colours := {}
	var whole := is_nan(z)
	for y in h:
		for x in w:
			var i := y * w + x
			var c := Color(.05, .04, .04)
			if lv.solid[i] < 0:
				var tile := lv.floor_tile[i]
				if not colours.has(tile):
					colours[tile] = _tile_colour(lv, tile)
				c = colours[tile]
				if lv.roof[i] > lv.ground[i] + .01:
					c = c.darkened(.22)
				c = c.lightened(clampf(lv.ground[i], 0.0, .6) * .4)
				if not whole and absf(_floor_z(field, i) - z) > .3:
					c = c.darkened(.55)
			elif lv.wall_height[i] < 1.6:
				c = Color(.2, .16, .13)
			img.fill_rect(Rect2i(x * s, y * s, s, s), c)
	# The grid.
	for x in range(0, w + 1, 4):
		img.fill_rect(Rect2i(x * s, 0, 1, h * s), GRID)
	for y in range(0, h + 1, 4):
		img.fill_rect(Rect2i(0, y * s, w * s, 1), GRID)
	for x in range(0, w, 8):
		_text(img, str(x), x * s + 2, 2, Color(1, 1, 1, .45))
	for y in range(8, h, 8):
		_text(img, str(y), 2, y * s + 2, Color(1, 1, 1, .45))
	# Fixtures.
	for f: PackedFloat32Array in lv.collision_volumes:
		if not whole and (f[7] > z + 1.2 or f[4] < z):
			continue
		_box(img, f[0], f[1], f[2], f[3], s, Color(.42, .32, .22, .9))
	if lv.geo != null:
		_geometry(img, lv, z, s)
	# Grid doors.
	for d: LevelData.Door in lv.doors:
		var col := Color(.3, .5, 1)
		if d.key != "":
			col = Color(1, .8, .2)
		if d.secret:
			col = Color(1, .2, 1)
		img.fill_rect(Rect2i(d.x * s + s / 4, d.y * s + s / 4, s / 2, s / 2), col)
	if overlays.has("collision") and not whole:
		_collision(img, lv, z, s)
	if overlays.has("nav") and field != null:
		_nav(img, lv, field, z, s)
	_objects(img, doc, built, lv, field, z, s, overlays)
	if whole:
		_labels(img, doc, built, lv, s)
	var title := (
		"%s  %s"
		% [
			String(doc.get("id", lv.id)).to_upper(),
			"PLAN" if whole else "FLOOR Z %s" % snappedf(z, .01)
		]
	)
	_text(img, title, 4, h * s + 4, INK)
	_text(
		img,
		"N UP  1 CELL = %d PX  %s" % [s, " ".join(PackedStringArray(overlays)).to_upper()],
		4,
		h * s + 14,
		Color(.8, .75, .65)
	)
	return img


static func _floor_z(field: FlowField, cell: int) -> float:
	if field == null or field.graph == null:
		return 0.0
	return field.graph.z[cell]


static func _geometry(img: Image, lv: LevelData, z: float, s: int) -> void:
	var whole := is_nan(z)
	for slab in lv.geo.slabs:
		var poly := LevelGeometry.outline(slab.x0, slab.y0, slab.x1, slab.y1, slab.cuts)
		var top := slab.top_max()
		var on := (
			whole
			or absf(top - z) < .3
			or (slab.sloped() and slab.top_min() - .3 < z and z < top + .3)
		)
		var tint := Color.from_hsv(fmod(.08 + top * .17, 1.0), .55, .85, .55 if on else .18)
		if slab.kind == "stair":
			tint = tint.lightened(.15)
		_fill_poly(img, poly, s, tint)
		_outline(img, poly, s, Color(1, .9, .6, .9 if on else .3))
		if slab.sloped() and on:
			# An arrow up the slope.
			var mid := Vector2((slab.x0 + slab.x1) * .5, (slab.y0 + slab.y1) * .5)
			var up := (
				Vector2(slab.gx, slab.gy).normalized()
				* minf(slab.x1 - slab.x0, slab.y1 - slab.y0)
				* .35
			)
			_line(img, (mid - up) * s, (mid + up) * s, Color(1, 1, 1), 2)
			_line(
				img, (mid + up) * s, (mid + up * .5 + up.orthogonal() * .3) * s, Color(1, 1, 1), 2
			)
			_line(
				img, (mid + up) * s, (mid + up * .5 - up.orthogonal() * .3) * s, Color(1, 1, 1), 2
			)
	for c in lv.geo.ceilings:
		var poly := LevelGeometry.outline(c.x0, c.y0, c.x1, c.y1, c.cuts)
		for i in poly.size():
			var a := poly[i] * s
			var b := poly[(i + 1) % poly.size()] * s
			_line(img, a, b, Color(.6, .8, 1, .6), 1, 6)
	for g in lv.geo.segments:
		var on := whole or (g.z0 <= z + .3 and g.z1 > z + .1)
		var col := Color(.95, .9, .85, 1.0 if on else .25)
		if not g.sight:
			col = Color(.95, .8, .3, 1.0 if on else .25)
		elif g.z1 - g.z0 < 1.3:
			col = Color(.75, .55, .35, 1.0 if on else .25)
		_line(
			img,
			Vector2(g.ax, g.ay) * s,
			Vector2(g.bx, g.by) * s,
			col,
			maxi(1, int(g.half * 2.0 * s))
		)


static func _collision(img: Image, lv: LevelData, z: float, s: int) -> void:
	var step := maxi(2, s / 4)
	for py in range(0, lv.height * s, step):
		for px in range(0, lv.width * s, step):
			var x := (px + step * .5) / s
			var y := (py + step * .5) / s
			var c := lv.cell(x, y)
			if lv.solid[c] >= 0:
				continue
			var feet := lv.floor_under(x, y, z + .05)
			if absf(feet - z) > .3:
				continue
			if lv.geo != null and lv.geo.static_blocked(lv, x, y, .2, feet, LevelGeometry.BODY):
				img.fill_rect(Rect2i(px, py, step - 1, step - 1), Color(1, .1, .1, .45))


static func _nav(img: Image, lv: LevelData, field: FlowField, z: float, s: int) -> void:
	var g := field.graph
	var count := lv.width * lv.height if g == null else g.count
	for n in count:
		if field.open[n] == 0:
			continue
		var c := n if g == null else g.cell[n]
		var nz := 0.0 if g == null else g.z[n]
		if not is_nan(z) and absf(nz - z) > .3:
			continue
		var p := Vector2(c % lv.width + .5, c / lv.width + .5) * s
		var reached := field.steps[n] < FlowField.FAR
		var col := Color(.2, 1, .3, .8) if reached else Color(1, .2, .2, .8)
		img.fill_rect(Rect2i(int(p.x) - 1, int(p.y) - 1, 3, 3), col)
		if g != null:
			for e in range(g.first[n], g.first[n + 1]):
				var m := g.edges[e]
				if m < n:
					continue
				var cm := g.cell[m]
				var q := Vector2(cm % lv.width + .5, cm / lv.width + .5) * s
				var link := absf(g.z[m] - nz) > .1
				_line(img, p, q, Color(.2, .9, 1, .9) if link else Color(.2, 1, .3, .25), 1)


static func _objects(
	img: Image,
	doc: Dictionary,
	built: Dictionary,
	lv: LevelData,
	field: FlowField,
	z: float,
	s: int,
	overlays: Array
) -> void:
	var spawn: Array = built["spawn"]
	var sz := float(spawn[3]) if spawn.size() > 3 else 0.0
	if overlays.has("spawns") or overlays.is_empty() or is_nan(z) or absf(sz - z) < .3:
		var p := Vector2(spawn[0], spawn[1]) * s
		_disc(img, p, s * .35, Color(.2, 1, .3))
		_line(img, p, p + Vector2(cos(spawn[2]), sin(spawn[2])) * s * .8, Color(.2, 1, .3), 2)
	for o in doc.get("objects", []):
		if not (o is Dictionary) or not o.has("at"):
			continue
		var type := String(o.get("type", ""))
		var oz := float(o.get("z", 0.0))
		var at: Array = o["at"]
		var p := Vector2(float(at[0]), float(at[1])) * s
		var floor_z := lv.floor_under(float(at[0]), float(at[1]), oz + .05)
		if not is_nan(z) and absf(floor_z - z) > .3:
			continue
		match type:
			"enemy":
				_disc(img, p, s * .28, Color(1, .15, .1))
			"pickup":
				_disc(img, p, s * .2, Color(1, .9, .2))
			"station", "exit":
				_star(img, p, s * .4, Color(1, 1, 1))
			"spawn_point":
				_disc(img, p, s * .28, Color(.3, .9, 1))
			_:
				continue
		if overlays.has("unreachable") and field != null:
			var d := field.distance(float(at[0]), float(at[1]), floor_z)
			if d >= FlowField.FAR and type != "enemy":
				_line(img, p - Vector2(s, s) * .4, p + Vector2(s, s) * .4, Color(1, 0, 0), 2)
				_line(img, p - Vector2(s, -s) * .4, p + Vector2(s, -s) * .4, Color(1, 0, 0), 2)
	if overlays.has("unreachable") and field != null:
		var g := field.graph
		var count := lv.width * lv.height if g == null else g.count
		for n in count:
			if field.open[n] == 0 or field.steps[n] < FlowField.FAR:
				continue
			var c := n if g == null else g.cell[n]
			var nz := 0.0 if g == null else g.z[n]
			if not is_nan(z) and absf(nz - z) > .3:
				continue
			img.fill_rect(
				Rect2i(c % lv.width * s + 1, c / lv.width * s + 1, s - 2, s - 2),
				Color(1, 0, 0, .22)
			)


## Every object's id where it is.
static func _labels(
	img: Image, doc: Dictionary, _built: Dictionary, _lv: LevelData, s: int
) -> void:
	for o in doc.get("objects", []):
		if not (o is Dictionary):
			continue
		var p := Vector2.INF
		if o.has("rect"):
			var r: Array = o["rect"]
			p = Vector2(float(r[0]) + .15, float(r[1]) + .2)
		elif o.has("at"):
			p = Vector2(float(o["at"][0]) + .35, float(o["at"][1]) - .2)
		elif o.has("a"):
			p = (
				(
					Vector2(float(o["a"][0]), float(o["a"][1]))
					+ Vector2(float(o["b"][0]), float(o["b"][1]))
				)
				* .5
			)
		elif o.has("cell"):
			p = Vector2(float(o["cell"][0]), float(o["cell"][1]) - .4)
		elif o.has("points"):
			p = Vector2(float(o["points"][0][0]), float(o["points"][0][1]))
		if p == Vector2.INF or String(o.get("type", "")) in ["yard", "paint", "light", "raise"]:
			continue
		_text(img, String(o["id"]).to_upper(), int(p.x * s), int(p.y * s), INK, true)


static func _tile_colour(lv: LevelData, tile: int) -> Color:
	var name := String(lv.tile_names[tile]) if tile >= 0 and tile < lv.tile_names.size() else ""
	var path := (
		ProjectSettings
		. globalize_path("res://")
		. path_join("../assets/tiles/%s.png" % name)
		. simplify_path()
	)
	var img := Image.load_from_file(path) if FileAccess.file_exists(path) else null
	if img == null or img.is_empty():
		return Color(.4, .4, .4)
	img.resize(1, 1, Image.INTERPOLATE_BILINEAR)
	return img.get_pixel(0, 0)


# ------------------------------------------------------------- drawing


static func _blend(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	if c.a >= .999:
		img.set_pixel(x, y, c)
	else:
		img.set_pixel(x, y, img.get_pixel(x, y).blend(c))


static func _line(img: Image, a: Vector2, b: Vector2, c: Color, width := 1, dash := 0) -> void:
	var n := maxi(1, int(a.distance_to(b)))
	var r := width / 2
	for i in n + 1:
		if dash > 0 and (i / dash) % 2 == 1:
			continue
		var p := a.lerp(b, float(i) / n)
		for dy in range(-r, width - r):
			for dx in range(-r, width - r):
				_blend(img, int(p.x) + dx, int(p.y) + dy, c)


static func _box(img: Image, x0: float, y0: float, x1: float, y1: float, s: int, c: Color) -> void:
	for y in range(int(y0 * s), int(ceil(y1 * s))):
		for x in range(int(x0 * s), int(ceil(x1 * s))):
			_blend(img, x, y, c)


static func _fill_poly(img: Image, poly: PackedVector2Array, s: int, c: Color) -> void:
	if poly.size() < 3:
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	for y in range(int(lo.y * s), int(ceil(hi.y * s))):
		for x in range(int(lo.x * s), int(ceil(hi.x * s))):
			if Geometry2D.is_point_in_polygon(Vector2((x + .5) / s, (y + .5) / s), poly):
				_blend(img, x, y, c)


static func _outline(img: Image, poly: PackedVector2Array, s: int, c: Color) -> void:
	for i in poly.size():
		_line(img, poly[i] * s, poly[(i + 1) % poly.size()] * s, c, 1)


static func _disc(img: Image, p: Vector2, r: float, c: Color) -> void:
	for y in range(int(p.y - r), int(p.y + r) + 1):
		for x in range(int(p.x - r), int(p.x + r) + 1):
			if Vector2(x, y).distance_to(p) <= r:
				_blend(img, x, y, c)


static func _star(img: Image, p: Vector2, r: float, c: Color) -> void:
	for k in 4:
		var a := k * PI / 4.0
		var d := Vector2(cos(a), sin(a)) * r
		_line(img, p - d, p + d, c, 2)


## Lettering (the game's own pixel font), with a dark edge when `shade`.
static func _text(img: Image, text: String, x: int, y: int, c: Color, shade := false) -> void:
	var at := x
	for ch in text:
		var g: Array = PixelType.glyph(ch, false)
		var rows: Array = g[0]
		var gw: int = g[1]
		for ry in rows.size():
			for rx in gw:
				if int(rows[ry]) & (1 << (gw - 1 - rx)):
					if shade:
						_blend(img, at + rx + 1, y + ry + 1, Color(0, 0, 0, .8))
					_blend(img, at + rx, y + ry, c)
		at += gw + 1
