## The real pieces a broken thing comes apart into (features/wreckage.gd
## throws them, view3d/wreck_layer.gd draws them): cut from the thing's own
## look, so a piece in the air is the part of it that was there.
##
## A key names what is cut and how: "<source>|<recipe>[~<stuff>][^<variant>]".
## The source is m:<model> (a prop's baked model, assets3d/props: its
## triangles cut up and drawn with its own baked texture), p:<picture> (a
## board or a sprite's picture) or t:<tile>@<w>,<h> (a wall tile on a face w
## wide and h tall: a fence's planks, a window's glass). The recipe
## (breakables.cfg `pieces`): a model's are src/wreck_fracture.gd's (boards,
## staves, table, shatter, tear, burst, splinter, chunk, grid); a picture's:
##
##   staves:n         a barrel stood up from its picture (a round of staves
##                    wearing the picture), then cut as a model's staves
##   boards:n         a crate stood up from its picture, cut as a model's boards
##   splinter:n[,t]   a painted board in n splinters along its grain, t thick
##   planks:c,r       a picture (or a tile) in c by r boards
##   fence:n,v...     a fence tile in n upright boards and a rail at each v
##                    (a share of the height down from its top)
##   shards:n,u0,u1,z0,z1  a window's glass (from u0 to u1 across the face,
##                    z0 to z1 up it) in n by n panes, each two triangles
##
## `stuff` is what the pieces are made of (breakables.cfg; how thick, how a
## cut face is drawn: WreckFracture.MATERIALS). A fractured key comes in
## `variants` (a model's on the worker, each with its own dice and its own
## fracture origin: `origin`), "^k" naming one; the key alone is variant 0.
##
## Each piece is a Part: a box the physics tumbles (half sizes about its
## middle, its turn in the source's frame) and its faces about its middle in
## its own axes. Map axes throughout (x, y across, z up); a model's own axes
## (Godot's, y up) are swapped as it is read. A model's frame has its foot's
## middle at the origin and its front toward +y; a picture's or a tile's runs
## x along it (left to right as drawn), y through it, z up, its foot's middle
## at the origin. Cut once a key and kept.
##
## A level's breakables are not cut while it loads: prepare() lists their keys
## and pump() (each tick of the level's first frames) cuts them one at a time,
## a model's on a worker thread (looks only, the same pieces whichever thread
## cuts them: tools/load_check.gd holds the two together), its variants after
## it. A key asked for before its turn is cut there and then, as before. A
## build without threads (the lite browser build) cuts a key the first time
## something of it breaks, and keeps fewer variants (LITE).
class_name WreckCuts
extends RefCounted

const PROPS := "res://assets3d/props"
## How thick an old-style cut shell is made (_part: the inside face set in
## by this; a vehicle's wreck, src/vehicle_wreck_looks.gd) and the thinnest
## a piece's box may be (half).
const SHELL := .03
const THIN := .012
## A piece with less in it than this (the area of its faces) is dropped.
const SMALL := .004
## Fractured recipes, and how many variants each key is cut in: a model of
## more than HEAVY triangles in fewer; without threads fewer still.
const FRACTURED := [
	"boards", "staves", "table", "shatter", "tear", "burst", "splinter", "chunk", "grid"
]
const VARIANTS := 6
const VARIANTS_HEAVY := 3
const HEAVY := 2500
const LITE := 2


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
	## Its cut faces (WreckFracture.finish): a colour a corner (alpha 0: drawn
	## raw, red its material) and where it is in the piece; empty: all skin.
	var colors := PackedColorArray()
	var uv2s := PackedVector2Array()
	## What it is made of and its form, for the physics (WreckPhysics.add:
	## board, stave, ring, disc, shard, sheet, clump, chunk; "" a plain box).
	var material := "wood"
	var form := ""
	## Its corners and normals in Godot's axes (y up), made where it is cut
	## (a worker's thread) so the view only hands them over; empty: the view
	## swaps them itself.
	var shown := PackedVector3Array()
	var shown_n := PackedVector3Array()


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


## A model's pieces being cut on a worker thread (pump()): the key, what it
## cuts, and the pieces once cut. The worker only reads the soup (measured
## before it starts) and writes `out`.
class Job:
	var key := ""
	var soup: Soup
	var recipe := ""
	var args := PackedFloat32Array()
	var material := "wood"
	var variant := 0
	var out: Array = []
	var task := -1

	func run() -> void:
		out = WreckCuts._cut_model(soup, recipe, args, material, variant)


