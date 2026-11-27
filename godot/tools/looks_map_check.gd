## Checks of the looks layer a map opts into (pass 16, LOOKS: src/map_kit/
## map_looks.gd, foliage.gd, dressing.gd, water.gd, set_piece_hooks.gd and
## features/area_moods.gd), on tools/looks_demo.gd's 64 x 48 farm:
##
## - no chapter names a mood, so every chapter's view reads its own
##   effects.cfg values as before (the moods feature idle, now() empty);
## - moods by area: each district shows its mood's values, the view eases
##   from one to the next over [moods] blend seconds and snaps on a jump, the
##   3D view's fog and grade (WorldView3D._effects) take them, rain is held
##   off under a mood that keeps it off, and none of it touches game.rng;
## - foliage: the same objects give the same plants, another seed others;
##   every plant on its kind's ground, in the open, clear of the way, the
##   doors, the objectives, the spawn and the roads; only trunks block; the
##   map's and every block's plant budget held, and no view sees more than
##   budget.most_seen of them; every picture packed;
## - vignettes: each against a wall, clear of the way and the doors, the same
##   from the same seed, other seeds other spots, the vignette objects a dress
##   object hands back standing the same as written, every prop a model;
## - water: a pond's water flat in its bed with deep water in the middle
##   (nobody wades in), a creek in its bed under the road with a railed
##   bridge a body stands on, a trough, the terrain version 2;
## - set pieces: the demo's tower stands in play; a barn on a house is
##   refused;
## - odd input (an unknown kind, theme, mood or type; a bad area or shape)
##   gives its code and a plain line; an empty looks changes nothing;
## - every objective still reached once the looks are on.
##
##   godot --headless --path godot --script res://tools/looks_map_check.gd
##   godot --headless --path godot --script res://tools/looks_map_check.gd -- write=<level.json>
##
## write= writes the demo level (for tools/map/map_pictures.gd's window
## tour) and quits. Prints LOOKS MAP CHECK OK (check_all runs it).
extends SceneTree

const Demo := preload("res://tools/looks_demo.gd")
const STEP := 1.0 / 60.0

var main
var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, text: String) -> void:
	print("  ok   " if condition else "  FAIL ", text)
	if not condition:
		failures.append(text)


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("write="):
			var f := FileAccess.open(arg.substr(6), FileAccess.WRITE)
			f.store_string(JSON.stringify(Demo.level()))
			f.close()
			print("LOOKS DEMO WRITTEN")
			main.queue_free()
			await process_frame
			quit(0)
			return
	var report := {}
	var t0 := Time.get_ticks_msec()
	var lv := Demo.level(Demo.ID, false, report)
	print("the demo built in %d ms (%s)" % [Time.get_ticks_msec() - t0, report["ms"]])
	_chapters()
	_moods(lv)
	_foliage(lv, report)
	_vignettes(report)
	_water(lv)
	_set_pieces(lv)
	_odd()
	_reach(lv, report)
	LevelData.preview.erase(Demo.ID)
	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("LOOKS MAP CHECK OK")
	else:
		print("LOOKS MAP CHECK FAILED: %d" % failures.size())
		for f: String in failures:
			print("   - ", f)
	quit(0 if failures.is_empty() else 1)


func _game(id: String) -> Game:
	var g: Game = main.make_game(id)
	g.configure({"difficulty": 1, "events": 0})
	g.lessons = false
	g.cheats.god = true
	for e: Enemy in g.enemies:
		e.dormant = true
	return g


## Every level in data/ names no mood, and a chapter's game has its moods idle.
func _chapters() -> void:
	print("\nTHE CHAPTERS")
	var named := []
	var dir := DirAccess.open("res://data")
	for file in dir.get_files():
		if not file.ends_with(".json") or file == "index.json":
			continue
		var text := FileAccess.get_file_as_string("res://data/" + file)
		if text.contains('"area_moods"') or text.contains('"mood"'):
			named.append(file)
	check(named.is_empty(), "no level in data/ names a mood %s" % [named])
	for id: String in ["hickston", "bayou", "moonshine", "mothership", "grainyard"]:
		var g := _game(id)
		var moods: AreaMoodsFeature = g.features.get("moods")
		check(
			(
				moods != null
				and not moods.active
				and moods.now(g.player.x, g.player.y, 1.0).is_empty()
			),
			"%s: the moods feature is idle (the view keeps the level's own fog and grade)" % id
		)
	for name: String in [
		"farm_dusk",
		"barn_dark",
		"church_still",
		"holler_fog",
		"bayou_night",
		"store_fluorescent",
		"mothership_glow"
	]:
		check(Effects.MOODS.has(name), "the %s preset is there" % name)


