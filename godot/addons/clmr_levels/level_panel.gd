## The Levels screen: a level's map, drawn from data/<id>.json, to paint on.
##
## Left button paints with the chosen tool (a drag paints a line of cells, or
## draws a trigger's area); right button drags the map; the wheel zooms.
## Every stroke is one step of the editor's undo. Save writes the level back
## the way the game's own editors do (src/level_edit.gd: the wall list is
## patched, never rebuilt), and a game running from the project folder
## reloads it. Play from here starts the game at the last cell clicked.
@tool
extends VBoxContainer

const TOOLS := [
	"Wall", "Open floor", "Raise floor", "Lower floor", "Enemy", "Pickup", "Remove", "Trigger area"
]
const LEVELS := ["hickston", "fair", "sawmill", "quarry", "bayou", "speedway", "mothership", "hub"]
const FLOOR_STEP := .1


## A map that hands its drawing and input to the panel.
class MapView:
	extends Control
	var panel

	func _draw() -> void:
		panel.draw_map(self)

	func _gui_input(event: InputEvent) -> void:
		panel.map_input(event)


var plugin: EditorPlugin
var level_id := "hickston"
var level := {}
var saved := {}
var tile_names: Array = []
var tile_colors: Array[Color] = []
var kinds := PackedStringArray()
var pickup_names := PackedStringArray()
var zoom := 8.0
var offset := Vector2(12, 12)
var cursor := Vector2(-1, -1)
var selected := -1

var _built := false
var _map: MapView
var _level_pick: OptionButton
var _tool_pick: OptionButton
var _tile_pick: OptionButton
var _kind_pick: OptionButton
var _pickup_pick: OptionButton
var _status: Label
var _trigger_text: TextEdit
var _before := {}
var _stroke := false
var _drag_from := Vector2.ZERO
var _drag_to := Vector2.ZERO
var _panning := false
var _last_cell := Vector2i(-1, -1)


func open() -> void:
	if not _built:
		_build()
	_map.queue_redraw()


func _build() -> void:
	_built = true
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_read_palette()
	var bar := HBoxContainer.new()
	add_child(bar)
	_level_pick = _choices(bar, LEVELS)
	_level_pick.item_selected.connect(func(i: int) -> void: _load(LEVELS[i]))
	_tool_pick = _choices(bar, TOOLS)
	_tile_pick = _choices(bar, tile_names)
	_tile_pick.select(maxi(0, tile_names.find("brick")))
	_kind_pick = _choices(bar, kinds)
	_pickup_pick = _choices(bar, pickup_names)
	var save := Button.new()
	save.text = "Save"
	save.pressed.connect(_save)
	bar.add_child(save)
	var play := Button.new()
	play.text = "Play from here"
	play.pressed.connect(_play_here)
	bar.add_child(play)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_status)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	_map = MapView.new()
	_map.panel = self
	_map.clip_contents = true
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_map.focus_mode = Control.FOCUS_CLICK
	split.add_child(_map)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(320, 0)
	split.add_child(side)
	var heading := Label.new()
	heading.text = "Trigger (click one in its area; see src/triggers.gd)"
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD
	side.add_child(heading)
	_trigger_text = TextEdit.new()
	_trigger_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(_trigger_text)
	var row := HBoxContainer.new()
	side.add_child(row)
	for pair: Array in [["Apply", _apply_trigger], ["Delete", _delete_trigger]]:
		var button := Button.new()
		button.text = pair[0]
		button.pressed.connect(pair[1])
		row.add_child(button)
	_load(level_id)


func _choices(bar: HBoxContainer, items: Array) -> OptionButton:
	var pick := OptionButton.new()
	for item in items:
		pick.add_item(String(item))
	bar.add_child(pick)
	return pick


