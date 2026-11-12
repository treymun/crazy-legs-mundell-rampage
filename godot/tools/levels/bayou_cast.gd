## Gator Bayou's people and things (bayou_plan.gd lays out the water and the
## buildings): who stands where, what lies about, the stations that bring the
## bridges down and the king in, the notes, the talk, the set pieces.
extends RefCounted


static func _district(b, name: String) -> int:
	return b.districts.find(name)


static func enemies(b) -> void:
	for e in [
		# The landing: the bait run's welcome, one squatting in the water by the ramp.
		["coot", 70.5, 82.5, "landing-coot"],
		["billy", 75.5, 88.5, "landing-billy"],
		["noodler", 55.5, 73.5, "ramp-noodler"],
		# The bait and tackle, its porch, the gators that hang about for the scraps.
		["coot", 30.5, 72.5, "bait-clerk"],
		["chum_tosser", 35.5, 71.5, "bait-chummer"],
		["gator", 39.5, 77.5, "bait-gator"],
		["gator", 18.5, 79.5, "bait-gator-b"],
		# The crawfish boil.
		["billy", 19.5, 55.5, "boil-billy"],
		["coot", 8.5, 59.5, "boil-coot"],
		["chum_tosser", 22.5, 60.5, "boil-chummer"],
		["noodler", 26.5, 47.5, "inlet-noodler"],
		["clone", 9.5, 52.5, "boil-clone"],
		["gator", 24.5, 45.5, "inlet-gator"],
		["billy", 16.5, 63.5, "boil-billy-b"],
		# Stilt row.
		["clone", 63.5, 62.5, "spine-clone"],
		["coot", 52.5, 65.5, "boatshop-coot"],
		["billy", 70.5, 53.5, "mawmaw-billy"],
		["chum_tosser", 59.5, 56.0, "skinning-chummer"],
		["noodler", 57.5, 63.5, "row-noodler"],
		["skeeter", 66.5, 69.5, "row-skeeter"],
		["skeeter", 76.5, 66.5, "row-skeeter-b"],
		["coot", 71.5, 65.5, "preacher"],
		["billy", 48.5, 53.5, "loft-billy"],
		# The cabins.
		["coot", 99.5, 75.5, "cabin-coot"],
		["billy", 107.5, 74.5, "cabin-billy"],
		["gator", 112.5, 84.5, "cabin-gator"],
		["skeeter", 92.5, 84.5, "cabin-skeeter"],
		["chum_tosser", 104.5, 79.0, "cabin-chummer"],
		# The cannery.
		["clone", 97.5, 53.5, "cannery-clone"],
		["billy", 104.5, 58.5, "cannery-billy"],
		["coot", 90.0, 62.5, "cannery-coot"],
		["noodler", 112.5, 56.5, "cannery-noodler"],
		["yard_deputy", 116.5, 62.5, "ice-deputy"],
		["billy", 106.5, 44.5, "dock-cannery-billy"],
		["gator", 95.5, 63.5, "cannery-gator"],
		# The hammock.
		["coot", 60.5, 35.5, "tender"],
		["gator", 52.5, 42.5, "hammock-gator"],
		["gator", 72.5, 31.5, "hammock-gator-b"],
		["billy", 68.5, 38.5, "hammock-billy"],
		# The gator farm and its pit.
		["gator", 6.5, 16.5, "pen-gator-a"],
		["gator", 7.5, 27.5, "pen-gator-b"],
		["gator", 18.5, 20.5, "pen-gator-c"],
		["noodler", 27.5, 10.5, "pit-wrassler"],
		["gator", 29.5, 12.5, "pit-gator"],
		["chum_tosser", 13.5, 10.5, "farm-chummer"],
		["billy", 6.5, 5.5, "farm-office-billy"],
		["coot", 32.5, 23.5, "hide-coot"],
		["clone", 24.5, 20.5, "farm-clone"],
		["chicken", 9.5, 32.5, "hen-a"],
		["chicken", 11.5, 33.5, "hen-b"],
		["chicken", 12.5, 31.5, "hen-c"],
		# The Mudhole.
		["billy", 57.5, 10.5, "juke-billy"],
		["clone", 63.5, 14.5, "juke-clone"],
		["coot", 52.5, 18.5, "juke-band"],
		["yard_deputy", 59.5, 20.0, "bouncer"],
		["alien", 66.5, 13.5, "juke-alien"],
		["noodler", 64.5, 11.0, "juke-noodler"],
		["billy", 47.5, 9.5, "deck-billy"],
		["chum_tosser", 71.5, 22.5, "deck-chummer"],
		# The lagoon and the dock.
		["coot", 89.5, 13.5, "platform-coot"],
		["gator", 80.5, 18.5, "lagoon-gator"],
		["skeeter", 84.5, 22.5, "lagoon-skeeter"],
		["billy", 114.5, 28.5, "dock-billy-b"],
		["clone", 118.5, 13.5, "dock-clone"],
		["coot", 113.5, 17.5, "boathouse-coot"],
		# The king and his last hands: asleep until the fuel is spiked.
		["swamp_king", 95.5, 21.5, "king"],
		["gator", 99.5, 23.5, "lagoon-gator-a"],
		["gator", 86.5, 15.5, "lagoon-gator-b"],
		["chum_tosser", 109.5, 24.5, "dock-chummer"],
		["billy", 110.5, 14.5, "dock-billy"],
		# The still.
		["coot", 112.5, 6.5, "still-coot"],
		["noodler", 108.5, 5.5, "still-noodler"],
		# The backwater: the houseboat, the duck blind, the gator nest.
		["chum_tosser", 78.5, 8.5, "houseboat-chummer"],
		["coot", 6.5, 75.5, "blind-hunter"],
		["gator", 10.5, 86.0, "nest-gator"],
	]:
		b.enemy(String(e[0]), float(e[1]), float(e[2]), String(e[3]))
	b.enemy(
		"yard_deputy",
		80.5,
		58.5,
		"row-deputy",
		[[80.5, 57.5], [66.5, 57.5], [66.5, 58.5], [80.5, 58.5]]
	)
	b.enemy("coot", 63.5, 74.5, "spine-coot", [[63.5, 74.5], [63.5, 66.5]])
	b.partners.append(["juke-billy", "juke-clone", 1])
	b.partners.append(["boil-billy", "boil-clone", -1])


