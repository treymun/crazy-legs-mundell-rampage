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
	preload("res://src/features/weapon_fx.gd"),
	preload("res://src/features/posse.gd"),
	preload("res://src/features/ambient.gd"),
	preload("res://src/features/callouts.gd"),
	preload("res://src/features/tally.gd"),
	preload("res://src/features/fight_music.gd"),
	preload("res://src/features/boss_fight.gd"),
	preload("res://src/features/race_laps.gd"),
	preload("res://src/features/firing_range.gd"),
	preload("res://src/features/bayou_feature.gd"),
	preload("res://src/features/mothership.gd"),
	preload("res://src/features/corpses.gd"),
	preload("res://src/features/breakables.gd"),
	preload("res://src/features/wall_breaks.gd"),
	preload("res://src/features/water.gd"),
	preload("res://src/features/impacts.gd"),
	preload("res://src/features/dust.gd"),
	preload("res://src/features/gun_fx.gd"),
	preload("res://src/features/feel.gd"),
	preload("res://src/features/soundscape.gd"),
	preload("res://src/features/boss_voices.gd"),
	preload("res://src/features/boss_checkpoint.gd"),
	preload("res://src/features/boss_rematch.gd"),
	preload("res://src/features/boss_arena.gd"),
	preload("res://src/features/boss_arenas.gd"),
	preload("res://src/features/variants_feature.gd"),
	preload("res://src/features/squad_feature.gd"),
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


## Drawing over the view, under the gun (game_view.gd), on the 320-wide canvas.
static func draw_view(game, c: Canvas) -> void:
	for key: String in game.features:
		game.features[key].draw_view(c)


static func ground_marks(game) -> Array:
	var out: Array = []
	for key: String in game.features:
		out.append_array(game.features[key].ground_marks())
	return out


static func wall_marks(game) -> Array:
	var out: Array = []
	for key: String in game.features:
		out.append_array(game.features[key].wall_marks())
	return out


static func tally_rows(game) -> Array:
	var rows: Array = []
	for key: String in game.features:
		rows.append_array(game.features[key].tally_rows())
	return rows
