## Port of main.py's Desktop: window/letterbox presentation, the front-end state
## machine (title, setup, slots, replays, controls, credits, play), the fixed-step
## accumulator and all keyboard/mouse/gamepad input.
##
## The 320x200 RGB frame is uploaded to a TextureRect and graded by
## palette.gdshader, which is the Godot equivalent of period_palette.apply().
extends MainInput


func _ready() -> void:
	_parse_smoke()
	get_window().title = TITLE
	web = OS.has_feature("web")
	mobile = (
		OS.has_feature("android")
		or OS.has_feature("ios")
		or OS.has_feature("web_android")
		or OS.has_feature("web_ios")
	)

	art = Assets.new()
	hud = HUD.new(art)
	menu = Menu.new(art)
	sound = Sound.new(art)
	add_child(sound)

	canvas = Canvas.new()

	frame_image = Image.create_empty(WIDTH, HEIGHT, false, Image.FORMAT_RGB8)
	frame_texture = ImageTexture.create_from_image(frame_image)

	var backdrop := ColorRect.new()
	backdrop.color = Color(12 / 255.0, 9 / 255.0, 8 / 255.0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	view = TextureRect.new()
	view.texture = frame_texture
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)

	palette_material = ShaderMaterial.new()
	palette_material.shader = load("res://src/palette.gdshader")
	var lut_image := Image.create_empty(256, 128, false, Image.FORMAT_RGB8)
	lut_image.set_data(256, 128, false, Image.FORMAT_RGB8, art.palette)
	palette_material.set_shader_parameter("lut", ImageTexture.create_from_image(lut_image))
	if art.grain.size() == 936 * WIDTH:
		var grain_image := Image.create_from_data(936, WIDTH, false, Image.FORMAT_R8, art.grain)
		palette_material.set_shader_parameter("grain", ImageTexture.create_from_image(grain_image))
		gpu_ready = DisplayServer.get_name() != "headless"
	palette_material.set_shader_parameter("post_tex", frame_texture)
	palette_material.set_shader_parameter("frame_tex", frame_texture)
	layers = SceneLayers.new(palette_material, art)
	view.material = palette_material
	_start_overlay()

	# A plain black sheet over the picture: a tenth of a second of dip between
	# menu screens instead of a hard cut.
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)

	# Drawn at window resolution over the scaled canvas, like the reference.
	touch = TouchControls.new()
	add_child(touch)

	options = SessionStore.settings("")
	unlocked = SessionStore.unlocks("")
	hub_findings = SessionStore.road_notes("")
	apply_options()
	if mobile and not web:
		# A phone is always fullscreen. The reference stretched the picture to
		# the whole panel there; this build letterboxes it unless the player
		# picks FULLSCREEN (FILL) in setup.
		fullscreen = true
		fullscreen_mode = 1 if int(options["window_mode"]) == 1 else 2
	elif (
		int(options["window_mode"]) != 0
		and not smoke
		and not web
		and view_tour == ""
		and view_bench == 0
	):
		# A browser only grants fullscreen from a click or key, never at boot.
		change_window_mode(int(options["window_mode"]))
	_apply_view()

	if smoke_frames > 0 and smoke_screen != "":
		var parts := smoke_screen.split(":")
		state = parts[0]
		if parts.size() > 1:
			option_page = clampi(int(parts[1]), 0, SessionStore.setup_pages().size() - 1)
			controls_page = clampi(int(parts[1]), 0, CONTROL_PAGES.size() - 1)
		if parts.size() > 2:
			option_slot = clampi(int(parts[2]), 0, option_items().size() - 1)
		if state == "slots":
			show_slots("load")
	elif smoke_frames > 0:
		render()
		start(smoke_level)


