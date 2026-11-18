## How a broken thing's skin comes apart (src/wreck_cuts.gd keeps the cuts,
## features/wreckage.gd throws them): seeded, irregular fractures, never the
## same twice in a row. Each cut is a `variant` of its thing: its own dice
## (`seed`) and its own fracture origin (`origin`, a spot on the thing where
## the pieces are smallest and most), so a pool of variants cut once gives a
## break that differs by where it was struck.
##
## By recipe (breakables.cfg `pieces`, the model's triangles in map axes):
##
##   boards:n   each side in n boards, each board snapped across at one or two
##              slanting breaks (more near the origin): crates, coolers, the
##              outhouse's walls and roof
##   staves:n   a barrel: n staves round its axis keeping their curve (some
##              snapped across on a slant), its heads split into disc pieces
##              by chords, its iron hoops as real rings sprung open or broken
##              into bent arcs, anything else on it in chunks
##   table:n    the top in n planks (snapped like boards), legs and benches
##   shatter:n  glass and clay: n shards, small and many near the origin
##   tear:n     tin: n torn sheets curled out from the inside and crumpled
##   burst:n    hay, stuffing: n solid clumps (thin flakes across its length)
##   splinter:n wood in splinters along its grain (its longest way)
##   chunk:n    n chunks (grid:a,b,c means chunk:a*b*c)
##
## Every piece keeps the model's own UVs on its skin. A cut face (the inside
## face set in by its thickness and the rim joining it to the skin) is drawn
## raw by wreck.gdshader: vertex COLOR alpha 0, COLOR red its material
## (MATERIALS), COLOR green 1 on a rim (fresh broken stuff) and 0 on the
## inside face (wood's back is weathered wood, the rest their raw body), UV
## the one spot of its own texture it takes its colour from (nothing is
## smeared across it) and UV2 where it is in the piece (metres,
## its grain along x), so wood shows end grain, tin a bright raw edge, clay
## its body, glass a glint, hay straw, a cooler its foam.
##
## Looks only and its own arithmetic: the same seed cuts the same pieces on
## any thread (no global dice).
class_name WreckFracture
extends RefCounted

## Raw materials (wreck.gdshader RAW_*): what breakables.cfg's `stuff` is cut as.
const MATERIALS := {
	"wood": 0,
	"tin": 1,
	"clay": 2,
	"glass": 3,
	"straw": 4,
	"plastic": 5,
	"iron": 6,
	"goo": 7,
	"stuffing": 8,
	"rubber": 9,
	"char": 10,
}
const STUFF := {
	"grey": "wood",
	"redtin": "tin",
	"orange": "tin",
	"pink": "plastic",
}
## How thick a piece of each is (its inside face set in by this, cells).
const THICK := {
	"wood": .03,
	"char": .03,
	"tin": .007,
	"clay": .016,
	"glass": .008,
	"plastic": .022,
	"goo": .03,
	"rubber": .006,
	"iron": .008,
}
## Solid stuff: a piece is a lump, its inside face set in this share of its
## narrowest half (hay, stuffing).
const SOLID := {"straw": .7, "stuffing": .7}
## A piece with less skin than this (its area) is dropped.
const SMALL := .002
const THIN := .012
## A barrel's hoops: where up its side (shares), how tall and thick (cells).
const HOOPS := [.2, .78]
const HOOP_TALL := .045
const HOOP_THICK := .009


## A piece made: its skin, its turn, what it is.
class Raw:
	var soup: WreckCuts.Soup
	var basis := Basis.IDENTITY
	var form := "chunk"
	## Ready made (a hoop): used as it is.
	var made: WreckCuts.Part = null


## The material a breakables.cfg `stuff` is cut as.
static func material_of(stuff: String) -> String:
	var name: String = STUFF.get(stuff, stuff)
	return name if MATERIALS.has(name) else "wood"


## Where variant k of a thing whose box is `box` breaks from: round its
## sides at a height that changes with k (the same for the same k).
static func origin(box: AABB, k: int) -> Vector3:
	var turn := TAU * float(k) / 6.0 + .37 * float(k / 6)
	var up: float = [.45, .72, .3, .6, .82, .38][k % 6]
	var mid := box.get_center()
	return Vector3(
		mid.x + cos(turn) * box.size.x * .5,
		mid.y + sin(turn) * box.size.y * .5,
		box.position.z + box.size.z * up
	)


