## Messages, sound, damage, pickups, waves, doors, stations, the use key
## (game_use.gd) and the objective (game_objective.gd) (the game layers are
## listed in game_state.gd).
class_name GameWorld
extends GameState

## The mode feature (features/mode_feature.gd, id "mode"), as a type (a
## constant here, not on GameState: snapshots walk GameState's constants).
const ModeFeature := preload("res://src/features/mode_feature.gd")
## The vehicles feature's script (features/vehicles.gd), to type features["vehicles"].
const VehiclesScript := preload("res://src/features/vehicles.gd")
## The hound's script (features/hound.gd), to type features["hound"].
const HoundScript := preload("res://src/features/hound.gd")
## The junk bench's (features/bench.gd), to type features["bench"].
const BenchScript := preload("res://src/features/bench.gd")

# --------------------------------------------------------------- loadout


func loadout() -> Dictionary:
	return {
		"health": player.health,
		"owned": armory.owned.duplicate(),
		"loaded": armory.loaded.duplicate(),
		"reserve": armory.reserve.duplicate(),
		"active": armory.active,
		"inventory": inventory.duplicate(),
		"slot": inventory_slot,
		"scrap": armory.scrap,
		"mods": armory.mods.duplicate()
	}


func apply_loadout(kit: Dictionary) -> void:
	player.health = kit["health"]
	var owned: Array = kit["owned"]
	var loaded: Array = kit["loaded"]
	var reserve: Array = kit["reserve"]
	for i in mini(Weapons.COUNT, owned.size()):
		var own: bool = owned[i]
		armory.owned[i] = own
		var rounds: int = loaded[i]
		armory.loaded[i] = rounds
		var spare: int = reserve[i]
		armory.reserve[i] = spare
	armory.active = kit["active"]
	var bag: Dictionary = kit["inventory"]
	inventory = bag.duplicate()
	inventory_slot = kit["slot"]
	# The junk bench's (a kit from before it has none).
	var scrap: int = kit.get("scrap", 0)
	armory.scrap = scrap
	var mods: Array = kit.get("mods", [])
	var kept: Array[String] = []
	for id: Variant in mods:
		kept.append(str(id))
	armory.mods = kept


func result() -> Array:
	return [level.id, kills, total_kills, secrets, total_secrets, int(clock)]


func configure(options: Dictionary) -> void:
	var picked: int = options.get("difficulty", 1)
	difficulty = clampi(picked, 0, 3)
	incoming = Difficulty.at("player", "incoming", difficulty)
	sharpness = Difficulty.at("hands", "sharpness", difficulty)
	ammo_scale = Difficulty.at("player", "ammo_scale", difficulty)
	var bob: float = options.get("bob", 100)
	bob_scale = bob / 100.0
	var flashes: int = options.get("flashes", 0)
	flash_scale = [1.0, .32, 0.0][clampi(flashes, 0, 2)]
	gore = options.get("gore", 1)
	finish_slowmo = options.get("finish_slowmo", 1)
	View.ragdolls = options.get("ragdolls", 1)
	aim_assist = options.get("aim_assist", 0)
	smart_hands = options.get("smart_hands", 1)
	hit_feedback = options.get("hit_feedback", 1)
	var feel: int = options.get("weather", 0)
	weather_feel = [1.0, .5, 0.0][clampi(feel, 0, 2)]
	storm_on = options.get("county_storm", 1)
	adaptive = options.get("adaptive", 1)
	boss_wrecks = options.get("boss_wrecks", 1)
	# Absent (an older replay, a tool): no hound, as play was before him.
	var hounding: int = options.get("hound", 0)
	hound_on = hounding == 1
	var benching: int = options.get("bench", 0)
	bench_on = benching == 1
	# Absent (an older replay, a tool): no events, as play was before them.
	var eventful: int = options.get("events", 0)
	events_on = clampi(eventful, 0, 2)
	var cussing: int = options.get("chatter", CussLines.CUSSIN)
	chatter = clampi(cussing, 0, 2)
	var fov: int = options.get("fov", 0)
	View.fov_focal = View.FOCAL_FOR[clampi(fov, 0, 3)]
	View.base_focal = View.fov_focal
	var shaking: int = options.get("shake", 2)
	shake_scale = [0.0, .5, 1.0][clampi(shaking, 0, 2)]
	district_labels = options.get("district_labels", 1)
	hints = options.get("hints", 1)
	tips = options.get("tips", 1)
	hud_style = options.get("hud_style", 0)
	var tint: int = options.get("crosshair_color", 0)
	crosshair_tint = [
		Color8(188, 168, 132),
		Color8(251, 183, 98),
		Color8(160, 236, 92),
		Color8(240, 64, 48),
		Color8(255, 255, 255)
	][clampi(tint, 0, 4)]
	view.world_motion = options.get("world_motion", 0)
	weapon_view = options.get("weapon_view", 0)
	voice_captions = options.get("voice_captions", 1)
	bullet_marks = options.get("bullet_marks", 1)
	retro_look = options.get("film_look", 0)
	var detail: int = options.get("detail", 0)
	var far: int = options.get("draw_distance", 0)
	view.draw_far = View.draw_far_for(far)
	if detail == 1 or (detail == 2 and View.auto_low):
		view.set_detail(1)
	else:
		view.set_detail(-1 if detail == 3 else 0)
	flicker = options.get("flicker", 1)
	armory.auto_switch = options.get("auto_switch", 1)
	armory.auto_reload = options.get("auto_reload", 1)
	var barking: bool = options.get("barks", 1)
	var enabled := barking and not barks_off_by_code
	barks.enabled = enabled


