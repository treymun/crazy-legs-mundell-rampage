## The big breaks in the chapters (features/set_pieces.gd plays them; their
## shapes and numbers are data/tuning/set_pieces.cfg): each chapter's plan
## calls its own here at the end of build(). A set piece goes in the level's
## "set_pieces" list (the builder's meta); what stands round it (hay on the
## floor and in bales, a propane tank at a fuel line's end) is the plan's own.
##
## Where they stand: never across the only way to anything the chapter
## needs (tools/set_piece_check.gd brings each down every way it may fall and
## walks the way to every station, key and exit again), and each falls only
## the ways its spec's "falls" allows (0 east, 1 south, 2 west, 3 north): away
## from a hedge, a wall or the map's edge.
extends RefCounted


## A pole barn or hay shed, `turn` quarter turns (its open front faces +y
## turned), hay on its floor.
static func barn(b, id: String, x: float, y: float, turn: int, o := {}) -> Dictionary:
	var spec := {"kind": "barn", "id": id, "x": x, "y": y, "turn": turn}
	spec.merge(o)
	_add(b, spec)
	return spec


static func tower(b, id: String, x: float, y: float, o := {}) -> Dictionary:
	var spec := {"kind": "tower", "id": id, "x": x, "y": y, "turn": 0}
	spec.merge(o)
	_add(b, spec)
	return spec


## A fuel line through `points` from the pumps at `pumps`.
static func fuel(b, id: String, points: Array, pumps: Array) -> Dictionary:
	var first: Array = points[0]
	var spec := {
		"kind": "fuel", "id": id, "x": first[0], "y": first[1], "points": points, "pumps": pumps
	}
	_add(b, spec)
	return spec


static func _add(b, spec: Dictionary) -> void:
	var list: Array = b.meta.get("set_pieces", [])
	list.append(spec)
	b.meta["set_pieces"] = list


## A shed's plank floor in a box (it burns: fire.cfg [floors] porch).
static func plank_floor(b, x0: int, y0: int, x1: int, y1: int) -> void:
	b.paint(x0, y0, x1, y1, "porch")


# ---------------------------------------------------------------- chapters


static func hickston(b) -> void:
	# The orchard's hay shed, where the south rows of trees were: open to the
	# lane, hay bales stacked in it, a propane tank by its back wall. Two of
	# its posts shot out (or a stick of dynamite among the bales) and the tin
	# comes down on whoever is in it. Off the way through (the orchard is a
	# side trip from the lane).
	barn(b, "orchard-shed", 18.5, 15.6, 2, {"w": 8.0, "d": 4.6, "falls": [0, 1, 2]})
	plank_floor(b, 15, 14, 21, 17)
	for spot: Array in [[15.6, 14.4], [16.5, 14.3], [17.4, 14.4], [21.4, 16.5], [19.2, 14.4]]:
		b.town("range_hay_bale", spot[0], spot[1])
	b.town("propane_tank", 20.5, 14.5, {"solid": .35})
	# Hickston's water tower, moved out of the creek's corner to stand over
	# the county road where Main Street meets it: it goes over north or along
	# the road (never into the hedge), and its water floods the junction and
	# runs up Main Street.
	tower(
		b, "town-tower", 60.5, 73.0, {"falls": [0, 2, 3], "sign": "tower_hickston", "sign_face": 0}
	)
	# The GAS-N-GUT's fuel line: from under the pumps along the island's south
	# edge, round the corner and up the side of the store to the drums and a
	# propane tank by the side door.
	fuel(
		b,
		"gas-line",
		[[19.8, 59.6], [31.6, 59.6], [31.6, 53.5], [32.3, 53.5]],
		[[20.6, 58.95], [24.0, 58.95], [27.4, 58.95]]
	)
	b.town("propane_tank", 32.3, 53.5, {"solid": .4})


static func fair(b) -> void:
	# The livestock show's hay shed out in the parking field's east end, off
	# the way in: stacked with hay for the show barn, a rack of propane for
	# the corn-dog fryers. It goes over along the field, never back into the
	# wall nor onto the parked cars.
	barn(b, "parking-shed", 112.0, 75.5, 2, {"w": 8.0, "d": 4.6, "falls": [0, 2]})
	plank_floor(b, 109, 74, 115, 77)
	for spot: Array in [[109.4, 74.0], [110.3, 74.0], [111.2, 74.1], [113.6, 74.0], [115.0, 76.6]]:
		b.town("range_hay_bale", spot[0], spot[1])
	b.town("propane_tank", 114.5, 74.5, {"solid": .35})


static func sawmill(b) -> void:
	# A lumber shed in the yard's open south-west, west of the walk in: tin
	# walls and roof on timber posts, pallets stacked under it. Its posts
	# shot or rammed out (the forklift), it comes down on whoever hides in it.
	barn(
		b,
		"lumber-shed",
		34.0,
		74.5,
		1,
		{"w": 9.0, "d": 5.0, "wall_tile": "mill_tin", "roof_tile": "mill_tin", "eave": 3.1}
	)
	plank_floor(b, 32, 71, 36, 78)
	for spot: Array in [[32.4, 71.4], [32.4, 76.6], [35.6, 70.9], [35.6, 77.1]]:
		b.town("pallet_stack", spot[0], spot[1])


static func speedway(b) -> void:
	# The truck stop's water tower between the store and the fuel island: it
	# goes over east along the lot (the trailer north, the canopy south and
	# the store west hold it in) and floods the lot to the grandstand gate.
	tower(b, "truckstop-tower", 24.5, 80.5, {"falls": [0]})
	# The fuel island's line: from under the pumps west along the lot to the
	# big tank by the store, gas cans stacked where it ends.
	fuel(
		b,
		"truckstop-line",
		[[30.0, 88.4], [17.0, 88.4], [17.0, 91.6], [7.2, 91.6]],
		[[20.5, 87.5], [24.5, 87.5], [28.5, 87.5]]
	)
	b.town("gas_cans", 7.6, 92.6)
