## Source v2's compile (pass 16, T7): the high-level types of
## map_source_v2.gd turned into the level builder's cells and geometry, the
## map kit's pieces (src/map_kit/), triggers and stations, the 5v5 and
## deathmatch plan, and the looks (MapLooks). map_compile.gd calls begin()
## before the objects, apply() for each v2 object in order, finish() before
## the level is written out and looks() on the finished level.
##
## Order: everything is laid in the source's order, except what needs the
## whole map first: terrain heights (brushes add up, so they are summed over
## the map and written as patches at the end), logic (it names doors by id),
## the versus plan, and the looks (they go over the finished level, water
## first, foliage last).
extends RefCounted

const Geo := preload("res://tools/levels/geo_kit.gd")
const V2 := preload("res://tools/map/map_source_v2.gd")
## The tiles a road's shoulder and ditch take.
const SHOULDER := "shoulder"
## A ditch beside a road: this deep, a cell wide.
const DITCH := .35
## Places round a team start are this far apart at least.
const TEAM_GAP := 1.4


static func _issue(severity: String, code: String, object_id: String, message: String, hint := "") -> Dictionary:
	var d := {"severity": severity, "code": code, "object": object_id, "message": message}
	if hint != "":
		d["hint"] = hint
	return d


## Whether the source compiles as version 2 (says so, or uses anything of it).
static func is_v2(doc: Dictionary, types: Dictionary) -> bool:
	return int(doc.get("version", 1)) >= 2 or V2.needed(doc, types) >= 2


static func begin(b, doc: Dictionary, ctx: Dictionary) -> void:
	# Every v2 map walks its doorways and stairs by via points (T4).
	Geo.ways(b)
	var records: Array[Dictionary] = []
	ctx["kit_records"] = records
	ctx["seed"] = int(doc["seed"]) if doc.has("seed") else hash(str(doc.get("id", "")))
	ctx["cost"] = 0
	var field := PackedFloat32Array()
	field.resize((b.w + 1) * (b.h + 1))
	ctx["field"] = field
	ctx["patches"] = []
	ctx["logic"] = []
	ctx["versus"] = []
	ctx["looks"] = {"water": [], "set_pieces": [], "vignettes": [], "dress": [], "foliage": []}


## One v2 object (defaults merged in `v`, as written in `o`). Returns the
## ids of the pieces it made (for validate's overlap names).
static func apply(b, type: String, v: Dictionary, o: Dictionary, ctx: Dictionary) -> Array:
	var id := str(o["id"])
	var made: Array = []
	var row: Dictionary = ctx["types"].get(type, {})
	if bool(row.get("kit", false)) or type == "kit":
		return _kit(b, type, o, ctx)
	match type:
		"terrain":
			_terrain(b, v, ctx)
		"road":
			_road(b, v, ctx)
		"creek", "pond", "trough":
			var spec := _looks_spec(o, ["id", "type"])
			spec["type"] = type
			spec["id"] = id
			if type == "pond" and o.has("rect"):
				spec["rect"] = _inclusive(o["rect"])
			ctx["looks"]["water"].append(spec)
		"foliage":
			var spec := _looks_spec(o, ["id", "type", "rect"])
			if o.has("rect") and not (o["rect"] as Array).is_empty():
				spec["area"] = _inclusive(o["rect"])
			ctx["looks"]["foliage"].append(spec)
		"dress":
			var spec := _looks_spec(o, ["id", "type", "rect"])
			spec["area"] = _inclusive(o["rect"])
			ctx["looks"]["dress"].append(spec)
		"vignette":
			ctx["looks"]["vignettes"].append({"id": o["name"], "at": o["at"], "wall": o["wall"]})
		"set_piece":
			var spec := _looks_spec(o, ["type"])
			ctx["looks"]["set_pieces"].append(spec)
		"switch", "key", "kill_gate", "wake_zone", "message", "trigger":
			ctx["logic"].append(v)
		"dm_spawn", "team_spawn", "bomb_site", "hostage", "rescue_zone", "bot_route", "bot_hold":
			ctx["versus"].append(v)
		"via":
			var at: Array = v["at"]
			Geo.via(b, float(at[0]), float(at[1]), float(v["z"]))
	return made


static func _looks_spec(o: Dictionary, drop: Array) -> Dictionary:
	var out := {}
	for key: String in o:
		if not (key in drop) and not key.begins_with("_"):
			out[key] = o[key]
	return out


