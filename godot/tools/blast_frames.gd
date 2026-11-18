## Pictures of every kind of blast and of a vehicle wrecked, in a real window
## (the graphics-card view players see): a stick of dynamite, a powder keg, a
## fuel blast, a gas can, a cow, a bottle rocket and a shine cocktail going
## off in Hickston's yard; the propane tank, a hazard drum and the still shot
## until they go up; a stick against a wall, on the hay loft and in Gator
## Bayou's water; six sticks one after another; two blasts of one kind side
## by side (no two alike); and each vehicle wrecked by a blast from its side
## (and the stock car hurt, smoking and sparking as it is shot). Each is a row
## of frames, <name>_<n>.png, in out=<dir>.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/blast_frames.gd -- out=<dir> [only=<name,...>]
##
## It drives the game only the way play does (a blast where a shot would go
## off, a breakable struck, a vehicle hurt), so the same script on an older
## build shows the before. Point APPDATA at a scratch folder.
extends SceneTree

const BreakablesFeature := preload("res://src/features/breakables.gd")

const GAPS := [2, 4, 6, 8, 12, 18, 30, 60, 120]
## Shots.cfg kinds set off out in the yard.
const KINDS := ["tnt", "keg", "fuel", "gas_can", "cow", "bottle_rocket", "shine_cocktail"]
## Breakables shot until they go up: [name, picture, level].
const THINGS := [
	["propane", "town_propane_tank", "hickston"],
	["hazard", "town_warning_barrel", "hickston"],
	["still", "town_still", "hickston"],
]
const RIDES := {"car": "speedway", "airboat": "bayou", "mower": "hickston"}

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
	for kind: String in KINDS:
		if _wanted(kind):
			await _yard_blast(kind)
	for thing: Array in THINGS:
		if _wanted(str(thing[0])):
			await _thing(str(thing[0]), str(thing[1]), str(thing[2]))
	if _wanted("wall"):
		await _wall()
	if _wanted("loft"):
		await _loft()
	if _wanted("water"):
		await _water()
	if _wanted("chain"):
		await _chain()
	if _wanted("twins"):
		await _twins()
	for kind: String in RIDES:
		if _wanted("wreck_" + kind):
			await _wreck(kind, str(RIDES[kind]))
	if _wanted("hurt_car"):
		await _hurt_car()
	print("blast frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _wanted(name: String) -> bool:
	return only.is_empty() or only.has(name)


func _snap(name: String) -> void:
	var g: Game = main.game
	if g != null:
		g.message_until = 0.0
		g.barks.until = 0.0
		g.callout_until = 0.0
		g.district_until = 0.0
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
	p.floor_z = g.world.floor_under(x, y, g.world.elevation(x, y) + .3)
	p.eye = .95 + p.floor_z
	var d := Vector2(tx - x, ty - y).length()
	p.pitch = clampf((tz - p.eye) / maxf(d, .1) * View.base_focal, -50.0, 50.0)
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


func _ticks(g: Game, n: int) -> void:
	var held := Game.Controls.new()
	for i in n:
		g.tick(1.0 / 60.0, held)


func _row(g: Game, name: String) -> void:
	await _snap("%s_0" % name)
	var done := 0
	for k in GAPS.size():
		_ticks(g, int(GAPS[k]) - done)
		done = int(GAPS[k])
		await _snap("%s_%d" % [name, done])


## Whether (x, y) stands out in a yard: no wall within `r` cells.
func _open(g: Game, x: float, y: float, r: int) -> bool:
	for cy in range(int(y) - r, int(y) + r + 1):
		for cx in range(int(x) - r, int(x) + r + 1):
			if cx < 0 or cy < 0 or cx >= g.world.width or cy >= g.world.height:
				return false
			if g.world.solid[cy * g.world.width + cx] >= 0:
				return false
	return true


## A clear stretch of yard: [stand, blast], the blast `far` ahead, level ground.
func _yard(g: Game, far: float) -> Array:
	var w := g.world
	for cy in range(3, w.height - 3, 2):
		for cx in range(3, w.width - 3, 2):
			var at := Vector2(cx + .5, cy + .5)
			if not _open(g, at.x, at.y, 1):
				continue
			for dir: Vector2 in [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]:
				var boom := at + dir * far
				if not _open(g, boom.x, boom.y, 3):
					continue
				if absf(w.elevation(boom.x, boom.y) - w.elevation(at.x, at.y)) > .05:
					continue
				if w.roof[int(boom.y) * w.width + int(boom.x)] > 0.0:
					continue
				if not _clear(g, at, boom):
					continue
				return [at, boom]
	return []


func _clear(g: Game, a: Vector2, b: Vector2) -> bool:
	var things: Array = []
	for s: View.Sprite in g.props:
		things.append(Vector2(s.x, s.y))
	for board: LevelData.Billboard in g.world.billboards:
		things.append(Vector2(board.x, board.y))
	for q: Vector2 in things:
		var on := Geometry2D.get_closest_point_to_segment(q, a, b)
		if on.distance_to(q) < 1.0 and q.distance_to(a) > .3 and q.distance_to(b) > .7:
			return false
	return true


## An open place `far` (or nearer) from (x, y) at its floor, seeing it over
## nothing; `first` the way tried first (radians). Vector2.INF if none.
func _view_spot(g: Game, x: float, y: float, z: float, first: float, fars: Array) -> Vector2:
	var w := g.world
	for far: float in fars:
		for k in 24:
			var a := first + (k / 2) * TAU / 24.0 * (1 if k % 2 == 0 else -1)
			var at := Vector2(x, y) + Vector2.from_angle(a) * far
			if at.x < 1.5 or at.y < 1.5 or at.x > w.width - 1.5 or at.y > w.height - 1.5:
				continue
			if w.blocked(at.x, at.y, .45):
				continue
			var feet := w.floor_under(at.x, at.y, z + 1.0)
			if absf(feet - z) > .6:
				continue
			if not w.visible(at.x, at.y, x, y, feet + .95, z + .5):
				continue
			if not _clear(g, at, Vector2(x, y)):
				continue
			return at
	return Vector2.INF


func _boom(g: Game, at: Vector2, z: float, kind: String) -> void:
	var shot := Game.Shot.new(at.x, at.y, z, 0.0, 0.0, 0.0, kind, 0.0, false, 0)
	shot.owner = -1
	g.explode(shot)


func _yard_blast(kind: String) -> void:
	var g := _level("hickston")
	var spot := _yard(g, 5.0)
	if spot.is_empty():
		return
	var at: Vector2 = spot[0]
	var boom: Vector2 = spot[1]
	var floor_z := g.world.elevation(boom.x, boom.y)
	_stand(g, at.x, at.y, boom.x, boom.y, floor_z + .9)
	_arm(g, Weapons.REVOLVER)
	_ticks(g, 20)
	_boom(g, boom, floor_z + .15, kind)
	await _row(g, kind)


## A breakable struck until it goes up, seen from five paces.
func _thing(name: String, picture: String, level_id: String) -> void:
	var g := _level(level_id)
	var pieces: BreakablesFeature = g.features.get("breakables")
	for i in pieces.pieces.size():
		var p: BreakablesFeature.Piece = pieces.pieces[i]
		if p.image != picture or p.broken:
			continue
		var fz := g.world.elevation(p.x, p.y)
		var stand := _view_spot(g, p.x, p.y, fz, 0.0, [6.5, 5.5, 4.5])
		if stand == Vector2.INF:
			continue
		_stand(g, stand.x, stand.y, p.x, p.y, g.world.elevation(p.x, p.y) + 1.0)
		_arm(g, Weapons.REVOLVER)
		_ticks(g, 20)
		pieces.strike(i, 9999.0, p.x - stand.x, p.y - stand.y)
		# Its fuse burns (breakables.gd cooking), then it goes.
		for _k in 90:
			_ticks(g, 1)
			if not g.blasts.is_empty():
				break
		await _row(g, name)
		return


## A stick going off right against a plank wall.
func _wall() -> void:
	var g := _level("hickston")
	var w := g.world
	for cy in range(3, w.height - 3):
		for cx in range(3, w.width - 3):
			var at := Vector2(cx + .5, cy + .5)
			if w.solid[cy * w.width + cx] >= 0 or w.roof[cy * w.width + cx] > 0.0:
				continue
			for dir: Vector2 in [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]:
				var wall := at + dir
				var wi := int(wall.y) * w.width + int(wall.x)
				if w.solid[wi] < 0:
					continue
				var boom := at + dir * .25
				var side := Vector2(-dir.y, dir.x)
				var stand := at - dir * 2.5 + side * 3.5
				if w.blocked(stand.x, stand.y, .4) or not _open(g, stand.x, stand.y, 1):
					continue
				if not w.visible(
					stand.x,
					stand.y,
					boom.x,
					boom.y,
					w.elevation(stand.x, stand.y) + .95,
					w.elevation(at.x, at.y) + .5
				):
					continue
				if not _clear(g, stand, boom):
					continue
				var floor_z := w.elevation(boom.x, boom.y)
				_stand(g, stand.x, stand.y, boom.x, boom.y, floor_z + .9)
				_arm(g, Weapons.REVOLVER)
				_ticks(g, 20)
				_boom(g, boom, floor_z + .2, "tnt")
				await _row(g, "wall")
				return


## A stick on Hickston's hay loft (a deck: no crater in planks).
func _loft() -> void:
	var g := _level("hickston")
	for s: LevelGeometry.Slab in g.world.geo.slabs:
		if s.id != "hay_loft":
			continue
		var at := Vector2(s.x0 + 4.2, s.y1 - 1.0)
		var mark := Vector2(s.x0 + 2.4, s.y0 + 3.4)
		var p := g.player
		p.floor_z = g.world.floor_under(at.x, at.y, s.top + .3)
		_stand(g, at.x, at.y, mark.x, mark.y, s.top + .6)
		p.floor_z = g.world.floor_under(at.x, at.y, s.top + .3)
		p.eye = p.floor_z + .95
		p.pitch = clampf((s.top + .6 - p.eye) / at.distance_to(mark) * View.base_focal, -50, 50)
		_arm(g, Weapons.REVOLVER)
		_ticks(g, 6)
		_boom(g, mark, s.top + .15, "tnt")
		await _row(g, "loft")
		return


## A stick going off in Gator Bayou's water.
func _water() -> void:
	var g := _level("bayou")
	var water = g.features.get("water")
	var w := g.world
	for cy in range(4, w.height - 4, 2):
		for cx in range(4, w.width - 4, 2):
			var boom := Vector2(cx + .5, cy + .5)
			if not water.wet_at(boom.x, boom.y) or w.solid[cy * w.width + cx] >= 0:
				continue
			for k in 8:
				var stand := boom + Vector2.from_angle(k * TAU / 8.0) * 5.0
				if (
					stand.x < 1
					or stand.y < 1
					or stand.x >= w.width - 1
					or stand.y >= w.height - 1
					or w.blocked(stand.x, stand.y, .3)
					or water.wet_at(stand.x, stand.y)
				):
					continue
				if not w.visible(
					stand.x,
					stand.y,
					boom.x,
					boom.y,
					w.elevation(stand.x, stand.y) + .95,
					w.elevation(boom.x, boom.y) + .5
				):
					continue
				if not _clear(g, stand, boom):
					continue
				var floor_z := w.elevation(boom.x, boom.y)
				_stand(g, stand.x, stand.y, boom.x, boom.y, floor_z + .9)
				_arm(g, Weapons.REVOLVER)
				_ticks(g, 20)
				_boom(g, boom, floor_z + .1, "tnt")
				await _row(g, "water")
				return


## Six sticks going up a few ticks apart (a chain: each its own boom).
func _chain() -> void:
	var g := _level("hickston")
	var spot := _yard(g, 5.5)
	if spot.is_empty():
		return
	var at: Vector2 = spot[0]
	var boom: Vector2 = spot[1]
	var way := (boom - at).normalized()
	_stand(g, at.x, at.y, boom.x, boom.y, g.world.elevation(boom.x, boom.y) + 1.0)
	_arm(g, Weapons.REVOLVER)
	_ticks(g, 20)
	await _snap("chain_0")
	var done := 0
	for k in 6:
		var b := at + way * (4.6 + k * .3) + way.orthogonal() * ((k % 3) - 1) * 1.1
		_boom(g, b, g.world.elevation(b.x, b.y) + .15, "fuel" if k % 2 else "tnt")
		_ticks(g, 9)
		done += 9
		if k % 2 == 1:
			await _snap("chain_%d" % done)
	for k in [20, 40, 90]:
		_ticks(g, int(k))
		done += int(k)
		await _snap("chain_%d" % done)


## Two sticks side by side, one after the other: no two blasts alike.
func _twins() -> void:
	var g := _level("hickston")
	var spot := _yard(g, 5.5)
	if spot.is_empty():
		return
	var at: Vector2 = spot[0]
	var boom: Vector2 = spot[1]
	var way := (boom - at).normalized()
	_stand(g, at.x, at.y, boom.x, boom.y, g.world.elevation(boom.x, boom.y) + 1.0)
	_arm(g, Weapons.REVOLVER)
	_ticks(g, 20)
	for k in 2:
		var b := boom + way.orthogonal() * (k * 2.0 - 1.0) * 1.6
		_boom(g, b, g.world.elevation(b.x, b.y) + .15, "tnt")
	for k in [6, 12, 24]:
		_ticks(g, int(k))
		await _snap("twins_%d" % int(k))


## A vehicle with little left in it wrecked by a stick going off at its side,
## seen from across it; then burning, then burnt out.
func _wreck(kind: String, level_id: String) -> void:
	var g := _level(level_id)
	var rides = g.features["vehicles"]
	if rides.rides.is_empty():
		return
	var v: VehicleDrive.Ride = rides.rides[0]
	var s := VehicleDrive.spec(kind)
	_ticks(g, 10)
	var side := v.h + PI / 2.0
	var stand := _view_spot(g, v.x, v.y, v.z, side + .5, [6.5, 5.5, 4.5])
	if stand == Vector2.INF:
		return
	_stand(g, stand.x, stand.y, v.x, v.y, v.z + .6)
	g.player.floor_z = g.world.floor_under(stand.x, stand.y, v.z + 1.5)
	g.player.eye = g.player.floor_z + .95
	_arm(g, Weapons.REVOLVER)
	_ticks(g, 4)
	await _snap("wreck_%s_0" % kind)
	v.hp = 40.0
	var b := Vector2(v.x, v.y) - Vector2.from_angle(side) * (s.width * .5 + .5)
	_boom(g, b, v.z + .3, "tnt")
	var done := 0
	for k in [3, 8, 14, 24, 40, 70, 130, 300, 640]:
		_ticks(g, int(k) - done)
		done = int(k)
		await _snap("wreck_%s_%d" % [kind, done])


## The stock car badly hurt: smoke off its engine, sparks as rounds strike it.
func _hurt_car() -> void:
	var g := _level("speedway")
	var rides = g.features["vehicles"]
	if rides.rides.is_empty():
		return
	var v: VehicleDrive.Ride = rides.rides[0]
	var s := VehicleDrive.spec("car")
	v.hp = s.hp * .2
	var stand := _view_spot(g, v.x, v.y, v.z, v.h + .6, [4.5, 5.5])
	if stand == Vector2.INF:
		return
	_stand(g, stand.x, stand.y, v.x, v.y, v.z + .5)
	g.player.floor_z = g.world.floor_under(stand.x, stand.y, v.z + 1.5)
	g.player.eye = g.player.floor_z + .95
	_arm(g, Weapons.REVOLVER)
	_ticks(g, 30)
	await _snap("hurt_car_0")
	var held := Game.Controls.new()
	for k in 4:
		held.fire = true
		g.tick(1.0 / 60.0, held)
		held.fire = false
		for _j in 2:
			g.tick(1.0 / 60.0, held)
		await _snap("hurt_car_%d" % (k + 1))
		_ticks(g, 20)
