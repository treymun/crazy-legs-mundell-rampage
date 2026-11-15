## Small loose things moving over the level: gibs, the bits of a broken crate,
## a body thrown by a shot or a blast, a rolling stick of dynamite, a bowling
## ball. step() moves one for a moment: it falls, bounces off floors, walls
## and steps too high to climb (axis by axis, so it slides along a wall and is
## never left inside one), drops off ledges, lands on furniture tops, and on
## the ground rolls down the slope and slows by its drag until it rests.
## The level's real shape counts: a deck's top is a floor and its underside a
## roof, a ramp or a stair slab pulls it down its own slope (a flat deck over
## sloping ground does not), and the floor and roof are looked for from where
## it was before each step, so a fast fall never sinks through a deck.
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
## A thing almost still stays put while the slope pulls it at most this many
## times its drag (it holds better at rest than rolling).
const HOLD := 1.15
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


## The downhill pull at (x, y) for something resting at height z: how much
## the floor under it falls per unit, each way. On a walkable slab (a deck, a
## ramp, a stair tread) it is the slab's own slope (none on a flat deck, even
## over sloping ground); on furniture none; on the ground the cells' steps.
static func slope(world: LevelData, x: float, y: float, z := NAN) -> Vector2:
	var here := world.elevation(x, y)
	if not is_nan(z) and z > here + .02:
		var on := Vector2.ZERO
		if world.geo != null:
			var best := here
			for item: Variant in world.geo.near_items(x, y):
				if item is LevelGeometry.Slab:
					var s: LevelGeometry.Slab = item
					if not s.walk or not s.inside(x, y):
						continue
					var t := s.top_at(x, y)
					if t <= z + .02 and t > best:
						best = t
						on = Vector2(-s.gx, -s.gy)
		return on
	return _ground_slope(world, x, y, here)


static func _ground_slope(world: LevelData, x: float, y: float, here: float) -> Vector2:
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
## furniture it is over and above (a counter, a crate stack). With a radius r
## it is the highest such floor under any part of a body that wide (one coming
## down against a crate's side or a deck's edge sits on its edge, never
## half inside it).
static func floor_at(world: LevelData, x: float, y: float, z: float, r := 0.0) -> float:
	var out := world.floor_under(x, y, z + .05)
	if r > 0.0 and world.geo != null and not world.geo.clear_at(x, y):
		for k in 4:
			var px := x + (r if k & 1 else -r)
			var py := y + (r if k & 2 else -r)
			out = maxf(out, world.geo.floor_at(px, py, z + .05 - LevelGeometry.STEP, -1e9, false))
	for fixture: Variant in world.near_fixtures.get(Vector2i(int(x), int(y)), LevelData.NOTHING):
		var f: PackedFloat32Array = fixture
		if (
			f[0] - r < x
			and x < f[2] + r
			and f[1] - r < y
			and y < f[3] + r
			and f[4] <= z + .05
			and f[4] > out
		):
			out = f[4]
	return out


## Whether a body at height z cannot be at (x, y): a wall, furniture at its
## height, or ground higher than it can climb.
static func blocks(world: LevelData, x: float, y: float, z: float, feel: Feel) -> bool:
	if world.blocked(x, y, feel.radius, z - feel.lift + feel.radius + .01):
		return true
	return world.floor_under(x, y, z - feel.lift + feel.climb) > z - feel.lift + feel.climb