## Tile names and their average colours, enemy kinds and pickup names, all
## read from the project's data so the screen never goes out of date.
func _read_palette() -> void:
	var index = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets_gen/tiles_index.json")
	)
	tile_names = index["names"] if index is Dictionary else []
	var raw := FileAccess.get_file_as_bytes("res://assets_gen/tiles.bin")
	if raw.size() >= 8 and raw.slice(0, 4).get_string_from_ascii() == "TZ01":
		raw = raw.slice(8).decompress(raw.decode_u32(4), FileAccess.COMPRESSION_DEFLATE)
	var tile_bytes := 128 * 128 * 3
	for i in tile_names.size():
		var sum := Vector3.ZERO
		var n := 0
		for y in range(0, 128, 8):
			for x in range(0, 128, 8):
				var o := i * tile_bytes + (y * 128 + x) * 3
				if o + 2 < raw.size():
					sum += Vector3(raw[o], raw[o + 1], raw[o + 2])
					n += 1
		sum /= maxf(1.0, n * 255.0)
		tile_colors.append(Color(sum.x, sum.y, sum.z))
	var cfg := ConfigFile.new()
	cfg.load("res://data/tuning/enemies.cfg")
	for section in cfg.get_sections():
		if section != "all":
			kinds.append(section)
	var names := {}
	for id: String in LEVELS:
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/%s.json" % id))
		if data is Dictionary:
			for pickup in data.get("pickups", []):
				names[String(pickup[0])] = true
	var sorted := names.keys()
	sorted.sort()
	pickup_names = PackedStringArray(sorted)


func _load(id: String) -> void:
	level_id = id
	level = LevelEdit.read(id)
	saved = level.duplicate(true)
	selected = -1
	_trigger_text.text = ""
	_note("%s: %dx%d" % [id, int(level.get("width", 0)), int(level.get("height", 0))])
	if FileAccess.file_exists("res://maps/%s.map.json" % id):
		# Built from a map source: edit that (the Maps screen); a save here
		# makes the next build of it stop rather than lose it.
		_note("%s is built from maps/%s.map.json: edit it in the Maps screen" % [id, id])
	_map.queue_redraw()


func _note(text: String) -> void:
	_status.text = text


# --------------------------------------------------------------- drawing


func _to_screen(at: Vector2) -> Vector2:
	return offset + at * zoom


func _to_map(at: Vector2) -> Vector2:
	return (at - offset) / zoom


func draw_map(view: Control) -> void:
	if level.is_empty():
		return
	var w := int(level["width"])
	var h := int(level["height"])
	view.draw_rect(Rect2(Vector2.ZERO, view.size), Color(.06, .05, .05))
	var solid: Array = level["solid"]
	var ground: Array = level["ground"]
	for y in h:
		for x in w:
			var cell := y * w + x
			var tile := int(solid[cell])
			var color := Color(.32, .30, .27).lightened(clampf(float(ground[cell]) * .35, -.5, .6))
			if tile >= 0:
				color = (
					tile_colors[tile].darkened(.15) if tile < tile_colors.size() else Color.MAGENTA
				)
			view.draw_rect(
				Rect2(_to_screen(Vector2(x, y)), Vector2(zoom, zoom) - Vector2.ONE), color
			)
	for door: Dictionary in level.get("doors", []):
		view.draw_rect(
			Rect2(_to_screen(Vector2(door["x"], door["y"])), Vector2(zoom, zoom)),
			Color(.62, .38, .16),
			false,
			2.0
		)
	var font := ThemeDB.fallback_font
	for i in level.get("triggers", []).size():
		var trigger: Dictionary = level["triggers"][i]
		var box = trigger.get("when", {}).get("area")
		if not box is Array:
			continue
		var rect := Rect2(
			_to_screen(Vector2(box[0], box[1])), Vector2(box[2] - box[0], box[3] - box[1]) * zoom
		)
		var hot: bool = i == selected
		view.draw_rect(rect, Color(1, .55, .1, .22 if hot else .12))
		view.draw_rect(rect, Color(1, .6, .15, .9), false, 2.0 if hot else 1.0)
		view.draw_string(font, rect.position + Vector2(2, 12), String(trigger["id"]), 0, -1, 11)
	for prop in level.get("props", []):
		view.draw_circle(
			_to_screen(Vector2(prop[1], prop[2])), maxf(1.5, zoom * .15), Color(.6, .6, .6)
		)
	for pickup in level.get("pickups", []):
		var at := _to_screen(Vector2(pickup[1], pickup[2]))
		view.draw_rect(Rect2(at - Vector2(2, 2), Vector2(4, 4)), Color(1, .86, .2))
	for station: Dictionary in level.get("stations", []):
		var at := _to_screen(Vector2(station["x"], station["y"]))
		view.draw_rect(Rect2(at - Vector2(3, 3), Vector2(6, 6)), Color.WHITE, false, 2.0)
	for enemy: Dictionary in level.get("enemies", []):
		var at := _to_screen(Vector2(enemy["x"], enemy["y"]))
		view.draw_circle(at, maxf(2.5, zoom * .3), Color(.9, .2, .15))
		if zoom >= 10.0:
			view.draw_string(font, at + Vector2(4, -4), String(enemy["kind"]), 0, -1, 10)
	var spawn: Array = level.get("spawn", [0, 0, 0])
	var start := _to_screen(Vector2(spawn[0], spawn[1]))
	view.draw_circle(start, maxf(3.0, zoom * .35), Color(.2, .9, .3))
	view.draw_line(
		start, start + Vector2(cos(spawn[2]), sin(spawn[2])) * zoom, Color(.2, .9, .3), 2.0
	)
	if cursor.x >= 0.0:
		view.draw_rect(
			Rect2(_to_screen(cursor.floor()), Vector2(zoom, zoom)), Color(.4, .8, 1), false, 2.0
		)
	if _stroke and TOOLS[_tool_pick.selected] == "Trigger area":
		var a := _drag_from.floor()
		var b := _drag_to.floor() + Vector2.ONE
		view.draw_rect(
			Rect2(_to_screen(a.min(b)), (b - a).abs() * zoom), Color(1, .6, .15), false, 2.0
		)


