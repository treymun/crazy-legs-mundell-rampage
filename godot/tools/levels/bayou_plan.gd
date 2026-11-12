## Gator Bayou (chapter five, layout 1): a fish camp out past the county line
## at dusk, built on the water. Black water everywhere: shallow you wade
## (slowly), deep channels nobody but a gator crosses. The Big Channel splits
## the swamp in two, forking round the bridge tender's hammock and joining the
## king's lagoon in the east, and three bridges cross it: the west drawbridge
## (crank the boil yard generator), the cannery's hoist bridge (trip the ice
## plant breaker) and the swing bridge in the middle (down once both are).
##
## South of the channel: the county line landing (the start), the bait and
## tackle on its stilts, the crawfish boil on its hammock, stilt row (shacks
## at four heights joined by boardwalks you climb between), the flooded
## cannery and the fish camp cabins. North of it: the gator farm and its
## wrassling pit, the Mudhole juke joint on its pilings, the king's lagoon
## where the boss runs his armoured airboat, the airboat dock (spike the fuel:
## the king comes) and, hidden in the cypress, the king's own still.
##
## Built by tools/levels/build_level.gd -- bayou. The people and things in it
## are in bayou_cast.gd.
extends RefCounted

const Builder := preload("res://tools/levels/level_builder.gd")
const Cast := preload("res://tools/levels/bayou_cast.gd")
const W := 128
const H := 92
## Water stands this far under the boardwalks and banks: a step up out of it.
const WATER := -.24
## The Big Channel's reaches: in from the west, the fork round the hammock,
## out east to the lagoon.
const CHANNEL := [
	[1, 37, 44, 42],
	[41, 27, 46, 46],
	[45, 27, 80, 30],
	[45, 43, 80, 46],
	[79, 27, 84, 46],
	[83, 37, 126, 42]
]

var b: Builder
var d := {}
var walks: Array = []


func make() -> Builder:
	b = Builder.new("bayou", W, H, "bayou_cypress")
	b.wall_top(0, 0, W - 1, H - 1, 3.6)
	b.deep_floor = b.t("bayou_deep")
	b.riser_tiles = {
		"bayou_planks": "bayou_stilts",
		"bayou_mud": "bayou_bank",
		"bayou_marsh": "bayou_bank",
		"gravel": "bayou_bank",
		"concrete": "bayou_bank",
	}
	b.meta = {
		"title": "GATOR BAYOU",
		"heading": ["GATOR BAYOU", "PAST THE COUNTY LINE"],
		"intro": "LOWER THE BRIDGES: CRANK THE BOIL YARD GENERATOR, TRIP THE CANNERY BREAKER.",
		"ending": '"NO WAKE ZONE, MY FOOT."',
		"score": "bayou_score",
		"ambience": "bayou",
		"layout": 1,
		"sky": "bayou_sky",
		"control_name": "BRIDGES: BOIL YARD GENERATOR, CANNERY BREAKER",
		"extraction":
		{"x": 114.5, "y": 21.5, "label": "HOT-WIRE THE KING'S AIRBOAT", "shutdown": "fuel"},
		"return_gate": {"destination": "hub", "x": 64.0, "y": 90.4, "width": 3.5, "side": -1},
		"wave": ["king", "lagoon-gator-a", "lagoon-gator-b", "dock-chummer", "dock-billy"],
		"devices": [["jukebox", 68.4, 20.4]],
	}
	return b


func build(_b) -> Array:
	for pair in [
		["back", "BACKWATER", Color(.92, 1.0, .9)],
		["landing", "COUNTY LINE LANDING", Color(1.04, .98, .9)],
		["bait", "BAIT & TACKLE", Color(1.06, .96, .86)],
		["boil", "CRAWFISH BOIL", Color(1.08, .96, .84)],
		["stilt", "STILT ROW", Color(1.0, .98, .9)],
		["cabins", "FISH CAMP CABINS", Color(.98, .98, .94)],
		["cannery", "SWAMP KING CANNERY", Color(.92, 1.02, .98)],
		["channel", "BIG CHANNEL", Color(.86, .96, 1.0)],
		["hammock", "BRIDGE TENDER'S HAMMOCK", Color(.96, 1.02, .9)],
		["farm", "GATOR FARM", Color(1.02, 1.0, .88)],
		["pit", "WRASSLIN PIT", Color(1.08, .94, .84)],
		["juke", "THE MUDHOLE", Color(1.1, .9, .9)],
		["lagoon", "KING'S LAGOON", Color(.9, .96, 1.04)],
		["dock", "AIRBOAT DOCK", Color(1.04, .98, .9)],
		["still", "THE KING'S STILL", Color(1.08, .96, .84)],
	]:
		d[pair[0]] = b.district(String(pair[1]), pair[2])
	swamp()
	stilt_row()
	cabins()
	cannery()
	landing()
	boil_yard()
	bait_shop()
	hammock()
	gator_farm()
	juke_joint()
	lagoon()
	dock()
	still()
	backwater()
	channel()
	story()
	Cast.enemies(b)
	Cast.pickups(b)
	Cast.set_pieces(b)
	posts()
	return [64.5, 87.5, -PI / 2]


# ------------------------------------------------------------------ the kit


func water(x0: int, y0: int, x1: int, y1: int, district: String) -> void:
	b.yard(x0, y0, x1, y1, "bayou_water", d[district], {"ground": WATER, "light": .9})


func deep(x0: int, y0: int, x1: int, y1: int) -> void:
	b.paint(x0, y0, x1, y1, "bayou_deep")
	b.raise(x0, y0, x1, y1, WATER)


func land(x0: int, y0: int, x1: int, y1: int, district: String, floor_name := "bayou_mud") -> void:
	b.yard(x0, y0, x1, y1, floor_name, d[district], {"light": .92})


## A boardwalk: planks over the water at `top`, pilings on its corners (posts()).
func walk(x0: int, y0: int, x1: int, y1: int, district: String, top := 0.0) -> void:
	b.yard(x0, y0, x1, y1, "bayou_planks", d[district], {"ground": top, "light": .92})
	walks.append([x0, y0, x1, y1, top])


## A shack on stilts: walls of `wall` round a floor `ground` up, roofed above.
func shack(
	x0: int, y0: int, x1: int, y1: int, district: String, ground: float, wall: String, o := {}
) -> void:
	(
		b
		. building(
			x0,
			y0,
			x1,
			y1,
			d[district],
			{
				"wall": wall,
				"roof": ground + float(o.get("height", 2.3)),
				"floor": String(o.get("floor", "bayou_planks")),
				"ceiling": "joists",
				"light": float(o.get("light", .74)),
				"skin": String(o.get("skin", "bayou_shack")),
				"windows": int(o.get("windows", 3)),
				"lit": float(o.get("lit", .45)),
			}
		)
	)
	b.raise(x0 + 1, y0 + 1, x1 - 1, y1 - 1, ground)


