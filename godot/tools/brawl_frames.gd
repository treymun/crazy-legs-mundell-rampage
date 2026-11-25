## Pictures of dirty fighting in a real window (features/brawl.gd and
## brawl_looks.gd): the boot coming up and a man flying back from it, a door
## kicked in, a finisher of each class at its blow and after, and a man
## booted into each of the county's hazards where the chapters stand them
## (the chipper, the saw, the bug zapper, the hot wire, the burn barrel, the
## well, the cattle guard, the creek, the hog pen), with the new props
## standing in their chapters. Each is <name>.png in out=<dir>.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/brawl_frames.gd -- out=<dir> [only=<name,...>]
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

const Brawl := preload("res://src/features/brawl.gd")
const STEP := 1.0 / 60.0

var main
var out := ""
var only: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text.begins_with("out="):
			out = text.substr(4)
		elif text.begins_with("only="):
			only = Array(text.substr(5).split(","))
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
	if _want("kick"):
		await _kick()
	if _want("door"):
		await _door()
	for row: Array in [
		["revolver", "whip"],
		["revolver", "mouth"],
		["shotgun", "butt"],
		["shotgun", "belly"],
		["crowbar", "skull"],
		["slingblade", "gut"],
		["tnt", "stomp"],
		["tnt", "punt"],
	]:
		if _want("finish_" + str(row[1])):
			await _finish(row[0], row[1])
	var spots := [
		["chipper", "sawmill", Vector2(82.5, 69.5)],
		["chipper_west", "sawmill", Vector2(23.5, 40.5)],
		["saw", "sawmill", Vector2(52.5, 18.5)],
		["zapper", "hickston", Vector2(69.5, 52.5)],
		["fence", "hickston", Vector2(86.5, 13.5)],
		["barrel", "fair", Vector2(118.5, 52.5)],
		["well", "hickston", Vector2(19.5, 41.5)],
		["guard", "hickston", Vector2(58.5, 37.5)],
		["fence_quarry", "quarry", Vector2(97.5, 31.5)],
		["zapper_bayou", "bayou", Vector2(25.5, 18.5)],
	]
	for row: Array in spots:
		if _want("hazard_" + str(row[0])):
			await _hazard(row[0], row[1], row[2])
	if _want("hazard_water"):
		await _water()
	if _want("hazard_hogs"):
		await _hogs()
	print("brawl frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _want(name: String) -> bool:
	if only.is_empty():
		return true
	for o: String in only:
		if name.begins_with(o):
			return true
	return false


func _snap(name: String) -> void:
	if main.game != null:
		main.game.message_until = 0.0
	main.render()
	await RenderingServer.frame_post_draw
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


func _level(level_id: String) -> Game:
	main.start(level_id)
	var g: Game = main.game
	g.cheats.god = true
	g.lessons = false
	for e: Enemy in g.enemies:
		e.dormant = true
	g.message_until = 0.0
	g.district_until = 0.0
	return g


func _hand(g: Game, kind: String, at: Vector2, face: float) -> Enemy:
	var e := Enemy.new(kind, at.x, at.y, face)
	e.dormant = false
	e.uid = g.take_uid()
	e.alerted = true
	e.floor_z = g.world.elevation(at.x, at.y)
	g.enemies.append(e)
	return e


func _stand(g: Game, at: Vector2, angle: float, pitch := 0.0) -> void:
	var p := g.player
	p.x = at.x
	p.y = at.y
	p.angle = angle
	p.floor_z = g.world.elevation(at.x, at.y)
	p.air = 0.0
	p.vertical_speed = 0.0
	p.eye = .95 + p.floor_z
	p.pitch = pitch
	p.vx = 0.0
	p.vy = 0.0


func _ticks(g: Game, seconds: float, use := false) -> void:
	for i in maxi(1, int(seconds * 60.0)):
		var c := Game.Controls.new()
		c.use = use and i == 0
		g.tick(STEP, c)


## A way into `spot` along open level floor: [where the player stands,
## where the hand stands, the angle], or [].
func _approach(g: Game, spot: Vector2, near := 1.2) -> Array:
	for k in 16:
		var a := k * TAU / 16.0
		var d := Vector2(cos(a), sin(a))
		var ok := true
		var z := g.world.elevation(spot.x - d.x * 2.0, spot.y - d.y * 2.0)
		for s in range(10, 46):
			var at := spot - d * (s / 10.0)
			if g.world.blocked(at.x, at.y, .3) or absf(g.world.elevation(at.x, at.y) - z) > .05:
				ok = false
				break
		if ok:
			return [spot - d * (near + 2.4), spot - d * (near + 1.2), a]
	return []


func _kick() -> void:
	var g := _level("hickston")
	var at := Vector2(60.5, 44.5)
	var way := _approach(g, at + Vector2(3.0, 0.0), 1.0)
	if way.is_empty():
		return
	_stand(g, way[0], way[2])
	_hand(g, "billy", way[1], way[2] + PI)
	_ticks(g, .1)
	_ticks(g, STEP, true)
	# A strip through the kick: chambered, out, the blow, back, away, him.
	for k in 8:
		_ticks(g, .05)
		await _snap("kick_%d" % k)


func _door() -> void:
	var g := _level("hickston")
	var b: Brawl = g.features["brawl"]
	for door: LevelData.Door in g.world.doors:
		if door.opened or door.key != "" or door.secret or door.blast_only or door.bar_side != 0:
			continue
		var c := door.center()
		for side in [-1.0, 1.0]:
			var off := Vector2(side, 0.0) if door.vertical else Vector2(0.0, side)
			var at := c + off * 1.3
			if g.world.blocked(at.x, at.y, .3) or g.world.roof_over(at.x, at.y, 1.0) > 0.0:
				continue
			var behind := c - off * 1.0
			if g.world.blocked(behind.x, behind.y, .3):
				continue
			_stand(g, at, atan2(-off.y, -off.x))
			g.player.vx = -off.x * 3.0
			g.player.vy = -off.y * 3.0
			if b._door_ahead(g.player) < 0:
				continue
			_hand(g, "coot", behind, atan2(off.y, off.x))
			await _snap("door_0_shut")
			var c2 := Game.Controls.new()
			c2.use = true
			c2.forward = 1.0
			g.tick(STEP, c2)
			_ticks(g, .16)
			await _snap("door_1_kicked_in")
			_ticks(g, .4)
			await _snap("door_2_him_behind")
			return


func _finish(gun_name: String, want: String) -> void:
	var g := _level("hickston")
	var at := Vector2(60.5, 44.5)
	var way := _approach(g, at + Vector2(3.0, 0.0), 1.0)
	if way.is_empty():
		return
	var p := g.player
	_stand(g, way[0], way[2], -8.0)
	var gun := Weapons.NAMES.find(gun_name)
	p.armory.owned[gun] = true
	p.armory.loaded[gun] = maxi(p.armory.loaded[gun], 4)
	p.armory.reserve[gun] = maxi(p.armory.reserve[gun], 8)
	p.armory.active = gun
	p.armory.switch = 0.0
	var e := _hand(g, "billy", way[1], way[2] + PI)
	e.hp = e.max_hp * .2
	_ticks(g, .3)
	_ticks(g, STEP, true)
	var b: Brawl = g.features["brawl"]
	# This move, whichever game.rng picked (the frames show each).
	var move := want
	if not b.moves.is_empty():
		b.moves[b.moves.size() - 1][2] = want
		b.last_moves[p.slot][0] = want
	# A strip in real time: the wind at full speed, the blow, the hit-stop
	# and the follow through in the slow motion, him down.
	var waits := [.04, .04, .04, .04, .08, .12, .2, .3, 1.0]
	for k in waits.size():
		_ticks(g, waits[k])
		await _snap("finish_%s_%d" % [move, k])


func _hazard(kind: String, level_id: String, spot: Vector2) -> void:
	var g := _level(level_id)
	var way := _approach(g, spot)
	if way.is_empty():
		push_warning("no way into " + kind)
		return
	_stand(g, way[0], way[2], -6.0)
	await _snap("hazard_%s_0_prop" % kind)
	var e := _hand(g, "billy", way[1], way[2] + PI)
	_ticks(g, .2)
	_ticks(g, STEP, true)
	_ticks(g, .32)
	await _snap("hazard_%s_1_in" % kind)
	_ticks(g, .5)
	await _snap("hazard_%s_2_after" % kind)
	var b: Brawl = g.features["brawl"]
	print("  %s: %s, kills %s" % [kind, "dead" if not e.alive else "ALIVE", str(b.hazard_kills)])


func _water() -> void:
	var g := _level("hickston")
	var w := g.world
	for y in range(2, w.height - 2):
		for x in range(3, w.width - 5):
			var dry := true
			for k in 3:
				if w.blocked(x + k + .5, y + .5, .45) or BayouBrains.wet_at(w, x + k + .5, y + .5):
					dry = false
			if not dry:
				continue
			if not (
				BayouBrains.wet_at(w, x + 3.5, y + .5) and BayouBrains.wet_at(w, x + 4.5, y + .5)
			):
				continue
			if w.roof_over(x + .5, y + .5, 1.0) > 0.0:
				continue
			_stand(g, Vector2(x + .5, y + .5), 0.0, -8.0)
			var e := _hand(g, "billy", Vector2(x + 1.7, y + .5), PI)
			_ticks(g, .2)
			_ticks(g, STEP, true)
			_ticks(g, .35)
			await _snap("hazard_water_1_in")
			_ticks(g, 1.0)
			await _snap("hazard_water_2_after")
			print("  water: ", "dead" if not e.alive else "ALIVE")
			return


func _hogs() -> void:
	var g := _level("hickston")
	# Inside the hog pen (hickston_plan.gd packing_shed_and_hog_pen), its
	# hogs awake.
	for e: Enemy in g.enemies:
		if e.brain == "pig" and e.x < 40.0:
			e.dormant = false
	var at := Vector2(30.5, 16.5)
	_stand(g, at + Vector2(-2.6, 0.0), 0.0, -6.0)
	var man := _hand(g, "billy", at + Vector2(-1.4, 0.0), PI)
	_ticks(g, .2)
	_ticks(g, STEP, true)
	_ticks(g, 1.4)
	await _snap("hazard_hogs_1_in")
	_ticks(g, 1.2)
	await _snap("hazard_hogs_2_after")
	print("  hogs: ", "dead" if not man.alive else "ALIVE")
