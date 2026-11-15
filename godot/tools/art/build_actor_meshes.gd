## Export the enemies and bosses as rigged, animated meshes for the 3D view.
##
##   godot --headless --path godot --script res://tools/art/build_actor_meshes.gd \
##       [-- kinds=billy,coot] [no-render]
##
## Blender (scripts/blender/export_actors.py) builds each kind with the code
## that renders its cels, frame by frame, rigs it from how its parts move and
## bakes its looks (plain, hurt, a boss's phases); this copies the meshes to
## godot/assets3d/actors/<kind>.glb, commits each look to the palette as
## assets/art/actor3d_<kind>[_<look>].png (packed with the rest of the art)
## and notes each kind's frames and looks in godot/assets3d/actors/actors.json
## (view3d/actor_models.gd). Then run tools/pack_assets.gd and --import.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")
const Actors := preload("res://tools/art/build_enemy_actors.gd")
const FOLDER := "res://assets3d/actors"


func _init() -> void:
	var kinds := "all"
	var render := true
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("kinds="):
			kinds = arg.substr(6)
		elif arg == "no-render":
			render = false
	var raw := Paint.repo("_preview/actors/mesh_raw")
	DirAccess.make_dir_recursive_absolute(raw)
	if render:
		var said: Array = []
		var code := OS.execute(
			Actors.blender(),
			["-b", "-P", Paint.repo("scripts/blender/export_actors.py"), "--", raw, kinds],
			said,
			true
		)
		# Blender's own report lines (each kind, the bake's missed texels).
		for chunk: Variant in said:
			for line in str(chunk).split("\n"):
				if line.begins_with("ACTOR"):
					print(line)
		if code != 0:
			push_error("Blender failed (exit %d); set BLENDER_PATH if it is elsewhere" % code)
			quit(1)
			return
	var meta: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(raw.path_join("actors.json"))
	)
	if not meta is Dictionary:
		push_error("no %s/actors.json: export first" % raw)
		quit(1)
		return
	var out_dir := ProjectSettings.globalize_path(FOLDER)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var known_path := out_dir.path_join("actors.json")
	var known: Dictionary = {}
	if FileAccess.file_exists(known_path):
		known = JSON.parse_string(FileAccess.get_file_as_string(known_path))
	var art := Paint.repo("assets/art")
	var count := 0
	for kind: String in meta:
		if kinds != "all" and not (kind in kinds.split(",")):
			continue
		var glb := raw.path_join(kind + ".glb")
		if not FileAccess.file_exists(glb):
			continue
		DirAccess.copy_absolute(glb, out_dir.path_join(kind + ".glb"))
		var entry: Dictionary = meta[kind]
		for look: String in entry["textures"]:
			var tag := kind if look == "" else "%s_%s" % [kind, look]
			var baked := Paint.Sheet.load_png(raw.path_join(tag + ".png"))
			var seed := 0
			for ch in tag.to_utf8_buffer():
				seed += ch
			Paint.digitize(Paint.photo_grade(baked, seed)).save(
				art.path_join("actor3d_%s.png" % tag)
			)
		known[kind] = entry
		count += 1
	var file := FileAccess.open(known_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(known, "\t", true))
	file.close()
	print("actor meshes: %d written to %s" % [count, out_dir])
	quit()
