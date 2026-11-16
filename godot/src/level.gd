## A level: res://data/<id>.json (the source of every map; see level_edit.gd
## for changing one) shuttled into packed arrays the renderer can read without
## per-pixel dictionary lookups.
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
var retiled := PackedVector2Array()
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
## 1 for a cell neither index lists anything under whose eight neighbours
## and itself are all open floor, off the map's edge: every step of a sight
## line inside it is clear, so visible() jumps to where the line leaves it.
## Never set again after load: a wall taken out leaves it 0 (still exact).
var clear_cells := PackedByteArray()
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
	return from_dict(j, assets)


## A level from its file's contents (load_level; the map tools check one
## before it is written).
static func from_dict(j: Dictionary, assets: Assets) -> LevelData:
	var lv := LevelData.new()
	lv.format = _int(j.get("format", 1))
	if lv.format > FORMAT:
		push_error(
			"level %s is format %d, newer than this build (%d)" % [j["id"], lv.format, FORMAT]
		)
		return null
	lv.tile_names = assets.tile_names
	lv.tile_index = assets.tile_index
	lv.id = str(j["id"])
	lv.title = str(j["title"])
	for v: Variant in j.get("heading", []):
		lv.heading.append(str(v))
	lv.introduction = str(j.get("intro", ""))
	lv.ending = str(j.get("ending", ""))
	lv.score = str(j.get("score", ""))
	lv.ambience = str(j.get("ambience", ""))
	lv.rescue = j.get("rescue", false)
	lv.spawn = _floats(j["spawn"])
	for v: Variant in j.get("districts", []):
		lv.districts.append(str(v))
	lv.width = _int(j["width"])
	lv.height = _int(j["height"])
	lv.sky = str(j["sky"])
	if j.get("mirror") != null:
		lv.mirror_x = _float(j["mirror"][0])

	lv.solid = _ints(j["solid"])
	lv.floor_tile = _ints(j["floor"])
	lv.ceiling_tile = _ints(j["ceiling"])
	lv.ground = _floats(j["ground"])
	lv.roof = _floats(j["roof"])
	lv.wall_height = _floats(j["wall_height"])
	lv.light = _floats(j["light"])
	lv.area = _ints(j["area"])
	lv.tints = _floats2(j["tints"])

	lv.ground_heights = _floats(j["ground_heights"])
	lv.roof_heights = _floats(j["roof_heights"])

	var wall_list: Array = j["walls"]
	lv.wall_count = wall_list.size()
	lv.walls.resize(lv.wall_count * WALL_STRIDE)
	for i in lv.wall_count:
		var row: Array = wall_list[i]
		var o := i * WALL_STRIDE
		for k in WALL_STRIDE:
			lv.walls[o + k] = _float(row[k])

	if not j.get("hub_split", false):
		lv._merge_runs()

	for d: Dictionary in j.get("doors", []):
		var door := Door.new()
		door.x = _int(d["x"])
		door.y = _int(d["y"])
		door.style = str(d.get("style", "slide"))
		door.vertical = d.get("vertical", false)
		door.key = str(d.get("key", ""))
		door.secret = d.get("secret", false)
		door.blast_only = d.get("blast_only", false)
		door.progress = _float(d.get("progress", 0.))
		door.opened = d.get("opened", false)
		door.discovered = d.get("discovered", false)
		door.texture = str(d.get("texture", ""))
		door.material = _int(d.get("material", 0))
		door.id = str(d.get("id", ""))
		lv.doors.append(door)

	for p: Variant in j.get("pane_tiles", []):
		lv.pane_tiles.append(Vector2i(_int(p[0]), _int(p[1])))

	for f: Array in j.get("fixtures", []):
		lv.fixtures.append(_floats(f))
	for f: Array in j.get("collision_volumes", []):
		lv.collision_volumes.append(_floats(f))

	for key: Variant in j.get("caps", {}):
		var h := _f32(_float(key))
		var list: Array = []
		for c: Variant in j["caps"][key]:
			list.append(
				[_float(c[0]), _float(c[1]), _float(c[2]), _float(c[3]), lv.tile_id(str(c[4]))]
			)
		lv.caps[h] = list

	lv._take_geometry(j.get("geometry"))
	lv._build_plane_bounds()

	for g: Dictionary in j.get("hub_gates", []):
		lv.hub_gates.append(_gate(lv, g))
	if j.get("return_gate") != null:
		var back: Dictionary = j["return_gate"]
		lv.return_gate = _gate(lv, back)

	lv.enemies = j.get("enemies", [])
	for key: Variant in j.get("patrols", {}):
		lv.patrols[_int(key)] = j["patrols"][key]
	lv.pickups = j.get("pickups", [])
	lv.props = j.get("props", [])
	for b: Dictionary in j.get("billboards", []):
		var board := Billboard.new()
		board.x = _float(b["x"])
		board.y = _float(b["y"])
		board.image = str(b["image"])
		board.height = _float(b["height"])
		board.z = _float(b.get("z", 0.))
		board.signal_name = str(b.get("signal", ""))
		board.glow = b.get("glow", false)
		board.plane = NAN if b.get("plane") == null else _float(b["plane"])
		board.back = str(b.get("back", ""))
		lv.billboards.append(board)
	for s: Dictionary in j.get("scenery", []):
		var prop := Scenery.new()
		prop.id = str(s["id"])
		prop.kind = str(s["kind"])
		prop.x = _float(s["x"])
		prop.y = _float(s["y"])
		prop.height = _float(s["height"])
		prop.z = _float(s.get("z", 0.))
		prop.radius = _float(s.get("radius", .25))
		for p: Variant in s.get("opens", []):
			prop.opens.append(Vector2i(_int(p[0]), _int(p[1])))
		prop.station = str(s.get("station", ""))
		lv.scenery.append(prop)
	lv.fuel_drums = j.get("fuel_drums", [])
	lv.dress_marks = j.get("dress_marks", [])
	for i: Variant in j.get("interiors", []):
		var room := Interior.new()
		room.art = str(i[0])
		room.x = _float(i[1])
		room.y = _float(i[2])
		room.z = _float(i[3])
		room.height = _float(i[4])
		room.plane = _float(i[5])
		lv.interior_art.append(room)

	for s: Dictionary in j.get("stations", []):
		var station := Station.new()
		station.id = str(s["id"])
		station.x = _float(s["x"])
		station.y = _float(s["y"])
		station.label = str(s.get("label", ""))
		station.message = str(s.get("message", ""))
		station.requires = s.get("requires", [])
		for p: Variant in s.get("opens", []):
			station.opens.append(Vector2i(_int(p[0]), _int(p[1])))
		station.sectors = s.get("sectors", [])
		station.cue = str(s.get("cue", "lever_clunk"))
		station.reveals_secret = s.get("reveals_secret", false)
		station.hidden = s.get("hidden", false)
		station.action = str(s.get("action", "use"))
		station.held = str(s.get("held", ""))
		station.z = _float(s["z"]) if s.has("z") else NAN
		lv.stations.append(station)

	lv.control_name = str(j.get("control_name", ""))
	lv.layout = _int(j.get("layout", 1))
	if j.get("hub_board") != null:
		lv.hub_board = Vector2(_float(j["hub_board"][0]), _float(j["hub_board"][1]))
	lv.map_window = j.get("map_window", [])
	if j.get("gallery") != null:
		lv.gallery_stand = Vector2(_float(j["gallery"][0]), _float(j["gallery"][1]))
	for d: Variant in j.get("devices", []):
		lv.devices.append([str(d[0]), _float(d[1]), _float(d[2])])
	if j.has("area_sounds"):
		lv.area_sounds = {}
		for key: Variant in j["area_sounds"]:
			lv.area_sounds[_int(key)] = str(j["area_sounds"][key])
	for key: Variant in j.get("area_cues", {}):
		lv.area_cues[_int(key)] = str(j["area_cues"][key])
	if j.get("extraction") != null:
		var ex: Dictionary = j["extraction"]
		var exit := Extraction.new()
		exit.x = _float(j["extraction"]["x"])
		exit.y = _float(j["extraction"]["y"])
		exit.label = str(j["extraction"]["label"])
		exit.shutdown = str(j["extraction"]["shutdown"])
		exit.z = _float(ex.get("z", NAN))
		lv.extraction = exit
	for clue: Variant in j.get("hub_clues", []):
		lv.hub_clues.append(
			[str(clue[0]), _float(clue[1]), _float(clue[2]), str(clue[3]), str(clue[4])]
		)
	for point: Variant in j.get("pressure_ports", []):
		lv.pressure_ports.append(Vector2(_float(point[0]), _float(point[1])))
	var laps: Variant = j.get("lap_cars", {})
	lv.lap_cars = laps if laps is Dictionary else {}
	lv.vehicles = j.get("vehicles", []) if j.get("vehicles", []) is Array else []
	for point: Variant in j.get("boss_decoys", []):
		lv.boss_decoys.append(Vector2(_float(point[0]), _float(point[1])))
	var arena: Variant = j.get("boss_arena", {})
	lv.boss_arena = arena if arena is Dictionary else {}
	var plan: Variant = j.get("tactical", {})
	lv.tactical = plan if plan is Dictionary else {}
	for cue: Variant in j.get("distant_cues", []):
		lv.distant_cues.append([_float(cue[0]), _float(cue[1]), str(cue[2])])
	for n: Array in j.get("notes", []):
		var note := Note.new()
		note.x = _float(n[0])
		note.y = _float(n[1])
		note.label = str(n[2])
		note.text = str(n[3])
		note.plane = _float(n[4]) if n.size() > 4 else 0.0
		lv.notes.append(note)
	for n: Variant in j.get("partners", []):
		lv.partners.append([str(n[0]), str(n[1]), _int(n[2])])
	for trigger: Variant in j.get("triggers", []):
		var td: Dictionary = trigger if trigger is Dictionary else {}
		if td.has("id"):
			lv.triggers.append(trigger)
	for n: Dictionary in j.get("exchanges", []):
		var exchange := Exchange.new()
		exchange.id = str(n["id"])
		exchange.x = _float(n["x"])
		exchange.y = _float(n["y"])
		exchange.stop_at = str(n.get("stop_at", ""))
		exchange.lines = n.get("lines", [])
		lv.exchanges.append(exchange)
	lv.ruptures = {}
	for key: Variant in j.get("ruptures", {}):
		var rup: Array = j["ruptures"][key]
		lv.ruptures[str(key)] = [_float(rup[0]), _float(rup[1]), str(rup[2])]
	if j.get("recovery_room") != null:
		var rec: Array = j["recovery_room"]
		lv.recovery_room = [
			_float(rec[0]), _float(rec[1]), _float(rec[2]), _float(rec[3]), str(rec[4])
		]
	lv.objective_side_tasks = j.get("objective_side_tasks", [])
	for point: Variant in j.get("controlled_doors", []):
		lv.controlled_doors[Vector2i(_int(point[0]), _int(point[1]))] = true
	for point: Variant in j.get("crouch_doors", []):
		lv.crouch_doors[Vector2i(_int(point[0]), _int(point[1]))] = true
	lv.access_doors = {}
	for key: Variant in j.get("access_doors", {}):
		var parts := str(key).split(",")
		lv.access_doors[Vector2i(int(parts[0]), int(parts[1]))] = j["access_doors"][key]
	lv.discovery_rooms = {}
	for key: Variant in j.get("discovery_rooms", {}):
		var pair := str(key).split(",")
		lv.discovery_rooms[Vector2i(int(pair[0]), int(pair[1]))] = j["discovery_rooms"][key]
	lv.reinforcements = j.get("reinforcements", [])
	for room: Variant in j.get("hidden_rooms", []):
		lv.hidden_rooms.append(
			[
				Vector2i(_int(room[0][0]), _int(room[0][1])),
				Vector4i(_int(room[1][0]), _int(room[1][1]), _int(room[1][2]), _int(room[1][3]))
			]
		)
	for label: Variant in j.get("map_labels", []):
		lv.map_labels.append([str(label[0]), _int(label[1]), _int(label[2])])
	lv._build_indexes()

	if j.get("hub_split", false):
		lv._split_road_and_hub()
	lv._build_moving_floors()
	lv.deep_tile = lv.tile_id("bayou_deep")
	return lv


