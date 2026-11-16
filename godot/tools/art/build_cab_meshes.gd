## Export the vehicles' seat views (what a driver sees of the airboat, the
## stock car and the riding mower from the seat) as meshes for the 3D view.
##
##   godot --headless --path godot --script res://tools/art/build_cab_meshes.gd \
##       [-- names=cab_car] [no-render]
##
## Blender (scripts/blender/export_meshes.py with vehicle_cabs.py) models
## each cab as parts (the body and its moving parts: a wheel with the hands
## on it, a stick, needles, a lever, the fan's prop), bakes its materials and
## the dusk stage's light into one texture and writes a glTF; this copies the
## meshes to godot/assets3d/cabs/<name>.glb, commits each texture to the
## palette as assets/art/mesh_<name>.png (packed with the rest of the art)
## and writes godot/assets3d/cabs/cabs.json (each part's pivot and axis,
## read by view3d/cab_layer.gd). Then run tools/pack_assets.gd and --import.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")
const Actors := preload("res://tools/art/build_enemy_actors.gd")
const CABS := "res://assets3d/cabs"


func _init() -> void:
	var names := "all"
	var render := true
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("names="):
			names = arg.substr(6)
		elif arg == "no-render":
			render = false
	var raw := Paint.repo("_preview/cabs/mesh_raw")
	DirAccess.make_dir_recursive_absolute(raw)
	if render:
		var code := OS.execute(
			Actors.blender(),
			[
				"-b",
				"--python-exit-code",
				"1",
				"-P",
				Paint.repo("scripts/blender/export_meshes.py"),
				"--",
				raw,
				names,
				"vehicle_cabs.py"
			]
		)
		if code != 0:
			push_error("Blender failed (exit %d); set BLENDER_PATH if it is elsewhere" % code)
			quit(1)
			return
	var pivots: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(raw.path_join("cabs.json"))
	)
	if not pivots is Dictionary:
		push_error("no %s/cabs.json: export first" % raw)
		quit(1)
		return
	var out_dir := ProjectSettings.globalize_path(CABS)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var art := Paint.repo("assets/art")
	var count := 0
	for name: String in pivots:
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
		count += 1
	var file := FileAccess.open(out_dir.path_join("cabs.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(pivots, "\t", true))
	file.close()
	print("cab meshes: %d written to %s" % [count, out_dir])
	quit()
