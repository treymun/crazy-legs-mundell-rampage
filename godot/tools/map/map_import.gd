## Original geometry from a glTF/GLB file into a map source, as the pieces
## the game is made of, never as a picture of them:
##
## - faces facing straight up become floors: a deck (a face under it within
##   2 units makes it that thick) or a block solid to the ground;
## - faces sloping up at most 45 degrees become ramps (their plane fitted);
## - faces facing straight down that no floor claims become ceilings;
## - upright faces become walls: grouped by plane, laid out along it, and
##   covered in rectangles, so a hole through a wall (a door, a window) comes
##   out as an opening of its size; two faces back to back within .6 make one
##   wall that thick;
## - anything else (a slanted wall, a slope over 45 degrees, a face leaning
##   down) cannot be drawn by the game: it is an error (skip_unsupported makes
##   it a warning and leaves it out), never flattened silently.
##
## Units and axes: glTF is metres, Y up, -Z forward. A map's x is the file's
## X, its y the file's Z (south), its z the file's Y; then `scale` (map units
## a metre: 1 keeps them; .6 makes a real-world model the game's size, a door
## 2.1 m becoming 1.26... see MAP_AUTHORING.md) and `origin` (x, y, z added).
## Materials: materials=<json> maps each material name to a tile; an unmapped
## one takes default_tile, or is an error. Objects come in named
## <prefix>_floor3, <prefix>_wall7, ... with "_import": "<prefix>": importing
## the same prefix again replaces exactly those and nothing else.
extends RefCounted

const Source := preload("res://tools/map/map_source.gd")
const Edit := preload("res://tools/map/map_edit.gd")

const FLAT := .985
const UPRIGHT := .02
const STEEPEST := .7071
const RES := .05


class Tri:
	var a: Vector3
	var b: Vector3
	var c: Vector3
	var n: Vector3
	var material := ""
	var mesh := ""


