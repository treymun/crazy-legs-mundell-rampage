## The 3D view's frame stays cheap (pass 10, docs/dev/view3d.md "Keeping the
## frame cheap"): what made it slow before cannot come back unnoticed.
##
##   godot --headless --path godot --script res://tools/view_perf_check.gd
##
## - The frame's numbers are global uniforms: every name WorldView3D.GLOBALS
##   routes is in project.godot [shader_globals] with the type the shaders
##   declare, no view3d shader declares one as a material's own uniform, and
##   none keeps a uniform array (the frame's lists are view_data's rows); a
##   frame hands none of them to a material.
## - Turning round LAPS times at Hickston's spawn with its hands awake, the
##   later turns make no prop and no model again (they are parked out of view and
##   shown again), and no living body or prop past where its model shows is
##   given one; the shader instance buffer is never over its room.
## - The view's frame() on the later turns (headless, no drawing: the
##   GDScript side alone; its lower quartile) stays under FRAME_RATIO times
##   a yardstick of plain GDScript work timed beside it, so a slower machine
##   is held to the same share: 0.4 to 1.1 of it here (2026-11-18, the PC
##   busy or not), v3.7.0
##   0.8 to 0.9 (its median, with a prop or model made every few frames,
##   1.9). The steady frame growing to two or three times fails; the props and
##   models made again are held above.
##
## Prints VIEW PERF CHECK OK.
extends SceneTree

const FRAME_RATIO := 1.5
const STEPS := 42
## The first lap stands the props and models; the rest are timed.
const LAPS := 4

var main
var failed := false


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	failed = failed or not ok


func _run() -> void:
	_globals()
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.touring = true
	await _turns()
	print("VIEW PERF CHECK FAILED" if failed else "VIEW PERF CHECK OK")
	main.queue_free()
	await process_frame
	quit(1 if failed else 0)


## The shaders' global uniforms against project.godot and the view's list.
func _globals() -> void:
	var declared := {}
	var own_uniforms: Array[String] = []
	var arrays: Array[String] = []
	var global_re := RegEx.create_from_string("(?m)^global uniform (\\w+) (\\w+);")
	var plain_re := RegEx.create_from_string("(?m)^uniform (\\w+) (\\w+)")
	var array_re := RegEx.create_from_string("(?m)^uniform \\w+ (\\w+)\\s*\\[")
	var instance_re := RegEx.create_from_string("(?m)^\\s*instance\\s+uniform\\s+\\w+\\s+(\\w+)")
	var instanced: Array[String] = []
	var folder := "res://src/view3d/"
	for file: String in DirAccess.get_files_at(folder):
		if not (file.ends_with(".gdshader") or file.ends_with(".gdshaderinc")):
			continue
		var code := FileAccess.get_file_as_string(folder + file)
		for m in global_re.search_all(code):
			declared[m.get_string(2)] = m.get_string(1)
		for m in plain_re.search_all(code):
			if WorldView3D.GLOBALS.has(m.get_string(2)):
				own_uniforms.append("%s %s" % [file, m.get_string(2)])
		for m in array_re.search_all(code):
			arrays.append("%s %s" % [file, m.get_string(1)])
		for m in instance_re.search_all(code):
			instanced.append("%s %s" % [file, m.get_string(1)])
	var missing: Array[String] = []
	for name: String in declared:
		var key := "shader_globals/" + name
		if not ProjectSettings.has_setting(key) or not WorldView3D.GLOBALS.has(name):
			missing.append(name)
			continue
		var setting: Dictionary = ProjectSettings.get_setting(key)
		if str(setting.get("type", "")) != declared[name]:
			missing.append("%s (%s)" % [name, declared[name]])
	for name: String in WorldView3D.GLOBALS:
		if not declared.has(name):
			missing.append(name + " (no shader declares it)")
	_check(
		missing.is_empty() and declared.size() == WorldView3D.GLOBALS.size(),
		(
			"%d global uniforms, each in project.godot and the view's list %s"
			% [declared.size(), missing]
		)
	)
	_check(own_uniforms.is_empty(), "none of them a material's own uniform %s" % [own_uniforms])
	_check(
		arrays.is_empty(), "no uniform arrays: the frame's lists are view_data's rows %s" % [arrays]
	)
	_check(
		instanced.is_empty(),
		"no instance uniforms: a part's own numbers are its own material's %s" % [instanced]
	)