## A source rect (x1, y1 exclusive) as the looks layer's (both corners in).
static func _inclusive(r: Array) -> Array:
	return [int(r[0]), int(r[1]), int(r[2]) - 1, int(r[3]) - 1]


# --------------------------------------------------------------------- kit


static func _kit(b, type: String, o: Dictionary, ctx: Dictionary) -> Array:
	var id := str(o["id"])
	var piece := str(o.get("piece", type)) if type == "kit" else type
	var spec := V2._kit_spec(o, piece)
	if str(o.get("district", "")) != "":
		spec["area"] = ctx["district_of"].call(o)
	var one := LevelParts.new()
	one.seed = int(ctx["seed"])
	one.width = b.w
	one.height = b.h
	one.pieces.assign(ctx["kit_records"])
	var made := KitPiece.build(spec, one)
	if made.has("error"):
		var line := str(made["error"])
		ctx["issues"].append(_issue("error", _kit_code(line), id, line, _kit_hint(line, piece)))
		return []
	Geo.kit_apply(b, one)
	var records: Array[Dictionary] = []
	records.assign(one.pieces)
	ctx["kit_records"] = records
	ctx["cost"] = int(ctx["cost"]) + int(made.get("cost", 0))
	var ids: Array = []
	var geo := one.geometry()
	for key: String in ["slabs", "segments", "ceilings", "ladders"]:
		for part: Dictionary in geo[key]:
			ids.append(str(part.get("id", "")))
	return ids


## A kit refusal's code (map_notes/t7.md lists them).
static func _kit_code(line: String) -> String:
	if line.contains("runs off the map"):
		return "kit_outside"
	if line.contains("stands on"):
		return "kit_overlap"
	if line.contains("pieces of building"):
		return "cost"
	if line.contains(" takes no "):
		return "kit_option"
	if line.contains(": w is") or line.contains(": d is"):
		return "kit_size"
	if line.contains(" is "):
		return "kit_option"
	return "kit"


static func _kit_hint(line: String, piece: String) -> String:
	var entry := KitPiece.catalog(piece)
	if line.contains("runs off the map"):
		return "move `at` so the whole footprint is inside the map's border (a cell in from each edge)"
	if line.contains("stands on"):
		return "buildings may not overlap: move one of them (map render shows their footprints)"
	if line.contains("pieces of building"):
		return "make it smaller or plainer (fewer storeys, no porch)"
	var keys := PackedStringArray(V2.KIT_COMMON)
	for key: String in entry.get("options", {}):
		keys.append(key)
	return "%s takes: %s (sizes: w %s, d %s)" % [
		piece, ", ".join(keys), str(entry.get("w", [])), str(entry.get("d", []))
	]


# ----------------------------------------------------------------- terrain


## A brush added into the map's corner heights; its patch noted for finish().
static func _terrain(b, v: Dictionary, ctx: Dictionary) -> void:
	var r: Array = v["rect"]
	var x0 := clampi(int(r[0]), 0, b.w - 1)
	var y0 := clampi(int(r[1]), 0, b.h - 1)
	var x1 := clampi(int(r[2]), x0 + 1, b.w)
	var y1 := clampi(int(r[3]), y0 + 1, b.h)
	var field: PackedFloat32Array = ctx["field"]
	brush(field, b.w + 1, x0, y0, x1, y1, v)
	if str(v["floor"]) != "":
		b.paint(x0, y0, x1 - 1, y1 - 1, str(v["floor"]))
	ctx["patches"].append(
		{"id": str(v["id"]), "rect": [x0, y0, x1, y1], "cliff": v["cliff"], "light": v["light"]}
	)


