## Pictures of the RAMPAGE meter in a real window (pass 15:
## features/rampage.gd, HUD.rampage_meter, src/rampage_looks.gd): the meter
## filling under the health, the RAMPAGE as it flares up, a beat into it
## (the edge burning, RAMPAGE on the health box) and guttering out at its
## end; the meter and the burn again in ASPECT WIDE and with the touch
## buttons up. Each is <name>.png in out=<dir>.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/rampage_frames.gd -- out=<dir> [only=<name,...>]
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

const STEP := 1.0 / 60.0

var main
var out := ""
var only: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text.begins_with("out="):
			out = text.substr(4)
		elif text.begins_with("only="):
			only = Array(text.substr(5).split(","))
	if out == "":
		push_error("out=<dir> is needed")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.touring = true
	Effects.enabled = true
	if _want("plain"):
		await _moments("plain")
	if _want("touch"):
		main.touch.active = true
		main.touch.set_showing(true)
		await _moments("touch", true)
		main.touch.active = false
		main.touch.set_showing(false)
	if _want("wide"):
		var size: Vector2i = root.size
		main.options["aspect"] = PictureShape.ASPECT_WIDE
		root.size = Vector2i(1424, 800)
		await _moments("wide")
		main.options["aspect"] = 0
		root.size = size
	print("rampage frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _want(name: String) -> bool:
	if only.is_empty():
		return true
	for o: String in only:
		if name.begins_with(o):
			return true
	return false


func _snap(name: String) -> void:
	if main.game != null:
		main.game.message_until = 0.0
		main.game.barks.until = 0.0
	main.render()
	await RenderingServer.frame_post_draw
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


func _level() -> Game:
	main.start("hickston")
	var g: Game = main.game
	g.cheats.god = true
	g.lessons = false
	g.barks.enabled = false
	for e: Enemy in g.enemies:
		e.dormant = true
	g.message_until = 0.0
	g.district_until = 0.0
	return g


func _ticks(g: Game, seconds: float) -> void:
	for i in maxi(1, int(seconds * 60.0)):
		g.tick(STEP, Game.Controls.new())


## The meter part full, then a RAMPAGE: as it flares, a beat in, and at its end.
func _moments(name: String, touch := false) -> void:
	var g := _level()
	if touch:
		main.touch.layout(main.viewport_rect(), true)
	_ticks(g, .2)
	var r := Rampage.of(g)
	if r == null:
		push_warning("no RAMPAGE here")
		return
	r._grow(0)
	r.meters[0] = .62
	r.holds[0] = g.clock + 99.0
	await _snap(name + "_0_filling")
	r.meters[0] = 1.0
	r.until[0] = g.clock + Rampage.LENGTH
	r.began[0] = g.clock
	_ticks(g, .2)
	await _snap(name + "_1_flare")
	_ticks(g, 1.5)
	await _snap(name + "_2_burning")
	if name == "plain":
		_ticks(g, float(r.until[0]) - g.clock - .9)
		# A tick into the guttering fire's lit part.
		while int(g.clock * 10.0) % 3 == 0:
			_ticks(g, STEP)
		await _snap(name + "_3_guttering")
