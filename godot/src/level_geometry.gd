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
	## The top at b (a gable end, a raking wall, an arch's haunch): the top
	## runs straight from z1 at a to z1b at b. Equal to z1 for a level top.
	var z1b := 2.0
	var half := .05
	var tile := -1
	var light := .9
	var area := 0
	## Stops sight lines and shots (a chain fence or a rail may let them by).
	var sight := true
	var shots := true

	func raked() -> bool:
		return z1b != z1

	func top_max() -> float:
		return maxf(z1, z1b)

	## The top over the centre line nearest (px, py), grown by `reach` along
	## the wall toward the higher end (a body touching the wall meets the top
	## anywhere within its reach). z1 itself for a level top.
	func top_near(px: float, py: float, reach: float) -> float:
		if z1b == z1:
			return z1
		var ex := bx - ax
		var ey := by - ay
		var length2 := maxf(ex * ex + ey * ey, 1e-12)
		var t := ((px - ax) * ex + (py - ay) * ey) / length2
		t += reach / sqrt(length2) * (1.0 if z1b > z1 else -1.0)
		return z1 + (z1b - z1) * clampf(t, 0.0, 1.0)

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


## A ladder (src/climbing.gd climbs it): leaning on a face at (x, y), climbed
## facing (dx, dy) from the floor at z0 up to the floor at z1 beyond the face.
## Seen as rails and rungs (render_parts); it stops nothing.
class Ladder:
	var id := ""
	var x := 0.0
	var y := 0.0
	var dx := 0.0
	var dy := -1.0
	var z0 := 0.0
	var z1 := 2.0
	var tile := -1
	var light := .85
	var area := 0

	## Where a climber stands at its foot (FOOT out from the face).
	func foot() -> Vector2:
		return Vector2(x - dx * FOOT, y - dy * FOOT)

	## Where a climber steps off at the top (TOP in over the floor beyond).
	func top() -> Vector2:
		return Vector2(x + dx * TOP, y + dy * TOP)


## A climber stands this far out from the face a ladder leans on, and steps
## off this far in at the top.
const FOOT := .36
const TOP := .5
## Rungs are this far apart (a climb's footsteps fall on them).
const RUNG := .3
const LADDER_DIRS := {
	"n": Vector2(0, -1), "s": Vector2(0, 1), "e": Vector2(1, 0), "w": Vector2(-1, 0)
}

var slabs: Array[Slab] = []
var segments: Array[Segment] = []
var ceilings: Array[Ceiling] = []
var ladders: Array[Ladder] = []
## Every slab edge render_parts() made: Vector4(ax, ay, bx, by) -> its tile (the
## 3D view lays a stretched material along a stair's side by the metre).
var slab_edges := {}
var width := 0
var height := 0
## cell -> Array of the slabs and segments within PAD of it.
var _index := {}
## cell -> Array of the slabs and ceilings over its footprint (for headroom).
var _over := {}
## 1 for a cell the index lists anything under.
var cells := PackedByteArray()
## The heights that may stop a sight line in each cell: for cell c the
## pairs band_low, band_high from sight_bands[sight_band_at[c]] up to
## sight_bands[sight_band_at[c + 1]], sorted and merged, each spanning all of
## what one or more of its index's slabs and sight-stopping segments fill
## (a slab from its lowest bottom to its highest top anywhere). A step of a
## sight line at heights outside every band, without passing one, meets
## nothing of the geometry there (sight_clear(); LevelSight.visible).
var sight_band_at := PackedInt32Array()
var sight_bands := PackedFloat64Array()
var _nav: NavGraph = null
## LevelData.source_key -> the nav graph of that level as read (nav()), the
## last NAVS_KEPT levels.
const NAVS_KEPT := 4
static var _navs: Dictionary = {}


