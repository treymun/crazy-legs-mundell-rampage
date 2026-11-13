## Port of game.py: shared player, combat, interaction and objective state.
##
## Everything the reference calls `world` is LevelData in the port (the JSON
## already carries the generated level), so `level` and `world` are the same
## object here.
class_name Game
extends GameView


## `p_host`: an authoritative host's game (game_host.gd), with no presentation.
func _init(p_art: Assets, p_hud: HUD, p_sound, level_id := "hickston", p_host := false) -> void:
	host = p_host
	gore_fx = Gore.new(self)
	art = p_art
	hud = p_hud
	sound = p_sound
	speaker = p_sound
	level = LevelData.load_level(level_id, art)
	world = level
	renderer = Renderer.new(art, level)
	# The sounds made in code (thunder alone is 30-odd ms of work) are made
	# while the level loads, not the moment one first plays.
	for cue: String in [] if host else Assets.MADE_CUES:
		art.cue(cue)
	# Player one (src/players.gd): the local and acting player.
	Players.join(self, float(level.spawn[0]), float(level.spawn[1]), float(level.spawn[2]))

	for i in level.enemies.size():
		var spec: Dictionary = level.enemies[i]
		enemy_ids.append(String(spec["id"]))
		var foe := Enemy.new(
			String(spec["kind"]), float(spec["x"]), float(spec["y"]), fmod(i * 2.3, TAU)
		)
		foe.uid = take_uid()
		foe.flank = .42 if i % 2 else -.42
		enemies.append(foe)
	var held := Triggers.held_back(level)
	for i in enemies.size():
		if held.has(enemy_ids[i]):
			enemies[i].dormant = true
	flow = FlowField.new(level)
	player.flow = flow
	route = FlowField.new(level, flow)
	route.budget = 1500
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
		add_pickup(String(ALIAS.get(name, name)), float(spec[1]), float(spec[2]))

	for point in level.fuel_drums:
		drums[Vector2(float(point[0]), float(point[1]))] = 18

	for door: LevelData.Door in level.doors:
		if door.secret:
			total_secrets += 1
	for station: LevelData.Station in level.stations:
		if station.reveals_secret:
			total_secrets += 1

	gallery = Gallery.new() if level_id == "fair" else null
	if gallery != null and level.gallery_stand != null:
		gallery.offset = level.gallery_stand - GALLERY_STAND
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
	Features.attach_all(self)
	message(level.introduction, 5.0)