## Shows a notice on the HUD: the local player's only (another player's
## pickups and doors say nothing here).
func message(text: String, length := 1.9) -> void:
	if own_step and player != local_player:
		return
	notice = text
	message_until = clock + maxf(length, .70 + .16 * text.split(" ", false).size())


# ----------------------------------------------------------------- sound


## How loud and where a sound from (x, y) reaches the local player's ears:
## farther counting height, cut by walls and floors between (Hearing).
func sound_position(x: float, y: float, strength := 1.0, muffle := true) -> Vector2:
	var p := local_player
	var me: Game = self as Object
	var dx := x - p.x
	var dy := y - p.y
	var across := sqrt(dx * dx + dy * dy)
	var up := hearing.rise(me, x, y)
	var distance := sqrt(across * across + up * up)
	var volume := strength / (1.0 + distance * .22)
	if muffle and distance > 1.0:
		volume *= hearing.gain(me, x, y)
	var pan := (-sin(p.view_angle()) * dx + cos(p.view_angle()) * dy) / maxf(1.0, across)
	return Vector2(volume, pan)


## How dull a sound from x, y reaches the player: muffled through a wall or
## a floor, less round a corner (Hearing), a little duller far off or behind
## (a pan alone cannot say behind).
func sound_cutoff(x: float, y: float) -> float:
	var p := local_player
	var me: Game = self as Object
	var dx := x - p.x
	var dy := y - p.y
	var up := hearing.rise(me, x, y)
	var distance := sqrt(dx * dx + dy * dy + up * up)
	if distance <= 1.0:
		return Sound.OPEN_CUTOFF
	var cutoff := Sound.OPEN_CUTOFF / (1.0 + maxf(0.0, distance - 6.0) * .12)
	var facing := (cos(p.view_angle()) * dx + sin(p.view_angle()) * dy) / distance
	if facing < -.3:
		cutoff = minf(cutoff, 9000.0)
	return minf(hearing.cutoff(me, x, y), maxf(2500.0, cutoff))


func sound_at(name: String, x: float, y: float, strength := 1.0, rate := 1.0) -> void:
	if host:
		return
	var place := sound_position(x, y, strength)
	speaker.play_at_rate(name, place.x, place.y, sound_cutoff(x, y), rate)
	var p := local_player
	if name != "bessie" and world.roof[int(p.y) * level.width + int(p.x)] != 0.0:
		if speaker.has("room_" + name):
			speaker.play("room_" + name, place.x * .55, place.y)


## sound_at tied to mover `from` (a Doppler key: a ride, a lap car): its
## pitch follows how fast that comes or goes for as long as it plays.
func sound_from(from: int, name: String, x: float, y: float, strength := 1.0, rate := 1.0) -> void:
	var node: Sound = null if host or speaker == null else speaker.node()
	if node != null:
		node.doppler.next_from = from
	sound_at(name, x, y, strength, rate)
	if node != null:
		node.doppler.next_from = 0