func door(
	x: int, y: int, vertical: bool, from: String, ground: float, door_id: String, o := {}
) -> void:
	var opts := o.duplicate()
	opts["from"] = from
	opts["id"] = door_id
	if not opts.has("roof"):
		opts["roof"] = ground + Builder.DOOR_TOP
	b.door(x, y, vertical, opts)
	b.raise(x, y, x, y, ground)


## One of the modelled props stood at (x, y); `solid` gives it a base that
## blocks the way at the floor (a sliver over water, not a box in the air).
func stand(name: String, x: float, y: float, solid := 0.0, o := {}) -> void:
	if solid > 0.0:
		var px := floorf(x) + .5
		var py := floorf(y) + .5
		var g: float = b.ground[b.at(int(x), int(y))]
		b.fixture(
			px - solid, py - solid, px + solid, py + solid, g + .04, "bayou_bank", "bayou_mud", g
		)
		b.town(name, px, py, o)
	else:
		b.town(name, x, y, o)


## A box standing on the floor of a raised room (fixtures count from 0 up).
func box(
	x0: float, y0: float, x1: float, y1: float, high: float, side: String, cap: String
) -> void:
	var g: float = b.ground[b.at(int((x0 + x1) * .5), int((y0 + y1) * .5))]
	b.fixture(x0, y0, x1, y1, g + high, side, cap, g)


## A lantern on its post, its light on the boards round it.
func lantern(x: float, y: float, reach := 3.4) -> void:
	b.town("lantern_post", x, y)
	b.glow(x, y, reach, .26)


## A stand of reeds too thick to see through or wade.
func reeds(x0: int, y0: int, x1: int, y1: int) -> void:
	b.wall(x0, y0, x1, y1, "bayou_reeds", 1.5)


## A cypress grove too close set to pass, trees stood round its edge.
func grove(x0: int, y0: int, x1: int, y1: int, trees: Array) -> void:
	b.wall(x0, y0, x1, y1, "bayou_cypress", 3.4)
	for t: Array in trees:
		stand(String(t[0]), float(t[1]), float(t[2]), .3)


## Pilings at a boardwalk's corners where it meets the water, every few cells.
func posts() -> void:
	var door_cells := {}
	for dr: Dictionary in b.doors:
		door_cells[Vector2i(int(dr["x"]), int(dr["y"]))] = true
	var wet := [b.t("bayou_water"), b.t("bayou_deep")]
	var planks := b.t("bayou_planks")
	var done := {}
	for wk: Array in walks:
		var x0: int = wk[0]
		var y0: int = wk[1]
		var x1: int = wk[2]
		var y1: int = wk[3]
		var corners: Array = []
		for x in range(x0, x1 + 2, 3):
			corners.append(Vector2i(x, y0))
			corners.append(Vector2i(x, y1 + 1))
		for y in range(y0, y1 + 2, 3):
			corners.append(Vector2i(x0, y))
			corners.append(Vector2i(x1 + 1, y))
		for c: Vector2i in corners:
			if done.has(c):
				continue
			var has_wet := false
			var has_walk := false
			var clear := true
			var top := -9.0
			for k in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
				var cell: Vector2i = c + k
				if not b.inside(cell.x, cell.y) or int(b.solid[b.at(cell.x, cell.y)]) >= 0:
					clear = false
					break
				if door_cells.has(cell):
					clear = false
					break
				var f := int(b.floor_tile[b.at(cell.x, cell.y)])
				if f in wet:
					has_wet = true
				elif f == planks:
					has_walk = true
					top = maxf(top, float(b.ground[b.at(cell.x, cell.y)]))
			if not (clear and has_wet and has_walk):
				continue
			done[c] = true
			b.fixture(c.x - .05, c.y - .05, c.x + .05, c.y + .05, top + .9, "wood", "wood", WATER)


# ---------------------------------------------------------------- the swamp


func swamp() -> void:
	water(1, 1, 126, 90, "back")
	# The Big Channel: in from the west, forking round the hammock, out east.
	for r in CHANNEL:
		b.yard(r[0], r[1], r[2], r[3], "bayou_deep", d["channel"], {"ground": WATER, "light": .88})


## The channel again over whatever water a region laid across it (its
## bridges are planks and stay), and the reed beds along its banks.
func channel() -> void:
	var water_tile := b.t("bayou_water")
	for r in CHANNEL:
		for y in range(r[1], r[3] + 1):
			for x in range(r[0], r[2] + 1):
				var i := b.at(x, y)
				if int(b.solid[i]) < 0 and int(b.floor_tile[i]) == water_tile:
					b.floor_tile[i] = b.t("bayou_deep")
					b.area[i] = d["channel"]
	for r in [
		[2, 34, 6, 35], [32, 43, 37, 44], [70, 24, 72, 25], [86, 44, 90, 45], [116, 43, 121, 44]
	]:
		reeds(r[0], r[1], r[2], r[3])


func landing() -> void:
	# The county line landing: the end of the gravel, the boat ramp, the gate home.
	land(50, 79, 78, 90, "landing", "gravel")
	b.paint(62, 79, 66, 90, "tracks")
	b.yard(54, 76, 59, 78, "concrete", d["landing"], {"ground": -.12})
	b.arch(64.0, 90.4, 3.5, "route_hub")
	b.board("hub_road_stake", 66.2, 89.4, .97, {"plane": PI, "back": "hub_road_stake_back"})
	b.board("bayou_landing_sign", 58.5, 85.0, .8, {"z": 1.0, "plane": PI / 2})
	b.board("bayou_noswim_sign", 54.0, 79.2, .5, {"z": .9, "plane": 0.0})
	# A truck backed down with the boat still on, another one parked.
	b.car(56.0, 82.5, true, "trailer")
	stand("skiff", 56.5, 80.0, .45)
	b.car(72.5, 87.0, false)
	stand("marina_pump", 75.5, 81.5, .3)
	b.board("bayou_ice_sign", 70.0, 79.3, .5, {"z": 1.3, "plane": 0.0})
	b.fixture(68.6, 79.1, 71.4, 79.9, 1.2, "tin", "counter_top")
	stand("ice_chest", 72.5, 79.5, .3)
	b.react("vending", 52.6, 88.0, 1.5, {"id": "bayou-vending"})
	stand("outhouse", 52.5, 85.5, .4)
	b.board("bayou_arrow_landing", 65.5, 79.4, .4, {"z": 1.2, "plane": PI})
	lantern(62.0, 79.2)
	lantern(69.0, 84.0)
	b.streetlamp(60.0, 88.0)
	b.poles([Vector2(51.5, 89.5), Vector2(51.5, 80.5)])
	b.label("LANDING", 56, 86)


