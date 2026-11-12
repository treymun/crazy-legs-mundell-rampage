## The Mothership (chapter 7, the last; layout 1): the ship that sent the
## Alien Sheriff, every room of it indoors, riveted, patched with county tin
## and stuffed with what the greys hauled up. Round the middle the core, a tall
## round chamber under the tractor-beam column where Maw Glorb waits; round the
## core the ring deck, a corridor that goes all the way round, with viewports
## looking into the core; off the ring the rooms. South, where the beam set the
## player down: the tractor-beam bay, a pickup hanging in the beam, the escape
## outhouse parked on its pad. East: the engine room (spike the drive with
## shine), the shine tanks, the corn deck, the cargo hold. West: the specimen
## hold (drain the cow tubes), the probe lab, the crew mess with its stolen
## jukebox, the bunks, the trophy room, Maw's parlor. North: the bridge, where
## the core's iris opens once the drive and the tubes are done. The way out,
## when she falls, is back round the ring to the outhouse.
##
## Built by tools/levels/build_level.gd -- mothership. Its people, pickups and
## the things in each room are mothership_cast.gd.
extends RefCounted

const Builder := preload("res://tools/levels/level_builder.gd")
const Cast := preload("res://tools/levels/mothership_cast.gd")
const W := 128
const H := 100
## The core's middle; the core, its wall, the ring deck and the ring's wall go
## out from it in these radii (cell middles).
const CX := 64.0
const CY := 50.0
const CORE_R := 11.4
const RING_IN := 12.6
const RING_OUT := 15.6
const HULL_R := 16.6
const SHIP := {"ceiling": "ship_ceiling"}

var b: Builder
var bay: int
var ring: int
var core: int
var bridge: int
var trophy: int
var parlor: int
var bunks: int
var mess: int
var specimen: int
var probe: int
var corn: int
var engine: int
var tanks: int
var cargo: int
var ducts: int


func make() -> Builder:
	b = Builder.new("mothership", W, H, "ship_hull")
	b.riser_tiles = {
		"ship_deck": "ship_hull",
		"ship_grate": "ship_hull",
		"ship_lino": "ship_tin",
		"floor_tile": "ship_hull",
		"wood": "ship_tin",
		"dirt": "ship_tin",
	}
	b.meta = {
		"title": "THE MOTHERSHIP",
		"heading": ["MAW'S", "MOTHERSHIP"],
		"intro": "SPIKE THE SHINE DRIVE AND DRAIN THE COW TUBES.",
		"ending": '"TELL YER MAW SHE CAN KEEP THE BUS."',
		"score": "mothership_score",
		"ambience": "mothership",
		"layout": 1,
		"sky": "sky",
		"control_name": "SHIP'S GUTS SCRAMBLED",
		"extraction": {"x": 70.5, "y": 92.5, "label": "RIDE THE OUTHOUSE HOME", "shutdown": "iris"},
		"return_gate": {"destination": "hub", "x": 54.0, "y": 96.4, "width": 3.0, "side": -1},
		"wave": ["core-maw", "core-guard-w", "core-guard-e", "core-drone-n", "core-drone-s"],
		"devices": [["jukebox", 41.5, 39.6]],
	}
	return b


func build(_b) -> Array:
	bay = b.district("TRACTOR BEAM BAY", Color(.96, 1.04, .98))
	ring = b.district("RING DECK", Color(.94, 1.02, 1.03))
	core = b.district("THE CORE", Color(1.08, .94, .96))
	bridge = b.district("THE BRIDGE", Color(.92, .98, 1.08))
	trophy = b.district("TROPHY ROOM", Color(1.06, 1.0, .88))
	parlor = b.district("MAW'S PARLOR", Color(1.06, .96, .98))
	bunks = b.district("CREW BUNKS", Color(.98, .98, 1.04))
	mess = b.district("CREW MESS", Color(1.06, 1.0, .9))
	specimen = b.district("SPECIMEN HOLD", Color(.9, 1.06, .98))
	probe = b.district("PROBE LAB", Color(1.02, .94, 1.08))
	corn = b.district("CORN DECK", Color(1.02, .96, 1.06))
	engine = b.district("ENGINE ROOM", Color(1.08, .96, .86))
	tanks = b.district("SHINE TANKS", Color(1.08, .98, .86))
	cargo = b.district("CARGO HOLD", Color(1.0, .98, .94))
	ducts = b.district("SERVICE DUCTS", Color(.94, .96, 1.0))
	core_and_ring()
	tractor_bay()
	west_wing()
	north_wing()
	east_wing()
	passages()
	secrets()
	Cast.stations(self)
	Cast.enemies(b)
	Cast.pickups(b)
	Cast.dress(self)
	Cast.set_pieces(b)
	labels()
	return [64.5, 92.5, -PI / 2]