## The pieces a recipe cuts `soup` into: variant `k` (its dice and origin).
static func cut(
	soup: WreckCuts.Soup, recipe: String, args: PackedFloat32Array, material: String, k: int
) -> Array:
	var box := soup.bounds()
	var dice := RandomNumberGenerator.new()
	dice.seed = hash(recipe) + 7919 * k + 104729 * int(box.size.length() * 1000.0)
	var at := origin(box, k)
	var raws: Array = []
	var all := PackedInt32Array()
	for t in soup.size() / 3:
		all.append(t)
	match recipe:
		"boards":
			_boards(soup, box, maxi(1, int(_arg(args, 0, 3.0))), at, dice, raws)
		"staves":
			_staves(soup, box, args, at, dice, raws)
		"table":
			_table(soup, box, maxi(1, int(_arg(args, 0, 4.0))), at, dice, raws)
		"shatter":
			_cells(
				soup,
				all,
				_sites(box, int(_arg(args, 0, 10.0)), at, .45, dice),
				Vector3.ONE,
				"shard",
				raws
			)
		"tear":
			var n := int(_arg(args, 0, 6.0))
			_cells(soup, all, _sites(box, n, at, .5, dice), Vector3.ONE, "sheet", raws)
			for raw: Raw in raws:
				_crumple(raw.soup, at, dice)
		"burst":
			# Hay comes away in flakes across its length: distances along it
			# count more (cells come out thin that way).
			var flakes := Vector3.ONE
			flakes[box.get_longest_axis_index()] = 2.5
			_cells(
				soup, all, _sites(box, int(_arg(args, 0, 8.0)), at, .3, dice), flakes, "clump", raws
			)
		"splinter":
			_cells(
				soup,
				all,
				_sites(box, int(_arg(args, 0, 8.0)), at, .4, dice),
				_grain(box),
				"board",
				raws
			)
		_:
			var n := int(_arg(args, 0, 2.0))
			if recipe == "grid":
				n = int(_arg(args, 0, 2.0) * _arg(args, 1, 2.0) * _arg(args, 2, 2.0))
			_cells(soup, all, _sites(box, n, at, .4, dice), Vector3.ONE, "chunk", raws)
	var out: Array = []
	for raw: Raw in raws:
		if raw.made != null:
			out.append(raw.made)
			continue
		if raw.soup.size() < 3 or WreckCuts.area(raw.soup) < SMALL:
			continue
		var turn := raw.basis
		if turn == Basis.IDENTITY:
			turn = fit(raw.soup)
		out.append(finish(raw.soup, turn, material, raw.form))
	return out


static func _arg(args: PackedFloat32Array, i: int, fallback: float) -> float:
	return args[i] if i < args.size() else fallback


## A box's grain for wood split along its longest way: distances along it
## count a third (cells come out long that way).
static func _grain(box: AABB) -> Vector3:
	var s := Vector3.ONE
	s[box.get_longest_axis_index()] = .33
	return s


## n seeds in the box: `near` of them about the origin (small pieces there),
## the rest anywhere.
static func _sites(
	box: AABB, n: int, at: Vector3, near: float, dice: RandomNumberGenerator
) -> PackedVector3Array:
	var out := PackedVector3Array()
	var count := maxi(2, n)
	var close := int(count * near)
	var reach := box.size * .3
	for i in count:
		if i < close:
			var spread := reach * (.25 + .75 * float(i) / maxf(1.0, close))
			out.append(
				(
					at
					+ Vector3(
						dice.randf_range(-1, 1) * spread.x,
						dice.randf_range(-1, 1) * spread.y,
						dice.randf_range(-1, 1) * spread.z
					)
				)
			)
		else:
			out.append(
				(
					box.position
					+ Vector3(
						dice.randf() * box.size.x,
						dice.randf() * box.size.y,
						dice.randf() * box.size.z
					)
				)
			)
	return out


# ------------------------------------------------------------------ cutting