## Reads a level's geometry block (null when it has none). Problems found are
## appended to `errors` as "<id>: <what>" (LevelData pushes them as errors).
static func from_json(
	block: Variant, w: int, h: int, tile_index: Dictionary, errors: Array = []
) -> LevelGeometry:
	if not (block is Dictionary):
		return null
	var data: Dictionary = block
	if data.is_empty():
		return null
	var g := LevelGeometry.new()
	g.width = w
	g.height = h
	var version: int = data.get("version", 1)
	if version > VERSION:
		errors.append(
			"geometry: version %d is newer than this build reads (%d)" % [version, VERSION]
		)
		return null
	for s: Dictionary in data.get("slabs", []):
		var slab := Slab.new()
		slab.id = str(s.get("id", "slab%d" % g.slabs.size()))
		slab.kind = str(s.get("kind", "deck"))
		slab.x0 = s["x0"]
		slab.y0 = s["y0"]
		slab.x1 = s["x1"]
		slab.y1 = s["y1"]
		slab.cuts = _cuts(s.get("cuts", []))
		slab.top = s["top"]
		slab.gx = s.get("gx", 0.0)
		slab.gy = s.get("gy", 0.0)
		slab.thick = s.get("thick", -1.0)
		slab.tile = _tile(tile_index, s.get("tile", "porch"), errors, slab.id)
		slab.under = _tile(tile_index, s.get("under", "ceiling"), errors, slab.id)
		slab.edge = _tile(tile_index, s.get("edge", s.get("tile", "porch")), errors, slab.id)
		slab.light = s.get("light", .9)
		slab.area = s.get("area", 0)
		slab.walk = s.get("walk", true)
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
	for s: Dictionary in data.get("segments", []):
		var seg := Segment.new()
		seg.id = str(s.get("id", "seg%d" % g.segments.size()))
		var a: Array = s["a"]
		var b: Array = s["b"]
		seg.ax = a[0]
		seg.ay = a[1]
		seg.bx = b[0]
		seg.by = b[1]
		seg.z0 = s.get("z0", 0.0)
		seg.z1 = s.get("z1", 2.0)
		seg.z1b = s.get("z1b", seg.z1)
		var thick: float = s.get("thick", .12)
		seg.half = maxf(THINNEST, thick) * .5
		seg.tile = _tile(tile_index, s.get("tile", "plaster"), errors, seg.id)
		seg.light = s.get("light", .9)
		seg.area = s.get("area", 0)
		seg.sight = s.get("sight", true)
		seg.shots = s.get("shots", seg.sight)
		# A raked top may come down to the foot at one end (a gable's).
		if seg.top_max() <= seg.z0 or minf(seg.z1, seg.z1b) < seg.z0:
			errors.append("%s: segment has no height" % seg.id)
			continue
		g.segments.append(seg)
	for s: Dictionary in data.get("ceilings", []):
		var c := Ceiling.new()
		c.id = str(s.get("id", "ceiling%d" % g.ceilings.size()))
		c.x0 = s["x0"]
		c.y0 = s["y0"]
		c.x1 = s["x1"]
		c.y1 = s["y1"]
		c.cuts = _cuts(s.get("cuts", []))
		c.z = s["z"]
		c.tile = _tile(tile_index, s.get("tile", "ceiling"), errors, c.id)
		c.light = s.get("light", .8)
		c.area = s.get("area", 0)
		g.ceilings.append(c)
	for s: Dictionary in data.get("ladders", []):
		var lad := Ladder.new()
		lad.id = str(s.get("id", "ladder%d" % g.ladders.size()))
		lad.x = s["x"]
		lad.y = s["y"]
		var way: Vector2 = LADDER_DIRS.get(str(s.get("dir", "n")), Vector2.ZERO)
		if way == Vector2.ZERO:
			errors.append("%s: ladder dir is n, e, s or w" % lad.id)
			continue
		lad.dx = way.x
		lad.dy = way.y
		lad.z0 = s.get("z0", 0.0)
		lad.z1 = s["z1"]
		lad.tile = _tile(tile_index, s.get("tile", "porch"), errors, lad.id)
		lad.light = s.get("light", .85)
		lad.area = s.get("area", 0)
		if lad.z1 <= lad.z0 + STEP:
			errors.append("%s: ladder climbs nothing" % lad.id)
			continue
		g.ladders.append(lad)
	g._build_index()
	return g


static func _cuts(list: Variant) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for c: Variant in list:
		var nx: float = c[0]
		var ny: float = c[1]
		var length := sqrt(nx * nx + ny * ny)
		if length < 1e-6:
			continue
		out.append(nx / length)
		out.append(ny / length)
		var d: float = c[2]
		out.append(d / length)
	return out


static func _tile(tile_index: Dictionary, name: Variant, errors: Array, owner: String) -> int:
	if name is float or name is int:
		var number: int = name
		return number
	var key := str(name)
	if not tile_index.has(key):
		errors.append("%s: no tile named %s" % [owner, key])
		return 0
	var at: int = tile_index[key]
	return at


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
	_build_sight_bands()


