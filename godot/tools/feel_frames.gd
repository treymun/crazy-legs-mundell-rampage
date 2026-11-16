## Pictures of the vehicles' feel (src/vehicle_feel.gd) and the plank walls
## that break (src/plank_walls.gd), in a real window, seen from a camera off
## to the side (PHOTO MODE's free eye, game.eye_override): the stock car
## straight and then leaning out of a hard turn, its skid marks, sparks off a
## wall, the airboat throwing spray, the mower spitting clippings; a barn's
## wall at the fair whole, shot about and broken through under its roof, a
## pen's fence in a barn, the sawmill's shed and a bayou shack opened.
## <name>.png in out=<dir>; only=cars or only=walls takes one half.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/feel_frames.gd -- out=<dir> [only=walls]
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

var main
var out := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var only := ""
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
	if only == "" or only == "cars":
		await _car()
		await _airboat()
		await _mower()
	if only == "" or only == "walls":
		await _walls()
	print("feel frames written to ", out)
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
	for e: Enemy in g.enemies:
		e.dormant = true
	return g


func _snap(name: String) -> void:
	var g: Game = main.game
	g.message_until = 0.0
	g.callout_until = 0.0
	g.district_until = 0.0
	# The free camera stands the player's own body where they are: a driver
	# would stand up through the roof, so they step out of the picture (the
	# next tick seats them again).
	if g.features["vehicles"].seated(g.player):
		g.player.x += 60.0
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


func _ticks(g: Game, n: int, forward := 0.0, strafe := 0.0, jump := false) -> void:
	for i in n:
		var c := Game.Controls.new()
		c.forward = forward
		c.strafe = strafe
		c.jump = jump
		g.tick(1.0 / 60.0, c)


## The free camera at (x, y), `high` over z, looking at (tx, ty).
static func _eye(
	g: Game, x: float, y: float, z: float, tx: float, ty: float, pitch := -6.0
) -> void:
	g.eye_override = {
		"x": x,
		"y": y,
		"eye": z,
		"view_angle": atan2(ty - y, tx - x),
		"pitch": pitch,
		"bob": 0.0,
		"sway": 0.0,
	}


## A camera `far` from ride 0 on its `side` (radians off its heading), low:
## the nearest side to that with a clear view of it, coming in closer when
## there is no room.
static func _beside(g: Game, side: float, far: float, high := .7, pitch := -4.0) -> void:
	var v: VehicleDrive.Ride = g.features["vehicles"].rides[0]
	var w := g.world
	for k in 16:
		var turn := (k + 1) / 2 * (PI / 8.0) * (1.0 if k % 2 == 0 else -1.0)
		var a := v.h + side + turn
		var d := far
		while d > 1.6:
			var x := v.x + cos(a) * d
			var y := v.y + sin(a) * d
			if not w.blocked(x, y, .3) and w.visible(x, y, v.x, v.y, v.z + high, v.z + .5):
				_eye(g, x, y, w.floor_under(x, y, v.z + high) + high, v.x, v.y, pitch)
				return
			d -= .3
	_eye(g, v.x + cos(v.h + side) * far, v.y + sin(v.h + side) * far, v.z + high, v.x, v.y, pitch)


## Into ride 0's driver's seat, turned to its longest open way.
static func _seat(g: Game) -> VehicleDrive.Ride:
	var rides = g.features["vehicles"]
	var v: VehicleDrive.Ride = rides.rides[0]
	var s := VehicleDrive.spec(v.kind)
	var best_h := v.h
	var best := 0
	for k in 32:
		var h := v.h + k * TAU / 32.0
		var run := 0
		for step in 60:
			var d := step * .3
			if is_nan(VehicleDrive.fits(g.world, s, v.x + cos(h) * d, v.y + sin(h) * d, h, v.z)):
				break
			run = step
		if run > best:
			best = run
			best_h = h
	v.h = best_h
	var p := g.player
	var r := Vector2(-sin(v.h), cos(v.h))
	p.x = v.x + r.x * (s.width * .5 + .5)
	p.y = v.y + r.y * (s.width * .5 + .5)
	p.angle = atan2(v.y - p.y, v.x - p.x)
	g.interact()
	g.player.angle = best_h
	return v


