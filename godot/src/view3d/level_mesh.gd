## Builds a level's 3D geometry from its grid data (LevelData): every wall row
## (walls, doors, panes, gates), every cell's floor and roof, the format-2
## caps and slopes. Map (x, y, z) is Godot (x, z, y): x east, y up, z south.
##
## Each vertex carries what the old renderer used for that surface (see
## world.gdshader): UV in tile pixels, the tile (and the plain tile under a
## window band), the light, the area's tint, the tiling mode and the kind.
## The level is cut into CHUNK x CHUNK cell blocks so the engine culls each.
class_name LevelMesh
extends RefCounted

const CHUNK := 16
const STRIDE := LevelData.WALL_STRIDE

## Surface kinds (world.gdshader KIND_*).
const KIND_WALL := 0
const KIND_GLOW := 1
const KIND_FLICKER := 2
const KIND_SHADOW := 3
const KIND_MESH := 4
const KIND_GLAZING := 5
const KIND_MIRROR := 6
## A plank wall or fence that can be shot about (features/wall_looks.gd): its
## knocked-out planks are cut out of it in the shader (plank_damage). The
## second number is its whole tile, or for the stockyard's (its posts and
## rails stay) less than 0: -1 - the whole tile.
const KIND_PLANKS := 7
const PLANK_TILES := {
	"wood": false,
	"barn": false,
	"bayou_shack": false,
	"detail_wall_feed_pen_boards": false,
	"stockyard": true,
}
const KIND_FLOOR := 8
const KIND_ROOF := 9
## Slab edges (LevelGeometry.slab_edges) keep these materials stretched over
## each piece (a grandstand's riser is drawn for one step); every other
## stretched material on a stair's, deck's or ramp's side is laid along by the
## metre instead, so a flight's treads do not each squeeze the whole picture
## into their own height.
const EDGE_STRETCHED: Array[String] = ["grandstand_riser"]
## Where a slab edge's material starts along it: far enough out that the
## texel stays positive both ways round (levels are under this many cells).
const EDGE_ORIGIN := 1024.0


## One growing set of arrays (a chunk's opaque or glazing surface).
class Part:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var custom0 := PackedFloat32Array()
	var custom1 := PackedFloat32Array()
	var index := PackedInt32Array()

	func empty() -> bool:
		return index.is_empty()

	func vertex(at: Vector3, n: Vector3, uv: Vector2, c0: Color, c1: Color) -> void:
		verts.append(at)
		normals.append(n)
		uvs.append(uv)
		custom0.append_array(PackedFloat32Array([c0.r, c0.g, c0.b, c0.a]))
		custom1.append_array(PackedFloat32Array([c1.r, c1.g, c1.b, c1.a]))

	## Two triangles over the last four vertices (a, b, c, d in order).
	func quad() -> void:
		var n := verts.size() - 4
		index.append_array(PackedInt32Array([n, n + 1, n + 2, n, n + 2, n + 3]))

	func mesh(into: ArrayMesh) -> void:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_CUSTOM0] = custom0
		arrays[Mesh.ARRAY_CUSTOM1] = custom1
		arrays[Mesh.ARRAY_INDEX] = index
		var format := (
			(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
			| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
		)
		into.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, format)


var level: LevelData
## Per tile: 0 stretched, 1 repeating, 2 a window band over its plain tile.
var tile_mode := PackedByteArray()
var tile_base := PackedInt32Array()
var _tile_liquor := -1
var _tile_eat := -1
var _tile_window := -1
var _tile_mirror := -1
var _tile_glazing := -1
var _tile_hub_wall := -1
var _tile_hub_screen := -1
var _hub := false
var _edge_stretched := {}
## Plank tiles (and their _hit) -> the second number their faces carry.
var _planks := {}
## chunk key -> [opaque Part, glazing Part]
var _chunks := {}
## build_static(only): the chunks being built again (empty: all of them);
## the rest goes in _waste.
var _only := {}
var _waste := Part.new()


