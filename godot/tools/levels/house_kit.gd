## SPIKE (pass 16 audit, maps-audit branch): whole buildings out of format-2
## geometry, to prove the plan's approach: a pitched roof walked on (two
## sloped decks meeting at a ridge, gable ends as raked walls), and a house
## of storeys with real floors, inside stairs and doorways and windows on
## every floor. Walls are geometry segments, not solid cells, so a body can
## stand on what is over them; the cells inside stay open ground (roof 0) and
## the roof's underside is the ceiling of the top floor.
##
##   const House := preload("res://tools/levels/house_kit.gd")
##   House.house(b, "farmhouse", 10, 4, 18, 10, {"storeys": 2})
extends RefCounted

const Geo := preload("res://tools/levels/geo_kit.gd")

## A storey's height floor to floor.
const STOREY := 2.4
## Walls' thickness (thick enough to draw both faces and the ends).
const WALL := .2
## A roof's thickness and default pitch (rise per unit run).
const ROOF_THICK := .15
const PITCH := .6


## A pitched (gable) roof over `rect` [x0, y0, x1, y1] (the wall lines), its
## underside at `eave` on the eave walls, rising at o.pitch to a ridge along
## `along` ("ew": the ridge runs east-west, eaves north and south; "ns" the
## other way). o.overhang past the eave walls (.3), o.rake past the gable
## walls (0: a ladder can lean on a gable), o.tile, o.under, o.edge, o.area.
## The gable walls (o.gables, true) are raked segments from `eave` up under
## the roof at o.wall_tile. Returns the ridge's height (the roof's top there).
static func gable_roof(b, id: String, rect: Array, eave: float, along: String, o := {}) -> float:
	var x0 := float(rect[0])
	var y0 := float(rect[1])
	var x1 := float(rect[2])
	var y1 := float(rect[3])
	var pitch := float(o.get("pitch", PITCH))
	var hang := float(o.get("overhang", .3))
	var rake := float(o.get("rake", 0.0))
	var thick := float(o.get("thick", ROOF_THICK))
	var opts := {
		"thick": thick,
		"tile": String(o.get("tile", "tin")),
		"under": String(o.get("under", "porch")),
		"edge": String(o.get("edge", o.get("tile", "tin"))),
		"area": int(o.get("area", 0)),
		"light": float(o.get("light", .85)),
	}
	var ns := along == "ns"
	# The half-span from an eave wall to the ridge, and the top's rise over it.
	var half := ((x1 - x0) if ns else (y1 - y0)) * .5
	var mid := ((x0 + x1) if ns else (y0 + y1)) * .5
	# The top at the eave wall line is eave + thick (the underside sits on it).
	var at_wall := eave + thick
	var ridge := at_wall + half * pitch
	var low := at_wall - hang * pitch
	var a := opts.duplicate()
	var c := opts.duplicate()
	if ns:
		a["gx"] = pitch
		Geo.slab(b, id + "_w", [x0 - hang, y0 - rake, mid, y1 + rake], low, a)
		c["gx"] = -pitch
		Geo.slab(b, id + "_e", [mid, y0 - rake, x1 + hang, y1 + rake], ridge, c)
	else:
		a["gy"] = pitch
		Geo.slab(b, id + "_n", [x0 - rake, y0 - hang, x1 + rake, mid], low, a)
		c["gy"] = -pitch
		Geo.slab(b, id + "_s", [x0 - rake, mid, x1 + rake, y1 + hang], ridge, c)
	if bool(o.get("gables", true)):
		var wall := {
			"thick": WALL,
			"tile": String(o.get("wall_tile", "barn")),
			"area": int(o.get("area", 0)),
		}
		# Each gable: two raked pieces from the eave walls up to the ridge, the
		# top under the roof's underside all the way.
		var inset := WALL * .5
		var under := ridge - thick
		for side in 2:
			var p := (x0 + inset if side == 0 else x1 - inset) if not ns else 0.0
			var q := (y0 + inset if side == 0 else y1 - inset) if ns else 0.0
			var ends: Array
			if ns:
				ends = [Vector2(x0, q), Vector2(mid, q), Vector2(x1, q)]
			else:
				ends = [Vector2(p, y0), Vector2(p, mid), Vector2(p, y1)]
			for k in 2:
				var s := {
					"id": "%s_gable%d_%d" % [id, side, k],
					"a": [Geo._r(ends[0].x), Geo._r(ends[0].y)],
					"b": [Geo._r(ends[1].x), Geo._r(ends[1].y)],
					"z0": Geo._r(eave),
					"z1": Geo._r(eave),
					"z1b": Geo._r(under),
					"thick": WALL,
					"tile": wall["tile"],
					"light": .85,
					"area": wall["area"],
				}
				if k == 1:
					s["a"] = [Geo._r(ends[2].x), Geo._r(ends[2].y)]
				b.geometry["segments"].append(s)
	return ridge


