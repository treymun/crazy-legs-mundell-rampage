## Pine Acres (2v2 TAG TEAM map "pineacres", src/modes/bomb_mode.gd): a
## trailer park at dusk, small and built for two a side and one bomb site.
## An original layout:
##
##   south  the PARK ENTRANCE, where the outlaws start;
##   west   the BACK ROW, a long dirt lane behind a row of trailers, in at the
##          site's west end;
##   middle the COMMON GREEN, round the trailer parked across it, picnic
##          tables and lawn flamingos, onto the site through the gap in the
##          board fence at its east end;
##   east   the WOODPILE and the DOUBLE-WIDE: in its back door, through it and
##          out the front onto the deputies' lane (the flank);
##   north  THE CARPORT, the site, and the deputies' lane east of it, where
##          they start.
## The site is the carport yard: a pickup under the carport, the wash line,
## a washer and a grill, the picnic table.
##
## Built by tools/levels/build_level.gd -- pineacres. Units are cells; x runs
## east, y south, angles as the player's (0 east, PI west, -PI/2 north).
extends RefCounted

const Builder := preload("res://tools/levels/level_builder.gd")
const W := 38
const H := 34
const N := -PI / 2

var b: Builder
var d := {}


func make() -> Builder:
	b = Builder.new("pineacres", W, H, "wood")
	b.meta = {
		"title": "PINE ACRES",
		"heading": ["PINE", "ACRES"],
		"intro": "PINE ACRES. TWO A SIDE. B TO BUY.",
		"score": "music",
		"ambience": "range",
		"layout": 1,
		"sky": "sky",
		"area_sounds": {},
		"tactical":
		{
			"attack_spawns": [[16.5, 29.5, N], [20.5, 29.5, N], [18.5, 30.5, N]],
			"defend_spawns": [[27.5, 4.5, PI], [27.5, 9.5, PI], [29.5, 7.0, PI]],
			"sites": {"A": [10, 4, 22, 10]},
			"hostages": [],
			"rescue": [13, 27, 24, 31],
			"routes":
			{
				"A":
				[
					[[10.5, 28.5], [4.5, 26.5], [4.5, 14.5], [4.5, 6.5], [8.5, 6.5], [13.5, 6.5]],
					[
						[14.5, 25.5],
						[13.5, 20.5],
						[15.5, 15.5],
						[22.0, 15.0],
						[22.0, 12.5],
						[19.5, 8.5]
					],
				],
			},
			"holds":
			{
				"A": [[9.5, 3.0, 2.27], [17.5, 9.0, .9]],
			},
		},
	}
	return b


func build(_b) -> Array:
	d["entrance"] = b.district("PARK ENTRANCE", Color(1.04, 1.0, .92))
	d["back"] = b.district("BACK ROW", Color(1.02, 1.0, .94))
	d["green"] = b.district("COMMON GREEN", Color(1.0, 1.04, .94))
	d["a"] = b.district("SITE A  THE CARPORT", Color(1.08, 1.0, .86))
	d["woodpile"] = b.district("WOODPILE", Color(1.04, .98, .9))
	d["double"] = b.district("THE DOUBLE-WIDE", Color(1.06, 1.0, .9))
	d["lane"] = b.district("DEPUTIES' LANE", Color(1.0, 1.0, 1.04))
	b.wall(0, 0, W - 1, H - 1, "wood", 2.8)
	b.wall(0, 0, W - 1, 1, "hedgerow", 3.4)
	b.wall(0, H - 2, W - 1, H - 1, "hedgerow", 3.4)
	b.wall(0, 0, 1, H - 1, "hedgerow", 3.4)
	b.wall(W - 2, 0, W - 1, H - 1, "hedgerow", 3.4)
	# Rows of trailers between the lanes; the double-wide's shell.
	b.wall(7, 12, 11, 26, "trailer", 2.4)
	b.wall(25, 12, 26, 22, "trailer", 2.4)
	b.wall(26, 14, 34, 22, "trailer", 2.4)
	b.wall(13, 12, 24, 13, "wood", 2.0)
	south()
	west()
	green()
	site()
	east()
	return [18.5, 29.5, N]


func south() -> void:
	b.yard(13, 27, 24, 31, "gravel", d["entrance"])
	b.paint(17, 27, 20, 31, "dirt")
	b.town("mailbox_row", 23.5, 31.5)
	b.prop("roadsign", 13.5, 31.5)
	b.streetlamp(13.5, 27.5, 4.4)
	b.yard(7, 27, 12, 30, "gravel", d["entrance"])
	b.town("wreck_pickup", 9.5, 30.5, {"solid": .4})


func west() -> void:
	b.yard(2, 4, 6, 29, "dirt", d["back"])
	b.town("burn_barrel", 5.5, 25.5, {"solid": .28})
	b.town("tire_stack", 2.5, 19.5, {"solid": .34})
	b.town("doghouse", 5.5, 15.5, {"solid": .32})
	b.town("porch_couch", 2.5, 10.5, {"solid": .34})
	b.town("bathtub", 2.5, 22.5, {"solid": .32})
	b.town("rocker", 6.5, 11.5, {"solid": .26})
	b.town("chicken_coop", 2.5, 27.5, {"solid": .38})
	b.town("lantern_post", 6.5, 8.5, {"solid": .1, "glow": true})
	b.streetlamp(6.5, 20.5, 4.0)
	# In at the site's west end.
	b.yard(7, 5, 7, 7, "dirt", d["a"])


