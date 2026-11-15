## The numbers that change with DIFFICULTY (EASY, NORMAL, HARD, HOG WILD),
## read from data/tuning/difficulty.cfg: one array of four per key, so a
## difficulty is balanced there, not in the scripts.
class_name Difficulty
extends RefCounted

const DATA := "res://data/tuning/difficulty.cfg"


## The four values of `key` in `section` (EASY first).
static func table(section: String, key: String) -> Array:
	var value: Variant = Tuning.file(DATA).get_value(section, key, null)
	var four: Array = value if value is Array else []
	if four.size() != 4:
		push_error("%s: [%s] %s is not four values" % [DATA, section, key])
		return [0, 0, 0, 0]
	return four


## One difficulty's value of `key` (0 EASY .. 3 HOG WILD).
static func at(section: String, key: String, difficulty: int) -> Variant:
	return table(section, key)[clampi(difficulty, 0, 3)]
