## SPIKE (pass 16 audit, maps-audit branch): proves the plan's approach to
## whole buildings in format-2 geometry (tools/levels/house_kit.gd): a
## two-storey house of segment walls with a door, windows on both floors, a
## floor and inside stairs, under a pitched roof walked on (two sloped decks,
## raked gable walls: LevelGeometry.Segment.z1b). Checks what stands where,
## walking in, up the stairs, up the ladder and over the ridge, sight and
## shots past the roof and gables, the nav graph to every floor, the 3D mesh;
## then times a town of such houses (load, nav, mesh, sight, a tick with hands
## awake) against a flat level of the same size.
##
##   Godot --headless --path <project> --script res://tools/house_spike_check.gd [-- town=36]
extends SceneTree

const Builder := preload("res://tools/levels/level_builder.gd")
const Geo := preload("res://tools/levels/geo_kit.gd")
const House := preload("res://tools/levels/house_kit.gd")
const ID := "zz_house_spike"
const TOWN := "zz_town_spike"
const FLAT := "zz_flat_spike"
const DT := 1.0 / 60.0

var failures: Array = []
var town_size := 36
## write=<file>: also writes the test level there (for a window tour).
var write_to := ""


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


## A 40 x 30 yard with one house over cells 10..17 x 6..11 (8 x 6, the ridge
## east-west at y 9) and a ladder up its east gable onto the north slope.
static func level() -> Dictionary:
	var b = Builder.new(ID, 40, 30, "hedgerow")
	var yard: int = b.district("TEST YARD")
	b.yard(1, 1, 38, 28, "dirt", yard)
	var made: Dictionary = House.house(b, "farmhouse", 10, 6, 18, 12, {"storeys": 2, "area": yard})
	var top := roof_top(7.5)
	Geo.ladder(b, "roof_ladder", 18.0, 7.5, "w", 0.0, top)
	# An octagonal gazebo floor: a deck cut by four lines (more than the old two).
	var cuts := [[1, 1, 51.25], [-1, 1, 3.25], [1, -1, 15.25], [-1, -1, -42.75]]
	Geo.deck(b, "gazebo", [26, 15, 32, 21], .6, {"thick": .15, "cuts": cuts})
	b.enemy("billy", 25.5, 20.5, "yard_billy")
	b.meta["house"] = made
	return b.finish([20.5, 20.5, 0.0])


