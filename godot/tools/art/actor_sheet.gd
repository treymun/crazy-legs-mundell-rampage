## A model sheet of one actor: a row a frame, each row the model in the
## game's own actor shader (its baked look, ActorModels.material) seen from
## the front three-quarters, the side, the front, the back three-quarters and
## the back up close, then the same three-quarter view at game size (drawn
## as small as the 320x200 view shows it a few cells off, blown up with hard
## pixels). Needs a window.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/art/actor_sheet.gd -- kind=hound out=<file.png> \
##       [frames=0,w1,sit] [ppu=160] [game=30]
##
## `game` is the game-size column's pixels a metre (about BLUE three cells
## off in the 320x200 view). The hound's before/after sheets in
## docs/godot3d/features/blue/ come from this.
extends SceneTree

const BACKDROP := Color8(74, 66, 70)
const GAP := 6
const TURNS: Array[float] = [-35.0, -90.0, 0.0, -145.0, 180.0]
const PITCH := 10.0

var ppu := 160.0
var game_ppu := 30.0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var kind := ""
	var out := ""
	var frames: PackedStringArray = []
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("kind="):
			kind = arg.substr(5)
		elif arg.begins_with("out="):
			out = arg.substr(4)
		elif arg.begins_with("frames="):
			frames = arg.substr(7).split(",")
		elif arg.begins_with("ppu="):
			ppu = float(arg.substr(4))
		elif arg.begins_with("game="):
			game_ppu = float(arg.substr(5))
	if kind == "" or out == "":
		push_error("actor_sheet.gd -- kind=<kind> out=<file.png> [frames=a,b] [ppu=160]")
		quit(1)
		return
	var assets := Assets.new()
	var models := ActorModels.new(assets)
	if not models.kinds.has(kind):
		push_error("%s: no model" % kind)
		quit(1)
		return
	var info: Dictionary = models.kinds[kind]
	if frames.is_empty():
		var known: Dictionary = info["frames"]
		var named: Array = known.keys()
		named.sort_custom(func(a: String, b: String) -> bool: return known[a] < known[b])
		frames = PackedStringArray(named)
	var canvas: Array = info.get("canvas", [1.0, 1.0])
	var reach: float = canvas[0] * 1.15
	var tall: float = canvas[1] * 1.1
	var port := SubViewport.new()
	port.own_world_3d = true
	port.transparent_bg = false
	port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(port)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKDROP
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	port.add_child(world_env)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	port.add_child(camera)
	var p := deg_to_rad(PITCH)
	camera.size = tall
	camera.transform = Transform3D(
		Basis(Vector3.RIGHT, -p), Vector3(0, tall * .45, 0) + Vector3(0, sin(p), cos(p)) * 3.0
	)
	var view := models.scene(kind).instantiate() as ActorView
	port.add_child(view)
	view.setup(models)
	var player: AnimationPlayer = null
	for child in view.find_children("*", "AnimationPlayer", true, false):
		player = child as AnimationPlayer
	var cell := Vector2i(ceili(reach * ppu), ceili(tall * ppu))
	var small := Vector2i(ceili(reach * game_ppu), ceili(tall * game_ppu))
	var rows: Array[Image] = []
	for frame in frames:
		var at: Variant = models.key_time(kind, frame)
		if at == null:
			push_error("%s: no frame %s" % [kind, frame])
			continue
		var seek_to: float = at
		player.seek(seek_to, true)
		var shots: Array[Image] = []
		port.size = cell
		for turn in TURNS:
			view.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(turn)), Vector3.ZERO)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			shots.append(port.get_texture().get_image())
		# Game size: the three-quarter view drawn small, blown up hard.
		port.size = small
		view.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(TURNS[0])), Vector3.ZERO)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var tiny := port.get_texture().get_image()
		tiny.resize(small.x * 3, small.y * 3, Image.INTERPOLATE_NEAREST)
		shots.append(tiny)
		var row_h := cell.y
		var row_w := GAP
		for shot in shots:
			row_h = maxi(row_h, shot.get_height())
			row_w += shot.get_width() + GAP
		var row := Image.create(row_w, row_h, false, Image.FORMAT_RGBA8)
		row.fill(BACKDROP)
		var x := GAP
		for shot in shots:
			shot.convert(Image.FORMAT_RGBA8)
			row.blit_rect(
				shot, Rect2i(Vector2i.ZERO, shot.get_size()), Vector2i(x, row_h - shot.get_height())
			)
			x += shot.get_width() + GAP
		rows.append(row)
		print("  %s" % frame)
	view.queue_free()
	var wide := 0
	var high := 0
	for row in rows:
		wide = maxi(wide, row.get_width())
		high += row.get_height() + GAP
	var sheet := Image.create(maxi(1, wide), maxi(1, high), false, Image.FORMAT_RGBA8)
	sheet.fill(Color8(30, 28, 30))
	var y := 0
	for row in rows:
		sheet.blit_rect(row, Rect2i(Vector2i.ZERO, row.get_size()), Vector2i(0, y))
		y += row.get_height() + GAP
	sheet.save_png(out)
	print("ACTOR SHEET %s: %d rows -> %s" % [kind, rows.size(), out])
	quit()
