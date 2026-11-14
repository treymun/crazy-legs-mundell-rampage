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
const KIND_FLOOR := 8
const KIND_ROOF := 9

## Plain wall materials that repeat at a fixed size (RenderState.TILED).
const TILED: Array[String] = [
	"wood",
	"barn",
	"tin",
	"brick",
	"plaster",
	"cinder",
	"office_wall",
	"quarry_face",
	"hedgerow",
	"tile",
	"quarry_shed",
	"mill_log",
	"fascia"
]


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
## chunk key -> [opaque Part, glazing Part]
var _chunks := {}


func _init(p_level: LevelData) -> void:
	level = p_level
	var names := level.tile_names
	tile_mode.resize(names.size())
	tile_base.resize(names.size())
	for i in names.size():
		var tile_name := String(names[i])
		tile_base[i] = i
		tile_mode[i] = 0
		if TILED.has(tile_name):
			tile_mode[i] = 1
		elif (
			tile_name.ends_with("_win")
			or tile_name.ends_with("_lit")
			or tile_name.ends_with("_brk")
		):
			var plain := tile_name.substr(0, tile_name.length() - 4)
			if TILED.has(plain) and level.tile_id(plain) >= 0:
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


## The level's fixed geometry: base walls (LevelData.active_base), floors,
## roofs, caps and slopes. Returns chunk key (Vector2i) -> ArrayMesh, whose
## surface 0 is opaque and surface 1 (when present) the window glazing.
func build_static(base_walls: PackedFloat32Array) -> Dictionary:
	_chunks = {}
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
	return _finish()


## Only the given wall rows (doors, panes, gates: what moves), as one mesh
## (null when there is nothing).
func build_walls(rows: PackedFloat32Array) -> ArrayMesh:
	_chunks = {}
	add_walls(rows)
	var opaque := Part.new()
	var glazing := Part.new()
	for key: Vector2i in _chunks:
		_append(opaque, _chunks[key][0])
		_append(glazing, _chunks[key][1])
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
	var parts: Array = _chunks.get(key, [])
	if parts.is_empty():
		parts = [Part.new(), Part.new()]
		_chunks[key] = parts
	return parts[1] if glass else parts[0]


func _tint(area: int) -> Color:
	var n := level.tints.size() / 3
	var i := clampi(area, 0, maxi(0, n - 1)) * 3
	if level.tints.size() < 3:
		return Color(1, 1, 1)
	return Color(level.tints[i], level.tints[i + 1], level.tints[i + 2])


## Every row of `rows` (stride 9: ax, ay, bx, by, tile, light, bottom, top,
## area) as an upright quad, seen from both sides.
func add_walls(rows: PackedFloat32Array) -> void:
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
		if top <= bottom:
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
		var plain := kind == KIND_WALL
		var mode := int(tile_mode[tile]) if plain and tile >= 0 and tile < tile_mode.size() else 0
		var along := length * 128.0 if mode != 0 else 128.0
		var base := tile_base[tile] if mode == 2 else tile
		var v_top := (1.96 - top) * 100.0 if mode != 0 else 0.0
		var v_bottom := (1.96 - bottom) * 100.0 if mode != 0 else 128.0
		# The face's normal in map terms is (dy, -dx); world.gdshader flips u
		# back for a viewer on that side, as the old renderer did.
		var n := Vector3(by - ay, 0.0, -(bx - ax)) / length
		var c0 := _tint(area)
		c0.a = light
		var c1 := Color(float(tile), float(base), along, float(mode + kind * 4))
		var part := _part((ax + bx) * .5, (ay + by) * .5, kind == KIND_GLAZING)
		part.vertex(Vector3(ax, bottom, ay), n, Vector2(0.0, v_bottom), c0, c1)
		part.vertex(Vector3(ax, top, ay), n, Vector2(0.0, v_top), c0, c1)
		part.vertex(Vector3(bx, top, by), n, Vector2(along, v_top), c0, c1)
		part.vertex(Vector3(bx, bottom, by), n, Vector2(along, v_bottom), c0, c1)
		part.quad()


## Every cell's floor at its ground, and its roof where it has one, merged
## along each row into runs of one height, tile, light and area.
func _add_floors() -> void:
	var w := level.width
	var h := level.height
	for overhead in [false, true]:
		for y in h:
			var x := 0
			while x < w:
				var c := y * w + x
				var height_here := level.roof[c] if overhead else level.ground[c]
				var tile := level.ceiling_tile[c] if overhead else level.floor_tile[c]
				if (overhead and height_here <= 0.0) or tile < 0:
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
		var nx := float(cuts[k])
		var ny := float(cuts[k + 1])
		var c := float(cuts[k + 2])
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
	var poly := _cut(float(cap[0]), float(cap[1]), float(cap[2]), float(cap[3]), cap.slice(5))
	var mid := Vector2((float(cap[0]) + float(cap[2])) * .5, (float(cap[1]) + float(cap[3])) * .5)
	var c := level.cell(clampf(mid.x, 0, level.width - .01), clampf(mid.y, 0, level.height - .01))
	_polygon(
		poly, h, Vector2.ZERO, Vector2.ZERO, int(cap[4]), level.light[c], level.area[c], overhead
	)


## [z0, gx, gy, side, x0, y0, x1, y1, tile, light, area, cuts...]
func _add_slope(row: Array) -> void:
	var x0 := float(row[4])
	var y0 := float(row[5])
	var poly := _cut(x0, y0, float(row[6]), float(row[7]), row.slice(11))
	_polygon(
		poly,
		float(row[0]),
		Vector2(float(row[1]), float(row[2])),
		Vector2(x0, y0),
		int(row[8]),
		float(row[9]),
		int(row[10]),
		float(row[3]) < 0.0
	)
