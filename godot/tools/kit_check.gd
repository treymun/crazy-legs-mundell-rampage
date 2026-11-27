## The map kit's check (src/map_kit/, pass 16 T5; the audit's house spike
## folded in). Every piece at its smallest and largest size, in all 4 turns,
## mirrored and not, is built into a gallery level and must:
## - compile (the geometry block reads without an error, ids unique, every
##   tile known) and stay inside its footprint (bar its overhang);
## - be walked into through every doorway (the nav graph from the yard crosses
##   each one; in two of the frames a body walks in through each);
## - have every floor and roof meant to be reached reached from the yard;
## - give the same parts twice (the hash), and keep within its cost.
## Then the farmhouse's details (sight through windows and walls, the ridge,
## up the stairs and the ladder, over the roof, the mesh), the refusals (one
## plain line each), and the town of houses stress_bench and cpu_check time.
##
##   godot --headless --path godot --script res://tools/kit_check.gd [-- town=36] [write=<dir>]
##
## write=<dir> also writes the two gallery levels (kit_min.json, kit_max.json)
## and a picture tour of each (<level>_tour.json: every piece from outside, in
## through its first doorway, on its roof when it is climbed), for
## tools/map/map_pictures.gd in a window:
##
##   godot --path godot --audio-driver Dummy --resolution 640x400 --script
##       res://tools/map/map_pictures.gd -- level=<dir>/kit_min.json id=kit_min
##       --view-tour=<dir>/kit_min_tour.json --view-out=<pictures dir>
extends SceneTree

const Builder := preload("res://tools/levels/level_builder.gd")
const Geo := preload("res://tools/levels/geo_kit.gd")
const ID := "zz_kit_check"
const HOUSE := "zz_kit_house"
const TOWN := "zz_kit_town"
const FLAT := "zz_kit_flat"
const DT := 1.0 / 60.0
## The gallery's rows: this wide at most, pieces this far apart.
const ROW := 150
const GAP := 6