# ------------------------------------------------------------------ helpers


func _room(o := {}) -> Dictionary:
	var out := SHIP.duplicate()
	out.merge(o, true)
	return out


## Open, roofed cells along a path of corners (each leg straight).
func carve(points: Array, floor_name: String, district_id: int, o := {}) -> void:
	for i in points.size():
		var p: Vector2i = points[i]
		var q: Vector2i = points[mini(i + 1, points.size() - 1)]
		var step := Vector2i(signi(q.x - p.x), signi(q.y - p.y))
		var c := p
		while true:
			b.room(c.x, c.y, c.x, c.y, floor_name, district_id, _room(o))
			if c == q:
				break
			c += step


## A picture flat on the wall on `side` of a room (n, s, e, w): (x, y) is the
## point on the wall's face, z how far up its foot is.
func on_wall(
	image: String, x: float, y: float, side: String, height: float, z: float, o := {}
) -> void:
	var opts := o.duplicate()
	opts["z"] = z
	match side:
		"n":
			opts["plane"] = 0.0
			y += .04
		"s":
			opts["plane"] = PI
			y -= .04
		"w":
			opts["plane"] = -PI / 2
			x += .04
		"e":
			opts["plane"] = PI / 2
			x -= .04
	b.board(image, x, y, height, opts)


## The same for one of the modelled props (a rack, a shelf).
func town_on_wall(name: String, x: float, y: float, side: String, z: float, o := {}) -> void:
	var opts := o.duplicate()
	opts["z"] = z
	match side:
		"n":
			opts["plane"] = 0.0
			y += .05
		"s":
			opts["plane"] = PI
			y -= .05
		"w":
			opts["plane"] = -PI / 2
			x += .05
		"e":
			opts["plane"] = PI / 2
			x -= .05
	b.town(name, x, y, opts)


## A modelled prop standing in the middle of its cell with a base that is in
## the way, the base on whatever floor the cell has (town()'s own sits at 0,
## which shows over a sunken floor). o.quest: a quest prop lit by that station.
func stand(name: String, x: float, y: float, r := .42, o := {}) -> void:
	var px := floorf(x) + .5
	var py := floorf(y) + .5
	var floor_z: float = b.ground[b.at(int(x), int(y))]
	b.fixture(px - r, py - r, px + r, py + r, floor_z + .05, "ship_hull", "ship_grate", floor_z)
	if o.has("quest"):
		var opts := o.duplicate()
		opts.erase("quest")
		b.quest(name, px, py, String(o["quest"]), opts)
	else:
		b.town(name, px, py, o)


## A desk-high box standing on the cell's own floor (a plinth, a cradle, a desk).
func block(x0: float, y0: float, x1: float, y1: float, high: float, side := "ship_hull") -> void:
	var floor_z: float = b.ground[b.at(int((x0 + x1) * .5), int((y0 + y1) * .5))]
	b.fixture(x0, y0, x1, y1, floor_z + high, side, "ship_grate", floor_z)


## Distance of a cell's middle from the core's.
func dist(x: int, y: int) -> float:
	return Vector2(x + .5 - CX, y + .5 - CY).length()


# ------------------------------------------------------------------ the core


