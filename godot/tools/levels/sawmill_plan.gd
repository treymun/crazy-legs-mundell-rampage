## Blackwater Timber, rebuilt (layout 2): a mill in the rain. The delivery
## yard and truck scale in the south; the flooded log pond in the middle,
## crossed on boardwalks; the west bank's sluice house (isolate the west feed)
## by the loggers' bunkhouse and the flume; the east bank's green chain sort
## and the dry kilns (strike the belt release), the rain storage sheds; the
## cutting shed across the north with the log carriage (its brake) and the
## pump house (the relay), where the foreman comes, and the loading apron.
##
## Built by tools/levels/build_level.gd -- sawmill.
extends RefCounted

const Builder := preload("res://tools/levels/level_builder.gd")
const W := 130
const H := 86

var b: Builder
var yard: int
var pond: int
var west: int
var east: int
var shed: int
var apron: int
var sort: int
var kilns: int
var storage: int
var bunk: int
var flume: int
var scale: int
var pump: int


func make() -> Builder:
	b = Builder.new("sawmill", W, H, "wood")
	b.meta = {
		"title": "BLACKWATER TIMBER",
		"heading": ["BLACKWATER", "TIMBER"],
		"intro": "ISOLATE THE WEST FEED AND TRIP THE DRY-KILN BELT.",
		"ending": '"CLOCK OUT. LEAVE THE BOOTS OUTSIDE."',
		"score": "mill_score",
		"ambience": "mill",
		"layout": 2,
		"sky": "mill_sky",
		"control_name": "SLUICE FEED AND DRY-KILN BELT",
		"objective_side_tasks": ["brake"],
		"extraction": {"x": 39.5, "y": 3.5, "label": "USE EXTRACTION CONTROL", "shutdown": "relay"},
		"return_gate": {"destination": "hub", "x": 64.0, "y": 84.4, "width": 3.45, "side": -1},
		"recovery_room": [58.4, 8.4, 69.6, 12.6, "mill_bank"],
		"wave": ["wave-guard", "wave-millhand", "wave-billy", "wave-lantern", "loading-foreman"],
	}
	return b


func build(_b) -> Array:
	yard = b.district("DELIVERY YARD", Color(.92, .96, 1.02))
	pond = b.district("FLOODED LOG POND", Color(.86, .96, 1.02))
	west = b.district("WEST BANK", Color(.9, 1.0, .96))
	east = b.district("EAST BANK", Color(.94, .98, .98))
	shed = b.district("THE CUTTING SHED", Color(1.04, .96, .88))
	apron = b.district("LOADING APRON", Color(.92, .96, 1.02))
	sort = b.district("GREEN CHAIN SORT", Color(.96, 1.02, .94))
	kilns = b.district("DRY KILNS", Color(1.1, .94, .82))
	storage = b.district("RAIN STORAGE", Color(.94, .96, 1.0))
	bunk = b.district("LOGGERS' BUNKHOUSE", Color(1.04, .98, .9))
	flume = b.district("THE FLUME", Color(.88, .98, 1.0))
	scale = b.district("TRUCK SCALE", Color(1.0, .98, .94))
	pump = b.district("PUMP HOUSE", Color(1.02, .98, .9))
	delivery_yard()
	log_pond()
	west_bank()
	bunkhouse()
	east_bank()
	dry_kilns()
	rain_storage()
	cutting_shed()
	loading_apron()
	story()
	cast()
	detail()
	polish()
	return [64.5, 81.5, -PI / 2]


# ------------------------------------------------------------------- areas


