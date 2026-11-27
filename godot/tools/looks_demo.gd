## The looks layer's demo map (pass 16, LOOKS): a 64 x 48 farm built with the
## level builder, then dressed by MapLooks (src/map_kit/map_looks.gd) the way
## a map compiler would: moods by area (the fields at dusk, the barn dark,
## the church still, the woods in holler fog), a creek under the county road
## with a plank bridge, a pond with deep water, a water tower set piece,
## vignettes by theme, and foliage (grass, weeds, scrub, trees, pines, corn
## rows, reeds, cypress). tools/looks_map_check.gd checks it, stress_bench's
## `looks` scenario times it, and map_pictures.gd draws it (looks_frames).
##
##   const Demo := preload("res://tools/looks_demo.gd")
##   LevelData.preview[Demo.ID] = Demo.level(Demo.ID)
extends RefCounted

const Builder := preload("res://tools/levels/level_builder.gd")
const ID := "zz_looks_demo"
const W := 64
const H := 48
## The woods' east edge and the fields' (the mood blend pictures stand
## either side of it, looking the same way).
const WOODS_EDGE := 15


## The built level before its looks (the grids, buildings, folks and loot).
static func bare(id := ID) -> Dictionary:
	var b = Builder.new(id, W, H, "hedgerow")
	var fields: int = b.district("THE BACK FORTY")
	b.yard(1, 1, W - 2, H - 2, "grass", fields)
	# The county road, north to south, a gravel lane off it to the barn.
	b.paint(30, 1, 32, H - 2, "road")
	b.paint(33, 17, 47, 18, "gravel")
	b.paint(16, 17, 29, 17, "dirt")
	# The farmhouse: plaster, a door to the south, a dirt yard before it.
	b.building(
		6, 6, 15, 13, fields, {"wall": "plaster", "windows": 3, "roof": 2.4, "floor": "wood"}
	)
	b.paint(6, 14, 16, 16, "dirt")
	b.door(10, 13, false, {"from": "n"})
	# The barn: red boards, its big doors to the south on the lane.
	b.building(40, 6, 52, 15, fields, {"wall": "barn", "windows": 4, "roof": 3.2, "floor": "dirt"})
	b.door(45, 15, false, {"from": "n", "style": "slide"})
	b.door(46, 15, false, {"from": "n", "style": "slide"})
	# The church: whitewash, its door to the north on the yard.
	b.building(
		42, 31, 52, 40, fields, {"wall": "plaster", "windows": 2, "roof": 3.0, "floor": "wood"}
	)
	b.door(47, 31, false, {"from": "s"})
	b.paint(40, 28, 54, 30, "dirt")
	# A corn field: tilled dirt.
	b.paint(18, 20, 27, 28, "dirt")
	# Folks and loot, a lever by the barn and the truck out by the house.
	b.station("barn_lever", 49.5, 18.5, "THE BARN LIGHTS", "THE BARN LIGHTS ARE ON.")
	b.meta["extraction"] = {"x": 8.5, "y": 18.5, "label": "HIT THE ROAD", "shutdown": "barn_lever"}
	for e: Array in [
		[36.5, 10.5], [44.5, 22.5], [24.5, 33.5], [55.5, 26.5], [9.5, 36.5], [46.5, 36.5]
	]:
		b.enemy("billy", e[0], e[1])
	for p: Array in [
		["shells", 33.5, 40.5], ["rinds", 36.5, 28.5], ["beer", 12.5, 20.5], ["shells", 54.5, 18.5]
	]:
		b.pickup(p[0], p[1], p[2])
	return b.finish([31.5, 45.0, -PI / 2.0])


## What the demo asks of MapLooks (a map source's looks objects would read
## the same). `dense`: twice the foliage, for the speed scenario.
static func looks(dense := false) -> Dictionary:
	var thick := 1.0 if dense else .7
	return {
		"mood": "farm_dusk",
		"areas":
		[
			{"name": "THE BARN", "rect": [41, 7, 51, 14], "mood": "barn_dark"},
			{"name": "THE CHURCH", "rect": [43, 32, 51, 39], "mood": "church_still"},
			{"name": "THE WOODS", "rect": [1, 29, WOODS_EDGE - 1, H - 2], "mood": "holler_fog"},
		],
		"water":
		[
			{
				"type": "creek",
				"id": "creek",
				"points": [[1, 23], [14, 24.5], [26, 22.5], [40, 25], [62, 24]],
				"width": 1.8
			},
			{"type": "pond", "id": "pond", "at": [22.5, 37.5], "radius": 3.7},
			{"type": "trough", "at": [37.0, 12.5], "along": "y", "length": 2},
		],
		"set_pieces": [{"kind": "tower", "id": "tank", "at": [57.5, 13.5], "falls": [1, 3]}],
		"dress":
		[
			{"theme": "farm", "area": [3, 3, 20, 18], "count": 2, "seed": 2},
			{"theme": "junk", "area": [36, 3, 60, 20], "count": 1, "seed": 5},
			{"theme": "church", "area": [38, 27, 56, 44], "count": 1, "seed": 1},
		],
		"foliage":
		[
			{"kind": "tree", "area": [1, 29, WOODS_EDGE - 1, H - 2], "density": 1.0, "seed": 1},
			{"kind": "pine", "area": [1, 29, WOODS_EDGE - 1, H - 2], "density": 1.0, "seed": 2},
			{"kind": "corn", "area": [18, 20, 27, 28], "density": 1.0, "seed": 3, "rows": true},
			{"kind": "reeds", "area": [1, 19, 62, 42], "density": .2, "seed": 4},
			{"kind": "cypress", "area": [17, 32, 28, 43], "density": .5, "seed": 5},
			{"kind": "snag", "area": [1, 29, WOODS_EDGE - 1, H - 2], "density": .4, "seed": 9},
			{"kind": "scrub", "area": [1, 1, 62, 46], "density": .12 * thick, "seed": 6},
			{"kind": "weeds", "area": [1, 1, 62, 46], "density": .1 * thick, "seed": 7},
			{"kind": "grass", "area": [1, 1, 62, 46], "density": .07 * thick, "seed": 8},
		],
	}


## The demo level, dressed. `report` (if given) gets MapLooks' report.
static func level(id := ID, dense := false, report := {}) -> Dictionary:
	var lv := bare(id)
	var done := MapLooks.apply(lv, looks(dense))
	report.merge(done, true)
	return lv
