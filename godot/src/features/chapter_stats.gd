## How the chapter went: shots fired and how many found a mark, damage taken,
## and kills with each gun. Built only from the game's events; saved with the
## chapter; its accuracy shows on the tally, and the console's `stats` prints
## the rest.
extends GameFeature

## A shot counts as landing when a hit comes within this long of it (a
## crossbow bolt or a bowling ball takes a moment to arrive).
const LANDS_WITHIN := 2.5

var shots := 0
var landed := 0
var hurt := 0.0
var kills_by_gun := {}
var _waiting: Array = []


func id() -> String:
	return "stats"


func attach() -> void:
	game.shot_fired.connect(_fired)
	game.hit_landed.connect(_hit)
	game.player_hurt.connect(func(amount: float, _cause: String) -> void: hurt += amount)
	game.enemy_killed.connect(_killed)


func _fired(_gun: int) -> void:
	shots += 1
	_waiting.append(game.clock)


func _hit(_amount: float, _killed: bool) -> void:
	while not _waiting.is_empty() and game.clock - float(_waiting[0]) > LANDS_WITHIN:
		_waiting.pop_front()
	if not _waiting.is_empty():
		_waiting.pop_front()
		landed += 1


func _killed(enemy: Enemy) -> void:
	if enemy.hostile:
		var gun := String(Weapons.NAMES[game.armory.active])
		kills_by_gun[gun] = int(kills_by_gun.get(gun, 0)) + 1


func accuracy() -> int:
	return roundi(landed * 100.0 / shots) if shots > 0 else 0


func save() -> Dictionary:
	if shots == 0 and hurt == 0.0 and kills_by_gun.is_empty():
		return {}
	return {"shots": shots, "landed": landed, "hurt": hurt, "kills": kills_by_gun.duplicate()}


func restore(state: Dictionary) -> void:
	shots = maxi(0, int(state.get("shots", 0)))
	landed = clampi(int(state.get("landed", 0)), 0, shots)
	hurt = maxf(0.0, float(state.get("hurt", 0.0)))
	kills_by_gun = {}
	var kills = state.get("kills", {})
	if kills is Dictionary:
		for gun in kills:
			kills_by_gun[String(gun)] = maxi(0, int(kills[gun]))


func tally_rows() -> Array:
	return [["ACCURACY", "%d%%" % accuracy()]] if shots > 0 else []


func report() -> String:
	var best := ""
	var most := 0
	for gun: String in kills_by_gun:
		if int(kills_by_gun[gun]) > most:
			most = int(kills_by_gun[gun])
			best = gun
	return (
		"%d shots, %d landed (%d%%), %d damage taken%s"
		% [shots, landed, accuracy(), int(hurt), ", most kills with " + best if best != "" else ""]
	)
