## Moved out of enemies.gd to keep it under the line limit; the originals call these.
class_name EnemyTuning
extends RefCounted


static func definition(cfg: ConfigFile, kind: String, depth: int) -> Dictionary:
	var d := {}
	if cfg.has_section_key(kind, "brain") and depth < 4:
		var brain_kind := String(cfg.get_value(kind, "brain"))
		if cfg.has_section(brain_kind) and brain_kind != kind:
			d = definition(cfg, brain_kind, depth + 1)
			d["brain"] = String(d.get("brain", brain_kind))
	for key in cfg.get_section_keys(kind):
		if key != "brain":
			d[key] = cfg.get_value(kind, key)
	return d


## enemies.cfg into Enemy's tables (Enemy.load_tuning).
static func load_tuning() -> void:
	var path := Tuning.ENEMIES
	var cfg := Tuning.file(path)
	Enemy.DEATH_TIME = Tuning.value(path, "death_time")
	Enemy.VOICE_TAKES = Tuning.value(path, "voice_takes")
	Enemy.DEATH_ONLY = Tuning.value(path, "death_only_voices")
	Enemy.LUCKY_CHANCE = float(Tuning.value(path, "lucky_chance"))
	Enemy.DEFS = {}
	for kind in Tuning.sections(path):
		Enemy.DEFS[kind] = definition(cfg, kind, 0)
	Enemy.KINDS = {}
	Enemy.RECOVERY_TIMES = {}
	Enemy.LUNGES = {}
	Enemy.REACH = {}
	Enemy.WINDUP = {}
	Enemy.COMFORT = {}
	Enemy.BOSS_TITLES = {}
	Enemy.SIGNATURES = {}
	Enemy.TELLS = {}
	Enemy.VOICES = {}
	Enemy.AWAKE = {}
	Enemy.TURN_CELS = []
	Enemy.FIDGET_CELS = []
	Enemy.CREATURE_FALLS = []
	Enemy.SHELL_ACTORS = []
	Enemy.TOOL_ACTORS = []
	Enemy.LOSS_RESPONDERS = []
	Enemy.RANGED = []
	Enemy.PLASMA = []
	Enemy.GREEN_GIBS = []
	var keyed := {
		"recovery_times": Enemy.RECOVERY_TIMES,
		"lunges": Enemy.LUNGES,
		"reach": Enemy.REACH,
		"windup": Enemy.WINDUP,
		"comfort": Enemy.COMFORT,
		"title": Enemy.BOSS_TITLES,
		"signature": Enemy.SIGNATURES,
		"tell": Enemy.TELLS,
		"voice": Enemy.VOICES,
		"alert": Enemy.AWAKE,
	}
	for kind: String in Enemy.DEFS:
		var d: Dictionary = Enemy.DEFS[kind]
		Enemy.KINDS[kind] = [d["hp"], d["speed"], d["radius"], d["height"], d["hostile"]]
		for key: String in keyed:
			if d.has(key):
				keyed[key][kind] = d[key]
		var cels := String(d.get("cels", ""))
		if cels == "turn":
			Enemy.TURN_CELS.append(kind)
		elif cels == "tumble":
			Enemy.CREATURE_FALLS.append(kind)
		if d.get("fidget", false):
			Enemy.FIDGET_CELS.append(kind)
		if d.get("struck", "") == "shell":
			Enemy.SHELL_ACTORS.append(kind)
		elif d.get("struck", "") == "tool":
			Enemy.TOOL_ACTORS.append(kind)
		if d.get("answers_losses", false):
			Enemy.LOSS_RESPONDERS.append(kind)
		if d.get("ranged", false):
			Enemy.RANGED.append(kind)
		if d.get("blood", "") == "plasma":
			Enemy.PLASMA.append(kind)
		if d.get("green_gibs", false):
			Enemy.GREEN_GIBS.append(kind)
	Enemy.TURNS = {}
	Enemy.FIDGETS = {}
	Enemy.FALLS = {}
	for kind: String in Enemy.TURN_CELS:
		Enemy.TURNS[kind] = true
	for kind: String in Enemy.FIDGET_CELS:
		Enemy.FIDGETS[kind] = true
	for kind: String in Enemy.CREATURE_FALLS:
		Enemy.FALLS[kind] = true
	Enemy._cels = {}
	Variants.tables()
