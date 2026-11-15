## Load every script under src/ (and tools/ with `tools`): a parse or compile
## error anywhere shows here without playing anything. Prints LOAD ALL OK.
extends SceneTree


func _init() -> void:
	var files: Array[String] = []
	_walk("res://src", files)
	if OS.get_cmdline_user_args().has("tools"):
		_walk("res://tools", files)
	var failed := 0
	for f: String in files:
		var s: Resource = load(f)
		if s == null:
			failed += 1
			print("FAILED ", f)
	print("LOAD ALL OK" if failed == 0 else "LOAD ALL: %d failed" % failed)
	quit(0 if failed == 0 else 1)


func _walk(dir: String, out: Array[String]) -> void:
	for f: String in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d: String in DirAccess.get_directories_at(dir):
		_walk(dir.path_join(d), out)
