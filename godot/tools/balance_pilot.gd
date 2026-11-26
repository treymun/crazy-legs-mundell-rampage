## The campaign bot (tools/bot_pilot.gd) with a player's skill, for the
## balance measurements (tools/balance.gd): it is slower to fire on a new
## foe, aims off by a little and turns no faster than its hand allows, and
## the better ones strafe in a fight, boot a hand up close (and finish one
## open to it) and eat when hurt. Its own dice, seeded per run: the game's
## game.rng is never touched. Its controls go through game.tick (as_controls).
extends "res://tools/bot_pilot.gd"

## The three players it can be: ROOKIE, REGULAR, SHARP.
const SKILLS := [
	{
		"name": "rookie",
		"react": 0.4,
		"err": 0.065,
		"cap": 0.1,
		"strafe": 0.0,
		"boots": false,
		"eat_at": 30,
		"forage": 6.0
	},
	{
		"name": "regular",
		"react": .3,
		"err": .05,
		"cap": .12,
		"strafe": .6,
		"boots": true,
		"eat_at": 40,
		"forage": 7.0
	},
	{
		"name": "sharp",
		"react": .15,
		"err": .025,
		"cap": .16,
		"strafe": .9,
		"boots": true,
		"eat_at": 50,
		"forage": 9.0
	}
]
## How much health each pocket item gives (game_world.gd use_item), in
## HUD.ITEMS order.
const HEALS := [28, 16, 24, 34, 12]
## Seconds it goes for one pickup before giving it up.
const FORAGE_FOR := 5.0

var skill: Dictionary = SKILLS[1]
var dice := RandomNumberGenerator.new()
var _seen: Enemy = null
var _seen_at := 0.0
var _off := 0.0
var _off_until := 0.0
var _side := 1.0
var _side_until := 0.0
var _boot_at := 0.0
var _ate_at := -9.0
## The pickup it is going for ([uid, x, y]) and when it gives up on it;
## the ones it gave up on.
var _going: Array = []
var _passed := {}
## Seconds spent going for each pickup (given up past FORAGE_FOR).
var _spent := {}
## The way's least steps to the objective lately, when it was reached and
## for which goal (no progress for a while: hop and turn, as a player would).
var _least := FlowField.FAR
var _least_at := 0.0
var _least_goal := Vector2.INF
## What it did (balance.gd reads them): items eaten, boots asked for.
var eaten := 0
var boots_asked := 0


func _init(level := 1, seed_value := 1) -> void:
	skill = SKILLS[clampi(level, 0, SKILLS.size() - 1)]
	dice.seed = seed_value * 7919 + level
	as_controls = true


func steer(game: Game) -> Game.Controls:
	var c := super.steer(game)
	var p := game.player
	if foe == null and around.is_empty():
		_forage(game, c)
	_dry(game, c)
	if foe != null:
		if foe != _seen:
			_seen = foe
			_seen_at = game.clock
		if game.clock >= _off_until:
			_off = dice.randfn(0.0, float(skill["err"]))
			_off_until = game.clock + dice.randf_range(.25, .5)
		var want := atan2(foe.y - p.y, foe.x - p.x) + _off
		var turn := fposmod(want - p.angle + PI, TAU) - PI
		var cap: float = skill["cap"]
		c.turn = clampf(turn, -cap, cap)
		c.fire = absf(turn) < .08 and game.clock - _seen_at >= float(skill["react"])
		var gap := Vector2(foe.x - p.x, foe.y - p.y).length()
		var strafe: float = skill["strafe"]
		if strafe > 0.0 and gap > 2.0:
			if game.clock >= _side_until:
				_side = -_side
				_side_until = game.clock + dice.randf_range(.6, 1.5)
			c.strafe = _side * strafe
		if bool(skill["boots"]) and gap < 1.5 and absf(turn) < .4 and game.clock >= _boot_at:
			var brawl: Object = game.features.get("brawl")
			var open: bool = brawl != null and bool(brawl.call("finishable", foe))
			# A finisher whenever one is open; the boot now and then (KICK,
			# pass 15: the boot alone, as a player has it).
			if open or dice.randf() < .35:
				c.kick = true
				boots_asked += 1
			_boot_at = game.clock + .7
	var eat_at: int = skill["eat_at"]
	if p.health > 0 and p.health < eat_at and game.clock - _ate_at > 1.0:
		var best := -1
		for i in HUD.ITEMS.size():
			var have: int = game.inventory.get(HUD.ITEMS[i], 0)
			if have > 0 and (best < 0 or HEALS[i] > HEALS[best]):
				best = i
		if best >= 0:
			c.item = best
			eaten += 1
			_ate_at = game.clock
	return c


