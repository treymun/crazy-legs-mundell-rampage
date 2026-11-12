## County Crossroads, rebuilt for seven chapters (layout 3): the county road
## comes in from the south to a four-way stop, and the roads out of it are the
## whole campaign. The county line road runs west and east from the stop with a
## gate on it for each chapter, nearest the stop first and further out as the
## campaign goes on, west and east by turns: the town road home to Hickston and
## the fair's midway road (north side), the logging road to Blackwater and the
## haul road to Stillwater Cut (south side), and out at the road's two ends the
## swamp road to Gator Bayou and the speedway road to Buzzard Bend. North,
## straight ahead from where the player comes in, the road the county closed
## runs up to the crash site and the tractor-beam pad: the Mothership, last.
##
## A fingerpost on the stop's island has an arm for every gate, each pointing
## straight at it, and every gate can be seen from it. Round the stop: the
## Crossroads diner, the County Road Department (the dispatch board on its back,
## facing the road in), the road crew's yard and the county impound.
##
## Built by tools/levels/build_level.gd -- hub.
extends RefCounted

const Builder := preload("res://tools/levels/level_builder.gd")
const W := 84
const H := 62
## The fingerpost, in the middle of the four-way stop.
const POST := Vector2(44.0, 34.0)
## The county line road's open rows; a north gate's line is its first row's
## edge, a south gate's the edge after its last.
const ROAD_N := 28
const ROAD_S := 39
## The gates in campaign order: [chapter, middle, line, side (1: walked up to
## from the south), name board, marker, the arm's height on the fingerpost].
const GATES := [
	["hickston", 35.0, 28.0, 1, "route_hickston", "hub_hickston_marker", 2.05],
	["fair", 53.0, 28.0, 1, "route_fair", "hub_fair_marker", 2.05],
	["sawmill", 26.0, 40.0, -1, "route_sawmill", "hub_mill_marker", 1.75],
	["quarry", 62.0, 40.0, -1, "route_quarry", "hub_quarry_marker", 1.75],
	["bayou", 17.0, 28.0, 1, "route_bayou", "hub_bayou_marker", 1.45],
	["speedway", 71.0, 28.0, 1, "route_speedway", "hub_speedway_marker", 1.45],
	["mothership", 44.0, 8.0, 1, "route_mothership", "hub_ship_marker", 2.5],
]

var b: Builder
var cross: int
var south: int
var town: int
var fair: int
var mill: int
var quarry: int
var bayou: int
var speedway: int
var crew: int
var impound: int
var site: int
var diner: int
var depot: int


func make() -> Builder:
	b = Builder.new("hub", W, H, "hedgerow")
	var gates: Array = []
	for g: Array in GATES:
		gates.append({"destination": g[0], "x": g[1], "y": g[2], "width": 4, "side": g[3]})
	b.meta = {
		"title": "COUNTY CROSSROADS",
		"heading": ["COUNTY", "CROSSROADS"],
		"layout": 3,
		"sky": "sky",
		"hub_board": [53.5, 47.05],
		"hub_gates": gates,
		"hub_clues":
		[
			[
				"ledger",
				38.4,
				28.9,
				"READ THE WEATHERED LEDGER",
				"COUNTY ROAD CREW: TAKE THE WEST TURN FOR TOWN."
			],
			[
				"survey",
				66.6,
				38.5,
				"CHECK THE SURVEY PEG",
				"PIN NINETEEN. THE COUNTY LINE MOVED, NOT THE PIN."
			],
			[
				"washout",
				39.6,
				51.6,
				"READ THE ROAD CREW NOTICE",
				"CULVERT OPEN. RETURN THE BORROWED TOOLS TO THE SHED."
			],
			[
				"order",
				47.2,
				21.6,
				"READ THE COUNTY ORDER",
				"BEAM PAD CLOSED TILL THE COUNTY IS CLEAN. ROAD DEPT."
			],
		],
	}
	return b


