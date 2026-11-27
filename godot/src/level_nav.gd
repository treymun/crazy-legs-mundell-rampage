## The nav graph's building, moved out of level_geometry.gd: the walkable
## places of a level with geometry as nodes and edges for FlowField
## (build_nav(), which LevelGeometry.nav() keeps), the ladders' ends on it
## (ladder_nodes()) and whether a node can be stood on (stands()). The graph
## itself is LevelGeometry.NavGraph (nav_graph.gd).
class_name LevelNav
extends RefCounted

## A graph of fewer nodes than this is built on the calling thread alone.
const SHARED_FROM := 2048
## Nodes to a share of the work when it is shared out over the worker threads.
const SHARE := 512
## The most worker threads a graph is built on (more only wait on each other).
const THREADS := 6


## One share of the building (a run of nodes): what its walks found.
class Share:
	var from := 0
	var to := 0
	## The orthogonal pairs (n, m) its nodes found, in the order found.
	var pair_n := PackedInt32Array()
	var pair_m := PackedInt32Array()
	## The steps to the cells beside them its cells' pairs found (cell, bit).
	var mask_at := PackedInt32Array()
	var mask_bit := PackedByteArray()
	## Its nodes' diagonals: node from + i's are dedges[dfirst[i] .. dfirst[i + 1]].
	var dfirst := PackedInt32Array()
	var dedges := PackedInt32Array()
	## The flat copy its walks read (NavWalk; a copy of its own on a worker
	## thread), or null: the queries themselves.
	var walk: NavWalk = null
	## Whether each of its nodes stands (stands()), 1 or 0.
	var stood := PackedByteArray()


## The graph (nav()): the nodes, edges and order it was always built with
## (tools/load_reference.gd keeps that build; load_check.gd holds this one to
## it) in a fraction of the time: the arrays read through locals, the
## orthogonal edges gathered as pairs in the order found and laid out once
## (no list per node copied at every append), the diagonals written straight in.
## Pass 16: each node's walks and diagonals are its own, so a big graph's are
## shared out over the worker threads in runs of nodes and put back together
## in node order (the same graph), and each walk asks only the pieces that can
## matter to it (walks()).
static func build_nav(geo: LevelGeometry, lv: LevelData) -> LevelGeometry.NavGraph:
	var g := LevelGeometry.NavGraph.new()
	var w := geo.width
	var h := geo.height
	var n_cells := w * h
	g.cells = n_cells
	var cell := PackedInt32Array(range(n_cells))
	var z := lv.ground.slice(0, n_cells)
	var over := g.over
	var extra_cell := PackedInt32Array()
	var extra_z := PackedFloat32Array()
	for s in geo.slabs:
		if not s.walk:
			continue
		for cy in range(maxi(0, floori(s.y0)), mini(h - 1, floori(s.y1)) + 1):
			for cx in range(maxi(0, floori(s.x0)), mini(w - 1, floori(s.x1)) + 1):
				var mx := cx + .5
				var my := cy + .5
				var c := cy * w + cx
				if not s.inside(mx, my) or lv.solid[c] >= 0:
					continue
				var top := s.top_at(mx, my)
				if s.thick < 0.0 or top - lv.ground[c] <= LevelGeometry.STEP:
					# Solid down to the ground (or nearly the floor): the cell's floor.
					z[c] = maxf(z[c], top)
					continue
				var dup := false
				var list: Array = over.get(c, [])
				for k: int in list:
					if absf(extra_z[k - n_cells] - top) < .05:
						dup = true
				if dup:
					continue
				list.append(n_cells + extra_cell.size())
				over[c] = list
				extra_cell.append(c)
				extra_z.append(top)
	cell.append_array(extra_cell)
	z.append_array(extra_z)
	var count := cell.size()
	g.count = count
	g.cell = cell
	g.z = z
	# Orthogonal edges: each pair (n, m), m >= n, in the order found; n's list
	# gets m and m's gets n, in that order.
	var shares := _shares(count)
	var flat := NavWalk.make(geo, lv, g)
	for share in shares:
		share.walk = flat if flat == null or shares.size() == 1 else flat.copy()
	_run(shares, func(share: Share) -> void: _orthogonal(geo, lv, g, share))
	var pair_n := PackedInt32Array()
	var pair_m := PackedInt32Array()
	# Each cell's steps to the cells beside it (E 1, W 2, S 4, N 8), for the
	# diagonals' quick way (_diagonals).
	var masks := PackedByteArray()
	masks.resize(n_cells)
	masks.fill(0)
	for share in shares:
		pair_n.append_array(share.pair_n)
		pair_m.append_array(share.pair_m)
		for k in share.mask_at.size():
			masks[share.mask_at[k]] |= share.mask_bit[k]
	var laid := lay_out(count, pair_n, pair_m)
	var starts: PackedInt32Array = laid[0]
	var edges: PackedInt32Array = laid[1]
	# Ladders join their foot and top after the steps (at the end of each end's
	# list).
	var extra := {}
	for i in geo.ladders.size():
		var ends := ladder_nodes(geo, g, geo.ladders[i])
		g.ladder_ends.append(ends)
		if ends.x < 0:
			continue
		var more: PackedInt32Array = extra.get(ends.x, PackedInt32Array())
		if more.has(ends.y) or edges.slice(starts[ends.x], starts[ends.x + 1]).has(ends.y):
			continue
		more.append(ends.y)
		extra[ends.x] = more
		var back: PackedInt32Array = extra.get(ends.y, PackedInt32Array())
		back.append(ends.x)
		extra[ends.y] = back
		g.links[ends.x * count + ends.y] = i
		g.links[ends.y * count + ends.x] = i
	if not extra.is_empty():
		var joined := PackedInt32Array()
		var joined_starts := PackedInt32Array()
		joined_starts.resize(count + 1)
		for n in count:
			joined_starts[n] = joined.size()
			joined.append_array(edges.slice(starts[n], starts[n + 1]))
			var more: Variant = extra.get(n)
			if more != null:
				var list: PackedInt32Array = more
				joined.append_array(list)
		joined_starts[count] = joined.size()
		edges = joined
		starts = joined_starts
	g.first = starts
	g.edges = edges
	diagonals(geo, lv, g, masks, shares)
	if flat != null:
		# Whether each node stands, while the threads are at it: the open floor
		# FlowField measures next (stands_all), asked of a graph just built.
		var marks := geo.cells
		_run(
			shares,
			func(share: Share) -> void:
				share.stood = share.walk.stands_run(share.from, share.to, marks)
		)
		for share in shares:
			g.stood.append_array(share.stood)
	return g


