## The pieces of broken scenery as rigid bodies (features/wreckage.gd keeps
## them), on the shared physics core (phys_core.gd): each a PhysCore.Box with
## a middle, a turn, a slide and a spin, its weight and moments from its size,
## what it is made of (`stuff`) and its shape (`form`): data/tuning/wreck.cfg
## gives each stuff its weight, bounce, grip, rolling resistance and sounds,
## each form its share of those. A box's corners (and, along a long stick,
## points between) are what touch; a round piece (a disc, a ring, a can)
## touches by the lowest points of its rims, worked out each step, so it rolls
## on its edge and wobbles down like a coin. They fall, strike the level's
## floors (decks, stairs, ramps, furniture tops: Tumble.floor_at), its roofs
## and its walls and furniture sides, one another and the ragdolls lying
## about, by the core's fast sequential impulses with friction and bounce, a
## few small steps a tick with penetration pushed out after. Pieces of one
## break pass through one another for a moment as they fly apart. A piece
## that has been still a moment sleeps and costs nothing until something
## knocks it, or what held it up goes (what it lay on waking wakes it at
## once). A stave or a board left standing on its end with nothing but other
## standing pieces against it is tipped over.
##
## How pieces are moved: add() puts one in (with its stuff and form);
## impact() knocks pieces from a point (a shot, a break, a blast, a boot, a
## vehicle: each piece pushed at its own point nearest the hit, by how far it
## is, so an off-centre hit spins it); burst() parts a break's pieces from
## its middle. After each step `knocks`, `knock_at`, `knock_hard`, each
## body's `hit` (its hardest knock) and `cracked` (pieces knocked harder than
## their stuff's `crack`) say what struck what.
##
## Looks only: nothing here is play, nothing is carried or saved, and nothing
## blocks anyone. Map axes: x, y across, z up.
class_name WreckPhysics
extends RefCounted

const PATH := WreckStuff.PATH
const GRAVITY := 9.4
## Bounce off the floor, a wall, another piece; closing speeds below
## BOUNCE_FROM do not bounce (a resting contact stays resting).
const E_FLOOR := .3
const E_WALL := .3
const E_BODY := .15
const BOUNCE_FROM := .7
## Friction on the floor and walls, and piece on piece.
const MU := .55
const MU_BODY := .45
const MU_WALL := .15
## A piece deeper in something than this does not sleep (it is pushed out
## first).
const SLEEP_DEEP := .03
## A contact is made this close before touching (more for a fast piece), so
## a falling piece meets the floor rather than sinking in.
const MARGIN := .015
## Penetration left alone, and the share of the rest pushed out a step.
const SLOP := .003
const PUSH := .8
## Spin and slide lost each second: in the air, on the floor.
const AIR_DAMP := .2
const GROUND_SPIN := 3.0
const GROUND_SLIDE := 1.2
## Asleep: slower than these (cells a second, radians a second) this long.
const SLEEP_V := .1
const SLEEP_W := .5
const SLEEP_AFTER := .35
## Or one that has gone no further than these (cells, radians) this long.
const HELD_MOVE := .02
const HELD_TURN := .08
const HELD_AFTER := .6
## Seconds a piece stays awake at most once it is slow (a big board sliding
## for ever down a pile lies down where it is); a round one still turning
## (rolling, wobbling down) has longer.
const LONGEST := 4.0
const LONGEST_ROUND := 9.0
## One that has gone nowhere (HELD_*) this long sleeps even wedged a little
## way into something (jittering in a pile).
const WEDGED_AFTER := 2.5
## One on the floor creeping slower than these (cells, radians a second)
## this long lies down where it is (a board inching off a crate's edge).
const CREEP_V := .35
const CREEP_W := 1.0
const CREEP_AFTER := 1.2
## Every awake piece slower than these (cells, radians a second): a tick
## takes one step, not `steps` (settling needs no small steps).
const SLOW_V := 1.5
const SLOW_W := 6.0
const PASSES := 4
## Pieces of one break do not touch one another for this long.
const APART := .25
## A floor more than this over a point is a step's side to it, not a floor,
## unless the piece's middle is DEEP_FLOOR over that floor.
const LEDGE := PhysCore.LEDGE
const DEEP_FLOOR := .05
## A piece whose lowest point is this much over every floor under it (and no
## wall or roof near) is in the air: none of its points are asked about.
const AIR_GAP := .25
## More pieces than this find their neighbours by the core's grid.
const GRID_FROM := 12
## How far round a resting piece's corner a wall holds it up (unsupported()).
const LEAN_SIDES := [
	Vector3(.05, 0.0, 0.0), Vector3(-.05, 0.0, 0.0), Vector3(0.0, .05, 0.0), Vector3(0.0, -.05, 0.0)
]
## A piece on its floor standing on an end or an edge (its upright reach
## more than TALL times its narrow foot's, within TIP_FROM radians of
## upright) with nothing leaning it (a contact steeper than PROP_N) is
## tipped over its foot (_tip: once slower than TIP_SLOW, again every
## TIP_EVERY seconds it still stands, the other way each time after two)
## for TIP_MOST at most. A piece leaning on another piece that itself
## stands on its end is not held by it (a ring of staves left standing goes
## over). Only a thin piece (a stave, a board, a stick: its thinnest side
## under THIN of its longest) tips; a chunk of something bulky may stand.
const TALL := 1.8
const THIN := .5
const TIP_FROM := .5
const PROP_N := .7
const TIP_SLOW := .3
const TIP_EVERY := .4
const TIP_KICK := 1.35
const TIP_MOST := 6.0
## Leaning on a piece that stands slender (its height over this many times
## its foot) holds nothing up.
const SLENDER := 4.0
## A round piece rolling on its rim slower than ROLL_UP is leaned over by
## WOBBLE (radians a second) every TIP_EVERY until it lies flat.
const ROLL_UP := 1.3
const WOBBLE := .9
## The fastest a piece is left spinning (radians a second) and sliding.
const MOST_SPIN := 40.0
const MOST_SPEED := 16.0
## Turns (radians about upright) tried on a piece going to sleep with both
## ends in walls, until one fits.
const TURNS: Array[float] = [.3, -.3, .6, -.6, .9, -.9, 1.3, -1.3]
## A ring's hole, a share of its radius: nothing in it touches the ring.
const RING_HOLE := .8
## Forms that roll: round about their thinnest axis, or about their longest.
const DISCS := ["disc", "ring"]
const CANS := ["can"]


