## What the faster level load hands play is what the slow way gave, level by
## level:
##
## - the nav graph (LevelGeometry._build_nav) node for node and edge for edge,
##   in the same order, against the build it replaced (tools/load_reference.gd);
## - the level read (LevelData.load_level): its grids and walls number for
##   number, its plane bounds box for box, against the reads they replaced;
## - the wreck pieces cut on a worker while the level's first frames run
##   (WreckCuts.prepare) against the same keys cut at once on this thread.
##
##   godot --headless --path godot --script res://tools/load_check.gd [-- levels=a,b]
##
## Prints LOAD CHECK OK.
extends SceneTree

const Reference := preload("res://tools/load_reference.gd")

var failures: Array[String] = []


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


func _run() -> void:
	var assets := Assets.new()
	var levels := _levels()
	var navs := 0
	var reads := 0
	for id: String in levels:
		var lv := LevelData.load_level(id, assets)
		if lv == null:
			_fail("%s: does not load" % id)
			continue
		_check_read(id, lv, assets)
		reads += 1
		if lv.geo != null:
			_check_nav(id, lv)
			navs += 1
	print("level reads: %d levels the same as the reference read" % reads)
	print("nav graphs: %d levels the same as the reference build" % navs)
	_check_cuts(assets, levels)
	if failures.is_empty():
		print("LOAD CHECK OK")
		quit(0)
	else:
		print("LOAD CHECK: %d failed" % failures.size())
		quit(1)


func _check_nav(id: String, lv: LevelData) -> void:
	var t0 := Time.get_ticks_usec()
	var fast: LevelGeometry.NavGraph = lv.geo._build_nav(lv)
	var t1 := Time.get_ticks_usec()
	var slow: LevelGeometry.NavGraph = Reference.nav(lv.geo, lv)
	var t2 := Time.get_ticks_usec()
	if fast == null or slow == null or fast.count == 0:
		_fail("%s: no nav graph built" % id)
		return
	for field: String in [
		"count", "cells", "cell", "z", "first", "edges", "dfirst", "dedges", "over", "links"
	]:
		if fast.get(field) != slow.get(field):
			_fail("%s: nav graph's %s differs from the reference build" % [id, field])
	if fast.ladder_ends != slow.ladder_ends:
		_fail("%s: nav graph's ladder_ends differ from the reference build" % id)
	print(
		(
			"  %-16s nav %5d nodes %6d edges %6d diagonals  %6.1f ms (reference %6.1f)"
			% [
				id,
				fast.count,
				fast.edges.size(),
				fast.dedges.size(),
				(t1 - t0) / 1000.0,
				(t2 - t1) / 1000.0
			]
		)
	)


## The wreck pieces of every breakable the levels have: cut by prepare() and
## pump() (a model's on a worker) and cut at once here, piece for piece.
func _check_cuts(assets: Assets, levels: Array) -> void:
	if not OS.has_feature("threads"):
		_fail("this build has no threads: the worker's cuts are not checked")
		return
	var hud := HUD.new(assets)
	var sound := Sound.new(assets)
	root.add_child(sound)
	var keys := {}
	for id: String in levels:
		if FileAccess.get_file_as_string("res://data/%s.json" % id).is_empty():
			continue
		var game := Game.new(assets, hud, sound, id)
		var wreck: Object = game.features.get("wreckage")
		var pieces: Object = game.features.get("breakables")
		if wreck == null or pieces == null or not bool(wreck.get("on")):
			continue
		for p: Object in pieces.get("pieces"):
			var src: Dictionary = wreck.call("_source", p)
			if not src.is_empty():
				keys[str(src["key"])] = true
		# The level's own pump, as its first frames run it.
		var waited := 0
		while not WreckCuts.idle() and waited < 20000:
			WreckCuts.pump(assets)
			OS.delay_usec(500)
			waited += 1
		if not WreckCuts.idle():
			_fail("%s: the wreck cuts never finished" % id)
	var by_worker := {}
	for key: String in keys:
		by_worker[key] = WreckCuts.parts(assets, key)
	WreckCuts.clear()
	var models := 0
	var pieces := 0
	for key: String in keys:
		var here: Array = WreckCuts.parts(assets, key)
		models += 1 if key.begins_with("m:") else 0
		pieces += here.size()
		if not _same_parts(here, by_worker[key]):
			_fail("wreck cut %s differs from the worker's" % key)
	if models == 0 or pieces == 0:
		_fail("no wreck pieces were cut")
	print(
		(
			"wreck cuts: %d keys (%d models, %d pieces) the same cut on a worker and here"
			% [keys.size(), models, pieces]
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
		):
			return false
	return true


## The level read: the grids and walls as the slow read gave them, and the
## plane bounds made both ways from the same level.
func _check_read(id: String, lv: LevelData, assets: Assets) -> void:
	if Reference.ints([1.0, "2"]) != PackedInt32Array([1, 2]):
		_fail("the reference read does not run")
		return
	var j: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % id))
	for pair: Array in [
		["solid", "solid"],
		["floor", "floor_tile"],
		["ceiling", "ceiling_tile"],
		["area", "area"],
	]:
		if lv.get(pair[1]) != Reference.ints(j[pair[0]]):
			_fail("%s: %s read differs" % [id, pair[1]])
	# (The geometry block adds heights and walls after the file's: the file's
	# come first.)
	for name: String in [
		"ground", "roof", "wall_height", "light", "ground_heights", "roof_heights", "spawn"
	]:
		var want := Reference.floats(j[name])
		var have: PackedFloat32Array = lv.get(name)
		if have.slice(0, want.size()) != want:
			_fail("%s: %s read differs" % [id, name])
	if not j.get("hub_split", false):
		var walls := PackedFloat32Array()
		for row: Array in j["walls"]:
			walls.append_array(Reference.floats(row.slice(0, LevelData.WALL_STRIDE)))
		var ref := LevelData.new()
		ref.tile_index = assets.tile_index
		ref.walls = walls
		ref.wall_count = (j["walls"] as Array).size()
		Reference.merge_runs(ref)
		if lv.walls.slice(0, ref.walls.size()) != ref.walls:
			_fail("%s: walls read differ" % id)
	var fast := _bounds_copy(lv)
	var slow := _bounds_copy(lv)
	fast._build_plane_bounds()
	Reference.plane_bounds(slow)
	if slow.floor_boxes.is_empty():
		_fail("%s: the reference plane bounds made nothing" % id)
	for name: String in ["floor_bounds", "roof_bounds", "floor_boxes", "roof_boxes"]:
		if fast.get(name) != slow.get(name):
			_fail("%s: %s differ from the reference" % [id, name])


## A level holding only what the plane bounds are made from.
func _bounds_copy(lv: LevelData) -> LevelData:
	var out := LevelData.new()
	out.width = lv.width
	out.height = lv.height
	out.ground = lv.ground
	out.roof = lv.roof
	out.ground_heights = lv.ground_heights
	out.roof_heights = lv.roof_heights
	out.caps = lv.caps
	out.roof_caps = lv.roof_caps
	return out
