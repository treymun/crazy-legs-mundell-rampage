## Pictures of things breaking and moving loose, in a real window (the
## graphics-card view players see): a barrel shot to pieces, a hazard barrel
## setting off the one beside it, a body knocked back against a wall, a body
## taken apart and its gibs bouncing, a stick of dynamite rolling down a step,
## a blast throwing what lies about, a storefront window shot out, a plank
## fence shot about and then through, and a boss fight (its entrance, the ring
## of its wind-up, its damage, a stagger, its fall; only=boss for just those).
## And how hits land (only=hits for just these): a head shot (the hat off, the
## pop), buckshot throwing a hand through a window, the cow launcher's throw,
## a body floating in the bayou, chickens scattering at a shot.
## Each is a row of frames, <effect>_<n>.png, in out=<dir>.
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
	# The boss's entrance is pictured (a tool gets none otherwise).
	BossKit.tool_intros = true
	var args := OS.get_cmdline_user_args()
	if args.has("only=hits"):
		await _hits()
		print("physics frames written to ", out)
		main.queue_free()
		await process_frame
		quit()
		return
	# only=boss: just the boss fight's pictures.
	if not args.has("only=boss"):
		await _barrel()
		await _chain()
		await _body()
		await _gibs()
		await _dynamite()
		await _blast()
		await _window()
		await _fence()
		await _hits()
	await _boss()
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


## A Hickston storefront window shot out with the revolver from across the
## walk, seen a little from the side.
func _window() -> void:
	var g := _level("hickston")
	var wb = g.features["wall_breaks"]
	for face in wb.windows:
		if not String(g.world.tile_names[face.whole]).begins_with("brick"):
			continue
		var n: Vector2 = face.normal()
		var mid: Vector2 = face.middle()
		var at := mid + n * 2.6 + n.orthogonal() * .7
		if (
			g.world.blocked(at.x, at.y, .3)
			or not g.world.visible(at.x, at.y, mid.x + n.x * .05, mid.y + n.y * .05, .95, 1.34)
			or not _clear(g, at, mid)
		):
			continue
		_stand(g, at.x, at.y, mid.x, mid.y, 1.34)
		_arm(g, Weapons.REVOLVER)
		_ticks(g, 20)
		await _snap("window_0")
		_ticks(g, 1, true)
		await _row(g, "window_shot", [2, 5, 10, 20, 40])
		return


## A plank fence cell shot about by one revolver round, then broken through by
## two more, then the gap seen from further back and from the far side.
func _fence() -> void:
	for level_id: String in ["fair", "hickston"]:
		var g := _level(level_id)
		var wb = g.features["wall_breaks"]
		for f in wb.fences.values():
			if not f.opens:
				continue
			var centre := Vector2(f.cell.x + .5, f.cell.y + .5)
			var n := Vector2(0, 1) if f.along_x else Vector2(1, 0)
			for way: float in [1.0, -1.0]:
				var near := centre + n * way * 2.4
				var far := centre - n * way * 3.0
				var face := centre + n * way * .55
				if (
					g.world.blocked(near.x, near.y, .3)
					or g.world.blocked(far.x, far.y, .3)
					or not _clear(g, near, centre)
					or not g.world.visible(near.x, near.y, face.x, face.y)
				):
					continue
				_stand(g, near.x, near.y, centre.x, centre.y, .55)
				_arm(g, Weapons.REVOLVER)
				_ticks(g, 20)
				await _snap("fence_0")
				for k in 3:
					_ticks(g, 1, true)
					_ticks(g, 40)
					await _snap("fence_shot_%d" % (k + 1))
				var back := centre + n * way * 4.5 + n.orthogonal() * 1.2
				if not g.world.blocked(back.x, back.y, .3):
					_stand(g, back.x, back.y, centre.x, centre.y, .4)
					_ticks(g, 2)
					await _snap("fence_gap")
				_stand(g, far.x, far.y, centre.x, centre.y, .5)
				_ticks(g, 2)
				await _snap("fence_far_side")
				return


