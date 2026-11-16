## The pieces of broken scenery as rigid boxes (features/wreckage.gd keeps
## them), on the shared physics core (phys_core.gd): each a PhysCore.Box with
## a middle, a turn, a slide and a spin, its weight and moments from its size.
## They fall, strike the level's floors (decks, stairs, ramps, furniture
## tops: Tumble.floor_at), its roofs and its walls and furniture sides, one
## another and the ragdolls lying about, by the core's fast sequential
## impulses with friction and bounce, a few small steps a tick with
## penetration pushed out after. A box's corners (and, along a long stick,
## points between) are what touch. Pieces of one break pass through one
## another for a moment as they fly apart. A piece that has been still a
## moment sleeps and costs nothing until something knocks it, or what held it
## up goes (what it lay on waking wakes it at once).
##
## Looks only: nothing here is play, nothing is carried or saved, and nothing
## blocks anyone. Map axes: x, y across, z up.
class_name WreckPhysics
extends RefCounted

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
## for ever down a pile lies down where it is).
const LONGEST := 4.0
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
## A floor more than this over a point is a step's side to it, not a floor.
const LEDGE := PhysCore.LEDGE
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
## TIP_EVERY seconds it still stands) for TIP_MOST at most.
## Only a thin piece (a stave, a board, a stick: its thinnest side under
## THIN of its longest) tips; a chunk of something bulky may stand.
const TALL := 1.8
const THIN := .5
const TIP_FROM := .5
const PROP_N := .7
const TIP_SLOW := .3
const TIP_EVERY := .4
const TIP_KICK := 1.35
const TIP_MOST := 2.5


## One piece: the core's box, and how it is settling.
class Body:
	extends PhysCore.Box
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

	func wake() -> void:
		if not awake:
			awake_for = 0.0
			tipping = 0.0
			kicked = -1.0
			floors.forget()
			seen = Vector3.INF
		awake = true
		still = 0.0


var world: LevelData
## The pieces (Body), and the clock (seconds stepped).
var bodies: Array = []
var clock := 0.0
## Hard knocks the last step: how many, where the hardest was, how hard.
var knocks := 0
var knock_at := Vector3.ZERO
var knock_hard := 0.0
var _pool := PhysCore.Pool.new()
var _grid := PhysCore.Grid.new()
var _space: PhysCore.Space
## The ragdolls near enough to touch this step: [doll, middle, reach].
var _dolls: Array = []


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


func _step(h: float) -> void:
	_pool.reset()
	for b: Body in bodies:
		b.turned()
		if b.awake and b.slept:
			# Woken since it last stepped: whatever lay on it wakes too.
			b.slept = false
			PhysCore.wake_resting_on(bodies, b)
	var live: Array = []
	for b: Body in bodies:
		if b.awake:
			b.v.z -= GRAVITY * h
			b.under = null
			live.append(b)
	_space.stirring = live.size()
	if live.is_empty():
		return
	_near_dolls()
	var contacts: Array = []
	for b: Body in live:
		b.grounded = false
		b.propped = false
		b.deepest = 0.0
		_world_contacts(b, h, contacts)
		if not _dolls.is_empty():
			_doll_contacts(b, contacts)
	_pairs(live, contacts)
	PhysCore.prepare_fast(contacts, h, BOUNCE_FROM)
	PhysCore.solve_fast(contacts, PASSES)
	for c: PhysCore.Contact in contacts:
		if c.jn * c.a.inv_m > 1.2:
			knocks += 1
			if c.jn * c.a.inv_m > knock_hard:
				knock_hard = c.jn * c.a.inv_m
				knock_at = c.a.p + c.ra
	for b: Body in live:
		PhysCore.integrate(b, h)
		if b.grounded:
			b.w *= exp(-GROUND_SPIN * h)
			b.v *= exp(-GROUND_SLIDE * h)
		else:
			b.w *= exp(-AIR_DAMP * h)
		# A stave or a board come down on its end or its edge with nothing
		# leaning it there tips over (it never sleeps standing).
		var tips := b.grounded and not b.propped and b.tipping < TIP_MOST and standing(b)
		if tips:
			_tip(b, h)
		# Gravity pulls every step: one this slow that long is held up by
		# something (the floor, a wall, another piece).
		var settled := b.deepest < SLEEP_DEEP and not tips
		var speed := b.v.length()
		if settled and speed < SLEEP_V and b.w.length() < SLEEP_W:
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
		if b.grounded and speed < CREEP_V and b.w.length() < CREEP_W:
			b.creeping += h
			if settled and b.creeping > CREEP_AFTER:
				_sleep(b)
		else:
			b.creeping = 0.0
		# However it sits, one awake this long and slow lies down where it is.
		b.awake_for += h
		if b.awake and b.awake_for > LONGEST and speed < 1.0 and not tips:
			_sleep(b)
	_push_out(contacts)


