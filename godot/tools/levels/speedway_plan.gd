## Buzzard Bend Speedway (chapter 6): a county dirt-track oval on race night.
## The oval fills the middle of the map, banked in the turns and walled in
## concrete, with the cars still running laps on it (the race_laps feature)
## until the pit fuel is dumped. Round it: the truck stop and fuel island at
## the road (south-west, the start), Lugnut's diner and the haulers' lot west,
## pit row's garages and the 'shine fuel depot north, Boggs Salvage's stacked
## wrecks and the crusher east, the grandstands and the announcer's booth
## south over the concourse underneath. In the infield: the campers, the
## monster jump and the figure 8, where Bumper Boggs waits in his car.
## Stations: dump the pit fuel (north), run the crusher (east), cut in on the
## PA (south), then drop the green flag at the figure 8, beat the champ and
## take the checkered flag on the front stretch.
##
## Built by tools/levels/build_level.gd -- speedway. The cast, pickups, set
## pieces and dressing are in speedway_cast.gd.
extends RefCounted

const Builder := preload("res://tools/levels/level_builder.gd")
const Cast := preload("res://tools/levels/speedway_cast.gd")
const W := 150
const H := 104
## The oval: straights between x STRAIGHT_W and STRAIGHT_E on the middle row
## MID, track between INNER and OUTER (an octagonal distance from that line).
const STRAIGHT_W := 52.0
const STRAIGHT_E := 96.0
const MID := 45.5
const INNER := 16.0
const OUTER := 23.5
const BANK := .72

var b: Builder
var truck: int
var diner: int
var haulers: int
var pits: int
var depot: int
var oval: int
var camp: int
var figure8: int
var stands: int
var booth: int
var concourse: int
var salvage: int
var crusher_yard: int
var backlot: int
var parking: int


func make() -> Builder:
	b = Builder.new("speedway", W, H, "junk_stack")
	b.riser_tiles = {
		"track_dirt": "track_dirt",
		"track_chalk": "track_dirt",
		"bleachers": "grandstand_riser",
		"derby_mud": "derby_mud",
		"dirt": "dirt",
	}
	b.meta = {
		"title": "DIRT TRACK SPEEDWAY",
		"heading": ["BUZZARD BEND", "RACE NIGHT"],
		"intro": "DUMP THE PIT FUEL, RUN THE CRUSHER AND CUT IN ON THE PA.",
		"ending": '"CHECKERED FLAG. NOBODY ELSE FINISHED."',
		"score": "music_speedway",
		"ambience": "",
		"layout": 1,
		"sky": "speedway_sky",
		"control_name": "FIX THE FIX: FUEL, CRUSHER, PA",
		"extraction":
		{"x": 74.5, "y": 62.6, "label": "TAKE THE CHECKERED FLAG", "shutdown": "flag"},
		"return_gate": {"destination": "hub", "x": 12.0, "y": 102.4, "width": 3.5, "side": -1},
		"wave": ["figure8-champ", "figure8-wrench", "figure8-tires", "figure8-huffer"],
	}
	return b


func build(_b) -> Array:
	truck = b.district("TRUCK STOP", Color(1.04, .98, .9))
	diner = b.district("LUGNUT'S DINER", Color(1.06, .98, .92))
	haulers = b.district("HAULERS' LOT", Color(.98, .98, 1.02))
	pits = b.district("PIT ROW", Color(1.02, 1.0, .96))
	depot = b.district("FUEL DEPOT", Color(1.06, .96, .88))
	oval = b.district("THE OVAL", Color(1.04, 1.0, .94))
	camp = b.district("INFIELD CAMP", Color(1.04, .96, .9))
	figure8 = b.district("FIGURE 8", Color(1.06, .96, .9))
	stands = b.district("GRANDSTANDS", Color(1.0, 1.0, 1.04))
	booth = b.district("ANNOUNCER'S BOOTH", Color(1.04, 1.0, .96))
	concourse = b.district("THE CONCOURSE", Color(1.04, .98, .92))
	salvage = b.district("BOGGS SALVAGE", Color(.96, .98, 1.02))
	crusher_yard = b.district("CRUSHER YARD", Color(1.02, .98, .94))
	backlot = b.district("TOW LOT", Color(.98, .98, 1.0))
	parking = b.district("GRANDSTAND PARKING", Color(1.0, .98, .96))
	grounds()
	the_oval()
	truck_stop()
	diner_lot()
	haulers_lot()
	pit_row()
	infield()
	figure_eight()
	grandstands()
	concourse_hall()
	salvage_yard()
	tow_lot()
	var cast := Cast.new()
	cast.dress(self)
	return [12.0, 100.5, -PI / 2]


# ------------------------------------------------------------- the oval maths


## How far a cell's middle is from the oval's middle line, octagonally.
func oval_d(x: int, y: int) -> float:
	var dx := maxf(0.0, maxf(STRAIGHT_W - (x + .5), (x + .5) - STRAIGHT_E))
	var dy := absf(y + .5 - MID)
	return maxf(maxf(dx, dy), (dx + dy) * .7071)


