## Buzzard Bend Speedway's people and things: who stands where, what lies
## about, the set pieces that fire, the map's labels and the dressing laid by
## hand district by district (speedway_plan.gd lays the ground first).
extends RefCounted

var b
var plan


func dress(p_plan) -> void:
	plan = p_plan
	b = plan.b
	labels()
	dress_track()
	dress_pits()
	dress_infield()
	dress_stands()
	dress_salvage()
	dress_lots()
	dress_grounds()
	cast()
	pickups()
	set_pieces()


func labels() -> void:
	for l in [
		["TRUCK STOP", 4, 88],
		["DINER", 6, 60],
		["HAULERS", 6, 22],
		["PIT ROW", 40, 10],
		["FUEL", 66, 3],
		["OVAL", 44, 25],
		["CAMP", 42, 46],
		["JUMP", 54, 33],
		["FIGURE 8", 82, 45],
		["STANDS", 50, 75],
		["BOOTH", 71, 77],
		["CONCOURSE", 58, 85],
		["SALVAGE", 124, 8],
		["CRUSHER", 130, 31],
		["TOW LOT", 118, 88],
	]:
		b.label(String(l[0]), int(l[1]), int(l[2]))


## The oval: wrecks against the wall where the last heat went wrong, tyres
## stacked at the inside of the turns, the wreckers' leavings.
func dress_track() -> void:
	b.town("wrecked_derby", 109.5, 27.5, {"solid": .45})
	b.fixture(108.5, 27.1, 110.5, 27.9, .3, "mill_tin", "tin")
	b.town("stock_car", 37.5, 55.5, {"solid": .45})
	b.fixture(36.5, 55.1, 38.5, 55.9, .3, "mill_tin", "tin")
	b.town("tire_pile", 33.5, 38.5, {"solid": .4})
	b.town("tire_pile", 114.5, 52.5, {"solid": .4})
	for p in [Vector2(40.5, 33.5), Vector2(40.5, 57.5), Vector2(107.5, 33.5), Vector2(107.5, 57.5)]:
		b.town("tire_stack", p.x, p.y, {"solid": .3})
		b.town("tire_stack", p.x + (1.0 if p.x < 70 else -1.0), p.y, {"solid": .3})
	for k in 10:
		var t := k * .62
		b.mark("detail_wear_oil", 54.0 + k * 4.4, 65.0 + sin(t) * 1.6, .1, 1.6, .6)
		b.mark("detail_wear_oil", 54.0 + k * 4.4, 25.5 + cos(t) * 1.6, -.1, 1.6, .6)
	# The busted wall into the salvage yard: the car that went through it.
	b.town("wreck_sedan", 122.5, 48.5, {"solid": .45})
	b.fixture(121.6, 48.1, 123.4, 48.9, .3, "mill_tin", "tin")


