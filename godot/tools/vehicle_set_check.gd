## Finding the vehicles and what is built round them (feature pass 7:
## src/vehicle_finder.gd, features/vehicle_runs.gd, features/vehicles.gd's
## window and passenger; tools/check_all.gd runs it):
##
##   godot --headless --path godot --script res://tools/vehicle_set_check.gd
##
## FIND, on every map with a vehicle (the bayou's airboat, the speedway's
## car, Hickston's mower): its KEYS IN IT sign hangs by it; standing ready
## its lamps give light and go out once it is burnt out; its radio is heard
## near it and not far off, nor once it is driven; the automap marks it; USE
## names it from further off looked at (and not looked away from), gets in
## from the wider reach when nothing else is at hand, and its line is said
## the first time it is seen; at its wheel the objective names a set piece's
## start where it has one. RUNS: the bayou's CHANNEL RUN started through the
## dock wakes the king's boys and points the pin at the next gate, driven
## through its gates in time it pays its stash to the boat and shows on the
## tally, keeps DONE through a save; held still it runs out of time and
## takes another pass through the start to go again; the speedway's HEAT
## RACE starts only the way the lap cars run, gives the lap cars' time for
## three laps while they run, wakes the pit crew and is won in three laps.
## GUNS: out of the car's window a one-handed gun shoots ahead and to the
## sides, not back through the cage; a long gun stays down and getting in
## takes up a one-handed one; the shot strays more, it steers less with one
## hand on the wheel and the cab's right hand is off the wheel. CO-OP: a
## partner rides beside the driver, shoots and sees the cab from their seat.
extends SceneTree

const STEP := 1.0 / 60.0
const VehiclesScript := preload("res://src/features/vehicles.gd")
const RunsScript := preload("res://src/features/vehicle_runs.gd")
const SpeedwayPlan := preload("res://tools/levels/speedway_plan.gd")
const LEVELS := {"airboat": "bayou", "car": "speedway", "mower": "hickston"}
## The bayou's run, driven: from the dock to its start, then round its gates
## (waypoints on the water the airboat runs on).
const CHANNEL := [
	Vector2(95.0, 37.0),
	Vector2(91.0, 39.5),
	Vector2(84.0, 40.0),
	Vector2(80.0, 44.5),
	Vector2(71.5, 44.8),
	Vector2(80.5, 44.5),
	Vector2(81.5, 36.0),
	Vector2(81.5, 29.0),
	Vector2(69.0, 28.5),
	Vector2(84.5, 28.5),
	Vector2(90.0, 22.0),
	Vector2(97.5, 17.5),
	Vector2(97.5, 12.0),
	Vector2(95.5, 9.5),
]

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
	var started := Time.get_ticks_msec()
	for kind: String in LEVELS:
		print("\nFIND %s" % kind.to_upper())
		_find(main, kind, str(LEVELS[kind]))
	print("\nCHANNEL RUN")
	_channel(main)
	print("\nHEAT RACE")
	_heat(main)
	print("\nOUT OF THE WINDOW")
	_window(main)
	print("\nRIDING SHOTGUN")
	_shotgun(main)
	print("")
	print(
		(
			"%d checks in %.1f s"
			% [passes + failures.size(), (Time.get_ticks_msec() - started) / 1000.0]
		)
	)
	print(
		(
			"VEHICLE SET OK"
			if failures.is_empty()
			else "%d VEHICLE SET CHECK(S) FAILED" % failures.size()
		)
	)
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _game(main: Control, id: String, alone := true) -> Game:
	var g: Game = main.make_game(id)
	g.configure({"difficulty": 1})
	g.cheats.god = true
	g.barks.enabled = false
	if alone:
		g.enemies.clear()
		g.enemy_ids.clear()
	return g


static func rides(g: Game) -> VehiclesScript:
	return g.features.get("vehicles")


static func runs(g: Game) -> RunsScript:
	return g.features.get("vehicle_runs")


func _tick(g: Game, n: int, c := Game.Controls.new()) -> void:
	for t in n:
		g.tick(STEP, c)


