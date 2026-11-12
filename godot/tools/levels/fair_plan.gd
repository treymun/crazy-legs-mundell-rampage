## Possum County Fair, rebuilt (layout 3): last call on the midway, at night,
## under string lights that only come on once the concession breaker is set.
## The parking field and ticket gate in the south; the midway north to the
## bell plaza; concession alley west (the breaker) with the livestock show
## barn and the Ferris wheel past it; the game court east (the tin rooster
## gallery), the demolition derby, the backstage sideshows and the freight and
## raffle lot (the PA patch lead, then the PA panel); the bell opens the prize
## pavilion, whose broadcast cut brings Rudy, and the service exit behind it.
##
## Built by tools/levels/build_level.gd -- fair.
extends RefCounted

const Builder := preload("res://tools/levels/level_builder.gd")
const W := 130
const H := 86

var b: Builder
var ticket: int
var midway: int
var conc: int
var games: int
var pavilion: int
var service: int
var freight: int
var sideshow: int
var pa: int
var barn: int
var wheel: int
var derby: int
var camp: int
var parking: int


func make() -> Builder:
	b = Builder.new("fair", W, H, "wood")
	b.meta = {
		"title": "POSSUM COUNTY FAIR",
		"heading": ["LAST CALL", "ON THE MIDWAY"],
		"intro": "SET CONCESSION POWER AND PATCH THE BACKSTAGE PA.",
		"ending": '"NO REFUNDS AFTER THE ABDUCTION."',
		"score": "fair_score",
		"ambience": "fair",
		"layout": 3,
		"sky": "fair_sky",
		"control_name": "CONCESSION AND BACKSTAGE PA",
		"objective_side_tasks": ["bell"],
		"extraction": {"x": 96.5, "y": 6.5, "label": "USE SERVICE EXIT", "shutdown": "broadcast"},
		"return_gate": {"destination": "hub", "x": 64.0, "y": 84.4, "width": 3.45, "side": -1},
		"recovery_room": [56.6, 70.6, 58.9, 73.9, "room"],
		"gallery": [79.96, 56.42],
		"boss_decoys": [[57.5, 9.5], [71.5, 9.5]],
		"wave": ["wave-barker", "wave-guard", "wave-crawler", "show-ringmaster"],
	}
	return b


func build(_b) -> Array:
	ticket = b.district("TICKET SHACK", Color(1.04, .98, .9))
	midway = b.district("THE MIDWAY", Color(1.1, .96, 1.04))
	conc = b.district("CONCESSION ALLEY", Color(1.08, 1.0, .86))
	games = b.district("GAME COURT", Color(1.04, .94, 1.08))
	pavilion = b.district("PRIZE PAVILION", Color(1.06, 1.0, .9))
	service = b.district("SERVICE EXIT", Color(.9, .96, 1.04))
	freight = b.district("FREIGHT AND RAFFLE LOT", Color(.94, .98, 1.04))
	sideshow = b.district("BACKSTAGE SIDESHOWS", Color(1.02, .9, 1.1))
	pa = b.district("PA BOOTH", Color(1.06, .98, .92))
	barn = b.district("LIVESTOCK SHOW BARN", Color(1.04, .96, .86))
	wheel = b.district("FERRIS WHEEL PLAZA", Color(1.0, .96, 1.1))
	derby = b.district("DEMOLITION DERBY", Color(1.04, .96, .9))
	camp = b.district("CARNY CAMP", Color(.92, .98, 1.02))
	parking = b.district("PARKING FIELD", Color(.9, .96, 1.06))
	parking_and_gate()
	midway_strip()
	concession_alley()
	livestock_barn()
	ferris_plaza()
	carny_camp()
	prize_pavilion()
	service_exit()
	freight_lot()
	sideshows()
	game_court()
	derby_arena()
	sound_and_story()
	cast()
	detail()
	polish()
	return [64.5, 81.5, -PI / 2]


# ------------------------------------------------------------------- areas


func parking_and_gate() -> void:
	b.yard(4, 73, 124, 84, "grass", parking)
	b.paint(56, 73, 72, 84, "tracks")
	for k in 7:
		b.paint(8 + k * 8, 76, 10 + k * 8, 82, "fair_gravel")
		b.paint(80 + (k % 5) * 9, 76, 82 + (k % 5) * 9, 82, "fair_gravel")
	b.arch(64.0, 84.4, 3.45, "route_hub")
	b.board("hub_road_stake", 66.2, 83.4, .97, {"plane": PI, "back": "hub_road_stake_back"})
	# Trucks parked in rows, a camper, a horse trailer; whoever came never left.
	b.prop("pickup_truck_b", 118.0, 77.6)
	b.town("truck_blocks", 35.5, 81.5, {"solid": .45})
	b.town("port_a_john", 49.5, 74.5, {"solid": .45})
	b.town("port_a_john", 51.5, 74.5, {"solid": .45})
	b.town("searchlight", 54.5, 76.5, {"solid": .35, "glow": true})
	b.town("searchlight", 73.5, 76.5, {"solid": .35, "glow": true})
	for k in 6:
		b.board("fair_pylon", 58.0 + (k % 2) * 12.0, 75.2 + (k / 2) * 3.0, 1.2, {"glow": true})
	# The ticket line: the fence with its gate between two ticket shacks.
	b.fence(4, 72, 124, 72, 1.6, "fair_iron")
	b.building(
		55,
		69,
		59,
		74,
		ticket,
		{
			"wall": "fair_booth",
			"roof": 2.3,
			"floor": "floor_tile",
			"light": .85,
			"skin": "detail_wall_raffle_stripes"
		}
	)
	b.building(
		69,
		69,
		73,
		74,
		ticket,
		{
			"wall": "fair_booth",
			"roof": 2.3,
			"floor": "floor_tile",
			"light": .85,
			"skin": "detail_wall_raffle_stripes"
		}
	)
	b.door(59, 72, true, {"from": "w", "id": "ticket-west"})
	b.door(69, 72, true, {"from": "e", "id": "ticket-east"})
	b.yard(60, 69, 68, 74, "tracks", ticket)
	b.interiors.append(["tickets", 57.0, 70.05, .78, .44, 0.0])
	b.board("fair_entry", 64.0, 72.0, 1.2, {"z": 1.5, "plane": 0.0, "back": "fair_ticket_rule"})
	b.board("fair_ticket_rule", 60.04, 70.5, .7, {"z": .9, "plane": -PI / 2})
	b.board("detail_ticket_rolls", 57.0, 71.5, .5, {"z": .8})
	for x in [61.0, 63.0, 65.0, 67.0]:
		b.fixture(x - .06, 72.94, x + .06, 73.06, .9, "fair_iron", "fair_iron")
	b.streetlamp(61.0, 74.5)
	b.streetlamp(67.0, 74.5)
	b.glow(64.0, 72.5, 4.0, .3)


