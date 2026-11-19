## The loose things' shared physics core. The rigid-body solvers (the wreck
## pieces, wreck_physics.gd; the bowling pins and the midway's bottles,
## range_pin_physics.gd) and the ragdolls (ragdoll.gd) are built on it:
##
## - Body, Box, Contact, Pool: a rigid body (a middle, a turn, a slide and a
##   spin), a box of one, a contact between two (or one and the level), and
##   contacts kept and handed out again each step.
## - The contact solver: sequential impulses with friction and bounce. Two
##   ways to run it: `prepare`/`solve`, the exact one (every number worked
##   out as the pins always have: play's bowling stays the same to the last
##   bit on every machine), and `prepare_fast`/`solve_fast`, which works out
##   each contact's turning terms once a step instead of every pass (looks:
##   the wreck pieces; about four times cheaper).
## - Grid: a broadphase (a hash of cells) so many bodies find their near
##   neighbours without asking every other one.
## - The level's questions every loose thing asks: whether a cell is plain
##   open floor (`plain`, `plain_under`, `plain_rect`), whether a point is in
##   a wall, furniture or a step's side (`solid`, `in_wall`, `way_out`), a
##   ball in a wall or a rail (`ball_solid`, `rail_at`), and Floors (a
##   point's floor kept while it stays put, so a body settling asks the level
##   once, not every step).
## - Space: what lies about on one level (kept on the LevelData), so things
##   of different solvers meet: a ragdoll's balls lie on wreck pieces and
##   wreck pieces on a ragdoll (looks only, both).
## - Resting on: a body asleep remembers what it lies on (Body.under), and
##   waking one wakes all that rests on it (`wake_resting_on`).
##
## Pure GDScript arithmetic, no dice, no threads, no native physics: the
## same every time on every machine (play's users stay exact). Map axes:
## x, y across, z up.
class_name PhysCore
extends RefCounted

## A floor more than this over a point is a step's side to it, not a floor
## (solid()).
const LEDGE := .2
## How far in a wall a point is looked out of, in steps of WALL_STEP.
const WALL_STEP := .03
const WALL_REACH := .6
## A point's floor is asked again once it has moved this far across (Floors).
const REASK := .03
## A fast pass that changes no speed by more than this (cells a second)
## ends the passes (solve_fast).
const SETTLED := .005
## Grid cells this wide (cells of the map).
const GRID := 1.0
## No turning at all (a body asleep, to the fast solver).
const STILL := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
## way_out: the most furniture a cell may list and still be summed by which
## of it holds a probe, and the room for those sums.
const HELD_MOST := 24
const HELD_KINDS := 1 << 24
const WAYS: Array[Vector3] = [
	Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0)
]


## A rigid body: its middle, turn (a quaternion), slide and spin, its weight's
## inverse. A solver's own bodies extend it (inv_inertia is theirs).
class Body:
	extends RefCounted
	var p := Vector3.ZERO
	var q := Quaternion.IDENTITY
	var v := Vector3.ZERO
	var w := Vector3.ZERO
	var inv_m := 1.0
	var awake := true
	## On the floor (or something that holds it as one) this step.
	var grounded := false
	## What it lies on while asleep (another body), or null: waking that
	## wakes this (PhysCore.wake_resting_on).
	var under: Body = null
	## Its inverse inertia in world axes this step (the fast solver's; none:
	## a point mass).
	var iw := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)

	## Its inverse inertia applied to `t` (none: a point mass).
	func inv_inertia(_t: Vector3) -> Vector3:
		return Vector3.ZERO

	func mass_inv() -> float:
		return inv_m if awake else 0.0

	func velocity_at(r: Vector3) -> Vector3:
		return v + w.cross(r)

	func push(j: Vector3, r: Vector3) -> void:
		v += j * mass_inv()
		w += inv_inertia(r.cross(j))

	func wake() -> void:
		awake = true


