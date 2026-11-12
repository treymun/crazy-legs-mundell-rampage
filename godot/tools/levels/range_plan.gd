## Mundell's Proving Grounds: the firing range off the title screen, not a
## chapter of the campaign. A county-fair shooting range at dusk under
## floodlights: the armory (where the player starts, every gun on its walls),
## the covered firing line north of it with eight lanes off it (tin cans,
## pellets, the long rifle range, the duck gallery, the bowling alley, the
## soak tank, special orders and the powder pit), and along the midway the
## boss corral, the whuppin' yard and the bullpen with its lever bank.
## Every number the range feature needs is in src/range_layout.gd.
##
## Built by tools/levels/build_level.gd -- range.
extends RefCounted

const Builder := preload("res://tools/levels/level_builder.gd")
const L := preload("res://src/range_layout.gd")
const W := 100
const H := 78

var b: Builder
var line: int
var hall: int
var lanes := {}


func make() -> Builder:
	b = Builder.new("range", W, H, "hedgerow")
	b.meta = {
		"title": "MUNDELL'S PROVING GROUNDS",
		"heading": ["MUNDELL'S", "PROVING GROUNDS"],
		"intro": "MUNDELL'S PROVING GROUNDS. EVERY GUN, ALL THE AMMO. PAUSE TO LEAVE.",
		"score": "music",
		"ambience": "range",
		"layout": 1,
		"sky": "sky",
		"pressure_ports": L.PRESSURE_PORTS,
		"boss_decoys": L.BOSS_DECOYS,
		"area_sounds": {},
	}
	return b


func build(_b) -> Array:
	line = b.district("FIRING LINE", Color(1.06, 1.0, .9))
	hall = b.district("THE ARMORY", Color(1.08, .98, .86))
	for id: String in L.STATIONS:
		if id != "armory":
			lanes[id] = b.district(String(L.STATIONS[id]["title"]), Color(1.04, .99, .92))
	# The woods all round, tall, then everything carved out of them.
	b.wall(0, 0, W - 1, H - 1, "hedgerow", 3.3)
	firing_line()
	tin_cans()
	pellets()
	rifle()
	gallery()
	bowling()
	soak()
	special()
	pit()
	corral()
	yard()
	armory()
	bullpen()
	dressing()
	return L.SPAWN


# ------------------------------------------------------------------- helpers


func lane(id: String, floor_name: String) -> Array:
	var r: Array = L.STATIONS[id]["lane"]
	b.yard(int(r[0]), int(r[1]), int(r[2]), int(r[3]), floor_name, lanes[id], {"light": .9})
	# A log backstop at the far end.
	if int(r[1]) > 1:
		b.wall(int(r[0]), int(r[1]) - 1, int(r[2]), int(r[1]) - 1, "mill_log", 2.8)
	return r


## The header board over a lane's mouth, hung from the porch eave.
func header(id: String, cx: float) -> void:
	b.board("range_head_" + id, cx, 51.96, .66, {"z": 1.96, "plane": 0.0})


## A yard marker on the lane's east baffle, facing the lane.
func marker(x_wall: float, y: float, yards: int) -> void:
	b.board("range_yd_%d" % yards, x_wall - .03, y, .26, {"z": .95, "plane": PI / 2.0})


## A lever on its post with its name plate, and the station that works it.
func lever(
	id: String, x: float, y: float, label_text: String, plate: String, facing := 0.0
) -> void:
	b.town("range_lever", x, y)
	b.station("range-" + id, x, y, label_text, "", {"cue": "range_lever"})
	if plate != "":
		var face := Vector2(-sin(facing), cos(facing))
		var at := Vector2(x, y) - face * .3
		b.board("range_plate_" + plate, at.x, at.y, .14, {"z": 1.12, "plane": facing})


func floodlight(x: float, y: float, reach := 6.0, amount := .22) -> void:
	b.town("range_floodlight", x, y, {"glow": true})
	b.glow(x, y, reach, amount)


func post(x: float, y: float, top: float) -> void:
	b.fixture(x - .06, y - .06, x + .06, y + .06, top, "wood", "wood")


# --------------------------------------------------------------------- areas


