## Port of game.py: shared player, combat, interaction and objective state.
##
## Everything the reference calls `world` is LevelData in the port (the JSON
## already carries the generated level), so `level` and `world` are the same
## object here.
class_name Game
extends GameView


func _init(p_art: Assets, p_hud: HUD, p_sound, level_id := "hickston") -> void:
	gore_fx = Gore.new(self)
	art = p_art
	hud = p_hud
	sound = p_sound
	level = LevelData.load_level(level_id, art)
	world = level
	renderer = Renderer.new(art, level)
	player = Player.new(float(level.spawn[0]), float(level.spawn[1]), float(level.spawn[2]))
	player.eye += world.elevation(player.x, player.y)
	armory = Weapons.Armory.new()

	for i in level.enemies.size():
		var spec: Dictionary = level.enemies[i]
		enemy_ids.append(String(spec["id"]))
		var foe := Enemy.new(
			String(spec["kind"]), float(spec["x"]), float(spec["y"]), fmod(i * 2.3, TAU)
		)
		foe.flank = .42 if i % 2 else -.42
		enemies.append(foe)
	var held := Triggers.held_back(level)
	for i in enemies.size():
		if held.has(enemy_ids[i]):
			enemies[i].dormant = true
	flow = FlowField.new(level)
	route = FlowField.new(level, flow)
	route.reach = 100000
	route.doors_open = true
	route.keys = keys
	var by_id := {}
	for i in enemy_ids.size():
		by_id[enemy_ids[i]] = enemies[i]
	for pair in level.partners:
		if by_id.has(String(pair[0])) and by_id.has(String(pair[1])):
			partners[by_id[pair[0]].get_instance_id()] = [by_id[pair[1]], int(pair[2])]
	for key in level.patrols:
		var index := int(key)
		if index < 0 or index >= enemies.size():
			continue
		var enemy: Enemy = enemies[index]
		var route: Array = level.patrols[key]
		enemy.route = route
		enemy.patrol_pause = .32 + fmod(index * .73, 1.85)
		if not route.is_empty():
			enemy.angle = atan2(float(route[0][1]) - enemy.y, float(route[0][0]) - enemy.x)
	for index in level.reinforcements:
		if int(index) >= 0 and int(index) < enemies.size():
			wave.append(enemies[int(index)])
	for enemy: Enemy in wave:
		enemy.dormant = true
	for enemy: Enemy in wave:
		if Enemy.TELLS.has(enemy.kind):
			finale = enemy
			break
	if level.rescue:
		enemies[0].angle = PI * .58
		for enemy: Enemy in enemies:
			if enemy.brain == "boss" and boss == null:
				boss = enemy
			elif enemy.brain == "jerry" and jerry == null:
				jerry = enemy
			elif enemy.brain == "bessie" and bessie == null:
				bessie = enemy
		if boss != null:
			boss.angle = PI * .49
		if jerry != null:
			jerry.dormant = true

	for spec in level.props:
		var name := String(spec[0])
		var x := float(spec[1])
		var y := float(spec[2])
		var idx := int(y) * level.width + int(x)
		var z := world.elevation(x, y)
		if name == "lamp":
			z = level.roof[idx] - .25
		var spr := Renderer.Sprite.new(
			x,
			y,
			"prop_" + name + ("_0" if name == "windmill" else ""),
			float(PROP_HEIGHTS[name]),
			z
		)
		spr.glow = name == "lamp"
		if name == "roadsign" or name == "bleacher_sign":
			spr.plane = 0.0
		props.append(spr)

	for spec in level.pickups:
		var name := String(spec[0])
		pickups.append([String(ALIAS.get(name, name)), float(spec[1]), float(spec[2])])

	for point in level.fuel_drums:
		drums[Vector2(float(point[0]), float(point[1]))] = 18

	for name in HUD.ITEMS:
		inventory[name] = 0
	inventory["rinds"] = 1
	inventory_slot = 0

	for door: LevelData.Door in level.doors:
		if door.secret:
			total_secrets += 1
	for station: LevelData.Station in level.stations:
		if station.reveals_secret:
			total_secrets += 1

	gallery = Gallery.new() if level_id == "fair" else null
	exchanges = [] if in_hub else level.exchanges

	entry = loadout()
	rng = Rng.new(1997)
	barks = Barks.new()
	cheats = Cheats.new()
	total_kills = 0
	for enemy: Enemy in enemies:
		if enemy.hostile:
			total_kills += 1
	district = int(level.area[int(player.y) * level.width + int(player.x)])
	configure({})
	_build_grit()
	message(level.introduction, 5.0)


