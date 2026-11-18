## Pictures of walls taking a beating, in a real window (the destruction
## pass's WALLS track, docs/godot3d/destruction/WALLS/): a storefront window
## shot once (cracked) and again (shot out), another blown out by a stick of
## dynamite, a plank fence shot about round by round with the revolver, one
## torn by a load of buckshot, one blown through, a shed's boards shot about
## from outside, and the holes rounds leave in brick, planks and tin, and a
## blast's scorch on brick. Each is a row of frames, <scene>_<n>.png, in
## out=<dir>.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/walls_frames.gd -- out=<dir> [only=<scene>]
##
## It drives the game only the way play does (aim, fire, a blast where a
## stick would land), so the same script on an older build shows the before.
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

var main
var out := ""
var only := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
		if String(arg).begins_with("only="):
			only = String(arg).substr(5)
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
	for scene: String in ["window", "window_blast", "fence", "buckshot", "fence_blast", "holes"]:
		if only == "" or only == scene:
			await call(scene)
	print("walls frames written to ", out)
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


func _level(level_id: String) -> Game:
	main.start(level_id)
	var g: Game = main.game
	g.cheats.god = true
	g.lessons = false
	g.barks.enabled = false
	for e: Enemy in g.enemies:
		e.dormant = true
	g.message_until = 0.0
	g.district_until = 0.0
	return g


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


func _arm(g: Game, gun: int) -> void:
	var a = g.armory
	a.owned[gun] = true
	a.reserve[gun] = maxi(Weapons.MAX_RESERVE[gun], 1)
	a.loaded[gun] = Weapons.CAPACITY[gun]
	a.active = gun
	a.switch = 0.0
	a.cooldown = 0.0
	a.reload = 0.0
	a.holstered = false
	a.lower = 0.0


func _ticks(g: Game, n: int, fire := false) -> void:
	var held := Game.Controls.new()
	for i in n:
		held.fire = fire and i == 0
		g.tick(1.0 / 60.0, held)


func _row(g: Game, name: String, gaps: Array) -> void:
	for k in gaps.size():
		_ticks(g, int(gaps[k]))
		await _snap("%s_%d" % [name, k + 1])


## Nothing standing between a and b (a post, a tree, a sign).
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


## A brick window on Hickston's street to stand `far` in front of (a little
## to the side), skipping the first `skip` that would do.
func _window_spot(g: Game, far: float, skip: int) -> Variant:
	var wb = g.features["wall_breaks"]
	for face in wb.windows:
		if not String(g.world.tile_names[face.whole]).begins_with("brick"):
			continue
		var n: Vector2 = face.normal()
		var mid: Vector2 = face.middle()
		var at := mid + n * far + n.orthogonal() * .5
		if (
			g.world.blocked(at.x, at.y, .3)
			or not g.world.visible(at.x, at.y, mid.x + n.x * .05, mid.y + n.y * .05, .95, 1.34)
			or not _clear(g, at, mid)
		):
			continue
		if skip > 0:
			skip -= 1
			continue
		return [face, at]
	return null


## A window shot with the revolver: once low and left (it cracks), then high
## and right (it goes), the glass flying and breaking where it lands.
func window() -> void:
	var g := _level("hickston")
	var spot = _window_spot(g, 2.4, 0)
	if spot == null:
		return
	var face = spot[0]
	var at: Vector2 = spot[1]
	var mid: Vector2 = face.middle()
	var along: Vector2 = Vector2(face.edge.z - face.edge.x, face.edge.w - face.edge.y).normalized()
	_arm(g, Weapons.REVOLVER)
	var first := mid - along * .12
	_stand(g, at.x, at.y, first.x, first.y, 1.2)
	_ticks(g, 20)
	await _snap("window_0")
	_ticks(g, 1, true)
	await _row(g, "window_crack", [4, 30])
	var second := mid + along * .14
	_stand(g, at.x, at.y, second.x, second.y, 1.5)
	_ticks(g, 30)
	_ticks(g, 1, true)
	await _row(g, "window_shot", [2, 5, 9, 16, 30, 90])


## A window blown out by a stick of dynamite on the walk below it.
func window_blast() -> void:
	var g := _level("hickston")
	var spot = _window_spot(g, 3.0, 2)
	if spot == null:
		return
	var face = spot[0]
	var at: Vector2 = spot[1]
	var mid: Vector2 = face.middle()
	var n: Vector2 = face.normal()
	_arm(g, Weapons.REVOLVER)
	_stand(g, at.x, at.y, mid.x, mid.y, 1.2)
	_ticks(g, 20)
	await _snap("window_blast_0")
	var boom := mid + n * .9
	g.explode(Game.Shot.new(boom.x, boom.y, g.world.elevation(boom.x, boom.y) + .4, 0, 0, 0, "tnt"))
	await _row(g, "window_blast", [3, 7, 12, 20, 40, 90])


## A fence cell that may open, seen square from `far` on a clear side.
func _fence_spot(g: Game, far: float, skip: int) -> Variant:
	var wb = g.features["wall_breaks"]
	var cells: Array = wb.fences.keys()
	cells.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return a.y * 1000 + a.x < b.y * 1000 + b.x
	)
	for cell: Vector2i in cells:
		var f = wb.fences[cell]
		if not f.opens or f.inside >= 0:
			continue
		var centre := Vector2(cell.x + .5, cell.y + .5)
		var n := Vector2(0, 1) if f.along_x else Vector2(1, 0)
		for way: float in [1.0, -1.0]:
			var near := centre + n * way * far
			var back := centre - n * way * 2.5
			var face := centre + n * way * .55
			if (
				g.world.blocked(near.x, near.y, .3)
				or g.world.blocked(back.x, back.y, .3)
				or not _clear(g, near, centre)
				or not g.world.visible(near.x, near.y, face.x, face.y)
			):
				continue
			if skip > 0:
				skip -= 1
				continue
			return [f, near, centre]
	return null


