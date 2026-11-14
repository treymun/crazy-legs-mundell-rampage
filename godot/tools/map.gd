## Map authoring from the command line (MAP_AUTHORING.md is the guide):
##
##   godot --headless --path godot --script res://tools/map.gd -- <command> [args]
##
## Commands (each prints what it did, then one line "MAP-RESULT {json}" an
## agent can parse; json alone prints only that line):
##   new <id> [size=WxH] [base=<plan id>]   a new source, maps/<id>.map.json
##   inspect <id>                            what it holds: objects, floors, nav
##   validate <id>                           errors and warnings (exit 1 on errors)
##   build <id> [dry] [force]                validate, then write data/<id>.json
##   render <id> [out=<dir>] [overlay=nav,collision,spawns,objects,unreachable]
##          [floor=<z>] [scale=<px>]          plans from above, one a floor
##   shot <id> out=<dir> [at=x,y[,z]] [angle=<deg>] [pitch=<deg>] [views=<json>]
##          [level=<level json>]             the game's own view from places (level=:
##                                           an older build as it is, for a before)
##   playtest <id> [scenario=<json>] [seconds=<s>] [perf]   bots walk routes
##   move <id> <object> by=dx,dy[,dz] | to=x,y
##   resize <id> <object> rect=x0,y0,x1,y1 | opening=<id> width=<w> | top=<z>
##   set <id> <object> key=<json value> [key=...]
##   material <id> <from tile> <to tile> [in=<object>,...]
##   add <id> '<object json>' [after=<object>]
##   remove <id> <object>
##   rename <id> <object> <new id>
##   top <id> key=<json>                     the source's own keys: spawn, districts,
##                                           meta (merged), border, size, playtest, base
##   undo <id>                               put back the source before the last edit
##   history <id>                            the edits kept for undo
##   catalog [out=<dir>]                     tiles, props, enemies, pickups, components
##   schema [out=<file>]                     the JSON Schema of a map source
##   import <id> <file.glb> [scale=1] [origin=x,y,z] [materials=<json>]
##          [prefix=<id>] [default_tile=<tile>] [skip_unsupported]
##                                           geometry from a glTF file into the source
##
## Every edit takes dry (show the change, write nothing); every edit and build
## backs the old file up under maps/.history/<id>/. Exit codes: 0 done, 1 the
## map has errors (or a playtest failed), 2 bad arguments, 3 a file could not
## be read or written, 4 refused (data/<id>.json was changed by hand since the
## last build: force keeps a copy and builds over it).
extends SceneTree

const Source := preload("res://tools/map/map_source.gd")
const Compile := preload("res://tools/map/map_compile.gd")
const Validate := preload("res://tools/map/map_validate.gd")
const Render := preload("res://tools/map/map_render.gd")
const Edit := preload("res://tools/map/map_edit.gd")
const Playtest := preload("res://tools/map/map_playtest.gd")
const Catalog := preload("res://tools/map/map_catalog.gd")
const Import := preload("res://tools/map/map_import.gd")

var args: Array = []
var opts := {}
var quiet := false
var result := {}
var assets: Assets


func _init() -> void:
	_main.call_deferred()


func say(text: String) -> void:
	if not quiet:
		print(text)


func _main() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		var eq := s.find("=")
		if eq > 0 and not s.begins_with("{") and not s.begins_with("["):
			opts[s.substr(0, eq)] = s.substr(eq + 1)
		elif s in ["dry", "force", "json", "perf", "enemies", "skip_unsupported", "quiet"]:
			opts[s] = true
		else:
			args.append(s)
	quiet = opts.has("json") or opts.has("quiet")
	if args.is_empty() or args[0] in ["help", "-h", "--help"]:
		print(_usage())
		await _finish(0 if not args.is_empty() else 2)
		return
	assets = Assets.new()
	var command := String(args[0])
	result = {"command": command, "ok": false}
	var code := 2
	match command:
		"new":
			code = _new()
		"inspect":
			code = _inspect()
		"validate":
			code = _validate()
		"build":
			code = _build()
		"render":
			code = _render()
		"shot":
			code = await _shot()
		"playtest":
			code = await _playtest()
		"move", "resize", "set", "material", "add", "remove", "rename", "undo", "top":
			code = _edit(command)
		"history":
			code = _history()
		"catalog":
			code = Catalog.write(
				String(opts.get("out", "res://../docs/map_catalog")), assets, result
			)
		"schema":
			code = Catalog.write_schema(
				String(opts.get("out", "res://../docs/map_schema.json")), result
			)
		"import":
			code = _import()
		_:
			result["error"] = "unknown command %s (map.gd -- help)" % command
	result["ok"] = code == 0
	result["exit"] = code
	await _finish(code)


