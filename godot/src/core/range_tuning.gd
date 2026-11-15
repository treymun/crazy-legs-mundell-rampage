## The midway games' numbers (the firing range's horseshoes, skee-ball, dunk
## tank and milk bottles, the fair's shooting gallery, the range's board)
## from data/tuning/range_games.cfg: the games read them here, so they are
## balanced in the file, not in their scripts.
class_name RangeTuning
extends RefCounted

const DATA := "res://data/tuning/range_games.cfg"


## [section] key, or `fallback` (with an error) when the file lacks it.
static func get_value(section: String, key: String, fallback: Variant = null) -> Variant:
	var cfg := Tuning.file(DATA)
	if not cfg.has_section_key(section, key):
		push_error("%s: no [%s] %s" % [DATA, section, key])
		return fallback
	return cfg.get_value(section, key)
