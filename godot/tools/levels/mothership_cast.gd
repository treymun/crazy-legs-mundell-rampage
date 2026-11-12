## Who and what is aboard the Mothership (layout 1): the stations, the crew
## where they wait, the pickups, the things in each room, and the set pieces
## (triggers, the PA, notes). The decks they stand on are mothership_plan.gd.
## Every piece is placed by hand, against a wall or with the things it belongs
## with; nothing is strewn to fill the floor.
extends RefCounted

const Builder := preload("res://tools/levels/level_builder.gd")


## A railing along a drop: a hip-high run of steel on the high side's cells,
## standing on their floor, so a path can only go by the ramp. `floor_z` is the
## floor it stands on when it is not that of the box's middle cell.
static func rail(b: Builder, x0: float, y0: float, x1: float, y1: float, floor_z := NAN) -> void:
	var z: float = (
		floor_z if not is_nan(floor_z) else b.ground[b.at(int((x0 + x1) * .5), int((y0 + y1) * .5))]
	)
	b.fixture(x0, y0, x1, y1, z + 1.0, "ship_edge", "ship_edge", z)


# ------------------------------------------------------------------ stations


## The jobs: spike the drive with shine (east), drain the cow tubes (west),
## then open the core's iris from the bridge (north). Each at a quest
## console the player walks up to, its lamp dark and its glow green once done.
static func stations(p) -> void:
	var b: Builder = p.b
	# The drive, down in the engine pit: the console west of the engine.
	p.stand("quest_ship_drive", 93.5, 50.5, .42, {"quest": "drive"})
	b.station(
		"drive",
		94.7,
		50.5,
		"SPIKE THE DRIVE WITH SHINE",
		"DRIVE SPIKED. 180 PROOF. THE BULKHEADS ARE LOOSE.",
		{"opens": [[73, 23]], "sectors": [p.engine, p.corn], "cue": "mill_trip"}
	)
	# The tubes, at the specimen hold's north wall.
	p.stand("quest_ship_drain", 10.5, 62.5, .42, {"quest": "tubes"})
	b.station(
		"tubes",
		10.5,
		63.7,
		"DRAIN THE COW TUBES",
		"TUBES DRAINED. THE COWS ARE MAD AND THE BRIDGE IS OPEN.",
		{"opens": [[55, 23]], "sectors": [p.specimen], "cue": "pressure_vent"}
	)
	# The iris, at the captain's console on the bridge dais.
	p.stand("quest_ship_iris", 64.5, 18.5, .42, {"quest": "iris"})
	b.station(
		"iris",
		64.5,
		19.7,
		"OPEN THE CORE IRIS",
		"THE IRIS IS OPEN. SOMETHING BIG IN THE CORE JUST WOKE UP.",
		{
			"requires": ["drive", "tubes"],
			"opens": [[64, 37]],
			"sectors": [p.core],
			"cue": "mill_isolate"
		}
	)
	# A lawn elf whose hat is a lever: the trophy room's vault.
	b.station(
		"elf-hat",
		40.5,
		16.4,
		"TUG THE LAWN ELF'S HAT",
		"THE ELF'S HAT IS A LEVER. OF COURSE IT IS.",
		{"opens": [[40, 12]], "hidden": true, "reveals_secret": true, "cue": "secret_slide"}
	)
	# The way home: the escape outhouse on its pad and its launch post, the
	# button under its cover lit green once the core is quiet.
	p.stand("escape_outhouse", 70.5, 94.5, .45)
	p.stand("quest_ship_launch", 73.5, 93.5, .3, {"quest": "exit"})
	p.on_wall("ship_sign_escape", 67.0, 97.0, "s", .7, 2.2)


# ------------------------------------------------------------------ the crew