func _moods(lv: Dictionary) -> void:
	print("\nMOODS BY AREA")
	LevelData.preview[Demo.ID] = lv
	var g := _game(Demo.ID)
	var moods: AreaMoodsFeature = g.features.get("moods")
	check(moods != null and moods.active, "the demo's moods are on")
	var rng_before := var_to_str(g.rng)
	var districts: Array = lv["districts"]
	var woods := districts.find("THE WOODS")
	var barn := districts.find("THE BARN")
	check(woods > 0 and barn > 0, "the demo's districts are there")
	var want: Color = Effects.preset("farm_dusk", "fog", Color.BLACK)
	var fog: Color = moods.values_for(0)["fog"]
	check(fog.is_equal_approx(want), "the fields take the level's mood, farm dusk (%s)" % fog)
	var w := moods.values_for(woods)
	var wfog: Color = w["fog"]
	check(
		wfog.is_equal_approx(Effects.preset("holler_fog", "fog", Color.BLACK)),
		"the woods take holler fog (%s)" % wfog
	)
	var b := moods.values_for(barn)
	check(
		float(b["rain"]) == 0.0 and not bool(b["crows"]), "the barn draws no rain and has no crows"
	)
	check(float(w["fog_banks"]) > 0.0, "fog banks roll in the woods (%.2f)" % float(w["fog_banks"]))
	var clock := 10.0
	var now := moods.now(20.5, 37.5, clock)
	check((now["fog"] as Color).is_equal_approx(want), "standing in the fields: farm dusk")
	clock += .5
	moods.now(17.5, 37.5, clock)
	clock += .5
	now = moods.now(Demo.WOODS_EDGE - .5, 37.5, clock)
	check(
		(now["fog"] as Color).is_equal_approx(want),
		"a step into the woods starts the blend from the fields"
	)
	var blend: float = Effects.MOOD_BLEND.get("blend", 1.5)
	clock += blend * .5
	now = moods.now(Demo.WOODS_EDGE - 1.0, 37.5, clock)
	var mid: Color = now["fog"]
	var share := (mid.r - want.r) / (wfog.r - want.r)
	check(share > .2 and share < .8, "half way through the blend it is in between (%.2f)" % share)
	clock += blend
	now = moods.now(Demo.WOODS_EDGE - 1.5, 37.5, clock)
	check((now["fog"] as Color).is_equal_approx(wfog), "after %.1f s it is holler fog" % blend)
	clock += STEP
	now = moods.now(46.5, 10.5, clock)
	var barn_fog: Color = Effects.preset("barn_dark", "fog", Color.BLACK)
	check(
		(now["fog"] as Color).is_equal_approx(barn_fog),
		"a jump into the barn takes its mood at once"
	)
	# The view: a 3D view made by hand draws the frame with the mood's numbers.
	var view := WorldView3D.new(g.art)
	main.add_child(view)
	main.game = g
	main.state = "play"
	g.player.x = 47.5
	g.player.y = 10.5
	g.clock += 5.0
	_draw(view, g)
	var shared: Variant = view.shared("fog_color")
	check(
		(
			shared is Vector3
			and (shared as Vector3).is_equal_approx(Vector3(barn_fog.r, barn_fog.g, barn_fog.b))
		),
		"the 3D view's fog is the barn's (%s)" % [shared]
	)
	var grade: Variant = view.shared("grade")
	var barn_grade: Color = Effects.preset("barn_dark", "grade", Color.WHITE)
	check(
		(
			grade is Vector3
			and (grade as Vector3).is_equal_approx(
				Vector3(barn_grade.r, barn_grade.g, barn_grade.b)
			)
		),
		"and its grade (%s)" % [grade]
	)
	var weather = g.features.get("weather")
	weather.hold(1.0, 1.0, 0.0)
	_draw(view, g)
	var drawn: Variant = view.shared("rain")
	check(drawn is float and float(drawn) == 0.0, "rain held off in the barn (%s)" % [drawn])
	g.player.x = 20.5
	g.player.y = 37.5
	g.clock += 5.0
	_draw(view, g)
	drawn = view.shared("rain")
	check(drawn is float and float(drawn) > .5, "and drawn in the fields (%s)" % [drawn])
	view.queue_free()
	check(var_to_str(g.rng) == rng_before, "none of it touches game.rng")
	# A chapter's view: the numbers it always had.
	var h := _game("hickston")
	var hv := WorldView3D.new(h.art)
	main.add_child(hv)
	main.game = h
	_draw(hv, h)
	var hfog: Color = Effects.mood("hickston", "fog", Color.BLACK)
	var hs: Variant = hv.shared("fog_color")
	check(
		hs is Vector3 and (hs as Vector3).is_equal_approx(Vector3(hfog.r, hfog.g, hfog.b)),
		"hickston's view keeps its own fog"
	)
	hv.queue_free()
	main.game = null
	main.state = "title"


