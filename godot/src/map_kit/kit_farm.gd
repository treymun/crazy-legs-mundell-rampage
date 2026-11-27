## The farm's buildings: the gambrel barn (big doors front and back, a
## hayloft over the front with its hay door and a ladder, bales to hide
## behind), the pole barn (a tin roof on posts, open sides, a back wall), the
## silo (round, a door each side, a cage ladder to a platform at the top),
## the grain bin (round, a cone roof walked on, a ladder up) and the water
## tower (legs, a balcony round the tank, a ladder up a leg).
class_name KitFarm
extends RefCounted


static func build(kind: String, o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	match kind:
		"barn":
			barn(o, look, parts)
		"pole_barn":
			pole_barn(o, look, parts)
		"silo":
			silo(o, look, parts)
		"grain_bin":
			grain_bin(o, look, parts)
		"water_tower":
			water_tower(o, look, parts)


## Hay bales (cover a body can hide behind) round the walls of `r` at z,
## where the dice put them, clear of the middle aisle; some stacked two high.
static func bales(parts: LevelParts, part: String, r: Rect2, z: float, count: int) -> void:
	var rng := parts.dice(part)
	var spots: Array[Vector2] = []
	var x0 := r.position.x + .7
	var x1 := r.end.x - .7
	var y := r.position.y + .6
	while y < r.end.y - .6:
		spots.append(Vector2(x0, y))
		spots.append(Vector2(x1, y))
		y += 1.4
	for k in mini(count, spots.size()):
		var pick := rng.randi_range(k, spots.size() - 1)
		var at := spots[pick]
		spots[pick] = spots[k]
		spots[k] = at
		var high := .62 if rng.randf() < .6 else 1.24
		parts.block(
			"%s%d" % [part, k],
			Rect2(at.x - .42, at.y - .3, .84, .6),
			z,
			z + high,
			"kit_hay",
			"kit_hay"
		)


static func barn(o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	var w: float = o["w"]
	var d: float = o["d"]
	var loft: bool = o["loft"]
	var count: int = o["bales"]
	var side_door: bool = o["side_door"]
	var kind: String = o["roof"]
	var storey := 2.6
	var body := Rect2(0, 0, w, d)
	var doors: Array[Dictionary] = [
		{"side": "s", "at": .5, "width": 3.0, "head": storey - .2},
		{"side": "n", "at": .5, "width": 3.0, "head": storey - .2},
	]
	if side_door:
		doors.append({"side": "e", "at": .3})
	if loft:
		doors.append({"side": "s", "at": .5, "width": 1.4, "head": 1.5, "storey": 1, "walk": false})
	var made := KitBody.box(
		parts,
		look,
		body,
		{"storeys": 2, "storey": storey, "decks": false, "doors": doors, "windows": 3}
	)
	var eave: float = made["eave"]
	var thick := KitPiece.num("wall")
	if loft:
		var front := d * .45
		var deck_look := {"tile": "porch", "under": "joists", "edge": "wood"}
		parts.slab(
			"loft",
			Rect2(thick, front, w - thick * 2, d - thick - front),
			storey,
			KitPiece.num("deck"),
			deck_look
		)
		var ladder_x := floorf(w * .25) + .5
		parts.ladder("loft_ladder", Vector2(ladder_x, front), "s", 0.0, storey)
		KitBits.rail_run(
			parts,
			"loft_rail",
			Vector2(ladder_x + .7, front + .05),
			Vector2(w - thick, front + .05),
			storey,
			"wood"
		)
		parts.floor_at("loft", Vector2(w * .5, (front + d) * .5), storey)
		bales(
			parts,
			"loft_bale",
			Rect2(thick, front + 1.0, w - thick * 2, d - front - 2.2),
			storey,
			count >> 1
		)
	parts.floor_at("floor", Vector2(w * .5, d * .3), 0.0)
	bales(
		parts, "bale", Rect2(thick, thick, w - thick * 2, d * .45 - .6), 0.0, count - (count >> 1)
	)
	var roof: Dictionary
	if kind == "gable":
		roof = KitRoofs.gable(parts, "roof", body, eave, .8, look, {"along": "v"})
	else:
		roof = KitRoofs.gambrel(parts, "roof", body, eave, look, {"along": "v"})
	var at: Vector2 = roof["at"]
	var top: float = roof["top"]
	parts.roof_at(at, top, false, kind)
	parts.glow(Vector2(w * .5, d * .5), 3.0, .2)
	parts.note("set_piece", "barn")


## A tin roof on posts: open on three sides (o.back_wall closes the back), hay
## stacked inside.
static func pole_barn(o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	var w: float = o["w"]
	var d: float = o["d"]
	var pitch: float = o["pitch"]
	var back: bool = o["back_wall"]
	var count: int = o["bales"]
	var eave := 3.2
	var body := Rect2(0, 0, w, d)
	parts.open(body, "", .85)
	var wall_tile: String = look.get("wall", "tin")
	var rows := maxi(2, ceili(d / 3.0) + 1)
	for k in rows:
		var y := lerpf(.15, d - .15, float(k) / (rows - 1))
		parts.post("post_w%d" % k, Vector2(.15, y), 0.0, eave, "wood", .2)
		parts.post("post_e%d" % k, Vector2(w - .15, y), 0.0, eave, "wood", .2)
	if back:
		parts.segment(
			"back_wall", Vector2(0, .1), Vector2(w, .1), 0.0, eave, {"tile": wall_tile, "thick": .2}
		)
	var roof := KitRoofs.gable(
		parts, "roof", body, eave, pitch, look, {"ends": back, "overhang": .4}
	)
	var at: Vector2 = roof["at"]
	var top: float = roof["top"]
	parts.roof_at(at, top, false, "gable")
	parts.floor_at("floor", Vector2(w * .5, d * .5), 0.0)
	parts.doorway("front", Vector2(w * .5, d), "s", 0.0, w - .6, eave)
	bales(parts, "bale", Rect2(.3, 1.0, w - .6, d - 1.6), 0.0, count)


## A silo of staves: round (o.d across), o.height high under a cone, a
## doorway south and a chute north, a cage ladder up its east side to a
## railed platform at the top (o.platform; o.w - o.d wide beside it).
static func silo(o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	var w: float = o["w"]
	var d: float = o["d"]
	var height: float = o["height"]
	var pitch: float = o["pitch"]
	var platform: bool = o["platform"] and w - d >= 1.5
	var radius := d * .5
	var c := Vector2(radius, radius)
	var wall_tile: String = look.get("wall", "kit_staves")
	var floor_tile: String = look.get("floor", "concrete")
	parts.open(Rect2(0, 0, ceilf(d), ceilf(d)), floor_tile, .8)
	var wl := {"tile": wall_tile, "thick": KitPiece.num("wall")}
	var inner := radius - KitPiece.num("wall") * .5
	KitBits.arc(parts, "wall", c, inner, -90.0, 270.0, 0.0, height, wl, {"doors": [90.0, 270.0]})
	var roof := KitRoofs.cone(parts, "roof", c, radius, height, pitch, look, {"overhang": 0.0})
	var top: float = roof["top"]
	parts.roof_at(c, top, false, "cone")
	parts.floor_at("floor", c, 0.0)
	if platform:
		var pw := minf(w - d, 2.0)
		var deck := Rect2(d, radius - .7, pw, 1.4)
		parts.slab(
			"platform",
			deck,
			height,
			.12,
			{"tile": "steel_mesh", "under": "steel_mesh", "edge": "tin"}
		)
		KitBits.rail_run(
			parts, "rail_n", Vector2(d, radius - .65), Vector2(d + pw, radius - .65), height, "tin"
		)
		KitBits.rail_run(
			parts, "rail_s", Vector2(d, radius + .65), Vector2(d + pw, radius + .65), height, "tin"
		)
		parts.ladder("ladder", Vector2(d + pw, radius), "w", 0.0, height, "tin")
		for k in 3:
			var z := height * (k + 1) / 4.0
			var hoop := {"tile": "tin", "thick": .06, "sight": false, "shots": false}
			parts.segment(
				"cage%d" % k,
				Vector2(d + pw + .55, radius - .4),
				Vector2(d + pw + .55, radius + .4),
				z,
				z + .06,
				hoop
			)
		parts.floor_at("platform", Vector2(d + pw * .5, radius), height)


## A round grain bin of corrugated tin, a cone roof walked on, a ladder up
## its east side onto the roof, a door south and north.
static func grain_bin(o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	var w: float = o["w"]
	var d: float = o["d"]
	var height: float = o["height"]
	var pitch: float = o["pitch"]
	var with_ladder: bool = o["ladder"]
	var radius := minf(w, d) * .5
	var c := Vector2(w * .5, d * .5)
	var floor_tile: String = look.get("floor", "concrete")
	parts.open(Rect2(0, 0, w, d), floor_tile, .8)
	var wl := {"tile": look.get("wall", "tin"), "thick": KitPiece.num("wall")}
	var inner := radius - KitPiece.num("wall") * .5
	KitBits.arc(parts, "wall", c, inner, -90.0, 270.0, 0.0, height, wl, {"doors": [90.0, 270.0]})
	var thick := KitPiece.num("roof_thick")
	var roof := KitRoofs.cone(parts, "roof", c, radius, height, pitch, look, {"overhang": 0.0})
	var top: float = roof["top"]
	parts.floor_at("floor", c, 0.0)
	if with_ladder:
		parts.ladder("ladder", c + Vector2(radius, 0), "w", 0.0, height + thick, "tin")
		var on := c + Vector2(radius * .55, 0)
		parts.roof_at(
			on, height + thick + pitch * radius * .45 * cos(PI / KitRoofs.FACETS), true, "cone"
		)
	else:
		parts.roof_at(c, top, false, "cone")


## A water tower: four legs, a railed balcony o.height up round a round tank
## with a doorway into it, a cone on top, a ladder up the south side.
static func water_tower(o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	var w: float = o["w"]
	var d: float = o["d"]
	var height: float = o["height"]
	var c := Vector2(w * .5, d * .5)
	var deck := Rect2(.2, .2, w - .4, d - .4)
	parts.slab(
		"balcony", deck, height, .2, {"tile": "steel_mesh", "under": "steel_mesh", "edge": "tin"}
	)
	for k in 4:
		var at := Vector2(1.0 if k % 2 == 0 else w - 1.0, 1.0 if k < 2 else d - 1.0)
		parts.post("leg%d" % k, at, 0.0, height - .2, "tin", .3)
	var brace := {"tile": "tin", "thick": .08, "sight": false, "shots": false}
	var z := height * .45
	parts.segment("brace_n", Vector2(1.0, 1.0), Vector2(w - 1.0, 1.0), z, z + .1, brace)
	parts.segment("brace_s", Vector2(1.0, d - 1.0), Vector2(w - 1.0, d - 1.0), z, z + .1, brace)
	parts.segment("brace_w", Vector2(1.0, 1.0), Vector2(1.0, d - 1.0), z, z + .1, brace)
	parts.segment("brace_e", Vector2(w - 1.0, 1.0), Vector2(w - 1.0, d - 1.0), z, z + .1, brace)
	var ladder_x := floorf(c.x + .5) + .5
	var e := .25
	KitBits.rail_run(parts, "rail_n", Vector2(e, e), Vector2(w - e, e), height, "tin")
	KitBits.rail_run(parts, "rail_w", Vector2(e, e), Vector2(e, d - e), height, "tin")
	KitBits.rail_run(parts, "rail_e", Vector2(w - e, e), Vector2(w - e, d - e), height, "tin")
	KitBits.rail_run(
		parts, "rail_s0", Vector2(e, d - e), Vector2(ladder_x - .45, d - e), height, "tin"
	)
	KitBits.rail_run(
		parts, "rail_s1", Vector2(ladder_x + .45, d - e), Vector2(w - e, d - e), height, "tin"
	)
	parts.ladder("ladder", Vector2(ladder_x, d - .2), "n", 0.0, height, "tin")
	var tank := minf(w, d) * .5 - 1.5
	var wl := {"tile": look.get("wall", "tin"), "thick": .16}
	KitBits.arc(
		parts,
		"tank",
		c,
		tank,
		-90.0,
		270.0,
		height,
		height + 3.0,
		wl,
		{"doors": [90.0], "door_head": height + KitPiece.num("door_head"), "walk_out": .7}
	)
	var roof := KitRoofs.cone(parts, "roof", c, tank + .1, height + 3.0, .7, look, {"overhang": .2})
	var top: float = roof["top"]
	parts.roof_at(c, top, false, "cone")
	parts.floor_at("balcony", Vector2(ladder_x, d - .7), height)
	parts.floor_at("tank", c, height)
	parts.note("set_piece", "tower")
