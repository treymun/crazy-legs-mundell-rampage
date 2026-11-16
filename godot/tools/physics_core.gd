## physics_check.gd's part for the shared physics core (src/phys_core.gd; run
## from there, after the ragdolls, whose rig it borrows).
##
## - The exact solver works out every number as the bowling pins always did:
##   a set of contacts solved by the old formulas written out here and by
##   PhysCore.prepare/solve ends the same to the last bit.
## - The grid finds the same neighbours as asking every body.
## - Box.ball_out pushes a ball out of a box the right way.
## - Wreck pieces on the fast solver: a box dropped on the ground rests on it
##   and sleeps; three stacked rest on one another and sleep; the bottom one
##   knocked away wakes the two on it at once (PhysCore.wake_resting_on); the
##   same throw twice lands the same.
## - Things of two solvers meet (looks only): a ragdoll dropped on a wreck
##   piece lies on it, not through it; a wreck piece dropped on a ragdoll
##   lying still comes to rest on the body.
extends RefCounted

const DT := 1.0 / 60.0
const R := preload("res://src/view3d/ragdoll_rig.gd")

var check: SceneTree
## Open ground on the level (_spot): plain cells all round, nothing over it.
var at := Vector2.ZERO


func _init(owner: SceneTree) -> void:
	check = owner


func _check(ok: bool, text: String) -> void:
	check.call("_check", ok, text)


func _ok(text: String) -> void:
	check.call("_ok", text)


func run(main: Node) -> void:
	_exact()
	_grid()
	_ball_out()
	var game: Game = main.make_game("hickston")
	game.configure({})
	at = _spot(game)
	_drop(game)
	_stack(game)
	_twice(game)
	var rig: RagdollRig = RagdollRig._built.get("billy")
	_check(rig != null and rig.ok, "the ragdoll rig to meet the pieces with is built")
	if rig != null and rig.ok:
		_doll_on_box(game, rig)
		_box_on_doll(game, rig)
	PhysCore.space(game.world).boxes = []
	Ragdoll.others = []


# ------------------------------------------------------------------ exact


## A pin-like body for the exact solver (round about its axis).
class Pin:
	extends PhysCore.Body
	var i_across := .0113
	var i_along := .0016

	func inv_inertia(t: Vector3) -> Vector3:
		if not awake:
			return Vector3.ZERO
		var u := q * Vector3(0.0, 0.0, 1.0)
		var along := u * u.dot(t)
		return along / i_along + (t - along) / i_across


## The old formulas (range_pin_physics.gd before the core), written out.
static func _old_rel(c: PhysCore.Contact) -> Vector3:
	var v := c.a.v + c.a.w.cross(c.ra)
	if c.b != null:
		v -= c.b.v + c.b.w.cross(c.rb)
	return v


static func _old_mass(c: PhysCore.Contact, d: Vector3) -> float:
	var k := c.a.mass_inv() + c.a.inv_inertia(c.ra.cross(d)).cross(c.ra).dot(d)
	if c.b != null:
		k += c.b.mass_inv() + c.b.inv_inertia(c.rb.cross(d)).cross(c.rb).dot(d)
	return 1.0 / k if k > 1e-9 else 0.0


static func _old_apply(c: PhysCore.Contact, j: Vector3) -> void:
	c.a.v += j * c.a.mass_inv()
	c.a.w += c.a.inv_inertia(c.ra.cross(j))
	if c.b != null:
		c.b.v += -j * c.b.mass_inv()
		c.b.w += c.b.inv_inertia(c.rb.cross(-j))


static func _old_solve(contacts: Array, passes: int) -> void:
	for c: PhysCore.Contact in contacts:
		c.mass_n = _old_mass(c, c.n)
		var closing := _old_rel(c).dot(c.n)
		c.bias = -c.e * closing if closing < -.35 else 0.0
	for _p in passes:
		for c: PhysCore.Contact in contacts:
			if c.mass_n <= 0.0:
				continue
			var vn := _old_rel(c).dot(c.n)
			var dj := (c.bias - vn) * c.mass_n
			var total := maxf(c.jn + dj, 0.0)
			dj = total - c.jn
			c.jn = total
			_old_apply(c, c.n * dj)
			var vr := _old_rel(c)
			var slip := vr - c.n * vr.dot(c.n)
			var speed := slip.length()
			if speed < 1e-6:
				continue
			var t := slip / speed
			var k := _old_mass(c, t)
			var want := c.jt - t * speed * k
			var most := c.mu * c.jn
			if want.length() > most:
				want = want.normalized() * most
			_old_apply(c, want - c.jt)
			c.jt = want