## Corner heights over [x0, x1] x [y0, y1] (corners) changed by one brush.
## `stride` is the field's row length (map width + 1).
static func brush(
	field: PackedFloat32Array, stride: int, x0: int, y0: int, x1: int, y1: int, v: Dictionary
) -> void:
	var kind := str(v.get("brush", "hill"))
	var height := float(v.get("height", 2.0))
	var mid := Vector2((x0 + x1) * .5, (y0 + y1) * .5)
	var half := Vector2(maxf((x1 - x0) * .5, .5), maxf((y1 - y0) * .5, .5))
	var fall := maxf(float(v.get("falloff", 3)), .5)
	var w := x1 - x0
	var h := y1 - y0
	if kind == "smooth":
		for _pass in clampi(int(v.get("passes", 2)), 1, 8):
			var copy := field.duplicate()
			for y in range(y0 + 1, y1):
				for x in range(x0 + 1, x1):
					var i := y * stride + x
					field[i] = (copy[i] * 4.0 + copy[i - 1] + copy[i + 1] + copy[i - stride] + copy[i + stride]) / 8.0
		return
	var heights: Array = v.get("heights", [])
	var seed := int(v.get("seed", 1))
	var scale := maxf(float(v.get("scale", 4.0)), 1.0)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var i := y * stride + x
			var d := Vector2((x - mid.x) / half.x, (y - mid.y) / half.y)
			var edge := minf(minf(x - x0, x1 - x), minf(y - y0, y1 - y))
			match kind:
				"hill":
					field[i] += height * (.5 + .5 * cos(PI * minf(d.length(), 1.0)))
				"ditch":
					# A trench along the rect's long side, deepest down its middle.
					var across := absf(d.y) if w >= h else absf(d.x)
					var ends := minf(x - x0, x1 - x) if w >= h else minf(y - y0, y1 - y)
					var shape := (.5 + .5 * cos(PI * minf(across, 1.0))) * minf(ends / fall, 1.0)
					field[i] -= absf(height) * shape
				"plateau":
					var up := height * smoothstep(0.0, 1.0, minf(edge / fall, 1.0))
					field[i] = maxf(field[i], up)
				"ramp":
					var t := 0.0
					match str(v.get("toward", "n")):
						"n":
							t = float(y1 - y) / maxf(h, 1)
						"s":
							t = float(y - y0) / maxf(h, 1)
						"e":
							t = float(x - x0) / maxf(w, 1)
						"w":
							t = float(x1 - x) / maxf(w, 1)
					field[i] += height * t
				"flat":
					field[i] = height
				"noise":
					var n := _noise(x / scale, y / scale, seed)
					field[i] += height * n * minf(edge / fall, 1.0)
				"heights":
					var k := (y - y0) * (w + 1) + (x - x0)
					if k < heights.size():
						field[i] = float(heights[k])


## Smooth value noise 0..1 from integer corners hashed with the seed (the
## same on every machine: no dice, no clock).
static func _noise(x: float, y: float, seed: int) -> float:
	var ix := floori(x)
	var iy := floori(y)
	var fx := x - ix
	var fy := y - iy
	var a := _lattice(ix, iy, seed)
	var bb := _lattice(ix + 1, iy, seed)
	var c := _lattice(ix, iy + 1, seed)
	var d := _lattice(ix + 1, iy + 1, seed)
	var ux := fx * fx * (3.0 - 2.0 * fx)
	var uy := fy * fy * (3.0 - 2.0 * fy)
	return lerpf(lerpf(a, bb, ux), lerpf(c, d, ux), uy)


static func _lattice(x: int, y: int, seed: int) -> float:
	var n := (x * 73856093) ^ (y * 19349663) ^ (seed * 83492791)
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0xFFFF) / 65535.0


# -------------------------------------------------------------------- road


## A road: its surface (and shoulders) painted along the points, a ditch
## carved beside it if asked; cells it runs over that are solid are noted.
static func _road(b, v: Dictionary, ctx: Dictionary) -> void:
	var points: Array = v["points"]
	var line: Array[Vector2] = []
	for p: Array in points:
		line.append(Vector2(float(p[0]), float(p[1])))
	var surface := str(v["surface"])
	var tile := str(V2.SURFACES.get(surface, "asphalt"))
	var half := float(v["width"]) * .5
	var shoulder := float(v["shoulder"])
	if shoulder < 0.0:
		shoulder = 1.0 if surface == "blacktop" else 0.0
	var reach := half + shoulder
	var blocked := 0
	var area := int(ctx["district_of"].call(v)) if str(v.get("district", "")) != "" else -1
	var field: PackedFloat32Array = ctx["field"]
	var ditch: bool = v["ditch"]
	var x_lo: int = b.w
	var y_lo: int = b.h
	var x_hi := 0
	var y_hi := 0
	for cy in range(1, b.h - 1):
		for cx in range(1, b.w - 1):
			var dist := _to_line(Vector2(cx + .5, cy + .5), line)
			if dist > reach + (1.0 if ditch else 0.0):
				continue
			var c: int = b.at(cx, cy)
			if dist > reach:
				# The ditch: the corners of this cell sunk.
				for k: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
					var i: int = (cy + k.y) * (b.w + 1) + cx + k.x
					if _to_line(Vector2(cx + k.x, cy + k.y), line) > reach + .2:
						field[i] = minf(field[i], -DITCH)
				x_lo = mini(x_lo, cx)
				y_lo = mini(y_lo, cy)
				x_hi = maxi(x_hi, cx + 1)
				y_hi = maxi(y_hi, cy + 1)
				continue
			if b.solid[c] >= 0:
				blocked += 1
				continue
			b.floor_tile[c] = b.t(tile if dist <= half else SHOULDER)
			if area >= 0:
				b.area[c] = area
	if ditch and x_hi > x_lo:
		ctx["patches"].append(
			{"id": str(v["id"]) + "_ditch", "rect": [x_lo, y_lo, x_hi, y_hi], "cliff": "", "light": -1.0}
		)
	if blocked > 0:
		ctx["issues"].append(
			_issue(
				"warning",
				"road_blocked",
				str(v["id"]),
				"road %s runs into %d solid cell(s) (a wall, hedge or building) and stops there" % [v["id"], blocked],
				"bend the road round it, or put a door or gap where it should pass"
			)
		)


