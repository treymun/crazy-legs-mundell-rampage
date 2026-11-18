## Pictures of how broken things' pieces move and lie, in a real window (the
## graphics-card view players see): hickston's yard barrel and a crate shot
## apart, moonshine's mash barrel shot apart (its staves, lids and hoops), a
## cluster of crates and barrels broken at once and the heap they leave, a
## blast among pieces lying about, and the player walking through them.
## Each scene is a row of frames, <scene>_<n>.png, in out=<dir>.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/wreck_motion_frames.gd -- out=<dir> [only=mash,heap]
##
## It drives the game only the way play does (aim, fire, a blast where a
## stick would land, walking), so the same script on an older build shows the
## before. Point APPDATA at a scratch folder: it runs the game with the
## profile there.
extends SceneTree

const DT := 1.0 / 60.0

var main
var out := ""
## bare: what is left standing where a thing broke is not drawn (to judge
## the pieces alone).
var bare := false
## The set pieces' feature kept out of the game's list for the heap.
var _sets: Variant = null


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var only: Array = []
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
		elif String(arg) == "bare":
			bare = true
		elif String(arg).begins_with("only="):
			only = Array(String(arg).substr(5).split(",", false))
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
	if only.is_empty() or only.has("barrel"):
		await _shot(["hickston"], "prop_barrel", "barrel", 2.2)
	if only.is_empty() or only.has("crate"):
		await _shot(["hickston", "county_hickston"], "prop_crate", "crate", 2.2)
	if only.is_empty() or only.has("mash"):
		await _shot(["bayou", "moonshine", "county_bayou"], "town_mash_barrel", "mash", 2.4)
	if only.is_empty() or only.has("heap"):
		await _heap()
	if only.is_empty() or only.has("toys"):
		await _toys()
	print("wreck motion frames written to ", out)
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
		g.tick(DT, held)
		if bare:
			for p in g.features["breakables"].pieces:
				if p.broken:
					if p.sprite != null:
						p.sprite.height = 0.0
					if p.board != null:
						p.board.height = 0.0


## A spot `far` from (x, y) on open floor at its height that sees it.
func _spot(g: Game, x: float, y: float, far: float) -> Vector2:
	var w := g.world
	for k in 24:
		var at := Vector2(x, y) + Vector2.from_angle(k * TAU / 24.0) * far
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


## Nothing standing between a and b to hide the view (a post, a crate).
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


## The first breakable of `image` with open floor round it: [x, y] or [].
func _find(g: Game, image: String) -> Array:
	var breaks = g.features["breakables"]
	for p in breaks.pieces:
		if p.image != image or p.broken or not _yard(g, p.x, p.y):
			continue
		var at := _spot(g, p.x, p.y, 2.2)
		if at != Vector2.INF:
			return [p.x, p.y, at]
	return []


## Whether (x, y) stands out in a yard: no wall within two cells, no roof.
func _yard(g: Game, x: float, y: float) -> bool:
	var w := g.world
	for cy in range(int(y) - 2, int(y) + 3):
		for cx in range(int(x) - 2, int(x) + 3):
			if cx < 0 or cy < 0 or cx >= w.width or cy >= w.height:
				return false
			if w.solid[cy * w.width + cx] >= 0 or w.roof[cy * w.width + cx] > 0.0:
				return false
	return true


## One thing shot with the sawed-off from `far`, frames as its pieces fly,
## land and lie, then a close look at where they lie.
func _shot(levels: Array, image: String, name: String, far: float) -> void:
	var g: Game = null
	var found := []
	for level_id: String in levels:
		g = _level(level_id)
		found = _find(g, image)
		if not found.is_empty():
			break
	if found.is_empty():
		print("no ", image, " in a yard on ", levels)
		return
	var x: float = found[0]
	var y: float = found[1]
	var at := _spot(g, x, y, far)
	var floor_z := g.world.elevation(x, y)
	_stand(g, at.x, at.y, x, y, floor_z + .5)
	_arm(g, Weapons.SHOTGUN)
	_ticks(g, 20)
	await _snap("%s_0" % name)
	_ticks(g, 1, true)
	# The gun put away: nothing hides the pieces.
	g.armory.holstered = true
	var k := 1
	for gap: int in [3, 6, 12, 30, 90, 240]:
		_ticks(g, gap)
		await _snap("%s_%d" % [name, k])
		k += 1
	# Where they lie, looked down at from a little nearer.
	var near := Vector2(x, y) + (at - Vector2(x, y)).normalized() * 1.5
	_stand(g, near.x, near.y, x, y, floor_z)
	_ticks(g, 1)
	await _snap("%s_rest" % name)