## Stands the player `far` from ride 0's side (its right, `side` radians
## round from there), looking at it, or away when `away`.
static func _stand(g: Game, far: float, side := 0.0, away := false) -> bool:
	var v: VehicleDrive.Ride = rides(g).rides[0]
	var s := VehicleDrive.spec(v.kind)
	for turn: float in [side, side + PI, side + PI * .5, side - PI * .5]:
		var a := v.h + PI * .5 + turn
		var reach := s.width * .5 + far
		var at := Vector2(v.x, v.y) + Vector2(cos(a), sin(a)) * reach
		if g.world.blocked(at.x, at.y, .3) or g.world.deep_at(at.x, at.y):
			continue
		var floor_z := g.world.floor_under(at.x, at.y, v.z + 1.5)
		if far > 2.0 and not g.world.visible(at.x, at.y, v.x, v.y, floor_z + .95, v.z + .6):
			continue
		var p := g.player
		p.x = at.x
		p.y = at.y
		p.floor_z = g.world.floor_under(at.x, at.y, v.z + 1.5)
		p.eye = p.floor_z + .95
		p.air = 0.0
		p.pitch = 0.0
		p.angle = atan2(v.y - at.y, v.x - at.x) + (PI if away else 0.0)
		return true
	return false


func _find(main: Control, kind: String, id: String) -> void:
	var g := _game(main, id)
	var cars := rides(g)
	_check(not cars.rides.is_empty(), "%s has a vehicle to find" % id)
	if cars.rides.is_empty():
		return
	var v: VehicleDrive.Ride = cars.rides[0]
	var s := VehicleDrive.spec(v.kind)
	var sign_gap := INF
	for board: LevelData.Billboard in g.world.billboards:
		if board.image == "vehicle_sign_" + kind:
			sign_gap = minf(sign_gap, Vector2(board.x - v.x, board.y - v.y).length())
	_check(sign_gap < 4.5, "KEYS IN IT hangs by it (%.1f cells off)" % sign_gap)
	_check(g.art.has_art("vehicle_sign_" + kind), "the sign's picture is packed")
	_stand(g, 3.0)
	var lit: Array = cars.lights(g.player)
	_check(
		lit.size() == s.lamps.size() and not lit.is_empty(), "its %d lamps are left on" % lit.size()
	)
	var tune := cars.radio(g.player)
	_check(tune != Vector3.INF, "its radio plays near it")
	var far_p := Player.new()
	far_p.x = v.x + VehicleDrive.shared("radio_reach") + 3.0
	far_p.y = v.y
	_check(cars.radio(far_p) == Vector3.INF, "and is not heard far off")
	# The automap: its little picture where it stands.
	var c := Canvas.new()
	g.map_view.draw(g, c)
	var at := g.map_view.point(v.x, v.y)
	var inked := 0
	for dy in range(-3, 4):
		for dx in range(-5, 6):
			var o := ((int(at.y) + dy) * Canvas.WIDTH + int(at.x) + dx) * 3
			if o >= 0 and o + 2 < c.pixels.size():
				var px := Color8(c.pixels[o], c.pixels[o + 1], c.pixels[o + 2])
				if px.is_equal_approx(VehicleFinder.MAP_INK):
					inked += 1
	_check(inked >= 8, "the automap marks it (%d yellow pixels)" % inked)
	# USE from further off: named when looked at, not when looked away from.
	_stand(g, VehicleDrive.shared("spot_reach") - 1.5)
	var said := g.use_prompt()
	_check(
		said == s.name + "  /  KEYS IN IT",
		"looked at from %.0f cells: '%s'" % [VehicleDrive.shared("spot_reach") - 1.5, said]
	)
	_stand(g, VehicleDrive.shared("spot_reach") - 1.5, 0.0, true)
	_check(g.use_prompt() == "", "looked away from: no prompt")
	# The wider reach: past USE's own, nothing else at hand.
	_stand(g, VehicleDrive.shared("reach_wide") - .2)
	said = g.use_prompt()
	_check(
		said == "E  DRIVE THE " + s.name,
		"from %.1f off: '%s'" % [VehicleDrive.shared("reach_wide") - .2, said]
	)
	# Its line, said once, the first time it is seen.
	var g2 := _game(main, id)
	_stand(g2, 6.0)
	var said_times := 0
	var last := ""
	for t in 60 * 12:
		g2.tick(STEP, Game.Controls.new())
		if g2.notice == s.spotted and last != s.spotted:
			said_times += 1
		last = g2.notice
		if said_times > 0 and t % 120 == 0:
			# Its line done, the board clear again: it is not said twice.
			g2.notice = ""
			g2.message_until = 0.0
	_check(said_times >= 1, "its line is said once the board is clear: '%s'" % s.spotted)
	_check(said_times == 1, "and only the once (%d)" % said_times)
	g.interact()
	_check(cars.seated(g.player), "USE from the wider reach gets in")
	_check(cars.radio(g.player) == Vector3.INF, "driven, the radio is off (the engine's on)")
	if runs(g) != null and not runs(g).defs.is_empty():
		var line := g.objective()
		var start: Array = runs(g).defs[0]["start"]
		var target: Variant = g.objective_target()
		_check(
			(
				line.contains("START AT")
				and target is Vector2
				and (target as Vector2).distance_to(Vector2(float(start[0]), float(start[1]))) < .01
			),
			"at the wheel the objective names its set piece's start: '%s'" % line
		)
	cars.call("_hurt", v, 99999.0)
	_tick(g, 2)
	_check(cars.lights(g.player).is_empty(), "burnt out, its lamps go dark")
	var c2 := Canvas.new()
	g.map_view.draw(g, c2)
	_check(not VehicleFinder.ready(v), "and it is not marked as ready")


