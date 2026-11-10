## Port of main.py's Desktop: window/letterbox presentation, the front-end state
## machine (title, setup, slots, replays, controls, credits, play), the fixed-step
## accumulator and all keyboard/mouse/gamepad input.
##
## The 320x200 RGB frame is uploaded to a TextureRect and graded by
## palette.gdshader, which is the Godot equivalent of period_palette.apply().
extends Control

const WIDTH := 320
const HEIGHT := 200
const SIM_STEP := 1.0 / 120.0
const SETUP_X := 23
const SETUP_Y := 56
const SETUP_ROW := 12
const SETUP_TAB := 55
const REPLAY_TOP := 46
const REPLAY_ROW := 25
const SLOT_TOP := 51
const SLOT_ROW := 25
const TITLE := "Crazy Legs Mundell Rampage | The Hickston Incident"

const CONTROL_ROWS := [
	["WASD / MOUSE", "MOVE / AIM"],
	["SHIFT / J / Z", "RUN / JUMP / CROUCH"],
	["MOUSE 1 / 2", "FIRE / WEAPON ALT FIRE"],
	["1-9  0  -  =", "WEAPONS / WHEEL / R LOAD"],
	["8 + HOLD FIRE", "LIGHT TNT / RELEASE THROW"],
	["Q / F", "SELECT ITEM / USE ITEM"],
	["C / B / M", "RINDS / BEER / MOONSHINE"],
	["E / SPACE / MMB", "USE / OPEN / RESCUE"],
	["TAB / F4 / F11", "MAP / MUSIC / FULLSCREEN"],
	["F5 / F6 / F9", "SLOTS / QUICKSAVE / QUICKLOAD"],
]

var art: Assets
var hud: HUD
var sound: Sound
var canvas: Canvas
var palette_material: ShaderMaterial

var view: TextureRect
var frame_image: Image
var frame_texture: ImageTexture

var game: Game = null
var campaign_run: Game = null
var hub_origin: Game = null
var replay_runs := {}

var state := "title"
var selection := 0
var options := {}
var option_slot := 0
var option_page := 0
var menu_note := ""

var unlocked := {}
var hub_findings := {}
var hub_visited := {}
var replay_selection := 0

var slots: Array = []
var slot_mode := "load"
var slot_index := 0
var slot_stage := "choose"
var slot_name := ""
var slot_replay := ""
var slots_return := "title"

var fullscreen := false
var fullscreen_mode := 1
var window_size := Vector2i(960, 720)
var focus_grace := 0

var block_fire := false
var crouch_latched := false
var focused := true

var accumulator := 0.0
var pending_turn := 0.0
var pending_look := 0.0
var mouse_rel := Vector2.ZERO
var pending_dt := 0.0

var tone_table = null

var pad_down := {}

var touch: TouchControls
var duck_held := false
## The reference fires on the left Ctrl key only (pygame's K_LCTRL).
var left_ctrl := false
## Phones and tablets (the APK, or a phone browser): no window, no pointer.
var mobile := false
var web := false
## Browsers take pointer lock back on Esc without sending the key, so the page
## has to notice the lock is gone instead of waiting for a keypress.
var lock_wanted := false
var lock_seen := false

var smoke := false
var smoke_frames := 0
var smoke_marker := ""
var smoke_shot := ""
var smoke_level := "hickston"
var frame_count := 0


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
	view.material = palette_material

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
	elif int(options["window_mode"]) != 0 and not smoke and not web:
		# A browser only grants fullscreen from a click or key, never at boot.
		change_window_mode(int(options["window_mode"]))
	_apply_view()

	if smoke_frames > 0:
		render()
		start(smoke_level)


func _parse_smoke() -> void:
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text.begins_with("--smoke-frames="):
			smoke_frames = int(text.substr(15))
		elif text.begins_with("--smoke-marker="):
			smoke_marker = text.substr(15)
		elif text.begins_with("--smoke-level="):
			smoke_level = text.substr(14)
		elif text.begins_with("--smoke-shot="):
			smoke_shot = text.substr(13)
	smoke = smoke_frames > 0
	focused = true


# ------------------------------------------------------------- presentation


static func presentation_size(
	width: int, height: int, aspect: int, fill := false
) -> PackedInt32Array:
	if fill:
		return PackedInt32Array([width, height])
	if aspect == 2 and width >= WIDTH and height >= HEIGHT:
		var step := mini(width / WIDTH, height / HEIGHT)
		return PackedInt32Array([WIDTH * step, HEIGHT * step])
	var a := 8 if aspect != 0 else 4
	var b := 5 if aspect != 0 else 3
	return PackedInt32Array(
		[maxi(1, mini(width, height * a / b)), maxi(1, mini(height, width * b / a))]
	)


## The part of the window the picture and the touch overlay may use: all of it,
## except on a phone, where the notch and rounded corners are kept clear.
func safe_rect() -> Rect2:
	var full := Rect2(Vector2.ZERO, get_viewport_rect().size)
	if not mobile or web:
		return full
	var safe := Rect2(DisplayServer.get_display_safe_area())
	safe.position -= Vector2(DisplayServer.window_get_position())
	var clipped := full.intersection(safe)
	if clipped.size.x < WIDTH or clipped.size.y < HEIGHT:
		return full
	return clipped


func viewport_rect() -> Rect2:
	var fill := fullscreen and fullscreen_mode == 1
	var bounds := Rect2(Vector2.ZERO, get_viewport_rect().size) if fill else safe_rect()
	var style := int(options.get("aspect", 0))
	var target := presentation_size(int(bounds.size.x), int(bounds.size.y), style, fill)
	# Whole pixels, as the reference's integer division gives: a half-pixel
	# origin makes nearest-neighbour rows uneven.
	return Rect2(
		bounds.position.x + floorf((bounds.size.x - float(target[0])) * 0.5),
		bounds.position.y + floorf((bounds.size.y - float(target[1])) * 0.5),
		float(target[0]),
		float(target[1])
	)


