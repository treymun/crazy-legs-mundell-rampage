## Motion strips of the active bodies' steps two and three (pass 15, T11:
## src/active_body.gd, src/dying_doll.gd on play's src/body_play.gd and
## src/stagger.gd), in a real window: each row a coot watched side on from a
## still camera, every tick drawn, fifteen moments (<row>.png in out=: three
## lines of five, 320x200 each, the first the moment before). Read them: the
## body should stagger with weight, catch itself or go over, brace, grab,
## writhe and go slack, never snap or float.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/active_frames.gd -- out=<dir> [rows=caught,rail] [off]
##
## Rows (brace, crawl and get_up shot from behind, the rest from the front):
## caught (a boot on open ground, caught), rail (a boot into the rail
## of the sawmill's raised walkway: over it and down), steps (a boot down the
## walkway's stairs), brace (both barrels: knocked over onto his hands), grab
## (a reel along the walkway's rail: he holds on), writhe, crawl, get_up (a killing shot and the last of
## him: each style made sure of), slack (a killing shot, no style), car (run
## down by the speedway's car), car_flat (run into and left up: knocked flat),
## drunk (the drunk coot walking). off: the active bodies off (RAGDOLLS off).
## Point APPDATA at a scratch folder.
extends "res://tools/death_frames.gd"

const Rows := preload("res://tools/death_rows.gd")
## Ticks after the start each picture is taken at, quick and long.
const AT := [0, 4, 8, 12, 17, 23, 30, 38, 47, 58, 70, 85, 100, 120, 150]
const AT_LONG := [0, 8, 16, 25, 35, 50, 70, 95, 125, 160, 200, 245, 290, 340, 400]
const ROWS := [
	"caught",
	"rail",
	"steps",
	"brace",
	"grab",
	"writhe",
	"crawl",
	"get_up",
	"slack",
	"car",
	"car_flat",
	"drunk",
]

var _rows: Rows