static func pickups(b) -> void:
	for p in [
		["rinds", 61.5, 82.5],
		["shells", 76.5, 80.5],
		["beer", 52.5, 82.5],
		["shotgun", 31.0, 75.0],
		["shells", 30.5, 70.5],
		["bullets", 24.5, 70.5],
		["rinds", 35.5, 76.0],
		["whiskey", 19.0, 70.6],
		["shells", 20.4, 72.4],
		["dynamite", 19.4, 73.4],
		["moonshine", 20.0, 71.2],
		["rinds", 12.5, 59.5],
		["beer", 20.5, 56.5],
		["shells", 7.5, 55.0],
		["bullets", 27.5, 56.5],
		["rifle_ammo", 5.5, 49.5],
		["whiskey", 24.5, 65.5],
		["shells", 63.5, 70.5],
		["rinds", 49.5, 53.5],
		["bullets", 59.0, 51.5],
		["rifle", 72.5, 66.5],
		["rifle_ammo", 70.5, 64.0],
		["beer", 75.5, 52.5],
		["whiskey", 52.5, 63.5],
		["shells", 80.5, 61.0],
		["cowpie", 80.5, 63.0],
		["dynamite", 59.5, 71.5],
		["shells", 90.5, 75.5],
		["rinds", 100.5, 75.5],
		["bullets", 108.5, 75.5],
		["beer", 103.0, 84.0],
		["milk_ammo", 110.0, 79.5],
		["shells", 96.5, 49.0],
		["rifle_ammo", 104.5, 51.0],
		["rinds", 90.0, 51.5],
		["pressure_ammo", 118.5, 48.8],
		["whiskey", 114.0, 61.0],
		["shells", 119.5, 63.0],
		["dynamite", 110.5, 61.5],
		["beer", 108.0, 45.5],
		["crossbow", 62.0, 36.5],
		["dynamite", 60.0, 36.6],
		["rinds", 66.5, 39.5],
		["shells", 58.5, 34.6],
		["moonshine", 58.5, 36.4],
		["keg_ammo", 58.4, 35.5],
		["shells", 8.5, 6.5],
		["bullets", 13.5, 14.5],
		["rinds", 24.0, 18.0],
		["rifle_ammo", 34.5, 24.5],
		["beer", 20.0, 29.0],
		["dynamite", 27.5, 9.5],
		["whiskey", 17.0, 3.5],
		["beer", 55.0, 9.6],
		["whiskey", 62.0, 9.6],
		["rinds", 51.5, 17.0],
		["shells", 68.0, 14.0],
		["rocket_ammo", 67.5, 9.5],
		["moonshine", 69.0, 10.0],
		["shells", 69.0, 7.6],
		["shells", 91.5, 13.0],
		["rifle_ammo", 106.5, 24.5],
		["pressure_ammo", 120.0, 30.5],
		["shells", 113.5, 19.0],
		["rinds", 106.5, 34.0],
		["beer", 124.5, 34.5],
		["cow_ammo", 122.5, 22.5],
		["moonshine", 118.5, 6.5],
		["moonshine", 114.0, 7.0],
		["whiskey", 121.5, 7.5],
		["dynamite", 123.5, 5.5],
		["cowpie", 111.5, 8.0],
		["whiskey", 80.0, 8.8],
		["shells", 78.0, 9.2],
		["shells", 5.5, 76.5],
		["rinds", 9.5, 85.5],
		["shells", 64.0, 76.5],
		["bullets", 64.5, 81.0],
		["bullets", 63.5, 68.0],
		["bullets", 75.5, 58.0],
		["shells", 52.0, 57.5],
		["rifle_ammo", 86.5, 57.5],
		["bullets", 95.0, 72.0],
		["shells", 63.5, 45.0],
	]:
		b.pickup(String(p[0]), float(p[1]), float(p[2]))
	# Drums that go up when shot: fuel on the dock and the landing, propane at the boil.
	for p in [[110.5, 32.5], [123.5, 26.5], [27.5, 52.8], [99.0, 46.0], [77.0, 84.0]]:
		b.fuel_drums.append(p)