## The triangles `tris` of `soup` shared out to the nearest of `sites` (in
## distances stretched by `scale`), each cut where it crosses: one Raw a site.
## A triangle whose corners, middle and edges' middles share one nearest seed
## lies wholly in that seed's cell (a cell is convex); the rest are cut by the
## few seeds they touch only.
static func _cells(
	soup: WreckCuts.Soup,
	tris: PackedInt32Array,
	sites: PackedVector3Array,
	scale: Vector3,
	form: String,
	raws: Array
) -> void:
	var made: Array = []
	for i in sites.size():
		made.append(WreckCuts.Soup.new())
	var s2 := scale * scale
	for t in tris:
		var a := soup.p[t * 3]
		var b := soup.p[t * 3 + 1]
		var c := soup.p[t * 3 + 2]
		var near: Array[int] = []
		for q: Vector3 in [a, b, c, (a + b + c) / 3.0, (a + b) * .5, (b + c) * .5, (c + a) * .5]:
			var best := 0
			var bd := INF
			for i in sites.size():
				var d := (q - sites[i]) * scale
				var dd := d.length_squared()
				if dd < bd:
					bd = dd
					best = i
			if not near.has(best):
				near.append(best)
		if near.size() == 1:
			var whole: WreckCuts.Soup = made[near[0]]
			for k in 3:
				whole.add(soup, t * 3 + k)
			continue
		for i: int in near:
			var poly := WreckCuts.Soup.new()
			for k in 3:
				poly.add(soup, t * 3 + k)
			var si := sites[i]
			for j: int in near:
				if j == i:
					continue
				var sj := sites[j]
				var n := s2 * (sj - si)
				var d := ((sj * scale).length_squared() - (si * scale).length_squared()) * .5
				poly = WreckCuts.clip(poly, n, d)
				if poly.size() < 3:
					break
			var into: WreckCuts.Soup = made[i]
			_fan(poly, into)
	for i in made.size():
		var raw := Raw.new()
		raw.soup = made[i]
		raw.form = form
		raws.append(raw)


## A polygon's triangles (a fan from its first corner) added to `into`.
static func _fan(poly: WreckCuts.Soup, into: WreckCuts.Soup) -> void:
	if poly.size() < 3:
		return
	for k in range(1, poly.size() - 1):
		into.add(poly, 0)
		into.add(poly, k)
		into.add(poly, k + 1)


## A soup split by a plane: [where n.p <= d, the rest].
static func split(soup: WreckCuts.Soup, n: Vector3, d: float) -> Array:
	var inside := WreckCuts.Soup.new()
	var outside := WreckCuts.Soup.new()
	for t in soup.size() / 3:
		var da := n.dot(soup.p[t * 3]) - d
		var db := n.dot(soup.p[t * 3 + 1]) - d
		var dc := n.dot(soup.p[t * 3 + 2]) - d
		if da <= 0.0 and db <= 0.0 and dc <= 0.0:
			for k in 3:
				inside.add(soup, t * 3 + k)
			continue
		if da >= 0.0 and db >= 0.0 and dc >= 0.0:
			for k in 3:
				outside.add(soup, t * 3 + k)
			continue
		var poly := WreckCuts.Soup.new()
		for k in 3:
			poly.add(soup, t * 3 + k)
		_fan(WreckCuts.clip(poly, n, d), inside)
		_fan(WreckCuts.clip(poly, -n, -d), outside)
	return [inside, outside]


## The triangles of `soup` (of `tris`) in a cell of planes ([n, d]: n.p <= d).
static func _keep(soup: WreckCuts.Soup, tris: PackedInt32Array, planes: Array) -> WreckCuts.Soup:
	var out := WreckCuts.Soup.new()
	for t in tris:
		var poly := WreckCuts.Soup.new()
		for k in 3:
			poly.add(soup, t * 3 + k)
		var whole := true
		for plane: Array in planes:
			var pn: Vector3 = plane[0]
			var pd: float = plane[1]
			var outside := 0
			var inside := 0
			for q: Vector3 in poly.p:
				if pn.dot(q) > pd:
					outside += 1
				else:
					inside += 1
			if inside == 0:
				poly = WreckCuts.Soup.new()
				break
			if outside == 0:
				continue
			whole = false
			poly = WreckCuts.clip(poly, pn, pd)
		if poly.size() < 3:
			continue
		if whole:
			for k in 3:
				out.add(poly, k)
		else:
			_fan(poly, out)
	return out


## A piece snapped across `along` at 0 to `most` slanting breaks: more the
## nearer its middle is to the origin. Each break leans up to `lean` radians
## off square, toward `side`.
static func _snap(
	soup: WreckCuts.Soup,
	along: Vector3,
	side: Vector3,
	at: Vector3,
	most: int,
	lean: float,
	dice: RandomNumberGenerator
) -> Array:
	var box := soup.bounds()
	var mid := box.get_center()
	var reach := maxf(.01, box.size.length())
	var near := clampf(1.0 - mid.distance_to(at) / maxf(.3, reach * 1.2), 0.0, 1.0)
	var count := 0
	for k in most:
		if dice.randf() < .1 + .7 * near:
			count += 1
	if count == 0:
		return [soup]
	var lo := INF
	var hi := -INF
	for q: Vector3 in soup.p:
		lo = minf(lo, q.dot(along))
		hi = maxf(hi, q.dot(along))
	var length := hi - lo
	if length < .12:
		return [soup]
	var cuts: Array[float] = []
	for k in count:
		cuts.append(lerpf(lo, hi, (float(k) + dice.randf_range(.35, .9)) / (count + .2)))
	var out: Array = []
	var rest := soup
	for v: float in cuts:
		var tilt := dice.randf_range(.35, 1.0) * lean * (1.0 if dice.randf() < .5 else -1.0)
		var n := (along * cos(tilt) + side * sin(tilt)).normalized()
		var through := along * v + mid - along * along.dot(mid)
		var parts := split(rest, n, n.dot(through))
		out.append(parts[0])
		rest = parts[1]
	out.append(rest)
	return out