func _init(p_level: LevelData) -> void:
	level = p_level
	var names := level.tile_names
	tile_mode.resize(names.size())
	tile_base.resize(names.size())
	for i in names.size():
		var tile_name := String(names[i])
		tile_base[i] = i
		tile_mode[i] = 0
		if LevelTiles.TILED.has(tile_name):
			tile_mode[i] = 1
		elif tile_name.ends_with("_hit") and LevelTiles.TILED.has(tile_name.trim_suffix("_hit")):
			# A plank wall shot about (wall_breaks.gd) repeats as its wall does.
			tile_mode[i] = 1
		elif (
			tile_name.ends_with("_win")
			or tile_name.ends_with("_lit")
			or tile_name.ends_with("_brk")
			or tile_name.ends_with("_bst")
		):
			var plain := tile_name.substr(0, tile_name.length() - 4)
			if LevelTiles.TILED.has(plain) and level.tile_id(plain) >= 0:
				tile_mode[i] = 2
				tile_base[i] = level.tile_id(plain)
	_tile_liquor = level.tile_id("liquor")
	_tile_eat = level.tile_id("eat")
	_tile_window = level.tile_id("window")
	_tile_mirror = level.tile_id("mirror")
	_tile_glazing = level.tile_id("glazing")
	_tile_hub_wall = level.tile_id("hub_service_wall")
	_tile_hub_screen = level.tile_id("hub_screen")
	_hub = level.id == "hub"
	for tile_name: String in PLANK_TILES:
		var whole := level.tile_id(tile_name)
		if whole < 0:
			continue
		var posts: bool = PLANK_TILES[tile_name]
		_planks[whole] = -1 - whole if posts else whole
		var hit := level.tile_id(tile_name + "_hit")
		if hit >= 0:
			_planks[hit] = _planks[whole]
	for tile_name: String in EDGE_STRETCHED:
		if level.tile_id(tile_name) >= 0:
			_edge_stretched[level.tile_id(tile_name)] = true


## The level's fixed geometry: base walls (LevelData.active_base), floors,
## roofs, caps and slopes. Returns chunk key (Vector2i) -> ArrayMesh, whose
## surface 0 is opaque and surface 1 (when present) the window glazing.
func build_static(base_walls: PackedFloat32Array, only := {}) -> Dictionary:
	_chunks = {}
	_only = only
	add_walls(base_walls)
	_add_floors()
	for h: float in level.caps:
		for cap: Array in level.caps[h]:
			_add_cap(cap, h, false)
	for h: float in level.roof_caps:
		for cap: Array in level.roof_caps[h]:
			_add_cap(cap, h, true)
	for row: Array in level.slopes:
		_add_slope(row)
	if level.geo != null and not level.geo.rakes.is_empty():
		add_rakes(level.geo.rakes)
	if level.geo != null and level.geo.terrain != null:
		_add_terrain(level.geo.terrain)
	return _finish()


## Only the given wall rows (doors, panes, gates: what moves), as one mesh
## (null when there is nothing).
func build_walls(rows: PackedFloat32Array) -> ArrayMesh:
	_chunks = {}
	_only = {}
	add_walls(rows)
	var opaque := Part.new()
	var glazing := Part.new()
	for key: Vector2i in _chunks:
		var pair: Array = _chunks[key]
		var solid: Part = pair[0]
		var glass: Part = pair[1]
		_append(opaque, solid)
		_append(glazing, glass)
	if opaque.empty() and glazing.empty():
		return null
	_chunks = {Vector2i.ZERO: [opaque, glazing]}
	return _finish()[Vector2i.ZERO]


static func _append(into: Part, from: Part) -> void:
	var base := into.verts.size()
	into.verts.append_array(from.verts)
	into.normals.append_array(from.normals)
	into.uvs.append_array(from.uvs)
	into.custom0.append_array(from.custom0)
	into.custom1.append_array(from.custom1)
	for i in from.index:
		into.index.append(i + base)