## Move `b` for dt. Returns WALL and FLOOR when it struck them hard enough to
## be heard, RESTED when it came to rest this step (the caller marks it so).
static func step(world: LevelData, b: Variant, feel: Feel, dt: float) -> int:
	# Typed copies of the body's numbers (b is any body with these fields: a
	# Body, a shot, a roller), written back before each return.
	var x: float = b.x
	var y: float = b.y
	var z: float = b.z
	var vx: float = b.vx
	var vy: float = b.vy
	var vz: float = b.vz
	var x0 := x
	var y0 := y
	var out := 0
	var under := floor_at(world, x, y, z - feel.lift, feel.radius) + feel.lift
	var grounded: bool = z <= under + .005 and vz <= 0.0
	var fall := Vector2.ZERO
	if grounded:
		z = under
		vz = 0.0
		fall = slope(world, x, y, z - feel.lift)
		var down := fall * feel.gravity * feel.pull
		vx += down.x * dt
		vy += down.y * dt
		var speed: float = sqrt(vx * vx + vy * vy)
		if speed > 0.0:
			var left := maxf(0.0, speed - feel.drag * dt) / speed
			vx *= left
			vy *= left
		# Slow, and the slope pulls it not much harder than it slows: it stays
		# (a thing at rest holds a little better than one rolling, so nothing
		# creeps down a gentle ramp for ever, never at rest).
		if speed < .06 and down.length() <= feel.drag * HOLD:
			vx = 0.0
			vy = 0.0
			_put(b, x, y, z, vx, vy, vz)
			return RESTED
	else:
		vz -= feel.gravity * dt
	var nx: float = x + vx * dt
	if blocks(world, nx, y, z, feel):
		if absf(vx) > .8:
			out |= WALL
		vx = -vx * feel.wall
		vy *= .85
	else:
		x = nx
	var ny: float = y + vy * dt
	if blocks(world, x, ny, z, feel):
		if absf(vy) > .8:
			out |= WALL
		vy = -vy * feel.wall
		vx *= .85
	else:
		y = ny
	if grounded:
		# Off the edge of a step or a ledge, it falls from here; down a slope it
		# keeps to the floor (a step's drop along the slope is not a ledge).
		var below := floor_at(world, x, y, z - feel.lift, feel.radius) + feel.lift
		var along := absf(fall.x * (x - x0)) + absf(fall.y * (y - y0))
		if below < z - .02 - along:
			vz = -.01
		else:
			z = below
		_put(b, x, y, z, vx, vy, vz)
		return out
	# The floor and the roof are looked for from where it was before this
	# step's fall or rise: a fast drop never passes through a deck or a
	# counter top, a fast rise never through a deck's underside.
	var was := z
	z += vz * dt
	var roof: float = world.roof_over(x, y, was)
	# Its top (a radius over its middle, which is `lift` over its z, or its
	# radius when lift is less) meets the roof.
	var head := maxf(feel.radius, 2.0 * feel.radius - feel.lift)
	if roof > 0.0 and z > roof - head and vz > 0.0:
		z = maxf(was, roof - head)
		vz = -vz * feel.bounce
	var land := floor_at(world, x, y, was - feel.lift, feel.radius) + feel.lift
	if z <= land:
		z = land
		if vz < -feel.hard:
			out |= FLOOR
			vz = -vz * feel.bounce
			vx *= feel.grip
			vy *= feel.grip
		else:
			vz = 0.0
	_put(b, x, y, z, vx, vy, vz)
	return out


## Lays `mark` on the floor under its middle as seen from height `from_z`
## (the highest floor at or below it: a deck's top, a stair, a counter, the
## ground; a ramp's tilt with it), `lift` over it so it never sinks in.
static func lay(
	world: LevelData, mark: View.GroundMark, from_z: float, lift := .004
) -> View.GroundMark:
	var top := floor_at(world, mark.x, mark.y, from_z)
	mark.z = top + lift
	mark.gx = 0.0
	mark.gy = 0.0
	if world.geo != null and top > world.elevation(mark.x, mark.y) + .001:
		for item: Variant in world.geo.near_items(mark.x, mark.y):
			if item is LevelGeometry.Slab:
				var s: LevelGeometry.Slab = item
				if (
					s.walk
					and s.sloped()
					and s.inside(mark.x, mark.y)
					and absf(s.top_at(mark.x, mark.y) - top) < .002
				):
					mark.gx = s.gx
					mark.gy = s.gy
					break
	return mark


## Whether a body lying at rest has lost what held it up (the crate it lay on
## was broken): it falls again (the caller sets it moving).
static func unsupported(world: LevelData, b: Variant, feel: Feel) -> bool:
	var x: float = b.x
	var y: float = b.y
	var z: float = b.z
	return floor_at(world, x, y, z - feel.lift, feel.radius) + feel.lift < z - .03


static func _put(b: Variant, x: float, y: float, z: float, vx: float, vy: float, vz: float) -> void:
	b.x = x
	b.y = y
	b.z = z
	b.vx = vx
	b.vy = vy
	b.vz = vz


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
