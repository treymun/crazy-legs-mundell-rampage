## Height in every chapter (the layouts after v3.1.0): ladders up roofs,
## stacks, lookouts, bins and catwalks, ledges to pull up onto and gaps to
## jump (climb_kit.gd builds them; src/climbing.gd climbs them; the hands take
## the ladders and drop off the edges). Each chapter's plan calls its own at
## the end of build(); the County Run maps built on a chapter get them too.
## Each stands clear of the ways through, on open ground or against a wall,
## never in the fair's shooting gallery or midway, the hub's shack, the
## speedway's track or the multiplayer maps.
extends RefCounted

const Climb := preload("res://tools/levels/climb_kit.gd")
const Geo := preload("res://tools/levels/geo_kit.gd")


static func hickston(b) -> void:
	# The salvage yard: crushed cars stacked up, a ladder against the west end
	# and a lower stack to pull up onto from the east; the yard's coot keeps
	# watch from the top.
	Climb.shed(
		b,
		"junk_stack",
		[23.6, 41.6, 25.6, 43.6],
		1.9,
		"w",
		{"tile": "tin", "edge": "junk_stack", "ladder": "wood", "area": _area(b, 24, 42)}
	)
	Climb.block(
		b,
		"junk_step",
		[25.6, 41.7, 26.6, 42.9],
		1.0,
		{"tile": "tin", "edge": "junk_stack", "area": _area(b, 24, 42)}
	)
	_lift(b, "junk-coot", 24.6, 42.6, 1.9)
	b.pickup("shells", 25.0, 43.1, 1.9)
	# The registry yard: a lookout on posts with a tin roof, walked under, a
	# ladder up its east side and a box of shells up top.
	Climb.tower(
		b,
		"registry_lookout",
		[92.0, 31.0, 94.0, 33.0],
		2.4,
		"e",
		{"roof": 1.7, "area": _area(b, 93, 32)}
	)
	b.pickup("bullets", 92.8, 31.8, 2.4)


static func fair(b) -> void:
	var freight := _area(b, 90, 30)
	# The freight lot's containers (fair_plan.gd makes them solid blocks): a
	# ladder up the north-west one, a plank laid across to the one south of
	# it, cartons stacked at that one's east end to climb by; the far pair
	# likewise, a ladder at the south and a plank between.
	Climb.ladder_on(
		b, "container_ladder", [82.0, 28.0, 88.0, 30.4], 0.0, 2.2, "n", .2, {"tile": "wood"}
	)
	Geo.deck(
		b,
		"container_plank",
		[84.1, 30.4, 84.9, 34.0],
		2.2,
		{"thick": .08, "tile": "porch", "under": "porch", "edge": "wood", "area": freight}
	)
	Climb.block(
		b,
		"carton_stack",
		[88.0, 34.5, 89.1, 35.7],
		1.1,
		{"tile": "crate_side", "edge": "crate_side", "area": freight}
	)
	Climb.ladder_on(
		b, "container_ladder_b", [96.0, 36.0, 104.0, 38.4], 0.0, 2.2, "s", .55, {"tile": "wood"}
	)
	Geo.deck(
		b,
		"container_plank_b",
		[98.1, 32.4, 98.9, 36.0],
		2.2,
		{"thick": .08, "tile": "porch", "under": "porch", "edge": "wood", "area": freight}
	)
	b.pickup("shells", 86.6, 29.2, 2.2)
	b.pickup("beer", 100.6, 31.2, 2.2)
	# The carny camp: a water tower's walk on four legs, roofed, its ladder
	# on the south leg-side.
	Climb.tower(
		b, "camp_tower", [38.0, 4.0, 40.0, 6.0], 2.6, "s", {"roof": 1.6, "area": _area(b, 39, 5)}
	)
	b.pickup("bullets", 38.7, 4.8, 2.6)


