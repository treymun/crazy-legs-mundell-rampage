## The bowling pins' rigid bodies (range_bowling.gd plays the lane with them):
## each pin a real body in three dimensions, its centre of mass, its turn (a
## quaternion), its slide and its spin, with a pin's own weight and shape.
##
## A pin's shape is a chain of spheres up its axis (its foot, belly, neck and
## head, as a real pin's profile) and the ring of its foot: stood on that ring
## it rocks back short of about ten degrees and goes over past it, because its
## centre of mass then lies outside its foot, not because a number says so.
## Down, it rolls on its belly and head and slides; knocked, it spins. The
## ball is a heavy sphere rolling on the lane. Contacts are solved by
## impulses (sequential, with friction and bounce: phys_core.gd's exact
## solver, every number as it always was), a few small steps a tick, and
## penetration is pushed out afterwards; bodies that have come to rest
## sleep until something knocks them. Map coordinates throughout: x and y
## across the floor, z up; a pin's z is its centre's height above the deck.
##
## The midway games use it too (range_games.gd): a milk bottle is a body with
## its own spheres, centre of mass, foot and moments (Body.shape and the
## rest, a pin's by default), and a thrown softball is a `free` ball, falling
## and bouncing in three dimensions, where the bowling ball keeps to the lane.
extends RefCounted

## A pin's profile up its axis from its foot: [height, radius] spheres (cells).
const SPHERES := [
	[.035, .033],
	[.11, .063],
	[.18, .056],
	[.25, .034],
	[.33, .032],
	[.39, .026],
]
## Its centre of mass up the axis, its foot's radius, its length.
const COM := .16
const FOOT := .028
const LENGTH := .417
## Its mass (1) and moments about its centre: across the axis, along it.
const INERTIA_ACROSS := .0113
const INERTIA_ALONG := .0016
const BALL_MASS := 4.6
const BALL_R := .118
const GRAVITY := 10.7
## Bounce: pin on pin, ball on pin, pin on the deck, on a kickback, the cushion.
const E_PIN := .6
const E_BALL := .7
const E_FLOOR := .25
const E_WALL := .45
const E_CUSHION := .05
## Friction: pin on the deck, pin on pin, ball on pin, on the walls.
const MU_FLOOR := .25
const MU_PIN := .15
const MU_BALL := .1
const MU_WALL := .2
## Closing speeds below this do not bounce (a resting contact stays resting).
const BOUNCE_FROM := .35
## Spin lost each second in the air, and rolling on the deck.
const AIR_DAMP := .3
const ROLL_DAMP := 2.6
## A pin lying on the deck loses its slide this fast (rolling resistance, a
## share a second) on top of its friction.
const ROLL_DRAG := 1.4
## Penetration left alone, and how much of the rest is pushed out a step.
const SLOP := .002
const PUSH := .8
## Asleep: slower than these (cells a second, radians a second) this long.
const SLEEP_V := .1
const SLEEP_W := .6
const SLEEP_AFTER := .3
## Solver passes over the contacts each step.
const PASSES := 4


## One body this tick (a pin, or the ball with `ball` set): PhysCore's rigid
## body (its middle, turn, slide, spin, weight), asleep until knocked.
class Body:
	extends PhysCore.Body
	var rest := 0.0
	var ball := false
	## Its spheres up the axis [height, radius], centre of mass, foot's radius
	## and moments (a pin's unless set: a milk bottle's are its own).
	var shape: Array = SPHERES
	var com := COM
	var foot_r := FOOT
	var i_across := INERTIA_ACROSS
	var i_along := INERTIA_ALONG
	## A ball's radius; a free ball falls and bounces in 3D (a thrown one).
	var radius := BALL_R
	var free := false
	## Its spheres' centres this step (spheres()).
	var sph: Array = []

	func _init() -> void:
		awake = false

	## Its axis (a pin's foot to head), world.
	func axis() -> Vector3:
		return q * Vector3(0.0, 0.0, 1.0)

	## The inverse inertia applied to `t` (a pin's is round about its axis).
	func inv_inertia(t: Vector3) -> Vector3:
		if ball or not awake:
			return Vector3.ZERO
		var u := axis()
		var along := u * u.dot(t)
		return along / i_along + (t - along) / i_across

	func mass_inv() -> float:
		return inv_m if awake or ball else 0.0

	func wake() -> void:
		if not ball:
			awake = true
			rest = 0.0


# A contact is a PhysCore.Contact: `kind` 0 a wall, 1 pin on pin, 2 ball on
# pin, 3 the deck (1 and 2 are heard); `cushion` the lane's end.