# ----------------------------------------------------------------- input


func map_input(event: InputEvent) -> void:
	if level.is_empty():
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if (
			button.button_index == MOUSE_BUTTON_WHEEL_UP
			or button.button_index == MOUSE_BUTTON_WHEEL_DOWN
		):
			if button.pressed:
				var before := _to_map(button.position)
				zoom = clampf(
					zoom * (1.15 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1 / 1.15),
					3.0,
					48.0
				)
				offset = button.position - before * zoom
				_map.queue_redraw()
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			_panning = button.pressed
		elif button.button_index == MOUSE_BUTTON_LEFT:
			var at := _to_map(button.position)
			if button.pressed:
				cursor = at
				_begin(at)
			elif _stroke:
				_end(at)
			_map.queue_redraw()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _panning:
			offset += motion.relative
			_map.queue_redraw()
		elif _stroke:
			_drag_to = _to_map(motion.position)
			var tool := String(TOOLS[_tool_pick.selected])
			if tool in ["Wall", "Open floor", "Raise floor", "Lower floor"]:
				_paint(_drag_to)
			_map.queue_redraw()


func _begin(at: Vector2) -> void:
	_before = level.duplicate(true)
	_stroke = true
	_drag_from = at
	_drag_to = at
	_last_cell = Vector2i(-1, -1)
	var tool := String(TOOLS[_tool_pick.selected])
	if tool in ["Wall", "Open floor", "Raise floor", "Lower floor"]:
		_paint(at)
	elif tool == "Enemy":
		_place_enemy(at)
	elif tool == "Pickup":
		level["pickups"].append(
			[pickup_names[_pickup_pick.selected], snappedf(at.x, .05), snappedf(at.y, .05)]
		)
	elif tool == "Remove":
		if not _remove(at):
			_note("nothing to remove within 1.2 cells")
	if tool != "Trigger area":
		_select_trigger_at(at)


func _end(at: Vector2) -> void:
	_stroke = false
	if String(TOOLS[_tool_pick.selected]) == "Trigger area":
		var a := _drag_from.floor().min(at.floor())
		var b := _drag_from.floor().max(at.floor()) + Vector2.ONE
		var triggers: Array = level.get("triggers", [])
		var n := triggers.size() + 1
		var ids := {}
		for t: Dictionary in triggers:
			ids[String(t["id"])] = true
		while ids.has("trigger-%d" % n):
			n += 1
		triggers.append(
			{
				"id": "trigger-%d" % n,
				"when": {"area": [a.x, a.y, b.x, b.y]},
				"do": [{"message": "SOMETHING STIRS.", "for": 3.0}]
			}
		)
		level["triggers"] = triggers
		selected = triggers.size() - 1
		_show_trigger()
	_commit(String(TOOLS[_tool_pick.selected]))


## One undo step: the level before the stroke, and after it.
func _commit(name: String) -> void:
	if JSON.stringify(_before) == JSON.stringify(level):
		return
	_note("%s: %s (not saved)" % [level_id, name.to_lower()])
	if plugin == null:
		# Outside the editor (tools/level_edit_check.gd): no undo history.
		return
	var undo := plugin.get_undo_redo()
	undo.create_action("Level: " + name, UndoRedo.MERGE_DISABLE, self)
	undo.add_do_method(self, "_set_level", level.duplicate(true))
	undo.add_undo_method(self, "_set_level", _before.duplicate(true))
	undo.commit_action(false)


