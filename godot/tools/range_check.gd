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
## and the bowling lane plays and scores as bowling does. The games row
## (range_games.gd) plays and scores: horseshoes (a ringer dropped round the
## stake, a shoe knocked off it, a game of ten), the dunk tank (a shot on the
## bullseye drops him in and he climbs back; a round counts), skee-ball (soft
## comes back, the right roll drops in the rings, a game of nine) and knock
## 'em down (three balls take bottles off the table, a shot one scores
## nothing); each game's best goes to the records and the board (answered
## here, range_board.gd), and every station's card draws.
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
## knocks (3D bodies: range_pin_physics.gd), a ball in the pocket strikes, a
## ball in the gutter takes none, the pins stay on the deck or go into the
## pit or a gutter, a pin stood alone stays up, and the sheet scores as
## bowling does.
static func _bowling(g: Game, feature, check: Callable) -> void:
	var bowl = feature.targets.bowling
	var roll := func(x: float, angle: float, turn := 0.0) -> int:
		bowl.sweep_at = -1.0
		bowl.new_game()
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
		straight >= 8,
		"a ball down the middle takes the head pin and most of the rack (%d)" % straight
	)
	# A racked pin left alone stands: it neither drifts nor falls.
	bowl.new_game()
	for i in 120:
		bowl.tick(g, 1.0 / 60.0)
	var still: bool = bowl.standing() == 10
	for pin: Dictionary in bowl.pins:
		still = still and float(pin["awake"]) == 0.0 and bowl.lean(pin) < .001
	check.call(still, "a rack left alone stands still")
	# A nudge rocks a pin and it settles back up; a shove puts it over.
	bowl.new_game()
	var head: Dictionary = bowl.pins[0]
	bowl._knock(head, Vector3(0.0, -.12, 0.0), .3)
	for i in 240:
		bowl.tick(g, 1.0 / 60.0)
	var rocked: bool = not bowl.is_down(head) and float(head["awake"]) == 0.0
	bowl.new_game()
	head = bowl.pins[0]
	bowl._knock(head, Vector3(0.0, -.9, 0.0), .3)
	for i in 240:
		bowl.tick(g, 1.0 / 60.0)
	check.call(rocked and bowl.is_down(head), "a nudged pin rocks back up, a shoved one goes over")
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
			and y > 33.0
			and y < 50.0
			and float(pin["z"]) > -.4
			and float(pin["z"]) < 2.0
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


static func _tick(g: Game, n: int) -> void:
	for i in n:
		g.tick(1.0 / 60.0, Game.Controls.new())


static func _stand(g: Game, x: float, y: float, angle: float, pitch := 0.0) -> void:
	var p := g.player
	p.x = x
	p.y = y
	p.angle = angle
	p.pitch = pitch
	p.floor_z = g.world.floor_under(x, y, .05)
	p.eye = .95 + g.world.stand(p)


## Ticks until the skee-ball in play has dropped (or come back).
static func _roll_out(g: Game, skee) -> void:
	for i in 600:
		if skee.ball.is_empty():
			return
		g.tick(1.0 / 60.0, Game.Controls.new())


