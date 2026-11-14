## Geometry beyond the grid (level format 2): what a level's "geometry" block
## adds on top of the cells, in map units (a cell is 1 x 1, z up, the eye .95
## over the floor).
##
## - Slabs: solid boxes standing on a footprint (a rectangle cut by up to a few
##   straight lines, so a triangle, a trapezoid or an angled balcony), with a
##   top that may slope (gx, gy: rise per unit along x and y) and either a
##   thickness (a deck, a landing, a bridge, a balcony: walked on AND under) or
##   none (solid down to the ground: a ramp's wedge, a stair tread, a plinth).
##   A walkable slab is a floor: bodies stand on its top, climb onto it when it
##   is at most STEP above their feet, fall off its edge, and pass under it
##   when there is headroom.
## - Segments: free walls from a to b, z0 up to z1, `thick` thick: thin walls,
##   angled walls, rails, low cover, the pieces round a doorway or window. They
##   collide in 3D (a rail stops a body but not a bullet over it).
## - Ceilings: flat overhead surfaces with no floor on top (an overhang, a
##   porch roof seen from under it, an upper room's ceiling).
##
## Everything here is static. LevelData asks it about collision (blocks()),
## standing (floor_at()), headroom (ceiling_at()), sight and shots
## (solid_point(), crosses()); the renderers take the surfaces it makes
## (render_parts()); FlowField walks its nav graph (nav()). A level without a
## geometry block has none of this and plays exactly as before.
class_name LevelGeometry
extends RefCounted

## The newest geometry block this build reads.
const VERSION := 1
## A body climbs at most this onto a slab without jumping (the grid's step).
const STEP := .245
## A standing body's height for collision and headroom (the eye is .95).
const BODY := 1.12
## Headroom a crouching body needs (its eye is .68).
const CROUCH := .86
## The steepest slope a slab's top may have (rise per unit run).
const STEEPEST := 1.0
## The thinnest segment: sight lines step 1/9 of a cell and must not slip through.
const THINNEST := .08
## Index cells reach this far past a piece (a body's radius and then some).
const PAD := .75
## How a nav edge is walked: sub-steps from cell middle to cell middle.
const NAV_STEPS := 8
## The nav graph's body radius (FlowField.BODY).
const NAV_BODY := .2


class Slab:
	var id := ""
	var kind := "deck"
	var x0 := 0.0
	var y0 := 0.0
	var x1 := 0.0
	var y1 := 0.0
	## Unit normal and offset triples: inside where nx * x + ny * y <= c.
	var cuts := PackedFloat32Array()
	var top := 0.0
	var gx := 0.0
	var gy := 0.0
	## < 0: solid down to the ground.
	var thick := -1.0
	var tile := -1
	var under := -1
	var edge := -1
	var light := .9
	var area := 0
	var walk := true

	func inside(x: float, y: float) -> bool:
		if x < x0 or x > x1 or y < y0 or y > y1:
			return false
		for k in range(0, cuts.size(), 3):
			if cuts[k] * x + cuts[k + 1] * y > cuts[k + 2]:
				return false
		return true

	## Inside the footprint grown by r (corners grown square: a little generous).
	func near(x: float, y: float, r: float) -> bool:
		if x < x0 - r or x > x1 + r or y < y0 - r or y > y1 + r:
			return false
		for k in range(0, cuts.size(), 3):
			if cuts[k] * x + cuts[k + 1] * y > cuts[k + 2] + r:
				return false
		return true

	func top_at(x: float, y: float) -> float:
		if gx == 0.0 and gy == 0.0:
			return top
		return top + gx * (clampf(x, x0, x1) - x0) + gy * (clampf(y, y0, y1) - y0)

	func bottom_at(x: float, y: float) -> float:
		if thick < 0.0:
			return -1e9
		return top_at(x, y) - thick

	func sloped() -> bool:
		return gx != 0.0 or gy != 0.0

	## The highest the top reaches anywhere on the footprint's box.
	func top_max() -> float:
		return top + maxf(0.0, gx * (x1 - x0)) + maxf(0.0, gy * (y1 - y0))

	func top_min() -> float:
		return top + minf(0.0, gx * (x1 - x0)) + minf(0.0, gy * (y1 - y0))