## How far into a turn a cell is, 0 on the straights to 1 well round.
func turn_of(x: int) -> float:
	var dx := maxf(0.0, maxf(STRAIGHT_W - (x + .5), (x + .5) - STRAIGHT_E))
	return clampf(dx / 8.0, 0.0, 1.0)


## The banked ground of a track cell: up toward the outside wall in the turns.
func bank_at(x: int, y: int) -> float:
	var lane := clampf((oval_d(x, y) - INNER) / (OUTER - INNER), 0.0, 1.0)
	return snappedf(turn_of(x) * lane * BANK, .12)


func is_track(x: int, y: int) -> bool:
	var d := oval_d(x, y)
	return d > INNER and d <= OUTER


func is_wall(x: int, y: int) -> bool:
	var d := oval_d(x, y)
	return d > OUTER and d <= OUTER + 1.0


func is_infield(x: int, y: int) -> bool:
	return oval_d(x, y) <= INNER


## The racing line the lap cars drive, counter-clockwise seen from above.
func racing_line(d: float) -> Array:
	var out: Array = []
	var r := d / cos(PI / 8.0)
	out.append([STRAIGHT_W, MID + d])
	out.append([STRAIGHT_E, MID + d])
	for k: int in [3, 1, -1, -3]:
		var a := k * PI / 8.0
		out.append([snappedf(STRAIGHT_E + r * cos(a), .01), snappedf(MID + r * sin(a), .01)])
	out.append([STRAIGHT_E, MID - d])
	out.append([STRAIGHT_W, MID - d])
	for k: int in [-5, -7, 7, 5]:
		var a := k * PI / 8.0
		out.append([snappedf(STRAIGHT_W + r * cos(a), .01), snappedf(MID + r * sin(a), .01)])
	return out


# --------------------------------------------------------------------- areas


## Everything outside the oval is open ground of one district or another, so
## the oval's wall stands free and the grounds go all the way round it.
func grounds() -> void:
	b.yard(1, 1, 26, 49, "gravel", haulers)
	b.yard(1, 50, 26, 71, "gravel", diner)
	b.yard(1, 72, 44, 102, "oil_asphalt", truck)
	b.yard(27, 1, 120, 20, "gravel", pits)
	b.yard(27, 21, 40, 40, "gravel", haulers)
	b.yard(27, 41, 40, 71, "gravel", diner)
	b.yard(106, 21, 120, 44, "gravel", pits)
	b.yard(104, 45, 120, 71, "gravel", backlot)
	b.yard(41, 70, 105, 72, "concrete", stands)
	b.yard(45, 93, 105, 102, "gravel", parking)
	b.yard(106, 72, 148, 102, "gravel", backlot)
	b.yard(121, 1, 148, 70, "junk_ground", salvage)
	# The edges: block wall behind pit row, stacked wrecks round the salvage
	# yard, the tree line everywhere else.
	b.wall(0, 0, 149, 0, "hedgerow", 2.4)
	b.wall(0, 103, 149, 103, "hedgerow", 2.4)
	b.wall(0, 0, 0, 103, "hedgerow", 2.4)
	b.wall(149, 0, 149, 103, "hedgerow", 2.4)
	b.wall(27, 0, 120, 0, "cinder", 2.6)
	b.wall(121, 0, 149, 0, "junk_stack", 2.6)
	b.wall(149, 0, 149, 71, "junk_stack", 2.6)


