## Pictures of things breaking and moving loose, in a real window (the
## graphics-card view players see): a barrel shot to pieces, a hazard barrel
## setting off the one beside it, a body knocked back against a wall, a body
## taken apart and its gibs bouncing, a stick of dynamite rolling down a step,
## and a blast throwing what lies about. Each is a row of frames,
## <effect>_<n>.png, in out=<dir>.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/physics_frames.gd -- out=<dir>
##
## It drives the game only the way play does (aim, fire, a blast where a
## stick would land), so the same script on an older build shows the before.
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

var main
var out := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
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
	await _barrel()
	await _chain()
	await _body()
	await _gibs()
	await _dynamite()
	await _blast()
	print("physics frames written to ", out)
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
	p.pitch = clampf((tz - p.eye) / maxf(d, .1) * Renderer.base_focal, -50.0, 50.0)
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


## A row of frames: one now, then one after each count of ticks.
func _row(g: Game, name: String, gaps: Array) -> void:
	await _snap("%s_0" % name)
	for k in gaps.size():
		_ticks(g, int(gaps[k]))
		await _snap("%s_%d" % [name, k + 1])


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
	for s: Renderer.Sprite in g.props:
		things.append(Vector2(s.x, s.y))
	for board: LevelData.Billboard in g.world.billboards:
		things.append(Vector2(board.x, board.y))
	for q: Vector2 in things:
		var on := Geometry2D.get_closest_point_to_segment(q, a, b)
		if on.distance_to(q) < .45 and q.distance_to(b) > .6 and q.distance_to(a) > .3:
			return false
	return true


## Whether (x, y) stands out in a yard: no wall within two cells.
func _yard(g: Game, x: float, y: float) -> bool:
	for cy in range(int(y) - 2, int(y) + 3):
		for cx in range(int(x) - 2, int(x) + 3):
			if g.world.solid[cy * g.world.width + cx] >= 0:
				return false
	return true


func _boards(g: Game, image: String) -> Array:
	var out_list: Array = []
	for b: LevelData.Billboard in g.world.billboards:
		if b.image == image:
			out_list.append(Vector2(b.x, b.y))
	return out_list


## A barrel shot with the sawed-off at a few paces.
func _barrel() -> void:
	var g := _level("hickston")
	for s: Renderer.Sprite in g.props:
		if s.image != "prop_barrel" or not _yard(g, s.x, s.y):
			continue
		var at := _spot(g, s.x, s.y, 2.4)
		if at == Vector2.INF:
			continue
		_stand(g, at.x, at.y, s.x, s.y, g.world.elevation(s.x, s.y) + .55)
		_arm(g, Weapons.SHOTGUN)
		_ticks(g, 20)
		await _snap("barrel_0")
		_ticks(g, 1, true)
		await _row(g, "barrel_shot", [2, 4, 6, 10, 20, 40])
		return


## A hazard barrel shot from across the yard sets off the one beside it.
func _chain() -> void:
	var g := _level("hickston")
	var barrels := _boards(g, "town_warning_barrel")
	for a: Vector2 in barrels:
		for b: Vector2 in barrels:
			if a == b or a.distance_to(b) > 2.5:
				continue
			var mid := (a + b) * .5
			var side := (b - a).orthogonal().normalized()
			var at := _spot(g, mid.x, mid.y, 6.0, side)
			if at == Vector2.INF:
				at = _spot(g, mid.x, mid.y, 6.0, -side)
			if at == Vector2.INF:
				continue
			_stand(g, at.x, at.y, a.x, a.y, g.world.elevation(a.x, a.y) + .5)
			_arm(g, Weapons.RIFLE)
			_ticks(g, 20)
			await _snap("chain_0")
			_ticks(g, 1, true)
			await _row(g, "chain_shot", [5, 6, 8, 10, 14, 24])
			return