static func enemies(b: Builder) -> void:
	# The bay, where the beam set the player down.
	for e in [
		["drone", 66.5, 86.5, "bay-drone-a"],
		["drone", 57.5, 80.5, "bay-drone-b"],
		["alien", 74.5, 77.5, "bay-alien"],
		["saucer", 64.0, 78.0, "bay-saucer"],
		["drone", 81.5, 86.5, "gantry-drone"],
		["alien", 79.5, 94.5, "booth-alien"],
		["probe", 51.5, 92.5, "bay-probe"],
		["chicken", 74.5, 86.5, "bay-hen-a"],
		["chicken", 71.5, 88.5, "bay-hen-b"],
		["chicken", 76.5, 82.5, "bay-rooster"],
	]:
		b.enemy(String(e[0]), float(e[1]), float(e[2]), String(e[3]))
	# The ring deck: a few walking it, a guard at each side.
	b.enemy("drone", 64.5, 64.0, "ring-drone-s", [[57.5, 62.5], [64.5, 64.0], [71.5, 62.5]])
	b.enemy("probe", 77.0, 50.5, "ring-probe-e", [[77.0, 44.5], [77.0, 56.5]])
	b.enemy("drone", 64.5, 35.5, "ring-drone-n", [[57.5, 37.5], [64.5, 35.5], [71.5, 37.5]])
	b.enemy("alien", 50.5, 52.5, "ring-alien-w")
	b.enemy("tin_guard", 54.5, 60.5, "ring-guard-sw")
	b.enemy("saucer", 73.0, 40.0, "ring-saucer-ne")
	b.enemy("drone", 75.5, 58.5, "ring-drone-se")
	b.enemy("probe", 51.0, 44.0, "ring-probe-nw")
	# The probe lab.
	for e in [
		["alien", 36.5, 75.5, "lab-alien-a"],
		["alien", 42.5, 69.5, "lab-alien-b"],
		["drone", 28.5, 81.5, "lab-drone-a"],
		["drone", 41.5, 84.5, "lab-drone-b"],
		["probe", 35.0, 79.0, "lab-probe"],
		["clone", 33.5, 67.5, "lab-patient"],
	]:
		b.enemy(String(e[0]), float(e[1]), float(e[2]), String(e[3]))
	# The specimen hold.
	for e in [
		["probe", 14.0, 72.0, "hold-probe-a"],
		["probe", 14.0, 84.0, "hold-probe-b"],
		["drone", 9.5, 78.5, "hold-drone-a"],
		["drone", 20.5, 70.5, "hold-drone-b"],
		["alien", 6.5, 75.5, "hold-gantry-alien"],
		["clone", 19.5, 86.5, "hold-cowhand"],
		["pig", 20.5, 84.5, "hold-hog-a"],
		["pig", 9.5, 66.5, "hold-hog-b"],
	]:
		b.enemy(String(e[0]), float(e[1]), float(e[2]), String(e[3]))
	# The mess: clones of county boys eating corn dogs, a cook, the crew.
	for e in [
		["clone", 33.5, 49.5, "mess-clone-a"],
		["clone", 35.5, 55.5, "mess-clone-b"],
		["billy", 32.5, 39.5, "mess-cook"],
		["drone", 40.5, 44.5, "mess-drone-a"],
		["drone", 27.5, 54.5, "mess-drone-b"],
		["alien", 42.5, 58.5, "mess-alien"],
	]:
		b.enemy(String(e[0]), float(e[1]), float(e[2]), String(e[3]))
	# The bunks.
	for e in [
		["drone", 11.5, 41.5, "bunk-drone-a"],
		["drone", 16.5, 52.5, "bunk-drone-b"],
		["drone", 9.5, 55.5, "bunk-drone-c"],
		["alien", 18.5, 38.5, "bunk-alien"],
	]:
		b.enemy(String(e[0]), float(e[1]), float(e[2]), String(e[3]))
	# Maw's parlor and her housekeeping.
	for e in [
		["tin_guard", 20.5, 29.5, "parlor-guard"],
		["probe", 12.5, 17.5, "parlor-probe-a"],
		["probe", 24.0, 17.0, "parlor-probe-b"],
	]:
		b.enemy(String(e[0]), float(e[1]), float(e[2]), String(e[3]))
	# The trophy room, and a coot they kept as one.
	for e in [
		["alien", 36.5, 26.5, "trophy-alien-a"],
		["alien", 46.5, 25.5, "trophy-alien-b"],
		["saucer", 41.0, 29.0, "trophy-saucer"],
		["coot", 31.5, 30.5, "trophy-coot"],
	]:
		b.enemy(String(e[0]), float(e[1]), float(e[2]), String(e[3]))
	# The bridge.
	for e in [
		["alien", 58.5, 23.5, "bridge-alien-w"],
		["alien", 70.5, 23.5, "bridge-alien-e"],
		["alien", 66.5, 27.5, "bridge-alien-s"],
		["tin_guard", 64.5, 28.5, "bridge-guard"],
		["drone", 59.5, 29.5, "bridge-drone-a"],
		["drone", 69.5, 29.5, "bridge-drone-b"],
	]:
		b.enemy(String(e[0]), float(e[1]), float(e[2]), String(e[3]))
	# The corn deck: bugs in the corn, farmhands, the crew picking.
	for e in [
		["skeeter", 85.5, 15.5, "corn-skeeter-a"],
		["skeeter", 98.5, 27.5, "corn-skeeter-b"],
		["drone", 80.5, 23.5, "corn-drone-a"],
		["drone", 96.5, 19.5, "corn-drone-b"],
		["drone", 100.5, 31.5, "corn-drone-c"],
		["clone", 78.5, 11.5, "corn-hand-a"],
		["clone", 103.5, 23.5, "corn-hand-b"],
		["alien", 90.5, 22.5, "corn-catwalk-alien"],
	]:
		b.enemy(String(e[0]), float(e[1]), float(e[2]), String(e[3]))
	# The shine tanks: two county moonshiners working for the greys.
	for e in [
		["billy", 115.5, 24.5, "shine-billy-a"],
		["billy", 110.5, 33.5, "shine-billy-b"],
		["drone", 117.5, 30.5, "shine-drone-a"],
		["drone", 117.5, 14.5, "shine-drone-b"],
	]:
		b.enemy(String(e[0]), float(e[1]), float(e[2]), String(e[3]))
	# The engine room.
	for e in [
		["tin_guard", 88.5, 41.5, "engine-guard-a"],
		["tin_guard", 104.5, 58.5, "engine-guard-b"],
		["drone", 93.5, 46.5, "pit-drone-a"],
		["drone", 100.5, 53.5, "pit-drone-b"],
		["drone", 99.5, 46.5, "pit-drone-c"],
		["alien", 86.5, 58.5, "engine-alien-a"],
		["alien", 106.5, 45.5, "engine-alien-b"],
	]:
		b.enemy(String(e[0]), float(e[1]), float(e[2]), String(e[3]))
	# The cargo hold, two of them shut in crates till the player walks in.
	for e in [
		["alien", 98.5, 70.5, "cargo-alien-a"],
		["alien", 108.5, 76.5, "cargo-alien-b"],
		["drone", 94.5, 80.5, "cargo-drone-a"],
		["drone", 102.5, 89.5, "cargo-drone-b"],
		["tin_guard", 104.5, 81.5, "cargo-guard"],
		["saucer", 96.0, 85.0, "cargo-saucer"],
		["drone", 91.5, 72.5, "crate-drone-a"],
		["drone", 109.5, 87.5, "crate-drone-b"],
	]:
		b.enemy(String(e[0]), float(e[1]), float(e[2]), String(e[3]))
	# The core: Maw, her two guards and two of her crew, all asleep till the iris.
	for e in [
		["maw", 64.5, 57.5, "core-maw"],
		["tin_guard", 57.5, 50.5, "core-guard-w"],
		["tin_guard", 71.5, 50.5, "core-guard-e"],
		["drone", 62.5, 42.5, "core-drone-n"],
		["drone", 69.5, 57.5, "core-drone-s"],
	]:
		b.enemy(String(e[0]), float(e[1]), float(e[2]), String(e[3]))
	b.partners.append(["bridge-alien-w", "bridge-alien-e", 1])
	b.partners.append(["engine-guard-a", "pit-drone-a", 1])