func _finish(code: int) -> void:
	if not result.is_empty():
		print("MAP-RESULT " + JSON.stringify(result))
	await process_frame
	quit(code)


func _usage() -> String:
	var text := FileAccess.get_file_as_string("res://tools/map.gd")
	var lines := PackedStringArray()
	for line in text.split("\n"):
		if not line.begins_with("##"):
			break
		lines.append(line.substr(3))
	return "\n".join(lines)


func _need_id() -> String:
	if args.size() < 2:
		result["error"] = "%s needs a map id" % args[0]
		return ""
	return String(args[1])


func _names() -> Dictionary:
	var tiles := {}
	for t in assets.tile_index:
		tiles[String(t)] = true
	return {
		"tiles": tiles,
		"props": Catalog.prop_names(),
		"enemies": Catalog.enemy_names(),
		"pickups": Catalog.pickup_names(assets),
	}


## The source read and checked, compiled and validated: [doc, built, issues]
## (doc empty when it could not be read).
func _load(map_id: String) -> Array:
	var errors: Array = []
	var doc := Source.read(map_id, errors)
	if doc.is_empty():
		result["error"] = errors[0]["message"] if not errors.is_empty() else "no source"
		return [{}, {}, errors]
	var issues: Array = Source.check(doc, _names())
	var has_error := false
	for i: Dictionary in issues:
		if i["severity"] == "error":
			has_error = true
	if has_error:
		return [doc, {}, issues]
	var built := Compile.compile(doc)
	issues.append_array(built.get("issues", []))
	issues.append_array(Validate.check(doc, built, assets))
	return [doc, built, issues]


func _report(issues: Array) -> int:
	var errors := 0
	var warnings := 0
	for i: Dictionary in issues:
		if i["severity"] == "error":
			errors += 1
		else:
			warnings += 1
		var at := ""
		if i.has("at"):
			at = " at %s" % [i["at"]]
		var obj := "" if String(i.get("object", "")) == "" else " [%s]" % i["object"]
		say("%s %s%s%s: %s" % [String(i["severity"]).to_upper(), i["code"], obj, at, i["message"]])
		if i.has("hint"):
			say("      hint: " + String(i["hint"]))
	result["errors"] = errors
	result["warnings"] = warnings
	result["issues"] = issues
	return errors


# ------------------------------------------------------------- commands


func _new() -> int:
	var map_id := _need_id()
	if map_id == "":
		return 2
	if not RegEx.create_from_string(Source.ID_PATTERN).search(map_id):
		result["error"] = "id %s must match %s" % [map_id, Source.ID_PATTERN]
		return 2
	if Source.exists(map_id):
		result["error"] = "%s already exists" % Source.path_of(map_id)
		return 2
	var doc: Dictionary
	if opts.has("base"):
		doc = {
			"schema": Source.SCHEMA,
			"version": Source.VERSION,
			"id": map_id,
			"base": {"plan": String(opts["base"])},
			"meta": {},
			"objects": [],
		}
	else:
		var size := String(opts.get("size", "32x24")).split("x")
		doc = Source.blank(map_id, int(size[0]), int(size[1]))
	result["path"] = Source.path_of(map_id)
	if opts.has("dry"):
		say(Source.to_text(doc))
		return 0
	if not Source.write(map_id, doc):
		result["error"] = "could not write " + Source.path_of(map_id)
		return 3
	say("wrote " + Source.path_of(map_id))
	return 0


