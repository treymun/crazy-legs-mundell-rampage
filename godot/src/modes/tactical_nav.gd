## Whole-map step fields for the 5v5 bots (tactical_bot.gd): how far every
## open cell is from a cell they want to reach (a waypoint, a hold, a site, the
## bomb, the rescue box), as a FlowField walked over the whole level. A field
## depends only on the level's floor, so each is walked once and kept until
## the level (or its solid floor) changes. Never part of a game's state.
class_name TacticalNav
extends RefCounted

const MOST := 160
## Worlds kept at once, the one used longest ago going first: an always-open
## server plays two matches, and client copies share the process with the
## server in the checks. One cache for all of them cleared itself at every
## switch and walked whole-map fields again each tick.
const WORLDS := 8

## world instance id -> {"solid": its solid_version, "fields": cell ->
## FlowField, "floor": FlowField}, the one used last at the end.
static var _worlds := {}
static var _last := -1
## WORLDS, or 1 (tools/net_lag.gd old: one cache for every game, as before).
static var worlds_kept := WORLDS


## The field walked from the cell under (x, y) (null when that is off the map).
## `z`: the floor there on a map of storeys (pass 16; NAN the cell's own, as
## ever): a place on a deck has a field of its own.
static func field(game: Game, x: float, y: float, z := NAN) -> FlowField:
	var world: LevelData = game.world
	var cell := Vector2i(int(x), int(y))
	if cell.x < 0 or cell.y < 0 or cell.x >= world.width or cell.y >= world.height:
		return null
	var place: Vector2i = cell
	var up := NAN
	if not is_nan(z) and world.geo != null:
		var node := world.geo.nav(world).node_at(x, y, world.width, world.height, z)
		if node >= world.width * world.height:
			# (Kept under a key no cell has.)
			place = Vector2i(-1 - node, -1)
			up = z
	var key := world.get_instance_id()
	var kept: Variant = _worlds.get(key)
	if kept == null:
		while _worlds.size() >= worlds_kept:
			_worlds.erase(_worlds.keys()[0])
		kept = {"solid": world.solid_version, "fields": {}, "floor": null}
		_worlds[key] = kept
	elif key != _last:
		# Used now: to the end, the last to go.
		_worlds.erase(key)
		_worlds[key] = kept
	_last = key
	var cache: Dictionary = kept
	if cache["solid"] != world.solid_version:
		# Its floor changed (a fence shot through, a round's reset).
		cache["solid"] = world.solid_version
		cache["fields"] = {}
		cache["floor"] = null
	var fields: Dictionary = cache["fields"]
	if fields.has(place):
		return fields[place]
	if fields.size() >= MOST:
		fields.clear()
	var floor_field: FlowField = cache["floor"]
	var made := FlowField.new(world, floor_field)
	if floor_field == null:
		cache["floor"] = made
	made.reach = world.width * world.height
	made.update(cell.x + .5, cell.y + .5, 0.0, up)
	fields[place] = made
	return made


## The floor a bot's goal at `at` is on, on a map of storeys (pass 16): a
## player standing there's, or the map's own for a route point [x, y, z] or a
## hold [x, y, facing, z]; NAN (the ground) else, and on every other map.
static func floor_of(game: Game, at: Vector2) -> float:
	var world: LevelData = game.world
	if world.geo == null:
		return NAN
	for p: Player in game.players:
		if p.health > 0 and Vector2(p.x, p.y).distance_to(at) < .3:
			return world.stand(p)
	var known: Variant = _floors.get(world.get_instance_id())
	if known == null:
		known = _map_floors(world.tactical)
		if _floors.size() >= worlds_kept:
			_floors.clear()
		_floors[world.get_instance_id()] = known
	var floors: Dictionary = known
	var key := Vector2i(roundi(at.x * 100.0), roundi(at.y * 100.0))
	return floors.get(key, NAN)


## world instance id -> its map's floors (_map_floors).
static var _floors := {}


## The points of a tactical block given with a floor: (x, y) in centimetres
## -> z.
static func _map_floors(plan: Dictionary) -> Dictionary:
	var out := {}
	var routes: Variant = plan.get("routes", {})
	if routes is Dictionary:
		for site: Variant in routes:
			var listed: Variant = routes[site]
			for route: Variant in listed if listed is Array else []:
				for point: Variant in route if route is Array else []:
					_floor_point(out, point, 2)
	var holds: Variant = plan.get("holds", {})
	if holds is Dictionary:
		for site: Variant in holds:
			var listed: Variant = holds[site]
			for row: Variant in listed if listed is Array else []:
				_floor_point(out, row, 3)
	return out


static func _floor_point(out: Dictionary, point: Variant, at: int) -> void:
	if not (point is Array):
		return
	var row: Array = point
	if row.size() <= at:
		return
	var x: Variant = row[0]
	var y: Variant = row[1]
	var z: Variant = row[at]
	if (x is float or x is int) and (y is float or y is int) and (z is float or z is int):
		var fx: float = x
		var fy: float = y
		var fz: float = z
		out[Vector2i(roundi(fx * 100.0), roundi(fy * 100.0))] = fz


## Steps from (x, y) to the field's cell (FlowField.FAR when it does not reach).
## `z`: the floor there on a map of storeys (pass 16; NAN the cell's own).
static func steps(f: FlowField, x: float, y: float, z := NAN) -> int:
	if f == null:
		return FlowField.FAR
	if not is_nan(z) and f.graph != null:
		return f.distance(x, y, z)
	var cx := int(x)
	var cy := int(y)
	if cx < 0 or cy < 0 or cx >= f.width or cy >= f.height:
		return FlowField.FAR
	return f.steps[cy * f.width + cx]
