## Typing on a phone in the browser build. Godot's own web keyboard is off
## (export_presets.cfg: it is experimental, and it hands the text only to a
## LineEdit, which the game's fields are not; an iPhone opens no keyboard
## from a frame's code either). So a finger's tap on a field asks the browser
## for the text (its own little box, with the phone's keyboard) and the
## answer is typed into the field as keys: every field keeps its own rules
## (which letters, how long), as if a keyboard had typed it. Android and the
## desktop keep the keyboard they have.
class_name WebTyping
extends RefCounted


## Whether a tap on a field should ask the browser: the browser build, and
## the last input a finger (a mouse click means there is a keyboard).
static func wanted(main: MainState) -> bool:
	return OS.has_feature("web") and main.input_device == "touch"


## Ask for `title`'s text, `current` filled in, and type the answer over
## `current`; `finish` presses ENTER after it (ESC when the box was
## cancelled). False when this is not the way here (wanted()).
static func ask(main: MainState, title: String, current: String, finish := false) -> bool:
	if not wanted(main):
		return false
	var code := "prompt(%s, %s)" % [JSON.stringify(title), JSON.stringify(current)]
	var answer: Variant = JavaScriptBridge.eval(code, true)
	if answer is String:
		type_over(current, str(answer), finish)
	elif finish:
		_press(KEY_ESCAPE, 0)
	return true


## Type `text` in place of `current` as key presses (BACKSPACE for each of
## `current`'s letters, then a press per letter), ENTER after when `finish`.
static func type_over(current: String, text: String, finish := false) -> void:
	for i in current.length():
		_press(KEY_BACKSPACE, 0)
	for i in text.length():
		var ch := text.unicode_at(i)
		if ch >= 32 and ch < 127:
			_press(KEY_NONE, ch)
	if finish:
		_press(KEY_ENTER, 0)


static func _press(code: Key, unicode: int) -> void:
	for down: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = code
		key.physical_keycode = code
		key.unicode = unicode
		key.pressed = down
		Input.parse_input_event(key)