static func _gate(lv: LevelData, g: Dictionary) -> Gate:
	var gate := Gate.new()
	gate.destination = str(g["destination"])
	gate.x = _float(g["x"])
	gate.y = _float(g["y"])
	gate.width = _float(g.get("width", 3.8))
	gate.side = _int(g.get("side", 1))
	gate.closed_tile = lv.tile_id("route_closed")
	return gate


static func _ints(values: Variant) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(len(values))
	for i in len(values):
		out[i] = _int(values[i])
	return out


static func _floats(values: Variant) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(len(values))
	for i in len(values):
		out[i] = _float(values[i])
	return out


static func _floats2(rows: Variant) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(len(rows) * 3)
	for i in len(rows):
		var row: Array = rows[i]
		out[i * 3] = _float(row[0])
		out[i * 3 + 1] = _float(row[1])
		out[i * 3 + 2] = _float(row[2])
	return out


## Round a double to the nearest float32 value so dictionary keys built from
## JSON strings compare equal to keys built from packed float arrays.
static func _f32(value: float) -> float:
	var one := PackedFloat32Array()
	one.resize(1)
	one[0] = value
	return float(one[0])


## Mirrors Renderer.plane_bounds, but gathers every bbox in one pass over cells
## instead of rescanning the grid per height.
func _build_plane_bounds() -> void:
	var buckets := {}
	for i in ground.size():
		var h := ground[i]
		var y := i / width
		var x := i - y * width
		var b: Variant = buckets.get(h)
		if b == null:
			buckets[h] = [x, y, x + 1, y + 1]
		else:
			if x < b[0]:
				b[0] = x
			if y < b[1]:
				b[1] = y
			if x + 1 > b[2]:
				b[2] = x + 1
			if y + 1 > b[3]:
				b[3] = y + 1
	floor_bounds = {}
	# Python inserts floors nearest-first (reversed sorted heights).
	var heights := Array(ground_heights)
	heights.sort()
	heights.reverse()
	for height: float in heights:
		var b: Variant = buckets.get(height)
		var extra: Array = caps.get(height, [])
		if b == null and extra.is_empty():
			continue
		var x0 := 1 << 30
		var y0 := 1 << 30
		var x1 := -(1 << 30)
		var y1 := -(1 << 30)
		if b != null:
			x0 = b[0]
			y0 = b[1]
			x1 = b[2]
			y1 = b[3]
		for c: Variant in extra:
			x0 = mini(x0, _int(c[0]))
			y0 = mini(y0, _int(c[1]))
			x1 = maxi(x1, _int(ceil(c[2])))
			y1 = maxi(y1, _int(ceil(c[3])))
		floor_bounds[height] = Vector4i(x0, y0, x1, y1)

	var roof_buckets := {}
	for i in roof.size():
		var h := roof[i]
		if h <= 0.0:
			continue
		var y := i / width
		var x := i - y * width
		var b: Variant = roof_buckets.get(h)
		if b == null:
			roof_buckets[h] = [x, y, x + 1, y + 1]
		else:
			if x < b[0]:
				b[0] = x
			if y < b[1]:
				b[1] = y
			if x + 1 > b[2]:
				b[2] = x + 1
			if y + 1 > b[3]:
				b[3] = y + 1
	roof_bounds = {}
	var rheight := Array(roof_heights)
	rheight.sort()
	for height: float in rheight:
		var b: Variant = roof_buckets.get(height)
		var over: Array = roof_caps.get(height, [])
		if b == null and over.is_empty():
			continue
		var r := Vector4i(1 << 30, 1 << 30, -(1 << 30), -(1 << 30))
		if b != null:
			r = Vector4i(_int(b[0]), _int(b[1]), _int(b[2]), _int(b[3]))
		for c: Variant in over:
			r = Vector4i(
				mini(r.x, _int(c[0])),
				mini(r.y, _int(c[1])),
				maxi(r.z, _int(ceil(c[2]))),
				maxi(r.w, _int(ceil(c[3])))
			)
		roof_bounds[height] = r
	floor_boxes = _tight_boxes(floor_bounds, ground, caps)
	roof_boxes = _tight_boxes(roof_bounds, roof, roof_caps)


