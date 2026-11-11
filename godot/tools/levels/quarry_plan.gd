## Stillwater Cut, rebuilt (layout 2): a limestone quarry with a bootleg
## works hidden in it, chalk on everything, a cold blue sky. The county weigh
## station in the south and the haul road up; the cut yard with its blocks,
## rigs and the crusher; the cutting shed west (disengage the cutting feed)
## under the chalk terraces and the dynamite shack; the lower cut east, a pit
## stepped down to a flooded bottom, and up out of it the condenser yard
## (crank the copper condenser) and copper recovery; the bottling works in the
## north (vent the relay: the baron) and the loading court behind, where the
## relief valves are and the load ticket gets signed.
##
## Built by tools/levels/build_level.gd -- quarry.
extends RefCounted

const Builder := preload("res://tools/levels/level_builder.gd")
const W := 130
const H := 86

var b: Builder
var weigh: int
var cut: int
var shed: int
var condenser: int
var bottling: int
var court: int
var lower: int
var terraces: int
var copper: int
var haul: int
var powder: int
var flooded: int


func make() -> Builder:
	b = Builder.new("quarry", W, H, "quarry_face")
	b.riser_tiles = {
		"quarry_dust": "quarry_face", "quarry_face": "quarry_face", "gravel": "quarry_face"
	}
	b.meta = {
		"title": "STILLWATER CUT",
		"heading": ["STILLWATER CUT", "BOOTLEG WORKS"],
		"intro": "STOP THE CUTTING FEED AND DIVERT THE COPPER CONDENSER.",
		"ending": '"WEIGHT INCLUDES CONTENTS AND DEBTS."',
		"score": "quarry_score",
		"ambience": "quarry",
		"layout": 2,
		"sky": "quarry_sky",
		"control_name": "QUARRY FEEDS ISOLATED",
		"extraction":
		{"x": 86.5, "y": 2.5, "label": "SIGN THE LOAD TICKET", "shutdown": "bottling"},
		"return_gate": {"destination": "hub", "x": 64.0, "y": 84.4, "width": 3.5, "side": -1},
		"recovery_room": [57.4, 74.4, 62.6, 78.6, "room"],
		"pressure_ports": [[48.5, 3.5], [56.5, 2.5], [72.5, 2.5], [80.5, 3.5]],
		"wave": ["court-guard", "court-clone", "court-center", "court-billy"],
	}
	return b


func build(_b) -> Array:
	weigh = b.district("COUNTY WEIGH STATION", Color(.96, .98, 1.04))
	cut = b.district("LIMESTONE CUT YARD", Color(.94, .98, 1.06))
	shed = b.district("CUTTING SHED", Color(1.02, .98, .94))
	condenser = b.district("CONDENSER YARD", Color(1.06, .96, .88))
	bottling = b.district("BOTTLING WORKS", Color(1.04, 1.0, .9))
	court = b.district("LOADING COURT", Color(.94, .98, 1.06))
	lower = b.district("LOWER CUT", Color(.88, .96, 1.08))
	terraces = b.district("CHALK TERRACES", Color(.98, 1.0, 1.06))
	copper = b.district("COPPER RECOVERY", Color(1.08, .96, .86))
	haul = b.district("HAUL ROAD", Color(.94, .96, 1.02))
	powder = b.district("DYNAMITE SHACK", Color(1.06, .96, .9))
	flooded = b.district("FLOODED PIT", Color(.84, .96, 1.06))
	weigh_station()
	haul_road()
	cut_yard()
	cutting_shed()
	chalk_terraces()
	lower_cut()
	condenser_yard()
	bottling_works()
	loading_court()
	story()
	cast()
	detail()
	polish()
	return [64.5, 81.5, -PI / 2]


# ------------------------------------------------------------------- areas


