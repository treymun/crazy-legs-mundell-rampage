## Turns a map source (map_source.gd) into a level (data/<id>.json's
## contents) through the level builder: a base plan first when the source
## names one, then each object in order (later ones over earlier ones where
## they change the same cells), then the signs mounted, then the builder's own
## checks. Nothing here writes a file: map_cli.gd does, after validate.
extends RefCounted

const Builder := preload("res://tools/levels/level_builder.gd")
const Geo := preload("res://tools/levels/geo_kit.gd")
const Source := preload("res://tools/map/map_source.gd")


## {level, builder, spawn, problems (the builder's), issues (objects it could
## not make), objects (id -> what it made: slab, segment and other ids)}.
## level is empty when the source could not be built.
static func compile(doc: Dictionary) -> Dictionary:
	var issues: Array = []
	var made := {}
	var b
	var spawn: Array
	var districts := {}
	var base = doc.get("base")
	if base is Dictionary:
		var plan_id := String(base.get("plan", ""))
		var path := "res://tools/levels/%s_plan.gd" % plan_id
		if not ResourceLoader.exists(path):
			issues.append(_issue("no_plan", "", "no plan %s for base" % path))
			return {"level": {}, "issues": issues, "objects": made}
		var plan = load(path).new()
		b = plan.make()
		spawn = plan.build(b)
		for i in b.districts.size():
			districts[String(b.districts[i]).to_lower().replace(" ", "_")] = i
	else:
		var size: Array = doc["size"]
		b = Builder.new(
			String(doc["id"]), int(size[0]), int(size[1]), String(doc.get("border", "hedgerow"))
		)
		for d: Dictionary in doc.get("districts", []):
			var tint: Array = d.get("tint", [1, 1, 1])
			districts[String(d["id"])] = b.district(
				String(d.get("name", String(d["id"]).to_upper())),
				Color(float(tint[0]), float(tint[1]), float(tint[2]))
			)
		var s: Dictionary = doc.get("spawn", {})
		var at: Array = s.get("at", [1.5, 1.5])
		spawn = [float(at[0]), float(at[1]), deg_to_rad(float(s.get("angle", 0.0)))]
		if float(s.get("z", 0.0)) > 0.0:
			spawn.append(float(s["z"]))
	for key in doc.get("meta", {}):
		b.meta[key] = doc["meta"][key]
	if base is Dictionary and doc.has("spawn"):
		var s: Dictionary = doc["spawn"]
		var at: Array = s["at"]
		spawn = [float(at[0]), float(at[1]), deg_to_rad(float(s.get("angle", 0.0)))]
		if float(s.get("z", 0.0)) > 0.0:
			spawn.append(float(s["z"]))
	var ctx := {"districts": districts, "made": made, "issues": issues}
	for o in doc.get("objects", []):
		if o is Dictionary and Source.TYPES.has(String(o.get("type", ""))):
			_apply(b, o, ctx)
	b.mount_signs()
	var problems: Array = b.problems(spawn)
	var level: Dictionary = b.finish(spawn)
	level["source"] = "maps/%s.map.json" % doc.get("id", "")
	return {
		"level": level,
		"builder": b,
		"spawn": spawn,
		"problems": problems,
		"issues": issues,
		"objects": made
	}


static func _issue(code: String, object_id: String, message: String) -> Dictionary:
	return {"severity": "error", "code": code, "object": object_id, "message": message}


## Cells x0..x1-1, y0..y1-1 of a whole-number rect, inclusive as the builder takes them.
static func _cells(r: Array) -> Array:
	return [int(r[0]), int(r[1]), int(r[2]) - 1, int(r[3]) - 1]


static func _v(p: Array) -> Vector2:
	return Vector2(float(p[0]), float(p[1]))


static func _district(o: Dictionary, ctx: Dictionary) -> int:
	var name := String(o.get("district", ""))
	if name != "" and not ctx["districts"].has(name):
		ctx["issues"].append(
			_issue(
				"no_district",
				String(o.get("id", "")),
				(
					"no district %s (here: %s)"
					% [name, ", ".join(PackedStringArray(ctx["districts"].keys()))]
				)
			)
		)
	return int(ctx["districts"].get(name, 0))


## The keys a geometry piece takes from an object (tiles, light, district).
static func _geo_opts(o: Dictionary, ctx: Dictionary, keys: Array) -> Dictionary:
	var out := {"area": _district(o, ctx)}
	for key: String in keys:
		if o.has(key) and not (o[key] is String and String(o[key]) == ""):
			out[key] = o[key]
	return out