static func _to_line(p: Vector2, line: Array[Vector2]) -> float:
	var best := INF
	for i in range(line.size() - 1):
		var q := Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])
		best = minf(best, p.distance_to(q))
	if line.size() == 1:
		best = p.distance_to(line[0])
	return best


# ------------------------------------------------------------------ finish


## What needs the whole map: district rects, terrain patches, logic, the
## versus plan, things lifted onto the terrain. `spawn` may get a z.
static func finish(b, doc: Dictionary, ctx: Dictionary, spawn: Array) -> void:
	for d in doc.get("districts", []):
		if d is Dictionary and d.get("rect") is Array:
			var r: Array = d["rect"]
			var index: int = ctx["districts"].get(str(d.get("id", "")), 0)
			for y in range(maxi(int(r[1]), 0), mini(int(r[3]), b.h)):
				for x in range(maxi(int(r[0]), 0), mini(int(r[2]), b.w)):
					b.area[b.at(x, y)] = index
	_patches(b, ctx)
	_logic(b, ctx)
	_versus(b, doc, ctx)
	Geo.lift_onto_terrain(b)
	var list: Array = b.geometry.get("terrain", [])
	if not list.is_empty():
		var t := LevelTerrain.from_json(list, b.w, b.h, b.tile, [])
		if t != null:
			var z := t.height_at(float(spawn[0]), float(spawn[1]))
			if not is_nan(z) and z > (float(spawn[3]) if spawn.size() > 3 else 0.0):
				if spawn.size() > 3:
					spawn[3] = snappedf(z, .001)
				else:
					spawn.append(snappedf(z, .001))
	var most := int(KitPiece.num("map_cost_most"))
	if int(ctx["cost"]) > most:
		ctx["issues"].append(
			_issue(
				"error",
				"cost",
				"",
				"too much building for one map: %d pieces from the kit, %d most" % [ctx["cost"], most],
				"fewer or smaller buildings (each piece's cost is in docs/map_notes/t5.md)"
			)
		)


static func _patches(b, ctx: Dictionary) -> void:
	var field: PackedFloat32Array = ctx["field"]
	var stride: int = b.w + 1
	for p: Dictionary in ctx["patches"]:
		var r: Array = p["rect"]
		var x0: int = r[0]
		var y0: int = r[1]
		var w: int = int(r[2]) - x0
		var h: int = int(r[3]) - y0
		var heights: Array = []
		for y in h + 1:
			for x in w + 1:
				heights.append(field[(y0 + y) * stride + x0 + x])
		var o := {}
		if str(p["cliff"]) != "":
			o["cliff"] = p["cliff"]
		if float(p["light"]) >= 0.0:
			o["light"] = p["light"]
		Geo.terrain(b, str(p["id"]), x0, y0, w, h, heights, o)


## The heights the source's terrain asked for, at a cell's corners (for
## validate: what stands on a hill).
static func field_at(ctx: Dictionary, b, x: int, y: int) -> float:
	var field: PackedFloat32Array = ctx["field"]
	return field[y * (b.w + 1) + x]


# ------------------------------------------------------------------- logic


