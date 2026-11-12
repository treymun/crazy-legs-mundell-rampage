## The Hickston Incident, rebuilt (layout 2): a dusk-lit nowhere town twice
## the old one's length. The road in from the Crossroads runs east past the
## GAS-N-GUT and the bait shop to Main Street; Stanky's back office has the
## brass key; the farm lane leads to the feed barn it opens, the barn to the
## livestock lots and the stock registry, where the steel key opens the gate
## into the corn: a maze with a fresh crop circle in it, and past it the north
## pasture, the saucer's crash site, the alien sheriff, Jerry, and Bessie.
## Off the way: the dry creek and orchard, the salvage yard, the chapel, the
## feed store, the trailer court, the hog pen and the packing shed.
##
## Built by tools/levels/build_level.gd -- hickston.
extends RefCounted

const Builder := preload("res://tools/levels/level_builder.gd")
const Cast := preload("res://tools/levels/hickston_cast.gd")
const W := 150
const H := 78

var b: Builder
# Districts
var road: int
var stankys: int
var restroom: int
var supply: int
var barn: int
var hogpen: int
var packing: int
var office: int
var trailers: int
var creek: int
var pasture: int
var main_street: int
var gas: int
var lots: int
var registry: int
var chapel: int
var feed_store: int
var bait: int
var lane: int
var junk: int
var orchard: int
var kitchen: int
var corn: int


func make() -> Builder:
	b = Builder.new("hickston", W, H, "hedgerow")
	b.meta = {
		"title": "THE HICKSTON INCIDENT",
		"heading": ["BESSIE'S", "COMIN' HOME"],
		"intro": "BRASS KEY: STANKY'S BACK OFFICE",
		"ending": '"NEXT TIME, TAKE THE TRACTOR."',
		"score": "music",
		"rescue": true,
		"layout": 2,
		"sky": "sky",
	}
	return b


func build(_b) -> Array:
	districts()
	b.wall(127, 1, W - 2, H - 2, "corn", 2.3)
	county_road()
	creek_and_orchard()
	farm_lane()
	salvage_yard()
	stankys_bar()
	main_street_block()
	feed_store_block()
	chapel_block()
	gas_station()
	bait_shop()
	trailer_court()
	packing_shed_and_hog_pen()
	feed_barn()
	livestock_lots()
	stock_registry()
	corn_maze()
	north_pasture()
	dressing()
	town_detail()
	more_detail()
	story()
	polish()
	return [7.5, 69.5, 0.0]


func districts() -> void:
	road = b.district("COUNTY ROAD", Color(.87, .94, 1.06))
	stankys = b.district("STANKY'S BAR & GRILL", Color(1.05, .97, .83))
	restroom = b.district("RESTROOM", Color(.92, 1.03, 1.03))
	supply = b.district("SUPPLY ROOM", Color(1.04, .95, .79))
	barn = b.district("FEED BARN", Color(1.03, .93, .82))
	hogpen = b.district("HOG PEN", Color(.88, .94, 1.04))
	packing = b.district("PACKING SHED", Color(.83, .98, .91))
	office = b.district("DISPATCH OFFICE", Color(1.09, 1, .86))
	trailers = b.district("LAZY 8 TRAILER COURT", Color(1.05, .98, .88))
	creek = b.district("DRY CREEK", Color(.88, 1.02, .96))
	pasture = b.district("NORTH PASTURE", Color(.91, .97, 1.04))
	main_street = b.district("MAIN STREET", Color(1.03, 1, .91))
	gas = b.district("GAS-N-GUT", Color(1.06, 1, .86))
	lots = b.district("LIVESTOCK LOTS", Color(1.1, 1.01, .89))
	registry = b.district("STOCK REGISTRY", Color(.97, 1.06, .96))
	chapel = b.district("OPEN ROAD CHAPEL", Color(.95, .95, 1.05))
	feed_store = b.district("FEED & SEED", Color(1.04, .98, .86))
	bait = b.district("BAIT & AMMO", Color(.92, 1, 1.04))
	lane = b.district("FARM LANE", Color(1, .98, .92))
	junk = b.district("SALVAGE YARD", Color(1.02, .96, .9))
	orchard = b.district("ORCHARD", Color(.9, 1.04, .94))
	kitchen = b.district("GRILL KITCHEN", Color(1.08, .98, .84))
	corn = b.district("CORN MAZE", Color(.92, 1.04, .9))


# ----------------------------------------------------------------- helpers


func fence(x0: int, y0: int, x1: int, y1: int, top := 1.24) -> void:
	b.wall(x0, y0, x1, y1, "stockyard", top)


func hedge(x0: int, y0: int, x1: int, y1: int, top := 1.48) -> void:
	b.wall(x0, y0, x1, y1, "hedgerow", top)


## A post-and-beam gate over a way through: two posts, a sign board between
## them (front `face`, back `back`) and a beam on top.
func arch(cx: float, y: float, width: float, face: String, back := "stockyard") -> void:
	var l := cx - width * .5
	var r := cx + width * .5
	b.fixture(l - .17, y - .17, l + .17, y + .17, 2.37, "stockyard", "counter_top")
	b.fixture(r - .17, y - .17, r + .17, y + .17, 2.37, "stockyard", "counter_top")
	b.panel(l + .17, y, r - .17, y, face, 1.83, 2.34, 1.29)
	b.panel(r - .17, y + .035, l + .17, y + .035, back, 1.83, 2.34, .86)
	b.panel(l + .17, y, r - .17, y, "stockyard", 2.34, 2.53, 1.08)


## A street lamp: a lit lamp head on a post and a pool of light under it.
func streetlamp(x: float, y: float) -> void:
	b.board("hub_lamp", x, y, 2.52, {"glow": true})
	b.glow(x, y, 4.2, .3)


## Utility poles along a line with the wires strung between them.
func poles(points: Array) -> void:
	for i in points.size():
		var p: Vector2 = points[i]
		b.prop("utilitypole", p.x, p.y)
		if i > 0:
			var q: Vector2 = points[i - 1]
			b.cable(q.x, q.y, p.x, p.y, 3.3)


## An old car body, rusting: a low box with a cab on it.
func car(x: float, y: float, along_x: bool, side := "mill_tin") -> void:
	b.car(x, y, along_x, side)


func table(x0: float, y0: float, x1: float, y1: float, top := .62) -> void:
	b.fixture(x0, y0, x1, y1, top, "wood", "counter_top")


## Small pieces stand in the middle of a cell, so paths go round them
## (level_builder.gd checks no piece cuts between two open cells).
func tombstone(x: float, y: float) -> void:
	var kind: String = ["a", "b", "c"][int(floorf(x) * 7.0 + floorf(y) * 3.0) % 3]
	b.town("tombstone_" + kind, x, y, {"solid": .22, "base": "concrete"})


func hay_bale(x: float, y: float) -> void:
	var c := Vector2(floorf(x) + .5, floorf(y) + .5)
	b.fixture(c.x - .42, c.y - .3, c.x + .42, c.y + .3, .62, "feed", "counter_top")


func trough(x0: float, y0: float, x1: float, y1: float) -> void:
	b.fixture(x0, y0, x1, y1, .45, "tin", "creek")


func scatter(name: String, spots: Array) -> void:
	for p: Vector2 in spots:
		b.prop(name, p.x, p.y)


## A trailer home: 8 by 4 cells, windows along the sides, a door on the
## long side facing `door_side` (s or n).
func trailer(x0: int, y0: int, door_side: String) -> void:
	b.building(
		x0,
		y0,
		x0 + 7,
		y0 + 3,
		trailers,
		{"wall": "trailer", "roof": 2.0, "parapet": .12, "floor": "floor_tile", "light": .66}
	)
	for x in [x0 + 2, x0 + 5]:
		b.wall(x, y0, x, y0, "trailer_window", 2.12)
		b.wall(x, y0 + 3, x, y0 + 3, "trailer_window", 2.12)
	var dy := y0 + 3 if door_side == "s" else y0
	b.door(x0 + 3, dy, false, {"from": "n" if door_side == "s" else "s", "style": "slide"})
	b.prop("lamp", x0 + 4.5, y0 + 1.5)


# ------------------------------------------------------------------- areas


