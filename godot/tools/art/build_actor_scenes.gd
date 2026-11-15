## Each rigged enemy and boss model as a scene of its own:
## scenes/actors/<kind>.tscn, an ActorView (src/view3d/actor_view.gd) over
## the kind's model (assets3d/actors/<kind>.glb, an instance, so a new export
## shows through). Run after tools/art/build_actor_meshes.gd and an --import
## (tools/art/build_prop_scenes.gd does the same for the props);
## open a scene in the editor to add to it (a lamp, a glow), and it keeps
## those when this runs again only if the kind is skipped (kinds=).
##
##   godot --headless --path godot --script res://tools/art/build_actor_scenes.gd [-- kinds=a,b]
extends SceneTree

const OUT := "res://scenes/actors"


func _init() -> void:
	var only := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("kinds="):
			only = arg.substr(6).split(",")
	var data: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(ActorModels.FOLDER.path_join("actors.json"))
	)
	if not data is Dictionary:
		push_error("no actors.json: build the actor meshes first")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var made := 0
	for kind: String in (data as Dictionary).keys():
		if not only.is_empty() and not only.has(kind):
			continue
		var model := load(ActorModels.FOLDER.path_join(kind + ".glb")) as PackedScene
		if model == null:
			push_error("%s: no model (import first)" % kind)
			continue
		var root := ActorView.new()
		root.name = kind.to_pascal_case()
		root.kind = kind
		var body := model.instantiate()
		body.name = "Model"
		root.add_child(body)
		body.owner = root
		var packed := PackedScene.new()
		var err := packed.pack(root)
		if err == OK:
			err = ResourceSaver.save(packed, OUT.path_join(kind + ".tscn"))
		root.free()
		if err != OK:
			push_error("%s: could not save its scene (%d)" % [kind, err])
			continue
		made += 1
	print("ACTOR SCENES %d" % made)
	quit()
