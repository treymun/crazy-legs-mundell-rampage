## Checks of where hits land and how the county falls (tools/check_fixes.gd
## runs them; this also runs on its own, from a scratch profile):
##
##   Godot --headless --path <project> --script res://tools/hit_check.gd
##
## Hit locations (src/hit_zones.gd): a revolver round on the head does twice
## a body shot, on the legs less and the hand limps, slower; an arm hit makes
## a hand drop its weapon (it walks to it and has it again) or throws its aim
## wide; the head knocks the hat off and a kill pops. Deaths by weapon
## (features/corpses.gd): buckshot at arm's length throws a fresh hand into
## the window behind it and the window breaks, both barrels take one apart;
## the cow launcher throws a body
## whole and high; a body killed in the bayou's water floats and bobs. Hit
## feedback: a bigger instant reels a hand further; a tin guard sparks. The
## animals (features/critters.gd): chickens scatter and flap at a shot, a hurt
## hog charges the player, a blast shoves Bessie and she lives, a hit gator
## thrashes.
extends SceneTree

const DT := 1.0 / 60.0

var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	run(
		main,
		func(ok: bool, text: String) -> void:
			print("  ok   " if ok else "  FAIL ", text)
			if not ok:
				failures.append(text)
	)
	print("")
	print("HIT CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


static func _game(main, level_id: String) -> Game:
	var g: Game = main.make_game(level_id)
	g.configure({})
	g.cheats.god = true
	g.spawn_grace = 0.0
	return g


static func _ticks(g: Game, seconds: float, actors := false) -> void:
	for _k in int(seconds * 60.0):
		g.clock += DT
		if actors:
			for e: Enemy in g.enemies:
				e.tick(DT, g)
		g.update_shots(DT)
		g.ticked.emit(DT)


## The first of a kind, every other enemy put to sleep out of the way.
static func _only(g: Game, kind: String) -> Enemy:
	var found: Enemy = null
	for e: Enemy in g.enemies:
		if found == null and e.kind == kind and e.alive:
			found = e
		else:
			e.dormant = true
	return found


## A flat stretch of open floor with room either way along x.
static func _open_spot(g: Game) -> Vector2:
	var w: LevelData = g.world
	for cy in range(2, w.height - 2):
		for cx in range(5, w.width - 5):
			var at := Vector2(cx + .5, cy + .5)
			var flat := true
			for k in range(-4, 5):
				var q := at + Vector2(k * .6, 0)
				flat = (
					flat
					and not w.blocked(q.x, q.y, .4)
					and w.elevation(q.x, q.y) == w.elevation(at.x, at.y)
					and w.roof[w.cell(q.x, q.y)] == 0.0
				)
			if flat and w.visible(at.x - 3.0, at.y, at.x, at.y):
				return at
	return Vector2(g.player.x, g.player.y)


## Stands the player `far` west of `e` (at `at`), both facing each other.
static func _face_off(g: Game, e: Enemy, at: Vector2, far: float) -> void:
	e.x = at.x
	e.y = at.y
	e.angle = PI
	e.alerted = true
	g.player.x = at.x - far
	g.player.y = at.y
	g.player.angle = 0.0
	g.player.eye = g.world.elevation(at.x, at.y) + .95


## One straight revolver round from the player at `e` (put back at `at`) at
## this share of the body's height, `aside` cells off its middle; what it took.
static func _shot(g: Game, e: Enemy, at: Vector2, up: float, aside := 0.0) -> float:
	g.armory.active = Weapons.REVOLVER
	e.x = at.x
	e.y = at.y
	var p := g.player
	var d := Vector2(e.x - p.x, e.y - p.y).length()
	var z: float = g.world.stand(e) + e.z + e.height * e.variant * up
	var angle := atan2(e.y - p.y, e.x - p.x) + atan2(aside, d)
	e.hp = 500.0
	e.stun = 0.0
	g.clock += .5
	g.hitscan(angle, (z - p.eye) / d, float(Weapons.DAMAGE[Weapons.REVOLVER]), 20.0, 0.0)
	return 500.0 - e.hp


static func run(main, check: Callable) -> void:
	print("HIT LOCATIONS, DEATHS BY WEAPON, CRITTERS")
	_zones(main, check)
	_arms(main, check)
	_throws(main, check)
	_floating(main, check)
	_critters(main, check)


static func _zones(main, check: Callable) -> void:
	var g := _game(main, "hickston")
	var e := _only(g, "billy")
	var at := _open_spot(g)
	_face_off(g, e, at, 3.0)
	var round := float(Weapons.DAMAGE[Weapons.REVOLVER])
	var body := _shot(g, e, at, .6)
	var body_zone := e.last_zone
	var head := _shot(g, e, at, .9)
	var head_zone := e.last_zone
	check.call(
		(
			body_zone == "body"
			and head_zone == "head"
			and is_equal_approx(body, round)
			and is_equal_approx(head, round * HitZones.HEAD["revolver"])
		),
		"a revolver round on the head does %.0f, on the body %.0f" % [head, body]
	)
	var reads = g.features["hit_reads"]
	check.call(
		e.hatless and reads.bits.size() == 1 and g.hit_mark_head,
		"the head knocks the hat off (it tumbles) and marks the crosshair gold"
	)
	var again := _shot(g, e, at, .9)
	check.call(
		is_equal_approx(again, head) and reads.bits.size() == 1,
		"the same shot does the same again (no dice), and a hat comes off once"
	)
	# Legs: less, and it limps.
	var legs := _shot(g, e, at, .2)
	check.call(
		e.last_zone == "legs" and legs < body and e.limp_until > g.clock,
		"on the legs %.0f, and the hand limps" % legs
	)
	var start := Vector2(e.x, e.y)
	e.stun = 0.0
	var limped := e.advance(.1, g, PI)
	e.x = start.x
	e.y = start.y
	e.limp_until = -1.0
	var walked := e.advance(.1, g, PI)
	check.call(
		limped < walked * .7 and limped > 0.0,
		"limping it covers %.3f a step, %.3f sound" % [limped, walked]
	)
	# Arms: off the middle at chest height.
	var arm := _shot(g, e, at, .6, e.radius * .8)
	check.call(
		e.last_zone == "arms" and arm < body, "an arm hit does %.0f (%s)" % [arm, e.last_zone]
	)
	# A head shot that kills pops.
	e.hp = 20.0
	g.clock += .5
	var p := g.player
	var d := Vector2(e.x - p.x, e.y - p.y).length()
	var top: float = g.world.stand(e) + e.height * e.variant * .9
	g.hitscan(atan2(e.y - p.y, e.x - p.x), (top - p.eye) / d, round, 20.0, 0.0)
	check.call(not e.alive and reads.pops() == 1, "a head shot that kills pops")
	# Buckshot: per pellet on the head a little more, the load stays a load.
	check.call(
		HitZones.HEAD["shotgun"] < HitZones.HEAD["revolver"] and HitZones.LEGS < 1.0,
		"a pellet on the head counts %.2f, a round %.2f" % [HitZones.HEAD["shotgun"], 2.0]
	)
	# A tin guard rings and sparks; a grey bleeds.
	var ship := _game(main, "mothership")
	var guard := _only(ship, "tin_guard")
	check.call(
		guard != null and HitZones.metal(guard) and not HitZones.METAL.has("alien"),
		"a tin guard is metal (sparks and a clank, no blood)"
	)
	# A bigger instant reels a hand further back.
	var g2 := _game(main, "hickston")
	var hand := _only(g2, "billy")
	_face_off(g2, hand, _open_spot(g2), 2.0)
	var from := hand.x
	g2.hit_point = Vector3(hand.x, hand.y, g2.world.stand(hand) + 1.0)
	g2.hit_from = Vector2(g2.player.x, g2.player.y)
	hand.hurt(8.0, g2, false, false, null, "revolver")
	var small := hand.x - from
	hand.x = from
	hand.hp = 500.0
	g2.clock += 1.0
	g2.hit_point = Vector3(hand.x, hand.y, g2.world.stand(hand) + 1.0)
	hand.hurt(64.0, g2, false, false, null, "rifle")
	var big := hand.x - from
	check.call(
		big > small + .1 and hand.stun > 0.0,
		"a big instant reels a hand back %.2f, a small one %.2f" % [big, small]
	)


static func _arms(main, check: Callable) -> void:
	var g := _game(main, "hickston")
	var e := _only(g, "coot")
	var at := _open_spot(g)
	_face_off(g, e, at, 3.0)
	var dropped := false
	for k in 30:
		_shot(g, e, at, .6, e.radius * .8)
		if e.disarmed_until > 0.0:
			dropped = true
			break
	check.call(
		dropped and e.arm_at != Vector2.INF and g.features["hit_reads"].bits.size() >= 1,
		"an arm hit makes a hand drop its pistol where it can be seen"
	)
	if not dropped:
		return
	var lies := e.arm_at
	var reached := false
	g.player.x = at.x - 6.0
	for _k in 360:
		g.clock += DT
		e.tick(DT, g)
		g.ticked.emit(DT)
		if Vector2(e.x, e.y).distance_to(lies) < .3:
			reached = true
		if e.disarmed_until < 0.0:
			break
	check.call(
		reached and e.disarmed_until < 0.0 and e.arm_at == Vector2.INF,
		"it walks to its pistol, picks it up and has it again"
	)
	# A hand with nothing to drop: an arm hit throws its wind-up's aim wide.
	var g2 := _game(main, "hickston")
	var thrower := _only(g2, "yard_deputy")
	_face_off(g2, thrower, _open_spot(g2), 3.0)
	thrower.windup = .3
	var p := g2.player
	thrower.aim_mark = [p.x, p.y, p.eye]
	# Its dice for a drop already rolled this instant: the aim it is.
	thrower.arm_roll = g2.clock
	g2.hit_point = Vector3(thrower.x, thrower.y + thrower.radius * .8, p.eye + .2)
	g2.hit_from = Vector2(p.x, p.y)
	thrower.hurt(5.0, g2, false, false, null, "revolver")
	var mark: Array = thrower.aim_mark if thrower.aim_mark != null else [p.x, p.y]
	check.call(
		(
			thrower.last_zone == "arms"
			and Vector2(mark[0], mark[1]).distance_to(Vector2(p.x, p.y)) > 1.0
		),
		"an arm hit throws a wind-up's aim wide"
	)


static func _throws(main, check: Callable) -> void:
	# Buckshot at arm's length throws a fresh hand back into the window behind it.
	var g := _game(main, "hickston")
	var breaks = g.features["wall_breaks"]
	var e := _only(g, "billy")
	var w: LevelData = g.world
	var face = null
	var stand := Vector2.ZERO
	var gun := Vector2.ZERO
	for f in breaks.windows:
		var n: Vector2 = f.normal()
		var a: Vector2 = f.middle() + n * .75
		var b: Vector2 = f.middle() + n * 2.2
		if (
			not w.blocked(a.x, a.y, .3)
			and not w.blocked(b.x, b.y, .3)
			and w.elevation(a.x, a.y) == w.elevation(b.x, b.y)
			and absf(w.elevation(a.x, a.y)) < .05
			and w.visible(b.x, b.y, a.x, a.y)
		):
			face = f
			stand = a
			gun = b
			break
	if face == null:
		check.call(false, "a window in Hickston with room before it")
		return
	e.x = stand.x
	e.y = stand.y
	g.player.x = gun.x
	g.player.y = gun.y
	g.hit_point = Vector3(e.x, e.y, 1.0)
	g.hit_from = gun
	for _k in Weapons.SHOTGUN_PELLETS:
		g.hit_point = Vector3(e.x, e.y, 1.0)
		e.hurt(float(Weapons.SHOTGUN_DAMAGE), g, false, false, null, "shotgun")
	_ticks(g, 1.5)
	check.call(
		not e.alive and not e.explosive and face.broken and g.features["corpses"].crashes() >= 1,
		"a load of buckshot at arm's length throws a hand through the window behind it"
	)
	# Both barrels at once take it apart.
	var g2 := _game(main, "hickston")
	var half := _only(g2, "billy")
	g2.armory.last_spent = 2
	var spot := _open_spot(g2)
	_face_off(g2, half, spot, 1.5)
	for _k in Weapons.SHOTGUN_PELLETS:
		g2.hit_point = Vector3(half.x, half.y, 1.0)
		g2.hit_from = Vector2(g2.player.x, g2.player.y)
		half.hurt(float(Weapons.SHOTGUN_DAMAGE), g2, false, false, null, "shotgun")
	check.call(half.explosive, "both barrels at once take a hand apart")
	# The cow launcher throws a body whole and high; a rifle drops one in place.
	var g3 := _game(main, "hickston")
	var cowed := _only(g3, "clone")
	spot = _open_spot(g3)
	_face_off(g3, cowed, spot, 4.0)
	cowed.hp = 20.0
	var z: float = g3.world.elevation(spot.x, spot.y) + .4
	g3.explode(Game.Shot.new(spot.x - .8, spot.y, z, 0.0, 0.0, 0.0, "cow", 0.0, false, 180))
	var highest := 0.0
	for _k in 90:
		g3.clock += DT
		g3.ticked.emit(DT)
		highest = maxf(highest, cowed.toss)
	check.call(
		not cowed.alive and not cowed.explosive and highest > .8,
		"the cow launcher throws a body whole, %.2f high" % highest
	)
	var g4 := _game(main, "hickston")
	var shot := _only(g4, "clone")
	spot = _open_spot(g4)
	_face_off(g4, shot, spot, 4.0)
	shot.hp = 10.0
	g4.hit_point = Vector3(shot.x, shot.y, 1.0)
	g4.hit_from = Vector2(g4.player.x, g4.player.y)
	shot.hurt(21.0, g4, false, false, null, "rifle")
	_ticks(g4, 1.0)
	check.call(
		Vector2(shot.x, shot.y).distance_to(spot) < .2,
		(
			"a rifle round drops a body where it stood (%.2f)"
			% Vector2(shot.x, shot.y).distance_to(spot)
		)
	)


static func _floating(main, check: Callable) -> void:
	var g := _game(main, "bayou")
	var w: LevelData = g.world
	var wet := Vector2.INF
	for cy in range(2, w.height - 2):
		for cx in range(2, w.width - 2):
			var at := Vector2(cx + .5, cy + .5)
			if not w.blocked(at.x, at.y, .3) and BayouBrains.wet_at(w, at.x, at.y):
				wet = at
				break
		if wet != Vector2.INF:
			break
	var e := _only(g, "billy")
	if wet == Vector2.INF or e == null:
		check.call(false, "water in the bayou to float a body in")
		return
	e.x = wet.x
	e.y = wet.y
	g.player.x = wet.x - 3.0
	g.player.y = wet.y
	g.hit_point = Vector3(e.x, e.y, 1.0)
	g.hit_from = Vector2(g.player.x, g.player.y)
	e.hp = 10.0
	e.hurt(12.0, g, false, false, null, "rifle")
	_ticks(g, 2.5)
	var low := 9.0
	var high := -9.0
	for _k in 120:
		g.clock += DT
		g.ticked.emit(DT)
		low = minf(low, e.toss)
		high = maxf(high, e.toss)
	check.call(
		g.features["corpses"].floating.size() >= 1 and high - low > .03,
		"a body in the bayou's water floats and bobs (%.3f)" % (high - low)
	)


static func _critters(main, check: Callable) -> void:
	var g := _game(main, "hickston")
	var hen := _only(g, "chicken")
	var at := _open_spot(g)
	hen.x = at.x
	hen.y = at.y
	g.player.x = at.x - 3.0
	g.player.y = at.y
	g.shot_fired.emit(Weapons.REVOLVER)
	var flapped := 0.0
	for _k in 60:
		g.clock += DT
		hen.tick(DT, g)
		g.ticked.emit(DT)
		flapped = maxf(flapped, hen.hop)
	check.call(
		g.features["critters"].scattered() >= 1 and flapped > .1 and hen.x > at.x + .3,
		"a shot sends a chicken running and flapping off (%.2f up)" % flapped
	)
	# A hurt hog charges the player.
	var g2 := _game(main, "hickston")
	g2.cheats.god = false
	var hog := _only(g2, "pig")
	var spot := _open_spot(g2)
	hog.x = spot.x
	hog.y = spot.y
	g2.player.x = spot.x - 2.5
	g2.player.y = spot.y
	g2.hit_point = Vector3(hog.x, hog.y, .3)
	g2.hit_from = Vector2(g2.player.x, g2.player.y)
	hog.hurt(6.0, g2, false, false, null, "shotgun")
	var health := g2.player.health
	var charged: bool = g2.features["critters"].charging(hog)
	for _k in 150:
		g2.clock += DT
		hog.tick(DT, g2)
		g2.ticked.emit(DT)
	check.call(
		hog.alive and charged and g2.player.health < health,
		"a hurt hog charges the player and butts them (%d)" % (health - g2.player.health)
	)
	# A blast shoves Bessie and she lives.
	var g3 := _game(main, "hickston")
	var cow: Enemy = g3.bessie
	var was := Vector2(cow.x, cow.y)
	var z: float = g3.world.elevation(cow.x, cow.y) + .3
	var blast := Vector2(cow.x - 1.0, cow.y)
	for side: Vector2 in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]:
		var b := Vector2(cow.x, cow.y) + side
		if not g3.world.blocked(b.x, b.y, .1) and g3.world.visible(b.x, b.y, cow.x, cow.y):
			blast = b
			break
	g3.explode(Game.Shot.new(blast.x, blast.y, z, 0.0, 0.0, 0.0, "tnt", 0.0, false, 0))
	var up := 0.0
	for _k in 30:
		g3.clock += DT
		g3.ticked.emit(DT)
		up = maxf(up, cow.hop)
	check.call(
		cow.alive and Vector2(cow.x, cow.y).distance_to(was) > .1 and up > .05,
		"a blast shoves Bessie and bowls her up, and she lives"
	)
	# A gator hit in the water thrashes.
	var g4 := _game(main, "bayou")
	var gator: Enemy = null
	for e: Enemy in g4.enemies:
		if gator == null and e.kind == "gator" and BayouBrains.wet_at(g4.world, e.x, e.y):
			gator = e
	if gator == null:
		check.call(false, "a gator in the water")
		return
	g4.hit_point = Vector3(gator.x, gator.y, .2)
	g4.hit_from = Vector2(gator.x - 3.0, gator.y)
	gator.hurt(5.0, g4, false, false, null, "revolver")
	var turns := 0
	var facing := gator.face_left
	for _k in 30:
		g4.clock += DT
		g4.ticked.emit(DT)
		if gator.face_left != facing:
			turns += 1
			facing = gator.face_left
	check.call(turns >= 3, "a gator hit in the water thrashes (%d rolls)" % turns)
