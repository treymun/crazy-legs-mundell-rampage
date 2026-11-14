## Checks of the map tools (tools/map.gd, tools/map/): run by
## tools/geometry_check.gd, and through it by check_fixes.gd. Everything here
## works in a scratch folder (Source.dir, Source.data_dir pointed at the cache
## folder): the repo's maps and data are only read.
##
## - the source checks name the object and the problem (bad and duplicate ids,
##   unknown types and keys, missing keys, grid rects not whole, tiles that do
##   not exist, rects off the map);
## - the demo map (maps/feedstore.map.json) compiles and validates clean;
## - broken copies of it are caught: a wall through a deck, a hand in a block,
##   stairs whose foot is walled off, a deck nothing reaches, a door blocked;
##   allow_overlap lets a named overlap through;
## - targeted edits change their object only (every other object's text the
##   same), a dry run writes nothing, undo puts the file back byte for byte,
##   rename follows references, a bad edit is refused; keys a type does not
##   know survive a save;
## - a build refuses to write over a level changed by hand, and force keeps a
##   copy;
## - a glTF file made here imports as a deck, a wall with its doorway, a ramp,
##   and refuses a slanted face unless told to leave it out;
## - the editor's Maps screen opens a source and saves it back unchanged,
##   then adds, moves and edits objects (one undo step each), keeps keys it
##   does not know, and builds a level that loads;
## - a bot walks the demo map from the spawn up to the loft's lever, and hands
##   woken under the loft, on the dock and in the yard all come up to a player
##   standing on it.
extends RefCounted

const Source := preload("res://tools/map/map_source.gd")
const Compile := preload("res://tools/map/map_compile.gd")
const Validate := preload("res://tools/map/map_validate.gd")
const Edit := preload("res://tools/map/map_edit.gd")
const Import := preload("res://tools/map/map_import.gd")
const Playtest := preload("res://tools/map/map_playtest.gd")


static func _codes(issues: Array, severity := "error") -> Dictionary:
	var out := {}
	for i: Dictionary in issues:
		if i["severity"] == severity:
			out[String(i["code"]) + "|" + String(i.get("object", ""))] = true
	return out


static func _has(issues: Array, code: String, object_id: String) -> bool:
	return _codes(issues).has(code + "|" + object_id)


static func run(main, check: Callable) -> void:
	print("MAP TOOLS: SOURCE CHECKS, VALIDATION, TARGETED EDITS, BUILDS, IMPORT, PLAYTEST")
	var assets: Assets = main.art
	var demo := Source.read("feedstore")
	check.call(not demo.is_empty(), "the demo map's source reads")
	if demo.is_empty():
		return
	var kept_dir := Source.dir
	var kept_data := Source.data_dir
	var scratch := OS.get_cache_dir().path_join("clmr_map_check")
	DirAccess.make_dir_recursive_absolute(scratch.path_join("data"))
	# What a run before this one left (this check's own files only).
	for name in ["built.json", "data/buildme.json", "data/roundtrip.json"]:
		if FileAccess.file_exists(scratch.path_join(name)):
			DirAccess.remove_absolute(scratch.path_join(name))
	Source.dir = scratch
	Source.data_dir = scratch.path_join("data")
	_source_checks(demo, check)
	_validation(demo, assets, check)
	_edits(demo, check)
	_build_guard(demo, check)
	_import(assets, check)
	_editor(main, demo, check)
	Source.dir = kept_dir
	Source.data_dir = kept_data
	_playtest(main, demo, check)
	climbers(main, demo, check)


static func _names(assets: Assets) -> Dictionary:
	var tiles := {}
	for t in assets.tile_index:
		tiles[String(t)] = true
	return {"tiles": tiles}


