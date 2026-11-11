## The front end's state, the window and letterbox, paths, and the menu
## screens it draws. main.gd is a chain of layers, each extending the one
## before: MainState -> MainFlow -> MainInput -> main.gd. A layer only calls
## functions of its own or of the layers below it.
class_name MainState
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
const PAD_ROWS := [
	["LEFT / RIGHT STICK", "MOVE / AIM"],
	["RIGHT TRIGGER", "FIRE"],
	["LEFT TRIGGER", "WEAPON ALT FIRE"],
	["A / B", "JUMP / CROUCH"],
	["X / Y", "RELOAD / USE"],
	["BUMPERS", "PREVIOUS / NEXT WEAPON"],
	["STICK CLICK", "RUN"],
	["D-PAD UP LEFT RIGHT", "RINDS / BEER / MOONSHINE"],
	["D-PAD DOWN", "USE THE PICKED ITEM"],
	["START / BACK", "PAUSE / MAP"],
]
const TOUCH_ROWS := [
	["LEFT THUMB STICK", "MOVE"],
	["DRAG RIGHT HALF", "AIM"],
	["FIRE / ALT", "FIRE / WEAPON ALT FIRE"],
	["USE", "OPEN / RESCUE"],
	["NEXT", "NEXT WEAPON"],
	["JUMP / DUCK", "JUMP / CROUCH"],
	["RIND BEER SHINE", "EAT OR DRINK"],
	["MENU", "PAUSE"],
	["TAP A MENU ROW", "SELECT IT"],
]
const CONTROL_PAGES := [["KEYBOARD", CONTROL_ROWS], ["GAMEPAD", PAD_ROWS], ["TOUCH", TOUCH_ROWS]]
## Which sound answers a change to each audio setting.
const AUDIO_PREVIEW := {
	"effects": "effects",
	"ambience": "ambience",
	"footsteps": "footsteps",
	"voice_volume": "voice",
	"stereo": "stereo",
	"music": "music",
}

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
var tone_sent = null
## True when the display shader does the view's look pass (a real window).
var gpu_look := false
var gpu_ready := false
## The display shader also composes the game view (sky, floors, ceilings and
## the renderer's layers); see scene_layers.gd. --cpu-view keeps it in software.
var layers: SceneLayers
var cpu_view := false
## The 320x200 viewport the canvas draws into with Godot 2D (see _start_overlay),
## and --cpu-canvas, which keeps the canvas in software.
var overlay: SubViewport
var cpu_canvas := false
## The browser build's chapter music, fetched after start (pack_loader.gd).
var packs: PackLoader
## The in-game level editor (level_editor.gd; only from the project folder),
## and when the playing level's file was last seen changed.
var editor: LevelEditor
var level_stamp := 0
var level_stamp_of := ""
var level_check := 0
## A Game whose chapter's pictures a browser build is still fetching: play()
## leaves it here and main.gd starts it when they arrive.
var waiting_play: Game = null
## VIEW DETAIL AUTO: the frame's work, smoothed, and how long it has been over
## or well under the frame's time.
var work_ms := 0.0
var detail_strain := 0.0
const CHAPTER_PACKS := {
	"hickston": "music_hickston",
	"fair": "music_fair",
	"sawmill": "music_mill",
	"quarry": "music_quarry"
}
## The first time the shader composes the view it is checked, at a grid of
## points, against the software picture of the same frame (_check_view). A
## graphics driver the shader does not suit would show a picture that does not
## match, and the view then stays in software for the session.
## 0 not checked yet, 1 matched, -1 did not.
var view_check := 0
var _view_checking := false
## --view-check prints the result of that check, and --view-broken makes the
## shader's picture wrong on purpose, to see the fallback work.
var view_check_report := false
var view_broken := false
## --view-tour=<shots.json> --view-out=<dir>: for every viewpoint in the list
## save the window twice, composed by the shader (<tag>_gpu.png) and in software
## (<tag>_cpu.png), from the same instant. For checking one against the other.
var view_tour := ""
var view_out := ""
var touring := false
## --view-bench=<frames>: time whole frames in the real window, uncapped, with
## the view composed in software and then by the shader, and print both.
var view_bench := 0
## --view-shot=<png> saves the window as shown (shader included) at the end of a smoke run;
## --cpu-look keeps the look pass in software for comparison.
var view_shot := ""
var cpu_look := false
const MENU_STATES := ["title", "setup", "slots", "replays", "controls", "credits"]

