## Pictures of the physics polish (track M), each a strip of frames side by
## side in one picture (<name>.png in out=<dir>), in a real window:
##   settle  brass and a burst's gibs coming down on hickston's hay loft,
##           close up, frame by frame as they land and lie (no snap flat);
##   body    a hand shot down on open ground, seen from low beside it once it
##           lies still (its limbs on the floor, not sunk into it);
##   water   a hand shot down in the bayou: the splash, then the body afloat
##           drifting on the current, brass splashing in beside it;
##   staves  the yard's hazard drums blown apart: the staves where they lie.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/physics_polish_frames.gd -- out=<dir> [only=settle]
##
## It drives the game only as play does, so the same script on an older build
## pictures the before. Point APPDATA at a scratch folder.
extends SceneTree

## Each frame of a strip is the view's middle, this many pixels each way.
const CROP := Vector2i(560, 420)

var main
var out := ""
var only := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		var a := String(arg)
		if a.begins_with("out="):
			out = a.substr(4)
		elif a.begins_with("only="):
			only = a.substr(5)
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.touring = true
	Effects.enabled = true
	if only == "" or only == "settle":
		await _settle()
	if only == "" or only == "body":
		await _body()
	if only == "" or only == "water":
		await _water()
	if only == "" or only == "staves":
		await _staves()
	print("polish frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _frame() -> Image:
	if main.game != null:
		main.game.message_until = 0.0
		main.game.barks.until = 0.0
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	var size := img.get_size()
	var view_h := int(size.y * 156.0 / 200.0)
	var at := Vector2i((size.x - CROP.x) / 2, (view_h - CROP.y) / 2)
	return img.get_region(Rect2i(at, CROP))


## Frames after each count of ticks in `gaps` (the first now), side by side.
func _strip(g: Game, name: String, gaps: Array, aim := Callable()) -> void:
	var frames: Array[Image] = []
	for k in gaps.size():
		_ticks(g, int(gaps[k]))
		if aim.is_valid():
			aim.call()
		frames.append(await _frame())
	var sheet := Image.create(CROP.x * frames.size(), CROP.y, false, frames[0].get_format())
	for k in frames.size():
		sheet.blit_rect(frames[k], Rect2i(Vector2i.ZERO, CROP), Vector2i(CROP.x * k, 0))
	sheet.save_png(out.path_join(name + ".png"))


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
	g.spawn_grace = 99.0
	return g


func _stand(g: Game, x: float, y: float, eye: float, tx: float, ty: float, tz: float) -> void:
	var p := g.player
	p.x = x
	p.y = y
	p.angle = atan2(ty - y, tx - x)
	p.eye = eye
	var d := Vector2(tx - x, ty - y).length()
	p.pitch = clampf((tz - p.eye) / maxf(d, .1) * View.base_focal, -50.0, 50.0)
	p.vx = 0.0
	p.vy = 0.0


func _ticks(g: Game, n: int) -> void:
	var held := Game.Controls.new()
	for _i in n:
		g.tick(1.0 / 60.0, held)


## Brass and gibs coming down on the hay loft, close up.
func _settle() -> void:
	var g := _level("hickston")
	var loft: LevelGeometry.Slab = null
	for s: LevelGeometry.Slab in g.world.geo.slabs:
		if s.id == "hay_loft":
			loft = s
	if loft == null:
		return
	var top := loft.top
	var mark := Vector2(loft.x0 + 2.4, loft.y0 + 3.4)
	var at := mark + Vector2(1.5, .9)
	var p := g.player
	p.floor_z = top
	var aim := func() -> void: _stand(g, at.x, at.y, top + .8, mark.x, mark.y, top)
	aim.call()
	_ticks(g, 4)
	var e: Enemy = null
	for one: Enemy in g.enemies:
		if one.hostile and not Enemy.BOSS_TITLES.has(one.kind) and not HitZones.METAL.has(one.kind):
			e = one
			break
	e.x = mark.x
	e.y = mark.y
	e.floor_z = top
	g.gore_fx.burst(e)
	e.x = 1.5
	e.y = 1.5
	p.x = mark.x + .3
	p.y = mark.y - .3
	p.eye = top + .95
	for _k in 2:
		g.events.gun_reloading.emit(Weapons.REVOLVER)
	aim.call()
	await _strip(g, "settle", [14, 4, 4, 4, 6, 10, 90], aim)


## A hand shot down on open ground, seen from low beside it at rest.
func _body() -> void:
	var g := _level("hickston")
	var pick := -1
	for i in g.enemies.size():
		var one: Enemy = g.enemies[i]
		if one.hostile and one.brain == "billy":
			pick = i
			break
	if pick < 0:
		return
	g = _level("hickston", [pick])
	var e: Enemy = g.enemies[pick]
	var spot := _open(g, e.x, e.y)
	if spot == Vector2.INF:
		return
	e.x = spot.x
	e.y = spot.y
	var ground := g.world.elevation(spot.x, spot.y)
	_stand(g, spot.x - 2.0, spot.y, ground + .95, spot.x, spot.y, ground + .5)
	_ticks(g, 10)
	g.hit_point = Vector3(e.x, e.y, ground + .9)
	g.hit_from = Vector2(spot.x - 2.0, spot.y)
	for _k in 6:
		if e.alive:
			e.hurt(e.hp + 4.0, g, false, false, null, "shotgun")
	_ticks(g, 240)
	var side := Vector2(e.x, e.y) + Vector2(.5, 1.9)
	for k in 16:
		var q := Vector2(e.x, e.y) + Vector2.from_angle(k * TAU / 16.0) * 1.9
		if (
			not g.world.blocked(q.x, q.y, .5)
			and g.world.visible(q.x, q.y, e.x, e.y, ground + .55, ground + .1)
		):
			side = q
			break
	var aim := func() -> void: _stand(g, side.x, side.y, ground + .55, e.x, e.y, ground + .05)
	aim.call()
	await _strip(g, "body", [1], aim)


## A hand shot down in the bayou's water: the splash, then afloat, drifting.
func _water() -> void:
	var g := _level("bayou")
	var w := g.world
	var pick := -1
	for i in g.enemies.size():
		var one: Enemy = g.enemies[i]
		if one.hostile and not Enemy.BOSS_TITLES.has(one.kind) and one.brain != "gator":
			pick = i
			break
	g = _level("bayou", [pick])
	var e: Enemy = g.enemies[pick]
	for cy in range(3, w.height - 3):
		for cx in range(3, w.width - 3):
			var at := Vector2(cx + .5, cy + .5)
			if (
				not w.deep_at(at.x, at.y)
				or not w.deep_at(at.x + 1.0, at.y)
				or w.blocked(at.x, at.y, .3)
			):
				continue
			var eye := Vector2.INF
			for k in 16:
				var q := at + Vector2.from_angle(k * TAU / 16.0) * 2.8
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
			var surface := w.elevation(at.x, at.y)
			var aim := func() -> void:
				_stand(g, eye.x, eye.y, w.elevation(eye.x, eye.y) + .95, e.x, e.y, surface + .1)
			aim.call()
			_ticks(g, 10)
			g.hit_point = Vector3(e.x, e.y, surface + .9)
			g.hit_from = eye
			e.hurt(e.hp + 4.0, g, false, false, null, "shotgun")
			var p := g.player
			var keep := Vector3(p.x, p.y, p.eye)
			p.x = at.x + .4
			p.y = at.y + .3
			p.eye = surface + .95
			g.events.gun_reloading.emit(Weapons.REVOLVER)
			p.x = keep.x
			p.y = keep.y
			p.eye = keep.z
			await _strip(g, "water", [4, 8, 30, 240, 600], aim)
			return


## The yard's hazard drums blown apart: where the staves lie.
func _staves() -> void:
	var g := _level("hickston")
	var drums: Array = []
	for b: LevelData.Billboard in g.world.billboards:
		if b.image == "town_warning_barrel" or b.image == "town_mash_barrel":
			drums.append(Vector2(b.x, b.y))
	for d: Vector2 in drums:
		var spot := _open(g, d.x, d.y, 4.5)
		if spot == Vector2.INF:
			continue
		var ground := g.world.elevation(d.x, d.y)
		var aim := func() -> void: _stand(g, spot.x, spot.y, ground + 1.9, d.x, d.y, ground)
		aim.call()
		_ticks(g, 10)
		g.explode(Game.Shot.new(d.x + .3, d.y + .2, ground + .2, 0, 0, 0, "tnt"))
		await _strip(g, "staves", [30, 420], aim)
		return


## A spot `far` from (x, y) with open floor at its height round it that sees it.
func _open(g: Game, x: float, y: float, far := 0.0) -> Vector2:
	var w := g.world
	for r in range(0, 12):
		for k in 16:
			var at := Vector2(x, y) + Vector2.from_angle(k * TAU / 16.0) * (far + r * .5)
			if at.x < 2.0 or at.y < 2.0 or at.x > w.width - 2 or at.y > w.height - 2:
				continue
			if w.blocked(at.x, at.y, .9) or w.geo != null and not w.geo.clear_at(at.x, at.y):
				continue
			if absf(w.elevation(at.x, at.y) - w.elevation(x, y)) > .05:
				continue
			if (
				far > 0.0
				and not w.visible(at.x, at.y, x, y, w.elevation(x, y) + .9, w.elevation(x, y) + .2)
			):
				continue
			if not _clear(g, at, Vector2(x, y)):
				continue
			return at
	return Vector2.INF


## Nothing standing between a and b (or beside a) to hide the view.
func _clear(g: Game, a: Vector2, b: Vector2) -> bool:
	var things: Array = []
	for s: View.Sprite in g.props:
		things.append(Vector2(s.x, s.y))
	for board: LevelData.Billboard in g.world.billboards:
		things.append(Vector2(board.x, board.y))
	for q: Vector2 in things:
		var on := Geometry2D.get_closest_point_to_segment(q, a, b)
		if on.distance_to(q) < .6 and q.distance_to(b) > .8:
			return false
	return true
