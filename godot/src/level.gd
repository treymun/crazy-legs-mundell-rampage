## Level data for the port, mirroring the Python TileMap structures.
##
## The JSON is produced by tools/export_levels.py from the reference build, so
## this class only has to shuttle it into packed arrays the renderer can read
## without per-pixel dictionary lookups.
class_name LevelData
extends RefCounted

const WALL_STRIDE := 9


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
	var cue := "menu_accept"
	var reveals_secret := false
	var hidden := false
	var action := "use"
	var held := ""


## Mirrors campaign.Extraction.
class Extraction:
	var x := 0.0
	var y := 0.0
	var label := ""
	var shutdown := ""


## Mirrors campaign.Billboard.
class Billboard:
	var x := 0.0
	var y := 0.0
	var image := ""
	var height := 1.0
	var z := 0.0
	var signal_name := ""
	var glow := false
	var plane = NAN
	var back := ""


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

	## Wall segment that closes a locked gate.
	func barrier() -> PackedFloat32Array:
		return PackedFloat32Array(
			[x + width * .5, y, x - width * .5, y, float(closed_tile), 1.08, 0.0, 1.34, 11.0]
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
var doors: Array[Door] = []
var pane_tiles: Array[Vector2i] = []
var fixtures: Array[PackedFloat32Array] = []
var collision_volumes: Array[PackedFloat32Array] = []

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
var broken_panes := {}
var return_gate = null
var extraction = null
var hub_clues: Array = []
var controlled_doors := {}
var access_doors := {}
var crouch_doors := {}
var discovery_rooms := {}
var reinforcements: Array = []
var pressure_ports: Array = []
var boss_decoys: Array = []
var distant_cues: Array = []
var notes: Array = []
var partners: Array = []
var exchanges: Array = []
var ruptures := {}
var recovery_room = null
var hidden_rooms: Array = []
var map_labels: Array = []
var objective_side_tasks: Array = []
var control_name := ""


static func load_level(level_id: String, assets: Assets) -> LevelData:
	var raw := FileAccess.get_file_as_string("res://data/%s.json" % level_id)
	if raw.is_empty():
		push_error("no level data for " + level_id)
		return null
	var j = JSON.parse_string(raw)
	if not (j is Dictionary):
		push_error("bad level json " + level_id)
		return null
	var lv := LevelData.new()
	lv.tile_names = assets.tile_names
	lv.tile_index = assets.tile_index
	lv.id = String(j["id"])
	lv.title = String(j["title"])
	for v in j.get("heading", []):
		lv.heading.append(String(v))
	lv.introduction = String(j.get("intro", ""))
	lv.ending = String(j.get("ending", ""))
	lv.score = String(j.get("score", ""))
	lv.ambience = String(j.get("ambience", ""))
	lv.rescue = bool(j.get("rescue", false))
	lv.spawn = _floats(j["spawn"])
	for v in j.get("districts", []):
		lv.districts.append(String(v))
	lv.width = int(j["width"])
	lv.height = int(j["height"])
	lv.sky = String(j["sky"])
	if j.get("mirror") != null:
		lv.mirror_x = float(j["mirror"][0])

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
			lv.walls[o + k] = float(row[k])

	for d in j.get("doors", []):
		var door := Door.new()
		door.x = int(d["x"])
		door.y = int(d["y"])
		door.style = String(d.get("style", "slide"))
		door.vertical = bool(d.get("vertical", false))
		door.key = String(d.get("key", ""))
		door.secret = bool(d.get("secret", false))
		door.blast_only = bool(d.get("blast_only", false))
		door.progress = float(d.get("progress", 0.))
		door.opened = bool(d.get("opened", false))
		door.discovered = bool(d.get("discovered", false))
		door.texture = String(d.get("texture", ""))
		door.material = int(d.get("material", 0))
		door.id = String(d.get("id", ""))
		lv.doors.append(door)

	for p in j.get("pane_tiles", []):
		lv.pane_tiles.append(Vector2i(int(p[0]), int(p[1])))

	for f in j.get("fixtures", []):
		lv.fixtures.append(_floats(f))
	for f in j.get("collision_volumes", []):
		lv.collision_volumes.append(_floats(f))

	for key in j.get("caps", {}):
		var h := _f32(float(key))
		var list: Array = []
		for c in j["caps"][key]:
			list.append(
				[float(c[0]), float(c[1]), float(c[2]), float(c[3]), lv.tile_id(String(c[4]))]
			)
		lv.caps[h] = list

	lv._build_plane_bounds()

	for g in j.get("hub_gates", []):
		lv.hub_gates.append(_gate(lv, g))
	if j.get("return_gate") != null:
		lv.return_gate = _gate(lv, j["return_gate"])

	lv.enemies = j.get("enemies", [])
	for key in j.get("patrols", {}):
		lv.patrols[int(key)] = j["patrols"][key]
	lv.pickups = j.get("pickups", [])
	lv.props = j.get("props", [])
	for b in j.get("billboards", []):
		var board := Billboard.new()
		board.x = float(b["x"])
		board.y = float(b["y"])
		board.image = String(b["image"])
		board.height = float(b["height"])
		board.z = float(b.get("z", 0.))
		board.signal_name = String(b.get("signal", ""))
		board.glow = bool(b.get("glow", false))
		board.plane = NAN if b.get("plane") == null else float(b["plane"])
		board.back = String(b.get("back", ""))
		lv.billboards.append(board)
	for s in j.get("scenery", []):
		var prop := Scenery.new()
		prop.id = String(s["id"])
		prop.kind = String(s["kind"])
		prop.x = float(s["x"])
		prop.y = float(s["y"])
		prop.height = float(s["height"])
		prop.z = float(s.get("z", 0.))
		prop.radius = float(s.get("radius", .25))
		for p in s.get("opens", []):
			prop.opens.append(Vector2i(int(p[0]), int(p[1])))
		prop.station = String(s.get("station", ""))
		lv.scenery.append(prop)
	lv.fuel_drums = j.get("fuel_drums", [])
	lv.dress_marks = j.get("dress_marks", [])
	for i in j.get("interiors", []):
		var room := Interior.new()
		room.art = String(i[0])
		room.x = float(i[1])
		room.y = float(i[2])
		room.z = float(i[3])
		room.height = float(i[4])
		room.plane = float(i[5])
		lv.interior_art.append(room)

	for s in j.get("stations", []):
		var station := Station.new()
		station.id = String(s["id"])
		station.x = float(s["x"])
		station.y = float(s["y"])
		station.label = String(s.get("label", ""))
		station.message = String(s.get("message", ""))
		station.requires = s.get("requires", [])
		for p in s.get("opens", []):
			station.opens.append(Vector2i(int(p[0]), int(p[1])))
		station.sectors = s.get("sectors", [])
		station.cue = String(s.get("cue", "menu_accept"))
		station.reveals_secret = bool(s.get("reveals_secret", false))
		station.hidden = bool(s.get("hidden", false))
		station.action = String(s.get("action", "use"))
		station.held = String(s.get("held", ""))
		lv.stations.append(station)

	lv.control_name = String(j.get("control_name", ""))
	if j.get("extraction") != null:
		var exit := Extraction.new()
		exit.x = float(j["extraction"]["x"])
		exit.y = float(j["extraction"]["y"])
		exit.label = String(j["extraction"]["label"])
		exit.shutdown = String(j["extraction"]["shutdown"])
		lv.extraction = exit
	for clue in j.get("hub_clues", []):
		lv.hub_clues.append(
			[String(clue[0]), float(clue[1]), float(clue[2]), String(clue[3]), String(clue[4])]
		)
	for point in j.get("pressure_ports", []):
		lv.pressure_ports.append(Vector2(float(point[0]), float(point[1])))
	for point in j.get("boss_decoys", []):
		lv.boss_decoys.append(Vector2(float(point[0]), float(point[1])))
	for cue in j.get("distant_cues", []):
		lv.distant_cues.append([float(cue[0]), float(cue[1]), String(cue[2])])
	for n in j.get("notes", []):
		var note := Note.new()
		note.x = float(n[0])
		note.y = float(n[1])
		note.label = String(n[2])
		note.text = String(n[3])
		note.plane = float(n[4]) if n.size() > 4 else 0.0
		lv.notes.append(note)
	for n in j.get("partners", []):
		lv.partners.append([String(n[0]), String(n[1]), int(n[2])])
	for n in j.get("exchanges", []):
		var exchange := Exchange.new()
		exchange.id = String(n["id"])
		exchange.x = float(n["x"])
		exchange.y = float(n["y"])
		exchange.stop_at = String(n.get("stop_at", ""))
		exchange.lines = n.get("lines", [])
		lv.exchanges.append(exchange)
	lv.ruptures = {}
	for key in j.get("ruptures", {}):
		var rup: Array = j["ruptures"][key]
		lv.ruptures[String(key)] = [float(rup[0]), float(rup[1]), String(rup[2])]
	if j.get("recovery_room") != null:
		var rec: Array = j["recovery_room"]
		lv.recovery_room = [
			float(rec[0]), float(rec[1]), float(rec[2]), float(rec[3]), String(rec[4])
		]
	lv.objective_side_tasks = j.get("objective_side_tasks", [])
	for point in j.get("controlled_doors", []):
		lv.controlled_doors[Vector2i(int(point[0]), int(point[1]))] = true
	for point in j.get("crouch_doors", []):
		lv.crouch_doors[Vector2i(int(point[0]), int(point[1]))] = true
	lv.access_doors = {}
	for key in j.get("access_doors", {}):
		var parts := String(key).split(",")
		lv.access_doors[Vector2i(int(parts[0]), int(parts[1]))] = j["access_doors"][key]
	lv.discovery_rooms = {}
	for key in j.get("discovery_rooms", {}):
		var pair := String(key).split(",")
		lv.discovery_rooms[Vector2i(int(pair[0]), int(pair[1]))] = j["discovery_rooms"][key]
	lv.reinforcements = j.get("reinforcements", [])
	for room in j.get("hidden_rooms", []):
		lv.hidden_rooms.append(
			[
				Vector2i(int(room[0][0]), int(room[0][1])),
				Vector4i(int(room[1][0]), int(room[1][1]), int(room[1][2]), int(room[1][3]))
			]
		)
	for label in j.get("map_labels", []):
		lv.map_labels.append([String(label[0]), int(label[1]), int(label[2])])
	lv._build_indexes()

	if not lv.hub_gates.is_empty():
		lv._split_road_and_hub()
	lv._build_moving_floors()
	return lv


static func _gate(lv: LevelData, g: Dictionary) -> Gate:
	var gate := Gate.new()
	gate.destination = String(g["destination"])
	gate.x = float(g["x"])
	gate.y = float(g["y"])
	gate.width = float(g.get("width", 3.8))
	gate.side = int(g.get("side", 1))
	gate.closed_tile = lv.tile_id("route_closed")
	return gate


static func _ints(values: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(values.size())
	for i in values.size():
		out[i] = int(values[i])
	return out


static func _floats(values: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(values.size())
	for i in values.size():
		out[i] = float(values[i])
	return out


static func _floats2(rows: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(rows.size() * 3)
	for i in rows.size():
		var row: Array = rows[i]
		out[i * 3] = float(row[0])
		out[i * 3 + 1] = float(row[1])
		out[i * 3 + 2] = float(row[2])
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
		var b = buckets.get(h)
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
	for height in heights:
		var b = buckets.get(height)
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
		for c in extra:
			x0 = mini(x0, int(c[0]))
			y0 = mini(y0, int(c[1]))
			x1 = maxi(x1, int(ceil(c[2])))
			y1 = maxi(y1, int(ceil(c[3])))
		floor_bounds[height] = Vector4i(x0, y0, x1, y1)

	var roof_buckets := {}
	for i in roof.size():
		var h := roof[i]
		if h <= 0.0:
			continue
		var y := i / width
		var x := i - y * width
		var b = roof_buckets.get(h)
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
	for height in rheight:
		var b = roof_buckets.get(height)
		if b != null:
			roof_bounds[height] = Vector4i(b[0], b[1], b[2], b[3])
	floor_boxes = _tight_boxes(floor_bounds, ground, caps)
	roof_boxes = _tight_boxes(roof_bounds, roof, {})


## The planes the renderer walks: [height, box] in the bounds' order. A height
## whose cells are scattered across a big box (a creek, a few porch roofs) is
## cut into tight boxes, so the pixels between them are not tested for it.
func _tight_boxes(bounds: Dictionary, grid: PackedFloat32Array, capped: Dictionary) -> Array:
	var out: Array = []
	for h in bounds:
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
	for flow in flows:
		var tile := int(tile_index.get(flow[0], 0))
		var rate := int(flow[1])
		var heights := {}
		for i in floor_tile.size():
			if floor_tile[i] == tile:
				heights[ground[i]] = true
		for h in caps:
			for c in caps[h]:
				if int(c[4]) == tile:
					heights[h] = true
		for h in heights:
			if not moving_floors.has(h):
				moving_floors[h] = []
			moving_floors[h].append([tile, rate])


func tile_id(name: String) -> int:
	return int(tile_index.get(name, -1))


## engine.IMPACT_MATERIAL: detail-wall tiles report their base surface.
const DETAIL_BASES := {
	"bar_wainscot": "tavern",
	"garage_courses": "brick",
	"feed_pen_boards": "barn",
	"raffle_stripes": "fair_booth",
	"prize_skirting": "fair_prize",
	"kiln_patches": "mill_tin",
	"rain_sheets": "mill_tin",
	"shed_repair": "mill_tin",
	"chalk_cut": "quarry_face",
	"copper_seams": "quarry_copper",
	"approach_fence": "stockyard",
}

const METAL_TILES := [
	"tin",
	"ship",
	"steel_mesh",
	"fair_iron",
	"fair_gate",
	"mill_tin",
	"mill_pump",
	"quarry_iron",
	"quarry_copper",
	"hub_tank_shell",
	"powder_panel"
]
const PLASTER_TILES := [
	"plaster", "brick", "cinder", "tile", "concrete", "quarry_face", "office_wall", "tavern"
]
const DIRT_TILES := [
	"dirt",
	"grass",
	"orchard",
	"tracks",
	"shoulder",
	"gravel",
	"quarry_dust",
	"mill_grit",
	"fair_gravel",
	"creek",
	"asphalt",
	"road",
	"oil_asphalt"
]

## Sound cue per floor surface; anything else is gravel.
const SURFACE_SOUNDS := {
	"porch": "wood",
	"floor_tile": "tile",
	"concrete": "tile",
	"dirt": "mud",
	"tracks": "mud",
	"shoulder": "mud",
	"grass": "grass",
	"orchard": "grass",
	"creek": "water",
	"mill_water": "water",
	"fair_gravel": "gravel",
	"mill_grit": "gravel",
	"quarry_dust": "gravel",
	"quarry_face": "gravel",
	"route_threshold": "gravel",
}

var _impact_surfaces := {}


## Mirrors engine.impact_surface(): the surface kind for a tile id.
func impact_surface(tile: int) -> String:
	if _impact_surfaces.is_empty():
		for name in METAL_TILES:
			_impact_surfaces[tile_id(name)] = "metal"
		for name in PLASTER_TILES:
			_impact_surfaces[tile_id(name)] = "plaster"
		for name in DIRT_TILES:
			_impact_surfaces[tile_id(name)] = "dirt"
		for name in DETAIL_BASES:
			_impact_surfaces[tile_id(name)] = _impact_surfaces.get(
				tile_id(DETAIL_BASES[name]), "wood"
			)
	var kind = _impact_surfaces.get(tile)
	return "wood" if kind == null else String(kind)


## Mirrors SURFACE_SOUNDS.get(floor, "gravel") using the tile id.
func surface_sound(tile: int) -> String:
	var name := String(tile_names[tile]) if tile >= 0 and tile < tile_names.size() else ""
	return String(SURFACE_SOUNDS.get(name, "gravel"))


## Mirrors TileMap.finish_geometry's spatial indexes (near_doors, near_fixtures).
func _build_indexes() -> void:
	near_doors = {}
	for door in doors:
		for yy in range(door.y - 1, door.y + 2):
			for xx in range(door.x - 1, door.x + 2):
				var key := Vector2i(xx, yy)
				if not near_doors.has(key):
					near_doors[key] = []
				near_doors[key].append(door)
	near_fixtures = {}
	for fixture in collision_volumes:
		var fx0 := int(floor(fixture[0] - index_radius))
		var fy0 := int(floor(fixture[1] - index_radius))
		var fx1 := int(floor(fixture[2] + index_radius))
		var fy1 := int(floor(fixture[3] + index_radius))
		for yy in range(fy0, fy1 + 1):
			for xx in range(fx0, fx1 + 1):
				var key := Vector2i(xx, yy)
				if not near_fixtures.has(key):
					near_fixtures[key] = []
				near_fixtures[key].append(fixture)


## Mirrors TileMap.blocked().
func blocked(x: float, y: float, radius := 0.0, z = null) -> bool:
	for step in 4:
		var dx := -radius if step < 2 else radius
		var dy := -radius if step % 2 == 0 else radius
		var ix := int(x + dx)
		var iy := int(y + dy)
		if ix < 0 or iy < 0 or ix >= width or iy >= height:
			return true
		if solid[iy * width + ix] >= 0:
			return true
	if pane_at(x, y, z, radius) != null:
		return true
	for gate: Gate in locked_gates:
		if absf(y - gate.y) < radius + .09 and absf(x - gate.x) < gate.width * .5 + radius:
			return true
	var tile := Vector2i(int(x), int(y))
	var fixtures: Array = (
		near_fixtures.get(tile, []) if radius <= index_radius else collision_volumes
	)
	for fixture in fixtures:
		var f: PackedFloat32Array = fixture
		if (
			f[0] - radius < x
			and x < f[2] + radius
			and f[1] - radius < y
			and y < f[3] + radius
			and (z == null or (f[7] - radius < float(z) and float(z) < f[4] + radius))
		):
			return true
	for door in near_doors.get(tile, []):
		var d: Door = door
		if d.blocks(x, y, radius):
			return true
	return false


## Mirrors TileMap.pane_at(); returns the pane cell or null.
func pane_at(x: float, y: float, z = null, radius := 0.0):
	for pane in pane_tiles:
		if broken_panes.has(pane):
			continue
		if (
			float(pane.x) - radius < x
			and x < float(pane.x) + 1.0 + radius
			and absf(y - float(pane.y) - .5) < radius + .044
			and (z == null or (.30 < float(z) and float(z) < 1.83))
		):
			return pane
	return null


## Mirrors TileMap.visible(): a stepped line-of-sight test.
func visible(x: float, y: float, xx: float, yy: float, z = null, zz = null) -> bool:
	var distance := sqrt((xx - x) * (xx - x) + (yy - y) * (yy - y))
	var n := maxi(1, int(ceil(distance * 9.0)))
	for i in range(1, n):
		var t := float(i) / float(n)
		var wz = null
		if z != null:
			wz = float(z) + (float(zz) - float(z)) * t
		if blocked(x + (xx - x) * t, y + (yy - y) * t, .023, wz):
			return false
	return true


## Mirrors TileMap.move(): axis-separated with a step-height limit.
func move(body, dx: float, dy: float, radius: float, occupied = null) -> void:
	var start_x: float = body.x
	var start_y: float = body.y
	if _can_walk(body, start_x + dx, start_y, radius, occupied):
		body.x += dx
	if _can_walk(body, body.x, start_y + dy, radius, occupied):
		body.y += dy


func _can_walk(body, x: float, y: float, radius: float, occupied) -> bool:
	if blocked(x, y, radius):
		return false
	if occupied != null and occupied.call(x, y):
		return false
	if not ("air" in body):
		return true
	var up := elevation(x, y) - elevation(body.x, body.y)
	return up <= .245 + float(body.air)


## Mirrors TileMap.update(): doors slide open/closed, blocked by live enemies.
func update(dt: float, player, enemies: Array) -> void:
	for door in doors:
		if (door.opened and door.progress >= 1.0) or (not door.opened and door.progress <= 0.0):
			continue
		var centre := door.center()
		if (
			not door.opened
			and (
				sqrt(
					(
						(player.x - centre.x) * (player.x - centre.x)
						+ (player.y - centre.y) * (player.y - centre.y)
					)
				)
				< .8
			)
		):
			continue
		var direction := 1.0 if door.opened else -1.0
		var previous := door.progress
		door.progress = maxf(0.0, minf(1.0, door.progress + dt * 1.65 * direction))
		if not door.opened:
			for enemy in enemies:
				if enemy.alive and door.blocks(enemy.x, enemy.y, enemy.radius):
					door.progress = previous
					break


func elevation(x: float, y: float) -> float:
	return ground[int(y) * width + int(x)]


func cell(x: float, y: float) -> int:
	return int(y) * width + int(x)


## Wall segments drawn this frame: static walls (or the hub split) plus doors,
## panes and locked gate barriers, matching Renderer.draw / door_walls().
func active_walls(at_hub: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if at_hub and not road_and_hub.is_empty():
		out = road_and_hub[1].duplicate()
		for gate: Gate in locked_gates:
			out.append_array(gate.barrier())
	else:
		if road_and_hub.is_empty():
			out = walls
		else:
			out = road_and_hub[0]
		out = out.duplicate()
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
			out.append(float(tile_index.get("glazing", 0)))
			out.append(.98)
			out.append(.36)
			out.append(1.78)
			out.append(1.0)
	return out
