## The pieces of broken scenery as rigid boxes (features/wreckage.gd keeps
## them): each a box with a middle, a turn (a quaternion), a slide and a spin,
## its weight and moments from its size. They fall, strike the level's floors
## (decks, stairs, ramps, furniture tops: Tumble.floor_at), its roofs and its
## walls and furniture sides (LevelData.blocked), and one another, by
## sequential impulses with friction and bounce as the bowling pins are
## (range_pin_physics.gd), a few small steps a tick with penetration pushed
## out after. A box's corners (and, along a long stick, points between) are
## what touch. Pieces of one break pass through one another for a moment as
## they fly apart. A piece that has been still a moment sleeps and costs
## nothing until something knocks it, or what held it up goes.
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
const LONGEST := 6.0
const PASSES := 4
## Pieces of one break do not touch one another for this long.
const APART := .25
## How far in a wall a corner is looked out of, in steps of WALL_STEP.
const WALL_STEP := .03
const WALL_REACH := .6
## A floor more than this over a point is a step's side to it, not a floor.
const LEDGE := .2
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


## One piece.
class Body:
	var p := Vector3.ZERO
	var q := Quaternion.IDENTITY
	var v := Vector3.ZERO
	var w := Vector3.ZERO
	var half := Vector3(.05, .05, .05)
	var inv_m := 1.0
	## Its moments' inverse about its own axes.
	var inv_i := Vector3.ONE
	var awake := true
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
	var grounded := false
	## Leaning on something this step (a wall, another piece's side), and how
	## long it has been tipped over off an end or an edge.
	var propped := false
	var tipping := 0.0
	var kicked := -1.0
	## The break it came from, and when (pieces of one break pass through each
	## other for a moment).
	var group := 0
	var born := 0.0
	## The points of it that touch, in its own axes, and how far its farthest
	## reaches from its middle.
	var points := PackedVector3Array()
	var reach := .1
	## Its turn this step (Basis(q)), kept for the contacts.
	var turn := Basis.IDENTITY

	## A box `half` its size each way, of density `dense`.
	func shape(size: Vector3, dense: float) -> void:
		half = size
		var full := size * 2.0
		var mass := maxf(.02, full.x * full.y * full.z * dense)
		inv_m = 1.0 / mass
		var ix := mass / 12.0 * (full.y * full.y + full.z * full.z)
		var iy := mass / 12.0 * (full.x * full.x + full.z * full.z)
		var iz := mass / 12.0 * (full.x * full.x + full.y * full.y)
		inv_i = Vector3(1.0 / maxf(ix, 1e-6), 1.0 / maxf(iy, 1e-6), 1.0 / maxf(iz, 1e-6))
		reach = size.length()
		points = PackedVector3Array()
		for k in 8:
			points.append(
				Vector3(
					size.x if k & 1 else -size.x,
					size.y if k & 2 else -size.y,
					size.z if k & 4 else -size.z
				)
			)
		# A long stick touches along its length too, not only at its ends.
		var longest := 0
		for a in 3:
			if size[a] > size[longest]:
				longest = a
		var others := 0.0
		for a in 3:
			if a != longest:
				others = maxf(others, size[a])
		if size[longest] > others * 2.5:
			var a1 := (longest + 1) % 3
			var a2 := (longest + 2) % 3
			for k in 4:
				var c := Vector3.ZERO
				c[a1] = size[a1] if k & 1 else -size[a1]
				c[a2] = size[a2] if k & 2 else -size[a2]
				points.append(c)
		turn = Basis(q)

	func inv_inertia(t: Vector3) -> Vector3:
		if not awake:
			return Vector3.ZERO
		var local := turn.transposed() * t
		return turn * (local * inv_i)

	func mass_inv() -> float:
		return inv_m if awake else 0.0

	func velocity_at(r: Vector3) -> Vector3:
		return v + w.cross(r)

	func push(j: Vector3, r: Vector3) -> void:
		v += j * mass_inv()
		w += inv_inertia(r.cross(j))

	func wake() -> void:
		if not awake:
			awake_for = 0.0
			tipping = 0.0
			kicked = -1.0
		awake = true
		still = 0.0