## The doors by id (the source's own and the kit's): id -> the door.
static func _doors(b) -> Dictionary:
	var out := {}
	for d: Dictionary in b.doors:
		if str(d.get("id", "")) != "":
			out[str(d["id"])] = d
	return out


static func _door_list(b, ctx: Dictionary, o: Dictionary, key: String) -> Array:
	var doors := _doors(b)
	var out: Array = []
	var pieces := {}
	for r: Dictionary in ctx["kit_records"]:
		pieces[str(r["id"])] = true
	for name in o.get(key, []):
		if doors.has(str(name)):
			out.append(doors[str(name)])
		elif pieces.has(str(name)) and _hung(doors, str(name)).size() > 0:
			# A kit piece's id: every door hung in it (a barn's two big doors).
			out.append_array(_hung(doors, str(name)))
		else:
			var known := PackedStringArray(doors.keys())
			known.sort()
			ctx["issues"].append(
				_issue(
					"error",
					"logic_target",
					str(o["id"]),
					"%s %s names door %s, and there is no door with that id" % [o["type"], o["id"], name],
					"the doors here: %s" % ", ".join(known)
				)
			)
	return out


## The doors a kit piece hung (ids <piece id>_<side>_hung<n>), in id order.
static func _hung(doors: Dictionary, piece: String) -> Array:
	var names: Array = []
	for id: String in doors:
		if id.begins_with(piece + "_") and id.contains("_hung"):
			names.append(id)
	names.sort()
	var out: Array = []
	for id: String in names:
		out.append(doors[id])
	return out


static func _handle_off(b, d: Dictionary) -> void:
	var cell := [int(d["x"]), int(d["y"])]
	if not b.controlled_doors.has(cell):
		b.controlled_doors.append(cell)


static func _hands_in(b, r: Array) -> Array:
	var out: Array = []
	for e: Dictionary in b.enemies:
		var x := float(e["x"])
		var y := float(e["y"])
		if x >= float(r[0]) and x < float(r[2]) and y >= float(r[1]) and y < float(r[3]):
			out.append(str(e["id"]))
	return out


static func _logic(b, ctx: Dictionary) -> void:
	var stations := {}
	for o: Dictionary in ctx["logic"]:
		if o["type"] == "switch":
			stations[str(o["id"])] = o.get("requires", [])
	for o: Dictionary in ctx["logic"]:
		var id := str(o["id"])
		match str(o["type"]):
			"switch":
				var opens: Array = []
				for d: Dictionary in _door_list(b, ctx, o, "opens"):
					opens.append([int(d["x"]), int(d["y"])])
					_handle_off(b, d)
				if (o.get("opens", []) as Array).is_empty():
					ctx["issues"].append(
						_issue(
							"warning",
							"logic_target",
							id,
							"switch %s opens nothing (it is still an objective to throw)" % id,
							"name the doors it opens in opens, or use a station"
						)
					)
				for need in o.get("requires", []):
					if not stations.has(str(need)) and not _station_ids(b).has(str(need)):
						ctx["issues"].append(
							_issue("error", "logic_target", id, "%s requires %s: no such switch" % [id, need])
						)
				if _loops(stations, id, id, {}):
					ctx["issues"].append(
						_issue(
							"error",
							"logic_loop",
							id,
							"switch %s needs itself thrown first (requires goes round in a ring)" % id,
							"break the ring: one of them must need nothing"
						)
					)
				var at: Array = o["at"]
				b.station(
					id,
					float(at[0]),
					float(at[1]),
					str(o["label"]),
					str(o["message"]),
					{"requires": o["requires"], "opens": opens}
				)
				var z := float(o["z"])
				if z > 0.0:
					b.stations[b.stations.size() - 1]["z"] = z
				if str(o["prop"]) != "":
					b.quest(str(o["prop"]), float(at[0]), float(at[1]), id)
					var lift: float = z - float(b.ground[b.at(int(at[0]), int(at[1]))])
					if lift > 0.0:
						b.billboards[b.billboards.size() - 1]["z"] = lift
			"key":
				var name := "key_" + str(o["color"])
				var at: Array = o["at"]
				b.pickup(name, float(at[0]), float(at[1]), float(o["z"]))
				for d: Dictionary in _door_list(b, ctx, o, "doors"):
					d["key"] = name
			"kill_gate":
				var hands := _hands_in(b, o["rect"])
				if hands.is_empty():
					ctx["issues"].append(
						_issue(
							"error",
							"logic_target",
							id,
							"kill gate %s watches %s and no hand stands in it" % [id, str(o["rect"])],
							"put hands (enemy objects) inside its rect, or move the rect onto them"
						)
					)
					continue
				var act: Array = []
				for d: Dictionary in _door_list(b, ctx, o, "opens"):
					_handle_off(b, d)
					act.append({"open": [int(d["x"]), int(d["y"])]})
				if str(o["message"]) != "":
					act.append({"message": str(o["message"]), "for": 3.0})
				b.triggers.append({"id": id, "when": {"down": hands}, "once": true, "do": act})
			"wake_zone":
				var hands := _hands_in(b, o["rect"])
				if hands.is_empty():
					ctx["issues"].append(
						_issue("warning", "logic_target", id, "wake zone %s holds no hands" % id, "put hands inside its rect")
					)
					continue
				var area: Array = o["trigger"] if not (o["trigger"] as Array).is_empty() else o["rect"]
				var act: Array = [{"wake": hands}]
				if str(o["message"]) != "":
					act.append({"message": str(o["message"]), "for": 3.0})
				b.triggers.append({"id": id, "when": {"area": area}, "once": true, "do": act})
			"message":
				b.triggers.append(
					{
						"id": id,
						"when": {"area": o["rect"]},
						"once": bool(o["once"]),
						"do": [{"message": str(o["text"]), "for": float(o["seconds"])}]
					}
				)
			"trigger":
				var act: Array = []
				var doors := _doors(b)
				for a in o["do"]:
					var step: Dictionary = (a as Dictionary).duplicate(true) if a is Dictionary else {}
					for verb: String in ["open", "close", "lock"]:
						if step.get(verb) is String:
							var named := str(step[verb])
							if not doors.has(named):
								ctx["issues"].append(
									_issue("error", "logic_target", id, "%s: no door %s to %s" % [id, named, verb])
								)
					act.append(step)
				b.triggers.append({"id": id, "when": o["when"], "once": bool(o["once"]), "do": act})


