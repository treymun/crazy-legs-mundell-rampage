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

## The newest geometry block this build reads. Version 2 (pass 16) adds
## terrain, raked walls drawn true and slopes' sides drawn as rakes, steeper
## slopes that are not walked on; a block is written as 2 only when it uses
## one of them (version_for), so every older block reads as it did.
const VERSION := 2
## The steepest a slab that is not walked on may be in a version 2 block (a
## roof's or a bank's face too steep to stand on).
const STEEPEST_FACE := 4.0
## A rake's row (rakes): ax, ay, bx, by, tile, light, the bottom and top at a,
## the bottom and top at b, area.
const RAKE_STRIDE := 11
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
## The sight index's reach past a piece (a sight line's step tests .023 round
## it, LevelSight).
const SIGHT_PAD := .03
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

## The block's version (1 or 2).
var version := 1
var slabs: Array[Slab] = []
var segments: Array[Segment] = []
var ceilings: Array[Ceiling] = []
var ladders: Array[Ladder] = []
## The ground's patches of corner heights (version 2), or null.
var terrain: LevelTerrain = null
## Every slab edge render_parts() made: Vector4(ax, ay, bx, by) -> its tile (the
## 3D view lays a stretched material along a stair's side by the metre).
var slab_edges := {}
## The faces whose top (or bottom) is not level, RAKE_STRIDE numbers each:
## raked walls' faces, and in a version 2 block sloped slabs' sides (in a
## version 1 block those stay strips in the wall rows, as ever). Drawn as true
## quads (LevelMesh); render_parts() makes them.
var rakes := PackedFloat32Array()
var width := 0
var height := 0
## cell -> Array of the slabs and segments within PAD of it.
var _index := {}
## cell -> Array of the slabs and ceilings over its footprint (for headroom).
var _over := {}
## cell -> Array of the slabs and segments within SIGHT_PAD of it: all a sight
## line's step in it can meet (LevelSight's tests reach .023), so its tests
## and its bands ask these and never the rest of the cell's PAD list.
var _sight := {}
## 1 for a cell the sight index lists anything under.
var sight_cells := PackedByteArray()
## cell -> its sight index's pieces as boxes for sight_first(), SIGHT_BOX
## numbers each: x0, y0, x1, y1 (a segment's grown by its half), the lowest
## and highest they fill, 1 when they stop a look (a slab, a segment that
## stops sight), 0 a rail's.
var _sight_boxes := {}
const SIGHT_BOX := 7
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
	g.version = version
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
		var steepest := STEEPEST if slab.walk or version < 2 else STEEPEST_FACE
		if absf(slab.gx) > steepest or absf(slab.gy) > steepest:
			errors.append("%s: slope steeper than %s" % [slab.id, steepest])
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
	if data.has("terrain"):
		if version < 2:
			errors.append("geometry: terrain needs version 2")
		else:
			g.terrain = LevelTerrain.from_json(data["terrain"], w, h, tile_index, errors)
	g._build_index()
	return g


