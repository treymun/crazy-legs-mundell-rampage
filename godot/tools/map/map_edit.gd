## Targeted edits of a map source: each touches only the objects it names and
## leaves every other line of the file as it was. Before writing, the file as
## it was is kept in maps/.history/<id>/ (undo puts the newest back), and the
## change is summed up object by object, key by key. dry shows the summary and
## writes nothing. An edit that would leave the source unreadable (an unknown
## type, a missing key, an id used twice) is refused.
extends RefCounted

const Source := preload("res://tools/map/map_source.gd")


static func _dir(map_id: String) -> String:
	return ProjectSettings.globalize_path("%s/.history/%s" % [Source.dir, map_id])


## Keep a copy of `text` (kind "source" or "data") before it is written over.
static func keep(map_id: String, kind: String, text: String, what := "") -> String:
	var dir := _dir(map_id)
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "").replace(
		" ", "_"
	)
	var n := 0
	var path := ""
	while true:
		path = dir.path_join("%s_%s_%02d.json" % [stamp, kind, n])
		if not FileAccess.file_exists(path):
			break
		n += 1
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()
	if what != "":
		var log := FileAccess.open(dir.path_join("log.txt"), FileAccess.READ_WRITE)
		if log == null:
			log = FileAccess.open(dir.path_join("log.txt"), FileAccess.WRITE)
		log.seek_end()
		log.store_line("%s\t%s" % [path.get_file(), what])
		log.close()
	return path


## The kept copies, newest last: {file, kind, what}.
static func history(map_id: String) -> Array:
	var dir := _dir(map_id)
	var notes := {}
	if FileAccess.file_exists(dir.path_join("log.txt")):
		for line in FileAccess.get_file_as_string(dir.path_join("log.txt")).split("\n", false):
			var parts := line.split("\t")
			if parts.size() > 1:
				notes[parts[0]] = parts[1]
	var out: Array = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var files := Array(DirAccess.get_files_at(dir))
	files.sort()
	for f: String in files:
		if f.ends_with(".json"):
			out.append({"file": f, "kind": f.get_slice("_", 2), "what": notes.get(f, "")})
	return out


static func _point(text: String) -> Array:
	var out: Array = []
	for v in text.split(",", false):
		out.append(float(v))
	return out


static func _value(text: String):
	var json := JSON.new()
	if json.parse(text) == OK:
		return json.data
	return text


## Do `command` on map `map_id`: {summary (lines), changes, exit, error?}.
static func apply(map_id: String, command: String, rest: Array, opts: Dictionary) -> Dictionary:
	var errors: Array = []
	var doc := Source.read(map_id, errors)
	if doc.is_empty():
		return {"exit": 3, "error": errors[0]["message"] if not errors.is_empty() else "no source"}
	if command == "undo":
		return _undo(map_id, doc, opts)
	var before := doc.duplicate(true)
	var what := "%s %s" % [command, " ".join(PackedStringArray(rest))]
	var err := ""
	match command:
		"move":
			err = _move(doc, rest, opts)
		"resize":
			err = _resize(doc, rest, opts)
		"set":
			err = _set_keys(doc, rest, opts)
		"material":
			err = _material(doc, rest, opts)
		"add":
			err = _add(doc, rest, opts)
		"remove":
			err = _remove(doc, rest)
		"rename":
			err = _rename(doc, rest)
		"top":
			err = _top(doc, opts)
	if err != "":
		return {"exit": 2, "error": err}
	var changes := diff(before, doc)
	var summary: Array = describe(changes)
	if changes.is_empty():
		summary.append("nothing changed")
		return {"exit": 0, "summary": summary, "changes": changes}
	# Refuse what would leave the source unreadable.
	var fresh: Array = []
	for i: Dictionary in Source.check(doc, {}):
		if i["severity"] == "error":
			fresh.append(i)
	var old: Array = []
	for i: Dictionary in Source.check(before, {}):
		if i["severity"] == "error":
			old.append(String(i["message"]))
	for i: Dictionary in fresh:
		if not old.has(String(i["message"])):
			return {
				"exit": 1,
				"error": "refused, it would leave: " + String(i["message"]),
				"summary": summary
			}
	if opts.has("dry"):
		summary.append("dry: nothing written")
		return {"exit": 0, "summary": summary, "changes": changes}
	var kept := keep(map_id, "source", FileAccess.get_file_as_string(Source.path_of(map_id)), what)
	if not Source.write(map_id, doc):
		return {"exit": 3, "error": "could not write " + Source.path_of(map_id)}
	summary.append("wrote %s (the old one kept as %s)" % [Source.path_of(map_id), kept.get_file()])
	return {"exit": 0, "summary": summary, "changes": changes, "backup": kept}