class Contact:
	var a: Body
	var b: Body
	var ra := Vector3.ZERO
	var rb := Vector3.ZERO
	var n := Vector3(0.0, 0.0, 1.0)
	var depth := 0.0
	var bias := 0.0
	var mu := MU
	var e := E_FLOOR
	var jn := 0.0
	var jt := Vector3.ZERO
	var mass_n := 0.0

	## As one just made (contacts are kept and handed out again each step).
	func clear() -> void:
		a = null
		b = null
		ra = Vector3.ZERO
		rb = Vector3.ZERO
		n = Vector3(0.0, 0.0, 1.0)
		depth = 0.0
		bias = 0.0
		mu = MU
		e = E_FLOOR
		jn = 0.0
		jt = Vector3.ZERO
		mass_n = 0.0


var world: LevelData
## The pieces (Body), and the clock (seconds stepped).
var bodies: Array = []
var clock := 0.0
## Hard knocks the last step: how many, where the hardest was, how hard.
var knocks := 0
var knock_at := Vector3.ZERO
var knock_hard := 0.0
## The contacts made so far, handed out again each step (a step of 48 pieces
## in the air makes hundreds; making them anew was a good share of its cost).
var _contacts: Array[Contact] = []
var _contacts_used := 0


func _init(p_world: LevelData) -> void:
	world = p_world


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
		clock += dt
		return
	var h := dt / maxi(1, steps)
	for _s in maxi(1, steps):
		_step(h)
		clock += h


## A contact as new, from the kept ones.
func _contact() -> Contact:
	var c: Contact
	if _contacts_used < _contacts.size():
		c = _contacts[_contacts_used]
		c.clear()
	else:
		c = Contact.new()
		_contacts.append(c)
	_contacts_used += 1
	return c


func _step(h: float) -> void:
	_contacts_used = 0
	var live: Array = []
	for b: Body in bodies:
		b.turn = Basis(b.q)
		if b.awake:
			b.v.z -= GRAVITY * h
			live.append(b)
	if live.is_empty():
		return
	var contacts: Array = []
	for b: Body in live:
		b.grounded = false
		b.propped = false
		b.deepest = 0.0
		_world_contacts(b, h, contacts)
	# Each awake piece against every other (two awake ones once).
	for i in bodies.size():
		var o: Body = bodies[i]
		o.order = i
	for a: Body in live:
		for o: Body in bodies:
			if o == a or (o.awake and o.order < a.order):
				continue
			if a.group == o.group and (clock - a.born < APART or clock - o.born < APART):
				continue
			var r := a.reach + o.reach
			if a.p.distance_squared_to(o.p) > r * r:
				continue
			_pair(a, o, contacts)
			_pair(o, a, contacts)
	_prepare(contacts, h)
	for _pass in PASSES:
		for c: Contact in contacts:
			_solve(c)
	for c: Contact in contacts:
		if c.jn * c.a.inv_m > 1.2:
			knocks += 1
			if c.jn * c.a.inv_m > knock_hard:
				knock_hard = c.jn * c.a.inv_m
				knock_at = c.a.p + c.ra
	for b: Body in live:
		b.p += b.v * h
		var spin := b.w.length()
		if spin > 1e-6:
			b.q = (Quaternion(b.w / spin, spin * h) * b.q).normalized()
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
		if settled and b.v.length() < SLEEP_V and b.w.length() < SLEEP_W:
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
			if settled and b.held > HELD_AFTER and b.v.length() < 1.0:
				_sleep(b)
		# However it sits, one awake this long and slow lies down where it is.
		b.awake_for += h
		if b.awake and b.awake_for > LONGEST and b.v.length() < 1.0 and not tips:
			_sleep(b)
	_push_out(contacts)


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
	b.v = Vector3.ZERO
	b.w = Vector3.ZERO
	b.still = 0.0
	b.held = 0.0
	var turn := Basis(b.q)
	for k in 2:
		var lift := 0.0
		var out := Vector3.ZERO
		for i in 8:
			var c := b.p + turn * b.points[i]
			if solid(c):
				var way := _way_out(c)
				if way.length() > out.length():
					out = way
				continue
			var under := Tumble.floor_at(world, c.x, c.y, maxf(c.z, b.p.z) + .02)
			if under - c.z < LEDGE:
				lift = maxf(lift, under - c.z)
		b.p += out + Vector3(0.0, 0.0, lift)


