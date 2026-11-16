## A level: res://data/<id>.json (the source of every map; see level_edit.gd
## for changing one) shuttled into packed arrays the renderer can read without
## per-pixel dictionary lookups (the reading and the tables built from it are
## level_load.gd's).
class_name LevelData
extends RefCounted

const WALL_STRIDE := 9
## The newest level file format this build reads (2: a geometry block).
const FORMAT := 2


class Door:
	var x: int
	var y: int
	var style: String = "slide"
	var vertical: bool = false
	var key: String = ""
	var secret: bool = false
	var blast_only: bool = false
	var progress: float = 0.0
	var opened: bool = false
	var discovered: bool = false
	var texture: String = ""
	var material: int = 0
	var id: String = ""

	## Mirrors level_hickston.Door.segment(); an empty array means fully open.
	func segment() -> PackedFloat32Array:
		if progress >= .995:
			return PackedFloat32Array()
		if style == "hinge":
			var turn := progress * PI * .5
			if vertical:
				return PackedFloat32Array([x + .5, y, x + .5 + sin(turn), y + cos(turn)])
			return PackedFloat32Array([x, y + .5, x + cos(turn), y + .5 + sin(turn)])
		if vertical:
			return PackedFloat32Array([x + .5, y + progress, x + .5, y + 1.0])
		return PackedFloat32Array([x + progress, y + .5, x + 1.0, y + .5])

	func center() -> Vector2:
		return Vector2(x + .5, y + .5)

	## Mirrors Door.blocks() for movement collision.
	func blocks(px: float, py: float, radius: float) -> bool:
		if absf(px - x - .5) > 1.3 or absf(py - y - .5) > 1.3:
			return false
		var seg := segment()
		if seg.is_empty():
			return false
		var ax := seg[0]
		var ay := seg[1]
		var ex := seg[2] - ax
		var ey := seg[3] - ay
		var t := clampf(((px - ax) * ex + (py - ay) * ey) / maxf(ex * ex + ey * ey, 1e-12), 0., 1.)
		var dx := px - ax - ex * t
		var dy := py - ay - ey * t
		return dx * dx + dy * dy < (radius + .055) * (radius + .055)


## Mirrors campaign.Station.
class Station:
	var id := ""
	var x := 0.0
	var y := 0.0
	var label := ""
	var message := ""
	var requires: Array = []
	var opens: Array = []
	var sectors: Array = []
	var cue := "lever_clunk"
	var reveals_secret := false
	var hidden := false
	var action := "use"
	var held := ""
	## The floor it is used from (format 2: on a deck); NAN the ground.
	var z := NAN


## Mirrors campaign.Extraction.
class Extraction:
	var x := 0.0
	var y := 0.0
	var label := ""
	var shutdown := ""
	var z := NAN


## Mirrors campaign.Billboard.
class Billboard:
	var x := 0.0
	var y := 0.0
	var image := ""
	var height := 1.0
	var z := 0.0
	var signal_name := ""
	var glow := false
	var plane := NAN
	var back := ""
	var hidden := false  # not drawn: features/arena_wreck.gd draws it on the move


## Mirrors level_hickston.Portal (a hub gate or the road gate).
class Gate:
	var destination := ""
	var x := 0.0
	var y := 0.0
	var width := 3.8
	var side := 1
	var closed_tile := -1

	## Select a single lane from its approach, including just past an open threshold.
	func approach(px: float, py: float, angle: float, reach: float) -> bool:
		var d := (py - y) * side
		var facing := sin(angle) * side
		return (
			-1.55 < d
			and d < reach
			and absf(px - x) < width * .5
			and (facing > .34 if d < -.30 else facing < -.43)
		)

	## Wall segment that closes a locked gate, its face to the side the gate
	## is walked up to (a wall shows on its left: east to west faces south).
	func barrier() -> PackedFloat32Array:
		var half := width * .5 * side
		return PackedFloat32Array(
			[x + half, y, x - half, y, float(closed_tile), 1.08, 0.0, 1.34, 11.0]
		)


## Mirrors county_events.CountyNote.
class Note:
	var x := 0.0
	var y := 0.0
	var label := ""
	var text := ""
	var plane := 0.0


