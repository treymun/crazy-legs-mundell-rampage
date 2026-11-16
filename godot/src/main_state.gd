## The front end's state, the window and letterbox, paths, and the menu screens it draws.
## main.gd is a chain of layers, each extending the one before: MainState -> MainFlow ->
## MainInput -> main.gd. A layer only calls functions of its own or of the layers below it.
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
## The 5v5 SHOWDOWN's own keys (src/modes/tactical_screens.gd).
const SHOWDOWN_ROWS := [
	["B", "THE STORE (BUY TIME)"],
	["1 2 3 4", "RIFLE / PISTOL / BAR / THROWN"],
	["MOUSE 2", "SCOPE UP AND DOWN (SNIPERS)"],
	["R", "RELOAD"],
	["HOLD E", "PLANT / CUT THE FUSE"],
	["E", "TAKE OR SET DOWN A HOSTAGE"],
	["CROUCH, STAND STILL", "STEADIER AIM"],
	["TAB HELD", "SCOREBOARD"],
	["M", "MAP WITH THE SITES"],
	["SPACE WHILE OUT", "WATCH THE NEXT TEAMMATE"],
]
const CONTROL_PAGES := [
	["KEYBOARD", CONTROL_ROWS], ["GAMEPAD", PAD_ROWS], ["TOUCH", TOUCH_ROWS], ["5V5", SHOWDOWN_ROWS]
]
## The width of each controls page's tab.
const CONTROL_TAB := 70
## Which sound answers a change to each audio setting.
const AUDIO_PREVIEW := {
	"master": "effects",
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
## The firing range's level, and the game paused when the player went to the
## range from the title (back in its place when they leave it).
const RANGE_ID := "range"
var range_return: Game = null
## BOSS REMATCH (boss_rematch.gd): the game paused when one began (back when
## it ends), the board's picked row, and the last result shown.
var rematch_return: Game = null
var rematch_pick := 0
var rematch_result := {}
## The board's bosses open to fight and best times, read when it opens.
var rematch_open := {}
var rematch_bests := {}

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

var tone_table: Variant = null
var tone_sent: Variant = null
## True when the display shader does the view's look pass (a real window).
var gpu_look := false
var gpu_ready := false
## The 3D view (view3d/world_view.gd): made the first time play is drawn with a window.
var world_view: WorldView3D
## The menu screens built from Control nodes (src/ui/): a state with a screen
## there is drawn and driven by it, not by render() and key().
var ui: UiRoot
## The 320x200 viewport the canvas draws into with Godot 2D (see _start_overlay),
## and --cpu-canvas, which keeps the canvas in software.
var overlay: SubViewport
var cpu_canvas := false
## The play HUD's Control nodes in the overlay (ui/hud/hud_layer.gd; none
## headless, where the HUD draws on the canvas), PHOTO MODE and the KILL CAM
## (photo_mode.gd, kill_cam.gd).
var hud_layer: HudLayer
var photo := PhotoMode.new()
var kill_cam := KillCam.new()
## QUALITY (core/quality.gd): the tier AUTO measured on this machine (-1 not
## yet), its measurement while it runs, and whether it may set the picture
## settings when done (only on a first run: no settings saved before).
var quality_measured := -1
var quality_meter: Quality.Meter = null
var quality_first := false
## The browser build's chapter music, fetched after start (pack_loader.gd).
var packs: PackLoader
## The in-game level editor (level_editor.gd; only from the project folder),
## and when the playing level's file was last seen changed.
var editor: LevelEditor
## The developer console (dev_console.gd; only from the project folder), and
## how fast play runs (its `time` command).
var console: DevConsole
var time_scale := 1.0
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
	"quarry": "music_quarry",
	"bayou": "music_bayou",
	"speedway": "music_speedway",
	"mothership": "music_mothership",
}
## --launch-check: a player's launch in any build, the exported game too: the
## settings' window mode, then a chapter, and after LAUNCH_CHECK_SECONDS of play
## one line saying whether the view is the graphics card's and HD is on; then
## it quits. Point APPDATA at a scratch profile: it plays with that profile.
var launch_check := false
var launch_clock := 0.0
const LAUNCH_CHECK_SECONDS := 4.0
## --view-tour=<shots.json> --view-out=<dir>: for every viewpoint in the list
## save the window twice, composed by the shader (<tag>_gpu.png) and in software
## (<tag>_cpu.png), from the same instant. For checking one against the other.
var view_tour := ""
var view_out := ""
var touring := false
## --view-bench=<frames>: time whole frames in the real window, uncapped, with
## the view composed in software and then by the shader, and print both.
var view_bench := 0
## --play-bench=<seconds>: tools/bot_pilot.gd plays each chapter in the real
## window, uncapped, and the slowest frames are printed (stutters; project
## folder only, the pilot is a tool).
var play_bench := 0
## How long the last frame took to hand its layers to the shader (the bench's parts).
var layers_us := 0
## --view-shot=<png> saves the window as shown (shader included) at the end of a smoke run;
## --cpu-look keeps the look pass in software for comparison.
var view_shot := ""
var cpu_look := false
const MENU_STATES := [
	"title",
	"setup",
	"slots",
	"replays",
	"controls",
	"credits",
	"rematch",
	"rematch_done",
	"showdown",
	"nethost",
	"netjoin",
	"lobby",
	"servers",
	"multi",
	"lobbyset",
	"county",
]
## The title's 5V5 SHOWDOWN picker (TacticalScreens.draw_picker): the row the
## cursor is on, the mode, map and match length picked, and whether the game
## now is a match started from it (anything else from the title clears the
## mode it set, so a campaign never starts as a 5v5).
var showdown_row := 0
var showdown_mode := 0
var showdown_map := 0
var showdown_long := 1
var showdown_rules := 0  # the picker's RULES (TacticalShop.RULE_IDS)
var showdown_skill := 1  # the picker's BOTS (TacticalScreens.SKILL_NAMES; NORMAL)
var browser: NetBrowser = null  # the COUNTY SERVERS list while it is shown
var showdown_on := false
## Online play (src/net/net_play.gd, docs/online.md): the lobby or match this
## machine is in (null: none), lobbies closing (polled until their goodbye is
## out), the HOST ONLINE / JOIN ONLINE forms' typed fields and cursor, the
## lobby's cursor, the kick row's pick and whether ENTER was pressed once on
## it, a line for those screens, asking to leave a match (ESC), and the
## match's own clock: time and mouse saved up toward the next tick.
var net: NetPlay = null
var net_old: Array = []
var net_form := {}
var net_row := 0
var lobby_row := 0
var net_kick := 0
var net_kick_armed := false
var net_note := ""
var net_leave := false
var net_accum := 0.0
var net_turn := 0.0
var net_look := 0.0
## A client's own player eased over prediction corrections (net_predict.gd).
var net_smooth := NetPredict.Smoother.new()
## Online from the command line (tests, a quick game with friends):
## --host-online[=port] or --join-online=<code or address>, --online-name=,
## --online-password=; for tests --online-start=<players> (the host starts
## once that many are in and ready, everyone readies by themselves),
## --online-map= and --online-bot (project folder: a bot plays this
## machine's player).
var online_args := {}
## --mode=tagteam: the 2v2 format (Modes.TAGTEAM_*).
var tag_team_arg := false
var online_pilot: Variant = null

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
## What the pointer is over on the settings screen ("back", "tab2", "up"...)
## for the hover light, where it last was, and what a held button is dragging
## ("bar": a level setting's bar, "track": the scroll groove).
var hover_part := ""
var pointer := Vector2(-1, -1)
var drag_mode := ""
## A finger on the settings list: whether it is down, how far it has travelled
## and the part of a row it has dragged the list by (a drag scrolls, a tap picks).
var touch_travel := 0.0
var touch_carry := 0.0
var touch_down := false
## A pad in the menus: the direction held (stick or D-pad) and the time to
## its next repeat.
var pad_dir := Vector2i.ZERO
var pad_repeat := 0.0
## True while key() handles a held key's repeat (keyboard or pad), not a press.
var key_echo := false

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
## --dev="cmd;cmd": developer console commands to run once a level starts.
var dev_commands := ""
## --server=<level>: run that chapter as a network game's host, with no window
## work (server_loop.gd), with --server-players=N players, quitting after
## --server-ticks=N ticks (0: never), reporting every --server-report=S
## seconds, at --server-difficulty=D.
var server_level := ""
var server_players := 1
var server_ticks := 0
var server_report := 5.0
var server_difficulty := 1
## --lobby-server=<config.json>: always-open online lobbies with no host
## player (src/net/lobby_server.gd), no window work.
var lobby_server := ""
## The game mode (src/modes/, CLAUDE.md "Modes"): --mode=<name> --players=<n>
## [--arena=<level>[:<boss>]] [--level=<chapter>] [--frag-limit=] [--time-limit=].
## "" is the campaign. The players past the first are played by
## tools/mode_bot.gd (project folder only), one pilot a slot.
var mode_name := ""
var mode_players := 1
var mode_options := {}
var mode_level := ""
var pilots := {}
const BOT := "res://tools/mode_bot.gd"
var frame_count := 0
## The crash and error log (crash_log.gd; null in tools and the browser) and
## the controls the last play frame handed the game (its context).
var crash_log: CrashLog = null
var last_controls: Game.Controls = null
## The run's replay (replay_keeper.gd: recorded from a local game's first
## tick, written at a death, the end or a crash), the replay playing in the
## game's view instead of the keys (--replay=, null: none) and its file.
var replays := ReplayKeeper.new()
var replay_play: Replay.Playback = null
var replay_file := ""