func county_road() -> void:
	b.yard(1, 63, 126, 74, "gravel", road)
	b.paint(1, 64, 126, 65, "shoulder")
	b.paint(1, 66, 126, 70, "asphalt")
	b.paint(1, 71, 126, 72, "shoulder")
	# The verge along the south side.
	b.paint(1, 73, 126, 74, "grass")
	hedge(1, 75, 126, 75)
	# The county line road south, to the Crossroads gate.
	b.yard(4, 73, 9, 76, "tracks", road)
	b.paint(4, 76, 9, 76, "route_threshold")
	arch(7.0, 76.4, 3.25, "route_hub")
	b.board("hub_road_stake", 9.6, 75.4, .97, {"plane": PI, "back": "hub_road_stake_back"})
	# Mundell's truck, nose in the ditch, and how it got there.
	b.prop("pickup_truck_b", 12.05, 73.45)
	b.mark("detail_wear_oil", 11.0, 72.2, .4, 1.4, .5)
	b.mark("detail_wear_grain", 14.5, 70.5, -.2, 2.2, .3)
	b.board("prop_tire", 9.8, 73.8, .49)
	# Oil, tracks and patches all down the road.
	for k in 14:
		var x := 6.0 + k * 8.7 + b.rng.randf() * 3.0
		b.mark(
			"detail_wear_oil" if k % 3 else "detail_wear_grain",
			x,
			66.5 + b.rng.randf() * 4.0,
			b.rng.randf() * 3.0,
			1.0 + b.rng.randf(),
			.4
		)
	b.paint(36, 67, 41, 69, "oil_asphalt")
	b.paint(88, 66, 92, 67, "oil_asphalt")
	poles(
		[
			Vector2(3.5, 63.5),
			Vector2(17.5, 63.5),
			Vector2(31.5, 63.5),
			Vector2(45.5, 63.5),
			Vector2(67.5, 63.5),
			Vector2(81.5, 63.5),
			Vector2(95.5, 63.5),
			Vector2(109.5, 63.5),
			Vector2(123.5, 63.5),
		]
	)
	b.prop("roadsign", 52.5, 64.2)
	# The town line, facing the way Mundell drove in.
	b.board("town_line_sign", 14.0, 64.6, .86, {"z": 1.05, "plane": PI / 2})
	b.fixture(13.95, 64.05, 14.05, 64.15, 1.1, "wood", "wood")
	b.fixture(13.95, 65.05, 14.05, 65.15, 1.1, "wood", "wood")
	b.prop("mailbox", 99.6, 63.4)
	scatter("reeds", [Vector2(16, 74.4), Vector2(33, 74.5), Vector2(58, 74.3), Vector2(76.7, 73.7)])
	scatter("reeds", [Vector2(101, 74.4), Vector2(118, 74.5)])
	scatter("tire", [Vector2(70.4, 73.8), Vector2(113.6, 64.4)])
	# The east end: the road closed by a jackknifed stock trailer.
	b.fixture(119.2, 64.4, 121.0, 73.6, 1.36, "stockyard", "tin")
	b.fixture(121.0, 65.5, 126.9, 66.9, 1.5, "tin", "tin")
	b.board("service_detour", 117.8, 68.5, .94, {"plane": -PI / 2})
	streetlamp(12.5, 64.2)
	streetlamp(52.0, 71.8)
	streetlamp(86.0, 64.2)


func creek_and_orchard() -> void:
	b.yard(1, 1, 12, 62, "grass", creek)
	# The bed: a dry channel with its banks, under the road at the culvert.
	for y in range(1, 63):
		var wobble := int(round(sin(y * .23) * 1.2))
		b.paint(4 + wobble, y, 9 + wobble, y, "dirt")
		b.raise(4 + wobble, y, 4 + wobble, y, -.12)
		b.raise(9 + wobble, y, 9 + wobble, y, -.12)
		b.paint(5 + wobble, y, 8 + wobble, y, "creek")
		b.raise(5 + wobble, y, 8 + wobble, y, -.24)
	b.raise(1, 63, 12, 63, -.12)
	b.paint(1, 63, 12, 63, "dirt")
	# The culvert under the road is grated: the creek is reached from the lane,
	# the salvage yard and the orchard.
	b.wall(1, 62, 12, 62, "steel_mesh", 1.0)
	# The lane's plank bridge.
	b.paint(1, 23, 12, 28, "wood")
	b.raise(1, 23, 12, 28, 0.0)
	b.fixture(3.0, 22.43, 11.0, 22.57, .92, "wood", "wood")
	b.fixture(3.0, 29.43, 11.0, 29.57, .92, "wood", "wood")
	# The orchard: rows of fruit trees by the windmill.
	b.yard(13, 1, 24, 21, "orchard", orchard)
	hedge(13, 22, 24, 22)
	b.yard(18, 22, 19, 22, "tracks", orchard)
	for y in [3.5, 7.5, 11.5, 15.5, 19.5]:
		for x in [14.5, 18.0, 21.5]:
			b.prop("tree" if int(x + y) % 2 else "tree_b", x + (y * .37 - floorf(y * .37)) * .6, y)
	b.prop("windmill", 23.2, 2.4)
	b.prop("water_tower", 2.8, 3.2)
	for k in 22:
		# Not on the footbridge's rail (y 29.5).
		b.prop("reeds", 4.8 + b.rng.randf() * 4.5, 2.0 + k * 2.75 + (.6 if k == 10 else 0.0))
	for k in 9:
		b.prop("tree_b" if k % 2 else "tree", 11.5 if k % 2 else 2.4, 6.0 + k * 6.6)
	b.board("prop_hay", 16.3, 5.6, .92)
	b.board("split_feed_sacks", 22.5, 12.4, .52, {"z": 0.0})
	b.mark("detail_wear_silt", 6.5, 40.0, 1.5, 2.0, .7)
	b.mark("detail_wear_silt", 7.0, 12.0, 1.4, 2.0, .7)
	b.board("detail_culvert_catch_rack", 6.6, 61.6, .53, {"z": 0.0, "plane": 0.0})


func farm_lane() -> void:
	b.yard(13, 23, 88, 29, "tracks", lane)
	b.paint(13, 23, 88, 23, "grass")
	b.paint(13, 29, 88, 29, "grass")
	# The lane's east end: the registry's yard bar, lifted from the far side.
	fence(89, 23, 89, 29, 1.6)
	var bar: Dictionary = b.door(
		89, 25, true, {"from": "w", "style": "slide", "tile": "gate", "roof": 0.0}
	)
	bar["id"] = "yard-bar"
	b.controlled_doors.append([89, 25])
	poles([Vector2(16.5, 29.4), Vector2(36.5, 29.4), Vector2(56.5, 29.4), Vector2(76.5, 29.4)])
	for k in 8:
		b.mark("detail_wear_grain", 18.0 + k * 9.0, 26.0, .1, 2.6, .35)
	scatter("hay", [Vector2(38.4, 23.6), Vector2(67.6, 23.6)])
	b.board("prop_tire", 33.5, 28.4, .49)
	streetlamp(41.0, 28.6)
	streetlamp(71.0, 28.6)


func salvage_yard() -> void:
	b.yard(13, 31, 28, 47, "gravel", junk)
	fence(13, 30, 28, 30)
	b.yard(19, 30, 20, 30, "tracks", junk)
	fence(13, 31, 13, 48)
	b.yard(13, 39, 13, 40, "dirt", junk)
	hedge(13, 48, 28, 48)
	b.paint(15, 32, 27, 46, "dirt")
	car(16.5, 33.5, true)
	car(16.4, 36.2, true, "tin")
	car(22.5, 34.0, false)
	car(26.6, 37.5, false, "tin")
	car(17.0, 44.6, true)
	car(23.8, 45.3, true, "tin")
	# The school bus nobody finished painting: a long tin hull you can hide behind.
	b.fixture(19.6, 38.8, 25.4, 40.4, .35, "trailer", "tin")
	b.town("school_bus", 22.5, 39.6)
	b.fixture(14.2, 41.0, 15.6, 42.4, 1.1, "crate_side", "counter_top")
	for p in [Vector2(21.0, 42.6), Vector2(21.6, 43.1), Vector2(27.2, 32.0), Vector2(14.6, 46.6)]:
		b.board("prop_tire", p.x, p.y, .49)
	scatter("tire", [Vector2(18.7, 42.8), Vector2(27.4, 42.4), Vector2(15.0, 38.6)])
	scatter("barrel", [Vector2(27.4, 46.4), Vector2(27.6, 33.6)])
	b.board("wing_town_tires", 14.04, 35.0, .74, {"z": .8, "plane": -PI / 2})
	b.board("wing_town_tow", 19.5, 30.95, .66, {"z": .6, "plane": 0.0})
	b.board("salvage_sign", 16.4, 29.96, .58, {"z": .45, "plane": PI})
	b.board("detail_tow_spool", 26.0, 44.0, .62)
	b.mark("detail_wear_oil", 21.0, 36.5, .3, 1.6, .6)
	b.mark("detail_wear_oil", 18.5, 40.5, 1.1, 1.3, .5)
	streetlamp(20.0, 47.2)