var failures: Array = []
var town_size := 0
var write_to := ""
var walks := 0
var walked := 0


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


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
	var t0 := Time.get_ticks_msec()
	_refusals()
	for size in ["min", "max"]:
		for turn in 4:
			for mirror in [false, true]:
				_gallery_run(main, size, turn, mirror)
	print("  (%d doorways walked by a body, %d made it)" % [walks, walked])
	_house(main)
	if write_to != "":
		_write_tour()
	if town_size > 0:
		_town(main)
	print("  kit check took %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	print("")
	print("KIT CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


# ------------------------------------------------------------------ gallery


## Every piece at its smallest or largest size (`size`), turned and mirrored
## so, laid out in rows on a dirt yard. Returns [level, parts].
static func gallery(id: String, size: String, turn: int, mirror: bool, gap := GAP) -> Array:
	var specs: Array = []
	var x := 4
	var y := 4
	var row_h := 0
	var widest := 0
	for name: String in KitPiece.names():
		var entry := KitPiece.catalog(name)
		var k := 1 if size == "min" else 2
		var w := int(entry["w"][k])
		var d := int(entry["d"][k])
		var fw := w if turn % 2 == 0 else d
		var fd := d if turn % 2 == 0 else w
		if x + fw > ROW:
			x = 4
			y += row_h + gap
			row_h = 0
		var spec := {
			"piece": name,
			"id": name,
			"x": x,
			"y": y,
			"w": w,
			"d": d,
			"turn": turn,
			"mirror": mirror
		}
		specs.append(spec)
		x += fw + gap
		row_h = maxi(row_h, fd)
		widest = maxi(widest, x)
	var b = Builder.new(id, widest + 4, y + row_h + 6, "hedgerow")
	var yard: int = b.district("KIT YARD")
	b.yard(1, 1, b.w - 2, b.h - 2, "dirt", yard)
	var parts := Geo.kit(b, specs, 7)
	var lv: Dictionary = b.finish([2.5, 2.5, 0.0])
	return [lv, parts]


func _gallery_run(main, size: String, turn: int, mirror: bool) -> void:
	var tag := "%s turn %d%s" % [size, turn, " mirrored" if mirror else ""]
	print("gallery: every piece, %s" % tag)
	var made := gallery(ID, size, turn, mirror)
	var lv: Dictionary = made[0]
	var parts: LevelParts = made[1]
	var again := gallery(ID, size, turn, mirror)
	var parts2: LevelParts = again[1]
	_check(
		parts.hash_text() == parts2.hash_text() and JSON.stringify(lv) == JSON.stringify(again[0]),
		"the same parts and level twice (%s)" % parts.hash_text().substr(0, 8)
	)
	var errors: Array = []
	var art: Assets = main.make_game("feedstore").art
	var geo := LevelGeometry.from_json(
		lv["geometry"], lv["width"], lv["height"], art.tile_index, errors
	)
	_check(
		geo != null and errors.is_empty(),
		(
			"the geometry reads (%d pieces) %s"
			% [parts.cost(), "" if errors.is_empty() else str(errors.slice(0, 3))]
		)
	)
	var ids := {}
	var doubled := 0
	for key in ["slabs", "segments", "ceilings", "ladders"]:
		for s: Dictionary in lv["geometry"][key]:
			if ids.has(s["id"]):
				doubled += 1
			ids[s["id"]] = true
	_check(doubled == 0, "every piece of geometry has its own id (%d doubled)" % doubled)
	_bounds(parts)
	var most := KitPiece.num("piece_cost_most")
	var dear: Array = []
	for p: Dictionary in parts.pieces:
		if int(p["cost"]) > most:
			dear.append("%s %d" % [p["id"], p["cost"]])
	_check(dear.is_empty(), "every piece within %d pieces of geometry %s" % [most, dear])
	_check(
		g_doors(lv) == parts.doors.size() and lv.get("geo_panes", []).size() == parts.panes.size(),
		(
			"%d doors hung, %d panes, %d vias written"
			% [parts.doors.size(), parts.panes.size(), parts.vias.size()]
		)
	)
	LevelData.preview[ID] = lv
	var g := _game(main, ID)
	_check(
		g.world.doors.size() == parts.doors.size(),
		"and every door loads (%d)" % g.world.doors.size()
	)
	_open_doors(g)
	var f := FlowField.new(g.world)
	f.reach = 100000
	f.update(2.5, 2.5, 0.0, 0.0)
	var shut: Array = []
	var far: Array = []
	var doors := 0
	var reached := 0
	for p: Dictionary in parts.pieces:
		for walk: Dictionary in p["walk_in"]:
			doors += 1
			var a: Array = walk["from"]
			var b: Array = walk["to"]
			var za := g.world.floor_under(a[0], a[1], float(a[2]) + .3)
			var zb := g.world.floor_under(b[0], b[1], float(b[2]) + .3)
			var d_out := f.distance(a[0], a[1], za)
			var d_in := f.distance(b[0], b[1], zb)
			if d_out >= FlowField.FAR or d_in >= FlowField.FAR or absi(d_in - d_out) > 5:
				shut.append("%s (%d, %d)" % [walk["door"], d_out, d_in])
		for spot: Dictionary in p["reach"]:
			var at: Array = spot["at"]
			var z := g.world.floor_under(at[0], at[1], float(at[2]) + .3)
			if f.distance(at[0], at[1], z) >= FlowField.FAR or absf(z - float(at[2])) > .35:
				far.append("%s (%.2f at %.2f)" % [spot["id"], at[2], z])
			else:
				reached += 1
	_check(
		shut.is_empty(), "the yard walks in through all %d doorways %s" % [doors, shut.slice(0, 6)]
	)
	_check(far.is_empty(), "and reaches %d floors and roofs %s" % [reached, far.slice(0, 6)])
	if (turn == 0 and not mirror) or (turn == 1 and mirror):
		_body_walks(g, parts, tag)
	LevelData.preview.erase(ID)


static func g_doors(lv: Dictionary) -> int:
	return (lv.get("doors", []) as Array).size()


## The walk-in tests go through open doors (T4's doors open on USE; ways_check
## holds them).
static func _open_doors(g: Game) -> void:
	for door: LevelData.Door in g.world.doors:
		door.opened = true
		door.progress = 1.0


## Every piece's geometry within its footprint grown by its overhang (1.0).
func _bounds(parts: LevelParts) -> void:
	var boxes := {}
	for p: Dictionary in parts.pieces:
		var fp: Array = p["footprint"]
		boxes[p["id"]] = Rect2(Vector2(fp[0], fp[1]), Vector2(fp[2] - fp[0], fp[3] - fp[1])).grow(
			1.0
		)
	var out: Array = []
	for s: Dictionary in parts.slabs:
		var box: Rect2 = boxes[_owner(s["id"], boxes)]
		if not box.encloses(Rect2(s["x0"], s["y0"], s["x1"] - s["x0"], s["y1"] - s["y0"])):
			out.append(s["id"])
	for s: Dictionary in parts.segments:
		var box: Rect2 = boxes[_owner(s["id"], boxes)]
		if (
			not box.has_point(Vector2(s["a"][0], s["a"][1]))
			or not box.has_point(Vector2(s["b"][0], s["b"][1]))
		):
			out.append(s["id"])
	_check(out.is_empty(), "every piece stays on its footprint %s" % [out.slice(0, 5)])


static func _owner(id: String, boxes: Dictionary) -> String:
	var best := ""
	for key: String in boxes:
		if id.begins_with(key + "_") and key.length() > best.length():
			best = key
	return best


## A body walks in through every doorway (from 1.1 outside to 1.1 inside).
func _body_walks(g: Game, parts: LevelParts, tag: String) -> void:
	var stuck: Array = []
	for p: Dictionary in parts.pieces:
		for walk: Dictionary in p["walk_in"]:
			var a: Array = walk["from"]
			var b: Array = walk["to"]
			_place(g, a[0], a[1], g.world.floor_under(a[0], a[1], float(a[2]) + .3))
			_walk(g, Vector2(b[0], b[1]), 5.0)
			walks += 1
			var pl := g.player
			var here := Vector2(pl.x, pl.y)
			if (
				here.distance_to(Vector2(b[0], b[1])) < .4
				and absf(g.world.stand(pl) - float(b[2])) < .3
			):
				walked += 1
			else:
				stuck.append(
					"%s at %.1f, %.1f, %.2f" % [walk["door"], pl.x, pl.y, g.world.stand(pl)]
				)
	_check(
		stuck.is_empty(), "a body walks in through every doorway (%s) %s" % [tag, stuck.slice(0, 5)]
	)


func _game(main, id: String) -> Game:
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


# ---------------------------------------------------------------- refusals


func _refusals() -> void:
	print("refusals (one plain line each, nothing built)")
	var cases := [
		[{"piece": "mansion", "id": "a"}, "no kit piece named mansion"],
		[{"piece": "farmhouse"}, "farmhouse: a kit piece needs an id"],
		[{"piece": "farmhouse", "id": "a b"}, "farmhouse: an id is letters"],
		[{"piece": "farmhouse", "id": "a".repeat(41)}, "farmhouse: an id is 40 letters at most"],
		[{"piece": "farmhouse", "id": "a", "w": NAN}, "a: w is 7 to 14"],
		[{"piece": "farmhouse", "id": "a", "stories": 2}, "a: farmhouse takes no stories"],
		[{"piece": "farmhouse", "id": "a", "storeys": 9}, "a: storeys is 1 to 3"],
		[{"piece": "farmhouse", "id": "a", "storeys": 1.5}, "a: storeys is a whole number"],
		[{"piece": "farmhouse", "id": "a", "w": "big"}, "a: w is a number"],
		[{"piece": "farmhouse", "id": "a", "roof": "dome"}, "a: roof is one of"],
		[{"piece": "farmhouse", "id": "a", "porch": true}, "a: porch is a number"],
		[{"piece": "farmhouse", "id": "a", "chimney": 1}, "a: chimney is true or false"],
		[{"piece": "farmhouse", "id": "a", "style": "pink"}, "a: no style named pink"],
		[{"piece": "farmhouse", "id": "a", "x": 30}, "a: runs off the map"],
	]
	for case: Array in cases:
		var parts := LevelParts.new()
		parts.width = 32
		parts.height = 32
		var made := KitPiece.build(case[0], parts)
		var line := String(made.get("error", ""))
		_check(
			line.begins_with(case[1]) and parts.cost() == 0,
			"%s -> %s" % [JSON.stringify(case[0]), line]
		)
	var parts := LevelParts.new()
	KitPiece.build({"piece": "barn", "id": "barn", "x": 2, "y": 2}, parts)
	var cost := parts.cost()
	var made := KitPiece.build({"piece": "farmhouse", "id": "home", "x": 6, "y": 6}, parts)
	_check(
		(
			String(made.get("error", "")) == "home: stands on barn (move one of them)"
			and parts.cost() == cost
		),
		"a house on the barn -> %s" % made.get("error", "")
	)
	made = KitPiece.build({"piece": "fence", "id": "barn", "x": 30, "y": 2}, parts)
	_check(
		String(made.get("error", "")) == "barn: that id is taken",
		"an id used twice -> %s" % made.get("error", "")
	)
	made = KitPiece.build({"piece": "fence", "id": "rail", "x": 4, "y": 1, "w": 12}, parts)
	_check(not made.has("error"), "a fence may run past the barn (bits may meet buildings)")
	var a := LevelParts.new()
	var b := LevelParts.new()
	b.seed = 99
	KitPiece.build({"piece": "barn", "id": "barn", "x": 2, "y": 2}, a)
	KitPiece.build({"piece": "barn", "id": "barn", "x": 2, "y": 2}, b)
	_check(a.hash_text() != b.hash_text(), "another map's seed gives other looks (bales, variant)")


# --------------------------------------------------- the farmhouse in detail


## A 40 x 30 yard with a plain two-storey house over cells 10..17 x 6..11 (the
## ridge east-west at y 9), its ladder up the west gable, and a farmhouse.
static func house_level() -> Dictionary:
	var b = Builder.new(HOUSE, 44, 34, "hedgerow")
	var yard: int = b.district("TEST YARD")
	b.yard(1, 1, 42, 32, "dirt", yard)
	(
		Geo
		. kit(
			b,
			[
				{
					"piece": "house",
					"id": "house",
					"x": 10,
					"y": 6,
					"ladder": true,
					"doors": "s",
					"rooms": 1,
					"glass": false,
					"hung": false
				},
				{"piece": "farmhouse", "id": "home", "x": 26, "y": 14},
			]
		)
	)
	return b.finish([20.5, 24.5, 0.0])


## The house's north slope's top at y (eave 4.8, roof .15, pitch .6 from the
## wall line at y 6).
static func roof_top(y: float) -> float:
	return 4.8 + .15 + (y - 6.0) * .6


func _house(main) -> void:
	print("the plain house and the farmhouse in detail")
	LevelData.preview[HOUSE] = house_level()
	var g := _game(main, HOUSE)
	_open_doors(g)
	var w: LevelData = g.world
	_check(is_equal_approx(w.floor_under(15.5, 9.5, .5), 0.0), "inside, the ground floor is 0")
	_check(is_equal_approx(w.floor_under(15.5, 9.5, 3.0), 2.4), "and the upper floor 2.4")
	_check(
		absf(w.floor_under(14.5, 9.0, 8.0) - roof_top(9.0)) < .02,
		"the ridge's top is %.2f (want %.2f)" % [w.floor_under(14.5, 9.0, 8.0), roof_top(9.0)]
	)
	_check(w.blocked(12.5, 11.9, .2), "the south wall stops a body")
	_check(
		w.geo.solid_point(10.1, 9.0, 6.0, .02, false), "the gable is solid near the ridge at 6.0"
	)
	_check(
		not w.geo.solid_point(10.1, 6.3, 6.0, .02, false),
		"but not at its foot (the top rakes down)"
	)
	_check(not w.visible(14.5, 3.0, 14.5, 15.0, 1.0, 1.0), "the house stops a look across the yard")
	_check(not w.visible(14.5, 3.0, 14.5, 15.0, 6.0, 6.0), "the roof stops one at 6.0")
	_check(w.visible(14.5, 3.0, 14.5, 15.0, 7.2, 7.2), "a look over the ridge")
	_check(
		not w.visible(5.0, 9.0, 25.0, 9.0, 6.4, 6.4), "the gables stop one along the ridge under it"
	)
	_check(w.visible(13.5, 7.0, 13.5, 3.0, 3.35, 3.35), "a look out of an upper window (x 13.5)")
	_check(w.visible(11.5, 7.5, 11.5, 3.0, 1.3, 1.3), "and of a ground floor one (x 11.5)")
	_check(
		not w.visible(12.5, 7.5, 12.5, 3.0, 1.3, 1.3), "but not through the wall beside it (x 12.5)"
	)
	var p := g.player
	_place(g, 10.8, 11.5, 0.0)
	_walk(g, Vector2(10.75, 6.6), 6.0)
	_check(
		absf(w.stand(p) - 2.4) < .02,
		"climbed the inside stairs to the upper floor (%.2f)" % w.stand(p)
	)
	_walk(g, Vector2(15.5, 8.5), 4.0)
	_check(
		absf(w.stand(p) - 2.4) < .02 and p.x > 15.0,
		"and walked across it (x %.2f, z %.2f)" % [p.x, w.stand(p)]
	)
	_place(g, 9.0, 7.5, 0.0, 0.0)
	var held := [false]
	_walk(g, Vector2(11.0, 7.5), 8.0, func() -> void: held[0] = held[0] or p.ladder >= 0)
	_check(
		held[0] and w.stand(p) > 5.0,
		"up the ladder onto the roof (held %s, z %.2f)" % [held[0], w.stand(p)]
	)
	_place(g, 14.5, 6.4, roof_top(6.4))
	var high := [0.0]
	_walk(g, Vector2(14.5, 11.6), 8.0, func() -> void: high[0] = maxf(high[0], w.stand(p)))
	_check(
		p.y > 11.0 and absf(high[0] - roof_top(9.0)) < .05,
		"over the ridge (stood %.2f) and down to y %.2f" % [high[0], p.y]
	)
	_walk(g, Vector2(14.5, 13.5), 4.0)
	for _k in 120:
		g.tick(DT, Game.Controls.new())
	_check(absf(w.stand(p)) < .01, "off the eave down to the yard (z %.2f)" % w.stand(p))
	# The farmhouse: up its stairs and out of the balcony door onto the porch roof.
	_place(g, 26.75, 19.4, .2)
	_walk(g, Vector2(26.75, 14.8), 7.0)
	var up := w.stand(p)
	_check(absf(up - 2.6) < .05, "up the farmhouse's stairs (%.2f)" % up)
	_walk(g, Vector2(29.4, 17.5), 4.0)
	_walk(g, Vector2(30.6, 17.5), 3.0)
	_walk(g, Vector2(30.5, 21.6), 4.0)
	_check(
		p.y > 21.2 and w.stand(p) > 2.0,
		"and out of the balcony door onto the porch roof (y %.2f, z %.2f)" % [p.y, w.stand(p)]
	)
	var builder := LevelMesh.new(g.level)
	var mesh_parts := builder.build_static(g.level.active_base(false))
	var ridge := 0
	var gable := 0
	for key: Vector2i in mesh_parts:
		var mesh: ArrayMesh = mesh_parts[key]
		for surface in mesh.get_surface_count():
			for q: Vector3 in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				if absf(q.y - roof_top(9.0)) < .02 and absf(q.z - 9.0) < .02:
					ridge += 1
				if absf(q.x - 10.0) < .01 and q.y > 5.5 and q.y < 6.7:
					gable += 1
	_check(
		ridge >= 4 and gable >= 4,
		"the 3D mesh has the ridge (%d points) and the raked gable (%d)" % [ridge, gable]
	)
	LevelData.preview.erase(HOUSE)


# ------------------------------------------------------------------- town


## A town of the kit's plain houses over a 128 x 96 level (stress_bench town,
## cpu_check): 2 and 3 storeys, a door, windows every 2 cells, gable roofs.
static func town_level(id: String, houses: int) -> Dictionary:
	var b = Builder.new(id, 128, 96, "hedgerow")
	var yard: int = b.district("TOWN")
	b.yard(1, 1, 126, 94, "dirt", yard)
	var specs: Array = []
	var n := 0
	for row in 6:
		for col in 8:
			if n >= houses:
				break
			(
				specs
				. append(
					{
						"piece": "house",
						"id": "h%d" % n,
						"x": 4 + col * 15,
						"y": 4 + row * 15,
						"w": 8 + (col % 2) * 2,
						"d": 6 + (row % 2),
						"storeys": 2 if (row + col) % 3 else 3,
						"doors": "s",
						"rooms": 1,
						"hung": false,
						"glass": false,
						"area": yard,
					}
				)
			)
			n += 1
	if not specs.is_empty():
		Geo.kit(b, specs)
	for k in 40:
		b.enemy("billy", 3.5 + (k % 10) * 12.0, 2.5 + (k / 10) * 14.0 + 12.0, "b%d" % k)
	return b.finish([2.5, 2.5, 0.0])


func _town(main) -> void:
	print("a town of %d houses against the same level flat" % town_size)
	for which: String in [FLAT, TOWN]:
		var t0 := Time.get_ticks_usec()
		LevelData.preview[which] = town_level(which, town_size if which == TOWN else 0)
		var t_build := Time.get_ticks_usec() - t0
		t0 = Time.get_ticks_usec()
		var g := _game(main, which)
		var t_load := Time.get_ticks_usec() - t0
		t0 = Time.get_ticks_usec()
		var f := FlowField.new(g.world)
		var t_nav := Time.get_ticks_usec() - t0
		var geo := g.world.geo
		print(
			(
				"  %s: %d slabs %d segments; build %.1f ms, load %.1f ms, nav %.1f ms (%d nodes)"
				% [
					which,
					0 if geo == null else geo.slabs.size(),
					0 if geo == null else geo.segments.size(),
					t_build / 1000.0,
					t_load / 1000.0,
					t_nav / 1000.0,
					f.graph.count if f.graph != null else 0
				]
			)
		)
		LevelData.preview.erase(which)


# ----------------------------------------------------------------- pictures


## The two gallery levels and a tour: each piece from outside (front left),
## from inside its first doorway, and from its roof when it is meant to be
## climbed.
func _write_tour() -> void:
	DirAccess.make_dir_recursive_absolute(write_to)
	var count := 0
	for which in [["kit_min", "min", 0, false], ["kit_max", "max", 1, true]]:
		var shots: Array = []
		var made := gallery(which[0], which[1], which[2], which[3], 18)
		var lv: Dictionary = made[0]
		var parts: LevelParts = made[1]
		var f := FileAccess.open(write_to.path_join(which[0] + ".json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(lv))
		f.close()
		for p: Dictionary in parts.pieces:
			var fp: Array = p["footprint"]
			var c := Vector2((fp[0] + fp[2]) * .5, (fp[1] + fp[3]) * .5)
			var size := maxf(fp[2] - fp[0], fp[3] - fp[1])
			var out: Vector2 = KitFrame.DIRS.get(p["front"], Vector2(0, 1))
			var side := Vector2(-out.y, out.x)
			var eye := c + out * (size * 1.1 + 4.0) + side * (size * .4)
			eye = eye.clamp(Vector2(2.5, 2.5), Vector2(lv["width"] - 2.5, lv["height"] - 2.5))
			shots.append(
				_shot(
					which[0],
					"%s_%s_out" % [which[0], p["id"]],
					eye,
					c,
					0.0,
					10.0 if size > 9 else 4.0
				)
			)
			for walk: Dictionary in p["walk_in"]:
				var a: Array = walk["from"]
				var b: Array = walk["to"]
				var into := (
					Vector2(b[0], b[1])
					+ (Vector2(b[0], b[1]) - Vector2(a[0], a[1])).normalized() * .2
				)
				shots.append(
					_shot(
						which[0],
						"%s_%s_in" % [which[0], p["id"]],
						into - (Vector2(b[0], b[1]) - Vector2(a[0], a[1])) * .45,
						into + (into - Vector2(a[0], a[1])) * 3.0,
						float(b[2]),
						0.0
					)
				)
				break
			var roof: Dictionary = p["roof"]
			if roof.get("reach", false):
				var at: Array = roof["at"]
				shots.append(
					_shot(
						which[0],
						"%s_%s_roof" % [which[0], p["id"]],
						Vector2(at[0], at[1]),
						c + out * size,
						float(roof["z"]),
						-10.0
					)
				)
		var tour := FileAccess.open(write_to.path_join(which[0] + "_tour.json"), FileAccess.WRITE)
		tour.store_string(JSON.stringify(shots, " "))
		tour.close()
		count += shots.size()
	print("  wrote the galleries and their tours (%d viewpoints) to %s" % [count, write_to])


static func _shot(
	level: String, tag: String, eye: Vector2, look_at: Vector2, z: float, pitch: float
) -> Dictionary:
	return {
		"level": level,
		"tag": tag,
		"x": snappedf(eye.x, .01),
		"y": snappedf(eye.y, .01),
		"z": snappedf(z, .01),
		"angle": snappedf((look_at - eye).angle(), .001),
		"pitch": pitch,
		"weapon": false,
	}
