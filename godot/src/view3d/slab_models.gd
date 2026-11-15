## Slabs for the 3D view, made from the world's own flat pictures the first
## time each is shown, and kept: the picture's solid pixels pushed out a few
## pixels thick. Its front and back show the picture; each edge pixel's side
## wall is that pixel's colour, so the outline and colours are the old
## sprite's exactly. Nothing is stored in the export: the meshes are built
## from the art at run time. Three families (family()):
##
## - PICKUP: the `item_*` pickups, a chunky slab (.6 of the art's breadth).
## - LOOSE: what a fight throws about and leaves lying (brass and hulls,
##   gibs and scrap, breakables' bits, chips, splinters and clods, a hat shot
##   off, a dropped gun): a thinner slab (.5 of the breadth) that tumbles.
## - TARGET: the firing range's plywood and steel (boards, gongs, the cow,
##   the gallery's movers): thin as plywood, a pixel for each 28 of height. A
##   gong's plate and chains are a part of their own (PARTS) that swings
##   from the bar, the frame staying put.
##
## A mesh is in sprite units: one unit is the picture's height, standing on
## its bottom row at y 0 (empty rows below the art kept, so it floats as the
## sprite did), x centred on the art's solid columns, the slab across z. The
## front (+Z) shows the picture as the sprite did. UVs are the picture's
## (0..1); a side wall's UV is its pixel's middle.
class_name SlabModels
extends RefCounted

const NONE := 0
const PICKUP := 1
const LOOSE := 2
const TARGET := 3
## A pixel is solid past this alpha (sprite.gdshader's solid test).
const SOLID := 100
## How thick a slab is: this share of the art's breadth (_breadth), in whole
## pixels, between THIN and THICK (PICKUP, LOOSE); a TARGET is a pixel for
## each PLY rows of its picture, at least THIN.
const DEPTH := {PICKUP: .6, LOOSE: .5}
const THICK := {PICKUP: 12, LOOSE: 8}
const THIN := 2
const PLY := 28.0
## A side wall shows the colour inside the art's outline: an edge pixel this
## much darker than the one inside it is outline, up to OUTLINE pixels deep.
const DARKER := .6
const OUTLINE := 2
## The pictures that tumble (by the start of their names). Not blood, smoke,
## flames, flashes or glows: those stay pictures.
const LOOSE_NAMES := [
	"fx_casing",
	"fx_hull",
	"gib_",
	"fx_brk_",
	"fx_chips",
	"fx_soil",
	"fx_splinter_",
	"fx_chunk_",
	"fx_grit_",
	"fx_hat_",
	"fx_drop_",
]
## The firing range's targets (range_targets.gd; not the bowling pins).
const TARGET_NAMES := {
	"town_range_target": true,
	"town_range_gong": true,
	"town_range_cow_target": true,
	"county_gallery_target": true,
	"town_range_duck": true,
}
## A target's part that moves on its own: the solid pixels in this box of
## its picture (a gong's plate and chains), hung from the box's top edge.
## Its mesh is `<picture>` + PART; the picture's own mesh leaves it out.
const PARTS := {"town_range_gong": Rect2i(14, 6, 56, 48)}
const PART := "#part"

var _assets: Assets
## mesh key -> ArrayMesh (null cached for a picture that is not there)
var _meshes: Dictionary = {}
## picture -> where its part hangs from, in sprite units up (NAN: no part)
var _pivots: Dictionary = {}


func _init(assets: Assets) -> void:
	_assets = assets


## Which family a picture's slab is in (NONE: it stays a sprite).
static func family(image: String) -> int:
	if image.begins_with("item_"):
		return PICKUP
	if TARGET_NAMES.has(image):
		return TARGET
	if image.begins_with("fx_") or image.begins_with("gib_"):
		for prefix: String in LOOSE_NAMES:
			if image.begins_with(prefix):
				return LOOSE
	return NONE


## True when a sprite showing `image` is a pickup drawn as a mesh.
static func is_pickup(image: String) -> bool:
	return family(image) == PICKUP