## The version a geometry block (as a plan or a source writes it) needs: 2
## when it uses something version 1 does not have (terrain, a raked wall, a
## face steeper than STEEPEST not walked on), else 1, so an older block is
## written as it always was.
static func version_for(block: Dictionary) -> int:
	var terrain: Array = block.get("terrain", [])
	if not terrain.is_empty():
		return 2
	for seg: Dictionary in block.get("segments", []):
		var z1: float = seg.get("z1", 2.0)
		var z1b: float = seg.get("z1b", z1)
		if z1b != z1:
			return 2
	for slab: Dictionary in block.get("slabs", []):
		var gx: float = slab.get("gx", 0.0)
		var gy: float = slab.get("gy", 0.0)
		var walk: bool = slab.get("walk", true)
		if not walk and maxf(absf(gx), absf(gy)) > STEEPEST:
			return 2
	return 1


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
	_sight = {}
	cells = PackedByteArray()
	cells.resize(width * height)
	cells.fill(0)
	var sp := SIGHT_PAD
	for slab in slabs:
		_put(_index, slab.x0 - PAD, slab.y0 - PAD, slab.x1 + PAD, slab.y1 + PAD, slab, true)
		_put(_sight, slab.x0 - sp, slab.y0 - sp, slab.x1 + sp, slab.y1 + sp, slab, false)
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
		var reach := sp + seg.half
		_put(
			_sight,
			minf(seg.ax, seg.bx) - reach,
			minf(seg.ay, seg.by) - reach,
			maxf(seg.ax, seg.bx) + reach,
			maxf(seg.ay, seg.by) + reach,
			seg,
			false
		)
	sight_cells = PackedByteArray()
	sight_cells.resize(width * height)
	sight_cells.fill(0)
	_sight_boxes = {}
	# Each piece's box once, then each cell's list of them.
	var box_of := {}
	for sl in slabs:
		box_of[sl] = PackedFloat64Array(
			[
				sl.x0,
				sl.y0,
				sl.x1,
				sl.y1,
				-1e12 if sl.thick < 0.0 else sl.top_min() - sl.thick,
				sl.top_max(),
				1.0
			]
		)
	for g in segments:
		box_of[g] = PackedFloat64Array(
			[
				minf(g.ax, g.bx) - g.half,
				minf(g.ay, g.by) - g.half,
				maxf(g.ax, g.bx) + g.half,
				maxf(g.ay, g.by) + g.half,
				g.z0,
				g.top_max(),
				1.0 if g.sight else 0.0
			]
		)
	for c: int in _sight:
		sight_cells[c] = 1
		var boxes := PackedFloat64Array()
		for item: Variant in _sight[c]:
			var box: PackedFloat64Array = box_of[item]
			boxes.append_array(box)
		_sight_boxes[c] = boxes
	for c in ceilings:
		_put(_over, c.x0, c.y0, c.x1, c.y1, c, true)
	if terrain != null:
		_index_terrain()
	_build_sight_bands()


## The terrain's cells and the ring round them are asked about everything
## (a cliff's face reaches a body in the next cell); each terrain cell is in
## the sight index as a box from far down to its highest corner, and for a
## flat look (whose floor is the surface itself) one with a cliff in or by
## it as a box filling every height.
func _index_terrain() -> void:
	var t := terrain
	for cy in height:
		for cx in width:
			var c := cy * width + cx
			var near := false
			var cliffs := false
			for yy in range(maxi(0, cy - 1), mini(height, cy + 2)):
				for xx in range(maxi(0, cx - 1), mini(width, cx + 2)):
					near = near or t.patch_at[yy * width + xx] != 0
					cliffs = cliffs or t.steep[yy * width + xx] != 0
			if not near:
				continue
			cells[c] = 1
			if t.patch_at[c] == 0 and not cliffs:
				continue
			sight_cells[c] = 1
			var boxes: PackedFloat64Array = _sight_boxes.get(c, PackedFloat64Array())
			if t.patch_at[c] != 0:
				boxes.append_array(
					PackedFloat64Array([cx, cy, cx + 1, cy + 1, -1e12, t.high[c], 2.0])
				)
			if cliffs:
				boxes.append_array(
					PackedFloat64Array([cx - 1, cy - 1, cx + 2, cy + 2, -1e12, 1e12, 3.0])
				)
			_sight_boxes[c] = boxes


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
		# The heights of its sight index's pieces (their boxes: a slab, a
		# segment that stops sight, the terrain under it).
		var spans: Array[Vector2] = []
		var found: Variant = _sight_boxes.get(c)
		if found != null:
			var boxes: PackedFloat64Array = found
			for o in range(0, boxes.size(), SIGHT_BOX):
				var kind := boxes[o + 6]
				if kind == 1.0 or kind == 2.0:
					spans.append(Vector2(boxes[o + 4], boxes[o + 5]))
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
## nothing of the geometry (the pieces within SIGHT_PAD of the cell): z1 in
## no band and no band between z0 and z1, so neither solid_point() nor
## crosses() could stop it there. False: ask them
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


