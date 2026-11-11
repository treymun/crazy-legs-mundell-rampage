## Change a level from the command line (the same changes as the in-game
## editor, level_editor.gd; wall lists are patched, see level_edit.gd).
##
##   Godot --headless --path godot --script res://tools/level_edit.gd -- <level> <change...>
##
##   wall <x> <y> <tile|open>      put a wall of that tile in a cell, or take it out
##   floor <x> <y> <height>        set a cell's floor height
##   enemy <kind> <x> <y>          add an enemy
##   pickup <name> <x> <y>         add a pickup
##   remove <x> <y>                take away the enemy, pickup or prop nearest there
##   trigger '<json>'              add a trigger (src/triggers.gd), or replace the
##                                 one with its id
##   untrigger <id>                take a trigger away
##
## A game running from the project folder reloads the level when the file
## changes.
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: level_edit.gd -- <level> <change...> (see the top of the file)")
		quit(1)
		return
	var id := String(args[0])
	var before := LevelEdit.read(id)
	if before.is_empty():
		push_error("no level " + id)
		quit(1)
		return
	var assets := Assets.new()
	var after := before.duplicate(true)
	var w := int(after["width"])
	var what := String(args[1])
	var grid := false
	match what:
		"wall":
			var cell := int(args[3]) * w + int(args[2])
			if String(args[4]) == "open":
				after["solid"][cell] = -1
			else:
				after["solid"][cell] = int(assets.tile_index.get(String(args[4]), -1))
				after["wall_height"][cell] = maxf(1.85, float(after["wall_height"][cell]))
			grid = true
		"floor":
			after["ground"][int(args[3]) * w + int(args[2])] = float(args[4])
			grid = true
		"enemy":
			var list: Array = after["enemies"]
			list.append(
				{
					"kind": String(args[2]),
					"x": float(args[3]),
					"y": float(args[4]),
					"id": "%s-edit-%d" % [args[2], list.size()]
				}
			)
		"pickup":
			after["pickups"].append([String(args[2]), float(args[3]), float(args[4])])
		"trigger":
			var trigger = JSON.parse_string(String(args[2]))
			if not (trigger is Dictionary and trigger.has("id") and trigger.has("do")):
				push_error("a trigger is a JSON object with an id and a do list")
				quit(1)
				return
			var kept: Array = []
			for old: Dictionary in after.get("triggers", []):
				if String(old["id"]) != String(trigger["id"]):
					kept.append(old)
			kept.append(trigger)
			after["triggers"] = kept
		"untrigger":
			var left: Array = []
			for old: Dictionary in after.get("triggers", []):
				if String(old["id"]) != String(args[2]):
					left.append(old)
			after["triggers"] = left
		"remove":
			if not _remove(after, Vector2(float(args[2]), float(args[3]))):
				push_error("nothing within 1.2 of that spot")
				quit(1)
				return
		_:
			push_error("unknown change " + what)
			quit(1)
			return
	if grid:
		LevelEdit.refresh_heights(after)
		LevelEdit.patch_walls(before, after, assets.tile_index)
	LevelEdit.write(id, after)
	print(
		"%s: %s done (walls %d -> %d)" % [id, what, before["walls"].size(), after["walls"].size()]
	)
	quit()


func _remove(level: Dictionary, spot: Vector2) -> bool:
	var best := 1.2
	var found := ""
	var at := -1
	for i in level["enemies"].size():
		var e: Dictionary = level["enemies"][i]
		var d := spot.distance_to(Vector2(float(e["x"]), float(e["y"])))
		if d < best:
			best = d
			found = "enemies"
			at = i
	for list in ["pickups", "props"]:
		for i in level[list].size():
			var entry: Array = level[list][i]
			var d := spot.distance_to(Vector2(float(entry[1]), float(entry[2])))
			if d < best:
				best = d
				found = list
				at = i
	if at < 0:
		return false
	level[found].remove_at(at)
	if found == "enemies":
		var routes := {}
		for key in level.get("patrols", {}):
			var n := int(key)
			if n != at:
				routes[str(n - 1 if n > at else n)] = level["patrols"][key]
		level["patrols"] = routes
	return true