func build(_b) -> Array:
	cross = b.district("COUNTY CROSSROADS", Color(1.02, .98, .94))
	south = b.district("COUNTY ROAD", Color(.9, .96, 1.04))
	town = b.district("TOWN ROAD", Color(1.02, .98, .9))
	fair = b.district("FAIR ROAD", Color(1.06, .96, 1.04))
	mill = b.district("MILL ROAD", Color(.88, .98, .98))
	quarry = b.district("QUARRY ROAD", Color(.94, .98, 1.06))
	bayou = b.district("BAYOU ROAD", Color(.9, 1.02, .9))
	speedway = b.district("SPEEDWAY ROAD", Color(1.06, .98, .9))
	crew = b.district("ROAD CREW YARD", Color(1.0, .98, .92))
	impound = b.district("COUNTY IMPOUND", Color(.98, .96, 1.0))
	site = b.district("CRASH SITE", Color(.9, 1.04, .98))
	diner = b.district("CROSSROADS DINER", Color(1.04, .98, .92))
	depot = b.district("ROAD DEPARTMENT", Color(.96, .98, 1.02))
	county_line_road()
	county_road()
	the_diner()
	road_department()
	bayou_road()
	mill_road()
	town_road()
	fair_road()
	quarry_road()
	speedway_road()
	crew_yard()
	impound_lot()
	crash_site()
	for g: Array in GATES:
		gate(g)
	the_stop()
	finish_up()
	return [44.0, 59.5, -PI / 2]


## A chapter's gate on its line: the opening (the yard past it on the road's
## ground, the threshold; the hedge stands round it), the arch with its name
## board, two lamps and the marker on the side away from the stop, so nothing
## stands between the gate and the fingerpost.
func gate(g: Array) -> void:
	var cx: float = g[1]
	var line: float = g[2]
	var side: int = g[3]
	var x0 := int(cx) - 3
	var x1 := int(cx) + 2
	var y0 := int(line) - 3 if side > 0 else int(line)
	var road := b.at(int(cx), int(line) if side > 0 else int(line) - 1)
	b.yard(x0, y0, x1, y0 + 2, b._name_of(int(b.floor_tile[road])), int(b.area[road]))
	var sill := int(line) - 1 if side > 0 else int(line)
	b.paint(x0, sill, x1, sill, "route_threshold")
	b.arch(cx, line, 4.0, String(g[4]), "stockyard")
	var front := line + side * .5
	b.board("hub_lamp", cx - 2.2, front, 2.2, {"glow": true})
	b.board("hub_lamp", cx + 2.2, front, 2.2, {"glow": true})
	b.glow(cx, front, 3.6, .35)
	var away := 1.0 if cx >= POST.x else -1.0
	b.board(
		String(g[5]),
		cx + away * 2.9,
		line + side * 1.6,
		.5,
		{"z": .5, "plane": 0.0 if side > 0 else PI}
	)


# ------------------------------------------------------------------- areas


## The county line road, west to east, each stretch the ground of where its gate
## goes; tarmac down the middle, fading to dirt toward the ends.
func county_line_road() -> void:
	b.yard(8, ROAD_N, 21, ROAD_S, "tracks", bayou)
	b.yard(22, ROAD_N, 30, ROAD_S, "mill_grit", mill)
	b.yard(31, ROAD_N, 38, ROAD_S, "tracks", town)
	b.yard(39, ROAD_N, 48, ROAD_S, "hub_patch", cross)
	b.yard(49, ROAD_N, 57, ROAD_S, "fair_gravel", fair)
	b.yard(58, ROAD_N, 66, ROAD_S, "quarry_dust", quarry)
	b.yard(67, ROAD_N, 80, ROAD_S, "track_dirt", speedway)
	b.paint(14, 31, 74, 36, "asphalt")
	b.paint(12, 32, 13, 35, "tracks")
	b.paint(75, 32, 76, 35, "tracks")
	b.paint(16, 33, 38, 33, "road")
	b.paint(49, 33, 72, 33, "road")
	b.paint(31, ROAD_N, 31, ROAD_N + 1, "grass")
	b.paint(38, ROAD_N, 38, ROAD_N + 1, "grass")
	# Utility poles along the north side, wired over the stop.
	b.poles([Vector2(9.5, 28.6), Vector2(30.6, 28.6), Vector2(39.4, 28.6)])
	b.poles([Vector2(48.6, 28.6), Vector2(57.6, 28.6), Vector2(78.6, 28.6)])
	b.cable(39.4, 28.6, 48.6, 28.6, 3.3)