class Segment:
	var id := ""
	var ax := 0.0
	var ay := 0.0
	var bx := 0.0
	var by := 0.0
	var z0 := 0.0
	var z1 := 2.0
	var half := .05
	var tile := -1
	var light := .9
	var area := 0
	## Stops sight lines and shots (a chain fence or a rail may let them by).
	var sight := true
	var shots := true

	## Squared distance from (px, py) to the centre line.
	func dist2(px: float, py: float) -> float:
		var ex := bx - ax
		var ey := by - ay
		var t := clampf(((px - ax) * ex + (py - ay) * ey) / maxf(ex * ex + ey * ey, 1e-12), 0., 1.)
		var dx := px - ax - ex * t
		var dy := py - ay - ey * t
		return dx * dx + dy * dy


class Ceiling:
	var id := ""
	var x0 := 0.0
	var y0 := 0.0
	var x1 := 0.0
	var y1 := 0.0
	var cuts := PackedFloat32Array()
	var z := 2.0
	var tile := -1
	var light := .8
	var area := 0

	func inside(x: float, y: float) -> bool:
		if x < x0 or x > x1 or y < y0 or y > y1:
			return false
		for k in range(0, cuts.size(), 3):
			if cuts[k] * x + cuts[k + 1] * y > cuts[k + 2]:
				return false
		return true


var slabs: Array[Slab] = []
var segments: Array[Segment] = []
var ceilings: Array[Ceiling] = []
var width := 0
var height := 0
## cell -> Array of the slabs and segments within PAD of it.
var _index := {}
## cell -> Array of the slabs and ceilings over its footprint (for headroom).
var _over := {}
## 1 for a cell the index lists anything under.
var cells := PackedByteArray()
var _nav: NavGraph = null


## Reads a level's geometry block (null when it has none). Problems found are
## appended to `errors` as "<id>: <what>" (LevelData pushes them as errors).
static func from_json(
	block, w: int, h: int, tile_index: Dictionary, errors: Array = []
) -> LevelGeometry:
	if not (block is Dictionary) or (block as Dictionary).is_empty():
		return null
	var g := LevelGeometry.new()
	g.width = w
	g.height = h
	var version := int(block.get("version", 1))
	if version > VERSION:
		errors.append(
			"geometry: version %d is newer than this build reads (%d)" % [version, VERSION]
		)
		return null
	for s: Dictionary in block.get("slabs", []):
		var slab := Slab.new()
		slab.id = String(s.get("id", "slab%d" % g.slabs.size()))
		slab.kind = String(s.get("kind", "deck"))
		slab.x0 = float(s["x0"])
		slab.y0 = float(s["y0"])
		slab.x1 = float(s["x1"])
		slab.y1 = float(s["y1"])
		slab.cuts = _cuts(s.get("cuts", []))
		slab.top = float(s["top"])
		slab.gx = float(s.get("gx", 0.0))
		slab.gy = float(s.get("gy", 0.0))
		slab.thick = float(s.get("thick", -1.0))
		slab.tile = _tile(tile_index, s.get("tile", "porch"), errors, slab.id)
		slab.under = _tile(tile_index, s.get("under", "ceiling"), errors, slab.id)
		slab.edge = _tile(tile_index, s.get("edge", s.get("tile", "porch")), errors, slab.id)
		slab.light = float(s.get("light", .9))
		slab.area = int(s.get("area", 0))
		slab.walk = bool(s.get("walk", true))
		if slab.x1 <= slab.x0 or slab.y1 <= slab.y0:
			errors.append(
				(
					"%s: slab has no area (%s..%s, %s..%s)"
					% [slab.id, slab.x0, slab.x1, slab.y0, slab.y1]
				)
			)
			continue
		if absf(slab.gx) > STEEPEST or absf(slab.gy) > STEEPEST:
			errors.append("%s: slope steeper than %s" % [slab.id, STEEPEST])
		g.slabs.append(slab)
	for s: Dictionary in block.get("segments", []):
		var seg := Segment.new()
		seg.id = String(s.get("id", "seg%d" % g.segments.size()))
		var a: Array = s["a"]
		var b: Array = s["b"]
		seg.ax = float(a[0])
		seg.ay = float(a[1])
		seg.bx = float(b[0])
		seg.by = float(b[1])
		seg.z0 = float(s.get("z0", 0.0))
		seg.z1 = float(s.get("z1", 2.0))
		seg.half = maxf(THINNEST, float(s.get("thick", .12))) * .5
		seg.tile = _tile(tile_index, s.get("tile", "plaster"), errors, seg.id)
		seg.light = float(s.get("light", .9))
		seg.area = int(s.get("area", 0))
		seg.sight = bool(s.get("sight", true))
		seg.shots = bool(s.get("shots", seg.sight))
		if seg.z1 <= seg.z0:
			errors.append("%s: segment has no height" % seg.id)
			continue
		g.segments.append(seg)
	for s: Dictionary in block.get("ceilings", []):
		var c := Ceiling.new()
		c.id = String(s.get("id", "ceiling%d" % g.ceilings.size()))
		c.x0 = float(s["x0"])
		c.y0 = float(s["y0"])
		c.x1 = float(s["x1"])
		c.y1 = float(s["y1"])
		c.cuts = _cuts(s.get("cuts", []))
		c.z = float(s["z"])
		c.tile = _tile(tile_index, s.get("tile", "ceiling"), errors, c.id)
		c.light = float(s.get("light", .8))
		c.area = int(s.get("area", 0))
		g.ceilings.append(c)
	g._build_index()
	return g