# ------------------------------------------------------------------ recipes


## Each side of a box-like model in n boards (walls across their height, the
## top and bottom along their longer way), each snapped near the origin.
static func _boards(
	soup: WreckCuts.Soup, box: AABB, n: int, at: Vector3, dice: RandomNumberGenerator, raws: Array
) -> void:
	var lo := box.position
	var hi := box.end
	var sides: Array = []
	for k in 6:
		sides.append(PackedInt32Array())
	for t in soup.size() / 3:
		var c := (soup.p[t * 3] + soup.p[t * 3 + 1] + soup.p[t * 3 + 2]) / 3.0
		var near := [c.x - lo.x, hi.x - c.x, c.y - lo.y, hi.y - c.y, c.z - lo.z, hi.z - c.z]
		var best := 0
		for k in 6:
			var d: float = near[k]
			var was: float = near[best]
			if d < was:
				best = k
		var list: PackedInt32Array = sides[best]
		list.append(t)
		sides[best] = list
	for side in 6:
		var axis := 2
		var flat := side >= 4
		if flat:
			axis = 0 if box.size.x >= box.size.y else 1
		var facing := Vector3.ZERO
		facing[side / 2] = -1.0 if side % 2 == 0 else 1.0
		# Along the board: across the side, square to its stacking axis.
		var along := Vector3.ZERO
		if flat:
			along[1 - axis] = 1.0
		else:
			along[1 if side / 2 == 0 else 0] = 1.0
		var tris: PackedInt32Array = sides[side]
		if tris.is_empty():
			continue
		# Boards a little uneven in width.
		var edges: Array[float] = [0.0]
		for k in range(1, n):
			edges.append((float(k) + dice.randf_range(-.18, .18)) / n)
		edges.append(1.0)
		for k in n:
			var a := lo[axis] + box.size[axis] * edges[k] - (1.0 if k == 0 else 0.0)
			var b := lo[axis] + box.size[axis] * edges[k + 1] + (1.0 if k == n - 1 else 0.0)
			var slab := _keep(soup, tris, WreckCuts.slab(axis, a, b))
			if slab.size() < 3:
				continue
			var across := Vector3.ZERO
			across[axis] = 1.0
			for piece: WreckCuts.Soup in _snap(slab, along, across, at, 2, .7, dice):
				var raw := Raw.new()
				raw.soup = piece
				raw.form = "board"
				raw.basis = frame(along, facing)
				raws.append(raw)


## A frame with x along `along` and y along `facing` (z the third way).
static func frame(along: Vector3, facing: Vector3) -> Basis:
	var x := along.normalized()
	var y := (facing - x * x.dot(facing)).normalized()
	if y.length() < .5:
		y = Vector3(0, 0, 1).cross(x).normalized()
	return Basis(x, y, x.cross(y))