## A box: `half` its size each way, its moments from its size, `turn` its
## Basis this step, `reach` how far its farthest corner is from its middle,
## `points` the points of it that touch (its corners, and along a long stick
## points between).
class Box:
	extends Body
	var half := Vector3(.05, .05, .05)
	var inv_i := Vector3.ONE
	var turn := Basis.IDENTITY
	var reach := .1
	var points := PackedVector3Array()
	## The middles of its twelve edges (two flat boxes lying face to face,
	## turned so neither's corners are over the other, touch by these).
	var edges := PackedVector3Array()

	## A box `size` half its size each way, of density `dense`.
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
		edges = PackedVector3Array()
		for a in 3:
			for k in 4:
				var m := Vector3.ZERO
				m[(a + 1) % 3] = size[(a + 1) % 3] if k & 1 else -size[(a + 1) % 3]
				m[(a + 2) % 3] = size[(a + 2) % 3] if k & 2 else -size[(a + 2) % 3]
				edges.append(m)
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

	## Its turn this step, and its inverse inertia in world axes from it.
	func turned() -> void:
		turn = Basis(q)
		iw = turn * Basis.from_scale(inv_i) * turn.transposed()

	## How far the box reaches along the unit vector `n` from its middle.
	func extent(n: Vector3) -> float:
		return (
			half.x * absf(turn.x.dot(n))
			+ half.y * absf(turn.y.dot(n))
			+ half.z * absf(turn.z.dot(n))
		)

	## A ball at `at` of radius `r` inside the box: the way out of it (from
	## the box's middle outwards, world) times how deep; ZERO when clear.
	func ball_out(at: Vector3, r: float) -> Vector3:
		var lying := Basis(q)
		var l := lying.transposed() * (at - p)
		var near := l.clamp(-half, half)
		var off := l - near
		var d2 := off.length_squared()
		if d2 >= r * r:
			return Vector3.ZERO
		if d2 > 1e-10:
			var d := sqrt(d2)
			return lying * (off / d * (r - d))
		# Its middle inside: out through the nearest face.
		var room := half - l.abs()
		var axis := 0
		if room.y < room[axis]:
			axis = 1
		if room.z < room[axis]:
			axis = 2
		var way := Vector3.ZERO
		way[axis] = (room[axis] + r) * (1.0 if l[axis] >= 0.0 else -1.0)
		return lying * way


