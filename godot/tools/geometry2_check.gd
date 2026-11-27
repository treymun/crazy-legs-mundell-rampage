## GEOMETRY 2 CHECK (pass 16, T1 SHAPES): geometry version 2 on a test level
## of its own: a hill and a plateau of terrain (its cliff), a raked wall, a
## house with a gable roof and its ridge, a deck cut by eight lines. Checks
## the version is written only when used; the terrain's queries; walking up
## and down the hill, against the cliff and off it; standing on the ridge;
## the nav graph over the hill and round the cliff; sight and shots over the
## hill's crest and past the raked wall; the 3D mesh (the hill's surface at
## every height, the cliff upright, the rakes as quads, no floor under the
## terrain); a save on the hillside; broken terrain refused; the same level
## twice; a glTF gable and a steep roof face imported (raked walls, a slope
## not walked on) and built as version 2.
##
##   Godot --headless --path <project> --script res://tools/geometry2_check.gd [-- write=<file>]
##
## write=<file> also writes the test level there (a window tour of it, under
## res://data/<id>.json for the tour's run only).
extends SceneTree

const Builder := preload("res://tools/levels/level_builder.gd")
const Geo := preload("res://tools/levels/geo_kit.gd")
const House := preload("res://tools/levels/house_kit.gd")
const Source := preload("res://tools/map/map_source.gd")
const Compile := preload("res://tools/map/map_compile.gd")
const Import := preload("res://tools/map/map_import.gd")
const ID := "zz_shapes2"
const DT := 1.0 / 60.0
## The hill: over cells 4..19 x 4..19, 3.0 at its middle (12, 12).
const HILL := [4, 4, 20, 20]
const HILL_TOP := 3.0
## The plateau: cells 24..33 x 4..11, flat 2.0 east of x 28, 0 west of x 27,
## the cell between a cliff.
const PLATEAU := 2.0
const CLIFF_X := 27

var failures: Array = []
var write_to := ""


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


static func level() -> Dictionary:
	var b = Builder.new(ID, 48, 36, "hedgerow")
	var yard: int = b.district("SHAPES")
	b.yard(1, 1, 46, 34, "dirt", yard)
	Geo.hill(b, "hill", HILL, HILL_TOP, {"tile": "grass"})
	var plateau := func(x: float, _y: float) -> float: return PLATEAU if x >= CLIFF_X + 1 else 0.0
	Geo.terrain(b, "plateau", 24, 4, 10, 8, plateau, {"tile": "gravel", "cliff": "quarry_face"})
	# A raked wall: .5 high at its west end, 3.0 at its east end.
	Geo.raked(b, "rake", Vector2(30, 22), Vector2(36, 22), 0.0, .5, 3.0, {"thick": .2})
	# A house with a gable roof (its ridge east-west at y 28).
	House.house(b, "house", 6, 25, 14, 31, {"storeys": 1, "area": yard})
	# An octagonal deck: a box cut by eight lines (four corners, four sides).
	var cuts := [
		[1, 1, 73.0],
		[1, -1, 19.0],
		[-1, 1, -7.0],
		[-1, -1, -61.0],
		[1, 0, 43.8],
		[-1, 0, -36.2],
		[0, 1, 30.8],
		[0, -1, -23.2]
	]
	Geo.deck(b, "octagon", [36, 23, 44, 31], .6, {"thick": .15, "cuts": cuts})
	b.enemy("billy", 12.5, 12.5, "hill_billy")
	b.enemy("billy", 40.5, 15.5, "yard_billy")
	b.pickup("beer", 12.5, 11.5)
	Geo.lift_onto_terrain(b)
	return b.finish([2.5, 18.5, 0.0])


