## The real pieces a broken thing comes apart into (features/wreckage.gd
## throws them, view3d/wreck_layer.gd draws them): cut from the thing's own
## look, so a piece in the air is the part of it that was there.
##
## A key names what is cut and how: "<source>|<recipe>". The source is
## m:<model> (a prop's baked model, assets3d/props: its triangles cut up and
## drawn with its own baked texture), p:<picture> (a board or a sprite's
## picture: boxes with the picture on their faces) or t:<tile>@<w>,<h> (a wall
## tile on a face w wide and h tall: a fence's planks, a window's glass). The
## recipe (breakables.cfg `pieces`):
##
##   boards:n         each side of a box-like model in n boards (crates, the
##                    outhouse's walls and roof)
##   staves:n[,x,y,r] a barrel's side in n staves round its upright axis (at
##                    x, y with radius r; the model's middle otherwise), its
##                    lids, two hoops; whatever stands off the barrel in chunks
##   grid:a,b,c       a model in a by b by c chunks (jugs, jars, tin, a bear)
##   table:n          a table's top in n planks, the legs and benches below in
##                    four chunks
##   planks:c,r       a picture (or a tile) in c by r boards
##   fence:n,v...     a fence tile in n upright boards and a rail at each v
##                    (a share of the height down from its top)
##   shards:n,u0,u1,z0,z1  a window's glass (from u0 to u1 across the face,
##                    z0 to z1 up it) in n by n panes, each two triangles
##
## Each piece is a Part: a box the physics tumbles (half sizes about its
## middle, its turn in the source's frame) and its faces about its middle in
## its own axes. Map axes throughout (x, y across, z up); a model's own axes
## (Godot's, y up) are swapped as it is read. A model's frame has its foot's
## middle at the origin and its front toward +y; a picture's or a tile's runs
## x along it (left to right as drawn), y through it, z up, its foot's middle
## at the origin. Cut once a key and kept.
class_name WreckCuts
extends RefCounted

const PROPS := "res://assets3d/props"
## How thick a cut shell is made (the inside face set in by this) and the
## thinnest a piece's box may be (half).
const SHELL := .03
const THIN := .012
## A piece with less in it than this (the area of its faces) is dropped.
const SMALL := .004


## One piece: its box and its faces.
class Part:
	## Its middle and its turn in the source's frame; its box's half sizes.
	var centre := Vector3.ZERO
	var basis := Basis.IDENTITY
	var half := Vector3(.05, .05, .05)
	## Its faces about its middle in its own axes, three corners a triangle.
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()


## A soup of triangles being cut: corners, normals, texture places.
class Soup:
	var p := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()

	func add(a: Soup, i: int) -> void:
		p.append(a.p[i])
		n.append(a.n[i])
		uv.append(a.uv[i])

	func size() -> int:
		return p.size()

	## Each triangle's bounds (lo, hi), made once.
	var lo := PackedVector3Array()
	var hi := PackedVector3Array()

	func measure() -> void:
		if lo.size() == p.size() / 3:
			return
		lo.resize(p.size() / 3)
		hi.resize(p.size() / 3)
		for t in p.size() / 3:
			var a := p[t * 3]
			var b := p[t * 3 + 1]
			var c := p[t * 3 + 2]
			lo[t] = Vector3(
				minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)), minf(a.z, minf(b.z, c.z))
			)
			hi[t] = Vector3(
				maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)), maxf(a.z, maxf(b.z, c.z))
			)

	func bounds() -> AABB:
		if p.is_empty():
			return AABB()
		var box := AABB(p[0], Vector3.ZERO)
		for q: Vector3 in p:
			box = box.expand(q)
		return box


static var _cache := {}
static var _soups := {}


