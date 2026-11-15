## The bosses' numbers from data/tuning/bosses.cfg (a section per boss and per
## part of the fights: boss_kit, each src/bosses/ file, the arenas, Maw's
## fight, the rematch's par times), so a fight is balanced in the file.
class_name BossData
extends RefCounted

const DATA := "res://data/tuning/bosses.cfg"


static func get_value(section: String, key: String) -> Variant:
	var cfg := Tuning.file(DATA)
	if not cfg.has_section_key(section, key):
		push_error("%s: no [%s] %s" % [DATA, section, key])
		return null
	return cfg.get_value(section, key)
