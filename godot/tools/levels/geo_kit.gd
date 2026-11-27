## Pieces of level format 2's geometry for a plan (a LevelBuilder `b`): decks,
## ramps, stairs, thin walls with doorways and windows cut to size, rails,
## balconies, bridges, ceilings, cover and rooms of any outline. Each adds to
## b.geometry (slabs, segments, ceilings: src/level_geometry.gd) with an id,
## and returns what it made. Map units: a cell is 1, z up from the ground,
## the eye .95 over a floor, a door 1.85 high, a step at most .245.
##
##   const Geo := preload("res://tools/levels/geo_kit.gd")
##   Geo.deck(b, "loft", [10, 4, 14, 7], 1.6, {"tile": "porch"})
extends RefCounted

## A tread rises at most this (LevelGeometry.STEP is .245).
const RISE := .2
## A deck's default thickness.
const DECK := .15
## Where a doorway in a thin wall tops out.
const DOOR_HEAD := 1.85


## Pass 16 (T4 WAYS): the level's nav graph also walks bent through the
## middle of every doorway cut after this (wall()'s openings with no sill
## over a step) and the foot and head of every stair (stairs()), so hands and
## bots find off-grid doorways and stairs. Call it before the walls. Writes
## "nav_via" and "vias" in the geometry block (never on a chapter that does
## not ask).
static func ways(b) -> void:
	if not b.geometry.has("vias"):
		b.geometry["vias"] = []


## A via point by hand (pass 16): where a way passes that the cells' middles
## miss (x, y, and the floor there). Turns the ways on.
static func via(b, x: float, y: float, z := 0.0) -> void:
	ways(b)
	b.geometry["vias"].append([_r(x), _r(y), _r(z)])


## A door that stands in the geometry (pass 16): on the line through the
## middles of cells (x, y) and the next o.span - 1 along it (east, or south
## when `vertical`), on the floor o.z (0 the ground), in the opening a
## wall() along that line leaves for it. Nothing of the grid changes (the
## cells stay as they are: under an upper door, the room below). o: span (1
## to 3; 2 hinged swings as a pair, 3 sliding is a barn door), style (hinge,
## slide), key, secret, bar, tile, id, opened.
static func door(b, x: int, y: int, vertical: bool, o := {}) -> Dictionary:
	var d := {
		"x": x,
		"y": y,
		"style": String(o.get("style", "hinge")),
		"vertical": vertical,
		"key": String(o.get("key", "")),
		"secret": bool(o.get("secret", false)),
		"blast_only": false,
		"progress": 1 if bool(o.get("opened", false)) else 0,
		"opened": bool(o.get("opened", false)),
		"discovered": false,
		"texture": "",
		"material": b.t(String(o.get("tile", "door"))),
		"id": String(o.get("id", "")),
	}
	if o.has("bar"):
		d["bar_side"] = String(o["bar"])
	b.ways_of_door(d, o)
	b.doors.append(d)
	return d


static func _rect(r: Array) -> Array:
	return [
		minf(float(r[0]), float(r[2])),
		minf(float(r[1]), float(r[3])),
		maxf(float(r[0]), float(r[2])),
		maxf(float(r[1]), float(r[3]))
	]


static func _r(v: float) -> float:
	return snappedf(v, .001)


## A slab: rectangle `rect` [x0, y0, x1, y1] (map units, not cells), top
## `top`; o: thick (< 0 solid to the ground), gx, gy, cuts [[nx, ny, c]...],
## tile, under, edge, light, area, walk, kind.
static func slab(b, id: String, rect: Array, top: float, o := {}) -> Dictionary:
	var r := _rect(rect)
	var s := {
		"id": id,
		"kind": String(o.get("kind", "deck")),
		"x0": _r(r[0]),
		"y0": _r(r[1]),
		"x1": _r(r[2]),
		"y1": _r(r[3]),
		"top": _r(top),
		"thick": _r(float(o.get("thick", DECK))),
		"tile": String(o.get("tile", "porch")),
		"under": String(o.get("under", "ceiling")),
		"edge": String(o.get("edge", o.get("tile", "porch"))),
		"light": snappedf(float(o.get("light", .85)), .0001),
		"area": int(o.get("area", 0)),
	}
	if o.has("gx"):
		s["gx"] = snappedf(float(o["gx"]), .0001)
	if o.has("gy"):
		s["gy"] = snappedf(float(o["gy"]), .0001)
	if o.has("cuts"):
		s["cuts"] = o["cuts"]
	if not bool(o.get("walk", true)):
		s["walk"] = false
	b.geometry["slabs"].append(s)
	return s


