## Gator Bayou's ways (chapter five), kept out of enemies.gd, which calls in
## here at the top of Enemy.tick() and of Enemy.attack().
##
## In the bayou everybody wades: the county's hands slow and sink to the knee
## in shallow water. A kind with `swims` (enemies.cfg) goes into the deep
## channels nobody else can (LevelData.deep_at): a gator lies low in water,
## only its eyes and back showing, and is quick there and slow on the bank. A
## `lurks` kind (the noodler) squats in the water to the eyes until it is
## roused and comes up out of it all at once. A `calls_gators` kind (the chum
## tosser) slings chum when it first sees the player, and every gator near
## wakes and comes. The swamp king's airboat circles its lagoon (it will not
## be drawn far from where it started), fires its punt gun, and makes AIRBOAT
## RUNS: a lane marked on the water (features/bayou_feature.gd), then the boat
## along it flat out, ramming whatever stands in it; one that runs into a wall
## or a piling sits stunned a moment. Past half health, the runs come in pairs.
class_name BayouBrains
extends RefCounted

const SKY := "bayou_sky"
## How far an airboat run goes, how fast, and what it does to the player.
const RUN_LENGTH := 12.0
const RUN_SPEED := 8.4
const RUN_DAMAGE := 22
## How far from where it started the king's boat will go before it turns back.
const LEASH := 12.5


static func is_king(e: Enemy) -> bool:
	return e.brain == "swamp_king"


## Water, shallow or deep, at the point.
static func wet_at(world: LevelData, x: float, y: float) -> bool:
	if x < 0.0 or y < 0.0 or x >= world.width or y >= world.height:
		return false
	if world.deep_at(x, y):
		return true
	return world.surface_sound(int(world.floor_tile[world.cell(x, y)])) == "water"


## Whether this attack (counted from 1) is an airboat run rather than the punt
## gun: every other one (two in three when mad), and only with room to run.
static func runs_on(e: Enemy, number: int, world: LevelData, bearing: float) -> bool:
	if lane(e, world, bearing) < 3.0:
		return false
	return e.has_meta("pair") or number % 2 == 1 or (e.enraged and number % 3 != 0)


## How far a run along `bearing` would go: open water, up to RUN_LENGTH.
static func lane(e: Enemy, world: LevelData, bearing: float) -> float:
	var length := 0.0
	while length < RUN_LENGTH:
		var step := length + .3
		var at := Vector2(e.x + cos(bearing) * step, e.y + sin(bearing) * step)
		if world.blocked(at.x, at.y, .2) or not wet_at(world, at.x, at.y):
			break
		length = step
	return length


## True when it took the whole tick (an airboat mid-run, the boat turning home).
static func tick(e: Enemy, dt: float, game) -> bool:
	var world: LevelData = game.world
	if not e.swims and world.sky != SKY:
		return false
	var deep := world.deep_at(e.x, e.y)
	var wet := deep or world.surface_sound(int(world.floor_tile[world.cell(e.x, e.y)])) == "water"
	var base := float(Enemy.KINDS[e.kind][1])
	if is_king(e):
		return _king(e, dt, game, wet)
	var want := 0.0
	var spec: Dictionary = Enemy.DEFS[e.kind]
	if e.swims:
		e.speed = base * (1.75 if wet else .8)
		if wet:
			var low := e.windup <= 0.0 and e.recovery <= 0.0 and e.stun <= 0.0
			want = (.3 if e.alerted else .38) if low else .1
	else:
		e.speed = base * (.8 if wet else 1.0)
		if wet:
			want = .22
			if bool(spec.get("lurks", false)) and not e.alerted:
				want = e.height * .8
		if bool(spec.get("calls_gators", false)) and e.alerted and not e.has_meta("called"):
			e.set_meta("called", true)
			if call_gators(game, e.x, e.y, 13.0) > 0:
				game.message("CHUM'S IN THE WATER! GATORS COMIN'.", 2.4)
				game.sound_at("chum_holler", e.x, e.y, .9)
	if not e.has_meta("settled"):
		# Already down in the water when the chapter starts, not sinking into it.
		e.set_meta("settled", true)
		e.sunk = want
	var was := e.sunk
	e.sunk = move_toward(e.sunk, want, dt * (4.0 if want < e.sunk else 1.2))
	if was > e.height * .5 and e.sunk <= e.height * .5:
		# Up out of the water all at once.
		game.burst(e.x, e.y, world.elevation(e.x, e.y) + .1, "splash", 16, 1.8)
		game.sound_at("noodler_rise", e.x, e.y, .85)
	return false


## Every gator within `reach` that has not seen the player yet comes for them.
static func call_gators(game, x: float, y: float, reach: float) -> int:
	var p = game.player
	var woke := 0
	for other: Enemy in game.enemies:
		if not other.swims or is_king(other) or not other.alive or other.alerted:
			continue
		if Vector2(other.x - x, other.y - y).length() < reach:
			other.wake(game, p.x, p.y)
			other.hunt_until = game.clock + 12.0
			woke += 1
	return woke


