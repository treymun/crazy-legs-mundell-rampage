## How the chapter went: shots fired and how many found a mark, damage taken,
## and kills with each gun. Built only from the game's events; saved with the
## chapter; its accuracy shows on the tally, and the console's `stats` prints
## the rest.
extends GameFeature

var shots := 0
var landed := 0
var hurt := 0.0
var kills_by_gun := {}


func id() -> String:
	return "stats"


func attach() -> void:
	game.events.attack_started.connect(_fired)
	game.events.attack_contact.connect(_hit)
	game.events.player_hurt.connect(
		func(amount: float, _cause: String) -> void: hurt += amount if game.acting_local() else 0.0
	)


func _fired() -> void:
	if game.acting_local():
		shots += 1


func _hit(gun: int, first: bool, killed_hostile: bool) -> void:
	if not game.acting_local():
		return
	if first:
		landed = mini(landed + 1, shots)
	if killed_hostile:
		var name: String = Weapons.NAMES[gun]
		var so_far: int = kills_by_gun.get(name, 0)
		kills_by_gun[name] = so_far + 1


func accuracy() -> int:
	return roundi(landed * 100.0 / shots) if shots > 0 else 0


func save() -> Dictionary:
	if shots == 0 and hurt == 0.0 and kills_by_gun.is_empty():
		return {}
	return {"shots": shots, "landed": landed, "hurt": hurt, "kills": kills_by_gun.duplicate()}


func restore(state: Dictionary) -> void:
	var saved_shots: int = state.get("shots", 0)
	shots = maxi(0, saved_shots)
	var saved_landed: int = state.get("landed", 0)
	landed = clampi(saved_landed, 0, shots)
	var saved_hurt: float = state.get("hurt", 0.0)
	hurt = maxf(0.0, saved_hurt)
	kills_by_gun = {}
	var kills: Variant = state.get("kills", {})
	if kills is Dictionary:
		var by_gun: Dictionary = kills
		for gun: Variant in by_gun:
			var count: int = by_gun[gun]
			kills_by_gun[str(gun)] = maxi(0, count)


func tally_rows() -> Array:
	return [["ACCURACY", "%d%%" % accuracy()]] if shots > 0 else []


func report() -> String:
	var best := ""
	var most := 0
	for gun: String in kills_by_gun:
		var count: int = kills_by_gun[gun]
		if count > most:
			most = count
			best = gun
	return (
		"%d shots, %d landed (%d%%), %d damage taken%s"
		% [shots, landed, accuracy(), int(hurt), ", most kills with " + best if best != "" else ""]
	)