## The hill's surface at (x, y) as the kit made it (to the centimetre).
static func hill_at(x: float, y: float) -> float:
	var mid := Vector2(12, 12)
	var d := Vector2((x - mid.x) / 8.0, (y - mid.y) / 8.0).length()
	return HILL_TOP * (.5 + .5 * cos(PI * minf(d, 1.0)))


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("write="):
			write_to = String(arg).substr(6)
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var made := level()
	LevelData.preview[ID] = made
	if write_to != "":
		var f := FileAccess.open(write_to, FileAccess.WRITE)
		f.store_string(JSON.stringify(made))
		f.close()
	_versions(made)
	_queries(main)
	_walking(main)
	_nav(main)
	_sight(main)
	_mesh(main)
	_saves(main)
	_refused(main)
	_imported(main)
	LevelData.preview.erase(ID)
	print("")
	print("GEOMETRY 2 CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _game(main) -> Game:
	var g: Game = main.make_game(ID)
	g.configure({})
	g.cheats.god = true
	g.spawn_grace = 0.0
	for e: Enemy in g.enemies:
		e.dormant = true
	return g


func _place(g: Game, x: float, y: float, z: float, angle := 0.0) -> void:
	var p := g.player
	p.x = x
	p.y = y
	p.floor_z = z
	p.air = 0.0
	p.angle = angle
	p.eye = .95 + z


func _walk(g: Game, goal: Vector2, seconds: float, watch := Callable()) -> void:
	var c := Game.Controls.new()
	c.forward = 1.0
	for _k in int(seconds * 60.0):
		var p := g.player
		if Vector2(p.x, p.y).distance_to(goal) < .15:
			break
		p.angle = atan2(goal.y - p.y, goal.x - p.x)
		g.tick(DT, c)
		if watch.is_valid():
			watch.call()
	for _k in 30:
		g.tick(DT, Game.Controls.new())


func _versions(made: Dictionary) -> void:
	print("versions")
	var block: Dictionary = made["geometry"]
	_check(
		int(block["version"]) == 2, "a level with terrain and a raked wall is written as version 2"
	)
	var plain := {"slabs": [{"id": "d", "gx": .5}], "segments": [{"id": "s", "z1": 2.0}]}
	_check(LevelGeometry.version_for(plain) == 1, "one without them as version 1")
	var raked := {"segments": [{"id": "s", "z1": 1.0, "z1b": 2.0}]}
	_check(LevelGeometry.version_for(raked) == 2, "a raked wall alone needs version 2")
	var steep := {"slabs": [{"id": "f", "gy": 3.0, "walk": false}]}
	_check(LevelGeometry.version_for(steep) == 2, "and a face too steep to walk on")
	var again := level()
	_check(JSON.stringify(again) == JSON.stringify(made), "the same level twice, to the byte")


func _queries(main) -> void:
	print("terrain")
	var g := _game(main)
	var w: LevelData = g.world
	var t := w.geo.terrain
	_check(t != null and t.patches.size() == 2, "two patches read")
	_check(
		absf(w.floor_under(12.0, 12.0, 10.0) - HILL_TOP) < .02,
		"the hill's top is %.2f (want %.2f)" % [w.floor_under(12.0, 12.0, 10.0), HILL_TOP]
	)
	var worst := 0.0
	var between := 0.0
	var under := true
	for k in 200:
		var x := 4.0 + (k % 20) * .79
		var y := 4.0 + (k / 20) * 1.59
		between = maxf(between, absf(w.floor_under(x, y, 10.0) - hill_at(x, y)))
		under = under and w.elevation(x, y) <= t.height_at(x, y) + 1e-6
	for k in 289:
		var x := 4.0 + k % 17
		var y := 4.0 + k / 17
		worst = maxf(
			worst, absf(w.floor_under(minf(x, 19.999), minf(y, 19.999), 10.0) - hill_at(x, y))
		)
	_check(worst < .006, "the surface is the hill at its corners (worst %.3f off)" % worst)
	_check(between < .08, "and close between them (worst %.3f off)" % between)
	_check(under, "every cell's ground lies under the surface")
	_check(absf(w.floor_under(30.0, 8.0, 10.0) - PLATEAU) < .01, "the plateau stands at 2.0")
	_check(t.cliff_at(27.6, 6.4) and t.cliff_at(27.4, 6.6), "the cell between is a cliff")
	_check(not t.cliff_at(14.0, 12.0), "the hill is no cliff")
	var e: Enemy = g.enemies[0]
	_check(
		absf(e.floor_z - t.height_at(e.x, e.y)) < .002,
		"the hand on the hill stands on it (%.2f)" % e.floor_z
	)
	var pk: Array = w.pickups[0]
	_check(
		pk.size() > 3 and absf(float(pk[3]) - t.height_at(12.5, 11.5)) < .002,
		"the beer lies on it (lifted at build: %s)" % [pk]
	)


func _walking(main) -> void:
	print("walking")
	var g := _game(main)
	var p := g.player
	# Up the hill from its west foot to the top, then down its east side.
	_place(g, 3.0, 12.0, 0.0)
	var high := [0.0]
	_walk(g, Vector2(12.0, 12.0), 8.0, func() -> void: high[0] = maxf(high[0], g.world.stand(p)))
	_check(
		(
			Vector2(p.x, p.y).distance_to(Vector2(12, 12)) < .3
			and absf(g.world.stand(p) - HILL_TOP) < .05
		),
		"walked up the hill to its top (%.2f, %.2f at %.2f)" % [p.x, p.y, g.world.stand(p)]
	)
	_walk(g, Vector2(21.0, 12.0), 8.0)
	_check(p.x > 20.0 and absf(g.world.stand(p)) < .05, "and down its far side (x %.2f)" % p.x)
	# The cliff: walked at from the west it holds a body back.
	_place(g, 25.5, 7.5, 0.0)
	_walk(g, Vector2(31.0, 7.5), 4.0)
	_check(p.x < 27.8 and g.world.stand(p) < .3, "the cliff holds a body back (x %.2f)" % p.x)
	# Off its top: a fall to the ground west of it.
	_place(g, 30.0, 7.5, PLATEAU)
	_walk(g, Vector2(25.0, 7.5), 4.0)
	for _k in 60:
		g.tick(DT, Game.Controls.new())
	_check(p.x < 27.0 and absf(g.world.stand(p)) < .05, "walked off the plateau, down the cliff")
	# On the ridge of the house's roof.
	var ridge := 2.4 + .15 + 3.0 * .6
	_place(g, 10.5, 26.0, 2.4 + .15 + .6 * .6)
	_walk(g, Vector2(10.5, 28.0), 3.0)
	_check(
		absf(g.world.stand(p) - ridge) < .05,
		"stood on the ridge at %.2f (want %.2f)" % [g.world.stand(p), ridge]
	)
	# The raked wall stops a body at its low end (.5 high) as at its high end.
	_place(g, 31.0, 23.5, 0.0)
	_walk(g, Vector2(31.0, 20.5), 2.0)
	_check(p.y > 22.0, "the raked wall's low end stops a body (y %.2f)" % p.y)


func _nav(main) -> void:
	print("nav")
	var g := _game(main)
	var w: LevelData = g.world
	var f := FlowField.new(w)
	f.reach = 100000
	var top := f.graph.node_at(12.5, 12.5, w.width, w.height, HILL_TOP)
	_check(
		absf(f.graph.z[top] - w.geo.terrain.height_at(12.5, 12.5)) < .002,
		"the hill's nodes stand on it (%.2f)" % f.graph.z[top]
	)
	f.update(12.5, 12.5, 1.0, HILL_TOP)
	var d := f.distance(2.5, 18.5, 0.0)
	_check(d < FlowField.FAR, "the yard reaches the hill's top (%d steps)" % d)
	# The plateau: its cliff to the west, and to the north, east and south its
	# edge 2.0 over the yard (no step): nobody walks up.
	f.update(30.5, 7.5, 10.0, PLATEAU)
	var up := f.distance(22.5, 7.5, 0.0)
	_check(up >= FlowField.FAR, "nobody walks up the cliff (%d)" % up)
	# A hand at the hill's foot comes up it to the player on its top.
	var h := _game(main)
	_place(h, 12.0, 12.0, HILL_TOP)
	h.cheats.god = true
	var e: Enemy = h.enemies[1]
	e.x = 3.5
	e.y = 12.5
	e.floor_z = h.world.stand(e)
	e.dormant = false
	e.alerted = true
	var far := Vector2(e.x, e.y).distance_to(Vector2(12, 12))
	for _k in 600:
		h.tick(DT, Game.Controls.new())
	var near := Vector2(e.x, e.y).distance_to(Vector2(12, 12))
	_check(
		near < far - 3.0 and h.world.stand(e) > 1.0,
		"a hand comes up the hill (%.1f -> %.1f cells off, at %.2f)" % [far, near, h.world.stand(e)]
	)


func _sight(main) -> void:
	print("sight and shots")
	var g := _game(main)
	var w: LevelData = g.world
	_check(
		not w.visible(3.0, 12.0, 21.0, 12.0, .95, .95),
		"the hill's crest stops a look at eye height"
	)
	_check(w.visible(3.0, 12.0, 21.0, 12.0, 4.5, 4.5), "a look over it passes")
	_check(w.visible(3.0, 12.0, 12.0, 12.0, .95, HILL_TOP + .95), "a look up to its top passes")
	_check(
		w.geo.solid_point(12.0, 12.0, HILL_TOP - .3, .0, true), "a shot into the hill stops in it"
	)
	_check(not w.visible(33.0, 26.0, 33.0, 18.0, 1.0, 1.0), "the raked wall stops a look at 1.0")
	_check(w.visible(30.5, 26.0, 30.5, 18.0, 1.0, 1.0), "but not over its low end")
	_check(not w.visible(35.5, 26.0, 35.5, 18.0, 2.4, 2.4), "its high end stops one at 2.4")
	# Flat looks (no heights) walk over the terrain's rise, as over a deck.
	_check(w.visible(3.0, 12.0, 21.0, 12.0), "a look without heights is the flat one it always was")


func _mesh(main) -> void:
	print("views")
	var g := _game(main)
	var builder := LevelMesh.new(g.level)
	var parts := builder.build_static(g.level.active_base(false))
	var top := 0
	var cliff := 0
	var rake := 0
	var floor_under := 0
	var heights := {}
	var cliff_tile := float(g.level.tile_id("quarry_face"))
	for key: Vector2i in parts:
		var mesh: ArrayMesh = parts[key]
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var custom1: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM1]
		for i in verts.size():
			var q := verts[i]
			if absf(q.y - HILL_TOP) < .01 and absf(q.x - 12.0) < .01 and absf(q.z - 12.0) < .01:
				top += 1
			var floor := int(custom1[i * 4 + 3]) == LevelMesh.KIND_FLOOR * 4
			if q.x > 4.5 and q.x < 19.5 and q.z > 4.5 and q.z < 19.5:
				heights[snappedf(q.y, .5)] = true
				# A floor's own quad at a cell's ground inside the hill would
				# show through: only the terrain's surface is there.
				if floor and q.y < hill_at(q.x, q.z) - .1:
					floor_under += 1
			if custom1[i * 4] == cliff_tile and int(custom1[i * 4 + 3]) == 1:
				cliff += 1
			if absf(q.y - 3.0) < .01 and absf(q.x - 36.0) < .01 and absf(q.z - 22.0) < .15:
				rake += 1
	_check(top >= 1, "the 3D mesh has the hill's top (%d points)" % top)
	_check(
		heights.size() >= 6,
		"and its surface at every height (%d half-metre bands)" % heights.size()
	)
	_check(floor_under == 0, "no floor drawn under the terrain (%d points)" % floor_under)
	_check(cliff >= 6, "the cliff drawn upright in its own tile (%d points)" % cliff)
	_check(rake >= 2, "the raked wall's high end as a quad (%d points)" % rake)
	var rows := g.level.geo.rakes.size() / LevelGeometry.RAKE_STRIDE
	_check(rows >= 4, "the rakes listed (%d: the wall's faces, the gables)" % rows)
	var w: LevelData = g.world
	_check(absf(w.floor_under(40.0, 27.0, 1.0) - .6) < .01, "the eight-cut deck floored at .6")
	_check(absf(w.floor_under(36.3, 23.3, 1.0)) < .01, "its cut-off corner not")
	_check(absf(w.floor_under(43.9, 27.0, 1.0)) < .01, "nor its cut-off side")