## Pit row: in the bays the cars and their crews' gear; out on the lane the
## jacks, the fuel cans and the tyres waiting for a stop.
func dress_pits() -> void:
	var cars := [
		"stock_car",
		"",
		"stock_car_b",
		"wrecked_derby",
		"",
		"stock_car",
		"",
		"stock_car_b",
		"",
		"stock_car",
		"",
		"wrecked_derby",
		""
	]
	var gear := ["tool_chest", "engine_stand", "nitro_rack", "tool_chest", "engine_stand"]
	var bay := 0
	for x0 in range(34, 110, 6):
		var cx := x0 + 3.0
		var car := String(cars[bay % cars.size()])
		if car != "":
			b.town(car, cx, 10.5, {"solid": .45})
			b.fixture(cx - 1.0, 10.1, cx + 1.0, 10.9, .3, "mill_tin", "tin")
		else:
			b.town("engine_hoist", cx, 10.5, {"solid": .45})
		b.town(String(gear[bay % gear.size()]), x0 + 1.5, 7.5, {"solid": .3})
		if bay % 2 == 1:
			b.town("tire_stack", x0 + 4.5, 7.5, {"solid": .3})
		bay += 1
	b.react("vending", 34.6, 13.4, 1.5, {"id": "pits-vending"})
	b.react("cans", 88.5, 7.5, .4, {"id": "pits-cans"})
	for x in range(36, 110, 12):
		b.prop("lamp", x + .5, 10.5)
		b.glow(x + .5, 10.5, 3.4, .18)
	# The lane.
	for x in [42.5, 54.5, 86.5, 104.5]:
		b.town("tire_stack", x, 17.5, {"solid": .3})
	b.town("gas_cans", 46.5, 19.5, {"solid": .25})
	b.town("gas_cans", 90.5, 19.5, {"solid": .25})
	b.town("tool_chest", 80.5, 17.5, {"solid": .3})
	for x in range(40, 110, 8):
		b.mark("detail_wear_oil", x + 2.0, 18.0, 0.0, 1.2, .8)
	# The alley behind: crates of parts and tyres against the garage's back.
	for p in [
		Vector2(30.5, 2.5),
		Vector2(46.5, 4.5),
		Vector2(60.5, 1.5),
		Vector2(88.5, 1.5),
		Vector2(100.5, 4.5),
		Vector2(116.5, 2.5)
	]:
		b.crate_stack(p.x, p.y, .75 if int(p.x) % 2 else 1.4)
	b.town("tire_pile", 52.5, 2.5, {"solid": .45})
	b.town("tire_pile", 96.5, 2.5, {"solid": .45})
	b.town("generator", 112.5, 4.5, {"solid": .45})
	b.react("pipe", 76.5, 4.5, .9, {"id": "depot-pipe"})
	b.ruptures["depot-pipe"] = [76.5, 4.5, "FUEL LINE SPRAYS. THAT'S 110 PROOF."]
	b.fuel_drums.append([66.5, 4.6])
	b.prop("barrel", 66.5, 4.6)
	b.fuel_drums.append([82.5, 4.6])
	b.prop("barrel", 82.5, 4.6)
	# The east end of the lane, round the corner of the oval.
	b.town("canned_ham", 112.5, 26.5, {"solid": .45})
	b.town("cooler", 115.5, 25.5, {"solid": .3})
	b.town("burn_barrel", 117.5, 30.5, {"solid": .3, "glow": true})
	b.glow(117.5, 30.5, 3.5, .3)
	b.streetlamp(110.0, 36.0)


## The infield camp: the trailers, the fire and the chairs round it, the
## coolers; the monster jump and its truck; the figure 8's flag stand.
func dress_infield() -> void:
	b.town("burn_barrel", 50.5, 46.5, {"solid": .3, "glow": true})
	b.glow(50.5, 46.5, 4.0, .34)
	b.town("camp_chairs", 48.0, 44.9)
	b.town("camp_chairs", 53.0, 48.1)
	b.town("cooler", 47.5, 47.5, {"solid": .3})
	b.town("cooler", 54.5, 44.5, {"solid": .3})
	b.town("canned_ham", 58.5, 44.5, {"solid": .45})
	b.town("canned_ham", 44.5, 55.5, {"solid": .45})
	b.town("grill", 56.5, 50.5, {"solid": .3})
	b.town("picnic_table", 60.5, 51.5, {"solid": .45})
	b.town("port_a_john", 38.6, 37.5)
	b.town("laundry", 45.0, 39.4, {"plane": 0.0})
	b.town("porch_couch", 62.5, 47.5)
	b.react("cancan", 52.0, 50.0, .4, {"id": "camp-can"})
	b.react("bottles", 49.0, 43.6, .42, {"id": "camp-bottles"})
	b.board("speedway_camping", 42.0, 48.5, .9, {"z": .5, "plane": 0.0})
	# The jump.
	b.board("speedway_jump", 51.0, 37.5, .9, {"z": .5, "plane": PI})
	b.town("crushed_stack", 60.5, 37.5, {"solid": .45})
	b.town("crushed_stack", 60.5, 32.5, {"solid": .45})
	b.town("floodlight_tower", 46.5, 51.5, {"solid": .25, "glow": true})
	b.glow(46.5, 51.5, 9.0, .3)
	b.streetlamp(62.0, 40.0)
	# Inside the figure 8: wrecks of the last derby, mud, the islands' tyres.
	b.town("wrecked_derby", 72.5, 45.5, {"solid": .45})
	b.fixture(72.1, 44.5, 72.9, 46.5, .3, "mill_tin", "tin")
	b.town("wrecked_derby", 105.5, 45.5, {"solid": .45})
	b.fixture(105.1, 44.5, 105.9, 46.5, .3, "mill_tin", "tin")
	for k in 8:
		var a := k * TAU / 8.0
		b.mark("detail_wear_oil", 79.5 + cos(a) * 7.0, 45.5 + sin(a) * 7.0, a, 1.4, .7)
		b.mark("detail_wear_oil", 98.5 + cos(a) * 7.0, 45.5 + sin(a) * 7.0, a, 1.4, .7)