## Mirrors county_events.Interior.
class Interior:
	var art := ""
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var height := 1.0
	var plane := 0.0


## Mirrors chatter.Exchange.
class Exchange:
	var id := ""
	var x := 0.0
	var y := 0.0
	var stop_at := ""
	var lines: Array = []


## Mirrors scenery.Reactive.
class Scenery:
	var id := ""
	var kind := ""
	var x := 0.0
	var y := 0.0
	var height := 1.0
	var z := 0.0
	var radius := .25
	var opens: Array = []
	var station := ""


var id := ""
var title := ""
var heading: PackedStringArray = PackedStringArray()
var introduction := ""
var ending := ""
var score := ""
var ambience := ""
var rescue := false
var spawn := PackedFloat32Array()
var districts: PackedStringArray = PackedStringArray()

var width := 0
var height := 0
var sky := "sky"
## The deep-water floor's tile (deep_at()), -1 without one.
var deep_tile := -1
var mirror_x := NAN

var solid: PackedInt32Array
var floor_tile: PackedInt32Array
var ceiling_tile: PackedInt32Array
var ground: PackedFloat32Array
var roof: PackedFloat32Array
var wall_height: PackedFloat32Array
var light: PackedFloat32Array
var area: PackedInt32Array
var tints: PackedFloat32Array

var walls := PackedFloat32Array()
var wall_count := 0
## Format 2: slabs, segments and ceilings beyond the grid (null without).
var geo: LevelGeometry = null
var format := 1
## height -> [x0, y0, x1, y1, tile, cuts...] seen from below; sloped surfaces
## [z0, gx, gy, side, x0, y0, x1, y1, tile, light, area, cuts...].
var roof_caps := {}
var slopes: Array = []
## The cells doors stand in (a door's own cell may be marked solid).
var door_cells := {}
## Bumped when the fixed wall list changes shape (open_cell(): a fence cell
## broken through), so the renderer puts it in map blocks again; and when a
## cell opens, so the automap is drawn again (0 until something breaks). A
## piece shown with another tile adds its start to `retiled` (set_wall_tile).
var walls_version := 0
var solid_version := 0
## The level file it was read from and that file's hash ("" when made from a
## dictionary): LevelGeometry.nav keeps the nav graph of a level as read.
var source_key := ""
var retiled := PackedVector2Array()
## Each open_cell() counts one in `reshapes` and adds to `reshaped` the
## points it changed (the cell's middle, every metre of each piece taken
## out): the 3D view builds only those chunks again.
var reshapes := 0
var reshaped := PackedVector2Array()
var boards_version := 0  # bumped when a board is hidden or shown (relisted)
## The fixed wall pieces by their edge (walls_on()), made when first asked.
var _edge_index := {}
var doors: Array[Door] = []
var pane_tiles: Array[Vector2i] = []
var fixtures: Array[PackedFloat32Array] = []
var collision_volumes: Array[PackedFloat32Array] = []

## Bumped whenever `light` is rewritten, so the display shader's copy follows.
var light_version := 0
var ground_heights := PackedFloat32Array()
var roof_heights := PackedFloat32Array()
## height -> Vector4i(x0, y0, x1, y1)
var floor_bounds := {}
var roof_bounds := {}
var floor_boxes: Array = []
var roof_boxes: Array = []
## height -> Array of [x0, y0, x1, y1, tile_index]
var caps := {}
## height -> Array of [tile_index, rate]
var moving_floors := {}

var road_and_hub: Array = []
var hub_gates: Array = []
var locked_gates: Array = []
## Wall rows a shut boss arena stands in its gaps (features/boss_lock.gd),
## drawn with the doors.
var lock_walls := PackedFloat32Array()

var enemies: Array = []
var patrols := {}
var pickups: Array = []
var props: Array = []
var billboards: Array = []
var scenery: Array = []
var stations: Array = []
var fuel_drums: Array = []
var dress_marks: Array = []
var interior_art: Array = []

var tile_names: PackedStringArray
var tile_index: Dictionary

var index_radius := .65