func _saves(main) -> void:
	print("saves")
	var g := _game(main)
	var p := g.player
	var z := hill_at(9.0, 12.0)
	_place(g, 9.0, 12.0, z)
	g.replay = true
	var doc: Dictionary = SessionStore.snapshot(g)
	var h: Game = SessionStore.restore_onto(doc, main.make_game(ID))
	_check(h != null, "a save on the hillside loads (%s)" % SessionStore.last_error)
	if h != null:
		_check(
			absf(h.world.stand(h.player) - z) < .02,
			(
				"the player stands on the hillside again (%.2f, want %.2f)"
				% [h.world.stand(h.player), z]
			)
		)
		_check(p.x == h.player.x and p.y == h.player.y, "where they were")


func _refused(main) -> void:
	print("broken terrain refused")
	var art: Assets = main.make_game(ID).art
	var bad := [
		[{"id": "few", "x": 1, "y": 1, "w": 2, "h": 2, "heights": [0, 0, 0]}, "corners"],
		[{"id": "half", "x": 1, "y": 1, "w": 1, "h": 1, "heights": [0, 0, 0, .5]}, "whole"],
		[{"id": "off", "x": 46, "y": 1, "w": 4, "h": 1, "heights": []}, "off the map"],
		[{"id": "big", "x": 1, "y": 1, "w": 1, "h": 1, "heights": [0, 0, 0, 99999]}, "past"],
		[
			{"id": "tile", "x": 1, "y": 1, "w": 1, "h": 1, "heights": [0, 0, 0, 0], "tile": "zz"},
			"tile"
		],
		[
			{
				"id": "rows",
				"x": 1,
				"y": 1,
				"w": 2,
				"h": 1,
				"heights": [0, 0, 0, 0, 0, 0],
				"rows": ["0"]
			},
			"letters"
		],
		["junk", "not an object"],
	]
	for case: Array in bad:
		var errors: Array = []
		var t := LevelTerrain.from_json([case[0]], 48, 36, art.tile_index, errors)
		var said := " ".join(PackedStringArray(errors))
		_check(t == null and said.contains(String(case[1])), "refused: %s" % said)
	var errors: Array = []
	var v1 := {"version": 1, "terrain": [{"x": 1, "y": 1, "w": 1, "h": 1, "heights": [0, 0, 0, 0]}]}
	LevelGeometry.from_json(v1, 48, 36, art.tile_index, errors)
	_check(
		" ".join(PackedStringArray(errors)).contains("version 2"),
		"terrain in a version 1 block refused"
	)
	errors = []
	var v1_steep := {
		"version": 1,
		"slabs": [{"x0": 1, "y0": 1, "x1": 2, "y1": 2, "top": 1, "gy": 3, "walk": false}]
	}
	LevelGeometry.from_json(v1_steep, 48, 36, art.tile_index, errors)
	_check(not errors.is_empty(), "a face steeper than 1 in a version 1 block refused")
	errors = []
	var v2_steep := {
		"version": 2,
		"slabs": [{"x0": 1, "y0": 1, "x1": 2, "y1": 2, "top": 1, "gy": 3, "walk": false}]
	}
	LevelGeometry.from_json(v2_steep, 48, 36, art.tile_index, errors)
	_check(errors.is_empty(), "but taken in version 2 when not walked on (%s)" % [errors])


