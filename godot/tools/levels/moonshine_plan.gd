## The Moonshine Run (chapter 7): Copperhead Ridge by night. Granny
## Hooten's last load of triple-X waits in her tobacco barn; the Revenue Man
## has her still up the ridge as evidence and his agents have the backroads
## shut. A dirt road runs from her farm (south-west, the start) over the low
## water bridge on Mule Creek (the first roadblock), round Little Bethel
## church and its graveyard, onto the county blacktop, a loop the revenue
## cruisers patrol with their light bars going; out of the loop Buzzard Knob
## and its radio mast (north-west), Snake Holler and Skeeter's trailer
## (south-east). North-east the ridge road climbs from the county line
## checkpoint (the second roadblock) through the log gate and the switchbacks
## to the revenue camp on top, and the still cave in the bluff behind it.
## Stations: load the shine (the barn), cut the revenue radio (the knob),
## ring the church bell (the log gate opens), then bang on the still cave's
## door: the Revenue Man is inside with Granny's still wired to blow.
##
## The stock car is in the barn with the keys in it: the MOONSHINE RUN set
## piece (vehicle_runs) drives the load from the barn through both roadblocks
## to the county line against the clock.
##
## Built by tools/levels/build_level.gd -- moonshine. The cast, pickups, set
## pieces and dressing are in moonshine_cast.gd.
extends RefCounted

const Climbs := preload("res://tools/levels/climbs.gd")
const SetPieces := preload("res://tools/levels/set_piece_kit.gd")
const Cast := preload("res://tools/levels/moonshine_cast.gd")
const Builder := preload("res://tools/levels/level_builder.gd")
const W := 128
const H := 96
## The ridge top's ground: the camp, the cave, the top of the switchbacks.
const TOP := 1.92
## The tiles of the woods, the bluffs and the cave.
const WOODS := "ridge_pines"
const ROCK := "ridge_rock"
const CAVE_FLOOR := "cave_floor"
## The blacktop loop the cruisers patrol: its outer edge (cells) and lane.
const LOOP := Rect2i(18, 36, 90, 24)
## Moonlit open ground's light, and under the trees.
const MOON := .62
const DARK := .5

var b: Builder
var farm: int
var barn: int
var creek: int
var bridge: int
var church: int
var graves: int
var backroad: int
var blacktop: int
var knob: int
var deer: int
var holler: int
var checkpoint: int
var switchbacks: int
var camp: int
var cave: int


func make() -> Builder:
	b = Builder.new("moonshine", W, H, WOODS)
	b.riser_tiles = {
		"grass": ROCK,
		"dirt": ROCK,
		"tracks": ROCK,
		CAVE_FLOOR: ROCK,
		"gravel": ROCK,
	}
	b.meta = {
		"title": "THE MOONSHINE RUN",
		"heading": ["COPPERHEAD RIDGE", "THE MOONSHINE RUN"],
		"intro": "LOAD GRANNY'S SHINE, CUT THE REVENUE RADIO AND RING THE CHURCH BELL.",
		"ending": '"GRANNY SAYS THE TAX IS PAID IN FULL."',
		"score": "moonshine_score",
		"ambience": "ridge",
		"layout": 1,
		"sky": "moonshine_sky",
		"control_name": "THE RUN: SHINE, RADIO, BELL",
		"extraction": {"x": 99.5, "y": 10.6, "label": "HAUL THE LAST JAR HOME", "shutdown": "cave"},
		"return_gate": {"destination": "hub", "x": 9.5, "y": 94.4, "width": 3.5, "side": -1},
		"wave": ["cave-revenue-man", "cave-agent-a", "cave-agent-b", "cave-buster"],
	}
	return b


func build(_b) -> Array:
	farm = b.district("GRANNY HOOTEN'S PLACE", Color(1.0, .96, .9))
	barn = b.district("THE TOBACCO BARN", Color(1.04, .96, .86))
	creek = b.district("MULE CREEK", Color(.88, .96, 1.06))
	bridge = b.district("LOW WATER BRIDGE", Color(.92, .96, 1.06))
	church = b.district("LITTLE BETHEL CHURCH", Color(1.0, 1.0, 1.06))
	graves = b.district("BETHEL GRAVEYARD", Color(.9, .96, 1.04))
	backroad = b.district("THE BACKROAD", Color(.96, .96, 1.02))
	blacktop = b.district("COUNTY BLACKTOP", Color(.94, .96, 1.04))
	knob = b.district("BUZZARD KNOB", Color(.92, .98, 1.04))
	deer = b.district("DEER CAMP", Color(1.0, .96, .9))
	holler = b.district("SNAKE HOLLER", Color(.88, .98, .96))
	checkpoint = b.district("COUNTY LINE CHECKPOINT", Color(1.0, .96, 1.04))
	switchbacks = b.district("THE SWITCHBACKS", Color(.94, .96, 1.04))
	camp = b.district("REVENUE CAMP", Color(1.02, .98, .96))
	cave = b.district("THE STILL CAVE", Color(1.06, .94, .84))
	granny_place()
	tobacco_barn()
	mule_creek()
	the_backroad()
	little_bethel()
	the_blacktop()
	buzzard_knob()
	deer_camp()
	snake_holler()
	county_line()
	the_switchbacks()
	revenue_camp()
	still_cave()
	var cast := Cast.new()
	cast.dress(self)
	moonshine_run()
	b.meta["area_sounds"] = {
		str(creek): "creek", str(bridge): "creek", str(barn): "barn", str(cave): "room"
	}
	Climbs.moonshine(b)
	set_pieces()
	hazards()
	woods_heights()
	return [9.5, 92.5, -PI / 2]