static func run(map_id: String, file: String, opts: Dictionary, assets: Assets) -> Dictionary:
	var summary: Array = []
	var errors: Array = []
	var doc := Source.read(map_id, errors)
	if doc.is_empty():
		return {"exit": 3, "error": errors[0]["message"] if not errors.is_empty() else "no source"}
	var path := (
		file
		if file.is_absolute_path() or file.begins_with("res://")
		else (
			ProjectSettings.globalize_path("res://").path_join("..").path_join(file).simplify_path()
		)
	)
	if not FileAccess.file_exists(path):
		path = file
	if not FileAccess.file_exists(path):
		return {"exit": 3, "error": "no file " + file}
	var scale := float(opts.get("scale", 1.0))
	var origin := Vector3.ZERO
	if opts.has("origin"):
		var o := String(opts["origin"]).split(",")
		origin = Vector3(float(o[0]), float(o[1]), float(o[2]) if o.size() > 2 else 0.0)
	var materials := {}
	if opts.has("materials"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(String(opts["materials"])))
		if not (parsed is Dictionary):
			return {"exit": 2, "error": "materials must be a JSON object {material: tile}"}
		materials = parsed
	var prefix := String(
		opts.get(
			"prefix", file.get_file().get_basename().to_lower().replace("-", "_").replace(" ", "_")
		)
	)
	if not RegEx.create_from_string(Source.ID_PATTERN).search(prefix):
		return {"exit": 2, "error": "prefix %s must match %s" % [prefix, Source.ID_PATTERN]}
	var tris := _read(path, scale, origin)
	if tris.is_empty():
		return {"exit": 3, "error": "no triangles read from " + path}
	summary.append("read %d triangles from %s" % [tris.size(), path.get_file()])
	# Materials to tiles.
	var unmapped := {}
	var default_tile := String(opts.get("default_tile", ""))
	for t: Tri in tris:
		var tile := String(materials.get(t.material, default_tile))
		if tile == "" or not assets.tile_index.has(tile):
			unmapped[t.material] = true
		t.material = tile
	if not unmapped.is_empty():
		return {
			"exit": 1,
			"error":
			(
				"materials with no tile: %s (materials=<json> maps them, default_tile=<tile> takes the rest)"
				% ", ".join(PackedStringArray(unmapped.keys()))
			),
			"summary": summary
		}
	var ups: Array = []
	var downs: Array = []
	var slopes: Array = []
	var walls: Array = []
	var odd: Array = []
	for t: Tri in tris:
		if t.n.z > FLAT:
			ups.append(t)
		elif t.n.z < -FLAT:
			downs.append(t)
		elif absf(t.n.z) < UPRIGHT:
			walls.append(t)
		elif t.n.z >= STEEPEST:
			slopes.append(t)
		else:
			odd.append(t)
	var issues: Array = []
	if not odd.is_empty():
		var meshes := {}
		for t: Tri in odd:
			meshes[t.mesh] = int(meshes.get(t.mesh, 0)) + 1
		var text := (
			"%d face(s) the game cannot draw (slanted walls, slopes over 45 degrees, faces leaning down): %s"
			% [odd.size(), meshes]
		)
		if not opts.has("skip_unsupported"):
			return {
				"exit": 1, "error": text + " (skip_unsupported leaves them out)", "summary": summary
			}
		issues.append(
			{"severity": "warning", "code": "unsupported", "message": text + ": left out"}
		)
	var objects: Array = []
	var used_downs := {}
	var n := 0
	for group: Array in _groups(
		ups, func(t: Tri): return snappedf((t.a.z + t.b.z + t.c.z) / 3.0, .01)
	):
		var z := snappedf((group[0] as Tri).a.z, .001)
		for piece: Dictionary in _footprints(group):
			var thick := -1.0
			for k in downs.size():
				var d: Tri = downs[k]
				var dz := d.a.z
				if dz < z - .005 and dz > z - 2.0 and _over(piece, d):
					thick = maxf(thick, -1.0) if thick > 0.0 else z - dz
					thick = minf(thick, z - dz)
					used_downs[k] = true
			n += 1
			var o := {
				"id": "%s_floor%d" % [prefix, n],
				"rect": piece["rect"],
				"top": z,
				"tile": (group[0] as Tri).material,
				"_import": prefix
			}
			if not (piece["cuts"] as Array).is_empty():
				o["cuts"] = piece["cuts"]
			if thick > 0.0:
				o["type"] = "deck"
				o["thick"] = snappedf(thick, .001)
			else:
				o["type"] = "block"
			objects.append(o)
	n = 0
	for group: Array in _groups(
		slopes,
		func(t: Tri):
			return (
				"%s|%s|%s"
				% [snappedf(t.n.x, .01), snappedf(t.n.y, .01), snappedf(t.n.dot(t.a), .01)]
			)
	):
		var t0: Tri = group[0]
		# z = d - (nx x + ny y) / nz on the plane n . p = d.
		var gx := -t0.n.x / t0.n.z
		var gy := -t0.n.y / t0.n.z
		for piece: Dictionary in _footprints(group):
			var r: Array = piece["rect"]
			var top := (t0.n.dot(t0.a) - t0.n.x * float(r[0]) - t0.n.y * float(r[1])) / t0.n.z
			n += 1
			var o := {
				"id": "%s_ramp%d" % [prefix, n],
				"type": "block",
				"rect": r,
				"top": snappedf(top, .001),
				"tile": t0.material,
				"_import": prefix,
				"_slope": [snappedf(gx, .0001), snappedf(gy, .0001)]
			}
			if not (piece["cuts"] as Array).is_empty():
				o["cuts"] = piece["cuts"]
			objects.append(o)
	n = 0
	var left: Array = []
	for k in downs.size():
		if not used_downs.has(k):
			left.append(downs[k])
	for group: Array in _groups(left, func(t: Tri): return snappedf(t.a.z, .01)):
		for piece: Dictionary in _footprints(group):
			n += 1
			var o := {
				"id": "%s_ceiling%d" % [prefix, n],
				"type": "ceiling",
				"rect": piece["rect"],
				"z": snappedf((group[0] as Tri).a.z, .001),
				"tile": (group[0] as Tri).material,
				"_import": prefix
			}
			if not (piece["cuts"] as Array).is_empty():
				o["cuts"] = piece["cuts"]
			objects.append(o)
	var wall_objects := _walls(walls, prefix)
	objects.append_array(wall_objects)
	# Ramps keep their slope as a sloped block: map them onto ramp's fields.
	for o: Dictionary in objects:
		if o.has("_slope"):
			o["_note"] = "imported slope gx %s gy %s" % o["_slope"]
			_as_ramp(o)
	var before := doc.duplicate(true)
	var kept: Array = []
	var removed := 0
	for o in doc.get("objects", []):
		if o is Dictionary and String(o.get("_import", "")) == prefix:
			removed += 1
			continue
		kept.append(o)
	kept.append_array(objects)
	doc["objects"] = kept
	var changes := Edit.diff(before, doc)
	summary.append(
		(
			"%d floor(s), %d ramp(s), %d ceiling(s), %d wall piece(s); %d old %s object(s) replaced"
			% [
				objects.filter(func(o): return String(o["id"]).contains("_floor")).size(),
				objects.filter(func(o): return String(o["id"]).contains("_ramp")).size(),
				objects.filter(func(o): return String(o["id"]).contains("_ceiling")).size(),
				wall_objects.size(),
				removed,
				prefix
			]
		)
	)
	for i: Dictionary in issues:
		summary.append("WARNING " + String(i["message"]))
	if opts.has("dry"):
		summary.append_array(Edit.describe(changes))
		summary.append("dry: nothing written")
		return {
			"exit": 0,
			"summary": summary,
			"changes": changes,
			"issues": issues,
			"objects": objects.size()
		}
	var backup := Edit.keep(
		map_id, "source", FileAccess.get_file_as_string(Source.path_of(map_id)), "import %s" % file
	)
	if not Source.write(map_id, doc):
		return {"exit": 3, "error": "could not write " + Source.path_of(map_id)}
	summary.append(
		(
			"wrote %s (the old one kept as %s); run validate, then build"
			% [Source.path_of(map_id), backup.get_file()]
		)
	)
	return {
		"exit": 0,
		"summary": summary,
		"changes": changes,
		"issues": issues,
		"objects": objects.size()
	}