static func _source_checks(demo: Dictionary, check: Callable) -> void:
	var names := _names(Assets.new())
	check.call(Source.check(demo, names).is_empty(), "the demo source has no problems")
	var bad := demo.duplicate(true)
	var objects: Array = bad["objects"]
	objects.append({"id": "Bad Id", "type": "yard", "rect": [1, 1, 2, 2], "floor": "dirt"})
	objects.append({"id": "loft", "type": "deck", "rect": [1, 1, 2, 2], "top": 1.0})
	objects.append({"id": "mystery", "type": "teleporter", "at": [1, 1]})
	objects.append({"id": "no_top", "type": "deck", "rect": [1, 1, 2, 2]})
	objects.append({"id": "half_cell", "type": "yard", "rect": [1.5, 1, 3, 2], "floor": "dirt"})
	objects.append(
		{"id": "no_such_tile", "type": "paint", "rect": [1, 1, 2, 2], "floor": "gold_bricks"}
	)
	objects.append({"id": "far_away", "type": "yard", "rect": [1, 1, 300, 2], "floor": "dirt"})
	objects.append(
		{"id": "chatty", "type": "pickup", "name": "shells", "at": [3, 3], "colour": "red"}
	)
	var issues := Source.check(bad, names)
	check.call(_has(issues, "bad_id", "Bad Id"), "a bad id is named")
	check.call(_has(issues, "duplicate_id", "loft"), "a second object with an id is named")
	check.call(_has(issues, "unknown_type", "mystery"), "an unknown type is named")
	check.call(_has(issues, "missing", "no_top"), "a missing key is named")
	check.call(
		_has(issues, "grid_rect", "half_cell"), "a grid rect that is not whole cells is named"
	)
	check.call(_has(issues, "no_tile", "no_such_tile"), "a tile that does not exist is named")
	check.call(_has(issues, "outside", "far_away"), "a rect off the map is named")
	check.call(
		_codes(issues, "warning").has("unknown_key|chatty"), "an unknown key is a warning, kept"
	)


static func _validation(demo: Dictionary, assets: Assets, check: Callable) -> void:
	var built := Compile.compile(demo)
	var issues := Validate.check(demo, built, assets)
	check.call(
		_codes(issues).is_empty(),
		"the demo map validates with no errors (%d issues)" % issues.size()
	)
	var level: Dictionary = built["level"]
	check.call(int(level.get("format", 1)) == 2, "it builds as level format 2")
	var ids := {}
	for s: Dictionary in level["geometry"]["slabs"]:
		ids[String(s["id"])] = true
	for s: Dictionary in level["geometry"]["segments"]:
		ids[String(s["id"])] = true
	check.call(
		ids.has("loft") and ids.has("dock") and ids.has("partition_0"),
		"its pieces keep the source's ids"
	)
	# Broken copies.
	var broken := demo.duplicate(true)
	var objects: Array = broken["objects"]
	objects.append(
		{"id": "through_loft", "type": "wall", "a": [12, 5], "b": [12, 7.5], "z0": 0, "z1": 3.0}
	)
	objects.append({"id": "boxed_in", "type": "enemy", "kind": "billy", "at": [19, 10]})
	broken["objects"] = objects
	var b2 := Compile.compile(broken)
	issues = Validate.check(broken, b2, assets)
	check.call(
		_has(issues, "overlap", "through_loft"), "a wall through the loft is an overlap, named"
	)
	check.call(_has(issues, "inside", "boxed_in"), "a hand standing in the dock block is named")
	var allowed := broken.duplicate(true)
	allowed["objects"].append(
		{
			"id": "on_purpose",
			"type": "allow_overlap",
			"objects": ["through_loft", "loft"],
			"reason": "test"
		}
	)
	issues = Validate.check(allowed, Compile.compile(allowed), assets)
	check.call(
		not _has(issues, "overlap", "through_loft"), "allow_overlap lets that overlap through"
	)
	var walled := demo.duplicate(true)
	var i := Source.find(walled, "loft_stairs")
	walled["objects"][i]["rect"] = [5, 4, 10, 5.2]
	issues = Validate.check(walled, Compile.compile(walled), assets)
	check.call(
		_has(issues, "stairs_foot", "loft_stairs"), "stairs whose foot is walled off are named"
	)
	var cut := demo.duplicate(true)
	cut["objects"].remove_at(Source.find(cut, "loft_stairs"))
	issues = Validate.check(cut, Compile.compile(cut), assets)
	check.call(
		_has(issues, "floor_unreachable", "loft"), "the loft with no stairs is unreachable, named"
	)
	check.call(_has(issues, "unreachable", "chute_lever"), "and so is its lever")
	var jammed := demo.duplicate(true)
	jammed["objects"].append(
		{"id": "door_jam", "type": "block", "rect": [8.7, 10.6, 9.3, 11.4], "top": 1.0}
	)
	issues = Validate.check(jammed, Compile.compile(jammed), assets)
	check.call(
		_has(issues, "blocked_doorway", "store_door"), "a block standing in the store door is named"
	)


