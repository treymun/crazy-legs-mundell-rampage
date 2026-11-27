## Co-op: the campaign for two to four players (CLAUDE.md "Modes").
##
## Shared: keys and the PA patch lead (Players.SHARED), stations, doors,
## kills, the objective. Each player's own: place, health, guns and rounds,
## pockets (rinds, beer...). A gun or an ammo pickup is given to EVERY player
## up (each gets what the toucher got: the extra hands below eat it); pocket
## items go to whoever takes them.
##
## A player brought to 0 is DOWN, not dead: a partner holding USE within
## REVIVE_REACH for REVIVE_TIME seconds stands them up with REVIVE_HEALTH;
## left alone RESPAWN_AFTER seconds they come back beside the nearest partner
## up with RESPAWN_HEALTH, guns kept. The game is lost only when everyone is
## down at once. A partner's bullets pass through you; their blasts bite at
## FRIENDLY_BLAST (your own in full). Bodies block each other. Reaching the
## exit ends the chapter for the whole party (anyone down comes along with
## REVIVE_HEALTH), and the next chapter starts with each player's own kit.
##
## The county scales with the party (SCALE, by players): its hands' health,
## the bosses' health, and a partner beside every n-th hand about at the
## start (as the posse does on HARD; saved with the posse's).
class_name CoopMode
extends GameMode

static var REVIVE_REACH: float = ModeData.get_value("coop", "revive_reach", 1.3)
static var REVIVE_TIME: float = ModeData.get_value("coop", "revive_time", 3.0)
static var REVIVE_HEALTH: int = ModeData.get_value("coop", "revive_health", 35)
static var RESPAWN_AFTER: float = ModeData.get_value("coop", "respawn_after", 20.0)
static var RESPAWN_HEALTH: int = ModeData.get_value("coop", "respawn_health", 50)
static var FRIENDLY_BLAST: float = ModeData.get_value("coop", "friendly_blast", .5)
## players -> [hands' health x, bosses' health x, a partner beside every n-th
## hand about at the start (0: none)].
static var SCALE: Dictionary = ModeData.get_value("coop", "scale", {})


func id() -> String:
	return Modes.COOP


static func scale_for(count: int) -> Array:
	return SCALE[clampi(count, 1, Modes.MAX_FREE_FOR_ALL)]


func start(game: Game, st: ModeFeature) -> void:
	var table := scale_for(_party_size(game))
	var step: int = table[2]
	if step > 0:
		var count := 0
		for i in mini(game.enemy_ids.size(), game.enemies.size()):
			var anchor: Enemy = game.enemies[i]
			if not anchor.tactical() or anchor.dormant or not anchor.alive:
				continue
			count += 1
			if count % step != 0:
				continue
			var spot := _beside(game, anchor)
			if spot.x == INF:
				continue
			var extra := Enemy.new(anchor.kind, spot.x, spot.y, anchor.angle + .6)
			extra.flank = -anchor.flank
			game.enemies.append(extra)
			game.total_kills += 1
	st.scaled_upto = 0
	scale_new(game, st)


## Health scaled on every enemy that has come along since the last look (the
## level's own and the extras at the start; a boss's backup, Maw's crew).
static func scale_new(game: Game, st: ModeFeature) -> void:
	var count := _party_size(game)
	var table := scale_for(count)
	var already := mini(st.scaled_upto, game.enemies.size())
	if st.scaled_party != count:
		var prior := scale_for(st.scaled_party)
		for i in already:
			var e: Enemy = game.enemies[i]
			_scale_health(e, _multiplier(e, table) / _multiplier(e, prior))
		st.scaled_party = count
	for i in range(already, game.enemies.size()):
		var e: Enemy = game.enemies[i]
		_scale_health(e, _multiplier(e, table))
	st.scaled_upto = game.enemies.size()


static func _party_size(game: Game) -> int:
	var count := 0
	for p: Player in game.players:
		if not p.away:
			count += 1
	return maxi(1, count)


static func _multiplier(e: Enemy, table: Array) -> float:
	return table[1 if Enemy.BOSS_TITLES.has(e.kind) else 0]


static func _scale_health(e: Enemy, times: float) -> void:
	if e.hostile:
		e.max_hp *= times
		e.hp *= times


## A save brought back scaled current health and unscaled maximum health.
static func rescale_loaded(game: Game, st: ModeFeature) -> void:
	var table := scale_for(st.scaled_party)
	for i in mini(st.scaled_upto, game.enemies.size()):
		var e: Enemy = game.enemies[i]
		if e.hostile:
			e.max_hp *= _multiplier(e, table)
	if st.started:
		scale_new(game, st)


func _beside(game: Game, anchor: Enemy) -> Vector2:
	for reach: float in [1.1, 1.6, 2.2]:
		for k in 8:
			var a := k * TAU / 8.0 + .9
			var x := anchor.x + cos(a) * reach
			var y := anchor.y + sin(a) * reach
			if not game.world.blocked(x, y, anchor.radius + .05):
				return Vector2(x, y)
	return Vector2(INF, INF)