func report(name: String) -> void:
	if not acting_local():
		# Another player's gun: heard from where they stand.
		sound.play(name)
		return
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
	var me: Game = self as Object
	for enemy: Enemy in enemies:
		var distance := sqrt((enemy.x - x) * (enemy.x - x) + (enemy.y - y) * (enemy.y - y))
		if (
			enemy.alive
			and enemy.hostile
			and not enemy.alerted
			and distance < radius
			and (distance < 1.45 or world.visible(x, y, enemy.x, enemy.y))
		):
			enemy.wake(me, x, y)


func disturb(x: float, y: float, radius: float, z: Variant = null) -> void:
	var source: float = world.elevation(x, y) + .78 if z == null else z
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
		var ear: float = world.stand(actor) + actor.z + minf(.90, actor.height * .76)
		if not world.visible(x, y, actor.x, actor.y, source, ear):
			continue
		var ready: float = clock + .22 + sqrt(dx * dx + dy * dy) * .035
		actor.heard = [x, y, ready, clock + (2.6 if actor.hostile else 1.05)]
		if not actor.hostile:
			sound_at(Enemy.animal_voice(actor.brain), actor.x, actor.y, .43)


# ----------------------------------------------------------------- damage


## Hurts the acting player, or `who` (made the acting player meanwhile, so what
## listens to player_hurt hears it as theirs); the looks are the local player's.
func damage(amount: float, source: Variant = null, cause := "HIT", who: Player = null) -> void:
	if who != null and who != player:
		var was := player
		focus(who)
		damage(amount, source, cause)
		focus(was)
		return
	if player.health <= 0:
		return
	var p := player
	if cheats.god:
		return
	var me: Game = self as Object
	var mellow: float = (
		.10 * float(15 <= p.drunk and p.drunk <= 56) + .09 * float(16 <= p.gut and p.gut <= 64)
	)
	# ADAPTIVE DIFFICULTY is this machine's own history: one player only.
	var adapting := adaptive and players.size() == 1
	amount = maxf(
		1.0, round_even(amount * (1.0 - mellow) * incoming * (adapt if adapting else 1.0))
	)
	amount = Modes.incoming(me, p, amount, cause)  # a mode's armour (COUNTY RUN)
	var rides: VehiclesScript = features.get("vehicles")
	if rides != null and cause != "WRECK" and rides.seated(p):
		amount = maxf(1.0, round_even(rides.soak(p, amount)))  # the vehicle takes its share
	p.health = maxi(0, p.health - int(amount))
	events.player_hurt.emit(amount, cause)
	if p.health == 0 and adapting:
		adapt = maxf(.78, adapt - .07)
	if gallery != null and gallery.active and gallery.slot == p.slot:
		gallery.finish(me, "GALLERY CLOSED. CLEAR THE BOOTH AND RETRY.")
	if not acting_local():
		var grunt := "player_down" if p.health == 0 else "hurt" if amount > 6.0 else "blow_grunt"
		if speaker != null:
			sound_at(grunt, p.x, p.y, .9)
		return
	var heading: Variant = null
	if source != null:
		var from_y: float = source[1]
		var from_x: float = source[0]
		heading = atan2(from_y - p.y, from_x - p.x)
	damage_feedback = [heading, cause, clock + .64]
	hurt_flash = .27
	shake = minf(1.0, shake + minf(.55, amount / 40.0))
	set_face("ouch_shock", .32)
	barks.say(me, "low" if p.health <= 25 else "hurt")
	# A light knock is a grunt; a real wound the hurt cry.
	var cry := "hurt" if amount > 6.0 or p.health <= 25 else "blow_grunt"
	sound.play("player_down" if p.health == 0 else cry)
	if p.health == 0:
		message("YOU BOUGHT THE FARM.", 8.0)


## One of the player's hits landed (Enemy.hurt): mark the crosshair, tick, and
## hold the world still a moment on a kill or a heavy blow.
func struck(amount: float, killed: bool, champion: bool) -> void:
	events.hit_landed.emit(amount, killed)
	# The crosshair's mark is the local player's; the world's hold the one
	# player's game feel (it would stop everyone).
	if not hit_feedback or not acting_local():
		return
	if clock >= hit_mark_until:
		hit_mark_kill = false
		hit_mark_head = false
		hit_mark_at = clock
	hit_mark_until = maxf(hit_mark_until, clock + (.24 if killed else .12))
	hit_mark_kill = hit_mark_kill or killed
	if players.size() == 1 and clock >= hitstop_next and (killed or amount >= 40.0):
		hitstop = maxf(hitstop, .09 if killed and champion else .05 if killed else .03)
		hitstop_next = clock + .22
	if killed:
		sound.play("kill_tick", .55)
		hit_tick_next = clock + .06
	elif clock >= hit_tick_next:
		sound.play("hit_tick", .34)
		hit_tick_next = clock + .06


