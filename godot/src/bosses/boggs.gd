## BUMPER BOGGS, the speedway's champion in his armoured derby car: ramming
## lanes and spare tyres, and he stalls when he hits a wall (derby_champ.gd,
## enemies.cfg [derby_champ]).
##
## Kind `derby_champ`. His fight in the derby bowl (speedway_plan.gd):
##   the bowl     a charge that ends in the pit crew's nitro or gas cans sets
##                them off (derby_champ.gd _crash), on him and whoever is near.
##   phase 3      NITRO RAM: every other attack he lights the nitro, his whole
##                run painted first (three legs, off the walls like a cue
##                ball), then goes down it twice as fast and stalls a long
##                breath at the end; the bowl's floodlights blow and the wrecks
##                burn (features/boss_arenas.gd).
##   weak spot    the radiator: a hit from in front of the car, low, counts double.
##   HOG WILD     OIL FIRE: his charges leave burning oil down the lane.
extends BossMoves

const NITRO_WINDUP := 1.3
const NITRO_SPEED := 10.5
const NITRO_LEGS := 3
const NITRO_REACH := 34.0
const NITRO_DAMAGE := 34
const NITRO_STALL := 1.9
## How far off his heading a shot can come from and still find the radiator.
const FRONT := .9
const WEAK := 2.0
const PACE := [1.3, 1.0, .92, .84]


func stagger_hit(_e: Enemy) -> float:
	return 180.0


func stagger_rest(_e: Enemy) -> float:
	return 6.0


func phase_changed(e: Enemy, game, phase: int) -> void:
	if phase == 3:
		var arenas = game.features.get("boss_arenas")
		if arenas != null:
			arenas.turn(e)


func tick(e: Enemy, dt: float, game) -> bool:
	if hog_wild(game):
		_oil(e, game)
	if e.has_meta("nitro"):
		_nitro(e, dt, game)
		return true
	if _nitro_ready(e, dt, game):
		_start_nitro(e, game)
		return true
	return false


func _mode(e: Enemy) -> String:
	var s: Dictionary = DerbyChamp.state.get(e.get_instance_id(), {})
	return String(s.get("mode", "roam")) if s.get("who") == e else "roam"


func _nitro_ready(e: Enemy, dt: float, game) -> bool:
	if e.boss_phase < 3 or not e.alerted or e.stun > 0.0 or e.recovery > .1:
		return false
	if _mode(e) != "roam" or e.attacks % 2 != 1:
		return false
	if e.cooldown > dt * float(game.sharpness):
		return false
	var p = game.player
	var eye: float = game.world.elevation(e.x, e.y) + 1.1
	return (
		Vector2(p.x - e.x, p.y - e.y).length() < 18.0
		and game.world.visible(e.x, e.y, p.x, p.y, eye, p.eye)
	)


## NITRO RAM: the run worked out and painted, the wind-up, then down it.
func _start_nitro(e: Enemy, game) -> void:
	var p = game.player
	var heading := atan2(p.y - e.y, p.x - e.x)
	var legs := legs_from(e, game, heading)
	if legs.is_empty():
		e.attacks += 1
		return
	e.windup = NITRO_WINDUP * float(PACE[clampi(game.difficulty, 0, 3)])
	e.aim_mark = null
	e.angle = heading
	e.face_left = cos(heading) < -.24
	e.set_meta("nitro", {"legs": legs, "leg": 0, "hit": false, "from": Vector2(e.x, e.y)})
	e.set_meta("tell", "NITRO RAM!")
	game.sound_at("derby_champ_warn", e.x, e.y, 1.0)
	game.sound_at("fuse_hiss", e.x, e.y, .8)


## The run's legs from where he stands along `heading`: as far as the bowl
## lets him, then off whatever stops him, NITRO_LEGS times at most.
static func legs_from(e: Enemy, game, heading: float) -> Array:
	var out: Array = []
	var at := Vector2(e.x, e.y)
	var dir := Vector2(cos(heading), sin(heading))
	var budget := NITRO_REACH
	var w: LevelData = game.world
	var r := e.radius * .8
	for k in NITRO_LEGS:
		var run := 0.0
		while run < budget:
			var next := at + dir * (run + .3)
			if w.blocked(next.x, next.y, r):
				break
			run += .3
		if run < 1.2:
			break
		var end := at + dir * run
		out.append(end)
		budget -= run
		# Off the wall like a ball off a cushion: flip what the wall stops.
		var probe := end + dir * .45
		var stop_x: bool = w.blocked(probe.x, end.y, r)
		var stop_y: bool = w.blocked(end.x, probe.y, r)
		if stop_x or not stop_y:
			dir.x = -dir.x
		if stop_y or not stop_x:
			dir.y = -dir.y
		at = end
	return out


