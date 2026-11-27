## The nav graph's walks over a flat copy of what they read (pass 16): the
## level's grid, its furniture and its geometry's pieces as packed arrays,
## the cells' lists of pieces as index runs. LevelNav.build_nav asks this
## the questions LevelGeometry's queries answer (floor_at, static_blocked,
## ceiling_at, the roof), with the same sums in the same order, so the same
## answers, without a typed object or a method call a step; and each worker
## thread gets a copy of its own (copy()), so the threads share nothing they
## write or count. Reading only; built once a graph.
class_name NavWalk
extends RefCounted

const STEP := LevelGeometry.STEP
const BODY := LevelGeometry.BODY
const CROUCH := LevelGeometry.CROUCH
const NAV_STEPS := LevelGeometry.NAV_STEPS
const R := LevelGeometry.NAV_BODY

var w := 0
var h := 0
## The grid: ground, roof, 1 where the grid lets a body's corner in (open, or
## a door's cell), the cells furniture or a door is listed near.
var ground := PackedFloat32Array()
var roof := PackedFloat32Array()
var open := PackedByteArray()
var furniture := PackedByteArray()
## near_fixtures as runs: cell c's are fixture numbers fix_list[fix_first[c]
## .. fix_first[c + 1]], each fix[8 k .. 8 k + 8] (LevelData's fixture row).
var fix_first := PackedInt32Array()
var fix_list := PackedInt32Array()
var fix := PackedFloat64Array()
## The nodes (the graph's).
var cell := PackedInt32Array()
var z := PackedFloat32Array()
## Slabs: box (x0, y0, x1, y1), top, slope, thickness (< 0 solid), walkable,
## cut lines cuts[cut_first[i] .. cut_first[i + 1]] as (nx, ny, c) triples.
var s_box := PackedFloat64Array()
var s_top := PackedFloat64Array()
var s_gx := PackedFloat64Array()
var s_gy := PackedFloat64Array()
var s_thick := PackedFloat64Array()
var s_walk := PackedByteArray()
var s_low := PackedFloat64Array()
var s_high := PackedFloat64Array()
var s_cut_first := PackedInt32Array()
var s_cuts := PackedFloat64Array()
## Segments: ends (ax, ay, bx, by), foot, tops at a and b, half thickness.
var g_ends := PackedFloat64Array()
var g_z0 := PackedFloat64Array()
var g_z1 := PackedFloat64Array()
var g_z1b := PackedFloat64Array()
var g_half := PackedFloat64Array()
## Ceilings: box, height, cut lines as the slabs'.
var c_box := PackedFloat64Array()
var c_z := PackedFloat64Array()
var c_cut_first := PackedInt32Array()
var c_cuts := PackedFloat64Array()
## The geometry's cell lists (LevelGeometry._index, _over) as runs: a slab i
## is i, a segment (index) or a ceiling (over) j is -1 - j. A cell the
## geometry does not mark has none.
var idx_first := PackedInt32Array()
var idx_list := PackedInt32Array()
var over_first := PackedInt32Array()
var over_list := PackedInt32Array()
## The graph's deck nodes over each cell (NavGraph.over) as runs.
var deck_first := PackedInt32Array()
var deck_list := PackedInt32Array()
## walks_both()'s points, what was asked at each (kept to save making it).
var _asked := PackedFloat64Array()


