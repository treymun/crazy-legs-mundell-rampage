## Keyboard, mouse, touch and gamepad: every screen's keys, pointer clicks
## and hover, window focus, and the controls a play frame reads (the
## front-end layers are listed in main_state.gd).
class_name MainInput
extends MainFlow


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_on_focus_lost()
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		_on_focus_gained()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back()


## Android's back button: Esc everywhere, and leave from the bare title screen.
func _on_back() -> void:
	if sound == null:
		return
	if state == "title" and game == null:
		get_tree().quit()
	else:
		key(KEY_ESCAPE)


func _on_focus_lost() -> void:
	if smoke:
		return
	if Time.get_ticks_msec() < focus_grace:
		return
	focused = false
	block_fire = true
	left_ctrl = false
	if state == "play" and game != null:
		game.player.vx = 0.0
		game.player.vy = 0.0
		if not game.showing_tally and bool(options["focus_pause"]):
			state = "title"
			selection = 0
			sound.pause_world()
			menu_music()
			sound.pause_score(true)
	grab(false)


func _on_focus_gained() -> void:
	if smoke:
		return
	focused = true
	block_fire = true
	if state != "play":
		sound.pause_score(false)
	if state == "play" and game != null:
		grab(not game.showing_tally and game.player.health > 0)


func key(code: int, shift := false) -> void:
	if binding_action != "":
		_bind_key(code)
		return
	if state == "slots":
		key_slots(code)
		return
	if state == "play" and console != null:
		if code == KEY_QUOTELEFT:
			console.toggle()
			return
		if console.key(code):
			return
	if state == "play" and editor != null:
		if code == KEY_F2:
			editor.toggle()
			return
		if editor.key(code, shift):
			return
	if code == KEY_F11:
		toggle_fullscreen()
		return
	if code == KEY_F4:
		sound.toggle_music()
		return
	if code == KEY_F5 and (state == "play" or state == "title"):
		show_slots("save" if slot_source() != null else "load")
		return
	if code == KEY_F2 or code == KEY_F6:
		save_game()
		return
	if code == KEY_F3 or code == KEY_F9:
		load_game()
		return
	if code == KEY_F12:
		_screenshot()
		return
	if state == "title" and game != null and game.player.health > 0:
		var said := game.cheats.feed(String.chr(_char_for(code)), game)
		if said != "":
			menu_note = said
			sound.play("yee_haw")
	if state == "setup":
		_key_setup(code, shift)
		return
	if state == "controls" or state == "credits":
		if state == "controls" and (code == KEY_LEFT or code == KEY_RIGHT or code == KEY_TAB):
			controls_page = posmod(
				controls_page + (-1 if code == KEY_LEFT else 1), CONTROL_PAGES.size()
			)
			sound.play("menu_move")
		elif code == KEY_ENTER or code == KEY_KP_ENTER or code == KEY_ESCAPE or code == KEY_SPACE:
			back_to_title()
		return
	if state == "replays":
		_key_replays(code)
		return
	if state == "title":
		_key_title(code)
		return
	_key_play(code)


## The key pressed while a KEYS page row waits for one.
func _bind_key(code: int) -> void:
	var action := binding_action
	binding_action = ""
	if code == KEY_ESCAPE:
		menu_note = ""
		sound.play("menu_back")
		return
	if code >= KEY_F1 and code <= KEY_F12:
		menu_note = "THE F KEYS ARE TAKEN. TRY ANOTHER."
		sound.play("empty")
		return
	KeyBindings.bind(options, action, code)
	apply_options()
	persist_options()
	menu_note = "%s SET." % KeyBindings.key_name(code)
	sound.play("menu_accept")


func _screenshot() -> void:
	var directory := "user://screenshots"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var now := Time.get_datetime_dict_from_system()
	var stamp := (
		"%04d%02d%02d-%02d%02d%02d-%06d"
		% [
			now["year"],
			now["month"],
			now["day"],
			now["hour"],
			now["minute"],
			now["second"],
			Time.get_ticks_usec() % 1000000
		]
	)
	var target := directory.path_join("Hickston-%s.png" % stamp)
	var image := Image.create_empty(WIDTH, HEIGHT, false, Image.FORMAT_RGB8)
	var picture := canvas.pixels
	if canvas.gpu and not (game != null and game.scene_live):
		# A menu (or a software view) under Godot 2D drawing: draw this screen
		# once more in software for the file.
		canvas.gpu = false
		render()
		picture = canvas.pixels.duplicate()
		canvas.gpu = true
	elif game != null and game.scene_live:
		# The canvas is only the layer over a view the shader composed: draw the
		# frame once more in software for the file.
		var whole := Canvas.new()
		var was_look := game.gpu_look
		game.gpu_look = false
		game.layered = false
		game.draw(whole, int(options["crosshair"]), true)
		game.gpu_look = was_look
		picture = whole.pixels
	image.set_data(WIDTH, HEIGHT, false, Image.FORMAT_RGB8, palettised(picture))
	if image.save_png(ProjectSettings.globalize_path(target)) == OK:
		notice("SCREENSHOT SAVED.")
	else:
		notice("COULD NOT SAVE THE SCREENSHOT.")


