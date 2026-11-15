## How a sound from a place in the world reaches the local player's ears
## (Game.sound_position, Game.sound_cutoff): what lies between them, and how
## far apart they are counting height. Looks and sound only: it reads the
## level, the bodies and the listener's flow field and changes none of them.
##
## - Height: a source a floor above or below is that much farther off (the
##   first HEIGHT_FREE of the gap is a mouth and an ear on one floor).
## - In the way: the level's own sight test (LevelData.visible) from the ear
##   to the source. On a level with geometry it runs at their heights, so a
##   deck or a floor between them stops it as a wall does, and that is duller
##   still (THROUGH_FLOOR_*): a floor is thicker than a board wall.
## - Round the corner: when the straight line is blocked, the listener's flow
##   field (Player.flow, the steps enemies walk to them, already worked out
##   for the tick) says how far the way round is. A sound one doorway or one
##   stairwell away comes round it only a little dull (ROUND_*), not as if
##   through solid wall. Used only when the field is the listener's own and
##   fresh (it is walked from the cell they stand in).
##
## Game asks for the volume and then the cutoff of one place back to back;
## the answer for the last place is kept for that tick.
class_name Hearing
extends RefCounted

## Through a wall: the level and the cutoff it always had.
const THROUGH_WALL_GAIN := .43
const THROUGH_WALL_CUTOFF := 1300.0
## Through a floor or a deck.
const THROUGH_FLOOR_GAIN := .32
const THROUGH_FLOOR_CUTOFF := 800.0
## Round a corner or up a stair: a way round at most ROUND_SLACK times the
## straight line plus ROUND_EXTRA steps.
const ROUND_GAIN := .72
const ROUND_CUTOFF := 3600.0
const ROUND_SLACK := 1.7
const ROUND_EXTRA := 3.0
## Height gaps under this count for nothing.
const HEIGHT_FREE := .6
## A source's height over its floor when nothing says better (a body's chest).
const SOURCE_RISE := .6

## The last place asked about, and what was found.
var _at := Vector2(INF, INF)
var _ear := Vector3(INF, INF, INF)
var _clock := -1.0
var _gain := 1.0
var _cutoff := Sound.OPEN_CUTOFF
var _rise := 0.0


## How much the sound from (x, y) is cut by what is in the way (1 nothing).
func gain(game: Game, x: float, y: float) -> float:
	_find(game, x, y)
	return _gain


## The low-pass cutoff of what is in the way (Sound.OPEN_CUTOFF nothing).
func cutoff(game: Game, x: float, y: float) -> float:
	_find(game, x, y)
	return _cutoff


## The height between ear and source that counts as distance.
func rise(game: Game, x: float, y: float) -> float:
	_find(game, x, y)
	return _rise


func _find(game: Game, x: float, y: float) -> void:
	var p := game.local_player
	var ear := Vector3(p.x, p.y, p.eye)
	if Vector2(x, y) == _at and ear == _ear and game.clock == _clock:
		return
	_at = Vector2(x, y)
	_ear = ear
	_clock = game.clock
	var world := game.world
	var floor_z := _source_floor(game, x, y)
	var mouth := floor_z + _source_rise(game, x, y)
	_rise = maxf(0.0, absf(mouth - p.eye) - HEIGHT_FREE)
	_gain = 1.0
	_cutoff = Sound.OPEN_CUTOFF
	var layered := world.geo != null
	# Height matters to the sight line only where floors stack (geometry); a
	# grid level keeps the flat test it always had.
	var clear := (
		world.visible(p.x, p.y, x, y, p.eye, mouth) if layered else world.visible(p.x, p.y, x, y)
	)
	if clear:
		return
	if _round_the_corner(game, x, y, floor_z):
		_gain = ROUND_GAIN
		_cutoff = ROUND_CUTOFF
	elif layered and _rise > 0.0 and world.visible(p.x, p.y, x, y):
		# Open from above but not at their heights: a floor between them.
		_gain = THROUGH_FLOOR_GAIN
		_cutoff = THROUGH_FLOOR_CUTOFF
	else:
		_gain = THROUGH_WALL_GAIN
		_cutoff = THROUGH_WALL_CUTOFF


## The floor the source stands on: a body standing exactly there gives its
## own; anything else the highest floor there at or under the listener's eye
## (on one floor with them unless there is no floor that high).
func _source_floor(game: Game, x: float, y: float) -> float:
	var world := game.world
	# Ambient sounds (a flock overhead) may sit off the map: hear them from
	# its nearest edge.
	x = clampf(x, 0.0, world.width - .001)
	y = clampf(y, 0.0, world.height - .001)
	if world.geo == null:
		return world.elevation(x, y)
	var body: Variant = _body_at(game, x, y)
	if body != null:
		return world.stand(body)
	return world.floor_under(x, y, game.local_player.eye)


func _source_rise(game: Game, x: float, y: float) -> float:
	if game.world.geo == null:
		return SOURCE_RISE
	var body: Variant = _body_at(game, x, y)
	if body is Enemy:
		var e: Enemy = body
		return e.z + minf(.92, e.height * .6)
	return SOURCE_RISE


## An enemy or a player standing exactly at (x, y): most placed sounds are a
## body's own (its gun, its cry, its fall), handed over as its x and y.
func _body_at(game: Game, x: float, y: float) -> Variant:
	for e: Enemy in game.enemies:
		if e.x == x and e.y == y:
			return e
	for q: Player in game.players:
		if q.x == x and q.y == y:
			return q
	return null


## Whether the way round from the source to the listener is short enough to
## carry the sound (the listener's own flow field, only while it is fresh).
func _round_the_corner(game: Game, x: float, y: float, floor_z: float) -> bool:
	var p := game.local_player
	var field := p.flow
	if field == null:
		return false
	var world := game.world
	var here := world.stand(p)
	if field.distance(p.x, p.y, here) != 0:
		return false
	var steps := field.distance(x, y, floor_z)
	if steps >= FlowField.FAR:
		return false
	var straight := Vector2(x - p.x, y - p.y).length()
	return float(steps) <= straight * ROUND_SLACK + ROUND_EXTRA
