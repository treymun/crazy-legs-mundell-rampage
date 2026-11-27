## What the looks layer (pass 16, LOOKS: foliage.gd, dressing.gd, water.gd)
## knows of a built level dictionary (a plan's or a source's finished level,
## a player map's UserMapBuild.level): its grids by tile name, where a body
## walks, the way through (the route from the start to every objective,
## kept to the middle of the open ground), and what scatter and dressing
## must keep clear of: the way, doors, objectives, spawns, roads and the
## things already standing. It also writes what they add (sprites, bases that
## block, fixtures) the way the level files hold them.
##
## Everything here is deterministic: no clock, no dice, lists walked in their
## order, floats snapped to .01 as the builder snaps them.
class_name MapLooksGrid
extends RefCounted

const TUNING := "res://data/tuning/dressing.json"
## A body's height band a thin wall must cover to stop a walk (cells).
const KNEE := .3
const HEAD := 1.2
## A route keeps off walls: a step this near one costs this much more.
const HUG_REACH := 3
const HUG_COST := 2.0

static var _tuning := {}
static var _tiles := {}
static var _names := PackedStringArray()

var level: Dictionary
var w := 0
var h := 0
var solid := PackedInt32Array()
var floor_tile := PackedInt32Array()
var roof := PackedFloat32Array()
var ground := PackedFloat32Array()
var area := PackedInt32Array()
## Cells a body may stand in (open, not deep water, no furniture over the
## middle, a door's cell included).
var walk := PackedByteArray()
## Cells under a deck or a ceiling (nothing grows there).
var covered := PackedByteArray()
## Cells' distance in cells to the nearest solid cell (capped at 9).
var wall_steps := PackedInt32Array()
var terrain: LevelTerrain = null
## The way through: [ax, ay, bx, by] pieces, bucketed by cell (_route_at).
var route: Array[PackedFloat32Array] = []
var _route_at := {}
## Points to keep clear of: [x, y, reach] bucketed by cell.
var _keep_at := {}
## Edges a thin wall closes: Vector2i(cell, neighbour) -> true.
var _closed := {}
## Boxes that already block (the level's furniture and what was added), by
## the cells they cover and one round them.
var _box_at := {}
## Per cell: how many kept points lie within two cells, and whether a piece
## of the way does (so most asks are answered without a look).
var _keep_near := PackedInt32Array()
var _route_near := PackedByteArray()
## names + reach -> per cell, whether a floor of those names is that near.
var _floor_near := {}


static func tuning() -> Dictionary:
	if _tuning.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TUNING))
		_tuning = parsed if parsed is Dictionary else {}
	return _tuning


## A number read from data (JSON gives floats, the builders ints) as a float.
static func f(v: Variant) -> float:
	if v is String:
		return str(v).to_float()
	var x: float = v if (v is float or v is int) else 0.0
	return x


## A number of dressing.json's `section`, or `fallback`.
static func num(section: String, key: String, fallback: float) -> float:
	var part: Dictionary = tuning().get(section, {})
	var v: float = part.get(key, fallback)
	return v


static func tile_index() -> Dictionary:
	if _tiles.is_empty():
		var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://data/index.json")
		)
		var index: Dictionary = parsed if parsed is Dictionary else {}
		var names: Array = index.get("tiles", [])
		for i in names.size():
			_tiles[str(names[i])] = i
			_names.append(str(names[i]))
	return _tiles


static func tile_name(index: int) -> String:
	tile_index()
	return _names[index] if index >= 0 and index < _names.size() else ""


static func tile_of(name: String) -> int:
	var found: int = tile_index().get(name, -1)
	return found