func _nitro(e: Enemy, dt: float, game) -> void:
	var run: Dictionary = e.get_meta("nitro")
	if not bool(run.get("going", false)):
		e.windup = maxf(0.0, e.windup - dt)
		if e.stun > .3:
			# Knocked out of it before he lit it.
			_end_nitro(e, game, false)
			return
		if e.windup > 0.0:
			return
		run["going"] = true
		game.sound_at("millhand_rev", e.x, e.y, 1.0)
		game.shake = minf(1.0, game.shake + .3)
	# Keep the run painted while he is on it (BossMoves.telegraph needs a wind-up).
	e.windup = .01
	var legs: Array = run["legs"]
	var leg := int(run["leg"])
	var end: Vector2 = legs[leg]
	var heading := atan2(end.y - e.y, end.x - e.x)
	e.angle = heading
	e.face_left = cos(heading) < -.24
	_ram(e, run, game, heading)
	var want := NITRO_SPEED * dt
	var moved := e.advance(dt, game, heading, NITRO_SPEED / maxf(.1, e.speed))
	var floor_z: float = game.world.elevation(e.x, e.y)
	if int(game.clock * 8.0) % 2 == 0:
		game.burst(e.x - cos(heading) * .9, e.y - sin(heading) * .9, floor_z + .2, "dust", 2, 1.0)
	if Vector2(e.x, e.y).distance_to(end) > .45 and moved >= want * .35:
		return
	# Off a wall: sparks, a bang, and on to the next leg or a dead stall.
	var fx := e.x + cos(heading) * (e.radius + .1)
	var fy := e.y + sin(heading) * (e.radius + .1)
	game.burst(fx, fy, floor_z + .6, "spark", 14, 2.4)
	game.sound_at("derby_champ_crash", fx, fy, .9)
	var pieces = game.features.get("breakables")
	if pieces != null:
		pieces.blast(fx, fy, floor_z + .4, 1.1, 50.0, false)
	game.shake = minf(1.0, game.shake + .25)
	run["leg"] = leg + 1
	run["hit"] = false
	if leg + 1 >= legs.size():
		_end_nitro(e, game, true)


## The player (or one of the county's) in the way of the run.
func _ram(e: Enemy, run: Dictionary, game, heading: float) -> void:
	var p = game.player
	var px: float = p.x - e.x
	var py: float = p.y - e.y
	var ahead := px * cos(heading) + py * sin(heading)
	var side := absf(px * sin(heading) - py * cos(heading))
	if not bool(run["hit"]) and ahead > -.2 and ahead < e.radius + .8 and side < e.radius + .35:
		run["hit"] = true
		game.damage(NITRO_DAMAGE, [e.x, e.y], "NITRO RAM")
		var off := 1.0 if px * sin(heading) - py * cos(heading) < 0.0 else -1.0
		var throw := heading + off * PI / 2.0
		game.move_actor(p, cos(throw) * 1.3, sin(throw) * 1.3, GameState.PLAYER_RADIUS)
		game.shake = minf(1.0, game.shake + .9)
		game.sound_at("scenery_scrap", p.x, p.y, 1.0)
	for other: Enemy in game.enemies:
		if other == e or not other.alive or not other.hostile:
			continue
		var ox := other.x - e.x
		var oy := other.y - e.y
		var along := ox * cos(heading) + oy * sin(heading)
		if along > 0.0 and along < e.radius + other.radius + .4:
			if absf(ox * sin(heading) - oy * cos(heading)) < e.radius + other.radius:
				other.hurt(60.0, game, false, false, e)


