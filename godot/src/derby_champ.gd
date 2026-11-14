## Bumper Boggs, the speedway's champion, in his armoured derby car: the boss
## of chapter 6 (enemies.cfg [derby_champ]). enemies.gd hands his whole tick
## here. He circles at a distance, then:
##   RAMMING LANE   revs with his lane painted on the ground (the windup),
##                  locks it a moment before he goes and charges down it
##                  until he hits something; the player in the lane is run
##                  down and thrown aside, the county's hands too. A charge
##                  that ends in a wall stalls him: that is the opening.
##   SPARE TYRES    up close, he slews round and spits spare tyres down a fan
##                  of lanes, also painted first.
## Fightin' mad at half health (enemies.gd _enrage): he charges again straight
## out of a crash, his radiator vents steam where he hits and he sheds parts,
## tyres bouncing off him. He goes up in a blast when he falls (_boss_falls).
class_name DerbyChamp
extends RefCounted

const CHARGE_SPEED := 7.6
const MAD_SPEED := 8.8
const CHARGE_TIME := 2.4
## The last part of the windup the lane is locked for (the dodge window).
const LOCK := .3
const RAM_DAMAGE := 30
const MAD_RAM_DAMAGE := 36

## Per champion: what he is doing ("roam", "aim", "charge", "stall", "spit"),
## the lane he locked, how long the charge has left, whether it hit the
## player, how many charges he has left in a row.
static var state := {}


static func _state(e: Enemy) -> Dictionary:
	var key := e.get_instance_id()
	var s: Dictionary = state.get(key, {})
	if s.is_empty() or s.get("who") != e:
		if state.size() > 8:
			state.clear()
		s = {"who": e, "mode": "roam", "heading": 0.0, "left": 0.0, "hit": false, "again": 0}
		state[key] = s
	return s


static func tick(e: Enemy, dt: float, game) -> void:
	var s := _state(e)
	var p = game.player
	var dx: float = p.x - e.x
	var dy: float = p.y - e.y
	var distance := sqrt(dx * dx + dy * dy)
	var toward := atan2(dy, dx)
	var eye: float = game.world.stand(e) + 1.1
	var sees: bool = distance < 18.0 and game.world.visible(e.x, e.y, p.x, p.y, eye, p.eye)
	if not e.alerted:
		if sees and distance < 12.0 and game.spawn_grace <= 0.0:
			e.wake(game, p.x, p.y)
		return
	e.cooldown -= dt * float(game.sharpness)
	var mode := String(s["mode"])
	if e.stun > .5 and (mode == "aim" or mode == "spit"):
		# Knocked out of it (fightin' mad, a heavy hit): start over.
		s["mode"] = "roam"
		e.windup = 0.0
		e.aim_mark = null
		return
	match mode:
		"aim":
			e.windup = maxf(0.0, e.windup - dt)
			if e.windup > LOCK:
				s["heading"] = toward
			e.angle = float(s["heading"])
			e.face_left = cos(e.angle) < -.24
			e.aim_mark = [e.x + cos(e.angle) * 4.0, e.y + sin(e.angle) * 4.0, p.eye]
			if e.windup <= 0.0:
				s["mode"] = "charge"
				s["left"] = CHARGE_TIME
				s["hit"] = false
				e.aim_mark = null
				game.sound_at("millhand_rev", e.x, e.y, 1.0)
				game.burst(e.x, e.y, eye - .8, "dust", 10, 1.6)
		"charge":
			_charge(e, s, dt, game)
		"stall":
			if e.recovery <= 0.0:
				if int(s["again"]) > 0 and e.enraged:
					s["again"] = int(s["again"]) - 1
					_start_aim(e, s, game, .55)
				else:
					s["mode"] = "roam"
					e.cooldown = .9
		"spit":
			e.windup = maxf(0.0, e.windup - dt)
			if e.windup > LOCK:
				s["heading"] = toward
			e.angle = float(s["heading"])
			e.aim_mark = [p.x, p.y, p.eye]
			if e.windup <= 0.0:
				_spit(e, s, game)
		_:
			_roam(e, s, dt, game, distance, toward, sees)