## A key read: its source, recipe name, numbers, stuff and variant, and the
## key without its variant.
class Named:
	var base := ""
	var source := ""
	var recipe := ""
	var args := PackedFloat32Array()
	var material := "wood"
	var variant := 0


static var _cache := {}
static var _soups := {}
## Each source's bounds (fracture origins are round them).
static var _boxes := {}
## Keys waiting to be cut (prepare()), and the model cut on a worker now.
static var _waiting: Array[String] = []
static var _job: Job = null


## A key taken apart (see the top).
static func named(key: String) -> Named:
	var out := Named.new()
	var base := key
	var caret := key.rfind("^")
	if caret > key.find("|"):
		base = key.left(caret)
		out.variant = key.substr(caret + 1).to_int()
	out.base = base
	var bar := base.find("|")
	if bar < 0:
		out.source = base
		return out
	out.source = base.left(bar)
	var recipe := base.substr(bar + 1)
	var tilde := recipe.find("~")
	if tilde >= 0:
		out.material = WreckFracture.material_of(recipe.substr(tilde + 1))
		recipe = recipe.left(tilde)
	out.recipe = recipe.get_slice(":", 0)
	out.args = _numbers(recipe.get_slice(":", 1) if recipe.contains(":") else "")
	return out


## How many variants a key is cut in (1: it is not fractured).
static func variants(key: String) -> int:
	var k := named(key)
	if not FRACTURED.has(k.recipe) or k.source.begins_with("t:"):
		return 1
	var heavy := false
	if k.source.begins_with("m:"):
		heavy = _model(k.source.substr(2)).size() / 3 > HEAVY
	if not OS.has_feature("threads"):
		return 1 if heavy else LITE
	return VARIANTS_HEAVY if heavy else VARIANTS


## Whether a key's pieces may be turned any way about its upright axis (a
## barrel's: round, so a break turns its fracture origin to the hit).
static func round_about(key: String) -> bool:
	return named(key).recipe == "staves"


## Where a key's variant breaks from (its fracture origin, in its source's
## frame), once it has been cut.
static func origin(key: String) -> Vector3:
	var k := named(key)
	var found: Variant = _boxes.get(k.source + "|" + k.recipe)
	if found == null:
		return Vector3.ZERO
	var box: AABB = found
	return WreckFracture.origin(box, k.variant)


## Lists keys to cut while the level's first frames run (pump()), none of it
## now; each key's variants follow it. Without threads nothing is listed: a
## key is cut when first asked for.
static func prepare(keys: Array) -> void:
	if not OS.has_feature("threads"):
		return
	for item: Variant in keys:
		var key := str(item)
		if _cache.has(key) or _waiting.has(key) or (_job != null and _job.key == key):
			continue
		_waiting.append(key)


## One step of the cutting prepare() listed: takes in a worker's finished cut,
## then starts the next model on a worker (its model read here) or cuts the
## next picture or tile here (a millisecond or two). A key's variants are
## listed last once its own is taken. Cheap when nothing waits.
static func pump(assets: Assets) -> void:
	if _job != null:
		if not WorkerThreadPool.is_task_completed(_job.task):
			return
		_settle()
	while not _waiting.is_empty():
		var key: String = _waiting.pop_front()
		if _cache.has(key):
			continue
		var k := named(key)
		if k.variant == 0:
			# Its variants after every key's own (each kind has one soon).
			var more := variants(key)
			for v in range(1, more):
				var other := "%s^%d" % [k.base, v]
				if not _cache.has(other) and not _waiting.has(other):
					_waiting.append(other)
		var soup := _worker_soup(assets, k)
		if soup == null:
			parts(assets, key)
			return
		if soup.size() == 0:
			_cache[key] = []
			continue
		soup.measure()
		_boxes[k.source + "|" + k.recipe] = soup.bounds()
		var job := Job.new()
		job.key = key
		job.soup = soup
		job.recipe = k.recipe
		job.args = k.args
		job.material = k.material
		job.variant = k.variant
		job.task = WorkerThreadPool.add_task(job.run, false, "wreck cuts")
		_job = job
		return