static func _king(e: Enemy, dt: float, game, wet: bool) -> bool:
	if not e.has_meta("home"):
		e.set_meta("home", Vector2(e.x, e.y))
	e.sunk = 0.0
	e.speed = float(Enemy.KINDS[e.kind][1]) * (1.25 if e.enraged else 1.0)
	# An airboat keeps to the water: a step onto planks or a bank is taken back.
	if wet:
		e.set_meta("wet_at", Vector2(e.x, e.y))
	elif not e.has_meta("run") and e.has_meta("wet_at"):
		var back: Vector2 = e.get_meta("wet_at")
		e.x = back.x
		e.y = back.y
	if e.has_meta("run"):
		_run(e, dt, game, e.get_meta("run"), wet)
		return true
	if e.stun > 0.0 or e.windup > 0.0 or not e.alerted:
		return false
	var home: Vector2 = e.get_meta("home")
	if Vector2(e.x, e.y).distance_to(home) > LEASH:
		e.follow(dt, game, atan2(home.y - e.y, home.x - e.x), 1.1)
		return true
	# Too close in to the bank to get up speed: swing out to line up the next run.
	var p = game.player
	if Vector2(p.x - e.x, p.y - e.y).length() < 5.0 and e.cooldown > -1.0:
		var away := atan2(e.y - p.y, e.x - p.x) + (.5 if int(e.pose / 2.0) % 2 else -.5)
		e.follow(dt, game, away, .9)
		return true
	return false


## One tick of an airboat run: [heading, cells left, hit yet, second of a pair].
static func _run(e: Enemy, dt: float, game, run: Array, wet: bool) -> void:
	var p = game.player
	var heading: float = run[0]
	var step := RUN_SPEED * (1.15 if e.enraged else 1.0) * dt
	var ox := e.x
	var oy := e.y
	var bow := Vector2(e.x + cos(heading) * (step + .5), e.y + sin(heading) * (step + .5))
	if wet_at(game.world, bow.x, bow.y):
		game.move_actor(e, cos(heading) * step, sin(heading) * step, e.radius)
	var moved := Vector2(e.x - ox, e.y - oy).length()
	e.angle = heading
	e.face_left = cos(heading) < 0.0
	e.gait += moved * 6.0
	e.last_stride = e.pose
	run[1] = float(run[1]) - moved
	if wet and fmod(e.pose, .12) < dt:
		game.burst(
			e.x - cos(heading) * .9,
			e.y - sin(heading) * .9,
			game.world.elevation(e.x, e.y) + .15,
			"splash",
			5,
			1.6
		)
	var gap := Vector2(p.x - e.x, p.y - e.y).length()
	if not bool(run[2]) and gap < e.radius + .6 and p.air < .5:
		run[2] = true
		game.damage(RUN_DAMAGE, [e.x, e.y], "AIRBOAT")
		game.shake = minf(1.0, game.shake + .5)
		var side := (
			heading + (PI / 2.0 if sin(atan2(p.y - e.y, p.x - e.x) - heading) > 0.0 else -PI / 2.0)
		)
		game.move_actor(p, cos(side) * .7, sin(side) * .7, GameState.PLAYER_RADIUS)
		game.sound_at("king_ram", e.x, e.y, 1.0)
	if moved >= step * .35 and float(run[1]) > 0.0:
		return
	e.remove_meta("run")
	e.recovery = .55
	e.cooldown = .8 if e.enraged else 1.3
	if moved < step * .35 and not bool(run[2]):
		# Run up on a piling or a bank: it sits there a breath, wide open.
		e.stun = 1.4
		e.flinch = .5
		game.shake = minf(1.0, game.shake + .4)
		game.burst(e.x, e.y, game.world.elevation(e.x, e.y) + .4, "dust", 14, 1.8)
		game.sound_at("king_beached", e.x, e.y, 1.0)
		game.message("HE BEACHED IT! LIGHT HIM UP!", 2.0)
	elif e.enraged and not bool(run[3]) and e.stun <= 0.0:
		# Fightin' mad: straight round and back at you.
		e.set_meta("pair", true)
		e.windup = .6
		e.aim_mark = [p.x, p.y, p.eye]
		game.sound_at("king_rev", e.x, e.y, .8)


## True when it made this attack itself (the king's runs and punt gun).
static func attack(e: Enemy, game, direction: float, distance: float, eye: float) -> bool:
	if not is_king(e):
		return false
	if runs_on(e, e.attacks, game.world, direction):
		var second := e.has_meta("pair")
		e.remove_meta("pair")
		e.set_meta("run", [direction, RUN_LENGTH, false, second])
		game.sound_at("king_charge", e.x, e.y, 1.0)
		game.shake = minf(1.0, game.shake + .25)
		return true
	# The punt gun: a spray of slugs off the bow.
	var spread := 5 if not e.enraged else 7
	for k in spread:
		var bearing := direction + (k - (spread - 1) / 2.0) * .11
		var sx := e.x + cos(bearing) * (e.radius + .3)
		var sy := e.y + sin(bearing) * (e.radius + .3)
		var aim: float = game.player.eye
		var slope := (aim - eye) * 7.6 / maxf(distance, 1.0)
		if not game.world.blocked(sx, sy, .045, eye):
			game.launch(sx, sy, eye, bearing, 7.6, "deputy_slug", slope, true, 6, 1.4)
	game.burst(e.x + cos(direction) * 1.1, e.y + sin(direction) * 1.1, eye, "spark", 8, 1.6)
	game.sound_at("king_puntgun", e.x, e.y, 1.0)
	e.cooldown = 1.25 if e.enraged else 1.7
	return true
