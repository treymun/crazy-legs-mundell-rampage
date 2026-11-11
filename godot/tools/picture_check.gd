## Picture regression check: renders a fixed set of viewpoints through the
## whole game frame (view, weapon, HUD; the software path, as without a
## window) and compares each with its reference image in tools/pictures/.
##
##   Godot --headless --path <project> --script res://tools/picture_check.gd
##   ... -- update          rewrite the reference images from this build
##   ... -- out=<dir>       also save every render and a diff image there
##   ... -- annotate        also report each difference as a GitHub annotation
##
## The viewpoints are tools/picture_views.json: {"tag", "level", "x", "y",
## "angle"} and optionally "pitch", "drunk", "weapon" (drawn and lit),
## "detail" (1 = LOW), "ticks" and "fire" (that many 60 Hz steps first,
## holding the trigger). A render may differ from its reference in a few
## pixels (floating point is not quite the same on every machine); more than
## LIMIT pixels fails the check. Change pictures on purpose, then run "update"
## and commit the new references with the change.
extends SceneTree

const VIEWS := "res://tools/picture_views.json"
const PICTURES := "res://tools/pictures"
const LIMIT := 64


func _init() -> void:
	_run.call_deferred()


func _render(shot: Dictionary, assets: Assets, hud: HUD, sound: Sound) -> Image:
	var level := String(shot["level"])
	# A fresh game per viewpoint: what one shot fires or ticks must not leak
	# into the next.
	var game := Game.new(assets, hud, sound, level)
	game.configure(SessionStore.settings(""))
	var p := game.player
	p.x = float(shot["x"])
	p.y = float(shot["y"])
	p.angle = float(shot["angle"])
	p.eye = .95 + game.world.elevation(p.x, p.y)
	p.pitch = float(shot.get("pitch", 0.0))
	p.drunk = float(shot.get("drunk", 0.0))
	p.sway = 0.0
	var armed := bool(shot.get("weapon", false))
	game.armory.holstered = not armed
	game.armory.lower = 0.0 if armed else 1.0
	if shot.has("detail"):
		game.renderer.set_detail(int(shot["detail"]))
	if shot.has("ticks"):
		var held := Game.Controls.new()
		held.fire = bool(shot.get("fire", false))
		for i in int(shot["ticks"]):
			game.tick(1.0 / 60.0, held)
	game.message_until = 0.0
	game.district_until = 0.0
	var canvas := Canvas.new()
	canvas.clear(0, 0, 0)
	game.draw(canvas, 1, false)
	return Image.create_from_data(320, 200, false, Image.FORMAT_RGB8, canvas.pixels)


func _run() -> void:
	var update := false
	var annotate := false
	var out_dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg == "update":
			update = true
		elif arg == "annotate":
			annotate = true
		elif String(arg).begins_with("out="):
			out_dir = String(arg).substr(4)
	var shots = JSON.parse_string(FileAccess.get_file_as_string(VIEWS))
	if not (shots is Array):
		push_error("cannot read " + VIEWS)
		quit(1)
		return
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
	var assets := Assets.new()
	var hud := HUD.new(assets)
	var sound := Sound.new(assets)
	root.add_child(sound)
	var failed: Array[String] = []
	var worst := 0
	for shot: Dictionary in shots:
		var tag := String(shot["tag"])
		var image := _render(shot, assets, hud, sound)
		var path := "%s/%s.png" % [PICTURES, tag]
		if out_dir != "":
			image.save_png("%s/%s.png" % [out_dir, tag])
		if update:
			image.save_png(ProjectSettings.globalize_path(path))
			continue
		if not FileAccess.file_exists(path):
			print("%-34s NO REFERENCE (run with -- update)" % tag)
			failed.append(tag)
			continue
		var want := Image.load_from_file(ProjectSettings.globalize_path(path))
		want.convert(Image.FORMAT_RGB8)
		var a := image.get_data()
		var b := want.get_data()
		var off := 0
		var diff := Image.create_empty(320, 200, false, Image.FORMAT_RGB8)
		for i in 320 * 200:
			var o := i * 3
			if a[o] != b[o] or a[o + 1] != b[o + 1] or a[o + 2] != b[o + 2]:
				off += 1
				diff.set_pixel(i % 320, i / 320, Color(1, .24, .24))
		worst = maxi(worst, off)
		if annotate and off > 0:
			print("::warning title=picture %s::%d pixels differ (limit %d)" % [tag, off, LIMIT])
		if off > LIMIT:
			failed.append(tag)
			print("%-34s %5d pixels differ  FAIL" % [tag, off])
			if out_dir != "":
				diff.save_png("%s/%s_diff.png" % [out_dir, tag])
		elif off > 0:
			print("%-34s %5d pixels differ" % [tag, off])
	Renderer.stop_crew()
	if update:
		print("PICTURES UPDATED: ", shots.size())
		quit()
		return
	if failed.is_empty():
		print("PICTURES OK: %d views, at most %d pixels apart" % [shots.size(), worst])
		quit()
	else:
		print("PICTURES CHANGED: ", ", ".join(failed))
		quit(1)