## The floor, the roof and the walls against each of the piece's points.
func _world_contacts(b: Body, h: float, out: Array) -> void:
	var margin := MARGIN + b.v.length() * h
	# Nothing in the way anywhere it reaches and one floor under all of it
	# (the open yard, a room's middle: most of the time): only that floor can
	# touch it, and no wall. Three questions instead of three a corner.
	var open := _plain_under(b)
	if is_nan(open) and not world.blocked(b.p.x, b.p.y, b.reach, b.p.z):
		var wide := Tumble.floor_at(world, b.p.x, b.p.y, b.p.z, b.reach)
		var roof := world.roof_over(b.p.x, b.p.y, b.p.z)
		var clear := roof <= 0.0 or roof > b.p.z + b.reach + .5
		if clear and _level_ground(b) and wide == Tumble.floor_at(world, b.p.x, b.p.y, b.p.z):
			open = wide
	if not is_nan(open):
		for lp: Vector3 in b.points:
			var r := b.turn * lp
			var depth := open - (b.p.z + r.z)
			if depth > -margin:
				_add(b, r, Vector3(0.0, 0.0, 1.0), depth, E_FLOOR, out)
				b.grounded = b.grounded or depth > -.01
		return
	for lp: Vector3 in b.points:
		var r := b.turn * lp
		var at := b.p + r
		if _in_wall(at):
			var out_of := _way_out(at)
			if out_of != Vector3.ZERO:
				_add(b, r, out_of.normalized(), out_of.length(), E_WALL, out)
			continue
		# The floor under it, looked for from the piece's middle (or the point,
		# when it is higher): a fast fall never passes through a deck.
		var plain := _plain(at)
		var from := maxf(at.z, b.p.z) + .02
		var under := plain if not is_nan(plain) else Tumble.floor_at(world, at.x, at.y, from)
		var depth := under - at.z
		if depth > -margin and depth < LEDGE:
			_add(b, r, Vector3(0.0, 0.0, 1.0), depth, E_FLOOR, out)
			b.grounded = b.grounded or depth > -.01
			continue
		if b.v.z > -.5 and r.z > 0.0:
			var roof := world.roof_over(at.x, at.y, minf(at.z, b.p.z) - .02)
			if roof > 0.0 and at.z > roof - margin:
				_add(b, r, Vector3(0.0, 0.0, -1.0), at.z - roof, E_WALL, out)
		if depth >= LEDGE or (is_nan(plain) and solid(at)):
			var way := _way_out(at)
			if way != Vector3.ZERO:
				_add(b, r, way.normalized(), way.length(), E_WALL, out)


## Whether a point is in something: a wall, furniture, a deck's slab, or
## under ground or a top more than LEDGE over it (a step's side).
func solid(at: Vector3) -> bool:
	if _in_wall(at):
		return true
	var top := Tumble.floor_at(world, at.x, at.y, at.z + .02)
	if top > at.z + LEDGE:
		return true
	# A point a hair under (or over) a top it lies on is on it, not in it.
	if absf(top - at.z) < .04:
		return false
	return world.blocked(at.x, at.y, 0.0, at.z)


## The ground under a point in a plain cell (open, nothing in it: no
## furniture, door, deck, stair, pane or gate), where nothing but the ground
## can hold it up or stand in its way; NAN anywhere else (ask the level).
func _plain(at: Vector3) -> float:
	var w := world.width
	if at.x < 0.0 or at.y < 0.0 or at.x >= w or at.y >= world.height:
		return NAN
	var c := int(at.y) * w + int(at.x)
	if world.solid[c] >= 0 or not world.locked_gates.is_empty():
		return NAN
	if not world.pane_tiles.is_empty() and world.pane_tiles.has(Vector2i(int(at.x), int(at.y))):
		return NAN
	if world.index_cells.size() != w * world.height or world.index_cells[c] != 0:
		return NAN
	if world.geo != null and world.geo.cells[c] != 0:
		return NAN
	return world.ground[c]


## The ground under the whole of a piece when every cell it can reach is
## plain and at one height (_plain), and nothing over it (a roof); NAN else.
func _plain_under(b: Body) -> float:
	var r := b.reach + .05
	var ground := NAN
	for cy in range(floori(b.p.y - r), floori(b.p.y + r) + 1):
		for cx in range(floori(b.p.x - r), floori(b.p.x + r) + 1):
			var here := _plain(Vector3(cx + .5, cy + .5, 0.0))
			if is_nan(here) or (not is_nan(ground) and here != ground):
				return NAN
			ground = here
			if world.roof[cy * world.width + cx] > 0.0:
				return NAN
	return ground


