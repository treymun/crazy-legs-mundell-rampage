## Puckett Grain Co-op (5v5 map "grainyard", src/modes/tactical_mode.gd): a
## county grain co-op at dusk, built for search and destroy and hostage
## rescue alike. An original layout, three lanes and two sites:
##
##   west   the TRUCK LOT, where the attackers start (the rescue box in
##          hostage rescue);
##   north  FEED ROAD up the west fence, then CONVEYOR ROW east under the
##          belts, through the BELT HOUSE's two narrow doors and out down
##          A LONG onto site A;
##   mid    SCALE ALLEY out of the lot into the RAIL YARD (boxcars and a grain
##          bin to fight round), A SHORT up its north-east corner onto A, the
##          SCALE OFFICE off its south side into the warehouse, and CO-OP
##          ROW, the long lane east to the defenders' lot;
##   south  DITCH ROAD down the west fence, the long FEED TUNNEL east, out
##          into B LONG and through the warehouse's big doors onto site B;
##   east   the CO-OP LOT, where the defenders start, a short run north to A
##          and south to B.
## Site A is the DUMP PIT: open concrete, grain bins and a hay wagon for cover.
## Site B is the SEED WAREHOUSE: indoors, pallets, shelves and a forklift.
## The hostages are held on each site.
##
## Built by tools/levels/build_level.gd -- grainyard. Units are cells; x runs
## east, y south, angles as the player's (0 east, PI west, -PI/2 north).
extends RefCounted

const Builder := preload("res://tools/levels/level_builder.gd")
const W := 66
const H := 54

var b: Builder
var d := {}


func make() -> Builder:
	b = Builder.new("grainyard", W, H, "tin")
	b.meta = {
		"title": "PUCKETT GRAIN CO-OP",
		"heading": ["PUCKETT", "GRAIN CO-OP"],
		"intro": "PUCKETT GRAIN CO-OP. FIVE A SIDE. B TO BUY.",
		"score": "music",
		"ambience": "range",
		"layout": 1,
		"sky": "sky",
		"area_sounds": {},
		"tactical":
		{
			"attack_spawns":
			[
				[5.5, 23.5, 0.0],
				[5.5, 27.5, 0.0],
				[5.5, 31.5, 0.0],
				[8.5, 25.5, 0.0],
				[8.5, 29.5, 0.0],
			],
			"defend_spawns":
			[
				[61.5, 21.5, PI],
				[61.5, 25.5, PI],
				[61.5, 29.5, PI],
				[58.5, 23.5, PI],
				[58.5, 27.5, PI],
			],
			"sites": {"A": [46, 3, 55, 12], "B": [44, 38, 53, 48]},
			"hostages": [[54.5, 4.5], [52.5, 46.5]],
			"rescue": [2, 20, 10, 33],
			"routes":
			{
				"A":
				[
					[[6.5, 16.5], [7.5, 6.5], [20.5, 6.5], [34.5, 5.5], [41.5, 6.5], [50.5, 8.5]],
					[[18.5, 26.5], [30.5, 23.5], [36.5, 17.5], [40.5, 12.5], [50.5, 8.5]],
				],
				"B":
				[
					[[6.5, 38.5], [7.5, 46.5], [20.5, 46.5], [36.5, 46.5], [48.5, 44.5]],
					[[18.5, 26.5], [30.5, 30.5], [35.5, 36.5], [40.5, 38.5], [48.5, 41.5]],
				],
			},
			"holds":
			{
				"A": [[54.5, 4.5, PI - .05], [51.5, 12.5, -PI * .83]],
				"B": [[51.5, 44.5, PI], [52.5, 38.5, PI]],
				"mid": [[53.5, 26.5, PI]],
			},
		},
	}
	return b


func build(_b) -> Array:
	d["lot"] = b.district("TRUCK LOT", Color(1.06, 1.0, .9))
	d["road"] = b.district("FEED ROAD", Color(1.04, 1.0, .9))
	d["belt"] = b.district("BELT HOUSE", Color(1.08, .97, .84))
	d["a"] = b.district("SITE A  DUMP PIT", Color(1.08, 1.0, .86))
	d["mid"] = b.district("RAIL YARD", Color(1.02, 1.0, .94))
	d["office"] = b.district("SCALE OFFICE", Color(1.06, 1.0, .9))
	d["tunnel"] = b.district("FEED TUNNEL", Color(1.0, .96, .9))
	d["b"] = b.district("SITE B  SEED WAREHOUSE", Color(1.08, .98, .86))
	d["coop"] = b.district("CO-OP LOT", Color(1.0, 1.0, 1.04))
	# Everything starts as tin sheds and fence, tall; the yards are cut out.
	b.wall(0, 0, W - 1, H - 1, "tin", 3.0)
	b.wall(0, 0, W - 1, 1, "hedgerow", 3.4)
	b.wall(0, H - 2, W - 1, H - 1, "hedgerow", 3.4)
	b.wall(0, 0, 1, H - 1, "hedgerow", 3.4)
	b.wall(W - 2, 0, W - 1, H - 1, "hedgerow", 3.4)
	b.wall(42, 35, 55, 50, "brick", 3.4, true)
	b.wall(30, 2, 38, 10, "barn", 3.0, true)
	b.wall(33, 35, 42, 41, "plaster", 2.6, true)
	west()
	north()
	middle()
	south()
	east()
	return [5.5, 27.5, 0.0]


