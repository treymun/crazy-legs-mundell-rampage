## Pictures of the weather you can feel, County Run's storm front and the
## critters, in a real window (the graphics-card view players see):
##   puddles_<0|1>     hickston's orchard early in its storm and after hours of it
##   prints_0          boot prints walked across the muddy orchard, looked back on
##   sway_<0..2>       the wind swinging hickston's laundry in a gust
##   storm_<0..3>      a County Run's storm front: the stage called, the wall
##                     closing in, from inside the ring and from out in it
##   chicken_<0..3>    a chicken flapping off on a glide
##   cow_<0..3>        a cow tipped over and lying
##   mule_<0|1>        the mule's kick
##   knocked_0         bowled over by a hog: the view from the ground
## Each lands in out=<dir> as <name>.png.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/climate_frames.gd -- out=<dir>
##
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
	await _puddles()
	await _prints()
	await _sway()
	await _critters()
	await _storm()
	print("climate frames written to ", out)
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


## A level with every hand asleep (the animals awake), the player unhurt.
func _level(level_id: String) -> Game:
	main.start(level_id)
	var g: Game = main.game
	g.cheats.god = true
	g.lessons = false
	g.barks.enabled = false
	for e: Enemy in g.enemies:
		if e.hostile:
			e.dormant = true
	g.message_until = 0.0
	g.district_until = 0.0
	g.spawn_grace = 99.0
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


func _ticks(g: Game, n: int, held: Game.Controls = null) -> void:
	var c := held if held != null else Game.Controls.new()
	for i in n:
		g.tick(1.0 / 60.0, c)


func _first(g: Game, brain: String) -> Enemy:
	for e: Enemy in g.enemies:
		if e.brain == brain and e.alive:
			return e
	return null


func _puddles() -> void:
	for k in 2:
		var g := _level("hickston")
		var weather = g.features["weather"]
		weather.hold(.85, .85, 0.0, .2 if k == 0 else 1.0)
		_stand(g, 7.5, 69.5, 17.5, 70.0, 0.0)
		_ticks(g, 2)
		_stand(g, 7.5, 69.5, 17.5, 70.0, 0.0)
		await _snap("puddles_%d" % k)


func _prints() -> void:
	var g := _level("hickston")
	for e: Enemy in g.enemies:
		e.dormant = true
	var held := Game.Controls.new()
	held.forward = 1.0
	_stand(g, 10.5, 12.5, 22.0, 13.0, .5)
	_ticks(g, 75, held)
	held.forward = 0.0
	_ticks(g, 10, held)
	var p := g.player
	var middle := Vector2((10.5 + p.x) * .5, (12.5 + p.y) * .5)
	_stand(g, middle.x - 1.2, middle.y + 2.2, middle.x, middle.y, 0.0)
	_ticks(g, 2)
	_stand(g, middle.x - 1.2, middle.y + 2.2, middle.x, middle.y, 0.0)
	g.district_until = 0.0
	await _snap("prints_0")


func _sway() -> void:
	var g := _level("hickston")
	var laundry: LevelData.Billboard = null
	for b: LevelData.Billboard in g.world.billboards:
		if b.image == "town_laundry":
			laundry = b
			break
	if laundry == null:
		return
	var weather = g.features["weather"]
	var at := Vector2.INF
	for k in 16:
		var d := Vector2.from_angle(k * TAU / 16.0) * 4.6
		var spot := Vector2(laundry.x, laundry.y) + d
		if (
			not g.world.blocked(spot.x, spot.y, .3)
			and g.world.visible(spot.x, spot.y, laundry.x, laundry.y, 1.0, 1.0)
			and _open_line(g, spot, Vector2(laundry.x, laundry.y), laundry)
		):
			at = spot
			break
	if at == Vector2.INF:
		return
	for k in 3:
		weather.hold(.6, .6, 0.0, .4, Vector2(.9, .3) * (1.0 + k * .6))
		_stand(g, at.x, at.y, laundry.x, laundry.y, g.world.elevation(laundry.x, laundry.y) + .8)
		_ticks(g, 12)
		_stand(g, at.x, at.y, laundry.x, laundry.y, g.world.elevation(laundry.x, laundry.y) + .8)
		await _snap("sway_%d" % k)


## No prop stands between a and b (but `own`) to hide the view.
func _open_line(g: Game, a: Vector2, b: Vector2, own: LevelData.Billboard) -> bool:
	for board: LevelData.Billboard in g.world.billboards:
		if board == own:
			continue
		var at := Vector2(board.x, board.y)
		var t := clampf((at - a).dot(b - a) / maxf((b - a).length_squared(), .01), 0.0, 1.0)
		if at.distance_to(a.lerp(b, t)) < .9:
			return false
	return true