## A view of `lv` (a level dictionary, changed in place by the writers below).
static func of(lv: Dictionary) -> MapLooksGrid:
	var g := MapLooksGrid.new()
	g.level = lv
	g.w = lv["width"]
	g.h = lv["height"]
	g.solid = LevelLoad.ints(lv["solid"])
	g.floor_tile = LevelLoad.ints(lv["floor"])
	g.roof = LevelLoad.floats(lv["roof"])
	g.ground = LevelLoad.floats(lv["ground"])
	g.area = LevelLoad.ints(lv["area"])
	g._keep_near.resize(g.w * g.h)
	g._keep_near.fill(0)
	g._route_near.resize(g.w * g.h)
	g._route_near.fill(0)
	g._read_geometry()
	g._read_furniture()
	g._find_walk()
	g._find_walls()
	g._find_keep()
	return g


func inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


func cell(x: float, y: float) -> int:
	return clampi(int(y), 0, h - 1) * w + clampi(int(x), 0, w - 1)


func floor_name(c: int) -> String:
	return tile_name(floor_tile[c])


func is_open(c: int) -> bool:
	return solid[c] < 0


## The floor's height at (x, y): the terrain's surface where it has one.
func floor_at(x: float, y: float) -> float:
	if terrain != null:
		var t := terrain.height_at(x, y)
		if not is_nan(t):
			return t
	return ground[cell(x, y)]


## Whether a thin wall stands between cell a and its neighbour b.
func closed(a: int, b: int) -> bool:
	return _closed.has(Vector2i(a, b))


# ------------------------------------------------------------------ reading


func _read_geometry() -> void:
	covered.resize(w * h)
	covered.fill(0)
	var block: Variant = level.get("geometry")
	if not (block is Dictionary):
		return
	var geo: Dictionary = block
	var errors: Array = []
	terrain = LevelTerrain.from_json(geo.get("terrain"), w, h, tile_index(), errors)
	for s: Variant in geo.get("slabs", []):
		var slab: Dictionary = s
		var x0: float = slab.get("x0", 0.0)
		var y0: float = slab.get("y0", 0.0)
		var x1: float = slab.get("x1", 0.0)
		var y1: float = slab.get("y1", 0.0)
		for y in range(maxi(0, floori(y0)), mini(h, ceili(y1))):
			for x in range(maxi(0, floori(x0)), mini(w, ceili(x1))):
				covered[y * w + x] = 1
	for c: Variant in geo.get("ceilings", []):
		var ceiling: Dictionary = c
		var cx0: float = ceiling.get("x0", 0.0)
		var cy0: float = ceiling.get("y0", 0.0)
		var cx1: float = ceiling.get("x1", 0.0)
		var cy1: float = ceiling.get("y1", 0.0)
		for y in range(maxi(0, floori(cy0)), mini(h, ceili(cy1))):
			for x in range(maxi(0, floori(cx0)), mini(w, ceili(cx1))):
				covered[y * w + x] = 1
	for s: Variant in geo.get("segments", []):
		var seg: Dictionary = s
		var z0: float = seg.get("z0", 0.0)
		var z1: float = seg.get("z1", 2.0)
		var a: Array = seg.get("a", [0, 0])
		var b: Array = seg.get("b", [0, 0])
		var pa := Vector2(f(a[0]), f(a[1]))
		var pb := Vector2(f(b[0]), f(b[1]))
		_close_across(pa, pb, z0, z1)