## Spatial indexes for movement/line-of-sight queries.
var near_doors := {}
var near_fixtures := {}
## 1 for a cell either index lists anything under (it stays 1 when a piece is
## taken out): a 0 lets blocked() skip both lookups for the open floor.
var index_cells := PackedByteArray()
## 1 for a cell either index lists anything under (index_cells without the
## geometry's cells): a geometry cell without it is the geometry's alone to
## blocked() at a height (LevelSight.visible's quick test).
var furniture_cells := PackedByteArray()
## 1 for a cell neither index lists anything under whose eight neighbours
## and itself are all open floor, off the map's edge: every step of a sight
## line inside it is clear, so visible() jumps to where the line leaves it.
## Never set again after load: a wall taken out leaves it 0 (still exact).
var clear_cells := PackedByteArray()
## 1 for an open cell off the map's edge with no door and no geometry listed
## under it (furniture may be): a sight line's steps through it are clear
## when the stretch inside it keeps blocked()'s reach from every solid cell
## round it and from the fixtures' boxes listed there (LevelSight.visible
## tests the stretch once instead of step by step). Never set again after
## load (a piece taken out leaves the index's list shorter, a wall taken out
## leaves the cell open: still exact).
var box_cells := PackedByteArray()
var broken_panes := {}
var return_gate: Gate = null
var extraction: Extraction = null
var hub_clues: Array = []
var controlled_doors := {}
var access_doors := {}
var crouch_doors := {}
var discovery_rooms := {}
var reinforcements: Array = []
var pressure_ports: Array = []
var boss_decoys: Array = []
## Where a boss arena's things stand, as each plan marks them: the first
## chapters' hazards (features/boss_arena.gd: kind -> notes) and the last
## bosses' burst pipes, floodlights and core (features/boss_arenas.gd).
var boss_arena := {}
## A 5v5 map's layout for the round modes (src/modes/tactical_mode.gd): the
## attackers' and defenders' spawns, the bomb sites, the hostages, the rescue
## box and the bots' routes and holds. Empty for every other level.
var tactical := {}
## Cars still lapping the track (features/race_laps.gd): their path, how
## many, how fast, the station that stops them.
var lap_cars := {}
var vehicles: Array = []  # to drive (features/vehicles.gd): [kind, x, y, heading]
## Set pieces run in them (features/vehicle_runs.gd): a dictionary each.
var vehicle_runs: Array = []
var distant_cues: Array = []
var notes: Array = []
var partners: Array = []
## Set pieces as data (triggers.gd): each a Dictionary as the JSON gives it.
var triggers: Array = []
var exchanges: Array = []
var ruptures := {}
var recovery_room: Variant = null
var hidden_rooms: Array = []
var map_labels: Array = []
var objective_side_tasks: Array = []
var control_name := ""
## Things to use that are not stations: [name, x, y] ("jukebox" plays the
## radio there, "sink").
var devices: Array = []
## District -> the room sound it has ("creek", "barn"); levels that say
## nothing get the old town's (creek 9, barn 4).
var area_sounds := {9: "creek", 4: "barn"}
## District -> the far-off cue heard now and then outdoors there.
var area_cues := {}
## Bumped when a level is rebuilt: a save of an older layout restarts it.
var layout := 1
## The fair's shooting booth: where its stand is (null: where it always was).
var gallery_stand: Variant = null
## The Crossroads: where its dispatch board stands (the trunk tag and the dust
## follow it) and the part of it the map shows [x, y, w, h].
var hub_board := Vector2(30.36, 44.13)
var map_window: Array = []

## Levels a tool hands in by id before (or instead of) writing them (the map
## tools' playtests and checks): load_level() takes these first.
static var preview := {}


static func load_level(level_id: String, assets: Assets) -> LevelData:
	if preview.has(level_id):
		var given: Dictionary = preview[level_id]
		return from_dict(given, assets)
	var raw := FileAccess.get_file_as_string("res://data/%s.json" % level_id)
	if raw.is_empty():
		push_error("no level data for " + level_id)
		return null
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		push_error("bad level json " + level_id)
		return null
	var j: Dictionary = parsed
	var lv := from_dict(j, assets)
	if lv != null:
		lv.source_key = "%s:%d:%d" % [level_id, raw.length(), raw.hash()]
	return lv