var pad_down := {}

var menu: Menu
## Seconds the front end has been open: drives the title screen's slow motion.
var menu_clock := 0.0
## Seconds since the screen last changed, for the short dip between screens.
var screen_age := 1.0
var shown_state := "title"
var fade: ColorRect
## First visible row of the settings list.
var option_scroll := 0
## "keys", "pad" or "touch": whatever was used last, so hints name the right buttons.
var input_device := "keys"
## Time left to press reset a second time.
var reset_armed := 0.0
## A display change waiting to be kept: {key, previous, left}.
var display_trial := {}
var controls_page := 0

var touch: TouchControls
var duck_held := false
## The reference fires on the left Ctrl key only (pygame's K_LCTRL).
var left_ctrl := false
## The KEYS page action waiting for its new key ("" when none is).
var binding_action := ""
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
var smoke_screen := ""
## --demo: a scripted tour of the menus and a stretch of play, for recording
## with Godot's --write-movie. Never set in normal play.
var demo := false
## --showcase: every weapon in turn (draw, fire, alternate fire, reload) on the
## first level, for recording with --write-movie. Never set in normal play.
var showcase := false
var showcase_slot := -1
var showcase_only := -1
var demo_clock := 0.0
var demo_step := 0
var smoke_level := "hickston"
## --play-at=<level>:<x>,<y>,<angle>: start there (the Godot editor's Levels
## screen, Play from here).
var play_at := ""
var frame_count := 0


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
		elif text.begins_with("--view-shot="):
			view_shot = text.substr(12)
		elif text == "--cpu-look":
			cpu_look = true
		elif text == "--cpu-view":
			cpu_view = true
		elif text == "--cpu-canvas":
			cpu_canvas = true
		elif text == "--view-check":
			view_check_report = true
		elif text == "--view-broken":
			view_check_report = true
			view_broken = true
		elif text.begins_with("--view-tour="):
			view_tour = text.substr(12)
		elif text.begins_with("--view-out="):
			view_out = text.substr(11)
		elif text.begins_with("--view-bench="):
			view_bench = int(text.substr(13))
		elif text == "--demo":
			demo = true
		elif text == "--showcase":
			showcase = true
		elif text.begins_with("--showcase="):
			showcase = true
			showcase_only = int(text.substr(11))
		elif text.begins_with("--play-at="):
			play_at = text.substr(10)
		elif text.begins_with("--smoke-screen="):
			# A front-end screen instead of a level: title, setup, controls,
			# credits, replays or slots; "setup:3" opens the fourth settings page.
			smoke_screen = text.substr(15)
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


## The menu theme, for every screen that is not the game itself. It keeps its
## place while play is paused, and the chapter's own track keeps its bookmark.
func menu_music() -> void:
	sound.set_score("title")
	sound.pause_score(false)


## Back to whatever the game in progress should be playing.
func play_music() -> void:
	var target := game
	if target == null:
		return
	sound.set_score(
		"victory" if target.showing_tally else ("title" if target.in_hub else target.level.score)
	)
	sound.pause_score(target.player.health <= 0)


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
	KeyBindings.register(options)
	sound.set_levels(
		float(options["effects"]) / 100.0,
		float(options["music"]) / 100.0,
		float(options["ambience"]) / 100.0,
		int(options["stereo"])
	)
	sound.footstep_gain = float(options["footsteps"]) / 100.0
	sound.reverb_on = int(options.get("reverb", 1)) != 0
	if not sound.reverb_on:
		sound.set_space("")
	sound.voice_gain = float(options["voice_volume"]) / 100.0
	Effects.enabled = int(options.get("lights", 1)) != 0
	HUD.text_style = ["body", "menu", "heading"][clampi(int(options.get("text_size", 0)), 0, 2)]
	if int(options.get("tilt_aim", 0)) != 0:
		TiltAim.enable()
	if int(options.get("touch_layout", 0)) == 2:
		# MOVE THEM is a doing, not a state: it opens the editor and reads MY LAYOUT.
		options["touch_layout"] = 1
		touch.start_editing()
	touch.use_custom = int(options.get("touch_layout", 0)) == 1
	touch.layout(touch.area, true)
	_build_tone(int(options["brightness"]))
	# Smoke runs count frames, not seconds: leave them uncapped.
	Engine.max_fps = 0 if smoke or web else roundi(1.0 / frame_interval())
	if game != null:
		game.configure(options)
		game.tone = tone_table


