## Render the reference camera shots with the Godot renderer and save PNGs.
##
##   Godot --headless --path <project> --script res://tools/shot.gd
##
## Writes tools/frames/gd_<tag>.png next to the Python frames so the two sets
## can be diffed.
extends SceneTree


func _initialize() -> void:
	var assets := Assets.new()
	var raw := FileAccess.get_file_as_string("res://tools/frames/shots.json")
	var shots = JSON.parse_string(raw)
	if not (shots is Dictionary):
		push_error("cannot read shots.json")
		quit(1)
		return
	var out_dir := ProjectSettings.globalize_path("res://tools/frames")
	for tag in shots:
		var shot: Dictionary = shots[tag]
		var level := LevelData.load_level(String(shot["level"]), assets)
		if level == null:
			quit(1)
			return
		var renderer := Renderer.new(assets, level)
		var player := {
			"x": float(shot["x"]),
			"y": float(shot["y"]),
			"eye": float(shot["eye"]),
			"view_angle": float(shot["angle"]),
			"pitch": float(shot["pitch"]),
			"bob": float(shot["horizon"]),
			"sway": 0.0,
		}
		var started := Time.get_ticks_usec()
		var frame := renderer.render(player, [], null, 0.0, [], [])
		var elapsed := (Time.get_ticks_usec() - started) / 1000.0
		var nonzero := 0
		for i in range(0, frame.size(), 3):
			if frame[i] != 0 or frame[i + 1] != 0 or frame[i + 2] != 0:
				nonzero += 1
		print("  pixels set: %d / %d" % [nonzero, Renderer.WIDTH * Renderer.HEIGHT])
		var image := Image.create_from_data(
			Renderer.WIDTH, Renderer.HEIGHT, false, Image.FORMAT_RGB8, frame
		)
		var view := image.get_region(Rect2i(0, 0, Renderer.WIDTH, Renderer.VIEW))
		var path := "%s/gd_%s.png" % [out_dir, tag]
		view.save_png(path)
		print("shot %s  %.2f ms  -> %s" % [tag, elapsed, path])
	quit()
