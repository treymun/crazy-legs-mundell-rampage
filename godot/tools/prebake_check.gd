## The bakes a chapter's first visit reads (src/level_bakes.gd, made at pack
## time by tools/level_bake.gd) against what is built without them, level by
## level:
##
## - every level of data/ with geometry (the chapters, the hub, the range,
##   County Run's maps, the boss arenas in them) has its nav graph baked, a
##   game made on it reads it, and it is the graph a game built with the bakes
##   off: node for node, edge for edge, in the same order (`over` and `links`
##   in their order too);
## - every key a level's breakables cut (the 5v5/2v2 maps have none) is baked,
##   and read back (parts() and a level's pump() alike) it is the cut piece
##   for piece and float for float (box, turn, faces, texture places, cut
##   faces, shown corners, material, form), with the same fracture origin
##   and variant count;
## - a stale bake is not read and the level builds as before: a copy of the
##   bakes with the level file's MD5, the tile list's, the format, the
##   scripts' or a source's (a model's files, a picture's pixels) changed, or
##   with a file missing; a level a tool hands in (LevelData.preview) and a
##   player's map (the MAP SHED's examples) are never baked.
##
##   godot --headless --path godot --script res://tools/prebake_check.gd [-- levels=a,b]
##
## A bake missing or stale here means the packs are older than the levels or
## the scripts: run tools/pack_assets.gd -- bake. Prints PREBAKE CHECK OK.
extends SceneTree

const LevelBake := preload("res://tools/level_bake.gd")

var failures: Array[String] = []
var assets: Assets
var hud: HUD
var sound: Sound
var options: Dictionary


func _init() -> void:
	_run.call_deferred()


func _fail(text: String) -> void:
	failures.append(text)
	print("FAIL ", text)


func _levels() -> Array:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("levels="):
			return Array(arg.substr(7).split(",", false))
	var out: Array = []
	for f: String in DirAccess.get_files_at("res://data"):
		if f.ends_with(".json") and f != "index.json":
			out.append(f.get_basename())
	out.sort()
	return out


func _navs() -> Dictionary:
	return (LevelGeometry as Script).get("_navs")


## A game on a level with the kept graphs forgotten (a first visit).
func _game(id: String, bakes: bool) -> Game:
	_navs().clear()
	LevelBakes.off = not bakes
	var game := Game.new(assets, hud, sound, id)
	game.configure(options)
	LevelBakes.off = false
	return game


func _run() -> void:
	assets = Assets.new()
	hud = HUD.new(assets)
	sound = Sound.new(assets)
	root.add_child(sound)
	options = SessionStore.settings("")
	var levels := _levels()
	var keys := {}
	var graphs := 0
	for id: String in levels:
		var read := LevelBakes.navs_read
		var game := _game(id, true)
		var baked := LevelBakes.navs_read - read
		var plain := _game(id, false)
		if game.level.geo != null:
			graphs += 1
			if baked != 1:
				_fail("%s: its nav graph was not read from a bake (missing or stale)" % id)
			_same_graph(id, game.flow.graph, plain.flow.graph)
		elif baked != 0:
			_fail("%s: a level without geometry read a nav bake" % id)
		for key: String in LevelBake.level_keys(game):
			keys[key] = true
		game.dispose()
		plain.dispose()
	print("nav graphs: %d levels read from their bakes, the same as built" % graphs)
	_check_cuts(keys.keys())
	_check_stale()
	_check_unbaked()
	_navs().clear()
	WreckCuts.clear()
	if failures.is_empty():
		print("PREBAKE CHECK OK")
		quit(0)
	else:
		print("PREBAKE CHECK: %d failed" % failures.size())
		quit(1)


func _same_graph(id: String, a: LevelGeometry.NavGraph, b: LevelGeometry.NavGraph) -> void:
	if a == null or b == null or b.count == 0:
		_fail("%s: no nav graph" % id)
		return
	for field: String in [
		"count", "cells", "cell", "z", "first", "edges", "dfirst", "dedges", "over", "links"
	]:
		if a.get(field) != b.get(field):
			_fail("%s: the baked graph's %s differs from the one built" % [id, field])
	# The same order too (node_at walks a cell's decks in it).
	if a.over.keys() != b.over.keys() or a.over.values() != b.over.values():
		_fail("%s: the baked graph's decks are in another order" % id)
	if a.links.keys() != b.links.keys() or a.links.values() != b.links.values():
		_fail("%s: the baked graph's ladder links are in another order" % id)
	if a.ladder_ends != b.ladder_ends:
		_fail("%s: the baked graph's ladder ends differ" % id)


