## The 5v5 rounds' breakable cover: the boarded fences of the maps
## (features/wall_breaks.gd, data/tuning/breakables.cfg [fence.cover_boards]),
## the windows and the props that break (features/breakables.gd) break during
## a round, opening new ways through, and stand whole again at the next
## round's start (TacticalMode.begin_round).
##
## Each game keeps its level's walls, floor and furniture as they were built
## (remember(), from Modes.setup, before anything can break: a client's copy
## too, before a snapshot is put on it), and put_back() lays them down again
## and tells the two features to forget what broke. Every copy does it on the
## same tick, so it plays the same online; a snapshot put onto a copy that
## had something broken the snapshot has not (a copy that missed the round's
## start) lays the level down again first (GameSnapshot._apply_facts).
## Never carried: a level as built is the same on every machine.
class_name RoundCover
extends RefCounted

const WallBreaksScript := preload("res://src/features/wall_breaks.gd")
const BreakablesScript := preload("res://src/features/breakables.gd")
## Games remembered at once (a server plays two matches; checks make more).
const GAMES_KEPT := 8

## world instance id -> {walls, wall_count, solid, volumes, pieces: [x, y]}.
static var _built := {}


## Keeps `game`'s level as built (the 5v5 modes call it as the mode is set).
static func remember(game: Game) -> void:
	var w: LevelData = game.world
	var key := w.get_instance_id()
	if _built.has(key):
		return
	while _built.size() >= GAMES_KEPT:
		_built.erase(_built.keys()[0])
	var volumes: Array[PackedFloat32Array] = []
	for v: PackedFloat32Array in w.collision_volumes:
		volumes.append(v)
	var places: Array = []
	var pieces: BreakablesScript = game.features.get("breakables")
	if pieces != null:
		for p: BreakablesScript.Piece in pieces.pieces:
			places.append(Vector2(p.x, p.y))
	_built[key] = {
		"walls": w.walls.duplicate(),
		"wall_count": w.wall_count,
		"solid": w.solid.duplicate(),
		"volumes": volumes,
		"pieces": places,
	}


## Whether anything is broken, shot about or moved now.
static func broken(game: Game) -> bool:
	for id: String in GameSnapshot.FACT_FEATURES:
		var feature: GameFeature = game.features.get(id)
		if feature != null and not feature.save().is_empty():
			return true
	return false


## Lays the level down as built again if anything broke (a round's start);
## false when this game was never remembered or nothing broke.
static func put_back(game: Game) -> bool:
	var built: Variant = _built.get(game.world.get_instance_id())
	if built == null or not broken(game):
		return false
	var kept: Dictionary = built
	var w: LevelData = game.world
	var walls: PackedFloat32Array = kept["walls"]
	var solid: PackedInt32Array = kept["solid"]
	w.walls = walls.duplicate()
	w.wall_count = kept["wall_count"]
	w.solid = solid.duplicate()
	var volumes: Array[PackedFloat32Array] = []
	var was: Array[PackedFloat32Array] = kept["volumes"]
	for v: PackedFloat32Array in was:
		volumes.append(v)
	w.collision_volumes = volumes
	# The level's own lookups over its walls, floor and furniture, made again
	# (LevelData has no room for a method of its own: it is at the line limit).
	w._edge_index = {}
	w._active_key = []
	w._build_indexes()
	w.walls_version += 1
	w.solid_version += 1
	var fences: WallBreaksScript = game.features.get("wall_breaks")
	if fences != null:
		fences.forget()
	var pieces: BreakablesScript = game.features.get("breakables")
	if pieces != null:
		var places: Array = kept["pieces"]
		pieces.forget(places)
	_close_paths(game)
	game.route_sig = []
	game.fixed_sprites_key = []
	return true


## The cells a break opened, shut again in every flow field (the players'
## and the route's): open floor now solid or under furniture again.
static func _close_paths(game: Game) -> void:
	var w: LevelData = game.world
	var fields: Array[FlowField] = []
	for p: Player in game.players:
		if p.flow != null and not fields.has(p.flow):
			fields.append(p.flow)
	if game.route != null:
		fields.append(game.route)
	for cy in w.height:
		for cx in w.width:
			var cell := cy * w.width + cx
			var shut := -1
			for f: FlowField in fields:
				if f.open.size() <= cell or f.open[cell] != 1:
					continue
				if shut < 0:
					shut = (
						1
						if (w.solid[cell] >= 0 or w.blocked(cx + .5, cy + .5, FlowField.BODY))
						else 0
					)
				if shut == 1:
					f.open[cell] = 0
					f.origin = Vector2i(-1, -1)
					f.next_at = 0.0
