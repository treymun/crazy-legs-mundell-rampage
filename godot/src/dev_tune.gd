## The dev console's `tune` commands (dev_console.gd): data/tuning/*.cfg read
## again from disk, or a value set by hand, in a running game, and put to use
## where that is safe. Each change is said as `file [section] key: old -> new`
## with where it took:
##
##   live         weapons.cfg, enemies.cfg, shots.cfg and effects.cfg go back
##                through their loaders (Weapons, Enemy, Shots, Effects
##                load_tuning); enemies in play are scaled to their kind's new
##                hp, speed, radius and height; a script's `static var` read
##                from a tuning file (BossData.get_value, ModeData, HitData,
##                Difficulty, a script's own reader...) is worked out again
##                from its own line and set (named as Class.VAR)
##   level        effects.cfg [level.*], a level's mood: `reload` the level
##   restart      a static var read from the key whose line could not be
##                worked out again (it names what an Expression cannot reach,
##                or is a typed Dictionary): restart the game
##   when read    nothing kept it: it takes the next time play reads it
##                (some only at a level's start: `reload` to be sure)
##
## `tune set` changes the file as read, not on disk; `tune save` writes the
## hand-set values back into the .cfg text, each key's line rewritten in place
## (comments, order and line endings kept). The console also reads a saved
## file again by itself within a second (watch()). Never online: every machine
## must play the same numbers. A change mid-run is a keyframe in the run's
## replay (DevConsole.run); the numbers are not in the replay, so one played
## later with other numbers parts where they matter.
## The JSON files are read by their own code (county.json again by itself
## when saved), so only the .cfg files are tuned here.
class_name DevTune
extends RefCounted

const DIR := "res://data/tuning"
## The files with a loader that reads them again (apply() runs it).
const LOADED := ["weapons.cfg", "enemies.cfg", "shots.cfg", "effects.cfg"]
## Where a script's static var is read from tuning (its line names one).
const READERS := [
	"ModeData.", "BossData.", "HitData.", "Difficulty.", "RangeTuning.", "Tuning.", "CountyData."
]

## Values set by hand and not yet saved: path -> [[section, key], ...].
var unsaved := {}
## Every static var a tuning file feeds: [script path, name, expression].
var _statics: Array = []
var _scanned := false
## Global class name -> its script's path (an expression's inputs).
var _classes := {}
## Each file as it was read from disk (and set by hand), kept apart: some code
## changes what Tuning.file() hands it (net_play.gd fills a lobby row in), so
## the copy the game reads is no measure of what changed.
var _disk := {}


func _init() -> void:
	for path in files():
		var cfg := ConfigFile.new()
		if cfg.load(path) == OK:
			_disk[path] = cfg


## "weapons", "weapons.cfg" or a res:// path -> the file's path ("" none).
static func path_of(name: String) -> String:
	if name.begins_with("res://"):
		return name if FileAccess.file_exists(name) else ""
	var file := name if name.ends_with(".cfg") else name + ".cfg"
	var path := DIR.path_join(file)
	return path if FileAccess.file_exists(path) else ""


## Every .cfg in DIR, sorted.
static func files() -> PackedStringArray:
	var out := PackedStringArray()
	for file in DirAccess.get_files_at(DIR):
		if file.ends_with(".cfg"):
			out.append(DIR.path_join(file))
	out.sort()
	return out


## A value as one short line.
static func shown(v: Variant) -> String:
	var text := var_to_str(v).replace("\r", "").replace("\n", " ")
	return text if text.length() <= 48 else text.left(45) + "..."


## The files changed on disk (Tuning.changed()) read again: what it says,
## empty when no value changed (a comment edited, the file saved as it was).
func watch(game: Game) -> PackedStringArray:
	var paths := Tuning.changed()
	if paths.is_empty():
		return paths
	var said := reload(paths, game)
	if said.size() == 1 and said[0] == "no changes":
		return PackedStringArray()
	return said


