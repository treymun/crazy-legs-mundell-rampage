## Changing a level: res://data/<id>.json is the source of every map.
##
## Its wall list is mostly what the grids imply (the sides of solid cells, roof
## edges, floor steps, fixture boxes), plus hand-built pieces (building fronts,
## interiors) that no rule gives back. So a change to the grids never rebuilds
## the list: it is patched. The walls the grids imply are worked out before and
## after the change; the ones that went away are taken out of the stored list
## and the new ones added, and every other wall stays exactly as it was.
##
## The in-game editor (level_editor.gd), tools/level_edit.gd and the Godot
## editor's Levels screen (addons/clmr_levels) use this, hence @tool.
@tool
class_name LevelEdit
extends RefCounted

const EDGES := [[0, -1, 0, 0, 1, 0], [1, 0, 1, 0, 1, 1], [0, 1, 1, 1, 0, 1], [-1, 0, 0, 1, 0, 0]]


static func path_of(level_id: String) -> String:
	return "res://data/%s.json" % level_id


static func read(level_id: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path_of(level_id)))
	return parsed if parsed is Dictionary else {}


## Write a level back in the same compact form it is kept in.
static func write(level_id: String, level: Dictionary) -> bool:
	var file := FileAccess.open(ProjectSettings.globalize_path(path_of(level_id)), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(_json(level))
	file.close()
	return true


## Compact JSON: whole numbers without a decimal point, the rest as short as
## they round-trip (the files were written that way).
static func _json(value: Variant) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			var parts := PackedStringArray()
			for key: Variant in value:
				parts.append(JSON.stringify(str(key)) + ":" + _json(value[key]))
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var items := PackedStringArray()
			for item: Variant in value:
				items.append(_json(item))
			return "[" + ",".join(items) + "]"
		TYPE_FLOAT:
			var number: float = value
			if number == floorf(number) and absf(number) < 1e15:
				return str(int(number))
			return str(value)
		TYPE_INT:
			return str(value)
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_NIL:
			return "null"
		_:
			return JSON.stringify(str(value))


## The walls the grids and fixtures imply (the reference's wall_segments()).
static func implied_walls(level: Dictionary, tile_index: Dictionary) -> Array:
	var w: int = level["width"]
	var h: int = level["height"]
	var solid: Array = level["solid"]
	var wall_height: Array = level["wall_height"]
	var roof: Array = level["roof"]
	var light: Array = level["light"]
	var area: Array = level["area"]
	var ground: Array = level["ground"]
	var floor_tile: Array = level["floor"]
	# A row of building fronts with a fascia band above the door height (the
	# old town's main street; hub.json still has it).
	var facade_row: int = level.get("facade_row", -1)
	var facades := facade_row >= 0
	var cap: Array = level.get("fascia_cap", [-1, -1])
	var fascia: int = tile_index.get("fascia", 0)
	var porch: int = tile_index.get("porch", 0)
	var shoulder: int = tile_index.get("shoulder", 0)
	var walls: Array = []
	for y in h:
		for x in w:
			var i := y * w + x
			var solid_i: int = solid[i]
			var solid_here := solid_i >= 0
			for e: Array in EDGES:
				var nx: int = x + e[0]
				var ny: int = y + e[1]
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var n := ny * w + nx
				var edge := [x + e[2], y + e[3], x + e[4], y + e[5]]
				var solid_n: int = solid[n]
				if solid_here and solid_n < 0:
					var wall_i: float = wall_height[i]
					var roof_n: float = roof[n]
					var top := maxf(wall_i, roof_n)
					var light_n: float = light[n]
					var lit := light_n * (1.0 if e[0] == 0 else .83)
					var base: float = ground[n]
					var area_n: int = area[n]
					if facades and area_n == 0 and y == facade_row and top > 2.05:
						walls.append(edge + [solid_i, lit, base, 2.14, area_n])
						walls.append(edge + [fascia, lit, 2.14, top, area_n])
					else:
						walls.append(edge + [solid_i, lit, base, top, area_n])
	for y in h:
		for x in w:
			var i := y * w + x
			var roof_i: float = roof[i]
			if roof_i <= 0.0:
				continue
			for e: Array in EDGES:
				var nx: int = x + e[0]
				var ny: int = y + e[1]
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var n := ny * w + nx
				var solid_n: int = solid[n]
				var roof_n: float = roof[n]
				if solid_n >= 0 or roof_i <= roof_n:
					continue
				var bottom := roof_n
				var top := roof_i
				if bottom == 0.0:
					bottom = top
					var cap_x: int = cap[0]
					var cap_y: int = cap[1]
					top = top + (.48 if facades and y == cap_y and x == cap_x else .35)
				var light_n: float = light[n]
				var area_n: int = area[n]
				walls.append(
					[x + e[2], y + e[3], x + e[4], y + e[5], fascia, light_n, bottom, top, area_n]
				)
	for y in h:
		for x in w:
			var i := y * w + x
			var solid_i: int = solid[i]
			if solid_i >= 0:
				continue
			var ground_i: float = ground[i]
			for e: Array in EDGES:
				var nx: int = x + e[0]
				var ny: int = y + e[1]
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var n := ny * w + nx
				var solid_n: int = solid[n]
				var ground_n: float = ground[n]
				if solid_n < 0 and ground_n < ground_i:
					var floor_i: int = floor_tile[i]
					var riser := shoulder if ground_n < 0.0 and floor_i != porch else porch
					var light_i: float = light[i]
					var area_i: int = area[i]
					walls.append(
						[
							x + e[2],
							y + e[3],
							x + e[4],
							y + e[5],
							riser,
							light_i,
							ground_n,
							ground_i,
							area_i
						]
					)
	for f: Array in level.get("fixtures", []):
		var x0: float = f[0]
		var y0: float = f[1]
		var x1: float = f[2]
		var y1: float = f[3]
		var c := int((y0 + y1) / 2.0) * w + int((x0 + x1) / 2.0)
		var sides := [[x0, y0, x1, y0], [x1, y0, x1, y1], [x1, y1, x0, y1], [x0, y1, x0, y0]]
		var face: int = tile_index.get(str(f[5]), 0)
		var light_c: float = light[c]
		var f_bottom: float = f[7]
		var f_top: float = f[4]
		var area_c: int = area[c]
		for k in 4:
			var side: Array = sides[k]
			walls.append(
				side + [face, light_c * (1.0 if k % 2 == 0 else .84), f_bottom, f_top, area_c]
			)
	return walls


## A wall's identity for patching: where it is and what it is, not its light
## (the grids keep light rounded, so a stored wall's light may differ a little).
## Fields: the edge, the material, then the bottom and the top (parts 5 and 6).
static func _key(wall: Array) -> String:
	var x0: float = wall[0]
	var y0: float = wall[1]
	var x1: float = wall[2]
	var y1: float = wall[3]
	var face: int = wall[4]
	var bottom: float = wall[6]
	var top: float = wall[7]
	var area: int = wall[8]
	return "%.3f,%.3f,%.3f,%.3f,%d,%.3f,%.3f,%d" % [x0, y0, x1, y1, face, bottom, top, area]


## Patch `after`'s wall list for the change from `before` (see the top).
static func patch_walls(before: Dictionary, after: Dictionary, tile_index: Dictionary) -> void:
	var was := {}
	for wall: Array in implied_walls(before, tile_index):
		was[_key(wall)] = true
	var now := {}
	for wall: Array in implied_walls(after, tile_index):
		now[_key(wall)] = wall
	# A wall the grids implied and no longer do takes with it every stored wall
	# on the same edge within its height: a dressing pass split many of them
	# into a base trim, a body and a cap.
	var gone := {}
	for key: String in was:
		if not now.has(key):
			var parts := key.split(",")
			var edge := ",".join(parts.slice(0, 4))
			if not gone.has(edge):
				gone[edge] = []
			var spans: Array = gone[edge]
			spans.append(Vector2(float(parts[5]), float(parts[6])))
	var kept: Array = []
	for wall: Array in before.get("walls", []):
		var x0: float = wall[0]
		var y0: float = wall[1]
		var x1: float = wall[2]
		var y1: float = wall[3]
		var edge := "%.3f,%.3f,%.3f,%.3f" % [x0, y0, x1, y1]
		var dropped := false
		for span: Vector2 in gone.get(edge, []):
			var bottom: float = wall[6]
			var top: float = wall[7]
			if bottom >= span.x - .001 and top <= span.y + .001:
				dropped = true
				break
		if not dropped:
			kept.append(wall)
	for key: String in now:
		if not was.has(key):
			kept.append(now[key])
	after["walls"] = kept


## The floor heights after a ground change (the renderer draws one plane each).
static func refresh_heights(level: Dictionary) -> void:
	var heights := {}
	for v: float in level["ground"]:
		heights[snappedf(float(v), .0001)] = true
	for key: String in level.get("caps", {}):
		heights[snappedf(float(key), .0001)] = true
	var sorted := heights.keys()
	sorted.sort()
	level["ground_heights"] = sorted