func bait_shop() -> void:
	# The bait and tackle on its stilts, the porch, the walk to the landing.
	water(14, 67, 43, 82, "bait")
	shack(21, 68, 33, 78, "bait", .24, "bayou_tin", {"windows": 4, "light": .8, "lit": .6})
	b.wall(33, 71, 33, 71, "bayou_bait_neon", 2.82)
	b.wall(33, 77, 33, 77, "bayou_bait_neon", 2.82)
	door(33, 74, true, "w", .24, "bait-front")
	door(27, 68, false, "s", .24, "bait-back")
	walk(34, 70, 36, 78, "bait", .24)
	walk(37, 74, 51, 75, "bait")
	walk(50, 76, 51, 78, "landing")
	walk(26, 62, 28, 67, "bait")
	b.board("bayou_bait_sign", 34.06, 74.0, .74, {"z": 1.92, "plane": -PI / 2})
	# Inside: the counter, the bait tank, the cooler, the cane poles, the shelves.
	box(28.2, 70.2, 29.0, 76.0, .95, "counter", "counter_top")
	stand("bait_tank", 25.5, 75.5, .45, {})
	stand("ice_chest", 31.5, 76.5, .3)
	stand("bait_cooler_rack", 31.5, 69.5, .3)
	box(22.1, 69.1, 26.0, 69.6, 1.8, "shelves", "counter_top")
	box(22.1, 72.4, 22.6, 74.6, 1.8, "shelves", "counter_top")
	b.react("cans", 28.6, 72.5, .3, {"z": .95, "id": "bait-counter-cans"})
	b.prop("lamp", 26.0, 72.5)
	b.prop("lamp", 30.5, 74.5)
	b.glow(27.0, 73.0, 4.0, .2)
	# The back room behind the shelves: what the king paid for in jugs.
	b.secret(
		21,
		71,
		true,
		[18, 70, 20, 73],
		{"from": "e", "id": "bait-back-room", "tile": "bayou_tin", "roof": 2.09}
	)
	b.room(
		18,
		70,
		20,
		73,
		"bayou_planks",
		d["bait"],
		{"roof": 2.5, "light": .55, "ground": .24, "skin": "bayou_tin"}
	)
	b.raise(21, 71, 21, 71, .24)
	b.wall(17, 69, 21, 69, "bayou_tin", 2.8)
	b.wall(17, 74, 21, 74, "bayou_tin", 2.8)
	b.wall(17, 70, 17, 73, "bayou_tin", 2.8)
	stand("jug_stack", 18.5, 72.5, .4)
	# Outside: traps stacked on the porch, the minnow buckets, a heron waiting.
	stand("crawfish_traps", 35.5, 77.5, .4)
	stand("heron", 40.5, 72.5)
	stand("cypress", 16.5, 64.5, .3)
	stand("cypress_knees", 18.5, 66.5)
	stand("cypress_b", 45.5, 70.5, .3)
	stand("cypress", 42.5, 79.5, .3)
	stand("cypress_knees", 44.5, 78.5)
	lantern(37.0, 73.95)
	b.label("BAIT", 24, 66)


func boil_yard() -> void:
	# The crawfish boil on its hammock: burners going, the tables, the generator.
	land(3, 44, 30, 66, "boil", "bayou_marsh")
	b.paint(8, 50, 26, 64, "bayou_mud")
	water(23, 44, 30, 48, "boil")
	grove(3, 56, 5, 62, [["cypress", 6.5, 57.5], ["cypress_b", 6.5, 61.5]])
	walk(31, 57, 46, 58, "boil")
	walk(15, 43, 15, 43, "boil")
	b.yard(15, 37, 15, 42, "bayou_planks", d["channel"], {"ground": 0.0, "light": .9})
	walks.append([15, 37, 15, 42, 0.0])
	b.controlled(15, 39, false, {"from": "s", "id": "west-drawbridge", "tile": "bayou_bridge"})
	b.board("bayou_bridge_sign", 13.5, 44.5, .5, {"z": .9, "plane": 0.0})
	# The generator under its lean-to: crank it and the west drawbridge comes down.
	b.wall(4, 45, 11, 45, "bayou_shack", 2.6)
	b.wall(4, 46, 4, 50, "bayou_shack", 2.6)
	b.wall(11, 46, 11, 50, "bayou_shack", 2.6)
	b.room(5, 46, 10, 50, "bayou_mud", d["boil"], {"roof": 2.3, "light": .8})
	stand("generator", 8.5, 47.5, .45)
	stand("propane_tank", 6.5, 46.5)
	b.board("bayou_arrow_farm", 13.0, 45.06, .4, {"z": 1.3, "plane": 0.0})
	# The boil itself: three burners, the long tables, the sacks, the shells.
	for p in [Vector2(12.5, 53.5), Vector2(17.5, 53.5), Vector2(22.5, 53.5)]:
		stand("boil_pot", p.x, p.y, .4)
		b.glow(p.x, p.y, 2.5, .2)
	# The long tables: the boards they stand on block the way at the floor.
	for y in [58.0, 61.0]:
		b.fixture(10.6, y - .3, 18.4, y + .3, .04, "bayou_bank", "bayou_mud")
		b.town("boil_table", 12.5, y)
		b.town("boil_table", 16.5, y)
	b.fixture(21.0, 57.7, 25.0, 58.3, .04, "bayou_bank", "bayou_mud")
	b.town("boil_table", 23.0, 58.0)
	for p in [Vector2(14.0, 56.0), Vector2(20.0, 60.5), Vector2(11.0, 63.5)]:
		b.mark("bayou_shells", p.x, p.y, p.x, .9, .9)
	stand("propane_tank", 26.5, 51.5, .45)
	stand("crawfish_traps", 27.5, 61.5, .4)
	stand("ice_chest", 9.5, 56.5, .3)
	stand("picnic_table", 24.5, 63.5, .45)
	b.board("bayou_boil_sign", 17.0, 50.0, .8, {"z": .9, "plane": 0.0})
	b.board("bayou_menu_sign", 25.4, 57.0, .7, {"z": .6, "plane": -PI / 2})
	b.poles([Vector2(9.5, 51.5), Vector2(28.5, 51.5), Vector2(28.5, 65.5)], 2.8)
	lantern(14.5, 64.5)
	lantern(21.5, 64.5)
	stand("cypress", 28.5, 45.5, .3)
	stand("cypress_knees", 26.5, 46.5)
	stand("dead_snag", 3.5, 47.5, .3)
	b.label("BOIL", 14, 47)