func the_oval() -> void:
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			if is_track(x, y):
				b.yard(x, y, x, y, "track_dirt", oval, {"ground": bank_at(x, y)})
			elif is_infield(x, y):
				b.yard(x, y, x, y, "grass", camp if x < 66 else figure8)
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			if not is_wall(x, y):
				continue
			var top := 0.0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = Vector2i(x, y) + d
				if is_track(n.x, n.y):
					top = maxf(top, bank_at(n.x, n.y))
			b.wall(x, y, x, y, "crash_wall", top + 1.05)
	# The groove the cars have worn, darker, a lane off the inside.
	for x in range(52, 97):
		b.paint(x, 63, x, 63, "tracks")
		b.paint(x, 27, x, 27, "tracks")
	# Start and finish across the front stretch, and the infield's edge.
	b.paint(74, 62, 74, 68, "track_chalk")
	for x in range(52, 97):
		for y in [29, 61]:
			if x in [57, 58, 66, 67, 82, 83, 91, 92]:
				continue
			b.wall(x, y, x, y, "tire_wall", .72)
	# Gaps in the wall: onto the track from the apron, the pits, the hauler lot
	# (west) and the busted wall into the salvage yard (east).
	for c: Vector2i in [
		Vector2i(60, 69),
		Vector2i(61, 69),
		Vector2i(88, 69),
		Vector2i(89, 69),
		Vector2i(48, 21),
		Vector2i(49, 21),
		Vector2i(74, 21),
		Vector2i(75, 21),
		Vector2i(100, 21),
		Vector2i(101, 21),
	]:
		# A step at most up to the banked lane beyond the gap.
		var lane := bank_at(c.x, c.y + (1 if c.y < 40 else -1))
		b.yard(c.x, c.y, c.x, c.y, "track_dirt", oval, {"ground": minf(.24, lane)})
	# The breaches at the ends of the turns, where the top lane is highest: a
	# ramp of two steps down from it to the lots.
	for y in range(44, 48):
		b.yard(27, y, 27, y, "gravel", haulers, {"ground": .48})
		b.yard(26, y, 26, y, "gravel", haulers, {"ground": .24})
		b.yard(120, y, 120, y, "junk_ground", salvage, {"ground": .48})
		b.yard(121, y, 121, y, "junk_ground", salvage, {"ground": .24})
	b.meta["lap_cars"] = {
		"path": racing_line(19.6),
		"cars": 2,
		"speed": 8.4,
		"stop_at": "pits",
		"damage": 34,
		"models": ["race_car", "race_car"],
	}
	# The flag stand at the line and the banner over it.
	b.fixture(73.9, 61.1, 74.1, 61.3, 3.9, "steel_mesh", "steel_mesh")
	b.fixture(73.9, 69.7, 74.1, 69.9, 3.9, "steel_mesh", "steel_mesh")
	b.board(
		"speedway_start_finish",
		74.0,
		65.5,
		1.3,
		{"z": 2.55, "plane": PI / 2, "back": "speedway_start_finish"}
	)
	b.panel(74.0, 61.2, 74.0, 69.8, "steel_mesh", 3.85, 3.92, .9)
	# The turns: numbers on the outside wall, tyres stacked at the inside.
	b.board("speedway_turn_1", 119.94, 45.5, .7, {"z": 1.1, "plane": PI / 2})
	b.board("speedway_turn_3", 28.06, 45.5, .7, {"z": 1.1, "plane": -PI / 2})
	b.board("speedway_turn_2", 96.0, 21.94, .7, {"z": 1.1, "plane": 0.0})
	b.board("speedway_turn_4", 52.0, 69.06, .7, {"z": .4, "plane": PI})
	# Sponsors along the front and back stretch walls.
	var ads := ["speedway_ad_oil", "speedway_ad_chaw", "speedway_ad_tires", "speedway_ad_bait"]
	for k in 4:
		var x := 55.0 + k * 11.0
		if absf(x - 74.0) < 3.0:
			x += 4.0
		b.board(ads[k], x, 68.94, .55, {"z": .3, "plane": PI})
		b.board(ads[(k + 2) % 4], x + 4.0, 22.06, .55, {"z": .3, "plane": 0.0})


## The truck stop at the road: the store, the fuel island under its canopy,
## the rigs parked along the lot, and the speedway's gate east.
func truck_stop() -> void:
	b.paint(1, 99, 44, 102, "road")
	b.arch(12.0, 102.4, 3.5, "route_hub")
	b.board("hub_road_stake", 14.2, 101.4, .97, {"plane": PI, "back": "hub_road_stake_back"})
	b.building(
		2,
		74,
		14,
		84,
		truck,
		{
			"wall": "cinder",
			"roof": 2.5,
			"floor": "floor_tile",
			"windows": 3,
			"lit": .7,
			"light": .82
		}
	)
	b.door(14, 79, true, {"from": "w", "id": "store-door"})
	b.board("speedway_truckstop_sign", 14.06, 76.5, .9, {"z": 1.7, "plane": -PI / 2})
	# The fuel island under its canopy.
	b.room(18, 84, 31, 90, "concrete", truck, {"roof": 2.9, "ceiling": "tin", "light": 1.18})
	for p in [Vector2(18.0, 84.0), Vector2(32.0, 84.0), Vector2(18.0, 91.0), Vector2(32.0, 91.0)]:
		b.fixture(p.x - .12, p.y - .12, p.x + .12, p.y + .12, 2.9, "tin", "tin")
	for x in [20.5, 24.5, 28.5]:
		b.town("fuel_pump", x, 87.5, {"solid": .3, "glow": true})
	b.board("speedway_fuel_price", 33.0, 86.5, .9, {"z": 1.2, "plane": -PI / 2})
	b.fixture(32.9, 86.0, 33.1, 86.2, 1.2, "wood", "wood")
	for x in [21.0, 29.0]:
		b.prop("lamp", x, 87.5)
	b.glow(25.0, 87.5, 6.0, .3)
	# The rigs: a cab with its box trailer, a second cab alone, the reefer.
	b.town("semi_tractor", 21.5, 76.5, {"solid": .45})
	b.fixture(23.1, 75.6, 33.9, 77.4, 2.7, "trailer", "trailer")
	b.town("semi_tractor", 38.5, 96.5, {"solid": .45})
	b.fixture(23.1, 95.6, 36.9, 97.4, 2.7, "trailer", "trailer")
	b.board("speedway_ad_tires", 28.5, 75.56, .8, {"z": 1.2, "plane": PI})
	b.board("speedway_ad_oil", 30.0, 97.44, .8, {"z": 1.2, "plane": 0.0})
	b.town("fuel_tank", 5.5, 91.5, {"solid": .45})
	b.town("tire_pile", 9.5, 88.5, {"solid": .4})
	b.town("port_a_john", 2.6, 96.5)
	# The gate east into the grandstand: posts and the marquee over the way.
	b.fixture(43.8, 83.8, 44.2, 84.2, 3.4, "cinder", "cinder")
	b.fixture(43.8, 88.8, 44.2, 89.2, 3.4, "cinder", "cinder")
	b.panel(44.0, 84.2, 44.0, 88.8, "speedway_marquee", 2.2, 3.4, 1.3)
	b.panel(44.03, 88.8, 44.03, 84.2, "speedway_marquee", 2.2, 3.4, 1.0)
	b.board("speedway_entry", 41.5, 80.06, 1.2, {"z": 1.6, "plane": 0.0})
	b.poles([Vector2(2.5, 71.5), Vector2(16.5, 71.5), Vector2(30.5, 71.5), Vector2(42.5, 78.5)])
	for p in [Vector2(10.0, 95.0), Vector2(36.0, 82.0), Vector2(16.0, 80.0), Vector2(40.0, 90.0)]:
		b.streetlamp(p.x, p.y)