func weigh_station() -> void:
	b.yard(36, 68, 92, 84, "quarry_dust", weigh)
	b.paint(60, 68, 68, 84, "tracks")
	b.arch(64.0, 84.4, 3.5, "route_hub")
	b.board("hub_road_stake", 66.2, 83.4, .97, {"plane": PI, "back": "hub_road_stake_back"})
	# The scale house: the weigh slip, two sets of books, a drawer that slides.
	b.building(
		54,
		73,
		63,
		79,
		weigh,
		{
			"wall": "quarry_shed",
			"roof": 2.3,
			"floor": "quarry_shed",
			"light": .8,
			"skin": "office_wall",
			"windows": 3
		}
	)
	b.door(63, 76, true, {"from": "w", "id": "scale-door"})
	b.interiors.append(["bunk", 58.0, 73.05, .83, .52, 0.0])
	b.table(55.2, 77.2, 58.8, 78.0, .82)
	b.notes.append(
		[
			57.0,
			77.6,
			"WEIGH SLIP",
			"BLUE TRUNK / ONE HOG TAG AND SIX EMPTY JUGS. BILL THE SHERIFF.",
			0.0
		]
	)
	b.board("county_note", 57.0, 77.2, .3, {"z": .82, "plane": 0.0})
	b.board("quarry_scale", 60.0, 73.06, .9, {"z": 1.0, "plane": 0.0})
	b.board("detail_scale_weights", 61.5, 77.6, .5, {"z": .0})
	b.station(
		"scale-drawer",
		55.6,
		74.6,
		"SLIDE THE SCALE DRAWER",
		"CACHE UNLATCHED. THE SCALE HOUSE KEEPS TWO SETS OF BOOKS.",
		{"opens": [[54, 75]], "hidden": true, "cue": "secret_slide"}
	)
	b.controlled(54, 75, true, {"from": "e", "id": "scale-cache"})
	b.room(51, 74, 53, 76, "quarry_shed", weigh, {"roof": 2.2, "light": .5, "skin": "quarry_shed"})
	b.wall(51, 73, 53, 73, "quarry_shed", 2.5)
	b.wall(51, 77, 53, 77, "quarry_shed", 2.5)
	b.wall(50, 74, 50, 76, "quarry_shed", 2.5)
	b.prop("lamp", 58.5, 76.0)
	b.react("tv", 56.0, 77.6, .75, {"z": .82, "id": "x2-quarry-0"})
	# The truck scale, the trucks, a jug crate for the inspector.
	b.paint(66, 74, 74, 80, "steel_mesh")
	b.town("dump_truck", 70.5, 77.5, {"solid": .45})
	b.town("dump_truck", 82.5, 72.5, {"solid": .45})
	b.town("jug_stack", 52.5, 70.5, {"solid": .4})
	b.town("warning_barrel", 76.5, 82.5, {"solid": .3})
	b.town("warning_barrel", 51.5, 82.5, {"solid": .3})
	b.town("outhouse", 40.5, 82.5, {"solid": .4})
	b.board("wing_quarry_weight", 64.0, 68.06, .8, {"z": 1.5, "plane": 0.0})
	b.fixture(61.9, 67.9, 62.1, 68.1, 2.4, "quarry_iron", "quarry_iron")
	b.fixture(65.9, 67.9, 66.1, 68.1, 2.4, "quarry_iron", "quarry_iron")
	b.poles([Vector2(38.5, 68.5), Vector2(52.5, 68.5), Vector2(76.5, 68.5), Vector2(90.5, 68.5)])
	b.streetlamp(60.0, 81.0)
	b.streetlamp(68.0, 71.0)
	b.streetlamp(46.0, 76.0)


func haul_road() -> void:
	# Up from the weigh station: the haul road climbs a bench into the cut.
	b.yard(60, 60, 68, 67, "gravel", haul)
	b.paint(62, 60, 66, 67, "tracks")
	b.raise(60, 64, 68, 65, .24)
	b.raise(60, 60, 68, 63, .48)
	b.fixture(59.4, 60.0, 59.6, 66.0, .9, "quarry_iron", "quarry_iron", .24)
	b.board("wing_quarry_danger", 68.94, 63.0, .7, {"z": 1.0, "plane": -PI / 2})
	b.town("warning_barrel", 60.5, 66.5, {"solid": .3})
	b.town("warning_barrel", 67.5, 66.5, {"solid": .3})


func cut_yard() -> void:
	b.yard(36, 34, 92, 59, "quarry_dust", cut)
	b.raise(36, 34, 92, 59, .48)
	b.paint(44, 46, 84, 48, "tracks")
	# Cut blocks stacked to dry, the drill rigs, the crusher, a mine cart run.
	for c in [
		[40.0, 36.0, 43.0, 38.0, 1.4],
		[46.0, 36.0, 50.0, 38.0, 1.0],
		[40.0, 52.0, 44.0, 55.0, 1.6],
		[80.0, 36.0, 84.0, 38.0, 1.2],
		[84.0, 52.0, 88.0, 55.0, 1.4],
		[72.0, 53.0, 75.0, 56.0, 1.0]
	]:
		b.fixture(c[0], c[1], c[2], c[3], c[4] + .48, "quarry_face", "quarry_face", .48)
	b.town("drill_rig", 54.5, 38.5, {"solid": .45})
	b.town("drill_rig", 76.5, 40.5, {"solid": .45})
	b.town("crusher", 64.5, 37.5, {"solid": .45})
	b.fixture(63.0, 36.0, 66.0, 39.0, .8, "quarry_iron", "quarry_iron", .48)
	b.town("mine_cart", 50.5, 47.5, {"solid": .45})
	b.town("mine_cart", 78.5, 47.5, {"solid": .45})
	b.town("cable_spool", 88.5, 44.5, {"solid": .45})
	for p in [Vector2(48.5, 56.5), Vector2(70.5, 42.5), Vector2(58.5, 52.5), Vector2(86.5, 40.5)]:
		b.town("boulder_a" if int(p.x) % 2 else "boulder_b", p.x, p.y, {"solid": .4})
	b.board("detail_cutting_drill", 56.0, 40.5, .5, {"z": .48})
	b.board("quarry_cut_arrow", 40.0, 47.0, .7, {"z": 1.4, "plane": -PI / 2})
	b.board("quarry_stills_arrow", 90.0, 47.0, .7, {"z": 1.4, "plane": PI / 2})
	b.react("pipe", 67.5, 53.5, .9, {"id": "quarry-cut-leak"})
	b.ruptures["quarry-cut-leak"] = [67.5, 53.5, "COPPER JOINT WHISTLES. GIVE IT ROOM."]
	b.distant_cues.append([64.5, 52.0, "distant_quarry_pipe"])
	b.poles([Vector2(38.5, 58.5), Vector2(52.5, 58.5), Vector2(76.5, 58.5), Vector2(90.5, 58.5)])
	for p in [Vector2(46.0, 44.0), Vector2(60.0, 50.0), Vector2(74.0, 44.0), Vector2(86.0, 50.0)]:
		b.streetlamp(p.x, p.y)


