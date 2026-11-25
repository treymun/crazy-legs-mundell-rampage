## Pictures of reading danger in a real window (pass 15: src/danger_marks.gd,
## features/danger_looks.gd, EnemyLooks.tell): DANGER ARROWS for blows from
## the left and from behind (the moment one lands, white, and a beat later,
## red; a heavy one doubled), the same in ASPECT WIDE and with the touch
## buttons up, hands winding up (the amber on their models, the floor mark of
## a big one, a gun's glint, the amber arrow for one behind), and a hand by
## the sawmill's saw (the brackets round it, the skull under the crosshair).
## Each is <name>.png in out=<dir>.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/danger_frames.gd -- out=<dir> [only=<name,...>]
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

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
	if _want("arrows"):
		await _arrows("arrows")
	if _want("touch"):
		await _arrows("touch", true)
		main.touch.active = false
		main.touch.set_showing(false)
	if _want("wide"):
		var size: Vector2i = root.size
		main.options["aspect"] = PictureShape.ASPECT_WIDE
		root.size = Vector2i(1424, 800)
		await _arrows("wide")
		main.options["aspect"] = 0
		root.size = size
	if _want("windup"):
		await _windup()
	if _want("hazard"):
		await _hazard()
	print("danger frames written to ", out)
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
	g.barks.enabled = false
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


## Blows from the left and from behind on the right (heavy): as they land,
## then a beat later.
func _arrows(name: String, touch := false) -> void:
	var g := _level("hickston")
	var at := Vector2(60.5, 44.5)
	_stand(g, at, _open(g, at))
	if touch:
		# A phone's: the buttons up over the view (main_state.gd shows them in play).
		main.touch.active = true
		main.touch.set_showing(true)
		main.touch.layout(main.viewport_rect(), true)
	_ticks(g, .2)
	g.cheats.god = false
	var p := g.player
	var a := p.angle
	var left := Vector2(sin(a), -cos(a))
	var back := -Vector2(cos(a), sin(a))
	# From the left, and from behind on the right (heavy).
	var from_left := Vector2(p.x, p.y) + left * 4.0
	var from_back := Vector2(p.x, p.y) + back * 3.0 - left * 2.0
	g.damage(8.0, [from_left.x, from_left.y], "BUCKSHOT")
	g.damage(30.0, [from_back.x, from_back.y], "PITCHFORK")
	g.hurt_flash = 0.0
	await _snap(name + "_0_landed")
	_ticks(g, .2)
	g.hurt_flash = 0.0
	await _snap(name + "_1_later")


## Three hands winding up: a chain hand ahead (the floor marked where his
## chain comes down: where the player stood as it began, a step and a half
## ahead of him now), a yard deputy ahead on the right (his gun's glint), a
## billy behind (the amber arrow), each in the last share of his wind-up.
func _windup() -> void:
	var g := _level("hickston")
	var at := Vector2(60.5, 44.5)
	var a := _open(g, at)
	_stand(g, at, a, -26.0)
	var p := g.player
	var ahead := Vector2(cos(a), sin(a))
	var side := Vector2(-ahead.y, ahead.x)
	var cast: Array[Enemy] = []
	for row: Array in [["chain_hand", 5.5, -1.4], ["yard_deputy", 4.2, 1.6]]:
		var spot: Vector2 = at + ahead * float(row[1]) + side * float(row[2])
		var e := _hand(g, str(row[0]), spot, 0.0)
		e.angle = atan2(p.y - e.y, p.x - e.x)
		cast.append(e)
	var behind := _hand(g, "billy", at - ahead * 4.0 + side * .5, a)
	cast.append(behind)
	_ticks(g, .1)
	for e: Enemy in cast:
		var whole: float = Enemy.WINDUP[e.kind][0]
		e.windup = whole * (.3 if e != cast[0] else .45)
		e.player_seen = true
		e.aim_mark = [p.x, p.y, p.eye]
		e.cooldown = 99.0
	var stood := at + ahead * 2.4
	cast[0].aim_mark = [stood.x, stood.y, p.eye]
	# A tick into the flicker's bright half.
	g.clock = floorf(g.clock * EnemyLooks.TELL_BEAT + 1.0) / EnemyLooks.TELL_BEAT + .01
	await _snap("windup_0_tell")
	for e: Enemy in cast:
		var whole: float = Enemy.WINDUP[e.kind][0]
		e.windup = whole * .9
	await _snap("windup_1_early")


## A billy beside the sawmill's saw: the brackets round it; then standing
## where a boot sends him in, the skull under the crosshair.
func _hazard() -> void:
	var g := _level("sawmill")
	var spot := Vector2(52.5, 18.5)
	var way := _approach(g, spot)
	if way.is_empty():
		push_warning("no way to the saw")
		return
	var from: Vector2 = way[0]
	var by: Vector2 = way[1]
	var a: float = way[2]
	_stand(g, from - Vector2(cos(a), sin(a)) * 3.0, a, -8.0)
	_hand(g, "billy", by, a + PI)
	_ticks(g, .1)
	await _snap("hazard_0_glow")
	_stand(g, from, a, -8.0)
	_ticks(g, .05)
	await _snap("hazard_1_skull")


## The way from `at` with the longest run of open, level floor (at most 12
## cells), to look along.
func _open(g: Game, at: Vector2) -> float:
	var best := 0.0
	var longest := -1
	for k in 32:
		var a := k * TAU / 32.0
		var z := g.world.elevation(at.x, at.y)
		var run := 0
		for s in range(1, 121):
			var p := at + Vector2(cos(a), sin(a)) * (s / 10.0)
			var wide := Vector2(-sin(a), cos(a)) * 1.6
			if (
				g.world.blocked(p.x, p.y, .3)
				or g.world.blocked(p.x + wide.x, p.y + wide.y, .2)
				or g.world.blocked(p.x - wide.x, p.y - wide.y, .2)
				or absf(g.world.elevation(p.x, p.y) - z) > .05
			):
				break
			run = s
		if run > longest:
			longest = run
			best = a
	return best


## A way into `spot` along open level floor: [where the player stands,
## where the hand stands, the angle], or [] (as brawl_frames.gd).
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
