## Messages, sound, damage, pickups, waves, doors, stations, the use key and
## the objective (the game layers are listed in game_state.gd).
class_name GameWorld
extends GameState

# --------------------------------------------------------------- loadout


func loadout() -> Dictionary:
	return {
		"health": player.health,
		"owned": armory.owned.duplicate(),
		"loaded": armory.loaded.duplicate(),
		"reserve": armory.reserve.duplicate(),
		"active": armory.active,
		"inventory": inventory.duplicate(),
		"slot": inventory_slot
	}


func apply_loadout(kit: Dictionary) -> void:
	player.health = int(kit["health"])
	var owned: Array = kit["owned"]
	var loaded: Array = kit["loaded"]
	var reserve: Array = kit["reserve"]
	for i in mini(Weapons.COUNT, owned.size()):
		armory.owned[i] = bool(owned[i])
		armory.loaded[i] = int(loaded[i])
		armory.reserve[i] = int(reserve[i])
	armory.active = int(kit["active"])
	inventory = kit["inventory"].duplicate()
	inventory_slot = int(kit["slot"])


func result() -> Array:
	return [level.id, kills, total_kills, secrets, total_secrets, int(clock)]


func configure(options: Dictionary) -> void:
	difficulty = clampi(int(options.get("difficulty", 1)), 0, 3)
	incoming = [0.66, 1.0, 1.34, 1.65][difficulty]
	sharpness = [.88, 1.0, 1.18, 1.36][difficulty]
	ammo_scale = [1.0, 1.0, .75, .55][difficulty]
	bob_scale = float(options.get("bob", 100)) / 100.0
	flash_scale = [1.0, .32, 0.0][clampi(int(options.get("flashes", 0)), 0, 2)]
	gore = bool(options.get("gore", 1))
	aim_assist = int(options.get("aim_assist", 0))
	hit_feedback = bool(options.get("hit_feedback", 1))
	adaptive = bool(options.get("adaptive", 1))
	Renderer.base_focal = Renderer.FOCAL_FOR[clampi(int(options.get("fov", 0)), 0, 3)]
	shake_scale = [0.0, .5, 1.0][clampi(int(options.get("shake", 2)), 0, 2)]
	district_labels = bool(options.get("district_labels", 1))
	hints = bool(options.get("hints", 1))
	hud_style = int(options.get("hud_style", 0))
	crosshair_tint = [
		Color8(188, 168, 132),
		Color8(251, 183, 98),
		Color8(160, 236, 92),
		Color8(240, 64, 48),
		Color8(255, 255, 255)
	][clampi(int(options.get("crosshair_color", 0)), 0, 4)]
	renderer.world_motion = int(options.get("world_motion", 0))
	weapon_view = int(options.get("weapon_view", 0))
	voice_captions = bool(options.get("voice_captions", 1))
	bullet_marks = bool(options.get("bullet_marks", 1))
	retro_look = bool(options.get("film_look", 0))
	renderer.wall_tiling = bool(options.get("wall_tiling", 1))
	# A browser without threads draws every band on one core: it gets LOW whatever the setting.
	var unthreaded := OS.has_feature("web") and not OS.has_feature("threads")
	var detail := int(options.get("detail", 0))
	if unthreaded or detail == 1 or (detail == 2 and Renderer.auto_low):
		renderer.set_detail(1)
	else:
		renderer.set_detail(-1 if detail == 3 else 0)
	flicker = bool(options.get("flicker", 1))
	armory.auto_switch = bool(options.get("auto_switch", 1))
	armory.auto_reload = bool(options.get("auto_reload", 1))
	var enabled := bool(options.get("barks", 1)) and not barks_off_by_code
	barks.enabled = enabled


func message(text: String, length := 1.9) -> void:
	notice = text
	message_until = clock + maxf(length, .70 + .16 * text.split(" ", false).size())


# ----------------------------------------------------------------- sound


func sound_position(x: float, y: float, strength := 1.0, muffle := true) -> Vector2:
	var p := player
	var dx := x - p.x
	var dy := y - p.y
	var distance := sqrt(dx * dx + dy * dy)
	var volume := strength / (1.0 + distance * .22)
	if muffle and distance > 1.0 and not world.visible(p.x, p.y, x, y):
		volume *= .43
	var pan := (-sin(p.view_angle()) * dx + cos(p.view_angle()) * dy) / maxf(1.0, distance)
	return Vector2(volume, pan)


## How dull a sound from x, y reaches the player: muffled through a wall,
## a little duller far off or behind (a pan alone cannot say behind).
func sound_cutoff(x: float, y: float) -> float:
	var p := player
	var dx := x - p.x
	var dy := y - p.y
	var distance := sqrt(dx * dx + dy * dy)
	if distance <= 1.0:
		return Sound.OPEN_CUTOFF
	if not world.visible(p.x, p.y, x, y):
		return 1300.0
	var cutoff := Sound.OPEN_CUTOFF / (1.0 + maxf(0.0, distance - 6.0) * .12)
	var facing := (cos(p.view_angle()) * dx + sin(p.view_angle()) * dy) / distance
	if facing < -.3:
		cutoff = minf(cutoff, 9000.0)
	return maxf(2500.0, cutoff)


func sound_at(name: String, x: float, y: float, strength := 1.0) -> void:
	var place := sound_position(x, y, strength)
	sound.play(name, place.x, place.y, sound_cutoff(x, y))
	var p := player
	if name != "bessie" and world.roof[int(p.y) * level.width + int(p.x)] != 0.0:
		if sound.has("room_" + name):
			sound.play("room_" + name, place.x * .55, place.y)


func report(name: String) -> void:
	sound.play(name)
	var p := player
	if world.roof[int(p.y) * level.width + int(p.x)] != 0.0:
		sound.play("room_" + name, .78)


func player_sheltered() -> bool:
	# Every idle enemy asks this every tick: the answer to the first part only
	# changes when some enemy's alerted does (or the list does).
	var key := Vector2i(Enemy.alert_changes, enemies.size())
	if key != shelter_key:
		shelter_key = key
		shelter_alert = false
		for enemy: Enemy in enemies:
			if enemy.alerted and enemy.hostile:
				shelter_alert = true
				break
	if shelter_alert:
		return false
	var p := player
	var sx := float(level.spawn[0])
	var sy := float(level.spawn[1])
	return sqrt((p.x - sx) * (p.x - sx) + (p.y - sy) * (p.y - sy)) < 9.0