func _apply_view() -> void:
	var rect := viewport_rect()
	view.position = rect.position
	view.size = rect.size
	touch.layout(safe_rect())
	touch.set_showing(state == "play")


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
			sound.pause_score(true)
	grab(false)


func _on_focus_gained() -> void:
	if smoke:
		return
	focused = true
	block_fire = true
	if state == "play" and game != null:
		grab(not game.showing_tally and game.player.health > 0)


func change_window_mode(mode: int) -> void:
	if not fullscreen:
		window_size = get_window().size
	fullscreen = mode != 0
	if mode != 0:
		fullscreen_mode = mode
	focus_grace = Time.get_ticks_msec() + 380
	if mode != 0:
		get_window().mode = Window.MODE_FULLSCREEN
	else:
		get_window().mode = Window.MODE_WINDOWED
		get_window().size = window_size
	_apply_view()
	if state == "play" and game != null:
		grab(not game.showing_tally and game.player.health > 0)


func grab(value: bool) -> void:
	if smoke:
		return
	# A phone has no pointer to capture.
	var capture := value and not mobile
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if capture else Input.MOUSE_MODE_VISIBLE
	lock_wanted = capture
	lock_seen = false
	accumulator = 0.0
	pending_turn = 0.0
	pending_look = 0.0
	mouse_rel = Vector2.ZERO


# --------------------------------------------------------------- campaign


func entries() -> PackedStringArray:
	var out := PackedStringArray(
		[
			"NEW GAME",
			"COUNTY HUB",
			"REPLAY LEVEL",
			"SAVE SLOTS",
			"SETUP",
			"CONTROLS",
			"CREDITS",
			"QUIT"
		]
	)
	if _save_exists():
		var with_quick := PackedStringArray([out[0], "QUICKLOAD"])
		for i in range(1, out.size()):
			with_quick.append(out[i])
		out = with_quick
	if game != null:
		var resumed := PackedStringArray(["RESUME"])
		resumed.append_array(out)
		return resumed
	if campaign_run != null or _entry_exists():
		var continued := PackedStringArray(["CONTINUE CAMPAIGN"])
		continued.append_array(out)
		return continued
	return out


func _save_exists() -> bool:
	return FileAccess.file_exists(_save_path())


func _entry_exists() -> bool:
	return FileAccess.file_exists(_entry_path())


func _save_path() -> String:
	return "user://hickston-quick.json"


func _entry_path() -> String:
	return "user://campaign-entry.json"


func make_game(level_id := "hickston") -> Game:
	return Game.new(art, hud, sound, level_id)


func start(
	level_id := "hickston", kit = null, history: Array = [], replay := false, supply_rule = null
) -> void:
	menu_note = ""
	var fresh := make_game(level_id)
	fresh.supply_rule = int(options["supply_rule"]) if supply_rule == null else int(supply_rule)
	fresh.replay = replay
	fresh.history = history
	if replay and kit == null and level_id != "hickston":
		fresh.armory.owned[Weapons.SHOTGUN] = true
		fresh.armory.owned[Weapons.RIFLE] = true
		fresh.armory.loaded[Weapons.SHOTGUN] = Weapons.CAPACITY[Weapons.SHOTGUN]
		fresh.armory.loaded[Weapons.RIFLE] = Weapons.CAPACITY[Weapons.RIFLE]
		fresh.armory.reserve[Weapons.SHOTGUN] = 16
		fresh.armory.reserve[Weapons.RIFLE] = 48
		fresh.armory.active = Weapons.SHOTGUN
		fresh.inventory["rinds"] = 2
		var bonus: Array = (
			{
				"fair": [Weapons.ROCKET, 3],
				"sawmill": [Weapons.BOWLING, 3],
				"quarry": [Weapons.COW, 3]
			}
			. get(level_id, [Weapons.ROCKET, 3])
		)
		var new_weapon := int(bonus[0])
		fresh.armory.owned[new_weapon] = true
		fresh.armory.loaded[new_weapon] = Weapons.CAPACITY[new_weapon]
		fresh.armory.reserve[new_weapon] = int(bonus[1])
		for extra: Array in [[Weapons.TEAT, 60], [Weapons.KEG, 2]]:
			var slot := int(extra[0])
			fresh.armory.owned[slot] = true
			fresh.armory.loaded[slot] = Weapons.CAPACITY[slot]
			fresh.armory.reserve[slot] = int(extra[1])
	if kit != null:
		fresh.apply_loadout(kit)
	fresh.entry = fresh.loadout()
	play(fresh)


func play(target: Game) -> void:
	game = target
	if not target.replay and not target.in_hub and not target.revisiting:
		campaign_run = target
	if target.replay:
		replay_runs[target.level.id] = target
	target.configure(options)
	target.tone = tone_table
	crouch_latched = target.player.crouched and int(options["crouch"]) != 0
	sound.pause_world()
	sound.set_score(
		"victory" if target.showing_tally else ("title" if target.in_hub else target.level.score)
	)
	sound.pause_score(false)
	state = "play"
	block_fire = true
	grab(not target.showing_tally and target.player.health > 0)


