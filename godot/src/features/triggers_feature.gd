## The level's triggers (triggers.gd) as a feature: checked every tick, the
## ones that fired kept in the save.
extends GameFeature


func id() -> String:
	return "triggers"


func attach() -> void:
	tick_with(_tick)


func _tick(_dt: float) -> void:
	Triggers.tick(game)
	if not game.trigger_lights.is_empty() and _any_out():
		game.trigger_lights = game.trigger_lights.filter(
			func(l: Array) -> bool:
				var until: float = l[6]
				return game.clock < until
		)


## Whether a trigger's light has gone out (only then is the list made again).
func _any_out() -> bool:
	for l: Array in game.trigger_lights:
		var until: float = l[6]
		if not (game.clock < until):
			return true
	return false


func save() -> Dictionary:
	var fired: Array = game.triggers_fired.keys()
	fired.sort()
	return {"fired": fired} if not fired.is_empty() else {}


## A trigger no longer in the level is dropped.
func restore(state: Dictionary) -> void:
	game.triggers_fired = {}
	var known := {}
	for trigger: Dictionary in game.level.triggers:
		known[str(trigger["id"])] = true
	var fired: Variant = state.get("fired", [])
	if fired is Array:
		for name: Variant in fired:
			if typeof(name) == TYPE_STRING and known.has(name):
				game.triggers_fired[str(name)] = true