## The same scene of three pins and their contacts, twice.
static func _scene() -> Array:
	var dice := RandomNumberGenerator.new()
	dice.seed = 41
	var pins: Array = []
	for k in 3:
		var b := Pin.new()
		b.p = Vector3(k * .12, 0.0, .16)
		b.q = Quaternion(Vector3(1.0, .3, 0.0).normalized(), dice.randf_range(-.4, .4))
		b.v = Vector3(dice.randf_range(-2, 2), dice.randf_range(-2, 2), dice.randf_range(-1, 0))
		b.w = Vector3(dice.randf_range(-5, 5), dice.randf_range(-5, 5), dice.randf_range(-5, 5))
		pins.append(b)
	var contacts: Array = []
	for k in 6:
		var c := PhysCore.Contact.new()
		c.a = pins[k % 3]
		c.b = null if k < 3 else pins[(k + 1) % 3]
		c.ra = Vector3(dice.randf_range(-.05, .05), dice.randf_range(-.05, .05), -.15)
		c.rb = Vector3(dice.randf_range(-.05, .05), dice.randf_range(-.05, .05), .1)
		c.n = Vector3(dice.randf_range(-.3, .3), dice.randf_range(-.3, .3), 1.0).normalized()
		c.depth = .01
		c.mu = .25
		c.e = .6
		contacts.append(c)
	return [pins, contacts]


func _exact() -> void:
	var old_run := _scene()
	_old_solve(old_run[1], 4)
	var new_run := _scene()
	PhysCore.prepare(new_run[1], 1.0 / 240.0, .35)
	for _p in 4:
		for c: PhysCore.Contact in new_run[1]:
			PhysCore.solve(c)
	var same := true
	for k in 3:
		var a: Pin = old_run[0][k]
		var b: Pin = new_run[0][k]
		same = same and a.v == b.v and a.w == b.w
	for k in 6:
		var a: PhysCore.Contact = old_run[1][k]
		var b: PhysCore.Contact = new_run[1][k]
		same = same and a.jn == b.jn and a.jt == b.jt
	_check(same, "the exact solver ends every number as the pins' old one did")
	_ok("the exact solver (the pins'): the same to the last bit as before")


# ------------------------------------------------------------------ the grid


func _grid() -> void:
	var dice := RandomNumberGenerator.new()
	dice.seed = 9
	var at: Array[Vector2] = []
	var reach: Array[float] = []
	var grid := PhysCore.Grid.new()
	grid.clear(60)
	for i in 60:
		at.append(Vector2(dice.randf_range(10, 16), dice.randf_range(10, 16)))
		reach.append(dice.randf_range(.05, .7))
		grid.add(i, at[i].x, at[i].y, reach[i])
	var wrong := 0
	for i in 60:
		var found := grid.near(at[i].x, at[i].y, reach[i])
		for k in 60:
			var r := reach[i] + reach[k]
			var close := absf(at[i].x - at[k].x) <= r and absf(at[i].y - at[k].y) <= r
			if close and not found.has(k):
				wrong += 1
		var once := {}
		for k in found:
			if once.has(k):
				wrong += 1
			once[k] = true
	_check(wrong == 0, "the grid finds every near body once (%d wrong)" % wrong)
	_ok("the grid: 60 bodies, every near one found once")


func _ball_out() -> void:
	var box := PhysCore.Box.new()
	box.q = Quaternion(Vector3(0.0, 0.0, 1.0), .5)
	box.shape(Vector3(.3, .2, .1), 500.0)
	box.p = Vector3(5.0, 5.0, 1.0)
	var up := box.ball_out(Vector3(5.0, 5.0, 1.15), .1)
	var clear := box.ball_out(Vector3(5.0, 5.0, 1.25), .1)
	var middle := box.ball_out(Vector3(5.0, 5.0, 1.05), .1)
	_check(
		up.z > .04 and absf(up.x) < 1e-5 and clear == Vector3.ZERO and middle.z > .14,
		"a ball in a box is pushed out of it the right way (%s, %s, %s)" % [up, clear, middle]
	)
	_ok("a ball in a box: out through the nearest face, none when clear")