func open_hub(origin = null, message := "") -> void:
	if origin != null and not origin.in_hub:
		hub_origin = origin
		if not origin.replay and campaign_run != null:
			if not write_campaign(campaign_run, _entry_path()):
				message = "CROSSROADS OPEN. PROGRESS COULD NOT BE SAVED."
	var hub := make_game()
	hub.in_hub = true
	hub.hub_findings = hub_findings
	hub.visited = hub_visited
	hub.world.locked_gates = []
	for gate: LevelData.Gate in hub.world.hub_gates:
		if not unlocked.has(gate.destination):
			hub.world.locked_gates.append(gate)
	for gate: LevelData.Gate in hub.world.hub_gates:
		var level_id := gate.destination
		if hub_origin != null and hub_origin.replay and hub_origin.level.id == level_id:
			hub.gate_modes[level_id] = "RESUME REPLAY"
		elif campaign_run != null and campaign_run.level.id == level_id:
			hub.gate_modes[level_id] = "REVISIT" if campaign_run.won else "CONTINUE"
		elif campaign_run != null and campaign_run.retained.has(level_id):
			hub.gate_modes[level_id] = "REVISIT"
		elif replay_runs.has(level_id):
			hub.gate_modes[level_id] = "RESUME REPLAY"
		elif campaign_run != null or level_id != "hickston":
			hub.gate_modes[level_id] = "REPLAY"
	var carried: Game = campaign_run if campaign_run != null else hub_origin
	if campaign_run != null:
		hub.hub_milestone = campaign_run.history.size() + (1 if campaign_run.won else 0)
	if carried != null and carried.player.health > 0:
		hub.apply_loadout(carried.loadout())
	hub.player.x = 24.5
	hub.player.y = 53.90
	hub.player.angle = -PI / 2.0
	hub.district = 11
	hub.message(message if message != "" else "COUNTY CROSSROADS. FACE A GATE AND PRESS E.", 4.5)
	play(hub)


func travel(destination: String) -> void:
	var current := game
	current.portal_request = ""
	if destination == "hub":
		open_hub(current)
		return
	if not unlocked.has(destination):
		return
	var origin: Game = hub_origin
	var chapter: Game = null
	if campaign_run != null:
		if campaign_run.level.id == destination:
			chapter = campaign_run
		elif campaign_run.retained.has(destination):
			var held = campaign_run.retained[destination]
			if held is Game:
				chapter = held
	if origin != null and origin.replay and origin.level.id == destination and not origin.won:
		face_into_level(origin)
		play(origin)
	elif chapter != null:
		chapter.revisiting = chapter.won
		face_into_level(chapter)
		play(chapter)
	elif replay_runs.has(destination):
		var replay: Game = replay_runs[destination]
		face_into_level(replay)
		play(replay)
	else:
		start(destination, null, [], campaign_run != null or destination != "hickston", null)


func face_into_level(target: Game) -> void:
	var p := target.player
	var gate = target.world.return_gate
	if gate == null:
		return
	if absf(p.x - gate.x) < gate.width * 0.5 and absf(p.y - gate.y) < 3.0:
		if (p.y - gate.y) * gate.side < -0.30:
			var x: float = gate.x
			var y: float = gate.y + gate.side * 1.65
			p.eye += target.world.elevation(x, y) - target.world.elevation(p.x, p.y)
			p.x = x
			p.y = y
		p.angle = gate.side * PI / 2.0
		p.pitch = 0.0
		p.vx = 0.0
		p.vy = 0.0


func bookmark_campaign_audio(target: Game) -> void:
	var chapters: Array = [target]
	for key in target.retained:
		var chapter = target.retained[key]
		if chapter is Game:
			chapters.append(chapter)
	for chapter: Game in chapters:
		var bookmark = sound.bookmark_score(chapter.level.score)
		if bookmark != null:
			chapter.music_bookmark = bookmark


func write_campaign(target: Game, path: String) -> bool:
	bookmark_campaign_audio(target)
	return SessionStore.save(target, path)


func restore_campaign_audio(target: Game) -> void:
	var chapters: Array = [target]
	for key in target.retained:
		var chapter = target.retained[key]
		if chapter is Game:
			chapters.append(chapter)
	for chapter: Game in chapters:
		sound.restore_score(chapter.level.score, chapter.music_bookmark)


func resume_entry() -> void:
	if campaign_run != null:
		open_hub(campaign_run, "CAMPAIGN READY. USE YOUR CURRENT GATE.")
		return
	var loaded := SessionStore.read(_entry_path(), make_game, false)
	if loaded == null:
		notice("THE CAMPAIGN ENTRY COULD NOT BE LOADED.")
		return
	campaign_run = loaded
	restore_campaign_audio(loaded)
	var index := Campaign.ORDER.find(loaded.level.id)
	for i in index + 1:
		unlocked[Campaign.ORDER[i]] = true
	open_hub(loaded, "CAMPAIGN READY. USE YOUR NEXT GATE.")


func continue_campaign() -> void:
	var current := game
	if current.replay:
		replay_runs.erase(current.level.id)
		if hub_origin == current:
			hub_origin = null
		return_to_title(true)
		return
	var following := Campaign.next_level(current.level.id)
	if following == "":
		open_hub(current, "SHIFT COMPLETE. OPEN ROADS LEAD BACK TO FINISHED CHAPTERS.")
		return
	var history: Array = current.history.duplicate()
	history.append(current.result())
	start(following, current.loadout(), history, false, current.supply_rule)
	game.retained = current.retained.duplicate()
	game.retained[current.level.id] = current
	unlocked[following] = true
	var message := "GATE OPEN: " + Campaign.title_of(following)
	var merged := SessionStore.unlocks("")
	for key in merged:
		unlocked[key] = true
	if not SessionStore.save_unlocks("", unlocked):
		message = "GATE OPEN. UNLOCK COULD NOT BE SAVED."
	if int(options["classic"]) != 0:
		notice(message, 1.8)
		return
	open_hub(game, message)


func return_to_title(discard := false) -> void:
	if discard:
		game = null
		sound.set_score("title")
	sound.pause_score(not discard)
	state = "title"
	selection = 0
	sound.pause_world()
	grab(false)


func menu_action() -> void:
	var rows := entries()
	var entry := rows[selection % rows.size()]
	menu_note = ""
	if entry == "RESUME":
		state = "play"
		sound.pause_score(false)
		grab(not game.showing_tally and game.player.health > 0)
	elif entry == "NEW GAME":
		start()
		if not SessionStore.save(game, _entry_path()):
			notice("CAMPAIGN ENTRY COULD NOT BE SAVED.")
	elif entry == "CONTINUE CAMPAIGN":
		resume_entry()
	elif entry == "COUNTY HUB":
		if game != null and game.armory.fuse > 0.0:
			notice("THROW THE LIT STICK BEFORE LEAVING.")
		else:
			open_hub(game)
	elif entry == "QUICKLOAD":
		load_game()
	elif entry == "REPLAY LEVEL":
		replay_selection = 0
		state = "replays"
	elif entry == "SAVE SLOTS":
		show_slots("load")
	elif entry == "SETUP" or entry == "CONTROLS" or entry == "CREDITS":
		state = entry.to_lower()
	else:
		get_tree().quit()


