## How BLUE moves and how he looks moving (pass 12: "he's a frickin speed
## demon and hard to even look at"): frame rows of him beside his player,
## every tick, and their sums. Scenes (SCENES), each on a few chapters:
##   walk, run      his player walking / running the chapter's way through
##   still          his player standing (rest, settling, ranging round)
##   look           his player standing, looking round (90s, a flick about)
##   stopgo         walking three seconds, standing three
##   turnback       walking the way four seconds, turning about, back four
##   fight          a hand told SIC 'EM on (the sprint, the bite, the hold)
##   point          a pickup out of his player's sight (his nose, the point)
##   car            a car coming at him (the jump aside)
##   coop           two players walking, two hounds
## A row a tick (1/120 s): where he is, how fast (cells a second), his
## acceleration, his turn, how far his feet slip (his motion's planted feet
## against the ground: FootModel), what he does, how far from the eye, how
## much of the view and whether over the crosshair, his speed across the view.
##
##   godot --headless --path godot --script res://tools/hound_pace.gd -- \
##       [out=<dir>] [only=walk,still] [levels=hickston,fair] [check] [quiet]
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/hound_pace.gd -- draw out=<dir> [only=..] [snaps]
##
## out= writes <scene>_<level>.csv (the rows) and summary.txt. draw (a window,
## scratch APPDATA) draws every tick and adds what the drawn model's feet do
## (`drawn`: planted feet's slide against his speed); snaps saves a picture
## a second of each scene. check holds the budgets (BUDGETS) and prints
## HOUND PACE OK (tools/check_all.gd runs it).
extends SceneTree

const STEP := 1.0 / 120.0
const Hound := preload("res://src/features/hound.gd")
const RouteMap := preload("res://tools/route_map.gd")
const SCENES := [
	"walk", "run", "still", "look", "stopgo", "turnback", "fight", "point", "car", "coop"
]
const LEVELS := ["hickston", "fair", "quarry", "bayou"]
## Seconds each scene runs.
const LENGTH := {
	"walk": 24.0,
	"run": 24.0,
	"still": 30.0,
	"look": 24.0,
	"stopgo": 24.0,
	"turnback": 24.0,
	"fight": 10.0,
	"point": 10.0,
	"car": 6.0,
	"coop": 20.0,
}
## The view: canvas pixels across and down, and the hound's box (map units:
## half his length, half his width, his height to the head's top).
const VIEW_W := 320.0
const VIEW_H := 156.0
const HALF_LONG := .31
const HALF_WIDE := .09
const TALL := .45
## His player's walk and run (game.gd).
const WALK := 2.75
const RUN := 3.85
## The budgets (check). Each scene on its own: no turn quicker than
## `turn_p95` (degrees a second, the 95th percentile), his feet keeping at
## least `slip_min` of the ground in every gait (calm scenes), never filling
## `cover_most` of the view, never over the crosshair `cross_secs`, and at
## rest (still) no wandering or fidgeting. Over all the calm scenes (not the
## fight or the car; a dog wedged on a level's corner now and then is one
## scene's worst, not his pacing): the middle scene's share of time dashing
## past his player, sprints a minute, acceleration (99th percentile, cells
## a second each second), darts a minute (turnback aside: his player turns
## about), off where he faces (90th percentile), pose pops a minute, and the
## nearest he came to the eye; and the worst scene's against WORST. v3.9.0's
## middle scene: 32% dashing, 18 sprints, 37 cells/s/s, 573 degrees a
## second (his cap), 46 degrees off, 10 darts, 22 pops, feet .14/.42/.14.
const BUDGETS := {
	"turn_p95": 330.0,
	"slip_min": .6,
	"cover_most": .22,
	"cross_secs": .6,
	"rest_moved": 3.0,
	"rest_poses_min": 8.0,
	"fast_share": .06,
	"sprints_min": 3.0,
	"accel_p99": 8.0,
	"darts_min": 3.0,
	"crab_p90": 10.0,
	"pops_min": 4.0,
	"eye_min": .85,
	"zip_p90": 1.0,
}
const WORST := {
	"fast_share": .2,
	"sprints_min": 10.0,
	"accel_p99": 15.0,
	"darts_min": 20.0,
	# Pass 15 (MOVES, the quicker stop: modes.cfg [move] ease_stop 30 -> 40):
	# Walker lets go of its key a tick at every cell it reaches, and the
	# walk dips more for it, so BLUE switched his walk and trot back and
	# forth in turnback on hickston 15 times a minute (6 in its 24 s; 5
	# before). With the key held through, as a player's is, he pops 0 to 2.5
	# a minute in every scene before and after (the other budgets are this
	# walker's and fail with it changed, so it stays). 12 before.
	"pops_min": 16.0,
	"eye_min": .72,
	"zip_p90": 1.6,
}