static func _cuts(list) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for c in list:
		var nx := float(c[0])
		var ny := float(c[1])
		var length := sqrt(nx * nx + ny * ny)
		if length < 1e-6:
			continue
		out.append(nx / length)
		out.append(ny / length)
		out.append(float(c[2]) / length)
	return out


static func _tile(tile_index: Dictionary, name, errors: Array, owner: String) -> int:
	if name is float or name is int:
		return int(name)
	var key := String(name)
	if not tile_index.has(key):
		errors.append("%s: no tile named %s" % [owner, key])
		return 0
	return int(tile_index[key])


func _build_index() -> void:
	_index = {}
	_over = {}
	cells = PackedByteArray()
	cells.resize(width * height)
	cells.fill(0)
	for slab in slabs:
		_put(_index, slab.x0 - PAD, slab.y0 - PAD, slab.x1 + PAD, slab.y1 + PAD, slab, true)
		if slab.thick >= 0.0:
			_put(_over, slab.x0, slab.y0, slab.x1, slab.y1, slab, false)
	for seg in segments:
		_put(
			_index,
			minf(seg.ax, seg.bx) - PAD,
			minf(seg.ay, seg.by) - PAD,
			maxf(seg.ax, seg.bx) + PAD,
			maxf(seg.ay, seg.by) + PAD,
			seg,
			true
		)
	for c in ceilings:
		_put(_over, c.x0, c.y0, c.x1, c.y1, c, true)


func _put(into: Dictionary, x0: float, y0: float, x1: float, y1: float, item, mark: bool) -> void:
	for cy in range(maxi(0, floori(y0)), mini(height - 1, floori(y1)) + 1):
		for cx in range(maxi(0, floori(x0)), mini(width - 1, floori(x1)) + 1):
			var key := cy * width + cx
			if not into.has(key):
				into[key] = []
			into[key].append(item)
			if mark:
				cells[key] = 1


const NOTHING: Array = []


func near_items(x: float, y: float) -> Array:
	if x < 0.0 or y < 0.0 or x >= width or y >= height:
		return NOTHING
	var c := int(y) * width + int(x)
	if cells[c] == 0:
		return NOTHING
	return _index.get(c, NOTHING)


## Whether nothing of the geometry is within reach of (x, y): its answers are
## the grid's own there (the fast way, for the most of every level). Cells are
## marked out to PAD each way, so it holds for a body narrower than PAD.
func clear_at(x: float, y: float) -> bool:
	return (
		x >= 0.0 and y >= 0.0 and x < width and y < height and cells[int(y) * width + int(x)] == 0
	)


## The highest floor under feet at z at (x, y): the cell's ground (`ground`,
## or none when `open` is false) or a walkable slab's top at most STEP above
## the feet. -1e9 when there is none.
func floor_at(x: float, y: float, z: float, ground: float, open: bool) -> float:
	var best := ground if open else -1e9
	for item in near_items(x, y):
		if item is Slab:
			var s: Slab = item
			if not s.walk or not s.inside(x, y):
				continue
			var t := s.top_at(x, y)
			if t <= z + STEP + .001 and t > best:
				best = t
	return best


