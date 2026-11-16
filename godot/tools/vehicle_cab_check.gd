## The vehicles' seat views and driving plate (src/vehicle_cab.gd,
## view3d/cab_layer.gd, src/vehicle_hud.gd; tools/check_all.gd runs it, quick
## too):
##
##   godot --headless --path godot --script res://tools/vehicle_cab_check.gd
##
## Every kind names a cab whose model, baked art and every moving part the
## game turns are there (the wheel, the hands riding it, the stick, needles,
## the prop, the blade lever); in the driver's seat with a window, the eye is
## handed the cab (none on foot, none for PHOTO MODE's free camera, none
## without a window: then the car keeps its painted dash), the driver's own
## model is left out of the sprites, the wheel turns clockwise for a right
## turn and the hands ride it, the needles rise with the speed, the prop
## turns and the mower's blade lever is forward while it cuts; drawn by the
## 3D view, every part sits nearer than any wall can come and further than
## the camera's near plane; SCREEN SHAKE off stops the buzz, STILL stops the
## sway, the dip and the widening; the view widens at speed and not past the
## FIELD OF VIEW a player chose wider; the airboat throws spray over its bow
## that lands in the view; the plate is drawn (full, MINIMAL, STATUS PANEL's
## dial, up under the pin with the touch buttons) with the right line for
## each kind; and driving is the same with the cab drawn or not.
extends SceneTree

const STEP := 1.0 / 60.0
const VehiclesScript := preload("res://src/features/vehicles.gd")
const LEVELS := {"airboat": "bayou", "car": "speedway", "mower": "hickston"}
## Each kind's moving parts the game sets (VehicleCab.dress).
const PARTS := {
	"airboat": ["stick", "hand", "needle", "prop"],
	"car": ["steer", "hand_l", "hand_r", "speed", "tach"],
	"mower": ["steer", "hand", "lever"],
}
## The nearest any wall can be to a driver's eye (cells: a hull's half width
## is .45 and more, and the eye is inside it).
const WALL := .45