## The world's floor under (x, y) relative to the deck, given by the lane.
var floor_at: Callable
## Walls: [x min, x max] (the kickbacks), the cushion's y, the foul line's y,
## and the lane's span in y where the kickbacks stand.
var kick := Vector2.ZERO
var cushion := 0.0
var foul := 0.0
## Hard knocks this tick, and where the last was (for the clatter).
var knocks := 0
var knock_at := Vector2.ZERO
var first_hit := false


## A pin's sphere centres, world.
static func spheres(b: Body) -> Array:
	var u := b.axis()
	var out: Array = []
	for s: Array in b.shape:
		var h: float = s[0]
		out.append(b.p + u * (h - b.com))
	return out


## A pin's foot (its base's middle), world.
static func foot(b: Body) -> Vector3:
	return b.p - b.axis() * b.com


## Step the bodies `h` seconds: pins (any may be asleep) and the ball (or
## null). The ball's height is held; its slide is the solver's.
func step(pins: Array, ball: Body, h: float) -> void:
	for b: Body in pins:
		if b.awake:
			b.v.z -= GRAVITY * h
	var contacts: Array = []
	if ball != null and ball.free:
		ball.v.z -= GRAVITY * h
		var under: float = floor_at.call(ball.p.x, ball.p.y)
		var low := under - (ball.p.z - ball.radius)
		if low > 0.0:
			_add_world(
				ball,
				ball.p - Vector3(0, 0, ball.radius),
				Vector3(0.0, 0.0, 1.0),
				low,
				MU_FLOOR,
				contacts
			)
	for b: Body in pins:
		b.sph = spheres(b)
	for b: Body in pins:
		b.grounded = false
		if b.awake:
			_floor_contacts(b, contacts)
			_wall_contacts(b, contacts)
	for i in pins.size():
		var a: Body = pins[i]
		for k in range(i + 1, pins.size()):
			var o: Body = pins[k]
			if not a.awake and not o.awake:
				continue
			if a.p.distance_squared_to(o.p) > .25:
				continue
			_pin_pair(a, o, contacts)
		if ball != null:
			_ball_pin(ball, a, contacts)
	_prepare(contacts, h)
	for _pass in PASSES:
		for c: PhysCore.Contact in contacts:
			c.solve_exact()  # (PhysCore.solve)
	for c: PhysCore.Contact in contacts:
		if c.jn > .18 and (c.kind == 1 or c.kind == 2):
			knocks += 1
			var at := c.a.p + c.ra
			knock_at = Vector2(at.x, at.y)
	for b: Body in pins:
		if not b.awake:
			continue
		PhysCore.integrate(b, h)
		b.w *= exp(-(ROLL_DAMP if b.grounded else AIR_DAMP) * h)
		if b.grounded and b.axis().z < .5:
			b.v *= exp(-ROLL_DRAG * h)
		if b.grounded and b.v.length() < SLEEP_V and b.w.length() < SLEEP_W:
			b.rest += h
			if b.rest > SLEEP_AFTER:
				b.awake = false
				b.v = Vector3.ZERO
				b.w = Vector3.ZERO
		else:
			b.rest = 0.0
	if ball != null:
		if not ball.free:
			ball.v.z = 0.0
		ball.p += ball.v * h
	_push_out(contacts)


func _floor_contacts(b: Body, out: Array) -> void:
	var u := b.axis()
	var r := 0
	for c: Vector3 in b.sph:
		var sphere: Array = b.shape[r]
		var rad: float = sphere[1]
		r += 1
		var under: float = floor_at.call(c.x, c.y)
		var depth := under - (c.z - rad)
		if depth > 0.0:
			_add_world(
				b, Vector3(c.x, c.y, c.z - rad), Vector3(0.0, 0.0, 1.0), depth, MU_FLOOR, out
			)
	# The foot's ring, while it is anywhere near standing.
	if u.z > .3:
		var base := foot(b)
		var side := u.cross(Vector3(1.0, 0.0, 0.0))
		if side.length_squared() < 1e-4:
			side = u.cross(Vector3(0.0, 1.0, 0.0))
		side = side.normalized()
		var other := u.cross(side)
		for k in 6:
			var a := k * TAU / 6.0
			var pt := base + (side * cos(a) + other * sin(a)) * b.foot_r
			var under: float = floor_at.call(pt.x, pt.y)
			if pt.z < under:
				_add_world(b, pt, Vector3(0.0, 0.0, 1.0), under - pt.z, MU_FLOOR, out)


