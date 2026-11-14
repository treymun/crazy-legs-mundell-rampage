## COUNTY RUN: one player, one big map, enemies that never stop coming
## (CLAUDE.md "County Run"). Survival time is the score; death ends the run.
##
## The run starts at level 1 with the .38 and the crowbar in two of three
## slots. Kills drop XP to walk over (county_orbs.gd); each level up offers
## three cards (county_build.gd), every tenth three big ones, and the world
## holds still while they are on screen (holds()). The spawner
## (county_spawner.gd) keeps the pressure building whatever the player does;
## the upgrades and milestone abilities act through the hooks below and
## county_moves.gd. The state is the county feature's
## (features/county_run.gd). Never saved; records go to their own file
## (county_records.gd).
class_name CountyMode
extends GameMode


func id() -> String:
	return Modes.COUNTY


## The county feature of a game in a run (null otherwise).
static func run(game):
	var f = game.features.get("county") if game != null else null
	return f if f != null and f.on else null


static func active(game) -> bool:
	return game != null and Modes.mode_of(game) == Modes.COUNTY


func start(game, _st) -> void:
	var f = game.features["county"]
	Modes.clear_enemies(game)
	game.pickups.clear()
	game.supply_rule = 2
	# Every door stands open: the horde comes through, and so do you.
	for door: LevelData.Door in game.world.doors:
		if not door.secret:
			door.opened = true
			door.progress = 1.0
	f.on = true
	f.map_id = game.level.id
	f.level = 1
	f.xp = 0
	CountyBuild.start_kit(game, f)
	var p: Player = game.player
	p.health = int(CountyData.number("start", "health", 100))
	for item in HUD.ITEMS:
		game.inventory[item] = 0
	CountySpawner.begin(game, f)
	# Tips on the cards for a player's first three runs (any map).
	var runs := 0
	for rec in CountyRecords.read().values():
		runs += int(rec.get("runs", 0)) if rec is Dictionary else 0
	f.tips = runs < 3
	game.spawn_grace = 0.0
	Modes.say(
		game, "%s. SURVIVE." % String(CountyData.map(f.map_id).get("title", "COUNTY RUN")), 3.0
	)


## Every tick of a run (the county feature's): the clock, the spawner, XP
## and supplies, the abilities, then the next choice when a level came.
static func step(game, f, dt: float) -> void:
	f.run_time += dt
	if not game.pickups.is_empty():
		# The level's and the hands' own drops are the run's own supplies now.
		game.pickups.clear()
	CountySpawner.tick(game, f, dt)
	CountyOrbs.tick(game, f, dt)
	CountyMoves.tick(game, f, dt)
	if not f.pending.is_empty() and f.offer.is_empty():
		f.offer = CountyBuild.offers(game, f, f.pending[0])


## Gains `amount` XP: level ups queue a choice each, in order (every tenth a
## milestone), the gun in hand remembered.
static func gain(game, f, amount: int) -> void:
	f.xp += amount
	f.xp_total += amount
	var came := 0
	while f.xp >= CountyData.xp_to_next(f.level):
		f.xp -= CountyData.xp_to_next(f.level)
		f.level += 1
		came += 1
		f.pending.append([f.level, f.level % 10 == 0, game.armory.active])
	if came > 0:
		if f.offer.is_empty():
			f.offer = CountyBuild.offers(game, f, f.pending[0])
		var big := false
		for entry: Array in f.pending:
			big = big or bool(entry[1])
		game.sound.play("victory" if big else "fair_score", .9)
		Modes.say(
			game,
			("LEVEL %d!" % f.level) if came == 1 else "LEVEL %d! (%d LEVELS)" % [f.level, came],
			2.0
		)


## The player picks card `index` of the offer (slot: where a weapon goes when
## every slot is full; -1 the open one). False when that is not possible.
static func choose(game, index: int, slot := -1) -> bool:
	var f = run(game)
	if f == null or f.offer.is_empty() or index < 0 or index >= f.offer.size():
		return false
	var c: Dictionary = f.offer[index]
	if String(c["type"]) == "weapon" and CountyBuild.open_slot(f) < 0 and slot < 0:
		return false
	CountyBuild.take(game, f, c, slot)
	f.pending.pop_front()
	f.offer = []
	if not f.pending.is_empty():
		f.offer = CountyBuild.offers(game, f, f.pending[0])
	game.sound.play("weapon_pickup" if String(c["type"]) == "weapon" else "menu_accept", .8)
	return true