## A band's margin past what it spans (rounding never lets a test slip by).
const BAND_SLACK := 1e-4


func _build_sight_bands() -> void:
	sight_band_at = PackedInt32Array()
	sight_band_at.resize(width * height + 1)
	sight_bands = PackedFloat64Array()
	for c in width * height:
		sight_band_at[c] = sight_bands.size()
		if cells[c] == 0:
			continue
		var spans: Array[Vector2] = []
		for item: Variant in _index.get(c, NOTHING):
			if item is Slab:
				var sl: Slab = item
				var low := -1e12 if sl.thick < 0.0 else sl.top_min() - sl.thick
				spans.append(Vector2(low, sl.top_max()))
			elif item is Segment:
				var g: Segment = item
				if g.sight:
					spans.append(Vector2(g.z0, g.top_max()))
		spans.sort()
		var low := 0.0
		var high := 0.0
		for k in spans.size():
			var span: Vector2 = spans[k]
			if k > 0 and span.x - BAND_SLACK <= high + BAND_SLACK:
				high = maxf(high, span.y)
				continue
			if k > 0:
				sight_bands.append(low - BAND_SLACK)
				sight_bands.append(high + BAND_SLACK)
			low = span.x
			high = span.y
		if not spans.is_empty():
			sight_bands.append(low - BAND_SLACK)
			sight_bands.append(high + BAND_SLACK)
	sight_band_at[width * height] = sight_bands.size()


## Whether a sight line's step from height z0 to z1 ending in cell c meets
## nothing of the geometry: z1 in no band and no band between z0 and z1, so
## neither solid_point() nor crosses() could stop it there. False: ask them
## (it never says clear where they would not).
func sight_clear(c: int, z0: float, z1: float) -> bool:
	for k in range(sight_band_at[c], sight_band_at[c + 1], 2):
		var low := sight_bands[k]
		var high := sight_bands[k + 1]
		if z1 >= low and z1 <= high:
			return false
		if (z0 < low) != (z1 < low) or (z0 > high) != (z1 > high):
			return false
	return true


func _put(
	into: Dictionary, x0: float, y0: float, x1: float, y1: float, item: RefCounted, mark: bool
) -> void:
	for cy in range(maxi(0, floori(y0)), mini(height - 1, floori(y1)) + 1):
		for cx in range(maxi(0, floori(x0)), mini(width - 1, floori(x1)) + 1):
			var key := cy * width + cx
			if not into.has(key):
				into[key] = []
			var list: Array = into[key]
			list.append(item)
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
	for item: Variant in near_items(x, y):
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
	for item: Variant in _over.get(int(y) * width + int(x), NOTHING):
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
	for item: Variant in near_items(x, y):
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
			if g.z0 < hi and g.top_near(x, y, r) > lo:
				var reach := r + g.half
				if g.dist2(x, y) < reach * reach:
					return true
	return false


## Whether the point (x, y, z) is inside something that stops sight (`shots`
## false) or shots (`shots` true), grown by r across.
func solid_point(x: float, y: float, z: float, r: float, shots: bool) -> bool:
	for item: Variant in near_items(x, y):
		if item is Slab:
			var s: Slab = item
			if s.near(x, y, r) and z <= s.top_at(x, y) and z >= s.bottom_at(x, y):
				return true
		else:
			var g: Segment = item
			if (g.shots if shots else g.sight) and z >= g.z0 and z <= g.top_near(x, y, r):
				var reach := r + g.half
				if g.dist2(x, y) < reach * reach:
					return true
	return false


