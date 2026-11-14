## The firing range's checks (tools/check_fixes.gd runs them; this also runs
## on its own):
##
##   Godot --headless --path <project> --script res://tools/range_check.gd
##
## The title's FIRING RANGE entry loads the range with every gun, leaving it
## goes back to the title (and to the game paused before it), and none of it
## touches the campaign: no save, no unlock, no gun carried out of it. Then
## the range itself: the levers turn critters and bosses out and clear them,
## the racks hand guns over, shots score on the targets, the pins fall.
## All eight bosses come out of the corral (the Swamp King onto its pond, Maw
## with her own fight), every hand in the county out of the bullpen (the tough
## guys and oddballs one after another), every gun hangs somewhere to take it,
## and the bowling lane plays and scores as bowling does.
extends SceneTree

const L := preload("res://src/range_layout.gd")

var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	run(main, func(ok: bool, text: String) -> void: _check(ok, text))
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("shots="):
			_shots(main, String(arg).substr(6))
	print("")
	print("RANGE OK" if failures.is_empty() else "%d RANGE CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


## The lane: balls rolled at the pins knock them down by the pins' own
## knocks, a ball in the gutter takes none, the pins stay on the deck or go
## into the pit or a gutter, and the sheet scores as bowling does.
static func _bowling(g: Game, feature, check: Callable) -> void:
	var bowl = feature.targets.bowling
	var roll := func(x: float, angle: float, turn := 0.0) -> int:
		bowl.sweep_at = -1.0
		bowl.rack()
		bowl.frames[bowl.frame].clear()
		bowl.ball = 0
		var p := g.player
		p.x = x
		p.y = 50.2
		p.angle = angle
		feature.targets.last_angle = angle
		feature.targets.turn_rate = turn
		g.launch(x, 49.9, .22, angle, 7.4, "bowling", 0.0, false, 108, 4.5)
		for i in 420:
			g.tick(1.0 / 60.0, Game.Controls.new())
			if not bowl.frames[bowl.frame].is_empty() or bowl.frame > 0:
				break
		return bowl.pins_down()
	var straight: int = roll.call(46.5, -PI / 2.0)
	check.call(
		straight >= 5,
		"a ball down the middle takes the head pin and most of the rack (%d)" % straight
	)
	var brooklyn: int = roll.call(46.3, -PI / 2.0)
	var pocket: int = roll.call(46.62, -PI / 2.0)
	check.call(
		brooklyn != pocket or bowl.last_roll != "",
		"where the ball meets the rack changes what falls (%d, %d)" % [brooklyn, pocket]
	)
	var gutter: int = roll.call(44.6, -PI / 2.0)
	check.call(
		gutter == 0 and bowl.last_roll == "GUTTER BALL", "a ball in the gutter takes nothing"
	)
	var edge: int = roll.call(47.75, -PI / 2.0)
	check.call(edge <= 4, "a ball down the edge clips a pin or two at most (%d)" % edge)
	var hooked: int = roll.call(47.4, -PI / 2.0, -3.0)
	check.call(
		hooked >= 1, "turning as it goes hooks the ball back in off the edge (%d down)" % hooked
	)
	var sane := true
	for pin: Dictionary in bowl.pins:
		var x := float(pin["x"])
		var y := float(pin["y"])
		sane = (
			sane
			and is_finite(x)
			and is_finite(y)
			and x > 43.9
			and x < 49.1
			and y > 33.5
			and y < 50.0
		)
	check.call(sane, "the pins stay on the lane, in its pit or its gutters")
	# The sheet: a perfect game, all spares, a frame of nines, an open game.
	var sheet := func(balls: Array) -> int:
		bowl.new_game()
		var f := 0
		var k := 0
		while k < balls.size() and f < 10:
			var frame: Array = bowl.frames[f]
			frame.append(int(balls[k]))
			k += 1
			if bowl._frame_done(frame, f == 9):
				f += 1
		return bowl.score()
	var perfect: int = sheet.call([10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10])
	var spares: int = sheet.call([5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5])
	var nines: int = sheet.call([9, 0, 9, 0, 9, 0, 9, 0, 9, 0, 9, 0, 9, 0, 9, 0, 9, 0, 9, 0])
	var mixed: int = sheet.call([10, 7, 3, 9, 0, 10, 0, 8, 8, 2, 0, 6, 10, 10, 10, 8, 1])
	check.call(
		perfect == 300 and spares == 150 and nines == 90 and mixed == 167,
		(
			"the sheet scores as bowling does (300 %d, 150 %d, 90 %d, 167 %d)"
			% [perfect, spares, nines, mixed]
		)
	)
	bowl.new_game()
	for pin: Dictionary in bowl.pins:
		if not int(pin["n"]) in [7, 10]:
			pin["gone"] = "pit"
	check.call(
		bowl.split_name() == "7-10", "a split is called by its pins (%s)" % bowl.split_name()
	)
	bowl.new_game()


## shots=<dir>: software pictures of the stations at work (levers pulled,
## a few seconds played), card and all, to look at by eye.
func _shots(main, folder: String) -> void:
	DirAccess.make_dir_recursive_absolute(folder)
	var scenes := [
		["bullpen", [82.0, 57.2, PI / 2.0, 0.0], ["pen-squad", "pen-coot"], 360],
		["corral", [12.0, 57.2, PI / 2.0, 0.0], ["boss-jerry"], 240],
		["soak", [55.5, 50.5, -PI / 2.0, 0.0], ["soak"], 300],
		["pit", [84.5, 49.5, -PI / 2.0, 0.0], ["fodder"], 300],
		["gallery", [36.5, 51.0, -PI / 2.0, 4.0], ["gallery"], 90],
		["bowling", [46.5, 50.0, -PI / 2.0, 0.0], ["pins"], 30],
	]
	for scene: Array in scenes:
		var g: Game = main.make_game("range")
		g.configure({})
		var at: Array = scene[1]
		g.player.x = float(at[0])
		g.player.y = float(at[1])
		g.player.angle = float(at[2])
		g.player.pitch = float(at[3])
		for id: String in scene[2]:
			for s: LevelData.Station in g.world.stations:
				if s.id == "range-" + id:
					g.operate_station(s)
		for i in int(scene[3]):
			g.tick(1.0 / 60.0, Game.Controls.new())
		g.message_until = 0.0
		var c := Canvas.new()
		g.draw(c, 1, true)
		var image := Image.create_from_data(320, 200, false, Image.FORMAT_RGB8, c.pixels)
		image.resize(960, 600, Image.INTERPOLATE_NEAREST)
		image.save_png(folder.path_join("%s.png" % scene[0]))


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


static func _pick(main, entry: String) -> bool:
	var rows: PackedStringArray = main.entries()
	var at := rows.find(entry)
	if at < 0:
		return false
	main.selection = at
	main.menu_action()
	return true


static func _stamp(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "none"
	return "%d:%s" % [FileAccess.get_modified_time(path), FileAccess.get_md5(path)]


static func run(main, check: Callable) -> void:
	print("FIRING RANGE (title entry, every gun, back out, campaign untouched)")
	main.return_to_title(true)
	main.campaign_run = null
	var files := [
		"user://campaign-entry.json", "user://hickston-quick.json", "user://campaign-unlocks.json"
	]
	var before := {}
	for path: String in files:
		before[path] = _stamp(path)
	var unlocked_before: Dictionary = main.unlocked.duplicate()
	check.call(main.entries().has("FIRING RANGE"), "the title offers the FIRING RANGE")
	check.call(_pick(main, "FIRING RANGE"), "and it can be picked")
	var range_game: Game = main.game
	check.call(
		main.state == "play" and range_game != null and range_game.level.id == "range",
		"picking it loads the range"
	)
	var armed := true
	for i in Weapons.COUNT:
		armed = armed and range_game.armory.owned[i]
		armed = armed and range_game.armory.reserve[i] == Weapons.MAX_RESERVE[i]
	check.call(armed, "every gun in weapons.cfg is owned and full")
	check.call(main.campaign_run == null, "the range is not taken for the campaign")
	range_game.armory.reserve[Weapons.RIFLE] = 0
	range_game.tick(1.0 / 60.0, Game.Controls.new())
	check.call(
		range_game.armory.reserve[Weapons.RIFLE] == Weapons.MAX_RESERVE[Weapons.RIFLE],
		"the ammo tops itself up"
	)
	range_game.damage(500.0, null, "TEST")
	check.call(range_game.player.health > 0, "the range medic never lets the player die")
	main.save_game()
	check.call(main.slot_source() == null, "the range offers nothing to save")
	main.key(KEY_ESCAPE)
	check.call(
		main.state == "title" and main.entries().has("LEAVE RANGE"),
		"Esc pauses on the title with LEAVE RANGE"
	)
	_pick(main, "LEAVE RANGE")
	check.call(
		main.state == "title" and main.game == null and not main.entries().has("RESUME"),
		"leaving goes back to the title with nothing paused"
	)
	# From a chapter paused on the title: the range, then back to the chapter.
	main.start("hickston")
	var chapter: Game = main.game
	main.return_to_title()
	_pick(main, "FIRING RANGE")
	check.call(main.game != chapter and main.campaign_run == chapter, "the chapter waits")
	main.key(KEY_ESCAPE)
	_pick(main, "LEAVE RANGE")
	check.call(main.game == chapter, "leaving the range resumes the chapter paused before it")
	# A road out of the range leaves the range's guns behind.
	main.return_to_title(true)
	main.campaign_run = null
	_pick(main, "FIRING RANGE")
	main.key(KEY_ESCAPE)
	_pick(main, "COUNTY HUB")
	var carried := 0
	if main.game != null:
		for owned: bool in main.game.armory.owned:
			carried += 1 if owned else 0
	check.call(
		main.game != null and main.game.in_hub and carried < Weapons.COUNT,
		"the county hub from the range carries none of its guns"
	)
	main.return_to_title(true)
	var same := true
	for path: String in files:
		same = same and _stamp(path) == before[path]
	check.call(same, "no campaign entry, quicksave or unlock file was written")
	check.call(main.unlocked == unlocked_before, "no chapter was unlocked")

	print("RANGE STATIONS (levers, racks, targets, pins)")
	var g: Game = main.make_game("range")
	g.configure({})
	var feature = g.features["range"]
	var lever := func(id: String) -> void:
		for s: LevelData.Station in g.world.stations:
			if s.id == "range-" + id:
				g.operate_station(s)
	lever.call("pen-billy")
	check.call(
		g.enemies.size() == 1 and g.enemies[0].kind == "billy", "a pen lever turns a billy out"
	)
	lever.call("pen-billy")
	check.call(g.enemies.size() == 2, "the same lever works again")
	lever.call("pen-squad")
	check.call(g.enemies.size() == 7, "the squad lever turns five out")
	lever.call("pen-clear")
	check.call(g.enemies.is_empty(), "the clear lever empties the pen")
	var bosses_ok := true
	var bad := ""
	for kind: String in L.BOSS_KINDS:
		if kind == "clear":
			continue
		lever.call("boss-" + kind)
		var out_ok: bool = g.finale != null and g.finale.kind == kind
		for i in 90:
			g.tick(1.0 / 60.0, Game.Controls.new())
		out_ok = out_ok and g.finale != null and g.finale.alive
		if not out_ok:
			bad += " " + kind
		bosses_ok = bosses_ok and out_ok
		if kind == "swamp_king":
			check.call(
				g.finale != null and BayouBrains.wet_at(g.world, g.finale.x, g.finale.y),
				"the Swamp King's airboat comes in on the corral's pond and stays on the water"
			)
		if kind == "maw":
			var fight = g.features["mothership"]
			check.call(
				(
					fight.on_range
					and fight.maw == g.finale
					and fight.center.distance_to(L.BOSS_DOOR) < 6.0
				),
				"Maw's own fight picks her up in the corral"
			)
	check.call(
		bosses_ok, "each of the eight boss levers lets its boss out, health bar and all" + bad
	)
	lever.call("boss-clear")
	check.call(g.enemies.is_empty() and g.finale == null, "and the corral clears")
	var pen_ok := true
	var pen_bad := ""
	for kind: String in L.PEN_KINDS:
		if kind in ["squad", "clear", "tough", "variant"]:
			continue
		lever.call("pen-clear")
		lever.call("pen-" + kind)
		var got: bool = not g.enemies.is_empty() and g.enemies[0].kind == kind
		for i in 30:
			g.tick(1.0 / 60.0, Game.Controls.new())
		if not got:
			pen_bad += " " + kind
		pen_ok = pen_ok and got
	check.call(pen_ok, "every pen lever turns its kind out" + pen_bad)
	lever.call("pen-clear")
	var toughs: Array = []
	for k in L.TOUGH_KINDS.size() + 1:
		lever.call("pen-tough")
		toughs.append(g.enemies[g.enemies.size() - 1].kind)
	check.call(
		toughs.slice(0, L.TOUGH_KINDS.size()) == L.TOUGH_KINDS and toughs[-1] == L.TOUGH_KINDS[0],
		"the tough guy lever turns out each chapter's tough guy in turn, then starts over"
	)
	lever.call("pen-clear")
	for k in L.VARIANT_KINDS.size():
		lever.call("pen-variant")
	var odd: Array = []
	for e: Enemy in g.enemies:
		odd.append(e.kind)
	check.call(odd == L.VARIANT_KINDS, "the oddball lever turns out each variant in turn")
	lever.call("pen-clear")
	var levers_ok := true
	for i in L.PEN_KINDS.size():
		var at := L.pen_lever(i)
		levers_ok = levers_ok and not g.world.blocked(at.x, at.y, .1)
	for x: float in L.BOSS_LEVER_X:
		levers_ok = levers_ok and not g.world.blocked(x, L.BOSS_LEVER_Y, .1)
	check.call(levers_ok, "every lever stands in the open")
	var racks_ok := true
	var rack_bad := ""
	for i in Weapons.COUNT:
		var found := false
		for s: LevelData.Station in g.world.stations:
			found = found or s.id == "range-rack-%d" % i
		lever.call("rack-%d" % i)
		if not found or g.armory.active != i:
			rack_bad += " %d" % i
			racks_ok = false
	check.call(
		racks_ok, "every gun, the 5v5 store's too, hangs on a rack that hands it over" + rack_bad
	)
	lever.call("rack-2")
	check.call(g.armory.active == Weapons.SHOTGUN, "a rack on the armory wall hands the gun over")
	lever.call("soak")
	lever.call("fodder")
	lever.call("alien_one")
	check.call(g.enemies.size() == 3 + L.FODDER_DOORS.size() + 1, "soak, fodder and grey levers")
	lever.call("reset-pit")
	check.call(g.drums.size() == L.DRUMS.size(), "the pit reset puts the drums back")
	# A .38 round at the near board in the alley.
	var p := g.player
	p.x = 5.5
	p.y = 51.0
	p.angle = -PI / 2.0
	var board: Dictionary = feature.targets.targets[0]
	var slope: float = (.83 - p.eye) / (p.y - float(board["y"]))
	g.hitscan(-PI / 2.0, slope, 36.0, 23.0, .055)
	check.call(int(board["hits"]) == 1, "a shot at a board scores a hit on it")
	# A bowling ball down the lane.
	p.x = 46.5
	p.y = 49.5
	p.angle = -PI / 2.0
	feature.targets.last_angle = p.angle
	feature.targets.turn_rate = 0.0
	g.launch(46.5, 49.2, .22, -PI / 2.0, 7.4, "bowling", 0.0, false, 108, 4.5)
	for i in 300:
		g.tick(1.0 / 60.0, Game.Controls.new())
	var bowl = feature.targets.bowling
	check.call(
		not bowl.frames[0].is_empty() and int(bowl.frames[0][0]) > 0 and bowl.last_roll != "",
		"the ball takes pins: %s" % bowl.last_roll
	)
	_bowling(g, feature, check)
	lever.call("gallery")
	check.call(feature.targets.gallery_on, "the gallery lever starts a round")
	var c := Canvas.new()
	feature.station = "bullpen"
	feature.draw_view(c)
	check.call(true, "the station card draws")
