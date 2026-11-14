## The Maps screen: a map source (godot/maps/<id>.map.json) to edit in the
## Godot editor, beside the Levels screen (which edits data/<id>.json cell by
## cell). The plan drawn is map.gd's own render of the source, a floor at a
## time; left button picks an object (a drag moves it: whole cells for one
## that changes cells), right button pans, the wheel zooms. The list picks an
## object by id and shows its JSON to change (Apply); Add puts a new object of
## the type picked where the map was last clicked. Every change is one step of
## the editor's undo. Save writes the source as the command-line tools write
## it; Validate lists the problems (click one to pick its object); Build
## writes data/<id>.json (refused over a level changed by hand); Play from
## here starts the game at the last click, on the floor picked.
@tool
extends VBoxContainer

const Document := preload("res://tools/map/map_document.gd")
const Render := preload("res://tools/map/map_render.gd")
const Source := preload("res://tools/map/map_source.gd")
const SCALE := 8


class MapView:
	extends Control
	var panel

	func _draw() -> void:
		panel.draw_map(self)

	func _gui_input(event: InputEvent) -> void:
		panel.map_input(event)


var plugin: EditorPlugin
var document := Document.new()
var assets: Assets
var selected := ""
var floor_z := NAN
var floors: Array = []
var zoom := 1.5
var offset := Vector2(8, 8)
var cursor := Vector2(-1, -1)
var picture: ImageTexture
## The plan as drawn (also without a screen: the checks look at it).
var plan: Image

var _built := false
var _map: MapView
var _map_pick: OptionButton
var _floor_pick: OptionButton
var _nav: CheckBox
var _type_pick: OptionButton
var _list: ItemList
var _text: TextEdit
var _issues: ItemList
var _status: Label
var _drag_from := Vector2.INF
var _panning := false


func open() -> void:
	if not _built:
		_build()
	_map.queue_redraw()


func _build() -> void:
	_built = true
	assets = Assets.new()
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bar := HBoxContainer.new()
	add_child(bar)
	_map_pick = OptionButton.new()
	for id in Document.list():
		_map_pick.add_item(id)
	_map_pick.item_selected.connect(func(i: int) -> void: load_map(_map_pick.get_item_text(i)))
	bar.add_child(_map_pick)
	_floor_pick = OptionButton.new()
	_floor_pick.item_selected.connect(func(i: int) -> void: _pick_floor(i))
	bar.add_child(_floor_pick)
	_nav = CheckBox.new()
	_nav.text = "Nav"
	_nav.toggled.connect(func(_on: bool) -> void: refresh())
	bar.add_child(_nav)
	for pair: Array in [
		["Save", save], ["Validate", validate], ["Build", build], ["Play from here", _play_here]
	]:
		var b := Button.new()
		b.text = pair[0]
		b.pressed.connect(pair[1])
		bar.add_child(b)
	_status = Label.new()
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_status)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	_map = MapView.new()
	_map.panel = self
	_map.clip_contents = true
	_map.focus_mode = Control.FOCUS_CLICK
	_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(_map)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(360, 0)
	split.add_child(side)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 160)
	_list.item_selected.connect(func(i: int) -> void: select(_list.get_item_text(i)))
	side.add_child(_list)
	var add_row := HBoxContainer.new()
	side.add_child(add_row)
	_type_pick = OptionButton.new()
	for t in Source.TYPES:
		_type_pick.add_item(String(t))
	add_row.add_child(_type_pick)
	var add := Button.new()
	add.text = "Add at click"
	add.pressed.connect(func() -> void: add_object(_type_pick.get_item_text(_type_pick.selected)))
	add_row.add_child(add)
	_text = TextEdit.new()
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(_text)
	var row := HBoxContainer.new()
	side.add_child(row)
	for pair: Array in [["Apply", apply_text], ["Delete", delete_selected]]:
		var b := Button.new()
		b.text = pair[0]
		b.pressed.connect(pair[1])
		row.add_child(b)
	_issues = ItemList.new()
	_issues.custom_minimum_size = Vector2(0, 140)
	_issues.item_selected.connect(_issue_picked)
	side.add_child(_issues)
	if _map_pick.item_count > 0:
		load_map(_map_pick.get_item_text(0))