## Lugnut's diner: chrome front, a counter and booths, the kitchen behind,
## and the walk-in out back that nobody is supposed to open.
func diner_lot() -> void:
	b.building(
		3,
		54,
		21,
		64,
		diner,
		{
			"wall": "diner_steel",
			"roof": 2.6,
			"floor": "diner_checker",
			"windows": 3,
			"lit": .85,
			"light": .9,
			"skin": "tile"
		}
	)
	b.door(12, 64, false, {"from": "n", "id": "diner-front"})
	b.door(5, 54, false, {"from": "s", "id": "diner-back"})
	b.board("speedway_diner_sign", 12.0, 64.94, 1.0, {"z": 2.75, "plane": 0.0})
	b.fixture(10.4, 64.6, 13.6, 65.0, 2.62, "tin", "tin", 2.5)
	# The counter, the kitchen behind it, the booths along the windows.
	b.fixture(6.0, 58.3, 17.0, 58.8, .95, "counter", "counter_top")
	b.fixture(4.1, 55.1, 9.9, 55.8, .92, "counter", "counter_top")
	b.fixture(12.1, 55.1, 16.9, 55.8, .92, "counter", "counter_top")
	for x in [5.2, 9.2, 15.2]:
		b.fixture(x, 62.3, x + 1.6, 62.9, .66, "wood", "counter_top")
	b.react("jukebox", 19.5, 62.6, 1.4, {"id": "diner-jukebox", "radius": .3})
	b.react("cans", 8.0, 58.55, .4, {"z": .95, "id": "diner-cans"})
	b.react("tv", 14.0, 55.45, .75, {"z": .92, "id": "diner-tv"})
	b.board("speedway_menu", 11.0, 54.96, .8, {"z": 1.3, "plane": 0.0})
	b.board("speedway_points", 20.94, 60.0, .7, {"z": 1.2, "plane": -PI / 2})
	b.notes.append(
		[
			11.5,
			58.55,
			"GUEST CHECK",
			"TABLE 4 / BOGGS. 6 CHILI DOGS, 2 JUGS. 'PUT IT ON THE PURSE.'",
			.95
		]
	)
	b.board("county_note", 11.5, 58.55, .3, {"z": .95, "plane": 0.0})
	for p in [Vector2(8.0, 60.5), Vector2(15.0, 60.5), Vector2(10.0, 56.5)]:
		b.prop("lamp", p.x, p.y)
		b.glow(p.x, p.y, 3.0, .16)
	# The walk-in freezer out back: the jugs keep cold in there.
	b.wall(17, 50, 21, 50, "diner_steel", 2.6)
	b.wall(17, 51, 17, 53, "diner_steel", 2.6)
	b.wall(21, 51, 21, 53, "diner_steel", 2.6)
	b.room(18, 51, 20, 53, "concrete", diner, {"roof": 2.3, "light": .5, "skin": "steel_mesh"})
	b.secret(19, 54, false, [18, 51, 20, 53], {"from": "s", "id": "walk-in", "tile": "diner_steel"})
	# The lot: the cook's pickup, the dumpster, the grease barrels.
	b.prop("pickup_truck_b", 23.5, 60.5)
	b.fixture(23.2, 55.2, 25.8, 56.8, 1.3, "steel_mesh", "tin")
	b.town("warning_barrel", 2.5, 67.5, {"solid": .3})
	b.town("warning_barrel", 3.5, 68.5, {"solid": .3})
	b.streetlamp(17.0, 68.0)
	b.streetlamp(24.0, 52.0)


