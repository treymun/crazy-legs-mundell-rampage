## The features every Game has (game_feature.gd says how to write one). Game._init
## attaches them; SessionStore saves and restores them by id.
class_name Features
extends RefCounted

const ALL := [
	preload("res://src/features/triggers_feature.gd"),
	preload("res://src/features/lessons_feature.gd"),
	preload("res://src/features/chapter_stats.gd"),
	preload("res://src/features/weather.gd"),
	preload("res://src/features/debris.gd"),
	preload("res://src/features/ambient.gd"),
	preload("res://src/features/callouts.gd"),
	preload("res://src/features/tally.gd"),
]


static func attach_all(game) -> void:
	for script: GDScript in ALL:
		var feature: GameFeature = script.new(game)
		game.features[feature.id()] = feature


static func save_all(game) -> Dictionary:
	var out := {}
	for key: String in game.features:
		var state: Dictionary = game.features[key].save()
		if not state.is_empty():
			out[key] = state
	return out


static func restore_all(game, saved) -> void:
	var states: Dictionary = saved if saved is Dictionary else {}
	for key: String in game.features:
		var state = states.get(key, {})
		game.features[key].restore(state if state is Dictionary else {})


static func sprites(game) -> Array:
	var out: Array = []
	for key: String in game.features:
		out.append_array(game.features[key].sprites())
	return out


static func ground_marks(game) -> Array:
	var out: Array = []
	for key: String in game.features:
		out.append_array(game.features[key].ground_marks())
	return out


static func tally_rows(game) -> Array:
	var rows: Array = []
	for key: String in game.features:
		rows.append_array(game.features[key].tally_rows())
	return rows
