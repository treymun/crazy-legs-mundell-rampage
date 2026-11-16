## Checks of how the vehicles look on the move (src/vehicle_feel.gd, looks
## only), run by tools/vehicle_check.gd: the car squats on the throttle and
## dives braking hard (leaving tyre marks), leans out of a turn (its outside
## lower), leaves skid marks on a hard handbrake turn, throws sparks off a
## wall it scrapes, and comes back to rest on its springs after a drop off a
## ledge; the airboat rocks parked, throws spray and leaves a wake on the
## water; the mower bounces and spits clippings; the engine's pitch rises
## with the speed; and the 3D view is handed the car tipped on its springs.
## Driving stays the same: a game whose looks dice were rolled otherwise
## drives tick for tick the same.
extends RefCounted

const STEP := 1.0 / 60.0
const VehiclesScript := preload("res://src/features/vehicles.gd")


static func _seat(main, id: String) -> Game:
	var g: Game = main.make_game(id)
	g.configure({"difficulty": 1})
	g.cheats.god = true
	g.enemies.clear()
	g.enemy_ids.clear()
	var rides: VehiclesScript = g.features.get("vehicles")
	var v: VehicleDrive.Ride = rides.rides[0]
	# Straight into the seat (vehicle_check covers walking up to it).
	var p := g.player
	var r := Vector2(-sin(v.h), cos(v.h))
	var s := VehicleDrive.spec(v.kind)
	for side: float in [1.0, -1.0]:
		var at := Vector2(v.x, v.y) + r * side * (s.width * .5 + .5)
		if not g.world.blocked(at.x, at.y, .25) and not g.world.deep_at(at.x, at.y):
			p.x = at.x
			p.y = at.y
			p.floor_z = g.world.floor_under(at.x, at.y, v.z + 1.0)
			p.angle = atan2(v.y - at.y, v.x - at.x)
			break
	g.interact()
	return g


static func _drive(g: Game, ticks: int, forward: float, strafe := 0.0, jump := false) -> void:
	for t in ticks:
		var c := Game.Controls.new()
		c.forward = forward
		c.strafe = strafe
		c.jump = jump
		g.tick(STEP, c)


## Turns ride 0 to face its longest open run of floor (its kind runs on).
static func _open_way(g: Game, v: VehicleDrive.Ride) -> float:
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
	g.player.angle = best_h
	return best * .3


static func run(main, check: Callable) -> void:
	_car(main, check)
	_landing(main, check)
	_airboat(main, check)
	_mower(main, check)
	_same_drive(main, check)
	check.call(
		VehiclesScript.engine_rate(0.0) < 1.0 and VehiclesScript.engine_rate(1.0) > 1.2,
		(
			"the engine's pitch rises with the speed (%.2f standing, %.2f flat out)"
			% [VehiclesScript.engine_rate(0.0), VehiclesScript.engine_rate(1.0)]
		)
	)


static func _car(main, check: Callable) -> void:
	var g := _seat(main, "speedway")
	var rides: VehiclesScript = g.features.get("vehicles")
	var v: VehicleDrive.Ride = rides.rides[0]
	_open_way(g, v)
	var b := rides.body(0)
	var squat := 0.0
	for t in 50:
		_drive(g, 1, 1.0)
		squat = maxf(squat, b.pitch)
	check.call(squat > .01, "car: it squats back on the throttle (nose up %.3f rad)" % squat)
	var marks := rides.looks_count("marks")
	var dive := 0.0
	for t in 40:
		_drive(g, 1, -1.0)
		dive = minf(dive, b.pitch)
	check.call(dive < -.01, "car: it dives braking hard (nose down %.3f rad)" % dive)
	check.call(
		rides.looks_count("marks") > marks,
		"car: braking hard leaves tyre marks (%d)" % (rides.looks_count("marks") - marks)
	)
	# A turn at speed: the outside of the turn lower than the inside.
	g = _seat(main, "speedway")
	rides = g.features.get("vehicles")
	v = rides.rides[0]
	_open_way(g, v)
	b = rides.body(0)
	_drive(g, 30, 1.0)
	var right_way := 0
	var wrong_way := 0
	var lean := 0.0
	var h0 := v.h
	var bumps := v.bumps
	for t in 40:
		var h := v.h
		_drive(g, 1, .6, 1.0)
		var yaw := wrapf(v.h - h, -PI, PI)
		# The first few ticks of the turn the body is still coming over; a
		# wall met ends the turn.
		if v.bumps != bumps or VehicleDrive.speed(v) < 3.0:
			break
		if absf(yaw) < .002 or t < 8:
			continue
		# The turn's middle is on the side the heading swings to.
		var inside := VehicleFeel.height_at(b, v.h, 0.0, .5 * signf(yaw), .5)
		var outside := VehicleFeel.height_at(b, v.h, 0.0, -.5 * signf(yaw), .5)
		lean = maxf(lean, inside - outside)
		if outside < inside - .002:
			right_way += 1
		elif outside > inside + .002:
			wrong_way += 1
	(
		check
		. call(
			right_way >= 6 and wrong_way == 0,
			(
				"car: it leans out of a turn, its outside down (%d ticks so, %d not; %.3f across, %.2f rad)"
				% [right_way, wrong_way, lean, absf(wrapf(v.h - h0, -PI, PI))]
			)
		)
	)
	# A hard handbrake turn slides it: skid marks.
	g = _seat(main, "speedway")
	rides = g.features.get("vehicles")
	v = rides.rides[0]
	_open_way(g, v)
	_drive(g, 50, 1.0)
	var before := rides.looks_count("marks")
	_drive(g, 30, 1.0, 1.0, true)
	check.call(
		rides.looks_count("marks") > before + 4,
		(
			"car: a hard handbrake turn leaves skid marks (%d, slid %.1f)"
			% [rides.looks_count("marks") - before, v.slide]
		)
	)
	# Into a wall: sparks.
	g = _seat(main, "speedway")
	rides = g.features.get("vehicles")
	v = rides.rides[0]
	bumps = v.bumps
	var sparks := 0
	for t in 900:
		_drive(g, 1, 1.0)
		sparks = maxi(sparks, rides.looks_count("sparks"))
		if v.bumps > bumps + 3:
			break
	check.call(
		v.bumps > bumps and sparks > 0,
		"car: it throws sparks where it strikes a wall (%d, %d bumps)" % [sparks, v.bumps - bumps]
	)


