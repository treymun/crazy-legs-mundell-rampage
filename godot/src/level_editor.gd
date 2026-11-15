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

var main: MainFlow
var active := false
var things: Array = []
var thing := 0
var wall_tile := -1
var _note := ""


func _init(owner: MainFlow) -> void:
	main = owner
	var kinds: Array = Enemy.KINDS.keys()
	kinds.sort()
	for kind: Variant in kinds:
		things.append(["enemy", str(kind)])
	var pickups := {}
	for id: String in ["hickston", "fair", "sawmill", "quarry", "bayou", "speedway", "mothership"]:
		for entry: Array in LevelEdit.read(id).get("pickups", []):
			pickups[str(entry[0])] = true
	var names := pickups.keys()
	names.sort()
	for name: Variant in names:
		things.append(["pickup", str(name)])


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
				% [str(things[thing][0]).to_upper(), str(things[thing][1]).to_upper()]
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
			var spot: Vector2 = target["spot"]
			var width: int = level["width"]
			if cell >= 0 and float(spot.distance_to(Vector2(cell % width, cell / width))) < 3.0:
				wall_tile = solid[cell]
				solid[cell] = -1
				_note = "WALL TAKEN OUT"
				return true
			cell = target["front"]
			if cell < 0:
				return false
			if wall_tile < 0:
				for v: Variant in solid:
					var tile: int = v
					if tile >= 0:
						wall_tile = tile
						break
			solid[cell] = wall_tile
			var was: float = level["wall_height"][cell]
			level["wall_height"][cell] = maxf(1.85, was)
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
			var was: float = ground[cell]
			ground[cell] = snappedf(was + step, .01)
			var now: float = ground[cell]
			_note = "FLOOR %.2f" % now
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
				var pickups: Array = level["pickups"]
				pickups.append([what[1], x, y])
			_note = "PLACED %s" % str(what[1]).to_upper()
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
			var enemies: Array = level["enemies"]
			for i in enemies.size():
				var e: Dictionary = enemies[i]
				var d := spot.distance_to(Vector2(_float(e["x"]), _float(e["y"])))
				if d < best:
					best = d
					found = "enemies"
					at = i
			for list: String in ["pickups", "props"]:
				var rows: Array = level[list]
				for i in rows.size():
					var entry: Array = rows[i]
					var d := spot.distance_to(Vector2(_float(entry[1]), _float(entry[2])))
					if d < best:
						best = d
						found = list
						at = i
			if at < 0:
				_note = "NOTHING THERE TO TAKE AWAY"
				return false
			var from_list: Array = level[found]
			from_list.remove_at(at)
			if found == "enemies":
				# Patrol routes are keyed by enemy number: the later ones move up.
				var routes := {}
				for key: Variant in level.get("patrols", {}):
					var n := _int(key)
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
	line += "  [4] %s" % str(things[thing][1]).to_upper()
	c.fill_rect(0, 0, Canvas.WIDTH, 9, Color(0, 0, 0))
	HUD.text(c, line, 2, 1, "mini", HUD.AMBER, false, false)
	# Trigger areas the player stands in (triggers.gd), with whether they fired.
	var inside := PackedStringArray()
	var p := game.player
	for trigger: Dictionary in game.level.triggers:
		var when: Dictionary = trigger.get("when", {})
		var box: Variant = when.get("area")
		if (
			box is Array
			and _float(box[0]) <= p.x
			and p.x <= _float(box[2])
			and _float(box[1]) <= p.y
			and p.y <= _float(box[3])
		):
			var id := str(trigger["id"])
			inside.append(id.to_upper() + (" (FIRED)" if game.triggers_fired.has(id) else ""))
	if not inside.is_empty():
		c.fill_rect(0, 9, Canvas.WIDTH, 9, Color(0, 0, 0))
		HUD.text(c, "TRIGGER  " + ", ".join(inside), 2, 10, "mini", HUD.AMBER, false, false)
	if _note != "":
		c.fill_rect(0, 147, Canvas.WIDTH, 9, Color(0, 0, 0))
		HUD.text(c, _note, 2, 148, "mini", HUD.INK, false, false)


## int() and float() of a value read from data or a dictionary, typed (the
## same result for a number, a bool or a number written as text).
static func _int(v: Variant) -> int:
	return str(v).to_int() if v is String else v


static func _float(v: Variant) -> float:
	return str(v).to_float() if v is String else v