## Each awake piece against every other near it (two awake ones once): by
## the core's grid when there are many, every other when few.
func _pairs(live: Array, contacts: Array) -> void:
	var count := bodies.size()
	for i in count:
		var o: Body = bodies[i]
		o.order = i
	var gridded := count > GRID_FROM
	if gridded:
		_grid.clear(count)
		for i in count:
			var o: Body = bodies[i]
			_grid.add(i, o.p.x, o.p.y, o.reach)
	for a: Body in live:
		if gridded:
			var near := _grid.near(a.p.x, a.p.y, a.reach)
			near.sort()
			for i in near:
				var o: Body = bodies[i]
				_pair_up(a, o, contacts)
		else:
			for o: Body in bodies:
				_pair_up(a, o, contacts)


func _pair_up(a: Body, o: Body, contacts: Array) -> void:
	if o == a or (o.awake and o.order < a.order):
		return
	if a.group == o.group and (clock - a.born < APART or clock - o.born < APART):
		return
	var r := a.reach + o.reach
	if a.p.distance_squared_to(o.p) > r * r:
		return
	_pair(a, o, contacts)
	_pair(o, a, contacts)


## Whether a piece stands on an end or an edge: its axis nearest upright
## reaches more than TALL times the narrower of the other two (a stave on its
## end, a board on its edge), and it is within TIP_FROM of upright. A cube,
## a chunk or anything lying flat does not.
static func standing(b: Body) -> bool:
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


## Tip a standing piece over its narrow foot, the way it already leans (else
## by its place): once it has slowed, it is set turning about its foot's edge
## on that side (that edge still, so nothing drags it back) fast enough to
## carry its middle past the edge (TIP_KICK times what just does), every
## TIP_EVERY while it still stands.
func _tip(b: Body, h: float) -> void:
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
			if solid(c):
				var way := PhysCore.way_out(world, c)
				if way.length() > out.length():
					out = way
				continue
			var under := Tumble.floor_at(world, c.x, c.y, maxf(c.z, b.p.z) + .02)
			if under - c.z < LEDGE:
				lift = maxf(lift, under - c.z)
		b.p += out + Vector3(0.0, 0.0, lift)


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
	if not is_nan(open):
		for lp: Vector3 in b.points:
			var r := b.turn * lp
			var depth := open - (b.p.z + r.z)
			if depth > -margin:
				_add(b, r, Vector3(0.0, 0.0, 1.0), depth, E_FLOOR, out)
				b.grounded = b.grounded or depth > -.01
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
	for i in count:
		var r := b.turn * b.points[i]
		var at := b.p + r
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
			continue
		# The floor under it, looked for from the piece's middle (or the point,
		# when it is higher): a fast fall never passes through a deck. Kept
		# while the point stays put.
		var from := maxf(at.z, b.p.z) + .02
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
			under = plain if flat else Tumble.floor_at(world, at.x, at.y, from)
			fl.keep(i, at.x, at.y, from, under, flat)
		var depth := under - at.z
		if depth > -margin and depth < LEDGE:
			_add(b, r, Vector3(0.0, 0.0, 1.0), depth, E_FLOOR, out)
			b.grounded = b.grounded or depth > -.01
			continue
		if rising and r.z > 0.0:
			var roof := roofs[i] if kept else NAN
			if is_nan(roof):
				roof = world.roof_over(at.x, at.y, minf(at.z, b.p.z) - .02)
				fl.roof[i] = roof
			if roof > 0.0 and at.z > roof - margin:
				_add(b, r, Vector3(0.0, 0.0, -1.0), at.z - roof, E_WALL, out)
		# A step's side, or (where walls are near) furniture or a slab.
		var into := depth >= LEDGE
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
	c.mu = MU if n.z > .5 else MU_WALL
	out.append(c)
	# Against a wall's side, or held up over its middle (its top end on a
	# ledge): it leans there.
	if (n.z < PROP_N or r.z > 0.0) and depth > -.01:
		b.propped = true
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
	var least := _least(a, o)
	if least == Vector3.ZERO:
		return
	var found := _pair_points(a, o, least, a.points, out)
	# Lying face to face (one on the other): by its edges' middles too.
	if found == 0 and absf(least.z) > PROP_N * least.length():
		_pair_points(a, o, least, a.edges, out)