## The runs of nodes the building is shared out in (one, for a small graph or
## a build without threads).
static func _shares(count: int) -> Array[Share]:
	var out: Array[Share] = []
	var size := count
	if count >= SHARED_FROM and OS.has_feature("threads"):
		size = SHARE
	var from := 0
	while from < count:
		var share := Share.new()
		share.from = from
		share.to = mini(count, from + size)
		out.append(share)
		from = share.to
	return out


## `job` on every share: on the worker threads when there are several (each
## writes only its own share), else here.
static func _run(shares: Array[Share], job: Callable) -> void:
	if shares.size() == 1:
		job.call(shares[0])
		return
	var task := WorkerThreadPool.add_group_task(
		func(i: int) -> void: job.call(shares[i]), shares.size(), THREADS, true, "nav graph"
	)
	WorkerThreadPool.wait_for_group_task_completion(task)


## The orthogonal pairs the share's nodes start (build_nav's walk over them).
static func _orthogonal(
	geo: LevelGeometry, lv: LevelData, g: LevelGeometry.NavGraph, share: Share
) -> void:
	var w := geo.width
	var h := geo.height
	var n_cells := g.cells
	var cell := g.cell
	var over := g.over
	var geo_cells := geo.cells
	var dx := PackedInt32Array([1, -1, 0, 0])
	var dy := PackedInt32Array([0, 0, 1, -1])
	var bit := PackedByteArray([1, 2, 4, 8])
	var back_bit := PackedByteArray([2, 1, 8, 4])
	var walked := {}
	var near := {}
	var flat := share.walk
	var pair_n := share.pair_n
	var pair_m := share.pair_m
	var mask_at := share.mask_at
	var mask_bit := share.mask_bit
	for n in range(share.from, share.to):
		var c := cell[n]
		var cx := c % w
		var cy := c / w
		var own := n < n_cells and geo_cells[c] == 0
		for d in 4:
			var nx := cx + dx[d]
			var ny := cy + dy[d]
			if nx < 0 or ny < 0 or nx >= w or ny >= h:
				continue
			var c2 := ny * w + nx
			# Far from every piece: the grid's own rule (heights not asked), as
			# the flow fields always had it.
			if (
				c2 >= n
				and (
					(own and geo_cells[c2] == 0)
					or (
						flat.walks_both(n, c2, near)
						if flat != null
						else (
							walks(geo, lv, g, n, c2, walked, near)
							and walks(geo, lv, g, c2, n, walked, near)
						)
					)
				)
			):
				pair_n.append(n)
				pair_m.append(c2)
				if n < n_cells:
					mask_at.append(n)
					mask_bit.append(bit[d])
					mask_at.append(c2)
					mask_bit.append(back_bit[d])
			if flat != null:
				for k in range(flat.deck_first[c2], flat.deck_first[c2 + 1]):
					var m := flat.deck_list[k]
					if m >= n and flat.walks_both(n, m, near):
						pair_n.append(n)
						pair_m.append(m)
				continue
			var decks: Variant = over.get(c2)
			if decks != null:
				for m: int in decks:
					if (
						m >= n
						and walks(geo, lv, g, n, m, walked, near)
						and walks(geo, lv, g, m, n, walked, near)
					):
						pair_n.append(n)
						pair_m.append(m)
	share.pair_n = pair_n
	share.pair_m = pair_m
	share.mask_at = mask_at
	share.mask_bit = mask_bit


