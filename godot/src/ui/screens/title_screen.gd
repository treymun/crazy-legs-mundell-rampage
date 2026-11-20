## The title: the board of the county's notices with one button per entry
## (the primary plate, the road's column, the county office's column), laid
## out by Menu.title_items and painted with Menu's own drawing. A button
## picked (focus, hover) is the front end's `selection`; pressing it runs
## the entry (Main.menu_action); BACK resumes a paused game. When the update
## notice found a newer version, its sign (UpdateSign) is one more button the
## keys, a pad, the mouse and a finger reach; picking it opens the download.
class_name TitleScreen
extends UiScreen

var _entries := PackedStringArray()
var _rows: Array[PixelButton] = []
## The update sign's button (null while there is no sign) and whether it has
## the focus rather than the selection's row.
var _sign: PixelButton = null
var _on_sign := false
## What the sign was built for (its platform and version; "": no sign).
var _sign_built := ""


func open(m: MainInput) -> void:
	super.open(m)
	_build()


func _build() -> void:
	for child in get_children():
		if child is PixelButton:
			child.queue_free()
			remove_child(child)
	_entries = main.entries()
	_rows.clear()
	var items := Menu.title_items(_entries)
	var chosen: PixelButton = null
	for i in items.size():
		var item: Dictionary = items[i]
		var index := i
		var rect: Rect2i = item["rect"]
		var b := add_button(
			rect,
			str(item["id"]),
			func(c: Canvas, active: bool) -> void: main.menu.draw_title_item(c, item, active),
			func() -> void: _press(index)
		)
		b.focus_entered.connect(func() -> void: _picked(index))
		_rows.append(b)
		if i == posmod(main.selection, items.size()):
			chosen = b
	_sign = null
	_sign_built = _sign_key()
	if _sign_built != "":
		var android := main.update_notice.target == "android"
		_sign = add_button(
			UpdateSign.rect(android),
			"update",
			func(c: Canvas, active: bool) -> void:
				UpdateSign.draw(
					c, main.update_notice.found, android, active, int(main.menu_clock * 8.0)
				),
			_press_sign
		)
		_sign.focus_entered.connect(func() -> void: _on_sign = true)
		_link_sign(items)
	else:
		_on_sign = false
	if _on_sign and _sign != null:
		chosen = _sign
	if chosen != null:
		chosen.call_deferred("grab_when_shown")


## The keys and a pad reach the sign up from the big plate and right from
## the county office's column; down or left from it goes back to the plate.
func _link_sign(items: Array) -> void:
	var plate: PixelButton = null
	for i in items.size():
		var item: Dictionary = items[i]
		var row := _rows[i]
		var column: int = item["column"]
		var primary: bool = item["primary"]
		if primary:
			plate = row
			row.focus_neighbor_top = row.get_path_to(_sign)
		elif column == 1:
			row.focus_neighbor_right = row.get_path_to(_sign)
	if plate != null:
		_sign.focus_neighbor_bottom = _sign.get_path_to(plate)
		_sign.focus_neighbor_left = _sign.get_path_to(plate)
	_sign.focus_neighbor_top = NodePath(".")
	_sign.focus_neighbor_right = NodePath(".")


## The sign wanted now: "" for none, else its platform and version.
func _sign_key() -> String:
	if main.update_notice == null or not main.update_notice.shown(main.options):
		return ""
	return main.update_notice.target + " " + main.update_notice.found


## The update sign's button, or null (the checks press it).
func sign_button() -> PixelButton:
	return _sign


## Give the focus to the update sign (tools/update_frames.gd).
func pick_sign() -> void:
	if _sign != null:
		_on_sign = true
		_sign.grab_focus()


## Hand the focus back to the selection's row (tools/update_frames.gd).
func leave_sign() -> void:
	_on_sign = false
	_build()


func _press_sign() -> void:
	main.sound.play("menu_accept")
	main.menu_note = main.update_notice.started_note()
	main.update_notice.open_download()


func picked() -> PixelButton:
	if main.entries() != _entries or _sign_key() != _sign_built:
		_build()
	if _on_sign and _sign != null:
		return _sign
	return _rows[posmod(main.selection, _rows.size())] if not _rows.is_empty() else null


func _picked(index: int) -> void:
	_on_sign = false
	if index == posmod(main.selection, maxi(1, _entries.size())):
		return
	main.selection = index
	main.menu_note = ""
	main.sound.play("menu_move")


func _press(index: int) -> void:
	main.selection = index
	main.sound.play("menu_accept")
	main.menu_action()


func back() -> bool:
	if main.game != null:
		main.state = "play"
		main.sound.play("menu_back")
		main.play_music()
		main.grab(not main.game.showing_tally and not main.game.defeated())
	return true


func draw_back(c: Canvas) -> void:
	if main.entries() != _entries or _sign_key() != _sign_built:
		# An entry came or went (a quicksave was made, a game paused), or the
		# update sign (the site answered, CHECK FOR UPDATES was turned off).
		_build()
	var flashes: int = main.options.get("flashes", 0)
	var flicker: int = main.options.get("flicker", 1)
	var steady := flashes != 0 or flicker == 0
	var motion: int = main.options.get("world_motion", 0)
	main.menu.draw_title(
		c,
		_entries,
		main.selection,
		main.menu_note,
		main.title_hint(),
		main.menu_clock,
		motion,
		steady,
		true
	)