## The stands: what the crowd left on the rows, the scoreboard at the top.
func dress_stands() -> void:
	for p in [
		Vector2(52.5, 72.5),
		Vector2(66.5, 74.5),
		Vector2(83.5, 73.5),
		Vector2(96.5, 76.5),
		Vector2(56.5, 78.5)
	]:
		b.town("cooler", p.x, p.y, {"solid": .3})
	b.react("cans", 64.5, 76.5, .4, {"id": "stands-cans"})
	b.react("bottles", 92.5, 72.5, .42, {"id": "stands-bottles"})
	b.board("speedway_standings", 96.0, 79.94, 1.4, {"z": .4, "plane": PI})
	b.board("speedway_ad_chaw", 52.5, 79.94, .8, {"z": .4, "plane": PI})
	b.town("trophy", 76.5, 77.5, {"z": .0})


## The salvage yard: the wrecks between the stacks, parts on the ground where
## the pullers left them.
func dress_salvage() -> void:
	for p in [
		["wreck_pickup", 131.5, 7.5],
		["wreck_sedan", 139.5, 12.5],
		["crushed_stack", 126.5, 18.5],
		["wreck_sedan", 130.5, 45.5],
		["wreck_pickup", 136.5, 52.5],
		["crushed_stack", 145.5, 45.5],
		["wreck_sedan", 124.5, 57.5],
	]:
		b.town(String(p[0]), float(p[1]), float(p[2]), {"solid": .45})
	b.town("tire_pile", 147.5, 3.5, {"solid": .45})
	b.town("tire_pile", 130.5, 64.5, {"solid": .45})
	b.town("engine_stand", 142.5, 7.5, {"solid": .3})
	b.town("hubcap_board", 135.0, 41.94, {"plane": PI})
	b.react("scrap", 141.5, 18.5, .7, {"id": "salvage-scrap"})
	b.react("scrap", 125.5, 52.5, .7, {"id": "salvage-scrap-b"})
	b.board("speedway_salvage_arrow", 118.0, 20.94, .4, {"z": 1.3, "plane": PI})


func dress_lots() -> void:
	b.town("cooler", 30.5, 90.5, {"solid": .3})
	b.react("cancan", 34.0, 88.0, .4, {"id": "truck-can"})
	b.prop("pickup_truck", 50.5, 96.5)
	b.prop("pickup_truck_b", 70.5, 98.5)
	b.prop("pickup_truck", 94.5, 96.5)
	b.town("monster_truck", 100.5, 99.5, {"solid": .45})
	b.board("speedway_pits_arrow", 37.0, 69.94, .4, {"z": 1.3, "plane": PI})


