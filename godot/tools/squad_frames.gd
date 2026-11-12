## Pictures of the county's squads, idle life and variants in a real window
## (the graphics-card view players see): locals busy at their activities
## (each kind of activity once, from across the thing they face), a squad on
## HOG WILD hunting the player round a building with the console's map over
## it (flankers' paths), a shield deputy behind his door and with it swung
## aside to fire, and every chapter's tough guy. <name>.png in out=<dir>.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/squad_frames.gd -- out=<dir>
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

const CHAPTERS := ["hickston", "fair", "sawmill", "quarry", "bayou", "speedway", "mothership"]

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
	await _activities()
	await _squad()
	await _deputy()
	await _toughs()
	print("squad frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _game(level_id: String, difficulty: int) -> Game:
	var g: Game = main.make_game(level_id)
	main.game = g
	main.state = "play"
	var options: Dictionary = SessionStore.defaults()
	options["difficulty"] = difficulty
	g.configure(options)
	g.cheats.god = true
	g.barks.enabled = false
	g.armory.holstered = true
	g.armory.lower = 1.0
	return g


func _snap(name: String) -> void:
	var g: Game = main.game
	g.message_until = 0.0
	g.barks.until = 0.0
	g.callout_until = 0.0
	g.district_until = 0.0
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


func _ticks(g: Game, n: int) -> void:
	var held := Game.Controls.new()
	for i in n:
		g.tick(1.0 / 60.0, held)


## Stand at `at` looking at (tx, ty) at height tz.
func _stand(g: Game, at: Vector2, tx: float, ty: float, tz: float) -> void:
	var p := g.player
	p.x = at.x
	p.y = at.y
	p.angle = atan2(ty - at.y, tx - at.x)
	p.eye = .95 + g.world.elevation(at.x, at.y)
	var d := Vector2(tx - at.x, ty - at.y).length()
	p.pitch = clampf((tz - p.eye) / maxf(d, .1) * Renderer.base_focal, -50.0, 50.0)
	p.vx = 0.0
	p.vy = 0.0


## A spot `reach` from (x, y) toward `a` (or round from it) a body fits and
## that sees (x, y).
func _spot_near(g: Game, x: float, y: float, a: float, reach: float) -> Vector2:
	for r: float in [reach, reach * .75, reach * .55]:
		for k in 18:
			var b := a + (k / 2) * .35 * (1.0 if k % 2 == 0 else -1.0)
			var at := Vector2(x + cos(b) * r, y + sin(b) * r)
			var eye := g.world.elevation(at.x, at.y) + .95
			var mid := g.world.elevation(x, y) + .9
			if (
				not g.world.blocked(at.x, at.y, .3)
				and g.world.visible(at.x, at.y, x, y, eye, mid)
				and g.world.roof[g.world.cell(at.x, at.y)] == g.world.roof[g.world.cell(x, y)]
			):
				return at
	return Vector2(x + cos(a) * reach, y + sin(a) * reach)


## One local at each kind of activity, from across the thing he faces (they
## do not notice: the start's grace is held on).
func _activities() -> void:
	var shown := {}
	for level_id: String in CHAPTERS:
		var g := _game(level_id, 1)
		_ticks(g, 2)
		for e: Enemy in g.enemies:
			var m = e.mind
			if m == null or m.activity == "" or shown.has(m.activity) or e.alerted:
				continue
			shown[m.activity] = true
			var away: float = (m.focus - m.spot).angle()
			var at := _spot_near(g, e.x, e.y, away, 3.2)
			g.spawn_grace = 99.0
			_stand(g, at, e.x, e.y, g.world.elevation(e.x, e.y) + e.height * .6)
			for frame in 2:
				_ticks(g, 50 + frame * 35)
				g.spawn_grace = 99.0
				_stand(g, at, e.x, e.y, g.world.elevation(e.x, e.y) + e.height * .6)
				await _snap("activity_%s_%s_%d" % [m.activity, level_id, frame])
			if shown.size() >= 10:
				return


## HOG WILD: the player behind a corner, three hands after them; the map
## overlay shows who goes wide.
func _squad() -> void:
	var g := _game("hickston", 3)
	_ticks(g, 2)
	var p := g.player
	var hands: Array = []
	for e: Enemy in g.enemies:
		if e.mind != null and e.alive and not e.dormant and e.brain == "billy":
			hands.append(e)
		if hands.size() == 3:
			break
	var at := Vector2(p.x + 10.0, p.y)
	for k in hands.size():
		var e: Enemy = hands[k]
		var spot := _spot_near(g, p.x, p.y, (k - 1) * .5, 8.0 + k)
		e.x = spot.x
		e.y = spot.y
		e.alerted = true
		e.target = [p.x, p.y]
		e.hunt_until = g.clock + 9.0
	at = Vector2(hands[0].x, hands[0].y)
	if main.console != null:
		main.console.show_map = true
	for shot in 4:
		_ticks(g, 90)
		_stand(g, Vector2(p.x, p.y), hands[0].x, hands[0].y, p.eye)
		await _snap("squad_hogwild_%d" % shot)
	if main.console != null:
		main.console.show_map = false


## A shield deputy on the range: door square on, then swung aside to fire.
func _deputy() -> void:
	var g := _game("range", 1)
	_ticks(g, 2)
	g.enemies.clear()
	var p := g.player
	var at := Vector2(p.x + cos(p.angle) * 4.0, p.y + sin(p.angle) * 4.0)
	var d := Enemy.new("shield_deputy", at.x, at.y, p.angle + PI)
	d.cooldown = 99.0
	g.enemies.append(d)
	_stand(g, Vector2(p.x, p.y), d.x, d.y, g.world.elevation(d.x, d.y) + 1.0)
	_ticks(g, 1)
	await _snap("shield_deputy_door")
	d.angle = p.angle + PI + .6
	_ticks(g, 1)
	await _snap("shield_deputy_door_quarter")
	d.angle = p.angle + PI
	d.windup = .5
	d.aim_mark = [p.x, p.y, p.eye]
	await _snap("shield_deputy_aside")
	d.windup = 0.0
	d.aim_mark = null
	for kind: String in ["big_billy", "drunk_coot"]:
		g.enemies.clear()
		var v := Enemy.new(kind, at.x, at.y, p.angle + PI)
		v.cooldown = 99.0
		g.enemies.append(v)
		var plain := Enemy.new(String(Enemy.DEFS[kind]["swap"]), at.x + .9, at.y + .9, p.angle + PI)
		plain.cooldown = 99.0
		g.enemies.append(plain)
		_ticks(g, 1)
		await _snap("variant_%s" % kind)


## Each chapter's tough guy where he stands, from a few cells off.
func _toughs() -> void:
	for level_id: String in CHAPTERS:
		var g := _game(level_id, 1)
		_ticks(g, 2)
		for e: Enemy in g.enemies:
			if not Enemy.DEFS[e.kind].has("tough_for"):
				continue
			g.spawn_grace = 99.0
			var at := _spot_near(g, e.x, e.y, e.angle, 3.4)
			_stand(g, at, e.x, e.y, g.world.elevation(e.x, e.y) + e.height * .55)
			_ticks(g, 1)
			_stand(g, at, e.x, e.y, g.world.elevation(e.x, e.y) + e.height * .55)
			await _snap("tough_%s" % e.kind)
			break
