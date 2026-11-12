## Small loose things moving over the level: gibs, the bits of a broken crate,
## a body thrown by a shot or a blast, a rolling stick of dynamite, a bowling
## ball. step() moves one for a moment: it falls, bounces off floors, walls
## and steps too high to climb (axis by axis, so it slides along a wall and is
## never left inside one), drops off ledges, lands on furniture tops, and on
## the ground rolls down the slope and slows by its drag until it rests.
##
## Pure arithmetic on the body's own numbers and the level: no dice, so it is
## the same every time (gameplay bodies stay in step; looks-only callers bring
## their own dice for how things set off).
class_name Tumble
extends RefCounted

const GRAVITY := 9.4
## The floor is sampled this far each way for its slope; a change of more than
## LEDGE between samples is a ledge to drop off, not a slope to roll down.
const SPAN := .45
const LEDGE := .5
## What step() reports.
const WALL := 1
const FLOOR := 2
const RESTED := 4


## A body step() can move: where it is, how it moves, whether it has come to
## rest. Features keep their own (a gib, a bit, a body) with these fields.
class Body:
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var vx := 0.0
	var vy := 0.0
	var vz := 0.0
	var rest := false


## How a body moves: its size against walls, how much it keeps when it hits
## something, how fast it slows rolling, how hard the slope pulls it.
class Feel:
	var radius := .05
	## Speed kept off a wall (the part into it) and off the floor (its fall).
	var wall := .4
	var bounce := .35
	## Run kept when it strikes the floor hard.
	var grip := .6
	## Slowing on the ground, units a second a second, and the slope's share of
	## gravity that pulls it downhill.
	var drag := 2.0
	var pull := .8
	## How fast it falls (shots fall by their own).
	var gravity := GRAVITY
	## How high its z stands over the floor (a bowling ball's middle).
	var lift := 0.0
	## A step up it rolls over; anything higher is a wall to it.
	var climb := .06
	## A fall faster than this bounces; slower, it settles on the floor.
	var hard := 1.2

	func _init(p_radius := .05, p_wall := .4, p_bounce := .35, p_drag := 2.0) -> void:
		radius = p_radius
		wall = p_wall
		bounce = p_bounce
		drag = p_drag


static var _shot_feels := {}


## How the player's rolling shots move: a stick of dynamite (it falls by
## shots.cfg's gravity, bounces low and rolls a little) and a bowling ball (it
## rolls on its middle, a long way, off walls).
static func shot_feel(kind: String) -> Feel:
	var feel: Feel = _shot_feels.get(kind)
	if feel != null:
		return feel
	if kind == "bowling":
		feel = Feel.new(.1, .62, .2, .35)
		feel.lift = .22
		feel.climb = .12
		feel.pull = .7
		feel.hard = 2.0
	else:
		feel = Feel.new(.045, .57, .46, .8)
		feel.grip = .64
		feel.lift = .045
		feel.hard = .77
		feel.gravity = maxf(1.0, Shots.gravity(kind))
	_shot_feels[kind] = feel
	return feel


## The downhill pull at (x, y): how much the floor falls per unit, each way.
static func slope(world: LevelData, x: float, y: float) -> Vector2:
	var here := world.elevation(x, y)
	return (
		Vector2(
			_sample(world, x - SPAN, y, here) - _sample(world, x + SPAN, y, here),
			_sample(world, x, y - SPAN, here) - _sample(world, x, y + SPAN, here)
		)
		/ (2.0 * SPAN)
	)


static func _sample(world: LevelData, x: float, y: float, here: float) -> float:
	if x < 0.0 or y < 0.0 or x >= world.width or y >= world.height:
		return here
	var cell := int(y) * world.width + int(x)
	if world.solid[cell] >= 0:
		return here
	var e: float = world.ground[cell]
	return e if absf(e - here) <= LEDGE else here