func cutting_shed() -> void:
	b.yard(6, 34, 35, 62, "quarry_dust", shed)
	b.raise(6, 34, 35, 62, .48)
	b.building(
		8,
		36,
		30,
		52,
		shed,
		{
			"wall": "quarry_shed",
			"roof": 3.0,
			"floor": "quarry_shed",
			"ceiling": "quarry_iron",
			"windows": 4,
			"light": .76,
			"skin": "detail_wall_chalk_cut",
			"ground": .48
		}
	)
	b.raise(9, 37, 29, 51, .48)
	b.door(19, 52, false, {"from": "n", "id": "shed-south"})
	b.raise(19, 52, 19, 52, .48)
	b.station(
		"stone",
		12.5,
		40.5,
		"DISENGAGE THE CUTTING FEED",
		"CUTTING FEED OFF. BENCH SHUTTER OPEN.",
		{"opens": [[19, 36]], "sectors": [shed], "cue": "mill_isolate"}
	)
	b.board("mill_control", 12.5, 37.1, 1.1, {"signal": "stone"})
	b.fixture(14.0, 39.0, 26.0, 40.0, 1.2, "quarry_iron", "quarry_iron", .48)
	b.town("saw_blade", 20.5, 42.5, {"solid": .45})
	b.town("crusher", 25.5, 48.5, {"solid": .45})
	b.board("wing_quarry_cut", 19.0, 36.94, .9, {"z": 1.6, "plane": 0.0})
	for p in [Vector2(11.5, 49.5), Vector2(14.5, 49.5)]:
		b.fixture(
			p.x - .45, p.y - .45, p.x + .45, p.y + .45, 1.4, "quarry_face", "quarry_face", .48
		)
	b.react("vending", 28.6, 38.0, 1.5, {"id": "x2-quarry-2"})
	for p in [Vector2(14.0, 45.0), Vector2(24.0, 45.0)]:
		b.prop("lamp", p.x, p.y)
		b.glow(p.x, p.y, 3.0, .18)
	b.controlled(19, 36, false, {"from": "s", "id": "bench-shutter", "tile": "gate"})
	b.raise(19, 36, 19, 36, .48)
	b.secret(8, 45, true, [5, 44, 6, 46], {"from": "e", "id": "cut-cache", "tile": "quarry_shed"})
	b.raise(8, 45, 8, 45, .48)
	b.room(5, 44, 6, 46, "quarry_shed", shed, {"roof": 2.2, "light": .5, "ground": .48})
	b.wall(5, 43, 7, 43, "quarry_face", 2.5)
	b.wall(5, 47, 7, 47, "quarry_face", 2.5)
	b.room(7, 44, 7, 46, "quarry_shed", shed, {"roof": 2.2, "light": .5, "ground": .48})
	b.wall(7, 44, 7, 44, "quarry_face", 2.5)
	b.wall(7, 46, 7, 46, "quarry_face", 2.5)
	for p in [Vector2(12.5, 58.5), Vector2(28.5, 58.5)]:
		b.town("tnt_crate", p.x, p.y, {"solid": .4})
	b.town("mine_cart", 20.5, 57.5, {"solid": .45})
	b.streetlamp(22.0, 56.0)


func chalk_terraces() -> void:
	# Stepped benches up the west face, each a jump too high but for its ramp.
	b.yard(4, 2, 36, 32, "quarry_face", terraces)
	b.raise(4, 24, 36, 32, .72)
	b.raise(4, 16, 36, 23, 1.2)
	b.raise(4, 8, 36, 15, 1.68)
	b.raise(4, 2, 36, 7, 2.16)
	# A ramp cell between each bench and the one above it.
	b.raise(30, 24, 32, 24, .96)
	b.raise(8, 16, 10, 16, 1.44)
	b.raise(30, 8, 32, 8, 1.92)
	b.raise(18, 33, 20, 33, .6)
	b.paint(4, 2, 36, 32, "quarry_dust")
	b.paint(18, 2, 22, 32, "quarry_face")
	b.board("wing_quarry_terrace", 33.0, 31.4, .8, {"z": .72})
	for p in [Vector2(10.5, 28.5), Vector2(26.5, 20.5), Vector2(14.5, 12.5), Vector2(30.5, 4.5)]:
		b.town("boulder_b" if int(p.x) % 2 else "boulder_a", p.x, p.y, {"solid": .4})
	b.town("drill_rig", 22.5, 27.5, {"solid": .45})
	for k in 8:
		b.mark("detail_wear_chalk", 8.0 + k * 3.5, 5.0 + (k % 4) * 7.0, k * .9, 1.4, 1.0)
	# The dynamite shack on the top bench.
	b.building(
		8,
		2,
		16,
		7,
		powder,
		{
			"wall": "quarry_shed",
			"roof": 2.2,
			"floor": "quarry_shed",
			"light": .7,
			"skin": "quarry_shed"
		}
	)
	b.raise(9, 3, 15, 6, 2.16)
	b.door(16, 5, true, {"from": "w", "id": "powder-door"})
	b.raise(16, 5, 16, 5, 2.16)
	b.board("quarry_blast", 16.06, 3.5, .7, {"z": 3.0, "plane": -PI / 2})
	b.town("tnt_crate", 10.5, 4.5, {"solid": .4})
	b.town("tnt_crate", 13.5, 3.5, {"solid": .4})
	b.prop("lamp", 12.0, 5.0)
	b.fence(4, 33, 17, 33, 1.0, "quarry_iron")
	b.fence(21, 33, 36, 33, 1.0, "quarry_iron")
	b.fence(37, 2, 37, 33, 2.6, "quarry_face")
	b.streetlamp(20.0, 18.0)
	b.streetlamp(28.0, 10.0)