func _key_setup(code: int, shift: bool) -> void:
	if not display_trial.is_empty():
		if code == KEY_ENTER or code == KEY_KP_ENTER or code == KEY_SPACE:
			settle_display(true)
			return
		if code == KEY_ESCAPE:
			settle_display(false)
			return
	var item: SessionStore.Setting = option_items()[option_slot]
	if item is SessionStore.KeySetting and (code == KEY_ENTER or code == KEY_KP_ENTER):
		binding_action = (item as SessionStore.KeySetting).action
		menu_note = "PRESS A KEY FOR %s. ESC KEEPS THE OLD ONE." % item.label
		sound.play("menu_accept")
		return
	if code == KEY_UP or code == KEY_DOWN:
		setup_select(option_slot + (1 if code == KEY_DOWN else -1))
	elif code == KEY_TAB or code == KEY_PAGEUP or code == KEY_PAGEDOWN:
		setup_page(-1 if code == KEY_PAGEUP or (code == KEY_TAB and shift) else 1)
	elif code == KEY_LEFT or code == KEY_RIGHT or code == KEY_ENTER or code == KEY_KP_ENTER:
		adjust_setting(-1 if code == KEY_LEFT else 1)
	elif code == KEY_R:
		reset_page()
	elif code == KEY_ESCAPE:
		back_to_title()


func _key_replays(code: int) -> void:
	if code == KEY_ESCAPE:
		back_to_title()
	elif code == KEY_UP or code == KEY_DOWN or code == KEY_W or code == KEY_S:
		var step := -1 if code == KEY_UP or code == KEY_W else 1
		replay_selection = posmod(replay_selection + step, Campaign.ORDER.size())
		sound.play("menu_move")
	elif code == KEY_ENTER or code == KEY_KP_ENTER or code == KEY_SPACE:
		var level_id: String = Campaign.ORDER[replay_selection]
		if unlocked.has(level_id):
			start(level_id, null, [], true, null)
		else:
			sound.play("empty")
			menu_note = "CONTINUE THE CAMPAIGN TO UNLOCK."


func _key_title(code: int) -> void:
	var rows := entries()
	var step := Vector2i.ZERO
	if code == KEY_UP or code == KEY_W:
		step.y = -1
	elif code == KEY_DOWN or code == KEY_S:
		step.y = 1
	elif code == KEY_LEFT or code == KEY_A:
		step.x = -1
	elif code == KEY_RIGHT or code == KEY_D:
		step.x = 1
	if step != Vector2i.ZERO:
		var next := Menu.title_move(rows, selection, step.x, step.y)
		if next != posmod(selection, rows.size()):
			selection = next
			menu_note = ""
			sound.play("menu_move")
	elif code == KEY_ENTER or code == KEY_KP_ENTER or code == KEY_SPACE:
		sound.play("menu_accept")
		menu_action()
	elif code == KEY_ESCAPE and game != null:
		state = "play"
		sound.play("menu_back")
		play_music()
		grab(not game.showing_tally and game.player.health > 0)