## The haulers' lot west of the oval: the teams' rigs nose to tail, their
## campers, and the busted fence through to turn 3.
func haulers_lot() -> void:
	for r in [[4, 6, 16, 8], [4, 16, 16, 18], [4, 28, 16, 30], [4, 38, 16, 40]]:
		b.fixture(r[0] + .1, r[1] + .6, r[2] + .9, r[3] + .4, 2.7, "trailer", "trailer")
	for p in [Vector2(18.5, 7.5), Vector2(18.5, 17.5), Vector2(18.5, 29.5), Vector2(18.5, 39.5)]:
		b.town("semi_tractor", p.x, p.y, {"solid": .45})
	for p in [
		["speedway_ad_oil", 10.0, 6.56, PI],
		["speedway_ad_chaw", 10.0, 18.44, 0.0],
		["speedway_ad_tires", 10.0, 28.56, PI],
		["speedway_ad_bait", 10.0, 40.44, 0.0],
	]:
		b.board(String(p[0]), float(p[1]), float(p[2]), .9, {"z": 1.3, "plane": float(p[3])})
	b.town("canned_ham", 5.5, 12.5, {"solid": .45})
	b.town("canned_ham", 6.5, 34.5, {"solid": .45})
	b.town("generator", 12.5, 12.5, {"solid": .45})
	b.town("tire_pile", 22.5, 23.5, {"solid": .45})
	b.town("tire_pile", 3.5, 45.5, {"solid": .45})
	b.town("port_a_john", 2.6, 23.5)
	b.town("port_a_john", 2.6, 25.5)
	b.town("burn_barrel", 12.5, 23.5, {"solid": .3, "glow": true})
	b.glow(12.5, 23.5, 3.5, .3)
	b.town("camp_chairs", 9.5, 23.5)
	b.town("cooler", 14.5, 24.5, {"solid": .3})
	b.town("floodlight_tower", 25.5, 45.5, {"solid": .25, "glow": true})
	b.glow(25.5, 45.5, 9.0, .3)
	for p in [Vector2(10.0, 2.0), Vector2(22.0, 33.0), Vector2(10.0, 47.0)]:
		b.streetlamp(p.x, p.y)


## Pit row: the pit lane along the back stretch, twelve bays in one long
## garage behind it, and the alley behind that with the fuel depot.
func pit_row() -> void:
	b.paint(27, 16, 120, 20, "oil_asphalt")
	b.building(
		33,
		6,
		111,
		14,
		pits,
		{
			"wall": "cinder",
			"roof": 2.7,
			"floor": "concrete",
			"ceiling": "joists",
			"windows": 0,
			"light": .74,
			"skin": "detail_wall_garage_courses"
		}
	)
	# Bays of six with block walls between; some open on the lane, some
	# behind their roll-up doors, doors through the walls between them.
	var bay := 0
	for x0 in range(34, 110, 6):
		var x1 := x0 + 5
		if x1 < 110:
			b.wall(x1 + 1, 7, x1 + 1, 13, "cinder", 2.98)
		var front_open := bay % 3 != 1
		for x in range(x0 + 1, x1):
			if front_open:
				b.room(x, 14, x, 14, "concrete", pits, {"roof": 2.3, "light": .9})
			else:
				b.wall(x, 14, x, 14, "garage_door", 2.98)
		if x1 < 110 and bay % 2 == 0:
			b.door(x1 + 1, 10, true, {"from": "w", "id": "bay-door-%d" % bay})
		bay += 1
	# Doors out the back into the alley from every third bay.
	for x in [37, 55, 73, 91, 108]:
		b.door(x, 6, false, {"from": "s", "id": "bay-back-%d" % x})
	b.board("speedway_pit_row", 72.0, 14.94, 1.1, {"z": 2.3, "plane": 0.0})
	b.board("speedway_no_pass", 32.94, 10.0, .7, {"z": 1.1, "plane": -PI / 2})
	b.board("speedway_standings", 111.06, 10.0, .9, {"z": 1.1, "plane": PI / 2})
	# The alley: the fuel depot in its middle, tyres and crates down its length.
	b.paint(64, 1, 84, 5, "concrete")
	for y in [1, 2, 3, 4, 5]:
		for x in [64, 84]:
			if y < 5:
				b.wall(x, y, x, y, "stockyard", 1.24)
	b.town("fuel_tank", 67.5, 2.5, {"solid": .45})
	b.town("fuel_tank", 81.5, 2.5, {"solid": .45})
	b.town("nitro_rack", 70.5, 1.5, {"solid": .35})
	b.town("nitro_rack", 78.5, 1.5, {"solid": .35})
	b.board("speedway_tanks", 74.5, 1.04, .7, {"z": 1.75, "plane": 0.0})
	b.station(
		"pits",
		74.5,
		1.6,
		"DUMP THE PIT FUEL",
		"TANKS DUMPED. THE CARS ARE RUNNING ON FUMES.",
		{"sectors": [pits, depot], "cue": "pressure_vent", "action": "crank"}
	)
	b.board("mill_control", 74.5, 1.04, 1.1, {"signal": "pits", "z": .1, "plane": 0.0})
	for y in range(1, 6):
		for x in range(65, 84):
			if b.area[b.at(x, y)] == pits:
				b.area[b.at(x, y)] = depot
	b.glow(74.5, 3.0, 4.0, .26)
	b.distant_cues.append([74.5, 3.5, "distant_derby_engine"])
	for p in [Vector2(40.0, 3.0), Vector2(58.0, 3.0), Vector2(92.0, 3.0), Vector2(108.0, 3.0)]:
		b.streetlamp(p.x, p.y)
	for x in [50.5, 98.5]:
		b.town("floodlight_tower", x, 20.5, {"solid": .25, "glow": true})
		b.glow(x, 20.5, 9.0, .3)
	# The lane: the pit wall seats, the stalls' lines, a car waiting on its jack.
	b.town("pa_horns", 74.5, 16.5, {"solid": .2})
	b.town("stock_car_b", 62.5, 18.5, {"solid": .45})
	b.fixture(61.4, 18.1, 63.6, 18.9, .3, "mill_tin", "tin")