## One piece: the core's box, and how it is settling.
class Body:
	extends PhysCore.Box
	## What it is made of and its form (wreck.cfg); the numbers it moves by.
	var stuff := "wood"
	var form := ""
	var bounce := E_FLOOR
	var grip := MU
	var roll := GROUND_SPIN
	var slide := GROUND_SLIDE
	var drag := 0.0
	var crack := 0.0
	var burst := 1.0
	## Round: 0 a box, 1 a disc or a ring (round about `axis`, its thinnest),
	## 2 a can (round about `axis`, its longest); its rims' radius.
	var round := 0
	var axis := 2
	var radius := 0.0
	## Its hardest knock this step (the speed it changed by), and when it was
	## last heard (wreckage.gd).
	var hit := 0.0
	var heard := -9.0
	## A round one has begun to wobble down on its rim (once until it lies).
	var wobbling := false
	## Gone to sleep wedged in something it could not be turned out of.
	var stuck := false
	## Standing on an end or an edge (standing()) as of its last step, and
	## slender as it stands (a stave, a board on edge: SLENDER); what it leans
	## on this step, if another piece (held only if that one is not standing
	## slender too), and whether the level props it.
	var upright := false
	var slender := false
	var leans: Body = null
	var walled := false
	var still := 0.0
	## Its place in the list this step, and its contacts this step.
	var order := 0
	var touching := 0
	## How deep its deepest contact is this step, and how far out of the
	## level it is pushed each way.
	var deepest := 0.0
	var out_up := Vector3.ZERO
	var out_down := Vector3.ZERO
	## Where it was when it last went anywhere, and how long since.
	var anchor := Vector3.INF
	var anchor_q := Quaternion.IDENTITY
	var held := 0.0
	var awake_for := 0.0
	## Leaning on something this step (a wall, another piece's side), and how
	## long it has been tipped over off an end or an edge.
	var propped := false
	var tipping := 0.0
	var kicked := -1.0
	## How long it has crept on the floor (CREEP_V).
	var creeping := 0.0
	## The break it came from, and when (pieces of one break pass through each
	## other for a moment).
	var group := 0
	var born := 0.0
	## Asleep last step (woken since: what lies on it wakes too).
	var slept := false
	## Each point's floor, kept while the point stays put.
	var floors := PhysCore.Floors.new()
	## What the level is round it as a whole, asked where it was (`seen`),
	## kept while it stays within REASK: the plain ground under all of it
	## (NAN none), whether a wall is near, the highest floor under any of it,
	## and whether no roof is near over it.
	var seen := Vector3.INF
	var open := NAN
	var walls := true
	var wide := NAN
	var clear := false
	## How far it reaches along each of its own axes (extent(turn[k])) and
	## the step they were worked out on (own_extents).
	var ex0 := 0.0
	var ex1 := 0.0
	var ex2 := 0.0
	var ex_step := -1
	var rp := PackedVector3Array()
	var rp_step := -1

	## ex0..ex2 for step `stamp` (its turn is fixed through a step): the same
	## sums extent() makes, once a step instead of once a pair.
	func own_extents(stamp: int) -> void:
		if ex_step == stamp:
			return
		ex_step = stamp
		var tx := turn.x
		var ty := turn.y
		var tz := turn.z
		ex0 = half.x * absf(tx.dot(tx)) + half.y * absf(ty.dot(tx)) + half.z * absf(tz.dot(tx))
		ex1 = half.x * absf(tx.dot(ty)) + half.y * absf(ty.dot(ty)) + half.z * absf(tz.dot(ty))
		ex2 = half.x * absf(tx.dot(tz)) + half.y * absf(ty.dot(tz)) + half.z * absf(tz.dot(tz))

	## Its points turned by its turn this step (turn * points[i]), once a
	## step: the level's contacts and the pairs' each turned them again.
	func rotated(stamp: int) -> PackedVector3Array:
		if rp_step != stamp or rp.size() != points.size():
			rp_step = stamp
			rp.resize(points.size())
			for i in points.size():
				rp[i] = turn * points[i]
		return rp

	func wake() -> void:
		if not awake:
			awake_for = 0.0
			tipping = 0.0
			kicked = -1.0
			floors.forget()
			seen = Vector3.INF
		awake = true
		still = 0.0

	## Its size (half each way), stuff and form: its weight, its moments (a
	## round one's as a disc's, a ring's or a can's) and the numbers it
	## moves by.
	func made_of(size: Vector3, made: WreckStuff, p_form: String) -> void:
		stuff = made.name
		form = p_form
		bounce = made.bounce
		grip = made.grip
		roll = made.roll
		slide = made.slide
		drag = made.drag
		crack = made.crack
		burst = made.burst
		round = 1 if DISCS.has(p_form) else 2 if CANS.has(p_form) else 0
		if round == 0:
			shape(size, made.dense)
			return
		var thin := 0
		var long := 0
		for a in 3:
			thin = a if size[a] < size[thin] else thin
			long = a if size[a] > size[long] else long
		axis = thin if round == 1 else long
		var a1 := (axis + 1) % 3
		var a2 := (axis + 2) % 3
		radius = maxf(size[a1], size[a2])
		var even := size
		even[a1] = radius
		even[a2] = radius
		# A cylinder fills pi/4 of its box; a ring's band a quarter of its disc.
		shape(even, made.dense * (.25 if p_form == "ring" else PI * .25))
		var mass := 1.0 / inv_m
		var r2 := radius * radius
		var h2 := even[axis] * even[axis] * 4.0
		var spin := mass * r2 * (1.0 if p_form == "ring" else .5)
		var across := mass * (r2 * (.5 if p_form == "ring" else .25) + h2 / 12.0)
		var moments := Vector3(across, across, across)
		moments[axis] = spin
		inv_i = Vector3(1.0 / moments.x, 1.0 / moments.y, 1.0 / moments.z)
		points.resize(8)
		rims()

	## A round piece's touching points: on each rim the lowest point, the
	## highest and the two between (a square turned so one corner is always
	## the bottom), from its turn this step.
	func rims() -> void:
		var down := turn.transposed() * Vector3(0.0, 0.0, -1.0)
		down[axis] = 0.0
		if down.length_squared() < 1e-6:
			down = Vector3.ZERO
			down[(axis + 1) % 3] = 1.0
		var d := down.normalized() * radius
		var along := Vector3.ZERO
		along[axis] = 1.0
		var s := along.cross(d)
		along *= half[axis]
		points[0] = -along + d
		points[1] = -along - d
		points[2] = -along + s
		points[3] = -along - s
		points[4] = along + d
		points[5] = along - d
		points[6] = along + s
		points[7] = along - s