var main
var out := ""
var only: Array = []
var levels: Array = []
var draw := false
var snaps := false
var check := false
var quiet := false
var failures: Array = []
var feet: FootModel
var summaries: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out = arg.substr(4)
		elif arg.begins_with("only="):
			only = Array(arg.substr(5).split(","))
		elif arg.begins_with("levels="):
			levels = Array(arg.substr(7).split(","))
		elif arg == "draw":
			draw = true
		elif arg == "snaps":
			snaps = true
		elif arg == "check":
			check = true
		elif arg == "quiet":
			quiet = true
	if out != "":
		DirAccess.make_dir_recursive_absolute(out)
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	# (the window draws only when told: its own loop would tick the game too)
	main.set_process(false)
	main.state = "title"
	var started := Time.get_ticks_msec()
	feet = FootModel.new()
	feet.measure(root)
	print("his motions' planted feet (metres his feet go back a beat, share of the beats down):")
	for m: String in feet.back:
		print("  %s  %.3f m a beat, down %.2f" % [m, feet.back[m], feet.down.get(m, 0.0)])
	print("")
	print(Summary.header())
	var scenes: Array = only if not only.is_empty() else SCENES
	var lv: Array = levels if not levels.is_empty() else LEVELS
	if check and levels.is_empty():
		lv = ["hickston", "quarry"]
	for scene: String in scenes:
		var here: Array = lv
		if scene in ["car"]:
			here = ["speedway"]
		elif scene in ["fight", "point", "coop"] and check:
			here = [lv[0]]
		for id: String in here:
			var s: Summary = await _scene(scene, id)
			if s == null:
				if check:
					failures.append("%s %s did not run" % [scene, id])
				continue
			summaries.append(s)
			print(s.line())
			if check:
				_hold(s)
	if out != "":
		var text := Summary.header() + "\n"
		for s: Summary in summaries:
			text += s.line() + "\n"
		var f := FileAccess.open(out.path_join("summary.txt"), FileAccess.WRITE)
		f.store_string(text)
		f.close()
	if check:
		_hold_all()
	print("\n%.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
	if check:
		print(
			"HOUND PACE OK" if failures.is_empty() else "%d HOUND PACE(S) FAILED" % failures.size()
		)
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _hold(s: Summary) -> void:
	var calm := not s.scene in ["fight", "car"]
	var bad: Array = []
	if s.turn_p95 > BUDGETS["turn_p95"] and s.scene != "car":
		bad.append("turns %.0f degrees a second" % s.turn_p95)
	for m: String in s.slip_moving:
		var r := s.slip_ratio(m)
		if calm and r >= 0.0 and r < BUDGETS["slip_min"]:
			bad.append("%s feet go %.2f of the ground" % [m, r])
	if s.cover_most > BUDGETS["cover_most"]:
		bad.append("fills %.0f%% of the view" % (s.cover_most * 100.0))
	if calm and s.cross > BUDGETS["cross_secs"]:
		bad.append("%.1f s over the crosshair" % s.cross)
	if s.scene == "still":
		if s.rest_moved > BUDGETS["rest_moved"]:
			bad.append("wanders %.1f cells at rest" % s.rest_moved)
		if s.rest_poses_min() > BUDGETS["rest_poses_min"]:
			bad.append("%.1f pose changes a minute at rest" % s.rest_poses_min())
	var text := "%s %s" % [s.scene, s.level]
	if bad.is_empty():
		print("  ok   ", text)
	else:
		print("  FAIL ", text, ": ", ", ".join(bad))
		failures.append(text)


## Over the calm scenes: the middle one against BUDGETS, the worst against
## WORST.
func _hold_all() -> void:
	var values := {}
	for key: String in WORST:
		values[key] = []
	for s: Summary in summaries:
		if s.scene in ["fight", "car"]:
			continue
		if s.scene != "point":
			values["fast_share"].append(s.fast_share)  # (his nose's errand aside)
		values["sprints_min"].append(s.sprints_min())
		values["accel_p99"].append(s.accel_p99)
		if s.scene != "turnback":
			values["darts_min"].append(s.darts_min())
		values["pops_min"].append(s.pops_min())
		values["eye_min"].append(s.eye_min)
		values["zip_p90"].append(s.zip_p90)
	var crabs: Array = []
	for s: Summary in summaries:
		if not s.scene in ["fight", "car"]:
			crabs.append(s.crab_p90)
	values["crab_p90"] = crabs
	print("\nOVER THE CALM SCENES (middle, worst)")
	for key: String in values:
		var arr: Array = values[key]
		if arr.is_empty():
			continue
		arr.sort()
		var low := key == "eye_min"
		var middle: float = arr[arr.size() / 2]
		var worst: float = arr[0] if low else arr[arr.size() - 1]
		var budget: float = BUDGETS[key]
		var ok: bool = middle >= budget if low else middle <= budget
		if WORST.has(key):
			var limit: float = WORST[key]
			ok = ok and (worst >= limit if low else worst <= limit)
		var line := (
			"%-12s %7.2f %7.2f  (budget %.2f%s)"
			% [
				key,
				middle,
				worst,
				BUDGETS[key],
				", worst %.2f" % WORST[key] if WORST.has(key) else ""
			]
		)
		print("  ok   " if ok else "  FAIL ", line)
		if not ok:
			failures.append(key)


# ------------------------------------------------------------------ games


func _game(id: String, coop: bool) -> Game:
	var g: Game
	if draw:
		main.options["hound"] = 1
		main.start(id)
		g = main.game
	else:
		g = main.make_game(id)
		g.configure({"difficulty": 1, "hound": 1})
	if coop:
		Modes.setup(g, Modes.COOP, 2)
	g.cheats.god = true
	g.lessons = false
	g.barks.enabled = false
	g.spawn_grace = 99.0
	for e: Enemy in g.enemies:
		e.dormant = true
	for door: LevelData.Door in g.world.doors:
		door.opened = true
		door.progress = 1.0
	g.world.locked_gates.clear()
	return g


## The cells of the level's way through (route_map's stops, every door open).
func _way(g: Game) -> Array:
	var level: LevelData = g.world
	var stops := RouteMap.stops_of(level)
	var field := FlowField.new(level)
	field.reach = 100000
	field.doors_open = true
	field.every_door = true
	var from := Vector2(g.player.x, g.player.y)
	var cells: Array = []
	for stop: Array in stops:
		var to: Vector2 = stop[1]
		field.origin = Vector2i(-1, -1)
		field.next_at = 0.0
		field.update(to.x, to.y, 0.0)
		var path: Array = []
		var begin := RouteMap.nearest_reached(field, from)
		field.waypoint(begin.x, begin.y, 100000, path)
		cells.append_array(path)
		from = to
		if cells.size() > 400:
			break
	return cells


## A walker along the way: each tick it steers its player toward the cells
## ahead (turning as a mouse does, at most TURN a second).
class Walker:
	const TURN := 5.0
	var cells: Array = []
	var i := 0
	var dir := 1
	var stuck := 0.0
	var last := INF

	func steer(g: Game, p: Player, c: Game.Controls, dt: float, run: bool) -> void:
		if cells.is_empty():
			return
		i = clampi(i, 0, cells.size() - 1)
		var cell: Vector2i = cells[i]
		var here := Vector2(cell.x + .5, cell.y + .5)
		var gap := here.distance_to(Vector2(p.x, p.y))
		if gap < .6:
			i += dir
			if i >= cells.size() or i < 0:
				dir = -dir
				i = clampi(i, 0, cells.size() - 1)
			last = INF
			stuck = 0.0
			return
		var aim := here
		for k in range(1, 3):
			var j := i + k * dir
			if j >= 0 and j < cells.size():
				var a: Vector2i = cells[j]
				aim = Vector2(a.x + .5, a.y + .5)
		var want := atan2(aim.y - p.y, aim.x - p.x)
		p.angle += clampf(wrapf(want - p.angle, -PI, PI), -TURN * dt, TURN * dt)
		c.forward = 1.0
		c.running = run
		if gap < last - .01:
			last = gap
			stuck = 0.0
		else:
			stuck += dt
		if stuck > 1.0:
			p.x = here.x
			p.y = here.y
			p.floor_z = g.world.floor_under(here.x, here.y, p.floor_z + 1.0)
			p.eye = p.floor_z + .95
			i += dir
			stuck = 0.0
			last = INF

	func about() -> void:
		dir = -dir


func _dog(g: Game, slot := 0) -> Hound.Dog:
	var h: Hound = g.features["hound"]
	for d: Hound.Dog in h.dogs:
		if d.slot == slot:
			return d
	return null


## An open spot about `far` from (x, y), on its floor and in its sight.
func _spot(g: Game, x: float, y: float, far: float, ahead := NAN) -> Vector2:
	var reach := far
	while reach >= 1.0:
		for k in 24:
			var a := k * TAU / 24.0
			if not is_nan(ahead):
				a = ahead + (k / 2) * .2 * (1.0 if k % 2 == 0 else -1.0)
			var at := Vector2(x, y) + Vector2(cos(a), sin(a)) * reach
			if at.x < 1 or at.y < 1 or at.x > g.world.width - 1 or at.y > g.world.height - 1:
				continue
			if g.world.blocked(at.x, at.y, .4) or g.world.deep_at(at.x, at.y):
				continue
			if absf(g.world.elevation(at.x, at.y) - g.world.elevation(x, y)) > .3:
				continue
			var eye := g.world.elevation(x, y) + .9
			if not g.world.visible(x, y, at.x, at.y, eye, g.world.elevation(at.x, at.y) + .5):
				continue
			return at
		reach -= .5
	return Vector2.INF


## Somewhere open with room round it: the way's first cell with an open
## spot `room` off on most sides (the still and look scenes stand there).
func _open(g: Game, cells: Array, room: float) -> Vector2:
	for k in range(0, cells.size(), 3):
		var c: Vector2i = cells[k]
		var at := Vector2(c.x + .5, c.y + .5)
		var open := 0
		for j in 8:
			var a := j * TAU / 8.0
			if g.world.visible(
				at.x,
				at.y,
				at.x + cos(a) * room,
				at.y + sin(a) * room,
				g.world.elevation(at.x, at.y) + .5,
				g.world.elevation(at.x, at.y) + .5
			):
				open += 1
		if open >= 7:
			return at
	return Vector2(g.player.x, g.player.y)


# ------------------------------------------------------------------ a scene


func _scene(scene: String, id: String) -> Summary:
	var g := _game(id, scene == "coop")
	var c0 := Game.Controls.new()
	g.tick(STEP, c0)
	var d := _dog(g)
	if d == null:
		print("  %s %s: no hound" % [scene, id])
		return null
	var h: Hound = g.features["hound"]
	var p := g.player
	var walker := Walker.new()
	walker.cells = _way(g)
	var length: float = LENGTH[scene]
	var s := Summary.new()
	s.scene = scene
	s.level = id
	s.feet = feet
	var rows := PackedStringArray()
	rows.append(Track.HEAD)
	var rows2 := PackedStringArray()
	rows2.append(Track.HEAD)
	var track := Track.new()
	var track2 := Track.new()
	var s2 := Summary.new()
	s2.scene = "coop2"
	s2.level = id
	s2.feet = feet
	var q: Player = g.players[1] if g.players.size() > 1 else null
	var trail: Array = []
	var foe: Enemy = null
	var car: VehicleDrive.Ride = null
	var turn_to := p.angle
	if scene in ["still", "look"]:
		var at := _open(g, walker.cells, 4.0)
		Modes.place(g, p, at.x, at.y, p.angle)
		d.x = p.x - cos(p.angle) * 1.4
		d.y = p.y - sin(p.angle) * 1.4
		d.floor_z = g.world.floor_under(d.x, d.y, g.world.stand(p) + .4)
		turn_to = p.angle
	elif scene == "fight":
		foe = _setup_fight(g, p)
		if foe == null:
			print("  fight %s: no hand to sic" % id)
			return null
	elif scene == "point":
		if not _setup_point(g, p, d):
			print("  point %s: nowhere to hide a pickup" % id)
			return null
	elif scene == "car":
		car = _setup_car(g, p, d)
		if car == null:
			print("  car %s: no car" % id)
			return null
	var ticks := int(length / STEP)
	var snap_every := int(1.0 / STEP)
	for t in ticks:
		var now := t * STEP
		var c := Game.Controls.new()
		match scene:
			"walk", "coop":
				walker.steer(g, p, c, STEP, false)
			"run":
				walker.steer(g, p, c, STEP, true)
			"still", "fight", "point":
				pass
			"look":
				# A new way to look every 2.5 s, a quick flick about at 12 s.
				var k := int(now / 2.5)
				var turns := [0.0, 1.57, 3.14, -1.0, 0.6, 2.4, 0.0, -2.0, 1.0, 3.0]
				turn_to = turns[k % turns.size()] + (PI if now > 12.0 else 0.0)
				var rate := 12.0 if absf(now - 12.0) < .3 else 4.0
				p.angle += clampf(wrapf(turn_to - p.angle, -PI, PI), -rate * STEP, rate * STEP)
			"stopgo":
				if fmod(now, 6.0) < 3.0:
					walker.steer(g, p, c, STEP, false)
			"turnback":
				var leg := int(now / 4.0)
				if leg != int((now - STEP) / 4.0) and t > 0:
					walker.about()
				walker.steer(g, p, c, STEP, false)
			"car":
				var ahead := Vector2(d.x - car.x, d.y - car.y)
				if now < 3.0 and ahead.dot(Vector2(cos(car.h), sin(car.h))) > -1.0:
					car.vx = cos(car.h) * 6.0
					car.vy = sin(car.h) * 6.0
		if scene == "fight" and absf(now - 1.0) < STEP * .5:
			p.angle = atan2(foe.y - p.y, foe.x - p.x)
			h.command(p)
		if scene == "fight" and absf(now - 7.0) < STEP * .5 and foe.alive:
			foe.hurt(foe.hp + 50.0, g)
		if q != null:
			trail.append(Vector3(p.x, p.y, p.angle))
			if trail.size() > 140:
				var back: Vector3 = trail.pop_front()
				var was := Vector2(q.x, q.y)
				q.x = back.x + cos(back.z + PI * .5) * .7
				q.y = back.y + sin(back.z + PI * .5) * .7
				q.angle = back.z
				q.vx = (q.x - was.x) / STEP
				q.vy = (q.y - was.y) / STEP
				q.floor_z = g.world.floor_under(q.x, q.y, q.floor_z + .6)
				q.eye = q.floor_z + .95
		g.tick(STEP, c)
		var drawn := NAN
		if draw:
			main.render()
			await process_frame
			drawn = feet.drawn_slide(main, g, d, STEP)
			if snaps and out != "" and t % snap_every == 0:
				await RenderingServer.frame_post_draw
				var name := "%s_%s_%02d.png" % [scene, id, int(now)]
				root.get_texture().get_image().save_png(out.path_join(name))
		rows.append(track.row(g, p, d, h, now, drawn, s))
		if q != null:
			var d2 := _dog(g, 1)
			if d2 != null:
				rows2.append(track2.row(g, q, d2, h, now, NAN, s2))
	s.finish()
	if q != null:
		s2.finish()
		summaries.append(s2)
		print(s2.line())
		if check:
			_hold(s2)
	if out != "":
		var f := FileAccess.open(out.path_join("%s_%s.csv" % [scene, id]), FileAccess.WRITE)
		f.store_string("\n".join(rows) + "\n")
		f.close()
		if q != null:
			var f2 := FileAccess.open(out.path_join("coop2_%s.csv" % id), FileAccess.WRITE)
			f2.store_string("\n".join(rows2) + "\n")
			f2.close()
	return s


func _setup_fight(g: Game, p: Player) -> Enemy:
	var foe: Enemy = null
	for e: Enemy in g.enemies:
		e.dormant = false
		if foe == null and e.hostile and HoundNose.takes(e) and e.tactical():
			foe = e
		e.dormant = true
	if foe == null:
		print("  (no hand of a kind he takes among %d)" % g.enemies.size())
		return null
	var cells := _way(g)
	var at := _open(g, cells, 6.0)
	Modes.place(g, p, at.x, at.y, p.angle)
	var spot := _spot(g, p.x, p.y, 7.0, p.angle)
	if spot == Vector2.INF:
		spot = _spot(g, p.x, p.y, 7.0)
	if spot == Vector2.INF:
		print("  (no open spot by %.1f,%.1f)" % [p.x, p.y])
		return null
	p.angle = atan2(spot.y - p.y, spot.x - p.x)
	foe.x = spot.x
	foe.y = spot.y
	foe.floor_z = g.world.elevation(spot.x, spot.y)
	foe.dormant = false
	foe.alerted = true
	foe.mind = null
	var d := _dog(g)
	d.x = p.x - cos(p.angle) * 1.4
	d.y = p.y - sin(p.angle) * 1.4
	d.floor_z = g.world.floor_under(d.x, d.y, g.world.stand(p) + .4)
	return foe


func _setup_point(g: Game, p: Player, d: Hound.Dog) -> bool:
	# A spot for him near his player and a box of shells he can see from it
	# that his player cannot (hound_check's _hidden_pair).
	var z := g.world.elevation(p.x, p.y)
	for ring in range(2, 6):
		for k in 16:
			var a := k * TAU / 16.0
			var dog_at := Vector2(p.x, p.y) + Vector2(cos(a), sin(a)) * ring
			if g.world.blocked(dog_at.x, dog_at.y, .35):
				continue
			if absf(g.world.elevation(dog_at.x, dog_at.y) - z) > .1:
				continue
			if not g.world.visible(p.x, p.y, dog_at.x, dog_at.y, p.eye, z + .4):
				continue
			for r2 in range(3, 7):
				for k2 in 16:
					var b := k2 * TAU / 16.0
					var at := dog_at + Vector2(cos(b), sin(b)) * r2
					if (
						at.x < 1
						or at.y < 1
						or at.x > g.world.width - 1
						or at.y > g.world.height - 1
					):
						continue
					if (
						g.world.blocked(at.x, at.y, .3)
						or absf(g.world.elevation(at.x, at.y) - z) > .1
					):
						continue
					if not g.world.visible(dog_at.x, dog_at.y, at.x, at.y, z + .4, z + .2):
						continue
					if g.world.visible(p.x, p.y, at.x, at.y, p.eye, z + .2):
						continue
					d.x = dog_at.x
					d.y = dog_at.y
					d.floor_z = z
					var h: Hound = g.features["hound"]
					for door: LevelData.Door in g.world.doors:
						h.bayed[HoundNose.key(Vector2(door.x + .5, door.y + .5))] = 0.0
					g.add_pickup("shells", at.x, at.y)
					d.next_nose = 0.0
					d.next_sniff = 0.0
					return true
	return false


func _setup_car(g: Game, p: Player, d: Hound.Dog) -> VehicleDrive.Ride:
	var rides: Game.VehiclesScript = g.features.get("vehicles")
	if rides == null or rides.rides.is_empty():
		return null
	var v: VehicleDrive.Ride = rides.rides[0]
	# The dog and his player beside the car's way, the car coming on.
	var ahead := Vector2(cos(v.h), sin(v.h))
	var side := Vector2(-ahead.y, ahead.x)
	var at := Vector2(v.x, v.y) + ahead * 7.0
	d.x = at.x
	d.y = at.y
	d.floor_z = g.world.floor_under(d.x, d.y, v.z + .5)
	var pa := at + side * 2.0 - ahead * 1.0
	Modes.place(g, p, pa.x, pa.y, atan2(v.y - pa.y, v.x - pa.x))
	return v


# ------------------------------------------------------------------ a row


## One hound's rows: what changed since the last tick.
class Track:
	const HEAD := (
		"t,px,py,x,y,v,accel,face,turn,crab,state,job,pace,speed,frame,beats,slip,"
		+ "gap,eye,cover,cross,onscreen,screen_x,player_v,drawn"
	)
	var was := Vector3.INF
	var was_angle := 0.0
	var was_gait := NAN
	var was_motion := ""
	var was_p := Vector2.INF
	var vs: Array[float] = []
	var ps: Array[Vector2] = []
	var pps: Array[Vector2] = []

	func row(
		g: Game, p: Player, d: Hound.Dog, h: Hound, now: float, drawn: float, s: Summary
	) -> String:
		var dt := STEP
		var here := Vector3(d.x, d.y, d.floor_z)
		var v := 0.0
		var move := Vector2.ZERO
		if was != Vector3.INF:
			move = Vector2(here.x - was.x, here.y - was.y)
			v = move.length() / dt
			if v > 12.0:
				v = 0.0  # a jump (put back, turned up), not a run
				move = Vector2.ZERO
		# Speed smoothed over a tenth of a second, its change the acceleration.
		ps.append(Vector2(here.x, here.y))
		if ps.size() > 13:
			ps.remove_at(0)
		var smooth := 0.0
		if ps.size() >= 13:
			smooth = ps[0].distance_to(ps[ps.size() - 1]) / (dt * 12.0)
			if smooth > 12.0:
				smooth = 0.0
		vs.append(smooth)
		if vs.size() > 13:
			vs.remove_at(0)
		var accel := 0.0
		if vs.size() >= 13:
			accel = (vs[vs.size() - 1] - vs[0]) / (dt * 12.0)
		var turn := (
			rad_to_deg(wrapf(d.angle - was_angle, -PI, PI)) / dt if was != Vector3.INF else 0.0
		)
		var crab := 0.0
		if v > .8:
			crab = absf(rad_to_deg(wrapf(move.angle() - d.angle, -PI, PI)))
		var pose: Array = HoundLooks.pose(h, d)
		var frame: String = pose[0]
		var gait: float = pose[1]
		var beats := 0.0
		var motion := frame[0] if ActorView.is_run(frame) else ""
		if not is_nan(was_gait) and motion != "" and motion == was_motion:
			beats = (gait - was_gait) / (PI * .5) / dt
		var slip := -1.0
		if motion in s.feet.back and v > .5:
			slip = beats * float(s.feet.back[motion]) * HoundLooks.SIZE / v
		# How he sits in the view.
		var view := InView.of(g, p, d)
		if was != Vector3.INF and view.on:
			view.zip = (
				absf(InView.screen_x(p, d.x, d.y) - InView.screen_x(p, was.x, was.y)) / VIEW_W / dt
			)
		# His player's speed: where they truly went (a player running into a
		# wall stands), over a tenth of a second.
		pps.append(Vector2(p.x, p.y))
		if pps.size() > 13:
			pps.remove_at(0)
		var pv := 0.0
		if pps.size() >= 13:
			pv = pps[0].distance_to(pps[pps.size() - 1]) / (dt * 12.0)
			if pv > 12.0:
				pv = 0.0
		var gap := Vector2(d.x - p.x, d.y - p.y).length()
		# The walker put its player on a cell it was caught short of: no
		# player jumps in play, so the next moments are left out of the sums.
		if was_p != Vector2.INF and was_p.distance_to(Vector2(p.x, p.y)) > .5:
			s.skip_until = now + 1.5
		was_p = Vector2(p.x, p.y)
		if now >= s.skip_until:
			s.p_way = (pps[pps.size() - 1] - pps[0]).angle() if pps.size() >= 2 else 0.0
		s.add(now, v, smooth, accel, turn, crab, d, frame, motion, slip, gap, view, pv, drawn)
		was = here
		was_angle = d.angle
		was_gait = gait
		was_motion = motion
		return (
			(
				"%.3f,%.2f,%.2f,%.3f,%.3f,%.2f,%.2f,%.1f,%.0f,%.0f,%d,%s,%.2f,%.2f,"
				+ "%s,%.2f,%.2f,%.2f,%.2f,%.3f,%d,%d,%.1f,%.2f,%s"
			)
			% [
				now,
				p.x,
				p.y,
				d.x,
				d.y,
				v,
				accel,
				rad_to_deg(d.angle),
				turn,
				crab,
				d.state,
				Hound.JOBS[d.job],
				d.pace,
				d.speed,
				frame,
				beats,
				slip,
				gap,
				view.eye,
				view.cover,
				1 if view.cross else 0,
				1 if view.on else 0,
				view.sx,
				pv,
				"" if is_nan(drawn) else "%.2f" % drawn
			]
		)


## Where the hound falls in player p's view (the old projection, View).
class InView:
	var eye := 0.0
	var cover := 0.0
	var cross := false
	var on := false
	var sx := -1.0
	## How fast his own going moves him across the view (views a second).
	var zip := 0.0

	static func screen_x(p: Player, x: float, y: float) -> float:
		var fx := cos(p.angle)
		var fy := sin(p.angle)
		var dx := x - p.x
		var dy := y - p.y
		var ahead := maxf(dx * fx + dy * fy, .3)
		return VIEW_W / 2.0 + (dy * fx - dx * fy) / ahead * View.base_focal

	static func of(g: Game, p: Player, d: Hound.Dog) -> InView:
		var out := InView.new()
		var mid := Vector3(d.x, d.y, d.floor_z + TALL * .5)
		out.eye = mid.distance_to(Vector3(p.x, p.y, p.eye))
		var fx := cos(p.angle)
		var fy := sin(p.angle)
		var horizon := VIEW_H / 2.0 + p.pitch
		var focal := View.base_focal
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var front := 0
		var fwd := Vector2(cos(d.angle), sin(d.angle))
		var side := Vector2(-fwd.y, fwd.x)
		for a: float in [-HALF_LONG, HALF_LONG]:
			for b: float in [-HALF_WIDE, HALF_WIDE]:
				for z: float in [0.0, TALL]:
					var at := Vector2(d.x, d.y) + fwd * a + side * b
					var dx := at.x - p.x
					var dy := at.y - p.y
					var ahead := dx * fx + dy * fy
					if ahead < .12:
						continue
					front += 1
					var x := VIEW_W / 2.0 + (dy * fx - dx * fy) / ahead * focal
					var y := horizon - (d.floor_z + z - p.eye) / ahead * focal
					lo = Vector2(minf(lo.x, x), minf(lo.y, y))
					hi = Vector2(maxf(hi.x, x), maxf(hi.y, y))
		if front == 0:
			return out
		var cx0 := clampf(lo.x, 0.0, VIEW_W)
		var cx1 := clampf(hi.x, 0.0, VIEW_W)
		var cy0 := clampf(lo.y, 0.0, VIEW_H)
		var cy1 := clampf(hi.y, 0.0, VIEW_H)
		var area := (cx1 - cx0) * (cy1 - cy0)
		if area <= 0.0:
			return out
		if not g.world.visible(p.x, p.y, d.x, d.y, p.eye, d.floor_z + .3):
			return out
		out.on = true
		out.cover = area / (VIEW_W * VIEW_H)
		out.sx = (cx0 + cx1) * .5
		var cx := VIEW_W / 2.0
		out.cross = lo.x <= cx and hi.x >= cx and lo.y <= horizon and hi.y >= horizon
		return out


# ------------------------------------------------------------------ sums


class Summary:
	var scene := ""
	var level := ""
	var feet: FootModel
	var ticks := 0
	var speeds: Array[float] = []
	var player_speeds: Array[float] = []
	var fast := 0
	var near_ticks := 0
	var fast_share := 0.0
	var sprints := 0
	var sprinting := false
	var accels: Array[float] = []
	var accel_p99 := 0.0
	var turns: Array[float] = []
	var turn_p95 := 0.0
	var crabs: Array[float] = []
	var crab_p90 := 0.0
	var darts := 0
	var dirs: Array = []
	var group := ""
	var group_was := ""
	var group_at := -10.0
	var switches := 0
	var pops := 0
	var slip_moving := {}
	var slip_sum := {}
	var eye_min := INF
	var eye_near := 0
	var cover_most := 0.0
	var cross := 0.0
	var zips: Array[float] = []
	var zip_p90 := 0.0
	var last_sx := -1.0
	var on_ticks := 0
	var flicks := 0
	var was_on := false
	var orbit := 0.0
	var last_bearing := NAN
	var rest_moved := 0.0
	var rest_ticks := 0
	var rest_poses := 0
	var rest_turn := 0.0
	var rest_last := ""
	var rest_at := Vector2.INF
	var rest_angle := NAN
	var drawn: Array[float] = []
	var v_top := 0.0
	var skip_until := -1.0
	var p_way := 0.0

	static func header() -> String:
		return (
			(
				"%-8s %-9s %5s %5s %5s %5s %5s %5s %5s %5s %5s %5s %5s"
				+ " %5s %5s %5s %5s %5s %5s %5s %5s %6s %6s %5s"
			)
			% [
				"scene",
				"level",
				"pv",
				"v50",
				"v90",
				"vtop",
				"fast",
				"spr/m",
				"acc99",
				"trn95",
				"crb90",
				"dart",
				"pop/m",
				"slipW",
				"slipT",
				"slipR",
				"eye",
				"cov",
				"cross",
				"zip90",
				"onscr",
				"orbit",
				"rest",
				"drawn"
			]
		)

	func add(
		now: float,
		v: float,
		smooth: float,
		accel: float,
		turn: float,
		crab: float,
		d: Hound.Dog,
		frame: String,
		motion: String,
		slip: float,
		gap: float,
		view: InView,
		pv: float,
		slide: float
	) -> void:
		ticks += 1
		speeds.append(smooth)
		player_speeds.append(pv)
		v_top = maxf(v_top, smooth)
		if gap < 5.0:
			near_ticks += 1
			if smooth > maxf(pv, 0.5) + 1.5:
				fast += 1
		if smooth > 5.0 and not sprinting:
			sprints += 1
			sprinting = true
		elif smooth < 4.0:
			sprinting = false
		accels.append(absf(accel))
		if smooth > .3:
			turns.append(absf(turn))
		if v > .8:
			crabs.append(crab)
		# Darting: his way reversed (over 120 degrees) within .6 s, trotting or
		# quicker both times, his player not turned about themselves.
		if smooth > 2.0 and ticks % 6 == 0:
			var dir := float(d.angle)
			dirs.append([now, dir, p_way, pv])
			while not dirs.is_empty() and now - float(dirs[0][0]) > .6:
				dirs.pop_front()
			for e: Array in dirs:
				var about := (
					float(e[3]) > .6 and pv > .6 and absf(wrapf(p_way - float(e[2]), -PI, PI)) > 1.0
				)
				if absf(wrapf(dir - float(e[1]), -PI, PI)) > 2.1 and not about:
					darts += 1
					dirs.clear()
					break
		# A pop: back to the pose he was in before within .4 s (a flicker
		# between two), not a walk going into a trot and on into a lope.
		var g := frame[0] if ActorView.is_run(frame) else frame
		if g != group:
			if g == group_was and now - group_at < .4:
				pops += 1
			switches += 1
			group_was = group
			group = g
			group_at = now
		if slip >= 0.0:
			slip_moving[motion] = float(slip_moving.get(motion, 0)) + 1.0
			slip_sum[motion] = float(slip_sum.get(motion, 0.0)) + slip
		eye_min = minf(eye_min, view.eye)
		if view.on:
			on_ticks += 1
			cover_most = maxf(cover_most, view.cover)
			if view.cross:
				cross += STEP
			zips.append(view.zip)
		if view.on != was_on:
			flicks += 1
			was_on = view.on
		if not is_nan(slide):
			drawn.append(slide)
		# Round a standing player: how far round him he goes.
		if pv < .3 and gap < 5.0:
			var p_at := Vector2(d.x, d.y)
			var bearing := atan2(p_at.y, p_at.x)
			if not is_nan(last_bearing):
				orbit += absf(rad_to_deg(wrapf(bearing - last_bearing, -PI, PI)))
			last_bearing = bearing
		# At rest (the still scene after its first six seconds).
		if scene == "still" and now > 6.0:
			rest_ticks += 1
			var here := Vector2(d.x, d.y)
			if rest_at != Vector2.INF:
				rest_moved += here.distance_to(rest_at)
			rest_at = here
			if (
				frame != rest_last
				and not (
					ActorView.is_run(frame) and rest_last.length() == 2 and rest_last[0] == frame[0]
				)
			):
				rest_poses += 1
			rest_last = frame
			if not is_nan(rest_angle):
				rest_turn += absf(wrapf(d.angle - rest_angle, -PI, PI))
			rest_angle = d.angle

	func finish() -> void:
		accel_p99 = _pct(accels, .99)
		turn_p95 = _pct(turns, .95)
		crab_p90 = _pct(crabs, .9)
		zip_p90 = _pct(zips, .9)
		fast_share = float(fast) / maxf(1.0, near_ticks)

	func minutes() -> float:
		return maxf(ticks * STEP / 60.0, .001)

	func sprints_min() -> float:
		return sprints / minutes()

	func darts_min() -> float:
		return darts / minutes()

	func pops_min() -> float:
		return pops / minutes()

	func rest_poses_min() -> float:
		return rest_poses / maxf(rest_ticks * STEP / 60.0, .001)

	func slip_ratio(m: String) -> float:
		var n: float = slip_moving.get(m, 0.0)
		if n < 24.0:
			return -1.0
		return float(slip_sum[m]) / n

	func line() -> String:
		var ds := "-"
		if not drawn.is_empty():
			ds = "%.2f" % _pct(drawn, .5)
		var sw := slip_ratio("w")
		var st := slip_ratio("t")
		var sr := slip_ratio("r")
		return (
			(
				"%-8s %-9s %5.2f %5.2f %5.2f %5.2f %4.0f%% %5.1f %5.1f %5.0f %5.0f %5.1f %5.1f"
				+ " %5s %5s %5s %5.2f %4.0f%% %5.1f %5.2f %4.0f%% %6.0f %6.1f %5s"
			)
			% [
				scene,
				level,
				_pct(player_speeds, .5),
				_pct(speeds, .5),
				_pct(speeds, .9),
				v_top,
				fast_share * 100.0,
				sprints_min(),
				accel_p99,
				turn_p95,
				crab_p90,
				darts_min(),
				pops_min(),
				"-" if sw < 0.0 else "%.2f" % sw,
				"-" if st < 0.0 else "%.2f" % st,
				"-" if sr < 0.0 else "%.2f" % sr,
				eye_min,
				cover_most * 100.0,
				cross,
				zip_p90,
				100.0 * on_ticks / maxf(1.0, ticks),
				orbit / minutes(),
				rest_moved,
				ds
			]
		)

	static func _pct(a: Array[float], k: float) -> float:
		if a.is_empty():
			return 0.0
		var b := a.duplicate()
		b.sort()
		return b[clampi(int(b.size() * k), 0, b.size() - 1)]


# ------------------------------------------------------------------ his feet


## His model's feet: how far a planted foot goes back a beat in each of his
## gaits (walk w, trot t, gallop r, tracking n, limp l), from the model's own
## keys (the parts within FOOT of the ground standing), and what the drawn
## model's planted feet do in the window.
class FootModel:
	## A part is a foot when its lowest point standing is within this of the
	## ground; planted when within PLANT of its lowest in the motion.
	const FOOT := .03
	const PLANT := .012
	const SAMPLES := 64
	var back := {}
	var down := {}
	var parts := {}
	var foot_groups := {}
	var _was := {}

	func measure(root: Node) -> void:
		var models := ActorModels.new(Assets.new())
		var view := models.scene("hound").instantiate() as ActorView
		root.add_child(view)
		view.setup(models)
		var sk := view.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var player := view.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		_parts(view, sk)
		var i0: float = models.key_time("hound", "i0")
		player.seek(i0, true)
		# His four feet: the parts near the ground standing, by quarter (front
		# or hind, left or right).
		var groups := {}
		for bone: int in parts:
			var at := _low(sk, bone)
			if at.y < FOOT:
				var key := ("f" if at.z > 0.0 else "h") + ("l" if at.x > 0.0 else "r")
				if not groups.has(key):
					groups[key] = []
				groups[key].append(bone)
		foot_groups = groups
		for m: String in ["w", "t", "r", "n", "l"]:
			var t0: Variant = models.key_time("hound", m + "0")
			if t0 == null:
				continue
			# Each foot's sole (its lowest point) and middle at every sample.
			var soles := {}
			for k in SAMPLES + 1:
				player.seek(float(t0) + 4.0 * k / SAMPLES * ActorModels.KEY_TIME, true)
				for key: String in groups:
					if not soles.has(key):
						soles[key] = []
					soles[key].append(_foot(sk, groups[key]))
			var speeds: Array[float] = []
			var planted := 0
			var samples := 0
			for key: String in soles:
				var arr: Array = soles[key]
				var least := INF
				for at: Vector3 in arr:
					least = minf(least, at.y)
				for k in SAMPLES:
					samples += 1
					var a: Vector3 = arr[k]
					var b: Vector3 = arr[k + 1]
					if a.y < least + PLANT and b.y < least + PLANT:
						speeds.append((a.z - b.z) * SAMPLES / 4.0)
						planted += 1
			if planted > 0:
				# The middle of how fast planted feet go back (a foot coming
				# down or lifting, still low, goes forward a little).
				speeds.sort()
				back[m] = speeds[speeds.size() / 2]
				down[m] = float(planted) / samples
		view.queue_free()

	## Each part's bind and its own vertices (those wholly on its bone).
	func _parts(view: Node, sk: Skeleton3D) -> void:
		for child in view.find_children("*", "MeshInstance3D", true, false):
			var mi := child as MeshInstance3D
			if mi.mesh == null or mi.skin == null:
				continue
			for surface in mi.mesh.get_surface_count():
				var arrays := mi.mesh.surface_get_arrays(surface)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				var per := bones.size() / maxi(1, verts.size())
				for i in verts.size():
					if weights[i * per] < .99:
						continue
					var bind := bones[i * per]
					var bone := mi.skin.get_bind_bone(bind)
					if bone < 0:
						bone = sk.find_bone(mi.skin.get_bind_name(bind))
					if not parts.has(bone):
						parts[bone] = [mi.skin.get_bind_pose(bind), PackedVector3Array()]
					var arr: PackedVector3Array = parts[bone][1]
					arr.append(verts[i])
					parts[bone][1] = arr

	## A part's middle (x, z) at its lowest point's height (y), model space.
	func _low(sk: Skeleton3D, bone: int, place := Transform3D.IDENTITY) -> Vector3:
		var bind: Transform3D = parts[bone][0]
		var pose := place * sk.get_bone_global_pose(bone) * bind
		var vs: PackedVector3Array = parts[bone][1]
		var least := INF
		var mid := Vector3.ZERO
		for v in vs:
			var at := pose * v
			mid += at
			least = minf(least, at.y)
		mid /= vs.size()
		return Vector3(mid.x, least, mid.z)

	## A foot (its parts): the middle of its parts.
	func _foot(sk: Skeleton3D, bones: Array, place := Transform3D.IDENTITY) -> Vector3:
		# (Its middle's height, not its lowest point's: a carried paw hangs
		# its toes down near the ground.)
		var mid := Vector3.ZERO
		for bone: int in bones:
			var bind: Transform3D = parts[bone][0]
			var pose := place * sk.get_bone_global_pose(bone) * bind
			var vs: PackedVector3Array = parts[bone][1]
			var c := Vector3.ZERO
			for v in vs:
				c += pose * v
			mid += c / vs.size()
		return mid / bones.size()

	## The drawn model's planted feet this frame: how fast they slide over
	## the ground against how fast he goes (0 they hold, 1 they skate with
	## him); NAN when nothing is drawn or he stands.
	func drawn_slide(main: Node, g: Game, d: Hound.Dog, dt: float) -> float:
		var wv = main.get("world_view")
		if wv == null or wv.actors == null:
			return NAN
		var stand := ModeBodies.stand_in(g, "hound%d" % d.slot, "hound")
		var view: ActorView = wv.actors._shown.get(stand.get_instance_id())
		if view == null or not view.visible:
			_was.clear()
			return NAN
		var sk := view.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var place := sk.global_transform
		var now := {}
		var least := INF
		for key: String in foot_groups:
			var at := _foot(sk, foot_groups[key], place)
			now[key] = at
			least = minf(least, at.y)
		var slide := 0.0
		var n := 0
		for key: String in now:
			var at: Vector3 = now[key]
			if at.y > least + PLANT * HoundLooks.SIZE or not _was.has(key):
				continue
			var was: Vector3 = _was[key]
			slide += Vector2(at.x - was.x, at.z - was.z).length() / dt
			n += 1
		_was = now
		var v := d.pace
		if n == 0 or v < .5:
			return NAN
		return slide / n / v