func _parse_smoke() -> void:
	LaunchArgs.parse_smoke(self)


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
	var style: int = options.get("aspect", 0)
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
	touch.set_showing(state == "play" and not CountyScreens.covering(game))


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
		grab(not game.showing_tally and not game.defeated())


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
			"COUNTY RUN",
			"COUNTY HUB",
			"REPLAY LEVEL",
			"LEAVE RANGE" if in_range() else "FIRING RANGE",
			"LEAVE REMATCH" if in_rematch() else "BOSS REMATCH",
			"MULTIPLAYER",
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


## The firing range (data/range.json) is the game in play: practice, never
## saved, never the campaign.
func in_range() -> bool:
	return game != null and game.level.id == RANGE_ID


## A boss rematch is the game in play: never saved, never the campaign.
func in_rematch() -> bool:
	return BossRematch.active(game)


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
	var gate: LevelData.Gate = target.world.return_gate
	if gate == null:
		return
	if absf(p.x - gate.x) < gate.width * 0.5 and absf(p.y - gate.y) < 3.0:
		if (p.y - gate.y) * gate.side < -0.30:
			var x: float = gate.x
			var y: float = gate.y + gate.side * 1.65
			p.eye += target.world.elevation(x, y) - target.world.stand(p)
			p.x = x
			p.y = y
		p.angle = gate.side * PI / 2.0
		p.pitch = 0.0
		p.vx = 0.0
		p.vy = 0.0


