## The numbers a designer tunes, read from data/tuning/*.cfg instead of being
## written into the scripts: weapons.cfg has a section per gun (its name in
## Weapons.NAMES) and enemies.cfg one per enemy kind, each with an [all]
## section for the shared values. The files are Godot ConfigFile text, so a
## value keeps its type exactly as written (6 is a whole number, 6.0 is not;
## Vector2 and Vector3i are written as such).
##
## Weapons and Enemy load them when their scripts load. When the game runs
## from the project folder the dev console (src/dev_tune.gd) asks changed()
## every frame and a saved change is picked up in under a second, with no
## restart: fire rates, damage, how a gun sits in view, enemy speed and reach,
## and the static values the scripts read from the files.
class_name Tuning
extends RefCounted

const WEAPONS := "res://data/tuning/weapons.cfg"
const ENEMIES := "res://data/tuning/enemies.cfg"

static var _files := {}
static var _stamps := {}
static var _next_check := 0


static func file(path: String) -> ConfigFile:
	var kept: ConfigFile = _files.get(path)
	if kept == null:
		kept = ConfigFile.new()
		var error := kept.load(path)
		if error != OK:
			push_error("cannot read %s (error %d)" % [path, error])
		_files[path] = kept
		_stamps[path] = FileAccess.get_modified_time(path)
	return kept


## One value of the [all] section (or of any section).
static func value(path: String, key: String, section := "all") -> Variant:
	return file(path).get_value(section, key)


## A value for every name in `names`, in that order: an array indexed like it.
static func table(path: String, names: Array, key: String) -> Array:
	var cfg := file(path)
	var out: Array = []
	for name: String in names:
		out.append(cfg.get_value(name, key))
	return out


## Index -> value for each name in `names` whose section has the key.
static func entries(path: String, names: Array, key: String) -> Dictionary:
	var cfg := file(path)
	var out := {}
	for i in names.size():
		var name: String = names[i]
		if cfg.has_section_key(name, key):
			out[i] = cfg.get_value(name, key)
	return out


## Section name -> value for every section (but [all]) that has the key.
static func by_section(path: String, key: String) -> Dictionary:
	var cfg := file(path)
	var out := {}
	for section in cfg.get_sections():
		if section != "all" and cfg.has_section_key(section, key):
			out[section] = cfg.get_value(section, key)
	return out


## Every section but [all], in file order.
static func sections(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	for section in file(path).get_sections():
		if section != "all":
			out.append(section)
	return out


## The file as last read (null: not read yet), without reading it.
static func cached(path: String) -> ConfigFile:
	return _files.get(path)


## Use `cfg` for `path` from now on (DevTune: a file read again, or edited by
## hand), stamped with the file's time on disk now.
static func put(path: String, cfg: ConfigFile) -> void:
	_files[path] = cfg
	_stamps[path] = FileAccess.get_modified_time(path)


## The files read that were saved since (at most every half second; never in
## an exported game, which cannot change). DevTune reads them again.
static func changed() -> PackedStringArray:
	var out := PackedStringArray()
	if OS.has_feature("template"):
		return out
	var now := Time.get_ticks_msec()
	if now < _next_check:
		return out
	_next_check = now + 500
	for path: String in _stamps.keys():
		if not FileAccess.file_exists(path):
			# Gone (a tool's copy): forgotten.
			_stamps.erase(path)
			_files.erase(path)
			continue
		var stamp: int = _stamps[path]
		if FileAccess.get_modified_time(path) != stamp:
			out.append(path)
	return out