## The floor holding up a body of radius r with its feet at `feet`: the floor
## under its middle, or a floor at most as high as its feet under any part of
## it (a body half off a deck's edge still stands on the deck until it is clear
## of it, then falls).
func support(x: float, y: float, r: float, feet: float, ground: float) -> float:
	if r < PAD and clear_at(x, y):
		return ground
	var best := floor_at(x, y, feet, ground, true)
	for k in 4:
		var px := x + (r if k & 1 else -r)
		var py := y + (r if k & 2 else -r)
		best = maxf(best, floor_at(px, py, feet - STEP, -1e9, false))
	return best


## The lowest surface overhead of a point at z (a slab's underside, a
## ceiling): INF when nothing of the geometry is over it.
func ceiling_at(x: float, y: float, z: float) -> float:
	var best := INF
	if x < 0.0 or y < 0.0 or x >= width or y >= height or cells[int(y) * width + int(x)] == 0:
		return best
	for item in _over.get(int(y) * width + int(x), NOTHING):
		if item is Slab:
			var s: Slab = item
			if s.inside(x, y):
				var b := s.bottom_at(x, y)
				if b > z + .01 and b < best:
					best = b
		else:
			var c: Ceiling = item
			if c.z > z + .01 and c.z < best and c.inside(x, y):
				best = c.z
	return best


## Whether a body of radius r at (x, y) spanning lo..hi meets a slab or a
## segment.
func blocks(x: float, y: float, r: float, lo: float, hi: float) -> bool:
	for item in near_items(x, y):
		if item is Slab:
			var s: Slab = item
			if not s.near(x, y, r):
				continue
			var t := s.top_at(x, y)
			if s.sloped():
				# A slope's edge: the highest of its top within the body's reach.
				t = maxf(t, maxf(s.top_at(x - r, y - r), s.top_at(x + r, y + r)))
				t = maxf(t, maxf(s.top_at(x - r, y + r), s.top_at(x + r, y - r)))
			if t > lo and s.bottom_at(x, y) < hi:
				return true
		else:
			var g: Segment = item
			if g.z0 < hi and g.z1 > lo:
				var reach := r + g.half
				if g.dist2(x, y) < reach * reach:
					return true
	return false


## Whether the point (x, y, z) is inside something that stops sight (`shots`
## false) or shots (`shots` true), grown by r across.
func solid_point(x: float, y: float, z: float, r: float, shots: bool) -> bool:
	for item in near_items(x, y):
		if item is Slab:
			var s: Slab = item
			if s.near(x, y, r) and z <= s.top_at(x, y) and z >= s.bottom_at(x, y):
				return true
		else:
			var g: Segment = item
			if (g.shots if shots else g.sight) and z >= g.z0 and z <= g.z1:
				var reach := r + g.half
				if g.dist2(x, y) < reach * reach:
					return true
	return false


## Whether a short step from (x0, y0, z0) to (x1, y1, z1) passes through a
## slab's top or underside between its ends (a step longer than a deck is
## thick could jump it).
func crosses(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float) -> bool:
	for item in near_items(x1, y1):
		if not (item is Slab):
			continue
		var s: Slab = item
		if not s.inside(x1, y1) or not s.inside(x0, y0):
			continue
		var t := s.top_at(x1, y1)
		if (z0 >= t) != (z1 >= t):
			return true
		var b := s.bottom_at(x1, y1)
		if b > -1e8 and (z0 <= b) != (z1 <= b):
			return true
	return false


## Whether any slab is a floor over (x, y) (the shader's weather: no rain under it).
func covered(x: float, y: float, ground: float) -> bool:
	for item in _over.get(int(y) * width + int(x), NOTHING):
		if item is Slab and (item as Slab).inside(x, y) and (item as Slab).bottom_at(x, y) > ground:
			return true
		if item is Ceiling and (item as Ceiling).inside(x, y):
			return true
	return false


# ------------------------------------------------------------- rendering


