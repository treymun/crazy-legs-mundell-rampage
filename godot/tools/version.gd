## Read or stamp the version carried by the project and its export presets.
##
##   Godot --headless --path godot --script res://tools/version.gd            # prints it
##   Godot --headless --path godot --script res://tools/version.gd -- 2.1.0   # stamps it
##
## One version string lives in project.godot (config/version). The export
## presets need it in three more shapes: the four-part Windows file version,
## the Android version name, and the Android version code, an integer that
## must grow with every release an installed copy should update to. A leading
## "v" (a tag name) is dropped.
extends SceneTree


func _init() -> void:
	var project := ProjectSettings.globalize_path("res://project.godot")
	var presets := ProjectSettings.globalize_path("res://export_presets.cfg")
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		var found := RegEx.create_from_string('(?m)^config/version="([^"]*)"').search(
			FileAccess.get_file_as_string(project)
		)
		print(found.get_string(1) if found else "")
		quit(0 if found else 1)
		return
	var version := String(args[0]).trim_prefix("v")
	var shape := RegEx.create_from_string("^(\\d+)\\.(\\d+)\\.(\\d+)(?:-[A-Za-z]+\\.(\\d+))?$")
	var parts := shape.search(version)
	if parts == null:
		push_error("A version looks like 2.1.0 or 2.1.0-dev.3, not " + version)
		quit(1)
		return
	var major := int(parts.get_string(1))
	var minor := int(parts.get_string(2))
	var patch := int(parts.get_string(3))
	var has_build := parts.get_string(4) != ""
	var build := int(parts.get_string(4)) if has_build else 0
	var windows := "%d.%d.%d.%d" % [major, minor, patch, build]
	# A final release sorts above every pre-release of the same number.
	var code := (
		major * 1000000 + minor * 10000 + patch * 100 + (mini(build, 98) if has_build else 99)
	)
	var ok := _replace(project, {'(?m)^config/version="[^"]*"': 'config/version="%s"' % version})
	ok = (
		_replace(
			presets,
			{
				'(?m)^application/file_version="[^"]*"': 'application/file_version="%s"' % windows,
				'(?m)^application/product_version="[^"]*"':
				'application/product_version="%s"' % windows,
				'(?m)^version/name="[^"]*"': 'version/name="%s"' % version,
				"(?m)^version/code=\\d+": "version/code=%d" % code,
			}
		)
		and ok
	)
	if not ok:
		quit(1)
		return
	print("Stamped %s (Windows %s, Android code %d)" % [version, windows, code])
	quit()


func _replace(path: String, rules: Dictionary) -> bool:
	var text := FileAccess.get_file_as_string(path)
	for pattern: String in rules:
		var regex := RegEx.create_from_string(pattern)
		var found := regex.search_all(text)
		if found.size() != 1:
			push_error(
				"%s: expected one line matching %s, found %d" % [path, pattern, found.size()]
			)
			return false
		text = regex.sub(text, String(rules[pattern]))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return true