## The pieces a key cuts into (empty when there is nothing to cut).
static func parts(assets: Assets, key: String) -> Array:
	var cached: Variant = _cache.get(key)
	if cached != null:
		var known: Array = cached
		return known
	var out: Array = []
	var bar := key.find("|")
	if bar > 0:
		var source := key.left(bar)
		var recipe := key.substr(bar + 1)
		var name := recipe.get_slice(":", 0)
		var args := _numbers(recipe.get_slice(":", 1) if recipe.contains(":") else "")
		if source.begins_with("m:"):
			var soup := _model(source.substr(2))
			if soup.size() > 0:
				out = _cut_model(soup, name, args)
		elif source.begins_with("p:"):
			out = _cut_picture(assets, source.substr(2), name, args)
		elif source.begins_with("t:"):
			out = _cut_tile(source.substr(2), name, args)
	_cache[key] = out
	return out


static func _numbers(text: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if text.strip_edges() == "":
		return out
	for item: String in text.split(","):
		out.append(item.to_float())
	return out


static func _arg(args: PackedFloat32Array, i: int, fallback: float) -> float:
	return args[i] if i < args.size() else fallback


# ------------------------------------------------------------------ sources


## A prop model's triangles in map axes (its foot's middle at the origin).
static func _model(name: String) -> Soup:
	var cached: Variant = _soups.get(name)
	if cached != null:
		var known: Soup = cached
		return known
	var soup := Soup.new()
	var path := PROPS.path_join(name + ".glb")
	if ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		if scene != null:
			var root := scene.instantiate()
			var found: Array = []
			_meshes(root, Transform3D.IDENTITY, found)
			for item: Array in found:
				var mesh: Mesh = item[0]
				var xf: Transform3D = item[1]
				_read(mesh, xf, soup)
			root.free()
	_soups[name] = soup
	return soup


static func _meshes(node: Node, xf: Transform3D, out: Array) -> void:
	var here := xf
	if node is Node3D:
		here = xf * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh != null:
			out.append([mesh, here])
	for child in node.get_children():
		_meshes(child, here, out)


static func _read(mesh: Mesh, xf: Transform3D, soup: Soup) -> void:
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if index.is_empty():
			index.resize(verts.size())
			for i in verts.size():
				index[i] = i
		for i in index:
			var v := xf * verts[i]
			var nv := (xf.basis * (normals[i] if i < normals.size() else Vector3.UP)).normalized()
			soup.p.append(Vector3(v.x, v.z, v.y))
			soup.n.append(Vector3(nv.x, nv.z, nv.y))
			soup.uv.append(uvs[i] if i < uvs.size() else Vector2.ZERO)


# ------------------------------------------------------------------ models


## A model cut by a recipe.
static func _cut_model(soup: Soup, recipe: String, args: PackedFloat32Array) -> Array:
	var box := soup.bounds()
	var tris := soup.size() / 3
	# Which group each triangle falls in, and each group's cells (planes).
	var group := PackedInt32Array()
	group.resize(tris)
	var cells: Array = []
	match recipe:
		"boards":
			_boards(soup, box, maxi(1, int(_arg(args, 0, 3.0))), group, cells)
		"staves":
			_staves(soup, box, args, group, cells)
		"table":
			_table(soup, box, maxi(1, int(_arg(args, 0, 3.0))), group, cells)
		_:
			var counts := Vector3i(
				maxi(1, int(_arg(args, 0, 2.0))),
				maxi(1, int(_arg(args, 1, 2.0))),
				maxi(1, int(_arg(args, 2, 2.0)))
			)
			_grid_cells(box, counts, 0, cells)
	var out: Array = []
	for cell: Dictionary in cells:
		var piece := _clip_cell(soup, group, cell)
		if piece.size() < 3 or _area(piece) < SMALL:
			continue
		var outward: float = cell.get("out", 0.0)
		if outward > 0.0:
			_swell(piece, cell, outward)
		out.append(_part(piece, cell, true))
	return out


## Each triangle to the side of the box its middle is nearest; each side in n
## boards (the walls across their height, the top and the bottom along their
## longer way).
static func _boards(soup: Soup, box: AABB, n: int, group: PackedInt32Array, cells: Array) -> void:
	var lo := box.position
	var hi := box.end
	for t in group.size():
		var c := (soup.p[t * 3] + soup.p[t * 3 + 1] + soup.p[t * 3 + 2]) / 3.0
		var near := [c.x - lo.x, hi.x - c.x, c.y - lo.y, hi.y - c.y, c.z - lo.z, hi.z - c.z]
		var best := 0
		for k in 6:
			var d: float = near[k]
			var was: float = near[best]
			if d < was:
				best = k
		group[t] = best
	for side in 6:
		var up := side >= 4
		var axis := 2
		if up:
			axis = 0 if box.size.x >= box.size.y else 1
		for k in n:
			var a := lo[axis] + box.size[axis] * k / n
			var b := lo[axis] + box.size[axis] * (k + 1) / n
			(
				cells
				. append(
					{
						"group": side,
						"planes": _slab(axis, a, b),
						"shell":
						[
							Vector3(-1, 0, 0),
							Vector3(1, 0, 0),
							Vector3(0, -1, 0),
							Vector3(0, 1, 0),
							Vector3(0, 0, -1),
							Vector3(0, 0, 1)
						][side],
					}
				)
			)


## Planes keeping a ≤ p[axis] ≤ b.
static func _slab(axis: int, a: float, b: float) -> Array:
	var n := Vector3.ZERO
	n[axis] = 1.0
	return [[-n, -a], [n, b]]


## A barrel: staves round its axis, its lids, two hoops, the rest in chunks.
static func _staves(
	soup: Soup, box: AABB, args: PackedFloat32Array, group: PackedInt32Array, cells: Array
) -> void:
	var n := maxi(3, int(_arg(args, 0, 8.0)))
	var mid := box.get_center()
	var axis := Vector2(_arg(args, 1, mid.x), _arg(args, 2, mid.y))
	var radius := _arg(args, 3, minf(box.size.x, box.size.y) * .5)
	# The barrel's own height: its side's triangles' reach up.
	var low := INF
	var high := -INF
	for t in group.size():
		var c := (soup.p[t * 3] + soup.p[t * 3 + 1] + soup.p[t * 3 + 2]) / 3.0
		if Vector2(c.x, c.y).distance_to(axis) <= radius * 1.15:
			low = minf(low, minf(soup.p[t * 3].z, minf(soup.p[t * 3 + 1].z, soup.p[t * 3 + 2].z)))
			high = maxf(high, maxf(soup.p[t * 3].z, maxf(soup.p[t * 3 + 1].z, soup.p[t * 3 + 2].z)))
	if low > high:
		_grid_cells(box, Vector3i(2, 2, 2), 0, cells)
		return
	var tall := high - low
	var others := false
	for t in group.size():
		var c := (soup.p[t * 3] + soup.p[t * 3 + 1] + soup.p[t * 3 + 2]) / 3.0
		var nz := absf((soup.n[t * 3] + soup.n[t * 3 + 1] + soup.n[t * 3 + 2]).normalized().z)
		if Vector2(c.x, c.y).distance_to(axis) > radius * 1.15 or c.z > high + .02:
			group[t] = 3
			others = true
		elif nz > .7 and c.z > high - tall * .12:
			group[t] = 1
		elif nz > .7 and c.z < low + tall * .12:
			group[t] = 2
		else:
			group[t] = 0
	var centre := Vector3(axis.x, axis.y, 0.0)
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var d0 := Vector3(cos(a0), sin(a0), 0.0)
		var d1 := Vector3(cos(a1), sin(a1), 0.0)
		var n0 := Vector3(d0.y, -d0.x, 0.0)
		var n1 := Vector3(-d1.y, d1.x, 0.0)
		var am := (a0 + a1) * .5
		var r := Vector3(cos(am), sin(am), 0.0)
		(
			cells
			. append(
				{
					"group": 0,
					"planes": [[n0, n0.dot(centre)], [n1, n1.dot(centre)]],
					"basis": Basis(Vector3(sin(am), -cos(am), 0.0), r, Vector3(0.0, 0.0, 1.0)),
					"shell": r,
				}
			)
		)
	cells.append({"group": 1, "planes": []})
	cells.append({"group": 2, "planes": []})
	for band: Vector2 in [Vector2(.18, .26), Vector2(.74, .82)]:
		(
			cells
			. append(
				{
					"group": 0,
					"planes": _slab(2, low + tall * band.x, low + tall * band.y),
					"out": 1.06,
					"axis": centre,
				}
			)
		)
	if others:
		_grid_cells(box, Vector3i(2, 2, 1), 3, cells)


## A table: the top in n planks along its longer way, what is below it in four.
static func _table(soup: Soup, box: AABB, n: int, group: PackedInt32Array, cells: Array) -> void:
	var top := box.end.z - maxf(.08, box.size.z * .12)
	for t in group.size():
		var c := (soup.p[t * 3] + soup.p[t * 3 + 1] + soup.p[t * 3 + 2]) / 3.0
		group[t] = 1 if c.z > top else 0
	var axis := 0 if box.size.x >= box.size.y else 1
	var across := 1 - axis
	for k in n:
		var a := box.position[across] + box.size[across] * k / n
		var b := box.position[across] + box.size[across] * (k + 1) / n
		cells.append({"group": 1, "planes": _slab(across, a, b), "shell": Vector3(0, 0, 1)})
	var low := AABB(box.position, Vector3(box.size.x, box.size.y, top - box.position.z))
	_grid_cells(low, Vector3i(2, 2, 1), 0, cells)


static func _grid_cells(box: AABB, counts: Vector3i, in_group: int, cells: Array) -> void:
	for i in counts.x:
		for j in counts.y:
			for k in counts.z:
				var planes: Array = []
				var at := Vector3i(i, j, k)
				for axis in 3:
					var a := box.position[axis] + box.size[axis] * at[axis] / counts[axis]
					var b := box.position[axis] + box.size[axis] * (at[axis] + 1) / counts[axis]
					# The outermost cells reach past the box (nothing is lost).
					if at[axis] == 0:
						a -= 1.0
					if at[axis] == counts[axis] - 1:
						b += 1.0
					planes.append_array(_slab(axis, a, b))
				cells.append({"group": in_group, "planes": planes})


## The triangles of `group` inside the cell's planes, cut where they cross.
static func _clip_cell(soup: Soup, group: PackedInt32Array, cell: Dictionary) -> Soup:
	var out := Soup.new()
	var want: int = cell.get("group", 0)
	var planes: Array = cell.get("planes", [])
	var normals := PackedVector3Array()
	var ds := PackedFloat32Array()
	# The cell's box, from its planes along the axes (a wedge's are not).
	var lo := Vector3(-INF, -INF, -INF)
	var hi := Vector3(INF, INF, INF)
	for plane: Array in planes:
		var pn: Vector3 = plane[0]
		var pd: float = plane[1]
		normals.append(pn)
		ds.append(pd)
		for axis in 3:
			if absf(pn[axis]) > .999:
				if pn[axis] > 0.0:
					hi[axis] = minf(hi[axis], pd)
				else:
					lo[axis] = maxf(lo[axis], -pd)
	soup.measure()
	for t in group.size():
		if group[t] != want:
			continue
		var tlo := soup.lo[t]
		var thi := soup.hi[t]
		if (
			thi.x < lo.x
			or thi.y < lo.y
			or thi.z < lo.z
			or tlo.x > hi.x
			or tlo.y > hi.y
			or tlo.z > hi.z
		):
			continue
		# Wholly inside every plane: as it is; wholly outside one: not here.
		var a := soup.p[t * 3]
		var b := soup.p[t * 3 + 1]
		var c := soup.p[t * 3 + 2]
		var inside := true
		var outside := false
		for k in normals.size():
			var pn := normals[k]
			var da := pn.dot(a) - ds[k]
			var db := pn.dot(b) - ds[k]
			var dc := pn.dot(c) - ds[k]
			if da > 0.0 and db > 0.0 and dc > 0.0:
				outside = true
				break
			if da > 0.0 or db > 0.0 or dc > 0.0:
				inside = false
		if outside:
			continue
		if inside:
			for k in 3:
				out.add(soup, t * 3 + k)
			continue
		var poly := Soup.new()
		for k in 3:
			poly.add(soup, t * 3 + k)
		var whole := true
		for plane: Array in planes:
			var pn: Vector3 = plane[0]
			var pd: float = plane[1]
			var all_in := true
			for q: Vector3 in poly.p:
				if pn.dot(q) > pd:
					all_in = false
					break
			if all_in:
				continue
			whole = false
			poly = _clip(poly, pn, pd)
			if poly.size() < 3:
				break
		if poly.size() < 3:
			continue
		if whole:
			for k in 3:
				out.add(poly, k)
			continue
		for k in range(1, poly.size() - 1):
			out.add(poly, 0)
			out.add(poly, k)
			out.add(poly, k + 1)
	return out


## A polygon cut by a plane: the part where n.p <= d.
static func _clip(poly: Soup, pn: Vector3, pd: float) -> Soup:
	var out := Soup.new()
	var count := poly.size()
	for i in count:
		var j := (i + 1) % count
		var a := poly.p[i]
		var b := poly.p[j]
		var da := pn.dot(a) - pd
		var db := pn.dot(b) - pd
		if da <= 0.0:
			out.add(poly, i)
		if (da <= 0.0) != (db <= 0.0):
			var t := da / (da - db)
			out.p.append(a.lerp(b, t))
			out.n.append(poly.n[i].lerp(poly.n[j], t).normalized())
			out.uv.append(poly.uv[i].lerp(poly.uv[j], t))
	return out


static func _area(soup: Soup) -> float:
	var total := 0.0
	for t in soup.size() / 3:
		total += (
			(soup.p[t * 3 + 1] - soup.p[t * 3]).cross(soup.p[t * 3 + 2] - soup.p[t * 3]).length()
		)
	return total * .5


## A hoop: the band of the side pushed out from the axis so it rides outside.
static func _swell(piece: Soup, cell: Dictionary, by: float) -> void:
	var c: Vector3 = cell.get("axis", Vector3.ZERO)
	for i in piece.size():
		var q := piece.p[i]
		piece.p[i] = Vector3(c.x + (q.x - c.x) * by, c.y + (q.y - c.y) * by, q.z)


## A Part from a cut soup: its own axes (the cell's), its middle, its box, and
## (a shell) an inside face set in by SHELL so it has a thickness.
static func _part(piece: Soup, cell: Dictionary, shell: bool) -> Part:
	var part := Part.new()
	part.basis = cell.get("basis", Basis.IDENTITY)
	var inverse := part.basis.transposed()
	var faces := piece
	if shell:
		faces = Soup.new()
		var along: Variant = cell.get("shell")
		for i in piece.size():
			faces.add(piece, i)
		for i in piece.size():
			var into := -piece.n[i]
			if along is Vector3:
				var given: Vector3 = along
				into = -given
			faces.p.append(piece.p[i] + into * SHELL)
			faces.n.append(-piece.n[i])
			faces.uv.append(piece.uv[i])
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for q: Vector3 in faces.p:
		var l := inverse * q
		lo = Vector3(minf(lo.x, l.x), minf(lo.y, l.y), minf(lo.z, l.z))
		hi = Vector3(maxf(hi.x, l.x), maxf(hi.y, l.y), maxf(hi.z, l.z))
	var mid_local := (lo + hi) * .5
	part.centre = part.basis * mid_local
	var half := (hi - lo) * .5
	part.half = Vector3(maxf(half.x, THIN), maxf(half.y, THIN), maxf(half.z, THIN))
	for i in faces.size():
		part.verts.append(inverse * faces.p[i] - mid_local)
		part.normals.append(inverse * faces.n[i])
		part.uvs.append(faces.uv[i])
	return part


# ------------------------------------------------------------- pictures, tiles


## A picture cut in boards: [width, height] in its own pixels, its solid
## bounds, and whether a pixel is solid.
static func _cut_picture(
	assets: Assets, image: String, recipe: String, args: PackedFloat32Array
) -> Array:
	if not assets.has_art(image):
		return []
	var art := assets.art(image)
	var w: int = art["w"]
	var h: int = art["h"]
	var data: PackedByteArray = art["data"]
	var solid := PackedByteArray()
	solid.resize(w * h)
	var lo := Vector2i(w, h)
	var hi := Vector2i(-1, -1)
	for y in h:
		for x in w:
			if data[(y * w + x) * 4 + 3] > 100:
				solid[y * w + x] = 1
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	if hi.x < 0:
		return []
	# One unit: the picture's height (a sprite's height is its picture's).
	var unit := 1.0 / h
	var cols := maxi(1, int(_arg(args, 0, 2.0)))
	var rows := maxi(1, int(_arg(args, 1, 2.0)))
	# How thick, as a share of the picture's height (a piece is in picture heights).
	var thick := _arg(args, 2, .05)
	var out: Array = []
	var span := hi - lo + Vector2i.ONE
	if recipe != "planks":
		return out
	for c in cols:
		for r in rows:
			var x0 := lo.x + span.x * c / cols
			var x1 := lo.x + span.x * (c + 1) / cols
			var y0 := lo.y + span.y * r / rows
			var y1 := lo.y + span.y * (r + 1) / rows
			if x1 <= x0 or y1 <= y0:
				continue
			var filled := 0
			for y in range(y0, y1):
				for x in range(x0, x1):
					filled += solid[y * w + x]
			if filled < (x1 - x0) * (y1 - y0) * .4:
				continue
			var rect := Rect2(
				(x0 - w * .5) * unit, (h - y1) * unit, (x1 - x0) * unit, (y1 - y0) * unit
			)
			var tex := Rect2(float(x0) / w, float(y0) / h, float(x1 - x0) / w, float(y1 - y0) / h)
			out.append(board(rect, tex, thick, Vector2(w, h)))
	return out


## A tile on a face `w` wide and `h` tall cut by a recipe.
static func _cut_tile(source: String, recipe: String, args: PackedFloat32Array) -> Array:
	var size := _numbers(source.get_slice("@", 1))
	var w := _arg(size, 0, 1.0)
	var h := _arg(size, 1, 1.0)
	var texels := Vector2(128, 128)
	var out: Array = []
	match recipe:
		"fence":
			var n := maxi(1, int(_arg(args, 0, 6.0)))
			for k in n:
				var rect := Rect2(-w * .5 + w * k / n, 0.0, w / n, h)
				var tex := Rect2(float(k) / n, 0.0, 1.0 / n, 1.0)
				out.append(board(rect, tex, .035, texels))
			for i in range(1, args.size()):
				var v := args[i]
				var rail := Rect2(-w * .5, h * (1.0 - v - .04), w, h * .08)
				var part := board(rail, Rect2(0.0, v - .04, 1.0, .08), .045, texels)
				part.centre.y -= .04
				out.append(part)
		"planks":
			var cols := maxi(1, int(_arg(args, 0, 1.0)))
			var rows := maxi(1, int(_arg(args, 1, 4.0)))
			for c in cols:
				for r in rows:
					var rect := Rect2(
						-w * .5 + w * c / cols, h - h * (r + 1) / rows, w / cols, h / rows
					)
					var tex := Rect2(float(c) / cols, float(r) / rows, 1.0 / cols, 1.0 / rows)
					out.append(board(rect, tex, .035, texels))
		"shards":
			out = _shards(w, args)
	return out


## A board: a box `thick` through, `rect` its face in its frame's x (along)
## and z (up), the picture's `tex` (shares of it) on its front and back, its
## edges the picture's edge texels.
static func board(rect: Rect2, tex: Rect2, thick: float, texels: Vector2) -> Part:
	var part := Part.new()
	var hx := rect.size.x * .5
	var hz := rect.size.y * .5
	var hy := maxf(thick * .5, THIN)
	part.centre = Vector3(rect.position.x + hx, 0.0, rect.position.y + hz)
	part.half = Vector3(maxf(hx, THIN), hy, maxf(hz, THIN))
	# Texture places a texel in from each edge (texelFetch reads the texel).
	var px := Vector2(.5 / texels.x, .5 / texels.y)
	var u0 := tex.position.x + px.x
	var u1 := tex.end.x - px.x
	var v0 := tex.position.y + px.y
	var v1 := tex.end.y - px.y
	var c: Array[Vector3] = [
		Vector3(-hx, -hy, -hz),
		Vector3(hx, -hy, -hz),
		Vector3(hx, -hy, hz),
		Vector3(-hx, -hy, hz),
		Vector3(-hx, hy, -hz),
		Vector3(hx, hy, -hz),
		Vector3(hx, hy, hz),
		Vector3(-hx, hy, hz),
	]
	# Front (toward -y) and back: the picture, top row up.
	_quad(
		part,
		c[0],
		c[1],
		c[2],
		c[3],
		Vector3(0, -1, 0),
		[Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, v0), Vector2(u0, v0)]
	)
	_quad(
		part,
		c[5],
		c[4],
		c[7],
		c[6],
		Vector3(0, 1, 0),
		[Vector2(u1, v1), Vector2(u0, v1), Vector2(u0, v0), Vector2(u1, v0)]
	)
	# The edges: the picture's edge column or row drawn across them.
	_quad(
		part,
		c[4],
		c[0],
		c[3],
		c[7],
		Vector3(-1, 0, 0),
		[Vector2(u0, v1), Vector2(u0, v1), Vector2(u0, v0), Vector2(u0, v0)]
	)
	_quad(
		part,
		c[1],
		c[5],
		c[6],
		c[2],
		Vector3(1, 0, 0),
		[Vector2(u1, v1), Vector2(u1, v1), Vector2(u1, v0), Vector2(u1, v0)]
	)
	_quad(
		part,
		c[3],
		c[2],
		c[6],
		c[7],
		Vector3(0, 0, 1),
		[Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v0), Vector2(u0, v0)]
	)
	_quad(
		part,
		c[4],
		c[5],
		c[1],
		c[0],
		Vector3(0, 0, -1),
		[Vector2(u0, v1), Vector2(u1, v1), Vector2(u1, v1), Vector2(u0, v1)]
	)
	return part