func delivery_yard() -> void:
	b.yard(4, 66, 124, 84, "mill_grit", yard)
	b.paint(58, 66, 70, 84, "tracks")
	b.paint(20, 74, 108, 76, "tracks")
	b.arch(64.0, 84.4, 3.45, "route_hub")
	b.board("hub_road_stake", 66.2, 83.4, .97, {"plane": PI, "back": "hub_road_stake_back"})
	b.board("mill_entry", 64.0, 72.5, 1.2, {"z": 1.3, "plane": 0.0})
	b.fixture(61.9, 71.9, 62.1, 72.1, 2.5, "mill_log", "mill_log")
	b.fixture(65.9, 71.9, 66.1, 72.1, 2.5, "mill_log", "mill_log")
	# Log trucks waiting at the scale, deck stacks, puddles that never drain.
	b.town("dump_truck", 46.5, 70.5, {"solid": .45})
	b.town("lumber_cart", 80.5, 70.5, {"solid": .45})
	for p in [
		Vector2(20.5, 69.5),
		Vector2(24.5, 80.5),
		Vector2(100.5, 69.5),
		Vector2(108.5, 80.5),
		Vector2(36.5, 80.5)
	]:
		b.town("log_pile", p.x, p.y, {"solid": .45})
	for k in 10:
		b.mark("detail_wear_silt", 12.0 + k * 11.0, 68.0 + (k % 3) * 5.0, k * .7, 2.0, .9)
	b.paint(28, 70, 32, 72, "mill_oil")
	b.paint(90, 78, 95, 81, "mill_oil")
	# The truck scale and its shack.
	b.building(
		84,
		76,
		94,
		83,
		scale,
		{
			"wall": "mill_tin",
			"roof": 2.2,
			"floor": "concrete",
			"light": .78,
			"skin": "office_wall",
			"windows": 3
		}
	)
	b.door(84, 79, true, {"from": "e", "id": "scale-door"})
	b.paint(71, 76, 81, 79, "steel_mesh")
	b.board("wing_mill_ledger", 89.0, 76.04, .8, {"z": 1.2, "plane": PI})
	b.table(86.0, 81.2, 90.0, 82.0, .82)
	b.react("tv", 87.0, 81.6, .75, {"z": .82, "id": "x2-sawmill-0"})
	b.prop("lamp", 89.0, 79.5)
	b.town("pallet_stack", 52.5, 81.5, {"solid": .45})
	b.poles(
		[
			Vector2(10.5, 66.5),
			Vector2(30.5, 66.5),
			Vector2(50.5, 66.5),
			Vector2(78.5, 66.5),
			Vector2(98.5, 66.5),
			Vector2(118.5, 66.5)
		]
	)
	b.streetlamp(60.0, 70.0)
	b.streetlamp(68.0, 78.0)
	b.streetlamp(30.0, 76.0)
	b.streetlamp(104.0, 76.0)


func log_pond() -> void:
	b.yard(37, 29, 91, 29, "mill_grit", pond)
	b.yard(36, 30, 92, 65, "mill_water", pond)
	b.raise(36, 30, 92, 65, -.24)
	# Banks of mud all round, a step down to the water.
	for x in range(36, 93):
		for y in [30, 65]:
			b.raise(x, y, x, y, -.12)
			b.paint(x, y, x, y, "mill_grit")
	for y in range(30, 66):
		for x in [36, 92]:
			b.raise(x, y, x, y, -.12)
			b.paint(x, y, x, y, "mill_grit")
	# Boardwalks across: the main one north, one west, one east.
	b.paint(62, 31, 66, 64, "porch")
	b.raise(62, 31, 66, 64, 0.0)
	b.paint(37, 46, 61, 48, "porch")
	b.raise(37, 46, 61, 48, 0.0)
	b.paint(67, 40, 91, 42, "porch")
	b.raise(67, 40, 91, 42, 0.0)
	for k in 8:
		var y := 33.5 + k * 4.0
		b.fixture(61.43, y - .06, 61.57, y + .06, 1.0, "mill_log", "mill_log", -.24)
		b.fixture(66.43, y - .06, 66.57, y + .06, 1.0, "mill_log", "mill_log", -.24)
	# Logs afloat, pilings, the boom chain.
	for c in [
		[42.0, 36.0],
		[50.0, 54.0],
		[74.0, 56.0],
		[84.0, 34.0],
		[46.0, 60.0],
		[80.0, 50.0],
		[56.0, 38.0],
		[72.0, 34.0]
	]:
		b.fixture(c[0], c[1] + .35, c[0] + 3.0, c[1] + .65, -.08, "mill_log", "mill_log", -.24)
	for p in [
		Vector2(40.5, 44.5),
		Vector2(58.5, 52.5),
		Vector2(70.5, 46.5),
		Vector2(88.5, 58.5),
		Vector2(52.5, 32.5)
	]:
		b.board("mill_pilings", p.x, p.y, .9)
	b.board("mill_overflow", 63.5, 30.6, .7, {"z": .4, "plane": 0.0})
	for p in [Vector2(38.0, 52.0), Vector2(90.0, 36.0), Vector2(40.0, 33.0), Vector2(89.0, 62.0)]:
		b.prop("reeds", p.x, p.y)
	b.streetlamp(64.0, 46.0)
	b.streetlamp(64.0, 58.0)
	b.distant_cues.append([50.0, 50.0, "distant_mill_timber"])
	b.distant_cues.append([6.5, 44.0, "distant_mill_flume"])