## The menu theme, for every screen that is not the game itself. It keeps its
## place while play is paused, and the chapter's own track keeps its bookmark.
## MENU MUSIC off holds it paused.
func menu_music() -> void:
	sound.set_score("title")
	var menu_on: int = options.get("menu_music", 1)
	sound.pause_score(menu_on == 0)


## MASTER VOLUME on the mixer's last bus, silent while another window has the
## focus when MUTE IN BACKGROUND is on.
func apply_master() -> void:
	var master: float = options.get("master", 100)
	var level := master / 100.0
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(level, .001)))
	var bg_mute: int = options.get("bg_mute", 0)
	AudioServer.set_bus_mute(0, level <= 0.0 or (bg_mute != 0 and not focused))


## Back to whatever the game in progress should be playing.
func play_music() -> void:
	var target := game
	if target == null:
		return
	sound.set_score(
		"victory" if target.showing_tally else ("title" if target.in_hub else target.level.score)
	)
	sound.pause_score(target.defeated())


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
		or current.level.id == RANGE_ID
		or BossRematch.active(current)
		or CountyMode.active(current)
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
	var effects_level: float = options["effects"]
	var music_level: float = options["music"]
	var ambience_level: float = options["ambience"]
	var stereo: int = options["stereo"]
	sound.set_levels(effects_level / 100.0, music_level / 100.0, ambience_level / 100.0, stereo)
	var footsteps: float = options["footsteps"]
	sound.footstep_gain = footsteps / 100.0
	var reverb: int = options.get("reverb", 1)
	sound.reverb_on = reverb != 0
	if not sound.reverb_on:
		sound.set_space("")
	var voice_volume: float = options["voice_volume"]
	sound.voice_gain = voice_volume / 100.0
	apply_master()
	var lights: int = options.get("lights", 1)
	Effects.enabled = lights != 0
	var shadows: int = options.get("shadows", 1)
	View.shadows = shadows != 0
	var text_size: int = options.get("text_size", 0)
	HUD.text_style = ["body", "menu", "heading"][clampi(text_size, 0, 2)]
	var small_text: int = options.get("small_text", 0)
	PixelType.clear_small = small_text != 0
	var hud_mode: int = options.get("hud_mode", 0)
	hud.minimal = hud_mode == 1
	var kill_mode: int = options.get("kill_cam", KillCam.BOSSES)
	kill_cam.mode = kill_mode
	var quality: int = options.get("quality", 0)
	Quality.physics = Quality.tier_of(quality, quality_measured, mobile)
	var tilt_aim: int = options.get("tilt_aim", 0)
	if tilt_aim != 0:
		TiltAim.enable()
	var touch_layout: int = options.get("touch_layout", 0)
	if touch_layout == 2:
		# MOVE THEM is a doing, not a state: it opens the editor and reads MY LAYOUT.
		options["touch_layout"] = 1
		touch.start_editing()
	touch_layout = options.get("touch_layout", 0)
	touch.use_custom = touch_layout == 1
	touch.layout(touch.area, true)
	var brightness: int = options["brightness"]
	_build_tone(brightness)
	# Smoke runs count frames, not seconds: leave them uncapped.
	Engine.max_fps = 0 if smoke or web else roundi(1.0 / frame_interval())
	# REPLAYS: local games are recorded (never a tool's, a tour's or a bench's).
	var keep_replays: int = options.get("replays", 1)
	replays.enabled = (
		keep_replays != 0
		and replay_play == null
		and Engine.get_main_loop().get_script() == null
		and view_tour == ""
		and view_bench == 0
		and not smoke
		and not demo
		and not showcase
	)
	if game != null:
		game.configure(options)
		game.tone = tone_table
		replays.options_changed(game, options)