# ------------------------------------------------------------- set pieces


## The big breaks (set_piece_kit.gd, features/set_pieces.gd): Granny's
## tobacco curing shed south of the barn, hay hung and stacked in it, open to
## the lane (it goes over east or west, off the barn's door); the revenue
## camp's water tank by the cave (it goes over south or west across the
## camp, flooding it, never into the bluff); and the camp's fuel line from
## the drums by the generator round to a propane tank under the lights.
func set_pieces() -> void:
	SetPieces.barn(b, "curing-shed", 22.0, 89.4, 0, {"w": 8.0, "d": 4.6, "falls": [0, 2]})
	SetPieces.plank_floor(b, 18, 87, 25, 91)
	for spot: Array in [[18.6, 87.6], [19.5, 87.5], [24.6, 87.7], [25.4, 90.6], [21.0, 87.5]]:
		b.town("range_hay_bale", spot[0], spot[1])
	SetPieces.tower(b, "camp-tank", 104.5, 4.5, {"falls": [1, 2]})
	SetPieces.fuel(
		b,
		"camp-line",
		[[100.0, 4.4], [100.0, 6.6], [96.5, 6.6], [96.5, 11.5]],
		[[99.5, 3.5], [100.5, 3.5]]
	)
	stand("propane_tank", 97.5, 11.5, .35)


## What a brawl can use (features/brawl.gd): Granny's well in the yard, a
## burn barrel at the camp, the bug zapper on the church's porch light.
func hazards() -> void:
	stand("well", 7.5, 75.5, .5)
	stand("burn_barrel", 74.5, 11.5, .25, {"glow": true})
	b.glow(74.5, 11.5, 3.0, .34)
	b.town("bug_zapper", 50.5, 72.5, {"solid": .12, "glow": true})


# ------------------------------------------------------------------ helpers


## Open ground under the moon.
func open(x0: int, y0: int, x1: int, y1: int, floor_name: String, area: int, o := {}) -> void:
	var opts := o.duplicate()
	if not opts.has("light"):
		opts["light"] = MOON
	b.yard(x0, y0, x1, y1, floor_name, area, opts)


## A clump of woods left standing in open ground.
func thicket(x0: int, y0: int, x1: int, y1: int, top := 3.0) -> void:
	b.wall(x0, y0, x1, y1, WOODS, top)


## A pool of lantern light round a lantern post standing at (x, y).
func lantern(x: float, y: float, reach := 3.4) -> void:
	stand("lantern_post", x, y, .1, {"glow": true})
	b.glow(x, y, reach, .34)


## The ground of the cell under (x, y).
func floor_at(x: float, y: float) -> float:
	return float(b.ground[b.at(int(x), int(y))])


## A town prop standing on its cell's own floor (the knob's rises, the ridge
## top), its base `r` wide blocking the way from that floor up (town()'s
## base is for the ground at 0).
func stand(name: String, x: float, y: float, r := .42, o := {}) -> void:
	var px := floorf(x) + .5
	var py := floorf(y) + .5
	var floor_z := floor_at(x, y)
	b.fixture(px - r, py - r, px + r, py + r, floor_z + .05, "dirt", "dirt", floor_z)
	b.town(name, px, py, o)


## A desk-high box on its cell's own floor (a table, a counter).
func desk(x0: float, y0: float, x1: float, y1: float, high := .78, side := "wood") -> void:
	var floor_z := floor_at((x0 + x1) * .5, (y0 + y1) * .5)
	b.fixture(x0, y0, x1, y1, floor_z + high, side, "counter_top", floor_z)


## A parked car's model over the box it fills (a cruiser at a roadblock, in
## the camp), on its cell's own floor, along x or along y.
func parked(model: String, x: float, y: float, along_x: bool) -> void:
	var lx := 2.6 if along_x else 1.4
	var ly := 1.4 if along_x else 2.6
	var floor_z := floor_at(x, y)
	b.volume(x - lx * .5, y - ly * .5, x + lx * .5, y + ly * .5, floor_z + .5)
	b.town(model, x, y, {"plane": 0.0 if along_x else PI * .5, "hung": true, "glow": true})


## The woods everywhere nobody cleared: taller toward the ridge, uneven so
## the tree line does not read as a hedge.
func woods_heights() -> void:
	var tile_id := b.t(WOODS)
	for y in H:
		for x in W:
			var i := b.at(x, y)
			if int(b.solid[i]) != tile_id:
				continue
			var lift := 3.0 + .4 * sin(x * .7 + y * 1.3) + .3 * sin(x * 1.9 - y * .6)
			if y < 34 and x > 56:
				lift += TOP
			b.wall_height[i] = snappedf(lift, .01)


# ------------------------------------------------------- Granny Hooten's place