func _end_nitro(e: Enemy, game, stalled: bool) -> void:
	e.remove_meta("nitro")
	e.remove_meta("tell")
	e.windup = 0.0
	e.aim_mark = null
	e.attacks += 1
	e.cooldown = 1.0
	if not stalled:
		return
	# Dead in the water: the long breath to light him up.
	e.recovery = NITRO_STALL
	e.stun = maxf(e.stun, .3)
	var s: Dictionary = DerbyChamp.state.get(e.get_instance_id(), {})
	if s.get("who") == e:
		s["mode"] = "stall"
		s["again"] = 0
	game.message("HE BLEW HIS NITRO! LET HIM HAVE IT!", 2.0)


## HOG WILD: a charge leaves burning oil down its lane.
func _oil(e: Enemy, game) -> void:
	if _mode(e) != "charge" and not bool(e.get_meta("nitro", {}).get("going", false)):
		e.remove_meta("oil_at")
		return
	var last: Vector2 = e.get_meta("oil_at", Vector2(e.x, e.y))
	if not e.has_meta("oil_at"):
		e.set_meta("oil_at", last)
		return
	if last.distance_to(Vector2(e.x, e.y)) < 1.4:
		return
	e.set_meta("oil_at", Vector2(e.x, e.y))
	var arenas = game.features.get("boss_arenas")
	if arenas != null:
		arenas.burn(last.x, last.y)


func telegraph(e: Enemy, game) -> Array:
	var out: Array = []
	if not e.has_meta("nitro"):
		return out
	var run: Dictionary = e.get_meta("nitro")
	var legs: Array = run["legs"]
	var at: Vector2 = Vector2(e.x, e.y) if bool(run.get("going", false)) else run["from"]
	var z: float = game.world.elevation(e.x, e.y) + .004
	for k in range(int(run["leg"]), legs.size()):
		var end: Vector2 = legs[k]
		var mid := (at + end) * .5
		var half := at.distance_to(end) * .5
		if half > .3:
			out.append(
				Renderer.GroundMark.new(
					mid.x, mid.y, z, (end - at).angle(), half, e.radius, "mark_lane"
				)
			)
		at = end
	return out


## The radiator: hit from in front of the car, low.
func weak_spot(e: Enemy, game, hit: Vector3, from: Vector2, how: String) -> float:
	if how == "blast" or how == "energy" or how == "fire" or how == "steam":
		return 1.0
	var toward_shooter := atan2(from.y - e.y, from.x - e.x)
	if absf(Enemy.angle_delta(toward_shooter, e.angle)) > FRONT:
		return 1.0
	var up: float = (hit.z - game.world.elevation(e.x, e.y)) / maxf(.5, e.height)
	return WEAK if up > .03 and up < .42 else 1.0


## The radiator steaming once he is mad, the nitro burning out the back in
## his last phase and while he lights it.
func looks(e: Enemy, game) -> Array:
	var out: Array = []
	var floor_z: float = game.world.elevation(e.x, e.y)
	var frame := int(game.clock * 10.0)
	if e.boss_phase >= 2:
		var front := Vector2(e.x + cos(e.angle) * .55, e.y + sin(e.angle) * .55)
		var age := fposmod(game.clock * 1.6, 1.0)
		var steam := Renderer.Sprite.new(
			front.x, front.y, "fx_steam_%d" % mini(3, int(age * 4.0)), .4 + age * .4, floor_z + .5
		)
		steam.translucent = true
		out.append(steam)
	if e.boss_phase >= 3 or e.has_meta("nitro"):
		var big := 1.0 if e.has_meta("nitro") else .55
		for k in 2:
			var side := (k - .5) * .5
			var back := Vector2(
				e.x - cos(e.angle) * .75 - sin(e.angle) * side,
				e.y - sin(e.angle) * .75 + cos(e.angle) * side
			)
			var fire := Renderer.Sprite.new(
				back.x, back.y, "fx_fire_%d" % ((frame + k * 2) % 4), .5 * big + .2, floor_z + .25
			)
			fire.glow = true
			out.append(fire)
	return out


func dying(e: Enemy, game) -> void:
	var z: float = game.world.elevation(e.x, e.y)
	var fight = game.features.get("boss_fight")
	if fight != null:
		fight.sparks(e.x, e.y, z + .6, "chips", 18, 3.4)
		fight.sparks(e.x, e.y, z + .3, "dust", 20, 2.4)
	game.message("BOGGS IS TOTALED!", 2.6)