## A plank fence shot round by round with the revolver, each round a little
## off the last, then the gap.
func fence() -> void:
	var g := _level("fair")
	var spot = _fence_spot(g, 2.2, 0)
	if spot == null:
		return
	var near: Vector2 = spot[1]
	var centre: Vector2 = spot[2]
	_arm(g, Weapons.REVOLVER)
	_stand(g, near.x, near.y, centre.x, centre.y, .7)
	_ticks(g, 20)
	await _snap("fence_0")
	var aims := [
		Vector2(-.2, .75), Vector2(.18, .5), Vector2(-.15, .4), Vector2(.05, .9), Vector2(0, .6)
	]
	var side := (centre - near).normalized().orthogonal()
	for k in aims.size():
		var aim: Vector2 = aims[k]
		var to := centre + side * aim.x
		_stand(g, near.x, near.y, to.x, to.y, aim.y)
		_ticks(g, 1, true)
		_ticks(g, 6)
		await _snap("fence_shot_%d_a" % (k + 1))
		_ticks(g, 34)
		await _snap("fence_shot_%d" % (k + 1))


## A plank fence torn by buckshot at a few paces: twice.
func buckshot() -> void:
	var g := _level("fair")
	var spot = _fence_spot(g, 2.6, 3)
	if spot == null:
		return
	var near: Vector2 = spot[1]
	var centre: Vector2 = spot[2]
	_arm(g, Weapons.SHOTGUN)
	_stand(g, near.x, near.y, centre.x, centre.y, .7)
	_ticks(g, 20)
	await _snap("buckshot_0")
	_ticks(g, 1, true)
	await _row(g, "buckshot", [4, 30])
	_ticks(g, 40)
	_ticks(g, 1, true)
	await _row(g, "buckshot_2", [4, 12, 40])


## A plank fence blown through by a stick of dynamite against it.
func fence_blast() -> void:
	var g := _level("fair")
	var spot = _fence_spot(g, 3.2, 6)
	if spot == null:
		return
	var near: Vector2 = spot[1]
	var centre: Vector2 = spot[2]
	_arm(g, Weapons.REVOLVER)
	_stand(g, near.x, near.y, centre.x, centre.y, .6)
	_ticks(g, 20)
	await _snap("fence_blast_0")
	var boom := centre + (near - centre).normalized() * .75
	g.explode(Game.Shot.new(boom.x, boom.y, g.world.elevation(boom.x, boom.y) + .3, 0, 0, 0, "tnt"))
	await _row(g, "fence_blast", [3, 7, 12, 20, 40, 90])


## A wall face of a tile whose name has `part` to stand `far` square before.
func _wall_spot(g: Game, part: String, far: float) -> Variant:
	var w := g.world
	var stride := LevelData.WALL_STRIDE
	for i in w.wall_count:
		var o := i * stride
		var name := String(w.tile_names[int(w.walls[o + 4])])
		if not name.contains(part) or name.ends_with("_win") or name.ends_with("_lit"):
			continue
		var a := Vector2(w.walls[o], w.walls[o + 1])
		var b := Vector2(w.walls[o + 2], w.walls[o + 3])
		if a.distance_to(b) < .99 or w.walls[o + 7] - w.walls[o + 6] < 1.2:
			continue
		var mid := (a + b) * .5
		var n := (b - a).normalized().orthogonal()
		for way: float in [1.0, -1.0]:
			var at := mid + n * way * far
			var face := mid + n * way * .05
			if (
				at.x < 1
				or at.y < 1
				or at.x > w.width - 1
				or at.y > w.height - 1
				or w.blocked(at.x, at.y, .3)
				or not w.visible(at.x, at.y, face.x, face.y, .95, 1.0)
				or not _clear(g, at, mid)
			):
				continue
			return [mid, at]
	return null


## Rounds into brick, planks and tin from two paces, and a blast on brick.
func holes() -> void:
	for row: Array in [["hickston", "brick"], ["fair", "barn"], ["hickston", "tin"]]:
		var g := _level(str(row[0]))
		var spot = _wall_spot(g, str(row[1]), 1.8)
		if spot == null:
			print("no %s wall on %s" % [row[1], row[0]])
			continue
		var mid: Vector2 = spot[0]
		var at: Vector2 = spot[1]
		var side := (mid - at).normalized().orthogonal()
		_arm(g, Weapons.REVOLVER)
		for k in 3 if row[1] == "barn" else 4:
			var to := mid + side * (k - 1.5) * .22
			_stand(g, at.x, at.y, to.x, to.y, 1.0 + (k % 2) * .25)
			_ticks(g, 1, true)
			_ticks(g, 24)
		_stand(g, at.x, at.y, mid.x, mid.y, 1.1)
		_ticks(g, 2)
		await _snap("holes_%s" % row[1])
		if row[1] == "brick":
			var boom := mid + (at - mid).normalized() * .5
			g.explode(
				Game.Shot.new(
					boom.x, boom.y, g.world.elevation(boom.x, boom.y) + .5, 0, 0, 0, "tnt"
				)
			)
			_ticks(g, 90)
			await _snap("holes_brick_blast")