func notice(text: String, duration := 2.1) -> void:
	if state == "play" and game != null and game.player.health > 0:
		game.message(text, duration)
	else:
		menu_note = text


# ------------------------------------------------------------------- saves


func current_slot() -> String:
	if state == "play" and game != null and game.replay:
		return "user://replay-%s-quick.json" % game.level.id
	return _save_path()


func save_game() -> void:
	var target := game
	var slot := current_slot()
	if target != null and target.in_hub:
		notice("ENTER A LEVEL TO QUICKSAVE.")
	elif target == null or state != "play" or target.player.health <= 0 or target.showing_tally:
		notice("START A LIVE RUN TO SAVE.")
	elif target.armory.fuse > 0.0:
		notice("THROW THE LIT STICK BEFORE SAVING.")
	else:
		var source: Game = campaign_run if target.revisiting else target
		if not write_campaign(source, slot):
			notice("COULD NOT WRITE THE QUICKSAVE.")
		else:
			notice(
				(
					"CAMPAIGN SAVED. USE THE HUB TO REVISIT."
					if target.revisiting
					else "GAME SAVED. F9 TO LOAD."
				)
			)
			sound.play("menu_accept", .65)


func load_game() -> void:
	var slot := current_slot()
	if not FileAccess.file_exists(slot):
		notice("NO QUICKSAVE YET.")
		return
	var replay := slot != _save_path()
	load_checkpoint(slot, replay, game.level.id if replay and game != null else null)


func load_checkpoint(
	slot: String, replay: bool, level = null, label := "QUICKSAVE LOADED."
) -> void:
	var loaded := SessionStore.read(slot, make_game, replay, level)
	if loaded == null:
		notice("COULD NOT LOAD THAT SAVE. FILE PRESERVED.")
		return
	restore_campaign_audio(loaded)
	play(loaded)
	if not loaded.replay:
		var index := Campaign.ORDER.find(loaded.level.id)
		for i in index + 1:
			unlocked[Campaign.ORDER[i]] = true
	notice(label)
	sound.play("menu_accept", .65)


func show_slots(mode: String) -> void:
	slots_return = state
	slot_replay = game.level.id if game != null and game.replay else ""
	slot_mode = mode
	slot_index = 0
	slot_stage = "choose"
	slot_name = ""
	menu_note = ""
	state = "slots"
	sound.pause_world()
	sound.pause_score(true)
	grab(false)
	refresh_slots()


func refresh_slots() -> void:
	var root := SessionStore.slot_directory(slot_replay)
	slots = []
	for i in SessionStore.MANUAL_SLOTS:
		var path := root.path_join("slot-%d.json" % (i + 1))
		var found := SessionStore.slot_metadata(path, slot_replay)
		slots.append([path, found[0], found[1]])


func slot_source() -> Game:
	var current := game
	if (
		current == null
		or current.in_hub
		or current.showing_tally
		or current.player.health <= 0
		or current.armory.fuse > 0.0
	):
		return null
	return campaign_run if current.revisiting else current


func slot_commit() -> void:
	var source := slot_source()
	if source == null:
		menu_note = "A LIVE LEVEL WITHOUT A LIT FUSE IS REQUIRED."
		return
	var entry: Array = slots[slot_index]
	var path := String(entry[0])
	var digest = entry[1]
	var meta = entry[2]
	var name := slot_name.strip_edges()
	if name == "":
		name = String(meta[0]) if meta != null else "SLOT %d" % (slot_index + 1)
	bookmark_campaign_audio(source)
	if not SessionStore.save_named(source, path, name, digest):
		menu_note = "SAVE FAILED OR SLOT CHANGED. FILE PRESERVED."
	else:
		menu_note = "SAVED %s." % name
		sound.play("menu_accept")
	slot_stage = "choose"
	refresh_slots()


func key_slots(code: int) -> void:
	if slot_stage == "edit":
		if code == KEY_BACKSPACE:
			slot_name = slot_name.substr(0, maxi(0, slot_name.length() - 1))
		elif code == KEY_ESCAPE or code == KEY_ENTER or code == KEY_KP_ENTER:
			_text_input(false)
			slot_stage = "choose"
			if code != KEY_ESCAPE:
				if slots[slot_index][2] != null:
					slot_stage = "overwrite"
				else:
					slot_commit()
		return
	if slot_stage == "overwrite":
		if code == KEY_ENTER or code == KEY_KP_ENTER:
			slot_commit()
		elif code == KEY_ESCAPE:
			slot_stage = "choose"
		return
	if code == KEY_ESCAPE:
		state = slots_return
		menu_note = ""
		sound.pause_score(state == "title" and game != null)
		if state == "play":
			block_fire = true
			grab(game.player.health > 0 and not game.showing_tally)
	elif code == KEY_TAB or code == KEY_LEFT or code == KEY_RIGHT:
		slot_mode = "save" if slot_mode == "load" else "load"
		menu_note = ""
	elif code == KEY_UP or code == KEY_DOWN:
		var step := 1 if code == KEY_DOWN else -1
		slot_index = posmod(slot_index + step, slots.size())
		menu_note = ""
	elif code == KEY_ENTER or code == KEY_KP_ENTER:
		var entry: Array = slots[slot_index]
		var digest = entry[1]
		var meta = entry[2]
		if digest is String and String(digest) == "":
			menu_note = "UNREADABLE OR INCOMPATIBLE SLOT. FILE PRESERVED."
		elif slot_mode == "load":
			if meta != null:
				load_checkpoint(
					String(entry[0]), slot_replay != "", slot_replay, "NAMED SAVE LOADED."
				)
			else:
				menu_note = "THAT SLOT IS EMPTY."
		elif slot_source() != null:
			slot_name = ""
			slot_stage = "edit"
			menu_note = ""
			_text_input(true)
		else:
			menu_note = "A LIVE LEVEL WITHOUT A LIT FUSE IS REQUIRED."


