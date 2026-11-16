## The pictures of a player who is down (assets/art/player_down_*.png), for the
## flat picture of a partner, opponent or County Run partner lying out
## (ModeScreens.sprites; the 3D view draws the model itself, which these are
## taken from): Mundell's own model (scripts/blender/actors_mundell.py) in its
## down frame, as the game's 3D view draws it, seen across (`_side`, the
## head to the picture's left; flipped for the other way), from the feet
## (`_feet`) and from the head (`_head`). Needs a window:
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/art/build_player_down.gd [-- out=<dir>]
##
## Each is the view drawn twice, with and without the body (a matte from the
## difference, so nothing of the floor comes along), cut to the body, brought
## to the old cels' scale (CEL_HEIGHT rows for what DOWN_HEIGHT stands) with a
## dark rim as the old cels have. Run it again after the model changes, then
## pack_assets.
extends SceneTree

## Where the camera stands, turned from the way the body faced: the model
## falls onto its side of the way it faced, its head to its right.
const VIEWS := {"_side": 0.0, "_head": PI * .5, "_feet": -PI * .5}
## Where the camera stands from the body, and how far it looks down.
const REACH := 3.0
const PITCH := -30.0
## The view's pixels to the picture's (the view at HD, REACH away: about
## ModeScreens.DOWN_ROWS rows a map unit after it, which sizes them so).
const SCALE := .8
## A pixel is the body's when the two draws differ by more than this.
const MATTE := .035

var main: Control
var out := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	out = ProjectSettings.globalize_path("res://").path_join("../assets/art")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			out = arg.substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.touring = true
	var g: Game = main.make_game("hub")
	main.game = g
	main.state = "play"
	var options := SessionStore.defaults()
	options["detail"] = 3
	options["hud"] = 0
	options["shadows"] = 0
	g.configure(options)
	main.options.merge(options, true)
	main.apply_options()
	Modes.setup(g, Modes.COOP, 2)
	for i in 2:
		g.tick(1.0 / 60.0, Game.Controls.new())
	g.cheats.god = true
	g.spawn_grace = 99.0
	for e: Enemy in g.enemies:
		e.dormant = true
	var a: Player = g.players[0]
	var b: Player = g.players[1]
	var spot := _open_spot(g)
	b.health = 0
	b.down_at = g.clock
	for name: String in VIEWS:
		var turn: float = VIEWS[name]
		var lie := 0.4
		Modes.place(g, b, spot.x, spot.y, lie)
		b.health = 0
		var from := lie + turn
		Modes.place(g, a, spot.x + cos(from) * REACH, spot.y + sin(from) * REACH, from + PI)
		a.pitch = PITCH
		# Down long enough for the model to lie still (ModeBodies.fell_at).
		for k in 3:
			await _draw(g)
		g.clock += Enemy.DEATH_TIME + 1.0
		var with_body := await _draw(g)
		b.away = true
		var without := await _draw(g)
		b.away = false
		var cel := _cut(with_body, without, name)
		if cel == null:
			push_error("no body seen for " + name)
			continue
		cel.save_png(out.path_join("player_down%s.png" % name))
		print("player_down%s.png %dx%d" % [name, cel.get_width(), cel.get_height()])
	main.queue_free()
	await process_frame
	quit()


## Flat open ground near the range's middle with nothing about.
func _open_spot(g: Game) -> Vector2:
	var s: Array = g.level.spawn
	var sx: float = s[0]
	var sy: float = s[1]
	for reach: float in [3.0, 4.0, 5.0, 6.0]:
		for k in 12:
			var ang := k * TAU / 12.0
			var at := Vector2(sx + cos(ang) * reach, sy + sin(ang) * reach)
			var clear := true
			for d: Vector2 in [
				Vector2.ZERO, Vector2(2.4, 0), Vector2(-2.4, 0), Vector2(0, 2.4), Vector2(0, -2.4)
			]:
				if g.world.blocked(at.x + d.x, at.y + d.y, .4):
					clear = false
			if clear:
				return at
	return Vector2(sx, sy)


## The 3D view's own picture this frame (before the screen's colour grade).
func _draw(g: Game) -> Image:
	g.message_until = 0.0
	main.render()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return main.world_view.viewport.get_texture().get_image()


## The body from the difference of the two draws, cut to its box, scaled to
## the cels' rows and given the old cels' dark rim.
func _cut(with_body: Image, without: Image, name: String) -> Image:
	with_body.convert(Image.FORMAT_RGBA8)
	without.convert(Image.FORMAT_RGBA8)
	var w := with_body.get_width()
	var h := with_body.get_height()
	var mask := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	var box := Rect2i()
	var seen := false
	for y in h:
		for x in w:
			var c1 := with_body.get_pixel(x, y)
			var c0 := without.get_pixel(x, y)
			var d := absf(c1.r - c0.r) + absf(c1.g - c0.g) + absf(c1.b - c0.b)
			if d > MATTE:
				mask.set_pixel(x, y, Color(c1.r, c1.g, c1.b, 1.0))
				if not seen:
					box = Rect2i(x, y, 1, 1)
					seen = true
				else:
					box = box.expand(Vector2i(x, y)).expand(Vector2i(x + 1, y + 1))
	if not seen:
		return null
	if box.position.x <= 0 or box.position.y <= 0 or box.end.x >= w or box.end.y >= h:
		push_warning("%s: the body runs off the view %s" % [name, box])
	mask.save_png(OS.get_cache_dir().path_join("player_down_matte%s.png" % name))
	var body := mask.get_region(box)
	var scale := SCALE
	var size := Vector2i(
		maxi(8, roundi(body.get_width() * scale)), maxi(8, roundi(body.get_height() * scale))
	)
	body.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
	# Hard alpha, and a one-pixel dark rim round the body as the cels have.
	var rimmed := Image.create_empty(size.x + 2, size.y + 2, false, Image.FORMAT_RGBA8)
	for y in size.y:
		for x in size.x:
			var c := body.get_pixel(x, y)
			if c.a >= .5:
				rimmed.set_pixel(x + 1, y + 1, Color(c.r, c.g, c.b, 1.0))
	var rim := Color8(28, 18, 14)
	var edged := rimmed.duplicate() as Image
	for y in rimmed.get_height():
		for x in rimmed.get_width():
			if rimmed.get_pixel(x, y).a > 0.0:
				continue
			for n: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var px := x + n.x
				var py := y + n.y
				if px < 0 or py < 0 or px >= rimmed.get_width() or py >= rimmed.get_height():
					continue
				if rimmed.get_pixel(px, py).a > 0.0:
					edged.set_pixel(x, y, rim)
					break
	return edged
