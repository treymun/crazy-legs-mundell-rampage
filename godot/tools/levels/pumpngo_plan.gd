## Pump & Go (2v2 TAG TEAM map "pumpngo", src/modes/bomb_mode.gd): a highway
## gas station at dusk, small and built for two a side and one bomb site. An
## original layout:
##
##   west   the HIGHWAY SHOULDER, where the outlaws start;
##   north  TRUCK PARKING, the long open lane along the top fence, in through
##          the fence gap onto the pumps;
##   middle the CORNER STORE: in its side door, through the aisles, out the
##          loading dock and up the SERVICE ALLEY onto the pumps from below;
##   south  the FRONTAGE ROAD, the flank round to the deputies' lot;
##   east   the GARAGE LOT, where the deputies start, a few steps from the
##          pumps up the alley or through the garage bay.
## The site is THE PUMPS: the island, a car at the pump, the fuel tank, tyres.
##
## Built by tools/levels/build_level.gd -- pumpngo. Units are cells; x runs
## east, y south, angles as the player's (0 east, PI west, -PI/2 north).
extends RefCounted

const Builder := preload("res://tools/levels/level_builder.gd")
const W := 40
const H := 30
const N := -PI / 2

var b: Builder
var d := {}


func make() -> Builder:
	b = Builder.new("pumpngo", W, H, "tin")
	b.meta = {
		"title": "PUMP & GO",
		"heading": ["PUMP &", "GO"],
		"intro": "PUMP & GO. TWO A SIDE. B TO BUY.",
		"score": "music",
		"ambience": "range",
		"layout": 1,
		"sky": "sky",
		"area_sounds": {},
		"tactical":
		{
			"attack_spawns": [[4.5, 13.5, 0.0], [4.5, 16.5, 0.0], [6.5, 15.0, 0.0]],
			"defend_spawns": [[34.5, 20.5, PI], [34.5, 23.5, PI], [36.5, 22.0, PI]],
			"sites": {"A": [25, 3, 31, 12]},
			"hostages": [],
			"rescue": [2, 12, 7, 18],
			"routes":
			{
				"A":
				[
					[[4.5, 10.5], [4.5, 4.5], [14.5, 4.5], [21.5, 3.5], [25.5, 3.5], [28.5, 5.0]],
					[
						[9.5, 14.5],
						[13.5, 15.5],
						[18.5, 14.5],
						[23.5, 16.5],
						[26.5, 16.5],
						[29.5, 15.5],
						[29.5, 12.5],
						[28.0, 11.0]
					],
				],
			},
			"holds":
			{
				"A": [[30.5, 3.0, PI], [25.5, 9.5, .82]],
				"mid": [[33.5, 17.5, PI]],
			},
		},
	}
	return b


func build(_b) -> Array:
	d["shoulder"] = b.district("HIGHWAY SHOULDER", Color(1.04, 1.0, .92))
	d["parking"] = b.district("TRUCK PARKING", Color(1.02, 1.0, .94))
	d["a"] = b.district("SITE A  THE PUMPS", Color(1.08, 1.0, .86))
	d["store"] = b.district("CORNER STORE", Color(1.06, 1.0, .9))
	d["alley"] = b.district("SERVICE ALLEY", Color(1.0, .98, .94))
	d["road"] = b.district("FRONTAGE ROAD", Color(1.02, 1.0, .94))
	d["lot"] = b.district("GARAGE LOT", Color(1.0, 1.0, 1.04))
	b.wall(0, 0, W - 1, H - 1, "tin", 3.0)
	b.wall(0, 0, W - 1, 1, "hedgerow", 3.4)
	b.wall(0, H - 2, W - 1, H - 1, "hedgerow", 3.4)
	b.wall(0, 0, 1, H - 1, "hedgerow", 3.4)
	b.wall(W - 2, 0, W - 1, H - 1, "hedgerow", 3.4)
	# The store's brick and the garage's block, the rest tin sheds and fence.
	b.wall(13, 8, 23, 18, "brick", 3.0, true)
	b.wall(32, 4, 37, 13, "cinder", 3.2, true)
	b.wall(24, 14, 27, 20, "cinder", 3.0, true)
	west()
	north()
	store()
	south()
	east()
	return [4.5, 15.0, 0.0]


func west() -> void:
	b.yard(2, 7, 7, 25, "asphalt", d["shoulder"])
	b.paint(2, 7, 3, 25, "shoulder")
	b.prop("pickup_truck", 6.5, 8.5)
	b.fixture(5.8, 8.1, 7.2, 8.9, .3, "mill_tin", "tin")
	b.prop("roadsign", 2.5, 21.5)
	b.town("tire_pile", 2.5, 7.5, {"solid": .34})
	b.streetlamp(3.5, 24.5, 4.4)
	# The ice yard by the store's side door.
	b.yard(8, 12, 12, 17, "asphalt", d["shoulder"])
	b.town("ice_chest", 11.5, 12.5, {"solid": .3})
	b.town("burn_barrel", 8.5, 17.5, {"solid": .28})