## Nothing to shoot: a pickup it can use in sight and a straight walk away
## (rounds for a gun it has short, food, scrap, a gun) is gone for, as a
## player would step off the way for it.
func _forage(game: Game, c: Game.Controls) -> void:
	var p := game.player
	if not _going.is_empty():
		var uid_was: int = _going[0]
		_spent[uid_was] = float(_spent.get(uid_was, 0.0)) + STEP
		if float(_spent[uid_was]) > FORAGE_FOR:
			_passed[uid_was] = true
			_going = []
	var best: Array = []
	var reach: float = skill["forage"]
	for entry: Array in game.pickups:
		var uid: int = entry[3]
		if _passed.has(uid):
			continue
		var at := Vector2(float(entry[1]), float(entry[2]))
		var d := at.distance_to(Vector2(p.x, p.y))
		if d > reach or (not best.is_empty() and d >= float(best[3])):
			continue
		if not _wanted(game, str(entry[0])):
			continue
		# On its floor and on the way's walkable ground, not over a drop.
		if absf(game.world.elevation(at.x, at.y) - p.floor_z) > .5:
			continue
		if game.route.distance(at.x, at.y) >= FlowField.FAR:
			continue
		if not game.world.visible(p.x, p.y, at.x, at.y):
			continue
		if not _clear_walk(
			game.world, Vector2(p.x, p.y), at, GameState.PLAYER_RADIUS, p.floor_z + .35
		):
			continue
		best = [uid, at.x, at.y, d]
	if best.is_empty():
		_going = []
		return
	_going = best
	var aim := atan2(float(best[2]) - p.y, float(best[1]) - p.x)
	var turn := fposmod(aim - p.angle + PI, TAU) - PI
	c.turn = clampf(turn, -.12, .12)
	c.forward = 1.0 if absf(turn) < .9 else .2
	c.use = false


static func _wanted(game: Game, name: String) -> bool:
	if name.begins_with("scrap_"):
		return game.armory.scrap < 99
	if Weapons.NAMES.has(name):
		return true
	if HUD.ITEMS.has(name):
		return int(game.inventory.get(name, 0)) < 5
	if not GameState.AMMO.has(name):
		return false
	var entry: Array = GameState.AMMO[name]
	var slot: int = entry[0]
	var a := game.armory
	return a.owned[slot] and a.reserve[slot] < roundi(a.num(slot, "max_reserve"))


## After the tick: as the base bot, and when the way to the objective has
## not got shorter for a while with nothing to fight, hop (a step it cannot
## walk up) and after longer turn away a moment.
func moved(game: Game) -> void:
	super.moved(game)
	var goal: Variant = game.objective_target()
	if goal == null or foe != null:
		_least_at = game.clock
		return
	var at: Vector2 = goal
	var d := game.route.distance(game.player.x, game.player.y, game.world.stand(game.player))
	if at.distance_to(_least_goal) > .5 or d < _least:
		_least_goal = at
		_least = d
		_least_at = game.clock
		return
	var still := game.clock - _least_at
	if still > 4.0:
		stuck = maxf(stuck, .4)
	if still > 7.0:
		turn_away = dice.randf_range(.8, 1.6) * (1.0 if dice.randf() < .5 else -1.0)
		around = detour(game)
		around_until = game.clock + 4.0
		_least_at = game.clock - 4.0
		_least = d


## Out of rounds in the gun in hand: the next gun with some, else the blade
## or the crowbar (the base bot would cycle for ever), and a blade goes in
## close.
func _dry(game: Game, c: Game.Controls) -> void:
	var a := game.armory
	var p := game.player
	var melee := Weapons.MELEE.has(a.active)
	if c.cycle != 0:
		c.cycle = 0
		var pick := -1
		for offset in range(1, Weapons.COUNT):
			var slot := posmod(a.active + offset, Weapons.COUNT)
			if a.owned[slot] and not Weapons.MELEE.has(slot):
				if a.loaded[slot] > 0 or a.reserve[slot] > 0:
					pick = slot
					break
		if pick < 0:
			for slot: int in [Weapons.SLING, Weapons.CROWBAR]:
				if a.owned[slot]:
					pick = slot
					break
		if pick >= 0 and pick != a.active:
			c.weapon = pick
	if melee and foe != null:
		var gap := Vector2(foe.x - p.x, foe.y - p.y).length()
		c.forward = 1.0 if gap > 1.2 else 0.0
		c.strafe = 0.0
		c.fire = c.fire and gap < 1.9
	if melee:
		# A gun picked up since: back to it.
		for slot in Weapons.COUNT:
			if (
				a.owned[slot]
				and not Weapons.MELEE.has(slot)
				and a.loaded[slot] + a.reserve[slot] > 0
			):
				c.weapon = slot
				break