func wake_nearby(radius: float, x: float, y: float) -> void:
	for enemy: Enemy in enemies:
		var distance := sqrt((enemy.x - x) * (enemy.x - x) + (enemy.y - y) * (enemy.y - y))
		if (
			enemy.alive
			and enemy.hostile
			and not enemy.alerted
			and distance < radius
			and (distance < 1.45 or world.visible(x, y, enemy.x, enemy.y))
		):
			enemy.wake(self, x, y)


func disturb(x: float, y: float, radius: float, z = null) -> void:
	var source: float = world.elevation(x, y) + .78 if z == null else float(z)
	for actor: Enemy in enemies:
		if (
			not actor.alive
			or actor.alerted
			or actor.heard != null
			or Enemy.BOSS_TITLES.has(actor.kind)
			or actor.brain == "bessie"
			or actor.brain == "saucer"
		):
			continue
		var dx := actor.x - x
		var dy := actor.y - y
		var reach := radius if actor.hostile else minf(radius, 3.5)
		if dx * dx + dy * dy >= reach * reach:
			continue
		var ear: float = world.elevation(actor.x, actor.y) + actor.z + minf(.90, actor.height * .76)
		if not world.visible(x, y, actor.x, actor.y, source, ear):
			continue
		var ready: float = clock + .22 + sqrt(dx * dx + dy * dy) * .035
		actor.heard = [x, y, ready, clock + (2.6 if actor.hostile else 1.05)]
		if not actor.hostile:
			sound_at("chicken" if actor.brain == "chicken" else "pig", actor.x, actor.y, .43)


# ----------------------------------------------------------------- damage


func damage(amount: float, source = null, cause := "HIT") -> void:
	if player.health <= 0:
		return
	var p := player
	if cheats.god:
		return
	var mellow: float = (
		.10 * float(15 <= p.drunk and p.drunk <= 56) + .09 * float(16 <= p.gut and p.gut <= 64)
	)
	amount = maxf(
		1.0, round_even(amount * (1.0 - mellow) * incoming * (adapt if adaptive else 1.0))
	)
	p.health = maxi(0, p.health - int(amount))
	player_hurt.emit(amount, cause)
	if p.health == 0 and adaptive:
		adapt = maxf(.78, adapt - .07)
	if gallery != null and gallery.active:
		gallery.finish(self, "GALLERY CLOSED. CLEAR THE BOOTH AND RETRY.")
	var heading = null if source == null else atan2(float(source[1]) - p.y, float(source[0]) - p.x)
	damage_feedback = [heading, cause, clock + .64]
	hurt_flash = .27
	shake = minf(1.0, shake + minf(.55, amount / 40.0))
	set_face("ouch_shock", .32)
	barks.say(self, "low" if p.health <= 25 else "hurt")
	# A light knock is a grunt; a real wound the hurt cry.
	var cry := "hurt" if amount > 6.0 or p.health <= 25 else "blow_grunt"
	sound.play("player_down" if p.health == 0 else cry)
	if p.health == 0:
		message("YOU BOUGHT THE FARM.", 8.0)


## One of the player's hits landed (Enemy.hurt): mark the crosshair, tick, and
## hold the world still a moment on a kill or a heavy blow.
func struck(amount: float, killed: bool, champion: bool) -> void:
	hit_landed.emit(amount, killed)
	if not hit_feedback:
		return
	if clock >= hit_mark_until:
		hit_mark_kill = false
	hit_mark_until = maxf(hit_mark_until, clock + (.24 if killed else .12))
	hit_mark_kill = hit_mark_kill or killed
	if clock >= hitstop_next and (killed or amount >= 40.0):
		hitstop = maxf(hitstop, .09 if killed and champion else .05 if killed else .03)
		hitstop_next = clock + .22
	if killed:
		sound.play("kill_tick", .55)
		hit_tick_next = clock + .06
	elif clock >= hit_tick_next:
		sound.play("hit_tick", .34)
		hit_tick_next = clock + .06


func add_pickup(name: String, x: float, y: float) -> void:
	pickups.append([name, x, y])


func collect(name: String) -> bool:
	name = String(ALIAS.get(name, name))
	if Weapons.NAMES.has(name):
		armory.pickup(Weapons.NAMES.find(name), self)
		barks.say(self, "pickup_weapon", true)
		set_face("grin_rampage", .6)
	elif HUD.ITEMS.has(name):
		if int(inventory[name]) >= 5:
			return false
		inventory[name] = int(inventory[name]) + 1
		message(String(PICKUP_NAMES[name]))
		barks.say(self, "pickup_food")
	elif TASK_ITEMS.has(name):
		task_items[name] = true
		message("PA PATCH LEAD. TAKE IT TO THE BACKSTAGE BOOTH.", 3.0)
	elif name.begins_with("key_"):
		keys[name] = true
		message(
			(
				"BRASS KEY - OPEN THE BARN."
				if name.ends_with("brass")
				else "STEEL KEY - OPEN THE PASTURE GATE."
			),
			4.0
		)
	else:
		if not AMMO.has(name):
			return false
		var entry_ammo: Array = AMMO[name]
		var slot := int(entry_ammo[0])
		var amount := int(entry_ammo[1])
		if supply_rule == 1:
			amount = maxi(1, int(round(amount * .70)))
		amount = maxi(1, int(round(amount * ammo_scale)))
		if not armory.add_ammo(slot, amount):
			return false
		if name == "dynamite" and not armory.owned[Weapons.DYNAMITE]:
			armory.owned[Weapons.DYNAMITE] = true
			message("DYNAMITE [8] - HOLD FIRE, RELEASE TO THROW", 3.5)
		else:
			message(String(PICKUP_NAMES[name]), 1.0)
	sound.play(
		(
			"key_pickup"
			if name.begins_with("key_") or TASK_ITEMS.has(name)
			else "weapon_pickup" if Weapons.NAMES.has(name) else "pickup"
		),
		.8
	)
	pickup_taken.emit(name)
	return true


