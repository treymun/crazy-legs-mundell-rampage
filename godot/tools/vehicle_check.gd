## The vehicles (features/vehicles.gd; tools/check_all.gd runs it, quick too):
##
##   godot --headless --path godot --script res://tools/vehicle_check.gd
##
## For each vehicle (the bayou's airboat, the speedway's car, Hickston's
## mower): the player walks up to it and USE puts them in the driver's seat
## (the prompt says DRIVE); full throttle drives it more than CARRY cells
## along its floor, never into a wall; held on, it strikes something and
## bounces back off it, never ending up inside anything; a hand set in its
## way is run down (dead, killed by "roadkill" or the mower's blade, its body
## thrown along the way it was going); USE puts the player back on foot
## beside it, not inside it or a wall. Then: the airboat only runs on water
## and marsh, the car will not climb a stair, the car's driver holds a
## one-handed gun out of the window while the airboat shoots; a wreck throws its driver
## out hurt; a game driven and one made from its snapshot drive on the same,
## tick for tick; and a save and load keeps where it was parked. Then how
## they look on the move (tools/vehicle_feel_check.gd).
extends SceneTree

const STEP := 1.0 / 60.0
## Cells it must cover under full throttle in DRIVE_TICKS.
const CARRY := 4.0
const DRIVE_TICKS := 150
const VehiclesScript := preload("res://src/features/vehicles.gd")
const FeelCheck := preload("res://tools/vehicle_feel_check.gd")