# ------------------------------------------------------------------ pickups


## A finale's worth: alien cells for the arm gun all over the ship, the heavy
## rounds kept back for the bridge (the last stop before the core) and the core.
static func pickups(b: Builder) -> void:
	for p in [
		# The bay.
		["shells", 62.5, 90.5],
		["rinds", 66.5, 90.5],
		["arm_ammo", 50.5, 74.5],
		["bullets", 72.5, 74.5],
		["beer", 47.5, 82.5],
		["armgun", 77.5, 94.5],
		["arm_ammo", 77.5, 95.5],
		["rifle_ammo", 81.5, 77.5],
		# The ring.
		["shells", 57.5, 63.5],
		["arm_ammo", 76.5, 47.5],
		["rinds", 64.5, 63.5],
		["whiskey", 50.5, 47.5],
		["rifle_ammo", 70.5, 36.5],
		["arm_ammo", 52.5, 39.5],
		# The probe lab and its closet.
		["shells", 27.5, 65.5],
		["beer", 43.5, 85.5],
		["arm_ammo", 37.5, 66.5],
		["moonshine", 29.5, 88.5],
		["rocket_ammo", 30.5, 88.5],
		["arm_ammo", 31.5, 89.5],
		# The specimen hold.
		["milk_ammo", 21.5, 63.5],
		["rinds", 6.5, 88.5],
		["rifle_ammo", 7.5, 72.5],
		["shells", 16.5, 89.5],
		["cowpie", 21.5, 81.5],
		# The mess.
		["rinds", 33.5, 38.5],
		["beer", 35.5, 38.5],
		["shells", 42.5, 47.5],
		["bullets", 26.5, 59.5],
		["whiskey", 39.5, 59.5],
		# The bunks and the locker.
		["beer", 7.5, 49.5],
		["shells", 21.5, 44.5],
		["bullets", 13.5, 57.5],
		["keg_ammo", 3.5, 44.5],
		["whiskey", 4.5, 45.5],
		["cow_ammo", 3.5, 46.5],
		# Maw's parlor.
		["rinds", 9.5, 15.5],
		["moonshine", 26.5, 31.5],
		["arm_ammo", 9.5, 31.5],
		["pressure_ammo", 26.5, 13.5],
		# The trophy room and its vault.
		["shells", 31.5, 17.5],
		["rifle_ammo", 49.5, 30.5],
		["rocket_ammo", 38.5, 9.5],
		["cow_ammo", 42.5, 9.5],
		["whiskey", 40.5, 10.5],
		["bottle_launcher", 39.5, 10.5],
		# The bridge: the last stop before the core.
		["rocket_ammo", 57.5, 29.5],
		["arm_ammo", 71.5, 25.5],
		["arm_ammo", 56.5, 25.5],
		["shells", 66.5, 29.5],
		["cow_ammo", 62.5, 29.5],
		["whiskey", 72.5, 17.5],
		["rinds", 56.5, 17.5],
		["moonshine", 68.5, 25.5],
		# The corn deck and the still behind it.
		["cowpie", 89.5, 33.5],
		["shells", 103.5, 11.5],
		["rinds", 77.5, 33.5],
		["rifle_ammo", 92.5, 13.5],
		["moonshine", 84.5, 7.5],
		["moonshine", 83.5, 6.5],
		["dynamite", 85.5, 6.5],
		# The shine tanks.
		["moonshine", 121.5, 35.5],
		["keg_ammo", 121.5, 13.5],
		["powder_keg", 120.5, 14.5],
		["whiskey", 107.5, 35.5],
		# The engine room.
		["arm_ammo", 92.5, 54.5],
		["shells", 101.5, 45.5],
		["rinds", 85.5, 40.5],
		["rifle_ammo", 109.5, 60.5],
		["pressure_ammo", 109.5, 39.5],
		# The cargo hold.
		["arm_ammo", 87.5, 89.5],
		["shells", 111.5, 67.5],
		["beer", 99.5, 66.5],
		["rocket_ammo", 111.5, 89.5],
		["bullets", 87.5, 77.5],
		# The core: a little round the edge, under the pods.
		["arm_ammo", 55.5, 47.5],
		["arm_ammo", 73.5, 47.5],
		["rinds", 64.5, 40.5],
		["shells", 56.5, 56.5],
	]:
		b.pickup(String(p[0]), float(p[1]), float(p[2]))


# ------------------------------------------------------------------ the rooms


## Every room furnished by hand, each group against a wall or round the thing
## it belongs to.
static func dress(p) -> void:
	_bay(p)
	_ring(p)
	_core(p)
	_west(p)
	_north(p)
	_east(p)


