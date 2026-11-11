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
static func _upgrade_step(version: int, _doc: Dictionary) -> Variant:
	match version:
		_:
			push_warning("no upgrade from save version %d" % version)
			return null