static func _object_texts(doc: Dictionary) -> Dictionary:
	var out := {}
	for o in doc.get("objects", []):
		out[String(o.get("id", ""))] = Source.compact(o)
	return out


static func _edits(demo: Dictionary, check: Callable) -> void:
	var map_id := "editme"
	var doc := demo.duplicate(true)
	doc["id"] = map_id
	doc["objects"][0]["_note"] = "kept as it is"
	doc["objects"][0]["custom_key"] = 7
	Source.write(map_id, doc)
	var round := Source.read(map_id)
	check.call(
		Source.compact(round) == Source.compact(doc),
		"a source reads back as it was written (unknown keys too)"
	)
	var before_text := FileAccess.get_file_as_string(Source.path_of(map_id))
	var before := _object_texts(round)
	var out := Edit.apply(map_id, "move", ["partition"], {"by": "0,1", "dry": true})
	check.call(
		(
			FileAccess.get_file_as_string(Source.path_of(map_id)) == before_text
			and out.get("changes", {}).has("changed")
		),
		"a dry run shows the change and writes nothing"
	)
	out = Edit.apply(map_id, "move", ["partition"], {"by": "0,1"})
	var after := _object_texts(Source.read(map_id))
	var others_same := true
	for k in before:
		if k != "partition" and before[k] != after[k]:
			others_same = false
	check.call(
		int(out["exit"]) == 0 and before["partition"] != after["partition"] and others_same,
		"move changes the partition and nothing else"
	)
	out = Edit.apply(map_id, "resize", ["partition"], {"opening": "stock_door", "width": "1.4"})
	var part: Dictionary = Source.read(map_id)["objects"][Source.find(
		Source.read(map_id), "partition"
	)]
	check.call(
		float(part["openings"][0]["width"]) == 1.4 and float(part["openings"][1]["width"]) == 1.0,
		"resize widens one opening only"
	)
	out = Edit.apply(map_id, "material", ["plaster", "brick"], {"in": "office"})
	var now := Source.read(map_id)
	check.call(
		(
			String(now["objects"][Source.find(now, "office")]["wall"]) == "brick"
			and String(now["objects"][Source.find(now, "partition")]["tile"]) == "plaster"
		),
		"a material swap in one object leaves the rest"
	)
	out = Edit.apply(
		map_id, "add", ['{"id": "loft", "type": "deck", "rect": [1, 1, 2, 2], "top": 1}'], {}
	)
	check.call(int(out["exit"]) != 0, "adding a second object with an id is refused")
	out = Edit.apply(map_id, "set", ["loft"], {"id": '"other"'})
	check.call(int(out["exit"]) != 0, "set cannot change an id")
	out = Edit.apply(map_id, "add", ['{"id": "oops", "type": "teleporter"}'], {})
	check.call(int(out["exit"]) == 1, "an edit that leaves an unknown type is refused")
	(
		Edit
		. apply(
			map_id,
			"add",
			[
				'{"id": "ok_overlap", "type": "allow_overlap", "objects": ["loft", "partition"], "reason": "x"}'
			],
			{}
		)
	)
	Edit.apply(map_id, "rename", ["partition", "stock_wall"], {})
	now = Source.read(map_id)
	check.call(
		(
			Source.find(now, "stock_wall") >= 0
			and (now["objects"][Source.find(now, "ok_overlap")]["objects"] as Array).has(
				"stock_wall"
			)
		),
		"rename follows the references to it"
	)
	var mid_text := FileAccess.get_file_as_string(Source.path_of(map_id))
	Edit.apply(map_id, "remove", ["dock_crates"], {})
	Edit.apply(map_id, "undo", [], {})
	check.call(
		FileAccess.get_file_as_string(Source.path_of(map_id)) == mid_text,
		"undo puts the source back byte for byte"
	)
	check.call(
		Edit.history(map_id).size() >= 6,
		"every edit kept a copy (%d)" % Edit.history(map_id).size()
	)


