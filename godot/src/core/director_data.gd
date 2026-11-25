## The fight-rhythm director's numbers (data/tuning/director.cfg, pass 15):
## [all] its plain values, [pace] one array of four by difficulty (EASY,
## NORMAL, HARD, HOG WILD) as in difficulty.cfg. `ON` turns it off for good
## in a tool (as EnemyLod.ON), read from the file's `on` when first asked.
class_name DirectorData
extends RefCounted

const DATA := "res://data/tuning/director.cfg"

static var ON: bool = Tuning.file(DATA).get_value("all", "on", true)


## [all] `key`, or `fallback`.
static func value(key: String, fallback: Variant = null) -> Variant:
	var cfg := Tuning.file(DATA)
	if not cfg.has_section_key("all", key):
		push_error("%s: no [all] %s" % [DATA, key])
		return fallback
	return cfg.get_value("all", key)


static func num(key: String) -> float:
	var v: float = value(key, 0.0)
	return v


## [pace] `key` at `difficulty` (0 EASY .. 3 HOG WILD).
static func at(key: String, difficulty: int) -> float:
	var row: Variant = Tuning.file(DATA).get_value("pace", key, null)
	var four: Array = row if row is Array else []
	if four.size() != 4:
		push_error("%s: [pace] %s is not four values" % [DATA, key])
		return 0.0
	var v: float = four[clampi(difficulty, 0, 3)]
	return v


## Whether the file leaves `level_id` alone.
static func chapter_off(level_id: String) -> bool:
	var off: Variant = value("off_chapters", [])
	var ids: Array = off if off is Array else []
	return ids.has(level_id)