## The bay: the beam holding a pickup off the deck, the junk it already hauled
## up stacked round the walls, the school bus, the escape outhouse.
static func _bay(p) -> void:
	var b: Builder = p.b
	b.town("beam_emitter", 64.0, 83.0, {"z": 4.9})
	b.town("hung_pickup", 64.0, 83.0, {"z": 1.5})
	b.mark("mark_beam", 64.0, 83.0, 0.0, 2.3, 2.3)
	b.mark("mark_beam", 64.5, 92.5, 0.0, 1.1, 1.1)
	b.board("ship_hazard", 60.0, 79.5, .6, {"z": .5, "plane": 0.0})
	b.board("ship_hazard", 68.0, 87.5, .6, {"z": .5, "plane": PI})
	p.on_wall("ship_sign_tractor", 59.0, 72.0, "n", .8, 2.6)
	# The school bus along the west wall, its plaque on its side.
	p.block(46.3, 84.1, 48.6, 89.9, .05)
	b.town("school_bus", 47.4, 87.0)
	b.board("ship_plaque_bus", 49.4, 87.0, .32, {"z": .6, "plane": -PI / 2})
	# The junk pile in the north-west corner.
	p.stand("washer", 47.5, 72.5, .4)
	p.stand("fridge", 49.5, 72.5, .4)
	p.stand("tire_stack", 46.5, 74.5, .34)
	p.stand("mailbox_row", 46.5, 76.5, .4)
	p.stand("gas_cans", 50.5, 72.5, .3)
	# The county things along the north wall, either side of the way in.
	p.stand("outhouse", 57.5, 72.5, .42)
	p.stand("port_a_john", 55.5, 72.5, .42)
	p.stand("tractor", 70.5, 73.5, .45)
	p.stand("scarecrow", 72.5, 72.5, .3)
	p.stand("hay_wagon", 77.5, 73.5, .45)
	# The beam's controls by the pad, and the operator's booth up the gantry.
	p.stand("alien_console", 60.5, 95.5, .42)
	p.on_wall("ship_deck_four", 60.5, 97.0, "s", .6, 1.6)
	p.on_wall("ship_glyphs_a", 57.5, 97.0, "s", .5, 1.6)
	p.stand("alien_console", 78.5, 96.5, .42)
	p.stand("rocker", 79.5, 95.5, .3)
	# Railings along the gantry and round the booth: the only way up is the ramp.
	rail(b, 80.3, 76.0, 80.7, 93.0)
	rail(b, 76.0, 93.3, 80.0, 93.7)
	rail(b, 76.3, 94.0, 76.7, 97.0)
	p.on_wall("ship_glyphs_b", 79.5, 97.0, "s", .5, 1.9)
	p.stand("alien_crate", 82.5, 84.5, .4)
	p.stand("alien_crate", 82.5, 91.5, .4)
	b.arch(54.0, 96.4, 3.0, "route_hub", "ship_tin")
	# The county coop they beamed up whole, hens and all, east of the beam.
	p.stand("chicken_coop", 77.5, 88.5, .42)
	b.bale(76.5, 85.5)
	b.bale(77.5, 84.5)
	p.stand("wheelbarrow", 72.5, 91.5, .34)
	# Crates of county goods stacked by the return beam in the south-west.
	for c in [Vector2(47.5, 93.5), Vector2(47.5, 95.5), Vector2(49.5, 95.5)]:
		b.crate_stack(c.x, c.y, .75)
	b.crate_stack(48.5, 94.5, 1.5)
	for l in [Vector2(52.0, 80.0), Vector2(76.0, 80.0), Vector2(52.0, 91.0), Vector2(64.0, 76.0)]:
		b.prop("lamp", l.x, l.y)


## The ring deck: crates at the outer wall, a light every eighth of the way,
## arrows at the doors, the core's door marked.
static func _ring(p) -> void:
	var b: Builder = p.b
	for k in 8:
		var a := k * TAU / 8.0 + TAU / 16.0
		b.prop("lamp", p.CX + cos(a) * 14.1, p.CY + sin(a) * 14.1)
	for c in [Vector2i(55, 39), Vector2i(73, 61), Vector2i(78, 55), Vector2i(50, 55)]:
		p.stand("alien_crate", c.x + .5, c.y + .5, .38)
	p.stand("pod", 76.5, 42.5, .4)
	p.stand("pod", 49.5, 47.5, .4)
	p.on_wall("ship_sign_core", 62.0, 37.0, "s", .7, 1.3)
	p.on_wall("ship_sign_ring", 62.0, 63.0, "n", .6, 1.6)
	b.board("ship_arrow_left", 66.0, 64.4, .35, {"z": 1.0, "plane": 0.0})
	b.board("ship_arrow_right", 66.0, 35.6, .35, {"z": 1.0, "plane": PI})
	p.on_wall("ship_glyphs_a", 80.0, 48.0, "e", .45, 1.3)
	p.on_wall("ship_glyphs_b", 48.0, 51.6, "w", .45, 1.3)


## The core: the beam coming down its middle, pods round the wall, her crew's
## spawning points in front of them (boss_decoys).
static func _core(p) -> void:
	var b: Builder = p.b
	b.town("beam_emitter", 64.0, 50.0, {"z": 6.6})
	b.mark("mark_beam", 64.0, 50.0, 0.0, 2.6, 2.6)
	var spawns: Array = []
	for k in 8:
		var a := k * TAU / 8.0 + TAU / 16.0
		var pod := Vector2(p.CX + cos(a) * 10.3, p.CY + sin(a) * 10.3)
		p.stand("pod", pod.x, pod.y, .42)
		var at := Vector2(p.CX + cos(a) * 8.3, p.CY + sin(a) * 8.3)
		spawns.append([snappedf(floorf(at.x) + .5, .01), snappedf(floorf(at.y) + .5, .01)])
	b.meta["boss_decoys"] = spawns


