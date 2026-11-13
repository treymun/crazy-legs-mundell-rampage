## Mundell's Salvage (5v5 map "salvage", src/modes/tactical_mode.gd): a
## junkyard at dusk, tight and full of corners, built for search and destroy
## and hostage rescue alike. An original layout, three lanes and two sites:
##
##   east   the TOW LOT, where the attackers start (the rescue box in
##          hostage rescue);
##   north  HUBCAP ALLEY up out of the lot and west under the stacked cars,
##          then the narrow CRANE GAP onto site A;
##   mid    the TOW ROAD into WRECK CANYON, a zig-zag of junk walls; A SHORT
##          up its north-west corner onto A, B SHORT down its south-west corner
##          to the tire barn's side doors;
##   south  PARTS ROW down out of the lot and west along the BUS LANE past the
##          dead school bus to the tire barn's back doors;
##   west   the SCALE SHACK lot, where the defenders start, a short run north
##          to A and south to B, and the long look east down SCALE ROW into
##          the canyon.
## Site A is the CRUSHER PIT: open, the car crusher and the crane to fight
## round. Site B is the TIRE BARN: a tin barn, tyre stacks and a lift.
## The hostages are held on each site.
##
## Built by tools/levels/build_level.gd -- salvage. Units are cells; x runs
## east, y south, angles as the player's (0 east, PI west).
extends RefCounted

const Builder := preload("res://tools/levels/level_builder.gd")
const W := 60
const H := 50

var b: Builder
var d := {}


func make() -> Builder:
	b = Builder.new("salvage", W, H, "junk_stack")
	b.meta = {
		"title": "MUNDELL'S SALVAGE",
		"heading": ["MUNDELL'S", "SALVAGE"],
		"intro": "MUNDELL'S SALVAGE. FIVE A SIDE. B TO BUY.",
		"score": "music",
		"ambience": "range",
		"layout": 1,
		"sky": "sky",
		"area_sounds": {},
		"tactical":
		{
			"attack_spawns":
			[
				[55.5, 19.5, PI],
				[55.5, 23.5, PI],
				[55.5, 27.5, PI],
				[52.5, 21.5, PI],
				[52.5, 25.5, PI],
			],
			"defend_spawns":
			[
				[3.5, 21.5, 0.0],
				[3.5, 24.5, 0.0],
				[3.5, 27.5, 0.0],
				[6.5, 22.5, 0.0],
				[6.5, 26.5, 0.0],
			],
			"sites": {"A": [6, 4, 17, 13], "B": [6, 36, 17, 45]},
			"hostages": [[6.5, 4.5], [6.5, 45.5]],
			"rescue": [50, 17, 57, 32],
			"routes":
			{
				"A":
				[
					[[51.5, 15.5], [48.5, 8.5], [36.5, 6.5], [24.5, 8.5], [12.5, 8.5]],
					[
						[47.5, 24.5],
						[42.5, 24.5],
						[34.5, 22.5],
						[22.5, 19.5],
						[18.5, 16.5],
						[12.5, 10.5]
					],
				],
				"B":
				[
					[[51.5, 34.5], [49.5, 42.5], [35.5, 43.5], [22.5, 43.5], [12.5, 41.5]],
					[
						[47.5, 24.5],
						[42.5, 26.5],
						[33.5, 27.5],
						[22.5, 31.5],
						[22.5, 38.5],
						[12.5, 39.5]
					],
				],
			},
			"holds":
			{
				"A": [[8.5, 6.5, .2], [10.5, 12.5, -.3]],
				"B": [[8.5, 42.5, 0.0], [10.5, 37.5, .4]],
				"mid": [[12.5, 24.5, 0.0]],
			},
		},
	}
	return b


func build(_b) -> Array:
	d["tow"] = b.district("TOW LOT", Color(1.04, 1.0, .92))
	d["hubcap"] = b.district("HUBCAP ALLEY", Color(1.02, 1.0, .94))
	d["a"] = b.district("SITE A  CRUSHER PIT", Color(1.08, .98, .86))
	d["canyon"] = b.district("WRECK CANYON", Color(1.04, .98, .9))
	d["parts"] = b.district("PARTS ROW", Color(1.02, 1.0, .94))
	d["bus"] = b.district("BUS LANE", Color(1.04, 1.0, .9))
	d["b"] = b.district("SITE B  TIRE BARN", Color(1.08, .97, .84))
	d["shack"] = b.district("SCALE SHACK", Color(1.0, 1.0, 1.04))
	# Junk piled high everywhere; the yards are what is left between it.
	b.wall(0, 0, W - 1, H - 1, "junk_stack", 3.1)
	b.wall(0, 0, W - 1, 0, "crash_wall", 3.4)
	b.wall(0, H - 1, W - 1, H - 1, "crash_wall", 3.4)
	b.wall(4, 34, 19, 47, "tin", 3.2, true)
	east()
	north()
	middle()
	south()
	west()
	return [55.5, 23.5, PI]


# ------------------------------------------------------------------- east


func east() -> void:
	b.yard(50, 17, 57, 32, "asphalt", d["tow"])
	b.paint(51, 18, 56, 31, "oil_asphalt")
	b.town("tow_truck", 56.5, 31.5, {"solid": .44})
	b.town("monster_truck", 56.5, 17.5, {"solid": .46})
	b.town("hung_pickup", 50.5, 30.5)
	b.town("tire_pile", 50.5, 17.5, {"solid": .34})
	b.streetlamp(57.5, 24.5, 4.6)


# ------------------------------------------------------------------ north