func infield() -> void:
	# Campers and trailers in the west of the infield, round the fire.
	b.trailer(40, 40, "s", camp)
	b.trailer(40, 50, "n", camp)
	b.paint(39, 44, 62, 49, "dirt")
	# The monster jump: a dirt ramp up from the west, a deck of crushed cars,
	# and the landing ramp east, all of it a step at a time.
	for x in range(52, 70):
		var up := 0.0
		if x < 58:
			up = (x - 51) * .2
		elif x < 64:
			up = 1.2
		else:
			up = (70 - x) * .2
		b.raise(x, 34, x, 36, snappedf(up, .12))
		b.paint(x, 34, x, 36, "dirt")
	# Crushed cars banked along both sides of it: nobody climbs on from the side.
	for x in range(54, 68):
		for y in [33, 37]:
			b.fixture(x + .05, y + .1, x + .95, y + .9, .62, "junk_stack", "tin")
	b.town("monster_truck", 60.5, 35.5, {"solid": .45})


func figure_eight() -> void:
	var left := Vector2(79.5, 45.5)
	var right := Vector2(98.5, 45.5)
	for y in range(28, 63):
		for x in range(66, 112):
			if not is_infield(x, y):
				continue
			var dl := _oct(x, y, left)
			var dr := _oct(x, y, right)
			var d := minf(dl, dr)
			if d <= 3.6:
				b.wall(x, y, x, y, "tire_wall", 1.3)
			elif d <= 10.6:
				b.yard(x, y, x, y, "derby_mud", figure8)
			elif d <= 11.6:
				b.wall(x, y, x, y, "tire_wall", 1.25)
	# The gates at the crossing, north and south, that the green flag opens.
	b.yard(89, 38, 89, 38, "grass", figure8)
	b.yard(89, 52, 89, 52, "grass", figure8)
	b.controlled(89, 39, false, {"from": "s", "id": "figure8-north", "tile": "gate", "roof": 0.0})
	b.controlled(89, 51, false, {"from": "n", "id": "figure8-south", "tile": "gate", "roof": 0.0})
	b.board("speedway_figure8", 87.0, 33.0, 1.0, {"z": .5, "plane": PI})
	b.town("flag_stand", 91.5, 34.5, {"solid": .45})
	b.station(
		"flag",
		88.6,
		37.45,
		"DROP THE GREEN FLAG",
		"GREEN FLAG! BUMPER BOGGS IS ROLLIN'. TAKE HIM APART.",
		{"requires": ["pits", "crusher", "booth"], "opens": [[89, 39], [89, 51]], "cue": "gate"}
	)
	b.board("mill_control", 88.5, 37.96, .9, {"signal": "flag", "z": .1, "plane": PI})
	b.board("mill_exit", 74.5, 62.06, 1.2, {"signal": "exit", "z": .0, "plane": 0.0})
	b.town("floodlight_tower", 84.5, 32.5, {"solid": .25, "glow": true})
	b.town("floodlight_tower", 84.5, 58.5, {"solid": .25, "glow": true})
	b.glow(89.5, 45.5, 12.0, .28)


func _oct(x: int, y: int, c: Vector2) -> float:
	var dx := absf(x + .5 - c.x)
	var dy := absf(y + .5 - c.y)
	return maxf(maxf(dx, dy), (dx + dy) * .7071)