func stilt_row() -> void:
	# Stilt row: shacks on stilts at four heights, the boardwalks between them,
	# the water under everything. The spine runs from the landing to the
	# hammock bridge; the main walk from the boil yard to the cannery.
	water(44, 47, 84, 76, "stilt")
	walk(47, 57, 87, 58, "stilt")
	walk(63, 47, 64, 78, "stilt")
	walk(63, 43, 64, 46, "channel")
	# The net loft, two steps up.
	shack(46, 49, 53, 55, "stilt", .48, "bayou_shack", {"windows": 3})
	door(49, 55, false, "n", .48, "loft-door")
	walk(48, 56, 50, 56, "stilt", .24)
	stand("net_rack", 50.5, 52.5, .4)
	box(46.9, 49.9, 48.6, 51.4, .8, "crate_side", "counter_top")
	b.prop("lamp", 49.5, 52.0)
	# The skinning shed, one step up, its door on the walk.
	shack(56, 49, 61, 54, "stilt", .24, "bayou_tin", {"windows": 0})
	door(59, 54, false, "n", .24, "skinning-door")
	walk(58, 55, 60, 56, "stilt", .24)
	box(56.9, 50.2, 59.4, 51.0, .9, "steel_mesh", "steel_mesh")
	stand("gator_hide", 59.0, 50.06, 0.0, {"plane": 0.0})
	b.prop("lamp", 58.5, 52.0)
	# Maw-maw's place: the big house, porch and all, rocker on it.
	shack(68, 48, 77, 55, "stilt", .48, "bayou_shack", {"windows": 3, "lit": .7})
	door(72, 55, false, "n", .48, "mawmaw-door")
	walk(69, 56, 76, 56, "stilt", .24)
	stand("rocker", 74.5, 56.5)
	box(69.2, 49.2, 71.6, 50.4, .62, "wood", "counter_top")
	stand("porch_couch", 75.5, 49.5, .45)
	b.react("tv", 70.4, 49.8, .75, {"z": .62, "id": "mawmaw-tv"})
	b.prop("lamp", 72.5, 51.5)
	# The boat shop off the walk, outboards waiting on their horses.
	shack(47, 61, 55, 68, "stilt", .24, "bayou_tin", {"windows": 4})
	door(51, 61, false, "s", .24, "boatshop-door")
	walk(50, 59, 52, 60, "stilt")
	stand("outboard_stand", 49.5, 64.5, .4)
	stand("outboard_stand", 53.5, 66.5, .4)
	box(48.2, 66.4, 51.0, 67.2, .9, "wood", "counter_top")
	b.prop("lamp", 51.5, 64.5)
	# The preacher's shack, up high: the catwalk climbs to it a step at a time.
	shack(68, 62, 75, 68, "stilt", .72, "bayou_shack", {"windows": 3, "lit": .8})
	door(68, 65, true, "e", .72, "preacher-door")
	walk(65, 65, 65, 65, "stilt", .24)
	walk(66, 65, 66, 65, "stilt", .48)
	walk(67, 65, 67, 65, "stilt", .72)
	box(73.4, 63.2, 74.6, 64.6, .9, "wood", "counter_top")
	b.prop("lamp", 71.5, 65.5)
	# The outhouse at the end of its own pier, as it should be.
	walk(76, 62, 80, 62, "stilt")
	walk(80, 59, 80, 61, "stilt")
	stand("outhouse", 80.5, 63.5)
	walk(80, 63, 80, 63, "stilt")
	# The dry dock: a skiff upturned, a pirogue, a cypress over it all.
	walk(56, 70, 62, 72, "stilt")
	stand("pirogue", 58.5, 71.5, .3)
	stand("crawfish_traps", 61.5, 70.5, .35)
	stand("cypress", 46.5, 74.5, .3)
	stand("cypress_knees", 48.5, 73.5)
	stand("cypress_b", 81.5, 73.5, .3)
	stand("cypress", 82.5, 50.5, .3)
	stand("cypress_knees", 80.5, 51.5)
	stand("heron", 58.5, 66.5)
	b.mark("bayou_lilies", 66.0, 72.0, .4, 1.2, 1.2)
	b.mark("bayou_lilies", 55.0, 58.9, 1.2, 1.0, 1.0)
	b.mark("bayou_duckweed", 76.0, 70.0, 0.0, 2.0, 2.0)
	for p in [
		Vector2(55.5, 56.95),
		Vector2(70.5, 59.05),
		Vector2(62.95, 66.5),
		Vector2(65.05, 49.5),
		Vector2(80.5, 56.95)
	]:
		lantern(p.x, p.y)
	b.label("STILT ROW", 66, 70)


func cabins() -> void:
	# The fish camp cabins to rent, the walk past their doors, the boathouse.
	water(85, 68, 126, 90, "cabins")
	walk(79, 79, 87, 80, "cabins")
	walk(87, 78, 111, 79, "cabins")
	walk(94, 68, 95, 77, "cabins")
	for x in [88, 97, 105]:
		shack(x, 72, x + 5, 77, "cabins", .24, "bayou_shack", {"windows": 3, "lit": .5})
		door(x + 2, 77, false, "n", .24, "cabin-%d" % x)
		b.prop("lamp", x + 2.5, 74.5)
	stand("porch_couch", 89.5, 74.5, .45)
	stand("ice_chest", 99.5, 74.5, .3)
	box(105.2, 73.2, 107.0, 74.0, .62, "wood", "counter_top")
	b.board("bayou_cabins_sign", 86.5, 79.5, .7, {"z": 1.2, "plane": PI / 2})
	# The boathouse over the water, a skiff in its slip, a pier in to it.
	b.wall(98, 83, 98, 89, "bayou_shack", 2.9)
	b.wall(108, 83, 108, 89, "bayou_shack", 2.9)
	b.wall(99, 89, 107, 89, "bayou_shack", 2.9)
	b.room(
		99, 83, 107, 88, "bayou_water", d["cabins"], {"roof": 2.5, "light": .62, "ground": WATER}
	)
	walk(102, 80, 103, 82, "cabins")
	b.paint(102, 83, 103, 86, "bayou_planks")
	b.raise(102, 83, 103, 86, 0.0)
	walks.append([102, 83, 103, 86, 0.0])
	stand("skiff", 105.5, 85.5, .45)
	stand("outboard_stand", 100.5, 87.5, .35)
	b.prop("lamp", 103.0, 85.0)
	# The fish cleaning table at the end of the walk, the gulls' leavings.
	box(109.2, 78.2, 110.8, 78.9, .9, "steel_mesh", "steel_mesh")
	stand("crawfish_traps", 111.5, 78.5, .35)
	stand("cypress", 114.5, 82.5, .3)
	stand("cypress_knees", 116.5, 81.5)
	stand("dead_snag", 121.5, 87.5, .3)
	stand("cypress_b", 89.5, 86.5, .3)
	for p in [Vector2(92.0, 79.95), Vector2(101.0, 79.95), Vector2(95.95, 70.5)]:
		lantern(p.x, p.y)
	b.label("CABINS", 99, 70)