## What a worker cuts for a key: a model's triangles, or a barrel's or a
## crate's stood up from its picture (made here, a millisecond); null when
## the key is cut here at once (a tile, a painted board, a set piece's).
static func _worker_soup(assets: Assets, k: Named) -> Soup:
	if k.source.begins_with("m:") and k.recipe != "":
		return _model(k.source.substr(2))
	if k.source.begins_with("p:") and (k.recipe == "staves" or k.recipe == "boards"):
		var pic := _picture(assets, k.source.substr(2))
		return Soup.new() if pic.is_empty() else _stood_up(pic, k.recipe)
	return null


## Pieces made elsewhere kept under `key` (a set piece's standing parts
## merged into one: features/set_pieces.gd), drawn as any cut is.
static func put(key: String, made: Array) -> void:
	_cache[key] = made


static func has(key: String) -> bool:
	return _cache.has(key)


## Whether nothing is waiting to be cut or being cut.
static func idle() -> bool:
	return _job == null and _waiting.is_empty()


## Waits for the worker's cut and keeps it.
static func _settle() -> void:
	if _job == null:
		return
	WorkerThreadPool.wait_for_task_completion(_job.task)
	_cache[_job.key] = _job.out
	_job = null


## Forgets every cut (the tools' cold loads), after the worker's is done.
static func clear() -> void:
	_settle()
	_waiting.clear()
	_cache.clear()
	_soups.clear()
	_boxes.clear()


## The pieces a key cuts into (empty when there is nothing to cut).
static func parts(assets: Assets, key: String) -> Array:
	var cached: Variant = _cache.get(key)
	if cached != null:
		var known: Array = cached
		return known
	if _job != null and _job.key == key:
		_settle()
		var cut: Array = _cache[key]
		return cut
	_waiting.erase(key)
	var out: Array = []
	var k := named(key)
	if k.recipe != "":
		if k.source.begins_with("m:"):
			var soup := _model(k.source.substr(2))
			if soup.size() > 0:
				_boxes[k.source + "|" + k.recipe] = soup.bounds()
				out = _cut_model(soup, k.recipe, k.args, k.material, k.variant)
		elif k.source.begins_with("p:"):
			out = _cut_picture(assets, k)
		elif k.source.begins_with("t:"):
			out = _cut_tile(k.source.substr(2), k.recipe, k.args)
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


## A model cut by a recipe (src/wreck_fracture.gd): variant `k`, its pieces
## of `material` (WreckFracture.MATERIALS).
static func _cut_model(
	soup: Soup, recipe: String, args: PackedFloat32Array, material: String, k: int
) -> Array:
	return WreckFracture.cut(soup, recipe, args, material, k)


## Planes keeping a <= p[axis] <= b.
static func slab(axis: int, a: float, b: float) -> Array:
	var n := Vector3.ZERO
	n[axis] = 1.0
	return [[-n, -a], [n, b]]


## A polygon cut by a plane: the part where n.p <= d.
static func clip(poly: Soup, pn: Vector3, pd: float) -> Soup:
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


static func area(soup: Soup) -> float:
	var total := 0.0
	for t in soup.size() / 3:
		total += (
			(soup.p[t * 3 + 1] - soup.p[t * 3]).cross(soup.p[t * 3 + 2] - soup.p[t * 3]).length()
		)
	return total * .5


## Cutting by planes kept for a vehicle's wreck (src/vehicle_wreck_looks.gd);
## the breakables' cuts are wreck_fracture.gd's.
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
			poly = clip(poly, pn, pd)
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


## A Part from a cut soup: its own axes (the cell's), its middle, its box, and
## (a shell) an inside face set in by SHELL so it has a thickness.
static func _part(piece: Soup, cell: Dictionary, shell: bool) -> Part:
	var part := Part.new()
	part.basis = cell.get("basis", Basis.IDENTITY)
	part.form = str(cell.get("form", ""))
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


## A picture's solid pixels: [w, h, the solid bounds' lo and hi corners (its
## pixels), the RGBA data], or [] when it is not there or all clear.
static func _picture(assets: Assets, image: String) -> Array:
	if not assets.has_art(image):
		return []
	var art := assets.art(image)
	var w: int = art["w"]
	var h: int = art["h"]
	var data: PackedByteArray = art["data"]
	var lo := Vector2i(w, h)
	var hi := Vector2i(-1, -1)
	for y in h:
		for x in w:
			if data[(y * w + x) * 4 + 3] > 100:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	if hi.x < 0:
		return []
	return [w, h, lo, hi, data]