## The frame as the game lists it (main.render), drawn by a view made by hand
## (headless the game draws none: stress_bench's check does the same).
func _draw(view: WorldView3D, g: Game) -> void:
	main.render()
	view.frame(g)


func _foliage(lv: Dictionary, report: Dictionary) -> void:
	print("\nFOLIAGE")
	var again := Demo.level()
	check(
		JSON.stringify(again) == JSON.stringify(lv),
		"the same looks give the same level, plant for plant"
	)
	print("    level hash %s" % JSON.stringify(lv).sha256_text().substr(0, 12))
	var other := Demo.bare()
	var looks := Demo.looks()
	for f: Dictionary in looks["foliage"]:
		f["seed"] = int(f["seed"]) + 100
	MapLooks.apply(other, looks)
	check(
		JSON.stringify(_plants(other)) != JSON.stringify(_plants(lv)), "another seed, other plants"
	)
	var pictures := MapFoliage.pictures()
	var plants := _plants(lv)
	check(
		plants.size() == int(report["plants"]), "the report counts the plants (%d)" % plants.size()
	)
	# The ground rules, against the level as it was before the plants (its
	# way and things, the water and set pieces in).
	var before := Demo.bare()
	var no_plants := Demo.looks()
	no_plants["foliage"] = []
	MapLooks.apply(before, no_plants)
	var grid := MapLooksGrid.of(before)
	var kinds: Dictionary = MapLooksGrid.tuning()["foliage"]
	var clear: Dictionary = MapLooksGrid.tuning()["clear"]
	var roads: Array = MapLooksGrid.tuning()["roads"]
	var natural: Array = MapLooksGrid.tuning()["natural"]
	var bad := {}
	for b: Dictionary in plants:
		var x := float(b["x"])
		var y := float(b["y"])
		var kind: String = pictures[b["image"]]
		var info: Dictionary = kinds[kind]
		var c := grid.cell(x, y)
		var ground: Array = info.get("ground", natural)
		if not ground.has(grid.floor_name(c)):
			bad["not on its ground"] = "%s at %.1f,%.1f on %s" % [kind, x, y, grid.floor_name(c)]
		if grid.roof[c] > 0.0 or grid.covered[c] != 0:
			bad["under a roof"] = "%s at %.1f,%.1f" % [kind, x, y]
		if grid.route_distance(x, y) < float(clear["route"]) - .01:
			bad["on the way"] = "%s at %.1f,%.1f (%.2f)" % [kind, x, y, grid.route_distance(x, y)]
		if grid.distance_to_floor(x, y, roads, 2.0) < float(clear["road"]) - .01:
			bad["by a road"] = "%s at %.1f,%.1f" % [kind, x, y]
		for d: Dictionary in before["doors"]:
			if (
				Vector2(x, y).distance_to(Vector2(float(d["x"]) + .5, float(d["y"]) + .5))
				< float(clear["door"])
			):
				bad["at a door"] = "%s at %.1f,%.1f" % [kind, x, y]
		for p in grid.spawns():
			if Vector2(x, y).distance_to(p) < float(clear["spawn"]):
				bad["at the spawn"] = "%s at %.1f,%.1f" % [kind, x, y]
		for p in grid.objectives():
			if Vector2(x, y).distance_to(p) < float(clear["objective"]):
				bad["at an objective"] = "%s at %.1f,%.1f" % [kind, x, y]
	check(
		bad.is_empty(),
		(
			"every plant on its ground, in the open, off the way, doors, objectives, spawn and roads %s"
			% [bad]
		)
	)
	var trunks := 0
	for b: Dictionary in plants:
		var info: Dictionary = kinds[pictures[b["image"]]]
		trunks += 1 if float(info.get("block", 0.0)) > 0.0 else 0
	var bases := 0
	for f: Array in lv["collision_volumes"]:
		bases += 1 if float(f[4]) - float(f[7]) < .06 else 0
	check(
		trunks > 0 and bases >= trunks,
		"only the trunks block: %d trunks, %d low bases in all" % [trunks, bases]
	)
	# The budget, on the dense demo.
	var most := int(MapLooksGrid.num("budget", "most", 360))
	var thick := _plants(Demo.level(Demo.ID, true))
	check(
		thick.size() <= most,
		"the dense demo holds the map's budget (%d of %d)" % [thick.size(), most]
	)
	var block := int(MapLooksGrid.num("budget", "block", 6))
	var per := {}
	for b: Dictionary in thick:
		var key := Vector2i(int(float(b["x"])) / block, int(float(b["y"])) / block)
		per[key] = int(per.get(key, 0)) + 1
	var worst := 0
	for k: Vector2i in per:
		worst = maxi(worst, int(per[k]))
	var most_block := int(MapLooksGrid.num("budget", "most_block", 16))
	check(
		worst <= most_block,
		"no %d-cell square holds more than %d plants (%d)" % [block, most_block, worst]
	)
	var most_seen := int(MapLooksGrid.num("budget", "most_seen", 170))
	var seen := _most_seen(thick)
	check(seen <= most_seen, "no view sees more than %d plants (the most: %d)" % [most_seen, seen])
	var art: Assets = main.make_game("hickston").art
	var missing := []
	for p: String in pictures:
		if not art.has_art(p):
			missing.append(p)
	check(missing.is_empty(), "every foliage picture is packed %s" % [missing])