## Drives the player's ride along `points` (looking where it goes, slowing
## for the sharp turns, backing off a wall it is wedged on) until `done`
## says so or `most` ticks pass.
func _pilot(g: Game, points: Array, most: int, done: Callable, loop := false) -> int:
	var k := 0
	var v: VehicleDrive.Ride = rides(g).rides[0]
	var stuck := 0
	var backing := 0
	for t in most:
		if done.call():
			return t
		var aim: Vector2 = points[k]
		if Vector2(v.x, v.y).distance_to(aim) < maxf(2.0, VehicleDrive.speed(v) * .25):
			k += 1
			if k >= points.size():
				if not loop:
					return t
				k = 0
			aim = points[k]
		if OS.get_environment("PILOT_TRACE") != "" and t % 60 == 0:
			print(
				(
					"    t=%d at (%.1f, %.1f) h %.2f v %.1f hp %.0f -> wp %d %s"
					% [t, v.x, v.y, v.h, VehicleDrive.speed(v), v.hp, k, str(aim)]
				)
			)
		var p := g.player
		p.angle = atan2(aim.y - v.y, aim.x - v.x)
		var off := absf(wrapf(p.angle - v.h, -PI, PI))
		var c := Game.Controls.new()
		c.forward = 1.0 if off < .6 else .45
		var next_k := k + 1 if k + 1 < points.size() else (0 if loop else k)
		var after: Vector2 = points[next_k]
		var bend := absf(wrapf((after - aim).angle() - (aim - Vector2(v.x, v.y)).angle(), -PI, PI))
		var gap := Vector2(v.x, v.y).distance_to(aim)
		var fast := VehicleDrive.speed(v)
		var safe := clampf(13.0 - bend * 9.0, 3.5, 13.0)
		if gap < fast * .9 and fast > safe:
			# A bend ahead: on the brake into it, as a driver would.
			c.forward = -.6
		# Wedged against a bank or a wall, as a player would: back off a way.
		stuck = stuck + 1 if VehicleDrive.speed(v) < .4 else 0
		if stuck > 30:
			backing = 45
			stuck = 0
		if backing > 0:
			backing -= 1
			p.angle = v.h
			c.forward = -1.0
		g.tick(STEP, c)
	return most