func midway_strip() -> void:
	b.yard(52, 26, 76, 68, "fair_gravel", midway)
	b.paint(60, 26, 68, 68, "tracks")
	# Booth rows either side: ring toss, milk bottles, darts, the duck pond.
	var signs := ["fair_prize_pile", "fair_redemption", "wing_fair_receipts", "fair_lost_property"]
	for k in 4:
		var y0: int = 54 + (k % 2) * 7
		if k < 2:
			b.booth(52, y0, 57, y0 + 5, midway, "e", {"sign": signs[k]})
		else:
			b.booth(71, y0, 76, y0 + 5, midway, "w", {"sign": signs[k]})
	b.booth(52, 27, 57, 33, midway, "e", {"sign": "fair_prize_pile"})
	b.booth(71, 27, 76, 33, midway, "w", {"sign": "fair_redemption"})
	# The bell plaza: the show bell on its frame, and the way in to everything.
	b.yard(50, 42, 76, 52, "fair_gravel", midway)
	b.paint(58, 44, 70, 50, "porch")
	b.raise(62, 46, 66, 48, .12)
	b.paint(62, 46, 66, 48, "floor_tile")
	# The bell on its plinth: a frame of its own, nothing hung behind it.
	b.fixture(63.6, 47.1, 64.4, 47.9, .17, "fair_iron", "fair_iron", .12)
	b.quest("quest_bell", 64.0, 47.5, "bell", {"z": .05})
	b.station(
		"bell",
		64.5,
		48.4,
		"RING THE MIDWAY BELL",
		"SHOW BELL RUNG. THE PRIZE PAVILION IS OPEN.",
		{"requires": ["concession", "games"], "opens": [[61, 25], [67, 25]], "cue": "fair_bell"}
	)
	b.town("high_striker", 56.5, 43.5, {"solid": .3})
	b.town("cotton_candy", 71.5, 50.5, {"solid": .4})
	b.town("balloons", 57.5, 50.6)
	b.town("prize_bear", 70.6, 43.2)
	b.town("balloons", 66.5, 37.5)
	b.town("cotton_candy", 60.5, 38.5, {"solid": .4})
	# String lights down the midway: they light when the breaker is set.
	var left: Array = []
	var right: Array = []
	for k in 8:
		left.append(Vector2(59.5, 66.5 - k * 5.5))
		right.append(Vector2(68.5, 66.5 - k * 5.5))
	b.poles(left, 3.1)
	b.poles(right, 3.1)
	for k in 8:
		b.cable(59.5, 66.5 - k * 5.5, 68.5, 66.5 - k * 5.5, 3.0)
		b.board(
			"fair_bulbs",
			64.0,
			66.5 - k * 5.5,
			.39,
			{"z": 2.6, "plane": 0.0, "signal": "concession", "back": "fair_bulbs_off"}
		)
	for p in [Vector2(62.0, 58.0), Vector2(66.0, 40.0), Vector2(62.0, 30.0), Vector2(66.0, 64.0)]:
		b.streetlamp(p.x, p.y, 3.6)
	b.board("fair_wheel", 52.2, 47.0, 1.5, {"z": .3, "plane": -PI / 2})
	scatter_spill([Vector2(63.0, 55.0), Vector2(65.5, 34.0), Vector2(61.2, 62.0)])


func scatter_spill(spots: Array) -> void:
	for p: Vector2 in spots:
		b.board("fair_spill", p.x, p.y, .3, {"z": 0.0})


func concession_alley() -> void:
	b.yard(6, 52, 49, 70, "fair_gravel", conc)
	b.paint(6, 59, 49, 62, "tracks")
	b.yard(50, 60, 51, 60, "tracks", conc)
	b.fence(4, 51, 50, 51, 1.6, "fair_iron")
	b.fence(5, 52, 5, 71, 1.6, "fair_iron")
	b.fence(6, 71, 51, 71, 1.6, "fair_iron")
	# The food stands: corn dogs, funnel cake, fried pickles, the soda tent.
	var signs := ["fair_prize_pile", "fair_ticket_rule", "fair_redemption", "fair_lost_property"]
	for k in 4:
		b.booth(
			18 + k * 8,
			52,
			23 + k * 8,
			57,
			conc,
			"s",
			{"sign": signs[k], "skin": "detail_wall_prize_skirting"}
		)
		b.booth(
			18 + k * 8,
			64,
			23 + k * 8,
			69,
			conc,
			"n",
			{"sign": signs[3 - k], "skin": "detail_wall_prize_skirting"}
		)
	b.board("detail_soda_fountain", 20.5, 55.0, .5, {"z": .95})
	for p in [Vector2(24.5, 60.5), Vector2(32.5, 61.5), Vector2(40.5, 60.5)]:
		b.town("picnic_table", p.x, p.y, {"solid": .4})
	b.town("cotton_candy", 46.5, 58.5, {"solid": .4})
	b.town("generator", 15.5, 67.5, {"solid": .45})
	b.react("vending", 16.6, 53.0, 1.5, {"id": "alley-soda"})
	b.react("bottles", 30.5, 56.3, .42, {"z": .95, "id": "fair-soda-case"})
	b.react("cans", 38.5, 64.7, .42, {"z": .95, "id": "fair-raffle-tins"})
	# The breaker shack at the far end.
	b.building(
		6,
		53,
		13,
		61,
		conc,
		{
			"wall": "fair_iron",
			"roof": 2.3,
			"floor": "concrete",
			"light": .7,
			"skin": "fair_iron",
			"windows": 3
		}
	)
	b.door(13, 58, true, {"from": "w", "id": "breaker-door"})
	b.station(
		"concession",
		8.5,
		56.0,
		"SET CONCESSION BREAKER",
		"CONCESSION LIVE. NORTH GATE IS OPEN.",
		{"opens": [[20, 51]], "sectors": [conc, midway], "cue": "breaker_thunk"}
	)
	b.quest("quest_switch_fair", 7.5, 54.5, "concession")
	b.board("fair_concession_arrow", 50.6, 60.04, .7, {"z": 1.0, "plane": 0.0})
	b.controlled(
		20, 51, false, {"from": "s", "id": "concession-shortcut", "tile": "fair_gate", "roof": 0.0}
	)
	b.prop("lamp", 9.5, 57.0)
	b.streetlamp(28.0, 62.0)
	b.streetlamp(44.0, 62.0)


