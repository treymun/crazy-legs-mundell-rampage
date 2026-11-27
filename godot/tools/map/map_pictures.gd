## The 3D pictures of a map not yet written to data/ (map check, map
## pictures, map shot): the level is handed in as a file and played through
## LevelData.preview, then the game's own view tour (main.gd --view-tour)
## takes every viewpoint, as the picture references are made. Run in a
## window, started by tools/map/map_check_cli.gd with its scratch APPDATA:
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/map/map_pictures.gd -- level=<level.json> id=<map id> \
##       --view-tour=<tour.json> --view-out=<dir>
##
## Each viewpoint writes <tag>_fx.png, <tag>_gpu.png and <tag>_3d.png in the
## out folder; the tour quits when done.
extends SceneTree

const ScratchProfile := preload("res://tools/scratch_profile.gd")


func _init() -> void:
	if ScratchProfile.refuse(self, "MAP PICTURES"):
		return
	_run.call_deferred()


func _run() -> void:
	var level_file := ""
	var map_id := ""
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text.begins_with("level="):
			level_file = text.substr(6)
		elif text.begins_with("id="):
			map_id = text.substr(3)
	if level_file != "" and map_id != "":
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(level_file))
		if not (parsed is Dictionary):
			print("MAP PICTURES: %s is not a level" % level_file)
			quit(3)
			return
		LevelData.preview[map_id] = parsed
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
