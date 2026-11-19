## A client's check of its copy against the host's snapshot, a part at a
## time. NetSync.Client compared its whole copy with a snapshot once a
## second: a whole capture (every enemy's row) and a walk of it, 7 ms in a
## 5v5, 23 in County Run and about 40 in campaign co-op on this PC, all in
## one frame: a hitch every second (NETSOAK measured the client's frame p99
## at 23 and 44 ms). Now each check captures and compares one part (the
## game's own fields, the world, the facts, the players, the order and the
## statics; the simulation's features; or the next ENEMIES of the enemies),
## so a frame never carries more than a part; the parts take turns, so every
## part is still held to the host's word about once a second. Read only, as
## the whole capture was.
class_name NetCheckParts
extends RefCounted

## Enemies captured and compared in one part.
const ENEMIES := 8


## How many parts `game` has now (two and the enemies' chunks).
static func count(game: Game) -> int:
	return 2 + ceili(game.enemies.size() / float(ENEMIES))


## Part `part` (wrapped to count()) of `game` against `data` (the host's
## snapshot of the tick the copy is at): where they first differ ("" none).
static func compare(game: Game, data: Dictionary, part: int, near: float) -> String:
	game.name_new()
	var local: Player = game.local_player
	game.focus(game.players[0])
	var codec := SnapCodec.new(game)
	var where := ""
	var k := posmod(part, count(game))
	if k == 0:
		where = _head(game, codec, data, near)
	elif k == 1:
		where = _features(codec, game, data, near)
	else:
		where = _enemies(game, codec, data, (k - 2) * ENEMIES, near)
	game.focus(local)
	return where


static func _head(game: Game, codec: SnapCodec, data: Dictionary, near: float) -> String:
	var fields := {}
	for name: String in GameSnapshot.SIM_FIELDS:
		var v: Variant = game.get(name)
		fields[name] = v if SnapCodec.PLAIN.has(typeof(v)) else codec.encode(v)
	var where := GameSnapshot.first_difference(data.get("game"), fields, "/game", near)
	if where != "":
		return where
	where = GameSnapshot.first_difference(
		data.get("world"), GameSnapshot.world_of(game), "/world", near
	)
	if where != "":
		return where
	where = GameSnapshot.first_difference(
		data.get("facts"), GameSnapshot.facts_of(game), "/facts", near
	)
	if where != "":
		return where
	var players := {}
	for p: Player in game.players:
		players[str(p.slot)] = codec.encode_fields(p)
	where = GameSnapshot.first_difference(data.get("players"), players, "/players", near)
	if where != "":
		return where
	var order: Array = []
	for e: Enemy in game.enemies:
		order.append(e.uid)
	where = GameSnapshot.first_difference(data.get("order"), order, "/order", near)
	if where != "":
		return where
	return GameSnapshot.first_difference(
		data.get("statics"), GameSnapshot.statics_of(codec), "/statics", near
	)


static func _features(codec: SnapCodec, game: Game, data: Dictionary, near: float) -> String:
	var theirs: Dictionary = data.get("features", {})
	var ours := {}
	for id: String in GameSnapshot.SIM_FEATURES:
		var feature: GameFeature = game.features.get(id)
		if feature != null:
			ours[id] = GameSnapshot.feature_row(codec, feature, id)
	return GameSnapshot.first_difference(theirs, ours, "/features", near)


static func _enemies(
	game: Game, codec: SnapCodec, data: Dictionary, from: int, near: float
) -> String:
	var theirs: Dictionary = data.get("enemies", {})
	for i in range(from, mini(from + ENEMIES, game.enemies.size())):
		var e: Enemy = game.enemies[i]
		var key := str(e.uid)
		if not theirs.has(key):
			return "/enemies/%s (not on the host)" % key
		var row := GameSnapshot.enemy_row(game, codec, i)
		var where := GameSnapshot.first_difference(theirs[key], row, "/enemies/" + key, near)
		if where != "":
			return where
	return ""