func stankys_bar() -> void:
	b.building(
		29,
		30,
		53,
		47,
		stankys,
		{
			"wall": "wood",
			"roof": 2.25,
			"floor": "porch",
			"windows": 0,
			"light": .72,
			"skin": "detail_wall_bar_wainscot"
		}
	)
	# Inside walls: the west wing (office, supply, restroom) and the kitchen.
	b.wall(39, 31, 39, 46, "wood", 2.53)
	b.wall(30, 37, 38, 37, "wood", 2.53)
	b.wall(30, 42, 38, 42, "wood", 2.53)
	b.wall(40, 36, 52, 36, "wood", 2.53)
	b.room(30, 31, 38, 36, "porch", office, {"roof": 2.25, "skin": "office_wall", "light": .8})
	b.room(30, 38, 35, 41, "concrete", supply, {"roof": 2.25, "skin": "shelves", "light": .62})
	b.room(37, 38, 38, 41, "concrete", supply, {"roof": 2.25, "skin": "crate_side", "light": .5})
	b.wall(36, 38, 36, 41, "shelves", 2.53)
	b.room(30, 43, 38, 46, "tile", restroom, {"roof": 2.25, "skin": "restroom", "light": .76})
	b.room(40, 31, 52, 35, "floor_tile", kitchen, {"roof": 2.25, "skin": "cinder", "light": .8})
	# The facade on Main Street: the bar's signs and windows.
	b.wall(53, 33, 53, 33, "tavern", 2.53)
	b.wall(53, 37, 53, 37, "window", 2.53)
	b.wall(53, 39, 53, 39, "liquor", 2.53)
	b.wall(53, 45, 53, 45, "eat", 2.53)
	b.wall(53, 46, 53, 46, "window", 2.53)
	b.panel(54.04, 46.6, 54.04, 35.6, "stanky_marquee", 2.24, 2.8, 1.21)
	b.set_skin(34, 31, 34, 31, "dispatch")
	b.set_skin(30, 44, 30, 45, "mirror")
	b.wall(29, 44, 29, 45, "mirror", 2.53)
	b.set_skin(28, 44, 28, 45, "wood")
	b.meta["mirror"] = [30, 44, 30, 46]
	b.set_skin(40, 38, 40, 44, "shelves")
	b.set_skin(45, 31, 47, 31, "service")
	# Doors.
	b.door(53, 42, true, {"from": "w", "id": "front"})
	b.door(47, 30, false, {"from": "s", "id": "kitchen-back"})
	b.door(29, 40, true, {"from": "e", "id": "supply-back"})
	b.door(46, 36, false, {"from": "s", "id": "kitchen"})
	b.door(39, 33, true, {"from": "w", "id": "office"})
	b.door(39, 45, true, {"from": "w", "id": "restroom"})
	b.secret(36, 40, true, [37, 38, 38, 41], {"from": "w", "tile": "shelves"})
	# The bar.
	b.fixture(41.2, 37.6, 42.0, 44.9, .77, "counter", "counter_top")
	b.fixture(41.2, 44.9, 43.6, 45.5, .77, "counter", "counter_top")
	table(45.6, 39.4, 46.6, 40.4)
	table(49.4, 39.2, 50.4, 40.2)
	table(45.4, 43.6, 46.4, 44.6)
	b.fixture(48.6, 42.6, 50.9, 43.8, .74, "wood", "counter_top")
	b.raise(50, 45, 52, 46, .24)
	b.board("detail_bar_backstock", 40.2, 41.0, .52, {"z": .78, "plane": -PI / 2})
	b.board("wing_town_register", 41.6, 38.4, .72, {"z": .98, "plane": -PI / 2})
	b.board("story_food", 45.9, 44.1, .27, {"z": .62})
	b.board("wanted_poster", 52.92, 41.0, .6, {"z": 1.1, "plane": PI / 2})
	b.react("tv", 41.6, 37.8, .75, {"z": .77, "id": "bar-tv"})
	b.react("jukebox", 52.4, 37.6, 1.4, {"id": "jukebox", "radius": .3})
	b.react("bottles", 41.6, 42.4, .42, {"z": .77, "id": "bar-bottles"})
	b.react("cans", 46.1, 39.9, .4, {"z": .62, "id": "bar-cans"})
	b.meta["devices"] = [["jukebox", 52.4, 37.6], ["sink", 30.4, 44.5]]
	for p in [Vector2(43.5, 39.0), Vector2(47.5, 42.0), Vector2(51.0, 44.0)]:
		b.prop("lamp", p.x, p.y)
		b.glow(p.x, p.y, 3.0, .18)
	# The kitchen: the grill, the cooler, the fryer.
	b.fixture(40.1, 31.1, 44.4, 31.9, .92, "counter", "counter_top")
	b.fixture(48.6, 31.1, 52.9, 31.9, .92, "counter", "counter_top")
	b.fixture(51.8, 33.0, 52.9, 34.6, 1.85, "tin", "tin")
	b.fixture(43.0, 33.4, 45.6, 34.2, .92, "counter", "counter_top")
	b.react("cans", 43.6, 31.5, .42, {"z": .92, "id": "grill-cans"})
	b.prop("lamp", 46.5, 33.5)
	# The office: the safe, the dispatch desk and radio.
	b.town("safe_open", 30.6, 31.6, {"solid": .36, "base": "tin"})
	b.glow(30.5, 32.5, 1.6, .22)
	table(33.0, 32.8, 35.2, 33.6, .78)
	b.interiors.append(["dispatch", 34.9, 31.05, .78, .59, 0.0])
	b.notes.append(
		[
			34.0,
			33.2,
			"DISPATCH STUB",
			"MUNDELL / YOUR HOG TAG WENT TO THE FAIR. CHECK THE BLUE TRUNK.",
			0.0
		]
	)
	b.board("story_dispatch", 33.6, 33.2, .27, {"z": .78})
	b.board("detail_dispatch_rack", 37.9, 33.5, .54, {"z": .78, "plane": PI / 2})
	b.prop("lamp", 34.5, 34.0)
	b.glow(34.5, 34.0, 3.0, .2)
	# Supply and its stash; the restroom.
	b.fixture(30.2, 38.1, 34.0, 38.8, 1.4, "shelves", "counter_top")
	b.board("prop_crate", 31.0, 41.0, .72)
	b.board("prop_barrel", 35.2, 41.3, 1.03)
	b.fixture(33.4, 43.1, 33.6, 45.2, 1.6, "restroom", "counter_top")
	b.fixture(35.6, 43.1, 35.8, 45.2, 1.6, "restroom", "counter_top")
	b.react("toilet", 34.6, 43.5, .82, {"id": "stall-1"})
	b.react("toilet", 36.8, 43.5, .82, {"id": "stall-2"})
	b.prop("sink", 30.45, 45.6)
	b.prop("lamp", 32.0, 44.5)
	# Out front: the boardwalk and its awning.
	b.room(54, 31, 55, 46, "porch", main_street, {"roof": 2.05, "ceiling": "joists", "light": .95})
	b.raise(54, 31, 55, 46, .12)
	for y in [31.07, 36.0, 41.0, 46.93]:
		b.fixture(55.72, y - .07, 55.86, y + .07, 2.05, "wood", "counter_top", .12)
	b.prop("barrel", 54.5, 34.6)
	b.board("wing_town_radio", 54.08, 44.0, .81, {"z": .9, "plane": -PI / 2})
	# Behind the bar: the kitchen's back step and the grease barrels.
	scatter("barrel", [Vector2(44.2, 29.4), Vector2(45.0, 29.6), Vector2(51.6, 29.5)])
	b.board("detail_town_roadside_kit", 50.5, 29.6, .46, {"plane": PI})


func main_street_block() -> void:
	b.yard(54, 29, 66, 62, "asphalt", main_street)
	b.paint(54, 47, 55, 62, "concrete")
	b.paint(65, 29, 66, 62, "concrete")
	b.raise(65, 30, 66, 62, .12)
	b.raise(54, 47, 55, 62, .12)
	b.paint(59, 30, 60, 62, "oil_asphalt")
	# Re-open the boardwalk the yard painted over.
	b.room(54, 31, 55, 46, "porch", main_street, {"roof": 2.05, "ceiling": "joists", "light": .95})
	b.raise(54, 31, 55, 46, .12)
	b.prop("pickup_truck_b", 57.0, 55.6)
	b.prop("mailbox", 55.2, 50.2)
	scatter("barrel", [Vector2(65.5, 44.6), Vector2(65.6, 45.4)])
	b.board("wing_town_service", 66.4, 52.0, .87, {"z": .2, "plane": PI / 2})
	poles([Vector2(66.5, 31.5), Vector2(66.5, 46.5), Vector2(66.5, 61.5)])
	b.cable(66.5, 46.5, 54.2, 47.4, 3.1)
	streetlamp(56.4, 49.6)
	streetlamp(64.6, 41.4)
	streetlamp(64.6, 57.6)
	streetlamp(57.6, 30.2)
	b.mark("detail_wear_oil", 61.5, 44.0, 1.6, 1.4, .5)
	b.mark("detail_wear_oil", 58.0, 35.0, .2, 1.2, .5)


func feed_store_block() -> void:
	hedge(67, 30, 88, 30)
	b.yard(84, 30, 85, 30, "tracks", feed_store)
	b.building(
		68,
		31,
		80,
		42,
		feed_store,
		{
			"wall": "brick",
			"roof": 2.3,
			"floor": "concrete",
			"windows": 3,
			"light": .7,
			"skin": "feed"
		}
	)
	b.door(68, 36, true, {"from": "e", "id": "feed-front"})
	b.wall(75, 32, 75, 41, "brick", 2.58)
	b.door(75, 38, true, {"from": "w", "id": "feed-back"})
	b.set_skin(69, 32, 74, 41, "office_wall")
	b.set_skin(76, 32, 79, 41, "feed")
	for y in [33.4, 36.4, 39.4]:
		b.fixture(70.6, y, 73.4, y + .6, 1.38, "shelves", "counter_top")
	b.fixture(69.2, 40.4, 71.2, 41.0, .8, "counter", "counter_top")
	b.board("wing_town_feed", 67.94, 39.6, .87, {"z": .63, "plane": -PI / 2})
	b.board("detail_feed_sampler", 70.2, 40.7, .47, {"z": .8})
	for p in [Vector2(77.0, 33.0), Vector2(78.6, 33.4), Vector2(77.4, 40.6), Vector2(79.0, 36.0)]:
		b.board("split_feed_sacks", p.x, p.y, .52)
	b.prop("lamp", 72.0, 37.0)
	b.prop("lamp", 77.5, 37.0)
	# The side yard: the delivery truck, feed on pallets.
	b.yard(81, 31, 88, 43, "gravel", feed_store)
	b.prop("pickup_truck", 85.0, 35.4)
	for p in [Vector2(82.2, 32.0), Vector2(82.6, 33.0), Vector2(87.6, 41.8)]:
		b.board("split_feed_sacks", p.x, p.y, .52)
	scatter("crate", [Vector2(87.4, 32.0), Vector2(82.0, 41.6)])
	b.board("detail_railhead_sacks", 86.8, 38.6, .53)
	fence(89, 30, 89, 47, 1.48)