## The sheriff's fight: his entrance (the name on its ribbon), his wind-up
## with the ring closing round where he aims, smoke past half and sparks past
## a fifth, a load of buckshot staggering him, and his fall in slow motion
## with the gibs and the loot shower.
func _boss() -> void:
	var g := _level("hickston")
	var index := g.enemies.find(g.boss)
	g = _level("hickston", [index])
	var e: Enemy = g.boss
	var w := g.world
	var at := _spot(g, e.x, e.y, 5.0)
	if at == Vector2.INF:
		return
	_stand(g, at.x, at.y, e.x, e.y, w.elevation(e.x, e.y) + .9)
	g.player.angle += .6
	e.alerted = true
	g.lessons = true
	_ticks(g, 1)
	await _row(g, "boss_intro", [6, 10, 30])
	_ticks(g, 80)
	g.lessons = false
	_stand(g, at.x, at.y, e.x, e.y, w.elevation(e.x, e.y) + .5)
	var toward := Vector2(e.x - at.x, e.y - at.y).normalized()
	var aim := at + toward * 2.6
	e.stun = 0.0
	e.windup = 1.0
	e.aim_mark = [aim.x, aim.y, g.player.eye]
	g.features["boss_fight"].windups.clear()
	_ticks(g, 1)
	await _row(g, "boss_ring", [18, 18, 18])
	e.windup = 0.0
	e.aim_mark = null
	e.cooldown = 99.0
	e.hp = e.max_hp * .45
	e.boss_phase = 2
	_stand(g, at.x, at.y, e.x, e.y, w.elevation(e.x, e.y) + 1.0)
	_ticks(g, 20)
	await _snap("boss_smoke_2")
	e.hp = e.max_hp * .15
	e.boss_phase = 3
	_ticks(g, 20)
	await _snap("boss_smoke_3")
	var close := _spot(g, e.x, e.y, 2.3)
	if close == Vector2.INF:
		return
	_stand(g, close.x, close.y, e.x, e.y, w.elevation(e.x, e.y) + .6)
	_arm(g, Weapons.SHOTGUN)
	e.hp = e.max_hp * .9
	e.boss_phase = 1
	e.cooldown = 99.0
	_ticks(g, 20)
	_ticks(g, 1, true)
	await _row(g, "boss_stagger", [2, 6, 12])
	_stand(g, at.x, at.y, e.x, e.y, w.elevation(e.x, e.y) + .4)
	e.hp = 1.0
	e.cooldown = 99.0
	_arm(g, Weapons.REVOLVER)
	_ticks(g, 2)
	_ticks(g, 1, true)
	await _row(g, "boss_fall", [6, 14, 24, 40, 70, 110])


func _hits() -> void:
	await _headshot()
	await _window_throw()
	await _cow_throw()
	await _floating()
	await _chickens()


## The first enemy of a kind in a level, the rest put to sleep: its index.
func _first(level_id: String, kind: String) -> int:
	var g := _level(level_id)
	for i in g.enemies.size():
		if (g.enemies[i] as Enemy).kind == kind:
			return i
	return -1


## A revolver round to the head of a hand three paces off: the hat flies, the
## head pops (and the gold mark at the crosshair).
func _headshot() -> void:
	var target := _first("hickston", "clone")
	if target < 0:
		return
	var g := _level("hickston", [target])
	g.aim_assist = 0
	g.spawn_grace = 99.0
	var e: Enemy = g.enemies[target]
	var at := _spot(g, e.x, e.y, 3.0)
	if at == Vector2.INF:
		return
	e.hp = 20.0
	e.angle = atan2(at.y - e.y, at.x - e.x)
	var top: float = g.world.elevation(e.x, e.y) + e.height * e.variant * .9
	_stand(g, at.x, at.y, e.x, e.y, top)
	_arm(g, Weapons.REVOLVER)
	_ticks(g, 20)
	_stand(g, at.x, at.y, e.x, e.y, top)
	await _snap("headshot_0")
	_ticks(g, 1, true)
	await _row(g, "headshot_pop", [2, 5, 10, 20, 40])


## A load of buckshot at arm's length throws a hand back through the window
## behind it, seen from the side.
func _window_throw() -> void:
	var target := _first("hickston", "billy")
	if target < 0:
		return
	var g := _level("hickston", [target])
	g.aim_assist = 0
	g.spawn_grace = 99.0
	var w := g.world
	var e: Enemy = g.enemies[target]
	for face in g.features["wall_breaks"].windows:
		var n: Vector2 = face.normal()
		var mid: Vector2 = face.middle()
		var stand := mid + n * .75
		var gun := mid + n * 2.1
		var side := mid + n * 2.6 + n.orthogonal() * 2.2
		if (
			w.blocked(stand.x, stand.y, .3)
			or w.blocked(gun.x, gun.y, .3)
			or w.blocked(side.x, side.y, .3)
			or absf(w.elevation(stand.x, stand.y)) > .05
			or w.elevation(gun.x, gun.y) != w.elevation(stand.x, stand.y)
			or not w.visible(gun.x, gun.y, stand.x, stand.y)
			or not w.visible(side.x, side.y, mid.x + n.x * .05, mid.y + n.y * .05, .95, 1.3)
			or not _clear(g, side, mid)
		):
			continue
		e.x = stand.x
		e.y = stand.y
		e.angle = n.angle()
		e.cooldown = 99.0
		_stand(g, side.x, side.y, mid.x, mid.y, 1.0)
		_ticks(g, 20)
		await _snap("window_throw_before")
		_stand(g, gun.x, gun.y, e.x, e.y, w.elevation(e.x, e.y) + .9)
		_arm(g, Weapons.SHOTGUN)
		_ticks(g, 1, true)
		_stand(g, side.x, side.y, mid.x, mid.y, 1.0)
		await _row(g, "window_throw", [3, 6, 10, 16, 30, 50])
		return