static func sawmill(b) -> void:
	var west := _area(b, 25, 35)
	# The west bank: the sawdust bin, a ladder up its west side and a rail
	# round its top; it looks out over the log pond.
	Climb.shed(
		b,
		"sawdust_bin",
		[24.0, 34.0, 26.0, 36.0],
		3.0,
		"w",
		{"tile": "tin", "edge": "mill_tin", "ladder": "wood", "rail": "nesw", "area": west}
	)
	b.pickup("shells", 25.4, 34.6, 3.0)
	# Lumber stacked to season in a row: a low one to pull up onto, then two
	# high ones a jump apart.
	var lumber := {"tile": "wood", "edge": "mill_log", "area": west}
	Climb.block(b, "lumber_low", [22.0, 51.0, 24.0, 53.0], 1.0, lumber)
	Climb.block(b, "lumber_high", [25.2, 51.0, 27.6, 53.0], 1.8, lumber)
	Climb.block(b, "lumber_far", [28.8, 51.0, 31.0, 53.0], 1.8, lumber)
	b.pickup("bullets", 30.0, 52.0, 1.8)
	# The delivery yard: the scaler's lookout over the trucks coming in.
	Climb.tower(
		b,
		"yard_lookout",
		[104.0, 72.0, 106.0, 74.0],
		2.4,
		"w",
		{"roof": 1.5, "area": _area(b, 105, 73)}
	)
	b.pickup("beer", 105.3, 72.7, 2.4)


static func quarry(b) -> void:
	var cut := _area(b, 38, 39)
	var ground := 0.48
	# The cut yard: limestone blocks stacked by the west fence, a low one to
	# pull up onto and a ladder up the high one.
	var stone := {"tile": "quarry_face", "edge": "quarry_face", "ladder": "wood", "area": cut}
	Climb.block(b, "stone_low", [37.0, 38.2, 38.8, 39.8], ground + 1.0, stone)
	stone["base"] = ground
	stone["along"] = .5
	Climb.shed(b, "stone_high", [38.8, 38.0, 41.4, 40.0], ground + 1.9, "s", stone)
	b.pickup("shells", 40.6, 39.0, ground + 1.9)
	# The lower cut: a drill crew's lookout over the flooded pit.
	Climb.tower(
		b,
		"pit_lookout",
		[96.5, 36.5, 98.5, 38.5],
		2.4,
		"s",
		{"roof": 1.5, "post": "quarry_iron", "area": _area(b, 97, 37)}
	)
	b.pickup("bullets", 97.2, 37.2, 2.4)


static func bayou(b) -> void:
	# Deer stands out in the shallows on cypress legs: a roofed blind up a
	# ladder, a look over the channel and the camp.
	var blind := {
		"roof": 1.4,
		"base": -.24,
		"post": "bayou_stilts",
		"tile": "bayou_planks",
		"edge": "bayou_planks",
		"ladder": "bayou_stilts",
	}
	blind["area"] = _area(b, 37, 31)
	Climb.tower(b, "deer_stand", [36.0, 30.0, 38.0, 32.0], 2.2, "s", blind)
	b.pickup("shells", 36.7, 30.7, 2.2)
	blind["area"] = _area(b, 34, 85)
	Climb.tower(b, "deer_stand_b", [33.6, 84.0, 35.6, 86.0], 2.2, "n", blind)
	b.pickup("bullets", 34.9, 85.3, 2.2)


static func speedway(b) -> void:
	# The haulers' lot: the rigs' box trailers are blocks walked on top
	# (speedway_plan.gd), a ladder up the end of two of them.
	var lot := _area(b, 10, 12)
	Climb.ladder_on(
		b, "rig_ladder", [4.1, 6.6, 16.9, 8.4], 0.0, 2.7, "w", .5, {"tile": "wood", "area": lot}
	)
	Climb.ladder_on(
		b,
		"rig_ladder_b",
		[4.1, 16.6, 16.9, 18.4],
		0.0,
		2.7,
		"s",
		.85,
		{"tile": "wood", "area": lot}
	)
	b.pickup("shells", 13.5, 7.5, 2.7)
	b.pickup("bullets", 6.0, 17.5, 2.7)


