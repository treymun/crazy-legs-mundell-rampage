## Reading a level, moved out of level.gd: a level file's contents into a
## LevelData (from_dict(), with its gates and packed lists), the floor and
## roof planes' bounds and tight boxes the renderer walks, the walls' runs
## merged, the road and hub split, the moving floors and the geometry block.
## LevelData.load_level() and from_dict() hand on to it.
class_name LevelLoad
extends RefCounted


## Mirrors Renderer.plane_bounds, but gathers every bbox in one pass over cells
## instead of rescanning the grid per height.
static func build_plane_bounds(lv: LevelData) -> void:
	var counts := {}
	var buckets := buckets(lv.ground, lv.width, false, counts)
	lv.floor_bounds = {}
	# Python inserts floors nearest-first (reversed sorted heights).
	var heights := Array(lv.ground_heights)
	heights.sort()
	heights.reverse()
	for height: float in heights:
		var b: Variant = buckets.get(height)
		var extra: Array = lv.caps.get(height, [])
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
			x0 = mini(x0, LevelData._int(c[0]))
			y0 = mini(y0, LevelData._int(c[1]))
			x1 = maxi(x1, LevelData._int(ceil(c[2])))
			y1 = maxi(y1, LevelData._int(ceil(c[3])))
		lv.floor_bounds[height] = Vector4i(x0, y0, x1, y1)

	var roof_counts := {}
	var roof_buckets := buckets(lv.roof, lv.width, true, roof_counts)
	lv.roof_bounds = {}
	var rheight := Array(lv.roof_heights)
	rheight.sort()
	for height: float in rheight:
		var b: Variant = roof_buckets.get(height)
		var over: Array = lv.roof_caps.get(height, [])
		if b == null and over.is_empty():
			continue
		var r := Vector4i(1 << 30, 1 << 30, -(1 << 30), -(1 << 30))
		if b != null:
			r = Vector4i(
				LevelData._int(b[0]),
				LevelData._int(b[1]),
				LevelData._int(b[2]),
				LevelData._int(b[3])
			)
		for c: Variant in over:
			r = Vector4i(
				mini(r.x, LevelData._int(c[0])),
				mini(r.y, LevelData._int(c[1])),
				maxi(r.z, LevelData._int(ceil(c[2]))),
				maxi(r.w, LevelData._int(ceil(c[3])))
			)
		lv.roof_bounds[height] = r
	lv.floor_boxes = tight_boxes(lv.floor_bounds, lv.ground, lv.width, lv.height, lv.caps, counts)
	lv.roof_boxes = tight_boxes(
		lv.roof_bounds, lv.roof, lv.width, lv.height, lv.roof_caps, roof_counts
	)


## Each height's cells' bounds in `grid` (h -> [x0, y0, x1, y1]; none at or
## below 0 when `skip_low`), and how many cells have it (`counts`), a row's
## run of one height at a time.
static func buckets(
	grid: PackedFloat32Array, width: int, skip_low: bool, counts: Dictionary
) -> Dictionary:
	var buckets := {}
	var n := grid.size()
	var i := 0
	while i < n:
		var h := grid[i]
		var y := i / width
		var row_end := mini(n, (y + 1) * width)
		var j := i + 1
		while j < row_end and grid[j] == h:
			j += 1
		if not (skip_low and h <= 0.0):
			var x0 := i - y * width
			var x1 := j - y * width
			var b: Variant = buckets.get(h)
			if b == null:
				buckets[h] = [x0, y, x1, y + 1]
				counts[h] = j - i
			else:
				if x0 < b[0]:
					b[0] = x0
				if y < b[1]:
					b[1] = y
				if x1 > b[2]:
					b[2] = x1
				if y + 1 > b[3]:
					b[3] = y + 1
				counts[h] += j - i
		i = j
	return buckets