func lower_cut() -> void:
	# The pit: benches stepping down, a ramp round each, water at the bottom.
	b.yard(94, 34, 126, 70, "quarry_dust", lower)
	b.fence(93, 34, 93, 45, 1.2, "quarry_iron")
	b.fence(93, 49, 93, 70, 1.2, "quarry_iron")
	b.yard(93, 46, 93, 48, "gravel", lower)
	b.raise(93, 46, 93, 48, .48)
	b.raise(94, 34, 126, 70, .48)
	var rings := [
		[96, 36, 124, 68, .0],
		[99, 39, 121, 65, -.48],
		[102, 42, 118, 62, -.96],
		[105, 45, 115, 59, -1.44]
	]
	for r in rings:
		b.raise(r[0], r[1], r[2], r[3], r[4])
	b.yard(106, 46, 114, 58, "mill_water", flooded)
	b.raise(106, 46, 114, 58, -1.6)
	# Ramps between benches, round the pit like a corkscrew.
	var ramps := [
		[95, 50, 96, 52, .24, "x"],
		[109, 37, 111, 38, -.24, "y"],
		[119, 50, 120, 52, -.72, "x"],
		[109, 60, 111, 61, -1.2, "y"]
	]
	for rp in ramps:
		b.raise(rp[0], rp[1], rp[2], rp[3], rp[4])
	# The rim is rock but for where the way goes: in at the west, out low on
	# the east side and up the east rim to the condenser yard.
	b.wall(94, 34, 121, 35, "quarry_face", 2.0)
	b.wall(94, 36, 95, 45, "quarry_face", 2.0)
	b.wall(94, 53, 95, 70, "quarry_face", 2.0)
	b.wall(122, 35, 124, 35, "quarry_face", 2.0)
	b.raise(124, 59, 124, 61, .24)
	b.paint(94, 34, 126, 70, "quarry_dust")
	b.paint(106, 46, 114, 58, "mill_water")
	for p in [
		Vector2(98.5, 44.5), Vector2(120.5, 40.5), Vector2(104.5, 63.5), Vector2(117.5, 60.5)
	]:
		b.town("boulder_a" if int(p.y) % 2 else "boulder_b", p.x, p.y, {"solid": .4})
	b.town("dump_truck", 100.5, 66.5, {"solid": .45})
	b.town("mine_cart", 120.5, 56.5, {"solid": .45})
	b.board("wing_quarry_wash", 110.0, 59.4, .8, {"z": 0.0, "plane": 0.0})
	# The wash latch at the bottom bench: a way out to the bottle wash.
	b.station(
		"wash-latch",
		116.5,
		64.5,
		"LIFT THE CART LATCH",
		"OPEN CUT TO THE BOTTLE WASH.",
		{"opens": [[125, 66]], "hidden": true, "cue": "scenery_pipe"}
	)
	b.board("wing_quarry_latch", 116.5, 65.4, .48, {"z": .64, "plane": 0.0, "signal": "wash-latch"})
	b.wall(125, 64, 125, 65, "quarry_face", 2.0)
	b.wall(125, 67, 125, 68, "quarry_face", 2.0)
	b.controlled(
		125, 66, true, {"from": "w", "id": "wash-bench-latch", "tile": "gate", "roof": 0.0}
	)
	b.raise(125, 66, 125, 66, .24)
	b.room(126, 64, 128, 68, "quarry_shed", lower, {"roof": 2.2, "light": .6, "ground": .48})
	b.wall(126, 63, 128, 63, "quarry_face", 2.0)
	b.wall(126, 69, 128, 69, "quarry_face", 2.0)
	b.board("wing_quarry_wash_rack", 127.5, 64.04, .7, {"z": .9, "plane": 0.0})
	b.board("detail_wash_rejects", 127.0, 67.0, .5, {"z": .48})
	b.react("pipe", 127.5, 66.0, .9, {"id": "quarry-wash-pipe"})
	b.town("jug_stack", 127.5, 67.5, {"solid": .4})
	for p in [
		Vector2(100.0, 48.0), Vector2(120.0, 46.0), Vector2(110.0, 63.0), Vector2(110.0, 40.0)
	]:
		b.streetlamp(p.x, p.y)
	b.glow(110.0, 52.0, 6.0, .2)