func _inspect() -> int:
	var map_id := _need_id()
	if map_id == "":
		return 2
	var loaded := _load(map_id)
	var doc: Dictionary = loaded[0]
	if doc.is_empty():
		return 3
	var counts := {}
	var objects: Array = []
	for o in doc.get("objects", []):
		if o is Dictionary:
			var type := String(o.get("type", "?"))
			counts[type] = int(counts.get(type, 0)) + 1
			var where = o.get("rect", o.get("at", o.get("a", o.get("cell", o.get("points", null)))))
			objects.append({"id": o.get("id"), "type": type, "where": where})
	result["id"] = map_id
	result["base"] = doc.get("base")
	result["counts"] = counts
	result["objects"] = objects
	say("%s: %d objects %s" % [map_id, objects.size(), counts])
	var built: Dictionary = loaded[1]
	if built.is_empty():
		_report(loaded[2])
		return 1
	var lv := LevelData.from_dict(built["level"], assets)
	result["size"] = [lv.width, lv.height]
	result["format"] = lv.format
	var field := FlowField.new(lv)
	field.reach = 1 << 20
	field.doors_open = true
	field.every_door = true
	var spawn: Array = built["spawn"]
	field.update(
		spawn[0],
		spawn[1],
		0.0,
		lv.floor_under(spawn[0], spawn[1], (spawn[3] if spawn.size() > 3 else 0.0) + .05)
	)
	var floors := Render.floors_of(lv, field)
	var per_floor := {}
	var nodes := 0
	var reached := 0
	var count := lv.width * lv.height if field.graph == null else field.graph.count
	for n in count:
		if field.open[n] == 0:
			continue
		nodes += 1
		if field.steps[n] < FlowField.FAR:
			reached += 1
		var z := 0.0 if field.graph == null else snappedf(field.graph.z[n], .05)
		var key := str(z)
		per_floor[key] = int(per_floor.get(key, 0)) + 1
	result["floors"] = floors
	result["walkable_by_height"] = per_floor
	result["nav_nodes"] = nodes
	result["reached_from_spawn"] = reached
	if lv.geo != null:
		result["geometry"] = {
			"slabs": lv.geo.slabs.size(),
			"segments": lv.geo.segments.size(),
			"ceilings": lv.geo.ceilings.size()
		}
	say(
		(
			"size %dx%d format %d, floors %s, walkable places %d (%d reached from the spawn)"
			% [lv.width, lv.height, lv.format, floors, nodes, reached]
		)
	)
	_report(loaded[2])
	return 0


func _validate() -> int:
	var map_id := _need_id()
	if map_id == "":
		return 2
	var loaded := _load(map_id)
	if (loaded[0] as Dictionary).is_empty():
		_report(loaded[2])
		return 3
	var errors := _report(loaded[2])
	say("%s: %d error(s), %d warning(s)" % [map_id, errors, int(result.get("warnings", 0))])
	return 1 if errors > 0 else 0


func _build() -> int:
	var map_id := _need_id()
	if map_id == "":
		return 2
	var loaded := _load(map_id)
	var doc: Dictionary = loaded[0]
	if doc.is_empty():
		_report(loaded[2])
		return 3
	var errors := _report(loaded[2])
	if errors > 0:
		say("not built: %d error(s)" % errors)
		return 1
	var built: Dictionary = loaded[1]
	var level: Dictionary = built["level"]
	var wrote := Edit.write_level(map_id, level, opts)
	result.merge(wrote)
	if wrote.has("error"):
		say(
			(
				"REFUSED " + String(wrote["error"])
				if int(wrote["exit"]) == 4
				else "ERROR " + String(wrote["error"])
			)
		)
		return int(wrote["exit"])
	if not bool(wrote.get("changed", false)):
		say("%s is already up to date" % wrote["path"])
	elif wrote.has("dry"):
		say("dry: would write %s" % wrote["path"])
	else:
		say("wrote %s" % wrote["path"])
	if opts.has("map"):
		var lv := LevelData.from_dict(level, assets)
		Render.render(doc, built, lv, String(opts["map"]).get_base_dir(), ["spawns", "objects"], 8)
	return 0