static func _undo(map_id: String, doc: Dictionary, opts: Dictionary) -> Dictionary:
	var kept := history(map_id).filter(func(h): return h["kind"] == "source")
	if kept.is_empty():
		return {"exit": 2, "error": "nothing to undo for " + map_id}
	var last: Dictionary = kept[kept.size() - 1]
	var path := _dir(map_id).path_join(String(last["file"]))
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return {"exit": 3, "error": "the kept copy %s does not read" % last["file"]}
	var changes := diff(doc, parsed)
	var summary := describe(changes)
	summary.push_front("undo: back to before %s" % last.get("what", last["file"]))
	if opts.has("dry"):
		summary.append("dry: nothing written")
		return {"exit": 0, "summary": summary, "changes": changes}
	var now := keep(map_id, "redo", FileAccess.get_file_as_string(Source.path_of(map_id)), "")
	if not Source.write(map_id, parsed):
		return {"exit": 3, "error": "could not write"}
	# The copy put back is used up: renamed, never deleted (redo_ keeps what undo replaced).
	DirAccess.rename_absolute(path, path.trim_suffix(".json") + ".undone")
	summary.append(
		"wrote %s (what it replaced kept as %s)" % [Source.path_of(map_id), now.get_file()]
	)
	return {"exit": 0, "summary": summary, "changes": changes}


static func _object(doc: Dictionary, rest: Array) -> Dictionary:
	if rest.is_empty():
		return {}
	var i := Source.find(doc, String(rest[0]))
	return doc["objects"][i] if i >= 0 else {}


static func _move(doc: Dictionary, rest: Array, opts: Dictionary) -> String:
	var o := _object(doc, rest)
	if o.is_empty():
		return "no object %s" % (rest[0] if not rest.is_empty() else "named")
	var by := Vector3.ZERO
	if opts.has("by"):
		var p := _point(String(opts["by"]))
		by = Vector3(p[0], p[1], p[2] if p.size() > 2 else 0.0)
	elif opts.has("to"):
		var p := _point(String(opts["to"]))
		var anchor := _anchor(o)
		if anchor == Vector2.INF:
			return "%s has no place to move from" % o["id"]
		by = Vector3(p[0] - anchor.x, p[1] - anchor.y, 0.0)
	else:
		return "move needs by=dx,dy[,dz] or to=x,y"
	var grid: bool = Source.TYPES[String(o["type"])]["grid"]
	if grid and (by.x != floorf(by.x) or by.y != floorf(by.y)):
		return "%s is a %s (whole cells): move it by whole numbers" % [o["id"], o["type"]]
	_shift(o, by)
	return ""


static func _anchor(o: Dictionary) -> Vector2:
	if o.has("rect"):
		return Vector2(float(o["rect"][0]), float(o["rect"][1]))
	for key in ["at", "a", "cell"]:
		if o.has(key):
			return Vector2(float(o[key][0]), float(o[key][1]))
	if o.has("points"):
		return Vector2(float(o["points"][0][0]), float(o["points"][0][1]))
	return Vector2.INF


static func _shift(o: Dictionary, by: Vector3) -> void:
	if o.has("rect"):
		var r: Array = o["rect"]
		o["rect"] = [float(r[0]) + by.x, float(r[1]) + by.y, float(r[2]) + by.x, float(r[3]) + by.y]
	for key: String in Source.POINT_KEYS:
		if o.has(key):
			var p: Array = (o[key] as Array).duplicate()
			p[0] = float(p[0]) + by.x
			p[1] = float(p[1]) + by.y
			o[key] = p
	if o.has("points"):
		var pts: Array = []
		for p in o["points"]:
			pts.append([float(p[0]) + by.x, float(p[1]) + by.y])
		o["points"] = pts
	if o.has("cuts"):
		# Each line moves with it: c grows by n . (dx, dy).
		var cuts: Array = []
		for c in o["cuts"]:
			cuts.append([c[0], c[1], float(c[2]) + float(c[0]) * by.x + float(c[1]) * by.y])
		o["cuts"] = cuts
	if by.z != 0.0:
		for key in ["top", "z", "z0", "z1", "from", "to"]:
			if o.has(key):
				o[key] = float(o[key]) + by.z