func chapel_block() -> void:
	b.yard(67, 43, 88, 62, "grass", chapel)
	fence(67, 43, 67, 62, .9)
	b.yard(67, 51, 67, 53, "dirt", chapel)
	b.paint(76, 58, 78, 62, "tracks")
	b.building(
		71,
		45,
		83,
		57,
		chapel,
		{
			"wall": "plaster",
			"roof": 3.0,
			"parapet": .4,
			"floor": "porch",
			"ceiling": "joists",
			"windows": 3,
			"lit": .6,
			"light": .68,
			"skin": "plaster"
		}
	)
	# The steeple over the door.
	b.wall(76, 57, 78, 58, "plaster", 5.4, true)
	b.room(77, 57, 77, 57, "porch", chapel, {"roof": 2.6, "light": .7})
	b.door(77, 58, false, {"from": "n", "id": "chapel-door"})
	# Pews either side of the aisle, the altar on its step.
	for y in [49.3, 51.3, 53.3, 55.0]:
		b.fixture(72.4, y, 76.2, y + .42, .55, "wood", "counter_top")
		b.fixture(77.8, y, 81.6, y + .42, .55, "wood", "counter_top")
	b.raise(74, 46, 79, 47, .24)
	b.paint(74, 46, 79, 47, "floor_tile")
	b.fixture(76.4, 46.2, 77.6, 46.8, 1.15, "wood", "counter_top", .24)
	# The vestry behind the altar: a panel in the plaster.
	b.wall(80, 46, 80, 48, "plaster", 3.4)
	b.wall(81, 48, 82, 48, "plaster", 3.4)
	b.room(81, 46, 82, 47, "porch", chapel, {"roof": 2.4, "light": .5, "skin": "plaster"})
	b.secret(80, 46, true, [81, 46, 82, 47], {"from": "w", "tile": "plaster"})
	b.prop("lamp", 77.0, 48.5)
	b.prop("lamp", 77.0, 53.5)
	b.glow(77.0, 47.0, 3.4, .35)
	b.board("story_aftermath", 75.2, 47.2, .19, {"z": .24})
	# The graveyard: stones in crooked rows, a dead tree, the water tower.
	for p in [
		Vector2(68.6, 45.0),
		Vector2(68.6, 47.4),
		Vector2(68.8, 55.4),
		Vector2(68.6, 58.0),
		Vector2(69.0, 60.6),
		Vector2(85.0, 45.6),
		Vector2(86.6, 45.8),
		Vector2(85.2, 49.0),
		Vector2(86.8, 49.3),
		Vector2(85.4, 52.4),
		Vector2(87.0, 52.6),
		Vector2(85.1, 55.8),
		Vector2(72.0, 60.4),
		Vector2(73.8, 60.6),
		Vector2(80.6, 60.2),
		Vector2(82.4, 60.6),
	]:
		tombstone(p.x, p.y)
	b.prop("tree_b", 86.4, 58.6)
	b.prop("tree", 69.0, 51.0)
	b.prop("water_tower", 86.6, 43.8)
	streetlamp(75.0, 61.5)
	b.board("chapel_sign", 73.0, 63.06, .74, {"z": .5, "plane": 0.0})
	b.fixture(71.95, 62.95, 72.05, 63.05, .6, "wood", "wood")
	b.fixture(73.95, 62.95, 74.05, 63.05, .6, "wood", "wood")


func gas_station() -> void:
	b.yard(14, 49, 37, 62, "concrete", gas)
	fence(13, 49, 13, 62, 1.24)
	b.building(
		15,
		49,
		30,
		55,
		gas,
		{
			"wall": "cinder",
			"roof": 2.2,
			"floor": "floor_tile",
			"windows": 3,
			"lit": .7,
			"light": .82,
			"skin": "plaster"
		}
	)
	b.wall(25, 50, 25, 54, "cinder", 2.48)
	b.door(25, 52, true, {"from": "w", "id": "gas-store-back"})
	b.set_skin(26, 50, 29, 54, "cinder")
	b.door(20, 55, false, {"from": "n", "id": "gas-front"})
	b.door(30, 51, true, {"from": "w", "id": "gas-side", "style": "slide"})
	# The store: the counter, two aisles, the cooler and the TV.
	b.fixture(16.1, 50.1, 18.8, 50.8, .82, "counter", "counter_top")
	b.fixture(20.4, 51.6, 23.6, 52.0, 1.3, "shelves", "counter_top")
	b.fixture(20.4, 53.2, 23.6, 53.6, 1.3, "shelves", "counter_top")
	b.react("vending", 24.4, 50.4, 1.5, {"id": "gas-cooler"})
	b.react("tv", 16.6, 50.4, .75, {"z": .82, "id": "gas-tv"})
	b.react("cans", 21.0, 51.8, .42, {"z": 1.3, "id": "gas-cans"})
	b.board("detail_lost_property_tray", 17.6, 50.5, .4, {"z": .82})
	b.prop("lamp", 18.5, 52.5)
	b.prop("lamp", 22.5, 52.5)
	# The back room: fuel, powder, a crossbow somebody pawned.
	b.board("powder_notice", 27.5, 50.04, .62, {"z": .63, "plane": 0.0})
	b.board("prop_crate", 28.6, 50.6, .72)
	b.prop("lamp", 27.5, 52.5)
	# The canopy over the pumps.
	b.room(17, 57, 30, 60, "concrete", gas, {"roof": 2.45, "ceiling": "tin", "light": 1.05})
	for p in [Vector2(17.2, 57.2), Vector2(29.8, 57.2), Vector2(17.2, 60.8), Vector2(29.8, 60.8)]:
		b.fixture(p.x - .09, p.y - .09, p.x + .09, p.y + .09, 2.45, "tin", "tin")
	b.fixture(19.4, 58.6, 28.6, 59.3, .14, "concrete", "concrete")
	b.prop("pump", 20.6, 58.95)
	b.prop("pump_b", 24.0, 58.95)
	b.prop("pump", 27.4, 58.95)
	b.prop("lamp", 20.0, 58.0)
	b.prop("lamp", 27.0, 58.0)
	b.glow(23.5, 58.8, 5.0, .26)
	# Drums by the side door: shoot them and stand back.
	b.fuel_drums.append([32.2, 50.6])
	b.fuel_drums.append([33.2, 51.3])
	b.fuel_drums.append([32.5, 52.4])
	scatter("tire", [Vector2(36.2, 51.4), Vector2(35.8, 55.6)])
	b.prop("pickup_truck_b", 33.6, 58.4)
	b.mark("detail_wear_oil", 24.0, 61.6, 0.0, 1.8, .6)
	b.mark("detail_wear_oil", 33.0, 56.2, 1.2, 1.2, .5)
	b.board("gas_n_gut_sign", 35.6, 61.4, 1.2, {"z": 1.9, "plane": 0.0, "glow": true})
	b.board("prop_utilitypole", 35.6, 61.5, 3.57)


func bait_shop() -> void:
	b.yard(38, 49, 53, 62, "gravel", bait)
	b.building(
		40,
		50,
		50,
		57,
		bait,
		{"wall": "tin", "roof": 2.15, "floor": "porch", "windows": 4, "light": .7, "skin": "wood"}
	)
	b.door(45, 57, false, {"from": "n", "id": "bait-front"})
	b.fixture(41.1, 51.1, 44.0, 51.8, .82, "counter", "counter_top")
	b.fixture(46.2, 53.4, 49.0, 54.2, .95, "glazing", "creek")
	b.board("wanted_poster", 49.94, 52.4, .6, {"z": 1.0, "plane": PI / 2})
	b.board("detail_tire_patch_bench", 41.1, 55.0, .55, {"z": .0, "plane": -PI / 2})
	b.prop("lamp", 45.0, 53.0)
	b.board("bait_ammo_sign", 45.0, 58.04, .36, {"z": 1.62, "plane": 0.0})
	scatter("barrel", [Vector2(51.4, 50.6), Vector2(52.4, 51.1)])
	b.board("prop_crate", 38.6, 50.0, .72)
	b.board("delivery_plaque", 50.2, 58.04, .57, {"z": 1.0, "plane": 0.0})


