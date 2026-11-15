## Places to climb for the plans (layouts after v3.1.0): blocks walked on
## top (a shed's flat roof, a stack of bales or crates, a grain bin), towers
## on corner posts (a deer stand, a lookout, a water tower's walk), catwalks,
## and the ladders up them (geo_kit.gd ladder(); src/climbing.gd climbs them
## and the hands take them). A block no higher than Climbing's MANTLE_MAX
## (1.15) is pulled up onto without a ladder; jumps between blocks of one
## height want a gap of 1.6 at most.
##
##   const Climb := preload("res://tools/levels/climb_kit.gd")
##   Climb.shed(b, "feed_shed", [20, 4, 23, 6], 1.9, "s", {"edge": "barn"})
extends RefCounted

const Geo := preload("res://tools/levels/geo_kit.gd")


## Solid to the ground and walked on top: o.tile (its top, "tin"), o.edge (its
## sides, "barn"), light, area.
static func block(b, id: String, rect: Array, top: float, o := {}) -> Dictionary:
	var opts := {
		"kind": "block",
		"thick": -1.0,
		"tile": String(o.get("tile", "tin")),
		"edge": String(o.get("edge", "barn")),
		"light": float(o.get("light", .85)),
		"area": int(o.get("area", 0)),
	}
	return Geo.slab(b, id, rect, top, opts)


## A ladder on the `side` (n, e, s, w) of `rect`, `along` that side (0..1),
## from the floor at z0 up to z1 on top; o: tile, light, area.
static func ladder_on(
	b, id: String, rect: Array, z0: float, z1: float, side: String, along := .5, o := {}
) -> Dictionary:
	var r := Geo._rect(rect)
	var x := lerpf(r[0], r[2], along)
	var y := lerpf(r[1], r[3], along)
	match side:
		"n":
			return Geo.ladder(b, id, x, r[1], "s", z0, z1, o)
		"s":
			return Geo.ladder(b, id, x, r[3], "n", z0, z1, o)
		"w":
			return Geo.ladder(b, id, r[0], y, "e", z0, z1, o)
	return Geo.ladder(b, id, r[2], y, "w", z0, z1, o)


## A block with a ladder up its `side` (a shed's roof, a grain bin).
static func shed(b, id: String, rect: Array, top: float, side: String, o := {}) -> Dictionary:
	var made := block(b, id, rect, top, o)
	var lo := {
		"tile": String(o.get("ladder", "wood")),
		"light": float(o.get("light", .85)),
		"area": int(o.get("area", 0)),
	}
	ladder_on(
		b, id + "_ladder", rect, float(o.get("base", 0.0)), top, side, float(o.get("along", .5)), lo
	)
	if o.has("rail"):
		# Rails along the sides named (a bin's top, a roof's drop).
		_rails(b, id, Geo._rect(rect), top, String(o["rail"]), side, float(o.get("along", .5)), o)
	return made


## A deck on corner posts (a deer stand, a lookout, a water tower's walk),
## railed on every side but where its ladder stands at the middle of `side`;
## o: tile, edge, post (the posts' tile), roof (a tin roof this high over the
## deck), ladder (its tile), base (the floor it stands on), light, area.
static func tower(b, id: String, rect: Array, top: float, side: String, o := {}) -> Dictionary:
	var r := Geo._rect(rect)
	var base := float(o.get("base", 0.0))
	var made := (
		Geo
		. deck(
			b,
			id,
			r,
			top,
			{
				"tile": String(o.get("tile", "porch")),
				"under": "joists",
				"edge": String(o.get("edge", "wood")),
				"light": float(o.get("light", .85)),
				"area": int(o.get("area", 0)),
			}
		)
	)
	var post := {"thick": .22, "tile": String(o.get("post", "wood")), "area": int(o.get("area", 0))}
	var corners: Array[Vector2] = [
		Vector2(r[0], r[1]), Vector2(r[2], r[1]), Vector2(r[0], r[3]), Vector2(r[2], r[3])
	]
	for k in corners.size():
		var at: Vector2 = corners[k]
		Geo.wall(b, "%s_post%d" % [id, k], at, at + Vector2(.01, 0), base, top - .15, post)
	_rails(b, id, r, top, "nesw", side, .5, o)
	var lo := {
		"tile": String(o.get("ladder", "wood")),
		"light": float(o.get("light", .85)),
		"area": int(o.get("area", 0)),
	}
	ladder_on(b, id + "_ladder", r, base, top, side, .5, lo)
	if o.has("roof"):
		var roof := top + float(o["roof"])
		for k in corners.size():
			var at: Vector2 = corners[k]
			Geo.wall(b, "%s_upright%d" % [id, k], at, at + Vector2(.01, 0), top, roof, post)
		Geo.slab(
			b,
			id + "_roof",
			[r[0] - .15, r[1] - .15, r[2] + .15, r[3] + .15],
			roof + .08,
			{"thick": .08, "tile": "tin", "under": "tin", "edge": "tin", "walk": false}
		)
	return made