func _key_play(code: int) -> void:
	var target := game
	if target == null:
		return
	if code == KEY_ESCAPE:
		return_to_title()
	elif target.showing_tally:
		if code == KEY_ENTER or code == KEY_KP_ENTER or code == KEY_SPACE:
			continue_campaign()
	elif target.player.health <= 0:
		if code == KEY_ENTER or code == KEY_KP_ENTER:
			if target.revisiting:
				target.player.health = 1
				var spawn := target.level.spawn
				target.player.x = float(spawn[0])
				target.player.y = float(spawn[1])
				target.player.angle = float(spawn[2])
				target.player.vx = 0.0
				target.player.vy = 0.0
				target.player.air = 0.0
				target.player.vertical_speed = 0.0
				target.player.eye = target.world.elevation(target.player.x, target.player.y) + .95
				target.shots.clear()
				open_hub(target)
			else:
				start(
					target.level.id, target.entry, target.history, target.replay, target.supply_rule
				)
				game.retained = target.retained
	elif code == KEY_E or code == KEY_SPACE:
		var previous := hub_findings.size()
		target.interact()
		if hub_findings.size() != previous:
			if not SessionStore.save_notes("", hub_findings):
				target.message("ROAD NOTE FOUND. IT COULD NOT BE FILED.", 3.2)
		if target.portal_request != "":
			travel(target.portal_request)
	elif target.map and code in [KEY_PAGEUP, KEY_KP_ADD, KEY_PAGEDOWN, KEY_KP_SUBTRACT]:
		# The open map zooms: in, or out to the whole level.
		var step := 1 if code == KEY_PAGEUP or code == KEY_KP_ADD else -1
		target.map_zoom = clampi(target.map_zoom + step, 0, 3)
	elif target.in_hub:
		if code == KEY_TAB:
			target.map = not target.map
	elif code == KEY_R:
		if target.armory.start_reload(target):
			target.barks.say(target, "reload")
	elif (code == KEY_H or code == KEY_SCROLLLOCK) and target.armory.fuse <= 0.0:
		target.armory.holstered = not target.armory.holstered
	elif code >= KEY_1 and code <= KEY_9:
		target.armory.select(code - KEY_1, target)
	elif (
		code == KEY_0
		or code == KEY_MINUS
		or code == KEY_EQUAL
		or code == KEY_BACKSLASH
		or code == KEY_QUOTELEFT
	):
		var slot := int(
			(
				{
					KEY_0: Weapons.ROCKET,
					KEY_MINUS: Weapons.BOWLING,
					KEY_EQUAL: Weapons.KEG,
					KEY_BACKSLASH: Weapons.COW,
					KEY_QUOTELEFT: Weapons.TEAT
				}
				. get(code, Weapons.ROCKET)
			)
		)
		target.armory.select(slot, target)
	elif code == KEY_SEMICOLON or code == KEY_APOSTROPHE:
		target.armory.cycle(-1 if code == KEY_SEMICOLON else 1, target)
	elif code == KEY_BACKSPACE:
		target.player.angle = fposmod(target.player.angle + PI, TAU)
	elif code == KEY_Q or code == KEY_BRACKETLEFT or code == KEY_BRACKETRIGHT:
		target.inventory_slot = posmod(
			target.inventory_slot + (-1 if code == KEY_BRACKETLEFT else 1), HUD.ITEMS.size()
		)
	elif code == KEY_F or code == KEY_ENTER or code == KEY_KP_ENTER:
		target.use_item()
	elif code == KEY_C or code == KEY_B or code == KEY_M or code == KEY_V or code == KEY_X:
		target.use_item([KEY_C, KEY_B, KEY_M, KEY_V, KEY_X].find(code))
	elif code == KEY_TAB:
		target.map = not target.map
	elif code == KEY_HOME:
		target.player.pitch = 0.0
	elif code == KEY_CAPSLOCK:
		options["autorun"] = 0 if int(options["autorun"]) != 0 else 1
		persist_options()
		notice("ALWAYS RUN ON" if int(options["autorun"]) != 0 else "ALWAYS RUN OFF", 1.3)
	elif code == KEY_Z and int(options["crouch"]) != 0:
		crouch_latched = not crouch_latched
	elif code == KEY_Y:
		sound.play("yee_haw")


