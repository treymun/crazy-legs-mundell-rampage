## The game modes' rules from data/tuning/modes.cfg: modes read their numbers
## here, so a mode is balanced in the file, not in its script.
class_name ModeData
extends RefCounted

const DATA := "res://data/tuning/modes.cfg"


## [section] key, or `fallback` (with an error) when the file lacks it.
static func get_value(section: String, key: String, fallback: Variant) -> Variant:
	var cfg := Tuning.file(DATA)
	if not cfg.has_section_key(section, key):
		push_error("%s: no [%s] %s" % [DATA, section, key])
		return fallback
	return cfg.get_value(section, key)
