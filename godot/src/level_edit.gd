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
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path_of(level_id)))
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
static func _json(value) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			var parts := PackedStringArray()
			for key in value:
				parts.append(JSON.stringify(str(key)) + ":" + _json(value[key]))
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var items := PackedStringArray()
			for item in value:
				items.append(_json(item))
			return "[" + ",".join(items) + "]"
		TYPE_FLOAT:
			if value == floorf(value) and absf(value) < 1e15:
				return str(int(value))
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
	var w := int(level["width"])
	var h := int(level["height"])
	var solid: Array = level["solid"]
	var wall_height: Array = level["wall_height"]
	var roof: Array = level["roof"]
	var light: Array = level["light"]
	var area: Array = level["area"]
	var ground: Array = level["ground"]
	var floor_tile: Array = level["floor"]
	var facades := String(level.get("id", "")) == "hickston"
	var fascia := int(tile_index.get("fascia", 0))
	var porch := int(tile_index.get("porch", 0))
	var shoulder := int(tile_index.get("shoulder", 0))
	var walls: Array = []
	for y in h:
		for x in w:
			var i := y * w + x
			var solid_here := int(solid[i]) >= 0
			for e: Array in EDGES:
				var nx: int = x + e[0]
				var ny: int = y + e[1]
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var n := ny * w + nx
				var edge := [x + e[2], y + e[3], x + e[4], y + e[5]]
				if solid_here and int(solid[n]) < 0:
					var top := maxf(float(wall_height[i]), float(roof[n]))
					var lit := float(light[n]) * (1.0 if e[0] == 0 else .83)
					var base := float(ground[n])
					if facades and int(area[n]) == 0 and y == 20 and top > 2.05:
						walls.append(edge + [int(solid[i]), lit, base, 2.14, int(area[n])])
						walls.append(edge + [fascia, lit, 2.14, top, int(area[n])])
					else:
						walls.append(edge + [int(solid[i]), lit, base, top, int(area[n])])
	for y in h:
		for x in w:
			var i := y * w + x
			if float(roof[i]) <= 0.0:
				continue
			for e: Array in EDGES:
				var nx: int = x + e[0]
				var ny: int = y + e[1]
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var n := ny * w + nx
				if int(solid[n]) >= 0 or float(roof[i]) <= float(roof[n]):
					continue
				var bottom := float(roof[n])
				var top := float(roof[i])
				if bottom == 0.0:
					bottom = top
					top = top + (.48 if facades and y == 20 and x == 23 else .35)
				walls.append(
					[
						x + e[2],
						y + e[3],
						x + e[4],
						y + e[5],
						fascia,
						float(light[n]),
						bottom,
						top,
						int(area[n])
					]
				)
	for y in h:
		for x in w:
			var i := y * w + x
			if int(solid[i]) >= 0:
				continue
			for e: Array in EDGES:
				var nx: int = x + e[0]
				var ny: int = y + e[1]
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var n := ny * w + nx
				if int(solid[n]) < 0 and float(ground[n]) < float(ground[i]):
					var riser := (
						shoulder
						if float(ground[n]) < 0.0 and int(floor_tile[i]) != porch
						else porch
					)
					walls.append(
						[
							x + e[2],
							y + e[3],
							x + e[4],
							y + e[5],
							riser,
							float(light[i]),
							float(ground[n]),
							float(ground[i]),
							int(area[i])
						]
					)
	for f: Array in level.get("fixtures", []):
		var x0 := float(f[0])
		var y0 := float(f[1])
		var x1 := float(f[2])
		var y1 := float(f[3])
		var c := int((y0 + y1) / 2.0) * w + int((x0 + x1) / 2.0)
		var sides := [[x0, y0, x1, y0], [x1, y0, x1, y1], [x1, y1, x0, y1], [x0, y1, x0, y0]]
		for k in 4:
			walls.append(
				(
					sides[k]
					+ [
						int(tile_index.get(String(f[5]), 0)),
						float(light[c]) * (1.0 if k % 2 == 0 else .84),
						float(f[7]),
						float(f[4]),
						int(area[c])
					]
				)
			)
	return walls


## A wall's identity for patching: where it is and what it is, not its light
## (the grids keep light rounded, so a stored wall's light may differ a little).
## Fields: the edge, the material, then the bottom and the top (parts 5 and 6).
static func _key(wall: Array) -> String:
	return (
		"%.3f,%.3f,%.3f,%.3f,%d,%.3f,%.3f,%d"
		% [
			float(wall[0]),
			float(wall[1]),
			float(wall[2]),
			float(wall[3]),
			int(wall[4]),
			float(wall[6]),
			float(wall[7]),
			int(wall[8])
		]
	)


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
			gone[edge].append(Vector2(float(parts[5]), float(parts[6])))
	var kept: Array = []
	for wall: Array in before.get("walls", []):
		var edge := (
			"%.3f,%.3f,%.3f,%.3f" % [float(wall[0]), float(wall[1]), float(wall[2]), float(wall[3])]
		)
		var dropped := false
		for span: Vector2 in gone.get(edge, []):
			if float(wall[6]) >= span.x - .001 and float(wall[7]) <= span.y + .001:
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
	for v in level["ground"]:
		heights[snappedf(float(v), .0001)] = true
	for key in level.get("caps", {}):
		heights[snappedf(float(key), .0001)] = true
	var sorted := heights.keys()
	sorted.sort()
	level["ground_heights"] = sorted