## Dropped off a ledge it lands on its springs, bounces and settles.
static func _landing(main, check: Callable) -> void:
	var g := _seat(main, "speedway")
	var rides: VehiclesScript = g.features.get("vehicles")
	var v: VehicleDrive.Ride = rides.rides[0]
	var b := rides.body(0)
	_drive(g, 30, 0.0)
	# Lifted up off its floor, it falls back down to it.
	v.z += .7
	b.last_z = v.z
	var low := 0.0
	var high := 0.0
	for t in 90:
		_drive(g, 1, 0.0)
		if b.heave < low:
			low = b.heave
			high = 0.0
		high = maxf(high, b.heave)
	check.call(
		low < -.03 and high > 0.0,
		(
			"car: off a ledge it lands on its springs (down %.3f) and bounces back (up %.3f)"
			% [low, high]
		)
	)
	_drive(g, 150, 0.0)
	var rest := absf(b.heave) + absf(b.pitch) + absf(b.roll)
	check.call(rest < .005, "car: then its suspension settles (%.4f left after 3 s)" % rest)


static func _airboat(main, check: Callable) -> void:
	var g := _seat(main, "bayou")
	var rides: VehiclesScript = g.features.get("vehicles")
	var v: VehicleDrive.Ride = rides.rides[0]
	var b := rides.body(0)
	var rock := 0.0
	for t in 120:
		_drive(g, 1, 0.0)
		rock = maxf(rock, absf(b.roll))
	check.call(
		rock > .005 and rock < .08, "airboat: parked, it rocks on the water (%.3f rad)" % rock
	)
	_open_way(g, v)
	var water: GameFeature = g.features.get("water")
	var rings_before: int = water.get("rings").size() if water != null else 0
	var spray := 0
	for t in 120:
		_drive(g, 1, 1.0, .4 if t > 60 else 0.0)
		spray = maxi(spray, rides.looks_count("spray"))
	var rings: int = water.get("rings").size() if water != null else 0
	check.call(spray > 4, "airboat: on the water it throws spray off its bow (%d)" % spray)
	check.call(rings > rings_before, "airboat: and leaves a wake behind it (%d rings)" % rings)
	# The 3D view gets it as a model on the move, tipped by its springs.
	var shown: View.Sprite = null
	for s: View.Sprite in rides.sprites():
		if s.track == "ride0":
			shown = s
	check.call(
		(
			shown != null
			and shown.turn.is_equal_approx(VehicleFeel.turn(b, v.h))
			and absf(shown.z - v.z - b.heave) < .0001
			and (absf(b.pitch) > .001 or absf(b.roll) > .001)
		),
		"airboat: the 3D view is handed it tipped on its springs (its track, turn and bob)"
	)


static func _mower(main, check: Callable) -> void:
	var g := _seat(main, "hickston")
	var rides: VehiclesScript = g.features.get("vehicles")
	var v: VehicleDrive.Ride = rides.rides[0]
	var b := rides.body(0)
	_open_way(g, v)
	var bounce := 0.0
	var clips := 0
	for t in 120:
		_drive(g, 1, 1.0)
		bounce = maxf(bounce, absf(b.heave) + absf(b.roll))
		clips = maxi(clips, rides.looks_count("clips"))
	var tile := VehicleDrive.tile_at(g.world, v.x, v.y)
	check.call(bounce > .004, "mower: it bounces along (%.3f)" % bounce)
	check.call(
		clips > 0 or not ["grass", "lawn", "bayou_marsh"].has(tile),
		"mower: on the grass it spits clippings (%d, on %s)" % [clips, tile]
	)


## A game whose looks dice are rolled otherwise drives the same.
static func _same_drive(main, check: Callable) -> void:
	var a := _seat(main, "speedway")
	var c := _seat(main, "speedway")
	var other: VehiclesScript = c.features.get("vehicles")
	var dice: RandomNumberGenerator = other.get("_dice")
	dice.seed = 4242
	for t in 200:
		var k := Game.Controls.new()
		k.forward = 1.0 if t < 140 else -1.0
		k.strafe = sin(t * .07)
		k.jump = t % 40 < 8
		a.tick(STEP, k)
		c.tick(STEP, k)
	var sa := GameSnapshot.capture(a)
	var sc := GameSnapshot.capture(c)
	check.call(
		GameSnapshot.same(sa, sc), "the looks never change the driving (other dice, same drive)"
	)