## One step of the game (Game.tick of the reference): each player's controls,
## then the world once: doors, pickups, guns, enemies, shots and hazards.
## `controls` is one Controls for the local player (anyone else stands idle)
## or a Dictionary of slot -> Controls (src/players.gd). With one player this
## is the game as it always was, step for step and die for die.
func tick(dt: float, controls) -> void:
	var by_slot := Players.controls_by_slot(self, controls, _idle)
	if players.size() > 1:
		# The mode's say over what each player may do this tick (src/modes/).
		var mst = features.get("mode")
		if mst != null and mst.mode != Modes.CAMPAIGN:
			by_slot = mst.rules().hold_controls(self, mst, by_slot)
	var mine: Controls = by_slot[local_player.slot]
	if showing_tally or defeated() or portal_request != "":
		if sound != null:
			sound.set_fuse(false)
			sound.set_tool(false)
			sound.stop_voice()
		return
	shake = maxf(0.0, shake - dt * 1.7)
	if hitstop > 0.0:
		# The world holds still for a few hundredths after a kill; the aim does not.
		hitstop = maxf(0.0, hitstop - dt)
		for q: Player in players:
			var c: Controls = by_slot[q.slot]
			q.angle = fposmod(q.angle + c.turn, TAU)
			q.pitch = maxf(-53.0, minf(53.0, q.pitch + c.look))
		return
	if boss_hold > 0.0:
		# A boss's entrance: the world holds while the view comes round (boss_kit.gd).
		BossKit.hold(self, dt, mine)
		return
	# Slow motion as a boss falls: the world at SLOWMO_PACE, the player and gun not.
	var wdt := dt
	if slowmo > 0.0:
		slowmo = maxf(0.0, slowmo - dt)
		wdt = dt * SLOWMO_PACE
	clock += wdt
	spawn_grace = maxf(0.0, spawn_grace - dt)
	duck = maxf(0.0, duck - dt)
	if not host and sound != null and sound.has_method("level_music"):
		sound.level_music(
			sound.music_gain * (1.0 - .5 * minf(1.0, duck) - (.2 if barks.visible(self) else 0.0))
		)
	hurt_flash = maxf(0.0, hurt_flash - dt)
	blast_flash = maxf(0.0, blast_flash - dt)
	if players.size() > 1:
		_bucket_bodies()
	for q: Player in players:
		if q.health > 0:
			focus(q, true)
			_step_body(q, by_slot[q.slot], dt)
	body_cells_on = false
	focus(local_player)
	if in_hub:
		return
	for q: Player in players:
		if q.health > 0:
			focus(q, true)
			_discover(q)
	focus(local_player)
	world.update(wdt, players, enemies)
	for q: Player in players:
		if q.health > 0:
			focus(q, true)
			_step_hands(q, by_slot[q.slot], dt)
	focus(local_player)
	sound.set_fuse(armory.fuse != 0.0)
	sound.set_tool(
		(
			armory.active == Weapons.RIPSAW
			and mine.alt_fire
			and armory.grinding
			and not armory.holstered
			and armory.reload == 0.0
			and player.health > 0
		)
	)
	if players.size() == 1:
		player.flow.update(player.x, player.y, clock)
	else:
		# Walked when first needed (focus()): an enemy after them, a trigger...
		flow_walks.clear()
		for q: Player in players:
			q.flow_due = q.health > 0
	dangers.clear()
	for shot in shots:
		if shot.kind == "tnt":
			# The player's, or one a hand lobbed to flush them out (squad.gd).
			dangers.append(Vector3(shot.x, shot.y, 3.1))
	if players.size() == 1:
		for enemy: Enemy in enemies:
			enemy.tick(wdt, self)
	else:
		# Each enemy ticks with the player it is after acting (Players.hunted):
		# its sight, flow field, aim and blows are about them.
		for enemy: Enemy in enemies:
			if enemy.hp > 0.0 and not enemy.dormant:
				# Its pick stands RETARGET seconds (Players.hunted's first test,
				# written out), and focusing whoever is acting already is nothing.
				var keep: Player = enemy.hunted
				if keep == null or keep.health <= 0 or clock >= enemy.hunted_until:
					keep = Players.hunted(self, enemy)
				if keep != player or own_step or keep.flow_due:
					focus(keep)
			enemy.tick(wdt, self)
		focus(local_player)
		# Nobody needed theirs yet: walked now, so it is current after the tick
		# for whatever reads it (a bot after another player, the next tick).
		for q: Player in players:
			if q.flow_due:
				_walk_flow(q)
	update_shots(wdt)
	if not hazards.is_empty():
		update_hazards(wdt)
	if host:
		# Nobody to hear the county talk.
		ticked.emit(wdt)
		name_new()
		return
	var p := player
	var combat: bool = mine.fire or mine.alt_fire or hurt_flash > 0.0
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
	ticked.emit(wdt)
	name_new()


## The hostile bodies by cell, for every player's body this tick to look only
## round itself (move_actor) instead of over every enemy.
func _bucket_bodies() -> void:
	body_cells.clear()
	for enemy: Enemy in enemies:
		if enemy.hostile and enemy.alive:
			var key := Vector2i(floori(enemy.x), floori(enemy.y))
			if body_cells.has(key):
				body_cells[key].append(enemy)
			else:
				body_cells[key] = [enemy]
	body_cells_on = true


## Gives everything that came into being this tick (enemies, shots) its stable
## id, in list order: the same on every machine running the same ticks.
func name_new() -> void:
	# Enemies only ever join at the end: look from the last one named.
	var from := _named_enemies if _named_enemies <= enemies.size() else 0
	for i in range(from, enemies.size()):
		var enemy: Enemy = enemies[i]
		if enemy.uid == 0:
			enemy.uid = take_uid()
	_named_enemies = enemies.size()
	for shot in shots:
		if shot.uid == 0:
			shot.uid = take_uid()


## A player's body for one step: food and drink wearing off, the walk, the
## jump, the eye, the footsteps; and for the local player the room's sound,
## the place names and the automap's walked ground.
func _step_body(p: Player, controls: Controls, dt: float) -> void:
	var local := p == local_player
	p.gut = maxf(0.0, p.gut - dt * .40)
	p.drunk = maxf(0.0, p.drunk - dt * (2.4 if p.sprint else .77))
	p.sprint = maxf(0.0, p.sprint - dt)
	var intoxication := maxf(0.0, (p.drunk - 23.0) / 77.0)
	if p.gut >= 66.0 and clock >= p.next_belch:
		p.next_belch = clock + 5.6
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
	var speed: float = (
		(3.85 if controls.running else 2.75) * (1.42 if p.sprint else 1.0) / magnitude
	)
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
	if local and not host:
		# The gun's weight, its kick and the view's jolts: features/feel.gd.
		feel_turn = controls.turn
		feel_landed = landed
		_surroundings(p, roof)
	var step := int(p.walk_phase / PI)
	if landed or step != p.step_number:
		var surface: String = world.surface_sound(int(world.floor_tile[world.cell(p.x, p.y)]))
		sound.play(
			"step_%s_%d" % [surface, step % 2], .77 if landed else .31 if controls.crouch else .55
		)
		if surface == "water":
			burst(p.x, p.y, ground + .16, "splash", 5 if landed else 3, .52)
		p.step_number = step
	if local and not host:
		visited[Vector2i(int(p.x), int(p.y))] = true


