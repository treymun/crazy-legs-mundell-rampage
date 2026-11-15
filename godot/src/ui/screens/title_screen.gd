## The title: the board of the county's notices with one button per entry
## (the primary plate, the road's column, the county office's column), laid
## out by Menu.title_items and painted with Menu's own drawing. A button
## picked (focus, hover) is the front end's `selection`; pressing it runs
## the entry (Main.menu_action); BACK resumes a paused game.
class_name TitleScreen
extends UiScreen

var _entries := PackedStringArray()


func open(m: MainInput) -> void:
	super.open(m)
	_build()


func _build() -> void:
	for child in get_children():
		if child is PixelButton:
			child.queue_free()
			remove_child(child)
	_entries = main.entries()
	var items := Menu.title_items(_entries)
	var chosen: PixelButton = null
	for i in items.size():
		var item: Dictionary = items[i]
		var index := i
		var b := add_button(
			item["rect"],
			String(item["id"]),
			func(c: Canvas, active: bool) -> void: main.menu.draw_title_item(c, item, active),
			func() -> void: _press(index)
		)
		b.focus_entered.connect(func() -> void: _picked(index))
		if i == posmod(main.selection, items.size()):
			chosen = b
	if chosen != null:
		chosen.call_deferred("grab_focus")


func _picked(index: int) -> void:
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
	return true


func draw_back(c: Canvas) -> void:
	if main.entries() != _entries:
		# An entry came or went (a quicksave was made, a game paused).
		_build()
	var steady := (
		int(main.options.get("flashes", 0)) != 0 or int(main.options.get("flicker", 1)) == 0
	)
	main.menu.draw_title(
		c,
		_entries,
		main.selection,
		main.menu_note,
		main.title_hint(),
		main.menu_clock,
		int(main.options.get("world_motion", 0)),
		steady,
		true
	)