## The grounds round the oval: the fans' trucks parked in rows, each team's
## pit cart by its rig, the ticket shack at the gate, the wrecks the tow man
## has lined up for the crusher.
func dress_grounds() -> void:
	# The grandstand parking: two rows of the crowd's trucks nose to nose.
	var trucks := ["pickup_truck", "pickup_truck_b"]
	for k in 12:
		var x := 48.5 + k * 4.5
		if absf(x - 66.0) < 2.0 or absf(x - 82.0) < 2.0:
			continue
		b.prop(trucks[k % 2], x, 95.6)
		if k % 3 != 1:
			b.prop(trucks[(k + 1) % 2], x + 1.0, 100.4)
	b.paint(45, 97, 105, 98, "tracks")
	# Each team's pit cart beside its rig in the haulers' lot.
	for y in [10.5, 20.5, 32.5, 42.5]:
		b.town("tool_chest", 6.5, y, {"solid": .3})
		b.town("tire_stack", 8.5, y, {"solid": .3})
		b.town("gas_cans", 10.5, y, {"solid": .25})
	b.town("stock_car", 13.5, 2.5, {"solid": .45})
	b.fixture(12.5, 2.1, 14.5, 2.9, .3, "mill_tin", "tin")
	b.town("canned_ham", 22.5, 47.5, {"solid": .45})
	# The ticket shack and turnstiles at the gate.
	b.building(
		36, 73, 41, 77, plan.truck, {"wall": "tin", "roof": 2.3, "floor": "concrete", "windows": 2}
	)
	b.door(38, 77, false, {"from": "n", "id": "ticket-shack"})
	b.board("speedway_camping", 36.94, 79.0, .7, {"z": .6, "plane": -PI / 2})
	for y in [85.5, 87.5]:
		b.fixture(42.6, y - .3, 43.4, y + .3, .95, "steel_mesh", "tin")
	# A roadside billboard by the diner, on its own legs.
	b.board("speedway_entry", 33.0, 66.0, 2.2, {"z": 1.6, "plane": -PI / 2})
	b.town("wreck_pickup", 34.5, 50.5, {"solid": .45})
	b.town("tire_pile", 30.5, 61.5, {"solid": .45})
	# The tow lot: wrecks in a row waiting on the crusher.
	for k in 6:
		var x := 112.5 + k * 5.0
		b.town("wreck_sedan" if k % 2 else "wreck_pickup", x, 93.5, {"solid": .45})
		b.fixture(x - 1.0, 93.1, x + 1.0, 93.9, .3, "mill_tin", "tin")
	for k in 4:
		b.town("crushed_stack" if k % 2 else "wrecked_derby", 108.5, 50.5 + k * 5.0, {"solid": .45})
	b.town("tire_pile", 116.5, 62.5, {"solid": .45})
	b.town("engine_stand", 112.5, 66.5, {"solid": .3})
	b.town("canned_ham", 145.5, 98.5, {"solid": .45})
	b.town("burn_barrel", 141.5, 96.5, {"solid": .3, "glow": true})
	b.glow(141.5, 96.5, 3.5, .3)
	b.town("camp_chairs", 143.0, 94.5)
	# The north-east corner behind turn 2: a team camped by their hauler.
	b.fixture(108.1, 36.6, 117.9, 38.4, 2.7, "trailer", "trailer")
	b.town("semi_tractor", 119.5, 37.5, {"solid": .45})
	b.board("speedway_ad_bait", 113.0, 38.44, .9, {"z": 1.3, "plane": 0.0})


