## Rumble's numbers from data/tuning/rumble.cfg (features/rumble.gd,
## src/rumble_out.gd). A pulse is a Vector3: weak, strong, seconds. The
## file is read through Tuning, so a change saved while the game runs from
## the project folder is used from the next pulse on (the gun table is made
## again when the file is).
class_name RumbleData
extends RefCounted

const DATA := "res://data/tuning/rumble.cfg"

## Each gun's pulse by its index in weapons.cfg, and the file they came from.
static var _guns: Array[Vector3] = []
static var _from: ConfigFile = null


static func num(section: String, key: String, fallback := 0.0) -> float:
	var v: float = Tuning.file(DATA).get_value(section, key, fallback)
	return v


## [weak, strong, seconds] as a Vector3 (missing: none).
static func pulse(section: String, key: String) -> Vector3:
	var row: Variant = Tuning.file(DATA).get_value(section, key, null)
	return _vec3(row)


## [weak, strong] as a Vector2 (missing: none).
static func pair(section: String, key: String) -> Vector2:
	var row: Variant = Tuning.file(DATA).get_value(section, key, null)
	if not row is Array:
		return Vector2.ZERO
	var a: Array = row
	if a.size() < 2:
		return Vector2.ZERO
	var w: float = a[0]
	var s: float = a[1]
	return Vector2(w, s)


## Gun `gun`'s shot ([guns], by its weapons.cfg name).
static func gun(i: int) -> Vector3:
	var cfg := Tuning.file(DATA)
	if cfg != _from or _guns.size() != Weapons.NAMES.size():
		_from = cfg
		_guns.clear()
		for name: String in Weapons.NAMES:
			_guns.append(_vec3(cfg.get_value("guns", name, null)))
	if i < 0 or i >= _guns.size():
		return Vector3.ZERO
	return _guns[i]


## The section a vehicle kind's numbers are in.
static func vehicle_section(kind: String) -> String:
	var own := "vehicle." + kind
	return own if Tuning.file(DATA).has_section(own) else "vehicle"


## What a level of the RUMBLE settings scales by: OFF 0, LOW `low`, FULL 1.
static func level_scale(level: int) -> float:
	if level <= 0:
		return 0.0
	if level == 1:
		return num("all", "low", .45)
	return 1.0


static func _vec3(row: Variant) -> Vector3:
	if not row is Array:
		return Vector3.ZERO
	var a: Array = row
	if a.size() < 3:
		return Vector3.ZERO
	var w: float = a[0]
	var s: float = a[1]
	var t: float = a[2]
	return Vector3(w, s, t)
