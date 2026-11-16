## The features every Game has (game_feature.gd says how to write one). Game._init
## attaches them; SessionStore saves and restores them by id.
class_name Features
extends RefCounted

const ALL := [
	preload("res://src/features/triggers_feature.gd"),
	preload("res://src/features/lessons_feature.gd"),
	preload("res://src/features/chapter_stats.gd"),
	preload("res://src/features/climate.gd"),
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
	preload("res://src/features/vehicles.gd"),
	preload("res://src/features/firing_range.gd"),
	preload("res://src/features/bayou_feature.gd"),
	preload("res://src/features/mothership.gd"),
	preload("res://src/features/corpses.gd"),
	preload("res://src/features/finishers.gd"),
	preload("res://src/features/breakables.gd"),
	preload("res://src/features/wall_breaks.gd"),
	preload("res://src/features/carry.gd"),
	preload("res://src/features/fire.gd"),
	preload("res://src/features/stills.gd"),
	preload("res://src/features/wreckage.gd"),
	preload("res://src/features/water.gd"),
	preload("res://src/features/impacts.gd"),
	preload("res://src/features/dust.gd"),
	preload("res://src/features/gun_fx.gd"),
	preload("res://src/features/feel.gd"),
	preload("res://src/features/soundscape.gd"),
	preload("res://src/features/boss_voices.gd"),
	preload("res://src/features/enemy_barks.gd"),
	preload("res://src/features/boss_checkpoint.gd"),
	preload("res://src/features/boss_rematch.gd"),
	preload("res://src/features/boss_arena.gd"),
	preload("res://src/features/boss_arenas.gd"),
	preload("res://src/features/arena_wreck.gd"),
	preload("res://src/features/boss_gear.gd"),
	preload("res://src/features/boss_lock.gd"),
	preload("res://src/features/hit_reads.gd"),
	preload("res://src/features/critters.gd"),
	preload("res://src/features/variants_feature.gd"),
	preload("res://src/features/squad_feature.gd"),
	preload("res://src/features/county_run.gd"),
	preload("res://src/features/mode_feature.gd"),
	preload("res://src/features/fair_gallery.gd"),
	preload("res://src/features/trophy_shack.gd"),
]

## The features that only look or sound, by file (GameSnapshot.LOOKS_FEATURES
## by id; tools/net_check.gd holds the two lists together): a host leaves
## them off.
const LOOKS := [
	"lessons_feature",
	"chapter_stats",
	"weather",
	"debris",
	"weapon_fx",
	"ambient",
	"callouts",
	"tally",
	"fight_music",
	"water",
	"impacts",
	"dust",
	"gun_fx",
	"feel",
	"soundscape",
	"boss_voices",
	"enemy_barks",
	"boss_checkpoint",
	"trophy_shack",
	"wreckage",
]


static func attach_all(game: Game) -> void:
	for script: GDScript in ALL:
		if game.host and LOOKS.has(script.resource_path.get_file().get_basename()):
			continue
		var feature: GameFeature = script.new(game)
		game.features[feature.id()] = feature


static func save_all(game: Game) -> Dictionary:
	var out := {}
	for key: String in game.features:
		var feature: GameFeature = game.features[key]
		var state: Dictionary = feature.save()
		if not state.is_empty():
			out[key] = state
	return out


static func restore_all(game: Game, saved: Variant) -> void:
	var states: Dictionary = saved if saved is Dictionary else {}
	for key: String in game.features:
		var state: Variant = states.get(key, {})
		var feature: GameFeature = game.features[key]
		var given: Dictionary = state if state is Dictionary else {}
		feature.restore(given)
	game.events.wake_all()


static func sprites(game: Game) -> Array:
	var out: Array = []
	for key: String in game.features:
		var feature: GameFeature = game.features[key]
		out.append_array(feature.sprites())
	return out


## Drawing over the view, under the gun (game_view.gd), on the 320-wide canvas.
static func draw_view(game: Game, c: Canvas) -> void:
	for key: String in game.features:
		var feature: GameFeature = game.features[key]
		feature.draw_view(c)


static func ground_marks(game: Game) -> Array:
	var out: Array = []
	for key: String in game.features:
		var feature: GameFeature = game.features[key]
		out.append_array(feature.ground_marks())
	return out


static func wall_marks(game: Game) -> Array:
	var out: Array = []
	for key: String in game.features:
		var feature: GameFeature = game.features[key]
		out.append_array(feature.wall_marks())
	return out


static func tally_rows(game: Game) -> Array:
	var rows: Array = []
	for key: String in game.features:
		var feature: GameFeature = game.features[key]
		rows.append_array(feature.tally_rows())
	return rows