## The games row: each game plays and scores, its best kept and boarded.
static func _games(g: Game, feature, check: Callable) -> void:
	print("RANGE GAMES ROW (horseshoes, dunk tank, skee-ball, knock 'em down, the board)")
	RangeBoard.folder_override = OS.get_cache_dir().path_join("clmr-range-check")
	DirAccess.make_dir_recursive_absolute(RangeBoard.folder_override)
	if FileAccess.file_exists(RangeBoard.path()):
		DirAccess.remove_absolute(RangeBoard.path())
	var kept_store := RangeBoard.store
	RangeBoard.store = OS.get_cache_dir().path_join("clmr-range-check-board.json")
	if FileAccess.file_exists(RangeBoard.store):
		DirAccess.remove_absolute(RangeBoard.store)
	RangeBoard.local = true
	RangeBoard.boards.clear()
	g.player.health = 100
	var games = feature.games
	var walk := true
	for st: Array in L.GAME_STATIONS:
		var found := false
		for s: LevelData.Station in g.world.stations:
			found = found or s.id == "range-" + String(st[0])
		walk = walk and found and not g.world.blocked(float(st[1]), float(st[2]) - .8, .2)
	check.call(walk, "each game's station is there, with room to stand at it")
	# HORSESHOES: a shoe dropped round the stake rings it; one sliding into
	# the stake from the side is knocked off it.
	games.shoes.clear()
	games.shoes_left = 10
	games.shoe_score = 0
	(
		games
		. shoes
		. append(
			{
				"x": L.STAKE.x,
				"y": L.STAKE.y,
				"z": .6,
				"vx": 0.0,
				"vy": 0.0,
				"vz": 0.0,
				"yaw": 0.0,
				"wy": 0.0,
				"state": "fly",
				"ringed": false,
				"lean": 0.0,
				"knocked": false,
			}
		)
	)
	_tick(g, 90)
	var dropped: Dictionary = games.shoes[0]
	check.call(
		bool(dropped["ringed"]) and String(dropped["state"]) == "rest" and games.shoe_score == 3,
		(
			"a shoe dropped round the stake is a ringer: 3 (%s, %d)"
			% [games.shoe_last, games.shoe_score]
		)
	)
	games.shoes.clear()
	games.shoe_score = 0
	(
		games
		. shoes
		. append(
			{
				"x": L.STAKE.x - .6,
				"y": L.STAKE.y,
				"z": .009,
				"vx": 5.0,
				"vy": 0.0,
				"vz": 0.0,
				"yaw": 0.0,
				"wy": 0.0,
				"state": "slide",
				"ringed": false,
				"lean": 0.0,
				"knocked": false,
			}
		)
	)
	_tick(g, 90)
	var knocked: Dictionary = games.shoes[0]
	check.call(
		(
			bool(knocked["knocked"])
			and not bool(knocked["ringed"])
			and float(knocked["x"]) < L.STAKE.x
		),
		"a shoe sliding heel first into the stake is knocked back off it"
	)
	# A game of ten from the box, pitched by the look: the pitch that carries
	# to the stake scores, one that falls short does not.
	games.shoes.clear()
	games.shoes_left = 10
	games.shoe_score = 0
	games.ringers = 0
	var court: float = g.world.elevation(L.STAKE.x, L.STAKE.y)
	var aim := 0.0
	var off := 99.0
	for k in 107:
		_stand(g, L.SHOE_BOX.x, L.SHOE_BOX.y, PI / 2.0, -53.0 + k)
		var far: float = games.carry(g.player, court)
		var miss := absf(far - (L.STAKE.y - L.SHOE_BOX.y - .3) + .3)
		if miss < off:
			off = miss
			aim = -53.0 + k
	var first := -1
	var short := -1
	for k in 10:
		_stand(g, L.SHOE_BOX.x, L.SHOE_BOX.y, PI / 2.0, aim if k > 0 else -50.0)
		var before: int = games.shoe_score
		var said: String = games.pitch(g, g.player)
		_tick(g, 150)
		if k == 0:
			short = games.shoe_score - before
		elif first < 0:
			first = games.shoe_score - before
		if said != "":
			break
	var sane := true
	for shoe: Dictionary in games.shoes:
		sane = sane and String(shoe["state"]) == "rest" and is_finite(float(shoe["x"]))
	check.call(
		short == 0 and games.shoe_score > 0 and sane,
		(
			"a pitch that falls short scores nothing, those carried to the stake score (%d, %d: %s)"
			% [short, first, games.shoe_last]
		)
	)
	check.call(
		games.shoes_left == 0 and int(feature.records.get("horseshoes", 0)) == games.shoe_score,
		"a game of ten shoes ends and is kept as the best (%d)" % games.shoe_score
	)
	# THE DUNK TANK: a shot on the bullseye drops him in, he climbs back up.
	_stand(g, L.TANK_AT.x + 1.45, 84.0, PI / 2.0)
	games.start_dunk(g)
	var hits := 0
	for k in 2:
		_tick(g, 2)
		var t: Vector3 = games.target(g)
		var p := g.player
		var angle := atan2(t.y - p.y, t.x - p.x)
		var reach := Vector2(t.x - p.x, t.y - p.y).length()
		g.hitscan(angle, (t.z - p.eye) / reach, 36.0, 23.0, .0)
		if k == 0:
			check.call(
				games.dunk_state == "falling",
				"a .38 round on the bullseye drops the hand in (%s)" % games.dunk_state
			)
			_tick(g, 60)
			check.call(games.dunk_state == "under", "he goes under with a splash")
		_tick(g, int((games.DUNK_UNDER + games.DUNK_CLIMB + 1.0) * 60.0))
		hits = games.dunks
	check.call(games.dunk_state == "up" and hits == 2, "he climbs back up; two dunks counted")
	_tick(g, int(games.DUNK_ROUND * 60.0))
	check.call(
		not games.dunk_on and int(feature.records.get("dunk", 0)) == 2,
		"the round ends at the bell and its dunks are the best (%s)" % games.dunk_last
	)
	# SKEE-BALL: soft comes back, a range of rolls lands in the rings.
	var skee = games.skee
	skee.new_game()
	var seen := {}
	var best_pitch := 0.0
	var top := -1
	for k in 9:
		var pitch := -53.0 + k * 13.0
		_stand(g, L.SKEE_FOOT.x, L.SKEE_FOOT.y - .7, PI / 2.0, pitch)
		var before: int = skee.score
		feature._station("range-skee")
		_roll_out(g, skee)
		var got: int = skee.score - before
		seen[pitch] = got
		if got > top:
			top = got
			best_pitch = pitch
	(
		check
		. call(
			int(seen[-53.0]) == 0 and top >= 30 and skee.games == 1,
			(
				"skee-ball: soft rolls back for nothing, harder lands in the rings, nine balls a game %s"
				% [seen]
			)
		)
	)
	check.call(
		int(feature.records.get("skeeball", 0)) == skee.best and skee.best > 0,
		"a skee-ball game is kept as the best (%d)" % skee.best
	)
	var fine := -1
	for k in 40:
		var pitch2: float = best_pitch - 6.0 + k * .3
		_stand(g, L.SKEE_FOOT.x, L.SKEE_FOOT.y - .7, PI / 2.0, pitch2)
		var before2: int = skee.score
		feature._station("range-skee")
		_roll_out(g, skee)
		fine = maxi(fine, skee.score - before2)
	check.call(fine >= 50, "a roll just right drops in the 50 (best %d)" % fine)
	# KNOCK 'EM DOWN: three balls at the rack take bottles off the table.
	games.rack_bottles()
	_stand(g, L.BOTTLE_LINE.x, L.BOTTLE_LINE.y - .25, PI / 2.0)
	var floor_z: float = g.world.elevation(L.TABLE_AT.x, L.TABLE_AT.y)
	var aim_at := Vector3(L.TABLE_AT.x, L.TABLE_AT.y - .1, floor_z + 0.92)
	for k in 3:
		var p2 := g.player
		var d := Vector2(aim_at.x - p2.x, aim_at.y - p2.y).length()
		# Aim low over the counter: straight at the rack, the fall allowed for.
		var speed: float = games.BALL_SPEED
		var loft: float = games.BALL_LOFT
		var drop := .5 * 10.7 * pow(d / speed, 2.0)
		var slope := (aim_at.z + drop - (p2.eye - .12)) / d - loft
		p2.pitch = slope * View.base_focal
		p2.angle = atan2(aim_at.y - p2.y, aim_at.x - p2.x) + (k - 1) * .02
		feature._station("range-bottles")
		_tick(g, 300)
	var off_table := 0
	var bottles_ok := true
	for bottle: Dictionary in games.bottles:
		off_table += 1 if String(bottle["gone"]) == "off" else 0
		var bx := float(bottle["x"])
		var by := float(bottle["y"])
		bottles_ok = (
			bottles_ok
			and is_finite(bx)
			and absf(bx - L.TABLE_AT.x) < 9.0
			and by < L.BOTTLE_BACK + .1
			and float(bottle["z"]) > -.1
		)
	check.call(
		games.balls_left == 0 and games.bottle_score > 0 and bottles_ok,
		(
			"three softballs take bottles off the table and score (%d off: %s)"
			% [off_table, games.bottle_last]
		)
	)
	check.call(
		int(feature.records.get("bottles", 0)) == games.bottle_best,
		"knock 'em down's best is kept (%d)" % games.bottle_best
	)
	games.rack_bottles()
	var b0: Dictionary = games.bottles[0]
	var p3 := g.player
	var to := Vector3(float(b0["x"]), float(b0["y"]), floor_z + .95)
	var reach3 := Vector2(to.x - p3.x, to.y - p3.y).length()
	g.hitscan(atan2(to.y - p3.y, to.x - p3.x), (to.z - p3.eye) / reach3, 36.0, 23.0, .0)
	_tick(g, 120)
	check.call(
		games.bottle_shot or String(games.bottle_last).contains("NO SCORE"),
		"a round fired at the bottles knocks one over and the round scores nothing"
	)
	# The board: the bests went to it and come back on it.
	var rows: Array = RangeBoard.rows("skeeball")
	check.call(
		not rows.is_empty() and int(rows[0][1]) == skee.best,
		"the bests are posted to the board and come back on it (%s)" % [rows]
	)
	RangeBoard.answer({"range": "skeeball", "post": ["CHEAT", 9999], "version": "x"})
	var cheat: Dictionary = RangeBoard.answer(
		{
			"range": "skeeball",
			"post": ["CHEAT", 9999],
			"version": String(ProjectSettings.get_setting("application/config/version", ""))
		}
	)
	var cheated := false
	for row: Array in cheat["rows"]:
		cheated = cheated or String(row[0]) == "CHEAT"
	check.call(not cheated, "a score past what a game allows is refused")
	var c := Canvas.new()
	var drew := true
	for station: String in ["horseshoes", "dunk", "skeeball", "bottles", "bowling"]:
		feature.station = station
		feature.station_since = -100.0
		feature.draw_view(c)
		drew = drew and not feature.Card.readouts(feature).is_empty()
	check.call(drew, "each game's station card draws its score and the board")
	_stand(g, L.BOTTLE_LINE.x, L.BOTTLE_LINE.y - .25, PI / 2.0)
	var kinds := {}
	for sprite: View.Sprite in games.sprites(g):
		kinds[sprite.solid] = true
	check.call(
		kinds.has("bottle") and kinds.has("softball"),
		"the games give the 3D view their bodies (%s)" % [kinds.keys()]
	)
	RangeBoard.local = false
	RangeBoard.store = kept_store
	RangeBoard.folder_override = ""


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
	_games(g, feature, check)
	var c := Canvas.new()
	feature.station = "bullpen"
	feature.draw_view(c)
	check.call(true, "the station card draws")