static func _apply(b, o: Dictionary, ctx: Dictionary) -> void:
	var id := String(o["id"])
	var type := String(o["type"])
	var spec: Dictionary = Source.TYPES[type]
	# Defaults first, then what the object says.
	var v: Dictionary = (spec["opt"] as Dictionary).duplicate(true)
	v.merge(o, true)
	var made: Array = []
	match type:
		"yard":
			var c := _cells(v["rect"])
			b.yard(
				c[0],
				c[1],
				c[2],
				c[3],
				String(v["floor"]),
				_district(v, ctx),
				{"ground": v["ground"], "light": v["light"]}
			)
		"room":
			var c := _cells(v["rect"])
			var opts := {
				"roof": v["roof"],
				"ground": v["ground"],
				"light": v["light"],
				"ceiling": v["ceiling"]
			}
			if String(v["skin"]) != "":
				opts["skin"] = v["skin"]
			b.room(c[0], c[1], c[2], c[3], String(v["floor"]), _district(v, ctx), opts)
		"building":
			var c := _cells(v["rect"])
			b.building(
				c[0],
				c[1],
				c[2],
				c[3],
				_district(v, ctx),
				{
					"roof": v["roof"],
					"wall": v["wall"],
					"windows": v["windows"],
					"floor": v["floor"],
					"ceiling": v["ceiling"],
					"light": v["light"],
					"parapet": v["parapet"]
				}
			)
		"solid":
			var c := _cells(v["rect"])
			b.wall(c[0], c[1], c[2], c[3], String(v["tile"]), float(v["top"]), bool(v["band"]))
		"fence":
			var c := _cells(v["rect"])
			b.fence(c[0], c[1], c[2], c[3], float(v["top"]), String(v["tile"]))
		"paint":
			var c := _cells(v["rect"])
			b.paint(c[0], c[1], c[2], c[3], String(v["floor"]))
		"raise":
			var c := _cells(v["rect"])
			b.raise(c[0], c[1], c[2], c[3], float(v["ground"]))
		"light":
			var at := _v(v["at"])
			b.glow(at.x, at.y, float(v["reach"]), float(v["amount"]))
		"door":
			var cell: Array = v["cell"]
			var opts := {
				"key": v["key"],
				"style": v["style"],
				"secret": v["secret"],
				"tile": v["tile"],
				"opened": v["opened"],
				"id": id
			}
			if String(v["from"]) != "":
				opts["from"] = v["from"]
			b.door(int(cell[0]), int(cell[1]), bool(v["vertical"]), opts)
		"gap":
			var cell: Array = v["cell"]
			b.gap(int(cell[0]), int(cell[1]), String(v["from"]))
		"pane":
			var cell: Array = v["cell"]
			b.window_pane(int(cell[0]), int(cell[1]))
		"deck":
			var opts := _geo_opts(v, ctx, ["thick", "tile", "under", "edge", "cuts", "light"])
			made.append(Geo.deck(b, id, v["rect"], float(v["top"]), opts)["id"])
		"block":
			var opts := _geo_opts(v, ctx, ["tile", "edge", "cuts", "light", "walk"])
			opts["thick"] = -1.0
			opts["kind"] = "block"
			made.append(Geo.slab(b, id, v["rect"], float(v["top"]), opts)["id"])
		"ramp":
			var opts := _geo_opts(v, ctx, ["tile", "edge", "thick", "under", "light"])
			made.append(
				(
					Geo
					. ramp(
						b,
						id,
						v["rect"],
						float(v["from"]),
						float(v["to"]),
						String(v["toward"]),
						opts
					)["id"]
				)
			)
		"stairs":
			var opts := _geo_opts(v, ctx, ["tile", "edge", "rise", "thick", "light"])
			for s: Dictionary in Geo.stairs(
				b, id, v["rect"], float(v["from"]), float(v["to"]), String(v["toward"]), opts
			):
				made.append(s["id"])
		"wall":
			var opts := _geo_opts(v, ctx, ["thick", "tile", "openings", "light"])
			for s: Dictionary in Geo.wall(
				b, id, _v(v["a"]), _v(v["b"]), float(v["z0"]), float(v["z1"]), opts
			):
				made.append(s["id"])
		"rail":
			var opts := _geo_opts(v, ctx, ["height", "tile"])
			made.append(Geo.rail(b, id, _v(v["a"]), _v(v["b"]), float(v["z"]), opts)["id"])
		"cover":
			var opts := _geo_opts(v, ctx, ["height", "thick", "tile"])
			made.append(Geo.cover(b, id, _v(v["a"]), _v(v["b"]), float(v["z"]), opts)["id"])
		"balcony", "bridge":
			var opts := _geo_opts(v, ctx, ["thick", "tile", "under", "edge", "gaps"])
			opts["rail"] = {"tile": v["rail_tile"]}
			var before: int = b.geometry["segments"].size()
			if type == "balcony":
				Geo.balcony(b, id, v["rect"], float(v["top"]), String(v["open"]), opts)
			else:
				Geo.bridge(b, id, v["rect"], float(v["top"]), opts)
			made.append(id)
			for k in range(before, b.geometry["segments"].size()):
				made.append(b.geometry["segments"][k]["id"])
		"ceiling":
			var opts := _geo_opts(v, ctx, ["tile", "cuts", "light"])
			made.append(Geo.ceiling(b, id, v["rect"], float(v["z"]), opts)["id"])
		"room_poly":
			var opts := {
				"roof": v["roof"],
				"wall": v["wall"],
				"thick": v["thick"],
				"openings": v["openings"],
				"light": v["light"]
			}
			for s: Dictionary in Geo.room_poly(
				b, id, v["points"], String(v["floor"]), _district(v, ctx), opts
			):
				made.append(s["id"])
		"corridor":
			_corridor(b, v, ctx)
		"fixture":
			var r: Array = v["rect"]
			b.fixture(
				float(r[0]),
				float(r[1]),
				float(r[2]),
				float(r[3]),
				float(v["top"]),
				String(v["side"]),
				String(v["cap"]),
				float(v["bottom"])
			)
		"prop":
			_prop(b, v, ctx)
		"sign":
			var at := _v(v["at"])
			var lift := float(v["z"]) - _ground(b, at)
			b.board(
				String(v["image"]), at.x, at.y, float(v["height"]), {"z": lift, "glow": v["glow"]}
			)
		"enemy":
			var at := _v(v["at"])
			b.enemy(String(v["kind"]), at.x, at.y, id, v["route"])
			if float(v["z"]) > 0.0:
				b.enemies[b.enemies.size() - 1]["z"] = float(v["z"])
		"pickup":
			var at := _v(v["at"])
			b.pickup(String(v["name"]), at.x, at.y, float(v["z"]))
		"station":
			var at := _v(v["at"])
			b.station(
				id,
				at.x,
				at.y,
				String(v["label"]),
				String(v["message"]),
				{"requires": v["requires"], "opens": v["opens"]}
			)
			var lift := float(v["z"]) - _ground(b, at)
			if float(v["z"]) > 0.0:
				b.stations[b.stations.size() - 1]["z"] = float(v["z"])
			if String(v["prop"]) != "":
				b.quest(String(v["prop"]), at.x, at.y, id)
				if lift > 0.0:
					b.billboards[b.billboards.size() - 1]["z"] = lift
		"exit":
			var at := _v(v["at"])
			b.meta["extraction"] = {
				"x": at.x, "y": at.y, "label": String(v["label"]), "shutdown": String(v["shutdown"])
			}
			if float(v["z"]) > 0.0:
				b.meta["extraction"]["z"] = float(v["z"])
		"label":
			var at := _v(v["at"])
			b.label(String(v["text"]), int(at.x), int(at.y))
		"spawn_point", "allow_overlap":
			pass
	ctx["made"][id] = made