# ------------------------------------------------------------------- input


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if (
			key_event.keycode == KEY_CTRL
			and not key_event.echo
			and key_event.location != KEY_LOCATION_RIGHT
		):
			left_ctrl = key_event.pressed
		if key_event.pressed and not key_event.echo:
			input_device = "keys"
			if console != null and console.text(key_event.unicode):
				return
			if (
				state == "slots"
				and slot_stage == "edit"
				and key_event.unicode >= 32
				and key_event.unicode < 127
			):
				slot_name = SessionStore.slot_label(slot_name + String.chr(key_event.unicode))
				return
			var code := key_event.keycode
			if state == "play" and binding_action == "":
				# Play's key handler speaks in default keys (key_bindings.gd).
				code = KeyBindings.translate(code)
				if code == KEY_NONE:
					return
			key(code, key_event.shift_pressed)
	elif event is InputEventScreenTouch:
		var finger := event as InputEventScreenTouch
		input_device = "touch"
		if touch.editing:
			touch.touch(finger)
		elif state != "play":
			touch.active = true
			if finger.pressed:
				_touch_menu(finger.position)
		else:
			touch.touch(finger)
	elif event is InputEventScreenDrag:
		if state == "play" or touch.editing:
			touch.drag(event as InputEventScreenDrag)
	elif event is InputEventMouseMotion:
		if state == "play" and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			mouse_rel += (event as InputEventMouseMotion).relative
		elif state == "title" or state == "setup":
			hover((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed:
			return
		if (
			button.button_index == MOUSE_BUTTON_WHEEL_UP
			or button.button_index == MOUSE_BUTTON_WHEEL_DOWN
		):
			if (
				state == "play"
				and game != null
				and game.player.health > 0
				and not game.showing_tally
				and game.map
			):
				var step := 1 if button.button_index == MOUSE_BUTTON_WHEEL_UP else -1
				game.map_zoom = clampi(game.map_zoom + step, 0, 3)
			elif (
				state == "play"
				and game != null
				and game.player.health > 0
				and not game.showing_tally
				and not game.in_hub
			):
				game.armory.cycle(1 if button.button_index == MOUSE_BUTTON_WHEEL_UP else -1, game)
			elif state == "setup" and display_trial.is_empty():
				setup_select(
					clampi(
						option_slot + (-1 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1),
						0,
						option_items().size() - 1
					)
				)
			return
		input_device = "keys"
		if (
			web
			and state == "play"
			and lock_wanted
			and DisplayServer.mouse_get_mode() != DisplayServer.MOUSE_MODE_CAPTURED
		):
			# The browser refused or dropped pointer lock; a click may take it back.
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			block_fire = true
		if state != "play":
			click(button.position, button.button_index)
		elif (
			state == "play"
			and button.button_index == MOUSE_BUTTON_MIDDLE
			and game != null
			and not game.showing_tally
		):
			# The reference binds USE to pygame button 2, which is the middle
			# button; Godot's button 2 is the right one (alt fire).
			key(KEY_E)


## Fingers are left clicks on every menu. The reference stops there, which left
## CONTROLS and CREDITS with no way back on a phone, so a tap closes those.
func _touch_menu(position: Vector2) -> void:
	click(position, MOUSE_BUTTON_LEFT)


## The pointer lights the row it is over, without a sound per pixel.
func hover(position: Vector2) -> void:
	var at := picture_point(position)
	if at.x < 0:
		return
	if state == "title":
		var index := Menu.title_hit(entries(), at.x, at.y)
		if index >= 0 and index != selection:
			selection = index
			sound.play("menu_move")
	elif state == "setup" and display_trial.is_empty():
		var hit := Menu.setup_hit(
			at.x, at.y, SessionStore.setup_pages().size(), option_items().size(), option_scroll
		)
		if String(hit["kind"]) == "row" and int(hit["index"]) != option_slot:
			setup_select(int(hit["index"]))


func click(position: Vector2, button: int) -> void:
	var at := picture_point(position)
	if at.x < 0:
		return
	var x := at.x
	var y := at.y
	if state == "title" and button == MOUSE_BUTTON_LEFT:
		var index := Menu.title_hit(entries(), x, y)
		if index >= 0:
			selection = index
			sound.play("menu_accept")
			menu_action()
			if state == "play":
				block_fire = true
	elif state == "controls" or state == "credits":
		if state == "controls" and y >= 32 and y < 46:
			controls_page = clampi((x - 20) / 92, 0, CONTROL_PAGES.size() - 1)
			sound.play("menu_move")
		elif button == MOUSE_BUTTON_LEFT and (Menu.BACK.has_point(at) or input_device == "touch"):
			back_to_title()
	elif state == "slots" and button == MOUSE_BUTTON_LEFT:
		if slot_stage != "choose":
			if y >= 171 and y < 190:
				key_slots(KEY_ENTER if x < 160 else KEY_ESCAPE)
		elif x >= 23 and x < 296 and y >= 35 and y < 48:
			slot_mode = "save" if x < 160 else "load"
			menu_note = ""
		elif x >= 23 and x < 296 and y >= SLOT_TOP and y < SLOT_TOP + SLOT_ROW * slots.size():
			slot_index = (y - SLOT_TOP) / SLOT_ROW
			key_slots(KEY_ENTER)
		elif y >= 171 and x >= 228:
			key_slots(KEY_ESCAPE)
	elif (
		state == "replays"
		and button == MOUSE_BUTTON_LEFT
		and x >= 19
		and x < 301
		and y >= REPLAY_TOP
		and y < REPLAY_TOP + REPLAY_ROW * Campaign.ORDER.size()
	):
		replay_selection = (y - REPLAY_TOP) / REPLAY_ROW
		key(KEY_ENTER)
	elif state == "replays" and button == MOUSE_BUTTON_LEFT and Menu.BACK.has_point(at):
		back_to_title()
	elif state == "setup" and (button == MOUSE_BUTTON_LEFT or button == MOUSE_BUTTON_RIGHT):
		if not display_trial.is_empty():
			# The question box: left half keeps, right half goes back.
			if y >= 78 and y < 122:
				settle_display(x < 160)
			return
		var hit := Menu.setup_hit(
			x, y, SessionStore.setup_pages().size(), option_items().size(), option_scroll
		)
		var kind := String(hit["kind"])
		if kind == "tab" and int(hit["index"]) != option_page:
			setup_page(int(hit["index"]) - option_page)
		elif kind == "row":
			setup_select(int(hit["index"]))
			if option_items()[option_slot] is SessionStore.KeySetting:
				_key_setup(KEY_ENTER, false)
			elif int(hit["direction"]) != 0:
				adjust_setting(-1 if button == MOUSE_BUTTON_RIGHT else int(hit["direction"]))
		elif kind == "up" or kind == "down":
			var count := option_items().size()
			option_scroll = clampi(
				option_scroll + (-1 if kind == "up" else 1), 0, maxi(0, count - Menu.VISIBLE_ROWS)
			)
			option_slot = clampi(option_slot, option_scroll, option_scroll + Menu.VISIBLE_ROWS - 1)
			sound.play("menu_move")
		elif kind == "reset":
			reset_page()
		elif kind == "back":
			back_to_title()


func read_pad(dt: float) -> Dictionary:
	var idle := {
		"forward": 0.0,
		"strafe": 0.0,
		"turn": 0.0,
		"look": 0.0,
		"run": false,
		"fire": false,
		"alt": false,
		"jump": false,
		"crouch": false
	}
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		pad_down.clear()
		return idle
	var device := int(pads[0])
	# Every button is edge-tracked every frame, so one held across a state
	# change (Start pausing the game) is not read as a fresh press in the menu.
	var pressed := {}
	for index in JOY_BUTTON_SDL_MAX:
		var down := Input.is_joy_button_pressed(device, index)
		if down and not bool(pad_down.get(index, false)):
			pressed[index] = true
			input_device = "pad"
		pad_down[index] = down
	var before := state
	for pair: Array in _pad_bindings():
		if pressed.has(int(pair[0])):
			key(int(pair[1]))
			if state != before:
				break
	if state != "play" or game == null:
		return idle
	var forward := -_deadzone(Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
	var strafe := _deadzone(Input.get_joy_axis(device, JOY_AXIS_LEFT_X))
	var turn := _deadzone(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X)) * dt * 2.6
	var look := -_deadzone(Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y)) * dt * 55.0
	# The reference fires when the raw trigger axis (-1 at rest) passes 0: half
	# a pull. Godot reports triggers 0..1, so half a pull is 0.5.
	var trigger_right := Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT)
	var trigger_left := Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT)
	return {
		"forward": forward,
		"strafe": strafe,
		"turn": turn,
		"look": look,
		"run":
		(
			Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_STICK)
			or Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_STICK)
		),
		"fire": trigger_right > 0.5,
		"alt": trigger_left > 0.5,
		"jump": Input.is_joy_button_pressed(device, JOY_BUTTON_A),
		"crouch": Input.is_joy_button_pressed(device, JOY_BUTTON_B)
	}