# ------------------------------------------------------------------ pieces


func _ground(game: Game) -> float:
	return Tumble.floor_at(game.world, at.x, at.y, 99.0)


## The open cell nearest the player's start with plain ground three cells
## every way (PhysCore.plain_under).
static func _spot(game: Game) -> Vector2:
	var w := game.world
	var from := Vector2(game.player.x, game.player.y)
	var best := from
	var near := INF
	for cy in range(3, w.height - 3):
		for cx in range(3, w.width - 3):
			var c := Vector2(cx + .5, cy + .5)
			var d := c.distance_squared_to(from)
			if d >= near:
				continue
			if not is_nan(PhysCore.plain_under(w, Vector3(c.x, c.y, 0.0), 2.5)):
				near = d
				best = c
	return best


func _box(at: Vector3, half: Vector3, turn := 0.0) -> WreckPhysics.Body:
	var b := WreckPhysics.Body.new()
	b.q = Quaternion(Vector3(.3, 1.0, .2).normalized(), turn)
	b.p = at
	b.shape(half, 500.0)
	return b


## Step until every piece sleeps (or `most` ticks); the ticks taken.
static func _settle(physics: WreckPhysics, most := 900) -> int:
	for t in most:
		if not physics.moving():
			return t
		physics.step(DT, 2)
	return most


func _drop(game: Game) -> void:
	var physics := WreckPhysics.new(game.world)
	var floor_z := _ground(game)
	var b := _box(Vector3(at.x, at.y, floor_z + 1.0), Vector3(.2, .1, .04), .7)
	b.w = Vector3(3.0, -2.0, 1.0)
	physics.bodies.append(b)
	var took := _settle(physics)
	var low := INF
	for k in 8:
		low = minf(low, (b.p + Basis(b.q) * b.points[k]).z)
	_check(
		not b.awake and absf(low - floor_z) < .02,
		"a box dropped on the ground rests on it and sleeps (gap %.3f)" % (low - floor_z)
	)
	_ok("a box dropped on the ground: asleep on it in %.1f s" % (took * DT))


func _stack(game: Game) -> void:
	var physics := WreckPhysics.new(game.world)
	var floor_z := _ground(game)
	for k in 3:
		var half := Vector3(.3 - k * .06, .3 - k * .06, .06)
		var b := _box(Vector3(at.x, at.y, floor_z + .1 + k * .2), half)
		b.q = Quaternion(Vector3(0.0, 0.0, 1.0), k * .4)
		b.turned()
		# (Pieces of one break pass through one another a moment.)
		b.group = k + 1
		physics.bodies.append(b)
	_settle(physics)
	var bottom: WreckPhysics.Body = physics.bodies[0]
	var mid: WreckPhysics.Body = physics.bodies[1]
	var top: WreckPhysics.Body = physics.bodies[2]
	var ordered := bottom.p.z < mid.p.z - .08 and mid.p.z < top.p.z - .08
	_check(
		not physics.moving() and ordered,
		(
			"three boxes stacked rest on one another and sleep (%.2f %.2f %.2f)"
			% [bottom.p.z, mid.p.z, top.p.z]
		)
	)
	_check(
		mid.under == bottom and top.under == mid,
		"each remembers what it lies on (%s, %s)" % [mid.under == bottom, top.under == mid]
	)
	# The bottom one knocked out from under them: they wake at once and fall.
	WreckPhysics.knock(bottom, Vector3(6.0, 0.0, .5), Vector3.ZERO)
	physics.step(DT, 2)
	_check(mid.awake and top.awake, "the bottom one knocked away wakes the two on it at once")
	var was := top.p.z
	_settle(physics)
	_check(top.p.z < was - .1, "and they come down (%.2f to %.2f)" % [was, top.p.z])
	_ok("three stacked rest and sleep; the bottom one knocked away, the rest wake and fall")


