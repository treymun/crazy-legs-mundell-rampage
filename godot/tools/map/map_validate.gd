## A built map checked the way the game will play it: the level loaded as
## LevelData, its geometry and nav graph asked. Each problem is
## {severity: error|warning, code, object, at: [x, y, z], message, hint}.
## Errors stop a build; warnings do not. An allow_overlap object lets the
## overlaps it names through (as notes).
##
## Codes: geometry (a piece the game would refuse), overlap (two solids in
## each other), inside (a spawn, hand, pickup or objective in something
## solid), blocked_doorway, low_opening, headroom (crouch only), stairs_top /
## stairs_foot (stairs or a ramp leading nowhere), unreachable (from the
## spawn, every door opened), floor_unreachable (a deck no stairs reach),
## spawn_seen (a hand sees the spawn), builder (the plan builder's own checks).
extends RefCounted

const Source := preload("res://tools/map/map_source.gd")


static func issue(
	severity: String, code: String, object_id: String, at, message: String, hint := ""
) -> Dictionary:
	var d := {"severity": severity, "code": code, "object": object_id, "message": message}
	if at != null:
		var p: Array = []
		for v in at:
			p.append(snappedf(float(v), .01))
		d["at"] = p
	if hint != "":
		d["hint"] = hint
	return d


## Every problem with a compiled map (map_compile.compile()'s result).
static func check(doc: Dictionary, built: Dictionary, assets: Assets) -> Array:
	var out: Array = []
	var level: Dictionary = built["level"]
	if level.is_empty():
		return out
	# Which object each piece came from, and the overlaps allowed.
	var owner := {}
	var made: Dictionary = built.get("objects", {})
	for oid in made:
		for piece in made[oid]:
			owner[String(piece)] = String(oid)
	var allowed := {}
	for o in doc.get("objects", []):
		if o is Dictionary and String(o.get("type", "")) == "allow_overlap":
			var names: Array = o.get("objects", [])
			for a in names:
				for c in names:
					allowed["%s|%s" % [a, c]] = String(o["id"])
	var errors: Array = []
	var geo := LevelGeometry.from_json(
		level.get("geometry"), int(level["width"]), int(level["height"]), assets.tile_index, errors
	)
	for e: String in errors:
		var oid := e.get_slice(":", 0)
		out.append(issue("error", "geometry", String(owner.get(oid, oid)), null, e))
	var lv := LevelData.from_dict(level, assets)
	if lv == null:
		out.append(issue("error", "load", "", null, "the game would not load this level"))
		return out
	for p: String in built.get("problems", []):
		out.append(issue("error", "builder", _object_in(p, doc), null, p))
	if geo != null:
		_overlaps(out, geo, owner, allowed)
	_things(out, doc, built, lv, owner)
	if lv.geo != null:
		_doorways(out, doc, lv)
		_reach(out, doc, built, lv, owner)
	return out


## A builder problem names an enemy or station by its id: the object.
static func _object_in(text: String, doc: Dictionary) -> String:
	for o in doc.get("objects", []):
		if o is Dictionary and text.contains(" " + String(o.get("id", "")) + " "):
			return String(o["id"])
	return ""


static func _pair_allowed(allowed: Dictionary, a: String, b: String) -> bool:
	return allowed.has("%s|%s" % [a, b])


