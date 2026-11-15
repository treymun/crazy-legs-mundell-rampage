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
## - Inside, a card lists them all: the bosses and their rematch bests, each
##   game's best, each map's longest run.
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

var on := false
## Read from the files when first wanted: boss kind -> beaten, game -> best,
## map -> record, rematch bests; when they were read (game clock, -1 never).
var beaten := {}
var bests := {}
var county := {}
var rematch := {}
var read_at := -1.0


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
	return out


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
