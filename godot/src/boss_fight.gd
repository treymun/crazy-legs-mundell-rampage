## Which boss fight is on: the boss is alive, awake and the player is in its
## arena, as far as the boss bar shows (boss_bar.gd and features/fight_music.gd
## hold the same test). A boss with a lock (bosses.cfg [boss_lock]) has its
## arena as a room: the floor of its boxes or circles it can reach with its
## doors shut; the fight starts only once someone stands DEPTH past every way
## in (started_at), and features/boss_lock.gd shuts them. A boss without one
## keeps the old tests: within ARENA of a chapter's last boss, or Hickston's
## boxes. The boss checkpoint (features/boss_checkpoint.gd) and the rematch
## (features/boss_rematch.gd) start from it.
class_name BossFight
extends RefCounted

const ARENA := 14.0
const PEN_Y := 10.0
## How far past every way in a player stands before a locked arena's fight
## starts (cells): well into the arena, never in its doorway.
static var DEPTH: float = BossData.get_value("boss_lock", "depth")

## Lock sheets by kind (bosses.cfg [boss_lock]), read once.
static var _sheets := {}
## Rooms worked out: "<world instance id>:<kind>" -> PackedByteArray, a byte a
## cell (1 in the room). A few games' worth.
static var _rooms := {}
## Each kind's ways in (cells) on a world, the same way.
static var _ways := {}


## The boss whose fight it would be: the chapter's last boss, or Hickston's
## sheriff and then Jerry; null when none is awake.
static func awake(game: Game) -> Enemy:
	for foe: Enemy in [game.finale, game.boss, game.jerry]:
		if foe != null and foe.alive and foe.alerted and not foe.dormant:
			return foe
	return null


## Whether a point is in `foe`'s arena: its lock's room; else within ARENA of
## a chapter's last boss; for Hickston's two, the box its level gives it
## (boss_arena: the sheriff's rodeo pen, Jerry's football field), or the top
## of the pasture.
static func in_arena_at(game: Game, foe: Enemy, x: float, y: float) -> bool:
	if not lock_of(game, foe.kind).is_empty():
		return in_room(game, foe.kind, x, y)
	if foe == game.finale:
		return Vector2(foe.x - x, foe.y - y).length() < ARENA
	var box: Variant = box_of(game, foe.kind)
	if box != null:
		var area: Rect2 = box
		return area.has_point(Vector2(x, y))
	return y < PEN_Y


## Whether a fight with `foe` starts with someone at (x, y): in its arena and,
## for a locked one, DEPTH past every way in (not in the doorway or the
## corridor before it).
static func started_at(game: Game, foe: Enemy, x: float, y: float) -> bool:
	if not in_arena_at(game, foe, x, y):
		return false
	for cell: Vector2i in entrances(game, foe.kind):
		if _to_cell(cell, x, y) < DEPTH:
			return false
	return true


## The box a kind's arena fills on its level's map (boss_arena's `box`, both
## corner cells inside), or null.
static func box_of(game: Game, kind: String) -> Variant:
	var notes: Variant = game.level.boss_arena.get(kind, {})
	var sheet: Dictionary = notes if notes is Dictionary else {}
	var box: Variant = sheet.get("box") if notes is Dictionary else null
	if not (box is Array) or len(box) < 4:
		return null
	var x0: float = box[0]
	var y0: float = box[1]
	var x1: float = box[2]
	var y1: float = box[3]
	return Rect2(x0, y0, x1 - x0 + 1.0, y1 - y0 + 1.0)


## Whether a point is clear of `foe`'s arena: out of it and, for a locked
## one, out of its doorways; ARENA away from one without a lock.
static func clear_of(game: Game, foe: Enemy, x: float, y: float) -> bool:
	if in_arena_at(game, foe, x, y):
		return false
	if lock_of(game, foe.kind).is_empty():
		return Vector2(foe.x - x, foe.y - y).length() >= ARENA
	for cell: Vector2i in entrances(game, foe.kind):
		if _to_cell(cell, x, y) < .5:
			return false
	return true


## The boss whose fight is on this moment, or null.
static func on(game: Game) -> Enemy:
	if game.in_hub:
		return null
	var foe := awake(game)
	if foe == null or not in_arena_at(game, foe, game.player.x, game.player.y):
		return null
	return foe


## The living enemy of `kind` (a boss: there is one of each), or null.
static func of_kind(game: Game, kind: String) -> Enemy:
	for e: Enemy in game.enemies:
		if e.kind == kind and e.hp > 0.0:
			return e
	return null


# ------------------------------------------------------------------ the lock


## `kind`'s lock sheet on this game's level (bosses.cfg [boss_lock]), or {}
## (no lock, or another level: a County Run map).
static func lock_of(game: Game, kind: String) -> Dictionary:
	if not _sheets.has(kind):
		var cfg := Tuning.file(BossData.DATA)
		var found: Variant = (
			cfg.get_value("boss_lock", kind) if cfg.has_section_key("boss_lock", kind) else {}
		)
		_sheets[kind] = found if found is Dictionary else {}
	var sheet: Dictionary = _sheets[kind]
	if sheet.is_empty() or str(sheet.get("level", "")) != game.level.id:
		return {}
	return sheet