## A deck walked on and under: its top `top`, DECK thick unless o.thick.
static func deck(b, id: String, rect: Array, top: float, o := {}) -> Dictionary:
	return slab(b, id, rect, top, o)


## A ramp rising from z0 to z1 toward `toward` (n, e, s, w) across `rect`:
## solid down to the ground unless o.thick (a ramp walked under).
static func ramp(
	b, id: String, rect: Array, z0: float, z1: float, toward: String, o := {}
) -> Dictionary:
	var r := _rect(rect)
	var opts := o.duplicate()
	opts["kind"] = "ramp"
	if not opts.has("thick"):
		opts["thick"] = -1.0
	var rise := z1 - z0
	var top := z0
	match toward:
		"e":
			opts["gx"] = rise / (r[2] - r[0])
		"w":
			opts["gx"] = -rise / (r[2] - r[0])
			top = z1
		"s":
			opts["gy"] = rise / (r[3] - r[1])
		"n":
			opts["gy"] = -rise / (r[3] - r[1])
			top = z1
		_:
			assert(false, "ramp %s: toward must be n, e, s or w" % id)
	return slab(b, id, r, top, opts)


## Stairs from z0 up to z1 toward `toward` across `rect`: treads RISE high at
## most, each solid down to the ground (o.thick for open stairs).
static func stairs(
	b, id: String, rect: Array, z0: float, z1: float, toward: String, o := {}
) -> Array:
	var r := _rect(rect)
	var n := maxi(1, int(ceil((z1 - z0) / float(o.get("rise", RISE)) - .001)))
	var along_x := toward == "e" or toward == "w"
	var run: float = (r[2] - r[0]) if along_x else (r[3] - r[1])
	var out: Array = []
	var opts := o.duplicate()
	opts["kind"] = "stair"
	if not opts.has("thick"):
		opts["thick"] = -1.0
	for k in n:
		var a := run * k / n
		var c := run * (k + 1) / n
		var tread: Array
		match toward:
			"e":
				tread = [r[0] + a, r[1], r[0] + c, r[3]]
			"w":
				tread = [r[2] - c, r[1], r[2] - a, r[3]]
			"s":
				tread = [r[0], r[1] + a, r[2], r[1] + c]
			_:
				tread = [r[0], r[3] - c, r[2], r[3] - a]
		var top := z0 + (z1 - z0) * (k + 1) / n
		out.append(slab(b, "%s_%d" % [id, k + 1], tread, top, opts))
	if b.geometry.has("vias"):
		# (Its foot and its head, the ways on: pass 16.)
		var mx: float = (r[0] + r[2]) * .5
		var my: float = (r[1] + r[3]) * .5
		match toward:
			"e":
				b.geometry["vias"].append_array(
					[[_r(r[0]), _r(my), _r(z0)], [_r(r[2]), _r(my), _r(z1)]]
				)
			"w":
				b.geometry["vias"].append_array(
					[[_r(r[2]), _r(my), _r(z0)], [_r(r[0]), _r(my), _r(z1)]]
				)
			"s":
				b.geometry["vias"].append_array(
					[[_r(mx), _r(r[1]), _r(z0)], [_r(mx), _r(r[3]), _r(z1)]]
				)
			_:
				b.geometry["vias"].append_array(
					[[_r(mx), _r(r[3]), _r(z0)], [_r(mx), _r(r[1]), _r(z1)]]
				)
	return out