## LevelLoad.from_dict (level_load.gd).
static func from_dict(j: Dictionary, assets: Assets) -> LevelData:
	return LevelLoad.from_dict(j, assets)


## LevelLoad.build_plane_bounds (level_load.gd).
func _build_plane_bounds() -> void:
	LevelLoad.build_plane_bounds(self)


func tile_id(name: String) -> int:
	return _int(tile_index.get(name, -1))


const DETAIL_BASES := LevelTiles.DETAIL_BASES
const METAL_TILES := LevelTiles.METAL_TILES
const PLASTER_TILES := LevelTiles.PLASTER_TILES
const DIRT_TILES := LevelTiles.DIRT_TILES
## Sound cue per floor surface; anything else is gravel.
const SURFACE_SOUNDS := LevelTiles.SURFACE_SOUNDS

var _impact_surfaces := {}


## Mirrors engine.impact_surface(): the surface kind for a tile id.
func impact_surface(tile: int) -> String:
	if _impact_surfaces.is_empty():
		for name: String in METAL_TILES:
			_impact_surfaces[tile_id(name)] = "metal"
		for name: String in PLASTER_TILES:
			_impact_surfaces[tile_id(name)] = "plaster"
		for name: String in DIRT_TILES:
			_impact_surfaces[tile_id(name)] = "dirt"
		for name: String in DETAIL_BASES:
			_impact_surfaces[tile_id(name)] = _impact_surfaces.get(
				tile_id(str(DETAIL_BASES[name])), "wood"
			)
	var kind: Variant = _impact_surfaces.get(tile)
	return "wood" if kind == null else str(kind)


## Mirrors SURFACE_SOUNDS.get(floor, "gravel") using the tile id.
func surface_sound(tile: int) -> String:
	var name := String(tile_names[tile]) if tile >= 0 and tile < tile_names.size() else ""
	return str(SURFACE_SOUNDS.get(name, "gravel"))


## Mirrors TileMap.finish_geometry's spatial indexes (near_doors, near_fixtures).
func _build_indexes() -> void:
	near_doors = {}
	for door in doors:
		for yy in range(door.y - 1, door.y + 2):
			for xx in range(door.x - 1, door.x + 2):
				var key := Vector2i(xx, yy)
				if not near_doors.has(key):
					near_doors[key] = []
				var at_key: Array = near_doors[key]
				at_key.append(door)
	near_fixtures = {}
	for fixture in collision_volumes:
		var fx0 := floori(fixture[0] - index_radius)
		var fy0 := floori(fixture[1] - index_radius)
		var fx1 := floori(fixture[2] + index_radius)
		var fy1 := floori(fixture[3] + index_radius)
		for yy in range(fy0, fy1 + 1):
			for xx in range(fx0, fx1 + 1):
				var key := Vector2i(xx, yy)
				if not near_fixtures.has(key):
					near_fixtures[key] = []
				var at_key: Array = near_fixtures[key]
				at_key.append(fixture)
	door_cells = {}
	for door in doors:
		door_cells[door.y * width + door.x] = true
	index_cells = PackedByteArray()
	index_cells.resize(width * height)
	index_cells.fill(0)
	if geo != null:
		for i in width * height:
			index_cells[i] = geo.cells[i]
	furniture_cells = PackedByteArray()
	furniture_cells.resize(width * height)
	furniture_cells.fill(0)
	for index: Dictionary in [near_doors, near_fixtures]:
		for key: Vector2i in index:
			if key.x >= 0 and key.y >= 0 and key.x < width and key.y < height:
				index_cells[key.y * width + key.x] = 1
				furniture_cells[key.y * width + key.x] = 1
	# Open across: a cell and its left and right neighbours all open floor.
	var across := PackedByteArray()
	across.resize(width * height)
	across.fill(0)
	for cy in height:
		for cx in range(1, width - 1):
			var cell := cy * width + cx
			if solid[cell - 1] < 0 and solid[cell] < 0 and solid[cell + 1] < 0:
				across[cell] = 1
	clear_cells = PackedByteArray()
	clear_cells.resize(width * height)
	clear_cells.fill(0)
	box_cells = PackedByteArray()
	box_cells.resize(width * height)
	box_cells.fill(0)
	for cy in range(1, height - 1):
		for cx in range(1, width - 1):
			var cell := cy * width + cx
			if (
				index_cells[cell] == 0
				and across[cell] != 0
				and across[cell - width] != 0
				and across[cell + width] != 0
			):
				clear_cells[cell] = 1
			elif (
				solid[cell] < 0
				and (geo == null or geo.cells[cell] == 0)
				and not near_doors.has(Vector2i(cx, cy))
			):
				box_cells[cell] = 1