func condenser_yard() -> void:
	b.yard(94, 2, 126, 32, "quarry_dust", condenser)
	b.raise(94, 2, 126, 32, .48)
	b.fence(94, 33, 121, 33, 1.2, "quarry_iron")
	b.fence(125, 33, 126, 33, 1.2, "quarry_iron")
	b.yard(122, 33, 124, 33, "gravel", condenser)
	b.raise(122, 33, 124, 33, .48)
	# The stills: copper vats in a row, the condenser's wheel that diverts them.
	for p in [
		Vector2(99.5, 8.5),
		Vector2(104.5, 8.5),
		Vector2(109.5, 8.5),
		Vector2(99.5, 14.5),
		Vector2(104.5, 14.5)
	]:
		b.town("copper_vat", p.x, p.y, {"solid": .45, "glow": true})
		b.glow(p.x, p.y + 1.0, 2.0, .2)
	b.room(
		114,
		4,
		124,
		12,
		"quarry_shed",
		copper,
		{"roof": 2.6, "ceiling": "quarry_iron", "light": .9, "ground": .48}
	)
	for x in [114.0, 119.0, 124.0]:
		for y in [4.0, 12.0]:
			b.fixture(
				x + (-.1 if x > 120 else .1) - .07,
				y + (.1 if y < 8 else -.1) - .07,
				x + (-.1 if x > 120 else .1) + .07,
				y + (.1 if y < 8 else -.1) + .07,
				2.6,
				"quarry_iron",
				"quarry_iron",
				.48
			)
	b.fixture(116.0, 5.0, 123.0, 6.0, 1.6, "quarry_copper", "quarry_copper", .48)
	b.station(
		"stills",
		120.5,
		9.5,
		"DIVERT THE COPPER CONDENSER",
		"PRESSURE DIVERTED. TAKE THE RECOVERY GATE.",
		{
			"opens": [[88, 18], [93, 22]],
			"sectors": [condenser, copper],
			"cue": "pressure_vent",
			"action": "crank"
		}
	)
	b.board("mill_control", 121.5, 6.4, 1.26, {"signal": "stills", "z": .48})
	b.board("wing_quarry_condenser", 118.0, 6.4, .73, {"signal": "stills", "z": 1.45})
	b.board("detail_still_gauge_bank", 122.5, 11.6, .5, {"z": .9})
	b.board("wing_quarry_still", 104.0, 4.4, .8, {"z": 1.5})
	b.distant_cues.append([104.5, 11.5, "distant_quarry_bottler"])
	b.town("still", 108.5, 26.5, {"solid": .45})
	b.town("jug_stack", 112.5, 26.5, {"solid": .4})
	b.town("jug_stack", 98.5, 22.5, {"solid": .4})
	b.react("bottles", 113.0, 20.0, .42, {"id": "quarry-tasting-bottles"})
	b.exchanges.append(
		{
			"id": "pit-speaker",
			"x": 110.0,
			"y": 30.0,
			"stop_at": "",
			"lines": ["HORN: TASTE THAT MUD?", "VOICE: NEEDS MORE SALT."]
		}
	)
	b.secret(
		126,
		24,
		true,
		[127, 23, 128, 25],
		{"from": "w", "id": "condensate-stash", "tile": "quarry_iron"}
	)
	b.room(127, 23, 128, 25, "quarry_shed", condenser, {"roof": 2.2, "light": .5, "ground": .48})
	b.controlled(
		93, 22, true, {"from": "e", "id": "condenser-recovery-gate", "tile": "gate", "roof": 0.0}
	)
	b.raise(93, 22, 93, 22, .48)
	b.wall(93, 2, 93, 21, "quarry_face", 2.6)
	b.wall(93, 23, 93, 33, "quarry_face", 2.6)
	for p in [Vector2(102.0, 20.0), Vector2(118.0, 20.0), Vector2(110.0, 28.0)]:
		b.streetlamp(p.x, p.y)