static func _resize(doc: Dictionary, rest: Array, opts: Dictionary) -> String:
	var o := _object(doc, rest)
	if o.is_empty():
		return "no object %s" % (rest[0] if not rest.is_empty() else "named")
	if opts.has("rect"):
		if not o.has("rect"):
			return "%s has no rect" % o["id"]
		o["rect"] = _point(String(opts["rect"]))
	elif opts.has("opening"):
		var found := false
		for hole: Dictionary in o.get("openings", []):
			if String(hole.get("id", "")) == String(opts["opening"]):
				found = true
				for key in ["width", "at", "sill", "head"]:
					if opts.has(key):
						hole[key] = float(opts[key])
		if not found:
			return "%s has no opening %s" % [o["id"], opts["opening"]]
	elif opts.has("top"):
		o["top"] = float(opts["top"])
	elif opts.has("width"):
		o["width"] = float(opts["width"])
	else:
		return "resize needs rect=, opening= width=, top= or width="
	return ""


static func _set_keys(doc: Dictionary, rest: Array, opts: Dictionary) -> String:
	var o := _object(doc, rest)
	if o.is_empty():
		return "no object %s" % (rest[0] if not rest.is_empty() else "named")
	var any := false
	for key in opts:
		if key in ["dry", "json", "quiet", "force"]:
			continue
		if key == "id" or key == "type":
			return "set cannot change %s (rename changes an id)" % key
		o[key] = _value(String(opts[key]))
		any = true
	return "" if any else "set needs key=value"


## The source's own keys (not an object's): spawn, districts, meta, border,
## size, playtest, base.
static func _top(doc: Dictionary, opts: Dictionary) -> String:
	var any := false
	for key in opts:
		if key in ["dry", "json", "quiet", "force"]:
			continue
		if not (key in ["spawn", "districts", "meta", "border", "size", "playtest", "base"]):
			return "top sets spawn, districts, meta, border, size, playtest or base (not %s)" % key
		var value = _value(String(opts[key]))
		if key == "meta" and value is Dictionary and doc.get("meta") is Dictionary:
			# Merged: one key of meta changes, the rest stay.
			var meta: Dictionary = doc["meta"]
			meta.merge(value, true)
			value = meta
		doc[key] = value
		any = true
	return "" if any else "top needs key=<json>"


static func _material(doc: Dictionary, rest: Array, opts: Dictionary) -> String:
	if rest.size() < 2:
		return "material <from tile> <to tile> [in=<object>,...]"
	var from := String(rest[0])
	var to := String(rest[1])
	var only: Array = []
	if opts.has("in"):
		only = Array(String(opts["in"]).split(",", false))
	for o in doc.get("objects", []):
		if not (o is Dictionary) or (not only.is_empty() and not only.has(String(o.get("id", "")))):
			continue
		for key: String in Source.TILE_KEYS:
			if String(o.get(key, "")) == from:
				o[key] = to
	return ""


static func _add(doc: Dictionary, rest: Array, opts: Dictionary) -> String:
	if rest.is_empty():
		return "add needs an object as JSON"
	var o = JSON.parse_string(String(rest[0]))
	if not (o is Dictionary):
		return "add: %s is not a JSON object" % rest[0]
	if Source.find(doc, String(o.get("id", ""))) >= 0:
		return "an object %s exists already" % o.get("id")
	var objects: Array = doc.get("objects", [])
	if opts.has("after"):
		var i := Source.find(doc, String(opts["after"]))
		if i < 0:
			return "no object %s to add after" % opts["after"]
		objects.insert(i + 1, o)
	else:
		objects.append(o)
	doc["objects"] = objects
	return ""


static func _remove(doc: Dictionary, rest: Array) -> String:
	if rest.is_empty():
		return "remove <object>"
	var i := Source.find(doc, String(rest[0]))
	if i < 0:
		return "no object %s" % rest[0]
	(doc["objects"] as Array).remove_at(i)
	return ""