## The footprint of a rectangle cut by lines, as a clockwise polygon (map axes,
## y down): x, y pairs.
static func outline(
	x0: float, y0: float, x1: float, y1: float, cuts: PackedFloat32Array
) -> PackedVector2Array:
	var poly := PackedVector2Array(
		[Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]
	)
	for k in range(0, cuts.size(), 3):
		var n := Vector2(cuts[k], cuts[k + 1])
		var c := cuts[k + 2]
		var out := PackedVector2Array()
		for i in poly.size():
			var p := poly[i]
			var q := poly[(i + 1) % poly.size()]
			var dp := n.dot(p) - c
			var dq := n.dot(q) - c
			if dp <= 0.0:
				out.append(p)
			if (dp <= 0.0) != (dq <= 0.0):
				out.append(p + (q - p) * (dp / (dp - dq)))
		poly = out
		if poly.size() < 3:
			return PackedVector2Array()
	return poly


## What the renderers draw for it:
##   "walls": wall rows (LevelData.WALL_STRIDE each), slab edges and segments
##   "caps": height -> [x0, y0, x1, y1, tile, cuts...] flat floors seen from above
##   "roof_caps": height -> [...] flat surfaces seen from below
##   "slopes": [z0, gx, gy, side, x0, y0, x1, y1, tile, light, area, cuts...]
## `ground` gives a cell's floor (an edge or a wedge stops there).
func render_parts(ground: Callable) -> Dictionary:
	var walls := PackedFloat32Array()
	var caps := {}
	var roof_caps := {}
	var slopes: Array = []
	for s in slabs:
		var poly := outline(s.x0, s.y0, s.x1, s.y1, s.cuts)
		if poly.size() < 3:
			continue
		if s.sloped():
			slopes.append(_slope_row(s, s.top, 1.0, s.tile))
			if s.thick >= 0.0:
				slopes.append(_slope_row(s, s.top - s.thick, -1.0, s.under))
		else:
			_add_cap(caps, s.top, s, s.tile)
			if s.thick >= 0.0:
				_add_cap(roof_caps, s.top - s.thick, s, s.under)
		# The sides: each edge of the outline from the underside (or the ground)
		# up to the top, in strips where the top slopes along it.
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var length := a.distance_to(b)
			if length < .001:
				continue
			var strips := 1
			if s.sloped():
				var rise := absf(s.top_at(b.x, b.y) - s.top_at(a.x, a.y))
				strips = clampi(int(ceil(rise / .1)), 1, 64)
			for k in strips:
				var p := a.lerp(b, float(k) / strips)
				var q := a.lerp(b, float(k + 1) / strips)
				var mid := (p + q) * .5
				var top := s.top_at(mid.x, mid.y)
				if s.sloped():
					top = maxf(s.top_at(p.x, p.y), s.top_at(q.x, q.y))
				var bottom := s.bottom_at(mid.x, mid.y)
				if s.thick < 0.0:
					bottom = float(ground.call(mid.x, mid.y))
				if top - bottom < .005:
					continue
				walls.append_array(
					PackedFloat32Array([p.x, p.y, q.x, q.y, s.edge, s.light, bottom, top, s.area])
				)
	for g in segments:
		var length := Vector2(g.bx - g.ax, g.by - g.ay).length()
		if length < .001:
			continue
		if g.half * 2.0 < .2:
			walls.append_array(
				PackedFloat32Array([g.ax, g.ay, g.bx, g.by, g.tile, g.light, g.z0, g.z1, g.area])
			)
			continue
		# A thick wall: its two faces, its ends and (when low) its top.
		var d := Vector2(g.bx - g.ax, g.by - g.ay) / length
		var n := Vector2(-d.y, d.x) * g.half
		var c := [
			Vector2(g.ax, g.ay) - n,
			Vector2(g.bx, g.by) - n,
			Vector2(g.bx, g.by) + n,
			Vector2(g.ax, g.ay) + n
		]
		for i in 4:
			var p: Vector2 = c[i]
			var q: Vector2 = c[(i + 1) % 4]
			walls.append_array(
				PackedFloat32Array([p.x, p.y, q.x, q.y, g.tile, g.light, g.z0, g.z1, g.area])
			)
		if g.z1 < 1.5:
			var key := snappedf(g.z1, .001)
			if not caps.has(key):
				caps[key] = []
			var x0 := minf(minf(c[0].x, c[1].x), minf(c[2].x, c[3].x))
			var x1 := maxf(maxf(c[0].x, c[1].x), maxf(c[2].x, c[3].x))
			var y0 := minf(minf(c[0].y, c[1].y), minf(c[2].y, c[3].y))
			var y1 := maxf(maxf(c[0].y, c[1].y), maxf(c[2].y, c[3].y))
			var row := [x0, y0, x1, y1, g.tile]
			if d.x != 0.0 and d.y != 0.0:
				# An angled wall's top: its box cut down to the wall's band.
				for sign: float in [1.0, -1.0]:
					var nn := Vector2(-d.y, d.x) * sign
					row.append_array([nn.x, nn.y, nn.dot(Vector2(g.ax, g.ay)) + g.half])
			caps[key].append(row)
	for c in ceilings:
		var row := [c.x0, c.y0, c.x1, c.y1, c.tile]
		row.append_array(Array(c.cuts))
		var key := snappedf(c.z, .001)
		if not roof_caps.has(key):
			roof_caps[key] = []
		roof_caps[key].append(row)
	return {"walls": walls, "caps": caps, "roof_caps": roof_caps, "slopes": slopes}