func cannery() -> void:
	# The Swamp King Canning Co.: block walls on the bank, the floor inside
	# flooded to the shins, catwalks round and across it, the ice plant at
	# the back. Its north door gives on the dock and the hoist bridge.
	shack(
		88,
		47,
		121,
		67,
		"cannery",
		0.0,
		"bayou_cannery",
		{
			"height": 3.4,
			"floor": "concrete",
			"skin": "bayou_cannery",
			"windows": 4,
			"lit": .3,
			"light": .72
		}
	)
	b.paint(89, 48, 120, 66, "bayou_water")
	b.raise(89, 48, 120, 66, WATER)
	for r in [
		[89, 48, 120, 49],
		[89, 50, 90, 66],
		[91, 65, 111, 66],
		[91, 53, 120, 54],
		[104, 50, 105, 64],
		[106, 61, 111, 62],
	]:
		b.paint(r[0], r[1], r[2], r[3], "bayou_planks")
		b.raise(r[0], r[1], r[2], r[3], 0.0)
	door(88, 57, true, "e", 0.0, "cannery-west", {"opened": true})
	b.paint(88, 57, 90, 58, "bayou_planks")
	b.raise(89, 57, 90, 58, 0.0)
	door(104, 47, false, "s", 0.0, "cannery-north")
	door(95, 67, false, "n", 0.0, "cannery-south", {"opened": true})
	b.board("bayou_cannery_sign", 102.0, 68.06, .8, {"z": 2.0, "plane": 0.0})
	b.board("bayou_king_sign", 87.94, 54.0, .6, {"z": 1.4, "plane": PI / 2})
	# The ice plant room: compressors, ice in blocks, the breaker on the wall.
	b.wall(112, 58, 120, 58, "bayou_cannery", 3.0)
	b.wall(112, 59, 112, 66, "bayou_cannery", 3.0)
	b.room(
		113,
		59,
		120,
		66,
		"concrete",
		d["cannery"],
		{"roof": 3.0, "light": .7, "skin": "bayou_cannery"}
	)
	door(112, 62, true, "e", 0.0, "ice-room")
	b.paint(111, 61, 111, 62, "bayou_planks")
	for c in [[114.2, 63.6, 115.8, 65.8], [116.4, 63.6, 118.0, 65.8]]:
		b.fixture(c[0], c[1], c[2], c[3], 1.3, "steel_mesh", "steel_mesh")
	for c in [[119.1, 60.2, 120.8, 61.8], [119.1, 64.2, 120.8, 65.8]]:
		b.fixture(c[0], c[1], c[2], c[3], .9, "glazing", "glazing")
	b.board("bayou_ice_sign", 115.0, 59.12, .5, {"z": 1.6, "plane": 0.0})
	b.prop("lamp", 116.5, 62.0)
	b.glow(116.5, 62.0, 3.5, .2)
	# On the flooded floor: the line of boil kettles, sorting tables, the
	# crates that slosh, the conveyor down the middle.
	for x in [94.5, 99.5]:
		stand("boil_pot", x, 59.5, .4)
	b.fixture(92.0, 61.6, 102.0, 62.4, .9, "steel_mesh", "steel_mesh", WATER)
	for p in [Vector2(108.5, 51.5), Vector2(112.5, 51.5), Vector2(116.5, 51.5)]:
		b.fixture(p.x - .9, p.y - .45, p.x + .9, p.y + .45, .82, "wood", "counter_top", WATER)
	for p in [
		Vector2(93.5, 51.5),
		Vector2(96.5, 51.5),
		Vector2(99.5, 51.5),
		Vector2(108.5, 57.5),
		Vector2(115.5, 56.5)
	]:
		box(p.x - .36, p.y - .36, p.x + .36, p.y + .36, .9, "crate_side", "counter_top")
	stand("jug_stack", 101.5, 56.5, .4)
	stand("jug_stack", 117.5, 56.5, .4)
	stand("crawfish_traps", 92.5, 56.5, .35)
	for p in [
		Vector2(96.0, 50.0),
		Vector2(110.0, 50.0),
		Vector2(96.0, 63.0),
		Vector2(116.0, 50.0),
		Vector2(108.0, 63.0)
	]:
		b.prop("lamp", p.x, p.y)
		b.glow(p.x, p.y, 3.0, .18)
	# The dock on the channel and the hoist bridge over it.
	walk(98, 43, 110, 46, "cannery")
	b.yard(104, 37, 104, 42, "bayou_planks", d["channel"], {"ground": 0.0, "light": .9})
	walks.append([104, 37, 104, 42, 0.0])
	b.controlled(104, 39, false, {"from": "s", "id": "hoist-bridge", "tile": "bayou_bridge"})
	stand("forklift", 100.5, 44.5, .45)
	stand("crawfish_traps", 108.5, 44.5, .35)
	b.board("bayou_arrow_dock", 106.0, 46.94, .4, {"z": 1.3, "plane": PI})
	lantern(102.0, 46.95)
	b.label("CANNERY", 98, 64)


func hammock() -> void:
	# The bridge tender's hammock between the channel's forks: his shack, the
	# swing bridge's motor, the old family plot, gators on the banks.
	land(47, 31, 78, 42, "hammock", "bayou_marsh")
	b.paint(60, 31, 63, 42, "bayou_mud")
	grove(48, 32, 50, 34, [["cypress", 51.5, 33.5], ["cypress_b", 49.5, 35.5]])
	grove(74, 38, 77, 41, [["cypress", 73.5, 37.5], ["dead_snag", 78.5, 37.5]])
	shack(57, 33, 65, 38, "hammock", 0.0, "bayou_shack", {"windows": 3, "lit": .6})
	door(61, 33, false, "s", 0.0, "tender-north")
	door(63, 38, false, "n", 0.0, "tender-south")
	b.board("bayou_bridge_sign", 64.0, 32.94, .5, {"z": 1.1, "plane": PI})
	b.prop("lamp", 61.5, 35.5)
	box(62.2, 34.1, 64.6, 34.8, .95, "steel_mesh", "steel_mesh")
	stand("cable_spool", 63.5, 36.5, .4)
	# His cache behind a false wall: shells and a jug.
	b.wall(59, 34, 59, 37, "bayou_shack", 2.6)
	b.secret(
		59, 36, true, [58, 34, 58, 37], {"from": "w", "id": "tender-cache", "tile": "bayou_shack"}
	)
	b.room(
		58,
		34,
		58,
		37,
		"bayou_planks",
		d["hammock"],
		{"roof": 2.3, "light": .5, "skin": "bayou_shack"}
	)
	# The swing bridge to the north bank, down only once both circuits are live.
	b.yard(61, 27, 61, 30, "bayou_planks", d["channel"], {"ground": 0.0, "light": .9})
	walks.append([61, 27, 61, 30, 0.0])
	b.controlled(61, 28, false, {"from": "s", "id": "swing-bridge", "tile": "bayou_bridge"})
	b.access_doors["61,28"] = ["generator", "breaker"]
	# The family plot on its mound, a skiff hauled out, a heron.
	for p in [Vector2(69.5, 33.5), Vector2(71.5, 33.5), Vector2(70.5, 35.5)]:
		stand(["tombstone_a", "tombstone_b", "tombstone_c"][int(p.x + p.y) % 3], p.x, p.y)
	stand("skiff", 53.5, 40.5, .45)
	stand("heron", 76.5, 32.5)
	stand("cypress_b", 67.5, 41.5, .3)
	stand("cypress_knees", 55.5, 41.5)
	lantern(62.05, 31.5)
	lantern(62.95, 40.5)
	b.label("HAMMOCK", 66, 37)


