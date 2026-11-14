## Port of main.py's Desktop: window/letterbox presentation, the front-end state
## machine (title, setup, slots, replays, controls, credits, play), the fixed-step
## accumulator and all keyboard/mouse/gamepad input.
##
## The 320x200 RGB frame is uploaded to a TextureRect and graded by
## palette.gdshader, which is the Godot equivalent of period_palette.apply().
extends MainInput


func _ready() -> void:
	_parse_smoke()
	if server_level != "":
		# A network game's host: no window, picture, sound or menus at all.
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		var options := {"difficulty": server_difficulty}
		add_child(
			ServerLoop.new(server_level, server_players, options, server_ticks, server_report)
		)
		return
	get_window().title = TITLE
	web = OS.has_feature("web")
	# A real launch logs errors and crashes (a tool driving the game does not).
	if not web and Engine.get_main_loop().get_script() == null:
		crash_log = CrashLog.start(self)
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
	_grain_tone(PackedByteArray())
	if art.grain.size() == 936 * WIDTH:
		gpu_ready = DisplayServer.get_name() != "headless"
	palette_material.set_shader_parameter("post_tex", frame_texture)
	layers = SceneLayers.new(palette_material, art)
	view.material = palette_material
	_start_overlay()
	packs = PackLoader.new()
	add_child(packs)
	if LevelEditor.available():
		editor = LevelEditor.new(self)
	if DevConsole.available():
		console = DevConsole.new(self)

	# A plain black sheet over the picture: a tenth of a second of dip between
	# menu screens instead of a hard cut.
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	var iris := Shader.new()
	iris.code = (
		"shader_type canvas_item;\nuniform float open = 1.0;\nuniform float aspect = 1.6;\n"
		+ "void fragment() {\n\tvec2 d = (UV - 0.5) * vec2(aspect, 1.0);\n"
		+ "\tfloat edge = open * 1.05 * length(vec2(aspect, 1.0)) * 0.5;\n"
		+ "\tCOLOR = vec4(0.0, 0.0, 0.0, open >= 1.0 ? 0.0 : step(edge, length(d)));\n}\n"
	)
	fade.material = ShaderMaterial.new()
	(fade.material as ShaderMaterial).shader = iris
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)

	# Drawn at window resolution over the scaled canvas, like the reference.
	touch = TouchControls.new()
	add_child(touch)

	# A view tour draws with the default settings, never this machine's own
	# (its references must match CI's, which has no profile).
	options = SessionStore.settings("" if view_tour == "" else "res://no_settings.json")
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

	if online_args.has("host") or online_args.has("join"):
		_online_from_args()
	elif play_at != "":
		_play_at()
	elif mode_name != "" and Modes.rules_for(mode_name).versus():
		start_match()  # --mode: the match in its arena (src/modes/)
	elif mode_name != "" and mode_level != "":
		start(mode_level)
	elif smoke_frames > 0 and smoke_screen != "":
		var parts := smoke_screen.split(":")
		state = parts[0]
		if parts.size() > 1:
			option_page = clampi(int(parts[1]), 0, SessionStore.setup_pages().size() - 1)
			controls_page = clampi(int(parts[1]), 0, CONTROL_PAGES.size() - 1)
			selection = int(parts[1])
		if parts.size() > 2:
			option_slot = clampi(int(parts[2]), 0, option_items().size() - 1)
			showdown_mode = int(parts[2])  # "showdown:<row>:<mode>"
		if state == "slots":
			show_slots("load")
	elif smoke_frames > 0:
		render()
		start(smoke_level)
	if console != null and dev_commands != "" and game != null:
		for command in dev_commands.split(";", false):
			console.run(command)
	if state != "play":
		menu_music()  # MENU MUSIC off: the title tune waits paused


## Start the level and place the player as --play-at says.
func _play_at() -> void:
	var parts := play_at.split(":")
	start(parts[0])
	if parts.size() < 2 or game == null:
		return
	var at := parts[1].split(",")
	var p := game.player
	p.x = float(at[0])
	p.y = float(at[1])
	if at.size() > 2:
		p.angle = float(at[2])
	if at.size() > 3:
		# A floor to start on (level format 2: a deck, the Maps screen's floor).
		p.floor_z = game.world.floor_under(p.x, p.y, float(at[3]) + .05)
	p.eye = .95 + game.world.stand(p)