static func moonshine(b) -> void:
	# The tobacco barn's hayloft along its west wall over the bales, a ladder
	# up its east edge (moonshine_plan.gd).
	var barn := _area(b, 22, 76)
	(
		Climb
		. catwalk(
			b,
			"hayloft",
			[17.0, 69.0, 20.0, 84.0],
			1.9,
			"e",
			"e",
			.35,
			{
				"tile": "porch",
				"under": "joists",
				"edge": "barn",
				"rail": "wood",
				"ladder": "wood",
				"area": barn,
				"posts": [Vector2(20.0, 69.0), Vector2(20.0, 76.5), Vector2(20.0, 84.0)],
			}
		)
	)
	b.pickup("rifle_ammo", 19.0, 72.0, 1.9)
	b.pickup("moonshine", 18.5, 83.0, 1.9)
	# The deer camp's stand over the clearing.
	var blind := {
		"roof": 1.4,
		"post": "wood",
		"tile": "porch",
		"edge": "wood",
		"ladder": "wood",
		"area": _area(b, 75, 48),
	}
	Climb.tower(b, "deer_stand_m", [79.0, 50.0, 81.0, 52.0], 2.2, "w", blind)
	b.pickup("rifle_ammo", 80.3, 51.0, 2.2)
	# The fire lookout at the camp's west end, over the valley.
	var top := 1.92
	var lookout := {
		"roof": 1.4,
		"base": top,
		"post": "wood",
		"tile": "porch",
		"edge": "wood",
		"ladder": "wood",
		"area": _area(b, 61, 10),
	}
	Climb.tower(b, "fire_lookout", [59.6, 9.4, 62.4, 12.2], top + 2.8, "e", lookout)
	b.pickup("rifle_ammo", 60.6, 10.4, top + 2.8)
	b.pickup("dynamite", 61.4, 11.2, top + 2.8)


static func mothership(b) -> void:
	# The cargo hold: a grated walk along the north bulkhead, over the door
	# from the engine room, up a ladder at its west end.
	(
		Climb
		. catwalk(
			b,
			"cargo_walk",
			[86.0, 66.0, 96.6, 67.0],
			2.6,
			"se",
			"s",
			.08,
			{
				"tile": "ship_grate",
				"under": "ship_grate",
				"edge": "ship_edge",
				"rail": "ship_rib",
				"ladder": "ship_tin",
				"area": _area(b, 90, 70),
				"posts": [Vector2(96.6, 67.0), Vector2(91.0, 67.0)],
			}
		)
	)
	b.pickup("keg_ammo", 94.5, 66.5, 2.6)
	# The engine room: a catwalk along the vats, up a ladder at its west end.
	(
		Climb
		. catwalk(
			b,
			"engine_walk",
			[88.0, 42.0, 102.0, 43.0],
			2.8,
			"nsew",
			"w",
			.5,
			{
				"tile": "ship_grate",
				"under": "ship_grate",
				"edge": "ship_edge",
				"rail": "ship_rib",
				"ladder": "ship_tin",
				"area": _area(b, 95, 50),
				"posts":
				[
					Vector2(88.0, 42.0),
					Vector2(88.0, 43.0),
					Vector2(95.0, 42.0),
					Vector2(95.0, 43.0),
					Vector2(102.0, 42.0),
					Vector2(102.0, 43.0)
				],
			}
		)
	)
	b.pickup("rifle_ammo", 101.0, 42.5, 2.8)


## Lifts a placed enemy onto a floor `z` up (a roof, a stack), moving it to
## (x, y) there.
static func _lift(b, id: String, x: float, y: float, z: float) -> void:
	for e: Dictionary in b.enemies:
		if String(e["id"]) == id:
			e["x"] = snappedf(x, .01)
			e["y"] = snappedf(y, .01)
			e["z"] = z
			return
	assert(false, "no enemy called " + id)


static func _area(b, x: int, y: int) -> int:
	return int(b.area[b.at(x, y)])
