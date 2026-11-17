## Bringing an older save up to the current format (SessionStore.VERSION).
## SessionStore reads every save through upgrade(); tools/save_fixtures.gd
## checks real saves of each version still load.
class_name SaveUpgrade
extends RefCounted


## A save document brought up to VERSION, or null when it is too old, from a
## newer build, or not a save. Retained chapters are upgraded with it.
static func upgrade(given: Variant) -> Variant:
	if not (given is Dictionary):
		return null
	var doc: Dictionary = given
	var version: int = doc.get("version", 0)
	if version < SessionStore.OLDEST_VERSION or version > SessionStore.VERSION:
		return null
	while version < SessionStore.VERSION:
		var stepped: Variant = _upgrade_step(version, doc)
		if stepped == null:
			return null
		doc = stepped
		version += 1
		doc["version"] = version
	var retained: Variant = doc.get("retained")
	if retained is Dictionary:
		var chapters: Dictionary = retained
		for key: Variant in chapters:
			var chapter: Variant = upgrade(chapters[key])
			if chapter == null:
				return null
			chapters[key] = chapter
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
			var fired: Variant = doc.get("triggers", [])
			doc.erase("triggers")
			var kept := false
			if fired is Array:
				var fired_list: Array = fired
				kept = not fired_list.is_empty()
			doc["features"] = {"triggers": {"fired": fired}} if kept else {}
			return doc
		6:
			# Version 7 says which build of its level a save is of; every save
			# before it was of the first (SessionStore restarts a chapter whose
			# level has been rebuilt since).
			doc["layout"] = 1
			return doc
		7:
			# Version 8 keeps the floor each body stands on (level format 2:
			# a deck over the ground). No level had geometry before it, so
			# every floor was the ground (never read without geometry).
			var player: Variant = doc.get("player")
			if player is Dictionary:
				var player_doc: Dictionary = player
				player_doc["floor_z"] = 0.0
			var enemies: Variant = doc.get("enemies")
			if enemies is Dictionary:
				var bodies: Dictionary = enemies
				for key: Variant in bodies:
					if bodies[key] is Dictionary:
						var body: Dictionary = bodies[key]
						body["floor_z"] = 0.0
			return doc
		8:
			# Version 9 keeps what the set pieces brought down (the barns, water
			# towers and fuel lines: features/set_pieces.gd) in the features
			# block; nothing had come down before them, so they stand.
			var features: Variant = doc.get("features")
			if features is Dictionary:
				var block: Dictionary = features
				block.erase("set_pieces")
			else:
				doc["features"] = {}
			return doc
		9:
			# Version 10 keeps the junk bench's scrap and mods with the guns
			# (src/bench_mods.gd); nobody had any before it.
			var armory: Variant = doc.get("armory")
			if armory is Dictionary:
				var guns: Dictionary = armory
				guns["scrap"] = 0
				guns["mods"] = []
			return doc
		_:
			push_warning("no upgrade from save version %d" % version)
			return null
