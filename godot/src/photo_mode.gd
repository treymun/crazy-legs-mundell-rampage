## PHOTO MODE: play pauses and a free camera flies where the player looks
## (keys and mouse, a pad's sticks, the touch stick and a drag: whatever
## drives play, through main_input.gd _controls()), the gun, sights and HUD
## are off, a strip at the foot names the filter and the buttons, and a
## picture of the view is saved: to the Pictures folder ("Crazy Legs Mundell
## Rampage"), else the game's user folder (user://photos); the browser build
## downloads it. Entered with P in play, Y on a pad's pause screen, PHOTO on a
## touch screen; single player only. Looks only: nothing of play moves while
## it is up (the front end does not tick the game), and the view is drawn from
## game.eye_override (game_view.gd) with the player stood in it.
class_name PhotoMode
extends RefCounted

const DATA := "res://data/tuning/camera.cfg"
## The filters, in turn: PLAIN, FILM (the film look's grain, dither and
## wash), and the display shader's photo_filter 2 TINTYPE, 3 DUSK, 4
## MOONLIGHT. Every one still ends in the game's palette.
const FILTERS: Array[String] = ["PLAIN", "FILM", "TINTYPE", "DUSK", "MOONLIGHT"]
const STRIP := Color(22 / 255.0, 16 / 255.0, 13 / 255.0)
static var SPEED: float = _num("speed")
static var RUN_SPEED: float = _num("run_speed")
static var REACH: float = _num("reach")
static var CLEARANCE: float = _num("clearance")
static var SCALE: int = int(_num("scale"))
static var NOTE_TIME: float = _num("note_time")

var on := false
var game: Game
var x := 0.0
var y := 0.0
var z := 0.0
var angle := 0.0
var pitch := 0.0
var filter := 0
## The strip at the foot hidden (H, a pad's Y, USE).
var bare := false
var note := ""
var note_left := 0.0
var _fired := true
## Where pictures go (empty: Pictures, else user://photos); the checks set it.
var out_dir := ""
## The last picture written (its full path), for the checks.
var last_saved := ""
var _filter_sent := -1


static func _num(key: String) -> float:
	var v: float = Tuning.file(DATA).get_value("photo", key, 0.0)
	return v


## Whether PHOTO MODE may open now: single player, in play, alive.
static func allowed(m: MainState) -> bool:
	var g := m.game
	return (
		g != null
		and m.net == null
		and g.players.size() == 1
		and g.player.health > 0
		and not g.showing_tally
		and not g.defeated()
		and not CountyScreens.covering(g)
		# Never over a chapter's opener or the KILL CAM (their pictures are
		# drawn instead, so the camera would fly unseen): the pause screen's
		# Y while one waited behind it.
		and not m.opener.playing
		and not m.kill_cam.playing
	)


## Open it at the player's eye.
func enter(m: MainState) -> bool:
	if on or not allowed(m):
		return false
	game = m.game
	var p := game.player
	var eye := p.as_render_player()
	x = p.x
	y = p.y
	z = eye["eye"]
	angle = eye["view_angle"]
	pitch = p.pitch
	on = true
	bare = false
	note = ""
	note_left = 0.0
	_fired = true
	game.eye_override = eye_now()
	m.state = "play"
	m.sound.play("menu_accept")
	return true


func leave(m: MainState) -> void:
	if not on:
		return
	on = false
	if game != null:
		game.eye_override = {}
	game = null
	m.sound.play("menu_back")


## The eye the view is drawn from.
func eye_now() -> Dictionary:
	return {"x": x, "y": y, "eye": z, "view_angle": angle, "pitch": pitch, "bob": 0.0, "sway": 0.0}


## One frame: fly by the controls (forward, strafe, turn, look; jump up,
## crouch down, run faster); fire saves a picture.
func frame(m: MainState, dt: float, c: Game.Controls) -> void:
	if not on:
		return
	if game != m.game or m.game == null:
		leave(m)
		return
	note_left = maxf(0.0, note_left - dt)
	angle = fposmod(angle + c.turn, TAU)
	pitch = clampf(pitch + c.look, -70.0, 70.0)
	var speed := (RUN_SPEED if c.running else SPEED) * dt
	var fx := cos(angle)
	var fy := sin(angle)
	var mx := (fx * c.forward - fy * c.strafe) * speed
	var my := (fy * c.forward + fx * c.strafe) * speed
	var rise := ((1.0 if c.jump else 0.0) - (1.0 if c.crouch else 0.0)) * speed
	fly(mx, my, rise)
	if c.fire and not _fired:
		save(m)
	_fired = c.fire
	game.eye_override = eye_now()