func north() -> void:
	b.yard(2, 2, 22, 6, "gravel", d["parking"])
	b.paint(2, 4, 22, 4, "asphalt")
	b.town("semi_tractor", 16.5, 2.5, {"solid": .44})
	b.crate_stack(10.5, 2.5)
	b.crate_stack(11.5, 2.5, 1.1)
	b.town("tire_pile", 20.5, 6.5, {"solid": .34})
	b.town("wheelbarrow", 6.5, 6.5, {"solid": .28})
	# The gap in the fence onto the pumps.
	b.yard(23, 2, 23, 4, "gravel", d["a"])
	b.streetlamp(22.5, 2.5, 4.4)
	# The pumps: the island and its pumps, a car at them, the fuel tank, tyres.
	b.yard(24, 2, 31, 13, "concrete", d["a"])
	b.yard(32, 2, 37, 3, "concrete", d["a"])
	b.paint(26, 4, 31, 12, "oil_asphalt")
	b.fixture(27.2, 7.2, 30.8, 7.8, .25, "concrete", "concrete")
	b.town("fuel_pump", 27.8, 7.5, {"solid": .3})
	b.town("fuel_pump", 30.2, 7.5, {"solid": .3})
	b.car(29.0, 10.0, true)
	b.town("fuel_tank", 36.5, 2.5, {"solid": .44})
	b.town("tire_stack", 25.5, 12.5, {"solid": .34})
	b.crate_stack(31.5, 4.0)
	# Crates stacked head high: the corner by the alley hidden from the fence gap.
	b.crate_stack(24.5, 7.0, 1.1)
	b.crate_stack(25.5, 7.0, 1.1)
	b.town("cooler", 24.5, 3.0, {"solid": .26})
	b.streetlamp(25.5, 2.5, 4.6)


func store() -> void:
	b.room(
		14, 9, 22, 17, "floor_tile", d["store"], {"skin": "office_wall", "light": .82, "roof": 2.6}
	)
	b.gap(13, 15, "w")
	b.gap(23, 16, "e")
	b.fixture(15.2, 10.2, 18.8, 10.8, .95, "counter", "counter_top")
	b.town("powder_shelf", 18.5, 13.5, {"solid": .36})
	b.town("powder_shelf", 21.5, 11.5, {"solid": .36})
	b.town("fridge", 21.5, 9.5, {"solid": .3})
	b.crate_stack(15.5, 16.5)
	b.prop("lamp", 17.5, 12.5)
	b.window_pane(16, 8)
	b.window_pane(19, 8)
	# The loading dock out back, and the alley up onto the pumps.
	b.yard(24, 15, 27, 17, "concrete", d["alley"])
	b.yard(28, 14, 31, 20, "concrete", d["alley"])
	b.town("pallet_stack", 25.5, 15.5, {"solid": .34})
	b.crate_stack(30.5, 18.5)
	b.town("cable_spool", 28.5, 14.5, {"solid": .3})


func south() -> void:
	b.yard(8, 21, 31, 25, "asphalt", d["road"])
	b.paint(8, 23, 31, 23, "shoulder")
	b.town("wreck_sedan", 14.5, 21.8, {"solid": .4})
	b.town("tire_pile", 20.5, 24.5, {"solid": .34})
	b.car(26.0, 22.5, true)
	b.town("mailbox_row", 10.5, 25.5)
	b.streetlamp(18.5, 25.5, 4.4)


func east() -> void:
	b.yard(32, 14, 37, 27, "asphalt", d["lot"])
	b.paint(33, 16, 36, 26, "concrete")
	# The garage bay: from the lot through its back door, out its side onto the pumps.
	b.room(33, 5, 36, 12, "concrete", d["lot"], {"skin": "cinder", "light": .74, "roof": 2.8})
	b.gap(35, 13, "s")
	b.gap(32, 10, "w")
	b.gap(32, 11, "w")
	b.town("engine_stand", 35.5, 6.5, {"solid": .3})
	b.town("tool_chest", 33.5, 11.5, {"solid": .3})
	b.town("tow_truck", 36.5, 27.5, {"solid": .44})
	b.town("engine_hoist", 37.5, 17.5, {"solid": .36})
	b.streetlamp(37.5, 21.5, 4.6)
	b.label("SHOULDER", 3, 14)
	b.label("TRUCK PARKING", 8, 4)
	b.label("A", 29, 8)
	b.label("STORE", 16, 13)
	b.label("ALLEY", 28, 17)
	b.label("FRONTAGE ROAD", 15, 23)
	b.label("GARAGE", 33, 21)
