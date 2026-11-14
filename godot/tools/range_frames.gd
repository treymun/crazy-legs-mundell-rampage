## Pictures of the firing range's newer parts in a real window (the
## graphics-card view players see): the armory's store wall from both sides,
## the Swamp King on the corral's pond, Maw and Bumper Boggs in the corral,
## the bullpen's second lever bank, and a ball down the Bowl-O-Rama frame by
## frame (thrown, at the pins, the pins going over, what is left, from the
## side). <name>.png in out=<dir>.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/range_frames.gd -- out=<dir>
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

var main
var out := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
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
	await _store()
	await _corral()
	await _bowling()
	print("range frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _game() -> Game:
	var g: Game = main.make_game("range")
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
	_ticks(g, 80)
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
	_ticks(g, 120)
	await _snap("bowl_6_swept")
	print("bowling: ", bowl.last_roll, "  sheet ", bowl.sheet_text())