func west_bank() -> void:
	b.yard(4, 30, 35, 65, "mill_grit", west)
	b.fence(4, 29, 35, 29, 1.6, "mill_log")
	b.yard(14, 29, 16, 29, "tracks", west)
	b.paint(16, 30, 20, 65, "tracks")
	# The flume: a timber channel up on legs down the west edge, water in it.
	b.yard(5, 30, 8, 64, "mill_water", flume)
	b.raise(5, 30, 8, 64, .48)
	b.wall(9, 30, 9, 64, "mill_log", 1.0)
	b.yard(9, 50, 9, 52, "mill_grit", west)
	b.raise(9, 50, 9, 52, .24)
	b.raise(10, 50, 11, 52, .12)
	# The sluice house: where the west feed is isolated.
	b.building(
		6,
		16,
		18,
		25,
		west,
		{
			"wall": "mill_tin",
			"roof": 2.4,
			"floor": "mill_oil",
			"light": .72,
			"skin": "mill_tin",
			"windows": 3
		}
	)
	b.door(12, 16, false, {"from": "s", "id": "sluice-door"})
	b.station(
		"west",
		9.5,
		22.5,
		"ISOLATE WEST FEED",
		"WEST FEED ISOLATED. SERVICE GATE OPEN.",
		{"opens": [[36, 17]], "sectors": [west], "cue": "mill_isolate"}
	)
	b.board("mill_control", 9.5, 24.1, 1.12, {"signal": "west"})
	b.board("mill_west_arrow", 12.0, 15.96, .6, {"z": 1.6, "plane": PI})
	b.fixture(13.0, 23.2, 17.0, 24.0, 1.0, "mill_pump", "tin")
	b.board("detail_sluice_winder", 15.0, 23.6, .5, {"z": 1.0})
	b.react("pipe", 16.5, 18.5, .9, {"id": "mill-leaky-standpipe"})
	b.ruptures["mill-leaky-standpipe"] = [16.5, 18.5, "STANDPIPE SHUDDERS. STEP OFF THE GRATE."]
	b.prop("lamp", 12.0, 20.5)
	# The bank: log decks, the saw-doctor's stump, a skiff pulled up.
	for p in [Vector2(28.5, 34.5), Vector2(28.5, 58.5), Vector2(12.5, 40.5)]:
		b.town("log_pile", p.x, p.y, {"solid": .45})
	b.town("axe_stump", 24.5, 50.5, {"solid": .3})
	b.fixture(30.0, 47.3, 33.0, 47.7, .45, "wood", "wood")
	b.town("lantern_post", 32.5, 44.5, {"solid": .1, "glow": true})
	b.town("lantern_post", 32.5, 52.5, {"solid": .1, "glow": true})
	b.glow(32.5, 44.5, 3.0, .25)
	b.glow(32.5, 52.5, 3.0, .25)
	b.secret(6, 20, true, [4, 19, 5, 21], {"from": "e", "id": "dry-alcove", "tile": "mill_tin"})
	b.room(4, 19, 5, 21, "mill_oil", west, {"roof": 2.2, "light": .5})
	b.wall(4, 18, 5, 18, "mill_tin", 2.5)
	b.wall(4, 22, 5, 22, "mill_tin", 2.5)
	b.streetlamp(20.0, 46.0)
	b.streetlamp(26.0, 62.0)


func bunkhouse() -> void:
	b.yard(4, 2, 35, 28, "mill_grit", bunk)
	b.fence(36, 2, 36, 5, 1.6, "mill_log")
	b.building(
		6,
		4,
		22,
		13,
		bunk,
		{
			"wall": "wood",
			"roof": 2.3,
			"floor": "porch",
			"light": .72,
			"skin": "detail_wall_shed_repair",
			"windows": 0
		}
	)
	for x in [9, 13, 17]:
		b.wall(x, 4, x, 4, "window", 2.6)
	b.door(14, 13, false, {"from": "n", "id": "bunk-door"})
	b.interiors.append(["break", 12.0, 4.05, .73, .54, 0.0])
	for k in 4:
		b.fixture(7.1, 5.2 + k * 2.0, 9.0, 6.0 + k * 2.0, .6, "wood", "counter_top")
	b.table(14.0, 7.0, 18.0, 8.0, .78)
	b.notes.append(
		[
			16.0,
			7.6,
			"SHIFT TICKET",
			"BLUE TRUNK / WENT TO STILLWATER. TAG TOO TOUGH FOR THE SAW.",
			0.0
		]
	)
	b.board("county_note", 16.0, 7.1, .3, {"z": .78, "plane": 0.0})
	b.react("cancan", 19.5, 11.0, .4, {"id": "x2-sawmill-1"})
	b.react("jukebox", 21.0, 5.0, 1.4, {"id": "x2-sawmill-5"})
	b.prop("lamp", 14.0, 9.0)
	b.prop("lamp", 9.0, 9.0)
	# Out back: the outhouse, the wash tub, the firewood and the axes.
	b.town("outhouse", 30.5, 4.5, {"solid": .4})
	b.town("bathtub", 26.5, 10.5, {"solid": .45})
	b.town("axe_stump", 30.5, 16.5, {"solid": .3})
	b.town("log_pile", 26.5, 22.5, {"solid": .45})
	b.town("lantern_post", 20.5, 18.5, {"solid": .1, "glow": true})
	b.glow(20.5, 18.5, 3.0, .25)
	b.town("chicken_coop", 30.5, 24.5, {"solid": .45})
	b.react("toilet", 30.0, 6.4, .82, {"id": "x2-sawmill-3"})
	b.streetlamp(22.0, 15.0)