func firing_line() -> void:
	b.room(1, 52, 98, 55, "porch", line, {"roof": 2.5, "ceiling": "joists", "light": .9})
	b.yard(1, 56, 98, 58, "fair_gravel", line, {"light": .86})
	b.paint(1, 57, 98, 57, "tracks")
	# Porch posts on the cell corners along its front, and string lights
	# between them.
	for k in range(0, 25):
		var x := 2.0 + k * 4.0
		if x > 98.0:
			break
		b.fixture(x - .06, 55.94, x + .06, 56.06, 2.5, "wood", "counter_top")
		if k > 0:
			b.cable(x - 4.0, 56.0, x, 56.0, 2.42)
			b.board(
				"fair_bulbs", x - 2.0, 56.02, .3, {"z": 2.05, "plane": 0.0, "back": "fair_bulbs_on"}
			)
	for x in [8.0, 24.0, 40.0, 56.0, 72.0, 88.0]:
		b.prop("lamp", x, 53.5)
	for x in [14.0, 30.0, 62.0, 78.0, 94.0]:
		b.streetlamp(x, 57.6, 4.5)
	# Plank baffles between the lanes, floodlight poles rising out of them.
	for x in [10, 20, 30, 42, 50, 60, 70]:
		b.wall(x, 1, x, 51, "wood", 1.5)
		floodlight(x + .5, 51.6, 7.0, .2)


func tin_cans() -> void:
	lane("cans", "dirt")
	b.paint(4, 18, 6, 51, "tracks")
	header("cans", 5.5)
	b.town("range_bench", 8.5, 51.5, {"solid": .45, "scale": .85})
	for c: Array in L.CANS:
		var x := float(c[1])
		var y := float(c[2])
		post(x, y, L.CAN_TOP)
		b.react("cans", x, y, .32, {"id": String(c[0]), "z": L.CAN_TOP, "radius": .2})
	for pair in [[46.5, 5], [41.5, 10], [36.5, 15], [31.5, 20], [26.5, 25]]:
		marker(10.0, float(pair[0]), int(pair[1]))
	lever("cans", 2.5, 50.6, "STAND THE CANS BACK UP", "cans")
	b.prop("tree_b", 2.0, 19.5)
	b.prop("tree", 8.6, 21.0)


func pellets() -> void:
	lane("pellets", "dirt")
	b.paint(11, 46, 19, 51, "gravel")
	header("pellets", 15.5)
	b.town("range_bench", 18.5, 51.5, {"solid": .45, "scale": .85})
	for pair in [[48.0, 3], [45.0, 6], [42.0, 9], [39.0, 12]]:
		marker(20.0, float(pair[0]), int(pair[1]))
	b.town("hay_wagon", 15.5, 35.5, {"solid": .45})
	b.town("range_ammo_crate", 11.8, 50.4)


func rifle() -> void:
	lane("rifle", "grass")
	b.paint(24, 1, 26, 51, "dirt")
	header("rifle", 25.5)
	b.town("range_bench", 28.5, 51.5, {"solid": .45, "scale": .85})
	for pair in [[41.0, 10], [31.0, 20], [26.0, 25], [16.0, 35]]:
		marker(30.0, float(pair[0]) + .5, int(pair[1]))
	for p in [Vector2(22.0, 6.0), Vector2(28.6, 10.5), Vector2(22.2, 21.5), Vector2(28.5, 36.0)]:
		b.prop("tree" if int(p.y) % 2 else "tree_b", p.x, p.y)
	b.town("range_sandbags", 22.2, 50.2)
	floodlight(25.5, 22.0, 6.0, .18)


func gallery() -> void:
	lane("gallery", "porch")
	b.paint(31, 40, 41, 47, "fair_gravel")
	header("gallery", 36.5)
	b.fixture(31.0, 49.3, 42.0, 49.7, .8, "counter", "counter_top")
	b.board("range_gallery_back", 36.5, 40.08, 1.75, {"z": .45, "plane": 0.0})
	# The track rails the targets ride on.
	for row: Array in L.GALLERY_ROWS:
		var y := float(row[0]) + .12
		b.panel(31.0, y, 42.0, y, "steel_mesh", float(row[1]) - .06, float(row[1]) - .02, .9)
	for k in 4:
		var x := 32.5 + k * 2.6
		b.cable(x, 46.0, x + 2.6, 46.0, 2.6)
		b.board("fair_bulbs", x + 1.3, 46.02, .3, {"z": 2.2, "plane": 0.0, "back": "fair_bulbs_on"})
	b.prop("lamp", 36.5, 50.5)
	b.glow(36.5, 44.0, 5.0, .4)
	lever("gallery", 32.5, 50.5, "START A GALLERY ROUND", "gallery")
	b.town("balloons", 31.6, 48.6)
	b.town("prize_bear", 41.4, 48.5)