var world: LevelData
## The pieces (Body), and the clock (seconds stepped).
var bodies: Array = []
var clock := 0.0
## Hard knocks the last step: how many, where the hardest was, how hard.
var knocks := 0
var knock_at := Vector3.ZERO
var knock_hard := 0.0
## Pieces knocked harder than their stuff's `crack` since the last step()
## (the breaks may split them).
var cracked: Array = []
var _pool := PhysCore.Pool.new()
var grid := PhysCore.Grid.new()
var _space: PhysCore.Space
## The ragdolls near enough to touch this step: [doll, middle, reach].
var _dolls: Array = []
## Counts the steps (Body.own_extents and Body.rotated keep theirs for one).
var stamp := 0
## WreckPairs.leasts' answer, kept for each pair (no array made a pair).
var leasts_out: Array = [Vector3.ZERO, Vector3.ZERO]


## The stuff `name` with the form `form`'s shares (WreckStuff.of).
static func stuff_of(name: String, form := "") -> WreckStuff:
	return WreckStuff.of(name, form)


## One of wreck.cfg's [impact.<kind>] or [knock] numbers (WreckStuff.tuned).
static func tuned(section: String, key: String, fallback: float) -> float:
	return WreckStuff.tuned(section, key, fallback)


## A knock's push on a point (WreckStuff.push_for: a piece's or a ragdoll's).
static func push_for(
	kind: String,
	at: Vector3,
	way: Vector3,
	strength: float,
	point: Vector3,
	middle: Vector3,
	seen := true,
	dice: RandomNumberGenerator = null
) -> Vector3:
	return WreckStuff.push_for(kind, at, way, strength, point, middle, seen, dice)


## A new piece at `at`, turned `q`, `size` half its size each way, made of
## `stuff` (wreck.cfg; breakables.cfg's `stuff` names) in the form `form`
## ("board", "stave", "ring", "disc", "can", "shard", "chunk", "sheet",
## "clump"; "" a plain box), from break `group` (its pieces pass through one
## another a moment as they part). Still until knocked (impact(), burst(),
## knock()). The breaks call this for every piece they throw.
func add(
	at: Vector3, q: Quaternion, size: Vector3, stuff := "wood", form := "", group := 0
) -> Body:
	var b := Body.new()
	b.p = at
	b.q = q
	b.turn = Basis(q)
	b.made_of(size, stuff_of(stuff, form), form)
	b.turned()
	b.group = group
	b.born = clock
	bodies.append(b)
	return b


func _init(p_world: LevelData) -> void:
	world = p_world
	# The level's space holds the pieces, so a ragdoll lies on them.
	_space = PhysCore.space(world)
	_space.boxes = bodies


## Whether any piece is awake (none: step() costs nothing).
func moving() -> bool:
	for b: Body in bodies:
		if b.awake:
			return true
	return false


## Step every piece `dt` seconds in `steps` small steps.
func step(dt: float, steps := 2) -> void:
	knocks = 0
	knock_hard = 0.0
	cracked.clear()
	if not moving():
		_space.stirring = 0
		clock += dt
		return
	var n := maxi(1, steps)
	if n > 1 and _slow():
		n = 1
	var h := dt / n
	for _s in n:
		_step(h)
		clock += h


## Whether every awake piece is slow (SLOW_V, SLOW_W).
func _slow() -> bool:
	for b: Body in bodies:
		if (
			b.awake
			and (b.v.length_squared() > SLOW_V * SLOW_V or b.w.length_squared() > SLOW_W * SLOW_W)
		):
			return false
	return true


## Take a piece away (shrunk away, dropped): what lay on it wakes.
func remove(b: Body) -> void:
	bodies.erase(b)
	PhysCore.wake_resting_on(bodies, b)
	_wake_leaning_on(b)


## Wake every piece asleep leaning on `b` (it may go over now).
func _wake_leaning_on(b: Body) -> void:
	for item: Variant in bodies:
		var o: Body = item
		if o.leans == b and not o.awake:
			o.leans = null
			o.wake()


func _step(h: float) -> void:
	stamp += 1
	_pool.reset()
	for b: Body in bodies:
		b.turned()
		if b.awake and b.slept:
			# Woken since it last stepped: whatever lay on it wakes too, and
			# whatever leaned on it.
			b.slept = false
			PhysCore.wake_resting_on(bodies, b)
			_wake_leaning_on(b)
	var live: Array = []
	for b: Body in bodies:
		if b.awake:
			b.v.z -= GRAVITY * h
			b.under = null
			if b.round != 0:
				b.rims()
			b.upright = standing(b)
			b.slender = b.upright and _slender(b)
			live.append(b)
	_space.stirring = live.size()
	if live.is_empty():
		return
	_near_dolls()
	var contacts: Array = []
	for b: Body in live:
		b.grounded = false
		b.propped = false
		b.walled = false
		b.leans = null
		b.deepest = 0.0
		b.hit = 0.0
		_world_contacts(b, h, contacts)
		if not _dolls.is_empty():
			_doll_contacts(b, contacts)
	WreckPairs.pairs(self, live, contacts)
	PhysCore.prepare_fast(contacts, h, BOUNCE_FROM)
	PhysCore.solve_fast(contacts, PASSES)
	for c: PhysCore.Contact in contacts:
		var dv := c.jn * c.ima
		if dv > 1.2:
			knocks += 1
			if dv > knock_hard:
				knock_hard = dv
				knock_at = c.a.p + c.ra
		var a: Body = c.a
		a.hit += dv
		if c.b != null:
			var o: Body = c.b
			o.hit += c.jn * c.imb
	for b: Body in live:
		if b.crack > 0.0 and b.hit > b.crack and not cracked.has(b):
			cracked.append(b)
	for b: Body in live:
		if b.round != 0:
			_turn_round(b, h)
		else:
			PhysCore.integrate(b, h)
		if b.grounded:
			b.w *= exp(-b.roll * h)
			b.v *= exp(-b.slide * h)
		else:
			b.w *= exp(-AIR_DAMP * h)
			if b.drag > 0.0:
				_flutter(b, h)
		if b.w.length_squared() > MOST_SPIN * MOST_SPIN:
			b.w = b.w.normalized() * MOST_SPIN
		# A stave or a board come down on its end or its edge with nothing
		# leaning it there tips over (it never sleeps standing). Another piece
		# standing on its own end holds nothing up.
		if b.leans != null and not b.leans.slender:
			b.propped = true
		var tips := b.grounded and not b.propped and b.tipping < TIP_MOST and b.upright
		if tips:
			_tip(b, h)
		# Gravity pulls every step: one this slow that long is held up by
		# something (the floor, a wall, another piece).
		var settled := b.deepest < SLEEP_DEEP and not tips
		var speed := b.v.length()
		var spin := b.w.length()
		if settled and speed < SLEEP_V and spin < SLEEP_W:
			b.still += h
			if b.still > SLEEP_AFTER:
				_sleep(b)
		else:
			b.still = 0.0
		# One that shivers in a pile without going anywhere sleeps too.
		if b.p.distance_to(b.anchor) > HELD_MOVE or b.q.angle_to(b.anchor_q) > HELD_TURN:
			b.anchor = b.p
			b.anchor_q = b.q
			b.held = 0.0
		else:
			b.held += h
			if (
				(settled or (b.awake_for > WEDGED_AFTER and not tips))
				and b.held > HELD_AFTER
				and speed < 1.0
			):
				_sleep(b)
		# One creeping along the floor a while lies down where it is.
		if b.grounded and speed < CREEP_V and spin < CREEP_W:
			b.creeping += h
			if settled and b.creeping > CREEP_AFTER:
				_sleep(b)
		else:
			b.creeping = 0.0
		# However it sits, one awake this long and slow lies down where it is
		# (a round one still turning has longer: a hoop rolling away).
		b.awake_for += h
		var longest := LONGEST_ROUND if b.round != 0 and spin > CREEP_W else LONGEST
		if b.awake and b.awake_for > longest and speed < 1.0 and not tips:
			_sleep(b)
	_push_out(contacts)