## What a door says to USE: `normal`, or, held shut by a boss arena's lock
## (features/boss_lock.gd marks it a remote door "boss"), why.
static func door_note(world: LevelData, door: LevelData.Door, normal: String) -> String:
	var mark: Variant = world.controlled_doors.get(Vector2i(door.x, door.y), false)
	return "SHUT TILL THE BOSS IS DOWN" if mark is String else normal


## The level's doors into `kind`'s arena (by the sheet's ids).
static func lock_doors(game: Game, kind: String) -> Array[LevelData.Door]:
	var ids: Array = lock_of(game, kind).get("doors", [])
	var out: Array[LevelData.Door] = []
	for door: LevelData.Door in game.world.doors:
		if ids.has(door.id):
			out.append(door)
	return out


## The open cells that stand as gates while `kind`'s arena is shut.
static func gate_cells(game: Game, kind: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for box: Variant in lock_of(game, kind).get("gates", []):
		var corners: Array = box
		var x0: int = corners[0]
		var y0: int = corners[1]
		var x1: int = corners[2]
		var y1: int = corners[3]
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				out.append(Vector2i(x, y))
	return out


## Every way into `kind`'s arena: its doors' cells and its gates' cells.
static func entrances(game: Game, kind: String) -> Array[Vector2i]:
	var key := "%d:%s" % [game.world.get_instance_id(), kind]
	if _ways.has(key):
		return _ways[key]
	var out := gate_cells(game, kind)
	for door: LevelData.Door in lock_doors(game, kind):
		out.append(Vector2i(door.x, door.y))
	while _ways.size() >= 24:
		_ways.erase(_ways.keys()[0])
	_ways[key] = out
	return out


## Whether (x, y) is in `kind`'s room.
static func in_room(game: Game, kind: String, x: float, y: float) -> bool:
	var w := game.world
	if x < 0.0 or y < 0.0 or x >= w.width or y >= w.height:
		return false
	var room := room_of(game, kind)
	return room.size() == w.width * w.height and room[int(y) * w.width + int(x)] != 0


## `kind`'s room on this game's level: the cells of its boxes and circles its
## `spot` reaches side to side over open floor (deep water too: the
## king's lagoon) with its doors and gates counted shut, every other door
## open. Worked out once a level; empty without a lock.
static func room_of(game: Game, kind: String) -> PackedByteArray:
	var w := game.world
	var key := "%d:%s" % [w.get_instance_id(), kind]
	if _rooms.has(key):
		return _rooms[key]
	var room := PackedByteArray()
	var sheet := lock_of(game, kind)
	if sheet.is_empty():
		return room
	var size := w.width * w.height
	var shape := PackedByteArray()
	shape.resize(size)
	for part: Variant in sheet.get("room", []):
		_paint(w, shape, part)
	var shut := {}
	for cell: Vector2i in entrances(game, kind):
		shut[cell.y * w.width + cell.x] = true
	room.resize(size)
	# From the spot players are brought in to (the boss may have walked).
	var spot: Array = sheet.get("spot", [0.0, 0.0])
	var sx: float = spot[0]
	var sy: float = spot[1]
	var start := int(sy) * w.width + int(sx)
	if start < 0 or start >= size or shape[start] == 0:
		return room
	var todo := PackedInt32Array([start])
	room[start] = 1
	while not todo.is_empty():
		var c := todo[todo.size() - 1]
		todo.resize(todo.size() - 1)
		for step: int in [1, -1, w.width, -w.width]:
			var n := c + step
			if n < 0 or n >= size or room[n] != 0 or shape[n] == 0 or shut.has(n):
				continue
			if absi(n % w.width - c % w.width) > 1:
				continue
			if w.solid[n] >= 0 and not w.door_cells.has(n):
				continue
			room[n] = 1
			todo.append(n)
	while _rooms.size() >= 24:
		_rooms.erase(_rooms.keys()[0])
	_rooms[key] = room
	return room


## A box [x0, y0, x1, y1] or a circle [x, y, radius] marked on `shape`.
static func _paint(w: LevelData, shape: PackedByteArray, part: Variant) -> void:
	var nums: Array = part
	if nums.size() == 3:
		var cx: float = nums[0]
		var cy: float = nums[1]
		var r: float = nums[2]
		for y in range(maxi(0, floori(cy - r)), mini(w.height, ceili(cy + r) + 1)):
			for x in range(maxi(0, floori(cx - r)), mini(w.width, ceili(cx + r) + 1)):
				if Vector2(x + .5 - cx, y + .5 - cy).length() <= r:
					shape[y * w.width + x] = 1
		return
	var x0: int = nums[0]
	var y0: int = nums[1]
	var x1: int = nums[2]
	var y1: int = nums[3]
	for y in range(maxi(0, y0), mini(w.height, y1 + 1)):
		for x in range(maxi(0, x0), mini(w.width, x1 + 1)):
			shape[y * w.width + x] = 1


## How far (x, y) is from a cell's square.
static func _to_cell(cell: Vector2i, x: float, y: float) -> float:
	var dx := maxf(0.0, maxf(cell.x - x, x - (cell.x + 1.0)))
	var dy := maxf(0.0, maxf(cell.y - y, y - (cell.y + 1.0)))
	return sqrt(dx * dx + dy * dy)