## A barrel: staves round its axis (snapped across near the origin), its
## heads split by chords, its hoops as iron rings, the rest in chunks.
static func _staves(
	soup: WreckCuts.Soup,
	box: AABB,
	args: PackedFloat32Array,
	at: Vector3,
	dice: RandomNumberGenerator,
	raws: Array
) -> void:
	var n := maxi(3, int(_arg(args, 0, 8.0)))
	var mid := box.get_center()
	var axis := Vector2(_arg(args, 1, mid.x), _arg(args, 2, mid.y))
	var radius := _arg(args, 3, minf(box.size.x, box.size.y) * .5)
	var low := INF
	var high := -INF
	for t in soup.size() / 3:
		var c := (soup.p[t * 3] + soup.p[t * 3 + 1] + soup.p[t * 3 + 2]) / 3.0
		var off := Vector2(c.x, c.y).distance_to(axis)
		var nz := absf((soup.n[t * 3] + soup.n[t * 3 + 1] + soup.n[t * 3 + 2]).normalized().z)
		# The side's own reach up (not a paddle standing in it).
		if off <= radius * 1.15 and (off >= radius * .72 or nz > .7):
			for k in 3:
				low = minf(low, soup.p[t * 3 + k].z)
				high = maxf(high, soup.p[t * 3 + k].z)
	if low > high:
		var all := PackedInt32Array()
		for t in soup.size() / 3:
			all.append(t)
		_cells(soup, all, _sites(box, 6, at, .4, dice), Vector3.ONE, "chunk", raws)
		return
	var tall := high - low
	var side := PackedInt32Array()
	var tops := [PackedInt32Array(), PackedInt32Array()]
	var others := PackedInt32Array()
	for t in soup.size() / 3:
		var c := (soup.p[t * 3] + soup.p[t * 3 + 1] + soup.p[t * 3 + 2]) / 3.0
		var nz := absf((soup.n[t * 3] + soup.n[t * 3 + 1] + soup.n[t * 3 + 2]).normalized().z)
		var off := Vector2(c.x, c.y).distance_to(axis)
		if off > radius * 1.15 or c.z > high + .02:
			others.append(t)
		elif nz <= .7 and off < radius * .72:
			# Inside the barrel (its mash, a paddle in it): not its side, and
			# not thrown (mash is mush; the remains show its puddle).
			continue
		elif nz > .7 and c.z > high - tall * .12:
			var top: PackedInt32Array = tops[0]
			top.append(t)
			tops[0] = top
		elif nz > .7 and c.z < low + tall * .12:
			var bottom: PackedInt32Array = tops[1]
			bottom.append(t)
			tops[1] = bottom
		else:
			side.append(t)
	var centre := Vector3(axis.x, axis.y, 0.0)
	var start := dice.randf() * TAU
	var turns: Array[float] = []
	for k in n + 1:
		var jitter := dice.randf_range(-.2, .2) if k > 0 and k < n else 0.0
		turns.append(start + TAU * (float(k) + jitter) / n)
	for k in n:
		var a0 := turns[k]
		var a1 := turns[k + 1]
		var d0 := Vector3(cos(a0), sin(a0), 0.0)
		var d1 := Vector3(cos(a1), sin(a1), 0.0)
		var n0 := Vector3(d0.y, -d0.x, 0.0)
		var n1 := Vector3(-d1.y, d1.x, 0.0)
		var stave := _keep(soup, side, [[n0, n0.dot(centre)], [n1, n1.dot(centre)]])
		if stave.size() < 3:
			continue
		var am := (a0 + a1) * .5
		var out := Vector3(cos(am), sin(am), 0.0)
		var tangent := Vector3(-sin(am), cos(am), 0.0)
		for piece: WreckCuts.Soup in _snap(stave, Vector3(0, 0, 1), tangent, at, 2, .9, dice):
			var raw := Raw.new()
			raw.soup = piece
			raw.form = "stave"
			raw.basis = Basis(-tangent, out, Vector3(0, 0, 1))
			raws.append(raw)
	# The heads: one to three chords across each.
	for h in 2:
		var tris: PackedInt32Array = tops[h]
		if tris.is_empty():
			continue
		var head := _keep(soup, tris, [])
		var pieces: Array = [head]
		var chords := 1 + (1 if dice.randf() < .6 else 0)
		var way := dice.randf() * TAU
		for c in chords:
			var dir := Vector3(cos(way), sin(way), 0.0)
			var off := centre + dir * radius * dice.randf_range(-.35, .35)
			var next: Array = []
			for piece: WreckCuts.Soup in pieces:
				for half: WreckCuts.Soup in split(piece, dir, dir.dot(off)):
					if half.size() >= 3:
						next.append(half)
			pieces = next
			way += PI * .5 + dice.randf_range(-.5, .5)
		for piece: WreckCuts.Soup in pieces:
			var raw := Raw.new()
			raw.soup = piece
			raw.form = "disc"
			raws.append(raw)
	for k in HOOPS.size():
		var share: float = HOOPS[k]
		var z := low + tall * share
		var r := _radius_at(soup, side, axis, z, radius)
		for part: WreckCuts.Part in hoop(Vector3(axis.x, axis.y, z), r, tall * HOOP_TALL, dice):
			var raw := Raw.new()
			raw.made = part
			raws.append(raw)
	if not others.is_empty():
		var rest := soup.bounds()
		_cells(soup, others, _sites(rest, 3, at, .3, dice), Vector3.ONE, "chunk", raws)


## How far a barrel's side reaches out from its axis at height z.
static func _radius_at(
	soup: WreckCuts.Soup, side: PackedInt32Array, axis: Vector2, z: float, fallback: float
) -> float:
	var best := 0.0
	for t in side:
		for k in 3:
			var q := soup.p[t * 3 + k]
			if absf(q.z - z) < .08:
				best = maxf(best, Vector2(q.x, q.y).distance_to(axis))
	return clampf(best * 1.025, fallback * .9, fallback * 1.08) if best > 0.0 else fallback