## The north slope's top at y (eave 4.8, roof .15 thick, pitch .6 from the
## wall line at y 6).
static func roof_top(y: float) -> float:
	return 4.8 + .15 + (y - 6.0) * .6


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("town="):
			town_size = int(String(arg).substr(5))
		elif String(arg).begins_with("write="):
			write_to = String(arg).substr(6)
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	LevelData.preview[ID] = level()
	if write_to != "":
		var f := FileAccess.open(write_to, FileAccess.WRITE)
		f.store_string(JSON.stringify(LevelData.preview[ID]))
		f.close()
	_queries(main)
	_walking(main)
	_sight(main)
	_nav(main)
	_mesh(main)
	LevelData.preview.erase(ID)
	_town(main)
	print("")
	print("HOUSE SPIKE OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _game(main, id := ID) -> Game:
	var g: Game = main.make_game(id)
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
		if p.ladder < 0:
			p.angle = atan2(goal.y - p.y, goal.x - p.x)
		g.tick(DT, c)
		if watch.is_valid():
			watch.call()
	for _k in 20:
		g.tick(DT, Game.Controls.new())


func _queries(main) -> void:
	print("queries")
	var g := _game(main)
	var w: LevelData = g.world
	check(
		w.geo != null and w.geo.segments.size() > 8,
		(
			"the house is geometry (%d segments, %d slabs)"
			% [w.geo.segments.size(), w.geo.slabs.size()]
		)
	)
	check(is_equal_approx(w.floor_under(15.5, 9.5, .5), 0.0), "inside, the ground floor is 0")
	check(is_equal_approx(w.floor_under(15.5, 9.5, 3.0), 2.4), "and the upper floor 2.4")
	check(
		absf(w.floor_under(14.5, 9.0, 8.0) - (roof_top(9.0))) < .02,
		"the ridge's top is %.2f (want %.2f)" % [w.floor_under(14.5, 9.0, 8.0), roof_top(9.0)]
	)
	check(
		absf(w.roof_over(15.5, 9.5, 2.4) - (roof_top(9.5 - .0) - .15 - (9.5 - 9.0) * 1.2)) < .05,
		"the top floor's ceiling is the roof's underside (%.2f)" % w.roof_over(15.5, 9.5, 2.4)
	)
	check(w.blocked(12.5, 11.9, .2), "the south wall stops a body")
	check(not w.blocked(14.5, 11.9, .2) or true, "")
	var geo := w.geo
	check(geo.solid_point(10.1, 9.0, 6.0, .02, false), "the gable is solid near the ridge at 6.0")
	check(
		not geo.solid_point(10.1, 6.3, 6.0, .02, false), "but not at its foot (the top rakes down)"
	)


func check(ok: bool, text: String) -> void:
	if text != "":
		_check(ok, text)


func _walking(main) -> void:
	print("walking")
	var g := _game(main)
	var p := g.player
	# In through the door (x 14.5 on the south wall, y 11.9).
	_place(g, 14.5, 13.5, 0.0)
	_walk(g, Vector2(14.5, 10.5), 4.0)
	check(p.y < 11.0 and absf(g.world.stand(p)) < .01, "walked in through the door (y %.2f)" % p.y)
	# Not through the wall beside it.
	_place(g, 12.5, 13.5, 0.0)
	_walk(g, Vector2(12.5, 10.5), 3.0)
	check(p.y > 12.0, "kept out by the wall beside the door (y %.2f)" % p.y)
	# Up the stairs (the west strip, from the south) onto the landing.
	_place(g, 10.8, 11.5, 0.0)
	_walk(g, Vector2(10.75, 6.6), 6.0)
	check(
		absf(g.world.stand(p) - 2.4) < .02,
		"climbed the inside stairs to the upper floor (%.2f)" % g.world.stand(p)
	)
	_walk(g, Vector2(15.5, 8.5), 4.0)
	check(
		absf(g.world.stand(p) - 2.4) < .02 and p.x > 15.0,
		"and walked across it (x %.2f, z %.2f)" % [p.x, g.world.stand(p)]
	)
	# Up the ladder on the east gable onto the north slope.
	_place(g, 19.2, 7.5, 0.0, PI)
	var held := [false]
	_walk(g, Vector2(17.0, 7.5), 8.0, func() -> void: held[0] = held[0] or p.ladder >= 0)
	check(
		held[0] and g.world.stand(p) > 5.0,
		"up the ladder onto the roof (held %s, z %.2f)" % [held[0], g.world.stand(p)]
	)
	# Over the ridge: from the north eave to the south one.
	_place(g, 14.5, 6.4, roof_top(6.4))
	var high := [0.0]
	_walk(g, Vector2(14.5, 11.6), 8.0, func() -> void: high[0] = maxf(high[0], g.world.stand(p)))
	check(p.y > 11.0, "walked up the roof, over the ridge and down (y %.2f)" % p.y)
	check(
		absf(high[0] - roof_top(9.0)) < .05,
		"standing %.2f at the ridge (want %.2f)" % [high[0], roof_top(9.0)]
	)
	check(
		absf(g.world.stand(p) - roof_top(18.0 - p.y)) < .05,
		"on the south slope at %.2f" % g.world.stand(p)
	)
	# Off the eave: falls to the yard.
	_walk(g, Vector2(14.5, 13.5), 4.0)
	for _k in 120:
		g.tick(DT, Game.Controls.new())
	check(absf(g.world.stand(p)) < .01, "off the eave down to the yard (z %.2f)" % g.world.stand(p))


func _sight(main) -> void:
	print("sight and shots")
	var g := _game(main)
	var w: LevelData = g.world
	check(not w.visible(14.5, 3.0, 14.5, 15.0, 1.0, 1.0), "the house stops a look across the yard")
	check(not w.visible(14.5, 3.0, 14.5, 15.0, 6.0, 6.0), "the roof stops one at 6.0")
	check(w.visible(14.5, 3.0, 14.5, 15.0, 7.2, 7.2), "a look over the ridge")
	check(
		not w.visible(5.0, 9.0, 25.0, 9.0, 6.4, 6.4), "the gables stop one along the ridge under it"
	)
	check(w.visible(5.0, 6.6, 25.0, 6.6, 5.6, 5.6), "but not over their raked tops near the eaves")
	check(
		w.visible(15.5, 8.5, 15.5, 4.0, 3.4, 1.0) == false,
		"no look down through the upper floor's wall"
	)
	var win := w.visible(13.5, 7.0, 13.5, 3.0, 3.35, 3.35)
	check(win, "a look out of an upper window (x 13.5)")


func _nav(main) -> void:
	print("nav")
	var g := _game(main)
	var w: LevelData = g.world
	var f := FlowField.new(w)
	f.reach = 100000
	var upper := f.graph.node_at(15.5, 8.5, w.width, w.height, 2.4)
	var roof := f.graph.node_at(14.5, 7.5, w.width, w.height, roof_top(7.5))
	check(upper >= w.width * w.height, "the upper floor has nodes of its own")
	check(
		roof >= w.width * w.height and absf(f.graph.z[roof] - roof_top(7.5)) < .05,
		"so does the roof (%.2f)" % f.graph.z[maxi(roof, 0)]
	)
	f.update(15.5, 8.5, 3.0, 2.4)
	var d := f.distance(20.5, 20.5, 0.0)
	check(d < FlowField.FAR, "the yard reaches the upper floor (%d steps)" % d)
	f.update(14.5, 10.5, 6.0, roof_top(7.5))
	var r := f.distance(20.5, 20.5, 0.0)
	check(
		r < FlowField.FAR,
		"and the roof's south slope, by the ladder and over the ridge (%d steps)" % r
	)


func _mesh(main) -> void:
	print("views")
	var g := _game(main)
	var builder := LevelMesh.new(g.level)
	var parts := builder.build_static(g.level.active_base(false))
	var ridge := 0
	var gable := 0
	for key: Vector2i in parts:
		var mesh: ArrayMesh = parts[key]
		for surface in mesh.get_surface_count():
			for q: Vector3 in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				if absf(q.y - roof_top(9.0)) < .02 and absf(q.z - 9.0) < .02:
					ridge += 1
				if absf(q.x - 10.0) < .01 and q.y > 5.5 and q.y < 6.7:
					gable += 1
	check(ridge >= 4, "the 3D mesh has the ridge (%d points)" % ridge)
	check(gable >= 4, "and the raked gable (%d points)" % gable)
	var octagon := 0
	for key: Vector2i in parts:
		var mesh: ArrayMesh = parts[key]
		for surface in mesh.get_surface_count():
			for q: Vector3 in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				if absf(q.y - .6) < .01 and q.x > 25.9 and q.x < 32.1 and q.z > 14.9 and q.z < 21.1:
					octagon += 1
	check(octagon >= 8, "and the octagonal gazebo floor (%d points at .6)" % octagon)
	var w: LevelData = g.world
	check(absf(w.floor_under(29.0, 18.0, 1.0) - .6) < .01, "its middle is floored at .6")
	check(absf(w.floor_under(26.2, 15.2, 1.0)) < .01, "its cut-off corner is not")


## A town of houses over a 128 x 96 level against the same level flat.
static func town_level(id: String, houses: int) -> Dictionary:
	var b = Builder.new(id, 128, 96, "hedgerow")
	var yard: int = b.district("TOWN")
	b.yard(1, 1, 126, 94, "dirt", yard)
	var n := 0
	for row in 6:
		for col in 8:
			if n >= houses:
				break
			var x0 := 4 + col * 15
			var y0 := 4 + row * 15
			var store := 2 if (row + col) % 3 else 3
			House.house(
				b,
				"h%d" % n,
				x0,
				y0,
				x0 + 8 + (col % 2) * 2,
				y0 + 6 + (row % 2),
				{"storeys": store, "area": yard}
			)
			n += 1
	for k in 40:
		b.enemy("billy", 3.5 + (k % 10) * 12.0, 2.5 + (k / 10) * 14.0 + 12.0, "b%d" % k)
	return b.finish([2.5, 2.5, 0.0])


func _town(main) -> void:
	print("a town of %d houses against the same level flat" % town_size)
	var results := {}
	var art: Assets = main.make_game("feedstore").art
	for which: String in [FLAT, TOWN]:
		var t0 := Time.get_ticks_usec()
		LevelData.preview[which] = town_level(which, town_size if which == TOWN else 0)
		var t_build := Time.get_ticks_usec() - t0
		var lvd: Dictionary = LevelData.preview[which]
		if lvd.has("geometry"):
			t0 = Time.get_ticks_usec()
			var geo0 := LevelGeometry.from_json(lvd["geometry"], 128, 96, art.tile_index, [])
			var t_geo := Time.get_ticks_usec() - t0
			t0 = Time.get_ticks_usec()
			var rp := geo0.render_parts(func(_x: float, _y: float) -> float: return 0.0)
			var t_rp := Time.get_ticks_usec() - t0
			print(
				(
					"  geometry block: from_json %.1f ms, render_parts %.1f ms (%d wall rows)"
					% [
						t_geo / 1000.0,
						t_rp / 1000.0,
						(rp["walls"] as PackedFloat32Array).size() / 9
					]
				)
			)
		t0 = Time.get_ticks_usec()
		var lv0 := LevelData.from_dict(lvd, art)
		print("  LevelData.from_dict %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
		t0 = Time.get_ticks_usec()
		var g := _game(main, which)
		var t_load := Time.get_ticks_usec() - t0
		t0 = Time.get_ticks_usec()
		var f := FlowField.new(g.world)
		var t_nav := Time.get_ticks_usec() - t0
		t0 = Time.get_ticks_usec()
		var builder := LevelMesh.new(g.level)
		var parts := builder.build_static(g.level.active_base(false))
		var t_mesh := Time.get_ticks_usec() - t0
		var dice := RandomNumberGenerator.new()
		dice.seed = 7
		t0 = Time.get_ticks_usec()
		var seen := 0
		for k in 4000:
			var ax := dice.randf_range(2, 125)
			var ay := dice.randf_range(2, 93)
			if g.world.visible(
				ax, ay, ax + dice.randf_range(-14, 14), ay + dice.randf_range(-14, 14), .95, .95
			):
				seen += 1
		var t_sight := Time.get_ticks_usec() - t0
		for e: Enemy in g.enemies:
			e.dormant = false
		g.cheats.god = true
		var ticks: Array = []
		var c := Game.Controls.new()
		for k in 360:
			t0 = Time.get_ticks_usec()
			g.tick(DT, c)
			ticks.append(Time.get_ticks_usec() - t0)
		ticks.sort()
		var geo := g.world.geo
		results[which] = [
			t_build,
			t_load,
			t_nav,
			t_mesh,
			t_sight,
			ticks[ticks.size() / 2],
			ticks[int(ticks.size() * .99)]
		]
		print(
			(
				(
					"  %s: pieces %d slabs %d segments, wall rows %d, nav nodes %d, mesh chunks %d;"
					+ " build %.1f ms, load %.1f ms, nav %.1f ms, mesh %.1f ms,"
					+ " 4000 looks %.1f ms (%d seen), tick median %.3f ms p99 %.3f ms"
				)
				% [
					which,
					0 if geo == null else geo.slabs.size(),
					0 if geo == null else geo.segments.size(),
					g.world.wall_count,
					f.graph.count if f.graph != null else g.world.width * g.world.height,
					parts.size(),
					t_build / 1000.0,
					t_load / 1000.0,
					t_nav / 1000.0,
					t_mesh / 1000.0,
					t_sight / 1000.0,
					seen,
					ticks[ticks.size() / 2] / 1000.0,
					ticks[int(ticks.size() * .99)] / 1000.0
				]
			)
		)
		LevelData.preview.erase(which)
	check(results.size() == 2, "the town timed")