static func _west(p) -> void:
	var b: Builder = p.b
	# The probe lab: three tables with a lamp over each, the probes on the
	# wall smallest to biggest, the chart, the jars, the scarecrow waiting.
	for t in [Vector2(31.5, 70.5), Vector2(39.5, 70.5), Vector2(31.5, 81.5)]:
		p.block(t.x - .9, t.y - .3, t.x + .9, t.y + .3, .05)
		b.town("probe_table", t.x, t.y)
		b.prop("lamp", t.x, t.y)
	p.town_on_wall("probe_rack", 26.0, 82.5, "w", .5)
	p.on_wall("ship_chart", 29.5, 64.0, "n", 1.1, .7)
	p.on_wall("ship_sign_probe", 40.0, 64.0, "n", .7, 1.9)
	p.on_wall("ship_glyphs_b", 26.0, 70.0, "w", .5, 1.3)
	for x in [34.5, 36.5, 38.5]:
		p.stand("specimen_jar", x, 86.5, .25)
	p.stand("scarecrow", 33.5, 73.5, .3)
	p.stand("alien_console", 43.5, 64.5, .42)
	# The specimen hold: a cow in every tube, twelve of them down the aisle,
	# their labels, hay for the ones still out.
	for y in [66, 70, 74, 78, 82, 86]:
		p.stand("cow_tube", 11.5, y + .5, .45)
		p.stand("cow_tube", 17.5, y + .5, .45)
	for y in [66, 78]:
		b.board("ship_cow_label", 12.06, y + .5, .3, {"z": .25, "plane": -PI / 2})
		b.board("ship_cow_label", 16.94, y + .5, .3, {"z": .25, "plane": PI / 2})
	p.on_wall("ship_sign_specimens", 18.0, 62.0, "n", .7, 1.9)
	b.prop("hay", 21.5, 66.5)
	b.prop("hay", 21.5, 68.5)
	p.stand("searchlight", 6.5, 81.5, .3)
	rail(b, 8.3, 66.0, 8.7, 91.0)
	# Troughs for the ones still out of their tubes.
	b.trough(21.2, 72.0, 21.8, 80.0)
	p.stand("alien_crate", 6.5, 86.5, .38)
	for y in [68.0, 76.0, 84.0]:
		b.prop("lamp", 14.5, y)
	# The mess: the kitchen behind its counter, the tables, the jukebox.
	b.fixture(26.0, 41.2, 37.0, 41.8, 1.0, "counter", "counter_top")
	p.stand("grill", 27.5, 38.5, .4)
	p.stand("fridge", 29.5, 38.5, .4)
	p.on_wall("ship_menu", 33.0, 38.0, "n", .7, 1.3)
	b.prop("sink", 36.5, 38.6)
	b.react("cans", 30.0, 41.5, .4, {"z": 1.0, "id": "mess-counter-cans"})
	for t in [Vector2(31.0, 46.5), Vector2(39.0, 46.5), Vector2(31.0, 52.5), Vector2(39.0, 52.5)]:
		p.block(t.x - 1.4, t.y - .3, t.x + 1.4, t.y + .3, .05)
		b.town("picnic_table", t.x, t.y)
	b.react("cans", 39.0, 52.5, .4, {"z": .72, "id": "mess-table-cans"})
	for t in [Vector2(31.0, 57.5), Vector2(39.0, 57.5)]:
		p.block(t.x - 1.4, t.y - .3, t.x + 1.4, t.y + .3, .05)
		b.town("picnic_table", t.x, t.y)
	b.react("bottles", 31.0, 46.5, .42, {"z": .72, "id": "mess-table-bottles"})
	p.stand("jukebox_rig", 41.5, 38.5, .4)
	b.react("jukebox", 41.5, 38.9, 1.4, {"id": "mess-jukebox", "radius": .3})
	p.on_wall("ship_jukebox_note", 43.0, 38.0, "n", .35, 1.4)
	b.react("vending", 43.6, 56.5, 1.5, {"id": "mess-vending"})
	b.crate_stack(26.5, 57.5, .7)
	b.react("tv", 26.5, 57.5, .75, {"z": .7, "id": "mess-tv"})
	p.on_wall("ship_sign_mess", 44.0, 54.0, "e", .7, 1.9)
	b.notes.append([38.5, 59.9, "COMPLAINT", "WHO KEEPS PLAYING THE SAME SONG. -THE CREW", 0.0])
	b.board("county_note", 38.5, 60.96, .3, {"z": 1.2, "plane": PI})
	for l in [Vector2(31.0, 49.5), Vector2(39.0, 49.5), Vector2(32.0, 39.5)]:
		b.prop("lamp", l.x, l.y)
	# The bunks: steel bunks down both walls, lockers by the door, washing on
	# a line, a couch and a set in the corner.
	for y in [37, 40, 50, 53, 56]:
		p.block(6.05, y + .1, 7.95, y + .9, .05)
		b.town("bunk", 7.0, y + .5)
	for y in [37, 40, 50, 53]:
		p.block(20.05, y + .1, 21.95, y + .9, .05)
		b.town("bunk", 21.0, y + .5)
	for x0 in [8.0, 16.0]:
		p.block(x0 + .05, 36.05, x0 + 3.95, 36.6, 1.9, "ship_tin")
	b.town("laundry", 14.0, 46.0, {"plane": 0.0, "z": .95})
	p.stand("porch_couch", 17.5, 43.5, .42)
	b.crate_stack(17.5, 46.5, .6)
	b.react("tv", 17.5, 46.5, .7, {"z": .6, "id": "bunk-tv"})
	p.stand("washer", 21.5, 57.5, .4)
	# A double row of bunks back to back down the middle.
	for y in [50, 53]:
		p.block(12.05, y + .1, 13.95, y + .9, .05)
		b.town("bunk", 13.0, y + .5)
		p.block(14.05, y + .1, 15.95, y + .9, .05)
		b.town("bunk", 15.0, y + .5)
	p.on_wall("ship_sign_quarters", 18.0, 59.0, "s", .7, 1.6)
	for y in [42.0, 54.0]:
		b.prop("lamp", 14.5, y)
	# Maw's parlor: her recliner by the set, the couch, the rocker, a sewing
	# table, her boy on the wall with a ribbon on him, a list, her pink birds.
	p.stand("captain_chair", 17.5, 24.5, .42)
	b.crate_stack(17.5, 19.5, .7)
	b.react("tv", 17.5, 19.5, .75, {"z": .7, "id": "parlor-tv"})
	p.stand("porch_couch", 13.5, 22.5, .42)
	p.stand("rocker", 21.5, 22.5, .3)
	b.table(9.2, 13.2, 12.8, 13.8, .8)
	p.on_wall("ship_memorial", 17.5, 13.0, "n", 1.1, 1.0)
	b.notes.append(
		[11.0, 14.6, "MAW'S LIST", "1. PROBE THE COWS. 2. FIND WHO DONE IT TO MY BOY. 3. PIE.", 0.0]
	)
	b.board("county_note", 11.0, 13.5, .3, {"z": .8, "plane": 0.0})
	p.stand("flamingo", 25.5, 14.5, .22)
	p.stand("flamingo", 26.5, 15.5, .22)
	p.stand("doghouse", 24.5, 29.5, .42)
	# Her bed, behind the papered wall: a quilt off a county line, a lamp.
	b.fixture(15.0, 29.0, 20.0, 31.9, .7, "wood", "ship_lino")
	p.block(12.6, 30.6, 14.4, 31.4, .05)
	b.town("bunk", 13.5, 31.0)
	p.stand("fridge", 8.5, 30.5, .4)
	p.on_wall("ship_wanted", 28.0, 18.0, "e", 1.0, .9)
	for l in [Vector2(17.5, 22.0), Vector2(11.5, 28.0), Vector2(23.5, 17.0)]:
		b.prop("lamp", l.x, l.y)