## A round piece moved on h seconds keeping its spin's momentum (not its
## spin): a coin on its edge leaning over turns as it rolls and wobbles down,
## its spin about its axis carried round as its axis tips.
func _turn_round(b: Body, h: float) -> void:
	var was := b.turn
	var held := was * ((was.transposed() * b.w) / b.inv_i)
	PhysCore.integrate(b, h)
	var now := Basis(b.q)
	b.w = now * ((now.transposed() * held) * b.inv_i)


## A flat piece in the air (a tin sheet) is held back across its face: it
## flutters down and sails sideways, its leading edge lifted.
func _flutter(b: Body, h: float) -> void:
	var thin := 0
	for a in 3:
		thin = a if b.half[a] < b.half[thin] else thin
	var n: Vector3 = b.turn[thin]
	var across := b.v.dot(n)
	if absf(across) < .05:
		return
	var loss := clampf(b.drag * absf(across) * h, 0.0, .9)
	b.v -= n * across * loss
	# The push is ahead of the middle along the way it slides: it turns the
	# face into the way it goes (and back), so it rocks as it falls.
	var slide_way := b.v - n * b.v.dot(n)
	if slide_way.length_squared() > 1e-4:
		var lead := (
			slide_way.normalized() * minf(b.half[(thin + 1) % 3], b.half[(thin + 2) % 3]) * .3
		)
		b.w += b.iw * lead.cross(n * across * loss / b.inv_m) * .5


## Whether a piece stands on an end or an edge: its axis nearest upright
## reaches more than TALL times the narrower of the other two (a stave on its
## end, a board on its edge), and it is within TIP_FROM of upright. A cube,
## a chunk or anything lying flat does not.
static func standing(b: Body) -> bool:
	if b.round == 1:
		# A hoop or a lid on its rim, whichever way it has rolled round.
		return absf(b.turn[b.axis].z) < sin(TIP_FROM) and b.radius > b.half[b.axis] * TALL
	var up := 0
	var most := -1.0
	for a in 3:
		var along := absf(b.turn[a].z)
		if along > most:
			most = along
			up = a
	if most < cos(TIP_FROM):
		return false
	var thin := minf(b.half.x, minf(b.half.y, b.half.z))
	var big := maxf(b.half.x, maxf(b.half.y, b.half.z))
	if thin > big * THIN:
		return false
	var foot := minf(b.half[(up + 1) % 3], b.half[(up + 2) % 3])
	return b.half[up] > foot * TALL


## Whether a standing piece is slender as it stands (its upright reach more
## than SLENDER times its narrow foot): a stave on its end, a board on its
## edge; not a chunk of a hay bale.
static func _slender(b: Body) -> bool:
	if b.round == 1:
		return true
	var up := 0
	for a in 3:
		up = a if absf(b.turn[a].z) > absf(b.turn[up].z) else up
	var foot := minf(b.half[(up + 1) % 3], b.half[(up + 2) % 3])
	return b.half[up] > foot * SLENDER


## Tip a standing piece over its narrow foot, the way it already leans (else
## by its place): once it has slowed, it is set turning about its foot's edge
## on that side (that edge still, so nothing drags it back) fast enough to
## carry its middle past the edge (TIP_KICK times what just does), every
## TIP_EVERY while it still stands.
func _tip(b: Body, h: float) -> void:
	if b.round == 1:
		_wobble(b, h)
		return
	b.tipping += h
	if b.v.length() > TIP_SLOW or b.w.length() > TIP_SLOW * 4.0:
		return
	if b.kicked >= 0.0 and b.tipping - b.kicked < TIP_EVERY:
		return
	b.kicked = b.tipping
	var up := 0
	var most := -1.0
	for a in 3:
		if absf(b.turn[a].z) > most:
			most = absf(b.turn[a].z)
			up = a
	var a1 := (up + 1) % 3
	var a2 := (up + 2) % 3
	var narrow := a1 if b.half[a1] < b.half[a2] else a2
	var u: Vector3 = b.turn[up] * signf(b.turn[up].z)
	var side: Vector3 = b.turn[narrow]
	var lean := Vector3(u.x, u.y, 0.0)
	var sense := signf(side.dot(lean))
	if lean.length() < .02 or sense == 0.0:
		sense = 1.0 if fposmod(b.p.x * 7.3 + b.p.y * 3.1, 2.0) < 1.0 else -1.0
	# Kicked back up twice (something in the way that side): the other way.
	if int(b.tipping / TIP_EVERY) % 4 >= 2:
		sense = -sense
	side *= sense
	var tall: float = b.half[up]
	var foot: float = b.half[narrow]
	var edge := b.p - u * tall + side * foot
	var about := u.cross(side).normalized()
	var reach := sqrt(tall * tall + foot * foot)
	var rise := reach - tall
	# (Harder each time it comes back up: the floor's grip takes some.)
	var kick := TIP_KICK * (1.0 + b.tipping / TIP_EVERY * .35)
	var spin := sqrt(2.0 * GRAVITY * rise / (4.0 / 3.0 * reach * reach)) * kick
	b.w = about * spin
	b.v = b.w.cross(b.p - edge)