func cast() -> void:
	for e in [
		# Truck stop and its lot.
		["coot", 30.0, 81.0, "truck-coot"],
		["pit_mechanic", 25.0, 88.5, "pump-mechanic"],
		["billy", 8.0, 81.0, "store-billy"],
		["clone", 40.0, 93.0, "rig-clone"],
		["coot", 8.0, 93.5, "tank-coot"],
		# The diner.
		["billy", 10.0, 61.0, "diner-billy"],
		["pit_mechanic", 14.0, 56.8, "diner-cook"],
		["coot", 18.0, 61.5, "diner-coot"],
		["nitro_huffer", 22.0, 66.0, "diner-huffer"],
		# The haulers' lot.
		["tire_roller", 12.0, 33.0, "hauler-roller"],
		["coot", 21.0, 12.0, "hauler-coot"],
		["billy", 8.0, 44.0, "hauler-billy"],
		["flagman", 22.0, 26.0, "hauler-flagman"],
		["skeeter", 14.0, 46.0, "hauler-skeeter"],
		# Pit row and the alley.
		["pit_mechanic", 43.0, 12.6, "bay-mechanic-a"],
		["tire_roller", 61.0, 12.6, "bay-roller"],
		["pit_mechanic", 79.0, 12.0, "bay-mechanic-b"],
		["nitro_huffer", 95.0, 12.0, "bay-huffer"],
		["billy", 103.0, 8.5, "bay-billy"],
		["flagman", 66.0, 18.5, "lane-flagman"],
		["coot", 92.0, 18.0, "lane-coot"],
		["tire_roller", 110.0, 18.0, "lane-roller"],
		["nitro_huffer", 50.0, 3.0, "alley-huffer"],
		["pit_mechanic", 71.0, 3.5, "depot-mechanic"],
		["billy", 78.0, 4.0, "depot-billy"],
		["coot", 100.0, 2.5, "alley-coot"],
		# The oval itself.
		["coot", 47.0, 26.0, "track-coot"],
		["skeeter", 104.0, 26.0, "track-skeeter"],
		["skeeter", 46.0, 58.0, "track-skeeter-b"],
		# The infield camp and the jump.
		["billy", 49.0, 49.0, "camp-billy"],
		["coot", 56.0, 46.0, "camp-coot"],
		["clone", 44.0, 42.0, "camp-clone"],
		["nitro_huffer", 59.0, 49.0, "camp-huffer"],
		["billy", 44.5, 52.0, "trailer-billy"],
		["coot", 60.5, 35.0, "jump-coot"],
		["alien", 64.0, 56.0, "camp-alien"],
		["saucer", 72.0, 32.0, "infield-saucer"],
		# The stands, the booth, the concourse.
		["coot", 55.0, 79.0, "stands-coot"],
		["flagman", 84.0, 77.0, "stands-flagman"],
		["billy", 95.0, 74.0, "stands-billy"],
		["coot", 66.0, 79.0, "stands-coot-b"],
		["pit_mechanic", 73.0, 78.0, "booth-mechanic"],
		["tire_roller", 64.0, 85.0, "concourse-roller"],
		["billy", 80.0, 87.0, "concourse-billy"],
		["nitro_huffer", 92.0, 83.0, "concourse-huffer"],
		["coot", 74.0, 90.5, "snack-coot"],
		# The tow lot.
		["clone", 120.0, 84.0, "tow-clone"],
		["billy", 112.0, 83.0, "shack-billy"],
		["coot", 132.0, 90.0, "tow-coot"],
		# Boggs Salvage and the crusher.
		["tire_roller", 135.0, 12.5, "salvage-roller"],
		["pit_mechanic", 128.0, 3.0, "salvage-mechanic"],
		["nitro_huffer", 145.0, 20.0, "salvage-huffer"],
		["flagman", 132.0, 36.0, "crusher-flagman"],
		["billy", 141.0, 26.0, "crusher-billy"],
		["tire_roller", 126.0, 30.0, "crane-roller"],
		["coot", 130.0, 54.0, "maze-coot"],
		["pit_mechanic", 143.0, 55.0, "maze-mechanic"],
		["skeeter", 137.0, 46.0, "maze-skeeter"],
		["alien", 141.6, 62.4, "office-alien"],
		# The figure 8: the champ and his pit crew wait for the flag.
		["derby_champ", 98.5, 37.5, "figure8-champ"],
		["pit_mechanic", 79.5, 37.5, "figure8-wrench"],
		["tire_roller", 79.5, 53.5, "figure8-tires"],
		["nitro_huffer", 98.5, 53.5, "figure8-huffer"],
	]:
		b.enemy(String(e[0]), float(e[1]), float(e[2]), String(e[3]))
	b.partners.append(["bay-mechanic-a", "bay-roller", 1])
	b.partners.append(["crusher-billy", "crane-roller", -1])


func pickups() -> void:
	for p in [
		# The start: the store and the fuel island.
		["shells", 11.0, 77.0],
		["rinds", 4.0, 81.0],
		["beer", 9.0, 82.5],
		["bullets", 26.5, 89.5],
		["shotgun", 12.0, 92.0],
		["rinds", 36.0, 86.0],
		# The diner and its walk-in.
		["whiskey", 6.0, 61.5],
		["shells", 16.0, 57.0],
		["rinds", 19.0, 56.5],
		["moonshine", 18.6, 51.6],
		["rocket_ammo", 19.5, 52.5],
		["cowpie", 20.4, 51.6],
		# The haulers.
		["rifle", 14.0, 24.5],
		["rifle_ammo", 22.0, 44.0],
		["beer", 6.0, 14.0],
		["shells", 24.0, 3.0],
		# Pit row.
		["dynamite", 43.0, 8.0],
		["crossbow", 61.0, 8.5],
		["shells", 85.0, 8.0],
		["rinds", 97.0, 8.0],
		["rifle_ammo", 107.0, 12.0],
		["bullets", 70.0, 18.5],
		["beer", 33.0, 18.0],
		["whiskey", 74.5, 4.5],
		["dynamite", 104.0, 3.0],
		# The oval and the infield.
		["shells", 74.0, 30.5],
		["rinds", 33.0, 45.5],
		["rifle_ammo", 116.0, 45.5],
		["bottle_launcher", 62.0, 35.5],
		["rocket_ammo", 58.0, 35.5],
		["beer", 51.5, 45.0],
		["shells", 44.5, 41.5],
		["moonshine", 44.0, 52.5],
		["rinds", 64.0, 44.0],
		# The stands, the booth, the concourse.
		["rifle_ammo", 72.0, 78.5],
		["rocket_ammo", 76.0, 79.2],
		["shells", 49.0, 78.0],
		["whiskey", 99.0, 79.0],
		["rinds", 70.0, 88.0],
		["beer", 78.0, 88.0],
		["arm_ammo", 55.0, 89.5],
		["keg_ammo", 55.5, 90.5],
		["milk_ammo", 54.5, 90.5],
		["shells", 98.0, 89.0],
		# The tow lot and the salvage yard.
		["rinds", 111.0, 82.5],
		["saw_ammo", 114.0, 84.0],
		["shells", 126.0, 2.5],
		["rifle_ammo", 146.0, 7.0],
		["rocket_ammo", 140.0, 36.0],
		["rinds", 129.0, 38.0],
		["whiskey", 145.5, 62.4],
		["dynamite", 142.4, 63.4],
		["shells", 124.0, 62.0],
		# Round the figure 8 for the fight.
		["shells", 86.5, 33.5],
		["rinds", 89.5, 54.0],
		["rocket_ammo", 70.5, 57.5],
	]:
		b.pickup(String(p[0]), float(p[1]), float(p[2]))


