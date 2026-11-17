## How a hand attacks, moved out of enemies.gd: its swing or shot when it
## strikes (attack(): the level's own brains first, then the kind's), its
## signature move, the special attacks (spit, boilers, saws...) and the
## pasture bosses' volleys. Line-for-line the methods they were, so the same
## seeded rng calls happen in the same order. Enemy.attack() and
## Enemy.special_attack() hand on to these.
class_name EnemyAttacks
extends RefCounted


static func attack(
	e: Enemy, game: GameCombat, direction: float, distance: float, eye: float, aim_z: Variant = null
) -> void:
	e.attacks += 1
	if SpeedwayHands.attack(e, game as Game, direction, distance, eye, aim_z):
		return
	if MoonshineHands.attack(e, game as Game, direction, distance, eye, aim_z):
		return
	if BayouBrains.attack(e, game as Game, direction, distance, eye):
		return
	if ShipAliens.attack(e, game as Game, direction, distance, eye, aim_z):
		return
	if Variants.attack(e, game as Game, direction, distance, eye):
		return
	if Enemy.SIGNATURES.has(e.kind):
		signature_attack(e, game, direction, distance, eye, aim_z)
		return
	if e.brain == "boilerback" or e.brain == "chalk_spitter" or Enemy.TELLS.has(e.kind):
		special_attack(e, game, direction, distance, eye, aim_z)
		return
	if Enemy.LUNGES.has(e.kind):
		var lunge: Array = Enemy.LUNGES[e.kind]
		var p: Player = game.player
		var aim := atan2(p.y - e.y, p.x - e.x)
		var swing := e.brain == "skeeter" or absf(Enemy.angle_delta(aim, direction)) < .61
		var reach: float = lunge[2]
		if (
			swing
			and sqrt(pow(p.x - e.x, 2) + pow(p.y - e.y, 2)) < reach
			and game.world.visible(e.x, e.y, p.x, p.y, eye, p.eye)
		):
			var hit: int = lunge[3]
			game.damage(hit, [e.x, e.y], "STRIKE")
			game.sound_at(str(lunge[4]), e.x, e.y)
		e.cooldown = lunge[5]
		return
	if Enemy.RANGED.has(e.kind):
		fire_projectiles(e, game, direction, distance, eye, aim_z)
		return

	var chance := 0.0
	var damage := 0
	var cue := ""
	var delay := 0.0
	if e.brain == "billy":
		chance = maxf(.24, .88 - distance * .104)
		damage = 14 if distance < 2.4 else 8
		cue = "enemy_scatter"
		delay = 1.45
	elif e.brain == "coot":
		chance = maxf(.34, .83 - distance * .060)
		damage = 7
		cue = "enemy_pistol"
		delay = 1.58
	else:
		chance = maxf(.39, 1.0 - distance * .115)
		damage = 7 if distance > 2.0 else 10
		cue = "enemy"
		delay = 1.36 if e.attacks % 2 else 1.77
	e.cooldown = delay + game.rng.uniform(.04, .33)
	game.sound_at(cue, e.x, e.y, .90)
	game.burst(
		e.x + cos(direction) * e.radius, e.y + sin(direction) * e.radius, eye, "spark", 3, 1.2
	)
	var p2: Player = game.player
	var miss := absf(Enemy.angle_delta(atan2(p2.y - e.y, p2.x - e.x), direction))
	var fan := .23 if e.brain == "billy" else .11 if e.brain == "coot" else .15
	# One of their own between them and the player takes it instead.
	var in_way: Enemy = null
	var nearest := distance
	for other: Enemy in game.enemies:
		if other == e or not other.alive or not other.hostile:
			continue
		var ox: float = other.x - e.x
		var oy: float = other.y - e.y
		var along := ox * cos(direction) + oy * sin(direction)
		if along > .3 and along < nearest:
			if absf(ox * sin(direction) - oy * cos(direction)) < other.radius + .06:
				nearest = along
				in_way = other
	if in_way != null:
		if game.rng.random() < maxf(.35, chance):
			in_way.hurt(float(damage), game, false, false, e)
		return
	chance *= (.79 if p2.crouched else 1.0) * maxf(0.0, 1.0 - miss / fan * .60)
	chance = minf(.97, chance * float(game.sharpness))
	if miss < fan and game.rng.random() < chance:
		game.damage(damage, [e.x, e.y], "FIRE")