## A table: the top in n planks along its longer way (snapped near the
## origin), what is below it in chunks.
static func _table(
	soup: WreckCuts.Soup, box: AABB, n: int, at: Vector3, dice: RandomNumberGenerator, raws: Array
) -> void:
	var top := box.end.z - maxf(.08, box.size.z * .12)
	var upper := PackedInt32Array()
	var lower := PackedInt32Array()
	for t in soup.size() / 3:
		var c := (soup.p[t * 3] + soup.p[t * 3 + 1] + soup.p[t * 3 + 2]) / 3.0
		if c.z > top:
			upper.append(t)
		else:
			lower.append(t)
	# The top's own bounds (the benches reach wider than it).
	var deck := box
	if not upper.is_empty():
		deck = AABB(soup.p[upper[0] * 3], Vector3.ZERO)
		for t in upper:
			for k in 3:
				deck = deck.expand(soup.p[t * 3 + k])
	var axis := 0 if deck.size.x >= deck.size.y else 1
	var across := 1 - axis
	var along := Vector3.ZERO
	along[axis] = 1.0
	var side := Vector3.ZERO
	side[across] = 1.0
	for k in n:
		var a := deck.position[across] + deck.size[across] * k / n - (1.0 if k == 0 else 0.0)
		var b := (
			deck.position[across] + deck.size[across] * (k + 1) / n + (1.0 if k == n - 1 else 0.0)
		)
		var plank := _keep(soup, upper, WreckCuts.slab(across, a, b))
		if plank.size() < 3:
			continue
		for piece: WreckCuts.Soup in _snap(plank, along, side, at, 1, .6, dice):
			var raw := Raw.new()
			raw.soup = piece
			raw.form = "board"
			raw.basis = frame(along, Vector3(0, 0, 1))
			raws.append(raw)
	var low := AABB(box.position, Vector3(box.size.x, box.size.y, top - box.position.z))
	_cells(soup, lower, _sites(low, 5, at, .2, dice), _grain(low), "board", raws)


## Torn tin: each sheet's edges curled out from the inside (the farther from
## its middle, the more) and dented.
static func _crumple(soup: WreckCuts.Soup, at: Vector3, dice: RandomNumberGenerator) -> void:
	if soup.size() < 3:
		return
	var box := soup.bounds()
	var mid := box.get_center()
	var reach := maxf(.02, box.size.length() * .5)
	var curl := dice.randf_range(.18, .4)
	var dent := reach * dice.randf_range(.04, .09)
	var phase := Vector3(dice.randf() * 9.0, dice.randf() * 9.0, dice.randf() * 9.0)
	var near := clampf(1.0 - mid.distance_to(at) / maxf(.3, reach * 3.0), .3, 1.0)
	for i in soup.size():
		var q := soup.p[i]
		var f := minf(q.distance_to(mid) / reach, 1.4)
		var wave := (
			sin(q.x * 23.0 + phase.x) * sin(q.y * 19.0 + phase.y) * sin(q.z * 21.0 + phase.z)
		)
		soup.p[i] = q + soup.n[i] * (curl * near * f * f * reach + wave * dent)


## A barrel hoop round (c) of radius r and height `tall`: sprung open at a
## gap, or broken into two or three bent arcs. Iron all through (drawn raw).
static func hoop(c: Vector3, r: float, tall: float, dice: RandomNumberGenerator) -> Array:
	var out: Array = []
	var roll := dice.randf()
	var count := 1 if roll < .45 else (2 if roll < .85 else 3)
	var start := dice.randf() * TAU
	var gap := dice.randf_range(.25, .6)
	var span := (TAU - gap * count) / count
	for k in count:
		var a0 := start + k * (span + gap)
		out.append(_arc(c, r, tall, a0, a0 + span, dice))
	return out