## Every neighbour edge whose centre-to-centre walk the piece from pa to pb
## crosses, when it covers a body's band over the floor there.
func _close_across(pa: Vector2, pb: Vector2, z0: float, z1: float) -> void:
	var x0 := maxi(0, floori(minf(pa.x, pb.x)) - 1)
	var x1 := mini(w - 1, floori(maxf(pa.x, pb.x)) + 1)
	var y0 := maxi(0, floori(minf(pa.y, pb.y)) - 1)
	var y1 := mini(h - 1, floori(maxf(pa.y, pb.y)) + 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var c := y * w + x
			var floor_z: float = ground[c]
			if z0 > floor_z + KNEE or z1 < floor_z + HEAD:
				continue
			var mid := Vector2(x + .5, y + .5)
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				if not inside(x + d.x, y + d.y):
					continue
				var other := mid + Vector2(d)
				if Geometry2D.segment_intersects_segment(mid, other, pa, pb) != null:
					var n := (y + d.y) * w + x + d.x
					_closed[Vector2i(c, n)] = true
					_closed[Vector2i(n, c)] = true


func _read_furniture() -> void:
	for f: Variant in level.get("collision_volumes", []):
		var row: Array = f
		_add_box(PackedFloat32Array([f(row[0]), f(row[1]), f(row[2]), f(row[3])]))


func _add_box(box: PackedFloat32Array) -> void:
	for yy in range(floori(box[1]) - 1, floori(box[3]) + 2):
		for xx in range(floori(box[0]) - 1, floori(box[2]) + 2):
			if not inside(xx, yy):
				continue
			var key := Vector2i(xx, yy)
			var list: Array = _box_at.get(key, [])
			list.append(box)
			_box_at[key] = list


func _find_walk() -> void:
	walk.resize(w * h)
	walk.fill(0)
	var deep := tile_of("bayou_deep")
	var door_cells := {}
	for d: Variant in level.get("doors", []):
		var door: Dictionary = d
		var dx: int = door.get("x", -1)
		var dy: int = door.get("y", -1)
		if inside(dx, dy):
			door_cells[dy * w + dx] = true
	for c in w * h:
		var open := solid[c] < 0 or door_cells.has(c)
		if not open or (deep >= 0 and floor_tile[c] == deep):
			continue
		if terrain != null and terrain.cliff_at((c % w) + .5, (c / w) + .5):
			continue
		walk[c] = 0 if _in_box((c % w) + .5, (c / w) + .5, 0.0) else 1


func _find_walls() -> void:
	wall_steps.resize(w * h)
	wall_steps.fill(9)
	var todo: Array[int] = []
	for c in w * h:
		if solid[c] >= 0:
			wall_steps[c] = 0
			todo.append(c)
	var at := 0
	while at < todo.size():
		var c: int = todo[at]
		at += 1
		var x := c % w
		var y := c / w
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not inside(x + d.x, y + d.y):
				continue
			var n := (y + d.y) * w + x + d.x
			if wall_steps[n] > wall_steps[c] + 1:
				wall_steps[n] = wall_steps[c] + 1
				if wall_steps[n] < 9:
					todo.append(n)


## The objectives a level holds, as [x, y] (stations, keys, the exit, gates,
## vehicles, set pieces): what the way runs to and what nothing covers.
func objectives() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for s: Variant in level.get("stations", []):
		var st: Dictionary = s
		out.append(Vector2(f(st.get("x", 0.0)), f(st.get("y", 0.0))))
	var ex: Variant = level.get("extraction")
	if ex is Dictionary:
		var exit: Dictionary = ex
		out.append(Vector2(f(exit.get("x", 0.0)), f(exit.get("y", 0.0))))
	for p: Variant in level.get("pickups", []):
		var row: Array = p
		if str(row[0]).begins_with("key"):
			out.append(Vector2(f(row[1]), f(row[2])))
	for gate_key: String in ["hub_gates"]:
		for g: Variant in level.get(gate_key, []):
			var gate: Dictionary = g
			out.append(Vector2(f(gate.get("x", 0.0)), f(gate.get("y", 0.0))))
	for v: Variant in level.get("vehicles", []):
		var row: Array = v
		out.append(Vector2(f(row[1]), f(row[2])))
	for s: Variant in level.get("set_pieces", []):
		var piece: Dictionary = s
		out.append(Vector2(f(piece.get("x", 0.0)), f(piece.get("y", 0.0))))
	var tac: Variant = level.get("tactical", {})
	if tac is Dictionary:
		var plan: Dictionary = tac
		for key: String in ["sites", "hostages"]:
			var listed: Variant = plan.get(key, [])
			if listed is Array:
				for item: Variant in listed:
					var spot := _point_of(item)
					if spot.x >= 0.0:
						out.append(spot)
	return out


## Where everyone starts: the spawn and a versus map's spawns.
func spawns() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var sp: Array = level.get("spawn", [])
	if sp.size() >= 2:
		out.append(Vector2(f(sp[0]), f(sp[1])))
	var tac: Variant = level.get("tactical", {})
	if tac is Dictionary:
		var plan: Dictionary = tac
		var sides: Variant = plan.get("spawns", {})
		var lists: Array = []
		if sides is Dictionary:
			var by_side: Dictionary = sides
			var keys: Array = by_side.keys()
			keys.sort()
			for k: Variant in keys:
				lists.append(by_side[k])
		elif sides is Array:
			lists.append(sides)
		for list: Variant in lists:
			if list is Array:
				for item: Variant in list:
					var spot := _point_of(item)
					if spot.x >= 0.0:
						out.append(spot)
	return out


static func _point_of(item: Variant) -> Vector2:
	if item is Array:
		var row: Array = item
		if row.size() >= 2 and (row[0] is float or row[0] is int):
			return Vector2(f(row[0]), f(row[1]))
	if item is Dictionary:
		var d: Dictionary = item
		if d.has("x") and d.has("y"):
			return Vector2(f(d["x"]), f(d["y"]))
	return Vector2(-1, -1)


func _find_keep() -> void:
	var clear: Dictionary = tuning().get("clear", {})
	var spawn_r: float = clear.get("spawn", 1.5)
	var door_r: float = clear.get("door", 1.5)
	var goal_r: float = clear.get("objective", 1.5)
	var thing_r: float = clear.get("thing", .8)
	var board_r: float = clear.get("board", .6)
	var starts := spawns()
	for p in starts:
		keep(p.x, p.y, spawn_r)
	for d: Variant in level.get("doors", []):
		var door: Dictionary = d
		var dx: float = door.get("x", 0)
		var dy: float = door.get("y", 0)
		keep(dx + .5, dy + .5, door_r)
	var goals := objectives()
	for p in goals:
		keep(p.x, p.y, goal_r)
	for e: Variant in level.get("enemies", []):
		var en: Dictionary = e
		keep(f(en.get("x", 0.0)), f(en.get("y", 0.0)), thing_r)
	for p: Variant in level.get("pickups", []):
		var row: Array = p
		keep(f(row[1]), f(row[2]), thing_r)
	for b: Variant in level.get("billboards", []):
		var board: Dictionary = b
		keep(f(board.get("x", 0.0)), f(board.get("y", 0.0)), board_r)
	for p: Variant in level.get("props", []):
		var row: Array = p
		keep(f(row[1]), f(row[2]), board_r)
	if not starts.is_empty():
		for goal in goals:
			_add_route(starts[0], goal)
		for i in range(1, starts.size()):
			_add_route(starts[0], starts[i])
	var tac: Variant = level.get("tactical", {})
	if tac is Dictionary:
		var plan: Dictionary = tac
		var lines: Variant = plan.get("routes", [])
		if lines is Array:
			for line: Variant in lines:
				_add_line(line)


## Keep (x, y) clear by `reach`.
func keep(x: float, y: float, reach: float) -> void:
	var key := Vector2i(int(x), int(y))
	var list: Array = _keep_at.get(key, [])
	list.append(PackedFloat32Array([x, y, reach]))
	_keep_at[key] = list
	for yy in range(key.y - 2, key.y + 3):
		for xx in range(key.x - 2, key.x + 3):
			if inside(xx, yy):
				_keep_near[yy * w + xx] += 1


func _add_line(line: Variant) -> void:
	var points: Array[Vector2] = []
	var listed: Array = []
	if line is Dictionary:
		var d: Dictionary = line
		listed = d.get("points", [])
	elif line is Array:
		listed = line
	for item: Variant in listed:
		var p := _point_of(item)
		if p.x >= 0.0:
			points.append(p)
	for i in range(1, points.size()):
		_route_piece(points[i - 1], points[i])


func _route_piece(a: Vector2, b: Vector2) -> void:
	var piece := PackedFloat32Array([a.x, a.y, b.x, b.y])
	route.append(piece)
	var steps := maxi(1, ceili(a.distance_to(b)))
	var seen := {}
	for k in steps + 1:
		var p := a.lerp(b, f(k) / steps)
		var key := Vector2i(int(p.x), int(p.y))
		if seen.has(key):
			continue
		seen[key] = true
		var list: Array = _route_at.get(key, [])
		list.append(piece)
		_route_at[key] = list
		for yy in range(key.y - 2, key.y + 3):
			for xx in range(key.x - 2, key.x + 3):
				if inside(xx, yy):
					_route_near[yy * w + xx] = 1


## The way from a to b over walkable cells, kept off the walls (each step
## near one costs more), as pieces of route. Nothing when b is not reached.
func _add_route(a: Vector2, b: Vector2) -> void:
	var path := way(cell(a.x, a.y), cell(b.x, b.y))
	var last := a
	for c in path:
		var p := Vector2((c % w) + .5, (c / w) + .5)
		_route_piece(last, p)
		last = p
	if not path.is_empty():
		_route_piece(last, b)


## The cells of the cheapest walk from cell `from` to cell `to` (both ends
## in), or [] where none is. Steps beside a wall cost more (HUG_COST), so the
## way runs down the middle of a yard or a lane, as a player walks it.
func way(from: int, to: int) -> PackedInt32Array:
	var n := w * h
	if from < 0 or to < 0 or from >= n or to >= n:
		return PackedInt32Array()
	var cost := PackedFloat32Array()
	cost.resize(n)
	cost.fill(INF)
	var back := PackedInt32Array()
	back.resize(n)
	back.fill(-1)
	cost[from] = 0.0
	# A plain binary heap of [cost, cell], ties broken by the cell's index.
	var heap: Array[Vector2] = [Vector2(0.0, from)]
	while not heap.is_empty():
		var top: Vector2 = _pop(heap)
		var c := int(top.y)
		if top.x > cost[c]:
			continue
		if c == to:
			break
		var x := c % w
		var y := c / w
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if not inside(x + d.x, y + d.y):
				continue
			var m := (y + d.y) * w + x + d.x
			if (walk[m] == 0 and m != to) or closed(c, m):
				continue
			var near := wall_steps[m]
			var step := 1.0 + (HUG_COST * (HUG_REACH - near) / HUG_REACH if near < HUG_REACH else 0.0)
			var total := cost[c] + step
			if total < cost[m]:
				cost[m] = total
				back[m] = c
				_push(heap, Vector2(total, m))
	if back[to] < 0 and to != from:
		return PackedInt32Array()
	var out := PackedInt32Array()
	var at := to
	while at >= 0:
		out.append(at)
		if at == from:
			break
		at = back[at]
	out.reverse()
	return out


static func _push(heap: Array[Vector2], item: Vector2) -> void:
	heap.append(item)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) / 2
		if _less(heap[i], heap[parent]):
			var swap := heap[i]
			heap[i] = heap[parent]
			heap[parent] = swap
			i = parent
		else:
			break