## A free wall from a to bb, z0 up to z1, o.thick thick (.12), of o.tile,
## with o.openings cut to size: each {at (distance from a to the opening's
## middle), width, sill (0: a doorway), head (DOOR_HEAD for a door)}. Returns
## the pieces.
static func wall(b, id: String, a: Vector2, bb: Vector2, z0: float, z1: float, o := {}) -> Array:
	var length := a.distance_to(bb)
	var dir := (bb - a) / maxf(length, 1e-6)
	var holes: Array = []
	for hole: Dictionary in o.get("openings", []):
		var half := float(hole.get("width", 1.0)) * .5
		var mid := float(hole["at"])
		# (A wall standing on an upper floor: its doorway from that floor, pass 16.)
		var foot := maxf(0.0, z0)
		var sill := float(hole.get("sill", foot))
		var head := float(hole.get("head", DOOR_HEAD + foot if sill <= foot else sill + 1.0))
		holes.append([maxf(0.0, mid - half), minf(length, mid + half), sill, head])
		_way_through(b, a, dir, mid, half, z0, sill, head, hole)
	holes.sort_custom(func(p, q): return p[0] < q[0])
	for i in range(1, holes.size()):
		if holes[i][0] < holes[i - 1][1] - .001:
			# SPIKE (pass 16): openings over one another (a window over a door,
			# a storey's windows over the one below): cut by columns.
			return _stacked(b, id, a, dir, length, z0, z1, holes, o)
	var pieces: Array = []
	var from := 0.0
	var k := 0
	for hole: Array in holes:
		if hole[0] > from + .001:
			pieces.append(
				_piece(b, "%s_%d" % [id, k], a + dir * from, a + dir * hole[0], z0, z1, o)
			)
			k += 1
		if hole[2] > z0 + .001:
			pieces.append(
				_piece(b, "%s_%d" % [id, k], a + dir * hole[0], a + dir * hole[1], z0, hole[2], o)
			)
			k += 1
		if hole[3] < z1 - .001:
			pieces.append(
				_piece(b, "%s_%d" % [id, k], a + dir * hole[0], a + dir * hole[1], hole[3], z1, o)
			)
			k += 1
		from = hole[1]
	if length > from + .001:
		var name := id if holes.is_empty() else "%s_%d" % [id, k]
		pieces.append(_piece(b, name, a + dir * from, bb, z0, z1, o))
	return pieces


## An opening's pane and via (pass 16, T4 WAYS): o.pane true puts glass in it
## from its sill to its head; a doorway (no pane, its sill within a step of
## the wall's foot) is a via while the ways are on (ways()).
static func _way_through(
	b, a: Vector2, dir: Vector2, mid: float, half: float, z0: float, sill: float, head: float, hole
) -> void:
	if bool(hole.get("pane", false)):
		var p0 := a + dir * (mid - half)
		var p1 := a + dir * (mid + half)
		(
			b
			. geo_panes
			. append(
				{
					"a": [_r(p0.x), _r(p0.y)],
					"b": [_r(p1.x), _r(p1.y)],
					"z0": _r(sill),
					"z1": _r(head),
				}
			)
		)
		return
	if b.geometry.has("vias") and sill <= z0 + .245:
		var at := a + dir * mid
		b.geometry["vias"].append([_r(at.x), _r(at.y), _r(maxf(z0, sill))])


## A wall whose openings overlap along it: the length cut at every opening's
## ends into columns, each column solid from z0 to z1 but for the openings
## over it (pieces bottom to top).
static func _stacked(
	b, id: String, a: Vector2, dir: Vector2, length: float, z0: float, z1: float, holes: Array, o
) -> Array:
	var cuts: Array = [0.0, length]
	for hole: Array in holes:
		cuts.append(hole[0])
		cuts.append(hole[1])
	cuts.sort()
	var pieces: Array = []
	var k := 0
	for i in range(cuts.size() - 1):
		var u: float = cuts[i]
		var v: float = cuts[i + 1]
		if v - u < .001:
			continue
		var gaps: Array = []
		for hole: Array in holes:
			if hole[0] <= u + .001 and hole[1] >= v - .001:
				gaps.append([hole[2], hole[3]])
		gaps.sort_custom(func(p, q): return p[0] < q[0])
		var low := z0
		for gap: Array in gaps:
			if gap[0] > low + .001:
				pieces.append(
					_piece(b, "%s_%d" % [id, k], a + dir * u, a + dir * v, low, gap[0], o)
				)
				k += 1
			low = maxf(low, gap[1])
		if z1 > low + .001:
			pieces.append(_piece(b, "%s_%d" % [id, k], a + dir * u, a + dir * v, low, z1, o))
			k += 1
	return pieces


