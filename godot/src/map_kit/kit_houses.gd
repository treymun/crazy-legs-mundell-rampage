## Places folks live: the plain house, the farmhouse (porch, balcony door,
## chimney, a ladder up the gable), the shack (lean-to roof, stovepipe), the
## single-wide trailer (on blocks, steps to both doors, an awning) and the
## outhouse. Each in its own frame, the front on the local south side.
class_name KitHouses
extends RefCounted


static func build(kind: String, o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	match kind:
		"house":
			house(o, look, parts)
		"farmhouse":
			farmhouse(o, look, parts)
		"shack":
			shack(o, look, parts)
		"trailer":
			trailer(o, look, parts)
		"outhouse":
			outhouse(o, look, parts)


## Door sides as letters ("sne") -> KitBody doors: the front in the middle,
## the back toward the east, the sides in the middle.
static func doors_for(letters: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var at := {"s": .5, "n": .7, "e": .5, "w": .3}
	for side: String in ["s", "n", "e", "w"]:
		if letters.contains(side):
			var spot: float = at[side]
			out.append({"side": side, "at": spot})
	return out


## The plain box house (the pass-16 audit's): storeys, a roof of any kind,
## doors on the sides asked for, windows on every floor.
static func house(o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	var w: float = o["w"]
	var d: float = o["d"]
	var storeys: int = o["storeys"]
	var kind: String = o["roof"]
	var pitch: float = o["pitch"]
	var letters: String = o["doors"]
	var plinth: bool = o["plinth"]
	var ladder: bool = o["ladder"]
	var base := KitPiece.num("plinth") if plinth else 0.0
	var body := Rect2(0, 0, w, d)
	if plinth:
		_plinth(parts, look, body, base)
	var made := KitBody.box(
		parts,
		look,
		body,
		{
			"storeys": storeys,
			"base": base,
			"doors": doors_for(letters),
			"windows": o["windows"],
			"rooms": o["rooms"]
		}
	)
	var eave: float = made["eave"]
	_roof(parts, look, body, eave, kind, pitch, ladder)


## A farmhouse: the body behind a front porch o.porch deep, its roof the
## upper floor's balcony (a doorway out onto it), a brick chimney up the east
## end, a ladder up the west end onto the roof.
static func farmhouse(o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	var w: float = o["w"]
	var d: float = o["d"]
	var storeys: int = o["storeys"]
	var kind: String = o["roof"]
	var pitch: float = o["pitch"]
	var porch: int = o["porch"]
	var chimney: bool = o["chimney"]
	var ladder: bool = o["ladder"]
	var balcony: bool = o["balcony"]
	var storey := KitPiece.num("storey")
	var base := KitPiece.num("plinth")
	var body := Rect2(0, 0, w, d - porch)
	_plinth(parts, look, body, base)
	var doors := doors_for("sne")
	if balcony and storeys > 1 and porch > 0:
		doors.append({"side": "s", "at": .5, "storey": 1})
	var made := KitBody.box(
		parts,
		look,
		body,
		{
			"storeys": storeys,
			"base": base,
			"doors": doors,
			"windows": o["windows"],
			"rooms": o["rooms"]
		}
	)
	var eave: float = made["eave"]
	if porch > 0:
		var meet := base + storey if storeys > 1 else eave - .35
		porch_on(parts, look, Rect2(0, d - porch, w, porch), base, meet, true, true)
		parts.glow(Vector2(w * .5, d - porch * .5), 3.2, .35)
	if chimney:
		var top := eave + (minf(w, d - porch) * .5) * pitch + .9
		var at_x := w - .55
		parts.block(
			"chimney", Rect2(at_x, (d - porch) * .25 - .45, .9, .9), 0.0, top, "brick", "cinder"
		)
	_roof(parts, look, body, eave, kind, pitch, ladder)


## The roof over a body, and o.ladder up its west (or north) end onto it.
static func _roof(
	parts: LevelParts,
	look: Dictionary,
	body: Rect2,
	eave: float,
	kind: String,
	pitch: float,
	ladder: bool
) -> void:
	var opts := {"rake": 0.0}
	if kind == "flat" and ladder:
		opts["open"] = "n"
	var roof := KitRoofs.over(parts, "roof", kind, body, eave, pitch, look, opts)
	var at: Vector2 = roof["at"]
	var walk: bool = roof["walk"]
	var top: float = roof.get("walk_top", roof["top"])
	var thick := KitPiece.num("roof_thick")
	var along_x := body.size.x >= body.size.y
	if not ladder or not walk:
		parts.roof_at(at, top, false, kind)
		return
	var x0 := body.position.x
	var y0 := body.position.y
	match kind:
		"gable", "gambrel":
			# Up the end wall onto the near slope a quarter of the way across.
			if kind == "gambrel":
				parts.roof_at(at, top, false, kind)
			elif along_x:
				var y := y0 + body.size.y * .25
				var z := eave + thick + (y - y0) * pitch
				parts.ladder("roof_ladder", Vector2(x0, y), "e", 0.0, z)
				parts.roof_at(Vector2(x0 + .6, y), z, true, kind)
			else:
				var x := x0 + body.size.x * .25
				var z := eave + thick + (x - x0) * pitch
				parts.ladder("roof_ladder", Vector2(x, y0), "s", 0.0, z)
				parts.roof_at(Vector2(x, y0 + .6), z, true, kind)
		"flat":
			parts.ladder("roof_ladder", Vector2(x0 + body.size.x * .25, y0), "s", 0.0, eave + .2)
			parts.roof_at(body.get_center(), eave + .2, true, kind)
		_:
			parts.roof_at(at, top, false, kind)


## A plinth the body stands on (a stone foundation's edge round it).
static func _plinth(
	parts: LevelParts, look: Dictionary, body: Rect2, base: float, part := "plinth"
) -> void:
	var found: String = look.get("found", "kit_stone")
	var floor_tile: String = look.get("floor", "kit_porch")
	parts.block(part, body.grow(.05), 0.0, base, found, floor_tile)


## A porch over local `r` against a wall on its north side: a deck at `base`
## (solid), posts, a shed roof meeting the wall at `meet` falling .25 a unit,
## rails with a gap for the steps in the middle of the south side.
static func porch_on(
	parts: LevelParts,
	look: Dictionary,
	r: Rect2,
	base: float,
	meet: float,
	rails: bool,
	roofed: bool
) -> void:
	var floor_tile: String = look.get("floor", "kit_porch")
	var found: String = look.get("found", "kit_stone")
	var trim: String = look.get("trim", "kit_trim")
	if base > 0.0:
		parts.block("porch", r, 0.0, base, found, floor_tile)
	else:
		parts.open(r, floor_tile)
	var x0 := r.position.x
	var x1 := r.end.x
	var y0 := r.position.y
	var y1 := r.end.y
	parts.floor_at("porch", Vector2((x0 + x1) * .5, (y0 + y1) * .5), base)
	var fall := .25
	var thick := .12
	if roofed:
		var skin := KitRoofs._skin(look)
		parts.slab(
			"porch_roof",
			Rect2(x0 - .1, y0, x1 - x0 + .2, y1 - y0 + .2),
			meet,
			thick,
			skin,
			Vector2(0, -fall)
		)
		var posts := maxi(2, ceili((x1 - x0) / 3.0) + 1)
		for k in posts:
			var px := lerpf(x0 + .15, x1 - .15, float(k) / (posts - 1))
			var py := y1 - .15
			var under := meet - (py - y0) * fall - thick
			parts.post("porch_post%d" % k, Vector2(px, py), base, under, trim)
		parts.note("porch_roof", {"meet": meet, "fall": fall})
	if rails:
		var mid := (x0 + x1) * .5
		var gap := .7
		KitBits.rail_run(
			parts,
			"porch_rail_s0",
			Vector2(x0 + .15, y1 - .15),
			Vector2(mid - gap, y1 - .15),
			base,
			trim
		)
		KitBits.rail_run(
			parts,
			"porch_rail_s1",
			Vector2(mid + gap, y1 - .15),
			Vector2(x1 - .15, y1 - .15),
			base,
			trim
		)
		KitBits.rail_run(
			parts,
			"porch_rail_w",
			Vector2(x0 + .15, y0 + .3),
			Vector2(x0 + .15, y1 - .15),
			base,
			trim
		)
		KitBits.rail_run(
			parts,
			"porch_rail_e",
			Vector2(x1 - .15, y0 + .3),
			Vector2(x1 - .15, y1 - .15),
			base,
			trim
		)


## A one-room shack under a lean-to roof (high at the back), a door front and
## back, a stovepipe through the roof.
static func shack(o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	var w: float = o["w"]
	var d: float = o["d"]
	var pitch: float = o["pitch"]
	var back: bool = o["back_door"]
	var pipe: bool = o["stovepipe"]
	var body := Rect2(0, 0, w, d)
	var made := KitBody.box(
		parts,
		look,
		body,
		{"storeys": 1, "storey": 2.2, "doors": doors_for("sn" if back else "s"), "windows": 2}
	)
	var eave: float = made["eave"]
	var roof := KitRoofs.shed(parts, "roof", body, eave, pitch, look, {"overhang": .25})
	var top: float = roof["top"]
	parts.roof_at(body.get_center(), top, false, "shed")
	if pipe:
		parts.post("stovepipe", Vector2(w - 1.0, 1.0), eave - .4, top + .7, "tin", .18)


## A single-wide trailer on cinder blocks: the floor .7 up, steps to a front
## door and a back one, a flat tin roof, an awning over the front door.
static func trailer(o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	var w: float = o["w"]
	var back: bool = o["back_door"]
	var awning: bool = o["awning"]
	var base := .7
	var body := Rect2(0, 1, w, 3)
	var found: String = look.get("found", "cinder")
	var floor_tile: String = look.get("floor", "floor_tile")
	parts.block("blocks", body, 0.0, base, found, floor_tile)
	parts.open(Rect2(0, 0, w, 5), "")
	var doors: Array[Dictionary] = [{"side": "s", "at": .3}]
	if back:
		doors.append({"side": "n", "at": .75})
	var made := KitBody.box(
		parts,
		look,
		body,
		{"storeys": 1, "storey": 2.1, "base": base, "doors": doors, "windows": 2, "rooms": 2}
	)
	var eave: float = made["eave"]
	var step_look := {"tile": "porch", "under": "porch", "edge": "wood"}
	var front_x := floorf(clampf(w * .3, 1.0, w - 2.0)) + .5
	parts.stairs("steps_s", Rect2(front_x - .6, 4, 1.2, 1), 0.0, base, "n", step_look)
	if back:
		var back_x := floorf(clampf(w * .75, 1.0, w - 2.0)) + .5
		parts.stairs("steps_n", Rect2(back_x - .6, 0, 1.2, 1), 0.0, base, "s", step_look)
	if awning:
		var skin := KitRoofs._skin(look)
		parts.slab(
			"awning", Rect2(front_x - 1.1, 4, 2.2, .9), eave - .1, .08, skin, Vector2(0, -.25)
		)
		parts.post(
			"awning_post0", Vector2(front_x - 1.0, 4.8), 0.0, eave - .1 - .8 * .25 - .08, "tin", .1
		)
		parts.post(
			"awning_post1", Vector2(front_x + 1.0, 4.8), 0.0, eave - .1 - .8 * .25 - .08, "tin", .1
		)
	var roof := KitRoofs.flat(parts, "roof", body, eave, look, {"ends": false, "thick": .15})
	var top: float = roof["top"]
	parts.roof_at(body.get_center(), top, false, "flat")
	parts.glow(Vector2(front_x, 4.5), 2.6, .3)


## An outhouse: a plank box with a door and a lean-to roof.
static func outhouse(o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	var w: float = o["w"]
	var d: float = o["d"]
	var body := Rect2(0, 0, w, d)
	var made := KitBody.box(
		parts,
		look,
		body,
		{"storeys": 1, "storey": 2.1, "doors": [{"side": "s", "at": .5, "width": .8}], "windows": 0}
	)
	var eave: float = made["eave"]
	var roof := KitRoofs.shed(parts, "roof", body, eave, .3, look, {"overhang": .15})
	var top: float = roof["top"]
	parts.roof_at(body.get_center(), top, false, "shed")