var failures: Array = []
var passes := 0


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if ok:
		passes += 1
	else:
		failures.append(text)


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	for kind: String in LEVELS:
		print("\n%s" % kind.to_upper())
		_kind(main, kind, str(LEVELS[kind]))
	print("\nSETTINGS")
	_settings(main)
	print("\nPLATE")
	_plate(main)
	print("\nSAME DRIVE")
	_same_drive(main)
	print("")
	print("%d checks" % (passes + failures.size()))
	print("VEHICLE CAB OK" if failures.is_empty() else "%d CAB CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _game(main: Control, id: String) -> Game:
	var g: Game = main.make_game(id)
	g.configure({"difficulty": 1})
	g.cheats.god = true
	g.enemies.clear()
	g.enemy_ids.clear()
	return g


func _drive(g: Game, ticks: int, forward: float, strafe := 0.0) -> void:
	for t in ticks:
		var c := Game.Controls.new()
		c.forward = forward
		c.strafe = strafe
		g.tick(STEP, c)


## The eye as game_view.gd dresses it for the frame.
func _eye(g: Game) -> Dictionary:
	var eye := g.player.as_render_player()
	var rides: VehiclesScript = g.features["vehicles"]
	rides.sway_eye(eye)
	return eye


func _kind(main: Control, kind: String, id: String) -> void:
	var s := VehicleDrive.spec(kind)
	var g := _game(main, id)
	var rides: VehiclesScript = g.features["vehicles"]
	_check(s.cab != "" and g.art.has_art("mesh_" + s.cab), "%s names a cab with its art" % kind)
	var layer := CabLayer3D.new(g.art)
	root.add_child(layer)
	_check(layer.has_model(s.cab), "its model and pivots are there")
	var made: Dictionary = {}
	var packed := load(CabLayer3D.FOLDER.path_join(s.cab + ".glb")) as PackedScene
	if packed != null:
		var scene := packed.instantiate()
		for n in scene.find_children("look_*", "MeshInstance3D", true, false):
			made[str(n.name).trim_prefix("look_")] = true
		scene.free()
	var missing: Array = []
	for part: String in ["body"] + PARTS[kind]:
		if not made.has(part):
			missing.append(part)
	_check(missing.is_empty(), "every part it turns is a mesh of its own (missing %s)" % [missing])
	# On foot: no cab.
	g.view.layered = true
	_check(not _eye(g).has("cab"), "on foot the eye has no cab")
	_check(rides.seat_in(g.player, 0), "in at the wheel")
	var v: VehicleDrive.Ride = rides.rides[0]
	g.view.layered = false
	_check(not _eye(g).has("cab"), "without a window there is no cab")
	if kind == "car":
		var o := ((View.VIEW - 6) * Canvas.WIDTH + View.WIDTH / 2) * 3
		var c := Canvas.new()
		rides.draw_view(c)
		_check(c.pixels[o] + c.pixels[o + 1] > 0, "without a window the car keeps its painted dash")
		g.view.layered = true
		var c3 := Canvas.new()
		rides.draw_view(c3)
		_check(c3.pixels[o] + c3.pixels[o + 1] == 0, "with the cab drawn, no painted dash")
	g.view.layered = true
	var eye := _eye(g)
	var cab: Dictionary = eye.get("cab", {})
	_check(str(cab.get("model", "")) == s.cab, "in the seat the eye is handed the cab")
	var shown := false
	for spr: Variant in g.sprites():
		if spr is View.Sprite and (spr as View.Sprite).track == "ride0":
			shown = true
	_check(not shown, "its own model is left out of the driver's view")
	g.eye_override = {"x": v.x, "y": v.y, "eye": 3.0, "view_angle": 0.0, "pitch": 0.0}
	shown = false
	for spr: Variant in g.sprites():
		if spr is View.Sprite and (spr as View.Sprite).track == "ride0":
			shown = true
	_check(shown, "PHOTO MODE's free camera sees its model")
	g.eye_override = {}
	# Under way and turning right.
	_drive(g, 90, 1.0)
	_drive(g, 20, 1.0, 1.0)
	eye = _eye(g)
	cab = eye.get("cab", {})
	var parts: Dictionary = cab.get("parts", {})
	match kind:
		"car":
			var wheel: float = parts.get("steer", 0.0)
			_check(wheel < -.3, "the wheel turns clockwise for a right turn (%.2f)" % wheel)
			var speed: float = parts.get("speed", VehicleCab.NEEDLE_REST)
			_check(speed < VehicleCab.NEEDLE_REST - .3, "the speedometer's needle rises")
		"mower":
			var wheel2: float = parts.get("steer", 0.0)
			_check(wheel2 < -.3, "the wheel turns clockwise for a right turn (%.2f)" % wheel2)
			var lever: float = parts.get("lever", 0.0)
			_check(lever == VehicleCab.LEVER_ON, "the blade lever is forward while it cuts")
		"airboat":
			var stick: float = parts.get("stick", 0.0)
			_check(stick > .1, "the stick goes over for a right turn (%.2f)" % stick)
			var prop: float = parts.get("prop", 0.0)
			_drive(g, 3, 1.0)
			var prop2: float = _eye(g).get("cab", {}).get("parts", {}).get("prop", 0.0)
			_check(not is_equal_approx(prop, prop2), "the prop turns")
			var drops: Array = rides.get("_looks")["drops"]
			_check(not drops.is_empty(), "spray flies over the bow at speed")
			var c2 := Canvas.new()
			var before := c2.pixels.duplicate()
			g.view_eye = _eye(g)
			VehicleCab.draw_spray(c2, drops, g.view_eye, g.clock)
			_check(c2.pixels != before, "and lands in the view")
	# Drawn: every part between the near plane and the nearest wall.
	var at := Vector3(g.player.x, g.player.y, float(eye["eye"]))
	layer.show_cab(cab, at, g.level)
	var near := INF
	var far := 0.0
	var eye_g := Vector3(at.x, at.z, at.y)
	for node: Node in layer.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if not mesh.is_visible_in_tree():
			continue
		var arrays := mesh.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var xf := mesh.global_transform
		for k in range(0, verts.size(), 3):
			var d := (xf * verts[k]).distance_to(eye_g)
			near = minf(near, d)
			far = maxf(far, d)
	_check(
		near > WorldView3D.NEAR, "drawn, nothing of it is nearer than the near plane (%.3f)" % near
	)
	_check(far < WALL, "and all of it is nearer than a wall can come (%.3f)" % far)
	layer.queue_free()


func _settings(main: Control) -> void:
	var g := _game(main, "speedway")
	var rides: VehiclesScript = g.features["vehicles"]
	rides.seat_in(g.player, 0)
	g.view.layered = true
	_drive(g, 120, 1.0)
	var v: VehicleDrive.Ride = rides.rides[0]
	var s := VehicleDrive.spec(v.kind)
	var b := rides.body(0)
	var base := g.player.as_render_player()
	var lifts := {}
	for k in 6:
		var eye := base.duplicate()
		VehicleCab.dress(eye, v, s, b, 0, .7, 1.0, 1.0 + k * .013, 0.0, true)
		lifts[snappedf(float(eye["eye"]), .0001)] = true
	_check(lifts.size() > 2, "the engine buzzes in the view")
	lifts.clear()
	for k in 6:
		var eye2 := base.duplicate()
		VehicleCab.dress(eye2, v, s, b, 0, .7, 0.0, 1.0 + k * .013, 0.0, true)
		lifts[snappedf(float(eye2["eye"]), .0001)] = true
	_check(lifts.size() == 1, "SCREEN SHAKE off: no buzz")
	var still := base.duplicate()
	VehicleCab.dress(still, v, s, b, 0, 0.0, 1.0, 1.0, 0.0, true)
	var steady_eye: float = still["eye"]
	var steady_pitch: float = still["pitch"]
	var base_eye: float = base["eye"]
	var base_pitch: float = base["pitch"]
	_check(
		is_equal_approx(steady_eye, base_eye) and is_equal_approx(steady_pitch, base_pitch),
		"STILL: no sway, dip or buzz"
	)
	var wide_still: float = still["wide"]
	var moving := base.duplicate()
	VehicleCab.dress(moving, v, s, b, 0, .7, 1.0, 1.0, 0.0, true)
	var wide_moving: float = moving["wide"]
	_check(wide_moving < wide_still, "at speed the view widens (%.3f)" % wide_moving)
	_check(wide_still < 1.0, "a driver's view is wider than FIELD OF VIEW 70")
	var kept := View.fov_focal
	var kept_base := View.base_focal
	View.fov_focal = View.FOCAL_FOR[3]
	View.base_focal = View.FOCAL_FOR[3]
	var wide_view := base.duplicate()
	VehicleCab.dress(wide_view, v, s, b, 0, 0.0, 1.0, 1.0, 0.0, true)
	var wide_chosen: float = wide_view["wide"]
	View.fov_focal = kept
	View.base_focal = kept_base
	_check(is_equal_approx(wide_chosen, 1.0), "never wider than a FIELD OF VIEW chosen wider")


func _plate(main: Control) -> void:
	for kind: String in LEVELS:
		var g := _game(main, str(LEVELS[kind]))
		var rides: VehiclesScript = g.features["vehicles"]
		rides.seat_in(g.player, 0)
		_drive(g, 30, 1.0)
		var v: VehicleDrive.Ride = rides.rides[0]
		var s := VehicleDrive.spec(v.kind)
		var c := Canvas.new()
		VehicleHud.draw(c, g, v, s, true)
		var edge := VehicleHud.EDGE
		var at := VehicleHud.AT
		var o := (at.y * Canvas.WIDTH + at.x + VehicleHud.W / 2) * 3
		var top := Color8(c.pixels[o], c.pixels[o + 1], c.pixels[o + 2])
		_check(top.is_equal_approx(edge), "%s: the plate is drawn in its corner" % kind)
		g.touch_aim = true
		var t := Canvas.new()
		VehicleHud.draw(t, g, v, s, true)
		var o2 := (VehicleHud.AT_TOUCH.y * Canvas.WIDTH + at.x + VehicleHud.W / 2) * 3
		var top2 := Color8(t.pixels[o2], t.pixels[o2 + 1], t.pixels[o2 + 2])
		_check(top2.is_equal_approx(edge), "%s: up under the pin with the touch buttons" % kind)
		g.touch_aim = false
		g.hud.minimal = true
		var m := Canvas.new()
		VehicleHud.draw(m, g, v, s, true)
		var top3 := Color8(m.pixels[o], m.pixels[o + 1], m.pixels[o + 2])
		_check(not top3.is_equal_approx(edge), "%s: HUD MINIMAL keeps only two lines" % kind)
		_check(m.pixels != Canvas.new().pixels, "%s: and draws them" % kind)
		g.hud.minimal = false
		g.hud_style = 1
		var d := Canvas.new()
		VehicleHud.draw(d, g, v, s, true)
		_check(d.pixels != c.pixels, "%s: STATUS PANEL draws the speed on a dial" % kind)
		g.hud_style = 0
	var car := VehicleDrive.Ride.new()
	car.kind = "car"
	var cs := VehicleDrive.spec("car")
	car.vx = cs.top * .6
	_check(int(VehicleCab.gear(car, cs).x) == 3, "the car's gear rises with its speed")
	car.vx = -2.0
	_check(int(VehicleCab.gear(car, cs).x) == -1, "and is R backing up")
	car.hp = cs.hp * .2
	_check(VehicleHud.condition(car, .2) == "ON FIRE", "a rig under a quarter is ON FIRE")
	car.wreck = 1.0
	_check(VehicleHud.condition(car, 0.0) == "BURNT OUT", "a wreck is BURNT OUT")


## Driving is the same whether this machine draws the cab or not.
func _same_drive(main: Control) -> void:
	var drawn := _game(main, "bayou")
	var plain := _game(main, "bayou")
	for g: Game in [drawn, plain]:
		var rides: VehiclesScript = g.features["vehicles"]
		rides.seat_in(g.player, 0)
	drawn.view.layered = true
	for t in 240:
		var c := Game.Controls.new()
		c.forward = 1.0
		c.strafe = .6 if t > 120 else 0.0
		drawn.tick(STEP, c)
		plain.tick(STEP, c)
		_eye(drawn)
	var a: VehicleDrive.Ride = drawn.features["vehicles"].rides[0]
	var b: VehicleDrive.Ride = plain.features["vehicles"].rides[0]
	_check(
		a.x == b.x and a.y == b.y and a.h == b.h and a.vx == b.vx,
		"the airboat drives tick for tick the same with the cab drawn"
	)
