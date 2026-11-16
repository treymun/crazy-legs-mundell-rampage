## Mundell's trophy shack in the County Crossroads (hub_plan.gd builds the
## shack behind the Road Department's yard): what he has to show for it all,
## read from what the player already has, never a save of its own.
##
## - Each boss whose chapter is beaten (BossRematch.beaten: the next gate
##   open, the chapter marked won, or the campaign won) stands on its plinth
##   as a statuette in its own looks (its 3D model, the actor's stand-in, at
##   a third of its height), its plaque on the wall behind; a boss not yet
##   beaten leaves its plinth bare.
## - On the shelf on the east wall a cup for each of the firing range's games
##   he has a best in (range_board.gd's records: the bowling game biggest),
##   and a garden gnome for each County Run map he has a record on
##   (county_records.gd).
## - On the west wall by the door Mundell's shadow board (gun_board, built by
##   tools/art/build_gun_signs.gd): a painted outline for each of the
##   campaign's fourteen guns (GunFinder.BOARD), each gun the player has hung
##   on its outline; the bare outlines are the ones still out there
##   (src/gun_finder.gd).
## - Inside, a card lists them all: the bosses and their rematch bests, each
##   game's best, each map's longest run, the guns on the board and where the
##   missing ones lie in the chapters already beaten.
##
## Looks only (nothing carried): the records are files of their own, read
## when the shack is first seen (and again a minute on).
extends GameFeature

## The shack's inside (cells), the plinths along its north and south walls
## (x, and which wall: -1 north, facing south; 1 south, facing north), the
## shelf on its east wall.
const INSIDE := Rect2(63.0, 47.0, 7.0, 6.0)
const PLINTHS := [
	[63.9, -1],
	[65.5, -1],
	[67.1, -1],
	[68.7, -1],
	[63.9, 1],
	[65.5, 1],
	[67.1, 1],
	[68.7, 1],
]
const SHELF_X := 69.72
const SHELF_Z := 1.0
## The statuette's height on its plinth.
const STATUE := .42
## Order of the cups on the shelf (range_board.gd's games), and the County
## Run maps' gnomes.
const CUPS := ["bowling", "gallery", "horseshoes", "dunk", "skeeball", "bottles", "fair_gallery"]
## The shadow board on the west wall north of the door: where its middle is,
## how high it hangs, how tall it is; its picture's grid (build_gun_signs.gd
## COLUMNS, CELL, MARGIN: GunFinder.BOARD's guns five a row, three rows).
const BOARD_AT := Vector2(63.02, 48.52)
const BOARD_Z := .55
const BOARD_TALL := .98
const BOARD_CELL := Vector2i(56, 30)
const BOARD_MARGIN := 8
const BOARD_COLUMNS := 5
const BOARD_ROWS := 3

var on := false
## Read from the files when first wanted: boss kind -> beaten, game -> best,
## map -> record, rematch bests; when they were read (game clock, -1 never).
var beaten := {}
var bests := {}
var county := {}
var rematch := {}
var read_at := -1.0
## Chapter -> beaten (for the card's guns still out there), and each gun's
## place on the board ([the picture's middle along the board, its bottom up
## it, its height], in board pixels), worked out once from its picture.
var chapters := {}
var slots := {}


func id() -> String:
	return "trophy_shack"


func attach() -> void:
	on = game.level != null and game.level.id == "hub"


## The records, read again when stale (open_hub locks the gates after the
## hub is made, so this waits until it is first drawn).
func refresh() -> void:
	read_at = game.clock
	var unlocked := {}
	for gate: LevelData.Gate in game.world.hub_gates:
		if not game.world.locked_gates.has(gate):
			unlocked[gate.destination] = true
	var doc := BossRematch.profile()
	beaten = {}
	var known := {}
	for kind: String in BossRematch.BOSSES:
		var level_id: String = BossRematch.LEVEL_OF[kind]
		if not known.has(level_id):
			known[level_id] = BossRematch.beaten(level_id, unlocked, doc)
		if known[level_id]:
			beaten[kind] = true
	chapters = {}
	for level_id: String in Campaign.ORDER:
		chapters[level_id] = known.get(level_id, BossRematch.beaten(level_id, unlocked, doc))
	rematch = doc["bests"]
	bests = RangeBoard.read()
	county = CountyRecords.read()


func _fresh() -> void:
	if read_at < 0.0 or game.clock - read_at > 60.0:
		refresh()


func inside(p: Player) -> bool:
	return INSIDE.has_point(Vector2(p.x, p.y))


# ------------------------------------------------------------------ looks