## The core (a round chamber under the beam column), the ring deck round it,
## the viewports between them and the two doors through.
func core_and_ring() -> void:
	var viewports: Array = []
	for y in range(int(CY - HULL_R) - 1, int(CY + HULL_R) + 2):
		for x in range(int(CX - HULL_R) - 1, int(CX + HULL_R) + 2):
			var d := dist(x, y)
			if d <= CORE_R:
				var floor_name := "ship_grate" if d > 8.6 and d < 9.6 else "ship_deck"
				b.room(
					x,
					y,
					x,
					y,
					floor_name,
					core,
					_room({"roof": 8.0, "light": .72, "skin": "ship_core"})
				)
			elif d >= RING_IN and d <= RING_OUT:
				b.room(
					x,
					y,
					x,
					y,
					"ship_grate",
					ring,
					_room({"roof": 3.0, "light": .82, "skin": "ship_rib"})
				)
			elif d < RING_IN:
				viewports.append(Vector2i(x, y))
	# Viewports: a wall cell one thick between the core and the ring, a sill
	# across it the player can see over and not climb, at each eighth of the way
	# round (not over the doors).
	var picked := {}
	for cell: Vector2i in viewports:
		var open_pair := false
		for k: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			var a := cell + k
			var c := cell - k
			var da := dist(a.x, a.y)
			var dc := dist(c.x, c.y)
			if (da <= CORE_R and dc >= RING_IN) or (dc <= CORE_R and da >= RING_IN):
				open_pair = true
		if not open_pair:
			continue
		var angle := fposmod(atan2(cell.y + .5 - CY, cell.x + .5 - CX), TAU)
		var slot := int(roundf(angle / (TAU / 8.0))) % 8
		var off := absf(Enemy.angle_delta(angle, slot * TAU / 8.0))
		if slot == 2 or slot == 6:
			continue
		if not picked.has(slot) or off < float(picked[slot][1]):
			picked[slot] = [cell, off]
	for slot in picked:
		var cell: Vector2i = picked[slot][0]
		b.room(
			cell.x,
			cell.y,
			cell.x,
			cell.y,
			"ship_grate",
			ring,
			_room({"roof": 3.0, "light": .84, "skin": "ship_rib"})
		)
		b.fixture(
			cell.x + .02, cell.y + .02, cell.x + .98, cell.y + .98, 1.05, "ship_panel", "ship_grate"
		)
	# The iris (north, opened from the bridge) and the escape hatch (south,
	# opened when she falls), each through the two cells of wall.
	b.room(64, 38, 64, 38, "ship_deck", core, _room({"roof": 3.0, "light": .8}))
	b.controlled(64, 37, false, {"from": "n", "id": "core-iris", "tile": "ship_door"})
	b.room(64, 61, 64, 61, "ship_deck", core, _room({"roof": 3.0, "light": .8}))
	b.controlled(64, 62, false, {"from": "s", "id": "core-hatch", "tile": "ship_door"})
	# The beam column: light from floor to roof, a pillar to hide behind.
	b.fixture(63.42, 49.42, 64.58, 50.58, 8.0, "ship_beam", "ship_beam")
	for p in [Vector2i(59, 45), Vector2i(68, 45), Vector2i(59, 54), Vector2i(68, 54)]:
		b.fixture(p.x + .15, p.y + .15, p.x + .85, p.y + .85, 8.0, "ship_core", "ship_core")
	# The ring's doors out: a hatch north (the bridge), east (the engine room),
	# south (the bay), west (the mess); open passages at the corners.
	b.door(64, 33, false, {"from": "s", "id": "ring-north", "tile": "ship_door"})
	b.access_doors["64,33"] = ["drive", "tubes"]
	b.door(80, 50, true, {"from": "w", "id": "ring-east", "tile": "ship_door"})
	b.door(64, 66, false, {"from": "n", "id": "ring-south", "tile": "ship_door"})
	b.door(47, 50, true, {"from": "e", "id": "ring-west", "tile": "ship_door"})


# ------------------------------------------------------------------ the bay


## Where the beam set the player down: a tall hall, a pickup hanging in the
## beam, the gantry and the booth up the east side, the escape outhouse on its
## pad in the south.
func tractor_bay() -> void:
	b.room(46, 72, 82, 96, "ship_deck", bay, _room({"roof": 6.5, "light": .82}))
	b.paint(60, 78, 68, 88, "ship_grate")
	b.paint(62, 90, 66, 94, "ship_grate")
	# The gantry up the east wall, its ramp at the north end, and the booth over
	# the bay's south-east corner.
	for k in 6:
		b.raise(80, 74 + k, 82, 74 + k, .24 + k * .24)
	b.raise(80, 80, 82, 96, 1.44)
	b.raise(76, 93, 79, 96, 1.44)
	b.paint(80, 74, 82, 96, "ship_grate")
	b.paint(76, 93, 79, 96, "ship_grate")
	b.lighten(76, 80, 82, 96, .88)
	b.glow(64.0, 83.0, 6.0, .22)
	b.glow(64.0, 92.0, 3.5, .18)
	# Four ribs hold the roof up round the beam.
	for c in [Vector2i(54, 79), Vector2i(74, 79), Vector2i(54, 89), Vector2i(74, 89)]:
		b.wall(c.x, c.y, c.x, c.y, "ship_rib", 6.5)


