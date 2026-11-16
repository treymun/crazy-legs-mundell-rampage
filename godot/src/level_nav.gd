## The nav graph's building, moved out of level_geometry.gd: the walkable
## places of a level with geometry as nodes and edges for FlowField
## (build_nav(), which LevelGeometry.nav() keeps), the ladders' ends on it
## (ladder_nodes()) and whether a node can be stood on (stands()). The graph
## itself is LevelGeometry.NavGraph (nav_graph.gd).
class_name LevelNav
extends RefCounted


## The graph (nav()): the nodes, edges and order it was always built with
## (tools/load_reference.gd keeps that build; load_check.gd holds this one to
## it) in a fraction of the time: the arrays read through locals, the
## orthogonal edges gathered as pairs in the order found and laid out once
## (no list per node copied at every append), the diagonals written straight in.
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
	var pair_n := PackedInt32Array()
	var pair_m := PackedInt32Array()
	var geo_cells := geo.cells
	var dx := PackedInt32Array([1, -1, 0, 0])
	var dy := PackedInt32Array([0, 0, 1, -1])
	# Each cell's steps to the cells beside it (E 1, W 2, S 4, N 8), for the
	# diagonals' quick way (_diagonals).
	var masks := PackedByteArray()
	masks.resize(n_cells)
	masks.fill(0)
	var bit := PackedByteArray([1, 2, 4, 8])
	var back_bit := PackedByteArray([2, 1, 8, 4])
	var walked := {}
	for n in count:
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
					or (walks(geo, lv, g, n, c2, walked) and walks(geo, lv, g, c2, n, walked))
				)
			):
				pair_n.append(n)
				pair_m.append(c2)
				if n < n_cells:
					masks[n] |= bit[d]
					masks[c2] |= back_bit[d]
			var decks: Variant = over.get(c2)
			if decks != null:
				for m: int in decks:
					if (
						m >= n
						and walks(geo, lv, g, n, m, walked)
						and walks(geo, lv, g, m, n, walked)
					):
						pair_n.append(n)
						pair_m.append(m)
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
	diagonals(geo, lv, g, masks)
	return g


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
## steps to the cells beside it (E 1, W 2, S 4, N 8).
static func diagonals(
	geo: LevelGeometry, lv: LevelData, g: LevelGeometry.NavGraph, masks: PackedByteArray
) -> void:
	var count := g.count
	var n_cells := g.cells
	var w := geo.width
	var cell := g.cell
	var z := g.z
	var first := g.first
	var edges := g.edges
	var links := g.links
	# The corner asked last and once: (corner, feet) -> whether it is blocked.
	# The same answers in the same order as asking it all each time.
	var corners := {}
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
	var dfirst := PackedInt32Array()
	dfirst.resize(count + 1)
	var dedges := PackedInt32Array()
	var reach := LevelGeometry.NAV_BODY * .6
	for n in count:
		var start := dedges.size()
		dfirst[n] = start
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
					blocked = geo.static_blocked(lv, at.x, at.y, reach, at.z, LevelGeometry.BODY)
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
					blocked = geo.static_blocked(lv, at.x, at.y, reach, at.z, LevelGeometry.BODY)
					corners[at] = blocked
				if blocked:
					continue
				dedges.append(m)
	dfirst[count] = dedges.size()
	g.dfirst = dfirst
	g.dedges = dedges


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


## Whether a body walks from node n's middle to node m's (sub-stepped: the
## enemies' rule, the grid's own steps free, slabs at most STEP up, nothing in
## the way at the body's height, headroom for a crouch).
## `memo`: what has been asked at a point (on a sixteenth of a cell) at a
## height, so a walk back over the same points asks nothing again.
static func walks(
	geo: LevelGeometry, lv: LevelData, g: LevelGeometry.NavGraph, n: int, m: int, memo: Dictionary
) -> bool:
	var a := g.cell[n]
	var b := g.cell[m]
	var width := geo.width
	var ax := a % width + .5
	var ay := a / width + .5
	var bx := b % width + .5
	var by := b / width + .5
	var feet := g.z[n]
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
		var floors: Dictionary = {}
		var stood: Dictionary = {}
		var fx := x * 16.0
		var fy := y * 16.0
		var keep := fx == floorf(fx) and fy == floorf(fy)
		if keep:
			var point := (int(fy) * across + int(fx)) * 2
			var known: Variant = memo.get(point)
			if known == null:
				memo[point] = floors
				memo[point + 1] = stood
			else:
				floors = known
				stood = memo[point + 1]
		var floor_z: float
		var was: Variant = floors.get(feet) if keep else null
		if was != null:
			floor_z = was
		else:
			floor_z = geo.floor_at(x, y, feet, lv.ground[c], true)
			if keep:
				floors[feet] = floor_z
		if floor_z > feet + LevelGeometry.STEP + .002 and floor_z > lv.ground[c] + .001:
			return false
		feet = floor_z
		var stands: Variant = stood.get(feet) if keep else null
		if stands == null:
			stands = (
				not geo.static_blocked(lv, x, y, LevelGeometry.NAV_BODY, feet, LevelGeometry.BODY)
				and (
					minf(geo.ceiling_at(x, y, feet), LevelGeometry._roof(lv, c, feet)) - feet
					>= LevelGeometry.CROUCH
				)
			)
			if keep:
				stood[feet] = stands
		if not stands:
			return false
	return absf(feet - g.z[m]) < .06
