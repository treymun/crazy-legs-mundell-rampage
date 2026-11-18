## Pictures of breakable props coming apart (features/wreckage.gd), in a real
## window: each kind shot the way play shoots it (a revolver round, a load of
## buckshot at a few paces), fired until it breaks, then frames as it flies
## and lies. Each row is <shot>_<n>.png in out=<dir> (half the window's
## size): _0 before, then 2, 6, 15, 45 and 150 ticks after the break, and
## _close from a pace and a half off looking down at what lies about.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/break_frames.gd -- out=<dir> [only=barrel_gun,jugs]
##
## It drives the game only the way play does (stand, aim, fire), so the same
## script on an older build shows the before. Two shots of the same kind the
## same way (`barrel_gun`, `barrel_again`) show whether breaks differ.
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

## [name, level, picture, gun, paces off, aim up its height (share)]
const SHOTS := [
	["barrel_gun", "hickston", "prop_barrel", Weapons.SHOTGUN, 2.4, .5],
	["barrel_again", "hickston", "prop_barrel", Weapons.SHOTGUN, 2.4, .5],
	["barrel_pistol", "hickston", "prop_barrel", Weapons.REVOLVER, 3.0, .7],
	["crate", "hickston", "prop_crate", Weapons.SHOTGUN, 2.4, .5],
	["hay", "hickston", "town_range_hay_bale", Weapons.SHOTGUN, 2.6, .5],
	["mailbox", "hickston", "town_mailbox_row", Weapons.SHOTGUN, 2.6, .7],
	["table", "hickston", "town_picnic_table", Weapons.SHOTGUN, 2.6, .6],
	["outhouse", "hickston", "town_outhouse", Weapons.SHOTGUN, 3.2, .5],
	["sign", "hickston", "wanted_poster", Weapons.REVOLVER, 2.6, .5],
	["propane", "hickston", "town_propane_tank", Weapons.REVOLVER, 4.5, .5],
	["mash", "quarry", "town_mash_barrel", Weapons.SHOTGUN, 2.8, .5],
	["jugs", "quarry", "town_jug_stack", Weapons.REVOLVER, 2.6, .6],
	["tnt", "quarry", "town_tnt_crate", Weapons.REVOLVER, 5.0, .5],
	["cooler", "speedway", "town_cooler", Weapons.SHOTGUN, 2.4, .5],
	["jar", "mothership", "town_specimen_jar", Weapons.REVOLVER, 2.6, .6],
	["tube", "mothership", "town_cow_tube", Weapons.SHOTGUN, 3.2, .4],
	["ammo", "range", "town_range_ammo_crate", Weapons.SHOTGUN, 2.4, .5],
]
const AFTER := [2, 4, 9, 30, 105]

var main
var out := ""
## The pieces of a picture already pictured (barrel_again takes another).
var _used := {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var only: Array = []
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
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
	for row: Array in SHOTS:
		if only.is_empty() or only.has(row[0]):
			await _shot(row)
	print("break frames written to ", out)
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
	var image: Image = root.get_texture().get_image()
	image.resize(image.get_width() / 2, image.get_height() / 2, Image.INTERPOLATE_NEAREST)
	image.save_png(out.path_join(name + ".png"))


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


## A spot `far` from (x, y) on open floor at its height, that sees it.
func _spot(g: Game, x: float, y: float, far: float) -> Vector2:
	var w := g.world
	for k in 24:
		var at := Vector2(x, y) + Vector2.from_angle(k * TAU / 24.0 + .2) * far
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
	# No wall, fence or post cell along the way.
	var steps := int(a.distance_to(b) * 8.0)
	for k in range(1, steps):
		var c := a.lerp(b, float(k) / steps)
		if c.distance_to(b) > .6 and g.world.blocked(c.x, c.y, .05):
			return false
	for q: Vector2 in things:
		var on := Geometry2D.get_closest_point_to_segment(q, a, b)
		if on.distance_to(q) < .4 and q.distance_to(b) > .5 and q.distance_to(a) > .3:
			return false
	return true


## Whether (x, y) stands out in a yard: no wall within two cells.
func _yard(g: Game, x: float, y: float) -> bool:
	for cy in range(int(y) - 2, int(y) + 3):
		for cx in range(int(x) - 2, int(x) + 3):
			if cx < 0 or cy < 0 or cx >= g.world.width or cy >= g.world.height:
				return false
			if g.world.solid[cy * g.world.width + cx] >= 0:
				return false
	return true


func _shot(row: Array) -> void:
	var name: String = row[0]
	var g := _level(row[1])
	var pieces = g.features["breakables"]
	var order: Array = []
	# Out in a yard first (no wall within two cells), then anywhere.
	for open: bool in [true, false]:
		for i in pieces.pieces.size():
			var q = pieces.pieces[i]
			if q.image == row[2] and _yard(g, q.x, q.y) == open:
				order.append(i)
	for i: int in order:
		var p = pieces.pieces[i]
		var tag := "%s:%d" % [row[1], i]
		if p.broken or _used.has(tag):
			continue
		var at := _spot(g, p.x, p.y, row[4])
		if at == Vector2.INF:
			continue
		_used[tag] = true
		var foot: float = g.world.stand(p) + p.z
		var tz: float = foot + p.height * float(row[5])
		_stand(g, at.x, at.y, p.x, p.y, tz)
		_arm(g, row[3])
		_ticks(g, 20)
		await _snap("%s_0" % name)
		for k in 8:
			_stand(g, at.x, at.y, p.x, p.y, tz)
			_arm(g, row[3])
			_ticks(g, 1, true)
			if p.broken:
				break
			_ticks(g, 24)
		var gaps: Array = AFTER
		for k in gaps.size():
			_ticks(g, int(gaps[k]))
			await _snap("%s_%d" % [name, k + 1])
		# Close by, looking down at what lies about.
		var near := Vector2(p.x, p.y) + (at - Vector2(p.x, p.y)).normalized() * 1.5
		if not g.world.blocked(near.x, near.y, .25):
			_stand(g, near.x, near.y, p.x, p.y, foot - .15)
			# Turned a little right: what lies about shows left of the gun.
			g.player.angle += .3
			_ticks(g, 1)
			await _snap("%s_close" % name)
		return
	print("no clear shot at a ", row[2], " on ", row[1])
