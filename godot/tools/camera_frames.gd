## Pictures of PHOTO MODE, the KILL CAM and the HUD's Control nodes in a real
## window (the graphics-card view players see): the HUD in the campaign
## (full and MINIMAL), in a 5v5 round and in COUNTY RUN; PHOTO MODE from
## behind the player with each filter, and a picture saved through it; a
## kill replayed from the KILL CAM's camera. <name>.png in out=<dir>.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/camera_frames.gd -- out=<dir>
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

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
	print("HUD on Controls: ", main.hud_layer != null)
	await _hud()
	await _photo()
	await _kill_cam()
	print("camera frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _snap(name: String) -> void:
	var g: Game = main.game
	if g != null:
		g.message_until = 0.0
		g.callout_until = 0.0
		g.district_until = 0.0
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))


func _hud() -> void:
	main.start("hickston")
	main.state = "play"
	var g: Game = main.game
	g.barks.enabled = false
	for i in 30:
		g.tick(1.0 / 60.0, Game.Controls.new())
	await _snap("hud_full")
	main.options["hud_mode"] = 1
	main.apply_options()
	await _snap("hud_minimal")
	main.options["hud_mode"] = 0
	main.apply_options()
	var squad: Game = main.make_game("grainyard")
	squad.configure(main.options)
	Modes.setup(squad, Modes.BOMB, 10, {"arena": "grainyard"})
	for i in 60:
		squad.tick(1.0 / 120.0, Game.Controls.new())
	TacticalScreens.human = 0
	main.game = squad
	await _snap("hud_5v5")
	var run: Game = main.make_game("county_hickston")
	run.configure(main.options)
	Modes.setup(run, Modes.COUNTY, 1)
	run.tick(1.0 / 120.0, Game.Controls.new())
	var f = run.features["county"]
	f.next_spawn = 1e9
	main.game = run
	await _snap("hud_county")


func _photo() -> void:
	main.start("hickston")
	main.state = "play"
	var g: Game = main.game
	g.barks.enabled = false
	for i in 30:
		g.tick(1.0 / 60.0, Game.Controls.new())
	var photo: PhotoMode = main.photo
	photo.enter(main)
	# Back and up a little, turned round to look at the player.
	var back := Game.Controls.new()
	back.forward = -1.0
	back.strafe = -.4
	for i in 70:
		photo.frame(main, 1.0 / 60.0, back)
	var round := Game.Controls.new()
	round.look = -1.0
	round.turn = .005
	round.jump = true
	for i in 12:
		photo.frame(main, 1.0 / 60.0, round)
	for k in PhotoMode.FILTERS.size():
		photo.filter = k
		await _snap("photo_" + PhotoMode.FILTERS[k].to_lower())
	photo.filter = 2
	photo.out_dir = out
	main.render()
	photo.save(main)
	for i in 4:
		main.render()
		await process_frame
	print("photo saved: ", photo.last_saved)
	photo.leave(main)


func _kill_cam() -> void:
	main.options["kill_cam"] = KillCam.AREAS
	main.apply_options()
	main.start("hickston")
	main.state = "play"
	var g: Game = main.game
	g.barks.enabled = false
	var cam: KillCam = main.kill_cam
	var p: Player = g.player
	var fight: Array = []
	for e: Enemy in g.enemies:
		if e.alive and e.hostile and fight.size() < KillCam.FIGHT:
			fight.append(e)
		else:
			e.dormant = true
	for i in fight.size():
		var e: Enemy = fight[i]
		e.x = p.x + cos(p.angle) * (3.0 + i * .8) + sin(p.angle) * (i - 1) * .7
		e.y = p.y + sin(p.angle) * (3.0 + i * .8) - cos(p.angle) * (i - 1) * .7
		e.dormant = false
		e.alerted = true
	var still := Game.Controls.new()
	for n in 20:
		g.tick(1.0 / 60.0, still)
		main.render()
	for e: Enemy in fight:
		e.hurt(99999.0, g)
		for n in 12:
			g.tick(1.0 / 60.0, still)
			main.render()
	var waited := 0
	while not cam.ready(main) and waited < 200:
		g.tick(1.0 / 60.0, still)
		main.render()
		waited += 1
	print("kill cam ready: ", cam.ready(main))
	if not cam.start(main):
		return
	var shots := 0
	var step := 0
	while cam.playing:
		if step % 40 == 10 and shots < 3:
			shots += 1
			await _snap("killcam_%d" % shots)
		cam.frame(main, 1.0 / 60.0)
		main.render()
		await process_frame
		step += 1