func use_item(slot := -1) -> void:
	if slot >= 0:
		inventory_slot = slot
	var i := inventory_slot
	var name: String = HUD.ITEMS[i]
	if int(inventory[name]) == 0:
		message("OUT OF " + String(HUD.ITEM_LABELS[i]) + ".", 1.05)
		return
	inventory[name] = int(inventory[name]) - 1
	var p := player
	var health := p.health
	var text := ""
	var state := ""
	if i == 0:
		p.gut = minf(100.0, p.gut + 37.0)
		p.health = mini(100, p.health + 28)
		if p.drunk > 52:
			p.drunk -= 13
		text = "PORK RINDS. GOOD EATIN'."
		state = "FULL GUT" if p.gut >= 86 else ""
	elif i == 1:
		p.drunk = minf(100.0, p.drunk + 36.0)
		p.health = mini(100, p.health + 16)
		text = "COLD BEER. EASY ON THE STEERING."
		state = "WOBBLY" if p.drunk > 82 else "BUZZED"
	elif i == 3:
		p.drunk = minf(100.0, p.drunk + 55.0)
		p.health = mini(100, p.health + 34)
		text = "WHISKEY. HAIR ON YER CHEST."
		state = "LOOSE" if p.drunk > 70 else "WARM"
	elif i == 4:
		p.gut = minf(100.0, p.gut + 48.0)
		p.drunk = maxf(0.0, p.drunk - 12.0)
		p.health = mini(100, p.health + 12)
		text = "COW PIE. DON'T ASK."
		state = "FULL GUT" if p.gut >= 86 else ""
	else:
		p.drunk = maxf(0.0, p.drunk - 70.0)
		p.gut = maxf(0.0, p.gut - 55.0)
		p.health = mini(100, p.health + 24)
		sprint = 7.0
		text = "THAT'LL PUT HAIR ON THE TRACTOR."
		state = "SPEED UP"
	sound.play(["crunch", "gulp", "moonshine", "whiskey_glug", "cowpie_pick"][i])
	message(text)
	var change := "+%d HP" % (p.health - health) if p.health > health else ""
	var bits: Array = []
	if change != "":
		bits.append(change)
	if state != "":
		bits.append(state)
	item_feedback = [name, "  ".join(bits), clock + 1.05]


# --------------------------------------------------------------- movement


## Mirrors Game.move_actor: axis-separated world move with body separation, so
## the player cannot walk through a hostile actor (or an actor through them).
func move_actor(body, dx: float, dy: float, radius: float) -> void:
	var p := player
	var neighbors: Array = []
	if body == p:
		for enemy: Enemy in enemies:
			if (
				enemy.hostile
				and enemy.alive
				and absf(p.x - enemy.x) < 1.1
				and absf(p.y - enemy.y) < 1.1
			):
				neighbors.append(enemy)
	elif body.hostile and absf(body.x - p.x) < 1.1 and absf(body.y - p.y) < 1.1:
		neighbors = [p]
	var occupied = null
	if not neighbors.is_empty():
		occupied = func(x: float, y: float) -> bool:
			for neighbor in neighbors:
				var enemy = neighbor if body == p else body
				var enemy_base: float = world.elevation(enemy.x, enemy.y) + enemy.z
				var player_base: float = world.elevation(p.x, p.y) + p.air
				if enemy_base >= player_base + (.80 if p.crouched else 1.16):
					continue
				if player_base >= enemy_base + enemy.height:
					continue
				var reach := PLAYER_RADIUS + minf(enemy.radius, .37)
				var distance: float = (
					(x - neighbor.x) * (x - neighbor.x) + (y - neighbor.y) * (y - neighbor.y)
				)
				# An old checkpoint may already overlap a body. Allow motion outward.
				if (
					distance < reach * reach
					and (
						distance
						< (
							(body.x - neighbor.x) * (body.x - neighbor.x)
							+ (body.y - neighbor.y) * (body.y - neighbor.y)
						)
					)
				):
					return true
			return false
	world.move(body, dx, dy, radius, occupied)


# ------------------------------------------------------------------- death


func enemy_down(enemy: Enemy) -> void:
	kills += 1
	enemy_killed.emit(enemy)
	if enemy.hostile:
		barks.kill(self)
	if not Enemy.BOSS_TITLES.has(enemy.kind):
		for actor: Enemy in enemies:
			if (
				Enemy.LOSS_RESPONDERS.has(actor.kind)
				and actor.alive
				and actor.alerted
				and not actor.responded
				and not actor.windup
				and sqrt(pow(actor.x - enemy.x, 2) + pow(actor.y - enemy.y, 2)) < 2.85
				and world.visible(actor.x, actor.y, enemy.x, enemy.y)
			):
				actor.retreat_from(self, enemy.x, enemy.y)
				sound_at("county_fall_back", actor.x, actor.y, .67)
				break
	if enemy == boss:
		if jerry != null:
			jerry.dormant = false
			jerry.wake(self, player.x, player.y)
			jerry.cooldown = 1.25
		message("THE SHERIFF'S DOWN. HERE COMES JERRY!", 4.0)
		sound.play("jerry_intro")
	elif enemy == jerry:
		message("THAT'S THE BALL GAME! GO GET BESSIE.", 5.0)
		sound.play("yee_haw")
		sound.sting("shakedown_end")
	elif enemy == finale:
		hazards.clear()
		var kept: Array = []
		for shot in shots:
			if shot.kind != "foreman_cut" and shot.kind != "rudy_horn":
				kept.append(shot)
		shots = kept
		var reward := String(Enemy.DEFS[enemy.kind].get("finale_drop", "bullets"))
		add_pickup(String(reward), enemy.x, enemy.y)
		message(
			(
				String(Enemy.BOSS_TITLES.get(enemy.kind, "BOSS"))
				+ " IS DOWN. CLEAR THE LAST VARMINTS."
			),
			3.0
		)
		sound.sting(enemy.kind + "_end")
	elif Enemy.DEFS[enemy.kind].has("drop"):
		# What it leaves (enemies.cfg): always, or by chance unless NO DROPS.
		var spec: Dictionary = Enemy.DEFS[enemy.kind]
		var chance := float(spec.get("drop_chance", 1.0))
		if chance >= 1.0 or (rng.random() < chance and supply_rule != 2):
			add_pickup(String(spec["drop"]), enemy.x, enemy.y)
	if (
		enemy.hostile
		and not Enemy.BOSS_TITLES.has(enemy.kind)
		and supply_rule != 2
		and rng.random() < Enemy.LUCKY_CHANCE
	):
		add_pickup(String(rng.choice(HUD.ITEMS)), enemy.x + .2, enemy.y)
		message("FEELIN' LUCKY. SOMETHING DROPPED.", 1.6)
	if (
		world.extraction != null
		and world.extraction.shutdown in stations_done
		and _wave_has(enemy)
		and not _wave_alive()
	):
		message("THE EXIT IS CLEAR. GET MOVING.", 4.0)
		sound.play("gate")