static func _pop(heap: Array[Vector2]) -> Vector2:
	var top := heap[0]
	var last: Vector2 = heap.pop_back()
	if heap.is_empty():
		return top
	heap[0] = last
	var i := 0
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var best := i
		if l < heap.size() and _less(heap[l], heap[best]):
			best = l
		if r < heap.size() and _less(heap[r], heap[best]):
			best = r
		if best == i:
			break
		var swap := heap[i]
		heap[i] = heap[best]
		heap[best] = swap
		i = best
	return top


static func _less(a: Vector2, b: Vector2) -> bool:
	return a.x < b.x or (a.x == b.x and a.y < b.y)


# ------------------------------------------------------------------ asking


## How far (x, y) is from the way through (INF far from any).
func route_distance(x: float, y: float) -> float:
	if not inside(int(x), int(y)) or _route_near[cell(x, y)] == 0:
		return INF
	var best := INF
	var p := Vector2(x, y)
	var cx := int(x)
	var cy := int(y)
	for yy in range(cy - 2, cy + 3):
		for xx in range(cx - 2, cx + 3):
			for piece: PackedFloat32Array in _route_at.get(Vector2i(xx, yy), []):
				var q := Geometry2D.get_closest_point_to_segment(
					p, Vector2(piece[0], piece[1]), Vector2(piece[2], piece[3])
				)
				best = minf(best, p.distance_to(q))
	return best