## The mesh for `key` (a picture's name, or its name + PART), or null when its
## picture is not here (yet).
func mesh(key: String) -> ArrayMesh:
	if _meshes.has(key):
		var known: ArrayMesh = _meshes[key]
		return known
	var part := key.ends_with(PART)
	var image := key.trim_suffix(PART) if part else key
	if not _assets.has_art(image):
		_meshes[key] = null
		return null
	var a := _assets.art(image)
	var w: int = a["w"]
	var h: int = a["h"]
	var data: PackedByteArray = a["data"]
	var box: Rect2i = PARTS.get(image, Rect2i())
	var built := build(w, h, data, family(image), box, part)
	# A picture whose pack is still being fetched comes back blank: asked again.
	if built != null:
		_meshes[key] = built
	return built


## Where the part of `image` hangs from (sprite units up from its bottom
## row), or NAN when it has none.
func pivot(image: String) -> float:
	if _pivots.has(image):
		var known: float = _pivots[image]
		return known
	var at := NAN
	if PARTS.has(image) and _assets.has_art(image):
		var box: Rect2i = PARTS[image]
		var h: int = _assets.art(image)["h"]
		at = float(h - box.position.y) / h
	_pivots[image] = at
	return at


## The slab for a w x h RGBA8 picture, or null when no pixel is solid. With
## a `box`, only its pixels (`inside`) or all but them; the slab is placed
## as the whole picture's would be either way, so the two fit together.
static func build(
	w: int, h: int, data: PackedByteArray, kind := PICKUP, box := Rect2i(), inside := false
) -> ArrayMesh:
	if w <= 0 or h <= 0 or data.size() < w * h * 4:
		return null
	var solid := PackedByteArray()
	solid.resize(w * h)
	var all_x0 := w
	var all_x1 := -1
	var x0 := w
	var x1 := -1
	var y0 := h
	var y1 := -1
	var masked := box.has_area()
	for y in h:
		for x in w:
			if data[(y * w + x) * 4 + 3] <= SOLID:
				continue
			all_x0 = mini(all_x0, x)
			all_x1 = maxi(all_x1, x)
			if masked and box.has_point(Vector2i(x, y)) != inside:
				continue
			solid[y * w + x] = 1
			x0 = mini(x0, x)
			x1 = maxi(x1, x)
			y0 = mini(y0, y)
			y1 = maxi(y1, y)
	if x1 < 0:
		return null
	var q := 1.0 / h
	var mid := (all_x0 + all_x1 + 1) * .5
	var depth := maxi(THIN, roundi(h / PLY))
	if kind != TARGET:
		var share: float = DEPTH.get(kind, DEPTH[PICKUP])
		var most: int = THICK.get(kind, THICK[PICKUP])
		depth = clampi(roundi(_breadth(solid, w, h) * share), THIN, most)
	var half := depth * q * .5
	var slab := _Slab.new()
	# Front and back: the art's box, its empty pixels left to the shader.
	var left := (x0 - mid) * q
	var right := (x1 + 1 - mid) * q
	var top := (h - y0) * q
	var bottom := (h - y1 - 1) * q
	var uv0 := Vector2(float(x0) / w, float(y0) / h)
	var uv1 := Vector2(float(x1 + 1) / w, float(y1 + 1) / h)
	for side: float in [1.0, -1.0]:
		var z := half * side
		slab.quad(
			[
				Vector3(left, bottom, z),
				Vector3(left, top, z),
				Vector3(right, top, z),
				Vector3(right, bottom, z)
			],
			[Vector2(uv0.x, uv1.y), uv0, Vector2(uv1.x, uv0.y), uv1],
			Vector3(0.0, 0.0, side)
		)
	# The side walls: each run of edge pixels showing one colour, one quad.
	for y in h:
		for up: int in [-1, 1]:
			var x := 0
			while x < w:
				if not _edge(solid, w, h, x, y, 0, up):
					x += 1
					continue
				var shown := _wall(data, solid, w, h, x, y, 0, up)
				var run := x + 1
				while (
					run < w
					and _edge(solid, w, h, run, y, 0, up)
					and _same(data, shown, _wall(data, solid, w, h, run, y, 0, up))
				):
					run += 1
				var at := (h - y - (0 if up < 0 else 1)) * q
				var lx := (x - mid) * q
				var rx := (run - mid) * q
				slab.quad(
					[
						Vector3(lx, at, -half),
						Vector3(lx, at, half),
						Vector3(rx, at, half),
						Vector3(rx, at, -half)
					],
					[],
					Vector3(0.0, -up, 0.0),
					_middle(shown, w, h)
				)
				x = run
	for x in w:
		for across: int in [-1, 1]:
			var y := 0
			while y < h:
				if not _edge(solid, w, h, x, y, across, 0):
					y += 1
					continue
				var shown := _wall(data, solid, w, h, x, y, across, 0)
				var run := y + 1
				while (
					run < h
					and _edge(solid, w, h, x, run, across, 0)
					and _same(data, shown, _wall(data, solid, w, h, x, run, across, 0))
				):
					run += 1
				var at := (x + (0 if across < 0 else 1) - mid) * q
				var ty := (h - y) * q
				var by := (h - run) * q
				slab.quad(
					[
						Vector3(at, by, -half),
						Vector3(at, ty, -half),
						Vector3(at, ty, half),
						Vector3(at, by, half)
					],
					[],
					Vector3(across, 0.0, 0.0),
					_middle(shown, w, h)
				)
				y = run
	return slab.mesh()