## One bent arc of hoop iron from turn a0 to a1: its ends sprung out and
## up a little, a strip `tall` high and HOOP_THICK through.
static func _arc(
	c: Vector3, r: float, tall: float, a0: float, a1: float, dice: RandomNumberGenerator
) -> WreckCuts.Part:
	var soup := WreckCuts.Soup.new()
	var segs := maxi(3, int((a1 - a0) / .26))
	var spring := dice.randf_range(.08, .3)
	var lift := dice.randf_range(-.6, .6) * tall
	var t := HOOP_THICK
	var rows: Array = []
	for i in segs + 1:
		var s := float(i) / segs
		var a := lerpf(a0, a1, s)
		var bend := (s - .5) * (s - .5) * 4.0
		var rr := r * (1.0 + spring * bend)
		var dir := Vector3(cos(a), sin(a), 0.0)
		var z := c.z + lift * bend * (1.0 if s > .5 else -.4)
		var base := Vector3(c.x, c.y, z) + dir * rr
		rows.append([base, dir])
	for i in segs:
		var r0: Array = rows[i]
		var r1: Array = rows[i + 1]
		var p0: Vector3 = r0[0]
		var p1: Vector3 = r1[0]
		var o0: Vector3 = r0[1]
		var o1: Vector3 = r1[1]
		var up := Vector3(0, 0, tall * .5)
		# Outside, inside, top, bottom.
		_quad(soup, p0 - up, p1 - up, p1 + up, p0 + up, (o0 + o1).normalized())
		_quad(
			soup,
			p1 - up - o1 * t,
			p0 - up - o0 * t,
			p0 + up - o0 * t,
			p1 + up - o1 * t,
			-(o0 + o1).normalized()
		)
		_quad(soup, p0 + up, p1 + up, p1 + up - o1 * t, p0 + up - o0 * t, Vector3(0, 0, 1))
		_quad(soup, p1 - up, p0 - up, p0 - up - o0 * t, p1 - up - o1 * t, Vector3(0, 0, -1))
	var part := _framed(soup, Basis.IDENTITY)
	part.material = "iron"
	part.form = "ring"
	var raw := Color(float(MATERIALS["iron"]) / 16.0, 0.0, 0.0, 0.0)
	for i in part.verts.size():
		part.colors.append(raw)
		part.uv2s.append(Vector2(part.verts[i].x + part.verts[i].y, part.verts[i].z))
	return part


static func _quad(
	soup: WreckCuts.Soup, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3
) -> void:
	for q: Vector3 in [a, b, c, a, c, d]:
		soup.p.append(q)
		soup.n.append(n)
		soup.uv.append(Vector2.ZERO)


# ------------------------------------------------------------------ finishing


## A frame fitted to a piece (its corners' spread): x along its longest way,
## y through its thinnest (a shard's face, a sheet's), so its box is tight
## and a shard lies on its face. Power steps on the spread, its own sums.
static func fit(soup: WreckCuts.Soup) -> Basis:
	var n := soup.size()
	if n < 3:
		return Basis.IDENTITY
	var mid := Vector3.ZERO
	for q: Vector3 in soup.p:
		mid += q
	mid /= n
	var xx := 0.0
	var xy := 0.0
	var xz := 0.0
	var yy := 0.0
	var yz := 0.0
	var zz := 0.0
	for q: Vector3 in soup.p:
		var d := q - mid
		xx += d.x * d.x
		xy += d.x * d.y
		xz += d.x * d.z
		yy += d.y * d.y
		yz += d.y * d.z
		zz += d.z * d.z
	var spread := Basis(Vector3(xx, xy, xz), Vector3(xy, yy, yz), Vector3(xz, yz, zz))
	var long := _power(spread, Vector3(1.0, .31, .17))
	if long == Vector3.ZERO:
		return Basis.IDENTITY
	var lam := long.dot(spread * long)
	var rest := spread
	rest.x -= long * long.x * lam
	rest.y -= long * long.y * lam
	rest.z -= long * long.z * lam
	var start := long.cross(Vector3(0, 0, 1))
	if start.length() < .1:
		start = long.cross(Vector3(1, 0, 0))
	var wide := _power(rest, start.normalized())
	wide = (wide - long * long.dot(wide)).normalized()
	if wide.length() < .5:
		wide = start.normalized()
	var thin := long.cross(wide).normalized()
	return Basis(long, thin, long.cross(thin))


static func _power(m: Basis, start: Vector3) -> Vector3:
	var v := start
	for k in 14:
		var next := m * v
		var size := next.length()
		if size < 1e-9:
			return Vector3.ZERO
		v = next / size
	return v