## Whether (x, y) is within the reach of something kept clear (plus `pad`).
func kept(x: float, y: float, pad := 0.0) -> bool:
	if inside(int(x), int(y)) and _keep_near[cell(x, y)] == 0:
		return false
	var cx := int(x)
	var cy := int(y)
	for yy in range(cy - 2, cy + 3):
		for xx in range(cx - 2, cx + 3):
			for k: PackedFloat32Array in _keep_at.get(Vector2i(xx, yy), []):
				var dx := x - k[0]
				var dy := y - k[1]
				var reach := k[2] + pad
				if dx * dx + dy * dy < reach * reach:
					return true
	return false


## How far (x, y) is from the nearest cell whose floor is in `names` (looked
## for within `most` cells; INF past that).
func distance_to_floor(x: float, y: float, names: Array, most: float) -> float:
	var best := INF
	var reach := ceili(most) + 1
	var near := _near_floors(names, reach)
	if inside(int(x), int(y)) and near[cell(x, y)] == 0:
		return INF
	var cx := int(x)
	var cy := int(y)
	for yy in range(cy - reach, cy + reach + 1):
		for xx in range(cx - reach, cx + reach + 1):
			if not inside(xx, yy):
				continue
			var c := yy * w + xx
			if solid[c] >= 0 or not names.has(floor_name(c)):
				continue
			var dx := maxf(maxf(xx - x, x - (xx + 1)), 0.0)
			var dy := maxf(maxf(yy - y, y - (yy + 1)), 0.0)
			best = minf(best, sqrt(dx * dx + dy * dy))
	return best


