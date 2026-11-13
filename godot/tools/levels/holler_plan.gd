## Holler Distillery (5v5 map "holler", src/modes/tactical_mode.gd): a
## moonshine operation down a wooded holler, built for search and destroy
## and hostage rescue alike. An original layout, three lanes and two sites:
##
##   south  the LOGGING ROAD, where the attackers start (the rescue box in
##          hostage rescue);
##   west   PINE HOLLOW up through the woods, the west ford across the creek,
##          the SMOKEHOUSE PATH and in at the still house's south doors;
##   mid    the SAWDUST LOT, the footbridge over the creek (the only dry way
##          across), the WOODSHED yard round the woodshed, with A SHORT west
##          to the smokehouse path, B SHORT east to the hog pens, and the
##          CHIMNEY ROAD north to the defenders;
##   east   the BARN ROAD past the hay barn, the east ford, the HOG PENS and
##          through the bottling yard's south gate;
##   north  the FIRE ROAD, where the defenders start, with a door into the
##          still house and a gate into the bottling yard, and an alley off the
##          chimney road to each.
## The creek runs the width of the map: anyone wading it is slowed, so the
## bridge is worth fighting over and a rotation along the water is a gamble.
## Site A is the STILL HOUSE: indoors, copper and mash barrels, four ways in.
## Site B is the BOTTLING YARD: open gravel, jugs, crates and the shine tank.
## The hostages are held on each site.
##
## Built by tools/levels/build_level.gd -- holler. Units are cells; x runs
## east, y south, angles as the player's (0 east, PI/2 south, -PI/2 north).
extends RefCounted

const Builder := preload("res://tools/levels/level_builder.gd")
const W := 56
const H := 64
const N := -PI / 2
const S := PI / 2

var b: Builder
var d := {}


func make() -> Builder:
	b = Builder.new("holler", W, H, "hedgerow")
	b.meta = {
		"title": "HOLLER DISTILLERY",
		"heading": ["HOLLER", "DISTILLERY"],
		"intro": "HOLLER DISTILLERY. FIVE A SIDE. B TO BUY.",
		"score": "music",
		"ambience": "range",
		"layout": 1,
		"sky": "sky",
		"area_sounds": {},
		"tactical":
		{
			"attack_spawns":
			[
				[22.5, 58.5, N],
				[26.5, 58.5, N],
				[30.5, 58.5, N],
				[34.5, 58.5, N],
				[28.5, 60.5, N],
			],
			"defend_spawns":
			[
				[22.5, 4.5, S],
				[25.5, 3.5, S],
				[28.5, 4.5, S],
				[31.5, 3.5, S],
				[34.5, 4.5, S],
			],
			"sites": {"A": [7, 9, 18, 18], "B": [37, 9, 48, 18]},
			"hostages": [[8.5, 9.5], [47.5, 10.5]],
			"rescue": [18, 56, 40, 61],
			"rescue_more": [[10, 37, 16, 41], [37, 37, 44, 41]],
			"routes":
			{
				"A":
				[
					[
						[16.5, 55.5],
						[13.5, 45.5],
						[13.5, 34.5],
						[13.5, 25.5],
						[13.5, 21.0],
						[12.5, 14.5],
					],
					[
						[27.5, 52.5],
						[27.5, 40.5],
						[27.5, 34.5],
						[24.5, 28.5],
						[19.5, 25.5],
						[15.5, 24.5],
						[13.5, 21.0],
						[13.5, 14.5],
					],
				],
				"B":
				[
					[
						[38.5, 54.5],
						[39.5, 45.5],
						[40.5, 34.5],
						[40.5, 26.5],
						[40.5, 21.0],
						[42.5, 13.5],
					],
					[
						[27.5, 52.5],
						[27.5, 40.5],
						[28.5, 34.5],
						[32.5, 29.5],
						[34.5, 25.5],
						[38.5, 22.5],
						[40.5, 21.0],
						[42.5, 13.5],
					],
				],
			},
			"holds":
			{
				"A": [[9.5, 12.5, S * .7], [18.5, 10.5, S * 1.2]],
				"B": [[46.5, 13.5, PI * .72], [37.5, 10.5, S * .8]],
				"mid": [[27.5, 17.5, S]],
			},
		},
	}
	return b