func _add_cap(into: Dictionary, z: float, s: Slab, tile: int) -> void:
	var key := snappedf(z, .001)
	if not into.has(key):
		into[key] = []
	var row := [s.x0, s.y0, s.x1, s.y1, tile]
	row.append_array(Array(s.cuts))
	into[key].append(row)


func _slope_row(s: Slab, z0: float, side: float, tile: int) -> Array:
	var row := [z0, s.gx, s.gy, side, s.x0, s.y0, s.x1, s.y1, tile, s.light, s.area]
	row.append_array(Array(s.cuts))
	return row


# --------------------------------------------------------- bodies


## What never moves, for a body of radius r with its feet at `feet`, `tall`
## high: the grid's solid cells (not a door's), furniture at its height, the
## geometry. The nav graph's test.
func static_blocked(lv, x: float, y: float, r: float, feet: float, tall: float) -> bool:
	for step in 4:
		var ix := int(x + (-r if step < 2 else r))
		var iy := int(y + (-r if step % 2 == 0 else r))
		if ix < 0 or iy < 0 or ix >= lv.width or iy >= lv.height:
			return true
		var c: int = iy * lv.width + ix
		if lv.solid[c] >= 0 and not lv.door_cells.has(c):
			return true
	if _fixture_in(lv, x, y, r, feet, tall):
		return true
	return blocks(x, y, r, feet + STEP, feet + tall)


func _fixture_in(lv, x: float, y: float, r: float, feet: float, tall: float) -> bool:
	var list: Array = (
		lv.near_fixtures.get(Vector2i(int(x), int(y)), NOTHING)
		if r <= lv.index_radius
		else lv.collision_volumes
	)
	for fixture in list:
		var f: PackedFloat32Array = fixture
		if (
			f[0] - r < x
			and x < f[2] + r
			and f[1] - r < y
			and y < f[3] + r
			and f[7] < feet + tall
			and f[4] > feet + .01
		):
			return true
	return false


## blocked() for a body at its own height (format 2): what static_blocked()
## asks, doors and panes and locked gates too, the grid's solid cells as
## blocked() has them.
func blocked_body(lv, x: float, y: float, r: float, feet: float, tall: float) -> bool:
	for step in 4:
		var ix := int(x + (-r if step < 2 else r))
		var iy := int(y + (-r if step % 2 == 0 else r))
		if ix < 0 or iy < 0 or ix >= lv.width or iy >= lv.height:
			return true
		if lv.solid[iy * lv.width + ix] >= 0:
			return true
	if not lv.pane_tiles.is_empty() and feet < 1.83 and lv.pane_at(x, y, null, r) != null:
		return true
	for gate: LevelData.Gate in lv.locked_gates:
		if absf(y - gate.y) < r + .09 and absf(x - gate.x) < gate.width * .5 + r:
			return true
	if _fixture_in(lv, x, y, r, feet, tall):
		return true
	if feet < 1.85:
		for door in lv.near_doors.get(Vector2i(int(x), int(y)), NOTHING):
			if (door as LevelData.Door).blocks(x, y, r):
				return true
	return blocks(x, y, r, feet + STEP, feet + tall)