## The flat copy of `lv` and its geometry for graph g (its nodes set), or null
## when it cannot stand in for the queries (a body wider than the furniture
## index's reach: they read every collision volume then).
static func make(geo: LevelGeometry, lv: LevelData, g: LevelGeometry.NavGraph) -> NavWalk:
	if R > lv.index_radius or lv.furniture_cells.size() != lv.width * lv.height:
		return null
	var f := NavWalk.new()
	f.w = geo.width
	f.h = geo.height
	var n := f.w * f.h
	f.ground = lv.ground.duplicate()
	f.roof = lv.roof.duplicate()
	f.open.resize(n)
	for c in n:
		f.open[c] = 1 if lv.solid[c] < 0 or lv.door_cells.has(c) else 0
	f.furniture = lv.furniture_cells.duplicate()
	var numbers := {}
	f.fix_first.resize(n + 1)
	for c in n:
		f.fix_first[c] = f.fix_list.size()
		if f.furniture[c] == 0:
			continue
		for fixture: Variant in lv.near_fixtures.get(
			Vector2i(c % f.w, c / f.w), LevelGeometry.NOTHING
		):
			var row: PackedFloat32Array = fixture
			if not numbers.has(row):
				numbers[row] = f.fix.size() / 8
				for k in 8:
					f.fix.append(row[k])
			var number: int = numbers[row]
			f.fix_list.append(number)
	f.fix_first[n] = f.fix_list.size()
	f.cell = g.cell
	f.z = g.z
	var slab_no := {}
	for s in geo.slabs:
		slab_no[s] = slab_no.size()
		f.s_box.append_array(PackedFloat64Array([s.x0, s.y0, s.x1, s.y1]))
		f.s_top.append(s.top)
		f.s_gx.append(s.gx)
		f.s_gy.append(s.gy)
		f.s_thick.append(s.thick)
		f.s_walk.append(1 if s.walk else 0)
		f.s_low.append(s.top_min())
		f.s_high.append(s.top_max())
		f.s_cut_first.append(f.s_cuts.size())
		for v in s.cuts:
			f.s_cuts.append(v)
	f.s_cut_first.append(f.s_cuts.size())
	var seg_no := {}
	for seg in geo.segments:
		seg_no[seg] = seg_no.size()
		f.g_ends.append_array(PackedFloat64Array([seg.ax, seg.ay, seg.bx, seg.by]))
		f.g_z0.append(seg.z0)
		f.g_z1.append(seg.z1)
		f.g_z1b.append(seg.z1b)
		f.g_half.append(seg.half)
	var ceiling_no := {}
	for ce in geo.ceilings:
		ceiling_no[ce] = ceiling_no.size()
		f.c_box.append_array(PackedFloat64Array([ce.x0, ce.y0, ce.x1, ce.y1]))
		f.c_z.append(ce.z)
		f.c_cut_first.append(f.c_cuts.size())
		for v in ce.cuts:
			f.c_cuts.append(v)
	f.c_cut_first.append(f.c_cuts.size())
	f.idx_first.resize(n + 1)
	f.over_first.resize(n + 1)
	for c in n:
		f.idx_first[c] = f.idx_list.size()
		f.over_first[c] = f.over_list.size()
		if geo.cells[c] == 0:
			continue
		for item: Variant in geo._index.get(c, LevelGeometry.NOTHING):
			var number: int = slab_no[item] if item is LevelGeometry.Slab else -1 - seg_no[item]
			f.idx_list.append(number)
		for item: Variant in geo._over.get(c, LevelGeometry.NOTHING):
			var number: int = slab_no[item] if item is LevelGeometry.Slab else -1 - ceiling_no[item]
			f.over_list.append(number)
	f.idx_first[n] = f.idx_list.size()
	f.over_first[n] = f.over_list.size()
	f.deck_first.resize(n + 1)
	for c in n:
		f.deck_first[c] = f.deck_list.size()
		var decks: Variant = g.over.get(c)
		if decks != null:
			for m: int in decks:
				f.deck_list.append(m)
	f.deck_first[n] = f.deck_list.size()
	return f


## A copy of its own for a worker thread (every array copied).
func copy() -> NavWalk:
	var f := NavWalk.new()
	for p: Dictionary in get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var name: String = p["name"]
			var v: Variant = get(name)
			if v is PackedFloat64Array:
				var a: PackedFloat64Array = v
				f.set(name, a.duplicate())
			elif v is PackedFloat32Array:
				var a: PackedFloat32Array = v
				f.set(name, a.duplicate())
			elif v is PackedInt32Array:
				var a: PackedInt32Array = v
				f.set(name, a.duplicate())
			elif v is PackedByteArray:
				var a: PackedByteArray = v
				f.set(name, a.duplicate())
			else:
				f.set(name, v)
	return f