func _plants(lv: Dictionary) -> Array:
	var pictures := MapFoliage.pictures()
	var out := []
	for b: Dictionary in lv["billboards"]:
		if pictures.has(b["image"]):
			out.append(b)
	return out


## The most plants within budget.count_reach of a viewer in a 100 degree
## cone, from every other cell, eight ways.
func _most_seen(plants: Array) -> int:
	var reach := MapLooksGrid.num("budget", "count_reach", 24.0)
	var cone := cos(deg_to_rad(50.0))
	var most := 0
	for y in range(1, Demo.H - 1, 2):
		for x in range(1, Demo.W - 1, 2):
			for k in 8:
				var look := Vector2.from_angle(k * TAU / 8.0)
				var n := 0
				for b: Dictionary in plants:
					var d := Vector2(float(b["x"]) - x - .5, float(b["y"]) - y - .5)
					if d.length() < reach and d.normalized().dot(look) > cone:
						n += 1
				most = maxi(most, n)
	return most


func _vignettes(report: Dictionary) -> void:
	print("\nVIGNETTES")
	var placed: Array = report["vignettes"]
	check(placed.size() >= 3, "the dress objects placed %d vignettes" % placed.size())
	var before := Demo.bare()
	var no_dress := Demo.looks()
	no_dress["dress"] = []
	no_dress["foliage"] = []
	MapLooks.apply(before, no_dress)
	var grid := MapLooksGrid.of(before)
	var all := MapDressing.vignettes()
	var bad := []
	for p: Dictionary in placed:
		var at := Vector2i(int(p["at"][0]), int(p["at"][1]))
		var why := MapDressing.fits(grid, all[p["id"]], at, p["wall"])
		if why != "":
			bad.append("%s at %s: %s" % [p["id"], p["at"], why])
	check(bad.is_empty(), "each stands against a wall, off the way, clear of the doors %s" % [bad])
	var again := Demo.bare()
	var r2 := MapLooks.apply(again, Demo.looks())
	check(
		JSON.stringify(r2["vignettes"]) == JSON.stringify(placed),
		"the same seeds, the same vignettes"
	)
	var other := Demo.bare()
	var looks := Demo.looks()
	for d: Dictionary in looks["dress"]:
		d["seed"] = int(d["seed"]) + 7
	var r3 := MapLooks.apply(other, looks)
	check(JSON.stringify(r3["vignettes"]) != JSON.stringify(placed), "other seeds, other spots")
	# What a dress object hands back stands the same written as vignettes.
	var dressed := Demo.bare()
	var only_dress := Demo.looks()
	only_dress["foliage"] = []
	var r4 := MapLooks.apply(dressed, only_dress)
	var redo := Demo.bare()
	var explicit := Demo.looks()
	explicit["foliage"] = []
	explicit["dress"] = []
	explicit["vignettes"] = r4["vignettes"]
	MapLooks.apply(redo, explicit)
	check(
		JSON.stringify(redo["billboards"]) == JSON.stringify(dressed["billboards"]),
		"the vignette objects a dress object returns stand the same as written"
	)
	var themes: Array = MapLooksGrid.tuning()["themes"]
	var wrong := []
	for id: String in all:
		var v: Dictionary = all[id]
		for t: String in v["themes"]:
			if not themes.has(t):
				wrong.append("%s theme %s" % [id, t])
		for it: Dictionary in v["items"]:
			if it.has("prop") and MapDressing.prop_size(it["prop"]).is_empty():
				wrong.append("%s prop %s" % [id, it["prop"]])
		if not ["outside", "inside", "any"].has(v["where"]):
			wrong.append("%s where %s" % [id, v["where"]])
	check(wrong.is_empty(), "every vignette's props are models, its themes listed %s" % [wrong])
	for theme: String in themes:
		var n := 0
		for id: String in all:
			n += 1 if (all[id]["themes"] as Array).has(theme) else 0
		check(n >= 1, "theme %s has vignettes (%d)" % [theme, n])


