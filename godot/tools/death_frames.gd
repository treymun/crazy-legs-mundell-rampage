## Pictures of enemies dying, close up, in a real window (the graphics-card
## view players see): for each kind of hand on a level, one is stood in the
## open in front of the player, shot down, and pictured as it falls and lies
## (<kind>_<n>.png in out=<dir>), to look for anything left hanging in the air.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/death_frames.gd -- out=<dir> [level=hickston] [gun=shotgun]
##       [classic] [places]
##
## places: buckshot at arm's length down the feed store's loft stairs and over the
## hay loft's rail instead. classic: the scripted falls (RAGDOLLS off).
## audit [rows=a,b]: tools/death_rows.gd's rows instead (a kind, a gun, where
## it struck and where it stood; one strip of ten moments a row).
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

const DeathRows := preload("res://tools/death_rows.gd")

const AFTER := [3, 8, 16, 30, 60, 120]
## Kinds `places` pictures (the first on the level), each with a ragdoll.
const HANDS := [
	"coot",
	"yard_deputy",
	"clone",
	"flagman",
	"noodler",
	"billy",
	"chain_hand",
	"pit_mechanic",
	"barker"
]
var probe := false
## The scripted falls of before the ragdolls (RAGDOLLS off).
var classic := false

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
		elif a == "classic":
			classic = true
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
	if OS.get_cmdline_user_args().has("places"):
		# Buckshot at arm's length on a loft: down the feed store's stairs,
		# over the hay loft's rail.
		await _place(
			"feedstore",
			Vector2(10.9, 4.6),
			1.7,
			Vector2(12.4, 4.6),
			Vector2(5.0, 7.5),
			0.0,
			"stairs"
		)
		await _place(
			"hickston",
			Vector2(44.0, 8.6),
			1.55,
			Vector2(44.0, 7.2),
			Vector2(41.5, 13.5),
			0.0,
			"rail"
		)
		print("death frames written to ", out)
		main.queue_free()
		await process_frame
		quit()
		return
	if OS.get_cmdline_user_args().has("audit"):
		var only := ""
		# kind=: the rows asked for with that kind instead (the Meshy models track).
		var kind := ""
		for arg in OS.get_cmdline_user_args():
			if String(arg).begins_with("rows="):
				only = String(arg).substr(5)
			elif String(arg).begins_with("kind="):
				kind = String(arg).substr(5)
		var wanted := Array(only.split(",", false))
		for row: Array in DeathRows.ROWS:
			var name: String = row[0]
			if wanted.is_empty() or wanted.any(func(w: String) -> bool: return name == w):
				var use := row.duplicate()
				if kind != "":
					use[0] = name.replace(str(row[1]), kind)
					use[1] = kind
				await DeathRows.new(self).run(use)
		print("death rows written to ", out)
		main.queue_free()
		await process_frame
		quit()
		return
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
		# A killing shot, not an overkill (that takes the body apart).
		e.hurt(e.hp + 4.0, g, false, false, null, gun)
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


## A hand at `at` on a floor `top` high shot down with buckshot fired from
## `shot`, watched by the player at `cam` on a floor `cam_top` high
## (<name>_<n>.png).
func _place(
	level_id: String,
	at: Vector2,
	top: float,
	shot: Vector2,
	cam: Vector2,
	cam_top: float,
	name: String
) -> void:
	var keep := -1
	main.start(level_id)
	for i in main.game.enemies.size():
		var one: Enemy = main.game.enemies[i]
		if one.hostile and Variants.stem(one.kind) in HANDS:
			keep = i
			break
	if keep < 0:
		print("no hand to picture on ", level_id)
		return
	var g := _level(level_id, [keep])
	g.spawn_grace = 99.0
	var e: Enemy = g.enemies[keep]
	e.x = at.x
	e.y = at.y
	e.floor_z = top
	e.angle = atan2(shot.y - at.y, shot.x - at.x)
	e.alerted = false
	g.player.floor_z = cam_top
	_stand(g, cam.x, cam.y, at.x, at.y, top + .5)
	_lift(g, cam_top, at.x, at.y, top + .5)
	_ticks(g, 2)
	e.hurt(e.hp + 4.0, g, false, false, null, "shotgun")
	e.killed_from = shot
	var n := 0
	for t: int in AFTER:
		_ticks(g, t - (0 if n == 0 else AFTER[n - 1]))
		var z: float = g.world.floor_under(e.x, e.y, g.world.stand(e) + .3) + e.toss + .2
		_stand(g, cam.x, cam.y, e.x, e.y, z)
		_lift(g, cam_top, e.x, e.y, z)
		await _snap("%s_%d" % [name, t])
		n += 1


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
	if classic:
		View.ragdolls = false
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
		# Drawn every tick, as in play (the 3D view steps its ragdolls as it draws).
		if not probe:
			main.render()


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


## The player's eye on a floor `top` high, looking at (tx, ty, tz).
func _lift(g: Game, top: float, tx: float, ty: float, tz: float) -> void:
	var p := g.player
	p.eye = top + .95
	var d := Vector2(tx - p.x, ty - p.y).length()
	p.pitch = clampf((tz - p.eye) / maxf(d, .1) * View.base_focal, -50.0, 50.0)