func _finish() -> Dictionary:
	var out := {}
	for key: Vector2i in _chunks:
		var parts: Array = _chunks[key]
		var opaque: Part = parts[0]
		var glazing: Part = parts[1]
		if opaque.empty() and glazing.empty():
			continue
		var mesh := ArrayMesh.new()
		if opaque.empty():
			# Surface 0 is always the opaque one; a chunk of glass alone gets a
			# degenerate triangle there.
			opaque.vertex(Vector3.ZERO, Vector3.UP, Vector2.ZERO, Color(), Color())
			opaque.vertex(Vector3.ZERO, Vector3.UP, Vector2.ZERO, Color(), Color())
			opaque.vertex(Vector3.ZERO, Vector3.UP, Vector2.ZERO, Color(), Color())
			opaque.index.append_array(PackedInt32Array([0, 1, 2]))
		opaque.mesh(mesh)
		if not glazing.empty():
			glazing.mesh(mesh)
		out[key] = mesh
	return out


func _part(x: float, y: float, glass: bool) -> Part:
	var key := Vector2i(floori(x / CHUNK), floori(y / CHUNK))
	if not _only.is_empty() and not _only.has(key):
		# A chunk not being built again: what goes in it is thrown away.
		_waste.verts.clear()
		_waste.normals.clear()
		_waste.uvs.clear()
		_waste.custom0.clear()
		_waste.custom1.clear()
		_waste.index.clear()
		return _waste
	var parts: Array = _chunks.get(key, [])
	if parts.is_empty():
		parts = [Part.new(), Part.new()]
		_chunks[key] = parts
	return parts[1] if glass else parts[0]


## Whether what goes at (x, y) is in a chunk not being built (build_static's
## `only`), and whether all of a box is.
func _skip(x: float, y: float) -> bool:
	return not _only.is_empty() and not _only.has(Vector2i(floori(x / CHUNK), floori(y / CHUNK)))


func _skip_box(x0: float, y0: float, x1: float, y1: float) -> bool:
	if _only.is_empty():
		return false
	for key: Vector2i in _only:
		var lo := Vector2(key.x * CHUNK, key.y * CHUNK)
		if x1 >= lo.x and x0 < lo.x + CHUNK and y1 >= lo.y and y0 < lo.y + CHUNK:
			return false
	return true


func _tint(area: int) -> Color:
	var n := level.tints.size() / 3
	var i := clampi(area, 0, maxi(0, n - 1)) * 3
	if level.tints.size() < 3:
		return Color(1, 1, 1)
	return Color(level.tints[i], level.tints[i + 1], level.tints[i + 2])


