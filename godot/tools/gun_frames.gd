## Pictures of every gun firing and of what its shots do, in a real window
## (the graphics-card view players see): each gun at a plank wall a few paces
## off, a row of frames from the trigger on; a stick of dynamite going up in a
## yard; and the .38 into each material a level has (sparks, chips, dust,
## glints, a splash). Each is a row of frames, <name>_<n>.png, in out=<dir>.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/gun_frames.gd -- out=<dir> [only=<name,...>]
##
## It drives the game only the way play does (aim, fire, a blast where a stick
## would land), so the same script on an older build shows the before. Point
## APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

## Ticks between frames, from the first tick of the trigger.
const GAPS := [1, 1, 1, 2, 3, 5, 8]
## The guns shown at the wall, by weapons.cfg section (the trigger held for
## those that keep firing).
const AT_WALL := [
	"revolver",
	"shotgun",
	"rifle",
	"riveter",
	"pressure_gun",
	"teat_gun",
	"armgun",
	"crossbow",
	"bottle_launcher",
	"cow_launcher",
	"ripsaw",
	"powder_keg",
	"tnt",
]
const HELD := ["rifle", "riveter", "pressure_gun", "teat_gun", "armgun"]
## Materials the .38 is shown striking, and where to look for each.
const KINDS := ["wood", "brick", "tin", "steel", "stone", "dirt", "brush", "timber", "glass"]
const LEVELS := ["hickston", "fair", "sawmill", "quarry", "bayou", "speedway", "mothership"]

var main
var out := ""
var only: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
		elif String(arg).begins_with("only="):
			only = Array(String(arg).substr(5).split(","))
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
	for gun: String in AT_WALL:
		if _wanted(gun):
			await _gun(gun)
	if _wanted("blast"):
		await _blast()
	if _wanted("chain"):
		await _chain()
	for kind: String in KINDS:
		if _wanted("hit_" + kind):
			await _material(kind)
	print("gun frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _wanted(name: String) -> bool:
	return only.is_empty() or only.has(name)


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
	p.sway = 0.0


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
	held.fire = fire
	for i in n:
		g.tick(1.0 / 60.0, held)


## Nothing standing between a and b to hide the view (a post, a tree).
func _clear(g: Game, a: Vector2, b: Vector2) -> bool:
	var things: Array = []
	for s: Renderer.Sprite in g.props:
		things.append(Vector2(s.x, s.y))
	for board: LevelData.Billboard in g.world.billboards:
		things.append(Vector2(board.x, board.y))
	for q: Vector2 in things:
		var on := Geometry2D.get_closest_point_to_segment(q, a, b)
		if on.distance_to(q) < .5 or q.distance_to(a) < .8:
			return false
	return true


## A place `far` cells straight out from a wall of `kind` on level `g`:
## [stand, the point struck], or [] when there is none.
func _facing(g: Game, kind: String, far_min: float, far_max: float, room := .9) -> Array:
	var w := g.world
	for cy in range(2, w.height - 2):
		for cx in range(2, w.width - 2):
			var at := Vector2(cx + .5, cy + .5)
			if w.blocked(at.x, at.y, room):
				continue
			for dir: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				var d := .5
				var hit := false
				while d < far_max + .1:
					var q := at + dir * d
					if w.blocked(q.x, q.y, .02, w.elevation(at.x, at.y) + .7):
						hit = true
						break
					d += .05
				if not hit or d < far_min:
					continue
				var mark := at + dir * d
				if Materials.struck(w, mark.x + dir.x * .03, mark.y + dir.y * .03, .7) != kind:
					continue
				if (
					absf(
						(
							w.elevation(mark.x - dir.x * .3, mark.y - dir.y * .3)
							- w.elevation(at.x, at.y)
						)
					)
					> .05
				):
					continue
				if w.roof[cy * w.width + cx] > 0.0 and kind != "steel":
					continue
				if not _clear(g, at, mark - dir * .2):
					continue
				var open := true
				var s := .3
				while s < d - .7 and open:
					var q := at + dir * s
					open = not w.blocked(q.x, q.y, .45)
					s += .2
				if open:
					return [at, mark]
	return []


## A gun fired at a plank wall a few paces off.
func _gun(section: String) -> void:
	var gun := Weapons.NAMES.find(section)
	if gun < 0:
		return
	var g := _level("hickston")
	var spot := _facing(g, "wood", 3.6, 4.6)
	if spot.is_empty():
		return
	var at: Vector2 = spot[0]
	var mark: Vector2 = spot[1]
	_stand(g, at.x, at.y, mark.x, mark.y, .7)
	_arm(g, gun)
	_ticks(g, 30)
	await _snap("%s_0" % section)
	var keep := HELD.has(section)
	for k in GAPS.size():
		_ticks(g, int(GAPS[k]), keep or k == 0)
		await _snap("%s_%d" % [section, k + 1])
	# What a projectile does when it gets there.
	if not keep and Weapons.FIRING[gun].get("fire", "") == "projectile":
		for k in 4:
			_ticks(g, 10)
			await _snap("%s_%d" % [section, GAPS.size() + k + 1])


## A stick of dynamite going up in a yard, four paces off.
func _blast() -> void:
	var g := _level("hickston")
	var spot := _facing(g, "wood", 3.6, 4.6)
	if spot.is_empty():
		return
	var at: Vector2 = spot[0]
	var mark: Vector2 = spot[1]
	var boom := at + (mark - at).normalized() * 3.0
	_stand(g, at.x, at.y, boom.x, boom.y, .6)
	_arm(g, Weapons.REVOLVER)
	_ticks(g, 30)
	await _snap("blast_0")
	g.explode(
		Game.Shot.new(boom.x, boom.y, g.world.elevation(boom.x, boom.y) + .15, 0, 0, 0, "tnt")
	)
	for k in [1, 2, 3, 4, 6, 9, 14, 22, 34, 50]:
		_ticks(g, int(k))
		await _snap("blast_%d" % (int(k)))


## Three sticks going up one after another (the cap on what a chain throws).
func _chain() -> void:
	var g := _level("hickston")
	var spot := _facing(g, "wood", 3.6, 4.6)
	if spot.is_empty():
		return
	var at: Vector2 = spot[0]
	var mark: Vector2 = spot[1]
	var way := (mark - at).normalized()
	_stand(g, at.x, at.y, at.x + way.x * 3.0, at.y + way.y * 3.0, .6)
	_arm(g, Weapons.REVOLVER)
	_ticks(g, 30)
	for k in 6:
		var boom := at + way * (2.6 + k * .15) + way.orthogonal() * ((k % 3) - 1) * .8
		g.explode(
			Game.Shot.new(boom.x, boom.y, g.world.elevation(boom.x, boom.y) + .15, 0, 0, 0, "tnt")
		)
		_ticks(g, 4)
	await _snap("chain_0")
	_ticks(g, 10)
	await _snap("chain_1")


## The .38 into a wall of one material, wherever a level has one.
func _material(kind: String) -> void:
	for level_id: String in LEVELS:
		var g := _level(level_id)
		var spot := _facing(g, kind, 2.2, 3.4, .45)
		if spot.is_empty():
			continue
		var at: Vector2 = spot[0]
		var mark: Vector2 = spot[1]
		_stand(g, at.x, at.y, mark.x, mark.y, .7)
		_arm(g, Weapons.REVOLVER)
		_ticks(g, 30)
		_ticks(g, 1, true)
		var done := 1
		for k in [2, 4, 8, 16]:
			_ticks(g, int(k) - done)
			done = int(k)
			await _snap("hit_%s_%d" % [kind, done])
		return