# ------------------------------------------------------------------ the west


func west_wing() -> void:
	# The probe lab: white tile, a lamp over each table.
	b.room(26, 64, 44, 86, "floor_tile", probe, _room({"roof": 3.6, "light": .9}))
	b.paint(26, 64, 44, 66, "ship_deck")
	# Two viewports in the shared wall: the bay can see the tables.
	for y in [75, 82]:
		b.room(45, y, 45, y, "floor_tile", probe, _room({"roof": 3.6, "light": .7}))
		b.fixture(45.02, y + .02, 45.98, y + .98, 1.05, "ship_panel", "ship_grate")
	# The exam room in the south-west corner, behind a tin partition with a way
	# in and a window to the rest of the lab.
	b.wall(26, 78, 29, 78, "ship_tin", 3.6)
	b.wall(31, 78, 33, 78, "ship_tin", 3.6)
	b.wall(34, 78, 34, 86, "ship_tin", 3.6)
	b.room(34, 82, 34, 82, "floor_tile", probe, _room({"roof": 3.6, "light": .7}))
	b.fixture(34.02, 82.02, 34.98, 82.98, 1.05, "ship_panel", "ship_grate")
	# The specimen hold: tubes down the middle, a gantry up the west wall.
	b.room(6, 62, 22, 90, "ship_deck", specimen, _room({"roof": 4.6, "light": .78}))
	b.paint(10, 63, 18, 89, "ship_grate")
	for k in 4:
		b.raise(6, 64 + k, 8, 64 + k, .24 + k * .24)
	b.raise(6, 68, 8, 90, 1.2)
	b.paint(6, 64, 8, 90, "ship_grate")
	# The crew mess, linoleum and all; the kitchen behind a counter in the north.
	b.room(26, 38, 43, 60, "ship_lino", mess, _room({"roof": 3.4, "light": .9}))
	b.paint(26, 38, 43, 40, "floor_tile")
	# The bunks.
	b.room(6, 36, 22, 58, "ship_deck", bunks, _room({"roof": 3.0, "light": .8}))
	# Maw's parlor: boards for a floor, low lamps, a recliner by the set.
	b.room(8, 13, 27, 32, "wood", parlor, _room({"roof": 3.4, "light": .86}))
	b.paint(13, 18, 22, 25, "porch")
	# Her bedroom behind a papered wall, a way through at either end.
	b.wall(8, 26, 10, 26, "office_wall", 3.4)
	b.wall(13, 26, 22, 26, "office_wall", 3.4)
	b.wall(25, 26, 27, 26, "office_wall", 3.4)
	# The trophy room: a raised tier along the north wall for the best of it.
	b.room(30, 13, 50, 32, "ship_deck", trophy, _room({"roof": 4.6, "light": .88}))
	b.raise(31, 13, 49, 15, .48)
	b.raise(31, 16, 49, 16, .24)
	b.paint(31, 13, 49, 16, "wood")


# ------------------------------------------------------------------ the north


