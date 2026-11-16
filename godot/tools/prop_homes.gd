## Which chapter's pack each modelled prop goes in for the browser build (its
## baked picture mesh_<name> in art_<stem>.bin, its model
## assets3d/props/<name>.glb in the chapter's pack: tools/pack_assets.gd,
## tools/make_packs.gd). A prop is a chapter's when every level whose data
## shows its picture (town_<name>, a quest station's town_<name>_off / _on)
## is that chapter or its county map, and no script, tuning file or model
## data names it (code may show it anywhere). Every other prop stays in the
## first download, so a prop added anywhere is safe by default.
##
## By path, not class name: pack_assets.gd runs before the project is imported.
extends RefCounted

const AssetsLib := preload("res://src/assets.gd")
const PROPS := "res://assets3d/props"
const LOOKS := ["off", "on"]


## name -> the stem of the chapter it belongs to (Assets.stem_of), for the
## props that belong to one.
static func homes() -> Dictionary:
	var sizes: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(PROPS.path_join("meshes.json"))
	)
	if not sizes is Dictionary:
		return {}
	var props: Dictionary = sizes
	var named := _code_words()
	var shown := {}  # prop -> {stem or "-": true}
	var picture := RegEx.create_from_string('"town_([a-z0-9_]+)"')
	for file in DirAccess.get_files_at("res://data"):
		if not file.ends_with(".json") or file == "index.json":
			continue
		var level_id := file.get_basename()
		var stem := AssetsLib.stem_of(level_id)
		var text := FileAccess.get_file_as_string("res://data".path_join(file))
		var seen := {}
		for found in picture.search_all(text):
			seen[found.get_string(1)] = true
		for image: String in seen:
			var name := prop_of(image, props)
			if name == "":
				continue
			var where: Dictionary = shown.get(name, {})
			where[stem if stem != "" else "-"] = true
			shown[name] = where
	var out := {}
	for name: String in shown:
		var where: Dictionary = shown[name]
		if where.size() == 1 and not where.has("-") and not named.has(name):
			out[name] = str(where.keys()[0])
	return out


## The prop a picture town_<image> shows ("" none), as PropModels reads it.
static func prop_of(image: String, props: Dictionary) -> String:
	if props.has(image):
		return image
	for look: String in LOOKS:
		if image.ends_with("_" + look) and props.has(image.trim_suffix("_" + look)):
			return image.trim_suffix("_" + look)
	return ""


## Every word in the game's scripts, tuning and model data.
static func _code_words() -> Dictionary:
	var words := {}
	var word := RegEx.create_from_string("[A-Za-z0-9_]+")
	var files := PackedStringArray()
	_gather("res://src", ["gd", "gdshader", "gdshaderinc"], files)
	_gather("res://data/tuning", ["cfg", "json"], files)
	_gather("res://assets3d", ["json"], files)
	for path in files:
		if path.ends_with("props/meshes.json"):
			continue
		for found in word.search_all(FileAccess.get_file_as_string(path)):
			words[found.get_string()] = true
	return words


static func _gather(folder: String, extensions: Array, into: PackedStringArray) -> void:
	for file in DirAccess.get_files_at(folder):
		if file.get_extension() in extensions:
			into.append(folder.path_join(file))
	for sub in DirAccess.get_directories_at(folder):
		_gather(folder.path_join(sub), extensions, into)
