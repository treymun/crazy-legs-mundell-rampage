## Render the same full gameplay frames as tools/py_full.py, so the port can be
## compared against the reference including weapon, HUD and palette grading.
##
##   Godot --headless --path <project> --script res://tools/shot_full.gd [-- tag ...]
##
## Writes tools/frames/gd_full_<tag>.png next to the Python frames.
extends SceneTree


func _init() -> void:
	_run.call_deferred()


func _apply_palette(canvas: Canvas, lut: PackedByteArray) -> void:
	var pix := canvas.pixels
	for i in range(0, pix.size(), 3):
		var r5 := (pix[i] * 31 + 127) / 255
		var g5 := (pix[i + 1] * 31 + 127) / 255
		var b5 := (pix[i + 2] * 31 + 127) / 255
		var code: int = (r5 << 10) | (g5 << 5) | b5
		var at := code * 3
		pix[i] = lut[at]
		pix[i + 1] = lut[at + 1]
		pix[i + 2] = lut[at + 2]
	canvas.pixels = pix


func _run() -> void:
	var assets := Assets.new()
	var hud := HUD.new(assets)
	var sound := Sound.new(assets)
	root.add_child(sound)
	var raw := FileAccess.get_file_as_string("res://tools/frames/full_shots.json")
	var shots = JSON.parse_string(raw)
	if not (shots is Dictionary):
		push_error("cannot read full_shots.json")
		quit(1)
		return
	var wanted := []
	for arg in OS.get_cmdline_user_args():
		wanted.append(String(arg))
	var out_dir := ProjectSettings.globalize_path("res://tools/frames")
	var options := SessionStore.settings("")
	for tag in shots:
		if not wanted.is_empty() and not wanted.has(String(tag)):
			continue
		var shot: Dictionary = shots[tag]
		var game := Game.new(assets, hud, sound, String(shot["level"]))
		game.configure(options)
		var p := game.player
		p.x = float(shot["x"])
		p.y = float(shot["y"])
		p.angle = float(shot["angle"])
		p.eye = .95 + game.world.elevation(p.x, p.y)
		p.pitch = 0.0
		p.drunk = 0.0
		p.sway = 0.0
		p.health = int(shot["health"])
		game.clock = float(shot["clock"])
		game.hurt_flash = 0.0
		game.blast_flash = 0.0
		game.message_until = 0.0
		game.district_until = 0.0
		game.map = false
		game.armory.select(int(shot["weapon"]), game)
		game.armory.flash = 0.0
		game.armory.recoil = 0.0
		game.armory.reload = 0.0
		game.armory.cooldown = 0.0
		game.armory.shot_age = 0.0
		for _i in int(shot.get("shots", 0)):
			game.armory.fire(game, false)
			game.armory.flash = 0.0
		var canvas := Canvas.new()
		canvas.clear(0, 0, 0)
		game.draw(canvas, 1, false)
		var raw_path := "%s/gdraw_%s.png" % [out_dir, tag]
		var raw_image := Image.create_from_data(320, 200, false, Image.FORMAT_RGB8, canvas.pixels)
		raw_image.save_png(raw_path)
		_apply_palette(canvas, assets.palette)
		var path := "%s/gd_full_%s.png" % [out_dir, tag]
		var image := Image.create_from_data(320, 200, false, Image.FORMAT_RGB8, canvas.pixels)
		image.save_png(path)
		print("shot ", tag, " -> ", path)
	quit()