## Two turns round at Hickston's spawn: the second makes nothing again.
func _turns() -> void:
	main.start("hickston")
	var g: Game = main.game
	main.state = "play"
	g.cheats.god = true
	for e: Enemy in g.enemies:
		e.dormant = false
	var view := WorldView3D.new(g.art)
	main.add_child(view)
	var canvas := Canvas.new()
	var held := Game.Controls.new()
	var p := g.player
	var start := p.angle
	var times := PackedFloat64Array()
	var props_made := 0
	var models_made := 0
	var over := 0
	var beyond := 0
	for lap in LAPS:
		if lap == 1:
			props_made = view.props.made_total
			models_made = view.actors.made_total
		for i in STEPS:
			p.angle = start + TAU * i / STEPS
			g.tick(1.0 / 60.0, held)
			g.draw(canvas, 0, true)
			var t0 := Time.get_ticks_usec()
			view.frame(g)
			if lap >= 1:
				times.append((Time.get_ticks_usec() - t0) / 1000.0)
			await process_frame
			var parts := WorldView3D.instance_uniform_parts(view)
			if parts > WorldView3D.INSTANCE_ROOM_SMALL - WorldView3D.INSTANCE_MARGIN:
				over += 1
			beyond += _beyond(view, Vector2(p.x, p.y))
		if lap == 0:
			_check(
				view.props.made_total > 10 and view.actors.made_total > 0,
				(
					"the first turn stands props and models (%d, %d)"
					% [view.props.made_total, view.actors.made_total]
				)
			)
	var again_props: int = view.props.made_total - props_made
	var again_models: int = view.actors.made_total - models_made
	_check(again_props == 0, "the later turns make no prop again (%d)" % again_props)
	_check(again_models == 0, "nor any model (%d)" % again_models)
	_check(beyond == 0, "nothing given a model past where it shows (%d)" % beyond)
	_check(
		over == 0,
		(
			"the parts with instance uniforms always in WebGL's room, with margin (%d frames over)"
			% over
		)
	)
	_check(
		view.world_material.get_shader_parameter("eye") == null and view.shared("eye") != null,
		"the frame's numbers are not handed to the materials"
	)
	times.sort()
	# The lower quartile: the PC's own hiccups (other work on it) left out,
	# as the yardstick's least run leaves them out.
	var quartile := times[times.size() / 4]
	var yard := _yardstick()
	_check(
		quartile < yard * FRAME_RATIO,
		(
			"the view's frame() %.2f ms (lower quartile), %.2f of the yardstick's %.2f (limit %.1f)"
			% [quartile, quartile / yard, yard, FRAME_RATIO]
		)
	)
	view.queue_free()


## Living bodies and props shown further than their models show.
func _beyond(view: WorldView3D, eye: Vector2) -> int:
	var n := 0
	var far := ActorView.REACH + ActorLayer3D.BEYOND
	var shown: Dictionary = view.actors.get("_shown")
	for id: int in shown:
		var body: ActorView = shown[id]
		var e := instance_from_id(id) as Enemy
		var at := Vector2(body.position.x, body.position.z)
		if e != null and e.alive and at.distance_to(eye) > far + .5:
			n += 1
	for item: Variant in view.props.shown():
		var node: PropView = item
		var at := Vector2(node.position.x, node.position.z)
		if at.distance_to(eye) > 51.0 + 12.0:
			n += 1
	return n


## Plain GDScript work (a dictionary, vector sums, an array), the least of a
## few runs, in ms: what this machine does in the time the view's frame is
## held to.
static func _yardstick() -> float:
	var best := INF
	for run in 7:
		var t0 := Time.get_ticks_usec()
		var d := {}
		var v := Vector3.ZERO
		var a: Array = []
		for i in 4000:
			var k := i & 63
			var was: float = d.get(k, 0.0)
			d[k] = was + 1.0
			v += Vector3(cos(i * .01), sin(i * .01), 1.0).normalized()
			a.append(v.x)
		best = minf(best, (Time.get_ticks_usec() - t0) / 1000.0)
	return best