func _channel(main: Control) -> void:
	var g := _game(main, "bayou", false)
	var r := runs(g)
	_check(r.defs.size() == 1, "the bayou has its run")
	var boys: Array = []
	for i in g.enemies.size():
		if str(g.enemy_ids[i]).begins_with("run-"):
			boys.append(g.enemies[i])
	_check(boys.size() >= 6, "the king's boys are there (%d)" % boys.size())
	var held := boys.all(func(e: Enemy) -> bool: return e.dormant)
	_check(held, "and held back until it starts")
	_check(rides(g).seat_in(g.player, 0), "in the airboat")
	var running := func() -> bool: return r.state_of("channel_run") == RunsScript.RUNNING
	_pilot(g, CHANNEL.slice(0, 2), 1200, running)
	_check(running.call(), "out through the dock, the run starts")
	_tick(g, 2)
	var woke := boys.all(func(e: Enemy) -> bool: return not e.dormant)
	_check(woke, "and the king's boys come")
	var target: Variant = g.objective_target()
	var gate0: Array = r.defs[0]["gates"][0]
	_check(
		(
			target is Vector2
			and (target as Vector2).distance_to(Vector2(float(gate0[0]), float(gate0[1]))) < .01
		),
		"the pin points at the first gate (%s)" % str(target)
	)
	_check(
		g.objective().begins_with("CHANNEL RUN /"), "the objective says it: '%s'" % g.objective()
	)
	var c := Canvas.new()
	# Laid out first (src/ui/hud/hud_layout.gd), as a frame does.
	g.hud.layout.reset()
	r.hud_flow(g.hud.layout)
	var at: Rect2i = g.hud.layout.find("run")
	r.draw_view(c)
	var o := ((at.position.y + 1) * Canvas.WIDTH + at.position.x + 20) * 3
	_check(
		Color8(c.pixels[o], c.pixels[o + 1], c.pixels[o + 2]).is_equal_approx(VehicleHud.FACE),
		"its plate is up across from the driving plate"
	)
	_check(not r.lights(g.player).is_empty(), "a flare burns on the next gate")
	var shine: int = g.inventory["moonshine"]
	var sticks: int = g.armory.reserve[Weapons.CROSSBOW]
	var done := func() -> bool: return r.state_of("channel_run") == RunsScript.DONE
	var limit: float = r.limit[0]
	var took := _pilot(g, CHANNEL.slice(2), 60 * 120, done)
	_check(
		done.call(),
		"driven round its gates, the run is made (%.1f s of %.0f)" % [took * STEP, limit]
	)
	_check(r.best[0] > 0.0 and r.best[0] <= limit, "in time (%.1f s)" % r.best[0])
	_check(
		int(g.inventory["moonshine"]) > shine or g.armory.reserve[Weapons.CROSSBOW] > sticks,
		"the king's stash is in the boat"
	)
	var rows := Features.tally_rows(g)
	var shown := false
	for row: Array in rows:
		shown = shown or str(row[0]) == "CHANNEL RUN"
	_check(shown, "the tally shows its time")
	var saved := r.save()
	var fresh := _game(main, "bayou", false)
	runs(fresh).restore(saved)
	_check(runs(fresh).state_of("channel_run") == RunsScript.DONE, "a save keeps it made")
	# Held still once started: out of time, and it takes another pass.
	var slow := _game(main, "bayou")
	var sr := runs(slow)
	rides(slow).seat_in(slow.player, 0)
	_pilot(
		slow,
		CHANNEL.slice(0, 2),
		1200,
		func() -> bool: return sr.state_of("channel_run") == RunsScript.RUNNING
	)
	_tick(slow, int((float(sr.limit[0]) + 1.0) / STEP))
	_check(sr.state_of("channel_run") == RunsScript.READY, "held still it runs out of time")
	_check(sr.armed[0] == 0, "and needs the boat out of the start before it goes again")


