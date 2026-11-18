## PHOTO MODE, the KILL CAM, the QUALITY tiers and the HUD's Control nodes,
## headless (src/photo_mode.gd, src/kill_cam.gd, src/core/quality.gd,
## src/ui/hud/):
##
##   Godot --headless --path <project> --script res://tools/camera_check.gd
##
## - QUALITY: the tier from a measured frame time and the device, what each
##   tier sets, AUTO's measurement, the physics detail and its steps (HIGH
##   whenever several play).
## - The HUD on Controls: the status bar composed from its boxes over the
##   plate is HUD's own drawing pixel for pixel (campaign, 5v5, COUNTY RUN,
##   full and MINIMAL), and each mode's boxes are there.
## - PHOTO MODE: P opens it at the player's eye, the camera flies (and not
##   through walls or past its reach), the view is drawn from it with the
##   player in sight, the strip shows, a filter turns, a picture is saved at
##   its size, ESC leaves; nothing of play moved (the game's snapshot is the
##   same), and it will not open for a player who is down.
## - The KILL CAM: the last foe of a fight noted, sampled, replayed from its
##   own camera with stand-in bodies, play untouched (snapshot, clock, view
##   frame); it waits for slow motion; a key and a tap skip it; OFF records
##   nothing.
## Fails on any script or engine error.
extends SceneTree