func frame_interval() -> float:
	var limit: int = options.get("frame_limit", 1)
	var rate: int = [30, 60, 120, 144, 240][clampi(limit, 0, 4)]
	return 1.0 / float(rate)


func _build_tone(level: int) -> void:
	if level == 100:
		tone_table = null
		return
	var table := PackedByteArray()
	table.resize(256)
	for i in 256:
		table[i] = clampi(roundi(pow(float(i) / 255.0, 100.0 / float(level)) * 255.0), 0, 255)
	tone_table = table


## An action of this machine's player between ticks (a key, the wheel, a
## card): done, and kept in the run's replay (replay_keeper.gd). Nothing
## while a replay plays.
func act(target: Game, op: Array) -> Variant:
	if replay_play != null:
		return null
	return replays.act(target, op)


func persist_options() -> void:
	# A tool driving the game (a SceneTree script: tools/check_fixes.gd and the
	# like) keeps settings in memory: it must never write the player's profile.
	if Engine.get_main_loop() != null and Engine.get_main_loop().get_script() != null:
		return
	if not SessionStore.save_settings("", options):
		menu_note = "SETUP COULD NOT BE SAVED."


func _char_for(code: int) -> int:
	if code >= KEY_A and code <= KEY_Z:
		return 97 + (code - KEY_A)
	return 0


## period_palette.apply() on the CPU: the screen gets the 256-colour grade from
## display.gdshader, but a saved screenshot has to carry it in its pixels, as
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
		if game.showing_tally or game.defeated():
			# X: the chapter's start when A retries a boss fight (boss_checkpoint.gd).
			return [
				[JOY_BUTTON_A, KEY_ENTER],
				[JOY_BUTTON_START, KEY_ENTER],
				[JOY_BUTTON_B, KEY_ESCAPE],
				[JOY_BUTTON_X, KEY_R]
			]
		return [
			[JOY_BUTTON_X, KEY_R],
			[JOY_BUTTON_Y, KEY_E],
			[JOY_BUTTON_LEFT_SHOULDER, KEY_SEMICOLON],
			[JOY_BUTTON_RIGHT_SHOULDER, KEY_APOSTROPHE],
			[JOY_BUTTON_START, KEY_ESCAPE],
			[JOY_BUTTON_BACK, KEY_TAB],
			# With the map open, up and down zoom it instead.
			[JOY_BUTTON_DPAD_UP, KEY_PAGEUP if game.map else KEY_C],
			[JOY_BUTTON_DPAD_LEFT, KEY_B],
			[JOY_BUTTON_DPAD_RIGHT, KEY_M],
			[JOY_BUTTON_DPAD_DOWN, KEY_PAGEDOWN if game.map else KEY_F]
		]
	# The menus: the D-pad and the left stick move the cursor and repeat while
	# held (main_input.gd _pad_menu); Y resets a settings page.
	return [
		[JOY_BUTTON_A, KEY_ENTER],
		[JOY_BUTTON_START, KEY_ENTER],
		[JOY_BUTTON_B, KEY_ESCAPE],
		[JOY_BUTTON_Y, KEY_R if state == "setup" else KEY_NONE],
		[JOY_BUTTON_LEFT_SHOULDER, KEY_PAGEUP],
		[JOY_BUTTON_RIGHT_SHOULDER, KEY_PAGEDOWN]
	]