## Every row of `rows` (stride 9: ax, ay, bx, by, tile, light, bottom, top,
## area) as an upright quad, seen from both sides.
func add_walls(rows: PackedFloat32Array) -> void:
	var edges: Dictionary = level.geo.slab_edges if level.geo != null else {}
	for o in range(0, rows.size() - STRIDE + 1, STRIDE):
		var ax := rows[o]
		var ay := rows[o + 1]
		var bx := rows[o + 2]
		var by := rows[o + 3]
		var tile := int(rows[o + 4])
		var light := rows[o + 5]
		var bottom := rows[o + 6]
		var top := rows[o + 7]
		var area := int(rows[o + 8])
		if top <= bottom or _skip((ax + bx) * .5, (ay + by) * .5):
			continue
		var length := Vector2(bx - ax, by - ay).length()
		if length < .0005:
			continue
		var kind := KIND_WALL
		if tile == _tile_liquor:
			kind = KIND_FLICKER
		elif tile == _tile_eat or tile == _tile_window:
			kind = KIND_GLOW
		elif tile == _tile_glazing:
			kind = KIND_GLAZING
		elif tile == _tile_mirror:
			kind = KIND_MIRROR
		elif _hub and tile == _tile_hub_wall:
			kind = KIND_SHADOW
		elif _hub and tile == _tile_hub_screen:
			kind = KIND_MESH
		elif _planks.has(tile):
			kind = KIND_PLANKS
		var plain := kind == KIND_WALL or kind == KIND_PLANKS
		var mode := int(tile_mode[tile]) if plain and tile >= 0 and tile < tile_mode.size() else 0
		var along := length * 128.0 if mode != 0 else 128.0
		var base := tile_base[tile] if mode == 2 else tile
		if kind == KIND_PLANKS:
			base = _planks[tile]
		var u_a := 0.0
		if (
			plain
			and mode == 0
			and not edges.is_empty()
			and not _edge_stretched.has(tile)
			and edges.get(Vector4(ax, ay, bx, by), -1) == tile
		):
			# A slab edge in a stretched material: repeat it by the metre from a
			# point fixed in the world along the edge's line, so the next tread's
			# side carries on the same boards.
			mode = 1
			var d := Vector2(bx - ax, by - ay) / length
			u_a = (Vector2(ax, ay).dot(d) + EDGE_ORIGIN) * 128.0
			along = EDGE_ORIGIN * 256.0
		var u_b := u_a + length * 128.0 if mode != 0 else along
		var v_top := (1.96 - top) * 100.0 if mode != 0 else 0.0
		var v_bottom := (1.96 - bottom) * 100.0 if mode != 0 else 128.0
		# The face's normal in map terms is (dy, -dx); world.gdshader flips u
		# back for a viewer on that side, as the old renderer did.
		var n := Vector3(by - ay, 0.0, -(bx - ax)) / length
		var c0 := _tint(area)
		c0.a = light
		var c1 := Color(float(tile), float(base), along, float(mode + kind * 4))
		var part := _part((ax + bx) * .5, (ay + by) * .5, kind == KIND_GLAZING)
		part.vertex(Vector3(ax, bottom, ay), n, Vector2(u_a, v_bottom), c0, c1)
		part.vertex(Vector3(ax, top, ay), n, Vector2(u_a, v_top), c0, c1)
		part.vertex(Vector3(bx, top, by), n, Vector2(u_b, v_top), c0, c1)
		part.vertex(Vector3(bx, bottom, by), n, Vector2(u_b, v_bottom), c0, c1)
		part.quad()


