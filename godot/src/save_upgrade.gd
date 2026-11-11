## Bringing an older save up to the current format (SessionStore.VERSION).
## SessionStore reads every save through upgrade(); tools/save_fixtures.gd
## checks real saves of each version still load.
class_name SaveUpgrade
extends RefCounted


## A save document brought up to VERSION, or null when it is too old, from a
## newer build, or not a save. Retained chapters are upgraded with it.
static func upgrade(doc) -> Variant:
	if not (doc is Dictionary):
		return null
	var version := int(doc.get("version", 0))
	if version < SessionStore.OLDEST_VERSION or version > SessionStore.VERSION:
		return null
	while version < SessionStore.VERSION:
		doc = _upgrade_step(version, doc)
		if doc == null:
			return null
		version += 1
		doc["version"] = version
	var retained = doc.get("retained")
	if retained is Dictionary:
		for key in retained:
			var chapter = upgrade(retained[key])
			if chapter == null:
				return null
			retained[key] = chapter
	return doc


## Turn a save of `version` into one of version + 1 (null if it cannot be).
## Each format change adds its step here, oldest first, for example:
##   4: _doc["player"]["stamina"] = 1.0   # version 5 added stamina
static func _upgrade_step(version: int, doc: Dictionary) -> Variant:
	match version:
		4:
			# Version 5 saves which level triggers have fired; none had.
			doc["triggers"] = []
			return doc
		5:
			# Version 6 keeps each feature's state in one block; the triggers'
			# list moved into it.
			var fired = doc.get("triggers", [])
			doc.erase("triggers")
			var kept: bool = fired is Array and not fired.is_empty()
			doc["features"] = {"triggers": {"fired": fired}} if kept else {}
			return doc
		6:
			# Version 7 says which build of its level a save is of; every save
			# before it was of the first (SessionStore restarts a chapter whose
			# level has been rebuilt since).
			doc["layout"] = 1
			return doc
		_:
			push_warning("no upgrade from save version %d" % version)
			return null