func gator_farm() -> void:
	# The gator farm: the pens (their walls broke down in places), the
	# wrassling pit with its bleachers, the office, the hide shed.
	land(2, 2, 28, 36, "farm")
	land(29, 2, 37, 27, "farm")
	b.paint(13, 28, 17, 36, "tracks")
	# Pens: low block walls round a pool, gaps where the gators got out.
	for pen in [[3, 12, 11, 20], [3, 23, 11, 31], [15, 16, 22, 24]]:
		var x0: int = pen[0]
		var y0: int = pen[1]
		var x1: int = pen[2]
		var y1: int = pen[3]
		b.yard(x0 + 1, y0 + 1, x1 - 1, y1 - 1, "bayou_water", d["farm"], {"ground": WATER})
		for x in range(x0, x1 + 1):
			if (x + y0) % 4 != 1:
				b.fixture(x, y0 + .3, x + 1, y0 + .7, 1.0, "bayou_pen", "concrete")
			if (x + y1) % 5 != 2:
				b.fixture(x, y1 + .3, x + 1, y1 + .7, 1.0, "bayou_pen", "concrete")
		for y in range(y0 + 1, y1):
			if (y + x0) % 5 != 3:
				b.fixture(x0 + .3, y, x0 + .7, y + 1, 1.0, "bayou_pen", "concrete")
			if (y + x1) % 4 != 0:
				b.fixture(x1 + .3, y, x1 + .7, y + 1, 1.0, "bayou_pen", "concrete")
	b.board("bayou_nofeed_sign", 12.0, 21.5, .55, {"z": .9, "plane": PI / 2})
	# The wrassling pit: sunk in the mud, a ramp down, bleachers round it.
	b.yard(24, 7, 31, 14, "bayou_mud", d["pit"], {"ground": -.48})
	b.yard(27, 15, 28, 15, "bayou_mud", d["pit"], {"ground": -.24})
	for k in 3:
		b.fixture(23.0, 4.0 + k * .9, 32.0, 4.9 + k * .9, 1.2 - k * .3, "bleachers", "bleachers")
	b.fixture(32.2, 7.0, 33.0, 14.0, .6, "bleachers", "bleachers")
	b.fixture(33.1, 7.0, 33.9, 14.0, .9, "bleachers", "bleachers")
	b.board("bayou_pit_sign", 21.5, 9.0, .6, {"z": .8, "plane": PI / 2})
	stand("tire_stack", 22.5, 15.5, .3)
	# The office: a shack with the ledger, the gate's switch, the till.
	shack(3, 3, 10, 9, "farm", 0.0, "bayou_shack", {"windows": 3, "lit": .6})
	door(10, 6, true, "w", 0.0, "farm-office")
	box(4.2, 7.2, 7.0, 8.0, .82, "wood", "counter_top")
	b.prop("lamp", 6.5, 5.5)
	b.react("tv", 5.5, 4.6, .75, {"id": "farm-tv"})
	# The hide shed: hides tacked up drying, the skinning table.
	shack(29, 20, 36, 26, "farm", 0.0, "bayou_tin", {"windows": 0})
	door(32, 26, false, "n", 0.0, "hide-shed")
	stand("gator_hide", 32.5, 21.06, 0.0, {"plane": 0.0})
	stand("gator_hide", 30.06, 23.5, 0.0, {"plane": -PI / 2})
	box(33.4, 22.2, 35.6, 23.0, .9, "steel_mesh", "steel_mesh")
	b.prop("lamp", 32.5, 23.5)
	# The way in from the drawbridge: the sign, the big fiberglass gator.
	b.board("bayou_gator_sign", 15.5, 33.0, 1.0, {"z": 1.1, "plane": 0.0})
	stand("giant_gator", 21.5, 33.5, .45)
	stand("chicken_coop", 9.5, 34.5, .45)
	stand("cypress", 3.5, 35.5, .3)
	stand("cypress_b", 26.5, 2.5, .3)
	stand("dead_snag", 36.5, 3.5, .3)
	stand("propane_tank", 25.5, 25.5, .45)
	walk(38, 13, 44, 14, "farm")
	b.board("bayou_arrow_juke", 36.5, 12.5, .4, {"z": 1.2, "plane": PI / 2})
	for p in [Vector2(13.5, 26.5), Vector2(27.5, 18.5), Vector2(12.5, 4.5), Vector2(34.5, 15.5)]:
		lantern(p.x, p.y)
	b.streetlamp(18.0, 30.0)
	b.label("GATOR FARM", 13, 22)
	b.label("PIT", 26, 10)