static func _overlaps(out: Array, g: LevelGeometry, owner: Dictionary, allowed: Dictionary) -> void:
	var slabs := g.slabs
	for i in slabs.size():
		var s: LevelGeometry.Slab = slabs[i]
		for j in range(i + 1, slabs.size()):
			var t: LevelGeometry.Slab = slabs[j]
			var oa := String(owner.get(s.id, s.id))
			var ob := String(owner.get(t.id, t.id))
			if oa == ob:
				continue
			var x0 := maxf(s.x0, t.x0)
			var x1 := minf(s.x1, t.x1)
			var y0 := maxf(s.y0, t.y0)
			var y1 := minf(s.y1, t.y1)
			if x1 - x0 < .02 or y1 - y0 < .02:
				continue
			var mid := Vector2((x0 + x1) * .5, (y0 + y1) * .5)
			if not s.inside(mid.x, mid.y) or not t.inside(mid.x, mid.y):
				continue
			var z0 := maxf(s.bottom_at(mid.x, mid.y), t.bottom_at(mid.x, mid.y))
			var z1 := minf(s.top_at(mid.x, mid.y), t.top_at(mid.x, mid.y))
			if z1 - z0 < .02:
				continue
			if _pair_allowed(allowed, oa, ob):
				continue
			(
				out
				. append(
					issue(
						"error",
						"overlap",
						oa,
						[mid.x, mid.y, (z0 + z1) * .5],
						(
							"%s and %s are in each other (x %.2f..%.2f, y %.2f..%.2f, z %.2f..%.2f)"
							% [oa, ob, x0, x1, y0, y1, z0, z1]
						),
						(
							'move one, or add {"type": "allow_overlap", "objects": ["%s", "%s"], "reason": ...}'
							% [oa, ob]
						)
					)
				)
			)
	for seg in g.segments:
		var oa := String(owner.get(seg.id, seg.id))
		for s in slabs:
			var ob := String(owner.get(s.id, s.id))
			if oa == ob or _pair_allowed(allowed, oa, ob):
				continue
			# The wall's middle line inside the slab, past its own half thickness.
			for k in 9:
				var f := (k + .5) / 9.0
				var p := Vector2(lerpf(seg.ax, seg.bx, f), lerpf(seg.ay, seg.by, f))
				if not _deep_inside(s, p, seg.half + .03):
					continue
				var z0 := maxf(seg.z0, s.bottom_at(p.x, p.y))
				var z1 := minf(seg.z1, s.top_at(p.x, p.y))
				if z1 - z0 > .03:
					(
						out
						. append(
							issue(
								"error",
								"overlap",
								oa,
								[p.x, p.y, (z0 + z1) * .5],
								"wall %s runs through %s (z %.2f..%.2f)" % [seg.id, ob, z0, z1],
								"stand the wall on the deck (z0 at its top) or end it at the deck's edge"
							)
						)
					)
					break


static func _deep_inside(s: LevelGeometry.Slab, p: Vector2, margin: float) -> bool:
	if p.x < s.x0 + margin or p.x > s.x1 - margin or p.y < s.y0 + margin or p.y > s.y1 - margin:
		return false
	for k in range(0, s.cuts.size(), 3):
		if s.cuts[k] * p.x + s.cuts[k + 1] * p.y > s.cuts[k + 2] - margin:
			return false
	return true