## A contact: bodies a and b (b null: the level, or something held still),
## the points from each middle, the normal (pushing a away from b), how deep
## (below 0: not touching yet), the bounce and friction, the impulses so far,
## and what the fast solver works out once a step.
class Contact:
	var a: Body
	var b: Body
	var ra := Vector3.ZERO
	var rb := Vector3.ZERO
	var n := Vector3(0.0, 0.0, 1.0)
	var depth := 0.0
	var bias := 0.0
	var mu := 0.0
	var e := 0.0
	var jn := 0.0
	var jt := Vector3.ZERO
	var mass_n := 0.0
	## A solver's own sort (the pins: 0 a wall, 1 pin on pin, 2 ball on pin,
	## 3 the deck), and whether it is the lane's cushion.
	var kind := 0
	var cushion := false
	# The fast solver's terms: each body's weight's inverse, ra x n (and the
	# two ways across it) and the spin a push along it gives.
	var ima := 0.0
	var imb := 0.0
	var an := Vector3.ZERO
	var bn := Vector3.ZERO
	var ian := Vector3.ZERO
	var ibn := Vector3.ZERO
	var t1 := Vector3.ZERO
	var t2 := Vector3.ZERO
	var at1 := Vector3.ZERO
	var at2 := Vector3.ZERO
	var bt1 := Vector3.ZERO
	var bt2 := Vector3.ZERO
	var iat1 := Vector3.ZERO
	var iat2 := Vector3.ZERO
	var ibt1 := Vector3.ZERO
	var ibt2 := Vector3.ZERO
	var mass_t1 := 0.0
	var mass_t2 := 0.0
	var jt1 := 0.0
	var jt2 := 0.0

	## PhysCore.solve: the exact pass, as PhysCore.rel, mass_along and apply
	## work it out.
	func solve_exact() -> void:
		if mass_n <= 0.0:
			return
		var vn := _rel().dot(n)
		var dj := (bias - vn) * mass_n
		var total := maxf(jn + dj, 0.0)
		dj = total - jn
		jn = total
		_apply(n * dj)
		var vr := _rel()
		var slip := vr - n * vr.dot(n)
		var speed := slip.length()
		if speed < 1e-6:
			return
		var t := slip / speed
		var k := _mass_along(t)
		var want := jt - t * speed * k
		var most := mu * jn
		if want.length() > most:
			want = want.normalized() * most
		_apply(want - jt)
		jt = want

	func _rel() -> Vector3:
		var v := a.velocity_at(ra)
		if b != null:
			v -= b.velocity_at(rb)
		return v

	func _mass_along(d: Vector3) -> float:
		var k := a.mass_inv() + a.inv_inertia(ra.cross(d)).cross(ra).dot(d)
		if b != null:
			k += b.mass_inv() + b.inv_inertia(rb.cross(d)).cross(rb).dot(d)
		return 1.0 / k if k > 1e-9 else 0.0

	func _apply(j: Vector3) -> void:
		a.push(j, ra)
		if b != null:
			b.push(-j, rb)

	## Its terms for the fast solve (PhysCore.prepare_fast).
	func prepare(h: float, bounce_from: float) -> void:
		var tx := n.cross(Vector3(1.0, 0.0, 0.0) if absf(n.x) < .6 else Vector3(0.0, 1.0, 0.0))
		t1 = tx.normalized()
		t2 = n.cross(t1)
		ima = a.mass_inv()
		an = ra.cross(n)
		at1 = ra.cross(t1)
		at2 = ra.cross(t2)
		var ia := a.iw if a.awake else STILL
		ian = ia * an
		iat1 = ia * at1
		iat2 = ia * at2
		var kn := ima + ian.dot(an)
		var k1 := ima + iat1.dot(at1)
		var k2 := ima + iat2.dot(at2)
		var closing := a.v.dot(n) + a.w.dot(an)
		if b != null:
			imb = b.mass_inv()
			bn = rb.cross(n)
			bt1 = rb.cross(t1)
			bt2 = rb.cross(t2)
			var ib := b.iw if b.awake else STILL
			ibn = ib * bn
			ibt1 = ib * bt1
			ibt2 = ib * bt2
			kn += imb + ibn.dot(bn)
			k1 += imb + ibt1.dot(bt1)
			k2 += imb + ibt2.dot(bt2)
			closing -= b.v.dot(n) + b.w.dot(bn)
		mass_n = 1.0 / kn if kn > 1e-9 else 0.0
		mass_t1 = 1.0 / k1 if k1 > 1e-9 else 0.0
		mass_t2 = 1.0 / k2 if k2 > 1e-9 else 0.0
		if depth < 0.0:
			bias = depth / h
		else:
			bias = -e * closing if closing < -bounce_from else 0.0

	## One fast pass on this contact (PhysCore.solve_fast): the push along
	## its normal, then friction across it held inside mu times the push.
	## Returns how much it changed the speeds (0 when it has no weight).
	func solve_once() -> float:
		if mass_n <= 0.0:
			return 0.0
		var vn := a.v.dot(n) + a.w.dot(an)
		if b != null:
			vn -= b.v.dot(n) + b.w.dot(bn)
		var total := maxf(jn + (bias - vn) * mass_n, 0.0)
		var dj := total - jn
		jn = total
		if dj != 0.0:
			a.v += n * (dj * ima)
			a.w += ian * dj
			if b != null:
				b.v -= n * (dj * imb)
				b.w -= ibn * dj
		var most := mu * total
		var v1 := a.v.dot(t1) + a.w.dot(at1)
		var v2 := a.v.dot(t2) + a.w.dot(at2)
		if b != null:
			v1 -= b.v.dot(t1) + b.w.dot(bt1)
			v2 -= b.v.dot(t2) + b.w.dot(bt2)
		var j1 := jt1 - v1 * mass_t1
		var j2 := jt2 - v2 * mass_t2
		var sq := j1 * j1 + j2 * j2
		if sq > most * most:
			var k := most / sqrt(sq) if sq > 1e-18 else 0.0
			j1 *= k
			j2 *= k
		var d1 := j1 - jt1
		var d2 := j2 - jt2
		jt1 = j1
		jt2 = j2
		var changed := (absf(dj) + absf(d1) + absf(d2)) * (ima + imb)
		if d1 == 0.0 and d2 == 0.0:
			return changed
		a.v += (t1 * d1 + t2 * d2) * ima
		a.w += iat1 * d1 + iat2 * d2
		if b != null:
			b.v -= (t1 * d1 + t2 * d2) * imb
			b.w -= ibt1 * d1 + ibt2 * d2
		return changed