## Take one piece of furniture out of the way (a crate shot to pieces:
## features/breakables.gd): nothing collides with it after.
func drop_volume(volume: PackedFloat32Array) -> void:
	var i := collision_volumes.find(volume)
	if i < 0:
		return
	collision_volumes.remove_at(i)
	# Out of the index too, from the cells _build_indexes() put it in.
	for yy in range(floori(volume[1] - index_radius), floori(volume[3] + index_radius) + 1):
		for xx in range(floori(volume[0] - index_radius), floori(volume[2] + index_radius) + 1):
			var near: Array = near_fixtures.get(Vector2i(xx, yy), [])
			near.erase(volume)


## Show `tile` on fixed wall piece i (a window shot out, a fence shot about:
## features/wall_breaks.gd); `retiled` keeps where, for the 3D view.
func set_wall_tile(i: int, tile: int) -> void:
	walls[i * WALL_STRIDE + 4] = float(tile)
	retiled.append(Vector2(walls[i * WALL_STRIDE], walls[i * WALL_STRIDE + 1]))
	_active_key = []


## The fixed wall pieces lying exactly on the edge from (ax, ay) to (bx, by),
## that way round (a solid cell's face toward an open one runs clockwise round
## the cell, LevelEdit.EDGES).
func walls_on(ax: float, ay: float, bx: float, by: float) -> PackedInt32Array:
	if _edge_index.is_empty():
		for i in wall_count:
			var o := i * WALL_STRIDE
			var key := Vector4(walls[o], walls[o + 1], walls[o + 2], walls[o + 3])
			var list: PackedInt32Array = _edge_index.get(key, PackedInt32Array())
			list.append(i)
			_edge_index[key] = list
	return _edge_index.get(Vector4(ax, ay, bx, by), PackedInt32Array())


## Open a solid cell for good (a fence cell broken through: features/
## wall_breaks.gd). It is floor from now on to blocked(), visible() and (once
## reopened) the flow fields; the faces it showed leave the wall list and each
## solid cell beside it shows a face toward it, as the builder would have made
## it (LevelEdit.implied_walls), in `faces`' tile for its own when listed. The
## pieces taken out are the cell's own (a merged run of a LevelTiles.TILED
## plank wall is cut at the cell first: PlankWalls.split); the rest keep their
## order and the new faces go after them, as high as the cell's roof, or only
## as their own walls when `low` (a pen's fence under a barn's roof). Not for
## the Crossroads' split wall lists.
func open_cell(cx: int, cy: int, faces: Dictionary, low := false) -> void:
	if not road_and_hub.is_empty():
		return
	var c := cy * width + cx
	if solid[c] < 0:
		return
	var drop := {}
	var added := PackedFloat32Array()
	for e: Array in LevelEdit.EDGES:
		var ax := float(cx + _int(e[2]))
		var ay := float(cy + _int(e[3]))
		var bx := float(cx + _int(e[4]))
		var by := float(cy + _int(e[5]))
		for i in walls_on(ax, ay, bx, by):
			drop[i] = true
		var nx: int = cx + _int(e[0])
		var ny: int = cy + _int(e[1])
		if nx < 0 or ny < 0 or nx >= width or ny >= height:
			continue
		var n := ny * width + nx
		if solid[n] < 0:
			continue
		var tile := _int(faces.get(solid[n], solid[n]))
		added.append_array(
			PackedFloat32Array(
				[
					bx,
					by,
					ax,
					ay,
					float(tile),
					snappedf(light[c] * (1.0 if _int(e[0]) == 0 else .83), .0001),
					ground[c],
					wall_height[n] if low else maxf(wall_height[n], roof[c]),
					float(area[c])
				]
			)
		)
	solid[c] = -1
	reshapes += 1
	reshaped.append(Vector2(cx + .5, cy + .5))
	for i: int in drop:
		var a := Vector2(walls[i * WALL_STRIDE], walls[i * WALL_STRIDE + 1])
		var b := Vector2(walls[i * WALL_STRIDE + 2], walls[i * WALL_STRIDE + 3])
		var metres := ceili(a.distance_to(b))
		for k in metres + 1:
			reshaped.append(a.lerp(b, float(k) / maxf(1.0, metres)))
	var out := PackedFloat32Array()
	out.resize(walls.size() - drop.size() * WALL_STRIDE)
	var at := 0
	for i in wall_count:
		if drop.has(i):
			continue
		for k in WALL_STRIDE:
			out[at + k] = walls[i * WALL_STRIDE + k]
		at += WALL_STRIDE
	out.append_array(added)
	walls = out
	wall_count = out.size() / WALL_STRIDE
	walls_version += 1
	solid_version += 1
	_edge_index = {}
	_active_key = []