## Granny's farm: the house with its porch, the smokehouse with her own
## stash behind its back wall, the outhouse, the water tower, the coop, the
## lane in from the county road (the way home).
func granny_place() -> void:
	open(1, 63, 34, 94, "grass", farm)
	b.paint(12, 73, 33, 88, "dirt")
	b.paint(8, 84, 11, 94, "tracks")
	b.paint(12, 86, 15, 88, "tracks")
	b.arch(9.5, 94.4, 3.5, "route_hub")
	b.board("hub_road_stake", 11.9, 93.6, .97, {"plane": PI, "back": "hub_road_stake_back"})
	# The house: weathered boards, a porch along its east side.
	(
		b
		. building(
			2,
			65,
			11,
			73,
			farm,
			{
				"wall": "bayou_shack",
				"roof": 2.5,
				"floor": "wood",
				"windows": 3,
				"lit": .9,
				"light": .82,
				"skin": "bayou_shack",
				"ceiling": "joists",
			}
		)
	)
	b.door(11, 69, true, {"from": "w", "id": "house-front"})
	b.door(6, 73, false, {"from": "n", "id": "house-back"})
	b.room(12, 66, 13, 72, "porch", farm, {"roof": 2.1, "ceiling": "joists", "light": .9})
	b.raise(12, 66, 13, 72, .12)
	for y in [65.95, 69.0, 72.95]:
		b.fixture(13.84, y - .06, 13.96, y + .06, 2.1, "wood", "counter_top", .12)
	b.town("rocker", 12.6, 67.5)
	b.town("porch_couch", 12.7, 71.2)
	b.prop("lamp", 12.5, 69.0)
	b.glow(13.0, 69.0, 4.0, .34)
	# Inside: the kitchen table with Granny's note on it, the stove, the radio.
	b.table(4.2, 67.2, 6.8, 68.3, .78)
	b.board("county_note", 5.5, 67.75, .3, {"z": .78, "plane": 0.0})
	b.notes.append(
		[
			5.5,
			67.75,
			"GRANNY'S NOTE",
			"LOAD'S IN THE BARN. REVENUE MAN TOOK MY STILL UP THE RIDGE. RING THE BELL FOR DEWEY.",
			.78
		]
	)
	b.react("tv", 2.6, 71.0, .9, {"id": "granny-radio"})
	b.fixture(9.2, 65.6, 10.8, 66.6, .92, "counter", "counter_top")
	b.prop("lamp", 6.0, 70.0)
	b.glow(6.0, 70.0, 3.0, .2)
	# The smokehouse, and the jars Granny keeps behind its back wall.
	b.building(
		3,
		77,
		8,
		81,
		farm,
		{"wall": "bayou_shack", "roof": 2.3, "floor": "dirt", "light": .55, "ceiling": "joists"}
	)
	b.door(5, 77, false, {"from": "s", "id": "smokehouse"})
	b.wall(3, 82, 8, 85, "bayou_shack", 2.3)
	b.room(4, 82, 7, 84, "dirt", farm, {"roof": 2.1, "light": .45, "skin": "bayou_shack"})
	b.secret(
		5, 81, false, [4, 82, 7, 84], {"from": "n", "id": "granny-stash", "tile": "bayou_shack"}
	)
	# The yard: the outhouse, the water tower, the coop, the wash line, the
	# woodpile, the dog's empty house, the truck that quit.
	b.town("outhouse", 14.5, 91.5)
	b.town("chicken_coop", 2.5, 88.5, {"solid": .45})
	b.town("laundry", 9.5, 76.5)
	b.town("log_pile", 15.5, 80.5, {"solid": .45})
	b.town("axe_stump", 14.5, 82.5, {"solid": .3})
	b.town("doghouse", 14.5, 74.5, {"solid": .35})
	b.car(30.5, 89.5, false, "tin")
	b.town("tractor", 4.5, 92.5, {"solid": .45})
	b.prop("mailbox", 12.4, 92.2)
	b.town("burn_barrel", 15.5, 85.5, {"solid": .25, "glow": true})
	b.glow(15.5, 85.5, 3.0, .34)
	thicket(1, 63, 3, 64)
	thicket(26, 63, 34, 66)
	thicket(32, 86, 34, 94)
	b.prop("tree", 2.5, 75.5)
	b.prop("tree_b", 33.5, 70.5)
	b.prop("tree", 27.5, 93.0)
	lantern(9.6, 84.6)


## The tobacco barn: tall and dark, the curing racks overhead, the stock car
## inside loaded but for the last crate, the big doors east shut till it is.
func tobacco_barn() -> void:
	(
		b
		. building(
			16,
			68,
			31,
			85,
			barn,
			{
				"wall": "barn",
				"roof": 3.6,
				"floor": "dirt",
				"windows": 4,
				"lit": .35,
				"light": .62,
				"ceiling": "joists",
			}
		)
	)
	for y in range(75, 79):
		b.controlled(31, y, true, {"from": "w", "id": "barn-door-%d" % y, "style": "slide"})
	b.door(23, 85, false, {"from": "n", "id": "barn-south"})
	b.door(16, 77, true, {"from": "e", "id": "barn-west"})
	# The tack room in the north-east corner: Granny's reserve, behind a brass lock.
	b.wall(27, 69, 27, 72, "barn", 3.0)
	b.wall(28, 72, 30, 72, "barn", 3.0)
	b.room(28, 69, 30, 71, "wood", barn, {"roof": 2.4, "light": .5, "skin": "barn"})
	b.door(29, 72, false, {"from": "s", "id": "tack-room", "key": "key_brass"})
	# The stock car, its trunk to the station, its nose to the doors.
	b.meta["vehicles"] = [["car", 26.2, 76.5, 0.0]]
	b.meta["vehicle_lines"] = {"car": "GRANNY'S RUNNER'S GOT THE KEYS IN IT. LOAD HER UP."}
	b.board("vehicle_sign_car", 27.5, 73.06, .5, {"z": .95, "plane": PI, "hung": true})
	b.station(
		"trunk",
		22.4,
		76.5,
		"LOAD GRANNY'S SHINE",
		"TWENTY JARS OF TRIPLE-X IN THE TRUNK. THE BARN DOORS ARE OPEN. DRIVE SOFT.",
		{"opens": [[31, 75], [31, 76], [31, 77], [31, 78]], "sectors": [barn], "cue": "close"}
	)
	b.quest("quest_shine_load", 21.5, 76.5, "trunk")
	# Bales along the west wall under the loft, the racks of leaf overhead.
	for y in [70, 73, 80, 83]:
		b.bale(17.5, y + .5)
	for x in [19.0, 23.0, 27.0]:
		b.panel(x, 68.5, x, 84.5, "wood", 2.6, 2.7, .7)
	b.town("hay_wagon", 22.5, 82.5, {"solid": .45})
	b.town("tool_chest", 30.5, 82.5, {"solid": .3})
	b.town("jug_stack", 24.5, 70.5, {"solid": .3})
	b.town("jug_stack", 25.5, 70.5, {"solid": .3})
	for p in [Vector2(21.0, 72.0), Vector2(27.0, 80.0)]:
		b.prop("lamp", p.x, p.y)
		b.glow(p.x, p.y, 3.6, .22)
	lantern(32.6, 73.6)