func trailer_court() -> void:
	b.yard(90, 48, 126, 62, "gravel", trailers)
	hedge(89, 47, 126, 47)
	fence(89, 48, 89, 62, 1.24)
	b.paint(90, 53, 126, 55, "tracks")
	trailer(92, 49, "s")
	trailer(103, 49, "s")
	trailer(114, 49, "s")
	trailer(92, 56, "n")
	trailer(103, 56, "n")
	trailer(114, 56, "n")
	# The last trailer's back half is walled off, with a loose panel.
	b.wall(119, 57, 119, 58, "trailer", 2.12)
	b.room(120, 57, 120, 58, "floor_tile", trailers, {"roof": 2.0, "light": .5})
	b.secret(119, 58, true, [120, 57, 120, 58], {"from": "w", "tile": "trailer"})
	# Clotheslines, lawn chairs, cinder blocks and the satellite of love.
	for line in [[99.0, 53.0, 102.0, 56.0], [110.0, 53.0, 113.0, 56.0]]:
		b.fixture(line[0] - .06, line[1] - .06, line[0] + .06, line[1] + .06, 1.7, "wood", "wood")
		b.fixture(line[2] - .06, line[3] - .06, line[2] + .06, line[3] + .06, 1.7, "wood", "wood")
		b.panel(line[0], line[1], line[2], line[3], "cable", 1.6, 1.63, .9)
	car(123.4, 54.0, false, "tin")
	b.board("detail_trailer_service", 98.0, 53.0, .49, {"z": .008, "plane": PI})
	scatter("tire", [Vector2(101.4, 61.4), Vector2(112.6, 61.2), Vector2(91.0, 54.6)])
	scatter("barrel", [Vector2(122.4, 49.0), Vector2(100.6, 48.8)])
	b.prop("pickup_truck", 108.7, 54.5)
	b.board("lazy_eight_sign", 96.0, 62.2, 1.0, {"z": 1.2, "plane": 0.0})
	b.fixture(94.7, 62.14, 94.84, 62.28, 1.25, "wood", "wood")
	b.fixture(97.16, 62.14, 97.3, 62.28, 1.25, "wood", "wood")
	streetlamp(101.5, 54.0)
	streetlamp(118.5, 54.0)
	b.mark("detail_wear_oil", 106.0, 61.4, .5, 1.4, .5)


func packing_shed_and_hog_pen() -> void:
	b.building(
		25,
		1,
		38,
		9,
		packing,
		{"wall": "tin", "roof": 2.3, "floor": "concrete", "windows": 4, "light": .66, "skin": "tin"}
	)
	b.door(32, 9, false, {"from": "n", "id": "packing-door", "style": "slide"})
	# The packing line and its dock.
	b.fixture(27.0, 3.4, 34.0, 4.2, .92, "counter", "counter_top")
	b.fixture(27.0, 6.0, 31.0, 6.6, .92, "counter", "counter_top")
	b.raise(35, 2, 37, 8, .24)
	b.paint(35, 2, 37, 8, "porch")
	b.wall(35, 2, 37, 2, "tin", 2.58, true)
	b.room(35, 2, 37, 2, "porch", packing, {"roof": 2.3, "light": .4})
	b.wall(35, 3, 37, 3, "tin", 2.58, true)
	b.secret(36, 3, false, [35, 2, 37, 2], {"from": "s", "tile": "tin"})
	b.board("packing_notice", 26.02, 5.0, .53, {"z": .85, "plane": -PI / 2})
	b.board("detail_shed_tool_tray", 33.0, 3.8, .6, {"z": .92})
	b.board("detail_shed_spare_screen", 37.9, 6.0, .82, {"z": .3, "plane": PI / 2})
	scatter("crate", [Vector2(36.0, 5.2), Vector2(36.6, 6.4)])
	b.prop("lamp", 29.5, 5.0)
	b.prop("lamp", 34.0, 6.0)
	# The hog pen: mud, troughs, the shelter.
	b.yard(26, 10, 38, 21, "dirt", hogpen)
	fence(25, 10, 25, 22)
	fence(26, 22, 39, 22)
	fence(39, 10, 39, 21, 1.24)
	b.yard(39, 15, 39, 15, "dirt", hogpen)
	b.room(26, 18, 30, 21, "dirt", hogpen, {"roof": 1.95, "ceiling": "tin", "light": .7})
	trough(31.2, 12.0, 34.8, 12.5)
	trough(35.6, 17.2, 36.1, 20.0)
	for k in 7:
		b.mark("detail_wear_silt", 28.0 + k * 1.6, 13.0 + (k % 3) * 2.4, k * .7, 1.4, .8)
	b.board("wing_town_pen", 32.0, 9.97, .73, {"z": 1.43, "plane": 0.0, "signal": "cleared"})
	scatter("hay", [Vector2(27.0, 20.4), Vector2(29.2, 20.6)])
	b.board("prop_hay", 37.4, 21.2, .92)


func feed_barn() -> void:
	b.building(
		40,
		1,
		66,
		22,
		barn,
		{
			"wall": "barn",
			"roof": 2.9,
			"parapet": .5,
			"floor": "dirt",
			"ceiling": "joists",
			"windows": 5,
			"lit": .25,
			"light": .7,
			"skin": "barn"
		}
	)
	# The big door on the lane: brass.
	b.door(53, 22, false, {"from": "n", "key": "key_brass", "id": "barn-door", "style": "slide"})
	b.wall(51, 22, 51, 22, "barnsign", 3.4)
	b.wall(55, 22, 55, 22, "feed_wash", 3.4)
	b.panel(56.3, 23.04, 50.7, 23.04, "feed_marquee", 2.4, 2.94, 1.12)
	b.door(40, 15, true, {"from": "e", "id": "barn-west"})
	b.door(66, 12, true, {"from": "w", "id": "barn-east"})
	b.yard(67, 12, 67, 12, "dirt", lots)
	# The hay loft at the back: a platform up two steps.
	b.raise(41, 2, 48, 8, .48)
	b.raise(41, 9, 48, 9, .24)
	b.paint(41, 2, 48, 9, "porch")
	for p in [Vector2(42.0, 2.8), Vector2(43.2, 2.7), Vector2(44.4, 2.9), Vector2(46.8, 3.0)]:
		b.board("prop_hay", p.x, p.y, .92, {"z": .48})
	hay_bale(45.6, 5.4)
	hay_bale(42.4, 6.8)
	# Cattle stalls down the east side.
	for y in [3.5, 7.5, 11.5, 15.5, 19.5]:
		b.fixture(60.6, y - .06, 65.9, y + .06, 1.25, "wood", "counter_top")
	trough(64.9, 4.0, 65.6, 6.4)
	trough(64.9, 8.0, 65.6, 10.4)
	# The tack room by the west door.
	b.wall(41, 16, 47, 16, "barn", 3.4, true)
	b.door(45, 16, false, {"from": "s", "id": "tack-room"})
	b.room(41, 17, 47, 21, "porch", barn, {"roof": 2.4, "skin": "wood", "light": .55})
	b.wall(48, 16, 48, 21, "barn", 3.4, true)
	b.fixture(41.1, 20.2, 44.6, 20.9, .9, "counter", "counter_top")
	b.board("detail_carriage_tools", 46.0, 20.9, .5, {"z": .5, "plane": 0.0})
	# The feed scale in the middle, sacks about it, the tractor.
	b.fixture(52.4, 10.4, 55.6, 12.6, .3, "steel_mesh", "steel_mesh")
	b.board("wing_town_scale", 54.0, 10.3, .92, {"z": .48, "plane": PI})
	for p in [Vector2(51.2, 9.6), Vector2(56.8, 13.4), Vector2(50.6, 14.2), Vector2(57.6, 6.4)]:
		b.board("split_feed_sacks", p.x, p.y, .52)
	b.town("tractor", 56.5, 18.5, {"solid": .45})
	scatter("hay", [Vector2(50.2, 4.2), Vector2(55.95, 3.9), Vector2(49.3, 19.8)])
	scatter("barrel", [Vector2(64.8, 20.6), Vector2(65.4, 21.2)])
	for p in [Vector2(46.5, 12.5), Vector2(53.5, 6.5), Vector2(53.5, 16.5), Vector2(60.0, 12.0)]:
		b.prop("lamp", p.x, p.y)
		b.glow(p.x, p.y, 3.0, .16)


func livestock_lots() -> void:
	b.yard(67, 1, 94, 21, "dirt", lots)
	b.wall(67, 1, 67, 11, "barn", 3.4)
	b.wall(67, 13, 67, 21, "barn", 3.4)
	fence(95, 1, 95, 21, 1.24)
	fence(67, 22, 94, 22)
	# The stock gate onto the lane: unbolted from this side.
	var gate: Dictionary = b.door(
		80, 22, false, {"from": "n", "style": "slide", "tile": "gate", "roof": 0.0}
	)
	gate["id"] = "stock-gate"
	b.controlled_doors.append([80, 22])
	(
		b
		. stations
		. append(
			{
				"id": "stock-gate",
				"x": 80.5,
				"y": 21.2,
				"label": "UNBOLT THE STOCK GATE",
				"message": "STOCK GATE OPEN. THE LANE'S RIGHT THERE.",
				"requires": [],
				"opens": [[80, 22]],
				"sectors": [],
				"cue": "scenery_scrap",
				"reveals_secret": false,
				"hidden": true,
				"action": "use",
				"held": "",
			}
		)
	)
	b.quest("quest_bolt", 81.5, 21.5, "stock-gate")
	# Through to the registry yard: a cattle gate.
	b.door(92, 22, false, {"from": "n", "tile": "gate", "id": "cattle-gate", "roof": 0.0})
	# Pens: rails in rows with gaps to slip through.
	for x in [74, 81, 88]:
		fence(x, 1, x, 6, .95)
		fence(x, 9, x, 14, .95)
	fence(68, 7, 72, 7, .95)
	fence(76, 7, 79, 7, .95)
	fence(83, 7, 86, 7, .95)
	fence(68, 15, 79, 15, .95)
	fence(83, 15, 94, 15, .95)
	# The loading ramp in the north-east pen.
	b.raise(90, 2, 93, 3, .48)
	b.raise(90, 4, 93, 4, .24)
	b.paint(90, 2, 93, 4, "porch")
	trough(70.0, 3.0, 70.5, 5.6)
	trough(77.0, 11.0, 79.6, 11.5)
	trough(84.0, 3.0, 84.5, 5.6)
	b.prop("silo", 92.4, 9.6)
	b.prop("silo", 92.4, 13.0)
	scatter("hay", [Vector2(71.0, 12.0), Vector2(86.4, 12.0), Vector2(78.0, 19.8)])
	for k in 12:
		b.mark(
			"detail_wear_silt",
			69.0 + b.rng.randf() * 24.0,
			2.0 + b.rng.randf() * 18.0,
			b.rng.randf() * 3.0,
			1.4,
			.8
		)
	b.board("wing_town_rail", 89.0, 4.96, .78, {"z": 1.23, "plane": 0.0})
	poles([Vector2(68.4, 21.4), Vector2(80.0, 16.0), Vector2(93.6, 16.0)])
	streetlamp(80.0, 14.0)