var failures: Array = []
var main


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	var tally := CrashLog.tally()
	_quality()
	_hud()
	_photo()
	_kill_cam()
	preload("res://tools/view_polish_check.gd").run(main, _check)
	tally.stop()
	_check(
		tally.errors == 0,
		(
			"no script or engine errors"
			+ ("" if tally.errors == 0 else " (%d: %s)" % [tally.errors, tally.first_errors[0]])
		)
	)
	print("")
	print("CAMERA CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)
		if OS.get_environment("GITHUB_ACTIONS") != "":
			print("::error title=%s::%s" % [get_script().resource_path.get_file(), text])


# ------------------------------------------------------------------ quality


func _quality() -> void:
	print("QUALITY")
	_check(Quality.pick(false, 4.0) == Quality.HIGH, "a quick frame on a computer: HIGH")
	_check(Quality.pick(false, 9.0) == Quality.MEDIUM, "a middling frame: MEDIUM")
	_check(Quality.pick(false, 20.0) == Quality.LOW, "a slow frame: LOW")
	_check(Quality.pick(true, 4.0) == Quality.MEDIUM, "a phone, however quick, starts at MEDIUM")
	_check(Quality.device_tier(true) == Quality.MEDIUM, "a phone's guess before measuring")
	var low := Quality.preset(Quality.LOW)
	_check(
		(
			low["detail"] == 1
			and low["draw_distance"] == 2
			and low["lights"] == 0
			and low["shadows"] == 0
		),
		"LOW: half detail, near, no lights, no shadows"
	)
	var high := Quality.preset(Quality.HIGH)
	_check(
		high["detail"] == 2 and high["draw_distance"] == 1 and high["lights"] == 1,
		"HIGH: the old defaults (detail AUTO, far, lights)"
	)
	_check(Quality.tier_of(2, -1, false) == Quality.MEDIUM, "MEDIUM picked is MEDIUM")
	_check(Quality.tier_of(0, Quality.LOW, false) == Quality.LOW, "AUTO is what it measured")
	_check(Quality.tier_of(0, -1, true) == Quality.MEDIUM, "AUTO unmeasured is the device's guess")
	var meter := Quality.Meter.new(false)
	var tier := -1
	var frames := 0
	while tier < 0 and frames < 2000:
		tier = meter.add(1.0 / 60.0, 10.0)
		frames += 1
	_check(tier == Quality.MEDIUM, "AUTO's meter: 10 ms frames are MEDIUM (%d)" % tier)
	_check(
		frames >= int((Quality.SETTLE + Quality.MEASURE) * 60.0) - 1,
		"after settling and measuring (%d frames)" % frames
	)
	var was: int = Quality.physics
	Quality.physics = Quality.LOW
	Quality.shared = false
	_check(Quality.steps(6) == 3, "LOW physics: the pins step half as often")
	Quality.shared = true
	_check(Quality.steps(6) == 6, "with several players every copy steps at HIGH")
	Quality.shared = false
	Quality.physics = was
	main.options["quality"] = 1
	main.options = main.options.duplicate()
	main.call("_quality_picked")
	_check(
		main.options["detail"] == 1 and main.options["lights"] == 0,
		"QUALITY LOW in setup sets detail and lights"
	)
	main.apply_options()
	_check(Quality.physics == Quality.LOW, "and the physics detail")
	main.options["quality"] = 0
	main.options.merge(Quality.preset(Quality.HIGH), true)
	main.apply_options()


# ------------------------------------------------------------------ hud


func _hud() -> void:
	print("THE HUD ON CONTROLS")
	var holder := SubViewport.new()
	holder.size = Vector2i(320, 200)
	holder.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(holder)
	var layer := HudLayer.new(main.hud)
	holder.add_child(layer)
	var games := {"campaign": main.make_game("hickston")}
	var squad: Game = main.make_game("grainyard")
	squad.configure({"difficulty": 1})
	Modes.setup(squad, Modes.BOMB, 10, {"arena": "grainyard"})
	for i in 30:
		squad.tick(1.0 / 120.0, Game.Controls.new())
	TacticalScreens.human = 0
	games["5v5"] = squad
	var run: Game = main.make_game("county_hickston")
	run.configure({"difficulty": 1})
	Modes.setup(run, Modes.COUNTY, 1)
	run.tick(1.0 / 120.0, Game.Controls.new())
	games["county"] = run
	for minimal: bool in [false, true]:
		main.hud.minimal = minimal
		for name: String in games:
			var g: Game = games[name]
			var c := Canvas.new()
			main.hud.draw(c, g, g.armory)
			var drawn := Image.create_from_data(
				320, 44, false, Image.FORMAT_RGB8, c.pixels.slice(156 * 320 * 3)
			)
			layer.show_for(g, g.armory)
			var made: Image = layer.composed()
			var off := _first_off(made, drawn)
			_check(
				off == "",
				(
					"%s%s: the bar from its Control boxes is the drawn bar, pixel for pixel%s"
					% [name, " MINIMAL" if minimal else "", off]
				)
			)
			_check(
				layer.visible and layer.bar.position == Vector2(0, 156),
				"%s: shown at the foot" % name
			)
		_check(
			layer.boxes["face"].visible != minimal,
			"the face box %s" % ("hidden in MINIMAL" if minimal else "shown")
		)
	main.hud.minimal = false
	var campaign: Game = games["campaign"]
	campaign.hints = true
	campaign.map = false
	layer.show_for(campaign, campaign.armory)
	_check(layer.pin.visible, "the objective pin is a Control of the HUD")
	main.hud.minimal = true
	layer.show_for(campaign, campaign.armory)
	_check(not layer.pin.visible, "and MINIMAL leaves it off")
	main.hud.minimal = false
	layer.show_for(null, null)
	_check(not layer.visible, "no game, no HUD")
	holder.queue_free()


## "" when the two pictures are the same, else where they first differ.
static func _first_off(a: Image, b: Image) -> String:
	if a.get_size() != b.get_size():
		return " (sizes %s and %s)" % [a.get_size(), b.get_size()]
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				return " (first off at %d, %d)" % [x, y]
	return ""


# ------------------------------------------------------------------ photo


func _photo() -> void:
	print("PHOTO MODE")
	main.start("hickston")
	main.state = "play"
	var g: Game = main.game
	for i in 10:
		g.tick(1.0 / 60.0, Game.Controls.new())
	main.render()
	var before := GameSnapshot.capture(g)
	var clock: float = g.clock
	var p: Player = g.player
	var at := Vector2(p.x, p.y)
	main.key(KEY_P)
	var photo: PhotoMode = main.photo
	_check(photo.on and not g.eye_override.is_empty(), "P opens PHOTO MODE")
	var fly := Game.Controls.new()
	fly.forward = 1.0
	fly.turn = .02
	for i in 60:
		photo.frame(main, 1.0 / 60.0, fly)
		main.render()
	var moved := Vector2(photo.x, photo.y).distance_to(at)
	_check(moved > .5, "the camera flies (%.2f cells)" % moved)
	_check(
		not g.world.blocked(photo.x, photo.y, 0.0, photo.z - .5), "and never into a wall or post"
	)
	fly.forward = 0.0
	fly.jump = true
	var low: float = photo.z
	for i in 30:
		photo.frame(main, 1.0 / 60.0, fly)
	_check(photo.z > low, "JUMP lifts it")
	fly.jump = false
	main.render()
	var eye: Dictionary = g.view_frame.get("eye", {})
	_check(
		(
			absf(float(eye.get("x", 0.0)) - photo.x) < .001
			and absf(float(eye.get("eye", 0.0)) - photo.z) < .001
		),
		"the view is drawn from the camera"
	)
	var body := false
	for s: Variant in g.view_frame.get("sprites", []):
		if s is View.Sprite and (s as View.Sprite).who is Enemy:
			var who := (s as View.Sprite).who as Enemy
			body = body or (who.kind == ModeBodies.PLAYER_KIND and not g.enemies.has(who))
	_check(body, "the player stands in the view as Mundell")
	var strip: PackedByteArray = main.canvas.pixels.slice(
		(180 * 320 + 2) * 3, (180 * 320 + 2) * 3 + 3
	)
	_check(
		strip[0] == 22 and strip[1] == 16 and strip[2] == 13, "the strip at the foot, no status bar"
	)
	main.key(KEY_R)
	_check(photo.filter == 1, "R turns to the next filter (%s)" % PhotoMode.FILTERS[photo.filter])
	photo.out_dir = OS.get_cache_dir().path_join("clmr_photo_check")
	main.key(KEY_ENTER)
	var saved := photo.last_saved
	var picture := Image.load_from_file(saved) if saved != "" else null
	_check(
		(
			picture != null
			and picture.get_width() == 320 * PhotoMode.SCALE
			and picture.get_height() == 156 * PhotoMode.SCALE
		),
		"ENTER saves the view's picture at %dx its size (%s)" % [PhotoMode.SCALE, saved.get_file()]
	)
	if saved != "":
		DirAccess.remove_absolute(saved)
	var gun: int = g.armory.active
	main.key(KEY_2)
	main.key(KEY_SEMICOLON)
	_check(g.armory.active == gun, "play's keys do nothing meanwhile (the gun stays)")
	main.key(KEY_ESCAPE)
	_check(
		not photo.on and g.eye_override.is_empty() and main.state == "play",
		"ESC leaves it, back in play"
	)
	var after := GameSnapshot.capture(g)
	_check(
		GameSnapshot.same(before, after),
		"nothing of play moved: " + GameSnapshot.first_difference(before, after)
	)
	_check(g.clock == clock, "the game's clock held still")
	p.health = 0
	_check(not PhotoMode.allowed(main) and not photo.enter(main), "not for a player who is down")
	p.health = 100


# ------------------------------------------------------------------ kill cam


func _kill_cam() -> void:
	print("THE KILL CAM")
	main.options["kill_cam"] = KillCam.AREAS
	main.apply_options()
	main.start("hickston")
	main.state = "play"
	var g: Game = main.game
	var cam: KillCam = main.kill_cam
	var p: Player = g.player
	var fight: Array[Enemy] = []
	for e: Enemy in g.enemies:
		if e.alive and e.hostile and fight.size() < KillCam.FIGHT:
			fight.append(e)
		else:
			e.dormant = true
	for i in fight.size():
		var e := fight[i]
		e.x = p.x + cos(p.angle) * (3.0 + i)
		e.y = p.y + sin(p.angle) * (3.0 + i)
		e.dormant = false
	_check(fight.size() == KillCam.FIGHT, "a fight of %d" % fight.size())
	var still := Game.Controls.new()
	_frames(g, 20, still)
	for e in fight:
		e.hurt(99999.0, g)
		_frames(g, 12, still)
	_check(not cam.pending.is_empty(), "the last foe of the fight is noted")
	_check(cam.moments.size() >= 4, "the view was sampled (%d moments)" % cam.moments.size())
	g.slowmo = 1.0
	_check(not cam.ready(main), "it waits while slow motion runs")
	g.slowmo = 0.0
	var waited := 0
	while not cam.ready(main) and waited < 120:
		_frames(g, 1, still)
		waited += 1
	_check(cam.ready(main), "then starts once the moment has played out")
	var before := GameSnapshot.capture(g)
	var clock: float = g.clock
	var frame_before: Dictionary = g.view_frame
	_check(cam.start(main) and cam.playing, "the replay starts")
	var stand_ins := 0
	var eye_away := false
	var shown := 0
	while cam.playing and shown < 600:
		var f: Dictionary = cam.frame_at(g, cam.at)
		for s: Variant in f["sprites"]:
			if s is View.Sprite and (s as View.Sprite).who is Enemy:
				if not g.enemies.has((s as View.Sprite).who):
					stand_ins += 1
		var e: Dictionary = f["eye"]
		eye_away = eye_away or Vector2(float(e["x"]) - p.x, float(e["y"]) - p.y).length() > .5
		main.render()
		cam.frame(main, 1.0 / 60.0)
		shown += 1
	_check(not cam.playing and shown > 60, "it plays out and ends (%d frames)" % shown)
	_check(stand_ins > 0, "the bodies are stand-ins only the view reads (%d)" % stand_ins)
	_check(eye_away, "seen from another place than the player's eye")
	var after := GameSnapshot.capture(g)
	_check(
		GameSnapshot.same(before, after),
		"play untouched: " + GameSnapshot.first_difference(before, after)
	)
	_check(
		g.clock == clock and g.view_frame == frame_before,
		"the clock and the view frame as they were"
	)
	# A key, and a tap, skip it.
	for how: String in ["key", "tap"]:
		cam.pending = {"clock": g.clock, "x": p.x + 2.0, "y": p.y, "floor": 0.0, "height": 1.0}
		_frames(g, 50, still)
		var began: bool = cam.start(main)
		if how == "key":
			main.key(KEY_SPACE)
		else:
			var finger := InputEventScreenTouch.new()
			finger.pressed = true
			main._input(finger)
		_check(began and not cam.playing, "a %s skips it" % how)
	main.options["kill_cam"] = KillCam.OFF
	main.apply_options()
	_frames(g, 10, still)
	_check(cam.moments.is_empty(), "OFF samples nothing")
	main.options["kill_cam"] = KillCam.BOSSES
	main.apply_options()
	_boss_fall()


## BOSSES (the default): no replay at all now; a boss's fall is the boss
## ending's (src/boss_ending.gd, tools/boss_end_check.gd), shown live.
func _boss_fall() -> void:
	main.start("hickston")
	main.state = "play"
	var g: Game = main.game
	var cam: KillCam = main.kill_cam
	var p: Player = g.player
	var still := Game.Controls.new()
	for e: Enemy in g.enemies:
		e.dormant = true
	var kind := ""
	for k: String in Enemy.BOSS_TITLES:
		if kind == "" and Enemy.DEFS.has(k):
			kind = k
	var boss := Enemy.new(kind, p.x + cos(p.angle) * 4.0, p.y + sin(p.angle) * 4.0, 0.0)
	g.enemies.append(boss)
	g.enemy_ids.append("check-boss")
	boss.alerted = true
	_frames(g, 45, still)
	_check(cam.moments.is_empty(), "BOSSES samples nothing, a boss (%s) up or not" % kind)
	boss.hurt(9999999.0, g)
	_check(cam.pending.is_empty(), "a boss's fall is left to the boss ending, not replayed")
	main.options["kill_cam"] = KillCam.AREAS
	main.apply_options()
	var other := Enemy.new(kind, p.x + cos(p.angle) * 4.0, p.y + sin(p.angle) * 4.0, 0.0)
	g.enemies.append(other)
	g.enemy_ids.append("check-boss-2")
	other.alerted = true
	_frames(g, 45, still)
	other.hurt(9999999.0, g)
	_check(cam.pending.is_empty(), "nor with BOSSES AND AREAS")
	main.options["kill_cam"] = KillCam.BOSSES
	main.apply_options()


func _frames(g: Game, n: int, held: Game.Controls) -> void:
	for i in n:
		g.tick(1.0 / 60.0, held)
		main.render()