# ------------------------------------------------------- the creek and the road


## Mule Creek runs south out of the woods past the farm, a step down into
## the water: a man wades it, the car does not climb out of it.
func mule_creek() -> void:
	open(38, 60, 43, 94, "dirt", creek, {"light": DARK})
	b.yard(39, 60, 42, 94, "creek", creek, {"ground": -.24, "light": DARK})
	for y in [62, 68, 84, 90]:
		b.prop("reeds", 38.5, y + .5)
		b.prop("reeds", 43.5, y + 2.5)
	b.town("dead_snag", 43.5, 65.5, {"solid": .2})
	b.town("boulder_a", 38.5, 87.5, {"solid": .4})
	b.town("heron", 41.0, 92.0)


## The dirt road: out of the barn doors, over the low water bridge, past the
## church and north up the curve to the blacktop.
func the_backroad() -> void:
	open(32, 74, 37, 80, "tracks", backroad)
	b.paint(32, 74, 37, 74, "dirt")
	b.paint(32, 80, 37, 80, "dirt")
	# The low water bridge: a concrete slab at the road's height, the creek
	# running round its ends.
	open(38, 75, 43, 79, "concrete", bridge)
	b.paint(38, 75, 43, 75, "gravel")
	b.paint(38, 79, 43, 79, "gravel")
	for x in [38.1, 43.9]:
		for y in [75.1, 79.9]:
			b.fixture(x - .08, y - .08, x + .08, y + .08, .55, "concrete", "concrete")
	b.board("moonshine_low_water", 37.6, 74.06, .7, {"z": .4, "plane": 0.0})
	open(44, 75, 63, 79, "tracks", backroad)
	open(64, 60, 67, 79, "tracks", backroad)
	b.paint(64, 79, 67, 79, "dirt")
	# The ditch along the road's north side by the church, and the church's
	# lot opening off the road.
	open(44, 74, 47, 74, "dirt", backroad)
	open(48, 74, 63, 74, "grass", church)


## Little Bethel: a white church on the rise with its bell up the steeple,
## the graveyard east of it in an iron fence, a secret under the pulpit.
func little_bethel() -> void:
	open(44, 60, 63, 73, "grass", church)
	open(59, 60, 63, 73, "grass", graves)
	b.paint(46, 72, 56, 73, "dirt")
	(
		b
		. building(
			48,
			61,
			57,
			71,
			church,
			{
				"wall": "plaster",
				"roof": 3.2,
				"floor": "wood",
				"windows": 2,
				"lit": .85,
				"light": .8,
				"skin": "plaster",
				"ceiling": "joists",
			}
		)
	)
	b.door(52, 71, false, {"from": "n", "id": "church-door"})
	b.door(53, 71, false, {"from": "n", "id": "church-door-b"})
	# The steeple over the door: stages of white boards and a tin spire.
	b.tower(51.0, 70.0, 55.0, 72.0, 3.2, 4.6, "plaster")
	b.tower(51.6, 70.4, 54.4, 71.6, 4.6, 6.0, "plaster", .8)
	b.tower(52.4, 70.6, 53.6, 71.4, 6.0, 7.2, "tin", .7)
	b.station(
		"bell",
		52.5,
		69.6,
		"RING THE CHURCH BELL",
		"THE BELL CARRIES UP THE RIDGE. COUSIN DEWEY'S PULLIN' THE LOG GATE.",
		{
			"opens": [[92, 27], [93, 27], [94, 27], [95, 27]],
			"sectors": [church],
			"cue": "church_bell"
		}
	)
	b.quest("quest_bell_rope", 53.5, 69.5, "bell")
	# Pews either side of the aisle, the pulpit, the piano.
	for y in [63, 65, 67]:
		b.fixture(49.3, y + .3, 51.7, y + .8, .55, "wood", "counter_top")
		b.fixture(54.3, y + .3, 56.7, y + .8, .55, "wood", "counter_top")
	b.fixture(52.0, 62.2, 53.0, 62.8, 1.05, "wood", "counter_top")
	b.board("moonshine_hymn_board", 56.94, 64.5, .6, {"z": 1.2, "plane": -PI / 2})
	for p in [Vector2(49.5, 62.5), Vector2(55.5, 62.5), Vector2(52.5, 66.5)]:
		b.prop("lamp", p.x, p.y)
		b.glow(p.x, p.y, 3.0, .2)
	# Under the pulpit: the preacher's own stock.
	b.wall(50, 57, 55, 60, "plaster", 2.6)
	b.room(51, 58, 54, 60, "wood", church, {"roof": 2.2, "light": .45, "skin": "plaster"})
	b.secret(
		52, 61, false, [51, 58, 54, 60], {"from": "s", "id": "pulpit-stash", "tile": "plaster"}
	)
	b.board("moonshine_church_sign", 48.0, 73.97, .8, {"z": .6, "plane": PI, "hung": true})
	b.fixture(46.93, 73.93, 47.07, 74.07, 1.4, "wood", "wood")
	b.fixture(48.93, 73.93, 49.07, 74.07, 1.4, "wood", "wood")
	# The graveyard in its fence: the stones, the dead oak, a fresh hole.
	b.wall(58, 60, 58, 70, "fair_iron", 1.2)
	b.wall(59, 60, 63, 60, "fair_iron", 1.2)
	b.wall(59, 73, 63, 73, "fair_iron", 1.2)
	b.gap(58, 71, "e")
	var stones := ["tombstone_a", "tombstone_b", "tombstone_c"]
	var k := 0
	for y in [62, 64, 66, 68, 70]:
		for x in [60, 62]:
			if (x + y) % 3 == 0:
				continue
			b.town(String(stones[k % 3]), x + .5, y + .5, {"solid": .2})
			k += 1
	b.town("dead_snag", 62.5, 71.5, {"solid": .2})
	b.paint(60, 71, 61, 71, "dirt")
	lantern(59.5, 61.5)
	lantern(44.5, 60.5)