func livestock_barn() -> void:
	b.yard(6, 14, 34, 50, "dirt", barn)
	b.fence(5, 13, 5, 50, 1.6, "fair_iron")
	b.fence(35, 14, 35, 50, 1.24)
	b.yard(35, 38, 35, 40, "dirt", barn)
	b.building(
		8,
		16,
		32,
		38,
		barn,
		{
			"wall": "barn",
			"roof": 3.0,
			"parapet": .5,
			"floor": "dirt",
			"ceiling": "joists",
			"windows": 5,
			"light": .9,
			"skin": "barn"
		}
	)
	b.door(20, 38, false, {"from": "n", "id": "show-barn-south", "style": "slide"})
	b.door(32, 27, true, {"from": "w", "id": "show-barn-east", "style": "slide"})
	# The show ring with its rail and the bleachers round it.
	b.fence(14, 22, 26, 22, .9)
	b.fence(14, 32, 26, 32, .9)
	b.fence(14, 23, 14, 31, .9)
	b.fence(26, 23, 26, 26, .9)
	b.fence(26, 28, 26, 31, .9)
	b.paint(15, 23, 25, 31, "dirt")
	for y in [18.5, 35.5]:
		b.fixture(13.0, y - .4, 27.0, y + .4, .6, "bleachers", "bleachers")
	b.raise(9, 17, 12, 37, .24)
	b.paint(9, 17, 12, 37, "porch")
	b.raise(13, 17, 13, 37, .12)
	# Pens along the east wall, a judging table, the ribbons.
	for y in [18.5, 22.5, 26.5, 30.5, 34.5]:
		b.fixture(28.6, y - .06, 31.9, y + .06, 1.1, "wood", "counter_top")
	b.table(16.4, 33.4, 19.6, 34.2, .8)
	b.board("wing_fair_double_hog", 20.0, 17.04, .9, {"z": 1.2, "plane": 0.0})
	b.board("fair_lost_property", 31.92, 20.0, .6, {"z": 1.0, "plane": PI / 2})
	for p in [Vector2(18.0, 20.0), Vector2(23.0, 34.0), Vector2(29.5, 24.0), Vector2(10.0, 20.0)]:
		b.prop("hay", p.x, p.y)
	for p in [Vector2(13.6, 27.2), Vector2(26.0, 20.0), Vector2(14.0, 35.0), Vector2(26.0, 35.0)]:
		b.prop("lamp", p.x, p.y)
		b.glow(p.x, p.y, 3.0, .18)
	b.trough(16.0, 28.6, 18.4, 29.0)
	# Out front: the prize hog in fibreglass, the wash rack.
	b.town("giant_hog", 20.5, 44.5, {"solid": .45})
	b.glow(20.5, 44.5, 3.4, .3)
	b.town("searchlight", 15.5, 46.5, {"solid": .35, "glow": true})
	b.trough(27.0, 44.0, 30.0, 44.5)
	b.town("wheelbarrow", 30.5, 47.5)
	b.bale(9.5, 42.5)
	b.bale(10.5, 47.5)
	b.streetlamp(25.0, 41.0)


func ferris_plaza() -> void:
	b.yard(36, 14, 51, 41, "fair_gravel", wheel)
	b.yard(52, 34, 55, 41, "fair_gravel", wheel)
	b.paint(40, 18, 50, 26, "porch")
	b.town("ferris_wheel", 45.5, 21.5, {"solid": .45, "glow": true})
	b.fixture(42.0, 23.6, 49.0, 24.4, .3, "fair_iron", "fair_iron")
	b.glow(45.5, 22.0, 5.0, .35)
	# The carousel's horses on their poles, round a stand.
	b.fixture(44.6, 31.6, 46.4, 33.4, 2.2, "fair_iron", "fair_marquee")
	for k in 6:
		var a := k * TAU / 6.0
		b.town("carousel_horse", 45.5 + cos(a) * 2.6, 32.5 + sin(a) * 2.6, {"solid": .12})
	b.glow(45.5, 32.5, 3.6, .3)
	b.town("balloons", 38.5, 38.5)
	b.town("prize_bear", 49.55, 16.4)
	b.town("port_a_john", 37.5, 15.5, {"solid": .45})
	b.board("fair_pylon", 41.0, 28.0, 1.2, {"glow": true})
	b.board("fair_pylon", 50.0, 28.0, 1.2, {"glow": true})
	b.streetlamp(39.0, 30.0)
	b.streetlamp(53.0, 38.0)


