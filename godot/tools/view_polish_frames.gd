## Pictures of the view polish (track L) in a real window:
##   storm_<0..4>    County Run's storm front: from well inside the ring, close
##                   to its wall, with lightning, from out in the storm, and
##                   EASY ON THE EYES STILL
##   shadow_<0..2>   hands standing by a fire throwing their shadows, a crate
##                   tossed past it, and the same with SHADOWS off
##   marks_<0..3>    bullet holes in a prop, a blast's scorch on another, the
##                   speedway's stock car shot up, a prop charred by fire
## Each lands in out=<dir> as <name>.png; only=<storm|shadow|marks> takes one set.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/view_polish_frames.gd -- out=<dir> [only=storm]
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

var main
var out := ""
var only := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
		if String(arg).begins_with("only="):
			only = String(arg).substr(5)
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
	if only == "" or only == "storm":
		await _storm()
	if only == "" or only == "shadow":
		await _shadows()
	if only == "" or only == "marks":
		await _marks()
	print("view polish frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _snap(name: String) -> void:
	var g: Game = main.game
	if g != null:
		g.message_until = 0.0
		g.callout_until = 0.0
		g.district_until = 0.0
		g.barks.until = 0.0
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


func _ticks(g: Game, n: int) -> void:
	for i in n:
		g.tick(1.0 / 60.0, Game.Controls.new())


func _stand(g: Game, x: float, y: float, tx: float, ty: float, tz: float) -> void:
	var p := g.player
	p.x = x
	p.y = y
	p.angle = atan2(ty - y, tx - x)
	p.floor_z = g.world.floor_under(x, y, 9.0)
	p.air = 0.0
	p.eye = .95 + p.floor_z
	var d := Vector2(tx - x, ty - y).length()
	p.pitch = clampf((tz - p.eye) / maxf(d, .1) * View.base_focal, -50.0, 50.0)
	p.vx = 0.0
	p.vy = 0.0


func _level(id: String) -> Game:
	main.start(id)
	var g: Game = main.game
	g.cheats.god = true
	g.lessons = false
	g.barks.enabled = false
	for e: Enemy in g.enemies:
		e.dormant = true
	g.spawn_grace = 99.0
	return g


# --------------------------------------------------------------------- storm


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
	# The same storm every time (its dice come from the run's).
	g.rng.set_state(1997)
	CountyStorm.begin(g, f)
	f.storm_next = f.run_time + 1.0
	_ticks(g, 60 * 36)
	var spots: Array = CountySpawner.spots(g)
	var picks := {}
	for s: Vector2 in spots:
		var d: float = s.distance_to(f.storm_at)
		var way: Vector2 = (s - f.storm_at).normalized()
		var wall: Vector2 = f.storm_at + way * (f.storm_r + 1.0)
		var back: Vector2 = f.storm_at + way * (f.storm_r - 4.0)
		for want: Array in [["far", f.storm_r - 9.0, wall], ["near", f.storm_r - 3.5, wall]]:
			var tag: String = want[0]
			var ring: float = want[1]
			var target: Vector2 = want[2]
			if not picks.has(tag) and absf(d - ring) < .5:
				if g.world.visible(s.x, s.y, target.x, target.y, 1.0, 1.0):
					picks[tag] = [s, target]
		if not picks.has("out") and absf(d - (f.storm_r + 3.0)) < .5:
			if g.world.visible(s.x, s.y, back.x, back.y, 1.0, 1.0):
				picks["out"] = [s, back]
	var shots := [
		["far", "storm_0", 0.0, 0],
		["near", "storm_1", 0.0, 0],
		["near", "storm_2", .8, 0],
		["out", "storm_3", 0.0, 0],
		["far", "storm_4", 0.0, 2],
	]
	for shot: Array in shots:
		var tag: String = shot[0]
		if not picks.has(tag):
			print("no spot for ", tag)
			continue
		var pick: Array = picks[tag]
		var at: Vector2 = pick[0]
		var target: Vector2 = pick[1]
		g.view.world_motion = shot[3]
		_stand(g, at.x, at.y, target.x, target.y, 2.4 if tag != "out" else 1.2)
		_ticks(g, 20)
		_stand(g, at.x, at.y, target.x, target.y, 2.4 if tag != "out" else 1.2)
		g.lightning = shot[2]
		await _snap(shot[1])
	g.view.world_motion = 0


# ------------------------------------------------------------------- shadows


func _shadows() -> void:
	var g := _level("hickston")
	var p := g.player
	# The lantern post nearest the start, the hands round it.
	var post: LevelData.Billboard = null
	for b: LevelData.Billboard in g.world.billboards:
		if b.image == "town_lantern_post" or b.image == "town_burn_barrel":
			if (
				post == null
				or (
					Vector2(b.x - p.x, b.y - p.y).length()
					< Vector2(post.x - p.x, post.y - p.y).length()
				)
			):
				post = b
	if post == null:
		print("no lantern post")
		return
	var fx := post.x
	var fy := post.y
	var view := _view_of_point(g, Vector2(fx, fy), 4.2, 0.0, post)
	var side := (Vector2(fx, fy) - view).normalized()
	var across := Vector2(-side.y, side.x)
	var hands: Array = []
	for e: Enemy in g.enemies:
		if e.hostile and e.hp > 0.0 and e.brain == "billy" and hands.size() < 3:
			e.dormant = false
			hands.append(e)
	# Nightfall, for the picture: the yard's light down to a third.
	for c in g.world.light.size():
		g.world.light[c] *= .6
	g.world.light_version += 1
	var places := [Vector2(-1.2, .5), Vector2(-.5, -1.3), Vector2(.3, 1.4)]
	for k in hands.size():
		var e: Enemy = hands[k]
		var off: Vector2 = places[k]
		var at := Vector2(fx, fy) + side * off.x + across * off.y
		e.x = at.x
		e.y = at.y
		e.angle = atan2(-side.y, -side.x)
		e.speed = 0.0
		e.alerted = false
	# The lantern alone; a street lamp's worth of light off to the side (a
	# level trigger's light); the same with SHADOWS off.
	var lamp := Vector2(fx, fy) + side * .8 + across * .6
	var lamp_z := g.world.floor_under(lamp.x, lamp.y, 9.0) + 1.9
	for k in 3:
		_ticks(g, 30)
		_stand(g, view.x, view.y, fx, fy, -1.2)
		if k == 1:
			g.trigger_lights.append(
				[lamp.x, lamp.y, lamp_z, 5.5, Color(1.0, .8, .5), .9, g.clock + 1e6]
			)
		if k == 2:
			main.options["shadows"] = 0
			main.apply_options()
		await _snap("shadow_%d" % k)
	main.options["shadows"] = 1
	main.apply_options()


# --------------------------------------------------------------------- marks


## A modelled prop near the player, seen from `far` cells off its open side.
func _prop_near(g: Game, skip: Array) -> LevelData.Billboard:
	var best: LevelData.Billboard = null
	var best_d := 1e9
	var models: PropModels = main.world_view.props.models if main.world_view != null else null
	for b: LevelData.Billboard in g.world.billboards:
		if skip.has(b) or b.height < .5 or b.height > 1.6:
			continue
		if models != null and models.name_of(b.image) == "":
			continue
		var bulky := false
		for word: String in ["barrel", "crate", "drum", "bale", "keg", "trough"]:
			bulky = bulky or b.image.contains(word)
		if not bulky:
			continue
		var d := Vector2(b.x - g.player.x, b.y - g.player.y).length()
		if d < best_d:
			best = b
			best_d = d
	return best


func _view_of(g: Game, b: LevelData.Billboard, far: float) -> Vector2:
	return _view_of_point(g, Vector2(b.x, b.y), far, 0.0, b)


## A spot `far` from `at` with a clear line to it (no wall, no prop but
## `own` within .9 of the line), trying the ways round from `first`.
func _view_of_point(
	g: Game, at: Vector2, far: float, first := 0.0, own: LevelData.Billboard = null
) -> Vector2:
	for k in 32:
		var a := first + (k / 2) * TAU / 16.0 * (1.0 if k % 2 == 0 else -1.0)
		var from := at + Vector2(cos(a), sin(a)) * far
		if g.world.blocked(from.x, from.y, .3):
			continue
		if not g.world.visible(from.x, from.y, at.x, at.y, 1.0, .6):
			continue
		var clear := true
		for s in 20:
			var q := from.lerp(at, s / 20.0 * (1.0 - .6 / far))
			if g.world.blocked(q.x, q.y, .05, g.world.floor_under(q.x, q.y, 9.0) + .6):
				clear = false
				break
		for b: LevelData.Billboard in g.world.billboards:
			if b == own:
				continue
			var p := Vector2(b.x, b.y)
			var t := clampf(
				(p - from).dot(at - from) / maxf((at - from).length_squared(), .01), 0.0, 1.0
			)
			if p.distance_to(from.lerp(at, t)) < .9 and p.distance_to(at) > .3:
				clear = false
				break
		if clear:
			return from
	return at + Vector2(0, far)


func _shoot(g: Game, to: Vector3) -> void:
	g.armory.active = Weapons.REVOLVER
	var p := g.player
	var way := (to - Vector3(p.x, p.y, p.eye)).normalized()
	g.events.traced.emit(to + way * .3, "thing")


func _marks() -> void:
	var g := _level("hickston")
	main.render()
	await RenderingServer.frame_post_draw
	var crate := _prop_near(g, [])
	if crate == null:
		print("no prop to mark")
		return
	var at := _view_of(g, crate, 2.4)
	var base := g.world.floor_under(crate.x, crate.y, 9.0)
	_stand(g, at.x, at.y, crate.x, crate.y, base + crate.height * .5)
	_ticks(g, 2)
	main.render()
	await RenderingServer.frame_post_draw
	var side := Vector2(crate.x - at.x, crate.y - at.y).normalized()
	var across := Vector2(-side.y, side.x)
	for k in 6:
		var off := across * (k % 3 - 1) * .14
		var to := Vector3(
			crate.x + off.x, crate.y + off.y, base + crate.height * (.3 + .2 * (k / 3))
		)
		_shoot(g, to)
		_ticks(g, 2)
	_stand(g, at.x, at.y, crate.x, crate.y, base + crate.height * .5)
	await _snap("marks_0")
	# A blast beside it, then fire under it.
	var other := crate
	if other != null:
		var view := at
		var obase := g.world.floor_under(other.x, other.y, 9.0)
		var toward := Vector2(view.x - other.x, view.y - other.y).normalized()
		var blast := Vector3(other.x + toward.x * .9, other.y + toward.y * .9, obase + .4)
		_stand(g, view.x, view.y, other.x, other.y, obase + other.height * .5)
		_ticks(g, 2)
		main.render()
		await RenderingServer.frame_post_draw
		g.events.exploded.emit(blast.x, blast.y, blast.z, false)
		_ticks(g, 90)
		_stand(g, view.x, view.y, other.x, other.y, obase + other.height * .5)
		await _snap("marks_1")
		# Fire under it: charred.
		var fire = g.features.get("fire")
		if fire != null:
			fire.charred[g.world.cell(other.x, other.y)] = obase
			_ticks(g, 30)
			_stand(g, view.x, view.y, other.x, other.y, obase + other.height * .5)
			await _snap("marks_3")
	# The speedway's stock car shot along its side.
	g = _level("speedway")
	var rides = g.features["vehicles"]
	if rides.rides.is_empty():
		return
	_ticks(g, 20)
	var v: VehicleDrive.Ride = rides.rides[0]
	var stand := _view_of_point(g, Vector2(v.x, v.y), 4.0, v.h - PI / 2.0)
	_stand(g, stand.x, stand.y, v.x, v.y, v.z + .4)
	_ticks(g, 2)
	main.render()
	await RenderingServer.frame_post_draw
	for k in 7:
		var along := (k - 3) * .3
		_shoot(
			g, Vector3(v.x + cos(v.h) * along, v.y + sin(v.h) * along, v.z + .35 + .12 * (k % 2))
		)
		_ticks(g, 1)
	_stand(g, stand.x, stand.y, v.x, v.y, v.z + .4)
	await _snap("marks_2")