func _view_tour() -> void:
	touring = true
	await get_tree().process_frame
	var shots = JSON.parse_string(FileAccess.get_file_as_string(view_tour))
	var loaded := ""
	for shot: Dictionary in shots:
		var level_id := String(shot["level"])
		if level_id != loaded or game == null or shot.has("done") or shot.has("unlock"):
			# The Crossroads as players get it, its gates locked by the profile
			# (open_hub); "unlock" opens them all. "done" sets every station
			# (or those listed) and clears the exit, to show the after-state.
			if level_id == "hub" and shot.has("hub"):
				open_hub()
			else:
				start(level_id)
			loaded = level_id
			if shot.has("unlock"):
				game.world.locked_gates = []
			if shot.has("done"):
				var listed = shot["done"]
				for station: LevelData.Station in game.world.stations:
					if not (listed is Array) or listed.has(station.id):
						game.stations_done[station.id] = true
				if not (listed is Array):
					for member: Enemy in game.wave:
						member.alive = false
		var p := game.player
		p.x = float(shot["x"])
		p.y = float(shot["y"])
		p.angle = float(shot["angle"])
		p.floor_z = game.world.floor_under(p.x, p.y, float(shot.get("z", 0.0)) + .05)
		p.eye = .95 + game.world.stand(p)
		p.pitch = float(shot.get("pitch", 0.0))
		p.drunk = float(shot.get("drunk", 0.0))
		p.sway = 0.0
		game.message_until = 0.0
		game.district_until = 0.0
		# A viewpoint may hold a notice or the place name up (the objective pin
		# hangs under them).
		if shot.has("notice"):
			game.message(String(shot["notice"]), 99.0)
		if shot.has("district"):
			game.district = int(game.world.area[game.world.cell(p.x, p.y)])
			game.district_until = game.clock + 99.0
		# A viewpoint may open the map, at a zoom (game_view.gd MAP_ZOOMS).
		game.map = bool(shot.get("map", false))
		game.map_zoom = int(shot.get("map_zoom", 2))
		var armed := bool(shot.get("weapon", false))
		game.armory.holstered = not armed
		game.armory.lower = 0.0 if armed else 1.0
		if shot.has("detail"):
			game.renderer.set_detail(int(shot["detail"]))
		if shot.has("gun") and game.armory.active != int(shot["gun"]):
			# A viewpoint of one gun firing: given it, loaded, in hand (viewpoints
			# after it with the same gun go on firing it, frame by frame).
			var g := int(shot["gun"])
			var arms = game.armory
			arms.owned[g] = true
			arms.reserve[g] = maxi(Weapons.MAX_RESERVE[g], 1)
			arms.loaded[g] = Weapons.CAPACITY[g]
			arms.active = g
			arms.switch = 0.0
			arms.cooldown = 0.0
			arms.reload = 0.0
		if shot.has("ticks"):
			var held := Game.Controls.new()
			held.fire = bool(shot.get("fire", false))
			held.forward = float(shot.get("forward", 0.0))
			for i in int(shot["ticks"]):
				game.tick(1.0 / 60.0, held)
		if shot.has("rain"):
			# A viewpoint in the weather: rain this hard, the ground this wet, a
			# lightning flash (features/weather.gd hold()).
			var rain := float(shot["rain"])
			game.features["weather"].hold(
				rain, float(shot.get("wet", rain)), float(shot.get("lightning", 0.0))
			)
		# fx: the shader view as players see it (lights and glows); gpu: the same
		# without them, to hold against the software view (cpu).
		for mode in ["fx", "gpu", "cpu"]:
			cpu_view = mode == "cpu"
			Effects.enabled = mode == "fx"
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
	# The graphics card's own time for each frame (the shader's per-pixel cost,
	# which the frame time hides while the main thread is the slower side).
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var totals := {"cpu": 0.0, "gpu": 0.0}
	for level_id in ["hickston", "fair", "sawmill", "quarry", "bayou", "speedway", "mothership"]:
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
			var card := 0.0
			# The parts: tick, sprites, scene, weapon, look, hud, layers, waiting.
			var parts := PackedFloat64Array()
			parts.resize(8)
			# Each whole frame, for the slow ones (a stutter hides in an average).
			var frames := PackedFloat64Array()
			var last := Time.get_ticks_usec()
			for i in view_bench:
				var t0 := Time.get_ticks_usec()
				game.tick(1.0 / 60.0, held)
				var t1 := Time.get_ticks_usec()
				layers_us = 0
				render()
				var t2 := Time.get_ticks_usec()
				busy += t2 - t0
				drawing += t2 - t1
				parts[0] += t1 - t0
				for k in 5:
					parts[k + 1] += float(game.stage_ms[k]) * 1000.0
				parts[6] += layers_us
				await get_tree().process_frame
				parts[7] += Time.get_ticks_usec() - t2
				frames.append((Time.get_ticks_usec() - last) / 1000.0)
				last = Time.get_ticks_usec()
				card += RenderingServer.viewport_get_measured_render_time_gpu(rid)
			var each := (Time.get_ticks_usec() - began) / 1000.0 / view_bench
			totals[mode] += each
			if mode == "gpu":
				var row := "  parts"
				var names := ["tick", "sprites", "scene", "weapon", "look", "hud", "layers", "wait"]
				for k in 8:
					row += " %s %.2f" % [names[k], parts[k] / 1000.0 / view_bench]
				print("%-9s%s" % [level_id, row])
				frames.sort()
				var median := frames[frames.size() / 2]
				var slow := 0
				for f in frames:
					slow += 1 if f > median * 2.5 else 0
				print(
					(
						"%-9s  frames median %.2f  p99 %.2f  max %.2f  slow %d"
						% [
							level_id,
							median,
							frames[mini(frames.size() - 1, int(frames.size() * .99))],
							frames[-1],
							slow
						]
					)
				)
			line += (
				"  %s %6.2f ms (%4.0f fps; work %.2f, render() %.2f, card %.2f)"
				% [
					mode,
					each,
					1000.0 / each,
					busy / 1000.0 / view_bench,
					drawing / 1000.0 / view_bench,
					card / view_bench
				]
			)
		print(line)
	print(
		(
			"WINDOW    software view %.2f ms (%.0f fps)   shader view %.2f ms (%.0f fps)   x%.2f"
			% [
				totals["cpu"] / 7.0,
				7000.0 / totals["cpu"],
				totals["gpu"] / 7.0,
				7000.0 / totals["gpu"],
				totals["cpu"] / totals["gpu"]
			]
		)
	)
	get_tree().quit()