func _wall_contacts(b: Body, out: Array) -> void:
	var r := 0
	for c: Vector3 in b.sph:
		var sphere: Array = b.shape[r]
		var rad: float = sphere[1]
		r += 1
		if c.y > foul + .5 or c.y < cushion - .6:
			continue
		if c.x - rad < kick.x:
			_add_world(
				b, c - Vector3(rad, 0, 0), Vector3(1, 0, 0), kick.x - (c.x - rad), MU_WALL, out
			)
		elif c.x + rad > kick.y:
			_add_world(
				b, c + Vector3(rad, 0, 0), Vector3(-1, 0, 0), c.x + rad - kick.y, MU_WALL, out
			)
		if c.y - rad < cushion:
			var hit := _add_world(
				b, c - Vector3(0, rad, 0), Vector3(0, 1, 0), cushion - (c.y - rad), .6, out
			)
			hit.cushion = true
		elif c.y + rad > foul:
			_add_world(b, c + Vector3(0, rad, 0), Vector3(0, -1, 0), c.y + rad - foul, MU_WALL, out)


func _add_world(
	b: Body, at: Vector3, n: Vector3, depth: float, mu: float, out: Array
) -> PhysCore.Contact:
	var c := PhysCore.Contact.new()
	c.a = b
	c.b = null
	c.ra = at - b.p
	c.n = n
	c.depth = depth
	c.mu = mu
	if n.z > .5:
		b.grounded = true
		c.kind = 3
	out.append(c)
	return c


## Pin on pin: the deepest of their spheres' overlaps.
func _pin_pair(a: Body, o: Body, out: Array) -> void:
	var sa := a.sph
	var so := o.sph
	var best := 0.0
	var at := Vector3.ZERO
	var n := Vector3.ZERO
	for i in sa.size():
		var sphere_a: Array = a.shape[i]
		var ra: float = sphere_a[1]
		var ca: Vector3 = sa[i]
		for k in so.size():
			var sphere_k: Array = o.shape[k]
			var rk: float = sphere_k[1]
			var ck: Vector3 = so[k]
			var gap := ca - ck
			var d := gap.length()
			var depth := ra + rk - d
			if depth > best and d > 1e-6:
				best = depth
				n = gap / d
				at = ck + n * (rk - depth * .5)
	if best <= 0.0:
		return
	a.wake()
	o.wake()
	var c := PhysCore.Contact.new()
	c.a = a
	c.b = o
	c.ra = at - a.p
	c.rb = at - o.p
	c.n = n
	c.depth = best
	c.mu = MU_PIN
	c.kind = 1
	out.append(c)


## The ball on a pin: the ball is `a` (it is pushed off the pin).
func _ball_pin(ball: Body, pin: Body, out: Array) -> void:
	if ball.p.distance_squared_to(pin.p) > .4:
		return
	var best := 0.0
	var at := Vector3.ZERO
	var n := Vector3.ZERO
	var r := 0
	for c: Vector3 in spheres(pin):
		var sphere: Array = pin.shape[r]
		var rad: float = sphere[1]
		r += 1
		var gap := ball.p - c
		var d := gap.length()
		var depth := ball.radius + rad - d
		if depth > best and d > 1e-6:
			best = depth
			n = gap / d
			at = c + n * (rad - depth * .5)
	if best <= 0.0:
		return
	pin.wake()
	if not first_hit:
		first_hit = true
	var ct := PhysCore.Contact.new()
	ct.a = ball
	ct.b = pin
	ct.ra = at - ball.p
	ct.rb = at - pin.p
	ct.n = n
	ct.depth = best
	ct.mu = MU_BALL
	ct.kind = 2
	out.append(ct)


## Each contact's bounce by its kind, then PhysCore's exact preparing.
func _prepare(contacts: Array, h: float) -> void:
	for c: PhysCore.Contact in contacts:
		var e := E_FLOOR
		match c.kind:
			1:
				e = E_PIN
			2:
				e = E_BALL
			0:
				e = E_CUSHION if c.cushion else E_WALL
		c.e = e
	PhysCore.prepare(contacts, h, BOUNCE_FROM)


## Penetration left after the step pushed out (the bodies' places only).
func _push_out(contacts: Array) -> void:
	for c: PhysCore.Contact in contacts:
		var d := c.depth - SLOP
		if d <= 0.0:
			continue
		var ia := c.a.mass_inv()
		var ib := 0.0 if c.b == null else c.b.mass_inv()
		if ia + ib <= 0.0:
			continue
		var move := c.n * d * PUSH / (ia + ib)
		var a: Body = c.a
		if a.ball and not a.free:
			a.p += Vector3(move.x, move.y, 0.0) * ia
		elif a.ball:
			a.p += move * ia
		elif a.awake:
			a.p += move * ia
		if c.b != null:
			var o: Body = c.b
			if o.awake or o.ball:
				o.p -= move * ib
