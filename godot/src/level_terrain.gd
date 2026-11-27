## Terrain (geometry version 2): ground that is not one height a cell. A
## patch is a grid of corner heights over a rectangle of cells (hills,
## ditches, creek beds, banks, a road's crown). Each cell is two triangles,
## split from its north-west corner to its south-east one, so the surface is
## the same everywhere it is asked: standing, walking, sight, shots, the nav
## graph and the 3D mesh.
##
## A face steeper than STEEPEST is a cliff: it stops a body against it and is
## drawn upright (its picture up its face). The cells under a patch keep a
## ground of their lowest corner (written so by the plan or the source, see
## geo_kit.terrain), so everything that reads a cell's ground stays under
## the surface; LevelGeometry asks the patch itself for floors, steps, sight
## and shots. A later patch over the same cells wins.
##
## A block's "terrain": [{id, x, y, w, h, heights: [(w + 1) * (h + 1) whole
## centimetres, row by row from the north-west corner], tile (the cells'
## floor otherwise), palette + rows (a letter a cell: 0-9 then a-z index the
## palette, "." the patch's tile), cliff (the tile up a cliff and its sides
## where it stands over the ground round it), light}].
class_name LevelTerrain
extends RefCounted

## The steepest face a body walks up or down (LevelGeometry.STEEPEST).
const STEEPEST := 1.0
## A patch may be at most this many cells a side, and its heights within
## this many centimetres of 0 either way.
const MOST_CELLS := 256
const MOST_CM := 10000
## A cliff's face is drawn in this unless the patch names its own.
const CLIFF := "quarry_face"
## Where a cliff's probes go round a body (its radius out, eight ways).
const PROBE_X := [1.0, -1.0, 0.0, 0.0, .7071, .7071, -.7071, -.7071]
const PROBE_Y := [0.0, 0.0, 1.0, -1.0, .7071, -.7071, .7071, -.7071]


class Patch:
	var id := ""
	var x0 := 0
	var y0 := 0
	var w := 0
	var h := 0
	## (w + 1) * (h + 1) corner heights in map units.
	var heights := PackedFloat64Array()
	## A tile a cell (-1: the cell's own floor tile).
	var tiles := PackedInt32Array()
	var cliff := -1
	## < 0: each cell's own light.
	var light := -1.0

	func corner(cx: int, cy: int) -> float:
		return heights[(cy - y0) * (w + 1) + (cx - x0)]


var width := 0
var height := 0
var patches: Array[Patch] = []
## cell -> 1 + the index of the patch over it (0: none).
var patch_at := PackedInt32Array()
## Each cell's four corners: north-west, north-east, south-west, south-east.
var corners := PackedFloat64Array()
## Each cell's lowest and highest corner.
var low := PackedFloat64Array()
var high := PackedFloat64Array()
## Each cell: 1 when its north-east triangle (u >= v) is a cliff, 2 its
## south-west one.
var steep := PackedByteArray()


## Reads a block's terrain list (null when it has none). Problems go to
## `errors` as "<id>: <what>".
static func from_json(
	list: Variant, w: int, h: int, tile_index: Dictionary, errors: Array
) -> LevelTerrain:
	if not (list is Array):
		return null
	var items: Array = list
	if items.is_empty():
		return null
	var t := LevelTerrain.new()
	t.width = w
	t.height = h
	t.patch_at.resize(w * h)
	t.patch_at.fill(0)
	t.corners.resize(w * h * 4)
	t.low.resize(w * h)
	t.high.resize(w * h)
	t.steep.resize(w * h)
	t.steep.fill(0)
	for d: Variant in items:
		if not (d is Dictionary):
			errors.append("terrain: a patch is not an object")
			continue
		var spec: Dictionary = d
		var p := _patch(spec, w, h, tile_index, errors, t.patches.size())
		if p != null:
			t.patches.append(p)
			t._lay(p, t.patches.size())
	return t if not t.patches.is_empty() else null


static func _patch(
	d: Dictionary, w: int, h: int, tile_index: Dictionary, errors: Array, n: int
) -> Patch:
	var p := Patch.new()
	p.id = str(d.get("id", "terrain%d" % n))
	var box := PackedInt32Array()
	for key: String in ["x", "y", "w", "h"]:
		var v: Variant = d.get(key, 0)
		if not _whole(v):
			errors.append("%s: x, y, w and h are whole cells" % p.id)
			return null
		var f: float = v
		box.append(int(f))
	p.x0 = box[0]
	p.y0 = box[1]
	p.w = box[2]
	p.h = box[3]
	if p.w < 1 or p.h < 1 or p.w > MOST_CELLS or p.h > MOST_CELLS:
		errors.append("%s: a patch is 1 to %d cells a side" % [p.id, MOST_CELLS])
		return null
	if p.x0 < 0 or p.y0 < 0 or p.x0 + p.w > w or p.y0 + p.h > h:
		errors.append("%s: the patch runs off the map" % p.id)
		return null
	var raw: Variant = d.get("heights", [])
	var want := (p.w + 1) * (p.h + 1)
	var list: Array = raw if raw is Array else []
	if list.size() != want:
		errors.append("%s: heights wants %d corners ((w + 1) * (h + 1))" % [p.id, want])
		return null
	p.heights.resize(want)
	for k in want:
		var v: Variant = list[k]
		if not _whole(v):
			errors.append("%s: heights are whole centimetres" % p.id)
			return null
		var cm: float = v
		if absf(cm) > MOST_CM:
			errors.append("%s: a height past %d cm" % [p.id, MOST_CM])
			return null
		p.heights[k] = cm / 100.0
	var tile := -1
	var had := errors.size()
	if d.has("tile"):
		tile = _tile(tile_index, d["tile"], errors, p.id)
	p.cliff = _tile(tile_index, d.get("cliff", CLIFF), errors, p.id)
	if errors.size() > had:
		return null
	var light: Variant = d.get("light", -1.0)
	if light is float or light is int:
		var lit: float = light
		p.light = lit
	p.tiles.resize(p.w * p.h)
	p.tiles.fill(tile)
	var palette_v: Variant = d.get("palette", [])
	var palette: Array = palette_v if palette_v is Array else []
	var rows_v: Variant = d.get("rows", [])
	var lines: Array = rows_v if rows_v is Array else []
	if not lines.is_empty():
		if lines.size() != p.h:
			errors.append("%s: rows wants %d lines" % [p.id, p.h])
			return null
		var picks := PackedInt32Array()
		for name: Variant in palette:
			picks.append(_tile(tile_index, name, errors, p.id))
		if errors.size() > had:
			return null
		for cy in p.h:
			var line := str(lines[cy])
			if line.length() != p.w:
				errors.append("%s: each row is %d letters" % [p.id, p.w])
				return null
			for cx in p.w:
				var ch := line[cx]
				if ch == ".":
					continue
				var at := "0123456789abcdefghijklmnopqrstuvwxyz".find(ch)
				if at < 0 or at >= picks.size():
					errors.append("%s: row %d letter %s is not in the palette" % [p.id, cy, ch])
					return null
				p.tiles[cy * p.w + cx] = picks[at]
	return p