# ------------------------------------------------------------- the blacktop


## The county blacktop: a paved loop round the woods between the knob and
## the holler, the cruisers running it with their lights going.
func the_blacktop() -> void:
	var r := LOOP
	var x1 := r.end.x - 1
	var y1 := r.end.y - 1
	open(r.position.x, r.position.y, x1, r.position.y + 3, "asphalt", blacktop)
	open(r.position.x, y1 - 3, x1, y1, "asphalt", blacktop)
	open(r.position.x, r.position.y, r.position.x + 3, y1, "asphalt", blacktop)
	open(x1 - 3, r.position.y, x1, y1, "asphalt", blacktop)
	b.paint(r.position.x + 4, r.position.y + 1, x1 - 4, r.position.y + 2, "asphalt")
	b.paint(r.position.x + 5, r.position.y + 2, x1 - 5, r.position.y + 2, "road")
	b.paint(r.position.x + 5, y1 - 2, x1 - 5, y1 - 2, "road")
	# The cruisers' beat, counter-clockwise seen from above.
	b.meta["lap_cars"] = {
		"path": patrol_line(),
		"cars": 2,
		"speed": 7.2,
		"stop_at": "radio",
		"damage": 30,
		"model": "town_cruiser",
		"nose": 0.0,
		"siren": true,
		"laps": false,
		"dry": "THE CRUISERS LOST THEIR RADIO. THEY'RE PULLIN' OVER.",
	}
	for p in [
		Vector2(30.0, 59.6),
		Vector2(56.0, 59.6),
		Vector2(80.0, 59.6),
		Vector2(98.0, 35.4),
		Vector2(60.0, 35.4),
		Vector2(26.0, 35.4)
	]:
		b.prop("utilitypole", p.x, p.y)
	b.board("moonshine_county_line", 103.94, 47.0, .8, {"z": .7, "plane": -PI / 2})
	b.board("moonshine_speed_sign", 22.06, 47.0, .7, {"z": .9, "plane": PI / 2})


## The patrol's line, a lane in from the loop's outer edge.
func patrol_line() -> Array:
	var x0 := LOOP.position.x + 1.6
	var y0 := LOOP.position.y + 1.6
	var x1 := LOOP.end.x - 1.6
	var y1 := LOOP.end.y - 1.6
	var c := 3.0
	return [
		[x0 + c, y1],
		[x1 - c, y1],
		[x1, y1 - c],
		[x1, y0 + c],
		[x1 - c, y0],
		[x0 + c, y0],
		[x0, y0 + c],
		[x0, y1 - c],
	]


## Buzzard Knob: a wooded hill north-west of the blacktop, its top cleared
## for the revenue men's radio mast and the cruiser that brought it.
func buzzard_knob() -> void:
	open(3, 3, 50, 33, "grass", knob, {"light": DARK})
	var c := Vector2(24.0, 16.0)
	for y in range(3, 34):
		for x in range(3, 51):
			var d := Vector2((x + .5 - c.x) / 20.0, (y + .5 - c.y) / 12.5).length()
			var up := snappedf(clampf((1.05 - d) * 1.5, 0.0, .96), .24)
			b.ground[b.at(x, y)] = up
	# The way up from the blacktop: a dirt track, the woods either side.
	open(23, 30, 26, 35, "tracks", knob)
	b.paint(22, 12, 27, 22, "dirt")
	for p in [
		[3, 3, 10, 9],
		[42, 3, 50, 8],
		[3, 26, 9, 33],
		[44, 26, 50, 33],
		[13, 22, 16, 25],
		[33, 7, 36, 10],
		[36, 24, 40, 27],
	]:
		thicket(p[0], p[1], p[2], p[3])
	for p in [
		Vector2(12.5, 12.5),
		Vector2(18.5, 7.5),
		Vector2(30.5, 6.5),
		Vector2(38.5, 16.5),
		Vector2(10.5, 20.5),
		Vector2(31.5, 26.5),
		Vector2(44.5, 18.5),
	]:
		b.prop("tree" if int(p.x) % 2 else "tree_b", p.x, p.y)
	# The mast, guyed out, its red lamp up top; the radio set on its table.
	stand("radio_mast", 24.5, 15.5, .45, {"glow": true})
	b.glow(24.5, 15.5, 5.0, .2)
	desk(22.2, 17.6, 24.8, 18.4)
	b.station(
		"radio",
		23.5,
		18.6,
		"CUT THE REVENUE RADIO",
		"RADIO'S DEAD. THEM CRUISERS CAN'T CALL YOU IN NO MORE.",
		{"sectors": [knob, blacktop], "cue": "broadcast_cut"}
	)
	b.quest("quest_radio_set", 23.5, 18.0, "radio", {"z": .78, "scale": .6})
	stand("generator", 27.5, 18.5)
	stand("revenue_tent", 20.5, 13.5, .9)
	parked("cruiser", 28.5, 13.5, true)
	stand("floodlight_tower", 26.5, 20.5, .25, {"glow": true})
	b.glow(26.5, 20.5, 7.0, .3)
	b.board("moonshine_radio_sign", 22.0, 18.94, .5, {"z": .8, "plane": PI})