## Each key read from the bake (parts() and pump()) against the key cut.
func _check_cuts(keys: Array) -> void:
	keys.sort()
	var pieces := 0
	for key: String in keys:
		WreckCuts.clear()
		LevelBakes.off = true
		var cut := WreckCuts.parts(assets, key)
		var cut_origin := WreckCuts.origin(key)
		var cut_count := WreckCuts.variants(key)
		var cut_round := WreckCuts.round_about(key)
		WreckCuts.clear()
		LevelBakes.off = false
		var read := LevelBakes.cuts_read
		var count := WreckCuts.variants(key)
		var baked := WreckCuts.parts(assets, key)
		if LevelBakes.cuts_read != read + 1:
			_fail("%s: not read from the bake (missing or stale)" % key)
		if not _same_parts(baked, cut):
			_fail("%s: the baked pieces differ from the cut" % key)
		if WreckCuts.origin(key) != cut_origin or count != cut_count:
			_fail("%s: the baked fracture origin or variant count differs" % key)
		if WreckCuts.round_about(key) != cut_round:
			_fail("%s: the baked key turns differently" % key)
		pieces += cut.size()
		# A level's first frames: listed, then pumped (a worker's cut, or the bake).
		if OS.has_feature("threads"):
			WreckCuts.clear()
			WreckCuts.prepare([key])
			var waited := 0
			while not WreckCuts.idle() and waited < 20000:
				WreckCuts.pump(assets)
				OS.delay_usec(200)
				waited += 1
			if not WreckCuts.has(key) or not _same_parts(WreckCuts.parts(assets, key), cut):
				_fail("%s: pumped from the bake, the pieces differ from the cut" % key)
	print(
		(
			"wreck cuts: %d keys (%d pieces) read from the bake, the same as cut"
			% [keys.size(), pieces]
		)
	)


