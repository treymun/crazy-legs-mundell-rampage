## A small level editor inside the game, for running from the project folder
## (an exported game has no editable files, so it never offers it).
##
## F2 in play turns it on or off. It works on what is in front of the player:
##   1  wall: take out the wall cell looked at, or put one in the open cell ahead
##   2  lower / 3 raise the floor of the cell ahead by a tenth
##   4  next thing to place (with Shift: the one before): an enemy or a pickup
##   5  place that thing a step and a half ahead
##   6  take away the enemy, pickup or prop nearest that spot
## Every change is written to res://data/<level>.json at once (wall lists are
## patched, see level_edit.gd) and the level reloads where the player stands,
## enemies fresh. A change saved to that file from outside (a text editor,
## tools/level_edit.gd) reloads the same way.
class_name LevelEditor
extends RefCounted

var main
var active := false
var things: Array = []
var thing := 0
var wall_tile := -1
var _note := ""


func _init(owner) -> void:
	main = owner
	var kinds: Array = Enemy.KINDS.keys()
	kinds.sort()
	for kind in kinds:
		things.append(["enemy", String(kind)])
	var pickups := {}
	for id in ["hickston", "fair", "sawmill", "quarry"]:
		for entry: Array in LevelEdit.read(id).get("pickups", []):
			pickups[String(entry[0])] = true
	var names := pickups.keys()
	names.sort()
	for name in names:
		things.append(["pickup", String(name)])


static func available() -> bool:
	return not OS.has_feature("template")


func toggle() -> void:
	active = not active
	_note = "EDITOR ON: 1 WALL  2/3 FLOOR  4 THING  5 PLACE  6 REMOVE" if active else ""
	main.notice("LEVEL EDITOR ON." if active else "LEVEL EDITOR OFF.")


## True when the key was the editor's.
func key(code: int, shift: bool) -> bool:
	if not active:
		return false
	match code:
		KEY_1:
			_toggle_wall()
		KEY_2:
			_floor(-.1)
		KEY_3:
			_floor(.1)
		KEY_4:
			thing = posmod(thing + (-1 if shift else 1), things.size())
			_note = (
				"PLACE: %s %s"
				% [String(things[thing][0]).to_upper(), String(things[thing][1]).to_upper()]
			)
		KEY_5:
			_place()
		KEY_6:
			_remove()
		_:
			return false
	return true


## What is in front of the player: the first wall cell within six cells (or
## -1), the open cell just before it, and the spot a step and a half ahead.
func _target() -> Dictionary:
	var game: Game = main.game
	var p := game.player
	var w := game.world.width
	var dx := cos(p.angle)
	var dy := sin(p.angle)
	var hit := -1
	var front := -1
	var t := .3
	while t < 6.0:
		var x := int(p.x + dx * t)
		var y := int(p.y + dy * t)
		if x < 0 or y < 0 or x >= w or y >= game.world.height:
			break
		var i := y * w + x
		if game.world.solid[i] >= 0:
			hit = i
			break
		if t <= 1.6:
			front = i
		t += .05
	return {"hit": hit, "front": front, "spot": Vector2(p.x + dx * 1.5, p.y + dy * 1.5)}


func _edit(change: Callable, grid: bool) -> void:
	var game: Game = main.game
	var id := game.level.id
	var before := LevelEdit.read(id)
	if before.is_empty():
		main.notice("CANNOT READ THE LEVEL FILE.")
		return
	var after := before.duplicate(true)
	if not change.call(after):
		return
	if grid:
		LevelEdit.refresh_heights(after)
		LevelEdit.patch_walls(before, after, game.art.tile_index)
	if not LevelEdit.write(id, after):
		main.notice("CANNOT WRITE THE LEVEL FILE.")
		return
	main.reload_level_in_place()


func _toggle_wall() -> void:
	var target := _target()
	_edit(
		func(level: Dictionary) -> bool:
			var solid: Array = level["solid"]
			var cell: int = target["hit"]
			if (
				cell >= 0
				and (
					float(
						target["spot"].distance_to(
							Vector2(cell % int(level["width"]), cell / int(level["width"]))
						)
					)
					< 3.0
				)
			):
				wall_tile = int(solid[cell])
				solid[cell] = -1
				_note = "WALL TAKEN OUT"
				return true
			cell = target["front"]
			if cell < 0:
				return false
			if wall_tile < 0:
				for v in solid:
					if int(v) >= 0:
						wall_tile = int(v)
						break
			solid[cell] = wall_tile
			level["wall_height"][cell] = maxf(1.85, float(level["wall_height"][cell]))
			_note = "WALL PUT IN"
			return true,
		true
	)


func _floor(step: float) -> void:
	var target := _target()
	_edit(
		func(level: Dictionary) -> bool:
			var cell: int = target["front"]
			if cell < 0:
				return false
			var ground: Array = level["ground"]
			ground[cell] = snappedf(float(ground[cell]) + step, .01)
			_note = "FLOOR %.2f" % float(ground[cell])
			return true,
		true
	)


func _place() -> void:
	var spot: Vector2 = _target()["spot"]
	var what: Array = things[thing]
	_edit(
		func(level: Dictionary) -> bool:
			var x := snappedf(spot.x, .01)
			var y := snappedf(spot.y, .01)
			if what[0] == "enemy":
				var list: Array = level["enemies"]
				list.append(
					{"kind": what[1], "x": x, "y": y, "id": "%s-edit-%d" % [what[1], list.size()]}
				)
			else:
				level["pickups"].append([what[1], x, y])
			_note = "PLACED %s" % String(what[1]).to_upper()
			return true,
		false
	)


func _remove() -> void:
	var spot: Vector2 = _target()["spot"]
	_edit(
		func(level: Dictionary) -> bool:
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
				_note = "NOTHING THERE TO TAKE AWAY"
				return false
			level[found].remove_at(at)
			if found == "enemies":
				# Patrol routes are keyed by enemy number: the later ones move up.
				var routes := {}
				for key in level.get("patrols", {}):
					var n := int(key)
					if n != at:
						routes[str(n - 1 if n > at else n)] = level["patrols"][key]
				level["patrols"] = routes
			_note = "TOOK AWAY ONE OF THE %s" % found.to_upper()
			return true,
		false
	)


func draw(c: Canvas) -> void:
	if not active or main.game == null:
		return
	var game: Game = main.game
	var target := _target()
	var cell: int = target["hit"] if target["hit"] >= 0 else target["front"]
	var line := "EDIT"
	if cell >= 0:
		var w := game.world.width
		line += "  CELL %d,%d" % [cell % w, cell / w]
		if game.world.solid[cell] >= 0:
			line += " WALL %s" % String(game.world.tile_names[game.world.solid[cell]]).to_upper()
		else:
			line += " FLOOR %.2f" % game.world.ground[cell]
	line += "  [4] %s" % String(things[thing][1]).to_upper()
	c.fill_rect(0, 0, Canvas.WIDTH, 9, Color(0, 0, 0))
	HUD.text(c, line, 2, 1, "mini", HUD.AMBER, false, false)
	if _note != "":
		c.fill_rect(0, 147, Canvas.WIDTH, 9, Color(0, 0, 0))
		HUD.text(c, _note, 2, 148, "mini", HUD.INK, false, false)