## CSR arrays [first, edges] of the pairs (n, m): each node's neighbours in
## the order the pairs name them (n gets m, then m gets n).
static func lay_out(count: int, pair_n: PackedInt32Array, pair_m: PackedInt32Array) -> Array:
	var pairs := pair_n.size()
	var first := PackedInt32Array()
	first.resize(count + 1)
	first.fill(0)
	for k in pairs:
		first[pair_n[k] + 1] += 1
		first[pair_m[k] + 1] += 1
	for n in count:
		first[n + 1] += first[n]
	var edges := PackedInt32Array()
	edges.resize(first[count])
	var at := first.slice(0, count)
	for k in pairs:
		var n := pair_n[k]
		var m := pair_m[k]
		edges[at[n]] = m
		at[n] += 1
		edges[at[m]] = n
		at[m] += 1
	return [first, edges]


## Diagonals: n to m when each side cell leads from n to m (and no ladder
## does it), never past a corner something stands on. `masks`: each cell's
## steps to the cells beside it (E 1, W 2, S 4, N 8). `shares`: the runs of
## nodes to work them out in (build_nav's; one run when not given).
static func diagonals(
	geo: LevelGeometry,
	lv: LevelData,
	g: LevelGeometry.NavGraph,
	masks: PackedByteArray,
	shares: Array[Share] = []
) -> void:
	var count := g.count
	var n_cells := g.cells
	var w := geo.width
	var cell := g.cell
	# Each node's cell's column and row, and whether a ladder joins it.
	var col := PackedInt32Array()
	var row := PackedInt32Array()
	col.resize(count)
	row.resize(count)
	for n in count:
		col[n] = cell[n] % w
		row[n] = cell[n] / w
	var laddered := PackedByteArray()
	laddered.resize(count)
	laddered.fill(0)
	for ends: Vector2i in g.ladder_ends:
		if ends.x >= 0:
			laddered[ends.x] = 1
			laddered[ends.y] = 1
	# The cells with a deck or a ladder's end in their 3 by 3.
	var special := PackedByteArray()
	special.resize(n_cells)
	special.fill(0)
	var odd: Array = g.over.keys()
	for ends: Vector2i in g.ladder_ends:
		if ends.x >= 0:
			odd.append(cell[ends.x])
			odd.append(cell[ends.y])
	for c: int in odd:
		for yy in range(maxi(0, c / w - 1), mini(g.cells / w, c / w + 2)):
			for xx in range(maxi(0, c % w - 1), mini(w, c % w + 2)):
				special[yy * w + xx] = 1
	var runs := shares if not shares.is_empty() else _shares(count)
	if shares.is_empty():
		var flat := NavWalk.make(geo, lv, g)
		for share in runs:
			share.walk = flat if flat == null or runs.size() == 1 else flat.copy()
	var ways: Array = [col, row, laddered, special, masks]
	_run(runs, func(share: Share) -> void: _diagonals_of(geo, lv, g, ways, share))
	var dfirst := PackedInt32Array()
	dfirst.resize(count + 1)
	var dedges := PackedInt32Array()
	for share in runs:
		var base := dedges.size()
		for i in share.to - share.from:
			dfirst[share.from + i] = base + share.dfirst[i]
		dedges.append_array(share.dedges)
	dfirst[count] = dedges.size()
	g.dfirst = dfirst
	g.dedges = dedges