func east_bank() -> void:
	b.yard(93, 30, 126, 49, "mill_grit", east)
	b.paint(93, 40, 126, 42, "tracks")
	b.fence(93, 29, 126, 29, 1.6, "mill_log")
	b.yard(123, 29, 125, 29, "tracks", east)
	# The green chain: a long open shed where boards come off the rollers.
	b.room(97, 32, 120, 38, "mill_oil", sort, {"roof": 2.6, "ceiling": "mill_tin", "light": .78})
	for x in [97.0, 103.0, 109.0, 115.0, 121.0]:
		for y in [32.0, 39.0]:
			b.fixture(x - .07, y - .07, x + .07, y + .07, 2.6, "mill_log", "mill_log")
	for y in [33.5, 36.5]:
		b.fixture(98.0, y - .3, 119.0, y + .3, .82, "steel_mesh", "mill_log")
	b.board("wing_mill_sort", 108.0, 32.06, .8, {"z": 1.5, "plane": 0.0})
	b.board("wing_mill_sort_rollers", 104.0, 35.0, .6, {"z": .82})
	b.board("detail_sort_chain_box", 116.0, 35.0, .5, {"z": .82})
	for p in [Vector2(99.5, 44.5), Vector2(113.5, 45.5), Vector2(123.5, 34.5)]:
		b.town("lumber_cart", p.x, p.y, {"solid": .45})
	b.town("forklift", 106.5, 45.5, {"solid": .45})
	b.react("scrap", 95.0, 36.0, .71, {"id": "mill-log-scrap"})
	b.exchanges.append(
		{
			"id": "sort-radio",
			"x": 108.0,
			"y": 38.6,
			"stop_at": "",
			"lines": ["RADIO: HEAR THAT BELT?", "VOICE: SOUNDS LIKE TEETH."]
		}
	)
	b.streetlamp(100.0, 41.0)
	b.streetlamp(118.0, 41.0)


func dry_kilns() -> void:
	b.yard(93, 2, 126, 28, "mill_grit", kilns)
	b.fence(93, 2, 93, 15, 1.6, "mill_log")
	b.fence(93, 19, 93, 28, 1.6, "mill_log")
	# Three brick kilns, glowing at the doors, and the belt that feeds them.
	for k in 3:
		var x0 := 96 + k * 10
		b.building(
			x0,
			4,
			x0 + 7,
			13,
			kilns,
			{
				"wall": "brick",
				"roof": 2.8,
				"floor": "concrete",
				"light": 1.1,
				"skin": "detail_wall_kiln_patches"
			}
		)
		b.door(x0 + 3, 13, false, {"from": "n", "id": "kiln-%d" % k, "opened": true})
		b.glow(x0 + 3.5, 14.0, 3.0, .4)
		b.board("wing_mill_kiln", x0 + 3.5, 14.06, .7, {"z": 1.9, "plane": 0.0})
		b.tower(x0 + 3.0, 6.0, x0 + 4.0, 7.0, 3.08, 4.6, "brick")
	# The belt and its release, struck by a shot or a swing.
	b.fixture(96.0, 20.3, 118.0, 20.9, .7, "steel_mesh", "mill_log")
	b.react(
		"belt",
		99.5,
		21.6,
		.73,
		{"id": "mill-drive-belt-release", "z": .55, "radius": .29, "station": "east"}
	)
	b.station(
		"east",
		99.5,
		21.5,
		"STRIKE THE KILN BELT RELEASE",
		"KILN STOPPED. THE RETURN SHUTTER IS OPEN.",
		{"opens": [[92, 17]], "sectors": [east, kilns], "cue": "brake_ratchet", "action": "strike"}
	)
	b.board("mill_control", 101.5, 22.6, 1.11, {"signal": "east"})
	b.board("wing_mill_belt", 97.5, 20.2, .8, {"z": 1.2, "plane": 0.0, "signal": "east"})
	b.board("mill_east_arrow", 124.0, 28.6, .6, {"z": 1.0, "plane": 0.0})
	b.board("detail_kiln_duct", 116.0, 13.94, .5, {"z": 1.0, "plane": PI})
	for p in [Vector2(98.5, 25.5), Vector2(122.5, 25.5), Vector2(124.5, 16.5)]:
		b.town("pallet_stack", p.x, p.y, {"solid": .45})
	b.exchanges.append(
		{
			"id": "kiln-radio",
			"x": 104.0,
			"y": 24.0,
			"stop_at": "",
			"lines": ["RADIO: KILL THE DRIVE.", "VOICE: YOU FIRST."]
		}
	)
	b.streetlamp(105.0, 17.0)
	b.streetlamp(118.0, 25.0)