func tick(game: Game, st: ModeFeature, dt: float) -> void:
	scale_new(game, st)
	for p: Player in game.players:
		if p.away:
			continue  # left an online game: out of play until someone takes the slot
		if p.health > 0:
			if p.down_at >= 0.0:
				p.down_at = -1.0
				p.revive = 0.0
			continue
		if p.down_at < 0.0:
			p.down_at = game.clock
		var helper := _helper(game, p)
		if helper != null:
			p.revive += dt
			if p.revive >= REVIVE_TIME:
				_revived(game, st, p, helper)
		else:
			p.revive = maxf(0.0, p.revive - dt * .5)
			if game.clock - p.down_at >= RESPAWN_AFTER and Players.anyone_alive(game):
				respawn(game, st, p)


## A partner up, within reach and holding USE over the downed player `p`.
static func _helper(game: Game, p: Player) -> Player:
	for q: Player in game.players:
		if q == p or q.health <= 0 or q.away or not q.holding:
			continue
		if _can_reach(game, q, p):
			return q
	return null


## Both the action and its prompt use the same floor-aware reach test.
static func _can_reach(game: Game, helper: Player, down: Player) -> bool:
	var a := Vector3(helper.x, helper.y, game.world.stand(helper) + helper.air)
	var b := Vector3(down.x, down.y, game.world.stand(down) + down.air)
	return (
		absf(a.z - b.z) <= .65
		and a.distance_to(b) < REVIVE_REACH
		and game.world.visible(a.x, a.y, b.x, b.y, a.z + .65, b.z + .35)
	)


## The downed partner nearest `p` (null when nobody is), for a revive prompt.
static func downed_near(game: Game, p: Player) -> Player:
	var best: Player = null
	var gap := REVIVE_REACH
	for q: Player in game.players:
		if q == p or q.health > 0 or q.away:
			continue
		var d := Vector2(q.x - p.x, q.y - p.y).length()
		if d < gap and _can_reach(game, p, q):
			gap = d
			best = q
	return best


func _revived(game: Game, st: ModeFeature, p: Player, helper: Player) -> void:
	Modes.stand_up(game, p, REVIVE_HEALTH)
	st.revives += 1
	game.sound_at("key_pickup", p.x, p.y, .8)
	if p == game.local_player:
		Modes.say(game, "%s GOT YOU UP. GIT BACK IN THERE." % Modes.tag(helper))
	else:
		Modes.say(game, "%s IS BACK ON THEIR FEET." % Modes.tag(p))


func downed(game: Game, _st: ModeFeature, p: Player, _by: int) -> void:
	if not Players.anyone_alive(game):
		return
	if p != game.local_player:
		Modes.say(game, "%s IS DOWN! HOLD %s BESIDE THEM." % [Modes.tag(p), game.use_key], 3.0)


func respawn(game: Game, _st: ModeFeature, p: Player) -> void:
	var near := Players.nearest(game, p.x, p.y)
	if near == null:
		return
	var at := Modes.open_spot_near(game, near.x, near.y)
	Modes.place(game, p, at.x, at.y, near.angle)
	Modes.stand_up(game, p, RESPAWN_HEALTH)
	if p == game.local_player:
		Modes.say(game, "BACK IN IT BESIDE %s." % Modes.tag(near))


func hurt_scale(_game: Game, attacker: Player, victim: Player, blast: bool) -> float:
	if attacker == victim:
		return 1.0
	return FRIENDLY_BLAST if blast else 0.0


## The toucher got a gun or rounds: every other player up gets the same.
func pickup(game: Game, _st: ModeFeature, name: String) -> void:
	name = str(GameState.ALIAS.get(name, name))
	var gun := Weapons.NAMES.find(name)
	if gun < 0 and not GameState.AMMO.has(name):
		return
	var taker: Player = game.player
	var own: bool = game.own_step
	for q: Player in game.players:
		if q == taker or q.health <= 0:
			continue
		game.focus(q, true)
		if gun >= 0:
			q.armory.pickup(gun, game)
		else:
			var entry: Array = GameState.AMMO[name]
			var amount: int = entry[1]
			if game.supply_rule == 1:
				amount = maxi(1, roundi(amount * .70))
			amount = maxi(1, roundi(amount * game.ammo_scale))
			var ammo_gun: int = entry[0]
			q.armory.add_ammo(ammo_gun, amount)
			if name == "dynamite":
				q.armory.owned[Weapons.DYNAMITE] = true
	game.focus(taker, own)


## The chapter is won: anyone down comes along, on their feet.
func won(game: Game, _st: ModeFeature) -> void:
	for p: Player in game.players:
		if p.health <= 0 and not p.away:
			Modes.stand_up(game, p, REVIVE_HEALTH)