static func _station_ids(b) -> Array:
	var out: Array = []
	for s: Dictionary in b.stations:
		out.append(str(s["id"]))
	return out


static func _loops(needs: Dictionary, start: String, at: String, seen: Dictionary) -> bool:
	for need in needs.get(at, []):
		var n := str(need)
		if n == start:
			return true
		if seen.has(n):
			continue
		seen[n] = true
		if _loops(needs, start, n, seen):
			return true
	return false


# ------------------------------------------------------------------ versus


## The deathmatch spawns and the 5v5 plan (LevelData.tactical), with the
## modes the source says it supports.
static func _versus(b, doc: Dictionary, ctx: Dictionary) -> void:
	var list: Array = ctx["versus"]
	if list.is_empty() and not doc.has("modes"):
		return
	var tac := {}
	if doc.get("modes") is Array:
		tac["modes"] = (doc["modes"] as Array).duplicate()
	var middle := Vector2(b.w * .5, b.h * .5)
	var teams := {}
	for o: Dictionary in list:
		if o["type"] == "team_spawn":
			teams[str(o["team"])] = Vector2(float(o["at"][0]), float(o["at"][1]))
	var dm: Array = []
	var sites := {}
	var routes := {}
	var holds := {}
	var hostages: Array = []
	for o: Dictionary in list:
		var at := Vector2.ZERO
		if o.get("at") is Array:
			at = Vector2(float(o["at"][0]), float(o["at"][1]))
		match str(o["type"]):
			"dm_spawn":
				var ang := float(o["angle"])
				var face := (middle - at).angle() if ang < 0.0 else deg_to_rad(ang)
				dm.append([at.x, at.y, snappedf(face, .0001)])
			"team_spawn":
				var team := str(o["team"])
				var other := "defend" if team == "attack" else "attack"
				var toward: Vector2 = teams.get(other, middle)
				var ang := float(o["angle"])
				var face := (toward - at).angle() if ang < 0.0 else deg_to_rad(ang)
				var key := "attack_spawns" if team == "attack" else "defend_spawns"
				var rows: Array = tac.get(key, [])
				rows.append_array(_spread(b, at, int(o["count"]), face))
				tac[key] = rows
			"bomb_site":
				sites[str(o["site"])] = _inclusive(o["rect"])
			"hostage":
				hostages.append([at.x, at.y])
			"rescue_zone":
				tac["rescue"] = _inclusive(o["rect"])
			"bot_route":
				var site := str(o["site"])
				var pts: Array = []
				for p: Array in o["points"]:
					pts.append([float(p[0]), float(p[1])])
				var have: Array = routes.get(site, [])
				have.append(pts)
				routes[site] = have
			"bot_hold":
				var site := str(o["site"])
				var have: Array = holds.get(site, [])
				have.append([at.x, at.y, snappedf(deg_to_rad(float(o["angle"])), .0001)])
				holds[site] = have
	if not dm.is_empty():
		tac["deathmatch"] = dm
	if tac.has("attack_spawns") or tac.has("defend_spawns") or not sites.is_empty():
		var attack: Vector2 = teams.get("attack", middle)
		var defend: Vector2 = teams.get("defend", middle)
		tac["sites"] = sites
		tac["hostages"] = hostages
		if not tac.has("rescue"):
			tac["rescue"] = [int(attack.x) - 3, int(attack.y) - 3, int(attack.x) + 3, int(attack.y) + 3]
		for site: String in sites:
			var box: Array = sites[site]
			var centre := Vector2((float(box[0]) + float(box[2]) + 1.0) * .5, (float(box[1]) + float(box[3]) + 1.0) * .5)
			if not routes.has(site):
				routes[site] = [[[centre.x, centre.y]]]
			if not holds.has(site):
				holds[site] = [[centre.x, centre.y, snappedf((attack - centre).angle(), .0001)]]
		if not holds.has("mid"):
			var m := (attack + defend) * .5
			holds["mid"] = [[snappedf(m.x, .01), snappedf(m.y, .01), snappedf((attack - defend).angle(), .0001)]]
		tac["routes"] = routes
		tac["holds"] = holds
	elif not hostages.is_empty():
		tac["hostages"] = hostages
	b.meta["tactical"] = tac