## Every rake (LevelGeometry.rakes: a face whose top or bottom slopes, a
## gable's, a raked wall's, a slope's side) as a quad seen from both sides,
## its texture laid as a wall row's is: by the metre for a repeating
## material, over its whole height and length for a stretched one. A plank
## material is drawn whole (the planks shot out of a fence are a grid wall's).
func add_rakes(rows: PackedFloat32Array) -> void:
	var stride := LevelGeometry.RAKE_STRIDE
	var edges: Dictionary = level.geo.slab_edges
	for o in range(0, rows.size() - stride + 1, stride):
		var ax := rows[o]
		var ay := rows[o + 1]
		var bx := rows[o + 2]
		var by := rows[o + 3]
		var tile := int(rows[o + 4])
		var light := rows[o + 5]
		var a_bottom := rows[o + 6]
		var a_top := rows[o + 7]
		var b_bottom := rows[o + 8]
		var b_top := rows[o + 9]
		var area := int(rows[o + 10])
		if (a_top <= a_bottom and b_top <= b_bottom) or _skip((ax + bx) * .5, (ay + by) * .5):
			continue
		var length := Vector2(bx - ax, by - ay).length()
		if length < .0005:
			continue
		var kind := KIND_WALL
		if tile == _tile_liquor:
			kind = KIND_FLICKER
		elif tile == _tile_eat or tile == _tile_window:
			kind = KIND_GLOW
		elif tile == _tile_glazing:
			kind = KIND_GLAZING
		var plain := kind == KIND_WALL
		var mode := int(tile_mode[tile]) if plain and tile >= 0 and tile < tile_mode.size() else 0
		var along := length * 128.0 if mode != 0 else 128.0
		var base := tile_base[tile] if mode == 2 else tile
		var u_a := 0.0
		if (
			plain
			and mode == 0
			and not _edge_stretched.has(tile)
			and edges.get(Vector4(ax, ay, bx, by), -1) == tile
		):
			# A slope's side in a stretched material: by the metre, as a slab
			# edge's (add_walls).
			mode = 1
			var d := Vector2(bx - ax, by - ay) / length
			u_a = (Vector2(ax, ay).dot(d) + EDGE_ORIGIN) * 128.0
			along = EDGE_ORIGIN * 256.0
		var u_b := u_a + length * 128.0 if mode != 0 else along
		# v: the wall rows' (1.96 - z) * 100 by the metre; stretched, the whole
		# picture over the face's full height.
		var high := maxf(a_top, b_top)
		var low := minf(a_bottom, b_bottom)
		var span := maxf(high - low, .001)
		var va_top := (1.96 - a_top) * 100.0 if mode != 0 else (high - a_top) / span * 128.0
		var va_bottom := (
			(1.96 - a_bottom) * 100.0 if mode != 0 else (high - a_bottom) / span * 128.0
		)
		var vb_top := (1.96 - b_top) * 100.0 if mode != 0 else (high - b_top) / span * 128.0
		var vb_bottom := (
			(1.96 - b_bottom) * 100.0 if mode != 0 else (high - b_bottom) / span * 128.0
		)
		var n := Vector3(by - ay, 0.0, -(bx - ax)) / length
		var c0 := _tint(area)
		c0.a = light
		var c1 := Color(float(tile), float(base), along, float(mode + kind * 4))
		var part := _part((ax + bx) * .5, (ay + by) * .5, kind == KIND_GLAZING)
		part.vertex(Vector3(ax, a_bottom, ay), n, Vector2(u_a, va_bottom), c0, c1)
		part.vertex(Vector3(ax, a_top, ay), n, Vector2(u_a, va_top), c0, c1)
		part.vertex(Vector3(bx, b_top, by), n, Vector2(u_b, vb_top), c0, c1)
		part.vertex(Vector3(bx, b_bottom, by), n, Vector2(u_b, vb_bottom), c0, c1)
		part.quad()


## The sun the terrain's slopes are shaded by (map axes: from the north-west,
## high), and how much: a flat cell is drawn as bright as a flat floor.
const SUN := Vector3(-.4, -.48, .78)
const SLOPE_SHADE := .5


## The terrain (LevelTerrain): each cell two triangles split as the surface
## is, its corners lit from the slope there (each corner's normal from the
## heights round it, so the light runs smooth over a hill, the 1997 way); a
## cliff's triangle upright, its picture laid up its face by the metre.
func _add_terrain(t: LevelTerrain) -> void:
	var w := level.width
	var sun := SUN.normalized()
	for c in w * level.height:
		if t.patch_at[c] == 0:
			continue
		var cx := c % w
		var cy := c / w
		if _skip(cx + .5, cy + .5):
			continue
		var p := t.patch_of(c)
		var tile := t.tile_of(c)
		if tile < 0:
			tile = level.floor_tile[c]
		if tile < 0:
			continue
		var light := p.light if p.light >= 0.0 else level.light[c]
		var c0 := _tint(level.area[c])
		var k := c * 4
		var at: Array[Vector3] = [
			Vector3(cx, cy, t.corners[k]),
			Vector3(cx + 1, cy, t.corners[k + 1]),
			Vector3(cx, cy + 1, t.corners[k + 2]),
			Vector3(cx + 1, cy + 1, t.corners[k + 3]),
		]
		var normals: Array[Vector3] = []
		for q in at:
			normals.append(_terrain_normal(p, int(q.x), int(q.y)))
		var part := _part(cx + .5, cy + .5, false)
		# North-east (nw, ne, se), then south-west (nw, se, sw).
		_terrain_sides(t, p, c, at, light, c0)
		for tri in 2:
			var ids := PackedInt32Array([0, 1, 3]) if tri == 0 else PackedInt32Array([0, 3, 2])
			if t.steep[c] & (1 if tri == 0 else 2) != 0:
				_cliff_triangle(part, at[ids[0]], at[ids[1]], at[ids[2]], p.cliff, light, c0)
				continue
			var c1 := Color(float(tile), float(tile), 128.0, float(KIND_FLOOR * 4))
			for i in ids:
				var q := at[i]
				var n := normals[i]
				var lit := c0
				lit.a = light * (1.0 + SLOPE_SHADE * (n.dot(sun) - sun.z))
				part.vertex(
					Vector3(q.x, q.z, q.y),
					Vector3(n.x, n.z, n.y),
					Vector2(q.x * 128.0, q.y * 128.0),
					lit,
					c1
				)
			var first := part.verts.size() - 3
			part.index.append_array(PackedInt32Array([first, first + 1, first + 2]))