## The planes the renderer walks: [height, box] in the bounds' order. A height
## whose cells are scattered across a big box (a creek, a few porch roofs) is
## cut into tight boxes, so the pixels between them are not tested for it.
func _tight_boxes(bounds: Dictionary, grid: PackedFloat32Array, capped: Dictionary) -> Array:
	var out: Array = []
	for h: float in bounds:
		var box: Vector4i = bounds[h]
		var area := (box.z - box.x) * (box.w - box.y)
		var count := 0
		for y in range(maxi(0, box.y), mini(height, box.w)):
			for x in range(maxi(0, box.x), mini(width, box.z)):
				if grid[y * width + x] == h:
					count += 1
		if capped.has(h) or area <= 64 or count * 2 >= area:
			out.append([h, box])
			continue
		for ty in range(box.y, box.w, 8):
			for tx in range(box.x, box.z, 8):
				var x0 := 1 << 30
				var y0 := 1 << 30
				var x1 := -1
				var y1 := -1
				for y in range(ty, mini(box.w, ty + 8)):
					for x in range(tx, mini(box.z, tx + 8)):
						if grid[y * width + x] == h:
							x0 = mini(x0, x)
							y0 = mini(y0, y)
							x1 = maxi(x1, x + 1)
							y1 = maxi(y1, y + 1)
				if x1 >= 0:
					out.append([h, Vector4i(x0, y0, x1, y1)])
	return out