## The share's nodes' diagonals (diagonals() over them). `ways`: [col, row,
## laddered, special, masks] as diagonals() works them out.
static func _diagonals_of(
	geo: LevelGeometry, lv: LevelData, g: LevelGeometry.NavGraph, ways: Array, share: Share
) -> void:
	var n_cells := g.cells
	var w := geo.width
	var count := g.count
	var cell := g.cell
	var z := g.z
	var first := g.first
	var edges := g.edges
	var links := g.links
	var col: PackedInt32Array = ways[0]
	var row: PackedInt32Array = ways[1]
	var laddered: PackedByteArray = ways[2]
	var special: PackedByteArray = ways[3]
	var masks: PackedByteArray = ways[4]
	# The corner asked last and once: (corner, feet) -> whether it is blocked.
	# The same answers in the same order as asking it all each time.
	var corners := {}
	var flat := share.walk
	var dfirst := PackedInt32Array()
	dfirst.resize(share.to - share.from + 1)
	var dedges := PackedInt32Array()
	var reach := LevelGeometry.NAV_BODY * .6
	for n in range(share.from, share.to):
		var start := dedges.size()
		dfirst[n - share.from] = start
		var cx := col[n]
		var cy := row[n]
		var n0 := first[n]
		var n1 := first[n + 1]
		if n < n_cells and special[n] == 0:
			# A cell's own node with only cells round it (no deck, no ladder in
			# its 3 by 3): its neighbours are those cells in the order N, W, E,
			# S (as the pairs were found), so the walk below finds its
			# diagonals in the order NW, NE, SW, SE, each where both its sides
			# lead to it: asked straight from the masks, the same answers.
			var mk := masks[n]
			for k in 4:
				var ddx := -1 if k % 2 == 0 else 1
				var ddy := -1 if k < 2 else 1
				var side_x := 2 if ddx < 0 else 1
				var side_y := 8 if ddy < 0 else 4
				if mk & (side_x | side_y) != (side_x | side_y):
					continue
				if masks[n + ddy * w] & side_x == 0 or masks[n + ddx] & side_y == 0:
					continue
				var m := n + ddy * w + ddx
				var at := Vector3(
					(cx + cx + ddx + 1) * .5, (cy + cy + ddy + 1) * .5, minf(z[n], z[m])
				)
				var blocked: Variant = corners.get(at)
				if blocked == null:
					blocked = (
						flat.static_blocked(at.x, at.y, reach, at.z)
						if flat != null
						else geo.static_blocked(lv, at.x, at.y, reach, at.z, LevelGeometry.BODY)
					)
					corners[at] = blocked
				if not blocked:
					dedges.append(m)
			continue
		var lad_n := laddered[n] == 1
		for i in range(n0, n1):
			var a := edges[i]
			if lad_n and links.has(n * count + a):
				continue
			var ca := cell[a]
			var lad_a := laddered[a] == 1
			for j in range(first[a], first[a + 1]):
				var m := edges[j]
				var mc := col[m] - cx
				var mr := row[m] - cy
				if (mc != 1 and mc != -1) or (mr != 1 and mr != -1):
					continue
				if lad_a and links.has(a * count + m):
					continue
				var seen := false
				for q in range(start, dedges.size()):
					if dedges[q] == m:
						seen = true
						break
				if seen:
					continue
				# The other side's cell leads from n to m too.
				var side := false
				for k in range(n0, n1):
					var b := edges[k]
					if b == a or cell[b] == ca:
						continue
					for e in range(first[b], first[b + 1]):
						if edges[e] == m:
							side = true
							break
					if side:
						break
				if not side:
					continue
				# Never past the corner the two cells share when something stands
				# on it (a porch post on a cell corner): a body cutting the corner
				# would wedge on it.
				var at := Vector3((cx + col[m] + 1) * .5, (cy + row[m] + 1) * .5, minf(z[n], z[m]))
				var blocked: Variant = corners.get(at)
				if blocked == null:
					blocked = (
						flat.static_blocked(at.x, at.y, reach, at.z)
						if flat != null
						else geo.static_blocked(lv, at.x, at.y, reach, at.z, LevelGeometry.BODY)
					)
					corners[at] = blocked
				if blocked:
					continue
				dedges.append(m)
	dfirst[share.to - share.from] = dedges.size()
	share.dfirst = dfirst
	share.dedges = dedges