func bowling() -> void:
	lane("bowling", "floor_tile")
	b.paint(45, 33, 47, 50, "porch")
	b.paint(44, 33, 44, 50, "concrete")
	b.paint(48, 33, 48, 50, "concrete")
	header("bowling", 46.5)
	b.board("range_bowling_mask", 46.5, 33.06, .9, {"z": .75, "plane": 0.0})
	b.fixture(43.15, 38.0, 43.65, 49.0, .35, "tin", "tin")
	b.mark("mark_lane", 46.5, 49.4, 0.0, .9, .14)
	lever("pins", 48.5, 50.6, "RACK THE PINS", "pins")
	b.prop("lamp", 46.5, 53.5)
	b.glow(46.5, 36.5, 3.5, .45)


func soak() -> void:
	lane("soak", "dirt")
	header("soak", 55.5)
	b.paint(52, 34, 58, 42, "creek")
	b.fence(51, 44, 59, 44, .85, "stockyard")
	b.town("jug_stack", 58.0, 49.6)
	b.town("washer", 52.0, 47.0)
	b.town("range_hay_bale", 54.5, 38.5, {"solid": .4})
	lever("soak", 52.5, 50.6, "TURN OUT THREE HANDS", "soak")
	b.glow(55.5, 38.0, 4.0, .2)


func special() -> void:
	lane("special", "concrete")
	b.paint(61, 22, 69, 37, "gravel")
	header("special", 65.5)
	b.fence(61, 38, 69, 38, .85, "stockyard")
	# Sheet tin set at an angle for the rip saw's blades to bounce off.
	b.panel(61.2, 34.0, 63.4, 31.6, "tin", 0.0, 1.3, .9)
	b.panel(68.8, 34.0, 66.6, 31.6, "tin", 0.0, 1.3, .9)
	b.town("range_bench", 68.5, 51.5, {"solid": .45, "scale": .85})
	lever("alien_one", 62.5, 50.6, "WAKE THE GREY ALIEN", "alien_one")
	b.town("pylon", 68.4, 24.0)
	b.town("saucer_wreck", 65.0, 23.6)


func pit() -> void:
	lane("pit", "dirt")
	b.paint(71, 10, 98, 44, "quarry_dust")
	header("pit", 84.5)
	# The sandbag berm the pit is thrown into over.
	b.fixture(71.0, 45.6, 99.0, 46.4, .75, "concrete", "concrete")
	for d: Vector2 in L.DRUMS:
		b.fuel_drums.append([d.x, d.y])
	lever("fodder", 72.5, 50.6, "SEND IN THE FODDER", "fodder")
	lever("reset-pit", 97.5, 50.6, "RESET THE PIT", "reset")
	b.town("tnt_crate", 73.5, 41.5, {"solid": .4})
	b.town("tnt_crate", 96.5, 40.5, {"solid": .4})
	b.town("warning_barrel", 97.5, 13.5, {"solid": .3})
	b.town("warning_barrel", 72.5, 12.5, {"solid": .3})
	b.car(94.0, 28.0, false)
	b.town("scarecrow", 86.5, 14.5)
	for k in 6:
		b.mark("mark_scorch_%d" % (k % 3), 76.0 + k * 3.7, 20.0 + (k % 3) * 6.0, k * .9, 1.4, 1.2)
	b.board("range_hot", 84.5, 46.43, .4, {"z": .75, "plane": 0.0})
	floodlight(84.5, 11.5, 9.0, .2)


