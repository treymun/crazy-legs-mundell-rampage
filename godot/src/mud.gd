## Mud underfoot (features/climate.gd): a floor effects.cfg [mud] names goes
## muddy in the wet and slows whatever walks it (players in game.gd
## _step_body, enemies and animals in Enemy.advance), by game.mud (the climate
## scaled by the WEATHER setting) times the tile's own share times mud_slow.
## Plain arithmetic on carried numbers: the same on every machine.
class_name Mud
extends RefCounted

## The level the table below is for, and its floor tiles' [mud] shares.
static var _level: LevelData = null
static var _table := PackedFloat32Array()


## How muddy the floor at (x, y) can get (0 to 1, the tile's [mud] share).
static func at(world: LevelData, x: float, y: float) -> float:
	if world != _level:
		_level = world
		_table = PackedFloat32Array()
		_table.resize(world.tile_names.size())
		for i in world.tile_names.size():
			var share: float = Effects.MUD.get(String(world.tile_names[i]), 0.0)
			_table[i] = share
	if x < 0.0 or y < 0.0 or x >= world.width or y >= world.height:
		return 0.0
	var tile := int(world.floor_tile[world.cell(x, y)])
	return _table[tile] if tile >= 0 and tile < _table.size() else 0.0


## The share of its speed a body keeps at (x, y): 1 on dry ground, down to
## 1 - mud_slow in the deepest mud of a long storm.
static func pace(game: GameState, x: float, y: float) -> float:
	if game.mud <= 0.0:
		return 1.0
	var slow: float = Effects.CLIMATE.get("mud_slow", .2)
	return 1.0 - slow * game.mud * at(game.world, x, y)
