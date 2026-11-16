## Pictures of the vehicles (features/vehicles.gd) in a real window: each one
## parked, seen from beside it; from the driver's seat; driving; and the
## airboat burning out after a wreck. <name>.png in out=<dir>; only=<kind>
## takes one vehicle's.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/vehicle_frames.gd -- out=<dir> [only=car]
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

const LEVELS := {"airboat": "bayou", "car": "speedway", "mower": "hickston"}

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
	for kind: String in LEVELS:
		if only == "" or only == kind:
			await _vehicle(kind, str(LEVELS[kind]))
	print("vehicle frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _game(id: String) -> Game:
	var g: Game = main.make_game(id)
	main.game = g
	main.state = "play"
	g.configure(SessionStore.defaults())
	g.barks.enabled = false
	g.cheats.god = true
	return g


func _snap(name: String) -> void:
	var g: Game = main.game
	g.message_until = 0.0
	g.callout_until = 0.0
	g.district_until = 0.0
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


func _ticks(g: Game, n: int, forward := 0.0, strafe := 0.0) -> void:
	for i in n:
		var c := Game.Controls.new()
		c.forward = forward
		c.strafe = strafe
		g.tick(1.0 / 60.0, c)


## Stands the player `far` from the vehicle on its `side` (radians off its
## heading), looking at it.
func _look_at(g: Game, v: VehicleDrive.Ride, side: float, far: float, pitch := -8.0) -> void:
	var p := g.player
	var a := v.h + side
	p.x = v.x + cos(a) * far
	p.y = v.y + sin(a) * far
	p.angle = a + PI
	p.floor_z = g.world.floor_under(p.x, p.y, v.z + 1.5)
	p.eye = .95 + p.floor_z
	p.pitch = pitch


func _vehicle(kind: String, id: String) -> void:
	var g := _game(id)
	var rides = g.features["vehicles"]
	var v: VehicleDrive.Ride = rides.rides[0]
	_ticks(g, 20)
	_look_at(g, v, 0.0 if kind == "car" else PI / 2.0, 4.5)
	await _snap(kind + ("_0_parked_front" if kind == "car" else "_0_parked_side"))
	_look_at(g, v, PI / 4.0, 5.0)
	await _snap(kind + "_1_parked_front")
	# In: from beside it, USE.
	_look_at(g, v, PI / 2.0, VehicleDrive.spec(kind).width * .5 + .6, 0.0)
	g.interact()
	_ticks(g, 10)
	g.player.pitch = -6.0
	await _snap(kind + "_2_seat")
	_ticks(g, 70, 1.0)
	await _snap(kind + "_3_driving")
	_ticks(g, 50, 1.0, .8)
	await _snap(kind + "_4_turning")
	# The seat view looked round: down at the controls, and back (the
	# airboat's fan cage).
	var p := g.player
	p.pitch = -40.0
	await _snap(kind + "_6_seat_down")
	p.pitch = 0.0
	p.angle = fposmod(v.h + PI * .8, TAU)
	await _snap(kind + "_7_seat_back")
	p.angle = v.h
	if kind == "airboat":
		rides.call("_hurt", v, 99999.0)
		_ticks(g, 90)
		_look_at(g, v, -PI / 2.0, 6.0, -4.0)
		await _snap(kind + "_5_wrecked")
