## Pictures of the models that stood in for flat pictures after v3.2.0, in a
## real window (the graphics-card view players see):
##   duck_<0..3>      the range's duck gallery: ducks going right, going left,
##                    just turned at the end of the rail, knocked over
##   fair_duck_0      the fair's gallery ducks riding their rail
##   cow_<0..5>       a cow tipped: standing, going over, at the ground,
##                    lying (from the side and from by her head), getting up
##   lamp_<0..3>      a shop lamp in the saw floor's arena: hung, letting go,
##                    falling, lying where it landed
## Each lands in out=<dir> as <name>.png; only=<a,b> takes some of: duck,
## cow, lamp.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/model_frames.gd -- out=<dir> [only=cow]
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

const L := preload("res://src/range_layout.gd")

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
	if _wanted("duck"):
		await _ducks()
	if _wanted("cow"):
		await _cow()
	if _wanted("lamp"):
		await _lamp()
	print("model frames written to ", out)
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


func _stand(g: Game, x: float, y: float, tx: float, ty: float, tz: float) -> void:
	var p := g.player
	p.x = x
	p.y = y
	p.angle = atan2(ty - y, tx - x)
	p.floor_z = g.world.floor_under(x, y, .05)
	p.eye = .95 + g.world.stand(p)
	var d := Vector2(tx - x, ty - y).length()
	p.pitch = clampf((tz - p.eye) / maxf(d, .1) * View.base_focal, -50.0, 50.0)
	p.vx = 0.0
	p.vy = 0.0
	g.armory.holstered = true
	g.armory.lower = 1.0


func _ticks(g: Game, n: int) -> void:
	for i in n:
		g.tick(1.0 / 60.0, Game.Controls.new())


## The range's duck row from the firing line, close; then the fair's.
func _ducks() -> void:
	var g := _level("range")
	var t = g.features["range"].targets
	t.start_gallery(g)
	var row: Array = L.GALLERY_ROWS[1]
	var row_y: float = row[0]
	var mid: float = (L.GALLERY_X[0] + L.GALLERY_X[1]) * .5
	var view := func() -> void: _stand(g, mid, row_y + 3.2, mid, row_y, row[1] + .3)
	view.call()
	_ticks(g, 20)
	view.call()
	await _snap("duck_0")
	# Until a duck runs the other way.
	var turned := false
	for k in 600:
		_ticks(g, 1)
		for m: Dictionary in t.movers:
			if int(m["row"]) == 1 and float(m["dir"]) < 0.0:
				turned = true
		if turned:
			break
	_ticks(g, 30)
	view.call()
	await _snap("duck_1")
	# A duck just turned at the rail's end, seen from that end.
	for m: Dictionary in t.movers:
		if int(m["row"]) == 1:
			m["x"] = L.GALLERY_X[1] - .05
			m["dir"] = 1.0
	_ticks(g, 6)
	_stand(g, L.GALLERY_X[1] - 1.0, row_y + 2.6, L.GALLERY_X[1] - .4, row_y, row[1] + .3)
	await _snap("duck_2")
	for m: Dictionary in t.movers:
		if int(m["row"]) == 1:
			m["down_until"] = g.clock + .5
	_ticks(g, 9)
	view.call()
	await _snap("duck_3")
	g = _level("fair")
	var f = g.features["fair_gallery"]
	f.start(g.player)
	_ticks(g, 150)
	_stand(g, 98.5, 49.0, 98.5, 44.75, 1.6)
	await _snap("fair_duck_0")


## A cow tipped over, from her side, then from behind her back.
func _cow() -> void:
	var g := _level("hickston")
	var crit = g.features["critters"]
	var cow: Enemy = null
	for e: Enemy in g.enemies:
		if e.brain == "cow" and e.alive:
			cow = e
			break
	if cow == null:
		return
	cow.angle = 0.0
	cow.face_left = false
	var floor_z: float = g.world.elevation(cow.x, cow.y)
	var side := Vector2(cow.x - .3, cow.y + 3.6)
	_stand(g, side.x, side.y, cow.x, cow.y, floor_z + .6)
	_ticks(g, 2)
	_stand(g, side.x, side.y, cow.x, cow.y, floor_z + .6)
	await _snap("cow_0")
	g.player.x = cow.x
	g.player.y = cow.y + 1.0
	crit.tip(g.player)
	var steps := [16, 18, 40]
	for k in steps.size():
		_ticks(g, steps[k])
		_stand(g, side.x, side.y, cow.x, cow.y, floor_z + .5)
		await _snap("cow_%d" % (k + 1))
	_stand(g, cow.x + 2.6, cow.y + 1.7, cow.x, cow.y, floor_z + .2)
	_ticks(g, 1)
	_stand(g, cow.x + 2.6, cow.y + 1.7, cow.x, cow.y, floor_z + .2)
	await _snap("cow_4")
	# Getting up.
	for k in 60 * 12:
		_ticks(g, 1)
		if cow.held_cel == "":
			break
	_ticks(g, 20)
	_stand(g, side.x, side.y, cow.x, cow.y, floor_z + .5)
	await _snap("cow_5")


## The saw floor's first shop lamp letting go over the foreman's arena.
func _lamp() -> void:
	var g: Game = BossRematch.build(Callable(main, "make_game"), "foreman")
	main.game = g
	main.state = "play"
	g.configure(SessionStore.defaults())
	g.cheats.god = true
	g.barks.enabled = false
	var e := BossFight.of_kind(g, "foreman")
	var f: ArenaWreckFeature = g.features["arena_wreck"]
	var step: Dictionary = {}
	for i in f.steps.size():
		if f.foes[i] == e and str(f.steps[i]["do"]) == "fall":
			step = f.steps[i]
			break
	if step.is_empty():
		return
	var spot: Array = step["spots"][0]
	var sx: float = spot[0]
	var sy: float = spot[1]
	var floor_z: float = g.world.elevation(sx, sy)
	var look := func(tz: float) -> void:
		_stand(g, sx - .6, sy + 3.0, sx, sy, floor_z + tz)
		e.stun = 10.0
		e.cooldown = 10.0
	look.call(2.0)
	_ticks(g, 2)
	look.call(2.0)
	await _snap("lamp_0")
	var at_hp: float = step["at"]
	e.hp = e.max_hp * (at_hp - .01)
	BossKit.phase_check(e, g)
	for k in 3:
		var n: int = [50, 61, 90][k]
		for i in n:
			e.stun = 10.0
			e.cooldown = 10.0
			_ticks(g, 1)
		look.call([2.2, 1.5, .2][k])
		await _snap("lamp_%d" % (k + 1))