func carny_camp() -> void:
	b.yard(4, 2, 48, 12, "dirt", camp)
	b.fence(4, 13, 48, 13, 1.24)
	b.yard(39, 13, 41, 13, "dirt", camp)
	b.fence(49, 2, 49, 13, 1.6, "fair_iron")
	b.trailer(6, 3, "s", camp)
	b.trailer(17, 3, "s", camp)
	b.trailer(28, 3, "s", camp)
	b.town("grill", 15.5, 9.5, {"solid": .35})
	b.town("porch_couch", 26.5, 9.6)
	b.town("laundry", 37.5, 9.5, {"plane": 0.0, "z": .7, "back": "town_laundry"})
	b.town("generator", 43.5, 4.5, {"solid": .45})
	b.town("dish", 46.5, 10.5, {"solid": .2})
	b.town("tire_stack", 6.5, 10.5, {"solid": .3})
	b.react("tv", 30.0, 4.4, .75, {"id": "x2-fair-0"})
	b.react("cancan", 21.0, 10.0, .4, {"id": "x2-fair-1"})
	b.streetlamp(22.0, 10.0)
	b.streetlamp(40.0, 8.0)


func prize_pavilion() -> void:
	b.building(
		50,
		3,
		78,
		25,
		pavilion,
		{
			"wall": "fair_iron",
			"roof": 3.2,
			"parapet": .5,
			"floor": "porch",
			"ceiling": "fair_iron",
			"windows": 4,
			"lit": .7,
			"light": .9,
			"skin": "fair_booth"
		}
	)
	b.controlled(61, 25, false, {"from": "n", "id": "pavilion-left", "tile": "fair_gate"})
	b.controlled(67, 25, false, {"from": "n", "id": "pavilion-right", "tile": "fair_gate"})
	b.board("fair_pavilion", 64.0, 26.06, 1.3, {"z": 2.0, "plane": 0.0, "glow": true})
	big_top()


## Inside the pavilion, Rudy's big top: the ring in the middle (a sawdust floor
## inside a red and white curb), bleachers down both sides, the PA horn stacks
## at the ring's four corners, helium for the balloons, the rigging overhead,
## and RUDY'S BIG TOP over the stage where the broadcast is cut.
func big_top() -> void:
	var ring := Vector2(64.5, 16.5)
	for y in range(10, 24):
		for x in range(57, 73):
			var d := Vector2(x + .5, y + .5).distance_to(ring)
			if d < 5.2:
				b.paint(x, y, x, y, "dirt")
			elif d < 6.0:
				b.raise(x, y, x, y, .18)
				b.paint(x, y, x, y, "crash_wall")
	b.paint(54, 10, 56, 23, "porch")
	b.paint(72, 10, 73, 23, "porch")
	# Bleachers down both sides, three rows up.
	for tier: Array in [[51.0, 51.95, 1.35], [52.0, 52.95, .9], [53.0, 53.95, .45]]:
		b.fixture(tier[0], 10.0, tier[1], 23.0, tier[2], "grandstand_riser", "bleachers")
	for tier: Array in [[76.05, 76.95, 1.35], [75.05, 76.0, .9], [74.05, 75.0, .45]]:
		b.fixture(tier[0], 10.0, tier[1], 23.0, tier[2], "grandstand_riser", "bleachers")
	# The horn stacks: Rudy's PA at the ring's corners (they fire down lanes).
	for p in [Vector2(56.5, 11.5), Vector2(72.5, 11.5), Vector2(56.5, 21.5), Vector2(72.5, 21.5)]:
		b.town("pa_horns", p.x, p.y, {"solid": .35})
	# Helium for the balloons (it goes up), the balloons, the prizes for cover.
	for p in [Vector2(55.5, 23.5), Vector2(73.5, 23.5), Vector2(59.5, 9.5)]:
		b.town("propane_tank", p.x, p.y, {"solid": .4})
	for p in [Vector2(54.5, 14.5), Vector2(73.5, 18.5), Vector2(69.5, 9.5)]:
		b.town("balloons", p.x, p.y, {"solid": .3})
	for p in [Vector2(54.5, 19.5), Vector2(73.5, 14.5), Vector2(59.5, 24.5), Vector2(69.5, 24.5)]:
		b.town("prize_bear", p.x, p.y, {"solid": .35})
	b.town("cotton_candy", 55.5, 9.5, {"solid": .4})
	b.town("gas_cans", 72.6, 9.6)
	# The rigging: lines from the corners to the king pole's crown overhead.
	for c in [Vector2(51.5, 4.5), Vector2(77.5, 4.5), Vector2(51.5, 24.5), Vector2(77.5, 24.5)]:
		b.cable(c.x, c.y, ring.x, ring.y, 3.05)
	# Strings of bulbs across the ring, lit with the concession power.
	for y: float in [11.5, 16.5, 21.5]:
		b.cable(55.0, y, 74.0, y, 2.95)
		b.board(
			"fair_bulbs",
			64.5,
			y,
			.39,
			{"z": 2.55, "plane": 0.0, "signal": "concession", "back": "fair_bulbs_off"}
		)
	# The ringmaster's board hung over the front of the stage.
	b.board("big_top_sign", 64.5, 9.92, .7, {"z": 1.95, "plane": 0.0, "hung": true})
	b.glow(ring.x, ring.y, 6.5, .3)
	b.meta["boss_arena"] = {
		"rudy":
		{
			"box": [51, 4, 77, 24],
			"ring": [ring.x, ring.y],
			"horns": [[56.5, 11.5], [72.5, 11.5], [72.5, 21.5], [56.5, 21.5]],
			"approach": [64.5, 24.0],
			"lights":
			[
				[64.5, 13.0, 2.6, 7.0, [1.0, .9, .7], .9],
				[64.5, 20.0, 2.6, 6.0, [1.0, .55, .45], .6],
				[64.5, 6.5, 2.4, 6.0, [1.0, .82, .55], .8],
				[54.5, 16.5, 2.4, 5.0, [.7, .6, 1.0], .45],
				[74.5, 16.5, 2.4, 5.0, [.7, .6, 1.0], .45],
			],
		},
	}
	# The stage and the PA booth on it: where the broadcast is cut.
	b.raise(56, 4, 72, 8, .36)
	b.raise(56, 9, 72, 9, .18)
	b.paint(56, 4, 72, 9, "floor_tile")
	b.wall(60, 4, 60, 6, "fair_booth", 3.0)
	b.wall(68, 4, 68, 6, "fair_booth", 3.0)
	b.room(
		61,
		4,
		67,
		6,
		"floor_tile",
		pa,
		{"roof": 2.6, "skin": "fair_booth", "light": .85, "ground": .36}
	)
	b.raise(61, 4, 67, 6, .36)
	b.station(
		"broadcast",
		64.5,
		5.5,
		"CUT THE PRIZE BROADCAST",
		"RUDY RACKET! GET BEHIND THE PRIZE STALLS.",
		{
			"requires": ["concession", "games", "bell"],
			"opens": [[78, 8]],
			"sectors": [pavilion, pa],
			"cue": "broadcast_cut"
		}
	)
	b.quest("quest_pa_rig", 63.5, 4.5, "broadcast")
	b.board("detail_stage_footlights", 64.0, 9.4, .4, {"z": .18})
	for x in [58.0, 70.0]:
		b.town("searchlight", x + .5, 8.5, {"glow": true})
	b.controlled(78, 8, true, {"from": "w", "id": "service-alley"})
	for p in [Vector2(57.0, 12.0), Vector2(71.0, 12.0), Vector2(64.0, 18.0), Vector2(64.0, 7.0)]:
		b.prop("lamp", p.x, p.y)
		b.glow(p.x, p.y, 3.2, .2)