func rain_storage() -> void:
	b.yard(93, 50, 126, 65, "mill_grit", storage)
	b.fence(93, 49, 106, 49, 1.24, "mill_log")
	b.fence(110, 49, 126, 49, 1.24, "mill_log")
	# Long open sheds of drying stacks, the rain off their edges.
	for y0 in [52, 59]:
		b.room(
			96,
			y0,
			123,
			y0 + 4,
			"mill_grit",
			storage,
			{"roof": 2.4, "ceiling": "mill_tin", "light": .8}
		)
		for x in [96.0, 103.0, 110.0, 117.0, 124.0]:
			b.fixture(x - .07, y0 - .07, x + .07, y0 + .07, 2.4, "mill_log", "mill_log")
			b.fixture(x - .07, y0 + 4.93, x + .07, y0 + 5.07, 2.4, "mill_log", "mill_log")
		for x in [99.5, 106.5, 113.5, 120.5]:
			b.town("log_pile" if int(x) % 2 else "pallet_stack", x, y0 + 2.5, {"solid": .45})
	b.board("wing_mill_rain", 109.0, 49.94, .8, {"z": 1.1, "plane": PI})
	b.board("detail_rain_stock", 101.0, 57.2, .5)
	b.board("county_mill_bypass", 94.0, 64.6, .9, {"z": .2, "plane": PI / 2})
	b.secret(
		126,
		61,
		true,
		[127, 60, 128, 62],
		{"from": "w", "id": "dry-stacks-breakout", "tile": "mill_log"}
	)
	b.room(127, 60, 128, 62, "mill_grit", storage, {"roof": 2.2, "light": .5})
	b.streetlamp(108.0, 57.0)


func cutting_shed() -> void:
	b.building(
		36,
		6,
		92,
		28,
		shed,
		{
			"wall": "mill_tin",
			"roof": 3.2,
			"parapet": .5,
			"floor": "mill_oil",
			"ceiling": "mill_tin",
			"windows": 5,
			"lit": .6,
			"light": .74,
			"skin": "detail_wall_rain_sheets"
		}
	)
	b.controlled(36, 17, true, {"from": "e", "id": "west-service-loop", "tile": "gate"})
	b.controlled(92, 17, true, {"from": "w", "id": "east-service-loop", "tile": "gate"})
	b.door(64, 28, false, {"from": "n", "id": "shed-south", "style": "slide"})
	b.yard(35, 15, 35, 19, "mill_grit", bunk)
	b.board("mill_shed", 64.0, 29.0, 1.1, {"z": 2.0, "plane": 0.0})
	# The log carriage on its track, the head saw, the gang saws, the chains.
	b.paint(40, 19, 88, 22, "tracks")
	b.town("saw_blade", 52.5, 18.5, {"solid": .45})
	b.town("saw_blade", 76.5, 18.5, {"solid": .45})
	b.fixture(58.0, 20.2, 70.0, 21.8, .7, "mill_log", "mill_log")
	b.station(
		"brake",
		64.5,
		23.5,
		"RELEASE THE LOG CARRIAGE BRAKE",
		"CARRIAGE STOPPED. PUMP HOUSE ACCESS OPEN.",
		{
			"requires": ["west", "east"],
			"opens": [[64, 14]],
			"sectors": [shed],
			"cue": "brake_ratchet"
		}
	)
	b.board("mill_brake", 63.0, 22.1, .98, {"signal": "brake"})
	b.board("mill_saw", 52.5, 17.0, 1.0, {"z": 2.0})
	b.board("detail_carriage_tools", 70.5, 22.4, .5, {"z": .7})
	for p in [Vector2(42.5, 24.5), Vector2(86.5, 24.5), Vector2(44.5, 9.5), Vector2(84.5, 9.5)]:
		b.town("log_pile", p.x, p.y, {"solid": .45})
	b.town("sawdust_pile", 48.5, 25.5, {"solid": .45})
	b.town("sawdust_pile", 80.5, 25.5, {"solid": .45})
	for x in [44.0, 56.0, 72.0, 84.0]:
		b.fixture(x - .1, 13.9, x + .1, 14.1, 3.2, "mill_log", "mill_log")
	for p in [
		Vector2(46.0, 18.0),
		Vector2(64.0, 25.0),
		Vector2(82.0, 18.0),
		Vector2(50.0, 11.0),
		Vector2(78.0, 11.0)
	]:
		b.prop("lamp", p.x, p.y)
		b.glow(p.x, p.y, 3.2, .18)
	b.react("vending", 38.0, 26.4, 1.5, {"id": "x2-sawmill-2"})
	b.react("window", 90.6, 25.0, 1.2, {"id": "x2-sawmill-4"})
	# The pump house in the north middle: the relay that runs it all.
	b.wall(57, 7, 57, 14, "mill_pump", 3.6)
	b.wall(71, 7, 71, 14, "mill_pump", 3.6)
	b.wall(58, 14, 70, 14, "mill_pump", 3.6)
	b.room(58, 7, 70, 13, "concrete", pump, {"roof": 2.6, "skin": "mill_pump", "light": .8})
	b.controlled(64, 14, false, {"from": "s", "id": "pump-entry", "tile": "gate"})
	b.station(
		"relay",
		64.5,
		9.5,
		"SHUT DOWN THE MILL RELAY",
		"SPLINTER FOREMAN! WATCH THE CUT MARKS.",
		{
			"requires": ["west", "east", "brake"],
			"opens": [[76, 6], [88, 6]],
			"sectors": [shed, pump],
			"cue": "mill_trip"
		}
	)
	b.board("mill_relay", 63.0, 7.1, 1.54, {"signal": "relay"})
	b.board("mill_pump_sign", 64.0, 14.6, .7, {"z": 1.6, "plane": 0.0})
	b.board("detail_pump_manifold", 68.0, 7.4, .5, {"z": .8})
	b.secret(71, 11, true, [72, 10, 73, 12], {"from": "w", "id": "pump-cache", "tile": "mill_pump"})
	b.wall(71, 9, 74, 9, "mill_pump", 3.6)
	b.wall(71, 13, 74, 13, "mill_pump", 3.6)
	b.wall(74, 10, 74, 12, "mill_pump", 3.6)
	b.room(72, 10, 73, 12, "concrete", pump, {"roof": 2.4, "light": .5})
	b.prop("lamp", 61.0, 10.0)
	b.prop("lamp", 67.0, 10.0)
	b.distant_cues.append([64.5, 9.5, "distant_mill_pump"])
	b.wall(37, 24, 39, 24, "mill_tin", 3.6)
	b.wall(39, 25, 39, 27, "mill_tin", 3.6)
	b.room(37, 25, 38, 27, "mill_oil", shed, {"roof": 2.2, "light": .5})
	b.secret(39, 26, true, [37, 25, 38, 27], {"from": "e", "id": "log-cache", "tile": "mill_tin"})
	b.controlled(76, 6, false, {"from": "s", "id": "apron-west", "tile": "gate"})
	b.wall(60, 1, 60, 5, "mill_log", 1.6)
	b.yard(60, 3, 60, 3, "tracks", apron)
	b.controlled(88, 6, false, {"from": "s", "id": "apron-east", "tile": "gate"})