static func _piece(
	b, id: String, a: Vector2, bb: Vector2, z0: float, z1: float, o: Dictionary
) -> Dictionary:
	var s := {
		"id": id,
		"a": [_r(a.x), _r(a.y)],
		"b": [_r(bb.x), _r(bb.y)],
		"z0": _r(z0),
		"z1": _r(z1),
		"thick": _r(float(o.get("thick", .12))),
		"tile": String(o.get("tile", "plaster")),
		"light": snappedf(float(o.get("light", .85)), .0001),
		"area": int(o.get("area", 0)),
	}
	if not bool(o.get("sight", true)):
		s["sight"] = false
	if o.has("shots"):
		s["shots"] = bool(o["shots"])
	b.geometry["segments"].append(s)
	return s


## A rail from a to bb standing on z0, o.height (.95) high: stops a body,
## not a look or a shot.
static func rail(b, id: String, a: Vector2, bb: Vector2, z0: float, o := {}) -> Dictionary:
	var opts := o.duplicate()
	opts["sight"] = false
	opts["shots"] = false
	if not opts.has("thick"):
		opts["thick"] = .08
	if not opts.has("tile"):
		opts["tile"] = "stockyard"
	return _piece(b, id, a, bb, z0, z0 + float(o.get("height", .95)), opts)


## Low cover from a to bb on z0, o.height (1.0) high and o.thick (.3)
## thick: stops bodies, looks and shots below its top.
static func cover(b, id: String, a: Vector2, bb: Vector2, z0: float, o := {}) -> Dictionary:
	var opts := o.duplicate()
	if not opts.has("thick"):
		opts["thick"] = .3
	return _piece(b, id, a, bb, z0, z0 + float(o.get("height", 1.0)), opts)


## A deck with rails along the sides named in `open` ("nesw" letters), each
## side's rail left open where o.gaps lists it ([[side, from, to]...] along it).
static func balcony(b, id: String, rect: Array, top: float, open: String, o := {}) -> Dictionary:
	var r := _rect(rect)
	var made := deck(b, id, r, top, o)
	var inset := .06
	var sides := {
		"n": [Vector2(r[0], r[1] + inset), Vector2(r[2], r[1] + inset)],
		"s": [Vector2(r[0], r[3] - inset), Vector2(r[2], r[3] - inset)],
		"w": [Vector2(r[0] + inset, r[1]), Vector2(r[0] + inset, r[3])],
		"e": [Vector2(r[2] - inset, r[1]), Vector2(r[2] - inset, r[3])],
	}
	var rail_o: Dictionary = o.get("rail", {})
	for side: String in open:
		var ends: Array = sides[side]
		var spans: Array = [[0.0, 1.0]]
		for gap: Array in o.get("gaps", []):
			if String(gap[0]) != side:
				continue
			var length: float = (ends[0] as Vector2).distance_to(ends[1])
			var g0 := float(gap[1]) / length
			var g1 := float(gap[2]) / length
			var cut: Array = []
			for span: Array in spans:
				if g1 <= span[0] or g0 >= span[1]:
					cut.append(span)
					continue
				if g0 > span[0]:
					cut.append([span[0], g0])
				if g1 < span[1]:
					cut.append([g1, span[1]])
			spans = cut
		for k in spans.size():
			var span: Array = spans[k]
			var p: Vector2 = (ends[0] as Vector2).lerp(ends[1], span[0])
			var q: Vector2 = (ends[0] as Vector2).lerp(ends[1], span[1])
			rail(b, "%s_rail_%s%d" % [id, side, k], p, q, top, rail_o)
	return made