## A hoop or a lid rolling on its rim: once it slows under ROLL_UP it is
## leaned a little (WOBBLE, every TIP_EVERY, the way it leans already) and
## its own spin carries it round in a curve as it goes over, wobbling down
## like a coin.
func _wobble(b: Body, h: float) -> void:
	if b.v.length() > ROLL_UP:
		return
	b.tipping += h
	if b.kicked >= 0.0 and b.tipping - b.kicked < TIP_EVERY:
		return
	if b.kicked < 0.0:
		b.wobbling = true
	b.kicked = b.tipping
	var axis: Vector3 = b.turn[b.axis]
	var ahead := axis.cross(Vector3(0.0, 0.0, 1.0))
	if ahead.length_squared() < 1e-4:
		return
	var sense := signf(axis.z)
	if sense == 0.0:
		sense = 1.0 if fposmod(b.p.x * 7.3 + b.p.y * 3.1, 2.0) < 1.0 else -1.0
	b.w += ahead.normalized() * WOBBLE * sense


## Put a piece to sleep where it lies, lifted out of any floor and moved out
## of any wall it is still a little way into (it lies on them, not in them).
func _sleep(b: Body) -> void:
	b.awake = false
	b.slept = true
	b.v = Vector3.ZERO
	b.w = Vector3.ZERO
	b.still = 0.0
	b.held = 0.0
	b.creeping = 0.0
	var turn := Basis(b.q)
	for k in 2:
		var lift := 0.0
		var out := Vector3.ZERO
		for i in 8:
			var c := b.p + turn * b.points[i]
			var under := Tumble.floor_at(world, c.x, c.y, maxf(c.z, b.p.z) + .02)
			if under > c.z and b.p.z - under > DEEP_FLOOR and not PhysCore.in_wall(world, c):
				lift = maxf(lift, under - c.z)
				continue
			if solid(c):
				var way := PhysCore.way_out(world, c)
				if way.length() > out.length():
					out = way
				continue
			if under - c.z < LEDGE:
				lift = maxf(lift, under - c.z)
		b.p += out + Vector3(0.0, 0.0, lift)
	# Still in something at both ends (a long board across a gap narrower
	# than it): turned about upright until it fits.
	if _walled_in(b, turn):
		for k in TURNS.size():
			var q := (Quaternion(Vector3(0.0, 0.0, 1.0), TURNS[k]) * b.q).normalized()
			if not _walled_in(b, Basis(q)):
				b.q = q
				return
		# Or laid flat, about its longest way (a plank on its edge wedged under
		# a ledge lies down where it is).
		var long := 0
		for a in 3:
			long = a if b.half[a] > b.half[long] else long
		var was_p := b.p
		b.turn = turn
		for sense: float in [1.0, -1.0] if standing(b) else []:
			var q := (Quaternion(turn[long].normalized(), PI * .5 * sense) * b.q).normalized()
			var laid := Basis(q)
			var low := INF
			for i in 8:
				low = minf(low, (b.p + laid * b.points[i]).z)
			b.p.z += Tumble.floor_at(world, b.p.x, b.p.y, b.p.z + .02) - low
			b.turn = laid
			if not _walled_in(b, laid) and not standing(b):
				b.q = q
				return
			b.p = was_p
			b.turn = turn
		# Wedged where nothing fits (a crack between a wall and a bench): it
		# goes (wreckage.gd shrinks it away).
		b.stuck = true


## Whether any corner of the piece turned `turn` is in a wall, furniture or
## a step's side.
func _walled_in(b: Body, turn: Basis) -> bool:
	for i in 8:
		if solid(b.p + turn * b.points[i]):
			return true
	return false


## The floor, the roof and the walls against each of the piece's points. A
## piece over plain ground every way it reaches asks only that ground; one
## high in the air over everything under it asks nothing more; else each
## point asks, its floor kept while it stays put (PhysCore.Floors).
func _world_contacts(b: Body, h: float, out: Array) -> void:
	var margin := MARGIN + b.v.length() * h
	if b.seen.distance_squared_to(b.p) > PhysCore.REASK * PhysCore.REASK:
		_look_round(b)
	var open := b.open
	var walls := b.walls
	if (
		is_nan(open)
		and b.clear
		and b.p.z - b.extent(Vector3(0.0, 0.0, 1.0)) > b.wide + margin + AIR_GAP
	):
		# In the air over everything under it: nothing to touch.
		return
	# (Its place, bounce and grounding read once: pass 13.)
	var bp := b.p
	var bounce := b.bounce
	var grounded := b.grounded
	if not is_nan(open):
		for r: Vector3 in b.rotated(stamp):
			var depth := open - (bp.z + r.z)
			if depth > -margin:
				_add(b, r, Vector3(0.0, 0.0, 1.0), depth, bounce, out)
				grounded = grounded or depth > -.01
		b.grounded = grounded
		return
	var count := b.points.size()
	var fl := b.floors
	fl.size_to(count)
	# No wall and no roof near: a point higher than every floor under it
	# touches nothing.
	var above := b.wide + margin + .02 if not walls and b.clear else INF
	# (No wall at its reach's corners, and it reaches less than half a cell:
	# no point of it is in a wall cell.)
	var cells := walls or b.reach >= .5
	var wide := world.width
	var high := world.height
	var solid_cells := world.solid
	# The kept floors read here (Floors.held written out: this runs for every
	# point of every awake piece every step).
	var asked := fl.at
	var floors := fl.floor
	var flats := fl.flat
	var roofs := fl.roof
	var insides := fl.inside
	var reask := PhysCore.REASK
	var rising := b.v.z > -.5
	var turned := b.rotated(stamp)
	for i in count:
		var r := turned[i]
		var at := bp + r
		if at.z > above:
			continue
		if (
			cells
			and (
				at.x < 0.0
				or at.y < 0.0
				or at.x >= wide
				or at.y >= high
				or solid_cells[int(at.y) * wide + int(at.x)] >= 0
			)
		):
			var out_of := PhysCore.way_out(world, at)
			if out_of != Vector3.ZERO:
				_add(b, r, out_of.normalized(), out_of.length(), E_WALL, out)
			# Never under the ground there either (a piece thrown into a fence's
			# cell is pushed out of it, not let fall through it meanwhile).
			if at.x >= 0.0 and at.y >= 0.0 and at.x < wide and at.y < high:
				var base := world.ground[int(at.y) * wide + int(at.x)]
				if base - at.z > -margin and base - at.z < LEDGE:
					_add(b, r, Vector3(0.0, 0.0, 1.0), base - at.z, bounce, out)
			continue
		# The floor under it, looked for from the piece's middle (or the point,
		# when it is higher): a fast fall never passes through a deck. Kept
		# while the point stays put.
		var from := maxf(at.z, bp.z) + .02
		var under: float
		var flat := false
		var was := asked[i]
		var kept := false
		if absf(at.x - was.x) < reask and absf(at.y - was.y) < reask and from <= was.z + .01:
			under = floors[i]
			kept = from >= under - .01
		if kept:
			flat = flats[i] == 1
		else:
			var plain := PhysCore.plain(world, at.x, at.y)
			flat = not is_nan(plain)
			under = plain if flat else PhysCore.floor_under(world, at.x, at.y, from)
			fl.keep(i, at.x, at.y, from, under, flat)
		var depth := under - at.z
		# Deeper than a step under a floor its middle is over (a fast corner
		# swept in): still that floor, not a step's side.
		if depth > -margin and (depth < LEDGE or bp.z - under > DEEP_FLOOR):
			_add(b, r, Vector3(0.0, 0.0, 1.0), depth, bounce, out)
			grounded = grounded or depth > -.01
			continue
		if rising and r.z > 0.0:
			var roof := roofs[i] if kept else NAN
			if is_nan(roof):
				roof = world.roof_over(at.x, at.y, minf(at.z, bp.z) - .02)
				fl.roof[i] = roof
			if roof > 0.0 and at.z > roof - margin:
				_add(b, r, Vector3(0.0, 0.0, -1.0), at.z - roof, E_WALL, out)
		# A step's side, or (where walls are near) furniture or a slab.
		var into := depth >= LEDGE and bp.z - under <= DEEP_FLOOR
		if not into and walls and not flat:
			var known := insides[i] if kept else 2
			if known == 2:
				known = 1 if solid(at) else 0
				fl.inside[i] = known
			into = known == 1
		if into:
			var way := PhysCore.way_out(world, at)
			if way != Vector3.ZERO:
				_add(b, r, way.normalized(), way.length(), E_WALL, out)
	b.grounded = grounded