## Contacts kept and handed out again each step (a step of 48 boxes in the
## air makes hundreds; making them anew was a good share of its cost).
class Pool:
	var _kept: Array[Contact] = []
	var _used := 0

	## Hand them all out again from the first.
	func reset() -> void:
		_used = 0

	## A contact as new.
	func take() -> Contact:
		var c: Contact
		if _used < _kept.size():
			c = _kept[_used]
			c.b = null
			c.rb = Vector3.ZERO
			c.depth = 0.0
			c.jn = 0.0
			c.jt = Vector3.ZERO
			c.jt1 = 0.0
			c.jt2 = 0.0
			c.kind = 0
			c.cushion = false
		else:
			c = Contact.new()
			_kept.append(c)
		_used += 1
		return c


# ------------------------------------------------------------------ the solver


## The closing speed of a contact's two points (a's less b's).
static func rel(c: Contact) -> Vector3:
	var v := c.a.velocity_at(c.ra)
	if c.b != null:
		v -= c.b.velocity_at(c.rb)
	return v


## The impulse it takes to change the closing speed along `d` by one.
static func mass_along(c: Contact, d: Vector3) -> float:
	var k := c.a.mass_inv() + c.a.inv_inertia(c.ra.cross(d)).cross(c.ra).dot(d)
	if c.b != null:
		k += c.b.mass_inv() + c.b.inv_inertia(c.rb.cross(d)).cross(c.rb).dot(d)
	return 1.0 / k if k > 1e-9 else 0.0


## Ready the contacts for the exact solve: each one's mass along its normal
## and the speed it wants (its bounce, `e` of a closing speed faster than
## `bounce_from`; a contact not touching yet may close its gap this step).
static func prepare(contacts: Array, h: float, bounce_from: float) -> void:
	for c: Contact in contacts:
		c.mass_n = mass_along(c, c.n)
		var closing := rel(c).dot(c.n)
		if c.depth < 0.0:
			c.bias = c.depth / h
		else:
			c.bias = -c.e * closing if closing < -bounce_from else 0.0


## One exact pass on a contact: the push along its normal (never pulling),
## then friction against the slip, no more than mu times the push
## (Contact.solve_exact: the same sums, on the contact's own fields).
static func solve(c: Contact) -> void:
	c.solve_exact()


static func apply(c: Contact, j: Vector3) -> void:
	c.a.push(j, c.ra)
	if c.b != null:
		c.b.push(-j, c.rb)


## Ready the contacts for the fast solve: the turning terms along the normal
## and two fixed ways across it, worked out once (no body's turn or sleep
## changes while the passes run).
static func prepare_fast(contacts: Array, h: float, bounce_from: float) -> void:
	for c: Contact in contacts:
		# (Contact.prepare: the same sums, on the contact's own fields.)
		c.prepare(h, bounce_from)