func frame_interval() -> float:
	return 1.0 / float([30, 60, 120, 144, 240][clampi(int(options.get("frame_limit", 1)), 0, 4)])


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


func _char_for(code: int) -> int:
	if code >= KEY_A and code <= KEY_Z:
		return 97 + (code - KEY_A)
	return 0


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


## A point of the window as a pixel of the 320x200 picture, or (-1, -1).
func picture_point(position: Vector2) -> Vector2i:
	var rect := viewport_rect()
	if not rect.has_point(position):
		return Vector2i(-1, -1)
	return Vector2i(
		int((position.x - rect.position.x) * WIDTH / rect.size.x),
		int((position.y - rect.position.y) * HEIGHT / rect.size.y)
	)


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

## The recorded tour: [seconds, key] pairs fired in order. Keys go through the
## same key() the keyboard uses, so the recording shows the real front end.
const DEMO_KEYS := [
	[2.5, KEY_DOWN],
	[3.0, KEY_DOWN],
	[3.5, KEY_RIGHT],
	[4.0, KEY_DOWN],  # to SETTINGS
	[4.8, KEY_ENTER],
	[5.8, KEY_TAB],
	[6.6, KEY_TAB],  # DISPLAY, AUDIO
	[7.2, KEY_DOWN],
	[7.8, KEY_LEFT],
	[8.6, KEY_RIGHT],  # effects volume
	[9.4, KEY_DOWN],
	[9.9, KEY_DOWN],
	[10.4, KEY_DOWN],
	[11.0, KEY_LEFT],  # voice volume
	[12.0, KEY_RIGHT],
	[13.0, KEY_TAB],
	[14.0, KEY_DOWN],
	[14.3, KEY_DOWN],
	[14.6, KEY_DOWN],
	[14.9, KEY_DOWN],
	[15.2, KEY_DOWN],
	[15.5, KEY_DOWN],
	[15.8, KEY_DOWN],
	[16.1, KEY_DOWN],
	[16.4, KEY_DOWN],  # scroll PLAY
	[17.4, KEY_ESCAPE],
	[18.2, KEY_LEFT],
	[18.6, KEY_UP],
	[18.9, KEY_UP],
	[19.2, KEY_UP],
	[20.0, KEY_ENTER],  # NEW GAME
	[27.0, KEY_3],
	[36.0, KEY_ESCAPE],
	[39.5, KEY_ESCAPE],
	[44.0, KEY_F12],
]

const SHOWCASE_SECONDS := 6.0


func _exit_tree() -> void:
	Renderer.stop_crew()
	canvas.gpu_free()


func _save_view() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(view_shot)
	get_tree().quit()


## Hand this frame's look to the display shader (see palette.gdshader).
func _look_uniforms() -> void:
	var playing := gpu_look and game != null and state not in MENU_STATES
	var look_on := playing and game.look_live
	var tone_on := playing and game.tone_live
	palette_material.set_shader_parameter("hurt", game.hurt_alpha if playing else 0)
	palette_material.set_shader_parameter("look", look_on)
	palette_material.set_shader_parameter("tone_on", tone_on)
	if look_on:
		var w: Array = Game.WASH.get(game.level.id, [255, 255, 255, 0])
		var amount := float(w[3])
		palette_material.set_shader_parameter(
			"wash",
			Vector3(
				1.0 - amount + float(w[0]) / 255.0 * amount,
				1.0 - amount + float(w[1]) / 255.0 * amount,
				1.0 - amount + float(w[2]) / 255.0 * amount
			)
		)
		palette_material.set_shader_parameter("gain", game._look_gain)
		palette_material.set_shader_parameter("blast", game._look_blast)
		palette_material.set_shader_parameter("grain_frame", game._look_frame)
	if tone_on and tone_table != tone_sent:
		tone_sent = tone_table
		_grain_tone(tone_table)