## The overlay's one-shot buttons, in the reference's order: menu first, then
## use and next weapon if play survived it. The consumables and the tap that
## answers the tally and death screens are this build's additions.
func _touch_actions() -> void:
	if touch.consume("menu"):
		key(KEY_ESCAPE)
	if state != "play" or game == null:
		return
	if touch.consume("use"):
		key(KEY_E)
	if touch.consume("next") and not game.in_hub:
		game.armory.cycle(1, game)
	for pair: Array in [["rinds", KEY_C], ["beer", KEY_B], ["shine", KEY_M]]:
		if touch.consume(String(pair[0])) and state == "play":
			key(int(pair[1]))
	if touch.consume("map"):
		game.map = not game.map
	# With CROUCH set to TOGGLE the DUCK button flips the latch, like the Z key.
	if int(options["crouch"]) != 0 and touch.crouch and not duck_held:
		crouch_latched = not crouch_latched
	duck_held = touch.crouch
	var tapped = touch.consume_tap()
	if tapped != null and state == "play" and game != null and game.map:
		# A tap on the open map steps the zoom in, then back out to the whole level.
		game.map_zoom = (game.map_zoom + 1) % 4
	elif (
		tapped != null
		and state == "play"
		and game != null
		and (game.showing_tally or game.player.health <= 0)
	):
		key(KEY_ENTER)