## The fast passes over the contacts (prepare_fast first), at most
## `passes`: on each, the push along its normal, then friction along the two
## ways across it, held inside a circle of mu times the push. Stops early
## once a pass changes no speed by more than SETTLED (a pile at rest
## converges in one or two). Returns the passes taken.
static func solve_fast(contacts: Array, passes: int) -> int:
	for pass_no in passes:
		var change := 0.0
		for item: Variant in contacts:
			var c: Contact = item
			# (Contact.solve_once: the same sums in the same order, on the
			# contact's own fields, read there at half the cost.)
			change = maxf(change, c.solve_once())
		if change < SETTLED:
			return pass_no + 1
	return passes


## Move a body on by its slide and spin for h seconds.
static func integrate(b: Body, h: float) -> void:
	b.p += b.v * h
	var spin := b.w.length()
	if spin > 1e-6:
		b.q = (Quaternion(b.w / spin, spin * h) * b.q).normalized()


# ------------------------------------------------------------------ sleeping


## Wake every body asleep on `b` (Body.under), and every one on those.
## Returns how many woke.
static func wake_resting_on(bodies: Array, b: Body) -> int:
	var woke := 0
	var queue: Array[Body] = [b]
	while not queue.is_empty():
		var below: Body = queue.pop_back()
		for item: Variant in bodies:
			var o: Body = item
			if o.under == below and o != below:
				o.under = null
				if not o.awake:
					o.wake()
					woke += 1
					queue.append(o)
	return woke


# ------------------------------------------------------------------ the grid


## A broadphase: each body's square of reach in the cells it covers, so a
## body asks only those sharing a cell with it.
class Grid:
	var _cells := {}
	var _mark := PackedInt32Array()
	var _ask := 0

	func clear(count: int) -> void:
		_cells.clear()
		if _mark.size() < count:
			_mark.resize(count)
			_mark.fill(-1)

	static func _key(cx: int, cy: int) -> int:
		return (cy + 8192) * 16384 + cx + 8192

	## Body `i` at (x, y), reaching r. (Each cell's list an Array, added to
	## where it lies; _key written out: pass 13.)
	func add(i: int, x: float, y: float, r: float) -> void:
		var x0 := floori((x - r) / GRID)
		var x1 := floori((x + r) / GRID)
		for cy in range(floori((y - r) / GRID), floori((y + r) / GRID) + 1):
			var row := (cy + 8192) * 16384 + 8192
			for cx in range(x0, x1 + 1):
				var k := row + cx
				var list: Variant = _cells.get(k)
				if list == null:
					_cells[k] = [i]
				else:
					var ids: Array = list
					ids.append(i)

	## The bodies sharing a cell with the square r round (x, y), each once,
	## in the order they were added within a cell.
	func near(x: float, y: float, r: float) -> PackedInt32Array:
		_ask += 1
		var ask := _ask
		var out := PackedInt32Array()
		var x0 := floori((x - r) / GRID)
		var x1 := floori((x + r) / GRID)
		for cy in range(floori((y - r) / GRID), floori((y + r) / GRID) + 1):
			var row := (cy + 8192) * 16384 + 8192
			for cx in range(x0, x1 + 1):
				var list: Variant = _cells.get(row + cx)
				if list == null:
					continue
				var ids: Array = list
				for i: int in ids:
					if _mark[i] != ask:
						_mark[i] = ask
						out.append(i)
		return out


# ------------------------------------------------------------------ the level


## A point's floor kept while the point stays put: asked again once it moves
## REASK across, rises over where it was asked from or sinks under the floor
## found. Point i of a body (or ball i of a ragdoll).
class Floors:
	var at := PackedVector3Array()
	var floor := PackedFloat32Array()
	## 1 where the floor was a plain cell's ground (PhysCore.plain).
	var flat := PackedByteArray()
	## The roof over the point, asked when wanted (NAN: not yet), and
	## whether the point is in something (solid(): 0 no, 1 yes, 2 not yet).
	var roof := PackedFloat32Array()
	var inside := PackedByteArray()

	func size_to(n: int) -> void:
		if at.size() != n:
			at.resize(n)
			floor.resize(n)
			flat.resize(n)
			roof.resize(n)
			inside.resize(n)
			at.fill(Vector3.INF)

	## Whether point i's floor asked before still holds at (x, y) from z.
	func held(i: int, x: float, y: float, z: float) -> bool:
		var was := at[i]
		return (
			absf(x - was.x) < REASK
			and absf(y - was.y) < REASK
			and z <= was.z + .01
			and z >= floor[i] - .01
		)

	func keep(i: int, x: float, y: float, z: float, under: float, plain := false) -> void:
		at[i] = Vector3(x, y, z)
		floor[i] = under
		flat[i] = 1 if plain else 0
		roof[i] = NAN
		inside[i] = 2

	## Ask every point again (woken: what held it may have gone).
	func forget() -> void:
		at.fill(Vector3.INF)