## How broad the art is: the middle of its solid columns' and rows' pixel
## counts, the smaller (a gun's barrel and stock, a can's width).
static func _breadth(solid: PackedByteArray, w: int, h: int) -> int:
	var cols := PackedInt32Array()
	var rows := PackedInt32Array()
	for x in w:
		var n := 0
		for y in h:
			n += solid[y * w + x]
		if n > 0:
			cols.append(n)
	for y in h:
		var n := 0
		for x in w:
			n += solid[y * w + x]
		if n > 0:
			rows.append(n)
	cols.sort()
	rows.sort()
	return mini(cols[cols.size() / 2], rows[rows.size() / 2])


## Pixel (x, y) is solid and its neighbour (x + dx, y + dy) is not.
static func _edge(solid: PackedByteArray, w: int, h: int, x: int, y: int, dx: int, dy: int) -> bool:
	if solid[y * w + x] == 0:
		return false
	var nx := x + dx
	var ny := y + dy
	if nx < 0 or ny < 0 or nx >= w or ny >= h:
		return true
	return solid[ny * w + nx] == 0


## The pixel whose colour the wall of edge pixel (x, y) facing (dx, dy)
## shows: the edge pixel, or past its drawn outline (a pixel much darker than
## the one inside it) the first pixel in, up to OUTLINE deep.
static func _wall(
	data: PackedByteArray, solid: PackedByteArray, w: int, h: int, x: int, y: int, dx: int, dy: int
) -> int:
	var at := y * w + x
	for step in OUTLINE:
		var ix := x - dx * (step + 1)
		var iy := y - dy * (step + 1)
		if ix < 0 or iy < 0 or ix >= w or iy >= h or solid[iy * w + ix] == 0:
			break
		var inner := iy * w + ix
		if _luma(data, at) >= _luma(data, inner) * DARKER:
			break
		at = inner
	return at


static func _luma(data: PackedByteArray, at: int) -> float:
	return data[at * 4] * .3 + data[at * 4 + 1] * .59 + data[at * 4 + 2] * .11


## The UV of pixel `at`'s middle.
static func _middle(at: int, w: int, h: int) -> Vector2:
	return Vector2((at % w + .5) / w, (at / w + .5) / h)


static func _same(data: PackedByteArray, a: int, b: int) -> bool:
	var i := a * 4
	var j := b * 4
	return data[i] == data[j] and data[i + 1] == data[j + 1] and data[i + 2] == data[j + 2]


## The arrays of a mesh being built, a quad at a time.
class _Slab:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var index := PackedInt32Array()

	## Four corners in order round the quad, facing `normal`; the UVs per
	## corner, or one UV for all (`flat`).
	func quad(corners: Array, corner_uvs: Array, normal: Vector3, flat := Vector2.ZERO) -> void:
		var base := verts.size()
		for k in 4:
			var p: Vector3 = corners[k]
			verts.append(p)
			normals.append(normal)
			if corner_uvs.is_empty():
				uvs.append(flat)
			else:
				var uv: Vector2 = corner_uvs[k]
				uvs.append(uv)
		var a: Vector3 = corners[0]
		var b: Vector3 = corners[1]
		var c: Vector3 = corners[2]
		# Godot's front faces wind clockwise as seen from the front.
		if (b - a).cross(c - a).dot(normal) < 0.0:
			index.append_array(
				PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3])
			)
		else:
			index.append_array(
				PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2])
			)

	func mesh() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = index
		var out := ArrayMesh.new()
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return out
