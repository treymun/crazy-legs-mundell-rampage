## Whole-map step fields for the 5v5 bots (tactical_bot.gd): how far every
## open cell is from a cell they want to reach (a waypoint, a hold, a site, the
## bomb, the rescue box), as a FlowField walked over the whole level. A field
## depends only on the level's floor, so each is walked once and kept until
## the level (or its solid floor) changes. Never part of a game's state.
class_name TacticalNav
extends RefCounted

const MOST := 160

static var _fields := {}
static var _key := ""
static var _floor: FlowField = null


## The field walked from the cell under (x, y) (null when that is off the map).
static func field(game, x: float, y: float) -> FlowField:
	var world: LevelData = game.world
	var key := "%s|%d|%d" % [world.id, world.solid_version, world.get_instance_id()]
	if key != _key:
		_fields.clear()
		_key = key
		_floor = null
	var cell := Vector2i(int(x), int(y))
	if cell.x < 0 or cell.y < 0 or cell.x >= world.width or cell.y >= world.height:
		return null
	if _fields.has(cell):
		return _fields[cell]
	if _fields.size() >= MOST:
		_fields.clear()
	var made := FlowField.new(world, _floor)
	if _floor == null:
		_floor = made
	made.reach = world.width * world.height
	made.update(cell.x + .5, cell.y + .5, 0.0)
	_fields[cell] = made
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