func stock_registry() -> void:
	b.yard(90, 23, 126, 46, "gravel", registry)
	fence(90, 22, 126, 22, 1.6)
	b.yard(92, 22, 92, 22, "dirt", registry)
	(
		b
		. stations
		. append(
			{
				"id": "yard-bar",
				"x": 90.4,
				"y": 25.5,
				"label": "LIFT THE YARD BAR",
				"message": "YARD BAR UP. STRAIGHT BACK DOWN THE LANE.",
				"requires": [],
				"opens": [[89, 25]],
				"sectors": [],
				"cue": "scenery_scrap",
				"reveals_secret": false,
				"hidden": true,
				"action": "use",
				"held": "",
			}
		)
	)
	b.building(
		98,
		28,
		118,
		41,
		registry,
		{
			"wall": "brick",
			"roof": 2.4,
			"floor": "concrete",
			"windows": 3,
			"lit": .5,
			"light": .74,
			"skin": "office_wall"
		}
	)
	b.raise(104, 26, 112, 27, .12)
	b.paint(104, 26, 112, 27, "porch")
	b.door(108, 28, false, {"from": "s", "id": "registry-front"})
	b.board("wing_town_registry", 106.0, 27.94, .77, {"z": 1.4, "plane": PI})
	b.wall(99, 34, 117, 34, "brick", 2.68, true)
	b.door(103, 34, false, {"from": "s", "id": "records"})
	b.door(113, 34, false, {"from": "s", "id": "records-east"})
	b.wall(111, 35, 111, 40, "brick", 2.68, true)
	b.door(111, 38, true, {"from": "w", "id": "vault"})
	b.room(
		112, 35, 117, 40, "floor_tile", registry, {"roof": 2.4, "skin": "steel_mesh", "light": .82}
	)
	# The front office: the counter, the stamp, the radio.
	b.fixture(100.0, 31.4, 106.0, 32.2, .95, "counter", "counter_top")
	b.fixture(110.0, 31.4, 116.0, 32.2, .95, "counter", "counter_top")
	b.board("detail_registry_stamp", 104.0, 31.8, .5, {"z": .95, "plane": PI / 2})
	b.board("detail_scale_weights", 112.0, 31.8, .5, {"z": .95})
	b.prop("lamp", 103.0, 30.5)
	b.prop("lamp", 113.0, 30.5)
	# The records: shelves in aisles.
	for x in [100.6, 103.6, 106.6]:
		b.fixture(x, 36.0, x + .6, 39.6, 1.4, "shelves", "counter_top")
	b.prop("lamp", 105.0, 37.5)
	# The vault: the steel key on the desk.
	table(114.0, 39.2, 116.6, 40.0, .78)
	b.town("strongbox", 115.3, 39.55, {"z": .78, "scale": .55})
	b.prop("lamp", 114.5, 37.0)
	b.glow(115.0, 38.0, 2.6, .25)
	# The yard: stock trailer, chutes, scale house sign.
	b.fixture(120.0, 26.0, 125.0, 27.6, 1.36, "stockyard", "tin")
	b.fixture(94.0, 42.0, 96.6, 43.0, .62, "crate_side", "counter_top")
	fence(120, 33, 126, 33)
	fence(120, 38, 126, 38)
	b.wall(120, 34, 120, 36, "stockyard", 1.24)
	scatter("hay", [Vector2(122.0, 35.6), Vector2(123.4, 36.2)])
	scatter("barrel", [Vector2(96.4, 29.4), Vector2(97.2, 30.0)])
	b.board("wing_town_scale", 95.0, 41.98, .92, {"z": .1, "plane": PI})
	poles([Vector2(91.0, 45.6), Vector2(108.0, 45.6), Vector2(125.6, 45.6)])
	streetlamp(108.0, 25.0)
	streetlamp(94.0, 36.0)
	streetlamp(122.0, 42.0)


func corn_maze() -> void:
	# Bands of path cut through the corn, a clearing in the middle with a
	# fresh crop circle, and gaps that make you walk the long way.
	for r in [
		[128, 43, 146, 45],
		[144, 42, 146, 42],
		[129, 39, 146, 41],
		[129, 37, 131, 38],
		[128, 29, 148, 36],
		[144, 27, 146, 28],
		[129, 24, 146, 26],
		[129, 22, 131, 23],
	]:
		b.yard(r[0], r[1], r[2], r[3], "dirt", corn, {"light": .9})
	# Corn left standing in the clearing to hide behind.
	for r in [[132, 30, 133, 31], [143, 30, 144, 31], [146, 34, 147, 35], [129, 34, 130, 35]]:
		b.wall(r[0], r[1], r[2], r[3], "corn", 2.3)
	b.wall(138, 29, 138, 29, "corn", 2.3)
	# The crop circle: flattened stalks in rings.
	for y in range(29, 37):
		for x in range(133, 145):
			var d := Vector2(x + .5 - 138.5, (y + .5 - 32.5) * 1.15).length()
			if d < 1.4 or (d > 2.4 and d < 3.4):
				b.paint(x, y, x, y, "orchard")
	for k in 6:
		b.mark("mark_scorch_%d" % (k % 3), 136.0 + k * .9, 31.0 + (k % 2) * 2.5, k * 1.1, 1.0, .8)
	scatter("reeds", [Vector2(128.6, 44.4), Vector2(146.4, 40.4), Vector2(131.3, 25.6)])
	b.board("prop_hay", 147.4, 32.0, .92)
	b.town("skull_post", 128.5, 36.5, {"solid": .1})
	# The steel gate in the registry yard's east fence.
	b.door(
		127,
		44,
		true,
		{"from": "w", "key": "key_steel", "id": "corn-gate", "tile": "gate", "roof": 0.0}
	)
	b.board("wing_town_pen", 126.94, 42.6, .73, {"z": 1.1, "plane": PI / 2, "signal": "cleared"})


func north_pasture() -> void:
	b.yard(96, 1, W - 2, 21, "grass", pasture)
	b.wall(127, 22, W - 2, 22, "corn", 2.3)
	b.yard(129, 22, 131, 22, "dirt", corn)
	b.distant_cues.append([137.0, 44.0, "distant_corn_rustle"])
	b.distant_cues.append([138.5, 32.5, "distant_corn_rustle"])
	# The crater the saucer dug, scorched, and the wreck in it.
	for y in range(3, 18):
		for x in range(108, 129):
			var d := Vector2(x + .5 - 118.0, (y + .5 - 10.0) * 1.3).length()
			if d < 4.2:
				b.raise(x, y, x, y, -.24)
				b.paint(x, y, x, y, "quarry_dust")
			elif d < 6.6:
				b.raise(x, y, x, y, -.12)
				b.paint(x, y, x, y, "dirt")
	# The wreck: the modelled saucer over a low hull the shots and boots hit.
	b.fixture(117.0, 9.0, 119.0, 11.0, -.1, "quarry_dust", "quarry_dust", -.24)
	b.town("saucer_wreck", 118.0, 10.0, {"glow": true, "scale": 1.35})
	for k in 12:
		b.mark(
			"mark_scorch_%d" % (k % 3),
			113.0 + b.rng.randf() * 10.0,
			6.0 + b.rng.randf() * 8.0,
			b.rng.randf() * 3.0,
			1.6,
			1.0
		)
	# Bessie's pen in the far corner: an alien fence of mesh, cut open.
	fence(139, 2, 147, 2, 1.1)
	b.wall(139, 3, 139, 8, "steel_mesh", .55)
	b.wall(147, 3, 147, 8, "steel_mesh", .55)
	b.wall(139, 8, 142, 8, "steel_mesh", .55)
	b.wall(145, 8, 147, 8, "steel_mesh", .55)
	trough(141.0, 3.4, 143.6, 3.9)
	b.glow(143.0, 5.0, 3.6, .3)
	# Cover in the field: bales, rocks, the tractor the aliens tipped.
	hay_bale(100.0, 6.0)
	hay_bale(100.8, 15.6)
	hay_bale(125.6, 16.4)
	hay_bale(108.4, 18.6)
	hay_bale(133.0, 7.0)
	hay_bale(135.4, 15.0)
	b.fixture(104.6, 10.4, 105.8, 11.4, .7, "quarry_face", "quarry_face")
	b.fixture(129.4, 12.0, 130.8, 13.0, .7, "quarry_face", "quarry_face")
	b.fixture(137.0, 18.4, 138.2, 19.6, .7, "quarry_face", "quarry_face")
	b.town("tractor", 122.5, 18.5, {"solid": .45})
	b.prop("tree", 97.4, 2.6)
	b.prop("tree_b", 125.0, 2.4)
	b.prop("tree", 147.4, 19.6)
	b.prop("windmill", 133.6, 3.0)
	scatter("hay", [Vector2(102.6, 2.6), Vector2(107.0, 20.6), Vector2(146.0, 12.0)])
	b.glow(118.0, 10.0, 5.0, .2)