## Where terrain cell c's edge stands over the floor beside it (the patch's
## edge over lower ground, or a lower patch), that side drawn down to it as a
## cliff's face is. `at`: its corners (nw, ne, sw, se) as map points.
func _terrain_sides(
	t: LevelTerrain, p: LevelTerrain.Patch, c: int, at: Array[Vector3], light: float, c0: Color
) -> void:
	var w := level.width
	var cx := c % w
	var cy := c / w
	# North, east, south, west: the neighbour's step, the edge's two corners
	# (of nw 0, ne 1, sw 2, se 3), and the same corners as the neighbour's.
	var steps := PackedInt32Array([0, -1, 1, 0, 0, 1, -1, 0])
	var ends := PackedInt32Array([0, 1, 1, 3, 3, 2, 2, 0])
	var theirs := PackedInt32Array([2, 3, 0, 2, 1, 0, 3, 1])
	for side in 4:
		var nx := cx + steps[side * 2]
		var ny := cy + steps[side * 2 + 1]
		if nx < 0 or ny < 0 or nx >= w or ny >= level.height:
			continue
		var n := ny * w + nx
		if t.patch_at[n] == t.patch_at[c]:
			continue
		var a: Vector3 = at[ends[side * 2]]
		var b: Vector3 = at[ends[side * 2 + 1]]
		var low_a := level.ground[n]
		var low_b := low_a
		if t.patch_at[n] != 0:
			# Another patch: its own surface along the edge.
			low_a = t.corners[n * 4 + theirs[side * 2]]
			low_b = t.corners[n * 4 + theirs[side * 2 + 1]]
		if a.z <= low_a + .005 and b.z <= low_b + .005:
			continue
		var row := PackedFloat32Array(
			[a.x, a.y, b.x, b.y, p.cliff, light, minf(low_a, a.z), a.z, minf(low_b, b.z), b.z, 0]
		)
		var lit := c0
		lit.a = light
		_side_quad(row, lit)


## One terrain side (a rake's row) drawn upright in its tile by the metre.
func _side_quad(row: PackedFloat32Array, c0: Color) -> void:
	var ax := row[0]
	var ay := row[1]
	var bx := row[2]
	var by := row[3]
	var length := Vector2(bx - ax, by - ay).length()
	if length < .0005:
		return
	var d := Vector2(bx - ax, by - ay) / length
	var u_a := (Vector2(ax, ay).dot(d) + EDGE_ORIGIN) * 128.0
	var u_b := u_a + length * 128.0
	var along := EDGE_ORIGIN * 256.0
	var n := Vector3(by - ay, 0.0, -(bx - ax)) / length
	var c1 := Color(row[4], row[4], along, float(1 + KIND_WALL * 4))
	var part := _part((ax + bx) * .5, (ay + by) * .5, false)
	part.vertex(Vector3(ax, row[6], ay), n, Vector2(u_a, (1.96 - row[6]) * 100.0), c0, c1)
	part.vertex(Vector3(ax, row[7], ay), n, Vector2(u_a, (1.96 - row[7]) * 100.0), c0, c1)
	part.vertex(Vector3(bx, row[9], by), n, Vector2(u_b, (1.96 - row[9]) * 100.0), c0, c1)
	part.vertex(Vector3(bx, row[8], by), n, Vector2(u_b, (1.96 - row[8]) * 100.0), c0, c1)
	part.quad()