func _render() -> int:
	var map_id := _need_id()
	if map_id == "":
		return 2
	var loaded := _load(map_id)
	var doc: Dictionary = loaded[0]
	var built: Dictionary = loaded[1]
	if built.is_empty():
		_report(loaded[2])
		return 1 if not doc.is_empty() else 3
	_report(loaded[2])
	var lv := LevelData.from_dict(built["level"], assets)
	var dir := ProjectSettings.globalize_path(String(opts.get("out", "user://maps/%s" % map_id)))
	var overlays: Array = []
	for o in String(opts.get("overlay", "spawns,objects")).split(",", false):
		overlays.append(String(o))
	var paths := Render.render(
		doc,
		built,
		lv,
		dir,
		overlays,
		int(opts.get("scale", 16)),
		float(opts["floor"]) if opts.has("floor") else NAN
	)
	result["pictures"] = paths
	for p in paths:
		say("wrote " + String(p))
	return 0


func _shot() -> int:
	var map_id := _need_id()
	if map_id == "":
		return 2
	var built := {}
	if opts.has("level"):
		# A level file as it is (an older build, for a before picture).
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(String(opts["level"])))
		if not (parsed is Dictionary):
			result["error"] = "level=%s is not a level file" % opts["level"]
			return 3
		var sp: Array = parsed["spawn"]
		built = {"level": parsed, "spawn": sp}
	else:
		var loaded := _load(map_id)
		built = loaded[1]
		if built.is_empty():
			_report(loaded[2])
			return 1
	var views: Array = []
	if opts.has("views"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(String(opts["views"])))
		if not (parsed is Array):
			result["error"] = "views must be a JSON list of {tag, at, angle, pitch}"
			return 2
		views = parsed
	else:
		var spawn: Array = built["spawn"]
		var at := (
			String(
				opts.get(
					"at", "%s,%s,%s" % [spawn[0], spawn[1], spawn[3] if spawn.size() > 3 else 0.0]
				)
			)
			. split(",")
		)
		(
			views
			. append(
				{
					"tag": String(opts.get("tag", "view")),
					"at": [float(at[0]), float(at[1]), float(at[2]) if at.size() > 2 else 0.0],
					"angle": float(opts.get("angle", rad_to_deg(spawn[2]))),
					"pitch": float(opts.get("pitch", 0.0)),
				}
			)
		)
	var dir := ProjectSettings.globalize_path(
		String(opts.get("out", "user://maps/%s/shots" % map_id))
	)
	var paths: Array = await Playtest.shots(self, map_id, built["level"], views, dir)
	result["pictures"] = paths
	for p in paths:
		say("wrote " + String(p))
	return 0


func _playtest() -> int:
	var map_id := _need_id()
	if map_id == "":
		return 2
	var loaded := _load(map_id)
	var doc: Dictionary = loaded[0]
	var built: Dictionary = loaded[1]
	if built.is_empty():
		_report(loaded[2])
		return 1
	var scenario: Dictionary = doc.get("playtest", {})
	if opts.has("scenario"):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(String(opts["scenario"])))
		if not (parsed is Dictionary):
			result["error"] = "scenario must be a JSON object"
			return 2
		scenario = parsed
	var report: Dictionary = await Playtest.run(self, doc, built, scenario, opts)
	result.merge(report)
	for line: String in report.get("lines", []):
		say(line)
	result.erase("lines")
	return 0 if bool(report.get("passed", false)) else 1


func _edit(command: String) -> int:
	var map_id := _need_id()
	if map_id == "":
		return 2
	var out := Edit.apply(map_id, command, args.slice(2), opts)
	result.merge(out)
	for line: String in out.get("summary", []):
		say(line)
	if out.has("error"):
		say("ERROR " + String(out["error"]))
	return int(out.get("exit", 0))


func _history() -> int:
	var map_id := _need_id()
	if map_id == "":
		return 2
	result["history"] = Edit.history(map_id)
	for h: Dictionary in result["history"]:
		say("%s  %s" % [h["file"], h.get("what", "")])
	return 0


func _import() -> int:
	var map_id := _need_id()
	if map_id == "" or args.size() < 3:
		result["error"] = "import <id> <file.glb>"
		return 2
	var out := Import.run(map_id, String(args[2]), opts, assets)
	result.merge(out)
	for line: String in out.get("summary", []):
		say(line)
	return int(out.get("exit", 0))