## --launch-check (main_state.gd): from the title into Hickston as a player
## starts, then the verdict on the view after a few seconds of play.
func _launch_check(delta: float) -> void:
	launch_clock += delta
	if state == "title" and launch_clock > 1.0:
		start("hickston")
		state = "play"
		launch_clock = 0.0
	elif state == "play" and game != null and launch_clock > LAUNCH_CHECK_SECONDS:
		print(
			(
				"LAUNCH CHECK: view_check %d  graphics-card view %s  HD %s  window %s  mode %d"
				% [
					view_check,
					game.layered and not cpu_view,
					game.renderer.detail < 0,
					get_window().size,
					get_window().mode
				]
			)
		)
		get_tree().quit()


## Plays every chapter with the bot for play_bench seconds each (god mode, guns
## refilled) and prints how the frames went: the median, the slow tail, and
## the slowest frames with when they came and the tick's and the draw's share.
func _play_bench() -> void:
	touring = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await get_tree().process_frame
	var pilot_script: GDScript = load("res://tools/bot_pilot.gd")
	for level_id in ["hickston", "fair", "sawmill", "quarry", "bayou", "speedway", "mothership"]:
		start(level_id)
		Engine.max_fps = 0
		cpu_view = false
		game.cheats.god = true
		var pilot = pilot_script.new()
		pilot.whole = true
		var frames := PackedFloat64Array()
		var slowest: Array = []
		var last := Time.get_ticks_usec()
		for i in play_bench * 60:
			var t0 := Time.get_ticks_usec()
			game.tick(1.0 / 60.0, pilot.steer(game))
			var t1 := Time.get_ticks_usec()
			render()
			var t2 := Time.get_ticks_usec()
			await get_tree().process_frame
			pilot.moved(game)
			var now := Time.get_ticks_usec()
			var ms := (now - last) / 1000.0
			last = now
			if i < 30:
				continue
			frames.append(ms)
			slowest.append([ms, game.clock, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0])
			if game.won:
				break
		frames.sort()
		slowest.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
		var n := frames.size()
		print(
			(
				"%-10s frames %d  median %.2f  p99 %.2f  p99.9 %.2f  max %.2f ms"
				% [
					level_id,
					n,
					frames[n / 2],
					frames[int(n * .99)],
					frames[int(n * .999)],
					frames[-1]
				]
			)
		)
		for row in slowest.slice(0, 6):
			print("    %.2f ms at %.1f s (tick %.2f, draw %.2f)" % [row[0], row[1], row[2], row[3]])
	get_tree().quit()