## A picture cut by a recipe: a barrel or a crate stood up from it and cut as
## a model is, a painted board in splinters, or boards of it.
static func _cut_picture(assets: Assets, k: Named) -> Array:
	var image := k.source.substr(2)
	var recipe := k.recipe
	var args := k.args
	if recipe.begins_with("sp") and recipe != "splinter":
		# A set piece's painted band (src/set_piece_mesh.gd).
		return SetPieceMesh.cut(recipe, args)
	var pic := _picture(assets, image)
	if pic.is_empty():
		return []
	var w: int = pic[0]
	var h: int = pic[1]
	var lo: Vector2i = pic[2]
	var hi: Vector2i = pic[3]
	var data: PackedByteArray = pic[4]
	if recipe == "staves" or recipe == "boards":
		var soup := _stood_up(pic, recipe)
		_boxes[k.source + "|" + recipe] = soup.bounds()
		return WreckFracture.cut(soup, recipe, args, k.material, k.variant)
	if recipe == "splinter":
		return _splinters(pic, k)
	if recipe != "planks":
		return []
	# One unit: the picture's height (a sprite's height is its picture's).
	var unit := 1.0 / h
	var cols := maxi(1, int(_arg(args, 0, 2.0)))
	var rows := maxi(1, int(_arg(args, 1, 2.0)))
	# How thick, as a share of the picture's height (a piece is in picture heights).
	var thick := _arg(args, 2, .05)
	var out: Array = []
	var span := hi - lo + Vector2i.ONE
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
					filled += 1 if data[(y * w + x) * 4 + 3] > 100 else 0
			if filled < (x1 - x0) * (y1 - y0) * .4:
				continue
			var rect := Rect2(
				(x0 - w * .5) * unit, (h - y1) * unit, (x1 - x0) * unit, (y1 - y0) * unit
			)
			var tex := Rect2(float(x0) / w, float(y0) / h, float(x1 - x0) / w, float(y1 - y0) / h)
			out.append(board(rect, tex, thick, Vector2(w, h)))
	return out