func juke_joint() -> void:
	# The Mudhole: a juke joint on pilings, its deck all round, the marquee,
	# the bar, the stage, the pool table, the jukebox, the king's back room.
	water(38, 2, 72, 26, "juke")
	walk(46, 4, 72, 24, "juke", .48)
	shack(
		48,
		6,
		70,
		22,
		"juke",
		.48,
		"bayou_juke",
		{"height": 2.8, "skin": "bayou_juke", "windows": 0, "light": .66}
	)
	# Blade signs down the front corners, the name over the door.
	b.wall(48, 22, 48, 22, "bayou_juke_marquee", 3.56)
	b.wall(70, 22, 70, 22, "bayou_juke_marquee", 3.56)
	b.board("bayou_mudhole_sign", 59.5, 23.04, .74, {"z": 1.95, "plane": 0.0, "glow": true})
	door(59, 22, false, "n", .48, "juke-front")
	door(48, 14, true, "e", .48, "juke-west")
	door(70, 14, true, "w", .48, "juke-east")
	walk(58, 25, 60, 25, "juke", .24)
	walk(57, 26, 63, 26, "juke")
	walk(45, 13, 45, 14, "juke", .24)
	walk(73, 13, 73, 14, "juke", .24)
	b.board("bayou_juke_sign", 53.5, 23.04, .62, {"z": .7, "plane": 0.0})
	b.board("bayou_juke_sign", 65.5, 23.04, .62, {"z": .7, "plane": 0.0})
	# The bar along the north wall, bottles behind it.
	box(51.0, 8.2, 64.0, 8.9, 1.0, "counter", "counter_top")
	box(51.0, 7.05, 64.0, 7.5, 1.9, "shelves", "counter_top")
	b.react("bottles", 56.0, 8.5, .42, {"z": 1.0, "id": "juke-bar-bottles"})
	b.react("bottles", 61.0, 8.5, .42, {"z": 1.0, "id": "juke-bar-bottles-b"})
	# The stage in the corner, a step up; the pool table; the tables.
	b.raise(49, 16, 54, 21, .72)
	b.paint(49, 16, 54, 21, "porch")
	stand("rocker", 51.5, 18.5)
	b.crate_stack(49.6, 20.6, .5 + .72)
	b.crate_stack(53.5, 20.6, .5 + .72)
	box(59.6, 15.6, 62.4, 17.0, .82, "counter", "grass")
	for p in [Vector2(57.0, 12.0), Vector2(62.0, 12.0), Vector2(66.5, 16.0)]:
		box(p.x - .5, p.y - .5, p.x + .5, p.y + .5, .7, "wood", "counter_top")
	b.react("jukebox", 68.4, 20.4, 1.4, {"id": "juke-jukebox"})
	b.react("cancan", 64.5, 19.5, .4, {"id": "juke-can"})
	for p in [
		Vector2(53.0, 11.0),
		Vector2(60.0, 13.0),
		Vector2(66.0, 11.0),
		Vector2(56.0, 18.0),
		Vector2(64.0, 18.5)
	]:
		b.prop("lamp", p.x, p.y)
		b.glow(p.x, p.y, 3.0, .22)
	# The king's poker room behind the bar, past a panel that slides.
	b.wall(66, 7, 66, 11, "bayou_juke", 3.56)
	b.wall(67, 11, 69, 11, "bayou_juke", 3.56)
	b.secret(
		66,
		9,
		true,
		[67, 7, 69, 10],
		{"from": "e", "id": "poker-room", "tile": "bayou_juke", "roof": 2.33}
	)
	b.room(
		67,
		7,
		69,
		10,
		"porch",
		d["juke"],
		{"roof": 3.28, "light": .5, "ground": .48, "skin": "bayou_juke"}
	)
	b.raise(66, 9, 66, 9, .48)
	box(67.4, 7.8, 68.6, 8.8, .7, "counter", "grass")
	b.prop("lamp", 68.0, 9.0)
	# Out on the deck: the couch, the cooler, a skiff tied under it.
	stand("porch_couch", 66.5, 23.5)
	stand("ice_chest", 47.5, 22.5)
	stand("cypress", 40.5, 4.5, .3)
	stand("cypress_knees", 42.5, 6.5)
	stand("cypress_b", 41.5, 22.5, .3)
	stand("dead_snag", 70.5, 2.5, .3)
	lantern(60.05, 26.95)
	b.streetlamp(47.0, 5.0)
	b.streetlamp(71.0, 23.0)
	b.label("MUDHOLE", 52, 3)


func lagoon() -> void:
	# The king's lagoon: deep in the middle, a feed platform out in it, the
	# boardwalks to the juke joint and the dock across it. The boss's water.
	water(73, 2, 105, 26, "lagoon")
	water(85, 27, 105, 36, "lagoon")
	for y in range(6, 30):
		for x in range(84, 106):
			var dx := (x + .5 - 95.0) / 10.0
			var dy := (y + .5 - 18.0) / 11.5
			if dx * dx + dy * dy <= 1.0:
				b.paint(x, y, x, y, "bayou_deep")
	b.yard(88, 29, 96, 36, "bayou_deep", d["lagoon"], {"ground": WATER, "light": .88})
	walk(74, 13, 86, 14, "lagoon")
	walk(87, 11, 92, 16, "lagoon")
	walk(93, 13, 107, 14, "lagoon")
	walk(98, 24, 107, 25, "lagoon")
	# The feed platform: the chute the king tips chum down, a sign for tourists.
	box(89.0, 11.2, 90.6, 12.2, 1.1, "steel_mesh", "steel_mesh")
	stand("crawfish_traps", 91.5, 15.5, .35)
	b.board("bayou_nofeed_sign", 87.2, 15.0, .5, {"z": .9, "plane": PI / 2})
	b.mark("bayou_slick", 96.0, 20.0, 0.0, 2.6, 2.6)
	b.mark("bayou_duckweed", 80.0, 22.0, 1.0, 2.4, 2.4)
	b.mark("bayou_lilies", 84.0, 8.0, 0.0, 1.4, 1.4)
	reeds(75, 20, 79, 21)
	reeds(81, 3, 84, 4)
	stand("cypress", 76.5, 17.5, .3)
	stand("cypress_knees", 78.5, 16.5)
	stand("cypress_b", 82.5, 27.5, .3)
	stand("dead_snag", 85.5, 33.5, .3)
	stand("airboat", 102.5, 10.5)
	stand("airboat", 101.5, 27.5)
	lantern(87.05, 11.05, 3.8)
	b.label("LAGOON", 80, 10)