## A pickup lying at (x, y): [name, x, y, its stable id] (and the deck it lies
## on, level format 2).
func add_pickup(name: String, x: float, y: float, lift := NAN) -> void:
	pickups.append([name, x, y, take_uid()])
	if world.geo != null and not is_nan(lift):
		var on := world.floor_under(x, y, lift + .05)
		if on > world.elevation(x, y) + .01:
			var placed: Array = pickups[pickups.size() - 1]
			placed.append(on)


func collect(name: String) -> bool:
	var me: Game = self as Object
	name = str(ALIAS.get(name, name))
	if name.begins_with("scrap_"):
		# The junk bench's scrap (src/bench_mods.gd), on the taker's armory.
		var most: int = BenchMods.value("scrap", "most", 99)
		if armory.scrap >= most:
			return false
		armory.scrap = mini(most, armory.scrap + BenchMods.worth(name))
		message("SCRAP. %d IN THE POCKET." % armory.scrap, 1.2)
	elif Weapons.NAMES.has(name):
		armory.pickup(Weapons.NAMES.find(name), me)
		barks.say(me, "pickup_weapon", true)
		set_face("grin_rampage", .6)
	elif HUD.ITEMS.has(name):
		var have: int = inventory[name]
		if have >= 5:
			return false
		inventory[name] = have + 1
		message(str(PICKUP_NAMES[name]))
		barks.say(me, "pickup_food")
	elif TASK_ITEMS.has(name):
		task_items[name] = true
		message("PA PATCH LEAD. TAKE IT TO THE BACKSTAGE BOOTH.", 3.0)
	elif name.begins_with("key_"):
		keys[name] = true
		barks.say(me, "key", true)
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
		var slot: int = entry_ammo[0]
		var amount: int = entry_ammo[1]
		if supply_rule == 1:
			amount = maxi(1, roundi(amount * .70))
		amount = maxi(1, roundi(amount * ammo_scale))
		if not armory.add_ammo(slot, amount):
			return false
		if name == "dynamite" and not armory.owned[Weapons.DYNAMITE]:
			armory.owned[Weapons.DYNAMITE] = true
			message("DYNAMITE [8] - HOLD FIRE, RELEASE TO THROW", 3.5)
		else:
			message(str(PICKUP_NAMES[name]), 1.0)
	sound.play(
		(
			"key_pickup"
			if name.begins_with("key_") or TASK_ITEMS.has(name)
			else "weapon_pickup" if Weapons.NAMES.has(name) else "pickup"
		),
		.8
	)
	events.pickup_taken.emit(name)
	return true


## Each pocket item's sound and word as it goes down (HUD.ITEMS order; an
## online client shows them at its press, net_shot_predict.gd).
const ITEM_CUES := ["crunch", "gulp", "moonshine", "whiskey_glug", "cowpie_pick"]
const ITEM_WORDS := [
	"PORK RINDS. GOOD EATIN'.",
	"COLD BEER. EASY ON THE STEERING.",
	"THAT'LL PUT HAIR ON THE TRACTOR.",
	"WHISKEY. HAIR ON YER CHEST.",
	"COW PIE. DON'T ASK.",
]