static func _solid(
	x: float, y: float, z: float, kind: String, turn := Basis.IDENTITY
) -> View.Sprite:
	var s := View.Sprite.new(x, y, "town_range_pin", .3, z)
	s.solid = kind
	s.turn = turn
	return s


func sprites() -> Array:
	var out: Array = []
	if not on or not game.in_view(66.5, 50.0, 5.0):
		return out
	_fresh()
	var floor_z := game.world.elevation(66.5, 50.0)
	for i in PLINTHS.size():
		var row: Array = PLINTHS[i]
		var x: float = row[0]
		var side: int = row[1]
		var y := INSIDE.position.y + .42 if side < 0 else INSIDE.end.y - .42
		var wall := INSIDE.position.y + .03 if side < 0 else INSIDE.end.y - .03
		var facing := 0.0 if side < 0 else PI
		out.append(_solid(x, y, floor_z, "plinth"))
		out.append(_solid(x, wall, floor_z + 1.5, "plaque", Basis(Vector3(0, 0, 1), facing)))
		if i >= BossRematch.BOSSES.size():
			continue
		var kind: String = BossRematch.BOSSES[i]
		if not beaten.has(kind):
			continue
		var e := ModeBodies.stand_in(game, "trophy-" + kind, kind)
		e.x = x
		e.y = y
		e.angle = PI * .5 if side < 0 else -PI * .5
		e.height = STATUE
		e.gait = 0.0
		var statue := View.Sprite.new(x, y, kind + "_0", STATUE, floor_z + .25)
		statue.body = true
		statue.who = e
		out.append(statue)
	# The shelf on the east wall, its cups and gnomes.
	var shelf_from := INSIDE.position.y + 1.1
	var shelf_long := INSIDE.size.y - 2.2
	out.append(
		_solid(
			SHELF_X,
			shelf_from,
			floor_z + SHELF_Z,
			"shelf",
			Basis(Vector3(0, 0, 1), PI * .5) * Basis.from_scale(Vector3(shelf_long, 1, 1))
		)
	)
	var won: Array = []
	for game_id: String in CUPS:
		var best: int = bests.get(game_id, 0)
		if best > 0:
			won.append(game_id)
	for k in won.size():
		var y := shelf_from + (k + .5) * shelf_long / maxf(1.0, won.size())
		var tall := .48 if str(won[k]) == "bowling" else .34
		var cup := View.Sprite.new(SHELF_X - .02, y, "town_trophy", tall, floor_z + SHELF_Z)
		cup.plane = PI * .5
		out.append(cup)
	var maps: Array = county.keys()
	maps.sort()
	for k in maps.size():
		var gnome := View.Sprite.new(
			INSIDE.position.x + 2.5 + k * .9,
			INSIDE.position.y + 3.0,
			"town_trophy_gnome",
			.4,
			floor_z
		)
		out.append(gnome)
	_board(out, floor_z)
	return out


## The shadow board, and each gun the local player has hung on it, flat on the
## wall (a pickup's picture on a plane is drawn flat, not as a slab).
func _board(out: Array, floor_z: float) -> void:
	var w := BOARD_MARGIN * 2 + BOARD_CELL.x * BOARD_COLUMNS
	var h := BOARD_MARGIN * 2 + BOARD_CELL.y * BOARD_ROWS
	var unit := BOARD_TALL / h
	var plane := -PI * .5  # facing east, into the shack
	var along := Vector2(cos(plane), sin(plane))
	var board := View.Sprite.new(BOARD_AT.x, BOARD_AT.y, "gun_board", BOARD_TALL, floor_z + BOARD_Z)
	board.plane = plane
	out.append(board)
	var owned: Array[bool] = game.local_player.armory.owned
	for i in GunFinder.BOARD.size():
		var gun: String = GunFinder.BOARD[i]
		if not owned[Weapons.NAMES.find(gun)]:
			continue
		var item := "item_" + ("dynamite" if gun == "tnt" else gun)
		var slot := _slot(i, item)
		if slot.is_empty():
			continue
		var mid: float = slot[0]
		var bottom: float = slot[1]
		var tall: float = slot[2]
		var at := BOARD_AT + along * (mid - w * .5) * unit + Vector2(.015, 0.0)
		var hung := View.Sprite.new(
			at.x, at.y, item, tall * unit, floor_z + BOARD_Z + (h - bottom) * unit
		)
		hung.plane = plane
		out.append(hung)