## A terrain corner's normal (map axes): the patch's heights either side.
static func _terrain_normal(p: LevelTerrain.Patch, x: int, y: int) -> Vector3:
	var x0 := maxi(p.x0, x - 1)
	var x1 := mini(p.x0 + p.w, x + 1)
	var y0 := maxi(p.y0, y - 1)
	var y1 := mini(p.y0 + p.h, y + 1)
	var gx := (p.corner(x1, y) - p.corner(x0, y)) / float(x1 - x0)
	var gy := (p.corner(x, y1) - p.corner(x, y0)) / float(y1 - y0)
	return Vector3(-gx, -gy, 1.0).normalized()


## A cliff's triangle (map points a, b, c): drawn as a wall is, its picture
## along the face's level line by the metre and up it by height.
func _cliff_triangle(
	part: Part, a: Vector3, b: Vector3, c: Vector3, tile: int, light: float, c0: Color
) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.z < 0.0:
		n = -n
	var across := Vector2(-n.y, n.x)
	if across.length() < 1e-6:
		across = Vector2(1, 0)
	across = across.normalized()
	var lit := c0
	lit.a = light * (1.0 + SLOPE_SHADE * (n.dot(SUN.normalized()) - SUN.normalized().z))
	var along := EDGE_ORIGIN * 256.0
	var c1 := Color(float(tile), float(tile), along, float(1 + KIND_WALL * 4))
	var flat := (
		Vector3(n.x, 0.0, n.y).normalized() if Vector2(n.x, n.y).length() > 1e-6 else Vector3.RIGHT
	)
	for q: Vector3 in [a, b, c]:
		var u := (Vector2(q.x, q.y).dot(across) + EDGE_ORIGIN) * 128.0
		part.vertex(Vector3(q.x, q.z, q.y), flat, Vector2(u, (1.96 - q.z) * 100.0), lit, c1)
	var first := part.verts.size() - 3
	part.index.append_array(PackedInt32Array([first, first + 1, first + 2]))


## Every cell's floor at its ground, and its roof where it has one, merged
## along each row into runs of one height, tile, light and area.
func _add_floors() -> void:
	var w := level.width
	var h := level.height
	# The cells the terrain draws (their ground is under its surface).
	var under := PackedInt32Array()
	var terrained := level.geo != null and level.geo.terrain != null
	if terrained:
		under = level.geo.terrain.patch_at
	for overhead: bool in [false, true]:
		for y in h:
			if _skip_box(0.0, y + .5, w, y + .5):
				continue
			var x := 0
			while x < w:
				if _skip(x + .5, y + .5):
					x = (x / CHUNK + 1) * CHUNK
					continue
				var c := y * w + x
				var height_here := level.roof[c] if overhead else level.ground[c]
				var tile := level.ceiling_tile[c] if overhead else level.floor_tile[c]
				if (overhead and height_here <= 0.0) or tile < 0:
					x += 1
					continue
				if terrained and not overhead and under[c] != 0:
					x += 1
					continue
				var light := level.light[c]
				var area := level.area[c]
				var end := x + 1
				# A run stops at a chunk's edge too.
				var chunk_end := (x / CHUNK + 1) * CHUNK
				while end < w and end < chunk_end:
					var k := y * w + end
					var hk := level.roof[k] if overhead else level.ground[k]
					var tk := level.ceiling_tile[k] if overhead else level.floor_tile[k]
					if (
						hk != height_here
						or tk != tile
						or level.light[k] != light
						or level.area[k] != area
						or (terrained and not overhead and under[k] != 0)
					):
						break
					end += 1
				_flat(
					float(x),
					float(y),
					float(end),
					float(y + 1),
					height_here,
					tile,
					light,
					area,
					overhead
				)
				x = end


