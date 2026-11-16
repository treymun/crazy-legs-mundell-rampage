## The level's triggers (triggers.gd) as a feature: checked every tick, the
## ones that fired kept in the save.
extends GameFeature


func id() -> String:
	return "triggers"


func attach() -> void:
	tick_with(_tick)


func _tick(_dt: float) -> void:
	Triggers.tick(game)
	if not game.trigger_lights.is_empty():
		game.trigger_lights = game.trigger_lights.filter(
			func(l: Array) -> bool:
				var until: float = l[6]
				return game.clock < until
		)


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