func service_exit() -> void:
	b.yard(79, 2, 104, 12, "tracks", service)
	b.fence(79, 13, 106, 13, 1.6, "fair_iron")
	b.fence(105, 2, 105, 12, 1.6, "fair_iron")
	b.paint(92, 3, 101, 10, "concrete")
	b.raise(98, 3, 101, 5, .36)
	b.quest("quest_exit_fair", 96.5, 4.5, "exit")
	b.prop("pickup_truck", 88.5, 5.0)
	for p in [Vector2(83.5, 10.5), Vector2(84.5, 10.6), Vector2(102.5, 10.5)]:
		b.crate_stack(p.x, p.y, 1.0)
	b.town("generator", 90.5, 10.5, {"solid": .45})
	b.streetlamp(94.0, 9.0)


func freight_lot() -> void:
	b.yard(78, 26, 79, 41, "tracks", freight)
	b.wall(77, 26, 77, 41, "fair_iron", 1.6)
	b.controlled(
		77, 33, true, {"from": "e", "id": "games-shortcut", "tile": "fair_gate", "roof": 0.0}
	)
	b.yard(80, 14, 106, 41, "concrete", freight)
	b.fence(80, 42, 106, 42, 1.6, "fair_iron")
	b.fence(107, 14, 107, 27, 1.6, "fair_iron")
	b.fence(107, 33, 107, 41, 1.6, "fair_iron")
	# Freight containers, the stacks between them, the forklift.
	for c in [
		[82.0, 28.0, 88.0, 30.4],
		[82.0, 34.0, 88.0, 36.4],
		[96.0, 30.0, 102.0, 32.4],
		[96.0, 36.0, 104.0, 38.4]
	]:
		b.fixture(c[0], c[1], c[2], c[3], 2.2, "fair_iron", "tin")
	b.board("wing_fair_freight", 88.06, 29.2, .9, {"z": 1.2, "plane": -PI / 2})
	b.board("detail_freight_cartons", 95.94, 31.2, .56, {"z": .5, "plane": PI / 2})
	for p in [
		Vector2(91.5, 27.5),
		Vector2(92.5, 27.5),
		Vector2(93.5, 39.5),
		Vector2(104.5, 27.5),
		Vector2(81.5, 39.5)
	]:
		b.crate_stack(p.x, p.y, .75 if int(p.x) % 2 else 1.4)
	b.town("forklift", 92.5, 34.5, {"solid": .45})
	b.town("pallet_stack", 104.5, 33.5, {"solid": .45})
	b.town("generator", 101.5, 18.5, {"solid": .45})
	# The raffle office: the PA patch lead on the drawer, the trunk tag.
	b.building(
		83,
		15,
		94,
		23,
		freight,
		{
			"wall": "fair_booth",
			"roof": 2.4,
			"floor": "floor_tile",
			"light": .78,
			"skin": "detail_wall_raffle_stripes",
			"windows": 3
		}
	)
	b.door(88, 23, false, {"from": "n", "id": "raffle-door"})
	b.table(85.0, 16.2, 88.0, 17.0, .8)
	b.board("detail_raffle_drawer", 86.4, 16.6, .45, {"z": .8})
	b.board("wing_fair_receipts", 93.94, 19.0, .7, {"z": 1.0, "plane": PI / 2})
	b.notes.append(
		[
			90.0,
			17.0,
			"BLUE TRUNK TAG",
			"BESSIE'S TAG / FOUND UNDER THE PRIZE RIBBONS. SENT TO BLACKWATER WITH THE CRATES.",
			0.0
		]
	)
	b.board("county_note", 90.0, 16.2, .3, {"z": .8, "plane": 0.0})
	b.table(89.2, 16.2, 92.0, 17.0, .8)
	b.prop("lamp", 88.5, 19.0)
	b.secret(
		94, 21, true, [95, 20, 97, 22], {"from": "w", "id": "lost-socks", "tile": "fair_booth"}
	)
	b.wall(95, 19, 98, 19, "fair_booth", 2.7)
	b.wall(95, 23, 98, 23, "fair_booth", 2.7)
	b.wall(98, 20, 98, 22, "fair_booth", 2.7)
	b.room(95, 20, 97, 22, "floor_tile", freight, {"roof": 2.4, "light": .55, "skin": "fair_booth"})
	b.board("detail_lost_property_tray", 96.5, 20.4, .4, {"z": 0.0})
	b.streetlamp(90.0, 26.0)
	b.streetlamp(100.0, 22.0)
	b.distant_cues.append([101.5, 18.5, "distant_fair_generator"])