## A flat rectangle (a floor seen from above, a roof from below).
func _flat(
	x0: float,
	y0: float,
	x1: float,
	y1: float,
	z: float,
	tile: int,
	light: float,
	area: int,
	overhead: bool
) -> void:
	_polygon(
		PackedVector2Array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]),
		z,
		Vector2.ZERO,
		Vector2(x0, y0),
		tile,
		light,
		area,
		overhead
	)


## A convex polygon (map x, y, clockwise in y-down) on the plane
## z + g . (p - origin), facing up, or down when `overhead`.
func _polygon(
	poly: PackedVector2Array,
	z: float,
	g: Vector2,
	origin: Vector2,
	tile: int,
	light: float,
	area: int,
	overhead: bool
) -> void:
	if poly.size() < 3:
		return
	var centre := Vector2.ZERO
	for p in poly:
		centre += p
	centre /= poly.size()
	var part := _part(centre.x, centre.y, false)
	var n := Vector3(-g.x, 1.0, -g.y).normalized()
	if overhead:
		n = -n
	var c0 := _tint(area)
	c0.a = light
	var kind := KIND_ROOF if overhead else KIND_FLOOR
	var c1 := Color(float(tile), float(tile), 128.0, float(kind * 4))
	var first := part.verts.size()
	for p in poly:
		var pz := z + g.dot(p - origin)
		part.vertex(Vector3(p.x, pz, p.y), n, Vector2(p.x * 128.0, p.y * 128.0), c0, c1)
	# Clockwise seen from above is Godot's front face for a floor; a roof is
	# seen from below, so its triangles turn the other way.
	for i in range(1, poly.size() - 1):
		if overhead:
			part.index.append_array(PackedInt32Array([first, first + i + 1, first + i]))
		else:
			part.index.append_array(PackedInt32Array([first, first + i, first + i + 1]))


## A rectangle cut by lines (nx * x + ny * y <= c keeps a point).
static func _cut(x0: float, y0: float, x1: float, y1: float, cuts: Array) -> PackedVector2Array:
	var poly := PackedVector2Array(
		[Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)]
	)
	var k := 0
	while k + 2 < cuts.size():
		var nx: float = cuts[k]
		var ny: float = cuts[k + 1]
		var c: float = cuts[k + 2]
		var out := PackedVector2Array()
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var da := nx * a.x + ny * a.y - c
			var db := nx * b.x + ny * b.y - c
			if da <= 0.0:
				out.append(a)
			if (da <= 0.0) != (db <= 0.0):
				out.append(a.lerp(b, da / (da - db)))
		poly = out
		k += 3
	return poly


func _add_cap(cap: Array, h: float, overhead: bool) -> void:
	var x0: float = cap[0]
	var y0: float = cap[1]
	var x1: float = cap[2]
	var y1: float = cap[3]
	var tile: int = cap[4]
	if _skip_box(x0, y0, x1, y1):
		return
	var poly := _cut(x0, y0, x1, y1, cap.slice(5))
	var mid := Vector2((x0 + x1) * .5, (y0 + y1) * .5)
	var c := level.cell(clampf(mid.x, 0, level.width - .01), clampf(mid.y, 0, level.height - .01))
	_polygon(poly, h, Vector2.ZERO, Vector2.ZERO, tile, level.light[c], level.area[c], overhead)


## [z0, gx, gy, side, x0, y0, x1, y1, tile, light, area, cuts...]
func _add_slope(row: Array) -> void:
	var z0: float = row[0]
	var gx: float = row[1]
	var gy: float = row[2]
	var side: float = row[3]
	var x0: float = row[4]
	var y0: float = row[5]
	var x1: float = row[6]
	var y1: float = row[7]
	var tile: int = row[8]
	var light: float = row[9]
	var area: int = row[10]
	if _skip_box(minf(x0, x1), minf(y0, y1), maxf(x0, x1), maxf(y0, y1)):
		return
	var poly := _cut(x0, y0, x1, y1, row.slice(11))
	_polygon(poly, z0, Vector2(gx, gy), Vector2(x0, y0), tile, light, area, side < 0.0)
