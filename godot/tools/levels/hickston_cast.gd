## Who and what is in the Hickston Incident (layout 2): the enemies where
## they wait, the pickups, and the set pieces (triggers, radio chatter). The
## ground they stand on is hickston_plan.gd.
extends RefCounted

const Builder := preload("res://tools/levels/level_builder.gd")


static func enemies(b: Builder) -> void:
	# The road and the gas station: the first fights, a few at a time.
	b.enemy("coot", 24.5, 61.5, "gas-coot", [[19.5, 61.5], [29.5, 61.5]])
	b.enemy("chicken", 15.5, 66.0, "road-chicken")
	b.enemy("billy", 27.5, 52.5, "gas-billy")
	b.enemy("coot", 40.5, 61.0, "bait-coot")
	b.enemy("billy", 45.5, 53.0, "bait-billy")
	b.enemy("skeeter", 36.0, 67.5, "road-skeeter")
	# Main Street.
	b.enemy("billy", 58.5, 42.5, "main-billy", [[58.5, 42.5], [58.5, 54.5]])
	b.enemy("billy", 62.5, 50.5, "main-billy-b")
	b.enemy("coot", 63.5, 33.5, "main-coot")
	b.enemy("skeeter", 57.5, 58.5, "main-skeeter")
	b.enemy("yard_deputy", 60.5, 31.0, "lane-deputy")
	# Stanky's.
	b.enemy("coot", 44.5, 42.0, "bar-coot")
	b.enemy("billy", 50.5, 41.5, "bar-billy")
	b.enemy("coot", 47.6, 45.6, "bar-coot-b")
	b.enemy("billy", 40.6, 41.0, "bartender")
	b.enemy("billy", 47.5, 33.0, "cook")
	b.enemy("coot", 37.5, 45.6, "john-coot")
	b.enemy("clone", 33.5, 39.6, "supply-clone")
	# Called in by the office safe's bell.
	b.enemy("alien", 49.5, 26.5, "alarm-alien")
	b.enemy("alien", 42.5, 25.5, "alarm-alien-b")
	b.enemy("clone", 50.0, 34.6, "alarm-clone")
	b.enemy("clone", 20.0, 44.0, "alarm-clone-b")
	# The salvage yard and the creek.
	b.enemy("billy", 18.5, 35.0, "junk-billy")
	b.enemy("coot", 24.5, 43.0, "junk-coot")
	b.enemy("chicken", 15.6, 46.4, "junk-chicken")
	b.enemy("skeeter", 7.0, 18.0, "creek-skeeter")
	b.enemy("skeeter", 6.5, 49.0, "creek-skeeter-b")
	b.enemy("alien", 11.5, 37.5, "creek-alien")
	b.enemy("coot", 6.5, 57.5, "creek-coot")
	b.enemy("pig", 16.5, 9.5, "orchard-pig")
	b.enemy("alien", 20.5, 4.5, "orchard-alien")
	b.enemy("chicken", 22.0, 17.0, "orchard-chicken")
	# The lane.
	b.enemy("clone", 30.5, 26.0, "lane-clone", [[30.5, 26.0], [44.5, 26.0]])
	b.enemy("alien", 70.5, 25.5, "lane-alien")
	b.enemy("clone", 84.5, 27.5, "lane-clone-b")
	# Feed & Seed.
	b.enemy("clone", 72.5, 35.0, "feed-clone")
	b.enemy("clone", 78.0, 39.5, "feed-clone-b")
	b.enemy("coot", 85.5, 40.0, "feed-coot")
	# The chapel: the congregation waits for the doors.
	b.enemy("clone", 74.0, 50.6, "pew-clone")
	b.enemy("clone", 80.0, 52.6, "pew-clone-b")
	b.enemy("clone", 74.5, 54.4, "pew-clone-c")
	b.enemy("alien", 77.0, 47.8, "preacher")
	b.enemy("coot", 85.5, 61.0, "grave-coot")
	b.enemy("skeeter", 70.0, 57.0, "grave-skeeter")
	# The trailer court.
	b.enemy("billy", 100.5, 54.5, "court-billy")
	b.enemy("billy", 110.5, 60.5, "court-billy-b")
	b.enemy("coot", 121.5, 54.5, "court-coot")
	b.enemy("chicken", 97.0, 61.0, "court-chicken")
	b.enemy("yard_deputy", 118.5, 61.0, "court-deputy")
	b.enemy("billy", 106.0, 50.5, "trailer-billy")
	b.enemy("coot", 95.0, 57.5, "trailer-coot")
	# The barn.
	b.enemy("clone", 50.5, 13.5, "barn-clone")
	b.enemy("clone", 58.5, 16.5, "barn-clone-b")
	b.enemy("clone", 46.5, 13.0, "barn-clone-c")
	b.enemy("alien", 44.5, 4.5, "loft-alien")
	b.enemy("chicken", 54.0, 8.0, "barn-chicken")
	b.enemy("chicken", 62.0, 5.0, "barn-chicken-b")
	b.enemy("billy", 44.0, 18.5, "tack-billy")
	# The hog pen and the packing shed.
	b.enemy("pig", 29.5, 14.0, "pen-pig")
	b.enemy("pig", 34.5, 15.5, "pen-pig-b")
	b.enemy("pig", 32.0, 19.5, "pen-pig-c")
	b.enemy("pig", 36.5, 11.5, "pen-pig-d")
	b.enemy("billy", 37.0, 19.5, "pen-billy")
	b.enemy("clone", 28.5, 5.2, "packing-clone")
	b.enemy("clone", 33.5, 7.4, "packing-clone-b")
	# The lots.
	b.enemy("pig", 71.0, 9.5, "lot-pig")
	b.enemy("pig", 85.0, 17.5, "lot-pig-b")
	b.enemy("chicken", 77.5, 4.0, "lot-chicken")
	b.enemy("chicken", 90.0, 12.0, "lot-chicken-b")
	b.enemy("alien", 83.0, 4.0, "lot-alien")
	b.enemy("alien", 91.0, 19.0, "lot-alien-b")
	b.enemy("yard_deputy", 75.5, 18.5, "lot-deputy")
	b.enemy("saucer", 86.0, 9.0, "lot-saucer")
	# The registry and its yard.
	b.enemy("alien", 96.0, 31.0, "yard-alien")
	b.enemy("alien", 123.0, 30.0, "yard-alien-b")
	b.enemy("saucer", 115.0, 25.0, "yard-saucer")
	b.enemy("clone", 95.0, 44.6, "yard-clone")
	b.enemy("yard_deputy", 102.5, 30.0, "clerk-deputy")
	b.enemy("yard_deputy", 114.0, 36.5, "vault-deputy")
	b.enemy("clone", 102.0, 38.5, "records-clone")
	# The north pasture: the sheriff in the rodeo ring before Bessie's pen,
	# seen across it from the chute gate; Jerry at midfield on the Hogs'
	# field, waiting behind the stock gate; Bessie, and their escort.
	b.enemy("boss", 132.5, 14.0, "sheriff")
	b.enemy("jerry", 108.5, 9.5, "jerry")
	b.enemy("bessie", 143.0, 5.4, "bessie")
	b.enemy("saucer", 104.0, 6.0, "pasture-saucer")
	b.enemy("saucer", 127.5, 5.5, "pasture-saucer-b")
	b.enemy("alien", 100.5, 15.5, "pasture-alien")
	b.enemy("alien", 145.5, 19.5, "pasture-alien-b")
	b.enemy("alien", 117.5, 14.5, "pasture-alien-c")
	b.enemy("alien", 141.5, 13.5, "pen-guard")
	# The corn: things in the rows, and more waiting in the circle.
	b.enemy("skeeter", 137.0, 44.0, "corn-skeeter")
	b.enemy("clone", 133.0, 40.0, "corn-clone")
	b.enemy("skeeter", 140.0, 25.0, "corn-skeeter-b")
	b.enemy("alien", 135.0, 25.0, "corn-alien")
	b.enemy("alien", 141.0, 31.5, "circle-alien")
	b.enemy("alien", 135.5, 34.5, "circle-alien-b")
	b.enemy("clone", 145.5, 29.6, "circle-clone")
	b.enemy("skeeter", 130.5, 31.6, "circle-skeeter")