func bottling_works() -> void:
	b.yard(89, 14, 92, 33, "quarry_dust", copper)
	b.raise(89, 14, 92, 33, .48)
	b.yard(36, 31, 92, 33, "quarry_dust", cut)
	b.raise(36, 31, 92, 33, .48)
	b.building(
		38,
		6,
		88,
		30,
		bottling,
		{
			"wall": "quarry_iron",
			"roof": 3.0,
			"parapet": .5,
			"floor": "quarry_shed",
			"ceiling": "quarry_iron",
			"windows": 5,
			"lit": .7,
			"light": .9,
			"skin": "detail_wall_copper_seams"
		}
	)
	b.raise(39, 7, 87, 29, .48)
	# Into it: the bench shutter west, the recovery gate east, the main door
	# south (only once both feeds are off).
	b.door(38, 28, true, {"from": "e", "id": "bottling-west"})
	b.yard(37, 28, 37, 28, "quarry_face", terraces)
	b.raise(37, 28, 37, 28, .72)
	b.controlled(88, 18, true, {"from": "w", "id": "stills-shutter", "tile": "gate"})
	b.door(64, 30, false, {"from": "n", "id": "bottling-entry"})
	b.access_doors["64,30"] = ["stone", "stills"]
	for d in [Vector2i(38, 28), Vector2i(88, 18), Vector2i(64, 30)]:
		b.raise(d.x, d.y, d.x, d.y, .48)
	b.board("quarry_bottling", 64.0, 31.06, 1.0, {"z": 2.4, "plane": 0.0})
	# The bottling line: rollers, the filler, crates of jugs, the capper.
	for y in [12.5, 20.5]:
		b.fixture(44.0, y - .4, 84.0, y + .4, 1.4, "steel_mesh", "quarry_iron", .48)
	for x in [50.5, 60.5, 70.5, 80.5]:
		b.town("jug_stack", x, 16.5, {"solid": .4, "z": .48})
	b.town("copper_vat", 44.5, 25.5, {"solid": .45, "z": .48})
	b.town("copper_vat", 82.5, 25.5, {"solid": .45, "z": .48})
	b.board("quarry_bottles", 56.0, 12.5, .7, {"z": 1.88})
	b.board("quarry_bottles", 72.0, 20.5, .7, {"z": 1.88})
	b.board("detail_bottling_cradles", 64.0, 24.0, .6, {"z": .48})
	b.station(
		"bottling",
		64.5,
		8.5,
		"VENT THE BOTTLING RELAY",
		"COPPER BARON! USE THE RELIEF VALVES.",
		{
			"requires": ["stone", "stills"],
			"opens": [[52, 6], [76, 6]],
			"sectors": [bottling, court],
			"cue": "mill_trip"
		}
	)
	b.board("mill_relay", 63.0, 7.1, 1.46, {"signal": "bottling", "z": .48})
	b.exchanges.append(
		{
			"id": "line-speaker",
			"x": 64.0,
			"y": 22.0,
			"stop_at": "",
			"lines": ["HORN: CLOSE THE TAP.", "VOICE: WHICH RED ONE?"]
		}
	)
	b.react("jukebox", 86.6, 27.0, 1.4, {"id": "x2-quarry-5"})
	b.react("cancan", 42.0, 28.0, .4, {"id": "x2-quarry-1"})
	b.react("toilet", 40.0, 8.0, .82, {"id": "x2-quarry-3"})
	b.react("cancan", 85.0, 8.0, .4, {"id": "x2-quarry-6"})
	b.secret(
		64,
		6,
		false,
		[63, 4, 65, 5],
		{"from": "s", "id": "condensate-stash-n", "tile": "quarry_iron"}
	)
	b.raise(64, 6, 64, 6, .48)
	for p in [
		Vector2(46.0, 9.0),
		Vector2(64.0, 16.5),
		Vector2(82.0, 9.0),
		Vector2(56.0, 25.0),
		Vector2(72.0, 25.0),
		Vector2(46.0, 25.0),
		Vector2(82.0, 25.0),
		Vector2(54.0, 9.0),
		Vector2(74.0, 9.0)
	]:
		b.prop("lamp", p.x, p.y)
		b.glow(p.x, p.y, 3.2, .2)


func loading_court() -> void:
	b.yard(39, 1, 87, 5, "concrete", court)
	b.raise(39, 1, 87, 5, .48)
	b.paint(39, 1, 87, 5, "tracks")
	b.room(63, 4, 65, 5, "quarry_shed", court, {"roof": 2.2, "light": .5, "ground": .48})
	b.wall(62, 4, 62, 5, "quarry_iron", 2.5)
	b.wall(66, 4, 66, 5, "quarry_iron", 2.5)
	b.wall(63, 3, 65, 3, "quarry_iron", 2.5)
	b.controlled(52, 6, false, {"from": "s", "id": "court-west"})
	b.controlled(76, 6, false, {"from": "s", "id": "court-east"})
	for d in [Vector2i(52, 6), Vector2i(76, 6)]:
		b.raise(d.x, d.y, d.x, d.y, .48)
	b.station(
		"relief-west",
		41.5,
		3.5,
		"OPEN WEST RELIEF VALVE",
		"RELIEF OPEN. FEWER OUTLETS UNDER PRESSURE.",
		{"requires": ["bottling"], "cue": "pressure_vent"}
	)
	b.station(
		"relief-east",
		84.5,
		4.5,
		"OPEN EAST RELIEF VALVE",
		"RELIEF OPEN. FEWER OUTLETS UNDER PRESSURE.",
		{"requires": ["bottling"], "cue": "pressure_vent"}
	)
	b.board("mill_control", 41.5, 1.4, .76, {"signal": "relief-west"})
	b.board("mill_control", 84.5, 1.4, .76, {"signal": "relief-east"})
	b.board("mill_exit", 86.5, 1.3, 1.42, {"signal": "exit"})
	for p in [Vector2(48.5, 3.5), Vector2(56.5, 2.5), Vector2(72.5, 2.5), Vector2(80.5, 3.5)]:
		b.mark("mark_outlet", p.x, p.y, 0.0, 1.0, 1.0)
	b.board("quarry_safety", 70.0, 1.06, .7, {"z": 1.0, "plane": 0.0})
	b.board("quarry_ledger", 58.0, 1.06, .7, {"z": 1.0, "plane": 0.0})
	b.town("cable_spool", 44.5, 1.5)
	b.streetlamp(50.0, 4.0)
	b.streetlamp(78.0, 4.0)