## The four-way stop: the island with the fingerpost, stop signs on the
## corners, the oil the trucks leave idling at it.
func the_stop() -> void:
	b.fixture(43.3, 33.3, 44.7, 34.7, .2, "concrete", "concrete")
	var arms: Array = []
	for g: Array in GATES:
		var at := Vector2(float(g[1]), float(g[2]))
		arms.append(["hub_arm_" + String(g[0]), (at - POST).angle(), float(g[6]), .26])
	b.fingerpost(POST.x, POST.y, arms, 3.0)
	b.glow(POST.x, POST.y, 3.0, .25)
	for p in [Vector2(39.4, 39.4), Vector2(48.6, 39.4)]:
		b.prop("roadsign", p.x, p.y)
	for k in 6:
		b.mark("detail_wear_oil", 41.2 + (k % 3) * 2.6, 32.2 + (k / 3) * 3.6, k * .6, 1.4, .5)


## The county road in from the south: the way the player comes, the diner on
## the left, the Road Department on the right, the culvert in the ditch.
func county_road() -> void:
	b.yard(39, 40, 48, 60, "tracks", south)
	b.paint(41, 40, 46, 60, "asphalt")
	b.paint(39, 50, 40, 52, "hub_runoff")
	b.board("detail_culvert_catch_rack", 39.6, 51.6, .53, {"z": 0.0, "plane": 0.0})
	b.board("hub_title", 47.7, 55.4, 1.1, {"plane": .35})
	b.board("town_line_sign", 39.55, 57.5, .86, {"z": 1.05, "plane": -.3})
	b.fixture(39.5, 57.45, 39.6, 57.55, 1.1, "wood", "wood")
	b.town("mailbox_row", 47.6, 58.6)
	for p in [Vector2(39.5, 46.5), Vector2(48.5, 50.0)]:
		b.streetlamp(p.x, p.y)
	b.streetlamp(39.5, 55.0)


func the_diner() -> void:
	# Chrome and grease, closed for the night, its porch on the county line road.
	b.building(
		30,
		41,
		38,
		48,
		diner,
		{
			"wall": "diner_steel",
			"roof": 2.4,
			"floor": "floor_tile",
			"windows": 2,
			"lit": .8,
			"light": .8,
			"skin": "plaster"
		}
	)
	b.wall_top(30, 41, 38, 41, 3.1)
	b.room(31, 40, 37, 40, "porch", diner, {"roof": 2.1, "ceiling": "joists", "light": .95})
	b.raise(31, 40, 37, 40, .12)
	b.wall(30, 40, 30, 40, "diner_steel", 2.4)
	b.wall(38, 40, 38, 40, "diner_steel", 2.4)
	b.panel(33.0, 40.97, 36.0, 40.97, "eat", 2.35, 3.05, 1.3)
	for x in [31.08, 34.0, 37.92]:
		b.fixture(x - .06, 39.94, x + .06, 40.06, 2.1, "wood", "counter_top", .12)
	b.town("porch_couch", 32.6, 40.3)
	b.react("vending", 36.6, 40.4, 1.5, {"id": "diner-cooler"})
	# Its lot on the county road.
	b.yard(30, 49, 38, 55, "gravel", diner)
	b.prop("pickup_truck", 34.0, 51.5)
	b.town("picnic_table", 31.5, 54.5, {"solid": .4})
	b.town("burn_barrel", 37.5, 49.5, {"solid": .25, "glow": true})
	b.glow(37.5, 49.5, 2.6, .3)
	b.town("cooler", 32.5, 54.2)
	b.prop("tree", 30.6, 49.6)


func road_department() -> void:
	# The County Road Department: its sign on the county line road, the
	# dispatch board on its back where the county road comes in.
	b.building(
		49,
		40,
		58,
		46,
		depot,
		{
			"wall": "hub_service_wall",
			"roof": 2.4,
			"floor": "concrete",
			"windows": 3,
			"lit": .6,
			"light": .78,
			"skin": "hub_service_wall"
		}
	)
	b.wall_top(49, 40, 58, 40, 3.0)
	b.board("hub_road_dept", 53.5, 39.94, .46, {"z": 2.3, "plane": PI})
	b.yard(49, 47, 58, 54, "gravel", depot)
	b.paint(49, 47, 58, 48, "concrete")
	b.prop("water_tower", 56.4, 52.4)
	b.board("hub_tank_label", 56.4, 53.0, .35, {"z": 3.5, "plane": 0.0})
	b.town("generator", 51.5, 53.5, {"solid": .45})
	b.town("dump_truck", 56.5, 48.5, {"solid": .45})
	b.town("gas_cans", 49.6, 53.6)
	b.board("detail_shed_tool_tray", 51.0, 47.4, .6, {"z": .8, "plane": 0.0})
	b.fixture(50.2, 47.1, 51.8, 47.7, .8, "crate_side", "counter_top")
	b.cable(48.6, 28.6, 53.5, 40.0, 3.0)


