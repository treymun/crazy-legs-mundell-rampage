## A map source open for editing (the Godot editor's Maps screen,
## addons/clmr_maps): the source as read, every change one undo step,
## saved back exactly as the command-line tools write it, so a source opened
## and saved with no change is the same file, and keys the screen does not
## know (an object's _note, a type's extra key) go back out untouched. Kept
## free of the editor, so tools/map_check.gd can drive it headless.
extends RefCounted

const Source := preload("res://tools/map/map_source.gd")
const Compile := preload("res://tools/map/map_compile.gd")
const Validate := preload("res://tools/map/map_validate.gd")
const Edit := preload("res://tools/map/map_edit.gd")
const Catalog := preload("res://tools/map/map_catalog.gd")

var map_id := ""
var doc := {}
## The file as it was read (what save compares against).
var saved_text := ""
var undo_stack: Array = []
var redo_stack: Array = []
var issues: Array = []
## The last build of the source (map_compile.compile()): its level and spawn.
var built := {}


static func list() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := ProjectSettings.globalize_path(Source.dir)
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".map.json"):
				out.append(f.trim_suffix(".map.json"))
	out.sort()
	return out


func open(id: String) -> String:
	var errors: Array = []
	var read := Source.read(id, errors)
	if read.is_empty():
		return String(errors[0]["message"]) if not errors.is_empty() else "cannot read " + id
	map_id = id
	doc = read
	saved_text = FileAccess.get_file_as_string(Source.path_of(id))
	undo_stack.clear()
	redo_stack.clear()
	issues.clear()
	built = {}
	return ""


func dirty() -> bool:
	return Source.to_text(doc) != saved_text


## One change: `change` takes the source and changes it (returns "" or why
## not). The source before it goes on the undo stack.
func change(what: String, change_fn: Callable) -> String:
	var before := doc.duplicate(true)
	var err: String = change_fn.call(doc)
	if err != "":
		doc = before
		return err
	if Source.compact(before) == Source.compact(doc):
		return "nothing changed"
	# Refused when it leaves the source with an error it did not have.
	var old := {}
	for i: Dictionary in Source.check(before, {}):
		old[String(i["message"])] = true
	for i: Dictionary in Source.check(doc, {}):
		if i["severity"] == "error" and not old.has(String(i["message"])):
			doc = before
			return "refused: " + String(i["message"])
	undo_stack.append([what, before])
	redo_stack.clear()
	built = {}
	return ""


func undo() -> String:
	if undo_stack.is_empty():
		return "nothing to undo"
	var step: Array = undo_stack.pop_back()
	redo_stack.append([step[0], doc.duplicate(true)])
	doc = step[1]
	built = {}
	return "undid " + String(step[0])


func redo() -> String:
	if redo_stack.is_empty():
		return "nothing to redo"
	var step: Array = redo_stack.pop_back()
	undo_stack.append([step[0], doc.duplicate(true)])
	doc = step[1]
	built = {}
	return "redid " + String(step[0])


func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for o in doc.get("objects", []):
		if o is Dictionary:
			out.append(String(o.get("id", "")))
	return out


func object(id: String) -> Dictionary:
	var i := Source.find(doc, id)
	return doc["objects"][i] if i >= 0 else {}


## Replace an object with `text` (its JSON): refused when it does not read,
## changes its id to one in use, or leaves the source with a new error.
func set_object(id: String, text: String) -> String:
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return "that is not a JSON object"
	return change(
		"edit " + id,
		func(d: Dictionary) -> String:
			var i := Source.find(d, id)
			if i < 0:
				return "no object " + id
			var new_id := String(parsed.get("id", ""))
			if new_id != id and Source.find(d, new_id) >= 0:
				return "an object %s exists already" % new_id
			d["objects"][i] = parsed
			return ""
	)