func can_walk(lv, body, x: float, y: float, radius: float, occupied) -> bool:
	var player: bool = not (body is Enemy) and ("air" in body)
	var air: float = float(body.air) if player else 0.0
	# The floor it stands on now, worked out again: something that moved it
	# without walking (a bridge, a shove, a script) leaves floor_z behind, and
	# the grid's own steps are measured from the cell it is in, as ever.
	var here: int = lv.cell(body.x, body.y)
	var floor_z := support(body.x, body.y, radius, float(body.floor_z), lv.ground[here])
	body.floor_z = floor_z
	var feet := floor_z + air
	var tall: float = BODY
	if body is Enemy:
		tall = minf(BODY, maxf(.4, float(body.height)))
	elif player and body.crouched:
		tall = CROUCH
	if blocked_body(lv, x, y, radius, feet, tall):
		return false
	if (
		lv.deep_tile >= 0
		and lv.deep_at(x, y)
		and not lv.deep_at(body.x, body.y)
		and not body.get("swims")
	):
		return false
	if occupied != null and occupied.call(x, y):
		return false
	var c: int = lv.cell(x, y)
	var under := floor_at(x, y, feet, lv.ground[c], true)
	if player and under - floor_z > STEP + air + .001:
		return false
	var over := minf(ceiling_at(x, y, under), _roof(lv, c, under))
	return over - under >= CROUCH


## After a move (format 2): the floor under the body now. A player who walked
## off an edge is in the air above the lower floor and falls; one who stepped
## up stands on the higher one.
func settle(lv, body, radius := .2) -> void:
	var c: int = lv.cell(body.x, body.y)
	var player: bool = not (body is Enemy) and ("air" in body)
	var feet: float = float(body.floor_z) + (float(body.air) if player else 0.0)
	var under := support(body.x, body.y, radius, feet, lv.ground[c])
	if player:
		body.air = maxf(0.0, feet - under)
	body.floor_z = under


# ------------------------------------------------------------------- nav


## The walkable places as a graph for FlowField: node n < width * height is
## the cell n's own floor (the grid's, or the top of a solid slab standing on
## it: a stair tread, a ramp), the rest stand on decks over it. Edges join
## places a body can walk between both ways.
class NavGraph:
	var count := 0
	var cells := 0
	var cell := PackedInt32Array()
	var z := PackedFloat32Array()
	## Orthogonal neighbours (CSR: first[n] .. first[n + 1] in edges).
	var first := PackedInt32Array()
	var edges := PackedInt32Array()
	## Diagonal neighbours, the same way (only where both sides are walkable).
	var dfirst := PackedInt32Array()
	var dedges := PackedInt32Array()
	## cell -> the deck nodes over it (a cell's own node is the cell).
	var over := {}

	## The node a body at (x, y) with feet at z stands on (NAN: the cell's own).
	func node_at(x: float, y: float, w: int, h: int, feet: float) -> int:
		if x < 0.0 or y < 0.0 or x >= w or y >= h:
			return -1
		var c := int(y) * w + int(x)
		if is_nan(feet) or not over.has(c):
			return c
		var best := c
		var best_z := z[c]
		for n: int in over[c]:
			var nz := z[n]
			if nz <= feet + .5 and (nz > best_z or best_z > feet + .5):
				best = n
				best_z = nz
		return best

	func around(n: int) -> PackedInt32Array:
		return edges.slice(first[n], first[n + 1])