## A walk along a wall at `top` (a catwalk in a mill or a ship), railed along
## its open long side, a ladder up at one end (`side`, `along`).
static func catwalk(
	b, id: String, rect: Array, top: float, open: String, side: String, along: float, o := {}
) -> Dictionary:
	var r := Geo._rect(rect)
	var made := (
		Geo
		. balcony(
			b,
			id,
			r,
			top,
			open,
			{
				"tile": String(o.get("tile", "steel_mesh")),
				"under": String(o.get("under", "steel_mesh")),
				"edge": String(o.get("edge", "mill_tin")),
				"light": float(o.get("light", .8)),
				"area": int(o.get("area", 0)),
				"gaps": _gap(r, side, along),
				"rail": {"tile": String(o.get("rail", "stockyard"))},
			}
		)
	)
	var lo := {
		"tile": String(o.get("ladder", "mill_tin")),
		"light": float(o.get("light", .8)),
		"area": int(o.get("area", 0)),
	}
	ladder_on(b, id + "_ladder", r, float(o.get("base", 0.0)), top, side, along, lo)
	for at: Variant in o.get("posts", []):
		var p: Vector2 = at
		Geo.wall(
			b,
			"%s_post_%d_%d" % [id, int(p.x * 10), int(p.y * 10)],
			p,
			p + Vector2(.01, 0),
			float(o.get("base", 0.0)),
			top - .15,
			{"thick": .14, "tile": String(o.get("edge", "mill_tin"))}
		)
	return made


static func _gap(r: Array, side: String, along: float) -> Array:
	var length: float = (r[2] - r[0]) if side == "n" or side == "s" else (r[3] - r[1])
	var mid := length * along
	return [[side, mid - .38, mid + .38]]


static func _rails(
	b, id: String, r: Array, top: float, sides: String, side: String, along: float, o: Dictionary
) -> void:
	var inset := .06
	var ends := {
		"n": [Vector2(r[0], r[1] + inset), Vector2(r[2], r[1] + inset)],
		"s": [Vector2(r[0], r[3] - inset), Vector2(r[2], r[3] - inset)],
		"w": [Vector2(r[0] + inset, r[1]), Vector2(r[0] + inset, r[3])],
		"e": [Vector2(r[2] - inset, r[1]), Vector2(r[2] - inset, r[3])],
	}
	var rail_o := {"tile": String(o.get("rail_tile", "stockyard"))}
	for s: String in sides:
		var p: Vector2 = ends[s][0]
		var q: Vector2 = ends[s][1]
		if s != side:
			Geo.rail(b, "%s_rail_%s" % [id, s], p, q, top, rail_o)
			continue
		var length := p.distance_to(q)
		var g0 := (length * along - .38) / length
		var g1 := (length * along + .38) / length
		if g0 > .02:
			Geo.rail(b, "%s_rail_%s0" % [id, s], p, p.lerp(q, g0), top, rail_o)
		if g1 < .98:
			Geo.rail(b, "%s_rail_%s1" % [id, s], p.lerp(q, g1), q, top, rail_o)