## pg.key.start_text_input / stop_text_input: raises the on-screen keyboard
## where there is one, so a save slot can be named on a phone.
func _text_input(active: bool) -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return
	if active:
		DisplayServer.virtual_keyboard_show(slot_name)
	else:
		DisplayServer.virtual_keyboard_hide()


# ----------------------------------------------------------------- options


func option_items() -> Array:
	return SessionStore.setup_pages()[option_page][1]


func apply_options() -> void:
	sound.set_levels(
		float(options["effects"]) / 100.0,
		float(options["music"]) / 100.0,
		float(options["ambience"]) / 100.0,
		int(options["stereo"])
	)
	sound.footstep_gain = float(options["footsteps"]) / 100.0
	sound.voice_gain = float(options["voice_volume"]) / 100.0
	_build_tone(int(options["brightness"]))
	# Smoke runs count frames, not seconds: leave them uncapped.
	Engine.max_fps = 0 if smoke or web else roundi(1.0 / frame_interval())
	if game != null:
		game.configure(options)
		game.tone = tone_table


func frame_interval() -> float:
	return 1.0 / float([30, 60, 120][clampi(int(options.get("frame_limit", 1)), 0, 2)])


func _build_tone(level: int) -> void:
	if level == 100:
		tone_table = null
		return
	var table := PackedByteArray()
	table.resize(256)
	for i in 256:
		table[i] = clampi(int(round(pow(float(i) / 255.0, 100.0 / float(level)) * 255.0)), 0, 255)
	tone_table = table


func persist_options() -> void:
	if not SessionStore.save_settings("", options):
		menu_note = "SETUP COULD NOT BE SAVED."


func adjust_setting(direction: int) -> void:
	var items := option_items()
	var item: SessionStore.Setting = items[option_slot]
	options[item.key] = item.adjust(int(options[item.key]), direction)
	if item.key == "crouch":
		crouch_latched = false
	if item.key == "window_mode":
		change_window_mode(int(options["window_mode"]))
	apply_options()
	sound.play("menu_move")
	persist_options()


func toggle_fullscreen() -> void:
	var mode := 0 if fullscreen else fullscreen_mode
	change_window_mode(mode)
	options["window_mode"] = mode
	persist_options()


# -------------------------------------------------------------------- keys


func key(code: int, shift := false) -> void:
	if state == "slots":
		key_slots(code)
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
		if code == KEY_ENTER or code == KEY_KP_ENTER or code == KEY_ESCAPE or code == KEY_SPACE:
			state = "title"
		return
	if state == "replays":
		_key_replays(code)
		return
	if state == "title":
		_key_title(code)
		return
	_key_play(code)


func _char_for(code: int) -> int:
	if code >= KEY_A and code <= KEY_Z:
		return 97 + (code - KEY_A)
	return 0


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
	image.set_data(WIDTH, HEIGHT, false, Image.FORMAT_RGB8, palettised(canvas.pixels))
	if image.save_png(ProjectSettings.globalize_path(target)) == OK:
		notice("SCREENSHOT SAVED.")
	else:
		notice("COULD NOT SAVE THE SCREENSHOT.")


## period_palette.apply() on the CPU: the screen gets the 256-colour grade from
## palette.gdshader, but a saved screenshot has to carry it in its pixels, as
## the reference's does.
func palettised(source: PackedByteArray) -> PackedByteArray:
	var lut := art.palette
	var graded := PackedByteArray()
	graded.resize(source.size())
	for i in range(0, source.size(), 3):
		var code := (
			(((source[i] * 31 + 127) / 255) << 10)
			| (((source[i + 1] * 31 + 127) / 255) << 5)
			| ((source[i + 2] * 31 + 127) / 255)
		)
		var o := code * 3
		graded[i] = lut[o]
		graded[i + 1] = lut[o + 1]
		graded[i + 2] = lut[o + 2]
	return graded


func _key_setup(code: int, shift: bool) -> void:
	if code == KEY_UP or code == KEY_DOWN:
		var items := option_items()
		option_slot = posmod(option_slot + (1 if code == KEY_DOWN else -1), items.size())
		sound.play("menu_move")
	elif code == KEY_TAB or code == KEY_PAGEUP or code == KEY_PAGEDOWN:
		var step := -1 if code == KEY_PAGEUP or (code == KEY_TAB and shift) else 1
		option_page = posmod(option_page + step, SessionStore.setup_pages().size())
		option_slot = 0
		menu_note = ""
		sound.play("menu_move")
	elif code == KEY_LEFT or code == KEY_RIGHT or code == KEY_ENTER or code == KEY_KP_ENTER:
		adjust_setting(-1 if code == KEY_LEFT else 1)
	elif code == KEY_R:
		for raw in option_items():
			var item: SessionStore.Setting = raw
			options[item.key] = item.default_value
			if item.key == "window_mode" and fullscreen:
				change_window_mode(0)
		crouch_latched = false
		apply_options()
		persist_options()
		sound.play("menu_accept")
	elif code == KEY_ESCAPE:
		state = "title"