## The woods inside the loop: a hunting camp in a clearing with a path
## across from leg to leg, so a man on foot cuts the corner.
func deer_camp() -> void:
	open(62, 42, 82, 53, "grass", deer, {"light": DARK})
	open(70, 40, 71, 55, "dirt", deer, {"light": DARK})
	b.paint(64, 46, 80, 48, "dirt")
	b.building(
		64,
		43,
		69,
		47,
		deer,
		{"wall": "bayou_shack", "roof": 2.2, "floor": "wood", "windows": 3, "lit": .7, "light": .7}
	)
	b.door(66, 47, false, {"from": "n", "id": "deer-cabin"})
	b.town("deer_target", 76.5, 44.5)
	b.town("camp_chairs", 74.5, 50.5)
	b.town("burn_barrel", 76.5, 50.5, {"solid": .25, "glow": true})
	b.glow(76.5, 50.5, 3.2, .34)
	b.prop("pickup_truck", 79.0, 47.0)
	b.town("cooler", 73.5, 51.5)
	thicket(62, 50, 66, 53)
	thicket(78, 42, 82, 44)


## Snake Holler: south of the blacktop, down a footpath into the dark. The
## revenue men already busted one still here; Skeeter Pruitt, who told them
## where, has his trailer at the bottom with Granny's barn key in it.
func snake_holler() -> void:
	open(84, 60, 86, 65, "dirt", holler, {"light": DARK})
	open(74, 64, 98, 76, "grass", holler, {"light": DARK})
	open(98, 66, 124, 80, "grass", holler, {"light": DARK})
	open(86, 80, 112, 93, "grass", holler, {"light": DARK})
	b.paint(84, 64, 86, 72, "dirt")
	b.paint(86, 70, 104, 72, "dirt")
	b.paint(100, 72, 102, 84, "dirt")
	for p in [
		[74, 64, 79, 67],
		[93, 64, 98, 66],
		[74, 73, 80, 76],
		[110, 66, 124, 68],
		[118, 76, 124, 80],
		[86, 80, 92, 84],
		[106, 88, 112, 93],
		[94, 74, 98, 78],
	]:
		thicket(p[0], p[1], p[2], p[3])
	# Skeeter's trailer and his junk.
	b.trailer(78, 68, "s", holler)
	b.town("wreck_pickup", 90.5, 67.5, {"solid": .45})
	b.town("washer", 82.5, 73.5, {"solid": .3})
	b.town("porch_couch", 83.0, 72.6)
	b.town("burn_barrel", 87.5, 73.5, {"solid": .25, "glow": true})
	b.glow(87.5, 73.5, 3.0, .34)
	b.notes.append(
		[
			80.6,
			69.5,
			"REWARD SLIP",
			"U.S. REVENUE. PAID TO S. PRUITT: $40 FOR INFO ON H. STILL. KEEP YOUR MOUTH SHUT.",
			.78
		]
	)
	b.table(79.4, 69.2, 81.8, 69.8, .78)
	b.board("county_note", 80.6, 69.5, .3, {"z": .78, "plane": 0.0})
	# The busted still: axed barrels, a split pot, the agents' axe in a stump.
	b.paint(104, 70, 116, 77, "dirt")
	b.town("still", 110.5, 73.5, {"solid": .45})
	b.town("mash_barrel", 108.5, 71.5, {"solid": .3})
	b.town("mash_barrel", 113.5, 75.5, {"solid": .3})
	b.town("axe_stump", 106.5, 75.5, {"solid": .3})
	b.town("jug_stack", 114.5, 71.5, {"solid": .3})
	b.board("moonshine_seized_tag", 110.5, 72.94, .4, {"z": .6, "plane": PI})
	lantern(105.6, 72.4)
	# The sinkhole: two steps down into the dark, a crack in its east wall.
	for y in range(84, 91):
		for x in range(94, 104):
			var d := Vector2(x + .5 - 99.0, (y + .5 - 87.5) * 1.3).length()
			if d < 3.2:
				b.ground[b.at(x, y)] = -.48
			elif d < 4.6:
				b.ground[b.at(x, y)] = -.24
	b.wall(104, 85, 108, 85, ROCK, 1.8)
	b.wall(104, 89, 108, 89, ROCK, 1.8)
	b.wall(108, 86, 108, 88, ROCK, 1.8)
	b.room(
		104,
		86,
		107,
		88,
		CAVE_FLOOR,
		holler,
		{"roof": 1.9, "light": .4, "skin": ROCK, "ground": -.48}
	)
	b.secret(103, 87, true, [104, 86, 107, 88], {"from": "w", "id": "sinkhole-crack", "tile": ROCK})
	for p in [Vector2(96.5, 77.5), Vector2(116.5, 70.5), Vector2(89.5, 86.5), Vector2(122.5, 73.5)]:
		b.prop("tree" if int(p.y) % 2 else "tree_b", p.x, p.y)


# ---------------------------------------------------------------- the ridge