## Whether v is a whole, finite number.
static func _whole(v: Variant) -> bool:
	if not (v is int or v is float):
		return false
	var f: float = v
	return is_finite(f) and f == floorf(f)


static func _tile(tile_index: Dictionary, name: Variant, errors: Array, owner: String) -> int:
	var key := str(name)
	if not tile_index.has(key):
		errors.append("%s: no tile named %s" % [owner, key])
		return 0
	var at: int = tile_index[key]
	return at


## Lays patch p (number n, from 1) over its cells.
func _lay(p: Patch, n: int) -> void:
	for cy in range(p.y0, p.y0 + p.h):
		for cx in range(p.x0, p.x0 + p.w):
			var c := cy * width + cx
			patch_at[c] = n
			var nw := p.corner(cx, cy)
			var ne := p.corner(cx + 1, cy)
			var sw := p.corner(cx, cy + 1)
			var se := p.corner(cx + 1, cy + 1)
			corners[c * 4] = nw
			corners[c * 4 + 1] = ne
			corners[c * 4 + 2] = sw
			corners[c * 4 + 3] = se
			low[c] = minf(minf(nw, ne), minf(sw, se))
			high[c] = maxf(maxf(nw, ne), maxf(sw, se))
			var flags := 0
			# North-east triangle (nw, ne, se): slope (ne - nw, se - ne).
			if Vector2(ne - nw, se - ne).length() > STEEPEST:
				flags |= 1
			# South-west triangle (nw, sw, se): slope (se - sw, sw - nw).
			if Vector2(se - sw, sw - nw).length() > STEEPEST:
				flags |= 2
			steep[c] = flags


## Whether (x, y) is under a patch.
func has(x: float, y: float) -> bool:
	if x < 0.0 or y < 0.0 or x >= width or y >= height:
		return false
	return patch_at[int(y) * width + int(x)] != 0


## The surface's height at (x, y); NAN where no patch is.
func height_at(x: float, y: float) -> float:
	if x < 0.0 or y < 0.0 or x >= width or y >= height:
		return NAN
	var cx := int(x)
	var cy := int(y)
	var c := cy * width + cx
	if patch_at[c] == 0:
		return NAN
	var u := x - cx
	var v := y - cy
	var k := c * 4
	var nw := corners[k]
	if u >= v:
		return nw + (corners[k + 1] - nw) * u + (corners[k + 3] - corners[k + 1]) * v
	return nw + (corners[k + 3] - corners[k + 2]) * u + (corners[k + 2] - nw) * v


## The way the surface rises at (x, y): (rise per unit east, per unit south);
## ZERO where no patch is.
func slope_at(x: float, y: float) -> Vector2:
	if not has(x, y):
		return Vector2.ZERO
	var c := int(y) * width + int(x)
	var k := c * 4
	if x - int(x) >= y - int(y):
		return Vector2(corners[k + 1] - corners[k], corners[k + 3] - corners[k + 1])
	return Vector2(corners[k + 3] - corners[k + 2], corners[k + 2] - corners[k])


## Whether the triangle (x, y) is on is a cliff.
func cliff_at(x: float, y: float) -> bool:
	if not has(x, y):
		return false
	var c := int(y) * width + int(x)
	var flags := steep[c]
	if flags == 0:
		return false
	return flags & (1 if x - int(x) >= y - int(y) else 2) != 0


## Whether the surface stops a body of radius r at (x, y) whose step reaches
## lo (its feet plus a step): the ground under its middle higher than that (a
## rise it cannot step), or a cliff within its reach that is.
func blocks(x: float, y: float, r: float, lo: float) -> bool:
	var t := height_at(x, y)
	if not is_nan(t) and t > lo:
		return true
	if r <= 0.0:
		return false
	for k in 8:
		var px: float = x + PROBE_X[k] * r
		var py: float = y + PROBE_Y[k] * r
		if cliff_at(px, py) and height_at(px, py) > lo:
			return true
	return false


## The patch over cell c, or null.
func patch_of(c: int) -> Patch:
	var n := patch_at[c]
	return patches[n - 1] if n > 0 else null


## The tile cell c's surface is drawn in (-1: the cell's own floor tile).
func tile_of(c: int) -> int:
	var p := patch_of(c)
	if p == null:
		return -1
	return p.tiles[(c / width - p.y0) * p.w + (c % width - p.x0)]