func _car() -> void:
	var g := _game("speedway")
	var v := _seat(g)
	_ticks(g, 40, 1.0)
	_beside(g, PI, 4.0, .6)
	await _snap("car_0_straight")
	_ticks(g, 14, .7, 1.0)
	_beside(g, PI, 4.0, .6)
	await _snap("car_1_leaning")
	_ticks(g, 24, 1.0, 1.0, true)
	_ticks(g, 20, -1.0)
	_beside(g, PI * .7, 4.5, 2.6, -32.0)
	await _snap("car_2_skids")
	var bumps := v.bumps
	for t in 600:
		_ticks(g, 1, 1.0)
		if v.bumps > bumps:
			break
	_ticks(g, 1, 1.0)
	_beside(g, PI * .35, 3.0, .8)
	await _snap("car_3_sparks")


func _airboat() -> void:
	var g := _game("bayou")
	_seat(g)
	_ticks(g, 60, 1.0)
	_ticks(g, 16, 1.0, .9)
	_beside(g, PI * .75, 5.0, 1.1, -8.0)
	await _snap("airboat_spray")


func _mower() -> void:
	var g := _game("hickston")
	_seat(g)
	_ticks(g, 50, 1.0)
	_beside(g, PI * .65, 2.6, .9, -10.0)
	await _snap("mower_clippings")


## A plank wall of `tile` that may open (`shed`: under a roof on one side),
## seen from outside: whole, shot about, broken through and settled.
func _wall(id: String, tile: String, shed: bool, name: String, steps := true) -> void:
	var g := _game(id)
	var wb = g.features["wall_breaks"]
	var tid := g.world.tile_id(tile)
	var found = null
	var keys: Array = wb.fences.keys()
	keys.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return a.y * 1000 + a.x < b.y * 1000 + b.x
	)
	for key: Vector2i in keys:
		var f = wb.fences[key]
		if f.tile == tid and f.opens and (f.inside >= 0) == shed and (shed or f.low):
			found = f
			break
	if found == null:
		print("no ", tile, " wall at ", id)
		return
	var f = found
	var w := g.world
	var c := Vector2(f.cell.x + .5, f.cell.y + .5)
	# The camera on the open air side (a pen: either side), back from it.
	var from := c
	for e: Array in LevelEdit.EDGES:
		var n := Vector2i(f.cell.x + e[0], f.cell.y + e[1])
		var k := n.y * w.width + n.x
		if w.solid[k] < 0 and (w.roof[k] <= 0.0 or not shed):
			from = Vector2(n.x + .5, n.y + .5)
			break
	var away := (from - c).normalized()
	var cam := c + away * 3.2
	while w.blocked(cam.x, cam.y, .2) and cam.distance_to(c) > 1.2:
		cam -= away * .2
	var ground := w.ground[f.cell.y * w.width + f.cell.x]
	_eye(g, cam.x, cam.y, ground + 1.1, c.x, c.y, 2.0)
	if steps:
		await _snap(name + "_0_whole")
		wb._knock(f, f.most * .5, -away.x, -away.y)
		_ticks(g, 30)
		await _snap(name + "_1_shot")
	wb._knock(f, f.most * 3.0, -away.x, -away.y)
	_ticks(g, 150)
	await _snap(name + ("_2_through" if steps else ""))


func _walls() -> void:
	await _wall("fair", "barn", true, "barn")
	await _wall("fair", "stockyard", false, "pen", false)
	await _wall("sawmill", "wood", true, "shed", false)
	await _wall("bayou", "bayou_shack", true, "shack", false)