func bayou_road() -> void:
	# The west end: the road gives out in the mud where the bayou starts, a boat
	# pulled up, the traps stacked, the cypress over it all.
	b.wall(7, ROAD_N, 7, ROAD_S, "bayou_cypress", 2.6)
	b.wall(8, ROAD_N - 1, 13, ROAD_N - 1, "bayou_reeds", 1.5)
	b.wall(20, ROAD_N - 1, 20, ROAD_N - 1, "bayou_reeds", 1.5)
	b.wall(8, ROAD_S + 1, 18, ROAD_S + 1, "bayou_reeds", 1.5)
	b.paint(8, ROAD_N, 13, ROAD_S, "bayou_mud")
	b.paint(8, 36, 10, 39, "bayou_water")
	b.paint(11, 38, 12, 39, "bayou_water")
	b.paint(8, 28, 9, 29, "bayou_marsh")
	b.town("cypress", 8.6, 38.6)
	b.town("cypress_b", 8.7, 29.0)
	b.town("cypress_knees", 11.5, 38.7)
	b.town("dead_snag", 12.5, 28.7)
	b.town("pirogue", 9.5, 33.5, {"solid": .45})
	b.town("crawfish_traps", 10.5, 31.5)
	b.town("bait_cooler_rack", 8.6, 35.3, {"solid": .3})
	b.town("heron", 10.0, 37.4)
	b.town("lantern_post", 12.6, 35.5, {"solid": .1, "glow": true})
	b.glow(12.6, 35.5, 3.0, .3)
	b.town("gator_hide", 16.5, 39.4)
	b.board("bayou_noswim_sign", 10.0, 39.9, .36, {"z": .9, "plane": PI})


func mill_road() -> void:
	# The logging road's turn: timber either side of the gate on the south side.
	b.wall(19, ROAD_S + 1, 22, ROAD_S + 1, "mill_log", 1.6)
	b.wall(29, ROAD_S + 1, 29, ROAD_S + 1, "mill_log", 1.6)
	b.town("log_pile", 20.5, 38.5, {"solid": .45})
	b.town("axe_stump", 29.5, 38.5, {"solid": .3})
	b.town("lantern_post", 22.6, 38.8, {"solid": .1, "glow": true})
	b.glow(22.6, 38.8, 3.0, .25)
	b.board("mill_log_ends", 20.5, 39.94, 1.0, {"plane": PI})
	b.board("detail_mill_tie_off", 28.6, 39.6, .52, {"z": .65, "plane": PI})


func town_road() -> void:
	# The town road home: hay and the mail on the north side by Hickston's gate.
	b.fence(30, ROAD_N - 1, 31, ROAD_N - 1, 1.24, "stockyard")
	b.fence(38, ROAD_N - 1, 38, ROAD_N - 1, 1.24, "stockyard")
	b.town("mailbox_row", 37.4, 39.35)
	b.board("story_dispatch", 38.4, 28.9, .25, {"z": .65})
	b.fixture(38.1, 28.6, 38.7, 29.2, .65, "stockyard", "counter_top")
	b.streetlamp(31.0, 39.3)


func fair_road() -> void:
	# The midway road: pylons and bunting over the fair's gate, what the fair
	# dropped on its way out.
	b.fence(49, ROAD_N - 1, 49, ROAD_N - 1, 1.6, "fair_iron")
	b.fence(56, ROAD_N - 1, 57, ROAD_N - 1, 1.6, "fair_iron")
	b.board("fair_pylon", 49.4, 28.4, 1.2, {"glow": true})
	b.board("fair_pylon", 56.6, 28.4, 1.2, {"glow": true})
	b.cable(49.4, 28.4, 56.6, 28.4, 2.9)
	b.board("fair_bulbs", 53.0, 28.4, .39, {"z": 2.55, "plane": 0.0, "back": "fair_bulbs_on"})
	b.town("prize_bear", 50.0, 39.3)
	b.town("cotton_candy", 51.5, 38.5, {"solid": .4, "scale": .88})
	b.town("balloons", 52.7, 39.3)
	b.board("detail_fair_route_crate", 57.4, 39.6, .56, {"z": .57, "plane": PI})
	b.streetlamp(57.0, 39.3)