## Per cell, whether an open cell with a floor in `names` is within `reach`.
func _near_floors(names: Array, reach: int) -> PackedByteArray:
	var key := "%s|%d" % [str(names), reach]
	if _floor_near.has(key):
		var known: PackedByteArray = _floor_near[key]
		return known
	var out := PackedByteArray()
	out.resize(w * h)
	out.fill(0)
	for c in w * h:
		if solid[c] >= 0 or not names.has(floor_name(c)):
			continue
		for yy in range(c / w - reach, c / w + reach + 1):
			for xx in range(c % w - reach, c % w + reach + 1):
				if inside(xx, yy):
					out[yy * w + xx] = 1
	_floor_near[key] = out
	return out


## How far (x, y) is from the nearest solid cell's face (looked for within 3).
func distance_to_wall(x: float, y: float) -> float:
	if inside(int(x), int(y)) and wall_steps[cell(x, y)] > 4:
		return INF
	var best := INF
	var cx := int(x)
	var cy := int(y)
	for yy in range(cy - 3, cy + 4):
		for xx in range(cx - 3, cx + 4):
			if inside(xx, yy) and solid[yy * w + xx] < 0:
				continue
			var dx := maxf(maxf(xx - x, x - (xx + 1)), 0.0)
			var dy := maxf(maxf(yy - y, y - (yy + 1)), 0.0)
			best = minf(best, sqrt(dx * dx + dy * dy))
	return best


func _in_box(x: float, y: float, pad: float) -> bool:
	for b: PackedFloat32Array in _box_at.get(Vector2i(int(x), int(y)), []):
		if b[0] - pad < x and x < b[2] + pad and b[1] - pad < y and y < b[3] + pad:
			return true
	return false


