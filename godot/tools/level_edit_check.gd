## Check the level editing path (src/level_edit.gd) on every level:
##   - a patch with no change keeps the wall list exactly,
##   - writing a level and reading it back gives the same values,
##   - taking a wall cell out and putting it back again leaves every wall away
##     from that cell as it was and every wall the grids imply in the list
##     (walls on the cell's own edges come back plain, not dressed),
##   - the Godot editor's Levels screen (addons/clmr_levels) paints walls and
##     floors, places and removes enemies, draws trigger areas and takes a
##     trigger's JSON, without writing anything.
##
##   Godot --headless --path godot --script res://tools/level_edit_check.gd   # LEVEL EDIT OK
extends SceneTree


func _init() -> void:
	var assets := Assets.new()
	var failures: Array = []
	for id in [
		"hickston", "fair", "sawmill", "quarry", "bayou", "speedway", "mothership", "hub", "range"
	]:
		var level := LevelEdit.read(id)
		if level.is_empty():
			failures.append("%s: cannot read" % id)
			continue
		var same := level.duplicate(true)
		LevelEdit.patch_walls(level, same, assets.tile_index)
		if str(same["walls"]) != str(level["walls"]):
			failures.append("%s: a patch with no change altered the walls" % id)
		var back = JSON.parse_string(LevelEdit._json(level))
		if str(back) != str(level):
			failures.append("%s: write and read back differ" % id)
		var w := int(level["width"])
		var solid: Array = level["solid"]
		var cell := -1
		for i in range(1, solid.size() - 1):
			if int(solid[i]) >= 0 and i % w > 1 and int(solid[i + 1]) < 0 and int(solid[i - 1]) < 0:
				cell = i
				break
		if cell < 0:
			failures.append("%s: no lone wall cell to try" % id)
			continue
		var opened := level.duplicate(true)
		opened["solid"][cell] = -1
		LevelEdit.patch_walls(level, opened, assets.tile_index)
		if _sorted(opened["walls"]) == _sorted(level["walls"]):
			failures.append("%s: opening cell %d changed no walls" % [id, cell])
		_check_patched(failures, "%s opened %d" % [id, cell], level, opened, cell, assets)
		var closed := opened.duplicate(true)
		closed["solid"][cell] = level["solid"][cell]
		LevelEdit.patch_walls(opened, closed, assets.tile_index)
		_check_patched(failures, "%s closed %d" % [id, cell], opened, closed, cell, assets)
		print(
			(
				"%-9s walls %d -> opened %d -> closed %d"
				% [id, level["walls"].size(), opened["walls"].size(), closed["walls"].size()]
			)
		)
	_panel_checks(failures)
	for failure in failures:
		push_error(failure)
	print("LEVEL EDIT OK" if failures.is_empty() else "LEVEL EDIT FAILED")
	quit(0 if failures.is_empty() else 1)


func _sorted(walls: Array) -> Array:
	var keys: Array = []
	for wall: Array in walls:
		keys.append(LevelEdit._key(wall))
	keys.sort()
	return keys


## After a patch around `cell`: walls away from it are the start's, every wall
## the grids now imply and did not at the start is in the list, and every one
## they no longer imply is gone.
func _check_patched(
	failures: Array, what: String, start: Dictionary, now: Dictionary, cell: int, assets: Assets
) -> void:
	var w := int(start["width"])
	var near := Rect2(cell % w - 1.01, cell / w - 1.01, 3.02, 3.02)
	if _sorted(_away(start["walls"], near)) != _sorted(_away(now["walls"], near)):
		failures.append("%s: walls away from the cell changed" % what)
	var have := {}
	for key in _sorted(now["walls"]):
		have[key] = true
	var was := {}
	for key in _sorted(LevelEdit.implied_walls(start, assets.tile_index)):
		was[key] = true
	var is_now := {}
	for key in _sorted(LevelEdit.implied_walls(now, assets.tile_index)):
		is_now[key] = true
		if not was.has(key) and not have.has(key):
			failures.append("%s: a new wall is missing (%s)" % [what, key])
	for key in was:
		if not is_now.has(key) and have.has(key):
			failures.append("%s: a wall that went is still there (%s)" % [what, key])


func _away(walls: Array, near: Rect2) -> Array:
	var out: Array = []
	for wall: Array in walls:
		var a := Vector2(float(wall[0]), float(wall[1]))
		var b := Vector2(float(wall[2]), float(wall[3]))
		if not (near.has_point(a) and near.has_point(b)):
			out.append(wall)
	return out


## The Levels screen outside the editor: no undo history, nothing saved.
func _panel_checks(failures: Array) -> void:
	var script = load("res://addons/clmr_levels/level_panel.gd")
	if not (script is GDScript and script.can_instantiate()):
		failures.append("Levels screen: addons/clmr_levels/level_panel.gd does not load")
		return
	var panel = script.new()
	panel.open()
	var level: Dictionary = panel.level
	var w := int(level["width"])
	var spot := Vector2.ZERO
	for i in level["solid"].size():
		if int(level["solid"][i]) < 0 and i % w > 2:
			spot = Vector2(i % w + .5, i / w + .5)
			break
	var cell := int(spot.y) * w + int(spot.x)
	var ground_was := float(level["ground"][cell])
	panel._tool_pick.select(panel.TOOLS.find("Wall"))
	panel._begin(spot)
	panel._end(spot)
	if int(panel.level["solid"][cell]) != panel._tile_pick.selected:
		failures.append("Levels screen: painting a wall did not change the cell")
	panel._tool_pick.select(panel.TOOLS.find("Open floor"))
	panel._begin(spot)
	panel._end(spot)
	panel._tool_pick.select(panel.TOOLS.find("Raise floor"))
	panel._begin(spot)
	panel._end(spot)
	if int(panel.level["solid"][cell]) >= 0 or float(panel.level["ground"][cell]) <= ground_was:
		failures.append("Levels screen: opening and raising the cell did not work")
	var enemies := int(panel.level["enemies"].size())
	panel._tool_pick.select(panel.TOOLS.find("Enemy"))
	panel._begin(spot)
	panel._end(spot)
	panel._tool_pick.select(panel.TOOLS.find("Remove"))
	panel._begin(spot)
	panel._end(spot)
	if panel.level["enemies"].size() != enemies:
		failures.append("Levels screen: placing then removing an enemy did not balance")
	var triggers := int(panel.level.get("triggers", []).size())
	panel._tool_pick.select(panel.TOOLS.find("Trigger area"))
	panel._begin(spot)
	panel._drag_to = spot + Vector2(3, 2)
	panel._end(spot + Vector2(3, 2))
	var made: Array = panel.level.get("triggers", [])
	if made.size() != triggers + 1 or not made[-1]["when"].has("area"):
		failures.append("Levels screen: dragging a trigger area made no trigger")
	else:
		var typed := '{"id": "checked", "when": {"after": 1.0}, '
		panel._trigger_text.text = typed + '"do": [{"message": "HI."}]}'
		panel._apply_trigger()
		if String(panel.level["triggers"][-1]["id"]) != "checked":
			failures.append("Levels screen: a trigger's JSON was not taken")
	if LevelEdit.read("hickston").get("triggers", []).size() != triggers:
		failures.append("Levels screen: something was written without Save")
	panel.free()
	print("levels screen: paint, place, remove, trigger area and JSON all work")
