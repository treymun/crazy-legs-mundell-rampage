## Where player maps live and how the game gets at them:
##   user://maps/<name>.json          the player's own (the MAP SHED saves here)
##   user://maps/shared/<hash>.json    maps a lobby sent this machine (kept so a
##                                     second match on one needs no new copy)
##   user://maps/saves/<key>.json      one save a map (UserMapSaves)
##   res://data/user_maps/<name>.json  the examples shipped with the game
## Every file goes through UserMap.parse_bytes; one that does not pass shows on
## the CUSTOM MAPS list with its reason and cannot be played. A map is put
## where the game loads levels from (LevelData.preview) under its level id
## when it is played (register()).
class_name UserMaps
extends RefCounted

const FOLDER := "user://maps"
const EXAMPLES := "res://data/user_maps"
const SHARED := "shared"
const SOURCES := ["mine", "example", "shared"]

## Tools put the maps under OS.get_cache_dir() (never the player's folder).
static var folder_override := ""


static func folder() -> String:
	return folder_override if folder_override != "" else FOLDER


static func shared_folder() -> String:
	return folder().path_join(SHARED)


## Every map the list shows: the player's, the examples, then the shared ones
## (each {path, stem, source, map or error, hash, id}), the player's capped
## at limits.maps and the shared at limits.shared.
static func list() -> Array:
	var out: Array = []
	out.append_array(_from(folder(), "mine", UserMap.limit("maps")))
	out.append_array(_from(EXAMPLES, "example", UserMap.limit("maps")))
	out.append_array(_from(shared_folder(), "shared", UserMap.limit("shared")))
	return out


static func _from(dir_path: String, source: String, most: int) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	var names: Array = []
	for file_name: String in dir.get_files():
		if file_name.get_extension().to_lower() == "json":
			names.append(file_name)
	names.sort()
	for file_name: String in names.slice(0, most):
		out.append(read(dir_path.path_join(file_name), source))
	return out


## One file as a list entry.
static func read(path: String, source := "mine") -> Dictionary:
	var entry := {"path": path, "stem": path.get_file().get_basename(), "source": source}
	var size := _size_of(path)
	if size > UserMap.limit("bytes"):
		entry["error"] = (
			"TOO BIG: %d KB. A MAP TOPS OUT AT %d KB."
			% [size / 1024, UserMap.limit("bytes") / 1024]
		)
		return entry
	var parsed := UserMap.parse_bytes(FileAccess.get_file_as_bytes(path))
	if parsed.has("error"):
		entry["error"] = parsed["error"]
		return entry
	var map: Dictionary = parsed["map"]
	entry["map"] = map
	entry["hash"] = UserMap.hash_of(map)
	entry["id"] = UserMap.level_id(map)
	return entry


static func _size_of(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var size := file.get_length()
	file.close()
	return size


## A file name from a map's name ("BUBBA'S BACK 40" -> "bubba_s_back_40").
static func stem_for(name: String) -> String:
	var out := ""
	for ch in name.to_lower():
		out += ch if ("abcdefghijklmnopqrstuvwxyz0123456789").contains(ch) else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.strip_edges().trim_prefix("_").trim_suffix("_")
	return out.left(32) if out != "" else "map"


## Write a map into the player's folder as `stem`: "" or why not.
static func write(map: Dictionary, stem: String) -> String:
	var checked := UserMap.parse_text(UserMap.to_text(map))
	if checked.has("error"):
		return str(checked["error"])
	if not DirAccess.dir_exists_absolute(folder()):
		DirAccess.make_dir_recursive_absolute(folder())
	if (
		not FileAccess.file_exists(path_of(stem))
		and _from(folder(), "mine", 9999).size() >= UserMap.limit("maps")
	):
		return "THE SHED'S FULL: %d MAPS. CLEAR ONE OUT FIRST." % UserMap.limit("maps")
	var temp := path_of(stem) + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return "COULDN'T WRITE THE MAP."
	file.store_string(UserMap.to_text(map))
	file.close()
	if DirAccess.rename_absolute(temp, path_of(stem)) != OK:
		return "COULDN'T WRITE THE MAP."
	return ""


static func path_of(stem: String) -> String:
	return folder().path_join(stem + ".json")


## Throw away one of the player's own maps (the list asks first).
static func remove(entry: Dictionary) -> bool:
	if str(entry.get("source", "")) == "example":
		return false
	return DirAccess.remove_absolute(str(entry["path"])) == OK


## A map a lobby sent, kept under its hash (the oldest go past the cap).
static func keep_shared(map: Dictionary) -> void:
	var dir := shared_folder()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(UserMap.hash_of(map).substr(0, 16) + ".json")
	if FileAccess.file_exists(path):
		return
	var held := DirAccess.get_files_at(dir)
	if held.size() >= UserMap.limit("shared"):
		var oldest := ""
		var when := 0
		for file_name: String in held:
			var stamp := FileAccess.get_modified_time(dir.path_join(file_name))
			if oldest == "" or stamp < when:
				oldest = file_name
				when = stamp
		DirAccess.remove_absolute(dir.path_join(oldest))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(UserMap.to_text(map))
		file.close()


## The map with this hash among every list (or {}).
static func find(hash: String) -> Dictionary:
	for entry: Dictionary in list():
		if str(entry.get("hash", "")) == hash:
			return entry
	return {}


## The map compiled and put where the game loads levels from; the level id
## (the versus copy's for `versus`). One map at a time: any other map's
## levels go (a long session in the shed would pile them up otherwise).
static func register(map: Dictionary, versus := false) -> String:
	var id := UserMap.level_id(map, versus)
	var mine := UserMap.level_id(map).trim_suffix(UserMap.VERSUS_TAIL)
	for key: Variant in LevelData.preview.keys():
		var other := str(key)
		if UserMap.is_custom(other) and not other.begins_with(mine):
			LevelData.preview.erase(other)
	if not LevelData.preview.has(id):
		LevelData.preview[id] = UserMapBuild.level(map, versus)
	return id


## Take a map's levels back out (the shed's test copy, when it changes).
static func forget(map: Dictionary) -> void:
	LevelData.preview.erase(UserMap.level_id(map))
	LevelData.preview.erase(UserMap.level_id(map, true))