func green() -> void:
	b.yard(12, 14, 24, 26, "grass", d["green"])
	b.paint(12, 14, 15, 26, "dirt")
	b.paint(12, 14, 24, 16, "dirt")
	# A trailer parked across the middle of the green: round it either side.
	b.wall(16, 18, 22, 22, "trailer", 2.4)
	b.town("picnic_table", 14.5, 24.5, {"solid": .36})
	b.town("flamingo", 23.5, 23.5, {"solid": .16})
	b.town("flamingo", 12.5, 17.5, {"solid": .16})
	b.town("grill", 23.5, 18.5, {"solid": .28})
	b.town("camp_chairs", 19.5, 25.0, {"solid": .3})
	b.town("cooler", 12.5, 21.5, {"solid": .26})
	b.town("lantern_post", 15.5, 14.5, {"solid": .1, "glow": true})
	b.town("lantern_post", 23.5, 21.5, {"solid": .1, "glow": true})
	b.streetlamp(23.5, 25.5, 4.4)
	# The gap in the board fence onto the carport, at the green's east end.
	b.yard(21, 12, 23, 13, "dirt", d["a"])


func site() -> void:
	b.yard(8, 2, 24, 11, "concrete", d["a"])
	b.paint(11, 5, 21, 9, "gravel")
	b.prop("pickup_truck", 12.5, 3.5)
	b.fixture(11.8, 3.1, 13.2, 3.9, .3, "mill_tin", "tin")
	b.town("laundry", 17.5, 4.5, {"solid": .2})
	b.town("washer", 8.5, 10.5, {"solid": .3})
	b.town("picnic_table", 11.5, 9.5, {"solid": .36})
	# Crates stacked head high: the west corner hidden from the fence gap, the
	# gap's corner from the west end.
	b.crate_stack(12.5, 4.6, 1.1)
	b.crate_stack(12.5, 5.5, 1.1)
	b.crate_stack(15.0, 7.5, 1.1)
	b.crate_stack(15.0, 8.5, 1.1)
	b.town("grill", 22.5, 3.5, {"solid": .28})
	b.crate_stack(19.5, 9.5)
	b.town("cooler", 10.5, 6.0, {"solid": .26})
	b.streetlamp(8.5, 2.5, 4.6)


func east() -> void:
	b.yard(25, 23, 34, 30, "dirt", d["woodpile"])
	b.town("log_pile", 28.5, 26.5, {"solid": .4})
	b.town("axe_stump", 32.5, 28.5, {"solid": .26})
	b.town("wheelbarrow", 26.5, 29.5, {"solid": .28})
	b.town("truck_blocks", 33.5, 24.5, {"solid": .4})
	b.town("port_a_john", 25.5, 23.5, {"solid": .36})
	# The double-wide: in its back door, out its front.
	b.room(
		27,
		15,
		33,
		21,
		"floor_tile",
		d["double"],
		{"skin": "office_wall", "light": .78, "roof": 2.3}
	)
	b.gap(30, 22, "s")
	b.gap(30, 14, "n")
	b.town("porch_couch", 28.5, 17.5, {"solid": .34})
	b.town("fridge", 32.5, 15.5, {"solid": .3})
	b.fixture(31.2, 19.2, 32.8, 20.8, .8, "counter", "counter_top")
	b.prop("lamp", 29.5, 18.5)
	b.window_pane(28, 22)
	b.window_pane(32, 22)
	# The deputies' lane, from their start down to the double-wide's front.
	b.yard(25, 2, 35, 13, "gravel", d["lane"])
	b.paint(28, 2, 33, 13, "asphalt")
	b.town("tow_truck", 35.5, 12.5, {"solid": .44})
	b.town("wreck_sedan", 26.5, 2.5, {"solid": .4})
	b.town("doghouse", 34.5, 9.5, {"solid": .32})
	b.town("flamingo", 26.5, 12.5, {"solid": .16})
	b.town("propane_tank", 35.5, 2.5, {"solid": .34})
	b.streetlamp(35.5, 7.5, 4.6)
	# A row of trailers between the carport and the lane, two ways through.
	b.wall(24, 2, 25, 11, "trailer", 2.4)
	b.yard(24, 4, 25, 5, "concrete", d["a"])
	b.yard(24, 9, 25, 10, "concrete", d["a"])
	b.label("ENTRANCE", 16, 29)
	b.label("BACK ROW", 2, 18)
	b.label("GREEN", 16, 20)
	b.label("A", 15, 7)
	b.label("DOUBLE-WIDE", 27, 18)
	b.label("WOODPILE", 27, 26)
	b.label("LANE", 29, 6)