func _key_replays(code: int) -> void:
	if code == KEY_ESCAPE:
		state = "title"
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
	if code == KEY_UP or code == KEY_W:
		selection = posmod(selection - 1, rows.size())
		sound.play("menu_move")
	elif code == KEY_DOWN or code == KEY_S:
		selection = posmod(selection + 1, rows.size())
		sound.play("menu_move")
	elif code == KEY_ENTER or code == KEY_KP_ENTER or code == KEY_SPACE:
		sound.play("menu_accept")
		menu_action()
	elif code == KEY_ESCAPE and game != null:
		state = "play"
		sound.pause_score(false)
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
			if (
				state == "slots"
				and slot_stage == "edit"
				and key_event.unicode >= 32
				and key_event.unicode < 127
			):
				slot_name = SessionStore.slot_label(slot_name + String.chr(key_event.unicode))
				return
			key(key_event.keycode, key_event.shift_pressed)
	elif event is InputEventScreenTouch:
		var finger := event as InputEventScreenTouch
		if state != "play":
			touch.active = true
			if finger.pressed:
				_touch_menu(finger.position)
		else:
			touch.touch(finger)
	elif event is InputEventScreenDrag:
		if state == "play":
			touch.drag(event as InputEventScreenDrag)
	elif event is InputEventMouseMotion:
		if state == "play" and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			mouse_rel += (event as InputEventMouseMotion).relative
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
				and not game.in_hub
			):
				game.armory.cycle(1 if button.button_index == MOUSE_BUTTON_WHEEL_UP else -1, game)
			return
		if (
			web
			and state == "play"
			and lock_wanted
			and DisplayServer.mouse_get_mode() != DisplayServer.MOUSE_MODE_CAPTURED
		):
			# The browser refused or dropped pointer lock; a click may take it back.
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			block_fire = true
		if state == "title" or state == "setup" or state == "replays" or state == "slots":
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
	if state == "controls" or state == "credits":
		state = "title"
	else:
		click(position, MOUSE_BUTTON_LEFT)


func click(position: Vector2, button: int) -> void:
	var rect := viewport_rect()
	if not rect.has_point(position):
		return
	var x := int((position.x - rect.position.x) * WIDTH / rect.size.x)
	var y := int((position.y - rect.position.y) * HEIGHT / rect.size.y)
	if (
		state == "title"
		and button == MOUSE_BUTTON_LEFT
		and x >= 16
		and x < 190
		and y >= HUD.TITLE_FIRST
	):
		var rows := entries()
		var row := HUD.TITLE_ROW - (1 if rows.size() > 9 else 0)
		var index := (y - HUD.TITLE_FIRST) / row
		if index < rows.size():
			selection = index
			sound.play("menu_accept")
			menu_action()
			if state == "play":
				block_fire = true
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
	elif state == "setup" and (button == MOUSE_BUTTON_LEFT or button == MOUSE_BUTTON_RIGHT):
		var pages := SessionStore.setup_pages().size()
		if (
			button == MOUSE_BUTTON_LEFT
			and x >= SETUP_X
			and x < SETUP_X + SETUP_TAB * pages
			and y >= 39
			and y < 54
		):
			option_page = (x - SETUP_X) / SETUP_TAB
			option_slot = 0
			menu_note = ""
			sound.play("menu_move")
		elif (
			x >= SETUP_X
			and x < 298
			and y >= SETUP_Y
			and y < SETUP_Y + SETUP_ROW * option_items().size()
		):
			option_slot = (y - SETUP_Y) / SETUP_ROW
			if x >= 171:
				adjust_setting(-1 if button == MOUSE_BUTTON_RIGHT or x < 183 else 1)
		elif button == MOUSE_BUTTON_LEFT and y >= 175 and y < 190 and x >= 246 and x <= 299:
			state = "title"


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


## Pad buttons that act as key presses. The reference reads raw SDL joystick
## indices off an XInput pad (2 X reload, 3 Y use, 4/5 the bumpers for previous
## and next weapon, 8/9 the stick clicks to run); Godot numbers the same
## buttons differently, so they are named here. Everything after the first four
## is this build's own: the reference had no pad binding for pause, the map, the
## consumables or any menu, so a pad alone could not get past the title screen.
func _pad_bindings() -> Array:
	if state == "play" and game != null:
		if game.showing_tally or game.player.health <= 0:
			return [
				[JOY_BUTTON_A, KEY_ENTER], [JOY_BUTTON_START, KEY_ENTER], [JOY_BUTTON_B, KEY_ESCAPE]
			]
		return [
			[JOY_BUTTON_X, KEY_R],
			[JOY_BUTTON_Y, KEY_E],
			[JOY_BUTTON_LEFT_SHOULDER, KEY_SEMICOLON],
			[JOY_BUTTON_RIGHT_SHOULDER, KEY_APOSTROPHE],
			[JOY_BUTTON_START, KEY_ESCAPE],
			[JOY_BUTTON_BACK, KEY_TAB],
			[JOY_BUTTON_DPAD_UP, KEY_C],
			[JOY_BUTTON_DPAD_LEFT, KEY_B],
			[JOY_BUTTON_DPAD_RIGHT, KEY_M],
			[JOY_BUTTON_DPAD_DOWN, KEY_F]
		]
	return [
		[JOY_BUTTON_DPAD_UP, KEY_UP],
		[JOY_BUTTON_DPAD_DOWN, KEY_DOWN],
		[JOY_BUTTON_DPAD_LEFT, KEY_LEFT],
		[JOY_BUTTON_DPAD_RIGHT, KEY_RIGHT],
		[JOY_BUTTON_A, KEY_ENTER],
		[JOY_BUTTON_START, KEY_ENTER],
		[JOY_BUTTON_B, KEY_ESCAPE],
		[JOY_BUTTON_LEFT_SHOULDER, KEY_PAGEUP],
		[JOY_BUTTON_RIGHT_SHOULDER, KEY_PAGEDOWN]
	]


func _deadzone(value: float) -> float:
	return 0.0 if absf(value) < .18 else value


# ------------------------------------------------------------------- frame