## Whether the ground is one height under every cell a piece reaches.
func _level_ground(b: Body) -> bool:
	var r := b.reach + .05
	var w := world.width
	var x0 := floori(b.p.x - r)
	var y0 := floori(b.p.y - r)
	if x0 < 0 or y0 < 0 or floori(b.p.x + r) >= w or floori(b.p.y + r) >= world.height:
		return false
	var first := world.ground[y0 * w + x0]
	for cy in range(y0, floori(b.p.y + r) + 1):
		for cx in range(x0, floori(b.p.x + r) + 1):
			if world.ground[cy * w + cx] != first:
				return false
	return true


## Whether a point is in a solid cell (a wall), or off the map.
func _in_wall(at: Vector3) -> bool:
	if at.x < 0.0 or at.y < 0.0 or at.x >= world.width or at.y >= world.height:
		return true
	return world.solid[int(at.y) * world.width + int(at.x)] >= 0


## The shortest way out of a wall, furniture or a step's side, along x or y
## (ZERO when none is near).
func _way_out(at: Vector3) -> Vector3:
	var s := WALL_STEP
	while s <= WALL_REACH:
		for dir: Vector3 in [
			Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0)
		]:
			if not solid(at + dir * s):
				return dir * s
		s += WALL_STEP
	return Vector3.ZERO


func _add(b: Body, r: Vector3, n: Vector3, depth: float, e: float, out: Array) -> void:
	var c := _contact()
	c.a = b
	c.b = null
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


## The way two boxes overlap least, over each one's three face axes (pushing
## a away from o), and by how much; ZERO when they do not overlap.
static func _least(a: Body, o: Body) -> Vector3:
	var d := a.p - o.p
	var best := INF
	var way := Vector3.ZERO
	for k in 6:
		var axis: Vector3 = a.turn[k] if k < 3 else o.turn[k - 3]
		var ra := (
			a.half.x * absf(a.turn.x.dot(axis))
			+ a.half.y * absf(a.turn.y.dot(axis))
			+ a.half.z * absf(a.turn.z.dot(axis))
		)
		var rb := (
			o.half.x * absf(o.turn.x.dot(axis))
			+ o.half.y * absf(o.turn.y.dot(axis))
			+ o.half.z * absf(o.turn.z.dot(axis))
		)
		var along := d.dot(axis)
		var overlap := ra + rb - absf(along)
		if overlap <= 0.0:
			return Vector3.ZERO
		if overlap < best:
			best = overlap
			way = axis if along >= 0.0 else -axis
	return way * best


## a's points inside o's box: each a contact pushing a out of o along the way
## the two overlap least (a plank on a plank is pushed up, not off its side).
func _pair(a: Body, o: Body, out: Array) -> void:
	var least := _least(a, o)
	if least == Vector3.ZERO:
		return
	var n := least.normalized()
	# How far o reaches along n from its middle.
	var top := (
		o.half.x * absf(o.turn.x.dot(n))
		+ o.half.y * absf(o.turn.y.dot(n))
		+ o.half.z * absf(o.turn.z.dot(n))
	)
	var inverse := o.turn.transposed()
	var found := 0
	for lp: Vector3 in a.points:
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
		var c := _contact()
		c.a = a
		c.b = o
		c.ra = r
		c.rb = at - o.p
		c.n = n
		c.depth = deep
		c.e = E_BODY
		c.mu = MU_BODY
		out.append(c)
		# Lying on another piece holds it up as the floor does (it may sleep);
		# against one's side, it leans on it.
		if n.z > .5:
			a.grounded = true
		elif n.z < -.5:
			o.grounded = true
		if absf(n.z) < PROP_N or (n.z > .5 and r.z > 0.0):
			a.propped = true
			o.propped = true
		found += 1
		if found >= 4:
			return


func _rel(c: Contact) -> Vector3:
	var v := c.a.velocity_at(c.ra)
	if c.b != null:
		v -= c.b.velocity_at(c.rb)
	return v


func _mass_along(c: Contact, d: Vector3) -> float:
	var k := c.a.mass_inv() + c.a.inv_inertia(c.ra.cross(d)).cross(c.ra).dot(d)
	if c.b != null:
		k += c.b.mass_inv() + c.b.inv_inertia(c.rb.cross(d)).cross(c.rb).dot(d)
	return 1.0 / k if k > 1e-9 else 0.0