## Spawns, hands, pickups and objectives: each where a body can stand.
static func _things(
	out: Array, doc: Dictionary, built: Dictionary, lv: LevelData, owner: Dictionary
) -> void:
	var spots: Array = []
	var spawn: Array = built["spawn"]
	spots.append(
		[
			"spawn",
			Vector2(spawn[0], spawn[1]),
			float(spawn[3]) if spawn.size() > 3 else 0.0,
			"spawn"
		]
	)
	for o in doc.get("objects", []):
		if not (o is Dictionary):
			continue
		var type := String(o.get("type", ""))
		if type in ["enemy", "pickup", "station", "exit", "spawn_point"] and o.has("at"):
			var at: Array = o["at"]
			spots.append(
				[String(o["id"]), Vector2(float(at[0]), float(at[1])), float(o.get("z", 0.0)), type]
			)
	for s: Array in spots:
		var at: Vector2 = s[1]
		if at.x < 0 or at.y < 0 or at.x >= lv.width or at.y >= lv.height:
			out.append(
				issue(
					"error",
					"outside",
					s[0],
					[at.x, at.y, s[2]],
					"%s %s is off the map" % [s[3], s[0]]
				)
			)
			continue
		var c := lv.cell(at.x, at.y)
		var feet := lv.floor_under(at.x, at.y, float(s[2]) + .05)
		if lv.solid[c] >= 0 and not lv.door_cells.has(c):
			out.append(
				issue(
					"error",
					"inside",
					s[0],
					[at.x, at.y, feet],
					"%s %s stands in a solid cell (%d, %d)" % [s[3], s[0], int(at.x), int(at.y)],
					"move it onto open floor"
				)
			)
			continue
		if lv.geo == null:
			continue
		var r := .18 if s[3] != "station" else .05
		if lv.geo.blocks(at.x, at.y, r, feet + LevelGeometry.STEP, feet + LevelGeometry.BODY):
			var what := _what_blocks(lv.geo, at, r, feet, owner)
			out.append(
				issue(
					"error",
					"inside",
					s[0],
					[at.x, at.y, feet],
					"%s %s stands in %s" % [s[3], s[0], what],
					"move it, or give it the z of the floor it is on"
				)
			)
		elif s[3] in ["spawn", "spawn_point", "enemy"]:
			var over := minf(
				lv.geo.ceiling_at(at.x, at.y, feet), lv.roof[c] if lv.roof[c] > feet + .01 else INF
			)
			if over - feet < LevelGeometry.BODY:
				out.append(
					issue(
						"warning",
						"headroom",
						s[0],
						[at.x, at.y, feet],
						(
							"%s %s has %.2f of headroom (a body stands 1.12)"
							% [s[3], s[0], over - feet]
						)
					)
				)


static func _what_blocks(
	g: LevelGeometry, at: Vector2, r: float, feet: float, owner: Dictionary
) -> String:
	for item in g.near_items(at.x, at.y):
		var id: String = item.id
		if item is LevelGeometry.Slab:
			var s: LevelGeometry.Slab = item
			if (
				s.near(at.x, at.y, r)
				and s.top_at(at.x, at.y) > feet + LevelGeometry.STEP
				and s.bottom_at(at.x, at.y) < feet + LevelGeometry.BODY
			):
				return String(owner.get(id, id))
		else:
			var w: LevelGeometry.Segment = item
			if (
				w.z0 < feet + LevelGeometry.BODY
				and w.z1 > feet + LevelGeometry.STEP
				and w.dist2(at.x, at.y) < (r + w.half) * (r + w.half)
			):
				return String(owner.get(id, id))
	return "geometry"


## Grid doors with something standing in them; openings too low to walk.
static func _doorways(out: Array, doc: Dictionary, lv: LevelData) -> void:
	for door: LevelData.Door in lv.doors:
		var x := door.x + .5
		var y := door.y + .5
		if lv.geo.blocks(
			x,
			y,
			.2,
			lv.ground[door.y * lv.width + door.x] + LevelGeometry.STEP,
			lv.ground[door.y * lv.width + door.x] + LevelGeometry.BODY
		):
			out.append(
				issue(
					"error",
					"blocked_doorway",
					door.id,
					[x, y, 0.0],
					(
						"door %s at (%d, %d) has a deck, wall or block standing in it"
						% [door.id, door.x, door.y]
					),
					"move what stands in it, or the door"
				)
			)
	for o in doc.get("objects", []):
		if not (o is Dictionary) or String(o.get("type", "")) != "wall":
			continue
		for hole: Dictionary in o.get("openings", []):
			var sill := float(hole.get("sill", 0.0))
			var head := float(hole.get("head", 1.85 if sill <= 0.0 else sill + 1.0))
			var width := float(hole.get("width", 1.0))
			var a: Array = o["a"]
			var b: Array = o["b"]
			var dir := Vector2(float(b[0]) - float(a[0]), float(b[1]) - float(a[1])).normalized()
			var mid := Vector2(float(a[0]), float(a[1])) + dir * float(hole["at"])
			var name := String(hole.get("id", "%s opening at %s" % [o["id"], hole["at"]]))
			if sill <= float(o.get("z0", 0.0)) + .01:
				if head - sill < LevelGeometry.BODY + .05:
					out.append(
						issue(
							"error",
							"low_opening",
							String(o["id"]),
							[mid.x, mid.y, sill],
							"doorway %s is %.2f high: a body needs 1.17" % [name, head - sill]
						)
					)
				if not _on_grid(mid, dir, width, float(o.get("thick", .12)) * .5):
					(
						out
						. append(
							issue(
								"warning",
								"off_grid_opening",
								String(o["id"]),
								[mid.x, mid.y, sill],
								(
									"doorway %s misses every cell's middle line: " % name
									+ "bots and the pin path middle to middle and will not use it"
								),
								"move `at` so a cell middle (x.5 or y.5) is inside it, .26 from each side"
							)
						)
					)
				if width < .5:
					out.append(
						issue(
							"error",
							"low_opening",
							String(o["id"]),
							[mid.x, mid.y, sill],
							"doorway %s is %.2f wide: a body needs .5" % [name, width]
						)
					)