## The cow launcher at a hand down the street: it goes up whole and comes down.
func _cow_throw() -> void:
	var g := _level("hickston")
	var target := -1
	var at := Vector2.INF
	for i in g.enemies.size():
		var e: Enemy = g.enemies[i]
		if e.kind == "clone" or e.kind == "billy":
			at = _spot(g, e.x, e.y, 5.0)
			if at != Vector2.INF:
				target = i
				break
	if target < 0:
		return
	g = _level("hickston", [target])
	g.aim_assist = 0
	g.spawn_grace = 99.0
	var e: Enemy = g.enemies[target]
	e.cooldown = 99.0
	e.hp = 40.0
	_stand(g, at.x, at.y, e.x, e.y, g.world.elevation(e.x, e.y) + .7)
	_arm(g, Weapons.COW)
	_ticks(g, 20)
	_stand(g, at.x, at.y, e.x, e.y, g.world.elevation(e.x, e.y) + .7)
	_ticks(g, 1, true)
	var waited := 0
	while e.alive and waited < 90:
		_ticks(g, 1)
		waited += 1
	_stand(g, at.x, at.y, e.x, e.y, g.world.elevation(e.x, e.y) + 1.2)
	await _row(g, "cow_throw", [6, 8, 10, 12, 30])


## A hand dropped in a bayou channel floats there and bobs.
func _floating() -> void:
	var target := _first("bayou", "billy")
	if target < 0:
		return
	var g := _level("bayou", [target])
	g.spawn_grace = 99.0
	var w := g.world
	var e: Enemy = g.enemies[target]
	for cy in range(3, w.height - 3):
		for cx in range(3, w.width - 3):
			var at := Vector2(cx + .5, cy + .5)
			if not w.deep_at(at.x, at.y) or w.blocked(at.x, at.y, .3):
				continue
			var eye := Vector2.INF
			for k in 16:
				var q := at + Vector2.from_angle(k * TAU / 16.0) * 2.6
				if (
					not w.blocked(q.x, q.y, .3)
					and not w.deep_at(q.x, q.y)
					and w.visible(
						q.x, q.y, at.x, at.y, w.elevation(q.x, q.y) + .95, w.elevation(at.x, at.y)
					)
				):
					eye = q
					break
			if eye == Vector2.INF:
				continue
			e.x = at.x
			e.y = at.y
			e.hp = 5.0
			g.hit_point = Vector3(e.x, e.y, w.elevation(e.x, e.y) + .9)
			g.hit_from = eye
			e.hurt(10.0, g, false, false, null, "rifle")
			_stand(g, eye.x, eye.y, e.x, e.y, w.elevation(e.x, e.y))
			_ticks(g, 90)
			await _row(g, "float_bob", [12, 12, 12, 12, 12])
			return


## A revolver fired near the chickens: they scatter, flapping, feathers flying.
func _chickens() -> void:
	var g := _level("hickston")
	var keep: Array = []
	for i in g.enemies.size():
		if (g.enemies[i] as Enemy).kind == "chicken":
			keep.append(i)
	if keep.is_empty():
		return
	g = _level("hickston", keep)
	var hen: Enemy = g.enemies[keep[0]]
	var at := _spot(g, hen.x, hen.y, 3.2)
	if at == Vector2.INF:
		return
	_stand(g, at.x, at.y, hen.x, hen.y, g.world.elevation(hen.x, hen.y) + .3)
	_arm(g, Weapons.REVOLVER)
	_ticks(g, 20)
	_stand(g, at.x, at.y, hen.x, hen.y, g.world.elevation(hen.x, hen.y) + .3)
	g.player.angle += .25
	await _snap("chickens_0")
	_ticks(g, 1, true)
	await _row(g, "chickens_scatter", [3, 6, 10, 16, 30])
