## Water (pass 16, LOOKS): ponds, creeks and troughs, opt-in. Water stays the
## floor tiles the game already draws and plays (creek, bayou water and the
## deep water nobody wades: the shader's ripples, the wading rings); what is
## new is the bed under it, carved as terrain (geometry version 2, src/
## level_terrain.gd): the water lies [water] bed (.35) under the bank, its
## shore slopes down to it in the shore tile, and a pond's middle, deep_from
## cells or more from dry ground, drops to the deep tile at [water] deep (the
## shallows round it sloping down to it).
##
##   {"type": "pond", "polygon": [[20, 10], [27, 9], [29, 15], [21, 16]], "seed": 0}
##   {"type": "pond", "at": [24, 12], "radius": 3.5}
##   {"type": "creek", "points": [[0, 30], [18, 28], [40, 33], [64, 31]], "width": 2}
##   {"type": "trough", "at": [12.5, 8.5], "along": "x", "length": 2}
##
## A pond's water is flat (its lowest bank less the bed); a creek's follows
## the ground down. Where a creek crosses a road a plank bridge goes over it,
## railed on the sides over the water. Nothing standing is drowned: a cell
## with a thing, a door, a station or furniture in it stays dry (water_thing
## says so), and so does a cell under a roof or a deck.
class_name MapWater
extends RefCounted


static func _info() -> Dictionary:
	var found: Dictionary = MapLooksGrid.tuning().get("water", {})
	return found


## A pond. Returns {"cells": count, "problems": [...]}.
static func pond(grid: MapLooksGrid, spec: Dictionary) -> Dictionary:
	var wet := {}
	var polygon := PackedVector2Array()
	var listed: Variant = spec.get("polygon")
	var points: Array = listed if listed is Array else []
	for item: Variant in points:
		var pair: Array = item if item is Array else []
		if pair.size() >= 2:
			polygon.append(Vector2(MapLooksGrid.f(pair[0]), MapLooksGrid.f(pair[1])))
	var at: Array = spec.get("at", []) if spec.get("at") is Array else []
	var radius := MapLooksGrid.f(spec.get("radius", 0.0))
	var rect: Array = spec.get("rect", []) if spec.get("rect") is Array else []
	for c in grid.w * grid.h:
		var p := Vector2((c % grid.w) + .5, (c / grid.w) + .5)
		var inside := false
		if polygon.size() >= 3:
			inside = Geometry2D.is_point_in_polygon(p, polygon)
		elif at.size() >= 2 and radius > 0.0:
			inside = p.distance_to(Vector2(MapLooksGrid.f(at[0]), MapLooksGrid.f(at[1]))) <= radius
		elif rect.size() == 4:
			inside = (
				p.x >= MapLooksGrid.f(rect[0])
				and p.x <= MapLooksGrid.f(rect[2]) + 1.0
				and p.y >= MapLooksGrid.f(rect[1])
				and p.y <= MapLooksGrid.f(rect[3]) + 1.0
			)
		if inside:
			wet[c] = true
	return _carve(grid, spec, wet, true, [])


## A creek along a polyline, `width` wide (at least a cell).
static func creek(grid: MapLooksGrid, spec: Dictionary) -> Dictionary:
	var line: Array[Vector2] = []
	var listed: Variant = spec.get("points")
	var points: Array = listed if listed is Array else []
	for item: Variant in points:
		var pair: Array = item if item is Array else []
		if pair.size() >= 2:
			line.append(Vector2(MapLooksGrid.f(pair[0]), MapLooksGrid.f(pair[1])))
	if line.size() < 2:
		return {"cells": 0, "problems": [["water_shape", "a creek wants two points or more"]]}
	var half := maxf(MapLooksGrid.f(spec.get("width", 1.6)) * .5, .5)
	var wet := {}
	for c in grid.w * grid.h:
		var p := Vector2((c % grid.w) + .5, (c / grid.w) + .5)
		for i in range(1, line.size()):
			var q := Geometry2D.get_closest_point_to_segment(p, line[i - 1], line[i])
			if p.distance_to(q) <= half:
				wet[c] = true
				break
	# A thin creek still runs unbroken: every cell its line passes through.
	for i in range(1, line.size()):
		var steps := ceili(line[i - 1].distance_to(line[i]) * 3.0)
		for k in steps + 1:
			var p := line[i - 1].lerp(line[i], float(k) / maxi(steps, 1))
			if p.x >= 0.0 and p.y >= 0.0 and p.x < grid.w and p.y < grid.h:
				wet[grid.cell(p.x, p.y)] = true
	return _carve(grid, spec, wet, false, line)