func story() -> void:
	for l in [
		["SCALES", 56, 80],
		["HAUL", 61, 61],
		["CUT YARD", 52, 44],
		["SHED", 12, 44],
		["TERRACES", 10, 20],
		["POWDER", 9, 4],
		["LOWER CUT", 98, 52],
		["PIT", 107, 50],
		["STILLS", 98, 12],
		["COPPER", 114, 8],
		["BOTTLING", 44, 18],
		["COURT", 44, 3],
	]:
		b.label(String(l[0]), int(l[1]), int(l[2]))
	for p in [[46.5, 33.4], [80.5, 33.4], [24.5, 60.0], [100.0, 30.0]]:
		b.fuel_drums.append(p)
		b.prop("barrel", float(p[0]) + .4, float(p[1]) - .6)
	b.wall(36, 60, 59, 67, "quarry_face", 2.6)
	b.wall(69, 60, 92, 67, "quarry_face", 2.6)


func cast() -> void:
	for e in [
		["coot", 60.0, 72.0, "yard-coot"],
		["clone", 74.0, 81.0, "yard-clone"],
		["valve_rat", 46.0, 72.0, "scale-rat"],
		["billy", 84.0, 78.0, "weigh-billy"],
		["coot", 64.0, 62.0, "haul-coot"],
		["chalk_spitter", 50.0, 42.0, "cut-sentinel"],
		["boilerback", 72.0, 50.0, "cut-guard"],
		["coot", 58.0, 56.0, "cut-coot"],
		["skeeter", 66.0, 44.0, "spill-skeeter"],
		["billy", 84.0, 45.0, "cut-billy"],
		["alien", 44.0, 57.0, "cut-alien"],
		["coot", 20.0, 46.0, "shed-coot"],
		["boilerback", 13.0, 43.5, "shed-boiler"],
		["valve_rat", 27.0, 42.0, "shed-rat"],
		["chalk_spitter", 16.0, 26.0, "lower-cut-chalk"],
		["chalk_spitter", 30.0, 14.0, "upper-cut-chalk"],
		["coot", 25.0, 6.0, "powder-coot"],
		["saucer", 12.0, 20.0, "terrace-saucer"],
		["boilerback", 100.0, 40.0, "bench-boilerback"],
		["coot", 120.0, 54.0, "wash-yard-coot"],
		["valve_rat", 104.0, 62.0, "pit-rat"],
		["clone", 116.0, 44.0, "pit-clone"],
		["skeeter", 110.0, 52.0, "pit-skeeter"],
		["chalk_spitter", 122.0, 66.0, "pit-chalk"],
		["alien", 103.0, 18.0, "vat-sentinel"],
		["coot", 116.0, 26.0, "stills-coot"],
		["boilerback", 118.0, 10.0, "condenser-guard"],
		["billy", 122.0, 18.0, "copper-billy"],
		["saucer", 100.0, 28.0, "condenser-saucer"],
		["coot", 90.5, 26.0, "quarry-store-coot"],
		["boilerback", 48.0, 18.0, "line-guard"],
		["billy", 67.0, 17.0, "line-billy"],
		["coot", 58.0, 24.0, "line-coot"],
		["valve_rat", 80.0, 23.0, "line-rat"],
		["alien", 50.0, 3.0, "court-guard"],
		["chalk_spitter", 70.0, 3.0, "court-clone"],
		["baron", 64.5, 9.6, "court-center"],
		["boilerback", 78.0, 3.0, "court-billy"],
	]:
		b.enemy(String(e[0]), float(e[1]), float(e[2]), String(e[3]))
	b.partners.append(["line-billy", "line-coot", 1])
	for p in [
		["shells", 64.6, 70.6],
		["rinds", 57.0, 81.0],
		["bullets", 72.0, 82.0],
		["beer", 61.5, 74.6],
		["whiskey", 52.0, 75.0],
		["moonshine", 51.6, 74.6],
		["shells", 52.4, 75.4],
		["rinds", 86.0, 76.0],
		["shotgun", 60.5, 77.4],
		["shells", 64.0, 63.0],
		["rinds", 64.0, 50.0],
		["shells", 46.0, 50.0],
		["rifle_ammo", 82.0, 48.0],
		["beer", 58.0, 44.0],
		["whiskey", 72.0, 57.0],
		["bullets", 38.0, 44.0],
		["pressure_ammo", 90.0, 56.0],
		["rifle", 23.0, 41.0],
		["rifle_ammo", 16.0, 50.0],
		["shells", 28.0, 50.0],
		["rinds", 10.0, 38.0],
		["dynamite", 5.6, 45.0],
		["keg_ammo", 6.4, 44.6],
		["arm_ammo", 6.0, 45.6],
		["dynamite", 12.0, 3.4],
		["keg_ammo", 14.6, 5.4],
		["rinds", 26.0, 28.0],
		["beer", 10.0, 12.0],
		["rifle_ammo", 32.0, 20.0],
		["pressure_gun", 99.0, 66.0],
		["pressure_ammo", 108.0, 60.0],
		["shells", 120.0, 38.0],
		["rinds", 101.0, 46.0],
		["whiskey", 127.0, 65.0],
		["cow_ammo", 127.6, 66.6],
		["rivet_ammo", 126.6, 64.6],
		["pressure_ammo", 104.0, 20.0],
		["shells", 124.0, 30.0],
		["rinds", 96.0, 4.0],
		["beer", 116.0, 30.0],
		["milk_ammo", 127.6, 24.0],
		["moonshine", 128.4, 23.4],
		["cowpie", 127.4, 25.0],
		["shells", 46.0, 28.0],
		["rinds", 82.0, 28.0],
		["pressure_ammo", 64.0, 27.0],
		["whiskey", 86.0, 14.0],
		["rifle_ammo", 63.6, 4.4],
		["pressure_ammo", 64.4, 4.6],
		["rinds", 42.0, 2.0],
		["shells", 84.0, 2.0],
	]:
		b.pickup(String(p[0]), float(p[1]), float(p[2]))
	(
		b
		. triggers
		. append(
			{
				"id": "pit-echo",
				"when": {"area": [99, 39, 121, 65]},
				"do":
				[
					{"message": "THE PIT ECHOES. EVERYTHING DOWN HERE HEARD YOU.", "for": 3.0},
					{"alert": 14}
				],
			}
		)
	)
	(
		b
		. triggers
		. append(
			{
				"id": "powder-warning",
				"when": {"area": [8, 2, 16, 7]},
				"do": [{"message": "DYNAMITE SHACK. MIND THE SPARKS.", "for": 2.5}],
			}
		)
	)