## The planes the renderer walks: [height, box] in the bounds' order. A height
## whose cells are scattered across a big box (a creek, a few porch roofs) is
## cut into tight boxes, so the pixels between them are not tested for it.
## `counts`: how many cells of a height there are (all inside its box), where
## known (_buckets).
static func tight_boxes(
	bounds: Dictionary,
	grid: PackedFloat32Array,
	width: int,
	height: int,
	capped: Dictionary,
	counts: Dictionary
) -> Array:
	var out: Array = []
	for h: float in bounds:
		var box: Vector4i = bounds[h]
		var area := (box.z - box.x) * (box.w - box.y)
		var count: int = counts.get(h, -1)
		if count < 0:
			count = 0
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
static func merge_runs(lv: LevelData) -> void:
	var tiled := {}
	for name: String in LevelTiles.TILED:
		if lv.tile_index.has(name):
			tiled[LevelData._int(lv.tile_index[name])] = true
	var out := PackedFloat32Array()
	var by_end := {}
	var by_start := {}
	# The walls read through a local (only `out` is written; lv.walls after).
	var walls := lv.walls
	for i in lv.wall_count:
		var o := i * LevelData.WALL_STRIDE
		var a := Vector2(walls[o], walls[o + 1])
		var b := Vector2(walls[o + 2], walls[o + 3])
		var step := b - a
		var whole := a == a.floor() and b == b.floor() and (step.x == 0.0 or step.y == 0.0)
		if not tiled.has(int(walls[o + 4])) or not whole or step == Vector2.ZERO:
			for k in LevelData.WALL_STRIDE:
				out.append(walls[o + k])
			continue
		# (Keys as text, as they always were: str() of each, joined.)
		var kind := (
			str(step.normalized())
			+ "|"
			+ str(walls[o + 4])
			+ "|"
			+ str(walls[o + 5])
			+ "|"
			+ str(walls[o + 6])
			+ "|"
			+ str(walls[o + 7])
			+ "|"
			+ str(walls[o + 8])
		)
		var after := str(a) + "|" + kind
		var before := str(b) + "|" + kind
		if by_end.has(after):
			# This piece carries on from the end of a run: the run reaches b.
			var r: int = by_end[after]
			by_end.erase(after)
			out[r + 2] = b.x
			out[r + 3] = b.y
			by_end[before] = r
		elif by_start.has(before):
			# A run starts where this piece ends: the run starts at a now.
			var r: int = by_start[before]
			by_start.erase(before)
			out[r] = a.x
			out[r + 1] = a.y
			by_start[after] = r
		else:
			var r := out.size()
			for k in LevelData.WALL_STRIDE:
				out.append(walls[o + k])
			by_end[before] = r
			by_start[after] = r
	lv.walls = out
	lv.wall_count = out.size() / LevelData.WALL_STRIDE


static func split_road_and_hub(lv: LevelData) -> void:
	lv.road_and_hub = [PackedFloat32Array(), PackedFloat32Array()]
	var a: PackedFloat32Array = lv.road_and_hub[0]
	var b: PackedFloat32Array = lv.road_and_hub[1]
	var walls := lv.walls
	for i in lv.wall_count:
		var o := i * LevelData.WALL_STRIDE
		var y0: float = walls[o + 1]
		var y1: float = walls[o + 3]
		if maxf(y0, y1) <= 34.:
			for k in LevelData.WALL_STRIDE:
				a.append(walls[o + k])
		if minf(y0, y1) >= 33.:
			for k in LevelData.WALL_STRIDE:
				b.append(walls[o + k])
	lv.road_and_hub = [a, b]


