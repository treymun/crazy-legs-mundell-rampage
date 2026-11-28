## The wreck pieces' pairs (WreckPhysics' step): which awake piece is near
## which other, and the way each pair overlaps least, both ways at once
## (pass 13: moved out of wreck_physics.gd with its new sums). Looks only,
## the same sums in the same order as WreckPhysics._least.
class_name WreckPairs
extends RefCounted


## Each awake piece against every other near it (two awake ones once): by
## the core's grid when there are many, every other when few.
static func pairs(phys: WreckPhysics, live: Array, contacts: Array) -> void:
	var bodies := phys.bodies
	var grid := phys.grid
	var clock := phys.clock
	var count := bodies.size()
	var gridded := count > WreckPhysics.GRID_FROM
	if gridded:
		grid.clear(count)
	for i in count:
		var o: WreckPhysics.Body = bodies[i]
		o.order = i
		if gridded:
			grid.add(i, o.p.x, o.p.y, o.reach)
	for a: WreckPhysics.Body in live:
		# _pair_up's tests asked here, before the call (most pairs fail one):
		# itself, an awake one met already, one of its own break just thrown
		# (WreckPhysics.APART), out of reach.
		var ap := a.p
		var ar := a.reach
		var order := a.order
		var group := a.group
		var young := clock - a.born < WreckPhysics.APART
		if gridded:
			var near := grid.near(ap.x, ap.y, ar)
			near.sort()
			for i in near:
				var o: WreckPhysics.Body = bodies[i]
				if i == order or (i < order and o.awake):
					continue
				if group == o.group and (young or clock - o.born < WreckPhysics.APART):
					continue
				var r := ar + o.reach
				if ap.distance_squared_to(o.p) <= r * r:
					_pair_up(phys, a, o, contacts)
		else:
			for o: WreckPhysics.Body in bodies:
				if o == a or (o.awake and o.order < order):
					continue
				if group == o.group and (young or clock - o.born < WreckPhysics.APART):
					continue
				var r := ar + o.reach
				if ap.distance_squared_to(o.p) <= r * r:
					_pair_up(phys, a, o, contacts)


## Two pieces near enough to touch (pairs() asked the rest), each against the
## other.
static func _pair_up(
	phys: WreckPhysics, a: WreckPhysics.Body, o: WreckPhysics.Body, contacts: Array
) -> void:
	if leasts(a, o, phys.stamp, phys.leasts_out):
		var least_a: Vector3 = phys.leasts_out[0]
		var least_o: Vector3 = phys.leasts_out[1]
		phys.pair_with(a, o, least_a, contacts)
		phys.pair_with(o, a, least_o, contacts)


## WreckPhysics._least(a, o) into out[0] and _least(o, a) into out[1] (the
## turns as of step `stamp`); false when the boxes do not overlap (both ZERO).
static func leasts(a: WreckPhysics.Body, o: WreckPhysics.Body, stamp: int, out: Array) -> bool:
	# WreckPhysics._least(a, o) and _least(o, a) at once (pass 13): the six
	# face axes' overlaps are the same numbers both ways (the sums the same,
	# the side flipped), each extent from the nine dots of one turn's axes on
	# the other's and each turn's own (Body.own_extents), not twelve extents'
	# thirty-six dots twice. Each way still picks its least in its own order.
	var ta := a.turn
	var tb := o.turn
	var ha := a.half
	var hb := o.half
	var a0 := ta.x
	var a1 := ta.y
	var a2 := ta.z
	var b0 := tb.x
	var b1 := tb.y
	var b2 := tb.z
	if a.ex_step != stamp:
		a.own_extents(stamp)
	var d := a.p - o.p
	# m_ij: a's axis i on o's axis j (o.extent along a's axes, a's along o's).
	var m00 := absf(a0.dot(b0))
	var m01 := absf(a0.dot(b1))
	var m02 := absf(a0.dot(b2))
	var along0 := d.dot(a0)
	var over0 := a.ex0 + (hb.x * m00 + hb.y * m01 + hb.z * m02) - absf(along0)
	if over0 <= 0.0:
		return false
	var m10 := absf(a1.dot(b0))
	var m11 := absf(a1.dot(b1))
	var m12 := absf(a1.dot(b2))
	var along1 := d.dot(a1)
	var over1 := a.ex1 + (hb.x * m10 + hb.y * m11 + hb.z * m12) - absf(along1)
	if over1 <= 0.0:
		return false
	var m20 := absf(a2.dot(b0))
	var m21 := absf(a2.dot(b1))
	var m22 := absf(a2.dot(b2))
	var along2 := d.dot(a2)
	var over2 := a.ex2 + (hb.x * m20 + hb.y * m21 + hb.z * m22) - absf(along2)
	if over2 <= 0.0:
		return false
	if o.ex_step != stamp:
		o.own_extents(stamp)
	var along3 := d.dot(b0)
	var over3 := (ha.x * m00 + ha.y * m10 + ha.z * m20) + o.ex0 - absf(along3)
	if over3 <= 0.0:
		return false
	var along4 := d.dot(b1)
	var over4 := (ha.x * m01 + ha.y * m11 + ha.z * m21) + o.ex1 - absf(along4)
	if over4 <= 0.0:
		return false
	var along5 := d.dot(b2)
	var over5 := (ha.x * m02 + ha.y * m12 + ha.z * m22) + o.ex2 - absf(along5)
	if over5 <= 0.0:
		return false
	# a pushed out of o: a's axes first, then o's (as _least(a, o)).
	var best := over0
	var axis := a0
	var along := along0
	if over1 < best:
		best = over1
		axis = a1
		along = along1
	if over2 < best:
		best = over2
		axis = a2
		along = along2
	if over3 < best:
		best = over3
		axis = b0
		along = along3
	if over4 < best:
		best = over4
		axis = b1
		along = along4
	if over5 < best:
		best = over5
		axis = b2
		along = along5
	var least_a := (axis if along >= 0.0 else -axis) * best
	# o pushed out of a: o's axes first (as _least(o, a)), along the other way.
	best = over3
	axis = b0
	along = along3
	if over4 < best:
		best = over4
		axis = b1
		along = along4
	if over5 < best:
		best = over5
		axis = b2
		along = along5
	if over0 < best:
		best = over0
		axis = a0
		along = along0
	if over1 < best:
		best = over1
		axis = a1
		along = along1
	if over2 < best:
		best = over2
		axis = a2
		along = along2
	out[0] = least_a
	out[1] = (axis if -along >= 0.0 else -axis) * best
	return true