## The last pass: the cut yard, the pit and the works crowded the way a
## working quarry is, and lit.
func detail() -> void:
	var rock := ["boulder_a", "boulder_b", "warning_barrel", "tnt_crate"]
	for e in [
		["coot", 80.0, 80.0, "scale-coot"],
		["chalk_spitter", 26.0, 6.0, "powder-chalk"],
		["valve_rat", 48.0, 26.0, "bottling-rat"],
		["boilerback", 84.0, 42.0, "yard-boiler"],
		["skeeter", 110.0, 44.0, "pit-skeeter-b"],
		["alien", 40.0, 22.0, "bottling-alien"],
	]:
		b.enemy(String(e[0]), float(e[1]), float(e[2]), String(e[3]))


## The polish pass: the cut yard and benches crowded with cut stone, rock
## and gear, the empty ground filled with what a quarry leaves about.
func polish() -> void:
	# Set pieces where a yard read unfinished, each against a wall, nothing strewn.
	# The limestone cut: a drill rig parked at the face, spoil and powder by it.
	b.town("drill_rig", 92.0, 34.5)
	b.town("boulder_b", 92.45, 33.05)
	b.town("tnt_crate", 92.45, 35.95)
	# The condenser yard: a still against the north wall, its vat and its jugs.
	b.town("still", 111.5, 2.8)
	b.town("copper_vat", 109.9, 2.92)
	b.town("jug_stack", 112.8, 2.6)
	# Copper recovery: a vat waiting for the scrap man, wire, a barrel.
	b.town("copper_vat", 92.08, 17.5)
	b.town("cable_spool", 92.33, 16.0)
	b.town("warning_barrel", 92.65, 18.7)
	# Rock outcrops left standing where the cut went round them.
	for c in [
		[44, 40, 45, 41, 1.9], [82, 50, 83, 51, 1.6], [70, 37, 71, 38, 2.2], [54, 54, 55, 55, 1.4]
	]:
		b.wall(c[0], c[1], c[2], c[3], "quarry_face", c[4] + .48)
	# Cut blocks stacked two high, a conveyor from the crusher.
	for c in [[50.0, 43.0], [60.0, 42.0], [78.0, 55.0], [88.0, 36.0], [40.0, 56.0], [66.0, 56.0]]:
		b.fixture(c[0], c[1], c[0] + 2.0, c[1] + 1.0, 1.4, "quarry_face", "quarry_face", .48)
		b.fixture(
			c[0] + .3, c[1] + .1, c[0] + 1.7, c[1] + .9, 2.2, "quarry_face", "quarry_face", 1.4
		)
	b.fixture(66.0, 37.3, 76.0, 37.7, 1.3, "steel_mesh", "quarry_iron", .48)
	# The powder magazine on the weigh station's edge, sandbagged.
	b.building(
		80,
		70,
		86,
		74,
		weigh,
		{
			"wall": "quarry_shed",
			"roof": 2.1,
			"floor": "quarry_shed",
			"light": .7,
			"skin": "quarry_shed"
		}
	)
	b.door(83, 74, false, {"from": "n", "id": "magazine-door"})
	b.board("quarry_blast", 83.0, 74.06, .7, {"z": 1.3, "plane": 0.0})
	b.town("tnt_crate", 81.5, 71.5, {"solid": .4})
	var rock := ["boulder_a", "boulder_b", "warning_barrel", "tnt_crate"]
	for e in [
		["chalk_spitter", 75.0, 44.0, "outcrop-chalk"],
		["valve_rat", 100.0, 10.0, "vat-rat"],
		["boilerback", 60.0, 22.5, "works-boiler"],
	]:
		b.enemy(String(e[0]), float(e[1]), float(e[2]), String(e[3]))
	(
		b
		. triggers
		. append(
			{
				"id": "blast-warning",
				"when": {"area": [60, 34, 80, 46]},
				"do":
				[
					{"message": "FIRE IN THE HOLE! SOMEBODY LIT A FUSE.", "for": 3.0},
					{"sound": "distant_quarry_blast"},
					{"shake": .6},
					{"alert": 14}
				],
			}
		)
	)