static func pickups(b: Builder) -> void:
	for p in [
		# The road in.
		["bullets", 11.0, 64.8],
		["rinds", 9.6, 70.8],
		["beer", 31.0, 64.6],
		# The gas station.
		["beer", 17.0, 52.0],
		["rinds", 22.0, 50.6],
		["bullets", 23.0, 54.4],
		["crossbow", 28.5, 53.5],
		["dynamite", 27.0, 50.8],
		["dynamite", 28.8, 51.8],
		["whiskey", 34.6, 57.0],
		# Bait & Ammo.
		["shotgun", 48.0, 51.2],
		["shells", 42.0, 52.6],
		["shells", 47.6, 55.6],
		["bullets", 41.6, 56.2],
		# Main Street.
		["shells", 61.4, 44.0],
		["whiskey", 55.4, 58.6],
		["rinds", 64.6, 30.6],
		# Stanky's.
		["beer", 40.6, 38.6],
		["beer", 45.0, 46.4],
		["bullets", 50.6, 45.6],
		["rinds", 42.5, 32.8],
		["whiskey", 51.4, 34.8],
		["key_brass", 30.6, 32.6],
		["shells", 33.0, 40.8],
		["moonshine", 37.6, 38.6],
		["dynamite", 38.4, 40.6],
		["shells", 37.6, 41.4],
		["cowpie", 37.2, 46.4],
		# The salvage yard and the creek.
		["slingblade", 26.6, 33.0],
		["bullets", 15.6, 40.2],
		["rinds", 23.0, 37.0],
		["shells", 7.0, 31.0],
		["beer", 6.8, 10.0],
		["rifle_ammo", 11.0, 52.0],
		["cowpie", 17.0, 14.0],
		# The lane.
		["rinds", 27.0, 28.6],
		["bullets", 63.0, 23.6],
		# Feed & Seed.
		["rifle", 78.6, 33.4],
		["rifle_ammo", 76.8, 35.0],
		["rifle_ammo", 78.6, 40.6],
		["rinds", 72.0, 41.0],
		["shells", 86.6, 42.6],
		# The chapel.
		["whiskey", 75.0, 46.6],
		["moonshine", 79.0, 46.6],
		["dynamite", 81.6, 46.6],
		["rifle_ammo", 82.4, 47.4],
		["beer", 87.0, 61.0],
		# The trailer court.
		["ripsaw", 95.5, 57.6],
		["saw_ammo", 96.4, 58.5],
		["shells", 106.6, 50.6],
		["beer", 116.6, 50.4],
		["rinds", 106.5, 58.5],
		["armgun", 120.5, 57.6],
		["arm_ammo", 120.5, 58.4],
		["whiskey", 124.6, 61.4],
		["bullets", 91.0, 49.0],
		# The hog pen and the packing shed.
		["cowpie", 30.0, 16.0],
		["cowpie", 36.6, 14.0],
		["rifle_ammo", 29.0, 20.0],
		["shells", 30.0, 7.4],
		["moonshine", 35.6, 2.4],
		["bowling_ammo", 36.8, 2.6],
		["dynamite", 33.6, 5.4],
		# The barn.
		["teat_gun", 42.6, 19.4],
		["milk_ammo", 46.6, 19.6],
		["shells", 42.6, 4.6],
		["rinds", 47.4, 7.6],
		["rifle_ammo", 62.6, 9.0],
		["beer", 58.6, 21.0],
		["saw_ammo", 50.0, 17.6],
		# The lots.
		["milk_ammo", 72.0, 13.6],
		["shells", 85.6, 5.0],
		["whiskey", 91.6, 2.6],
		["rifle_ammo", 77.0, 20.4],
		["dynamite", 87.4, 18.6],
		# The registry.
		["shells", 97.0, 24.0],
		["rinds", 125.0, 24.0],
		["arm_ammo", 101.0, 33.0],
		["rifle_ammo", 105.0, 40.4],
		["moonshine", 116.6, 35.6],
		["key_steel", 115.3, 38.5],
		["beer", 123.6, 45.6],
		# The corn.
		["shells", 129.4, 40.4],
		["rinds", 146.0, 44.6],
		["moonshine", 147.6, 33.0],
		["arm_ammo", 129.0, 29.6],
		["dynamite", 145.6, 24.6],
		# The pasture.
		["arm_ammo", 100.4, 21.4],
		["arm_ammo", 131.6, 20.6],
		["rinds", 99.6, 2.4],
		["moonshine", 147.0, 14.6],
		["dynamite", 118.6, 20.0],
		["beer", 141.0, 16.2],
	]:
		b.pickup(String(p[0]), float(p[1]), float(p[2]))