static func _quad(
	part: Part, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, uv: Array
) -> void:
	var corners := [a, b, c, d]
	for i: int in [0, 1, 2, 0, 2, 3]:
		var q: Vector3 = corners[i]
		var t: Vector2 = uv[i]
		part.verts.append(q)
		part.normals.append(n)
		part.uvs.append(t)


## A window's glass in n by n panes across the face (u0 to u1 of its width w,
## z0 to z1 up), each pane two triangles, its corners shaken a little.
static func _shards(w: float, args: PackedFloat32Array) -> Array:
	var n := maxi(1, int(_arg(args, 0, 3.0)))
	var u0 := _arg(args, 1, .2)
	var u1 := _arg(args, 2, .8)
	var z0 := _arg(args, 3, 1.0)
	var z1 := _arg(args, 4, 1.68)
	var grid: Array = []
	for j in n + 1:
		var row: Array = []
		for i in n + 1:
			var u := lerpf(u0, u1, float(i) / n)
			var z := lerpf(z0, z1, float(j) / n)
			# Shaken where it is inside the frame (the same shake every time).
			if i > 0 and i < n:
				u += sin(i * 12.9898 + j * 78.233) * (u1 - u0) / n * .3
			if j > 0 and j < n:
				z += cos(i * 39.346 + j * 11.135) * (z1 - z0) / n * .3
			row.append(Vector2(u, z))
		grid.append(row)
	var out: Array = []
	for j in n:
		for i in n:
			var r0: Array = grid[j]
			var r1: Array = grid[j + 1]
			var a: Vector2 = r0[i]
			var b: Vector2 = r0[i + 1]
			var c: Vector2 = r1[i + 1]
			var d: Vector2 = r1[i]
			var tris := [[a, b, c], [a, c, d]] if (i + j) % 2 == 0 else [[a, b, d], [b, c, d]]
			for tri: Array in tris:
				out.append(_shard(tri, w, u0, u1, z0, z1))
	return out


