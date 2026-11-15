## Pictures of enemies dying, close up, in a real window (the graphics-card
## view players see): for each kind of hand on a level, one is stood in the
## open in front of the player, shot down, and pictured as it falls and lies
## (<kind>_<n>.png in out=<dir>), to look for anything left hanging in the air.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/death_frames.gd -- out=<dir> [level=hickston] [gun=shotgun]
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

const AFTER := [3, 8, 16, 30, 60, 120]
var probe := false

var main
var out := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var level := "hickston"
	var gun := "shotgun"
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a.begins_with("out="):
			out = a.substr(4)
		elif a.begins_with("level="):
			level = a.substr(6)
		elif a == "probe":
			probe = true
		elif a.begins_with("gun="):
			gun = a.substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.touring = true
	Effects.enabled = true
	main.start(level)
	var g: Game = main.game
	var seen := {}
	var picks: Array = []
	for i in g.enemies.size():
		var e: Enemy = g.enemies[i]
		if e.hostile and not seen.has(e.brain):
			seen[e.brain] = true
			picks.append(i)
	for i: int in picks:
		g = _level(level, [i])
		var e: Enemy = g.enemies[i]
		g.spawn_grace = 99.0
		var at: Vector2 = _spot(g, e.x, e.y, 2.4)
		if at == Vector2.INF:
			continue
		_stand(g, at.x, at.y, e.x, e.y, g.world.stand(e) + .4)
		_ticks(g, 10)
		e.hurt(400.0, g, false, false, null, gun)
		var n := 0
		for t: int in AFTER:
			_ticks(g, t - (0 if n == 0 else AFTER[n - 1]))
			_stand(g, at.x, at.y, e.x, e.y, g.world.stand(e) + .3)
			if probe:
				var sp: View.Sprite = e.sprite([at.x, at.y], false, g.clock)
				print(
					(
						"%s t%d toss %.3f stand %.3f floor %.3f sprite %s z %.3f"
						% [
							e.brain,
							t,
							e.toss,
							g.world.stand(e),
							g.world.floor_under(e.x, e.y, g.world.stand(e) + .3),
							sp.image if sp != null else "-",
							sp.z if sp != null else -1.0
						]
					)
				)
				continue
			await _snap("%s_%d" % [e.brain, t])
			n += 1
	print("death frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _snap(name: String) -> void:
	if main.game != null:
		main.game.message_until = 0.0
		main.game.barks.until = 0.0
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


## A level with nobody about (or only `keep`), the player unhurt.
func _level(level_id: String, keep: Array = []) -> Game:
	main.start(level_id)
	var g: Game = main.game
	g.cheats.god = true
	g.lessons = false
	g.barks.enabled = false
	for e: Enemy in g.enemies:
		if not keep.has(g.enemies.find(e)):
			e.dormant = true
	g.message_until = 0.0
	g.district_until = 0.0
	return g


## Stand at (x, y) looking at (tx, ty) at height tz.
func _stand(g: Game, x: float, y: float, tx: float, ty: float, tz: float) -> void:
	var p := g.player
	p.x = x
	p.y = y
	p.angle = atan2(ty - y, tx - x)
	p.eye = .95 + g.world.elevation(x, y)
	var d := Vector2(tx - x, ty - y).length()
	p.pitch = clampf((tz - p.eye) / maxf(d, .1) * View.base_focal, -50.0, 50.0)
	p.vx = 0.0
	p.vy = 0.0


func _ticks(g: Game, n: int, fire := false) -> void:
	var held := Game.Controls.new()
	for i in n:
		held.fire = fire and i == 0
		g.tick(1.0 / 60.0, held)


## A spot `far` from (x, y) on open floor at its height, that sees it.
func _spot(g: Game, x: float, y: float, far: float, away := Vector2.ZERO) -> Vector2:
	var w := g.world
	for k in 24:
		var dir := Vector2.from_angle(k * TAU / 24.0)
		if away != Vector2.ZERO and dir.dot(away) < .3:
			continue
		var at := Vector2(x, y) + dir * far
		if (
			at.x > 1.0
			and at.y > 1.0
			and at.x < w.width - 1
			and at.y < w.height - 1
			and not w.blocked(at.x, at.y, .3)
			and absf(w.elevation(at.x, at.y) - w.elevation(x, y)) < .05
			and w.visible(at.x, at.y, x, y, w.elevation(x, y) + .95, w.elevation(x, y) + .5)
			and _clear(g, at, Vector2(x, y))
		):
			return at
	return Vector2.INF


## Nothing standing between a and b to hide the view (a post, a tree).
func _clear(g: Game, a: Vector2, b: Vector2) -> bool:
	var things: Array = []
	for s: View.Sprite in g.props:
		things.append(Vector2(s.x, s.y))
	for board: LevelData.Billboard in g.world.billboards:
		things.append(Vector2(board.x, board.y))
	for q: Vector2 in things:
		var on := Geometry2D.get_closest_point_to_segment(q, a, b)
		if on.distance_to(q) < .45 and q.distance_to(b) > .6 and q.distance_to(a) > .3:
			return false
	return true