## A house of o.storeys (2) storeys over cells x0..x1-1, y0..y1-1 (at least
## 5 x 5): walls of o.wall on the outline, a door in the middle of the
## o.door side (s) on the ground floor, windows every o.windows (2) cells on
## every floor, a floor (deck) over each storey but the top one's stairwell,
## inside stairs up the west wall from the south, and a pitched roof (ridge
## along the longer side) walked on. Returns {ridge, eave, floors: [z...],
## door: Vector2 (the doorway's middle)}.
static func house(b, id: String, x0: int, y0: int, x1: int, y1: int, o := {}) -> Dictionary:
	var storeys := int(o.get("storeys", 2))
	var area := int(o.get("area", 0))
	var wall_tile := String(o.get("wall", "barn"))
	var every := int(o.get("windows", 2))
	b.room(
		x0, y0, x1 - 1, y1 - 1, String(o.get("floor", "porch")), area, {"roof": 0.0, "light": .8}
	)
	var eave := storeys * STOREY
	var inset := WALL * .5
	var w := float(x1 - x0)
	var d := float(y1 - y0)
	var corners: Array[Vector2] = [
		Vector2(x0, y0 + inset),
		Vector2(x1, y0 + inset),
		Vector2(x1 - inset, y0),
		Vector2(x1 - inset, y1),
		Vector2(x1, y1 - inset),
		Vector2(x0, y1 - inset),
		Vector2(x0 + inset, y1),
		Vector2(x0 + inset, y0),
	]
	var door_at := Vector2(x0 + floorf(w * .5) + .5, y1 - inset)
	for side in 4:
		var a: Vector2 = corners[side * 2]
		var bb: Vector2 = corners[side * 2 + 1]
		var length := a.distance_to(bb)
		var holes: Array = []
		for s in storeys:
			var floor_z := s * STOREY
			var k := 1
			while k < int(length) - 1:
				var at := k + .5
				var is_door := (
					side == 2 and s == 0 and absf(a.lerp(bb, at / length).x - door_at.x) < .01
				)
				if is_door:
					holes.append({"id": "door", "at": at, "width": 1.0})
				elif every > 0 and k % every == 1 and not (side == 3 and k == int(length) - 2):
					holes.append(
						{
							"id": "win%d_%d" % [s, k],
							"at": at,
							"width": .8,
							"sill": floor_z + .9,
							"head": floor_z + 1.7
						}
					)
				k += 1
		Geo.wall(
			b,
			"%s_wall%d" % [id, side],
			a,
			bb,
			0.0,
			eave,
			{"thick": WALL, "tile": wall_tile, "openings": holes, "area": area}
		)
	# Floors over each storey but the ground: the stairwell (the west strip,
	# x0 .. x0 + 1.4, south of a landing) left open on each.
	var floors: Array = [0.0]
	var inner := [x0 + WALL, y0 + WALL, x1 - WALL, y1 - WALL]
	var well := x0 + 1.4
	for s in range(1, storeys):
		var z := s * STOREY
		floors.append(z)
		var deck_opts := {"thick": .15, "tile": "porch", "under": "porch", "area": area}
		Geo.deck(b, "%s_floor%d" % [id, s], [well, inner[1], inner[2], inner[3]], z, deck_opts)
		Geo.deck(b, "%s_landing%d" % [id, s], [inner[0], inner[1], well, y0 + 1.2], z, deck_opts)
		Geo.stairs(
			b,
			"%s_stairs%d" % [id, s],
			[inner[0], y0 + 1.2, well, inner[3] - .8],
			z - STOREY,
			z,
			"n",
			{"tile": "porch", "area": area, "thick": .15 if s > 1 else -1.0}
		)
	var along := "ew" if w >= d else "ns"
	var ridge := gable_roof(
		b,
		id + "_roof",
		[x0, y0, x1, y1],
		eave,
		along,
		{"wall_tile": wall_tile, "area": area, "tile": String(o.get("roof", "tin"))}
	)
	return {"ridge": ridge, "eave": eave, "floors": floors, "door": door_at, "along": along}