## Read `paths` again from disk and put the changes to use.
func reload(paths: PackedStringArray, game: Game) -> PackedStringArray:
	var changes: Array = []
	for path in paths:
		var old: ConfigFile = _disk.get(path, Tuning.cached(path))
		var fresh := ConfigFile.new()
		var kept := ConfigFile.new()
		if fresh.load(path) != OK or kept.load(path) != OK:
			push_error("cannot read " + path)
			continue
		Tuning.put(path, fresh)
		_disk[path] = kept
		unsaved.erase(path)
		if old != null:
			changes.append_array(_differences(path, old, kept))
	return apply(changes, game)


## One value: [[path, section, key, value], ...] in every file with it.
## `spec` is "section.key" (sections may hold dots: the key is after the last).
func find(spec: String) -> Array:
	var cut := spec.rfind(".")
	if cut < 0:
		return []
	var section := spec.left(cut)
	var key := spec.substr(cut + 1)
	var out: Array = []
	for path in files():
		var cfg := Tuning.file(path)
		if cfg.has_section_key(section, key):
			out.append([path, section, key, cfg.get_value(section, key)])
	return out


## Set [section] key in the file as read (not on disk; save() writes it).
## `text` is Godot value text (6, 6.0, [1, 2], Vector2(1, 2), "words"); a
## whole number given for a value that is not keeps the value's type.
func set_value(
	path: String, section: String, key: String, text: String, game: Game
) -> PackedStringArray:
	var cfg := Tuning.file(path)
	var as_read: ConfigFile = _disk.get(path, cfg)
	var had := as_read.has_section_key(section, key)
	var old: Variant = as_read.get_value(section, key) if had else null
	var value: Variant = str_to_var(text)
	if value == null and text != "null":
		value = text  # a bare word: a String
	if had and typeof(old) == TYPE_FLOAT and typeof(value) == TYPE_INT:
		var as_float: float = value
		value = as_float
	cfg.set_value(section, key, value)
	var kept: ConfigFile = _disk.get(path)
	if kept != null:
		kept.set_value(section, key, value)
	var pending: Array = unsaved.get(path, [])
	if not pending.has([section, key]):
		pending.append([section, key])
	unsaved[path] = pending
	var out := PackedStringArray()
	if not had:
		out.append("new key: %s [%s] %s" % [path.get_file(), section, key])
	out.append_array(apply([[path, section, key, old, value]], game))
	return out


