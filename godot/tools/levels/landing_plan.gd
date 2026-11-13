## Catfish Landing (2v2 TAG TEAM map "landing", src/modes/bomb_mode.gd): a
## bait shop and boat dock on the river at dusk, small and built for two a
## side and one bomb site. An original layout:
##
##   north-west the GRAVEL LOT, where the outlaws start, and the SHOP PORCH;
##   west/south the BANK PATH, the long way down the bank and along the
##              water onto the dock from the west;
##   middle     the BAIT SHOP: in at its front door, through the tanks and
##              coolers, out the side to the CLEANING SHED and down onto the
##              dock;
##   north      ICE HOUSE ROW, round to the deputies' office (the flank);
##   east       the MARINA OFFICE lot, where the deputies start, straight
##              down onto the dock or across through the shed.
## The site is THE DOCK: planks over the water, boats tied up, bait tanks, the
## net rack, crawfish traps; the water off its east end slows anyone in it.
##
## Built by tools/levels/build_level.gd -- landing. Units are cells; x runs
## east, y south, angles as the player's (0 east, PI west, -PI/2 north).
extends RefCounted

const Builder := preload("res://tools/levels/level_builder.gd")
const W := 40
const H := 30
const S := PI / 2

var b: Builder
var d := {}


func make() -> Builder:
	b = Builder.new("landing", W, H, "bayou_shack")
	b.meta = {
		"title": "CATFISH LANDING",
		"heading": ["CATFISH", "LANDING"],
		"intro": "CATFISH LANDING. TWO A SIDE. B TO BUY.",
		"score": "music",
		"ambience": "range",
		"layout": 1,
		"sky": "sky",
		"area_sounds": {},
		"tactical":
		{
			"attack_spawns": [[4.5, 4.5, 0.0], [7.5, 4.5, 0.0], [5.5, 6.5, 0.0]],
			"defend_spawns": [[33.5, 6.5, S], [35.5, 8.0, S], [33.5, 9.5, S]],
			"sites": {"A": [26, 19, 34, 27]},
			"hostages": [],
			"rescue": [2, 2, 10, 8],
			"routes":
			{
				"A":
				[
					[
						[4.5, 9.5],
						[4.5, 20.5],
						[5.5, 25.5],
						[14.5, 25.5],
						[22.5, 25.5],
						[28.5, 23.5]
					],
					[
						[15.5, 7.5],
						[16.5, 10.5],
						[17.5, 14.5],
						[22.5, 15.5],
						[25.5, 15.5],
						[26.5, 19.5],
						[29.5, 21.5]
					],
				],
			},
			"holds":
			{
				"A": [[33.5, 23.5, 2.91], [31.5, 19.5, -2.82]],
				"mid": [[30.5, 14.5, PI]],
			},
		},
	}
	return b


func build(_b) -> Array:
	d["lot"] = b.district("GRAVEL LOT", Color(1.04, 1.0, .92))
	d["porch"] = b.district("SHOP PORCH", Color(1.04, 1.0, .9))
	d["bank"] = b.district("BANK PATH", Color(1.0, 1.02, .96))
	d["shop"] = b.district("BAIT SHOP", Color(1.06, 1.0, .9))
	d["shed"] = b.district("CLEANING SHED", Color(1.02, 1.0, .94))
	d["a"] = b.district("SITE A  THE DOCK", Color(1.04, 1.0, .9))
	d["ice"] = b.district("ICE HOUSE ROW", Color(1.0, 1.0, 1.02))
	d["office"] = b.district("MARINA OFFICE", Color(1.0, 1.0, 1.04))
	b.wall(0, 0, W - 1, H - 1, "bayou_shack", 3.0)
	b.wall(0, 0, W - 1, 1, "bayou_cypress", 3.6)
	b.wall(0, H - 2, W - 1, H - 1, "bayou_cypress", 3.6)
	b.wall(0, 0, 1, H - 1, "bayou_cypress", 3.6)
	b.wall(W - 2, 0, W - 1, H - 1, "bayou_cypress", 3.6)
	b.wall(11, 9, 22, 19, "bayou_tin", 3.0, true)
	north()
	bank()
	shop()
	dock()
	east()
	return [5.5, 5.0, 0.0]


func north() -> void:
	b.yard(2, 2, 10, 8, "fair_gravel", d["lot"])
	b.prop("pickup_truck", 2.5, 2.5)
	b.fixture(1.8, 2.1, 3.2, 2.9, .3, "mill_tin", "tin")
	b.town("outboard_stand", 9.5, 7.5, {"solid": .3})
	b.streetlamp(10.5, 2.5, 4.4)
	b.yard(11, 2, 22, 8, "bayou_planks", d["porch"])
	b.town("bait_cooler_rack", 13.5, 2.5, {"solid": .34})
	b.town("ice_chest", 19.5, 8.5, {"solid": .3})
	b.town("camp_chairs", 21.5, 3.5, {"solid": .3})
	b.prop("roadsign", 11.5, 8.5)
	# Ice house row: round the top to the office.
	b.yard(23, 2, 28, 5, "fair_gravel", d["ice"])
	b.town("generator", 25.5, 2.5, {"solid": .34})
	b.crate_stack(27.5, 5.0)