## A sloped block as a ramp: rising toward its steepest way along x or y.
static func _as_ramp(o: Dictionary) -> void:
	var g: Array = o["_slope"]
	var r: Array = o["rect"]
	var gx := float(g[0])
	var gy := float(g[1])
	o.erase("_slope")
	o["type"] = "ramp"
	var top := float(o["top"])
	o.erase("top")
	if absf(gx) >= absf(gy):
		var run := float(r[2]) - float(r[0])
		o["toward"] = "e" if gx > 0.0 else "w"
		var west := top
		var east := top + gx * run
		o["from"] = snappedf(minf(west, east), .001)
		o["to"] = snappedf(maxf(west, east), .001)
	else:
		var run := float(r[3]) - float(r[1])
		o["toward"] = "s" if gy > 0.0 else "n"
		var north := top
		var south := top + gy * run
		o["from"] = snappedf(minf(north, south), .001)
		o["to"] = snappedf(maxf(north, south), .001)


static func _read(path: String, scale: float, origin: Vector3) -> Array:
	var gltf := GLTFDocument.new()
	var state := GLTFState.new()
	if gltf.append_from_file(path, state) != OK:
		return []
	var scene := gltf.generate_scene(state)
	var out: Array = []
	_walk(scene, Transform3D.IDENTITY, scale, origin, out)
	scene.free()
	return out