## What the level is round a piece as a whole (Body.seen and on): plain
## ground every way it reaches (and no roof), else whether nothing is in the
## way anywhere it reaches, the highest floor under any of it and whether a
## roof is near over it; plain ground too when the ground is level under all
## of it and no slab or top stands there.
func _look_round(b: Body) -> void:
	b.seen = b.p
	b.open = PhysCore.plain_under(world, b.p, b.reach)
	b.walls = true
	b.clear = false
	if not is_nan(b.open) or world.blocked(b.p.x, b.p.y, b.reach, b.p.z):
		return
	b.walls = false
	b.wide = Tumble.floor_at(world, b.p.x, b.p.y, b.p.z, b.reach)
	var roof := world.roof_over(b.p.x, b.p.y, b.p.z)
	b.clear = roof <= 0.0 or roof > b.p.z + b.reach + .5
	if (
		b.clear
		and PhysCore.level_ground(world, b.p, b.reach)
		and b.wide == Tumble.floor_at(world, b.p.x, b.p.y, b.p.z)
	):
		b.open = b.wide


## Whether a point is in something: a wall, furniture, a deck's slab, or
## under ground or a top more than LEDGE over it (a step's side).
func solid(at: Vector3) -> bool:
	return PhysCore.solid(world, at)


func _add(b: Body, r: Vector3, n: Vector3, depth: float, e: float, out: Array) -> PhysCore.Contact:
	var c := _pool.take()
	c.a = b
	c.ra = r
	c.n = n
	c.depth = depth
	c.e = e
	# A wall is slippery: a piece against one slides down it to the floor.
	c.mu = b.grip if n.z > .5 else MU_WALL
	out.append(c)
	# Against a wall's side, or held up over its middle (its top end on a
	# ledge): it leans there.
	if (n.z < PROP_N or r.z > 0.0) and depth > -.01:
		b.propped = true
		b.walled = true
	b.deepest = maxf(b.deepest, depth)
	return c


# ------------------------------------------------------------------ ragdolls


## The ragdolls on this level near any awake piece (ActorLayer3D hands
## Ragdoll.others each frame: only where the 3D view shows bodies).
func _near_dolls() -> void:
	_dolls.clear()
	if Ragdoll.others.is_empty():
		return
	for item: Variant in Ragdoll.others:
		var doll: Ragdoll = item
		if doll.level != world or doll.pos.is_empty():
			continue
		var mid := doll.middle()
		_dolls.append([doll, mid, doll.extent])


## A piece against a ragdoll's balls (held still: the body lies, the piece
## comes to rest on it or glances off).
func _doll_contacts(b: Body, out: Array) -> void:
	for row: Array in _dolls:
		var mid: Vector3 = row[1]
		var reach: float = row[2] + b.reach
		if (
			absf(mid.x - b.p.x) > reach
			or absf(mid.y - b.p.y) > reach
			or absf(mid.z - b.p.z) > reach
		):
			continue
		var doll: Ragdoll = row[0]
		for i in doll.pos.size():
			var ball := doll.pos[i]
			var r := doll.radius[i]
			if ball.distance_squared_to(b.p) > (b.reach + r) * (b.reach + r):
				continue
			var push := b.ball_out(ball, r)
			var deep := push.length()
			if deep < 1e-5:
				continue
			# Pushing the piece away from the ball, at the piece's point in it.
			var n := -push / deep
			var at := ball + n * (r - deep)
			var c := _add(b, at - b.p, n, deep, E_BODY, out)
			c.mu = MU_BODY
			if n.z > .5:
				b.grounded = true


# ------------------------------------------------------------------ pieces


## a's points inside o's box (its corners, else the middles of its edges):
## each a contact pushing a out of o along the way the two overlap least (a
## plank on a plank is pushed up, not off its side).
func _pair(a: Body, o: Body, out: Array) -> void:
	pair_with(a, o, _least(a, o), out)


## _pair with a's way out of o (_least) worked out already (WreckPairs).
func pair_with(a: Body, o: Body, least: Vector3, out: Array) -> void:
	if least == Vector3.ZERO:
		return
	var found := _pair_points(a, o, least, a.rotated(stamp), out)
	# Lying face to face (one on the other): by its edges' middles too.
	if found == 0 and absf(least.z) > PROP_N * least.length():
		var edges := PackedVector3Array()
		edges.resize(a.edges.size())
		for i in a.edges.size():
			edges[i] = a.turn * a.edges[i]
		_pair_points(a, o, least, edges, out)