## Whether node b's orthogonal neighbours include m.
static func joins(g: LevelGeometry.NavGraph, b: int, m: int) -> bool:
	for e in range(g.first[b], g.first[b + 1]):
		if g.edges[e] == m:
			return true
	return false


## A ladder's foot and top nodes in g ((-1, -1): its foot or its top is not a
## place to stand, or the floor there is not the ladder's).
static func ladder_nodes(
	geo: LevelGeometry, g: LevelGeometry.NavGraph, lad: LevelGeometry.Ladder
) -> Vector2i:
	var f := lad.foot()
	var t := lad.top()
	var a := g.node_at(f.x, f.y, geo.width, geo.height, lad.z0 + .1)
	var b := g.node_at(t.x, t.y, geo.width, geo.height, lad.z1 + .1)
	if a < 0 or b < 0 or a == b:
		return Vector2i(-1, -1)
	if absf(g.z[a] - lad.z0) > .3 or absf(g.z[b] - lad.z1) > .3:
		return Vector2i(-1, -1)
	return Vector2i(a, b)


## Whether node n's middle is somewhere a body can stand (FlowField's open
## floor on a level with geometry; doors and panes are FlowField's to ask).
static func stands(geo: LevelGeometry, lv: LevelData, g: LevelGeometry.NavGraph, n: int) -> bool:
	var c := g.cell[n]
	var width := geo.width
	var x := c % width + .5
	var y := c / width + .5
	var feet := g.z[n]
	if geo.static_blocked(lv, x, y, LevelGeometry.NAV_BODY, feet, LevelGeometry.BODY):
		return false
	return (
		minf(geo.ceiling_at(x, y, feet), LevelGeometry._roof(lv, c, feet)) - feet
		>= LevelGeometry.CROUCH
	)


## stands() for each of `nodes`, 1 or 0 in their order (FlowField's open
## floor): the graph's own answers when it was built here (build_nav keeps
## them), else asked, on the worker threads when there are many.
static func stands_all(
	geo: LevelGeometry, lv: LevelData, g: LevelGeometry.NavGraph, nodes: PackedInt32Array
) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(nodes.size())
	if g.stood.size() == g.count:
		var known := true
		for k in nodes.size():
			out[k] = g.stood[nodes[k]]
			known = known and out[k] != 2
		if known:
			return out
	var shares := _shares(nodes.size())
	var flat := NavWalk.make(geo, lv, g)
	for share in shares:
		share.walk = flat if flat == null or shares.size() == 1 else flat.copy()
	_run(
		shares,
		func(share: Share) -> void:
			var mine := PackedByteArray()
			mine.resize(share.to - share.from)
			for k in share.to - share.from:
				var node := nodes[share.from + k]
				var ok := (
					share.walk.stands(node) if share.walk != null else stands(geo, lv, g, node)
				)
				mine[k] = 1 if ok else 0
			share.mask_bit = mine
	)
	for share in shares:
		for k in share.to - share.from:
			out[share.from + k] = share.mask_bit[k]
	return out