static func _build_guard(demo: Dictionary, check: Callable) -> void:
	var map_id := "buildme"
	var doc := demo.duplicate(true)
	doc["id"] = map_id
	Source.write(map_id, doc)
	var level: Dictionary = Compile.compile(doc)["level"]
	var out := Edit.write_level(map_id, level, {})
	check.call(int(out["exit"]) == 0 and bool(out["changed"]), "a build writes the level")
	out = Edit.write_level(map_id, level, {})
	check.call(int(out["exit"]) == 0 and not bool(out["changed"]), "building again changes nothing")
	var path := "%s/%s.json" % [Source.data_dir, map_id]
	var f := FileAccess.open(path, FileAccess.READ_WRITE)
	f.seek_end()
	f.store_string(" ")
	f.close()
	out = Edit.write_level(map_id, level, {})
	check.call(int(out["exit"]) == 4, "a level changed by hand since its build is not written over")
	var copies := Edit.history(map_id).size()
	out = Edit.write_level(map_id, level, {"force": true})
	check.call(
		int(out["exit"]) == 0 and Edit.history(map_id).size() == copies + 1,
		"force builds over it and keeps a copy"
	)


## A small glTF file: a deck, a wall with a doorway (two piers and a lintel),
## a ramp, and (when `slanted`) a leaning face the game cannot draw.
static func make_gltf(path: String, slanted: bool) -> void:
	var root := Node3D.new()
	root.name = "Shed"
	var planks := StandardMaterial3D.new()
	planks.resource_name = "Planks"
	var brick := StandardMaterial3D.new()
	brick.resource_name = "Brick"
	for spec: Array in [
		["Deck", Vector3(4, .2, 3), Vector3(6, 1.5, 4), planks],
		["PierA", Vector3(1.5, 2.2, .2), Vector3(2.75, 1.1, 8), brick],
		["PierB", Vector3(1.5, 2.2, .2), Vector3(5.25, 1.1, 8), brick],
		["Lintel", Vector3(1.0, .35, .2), Vector3(4.0, 2.025, 8), brick],
	]:
		var m := MeshInstance3D.new()
		m.name = spec[0]
		var box := BoxMesh.new()
		box.size = spec[1]
		box.material = spec[3]
		m.mesh = box
		m.position = spec[2]
		root.add_child(m)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(planks)
	# A ramp top from y 0 at z 10 to y 1 at z 13, x 2..4, facing up.
	var q := [Vector3(2, 0, 10), Vector3(4, 0, 10), Vector3(4, 1, 13), Vector3(2, 1, 13)]
	for idx in [0, 1, 2, 0, 2, 3]:
		st.add_vertex(q[idx])
	st.generate_normals()
	var ramp := MeshInstance3D.new()
	ramp.name = "Ramp"
	ramp.mesh = st.commit()
	root.add_child(ramp)
	if slanted:
		var s2 := SurfaceTool.new()
		s2.begin(Mesh.PRIMITIVE_TRIANGLES)
		s2.set_material(brick)
		var w := [Vector3(8, 0, 10), Vector3(10, 0, 10), Vector3(10, 2, 11), Vector3(8, 2, 11)]
		for idx in [0, 2, 1, 0, 3, 2]:
			s2.add_vertex(w[idx])
		var lean := MeshInstance3D.new()
		lean.name = "Lean"
		lean.mesh = s2.commit()
		root.add_child(lean)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_scene(root, state)
	doc.write_to_filesystem(state, path)
	root.free()


