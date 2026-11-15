## Each modelled prop as a scene of its own:
## scenes/props/<name>.tscn, a PropView (src/view3d/prop_view.gd) over
## the prop's model (assets3d/props/<name>.glb, an instance, so a new export
## shows through). Run after tools/art/build_prop_meshes.gd and an --import;
## open a scene in the editor to add to it (a lamp, a flame), and it keeps
## those when this runs again only if the prop is skipped (names=).
##
##   godot --headless --path godot --script res://tools/art/build_prop_scenes.gd [-- names=a,b]
extends SceneTree

const OUT := "res://scenes/props"


func _init() -> void:
	var only := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("names="):
			only = arg.substr(6).split(",")
	var data: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(PropModels.FOLDER.path_join("meshes.json"))
	)
	if not data is Dictionary:
		push_error("no meshes.json: build the prop meshes first")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var made := 0
	for name: String in (data as Dictionary).keys():
		if not only.is_empty() and not only.has(name):
			continue
		var model := load(PropModels.FOLDER.path_join(name + ".glb")) as PackedScene
		if model == null:
			push_error("%s: no model (import first)" % name)
			continue
		var root := PropView.new()
		root.name = name.to_pascal_case()
		root.prop = name
		var body := model.instantiate()
		body.name = "Model"
		root.add_child(body)
		body.owner = root
		var packed := PackedScene.new()
		var err := packed.pack(root)
		if err == OK:
			err = ResourceSaver.save(packed, OUT.path_join(name + ".tscn"))
		root.free()
		if err != OK:
			push_error("%s: could not save its scene (%d)" % [name, err])
			continue
		made += 1
	print("PROP SCENES %d" % made)
	quit()
