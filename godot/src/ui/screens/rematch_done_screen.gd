## After a rematch's boss falls: the time and ribbon. Pressing anywhere (or
## ENTER) goes back to the board; ESC to the title.
class_name RematchDoneScreen
extends UiScreen

var _back: PixelButton


func open(m: MainInput) -> void:
	super.open(m)
	clear_buttons()
	# The whole sheet is the button on to the board: BACK's plate names it.
	_back = add_button(Rect2i(0, 0, 320, 200), "board", Callable(), _board)
	_back.call_deferred("grab_when_shown")


func _board() -> void:
	main.sound.play("menu_accept")
	main.open_rematch_board()


func picked() -> PixelButton:
	return _back


func back() -> bool:
	main.back_to_title()
	return true


func draw_back(c: Canvas) -> void:
	BossRematch.draw_result(
		c,
		main.menu,
		main.rematch_result,
		main.rematch_guide(),
		"back" if _back.is_hovered() else ""
	)
