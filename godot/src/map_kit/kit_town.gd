## The town's buildings: the general store (a false front over a boardwalk
## under an awning, a counter and shelves to hide behind, a ladder up the
## back), the gas station (a cinder box, a canopy on posts over the pump
## islands you can walk out onto from the box's roof) and the church (a nave
## of arched coloured windows and pews, a bell tower in front with a belfry
## up a ladder and a steeple, the bell rope a station).
class_name KitTown
extends RefCounted


static func build(kind: String, o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	match kind:
		"store":
			store(o, look, parts)
		"gas_station":
			gas_station(o, look, parts)
		"church":
			church(o, look, parts)


static func store(o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	var w: float = o["w"]
	var d: float = o["d"]
	var false_front: bool = o["false_front"]
	var awning: bool = o["awning"]
	var counter: bool = o["counter"]
	var shelves: int = o["shelves"]
	var with_ladder: bool = o["ladder"]
	var base := KitPiece.num("plinth")
	var deep := d - 2.0
	var body := Rect2(0, 0, w, deep)
	KitHouses._plinth(parts, look, body, base)
	var doors: Array[Dictionary] = [
		{"side": "s", "at": .5, "width": 2.0}, {"side": "n", "at": .7}, {"side": "e", "at": .6}
	]
	var made := KitBody.box(
		parts,
		look,
		body,
		{
			"storeys": 1,
			"storey": 3.0,
			"base": base,
			"doors": doors,
			"windows": 2,
			"win_head": 2.0,
			"win_width": 1.0
		}
	)
	var eave: float = made["eave"]
	var pitch := .4
	var roof := KitRoofs.gable(parts, "roof", body, eave, pitch, look, {"along": "v"})
	var ridge: float = roof["top"]
	var thick := KitPiece.num("roof_thick")
	var trim: String = look.get("trim", "kit_trim")
	var wall_tile: String = look.get("wall", "kit_clapboard_grey")
	if false_front:
		var top := ridge + .6
		parts.segment(
			"false_front",
			Vector2(-.1, deep - .1),
			Vector2(w + .1, deep - .1),
			eave,
			top,
			{"tile": wall_tile, "thick": .22}
		)
		parts.block("cornice", Rect2(-.25, deep - .4, w + .5, .45), top, top + .2, trim, trim)
	KitHouses.porch_on(parts, look, Rect2(0, deep, w, 2.0), base, eave - .2, false, awning)
	parts.glow(Vector2(w * .5, deep + 1.0), 3.0, .3)
	parts.prop("ice_chest", Vector2(w * .5 + 1.6, deep + .7), base)
	if counter:
		var cx := w * .55
		parts.block(
			"counter",
			Rect2(cx, deep * .35, w - .6 - cx, .6),
			0.0,
			base + 1.0,
			"counter",
			"counter_top"
		)
		parts.block(
			"counter_end",
			Rect2(cx, deep * .35 + .6, .6, 1.2),
			0.0,
			base + 1.0,
			"counter",
			"counter_top"
		)
	for k in shelves:
		var x := 1.4 + k * 1.6
		if x > w * .5 - .4:
			break
		parts.segment(
			"shelf%d" % k,
			Vector2(x, 1.0),
			Vector2(x, deep - 2.2),
			base,
			base + 1.8,
			{"tile": "shelves", "thick": .5}
		)
	parts.glow(Vector2(w * .5, deep * .5), 3.5, .25)
	if with_ladder:
		var lx := w * .25
		var z := eave + thick + lx * pitch
		parts.ladder("roof_ladder", Vector2(lx, 0), "s", 0.0, z)
		parts.roof_at(Vector2(lx, .6), z, true, "gable")
	else:
		var at: Vector2 = roof["at"]
		parts.roof_at(at, ridge, false, "gable")


static func gas_station(o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	var w: float = o["w"]
	var d: float = o["d"]
	var pumps: int = o["pumps"]
	var with_ladder: bool = o["ladder"]
	var bw := floorf(w * .5)
	var bd := 5.0
	var box := Rect2(0, 0, bw, bd)
	var doors: Array[Dictionary] = [
		{"side": "s", "at": .5, "width": 2.0}, {"side": "e", "at": .5}, {"side": "n", "at": .3}
	]
	var made := KitBody.box(
		parts,
		look,
		box,
		{
			"storeys": 1,
			"storey": 3.0,
			"doors": doors,
			"windows": 2,
			"win_sill": .8,
			"win_head": 2.2,
			"win_width": 1.2
		}
	)
	var eave: float = made["eave"]
	var flat := KitRoofs.flat(
		parts, "roof", box, eave, look, {"open": "sn" if with_ladder else "s"}
	)
	var top: float = flat["top"]
	parts.open(Rect2(0, bd, w, d - bd), "concrete", -1.0)
	var canopy := Rect2(.5, bd, w - 1.0, d - bd - .5)
	var fall := .03
	var thick := .35
	parts.slab(
		"canopy",
		canopy,
		top,
		thick,
		{"tile": "tin", "under": "kit_canopy", "edge": look.get("trim", "kit_trim")},
		Vector2(0, -fall)
	)
	parts.floor_at("canopy", Vector2(w * .5, bd + 1.0), top - fall * 1.0)
	var cy := (bd + d) * .5
	# The islands clear of the way in at the box's front door.
	var door_x := KitBody._door_middle(bw * .5, 2.0, bw)
	for k in pumps:
		var px := w * (k + 1) / (pumps + 1)
		if absf(px - door_x) < 1.5:
			px = door_x + (1.5 if px >= door_x else -1.5)
		px = clampf(px, 1.0, w - 1.0)
		parts.block(
			"island%d" % k, Rect2(px - .45, cy - 1.5, .9, 3.0), 0.0, .15, "concrete", "concrete"
		)
		parts.prop("fuel_pump", Vector2(px, cy), .15)
		for end in 2:
			var py := cy - 1.3 if end == 0 else cy + 1.3
			var under := top - (py - bd) * fall - thick
			parts.post("post%d_%d" % [k, end], Vector2(px, py), .15, under, "kit_trim", .22)
		parts.glow(Vector2(px, cy), 3.6, .45)
	var counter := Rect2(bw * .5, 1.0, bw * .5 - .5, .6)
	parts.block("counter", counter, 0.0, 1.0, "counter", "counter_top")
	parts.segment(
		"shelf",
		Vector2(1.0, 1.4),
		Vector2(1.0, bd - 1.6),
		0.0,
		1.7,
		{"tile": "shelves", "thick": .5}
	)
	parts.prop("tire_stack", Vector2(bw + .8, .9))
	parts.prop("gas_cans", Vector2(bw + 1.8, .8))
	if with_ladder:
		parts.ladder("roof_ladder", Vector2(bw * .75, 0), "s", 0.0, top)
		parts.roof_at(Vector2(bw * .5, bd * .5), top, true, "flat")
	else:
		parts.roof_at(Vector2(bw * .5, bd * .5), top, false, "flat")


static func church(o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	var w: float = o["w"]
	var d: float = o["d"]
	var pews: int = o["pews"]
	var bell: bool = o["bell"]
	var steeple: float = o["steeple"]
	var base := KitPiece.num("plinth")
	var deep := d - 3.0
	var nave := Rect2(0, 0, w, deep)
	var cx := w * .5
	var tower := Rect2(floorf(cx - 1.5), deep, 3.0, 3.0)
	KitHouses._plinth(parts, look, nave, base)
	KitHouses._plinth(parts, look, tower, base, "tower_plinth")
	var storey := 3.8
	var front := (tower.position.x + 1.5) / w
	var doors: Array[Dictionary] = [
		{"side": "s", "at": front, "width": 1.2, "head": 2.3},
		{"side": "e", "at": .3},
		{"side": "n", "at": .2}
	]
	var made := (
		KitBody
		. box(
			parts,
			look,
			nave,
			{
				"storeys": 1,
				"storey": storey,
				"base": base,
				"doors": doors,
				"windows": 2,
				"win_sill": 1.1,
				"win_head": 3.0,
				"win_width": .9,
				"glass": "kit_church_glass_lit",
				"arch": true,
			}
		)
	)
	var eave: float = made["eave"]
	var roof := KitRoofs.gable(parts, "roof", nave, eave, 1.0, look, {"along": "v"})
	var ridge: float = roof["top"]
	var nave_at: Vector2 = roof["at"]
	# Pews either side of the aisle, the altar at the back.
	var aisle := .6
	var mid := tower.position.x + 1.5
	for k in pews:
		var y := 2.4 + k * 1.3
		if y > deep - 1.8:
			break
		for side in 2:
			var x0 := 2.0 if side == 0 else mid + aisle
			var x1 := mid - aisle if side == 0 else w - 2.0
			if x1 - x0 < .8:
				continue
			parts.block(
				"pew%d_%d" % [k, side],
				Rect2(x0, y, x1 - x0, .45),
				0.0,
				base + .5,
				"wood",
				"counter_top"
			)
			parts.segment(
				"pew%d_%d_back" % [k, side],
				Vector2(x0, y + .48),
				Vector2(x1, y + .48),
				base,
				base + 1.0,
				{"tile": "wood", "thick": .08}
			)
	parts.block("altar", Rect2(mid - .6, .7, 1.2, .7), 0.0, base + 1.0, "wood", "counter_top")
	parts.glow(Vector2(cx, deep * .5), 4.5, .3)
	# The tower: its door, the nave's door through its back, a belfry floor up
	# a ladder with a way out each side, the steeple over it.
	var t0 := tower.position
	var belfry := 4.4
	var tower_top := belfry + 2.4
	var wl := {"tile": look.get("wall", "kit_clapboard"), "thick": KitPiece.num("wall")}
	var inset := KitPiece.num("wall") * .5
	var bel := {"width": 1.4, "sill": belfry + .5, "head": belfry + 1.9}
	var s_holes: Array[Dictionary] = [
		{"at": 1.5, "width": 1.2, "sill": base, "head": base + 2.3}, _at(bel, 1.5)
	]
	var side_holes: Array[Dictionary] = [_at(bel, 1.5)]
	parts.wall(
		"tower_s",
		t0 + Vector2(0, 3 - inset),
		t0 + Vector2(3, 3 - inset),
		base,
		tower_top,
		wl,
		s_holes
	)
	parts.wall(
		"tower_w", t0 + Vector2(inset, 0), t0 + Vector2(inset, 3), base, tower_top, wl, side_holes
	)
	parts.wall(
		"tower_e",
		t0 + Vector2(3 - inset, 0),
		t0 + Vector2(3 - inset, 3),
		base,
		tower_top,
		wl,
		side_holes
	)
	parts.wall(
		"tower_n", t0 + Vector2(0, inset), t0 + Vector2(3, inset), eave, tower_top, wl, side_holes
	)
	parts.doorway("tower_door", t0 + Vector2(1.5, 3 - inset), "s", base, 1.2, 2.3)
	var deck_look := {"tile": "porch", "under": "joists", "edge": "wood"}
	parts.slab(
		"belfry", Rect2(t0.x + .2, t0.y + 1.2, 2.6, 1.6), belfry, KitPiece.num("deck"), deck_look
	)
	parts.ladder("belfry_ladder", Vector2(t0.x + 1.5, t0.y + 1.2), "s", base, belfry)
	parts.floor_at("belfry", Vector2(t0.x + 1.5, t0.y + 2.0), belfry)
	parts.floor_at("tower", Vector2(t0.x + 1.5, t0.y + 2.2), base)
	KitRoofs.hip(parts, "steeple", tower, tower_top, steeple, look, {"overhang": .15})
	if bell:
		var sid := parts.station(
			"bell",
			Vector2(t0.x + 2.3, t0.y + 1.9),
			"RING THE CHURCH BELL",
			"THE BELL CARRIES CLEAR ACROSS THE COUNTY.",
			"church_bell"
		)
		parts.prop("quest_bell_rope", Vector2(t0.x + 2.3, t0.y + 2.0), base, sid)
	parts.roof_at(nave_at, ridge, false, "gable")


static func _at(hole: Dictionary, at: float) -> Dictionary:
	var out := hole.duplicate()
	out["at"] = at
	return out