static func _north(p) -> void:
	var b: Builder = p.b
	# The trophy room: the best of it up on the tier, the rest on plinths.
	p.stand("trophy_gnome", 40.5, 14.5, .34)
	b.board("ship_plaque_gnome", 40.5, 15.94, .3, {"z": .05, "plane": 0.0})
	p.stand("flamingo", 33.5, 13.5, .22)
	p.stand("flamingo", 35.5, 13.5, .22)
	p.on_wall("ship_plaque_flamingo", 34.5, 13.0, "n", .32, 1.3)
	p.stand("deer_target", 37.5, 14.5, .4)
	p.stand("outhouse", 45.5, 13.5, .42)
	p.on_wall("ship_plaque_outhouse", 47.5, 13.0, "n", .32, 1.4)
	p.stand("port_a_john", 48.5, 14.5, .42)
	p.block(38.6, 23.4, 41.4, 25.6, .4, "wood")
	b.town("giant_hog", 40.0, 24.5, {"z": .4})
	p.block(33.1, 20.1, 33.9, 20.9, .5, "wood")
	b.town("prize_bear", 33.5, 20.5, {"z": .5})
	p.stand("scarecrow", 34.5, 29.5, .3)
	p.stand("tombstone_a", 46.5, 20.5, .25)
	p.stand("mailbox_row", 46.5, 29.5, .4)
	p.stand("chicken_coop", 31.5, 25.5, .42)
	p.stand("bathtub", 44.5, 18.5, .42)
	p.stand("wheelbarrow", 49.5, 20.5, .34)
	p.stand("skull_post", 43.5, 30.5, .22)
	p.on_wall("ship_sign_trophy", 51.0, 28.0, "e", .7, 1.9)
	for l in [Vector2(40.0, 22.0), Vector2(34.0, 18.0), Vector2(46.0, 18.0), Vector2(40.0, 14.0)]:
		b.prop("lamp", l.x, l.y)
	# The bridge: the screen, crew at their consoles either side, the captain's
	# chair behind the iris console, a lounge at the back with the beer.
	p.stand("captain_chair", 64.5, 21.5, .42)
	for c in [Vector2(57.5, 17.5), Vector2(57.5, 20.5), Vector2(71.5, 17.5), Vector2(71.5, 20.5)]:
		p.stand("alien_console", c.x, c.y, .42)
	p.stand("porch_couch", 59.5, 28.5, .42)
	# The map table: the county under glass, lit from below.
	b.fixture(62.2, 25.2, 66.8, 26.8, .9, "ship_hull", "ship_screen")
	p.stand("fridge", 72.5, 29.5, .4)
	p.on_wall("ship_glyphs_a", 59.0, 31.0, "s", .5, 1.4)
	p.on_wall("ship_glyphs_b", 69.0, 31.0, "s", .5, 1.4)
	p.on_wall("ship_sign_bridge", 67.5, 31.0, "s", .7, 2.1)
	p.on_wall("ship_deck_four", 56.0, 27.0, "w", .6, 1.3)
	p.on_wall("ship_wanted", 73.0, 27.0, "e", 1.0, .9)
	b.notes.append(
		[
			66.5,
			16.4,
			"CAPTAIN'S LOG",
			"DAY 9 OVER HICKSTON. MAW WON'T GO HOME TILL SHE GETS HER REVENGE AND HER DISH BACK.",
			0.0
		]
	)
	b.board("county_note", 66.5, 16.06, .3, {"z": 1.1, "plane": 0.0})
	for l in [Vector2(60.0, 19.0), Vector2(68.0, 19.0), Vector2(64.0, 27.0)]:
		b.prop("lamp", l.x, l.y)
	# The corn deck: county corn in beds, cross aisles cut through, a
	# scarecrow they brought with it, a tractor, the grow trays by the east wall.
	for y in [13, 17, 21, 25, 29]:
		var gap_left: bool = y == 17 or y == 25
		var gap_right: bool = y == 21 or y == 29
		if gap_left:
			b.fixture(79.0, y + .04, 83.0, y + 1.96, 1.4, "corn", "dirt")
			b.fixture(85.0, y + .04, 89.0, y + 1.96, 1.4, "corn", "dirt")
		else:
			b.fixture(79.0, y + .04, 89.0, y + 1.96, 1.4, "corn", "dirt")
		if gap_right:
			b.fixture(93.0, y + .04, 96.0, y + 1.96, 1.4, "corn", "dirt")
			b.fixture(98.0, y + .04, 103.0, y + 1.96, 1.4, "corn", "dirt")
		else:
			b.fixture(93.0, y + .04, 103.0, y + 1.96, 1.4, "corn", "dirt")
	p.stand("scarecrow", 78.5, 19.5, .3)
	p.stand("tractor", 82.5, 32.5, .45)
	for y in [12.5, 17.5, 26.5, 32.5]:
		p.stand("corn_tray", 104.5, y, .42)
	p.on_wall("ship_sign_corn", 96.0, 10.0, "n", .8, 2.6)
	for l in [Vector2(84.0, 15.5), Vector2(98.0, 15.5), Vector2(84.0, 27.5), Vector2(98.0, 27.5)]:
		b.prop("lamp", l.x, l.y)
	# The still somebody hid behind the corn.
	p.stand("still", 85.5, 7.5, .42)
	p.stand("jug_stack", 82.5, 6.5, .35)
	# The shine tanks: copper tanks on cradles down the east wall, green
	# glass tanks in the middle, the vats, the still, the jugs.
	for y in [18.0, 22.0, 26.0, 30.0]:
		b.fixture(119.4, y, 122.8, y + 2.4, 1.0, "quarry_copper", "ship_grate")
		b.town("shine_tank", 121.1, y + 1.2, {"z": .3})
	for y in [19.0, 25.0]:
		b.fixture(112.04, y + .04, 113.96, y + 1.96, 3.6, "ship_vat", "ship_grate")
	p.stand("copper_vat", 108.5, 27.5, .42)
	p.stand("copper_vat", 108.5, 30.5, .42)
	p.stand("still", 113.5, 34.5, .42)
	p.stand("jug_stack", 116.5, 35.5, .35)
	p.stand("jug_stack", 111.5, 35.5, .35)
	p.stand("mash_barrel", 117.5, 19.5, .4)
	rail(b, 110.0, 15.3, 123.0, 15.7)
	p.on_wall("ship_shine_note", 118.0, 12.0, "n", .35, 1.4)
	p.on_wall("ship_sign_engine", 115.0, 37.0, "s", .7, 2.0)
	for d in [Vector2(110.5, 18.5), Vector2(116.5, 28.5)]:
		b.fuel_drums.append([d.x, d.y])
	for l in [Vector2(113.0, 23.0), Vector2(118.0, 33.0)]:
		b.prop("lamp", l.x, l.y)