## Whether a short step from (x0, y0, z0) to (x1, y1, z1) passes through a
## slab's top or underside between its ends (a step longer than a deck is
## thick could jump it).
func crosses(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float) -> bool:
	for item: Variant in near_items(x1, y1):
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
	for item: Variant in _over.get(int(y) * width + int(x), NOTHING):
		if item is Slab:
			var s: Slab = item
			if s.inside(x, y) and s.bottom_at(x, y) > ground:
				return true
		if item is Ceiling:
			var c: Ceiling = item
			if c.inside(x, y):
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
				strips = clampi(int(ceilf(rise / .1)), 1, 64)
			for k in strips:
				var p := a.lerp(b, float(k) / strips)
				var q := a.lerp(b, float(k + 1) / strips)
				var mid := (p + q) * .5
				var top := s.top_at(mid.x, mid.y)
				if s.sloped():
					top = maxf(s.top_at(p.x, p.y), s.top_at(q.x, q.y))
				var bottom := s.bottom_at(mid.x, mid.y)
				if s.thick < 0.0:
					bottom = ground.call(mid.x, mid.y)
				if top - bottom < .005:
					continue
				walls.append_array(
					PackedFloat32Array([p.x, p.y, q.x, q.y, s.edge, s.light, bottom, top, s.area])
				)
				slab_edges[Vector4(p.x, p.y, q.x, q.y)] = s.edge
	for g in segments:
		var length := Vector2(g.bx - g.ax, g.by - g.ay).length()
		if length < .001:
			continue
		if g.half * 2.0 < .2:
			_face_rows(walls, g, Vector2(g.ax, g.ay), Vector2(g.bx, g.by), g.z1, g.z1b)
			continue
		# A thick wall: its two faces, its ends and (when low) its top.
		var d := Vector2(g.bx - g.ax, g.by - g.ay) / length
		var n := Vector2(-d.y, d.x) * g.half
		var c: Array[Vector2] = [
			Vector2(g.ax, g.ay) - n,
			Vector2(g.bx, g.by) - n,
			Vector2(g.bx, g.by) + n,
			Vector2(g.ax, g.ay) + n
		]
		# Each face's top at its two ends (a raked wall's faces slope with it).
		var tops: Array[float] = [g.z1, g.z1b, g.z1b, g.z1b, g.z1b, g.z1, g.z1, g.z1]
		for i in 4:
			var p: Vector2 = c[i]
			var q: Vector2 = c[(i + 1) % 4]
			_face_rows(walls, g, p, q, tops[i * 2], tops[i * 2 + 1])
		if g.z1 < 1.5 and not g.raked():
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
			var at_key: Array = caps[key]
			at_key.append(row)
	for c in ceilings:
		var row := [c.x0, c.y0, c.x1, c.y1, c.tile]
		row.append_array(Array(c.cuts))
		var key := snappedf(c.z, .001)
		if not roof_caps.has(key):
			roof_caps[key] = []
		var at_key: Array = roof_caps[key]
		at_key.append(row)
	for lad in ladders:
		walls.append_array(ladder_rows(lad))
	return {"walls": walls, "caps": caps, "roof_caps": roof_caps, "slopes": slopes}


## A ladder's pieces as wall rows: two square rails from its floor to a
## hand-hold over the top, and a rung every RUNG up to the top.
static func ladder_rows(lad: Ladder) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var d := Vector2(lad.dx, lad.dy)
	var side := Vector2(-d.y, d.x)
	var base := Vector2(lad.x, lad.y) - d * .07
	var half := .025
	for s: float in [-1.0, 1.0]:
		var mid := base + side * (.22 * s)
		var c: Array[Vector2] = [
			mid - d * half - side * half,
			mid + d * half - side * half,
			mid + d * half + side * half,
			mid - d * half + side * half
		]
		for i in 4:
			var p: Vector2 = c[i]
			var q: Vector2 = c[(i + 1) % 4]
			out.append_array(
				PackedFloat32Array(
					[p.x, p.y, q.x, q.y, lad.tile, lad.light, lad.z0, lad.z1 + .8, lad.area]
				)
			)
	var a := base - side * .22
	var b := base + side * .22
	var z := lad.z0 + .26
	while z < lad.z1 + .6:
		for k: float in [-half, half]:
			var pa := a + d * k
			var pb := b + d * k
			out.append_array(
				PackedFloat32Array(
					[pa.x, pa.y, pb.x, pb.y, lad.tile, lad.light * .9, z, z + .045, lad.area]
				)
			)
		z += RUNG
	return out


## A segment's face from p (top ta) to q (top tb) as wall rows: one row for a
## level top, else strips RAKE_STRIP high at most, each topped at its higher
## end (the step hides in the roof a gable carries; the wall row format has
## one top a row, and everything reading level walls keeps it).
func _face_rows(
	walls: PackedFloat32Array, g: Segment, p: Vector2, q: Vector2, ta: float, tb: float
) -> void:
	var strips := 1
	if ta != tb:
		strips = clampi(int(ceilf(absf(tb - ta) / RAKE_STRIP)), 1, 96)
	for k in strips:
		var u := float(k) / strips
		var v := float(k + 1) / strips
		var a := p.lerp(q, u)
		var b := p.lerp(q, v)
		var top := maxf(lerpf(ta, tb, u), lerpf(ta, tb, v))
		walls.append_array(
			PackedFloat32Array([a.x, a.y, b.x, b.y, g.tile, g.light, g.z0, top, g.area])
		)