func _view_tour() -> void:
	touring = true
	await get_tree().process_frame
	var shots = JSON.parse_string(FileAccess.get_file_as_string(view_tour))
	var loaded := ""
	for shot: Dictionary in shots:
		var level_id := String(shot["level"])
		if level_id != loaded or game == null:
			start(level_id)
			loaded = level_id
		var p := game.player
		p.x = float(shot["x"])
		p.y = float(shot["y"])
		p.angle = float(shot["angle"])
		p.eye = .95 + game.world.elevation(p.x, p.y)
		p.pitch = float(shot.get("pitch", 0.0))
		p.drunk = float(shot.get("drunk", 0.0))
		p.sway = 0.0
		game.message_until = 0.0
		game.district_until = 0.0
		var armed := bool(shot.get("weapon", false))
		game.armory.holstered = not armed
		game.armory.lower = 0.0 if armed else 1.0
		if shot.has("detail"):
			game.renderer.set_detail(int(shot["detail"]))
		if shot.has("ticks"):
			var held := Game.Controls.new()
			held.fire = bool(shot.get("fire", false))
			held.forward = float(shot.get("forward", 0.0))
			for i in int(shot["ticks"]):
				game.tick(1.0 / 60.0, held)
		for mode in ["gpu", "cpu"]:
			cpu_view = mode == "cpu"
			render()
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
				"%s/%s_%s.png" % [view_out, String(shot["tag"]), mode]
			)
	get_tree().quit()


func _view_bench() -> void:
	touring = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await get_tree().process_frame
	var totals := {"cpu": 0.0, "gpu": 0.0}
	for level_id in ["hickston", "fair", "sawmill", "quarry"]:
		var line := "%-9s" % level_id
		for mode in ["cpu", "gpu"]:
			start(level_id)
			Engine.max_fps = 0
			cpu_view = mode == "cpu"
			var held := Game.Controls.new()
			held.turn = .3
			held.fire = true
			for i in 20:
				game.tick(1.0 / 60.0, held)
				render()
				await get_tree().process_frame
			var began := Time.get_ticks_usec()
			var busy := 0
			var drawing := 0
			for i in view_bench:
				var t0 := Time.get_ticks_usec()
				game.tick(1.0 / 60.0, held)
				var t1 := Time.get_ticks_usec()
				render()
				var t2 := Time.get_ticks_usec()
				busy += t2 - t0
				drawing += t2 - t1
				await get_tree().process_frame
			var each := (Time.get_ticks_usec() - began) / 1000.0 / view_bench
			totals[mode] += each
			line += (
				"  %s %6.2f ms (%4.0f fps; work %.2f, render() %.2f)"
				% [
					mode,
					each,
					1000.0 / each,
					busy / 1000.0 / view_bench,
					drawing / 1000.0 / view_bench
				]
			)
		print(line)
	print(
		(
			"WINDOW    software view %.2f ms (%.0f fps)   shader view %.2f ms (%.0f fps)   x%.2f"
			% [
				totals["cpu"] / 4.0,
				4000.0 / totals["cpu"],
				totals["gpu"] / 4.0,
				4000.0 / totals["gpu"],
				totals["cpu"] / totals["gpu"]
			]
		)
	)
	get_tree().quit()


func _process(delta: float) -> void:
	if touring:
		return
	if view_bench > 0:
		_view_bench()
		return
	if view_tour != "":
		_view_tour()
		return
	# The engine paces frames to the FRAME LIMIT option (apply_options sets
	# Engine.max_fps), which is what the reference's clock.tick() does. A
	# browser ignores that cap and calls back once per display refresh, so
	# there the frame is skipped until most of the target interval has passed.
	pending_dt += delta
	if web and pending_dt < frame_interval() * 0.75:
		return
	var dt := minf(0.08, pending_dt)
	pending_dt = 0.0

	touch.tick(dt)
	if demo:
		_demo(dt)
	if showcase:
		_showcase(dt)
	menu_clock += dt
	if state != shown_state:
		shown_state = state
		screen_age = 0.0
	screen_age += dt
	# A short dip to black between screens; none with SCENERY MOTION on STATIC.
	var dip := 0.0
	if int(options.get("world_motion", 0)) != 2 and state != "play":
		dip = clampf(1.0 - screen_age / .14, 0.0, 1.0) * .6
	fade.color.a = dip
	if reset_armed > 0.0:
		reset_armed -= dt
		if reset_armed <= 0.0 and state == "setup":
			menu_note = ""
	if not display_trial.is_empty():
		display_trial["left"] = float(display_trial["left"]) - dt
		if float(display_trial["left"]) <= 0.0 or state != "setup":
			settle_display(false)
	var pad := read_pad(dt)
	var fingers := touch.state()
	if state == "play" and game != null:
		_touch_actions()
		_watch_pointer_lock()

	if state == "play" and game != null:
		if not focused:
			var neutral := Game.Controls.new()
			neutral.fire = game.armory.fuse > 0.0
			advance(dt, neutral)
		else:
			if showcase:
				advance(dt, _showcase_controls())
			else:
				advance(dt, _demo_controls(dt) if demo else _controls(dt, pad, fingers))
			if game.player.health <= 0:
				sound.pause_score(true)
			if game.showing_tally or game.player.health <= 0:
				grab(false)

	sound.tick_score(dt)
	render()
	mouse_rel = Vector2.ZERO

	if smoke_frames > 0:
		frame_count += 1
		if frame_count >= smoke_frames:
			if smoke_shot != "":
				var shot := Image.create_empty(WIDTH, HEIGHT, false, Image.FORMAT_RGB8)
				shot.set_data(WIDTH, HEIGHT, false, Image.FORMAT_RGB8, canvas.pixels)
				shot.save_png(smoke_shot)
			_write_marker()
			if view_shot != "":
				smoke_frames = 0
				_save_view()
				return
			get_tree().quit()