func _imported(main) -> void:
	print("import")
	var art: Assets = main.make_game(ID).art
	var kept := Source.dir
	var scratch := OS.get_cache_dir().path_join("clmr_geometry2_check")
	DirAccess.make_dir_recursive_absolute(scratch)
	Source.dir = scratch
	var map_id := "gable"
	Source.write(map_id, Source.blank(map_id, 16, 16))
	var glb := scratch.path_join("gable.glb")
	_gable_gltf(glb)
	var out := Import.run(map_id, glb, {"default_tile": "barn", "prefix": "gable"}, art)
	_check(
		int(out["exit"]) == 0, "a gable and a steep roof face import (%s)" % out.get("error", "")
	)
	var doc := Source.read(map_id)
	Source.dir = kept
	var raked := 0
	var steep := 0
	for o: Dictionary in doc.get("objects", []):
		if String(o["type"]) == "wall" and o.has("z1b"):
			raked += 1
		if String(o["type"]) == "ramp" and not bool(o.get("walk", true)):
			steep += 1
	_check(raked == 2, "the gable comes in as two raked walls up to its peak (%d)" % raked)
	_check(steep == 1, "the steep face as a slope not walked on (%d)" % steep)
	var built := Compile.compile(doc)
	var level: Dictionary = built.get("level", {})
	var block: Dictionary = level.get("geometry", {})
	var peak := 0.0
	for seg: Dictionary in block.get("segments", []):
		peak = maxf(peak, float(seg.get("z1b", 0.0)))
	_check(int(block.get("version", 1)) == 2, "and it builds as geometry version 2")
	_check(absf(peak - 3.5) < .02, "its raked walls reach the peak at 3.5 (%.2f)" % peak)
	var errors: Array = []
	LevelGeometry.from_json(block, 16, 16, art.tile_index, errors)
	_check(errors.is_empty(), "and reads back without a word (%s)" % [errors])