func _prepare(contacts: Array, h: float) -> void:
	for c: Contact in contacts:
		c.mass_n = _mass_along(c, c.n)
		var closing := _rel(c).dot(c.n)
		if c.depth < 0.0:
			# Not touching yet: it may close the gap this step, no more.
			c.bias = c.depth / h
		else:
			c.bias = -c.e * closing if closing < -BOUNCE_FROM else 0.0


func _solve(c: Contact) -> void:
	if c.mass_n <= 0.0:
		return
	var vn := _rel(c).dot(c.n)
	var dj := (c.bias - vn) * c.mass_n
	var total := maxf(c.jn + dj, 0.0)
	dj = total - c.jn
	c.jn = total
	_apply(c, c.n * dj)
	var vr := _rel(c)
	var slip := vr - c.n * vr.dot(c.n)
	var speed := slip.length()
	if speed < 1e-6:
		return
	var t := slip / speed
	var k := _mass_along(c, t)
	var want := c.jt - t * speed * k
	var most := c.mu * c.jn
	if want.length() > most:
		want = want.normalized() * most
	_apply(c, want - c.jt)
	c.jt = want


func _apply(c: Contact, j: Vector3) -> void:
	c.a.push(j, c.ra)
	if c.b != null:
		c.b.push(-j, c.rb)


## Penetration left after the step pushed out (the pieces' places only), each
## contact's share split among a piece's contacts so four corners on the
## floor lift it once, not four times.
func _push_out(contacts: Array) -> void:
	for c: Contact in contacts:
		c.a.touching = 0
		c.a.out_up = Vector3.ZERO
		c.a.out_down = Vector3.ZERO
		if c.b != null:
			c.b.touching = 0
	for c: Contact in contacts:
		if c.depth > SLOP:
			c.a.touching += 1
			if c.b != null:
				c.b.touching += 1
	# Pieces out of one another first, then out of the level, so the floor
	# and the walls have the last word (a pile never squeezes one into them).
	for world_pass in 2:
		for c: Contact in contacts:
			if (c.b == null) != (world_pass == 1):
				continue
			var d := c.depth - SLOP
			if d <= 0.0:
				continue
			var ia := c.a.mass_inv()
			var ib := 0.0 if c.b == null else c.b.mass_inv()
			if ia + ib <= 0.0:
				continue
			if c.b == null:
				# Out of the level by the deepest of its contacts each way (the
				# level's are along the axes), not their sum.
				var want := c.n * d * PUSH
				c.a.out_up = c.a.out_up.max(want)
				c.a.out_down = c.a.out_down.min(want)
				continue
			var move := c.n * d * PUSH / (ia + ib)
			c.a.p += move * ia / maxi(1, c.a.touching)
			c.b.p -= move * ib / maxi(1, c.b.touching)
		if world_pass == 1:
			for c: Contact in contacts:
				if c.b == null and c.a.awake:
					c.a.p += c.a.out_up + c.a.out_down
					c.a.out_up = Vector3.ZERO
					c.a.out_down = Vector3.ZERO


## A push at `at` (a blast's shove, a boot): wakes the piece.
static func knock(b: Body, dv: Vector3, spin: Vector3) -> void:
	b.wake()
	b.v += dv
	b.w += spin


## Whether a piece at rest lost what held it up (the crate it lay on broke):
## its lowest corner is well over the floor under it.
func unsupported(b: Body) -> bool:
	var turn := Basis(b.q)
	var near: Array = []
	for o: Body in bodies:
		if o != b and o.p.distance_to(b.p) < o.reach + b.reach + .1:
			near.append(o)
	for k in 8:
		var c := b.p + turn * b.points[k]
		# A corner on a floor, a top or a wall's foot...
		if Tumble.floor_at(world, c.x, c.y, b.p.z + .02) >= c.z - .05:
			return false
		# ...leaning on a wall (a stave propped in a corner is held there)...
		for side: Vector3 in LEAN_SIDES:
			if solid(c + side):
				return false
		# ...or on another piece.
		var below := c - Vector3(0.0, 0.0, .04)
		for o: Body in near:
			var l := Basis(o.q).transposed() * (below - o.p)
			var room := o.half + Vector3(.02, .02, .02)
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
			var way := _way_out(c)
			worst = maxf(worst, way.length() if way != Vector3.ZERO else WALL_REACH)
	return worst