## The stands rise a step a row from the apron to the top walk; the booth
## sits on top in the middle, open to the track; two tunnels go through
## between the sections to the concourse underneath.
func grandstands() -> void:
	for y in range(71, 80):
		b.yard(46, y, 102, y, "bleachers", stands, {"ground": (y - 70) * .24})
	b.wall(45, 71, 45, 80, "cinder", 3.4)
	b.wall(103, 71, 103, 80, "cinder", 3.4)
	b.wall(46, 80, 102, 80, "cinder", 3.4)
	for x0 in [59, 87]:
		b.wall(x0, 71, x0, 80, "cinder", 3.4)
		b.wall(x0 + 3, 71, x0 + 3, 80, "cinder", 3.4)
		b.room(x0 + 1, 71, x0 + 2, 80, "concrete", concourse, {"roof": 2.2, "light": .6})
	# The booth: up on the top row, its front open over the track.
	b.wall(70, 76, 70, 80, "office_wall", 5.0)
	b.wall(78, 76, 78, 80, "office_wall", 5.0)
	b.wall(71, 80, 77, 80, "office_wall", 5.0)
	b.room(
		71,
		76,
		77,
		79,
		"porch",
		booth,
		{"roof": 4.7, "light": .9, "ground": 2.4, "skin": "office_wall"}
	)
	b.fixture(71.0, 76.0, 78.0, 76.75, 2.98, "office_wall", "counter_top", 2.4)
	b.door(70, 79, true, {"from": "e", "id": "booth-west"})
	b.door(78, 79, true, {"from": "w", "id": "booth-east"})
	b.raise(70, 79, 70, 79, 2.4)
	b.raise(78, 79, 78, 79, 2.4)
	b.board("speedway_booth_sign", 74.5, 75.95, .6, {"z": 2.45, "plane": PI})
	b.station(
		"booth",
		74.5,
		77.2,
		"CUT IN ON THE PA",
		"PA: BUMPER BOGGS, GET YOUR RUST BUCKET TO THE FIGURE 8!",
		{"sectors": [figure8, booth], "cue": "menu_accept"}
	)
	b.board("mill_relay", 74.5, 76.78, .7, {"signal": "booth", "z": .58, "plane": 0.0})
	b.town("pa_horns", 74.5, 78.5, {"z": 2.3})
	b.prop("lamp", 73.0, 78.0)
	b.glow(74.5, 78.0, 3.0, .2)
	b.react("tv", 76.5, 79.4, .7, {"z": .0, "id": "booth-tv"})
	b.town("floodlight_tower", 46.5, 70.5, {"solid": .25, "glow": true})
	b.town("floodlight_tower", 102.5, 70.5, {"solid": .25, "glow": true})
	b.glow(46.5, 70.5, 9.0, .3)
	b.glow(102.5, 70.5, 9.0, .3)


## The concourse under the stands: the snack bar along its back wall, the
## restrooms at the west end, beer, the main gates on the parking.
func concourse_hall() -> void:
	b.room(
		46,
		81,
		102,
		91,
		"concrete",
		concourse,
		{"roof": 2.7, "ceiling": "joists", "light": .86, "skin": "cinder"}
	)
	b.wall(45, 81, 45, 92, "cinder", 3.0)
	b.wall(103, 81, 103, 92, "cinder", 3.0)
	b.wall(46, 92, 102, 92, "cinder", 3.0)
	b.door(45, 86, true, {"from": "e", "id": "concourse-west"})
	b.door(103, 86, true, {"from": "w", "id": "concourse-east"})
	b.door(66, 92, false, {"from": "n", "id": "gate-south-a"})
	b.door(82, 92, false, {"from": "n", "id": "gate-south-b"})
	# Columns holding up the stands.
	for x in range(50, 101, 8):
		b.fixture(x - .22, 83.8, x + .22, 84.2, 2.7, "concrete", "concrete")
	# The snack bar.
	b.fixture(68.0, 89.3, 81.0, 89.8, .98, "counter", "counter_top")
	b.board("speedway_menu", 74.5, 91.94, .9, {"z": 1.3, "plane": PI})
	b.board("speedway_beer", 79.0, 91.94, .5, {"z": 1.6, "plane": PI, "glow": true})
	b.react("cans", 71.0, 89.55, .4, {"z": .98, "id": "snack-cans"})
	b.react("vending", 84.5, 91.4, 1.5, {"id": "concourse-vending"})
	# The restrooms.
	b.wall(46, 87, 53, 87, "tile", 2.7)
	b.wall(50, 88, 50, 91, "tile", 2.7)
	b.room(46, 88, 49, 91, "floor_tile", concourse, {"roof": 2.4, "light": .55, "skin": "tile"})
	b.room(51, 88, 53, 91, "floor_tile", concourse, {"roof": 2.4, "light": .55, "skin": "tile"})
	b.door(48, 87, false, {"from": "n", "id": "restroom-men"})
	b.door(52, 87, false, {"from": "n", "id": "restroom-women"})
	b.react("toilet", 47.0, 90.5, .82, {"id": "concourse-toilet"})
	b.wall(53, 88, 53, 91, "tile", 2.7)
	b.room(54, 88, 56, 91, "concrete", concourse, {"roof": 2.4, "light": .45, "skin": "cinder"})
	b.wall(57, 88, 57, 91, "cinder", 2.7)
	b.wall(54, 87, 56, 87, "cinder", 2.7)
	b.secret(
		55, 87, false, [54, 88, 56, 91], {"from": "n", "id": "janitor-closet", "tile": "cinder"}
	)
	for x in range(52, 101, 6):
		b.prop("lamp", x, 85.5)
		b.glow(x, 85.5, 3.4, .22)