func _pair_points(a: Body, o: Body, least: Vector3, points: PackedVector3Array, out: Array) -> int:
	var n := least.normalized()
	# How far o reaches along n from its middle.
	var top := o.extent(n)
	var inverse := o.turn.transposed()
	var found := 0
	for lp: Vector3 in points:
		var r := a.turn * lp
		var at := a.p + r
		var l := inverse * (at - o.p)
		var gap := o.half - l.abs()
		if gap.x <= 0.0 or gap.y <= 0.0 or gap.z <= 0.0:
			continue
		var deep := minf(o.p.dot(n) + top - at.dot(n), least.length())
		if deep <= 0.0:
			continue
		if not a.awake or not o.awake:
			# A sleeping piece wakes when it is struck hard, not when one comes
			# to lie on it.
			var closing := (a.velocity_at(r) - o.velocity_at(at - o.p)).dot(n)
			if closing < -.5:
				a.wake()
				o.wake()
		var c := _pool.take()
		c.a = a
		c.b = o
		c.ra = r
		c.rb = at - o.p
		c.n = n
		c.depth = deep
		c.e = E_BODY
		c.mu = MU_BODY
		out.append(c)
		# Lying on another piece holds it up as the floor does (it may sleep,
		# and wakes when that one does); against one's side, it leans on it.
		if n.z > .5:
			a.grounded = true
			a.under = o
		elif n.z < -.5:
			o.grounded = true
			o.under = a
		if absf(n.z) < PROP_N or (n.z > .5 and r.z > 0.0):
			a.propped = true
			o.propped = true
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
	# Pieces out of one another first, then out of the level, so the floor
	# and the walls have the last word (a pile never squeezes one into them).
	for world_pass in 2:
		for c: PhysCore.Contact in contacts:
			if (c.b == null) != (world_pass == 1):
				continue
			var d := c.depth - SLOP
			if d <= 0.0:
				continue
			var a: Body = c.a
			var ia := a.mass_inv()
			var ib := 0.0 if c.b == null else c.b.mass_inv()
			if ia + ib <= 0.0:
				continue
			if c.b == null:
				# Out of the level by the deepest of its contacts each way (the
				# level's are along the axes), not their sum.
				var want := c.n * d * PUSH
				a.out_up = a.out_up.max(want)
				a.out_down = a.out_down.min(want)
				continue
			var o: Body = c.b
			var move := c.n * d * PUSH / (ia + ib)
			a.p += move * ia / maxi(1, a.touching)
			o.p -= move * ib / maxi(1, o.touching)
		if world_pass == 1:
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
		if under - c.z < LEDGE:
			worst = maxf(worst, under - c.z)
		if solid(c):
			var way := PhysCore.way_out(world, c)
			worst = maxf(worst, way.length() if way != Vector3.ZERO else PhysCore.WALL_REACH)
	return worst