## A new object of `type` (its catalog example) at `at`, with an id of its own.
func add(type: String, at: Vector2) -> String:
	if not Source.TYPES.has(type):
		return "no type " + type
	var o := Catalog.example(type)
	var n := 1
	while Source.find(doc, "%s_%d" % [type, n]) >= 0:
		n += 1
	o["id"] = "%s_%d" % [type, n]
	var anchor := Edit._anchor(o)
	if anchor != Vector2.INF:
		var by := (
			(at - anchor).floor()
			if Source.TYPES[type]["grid"]
			else (at - anchor).snapped(Vector2(.25, .25))
		)
		Edit._shift(o, Vector3(by.x, by.y, 0.0))
	return change(
		"add " + String(o["id"]),
		func(d: Dictionary) -> String:
			d["objects"].append(o)
			return ""
	)


func remove(id: String) -> String:
	return change("remove " + id, func(d: Dictionary) -> String: return Edit._remove(d, [id]))


## Move an object by (dx, dy): whole cells for one that changes cells.
func move(id: String, by: Vector2) -> String:
	var o := object(id)
	if o.is_empty():
		return "no object " + id
	if bool(Source.TYPES.get(String(o.get("type", "")), {}).get("grid", false)):
		by = by.round()
	else:
		by = by.snapped(Vector2(.05, .05))
	if by == Vector2.ZERO:
		return "nothing changed"
	return change(
		"move " + id,
		func(d: Dictionary) -> String:
			Edit._shift(d["objects"][Source.find(d, id)], Vector3(by.x, by.y, 0.0))
			return ""
	)


## The object nearest map point `at` (its anchor or its rect containing it).
func pick(at: Vector2) -> String:
	var best := ""
	var best_d := 1.5
	for o in doc.get("objects", []):
		if not (o is Dictionary):
			continue
		var type := String(o.get("type", ""))
		if type in ["yard", "paint", "light", "raise"]:
			continue
		var d := INF
		if o.has("rect"):
			var r: Array = o["rect"]
			if (
				at.x >= float(r[0])
				and at.x <= float(r[2])
				and at.y >= float(r[1])
				and at.y <= float(r[3])
			):
				d = .5 + minf(float(r[2]) - float(r[0]), float(r[3]) - float(r[1])) * .1
		elif o.has("a"):
			d = (
				Geometry2D
				. get_closest_point_to_segment(
					at, Vector2(o["a"][0], o["a"][1]), Vector2(o["b"][0], o["b"][1])
				)
				. distance_to(at)
			)
		else:
			var anchor := Edit._anchor(o)
			if anchor != Vector2.INF:
				d = anchor.distance_to(at)
		if d < best_d:
			best_d = d
			best = String(o["id"])
	return best


func check(assets: Assets) -> Array:
	issues = Source.check(doc, {})
	var has_error := false
	for i: Dictionary in issues:
		if i["severity"] == "error":
			has_error = true
	if not has_error:
		built = Compile.compile(doc)
		issues.append_array(built.get("issues", []))
		issues.append_array(Validate.check(doc, built, assets))
	return issues


func save() -> String:
	var text := Source.to_text(doc)
	if text == saved_text:
		return "%s has no changes" % Source.path_of(map_id)
	Edit.keep(map_id, "source", saved_text, "saved from the Maps screen")
	if not Source.write(map_id, doc):
		return "could not write " + Source.path_of(map_id)
	saved_text = text
	return "saved %s" % Source.path_of(map_id)


## Validate, then write data/<id>.json as `map.gd -- build` does (refused when
## that file was changed by hand since its last build, unless force).
func build(assets: Assets, force := false) -> String:
	var found := check(assets)
	var errors := 0
	for i: Dictionary in found:
		if i["severity"] == "error":
			errors += 1
	if errors > 0:
		return "not built: %d error(s)" % errors
	var out := Edit.write_level(map_id, built["level"], {"force": true} if force else {})
	if out.has("error"):
		return String(out["error"])
	return (
		"built %s" % out["path"]
		if bool(out.get("changed", false))
		else "%s is up to date" % out["path"]
	)