func quarry_road() -> void:
	# The haul road's turn: rock and the powder on the south side by the gate.
	b.wall(65, ROAD_S + 1, 66, ROAD_S + 1, "quarry_face", 2.0)
	b.town("boulder_a", 58.5, 38.5, {"solid": .4})
	b.town("warning_barrel", 66.5, 37.5, {"solid": .3})
	b.town("tnt_crate", 65.5, 39.2)
	b.board("survey_peg", 66.6, 38.5, .58, {"plane": PI + .35})
	for k in 3:
		b.mark("detail_wear_chalk", 60.0 + k * 1.6, 37.6 + (k % 2) * .8, k * .7, 1.2, .9)


func speedway_road() -> void:
	# The east end: the road turns to track dirt past a checkered line, the
	# flagman's stand, tyres, a wreck towed off the oval, the ads on the wall.
	b.wall(81, ROAD_N, 81, ROAD_S, "crash_wall", 1.3)
	b.wall(67, ROAD_N - 1, 67, ROAD_N - 1, "tire_wall", 1.1)
	b.wall(74, ROAD_N - 1, 80, ROAD_N - 1, "tire_wall", 1.1)
	b.wall(67, ROAD_S + 1, 80, ROAD_S + 1, "crash_wall", 1.3)
	b.paint(75, ROAD_N, 80, ROAD_S, "track_dirt")
	b.paint(76, ROAD_N, 76, ROAD_S, "checker_band")
	b.board("speedway_entry", 80.94, 34.0, .9, {"z": 1.3, "plane": PI / 2})
	b.board("speedway_ad_tires", 70.0, 39.94, .3, {"z": .7, "plane": PI})
	b.board("speedway_ad_oil", 75.5, 39.94, .3, {"z": .7, "plane": PI})
	b.town("flag_stand", 79.5, 33.5, {"solid": .45})
	b.town("stock_car", 78.5, 38.4, {"solid": .45})
	b.town("tire_pile", 79.5, 29.5, {"solid": .45})
	b.town("tire_stack", 77.5, 28.6, {"solid": .3})
	for y in [31.5, 33.5, 35.5]:
		b.town("pylon", 77.5, y)
	b.town("fuel_pump", 68.5, 39.2)
	b.streetlamp(73.5, 39.3)


func crew_yard() -> void:
	# North of the road west of the stop: the road crew's yard and its gear.
	b.yard(21, 22, 29, ROAD_N - 1, "gravel", crew)
	b.fence(20, 22, 20, ROAD_N - 1, 1.24, "stockyard")
	b.paint(22, 23, 28, 24, "hub_patch")
	b.panel(28.0, 22.06, 22.0, 22.06, "hub_screen", 0.0, 2.2, .9)
	b.town("cable_spool", 21.5, 23.5, {"solid": .45})
	b.town("sawdust_pile", 27.5, 23.5, {"solid": .45})
	b.town("tractor", 24.5, 23.5, {"solid": .45})
	b.town("pallet_stack", 28.5, 26.5, {"solid": .45})
	b.town("wheelbarrow", 21.6, 26.4)
	b.board("detail_town_roadside_kit", 25.0, 22.2, .46, {"z": .7, "plane": 0.0})


func impound_lot() -> void:
	# North of the road east of the stop: what the county towed off its roads.
	b.yard(58, 22, 66, ROAD_N - 1, "junk_ground", impound)
	b.fence(67, 22, 67, ROAD_N - 2, 1.6, "steel_mesh")
	b.panel(66.0, 22.06, 58.0, 22.06, "steel_mesh", 0.0, 1.9, .9)
	b.car(59.6, 23.4, true, "mill_tin")
	b.car(59.6, 25.9, true, "tin")
	b.town("tow_truck", 62.5, 24.5, {"solid": .45})
	b.town("crushed_stack", 65.5, 23.5, {"solid": .45})
	b.prop("tire", 58.6, 26.6)
	b.board("salvage_sign", 66.9, 26.5, .3, {"z": 1.0, "plane": -PI / 2})