func _wave_has(enemy: Enemy) -> bool:
	for member: Enemy in wave:
		if member == enemy:
			return true
	return false


func _wave_alive() -> bool:
	for member: Enemy in wave:
		if member.alive:
			return true
	return false


func set_face(value: String, duration: float) -> void:
	if face == "ouch_shock" and clock < face_until and value != "ouch_shock":
		return
	face = value
	face_until = clock + duration


func face_name() -> String:
	var health := player.health
	if health <= 0:
		return "dead"
	if face_until > clock:
		return face
	if player.drunk > 47:
		return "drunk_dizzy"
	if health <= 25:
		return "hurt_75"
	if health <= 50:
		return "hurt_50"
	if health <= 75:
		return "hurt_25"
	var phase := fmod(clock, 5.9)
	if 1.7 < phase and phase < 2.04:
		return "look_left"
	if 3.3 < phase and phase < 3.62:
		return "look_right"
	return "idle_blink" if phase > 5.75 else "idle_center"


# -------------------------------------------------------------- interaction


## Mirrors Game.use_target: returns [target, x, y] or null.
func use_target() -> Variant:
	if gallery != null and gallery.active:
		return [gallery, GALLERY_STAND.x + gallery.offset.x, GALLERY_STAND.y + gallery.offset.y]
	var facing := Vector2(cos(player.view_angle()), sin(player.view_angle()))
	if bessie != null and bessie.alive:
		var dx: float = bessie.x - player.x
		var dy: float = bessie.y - player.y
		var distance := sqrt(dx * dx + dy * dy)
		if (
			distance < 1.52
			and (distance < .55 or dx * facing.x + dy * facing.y > distance * .40)
			and world.visible(player.x, player.y, bessie.x, bessie.y)
		):
			return ["bessie", bessie.x, bessie.y]
	var doors: Array = []
	for door: LevelData.Door in world.doors:
		if (
			door.opened
			and (door.blast_only or world.controlled_doors.has(Vector2i(door.x, door.y)))
		):
			continue
		var centre := door.center()
		doors.append([door, centre.x, centre.y])
	var devices: Array = []
	for station: LevelData.Station in world.stations:
		if not station.reveals_secret or not stations_done.has(station.id):
			devices.append(station)
	if world.extraction != null:
		devices.append(world.extraction)
	for device: Array in level.devices:
		devices.append(device)
	if gallery != null:
		devices.append(gallery)
	for note: LevelData.Note in level.notes:
		devices.append(note)
	# An aimed target beats an unaimed one (the reference's rule); among them
	# the one nearest the crosshair wins, a little in favour of the nearer.
	var best := [true, INF]
	var result = null
	use_aim = Vector3.INF
	for door_entry: Array in doors:
		var x: float = door_entry[1]
		var y: float = door_entry[2]
		var rank := _use_rank(x, y, 1.57, .50, .48, facing)
		if _ranks_above(rank, best) and world.visible(player.x, player.y, x, y):
			best = rank
			result = door_entry
			use_aim = Vector3.INF
	for device in devices:
		for point: Vector3 in aim_points(device):
			var rank := _use_rank(point.x, point.y, DEVICE_REACH, DEVICE_TOUCH, DEVICE_CONE, facing)
			if _ranks_above(rank, best) and seen_at(point):
				best = rank
				use_aim = point
				var at := use_point(device)
				result = [device[0] if device is Array else device, at.x, at.y]
	return result


## Quest devices (stations, the exit, notes, the jukebox and sink, the tin
## rooster stand) answer USE from a little farther than doors and a little
## wider round the crosshair, at any of their aim points (aim_points).
const DEVICE_REACH := 1.65
const DEVICE_TOUCH := .62
const DEVICE_CONE := .34


## [not aimed, score] for something at x, y, or [] when it is out of reach:
## aimed within `cone` (the dot of the facing and the way to it, per unit of
## distance), or closer than `touch` whichever way the player faces. The score
## is how far off the crosshair it is (radians) and a third of its distance.
func _use_rank(
	x: float, y: float, reach: float, touch: float, cone: float, facing: Vector2
) -> Array:
	var dx := x - player.x
	var dy := y - player.y
	var distance := sqrt(dx * dx + dy * dy)
	if distance >= reach:
		return []
	var along := dx * facing.x + dy * facing.y
	var aimed := along > distance * cone
	if not aimed and distance >= touch:
		return []
	var off := acos(clampf(along / maxf(distance, .001), -1.0, 1.0))
	return [not aimed, off + distance * .35]


func _ranks_above(rank: Array, best: Array) -> bool:
	if rank.is_empty():
		return false
	if bool(rank[0]) != bool(best[0]):
		return not bool(rank[0])
	return float(rank[1]) < float(best[1])


## Where USE acts on a device, as the game has always reported it.
func use_point(device) -> Vector2:
	if device is Array:
		return Vector2(float(device[1]), float(device[2]))
	if device is GameState.Gallery:
		return GALLERY_STAND + gallery.offset
	return Vector2(device.x, device.y)


## The points a device can be aimed at, with the height of what is seen there:
## its own point, and for a station or the exit the board that lights up for it
## close by (the panel the player looks at), for a note the slip on the table,
## for the jukebox and sink the thing itself.
func aim_points(device) -> Array:
	if aim_cache.get("level") != world:
		# A level reloaded from the editor: its boards may have moved.
		aim_cache = {"level": world}
	var key = device if not (device is Array) else String(device[0])
	if aim_cache.has(key):
		return aim_cache[key]
	var at := use_point(device)
	var lift := .9
	var signal_name := ""
	var near_art := ""
	if device is LevelData.Station:
		signal_name = device.id
	elif device is LevelData.Extraction:
		signal_name = "exit"
	elif device is LevelData.Note:
		lift = 1.01
		near_art = "note"
	elif device is Array:
		near_art = String(device[0])
	var points: Array = [Vector3(at.x, at.y, world.elevation(at.x, at.y) + lift)]
	for board: LevelData.Billboard in world.billboards:
		var d := Vector2(board.x, board.y).distance_to(at)
		var mine := signal_name != "" and board.signal_name == signal_name and d < 3.5
		if near_art == "note":
			mine = d < .8 and (board.image == "county_note" or board.image.begins_with("story_"))
		if mine:
			var z: float = world.elevation(board.x, board.y) + board.z + board.height * .5
			points.append(Vector3(board.x, board.y, z))
	if near_art != "" and near_art != "note":
		for prop: LevelData.Scenery in world.scenery:
			if prop.kind == near_art and Vector2(prop.x, prop.y).distance_to(at) < 1.5:
				var z: float = world.elevation(prop.x, prop.y) + prop.z + prop.height * .5
				points.append(Vector3(prop.x, prop.y, z))
		for spec in level.props:
			var q := Vector2(float(spec[1]), float(spec[2]))
			if String(spec[0]) == near_art and q.distance_to(at) < 1.5:
				var h := float(PROP_HEIGHTS.get(near_art, 1.0))
				points.append(Vector3(q.x, q.y, world.elevation(q.x, q.y) + h * .5))
	aim_cache[key] = points
	return points