## A stock trough: tin sides, water in it, `length` long along x or y.
static func trough(grid: MapLooksGrid, spec: Dictionary) -> Dictionary:
	var at: Array = spec.get("at", []) if spec.get("at") is Array else []
	if at.size() < 2:
		return {"cells": 0, "problems": [["water_shape", "a trough wants at [x, y]"]]}
	var length := clampf(MapLooksGrid.f(spec.get("length", 2.0)), .8, 4.0)
	var p := Vector2(MapLooksGrid.f(at[0]), MapLooksGrid.f(at[1]))
	var along_x := str(spec.get("along", "x")) != "y"
	var half := Vector2(length * .5, .3) if along_x else Vector2(.3, length * .5)
	var box := Rect2(p - half, half * 2.0)
	for y in range(floori(box.position.y), ceili(box.end.y)):
		for x in range(floori(box.position.x), ceili(box.end.x)):
			if not grid.inside(x, y) or not grid.is_open(y * grid.w + x):
				return {
					"cells": 0, "problems": [["water_shape", "a trough must stand on open floor"]]
				}
	grid.add_fixture(box, .45, "tin", "creek")
	return {"cells": 0, "problems": []}


## Carve the cells in `wet` (those that may be) into water with a bed, a shore
## and (for a pond) deep water; a creek's road crossings get bridges.
static func _carve(
	grid: MapLooksGrid, spec: Dictionary, asked: Dictionary, flat: bool, line: Array[Vector2]
) -> Dictionary:
	var problems: Array = []
	var info := _info()
	var lv := grid.level
	var roads: Array = MapLooksGrid.tuning().get("roads", [])
	var busy := _busy_cells(grid)
	var wet := {}
	var crossing := {}
	var drowned := 0
	var keys: Array = asked.keys()
	keys.sort()
	for k: Variant in keys:
		var c: int = k
		if not grid.is_open(c) or grid.roof[c] > 0.0 or grid.covered[c] != 0:
			continue
		if busy.has(c) or grid.in_furniture((c % grid.w) + .5, (c / grid.w) + .5, -.05):
			drowned += 1
			continue
		if roads.has(grid.floor_name(c)):
			if flat:
				drowned += 1
				continue
			crossing[c] = true
		wet[c] = true
	if drowned > 0:
		problems.append(
			[
				"water_thing",
				(
					"%s: %d cell(s) left dry (a thing, door, station, road or furniture in them)"
					% [str(spec.get("id", "water")), drowned]
				)
			]
		)
	if wet.is_empty():
		problems.append(
			["water_none", "%s: no open ground to carve" % str(spec.get("id", "water"))]
		)
		return {"cells": 0, "problems": problems}
	var w := grid.w
	var h := grid.h
	# The deep: a pond's cells with no dry cell within deep_from, by the
	# straight distance between cell middles (pass 16, T7: a round pond gets a
	# round deep, not the cross a square neighbourhood left).
	var deep := {}
	var deep_from := int(MapLooksGrid.f(info.get("deep_from", 2)))
	var wants_deep: bool = spec.get("deep", true)
	if flat and wants_deep:
		for k: Variant in wet:
			var c: int = k
			var x := c % w
			var y := c / w
			var all_wet := true
			for dy in range(-deep_from, deep_from + 1):
				for dx in range(-deep_from, deep_from + 1):
					if dx * dx + dy * dy > deep_from * deep_from:
						continue
					var n := (y + dy) * w + x + dx
					if not grid.inside(x + dx, y + dy) or not wet.has(n):
						all_wet = false
			if all_wet:
				deep[c] = true
	# The shore: open dry cells beside the water (eight ways).
	var shore := {}
	for k: Variant in wet:
		var c: int = k
		var x := c % w
		var y := c / w
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if not grid.inside(x + dx, y + dy):
					continue
				var n := (y + dy) * w + x + dx
				if not wet.has(n) and grid.is_open(n) and grid.roof[n] <= 0.0:
					shore[n] = true
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for k: Variant in wet.keys() + shore.keys():
		var c: int = k
		x0 = mini(x0, c % w)
		y0 = mini(y0, c / w)
		x1 = maxi(x1, c % w)
		y1 = maxi(y1, c / w)
	var pw := x1 - x0 + 1
	var ph := y1 - y0 + 1
	var bed := MapLooksGrid.f(spec.get("depth", info.get("bed", .35)))
	var deep_z := MapLooksGrid.f(info.get("deep", .8))
	# Each corner's height before: the surface there, else its lowest open
	# neighbour's ground; a pond's water is its lowest wet corner's less the bed.
	var base := PackedFloat32Array()
	var wet_corner := PackedByteArray()
	var deep_corner := PackedByteArray()
	base.resize((pw + 1) * (ph + 1))
	wet_corner.resize(base.size())
	deep_corner.resize(base.size())
	var lowest := INF
	for cy in ph + 1:
		for cx in pw + 1:
			var gx := x0 + cx
			var gy := y0 + cy
			var i := cy * (pw + 1) + cx
			var here := NAN
			if grid.terrain != null:
				here = _terrain_corner(grid, gx, gy)
			var low := INF
			var any_wet := false
			var any_deep := false
			for d: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
				var tx := gx + d.x
				var ty := gy + d.y
				if not grid.inside(tx, ty):
					continue
				var t := ty * w + tx
				if grid.is_open(t):
					low = minf(low, grid.ground[t])
				any_wet = any_wet or wet.has(t)
				any_deep = any_deep or deep.has(t)
			if is_nan(here):
				here = low if low != INF else 0.0
			base[i] = here
			wet_corner[i] = 1 if any_wet else 0
			deep_corner[i] = 1 if any_deep else 0
			if any_wet:
				lowest = minf(lowest, here)
	var heights: Array = []
	var corner_z := PackedFloat32Array()
	corner_z.resize(base.size())
	for i in base.size():
		var z := base[i]
		if wet_corner[i] != 0:
			var top := lowest if flat else base[i]
			z = top - (deep_z if deep_corner[i] != 0 else bed)
		corner_z[i] = z
		heights.append(roundi(z * 100.0))
	var id := str(spec.get("id", "water%d" % _terrain_count(lv)))
	var patch := {"id": id, "x": x0, "y": y0, "w": pw, "h": ph, "heights": heights}
	_add_terrain(lv, patch)
	# Tiles and grounds: water, deep, shore; each patch cell's ground its
	# lowest corner (so readers of a cell's ground stay under the surface).
	var floors: Array = lv["floor"]
	var grounds: Array = lv["ground"]
	var water_tile := MapLooksGrid.tile_of(str(spec.get("tile", info.get("tile", "creek"))))
	var deep_tile := MapLooksGrid.tile_of(str(info.get("deep_tile", "bayou_deep")))
	var shore_name := str(spec.get("shore", info.get("shore", "bayou_bank")))
	var shore_tile := MapLooksGrid.tile_of(shore_name) if shore_name != "" else -1
	for cy in ph:
		for cx in pw:
			var c := (y0 + cy) * w + x0 + cx
			var i := cy * (pw + 1) + cx
			var low := minf(
				minf(corner_z[i], corner_z[i + 1]), minf(corner_z[i + pw + 1], corner_z[i + pw + 2])
			)
			grounds[c] = snappedf(minf(low, MapLooksGrid.f(grounds[c])), .01)
			if deep.has(c) and deep_tile >= 0:
				floors[c] = deep_tile
			elif wet.has(c) and water_tile >= 0:
				floors[c] = water_tile
			elif shore.has(c) and shore_tile >= 0 and not roads.has(grid.floor_name(c)):
				floors[c] = shore_tile
	LevelEdit.refresh_heights(lv)
	if not crossing.is_empty():
		_bridges(grid, crossing, wet, shore, line, base, x0, y0, pw)
	return {"cells": wet.size(), "problems": problems}