func crash_site() -> void:
	# The road the county closed, up to where the saucer came down and the
	# Mothership's beam still stands: cones and tape across it, the county's
	# order, the lights they brought, the saucer in the trench it dug, what fell
	# out of it, and at the far end the pad.
	b.yard(39, 21, 48, ROAD_N - 1, "tracks", site)
	b.paint(41, 21, 46, ROAD_N - 1, "asphalt")
	b.yard(33, 8, 55, 20, "dirt", site)
	b.paint(42, 8, 45, 20, "tracks")
	for p in [Vector2(39.5, 21.5), Vector2(41.5, 21.5), Vector2(46.5, 21.5), Vector2(48.5, 21.5)]:
		b.town("pylon", p.x, p.y)
	for pair in [[39.5, 41.5], [46.5, 48.5]]:
		b.panel(float(pair[0]), 21.5, float(pair[1]), 21.5, "warning", .82, .94, 1.0)
	b.board("hub_county_order", 47.2, 21.6, .6, {"z": .45, "plane": 0.0})
	# The saucer came in low from the west, dug a trench and stopped nose down.
	b.paint(36, 13, 47, 14, "derby_mud")
	b.paint(47, 11, 54, 16, "derby_mud")
	b.town("saucer_wreck", 51.5, 13.5, {"glow": true, "scale": 1.35, "solid": 1.1})
	b.glow(51.5, 13.5, 4.0, .35)
	for p in [Vector2(48.5, 10.5), Vector2(54.5, 11.5), Vector2(53.5, 16.5), Vector2(48.5, 16.5)]:
		b.town("boulder_a" if int(p.y) % 2 else "boulder_b", p.x, p.y, {"solid": .4})
	for k in 6:
		b.mark("detail_wear_oil", 37.5 + k * 1.9, 13.4 + (k % 2) * .6, k * .4, 1.6, .9)
	b.town("dead_snag", 36.5, 10.5, {"solid": .2})
	b.town("dead_snag", 54.5, 19.5, {"solid": .2})
	# What fell out of it: a pod and the crates, spilled along the trench.
	b.town("pod", 37.5, 16.5, {"solid": .45})
	b.town("alien_crate", 39.5, 15.5, {"solid": .4})
	b.town("alien_crate", 35.5, 15.5, {"solid": .4})
	b.paint(35, 15, 40, 17, "junk_ground")
	# The county's lights on it, one behind sandbags, and the generator.
	b.town("floodlight_tower", 34.5, 8.5, {"solid": .3, "glow": true})
	b.glow(34.5, 8.5, 6.0, .35)
	b.town("searchlight", 53.5, 8.5, {"solid": .3})
	b.town("range_sandbags", 52.5, 9.6)
	b.town("generator", 34.5, 19.5, {"solid": .45})
	b.town("warning_barrel", 40.5, 19.5, {"solid": .3})
	b.town("warning_barrel", 49.5, 8.5, {"solid": .3})
	# The pad: the beam down out of the sky, a truck caught in it.
	b.fixture(43.2, 5.2, 44.8, 6.8, 12.0, "ship_beam", "ship_beam")
	b.town("hung_pickup", 44.0, 6.95, {"z": 2.2})
	b.town("beam_emitter", 44.0, 6.0, {"z": 11.0})
	b.mark("mark_beam", 44.0, 6.0, 0.0, 2.0, 2.0)
	b.board("ship_hazard", 41.1, 9.6, .5, {"z": .5, "plane": 0.0})
	b.glow(44.0, 7.0, 5.0, .5)


func finish_up() -> void:
	for l in [
		["BAYOU", 9, 33],
		["MILL", 24, 37],
		["TOWN", 33, 30],
		["STOP", 42, 36],
		["FAIR", 51, 30],
		["QUARRY", 60, 37],
		["SPEEDWAY", 71, 33],
		["CREW", 23, 24],
		["IMPOUND", 60, 24],
		["CRASH SITE", 41, 14],
		["DINER", 32, 45],
		["ROAD DEPT", 51, 43],
	]:
		b.label(String(l[0]), int(l[1]), int(l[2]))