static func set_pieces(b: Builder) -> void:
	(
		b
		. triggers
		. append(
			{
				"id": "dispatch-alarm",
				"when": {"key": "key_brass"},
				"do":
				[
					{
						"message": "THE DISPATCH SAFE HAD A BELL ON IT. COMPANY IS COMING.",
						"for": 3.5
					},
					{"sound": "fair_bell", "at": [31.0, 32.0]},
					{
						"light":
						{
							"at": [31.0, 32.0],
							"color": [1, .25, .15],
							"radius": 6,
							"strength": 1.6,
							"for": 5
						}
					},
					{"wake": ["alarm-alien", "alarm-alien-b", "alarm-clone", "alarm-clone-b"]},
					{"alert": 16},
					{"shake": .3},
				],
			}
		)
	)
	(
		b
		. triggers
		. append(
			{
				"id": "chapel-rises",
				"when": {"area": [72, 49, 82, 56]},
				"do":
				[
					{"message": "THE CONGREGATION RISES. THEY'VE BEEN PROBED.", "for": 3.0},
					{"sound": "fair_bell", "at": [77.0, 58.0]},
					{"wake": ["pew-clone", "pew-clone-b", "pew-clone-c", "preacher"]},
					{
						"light":
						{
							"at": [77.0, 47.0],
							"color": [.4, 1, .5],
							"radius": 7,
							"strength": 1.4,
							"for": 3
						}
					},
				],
			}
		)
	)
	(
		b
		. triggers
		. append(
			{
				"id": "registry-key",
				"when": {"key": "key_steel"},
				"do":
				[
					{
						"message":
						"SOMETHING JUST SET DOWN IN THE NORTH PASTURE. BESSIE'S OUT THERE.",
						"for": 4.0
					},
					{"sound": "thunder"},
					{"shake": .5},
					{"alert": 14},
				],
			}
		)
	)
	(
		b
		. triggers
		. append(
			{
				"id": "crop-circle",
				"when": {"area": [128, 29, 148, 36]},
				"do":
				[
					{"message": "A CROP CIRCLE. STILL WARM.", "for": 3.0},
					{"sound": "distant_corn_rustle", "at": [138.5, 32.5]},
					{"wake": ["circle-alien", "circle-alien-b", "circle-clone", "circle-skeeter"]},
					{
						"light":
						{
							"at": [138.5, 32.5],
							"color": [.4, 1, .55],
							"radius": 6,
							"strength": 1.5,
							"for": 2.5
						}
					},
					{"shake": .25},
				],
			}
		)
	)
	(
		b
		. triggers
		. append(
			{
				"id": "pasture-gate",
				"when": {"area": [127, 18, 133, 21]},
				"do": [{"message": "HANG ON, BESSIE. DADDY'S HERE.", "for": 3.0}],
			}
		)
	)
	# The sheriff falls: the stock gate onto the Hogs' field swings open, the
	# lights over it flare and the crowd that is not there roars.
	(
		b
		. triggers
		. append(
			{
				"id": "field-gate",
				"when": {"down": ["sheriff"]},
				"do":
				[
					{"open": [122, 10]},
					{"sound": "crowd_cheer", "at": [108.5, 9.5]},
					{
						"light":
						{
							"at": [108.5, 9.5],
							"color": [1, .92, .7],
							"radius": 9,
							"strength": 1.4,
							"for": 3
						}
					},
				],
			}
		)
	)
	b.exchanges.append(
		{
			"id": "tow-radio",
			"x": 26.0,
			"y": 44.0,
			"stop_at": "",
			"lines": ["RADIO: WHO TOOK THE TRUCK?", "VOICE: ASK THE PIG."]
		}
	)
	b.exchanges.append(
		{
			"id": "registry-radio",
			"x": 110.0,
			"y": 32.6,
			"stop_at": "",
			"lines": ["RADIO: KEEP THE KEY DRY.", "VOICE: THEN FIX THE ROOF."]
		}
	)