## Move the camera by (dx, dy, dz), sliding along walls, kept off floors and
## ceilings and within REACH of the player.
func fly(dx: float, dy: float, dz: float) -> void:
	var level := game.world
	var p := game.player
	for step: Vector2 in [Vector2(dx, 0.0), Vector2(0.0, dy)]:
		var nx := x + step.x
		var ny := y + step.y
		if step == Vector2.ZERO:
			continue
		if nx < 1.0 or ny < 1.0 or nx > level.width - 1.0 or ny > level.height - 1.0:
			continue
		if Vector2(nx - p.x, ny - p.y).length() > REACH:
			continue
		if level.blocked(nx, ny, CLEARANCE, z - .5):
			continue
		x = nx
		y = ny
	var ground := level.floor_under(x, y, z)
	var top := level.roof_over(x, y, z)
	var highest := (top - CLEARANCE) if top > 0.0 else ground + 8.0
	z = clampf(z + dz, ground + CLEARANCE + .1, maxf(ground + CLEARANCE + .1, highest))


## A key while it is up: true when it was PHOTO MODE's (every key but the
## window's own is, so nothing of play moves).
func key(m: MainState, code: int) -> bool:
	if not on:
		return false
	match code:
		KEY_ESCAPE, KEY_P:
			leave(m)
		KEY_R, KEY_TAB, KEY_BRACKETRIGHT:
			next_filter(m, 1)
		KEY_BRACKETLEFT:
			next_filter(m, -1)
		KEY_H, KEY_E:
			bare = not bare
		KEY_ENTER, KEY_KP_ENTER, KEY_F12, KEY_F:
			save(m)
		KEY_F11, KEY_F4:
			return false
	return true


func next_filter(m: MainState, step: int) -> void:
	filter = posmod(filter + step, FILTERS.size())
	m.sound.play("menu_move")


## Hand the filter to the display shader (every frame; sent when it changes).
func uniforms(m: MainState) -> void:
	var want := filter if on else 0
	if want != _filter_sent:
		_filter_sent = want
		m.palette_material.set_shader_parameter("photo_filter", want)
	if on and filter == 1 and m.gpu_look:
		# FILM: the film look's pass, as FILM GRAIN + COLOR WASH draws it.
		m.palette_material.set_shader_parameter("look", true)
		m.palette_material.set_shader_parameter("gain", 1.0)
		m.palette_material.set_shader_parameter("blast", 0.0)
		var w: Array = Game.WASH.get(game.level.id, [255, 255, 255, 0])
		var amount: float = w[3]
		var wr: float = w[0]
		var wg: float = w[1]
		var wb: float = w[2]
		var tint := Vector3(wr, wg, wb) / 255.0
		m.palette_material.set_shader_parameter(
			"wash", Vector3.ONE * (1.0 - amount) + tint * amount
		)


## The strip at the foot of the picture (the status bar's rows): the filter,
## the buttons for the device in use, and where the last picture went.
func draw(m: MainState) -> void:
	if not on or bare:
		return
	var c := m.canvas
	c.fill_rect(0, View.VIEW, View.WIDTH, View.HEIGHT - View.VIEW, STRIP)
	c.fill_rect(0, View.VIEW, View.WIDTH, 1, Canvas.EDGE)
	HUD.text(c, "PHOTO MODE", 8, View.VIEW + 5, "body", HUD.AMBER)
	HUD.text(
		c, "FILTER  " + FILTERS[filter], 312, View.VIEW + 5, "body", HUD.INK, false, true, true
	)
	var lines := guide(m.input_device)
	HUD.text(c, lines[0], 160, View.VIEW + 19, "mini", HUD.DIM, true, false)
	var last := lines[1]
	if note_left > 0.0:
		last = note
	HUD.text(c, last, 160, View.VIEW + 30, "mini", HUD.INK, true, false)


