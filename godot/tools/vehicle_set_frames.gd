## Pictures of finding the vehicles and what is built round them (feature
## pass 7) in a real window: each vehicle as a player comes up on it (its
## KEYS IN IT sign, its lamps, USE's prompt from off), the automap marking
## it, the bayou's CHANNEL RUN and the speedway's HEAT RACE under way (the
## plate, the flare on the next gate), the .38 out of the car's window and a
## partner's view from the passenger seat. <name>.png in out=<dir>.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/vehicle_set_frames.gd -- out=<dir> [only=<name>]
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

var main
var out := ""
var only := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
		if String(arg).begins_with("only="):
			only = String(arg).substr(5)
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
	if only == "" or only == "find":
		await _find("bayou", Vector2(101.5, 33.0), -4.0)
		await _find("speedway", Vector2(65.0, 16.0), -4.0)
		await _find("bayou_bow", Vector2(98.6, 29.6), -8.0)
		await _find("hickston", Vector2(84.5, 62.0), -6.0)
		await _map()
	if only == "" or only == "runs":
		await _channel()
		await _heat()
	if only == "" or only == "window":
		await _window()
	print("vehicle set frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _game(id: String, alone := true) -> Game:
	var g: Game = main.make_game(id)
	main.game = g
	main.state = "play"
	g.configure(SessionStore.defaults())
	g.barks.enabled = false
	g.cheats.god = true
	if alone:
		g.enemies.clear()
		g.enemy_ids.clear()
	return g


func _snap(name: String, keep_notice := false) -> void:
	var g: Game = main.game
	if not keep_notice:
		g.message_until = 0.0
	g.callout_until = 0.0
	g.district_until = 0.0
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


func _ticks(g: Game, n: int, forward := 0.0) -> void:
	for i in n:
		var c := Game.Controls.new()
		c.forward = forward
		g.tick(1.0 / 60.0, c)


## The player standing at `at` looking at ride 0 (pitched `pitch`).
func _from(g: Game, at: Vector2, pitch: float) -> void:
	var v: VehicleDrive.Ride = g.features["vehicles"].rides[0]
	var p := g.player
	p.x = at.x
	p.y = at.y
	p.floor_z = g.world.floor_under(at.x, at.y, v.z + 1.5)
	p.eye = p.floor_z + .95
	p.angle = atan2(v.y - at.y, v.x - at.x)
	p.pitch = pitch


func _find(name: String, at: Vector2, pitch: float) -> void:
	var id := name.trim_suffix("_bow")
	var g := _game(id)
	_ticks(g, 20)
	_from(g, at, pitch)
	_ticks(g, 2)
	await _snap("find_%s" % name)


func _map() -> void:
	var g := _game("bayou")
	_from(g, Vector2(101.5, 33.0), 0.0)
	_ticks(g, 2)
	g.map = true
	g.map_zoom = 2
	await _snap("find_map_bayou")
	g.map_zoom = 0
	await _snap("find_map_bayou_whole")


## Drives ride 0 toward `aim` for `n` ticks.
func _drive_to(g: Game, aim: Vector2, n: int) -> void:
	var v: VehicleDrive.Ride = g.features["vehicles"].rides[0]
	for i in n:
		g.player.angle = atan2(aim.y - v.y, aim.x - v.x)
		var c := Game.Controls.new()
		c.forward = 1.0
		g.tick(1.0 / 60.0, c)


func _channel() -> void:
	var g := _game("bayou", false)
	var cars = g.features["vehicles"]
	cars.seat_in(g.player, 0)
	_ticks(g, 10)
	g.player.pitch = -4.0
	await _snap("run_channel_0_start", true)
	for aim: Vector2 in [Vector2(95.0, 37.0), Vector2(91.0, 39.5)]:
		_drive_to(g, aim, 120)
	_drive_to(g, Vector2(84.0, 40.0), 50)
	g.player.pitch = -3.0
	await _snap("run_channel_1_going", true)


func _heat() -> void:
	var g := _game("speedway", false)
	var cars = g.features["vehicles"]
	var v: VehicleDrive.Ride = cars.rides[0]
	# Rolled up to the start line, the way the lap cars run, and through it.
	v.x = 64.0
	v.y = 64.0
	v.h = 0.0
	v.z = g.world.floor_under(v.x, v.y, 9.0)
	cars.seat_in(g.player, 0)
	_drive_to(g, Vector2(84.0, 64.0), 90)
	g.player.pitch = -3.0
	await _snap("run_heat_0_start", true)
	_drive_to(g, Vector2(104.0, 63.5), 40)
	_drive_to(g, Vector2(114.0, 53.0), 50)
	g.player.angle = atan2(45.5 - v.y, 116.2 - v.x)
	_ticks(g, 2, .5)
	await _snap("run_heat_1_turn", true)


func _window() -> void:
	var g := _game("speedway")
	var cars = g.features["vehicles"]
	cars.seat_in(g.player, 0)
	_ticks(g, 30)
	var v: VehicleDrive.Ride = cars.rides[0]
	g.player.angle = v.h + .5
	g.player.pitch = -4.0
	_ticks(g, 20)
	await _snap("window_38_out")
	g.player.angle = v.h + 1.3
	_ticks(g, 4)
	await _snap("window_38_side")
	# A partner beside the driver: their own view from the passenger seat.
	GameHost.join_near(g)
	var two: Player = g.players[1]
	var keep: Player = g.player
	g.player = two
	g.focus(two)
	two.x = v.x - sin(v.h) * 1.4
	two.y = v.y + cos(v.h) * 1.4
	two.angle = v.h - PI * .5
	g.interact()
	g.player = keep
	g.focus(keep)
	_ticks(g, 4)
	g.local_player = two
	g.player = two
	two.angle = v.h - .15
	two.pitch = -4.0
	_ticks(g, 2)
	await _snap("window_passenger")
	g.local_player = keep
	g.player = keep