## Whether the player's eye sees `point` (x, y, height), or failing that the
## face of what it is mounted in or stood on: a point stepped back toward the
## player, out of the wall, counter or pump, at most .45 (less than half a
## cell, so a thing in a wall is only ever seen from its own side).
func seen_at(point: Vector3) -> bool:
	var p := player
	if world.visible(p.x, p.y, point.x, point.y, p.eye, point.z):
		return true
	var way := Vector2(p.x - point.x, p.y - point.y)
	var length := way.length()
	if length < .05:
		return true
	way /= length
	for k in range(1, 10):
		var step := minf(k * .05, length - .02)
		var face := Vector2(point.x, point.y) + way * step
		if not world.blocked(face.x, face.y, .023, point.z):
			return world.visible(p.x, p.y, face.x, face.y, p.eye, point.z)
	return false


## Whether the player standing where they are takes the pickup `entry`
## ([name, x, y]). A key or the patch lead is taken from a little farther and
## over a counter or crate it lies by; anything else as it always was.
func reaches_pickup(entry: Array) -> bool:
	var x := float(entry[1])
	var y := float(entry[2])
	var gap := (player.x - x) * (player.x - x) + (player.y - y) * (player.y - y)
	if gap >= .62 * .62:
		# Beyond either reach (every tick, for every pickup in the level).
		return false
	var name := String(entry[0])
	if name.begins_with("key_") or TASK_ITEMS.has(name):
		return gap < .62 * .62 and seen_at(Vector3(x, y, world.elevation(x, y) + .25))
	return gap < .43 * .43 and world.visible(player.x, player.y, x, y)


func use_prompt() -> String:
	var found = use_target()
	if found == null:
		return ""
	var target = found[0]
	if target is String:
		if target == "bessie":
			var boss_alive: bool = boss != null and boss.alive
			var jerry_alive: bool = jerry != null and jerry.alive
			return "CLEAR THE PEN FIRST" if boss_alive or jerry_alive else "E  RESCUE BESSIE"
		if target == "jukebox":
			return "E  STOP JUKEBOX" if jukebox_on else "E  PLAY JUKEBOX"
		if target == "sink":
			return "E  USE SINK"
	if target is Gallery:
		return target.prompt()
	if target is LevelData.Note:
		return "E  READ " + target.label
	if target is LevelData.Station:
		var station: LevelData.Station = target
		if stations_done.has(station.id):
			return "ALREADY SET"
		if station.reveals_secret:
			return "E  CHECK THE LOOSE PANEL"
		for key in station.requires:
			if not stations_done.has(String(key)):
				return objective()
		if station.held != "" and not task_items.has(station.held):
			return "FIND THE PATCH LEAD AT THE RAFFLE OFFICE"
		if station.action == "strike":
			return "STRIKE THE BELT RELEASE"
		if station.action == "crank":
			return "E  TURN THE CONDENSER  %d/3" % int(valve_turns.get(station.id, 0))
		return "E  " + station.label
	if target is LevelData.Extraction:
		return "E  " + target.label if exit_ready() else "EXIT LOCKED / CHECK TAB MAP"
	var door: LevelData.Door = target
	if world.controlled_doors.has(Vector2i(door.x, door.y)):
		return "" if door.opened else "CONTROLLED BY A REMOTE SWITCH"
	if door.blast_only:
		return "POWDER STORE  /  BLAST PANEL"
	if door.key != "" and not keys.has(door.key):
		return "BRASS KEY NEEDED" if door.key.ends_with("brass") else "STEEL KEY NEEDED"
	if door.secret and not door.discovered:
		if world.crouch_doors.has(Vector2i(door.x, door.y)):
			return "CROUCH / USE THE LOW HATCH"
		return ""
	return "E  CLOSE DOOR" if door.opened else "E  OPEN DOOR"


func interact() -> void:
	if showing_tally or player.health <= 0:
		return
	if boss_hold > 0.0:
		# USE cuts a boss's entrance short (BossKit.hold).
		if boss_hold_for - boss_hold > BossKit.SKIP_AFTER:
			boss_hold = 0.0
		return
	var gate = portal_target()
	if gate != null:
		if world.locked_gates.has(gate):
			message(gate_text(gate), 3.0)
			sound.play("chain_rattle")
		elif armory.fuse > 0.0:
			message("THROW THE LIT STICK BEFORE LEAVING.", 3.0)
		else:
			portal_request = gate.destination
		return
	if in_hub:
		var clue = hub_clue()
		if clue != null:
			message(String(clue[4]), 4.0)
			if String(clue[0]) == "dispatch":
				if clock >= hub_dispatch_until:
					hub_dispatch_until = clock + 6.0
					var place := sound_position(level.hub_board.x, level.hub_board.y, .64)
					sound.play_voice("county_dispatch_%d" % hub_milestone, place.x, place.y)
					if voice_captions:
						caption = String(HUB_DISPATCH[hub_milestone][2])
						caption_until = clock + 2.4
			else:
				hub_findings[String(clue[0])] = true
				sound.play("menu_accept", .55)
		return
	var found = use_target()
	if found == null:
		return
	var target = found[0]
	var x: float = found[1]
	var y: float = found[2]
	if target is String:
		if target == "bessie":
			if (boss != null and boss.alive) or (jerry != null and jerry.alive):
				message("CLEAR THE PASTURE BEFORE YOU FREE BESSIE.", 2.4)
			elif revisiting:
				message("BESSIE IS SAFE. RETURN VIA THE ROAD GATE.", 2.4)
			else:
				finish_level("got_bessie")
			return
		if target == "jukebox":
			jukebox_on = not jukebox_on
			radio_check = 0.0
			sound_at("menu_accept", x, y, .54)
			message("JUKEBOX: HICKSTON SHUFFLE" if jukebox_on else "JUKEBOX OFF", 1.45)
			return
		if target == "sink":
			if clock >= flush_until:
				flush_until = clock + 1.35
				sound_at("sink_flush", x, y, .83)
				burst(x, y, .86, "splash", 8, .47)
				message("WASH UP, YOU ANIMAL.", 1.5)
			return
	if target is Gallery:
		target.toggle(self)
		return
	if target is LevelData.Note:
		message(target.text, 4.0)
		sound.play("menu_move", .40)
		return
	if target is LevelData.Station:
		operate_station(target)
		return
	if target is LevelData.Extraction:
		if revisiting:
			message("SHIFT DONE. RETURN VIA THE ROAD GATE.", 2.4)
		elif exit_ready():
			finish_level("gate")
		else:
			message(objective(), 3.0)
			sound_at("chain_rattle", x, y, .8)
		return
	var door: LevelData.Door = target
	if world.controlled_doors.has(Vector2i(door.x, door.y)):
		if not door.opened:
			message("THAT GATE HAS A REMOTE SWITCH.", 2.5)
		return
	if door.key != "" and not keys.has(door.key):
		message(
			(
				"NEEDS THE BRASS BARN KEY."
				if door.key.ends_with("brass")
				else "NEEDS THE STEEL PASTURE KEY."
			),
			2.7
		)
		sound.play("empty")
		return
	if door.blast_only:
		message("POWDER STORE. THAT PANEL NEEDS DYNAMITE.", 2.65)
		sound.play("empty", .56)
		return
	if (
		world.crouch_doors.has(Vector2i(door.x, door.y))
		and not player.crouched
		and not door.discovered
	):
		message("GET LOW AND TRY THE HATCH AGAIN.", 3.0)
		return
	toggle_door(door, not door.opened)