func _water(lv: Dictionary) -> void:
	print("\nWATER")
	var geo: Dictionary = lv["geometry"]
	check(
		int(geo["version"]) == 2 and (geo["terrain"] as Array).size() >= 2,
		"the beds are terrain in a version 2 block"
	)
	LevelData.preview[Demo.ID] = lv
	var g := _game(Demo.ID)
	var world := g.world
	var terrain: LevelTerrain = world.geo.terrain
	check(world.deep_at(22.5, 37.5), "the pond's middle is deep water nobody wades")
	var z := terrain.height_at(22.5, 34.5)
	check(absf(z + .35) < .02, "its shallows lie .35 down (%.2f)" % z)
	check(absf(z - terrain.height_at(22.8, 34.7)) < .01, "a pond's water is flat")
	check(
		terrain.height_at(22.5, 37.5) < -.6,
		"the deep goes down (%.2f)" % terrain.height_at(22.5, 37.5)
	)
	var cz := terrain.height_at(10.5, 24.0)
	check(cz < -.2, "the creek runs in its bed (%.2f)" % cz)
	var bridge := false
	for s: Dictionary in geo["slabs"]:
		if str(s["id"]).begins_with("bridge") and float(s["x0"]) <= 31.5 and float(s["x1"]) >= 31.5:
			bridge = true
	check(bridge, "a bridge carries the road over the creek")
	var rails := 0
	for s: Dictionary in geo["segments"]:
		rails += 1 if str(s["id"]).begins_with("bridge") else 0
	check(rails == 2, "railed on its two sides over the water (%d)" % rails)
	var crossing := -1.0
	for y in range(18, 30):
		if terrain.has(31.5, y + .5) and terrain.height_at(31.5, y + .5) < -.2:
			crossing = y + .5
	check(crossing > 0.0, "the road is carved where the creek crosses it (y %.1f)" % crossing)
	var p := g.player
	p.x = 31.5
	p.y = crossing
	p.floor_z = world.floor_under(p.x, p.y, .5)
	check(p.floor_z > -.05, "a body on the bridge stands on its deck (%.2f)" % p.floor_z)
	for i in 30:
		g.tick(STEP, Game.Controls.new())
	check(p.floor_z > -.05 and absf(p.y - crossing) < .5, "and stays there (%.2f)" % p.floor_z)
	var trough := false
	for f: Array in lv["fixtures"]:
		trough = trough or (str(f[6]) == "creek" and absf(float(f[4]) - .45) < .01)
	check(trough, "the trough stands with water in it")