static func build_moving_floors(lv: LevelData) -> void:
	lv.moving_floors = {}
	var flows: Array = [["creek", 6]]
	if lv.sky == "mill_sky":
		flows.append(["mill_water", 5])
	if lv.sky == "bayou_sky":
		flows.append(["bayou_water", 2])
		flows.append(["bayou_deep", 1])
	for flow: Array in flows:
		var tile := LevelData._int(lv.tile_index.get(flow[0], 0))
		var rate := LevelData._int(flow[1])
		var heights := {}
		var floor_tile := lv.floor_tile
		var ground := lv.ground
		for i in floor_tile.size():
			if floor_tile[i] == tile:
				heights[ground[i]] = true
		for h: float in lv.caps:
			for c: Variant in lv.caps[h]:
				if LevelData._int(c[4]) == tile:
					heights[h] = true
		for h: float in heights:
			if not lv.moving_floors.has(h):
				lv.moving_floors[h] = []
			var on_h: Array = lv.moving_floors[h]
			on_h.append([tile, rate])


## Take a geometry block (format 2): its pieces join the walls, floors and
## overhead surfaces the renderers draw, and the cells it touches are asked
## about collision and sight from now on.
static func take_geometry(lv: LevelData, block: Variant) -> void:
	if block == null:
		return
	var errors: Array = []
	lv.geo = LevelGeometry.from_json(block, lv.width, lv.height, lv.tile_index, errors)
	for e: Variant in errors:
		push_error("level %s %s" % [lv.id, e])
	if lv.geo == null:
		return
	var parts := lv.geo.render_parts(
		func(x: float, y: float) -> float:
			return lv.elevation(clampf(x, 0.0, lv.width - .001), clampf(y, 0.0, lv.height - .001))
	)
	var more: PackedFloat32Array = parts["walls"]
	lv.walls.append_array(more)
	lv.wall_count = lv.walls.size() / LevelData.WALL_STRIDE
	for key: Variant in parts["caps"]:
		var h := f32(LevelData._float(key))
		if not lv.caps.has(h):
			lv.caps[h] = []
		var have: Array = lv.caps[h]
		var add: Array = parts["caps"][key]
		have.append_array(add)
		if not lv.ground_heights.has(h):
			lv.ground_heights.append(h)
	for key: Variant in parts["roof_caps"]:
		var h := f32(LevelData._float(key))
		if not lv.roof_caps.has(h):
			lv.roof_caps[h] = []
		var have: Array = lv.roof_caps[h]
		var add: Array = parts["roof_caps"][key]
		have.append_array(add)
		if not lv.roof_heights.has(h):
			lv.roof_heights.append(h)
	lv.slopes = parts["slopes"]


