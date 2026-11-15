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
static func field(game: Game, x: float, y: float) -> FlowField:
	var world: LevelData = game.world
	var cell := Vector2i(int(x), int(y))
	if cell.x < 0 or cell.y < 0 or cell.x >= world.width or cell.y >= world.height:
		return null
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
	if fields.has(cell):
		return fields[cell]
	if fields.size() >= MOST:
		fields.clear()
	var floor_field: FlowField = cache["floor"]
	var made := FlowField.new(world, floor_field)
	if floor_field == null:
		cache["floor"] = made
	made.reach = world.width * world.height
	made.update(cell.x + .5, cell.y + .5, 0.0)
	fields[cell] = made
	return made


## Steps from (x, y) to the field's cell (FlowField.FAR when it does not reach).
static func steps(f: FlowField, x: float, y: float) -> int:
	if f == null:
		return FlowField.FAR
	var cx := int(x)
	var cy := int(y)
	if cx < 0 or cy < 0 or cx >= f.width or cy >= f.height:
		return FlowField.FAR
	return f.steps[cy * f.width + cx]
