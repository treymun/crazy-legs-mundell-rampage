## Render Hickston's props in Blender and shrink them into assets/art.
##
##   godot --headless --path godot --script res://tools/art/build_town_props.gd \
##       [-- names=outhouse,still] [no-render] [out=<dir>]
##
## Blender (scripts/blender/town_props.py, with props_more.py and Gator Bayou's
## props_bayou.py exec'd into it) models each prop from plain shapes
## and writes it four times oversized, with a margin, into _preview/props/raw;
## this crops each to its edges, shrinks it to game size with the enemies'
## grade (paint.gd photo_shrink: a hard alpha edge, a dark rim, a worn
## photograph's colour) and commits it to the palette as town_<name>.png. Its
## size in map units goes in assets/art/town_props.json, which the level
## builder reads (level_builder.gd town()). BLENDER_PATH overrides where
## Blender is; no-render reuses the last renders. Then run tools/pack_assets.gd.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")
const Actors := preload("res://tools/art/build_enemy_actors.gd")
const SUPERSAMPLE := 4
## The Blender scripts that model props, each run in turn into the same folder
## (each renders only the names it knows): the town's (with props_more.py) and
## the firing range's.
const SCRIPTS := ["town_props.py", "props_range.py"]


func _init() -> void:
	var names := "all"
	var render := true
	var out := Paint.repo("assets/art")
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text.begins_with("names="):
			names = text.substr(6)
		elif text == "no-render":
			render = false
		elif text.begins_with("out="):
			out = text.substr(4)
	var raw := Paint.repo("_preview/props/raw")
	DirAccess.make_dir_recursive_absolute(raw)
	DirAccess.make_dir_recursive_absolute(out)
	if render:
		for script: String in SCRIPTS:
			var code := OS.execute(
				Actors.blender(),
				[
					"-b",
					"-P",
					Paint.repo("scripts/blender/" + script),
					"--",
					raw,
					names,
					str(SUPERSAMPLE)
				]
			)
			if code != 0:
				push_error("Blender failed (exit %d); set BLENDER_PATH if it is elsewhere" % code)
				quit(1)
				return
	var meta = JSON.parse_string(FileAccess.get_file_as_string(raw.path_join("meta.json")))
	if not meta is Dictionary:
		push_error("no %s/meta.json: render first" % raw)
		quit(1)
		return
	var sizes_path := out.path_join("town_props.json")
	var sizes := {}
	if FileAccess.file_exists(sizes_path):
		sizes = JSON.parse_string(FileAccess.get_file_as_string(sizes_path))
	var count := 0
	for name: String in meta:
		if names != "all" and not (name in names.split(",")):
			continue
		var image := Paint.Sheet.load_png(raw.path_join(name + ".png"))
		var box := image.bbox(127)
		if box.size.x <= 0 or box.size.y <= 0:
			push_error("%s rendered empty" % name)
			continue
		var cut := image.cropped(box)
		var ppu := float(meta[name][2]) * SUPERSAMPLE
		var target := Vector2i(
			maxi(1, roundi(cut.w / float(SUPERSAMPLE))), maxi(1, roundi(cut.h / float(SUPERSAMPLE)))
		)
		var seed := 0
		for c in name.to_utf8_buffer():
			seed += c
		var sprite := Paint.digitize(Paint.photo_shrink(cut, target, seed))
		sprite.save(out.path_join("town_%s.png" % name))
		sizes[name] = [snappedf(cut.w / ppu, .01), snappedf(cut.h / ppu, .01)]
		count += 1
	var file := FileAccess.open(sizes_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(sizes, "\t", true))
	file.close()
	print("town props: %d written to %s" % [count, out])
	quit()