## The second pass: what makes a place look lived in (and shot up).
func dressing() -> void:
	# A covered sidewalk in front of the feed store, benches, a phone booth.
	b.room(65, 32, 67, 41, "porch", main_street, {"roof": 2.05, "ceiling": "joists", "light": .95})
	b.raise(65, 32, 67, 41, .12)
	for y in [32.07, 37.0, 41.93]:
		b.fixture(64.93, y - .07, 65.07, y + .07, 2.05, "wood", "counter_top", .12)
	b.fixture(66.3, 33.4, 66.8, 35.0, .45, "wood", "counter_top", .12)
	b.fixture(54.3, 48.6, 54.8, 50.0, .45, "wood", "counter_top", .12)
	b.fixture(65.9, 55.2, 66.8, 56.1, 2.0, "glazing", "tin", .12)
	b.board("wing_town_radio", 65.88, 55.65, .5, {"z": 1.2, "plane": PI / 2})
	scatter("barrel", [Vector2(54.6, 52.4), Vector2(66.4, 43.2)])
	b.board("story_aftermath", 61.5, 47.0, .19, {"z": .025})
	# Wall trim with a history: repaired boards, garage courses, pen boards.
	b.set_skin(26, 50, 29, 54, "detail_wall_garage_courses")
	b.set_skin(27, 18, 30, 21, "detail_wall_feed_pen_boards")
	b.set_skin(26, 2, 34, 8, "detail_wall_shed_repair")
	b.set_skin(76, 32, 79, 41, "detail_wall_kiln_patches")
	# The barn: more light, hay stacked high, a wagon, the loft ladder.
	for p in [Vector2(44.0, 5.0), Vector2(62.0, 6.0), Vector2(62.0, 17.0), Vector2(50.0, 20.0)]:
		b.prop("lamp", p.x, p.y)
		b.glow(p.x, p.y, 3.2, .18)
	b.fixture(56.4, 2.2, 59.2, 4.0, 1.25, "feed", "counter_top")
	b.fixture(56.6, 2.4, 58.8, 3.8, 1.9, "feed", "counter_top", 1.25)
	b.fixture(49.4, 2.2, 51.0, 3.0, .9, "feed", "counter_top")
	b.fixture(50.2, 14.6, 52.8, 16.0, .7, "wood", "wood")
	b.board("prop_tire", 50.0, 16.3, .49)
	b.board("prop_tire", 53.0, 16.3, .49)
	b.board("wanted_poster", 41.04, 11.0, .6, {"z": 1.1, "plane": -PI / 2})
	# The chapel: candles at the altar, the hymn board.
	b.glow(77.0, 46.5, 2.4, .3)
	b.board("hub_lamp", 75.0, 46.3, .9, {"glow": true, "z": .24})
	b.board("hub_lamp", 79.0, 46.3, .9, {"glow": true, "z": .24})
	b.board("detail_lost_property_tray", 72.55, 46.45, .4, {"z": .0})
	# The trailers: a table, a bed, a TV in each that has room.
	for t: Vector2i in [
		Vector2i(92, 49), Vector2i(103, 49), Vector2i(114, 49), Vector2i(92, 56), Vector2i(103, 56)
	]:
		var x0 := t.x + 1
		var y0 := t.y + 1
		b.fixture(x0 + .1, y0 + .1, x0 + 1.4, y0 + 1.0, .5, "wood", "counter_top")
		table(x0 + 4.2, y0 + .2, x0 + 5.0, y0 + .9, .7)
	b.react("tv", 104.4, 51.6, .75, {"id": "trailer-tv"})
	b.react("tv", 117.6, 51.5, .75, {"id": "trailer-tv-b"})
	b.react("cans", 108.0, 50.4, .4, {"id": "trailer-cans"})
	b.react("cancan", 98.6, 55.0, .4, {"id": "court-can"})
	b.react("cancan", 112.0, 61.0, .4, {"id": "court-can-b"})
	# The creek: stones in the bed, a rowboat that never floated.
	for p in [Vector2(6.5, 14.5), Vector2(5.5, 47.5), Vector2(7.5, 55.5)]:
		b.fixture(p.x - .3, p.y - .2, p.x + .3, p.y + .2, .3, "quarry_face", "quarry_face", -.24)
	b.fixture(9.6, 33.2, 10.6, 35.4, .38, "wood", "wood", -.12)
	b.react("bottles", 3.0, 18.0, .42, {"id": "creek-bottles"})
	# The salvage yard: the crushed-car stack and the crane hook.
	b.fixture(14.2, 31.2, 16.0, 32.6, 1.5, "mill_tin", "tin")
	b.react("scrap", 25.0, 31.8, .71, {"id": "junk-scrap"})
	b.react("cans", 22.6, 46.4, .4, {"id": "junk-cans"})
	# Gas-N-Gut: the ice chest and the air pump by the road.
	b.fixture(31.2, 56.4, 32.2, 57.0, .7, "glazing", "tin")
	b.prop("pump_b", 36.4, 58.0)
	# Registry yard and lots: more light to fight by.
	for p in [Vector2(98.0, 44.0), Vector2(116.0, 44.0)]:
		streetlamp(p.x, p.y)
	streetlamp(70.0, 4.0)
	streetlamp(90.0, 20.0)
	# The pasture: a light in the pen, the alien glow off the wreck.
	b.board("hub_lamp", 139.4, 9.0, 2.52, {"glow": true})
	b.glow(139.0, 9.0, 4.0, .25)


## The third pass: the town's modelled props where people left them, and
## the buildings given a skyline: false fronts, gables, chimneys, a spire.
func town_detail() -> void:
	# Outhouses, the moonshine, the junk on every porch.
	b.town("outhouse", 26.5, 46.5, {"solid": .4})
	b.town("outhouse", 124.5, 60.5, {"solid": .4})
	b.town("still", 11.5, 15.5, {"solid": .45})
	scatter("barrel", [Vector2(10.6, 14.4), Vector2(12.3, 16.6)])
	b.glow(11.5, 15.5, 2.4, .2)
	b.town("still", 34.5, 40.5, {"solid": .4})
	b.town("fridge", 14.5, 44.5, {"solid": .35})
	b.town("washer", 27.5, 38.5, {"solid": .3})
	b.town("engine_hoist", 17.5, 38.5, {"solid": .45})
	b.town("rocker", 55.0, 33.6)
	b.town("rocker", 96.6, 53.5)
	# The trailer court: dishes, a washer, flamingos, grills, a doghouse.
	b.town("dish", 101.5, 48.5, {"solid": .2})
	b.town("washer", 101.5, 50.5, {"solid": .3})
	b.town("fridge", 112.5, 48.5, {"solid": .35})
	b.town("dish", 111.5, 50.5, {"solid": .2})
	b.town("grill", 105.5, 61.5, {"solid": .35})
	b.town("grill", 120.5, 61.5, {"solid": .35})
	b.town("picnic_table", 111.5, 61.5, {"solid": .4})
	b.town("doghouse", 125.5, 57.5, {"solid": .45})
	for p in [Vector2(99.4, 61.5), Vector2(100.3, 61.7), Vector2(116.6, 61.6), Vector2(93.5, 61.4)]:
		b.town("flamingo", p.x, p.y)
	b.town("laundry", 100.5, 54.5, {"plane": PI / 4, "z": .68, "back": "town_laundry"})
	b.town("laundry", 111.5, 54.5, {"plane": PI / 4, "z": .68, "back": "town_laundry"})
	# Picnic tables at the gas station and the chapel; a hay wagon on the lane.
	b.town("picnic_table", 36.5, 55.5, {"solid": .4})
	b.town("picnic_table", 84.5, 61.5, {"solid": .4})
	b.town("hay_wagon", 61.5, 24.5, {"solid": .45})
	b.town("hay_wagon", 78.5, 18.5, {"solid": .45})
	# Scarecrows in the corn and the orchard; skulls on the fence posts.
	for p in [
		Vector2(143.35, 45.35),
		Vector2(129.65, 41.35),
		Vector2(145.35, 35.65),
		Vector2(130.5, 25.5),
		Vector2(100.5, 11.5),
		Vector2(16.5, 17.5),
	]:
		b.town("scarecrow", p.x, p.y, {"solid": .12})
	b.town("skull_post", 104.5, 20.5, {"solid": .1})
	b.town("skull_post", 93.5, 6.5, {"solid": .1})
	# The aliens' pylons round Bessie's pen, humming.
	for p in [Vector2(140.5, 3.5), Vector2(146.5, 3.5), Vector2(140.5, 7.5), Vector2(146.5, 7.5)]:
		b.town("pylon", p.x, p.y, {"solid": .15, "glow": true})
		b.glow(p.x, p.y, 2.0, .2)
	# Where the station levers are: the gate bolt, its lamp green once drawn.
	b.quest("quest_bolt", 90.5, 26.5, "yard-bar")
	b.glow(90.4, 25.5, 2.0, .2)
	b.glow(80.5, 21.2, 2.0, .2)
	# False fronts on Main Street.
	b.wall_top(53, 31, 53, 46, 3.3)
	b.wall_top(53, 30, 53, 30, 3.0)
	b.wall_top(53, 47, 53, 47, 3.0)
	b.wall_top(68, 31, 68, 42, 3.0)
	b.wall_top(15, 55, 30, 55, 2.75)
	b.wall_top(40, 57, 50, 57, 2.6)
	b.wall_top(98, 28, 118, 28, 2.9)
	# The barn's gable, stepped, over the lane, and the hay door in it.
	for step in [[40.0, 67.0, 3.4, 3.9], [43.0, 64.0, 3.9, 4.4], [46.0, 61.0, 4.4, 4.9]]:
		b.tower(step[0], 22.0, step[1], 23.0, step[2], step[3], "barn")
	b.tower(49.0, 22.0, 58.0, 23.0, 4.9, 5.3, "barn")
	b.tower(51.5, 22.0, 55.5, 23.0, 5.3, 5.6, "barn")
	b.panel(54.4, 23.03, 52.6, 23.03, "door", 3.6, 4.6, .8)
	b.panel(56.0, 23.03, 51.0, 23.03, "trim_eave", 5.6, 5.75, .9)
	# Chimneys and stacks.
	b.tower(51.2, 30.2, 52.0, 31.0, 2.53, 3.7, "brick")
	b.tower(115.2, 28.2, 116.0, 29.0, 2.68, 3.6, "brick")
	b.tower(36.2, 1.2, 36.8, 1.8, 2.58, 3.9, "tin")
	b.tower(17.3, 49.2, 18.0, 49.9, 2.48, 3.3, "cinder")
	# The chapel's spire on its steeple, and the cross.
	b.tower(76.0, 57.0, 79.0, 59.0, 5.4, 5.8, "plaster")
	b.tower(76.4, 57.3, 78.6, 58.7, 5.8, 6.6, "plaster")
	b.tower(76.9, 57.6, 78.1, 58.4, 6.6, 7.6, "tin")
	b.tower(77.3, 57.8, 77.7, 58.2, 7.6, 8.4, "tin")
	b.tower(77.45, 57.95, 77.55, 58.05, 8.4, 9.1, "wood")
	b.panel(77.15, 58.0, 77.85, 58.0, "wood", 8.7, 8.82, .9)
	# An awning over each trailer's door, on corner posts.
	for t: Array in [[92, 49, "s"], [103, 49, "s"], [114, 49, "s"], [92, 56, "n"], [103, 56, "n"]]:
		var x := int(t[0]) + 3
		var y := int(t[1]) + 4 if t[2] == "s" else int(t[1]) - 1
		b.room(x, y, x, y, "porch", trailers, {"roof": 1.95, "ceiling": "tin", "light": .9})
		var post_y := float(y + 1) if t[2] == "s" else float(y)
		for px in [float(x), float(x + 1)]:
			b.fixture(px - .05, post_y - .05, px + .05, post_y + .05, 1.95, "tin", "tin")
	b.room(117, 55, 117, 55, "porch", trailers, {"roof": 1.95, "ceiling": "tin", "light": .9})