func note(text: String) -> void:
	if _status != null:
		_status.text = text


func load_map(id: String) -> void:
	var err := document.open(id)
	if err != "":
		note(err)
		return
	selected = ""
	floor_z = NAN
	refresh()
	note("%s: %d objects" % [id, document.ids().size()])


## Compile and draw again, the list and the floors with it.
func refresh() -> void:
	document.check(assets)
	_list.clear()
	for id in document.ids():
		_list.add_item(id)
	_issues.clear()
	for i: Dictionary in document.issues:
		_issues.add_item(
			(
				"%s %s [%s] %s"
				% [String(i["severity"]).to_upper(), i["code"], i.get("object", ""), i["message"]]
			)
		)
	if document.built.is_empty():
		picture = null
		_map.queue_redraw()
		return
	var lv := LevelData.from_dict(document.built["level"], assets)
	var field := FlowField.new(lv)
	field.reach = 1 << 20
	field.doors_open = true
	field.every_door = true
	var spawn: Array = document.built["spawn"]
	field.update(
		spawn[0],
		spawn[1],
		0.0,
		lv.floor_under(spawn[0], spawn[1], (spawn[3] if spawn.size() > 3 else 0.0) + .05)
	)
	floors = Render.floors_of(lv, field)
	_floor_pick.clear()
	_floor_pick.add_item("All floors")
	for z in floors:
		_floor_pick.add_item("Floor z %s" % snappedf(z, .01))
	var at := 0 if is_nan(floor_z) else floors.find(floor_z) + 1
	_floor_pick.select(maxi(0, at))
	var overlays: Array = ["spawns", "objects"]
	if _nav.button_pressed:
		overlays.append_array(["nav", "unreachable"])
	plan = Render._picture(document.doc, document.built, lv, field, floor_z, overlays, SCALE)
	picture = ImageTexture.create_from_image(plan)
	_map.queue_redraw()


func _pick_floor(i: int) -> void:
	floor_z = NAN if i == 0 else float(floors[i - 1])
	refresh()


func select(id: String) -> void:
	selected = id
	var o := document.object(id)
	_text.text = JSON.stringify(o, "  ", false) if not o.is_empty() else ""
	_map.queue_redraw()


# ------------------------------------------------------------- changes


## A change made through the document, put on the editor's undo too.
func _changed(before: Dictionary, what: String, err: String) -> void:
	if err != "":
		note(err)
		return
	note("%s: %s (not saved)" % [document.map_id, what])
	if plugin != null:
		var undo := plugin.get_undo_redo()
		undo.create_action("Map: " + what, UndoRedo.MERGE_DISABLE, self)
		undo.add_do_method(self, "_set_doc", document.doc.duplicate(true))
		undo.add_undo_method(self, "_set_doc", before)
		undo.commit_action(false)
	refresh()
	select(selected)


func _set_doc(value: Dictionary) -> void:
	document.doc = value.duplicate(true)
	refresh()
	select(selected)


func apply_text() -> void:
	if selected == "":
		return
	var before := document.doc.duplicate(true)
	var parsed = JSON.parse_string(_text.text)
	var err := document.set_object(selected, _text.text)
	if err == "" and parsed is Dictionary:
		selected = String(parsed.get("id", selected))
	_changed(before, "edit " + selected, err)


func delete_selected() -> void:
	if selected == "":
		return
	var before := document.doc.duplicate(true)
	var err := document.remove(selected)
	var what := "remove " + selected
	selected = ""
	_changed(before, what, err)


func add_object(type: String) -> void:
	var before := document.doc.duplicate(true)
	var at := cursor if cursor.x >= 0.0 else Vector2(4, 4)
	var err := document.add(type, at)
	if err == "":
		selected = document.ids()[document.ids().size() - 1]
	_changed(before, "add " + type, err)