## The palette table, the grain frames and the brightness table, as one
## texture (the shader may only sample so many): see palette.gdshader `looks`.
func _grain_tone(table: PackedByteArray) -> void:
	var looks := Image.create_empty(936, 128 + WIDTH + 1, false, Image.FORMAT_RGB8)
	looks.blit_rect(
		Image.create_from_data(256, 128, false, Image.FORMAT_RGB8, art.palette),
		Rect2i(0, 0, 256, 128),
		Vector2i.ZERO
	)
	if art.grain.size() == 936 * WIDTH:
		var grain := Image.create_from_data(936, WIDTH, false, Image.FORMAT_R8, art.grain)
		grain.convert(Image.FORMAT_RGB8)
		looks.blit_rect(grain, Rect2i(0, 0, 936, WIDTH), Vector2i(0, 128))
	if not table.is_empty():
		var strip := Image.create_from_data(256, 1, false, Image.FORMAT_R8, table)
		strip.convert(Image.FORMAT_RGB8)
		looks.blit_rect(strip, Rect2i(0, 0, 256, 1), Vector2i(0, 128 + WIDTH))
	palette_material.set_shader_parameter("looks", ImageTexture.create_from_image(looks))


func menu_panel(title: String) -> void:
	menu.draw_sheet(canvas, title)


func title_hint() -> String:
	if input_device == "touch":
		return "TAP A SIGN TO PICK IT"
	if input_device == "pad":
		return "D-PAD MOVE / A SELECT / B BACK"
	return "ARROWS MOVE / ENTER SELECT"


func setup_guide() -> String:
	if input_device == "touch":
		return "TAP A ROW  THEN ITS LEFT OR RIGHT"
	if input_device == "pad":
		return "LB RB PAGE / D-PAD CHANGE / B BACK"
	return "TAB PAGE / ARROWS CHANGE / R RESET"


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
		140,
		180,
		"body",
		HUD.INK,
		true
	)
	Menu.plate_button(canvas, Menu.BACK, "BACK")


func render_controls() -> void:
	menu_panel("HOW TO RAISE HELL")
	for j in CONTROL_PAGES.size():
		var on := j == controls_page
		canvas.fill_rect(20 + j * 92, 32, 90, 13, Menu.RUST if on else Canvas.rgb(48, 34, 26))
		HUD.text(
			canvas,
			String(CONTROL_PAGES[j][0]),
			65 + j * 92,
			35,
			"body",
			HUD.INK if on else Menu.FADED,
			true
		)
	var rows: Array = CONTROL_PAGES[controls_page][1]
	for i in rows.size():
		var row: Array = rows[i]
		var y := 51 + i * 12
		if i % 2 == 0:
			canvas.fill_rect(19, y - 2, 282, 12, Canvas.rgb(33, 23, 19))
		HUD.text(canvas, String(row[0]), 24, y, "menu", HUD.INK)
		HUD.text(canvas, String(row[1]), 146, y, "menu", Canvas.rgb(232, 213, 178))
	HUD.text(canvas, "LEFT / RIGHT  OTHER CONTROLLERS", 24, 181, "mini", Menu.PAINT, false, false)
	Menu.plate_button(canvas, Menu.BACK, "BACK")


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
			[
				"SCORE AND EFFECTS / ELEVENLABS, FINISHED BY HAND",
				"FULL CREDITS IN THIRD_PARTY_NOTICES.MD"
			]
		],
	]
	for i in blocks.size():
		var block: Array = blocks[i]
		var y := 44 + i * 41
		HUD.text(canvas, String(block[0]), 25, y, "body", HUD.AMBER)
		var lines: Array = block[1]
		for j in lines.size():
			HUD.text(canvas, String(lines[j]), 25, y + 13 + j * 10, "body", HUD.INK)
	Menu.plate_button(canvas, Menu.BACK, "BACK")


func render_setup() -> void:
	var pages := SessionStore.setup_pages()
	option_scroll = Menu.scroll_for(option_slot, option_scroll, option_items().size())
	var confirm := ""
	if not display_trial.is_empty():
		var left := int(ceilf(float(display_trial["left"])))
		if input_device == "touch":
			confirm = "TAP LEFT TO KEEP / RIGHT TO UNDO  (%d)" % left
		elif input_device == "pad":
			confirm = "A KEEP / B UNDO  (%d)" % left
		else:
			confirm = "ENTER KEEP / ESC UNDO  (%d)" % left
	menu.draw_setup(
		canvas,
		pages,
		option_page,
		option_slot,
		option_scroll,
		options,
		menu_note,
		setup_guide(),
		confirm
	)


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
	canvas.blit_rgba(sheet["data"], int(sheet["w"]), int(sheet["h"]), x, y, "art|" + name)


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