func use_item(slot := -1) -> void:
	if slot >= 0:
		inventory_slot = slot
	var i := inventory_slot
	var name: String = HUD.ITEMS[i]
	var have: int = inventory[name]
	if have == 0:
		message("OUT OF " + str(HUD.ITEM_LABELS[i]) + ".", 1.05)
		return
	inventory[name] = have - 1
	var p := player
	var health := p.health
	var text := ""
	var state := ""
	if i == 0:
		p.gut = minf(100.0, p.gut + 37.0)
		p.health = mini(100, p.health + 28)
		if p.drunk > 52:
			p.drunk -= 13
		text = ITEM_WORDS[0]
		state = "FULL GUT" if p.gut >= 86 else ""
	elif i == 1:
		p.drunk = minf(100.0, p.drunk + 36.0)
		p.health = mini(100, p.health + 16)
		text = ITEM_WORDS[1]
		state = "WOBBLY" if p.drunk > 82 else "BUZZED"
	elif i == 3:
		p.drunk = minf(100.0, p.drunk + 55.0)
		p.health = mini(100, p.health + 34)
		text = ITEM_WORDS[3]
		state = "LOOSE" if p.drunk > 70 else "WARM"
	elif i == 4:
		p.gut = minf(100.0, p.gut + 48.0)
		p.drunk = maxf(0.0, p.drunk - 12.0)
		p.health = mini(100, p.health + 12)
		text = ITEM_WORDS[4]
		state = "FULL GUT" if p.gut >= 86 else ""
	else:
		p.drunk = maxf(0.0, p.drunk - 70.0)
		p.gut = maxf(0.0, p.gut - 55.0)
		p.health = mini(100, p.health + 24)
		sprint = 7.0
		text = ITEM_WORDS[2]
		state = "SPEED UP"
	var cue: String = ITEM_CUES[i]
	sound.play(cue)
	message(text)
	var change := "+%d HP" % (p.health - health) if p.health > health else ""
	var bits: Array = []
	if change != "":
		bits.append(change)
	if state != "":
		bits.append(state)
	if acting_local():
		item_feedback = [name, "  ".join(bits), clock + 1.05]


# --------------------------------------------------------------- movement


## Mirrors Game.move_actor: axis-separated world move with body separation, so
## the player cannot walk through a hostile actor (or an actor through them).
## (A hostile body keeps out of every player's way; a player out of the
## enemies'; players who are up out of each other's.) Any player may be the
## body, not only the acting one (a twister or the hogs shoving player two).
func move_actor(body: Variant, dx: float, dy: float, radius: float) -> void:
	var p := player
	if body is Player:
		p = body
	var neighbors: Array = []
	if body == p and body_cells_on:
		# (Several players: the bodies by cell, game.gd. Any of them blocks.)
		for cx in range(floori(p.x - 1.1), floori(p.x + 1.1) + 1):
			for cy in range(floori(p.y - 1.1), floori(p.y + 1.1) + 1):
				var cell_bodies: Variant = body_cells.get(cx * BODY_ROW + cy)
				if cell_bodies == null:
					continue
				var bodies: Array = cell_bodies
				for enemy: Enemy in bodies:
					if absf(p.x - enemy.x) < 1.1 and absf(p.y - enemy.y) < 1.1:
						neighbors.append(enemy)
	elif body == p:
		for enemy: Enemy in enemies:
			if (
				enemy.hostile
				and enemy.alive
				and absf(p.x - enemy.x) < 1.1
				and absf(p.y - enemy.y) < 1.1
			):
				neighbors.append(enemy)
	elif body.hostile:
		var bx: float = body.x
		var by: float = body.y
		for q: Player in players:
			if absf(bx - q.x) < 1.1 and absf(by - q.y) < 1.1:
				neighbors.append(q)
	# Players who are up block each other where the mode says (src/modes/).
	var mates: Array = []
	var me: Game = self as Object
	if body == p and players.size() > 1 and Modes.rules(me).bodies_block():
		for q: Player in players:
			if q != p and q.health > 0 and absf(p.x - q.x) < .6 and absf(p.y - q.y) < .6:
				mates.append(q)
	var occupied: Variant = null
	if not neighbors.is_empty():
		occupied = func(x: float, y: float) -> bool:
			for neighbor: Variant in neighbors:
				var enemy: Enemy = neighbor if body == p else body
				var them: Player = p if body == p else neighbor
				var enemy_base: float = world.stand(enemy) + enemy.z
				var player_base: float = world.stand(them) + them.air
				if enemy_base >= player_base + (.80 if them.crouched else 1.16):
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
	if not mates.is_empty():
		var bodies: Variant = occupied
		occupied = func(x: float, y: float) -> bool:
			var reach := PLAYER_RADIUS * 2.0
			for q: Player in mates:
				var d := (x - q.x) * (x - q.x) + (y - q.y) * (y - q.y)
				var was := (p.x - q.x) * (p.x - q.x) + (p.y - q.y) * (p.y - q.y)
				if d < reach * reach and d < was and absf(p.air - q.air) < 1.0:
					return true
			if bodies == null:
				return false
			var others: Callable = bodies
			return others.call(x, y)
	world.move(body, dx, dy, radius, occupied)