func _set_pieces(lv: Dictionary) -> void:
	print("\nSET PIECES")
	var pieces: Array = lv.get("set_pieces", [])
	check(
		pieces.size() == 1 and pieces[0]["kind"] == "tower",
		"the demo's water tower is in the level"
	)
	LevelData.preview[Demo.ID] = lv
	var g := _game(Demo.ID)
	var sp = g.features.get("set_pieces")
	check(sp != null and sp.pieces.size() == 1, "and stands in play")
	var bad := Demo.bare()
	var r := MapLooks.apply(
		bad, {"set_pieces": [{"kind": "barn", "id": "in_house", "at": [10.5, 9.5]}]}
	)
	check(
		_codes(r).has("set_piece_spot") and not bad.has("set_pieces"),
		"a barn on the house is refused: %s" % _line(r, "set_piece_spot")
	)


func _odd() -> void:
	print("\nODD INPUT")
	var plain := Demo.bare()
	var copy := plain.duplicate(true)
	MapLooks.apply(plain, {})
	check(JSON.stringify(plain) == JSON.stringify(copy), "an empty looks changes nothing")
	var cases := {
		"foliage_kind": {"foliage": [{"kind": "kudzu"}]},
		"foliage_area": {"foliage": [{"kind": "grass", "area": [200, 200, 300, 300]}]},
		"dress_theme": {"dress": [{"theme": "disco"}]},
		"mood_unknown": {"mood": "sunny"},
		"mood_area": {"area_moods": {"THE MOON": "farm_dusk"}},
		"water_type": {"water": [{"type": "ocean"}]},
		"water_shape": {"water": [{"type": "creek", "points": [[1, 1]]}]},
		"set_piece_kind": {"set_pieces": [{"kind": "volcano"}]},
		"vignette": {"vignettes": [{"id": "hot_tub", "at": [3, 3], "wall": "n"}]},
		"area_rect": {"areas": [{"name": "NOWHERE"}]},
	}
	for code: String in cases:
		var lv := Demo.bare()
		var r := MapLooks.apply(lv, cases[code])
		check(_codes(r).has(code), "%s: %s" % [code, _line(r, code)])
	var lv := Demo.bare()
	MapLooks.apply(lv, {"mood": "sunny"})
	check(not lv.has("mood"), "an unknown mood is left out")


func _reach(lv: Dictionary, report: Dictionary) -> void:
	print("\nTHE WAY")
	check(not _codes(report).has("looks_blocked"), "the looks shut nothing off")
	check(report["problems"].is_empty(), "the demo builds with no problems %s" % [_codes(report)])
	var grid := MapLooksGrid.of(lv)
	var from := grid.cell(grid.spawns()[0].x, grid.spawns()[0].y)
	var all := true
	for goal in grid.objectives():
		all = all and not grid.way(from, grid.cell(goal.x, goal.y)).is_empty()
	check(all, "the start still walks to the lever, the truck and the tower")


static func _codes(report: Dictionary) -> Array:
	var out := []
	for p: Array in report.get("problems", []):
		out.append(p[0])
	return out


static func _line(report: Dictionary, code: String) -> String:
	for p: Array in report.get("problems", []):
		if p[0] == code:
			return str(p[1])
	return ""
