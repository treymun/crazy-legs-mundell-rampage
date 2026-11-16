## Pictures of the polish pass's visible fixes (track S, before v3.3.0) in a
## real window:
##   photo_car      PHOTO MODE's camera beside the stock car with Mundell at
##                  its wheel (he stood up through its roof: now unseen in it)
##   photo_mower    the same at the mower (he sits down into its seat)
##   photo_airboat  and at the airboat
##   skids          the stock car's tyre marks after a slide, from above
##   sparks         the stock car scraping the speedway's wall
## Each lands in out=<dir> as <name>.png; only=<name> takes one.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/polish_frames.gd -- out=<dir> [only=skids]
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
	if only == "" or only == "photo_car":
		await _photo("speedway", "photo_car", 3.6)
	if only == "" or only == "photo_mower":
		await _photo("hickston", "photo_mower", 2.6)
	if only == "" or only == "photo_airboat":
		await _photo("bayou", "photo_airboat", 4.0)
	if only == "" or only == "skids":
		await _skids()
	if only == "" or only == "sparks":
		await _sparks()
	print("polish frames written to ", out)
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
		e.alive = false
		e.hp = 0.0
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


func _ticks(g: Game, n: int, forward := 0.0, strafe := 0.0, jump := false) -> void:
	for i in n:
		var c := Game.Controls.new()
		c.forward = forward
		c.strafe = strafe
		c.jump = jump
		g.tick(1.0 / 60.0, c)


## Into the level's first vehicle from beside it.
func _get_in(g: Game) -> VehicleDrive.Ride:
	var rides = g.features["vehicles"]
	var v: VehicleDrive.Ride = rides.rides[0]
	_ticks(g, 20)
	var p := g.player
	var a := v.h + PI / 2.0
	var far := VehicleDrive.spec(v.kind).width * .5 + .6
	p.x = v.x + cos(a) * far
	p.y = v.y + sin(a) * far
	p.angle = a + PI
	p.floor_z = g.world.floor_under(p.x, p.y, v.z + 1.5)
	p.eye = .95 + p.floor_z
	g.interact()
	_ticks(g, 10)
	return v


## A camera `far` off the point (x, y) at `side` radians, `up` over its floor,
## looking at it (PHOTO MODE's eye).
func _camera(g: Game, x: float, y: float, z: float, side: float, far: float, up: float) -> void:
	var cx := x + cos(side) * far
	var cy := y + sin(side) * far
	var eye := z + up
	var look := atan2(y - cy, x - cx)
	var pitch := -atan((eye - z - .5) / far) * View.base_focal
	g.eye_override = {
		"x": cx, "y": cy, "eye": eye, "view_angle": look, "pitch": pitch, "bob": 0.0, "sway": 0.0
	}


func _photo(level: String, name: String, far: float) -> void:
	var g := _game(level)
	var v := _get_in(g)
	_camera(g, v.x, v.y, v.z, v.h + PI * .4, far, 1.1)
	await _snap(name)
	g.eye_override = {}


## The way from (x, y) with the most open floor ahead, and how far it runs.
func _open_way(g: Game, x: float, y: float) -> Vector2:
	var best := Vector2(0.0, 0.0)
	for k in 72:
		var a := k * TAU / 72.0
		var d := 0.0
		while d < 40.0 and not g.world.blocked(x + cos(a) * d, y + sin(a) * d, .8):
			d += .25
		if d > best.y:
			best = Vector2(a, d)
	return best


func _skids() -> void:
	var g := _game("speedway")
	var v := _get_in(g)
	v.h = _open_way(g, v.x, v.y).x
	_ticks(g, 55, 1.0)
	_ticks(g, 40, 1.0, 1.0, true)
	_ticks(g, 25, 0.0, 0.0, true)
	var marks: Array = g.features["vehicles"]._looks["marks"]
	var mid := Vector2(v.x, v.y)
	if not marks.is_empty():
		var m: Array = marks[marks.size() / 2]
		mid = Vector2(float(m[0]), float(m[1]))
	print("skid marks: %d" % marks.size())
	var back := _open_way(g, mid.x, mid.y).x
	_camera(g, mid.x, mid.y, v.z, back, 3.5, 2.8)
	await _snap("skids")
	g.eye_override = {}


func _sparks() -> void:
	var g := _game("speedway")
	var v := _get_in(g)
	# Turned onto the nearest wall at a slant, then driven along it.
	var best := INF
	var toward := 0.0
	for k in 72:
		var a := k * TAU / 72.0
		for step in range(1, 40):
			var d := step * .25
			if g.world.blocked(v.x + cos(a) * d, v.y + sin(a) * d, .1):
				if d < best:
					best = d
					toward = a
				break
	v.h = toward - .45
	var hit := false
	for i in 400:
		_ticks(g, 1, 1.0, -.25)
		var sparks: Array = g.features["vehicles"]._looks["sparks"]
		if not sparks.is_empty():
			var last: Array = sparks[sparks.size() - 1]
			if g.clock - float(last[6]) < .05:
				hit = true
				break
	if not hit:
		print("no scrape found")
	_ticks(g, 9)
	_camera(g, v.bump_x, v.bump_y, v.z, toward + PI + .5, 2.8, 1.2)
	await _snap("sparks")
	g.eye_override = {}