static func signature_attack(
	e: Enemy, game: GameCombat, direction: float, distance: float, eye: float, aim_z: Variant
) -> void:
	var p: Player = game.player
	var spec: Array = Enemy.SIGNATURES[e.kind]
	e.cooldown = spec[4]
	game.sound_at(str(spec[6]), e.x, e.y, .9)
	var def: Dictionary = Enemy.DEFS[e.kind]
	var sx := e.x + cos(direction) * .34
	var sy := e.y + sin(direction) * .34
	if game.world.blocked(sx, sy, .045, eye):
		return
	if e.brain == "yard_deputy":
		var aim_target: float = p.eye if aim_z == null else aim_z
		var slope := (aim_target - eye) * 8.4 / maxf(distance - .34, .6)
		game.launch(sx, sy, eye, direction - .023, 8.4, "deputy_slug", slope, true, 8, 1.08)
		e.volley = 1
		e.volley_timer = .23
		e.volley_angle = direction
		e.volley_slope = slope
	elif e.brain == "bottle_tosser":
		var flight := minf(1.32, maxf(.48, distance / 6.1))
		var speed2 := maxf(.45, (distance - .34) / flight)
		var mark: Array = e.aim_mark if e.aim_mark != null else [p.x, p.y]
		var mark_x: float = mark[0]
		var mark_y: float = mark[1]
		var target_z: float = game.world.elevation(mark_x, mark_y)
		game.launch(
			sx,
			sy,
			eye,
			direction,
			speed2,
			str(def.get("shot", "fair_bottle")),
			(target_z + .06 - eye) / flight + 2.75 * flight,
			true,
			0,
			flight
		)
	elif e.brain == "chain_hand":
		for swing: float in [-.19, 0.0, .19]:
			game.launch(sx, sy, eye - .12, direction + swing, 8.0, "chain_hook", 0.0, true, 7, .44)
	else:
		var ground_z: float = game.world.stand(e)
		var slug := str(def.get("shot", "valve_slug"))
		game.launch(sx, sy, ground_z + .31, direction, 6.3, slug, 0.0, true, 12, 1.17)