## Mirrors TileMap.blocked().
func blocked(x: float, y: float, radius := 0.0, z: Variant = null) -> bool:
	for step in 4:
		var dx := -radius if step < 2 else radius
		var dy := -radius if step % 2 == 0 else radius
		var ix := int(x + dx)
		var iy := int(y + dy)
		if ix < 0 or iy < 0 or ix >= width or iy >= height:
			return true
		if solid[iy * width + ix] >= 0:
			return true
	if not pane_tiles.is_empty() and pane_at(x, y, z, radius) != null:
		return true
	for gate: Gate in locked_gates:
		if absf(y - gate.y) < radius + .09 and absf(x - gate.x) < gate.width * .5 + radius:
			return true
	if geo != null and geo.cells[int(y) * width + int(x)] != 0:
		if z == null:
			var g := ground[int(y) * width + int(x)]
			if geo.blocks(x, y, radius, g + LevelGeometry.STEP, g + LevelGeometry.BODY):
				return true
		elif geo.solid_point(x, y, _float(z), radius, false):
			return true
	var near := radius <= index_radius
	if near and index_cells.size() == width * height and index_cells[int(y) * width + int(x)] == 0:
		# Neither index lists anything here: no furniture near enough, no door.
		return false
	var tile := Vector2i(int(x), int(y))
	var fixtures: Array = near_fixtures.get(tile, NOTHING) if near else collision_volumes
	for fixture: PackedFloat32Array in fixtures:
		var f: PackedFloat32Array = fixture
		if (
			f[0] - radius < x
			and x < f[2] + radius
			and f[1] - radius < y
			and y < f[3] + radius
			and (z == null or (f[7] - radius < _float(z) and _float(z) < f[4] + radius))
		):
			return true
	for door: Door in near_doors.get(tile, NOTHING):
		var d: Door = door
		if d.blocks(x, y, radius):
			return true
	return false


## An empty list to hand out as an index's "nothing here" (never added to).
const NOTHING: Array = []


## Mirrors TileMap.pane_at(); returns the pane cell or null.
func pane_at(x: float, y: float, z: Variant = null, radius := 0.0) -> Variant:
	for pane in pane_tiles:
		if broken_panes.has(pane):
			continue
		if (
			float(pane.x) - radius < x
			and x < float(pane.x) + 1.0 + radius
			and absf(y - float(pane.y) - .5) < radius + .044
			and (z == null or (.30 < _float(z) and _float(z) < 1.83))
		):
			return pane
	return null


## Mirrors TileMap.visible(): a stepped line-of-sight test (level_sight.gd).
func visible(
	x: float, y: float, xx: float, yy: float, z: Variant = null, zz: Variant = null
) -> bool:
	return LevelSight.visible(self, x, y, xx, yy, z, zz)