## The ground under a point in a plain cell (open, nothing in it: no
## furniture, door, deck, stair, pane or gate), where nothing but the ground
## can hold it up or stand in its way; NAN anywhere else (ask the level).
static func plain(world: LevelData, x: float, y: float) -> float:
	var w := world.width
	if x < 0.0 or y < 0.0 or x >= w or y >= world.height:
		return NAN
	var c := int(y) * w + int(x)
	if world.solid[c] >= 0 or not world.locked_gates.is_empty():
		return NAN
	if not world.pane_tiles.is_empty() and world.pane_tiles.has(Vector2i(int(x), int(y))):
		return NAN
	if world.index_cells.size() != w * world.height or world.index_cells[c] != 0:
		return NAN
	if world.geo != null and world.geo.cells[c] != 0:
		return NAN
	return world.ground[c]


## The ground under the whole of something reaching r from `at` when every
## cell it can reach is plain and at one height, and nothing over it (a
## roof); NAN else.
static func plain_under(world: LevelData, at: Vector3, r: float) -> float:
	var reach := r + .05
	var ground := NAN
	for cy in range(floori(at.y - reach), floori(at.y + reach) + 1):
		for cx in range(floori(at.x - reach), floori(at.x + reach) + 1):
			var here := plain(world, cx + .5, cy + .5)
			if is_nan(here) or (not is_nan(ground) and here != ground):
				return NAN
			ground = here
			if world.roof[cy * world.width + cx] > 0.0:
				return NAN
	return ground


## Whether every cell from (x0, y0) to (x1, y1) is open floor with nothing of
## the geometry, no furniture or door in it, no pane next to it and no locked
## gate within three cells: the cells' own ground and roof are all there is.
static func plain_rect(world: LevelData, x0: int, y0: int, x1: int, y1: int) -> bool:
	if world.index_cells.size() != world.width * world.height:
		return false
	if x0 < 0 or y0 < 0 or x1 >= world.width or y1 >= world.height:
		return false
	var geo := world.geo
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var c := y * world.width + x
			if world.solid[c] >= 0 or world.index_cells[c] != 0:
				return false
			if geo != null and geo.cells[c] != 0:
				return false
	for pane: Vector2i in world.pane_tiles:
		if pane.x >= x0 - 1 and pane.x <= x1 + 1 and pane.y >= y0 - 1 and pane.y <= y1 + 1:
			return false
	for gate: LevelData.Gate in world.locked_gates:
		if (
			absf(gate.x - (x0 + x1 + 1) * .5) < gate.width + 3.0
			and absf(gate.y - (y0 + y1 + 1) * .5) < 3.0
		):
			return false
	return true


## Whether the ground is one height under every cell within r of `at`.
static func level_ground(world: LevelData, at: Vector3, r: float) -> bool:
	var reach := r + .05
	var w := world.width
	var x0 := floori(at.x - reach)
	var y0 := floori(at.y - reach)
	if x0 < 0 or y0 < 0 or floori(at.x + reach) >= w or floori(at.y + reach) >= world.height:
		return false
	var first := world.ground[y0 * w + x0]
	for cy in range(y0, floori(at.y + reach) + 1):
		for cx in range(x0, floori(at.x + reach) + 1):
			if world.ground[cy * w + cx] != first:
				return false
	return true


