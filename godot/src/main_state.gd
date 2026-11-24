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
## A save slot question's answers for a finger, in the footer's halves a tap
## reads (main_input.gd click: y 171..190, left of 160 goes on).
const SLOT_GO := Rect2i(40, 175, 104, 13)
const SLOT_STOP := Rect2i(176, 175, 104, 13)
const TITLE := "Crazy Legs Mundell Rampage | The Hickston Incident"

## The keyboard page: {action} is the key bound to it (KEYS page), filled in
## by ControlsScreen.rows_of().
const CONTROL_ROWS := [
	["{forward}{strafe_left}{back}{strafe_right} / MOUSE", "MOVE / AIM"],
	["{run} / {jump} / {crouch}", "RUN / JUMP / CROUCH"],
	["MOUSE 1 / 2", "FIRE / THE GUN'S OTHER FIRE"],
	["1-9 0 - = / WHEEL", "PICK A GUN / NEXT GUN"],
	["{reload} / 8 + HOLD", "RELOAD / LIGHT TNT, LET GO"],
	["{use} / SPACE / MMB", "USE: OPEN, TOTE, BOOT"],
	["TOTING: MOUSE 1/2", "CHUCK IT / SET IT DOWN"],
	["{next_item} / {use_item}", "PICK AN ITEM / HAVE IT"],
	["C / B / M", "RINDS / BEER / MOONSHINE"],
	["{whistle} / {flashlight}", "WHISTLE FOR BLUE / FLASHLIGHT"],
	["{map} / F5 F6 F9", "MAP / SLOTS, SAVE, LOAD"],
]
const PAD_ROWS := [
	["LEFT / RIGHT STICK", "MOVE / AIM"],
	["RIGHT TRIGGER", "FIRE"],
	["LEFT TRIGGER", "WEAPON ALT FIRE"],
	["A / B", "JUMP / CROUCH"],
	["X / Y", "RELOAD / USE, TOTE, BOOT"],
	["BUMPERS", "PREVIOUS / NEXT WEAPON"],
	["L3 / R3 STICK CLICK", "RUN / FLASHLIGHT"],
	["D-PAD UP LEFT RIGHT", "RINDS / BEER / MOONSHINE"],
	["D-PAD DOWN", "USE THE PICKED ITEM"],
	["START / BACK", "PAUSE / MAP"],
	["HOLD BACK", "WHISTLE FOR BLUE"],
]
const TOUCH_ROWS := [
	["LEFT THUMB STICK", "MOVE"],
	["DRAG RIGHT HALF", "AIM"],
	["FIRE / ALT", "FIRE / WEAPON ALT FIRE"],
	["USE", "OPEN / TOTE / BOOT"],
	["NEXT", "NEXT WEAPON"],
	["JUMP / DUCK", "JUMP / CROUCH"],
	["RIND BEER SHINE", "EAT OR DRINK"],
	["LIGHT / WHISTLE", "FLASHLIGHT / CALL BLUE"],
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

## The game on screen. Each change has the games let go disposed at the
## frame's end (release_games(): a game never frees itself, game.gd dispose()).
var game: Game = null:
	set(value):
		game = value
		_release_due()
## Every game made here (make_game), for release_games().
var games := GamePool.new()
var _release_queued := false
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
## Single player drawn between its last two ticks (solo_blend.gd), and the
## ticks played (its clock: main.gd advance, replay_keeper.gd).
var solo_blend := SoloBlend.new()
var solo_ticks := 0
## The fast movers' sounds each drawn frame: the Doppler and the flight loops.
var movers := MoverSounds.new()
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
## What the canvas draws on in the overlay (centred on the picture in WIDE).
var painter: Node2D
var cpu_canvas := false
## The play HUD's Control nodes in the overlay (ui/hud/hud_layer.gd; none
## headless, where the HUD draws on the canvas), PHOTO MODE and the KILL CAM
## (photo_mode.gd, kill_cam.gd).
var hud_layer: HudLayer
var photo := PhotoMode.new()
var kill_cam := KillCam.new()
## A boss's fall shown as a cinematic (boss_ending.gd).
var boss_end := BossEnding.new()
## The chapter openers (opener.gd): the cinematic before a chapter's first tick.
var opener := ChapterOpener.new()
## QUALITY (core/quality.gd): the tier AUTO measured on this machine (-1 not
## yet), its measurement while it runs, and whether it may set the picture
## settings when done (only on a first run: no settings saved before).
var quality_measured := -1
var quality_meter: Quality.Meter = null
var quality_first := false
## The browser build's chapter packs, fetched after start (pack_loader.gd).
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
## Each chapter's pack in a browser build (tools/make_packs.gd pack_name).
const CHAPTER_PACKS := {
	"hickston": "chapter_hickston",
	"fair": "chapter_fair",
	"sawmill": "chapter_sawmill",
	"quarry": "chapter_quarry",
	"bayou": "chapter_bayou",
	"speedway": "chapter_speedway",
	"moonshine": "chapter_moonshine",
	"mothership": "chapter_mothership",
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
## The 3D view's warm-up under the title (warm_view): seconds a menu has been
## up, and whether it is done.
const TITLE_WARM_AFTER := .6
var title_wait := 0.0
var view_warmed := false
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
	"maps",
	"mapedit",
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
## Voice chat's mic, voices and marks while a lobby is up (main.gd).
var voice_chat: VoiceChat = null
## The pad's motors and the phone's buzz (main.gd drives them each frame).
var rumble := RumbleOut.new()
## Online co-op, the host: the chapter the party is in or left for the hub,
## picked up again through its gate (net_coop.gd).
var net_run: Game = null
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
## Everyone else drawn between ticks online (net_blend.gd).
var net_blend := NetBlend.new()
## An online client's own shots, reloads and pickups shown at once (net_shot_predict.gd).
var net_shots := NetShotPredict.new()
## Online from the command line (tests, a quick game with friends):
## --host-online[=port] or --join-online=<code or address>, --online-name=,
## --online-password=; for tests --online-start=<players> (the host starts
## once that many are in and ready, everyone readies by themselves),
## --online-map= and --online-bot (project folder: a bot plays this
## machine's player); --party-line=<address:port> another party line than
## servers.json's (a lobby server on this PC).
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
## Every finger on the glass (index -> true) and the one driving the menus
## (-1: none): main_input.gd _finger_echo, _menu_finger.
var fingers_down := {}
var menu_finger := -1
## A pad in the menus: the direction held (stick or D-pad) and the time to
## its next repeat.
var pad_dir := Vector2i.ZERO
var pad_repeat := 0.0
## The pad's BACK in play: how long it has been held (-1 up) and whether the
## hold already whistled for BLUE (a tap opens the map on its release).
var pad_back_held := -1.0
var pad_back_fired := false
## Seconds BACK is held before it whistles instead of opening the map.
const PAD_WHISTLE_HOLD := .4
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
## The update notice (update_notice.gd; null unless this launch asks the site).
var update_notice: UpdateNotice = null
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


## The picture's size in a window (PictureShape.size_for).
static func presentation_size(
	width: int, height: int, aspect: int, fill := false
) -> PackedInt32Array:
	return PictureShape.size_for(width, height, aspect, fill)


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


## The picture's columns: 320, or with WIDE as many as the screen's shape
## asks (only with the overlay: a window's Godot canvas; tools keep 320).
func picture_cols() -> int:
	var style: int = options.get("aspect", 0)
	if style != PictureShape.ASPECT_WIDE or overlay == null:
		return WIDTH
	var fill := fullscreen and fullscreen_mode == 1
	var bounds := Rect2(Vector2.ZERO, get_viewport_rect().size) if fill else safe_rect()
	return PictureShape.wide_cols(int(bounds.size.x), int(bounds.size.y))


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
	var cols := picture_cols()
	if cols != View.cols:
		PictureShape.fit(self, cols)
	var style: int = options.get("aspect", 0)
	View.square = style == PictureShape.ASPECT_WIDE and overlay != null
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
			"CUSTOM MAPS",
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
	return games.track(Game.new(art, hud, sound, level_id))


## Disposes, at the frame's end, the games made here that nothing keeps any
## more (GamePool): by then a change of level, retry, load, rematch or match
## has put every game it keeps in its place.
func _release_due() -> void:
	if not _release_queued and is_inside_tree():
		_release_queued = true
		release_games.call_deferred()


## The games kept: on screen, the campaign and the hub's, a replay, the ones
## waiting behind the range or a rematch or for their pictures, a match's,
## and any the kill cam, PHOTO MODE or the HUD still look at (each with the
## chapters it retains). Every other game made here is disposed.
func release_games() -> int:
	_release_queued = false
	var kept: Array = [
		game, campaign_run, hub_origin, range_return, rematch_return, waiting_play, net_run
	]
	kept.append_array(replay_runs.values())
	for each: Variant in [net] + net_old:
		if each is NetPlay:
			var link: NetPlay = each
			kept.append(link.match_game())
	kept.append_array(
		[kill_cam.game, boss_end.game, photo.game, hud.shown_game if hud != null else null]
	)
	kept.append_array([opener.game, opener.pending])
	return games.sweep(kept)


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
		or UserMap.is_custom(current.level.id)
	):
		return null
	return campaign_run if current.revisiting else current


## pg.key.start_text_input / stop_text_input: raises the on-screen keyboard
## where there is one, so a save slot can be named on a phone.
func _text_input(active: bool) -> void:
	if active and WebTyping.ask(self, "NAME THIS SAVE", slot_name, true):
		return  # a phone's browser: its own box, then the save goes on
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
	var radio: int = options.get("radio", RadioStation.DJ_AND_MUSIC)
	sound.station.mode = clampi(radio, 0, 2)
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
	boss_end.mode = kill_mode
	var opener_mode: int = options.get("openers", ChapterOpener.FIRST_TIME)
	opener.mode = opener_mode
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
		if replay_play == null:  # a replay plays on with the settings it was made with
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


## A point of the window as a pixel of the 320x200 canvas, or (-1, -1).
## In WIDE the canvas is centred on the picture: a point left of it is
## negative, one right of it past 319 (`edge` -1 or 1: as a HUD piece kept
## to that edge sees it, HudLayout.side_of).
func picture_point(position: Vector2, edge := 0) -> Vector2i:
	var rect := viewport_rect()
	if not rect.has_point(position):
		return Vector2i(-1, -1)
	return Vector2i(
		(
			int(floorf((position.x - rect.position.x) * View.cols / rect.size.x))
			- View.shift * (1 + edge)
		),
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
			# BACK: a tap the map, held the whistle (main_input.gd _pad_back).
			# The pad's share or capture button whistles for BLUE too.
			[JOY_BUTTON_MISC1, KEY_G],
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
	rumble.stop()
	games.clear()
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
		palette_material.set_shader_parameter("gain", game.screen_look.gain)
		palette_material.set_shader_parameter("blast", game.screen_look.blast)
		palette_material.set_shader_parameter("grain_frame", game.screen_look.frame)
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


## Ask the site whether a newer version is out, once a run, when this launch
## may (UpdateNotice.wanted): at start, or when CHECK FOR UPDATES is turned on.
func start_update_check() -> void:
	if update_notice != null or not UpdateNotice.wanted(self):
		return
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	update_notice = UpdateNotice.new(version, UpdateNotice.platform())
	add_child(update_notice)
	update_notice.ask()


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


## The FLASHLIGHT key as the blackout names it: the bound key, R3 (the right
## stick's click) on a controller, the LIGHT button on a touch screen.
func torch_button() -> String:
	if input_device == "touch":
		return "LIGHT"
	if input_device == "pad":
		return "R3"
	var torch_key: int = options.get(KeyBindings.option_key("flashlight"), KEY_L)
	return KeyBindings.key_name(torch_key)


## Whether this machine's player has a flashlight now (a blackout): R3 and
## the touch LIGHT button work it then.
func has_torch() -> bool:
	if game == null or state != "play":
		return false
	var ev: CountyEvents = game.features.get("events")
	return ev != null and not ev.torch_of(game.local_player).is_empty()


## Whether this machine's player has BLUE along: the touch WHISTLE button.
func hound_along() -> bool:
	if game == null or state != "play":
		return false
	var hound: Game.HoundScript = game.features.get("hound")
	return hound != null and hound.dog_of(game.local_player) != null


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
	# A finger answers a question with the footer's halves (main_input.gd
	# click): left goes on, right backs out, so they are plates to tap.
	var plates: Array[String] = []
	if slot_stage == "edit":
		var fallback := ("SLOT %d" % (slot_index + 1)) if selected == null else str(picked[0])
		lines = ["NAME  " + (slot_name if slot_name != "" else fallback) + "_"]
		guide = "ENTER CONTINUE / ESC CANCEL"
		plates = ["SAVE IT", "CANCEL"]
	elif slot_stage == "overwrite":
		lines = ["REPLACE " + str(picked[0]) + "?"]
		guide = "ENTER OVERWRITE / ESC KEEP SAVE"
		plates = ["OVERWRITE", "KEEP SAVE"]
	else:
		var text := menu_note
		if text == "":
			text = "QUICKSAVE IS SEPARATE." if selected == null else str(picked[2])
		var wrapped := PixelType.wrap(text, 270)
		for i in mini(2, wrapped.size()):
			lines.append(wrapped[i])
	for i in lines.size():
		HUD.text(canvas, str(lines[i]), 160, 153 + i * 9, "body", HUD.AMBER, true)
	if input_device == "touch" and not plates.is_empty():
		Menu.plate_button(canvas, SLOT_GO, plates[0])
		Menu.plate_button(canvas, SLOT_STOP, plates[1])
	else:
		if input_device == "touch":
			guide = "TAP SAVE OR LOAD, THEN A SLOT"
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
	overlay.size = Vector2i(View.cols, HEIGHT)
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
	painter = Node2D.new()
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
	# A finger was the last input: the menus' hints speak to it.
	menu.touch_words = input_device == "touch"
	LobbyScreens.touch_words = menu.touch_words
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
		_pin_hud()
		if boss_end.playing:
			boss_end.draw(self)  # a boss's fall from its own camera, no HUD
		elif kill_cam.playing:
			kill_cam.draw(self)  # the replay from its own camera, no HUD
		elif opener.playing:
			opener.draw(self)  # a chapter's opener: its own camera, no HUD
		else:
			game.draw(canvas, crosshair, true)
			_frame_3d()
			kill_cam.record(self)
			photo.draw(self)
		if TacticalScreens.open and Modes.is_tactical(game) and not game.showing_tally:
			TacticalScreens.draw_shop(canvas, game, Modes.feature(game))
		BenchScreen.draw(canvas, game)  # the junk bench's board, when it is up
		CountyScreens.draw_over(canvas, game)  # a COUNTY RUN's HUD, cards and end
		if net != null and state == "play":
			LobbyScreens.draw_match(canvas, net, game, net_leave)
		if voice_chat != null:
			voice_chat.draw(canvas, self)
		var show_fps: int = options.get("show_fps", 0)
		if show_fps != 0 and not touring:
			# FRAME COUNTER: frames per second, top right, over the view.
			HudLayout.begin(canvas, "fps")
			HUD.text(
				canvas,
				"%d FPS" % roundi(Engine.get_frames_per_second()),
				316,
				HudLayout.TOP,
				"mini",
				HUD.AMBER,
				false,
				true,
				true
			)
			HudLayout.end(canvas)
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


## The pieces drawn over play after it (the frame counter, the online
## ping) keep the top right corner, and the touch buttons over the view keep
## their places: the HUD's layout fits the rest round them
## (ui/hud/hud_layout.gd). The move stick is the thumb's, not a place: the
## badge and the plates sit under it as before.
func _pin_hud() -> void:
	var pins: Array = []
	if touch != null and touch.showing:
		var picture := viewport_rect()
		var k := View.cols / maxf(1.0, picture.size.x)
		for b: Array in touch.shown_buttons():
			var middle: Vector2 = b[1]
			var radius: float = b[2]
			var at := (middle - picture.position) * k
			# WIDE: where the pieces kept to that half's edge see it.
			at.x -= 0.0 if at.x < View.cols * .5 else View.shift * 2.0
			var r := radius * k
			var box := Rect2i(Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0))
			if box.intersects(Rect2i(0, 0, 320, View.VIEW)):
				pins.append(["touch_" + str(b[0]), box])
	var show_fps: int = options.get("show_fps", 0)
	if show_fps != 0 and not touring:
		var fps := "999 FPS"
		var at := 316 - PixelType.text_width(fps, "mini")
		pins.append(["fps", HudLayout.text_rect(fps, at, HudLayout.TOP, "mini")])
	if net != null and state == "play":
		var ms := "999 MS"
		pins.append(
			["ping", HudLayout.text_rect(ms, 316 - PixelType.text_width(ms, "mini"), 12, "mini")]
		)
	if voice_chat != null:
		pins.append_array(voice_chat.pins(self))
	hud.layout.pinned = pins


func _make_world_view() -> void:
	world_view = WorldView3D.new(art)
	add_child(world_view)
	palette_material.set_shader_parameter("view3d_tex", world_view.texture())


## Before the first level, once a menu has been up TITLE_WARM_AFTER seconds:
## the 3D view made (about 0.18 s on the desktop, which the first level's
## load paid) and then its shaders compiled a piece a frame
## (WorldView3D.warm_title; pass 10). Starting a level first leaves the rest
## to its first frame, as before.
func warm_view(delta: float) -> void:
	if view_warmed or game != null or not gpu_ready or not canvas.gpu:
		return
	title_wait += delta
	if title_wait < TITLE_WARM_AFTER:
		return
	if world_view == null:
		_make_world_view()
		world_view.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	elif not world_view.warm_title():
		view_warmed = true


## Hand game.view_frame to the 3D view now (the KILL CAM's replay frames).
func show_view() -> void:
	_frame_3d()


## Hand this frame to the 3D view (made the first time it is wanted) and tell
## the display shader whether its picture is the view.
func _frame_3d() -> void:
	var on := game != null and game.view3d and not game.view_frame.is_empty()
	if on:
		if world_view == null:
			_make_world_view()
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