## Mirrors TileMap.move(): axis-separated with a step-height limit.
func move(body: Variant, dx: float, dy: float, radius: float, occupied: Variant = null) -> void:
	var start_x: float = body.x
	var start_y: float = body.y
	if _can_walk(body, start_x + dx, start_y, radius, occupied):
		body.x += dx
	if _can_walk(body, _float(body.x), start_y + dy, radius, occupied):
		body.y += dy
	if geo != null:
		geo.settle(self, body, radius)


## Gator Bayou's deep channels: nobody wades in (a body already in one may
## climb out); a body that swims (a gator, the king's airboat) goes anywhere.
func deep_at(x: float, y: float) -> bool:
	if deep_tile < 0 or x < 0.0 or y < 0.0 or x >= width or y >= height:
		return false
	return floor_tile[int(y) * width + int(x)] == deep_tile


## A deck (a walkable slab) stands over the deep water at (x, y).
func over_deep(x: float, y: float) -> bool:
	if geo == null or x < 0.0 or y < 0.0 or x >= width or y >= height:
		return false
	var c := int(y) * width + int(x)
	return geo.floor_at(x, y, 1e6, ground[c], true) > ground[c] + LevelGeometry.STEP


func _can_walk(body: Variant, x: float, y: float, radius: float, occupied: Variant) -> bool:
	if geo != null:
		# Format 2: the 3D test everywhere (the grid's own below differs from it
		# by fixture heights, over water say, so it is never a short cut).
		return geo.can_walk(self, body, x, y, radius, occupied)
	if blocked(x, y, radius):
		return false
	if deep_tile >= 0 and deep_at(x, y) and not deep_at(_float(body.x), _float(body.y)):
		var thing: Object = body
		if not thing.get("swims"):
			return false
	if occupied != null:
		var taken: Callable = occupied
		if taken.call(x, y):
			return false
	# An enemy has no `air` (only the player climbs a step by jumping); the
	# type test answers as `"air" in body` would, without looking the name up.
	if body is Enemy or not ("air" in body):
		return true
	var up := elevation(x, y) - elevation(_float(body.x), _float(body.y))
	return up <= .245 + _float(body.air)


## Mirrors TileMap.update(): doors slide open/closed, blocked by live enemies.
## Swings the doors; a closing door waits while any of `players` stands in
## it (and backs off an enemy in its way).
func update(dt: float, players: Array, enemies: Array) -> void:
	for door in doors:
		if (door.opened and door.progress >= 1.0) or (not door.opened and door.progress <= 0.0):
			continue
		var centre := door.center()
		if not door.opened and _someone_in(players, centre):
			continue
		var direction := 1.0 if door.opened else -1.0
		var previous := door.progress
		door.progress = maxf(0.0, minf(1.0, door.progress + dt * 1.65 * direction))
		if not door.opened:
			for enemy: Enemy in enemies:
				if enemy.alive and door.blocks(enemy.x, enemy.y, enemy.radius):
					door.progress = previous
					break


func _someone_in(players: Array, centre: Vector2) -> bool:
	for player: Player in players:
		if (
			sqrt(
				(
					(player.x - centre.x) * (player.x - centre.x)
					+ (player.y - centre.y) * (player.y - centre.y)
				)
			)
			< .8
		):
			return true
	return false


func elevation(x: float, y: float) -> float:
	return ground[int(y) * width + int(x)]


func cell(x: float, y: float) -> int:
	return int(y) * width + int(x)


## The fixed walls active_walls() starts from (the moving ones follow them).
func active_base(at_hub: bool) -> PackedFloat32Array:
	if at_hub and not road_and_hub.is_empty():
		return road_and_hub[1]
	if at_hub or road_and_hub.is_empty():
		return walls
	return road_and_hub[0]


## Wall segments drawn this frame: static walls (or the hub split) plus doors,
## panes and locked gate barriers, matching Renderer.draw / door_walls().
func active_walls(at_hub: bool) -> PackedFloat32Array:
	# Only doors and gates move (and the light, which the walls carry, changes
	# with light_version): the list is made again only when one of them has.
	var key: Array = [at_hub, light_version, locked_gates.size(), lock_walls.size()]
	if not at_hub:
		for door in doors:
			key.append(door.progress)
	if key == _active_key:
		return _active_last
	_active_key = key
	_active_last = _make_active(at_hub)
	return _active_last