## The county line checkpoint where the ridge road leaves the blacktop: the
## booth, the arm, a cruiser across half the road and the barricade across
## the rest (rammed through, or walked round at the ditch).
func county_line() -> void:
	open(88, 28, 97, 35, "gravel", checkpoint)
	open(92, 28, 95, 35, "tracks", checkpoint)
	# The shoulder east of the road a step up: a man walks round the
	# barricade there, the car does not.
	b.raise(96, 28, 97, 35, .24)
	b.building(
		87,
		29,
		90,
		33,
		checkpoint,
		{
			"wall": "office_wall",
			"roof": 2.3,
			"floor": "concrete",
			"windows": 2,
			"lit": 1.0,
			"light": .9
		}
	)
	b.door(90, 31, true, {"from": "w", "id": "checkpoint-booth"})
	b.board("moonshine_checkpoint", 91.0, 28.06, .8, {"z": 1.5, "plane": 0.0})
	b.prop("lamp", 88.5, 31.0)
	b.glow(91.5, 31.0, 4.0, .3)
	# The ridge's rock either side of the road above the booth.
	b.wall(84, 15, 91, 27, ROCK, TOP + 1.4)
	b.wall(96, 19, 127, 27, ROCK, TOP + 1.4)
	b.wall(84, 28, 86, 35, ROCK, 1.8)
	b.wall(98, 28, 103, 35, ROCK, 1.8)
	# The log gate the bell opens.
	for x in range(92, 96):
		b.controlled(
			x, 27, false, {"from": "s", "id": "log-gate-%d" % x, "tile": "gate", "roof": 0.0}
		)
	b.board("moonshine_log_gate", 96.0, 27.94, .7, {"z": .6, "plane": PI})


## The switchbacks: north up from the gate, a landing, then east along the
## bluff's face climbing to the top, a step of .12 a cell (the car's).
func the_switchbacks() -> void:
	# Up from the gate to the landing.
	for y in range(19, 27):
		open(92, y, 95, y, "tracks", switchbacks, {"ground": snappedf((27 - y) * .12, .01)})
	open(92, 15, 99, 18, "tracks", switchbacks, {"ground": .96})
	for x in range(100, 108):
		open(x, 15, x, 18, "tracks", switchbacks, {"ground": snappedf(.96 + (x - 99) * .12, .01)})
	open(108, 15, 111, 18, "tracks", switchbacks, {"ground": TOP})
	b.wall(92, 14, 107, 14, ROCK, TOP + 1.2)
	b.wall(91, 15, 91, 18, ROCK, TOP + 1.2)
	b.wall(112, 15, 112, 18, ROCK, TOP + 1.2)
	# A rail of rock along the drop, and the car that went over it.
	for x in [97, 101, 105]:
		b.fixture(x + .1, 18.6, x + .9, 18.95, b.ground[b.at(x, 18)] + .45, ROCK, ROCK)
	b.board("moonshine_switchback", 96.5, 14.94, .6, {"z": 1.4, "plane": PI})


## The revenue camp on the ridge top: their tents, the evidence table with
## Granny's jars on it, the Revenue Man's trailer, the generator and the
## lights, the water tank, the fire lookout over the valley.
func revenue_camp() -> void:
	open(58, 2, 111, 13, "gravel", camp, {"ground": TOP, "light": .66})
	open(108, 13, 111, 14, "tracks", camp, {"ground": TOP})
	b.paint(60, 2, 72, 13, "grass")
	b.wall(57, 0, 57, 14, ROCK, TOP + 1.4)
	b.wall(57, 14, 91, 14, ROCK, TOP + 1.2)
	# Tents in a row, the table between them.
	for x in [63.5, 69.5, 75.5]:
		stand("revenue_tent", x, 4.5, .9)
	desk(66.2, 8.2, 72.8, 9.0, .82)
	b.town("jug_stack", 67.5, 8.6, {"z": .82})
	b.town("jug_stack", 71.0, 8.6, {"z": .82})
	b.board("moonshine_evidence", 69.5, 9.06, .5, {"z": .7, "plane": 0.0})
	# The Revenue Man's trailer.
	b.trailer(80, 2, "s", camp)
	b.raise(80, 2, 87, 5, TOP)
	(
		b
		. notes
		. append(
			[
				84.0,
				3.6,
				"FIELD REPORT",
				"H. STILL SEIZED. 300 GAL. EVIDENCE. HOLD TILL DAWN THEN DESTROY. DO NOT TASTE IT, PRUITT.",
				TOP + .78
			]
		)
	)
	desk(82.6, 3.2, 85.2, 3.9)
	b.board("county_note", 84.0, 3.6, .3, {"z": .78, "plane": 0.0})
	# Their cars, the generator, the lights and the fuel.
	parked("cruiser", 92.5, 5.5, true)
	parked("cruiser", 92.5, 9.5, true)
	stand("generator", 97.5, 3.5)
	b.fuel_drums.append([99.5, 3.5])
	b.prop("barrel", 99.5, 3.5)
	b.fuel_drums.append([100.5, 3.5])
	b.prop("barrel", 100.5, 3.5)
	for p in [Vector2(78.5, 11.5), Vector2(102.5, 11.5)]:
		stand("floodlight_tower", p.x, p.y, .25, {"glow": true})
		b.glow(p.x, p.y, 8.0, .3)
	b.station(
		"cave",
		110.0,
		7.5,
		"BANG ON THE STILL CAVE DOOR",
		"REVENUE MAN: COME ON IN, SON. BRING THE EVIDENCE.",
		{
			"requires": ["trunk", "radio", "bell"],
			"opens": [[112, 6], [112, 7], [112, 8]],
			"cue": "door"
		}
	)
	b.quest("quest_cave_knocker", 110.5, 5.5, "cave")
	b.quest("quest_exit_jar", 99.5, 11.5, "exit")
	b.board("moonshine_keep_out", 111.94, 5.0, .6, {"z": TOP + .9, "plane": -PI / 2})