## Mirrors Renderer.__init__'s wall split when the level has hub gates.
## Runs of one repeating wall material in a straight line, cell edge to cell
## edge, become one piece: what the renderer spends goes with the pieces in
## view, and a long street is all runs. They look the same (a repeating
## material is laid along a wall by its length). The file keeps one piece a
## cell, which is what level_edit.gd patches. Not for the Crossroads, whose
## walls are split at its row 33 into the road's and the hub's.
func _merge_runs() -> void:
	var tiled := {}
	for name: String in LevelTiles.TILED:
		if tile_index.has(name):
			tiled[_int(tile_index[name])] = true
	var out := PackedFloat32Array()
	var by_end := {}
	var by_start := {}
	for i in wall_count:
		var o := i * WALL_STRIDE
		var a := Vector2(walls[o], walls[o + 1])
		var b := Vector2(walls[o + 2], walls[o + 3])
		var step := b - a
		var whole := a == a.floor() and b == b.floor() and (step.x == 0.0 or step.y == 0.0)
		if not tiled.has(int(walls[o + 4])) or not whole or step == Vector2.ZERO:
			for k in WALL_STRIDE:
				out.append(walls[o + k])
			continue
		var kind := (
			"%s|%s|%s|%s|%s|%s"
			% [
				step.normalized(),
				walls[o + 4],
				walls[o + 5],
				walls[o + 6],
				walls[o + 7],
				walls[o + 8]
			]
		)
		var after := "%s|%s" % [a, kind]
		var before := "%s|%s" % [b, kind]
		if by_end.has(after):
			# This piece carries on from the end of a run: the run reaches b.
			var r: int = by_end[after]
			by_end.erase(after)
			out[r + 2] = b.x
			out[r + 3] = b.y
			by_end["%s|%s" % [b, kind]] = r
		elif by_start.has(before):
			# A run starts where this piece ends: the run starts at a now.
			var r: int = by_start[before]
			by_start.erase(before)
			out[r] = a.x
			out[r + 1] = a.y
			by_start["%s|%s" % [a, kind]] = r
		else:
			var r := out.size()
			for k in WALL_STRIDE:
				out.append(walls[o + k])
			by_end["%s|%s" % [b, kind]] = r
			by_start["%s|%s" % [a, kind]] = r
	walls = out
	wall_count = out.size() / WALL_STRIDE