## A sight line's step at (x, y) in cell c (its own cell, marked): whether a
## body's flat test there (blocks() at .023, the floor `ground`) meets a
## piece; over the sight index, so the same answers as blocks().
func sight_blocks(c: int, x: float, y: float, ground: float) -> bool:
	var items: Array = _sight.get(c, NOTHING)
	if terrain == null:
		return blocks_in(items, x, y, .023, ground + STEP, ground + BODY)
	# On terrain the floor is the surface there.
	var g := ground_at(x, y, ground)
	return blocks_in(items, x, y, .023, g + STEP, g + BODY) or terrain.blocks(x, y, .023, g + STEP)


## solid_point(x, y, z, .023, false) for a sight line's step in cell c.
func sight_point(c: int, x: float, y: float, z: float) -> bool:
	if terrain != null and terrain.patch_at[c] != 0 and z <= terrain.height_at(x, y):
		return true
	for item: Variant in _sight.get(c, NOTHING):
		if item is Slab:
			var s: Slab = item
			if s.near(x, y, .023) and z <= s.top_at(x, y) and z >= s.bottom_at(x, y):
				return true
		else:
			var g: Segment = item
			if g.sight and z >= g.z0 and z <= g.top_near(x, y, .023):
				var reach := .023 + g.half
				if g.dist2(x, y) < reach * reach:
					return true
	return false


## Where on the stretch of a sight line from (x, y, z) along (dx, dy, dz),
## from t0 to t1, it might first meet a piece of cell c's sight index (INF:
## nowhere): each piece's box grown by a step's reach, clipped to the stretch
## (Liang-Barsky), and its heights over that against the piece's. `flat`: a
## look without heights, tested at the floor `ground` as sight_blocks() is.
## Before the answer no step meets one (sight_point, sight_crosses,
## sight_blocks); after it one only might.
func sight_first(
	c: int,
	x: float,
	y: float,
	z: float,
	dx: float,
	dy: float,
	dz: float,
	t0: float,
	t1: float,
	flat: bool,
	ground: float
) -> float:
	var first := INF
	# A flat look's floor is the cell's ground, or on terrain anywhere from
	# its lowest corner to its highest.
	var g_lo := ground
	var g_hi := ground
	if terrain != null and terrain.patch_at[c] != 0:
		g_lo = terrain.low[c]
		g_hi = terrain.high[c]
	var step_lo := g_lo + STEP
	var body_hi := g_hi + BODY
	var reach := .023 + 1e-4
	var boxes: PackedFloat64Array = _sight_boxes.get(c, PackedFloat64Array())
	for o in range(0, boxes.size(), SIGHT_BOX):
		var low := boxes[o + 4]
		var high := boxes[o + 5]
		var kind := boxes[o + 6]
		if flat:
			# (A flat look never meets the surface it is on (kind 2), only a
			# cliff by it (3).)
			if kind == 2.0 or (kind != 3.0 and (high <= step_lo or low >= body_hi)):
				continue
		elif kind == 0.0 or kind == 3.0:
			continue
		var lo := t0
		var hi := minf(t1, first)
		var gx0 := x - (boxes[o] - reach)
		var gx1 := (boxes[o + 2] + reach) - x
		var gy0 := y - (boxes[o + 1] - reach)
		var gy1 := (boxes[o + 3] + reach) - y
		if dx == 0.0:
			if gx0 < 0.0 or gx1 < 0.0:
				continue
		elif dx > 0.0:
			lo = maxf(lo, -gx0 / dx)
			hi = minf(hi, gx1 / dx)
		else:
			lo = maxf(lo, gx1 / dx)
			hi = minf(hi, -gx0 / dx)
		if dy == 0.0:
			if gy0 < 0.0 or gy1 < 0.0:
				continue
		elif dy > 0.0:
			lo = maxf(lo, -gy0 / dy)
			hi = minf(hi, gy1 / dy)
		else:
			lo = maxf(lo, gy1 / dy)
			hi = minf(hi, -gy0 / dy)
		if lo > hi:
			continue
		if not flat:
			var za := z + dz * lo
			var zb := z + dz * hi
			if maxf(za, zb) < low - 1e-4 or minf(za, zb) > high + 1e-4:
				continue
			if dz != 0.0:
				# The first of the clipped part within the piece's heights.
				if za < low - 1e-4:
					lo = maxf(lo, (low - 1e-4 - z) / dz)
				elif za > high + 1e-4:
					lo = maxf(lo, (high + 1e-4 - z) / dz)
		first = minf(first, lo)
	return first