func _heat(main: Control) -> void:
	var g := _game(main, "speedway", false)
	var r := runs(g)
	_check(r.defs.size() == 1, "the speedway has its race")
	var line := PackedVector2Array()
	for point: Variant in g.level.lap_cars.get("path", []):
		line.append(Vector2(float(point[0]), float(point[1])))
	var crew: Array = []
	for i in g.enemies.size():
		if str(g.enemy_ids[i]).begins_with("heat-"):
			crew.append(g.enemies[i])
	_check(
		crew.size() == 4 and crew.all(func(e: Enemy) -> bool: return e.dormant),
		"the pit crew waits"
	)
	rides(g).seat_in(g.player, 0)
	var v: VehicleDrive.Ride = rides(g).rides[0]
	# Off pit row through the gap onto the back stretch, then round the east
	# turn: down the front stretch through the start the wrong way, no race.
	var onto := [Vector2(66.0, 18.0), Vector2(74.5, 19.0), Vector2(74.5, 25.0)]
	var wrong := (
		onto
		+ [
			line[6],
			line[5],
			line[4],
			line[3],
			line[2],
			line[1],
			Vector2(74.0, 65.1),
			Vector2(60.0, 65.1)
		]
	)
	_pilot(g, wrong, 60 * 40, func() -> bool: return false)
	_check(r.state_of("heat_race") == RunsScript.READY, "through the start the wrong way: no race")
	# Round the west turn instead: through it the way the lap cars run.
	g = _game(main, "speedway", false)
	r = runs(g)
	rides(g).seat_in(g.player, 0)
	v = rides(g).rides[0]
	var going := func() -> bool: return r.state_of("heat_race") == RunsScript.RUNNING
	var right := (
		onto + [line[7], line[8], line[9], line[10], line[11], line[0], Vector2(80.0, 65.1)]
	)
	_pilot(g, right, 60 * 40, going)
	_check(going.call(), "the right way, the heat race starts (%.1f, %.1f)" % [v.x, v.y])
	crew.clear()
	for i in g.enemies.size():
		if str(g.enemy_ids[i]).begins_with("heat-"):
			crew.append(g.enemies[i])
	var laps: GameFeature = g.features.get("race_laps")
	var total: float = laps.get("total")
	var pace: float = 3.0 * total / float(g.level.lap_cars.get("speed", 8.4))
	_check(
		absf(float(r.limit[0]) - pace) < .2,
		"it gives the lap cars' time for three laps (%.1f s)" % r.limit[0]
	)
	_tick(g, 2)
	_check(crew.all(func(e: Enemy) -> bool: return not e.dormant), "the pit crew comes out")
	# Three laps in the inside lane, wide of the lap cars on the racing line
	# (they run down whoever is on it), from the point past the line.
	var lane: Array = SpeedwayPlan.new().racing_line(18.2)
	var from := 0
	for i in lane.size():
		if float(lane[i][0]) > 80.0 and float(lane[i][1]) > 60.0:
			from = i
			break
	var round_line: Array = []
	for k in lane.size():
		var point: Array = lane[(from + k) % lane.size()]
		round_line.append(Vector2(float(point[0]), float(point[1])))
	var won := func() -> bool: return r.state_of("heat_race") == RunsScript.DONE
	var took := _pilot(g, round_line, 60 * 150, won, true)
	_check(won.call(), "three laps and it is won (%.1f s; %s)" % [took * STEP, g.notice])
	var dry := _game(main, "speedway")
	var dry_laps: GameFeature = dry.features.get("race_laps")
	dry_laps.set("dry", true)
	_check(
		is_equal_approx(runs(dry).call("_limit", runs(dry).defs[0]), 80.0),
		"once the lap cars run dry, it is 80 seconds"
	)


func _window(main: Control) -> void:
	var g := _game(main, "speedway")
	var cars := rides(g)
	var p := g.player
	var revolver: int = Weapons.NAMES.find("revolver")
	var rifle: int = Weapons.NAMES.find("rifle")
	p.armory.owned[rifle] = true
	p.armory.select(rifle, g)
	_tick(g, 30)
	cars.seat_in(p, 0)
	_check(p.armory.active == revolver, "in at the wheel with a long gun, the .38 is taken up")
	_tick(g, 20)
	_check(not p.armory.holstered and not cars.hands_busy(p), "it is out of the window")
	var v: VehicleDrive.Ride = cars.rides[0]
	var before: int = p.armory.loaded[revolver]
	var c := Game.Controls.new()
	c.fire = true
	p.angle = v.h + .9
	_tick(g, 2, c)
	_check(p.armory.loaded[revolver] < before, "it shoots out of the side window")
	_tick(g, 40)
	p.angle = v.h + PI
	_tick(g, 2)
	before = p.armory.loaded[revolver]
	_tick(g, 30, c)
	_check(cars.hands_busy(p) and p.armory.loaded[revolver] == before, "not back through the cage")
	p.angle = v.h
	_tick(g, 10)
	_check(
		is_equal_approx(cars.aim_scale(p), VehicleDrive.shared("window_spread")),
		"its shot strays more (x%.2f)" % cars.aim_scale(p)
	)
	g.view.layered = true
	var eye := p.as_render_player()
	cars.sway_eye(eye)
	var fade: Dictionary = eye.get("cab", {}).get("fade", {})
	_check(
		float(fade.get("hand_r", 1.0)) == 0.0 and float(fade.get("hand_l", 0.0)) == 1.0,
		"the cab's right hand is off the wheel, the left on it"
	)
	p.armory.select(rifle, g)
	_tick(g, 20)
	before = p.armory.loaded[rifle]
	_tick(g, 30, c)
	_check(p.armory.holstered and p.armory.loaded[rifle] == before, "a long gun stays down")
	eye = p.as_render_player()
	cars.sway_eye(eye)
	fade = eye.get("cab", {}).get("fade", {})
	_check(float(fade.get("hand_r", 0.0)) == 1.0, "and both hands are on the wheel")
	# One hand on the wheel steers less than two.
	var turns: Array = []
	for gun: int in [revolver, rifle]:
		var t := _game(main, "speedway")
		# Out on the truck stop's open asphalt, clear of any wall.
		var ride: VehicleDrive.Ride = rides(t).rides[0]
		ride.x = 22.0
		ride.y = 86.0
		ride.h = 0.0
		ride.z = t.world.floor_under(ride.x, ride.y, 9.0)
		rides(t).seat_in(t.player, 0)
		t.player.armory.owned[rifle] = true
		t.player.armory.select(gun, t)
		var go := Game.Controls.new()
		go.forward = 1.0
		_tick(t, 40, go)
		var h := ride.h
		var steer := Game.Controls.new()
		steer.forward = 1.0
		steer.strafe = 1.0
		_tick(t, 12, steer)
		turns.append(absf(wrapf(ride.h - h, -PI, PI)))
	_check(
		turns[0] < turns[1] * .9,
		"one hand on the wheel steers less (%.3f to %.3f)" % [turns[0], turns[1]]
	)
	var b := _game(main, "bayou")
	rides(b).seat_in(b.player, 0)
	_check(
		is_equal_approx(rides(b).aim_scale(b.player), 1.0), "the airboat's driver aims as before"
	)
	var foot := _game(main, "speedway")
	_check(is_equal_approx(rides(foot).aim_scale(foot.player), 1.0), "and on foot as before")