func _split_road_and_hub() -> void:
	road_and_hub = [PackedFloat32Array(), PackedFloat32Array()]
	var a: PackedFloat32Array = road_and_hub[0]
	var b: PackedFloat32Array = road_and_hub[1]
	for i in wall_count:
		var o := i * WALL_STRIDE
		var y0: float = walls[o + 1]
		var y1: float = walls[o + 3]
		if maxf(y0, y1) <= 34.:
			for k in WALL_STRIDE:
				a.append(walls[o + k])
		if minf(y0, y1) >= 33.:
			for k in WALL_STRIDE:
				b.append(walls[o + k])
	road_and_hub = [a, b]


func _build_moving_floors() -> void:
	moving_floors = {}
	var flows: Array = [["creek", 6]]
	if sky == "mill_sky":
		flows.append(["mill_water", 5])
	if sky == "bayou_sky":
		flows.append(["bayou_water", 2])
		flows.append(["bayou_deep", 1])
	for flow: Array in flows:
		var tile := _int(tile_index.get(flow[0], 0))
		var rate := _int(flow[1])
		var heights := {}
		for i in floor_tile.size():
			if floor_tile[i] == tile:
				heights[ground[i]] = true
		for h: float in caps:
			for c: Variant in caps[h]:
				if _int(c[4]) == tile:
					heights[h] = true
		for h: float in heights:
			if not moving_floors.has(h):
				moving_floors[h] = []
			var on_h: Array = moving_floors[h]
			on_h.append([tile, rate])


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
	for index: Dictionary in [near_doors, near_fixtures]:
		for key: Vector2i in index:
			if key.x >= 0 and key.y >= 0 and key.x < width and key.y < height:
				index_cells[key.y * width + key.x] = 1
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
	var key: Array = [at_hub, light_version, locked_gates.size()]
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