## The fourth pass: more of what a hick town keeps in its yards.
func more_detail() -> void:
	b.town("truck_blocks", 123.5, 50.5, {"solid": .45})
	b.town("truck_blocks", 24.5, 32.5, {"solid": .45})
	b.town("porch_couch", 104.75, 53.8)
	b.town("porch_couch", 54.8, 44.2)
	b.town("chicken_coop", 21.5, 9.5, {"solid": .45})
	b.town("chicken_coop", 93.4, 46.25, {"scale": .9})
	b.town("bathtub", 37.5, 17.5, {"solid": .45})
	b.town("bathtub", 125.5, 51.5, {"solid": .45})
	b.town("wheelbarrow", 35.5, 13.6)
	b.town("wheelbarrow", 58.6, 13.6)
	b.town("gas_cans", 36.6, 52.6)
	b.town("gas_cans", 27.4, 35.6)
	b.town("tire_stack", 27.5, 44.5, {"solid": .3})
	b.town("tire_stack", 35.5, 50.5, {"solid": .3})
	b.town("mailbox_row", 90.5, 64.1)
	b.town("mailbox_row", 55.4, 51.6)
	b.town("axe_stump", 22.5, 13.5, {"solid": .3})
	b.town("log_pile", 3.5, 26.6)
	b.town("forklift", 86.5, 41.5, {"solid": .45})
	b.town("pallet_stack", 83.5, 33.5, {"solid": .45})
	b.town("generator", 30.5, 58.5, {"solid": .45})
	b.town("lantern_post", 12.5, 17.5, {"solid": .1, "glow": true})
	b.glow(12.5, 17.5, 3.0, .25)
	b.town("cable_spool", 118.5, 44.5, {"solid": .45})
	b.town("warning_barrel", 117.5, 64.5, {"solid": .3})
	b.town("warning_barrel", 118.5, 64.5, {"solid": .3})
	b.town("searchlight", 125.5, 21.5, {"solid": .35, "glow": true})
	b.town("searchlight", 97.5, 21.5, {"solid": .35, "glow": true})


func story() -> void:
	b.meta["return_gate"] = {"destination": "hub", "x": 7.0, "y": 76.4, "width": 3.25, "side": -1}
	b.meta["area_sounds"] = {str(creek): "creek", str(barn): "barn"}
	b.meta["area_cues"] = {
		str(road): "distant_dog",
		str(trailers): "distant_dog",
		str(creek): "distant_crow",
		str(orchard): "distant_crow",
		str(pasture): "distant_crow",
		str(corn): "distant_crow",
		str(hogpen): "distant_crow",
		str(chapel): "distant_crow",
	}
	for l in [
		["ROAD", 6, 67],
		["GAS", 20, 51],
		["BAIT", 43, 53],
		["STANKY'S", 42, 40],
		["MAIN ST", 57, 52],
		["CREEK", 3, 40],
		["SALVAGE", 16, 38],
		["FEED", 70, 35],
		["CHAPEL", 73, 49],
		["TRAILERS", 104, 54],
		["BARN", 50, 10],
		["HOG PEN", 28, 14],
		["PACKING", 27, 4],
		["LOTS", 77, 9],
		["REGISTRY", 103, 37],
		["PASTURE", 110, 4],
		["CORN", 134, 41],
	]:
		b.label(String(l[0]), int(l[1]), int(l[2]))
	Cast.enemies(b)
	Cast.pickups(b)
	Cast.set_pieces(b)


## The polish pass: structure in the big empty stretches, then every empty
## patch filled with what that part of town would have lying in it.
func polish() -> void:
	# Produce stands on the road's south verge, a billboard frame between.
	b.booth(
		24,
		71,
		28,
		74,
		road,
		"n",
		{"wall": "wood", "skin": "wood", "sign": "story_food", "roof": 2.1}
	)
	b.booth(
		74,
		71,
		78,
		74,
		road,
		"n",
		{"wall": "wood", "skin": "wood", "sign": "wing_town_feed", "roof": 2.1}
	)
	b.board("wanted_poster", 51.0, 73.9, 1.4, {"z": 1.0, "plane": PI})
	# The creek: a fallen cottonwood across the bank, a moonshiner's stump.
	b.fixture(1.0, 44.4, 4.0, 44.6, .5, "mill_log", "mill_log", -.12)
	b.town("axe_stump", 2.5, 30.5, {"solid": .3})
	# Main Street: cars nosed in at the kerb.
	for y in [36.0, 44.0, 52.0, 58.0]:
		b.car(63.2, y, false, "tin" if int(y) % 3 else "mill_tin")
	# The pasture: an open hay shed and its stacked bales.
	b.room(98, 13, 103, 17, "dirt", pasture, {"roof": 2.4, "ceiling": "tin", "light": .9})
	for p in [Vector2(98.0, 13.0), Vector2(104.0, 13.0), Vector2(98.0, 18.0), Vector2(104.0, 18.0)]:
		b.fixture(p.x - .07, p.y - .07, p.x + .07, p.y + .07, 2.4, "wood", "wood")
	for y in [14.5, 16.5]:
		b.bale(99.5, y)
		b.bale(101.5, y)
	# The registry yard: a second pen and a feed bunk.
	b.fence(120, 39, 124, 39, 1.0)
	b.fence(120, 44, 124, 44, 1.0)
	b.trough(121.0, 41.3, 124.6, 41.7)
	var junk := ["prop:tire", "prop:barrel", "gas_cans", "tire_stack", "warning_barrel"]
	var farm := ["prop:hay", "wheelbarrow", "prop:barrel", "axe_stump", "chicken_coop"]
	for e in [
		["billy", 26.0, 66.5, "stand-billy"],
		["coot", 76.0, 66.5, "stand-coot"],
		["alien", 102.6, 15.5, "shed-alien"],
	]:
		b.enemy(String(e[0]), float(e[1]), float(e[2]), String(e[3]))
	(
		b
		. triggers
		. append(
			{
				"id": "hay-shed-ambush",
				"when": {"area": [96, 11, 106, 20]},
				"do":
				[
					{"message": "SOMETHING'S BEEN SLEEPING IN THE HAY.", "for": 2.5},
					{"wake": ["shed-alien"]},
					{"alert": 10}
				],
			}
		)
	)