# ------------------------------------------------------------ the pieces


func _s_inside(i: int, x: float, y: float) -> bool:
	var o := i * 4
	if x < s_box[o] or x > s_box[o + 2] or y < s_box[o + 1] or y > s_box[o + 3]:
		return false
	for k in range(s_cut_first[i], s_cut_first[i + 1], 3):
		if s_cuts[k] * x + s_cuts[k + 1] * y > s_cuts[k + 2]:
			return false
	return true


func _s_near(i: int, x: float, y: float, r: float) -> bool:
	var o := i * 4
	if x < s_box[o] - r or x > s_box[o + 2] + r or y < s_box[o + 1] - r or y > s_box[o + 3] + r:
		return false
	for k in range(s_cut_first[i], s_cut_first[i + 1], 3):
		if s_cuts[k] * x + s_cuts[k + 1] * y > s_cuts[k + 2] + r:
			return false
	return true


func _s_top_at(i: int, x: float, y: float) -> float:
	var gx := s_gx[i]
	var gy := s_gy[i]
	if gx == 0.0 and gy == 0.0:
		return s_top[i]
	var o := i * 4
	return (
		s_top[i]
		+ gx * (clampf(x, s_box[o], s_box[o + 2]) - s_box[o])
		+ gy * (clampf(y, s_box[o + 1], s_box[o + 3]) - s_box[o + 1])
	)


func _c_inside(j: int, x: float, y: float) -> bool:
	var o := j * 4
	if x < c_box[o] or x > c_box[o + 2] or y < c_box[o + 1] or y > c_box[o + 3]:
		return false
	for k in range(c_cut_first[j], c_cut_first[j + 1], 3):
		if c_cuts[k] * x + c_cuts[k + 1] * y > c_cuts[k + 2]:
			return false
	return true


## LevelGeometry.blocks_in over the pieces `items` (index list numbers).
func _blocks(items: PackedInt32Array, x: float, y: float, r: float, lo: float, hi: float) -> bool:
	for item in items:
		if item >= 0:
			if not _s_near(item, x, y, r):
				continue
			var t := _s_top_at(item, x, y)
			if s_gx[item] != 0.0 or s_gy[item] != 0.0:
				t = maxf(t, maxf(_s_top_at(item, x - r, y - r), _s_top_at(item, x + r, y + r)))
				t = maxf(t, maxf(_s_top_at(item, x - r, y + r), _s_top_at(item, x + r, y - r)))
			var bottom := -1e9 if s_thick[item] < 0.0 else _s_top_at(item, x, y) - s_thick[item]
			if t > lo and bottom < hi:
				return true
		else:
			var j := -1 - item
			if g_z0[j] < hi and _g_top_near(j, x, y, r) > lo:
				var reach := r + g_half[j]
				if _g_dist2(j, x, y) < reach * reach:
					return true
	return false


func _g_top_near(j: int, px: float, py: float, reach: float) -> float:
	var z1 := g_z1[j]
	var z1b := g_z1b[j]
	if z1b == z1:
		return z1
	var o := j * 4
	var ax := g_ends[o]
	var ay := g_ends[o + 1]
	var ex := g_ends[o + 2] - ax
	var ey := g_ends[o + 3] - ay
	var length2 := maxf(ex * ex + ey * ey, 1e-12)
	var t := ((px - ax) * ex + (py - ay) * ey) / length2
	t += reach / sqrt(length2) * (1.0 if z1b > z1 else -1.0)
	return z1 + (z1b - z1) * clampf(t, 0.0, 1.0)


func _g_dist2(j: int, px: float, py: float) -> float:
	var o := j * 4
	var ax := g_ends[o]
	var ay := g_ends[o + 1]
	var ex := g_ends[o + 2] - ax
	var ey := g_ends[o + 3] - ay
	var t := clampf(((px - ax) * ex + (py - ay) * ey) / maxf(ex * ex + ey * ey, 1e-12), 0., 1.)
	var dx := px - ax - ex * t
	var dy := py - ay - ey * t
	return dx * dx + dy * dy