## PAD DEADZONE: how far a stick moves before it counts.
func _deadzone(value: float) -> float:
	var pad_dead: int = options.get("pad_deadzone", 1)
	var dead: float = [.10, .18, .28][clampi(pad_dead, 0, 2)]
	return 0.0 if absf(value) < dead else value


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
	[7.0, KEY_DOWN],
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
	if net != null:
		net.leave("THE HOST QUIT" if net.role == NetPlay.Role.HOST else "LEFT")
		net.flush_leave()
	for old: NetPlay in net_old:
		old.finish()
	replays.settle()
	if crash_log != null:
		crash_log.close()
		crash_log = null
	Weapons.Armory.settle()
	if canvas != null:
		canvas.gpu_free()


func _save_view() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(view_shot)
	get_tree().quit()


## Hand this frame's look to the display shader (see display.gdshader).
func _look_uniforms() -> void:
	var playing := gpu_look and game != null and state not in MENU_STATES
	var look_on := playing and game.look_live
	var tone_on := playing and game.tone_live
	palette_material.set_shader_parameter("hurt", game.hurt_alpha if playing else 0)
	palette_material.set_shader_parameter("look", look_on)
	palette_material.set_shader_parameter("tone_on", tone_on)
	if look_on:
		var w: Array = Game.WASH.get(game.level.id, [255, 255, 255, 0])
		var amount: float = w[3]
		var wr: float = w[0]
		var wg: float = w[1]
		var wb: float = w[2]
		palette_material.set_shader_parameter(
			"wash",
			Vector3(
				1.0 - amount + wr / 255.0 * amount,
				1.0 - amount + wg / 255.0 * amount,
				1.0 - amount + wb / 255.0 * amount
			)
		)
		palette_material.set_shader_parameter("gain", game._look_gain)
		palette_material.set_shader_parameter("blast", game._look_blast)
		palette_material.set_shader_parameter("grain_frame", game._look_frame)
	if tone_on and tone_table != tone_sent:
		tone_sent = tone_table
		var table: PackedByteArray = tone_table
		_grain_tone(table)


## The palette table, the grain frames and the brightness table, as one
## texture (the shader may only sample so many): see display.gdshader `looks`.
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
		if PhotoMode.allowed(self):
			return "D-PAD MOVE / A PICK / B BACK / Y PHOTO"
		return "STICK OR D-PAD MOVE / A PICK / B BACK"
	return "ARROWS MOVE / ENTER SELECT"


## The button that uses things, as the play prompts name it: USE on a touch
## screen, Y on a controller, else the key USE is bound to (KEYS page).
func use_button() -> String:
	if input_device == "touch":
		return "USE"
	if input_device == "pad":
		return "Y"
	var use_key: int = options.get(KeyBindings.option_key("use"), KEY_E)
	return KeyBindings.key_name(use_key)


## The rematch board's and result's line on how to drive them.
func rematch_guide() -> String:
	var board := state == "rematch"
	if input_device == "touch":
		return "TAP A BOSS TO FIGHT" if board else "TAP FOR THE BOARD"
	if input_device == "pad":
		return "D-PAD MOVE / A FIGHT / B BACK" if board else "A BOARD / B TITLE"
	return "ARROWS MOVE / ENTER FIGHT / ESC BACK" if board else "ENTER BOARD / ESC TITLE"


func setup_guide() -> String:
	if input_device == "touch":
		return "TAP A ROW, THEN A SIDE / DRAG TO SCROLL"
	if input_device == "pad":
		return "LB RB PAGE / D-PAD CHANGE / Y RESET"
	return "TAB PAGE / ARROWS CHANGE / R RESET"