func sideshows() -> void:
	b.yard(108, 2, 126, 41, "fair_gravel", sideshow)
	b.yard(107, 28, 107, 32, "tracks", sideshow)
	b.fence(108, 42, 126, 42, 1.6, "fair_iron")
	b.yard(116, 42, 118, 42, "tracks", sideshow)
	# Tents along both sides: the two-headed hog, the rope man, the saucer pilot.
	b.booth(
		108, 30, 114, 36, sideshow, "e", {"sign": "wing_fair_double_hog", "skin": "fair_marquee"}
	)
	b.booth(108, 20, 114, 26, sideshow, "e", {"sign": "wing_fair_sideshow", "skin": "fair_marquee"})
	b.booth(120, 22, 126, 28, sideshow, "w", {"sign": "wing_fair_rope", "skin": "fair_marquee"})
	b.booth(120, 32, 126, 38, sideshow, "w", {"sign": "wing_fair_sideshow", "skin": "fair_marquee"})
	b.town("giant_hog", 110.0, 32.4, {"scale": .55})
	b.town("carousel_horse", 123.0, 25.0, {"scale": .8})
	# The PA shed: where the patch lead goes in.
	b.building(
		115,
		3,
		125,
		10,
		pa,
		{
			"wall": "fair_booth",
			"roof": 2.4,
			"floor": "porch",
			"light": .8,
			"skin": "fair_booth",
			"windows": 3
		}
	)
	b.door(117, 10, false, {"from": "n", "id": "backstage-pa-shortcut"})
	b.station(
		"games",
		122.5,
		5.5,
		"PATCH THE BACKSTAGE PA",
		"PA PATCHED. TAKE THE SERVICE CUT BACK TO THE MIDWAY.",
		{
			"opens": [[77, 33]],
			"sectors": [games, sideshow],
			"cue": "broadcast_cut",
			"held": "pa_patch"
		}
	)
	b.quest("quest_patchbay", 123.5, 4.5, "games")
	b.board("detail_pa_cable_case", 119.0, 4.0, .5, {"z": .0, "plane": 0.0})
	b.prop("lamp", 120.0, 6.5)
	b.distant_cues.append([122.5, 5.5, "distant_fair_pa"])
	b.exchanges.append(
		{
			"id": "show-pa",
			"x": 118.0,
			"y": 14.0,
			"stop_at": "",
			"lines": ["PA: CLEAR THE STAGE.", "VOICE: TELL THE GOAT."]
		}
	)
	b.town("generator", 110.5, 12.5, {"solid": .45})
	b.town("port_a_john", 124.5, 13.5, {"solid": .45})
	b.room(127, 24, 128, 26, "floor_tile", sideshow, {"roof": 2.2, "light": .5})
	b.secret(
		126,
		25,
		true,
		[127, 24, 128, 26],
		{"from": "w", "id": "sideshow-panel-flank", "tile": "fair_booth"}
	)
	for p in [Vector2(117.0, 18.0), Vector2(117.0, 30.0), Vector2(112.0, 6.0)]:
		b.streetlamp(p.x, p.y)
	for k in 5:
		b.board("fair_pylon", 116.0 + (k % 2) * 3.0, 14.0 + k * 5.0, 1.2, {"glow": true})


func game_court() -> void:
	b.yard(77, 43, 106, 71, "fair_gravel", games)
	b.paint(80, 50, 104, 52, "tracks")
	b.fence(106, 43, 106, 54, 1.6, "fair_iron")
	b.fence(106, 59, 106, 71, 1.6, "fair_iron")
	b.yard(77, 43, 77, 52, "fair_gravel", games)
	b.booth(86, 43, 92, 48, games, "s", {"sign": "fair_redemption"})
	b.booth(95, 43, 101, 48, games, "s", {"sign": "fair_prize_pile"})
	b.booth(86, 64, 92, 70, games, "n", {"sign": "fair_lost_property"})
	b.booth(95, 64, 101, 70, games, "n", {"sign": "wing_fair_receipts"})
	# The tin rooster: the stand, the counter and the backstop with its targets.
	b.building(
		78,
		54,
		84,
		58,
		games,
		{"wall": "fair_booth", "roof": 2.3, "floor": "porch", "light": .95, "skin": "fair_booth"}
	)
	b.room(78, 55, 78, 57, "porch", games, {"roof": 2.05, "light": 1.0})
	b.board("county_gallery_sign", 77.4, 56.0, .6, {"z": 1.6, "plane": PI / 2})
	b.board("county_gallery_backstop", 83.96, 56.4, 1.0, {"z": .3, "plane": PI / 2})
	b.prop("lamp", 81.0, 56.0)
	b.glow(81.0, 56.0, 2.6, .3)
	b.town("high_striker", 82.5, 61.5, {"solid": .3})
	b.town("balloons", 85.5, 54.5)
	b.town("prize_bear", 103.6, 50.0)
	b.town("cotton_candy", 103.5, 61.5, {"solid": .4})
	b.react("vending", 82.6, 66.0, 1.5, {"id": "x2-fair-2"})
	b.react("jukebox", 104.6, 66.0, 1.4, {"id": "x2-fair-5"})
	b.board("fair_games_arrow", 77.6, 52.6, .7, {"z": 1.0, "plane": PI / 2})
	b.distant_cues.append([92.0, 55.0, "distant_fair_rattle"])
	b.exchanges.append(
		{
			"id": "freight-pa",
			"x": 95.0,
			"y": 57.0,
			"stop_at": "",
			"lines": ["PA: SAVE THAT ROPE.", "VOICE: FOR THE SHOW?"]
		}
	)
	b.streetlamp(90.0, 57.5)
	b.streetlamp(100.0, 57.0)
	scatter_spill([Vector2(88.0, 59.0), Vector2(97.0, 53.3)])