static func _start_aim(e: Enemy, s: Dictionary, game, windup := -1.0) -> void:
	s["mode"] = "aim"
	e.windup = float(Enemy.WINDUP[e.kind][0]) * (.82 if e.enraged else 1.0)
	if windup > 0.0:
		e.windup = windup
	s["heading"] = atan2(game.player.y - e.y, game.player.x - e.x)
	e.aim_mark = [game.player.x, game.player.y, game.player.eye]
	game.sound_at(String(Enemy.WINDUP[e.kind][1]), e.x, e.y, .9)


static func _roam(
	e: Enemy, s: Dictionary, dt: float, game, distance: float, toward: float, sees: bool
) -> void:
	e.windup = 0.0
	e.aim_mark = null
	if e.stun > 0.0 or e.recovery > .1:
		return
	if sees and e.cooldown <= 0.0:
		e.attacks += 1
		if distance < 4.6 and e.attacks % 3 == 0:
			s["mode"] = "spit"
			e.windup = .7 if e.enraged else .85
			s["heading"] = toward
			e.aim_mark = [game.player.x, game.player.y, game.player.eye]
			game.sound_at("rat_hiss", e.x, e.y, .9)
		else:
			s["again"] = 1 if e.enraged else 0
			_start_aim(e, s, game)
		return
	if not sees and game.flow != null:
		var lead: float = game.flow.heading(e.x, e.y)
		if not is_nan(lead):
			e.follow(dt, game, lead, 1.4)
			return
	# Circle the player at a ramming distance, the way a car prowls.
	var swing := PI / 2.0 if int(game.clock / 3.0) % 2 == 0 else -PI / 2.0
	var want := toward
	if distance < 4.5:
		want = toward + PI + swing * .4
	elif distance < 8.0:
		want = toward + swing * .8
	e.follow(dt, game, want, 1.5 if e.enraged else 1.25)


static func _charge(e: Enemy, s: Dictionary, dt: float, game) -> void:
	var heading := float(s["heading"])
	var speed := MAD_SPEED if e.enraged else CHARGE_SPEED
	var p = game.player
	# The player in the way: run down and thrown off the lane.
	var px: float = p.x - e.x
	var py: float = p.y - e.y
	var ahead := px * cos(heading) + py * sin(heading)
	var side := absf(px * sin(heading) - py * cos(heading))
	if not bool(s["hit"]) and ahead > -.2 and ahead < e.radius + .7 and side < e.radius + .3:
		s["hit"] = true
		game.damage(MAD_RAM_DAMAGE if e.enraged else RAM_DAMAGE, [e.x, e.y], "RAMMED")
		var off := 1.0 if px * sin(heading) - py * cos(heading) < 0.0 else -1.0
		var throw_angle := heading + off * PI / 2.0
		game.move_actor(p, cos(throw_angle) * 1.1, sin(throw_angle) * 1.1, GameState.PLAYER_RADIUS)
		game.move_actor(p, cos(heading) * .5, sin(heading) * .5, GameState.PLAYER_RADIUS)
		game.shake = minf(1.0, game.shake + .8)
		game.sound_at("scenery_scrap", p.x, p.y, 1.0)
	# The county's own in the way get the same.
	for other: Enemy in game.enemies:
		if other == e or not other.alive or not other.hostile:
			continue
		var ox := other.x - e.x
		var oy := other.y - e.y
		var along := ox * cos(heading) + oy * sin(heading)
		if along > 0.0 and along < e.radius + other.radius + .4:
			if absf(ox * sin(heading) - oy * cos(heading)) < e.radius + other.radius:
				other.hurt(45.0, game, false, false, e)
				game.move_actor(
					other, cos(heading + PI / 2.0) * .9, sin(heading + PI / 2.0) * .9, other.radius
				)
	var want := speed * dt
	var moved := e.advance(dt, game, heading, speed / maxf(.1, e.speed))
	s["left"] = float(s["left"]) - dt
	if int(game.clock * 6.0) % 2 == 0:
		game.burst(
			e.x - cos(heading) * .9,
			e.y - sin(heading) * .9,
			game.world.stand(e) + .2,
			"dust",
			2,
			.9
		)
	if moved < want * .35:
		_crash(e, s, game, heading)
	elif float(s["left"]) <= 0.0:
		s["mode"] = "roam"
		e.cooldown = .8
		e.recovery = .35