## A bridge across `rect` at `top`, rails along its two long sides.
static func bridge(b, id: String, rect: Array, top: float, o := {}) -> Dictionary:
	var r := _rect(rect)
	var along_x: bool = (r[2] - r[0]) >= (r[3] - r[1])
	return balcony(b, id, r, top, "ns" if along_x else "we", o)


## A ceiling over `rect` at z (an overhang, an upper room's ceiling).
static func ceiling(b, id: String, rect: Array, z: float, o := {}) -> Dictionary:
	var r := _rect(rect)
	var c := {
		"id": id,
		"x0": _r(r[0]),
		"y0": _r(r[1]),
		"x1": _r(r[2]),
		"y1": _r(r[3]),
		"z": _r(z),
		"tile": String(o.get("tile", "ceiling")),
		"light": snappedf(float(o.get("light", .8)), .0001),
		"area": int(o.get("area", 0)),
	}
	if o.has("cuts"):
		c["cuts"] = o["cuts"]
	b.geometry["ceilings"].append(c)
	return c


## A room of any outline (`points` clockwise or not, map units): the cells
## whose middles are inside open as b.room() would make them, and a wall
## o.thick thick along each edge, from the floor to o.top (the room's roof
## or 2.2), of o.wall; o.openings per edge index ([edge, {at, width, ...}]).
static func room_poly(
	b, id: String, points: Array, floor_name: String, district_id: int, o := {}
) -> Array:
	var poly := PackedVector2Array()
	for p in points:
		poly.append(Vector2(float(p[0]), float(p[1])))
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	var roof := float(o.get("roof", 2.2))
	for cy in range(maxi(0, floori(lo.y)), mini(b.h - 1, floori(hi.y)) + 1):
		for cx in range(maxi(0, floori(lo.x)), mini(b.w - 1, floori(hi.x)) + 1):
			if Geometry2D.is_point_in_polygon(Vector2(cx + .5, cy + .5), poly):
				b.room(cx, cy, cx, cy, floor_name, district_id, o)
	var walls: Array = []
	var top := float(o.get("top", roof))
	var wall_o := {
		"tile": String(o.get("wall", "plaster")),
		"thick": float(o.get("thick", .16)),
		"light": float(o.get("light", .78)),
		"area": district_id,
	}
	for i in poly.size():
		var opts := wall_o.duplicate()
		var holes: Array = []
		for entry: Array in o.get("openings", []):
			if int(entry[0]) == i:
				holes.append(entry[1])
		opts["openings"] = holes
		walls.append_array(
			wall(b, "%s_wall%d" % [id, i], poly[i], poly[(i + 1) % poly.size()], 0.0, top, opts)
		)
	return walls


## A ladder leaning on a face at (x, y) (the face's own line: a deck's or a
## block's edge), climbed facing `dir` (n, e, s, w) from the floor at z0 to
## the floor at z1 beyond the face; o: tile, light, area. src/climbing.gd
## climbs it; LevelGeometry draws its rails and rungs and joins its foot and
## top in the nav graph, so the hands take it too.
static func ladder(
	b, id: String, x: float, y: float, dir: String, z0: float, z1: float, o := {}
) -> Dictionary:
	var lad := {
		"id": id,
		"x": _r(x),
		"y": _r(y),
		"dir": dir,
		"z0": _r(z0),
		"z1": _r(z1),
		"tile": String(o.get("tile", "porch")),
		"light": snappedf(float(o.get("light", .85)), .0001),
		"area": int(o.get("area", 0)),
	}
	b.geometry["ladders"].append(lad)
	return lad


# ------------------------------------------------- version 2 (pass 16)


## A raked wall (geometry version 2) from a (its top za there) to bb (zb), its
## foot at z0: a gable's end, a wall under a stair or a lean-to roof, an
## arch's haunch. o: thick, tile, light, area, sight, shots, as wall()'s
## pieces. Drawn as a true quad, collides, stops looks and shots along its
## sloping top.
static func raked(
	b, id: String, a: Vector2, bb: Vector2, z0: float, za: float, zb: float, o := {}
) -> Dictionary:
	var s := _piece(b, id, a, bb, z0, za, o)
	s["z1b"] = _r(zb)
	return s


