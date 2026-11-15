## Pictures of the firing range's newer parts in a real window (the
## graphics-card view players see): the armory's store wall from both sides,
## the Swamp King on the corral's pond, Maw and Bumper Boggs in the corral,
## the bullpen's second lever bank, and a ball down the Bowl-O-Rama frame by
## frame (thrown, at the pins, the pins going over, what is left, from the
## side); the games row (a shoe in the air and a ringer, the dunk tank up, a
## hand going in and under, the skee-ball cabinet and a ball in the air,
## knock 'em down racked and hit), the fair's shooting gallery and prize
## booth, and the trophy shack in the Crossroads. <name>.png in out=<dir>;
## only=<a,b> takes some of: store, corral, bowling, games, fair, shack.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/range_frames.gd -- out=<dir> [only=games,fair]
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

const L := preload("res://src/range_layout.gd")

var main
var out := ""
var only: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
		elif String(arg).begins_with("only="):
			only = String(arg).substr(5).split(",")
	if out == "":
		push_error("out=<dir> is needed")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.touring = true
	Effects.enabled = true
	if _wanted("store"):
		await _store()
	if _wanted("corral"):
		await _corral()
	if _wanted("bowling"):
		await _bowling()
	if _wanted("games"):
		await _games()
	if _wanted("fair"):
		await _fair()
	if _wanted("shack"):
		await _shack()
	print("range frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _wanted(part: String) -> bool:
	return only.is_empty() or only.has(part)


func _game(level := "range") -> Game:
	var g: Game = main.make_game(level)
	main.game = g
	main.state = "play"
	g.configure(SessionStore.defaults())
	g.barks.enabled = false
	return g


func _stand(g: Game, x: float, y: float, angle: float, pitch := 0.0, armed := false) -> void:
	var p := g.player
	p.x = x
	p.y = y
	p.angle = angle
	p.floor_z = g.world.floor_under(x, y, .05)
	p.eye = .95 + g.world.stand(p)
	p.pitch = pitch
	g.armory.holstered = not armed
	g.armory.lower = 0.0 if armed else 1.0


func _lever(g: Game, id: String) -> void:
	for s: LevelData.Station in g.world.stations:
		if s.id == "range-" + id:
			g.operate_station(s)


func _snap(name: String) -> void:
	var g: Game = main.game
	g.message_until = 0.0
	g.callout_until = 0.0
	g.district_until = 0.0
	# A tick first: the view culls by where the eye stood at the last one.
	g.tick(1.0 / 60.0, Game.Controls.new())
	g.message_until = 0.0
	g.callout_until = 0.0
	if g.features.has("range") and g.features["range"].on:
		# The card without its teaching lines: the score and the board.
		g.features["range"].station_since = -100.0
	for k in 3:
		main.render()
		await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


func _ticks(g: Game, n: int, given = null) -> void:
	for i in n:
		g.tick(1.0 / 60.0, given if given != null else Game.Controls.new())


func _store() -> void:
	var g := _game()
	_ticks(g, 30)
	_stand(g, 48.0, 70.4, -PI / 2.0, 4.0)
	await _snap("store_deputies")
	_stand(g, 47.0, 64.6, PI / 2.0, 4.0)
	await _snap("store_outlaws")
	_stand(g, 41.8, 66.9, PI / 2.0, -6.0)
	await _snap("store_hunter_close")
	_stand(g, 63.6, 67.0, 0.0, 6.0)
	await _snap("bullpen_west_bank")


func _corral() -> void:
	var g := _game()
	_ticks(g, 30)
	for kind: String in ["swamp_king", "maw", "derby_champ"]:
		_lever(g, "boss-" + kind)
		_stand(g, 12.5, 60.4, PI / 2.0, 2.0, true)
		_ticks(g, 150)
		# Back to where the picture is taken from (the fight has moved things).
		_stand(g, 12.5, 60.4, PI / 2.0, 2.0, true)
		await _snap("corral_" + kind)


func _bowling() -> void:
	var g := _game()
	_ticks(g, 30)
	var feature = g.features["range"]
	var bowl = feature.targets.bowling
	g.armory.active = Weapons.BOWLING
	_stand(g, 46.62, 50.3, -PI / 2.0, -4.0, true)
	feature.targets.last_angle = g.player.angle
	g.launch(46.62, 49.9, .22, -PI / 2.0, 7.4, "bowling", 0.0, false, 108, 4.5)
	_ticks(g, 4)
	await _snap("bowl_0_thrown")
	_ticks(g, 96)
	await _snap("bowl_1_at_the_pins")
	_stand(g, 46.5, 41.0, -PI / 2.0, -10.0)
	_ticks(g, 10)
	await _snap("bowl_2_pin_action")
	_ticks(g, 10)
	await _snap("bowl_3_pin_action")
	_ticks(g, 25)
	await _snap("bowl_4_falling")
	_stand(g, 48.55, 38.9, PI + .55, -14.0)
	_ticks(g, 60)
	await _snap("bowl_5_from_the_side")
	_stand(g, 46.5, 41.0, -PI / 2.0, -10.0)
	_ticks(g, 240)
	await _snap("bowl_6_swept")
	print("bowling: ", bowl.last_roll, "  sheet ", bowl.sheet_text())


func _games() -> void:
	var g := _game()
	_ticks(g, 30)
	var feature = g.features["range"]
	var games = feature.games
	# Horseshoes: a shoe in the air over the court, then a ringer close up.
	_stand(g, L.SHOE_BOX.x + .4, L.SHOE_BOX.y - .6, PI / 2.0 + .03, 2.0)
	g.player.pitch = 4.0
	games.pitch(g, g.player)
	_stand(g, L.SHOE_BOX.x + 2.2, L.SHOE_BOX.y + 3.5, PI / 2.0 + .35, 0.0)
	_ticks(g, 26)
	await _snap("games_shoe_flying")
	games.shoes.clear()
	(
		games
		. shoes
		. append(
			{
				"x": L.STAKE.x + .01,
				"y": L.STAKE.y,
				"z": .5,
				"vx": 0.0,
				"vy": 0.0,
				"vz": 0.0,
				"yaw": .8,
				"wy": 0.0,
				"state": "fly",
				"ringed": false,
				"lean": 0.0,
				"knocked": false,
			}
		)
	)
	(
		games
		. shoes
		. append(
			{
				"x": L.STAKE.x - .1,
				"y": L.STAKE.y - .02,
				"z": .009,
				"vx": 0.0,
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
	_ticks(g, 60)
	_stand(g, L.STAKE.x - .9, L.STAKE.y - 2.2, atan2(2.2, .9), -38.0)
	await _snap("games_shoe_ringer")
	# The dunk tank: the hand up jawing, then in he goes.
	_stand(g, L.TANK_AT.x - 2.0, L.TANK_AT.y - 6.0, atan2(6.0, 2.6), 10.0)
	_ticks(g, 20)
	await _snap("games_dunk_up")
	var t: Vector3 = games.target(g)
	g.player.angle = atan2(t.y - g.player.y, t.x - g.player.x)
	g.hitscan(
		g.player.angle,
		(t.z - g.player.eye) / Vector2(t.x - g.player.x, t.y - g.player.y).length(),
		36.0,
		30.0,
		0.0
	)
	_stand(g, L.TANK_AT.x - 2.0, L.TANK_AT.y - 6.0, atan2(6.0, 2.6), 10.0)
	_ticks(g, 22)
	await _snap("games_dunk_splash")
	_ticks(g, 60)
	await _snap("games_dunk_under")
	# Skee-ball: the cabinet from the foot, a ball in the air, from the side.
	_stand(g, L.SKEE_FOOT.x - 1.9, L.SKEE_FOOT.y - 1.5, atan2(4.6, 1.5), 4.0)
	await _snap("games_skee_cabinet")
	_stand(g, L.SKEE_FOOT.x, L.SKEE_FOOT.y - .62, PI / 2.0, 8.0)
	await _snap("games_skee_foot")
	_stand(g, L.SKEE_FOOT.x, L.SKEE_FOOT.y - .75, PI / 2.0, -1.0)
	g.player.pitch = -1.0
	games.skee.roll(g.player, g.rng)
	_stand(g, L.SKEE_FOOT.x - 2.3, L.SKEE_FOOT.y + .2, atan2(3.6, 2.3), 6.0)
	for i in 120:
		_ticks(g, 1)
		if String(games.skee.ball.get("phase", "")) == "air":
			break
	_ticks(g, 6)
	await _snap("games_skee_air")
	# Knock 'em down: racked, then a ball through them.
	games.rack_bottles()
	_stand(g, L.BOTTLE_LINE.x - .6, L.BOTTLE_LINE.y - .7, atan2(6.6, .6), -4.0)
	await _snap("games_bottles_racked")
	_stand(g, L.BOTTLE_LINE.x, L.BOTTLE_LINE.y - .25, PI / 2.0, -2.0)
	var p := g.player
	var d := Vector2(L.TABLE_AT.x - p.x, L.TABLE_AT.y - .1 - p.y).length()
	var speed: float = games.BALL_SPEED
	var loft: float = games.BALL_LOFT
	var fall := .5 * 10.7 * pow(d / speed, 2.0)
	p.pitch = ((.92 + fall - (p.eye - .12)) / d - loft) * View.base_focal
	p.angle = atan2(L.TABLE_AT.y - .1 - p.y, L.TABLE_AT.x - p.x)
	games.throw_ball(g, g.player)
	_stand(g, L.TABLE_AT.x - 2.2, L.TABLE_AT.y - 2.6, atan2(2.6, 2.2), -10.0)
	_ticks(g, 40)
	await _snap("games_bottles_hit")
	_stand(g, 66.5, 79.6, PI / 2.0, 8.0)
	await _snap("games_row")


func _fair() -> void:
	var g := _game("fair")
	g.enemies.clear()
	g.enemy_ids.clear()
	_ticks(g, 30)
	var f = g.features["fair_gallery"]
	_stand(g, 98.5, 49.7, -PI / 2.0, 6.0, true)
	f.start(g.player)
	_ticks(g, 150)
	await _snap("fair_gallery_round")
	for t: Dictionary in f.targets:
		if String(t["kind"]) == "can" and float(t["x"]) > 97.0 and float(t["x"]) < 100.0:
			f._target_hit(t, Vector2(0.0, -1.0))
			break
	_ticks(g, 9)
	await _snap("fair_gallery_can_flying")
	f.won_hat = true
	_stand(g, 89.5, 50.2, -PI / 2.0, 4.0)
	await _snap("fair_prize_booth")


func _shack() -> void:
	var g := _game("hub")
	g.in_hub = true
	g.world.locked_gates = []
	_ticks(g, 10)
	var f = g.features["trophy_shack"]
	f.refresh()
	for kind: String in BossRematch.BOSSES:
		f.beaten[kind] = true
	f.bests = {"bowling": 210, "skeeball": 280, "horseshoes": 14, "dunk": 6}
	f.county = {"county_bayou": {"time": 400.0, "level": 8}}
	_stand(g, 63.6, 50.0, -.05, 2.0)
	await _snap("shack_east")
	_stand(g, 66.4, 51.9, -PI / 2.0 + .2, 4.0)
	await _snap("shack_north")
	_stand(g, 66.4, 48.1, PI / 2.0 - .2, 4.0)
	await _snap("shack_south")
	_stand(g, 57.5, 50.5, 0.0, 2.0)
	await _snap("shack_outside")