static func _import(assets: Assets, check: Callable) -> void:
	var map_id := "importme"
	Source.write(map_id, Source.blank(map_id, 16, 16))
	var dir := Source.dir
	var glb := dir.path_join("shed.glb")
	make_gltf(glb, false)
	var mats := dir.path_join("mats.json")
	var f := FileAccess.open(mats, FileAccess.WRITE)
	f.store_string('{"Planks": "porch", "Brick": "brick"}')
	f.close()
	var out := Import.run(map_id, glb, {"materials": mats, "prefix": "shed"}, assets)
	check.call(int(out["exit"]) == 0, "a glTF file imports (%s)" % out.get("error", ""))
	var doc := Source.read(map_id)
	var by_type := {}
	var door_gap := false
	for o in doc["objects"]:
		by_type[String(o["type"])] = int(by_type.get(String(o["type"]), 0)) + 1
		if (
			String(o["type"]) == "deck"
			and absf(float(o["top"]) - 1.6) < .02
			and absf(float(o["thick"]) - .2) < .02
		):
			by_type["deck_ok"] = 1
		if (
			String(o["type"]) == "ramp"
			and String(o["toward"]) == "s"
			and absf(float(o["to"]) - 1.0) < .02
		):
			by_type["ramp_ok"] = 1
		if String(o["type"]) == "wall" and absf(float(o["z0"]) - 1.85) < .03:
			door_gap = true
	check.call(by_type.has("deck_ok"), "its deck comes in 1.6 up and .2 thick")
	check.call(by_type.has("ramp_ok"), "its ramp comes in rising south to 1.0")
	check.call(
		door_gap and int(by_type.get("wall", 0)) >= 3,
		"its wall comes in round a doorway 1.85 high (%d pieces)" % int(by_type.get("wall", 0))
	)
	var first := int(by_type.get("wall", 0))
	out = Import.run(map_id, glb, {"materials": mats, "prefix": "shed"}, assets)
	var again := 0
	for o in Source.read(map_id)["objects"]:
		if String(o["type"]) == "wall":
			again += 1
	check.call(
		int(out["exit"]) == 0 and again == first,
		"importing it again replaces its own objects, not adds"
	)
	make_gltf(glb, true)
	out = Import.run(map_id, glb, {"materials": mats, "prefix": "shed"}, assets)
	check.call(
		int(out["exit"]) == 1 and String(out.get("error", "")).contains("cannot draw"),
		"a slanted face is refused, not flattened"
	)
	out = Import.run(
		map_id, glb, {"materials": mats, "prefix": "shed", "skip_unsupported": true}, assets
	)
	check.call(
		int(out["exit"]) == 0 and not (out.get("issues", []) as Array).is_empty(),
		"skip_unsupported leaves it out and says so"
	)
	out = Import.run(map_id, glb, {"prefix": "shed"}, assets)
	check.call(
		int(out["exit"]) == 1 and String(out.get("error", "")).contains("Planks"),
		"unmapped materials are named"
	)


static func _playtest(main, demo: Dictionary, check: Callable) -> void:
	var built := Compile.compile(demo)
	LevelData.preview["feedstore"] = built["level"]
	var g: Game = main.make_game("feedstore")
	g.configure({})
	g.cheats.god = true
	for e: Enemy in g.enemies:
		e.dormant = true
	var a := Playtest.place("spawn", demo, built, g.world)
	var b := Playtest.place("chute_lever", demo, built, g.world)
	var walk := Playtest.walk(g, a, b, 20.0, [])
	LevelData.preview.erase("feedstore")
	check.call(
		bool(walk["reached"]),
		(
			"a bot walks from the spawn up the stairs to the loft's lever (%.1f s)"
			% float(walk["seconds"])
		)
	)
	check.call(absf(g.world.stand(g.player) - 1.7) < .05, "and stands on the loft")