func holds(game) -> bool:
	var f = run(game)
	return f != null and (not f.pending.is_empty() or f.paused) and not f.over


func downed(game, _st, p: Player, _by: int) -> void:
	var f = run(game)
	if f == null or f.over:
		return
	f.over = true
	f.pending.clear()
	f.offer = []
	f.result = {
		"map": f.map_id,
		"time": f.run_time,
		"level": f.level,
		"kills": game.kills,
		"build": CountyBuild.summary(f),
		"elites": f.elites_down,
		"xp": f.xp_total,
		"hurt": roundi(f.hurt),
		"streak": f.best_streak,
	}
	f.result["best_before"] = CountyRecords.finish(f.result)
	p.down_at = game.clock


# ------------------------------------------------------------------ hooks


## USE: MUDSLIDE when the run has it.
func use(game) -> bool:
	var f = run(game)
	return f != null and CountyMoves.dash(game, f)


func use_prompt(_game) -> String:
	return ""


func move_scale(game, p: Player) -> float:
	var f = run(game)
	if f == null or p != game.players[0]:
		return 1.0
	var scale := 1.0 + CountyBuild.perk_value(f, "good_boots")
	if game.clock < f.burst_until:
		scale += float(CountyData.milestone("breakaway").get("speed", .3))
	return scale


## A hit on the player as it lands: SECOND WIND, LAST STAND's guard, THICK
## HIDE and IRON GUT, then GRIT ARMOR takes what it can.
func incoming(game, p: Player, amount: float, _cause: String) -> float:
	var f = run(game)
	if f == null or f.over:
		return amount
	if game.clock < f.safe_until:
		return 0.0
	var share := 1.0 - CountyBuild.perk_value(f, "thick_hide")
	share -= (
		float(CountyData.milestone("iron_gut").get("per", .1))
		* CountyBuild.milestone_rank(f, "iron_gut")
	)
	if game.clock < f.guard_until:
		share *= 1.0 - float(CountyData.milestone("last_stand").get("guard", .5))
	amount *= maxf(.2, share)
	if f.armor > 0.0:
		var soaked := minf(f.armor, amount)
		f.armor -= soaked
		amount -= soaked
	if amount >= float(p.health) and CountyBuild.has(f, "second_wind") and not f.second_wind_used:
		CountyMoves.second_wind(game, f, p)
		return 0.0
	f.hurt += minf(amount, float(p.health))
	return amount


func shot_tuning(game, _p: Player, gun: int, spread: Vector2, reach: float) -> Array:
	var f = run(game)
	if f == null:
		return [spread, reach]
	return [spread * CountyBuild.spread_scale(f, gun), reach]


func hit_reach(game, reach: float) -> float:
	var f = run(game)
	var gun: int = game.armory.active
	if f == null or CountyData.kind_of(gun) != CountyData.MELEE:
		return reach
	return reach * CountyBuild.reach_scale(f, gun)


func hit_amount(game, e: Enemy, amount: float, d: float) -> float:
	var f = run(game)
	return amount if f == null else CountyMoves.hit_amount(game, f, e, amount, d)


func hit_after(game, e: Enemy, amount: float, d: float, ax: float, ay: float, slope: float) -> void:
	var f = run(game)
	if f != null:
		CountyMoves.hit_after(game, f, e, amount, d, ax, ay, slope)


## A blast's reach, strength and the share added near its middle, for the
## player's own explosives (PACKED CHARGE, SHAPED CHARGE, HOT LOADS).
func blast_tuning(game, shot, radius: float, strength: float) -> Array:
	var f = run(game)
	if f == null:
		return [radius, strength, 0.0, 0.0]
	# Whose blast this is, for CHAIN REACTION's kills (county_moves.gd).
	f.blast_mine = not shot.enemy and shot.kind != "fuel" and shot.owner != -1
	if f.blast_mine:
		CountyMoves.blast_began(f, String(shot.kind))
	if not f.blast_mine:
		return [radius, strength, 0.0, 0.0]
	return CountyMoves.blast_tuning(game, f, shot, radius, strength)


## The player's own blast on themselves: BLAST PADDING.
func blast_damage(game, thrower: Player, victim: Player, amount: float, kind: String) -> float:
	var f = run(game)
	if f == null or thrower != victim:
		return amount
	var gun := CountyMoves.gun_of_shot(kind)
	var pad := CountyBuild.value(f, gun, "blast_padding") if gun >= 0 else 0.0
	return amount * maxf(.1, 1.0 - pad)