func bank() -> void:
	b.yard(2, 9, 6, 27, "bayou_mud", d["bank"])
	b.yard(7, 24, 24, 27, "bayou_mud", d["bank"])
	b.yard(7, 27, 24, 27, "creek", d["bank"], {"light": .92})
	b.town("crawfish_traps", 5.5, 13.5, {"solid": .32})
	b.town("pirogue", 2.5, 18.5, {"solid": .3})
	b.town("net_rack", 12.5, 24.5, {"solid": .32})
	b.town("skiff", 19.5, 25.0, {"solid": .38})
	b.prop("reeds", 7.5, 26.5)
	b.town("lantern_post", 6.5, 15.5, {"solid": .1, "glow": true})
	b.town("lantern_post", 16.5, 23.5, {"solid": .1, "glow": true})
	b.town("cooler", 2.5, 24.5, {"solid": .26})
	b.town("heron", 22.5, 27.0, {"solid": .16})
	b.prop("reeds", 23.5, 26.5)
	b.streetlamp(6.5, 23.5, 4.2)


func shop() -> void:
	b.room(12, 10, 21, 18, "wood", d["shop"], {"skin": "bayou_planks", "light": .76, "roof": 2.6})
	b.gap(16, 9, "n")
	b.gap(17, 9, "n")
	b.gap(22, 15, "e")
	b.town("bait_tank", 14.5, 12.5, {"solid": .36})
	b.town("bait_tank", 14.5, 16.5, {"solid": .36})
	b.town("cooler", 19.5, 11.5, {"solid": .26})
	b.fixture(18.2, 16.2, 20.8, 16.8, .95, "counter", "counter_top")
	b.town("fridge", 20.5, 10.5, {"solid": .3})
	b.prop("lamp", 17.5, 13.5)
	b.window_pane(11, 13)
	b.window_pane(11, 16)
	# The cleaning shed out the side, down onto the dock.
	b.yard(23, 12, 27, 18, "concrete", d["shed"])
	b.town("boil_table", 24.5, 13.5, {"solid": .34})
	b.town("lantern_post", 27.5, 12.5, {"solid": .1, "glow": true})
	b.town("ice_chest", 26.5, 17.0, {"solid": .3})


func dock() -> void:
	b.yard(25, 19, 37, 27, "bayou_planks", d["a"])
	b.yard(35, 19, 37, 27, "creek", d["a"], {"light": .92})
	b.yard(25, 27, 34, 27, "creek", d["a"], {"light": .92})
	b.town("airboat", 31.5, 24.5, {"solid": .44})
	b.town("skiff", 36.0, 21.5, {"solid": .38})
	b.town("bait_tank", 27.5, 21.5, {"solid": .36})
	b.town("marina_pump", 33.5, 19.5, {"solid": .3})
	b.town("net_rack", 29.5, 26.0, {"solid": .32})
	b.crate_stack(26.5, 25.5)
	b.streetlamp(34.5, 26.5, 4.6)
	b.town("lantern_post", 25.5, 19.5, {"solid": .1, "glow": true})
	b.town("crawfish_traps", 33.5, 21.5, {"solid": .32})
	b.town("outboard_stand", 28.5, 19.5, {"solid": .3})


func east() -> void:
	b.yard(29, 2, 37, 17, "fair_gravel", d["office"])
	b.paint(31, 4, 36, 15, "asphalt")
	b.town("tow_truck", 36.5, 2.5, {"solid": .44})
	b.town("propane_tank", 29.5, 2.5, {"solid": .34})
	b.town("picnic_table", 35.5, 12.5, {"solid": .36})
	b.town("bait_cooler_rack", 37.5, 6.5, {"solid": .34})
	b.town("skiff", 30.5, 9.5, {"solid": .38})
	b.streetlamp(37.5, 9.5, 4.6)
	# Across to the cleaning shed.
	b.yard(28, 13, 28, 15, "concrete", d["shed"])
	b.label("LOT", 4, 5)
	b.label("PORCH", 14, 5)
	b.label("BANK", 2, 16)
	b.label("SHOP", 15, 14)
	b.label("SHED", 23, 15)
	b.label("A", 30, 22)
	b.label("OFFICE", 32, 9)
	b.label("ICE ROW", 23, 3)