## Whether a doorway at `mid` along `dir`, `width` wide, has a cell's middle
## line through it with room for a body (.2) and the wall's half thickness.
static func _on_grid(mid: Vector2, dir: Vector2, width: float, half: float) -> bool:
	var along := mid.y if absf(dir.y) > absf(dir.x) else mid.x
	if absf(dir.x) > .01 and absf(dir.y) > .01:
		return true
	var room := .2 + half - .06
	var lo := along - width * .5 + room
	var hi := along + width * .5 - room
	return floorf(hi - .5) >= ceilf(lo - .5) and hi >= lo


## Reachability over the nav graph from the spawn, every door counted open.
static func _reach(
	out: Array, doc: Dictionary, built: Dictionary, lv: LevelData, owner: Dictionary
) -> void:
	var field := FlowField.new(lv)
	field.reach = 1 << 20
	field.doors_open = true
	field.every_door = true
	var spawn: Array = built["spawn"]
	var sz := float(spawn[3]) if spawn.size() > 3 else 0.0
	field.update(spawn[0], spawn[1], 0.0, lv.floor_under(spawn[0], spawn[1], sz + .05))
	var g := field.graph
	for o in doc.get("objects", []):
		if not (o is Dictionary) or not o.has("at"):
			continue
		var type := String(o.get("type", ""))
		if not (type in ["enemy", "pickup", "station", "exit", "spawn_point"]):
			continue
		var at: Array = o["at"]
		var feet := lv.floor_under(float(at[0]), float(at[1]), float(o.get("z", 0.0)) + .05)
		var d := field.distance(float(at[0]), float(at[1]), feet)
		if d >= FlowField.FAR:
			# A station or pickup is used from beside it: any neighbour reached will do.
			var near := false
			for n: Vector2i in FlowField.NEIGHBOURS:
				if field.distance(float(at[0]) + n.x, float(at[1]) + n.y, feet) < FlowField.FAR:
					near = true
			if near and type != "spawn_point":
				continue
			var sev := "warning" if type == "enemy" else "error"
			out.append(
				issue(
					sev,
					"unreachable",
					String(o["id"]),
					[float(at[0]), float(at[1]), feet],
					(
						"%s %s cannot be walked to from the spawn (every door opened)"
						% [type, o["id"]]
					),
					"a ramp or stairs to its floor, or move it"
				)
			)
	# Decks nothing reaches, and stairs or ramps whose ends lead nowhere.
	var deck_nodes := {}
	for n in range(g.cells, g.count):
		var c := g.cell[n]
		for item in lv.geo.near_items(c % lv.width + .5, c / lv.width + .5):
			if (
				item is LevelGeometry.Slab
				and (item as LevelGeometry.Slab).inside(c % lv.width + .5, c / lv.width + .5)
				and (
					absf(
						(
							(item as LevelGeometry.Slab).top_at(
								c % lv.width + .5, c / lv.width + .5
							)
							- g.z[n]
						)
					)
					< .05
				)
			):
				var oid := String(owner.get(item.id, item.id))
				if not deck_nodes.has(oid):
					deck_nodes[oid] = []
				deck_nodes[oid].append(n)
	for oid in deck_nodes:
		var reached := false
		var standing := false
		for n: int in deck_nodes[oid]:
			if field.open[n] != 0:
				standing = true
			if field.steps[n] < FlowField.FAR:
				reached = true
				break
		if standing and not reached:
			var n0: int = deck_nodes[oid][0]
			(
				out
				. append(
					issue(
						"error",
						"floor_unreachable",
						oid,
						[g.cell[n0] % lv.width + .5, g.cell[n0] / lv.width + .5, g.z[n0]],
						(
							"nothing leads up to %s (z %.2f): no stairs or ramp joins it to the spawn's floor"
							% [oid, g.z[n0]]
						),
						"add stairs or a ramp, or mark it walk:false if nobody should stand there"
					)
				)
			)
	for o in doc.get("objects", []):
		if not (o is Dictionary) or not (String(o.get("type", "")) in ["stairs", "ramp"]):
			continue
		var r: Array = o["rect"]
		var toward := String(o["toward"])
		var foot := _beyond(r, toward, false)
		var top := _beyond(r, toward, true)
		var low := lv.floor_under(foot.x, foot.y, float(o["from"]) + .05)
		var high := lv.floor_under(top.x, top.y, float(o["to"]) + .05)
		if field.distance(foot.x, foot.y, low) >= FlowField.FAR:
			out.append(
				issue(
					"error",
					"stairs_foot",
					String(o["id"]),
					[foot.x, foot.y, low],
					"%s %s: the ground at its foot is not reached" % [o["type"], o["id"]],
					"clear its foot, or check its `from` and `toward`"
				)
			)
		if absf(high - float(o["to"])) > .06 or field.distance(top.x, top.y, high) >= FlowField.FAR:
			(
				out
				. append(
					issue(
						"error",
						"stairs_top",
						String(o["id"]),
						[top.x, top.y, float(o["to"])],
						(
							"%s %s leads nowhere at its top (z %.2f): no floor there at that height that is walked to"
							% [o["type"], o["id"], float(o["to"])]
						),
						"end it against a deck whose top is its `to`"
					)
				)
			)
	# A hand that sees the spawn from close by.
	for o in doc.get("objects", []):
		if o is Dictionary and String(o.get("type", "")) == "enemy":
			var at: Array = o["at"]
			var e := Vector2(float(at[0]), float(at[1]))
			var s := Vector2(spawn[0], spawn[1])
			if (
				e.distance_to(s) < 8.0
				and lv.visible(s.x, s.y, e.x, e.y, sz + .95, float(o.get("z", 0.0)) + .9)
			):
				out.append(
					issue(
						"warning",
						"spawn_seen",
						String(o["id"]),
						[e.x, e.y, float(o.get("z", 0.0))],
						"enemy %s sees the spawn from %.1f away" % [o["id"], e.distance_to(s)]
					)
				)


## The middle of the cell just past a ramp's or stairs' low end (top false) or high end.
static func _beyond(r: Array, toward: String, top: bool) -> Vector2:
	var cx := (float(r[0]) + float(r[2])) * .5
	var cy := (float(r[1]) + float(r[3])) * .5
	var step := .5
	match toward:
		"e":
			return Vector2(float(r[2]) + step if top else float(r[0]) - step, cy)
		"w":
			return Vector2(float(r[0]) - step if top else float(r[2]) + step, cy)
		"s":
			return Vector2(cx, float(r[3]) + step if top else float(r[1]) - step)
	return Vector2(cx, float(r[1]) - step if top else float(r[3]) + step)