## A thing stood up from its picture, in picture heights (its foot's middle
## at the origin, its front toward -y): `staves` a barrel (a round of 16
## faces wearing the picture's columns as they face the eye, front and back
## alike, and its heads), `boards` a crate (each side the picture, its lid the
## top rows). Kept a picture.
static func _stood_up(pic: Array, recipe: String) -> Soup:
	var w: int = pic[0]
	var h: int = pic[1]
	var lo: Vector2i = pic[2]
	var hi: Vector2i = pic[3]
	var name := "%d,%d,%d,%d,%d,%d|%s" % [w, h, lo.x, lo.y, hi.x, hi.y, recipe]
	var kept: Variant = _soups.get(name)
	if kept != null:
		var known: Soup = kept
		return known
	var unit := 1.0 / h
	var cx := ((lo.x + hi.x + 1) * .5 - w * .5) * unit
	var half := (hi.x - lo.x + 1) * .5 * unit
	var z0 := (h - hi.y - 1) * unit
	var z1 := (h - lo.y) * unit
	var mid_col := (lo.x + hi.x + 1) * .5
	var reach := (hi.x - lo.x + 1) * .5 - 1.5
	var soup := Soup.new()
	if recipe == "staves":
		var segs := 16
		var bands := 3
		for i in segs:
			for b in bands:
				var za := lerpf(z0, z1, float(b) / bands)
				var zb := lerpf(z0, z1, float(b + 1) / bands)
				var corners: Array = []
				for e: int in [i, i + 1]:
					var a := TAU * e / segs
					var p := Vector3(cx + sin(a) * half, -cos(a) * half, 0.0)
					var u := (mid_col + sin(a) * reach) / w
					corners.append([p, Vector3(sin(a), -cos(a), 0.0), u])
				var c0: Array = corners[0]
				var c1: Array = corners[1]
				for row: Array in [[c0, za], [c1, za], [c1, zb], [c0, za], [c1, zb], [c0, zb]]:
					var c: Array = row[0]
					var z: float = row[1]
					var at: Vector3 = c[0]
					var normal: Vector3 = c[1]
					var u: float = c[2]
					soup.p.append(Vector3(at.x, at.y, z))
					soup.n.append(normal)
					soup.uv.append(Vector2(u, (h - z / unit) / h))
		# The heads: a fan each, the colour at the picture's top and foot.
		for top: bool in [true, false]:
			var z := z1 if top else z0
			var uv := Vector2(mid_col / w, (lo.y + 2.5 if top else hi.y - 2.5) / h)
			for i in segs:
				var a0 := TAU * i / segs
				var a1 := TAU * (i + 1) / segs
				var ring: Array[Vector3] = [
					Vector3(cx, 0.0, z),
					Vector3(cx + sin(a0) * half, -cos(a0) * half, z),
					Vector3(cx + sin(a1) * half, -cos(a1) * half, z)
				]
				if not top:
					ring = [ring[0], ring[2], ring[1]]
				for q: Vector3 in ring:
					soup.p.append(q)
					soup.n.append(Vector3(0, 0, 1 if top else -1))
					soup.uv.append(uv)
	else:
		# A crate: four sides wearing the picture below its lid rows, the lid
		# those rows.
		var lid := lo.y + (hi.y - lo.y) * .18
		var u0 := (lo.x + 1.0) / w
		var u1 := (hi.x) / float(w)
		var v_lid := lid / h
		var v_foot := (hi.y + .5) / h
		for side in 4:
			var turn := Basis(Vector3(0, 0, 1), side * PI * .5)
			var n: Vector3 = turn * Vector3(0, -1, 0)
			var a: Vector3 = turn * Vector3(-half, -half, 0.0) + Vector3(cx, 0, 0)
			var b: Vector3 = turn * Vector3(half, -half, 0.0) + Vector3(cx, 0, 0)
			_face(soup, a, b, z0, z1, n, [u0, u1, v_foot, v_lid])
		var top := [
			Vector3(cx - half, -half, z1),
			Vector3(cx + half, -half, z1),
			Vector3(cx + half, half, z1),
			Vector3(cx - half, half, z1)
		]
		var tuv := [
			Vector2(u0, v_lid),
			Vector2(u1, v_lid),
			Vector2(u1, (lo.y + 1.0) / h),
			Vector2(u0, (lo.y + 1.0) / h)
		]
		for i: int in [0, 1, 2, 0, 2, 3]:
			var corner: Vector3 = top[i]
			var place: Vector2 = tuv[i]
			soup.p.append(corner)
			soup.n.append(Vector3(0, 0, 1))
			soup.uv.append(place)
		for i: int in [0, 2, 1, 0, 3, 2]:
			var q: Vector3 = top[i]
			soup.p.append(Vector3(q.x, q.y, z0))
			soup.n.append(Vector3(0, 0, -1))
			soup.uv.append(Vector2((u0 + u1) * .5, v_foot))
	_soups[name] = soup
	return soup


## A side from a to b (along the ground) between heights z0 and z1, facing
## n, wearing [u0, u1, v at z0, v at z1] of a picture; in two bands.
static func _face(
	soup: Soup, a: Vector3, b: Vector3, z0: float, z1: float, n: Vector3, uv: Array
) -> void:
	var u0: float = uv[0]
	var u1: float = uv[1]
	var vf: float = uv[2]
	var vt: float = uv[3]
	for band in 2:
		var za := lerpf(z0, z1, band * .5)
		var zb := lerpf(z0, z1, (band + 1) * .5)
		var va := lerpf(vf, vt, band * .5)
		var vb := lerpf(vf, vt, (band + 1) * .5)
		var quad := [
			[Vector3(a.x, a.y, za), Vector2(u0, va)],
			[Vector3(b.x, b.y, za), Vector2(u1, va)],
			[Vector3(b.x, b.y, zb), Vector2(u1, vb)],
			[Vector3(a.x, a.y, zb), Vector2(u0, vb)]
		]
		for i: int in [0, 1, 2, 0, 2, 3]:
			var c: Array = quad[i]
			var corner: Vector3 = c[0]
			var place: Vector2 = c[1]
			soup.p.append(corner)
			soup.n.append(n)
			soup.uv.append(place)


