## CREDITS: the blocks of credits and BACK; any press (a tap anywhere on a
## phone) goes back.
class_name CreditsScreen
extends UiScreen

const BLOCKS := [
	["THE 1997 INSPIRATION", ["REDNECK RAMPAGE / XATRIX ENTERTAINMENT"]],
	[
		"PHOTOGRAPHS",
		[
			"JERRY JONES / KEITH ALLISON (CC BY-SA 2.0)",
			"ROADSIDE / JOHN MARGOLIES, LIBRARY OF CONGRESS"
		]
	],
	[
		"MATERIALS AND AUDIO",
		[
			"SCORE AND EFFECTS / ELEVENLABS, FINISHED BY HAND",
			"FULL CREDITS IN THIRD_PARTY_NOTICES.MD"
		]
	],
]

var _back: PixelButton


func open(m: MainInput) -> void:
	super.open(m)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clear_buttons()
	_back = add_button(Menu.BACK, "back", Callable(), back)
	_back.call_deferred("grab_when_shown")


func _gui_input(event: InputEvent) -> void:
	# A tap anywhere on a touch screen goes back, as it always did.
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if main.input_device == "touch":
			back()


func picked() -> PixelButton:
	return _back


func back() -> bool:
	main.back_to_title()
	return true


func draw_back(c: Canvas) -> void:
	main.menu.draw_sheet(c, "CREDITS")
	for i in BLOCKS.size():
		var block: Array = BLOCKS[i]
		var y := 44 + i * 41
		HUD.text(c, str(block[0]), 25, y, "body", HUD.AMBER)
		var lines: Array = block[1]
		for j in lines.size():
			HUD.text(c, str(lines[j]), 25, y + 13 + j * 10, "body", HUD.INK)
	Menu.plate_button(c, Menu.BACK, "BACK", _back.is_hovered())