## Where the board's gun `i`'s picture `item` hangs on it, as build_gun_signs.gd
## painted its outline: [middle, bottom, height] in board pixels ([] with no
## picture).
func _slot(i: int, item: String) -> Array:
	if slots.has(i):
		return slots[i]
	var found: Array = []
	if game.art.has_art(item):
		var pic: Dictionary = game.art.art(item)
		var pw: int = pic["w"]
		var ph: int = pic["h"]
		var data: PackedByteArray = pic["data"]
		var lo := Vector2i(pw, ph)
		var hi := Vector2i(-1, -1)
		for y in ph:
			for x in pw:
				if data[(y * pw + x) * 4 + 3] > 100:
					lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
					hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
		if hi.x >= 0:
			var box := hi - lo + Vector2i.ONE
			var k := minf(
				1.0, minf(float(BOARD_CELL.x - 8) / box.x, float(BOARD_CELL.y - 6) / box.y)
			)
			var size := Vector2i(maxi(1, int(box.x * k)), maxi(1, int(box.y * k)))
			var cell := Vector2i(
				BOARD_MARGIN + (i % BOARD_COLUMNS) * BOARD_CELL.x,
				BOARD_MARGIN + (i / BOARD_COLUMNS) * BOARD_CELL.y
			)
			var top_left := (
				Vector2(cell + (BOARD_CELL - size) / 2 - Vector2i(0, 2)) - Vector2(lo) * k
			)
			found = [top_left.x + pw * k * .5, top_left.y + ph * k, ph * k]
	slots[i] = found
	return found


# ------------------------------------------------------------------ the card


## The card's lines (draw_view shows them inside the shack).
func lines() -> Array:
	_fresh()
	var out: Array = []
	out.append("BOSSES BEATEN %d OF %d" % [beaten.size(), BossRematch.BOSSES.size()])
	var bossed := PackedStringArray()
	for kind: String in BossRematch.BOSSES:
		if beaten.has(kind) and rematch.has(kind):
			var t: float = rematch[kind]
			bossed.append("%s %s" % [BossRematch.title(kind).get_slice(" ", 0), _clock(t)])
	if not bossed.is_empty():
		out.append("REMATCH BESTS: " + "  ".join(bossed.slice(0, 2)))
		if bossed.size() > 2:
			out.append("  " + "  ".join(bossed.slice(2, 5)))
	var games := PackedStringArray()
	for game_id: String in CUPS:
		var best: int = bests.get(game_id, 0)
		if best > 0:
			games.append("%s %d" % [str(RangeBoard.GAMES[game_id]), best])
	if games.is_empty():
		out.append("NO RANGE BESTS YET: THE FIRING RANGE")
	else:
		for k in range(0, games.size(), 2):
			out.append("  ".join(games.slice(k, k + 2)))
	out.append_array(_gun_lines())
	var maps: Array = county.keys()
	maps.sort()
	for map_id: Variant in maps:
		var rec: Variant = county[map_id]
		if rec is Dictionary:
			var r: Dictionary = rec
			var t: float = r.get("time", 0.0)
			var level: int = r.get("level", 0)
			out.append(
				(
					"COUNTY RUN %s %s LV %d"
					% [str(map_id).replace("county_", "").to_upper(), _clock(t), level]
				)
			)
	return out


## The card's lines for the shadow board: how many of its guns hang on it,
## and each one missing that lies in a chapter already beaten, with where.
func _gun_lines() -> Array:
	var out: Array = []
	var owned: Array[bool] = game.local_player.armory.owned
	var had := 0
	for gun: String in GunFinder.BOARD:
		if owned[Weapons.NAMES.find(gun)]:
			had += 1
	out.append("GUN BOARD %d OF %d" % [had, GunFinder.BOARD.size()])
	var missing: Array = []
	for gun: String in GunFinder.BOARD:
		if owned[Weapons.NAMES.find(gun)]:
			continue
		var where := PackedStringArray()
		for level_id: String in Campaign.ORDER:
			if chapters.get(level_id, false) and GunFinder.chapter_guns(level_id).has(gun):
				where.append(str(Campaign.GATE_LABELS[level_id]))
		if not where.is_empty():
			missing.append("  %s - %s" % [GunFinder.label(gun), ", ".join(where)])
	if not missing.is_empty():
		out.append("STILL OUT THERE:")
		out.append_array(missing.slice(0, 3))
		if missing.size() > 3:
			out.append("  AND %d MORE" % (missing.size() - 3))
	return out


static func _clock(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]


func draw_view(c: Canvas) -> void:
	if not on or game.map or not inside(game.local_player):
		return
	var rows := lines()
	var top := 34 if game.message_until > game.clock else 18
	HUD.panel(c, 4, top, 170, 14 + rows.size() * 7, Color(34 / 255.0, 24 / 255.0, 19 / 255.0))
	HUD.text(c, "MUNDELL'S TROPHIES", 9, top + 3, "body", HUD.AMBER)
	for i in rows.size():
		HUD.text(c, str(rows[i]), 9, top + 13 + i * 7, "mini", HUD.INK, false, false)