func _set_level(value: Dictionary) -> void:
	level = value.duplicate(true)
	if selected >= level.get("triggers", []).size():
		selected = -1
	_show_trigger()
	_map.queue_redraw()


func _paint(at: Vector2) -> void:
	var w := int(level["width"])
	var cell := Vector2i(at.floor())
	if (
		cell == _last_cell
		or cell.x < 0
		or cell.y < 0
		or cell.x >= w
		or cell.y >= int(level["height"])
	):
		return
	_last_cell = cell
	var i := cell.y * w + cell.x
	match String(TOOLS[_tool_pick.selected]):
		"Wall":
			level["solid"][i] = _tile_pick.selected
			level["wall_height"][i] = maxf(1.85, float(level["wall_height"][i]))
		"Open floor":
			level["solid"][i] = -1
		"Raise floor":
			level["ground"][i] = snappedf(float(level["ground"][i]) + FLOOR_STEP, .05)
		"Lower floor":
			level["ground"][i] = snappedf(float(level["ground"][i]) - FLOOR_STEP, .05)


func _place_enemy(at: Vector2) -> void:
	var kind := kinds[_kind_pick.selected]
	var ids := {}
	for e: Dictionary in level["enemies"]:
		ids[String(e["id"])] = true
	var n := 1
	while ids.has("%s-edit-%d" % [kind, n]):
		n += 1
	level["enemies"].append(
		{
			"kind": kind,
			"x": snappedf(at.x, .05),
			"y": snappedf(at.y, .05),
			"id": "%s-edit-%d" % [kind, n]
		}
	)


## The nearest enemy, pickup or prop within 1.2 cells goes (as tools/level_edit.gd).
func _remove(spot: Vector2) -> bool:
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


# --------------------------------------------------------------- triggers


func _select_trigger_at(at: Vector2) -> void:
	var triggers: Array = level.get("triggers", [])
	for i in triggers.size():
		var box = triggers[i].get("when", {}).get("area")
		if box is Array and box[0] <= at.x and at.x <= box[2] and box[1] <= at.y and at.y <= box[3]:
			selected = i
			_show_trigger()
			return


func _show_trigger() -> void:
	var triggers: Array = level.get("triggers", [])
	_trigger_text.text = (
		JSON.stringify(triggers[selected], "  ")
		if selected >= 0 and selected < triggers.size()
		else ""
	)


func _apply_trigger() -> void:
	var parsed = JSON.parse_string(_trigger_text.text)
	if not (parsed is Dictionary and parsed.has("id") and parsed.has("do")):
		_note("a trigger is a JSON object with an id and a do list")
		return
	_before = level.duplicate(true)
	var triggers: Array = level.get("triggers", [])
	if selected >= 0 and selected < triggers.size():
		triggers[selected] = parsed
	else:
		triggers.append(parsed)
		selected = triggers.size() - 1
	level["triggers"] = triggers
	_commit("trigger " + String(parsed["id"]))
	_map.queue_redraw()


func _delete_trigger() -> void:
	var triggers: Array = level.get("triggers", [])
	if selected < 0 or selected >= triggers.size():
		return
	_before = level.duplicate(true)
	triggers.remove_at(selected)
	selected = -1
	_show_trigger()
	_commit("delete trigger")
	_map.queue_redraw()


# ------------------------------------------------------------ save, play


func _save() -> void:
	if level.is_empty():
		return
	var tile_index := {}
	for i in tile_names.size():
		tile_index[tile_names[i]] = i
	if level["solid"] != saved["solid"] or level["ground"] != saved["ground"]:
		LevelEdit.refresh_heights(level)
		LevelEdit.patch_walls(saved, level, tile_index)
	if LevelEdit.write(level_id, level):
		saved = level.duplicate(true)
		_note("%s saved; a game running from the project folder reloads it" % level_id)
	else:
		_note("could not write data/%s.json" % level_id)


func _play_here() -> void:
	var at := (
		cursor.floor() + Vector2(.5, .5)
		if cursor.x >= 0.0
		else Vector2(level["spawn"][0], level["spawn"][1])
	)
	var key := "editor/run/main_run_args"
	var kept = ProjectSettings.get_setting(key, "")
	ProjectSettings.set_setting(key, "-- --play-at=%s:%.2f,%.2f" % [level_id, at.x, at.y])
	EditorInterface.play_main_scene()
	# Only for this run: the project's own setting comes back straight after.
	get_tree().create_timer(3.0).timeout.connect(
		func() -> void: ProjectSettings.set_setting(key, kept)
	)