func render_setup() -> void:
	var pages := SessionStore.setup_pages()
	option_scroll = Menu.scroll_for(option_page, option_slot, option_scroll)
	var confirm := ""
	if not display_trial.is_empty():
		var trial_left: float = display_trial["left"]
		var left := int(ceilf(trial_left))
		if input_device == "touch":
			confirm = "TAP KEEP OR UNDO  (%d)" % left
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
		confirm,
		"reset" if reset_armed > 0.0 else hover_part,  # an armed reset stays lit
		binding_action
	)


func render_slots() -> void:
	var kind := "REPLAY" if slot_replay != "" else "CAMPAIGN"
	menu_panel(kind + " SAVE SLOTS")
	for pair: Array in [["save", 23], ["load", 161]]:
		var mode := str(pair[0])
		var x: int = pair[1]
		canvas.fill_rect(
			x, 35, 135, 13, Canvas.rgb(96, 58, 34) if slot_mode == mode else Canvas.rgb(53, 37, 29)
		)
		HUD.text(canvas, mode.to_upper(), x + 67, 38, "body", HUD.INK, true)
	for i in slots.size():
		var entry: Array = slots[i]
		var digest: Variant = entry[1]
		var meta: Variant = entry[2]
		var y := SLOT_TOP + i * SLOT_ROW
		var active := slot_index == i
		canvas.fill_rect(
			23, y, 273, SLOT_ROW - 2, Canvas.rgb(75, 48, 32) if active else Canvas.rgb(39, 28, 22)
		)
		var label := "FILE UNREADABLE" if (digest is String and str(digest) == "") else "EMPTY"
		var level := ""
		var stamp := ""
		if meta != null:
			var info: Array = meta
			label = str(info[0])
			level = str(info[1]).to_upper()
			stamp = str(info[3])
		HUD.text(
			canvas, "%d  %s" % [i + 1, label], 28, y + 4, "body", HUD.AMBER if active else HUD.INK
		)
		HUD.text(canvas, level, 291, y + 4, "body", HUD.INK, false, true, true)
		HUD.text(canvas, stamp, 28, y + 14, "mini", HUD.INK, false, false)
	var selected: Variant = slots[slot_index][2]
	var picked: Array = [] if selected == null else selected
	var lines: Array = []
	var guide := "TAB SAVE / LOAD   ENTER SELECT   ESC BACK"
	if slot_stage == "edit":
		var fallback := ("SLOT %d" % (slot_index + 1)) if selected == null else str(picked[0])
		lines = ["NAME  " + (slot_name if slot_name != "" else fallback) + "_"]
		guide = "ENTER CONTINUE / ESC CANCEL"
	elif slot_stage == "overwrite":
		lines = ["REPLACE " + str(picked[0]) + "?"]
		guide = "ENTER OVERWRITE / ESC KEEP SAVE"
	else:
		var text := menu_note
		if text == "":
			text = "QUICKSAVE IS SEPARATE." if selected == null else str(picked[2])
		var wrapped := PixelType.wrap(text, 270)
		for i in mini(2, wrapped.size()):
			lines.append(wrapped[i])
	for i in lines.size():
		HUD.text(canvas, str(lines[i]), 160, 153 + i * 9, "body", HUD.AMBER, true)
	HUD.text(canvas, guide, 132, 181, "mini", HUD.INK, true)
	if slot_stage == "choose":
		Menu.plate_button(canvas, Menu.BACK, "BACK", hover_part == "back")


func _blit_art(name: String, x: int, y: int) -> void:
	var sheet := art.art(name)
	var data: PackedByteArray = sheet["data"]
	var w: int = sheet["w"]
	var h: int = sheet["h"]
	canvas.blit_rgba(data, w, h, x, y, "art|" + name)


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
	# The HUD's Control nodes first, under everything the canvas draws.
	hud_layer = HudLayer.new(hud)
	overlay.add_child(hud_layer)
	hud.controls = true
	var painter := Node2D.new()
	overlay.add_child(painter)
	canvas.gpu = true
	canvas.gpu_parent = painter.get_canvas_item()
	palette_material.set_shader_parameter("post_tex", overlay.get_texture())
	palette_material.set_shader_parameter("overlay_on", true)