## A level from its file's contents (load_level; the map tools check one
## before it is written).
static func from_dict(j: Dictionary, assets: Assets) -> LevelData:
	var lv := LevelData.new()
	lv.format = LevelData._int(j.get("format", 1))
	if lv.format > LevelData.FORMAT:
		push_error(
			(
				"level %s is format %d, newer than this build (%d)"
				% [j["id"], lv.format, LevelData.FORMAT]
			)
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
	lv.spawn = floats(j["spawn"])
	for v: Variant in j.get("districts", []):
		lv.districts.append(str(v))
	lv.width = LevelData._int(j["width"])
	lv.height = LevelData._int(j["height"])
	lv.sky = str(j["sky"])
	if j.get("mirror") != null:
		lv.mirror_x = LevelData._float(j["mirror"][0])

	lv.solid = ints(j["solid"])
	lv.floor_tile = ints(j["floor"])
	lv.ceiling_tile = ints(j["ceiling"])
	lv.ground = floats(j["ground"])
	lv.roof = floats(j["roof"])
	lv.wall_height = floats(j["wall_height"])
	lv.light = floats(j["light"])
	lv.area = ints(j["area"])
	lv.tints = floats2(j["tints"])

	lv.ground_heights = floats(j["ground_heights"])
	lv.roof_heights = floats(j["roof_heights"])

	var wall_list: Array = j["walls"]
	lv.wall_count = wall_list.size()
	for i in lv.wall_count:
		var row := floats(wall_list[i])
		if row.size() != LevelData.WALL_STRIDE:
			row.resize(LevelData.WALL_STRIDE)
		lv.walls.append_array(row)

	if not j.get("hub_split", false):
		merge_runs(lv)

	for d: Dictionary in j.get("doors", []):
		var door := LevelData.Door.new()
		door.x = LevelData._int(d["x"])
		door.y = LevelData._int(d["y"])
		door.style = str(d.get("style", "slide"))
		door.vertical = d.get("vertical", false)
		door.key = str(d.get("key", ""))
		door.secret = d.get("secret", false)
		door.blast_only = d.get("blast_only", false)
		door.progress = LevelData._float(d.get("progress", 0.))
		door.opened = d.get("opened", false)
		door.discovered = d.get("discovered", false)
		door.texture = str(d.get("texture", ""))
		door.material = LevelData._int(d.get("material", 0))
		door.id = str(d.get("id", ""))
		door.bar_side = LevelLoad.bar_side(str(d.get("bar_side", "")), door.vertical)
		if d.has("z") or d.has("span"):
			# Pass 16 (T4 WAYS): a door up on a storey, a door wider than a cell.
			var wrong := LevelLoad.door_ways(door, d)
			if wrong != "":
				push_error("level %s door %d,%d: %s" % [lv.id, door.x, door.y, wrong])
		lv.doors.append(door)

	for p: Variant in j.get("pane_tiles", []):
		lv.pane_tiles.append(Vector2i(LevelData._int(p[0]), LevelData._int(p[1])))
	for p: Variant in j.get("geo_panes", []):
		var pane := LevelLoad.geo_pane(p)
		if pane == null:
			push_error("level %s: a geo pane is {a: [x, y], b: [x, y], z0, z1}" % lv.id)
		else:
			lv.geo_panes.append(pane)

	for f: Array in j.get("fixtures", []):
		lv.fixtures.append(floats(f))
	for f: Array in j.get("collision_volumes", []):
		lv.collision_volumes.append(floats(f))

	for key: Variant in j.get("caps", {}):
		var h := f32(LevelData._float(key))
		var list: Array = []
		for c: Variant in j["caps"][key]:
			list.append(
				[
					LevelData._float(c[0]),
					LevelData._float(c[1]),
					LevelData._float(c[2]),
					LevelData._float(c[3]),
					lv.tile_id(str(c[4]))
				]
			)
		lv.caps[h] = list

	take_geometry(lv, j.get("geometry"))
	build_plane_bounds(lv)

	for g: Dictionary in j.get("hub_gates", []):
		lv.hub_gates.append(gate(lv, g))
	if j.get("return_gate") != null:
		var back: Dictionary = j["return_gate"]
		lv.return_gate = gate(lv, back)

	lv.enemies = j.get("enemies", [])
	for key: Variant in j.get("patrols", {}):
		lv.patrols[LevelData._int(key)] = j["patrols"][key]
	lv.pickups = j.get("pickups", [])
	lv.props = j.get("props", [])
	for b: Dictionary in j.get("billboards", []):
		var board := LevelData.Billboard.new()
		board.x = LevelData._float(b["x"])
		board.y = LevelData._float(b["y"])
		board.image = str(b["image"])
		board.height = LevelData._float(b["height"])
		board.z = LevelData._float(b.get("z", 0.))
		board.signal_name = str(b.get("signal", ""))
		board.glow = b.get("glow", false)
		board.plane = NAN if b.get("plane") == null else LevelData._float(b["plane"])
		board.back = str(b.get("back", ""))
		lv.billboards.append(board)
	for s: Dictionary in j.get("scenery", []):
		var prop := LevelData.Scenery.new()
		prop.id = str(s["id"])
		prop.kind = str(s["kind"])
		prop.x = LevelData._float(s["x"])
		prop.y = LevelData._float(s["y"])
		prop.height = LevelData._float(s["height"])
		prop.z = LevelData._float(s.get("z", 0.))
		prop.radius = LevelData._float(s.get("radius", .25))
		for p: Variant in s.get("opens", []):
			prop.opens.append(Vector2i(LevelData._int(p[0]), LevelData._int(p[1])))
		prop.station = str(s.get("station", ""))
		lv.scenery.append(prop)
	lv.fuel_drums = j.get("fuel_drums", [])
	lv.dress_marks = j.get("dress_marks", [])
	for i: Variant in j.get("interiors", []):
		var room := LevelData.Interior.new()
		room.art = str(i[0])
		room.x = LevelData._float(i[1])
		room.y = LevelData._float(i[2])
		room.z = LevelData._float(i[3])
		room.height = LevelData._float(i[4])
		room.plane = LevelData._float(i[5])
		lv.interior_art.append(room)

	for s: Dictionary in j.get("stations", []):
		var station := LevelData.Station.new()
		station.id = str(s["id"])
		station.x = LevelData._float(s["x"])
		station.y = LevelData._float(s["y"])
		station.label = str(s.get("label", ""))
		station.message = str(s.get("message", ""))
		station.requires = s.get("requires", [])
		for p: Variant in s.get("opens", []):
			station.opens.append(Vector2i(LevelData._int(p[0]), LevelData._int(p[1])))
		station.sectors = s.get("sectors", [])
		station.cue = str(s.get("cue", "lever_clunk"))
		station.reveals_secret = s.get("reveals_secret", false)
		station.hidden = s.get("hidden", false)
		station.action = str(s.get("action", "use"))
		station.held = str(s.get("held", ""))
		station.z = LevelData._float(s["z"]) if s.has("z") else NAN
		lv.stations.append(station)

	lv.control_name = str(j.get("control_name", ""))
	lv.layout = LevelData._int(j.get("layout", 1))
	if j.get("hub_board") != null:
		lv.hub_board = Vector2(
			LevelData._float(j["hub_board"][0]), LevelData._float(j["hub_board"][1])
		)
	lv.map_window = j.get("map_window", [])
	if j.get("gallery") != null:
		lv.gallery_stand = Vector2(
			LevelData._float(j["gallery"][0]), LevelData._float(j["gallery"][1])
		)
	for d: Variant in j.get("devices", []):
		lv.devices.append([str(d[0]), LevelData._float(d[1]), LevelData._float(d[2])])
	if j.has("area_sounds"):
		lv.area_sounds = {}
		for key: Variant in j["area_sounds"]:
			lv.area_sounds[LevelData._int(key)] = str(j["area_sounds"][key])
	for key: Variant in j.get("area_cues", {}):
		lv.area_cues[LevelData._int(key)] = str(j["area_cues"][key])
	if j.get("extraction") != null:
		var ex: Dictionary = j["extraction"]
		var exit := LevelData.Extraction.new()
		exit.x = LevelData._float(j["extraction"]["x"])
		exit.y = LevelData._float(j["extraction"]["y"])
		exit.label = str(j["extraction"]["label"])
		exit.shutdown = str(j["extraction"]["shutdown"])
		exit.z = LevelData._float(ex.get("z", NAN))
		lv.extraction = exit
	for clue: Variant in j.get("hub_clues", []):
		lv.hub_clues.append(
			[
				str(clue[0]),
				LevelData._float(clue[1]),
				LevelData._float(clue[2]),
				str(clue[3]),
				str(clue[4])
			]
		)
	for point: Variant in j.get("pressure_ports", []):
		lv.pressure_ports.append(Vector2(LevelData._float(point[0]), LevelData._float(point[1])))
	var laps: Variant = j.get("lap_cars", {})
	lv.lap_cars = laps if laps is Dictionary else {}
	lv.vehicles = j.get("vehicles", []) if j.get("vehicles", []) is Array else []
	var breaks: Variant = j.get("set_pieces", [])
	lv.set_pieces = breaks if breaks is Array else []
	var runs: Variant = j.get("vehicle_runs", [])
	lv.vehicle_runs = runs if runs is Array else []
	var lines: Variant = j.get("vehicle_lines", {})
	lv.vehicle_lines = lines if lines is Dictionary else {}
	for point: Variant in j.get("boss_decoys", []):
		lv.boss_decoys.append(Vector2(LevelData._float(point[0]), LevelData._float(point[1])))
	var arena: Variant = j.get("boss_arena", {})
	lv.boss_arena = arena if arena is Dictionary else {}
	var plan: Variant = j.get("tactical", {})
	lv.tactical = plan if plan is Dictionary else {}
	for cue: Variant in j.get("distant_cues", []):
		lv.distant_cues.append([LevelData._float(cue[0]), LevelData._float(cue[1]), str(cue[2])])
	for n: Array in j.get("notes", []):
		var note := LevelData.Note.new()
		note.x = LevelData._float(n[0])
		note.y = LevelData._float(n[1])
		note.label = str(n[2])
		note.text = str(n[3])
		note.plane = LevelData._float(n[4]) if n.size() > 4 else 0.0
		lv.notes.append(note)
	for n: Variant in j.get("partners", []):
		lv.partners.append([str(n[0]), str(n[1]), LevelData._int(n[2])])
	for trigger: Variant in j.get("triggers", []):
		var td: Dictionary = trigger if trigger is Dictionary else {}
		if td.has("id"):
			lv.triggers.append(trigger)
	for n: Dictionary in j.get("exchanges", []):
		var exchange := LevelData.Exchange.new()
		exchange.id = str(n["id"])
		exchange.x = LevelData._float(n["x"])
		exchange.y = LevelData._float(n["y"])
		exchange.stop_at = str(n.get("stop_at", ""))
		exchange.lines = n.get("lines", [])
		lv.exchanges.append(exchange)
	lv.ruptures = {}
	for key: Variant in j.get("ruptures", {}):
		var rup: Array = j["ruptures"][key]
		lv.ruptures[str(key)] = [LevelData._float(rup[0]), LevelData._float(rup[1]), str(rup[2])]
	if j.get("recovery_room") != null:
		var rec: Array = j["recovery_room"]
		lv.recovery_room = [
			LevelData._float(rec[0]),
			LevelData._float(rec[1]),
			LevelData._float(rec[2]),
			LevelData._float(rec[3]),
			str(rec[4])
		]
	lv.objective_side_tasks = j.get("objective_side_tasks", [])
	for point: Variant in j.get("controlled_doors", []):
		lv.controlled_doors[Vector2i(LevelData._int(point[0]), LevelData._int(point[1]))] = true
	for point: Variant in j.get("crouch_doors", []):
		lv.crouch_doors[Vector2i(LevelData._int(point[0]), LevelData._int(point[1]))] = true
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
				Vector2i(LevelData._int(room[0][0]), LevelData._int(room[0][1])),
				Vector4i(
					LevelData._int(room[1][0]),
					LevelData._int(room[1][1]),
					LevelData._int(room[1][2]),
					LevelData._int(room[1][3])
				)
			]
		)
	for label: Variant in j.get("map_labels", []):
		lv.map_labels.append([str(label[0]), LevelData._int(label[1]), LevelData._int(label[2])])
	lv._build_indexes()

	if j.get("hub_split", false):
		split_road_and_hub(lv)
	build_moving_floors(lv)
	lv.deep_tile = lv.tile_id("bayou_deep")
	return lv


