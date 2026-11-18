## The hitches the 3D view takes out of play (WorldView3D._warm_models and
## warm_up; measured in a window by tools/hitch_bench.gd), headless:
## - a level's first frames draw every hidden piece once (the twister, the
##   storm wall, the rain, the seat views made for the level's vehicles), a
##   speck in front of the eye, and the frame after puts each back as it was;
## - the props the level stands, the county events' hogs and raiders and the
##   vehicles' seat views are made at the level's first frame, not when first
##   seen (one hog and one raider made and kept hidden, drawn as specks with
##   the rest: pass 10);
## - every speck kind the game throws by name (game.burst) has its picture
##   (fx_<kind>): a missing one drew nothing and its warning cost 19 ms.
##
##   Godot --headless --path <project> --script res://tools/warm_check.gd
##
## Prints WARM CHECK OK, or what failed.
extends SceneTree

var failures: Array = []
var main


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.touring = true
	main.options["events"] = 2
	main.start("hickston")
	var g: Game = main.game
	main.state = "play"
	# Headless the game makes no 3D view of its own: one by hand.
	var view := WorldView3D.new(g.art)
	main.add_child(view)
	var canvas := Canvas.new()
	g.draw(canvas, 0, true)
	view.frame(g)
	var hidden: Array[Node3D] = []
	for name: String in ["_twister", "_storm_walls", "_rain"]:
		var nodes: Array = view.get(name)
		for node: Node3D in nodes:
			hidden.append(node)
	hidden.append_array(view.cab.hidden_roots())
	hidden.append_array(view.wrecks.warm_roots())
	var kept: Dictionary = view.actors.get("_warmed")
	for model: Node3D in kept.values():
		hidden.append(model)
	_check(not view.cab.hidden_roots().is_empty(), "hickston's mower seat view made at once")
	_check(
		kept.has("hog") and kept.size() == 2,
		"a hog and a raider made hidden at once, for the first of each (pass 10)"
	)
	var warmed: Dictionary = view.get("_warmed")
	# Each hidden piece is out (one already showing, the rain in a shower, is
	# drawn anyway and left as it is).
	var out := 0
	var shown := {}
	for node: Node3D in hidden:
		if node.visible and not warmed.has(node):
			shown[node] = true
		if node.visible:
			out += 1
	_check(
		out == hidden.size() and view.warming(),
		"the first frame draws every hidden piece (%d of %d)" % [out, hidden.size()]
	)
	var specks := 0
	for node: Node3D in warmed:
		var away := node.global_position.distance_to(view.camera.global_position)
		# Small and well off: under a pixel (it showed at a thousandth of its
		# size just past the near plane).
		if node.global_transform.basis.get_scale().x <= WorldView3D.SPECK * 1.01 and away > 20.0:
			specks += 1
	_check(
		specks == warmed.size() and specks + shown.size() == hidden.size(),
		"each a speck well off (%d of %d)" % [specks, warmed.size()]
	)
	var put_out := warmed.keys()
	for i in WorldView3D.WARM_FRAMES + 1:
		g.tick(1.0 / 60.0, Game.Controls.new())
		g.draw(canvas, 0, true)
		view.frame(g)
	var back := 0
	for node: Node3D in put_out:
		if not node.visible:
			back += 1
	_check(
		back == put_out.size() and not view.warming() and warmed.is_empty(),
		"then each is put back hidden (%d of %d)" % [back, put_out.size()]
	)
	var props: Dictionary = view.props.get("_materials")
	_check(props.size() >= 20, "the props hickston stands are made at once (%d)" % props.size())
	var made: Dictionary = view.actors.models.get("_materials")
	var loaded: Dictionary = view.actors.models.get("_scenes")
	_check(
		made.has("hog") and loaded.get("hog") != null and made.has(EventRaid.squad_kind()),
		"the hogs' and the raiders' models are ready before an event"
	)
	_bursts(g)
	_done()


## Every literal kind of game.burst() in the game's scripts has its picture.
func _bursts(g: Game) -> void:
	var call := RegEx.create_from_string('burst\\([^()]*?,[^()]*?,[^()]*?,\\s*"([a-z_]+)"')
	var kinds := {}
	var files := PackedStringArray()
	_gather("res://src", files)
	for path in files:
		for found in call.search_all(FileAccess.get_file_as_string(path)):
			kinds[found.get_string(1)] = path.get_file()
	var missing := PackedStringArray()
	for kind: String in kinds:
		if not g.art.has_art("fx_" + kind):
			missing.append("%s (%s)" % [kind, kinds[kind]])
	_check(
		kinds.size() >= 5 and missing.is_empty(),
		"every speck kind thrown has its picture (%d kinds) %s" % [kinds.size(), ", ".join(missing)]
	)


func _gather(folder: String, into: PackedStringArray) -> void:
	for file in DirAccess.get_files_at(folder):
		if file.get_extension() == "gd":
			into.append(folder.path_join(file))
	for sub in DirAccess.get_directories_at(folder):
		_gather(folder.path_join(sub), into)


func _done() -> void:
	print("")
	print("WARM CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)