# ------------------------------------------------------------------- west


func west() -> void:
	b.yard(2, 19, 11, 34, "gravel", d["lot"])
	b.paint(3, 20, 10, 33, "asphalt")
	b.paint(2, 26, 11, 27, "shoulder")
	b.yard(4, 5, 9, 18, "dirt", d["road"])
	b.yard(4, 35, 9, 47, "dirt", d["road"])
	b.streetlamp(3.5, 19.5, 4.4)
	b.streetlamp(10.5, 34.5, 4.0)
	# The attackers' trucks along the lot's edges, never on the way out.
	b.town("semi_tractor", 3.5, 33.5, {"solid": .44})
	b.town("dump_truck", 10.5, 20.5, {"solid": .44})
	b.prop("pickup_truck", 10.5, 32.5)
	b.fixture(9.8, 32.1, 11.2, 32.9, .3, "mill_tin", "tin")
	b.town("tire_pile", 2.5, 19.5, {"solid": .34})
	b.prop("roadsign", 11.5, 23.5)
	# Feed road: bales and a wheelbarrow off to the sides.
	b.bale(4.5, 9.5)
	b.bale(9.5, 13.5)
	b.town("wheelbarrow", 4.5, 15.5, {"solid": .28})
	b.prop("tree_b", 4.5, 5.5)
	# Ditch road.
	b.town("burn_barrel", 9.5, 39.5, {"solid": .28})
	b.town("tire_stack", 4.5, 43.5, {"solid": .34})
	b.prop("tree", 4.5, 47.5)


# ------------------------------------------------------------------ north


func north() -> void:
	b.yard(10, 4, 29, 9, "dirt", d["road"])
	b.paint(10, 6, 29, 7, "gravel")
	# The belts overhead and their footings, all on the north edge.
	for x in [13, 19, 25]:
		b.fixture(x + .2, 4.1, x + .8, 4.9, 2.6, "mill_tin", "tin")
	b.town("belt_conveyor", 16.5, 4.5)
	b.town("belt_conveyor", 22.5, 4.5)
	b.crate_stack(15.5, 8.5)
	b.crate_stack(21.5, 5.5, 1.1)
	b.town("lumber_cart", 27.5, 8.5, {"solid": .36})
	# The belt house: two narrow doors in, two out.
	b.room(31, 3, 37, 9, "wood", d["belt"], {"skin": "barn", "light": .66, "roof": 2.4})
	b.gap(30, 5, "w")
	b.gap(30, 8, "w")
	b.gap(38, 4, "e")
	b.gap(38, 8, "e")
	b.town("sorting_table", 34.5, 6.5, {"solid": .4})
	b.crate_stack(32.5, 3.5)
	b.town("powder_shelf", 36.5, 9.5, {"solid": .34})
	b.prop("lamp", 33.5, 8.5)
	# A long, and site A: the dump pit.
	b.yard(39, 3, 44, 10, "dirt", d["a"])
	b.yard(45, 2, 56, 13, "concrete", d["a"])
	b.paint(46, 3, 55, 12, "track_chalk")
	b.paint(47, 4, 54, 11, "concrete")
	b.town("hay_wagon", 41.5, 9.5, {"solid": .44})
	b.bale(42.5, 3.5)
	# Two grain bins, tall and round enough to hide behind.
	b.wall(49, 6, 50, 7, "tin", 3.8)
	b.wall(52, 10, 53, 11, "tin", 3.8)
	b.town("tractor", 54.5, 8.5, {"solid": .44})
	b.crate_stack(46.5, 11.5)
	b.crate_stack(47.5, 11.5, 1.1)
	b.town("tool_chest", 55.5, 2.5, {"solid": .34})
	b.streetlamp(45.5, 2.5, 4.6)


# ------------------------------------------------------------------- mid


