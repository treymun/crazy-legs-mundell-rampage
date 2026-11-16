## Mundell's boot in first person, for the kick and the stomp
## (features/brawl_looks.gd), into assets/art.
##
##   godot --headless --path godot --script res://tools/art/build_boot_views.gd \
##       [-- no-render] [out=<dir>]
##
## Blender (scripts/blender/boot_views.py) renders each pose of his leg over
## the whole 320x200 view, four times over, into _preview/boot_raw; this
## crops each to its edges, shrinks it with the gun cels' grade (paint.gd
## photo_shrink, then the palette) to fx_boot_<pose>.png and writes where its
## top left corner sits on the 320x200 view to boot_views.json. BLENDER_PATH
## overrides where Blender is; no-render reuses the last renders. Then run
## tools/pack_assets.gd.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")
const Actors := preload("res://tools/art/build_enemy_actors.gd")
const SUPER := 4


func _init() -> void:
	var render := true
	var out := Paint.repo("assets/art")
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text == "no-render":
			render = false
		elif text.begins_with("out="):
			out = text.substr(4)
	var raw := Paint.repo("_preview/boot_raw")
	DirAccess.make_dir_recursive_absolute(raw)
	if render:
		var code := OS.execute(
			Actors.blender(),
			[
				"-b",
				"--python-exit-code",
				"1",
				"-P",
				Paint.repo("scripts/blender/boot_views.py"),
				"--",
				raw,
				"all"
			]
		)
		if code != 0:
			push_error("Blender failed (exit %d); set BLENDER_PATH if it is elsewhere" % code)
			quit(1)
			return
	var poses = JSON.parse_string(FileAccess.get_file_as_string(raw.path_join("poses.json")))
	if not poses is Array:
		push_error("no %s/poses.json: render first" % raw)
		quit(1)
		return
	var places := {}
	for pose: String in poses:
		var image := Paint.Sheet.load_png(raw.path_join(pose + ".png"))
		var box := image.bbox(127)
		if box.size.x <= 0 or box.size.y <= 0:
			push_error("%s rendered empty" % pose)
			continue
		# Whole view pixels: the box grown to the next multiple of SUPER.
		var x0 := box.position.x / SUPER * SUPER
		var y0 := box.position.y / SUPER * SUPER
		var x1 := mini(image.w, ceili((box.position.x + box.size.x) / float(SUPER)) * SUPER)
		var y1 := mini(image.h, ceili((box.position.y + box.size.y) / float(SUPER)) * SUPER)
		var cut := image.cropped(Rect2i(x0, y0, x1 - x0, y1 - y0))
		var target := Vector2i(cut.w / SUPER, cut.h / SUPER)
		var seed := 0
		for c in pose.to_utf8_buffer():
			seed += c
		var cel := Paint.digitize(Paint.photo_shrink(cut, target, seed))
		cel.save(out.path_join("fx_boot_%s.png" % pose))
		places[pose] = [x0 / SUPER, y0 / SUPER]
	var file := FileAccess.open(out.path_join("boot_views.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(places, "\t", true))
	file.close()
	print("boot views: %d written to %s" % [places.size(), out])
	quit()