## Whether furniture (the level's or what was added) stands within `pad` of
## (x, y).
func in_furniture(x: float, y: float, pad := 0.0) -> bool:
	return _in_box(x, y, pad)


# ------------------------------------------------------------------ writing


## A sprite standing at (x, y): camera-facing unless `plane` is a number; its
## z is from its cell's ground (on terrain, lifted onto the surface).
func add_board(image: String, x: float, y: float, height: float, z := 0.0) -> Dictionary:
	var lift := z
	var surface := floor_at(x, y)
	lift += surface - ground[cell(x, y)]
	var b := {
		"x": snappedf(x, .01),
		"y": snappedf(y, .01),
		"image": image,
		"height": snappedf(height, .01),
		"z": snappedf(lift, .01),
		"signal": "",
		"glow": false,
		"plane": null,
		"back": "",
	}
	var list: Array = level.get("billboards", [])
	list.append(b)
	level["billboards"] = list
	keep(x, y, num("clear", "board", .6))
	return b


## A base `r` half wide that stops a body (a trunk, a solid prop's foot), as
## the player maps' props have: furniture a few centimetres high, no walls.
func add_base(x: float, y: float, r: float) -> void:
	var g := floor_at(x, y)
	var row := [
		snappedf(x - r, .01),
		snappedf(y - r, .01),
		snappedf(x + r, .01),
		snappedf(y + r, .01),
		snappedf(g + .05, .01),
		"dirt",
		"dirt",
		snappedf(g, .01)
	]
	_furniture(row, false)


## A piece of furniture drawn and stood on (a trough, a table): its box, top,
## side and cap tiles, with its four walls and its cap as the builder writes.
func add_fixture(box: Rect2, top: float, side: String, cap: String) -> void:
	var g := floor_at(box.get_center().x, box.get_center().y)
	var row := [
		snappedf(box.position.x, .01),
		snappedf(box.position.y, .01),
		snappedf(box.end.x, .01),
		snappedf(box.end.y, .01),
		snappedf(g + top, .01),
		side,
		cap,
		snappedf(g, .01)
	]
	_furniture(row, true)


func _furniture(row: Array, drawn: bool) -> void:
	var fixtures: Array = level.get("fixtures", [])
	fixtures.append(row)
	level["fixtures"] = fixtures
	var volumes: Array = level.get("collision_volumes", [])
	volumes.append(row.duplicate())
	level["collision_volumes"] = volumes
	var x0: float = row[0]
	var y0: float = row[1]
	var x1: float = row[2]
	var y1: float = row[3]
	_add_box(PackedFloat32Array([x0, y0, x1, y1]))
	for yy in range(floori(y0), ceili(y1)):
		for xx in range(floori(x0), ceili(x1)):
			if inside(xx, yy):
				var c := yy * w + xx
				walk[c] = 0 if _in_box(xx + .5, yy + .5, 0.0) else walk[c]
	if not drawn:
		return
	var top: float = row[4]
	var bottom: float = row[7]
	var c := cell((x0 + x1) * .5, (y0 + y1) * .5)
	var light_list: Array = level.get("light", [])
	var lit: float = light_list[c] if c < light_list.size() else 1.0
	var face := tile_of(str(row[5]))
	var walls: Array = level.get("walls", [])
	var sides := [[x0, y0, x1, y0], [x1, y0, x1, y1], [x1, y1, x0, y1], [x0, y1, x0, y0]]
	for k in 4:
		var side: Array = sides[k]
		walls.append(
			side + [face, snappedf(lit * (1.0 if k % 2 == 0 else .84), .0001), bottom, top, area[c]]
		)
	level["walls"] = walls
	if top - bottom >= .15 and top - bottom < 1.5:
		var caps: Dictionary = level.get("caps", {})
		var key := str(snappedf(top, .01))
		var list: Array = caps.get(key, [])
		list.append([x0, y0, x1, y1, str(row[6])])
		caps[key] = list
		level["caps"] = caps
		LevelEdit.refresh_heights(level)
