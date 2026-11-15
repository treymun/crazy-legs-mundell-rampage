## BOSS REMATCH: a row per boss (picked by focus, the pointer or a tap;
## pressed to fight) and BACK. BossRematch draws the board.
class_name RematchScreen
extends UiScreen

var _back: PixelButton
var _rows: Array[PixelButton] = []


func open(m: MainInput) -> void:
	super.open(m)
	clear_buttons()
	var rows := _rows
	rows.clear()
	for i in BossRematch.BOSSES.size():
		var index := i
		var b := add_button(
			Rect2i(19, BossRematch.TOP + i * BossRematch.ROW, 282, BossRematch.ROW),
			str(BossRematch.BOSSES[i]),
			Callable(),
			_fight.bind(index)
		)
		b.focus_entered.connect(_picked.bind(index))
		rows.append(b)
	UiScreen.chain(rows)
	_back = add_pointer_button(Menu.BACK, "back", back)
	rows[posmod(main.rematch_pick, rows.size())].call_deferred("grab_when_shown")


func picked() -> PixelButton:
	return _rows[posmod(main.rematch_pick, _rows.size())]


func _picked(index: int) -> void:
	if index != main.rematch_pick:
		main.rematch_pick = index
		main.menu_note = ""
		main.sound.play("menu_move")


func _fight(index: int) -> void:
	main.rematch_pick = index
	main.sound.play("menu_accept")
	main.start_rematch(str(BossRematch.BOSSES[index]))
	if main.state == "play":
		main.block_fire = true


func back() -> bool:
	main.back_to_title()
	return true


func draw_back(c: Canvas) -> void:
	BossRematch.draw_board(
		c,
		main.menu,
		main.rematch_pick,
		main.rematch_open,
		main.rematch_bests,
		main.menu_note,
		main.rematch_guide(),
		"back" if _back.has_focus() else ""
	)