## The same throw twice ends the same (looks, but the same every time).
func _twice(game: Game) -> void:
	var ends: Array = []
	for run in 2:
		var physics := WreckPhysics.new(game.world)
		var floor_z := _ground(game)
		for k in 6:
			var b := _box(
				Vector3(at.x + k * .05, at.y, floor_z + .4 + k * .1), Vector3(.15, .05, .03), k
			)
			b.v = Vector3(1.0 - k * .3, .5, 1.0)
			b.w = Vector3(k, 2.0, -1.0)
			physics.bodies.append(b)
		_settle(physics)
		var end := ""
		for item: Variant in physics.bodies:
			var b: WreckPhysics.Body = item
			end += var_to_str(b.p) + var_to_str(b.q)
		ends.append(end)
	_check(ends[0] == ends[1], "the same throw twice lands the same")
	_ok("six pieces thrown the same twice land the same")


# ------------------------------------------------------------------ meeting


static func _xf(at: Vector3, turn: float, size: float) -> Transform3D:
	return Transform3D(
		Basis(Vector3.UP, turn).scaled(Vector3(size, size, size)), Vector3(at.x, at.z, at.y)
	)


## A big wreck piece lying asleep on the ground; a body dropped across it
## lies on it: no ball through it, the balls over it held up on its top.
func _doll_on_box(game: Game, rig: RagdollRig) -> void:
	var physics := WreckPhysics.new(game.world)
	var floor_z := _ground(game)
	var plank := _box(Vector3(at.x, at.y, floor_z + .1), Vector3(.8, .6, .1))
	plank.q = Quaternion.IDENTITY
	physics.bodies.append(plank)
	_settle(physics)
	var top := plank.p.z + .1
	var doll := Ragdoll.made(rig, _xf(Vector3(at.x, at.y, top + .15), .3, .5), rig.lying_points)
	Ragdoll.others = [doll]
	for _k in 900:
		if not doll.awake:
			break
		doll.step(game.world)
	var through := 0.0
	var held := 0
	for i in doll.pos.size():
		var out := plank.ball_out(doll.pos[i], doll.radius[i])
		through = maxf(through, out.length())
		if out == Vector3.ZERO and doll.pos[i].z - doll.radius[i] > top - .03:
			var l := Basis(plank.q).transposed() * (doll.pos[i] - plank.p)
			if absf(l.x) < plank.half.x and absf(l.y) < plank.half.y:
				held += 1
	_check(not doll.awake, "a body dropped on a wreck piece comes to rest")
	_check(through < .02, "it lies on the piece, not through it (%.3f in)" % through)
	_check(held >= 2, "balls over the piece rest on its top (%d)" % held)
	_ok("a body dropped on a wreck piece lies on it (%d balls on its top)" % held)
	Ragdoll.others = []


## A body lying still on the ground; a wreck piece dropped on its middle
## comes to rest on it, over the ground, not inside a ball.
func _box_on_doll(game: Game, rig: RagdollRig) -> void:
	var floor_z := _ground(game)
	var doll := Ragdoll.made(rig, _xf(Vector3(at.x, at.y, floor_z), 1.1, .5), rig.lying_points)
	doll.settle(game.world, 240, true)
	Ragdoll.others = [doll]
	var physics := WreckPhysics.new(game.world)
	var mid := doll.middle()
	# A long board dropped flat across the body's middle.
	var piece := _box(Vector3(mid.x, mid.y, mid.z + .4), Vector3(.5, .08, .03))
	var across := doll.pos[R.SH_L] - doll.pos[R.HIP_L]
	piece.q = Quaternion(Vector3(0.0, 0.0, 1.0), atan2(across.y, across.x) + PI * .5)
	physics.bodies.append(piece)
	_settle(physics)
	var low := piece.p.z - .03
	var into := 0.0
	for i in doll.pos.size():
		into = maxf(into, piece.ball_out(doll.pos[i], doll.radius[i]).length())
	_check(not piece.awake, "a wreck piece dropped on a body comes to rest")
	_check(
		low > floor_z + .04 and into < .03,
		(
			"it lies across the body, its middle over the ground (%.2f up, %.3f in)"
			% [low - floor_z, into]
		)
	)
	_ok("a board dropped across a body lies on it, %.2f over the ground" % (low - floor_z))
	Ragdoll.others = []