static func gate(lv: LevelData, g: Dictionary) -> LevelData.Gate:
	var gate := LevelData.Gate.new()
	gate.destination = str(g["destination"])
	gate.x = LevelData._float(g["x"])
	gate.y = LevelData._float(g["y"])
	gate.width = LevelData._float(g.get("width", 3.8))
	gate.side = LevelData._int(g.get("side", 1))
	gate.closed_tile = lv.tile_id("route_closed")
	return gate


## A door's "z" (the floor it stands on, 0 to 100) and "span" (1 to 3 cells)
## onto `door`; what is wrong with them ("" when nothing is: a wrong value is
## left as a door on the ground one cell wide).
static func door_ways(door: LevelData.Door, d: Dictionary) -> String:
	var z: Variant = d.get("z", 0.0)
	var span: Variant = d.get("span", 1)
	if not (z is float or z is int) or not (span is float or span is int):
		return "z and span are numbers"
	var zf: float = z
	var sf: float = span
	if zf < 0.0 or zf > 100.0:
		return "z is 0 to 100"
	if sf != floorf(sf) or sf < 1.0 or sf > 3.0:
		return "span is 1, 2 or 3 cells"
	if zf != 0.0:
		door.z = snappedf(zf, .001)
	door.span = int(sf)
	return ""