## A raked wall's strips rise at most this each.
const RAKE_STRIP := .05


func _add_cap(into: Dictionary, z: float, s: Slab, tile: int) -> void:
	var key := snappedf(z, .001)
	if not into.has(key):
		into[key] = []
	var row := [s.x0, s.y0, s.x1, s.y1, tile]
	row.append_array(Array(s.cuts))
	var at_key: Array = into[key]
	at_key.append(row)


func _slope_row(s: Slab, z0: float, side: float, tile: int) -> Array:
	var row := [z0, s.gx, s.gy, side, s.x0, s.y0, s.x1, s.y1, tile, s.light, s.area]
	row.append_array(Array(s.cuts))
	return row


# --------------------------------------------------------- bodies


## What never moves, for a body of radius r with its feet at `feet`, `tall`
## high: the grid's solid cells (not a door's), furniture at its height, the
## geometry. The nav graph's test.
func static_blocked(lv: LevelData, x: float, y: float, r: float, feet: float, tall: float) -> bool:
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


func _fixture_in(lv: LevelData, x: float, y: float, r: float, feet: float, tall: float) -> bool:
	var list: Array = (
		lv.near_fixtures.get(Vector2i(int(x), int(y)), NOTHING)
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
			and f[7] < feet + tall
			and f[4] > feet + .01
		):
			return true
	return false


## blocked() for a body at its own height (format 2): what static_blocked()
## asks, doors and panes and locked gates too, the grid's solid cells as
## blocked() has them. `pieces` false: the caller knows no slab or segment is
## within reach.
func blocked_body(
	lv: LevelData, x: float, y: float, r: float, feet: float, tall: float, pieces := true
) -> bool:
	# (width and height are the level's; its grid read once.)
	var solid := lv.solid
	for step in 4:
		var ix := int(x + (-r if step < 2 else r))
		var iy := int(y + (-r if step % 2 == 0 else r))
		if ix < 0 or iy < 0 or ix >= width or iy >= height:
			return true
		if solid[iy * width + ix] >= 0:
			return true
	if not lv.pane_tiles.is_empty() and feet < 1.83 and lv.pane_at(x, y, null, r) != null:
		return true
	for gate: LevelData.Gate in lv.locked_gates:
		if absf(y - gate.y) < r + .09 and absf(x - gate.x) < gate.width * .5 + r:
			return true
	# A cell neither index lists anything under (index_cells 0) has no
	# furniture near and no door: both lookups are left out (most steps).
	var index_cells := lv.index_cells
	var listed := index_cells.size() != width * height or index_cells[int(y) * width + int(x)] != 0
	if (listed or r > lv.index_radius) and _fixture_in(lv, x, y, r, feet, tall):
		return true
	if feet < 1.85 and listed:
		for door: LevelData.Door in lv.near_doors.get(Vector2i(int(x), int(y)), NOTHING):
			if door.blocks(x, y, r):
				return true
	return pieces and blocks(x, y, r, feet + STEP, feet + tall)