func set_pieces() -> void:
	(
		b
		. triggers
		. append(
			{
				"id": "race-on",
				"when": {"area": [41, 70, 105, 72]},
				"do":
				[
					{"message": "THE RACE IS STILL RUNNIN'. CROSS BETWEEN THE CARS.", "for": 3.5},
					{"sound": "distant_derby_engine", "at": [74.0, 65.0]},
				],
			}
		)
	)
	(
		b
		. triggers
		. append(
			{
				"id": "pit-row",
				"when": {"area": [27, 15, 120, 20]},
				"do":
				[
					{"message": "PIT ROW. EVERY CREW IN HERE'S GOT A WRENCH.", "for": 3.0},
					{"alert": 10}
				],
			}
		)
	)
	(
		b
		. triggers
		. append(
			{
				"id": "salvage",
				"when": {"area": [122, 16, 148, 22]},
				"do": [{"message": "BOGGS SALVAGE. MIND THE STACKS, THEY LEAN.", "for": 3.0}],
			}
		)
	)
	(
		b
		. triggers
		. append(
			{
				"id": "booth-up",
				"when": {"area": [71, 77, 77, 79]},
				"do":
				[
					{"message": "THE BOOTH. YOU CAN SEE THE WHOLE OVAL FROM UP HERE.", "for": 3.0},
					{"alert": 12},
				],
			}
		)
	)
	(
		b
		. triggers
		. append(
			{
				"id": "green-flag",
				"when": {"station": "flag"},
				"do":
				[
					{"shake": .7},
					{"sound": "distant_derby_engine", "at": [98.5, 37.5]},
					{
						"light":
						{
							"at": [89.5, 45.5],
							"z": 3.0,
							"color": [1.0, .9, .6],
							"radius": 14.0,
							"strength": 1.2,
							"for": 3.0
						}
					},
				],
			}
		)
	)
	b.exchanges.append(
		{
			"id": "pit-radio",
			"x": 64.0,
			"y": 10.5,
			"stop_at": "pits",
			"lines": ["RADIO: FUEL'S 110 PROOF, BOYS.", "CREW: THEN DON'T LIGHT A SMOKE."]
		}
	)
	b.exchanges.append(
		{
			"id": "booth-pa",
			"x": 74.5,
			"y": 78.0,
			"stop_at": "booth",
			"lines": ["PA: LAP FORTY-SEVEN, BOGGS LEADS.", "PA: AS USUAL. WHAT A SHOCK."]
		}
	)
	b.exchanges.append(
		{
			"id": "camp-fire",
			"x": 50.5,
			"y": 47.0,
			"stop_at": "",
			"lines": ["CAMPER: SEE THAT SAUCER OVER TURN TWO?", "OTHER: THAT'S A FLOODLIGHT, EARL."]
		}
	)
	b.distant_cues.append([74.0, 65.0, "distant_derby_engine"])
	b.distant_cues.append([98.5, 45.5, "distant_derby_engine"])