## Whether a body walks from node n's middle to node m's (sub-stepped: the
## enemies' rule, the grid's own steps free, slabs at most STEP up, nothing in
## the way at the body's height, headroom for a crouch).
## `memo`: what has been asked at a point (on a sixteenth of a cell) at a
## height, so a walk back over the same points asks nothing again.
## `near`: each pair of cells' pieces that come near a walk between them and
## the lowest feet any of them can matter at (_near_walk). A walk asks only
## those, and a walk whose feet stay under that height is the grid's own
## (_grid_walk). Pass 16: the same answers in a fraction of the time.
static func walks(
	geo: LevelGeometry,
	lv: LevelData,
	g: LevelGeometry.NavGraph,
	n: int,
	m: int,
	memo: Dictionary,
	near: Dictionary
) -> bool:
	var a := g.cell[n]
	var b := g.cell[m]
	var width := geo.width
	var ground := lv.ground
	var pair := Vector2i(mini(a, b), maxi(a, b))
	var lists: Variant = near.get(pair)
	if lists == null:
		lists = _near_walk(geo, pair.x, pair.y)
		near[pair] = lists
	var parts: Array = lists
	var feet := g.z[n]
	var lowest: float = parts[6]
	if maxf(feet, maxf(ground[a], ground[b])) < lowest:
		return _grid_walk(lv, a, b, g.z[m])
	var ax := a % width + .5
	var ay := a / width + .5
	var bx := b % width + .5
	var by := b / width + .5
	var across := width * 16 + 1
	for k in range(1, LevelGeometry.NAV_STEPS + 1):
		var f := float(k) / LevelGeometry.NAV_STEPS
		var x := ax + (bx - ax) * f
		var y := ay + (by - ay) * f
		var c := int(y) * width + int(x)
		# Asked before at this point and height: the same answer (the
		# point's key is exact: it is on a sixteenth of a cell, or not kept).
		# Its floor by the feet it was asked from, whether it stands by the
		# feet on it.
		var floors: Dictionary
		var stood: Dictionary
		var fx := x * 16.0
		var fy := y * 16.0
		var keep := fx == floorf(fx) and fy == floorf(fy)
		if keep:
			var point := (int(fy) * across + int(fx)) * 2
			var known: Variant = memo.get(point)
			if known == null:
				floors = {}
				stood = {}
				memo[point] = floors
				memo[point + 1] = stood
			else:
				floors = known
				stood = memo[point + 1]
		# This cell's pieces near the walk: [floors, in the way, overhead].
		var side := 0 if c == pair.x else 3
		var floor_z: float
		var was: Variant = floors.get(feet) if keep else null
		if was != null:
			floor_z = was
		else:
			# LevelGeometry.floor_at(x, y, feet, ground[c], true) over them.
			floor_z = ground[c]
			for s: LevelGeometry.Slab in parts[side]:
				if s.inside(x, y):
					var t := s.top_at(x, y)
					if t <= feet + LevelGeometry.STEP + .001 and t > floor_z:
						floor_z = t
			if keep:
				floors[feet] = floor_z
		if floor_z > feet + LevelGeometry.STEP + .002 and floor_z > ground[c] + .001:
			return false
		feet = floor_z
		var stands_here: Variant = stood.get(feet) if keep else null
		if stands_here == null:
			var in_way: Array = parts[side + 1]
			var overhead: Array = parts[side + 2]
			stands_here = (
				not geo.static_blocked_in(
					lv, x, y, LevelGeometry.NAV_BODY, feet, LevelGeometry.BODY, in_way
				)
				and (
					(
						minf(
							LevelGeometry.ceiling_in(overhead, x, y, feet),
							LevelGeometry._roof(lv, c, feet)
						)
						- feet
					)
					>= LevelGeometry.CROUCH
				)
			)
			if keep:
				stood[feet] = stands_here
		if not stands_here:
			return false
	return absf(feet - g.z[m]) < .06


## walks() from cell a's middle to b's (its neighbour) where no piece of the
## geometry can matter: each step on its cell's ground (never refused for the
## grid's own steps), the body's corners in a or b (each solid but for a
## door's), the furniture at its height, headroom under the cell's roof.
static func _grid_walk(lv: LevelData, a: int, b: int, to_z: float) -> bool:
	var ground := lv.ground
	for c: int in [a, b]:
		if lv.solid[c] >= 0 and not lv.door_cells.has(c):
			return false
		if LevelGeometry._roof(lv, c, ground[c]) - ground[c] < LevelGeometry.CROUCH:
			return false
	var width := lv.width
	var furniture := lv.furniture_cells
	var r := LevelGeometry.NAV_BODY
	if (
		furniture.size() != width * lv.height
		or r > lv.index_radius
		or furniture[a] != 0
		or furniture[b] != 0
	):
		var ax := a % width + .5
		var ay := a / width + .5
		var bx := b % width + .5
		var by := b / width + .5
		for k in range(1, LevelGeometry.NAV_STEPS + 1):
			var f := float(k) / LevelGeometry.NAV_STEPS
			var x := ax + (bx - ax) * f
			var y := ay + (by - ay) * f
			var c := int(y) * width + int(x)
			if _fixture_at(lv, x, y, r, ground[c]):
				return false
	return absf(ground[b] - to_z) < .06