## The nav graph, built when first asked (FlowField).
func nav(lv) -> NavGraph:
	if _nav != null:
		return _nav
	var g := NavGraph.new()
	var n_cells := width * height
	g.cells = n_cells
	g.cell.resize(n_cells)
	g.z.resize(n_cells)
	for c in n_cells:
		g.cell[c] = c
		g.z[c] = lv.ground[c]
	var extra_cell := PackedInt32Array()
	var extra_z := PackedFloat32Array()
	for s in slabs:
		if not s.walk:
			continue
		for cy in range(maxi(0, floori(s.y0)), mini(height - 1, floori(s.y1)) + 1):
			for cx in range(maxi(0, floori(s.x0)), mini(width - 1, floori(s.x1)) + 1):
				var mx := cx + .5
				var my := cy + .5
				var c := cy * width + cx
				if not s.inside(mx, my) or lv.solid[c] >= 0:
					continue
				var top := s.top_at(mx, my)
				if s.thick < 0.0 or top - lv.ground[c] <= STEP:
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
	var lists: Array = []
	lists.resize(g.count)
	for n in g.count:
		lists[n] = PackedInt32Array()
	for n in g.count:
		var c := g.cell[n]
		var cx := c % width
		var cy := c / width
		for d: Vector2i in orth:
			var nx := cx + d.x
			var ny := cy + d.y
			if nx < 0 or ny < 0 or nx >= width or ny >= height:
				continue
			var c2 := ny * width + nx
			var plain := n < n_cells and cells[c] == 0 and cells[c2] == 0
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
				elif _walks(lv, g, n, m) and _walks(lv, g, m, n):
					lists[n].append(m)
					lists[m].append(n)
	g.first.resize(g.count + 1)
	var total := 0
	for n in g.count:
		g.first[n] = total
		total += (lists[n] as PackedInt32Array).size()
	g.first[g.count] = total
	for n in g.count:
		g.edges.append_array(lists[n])
	# Diagonals: n to m when each side cell leads from n to m.
	g.dfirst.resize(g.count + 1)
	var dtotal := 0
	var dlists: Array = []
	for n in g.count:
		var found := PackedInt32Array()
		var c := g.cell[n]
		var near := g.around(n)
		for a in near:
			for m in g.around(a):
				var cm := g.cell[m]
				if absi(cm % width - c % width) != 1 or absi(cm / width - c / width) != 1:
					continue
				if found.has(m):
					continue
				# Never past the corner the two cells share when something stands
				# on it (a porch post on a cell corner): a body cutting the corner
				# would wedge on it.
				var corner := Vector2(
					(c % width + cm % width + 1) * .5, (c / width + cm / width + 1) * .5
				)
				if static_blocked(
					lv, corner.x, corner.y, NAV_BODY * .6, minf(g.z[n], g.z[m]), BODY
				):
					continue
				for b in near:
					if b != a and g.cell[b] != g.cell[a] and g.around(b).has(m):
						found.append(m)
						break
		dlists.append(found)
		g.dfirst[n] = dtotal
		dtotal += found.size()
	g.dfirst[g.count] = dtotal
	for n in g.count:
		g.dedges.append_array(dlists[n])
	_nav = g
	return g


## Whether node n's middle is somewhere a body can stand (FlowField's open
## floor on a level with geometry; doors and panes are FlowField's to ask).
func stands(lv, g: NavGraph, n: int) -> bool:
	var c := g.cell[n]
	var x := c % width + .5
	var y := c / width + .5
	var feet := g.z[n]
	if static_blocked(lv, x, y, NAV_BODY, feet, BODY):
		return false
	return minf(ceiling_at(x, y, feet), _roof(lv, c, feet)) - feet >= CROUCH


## Whether a body walks from node n's middle to node m's (sub-stepped: the
## enemies' rule, the grid's own steps free, slabs at most STEP up, nothing in
## the way at the body's height, headroom for a crouch).
func _walks(lv, g: NavGraph, n: int, m: int) -> bool:
	var a := g.cell[n]
	var b := g.cell[m]
	var ax := a % width + .5
	var ay := a / width + .5
	var bx := b % width + .5
	var by := b / width + .5
	var feet := g.z[n]
	for k in range(1, NAV_STEPS + 1):
		var f := float(k) / NAV_STEPS
		var x := ax + (bx - ax) * f
		var y := ay + (by - ay) * f
		var c := int(y) * width + int(x)
		var floor_z := floor_at(x, y, feet, lv.ground[c], true)
		if floor_z > feet + STEP + .002 and floor_z > lv.ground[c] + .001:
			return false
		feet = floor_z
		if static_blocked(lv, x, y, NAV_BODY, feet, BODY):
			return false
		if minf(ceiling_at(x, y, feet), _roof(lv, c, feet)) - feet < CROUCH:
			return false
	return absf(feet - g.z[m]) < .06


static func _roof(lv, c: int, feet: float) -> float:
	# A roof of 0 is the open sky (a sunken floor's too: the pond).
	var r: float = lv.roof[c]
	return r if r != 0.0 and r > feet + .01 else INF