## Whether a point is in a solid cell (a wall), or off the map.
static func in_wall(world: LevelData, at: Vector3) -> bool:
	if at.x < 0.0 or at.y < 0.0 or at.x >= world.width or at.y >= world.height:
		return true
	return world.solid[int(at.y) * world.width + int(at.x)] >= 0


## Whether a point is in something: a wall, furniture, a deck's slab, or
## under ground or a top more than LEDGE over it (a step's side).
static func solid(world: LevelData, at: Vector3) -> bool:
	if in_wall(world, at):
		return true
	if empty_cell(world, at.x, at.y):
		return world.ground[int(at.y) * world.width + int(at.x)] > at.z + LEDGE
	return _in_something(world, at)


## solid() for a point not in a wall cell.
static func _in_something(world: LevelData, at: Vector3) -> bool:
	var top := Tumble.floor_at(world, at.x, at.y, at.z + .02)
	if top > at.z + LEDGE:
		return true
	# A point a hair under (or over) a top it lies on is on it, not in it.
	if absf(top - at.z) < .04:
		return false
	return world.blocked(at.x, at.y, 0.0, at.z)


## Whether the open cell under (x, y) (not a wall: the caller knows) holds
## nothing now but its ground: no piece of the geometry, no furniture or
## door listed there (the lists as they are: broken furniture is gone from
## them though index_cells still marks the cell), no pane that could meet a
## point in it, no locked gate. There a point's floor is the cell's ground
## and blocked() finds nothing (round 2 of pass 10: the wreck pieces lie
## where the breakables stood).
static func empty_cell(world: LevelData, x: float, y: float) -> bool:
	if not world.locked_gates.is_empty():
		return false
	var ix := int(x)
	var iy := int(y)
	var c := iy * world.width + ix
	if world.geo != null and world.geo.cells[c] != 0:
		return false
	if not world.pane_tiles.is_empty():
		if world.pane_cells.size() != world.width * world.height or world.pane_cells[c] != 0:
			return false
	if world.index_cells.size() == world.width * world.height and world.index_cells[c] == 0:
		return true
	var key := Vector2i(ix, iy)
	var fixtures: Array = world.near_fixtures.get(key, LevelData.NOTHING)
	if not fixtures.is_empty():
		return false
	var doors: Array = world.near_doors.get(key, LevelData.NOTHING)
	return doors.is_empty()


## The floor under a point (Tumble.floor_at), the cell's ground in an empty
## open cell (empty_cell) without asking the level.
static func floor_under(world: LevelData, x: float, y: float, z: float) -> float:
	if (
		x >= 0.0
		and y >= 0.0
		and x < world.width
		and y < world.height
		and world.solid[int(y) * world.width + int(x)] < 0
		and empty_cell(world, x, y)
	):
		return world.ground[int(y) * world.width + int(x)]
	return Tumble.floor_at(world, x, y, z)