## A hand shot in front of a wall: knocked back, it slides up to the wall.
func _body() -> void:
	var g := _level("hickston")
	var w := g.world
	var target := -1
	for i in g.enemies.size():
		var e: Enemy = g.enemies[i]
		if e.hostile and e.brain == "billy":
			target = i
			break
	if target < 0:
		return
	g = _level("hickston", [target])
	w = g.world
	var e: Enemy = g.enemies[target]
	for cy in range(3, w.height - 3):
		for cx in range(4, w.width - 4):
			if (
				w.solid[cy * w.width + cx + 2] >= 0
				and not w.blocked(cx + .5, cy + .5, .35)
				and not w.blocked(cx + 1.4, cy + .5, .3)
				and not w.blocked(cx - 2.0, cy + .5, .3)
				and w.elevation(cx + .5, cy + .5) == w.elevation(cx - 2.0, cy + .5)
				and w.elevation(cx + .5, cy + .5) == w.elevation(cx + 1.4, cy + .5)
				and w.visible(cx - 2.0, cy + .5, cx + .5, cy + .5)
				and _clear(g, Vector2(cx - 2.0, cy + .5), Vector2(cx + .5, cy + .5))
			):
				var side := _spot(g, cx + 1.0, cy + .5, 3.2, Vector2(.3, 1.0))
				if side == Vector2.INF:
					side = _spot(g, cx + 1.0, cy + .5, 3.2, Vector2(.3, -1.0))
				if side == Vector2.INF:
					continue
				e.x = cx + .5
				e.y = cy + .5
				e.angle = PI
				e.hp = 30.0
				g.spawn_grace = 99.0
				_stand(g, side.x, side.y, cx + 1.0, cy + .5, w.elevation(e.x, e.y) + .4)
				_ticks(g, 20)
				await _snap("body_0")
				_stand(g, cx - 2.0, cy + .5, e.x, e.y, w.elevation(e.x, e.y) + .7)
				_arm(g, Weapons.SHOTGUN)
				_ticks(g, 1, true)
				_stand(g, side.x, side.y, cx + 1.0, cy + .5, w.elevation(e.x, e.y) + .4)
				await _row(g, "body_shot", [3, 6, 8, 12, 20, 40])
				return


## A hand taken apart at close range: the gibs fly, bounce, roll and lie.
func _gibs() -> void:
	var g := _level("hickston")
	var target := -1
	for i in g.enemies.size():
		if (g.enemies[i] as Enemy).hostile and (g.enemies[i] as Enemy).brain == "billy":
			target = i
			break
	g = _level("hickston", [target])
	var e: Enemy = g.enemies[target]
	g.spawn_grace = 99.0
	var at := _spot(g, e.x, e.y, 2.6)
	if at == Vector2.INF:
		return
	_stand(g, at.x, at.y, e.x, e.y, g.world.elevation(e.x, e.y) + .2)
	_ticks(g, 20)
	await _snap("gibs_0")
	g.explode(Game.Shot.new(e.x, e.y, g.world.elevation(e.x, e.y) + .3, 0, 0, 0, "tnt"))
	await _row(g, "gibs_blast", [4, 6, 8, 12, 20, 40])


## A stick of dynamite left at the edge of a step rolls down it.
func _dynamite() -> void:
	var g := _level("mothership")
	var w := g.world
	for cy in range(2, w.height - 2):
		for cx in range(4, w.width - 4):
			var here := w.elevation(cx + .5, cy + .5)
			var drop := here - w.elevation(cx + 1.5, cy + .5)
			if (
				drop < .2
				or drop > .3
				or w.elevation(cx + 2.5, cy + .5) > here - drop
				or w.blocked(cx + .75, cy + .5, .3)
				or w.blocked(cx + 1.5, cy + .5, .3)
				or w.blocked(cx + 2.5, cy + .5, .3)
			):
				continue
			var at := _spot(g, cx + 1.2, cy + .5, 2.4)
			if at == Vector2.INF:
				continue
			_stand(g, at.x, at.y, cx + 1.2, cy + .5, here - .3)
			_ticks(g, 10)
			g.shots.append(Game.Shot.new(cx + .75, cy + .5, here + .045, 0, 0, 0, "tnt", 1.6))
			await _row(g, "dynamite_roll", [6, 10, 14, 20, 30, 40])
			return


## A blast among a broken crate's bits, a body and loose barrels throws them.
func _blast() -> void:
	var g := _level("hickston")
	for s: Renderer.Sprite in g.props:
		if s.image != "prop_barrel":
			continue
		if not _yard(g, s.x, s.y):
			continue
		var others := 0
		for t: Renderer.Sprite in g.props:
			if t != s and t.image == "prop_barrel" and Vector2(t.x - s.x, t.y - s.y).length() < 2.6:
				others += 1
		if others < 1:
			continue
		var at := _spot(g, s.x, s.y, 4.5)
		if at == Vector2.INF:
			continue
		_stand(g, at.x, at.y, s.x, s.y, g.world.elevation(s.x, s.y) + .4)
		_arm(g, Weapons.SHOTGUN)
		_ticks(g, 1, true)
		_ticks(g, 60)
		await _snap("blast_0")
		var boom := Vector2(s.x, s.y) + Vector2(at.x - s.x, at.y - s.y).normalized() * .6
		g.explode(
			Game.Shot.new(boom.x, boom.y, g.world.elevation(boom.x, boom.y) + .2, 0, 0, 0, "tnt")
		)
		await _row(g, "blast_throw", [4, 6, 10, 16, 30, 50])
		return