# ----------------------------------------------------------------- stations


func set_station_lights(station: LevelData.Station) -> void:
	for sector_v in station.sectors:
		var sector := int(sector_v)
		var n := world.area.size()
		for i in n:
			if int(world.area[i]) == sector:
				world.light[i] += .26
		world.light_version += 1
		for i in world.wall_count:
			var o := i * LevelData.WALL_STRIDE
			if int(world.walls[o + 8]) == sector:
				world.walls[o + 5] += .26


func activate_station(station: LevelData.Station) -> void:
	if stations_done.has(station.id):
		return
	for key in station.requires:
		if not stations_done.has(String(key)):
			message(objective(), 3.0)
			sound.play("empty")
			return
	stations_done[station.id] = true
	station_done.emit(station.id)
	set_station_lights(station)
	for door: LevelData.Door in world.doors:
		var point := Vector2i(door.x, door.y)
		var required = world.access_doors.get(point)
		var satisfied := false
		if required != null:
			satisfied = true
			for key in required:
				if not stations_done.has(String(key)):
					satisfied = false
					break
		if station.opens.has(point) or (satisfied and not door.opened):
			toggle_door(door, true)
	if station.reveals_secret:
		secrets += 1
	if world.extraction != null and station.id == world.extraction.shutdown:
		for enemy: Enemy in wave:
			enemy.dormant = false
			enemy.wake(self, player.x, player.y)
			enemy.cooldown = 2.05 if enemy == finale else 1.15
		if finale != null:
			sound.sting(finale.kind + "_intro")
	sound_at(station.cue, station.x, station.y, .95)
	message(station.message, 4.0)


func operate_station(station: LevelData.Station) -> void:
	if stations_done.has(station.id):
		return
	if station.action == "strike":
		message("THE HANDLE'S STRIPPED. HIT THE BELT RELEASE.", 3.0)
		return
	if station.held != "" and not task_items.has(station.held):
		message("NEEDS THE PATCH LEAD FROM THE RAFFLE OFFICE.", 3.0)
		return
	if station.action == "crank":
		if clock < next_valve_turn:
			return
		next_valve_turn = clock + .20
		var turns := int(valve_turns.get(station.id, 0)) + 1
		if turns < 3:
			valve_turns[station.id] = turns
			sound_at("scenery_pipe", station.x, station.y, .67)
			message("CONDENSER VALVE  %d/3. KEEP TURNING." % turns, 2.0)
			return
		valve_turns.erase(station.id)
	activate_station(station)


## Where to go for a station: the station, or first the thing it needs carried
## to it (the fair's PA patch lead) while that still lies somewhere.
func _station_goal(station: LevelData.Station) -> Vector2:
	if station.held != "" and not task_items.has(station.held):
		for entry: Array in pickups:
			if String(entry[0]) == station.held:
				return Vector2(float(entry[1]), float(entry[2]))
	return Vector2(station.x, station.y)


## The mill's relay, where the saws are loudest (the rain is heard away from it).
func _relay_at() -> Vector2:
	for station: LevelData.Station in world.stations:
		if station.id == "relay":
			return Vector2(station.x, station.y)
	return Vector2(24.3, 6.7)


func exit_ready() -> bool:
	if world.extraction == null:
		return false
	return stations_done.has(world.extraction.shutdown) and not _wave_alive()


## What the objective is done at glows a little, as the lamp on the quest prop
## would: a station still to do warm at its lamp, a done one a small green
## pilot; the exit red until the way is clear, then green; a Crossroads gate
## red while locked, green once open (effects.cfg station_todo, station_done,
## exit_locked, exit_open, gate_locked, gate_open). Steady: the props are
## modelled whole and read without a blink. A hidden station keeps its secret.
func _quest_lights() -> Array:
	var p := player
	var out: Array = []
	if in_hub:
		for gate: LevelData.Gate in world.hub_gates:
			if absf(gate.x - p.x) < 14.0 and absf(gate.y - p.y) < 14.0:
				var locked := world.locked_gates.has(gate)
				var z := world.elevation(gate.x, gate.y + gate.side * .4) + 2.0
				out.append(
					Effects.light(
						"gate_locked" if locked else "gate_open",
						gate.x,
						gate.y + gate.side * .4,
						z,
						1.0,
						clock
					)
				)
		return out
	for station: LevelData.Station in world.stations:
		if station.hidden or station.reveals_secret:
			continue
		if absf(station.x - p.x) > 12.0 or absf(station.y - p.y) > 12.0:
			continue
		var done := stations_done.has(station.id)
		var at: Vector3 = _lamp_at(station)
		out.append(
			Effects.light(
				"station_done" if done else "station_todo",
				at.x,
				at.y,
				at.z - (.45 if done else 0.0),
				1.0,
				clock
			)
		)
	var exit: LevelData.Extraction = world.extraction
	if exit != null and absf(exit.x - p.x) < 12.0 and absf(exit.y - p.y) < 12.0:
		var at: Vector3 = _lamp_at(exit)
		var open := exit_ready()
		out.append(
			Effects.light("exit_open" if open else "exit_locked", at.x, at.y, at.z, 1.0, clock)
		)
	return out