## The local player's surroundings: the room's sound and reverb, the jukebox's
## radio, the place name, and the distant sounds of the level.
func _surroundings(p: Player, roof: float) -> void:
	var area := int(world.area[world.cell(p.x, p.y)])
	var ambience := level.ambience
	if (
		ambience == "mill"
		and (
			stations_done.has("relay")
			or (roof == 0.0 and Vector2(p.x, p.y).distance_to(_relay_at()) > 13.0)
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
	elif ambience == "bayou":
		ambience = (
			"bayou_after"
			if stations_done.has("fuel")
			else "bayou_shack" if roof != 0.0 else "bayou"
		)
		if not art.has_cue("amb_" + ambience):
			# Until the bayou's own beds are made: the plain yard and room.
			ambience = ""
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
	var area_sound := String(level.area_sounds.get(area, ""))
	if room == "":
		room = area_sound if area_sound != "" else "room" if roof != 0.0 else "yard"
	sound.set_room(room)
	# The reverb follows the space: under a roof a room, a barn or the long
	# quarry line and mill floor; outside the open air or the creek bed.
	var space := "open"
	if roof != 0.0:
		space = (
			"barn"
			if area_sound == "barn"
			else "hall" if ambience in ["quarry_line", "mill", "mothership"] else "room"
		)
	elif area_sound == "creek":
		space = "creek"
	sound.set_space(space)
	if clock >= radio_check:
		radio_check = clock + .045
		var radio: Array = []
		for device: Array in level.devices:
			if device[0] == "jukebox":
				radio = device
		if (
			jukebox_on
			and not radio.is_empty()
			and Vector2(p.x - float(radio[1]), p.y - float(radio[2])).length() < 11.0
		):
			var place := sound_position(float(radio[1]), float(radio[2]), .60)
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
					or (cue == "distant_bayou_airboat" and stations_done.has("fuel"))
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
		elif level.area_cues.has(area) and roof == 0.0:
			sound.play(String(level.area_cues[area]), .24, .7 if int(clock) % 2 else -.64)


## Rooms that open their secret door once the player walks in.
func _discover(p: Player) -> void:
	var ix := int(p.x)
	var iy := int(p.y)
	for point: Vector2i in world.discovery_rooms:
		var span: Array = world.discovery_rooms[point]
		if int(span[0]) <= ix and ix <= int(span[2]) and int(span[1]) <= iy and iy <= int(span[3]):
			for door: LevelData.Door in world.doors:
				if door.x == point.x and door.y == point.y:
					if not door.discovered:
						toggle_door(door, true)
					break


## A player's hands for one step: what their controls use or take up (a
## player played by controls; the local front end calls these between
## ticks), the pickups at their feet, their gun and the tin rooster booth.
func _step_hands(p: Player, controls: Controls, dt: float) -> void:
	if controls.weapon >= 0:
		armory.select(controls.weapon, self)
	if controls.cycle != 0:
		armory.cycle(controls.cycle, self)
	if controls.item >= 0:
		use_item(controls.item)
	if controls.use and not p.use_held:
		interact()
	p.use_held = controls.use
	p.holding = controls.use or controls.hold
	# reaches_pickup()'s first test written out: most ticks nothing is near.
	var near := false
	for entry in pickups:
		var gx: float = float(entry[1]) - p.x
		var gy: float = float(entry[2]) - p.y
		if gx * gx + gy * gy < .62 * .62:
			near = true
			break
	if near:
		var remaining: Array = []
		for entry in pickups:
			if not reaches_pickup(entry) or not collect(String(entry[0])):
				remaining.append(entry)
		pickups = remaining
	armory.tick(dt, self)
	# A scoped gun's ALT FIRE puts the scope up and down instead of firing;
	# a reload or another gun takes it down.
	var alt: bool = controls.alt_fire
	if Weapons.FIRING[armory.active].has("scope"):
		if alt and not p.alt_held and armory.reload <= 0.0:
			p.scoped = not p.scoped
		if armory.reload > 0.0 or armory.switch > 0.0:
			p.scoped = false
		p.alt_held = alt
		alt = false
	else:
		p.scoped = false
		p.alt_held = alt
	if gallery != null and gallery.active and gallery.slot == p.slot:
		gallery.tick(dt, self, controls.fire or alt)
	elif controls.fire or alt:
		armory.fire(self, alt)
	else:
		armory.release_dynamite(self)

# --------------------------------------------------------------- reflection
