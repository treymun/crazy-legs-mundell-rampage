## Pictures of BLUE, the hound (features/hound.gd), in a real window:
##   hound_<name>   see SHOTS below
## Each lands in out=<dir> as <name>.png; only=<a,b> takes some of them.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/hound_frames.gd -- out=<dir> [only=follow,pin]
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

## [picture, level, state (features/hound.gd), his turn from facing the eye]
const POSES := [
	["stand", "hickston", 0, 1.2],
	["front", "hickston", 0, 0.0],
	["sit", "hickston", 1, 0.9],
	["bay", "fair", 6, 1.3],
	["point", "sawmill", 7, 1.57],
	["carry", "hickston", 5, 0.5],
	["down", "hickston", 8, 1.5],
	["dusk", "quarry", 0, 2.2],
]

var main
var out := ""
var only: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
		elif String(arg).begins_with("only="):
			only = String(arg).substr(5).split(",")
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
	if _wanted("start"):
		var g := _level("hickston")
		_ticks(g, 30)
		await _snap("hound_start")
	# Each pose of his from a few cells off, at his side and from the front.
	for pose: Array in POSES:
		var name: String = pose[0]
		if not _wanted(name) and not _wanted("poses"):
			continue
		var g := _level(str(pose[1]))
		_ticks(g, 4)
		var h = g.features["hound"]
		var d = h.dogs[0]
		h.call("_into", d, int(pose[2]))
		d.until = g.clock + 99.0
		d.bark_at = g.clock + 99.0 if pose[2] in [6, 7] else -10.0
		d.down_at = g.clock - 2.0 if pose[2] == 8 else -1.0
		if pose[2] == 5:
			d.item = "shells"
		var p := g.player
		var turn: float = pose[3]
		d.x = p.x + cos(p.angle) * 2.6
		d.y = p.y + sin(p.angle) * 2.6
		d.floor_z = g.world.floor_under(d.x, d.y, g.world.stand(p) + .4)
		d.angle = p.angle + PI + turn
		p.pitch = -16.0
		g.armory.holstered = true
		g.armory.lower = 1.0
		await _snap("hound_" + name)
	if _wanted("pin"):
		await _pin()
	print("hound frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _wanted(part: String) -> bool:
	return only.is_empty() or only.has(part)


func _snap(name: String) -> void:
	var g: Game = main.game
	if g != null:
		g.message_until = 0.0
		g.callout_until = 0.0
		g.district_until = 0.0
		g.barks.until = 0.0
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


func _level(level_id: String) -> Game:
	main.options["hound"] = 1
	main.start(level_id)
	var g: Game = main.game
	g.cheats.god = true
	g.lessons = false
	g.barks.enabled = false
	for e: Enemy in g.enemies:
		if e.hostile:
			e.dormant = true
	g.spawn_grace = 99.0
	return g


func _ticks(g: Game, n: int) -> void:
	for i in n:
		g.tick(1.0 / 60.0, Game.Controls.new())


## BLUE holding a hand down: the hand stunned in its pain pose, BLUE hauling
## on it, from the side.
func _pin() -> void:
	main.options["hound"] = 1
	main.start("hickston")
	var g: Game = main.game
	g.cheats.god = true
	g.lessons = false
	g.barks.enabled = false
	g.spawn_grace = 99.0
	_ticks(g, 4)
	var p := g.player
	var foe: Enemy = null
	for e: Enemy in g.enemies:
		if foe == null and e.hostile and HoundNose.takes(e) and e.tactical():
			foe = e
		else:
			e.dormant = true
	var at := Vector2(p.x + cos(p.angle) * 3.4, p.y + sin(p.angle) * 3.4)
	foe.x = at.x
	foe.y = at.y
	foe.floor_z = g.world.floor_under(at.x, at.y, g.world.stand(p) + .4)
	foe.alerted = true
	foe.angle = p.angle + PI * .5
	foe.hp = foe.max_hp * .4
	var h = g.features["hound"]
	var d = h.dogs[0]
	var side := p.angle - PI * .5
	d.x = foe.x + cos(side) * .62
	d.y = foe.y + sin(side) * .62
	d.floor_z = foe.floor_z
	h.call("_into", d, 3)
	d.foe = foe.uid
	d.until = g.clock + 99.0
	d.angle = atan2(foe.y - d.y, foe.x - d.x)
	foe.stun = .3
	p.pitch = -10.0
	await _snap("hound_pin")