## `body` is an Enemy or a Player (game_world.gd move_actor).
func can_walk(
	lv: LevelData, body: Variant, x: float, y: float, radius: float, occupied: Variant
) -> bool:
	var obj: Object = body
	var en := obj as Enemy
	var pl := obj as Player
	var player: bool = not (obj is Enemy) and ("air" in obj)
	var air: float = pl.air if player else 0.0
	var bx: float = en.x if en != null else pl.x
	var by: float = en.y if en != null else pl.y
	# (lv.cell() written out: the same width. The level's tables read once.)
	var here: int = int(by) * width + int(bx)
	var c: int = int(y) * width + int(x)
	var ground := lv.ground
	# Nothing of the geometry within reach of either end (cells are marked out
	# to PAD): support, the floor and the ceiling are the grid's own and no
	# piece can block, so those calls are left out. The same answers.
	var clear: bool = (
		radius < PAD
		and bx >= 0.0
		and by >= 0.0
		and x >= 0.0
		and y >= 0.0
		and bx < width
		and by < height
		and x < width
		and y < height
		and cells[here] == 0
		and cells[c] == 0
	)
	# The floor it stands on now, worked out again: something that moved it
	# without walking (a bridge, a shove, a script) leaves floor_z behind, and
	# the grid's own steps are measured from the cell it is in, as ever.
	var was_z: float = en.floor_z if en != null else pl.floor_z
	var floor_z: float = ground[here] if clear else support(bx, by, radius, was_z, ground[here])
	if en != null:
		en.floor_z = floor_z
	else:
		if player and floor_z < was_z - STEP:
			# Off an edge on the last step: as high as ever, now over the
			# lower floor, so they fall the rest (and a running jump carries).
			air += was_z - floor_z
			pl.air = air
		pl.floor_z = floor_z
	var feet := floor_z + air
	var tall: float = BODY
	if obj is Enemy:
		tall = minf(BODY, maxf(.4, en.height))
	elif player and pl.crouched:
		tall = CROUCH
	if blocked_body(lv, x, y, radius, feet, tall, not clear):
		return false
	# Deep water: nobody walks into it from dry ground, but a deck over it is
	# dry ground (a boardwalk over the swamp); and nobody steps off one into it.
	if lv.deep_tile >= 0 and lv.deep_at(x, y) and not obj.get("swims"):
		var dry_here: bool = not lv.deep_at(bx, by) or floor_z > ground[here] + STEP
		var dry_there: bool = not clear and floor_at(x, y, feet, ground[c], true) > ground[c] + STEP
		if dry_here and not dry_there:
			return false
	if occupied != null:
		var check: Callable = occupied
		if check.call(x, y):
			return false
	if clear:
		var flat: float = ground[c]
		if player and flat - floor_z > STEP + air + .001:
			return false
		return _roof(lv, c, flat) - flat >= CROUCH
	var under := floor_at(x, y, feet, ground[c], true)
	if player and under - floor_z > STEP + air + .001:
		return false
	var over := minf(ceiling_at(x, y, under), _roof(lv, c, under))
	return over - under >= CROUCH


## After a move (format 2): the floor under the body now. A player who walked
## off an edge is in the air above the lower floor and falls; one who stepped
## up stands on the higher one.
func settle(lv: LevelData, body: Variant, radius := .2) -> void:
	var obj: Object = body
	var en := obj as Enemy
	var pl := obj as Player
	var bx: float = en.x if en != null else pl.x
	var by: float = en.y if en != null else pl.y
	var c: int = lv.cell(bx, by)
	var player: bool = not (obj is Enemy) and ("air" in obj)
	var was_z: float = en.floor_z if en != null else pl.floor_z
	var feet: float = was_z + (pl.air if player else 0.0)
	var under := support(bx, by, radius, feet, lv.ground[c])
	if player:
		pl.air = maxf(0.0, feet - under)
	if en != null:
		en.floor_z = under
	else:
		pl.floor_z = under


# ------------------------------------------------------------------- nav

## The walkable places as a graph for FlowField (nav_graph.gd).
const NavGraph := preload("res://src/nav_graph.gd")


## The nav graph, built when first asked (FlowField). The graph of a level as
## read from its file, nothing opened yet, is kept for the next time that
## level is played (a retry, a load, the next match: a few tenths of a second
## of the level's load); it is only read once built, never changed.
func nav(lv: LevelData) -> NavGraph:
	if _nav != null:
		return _nav
	var key := lv.source_key if lv.walls_version == 0 and lv.solid_version == 0 else ""
	if key != "" and _navs.has(key):
		_nav = _navs[key]
		return _nav
	# A level as read from its file: the graph baked at pack time, while its
	# key holds (level_bakes.gd); else built here.
	_nav = LevelBakes.nav(lv) if key != "" else null
	if _nav == null:
		_nav = LevelNav.build_nav(self, lv)
	if key != "":
		if _navs.size() >= NAVS_KEPT:
			_navs.erase(_navs.keys()[0])
		_navs[key] = _nav
	return _nav


static func _roof(lv: LevelData, c: int, feet: float) -> float:
	# A roof of 0 is the open sky (a sunken floor's too: the pond).
	var r: float = lv.roof[c]
	return r if r != 0.0 and r > feet + .01 else INF