## One triangle of glass (corners as [share across, height]) as a thin prism.
static func _shard(tri: Array, w: float, u0: float, u1: float, z0: float, z1: float) -> Part:
	var part := Part.new()
	var pts: Array = []
	var lo := Vector2(INF, INF)
	var hi := -lo
	for item: Vector2 in tri:
		var q := Vector2((item.x - .5) * w, item.y)
		pts.append(q)
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
	var mid := (lo + hi) * .5
	part.centre = Vector3(mid.x, 0.0, mid.y)
	part.half = Vector3(maxf((hi.x - lo.x) * .5, THIN), THIN, maxf((hi.y - lo.y) * .5, THIN))
	var t := THIN
	var faces: Array = []
	for item: Vector2 in pts:
		faces.append(Vector2(item.x - mid.x, item.y - mid.y))
	var uvs: Array = []
	for item: Vector2 in tri:
		# The glass is the middle of a window tile: across, and its middle half up.
		uvs.append(
			Vector2(
				(item.x - u0) / maxf(.01, u1 - u0) * .6 + .2,
				.25 + (z1 - item.y) / maxf(.01, z1 - z0) * .5
			)
		)
	for side: float in [-1.0, 1.0]:
		for k in 3:
			var f: Vector2 = faces[k]
			var uv: Vector2 = uvs[k]
			part.verts.append(Vector3(f.x, t * side, f.y))
			part.normals.append(Vector3(0.0, side, 0.0))
			part.uvs.append(uv)
	for k in 3:
		var fa: Vector2 = faces[k]
		var fb: Vector2 = faces[(k + 1) % 3]
		var ua: Vector2 = uvs[k]
		var edge := Vector3(fb.x - fa.x, 0.0, fb.y - fa.y).cross(Vector3(0, 1, 0)).normalized()
		var quad := [
			Vector3(fa.x, -t, fa.y),
			Vector3(fb.x, -t, fb.y),
			Vector3(fb.x, t, fb.y),
			Vector3(fa.x, t, fa.y)
		]
		for i: int in [0, 1, 2, 0, 2, 3]:
			var q: Vector3 = quad[i]
			part.verts.append(q)
			part.normals.append(edge)
			part.uvs.append(ua)
	return part


# ------------------------------------------------------------------ textures


## The picture a source's pieces are textured with (RGBA8), or null.
static func texture_image(assets: Assets, source: String) -> Image:
	var name := source.substr(2)
	if source.begins_with("m:"):
		name = "mesh_" + name
	elif source.begins_with("t:"):
		var tile := name.get_slice("@", 0)
		if not assets.tile_index.has(tile):
			return null
		var i: int = assets.tile_index[tile]
		var size := 128 * 128 * 3
		var image := Image.create_from_data(
			128, 128, false, Image.FORMAT_RGB8, assets.tiles.slice(i * size, (i + 1) * size)
		)
		image.convert(Image.FORMAT_RGBA8)
		return image
	if not assets.has_art(name):
		return null
	var a := assets.art(name)
	var w: int = a["w"]
	var h: int = a["h"]
	var data: PackedByteArray = a["data"]
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