func _process(delta: float) -> void:
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
			advance(dt, _controls(dt, pad, fingers))
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
			get_tree().quit()


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
	# With CROUCH set to TOGGLE the DUCK button flips the latch, like the Z key.
	if int(options["crouch"]) != 0 and touch.crouch and not duck_held:
		crouch_latched = not crouch_latched
	duck_held = touch.crouch
	var tapped = touch.consume_tap()
	if (
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
			or left_ctrl
		)
	):
		block_fire = false
	var sensitivity := float(options["sensitivity"]) / 100.0
	var arrows := (
		(1.0 if Input.is_key_pressed(KEY_RIGHT) else 0.0)
		- (1.0 if Input.is_key_pressed(KEY_LEFT) else 0.0)
	)
	var strafe_mode := Input.is_key_pressed(KEY_ALT)
	var turn := 0.0 if strafe_mode else arrows * dt * 2.1
	var strafe := (
		(1.0 if Input.is_key_pressed(KEY_D) else 0.0)
		- (1.0 if Input.is_key_pressed(KEY_A) else 0.0)
		+ (arrows if strafe_mode else 0.0)
	)
	var look := (
		(
			(1.0 if Input.is_key_pressed(KEY_PAGEUP) else 0.0)
			- (1.0 if Input.is_key_pressed(KEY_PAGEDOWN) else 0.0)
		)
		* dt
		* 55.0
	)
	var sprint := (int(options["autorun"]) != 0) != Input.is_key_pressed(KEY_SHIFT)
	controls.forward = clampf(
		(
			(1.0 if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP) else 0.0)
			- (1.0 if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN) else 0.0)
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
	controls.fire = (
		(
			Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
			or left_ctrl
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
	controls.jump = Input.is_key_pressed(KEY_J) or bool(pad["jump"]) or bool(fingers["jump"])
	# As the reference: a toggle setting reads only the latch, a hold setting
	# only what is held (keyboard, pad B, or the overlay's DUCK button).
	if int(options["crouch"]) != 0:
		controls.crouch = crouch_latched
	else:
		controls.crouch = (
			Input.is_key_pressed(KEY_Z) or bool(pad["crouch"]) or bool(fingers["crouch"])
		)
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


func render() -> void:
	if state == "title":
		hud.title(canvas, selection % entries().size(), entries(), menu_note)
	elif state == "setup":
		render_setup()
	elif state == "slots":
		render_slots()
	elif state == "replays":
		render_replays()
	elif state == "controls":
		render_controls()
	elif state == "credits":
		render_credits()
	elif game != null:
		game.draw(canvas, int(options["crosshair"]), true)
	else:
		canvas.clear(0, 0, 0)

	if canvas.pixels.size() != WIDTH * HEIGHT * 3:
		canvas.resize(WIDTH, HEIGHT)
	frame_image.set_data(WIDTH, HEIGHT, false, Image.FORMAT_RGB8, canvas.pixels)
	frame_texture.update(frame_image)
	_apply_view()


func menu_panel(title: String) -> void:
	_blit_art("title_backdrop", 0, 0)
	HUD.panel(canvas, 12, 9, 296, 182)
	HUD.text(canvas, title, 160, 18, "heading", HUD.AMBER, true)


func render_replays() -> void:
	menu_panel("REPLAY LEVEL")
	for i in Campaign.ORDER.size():
		var level_id: String = Campaign.ORDER[i]
		var color := HUD.AMBER if i == replay_selection else HUD.INK
		var y := REPLAY_TOP + i * REPLAY_ROW + 4
		if i == replay_selection:
			canvas.fill_rect(19, y - 4, 282, 24, Canvas.rgb(82, 49, 31))
		HUD.text(canvas, Campaign.title_of(level_id), 26, y, "menu", color)
		var status := "UNLOCKED" if unlocked.has(level_id) else "LOCKED"
		HUD.text(canvas, status, 292, y + 1, "body", color, false, true, true)
	HUD.text(canvas, "REPLAY USES ITS OWN SAVE SLOT", 160, 145, "body", HUD.INK, true)
	HUD.text(
		canvas,
		menu_note if menu_note != "" else "ENTER START  /  ESC BACK",
		160,
		172,
		"body",
		HUD.INK,
		true
	)


func render_controls() -> void:
	menu_panel("HOW TO RAISE HELL")
	HUD.text(canvas, "KEYS", 24, 40, "body", HUD.AMBER)
	HUD.text(canvas, "ACTION", 132, 40, "body", HUD.AMBER)
	for i in CONTROL_ROWS.size():
		var row: Array = CONTROL_ROWS[i]
		var y := 51 + i * 12
		if i % 2 == 0:
			canvas.fill_rect(19, y - 2, 282, 12, Canvas.rgb(33, 23, 19))
		HUD.text(canvas, String(row[0]), 24, y, "menu", HUD.INK)
		HUD.text(canvas, String(row[1]), 132, y, "menu", Canvas.rgb(232, 213, 178))
	HUD.text(canvas, "ESC BACK", 160, 178, "body", HUD.INK, true)


func render_credits() -> void:
	menu_panel("CREDITS")
	var blocks := [
		["THE 1997 INSPIRATION", ["REDNECK RAMPAGE / XATRIX ENTERTAINMENT"]],
		[
			"PHOTOGRAPHS",
			[
				"JERRY JONES / KEITH ALLISON (CC BY-SA 2.0)",
				"ROADSIDE / JOHN MARGOLIES, LIBRARY OF CONGRESS"
			]
		],
		[
			"MATERIALS AND AUDIO",
			["PHOTO MATERIALS / POLY HAVEN", "FULL CREDITS IN THIRD_PARTY_NOTICES.MD"]
		],
	]
	for i in blocks.size():
		var block: Array = blocks[i]
		var y := 44 + i * 41
		HUD.text(canvas, String(block[0]), 25, y, "body", HUD.AMBER)
		var lines: Array = block[1]
		for j in lines.size():
			HUD.text(canvas, String(lines[j]), 25, y + 13 + j * 10, "body", HUD.INK)
	HUD.text(canvas, "ESC BACK", 160, 178, "body", HUD.INK, true)


func render_setup() -> void:
	var pages := SessionStore.setup_pages()
	menu_panel("HICKSTON SETUP")
	for j in pages.size():
		var x := SETUP_X + SETUP_TAB * j
		var active := j == option_page
		canvas.fill_rect(
			x, 39, SETUP_TAB - 2, 14, Canvas.rgb(100, 61, 33) if active else Canvas.rgb(54, 39, 32)
		)
		canvas.line(
			x,
			39,
			x + SETUP_TAB - 3,
			39,
			Canvas.rgb(181, 131, 76) if active else Canvas.rgb(93, 69, 53)
		)
		HUD.text(
			canvas,
			String(pages[j][0]),
			x + (SETUP_TAB - 2) / 2,
			43,
			"body",
			HUD.AMBER if active else HUD.INK,
			true
		)
	var items: Array = pages[option_page][1]
	for j in items.size():
		var y := SETUP_Y + j * SETUP_ROW
		var active := j == option_slot
		var face := (
			Canvas.rgb(83, 52, 33)
			if active
			else (Canvas.rgb(34, 24, 20) if j % 2 == 0 else Canvas.rgb(40, 29, 23))
		)
		canvas.fill_rect(SETUP_X, y, 274, SETUP_ROW, face)
		var item: SessionStore.Setting = items[j]
		HUD.text(canvas, item.label, 35, y + 2, "menu", HUD.AMBER if active else HUD.INK)
		HUD.text(
			canvas,
			item.format_value(int(options[item.key])),
			234,
			y + 2,
			"menu",
			HUD.AMBER if active else HUD.INK,
			true
		)
		if active:
			HUD.text(canvas, ">", 26, y + 3, "body", HUD.AMBER)
			HUD.text(canvas, "<", 173, y + 3, "body", HUD.AMBER)
			HUD.text(canvas, ">", 291, y + 3, "body", HUD.AMBER)
	var hint_text := menu_note
	if hint_text == "":
		var current: SessionStore.Setting = items[option_slot]
		hint_text = current.hint
	var lines := PixelType.wrap(hint_text, 272)
	for i in lines.size():
		HUD.text(canvas, lines[i], 160, 155 + i * 9, "body", Canvas.rgb(227, 201, 161), true)
	canvas.line(23, 174, 296, 174, Canvas.rgb(113, 80, 54))
	var guides := [[23, "TAB PAGES"], [99, "ARROWS CHANGE"], [192, "R RESET"], [249, "ESC BACK"]]
	for guide: Array in guides:
		HUD.text(canvas, String(guide[1]), int(guide[0]), 179, "body", HUD.INK)


func render_slots() -> void:
	var kind := "REPLAY" if slot_replay != "" else "CAMPAIGN"
	menu_panel(kind + " SAVE SLOTS")
	for pair: Array in [["save", 23], ["load", 161]]:
		var mode := String(pair[0])
		var x := int(pair[1])
		canvas.fill_rect(
			x, 35, 135, 13, Canvas.rgb(96, 58, 34) if slot_mode == mode else Canvas.rgb(53, 37, 29)
		)
		HUD.text(canvas, mode.to_upper(), x + 67, 38, "body", HUD.INK, true)
	for i in slots.size():
		var entry: Array = slots[i]
		var digest = entry[1]
		var meta = entry[2]
		var y := SLOT_TOP + i * SLOT_ROW
		var active := slot_index == i
		canvas.fill_rect(
			23, y, 273, SLOT_ROW - 2, Canvas.rgb(75, 48, 32) if active else Canvas.rgb(39, 28, 22)
		)
		var label := "FILE UNREADABLE" if (digest is String and String(digest) == "") else "EMPTY"
		var level := ""
		var stamp := ""
		if meta != null:
			label = String(meta[0])
			level = String(meta[1]).to_upper()
			stamp = String(meta[3])
		HUD.text(
			canvas, "%d  %s" % [i + 1, label], 28, y + 4, "body", HUD.AMBER if active else HUD.INK
		)
		HUD.text(canvas, level, 291, y + 4, "body", HUD.INK, false, true, true)
		HUD.text(canvas, stamp, 28, y + 14, "mini", HUD.INK, false, false)
	var selected = slots[slot_index][2]
	var lines: Array = []
	var guide := "TAB SAVE / LOAD   ENTER SELECT   ESC BACK"
	if slot_stage == "edit":
		var fallback := ("SLOT %d" % (slot_index + 1)) if selected == null else String(selected[0])
		lines = ["NAME  " + (slot_name if slot_name != "" else fallback) + "_"]
		guide = "ENTER CONTINUE / ESC CANCEL"
	elif slot_stage == "overwrite":
		lines = ["REPLACE " + String(selected[0]) + "?"]
		guide = "ENTER OVERWRITE / ESC KEEP SAVE"
	else:
		var text := menu_note
		if text == "":
			text = "QUICKSAVE IS SEPARATE." if selected == null else String(selected[2])
		var wrapped := PixelType.wrap(text, 270)
		for i in mini(2, wrapped.size()):
			lines.append(wrapped[i])
	for i in lines.size():
		HUD.text(canvas, String(lines[i]), 160, 153 + i * 9, "body", HUD.AMBER, true)
	HUD.text(canvas, guide, 160, 179, "mini", HUD.INK, true)


func _blit_art(name: String, x: int, y: int) -> void:
	var sheet := art.art(name)
	canvas.blit_rgba(sheet["data"], int(sheet["w"]), int(sheet["h"]), x, y)


func _write_marker() -> void:
	if smoke_marker == "":
		return
	var lines := PackedStringArray()
	lines.append(TITLE)
	lines.append("Level: %s" % (game.level.id if game != null else "title"))
	lines.append("Frames: %d" % frame_count)
	lines.append("State: %s" % state)
	if smoke_shot != "":
		lines.append("Shot: %s" % smoke_shot)
	var handle := FileAccess.open(smoke_marker, FileAccess.WRITE)
	if handle != null:
		handle.store_string("\n".join(lines) + "\n")
		handle.close()
