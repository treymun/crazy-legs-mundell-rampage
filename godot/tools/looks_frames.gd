## Pictures of the pass 15 LOOKS work in a real window: awake hands' warm rim
## near and far by day (and the same hands asleep), the critters' cool one,
## the ridge's hands by night; the pickups' glints over a few moments; the
## hurt vignette and the drain at 60, 30 and 15 health (and in ASPECT WIDE,
## and under a RAMPAGE's burning edge); the hands' shots lighting the dark
## (the ridge by night, a county blackout); each newer gun's brass in the air
## and on the ground; and the smoke left curling off the muzzle after a burst.
## Each is <name>.png in out=<dir>.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/looks_frames.gd -- out=<dir> [only=<name,...>]
##
## Point APPDATA (and LOCALAPPDATA) at a scratch folder: it runs the game with
## the profile there. It only uses what the game had before the LOOKS track,
## so the same run on an older build makes the "before" pictures.
extends SceneTree

const STEP := 1.0 / 60.0

var main
var out := ""
var only: Array = []
## The open run (cells) the last _open() found.
var _open_run := 0.0


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
	if _want("rim"):
		await _rims()
	if _want("glint"):
		await _glints()
	if _want("hurt"):
		await _hurts()
	if _want("muzzle"):
		await _muzzles()
	if _want("casings"):
		await _casings()
	if _want("smoke"):
		await _smoke()
	print("looks frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _want(name: String) -> bool:
	if only.is_empty():
		return true
	for o: String in only:
		if name.begins_with(o) or o.begins_with(name):
			return true
	return false


func _snap(name: String) -> void:
	if not _want(name):
		return
	if main.game != null:
		main.game.message_until = 0.0
		main.game.barks.until = 0.0
		main.game.caption_until = 0.0
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
	# No gun in hand: it would stand in front of what is pictured.
	g.armory.holstered = true
	g.armory.lower = 1.0
	return g


func _hand(g: Game, kind: String, at: Vector2, awake := true) -> Enemy:
	var p := g.player
	var e := Enemy.new(kind, at.x, at.y, atan2(p.y - at.y, p.x - at.x))
	e.dormant = false
	e.uid = g.take_uid()
	e.alerted = awake
	e.cooldown = 99.0
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


func _ticks(g: Game, seconds: float, fire := false) -> void:
	for i in maxi(1, int(seconds * 60.0)):
		var c := Game.Controls.new()
		c.fire = fire
		g.tick(STEP, c)


func _spot(g: Game, ahead: float, side: float) -> Vector2:
	var p := g.player
	var a := p.angle
	return Vector2(p.x + cos(a) * ahead - sin(a) * side, p.y + sin(a) * ahead + cos(a) * side)


## The awake hands near and far by day, then the same asleep; the critters;
## the ridge's hands by night.
func _rims() -> void:
	var g := _level("hickston")
	var at := Vector2(60.5, 44.5)
	_stand(g, at, _open(g, at, 200), -4.0)
	var far := minf(16.0, _open_run - 1.0)
	var cast: Array[Enemy] = []
	for row: Array in [["billy", 3.2, -1.1], ["coot", 7.5, 1.4], ["billy", far, -.2]]:
		cast.append(_hand(g, str(row[0]), _spot(g, float(row[1]), float(row[2]))))
	_ticks(g, .1)
	await _snap("rim_day_awake")
	# The far one alone, before any of them is seen asleep (a rim coming up in
	# sight fades in over its `fade`, and a tool's clock stands still).
	cast[0].x += 500.0
	cast[1].x += 500.0
	g.player.pitch = -1.0
	await _snap("rim_far_awake")
	cast[2].alerted = false
	await _snap("rim_far_asleep")
	cast[0].x -= 500.0
	cast[1].x -= 500.0
	g.player.pitch = -4.0
	for e: Enemy in cast:
		e.alerted = false
	await _snap("rim_day_asleep")
	g = _level("hickston")
	_stand(g, at, _open(g, at, 120), -14.0)
	for row: Array in [["cow", 5.5, -1.6], ["pig", 3.6, 1.2], ["chicken", 2.6, -.2]]:
		_hand(g, str(row[0]), _spot(g, float(row[1]), float(row[2])), false)
	_ticks(g, .1)
	await _snap("rim_critters")
	g = _level("moonshine")
	_stand(g, Vector2(47.3, 73.5), -1.67)
	cast.clear()
	for row: Array in [["revenooer", 6.0, 1.0], ["gas_man", 9.5, -1.2], ["still_buster", 13.0, .3]]:
		cast.append(_hand(g, str(row[0]), _spot(g, float(row[1]), float(row[2]))))
	_ticks(g, .1)
	await _snap("rim_night_awake")
	for e: Enemy in cast:
		e.alerted = false
	await _snap("rim_night_asleep")


## Ammo, food and scrap lying ahead (and a key, which glints its own way),
## seen over a few moments.
func _glints() -> void:
	var g := _level("hickston")
	var at := Vector2(60.5, 44.5)
	_stand(g, at, _open(g, at, 120), -22.0)
	var rows := [
		["shells", 2.4, -1.0],
		["rinds", 2.6, 0.0],
		["scrap_bolts", 2.4, 1.0],
		["beer", 3.6, -1.4],
		["rifle_ammo", 3.8, .4],
		["scrap_hubcap", 3.5, 1.5],
		["key_brass", 4.6, -.4],
	]
	for row: Array in rows:
		var spot := _spot(g, float(row[1]), float(row[2]))
		g.pickups.append([str(row[0]), spot.x, spot.y, g.take_uid()])
	_ticks(g, .1)
	for k in 10:
		await _snap("glint_%d" % k)
		_ticks(g, .13)


## Hurt: a blow just past at 60, 30 and 15 health, and 15 a beat later; 30
## in ASPECT WIDE; 25 under a RAMPAGE's burning edge.
func _hurts() -> void:
	for row: Array in [[60, 14], [30, 12], [15, 10]]:
		var health: int = row[0]
		var g := await _hurt_at(health, float(row[1]))
		await _snap("hurt_%d" % health)
		if health == 15:
			_ticks(g, 1.3)
			await _snap("hurt_15_later")
	if _want("hurt_wide"):
		var size: Vector2i = root.size
		main.options["aspect"] = PictureShape.ASPECT_WIDE
		root.size = Vector2i(1424, 800)
		await _hurt_at(30, 12.0)
		await _snap("hurt_wide_30")
		main.options["aspect"] = 0
		root.size = size
	if _want("hurt_rampage"):
		var g := await _hurt_at(25, 10.0)
		var r := Rampage.of(g)
		if r != null:
			r._grow(0)
			r.meters[0] = 1.0
			r.until[0] = g.clock + Rampage.LENGTH
			r.began[0] = g.clock
			_ticks(g, .6)
			await _snap("hurt_rampage_25")


func _hurt_at(health: int, blow: float) -> Game:
	var g := _level("hickston")
	var at := Vector2(60.5, 44.5)
	_stand(g, at, _open(g, at, 120))
	g.armory.holstered = false
	g.armory.lower = 0.0
	_ticks(g, .2)
	g.cheats.god = false
	var p := g.player
	p.health = health + int(blow)
	var a := p.angle
	var from := Vector2(p.x, p.y) + Vector2(cos(a), sin(a)) * 4.0 + Vector2(sin(a), -cos(a)) * 2.0
	g.damage(blow, [from.x, from.y], "BUCKSHOT")
	p.health = health
	_ticks(g, .3)
	await process_frame
	return g


## Hands firing in the dark: the ridge by night, and a county blackout in
## Hickston (the flashlight on), each before and as the shots go.
func _muzzles() -> void:
	var g := _level("moonshine")
	_stand(g, Vector2(47.3, 73.5), -1.67)
	var cast: Array[Enemy] = []
	for row: Array in [["billy", 6.0, 1.0], ["revenooer", 9.5, -1.2]]:
		cast.append(_hand(g, str(row[0]), _spot(g, float(row[1]), float(row[2]))))
	_ticks(g, .1)
	await _snap("muzzle_night_0_before")
	await _fire(g, cast, "muzzle_night")
	g = _level("hickston")
	_stand(g, Vector2(7.5, 69.5), .05, -6.0)
	var county: CountyEvents = g.features["events"]
	g.player.flow.update(g.player.x, g.player.y, g.clock)
	if county.begin("blackout"):
		_ticks(g, county.n("blackout", "fade") + .2)
	cast.clear()
	for row: Array in [["coot", 6.0, -2.2], ["billy", 9.0, 2.4]]:
		cast.append(_hand(g, str(row[0]), _spot(g, float(row[1]), float(row[2]))))
	_ticks(g, .1)
	await _snap("muzzle_blackout_0_before")
	await _fire(g, cast, "muzzle_blackout")


## Each of `cast` fires at the player as its brain would (play's own attack),
## then a tick and a few on.
func _fire(g: Game, cast: Array[Enemy], name: String) -> void:
	g.cheats.god = true
	var p := g.player
	for e: Enemy in cast:
		var aim := atan2(p.y - e.y, p.x - e.x)
		var far := Vector2(p.x - e.x, p.y - e.y).length()
		e.attack(g, aim, far, e.z + e.height * .7, p.eye)
		e.recovery = e.recovery_time()
	_ticks(g, STEP)
	await _snap(name + "_1_shot")
	_ticks(g, .05)
	await _snap(name + "_2_after")


## The newer guns' brass: each fired (or a revolver reloaded) a few times,
## caught in the air, then all of it lying on the ground.
func _casings() -> void:
	var g := _level("hickston")
	var at := Vector2(60.5, 44.5)
	var a := _open(g, at, 120)
	_stand(g, at, a, -24.0)
	var guns := [
		"county45", "star357", "hogleg", "riot_pump", "tommy", "grease_gun", "marksman", "hunter"
	]
	for gun_name: String in guns:
		var gun := Weapons.NAMES.find(gun_name)
		if gun < 0:
			continue
		_take(g, gun)
		_ticks(g, .25)
		var shots := 3 if gun_name in ["tommy", "grease_gun"] else 1
		for k in shots:
			_ticks(g, STEP, true)
			_ticks(g, .12)
		if gun_name in ["star357", "hogleg"]:
			g.armory.loaded[gun] = 0
			var c := Game.Controls.new()
			c.reload = true
			g.tick(STEP, c)
			_ticks(g, .45)
		else:
			_ticks(g, .08)
		await _snap("casings_%s" % gun_name)
		_ticks(g, .05)
	# Stepped back off to the left, looking across where the brass lies (the
	# view leaves out what is right at the eye).
	var right := Vector2(-sin(a), cos(a))
	_stand(g, at - right * 1.1, a + PI * .5, -34.0)
	g.armory.holstered = true
	g.armory.lower = 1.0
	_ticks(g, .6)
	await _snap("casings_ground")
	_stand(g, at - right * 1.5 + Vector2(cos(a), sin(a)) * .2, a + PI * .5, -60.0)
	await _snap("casings_close")


func _take(g: Game, gun: int) -> void:
	var arms := g.armory
	arms.owned[gun] = true
	arms.reserve[gun] = maxi(Weapons.MAX_RESERVE[gun], 1)
	arms.loaded[gun] = Weapons.CAPACITY[gun]
	arms.active = gun
	arms.switch = 0.0
	arms.cooldown = 0.0
	arms.reload = 0.0
	arms.holstered = false
	arms.lower = 0.0


## The muzzle after a burst of the tommy gun and a load of buckshot: a beat
## after, and longer after.
func _smoke() -> void:
	for row: Array in [["tommy", 1.0], ["shotgun", 0.0], ["hogleg", 0.0]]:
		var g := _level("hickston")
		var at := Vector2(60.5, 44.5)
		_stand(g, at, _open(g, at, 120), 2.0)
		var gun := Weapons.NAMES.find(str(row[0]))
		_take(g, gun)
		_ticks(g, .5)
		var held: float = row[1]
		if held > 0.0:
			_ticks(g, held, true)
		else:
			_ticks(g, STEP, true)
		_ticks(g, .45)
		await _snap("smoke_%s_0" % row[0])
		_ticks(g, .7)
		await _snap("smoke_%s_1" % row[0])


## The way from `at` with the longest run of open, level floor (at most
## `most` tenths of a cell), to look along; `_open_run` is how far it runs.
func _open(g: Game, at: Vector2, most: int) -> float:
	var best := 0.0
	_open_run = 0.0
	var longest := -1
	for k in 32:
		var a := k * TAU / 32.0
		var z := g.world.elevation(at.x, at.y)
		var run := 0
		for s in range(1, most + 1):
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
			_open_run = run / 10.0
	return best