func _process(delta: float) -> void:
	if touring:
		return
	if launch_check:
		_launch_check(delta)
	if play_bench > 0:
		_play_bench()
		return
	if view_bench > 0:
		_view_bench()
		return
	if view_tour != "":
		_view_tour()
		return
	if Tuning.watch():
		notice("TUNING RELOADED.")
	if waiting_play != null and art.chapter_ready(waiting_play.level.id):
		play(waiting_play)
	if game != null:
		packs.want_first(String(CHAPTER_PACKS.get(game.level.id, "")))
		_watch_level()
	# The engine paces frames to the FRAME LIMIT option (apply_options sets
	# Engine.max_fps), which is what the reference's clock.tick() does. A
	# browser ignores that cap and calls back once per display refresh, so
	# there the frame is skipped until most of the target interval has passed.
	pending_dt += delta
	if web and pending_dt < frame_interval() * 0.75:
		return
	var dt := minf(0.08, pending_dt)
	pending_dt = 0.0

	var work_began := Time.get_ticks_usec()
	touch.tick(dt)
	if demo:
		_demo(dt)
	if showcase:
		_showcase(dt)
	menu_clock += dt
	if state != shown_state:
		shown_state = state
		screen_age = 0.0
		hover_part = ""
		drag_mode = ""
		touch_down = false
	screen_age += dt
	# An iris opening on each new screen, a cartoon's wipe; none with SCENERY
	# MOTION on STATIC.
	var opening := 1.0
	if int(options.get("world_motion", 0)) != 2 and not smoke and not touring:
		opening = clampf(screen_age / .32, 0.0, 1.0)
		opening = opening * opening * (3.0 - 2.0 * opening)
	var wipe := fade.material as ShaderMaterial
	wipe.set_shader_parameter("open", opening)
	wipe.set_shader_parameter("aspect", fade.size.x / maxf(1.0, fade.size.y))
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
		game.touch_aim = touch.active
		game.use_key = use_button()

	if console != null:
		console.tick(delta)
	if net != null or not net_old.is_empty():
		_net_frame()
	dt *= time_scale
	if state == "play" and game != null:
		if not focused or (console != null and console.open):
			var neutral := Game.Controls.new()
			neutral.fire = game.armory.fuse > 0.0
			advance(dt, neutral)
		else:
			if showcase:
				advance(dt, _showcase_controls())
			else:
				advance(dt, _demo_controls(dt) if demo else _controls(dt, pad, fingers))
			if game.defeated():
				sound.pause_score(true)
			if game.showing_tally or game.defeated():
				grab(false)
		watch_rematch()

	sound.tick_score(dt)
	var aimed := _net_aim()
	render()
	if not aimed.is_empty():
		var me: Player = aimed[0]
		me.angle = aimed[1]
		me.pitch = aimed[2]
	_auto_detail(dt, (Time.get_ticks_usec() - work_began) / 1000.0)
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


## VIEW DETAIL AUTO: draw at half size while the frame's own work (not the
## wait for the screen) keeps going past most of the frame's time, and back at
## full size once there is plenty of room again.
func _auto_detail(dt: float, spent: float) -> void:
	if game == null or state != "play" or int(options.get("detail", 0)) != 2:
		return
	var budget := frame_interval() * 1000.0
	work_ms = lerpf(work_ms, spent, minf(1.0, dt * 4.0))
	var low := Renderer.auto_low
	if (not low and work_ms > budget * .85) or (low and work_ms < budget * .3):
		detail_strain += dt
	else:
		detail_strain = 0.0
	if detail_strain > (1.5 if not low else 5.0):
		detail_strain = 0.0
		Renderer.auto_low = not low
		game.renderer.set_detail(1 if Renderer.auto_low else 0)


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
	if net != null and net.phase == "match":
		_net_advance(elapsed, controls)
		return
	last_controls = controls
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
	var tactical := Modes.is_tactical(game)
	for _i in steps:
		if tactical:
			TacticalScreens.take_pending(controls)
		if pilots.is_empty() or game.players.size() < 2:
			game.tick(SIM_STEP, controls)
		else:
			_tick_party(controls)
		if game.portal_request != "":
			travel(game.portal_request)
			break
	_follow_view()


