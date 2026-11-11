## County Crossroads, rebuilt (layout 2): where the county road comes in from
## the south to a four-way stop, and four roads fan north to the chapters'
## gates, each dressed as the place it goes: the logging road to the mill,
## the town road home to Hickston, the carnival lane to the fair, the haul road
## to the quarry. Round the stop: the Crossroads diner, the County Road
## Department shed with the dispatch board, and the road crew's yard.
##
## Built by tools/levels/build_level.gd -- hub.
extends RefCounted

const Builder := preload("res://tools/levels/level_builder.gd")
const W := 72
const H := 60

var b: Builder
var cross: int
var south: int
var mill: int
var town: int
var fair: int
var quarry: int
var crew: int


func make() -> Builder:
	b = Builder.new("hub", W, H, "hedgerow")
	b.meta = {
		"title": "COUNTY CROSSROADS",
		"heading": ["COUNTY", "CROSSROADS"],
		"layout": 2,
		"sky": "sky",
		"hub_board": [47.5, 46.05],
		"hub_gates":
		[
			{"destination": "sawmill", "x": 8.0, "y": 8.0, "width": 4, "side": 1},
			{"destination": "hickston", "x": 20.0, "y": 8.0, "width": 4, "side": 1},
			{"destination": "fair", "x": 50.0, "y": 8.0, "width": 4, "side": 1},
			{"destination": "quarry", "x": 62.0, "y": 8.0, "width": 4, "side": 1},
		],
		"hub_clues":
		[
			[
				"ledger",
				23.4,
				26.6,
				"READ THE WEATHERED LEDGER",
				"COUNTY ROAD CREW: TAKE THE WEST TURN FOR TOWN."
			],
			[
				"survey",
				58.6,
				28.4,
				"CHECK THE SURVEY PEG",
				"PIN NINETEEN. THE COUNTY LINE MOVED, NOT THE PIN."
			],
			[
				"washout",
				39.4,
				49.6,
				"READ THE ROAD CREW NOTICE",
				"CULVERT OPEN. RETURN THE BORROWED TOOLS TO THE SHED."
			],
		],
	}
	return b


func build(_b) -> Array:
	cross = b.district("COUNTY CROSSROADS", Color(1.02, .98, .94))
	south = b.district("COUNTY ROAD", Color(.9, .96, 1.04))
	mill = b.district("MILL ROAD", Color(.88, .98, .98))
	town = b.district("TOWN ROAD", Color(1.02, .98, .9))
	fair = b.district("FAIR ROAD", Color(1.06, .96, 1.04))
	quarry = b.district("QUARRY ROAD", Color(.94, .98, 1.06))
	crew = b.district("ROAD CREW YARD", Color(1.0, .98, .92))
	crossroads()
	county_road()
	mill_road()
	town_road()
	fair_road()
	quarry_road()
	crew_yard()
	finish_up()
	polish()
	return [35.5, 56.5, -PI / 2]


func gate(cx: float, face: String, marker: String, floor_name: String, district_id: int) -> void:
	var x0 := int(cx) - 3
	b.yard(x0, 5, x0 + 6, 7, floor_name, district_id)
	b.paint(x0, 7, x0 + 6, 7, "route_threshold")
	b.wall(x0, 4, x0 + 6, 4, "hedgerow", 2.4)
	b.arch(cx, 8.0, 4.0, face, "stockyard")
	b.board("hub_lamp", cx - 2.2, 8.5, 2.2, {"glow": true})
	b.board("hub_lamp", cx + 2.2, 8.5, 2.2, {"glow": true})
	b.glow(cx, 8.5, 3.6, .35)
	b.board(marker, cx + 2.9, 9.6, .5, {"z": .5, "plane": 0.0})


# ------------------------------------------------------------------- areas


