## COUNTY RUN's records (CLAUDE.md "County Run"): each map's best survival
## time, highest level and most kills, and how many runs, in
## county-records.json beside the unlocks, never in a campaign save. Tool
## scripts keep theirs under the cache folder (`folder()`), so a test never
## touches a player's records.
class_name CountyRecords
extends RefCounted

const FILE := "county-records.json"

## Set by a test to keep its records somewhere of its own.
static var folder_override := ""


static func folder() -> String:
	if folder_override != "":
		return folder_override
	var loop := Engine.get_main_loop()
	if loop != null and loop.get_script() != null:
		return OS.get_cache_dir().path_join("clmr-county")
	return SessionStore.data_directory()


static func path() -> String:
	return folder().path_join(FILE)


## {map id: {"time", "level", "kills", "runs"}}.
static func read() -> Dictionary:
	if not FileAccess.file_exists(path()):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path()))
	return parsed if parsed is Dictionary else {}


static func best(map_id: String) -> Dictionary:
	var all := read()
	var out = all.get(map_id, {})
	return out if out is Dictionary else {}


## A run ended: its numbers go in where they beat the map's records. Returns
## the map's record as it stood before (for the end screen's PERSONAL BEST).
static func finish(result: Dictionary) -> Dictionary:
	var all := read()
	var map_id := String(result.get("map", ""))
	var was = all.get(map_id, {})
	if not was is Dictionary:
		was = {}
	var before: Dictionary = was.duplicate()
	var now: Dictionary = was.duplicate()
	now["time"] = maxf(float(was.get("time", 0.0)), float(result.get("time", 0.0)))
	now["level"] = maxi(int(was.get("level", 0)), int(result.get("level", 1)))
	now["kills"] = maxi(int(was.get("kills", 0)), int(result.get("kills", 0)))
	now["runs"] = int(was.get("runs", 0)) + 1
	all[map_id] = now
	DirAccess.make_dir_recursive_absolute(folder())
	var file := FileAccess.open(path(), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(all, "\t"))
		file.close()
	return before


## "12:34" (minutes and seconds); past an hour "1:02:03".
static func clock_text(seconds: float) -> String:
	var s := int(seconds)
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]