## The floor under (x, y) for something at height z: the ground, or the top of
## furniture it is over and above (a counter, a crate stack).
static func floor_at(world: LevelData, x: float, y: float, z: float) -> float:
	var out := world.elevation(x, y)
	for fixture in world.near_fixtures.get(Vector2i(int(x), int(y)), []):
		var f: PackedFloat32Array = fixture
		if f[0] < x and x < f[2] and f[1] < y and y < f[3] and f[4] <= z + .05 and f[4] > out:
			out = f[4]
	return out


## Whether a body at height z cannot be at (x, y): a wall, furniture at its
## height, or ground higher than it can climb.
static func blocks(world: LevelData, x: float, y: float, z: float, feel: Feel) -> bool:
	if world.blocked(x, y, feel.radius, z - feel.lift + feel.radius + .01):
		return true
	return world.elevation(x, y) > z - feel.lift + feel.climb


## Move `b` for dt. Returns WALL and FLOOR when it struck them hard enough to
## be heard, RESTED when it came to rest this step (the caller marks it so).
static func step(world: LevelData, b, feel: Feel, dt: float) -> int:
	var out := 0
	var under := floor_at(world, b.x, b.y, b.z - feel.lift) + feel.lift
	var grounded: bool = b.z <= under + .005 and b.vz <= 0.0
	if grounded:
		b.z = under
		b.vz = 0.0
		var down := slope(world, b.x, b.y) * feel.gravity * feel.pull
		b.vx += down.x * dt
		b.vy += down.y * dt
		var speed: float = sqrt(b.vx * b.vx + b.vy * b.vy)
		if speed > 0.0:
			var left := maxf(0.0, speed - feel.drag * dt) / speed
			b.vx *= left
			b.vy *= left
		if speed < .06 and down.length() <= feel.drag * .9:
			b.vx = 0.0
			b.vy = 0.0
			return RESTED
	else:
		b.vz -= feel.gravity * dt
	var nx: float = b.x + b.vx * dt
	if blocks(world, nx, b.y, b.z, feel):
		if absf(b.vx) > .8:
			out |= WALL
		b.vx = -b.vx * feel.wall
		b.vy *= .85
	else:
		b.x = nx
	var ny: float = b.y + b.vy * dt
	if blocks(world, b.x, ny, b.z, feel):
		if absf(b.vy) > .8:
			out |= WALL
		b.vy = -b.vy * feel.wall
		b.vx *= .85
	else:
		b.y = ny
	if grounded:
		# Off the edge of a step or a ledge, it falls from here.
		var below := floor_at(world, b.x, b.y, b.z - feel.lift) + feel.lift
		if below < b.z - .02:
			b.vz = -.01
		else:
			b.z = below
		return out
	b.z += b.vz * dt
	var roof: float = world.roof[world.cell(b.x, b.y)]
	if roof > 0.0 and b.z > roof - feel.radius and b.vz > 0.0:
		b.z = roof - feel.radius
		b.vz = -b.vz * feel.bounce
	var land := floor_at(world, b.x, b.y, b.z - feel.lift) + feel.lift
	if b.z <= land:
		b.z = land
		if b.vz < -feel.hard:
			out |= FLOOR
			b.vz = -b.vz * feel.bounce
			b.vx *= feel.grip
			b.vy *= feel.grip
		else:
			b.vz = 0.0
	return out


## A push away from (x, y) out to `reach`, strongest at the middle: the shove
## of a blast on a body at (bx, by). Vector3: the run along x and y, and the lift.
static func shove(x: float, y: float, reach: float, power: float, bx: float, by: float) -> Vector3:
	var dx := bx - x
	var dy := by - y
	var d := sqrt(dx * dx + dy * dy)
	if d >= reach:
		return Vector3.ZERO
	var k := power * (1.0 - d / reach)
	if d < .05:
		return Vector3(0.0, 0.0, k)
	return Vector3(dx / d * k, dy / d * k, k * .55)