## A run on hickston's map with the storm's first stage closing in.
func _storm() -> void:
	main.start_county("county_hickston")
	var g: Game = main.game
	_ticks(g, 2)
	var f = g.features["county"]
	f.next_spawn = 1e9
	f.next_elite = 1e9
	f.next_lull = 1e9
	Modes.clear_enemies(g)
	g.cheats.god = true
	f.storm_next = f.run_time + 20.0
	_ticks(g, 60)
	g.player.x = f.storm_at.x + 4.0
	g.player.y = f.storm_at.y
	await _snap("storm_0")
	_ticks(g, 60 * 34)
	# From inside the ring, looking out at the wall.
	var spots: Array = CountySpawner.spots(g)
	var inside := Vector2.INF
	var outside := Vector2.INF
	for s: Vector2 in spots:
		var d := s.distance_to(f.storm_at)
		var out_at: Vector2 = f.storm_at + (s - f.storm_at).normalized() * (f.storm_r + 3.0)
		if (
			inside == Vector2.INF
			and absf(d - (f.storm_r - 6.0)) < .5
			and g.world.visible(s.x, s.y, out_at.x, out_at.y, 1.0, 1.0)
		):
			inside = s
		var in_at: Vector2 = f.storm_at + (s - f.storm_at).normalized() * (f.storm_r - 3.0)
		if (
			outside == Vector2.INF
			and absf(d - (f.storm_r + 3.0)) < .5
			and g.world.visible(s.x, s.y, in_at.x, in_at.y, 1.0, 1.0)
		):
			outside = s
	if inside != Vector2.INF:
		var toward: Vector2 = f.storm_at + (inside - f.storm_at).normalized() * (f.storm_r + 4.0)
		_stand(g, inside.x, inside.y, toward.x, toward.y, 1.6)
		_ticks(g, 2)
		_stand(g, inside.x, inside.y, toward.x, toward.y, 1.6)
		await _snap("storm_1")
	f.storm_next = f.run_time + .1
	_ticks(g, 60 * 8)
	if outside != Vector2.INF:
		_stand(g, outside.x, outside.y, f.storm_at.x, f.storm_at.y, 1.2)
		_ticks(g, 2)
		_stand(g, outside.x, outside.y, f.storm_at.x, f.storm_at.y, 1.2)
		await _snap("storm_2")
	g.map = true
	await _snap("storm_3")
	g.map = false


func _critters() -> void:
	# A chicken flapping off on a glide, seen from the side.
	var g := _level("hickston")
	var crit = g.features["critters"]
	var hen := _first(g, "chicken")
	if hen != null:
		_stand(g, hen.x - .2, hen.y + 3.4, hen.x + .8, hen.y, g.world.elevation(hen.x, hen.y) + .5)
		_ticks(g, 2)
		_stand(g, hen.x - .2, hen.y + 3.4, hen.x + .8, hen.y, g.world.elevation(hen.x, hen.y) + .5)
		var p: Player = g.player
		crit.scatter(hen.x - 1.0, hen.y, 3.0, p)
		for k in 4:
			_ticks(g, 6)
			await _snap("chicken_%d" % k)
	# A cow tipped over.
	g = _level("hickston")
	crit = g.features["critters"]
	var cow := _first(g, "cow")
	if cow != null:
		cow.angle = 0.0
		cow.face_left = false
		var p: Player = g.player
		p.x = cow.x
		p.y = cow.y + 1.0
		crit.tip(p)
		var view := Vector2(cow.x - .3, cow.y + 3.6)
		for k in 4:
			_stand(g, view.x, view.y, cow.x, cow.y, g.world.elevation(cow.x, cow.y) + .5)
			_ticks(g, [1, 14, 30, 60][k])
			_stand(g, view.x, view.y, cow.x, cow.y, g.world.elevation(cow.x, cow.y) + .5)
			await _snap("cow_%d" % k)
	# The mule's kick, from its side.
	g = _level("hickston")
	crit = g.features["critters"]
	var mule := _first(g, "mule")
	if mule != null:
		mule.angle = 0.0
		mule.face_left = false
		var view := Vector2(mule.x + .2, mule.y + 3.8)
		_stand(g, view.x, view.y, mule.x, mule.y, g.world.elevation(mule.x, mule.y) + .7)
		_ticks(g, 2)
		_stand(g, view.x, view.y, mule.x, mule.y, g.world.elevation(mule.x, mule.y) + .7)
		await _snap("mule_0")
		mule.held_cel = "mule_kick"
		_ticks(g, 1)
		mule.held_cel = "mule_kick"
		_stand(g, view.x, view.y, mule.x, mule.y, g.world.elevation(mule.x, mule.y) + .7)
		await _snap("mule_1")
	# Bowled over by a hog: the view from the ground.
	g = _level("hickston")
	crit = g.features["critters"]
	var hog := _first(g, "pig")
	if hog != null:
		var p: Player = g.player
		p.x = hog.x + 1.6
		p.y = hog.y
		p.angle = PI
		crit.charge(hog, p)
		for i in 120:
			_ticks(g, 1)
			if p.knocked > 0.0:
				break
		_ticks(g, 8)
		await _snap("knocked_0")