func move_selected(by: Vector2) -> void:
	if selected == "":
		return
	var before := document.doc.duplicate(true)
	_changed(before, "move " + selected, document.move(selected, by))


func save() -> void:
	note(document.save())


func validate() -> void:
	refresh()
	var errors := 0
	for i: Dictionary in document.issues:
		if i["severity"] == "error":
			errors += 1
	note(
		(
			"%s: %d error(s), %d warning(s)"
			% [document.map_id, errors, document.issues.size() - errors]
		)
	)


func build() -> void:
	note(document.build(assets))


func _issue_picked(i: int) -> void:
	var issue: Dictionary = document.issues[i]
	if String(issue.get("object", "")) != "":
		select(String(issue["object"]))
	if issue.has("at"):
		cursor = Vector2(issue["at"][0], issue["at"][1])


func _play_here() -> void:
	if document.built.is_empty():
		note("build first")
		return
	var spawn: Array = document.built["spawn"]
	var at := cursor if cursor.x >= 0.0 else Vector2(spawn[0], spawn[1])
	var z := 0.0 if is_nan(floor_z) else floor_z
	var key := "editor/run/main_run_args"
	var kept = ProjectSettings.get_setting(key, "")
	ProjectSettings.set_setting(
		key, "-- --play-at=%s:%.2f,%.2f,0,%.2f" % [document.map_id, at.x, at.y, z]
	)
	EditorInterface.play_main_scene()
	get_tree().create_timer(3.0).timeout.connect(
		func() -> void: ProjectSettings.set_setting(key, kept)
	)


# ------------------------------------------------------------- drawing


func _to_map(at: Vector2) -> Vector2:
	return (at - offset) / (zoom * SCALE)


func draw_map(view: Control) -> void:
	view.draw_rect(Rect2(Vector2.ZERO, view.size), Color(.06, .05, .05))
	if picture == null:
		return
	view.draw_texture_rect(picture, Rect2(offset, Vector2(picture.get_size()) * zoom), false)
	var o := document.object(selected)
	if not o.is_empty():
		var c := Color(1, .85, .1)
		var s := zoom * SCALE
		if o.has("rect"):
			var r: Array = o["rect"]
			view.draw_rect(
				Rect2(
					offset + Vector2(r[0], r[1]) * s,
					Vector2(float(r[2]) - float(r[0]), float(r[3]) - float(r[1])) * s
				),
				c,
				false,
				2.0
			)
		elif o.has("a"):
			view.draw_line(
				offset + Vector2(o["a"][0], o["a"][1]) * s,
				offset + Vector2(o["b"][0], o["b"][1]) * s,
				c,
				3.0
			)
		elif o.has("at"):
			view.draw_circle(offset + Vector2(o["at"][0], o["at"][1]) * s, 6.0, c, false, 2.0)
	if cursor.x >= 0.0:
		view.draw_circle(offset + cursor * zoom * SCALE, 3.0, Color(.3, .9, 1))


func map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if (
			button.button_index == MOUSE_BUTTON_WHEEL_UP
			or button.button_index == MOUSE_BUTTON_WHEEL_DOWN
		):
			var before := _to_map(button.position)
			zoom = clampf(
				zoom * (1.15 if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1 / 1.15), .4, 8.0
			)
			offset += (_to_map(button.position) - before) * zoom * SCALE
			_map.queue_redraw()
		elif button.button_index == MOUSE_BUTTON_RIGHT:
			_panning = button.pressed
		elif button.button_index == MOUSE_BUTTON_LEFT:
			var at := _to_map(button.position)
			if button.pressed:
				cursor = at
				var id := document.pick(at)
				if id != "":
					select(id)
				_drag_from = at
			else:
				if _drag_from != Vector2.INF and selected != "" and _drag_from.distance_to(at) > .2:
					move_selected(at - _drag_from)
				_drag_from = Vector2.INF
			_map.queue_redraw()
	elif event is InputEventMouseMotion and _panning:
		offset += (event as InputEventMouseMotion).relative
		_map.queue_redraw()
