## The one-time control lessons (lessons.gd) as a feature: checked every tick.
## What a profile was taught is its own file, not part of a save.
extends GameFeature


func id() -> String:
	return "lessons"


func attach() -> void:
	game.ticked.connect(func(_dt: float) -> void: Lessons.tick(game))
