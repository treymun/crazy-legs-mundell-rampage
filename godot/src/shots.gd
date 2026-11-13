## Shots and blasts as data (data/tuning/shots.cfg): how each kind of shot
## falls, how big it is drawn, whether it glows, and the blast it makes when it
## bursts. game_combat.gd moves and bursts them, game_view.gd draws them.
class_name Shots
extends RefCounted

const PATH := "res://data/tuning/shots.cfg"

## kind -> its section's values
static var KINDS := {}
## [blast]: what every blast has unless its kind says otherwise
static var BLAST := {}


static func _static_init() -> void:
	load_tuning()


static func load_tuning() -> void:
	var cfg := Tuning.file(PATH)
	KINDS = {}
	BLAST = {}
	for section in cfg.get_sections():
		var values := {}
		for key in cfg.get_section_keys(section):
			values[key] = cfg.get_value(section, key)
		if section == "blast":
			BLAST = values
		else:
			KINDS[section] = values


static func gravity(kind: String) -> float:
	return float(KINDS.get(kind, {}).get("gravity", 0.0))


static func size(kind: String, enemy: bool) -> float:
	return float(KINDS.get(kind, {}).get("size", .14 if enemy else .10))


static func glows(kind: String) -> bool:
	return bool(KINDS.get(kind, {}).get("glow", false))


## It bounces, rolls and rests till its life runs out, as thrown dynamite does.
static func rolls(kind: String) -> bool:
	return bool(KINDS.get(kind, {}).get("rolls", false))


static func explodes(kind: String) -> bool:
	return bool(KINDS.get(kind, {}).get("explodes", false))


## The blast of a kind: [blast] with what the kind's own section sets.
static func blast(kind: String) -> Dictionary:
	var out := BLAST.duplicate()
	out.merge(KINDS.get(kind, {}), true)
	return out