var failures: Array = []
var passes := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var started := Time.get_ticks_msec()
	for id: String in ["bayou", "speedway", "hickston"]:
		print("\n%s" % id.to_upper())
		_vehicle(main, id)
	print("\nRULES")
	_rules(main)
	print("\nCO-OP")
	_ride_along(main)
	print("\nIN STEP")
	_lockstep(main)
	print("\nFEEL")
	FeelCheck.run(main, _check)
	print("")
	print(
		(
			"%d checks in %.1f s"
			% [passes + failures.size(), (Time.get_ticks_msec() - started) / 1000.0]
		)
	)
	print("VEHICLES OK" if failures.is_empty() else "%d VEHICLE CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	if ok:
		passes += 1
		print("  ok   ", text)
	else:
		print("  FAIL ", text)
		failures.append(text)


func _game(main, id: String, alone := true) -> Game:
	var g: Game = main.make_game(id)
	g.configure({"difficulty": 1})
	g.cheats.god = true
	# Nobody else about: the hands the checks set down are the only ones.
	if alone:
		g.enemies.clear()
		g.enemy_ids.clear()
	return g


static func rides(g: Game) -> VehiclesScript:
	return g.features.get("vehicles")


static func ride(g: Game) -> VehicleDrive.Ride:
	return rides(g).rides[0]


## Stands the player beside vehicle 0 facing it, as a player walks up.
static func walk_up(g: Game) -> bool:
	var v := ride(g)
	var s := VehicleDrive.spec(v.kind)
	var r := Vector2(-sin(v.h), cos(v.h))
	var f := Vector2(cos(v.h), sin(v.h))
	for off: Vector2 in [
		r * (s.width * .5 + .5),
		-r * (s.width * .5 + .5),
		-f * (s.length * .5 + .5),
		r * (s.width * .5 + 1.0)
	]:
		var at := Vector2(v.x, v.y) + off
		if g.world.blocked(at.x, at.y, .25) or g.world.deep_at(at.x, at.y):
			continue
		var p := g.player
		p.x = at.x
		p.y = at.y
		p.floor_z = g.world.floor_under(at.x, at.y, v.z + 1.0)
		p.angle = atan2(v.y - at.y, v.x - at.x)
		return true
	return false


static func drive(g: Game, ticks: int, forward: float, strafe := 0.0, fire := false) -> void:
	for t in ticks:
		var c := Game.Controls.new()
		c.forward = forward
		c.strafe = strafe
		c.fire = fire
		g.tick(STEP, c)


static func inside_anything(g: Game) -> bool:
	var v := ride(g)
	var s := VehicleDrive.spec(v.kind)
	return is_nan(VehicleDrive.fits(g.world, s, v.x, v.y, v.h, v.z))


func _vehicle(main, id: String) -> void:
	var g := _game(main, id)
	var feature := rides(g)
	_check(feature != null and not feature.rides.is_empty(), "%s: has a vehicle" % id)
	if feature == null or feature.rides.is_empty():
		return
	var v := ride(g)
	_check(not inside_anything(g), "%s: the %s stands clear where it is parked" % [id, v.kind])
	_check(walk_up(g), "%s: there is room to walk up to it" % id)
	var prompt := g.use_prompt()
	_check(prompt.contains("DRIVE"), "%s: walking up shows '%s'" % [id, prompt])
	g.interact()
	_check(feature.seated(g.player), "%s: USE puts the player in the driver's seat" % id)
	var start := Vector2(v.x, v.y)
	var clear := true
	for t in DRIVE_TICKS:
		drive(g, 1, 1.0)
		if inside_anything(g):
			clear = false
	var went := Vector2(v.x, v.y).distance_to(start)
	_check(went > CARRY, "%s: full throttle drives it %.1f cells" % [id, went])
	_check(clear, "%s: it never drives into anything" % id)
	_check(
		Vector2(g.player.x, g.player.y).distance_to(Vector2(v.x, v.y)) < 1.5,
		"%s: the driver rides with it" % id
	)
	# Held on, it meets something and bounces off it.
	var bumps := v.bumps
	var stayed_clear := true
	for t in 900:
		drive(g, 1, 1.0)
		if inside_anything(g):
			stayed_clear = false
		if v.bumps > bumps:
			break
	_check(v.bumps > bumps, "%s: driven on, it strikes something (at %.1f, %.1f)" % [id, v.x, v.y])
	_check(stayed_clear, "%s: it bounces off, never inside a wall" % id)
	# Back off it, turn round and set a hand in its way.
	drive(g, 60, -1.0)
	drive(g, 20, 0.0)
	var victim := _victim(g)
	_check(victim != null, "%s: there is room for a hand ahead of it" % id)
	if victim != null:
		# The victim can close on the driver before the collision. Measure
		# the body's travel from the impact itself.
		var impact: Array[Vector2] = []
		var record := func(enemy: Enemy) -> void:
			if enemy == victim:
				impact.append(Vector2(enemy.x, enemy.y))
		g.events.enemy_killed.connect(record)
		for t in 300:
			drive(g, 1, 1.0)
			if not victim.alive:
				break
		g.events.enemy_killed.disconnect(record)
		_check(
			not victim.alive and victim.killed_by in ["roadkill", "mower"],
			(
				"%s: the hand in its way is run down (%s at %.1f cells a second)"
				% [id, victim.killed_by, VehicleDrive.speed(ride(g))]
			)
		)
		drive(g, 40, 0.0)
		var thrown := (
			Vector2(victim.x, victim.y).distance_to(impact[0]) if not impact.is_empty() else 0.0
		)
		_check(thrown > .5, "%s: its body is thrown %.1f cells from impact" % [id, thrown])
	drive(g, 90, -.0)
	g.interact()
	var p := g.player
	_check(not feature.seated(p), "%s: USE puts the player back on foot" % id)
	var s := VehicleDrive.spec(v.kind)
	_check(
		(
			VehicleDrive.out_of(s, v, p.x, p.y, 0.0) == Vector2.INF
			and not g.world.blocked(p.x, p.y, Game.PLAYER_RADIUS)
		),
		"%s: beside it, not inside it or a wall" % id
	)
	# A save keeps where it was left.
	var saved: Dictionary = feature.save()
	var g2 := _game(main, id)
	rides(g2).restore(saved)
	var w := ride(g2)
	_check(
		absf(w.x - v.x) < .01 and absf(w.y - v.y) < .01 and absf(w.hp - v.hp) < .2,
		"%s: a save keeps where it was left and how hurt" % id
	)


## A hand set down a few cells ahead of vehicle 0 on open floor it runs on.
static func _victim(g: Game) -> Enemy:
	var v := ride(g)
	var s := VehicleDrive.spec(v.kind)
	# Turn it to face the most open way first (the checks drive straight).
	var best_h := v.h
	var best := 0
	for k in 16:
		var h := v.h + k * TAU / 16.0
		var run := 0
		for step in 24:
			var d := step * .3
			if is_nan(VehicleDrive.fits(g.world, s, v.x + cos(h) * d, v.y + sin(h) * d, h, v.z)):
				break
			run = step
		if run > best:
			best = run
			best_h = h
	if best < 23:
		return null
	v.h = best_h
	g.player.angle = best_h
	v.vx = 0.0
	v.vy = 0.0
	var at := s.length * .5 + 4.5
	var e := Enemy.new("billy", v.x + cos(best_h) * at, v.y + sin(best_h) * at, best_h + PI)
	e.uid = g.take_uid()
	while e.uid % roundi(VehicleDrive.shared("dodge_skip")) != 0:
		e.uid = g.take_uid()
	g.enemies.append(e)
	g.enemy_ids.append("check-victim")
	return e


func _rules(main) -> void:
	# The airboat keeps to the water: driven at the dock walk it stops there.
	var g := _game(main, "bayou")
	var v := ride(g)
	var s := VehicleDrive.spec(v.kind)
	_check(
		is_nan(VehicleDrive.fits(g.world, s, 100.5, 33.5, v.h, v.z)),
		"bayou: the airboat will not go up on the planks"
	)
	_check(
		not is_nan(VehicleDrive.fits(g.world, s, 92.0, 20.0, v.h, v.z)),
		"bayou: it runs on the lagoon's deep water"
	)
	# The car will not climb a stair (a tread taller than its step).
	var car := VehicleDrive.spec("car")
	_check(car.step < LevelGeometry.STEP, "the car's step (%.2f) is under a stair's" % car.step)
	# The car's driver has a one-handed gun out of the window (the .38 to
	# start with; a long gun stays down: tools/vehicle_set_check.gd); the
	# airboat shoots.
	g = _game(main, "speedway")
	walk_up(g)
	g.interact()
	var holstered := g.player.armory.holstered
	_check(
		not holstered and not rides(g).hands_busy(g.player),
		"speedway: the car's driver holds the .38 out of the window"
	)
	var b := _game(main, "bayou")
	walk_up(b)
	b.interact()
	_check(not rides(b).hands_busy(b.player), "bayou: the airboat's driver can shoot")
	# A wreck throws its driver out, hurt.
	b.cheats.god = false
	var health := b.player.health
	var boat := ride(b)
	rides(b).call("_hurt", boat, 99999.0)
	_check(boat.wreck >= 0.0, "bayou: run down to nothing, the airboat is wrecked")
	_check(not rides(b).seated(b.player), "bayou: the wreck throws its driver out")
	_check(b.player.health < health, "bayou: and hurts them (%d)" % (health - b.player.health))
	_check(b.use_prompt() == "BURNT OUT" or b.use_prompt() == "", "bayou: a wreck can't be driven")


## Co-op: a second player rides along in the airboat's second seat and goes
## where it goes.
func _ride_along(main) -> void:
	var g := _game(main, "bayou")
	walk_up(g)
	g.interact()
	GameHost.join_near(g)
	var two: Player = g.players[1]
	var v := ride(g)
	var keep := g.player
	g.player = two
	g.focus(two)
	walk_up(g)
	var said := g.use_prompt()
	g.interact()
	g.player = keep
	g.focus(g.local_player)
	_check(
		rides(g).seat_of(two) == Vector2i(0, 1),
		"co-op: a second player climbs in to ride along ('%s')" % said
	)
	var from := Vector2(two.x, two.y)
	for t in 90:
		var drive_on := Game.Controls.new()
		drive_on.forward = 1.0
		g.tick(STEP, {0: drive_on, 1: Game.Controls.new()})
	_check(
		(
			Vector2(two.x, two.y).distance_to(from) > 2.0
			and Vector2(two.x, two.y).distance_to(Vector2(v.x, v.y)) < 2.0
		),
		"co-op: the rider goes along with it"
	)


## A game driven and a fresh one made from its snapshot go on the same.
func _lockstep(main) -> void:
	var a := _game(main, "speedway", false)
	walk_up(a)
	a.interact()
	drive(a, 120, 1.0, .4)
	var snap := GameSnapshot.capture(a)
	var unknown: Array = snap["unknown"]
	_check(unknown.is_empty(), "the snapshot knows the vehicles %s" % str(unknown))
	var b := _game(main, "speedway", false)
	GameSnapshot.apply(b, snap)
	_check(rides(b).seated(b.player), "the copy has the player at the wheel")
	for t in 240:
		var c := Game.Controls.new()
		c.forward = 1.0 if t < 160 else -1.0
		c.strafe = sin(t * .05)
		c.jump = t % 50 < 10
		a.tick(STEP, c)
		b.tick(STEP, c)
	var sa := GameSnapshot.capture(a)
	var sb := GameSnapshot.capture(b)
	var same := GameSnapshot.same(sa, sb)
	if not same:
		print("    first difference: ", GameSnapshot.first_difference(sa, sb))
	_check(same, "the copy drives the same as the game, tick for tick")