## Boggs Salvage: wrecks stacked into walls, rows and rows of them, the
## crusher and its crane in the yard in the middle, the office trailer.
func salvage_yard() -> void:
	for r in [
		[122, 5, 144, 5],
		[126, 10, 148, 10],
		[122, 15, 143, 15],
		[122, 41, 135, 41],
		[139, 41, 148, 41],
		[127, 49, 127, 62],
		[133, 43, 133, 56],
		[133, 60, 133, 70],
		[139, 45, 139, 58],
		[144, 49, 148, 49],
		[122, 66, 129, 66],
	]:
		b.wall(r[0], r[1], r[2], r[3], "junk_stack", 2.3)
	b.wall(121, 1, 121, 16, "junk_stack", 2.4)
	b.wall(121, 20, 121, 43, "junk_stack", 2.4)
	b.wall(121, 48, 121, 70, "junk_stack", 2.4)
	b.wall(121, 71, 148, 71, "junk_stack", 2.4)
	b.yard(121, 17, 121, 19, "junk_ground", salvage)
	b.controlled(129, 71, false, {"from": "n", "id": "salvage-gate", "tile": "gate", "roof": 0.0})
	# The crusher yard.
	for y in range(22, 41):
		for x in range(122, 149):
			b.area[b.at(x, y)] = crusher_yard
	b.paint(130, 27, 142, 35, "concrete")
	b.town("car_crusher", 136.5, 31.5, {"solid": 1.1, "base": "quarry_iron"})
	b.town("magnet_crane", 127.5, 26.5, {"solid": .45})
	b.town("crushed_stack", 145.5, 24.5, {"solid": .45})
	b.town("crushed_stack", 145.5, 37.5, {"solid": .45})
	b.town("crushed_stack", 124.5, 37.5, {"solid": .45})
	b.station(
		"crusher",
		138.3,
		31.0,
		"RUN THE CAR CRUSHER",
		"BOGGS' BACKUP CAR IS A PANCAKE. THE BACK GATE'S OPEN.",
		{"opens": [[129, 71]], "sectors": [crusher_yard, salvage], "cue": "mill_trip"}
	)
	b.board("mill_brake", 137.64, 31.0, .8, {"signal": "crusher", "z": .3, "plane": -PI / 2})
	b.board("speedway_crusher_warn", 136.5, 29.95, .6, {"z": 1.5, "plane": PI})
	b.board("speedway_junk_sign", 121.5, 18.0, .8, {"z": 2.45, "plane": -PI / 2})
	b.town("floodlight_tower", 122.5, 33.5, {"solid": .25, "glow": true})
	b.glow(122.5, 33.5, 9.0, .3)
	b.glow(136.5, 31.5, 6.0, .22)
	# Boggs' office.
	b.trailer(139, 61, "n", salvage)
	b.notes.append(
		[
			144.4,
			63.5,
			"PURSE LEDGER",
			"FEATURE: BOGGS 1ST AGAIN. FUEL: 40 JUGS FROM STILLWATER. ALIEN MONEY OK.",
			.8
		]
	)
	b.fixture(143.2, 63.2, 145.6, 63.8, .8, "wood", "counter_top")
	b.board("county_note", 144.4, 63.5, .3, {"z": .8, "plane": 0.0})
	b.board("speedway_points", 145.94, 62.5, .6, {"z": 1.1, "plane": -PI / 2})
	b.town("trophy", 140.5, 63.5, {"solid": .3})
	for p in [
		Vector2(130.0, 2.0),
		Vector2(146.0, 13.0),
		Vector2(126.0, 45.0),
		Vector2(142.0, 52.0),
		Vector2(124.0, 68.0)
	]:
		b.streetlamp(p.x, p.y)


## The tow lot behind the stands: the wrecker, the cars waiting to be
## crushed, the tow man's shack.
func tow_lot() -> void:
	b.building(
		108,
		80,
		116,
		86,
		backlot,
		{"wall": "tin", "roof": 2.4, "floor": "concrete", "windows": 3, "lit": .5, "light": .7}
	)
	b.door(112, 80, false, {"from": "s", "id": "tow-shack"})
	# The tow man's stash behind the shack's east wall.
	b.wall(117, 81, 119, 81, "tin", 2.6)
	b.wall(117, 85, 119, 85, "tin", 2.6)
	b.wall(119, 82, 119, 84, "tin", 2.6)
	b.room(117, 82, 118, 84, "concrete", backlot, {"roof": 2.2, "light": .5, "skin": "tin"})
	b.secret(116, 83, true, [117, 82, 118, 84], {"from": "e", "id": "tow-stash", "tile": "tin"})
	b.table(109.2, 84.2, 111.8, 84.8, .78)
	b.react("tv", 110.0, 84.5, .75, {"z": .78, "id": "tow-tv"})
	b.prop("lamp", 112.5, 83.0)
	b.glow(112.5, 83.0, 3.0, .2)
	b.town("tow_truck", 120.5, 77.5, {"solid": .45})
	b.town("wrecked_derby", 126.5, 84.5, {"solid": .45})
	b.fixture(125.5, 84.1, 127.5, 84.9, .3, "mill_tin", "tin")
	b.town("wrecked_derby", 131.5, 79.5, {"solid": .45})
	b.fixture(130.5, 79.1, 132.5, 79.9, .3, "mill_tin", "tin")
	b.town("tire_pile", 140.5, 76.5, {"solid": .45})
	b.town("hubcap_board", 113.0, 80.0 - .06, {"plane": PI})
	for p in [
		Vector2(118.0, 92.0),
		Vector2(136.0, 90.0),
		Vector2(108.0, 60.0),
		Vector2(60.0, 98.0),
		Vector2(88.0, 98.0)
	]:
		b.streetlamp(p.x, p.y)