## The 5v5 modes: while this machine's player is out the view goes to a
## teammate still up (the keys and mouse still drive their own player, who
## is out), and back to them when the next round stands them up.
func _follow_view() -> void:
	if game == null or not Modes.is_tactical(game):
		return
	var human := TacticalScreens.human
	if human < 0 or human >= game.players.size():
		return
	var me: Player = game.players[human]
	if me.health > 0:
		if game.local_player != me:
			Players.set_local(game, me)
		return
	var watched: Player = game.local_player
	if TacticalScreens.watch_next and watched != me:
		# SPACE: the next teammate up after the one watched.
		TacticalScreens.watch_next = false
		var order: Array = game.players.filter(
			func(q: Player) -> bool: return q.team == me.team and q.health > 0 and q != me
		)
		if not order.is_empty():
			var at := order.find(watched)
			Players.set_local(game, order[(at + 1) % order.size()])
			return
	if watched != me and watched.health > 0 and watched.team == me.team:
		return
	if watched == me and me.down_at >= 0.0 and game.clock - me.down_at < 2.0:
		return  # a moment to see who did it
	for q: Player in game.players:
		if q.team == me.team and q.health > 0:
			Players.set_local(game, q)
			return
	if watched != me:
		Players.set_local(game, me)


## One step with the other players played by their pilots (src/modes/,
## tools/mode_bot.gd; the 5v5 modes' TacticalBot): this machine's own player
## on `mine` (in the 5v5 modes the one it plays, even while the view is on a
## teammate).
func _tick_party(mine: Game.Controls) -> void:
	var own: int = game.local_player.slot
	if Modes.is_tactical(game):
		own = TacticalScreens.human
	var given := {own: mine}
	for p: Player in game.players:
		var pilot = pilots.get(p.slot)
		if pilot != null and p.slot != own and p.health > 0:
			game.focus(p)
			given[p.slot] = pilot.steer(game)
	game.focus(game.local_player)
	game.tick(SIM_STEP, given)
	for p: Player in game.players:
		var pilot = pilots.get(p.slot)
		if pilot != null and p.slot != own:
			game.focus(p)
			pilot.moved(game)
	game.focus(game.local_player)


## From the project folder: a level file saved from outside reloads the level.
func _watch_level() -> void:
	if editor == null or state != "play" or Time.get_ticks_msec() < level_check:
		return
	level_check = Time.get_ticks_msec() + 500
	var stamp := FileAccess.get_modified_time(LevelEdit.path_of(game.level.id))
	if level_stamp_of != game.level.id:
		level_stamp_of = game.level.id
		level_stamp = stamp
	elif stamp != level_stamp:
		reload_level_in_place()
		notice("LEVEL RELOADED.")


# -------------------------------------------------------------------- online


## Every frame while online (src/net/net_play.gd): what came in, who came and
## went, a match beginning or ending, the lobby gone.
func _net_frame() -> void:
	var now := float(Time.get_ticks_msec())
	for old: NetPlay in net_old.duplicate():
		old.poll(now)
		if old.finished():
			net_old.erase(old)
	if net == null:
		return
	net.poll(now)
	for line: String in net.take_news():
		if state == "play":
			notice(line)
		else:
			net_note = line
	for change: Dictionary in net.take_changes():
		if change.has("started"):
			net_begin_match()
		elif change.has("lobby"):
			net_to_lobby()
		elif change.has("bot") and net.role == NetPlay.Role.HOST:
			pilots[int(change["bot"])] = TacticalBot.new(int(change["bot"]))
		elif change.has("human"):
			pilots.erase(int(change["human"]))
	if net.phase == "closed":
		net_closed()
		return
	if int(online_args.get("start", 0)) > 0 and net.phase == "lobby":
		_online_autostart()