## The last active_walls() list and what it was made for.
var _active_key: Array = []
var _active_last := PackedFloat32Array()


func _make_active(at_hub: bool) -> PackedFloat32Array:
	var out := active_base(at_hub).duplicate()
	# A locked gate's barricade shows wherever the gate is: the rebuilt
	# Crossroads has no road split, so the renderer never asks for at_hub there.
	for gate: Gate in locked_gates:
		out.append_array(gate.barrier())
	out.append_array(lock_walls)
	if not at_hub:
		for door in doors:
			var seg := door.segment()
			if seg.is_empty():
				continue
			var idx := door.y * width + door.x
			out.append(seg[0])
			out.append(seg[1])
			out.append(seg[2])
			out.append(seg[3])
			out.append(float(door.material))
			out.append(light[idx])
			out.append(0.0)
			out.append(1.85)
			out.append(float(area[idx]))
		for p in pane_tiles:
			out.append(float(p.x))
			out.append(p.y + .5)
			out.append(p.x + 1.0)
			out.append(p.y + .5)
			out.append(_float(tile_index.get("glazing", 0)))
			out.append(.98)
			out.append(.36)
			out.append(1.78)
			out.append(1.0)
	return out


# ------------------------------------------------------------- format 2


## The floor under a body (its feet when it is not in the air). Anything
## that is not a body with a floor (a point, a piece of scenery) gets the
## cell's ground, as elevation() gives it.
func stand(body: Variant) -> float:
	var bx: float = body.x
	var by: float = body.y
	if geo == null:
		# elevation() written out: this is asked thousands of times a tick.
		return ground[int(by) * width + int(bx)]
	if not (body is Player or body is Enemy):
		return elevation(bx, by)
	var c := _cell_near(bx, by)
	var r: float = body.radius if body is Enemy else .2
	return geo.support(bx, by, r, _float(body.floor_z), ground[c])


## The highest floor at (x, y) at or below z (the cell's ground without geometry).
func floor_under(x: float, y: float, z: float) -> float:
	if geo == null:
		return ground[int(y) * width + int(x)]
	var c := _cell_near(x, y)
	return geo.floor_at(x, y, z - LevelGeometry.STEP, ground[c], true)


## The lowest surface over (x, y, z), or 0 when the sky is over it (the
## cell's roof without geometry).
func roof_over(x: float, y: float, z: float) -> float:
	var c := _cell_near(x, y)
	if geo == null:
		return roof[c]
	# A roof of 0 is the open sky (as everywhere else reads it).
	var r := roof[c] if roof[c] != 0.0 and roof[c] > z + .01 else INF
	r = minf(r, geo.ceiling_at(x, y, z))
	return 0.0 if r == INF else r


## Whether a step of a shot or a sight line from one point to the next passed
## through a deck's top or underside.
func crosses(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float) -> bool:
	return geo != null and geo.crosses(x0, y0, z0, x1, y1, z1)


## The floor a station or the exit at `at` is used from (format 2: NAN when
## it is on the ground or nothing stands there).
func goal_floor(at: Vector2) -> float:
	for s: Station in stations:
		if Vector2(s.x, s.y).distance_to(at) < .01:
			return s.z
	if extraction != null and Vector2(extraction.x, extraction.y).distance_to(at) < .01:
		return extraction.z
	return NAN


func _cell_near(x: float, y: float) -> int:
	return clampi(int(y), 0, height - 1) * width + clampi(int(x), 0, width - 1)


## Whether two bodies stand on floors a step can't join (format 2: one on a
## deck, one under it): a hand that sees the player up there walks the nav
## graph round to the stairs rather than straight at them.
func apart(a: Variant, b: Variant) -> bool:
	return geo != null and absf(stand(a) - stand(b)) > .45


## int() and float() of a value read from data or a dictionary, typed (the
## same result for a number, a bool or a number written as text).
static func _int(v: Variant) -> int:
	return str(v).to_int() if v is String else v


static func _float(v: Variant) -> float:
	return str(v).to_float() if v is String else v