func loading_apron() -> void:
	b.yard(37, 1, 91, 5, "concrete", apron)
	b.paint(40, 2, 88, 4, "tracks")
	b.board("mill_exit", 39.5, 1.6, .78, {"z": .71, "plane": 0.0, "signal": "exit"})
	b.town("lumber_cart", 45.5, 3.5, {"solid": .45})
	b.town("forklift", 82.5, 3.5, {"solid": .45})
	b.board("detail_apron_blade_rack", 70.0, 1.4, .5, {"plane": 0.0})
	b.board("detail_delivery_chocks", 58.0, 4.4, .45)
	b.streetlamp(56.0, 3.0)
	b.streetlamp(73.0, 3.0)


func story() -> void:
	for l in [
		["YARD", 60, 78],
		["SCALE", 86, 80],
		["POND", 46, 40],
		["WEST", 14, 46],
		["FLUME", 5, 44],
		["BUNKS", 10, 16],
		["SORT", 104, 42],
		["KILNS", 104, 16],
		["STACKS", 104, 56],
		["SHED", 46, 16],
		["PUMP", 60, 11],
		["APRON", 40, 3],
	]:
		b.label(String(l[0]), int(l[1]), int(l[2]))
	b.fuel_drums.append([94.5, 48.0])
	b.fuel_drums.append([40.5, 26.6])
	b.fuel_drums.append([88.5, 26.6])
	for p in [Vector2(94.4, 47.2), Vector2(39.6, 26.2), Vector2(89.4, 26.2)]:
		b.prop("barrel", p.x, p.y)