## Where a device's lamp is: near the top of its quest prop (the last of its
## aim points, the prop's middle), else above its own point.
func _lamp_at(device) -> Vector3:
	var points := aim_points(device)
	var last: Vector3 = points[points.size() - 1]
	return Vector3(last.x, last.y, last.z + .5)


func finish_level(cue: String) -> void:
	if not won:
		won = true
		level_won.emit()
		if adaptive and player.health >= 60 and not replay:
			adapt = minf(1.15, adapt + .05)
		shots.clear()
		hazards.clear()
		blasts.clear()
		specks.clear()
		sound.pause_world()
		sound.set_score("victory")
		sound.play(cue)


func portal_target(reach := 2.62) -> Variant:
	var portals: Array = world.hub_gates if in_hub else [world.return_gate]
	for gate in portals:
		if gate == null:
			continue
		if gate.approach(player.x, player.y, player.view_angle(), reach) or _gate_aimed(gate):
			var face: float = gate.y + (.17 if player.y - gate.y >= 0.0 else -.17)
			if world.visible(
				player.x,
				player.y,
				player.x,
				face,
				player.eye,
				world.elevation(player.x, face) + .93
			):
				return gate
	return null


## A gate the player stands in front of with the crosshair on its opening,
## however slanting (Gate.approach wants the gate fairly square ahead).
func _gate_aimed(gate: LevelData.Gate) -> bool:
	var d := (player.y - gate.y) * gate.side
	if d < .15 or d > 1.9 or absf(player.x - gate.x) > gate.width * .5 + .1:
		return false
	var toward := -sin(player.view_angle()) * gate.side
	if toward < .15:
		return false
	var hit := player.x + cos(player.view_angle()) * d / toward
	return absf(hit - gate.x) < gate.width * .5 and d / toward < 2.4


func hub_clue() -> Variant:
	var label: String = String(HUB_DISPATCH[hub_milestone][0])
	var text: String = String(HUB_DISPATCH[hub_milestone][1])
	var best = null
	var best_rank := [true, INF]
	var candidates: Array = world.hub_clues.duplicate()
	candidates.append(["dispatch", level.hub_board.x, level.hub_board.y, "READ " + label, text])
	var facing := Vector2(cos(player.view_angle()), sin(player.view_angle()))
	for clue in candidates:
		var x: float = clue[1]
		var y: float = clue[2]
		# As the quest devices: a little reach, the one nearest the crosshair.
		var rank := _use_rank(x, y, DEVICE_REACH, DEVICE_TOUCH, DEVICE_CONE, facing)
		if _ranks_above(rank, best_rank) and seen_at(Vector3(x, y, world.elevation(x, y) + .96)):
			best = clue
			best_rank = rank
	return best


func gate_text(gate: LevelData.Gate) -> String:
	if gate.destination == "hub":
		return "E  RETURN TO COUNTY CROSSROADS"
	if world.locked_gates.has(gate):
		var index := Campaign.ORDER.find(gate.destination)
		var previous: String = Campaign.ORDER[index - 1] if index > 0 else ""
		return "LOCKED / FINISH " + Campaign.title_of(previous)
	return (
		"E  "
		+ String(gate_modes.get(gate.destination, "ENTER"))
		+ " "
		+ Campaign.title_of(gate.destination)
	)


func toggle_door(door: LevelData.Door, opened: bool) -> void:
	door.opened = opened
	if door.blast_only and opened:
		door.progress = 1.0
		var centre := door.center()
		burst(centre.x, centre.y, .86, "dust", 11, 1.6)
	else:
		var centre := door.center()
		sound_at(
			"secret_slide" if door.secret else "gate" if door.key != "" else "door",
			centre.x,
			centre.y
		)
	if door.secret and not door.discovered:
		door.discovered = true
		secrets += 1
		message("YOU FOUND A SECRET!", 2.4)
		barks.say(self, "secret")
		sound.play("yee_haw")


# ------------------------------------------------------------ projectiles


func burst(x: float, y: float, z: float, kind: String, count: int, speed: float) -> void:
	if kind == "gore" and not gore:
		return
	for _i in count:
		var angle := rng.random() * TAU
		var v := rng.uniform(.24, speed)
		specks.append(
			Speck.new(
				x,
				y,
				z,
				cos(angle) * v,
				sin(angle) * v,
				rng.uniform(.2, speed * 1.3),
				rng.uniform(.18, .68),
				kind
			)
		)


func scenery_used(prop: LevelData.Scenery) -> bool:
	return scenery_spent.has(prop.id) or stations_done.has(prop.station)


func relief_open() -> bool:
	return stations_done.has("relief-west") or stations_done.has("relief-east")


func pressure_ports(attacks: int) -> Array:
	var ports: Array = world.pressure_ports
	if ports.is_empty():
		return []
	var count := 1 if relief_open() else 2
	# The baron picks the outlets nearest where the player stood as he wound up
	# (bosses/baron.gd keeps them on him); otherwise they go in turn.
	if finale != null and int(finale.get_meta("ports_for", -1)) == attacks:
		var picked: Array = finale.get_meta("ports")
		return picked.slice(0, mini(count, picked.size()))
	var offset := int(attacks / 2) % ports.size()
	var out: Array = []
	for i in count:
		out.append(ports[(offset + i) % ports.size()])
	return out


# -------------------------------------------------------------- ground marks