## A painted board in n splinters along its grain (across the picture): the
## board's face cut into cells about seeds (stretched along the grain, small
## near the variant's origin), each cell its front wearing the picture and
## its back and edges raw wood (WreckFracture.finish).
static func _splinters(pic: Array, k: Named) -> Array:
	var w: int = pic[0]
	var h: int = pic[1]
	var lo: Vector2i = pic[2]
	var hi: Vector2i = pic[3]
	var data: PackedByteArray = pic[4]
	var unit := 1.0 / h
	var rect := Rect2(
		(lo.x - w * .5) * unit,
		(h - hi.y - 1) * unit,
		(hi.x - lo.x + 1) * unit,
		(hi.y - lo.y + 1) * unit
	)
	var box := AABB(
		Vector3(rect.position.x, -.01, rect.position.y), Vector3(rect.size.x, .02, rect.size.y)
	)
	_boxes[k.source + "|" + k.recipe] = box
	var at := WreckFracture.origin(box, k.variant)
	var dice := RandomNumberGenerator.new()
	dice.seed = hash(k.source) + 7919 * k.variant
	var n := maxi(2, int(_arg(k.args, 0, 7.0)))
	var sites := PackedVector2Array()
	for i in n:
		if i < n / 2:
			sites.append(
				Vector2(
					clampf(
						at.x + dice.randf_range(-.3, .3) * rect.size.x, rect.position.x, rect.end.x
					),
					clampf(
						at.z + dice.randf_range(-.3, .3) * rect.size.y, rect.position.y, rect.end.y
					)
				)
			)
		else:
			sites.append(
				rect.position + Vector2(dice.randf() * rect.size.x, dice.randf() * rect.size.y)
			)
	# Along the grain (across) distances count a third.
	var s := Vector2(.33, 1.0)
	var out: Array = []
	for i in sites.size():
		var poly := PackedVector2Array(
			[
				rect.position,
				Vector2(rect.end.x, rect.position.y),
				rect.end,
				Vector2(rect.position.x, rect.end.y)
			]
		)
		for j in sites.size():
			if j == i:
				continue
			var nn := (sites[j] - sites[i]) * s * s
			var d := ((sites[j] * s).length_squared() - (sites[i] * s).length_squared()) * .5
			poly = _clip2(poly, nn, d)
			if poly.size() < 3:
				break
		if poly.size() < 3:
			continue
		var mid := Vector2.ZERO
		for q: Vector2 in poly:
			mid += q
		mid /= poly.size()
		var px := clampi(int(mid.x / unit + w * .5), 0, w - 1)
		var py := clampi(int(h - mid.y / unit), 0, h - 1)
		if data[(py * w + px) * 4 + 3] <= 100:
			continue
		var skin := Soup.new()
		for t in range(1, poly.size() - 1):
			for q: Vector2 in [poly[0], poly[t], poly[t + 1]]:
				skin.p.append(Vector3(q.x, 0.0, q.y))
				skin.n.append(Vector3(0, -1, 0))
				skin.uv.append(Vector2((q.x / unit + w * .5) / w, (h - q.y / unit) / h))
		if area(skin) < SMALL * .25:
			continue
		var along := Vector3(1, 0, 0) if rect.size.x >= rect.size.y else Vector3(0, 0, 1)
		out.append(
			WreckFracture.finish(
				skin, WreckFracture.frame(along, Vector3(0, -1, 0)), "wood", "board"
			)
		)
	return out


## A 2D polygon cut by a line: the part where n.p <= d.
static func _clip2(poly: PackedVector2Array, n: Vector2, d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var da := n.dot(a) - d
		var db := n.dot(b) - d
		if da <= 0.0:
			out.append(a)
		if (da <= 0.0) != (db <= 0.0):
			out.append(a.lerp(b, da / (da - db)))
	return out


## A tile on a face `w` wide and `h` tall cut by a recipe.
static func _cut_tile(source: String, recipe: String, args: PackedFloat32Array) -> Array:
	var size := _numbers(source.get_slice("@", 1))
	var w := _arg(size, 0, 1.0)
	var h := _arg(size, 1, 1.0)
	var texels := Vector2(128, 128)
	var out: Array = []
	if recipe.begins_with("sp"):
		# The set pieces' own (src/set_piece_mesh.gd).
		return SetPieceMesh.cut(recipe, args)
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
	part.form = "board"
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
	part.form = "shard"
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