func _demo(dt: float) -> void:
	demo_clock += dt
	while demo_step < DEMO_KEYS.size() and demo_clock >= float(DEMO_KEYS[demo_step][0]):
		key(int(DEMO_KEYS[demo_step][1]))
		demo_step += 1
	if demo_clock > 45.0:
		get_tree().quit()


## One weapon every SHOWCASE_SECONDS: draw it, fire, alternate fire, reload.
func _showcase(dt: float) -> void:
	if state != "play" or game == null:
		if demo_clock == 0.0 and state == "title":
			start("hickston")
		return
	if showcase_slot < 0:
		game.cheats.god = true
		game.cheats.apply("hickguns", game)
		for i in Weapons.COUNT:
			game.armory.loaded[i] = Weapons.CAPACITY[i]
	demo_clock += dt
	var slot := int(demo_clock / SHOWCASE_SECONDS)
	if showcase_only >= 0:
		if slot > 0:
			get_tree().quit()
			return
		slot = showcase_only
	if slot >= Weapons.COUNT:
		get_tree().quit()
		return
	if slot != showcase_slot:
		showcase_slot = slot
		game.player.health = 100
		if game.armory.active == slot:
			game.armory.select(Weapons.CROWBAR if slot else Weapons.REVOLVER, game)
		game.armory.select(slot, game)
	var t := fmod(demo_clock, SHOWCASE_SECONDS)
	if t >= 4.3 and t - dt < 4.3:
		game.armory.start_reload(game)


func _showcase_controls() -> Game.Controls:
	var controls := Game.Controls.new()
	var t := fmod(demo_clock, SHOWCASE_SECONDS)
	controls.fire = t > 1.0 and t < 2.9
	controls.alt_fire = t > 3.3 and t < 3.9
	return controls


## Walk up the county road, sweep the view and keep shooting.
func _demo_controls(dt: float) -> Game.Controls:
	var controls := Game.Controls.new()
	var t := demo_clock
	controls.forward = 1.0 if fmod(t, 6.0) < 4.2 else 0.0
	controls.turn = sin(t * .9) * dt * .9
	controls.fire = fmod(t, 1.1) < .25 and t > 22.0
	controls.alt_fire = t > 30.0 and fmod(t, 2.6) < .12
	controls.running = t > 28.0
	return controls


func advance(elapsed: float, controls: Game.Controls) -> void:
	accumulator = minf(.1, accumulator + elapsed)
	pending_turn += controls.turn
	pending_look += controls.look
	var steps := int((accumulator + 1e-9) / SIM_STEP)
	if steps == 0:
		return
	accumulator = maxf(0.0, accumulator - steps * SIM_STEP)
	controls.turn = pending_turn / steps
	controls.look = pending_look / steps
	pending_turn = 0.0
	pending_look = 0.0
	for _i in steps:
		game.tick(SIM_STEP, controls)
		if game.portal_request != "":
			travel(game.portal_request)
			break