static func _editor(main, demo: Dictionary, check: Callable) -> void:
	var map_id := "roundtrip"
	var doc := demo.duplicate(true)
	doc["id"] = map_id
	doc["objects"][2]["_note"] = "the screen must keep this"
	Source.write(map_id, doc)
	var original := FileAccess.get_file_as_string(Source.path_of(map_id))
	var panel = preload("res://addons/clmr_maps/map_panel.gd").new()
	main.add_child(panel)
	panel.open()
	panel.load_map(map_id)
	check.call(
		panel.plan != null and panel.plan.get_width() > 0 and panel.floors.size() >= 2,
		"the Maps screen draws the source (%d floors)" % panel.floors.size()
	)
	panel.save()
	check.call(
		FileAccess.get_file_as_string(Source.path_of(map_id)) == original,
		"opened and saved with no change, the file is the same"
	)
	panel.cursor = Vector2(23.5, 13.5)
	panel.add_object("pickup")
	var added: String = panel.selected
	check.call(
		added.begins_with("pickup_") and not panel.document.object(added).is_empty(),
		"Add puts a new pickup where the map was clicked"
	)
	panel.move_selected(Vector2(1.0, 0.0))
	panel.select("dock")
	var dock: Dictionary = panel.document.object("dock").duplicate(true)
	dock["top"] = 1.0
	panel._text.text = JSON.stringify(dock)
	panel.apply_text()
	check.call(
		float(panel.document.object("dock")["top"]) == 1.0, "Apply changes the dock from its JSON"
	)
	check.call(panel.document.undo_stack.size() == 3, "three changes, three undo steps")
	panel.document.undo()
	check.call(float(panel.document.object("dock")["top"]) == .9, "undo puts the dock back")
	panel.document.redo()
	check.call(float(panel.document.object("dock")["top"]) == 1.0, "and redo raises it again")
	# A dock 1.0 up leaves its ramp (to .9) leading nowhere: put it back.
	panel.document.undo()
	panel.save()
	var reread := Source.read(map_id)
	check.call(
		(
			String(reread["objects"][2].get("_note", "")) == "the screen must keep this"
			and Source.find(reread, added) >= 0
		),
		"saved, it keeps the note and the new pickup"
	)
	panel.build()
	var level_text := FileAccess.get_file_as_string("%s/%s.json" % [Source.data_dir, map_id])
	var lv := (
		LevelData.from_dict(JSON.parse_string(level_text), main.art) if level_text != "" else null
	)
	check.call(lv != null and lv.geo != null, "Build writes a level that loads with its geometry")
	panel.queue_free()


## Hands woken under the loft, on the dock and in the yard all come to the
## player standing on the loft: round by the stairs, not stuck under it.
static func climbers(main, demo: Dictionary, check: Callable) -> void:
	var built := Compile.compile(demo)
	LevelData.preview["feedstore"] = built["level"]
	for who in ["stock_billy", "dock_billy", "yard_billy"]:
		var g: Game = main.make_game("feedstore")
		g.configure({})
		g.cheats.god = true
		g.spawn_grace = 0.0
		var p := g.player
		p.x = 12.5
		p.y = 5.0
		p.floor_z = 1.7
		p.eye = 2.65
		for d: LevelData.Door in g.world.doors:
			d.opened = true
			d.progress = 1.0
		var e: Enemy = null
		for i in g.enemies.size():
			if g.enemy_ids[i] == who:
				e = g.enemies[i]
			else:
				g.enemies[i].dormant = true
		e.wake(g, p.x, p.y)
		e.hunt_until = 1e9
		var reached := -1.0
		var idle := Game.Controls.new()
		for k in 60 * 40:
			g.tick(1.0 / 60.0, idle)
			p.health = 100
			if g.world.stand(e) > 1.6 and Vector2(e.x, e.y).distance_to(Vector2(p.x, p.y)) < 2.5:
				reached = k / 60.0
				break
		check.call(
			reached >= 0.0, "%s comes up to the player on the loft (%.1f s)" % [who, reached]
		)
	LevelData.preview.erase("feedstore")