static func _east(p) -> void:
	var b: Builder = p.b
	# The engine room: the drive in its pit drinking shine, tanks at the east
	# wall feeding it, jugs and mash barrels round the rim.
	b.fixture(96.0, 49.0, 98.0, 51.0, -.2, "ship_hull", "ship_grate", -.96)
	b.town("ship_engine", 97.0, 50.0, {"z": .76})
	for y in [41.0, 56.0]:
		b.fixture(107.4, y, 110.8, y + 2.4, 1.0, "quarry_copper", "ship_grate")
		b.town("shine_tank", 109.1, y + 1.2, {"z": .3})
	for c in [Vector2(88.5, 43.5), Vector2(106.5, 43.5), Vector2(88.5, 57.5), Vector2(106.5, 57.5)]:
		p.stand("jug_stack", c.x, c.y, .35)
	# A railing round the pit but where the ramps go down.
	rail(b, 90.0, 44.3, 105.0, 44.7)
	rail(b, 90.0, 56.3, 105.0, 56.7)
	for y in [[45.0, 49.0], [52.0, 56.0]]:
		rail(b, 90.3, y[0], 90.7, y[1])
		rail(b, 104.3, y[0], 104.7, y[1])
	p.stand("mash_barrel", 86.5, 40.5, .4)
	p.stand("mash_barrel", 86.5, 60.5, .4)
	# Two turbines either side of the way in, coolant in green glass north,
	# the work bench south with its engine hoist.
	for y in [43.0, 53.0]:
		b.fixture(85.2, y, 87.8, y + 4.0, 4.2, "ship_hull", "ship_hull")
	for x in [91.0, 99.0]:
		b.fixture(x, 40.0, x + 2.0, 41.6, 3.4, "ship_vat", "ship_grate")
	p.stand("engine_hoist", 93.5, 59.5, .45)
	p.stand("generator", 101.5, 59.5, .45)
	b.table(95.2, 59.2, 97.8, 59.8, .9)
	# The fuel rule on the pit rail by the way down to the drive.
	b.board("ship_shine_note", 90.74, 48.5, .3, {"z": .62, "plane": -PI / 2})
	p.on_wall("ship_sign_engine", 84.0, 46.0, "w", .7, 2.4)
	p.on_wall("ship_glyphs_a", 97.0, 39.0, "n", .5, 2.0)
	for d in [Vector2(85.5, 52.5), Vector2(108.5, 47.5)]:
		b.fuel_drums.append([d.x, d.y])
	for l in [Vector2(90.0, 42.0), Vector2(104.0, 42.0), Vector2(90.0, 58.0), Vector2(104.0, 58.0)]:
		b.prop("lamp", l.x, l.y)
	# The cargo hold: crates stacked in rows, a forklift, a car they took,
	# the safe somebody hauled up with it.
	for c in [
		[89.0, 68.0, 92.0, 70.0, 1.6],
		[104.0, 68.0, 108.0, 70.0, 2.2],
		[90.0, 83.0, 93.0, 86.0, 1.9],
		[100.0, 83.0, 103.0, 85.0, 1.4],
		[109.0, 81.0, 112.0, 85.0, 2.4],
	]:
		b.fixture(c[0] + .04, c[1] + .04, c[2] - .04, c[3] - .04, c[4], "crate_side", "counter_top")
	for c in [Vector2(93.5, 69.5), Vector2(103.5, 69.5), Vector2(94.5, 85.5), Vector2(99.5, 84.5)]:
		p.stand("alien_crate", c.x, c.y, .38)
	p.stand("forklift", 96.5, 73.5, .45)
	b.car(106.0, 74.5, true, "tin")
	p.stand("safe_open", 111.5, 71.5, .38)
	p.stand("generator", 87.5, 86.5, .45)
	p.stand("pallet_stack", 104.5, 89.5, .4)
	for c in [
		[88.0, 73.0, 90.0, 75.0, 1.2],
		[100.0, 71.0, 103.0, 73.0, 1.8],
		[95.0, 87.0, 98.0, 89.0, 1.5],
		[106.0, 86.0, 108.0, 88.0, 2.0],
	]:
		b.fixture(c[0] + .04, c[1] + .04, c[2] - .04, c[3] - .04, c[4], "crate_side", "counter_top")
	p.on_wall("ship_sign_cargo", 86.0, 80.0, "w", .7, 2.4)
	for l in [Vector2(92.0, 76.0), Vector2(104.0, 78.0), Vector2(98.0, 88.0)]:
		b.prop("lamp", l.x, l.y)