## Terrain (geometry version 2): a patch of corner heights over the cells x0 ..
## x0 + w - 1, y0 .. y0 + h - 1. `heights`: a Callable (x, y) -> the height at
## that corner (map units), or (w + 1) * (h + 1) heights row by row from the
## north-west. o: tile (the patch's floor, painted into its cells too),
## cliff (the tile up its cliffs), light, palette + rows (src/level_terrain.gd).
## Heights are written in whole centimetres; each of its cells' ground
## becomes the patch's lowest corner, so everything reading a cell's ground
## stays under the surface (and the grid draws no steps under it). Call
## lift_onto_terrain(b) once everything is placed.
static func terrain(
	b, id: String, x0: int, y0: int, w: int, h: int, heights: Variant, o := {}
) -> Dictionary:
	var cm := PackedInt32Array()
	for y in h + 1:
		for x in w + 1:
			var v := 0.0
			if heights is Callable:
				v = float((heights as Callable).call(float(x0 + x), float(y0 + y)))
			else:
				v = float(heights[y * (w + 1) + x])
			cm.append(int(roundf(v * 100.0)))
	var patch := {"id": id, "x": x0, "y": y0, "w": w, "h": h, "heights": Array(cm)}
	for key: String in ["tile", "cliff", "light", "palette", "rows"]:
		if o.has(key):
			patch[key] = o[key]
	if not b.geometry.has("terrain"):
		b.geometry["terrain"] = []
	b.geometry["terrain"].append(patch)
	var low := cm[0]
	for v in cm:
		low = mini(low, v)
	for y in h:
		for x in w:
			var c: int = b.at(x0 + x, y0 + y)
			b.ground[c] = low / 100.0
			if o.has("tile"):
				b.floor_tile[c] = b.t(String(o["tile"]))
	return patch


## A round hill of terrain over `rect` [x0, y0, x1, y1] (whole cells): `top`
## high at its middle, easing down (a cosine) to o.base (0) at its edges.
static func hill(b, id: String, rect: Array, top: float, o := {}) -> Dictionary:
	var x0 := int(rect[0])
	var y0 := int(rect[1])
	var x1 := int(rect[2])
	var y1 := int(rect[3])
	var base := float(o.get("base", 0.0))
	var mid := Vector2((x0 + x1) * .5, (y0 + y1) * .5)
	var reach := Vector2((x1 - x0) * .5, (y1 - y0) * .5)
	var shape := func(x: float, y: float) -> float:
		var d := Vector2((x - mid.x) / reach.x, (y - mid.y) / reach.y).length()
		return base + (top - base) * (.5 + .5 * cos(PI * minf(d, 1.0)))
	return terrain(b, id, x0, y0, x1 - x0, y1 - y0, shape, o)


## Everything a plan laid on the ground lifted onto the terrain where it
## stands: pickups and hands get the surface's height as their floor, boards
## and props their height over their cell's ground. Call it after the plan
## has placed everything (a level without terrain is left as it was).
static func lift_onto_terrain(b) -> void:
	var list: Array = b.geometry.get("terrain", [])
	if list.is_empty():
		return
	var t := LevelTerrain.from_json(list, b.w, b.h, b.tile, [])
	if t == null:
		return
	for e: Dictionary in b.enemies:
		var z := t.height_at(float(e["x"]), float(e["y"]))
		if not is_nan(z) and z > float(e.get("z", 0.0)):
			e["z"] = _r(z)
	for p: Array in b.pickups:
		var z := t.height_at(float(p[1]), float(p[2]))
		if is_nan(z):
			continue
		if p.size() > 3:
			p[3] = maxf(float(p[3]), _r(z))
		else:
			p.append(_r(z))
	for bd: Dictionary in b.billboards:
		var x := float(bd["x"])
		var y := float(bd["y"])
		var z := t.height_at(x, y)
		if is_nan(z):
			continue
		var c: int = b.at(int(x), int(y))
		bd["z"] = _r(float(bd["z"]) + z - float(b.ground[c]))