func middle() -> void:
	b.yard(12, 24, 24, 28, "asphalt", d["mid"])
	b.paint(15, 25, 20, 27, "concrete")
	b.crate_stack(14.5, 24.5)
	b.town("gas_cans", 22.5, 28.5, {"solid": .26})
	# The rail yard: two strings of boxcars on their tracks, a bin and a tower.
	b.yard(25, 19, 37, 34, "gravel", d["mid"])
	b.paint(25, 21, 37, 22, "tracks")
	b.paint(25, 29, 37, 30, "tracks")
	b.fixture(27.15, 21.15, 31.85, 21.95, 1.75, "mill_tin", "tin")
	b.fixture(31.15, 29.15, 35.85, 29.95, 1.75, "mill_tin", "tin")
	b.wall(27, 32, 28, 33, "tin", 3.8)
	b.prop("water_tower", 35.5, 33.5)
	b.crate_stack(33.5, 24.5)
	b.crate_stack(26.5, 26.5, 1.1)
	b.prop("barrel", 36.5, 19.5)
	b.streetlamp(30.5, 25.5, 4.8)
	# A short: up out of the rail yard's corner to A.
	b.yard(35, 11, 42, 18, "gravel", d["a"])
	b.bale(36.5, 12.5)
	b.crate_stack(41.5, 15.5)
	# The scale office: through it from the rail yard into the warehouse.
	b.room(34, 36, 41, 40, "floor_tile", d["office"], {"skin": "office_wall", "light": .8})
	b.gap(35, 35, "n")
	b.gap(36, 35, "n")
	b.gap(42, 38, "w")
	b.gap(42, 39, "w")
	b.fixture(37.2, 37.4, 39.8, 38.0, .95, "counter", "counter_top")
	b.town("porch_couch", 34.5, 39.5, {"solid": .36})
	b.window_pane(38, 35)
	b.window_pane(39, 35)
	# Co-op row: the long lane from the rail yard to the defenders' lot.
	b.yard(38, 23, 56, 27, "asphalt", d["coop"])
	b.paint(38, 25, 56, 25, "shoulder")
	b.fixture(45.15, 24.15, 49.85, 24.95, 1.75, "mill_tin", "tin")
	b.crate_stack(41.5, 27.5)
	b.crate_stack(53.5, 23.5)


# ----------------------------------------------------------------- south


func south() -> void:
	b.room(11, 44, 31, 48, "concrete", d["tunnel"], {"skin": "cinder", "light": .6, "roof": 2.3})
	b.gap(10, 45, "e")
	b.gap(10, 46, "e")
	b.gap(10, 47, "e")
	for at: Vector2 in [Vector2(14.5, 44.5), Vector2(19.5, 48.5), Vector2(25.5, 44.5)]:
		b.crate_stack(at.x, at.y)
	b.town("pallet_stack", 22.5, 48.5, {"solid": .36})
	b.town("pallet_stack", 29.5, 44.5, {"solid": .36})
	b.prop("lamp", 17.5, 46.5)
	b.prop("lamp", 27.5, 46.5)
	b.gap(32, 45, "w")
	b.gap(32, 46, "w")
	b.gap(32, 47, "w")
	b.yard(33, 42, 41, 49, "dirt", d["b"])
	b.car(37.0, 48.0, true)
	b.bale(35.5, 42.5)
	b.crate_stack(40.5, 43.5)
	# The warehouse: site B.
	b.room(43, 36, 54, 49, "wood", d["b"], {"skin": "brick", "light": .72, "roof": 3.2})
	b.paint(44, 38, 53, 48, "floor_tile")
	b.paint(45, 39, 52, 47, "wood")
	b.gap(42, 44, "w")
	b.gap(42, 45, "w")
	b.gap(42, 46, "w")
	b.town("pallet_stack", 46.5, 41.5, {"solid": .38})
	b.town("pallet_stack", 49.5, 47.5, {"solid": .38})
	b.town("forklift", 50.5, 41.5, {"solid": .42})
	b.town("powder_shelf", 53.5, 37.5, {"solid": .36})
	b.town("powder_shelf", 53.5, 43.5, {"solid": .36})
	b.crate_stack(45.5, 45.5, 1.1)
	b.crate_stack(47.5, 37.5)
	b.town("lumber_stack", 44.5, 48.5, {"solid": .4})
	b.prop("lamp", 48.5, 44.5)


# ------------------------------------------------------------------ east


func east() -> void:
	b.yard(57, 18, 63, 34, "asphalt", d["coop"])
	b.paint(58, 19, 62, 33, "concrete")
	b.prop("pickup_truck", 62.5, 18.5)
	b.fixture(61.8, 18.1, 63.2, 18.9, .3, "mill_tin", "tin")
	b.prop("pump", 57.5, 33.5)
	b.town("mailbox_row", 63.5, 33.5)
	b.streetlamp(63.5, 25.5, 4.6)
	# North to A, through a gap in the stock fence.
	b.yard(57, 6, 62, 17, "asphalt", d["coop"])
	b.fence(57, 9, 57, 13)
	b.town("fuel_tank", 61.5, 7.5, {"solid": .44})
	b.town("propane_tank", 61.5, 13.5, {"solid": .36})
	# South to B, in through the warehouse's back door.
	b.yard(57, 35, 62, 45, "asphalt", d["coop"])
	b.room(55, 40, 56, 42, "wood", d["b"], {"skin": "brick", "light": .7, "roof": 2.4})
	b.town("cable_spool", 61.5, 44.5, {"solid": .34})
	b.town("tire_stack", 57.5, 36.5, {"solid": .34})
	b.label("TRUCK LOT", 4, 27)
	b.label("BELT HOUSE", 31, 6)
	b.label("A", 50, 9)
	b.label("RAIL YARD", 28, 25)
	b.label("SCALE OFFICE", 34, 38)
	b.label("FEED TUNNEL", 16, 46)
	b.label("B", 48, 43)
	b.label("CO-OP LOT", 58, 26)