func _same_parts(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		var p: WreckCuts.Part = a[i]
		var q: WreckCuts.Part = b[i]
		if (
			p.centre != q.centre
			or p.basis != q.basis
			or p.half != q.half
			or p.verts != q.verts
			or p.normals != q.normals
			or p.uvs != q.uvs
			or p.colors != q.colors
			or p.uv2s != q.uv2s
			or p.material != q.material
			or p.form != q.form
			or p.shown != q.shown
			or p.shown_n != q.shown_n
		):
			return false
	return true


## A scratch copy of the bakes, each doctored one way: none of it is read.
func _check_stale() -> void:
	if LevelBakes.scripts_md5(LevelBakes.NAV_SCRIPTS) == "":
		_fail("the scripts cannot be read here: their stamp is not checked")
	var level := "hickston"
	var scratch := OS.get_cache_dir().path_join("clmr_prebake_check")
	DirAccess.make_dir_recursive_absolute(scratch)
	var nav_name := LevelBakes.NAV_FILE % level
	var nav_data := FileAccess.get_file_as_bytes(LevelBakes.DIR + nav_name)
	var cut_data := FileAccess.get_file_as_bytes(LevelBakes.DIR + LevelBakes.CUTS_FILE)
	if nav_data.is_empty() or cut_data.is_empty():
		_fail("no bakes to doctor (run tools/pack_assets.gd -- bake)")
		return
	var fresh := _game(level, false)
	var built := fresh.flow.graph
	var wreck_key := ""
	var sign_key := ""
	for key: String in LevelBake.level_keys(fresh):
		if key.begins_with("m:") and wreck_key == "":
			wreck_key = key
		if key.begins_with("p:") and sign_key == "":
			sign_key = key
	fresh.dispose()
	LevelBakes.dir = scratch + "/"
	# The copy as it is: read (the doctoring below is what stops it).
	_put(scratch, nav_name, nav_data, cut_data)
	_expect_nav(level, built, true, "an undoctored copy")
	for field: String in ["level", "tiles", "format", "code"]:
		_put(scratch, nav_name, _doctor(nav_data, LevelBakes.NAV_MAGIC, "", field), cut_data)
		_expect_nav(level, built, false, "its %s changed" % field)
	_put(scratch, "", PackedByteArray(), cut_data)
	_expect_nav(level, built, false, "its file missing")
	for key: String in [wreck_key, sign_key]:
		if key == "":
			_fail(
				"%s has no %s key to doctor" % [level, "model" if key == wreck_key else "picture"]
			)
			continue
		WreckCuts.clear()
		LevelBakes.off = true
		var cut := WreckCuts.parts(assets, key)
		LevelBakes.off = false
		_put(scratch, nav_name, nav_data, cut_data)
		_expect_cut(key, cut, true, "an undoctored copy")
		for field: String in ["source", "format", "code"]:
			_put(scratch, nav_name, nav_data, _doctor(cut_data, LevelBakes.CUTS_MAGIC, key, field))
			_expect_cut(key, cut, false, "its %s changed" % field)
		_put(scratch, nav_name, nav_data, PackedByteArray())
		_expect_cut(key, cut, false, "the cuts file missing")
	# A key kept in a chapter's file: read with it, cut without it (a browser
	# before that chapter's pack is in).
	var homes: Dictionary = LevelBakes.read_header(cut_data, LevelBakes.CUTS_MAGIC)[0]["homes"]
	if homes.is_empty():
		_fail("no key is kept in a chapter's cuts file")
	else:
		var key: String = homes.keys()[0]
		var names: Array = homes[key]
		var name: String = names[0]
		var chapter := FileAccess.get_file_as_bytes(LevelBakes.DIR + name)
		WreckCuts.clear()
		LevelBakes.off = true
		var cut := WreckCuts.parts(assets, key)
		LevelBakes.off = false
		_put(scratch, nav_name, nav_data, cut_data)
		_write(scratch.path_join(name), chapter)
		_expect_cut(key, cut, true, "its chapter's file there")
		_put(scratch, nav_name, nav_data, cut_data)
		_expect_cut(key, cut, false, "its chapter's file not there yet")
	LevelBakes.dir = LevelBakes.DIR
	LevelBakes.forget()
	print("stale bakes: a changed level, tile list, format, script or source builds as before")


## Writes the scratch copy (a name "" or no bytes: that file left out).
func _put(scratch: String, nav_name: String, nav: PackedByteArray, cuts: PackedByteArray) -> void:
	for f: String in DirAccess.get_files_at(scratch):
		DirAccess.remove_absolute(scratch.path_join(f))
	if nav_name != "" and not nav.is_empty():
		_write(scratch.path_join(nav_name), nav)
	if not cuts.is_empty():
		_write(scratch.path_join(LevelBakes.CUTS_FILE), cuts)
	LevelBakes.forget()


func _write(path: String, data: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(data)
	file.close()


## A bake with one field of its header (`key` "": the file's own; else that
## cut key's stamp) changed.
func _doctor(data: PackedByteArray, magic: String, key: String, field: String) -> PackedByteArray:
	var found := LevelBakes.read_header(data, magic)
	var head: Dictionary = found[0]
	var rest := data.slice(found[1])
	if key == "":
		head[field] = _changed(head[field])
	else:
		var index: Dictionary = head["index"].duplicate()
		var entry: Array = index[key]
		var stamp: Dictionary = entry[2].duplicate()
		stamp[field] = _changed(stamp[field])
		entry = entry.duplicate()
		entry[2] = stamp
		index[key] = entry
		head["index"] = index
	return LevelBakes.pack_file(magic, head, rest)


func _changed(value: Variant) -> Variant:
	if value is int:
		return int(value) + 1
	return "0" + str(value).substr(1) if str(value).begins_with("f") else "f" + str(value).substr(1)


func _expect_nav(level: String, built: LevelGeometry.NavGraph, read: bool, how: String) -> void:
	var before := LevelBakes.navs_read
	var game := _game(level, true)
	var was_read := LevelBakes.navs_read > before
	if was_read != read:
		_fail("%s's nav bake, %s: %s" % [level, how, "read" if was_read else "not read"])
	_same_graph("%s (%s)" % [level, how], game.flow.graph, built)
	game.dispose()


func _expect_cut(key: String, cut: Array, read: bool, how: String) -> void:
	WreckCuts.clear()
	var before := LevelBakes.cuts_read
	var got := WreckCuts.parts(assets, key)
	var was_read := LevelBakes.cuts_read > before
	if was_read != read:
		_fail("%s's cut bake, %s: %s" % [key, how, "read" if was_read else "not read"])
	if not _same_parts(got, cut):
		_fail("%s (%s): the pieces differ from the cut" % [key, how])


## A level handed in by a tool, and a player's map: built, never read.
func _check_unbaked() -> void:
	var raw := FileAccess.get_file_as_string("res://data/hickston.json")
	var given: Variant = JSON.parse_string(raw)
	LevelData.preview["hickston"] = given
	var before := LevelBakes.navs_read
	var game := _game("hickston", true)
	if LevelBakes.navs_read != before:
		_fail("a level handed in (LevelData.preview) read the chapter's nav bake")
	if game.level.geo == null or game.flow.graph == null or game.flow.graph.count == 0:
		_fail("the level handed in built no nav graph")
	game.dispose()
	LevelData.preview.erase("hickston")
	var maps := 0
	for f: String in DirAccess.get_files_at("res://data/user_maps"):
		if not f.ends_with(".json"):
			continue
		var entry := UserMaps.read("res://data/user_maps".path_join(f), "example")
		var map: Variant = entry.get("map")
		if not (map is Dictionary):
			_fail("example map %s does not read" % f)
			continue
		var id := UserMaps.register(map)
		before = LevelBakes.navs_read
		var custom := _game(id, true)
		if LevelBakes.navs_read != before:
			_fail("the player's map %s read a nav bake" % f)
		custom.dispose()
		UserMaps.forget(map)
		maps += 1
	print("never baked: a level handed in and %d player's maps built as before" % maps)