## Take a geometry block (format 2): its pieces join the walls, floors and
## overhead surfaces the renderers draw, and the cells it touches are asked
## about collision and sight from now on.
func _take_geometry(block: Variant) -> void:
	if block == null:
		return
	var errors: Array = []
	geo = LevelGeometry.from_json(block, width, height, tile_index, errors)
	for e: Variant in errors:
		push_error("level %s %s" % [id, e])
	if geo == null:
		return
	var parts := geo.render_parts(
		func(x: float, y: float) -> float:
			return elevation(clampf(x, 0.0, width - .001), clampf(y, 0.0, height - .001))
	)
	var more: PackedFloat32Array = parts["walls"]
	walls.append_array(more)
	wall_count = walls.size() / WALL_STRIDE
	for key: Variant in parts["caps"]:
		var h := _f32(_float(key))
		if not caps.has(h):
			caps[h] = []
		var have: Array = caps[h]
		var add: Array = parts["caps"][key]
		have.append_array(add)
		if not ground_heights.has(h):
			ground_heights.append(h)
	for key: Variant in parts["roof_caps"]:
		var h := _f32(_float(key))
		if not roof_caps.has(h):
			roof_caps[h] = []
		var have: Array = roof_caps[h]
		var add: Array = parts["roof_caps"][key]
		have.append_array(add)
		if not roof_heights.has(h):
			roof_heights.append(h)
	slopes = parts["slopes"]


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