static func _ground(b, at: Vector2) -> float:
	var x := clampi(int(at.x), 0, b.w - 1)
	var y := clampi(int(at.y), 0, b.h - 1)
	return float(b.ground[b.at(x, y)])


## A modelled prop (town_props.json) or an old flat one (GameState.PROP_HEIGHTS),
## lifted onto the floor at z (a deck).
static func _prop(b, v: Dictionary, _ctx: Dictionary) -> void:
	var name := String(v["name"])
	var at := _v(v["at"])
	var lift := float(v["z"]) - _ground(b, at)
	if GameState.PROP_HEIGHTS.has(name):
		b.prop(name, at.x, at.y)
		return
	var before: int = b.billboards.size()
	b.town(name, at.x, at.y, {"z": lift} if lift > 0.0 else {})
	if lift > 0.0 and b.billboards.size() > before:
		b.billboards[b.billboards.size() - 1]["z"] = lift


## A passage along cell centres: each straight leg a room `width` cells wide.
static func _corridor(b, v: Dictionary, ctx: Dictionary) -> void:
	var points: Array = v["points"]
	var half := int(v["width"]) / 2
	var extra := int(v["width"]) - half * 2
	var opts := {"roof": v["roof"], "light": v["light"], "ceiling": v["ceiling"]}
	for i in range(points.size() - 1):
		var a := Vector2i(int(floor(float(points[i][0]))), int(floor(float(points[i][1]))))
		var c := Vector2i(int(floor(float(points[i + 1][0]))), int(floor(float(points[i + 1][1]))))
		var x0 := mini(a.x, c.x) - half
		var x1 := maxi(a.x, c.x) + half + extra - 1
		var y0 := mini(a.y, c.y) - half
		var y1 := maxi(a.y, c.y) + half + extra - 1
		if a.y == c.y:
			y0 = a.y - half
			y1 = a.y + half + extra - 1
		elif a.x == c.x:
			x0 = a.x - half
			x1 = a.x + half + extra - 1
		else:
			ctx["issues"].append(
				_issue(
					"corridor_leg",
					String(v["id"]),
					"a corridor leg runs n/s or e/w only (%s to %s)" % [a, c]
				)
			)
			continue
		b.room(
			maxi(0, x0),
			maxi(0, y0),
			mini(b.w - 1, x1),
			mini(b.h - 1, y1),
			String(v["floor"]),
			_district(v, ctx),
			opts
		)
