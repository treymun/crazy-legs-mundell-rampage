## tools/pack_assets.gd's last step: the bakes src/level_bakes.gd reads, so a
## chapter's first visit builds neither its nav graph nor its breakables'
## wreck pieces. Each level of data/ is made as a game makes it (Game.new,
## configure) with the bakes off: its graph as FlowField built it is written
## to bake_nav_<level>.bin, and every key its breakables cut (WreckCuts, each
## key's own pieces) to bake_cuts.bin, each under the key it holds while what
## it was made from is unchanged. A key only one chapter's levels cut (the
## chapter and its County Run map: Assets.stem_of) goes in that chapter's
## bake_cuts_<stem>.bin instead (one is written for every chapter, empty or
## not), which the browser build fetches with the chapter's pack. Needs the
## project imported (class names, the models' scenes): pack_assets.gd runs it
## then, or alone with `-- bake`.
##
## Loaded by path at run time (pack_assets.gd compiles before the project is
## imported, when the class names here do not resolve yet).
extends RefCounted


## Writes the bakes into `out`; [nav files, nav bytes, cut keys, cut bytes,
## seconds], or [] when something failed (said with push_error).
static func make(tree: SceneTree, out: String) -> Array:
	var started := Time.get_ticks_msec()
	var was_off := LevelBakes.off
	LevelBakes.off = true
	WreckCuts.clear()
	var navs: Dictionary = (LevelGeometry as Script).get("_navs")
	navs.clear()
	var assets := Assets.new()
	var hud := HUD.new(assets)
	var sound := Sound.new(assets)
	tree.root.add_child(sound)
	var options := SessionStore.settings("")
	var levels: Array = []
	for f: String in DirAccess.get_files_at("res://data"):
		if f.ends_with(".json") and f != "index.json":
			levels.append(f.get_basename())
	levels.sort()
	# key -> the stems of the levels that cut it ("" a level of no chapter's).
	var keys := {}
	var nav_files := 0
	var nav_bytes := 0
	var tiles := LevelBakes.tiles_md5(assets.tile_names)
	var code := LevelBakes.scripts_md5(LevelBakes.NAV_SCRIPTS)
	var ok := true
	for id: String in levels:
		var game := Game.new(assets, hud, sound, id)
		game.configure(options)
		var lv := game.level
		if lv == null:
			push_error("bake: level %s does not load" % id)
			ok = false
			continue
		if lv.geo != null:
			if lv.source_file == "" or game.flow.graph == null:
				push_error("bake: level %s has no graph read from its file" % id)
				ok = false
				continue
			var stamp := LevelBakes.nav_stamp(FileAccess.get_md5(lv.source_file), tiles, code)
			var data := LevelBakes.pack_file(
				LevelBakes.NAV_MAGIC,
				stamp,
				LevelBakes.pack_value(LevelBakes.nav_row(game.flow.graph))
			)
			_write(out.path_join(LevelBakes.NAV_FILE % lv.id), data)
			nav_files += 1
			nav_bytes += data.size()
		for key: String in level_keys(game):
			var stems: Dictionary = keys.get(key, {})
			stems[Assets.stem_of(id)] = true
			keys[key] = stems
		game.dispose()
	navs.clear()
	# Each key's file: the chapters' when only chapters' levels cut it (in each
	# of theirs: a browser has the chapter's pack before its levels start).
	var files := {LevelBakes.CUTS_FILE: []}
	for stem: Variant in Assets.CHAPTER_ART.values():
		files[LevelBakes.CHAPTER_CUTS % str(stem).trim_prefix("art_").trim_suffix(".bin")] = []
	var homes := {}
	for key: String in keys:
		var stems: Dictionary = keys[key]
		var names: Array = [LevelBakes.CUTS_FILE]
		if not stems.has(""):
			names = []
			for stem: String in stems:
				names.append(LevelBakes.CHAPTER_CUTS % stem)
			homes[key] = names
		for name: String in names:
			var list: Array = files[name]
			list.append(key)
	var cut_bytes := 0
	for name: String in files:
		var cuts := _cuts(assets, files[name], homes if name == LevelBakes.CUTS_FILE else {})
		_write(out.path_join(name), cuts)
		cut_bytes += cuts.size()
	WreckCuts.clear()
	sound.queue_free()
	LevelBakes.off = was_off
	LevelBakes.forget()
	if not ok:
		return []
	return [
		nav_files, nav_bytes, keys.size(), cut_bytes, (Time.get_ticks_msec() - started) / 1000.0
	]


## The wreck cut keys of a game's breakables (wreckage.gd _source: what
## WreckCuts.prepare lists as the level starts), sorted.
static func level_keys(game: Game) -> Array:
	var out := {}
	var wreck: Object = game.features.get("wreckage")
	var pieces: Object = game.features.get("breakables")
	if wreck == null or pieces == null or not wreck.get("on"):
		return []
	for p: Object in pieces.get("pieces"):
		var src: Dictionary = wreck.call("_source", p)
		if not src.is_empty():
			out[str(src["key"])] = true
	var keys := out.keys()
	keys.sort()
	return keys


## A cuts file of `keys`, each cut here (bakes off: as a level's first frames
## cut it) with its stamp, its fracture origin's box and its model's size;
## `homes` the keys kept in chapters' files, each with theirs (bake_cuts.bin
## names them).
static func _cuts(assets: Assets, keys: Array, homes: Dictionary) -> PackedByteArray:
	keys.sort()
	var index := {}
	var blob := PackedByteArray()
	var boxes: Dictionary = (WreckCuts as Script).get("_boxes")
	for key: String in keys:
		var k := WreckCuts.named(key)
		var parts := WreckCuts.parts(assets, key)
		var rows: Array = []
		for p: WreckCuts.Part in parts:
			rows.append(LevelBakes.part_row(p))
		var source := ""
		var tris := -1
		if k.source.begins_with("m:"):
			var name := k.source.substr(2)
			source = LevelBakes.model_md5(WreckCuts.PROPS.path_join(name + ".glb"))
			tris = WreckCuts._model(name).size() / 3
		elif k.source.begins_with("p:"):
			var pic := WreckCuts._picture(assets, k.source.substr(2))
			source = LevelBakes.bytes_md5(var_to_bytes(pic))
		var payload := LevelBakes.pack_value(rows)
		var box: Variant = boxes.get(k.source + "|" + k.recipe)
		index[key] = [blob.size(), payload.size(), LevelBakes.cut_stamp(source), tris, box]
		blob.append_array(payload)
	return LevelBakes.pack_file(LevelBakes.CUTS_MAGIC, {"index": index, "homes": homes}, blob)


static func _write(path: String, data: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(data)
	file.close()