func _run() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a.begins_with("out="):
			out = a.substr(4)
		elif a.begins_with("rows="):
			only = a.substr(5)
		elif a == "off":
			classic = true
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.touring = true
	Effects.enabled = true
	_rows = Rows.new(self)
	var wanted := Array(only.split(",", false))
	for name: String in ROWS:
		if wanted.is_empty() or wanted.has(name):
			await _row(name)
	DyingDoll.force_style = -1
	print("active frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


## Where the row stands: [level, at, floor, way (the push's)].
func _place_for(name: String) -> Array:
	match name:
		"rail":
			return ["sawmill", Vector2(49.0, 38.1), 1.4, Vector2(0.0, -1.0)]
		"grab":
			return ["sawmill", Vector2(46.5, 38.0), 1.4, Vector2(1.0, 0.0)]
		"steps":
			return ["sawmill", Vector2(36.6, 38.25), 1.4, Vector2(-1.0, 0.0)]
		"car", "car_flat":
			return ["speedway", Vector2.INF, 0.0, Vector2.ZERO]
	var open: Dictionary = _rows._open("hickston", false)
	return ["hickston", open["at"], open["top"], open["way"]]


func _row(name: String) -> void:
	var spot := _place_for(name)
	var g: Game = _level(spot[0], [])
	g.spawn_grace = 99.0
	g.weapon_view = 2
	g.finish_slowmo = false
	var at: Vector2 = spot[1]
	var top: float = spot[2]
	var way: Vector2 = spot[3]
	var ride: VehicleDrive.Ride = null
	if name.begins_with("car"):
		var cars: Object = g.features.get("vehicles")
		var list: Array = cars.get("rides")
		ride = list[0]
		way = Vector2.from_angle(ride.h)
		at = Vector2(ride.x, ride.y) + way * 5.0
		top = g.world.floor_under(at.x, at.y, 9.0)
	var kind := "drunk_coot" if name == "drunk" else "coot"
	var facing := atan2(-way.y, -way.x)
	if name == "drunk":
		facing = atan2(way.y, way.x) + PI * .5
	elif name in ["brace", "crawl", "get_up"]:
		# (Shot from behind: he goes over forwards, onto his hands, his face.)
		facing = atan2(way.y, way.x)
	var e := Enemy.new(kind, at.x, at.y, facing)
	e.floor_z = top
	e.last_floor = top
	e.hp = 400.0
	e.max_hp = 400.0
	g.enemies.append(e)
	e.alerted = false
	var cam: Vector3 = _rows._camera(g, at, way, top, 1.0)
	# (The sawmill's raised walkway, its rail and stairs, from the yard.)
	if name == "rail":
		cam = Vector3(50.6, 33.6, -.24)
	elif name == "grab":
		cam = Vector3(52.8, 38.3, 1.4)
	elif name == "steps":
		cam = Vector3(33.6, 33.8, -.24)
	elif name.begins_with("car"):
		cam = _cam_for(g, at, way, top)
	if OS.get_environment("CAM") != "":
		var c := OS.get_environment("CAM").split_floats(",")
		cam = Vector3(c[0], c[1], c[2])
	print("  %s: at %s top %.2f cam %s" % [name, at, top, cam])
	_rows._name = name
	_rows._body = e
	_rows._look = at
	_rows._look_z = NAN
	_rows._frames.clear()
	for _k in 8:
		# (A level's sleeping rooms put a hand in them to sleep: not this one.)
		e.dormant = false
		if name != "drunk":
			e.x = at.x
			e.y = at.y
		await _rows._ticks(g, 1, cam, at, top)
	await _rows._snap()
	e.dormant = false
	_act(g, e, name, way, ride)
	var done := 0
	var times: Array = AT_LONG if name in ["writhe", "crawl", "get_up", "slack", "drunk"] else AT
	for t: int in times.slice(1):
		while done < t:
			e.dormant = false
			if name == "drunk":
				_walk(g, e, at, way)
			if ride != null:
				_drive(ride, name)
			await _rows._ticks(g, 1, cam, at, top)
			done += 1
		if OS.get_environment("CAM") != "":
			print("    t%d man %.2f %.2f floor %.2f alive %s dormant %s p %.2f %.2f %.2f" % [done, e.x, e.y, e.floor_z, e.alive, e.dormant, g.player.x, g.player.y, g.player.eye])
		await _rows._snap()
	_save15(name)


## What happens to him at the start of the row.
func _act(g: Game, e: Enemy, name: String, way: Vector2, ride: VehicleDrive.Ride) -> void:
	var p := g.player
	match name:
		"caught", "rail", "steps":
			_boot(g, e, way)
		"brace":
			_shot(g, e, way, "shotgun", 60.0, .6, 1.0)
		"grab":
			_shot(g, e, way, "shotgun", 60.0, .6, 1.0)
		"writhe", "crawl", "get_up", "slack":
			DyingDoll.force_style = (
				{
					"writhe": DyingDoll.WRITHE,
					"crawl": DyingDoll.CRAWL,
					"get_up": DyingDoll.GET_UP,
					"slack": DyingDoll.LIMP
				}[name]
			)
			e.hp = 10.0
			_shot(g, e, way, "revolver", 30.0, .6, 3.0)
		"car", "car_flat":
			e.hp = 30.0 if name == "car" else 400.0
			# (Dazed: he stands there and takes it, no step out of the way.)
			e.stun = 2.0
			_drive(ride, name)
		"drunk":
			pass
	p.armory.holstered = true


## The car coasting at the man (no driver: features/vehicles.gd runs it).
func _drive(ride: VehicleDrive.Ride, name: String) -> void:
	if ride.hits.is_empty():
		var speed := 8.5 if name == "car" else 4.5
		ride.vx = cos(ride.h) * speed
		ride.vy = sin(ride.h) * speed


## A boot along `way` (features/brawl.gd's, as _boot_lands gives it).
func _boot(g: Game, e: Enemy, way: Vector2) -> void:
	var brawl: Object = g.features.get("brawl")
	var feet: float = g.world.stand(e) + e.z
	g.hit_point = Vector3(e.x, e.y, feet + e.height * .45)
	g.hit_from = Vector2(e.x, e.y) - way * 1.2
	e.hurt(14.0, g, false, false, null, "kick")
	e.stun = maxf(e.stun, .75)
	brawl.call("slide", e, way.x * 7.5, way.y * 7.5, 0)


## A shot along `way` from `far` cells: gun `how`, `amount`, at `up` of him.
func _shot(g: Game, e: Enemy, way: Vector2, how: String, amount: float, up: float, far: float) -> void:
	var p := g.player
	var keep := Vector2(p.x, p.y)
	var from := Vector2(e.x, e.y) - way * far
	p.x = from.x
	p.y = from.y
	g.hit_from = from
	var feet: float = g.world.stand(e) + e.z
	var spot := Vector2(e.x, e.y) - way * e.radius * .8
	var pellets := 8 if how == "shotgun" else 1
	for _k in pellets:
		g.hit_point = Vector3(spot.x, spot.y, feet + e.height * e.variant * up)
		e.hurt(amount / pellets, g, false, false, null, how)
	p.x = keep.x
	p.y = keep.y
	print("  %s: hit %s zone %s alive %s" % [_rows._name, how, e.last_zone, e.alive])


## The drunk walks back and forth across the camera's view.
func _walk(g: Game, e: Enemy, at: Vector2, way: Vector2) -> void:
	if e.stun > 0.0 or Stagger.reeling(e):
		return
	var across := Vector2(-way.y, way.x)
	var off := (Vector2(e.x, e.y) - at).dot(across)
	var heading := atan2(across.y, across.x)
	if off > 1.6:
		e.set_note("walk_back", 1)
	elif off < -1.6:
		e.set_note("walk_back", null)
	if e.has_note("walk_back"):
		heading += PI
	e.advance(1.0 / 60.0, g, heading, 1.0)


## A camera side on to the action from `at` along `way` (2.4 cells of it),
## 3 to 5 cells off on any floor, that sees both ends: the most side on.
func _cam_for(g: Game, at: Vector2, way: Vector2, top: float) -> Vector3:
	var w := g.world
	var mid := at + way * 1.2
	var end := at + way * 2.4
	var best := Vector3(at.x, at.y, top)
	var best_score := -INF
	for k in 32:
		var dir := Vector2.from_angle(k * TAU / 32.0)
		for r: float in [3.0, 3.8, 4.6, 5.4]:
			var c := mid + dir * r
			if c.x < 1 or c.y < 1 or c.x > w.width - 1 or c.y > w.height - 1:
				continue
			var z := w.floor_under(c.x, c.y, top + 2.0)
			if PhysCore.in_wall(w, Vector3(c.x, c.y, z)):
				continue
			# (Up in the air as high as he stands, over a yard below.)
			z = maxf(z, top)
			if w.blocked(c.x, c.y, .25, z + .4):
				continue
			if not w.visible(c.x, c.y, at.x, at.y, z + .95, top + .7):
				continue
			if not w.visible(c.x, c.y, end.x, end.y, z + .95, top + .3):
				continue
			# (Nothing standing between: furniture, a parked dozer.)
			var clear := true
			for k2 in range(1, 12):
				var q := c.lerp(mid, k2 / 12.0)
				var hz := lerpf(z + .95, top + .6, k2 / 12.0)
				if w.blocked(q.x, q.y, .1, hz) or PhysCore.rail_at(w, Vector3(q.x, q.y, hz), .05) != null:
					clear = false
					break
			if not clear:
				continue
			var score := 1.0 - absf(dir.dot(way)) - absf(z - top) * .2 - absf(r - 4.0) * .1
			if score > best_score:
				best_score = score
				best = Vector3(c.x, c.y, z)
	return best


func _save15(name: String) -> void:
	var sheet := Image.create(320 * 5, 202 * 3, false, Image.FORMAT_RGB8)
	sheet.fill(Color(.1, .1, .1))
	for k in _rows._frames.size():
		var f: Image = _rows._frames[k]
		f.convert(Image.FORMAT_RGB8)
		sheet.blit_rect(f, Rect2i(0, 0, 320, 200), Vector2i((k % 5) * 320, (k / 5) * 202))
	sheet.save_png(out.path_join(name + ".png"))
