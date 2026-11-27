## The kit's bits: a porch, stairs (straight, L, switchback), a ramp, a
## ladder, fence runs (rail, wire, picket, stock), bridges (plank, covered), a
## wall with doors and windows by storey, an arch, a curved wall, a chimney, a
## loading dock, a catwalk and a tower (a hunting stand). Plus the helpers
## the buildings share: rail runs, arcs of wall and stepped arch heads.
class_name KitBits
extends RefCounted


static func build(kind: String, o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	match kind:
		"porch":
			porch(o, look, parts)
		"stairs":
			stairs(o, look, parts)
		"ramp":
			ramp(o, look, parts)
		"ladder":
			ladder(o, look, parts)
		"fence":
			fence(o, look, parts)
		"bridge":
			bridge(o, look, parts)
		"wall":
			wall(o, look, parts)
		"arch":
			arch(o, look, parts)
		"curved_wall":
			curved_wall(o, look, parts)
		"chimney":
			chimney(o, look, parts)
		"dock":
			dock(o, look, parts)
		"catwalk":
			catwalk(o, look, parts)
		"tower":
			tower(o, look, parts)


# ------------------------------------------------------------------- helpers


## A rail from a to b standing on z: posts every 2 and two bars a body cannot
## pass, a look and a shot can.
static func rail_run(
	parts: LevelParts, part: String, a: Vector2, b: Vector2, z: float, tile: String
) -> void:
	var length := a.distance_to(b)
	if length < .2:
		return
	var posts := maxi(2, ceili(length / 2.0) + 1)
	for k in posts:
		parts.post("%s_p%d" % [part, k], a.lerp(b, float(k) / (posts - 1)), z, z + 1.02, tile, .12)
	var bar := {"tile": tile, "thick": .08, "sight": false, "shots": false}
	parts.segment(part + "_lo", a, b, z + .42, z + .52, bar)
	parts.segment(part + "_hi", a, b, z + .86, z + .96, bar)


## A wall round an arc (centre c, radius, from and to in degrees, 0 east, 90
## south) in straight pieces at most map_kit "curve_piece" long; doorways
## o.door_width wide at each of o.doors (degrees) up to o.door_head.
static func arc(
	parts: LevelParts,
	part: String,
	c: Vector2,
	radius: float,
	from: float,
	to: float,
	z0: float,
	z1: float,
	look: Dictionary,
	o := {}
) -> int:
	var span := deg_to_rad(to - from)
	var most := KitPiece.num("curve_piece")
	var n := maxi(4, ceili(absf(span) * radius / most))
	n = ceili(n / 4.0) * 4
	var doors: Array = o.get("doors", [])
	var door_width: float = o.get("door_width", 1.6)
	var walk_out: float = o.get("walk_out", 1.1)
	var door_head: float = o.get("door_head", z0 + KitPiece.num("door_head"))
	var made := 0
	for k in n:
		var t0 := deg_to_rad(from) + span * k / n
		var t1 := deg_to_rad(from) + span * (k + 1) / n
		var p0 := c + Vector2.from_angle(t0) * radius
		var p1 := c + Vector2.from_angle(t1) * radius
		# Each chord a little longer, so the outside corners close.
		var grow := (p1 - p0).normalized() * .03
		var bottom := z0
		var chord := p0.distance_to(p1)
		for v: Variant in doors:
			var door: float = v
			var off := absf(angle_difference((t0 + t1) * .5, deg_to_rad(door))) * radius
			if off < (door_width + chord) * .5:
				bottom = door_head
		if bottom < z1:
			parts.segment("%s_%d" % [part, k], p0 - grow, p1 + grow, bottom, z1, look)
			made += 1
	for i in doors.size():
		var door: float = doors[i]
		var way := Vector2.from_angle(deg_to_rad(door))
		parts.doorway(
			"%s_door%d" % [part, i],
			c + way * radius,
			_face_of(way),
			z0,
			door_width,
			door_head - z0,
			true,
			walk_out
		)
	return made


## The compass side nearest a direction.
static func _face_of(way: Vector2) -> String:
	if absf(way.x) >= absf(way.y):
		return "e" if way.x > 0.0 else "w"
	return "s" if way.y > 0.0 else "n"


## A stepped arch head in an opening from a to b (along its wall), its top
## at head: pairs of wall pieces filling the upper corners in steps.
static func arch_head(
	parts: LevelParts,
	part: String,
	a: Vector2,
	b: Vector2,
	head: float,
	look: Dictionary,
	steps: Array[Vector3]
) -> void:
	var width := a.distance_to(b)
	var along := (b - a) / maxf(width, 1e-6)
	for k in steps.size():
		var step := steps[k]
		parts.segment(
			"%s_w%d" % [part, k],
			a + along * width * step.x,
			a + along * width * step.y,
			head - step.z,
			head,
			look
		)
		parts.segment(
			"%s_e%d" % [part, k],
			b - along * width * step.y,
			b - along * width * step.x,
			head - step.z,
			head,
			look
		)


# --------------------------------------------------------------------- bits


## A porch standing free (or against a wall on its local north side): a deck,
## posts front and back, a shed roof, rails with a gap for the steps.
static func porch(o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	var w: float = o["w"]
	var d: float = o["d"]
	var height: float = o["height"]
	var rails: bool = o["rails"]
	var roofed: bool = o["roof"]
	var base := KitPiece.num("plinth")
	var r := Rect2(0, 0, w, d)
	KitHouses.porch_on(parts, look, r, base, height, rails, roofed)
	if roofed:
		var trim: String = look.get("trim", "kit_trim")
		parts.post("porch_back0", Vector2(.15, .15), base, height - .15 * .25 - .12, trim)
		parts.post("porch_back1", Vector2(w - .15, .15), base, height - .15 * .25 - .12, trim)
		parts.roof_at(Vector2(w * .5, d * .5), height - d * .5 * .25, false, "shed")


## Stairs over the footprint rising toward the local north from z0 by rise:
## straight, L (up the west side, then east along the north) or switchback
## (up the west side, a landing, back down the east side to the top).
static func stairs(o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	var w: float = o["w"]
	var d: float = o["d"]
	var kind: String = o["kind"]
	var z0: float = o["z0"]
	var rise: float = o["rise"]
	var rails: bool = o["rails"]
	var floor_tile: String = look.get("floor", "porch")
	var step_look := {"tile": floor_tile, "under": floor_tile, "edge": look.get("trim", "wood")}
	var wall_look := {"tile": look.get("wall", "wood"), "thick": .1}
	var z1 := z0 + rise
	match kind:
		"l", "switchback":
			var sw := clampf(w * .5, .5, 1.4)
			var mid := z0 + rise * .5
			parts.stairs("flight1", Rect2(0, sw, sw, d - sw), z0, mid, "n", step_look)
			parts.block(
				"landing", Rect2(0, 0, sw if kind == "l" else w, sw), 0.0, mid, "wood", floor_tile
			)
			if kind == "l":
				parts.stairs("flight2", Rect2(sw, 0, w - sw, sw), mid, z1, "e", step_look)
				parts.floor_at("top", Vector2(w - .2, sw * .5), z1)
			else:
				parts.stairs("flight2", Rect2(w - sw, sw, sw, d - sw), mid, z1, "s", step_look)
				parts.floor_at("top", Vector2(w - sw * .5, d - .15), z1)
		_:
			parts.stairs("flight", Rect2(0, 0, w, d), z0, z1, "n", step_look)
			parts.floor_at("top", Vector2(w * .5, .15), z1)
			if rails:
				for side in 2:
					var x := .05 if side == 0 else w - .05
					parts.segment(
						"side%d" % side,
						Vector2(x, d),
						Vector2(x, 0),
						z0,
						z0 + .9,
						wall_look,
						z1 + .9
					)
	var foot_x := w * .5 if kind == "straight" else clampf(w * .5, .5, 1.4) * .5
	parts.floor_at("foot", Vector2(foot_x, d + .5), z0, false)


## A ramp rising toward the local north from z0 by rise (no steeper than 1).
static func ramp(o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	var w: float = o["w"]
	var d: float = o["d"]
	var z0: float = o["z0"]
	var asked: float = o["rise"]
	var rise := minf(asked, d)
	var floor_tile: String = look.get("floor", "porch")
	parts.ramp(
		"ramp",
		Rect2(0, 0, w, d),
		z0,
		z0 + rise,
		"n",
		{"tile": floor_tile, "under": floor_tile, "edge": look.get("trim", "wood")}
	)
	parts.floor_at("top", Vector2(w * .5, .2), z0 + rise)


## A ladder leaning on the face along its cell's local north edge, from z0
## up by rise to the floor beyond the face.
static func ladder(o: Dictionary, _look: Dictionary, parts: LevelParts) -> void:
	var z0: float = o["z0"]
	var rise: float = o["rise"]
	parts.ladder("ladder", Vector2(.5, 0), "n", z0, z0 + rise)


## A fence along the local x axis (its middle line, y .5), w long: rail (posts
## and two bars), wire (thin posts and three wires), picket (white boards to
## the waist) or stock (boards head high: cover). o.gate: a gap 1.6 wide that
## far along (0 none).
static func fence(o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	var w: float = o["w"]
	var kind: String = o["kind"]
	var gate: float = o["gate"]
	var trim: String = look.get("trim", "kit_trim")
	var spans: Array[Vector2] = [Vector2(0, w)]
	if gate > 0.0:
		var g0 := clampf(gate - .8, 0.0, w)
		var g1 := clampf(gate + .8, 0.0, w)
		spans = [Vector2(0, g0), Vector2(g1, w)]
	for k in spans.size():
		var a := Vector2(spans[k].x, .5)
		var b := Vector2(spans[k].y, .5)
		if b.x - a.x < .2:
			continue
		match kind:
			"wire":
				var posts := maxi(2, ceili((b.x - a.x) / 2.5) + 1)
				for i in posts:
					parts.post(
						"f%d_p%d" % [k, i], a.lerp(b, float(i) / (posts - 1)), 0.0, 1.15, "wood", .1
					)
				var wire := {"tile": "tin", "thick": .08, "sight": false, "shots": false}
				for i in 3:
					var z := .35 + i * .3
					parts.segment("f%d_wire%d" % [k, i], a, b, z, z + .06, wire)
			"picket":
				parts.segment(
					"f%d_boards" % k,
					a,
					b,
					0.0,
					.95,
					{"tile": trim, "thick": .08, "sight": false, "shots": false}
				)
				var posts := maxi(2, ceili((b.x - a.x) / 2.0) + 1)
				for i in posts:
					parts.post(
						"f%d_p%d" % [k, i], a.lerp(b, float(i) / (posts - 1)), 0.0, 1.1, trim, .14
					)
			"stock":
				parts.segment("f%d_boards" % k, a, b, 0.0, 1.6, {"tile": "stockyard", "thick": .14})
			_:
				rail_run(parts, "f%d" % k, a, b, 0.0, "wood")
	if gate > 0.0:
		var at := Vector2(clampf(gate, 0.0, w), .5)
		parts.doorway("gate", at, "s", 0.0, 1.6, 2.0)


## A bridge spanning the local y axis (d long, w wide), its deck `height` up:
## ramps (or steps, when steep) at both ends, rails along both sides; covered:
## walls with windows and a gable roof over the deck.
static func bridge(o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	var w: float = o["w"]
	var d: float = o["d"]
	var kind: String = o["kind"]
	var height: float = o["height"]
	var deck_look := {"tile": "porch", "under": "joists", "edge": "wood"}
	var end := 0.0
	if height > .25:
		end = clampf(height * 1.6, 1.0, d * .35)
		var steep := height / end > .95
		if steep:
			parts.stairs("ramp_n", Rect2(0, 0, w, end), 0.0, height, "s", deck_look)
			parts.stairs("ramp_s", Rect2(0, d - end, w, end), 0.0, height, "n", deck_look)
		else:
			parts.ramp("ramp_n", Rect2(0, 0, w, end), 0.0, height, "s", deck_look)
			parts.ramp("ramp_s", Rect2(0, d - end, w, end), 0.0, height, "n", deck_look)
	var top := maxf(height, .12)
	parts.slab("deck", Rect2(0, end, w, d - end * 2), top, .2, deck_look)
	parts.floor_at("deck", Vector2(w * .5, d * .5), top)
	if kind == "covered":
		var wl := {"tile": look.get("wall", "barn"), "thick": .16}
		var holes: Array[Dictionary] = []
		var k := 1.5
		while k < d - end * 2 - 1.0:
			holes.append({"at": k, "width": .9, "sill": top + .9, "head": top + 1.6})
			k += 2.0
		parts.wall("side_w", Vector2(.08, end), Vector2(.08, d - end), top, top + 2.4, wl, holes)
		parts.wall(
			"side_e", Vector2(w - .08, end), Vector2(w - .08, d - end), top, top + 2.4, wl, holes
		)
		KitRoofs.gable(
			parts,
			"roof",
			Rect2(0, end, w, d - end * 2),
			top + 2.4,
			.7,
			look,
			{"along": "v", "ends": false, "overhang": .25}
		)
	else:
		rail_run(parts, "rail_w", Vector2(.08, 0), Vector2(.08, d), top, "wood")
		rail_run(parts, "rail_e", Vector2(w - .08, 0), Vector2(w - .08, d), top, "wood")
	parts.floor_at("end", Vector2(w * .5, -.5), 0.0, false)


## A free wall along the local x axis (at y .5), o.storeys storeys of
## o.height, from o.z0: o.doors doorways on its ground storey and o.windows
## windows on every storey, spread evenly.
static func wall(o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	var w: float = o["w"]
	var height: float = o["height"]
	var z0: float = o["z0"]
	var doors: int = o["doors"]
	var windows: int = o["windows"]
	var storeys: int = o["storeys"]
	var holes: Array[Dictionary] = []
	var slots := doors + windows
	var door_slots: Array[int] = []
	for i in doors:
		door_slots.append(floori((i + .5) * slots / doors))
	for k in slots:
		var at := floorf(w * (k + .5) / slots) + .5
		for s in storeys:
			var base := z0 + s * height
			if door_slots.has(k) and s == 0:
				holes.append(
					{"at": at, "width": 1.0, "sill": base, "head": base + KitPiece.num("door_head")}
				)
				parts.doorway(
					"door%d" % k, Vector2(at, .5), "s", base, 1.0, KitPiece.num("door_head")
				)
			else:
				holes.append(
					{
						"at": at,
						"width": KitPiece.num("window_width"),
						"sill": base + .9,
						"head": base + 1.7
					}
				)
	var tile: String = look.get("wall", "barn")
	parts.wall(
		"wall",
		Vector2(0, .5),
		Vector2(w, .5),
		z0,
		z0 + height * storeys,
		{"tile": tile, "thick": KitPiece.num("wall")},
		holes
	)


## A wall along the local x axis with one arched way through its middle.
static func arch(o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	var w: float = o["w"]
	var height: float = o["height"]
	var asked: float = o["width"]
	var width := minf(asked, w - .4)
	var tile: String = look.get("wall", "brick")
	var wl := {"tile": tile, "thick": .3}
	var head := maxf(2.2, height - .5)
	var mid := w * .5
	var hole: Array[Dictionary] = [{"at": mid, "width": width, "sill": 0.0, "head": head}]
	parts.wall("wall", Vector2(0, .5), Vector2(w, .5), 0.0, height, wl, hole)
	var rise := minf(width * .45, head - 1.9)
	var steps: Array[Vector3] = [
		Vector3(0, .12, rise), Vector3(.12, .26, rise * .55), Vector3(.26, .38, rise * .2)
	]
	arch_head(
		parts, "arch", Vector2(mid - width * .5, .5), Vector2(mid + width * .5, .5), head, wl, steps
	)
	parts.doorway("way", Vector2(mid, .5), "s", 0.0, width, head - rise)


## A curved wall round the footprint's middle, from o.from to o.to degrees (0
## east, 90 south), with a doorway at its middle when o.door.
static func curved_wall(o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	var w: float = o["w"]
	var d: float = o["d"]
	var height: float = o["height"]
	var from: float = o["from"]
	var to: float = o["to"]
	var door: bool = o["door"]
	if to <= from:
		to += 360.0
	var tile: String = look.get("wall", "brick")
	var c := Vector2(w * .5, d * .5)
	var radius := minf(w, d) * .5 - .15
	var opts := {}
	if door:
		opts["doors"] = [(from + to) * .5]
	arc(
		parts,
		"curve",
		c,
		radius,
		from,
		to,
		0.0,
		height,
		{"tile": tile, "thick": KitPiece.num("wall")},
		opts
	)


static func chimney(o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	var w: float = o["w"]
	var d: float = o["d"]
	var height: float = o["height"]
	var tile: String = look.get("wall", "brick")
	parts.block("stack", Rect2(.1, .1, w - .2, d - .2), 0.0, height, tile, "cinder")


## A loading dock: a block o.height high along the local south of its
## footprint's east part, steps up its west end. Waist-high cover.
static func dock(o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	var w: float = o["w"]
	var d: float = o["d"]
	var height: float = o["height"]
	var side: String = look.get("found", "cinder")
	parts.block("dock", Rect2(1, 0, w - 1, d), 0.0, height, side, "concrete")
	parts.stairs(
		"steps",
		Rect2(0, 0, 1, d),
		0.0,
		height,
		"e",
		{"tile": "concrete", "under": side, "edge": side}
	)
	parts.floor_at("top", Vector2(w * .5 + .5, d * .5), height)


## A catwalk along the local x axis, o.height up on posts, rails both sides, a
## ladder at its west end.
static func catwalk(o: Dictionary, _look: Dictionary, parts: LevelParts) -> void:
	var w: float = o["w"]
	var d: float = o["d"]
	var height: float = o["height"]
	var with_ladder: bool = o["ladder"]
	var deck_look := {"tile": "steel_mesh", "under": "steel_mesh", "edge": "tin"}
	parts.slab("deck", Rect2(0, 0, w, d), height, .12, deck_look)
	var posts := maxi(2, ceili(w / 3.0) + 1)
	for k in posts:
		var x := lerpf(.1, w - .1, float(k) / (posts - 1))
		parts.post("leg%d_n" % k, Vector2(x, .1), 0.0, height - .12, "tin", .12)
		parts.post("leg%d_s" % k, Vector2(x, d - .1), 0.0, height - .12, "tin", .12)
	rail_run(parts, "rail_n", Vector2(0, .05), Vector2(w, .05), height, "tin")
	rail_run(parts, "rail_s", Vector2(0, d - .05), Vector2(w, d - .05), height, "tin")
	if with_ladder:
		parts.ladder("ladder", Vector2(0, d * .5), "e", 0.0, height, "tin")
	parts.floor_at("deck", Vector2(w * .5, d * .5), height, with_ladder)


## A hunting stand: four legs, a deck o.height up behind knee walls (cover,
## a gap for the ladder on the local south), a tin roof over it.
static func tower(o: Dictionary, look: Dictionary, parts: LevelParts) -> void:
	var w: float = o["w"]
	var d: float = o["d"]
	var height: float = o["height"]
	var roofed: bool = o["roof"]
	var wall_tile: String = look.get("wall", "wood")
	var floor_tile: String = look.get("floor", "porch")
	parts.slab(
		"deck",
		Rect2(0, 0, w, d),
		height,
		.15,
		{"tile": floor_tile, "under": floor_tile, "edge": "wood"}
	)
	var top := height + 2.1
	for k in 4:
		var at := Vector2(.12 if k % 2 == 0 else w - .12, .12 if k < 2 else d - .12)
		parts.post("leg%d" % k, at, 0.0, top if roofed else height + 1.0, "wood", .16)
	var knee := {"tile": wall_tile, "thick": .1}
	parts.segment("knee_n", Vector2(0, .05), Vector2(w, .05), height, height + .95, knee)
	parts.segment("knee_e", Vector2(w - .05, 0), Vector2(w - .05, d), height, height + .95, knee)
	parts.segment("knee_w", Vector2(.05, 0), Vector2(.05, d), height, height + .95, knee)
	var mid := w * .5
	parts.segment(
		"knee_s0", Vector2(0, d - .05), Vector2(mid - .5, d - .05), height, height + .95, knee
	)
	parts.segment(
		"knee_s1", Vector2(mid + .5, d - .05), Vector2(w, d - .05), height, height + .95, knee
	)
	parts.ladder("ladder", Vector2(mid, d), "n", 0.0, height)
	if roofed:
		var skin := KitRoofs._skin(look)
		parts.slab("roof", Rect2(-.15, -.15, w + .3, d + .3), top + .15, .1, skin, Vector2(0, -.1))
	parts.floor_at("deck", Vector2(mid, d * .5), height)