## A charge that ends in a wall, a stack of tyres or a wreck.
static func _crash(e: Enemy, s: Dictionary, game, heading: float) -> void:
	s["mode"] = "stall"
	e.recovery = .7 if e.enraged else 1.35
	e.stun = maxf(e.stun, .2)
	var near := sqrt(pow(game.player.x - e.x, 2) + pow(game.player.y - e.y, 2))
	game.shake = minf(1.0, game.shake + maxf(0.0, .7 - near / 18.0))
	var fx := e.x + cos(heading) * (e.radius + .1)
	var fy := e.y + sin(heading) * (e.radius + .1)
	var floor_z: float = game.world.stand(e)
	game.burst(fx, fy, floor_z + .6, "spark", 18, 2.4)
	game.burst(fx, fy, floor_z + .4, "dust", 12, 1.8)
	game.sound_at("derby_champ_crash", fx, fy, 1.0)
	game.disturb(fx, fy, 6.0)
	# Into the pit crew's nitro or gas cans: they go up, on him as well.
	var pieces = game.features.get("breakables")
	if pieces != null:
		pieces.blast(fx, fy, floor_z + .4, 1.1, 50.0, false)
	if e.enraged:
		# The radiator goes, and parts come off him.
		game.add_hazard(
			"steam", e.x - cos(heading) * .2, e.y - sin(heading) * .2, 1.0, .25, 1.7, 10
		)
		game.sound_at("pressure_vent", e.x, e.y, .9)
		for k: float in [-1.0, 1.0]:
			var a := heading + PI + k * .7
			game.launch(
				e.x + cos(a) * (e.radius + .15),
				e.y + sin(a) * (e.radius + .15),
				floor_z + .31,
				a,
				4.6,
				"tire",
				0.0,
				true,
				10,
				1.1,
				e.get_instance_id()
			)


static func _spit(e: Enemy, s: Dictionary, game) -> void:
	var heading := float(s["heading"])
	var floor_z: float = game.world.stand(e)
	for off: float in _fan(e):
		var a := heading + off
		var sx := e.x + cos(a) * (e.radius + .15)
		var sy := e.y + sin(a) * (e.radius + .15)
		if not game.world.blocked(sx, sy, .05, floor_z + .31):
			game.launch(
				sx, sy, floor_z + .31, a, 6.0, "tire", 0.0, true, 12, 1.3, e.get_instance_id()
			)
	game.sound_at("bowling_hit", e.x, e.y, 1.0)
	e.recovery = .6
	e.cooldown = 1.5
	s["mode"] = "roam"
	e.aim_mark = null


static func _fan(e: Enemy) -> Array:
	return [-.42, -.21, 0.0, .21, .42] if e.enraged else [-.3, 0.0, .3]


## The windup's warning on the ground: the lane he will charge down, or the
## fan his tyres will roll along.
static func marks(e: Enemy, game) -> Array:
	var s := _state(e)
	var out: Array = []
	var mode := String(s["mode"])
	var lanes: Array = []
	if mode == "aim":
		lanes = [[float(s["heading"]), 16.0, e.radius]]
	elif mode == "spit":
		for off: float in _fan(e):
			lanes.append([float(s["heading"]) + off, 7.0, .2])
	var floor_z: float = game.world.stand(e) + .003
	for lane: Array in lanes:
		var bearing: float = lane[0]
		var length := 0.0
		while length < float(lane[1]):
			var step := length + .32
			if game.world.blocked(e.x + cos(bearing) * step, e.y + sin(bearing) * step, .03):
				break
			length = step
		if length > .6:
			out.append(
				Renderer.GroundMark.new(
					e.x + cos(bearing) * length / 2.0,
					e.y + sin(bearing) * length / 2.0,
					floor_z,
					bearing,
					length / 2.0,
					float(lane[2]),
					"mark_lane"
				)
			)
	return out


## The boss bar's word for what is coming.
static func tell(e: Enemy) -> String:
	var mode := String(_state(e)["mode"])
	if mode == "spit":
		return "SPARE TYRES"
	if mode == "stall":
		return "STALLED! LET HIM HAVE IT"
	return "RAMMING LANE"


## Down: the car goes up.
static func falls(e: Enemy, game) -> void:
	var floor_z: float = game.world.stand(e)
	game.explode(
		GameState.Shot.new(e.x, e.y, floor_z + .6, 0.0, 0.0, 0.0, "derby_blast", 0.0, true, 0)
	)
	game.burst(e.x, e.y, floor_z + 1.0, "spark", 24, 3.0)
	state.erase(e.get_instance_id())