## A piece of floor opened (a barrel broken, a fence shot down): every
## player's flow field and the objective's route walk through it now.
func reopen_paths(x0: float, y0: float, x1: float, y1: float) -> void:
	for p: Player in players:
		p.flow.reopen(x0, y0, x1, y1)
	route.reopen(x0, y0, x1, y1)


# ------------------------------------------------------------------- death


func enemy_down(enemy: Enemy) -> void:
	var me: Game = self as Object
	kills += 1
	events.enemy_killed.emit(enemy)
	if enemy.hostile:
		barks.kill(me, enemy.last_zone == "head")
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
				actor.retreat_from(me, enemy.x, enemy.y)
				if sound == null or not sound.talking():
					# (a shout: quiet while anyone talks, as the barks are)
					sound_at("county_fall_back", actor.x, actor.y, .67)
				break
	var kind_def: Dictionary = Enemy.DEFS[enemy.kind]
	if enemy == boss and (jerry == null or jerry.hp <= 0.0):
		# The sheriff alone (a rematch): Hickston's end sting, no Jerry.
		message("THE SHERIFF'S DOWN. YEE-HAW!", 4.0)
		sound.play("yee_haw")
		sound.sting("shakedown_end")
	elif enemy == boss:
		jerry.dormant = false
		jerry.wake(me, player.x, player.y)
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
		for shot: Shot in shots:
			if shot.kind != "foreman_cut" and shot.kind != "rudy_horn":
				kept.append(shot)
		shots = kept
		var reward := str(kind_def.get("finale_drop", "bullets"))
		add_pickup(String(reward), enemy.x, enemy.y)
		message(
			str(Enemy.BOSS_TITLES.get(enemy.kind, "BOSS")) + " IS DOWN. CLEAR THE LAST VARMINTS.",
			3.0
		)
		sound.sting(enemy.kind + "_end")
	elif kind_def.has("drop"):
		# What it leaves (enemies.cfg): always, or by chance unless NO DROPS;
		# leaning to what the player is short of (src/drop_need.gd) on the
		# same roll (an always-drop's by its uid).
		var spec: Dictionary = Enemy.DEFS[enemy.kind]
		var chance: float = spec.get("drop_chance", 1.0)
		if chance >= 1.0:
			add_pickup(
				DropNeed.pick(me, str(spec["drop"]), DropNeed.even(enemy.uid)), enemy.x, enemy.y
			)
		else:
			var roll := rng.random()
			if roll < chance and supply_rule != 2:
				add_pickup(DropNeed.pick(me, str(spec["drop"]), roll / chance), enemy.x, enemy.y)
	if (
		enemy.hostile
		and not Enemy.BOSS_TITLES.has(enemy.kind)
		and supply_rule != 2
		and rng.random() < Enemy.LUCKY_CHANCE
	):
		add_pickup(str(rng.choice(HUD.ITEMS)), enemy.x + .2, enemy.y)
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


## The HUD face (the local player's: another player's grin is not ours).
func set_face(value: String, duration: float) -> void:
	if not acting_local():
		return
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


## GameUse.use_target (game_use.gd).
func use_target() -> Variant:
	var me: Game = self as Object
	return GameUse.use_target(me)


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
	var x: float = entry[1]
	var y: float = entry[2]
	var gap := (player.x - x) * (player.x - x) + (player.y - y) * (player.y - y)
	if gap >= .62 * .62:
		# Beyond either reach (every tick, for every pickup in the level).
		return false
	var name := str(entry[0])
	# On the player's own floor (format 2: not the deck over them).
	var lies: float = entry[4] if entry.size() > 4 else world.elevation(x, y)
	if world.geo != null and absf(world.stand(player) + player.air - lies) > .7:
		return false
	if name.begins_with("key_") or TASK_ITEMS.has(name):
		return gap < .62 * .62 and seen_at(Vector3(x, y, lies + .25))
	if world.geo != null:
		return gap < .43 * .43 and world.visible(player.x, player.y, x, y, player.eye, lies + .25)
	return gap < .43 * .43 and world.visible(player.x, player.y, x, y)


## GameUse.use_prompt (game_use.gd).
func use_prompt() -> String:
	var me: Game = self as Object
	return GameUse.use_prompt(me)


## GameUse.interact (game_use.gd).
func interact() -> void:
	var me: Game = self as Object
	GameUse.interact(me)


# ----------------------------------------------------------------- stations