func crossroads() -> void:
	b.yard(14, 30, 57, 49, "hub_patch", cross)
	b.paint(31, 30, 40, 49, "asphalt")
	b.paint(14, 35, 57, 40, "asphalt")
	b.paint(34, 37, 37, 38, "road")
	# The four-way stop: signs on every corner, the county directory between.
	for p in [Vector2(30.4, 34.4), Vector2(41.6, 34.4), Vector2(30.4, 41.6), Vector2(41.6, 41.6)]:
		b.prop("roadsign", p.x, p.y)
	b.board("hub_directory", 35.5, 42.6, 1.56, {"plane": 0.06, "back": "hub_directory_back"})
	b.fixture(35.0, 42.5, 36.0, 43.0, .2, "concrete", "concrete")
	# The Crossroads diner: chrome and grease, closed for the night.
	b.building(
		16,
		41,
		28,
		48,
		cross,
		{
			"wall": "brick",
			"roof": 2.4,
			"floor": "floor_tile",
			"windows": 3,
			"lit": .8,
			"light": .8,
			"skin": "plaster"
		}
	)
	b.wall_top(16, 41, 28, 41, 3.1)
	b.room(17, 40, 27, 40, "porch", cross, {"roof": 2.1, "ceiling": "joists", "light": .95})
	b.raise(17, 40, 27, 40, .12)
	b.board("hub_title", 22.0, 40.96, .9, {"z": 2.2, "plane": 0.0, "glow": true})
	for x in [17.0, 22.0, 28.0]:
		b.fixture(x - .06, 39.94, x + .06, 40.06, 2.1, "wood", "counter_top", .12)
	b.town("porch_couch", 19.5, 40.4)
	b.react("vending", 26.4, 40.4, 1.5, {"id": "diner-cooler"})
	b.town("picnic_table", 15.5, 37.5, {"solid": .4})
	# The County Road Department: the dispatch board on its front.
	b.building(
		42,
		39,
		53,
		45,
		cross,
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
	b.wall_top(42, 39, 53, 39, 3.0)
	b.board("hub_road_dept", 47.5, 38.94, .46, {"z": 2.3, "plane": PI})
	b.prop("water_tower", 55.6, 47.0)
	b.board("hub_tank_label", 55.6, 47.6, .35, {"z": 3.5, "plane": 0.0})
	b.town("generator", 51.5, 47.5, {"solid": .45})
	# The culvert in the ditch south of the stop.
	b.paint(38, 48, 41, 49, "hub_runoff")
	b.board("detail_culvert_catch_rack", 39.4, 49.6, .53, {"z": 0.0, "plane": 0.0})
	b.poles([Vector2(14.5, 30.5), Vector2(29.5, 30.5), Vector2(44.5, 30.5), Vector2(56.5, 30.5)])
	b.cable(44.5, 30.5, 47.5, 39.4, 3.0)
	for p in [
		Vector2(31.0, 38.0),
		Vector2(40.0, 38.0),
		Vector2(35.5, 32.0),
		Vector2(35.5, 46.0),
		Vector2(20.0, 36.0),
		Vector2(51.0, 36.0)
	]:
		b.streetlamp(p.x, p.y)
	for k in 6:
		b.mark("detail_wear_oil", 33.0 + k * 1.3, 36.0 + (k % 3) * 1.2, k * .6, 1.4, .5)


func county_road() -> void:
	b.yard(31, 50, 40, 58, "tracks", south)
	b.paint(33, 50, 38, 58, "asphalt")
	b.board("hub_road_stake", 31.4, 54.0, .97, {"plane": PI / 2, "back": "hub_road_stake_back"})
	b.board("town_line_sign", 40.05, 52.5, .86, {"z": 1.05, "plane": -PI / 2})
	b.fixture(39.95, 51.95, 40.05, 52.05, 1.1, "wood", "wood")
	b.town("mailbox_row", 31.6, 51.5)
	for x in [26.0, 28.5, 43.0, 46.5]:
		b.prop("tree" if int(x) % 2 else "tree_b", x, 55.0)
	b.streetlamp(35.5, 53.0)


func mill_road() -> void:
	# West from the stop, then north to the mill: timber all the way.
	b.yard(3, 30, 13, 40, "mill_grit", mill)
	b.yard(3, 8, 13, 29, "mill_grit", mill)
	b.paint(6, 8, 10, 40, "tracks")
	gate(8.0, "route_sawmill", "hub_mill_marker", "mill_grit", mill)
	b.wall(14, 8, 15, 29, "mill_log", 1.6)
	for p in [Vector2(4.5, 14.5), Vector2(11.5, 20.5), Vector2(4.5, 26.5), Vector2(11.5, 33.5)]:
		b.town("log_pile", p.x, p.y, {"solid": .45})
	b.town("lumber_cart", 4.5, 37.5, {"solid": .45})
	b.town("axe_stump", 11.5, 11.5, {"solid": .3})
	b.town("lantern_post", 4.5, 20.5, {"solid": .1, "glow": true})
	b.town("lantern_post", 11.5, 27.5, {"solid": .1, "glow": true})
	b.glow(4.5, 20.5, 3.0, .25)
	b.glow(11.5, 27.5, 3.0, .25)
	b.board("mill_timber", 12.0, 16.0, .57)
	b.board("detail_mill_tie_off", 5.4, 10.2, .52, {"z": .65, "plane": PI})
	b.board("mill_log_ends", 14.0, 24.0, 1.0, {"plane": PI / 2})


func town_road() -> void:
	b.yard(16, 8, 24, 29, "tracks", town)
	b.paint(16, 8, 16, 29, "grass")
	b.paint(24, 8, 24, 29, "grass")
	gate(20.0, "route_hickston", "hub_hickston_marker", "tracks", town)
	b.town("tractor", 23.5, 17.5, {"solid": .45})
	b.town("hay_wagon", 16.5, 23.5, {"solid": .45})
	b.town("mailbox_row", 23.6, 12.5)
	for p in [Vector2(16.5, 12.0), Vector2(23.6, 21.0)]:
		b.prop("hay", p.x, p.y)
	b.board("detail_town_roadside_kit", 19.0, 26.6, .46, {"z": .7, "plane": PI})
	b.board("story_dispatch", 23.4, 26.6, .25, {"z": .65})
	b.fixture(23.1, 26.3, 23.7, 26.9, .65, "stockyard", "counter_top")
	b.streetlamp(20.0, 20.0)


func fair_road() -> void:
	b.yard(46, 8, 54, 29, "fair_gravel", fair)
	gate(50.0, "route_fair", "hub_fair_marker", "fair_gravel", fair)
	b.wall(45, 8, 45, 29, "fair_iron", 1.6)
	b.wall(55, 8, 55, 29, "fair_iron", 1.6)
	# Bunting strung over the lane, lit, and what the fair dropped on its way.
	for k in 4:
		var y := 12.5 + k * 4.5
		b.cable(45.6, y, 54.4, y, 2.9)
		b.board("fair_bulbs", 50.0, y, .39, {"z": 2.5, "plane": 0.0, "back": "fair_bulbs_on"})
	for p in [Vector2(46.5, 15.5), Vector2(53.5, 22.5)]:
		b.town("balloons", p.x, p.y)
	b.town("prize_bear", 53.4, 14.0)
	b.town("cotton_candy", 46.5, 26.5, {"solid": .4})
	b.board("fair_pylon", 46.0, 11.0, 1.2, {"glow": true})
	b.board("fair_pylon", 54.0, 11.0, 1.2, {"glow": true})
	b.board("detail_fair_route_crate", 52.0, 27.6, .56, {"z": .57, "plane": PI})
	b.glow(50.0, 18.0, 5.0, .3)


func quarry_road() -> void:
	b.yard(58, 30, 68, 40, "quarry_dust", quarry)
	b.yard(58, 8, 68, 29, "quarry_dust", quarry)
	b.paint(60, 8, 64, 40, "tracks")
	gate(62.0, "route_quarry", "hub_quarry_marker", "quarry_dust", quarry)
	b.wall(56, 8, 57, 29, "quarry_face", 2.0)
	b.wall(69, 8, 69, 40, "quarry_face", 2.6)
	for p in [Vector2(58.5, 13.5), Vector2(67.5, 19.5), Vector2(58.5, 23.5)]:
		b.town("boulder_a" if int(p.y) % 2 else "boulder_b", p.x, p.y, {"solid": .4})
	b.town("warning_barrel", 67.5, 12.5, {"solid": .3})
	b.town("warning_barrel", 67.5, 26.5, {"solid": .3})
	b.town("tnt_crate", 66.5, 35.5, {"solid": .4})
	b.town("mine_cart", 59.5, 36.5, {"solid": .45})
	b.board("survey_peg", 58.6, 28.4, .58, {"plane": -.4})
	b.board("detail_quarry_survey_case", 67.4, 31.0, .49, {"z": .0, "plane": PI / 2})
	b.board("wing_quarry_danger", 68.94, 22.0, .7, {"z": 1.0, "plane": PI / 2})
	for k in 5:
		b.mark("detail_wear_chalk", 60.0 + (k % 3) * 1.6, 14.0 + k * 4.0, k * .7, 1.2, .9)
	b.streetlamp(62.0, 20.0)


func crew_yard() -> void:
	# Between the town road and the fair lane: the road crew's yard.
	b.yard(26, 8, 44, 29, "gravel", crew)
	b.wall(25, 8, 25, 29, "stockyard", 1.24)
	b.yard(25, 27, 25, 28, "gravel", crew)
	b.fence(26, 7, 44, 7, 1.6, "stockyard")
	b.paint(28, 10, 42, 12, "hub_patch")
	# The old water tank on its legs, gravel heaps, the grader, the screen.
	b.town("dump_truck", 30.5, 14.5, {"solid": .45})
	b.town("cable_spool", 41.5, 24.5, {"solid": .45})
	b.town("tire_stack", 27.5, 22.5, {"solid": .3})
	b.town("sawdust_pile", 38.5, 12.5, {"solid": .45})
	b.town("gas_cans", 42.6, 20.6)
	b.town("pallet_stack", 34.5, 20.5, {"solid": .45})
	b.panel(32.0, 26.0, 37.0, 26.0, "hub_screen", 0.0, 2.2, .9)
	b.board("hub_road_stake", 43.4, 28.4, .97, {"plane": PI, "back": "hub_road_stake_back"})
	b.board("detail_shed_tool_tray", 29.0, 27.5, .6, {"z": .8, "plane": 0.0})
	b.fixture(28.2, 27.2, 29.8, 27.8, .8, "crate_side", "counter_top")
	b.streetlamp(36.0, 18.0)


func finish_up() -> void:
	b.hedge(2, 41, 13, 41)
	b.hedge(58, 41, 69, 41)
	for l in [
		["MILL", 4, 22],
		["TOWN", 17, 18],
		["CREW", 30, 18],
		["FAIR", 47, 18],
		["QUARRY", 59, 18],
		["STOP", 33, 36]
	]:
		b.label(String(l[0]), int(l[1]), int(l[2]))


## The polish pass: the Crossroads' empty ground filled, road by road.
func polish() -> void:
	var themes := {
		cross: ["prop:barrel", "prop:tire", "gas_cans", "warning_barrel", "mailbox_row"],
		south: ["prop:tire", "prop:reeds"],
		mill: ["log_pile", "axe_stump", "pallet_stack", "prop:barrel"],
		town: ["prop:hay", "wheelbarrow", "prop:barrel"],
		fair: ["balloons", "prize_bear", "board:fair_spill@.3"],
		quarry: ["boulder_a", "boulder_b", "warning_barrel", "tnt_crate"],
		crew: ["warning_barrel", "tire_stack", "gas_cans", "cable_spool", "prop:barrel"],
	}
	var marks := {
		cross: ["detail_wear_oil"],
		mill: ["detail_wear_sawdust"],
		quarry: ["detail_wear_chalk"],
		town: ["detail_wear_grain"],
		crew: ["detail_wear_oil"],
	}
	var filled := b.fill_empty(themes, 3, marks)
	print("hub: empty ground %d -> %d" % [filled.x, filled.y])