func derby_arena() -> void:
	b.yard(107, 43, 126, 71, "dirt", derby)
	b.yard(106, 55, 106, 58, "tracks", derby)
	b.fence(108, 71, 126, 71, 1.6, "fair_iron")
	# Bleachers round the ring, a concrete rail, wrecks in the mud.
	b.fixture(108.2, 44.0, 109.4, 70.0, .8, "bleachers", "bleachers")
	b.fixture(124.6, 44.0, 125.8, 70.0, .8, "bleachers", "bleachers")
	b.fixture(111.0, 69.0, 123.0, 70.4, .8, "bleachers", "bleachers")
	b.fence(111, 46, 122, 46, .9, "concrete")
	b.yard(115, 46, 117, 46, "dirt", derby)
	for c in [
		[113.5, 52.5, true],
		[118.5, 55.0, false],
		[114.0, 62.0, false],
		[120.5, 64.5, true],
		[112.0, 58.0, true]
	]:
		b.car(c[0], c[1], c[2], "tin" if c[2] else "mill_tin")
	b.town("truck_blocks", 119.5, 50.5, {"solid": .45})
	for p in [
		Vector2(111.5, 49.5), Vector2(122.5, 49.5), Vector2(111.5, 66.5), Vector2(122.5, 59.5)
	]:
		b.town("tire_stack", p.x, p.y, {"solid": .3})
	for k in 8:
		b.mark("detail_wear_oil", 112.0 + (k % 4) * 3.0, 50.0 + (k / 4) * 9.0, k * .8, 1.6, .7)
	b.town("searchlight", 110.5, 45.5, {"solid": .35, "glow": true})
	b.town("searchlight", 123.5, 45.5, {"solid": .35, "glow": true})
	b.glow(117.0, 57.0, 6.0, .25)
	b.distant_cues.append([117.0, 57.0, "distant_derby_engine"])
	b.streetlamp(116.0, 66.0)


func sound_and_story() -> void:
	b.distant_cues.append([64.0, 58.0, "distant_fair_motif"])
	for l in [
		["GATE", 62, 75],
		["MIDWAY", 61, 60],
		["FOOD", 26, 60],
		["SHOW BARN", 15, 26],
		["WHEEL", 41, 30],
		["CAMP", 10, 9],
		["PRIZES", 60, 15],
		["EXIT", 90, 6],
		["FREIGHT", 88, 32],
		["SIDESHOW", 112, 14],
		["PA", 118, 6],
		["GAMES", 90, 56],
		["DERBY", 114, 60],
	]:
		b.label(String(l[0]), int(l[1]), int(l[2]))
	b.distant_cues.append([45.5, 21.5, "distant_fair_motif"])