## LevelGeometry._fixture_in for a body BODY tall.
static func _fixture_at(lv: LevelData, x: float, y: float, r: float, feet: float) -> bool:
	var list: Array = (
		lv.near_fixtures.get(Vector2i(int(x), int(y)), LevelGeometry.NOTHING)
		if r <= lv.index_radius
		else lv.collision_volumes
	)
	for fixture: Variant in list:
		var f: PackedFloat32Array = fixture
		if (
			f[0] - r < x
			and x < f[2] + r
			and f[1] - r < y
			and y < f[3] + r
			and f[7] < feet + LevelGeometry.BODY
			and f[4] > feet + .01
		):
			return true
	return false


## For a walk between neighbour cells a and b (middle to middle), each one's
## pieces from its lists that a step of the walk inside it could meet:
## [a's walkable slabs, a's slabs and segments, a's overhead pieces, b's
## three, the lowest feet any of them can matter at]. A piece left out is one
## no point of the walk comes within the body's reach of (a slab's box, a
## segment's grown by its half), so the walk's answers over these are the
## answers over the whole lists. A floor matters to feet a step under its
## lowest top and up, a thick slab or a segment in the way to feet a body's
## height under its bottom and up (a solid slab to any), a piece overhead to
## feet a crouch under it and up.
static func _near_walk(geo: LevelGeometry, a: int, b: int) -> Array:
	var width := geo.width
	var x0 := minf(a % width, b % width) + .5
	var x1 := maxf(a % width, b % width) + .5
	var y0 := minf(a / width, b / width) + .5
	var y1 := maxf(a / width, b / width) + .5
	var r := LevelGeometry.NAV_BODY
	var out: Array = []
	var lowest := INF
	for c: int in [a, b]:
		var floors: Array[LevelGeometry.Slab] = []
		var in_way: Array = []
		var overhead: Array = []
		if geo.cells[c] != 0:
			for item: Variant in geo._index.get(c, LevelGeometry.NOTHING):
				if item is LevelGeometry.Slab:
					var s: LevelGeometry.Slab = item
					if s.x0 - r <= x1 and s.x1 + r >= x0 and s.y0 - r <= y1 and s.y1 + r >= y0:
						in_way.append(s)
						var low := s.top_min()
						lowest = minf(
							lowest, -INF if s.thick < 0.0 else low - s.thick - LevelGeometry.BODY
						)
						if s.walk and s.x0 <= x1 and s.x1 >= x0 and s.y0 <= y1 and s.y1 >= y0:
							floors.append(s)
							lowest = minf(lowest, low - LevelGeometry.STEP - .002)
				else:
					var seg: LevelGeometry.Segment = item
					var reach := r + seg.half
					if (
						minf(seg.ax, seg.bx) - reach <= x1
						and maxf(seg.ax, seg.bx) + reach >= x0
						and minf(seg.ay, seg.by) - reach <= y1
						and maxf(seg.ay, seg.by) + reach >= y0
					):
						in_way.append(seg)
						lowest = minf(lowest, seg.z0 - LevelGeometry.BODY)
			for item: Variant in geo._over.get(c, LevelGeometry.NOTHING):
				if item is LevelGeometry.Slab:
					var s: LevelGeometry.Slab = item
					if s.x0 <= x1 and s.x1 >= x0 and s.y0 <= y1 and s.y1 >= y0:
						overhead.append(s)
						lowest = minf(lowest, s.top_min() - s.thick - LevelGeometry.CROUCH)
				else:
					var ceiling: LevelGeometry.Ceiling = item
					if (
						ceiling.x0 <= x1
						and ceiling.x1 >= x0
						and ceiling.y0 <= y1
						and ceiling.y1 >= y0
					):
						overhead.append(ceiling)
						lowest = minf(lowest, ceiling.z - LevelGeometry.CROUCH)
		out.append(floors)
		out.append(in_way)
		out.append(overhead)
	out.append(lowest)
	return out