func set_station_lights(station: LevelData.Station) -> void:
	lit_stations[station.id] = true
	for sector_v: Variant in station.sectors:
		var sector: int = sector_v
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
	for key: Variant in station.requires:
		if not stations_done.has(str(key)):
			message(objective(), 3.0)
			sound.play("empty")
			return
	stations_done[station.id] = true
	events.station_done.emit(station.id)
	var me: Game = self as Object
	barks.say(me, "station")
	set_station_lights(station)
	for door: LevelData.Door in world.doors:
		var point := Vector2i(door.x, door.y)
		var required: Variant = world.access_doors.get(point)
		var satisfied := false
		if required != null:
			satisfied = true
			for key: Variant in required:
				if not stations_done.has(str(key)):
					satisfied = false
					break
		if station.opens.has(point) or (satisfied and not door.opened):
			toggle_door(door, true)
	if station.reveals_secret:
		secrets += 1
	if world.extraction != null and station.id == world.extraction.shutdown:
		for enemy: Enemy in wave:
			enemy.dormant = false
			enemy.wake(me, player.x, player.y)
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
		var turns: int = valve_turns.get(station.id, 0) + 1
		if turns < 3:
			valve_turns[station.id] = turns
			sound_at("scenery_pipe", station.x, station.y, .67)
			message("CONDENSER VALVE  %d/3. KEEP TURNING." % turns, 2.0)
			return
		valve_turns.erase(station.id)
	activate_station(station)


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


func finish_level(cue: String) -> void:
	if not won:
		won = true
		events.level_won.emit()
		if adaptive and player.health >= 60 and not replay:
			adapt = minf(1.15, adapt + .05)
		shots.clear()
		hazards.clear()
		blasts.clear()
		specks.clear()
		sound.pause_world()
		sound.set_score("victory")
		sound.play(cue)


## GameUse.portal_target (game_use.gd).
func portal_target(reach := 2.62) -> Variant:
	var me: Game = self as Object
	return GameUse.portal_target(me, reach)


## GameUse.hub_clue (game_use.gd).
func hub_clue() -> Variant:
	var me: Game = self as Object
	return GameUse.hub_clue(me)


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
		var me: Game = self as Object
		barks.say(me, "secret")
		sound.play("yee_haw")


# ------------------------------------------------------------ projectiles


## Specks thrown from (x, y, z) off game.rng. `keep` false: the dice are
## spent but nothing is thrown. Specks are presentation (never carried), so
## with more than one player what this machine shows (its specks, its GORE
## setting) must never decide what game.rng spends: a copy put back on a
## snapshot keeps its own specks, and its dice would part from the host's.
func burst(
	x: float, y: float, z: float, kind: String, count: int, speed: float, keep := true
) -> void:
	if kind == "gore" and not gore:
		if players.size() < 2:
			return
		keep = false
	if blast_quiet:
		keep = false  # a blast this machine showed already (explode)
	if own_quiet and keep:
		# An online client's own shot it showed already (hands_watch.gd):
		# the dice go as ever, the specks are the watcher's to show or drop.
		hands_watch.held_burst(x, y, z, kind, count, speed)
		keep = false
	for _i in count:
		var angle := rng.random() * TAU
		var v := rng.uniform(.24, speed)
		var up := rng.uniform(.2, speed * 1.3)
		var life := rng.uniform(.18, .68)
		if keep:
			specks.append(Speck.new(x, y, z, cos(angle) * v, sin(angle) * v, up, life, kind))


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
	if finale != null:
		var ports_for: int = finale.get_note("ports_for", -1)
		if ports_for == attacks:
			var picked: Array = finale.get_note("ports")
			return picked.slice(0, mini(count, picked.size()))
	var offset := int(attacks / 2) % ports.size()
	var out: Array = []
	for i in count:
		out.append(ports[(offset + i) % ports.size()])
	return out


# -------------------------------------------------------------- ground marks


## GameObjective.objective (game_objective.gd).
func objective() -> String:
	var me: Game = self as Object
	return GameObjective.objective(me)


func objective_target() -> Variant:
	var me: Game = self as Object
	return GameObjective.objective_target(me)


## GameObjective.objective_route (game_objective.gd).
func objective_route(target: Vector2, target_z := NAN) -> Array:
	var me: Game = self as Object
	return GameObjective.objective_route(me, target, target_z)


## GameUse.gate_prompt (game_use.gd).
func gate_prompt() -> String:
	var me: Game = self as Object
	return GameUse.gate_prompt(me)

# ---------------------------------------------------------------- feedback