## A cluster of hickston's breakables broken at once (as stress_bench's
## wreck48), the heap they leave, a blast among them, the player walking
## through what is left.
func _heap() -> void:
	var g := _level("hickston")
	# No barn brought down by the blast (set_piece_frames pictures those).
	_sets = g.features.get("set_pieces")
	g.features.erase("set_pieces")
	var breaks = g.features["breakables"]
	var can: Array = []
	for i in breaks.pieces.size():
		var bp = breaks.pieces[i]
		if (
			not bp.broken
			and str(bp.spec.get("pieces", "")) != ""
			and not bp.spec.has("blast")
			and str(bp.spec.get("stuff", "")) != "straw"
		):
			can.append(i)
	var best := Vector2.ZERO
	var most := -1
	for i: int in can:
		var p0 := Vector2(breaks.pieces[i].x, breaks.pieces[i].y)
		var n := 0
		for j: int in can:
			if p0.distance_to(Vector2(breaks.pieces[j].x, breaks.pieces[j].y)) < 4.0:
				n += 1
		if n > most:
			most = n
			best = p0
	var at := _spot(g, best.x, best.y, 4.5)
	if at == Vector2.INF:
		return
	var floor_z := g.world.elevation(best.x, best.y)
	_stand(g, at.x, at.y, best.x, best.y, floor_z + .3)
	g.armory.holstered = true
	_ticks(g, 10)
	await _snap("heap_0")
	var struck := 0
	for i: int in can:
		var bp = breaks.pieces[i]
		if bp.broken or Vector2(bp.x, bp.y).distance_to(best) > 4.0 or struck >= 8:
			continue
		var away := Vector2(bp.x - at.x, bp.y - at.y).normalized()
		breaks.strike(i, 9999.0, away.x, away.y)
		struck += 1
	var k := 1
	for gap: int in [4, 12, 40, 240]:
		_ticks(g, gap)
		await _snap("heap_%d" % k)
		k += 1
	# A stick of dynamite's blast among the pieces.
	var boom := best + (at - best).normalized() * .8
	g.explode(Game.Shot.new(boom.x, boom.y, g.world.elevation(boom.x, boom.y) + .2, 0, 0, 0, "tnt"))
	for gap: int in [4, 12, 60, 240]:
		_ticks(g, gap)
		await _snap("heap_%d" % k)
		k += 1
	# Walking through what is left.
	var p := g.player
	var to := best + (best - at).normalized() * 1.5
	for t in 90:
		var step := (to - Vector2(p.x, p.y)).limit_length(3.0 * DT)
		p.x += step.x
		p.y += step.y
		p.vx = step.x / DT
		p.vy = step.y / DT
		_ticks(g, 1)
		if t == 45:
			await _snap("heap_%d" % k)
			k += 1
	_ticks(g, 120)
	_stand(g, at.x, at.y, best.x, best.y, floor_z + .3)
	_ticks(g, 1)
	await _snap("heap_%d" % k)


## The open ground nearest the start on hickston (plain cells all round).
func _open(g: Game) -> Vector2:
	var w := g.world
	var from := Vector2(g.player.x, g.player.y)
	var best := from
	var near := INF
	for cy in range(3, w.height - 3):
		for cx in range(3, w.width - 3):
			var c := Vector2(cx + .5, cy + .5)
			var d := c.distance_squared_to(from)
			if d < near and not is_nan(PhysCore.plain_under(w, Vector3(c.x, c.y, 0.0), 2.5)):
				near = d
				best = c
	return best


## Moonshine's mash barrel's own pieces (its staves, lids and iron hoops)
## shot apart on hickston's open ground in daylight, struck on its left by a
## load of buckshot; a blast among them; the player walking through.
func _toys() -> void:
	var g := _level("hickston")
	var at := _open(g)
	var ground := Tumble.floor_at(g.world, at.x, at.y, 99.0)
	var eye := at + Vector2(-2.6, -1.2)
	_stand(g, eye.x, eye.y, at.x, at.y, ground + .3)
	g.armory.holstered = true
	_ticks(g, 10)
	var wreck = g.features["wreckage"]
	var key := "m:mash_barrel|staves:8,-0.02,-0.02,0.48"
	var src := {
		"key": key,
		"origin": Vector3(at.x, at.y, ground),
		"basis": Basis.IDENTITY,
		"size": wreck._models.scale_of("mash_barrel", 1.1),
	}
	var knock := Vector3(at.x - eye.x, at.y - eye.y, 0.0).normalized()
	knock.z = 1.0
	if wreck.has_method("_hits_for"):
		# A load of buckshot on its left side, chest high.
		var side := Vector2(-knock.y, knock.x)
		for k in 6:
			var end := Vector3(at.x + side.x * .3, at.y + side.y * .3, ground + .45 + .08 * k)
			wreck._traced(end, "thing")
		var hits: Array = wreck._hits_for(Vector3(at.x, at.y, ground), .5, 1.1, knock)
		wreck._throw(src, knock, 1.0, 99, "", [], "wood", hits)
	else:
		wreck._throw(src, knock, 1.0, 99, "debris_settle", [])
	await _snap("toys_0")
	var k := 1
	for gap: int in [4, 10, 20, 40, 120]:
		_ticks(g, gap)
		await _snap("toys_%d" % k)
		k += 1
	var boom := at + Vector2(.6, .9)
	g.explode(Game.Shot.new(boom.x, boom.y, ground + .2, 0, 0, 0, "tnt"))
	for gap: int in [6, 20, 120]:
		_ticks(g, gap)
		await _snap("toys_%d" % k)
		k += 1