func build(_b) -> Array:
	d["road"] = b.district("LOGGING ROAD", Color(1.04, 1.0, .92))
	d["pines"] = b.district("PINE HOLLOW", Color(.96, 1.02, .94))
	d["creek"] = b.district("THE CREEK", Color(.94, 1.0, 1.04))
	d["smoke"] = b.district("SMOKEHOUSE PATH", Color(1.04, .98, .9))
	d["a"] = b.district("SITE A  STILL HOUSE", Color(1.1, .95, .8))
	d["mid"] = b.district("WOODSHED", Color(1.04, 1.0, .92))
	d["barn"] = b.district("BARN ROAD", Color(1.04, 1.0, .9))
	d["pens"] = b.district("HOG PENS", Color(1.06, 1.0, .9))
	d["b"] = b.district("SITE B  BOTTLING YARD", Color(1.06, 1.0, .9))
	d["fire"] = b.district("FIRE ROAD", Color(1.0, 1.0, 1.04))
	# The woods all round and between the lanes; buildings set in them.
	b.wall(0, 0, W - 1, H - 1, "hedgerow", 3.3)
	b.wall(5, 7, 20, 20, "barn", 3.0, true)
	b.wall(35, 7, 50, 20, "stockyard", 1.8)
	south()
	west()
	creek()
	middle()
	east()
	north()
	return [26.5, 58.5, N]


# ------------------------------------------------------------------ south


func south() -> void:
	b.yard(18, 56, 40, 61, "dirt", d["road"])
	b.paint(18, 58, 40, 59, "gravel")
	b.town("log_pile", 19.5, 60.5, {"solid": .44})
	b.town("log_loader", 39.5, 60.5, {"solid": .44})
	b.prop("pickup_truck_b", 24.5, 61.5)
	b.fixture(23.8, 61.1, 25.2, 61.9, .3, "mill_tin", "tin")
	b.town("axe_stump", 33.5, 61.5, {"solid": .26})
	b.streetlamp(29.5, 61.5, 4.2)


# ------------------------------------------------------------------- west


func west() -> void:
	b.yard(9, 42, 17, 58, "dirt", d["pines"])
	b.paint(12, 42, 14, 58, "gravel")
	# Stands of pine as cover: solid clumps off the trail.
	b.hedge(10, 46, 11, 48, 3.0)
	b.hedge(15, 51, 16, 52, 3.0)
	for at: Vector2 in [Vector2(9.5, 43.5), Vector2(16.5, 44.5), Vector2(9.5, 55.5)]:
		b.prop("tree", at.x, at.y)
	b.town("dead_snag", 16.5, 56.5, {"solid": .26})
	b.yard(9, 21, 17, 29, "dirt", d["smoke"])
	# The smokehouse: a little plank shed to put your back to.
	b.wall(10, 24, 12, 26, "barn", 2.4, true)
	b.town("chicken_coop", 16.5, 28.5, {"solid": .38})
	b.town("wheelbarrow", 15.5, 22.5, {"solid": .26})


# ------------------------------------------------------------------ creek


func creek() -> void:
	# The fords and the creek bed, all of a piece across the map.
	b.yard(9, 30, 17, 41, "grass", d["creek"])
	b.yard(22, 31, 33, 43, "grass", d["creek"])
	b.yard(36, 31, 45, 43, "grass", d["creek"])
	b.yard(9, 33, 45, 36, "creek", d["creek"], {"light": .92})
	# Woods between the fords, north and south of the water.
	b.hedge(18, 30, 21, 32, 3.0)
	b.hedge(18, 37, 21, 43, 3.0)
	b.hedge(34, 30, 35, 32, 3.0)
	b.hedge(34, 37, 35, 43, 3.0)
	# The footbridge: the dry way across, its rails as low cover.
	b.paint(26, 32, 29, 37, "bayou_bridge")
	b.fixture(25.42, 32.1, 25.58, 36.9, .9, "wood", "counter_top")
	b.fixture(30.42, 32.1, 30.58, 36.9, .9, "wood", "counter_top")
	b.town("cypress_knees", 14.5, 35.5)
	b.town("cypress_knees", 41.5, 34.5)
	b.prop("reeds", 10.5, 33.5)
	b.prop("reeds", 44.5, 36.5)
	b.prop("reeds", 22.5, 33.5)
	b.town("pirogue", 37.5, 35.5)
	b.bale(23.5, 40.5)
	b.bale(32.5, 39.5)


# ------------------------------------------------------------------- mid


func middle() -> void:
	b.yard(22, 44, 33, 55, "dirt", d["road"])
	b.paint(25, 44, 30, 55, "mill_grit")
	b.town("sawdust_pile", 23.5, 47.5, {"solid": .42})
	b.town("lumber_stack", 31.5, 51.5, {"solid": .42})
	b.town("saw_blade", 32.5, 45.5)
	b.crate_stack(27.5, 49.5, 1.1)
	# The woodshed yard: the shed in the middle, a way round each side.
	b.yard(22, 21, 33, 30, "dirt", d["mid"])
	b.wall(25, 24, 30, 26, "barn", 2.6, true)
	b.town("log_pile", 23.5, 29.5, {"solid": .42})
	b.town("axe_stump", 32.5, 22.5, {"solid": .26})
	b.crate_stack(31.5, 28.5)
	b.yard(18, 24, 21, 26, "dirt", d["smoke"])
	b.yard(34, 24, 35, 26, "dirt", d["pens"])
	# The chimney road north, and the alleys off it to each site.
	b.yard(25, 7, 30, 20, "gravel", d["fire"])
	b.crate_stack(25.5, 16.5)
	b.town("burn_barrel", 29.5, 11.5, {"solid": .28})
	b.yard(21, 12, 24, 15, "dirt", d["fire"])
	b.yard(31, 12, 35, 15, "dirt", d["fire"])
	b.town("outhouse", 22.5, 12.5, {"solid": .36})