# ------------------------------------------------------------------ set pieces


static func set_pieces(b: Builder) -> void:
	for t in [
		{
			"id": "maw-down",
			"when": {"down": ["core-maw"]},
			"do": [{"open": [64, 62]}, {"shake": .8}],
		},
		{
			"id": "ring-first",
			"when": {"area": [48, 34, 80, 66]},
			"do": [{"message": "THE RING DECK. IT GOES ALL THE WAY ROUND.", "for": 3.0}],
		},
		{
			"id": "probe-lab",
			"when": {"area": [26, 64, 44, 86]},
			"do": [{"message": "THE PROBE LAB. KEEP YER BACK TO THE WALL.", "for": 3.0}],
		},
		{
			"id": "parlor",
			"when": {"area": [8, 13, 27, 32]},
			"do": [{"message": "MAW'S PARLOR. MOTHBALLS AND OZONE.", "for": 3.0}],
		},
		{
			"id": "corn-rustle",
			"when": {"area": [77, 10, 104, 34]},
			"do":
			[
				{"message": "SOMETHING'S MOVING IN THE CORN.", "for": 3.0},
				{"wake": ["corn-skeeter-a", "corn-skeeter-b"]}
			],
		},
		{
			"id": "cargo-crates",
			"when": {"area": [86, 66, 112, 90]},
			"do":
			[
				{"message": "THE CRATES ARE MOVING.", "for": 2.5},
				{"wake": ["crate-drone-a", "crate-drone-b"]},
				{"sound": "scenery_scrap", "at": [100.0, 80.0]}
			],
		},
		{
			"id": "tubes-cows",
			"when": {"station": "tubes"},
			"do": [{"shake": .4}, {"sound": "cow_moo", "at": [14.0, 76.0]}],
		},
	]:
		b.triggers.append(t)
	b.exchanges.append(
		{
			"id": "ship-pa",
			"x": 64.0,
			"y": 64.0,
			"stop_at": "",
			"lines": ["PA: HOOMAN LOOSE ON DECK FOUR.", "VOICE: WHICH ONE IS THE HOOMAN?"]
		}
	)
	b.exchanges.append(
		{
			"id": "mess-pa",
			"x": 35.0,
			"y": 50.0,
			"stop_at": "",
			"lines": ["PA: CORN DOGS ARE OFF.", "VOICE: AGAIN?"]
		}
	)
	b.exchanges.append(
		{
			"id": "engine-pa",
			"x": 90.0,
			"y": 50.0,
			"stop_at": "drive",
			"lines": ["PA: WHO PUT DIESEL IN THE DRIVE?", "VOICE: SIGN SAID UNLEADED."]
		}
	)
	b.exchanges.append(
		{
			"id": "bridge-pa",
			"x": 64.0,
			"y": 24.0,
			"stop_at": "iris",
			"lines": ["MAW: WHERE'S MY BOY'S TIN STAR?", "VOICE: HICKSTON, MAW."]
		}
	)
	b.distant_cues.append([97.0, 50.0, "distant_mill_pump"])
	b.distant_cues.append([90.0, 22.0, "distant_corn_rustle"])
	b.distant_cues.append([114.0, 24.0, "distant_quarry_bottler"])