func objective() -> String:
	if in_hub:
		return "FACE A GATE AND PRESS E OR SPACE"
	if revisiting:
		return "COMPLETED / RETURN AT THE ROAD GATE"
	if not level.rescue:
		var exit: LevelData.Extraction = world.extraction
		if exit == null:
			return ""
		var shutdown: LevelData.Station = null
		for station: LevelData.Station in world.stations:
			if station.id == exit.shutdown:
				shutdown = station
				break
		if shutdown == null:
			return ""
		var primary: Array = []
		for key in shutdown.requires:
			if not world.objective_side_tasks.has(key):
				primary.append(String(key))
		var pending: Array = []
		for key in primary:
			if not stations_done.has(key):
				pending.append(key)
		if pending.size() == 1:
			for station: LevelData.Station in world.stations:
				if station.id == pending[0]:
					if station.held != "" and not task_items.has(station.held):
						return "FIND THE PA PATCH LEAD AT THE RAFFLE OFFICE"
					return station.label
		if not pending.is_empty():
			return world.control_name
		for station: LevelData.Station in world.stations:
			if world.objective_side_tasks.has(station.id) and not stations_done.has(station.id):
				return station.label
		if not stations_done.has(shutdown.id):
			return shutdown.label
		var threats := 0
		for enemy: Enemy in wave:
			if enemy.alive:
				threats += 1
		return "CLEAR EXIT THREATS: %d" % threats if threats else exit.label
	if (boss == null or not boss.alive) and (jerry == null or not jerry.alive):
		return "RESCUE BESSIE"
	if jerry != null and jerry.alive and not jerry.dormant:
		return "PASTURE / BEAT JERRY"
	if keys.has("key_steel"):
		return "PASTURE / FIND BESSIE"
	if keys.has("key_brass"):
		return (
			"BARN / STEEL KEY AT THE FEED SCALE"
			if legacy_key_route
			else "STEEL KEY / EAST AT THE STOCK REGISTRY"
		)
	return "STANKY'S / BRASS KEY IN DISPATCH"


## The middle of the nearest cell to (x, y) a body can stand in out of deep
## water (rings out to 12 cells), or (x, y) itself when there is none.
func shore_near(x: float, y: float) -> Vector2:
	for r in range(1, 13):
		var best := Vector2.INF
		for cy in range(int(y) - r, int(y) + r + 1):
			for cx in range(int(x) - r, int(x) + r + 1):
				if maxi(absi(cx - int(x)), absi(cy - int(y))) != r:
					continue
				var at := Vector2(cx + .5, cy + .5)
				if cx < 1 or cy < 1 or cx >= world.width - 1 or cy >= world.height - 1:
					continue
				if world.blocked(at.x, at.y, .3) or world.deep_at(at.x, at.y):
					continue
				if at.distance_squared_to(Vector2(x, y)) < best.distance_squared_to(Vector2(x, y)):
					best = at
		if best != Vector2.INF:
			return best
	return Vector2(x, y)


func objective_target() -> Variant:
	if in_hub or revisiting:
		return null
	if not level.rescue:
		var exit: LevelData.Extraction = world.extraction
		if exit == null:
			return null
		var shutdown: LevelData.Station = null
		for station: LevelData.Station in world.stations:
			if station.id == exit.shutdown:
				shutdown = station
				break
		if shutdown == null:
			return null
		var primary: Array = []
		for key in shutdown.requires:
			if not world.objective_side_tasks.has(key):
				primary.append(String(key))
		var pending: Array = []
		for key in primary:
			if not stations_done.has(key):
				pending.append(key)
		if pending.size() == 1:
			for station: LevelData.Station in world.stations:
				if station.id == pending[0]:
					return _station_goal(station)
		if not pending.is_empty():
			var options: Array = []
			for station: LevelData.Station in world.stations:
				if pending.has(station.id):
					options.append(station)
			if options.is_empty():
				return null
			var near: LevelData.Station = options[0]
			for station: LevelData.Station in options:
				if (
					(
						(station.x - player.x) * (station.x - player.x)
						+ (station.y - player.y) * (station.y - player.y)
					)
					< (
						(near.x - player.x) * (near.x - player.x)
						+ (near.y - player.y) * (near.y - player.y)
					)
				):
					near = station
			return _station_goal(near)
		for station: LevelData.Station in world.stations:
			if world.objective_side_tasks.has(station.id) and not stations_done.has(station.id):
				return Vector2(station.x, station.y)
		if not stations_done.has(shutdown.id):
			return Vector2(shutdown.x, shutdown.y)
		var threats: Array = []
		for enemy: Enemy in wave:
			if enemy.alive:
				threats.append(enemy)
		if not threats.is_empty():
			var near2: Enemy = threats[0]
			for enemy: Enemy in threats:
				if (
					(
						(enemy.x - player.x) * (enemy.x - player.x)
						+ (enemy.y - player.y) * (enemy.y - player.y)
					)
					< (
						(near2.x - player.x) * (near2.x - player.x)
						+ (near2.y - player.y) * (near2.y - player.y)
					)
				):
					near2 = enemy
			if world.deep_at(near2.x, near2.y):
				# Out on deep water (the swamp king): the nearest ground to it.
				return shore_near(near2.x, near2.y)
			return Vector2(near2.x, near2.y)
		return Vector2(exit.x, exit.y)
	# Hickston: the same steps objective() names. The pin used to point at the
	# sheriff from the start, through the locked barn, while the words said to
	# fetch the brass key.
	var boss_up: bool = boss != null and boss.alive
	var jerry_up: bool = jerry != null and jerry.alive
	if not boss_up and not jerry_up:
		return Vector2(bessie.x, bessie.y) if bessie != null and bessie.hp > 0.0 else null
	if jerry_up and not jerry.dormant:
		return Vector2(jerry.x, jerry.y)
	if not keys.has("key_steel"):
		var wanted := "key_steel" if keys.has("key_brass") else "key_brass"
		for entry: Array in pickups:
			if String(entry[0]) == wanted:
				return Vector2(float(entry[1]), float(entry[2]))
	if boss_up:
		return Vector2(boss.x, boss.y)
	return Vector2(jerry.x, jerry.y)


## Where the objective pin points: four steps along the walk to `target`, and
## how many steps the whole walk is (-1 when it cannot be walked).
func objective_route(target: Vector2) -> Array:
	if route == null:
		return [target, -1]
	var opened := 0
	for door: LevelData.Door in world.doors:
		if door.opened:
			opened += 1
	var sig := [stations_done.size(), keys.size(), opened]
	if sig != route_sig:
		# A door opened or a key was found: the way may be different now.
		route_sig = sig
		route.origin = Vector2i(-1, -1)
		route.next_at = 0.0
	route.update(target.x, target.y, clock)
	var steps := route.distance(player.x, player.y)
	if steps >= FlowField.FAR:
		return [target, -1]
	return [route.waypoint(player.x, player.y, 4), steps]


func gate_prompt() -> String:
	var gate = portal_target()
	if gate != null:
		return gate_text(gate)
	var clue = hub_clue() if in_hub else null
	return "E  " + String(clue[3]) if clue != null else ""

# ---------------------------------------------------------------- feedback