func cast() -> void:
	for e in [
		["coot", 64.5, 62.0, "midway-coot"],
		["coot", 55.5, 68.5, "ticket-coot"],
		["barker", 55.5, 47.0, "midway-barker"],
		["billy", 66.5, 40.0, "midway-billy"],
		["skeeter", 62.0, 70.6, "gate-skeeter"],
		["crawler", 70.0, 52.0, "plaza-crawler"],
		["billy", 30.5, 60.5, "concession-billy"],
		["coot", 42.5, 61.5, "concession-coot"],
		["crawler", 22.0, 61.0, "concession-crawler"],
		["bottle_tosser", 10.0, 66.0, "alley-tosser"],
		["clone", 9.5, 58.5, "breaker-clone"],
		["clone", 20.5, 27.0, "ring-clone"],
		["barker", 11.0, 25.0, "bleacher-barker"],
		["crawler", 28.5, 33.0, "pen-crawler"],
		["coot", 23.0, 45.0, "hog-coot"],
		["alien", 45.5, 28.0, "wheel-alien"],
		["skeeter", 40.0, 18.0, "wheel-skeeter"],
		["billy", 50.0, 37.0, "wheel-billy"],
		["coot", 12.0, 8.0, "camp-coot"],
		["billy", 33.0, 9.0, "camp-billy"],
		["clone", 87.5, 51.5, "games-clone"],
		["coot", 97.0, 58.0, "games-coot"],
		["skeeter", 84.0, 66.0, "games-skeeter"],
		["barker", 98.5, 49.5, "court-barker"],
		["bottle_tosser", 116.0, 48.5, "derby-tosser"],
		["billy", 117.0, 60.0, "derby-billy"],
		["coot", 121.5, 67.5, "derby-coot"],
		["crawler", 110.6, 55.0, "derby-crawler"],
		["alien", 92.0, 26.5, "freight-shooter"],
		["clone", 85.5, 37.6, "freight-clone"],
		["coot", 99.5, 34.5, "freight-coot"],
		["skeeter", 89.5, 20.0, "raffle-skeeter"],
		["barker", 117.0, 22.0, "catwalk-barker"],
		["crawler", 113.0, 38.5, "sideshow-crawler"],
		["coot", 122.0, 30.5, "print-shop-coot"],
		["clone", 120.0, 8.0, "pa-stair-clone"],
		["bottle_tosser", 112.5, 9.0, "sideshow-tosser"],
		["billy", 76.0, 36.0, "cut-billy"],
		["coot", 64.5, 23.5, "pavilion-coot"],
		["alien", 55.5, 17.5, "pavilion-guard"],
		["clone", 70.5, 10.5, "pavilion-clone"],
		["barker", 60.5, 20.5, "wave-barker"],
		["alien", 68.5, 20.5, "wave-guard"],
		["crawler", 69.5, 12.5, "wave-crawler"],
		["rudy", 64.5, 16.5, "show-ringmaster"],
		["coot", 90.0, 8.5, "exit-coot"],
	]:
		b.enemy(String(e[0]), float(e[1]), float(e[2]), String(e[3]))
	b.partners.append(["concession-crawler", "concession-billy", 1])
	for p in [
		["shells", 64.5, 66.0],
		["rinds", 66.0, 77.0],
		["bullets", 58.0, 77.6],
		["beer", 57.6, 72.5],
		["shotgun", 58.4, 57.0],
		["shells", 69.6, 64.0],
		["whiskey", 62.0, 44.0],
		["rinds", 70.0, 37.5],
		["bullets", 58.4, 30.0],
		["shells", 25.0, 58.0],
		["beer", 36.5, 59.6],
		["rinds", 45.5, 62.6],
		["bullets", 11.0, 55.0],
		["whiskey", 7.0, 59.5],
		["rocket_ammo", 10.5, 60.0],
		["bottle_launcher", 23.5, 34.5],
		["rocket_ammo", 10.5, 18.0],
		["shells", 31.0, 37.0],
		["moonshine", 10.0, 36.0],
		["cowpie", 16.5, 24.0],
		["rinds", 24.0, 42.0],
		["rifle_ammo", 48.5, 16.0],
		["beer", 38.0, 26.0],
		["shells", 53.0, 40.0],
		["bullets", 8.5, 9.6],
		["rifle", 31.5, 5.0],
		["rifle_ammo", 20.5, 5.0],
		["whiskey", 44.0, 9.6],
		["shells", 80.0, 48.0],
		["beer", 104.0, 46.0],
		["bullets", 80.6, 68.6],
		["rinds", 93.0, 58.0],
		["rifle_ammo", 104.5, 69.0],
		["keg_ammo", 98.0, 62.6],
		["shells", 110.5, 61.0],
		["powder_keg", 116.0, 44.6],
		["rinds", 123.0, 62.0],
		["whiskey", 112.0, 68.0],
		["pa_patch", 86.5, 18.0],
		["dynamite", 96.5, 21.5],
		["arm_ammo", 95.5, 20.5],
		["milk_ammo", 82.0, 25.0],
		["shells", 105.0, 40.0],
		["rinds", 93.5, 26.0],
		["keg_ammo", 106.5, 16.0],
		["beer", 125.0, 16.0],
		["shells", 111.0, 4.0],
		["rocket_ammo", 124.0, 39.0],
		["bullets", 116.5, 5.0],
		["whiskey", 52.5, 6.0],
		["rinds", 74.6, 24.0],
		["shells", 54.4, 24.2],
		["rocket_ammo", 76.0, 4.0],
		["beer", 81.0, 11.0],
		["rinds", 103.0, 4.0],
	]:
		b.pickup(String(p[0]), float(p[1]), float(p[2]))
	(
		b
		. triggers
		. append(
			{
				"id": "lights-up",
				"when": {"station": "concession"},
				"do":
				[
					{"message": "THE MIDWAY LIGHTS UP. SO DOES EVERYTHING ON IT.", "for": 3.0},
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
				"id": "derby-roar",
				"when": {"area": [110, 47, 123, 68]},
				"do":
				[
					{"message": "THE DERBY'S STILL RUNNING. NOBODY TOLD THE DRIVERS.", "for": 3.0},
					{"sound": "distant_derby_engine", "at": [117.0, 57.0]},
					{"shake": .3},
					{"alert": 12}
				],
			}
		)
	)


## The last pass: the fair packed with what a fair leaves about, and lit.
func detail() -> void:
	for e in [
		["coot", 100.0, 75.0, "lot-coot"],
		["skeeter", 30.0, 80.0, "lot-skeeter"],
		["billy", 64.0, 33.5, "north-midway-billy"],
		["crawler", 40.0, 36.0, "carousel-crawler"],
	]:
		b.enemy(String(e[0]), float(e[1]), float(e[2]), String(e[3]))


## The polish pass: the empty lots filled the way a fair fills them.
func polish() -> void:
	# Set pieces where a yard read unfinished, each against a wall, nothing strewn.
	# The service exit: a pallet of stock and a crate by the back fence.
	b.town("pallet_stack", 82.5, 2.78)
	b.prop("crate", 81.1, 2.45)
	# The freight lot: the forklift left by the dock, its pallets, the cartons.
	b.town("forklift", 79.5, 40.85)
	b.town("pallet_stack", 81.4, 41.15)
	b.board("detail_freight_cartons", 78.62, 41.98, .6, {"z": 0.0, "plane": PI})
	# More booths down the middle of the game court, back to back.
	b.booth(86, 52, 91, 56, games, "w", {"sign": "fair_prize_pile"})
	b.booth(92, 52, 97, 56, games, "e", {"sign": "fair_redemption"})
	# Cars parked nose to tail in the field.
	for k in 8:
		b.car(10.0 + k * 5.5, 79.5, true, "tin" if k % 2 else "mill_tin")
		if k < 5:
			b.car(84.0 + k * 7.0, 79.5, true, "mill_tin" if k % 2 else "tin")
	# The sideshow stage, its bleachers and its spotlights.
	b.raise(116, 14, 124, 17, .36)
	b.raise(116, 18, 124, 18, .18)
	b.paint(116, 14, 124, 18, "porch")
	b.fixture(115.0, 19.6, 125.0, 20.4, .6, "bleachers", "bleachers")
	for e in [
		["barker", 120.0, 15.5, "stage-barker"],
		["crawler", 89.0, 58.5, "court-crawler"],
		["bottle_tosser", 46.0, 78.0, "lot-tosser"],
	]:
		b.enemy(String(e[0]), float(e[1]), float(e[2]), String(e[3]))
	(
		b
		. triggers
		. append(
			{
				"id": "showtime",
				"when": {"area": [114, 12, 126, 21]},
				"do":
				[
					{"message": "SHOWTIME. THE BARKER WANTS A VOLUNTEER.", "for": 3.0},
					{"sound": "crowd_cheer", "at": [120.0, 18.0]},
					{"wake": ["stage-barker"]}
				],
			}
		)
	)