func corral() -> void:
	var r: Array = L.STATIONS["corral"]["lane"]
	b.yard(int(r[0]), int(r[1]), int(r[2]), int(r[3]), "tracks", lanes["corral"], {"light": .86})
	b.paint(3, 62, 22, 75, "dirt")
	b.fence(1, 59, 24, 59, .85, "stockyard")
	b.fence(25, 59, 25, 76, .85, "stockyard")
	b.door(12, 59, false, {"from": "n", "tile": "stockyard", "id": "corral-gate"})
	b.board("range_head_corral", 12.0, 58.92, .5, {"z": 1.3, "plane": PI})
	for i in L.BOSS_KINDS.size():
		var kind := String(L.BOSS_KINDS[i])
		var label := "CLEAR THE CORRAL" if kind == "clear" else "LET OUT " + String(L.NAMES[kind])
		lever("boss-" + kind, L.BOSS_LEVER_X[i], L.BOSS_LEVER_Y, label, kind, PI)
	b.town("boulder_a", 6.5, 63.5, {"solid": .4})
	b.town("boulder_b", 19.5, 70.5, {"solid": .4})
	b.town("tombstone_a", 3.0, 75.4)
	b.town("tombstone_c", 21.6, 62.4)
	for p in L.PRESSURE_PORTS:
		b.mark("mark_outlet", float(p[0]), float(p[1]), 0.0, .5, .5)
	floodlight(1.6, 59.6, 9.0, .2)
	floodlight(23.4, 75.4, 9.0, .2)


func yard() -> void:
	var r: Array = L.STATIONS["yard"]["lane"]
	b.yard(int(r[0]), int(r[1]), int(r[2]), int(r[3]), "dirt", lanes["yard"], {"light": .88})
	b.paint(26, 59, 33, 60, "fair_gravel")
	b.board("range_head_yard", 29.95, 76.96, .58, {"z": 1.5, "plane": PI})
	var plaques := {"yard-crowbar": 0, "yard-sling": 8, "yard-saw": 5}
	for t: Array in L.TARGETS:
		if String(t[1]) != "yard":
			continue
		var x := float(t[3])
		var y := float(t[4])
		post(x, y, 1.6)
		if plaques.has(String(t[0])):
			b.board(
				"range_plaque_%d" % int(plaques[String(t[0])]),
				x,
				y + .62,
				.22,
				{"z": .3, "plane": 0.0}
			)
	b.town("high_striker", 32.5, 74.5, {"solid": .3})
	b.town("range_hay_bale", 27.0, 75.0)
	b.town("range_hay_bale", 26.9, 71.6)
	b.streetlamp(30.0, 66.0, 4.0)


func armory() -> void:
	(
		b
		. building(
			34,
			59,
			61,
			76,
			hall,
			{
				"wall": "barn",
				"roof": 3.0,
				"floor": "wood",
				"windows": 4,
				"lit": .9,
				"light": .92,
				"skin": "office_wall",
				"ceiling": "joists",
			}
		)
	)
	b.wall_top(34, 59, 61, 59, 4.3)
	# The big doors, slid back.
	b.room(45, 59, 50, 59, "wood", hall, {"roof": 2.7, "ceiling": "joists", "light": .95})
	b.board("range_title", 48.0, 58.93, 1.25, {"z": 2.75, "plane": PI, "glow": true})
	b.board("range_rules", 43.4, 58.94, .8, {"z": .7, "plane": PI})
	b.board("range_head_armory", 48.0, 60.06, .62, {"z": 2.0, "plane": 0.0})
	# Every gun on the walls, its plaque under it, and the station to take it.
	for i in Weapons.COUNT:
		var spot: Array = L.rack(i)
		var face := Vector2(-sin(float(spot[2])), cos(float(spot[2])))
		var at := Vector2(float(spot[0]), float(spot[1]))
		var gun := String(Weapons.NAMES[i])
		b.board("range_display", at.x, at.y, .78, {"z": .92, "plane": spot[2]})
		var held := at + face * .04
		b.board("item_" + gun, held.x, held.y, .56, {"z": 1.0, "plane": spot[2]})
		var plaque := at + face * .02
		b.board("range_plaque_%d" % i, plaque.x, plaque.y, .28, {"z": .58, "plane": spot[2]})
		b.glow(at.x + face.x * .8, at.y + face.y * .8, 1.6, .16)
		var stand: Vector2 = spot[3]
		b.station(
			"range-rack-%d" % i,
			stand.x,
			stand.y,
			"TAKE THE " + String(Weapons.LABELS[i]).get_slice(" [", 0),
			"",
			{"cue": "range_lever"}
		)
	b.town("range_gun_rack", 44.5, 63.5, {"solid": .45})
	b.town("range_gun_rack", 51.5, 63.5, {"solid": .45})
	b.town("range_ammo_crate", 41.5, 61.0)
	b.town("range_ammo_crate", 54.6, 61.0)
	b.town("strongbox", 45.0, 74.9)
	b.town("tnt_crate", 51.2, 74.9)
	b.town("range_scoreboard", 48.0, 75.7)
	for p in [
		Vector2(40.0, 63.0),
		Vector2(48.0, 63.0),
		Vector2(56.0, 63.0),
		Vector2(40.0, 71.0),
		Vector2(48.0, 69.0),
		Vector2(56.0, 71.0)
	]:
		b.prop("lamp", p.x, p.y)
	b.glow(48.0, 67.0, 9.0, .12)