## A match's ticks online, at the network's rate (NetSync.STEP): the host
## plays its own player and the bots and sends snapshots; a client sends its
## controls and plays its copy on toward the host's newest snapshot.
func _net_advance(elapsed: float, controls: Game.Controls) -> void:
	last_controls = controls
	net_accum = minf(.1, net_accum + elapsed)
	net_turn += controls.turn
	net_look += controls.look
	var steps := int((net_accum + 1e-9) / NetSync.STEP)
	var hosting := net.role == NetPlay.Role.HOST
	if steps > 0:
		net_accum = maxf(0.0, net_accum - steps * NetSync.STEP)
		controls.turn = net_turn / steps
		controls.look = net_look / steps
		net_turn = 0.0
		net_look = 0.0
		if net_leave:
			# Asking to leave: stand still (the round goes on).
			controls = Game.Controls.new()
		for _i in steps:
			if online_pilot != null:
				controls = _online_pilot_controls(controls)
			TacticalScreens.take_pending(controls)
			if hosting:
				_net_host_tick(controls)
			else:
				net.client_input(controls)
	if not hosting:
		net.client_play(steps)
		var copy := net.match_game()
		if copy != null and copy != game:
			game = copy
	_follow_view()


func _net_host_tick(mine: Game.Controls) -> void:
	var target := net.match_game()
	if target == null:
		return
	var own := {TacticalScreens.human: mine}
	for p: Player in target.players:
		var pilot = pilots.get(p.slot)
		if pilot != null and p.slot != TacticalScreens.human and p.health > 0:
			target.focus(p)
			own[p.slot] = pilot.steer(target)
	target.focus(target.local_player)
	net.host_tick(own)
	for p: Player in target.players:
		var pilot = pilots.get(p.slot)
		if pilot != null and p.slot != TacticalScreens.human:
			target.focus(p)
			pilot.moved(target)
	target.focus(target.local_player)


## A client's own aim drawn where the mouse has put it (inputs the host has
## not played into the copy yet), so looking round never waits on the
## network; put back after the frame. [player, angle, pitch] or [].
func _net_aim() -> Array:
	if net == null or net.role != NetPlay.Role.CLIENT or state != "play" or game == null:
		return []
	if not net.client_ready() or _view_checking or _view_unchecked():
		return []  # the start-up check draws this frame again later, as it stands
	var slot := net.my_slot()
	if slot < 0 or slot >= game.players.size():
		return []
	var me: Player = game.players[slot]
	if game.local_player != me or me.health <= 0 or game.showing_tally:
		return []
	var aim := net.client_sync.unplayed_aim() + Vector2(net_turn, net_look)
	var kept := [me, me.angle, me.pitch]
	me.angle = fposmod(me.angle + aim.x, TAU)
	me.pitch = clampf(me.pitch + aim.y, -53.0, 53.0)
	return kept


## --host-online / --join-online: straight into a lobby.
func _online_from_args() -> void:
	var name := String(online_args.get("name", "MUNDELL"))
	if online_args.has("host"):
		net_form = {
			"name": name,
			"lobby_name": "%s'S LOBBY" % NetPlay.clean_name(name),
			"password": String(online_args.get("password", "")),
			"port": str(int(online_args["host"])),
			"router": not online_args.has("start"),
		}
		net_open_lobby()
		if net != null and online_args.has("map"):
			net.set_setting("map", String(online_args["map"]))
	else:
		net_form = {
			"name": name,
			"address": String(online_args["join"]),
			"password": String(online_args.get("password", "")),
		}
		net_join()
	if net == null:
		menu_note = net_note
	if bool(online_args.get("bot", false)) and DevConsole.available():
		online_pilot = true  # a TacticalBot made per match, for the slot played


## --online-start: everyone readies by themselves, and the host starts the
## match once that many are in.
func _online_autostart() -> void:
	var me := net.player_of(net.my_id)
	if net.role == NetPlay.Role.CLIENT:
		if (
			not me.is_empty()
			and not bool(me.get("ready", false))
			and Engine.get_frames_drawn() % 30 == 0
		):
			net.ask({"ready": true})
	elif net.players.size() >= int(online_args["start"]) and net.why_not_start() == "":
		net.start_match()


## --online-bot: TacticalBot plays this machine's player (tests).
func _online_pilot_controls(mine: Game.Controls) -> Game.Controls:
	var target := net.match_game()
	var slot := net.my_slot()
	if target == null or slot < 0 or slot >= target.players.size():
		return mine
	if not (online_pilot is TacticalBot) or online_pilot.slot != slot:
		online_pilot = TacticalBot.new(slot)
	var me: Player = target.players[slot]
	if me.health <= 0 or (net.role == NetPlay.Role.CLIENT and not net.client_ready()):
		return Game.Controls.new()
	target.focus(me)
	var c: Game.Controls = online_pilot.steer(target)
	target.focus(target.local_player)
	return c