## Cells holding something that must stay dry: a door, a station, the exit,
## a spawn, a thing (a pickup, a hand, a board).
static func _busy_cells(grid: MapLooksGrid) -> Dictionary:
	var out := {}
	var lv := grid.level
	for d: Variant in lv.get("doors", []):
		var door: Dictionary = d
		out[grid.cell(MapLooksGrid.f(door.get("x", 0)), MapLooksGrid.f(door.get("y", 0)))] = true
	for p in grid.objectives():
		out[grid.cell(p.x, p.y)] = true
	for p in grid.spawns():
		out[grid.cell(p.x, p.y)] = true
	for e: Variant in lv.get("enemies", []):
		var en: Dictionary = e
		out[grid.cell(MapLooksGrid.f(en.get("x", 0.0)), MapLooksGrid.f(en.get("y", 0.0)))] = true
	for key: String in ["pickups", "props"]:
		for p: Variant in lv.get(key, []):
			var row: Array = p
			out[grid.cell(MapLooksGrid.f(row[1]), MapLooksGrid.f(row[2]))] = true
	for b: Variant in lv.get("billboards", []):
		var board: Dictionary = b
		out[grid.cell(MapLooksGrid.f(board.get("x", 0.0)), MapLooksGrid.f(board.get("y", 0.0)))] = true
	return out