static func special_attack(
	e: Enemy, game: GameCombat, direction: float, distance: float, eye: float, aim_z: Variant
) -> void:
	var p: Player = game.player
	if e.brain == "chalk_spitter":
		var flight := minf(1.25, maxf(.51, distance / 6.15))
		var speed2 := maxf(.5, (distance - .18) / flight)
		var mark: Array = e.aim_mark if e.aim_mark != null else [p.x, p.y]
		var mark_x: float = mark[0]
		var mark_y: float = mark[1]
		var target_z: float = game.world.elevation(mark_x, mark_y)
		game.launch(
			e.x,
			e.y,
			eye,
			direction,
			speed2,
			"chalk_lob",
			(target_z + .07 - eye) / flight + 2.1 * flight,
			true,
			0,
			flight
		)
		e.cooldown = 1.88
		game.sound_at("chalk_spit", e.x, e.y)
	elif e.brain == "rudy":
		e.volley = 8 if e.enraged else 5
		e.volley_timer = .02
		e.volley_angle = direction if e.attacks % 2 else direction + .095
		var aim_target: float = p.eye if aim_z == null else aim_z
		e.volley_slope = (aim_target - eye) * 6.8 / maxf(1.0, distance)
		e.cooldown = (1.42 if e.attacks % 2 else 1.73) * (.8 if e.enraged else 1.0)
		game.sound_at("rudy_horn", e.x, e.y)
	elif e.brain == "foreman":
		for lane: Array in e.saw_lanes(direction):
			var lane_x: float = lane[0]
			var lane_y: float = lane[1]
			var lane_at: float = lane[2]
			if not game.world.blocked(lane_x, lane_y, .04):
				game.launch(
					lane_x,
					lane_y,
					game.world.elevation(lane_x, lane_y) + .58,
					lane_at,
					7.6,
					"foreman_cut",
					0.0,
					true,
					13,
					1.38
				)
		e.cooldown = 1.69 * (.85 if e.enraged else 1.0)
		game.sound_at("foreman_cut", e.x, e.y)
	elif e.brain == "baron" and BaronMoves.outlets_next(e.attacks - 1, e.enraged):
		var ports: Array = game.pressure_ports(e.attacks - 1)
		var relieved: bool = game.relief_open()
		# pressure_ports() hands back the level's Vector2 points, not [x, y] pairs.
		for point: Vector2 in ports:
			game.add_hazard("steam", point.x, point.y, .94, .69, 1.08 if relieved else 1.35, 15)
			game.sound_at("pressure_vent", point.x, point.y, .76)
		e.cooldown = (1.95 if relieved else 1.58) * (.8 if e.enraged else 1.0)
	else:
		var rad := 4.45 if e.brain == "boilerback" else 5.45
		for spread: float in [-.23, 0.0, .23]:
			var sx := e.x + cos(direction + spread) * .72
			var sy := e.y + sin(direction + spread) * .72
			if not game.world.blocked(sx, sy, .04):
				game.burst(sx, sy, eye - .20, "dust", 6, 1.45)
		var aim := atan2(p.y - e.y, p.x - e.x)
		if (
			sqrt(pow(p.x - e.x, 2) + pow(p.y - e.y, 2)) < rad
			and absf(Enemy.angle_delta(aim, direction)) < .47
			and game.world.visible(e.x, e.y, p.x, p.y, eye, p.eye)
		):
			game.damage(15 if e.brain == "boilerback" else 18, [e.x, e.y], "STEAM")
		e.cooldown = 1.60
		game.sound_at("boiler_release", e.x, e.y)


static func fire_projectiles(
	e: Enemy, game: GameCombat, direction: float, distance: float, eye: float, aim_z: Variant
) -> void:
	var football := e.brain == "jerry"
	var kind_name := "football" if football else "plasma"
	var spread := .15
	var count := 1
	var speed2 := 0.0
	var damage := 0
	if football:
		count = 3 if e.hp < e.max_hp / 2.0 else 1
		speed2 = 7.1
		damage = 13
		e.cooldown = 1.02 if count == 3 else 1.32
	elif e.brain == "boss":
		count = 3 if e.hp < e.max_hp / 2.0 else 1
		speed2 = 5.7
		damage = 13
		e.cooldown = 1.28
	elif e.brain == "saucer":
		count = 2
		speed2 = 3.7
		damage = 8
		e.cooldown = 1.74
	elif e.brain == "barker":
		count = 3
		speed2 = 4.7
		damage = 8
		spread = .27
		e.cooldown = 1.70
		kind_name = "barker_bolt"
	elif e.brain == "lantern":
		count = 2
		speed2 = 4.15
		damage = 9
		spread = .12
		e.cooldown = 1.52
		kind_name = "lantern_bolt"
		var aim_at: float = game.player.eye if aim_z == null else aim_z
		aim_z = aim_at - .37
	else:
		count = 1
		speed2 = 4.4
		damage = 9
		e.cooldown = .99 if e.attacks % 2 else 1.84
	for i in count:
		var theta := direction + (i - (count - 1) / 2.0) * spread
		var dx := cos(theta) * (e.radius + .055)
		var dy := sin(theta) * (e.radius + .055)
		var t := maxf(.12, distance / speed2)
		var aim_target: float = game.player.eye if aim_z == null else aim_z
		var lift := (aim_target - eye) / t + (1.2 * t if football else 0.0)
		game.launch(
			e.x + dx,
			e.y + dy,
			eye,
			theta,
			speed2,
			kind_name,
			lift,
			true,
			damage,
			-1.0,
			e.get_instance_id()
		)
	var cue: String = (
		{
			"jerry": "football_throw",
			"saucer": "saucer_shot",
			"boss": "sheriff_shot",
			"barker": "barker_blast",
			"lantern": "lantern_spit"
		}
		. get(e.kind, "plasma")
	)
	game.sound_at(cue, e.x, e.y)