func dock() -> void:
	# The airboat dock: planks on the east bank, the fuel pump at its edge,
	# the king's boathouse with his own airboat in it, the way down to the
	# hoist bridge.
	b.yard(106, 12, 126, 36, "bayou_planks", d["dock"], {"light": .92})
	walk(97, 31, 105, 36, "dock")
	shack(
		112,
		15,
		124,
		25,
		"dock",
		0.0,
		"bayou_tin",
		{"height": 3.0, "windows": 4, "lit": .5, "light": .7}
	)
	b.paint(115, 16, 121, 24, "bayou_water")
	b.raise(115, 16, 121, 24, WATER)
	door(112, 21, true, "e", 0.0, "boathouse-door")
	stand("airboat", 118.5, 20.5)
	box(122.2, 16.2, 123.6, 18.0, 1.0, "wood", "counter_top")
	b.board("mill_exit", 113.2, 23.0, 1.42, {"signal": "exit"})
	for p in [Vector2(114.0, 18.0), Vector2(118.0, 17.0), Vector2(118.0, 23.0)]:
		b.prop("lamp", p.x, p.y)
		b.glow(p.x, p.y, 3.0, .2)
	# The pump on the dock's edge: sugar in it ends the king's fleet.
	stand("marina_pump", 108.5, 17.5, .3)
	b.board("mill_control", 109.6, 17.2, 1.1, {"signal": "fuel"})
	b.board("bayou_airboat_sign", 111.94, 19.0, .7, {"z": 1.5, "plane": PI / 2})
	stand("propane_tank", 110.5, 30.5, .45)
	stand("net_rack", 124.5, 30.5, .4)
	stand("crawfish_traps", 124.5, 13.5, .35)
	stand("outboard_stand", 110.5, 27.5, .35)
	b.board("bayou_king_sign", 125.06, 21.0, .6, {"z": 1.0, "plane": -PI / 2})
	b.poles([Vector2(107.5, 35.5), Vector2(107.5, 26.5), Vector2(107.5, 12.5)])
	for p in [Vector2(108.0, 22.0), Vector2(116.0, 30.0), Vector2(103.0, 34.0)]:
		b.streetlamp(p.x, p.y)
	b.label("DOCK", 115, 33)


func still() -> void:
	# The king's still, hid in the cypress behind a stand of reeds: the copper
	# going, the mash barrels, the jugs, the warning.
	b.wall(105, 2, 106, 11, "bayou_cypress", 3.4)
	water(107, 2, 125, 10, "still")
	land(110, 3, 125, 9, "still")
	reeds(107, 11, 125, 11)
	b.secret(
		118,
		11,
		false,
		[107, 2, 125, 10],
		{"from": "n", "id": "reed-curtain", "tile": "bayou_reeds"}
	)
	stand("still", 116.5, 4.5, .45)
	stand("mash_barrel", 113.5, 4.5, .4)
	stand("mash_barrel", 120.5, 5.5, .4)
	stand("jug_stack", 122.5, 3.5, .4)
	stand("cypress", 109.5, 3.5, .3)
	stand("cypress_knees", 108.5, 7.5)
	b.board("bayou_keepout_sign", 115.0, 12.06, .5, {"z": .8, "plane": 0.0})
	b.glow(116.5, 5.0, 3.0, .25)
	b.label("STILL", 112, 6)


## The open water between the places: what the swamp keeps for itself, each
## a set piece of its own, not strewn about.
func backwater() -> void:
	# The old houseboat, sunk to the gunwales and lived in anyway, off the
	# walk between the juke joint and the lagoon.
	shack(76, 5, 82, 10, "back", 0.0, "bayou_tin", {"windows": 3, "lit": .7})
	door(79, 10, false, "n", 0.0, "houseboat-door")
	walk(79, 11, 79, 12, "back")
	stand("porch_couch", 80.5, 7.5, .45)
	box(77.2, 6.2, 78.8, 7.0, .62, "wood", "counter_top")
	b.prop("lamp", 79.0, 7.5)
	stand("ice_chest", 81.5, 11.5)
	# A duck blind of reeds in the backwater by the bait shop, decoys out.
	reeds(4, 73, 8, 73)
	reeds(4, 74, 4, 77)
	reeds(8, 74, 8, 76)
	reeds(4, 78, 8, 78)
	stand("heron", 10.5, 75.5)
	stand("heron", 11.5, 77.0)
	# The gator nest: a mud hump with its mama on it, knees and a snag round it.
	land(8, 84, 12, 88, "back")
	b.raise(8, 84, 12, 88, 0.0)
	stand("dead_snag", 12.5, 84.5, .3)
	stand("cypress_knees", 9.5, 87.5)
	b.mark("bayou_duckweed", 6.0, 86.0, .5, 2.0, 2.0)
	# A truck that tried the ramp at night: sunk to its doors off the landing.
	stand("wreck_pickup", 43.5, 85.5, 0.0, {"z": -.32})
	b.fixture(42.7, 85.0, 44.3, 86.0, -.1, "bayou_bank", "bayou_mud", WATER)
	stand("cypress_b", 46.5, 88.5, .3)
	# The boat graveyard past the cabins: skiffs and a pirogue gone under.
	for p in [Vector3(116.5, 71.5, -.22), Vector3(120.5, 74.5, -.3), Vector3(118.5, 78.5, -.18)]:
		stand("skiff", p.x, p.y, 0.0, {"z": p.z})
	stand("pirogue", 123.5, 70.5, 0.0, {"z": -.12})
	stand("cypress", 124.5, 77.5, .3)
	stand("dead_snag", 113.5, 74.5, .3)
	reeds(121, 81, 125, 82)
	# Cypress standing in the open water, the moss off them, where the
	# backwater is widest: the west of the bait shop and north of the cabins.
	for t in [
		["cypress", 3.5, 69.5],
		["cypress_b", 13.5, 89.5],
		["cypress", 30.5, 86.5],
		["cypress_knees", 32.5, 85.5],
		["cypress", 75.5, 22.5],
		["cypress_knees", 74.5, 3.5],
		["cypress", 112.5, 45.5],
		["cypress_knees", 114.5, 46.5],
		["cypress", 86.5, 70.5],
		["cypress_b", 123.5, 46.5],
	]:
		stand(
			String(t[0]), float(t[1]), float(t[2]), .3 if String(t[0]) != "cypress_knees" else 0.0
		)
	reeds(26, 82, 29, 83)
	b.mark("bayou_lilies", 20.0, 86.0, 0.0, 1.4, 1.4)
	b.mark("bayou_lilies", 116.0, 84.0, 0.0, 1.2, 1.2)
	b.mark("bayou_lilies", 77.0, 18.0, 0.0, 1.2, 1.2)


## Where the way goes: arrows at the forks, the tide marks, the cables.
func story() -> void:
	b.board("bayou_arrow_boil", 45.5, 56.6, .4, {"z": 1.2, "plane": -PI / 2})
	b.board("bayou_arrow_cannery", 84.5, 56.6, .4, {"z": 1.2, "plane": PI / 2})
	b.board("bayou_tide_sign", 62.06, 60.0, .6, {"z": 1.0, "plane": -PI / 2})
	b.board("bayou_noswim_sign", 65.5, 47.4, .45, {"z": .9, "plane": PI})
	b.board("bayou_keepout_sign", 63.5, 26.6, .45, {"z": .9, "plane": 0.0})
	b.distant_cues.append([96.0, 18.0, "distant_bayou_airboat"])
	b.distant_cues.append([59.0, 14.0, "distant_bayou_juke"])
	b.distant_cues.append([14.0, 18.0, "distant_bayou_gator"])
	b.distant_cues.append([60.0, 70.0, "distant_bayou_frogs"])