## (`turned`: the points already turned by a's turn, a.turn * point.)
func _pair_points(a: Body, o: Body, least: Vector3, turned: PackedVector3Array, out: Array) -> int:
	var n := least.normalized()
	# How far o reaches along n from its middle.
	var top := o.extent(n)
	var inverse := o.turn.transposed()
	var found := 0
	# (Both places and o's size read once: pass 13.)
	var ap := a.p
	var op := o.p
	var oh := o.half
	var disc := o.round == 1
	for r: Vector3 in turned:
		var at := ap + r
		var l := inverse * (at - op)
		var gap := oh - l.abs()
		if gap.x <= 0.0 or gap.y <= 0.0 or gap.z <= 0.0:
			continue
		if disc:
			# A disc is round, a ring hollow: a corner of its box past its rim, or
			# a point in a ring's hole, is not in it (a lid lies inside a hoop).
			var across := Vector2(l[(o.axis + 1) % 3], l[(o.axis + 2) % 3]).length()
			if across > o.radius or (o.form == "ring" and across < o.radius * RING_HOLE):
				continue
		var deep := minf(op.dot(n) + top - at.dot(n), least.length())
		if deep <= 0.0:
			continue
		if not a.awake or not o.awake:
			# A sleeping piece wakes when it is struck hard, not when one comes
			# to lie on it.
			var closing := (a.velocity_at(r) - o.velocity_at(at - op)).dot(n)
			if closing < -.5:
				a.wake()
				o.wake()
		var c := _pool.take()
		c.a = a
		c.b = o
		c.ra = r
		c.rb = at - op
		c.n = n
		c.depth = deep
		c.e = E_BODY
		c.mu = minf(a.grip, o.grip) * (MU_BODY / MU)
		out.append(c)
		# Lying on another piece holds it up as the floor does (it may sleep,
		# and wakes when that one does); against one's side, it leans on it.
		if n.z > .5:
			a.grounded = true
			a.under = o
		elif n.z < -.5:
			o.grounded = true
			o.under = a
		# Against one's side (or held up over its middle): it leans on it, held
		# there only while that one does not stand on its own end too.
		if absf(n.z) < PROP_N or (n.z > .5 and r.z > 0.0):
			if a.leans == null or a.leans.slender:
				a.leans = o
			if o.leans == null or o.leans.slender:
				o.leans = a
		found += 1
		if found >= 4:
			break
	return found


## The way two boxes overlap least, over each one's three face axes (pushing
## a away from o), and by how much; ZERO when they do not overlap.
static func _least(a: Body, o: Body) -> Vector3:
	var d := a.p - o.p
	var best := INF
	var way := Vector3.ZERO
	for k in 6:
		var axis: Vector3 = a.turn[k] if k < 3 else o.turn[k - 3]
		var along := d.dot(axis)
		var overlap := a.extent(axis) + o.extent(axis) - absf(along)
		if overlap <= 0.0:
			return Vector3.ZERO
		if overlap < best:
			best = overlap
			way = axis if along >= 0.0 else -axis
	return way * best


## Penetration left after the step pushed out (the pieces' places only), each
## contact's share split among a piece's contacts so four corners on the
## floor lift it once, not four times.
func _push_out(contacts: Array) -> void:
	# (Split once into the contacts with another piece and those with the
	# level, each in its own order: pass 13, the same sums as walking them all
	# on each pass.)
	var with_pieces: Array = []
	var with_level: Array = []
	for c: PhysCore.Contact in contacts:
		var a: Body = c.a
		a.touching = 0
		a.out_up = Vector3.ZERO
		a.out_down = Vector3.ZERO
		if c.b != null:
			var o: Body = c.b
			o.touching = 0
	for c: PhysCore.Contact in contacts:
		if c.depth > SLOP:
			var a: Body = c.a
			a.touching += 1
			if c.b != null:
				var o: Body = c.b
				o.touching += 1
				with_pieces.append(c)
			else:
				with_level.append(c)
	# Pieces out of one another first, then out of the level, so the floor
	# and the walls have the last word (a pile never squeezes one into them).
	for c: PhysCore.Contact in with_pieces:
		var d := c.depth - SLOP
		var a: Body = c.a
		var o: Body = c.b
		var ia := a.mass_inv()
		var ib := o.mass_inv()
		if ia + ib <= 0.0:
			continue
		var move := c.n * d * PUSH / (ia + ib)
		a.p += move * ia / maxi(1, a.touching)
		o.p -= move * ib / maxi(1, o.touching)
	for c: PhysCore.Contact in with_level:
		var a: Body = c.a
		if a.mass_inv() <= 0.0:
			continue
		# Out of the level by the deepest of its contacts each way (the
		# level's are along the axes), not their sum.
		var want := c.n * (c.depth - SLOP) * PUSH
		a.out_up = a.out_up.max(want)
		a.out_down = a.out_down.min(want)
	for c: PhysCore.Contact in contacts:
		var a: Body = c.a
		if c.b == null and a.awake:
			a.p += a.out_up + a.out_down
			a.out_up = Vector3.ZERO
			a.out_down = Vector3.ZERO


## A push at `at` (a blast's shove, a boot): wakes the piece.
static func knock(b: Body, dv: Vector3, spin: Vector3) -> void:
	b.wake()
	b.v += dv
	b.w += spin


## Knock pieces from a hit (push_for() says each one's push): each piece (of
## `group` only, when not -1; of `only`, when given; asleep ones too) is
## pushed at its own point nearest the hit, so a hit off its middle spins it,
## plus the kind's `spin` at random; a shot's impulse moves a light piece far
## and a heavy one a little, the other kinds' speed a heavy piece somewhat
## less; no piece faster than the kind's `most`. A blast's push on a piece it
## cannot see is cut to `hidden`. Returns how many pieces moved.
func impact(
	at: Vector3,
	way: Vector3,
	strength: float,
	kind := "shot",
	group := -1,
	dice: RandomNumberGenerator = null,
	only: Body = null
) -> int:
	var numbers := WreckStuff.kind_of(kind)
	var far := numbers[WreckStuff.REACH] * 6.0
	var spin := numbers[WreckStuff.SPIN]
	var most := numbers[WreckStuff.MOST]
	var looks := numbers[WreckStuff.HIDDEN] < 1.0
	var impulse := kind == "shot"
	var moved := 0
	# Newest first: a break's pieces are the last added (its group's end).
	for i in range(bodies.size() - 1, -1, -1):
		var b: Body = bodies[i]
		if group >= 0 and b.group < group:
			break
		if (group >= 0 and b.group != group) or (only != null and b != only):
			continue
		if absf(b.p.x - at.x) > far + b.reach or absf(b.p.y - at.y) > far + b.reach:
			continue
		# Its point nearest the hit.
		var turn := Basis(b.q)
		var r := turn * (turn.transposed() * (at - b.p)).clamp(-b.half, b.half)
		var seen := not looks or world.visible(at.x, at.y, b.p.x, b.p.y, at.z, b.p.z)
		var push := push_for(kind, at, way, strength, b.p + r, b.p, seen, dice)
		var speed := push.length()
		if speed < 1e-4:
			continue
		var dir := push / speed
		if impulse:
			speed *= b.inv_m
		else:
			# A heavy piece is moved less than a light one by the same knock.
			speed *= clampf(sqrt(2.5 * b.inv_m), .45, 1.5)
		speed = minf(speed, most)
		if speed < .05:
			continue
		b.wake()
		b.turned()
		b.v += dir * speed
		b.w += b.iw * r.cross(dir * (speed / b.inv_m))
		if dice != null:
			b.w += (
				Vector3(
					dice.randf_range(-1.0, 1.0),
					dice.randf_range(-1.0, 1.0),
					dice.randf_range(-1.0, 1.0)
				)
				* spin
				* minf(1.0, speed / maxf(most * .5, .1))
			)
		_cap_motion(b)
		moved += 1
	return moved


