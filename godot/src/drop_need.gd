## What a fallen hand leaves leans toward what the player who downed it is
## short of (pass 15): when a kind's drop comes up, the pick is the kind's
## own drop while that is any use to them, else (`need_share` of the time) food
## when they are hurt under `need_health`, or rounds for the gun they own
## with the least left (under `need_full` of what it holds and carries).
## The roll is the one the drop already made (the same dice as before);
## an always-drop's is set by the hand's uid (no dice). Numbers in
## enemies.cfg [all]: need_share (0: the kind's own, as before), need_health,
## need_full, need_food. Campaign and co-op only (County Run and the versus
## modes drop as they did). The director's breather pickup uses `wanted()`.
class_name DropNeed
extends RefCounted

## The first ammo pickup (hits.cfg [ammo] order) that fills each gun.
static var _fills := {}


## [all] `key` of enemies.cfg (read each time: a drop is rare, and a change
## saved while the game runs from the project folder is used at once).
static func _num(key: String) -> float:
	var v: float = Tuning.file(Tuning.ENEMIES).get_value("all", key, 0.0)
	return v


static func on(game: Game) -> bool:
	var mode := Modes.mode_of(game)
	return _num("need_share") > 0.0 and (mode == Modes.CAMPAIGN or mode == Modes.COOP)


## An always-drop's roll in [0, 1), from the hand's uid.
static func even(uid: int) -> float:
	return fposmod(uid * .6180339887, 1.0)


## What a drop of `own` becomes for the acting player, on `roll` in [0, 1).
static func pick(game: Game, own: String, roll: float) -> String:
	if not on(game) or _useful(game, own) or roll >= _num("need_share"):
		return own
	var want := wanted(game)
	return own if want == "" else want


## What the acting player is shortest of: food when hurt, else the ammo
## of the gun with the least left; "" when they want for nothing.
static func wanted(game: Game) -> String:
	var food: String = Tuning.file(Tuning.ENEMIES).get_value("all", "need_food", "")
	if game.player.health < _num("need_health") and food != "":
		return food
	var a := game.armory
	var best := ""
	var least := _num("need_full")
	for slot in Weapons.COUNT:
		var share := _share(a, slot)
		if share < least:
			var fill := ammo_for(slot)
			if fill != "":
				least = share
				best = fill
	return best


## The share of what gun `slot` holds and carries that is left (2: not a gun
## that takes rounds the player owns).
static func _share(a: Weapons.Armory, slot: int) -> float:
	if not a.owned[slot] or Weapons.MELEE.has(slot):
		return 2.0
	var most := roundi(a.num(slot, "max_reserve"))
	if most <= 0:
		return 2.0
	var capacity: int = Weapons.CAPACITY[slot]
	return float(a.loaded[slot] + a.reserve[slot]) / float(most + capacity)


## The pickup that fills gun `slot` ("" none).
static func ammo_for(slot: int) -> String:
	if _fills.is_empty():
		for name: String in GameState.AMMO:
			var row: Array = GameState.AMMO[name]
			var gun: int = row[0]
			if not _fills.has(gun):
				_fills[gun] = name
	return str(_fills.get(slot, ""))


## Whether `own` is any use to the acting player now: rounds for a gun they
## own that is not near full, or food while they are hurt.
static func _useful(game: Game, own: String) -> bool:
	if HUD.ITEMS.has(own):
		return game.player.health < _num("need_health")
	if not GameState.AMMO.has(own):
		return true
	var row: Array = GameState.AMMO[own]
	var gun: int = row[0]
	return _share(game.armory, gun) < _num("need_full")