func render() -> void:
	LobbyScreens.clear_zones()
	canvas.layer = false
	canvas.base_set = false
	if canvas.gpu:
		canvas.gpu_begin()
	if game != null:
		game.scene_live = false
	hud.shown_game = null
	# The menus' little motions follow SCENERY MOTION, SCREEN FLASH and LAMP FLICKER.
	var flashes: int = options.get("flashes", 0)
	var flicker: int = options.get("flicker", 1)
	var steady := flashes != 0 or flicker == 0
	menu.clock = menu_clock
	var world_motion: int = options.get("world_motion", 0)
	menu.motion = world_motion
	menu.steady = steady
	if ui != null and ui.show_state(state):
		# Every menu is a screen of its own (src/ui/screens/).
		ui.shown().render(canvas)
	elif game != null:
		gpu_look = gpu_ready and not cpu_look and (not smoke or view_shot != "")
		game.gpu_look = gpu_look
		# With a window the 3D view draws the world (view3d/world_view.gd); a
		# headless run draws no world at all, only the canvas.
		game.layered = gpu_look and canvas.gpu
		game.view3d = game.layered
		var crosshair: int = options["crosshair"]
		if kill_cam.playing:
			kill_cam.draw(self)  # the replay from its own camera, no HUD
		else:
			game.draw(canvas, crosshair, true)
			_frame_3d()
			kill_cam.record(self)
			photo.draw(self)
		if TacticalScreens.open and Modes.is_tactical(game) and not game.showing_tally:
			TacticalScreens.draw_shop(canvas, game, Modes.feature(game))
		CountyScreens.draw_over(canvas, game)  # a COUNTY RUN's HUD, cards and end
		if net != null and state == "play":
			LobbyScreens.draw_match(canvas, net, game, net_leave)
		var show_fps: int = options.get("show_fps", 0)
		if show_fps != 0 and not touring:
			# FRAME COUNTER: frames per second, top right, over the view.
			HUD.text(
				canvas,
				"%d FPS" % roundi(Engine.get_frames_per_second()),
				316,
				2,
				"mini",
				HUD.AMBER,
				false,
				true,
				true
			)
		if editor != null and editor.active:
			editor.draw(canvas)
		if console != null:
			console.draw(canvas)
	else:
		canvas.clear(0, 0, 0)
	_look_uniforms()
	photo.uniforms(self)
	if hud_layer != null:
		hud_layer.show_frame()

	if canvas.pixels.size() != WIDTH * HEIGHT * 3:
		canvas.resize(WIDTH, HEIGHT)
	# On a Godot 2D canvas the pixels only matter when they hold a software view.
	if not canvas.gpu or canvas.base_set:
		frame_image.set_data(WIDTH, HEIGHT, false, Image.FORMAT_RGB8, canvas.pixels)
		frame_texture.update(frame_image)
	if canvas.gpu:
		palette_material.set_shader_parameter("base_on", canvas.base_set)
	_apply_view()


## Hand game.view_frame to the 3D view now (the KILL CAM's replay frames).
func show_view() -> void:
	_frame_3d()


## Hand this frame to the 3D view (made the first time it is wanted) and tell
## the display shader whether its picture is the view.
func _frame_3d() -> void:
	var on := game != null and game.view3d and not game.view_frame.is_empty()
	if on:
		if world_view == null:
			world_view = WorldView3D.new(art)
			add_child(world_view)
			palette_material.set_shader_parameter("view3d_tex", world_view.texture())
		world_view.frame(game)
		palette_material.set_shader_parameter("view_mul", 2 if game.view.detail < 0 else 1)
		palette_material.set_shader_parameter("view_div", 1 << maxi(game.view.detail, 0))
		palette_material.set_shader_parameter("anim_time", fposmod(game.clock, 3600.0))
		HeatHaze.apply(palette_material, game)
		palette_material.set_shader_parameter("drunk", game.drunk_k)
		if game.drunk_k > 0.0:
			var ghost := int(2 + 4 * game.drunk_k)
			palette_material.set_shader_parameter("drunk_phase", fposmod(game.clock * 3.1, TAU))
			palette_material.set_shader_parameter(
				"drunk_ghost", -ghost if sin(game.clock * 1.7) <= 0.0 else ghost
			)
	if world_view != null:
		world_view.viewport.render_target_update_mode = (
			SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
		)
	palette_material.set_shader_parameter("view3d_on", on)