func bullpen() -> void:
	var r: Array = L.STATIONS["bullpen"]["lane"]
	b.yard(62, 59, 65, 76, "fair_gravel", line, {"light": .86})
	b.yard(int(r[0]), int(r[1]), int(r[2]), int(r[3]), "tracks", lanes["bullpen"], {"light": .86})
	b.paint(69, 62, 97, 75, "dirt")
	b.fence(66, 59, 98, 59, .85, "stockyard")
	b.fence(66, 60, 66, 76, .85, "stockyard")
	b.door(66, 68, true, {"from": "w", "tile": "stockyard", "id": "bullpen-gate"})
	b.board("range_head_bullpen", 82.0, 58.9, .5, {"z": 1.35, "plane": PI})
	for i in L.PEN_KINDS.size():
		var kind := String(L.PEN_KINDS[i])
		var at := L.pen_lever(i)
		var label := "" + String(L.NAMES[kind])
		if kind == "clear":
			label = "CLEAR THE PEN"
		elif kind == "squad":
			label = "LET OUT A WHOLE SQUAD"
		else:
			label = "LET OUT A " + String(L.NAMES[kind])
		lever("pen-" + kind, at.x, at.y, label, kind, PI)
	# Cover for the locals to use: crates, bales, a wreck, sandbags.
	for p in [Vector2(74.5, 64.5), Vector2(80.5, 71.5), Vector2(87.5, 63.5), Vector2(91.5, 69.5)]:
		b.crate_stack(p.x, p.y, 1.1)
	for p in [Vector2(77.5, 67.5), Vector2(84.5, 74.5), Vector2(89.5, 66.5), Vector2(71.5, 72.5)]:
		b.bale(p.x, p.y)
	b.car(84.0, 68.0, true)
	b.town("range_sandbags", 72.5, 62.4)
	b.town("range_sandbags", 94.5, 74.6)
	b.town("range_scoreboard", 63.6, 75.6)
	b.town("range_loudspeaker", 64.5, 60.5, {"solid": .15})
	floodlight(97.4, 59.6, 9.0, .2)
	floodlight(97.4, 75.4, 9.0, .2)
	floodlight(67.6, 75.4, 9.0, .2)


## Set pieces that tie it together: the PA, flags, the range-is-hot sign.
func dressing() -> void:
	b.town("range_loudspeaker", 33.5, 57.5, {"solid": .15})
	b.board("range_hot", 41.0, 55.94, .36, {"z": 1.6, "plane": PI})
	b.town("range_ammo_crate", 60.0, 57.2)
	b.town("picnic_table", 22.5, 57.5)
	for l in [
		["CANS", 2, 40],
		["PELLETS", 11, 44],
		["RIFLE", 22, 20],
		["GALLERY", 32, 43],
		["BOWL", 43, 36],
		["SOAK", 52, 40],
		["SPECIAL", 61, 30],
		["POWDER PIT", 78, 28],
		["CORRAL", 6, 67],
		["YARD", 27, 68],
		["ARMORY", 42, 67],
		["BULLPEN", 77, 67],
	]:
		b.label(String(l[0]), int(l[1]), int(l[2]))
