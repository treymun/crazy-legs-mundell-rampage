## The hit tables of data/tuning/hits.cfg as the scripts use them: a section
## as a Dictionary (key -> value), the ammo pickups with their guns' indices.
class_name HitData
extends RefCounted

const DATA := "res://data/tuning/hits.cfg"


## Every key of `section` but those listed in `except`.
static func section(name: String, except: Array = []) -> Dictionary:
	var cfg := Tuning.file(DATA)
	var out := {}
	if not cfg.has_section(name):
		push_error("%s: no [%s]" % [DATA, name])
		return out
	for key: String in cfg.get_section_keys(name):
		if not except.has(key):
			out[key] = cfg.get_value(name, key)
	return out


static func value(name: String, key: String, fallback: Variant) -> Variant:
	return Tuning.file(DATA).get_value(name, key, fallback)


## The ammo pickups: name -> [gun index, rounds].
static func ammo() -> Dictionary:
	var guns := Tuning.sections(Tuning.WEAPONS)
	var out := {}
	for key: String in section("ammo"):
		var row: Array = value("ammo", key, [])
		var gun := guns.find(str(row[0]))
		if gun < 0:
			push_error("%s: [ammo] %s names no gun %s" % [DATA, key, row[0]])
			continue
		var rounds: int = row[1]
		out[key] = [gun, rounds]
	return out