static func set_pieces(b) -> void:
	var boil := _district(b, "CRAWFISH BOIL")
	var cannery := _district(b, "SWAMP KING CANNERY")
	var dock := _district(b, "AIRBOAT DOCK")
	var lagoon := _district(b, "KING'S LAGOON")
	# The boil yard generator: crank it and the west drawbridge comes down.
	b.station(
		"generator",
		6.5,
		48.6,
		"CRANK THE BOIL YARD GENERATOR",
		"GENERATOR'S UP. THE WEST DRAWBRIDGE COMES DOWN.",
		{"opens": [[15, 39]], "sectors": [boil], "cue": "mill_isolate", "action": "crank"}
	)
	# (The generator itself stands under its lean-to: bayou_plan.gd boil_yard.)
	# The cannery's ice plant breaker: trip it and the hoist bridge drops.
	b.station(
		"breaker",
		116.5,
		60.7,
		"TRIP THE ICE PLANT BREAKER",
		"ICE PLANT'S DEAD. THE HOIST BRIDGE DROPS ON THE CHANNEL.",
		{"opens": [[104, 39]], "sectors": [cannery], "cue": "mill_trip"}
	)
	b.quest("quest_switch_bayou", 116.5, 59.5, "breaker")
	# The fuel: sugar in the king's pump and his fleet is done. He comes.
	b.station(
		"fuel",
		108.5,
		19.0,
		"SPIKE THE AIRBOAT FUEL",
		"SUGAR IN THE TANK. HERE COMES THE KING!",
		{"requires": ["generator", "breaker"], "sectors": [dock, lagoon], "cue": "pressure_vent"}
	)
	# The king's own still, hid behind the reeds: a taste is a secret found.
	b.station(
		"still-tap",
		116.5,
		6.6,
		"TAP THE KING'S STILL",
		"THE KING'S PRIVATE RESERVE. SMOOTH AS A GATOR'S BELLY.",
		{"hidden": true, "reveals_secret": true, "cue": "moonshine"}
	)
	# Notes on counters and desks, readable from the floor in front of them.
	b.notes.append(
		[
			29.4,
			75.4,
			"BAIT LOG",
			"SOLD THE KING FORTY POUND OF CHUM. SAYS IT'S FOR THE GATORS. SAYS A LOT OF THINGS.",
			0.0
		]
	)
	# At the counter's south end, by the gap behind it: from back of the counter
	# it is a short step round, not a walk (quest_reach.gd).
	b.board("county_note", 28.8, 75.4, .3, {"z": .95, "plane": -PI / 2})
	b.fixture(113.2, 59.2, 114.6, 60.0, .8, "wood", "counter_top")
	b.notes.append(
		[
			113.9,
			60.4,
			"SHIPPING TICKET",
			"CRAWFISH, 200 CRATES. CRAWFISH THAT SLOSH, 60 CRATES. DO NOT TIP THE SLOSHING ONES.",
			0.0
		]
	)
	b.board("county_note", 113.9, 59.6, .3, {"z": .8, "plane": 0.0})
	b.notes.append(
		[59.0, 9.3, "SET LIST", "1. THE GATOR SONG. 2. THE GATOR SONG (SLOW). NO REQUESTS.", 0.0]
	)
	b.board("county_note", 59.0, 8.6, .3, {"z": 1.0, "plane": 0.0})
	b.notes.append(
		[
			5.6,
			6.8,
			"FARM LEDGER",
			"GATORS: 31. GATORS COUNTED TWICE: 31. TOURISTS: 9. TOURISTS COUNTED TWICE: 8.",
			0.0
		]
	)
	b.board("county_note", 5.6, 7.6, .3, {"z": .82, "plane": 0.0})
	b.notes.append(
		[
			122.9,
			18.4,
			"TOUR LOG",
			"TOURS AT DUSK. GUESTS RETURNED: MOST. BLUE TRUNK WENT UP THE BACKWATER.",
			0.0
		]
	)
	b.board("county_note", 122.9, 17.9, .3, {"z": 1.0, "plane": 0.0})
	b.exchanges.append(
		{
			"id": "boil-cooks",
			"x": 17.0,
			"y": 56.0,
			"stop_at": "",
			"lines": ["COOK: WHO DROPPED A BOOT IN THE BOIL?", "HAND: THAT'S SEASONIN'."]
		}
	)
	b.exchanges.append(
		{
			"id": "juke-band",
			"x": 55.0,
			"y": 17.0,
			"stop_at": "",
			"lines": ["BAND: WE KNOW TWO SONGS.", "BOUNCER: THEN PLAY THE OTHER ONE."]
		}
	)
	b.exchanges.append(
		{
			"id": "dock-radio",
			"x": 114.0,
			"y": 20.0,
			"stop_at": "fuel",
			"lines": ["RADIO: KING TO DOCK. FUEL HER UP.", "DOCK: TANK'S FULL, YOUR MAJESTY."]
		}
	)
	for t in [
		{
			"id": "deep-water",
			"when": {"area": [44, 47, 84, 49]},
			"do":
			[
				{
					"message": "THE BLACK WATER'S TOO DEEP TO WADE. STICK TO THE BOARDWALKS.",
					"for": 3.5
				}
			],
		},
		{
			"id": "drawbridge-up",
			"when": {"area": [8, 43, 22, 46]},
			"do": [{"message": "DRAWBRIDGE IS UP. THE GENERATOR WORKS IT.", "for": 3.0}],
		},
		{
			"id": "farm-gate",
			"when": {"area": [8, 26, 24, 36]},
			"do": [{"message": "GATOR FARM. THE PENS ARE BUSTED.", "for": 3.0}, {"alert": 10}],
		},
		{
			"id": "juke-door",
			"when": {"area": [49, 7, 69, 21]},
			"do":
			[
				{"message": "THE BAND STOPS. EVERYBODY TURNS AROUND.", "for": 3.0},
				{"sound": "record_scratch"},
				{"alert": 12}
			],
		},
		{
			"id": "cannery-slosh",
			"when": {"area": [89, 48, 120, 66]},
			"do": [{"message": "THE CRAWFISH CRATES SLOSH. THAT AIN'T CRAWFISH.", "for": 3.0}],
		},
		{
			"id": "lagoon-idle",
			"when": {"area": [97, 12, 111, 36]},
			"do":
			[
				{"message": "AN ENGINE IDLES OUT ON THE LAGOON. SOMEBODY'S WAITING.", "for": 3.0},
				{"sound": "distant_bayou_airboat", "at": [96.0, 18.0]}
			],
		},
	]:
		b.triggers.append(t)