static func _walk(
	node: Node, parent: Transform3D, scale: float, origin: Vector3, out: Array
) -> void:
	var xf := parent
	if node is Node3D:
		xf = parent * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh := (node as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var index = arrays[Mesh.ARRAY_INDEX]
			var mat := mesh.surface_get_material(s)
			var mat_name := (
				""
				if mat == null
				else (mat.resource_name if mat.resource_name != "" else String(mat.get_name()))
			)
			var order := PackedInt32Array()
			if index == null or (index as PackedInt32Array).is_empty():
				for i in verts.size():
					order.append(i)
			else:
				order = index
			for i in range(0, order.size() - 2, 3):
				var t := Tri.new()
				t.a = _map(xf * verts[order[i]], scale, origin)
				t.b = _map(xf * verts[order[i + 1]], scale, origin)
				t.c = _map(xf * verts[order[i + 2]], scale, origin)
				var cross := (t.b - t.a).cross(t.c - t.a)
				if cross.length() < 1e-8:
					continue
				# Godot's triangles wind clockwise seen from the front; in the
				# map's axes (a mirror of Godot's) that makes this the outward normal.
				t.n = cross.normalized()
				t.material = mat_name
				t.mesh = node.name
				out.append(t)
	for child in node.get_children():
		_walk(child, xf, scale, origin, out)


static func _map(p: Vector3, scale: float, origin: Vector3) -> Vector3:
	return Vector3(p.x * scale + origin.x, p.z * scale + origin.y, p.y * scale + origin.z)


## Triangles in groups that share a key and touch (share a corner).
static func _groups(tris: Array, key: Callable) -> Array:
	var by_key := {}
	for t: Tri in tris:
		var k = key.call(t)
		if not by_key.has(k):
			by_key[k] = []
		by_key[k].append(t)
	var out: Array = []
	for k in by_key:
		var list: Array = by_key[k]
		var seen := {}
		for i in list.size():
			if seen.has(i):
				continue
			var group: Array = []
			var todo: Array = [i]
			seen[i] = true
			while not todo.is_empty():
				var j: int = todo.pop_back()
				group.append(list[j])
				var tj: Tri = list[j]
				for m in list.size():
					if seen.has(m):
						continue
					if _touch(tj, list[m]):
						seen[m] = true
						todo.append(m)
			out.append(group)
	return out


static func _touch(p: Tri, q: Tri) -> bool:
	for u in [p.a, p.b, p.c]:
		for v in [q.a, q.b, q.c]:
			if (u as Vector3).distance_to(v) < .002:
				return true
	return false


## A group's footprint from above as slab shapes: one rectangle with at most
## two cut lines when its outline is convex, else rectangles covering it.
static func _footprints(group: Array) -> Array:
	var points := PackedVector2Array()
	var area := 0.0
	for t: Tri in group:
		for v in [t.a, t.b, t.c]:
			points.append(Vector2((v as Vector3).x, (v as Vector3).y))
		area += (
			absf(
				(Vector2(t.b.x, t.b.y) - Vector2(t.a.x, t.a.y)).cross(
					Vector2(t.c.x, t.c.y) - Vector2(t.a.x, t.a.y)
				)
			)
			* .5
		)
	var hull := Geometry2D.convex_hull(points)
	var hull_area := 0.0
	for i in range(hull.size() - 1):
		hull_area += hull[i].cross(hull[i + 1])
	hull_area = absf(hull_area) * .5
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in points:
		lo = lo.min(p)
		hi = hi.max(p)
	if hull_area <= area * 1.02 + .001:
		var cuts: Array = []
		for i in range(hull.size() - 1):
			var a := hull[i]
			var b := hull[i + 1]
			var on_box := (
				(absf(a.x - b.x) < .001 and (absf(a.x - lo.x) < .001 or absf(a.x - hi.x) < .001))
				or (absf(a.y - b.y) < .001 and (absf(a.y - lo.y) < .001 or absf(a.y - hi.y) < .001))
			)
			if on_box:
				continue
			var d := (b - a).normalized()
			var nrm := Vector2(d.y, -d.x)
			var mid := (a + b) * .5
			if nrm.dot((lo + hi) * .5 - mid) > 0.0:
				nrm = -nrm
			cuts.append(
				[snappedf(nrm.x, .0001), snappedf(nrm.y, .0001), snappedf(nrm.dot(a), .0001)]
			)
		if cuts.size() <= 2:
			return [
				{
					"rect":
					[
						snappedf(lo.x, .001),
						snappedf(lo.y, .001),
						snappedf(hi.x, .001),
						snappedf(hi.y, .001)
					],
					"cuts": cuts
				}
			]
	# Not one cut rectangle: cover it with rectangles on a fine grid.
	var res := RES * 2.0
	var cols := int(ceil((hi.x - lo.x) / res))
	var rows := int(ceil((hi.y - lo.y) / res))
	var filled := PackedByteArray()
	filled.resize(cols * rows)
	for t: Tri in group:
		var tri := PackedVector2Array(
			[Vector2(t.a.x, t.a.y), Vector2(t.b.x, t.b.y), Vector2(t.c.x, t.c.y)]
		)
		for r in rows:
			for c in cols:
				if Geometry2D.is_point_in_polygon(
					lo + Vector2((c + .5) * res, (r + .5) * res), tri
				):
					filled[r * cols + c] = 1
	var out: Array = []
	for rect: Rect2i in _rects(filled, cols, rows):
		out.append(
			{
				"rect":
				[
					snappedf(lo.x + rect.position.x * res, .001),
					snappedf(lo.y + rect.position.y * res, .001),
					snappedf(lo.x + rect.end.x * res, .001),
					snappedf(lo.y + rect.end.y * res, .001)
				],
				"cuts": []
			}
		)
	return out


## Greedy rectangles covering the set cells of a grid.
static func _rects(filled: PackedByteArray, cols: int, rows: int) -> Array:
	var used := PackedByteArray()
	used.resize(cols * rows)
	var out: Array = []
	for r in rows:
		for c in cols:
			if filled[r * cols + c] == 0 or used[r * cols + c] != 0:
				continue
			var w := 1
			while c + w < cols and filled[r * cols + c + w] != 0 and used[r * cols + c + w] == 0:
				w += 1
			var h := 1
			var grow := true
			while grow and r + h < rows:
				for k in w:
					if filled[(r + h) * cols + c + k] == 0 or used[(r + h) * cols + c + k] != 0:
						grow = false
						break
				if grow:
					h += 1
			for rr in h:
				for k in w:
					used[(r + rr) * cols + c + k] = 1
			out.append(Rect2i(c, r, w, h))
	return out


static func _over(piece: Dictionary, d: Tri) -> bool:
	var r: Array = piece["rect"]
	var mid := (Vector2(d.a.x, d.a.y) + Vector2(d.b.x, d.b.y) + Vector2(d.c.x, d.c.y)) / 3.0
	return (
		mid.x > float(r[0]) and mid.x < float(r[2]) and mid.y > float(r[1]) and mid.y < float(r[3])
	)


## Upright faces as walls: by plane, back-to-back pairs made one thick wall,
## each plane's faces covered with rectangles along it (openings fall out).
static func _walls(tris: Array, prefix: String) -> Array:
	var planes := {}
	for t: Tri in tris:
		var n2 := Vector2(t.n.x, t.n.y).normalized()
		var key := (
			"%s|%s|%s"
			% [
				snappedf(n2.x, .01),
				snappedf(n2.y, .01),
				snappedf(n2.dot(Vector2(t.a.x, t.a.y)), .01)
			]
		)
		if not planes.has(key):
			planes[key] = {
				"n": n2, "d": n2.dot(Vector2(t.a.x, t.a.y)), "tris": [], "tile": t.material
			}
		planes[key]["tris"].append(t)
	var keys := planes.keys()
	var paired := {}
	var out: Array = []
	var n := 0
	for k in keys:
		if paired.has(k):
			continue
		var p: Dictionary = planes[k]
		var thick := .1
		var offset := -.05
		for k2 in keys:
			if k2 == k or paired.has(k2):
				continue
			var q: Dictionary = planes[k2]
			if (q["n"] as Vector2).dot(p["n"]) < -.999:
				# Back to back: n . x = d and -n . x = d2, so the gap is -(d + d2).
				var gap := -(float(p["d"]) + float(q["d"]))
				if gap > .02 and gap < .6:
					thick = gap
					offset = -gap * .5
					paired[k2] = true
					break
		paired[k] = true
		var nrm: Vector2 = p["n"]
		var along := Vector2(-nrm.y, nrm.x)
		var base := nrm * float(p["d"])
		var u0 := INF
		var u1 := -INF
		var z0 := INF
		var z1 := -INF
		for t: Tri in p["tris"]:
			for v in [t.a, t.b, t.c]:
				var u := along.dot(Vector2((v as Vector3).x, (v as Vector3).y))
				u0 = minf(u0, u)
				u1 = maxf(u1, u)
				z0 = minf(z0, (v as Vector3).z)
				z1 = maxf(z1, (v as Vector3).z)
		var cols := maxi(1, int(ceil((u1 - u0) / RES)))
		var rows := maxi(1, int(ceil((z1 - z0) / RES)))
		var filled := PackedByteArray()
		filled.resize(cols * rows)
		for t: Tri in p["tris"]:
			var tri := PackedVector2Array()
			for v in [t.a, t.b, t.c]:
				tri.append(
					Vector2(
						along.dot(Vector2((v as Vector3).x, (v as Vector3).y)), (v as Vector3).z
					)
				)
			for r in rows:
				for c in cols:
					if Geometry2D.is_point_in_polygon(
						Vector2(u0 + (c + .5) * RES, z0 + (r + .5) * RES), tri
					):
						filled[r * cols + c] = 1
		for rect: Rect2i in _rects(filled, cols, rows):
			var ua := u0 + rect.position.x * RES
			var ub := u0 + rect.end.x * RES
			var a := base + along * ua + nrm * offset
			var b := base + along * ub + nrm * offset
			n += 1
			(
				out
				. append(
					{
						"id": "%s_wall%d" % [prefix, n],
						"type": "wall",
						"a": [snappedf(a.x, .001), snappedf(a.y, .001)],
						"b": [snappedf(b.x, .001), snappedf(b.y, .001)],
						"z0": snappedf(z0 + rect.position.y * RES, .001),
						"z1": snappedf(z0 + rect.end.y * RES, .001),
						"thick": snappedf(thick, .001),
						"tile": p["tile"],
						"_import": prefix,
					}
				)
			)
	return out