func cast() -> void:
	for e in [
		["clone", 62.0, 70.5, "yard-clone"],
		["coot", 46.0, 77.5, "yard-coot"],
		["millhand", 88.0, 72.0, "scale-millhand"],
		["skeeter", 30.0, 72.0, "yard-skeeter"],
		["lantern", 74.0, 66.6, "bank-lantern"],
		["skeeter", 52.0, 44.0, "pond-skeeter"],
		["lantern", 64.0, 39.0, "pond-lantern"],
		["lantern", 80.0, 45.5, "pond-bank-lantern"],
		["alien", 44.0, 47.0, "pond-alien"],
		["millhand", 18.0, 47.0, "west-millhand"],
		["coot", 28.0, 40.0, "west-coot"],
		["chain_hand", 12.5, 21.5, "sluice-chain"],
		["billy", 26.0, 61.0, "bank-billy"],
		["lantern", 7.0, 40.0, "flume-lantern"],
		["coot", 14.0, 16.0, "bunk-coot"],
		["billy", 25.0, 20.0, "bunk-billy"],
		["clone", 11.5, 10.0, "bunkroom-clone"],
		["skeeter", 30.0, 12.0, "outhouse-skeeter"],
		["billy", 104.0, 44.0, "east-billy"],
		["lantern", 115.0, 42.5, "east-lantern"],
		["clone", 120.0, 46.0, "east-clone"],
		["millhand", 108.0, 35.0, "sortyard-millhand"],
		["chain_hand", 100.0, 26.0, "kiln-chain"],
		["coot", 115.0, 17.0, "kiln-hand"],
		["lantern", 106.5, 15.5, "drying-lantern"],
		["alien", 122.0, 8.0, "kiln-alien"],
		["billy", 100.0, 57.0, "stack-billy"],
		["coot", 118.0, 63.5, "spill-track-coot"],
		["millhand", 113.0, 55.5, "stack-millhand"],
		["skeeter", 108.0, 58.0, "stack-skeeter"],
		["alien", 40.0, 17.0, "shed-guard"],
		["billy", 62.0, 17.0, "shed-billy"],
		["chain_hand", 82.0, 21.0, "shed-chain"],
		["millhand", 70.0, 25.0, "shed-millhand"],
		["coot", 48.0, 10.0, "shed-coot"],
		["skeeter", 64.0, 8.0, "mill-roof-skeeter"],
		["coot", 66.5, 11.5, "pump-coot"],
		["alien", 47.0, 21.0, "wave-guard"],
		["millhand", 81.0, 13.0, "wave-millhand"],
		["billy", 48.0, 15.5, "wave-billy"],
		["lantern", 78.0, 22.0, "wave-lantern"],
		["foreman", 64.5, 16.5, "loading-foreman"],
		["coot", 60.0, 3.0, "apron-coot"],
		["millhand", 70.0, 3.0, "stack-rifle"],
	]:
		b.enemy(String(e[0]), float(e[1]), float(e[2]), String(e[3]))
	b.partners.append(["east-billy", "east-lantern", -1])
	for p in [
		["shells", 64.6, 76.0],
		["rinds", 57.0, 80.0],
		["bullets", 70.0, 70.0],
		["beer", 88.0, 80.5],
		["shotgun", 92.6, 78.0],
		["shells", 40.0, 70.0],
		["whiskey", 108.0, 70.0],
		["rinds", 22.0, 79.0],
		["shells", 64.0, 52.0],
		["rinds", 64.5, 34.0],
		["bullets", 50.0, 47.0],
		["beer", 85.0, 41.0],
		["rifle", 15.5, 19.0],
		["rifle_ammo", 8.0, 18.0],
		["moonshine", 4.6, 20.0],
		["saw_ammo", 5.4, 20.6],
		["shells", 30.0, 54.0],
		["rinds", 14.0, 62.0],
		["whiskey", 24.0, 44.0],
		["cowpie", 7.0, 52.0],
		["beer", 16.0, 5.6],
		["rifle_ammo", 20.0, 9.0],
		["rinds", 8.0, 11.0],
		["bullets", 28.0, 22.0],
		["riveter", 118.0, 35.0],
		["rivet_ammo", 99.0, 38.0],
		["shells", 124.0, 44.0],
		["beer", 95.0, 32.0],
		["rivet_ammo", 101.0, 16.0],
		["rifle_ammo", 120.0, 18.0],
		["rinds", 96.0, 26.0],
		["dynamite", 124.0, 10.0],
		["arm_ammo", 127.6, 61.0],
		["bowling_ammo", 128.4, 60.4],
		["whiskey", 110.0, 51.0],
		["shells", 98.0, 63.0],
		["milk_ammo", 117.0, 62.6],
		["rinds", 125.0, 51.0],
		["cow_ammo", 37.6, 25.6],
		["rifle_ammo", 38.4, 26.6],
		["shells", 40.0, 12.0],
		["rinds", 88.0, 12.0],
		["rivet_ammo", 64.0, 26.5],
		["beer", 56.0, 26.0],
		["whiskey", 72.0, 8.0],
		["moonshine", 72.6, 10.6],
		["shells", 73.4, 11.6],
		["rinds", 49.0, 2.4],
		["rifle_ammo", 86.0, 2.6],
	]:
		b.pickup(String(p[0]), float(p[1]), float(p[2]))
	(
		b
		. triggers
		. append(
			{
				"id": "flume-burst",
				"when": {"area": [10, 44, 34, 56]},
				"do":
				[
					{"message": "THE FLUME GROANS. SOMETHING'S RIDING IT DOWN.", "for": 3.0},
					{"sound": "distant_mill_flume", "at": [6.5, 46.0]},
					{"sound": "thunder"},
					{"alert": 12}
				],
			}
		)
	)
	(
		b
		. triggers
		. append(
			{
				"id": "kilns-hot",
				"when": {"area": [95, 15, 125, 27]},
				"do":
				[
					{"message": "THE KILNS ARE STILL BURNING. SO'S THE CREW.", "for": 3.0},
					{"alert": 12}
				],
			}
		)
	)


