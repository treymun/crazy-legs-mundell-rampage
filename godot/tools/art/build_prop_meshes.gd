## Export the props as meshes for the 3D view.
##
##   godot --headless --path godot --script res://tools/art/build_prop_meshes.gd \
##       [-- names=outhouse,tractor] [no-render]
##
## Blender (scripts/blender/export_meshes.py) models each prop with the same
## code that renders its sprite, bakes its materials and the dusk stage's
## light into one texture and writes a glTF; this copies the meshes to
## godot/assets3d/props/<name>.glb, commits each texture to the palette as
## assets/art/mesh_<name>.png (packed with the rest of the art) and notes the
## sizes in godot/assets3d/props/meshes.json, which the 3D view reads
## (view3d/prop_models.gd): [width, depth, height, texture size, the
## height its picture town_<name> (a station's town_<name>_off) was drawn
## at, from assets/art/town_props.json; a sprite shown taller or shorter
## stands the model scaled to match]. Then run tools/pack_assets.gd and
## --import. A quest station (quest_props.py) is one model with both its
## looks (export_meshes.py).
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")
const Actors := preload("res://tools/art/build_enemy_actors.gd")
## The libraries that model props, each run in turn into the same folder.
const LIBRARIES: Array[String] = [
	"town_props.py", "props_range.py", "quest_props.py", "painted_boards.py"
]
const MESHES := "res://assets3d/props"


func _init() -> void:
	var names := "all"
	var render := true
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("names="):
			names = arg.substr(6)
		elif arg == "no-render":
			render = false
	var raw := Paint.repo("_preview/props/mesh_raw")
	DirAccess.make_dir_recursive_absolute(raw)
	if render:
		for library: String in LIBRARIES:
			var code := OS.execute(
				Actors.blender(),
				[
					"-b",
					"-P",
					Paint.repo("scripts/blender/export_meshes.py"),
					"--",
					raw,
					names,
					library
				]
			)
			if code != 0:
				push_error("Blender failed (exit %d); set BLENDER_PATH if it is elsewhere" % code)
				quit(1)
				return
	var meta: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(raw.path_join("meshes.json"))
	)
	if not meta is Dictionary:
		push_error("no %s/meshes.json: export first" % raw)
		quit(1)
		return
	var out_dir := ProjectSettings.globalize_path(MESHES)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var sizes_path := out_dir.path_join("meshes.json")
	var sizes: Dictionary = {}
	if FileAccess.file_exists(sizes_path):
		sizes = JSON.parse_string(FileAccess.get_file_as_string(sizes_path))
	var art := Paint.repo("assets/art")
	var count := 0
	for name: String in meta:
		if names != "all" and not (name in names.split(",")):
			continue
		var glb := raw.path_join(name + ".glb")
		if not FileAccess.file_exists(glb):
			continue
		DirAccess.copy_absolute(glb, out_dir.path_join(name + ".glb"))
		var baked := Paint.Sheet.load_png(raw.path_join(name + ".png"))
		var seed := 0
		for ch in name.to_utf8_buffer():
			seed += ch
		Paint.digitize(Paint.photo_grade(baked, seed)).save(art.path_join("mesh_%s.png" % name))
		sizes[name] = meta[name]
		count += 1
	# Every model's picture height (the old pictures' sizes do not move).
	var pictures: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(art.path_join("town_props.json"))
	)
	if pictures is Dictionary:
		for name: String in sizes:
			var dims: Array = sizes[name]
			var seen: Variant = pictures.get(name, pictures.get(name + "_off"))
			if seen is Array:
				var height: float = seen[1]
				sizes[name] = dims.slice(0, 4) + [height]
	var file := FileAccess.open(sizes_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(sizes, "\t", true))
	file.close()
	print("prop meshes: %d written to %s" % [count, out_dir])
	quit()