## The still cave in the bluff: Granny's copper still at its back with the
## thump keg and the worm, the mash barrels, the jars racked along the rock,
## lanterns on the timbers. The Revenue Man waits by the still with it wired
## to blow; in his last phase it does, and the roof comes down a rock at a
## time (boss_arena; features/boss_arenas.gd).
func still_cave() -> void:
	b.wall(112, 0, 127, 15, ROCK, TOP + 3.6)
	b.room(
		113,
		1,
		126,
		14,
		CAVE_FLOOR,
		cave,
		{"roof": TOP + 3.4, "ground": TOP, "ceiling": ROCK, "light": .62, "skin": ROCK}
	)
	for y in [6, 7, 8]:
		b.controlled(
			112,
			y,
			true,
			{"from": "w", "id": "cave-door" + ("" if y == 7 else "-%d" % y), "tile": "barn"}
		)
	b.raise(112, 6, 112, 8, TOP)
	# The still: the pot on its firebox, the thump keg, the worm in its barrel.
	stand("big_still", 121.5, 7.5, 1.1, {"glow": true})
	b.glow(121.5, 7.5, 5.0, .4)
	# The timbers holding the roof, a lantern on each.
	for p in [Vector2(116.5, 3.5), Vector2(116.5, 11.5), Vector2(123.5, 3.5), Vector2(123.5, 11.5)]:
		b.fixture(p.x - .14, p.y - .14, p.x + .14, p.y + .14, TOP + 3.4, "wood", "wood")
		b.town("hung_lantern", p.x, p.y + .2, {"z": 1.8, "glow": true})
		b.glow(p.x, p.y, 3.4, .26)
	for p in [Vector2(114.5, 2.5), Vector2(125.5, 2.5), Vector2(114.5, 12.5), Vector2(125.5, 12.5)]:
		stand("mash_barrel", p.x, p.y, .3)
	for p in [Vector2(118.5, 1.5), Vector2(119.5, 1.5), Vector2(118.5, 13.5)]:
		stand("jug_stack", p.x, p.y, .3)
	# Rock to get behind: two boulders down the middle.
	stand("boulder_a", 118.5, 4.5, .4)
	stand("boulder_b", 118.5, 11.5, .4)
	# The spring the still draws from, at the back.
	b.paint(125, 5, 126, 9, "creek")
	b.meta["boss_arena"] = {
		"still": [121.5, 7.5],
		"fires": [[119.5, 5.5], [119.5, 9.5], [123.5, 7.5]],
		"rocks":
		[[115.5, 4.5], [115.5, 10.5], [120.0, 3.0], [120.0, 12.0], [124.0, 5.0], [124.0, 10.0]],
	}
	(
		b
		. triggers
		. append(
			{
				"id": "cave-open",
				"when": {"station": "cave"},
				"do":
				[
					{"sound": "sheriff_spot", "at": [118.5, 7.5]},
					{"shake": .3},
					{
						"light":
						{
							"at": [121.5, 7.5],
							"z": TOP + 1.0,
							"color": [1.0, .6, .3],
							"radius": 7.0,
							"strength": 1.4,
							"for": 3.0
						}
					}
				],
			}
		)
	)


# --------------------------------------------------------- the moonshine run


## The stock car's set piece (features/vehicle_runs.gd): KEYS IN IT on the
## barn's wall by the car; out of the barn doors with the load, over the low
## water bridge through the first roadblock, round the church curve, east
## along the blacktop in among the cruisers and up its east leg, west and
## through the county line roadblock before the agents radio ahead. The
## agents at both roadblocks come out of the woods as it starts.
func moonshine_run() -> void:
	var agents := [
		["revenooer", 47.5, 72.5, "run-bridge-a"],
		["still_buster", 49.5, 79.0, "run-bridge-b"],
		["revenooer", 66.5, 64.5, "run-curve"],
		["gas_man", 97.0, 34.5, "run-line-gas"],
		["revenooer", 88.5, 34.5, "run-line-a"],
	]
	var ids: Array = []
	for e in agents:
		b.enemy(String(e[0]), float(e[1]), float(e[2]), String(e[3]))
		ids.append(e[3])
	(
		b
		. triggers
		. append(
			{
				"id": "moonshine-run-agents",
				"when": {"run": "moonshine_run"},
				"do": [{"wake": ids}, {"sound": "sheriff_siren", "at": [44.5, 77.0]}],
			}
		)
	)
	b.meta["vehicle_runs"] = [
		{
			"id": "moonshine_run",
			"title": "THE MOONSHINE RUN",
			"kind": "car",
			"start": [33.5, 77.0, 3.0, "THE BARN DOORS"],
			"way": [1.0, 0.0],
			"gates":
			[
				[45.0, 77.0, 4.0, "THE LOW WATER BRIDGE"],
				[65.5, 68.0, 4.0, "THE CHURCH CURVE"],
				[86.0, 57.5, 4.5, "THE BLACKTOP"],
				[105.5, 47.0, 4.5, "THE EAST LEG"],
				[94.0, 29.0, 2.0, "THE COUNTY LINE"],
			],
			"time": 45.0,
			"reward": ["moonshine", "moonshine", "dynamite", "dynamite", "shells", "rifle_ammo"],
			"intro": "THE MOONSHINE RUN! GET GRANNY'S LOAD PAST THE REVENUERS!",
			"won": "PAST THE COUNTY LINE IN %s! GRANNY'S TIP IS IN THE GLOVEBOX.",
			"lost": "THE REVENUERS RADIOED AHEAD. TRY IT AGAIN.",
		}
	]