func _shotgun(main: Control) -> void:
	var g := _game(main, "speedway")
	var cars := rides(g)
	cars.seat_in(g.player, 0)
	GameHost.join_near(g)
	var two: Player = g.players[1]
	var keep := g.player
	g.focus(two)
	g.player = two
	_stand(g, .6)
	var said := g.use_prompt()
	g.interact()
	g.player = keep
	g.focus(g.local_player)
	_check(
		cars.seat_of(two) == Vector2i(0, 1), "a partner climbs in beside the driver ('%s')" % said
	)
	var v: VehicleDrive.Ride = cars.rides[0]
	var go := Game.Controls.new()
	go.forward = 1.0
	for t in 60:
		g.tick(STEP, {0: go, 1: Game.Controls.new()})
	var side := Vector2(two.x - v.x, two.y - v.y).dot(Vector2(-sin(v.h), cos(v.h)))
	_check(
		absf(side - VehicleDrive.spec("car").ride_side) < .05,
		"riding shotgun on the right (%.2f)" % side
	)
	_check(
		VehiclesScript.window_clear(two, v) and not cars.hands_busy(two),
		"and can shoot out of the window"
	)
	_check(
		is_equal_approx(cars.aim_scale(two), VehicleDrive.shared("rider_spread")),
		"a little wilder riding (x%.2f)" % cars.aim_scale(two)
	)
	var gun: int = two.armory.active
	var before: int = two.armory.loaded[gun]
	var shoot := Game.Controls.new()
	shoot.fire = true
	two.angle = v.h + .8
	for t in 3:
		g.tick(STEP, {0: go, 1: shoot})
	_check(
		two.armory.loaded[gun] < before or Weapons.CAPACITY[gun] == 0, "the partner's gun goes off"
	)
	# The partner's own view: the cab from their seat, the car's shell left out.
	g.view.layered = true
	g.local_player = two
	g.player = two
	var eye := two.as_render_player()
	cars.sway_eye(eye)
	var cab: Dictionary = eye.get("cab", {})
	_check(str(cab.get("model", "")) == "cab_car", "the partner sees the cab from their seat")
	var lift: Vector3 = cab.get("lift", Vector3.ZERO)
	var right := lift.dot(Vector3(-sin(v.h), cos(v.h), 0.0))
	_check(right < -.3, "with the wheel off to their left (%.2f)" % right)
	var shell := false
	for spr: Variant in g.sprites():
		if spr is View.Sprite and (spr as View.Sprite).track == "ride0":
			shell = true
	_check(not shell, "and not the car's shell round their eye")
	g.local_player = keep
	g.player = keep