## `count` open places round `at` (the nearest first, TEAM_GAP apart), each
## [x, y, facing].
static func _spread(b, at: Vector2, count: int, face: float) -> Array:
	var cells: Array = []
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var c := Vector2i(int(floorf(at.x)) + dx, int(floorf(at.y)) + dy)
			if c.x < 1 or c.y < 1 or c.x >= b.w - 1 or c.y >= b.h - 1:
				continue
			if b.solid[b.at(c.x, c.y)] >= 0:
				continue
			cells.append(c)
	cells.sort_custom(
		func(p: Vector2i, q: Vector2i) -> bool:
			var dp := (Vector2(p) + Vector2(.5, .5)).distance_squared_to(at)
			var dq := (Vector2(q) + Vector2(.5, .5)).distance_squared_to(at)
			return dp < dq or (dp == dq and (p.y < q.y or (p.y == q.y and p.x < q.x)))
	)
	var out: Array = []
	for c: Vector2i in cells:
		var p := Vector2(c) + Vector2(.5, .5)
		var close := false
		for t: Array in out:
			if p.distance_to(Vector2(t[0], t[1])) < TEAM_GAP:
				close = true
		if close:
			continue
		out.append([p.x, p.y, snappedf(face, .0001)])
		if out.size() >= count:
			break
	return out


# ------------------------------------------------------------------- looks


## The looks over the finished level (MapLooks): the map's mood, the
## districts' moods, water, set pieces, vignettes, dressing, foliage. Its
## problems become validate warnings.
static func looks(level: Dictionary, doc: Dictionary, ctx: Dictionary) -> void:
	var asked: Dictionary = (ctx["looks"] as Dictionary).duplicate()
	var area_moods := {}
	for d in doc.get("districts", []):
		if d is Dictionary and str(d.get("mood", "")) != "":
			area_moods[str(ctx["districts"].get(str(d.get("id", "")), 0))] = str(d["mood"])
	if str(doc.get("mood", "")) != "":
		asked["mood"] = str(doc["mood"])
	if not area_moods.is_empty():
		asked["area_moods"] = area_moods
	var any := false
	for key: String in asked:
		if not (asked[key] is Array) or not (asked[key] as Array).is_empty():
			any = true
	if not any:
		return
	var report := MapLooks.apply(level, asked)
	for p: Array in report.get("problems", []):
		var line := str(p[1])
		var oid := line.get_slice(":", 0) if line.contains(":") else ""
		ctx["issues"].append(_issue("warning", str(p[0]), oid if not oid.contains(" ") else "", line))