## A Part from a piece's skin: its frame (`basis`, its box tight in it), its
## inside face set in by its material's thickness and the rim joining the
## two along every cut edge, both drawn raw.
static func finish(
	skin: WreckCuts.Soup, basis: Basis, material: String, form: String
) -> WreckCuts.Part:
	var faces := WreckCuts.Soup.new()
	for i in skin.size():
		faces.add(skin, i)
	var box := skin.bounds()
	var thick: float = THICK.get(material, .025)
	if SOLID.has(material):
		var least := minf(box.size.x, minf(box.size.y, box.size.z))
		var share: float = SOLID[material]
		thick = maxf(thick, least * .5 * share)
	thick = minf(thick, maxf(THIN, box.size.length() * .3))
	# Its colour's one spot: the middle of its biggest triangle.
	var spot := Vector2.ZERO
	var most := -1.0
	for t in skin.size() / 3:
		var a := skin.p[t * 3]
		var area := (skin.p[t * 3 + 1] - a).cross(skin.p[t * 3 + 2] - a).length()
		if area > most:
			most = area
			spot = (skin.uv[t * 3] + skin.uv[t * 3 + 1] + skin.uv[t * 3 + 2]) / 3.0
	var mid := box.get_center()
	var skin_count := faces.size()
	# The inside face.
	for i in skin.size():
		var into := -skin.n[i]
		if SOLID.has(material):
			into = (mid - skin.p[i]).normalized() * .5 + into * .5
		faces.p.append(skin.p[i] + into * thick)
		faces.n.append(-skin.n[i])
		faces.uv.append(spot)
	# The rims: every edge of the skin no other triangle shares.
	var codes := PackedInt64Array()
	codes.resize(skin.size())
	for i in skin.size():
		codes[i] = _corner_code(skin.p[i])
	var seen := {}
	for t in skin.size() / 3:
		for k in 3:
			var key := _edge_key(codes[t * 3 + k], codes[t * 3 + (k + 1) % 3])
			seen[key] = 1 if not seen.has(key) else 2
	for t in skin.size() / 3:
		for k in 3:
			var ia := t * 3 + k
			var ib := t * 3 + (k + 1) % 3
			var uses: int = seen[_edge_key(codes[ia], codes[ib])]
			if uses != 1:
				continue
			var a := skin.p[ia]
			var b := skin.p[ib]
			var a_in := faces.p[skin_count + ia]
			var b_in := faces.p[skin_count + ib]
			var n := (b - a).cross(skin.n[ia] + skin.n[ib])
			if n.length() < 1e-6:
				continue
			n = n.normalized()
			if n.dot((a + b) * .5 - mid) < 0.0:
				n = -n
			for q: Vector3 in [a, b, b_in, a, b_in, a_in]:
				faces.p.append(q)
				faces.n.append(n)
				faces.uv.append(spot)
	var part := _framed(faces, basis)
	part.material = material
	part.form = form
	var index: int = MATERIALS.get(material, 0)
	var inside := Color(float(index) / 16.0, 0.0, 0.0, 0.0)
	var rim := Color(float(index) / 16.0, 1.0, 0.0, 0.0)
	for i in part.verts.size():
		if i < skin_count:
			part.colors.append(Color(1, 1, 1, 1))
			part.uv2s.append(Vector2.ZERO)
		else:
			var l := part.verts[i]
			part.colors.append(inside if i < skin_count * 2 else rim)
			part.uv2s.append(Vector2(l.x, l.y * .7 + l.z))
	return part


## A corner's code (snapped to a tenth of a mm, hashed: two corners that
## share one are the same corner, near enough for looks).
static func _corner_code(a: Vector3) -> int:
	return (
		(roundi(a.x * 1e4) * 73856093)
		^ (roundi(a.y * 1e4) * 19349663)
		^ (roundi(a.z * 1e4) * 83492791)
	)


## An edge's key from its corners' codes, whichever way round.
static func _edge_key(a: int, b: int) -> int:
	return mini(a, b) * 1000003 + maxi(a, b)


## A Part of these faces in frame `basis`: its box tight in that frame.
static func _framed(faces: WreckCuts.Soup, basis: Basis) -> WreckCuts.Part:
	var part := WreckCuts.Part.new()
	part.basis = basis
	var inverse := basis.transposed()
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for q: Vector3 in faces.p:
		var l := inverse * q
		lo = Vector3(minf(lo.x, l.x), minf(lo.y, l.y), minf(lo.z, l.z))
		hi = Vector3(maxf(hi.x, l.x), maxf(hi.y, l.y), maxf(hi.z, l.z))
	var mid_local := (lo + hi) * .5
	part.centre = basis * mid_local
	var half := (hi - lo) * .5
	part.half = Vector3(maxf(half.x, THIN), maxf(half.y, THIN), maxf(half.z, THIN))
	part.verts.resize(faces.size())
	part.normals.resize(faces.size())
	part.shown.resize(faces.size())
	part.shown_n.resize(faces.size())
	for i in faces.size():
		var v := inverse * faces.p[i] - mid_local
		var n := inverse * faces.n[i]
		part.verts[i] = v
		part.normals[i] = n
		part.shown[i] = Vector3(v.x, v.z, v.y)
		part.shown_n[i] = Vector3(n.x, n.z, n.y)
	part.uvs = faces.uv.duplicate()
	return part