## The last pass: timber everywhere a mill keeps it, and light to see it by.
func detail() -> void:
	b.lamp_grid(8, 68, 120, 82, 10)
	b.lamp_grid(12, 31, 34, 64, 9)
	b.lamp_grid(94, 30, 124, 48, 9)
	b.lamp_grid(6, 14, 34, 27, 9)
	b.clutter(
		6,
		67,
		122,
		83,
		["log_pile", "pallet_stack", "lumber_cart", "axe_stump", "prop:barrel", "prop:crate"],
		18
	)
	b.clutter(
		11, 30, 34, 64, ["log_pile", "axe_stump", "pallet_stack", "lantern_post", "prop:barrel"], 10
	)
	b.clutter(94, 39, 125, 48, ["lumber_cart", "pallet_stack", "log_pile", "prop:barrel"], 8)
	b.clutter(94, 14, 125, 27, ["pallet_stack", "prop:barrel", "log_pile"], 6)
	b.clutter(
		5, 14, 34, 27, ["axe_stump", "log_pile", "prop:barrel", "chicken_coop", "tire_stack"], 6
	)
	b.clutter(
		38,
		8,
		90,
		27,
		["log_pile", "sawdust_pile", "pallet_stack", "lumber_cart", "prop:barrel", "prop:crate"],
		14
	)
	b.clutter(38, 1, 90, 5, ["pallet_stack", "prop:crate"], 4)
	for e in [
		["chain_hand", 34.0, 76.0, "yard-chain"],
		["lantern", 100.0, 74.0, "scale-lantern"],
		["coot", 20.0, 33.0, "flume-coot"],
	]:
		b.enemy(String(e[0]), float(e[1]), float(e[2]), String(e[3]))


## The polish pass: the pond and the yards full of what a mill floats,
## stacks and leaves lying.
func polish() -> void:
	# Log rafts and boom logs across the open water.
	for c in [
		[40.0, 40.0],
		[52.0, 58.0],
		[76.0, 60.0],
		[86.0, 46.0],
		[70.0, 36.0],
		[48.0, 34.0],
		[80.0, 54.0],
		[56.0, 44.0]
	]:
		b.fixture(c[0], c[1] + .3, c[0] + 4.0, c[1] + .7, -.06, "mill_log", "mill_log", -.24)
		b.fixture(c[0] + .5, c[1] + 1.3, c[0] + 3.5, c[1] + 1.7, -.06, "mill_log", "mill_log", -.24)
	# Log decks in the delivery yard: long low walls of stacked logs.
	for c in [
		[10, 68, 18, 69], [10, 81, 18, 82], [96, 68, 104, 69], [110, 81, 118, 82], [40, 81, 46, 82]
	]:
		b.wall(c[0], c[1], c[2], c[3], "mill_log", 1.3)
	# An open truck shed by the scale.
	b.room(72, 68, 80, 72, "mill_grit", yard, {"roof": 2.6, "ceiling": "mill_tin", "light": .85})
	for x in [72.0, 76.0, 81.0]:
		for y in [68.0, 73.0]:
			b.fixture(x - .07, y - .07, x + .07, y + .07, 2.6, "mill_log", "mill_log")
	var timber := [
		"log_pile", "pallet_stack", "axe_stump", "prop:barrel", "prop:crate", "lumber_cart"
	]
	var themes := {
		yard: timber + ["dump_truck", "sawdust_pile"],
		pond: ["board:mill_pilings@.9", "prop:reeds", "board:prop_reeds@.9"],
		west: timber + ["lantern_post"],
		east: timber + ["forklift"],
		bunk: ["axe_stump", "log_pile", "chicken_coop", "tire_stack", "prop:barrel"],
		kilns: ["pallet_stack", "log_pile", "prop:barrel"],
		storage: ["pallet_stack", "log_pile"],
		shed: ["log_pile", "sawdust_pile", "pallet_stack", "lumber_cart", "prop:barrel"],
		apron: ["pallet_stack", "prop:crate", "lumber_cart"],
		sort: ["pallet_stack", "lumber_cart"],
		scale: ["prop:crate"],
	}
	var marks := {
		yard: ["detail_wear_silt", "detail_wear_sawdust"],
		west: ["detail_wear_silt"],
		east: ["detail_wear_sawdust"],
		shed: ["detail_wear_sawdust", "detail_wear_oil"],
		kilns: ["detail_wear_sawdust"],
		apron: ["detail_wear_oil"],
	}
	var filled := b.fill_empty(themes, 4, marks)
	var again := b.fill_empty(themes, 3, marks)
	filled.y = again.y
	print("sawmill: empty ground %d -> %d" % [filled.x, filled.y])
	for e in [
		["chain_hand", 76.0, 70.5, "shed-chain-b"],
		["lantern", 70.0, 50.0, "raft-lantern"],
		["millhand", 104.0, 26.0, "kiln-hand-b"],
	]:
		b.enemy(String(e[0]), float(e[1]), float(e[2]), String(e[3]))
	(
		b
		. triggers
		. append(
			{
				"id": "truck-shed",
				"when": {"area": [70, 67, 82, 74]},
				"do":
				[
					{"message": "THE SHIFT CHANGE IS RUNNING LATE.", "for": 2.5},
					{"wake": ["shed-chain-b"]},
					{"alert": 10}
				],
			}
		)
	)