## LevelGeometry.ceiling_in over the overhead pieces `items`.
func _ceiling(items: PackedInt32Array, x: float, y: float, at: float) -> float:
	var best := INF
	for item in items:
		if item >= 0:
			if _s_inside(item, x, y):
				var b := _s_top_at(item, x, y) - s_thick[item]
				if b > at + .01 and b < best:
					best = b
		else:
			var j := -1 - item
			if c_z[j] > at + .01 and c_z[j] < best and _c_inside(j, x, y):
				best = c_z[j]
	return best


## LevelGeometry._fixture_in (near_fixtures) for a body BODY tall.
func _fixture(x: float, y: float, r: float, feet: float) -> bool:
	if x < 0.0 or y < 0.0 or x >= w or y >= h:
		return false
	var c := int(y) * w + int(x)
	if furniture[c] == 0:
		return false
	for k in range(fix_first[c], fix_first[c + 1]):
		var o := fix_list[k] * 8
		if (
			fix[o] - r < x
			and x < fix[o + 2] + r
			and fix[o + 1] - r < y
			and y < fix[o + 3] + r
			and fix[o + 7] < feet + BODY
			and fix[o + 4] > feet + .01
		):
			return true
	return false


func _roof_over(c: int, feet: float) -> float:
	var r := roof[c]
	return r if r != 0.0 and r > feet + .01 else INF


## LevelNav.stands for node n (static_blocked at its middle and its feet,
## headroom under the geometry and the roof).
func stands(n: int) -> bool:
	var c := cell[n]
	var x := c % w + .5
	var y := c / w + .5
	var feet := z[n]
	if static_blocked(x, y, R, feet):
		return false
	var best := INF
	for k in range(over_first[c], over_first[c + 1]):
		var item := over_list[k]
		if item >= 0:
			if _s_inside(item, x, y):
				var b := _s_top_at(item, x, y) - s_thick[item]
				if b > feet + .01 and b < best:
					best = b
		else:
			var j := -1 - item
			if c_z[j] > feet + .01 and c_z[j] < best and _c_inside(j, x, y):
				best = c_z[j]
	return minf(best, _roof_over(c, feet)) - feet >= CROUCH


## LevelGeometry.static_blocked (a body BODY tall), written out.
func static_blocked(x: float, y: float, r: float, feet: float) -> bool:
	for step in 4:
		var ix := int(x + (-r if step < 2 else r))
		var iy := int(y + (-r if step % 2 == 0 else r))
		if ix < 0 or iy < 0 or ix >= w or iy >= h or open[iy * w + ix] == 0:
			return true
	if _fixture(x, y, r, feet):
		return true
	if x < 0.0 or y < 0.0 or x >= w or y >= h:
		return false
	var c := int(y) * w + int(x)
	var box := s_box
	var tops := s_top
	var sgx := s_gx
	var sgy := s_gy
	var thicks := s_thick
	var cut_first := s_cut_first
	var cuts := s_cuts
	var lo := feet + STEP
	var hi := feet + BODY
	for k in range(idx_first[c], idx_first[c + 1]):
		var item := idx_list[k]
		if item >= 0:
			var o := item * 4
			var x0 := box[o]
			var y0 := box[o + 1]
			var x1 := box[o + 2]
			var y1 := box[o + 3]
			if x < x0 - r or x > x1 + r or y < y0 - r or y > y1 + r:
				continue
			var near := true
			for q in range(cut_first[item], cut_first[item + 1], 3):
				if cuts[q] * x + cuts[q + 1] * y > cuts[q + 2] + r:
					near = false
					break
			if not near:
				continue
			var gx := sgx[item]
			var gy := sgy[item]
			var top0 := tops[item]
			var t := top0
			var bottom := -1e9
			if gx == 0.0 and gy == 0.0:
				if thicks[item] >= 0.0:
					bottom = top0 - thicks[item]
			else:
				t = top0 + gx * (clampf(x, x0, x1) - x0) + gy * (clampf(y, y0, y1) - y0)
				if thicks[item] >= 0.0:
					bottom = t - thicks[item]
				var t1 := (
					top0 + gx * (clampf(x - r, x0, x1) - x0) + gy * (clampf(y - r, y0, y1) - y0)
				)
				var t2 := (
					top0 + gx * (clampf(x + r, x0, x1) - x0) + gy * (clampf(y + r, y0, y1) - y0)
				)
				t = maxf(t, maxf(t1, t2))
				var t3 := (
					top0 + gx * (clampf(x - r, x0, x1) - x0) + gy * (clampf(y + r, y0, y1) - y0)
				)
				var t4 := (
					top0 + gx * (clampf(x + r, x0, x1) - x0) + gy * (clampf(y - r, y0, y1) - y0)
				)
				t = maxf(t, maxf(t3, t4))
			if t > lo and bottom < hi:
				return true
		else:
			var j := -1 - item
			if g_z0[j] < hi and _g_top_near(j, x, y, r) > lo:
				var reach := r + g_half[j]
				if _g_dist2(j, x, y) < reach * reach:
					return true
	return false