## Mirrors Game.tick: player physics, ambience, pickups, combat and hazards.
func tick(dt: float, controls) -> void:
	var p := player
	if showing_tally or p.health <= 0 or portal_request != "":
		if sound != null:
			sound.set_fuse(false)
			sound.set_tool(false)
			sound.stop_voice()
		return
	shake = maxf(0.0, shake - dt * 1.7)
	if hitstop > 0.0:
		# The world holds still for a few hundredths after a kill; the aim does not.
		hitstop = maxf(0.0, hitstop - dt)
		p.angle = fposmod(p.angle + controls.turn, TAU)
		p.pitch = maxf(-53.0, minf(53.0, p.pitch + controls.look))
		return
	clock += dt
	spawn_grace = maxf(0.0, spawn_grace - dt)
	duck = maxf(0.0, duck - dt)
	if sound != null and sound.has_method("level_music"):
		sound.level_music(
			sound.music_gain * (1.0 - .5 * minf(1.0, duck) - (.2 if barks.visible(self) else 0.0))
		)
	hurt_flash = maxf(0.0, hurt_flash - dt)
	blast_flash = maxf(0.0, blast_flash - dt)
	p.gut = maxf(0.0, p.gut - dt * .40)
	p.drunk = maxf(0.0, p.drunk - dt * (2.4 if sprint else .77))
	sprint = maxf(0.0, sprint - dt)
	var intoxication := maxf(0.0, (p.drunk - 23.0) / 77.0)
	if p.gut >= 66.0 and clock >= next_belch:
		next_belch = clock + 5.6
		sound.play("belch", .76)
		wake_nearby(5.7, p.x, p.y)
	if p.drunk > 62.0:
		barks.say(self, "drunk")
	p.sway = sin(clock * 3.15) * intoxication * 11.0
	p.drift = sin(clock * 2.3) * pow(intoxication, 2.0) * .12
	p.angle = fposmod(p.angle + controls.turn, TAU)
	p.pitch = maxf(-53.0, minf(53.0, p.pitch + controls.look))
	var forward: float = controls.forward
	var strafe: float = controls.strafe + (sin(clock * 4.0) * .39 if p.drunk > 82.0 else 0.0)
	var magnitude := maxf(1.0, sqrt(forward * forward + strafe * strafe))
	var speed: float = (3.85 if controls.running else 2.75) * (1.42 if sprint else 1.0) / magnitude
	speed *= 1.0 - maxf(0.0, p.gut - 65.0) * .004 - maxf(0.0, p.drunk - 70.0) * .004
	if world.surface_sound(int(world.floor_tile[world.cell(p.x, p.y)])) == "water":
		speed *= .69
	p.crouched = controls.crouch and p.air <= .01
	if p.crouched:
		speed *= .51
	var vx := cos(p.view_angle())
	var vy := sin(p.view_angle())
	var ox := p.x
	var oy := p.y
	var response := (
		1.0 - exp(-dt * (7.0 if p.air else 23.0 if forward != 0.0 or strafe != 0.0 else 30.0))
	)
	p.vx += (speed * (forward * vx - strafe * vy) - p.vx) * response
	p.vy += (speed * (forward * vy + strafe * vx) - p.vy) * response
	move_actor(p, p.vx * dt, p.vy * dt, PLAYER_RADIUS)
	if p.x == ox and absf(p.vx) > .02:
		p.vx = 0.0
	if p.y == oy and absf(p.vy) > .02:
		p.vy = 0.0
	if controls.jump and not p.jump_held and p.air == 0.0 and not controls.crouch:
		p.vertical_speed = 2.7
	p.jump_held = controls.jump
	var landed := false
	if p.air > 0.0 or p.vertical_speed > 0.0:
		p.air = maxf(0.0, p.air + p.vertical_speed * dt)
		p.vertical_speed -= dt * 9.2
		if p.air == 0.0:
			p.vertical_speed = 0.0
			landed = true
	var ground: float = world.elevation(p.x, p.y)
	var eye := (.68 if p.crouched else .95) + ground + p.air
	var roof: float = world.roof[world.cell(p.x, p.y)]
	if roof != 0.0 and eye > roof - .22:
		eye = roof - .22
		p.vertical_speed = minf(0.0, p.vertical_speed)
	p.eye += (eye - p.eye) * minf(1.0, dt * 17.0)
	p.motion = minf(
		1.0, sqrt((p.x - ox) * (p.x - ox) + (p.y - oy) * (p.y - oy)) / maxf(dt * 2.0, .0001)
	)
	if p.air == 0.0:
		p.walk_phase += (
			dt * 11.0 * p.motion * (1.25 if controls.running else .80 if p.crouched else 1.0)
		)
	p.bob = sin(p.walk_phase * 2.0) * p.motion * (0.0 if p.air else 1.9) * bob_scale
	var iy := int(p.y)
	var ix := int(p.x)
	var area := int(world.area[world.cell(p.x, p.y)])
	var ambience := level.ambience
	if (
		ambience == "mill"
		and (
			stations_done.has("relay")
			or (
				roof == 0.0 and sqrt((p.x - 24.3) * (p.x - 24.3) + (p.y - 6.7) * (p.y - 6.7)) > 13.0
			)
		)
	):
		ambience = "mill_bank"
	elif ambience == "quarry":
		ambience = (
			"quarry_after"
			if stations_done.has("bottling")
			else "quarry_line" if roof != 0.0 else "quarry"
		)
	elif ambience == "fair" and stations_done.has("broadcast"):
		ambience = "fair_after"
	var recovery = level.recovery_room
	if recovery != null and ambience != "quarry_after" and ambience != "fair_after":
		if (
			float(recovery[0]) <= p.x
			and p.x <= float(recovery[2])
			and float(recovery[1]) <= p.y
			and p.y <= float(recovery[3])
		):
			ambience = String(recovery[4])
	var room: String = ambience
	if room == "":
		room = "creek" if area == 9 else "barn" if area == 4 else "room" if roof != 0.0 else "yard"
	sound.set_room(room)
	# The reverb follows the space: under a roof a room, a barn or the long
	# quarry line and mill floor; outside the open air or the creek bed.
	var space := "open"
	if roof != 0.0:
		space = (
			"barn"
			if area == 4
			else "hall" if ambience == "quarry_line" or ambience == "mill" else "room"
		)
	elif area == 9:
		space = "creek"
	sound.set_space(space)
	if clock >= radio_check:
		radio_check = clock + .045
		if (
			level.rescue
			and jukebox_on
			and sqrt((p.x - 7.26) * (p.x - 7.26) + (p.y - 17.14) * (p.y - 17.14)) < 11.0
		):
			var place := sound_position(7.26, 17.14, .60)
			sound.set_radio(true, place.x, place.y)
		else:
			sound.set_radio(false)
	if area != district and p.motion > .15:
		district = area
		district_until = clock + 2.1
	if clock >= amb_clock:
		amb_clock = clock + 5.9
		if not world.distant_cues.is_empty():
			for cue_row in world.distant_cues:
				var cx: float = cue_row[0]
				var cy: float = cue_row[1]
				var cue := String(cue_row[2])
				if sqrt((p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy)) >= 10.0:
					continue
				if (
					(cue == "distant_mill_pump" and stations_done.has("relay"))
					or (
						cue in ["distant_quarry_bottler", "distant_quarry_pipe"]
						and stations_done.has("bottling")
					)
					or (
						cue in ["distant_fair_motif", "distant_fair_generator"]
						and stations_done.has("broadcast")
					)
				):
					continue
				if cue == "distant_fair_pa":
					if (
						stations_done.has("broadcast")
						or sqrt((p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy)) > 5.0
						or not world.visible(p.x, p.y, cx, cy)
						or clock < message_until
					):
						continue
					message("PA: WINNERS MUST FEED THEIR PRIZES.", 3.5)
				sound_at(cue, cx, cy, .55)
		elif level.rescue and area in [0, 5, 8, 9, 10] and roof == 0.0:
			var cue2 := "distant_dog" if area in [0, 8] else "distant_crow"
			sound.play(cue2, .24, .7 if int(clock) % 2 else -.64)
	var step := int(p.walk_phase / PI)
	if landed or step != step_number:
		var surface: String = world.surface_sound(int(world.floor_tile[world.cell(p.x, p.y)]))
		sound.play(
			"step_%s_%d" % [surface, step % 2], .77 if landed else .31 if controls.crouch else .55
		)
		if surface == "water":
			burst(p.x, p.y, ground + .16, "splash", 5 if landed else 3, .52)
		step_number = step
	visited[Vector2i(ix, iy)] = true
	if in_hub:
		return
	for point: Vector2i in world.discovery_rooms:
		var span: Array = world.discovery_rooms[point]
		if int(span[0]) <= ix and ix <= int(span[2]) and int(span[1]) <= iy and iy <= int(span[3]):
			for door: LevelData.Door in world.doors:
				if door.x == point.x and door.y == point.y:
					if not door.discovered:
						toggle_door(door, true)
					break
	world.update(dt, p, enemies)
	var remaining: Array = []
	for entry in pickups:
		var name := String(entry[0])
		var x := float(entry[1])
		var y := float(entry[2])
		if (
			(p.x - x) * (p.x - x) + (p.y - y) * (p.y - y) >= .43 * .43
			or not world.visible(p.x, p.y, x, y)
			or not collect(name)
		):
			remaining.append(entry)
	pickups = remaining
	armory.tick(dt, self)
	if gallery != null and gallery.active:
		gallery.tick(dt, self, controls.fire or controls.alt_fire)
	elif controls.fire or controls.alt_fire:
		armory.fire(self, controls.alt_fire)
	else:
		armory.release_dynamite(self)
	sound.set_fuse(armory.fuse != 0.0)
	sound.set_tool(
		(
			armory.active == Weapons.RIPSAW
			and controls.alt_fire
			and armory.grinding
			and not armory.holstered
			and armory.reload == 0.0
			and p.health > 0
		)
	)
	flow.update(p.x, p.y, clock)
	dangers.clear()
	for shot in shots:
		if shot.kind == "tnt" and not shot.enemy:
			dangers.append(Vector3(shot.x, shot.y, 3.1))
	for enemy: Enemy in enemies:
		enemy.tick(dt, self)
	update_shots(dt)
	if not hazards.is_empty():
		update_hazards(dt)
	var combat: bool = controls.fire or controls.alt_fire or hurt_flash > 0.0
	if not combat:
		for enemy: Enemy in enemies:
			if (
				enemy.alive
				and enemy.hostile
				and (enemy.windup > 0.0 or enemy.recovery > 0.0)
				and absf(enemy.x - p.x) < 6.0
				and absf(enemy.y - p.y) < 6.0
			):
				combat = true
				break
	tick_exchanges(combat)
	Triggers.tick(self)
	if not trigger_lights.is_empty():
		trigger_lights = trigger_lights.filter(func(l: Array) -> bool: return clock < float(l[6]))
	Lessons.tick(self)

# --------------------------------------------------------------- reflection
