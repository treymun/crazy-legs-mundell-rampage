## REPLAY LEVEL: a row per chapter (picked by focus, the pointer or a tap;
## pressed to play it again if it is unlocked) and BACK.
class_name ReplaysScreen
extends UiScreen

const TOP := MainState.REPLAY_TOP
const ROW := MainState.REPLAY_ROW
## Where the rows must end (the note and the keys line are under them): with
## more chapters than fit at ROW the rows close up and take the smaller type.
const BOTTOM := 166

var _back: PixelButton
var _rows: Array[PixelButton] = []


func open(m: MainInput) -> void:
	super.open(m)
	clear_buttons()
	var rows := _rows
	rows.clear()
	var row := row_height()
	for i in Campaign.ORDER.size():
		var index := i
		var b := add_button(
			Rect2i(19, TOP + i * row, 282, row),
			str(Campaign.ORDER[i]),
			Callable(),
			_play.bind(index)
		)
		b.focus_entered.connect(_picked.bind(index))
		rows.append(b)
	UiScreen.chain(rows)
	_back = add_pointer_button(Menu.BACK, "back", back)
	rows[posmod(main.replay_selection, rows.size())].call_deferred("grab_when_shown")


## Each chapter's row: ROW, or less so every chapter fits above BOTTOM.
static func row_height() -> int:
	return mini(ROW, (BOTTOM - TOP) / Campaign.ORDER.size())


func picked() -> PixelButton:
	return _rows[posmod(main.replay_selection, _rows.size())]


func _picked(index: int) -> void:
	if index != main.replay_selection:
		main.replay_selection = index
		main.sound.play("menu_move")


func _play(index: int) -> void:
	main.replay_selection = index
	var level_id: String = Campaign.ORDER[index]
	if main.unlocked.has(level_id):
		main.start(level_id, null, [], true, null)
	else:
		main.sound.play("empty")
		main.menu_note = "CONTINUE THE CAMPAIGN TO UNLOCK."


func back() -> bool:
	main.back_to_title()
	return true


func draw_back(c: Canvas) -> void:
	main.menu.draw_sheet(c, "REPLAY LEVEL")
	var row := row_height()
	var big := row >= ROW
	for i in Campaign.ORDER.size():
		var level_id: String = Campaign.ORDER[i]
		var here := i == main.replay_selection
		var color := HUD.AMBER if here else HUD.INK
		var y := TOP + i * row + (4 if big else 3)
		if here:
			c.fill_rect(19, TOP + i * row, 282, row - 1, Canvas.rgb(82, 49, 31))
		HUD.text(c, Campaign.title_of(level_id), 26, y, "menu" if big else "body", color)
		var status := "UNLOCKED" if main.unlocked.has(level_id) else "LOCKED"
		HUD.text(c, status, 292, y + (1 if big else 0), "body", color, false, true, true)
	HUD.text(c, "REPLAY USES ITS OWN SAVE SLOT", 160, BOTTOM + 3, "body", HUD.INK, true)
	var line := main.menu_note if main.menu_note != "" else "ENTER START  /  ESC BACK"
	HUD.text(c, line, 140, 180, "body", HUD.INK, true)
	Menu.plate_button(c, Menu.BACK, "BACK", _back.has_focus())