## stands() for the share's nodes (from .. to) that FlowField's open floor
## asks of a graph (a deck's, or a cell the geometry marks), 1 or 0 each; 2
## for the rest (not asked).
func stands_run(from: int, to: int, marks: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(to - from)
	var cells := w * h
	for n in range(from, to):
		if n < cells and marks[n] == 0:
			out[n - from] = 2
		else:
			out[n - from] = 1 if stands(n) else 0
	return out


# ------------------------------------------------------------- the walks


## For a walk between neighbour cells a and b (a < b), each one's pieces a
## step of the walk inside it could meet (LevelNav._near_walk, which this
## mirrors): [a's floors, a's in the way, a's overhead, b's three] as
## PackedInt32Arrays, then the lowest feet any of them can matter at.
func near_walk(a: int, b: int) -> Array:
	var x0 := minf(a % w, b % w) + .5
	var x1 := maxf(a % w, b % w) + .5
	var y0 := minf(a / w, b / w) + .5
	var y1 := maxf(a / w, b / w) + .5
	var out: Array = []
	var lowest := INF
	for c: int in [a, b]:
		var floors := PackedInt32Array()
		var in_way := PackedInt32Array()
		var overhead := PackedInt32Array()
		for k in range(idx_first[c], idx_first[c + 1]):
			var item := idx_list[k]
			if item >= 0:
				var o := item * 4
				if (
					s_box[o] - R <= x1
					and s_box[o + 2] + R >= x0
					and s_box[o + 1] - R <= y1
					and s_box[o + 3] + R >= y0
				):
					in_way.append(item)
					var low := s_low[item]
					var thick := s_thick[item]
					lowest = minf(lowest, -INF if thick < 0.0 else low - thick - BODY)
					if (
						s_walk[item] == 1
						and s_box[o] <= x1
						and s_box[o + 2] >= x0
						and s_box[o + 1] <= y1
						and s_box[o + 3] >= y0
					):
						floors.append(item)
						lowest = minf(lowest, low - STEP - .002)
			else:
				var j := -1 - item
				var o := j * 4
				var reach := R + g_half[j]
				if (
					minf(g_ends[o], g_ends[o + 2]) - reach <= x1
					and maxf(g_ends[o], g_ends[o + 2]) + reach >= x0
					and minf(g_ends[o + 1], g_ends[o + 3]) - reach <= y1
					and maxf(g_ends[o + 1], g_ends[o + 3]) + reach >= y0
				):
					in_way.append(item)
					lowest = minf(lowest, g_z0[j] - BODY)
		for k in range(over_first[c], over_first[c + 1]):
			var item := over_list[k]
			if item >= 0:
				var o := item * 4
				if (
					s_box[o] <= x1
					and s_box[o + 2] >= x0
					and s_box[o + 1] <= y1
					and s_box[o + 3] >= y0
				):
					overhead.append(item)
					lowest = minf(lowest, s_low[item] - s_thick[item] - CROUCH)
			else:
				var j := -1 - item
				var o := j * 4
				if (
					c_box[o] <= x1
					and c_box[o + 2] >= x0
					and c_box[o + 1] <= y1
					and c_box[o + 3] >= y0
				):
					overhead.append(item)
					lowest = minf(lowest, c_z[j] - CROUCH)
		out.append(floors)
		out.append(in_way)
		out.append(overhead)
	out.append(lowest)
	return out


## Whether a body walks from node n's middle to node m's AND back from m's to
## n's (LevelNav.walks both ways, the same answers). `near`: near_walk()'s
## lists by pair of cells, kept between calls.
func walks_both(n: int, m: int, near: Dictionary) -> bool:
	var a := cell[n]
	var b := cell[m]
	# Every step's corners lie in a or b: either shut to a body, no walk.
	if open[a] == 0 or open[b] == 0:
		return false
	var pair := Vector2i(mini(a, b), maxi(a, b))
	var lists: Variant = near.get(pair)
	if lists == null:
		lists = near_walk(pair.x, pair.y)
		near[pair] = lists
	var parts: Array = lists
	var lowest: float = parts[6]
	var floor_ab := maxf(ground[a], ground[b])
	var grid_n := maxf(z[n], floor_ab) < lowest
	var grid_m := maxf(z[m], floor_ab) < lowest
	# Each way, the highest its feet can climb to (its cells' grounds, then each
	# floor whose lowest is within a step of the highest so far): short of
	# the far end's floor, no walk.
	if _reach(parts, maxf(z[n], floor_ab)) < z[m] - .06:
		return false
	if _reach(parts, maxf(z[m], floor_ab)) < z[n] - .06:
		return false
	if grid_n and grid_m:
		return _grid_walk(a, b, z[m]) and _grid_walk(b, a, z[n])
	# Each point the two walks step on (0 is a's middle, 8 b's) and what was
	# asked there last: the feet a floor was found from and that floor, the
	# feet a stand was asked at and whether it stood.
	if _asked.size() != 36:
		_asked.resize(36)
	_asked.fill(NAN)
	var there := _walk(a, b, z[n], z[m], parts, _asked, false, grid_n)
	return there and _walk(b, a, z[m], z[n], parts, _asked, true, grid_m)


## The highest feet a walk can climb to from `high` (the start's floor or
## its cells' grounds, the higher) over the floors in near_walk()'s `parts`.
func _reach(parts: Array, high: float) -> float:
	var floors_a: PackedInt32Array = parts[0]
	var floors_b: PackedInt32Array = parts[3]
	if floors_a.is_empty() and floors_b.is_empty():
		return high
	var lows := s_low
	var highs := s_high
	var grew := true
	while grew:
		grew = false
		for i in floors_a:
			if lows[i] <= high + STEP + .001 and highs[i] > high:
				high = highs[i]
				grew = true
		for i in floors_b:
			if lows[i] <= high + STEP + .001 and highs[i] > high:
				high = highs[i]
				grew = true
	return high


## One way of walks_both(): a's middle to b's from feet from_z, to arrive at
## to_z. Everything it reads is in locals and every query written out (a
## method call or a member read a step costs more than the sums).
func _walk(
	a: int,
	b: int,
	from_z: float,
	to_z: float,
	parts: Array,
	asked: PackedFloat64Array,
	back: bool,
	grid: bool
) -> bool:
	if grid:
		return _grid_walk(a, b, to_z)
	var ww := w
	var grounds := ground
	var roofs := roof
	var box := s_box
	var tops := s_top
	var sgx := s_gx
	var sgy := s_gy
	var thicks := s_thick
	var cut_first := s_cut_first
	var cuts := s_cuts
	var ends := g_ends
	var z0s := g_z0
	var z1s := g_z1
	var z1bs := g_z1b
	var halves := g_half
	var cbox := c_box
	var czs := c_z
	var c_first := c_cut_first
	var ccuts := c_cuts
	var ax := a % ww + .5
	var ay := a / ww + .5
	var bx := b % ww + .5
	var by := b / ww + .5
	var low_cell := mini(a, b)
	var feet := from_z
	var r := R
	for k in range(1, NAV_STEPS + 1):
		var f := float(k) / NAV_STEPS
		var x := ax + (bx - ax) * f
		var y := ay + (by - ay) * f
		var c := int(y) * ww + int(x)
		var at := (NAV_STEPS - k if back else k) * 4
		var side := 0 if c == low_cell else 3
		var floor_z: float
		if asked[at] == feet:
			floor_z = asked[at + 1]
		else:
			# LevelGeometry.floor_at over the floors near the walk.
			floor_z = grounds[c]
			var floors: PackedInt32Array = parts[side]
			for i in floors:
				var o := i * 4
				if x < box[o] or x > box[o + 2] or y < box[o + 1] or y > box[o + 3]:
					continue
				var inside := true
				for q in range(cut_first[i], cut_first[i + 1], 3):
					if cuts[q] * x + cuts[q + 1] * y > cuts[q + 2]:
						inside = false
						break
				if not inside:
					continue
				var t := tops[i]
				if sgx[i] != 0.0 or sgy[i] != 0.0:
					t = (
						tops[i]
						+ sgx[i] * (clampf(x, box[o], box[o + 2]) - box[o])
						+ sgy[i] * (clampf(y, box[o + 1], box[o + 3]) - box[o + 1])
					)
				if t <= feet + STEP + .001 and t > floor_z:
					floor_z = t
			asked[at] = feet
			asked[at + 1] = floor_z
		if floor_z > feet + STEP + .002 and floor_z > grounds[c] + .001:
			return false
		feet = floor_z
		var stood: bool
		if asked[at + 2] == feet:
			stood = asked[at + 3] != 0.0
		else:
			# static_blocked's corners lie in a or b, both open (walks_both).
			stood = not _fixture(x, y, r, feet)
			if stood:
				# LevelGeometry.blocks_in over the pieces near the walk.
				var lo := feet + STEP
				var hi := feet + BODY
				var in_way: PackedInt32Array = parts[side + 1]
				for item in in_way:
					if item >= 0:
						var o := item * 4
						if (
							x < box[o] - r
							or x > box[o + 2] + r
							or y < box[o + 1] - r
							or y > box[o + 3] + r
						):
							continue
						var near := true
						for q in range(cut_first[item], cut_first[item + 1], 3):
							if cuts[q] * x + cuts[q + 1] * y > cuts[q + 2] + r:
								near = false
								break
						if not near:
							continue
						var gx := sgx[item]
						var gy := sgy[item]
						var top0 := tops[item]
						var t := top0
						var bottom := -1e9
						if gx == 0.0 and gy == 0.0:
							if thicks[item] >= 0.0:
								bottom = top0 - thicks[item]
						else:
							var x0 := box[o]
							var y0 := box[o + 1]
							var x1 := box[o + 2]
							var y1 := box[o + 3]
							t = top0 + gx * (clampf(x, x0, x1) - x0) + gy * (clampf(y, y0, y1) - y0)
							if thicks[item] >= 0.0:
								bottom = t - thicks[item]
							var t1 := (
								top0
								+ gx * (clampf(x - r, x0, x1) - x0)
								+ gy * (clampf(y - r, y0, y1) - y0)
							)
							var t2 := (
								top0
								+ gx * (clampf(x + r, x0, x1) - x0)
								+ gy * (clampf(y + r, y0, y1) - y0)
							)
							t = maxf(t, maxf(t1, t2))
							var t3 := (
								top0
								+ gx * (clampf(x - r, x0, x1) - x0)
								+ gy * (clampf(y + r, y0, y1) - y0)
							)
							var t4 := (
								top0
								+ gx * (clampf(x + r, x0, x1) - x0)
								+ gy * (clampf(y - r, y0, y1) - y0)
							)
							t = maxf(t, maxf(t3, t4))
						if t > lo and bottom < hi:
							stood = false
							break
					else:
						var j := -1 - item
						if z0s[j] >= hi:
							continue
						var o := j * 4
						var sx := ends[o]
						var sy := ends[o + 1]
						var ex := ends[o + 2] - sx
						var ey := ends[o + 3] - sy
						var length2 := maxf(ex * ex + ey * ey, 1e-12)
						var z1 := z1s[j]
						var z1b := z1bs[j]
						var top := z1
						if z1b != z1:
							var u := ((x - sx) * ex + (y - sy) * ey) / length2
							u += r / sqrt(length2) * (1.0 if z1b > z1 else -1.0)
							top = z1 + (z1b - z1) * clampf(u, 0.0, 1.0)
						if top <= lo:
							continue
						var reach := r + halves[j]
						var v := clampf(((x - sx) * ex + (y - sy) * ey) / length2, 0., 1.)
						var dx := x - sx - ex * v
						var dy := y - sy - ey * v
						if dx * dx + dy * dy < reach * reach:
							stood = false
							break
			if stood:
				# LevelGeometry.ceiling_in over the overhead pieces, and the roof.
				var best := INF
				var overhead: PackedInt32Array = parts[side + 2]
				for item in overhead:
					if item >= 0:
						var o := item * 4
						if x < box[o] or x > box[o + 2] or y < box[o + 1] or y > box[o + 3]:
							continue
						var inside := true
						for q in range(cut_first[item], cut_first[item + 1], 3):
							if cuts[q] * x + cuts[q + 1] * y > cuts[q + 2]:
								inside = false
								break
						if not inside:
							continue
						var t := tops[item]
						if sgx[item] != 0.0 or sgy[item] != 0.0:
							t = (
								tops[item]
								+ sgx[item] * (clampf(x, box[o], box[o + 2]) - box[o])
								+ sgy[item] * (clampf(y, box[o + 1], box[o + 3]) - box[o + 1])
							)
						var bt := t - thicks[item]
						if bt > feet + .01 and bt < best:
							best = bt
					else:
						var j := -1 - item
						var cz := czs[j]
						if cz > feet + .01 and cz < best:
							var o := j * 4
							if x < cbox[o] or x > cbox[o + 2] or y < cbox[o + 1] or y > cbox[o + 3]:
								continue
							var inside := true
							for q in range(c_first[j], c_first[j + 1], 3):
								if ccuts[q] * x + ccuts[q + 1] * y > ccuts[q + 2]:
									inside = false
									break
							if inside:
								best = cz
				var rf := roofs[c]
				var over := rf if rf != 0.0 and rf > feet + .01 else INF
				stood = minf(best, over) - feet >= CROUCH
			asked[at + 2] = feet
			asked[at + 3] = 1.0 if stood else 0.0
		if not stood:
			return false
	return absf(feet - to_z) < .06


## A walk from a's middle to b's where no piece can matter (LevelNav._grid_walk):
## the corners are known open (walks_both), so the roofs and the furniture.
func _grid_walk(a: int, b: int, to_z: float) -> bool:
	if _roof_over(a, ground[a]) - ground[a] < CROUCH:
		return false
	if _roof_over(b, ground[b]) - ground[b] < CROUCH:
		return false
	if furniture[a] != 0 or furniture[b] != 0:
		var ax := a % w + .5
		var ay := a / w + .5
		var bx := b % w + .5
		var by := b / w + .5
		for k in range(1, NAV_STEPS + 1):
			var f := float(k) / NAV_STEPS
			var x := ax + (bx - ax) * f
			var y := ay + (by - ay) * f
			if _fixture(x, y, R, ground[int(y) * w + int(x)]):
				return false
	return absf(ground[b] - to_z) < .06
