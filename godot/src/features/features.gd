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
	preload("res://src/features/vehicle_runs.gd"),
	preload("res://src/features/firing_range.gd"),
	preload("res://src/features/bayou_feature.gd"),
	preload("res://src/features/mothership.gd"),
	preload("res://src/features/corpses.gd"),
	preload("res://src/features/finishers.gd"),
	preload("res://src/features/brawl.gd"),
	preload("res://src/features/breakables.gd"),
	preload("res://src/features/wall_breaks.gd"),
	preload("res://src/features/carry.gd"),
	preload("res://src/features/fire.gd"),
	preload("res://src/features/stills.gd"),
	preload("res://src/features/set_pieces.gd"),
	preload("res://src/features/wreckage.gd"),
	preload("res://src/features/wall_looks.gd"),
	preload("res://src/features/water.gd"),
	preload("res://src/features/impacts.gd"),
	preload("res://src/features/dust.gd"),
	preload("res://src/features/gun_fx.gd"),
	preload("res://src/features/feel.gd"),
	preload("res://src/features/brawl_looks.gd"),
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
	preload("res://src/features/kill_feed.gd"),
	preload("res://src/features/new_iron.gd"),
	preload("res://src/features/radio.gd"),
	preload("res://src/features/hound.gd"),
	preload("res://src/features/hound_voice.gd"),
	preload("res://src/features/bench.gd"),
	preload("res://src/features/county_events.gd"),
	preload("res://src/features/event_looks.gd"),
	preload("res://src/features/rumble.gd"),
	preload("res://src/features/trail_marker.gd"),
	preload("res://src/features/danger_looks.gd"),
	preload("res://src/features/director.gd"),
	preload("res://src/features/rampage.gd"),
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
	"brawl_looks",
	"soundscape",
	"boss_voices",
	"enemy_barks",
	"boss_checkpoint",
	"trophy_shack",
	"wreckage",
	"wall_looks",
	"kill_feed",
	"new_iron",
	"radio",
	"event_looks",
	"hound_voice",
	"rumble",
	"trail_marker",
	"danger_looks",
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


## The per-frame hooks below each run only the features whose script has
## its own (the rest would return nothing: GameFeature's are empty), listed
## once a game in the features' order (pass 10: seven calls a frame on each of
## 120-odd features were a tenth of a millisecond).
const HOOKS: Array[String] = [
	"sprites", "draw_view", "hud_fixed", "hud_late", "hud_flow", "ground_marks", "wall_marks"
]
## Per feature script, the hooks it has its own of.
static var _own_hooks := {}


## The features with their own `hook`, in order (made again when the
## features are not those it was made of).
static func with_hook(game: Game, hook: String) -> Array:
	var lists: Dictionary = game.events.hooks
	if game.events.hooks_of != game.features.size():
		lists.clear()
		game.events.hooks_of = game.features.size()
		for name: String in HOOKS:
			lists[name] = []
		for key: String in game.features:
			var feature: GameFeature = game.features[key]
			var script: Script = feature.get_script()
			var own: Dictionary = _hooks_of(script)
			for name: String in HOOKS:
				if own.has(name):
					var list: Array = lists[name]
					list.append(feature)
	return lists[hook]


static func _hooks_of(script: Script) -> Dictionary:
	var known: Variant = _own_hooks.get(script)
	if known != null:
		return known
	# A script's method list holds its bases' too: one it has its own of is
	# listed more often than in GameFeature's.
	var base_script: Script = load("res://src/features/game_feature.gd")
	var base := _method_counts(base_script)
	var seen := _method_counts(script)
	var own := {}
	for name: String in HOOKS:
		var mine: int = seen.get(name, 0)
		var based: int = base.get(name, 0)
		if mine > based:
			own[name] = true
	_own_hooks[script] = own
	return own


static func _method_counts(script: Script) -> Dictionary:
	var counts := {}
	for m: Dictionary in script.get_script_method_list():
		var name: String = m["name"]
		var had: int = counts.get(name, 0)
		counts[name] = had + 1
	return counts


static func sprites(game: Game) -> Array:
	var out: Array = []
	for feature: GameFeature in with_hook(game, "sprites"):
		out.append_array(feature.sprites())
	return out


## Drawing over the view, under the gun (game_view.gd), on the 320-wide canvas.
static func draw_view(game: Game, c: Canvas) -> void:
	for feature: GameFeature in with_hook(game, "draw_view"):
		feature.draw_view(c)


## Each feature's HUD pieces that keep to the edges (GameFeature.hud_fixed).
static func hud_fixed(game: Game, layout: HudLayout) -> void:
	for feature: GameFeature in with_hook(game, "hud_fixed"):
		feature.hud_fixed(layout)


## Each feature's HUD pieces placed last (GameFeature.hud_late).
static func hud_late(game: Game, layout: HudLayout) -> void:
	for feature: GameFeature in with_hook(game, "hud_late"):
		feature.hud_late(layout)


## Each feature's HUD pieces that hang under the top (GameFeature.hud_flow).
static func hud_flow(game: Game, layout: HudLayout) -> void:
	for feature: GameFeature in with_hook(game, "hud_flow"):
		feature.hud_flow(layout)


static func ground_marks(game: Game) -> Array:
	var out: Array = []
	for feature: GameFeature in with_hook(game, "ground_marks"):
		out.append_array(feature.ground_marks())
	return out


static func wall_marks(game: Game) -> Array:
	var out: Array = []
	for feature: GameFeature in with_hook(game, "wall_marks"):
		out.append_array(feature.wall_marks())
	return out


static func tally_rows(game: Game) -> Array:
	var rows: Array = []
	for key: String in game.features:
		var feature: GameFeature = game.features[key]
		rows.append_array(feature.tally_rows())
	return rows