## A glTF of a gable end (a wall 6 wide, 2 to its eaves, 3.5 at its peak) and
## a roof face rising 3 in 1 (72 degrees: too steep to stand on).
static func _gable_gltf(path: String) -> void:
	var root := Node3D.new()
	root.name = "Gable"
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var g := [
		Vector3(2, 0, 5), Vector3(8, 0, 5), Vector3(8, 2, 5), Vector3(2, 2, 5), Vector3(5, 3.5, 5)
	]
	for idx in [0, 1, 2, 0, 2, 3, 3, 2, 4]:
		st.add_vertex(g[idx])
	var wall := MeshInstance3D.new()
	wall.name = "GableEnd"
	wall.mesh = st.commit()
	root.add_child(wall)
	var s2 := SurfaceTool.new()
	s2.begin(Mesh.PRIMITIVE_TRIANGLES)
	var q := [Vector3(10, 0, 4), Vector3(12, 0, 4), Vector3(12, 3, 5), Vector3(10, 3, 5)]
	for idx in [0, 1, 2, 0, 2, 3]:
		s2.add_vertex(q[idx])
	var face := MeshInstance3D.new()
	face.name = "SteepFace"
	face.mesh = s2.commit()
	root.add_child(face)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_scene(root, state)
	doc.write_to_filesystem(state, path)
	root.free()