func north_wing() -> void:
	# The bridge: the viewscreen across the north wall, the dais in the middle.
	b.room(56, 16, 72, 30, "ship_deck", bridge, _room({"roof": 4.4, "light": .86}))
	b.wall(59, 15, 69, 15, "ship_screen", 4.6)
	b.wall(55, 17, 55, 21, "ship_panel", 4.6)
	b.wall(73, 17, 73, 21, "ship_panel", 4.6)
	b.raise(60, 18, 68, 23, .24)
	b.raise(61, 18, 67, 22, .48)
	b.paint(60, 18, 68, 23, "ship_grate")
	b.glow(64.0, 18.0, 5.0, .2)
	# The corn deck: beds of county corn in rows, a catwalk over them.
	b.room(77, 10, 104, 34, "ship_grate", corn, _room({"roof": 6.0, "light": .82}))
	for y in [13, 17, 21, 25, 29]:
		b.paint(79, y, 88, y + 1, "dirt")
		b.paint(93, y, 102, y + 1, "dirt")
	b.paint(89, 10, 92, 34, "ship_deck")
	# A walkway a step up down the middle, two steps up between the beds: high
	# enough there to see over the young corn, a step down where each aisle
	# crosses it.
	b.raise(90, 12, 91, 32, .24)
	for y in [13, 17, 21, 25, 29]:
		b.raise(90, y, 91, y + 1, .48)
	b.paint(90, 12, 91, 32, "ship_grate")
	# The shine tanks: a tank farm the drive drinks from.
	b.room(107, 12, 122, 36, "ship_deck", tanks, _room({"roof": 5.0, "light": .8}))
	b.raise(114, 12, 122, 15, 1.44)
	for k in 6:
		b.raise(108 + k, 12, 108 + k, 15, .24 + k * .24)
	b.paint(108, 12, 122, 15, "ship_grate")


# ------------------------------------------------------------------ the east


func east_wing() -> void:
	# The engine room: the drive in a pit, a ramp down to it either side.
	b.room(84, 39, 110, 61, "ship_deck", engine, _room({"roof": 7.0, "light": .78}))
	b.raise(91, 45, 103, 55, -.96)
	for k in 3:
		b.raise(88 + k, 49, 88 + k, 51, -.24 - k * .24)
		b.raise(106 - k, 49, 106 - k, 51, -.24 - k * .24)
	b.paint(88, 45, 106, 55, "ship_grate")
	b.glow(97.0, 50.0, 7.0, .25)
	# The cargo hold.
	b.room(86, 66, 112, 90, "ship_deck", cargo, _room({"roof": 5.5, "light": .8}))
	b.paint(86, 76, 112, 79, "ship_grate")


# ------------------------------------------------------------------ the ways


## The passages between the rooms and onto the ring, and their doors.
func passages() -> void:
	var low := {"roof": 2.6, "light": .78}
	# Onto the ring: north to the bridge, the corners, east, south, west.
	carve([Vector2i(64, 32), Vector2i(64, 32)], "ship_deck", ring, low)
	b.gap(64, 31, "s")
	carve([Vector2i(53, 37), Vector2i(53, 32), Vector2i(52, 32)], "ship_grate", ring, low)
	b.door(51, 32, true, {"from": "e", "id": "trophy-ring", "tile": "ship_door"})
	carve([Vector2i(74, 37), Vector2i(74, 31), Vector2i(75, 31)], "ship_grate", ring, low)
	b.gap(76, 31, "w")
	carve([Vector2i(81, 50), Vector2i(82, 50)], "ship_deck", ring, low)
	b.gap(83, 50, "w")
	carve([Vector2i(74, 62), Vector2i(74, 64), Vector2i(88, 64)], "ship_grate", ring, low)
	b.gap(88, 65, "n")
	carve([Vector2i(64, 67), Vector2i(64, 70)], "ship_deck", ring, low)
	b.gap(64, 71, "n")
	carve([Vector2i(53, 62), Vector2i(53, 66), Vector2i(46, 66)], "ship_grate", ring, low)
	b.gap(45, 66, "e")
	carve([Vector2i(45, 50), Vector2i(46, 50)], "ship_deck", ring, low)
	b.gap(44, 50, "e")
	# The bridge's side doors: the trophy room's opens with the tubes drained,
	# the corn deck's with the drive spiked.
	carve([Vector2i(52, 23), Vector2i(54, 23)], "ship_deck", trophy, low)
	b.gap(51, 23, "e")
	b.controlled(55, 23, true, {"from": "e", "id": "bridge-west", "tile": "ship_door"})
	carve([Vector2i(74, 23), Vector2i(75, 23)], "ship_deck", corn, low)
	b.gap(76, 23, "w")
	b.controlled(73, 23, true, {"from": "w", "id": "bridge-east", "tile": "ship_door"})
	# Room to room.
	b.door(29, 22, true, {"from": "e", "id": "trophy-parlor", "tile": "ship_door"})
	b.gap(28, 22, "w")
	carve([Vector2i(14, 34), Vector2i(14, 34)], "ship_deck", bunks, low)
	b.gap(14, 33, "n")
	b.door(14, 35, false, {"from": "s", "id": "bunks-parlor", "tile": "ship_door"})
	carve([Vector2i(24, 47), Vector2i(24, 47)], "ship_deck", mess, low)
	b.gap(23, 47, "w")
	b.door(25, 47, true, {"from": "e", "id": "mess-bunks", "tile": "ship_door"})
	carve([Vector2i(14, 60), Vector2i(14, 60)], "ship_deck", specimen, low)
	b.gap(14, 59, "n")
	b.door(14, 61, false, {"from": "s", "id": "bunks-specimen", "tile": "ship_door"})
	carve([Vector2i(35, 62), Vector2i(35, 62)], "ship_deck", probe, low)
	b.gap(35, 61, "n")
	b.door(35, 63, false, {"from": "s", "id": "mess-probe", "tile": "ship_door"})
	carve([Vector2i(24, 76), Vector2i(24, 76)], "ship_deck", probe, low)
	b.gap(23, 76, "w")
	b.door(25, 76, true, {"from": "e", "id": "specimen-probe", "tile": "ship_door"})
	b.door(45, 79, true, {"from": "e", "id": "probe-bay", "tile": "ship_door"})
	carve([Vector2i(95, 35), Vector2i(95, 37)], "ship_deck", engine, low)
	b.gap(95, 35, "n")
	b.door(95, 38, false, {"from": "s", "id": "engine-corn", "tile": "ship_door"})
	b.gap(105, 20, "w")
	b.door(106, 20, true, {"from": "e", "id": "corn-tanks", "tile": "ship_door"})
	carve([Vector2i(98, 63), Vector2i(98, 64)], "ship_deck", cargo, low)
	b.gap(98, 62, "n")
	b.door(98, 65, false, {"from": "s", "id": "engine-cargo", "tile": "ship_door"})
	b.gap(83, 72, "w")
	carve([Vector2i(84, 72), Vector2i(84, 72)], "ship_deck", cargo, low)
	b.door(85, 72, true, {"from": "e", "id": "cargo-bay", "tile": "ship_door"})


