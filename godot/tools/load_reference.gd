## The level load's work done the slow way it was done before the load was
## made faster: tools/load_check.gd holds what the game makes now to these,
## level by level (the nav graph node for node and edge for edge, the plane
## bounds box for box, the grids number for number).
extends RefCounted


## A list of numbers as LevelData read it, one at a time through _int/_float.
static func ints(values: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(len(values))
	for i in len(values):
		out[i] = LevelData._int(values[i])
	return out


static func floats(values: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(len(values))
	for i in len(values):
		out[i] = LevelData._float(values[i])
	return out


## The walls' runs merged as LevelLoad.merge_runs merged them before its
## keys were joined once a piece.
static func merge_runs(lv: LevelData) -> void:
	var tiled := {}
	for name: String in LevelTiles.TILED:
		if lv.tile_index.has(name):
			tiled[LevelData._int(lv.tile_index[name])] = true
	var out := PackedFloat32Array()
	var by_end := {}
	var by_start := {}
	for i in lv.wall_count:
		var o := i * LevelData.WALL_STRIDE
		var a := Vector2(lv.walls[o], lv.walls[o + 1])
		var b := Vector2(lv.walls[o + 2], lv.walls[o + 3])
		var step := b - a
		var whole := a == a.floor() and b == b.floor() and (step.x == 0.0 or step.y == 0.0)
		if not tiled.has(int(lv.walls[o + 4])) or not whole or step == Vector2.ZERO:
			for k in LevelData.WALL_STRIDE:
				out.append(lv.walls[o + k])
			continue
		var kind := (
			"%s|%s|%s|%s|%s|%s"
			% [
				step.normalized(),
				lv.walls[o + 4],
				lv.walls[o + 5],
				lv.walls[o + 6],
				lv.walls[o + 7],
				lv.walls[o + 8]
			]
		)
		var after := "%s|%s" % [a, kind]
		var before := "%s|%s" % [b, kind]
		if by_end.has(after):
			# This piece carries on from the end of a run: the run reaches b.
			var r: int = by_end[after]
			by_end.erase(after)
			out[r + 2] = b.x
			out[r + 3] = b.y
			by_end["%s|%s" % [b, kind]] = r
		elif by_start.has(before):
			# A run starts where this piece ends: the run starts at a now.
			var r: int = by_start[before]
			by_start.erase(before)
			out[r] = a.x
			out[r + 1] = a.y
			by_start["%s|%s" % [a, kind]] = r
		else:
			var r := out.size()
			for k in LevelData.WALL_STRIDE:
				out.append(lv.walls[o + k])
			by_end["%s|%s" % [b, kind]] = r
			by_start["%s|%s" % [a, kind]] = r
	lv.walls = out
	lv.wall_count = out.size() / LevelData.WALL_STRIDE


## The nav graph as LevelNav.build_nav built it before it was made
## faster.
static func nav(geo: LevelGeometry, lv: LevelData) -> LevelGeometry.NavGraph:
	var g := LevelGeometry.NavGraph.new()
	var n_cells := geo.width * geo.height
	g.cells = n_cells
	g.cell.resize(n_cells)
	g.z.resize(n_cells)
	for c in n_cells:
		g.cell[c] = c
		g.z[c] = lv.ground[c]
	var extra_cell := PackedInt32Array()
	var extra_z := PackedFloat32Array()
	for s in geo.slabs:
		if not s.walk:
			continue
		for cy in range(maxi(0, floori(s.y0)), mini(geo.height - 1, floori(s.y1)) + 1):
			for cx in range(maxi(0, floori(s.x0)), mini(geo.width - 1, floori(s.x1)) + 1):
				var mx := cx + .5
				var my := cy + .5
				var c := cy * geo.width + cx
				if not s.inside(mx, my) or lv.solid[c] >= 0:
					continue
				var top := s.top_at(mx, my)
				if s.thick < 0.0 or top - lv.ground[c] <= LevelGeometry.STEP:
					# Solid down to the ground (or nearly the floor): the cell's floor.
					g.z[c] = maxf(g.z[c], top)
					continue
				var dup := false
				var list: Array = g.over.get(c, [])
				for k: int in list:
					if absf(extra_z[k - n_cells] - top) < .05:
						dup = true
				if dup:
					continue
				list.append(n_cells + extra_cell.size())
				g.over[c] = list
				extra_cell.append(c)
				extra_z.append(top)
	g.cell.append_array(extra_cell)
	g.z.append_array(extra_z)
	g.count = g.cell.size()
	var orth: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	var lists: Array[PackedInt32Array] = []
	lists.resize(g.count)
	for n in g.count:
		lists[n] = PackedInt32Array()
	for n in g.count:
		var c := g.cell[n]
		var cx := c % geo.width
		var cy := c / geo.width
		for d: Vector2i in orth:
			var nx := cx + d.x
			var ny := cy + d.y
			if nx < 0 or ny < 0 or nx >= geo.width or ny >= geo.height:
				continue
			var c2 := ny * geo.width + nx
			var plain := n < n_cells and geo.cells[c] == 0 and geo.cells[c2] == 0
			var them := PackedInt32Array([c2])
			for m: int in g.over.get(c2, []):
				them.append(m)
			for m in them:
				if m < n:
					continue
				if plain and m < n_cells:
					# Far from every piece: the grid's own rule (heights not
					# asked), as the flow fields always had it.
					lists[n].append(m)
					lists[m].append(n)
				elif walks(geo, lv, g, n, m) and walks(geo, lv, g, m, n):
					lists[n].append(m)
					lists[m].append(n)
	for i in geo.ladders.size():
		var ends := LevelNav.ladder_nodes(geo, g, geo.ladders[i])
		g.ladder_ends.append(ends)
		if ends.x >= 0 and not lists[ends.x].has(ends.y):
			lists[ends.x].append(ends.y)
			lists[ends.y].append(ends.x)
			g.links[ends.x * g.count + ends.y] = i
			g.links[ends.y * g.count + ends.x] = i
	g.first.resize(g.count + 1)
	var total := 0
	for n in g.count:
		g.first[n] = total
		total += lists[n].size()
	g.first[g.count] = total
	for n in g.count:
		g.edges.append_array(lists[n])
	# Diagonals: n to m when each side cell leads from n to m.
	g.dfirst.resize(g.count + 1)
	var dtotal := 0
	var dlists: Array[PackedInt32Array] = []
	# (Read straight from the lists, not through around()'s copies; the
	# corner asked last and once: (corner, feet) -> whether it is blocked.
	# The same answers in the same order as asking it all each time, in a
	# third of the time.)
	var corners := {}
	# Each node's cell's column and row, and whether a ladder joins it.
	var col := PackedInt32Array()
	var row := PackedInt32Array()
	col.resize(g.count)
	row.resize(g.count)
	for n in g.count:
		col[n] = g.cell[n] % geo.width
		row[n] = g.cell[n] / geo.width
	var laddered := PackedByteArray()
	laddered.resize(g.count)
	for ends: Vector2i in g.ladder_ends:
		if ends.x >= 0:
			laddered[ends.x] = 1
			laddered[ends.y] = 1
	for n in g.count:
		var found := PackedInt32Array()
		var cx := col[n]
		var cy := row[n]
		var n0 := g.first[n]
		var n1 := g.first[n + 1]
		for i in range(n0, n1):
			var a := g.edges[i]
			if laddered[n] == 1 and g.links.has(n * g.count + a):
				continue
			var ca := g.cell[a]
			for j in range(g.first[a], g.first[a + 1]):
				var m := g.edges[j]
				if absi(col[m] - cx) != 1 or absi(row[m] - cy) != 1:
					continue
				if laddered[a] == 1 and g.links.has(a * g.count + m):
					continue
				if found.has(m):
					continue
				# The other side's cell leads from n to m too.
				var side := false
				for k in range(n0, n1):
					var b := g.edges[k]
					if b != a and g.cell[b] != ca and LevelNav.joins(g, b, m):
						side = true
						break
				if not side:
					continue
				# Never past the corner the two cells share when something stands
				# on it (a porch post on a cell corner): a body cutting the corner
				# would wedge on it.
				var at := Vector3(
					(cx + col[m] + 1) * .5, (cy + row[m] + 1) * .5, minf(g.z[n], g.z[m])
				)
				var blocked: Variant = corners.get(at)
				if blocked == null:
					blocked = geo.static_blocked(
						lv, at.x, at.y, LevelGeometry.NAV_BODY * .6, at.z, LevelGeometry.BODY
					)
					corners[at] = blocked
				if blocked:
					continue
				found.append(m)
		dlists.append(found)
		g.dfirst[n] = dtotal
		dtotal += found.size()
	g.dfirst[g.count] = dtotal
	for n in g.count:
		g.dedges.append_array(dlists[n])
	return g


## A body's walk from node n's middle to node m's as the nav build asked it
## before its answers were kept (LevelGeometry._walks).
static func walks(
	geo: LevelGeometry, lv: LevelData, g: LevelGeometry.NavGraph, n: int, m: int
) -> bool:
	var width := geo.width
	var a := g.cell[n]
	var b := g.cell[m]
	var ax := a % width + .5
	var ay := a / width + .5
	var bx := b % width + .5
	var by := b / width + .5
	var feet := g.z[n]
	for k in range(1, LevelGeometry.NAV_STEPS + 1):
		var f := float(k) / LevelGeometry.NAV_STEPS
		var x := ax + (bx - ax) * f
		var y := ay + (by - ay) * f
		var c := int(y) * width + int(x)
		var floor_z := geo.floor_at(x, y, feet, lv.ground[c], true)
		if floor_z > feet + LevelGeometry.STEP + .002 and floor_z > lv.ground[c] + .001:
			return false
		feet = floor_z
		if geo.static_blocked(lv, x, y, LevelGeometry.NAV_BODY, feet, LevelGeometry.BODY):
			return false
		var roof := LevelGeometry._roof(lv, c, feet)
		if minf(geo.ceiling_at(x, y, feet), roof) - feet < LevelGeometry.CROUCH:
			return false
	return absf(feet - g.z[m]) < .06


## The plane bounds as LevelData._build_plane_bounds made them before it read
## a row's run of one height at a time (the reference load_check holds it to).
static func plane_bounds(lv: LevelData) -> void:
	var buckets := {}
	for i in lv.ground.size():
		var h := lv.ground[i]
		var y := i / lv.width
		var x := i - y * lv.width
		var b: Variant = buckets.get(h)
		if b == null:
			buckets[h] = [x, y, x + 1, y + 1]
		else:
			if x < b[0]:
				b[0] = x
			if y < b[1]:
				b[1] = y
			if x + 1 > b[2]:
				b[2] = x + 1
			if y + 1 > b[3]:
				b[3] = y + 1
	lv.floor_bounds = {}
	# Python inserts floors nearest-first (reversed sorted heights).
	var heights := Array(lv.ground_heights)
	heights.sort()
	heights.reverse()
	for hh: float in heights:
		var b: Variant = buckets.get(hh)
		var extra: Array = lv.caps.get(hh, [])
		if b == null and extra.is_empty():
			continue
		var x0 := 1 << 30
		var y0 := 1 << 30
		var x1 := -(1 << 30)
		var y1 := -(1 << 30)
		if b != null:
			x0 = b[0]
			y0 = b[1]
			x1 = b[2]
			y1 = b[3]
		for c: Variant in extra:
			x0 = mini(x0, LevelData._int(c[0]))
			y0 = mini(y0, LevelData._int(c[1]))
			x1 = maxi(x1, LevelData._int(ceil(c[2])))
			y1 = maxi(y1, LevelData._int(ceil(c[3])))
		lv.floor_bounds[hh] = Vector4i(x0, y0, x1, y1)

	var roof_buckets := {}
	for i in lv.roof.size():
		var h := lv.roof[i]
		if h <= 0.0:
			continue
		var y := i / lv.width
		var x := i - y * lv.width
		var b: Variant = roof_buckets.get(h)
		if b == null:
			roof_buckets[h] = [x, y, x + 1, y + 1]
		else:
			if x < b[0]:
				b[0] = x
			if y < b[1]:
				b[1] = y
			if x + 1 > b[2]:
				b[2] = x + 1
			if y + 1 > b[3]:
				b[3] = y + 1
	lv.roof_bounds = {}
	var rheight := Array(lv.roof_heights)
	rheight.sort()
	for hh: float in rheight:
		var b: Variant = roof_buckets.get(hh)
		var over: Array = lv.roof_caps.get(hh, [])
		if b == null and over.is_empty():
			continue
		var r := Vector4i(1 << 30, 1 << 30, -(1 << 30), -(1 << 30))
		if b != null:
			r = Vector4i(
				LevelData._int(b[0]),
				LevelData._int(b[1]),
				LevelData._int(b[2]),
				LevelData._int(b[3])
			)
		for c: Variant in over:
			r = Vector4i(
				mini(r.x, LevelData._int(c[0])),
				mini(r.y, LevelData._int(c[1])),
				maxi(r.z, LevelData._int(ceil(c[2]))),
				maxi(r.w, LevelData._int(ceil(c[3])))
			)
		lv.roof_bounds[hh] = r
	lv.floor_boxes = _tight_boxes(lv, lv.floor_bounds, lv.ground, lv.caps)
	lv.roof_boxes = _tight_boxes(lv, lv.roof_bounds, lv.roof, lv.roof_caps)


## The planes the renderer walks: [height, box] in the bounds' order. A height
## whose cells are scattered across a big box (a creek, a few porch roofs) is
## cut into tight boxes, so the pixels between them are not tested for it.
static func _tight_boxes(
	lv: LevelData, bounds: Dictionary, grid: PackedFloat32Array, capped: Dictionary
) -> Array:
	var out: Array = []
	for h: float in bounds:
		var box: Vector4i = bounds[h]
		var area := (box.z - box.x) * (box.w - box.y)
		var count := 0
		for y in range(maxi(0, box.y), mini(lv.height, box.w)):
			for x in range(maxi(0, box.x), mini(lv.width, box.z)):
				if grid[y * lv.width + x] == h:
					count += 1
		if capped.has(h) or area <= 64 or count * 2 >= area:
			out.append([h, box])
			continue
		for ty in range(box.y, box.w, 8):
			for tx in range(box.x, box.z, 8):
				var x0 := 1 << 30
				var y0 := 1 << 30
				var x1 := -1
				var y1 := -1
				for y in range(ty, mini(box.w, ty + 8)):
					for x in range(tx, mini(box.z, tx + 8)):
						if grid[y * lv.width + x] == h:
							x0 = mini(x0, x)
							y0 = mini(y0, y)
							x1 = maxi(x1, x + 1)
							y1 = maxi(y1, y + 1)
				if x1 >= 0:
					out.append([h, Vector4i(x0, y0, x1, y1)])
	return out