static func _rename(doc: Dictionary, rest: Array) -> String:
	if rest.size() < 2:
		return "rename <object> <new id>"
	var i := Source.find(doc, String(rest[0]))
	if i < 0:
		return "no object %s" % rest[0]
	if Source.find(doc, String(rest[1])) >= 0:
		return "an object %s exists already" % rest[1]
	doc["objects"][i]["id"] = String(rest[1])
	for o in doc["objects"]:
		if o is Dictionary and o.has("objects"):
			var names: Array = o["objects"]
			for k in names.size():
				if String(names[k]) == String(rest[0]):
					names[k] = String(rest[1])
	for route: Dictionary in doc.get("playtest", {}).get("routes", []):
		for key in ["from", "to"]:
			if String(route.get(key, "")) == String(rest[0]):
				route[key] = String(rest[1])
	return ""


## What changed between two sources: {added: [ids], removed: [ids], changed:
## {id: {key: [before, after]}}, top: {key: [before, after]}}.
static func diff(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {}
	var ia := {}
	var ib := {}
	for o in a.get("objects", []):
		if o is Dictionary:
			ia[String(o.get("id", ""))] = o
	for o in b.get("objects", []):
		if o is Dictionary:
			ib[String(o.get("id", ""))] = o
	var added: Array = []
	var removed: Array = []
	var changed := {}
	for k in ib:
		if not ia.has(k):
			added.append(k)
	for k in ia:
		if not ib.has(k):
			removed.append(k)
			continue
		var keys := {}
		for key in ia[k]:
			keys[key] = true
		for key in ib[k]:
			keys[key] = true
		var d := {}
		for key in keys:
			var va = ia[k].get(key)
			var vb = ib[k].get(key)
			if JSON.stringify(va) != JSON.stringify(vb):
				d[key] = [va, vb]
		if not d.is_empty():
			changed[k] = d
	var top := {}
	for key in b:
		if key != "objects" and JSON.stringify(a.get(key)) != JSON.stringify(b[key]):
			top[key] = [a.get(key), b[key]]
	if not added.is_empty():
		out["added"] = added
	if not removed.is_empty():
		out["removed"] = removed
	if not changed.is_empty():
		out["changed"] = changed
	if not top.is_empty():
		out["top"] = top
	return out


static func describe(changes: Dictionary) -> Array:
	var lines: Array = []
	for k in changes.get("added", []):
		lines.append("+ added %s" % k)
	for k in changes.get("removed", []):
		lines.append("- removed %s" % k)
	var changed: Dictionary = changes.get("changed", {})
	for k in changed:
		for key in changed[k]:
			var pair: Array = changed[k][key]
			lines.append(
				"~ %s.%s: %s -> %s" % [k, key, Source.compact(pair[0]), Source.compact(pair[1])]
			)
	var top: Dictionary = changes.get("top", {})
	for key in top:
		lines.append(
			"~ %s: %s -> %s" % [key, Source.compact(top[key][0]), Source.compact(top[key][1])]
		)
	return lines


## Write a built level to data/<id>.json (Source.data_dir): refused (exit 4)
## when that file was changed since the last build (built.json keeps each
## file's hash) unless `force`; the old file kept first. {exit, path,
## changed, error?}.
static func write_level(map_id: String, level: Dictionary, opts: Dictionary) -> Dictionary:
	var text := LevelEdit._json(level)
	var path := "%s/%s.json" % [Source.data_dir, map_id]
	var built := "%s/built.json" % Source.dir
	var parsed = (
		JSON.parse_string(FileAccess.get_file_as_string(built))
		if FileAccess.file_exists(built)
		else {}
	)
	var hashes: Dictionary = parsed if parsed is Dictionary else {}
	var old := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	if old != "" and hashes.has(map_id) and old.sha256_text() != String(hashes[map_id]):
		if not opts.has("force"):
			return {
				"exit": 4,
				"path": path,
				"error":
				(
					(
						"%s was changed since it was last built (the editor, F2 or level_edit.gd): "
						% path
					)
					+ (
						"put those changes into %s, or build with force (a copy is kept)"
						% Source.path_of(map_id)
					)
				)
			}
	if old == text:
		return {"exit": 0, "path": path, "changed": false}
	if opts.has("dry"):
		return {"exit": 0, "path": path, "changed": true, "dry": true}
	if old != "":
		keep(map_id, "data", old)
	var f := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.WRITE)
	if f == null:
		return {"exit": 3, "path": path, "error": "could not write " + path}
	f.store_string(text)
	f.close()
	hashes[map_id] = text.sha256_text()
	var h := FileAccess.open(ProjectSettings.globalize_path(built), FileAccess.WRITE)
	if h != null:
		h.store_line(JSON.stringify(hashes, "  ", true))
		h.close()
	return {"exit": 0, "path": path, "changed": true}