## The shortest way out of a wall, furniture or a step's side, along x or y
## (ZERO when none is near). Every probe is at the point's height, so a
## probe's answer is its cell's and which of the furniture listed there
## holds it (_in_something reads nothing else there): worked out once for
## each such pair (a point deep in furniture asked eighty probes, most of
## them for nothing). A cell with a piece of the geometry, a door, a pane
## near or a locked gate is asked probe by probe as ever.
static func way_out(world: LevelData, at: Vector3) -> Vector3:
	var w := world.width
	var hgt := world.height
	var cells := world.solid
	var plain_world := (
		world.locked_gates.is_empty()
		and (world.pane_tiles.is_empty() or world.pane_cells.size() == w * hgt)
	)
	# Per cell: its furniture list (null: asked probe by probe); per cell and
	# furniture held, the answer (1 solid, 0 clear).
	var lists := {}
	var answers := {}
	# Each way's last cell and its list, and the last (cell, furniture held)
	# it found solid (pass 13: a probe still in the cell and the furniture of
	# the one before it asks no table: its answer is that one's, solid, or it
	# would have returned).
	var last_c := PackedInt32Array([-1, -1, -1, -1])
	var last_list: Array = [null, null, null, null]
	var last_key := PackedInt64Array([-1, -1, -1, -1])
	var s := WALL_STEP
	while s <= WALL_REACH:
		for d in 4:
			var dir: Vector3 = WAYS[d]
			var probe := at + dir * s
			if probe.x < 0.0 or probe.y < 0.0 or probe.x >= w or probe.y >= hgt:
				continue
			var ix := int(probe.x)
			var iy := int(probe.y)
			var c := iy * w + ix
			if cells[c] >= 0:
				continue
			var listed: Variant
			if c == last_c[d]:
				listed = last_list[d]
			else:
				if not lists.has(c):
					lists[c] = _held_list(world, plain_world, ix, iy, c)
				listed = lists[c]
				last_c[d] = c
				last_list[d] = listed
			if listed == null:
				if not _in_something(world, probe):
					return dir * s
				continue
			var fixtures: Array = listed
			var held := 0
			for k in fixtures.size():
				var f: PackedFloat32Array = fixtures[k]
				if f[0] < probe.x and probe.x < f[2] and f[1] < probe.y and probe.y < f[3]:
					held |= 1 << k
			var key := c * HELD_KINDS + held
			if key == last_key[d]:
				continue
			var answer: int = answers.get(key, -1)
			if answer < 0:
				answer = 1 if _in_something(world, probe) else 0
				answers[key] = answer
			if answer == 0:
				return dir * s
			last_key[d] = key
		s += WALL_STEP
	return Vector3.ZERO


## The furniture listed under open cell (ix, iy) when a point's solid() there
## is its ground's and that furniture's alone (no geometry, door, pane or
## gate in the way); null when not (or more than HELD_MOST listed).
static func _held_list(world: LevelData, plain_world: bool, ix: int, iy: int, c: int) -> Variant:
	if not plain_world:
		return null
	if world.geo != null and world.geo.cells[c] != 0:
		return null
	if not world.pane_tiles.is_empty() and world.pane_cells[c] != 0:
		return null
	var key := Vector2i(ix, iy)
	var doors: Array = world.near_doors.get(key, LevelData.NOTHING)
	if not doors.is_empty():
		return null
	var fixtures: Array = world.near_fixtures.get(key, LevelData.NOTHING)
	if fixtures.size() > HELD_MOST:
		return null
	return fixtures


## Whether a ball of radius r at p is in a wall, furniture, a slab's side or
## a rail.
static func ball_solid(world: LevelData, p: Vector3, r: float) -> bool:
	return world.blocked(p.x, p.y, r * .8, p.z) or rail_at(world, p, r) != null


## The rail (a free wall that lets sight by, which blocked() leaves out) a
## ball of radius r at p is in, or null.
static func rail_at(world: LevelData, p: Vector3, r: float) -> LevelGeometry.Segment:
	if world.geo == null or world.geo.clear_at(p.x, p.y):
		return null
	for item: Variant in world.geo.near_items(p.x, p.y):
		if item is LevelGeometry.Segment:
			var s: LevelGeometry.Segment = item
			if not s.sight and p.z + r > s.z0 and p.z - r < s.z1:
				var reach := r * .8 + s.half
				if s.dist2(p.x, p.y) < reach * reach:
					return s
	return null


# ------------------------------------------------------------------ the space


## What lies about on one level for things of other solvers to meet: the
## wreck pieces (Box, wreck_physics.gd hands its list) and how many of them
## are awake (a ragdoll asleep on one wakes when they stir).
class Space:
	var boxes: Array = []
	var stirring := 0


## The level's Space (made the first time it is asked for, kept on the level).
static func space(world: LevelData) -> Space:
	if world.has_meta(&"phys_space"):
		var kept: Space = world.get_meta(&"phys_space")
		return kept
	var made := Space.new()
	world.set_meta(&"phys_space", made)
	return made