## crosses() for a sight line's step ending at (x1, y1) in cell c.
func sight_crosses(
	c: int, x0: float, y0: float, z0: float, x1: float, y1: float, z1: float
) -> bool:
	for item: Variant in _sight.get(c, NOTHING):
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


func _put(
	into: Dictionary, x0: float, y0: float, x1: float, y1: float, item: RefCounted, mark: bool
) -> void:
	# (One lookup a cell, the list made only where there is none: the same
	# lists in the same order.)
	for cy in range(maxi(0, floori(y0)), mini(height - 1, floori(y1)) + 1):
		for cx in range(maxi(0, floori(x0)), mini(width - 1, floori(x1)) + 1):
			var key := cy * width + cx
			var found: Variant = into.get(key)
			if found == null:
				into[key] = [item]
			else:
				var list: Array = found
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
## the feet. -1e9 when there is none. On terrain the surface there is the
## ground (as a cell's is, whatever the feet); with `open` false a floor
## like a slab's top.
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
	if terrain != null:
		var t := terrain.height_at(x, y)
		if not is_nan(t) and t > best and (open or t <= z + STEP + .001):
			best = t
	return best


## The ground at (x, y): the terrain's surface there, else `ground` (the
## cell's).
func ground_at(x: float, y: float, ground: float) -> float:
	if terrain == null:
		return ground
	var t := terrain.height_at(x, y)
	return ground if is_nan(t) else t


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
	if x < 0.0 or y < 0.0 or x >= width or y >= height or cells[int(y) * width + int(x)] == 0:
		return INF
	var items: Array = _over.get(int(y) * width + int(x), NOTHING)
	return ceiling_in(items, x, y, z)


## ceiling_at() over the overhead pieces `items` (a cell's, or those a nav
## walk passes under: LevelNav._near_walk).
static func ceiling_in(items: Array, x: float, y: float, z: float) -> float:
	var best := INF
	for item: Variant in items:
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
	if terrain != null and terrain.blocks(x, y, r, lo):
		return true
	return blocks_in(near_items(x, y), x, y, r, lo, hi)


## blocks() over the pieces `items` (a cell's list, or the part of it a nav
## walk can meet: LevelNav._near_walk).
static func blocks_in(items: Array, x: float, y: float, r: float, lo: float, hi: float) -> bool:
	for item: Variant in items:
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
	if terrain != null:
		var t := terrain.height_at(x, y)
		if not is_nan(t) and z <= t:
			return true
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


## What the renderers draw for it (GeoParts.render, level_geometry_parts.gd):
##   "walls": wall rows (LevelData.WALL_STRIDE each), slab edges and segments
##   "caps": height -> [x0, y0, x1, y1, tile, cuts...] flat floors seen from above
##   "roof_caps": height -> [...] flat surfaces seen from below
##   "slopes": [z0, gx, gy, side, x0, y0, x1, y1, tile, light, area, cuts...]
##   "rakes": the rakes (also kept in `rakes`)
## `ground` gives a cell's floor (an edge or a wedge stops there).
func render_parts(ground: Callable) -> Dictionary:
	return GeoParts.render(self, ground)


## A station's lights coming on in `area` (game_world.set_station_lights does
## the wall rows): its rakes `by` brighter.
func brighten(area: int, by: float) -> void:
	for o in range(0, rakes.size(), RAKE_STRIDE):
		if int(rakes[o + 10]) == area:
			rakes[o + 5] += by


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


## static_blocked() with the pieces `items` in place of the cell's list (the
## part of it a nav walk can meet: LevelNav._near_walk).
func static_blocked_in(
	lv: LevelData, x: float, y: float, r: float, feet: float, tall: float, items: Array
) -> bool:
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
	if terrain != null and terrain.blocks(x, y, r, feet + STEP):
		return true
	return blocks_in(items, x, y, r, feet + STEP, feet + tall)


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