## Part a break's pieces (`group`) from its middle `mid` at about `speed`
## (the stuff's `burst` times it), each a little its own way and spin.
func burst(group: int, mid: Vector3, speed: float, dice: RandomNumberGenerator) -> void:
	for i in range(bodies.size() - 1, -1, -1):
		var b: Body = bodies[i]
		if b.group < group:
			break
		if b.group != group:
			continue
		var out := b.p - mid
		out.z *= .35
		if out.length() < .01:
			out = Vector3(dice.randf_range(-1.0, 1.0), dice.randf_range(-1.0, 1.0), .2)
		b.wake()
		b.v += out.normalized() * speed * b.burst * dice.randf_range(.4, 1.2)
		b.w += (
			Vector3(
				dice.randf_range(-1.0, 1.0),
				dice.randf_range(-1.0, 1.0),
				dice.randf_range(-1.0, 1.0)
			)
			* dice.randf_range(1.0, 4.0)
		)
		_cap_motion(b)


static func _cap_motion(b: Body) -> void:
	if b.v.length_squared() > MOST_SPEED * MOST_SPEED:
		b.v = b.v.normalized() * MOST_SPEED
	if b.w.length_squared() > MOST_SPIN * MOST_SPIN:
		b.w = b.w.normalized() * MOST_SPIN


## The first piece a ray from `from` to `to` passes into (a shot), and where
## it enters: [Body, Vector3], or [] when none.
func ray(from: Vector3, to: Vector3) -> Array:
	var way := to - from
	var length := way.length()
	if length < 1e-4:
		return []
	var lo := from.min(to)
	var hi := from.max(to)
	var best := INF
	var hit: Body = null
	for item: Variant in bodies:
		var b: Body = item
		var r := b.reach
		if (
			b.p.x < lo.x - r
			or b.p.x > hi.x + r
			or b.p.y < lo.y - r
			or b.p.y > hi.y + r
			or b.p.z < lo.z - r
			or b.p.z > hi.z + r
		):
			continue
		var inverse := Basis(b.q).transposed()
		var o := inverse * (from - b.p)
		var d := inverse * way
		var t0 := 0.0
		var t1 := 1.0
		var clear := false
		for k in 3:
			if absf(d[k]) < 1e-9:
				if absf(o[k]) > b.half[k]:
					clear = true
					break
				continue
			var ta := (-b.half[k] - o[k]) / d[k]
			var tb := (b.half[k] - o[k]) / d[k]
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
			if t0 > t1:
				clear = true
				break
		if not clear and t0 < best:
			best = t0
			hit = b
	if hit == null:
		return []
	return [hit, from + way * best]


## Whether a sleeping piece left standing on an end or an edge lost what
## held it there (the piece it leaned on woke, went or lies standing itself):
## then it should wake and go over.
func topples(b: Body) -> bool:
	if b.awake or b.walled or not b.upright or b.tipping >= TIP_MOST:
		return false
	b.turn = Basis(b.q)
	if not standing(b):
		return false
	var o := b.leans
	if o == null or o.awake or o.slender or not bodies.has(o):
		return true
	return o.p.distance_to(b.p) > o.reach + b.reach + .05


## Whether a piece at rest lost what held it up (the crate it lay on broke):
## its lowest corner is well over the floor under it.
func unsupported(b: Body) -> bool:
	var turn := Basis(b.q)
	# Balanced on its middle across an edge (a rail, a deck's lip): every
	# corner hangs out over air, yet the floor under its middle holds it.
	var lowest := INF
	for k in 8:
		lowest = minf(lowest, (b.p + turn * b.points[k]).z)
	if Tumble.floor_at(world, b.p.x, b.p.y, b.p.z + .02) >= lowest - .05:
		return false
	var near: Array = []
	for o: Body in bodies:
		if o != b and o.p.distance_to(b.p) < o.reach + b.reach + .1:
			near.append(o)
	_near_dolls()
	for k in 8:
		var c := b.p + turn * b.points[k]
		# A corner on a floor, a top or a wall's foot...
		if Tumble.floor_at(world, c.x, c.y, b.p.z + .02) >= c.z - .05:
			return false
		# ...leaning on a wall (a stave propped in a corner is held there)...
		for side: Vector3 in LEAN_SIDES:
			if solid(c + side):
				return false
		# ...or on another piece...
		var below := c - Vector3(0.0, 0.0, .04)
		for o: Body in near:
			var l := Basis(o.q).transposed() * (below - o.p)
			var room := o.half + Vector3(.02, .02, .02)
			if absf(l.x) < room.x and absf(l.y) < room.y and absf(l.z) < room.z:
				return false
		# ...or on a body lying there.
		for row: Array in _dolls:
			var doll: Ragdoll = row[0]
			for i in doll.pos.size():
				if doll.pos[i].distance_to(below) < doll.radius[i] + .03:
					return false
	# ...or leaning on another piece by a face or an edge anywhere on it (a big
	# tilted chunk propped on its neighbour partway up its side): the
	# midpoints between every two of its corners (its edges, faces and middle)
	# touching a piece near it.
	if near.is_empty():
		return true
	var all: Array = []
	for k in 8:
		all.append(b.p + turn * b.points[k])
	for i in all.size():
		for j in range(i + 1, all.size()):
			var a: Vector3 = all[i]
			var other: Vector3 = all[j]
			var mid := (a + other) * .5
			for o: Body in near:
				var l := Basis(o.q).transposed() * (mid - o.p)
				var room := o.half + Vector3(.04, .04, .04)
				if absf(l.x) < room.x and absf(l.y) < room.y and absf(l.z) < room.z:
					return false
	return true


## How far the piece is inside the level (0 when it is not): its corners
## under the floor under its middle, or in a wall. The check's measure.
func inside(b: Body) -> float:
	var worst := 0.0
	var turn := Basis(b.q)
	for k in 8:
		var c := b.p + turn * b.points[k]
		var under := Tumble.floor_at(world, c.x, c.y, maxf(c.z, b.p.z) + .02)
		if under - c.z < LEDGE or b.p.z - under > DEEP_FLOOR:
			worst = maxf(worst, under - c.z)
		if solid(c):
			var way := PhysCore.way_out(world, c)
			worst = maxf(worst, way.length() if way != Vector3.ZERO else PhysCore.WALL_REACH)
	return worst