static func guide(device: String) -> Array[String]:
	if device == "touch":
		return [
			"STICK FLIES  DRAG LOOKS  JUMP / DUCK UP AND DOWN",
			"NEXT FILTER  FIRE SAVES  USE HIDES  MENU BACK"
		]
	if device == "pad":
		return [
			"STICKS FLY AND LOOK  A / B UP AND DOWN  CLICK FAST",
			"X FILTER  RT SAVES  Y HIDES  START BACK"
		]
	return [
		"WASD FLY  MOUSE LOOKS  J / Z UP AND DOWN  SHIFT FAST",
		"R FILTER  ENTER SAVES  H HIDES  ESC BACK"
	]


## Save a picture of the view: drawn again off screen at SCALE times its
## size through the display shader (filter and all), or headless from the
## software canvas.
func save(m: MainState) -> void:
	if not on:
		return
	if m.canvas.gpu and m.gpu_look:
		_save_drawn(m)
		return
	var shot := Image.create_from_data(
		View.WIDTH, View.HEIGHT, false, Image.FORMAT_RGB8, m.palettised(m.canvas.pixels)
	)
	_write(m, shot.get_region(Rect2i(0, 0, View.WIDTH, View.VIEW)))


func _save_drawn(m: MainState) -> void:
	var k := maxi(1, SCALE)
	var port := SubViewport.new()
	port.size = Vector2i(View.WIDTH * k, View.VIEW * k)
	port.disable_3d = true
	port.transparent_bg = false
	port.render_target_update_mode = SubViewport.UPDATE_ONCE
	var shown := TextureRect.new()
	shown.texture = m.frame_texture
	shown.material = m.palette_material
	shown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shown.stretch_mode = TextureRect.STRETCH_SCALE
	shown.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shown.size = Vector2(View.WIDTH * k, View.HEIGHT * k)
	port.add_child(shown)
	m.add_child(port)
	await RenderingServer.frame_post_draw
	var image := port.get_texture().get_image()
	port.queue_free()
	if image == null or image.is_empty():
		_said("COULD NOT TAKE THE PICTURE.")
		return
	image.convert(Image.FORMAT_RGB8)
	_write(m, image, false)


## Write `image` (scaled up SCALE times first when `grow`) where pictures go.
func _write(m: MainState, image: Image, grow := true) -> void:
	if grow and SCALE > 1:
		image.resize(
			image.get_width() * SCALE, image.get_height() * SCALE, Image.INTERPOLATE_NEAREST
		)
	var now := Time.get_datetime_dict_from_system()
	var level_id := game.level.id if game != null else "county"
	var file := (
		"CrazyLegs-%s-%04d%02d%02d-%02d%02d%02d.png"
		% [
			level_id,
			now["year"],
			now["month"],
			now["day"],
			now["hour"],
			now["minute"],
			now["second"]
		]
	)
	if m.web and out_dir == "":
		JavaScriptBridge.download_buffer(image.save_png_to_buffer(), file, "image/png")
		_said("PICTURE DOWNLOADED: " + file)
		return
	var folder := where(m.mobile)
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join(file)
	if image.save_png(path) != OK and out_dir == "" and not folder.begins_with("user://"):
		folder = "user://photos"
		DirAccess.make_dir_recursive_absolute(folder)
		path = folder.path_join(file)
		if image.save_png(path) != OK:
			_said("COULD NOT SAVE THE PICTURE.")
			return
	last_saved = ProjectSettings.globalize_path(path)
	m.sound.play("menu_accept")
	_said(
		(
			"SAVED  "
			+ ("PICTURES" if not folder.begins_with("user://") else "USER FOLDER")
			+ "  "
			+ file
		)
	)


## The folder pictures go to: the checks' own, else Pictures/Crazy Legs
## Mundell Rampage on a computer, else the game's user folder.
func where(phone: bool) -> String:
	if out_dir != "":
		return out_dir
	if not phone:
		var pictures := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
		if pictures != "" and DirAccess.dir_exists_absolute(pictures):
			return pictures.path_join("Crazy Legs Mundell Rampage")
	return "user://photos"


func _said(text: String) -> void:
	note = text
	note_left = NOTE_TIME