# ------------------------------------------------------------------ the secrets


func secrets() -> void:
	# Behind the probe lab's south wall: the good probe and what it guards.
	b.secret(
		30, 87, false, [29, 88, 31, 89], {"from": "n", "id": "lab-closet", "tile": "ship_hull"}
	)
	b.room(29, 88, 31, 89, "floor_tile", probe, _room({"roof": 2.4, "light": .66}))
	# Under the bay's south wall: a duct somebody hid a case of rockets in.
	b.secret(72, 97, false, [71, 98, 73, 98], {"from": "n", "id": "bay-duct", "tile": "ship_hull"})
	b.room(71, 98, 73, 98, "ship_grate", ducts, _room({"roof": 2.2, "light": .66}))
	# A loose locker in the bunks' west wall.
	b.secret(5, 45, true, [3, 44, 4, 46], {"from": "e", "id": "bunk-locker", "tile": "ship_tin"})
	b.room(3, 44, 4, 46, "ship_deck", ducts, _room({"roof": 2.4, "light": .66}))
	# A still somebody built behind the corn, north wall.
	b.secret(84, 9, false, [82, 6, 86, 8], {"from": "s", "id": "corn-still", "tile": "ship_tin"})
	b.room(82, 6, 86, 8, "dirt", ducts, _room({"roof": 2.6, "light": .68}))
	# The trophy room's vault, opened by pulling the lawn elf's hat (a station).
	b.controlled(40, 12, false, {"from": "s", "id": "trophy-vault", "tile": "ship_hull"})
	b.room(38, 9, 42, 11, "wood", trophy, _room({"roof": 3.0, "light": .68}))
	b.raise(38, 9, 42, 12, .48)


func labels() -> void:
	for l in [
		["BAY", 60, 86],
		["CORE", 61, 50],
		["RING", 49, 42],
		["BRIDGE", 60, 25],
		["TROPHIES", 34, 24],
		["PARLOR", 12, 22],
		["BUNKS", 10, 46],
		["MESS", 31, 50],
		["SPECIMENS", 8, 76],
		["PROBES", 31, 74],
		["CORN", 80, 22],
		["ENGINE", 86, 48],
		["SHINE", 110, 24],
		["CARGO", 92, 84],
	]:
		b.label(String(l[0]), int(l[1]), int(l[2]))
