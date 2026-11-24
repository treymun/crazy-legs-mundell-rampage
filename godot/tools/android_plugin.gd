## Build the Android updater's AAR (addons/clmr_updater/bin/clmr_updater.aar)
## from its Java (addons/clmr_updater/java) for the Gradle export. Needs a
## JDK 17 (JAVA_HOME, or javac on the PATH), the Android SDK (ANDROID_HOME or
## ANDROID_SDK_ROOT, with a platforms/android-N) and Godot's export
## templates with android_source.zip (the godot-lib the plugin is compiled
## against; an Android build template installed in the project serves too).
##
##   godot --headless --path godot --script res://tools/android_plugin.gd
##
## The AAR is a zip of the compiled classes (classes.jar), the plugin's
## manifest part (addons/clmr_updater/aar/AndroidManifest.xml) and an empty
## R.txt: no Gradle project of its own. Prints ANDROID PLUGIN BUILT.
extends SceneTree

const ADDON := "res://addons/clmr_updater/"
const GODOT_LIB := "res://android/build/libs/release/godot-lib.template_release.aar"


func _init() -> void:
	var why := build()
	if why != "":
		printerr("ANDROID PLUGIN NOT BUILT: " + why)
		quit(1)
		return
	print("ANDROID PLUGIN BUILT: " + ProjectSettings.globalize_path(ADDON + "bin/clmr_updater.aar"))
	quit(0)


func build() -> String:
	var javac := _javac()
	if javac == "":
		return "no javac (set JAVA_HOME to a JDK 17)"
	var android_jar := _android_jar()
	if android_jar == "":
		return 'no Android SDK platform (set ANDROID_HOME; sdkmanager "platforms;android-36")'
	var godot_lib := _godot_lib()
	if godot_lib.is_empty():
		return "no godot-lib: install Godot's export templates (android_source.zip)"
	var work := OS.get_cache_dir().path_join("clmr_android_plugin")
	_wipe(work)
	DirAccess.make_dir_recursive_absolute(work.path_join("classes"))
	# godot-lib's classes, to compile against (not packed: the export has them).
	var lib := ZIPReader.new()
	var aar_path := work.path_join("godot-lib.aar")
	var f := FileAccess.open(aar_path, FileAccess.WRITE)
	f.store_buffer(godot_lib)
	f.close()
	if lib.open(aar_path) != OK:
		return "cannot read godot-lib"
	var godot_classes := work.path_join("godot-lib.jar")
	f = FileAccess.open(godot_classes, FileAccess.WRITE)
	f.store_buffer(lib.read_file("classes.jar"))
	f.close()
	lib.close()
	var sources := _files(ProjectSettings.globalize_path(ADDON + "java"), ".java")
	if sources.is_empty():
		return "no Java sources"
	var sep := ";" if OS.get_name() == "Windows" else ":"
	var args := [
		"-encoding",
		"UTF-8",
		"-source",
		"17",
		"-target",
		"17",
		"-Xlint:-options",
		"-nowarn",
		"-cp",
		android_jar + sep + godot_classes,
		"-d",
		work.path_join("classes"),
	]
	args.append_array(sources)
	var out := []
	if OS.execute(javac, args, out, true) != 0:
		return "javac failed:\n" + "".join(out)
	# classes.jar, then the AAR around it.
	var classes := work.path_join("classes.jar")
	var jar := ZIPPacker.new()
	jar.open(classes)
	var root := work.path_join("classes")
	for path: String in _files(root, ".class"):
		jar.start_file(path.substr(root.length() + 1).replace("\\", "/"))
		jar.write_file(FileAccess.get_file_as_bytes(path))
		jar.close_file()
	jar.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ADDON + "bin"))
	var aar := ZIPPacker.new()
	if aar.open(ProjectSettings.globalize_path(ADDON + "bin/clmr_updater.aar")) != OK:
		return "cannot write the AAR"
	var parts := {
		"AndroidManifest.xml": FileAccess.get_file_as_bytes(ADDON + "aar/AndroidManifest.xml"),
		"classes.jar": FileAccess.get_file_as_bytes(classes),
		"R.txt": PackedByteArray(),
	}
	for name: String in parts:
		aar.start_file(name)
		aar.write_file(parts[name])
		aar.close_file()
	aar.close()
	_wipe(work)
	return ""


## godot-lib's release AAR: from the build template installed in the project,
## else from the export templates' android_source.zip.
func _godot_lib() -> PackedByteArray:
	if FileAccess.file_exists(GODOT_LIB):
		return FileAccess.get_file_as_bytes(GODOT_LIB)
	var v := Engine.get_version_info()
	var version := "%d.%d.%d.%s" % [v["major"], v["minor"], v["patch"], v["status"]]
	for folder: String in ["Godot", "godot"]:
		var zip := OS.get_data_dir().path_join(folder).path_join("export_templates")
		zip = zip.path_join(version).path_join("android_source.zip")
		var source := ZIPReader.new()
		if FileAccess.file_exists(zip) and source.open(zip) == OK:
			var lib := source.read_file("libs/release/godot-lib.template_release.aar")
			source.close()
			if not lib.is_empty():
				return lib
	return PackedByteArray()


func _javac() -> String:
	var exe := "javac.exe" if OS.get_name() == "Windows" else "javac"
	var home := OS.get_environment("JAVA_HOME")
	if home != "" and FileAccess.file_exists(home.path_join("bin").path_join(exe)):
		return home.path_join("bin").path_join(exe)
	var out := []
	var finder := "where" if OS.get_name() == "Windows" else "which"
	if OS.execute(finder, [exe], out, true) == 0 and not out.is_empty():
		return String(out[0]).split("\n")[0].strip_edges()
	return ""


## The SDK's newest platforms/android-N/android.jar.
func _android_jar() -> String:
	for key: String in ["ANDROID_HOME", "ANDROID_SDK_ROOT"]:
		var sdk := OS.get_environment(key)
		if sdk == "":
			continue
		var best := -1
		for d in DirAccess.get_directories_at(sdk.path_join("platforms")):
			var level := String(d).trim_prefix("android-")
			if level.is_valid_int() and int(level) > best:
				if FileAccess.file_exists(
					sdk.path_join("platforms").path_join(d).path_join("android.jar")
				):
					best = int(level)
		if best >= 0:
			return sdk.path_join("platforms").path_join("android-%d" % best).path_join(
				"android.jar"
			)
	return ""


func _files(dir: String, ext: String) -> Array[String]:
	var found: Array[String] = []
	for sub in DirAccess.get_directories_at(dir):
		found.append_array(_files(dir.path_join(sub), ext))
	for file in DirAccess.get_files_at(dir):
		if String(file).ends_with(ext):
			found.append(dir.path_join(file))
	return found


func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(sub))
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)
