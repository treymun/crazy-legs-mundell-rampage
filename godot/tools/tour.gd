## Render a list of viewpoints through the full game frame, for looking over a
## level without playing it.
##
##   Godot --headless --path <project> --script res://tools/tour.gd -- <shots.json> <out dir>
##
## shots.json is a list of {"tag", "level", "x", "y", "angle"}; each becomes
## <out dir>/<tag>.png (320x200, palette applied, weapon holstered).
extends SceneTree


func _init() -> void:
	_run.call_deferred()


func _apply_palette(canvas: Canvas, lut: PackedByteArray) -> void:
	var pix := canvas.pixels
	for i in range(0, pix.size(), 3):
		var r5 := (pix[i] * 31 + 127) / 255
		var g5 := (pix[i + 1] * 31 + 127) / 255
		var b5 := (pix[i + 2] * 31 + 127) / 255
		var at := ((r5 << 10) | (g5 << 5) | b5) * 3
		pix[i] = lut[at]
		pix[i + 1] = lut[at + 1]
		pix[i + 2] = lut[at + 2]
	canvas.pixels = pix


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: tour.gd -- <shots.json> <out dir>")
		quit(1)
		return
	var shots = JSON.parse_string(FileAccess.get_file_as_string(String(args[0])))
	if not (shots is Array):
		push_error("cannot read the shot list")
		quit(1)
		return
	var out_dir := String(args[1])
	var assets := Assets.new()
	var hud := HUD.new(assets)
	var sound := Sound.new(assets)
	root.add_child(sound)
	var options := SessionStore.settings("")
	var games := {}
	for shot: Dictionary in shots:
		var level := String(shot["level"])
		if not games.has(level):
			var fresh := Game.new(assets, hud, sound, level)
			fresh.configure(options)
			games[level] = fresh
		var game: Game = games[level]
		var p := game.player
		p.x = float(shot["x"])
		p.y = float(shot["y"])
		p.angle = float(shot["angle"])
		p.eye = .95 + game.world.stand(p)
		p.pitch = 0.0
		p.drunk = 0.0
		p.sway = 0.0
		game.message_until = 0.0
		game.district_until = 0.0
		game.armory.holstered = true
		game.armory.lower = 1.0
		var canvas := Canvas.new()
		canvas.clear(0, 0, 0)
		game.draw(canvas, 1, false)
		_apply_palette(canvas, assets.palette)
		var image := Image.create_from_data(320, 200, false, Image.FORMAT_RGB8, canvas.pixels)
		image.save_png("%s/%s.png" % [out_dir, String(shot["tag"])])
	print("tour: ", shots.size(), " frames in ", out_dir)
	quit()