# ------------------------------------------------------------------ east


func east() -> void:
	b.yard(36, 44, 45, 55, "dirt", d["barn"])
	b.paint(38, 44, 40, 55, "gravel")
	# The hay barn, walled and roofed: a block to go round.
	b.wall(42, 47, 45, 51, "barn", 3.2, true)
	b.town("hay_wagon", 37.5, 49.5, {"solid": .44})
	b.bale(44.5, 45.5)
	b.bale(36.5, 53.5)
	b.yard(36, 21, 45, 30, "dirt", d["pens"])
	b.fence(38, 24, 41, 24)
	b.fence(43, 27, 43, 29)
	b.town("doghouse", 44.5, 22.5, {"solid": .32})
	b.prop("hay", 37.5, 28.5)
	b.town("washer", 36.5, 21.5, {"solid": .3})


# ----------------------------------------------------------------- north


func north() -> void:
	b.yard(6, 2, 49, 6, "gravel", d["fire"])
	b.paint(6, 4, 49, 4, "shoulder")
	b.prop("pickup_truck", 19.5, 2.5)
	b.fixture(18.8, 2.1, 20.2, 2.9, .3, "mill_tin", "tin")
	b.prop("pickup_truck_b", 37.5, 2.5)
	b.fixture(36.8, 2.1, 38.2, 2.9, .3, "mill_tin", "tin")
	b.streetlamp(27.5, 2.5, 4.6)
	b.prop("roadsign", 6.5, 2.5)
	# The still house: site A.
	b.room(6, 8, 19, 19, "wood", d["a"], {"skin": "barn", "light": .64, "roof": 2.8})
	b.paint(7, 9, 18, 18, "floor_tile")
	b.paint(8, 10, 17, 17, "wood")
	b.gap(12, 20, "s")
	b.gap(13, 20, "s")
	b.gap(14, 20, "s")
	b.gap(17, 20, "s")
	b.gap(11, 7, "n")
	b.gap(12, 7, "n")
	b.gap(20, 13, "e")
	b.gap(20, 14, "e")
	b.town("still", 10.5, 15.5, {"solid": .44})
	b.town("copper_vat", 15.5, 11.5, {"solid": .44})
	b.town("mash_barrel", 7.5, 12.5, {"solid": .3})
	b.town("mash_barrel", 18.5, 17.5, {"solid": .3})
	b.town("boil_pot", 14.5, 16.5, {"solid": .32})
	b.crate_stack(17.5, 9.5)
	b.prop("lamp", 12.5, 12.5)
	b.window_pane(5, 12)
	b.window_pane(5, 15)
	# The bottling yard: site B, a stock fence round it.
	b.yard(36, 8, 49, 19, "gravel", d["b"])
	b.paint(37, 9, 48, 18, "concrete")
	b.paint(38, 10, 47, 17, "gravel")
	b.gap(39, 20, "s")
	b.gap(40, 20, "s")
	b.gap(41, 20, "s")
	b.gap(43, 7, "n")
	b.gap(44, 7, "n")
	b.gap(45, 7, "n")
	b.town("shine_tank", 44.5, 15.5, {"solid": .46})
	b.town("jug_stack", 39.5, 13.5, {"solid": .36})
	b.town("jug_stack", 47.5, 17.5, {"solid": .36})
	b.town("mash_barrel", 42.5, 10.5, {"solid": .3})
	b.crate_stack(36.5, 17.5, 1.1)
	b.crate_stack(48.5, 13.5)
	b.town("tnt_crate", 37.5, 9.5, {"solid": .3})
	b.streetlamp(42.5, 8.5, 4.4)
	b.label("LOGGING ROAD", 24, 58)
	b.label("PINE HOLLOW", 10, 50)
	b.label("CREEK", 27, 34)
	b.label("WOODSHED", 26, 23)
	b.label("A", 12, 13)
	b.label("B", 42, 13)
	b.label("FIRE ROAD", 24, 4)
	b.label("HOG PENS", 38, 26)
	b.label("BARN ROAD", 37, 46)