## The surface's height at a corner (gx, gy) from the terrain already there.
static func _terrain_corner(grid: MapLooksGrid, gx: int, gy: int) -> float:
	for d: Vector2 in [
		Vector2(.001, .001), Vector2(-.001, .001), Vector2(.001, -.001), Vector2(-.001, -.001)
	]:
		var z := grid.terrain.height_at(gx + d.x, gy + d.y)
		if not is_nan(z):
			return z
	return NAN


static func _terrain_count(lv: Dictionary) -> int:
	var block: Variant = lv.get("geometry")
	if block is Dictionary:
		var geo: Dictionary = block
		var list: Array = geo.get("terrain", [])
		return list.size()
	return 0


## The level's geometry block (made, version 2, if it had none).
static func geometry(lv: Dictionary) -> Dictionary:
	var block: Variant = lv.get("geometry")
	if not (block is Dictionary):
		block = {"version": 2, "slabs": [], "segments": [], "ceilings": [], "ladders": []}
		lv["geometry"] = block
		lv["format"] = LevelData.FORMAT
	var geo: Dictionary = block
	for key: String in ["slabs", "segments", "ceilings", "ladders"]:
		if not geo.has(key):
			geo[key] = []
	return geo


static func _add_terrain(lv: Dictionary, patch: Dictionary) -> void:
	var geo := geometry(lv)
	var list: Array = geo.get("terrain", [])
	list.append(patch)
	geo["terrain"] = list
	geo["version"] = maxi(2, LevelGeometry.version_for(geo))