## A geometry pane from the level file ({a, b, z0, z1}), or null when it is
## not one (a side under .05 or over 16, heights out of order).
static func geo_pane(p: Variant) -> LevelData.GeoPane:
	if not (p is Dictionary):
		return null
	var d: Dictionary = p
	var a_at: Variant = d.get("a")
	var b_at: Variant = d.get("b")
	if not (a_at is Array and b_at is Array):
		return null
	var a: Array = a_at
	var b: Array = b_at
	if a.size() != 2 or b.size() != 2:
		return null
	for v: Variant in [a[0], a[1], b[0], b[1], d.get("z0", .9), d.get("z1", 1.9)]:
		if not (v is float or v is int):
			return null
	var pane := LevelData.GeoPane.new()
	pane.ax = a[0]
	pane.ay = a[1]
	pane.bx = b[0]
	pane.by = b[1]
	pane.z0 = d.get("z0", .9)
	pane.z1 = d.get("z1", 1.9)
	var length := Vector2(pane.bx - pane.ax, pane.by - pane.ay).length()
	if length < .05 or length > 16.0 or pane.z1 <= pane.z0 + .05 or pane.z0 < -50.0:
		return null
	return pane


## A barred door's side (pass 15, the level file's "bar_side": "n", "s", "e"
## or "w", the side its bar is on) as Door.bar_side: -1 west or north, 1 east
## or south, 0 none (or a side across the door's own wall).
static func bar_side(side: String, vertical: bool) -> int:
	match side:
		"w":
			return -1 if vertical else 0
		"e":
			return 1 if vertical else 0
		"n":
			return 0 if vertical else -1
		"s":
			return 0 if vertical else 1
	return 0


## A list of numbers (or numbers written as text) as ints, read natively (as
## _int reads each: tools/load_check.gd holds the two together).
static func ints(values: Variant) -> PackedInt32Array:
	if values is Array:
		var list: Array = values
		return PackedInt32Array(list)
	var out := PackedInt32Array()
	out.resize(len(values))
	for i in len(values):
		out[i] = LevelData._int(values[i])
	return out


static func floats(values: Variant) -> PackedFloat32Array:
	if values is Array:
		var list: Array = values
		return PackedFloat32Array(list)
	var out := PackedFloat32Array()
	out.resize(len(values))
	for i in len(values):
		out[i] = LevelData._float(values[i])
	return out


static func floats2(rows: Variant) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(len(rows) * 3)
	for i in len(rows):
		var row: Array = rows[i]
		out[i * 3] = LevelData._float(row[0])
		out[i * 3 + 1] = LevelData._float(row[1])
		out[i * 3 + 2] = LevelData._float(row[2])
	return out


## Round a double to the nearest float32 value so dictionary keys built from
## JSON strings compare equal to keys built from packed float arrays.
static func f32(value: float) -> float:
	var one := PackedFloat32Array()
	one.resize(1)
	one[0] = value
	return float(one[0])