func north() -> void:
	b.yard(46, 6, 53, 16, "junk_ground", d["hubcap"])
	b.yard(28, 4, 45, 9, "junk_ground", d["hubcap"])
	b.paint(28, 6, 53, 7, "gravel")
	b.town("hubcap_board", 47.5, 15.5)
	b.car(49.0, 11.0, false)
	b.town("crushed_stack", 52.5, 6.5, {"solid": .44})
	b.town("crushed_stack", 38.5, 4.5, {"solid": .44})
	b.car(33.0, 8.5, true)
	b.town("engine_stand", 43.5, 8.5, {"solid": .3})
	b.crate_stack(29.5, 4.5)
	# The crane gap: three wide, onto the crusher pit.
	b.yard(19, 7, 27, 9, "junk_ground", d["a"])
	b.town("cable_spool", 25.5, 7.5, {"solid": .32})
	# Site A: the crusher pit.
	b.yard(5, 3, 18, 14, "junk_ground", d["a"])
	b.paint(6, 4, 17, 13, "track_chalk")
	b.paint(7, 5, 16, 12, "derby_mud")
	b.town("car_crusher", 11.5, 8.5, {"solid": .48})
	b.town("magnet_crane", 15.5, 4.5, {"solid": .44})
	b.car(7.5, 11.5, true)
	b.town("crushed_stack", 16.5, 12.5, {"solid": .44})
	b.crate_stack(13.5, 12.5, 1.1)
	b.town("tire_stack", 5.5, 7.5, {"solid": .34})
	b.streetlamp(5.5, 3.5, 4.6)


# ------------------------------------------------------------------- mid


func middle() -> void:
	b.yard(45, 22, 49, 26, "asphalt", d["canyon"])
	b.yard(20, 19, 44, 29, "junk_ground", d["canyon"])
	b.paint(20, 23, 44, 25, "gravel")
	# The canyon's walls of junk, staggered so nothing sees end to end.
	b.wall(24, 19, 26, 22, "junk_stack", 2.8)
	b.wall(30, 26, 32, 29, "junk_stack", 2.8)
	b.wall(36, 19, 38, 22, "tire_wall", 2.4)
	b.wall(40, 26, 41, 29, "junk_stack", 2.8)
	b.car(28.0, 23.5, true)
	b.car(39.0, 24.0, false)
	b.town("wrecked_derby", 34.5, 28.5)
	b.crate_stack(21.5, 27.5)
	b.town("warning_barrel", 43.5, 19.5, {"solid": .26})
	b.streetlamp(33.5, 19.5, 4.6)
	# A short and B short, off the canyon's west end.
	b.yard(14, 15, 22, 18, "junk_ground", d["a"])
	b.town("tire_stack", 21.5, 15.5, {"solid": .34})
	b.yard(20, 30, 24, 40, "junk_ground", d["b"])
	b.town("engine_hoist", 23.5, 34.5, {"solid": .4})


# ----------------------------------------------------------------- south


func south() -> void:
	b.yard(46, 33, 53, 44, "junk_ground", d["parts"])
	b.town("tire_pile", 52.5, 36.5, {"solid": .34})
	b.town("gas_cans", 46.5, 43.5, {"solid": .26})
	b.crate_stack(48.5, 38.5)
	b.yard(25, 41, 45, 45, "asphalt", d["bus"])
	b.paint(25, 43, 45, 43, "shoulder")
	# The dead school bus: a long block down the lane's north side.
	b.fixture(30.1, 41.1, 37.9, 42.4, 1.7, "mill_tin", "tin")
	b.town("school_bus", 34.0, 41.8)
	b.car(42.0, 44.0, true)
	b.town("tire_stack", 26.5, 45.5, {"solid": .34})
	b.yard(19, 41, 24, 45, "asphalt", d["bus"])
	# Site B: the tire barn, doors on its east side and north to the shack.
	b.room(5, 35, 18, 46, "concrete", d["b"], {"skin": "tin", "light": .68, "roof": 3.0})
	b.paint(6, 36, 17, 45, "oil_asphalt")
	b.gap(19, 38, "e")
	b.gap(19, 39, "e")
	b.gap(19, 43, "e")
	b.gap(19, 44, "e")
	b.gap(5, 34, "n")
	b.gap(6, 34, "n")
	b.gap(7, 34, "n")
	b.town("tire_stack", 9.5, 38.5, {"solid": .36})
	b.town("tire_stack", 14.5, 43.5, {"solid": .36})
	b.town("tire_pile", 15.5, 37.5, {"solid": .34})
	b.town("engine_hoist", 11.5, 44.5, {"solid": .4})
	b.town("tool_chest", 17.5, 40.5, {"solid": .34})
	b.crate_stack(6.5, 40.5, 1.1)
	b.prop("lamp", 11.5, 40.5)


# ------------------------------------------------------------------ west


func west() -> void:
	b.yard(2, 19, 8, 30, "gravel", d["shack"])
	b.yard(3, 15, 8, 18, "gravel", d["shack"])
	b.yard(3, 31, 8, 33, "gravel", d["shack"])
	b.yard(9, 22, 19, 26, "gravel", d["shack"])
	b.paint(9, 24, 19, 24, "shoulder")
	b.town("tow_truck", 2.5, 29.5, {"solid": .44})
	b.prop("pickup_truck", 2.5, 19.5)
	b.fixture(1.8, 19.1, 3.2, 19.9, .3, "mill_tin", "tin")
	b.crate_stack(15.5, 22.5)
	b.town("mailbox_row", 8.5, 30.5)
	b.streetlamp(8.5, 19.5, 4.4)
	b.label("TOW LOT", 52, 24)
	b.label("HUBCAP ALLEY", 34, 6)
	b.label("A", 11, 8)
	b.label("WRECK CANYON", 30, 24)
	b.label("BUS LANE", 33, 44)
	b.label("B", 11, 40)
	b.label("SCALE SHACK", 3, 24)