## A plank bridge over each run of road the creek crosses: a deck a hair over
## the road from bank to bank, railed along the sides over the water.
static func _bridges(
	grid: MapLooksGrid,
	crossing: Dictionary,
	wet: Dictionary,
	shore: Dictionary,
	line: Array[Vector2],
	base: PackedFloat32Array,
	x0: int,
	y0: int,
	pw: int
) -> void:
	var info := _info()
	var w := grid.w
	var roads: Array = MapLooksGrid.tuning().get("roads", [])
	var seen := {}
	var keys: Array = crossing.keys()
	keys.sort()
	var count := 0
	for k: Variant in keys:
		var start: int = k
		if seen.has(start):
			continue
		# The road cells of this crossing, wet or shore, joined four ways.
		var group: Array[int] = [start]
		seen[start] = true
		var at := 0
		while at < group.size():
			var c := group[at]
			at += 1
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := c % w + d.x
				var ny := c / w + d.y
				if not grid.inside(nx, ny):
					continue
				var n := ny * w + nx
				if seen.has(n) or not (wet.has(n) or shore.has(n)):
					continue
				if not roads.has(grid.floor_name(n)):
					continue
				seen[n] = true
				group.append(n)
		var box := Rect2(group[0] % w, group[0] / w, 1, 1)
		var top := INF
		for c in group:
			box = box.merge(Rect2(c % w, c / w, 1, 1))
		for cy in range(int(box.position.y), int(box.end.y) + 1):
			for cx in range(int(box.position.x), int(box.end.x) + 1):
				var i := (cy - y0) * (pw + 1) + (cx - x0)
				if i >= 0 and i < base.size():
					top = minf(top, base[i])
		if top == INF:
			top = 0.0
		top += MapLooksGrid.f(info.get("bridge_top", .06))
		# Which way the water runs here: the rails go on the two sides it
		# runs under.
		var mid := box.get_center()
		var flow := Vector2.RIGHT
		var best := INF
		for i in range(1, line.size()):
			var q := Geometry2D.get_closest_point_to_segment(mid, line[i - 1], line[i])
			if q.distance_to(mid) < best:
				best = q.distance_to(mid)
				flow = line[i] - line[i - 1]
		var geo := geometry(grid.level)
		var id := "bridge%d" % count
		count += 1
		var tile := str(info.get("bridge_tile", "bayou_planks"))
		var slabs: Array = geo["slabs"]
		(
			slabs
			. append(
				{
					"id": id,
					"kind": "deck",
					"x0": snappedf(box.position.x, .001),
					"y0": snappedf(box.position.y, .001),
					"x1": snappedf(box.end.x, .001),
					"y1": snappedf(box.end.y, .001),
					"top": snappedf(top, .001),
					"thick": .15,
					"tile": tile,
					"under": tile,
					"edge": tile,
					"light": .85,
					"area": grid.area[grid.cell(mid.x, mid.y)],
				}
			)
		)
		var segments: Array = geo["segments"]
		var inset := .06
		var sides: Array = []
		if absf(flow.x) >= absf(flow.y):
			sides = [
				[
					Vector2(box.position.x + inset, box.position.y),
					Vector2(box.position.x + inset, box.end.y)
				],
				[Vector2(box.end.x - inset, box.position.y), Vector2(box.end.x - inset, box.end.y)],
			]
		else:
			sides = [
				[
					Vector2(box.position.x, box.position.y + inset),
					Vector2(box.end.x, box.position.y + inset)
				],
				[Vector2(box.position.x, box.end.y - inset), Vector2(box.end.x, box.end.y - inset)],
			]
		for s in sides.size():
			var ends: Array = sides[s]
			var a: Vector2 = ends[0]
			var b: Vector2 = ends[1]
			(
				segments
				. append(
					{
						"id": "%s_rail%d" % [id, s],
						"a": [snappedf(a.x, .001), snappedf(a.y, .001)],
						"b": [snappedf(b.x, .001), snappedf(b.y, .001)],
						"z0": snappedf(top, .001),
						"z1": snappedf(top + .95, .001),
						"thick": .08,
						"tile": "stockyard",
						"light": .85,
						"area": grid.area[grid.cell(mid.x, mid.y)],
						"sight": false,
						"shots": false,
					}
				)
			)