## Esc in a browser releases pointer lock and never reaches the page. Treat a
## lock that was held and is now gone as that Esc, so the game pauses instead
## of running on with a free cursor.
func _watch_pointer_lock() -> void:
	if not web or not lock_wanted:
		return
	if DisplayServer.mouse_get_mode() == DisplayServer.MOUSE_MODE_CAPTURED:
		lock_seen = true
	elif lock_seen:
		lock_seen = false
		if not game.showing_tally and game.player.health > 0:
			key(KEY_ESCAPE)


func _controls(dt: float, pad: Dictionary, fingers: Dictionary) -> Game.Controls:
	var controls := Game.Controls.new()
	if (
		block_fire
		and not (
			Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
			or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
			or KeyBindings.held("fire_key")
		)
	):
		block_fire = false
	var sensitivity := float(options["sensitivity"]) / 100.0
	var arrows := (
		(1.0 if KeyBindings.held("turn_right") else 0.0)
		- (1.0 if KeyBindings.held("turn_left") else 0.0)
	)
	var strafe_mode := KeyBindings.held("strafe_mode")
	var turn := 0.0 if strafe_mode else arrows * dt * 2.1
	var strafe := (
		(1.0 if KeyBindings.held("strafe_right") else 0.0)
		- (1.0 if KeyBindings.held("strafe_left") else 0.0)
		+ (arrows if strafe_mode else 0.0)
	)
	var look := (
		(
			(1.0 if KeyBindings.held("look_up") else 0.0)
			- (1.0 if KeyBindings.held("look_down") else 0.0)
		)
		* dt
		* 55.0
	)
	var sprint := (int(options["autorun"]) != 0) != KeyBindings.held("run")
	controls.forward = clampf(
		(
			(1.0 if KeyBindings.held("forward") else 0.0)
			- (1.0 if KeyBindings.held("back") else 0.0)
			+ float(pad["forward"])
			+ float(fingers["forward"])
		),
		-1.0,
		1.0
	)
	controls.strafe = clampf(strafe + float(pad["strafe"]) + float(fingers["strafe"]), -1.0, 1.0)
	controls.turn = (
		mouse_rel.x * .0034 * sensitivity + turn + float(pad["turn"]) + float(fingers["turn"])
	)
	var invert := 1.0 if int(options["invert"]) != 0 else -1.0
	var vertical := float(options["vertical"]) / 100.0
	controls.look = (
		mouse_rel.y * .24 * vertical * invert
		+ look
		+ float(pad["look"])
		+ float(fingers["look"]) * vertical * invert
	)
	controls.running = sprint or bool(pad["run"])
	if touch.active:
		var tilt := int(options.get("tilt_aim", 0))
		if tilt > 0:
			var rate := TiltAim.rates() * (.8 if tilt == 1 else 1.6) * dt
			controls.turn += rate.x
			controls.look += rate.y * Renderer.base_focal
	controls.fire = (
		(
			Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
			or KeyBindings.held("fire_key")
			or bool(pad["fire"])
			or bool(fingers["fire"])
		)
		and not block_fire
	)
	controls.alt_fire = (
		(
			Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
			or bool(pad["alt"])
			or bool(fingers["alt"])
		)
		and not block_fire
	)
	if (
		touch.active
		and not controls.fire
		and not block_fire
		and int(options.get("auto_fire", 1)) != 0
		and game.sights_on_enemy()
	):
		# TOUCH AUTO FIRE: a straight-shooting gun fires at a foe in the sights.
		controls.fire = true
	controls.jump = KeyBindings.held("jump") or bool(pad["jump"]) or bool(fingers["jump"])
	# As the reference: a toggle setting reads only the latch, a hold setting
	# only what is held (keyboard, pad B, or the overlay's DUCK button).
	if int(options["crouch"]) != 0:
		controls.crouch = crouch_latched
	else:
		controls.crouch = (
			KeyBindings.held("crouch") or bool(pad["crouch"]) or bool(fingers["crouch"])
		)
	return controls