## With a window the canvas draws with Godot 2D into a 320x200 viewport the
## display shader lays over the view (canvas.gd, gpu); --cpu-canvas, the
## software look (--cpu-look) and headless runs keep it in software.
func _start_overlay() -> void:
	if not gpu_ready or cpu_look or cpu_canvas or (smoke and view_shot == ""):
		return
	overlay = SubViewport.new()
	overlay.size = Vector2i(WIDTH, HEIGHT)
	overlay.transparent_bg = true
	overlay.disable_3d = true
	overlay.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	overlay.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	overlay.snap_2d_transforms_to_pixel = true
	add_child(overlay)
	var painter := Node2D.new()
	overlay.add_child(painter)
	canvas.gpu = true
	canvas.gpu_parent = painter.get_canvas_item()
	palette_material.set_shader_parameter("post_tex", overlay.get_texture())
	palette_material.set_shader_parameter("overlay_on", true)


func render() -> void:
	canvas.layer = false
	canvas.base_set = false
	if canvas.gpu:
		canvas.gpu_begin()
	if game != null:
		game.scene_live = false
	if state == "title":
		var steady := int(options.get("flashes", 0)) != 0 or int(options.get("flicker", 1)) == 0
		menu.draw_title(
			canvas,
			entries(),
			selection,
			menu_note,
			title_hint(),
			menu_clock,
			int(options.get("world_motion", 0)),
			steady
		)
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
		gpu_look = gpu_ready and not cpu_look and (not smoke or view_shot != "")
		game.gpu_look = gpu_look
		# One renderer: with a window the shader composes the view, always (the
		# software view is the fallback when the driver check fails, cpu_look).
		game.layered = gpu_look and canvas.gpu and not cpu_view
		game.draw(canvas, int(options["crosshair"]), true)
		if editor != null and editor.active:
			editor.draw(canvas)
	else:
		canvas.clear(0, 0, 0)
	_look_uniforms()

	if canvas.pixels.size() != WIDTH * HEIGHT * 3:
		canvas.resize(WIDTH, HEIGHT)
	# On a Godot 2D canvas the pixels only matter when they hold a software view.
	if not canvas.gpu or canvas.base_set:
		frame_image.set_data(WIDTH, HEIGHT, false, Image.FORMAT_RGB8, canvas.pixels)
		frame_texture.update(frame_image)
	if canvas.gpu:
		palette_material.set_shader_parameter("base_on", canvas.base_set)
	if game != null and game.scene_live and canvas.layer:
		layers.frame(game, canvas)
		if view_broken:
			palette_material.set_shader_parameter("scene_on", false)
		if view_check == 0 and not _view_checking and not touring and state == "play":
			_check_view()
	else:
		layers.off()
	_apply_view()


func _check_view() -> void:
	var rect := view.get_global_rect()
	if rect.size.x < WIDTH or rect.size.y < HEIGHT:
		return
	_view_checking = true
	await RenderingServer.frame_post_draw
	_view_checking = false
	if game == null or state != "play" or not game.scene_live:
		return
	var shown := get_viewport().get_texture().get_image()
	if shown == null or shown.is_empty():
		return
	# The same frame again, in software.
	var whole := Canvas.new()
	game.gpu_look = false
	game.layered = false
	game.draw(whole, int(options["crosshair"]), true)
	game.gpu_look = gpu_look
	var want := whole.pixels
	var lut := art.palette
	var tried := 0
	var off := 0
	for gy in 10:
		for gx in 14:
			var px := 30 + gx * 20
			var py := 10 + gy * 13
			var sx := int(rect.position.x + (px + .5) / WIDTH * rect.size.x)
			var sy := int(rect.position.y + (py + .5) / HEIGHT * rect.size.y)
			if sx < 0 or sy < 0 or sx >= shown.get_width() or sy >= shown.get_height():
				continue
			var o := (py * WIDTH + px) * 3
			var code := (
				(((want[o] * 31 + 127) / 255) << 10)
				| (((want[o + 1] * 31 + 127) / 255) << 5)
				| ((want[o + 2] * 31 + 127) / 255)
			)
			var c := shown.get_pixel(sx, sy)
			var apart := (
				absf(c.r * 255.0 - lut[code * 3])
				+ absf(c.g * 255.0 - lut[code * 3 + 1])
				+ absf(c.b * 255.0 - lut[code * 3 + 2])
			)
			tried += 1
			if apart > 36.0:
				off += 1
	if tried < 40:
		return
	view_check = 1 if off * 3 <= tried else -1
	if view_check_report:
		print("view check: %d of %d points differ" % [off, tried])
	if view_check < 0:
		cpu_view = true
		print(
			"The shader's view does not match the software picture; keeping the view in software."
		)