## Write the hand-set values of `paths` (every file with some when empty)
## into their .cfg text: what it says.
func save(paths: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	var which := paths if not paths.is_empty() else PackedStringArray(unsaved.keys())
	for path in which:
		var pending: Array = unsaved.get(path, [])
		if pending.is_empty():
			continue
		var text := FileAccess.get_file_as_string(path)
		var cfg := Tuning.file(path)
		var values: ConfigFile = _disk.get(path, cfg)
		for pair: Array in pending:
			var section: String = pair[0]
			var key: String = pair[1]
			text = TuneText.rewrite(text, section, key, var_to_str(values.get_value(section, key)))
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			out.append("cannot write " + path.get_file())
			continue
		f.store_string(text)
		f.close()
		# Read back: every value written must come out as it is in play.
		var back := ConfigFile.new()
		var good := back.load(path) == OK
		for pair: Array in pending:
			var section: String = pair[0]
			var key: String = pair[1]
			var want: Variant = values.get_value(section, key)
			var got: Variant = back.get_value(section, key)
			good = good and typeof(got) == typeof(want) and got == want
		Tuning.put(path, cfg)
		unsaved.erase(path)
		out.append(
			(
				"saved %d to %s" % [pending.size(), path.get_file()]
				if good
				else "saved %s, but it reads back different: check it" % path.get_file()
			)
		)
	if out.is_empty():
		out.append("nothing set to save")
	return out


## Put `changes` ([path, section, key, old, new]) to use: the loaders, the
## enemies in play, the static vars; what it says, a line a change.
func apply(changes: Array, game: Game) -> PackedStringArray:
	var out := PackedStringArray()
	if changes.is_empty():
		out.append("no changes")
		return out
	var touched := {}
	for change: Array in changes:
		var changed_path: String = change[0]
		touched[changed_path.get_file()] = true
	var kinds_before: Dictionary = Enemy.KINDS.duplicate(true)
	if touched.has("weapons.cfg"):
		Weapons.load_tuning()
	if touched.has("enemies.cfg"):
		Enemy.load_tuning()
	if touched.has("shots.cfg"):
		Shots.load_tuning()
	if touched.has("effects.cfg"):
		Effects.load_tuning()
	var scaled := 0
	if touched.has("enemies.cfg") and game != null:
		scaled = _scale_enemies(game, kinds_before)
	var statics := _refresh_statics()
	var set_now: Array = statics[0]
	var failed: Array = statics[1]
	for change: Array in changes:
		var path: String = change[0]
		var file := path.get_file()
		var section: String = change[1]
		var key: String = change[2]
		var where := _where(file, section, key, set_now, failed)
		out.append(
			(
				"%s [%s] %s: %s -> %s (%s)"
				% [file, section, key, shown(change[3]), shown(change[4]), where]
			)
		)
	if scaled > 0:
		out.append("%d enemies in play took their kind's new numbers" % scaled)
	for row: Array in set_now:
		out.append("  %s: %s -> %s" % [row[0], shown(row[1]), shown(row[2])])
	return out


func _differences(path: String, old: ConfigFile, fresh: ConfigFile) -> Array:
	var out: Array = []
	var sections := {}
	for s in old.get_sections():
		sections[s] = true
	for s in fresh.get_sections():
		sections[s] = true
	for section: String in sections:
		var keys := {}
		if old.has_section(section):
			for k in old.get_section_keys(section):
				keys[k] = true
		if fresh.has_section(section):
			for k in fresh.get_section_keys(section):
				keys[k] = true
		for key: String in keys:
			var a: Variant = old.get_value(section, key, null)
			var b: Variant = fresh.get_value(section, key, null)
			if typeof(a) != typeof(b) or a != b:
				out.append([path, section, key, a, b])
	return out


## Enemies in play keep what their own state made of their kind's numbers
## (co-op's toughness, a variant, a run's scaling): each is scaled by the
## kind's new over old. How many changed.
func _scale_enemies(game: Game, before: Dictionary) -> int:
	var n := 0
	for e: Enemy in game.enemies:
		var was: Array = before.get(e.kind, [])
		var now: Array = Enemy.KINDS.get(e.kind, [])
		if was.is_empty() or now.is_empty() or was == now:
			continue
		var hp_k := _ratio(was[0], now[0])
		e.max_hp *= hp_k
		e.hp *= hp_k
		e.speed *= _ratio(was[1], now[1])
		e.radius *= _ratio(was[2], now[2])
		e.height *= _ratio(was[3], now[3])
		n += 1
	return n


static func _ratio(was: Variant, now: Variant) -> float:
	var a: float = was
	var b: float = now
	return b / a if absf(a) > 1e-9 else 1.0


func _where(file: String, section: String, key: String, set_now: Array, failed: Array) -> String:
	var quoted := '"%s"' % key
	var named := PackedStringArray()
	for row: Array in set_now:
		var expr: String = row[3]
		var label: String = row[0]
		if expr.contains(quoted) or expr.contains('"%s"' % section):
			named.append(label)
	if not named.is_empty():
		return "live: " + ", ".join(named)
	if file == "effects.cfg" and section.begins_with("level."):
		return "level: reload"
	if file in LOADED:
		return "live"
	for expr: String in failed:
		if expr.contains(quoted):
			return "restart the game"
	return "when read"


## The static vars that tuning feeds, worked out again from their own lines;
## each that changed is set. [[[label, old, new, expression], ...] set,
## [expression, ...] that could not be worked out].
func _refresh_statics() -> Array:
	_scan()
	var set_now: Array = []
	var failed: Array = []
	for row: Array in _statics:
		var path: String = row[0]
		var name: String = row[1]
		var expr_text: String = row[2]
		if not ResourceLoader.has_cached(path):
			continue  # not loaded yet: it reads the new numbers when it is
		var script: GDScript = load(path)
		var names := PackedStringArray()
		var inputs: Array = []
		for cls: String in _classes_in(expr_text):
			var class_path: String = _classes[cls]
			names.append(cls)
			inputs.append(load(class_path))
		var expr := Expression.new()
		if expr.parse(expr_text, names) != OK:
			failed.append(expr_text)
			continue
		var value: Variant = expr.execute(inputs, script, false)
		if expr.has_execute_failed():
			failed.append(expr_text)
			continue
		var old: Variant = script.get(name)
		if typeof(old) == TYPE_FLOAT and typeof(value) == TYPE_INT:
			var f: float = value
			value = f
		elif typeof(old) == TYPE_INT and typeof(value) == TYPE_FLOAT:
			var i: int = value
			value = i
		if typeof(old) != typeof(value) or typeof(old) == TYPE_OBJECT or old == value:
			continue
		if old is Array:
			var was: Array = old
			if was.is_typed():
				# Typed like the var (its own line made it so when it loaded).
				var plain: Array = value
				value = Array(
					plain,
					was.get_typed_builtin(),
					was.get_typed_class_name(),
					was.get_typed_script()
				)
		elif old is Dictionary:
			var table: Dictionary = old
			if table.is_typed():
				failed.append(expr_text)
				continue
		script.set(name, value)
		var label := "%s.%s" % [path.get_file().get_basename(), name]
		set_now.append([label, old, value, expr_text])
	return [set_now, failed]


## The global classes an expression names before a dot.
func _classes_in(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var re := RegEx.create_from_string("\\b([A-Z][A-Za-z0-9_]*)\\.")
	for m in re.search_all(text):
		var cls := m.get_string(1)
		if _classes.has(cls) and not out.has(cls):
			out.append(cls)
	return out


## Every `static var X = <expression>` in src/ whose expression reads tuning
## (one of READERS, or a static func of its own script in a script that names
## data/tuning), once.
func _scan() -> void:
	if _scanned:
		return
	_scanned = true
	for d: Dictionary in ProjectSettings.get_global_class_list():
		var cls: String = d["class"]
		var cls_path: String = d["path"]
		_classes[cls] = cls_path
	var head := RegEx.create_from_string("^static var (\\w+)\\s*(?::\\s*[^=]+?)?\\s*:?=\\s*(.+)$")
	var own_call := RegEx.create_from_string("(?<![\\w.])(_?[a-z]\\w*)\\(")
	for path in _scripts("res://src"):
		var text := FileAccess.get_file_as_string(path)
		var reads_tuning := text.contains("data/tuning")
		var lines := text.split("\n")
		var i := 0
		while i < lines.size():
			var line := lines[i].strip_edges(false, true)
			i += 1
			var m := head.search(line)
			if m == null:
				continue
			var expr := m.get_string(2)
			while TuneText.depth(expr) > 0 and i < lines.size():
				expr += " " + lines[i].strip_edges()
				i += 1
			if expr.ends_with(":") or not expr.contains("("):
				continue
			if expr.contains(".new(") or expr.contains("load("):
				continue
			var named := false
			for reader: String in READERS:
				named = named or expr.contains(reader)
			if not named and reads_tuning:
				# A reader of the script's own (kill_cam.gd _num("keep")), not a
				# value of its state (a constructor, a builtin).
				for call in own_call.search_all(expr):
					named = named or text.contains("static func %s(" % call.get_string(1))
			if named:
				_statics.append([path, m.get_string(1), expr])


static func _scripts(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"):
			out.append(dir.path_join(file))
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(sub)))
	return out


## How many statics are watched (tools/tune_check.gd).
func static_count() -> int:
	_scan()
	return _statics.size()
