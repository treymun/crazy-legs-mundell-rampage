## The play controls as Godot input actions, each with a key the player can
## change (Settings, KEYS page) and the fixed extra keys it always had.
##
## register() fills the InputMap from the options: held controls are read with
## Input.is_action_pressed (main_input.gd _controls). A key press in play is
## handed on as the key its action has by default (translate), so the play
## key handler, the pad and the touch overlay keep speaking in default keys.
## The chosen keys are stored with the other settings as key_<action>.
class_name KeyBindings
extends RefCounted

## [action, label, default key, fixed extra keys]
const ACTIONS := [
	["forward", "MOVE FORWARD", KEY_W, [KEY_UP]],
	["back", "MOVE BACK", KEY_S, [KEY_DOWN]],
	["strafe_left", "STEP LEFT", KEY_A, []],
	["strafe_right", "STEP RIGHT", KEY_D, []],
	["turn_left", "TURN LEFT", KEY_LEFT, []],
	["turn_right", "TURN RIGHT", KEY_RIGHT, []],
	["run", "RUN", KEY_SHIFT, []],
	["strafe_mode", "TURN KEYS STEP", KEY_ALT, []],
	["fire_key", "FIRE (KEY)", KEY_CTRL, []],
	["jump", "JUMP", KEY_J, []],
	["crouch", "CROUCH", KEY_Z, []],
	["use", "USE", KEY_E, [KEY_SPACE]],
	["reload", "RELOAD", KEY_R, []],
	["prev_weapon", "PREVIOUS WEAPON", KEY_SEMICOLON, []],
	["next_weapon", "NEXT WEAPON", KEY_APOSTROPHE, []],
	["holster", "HOLSTER", KEY_H, [KEY_SCROLLLOCK]],
	["use_item", "USE ITEM", KEY_F, [KEY_ENTER, KEY_KP_ENTER]],
	["next_item", "NEXT ITEM", KEY_Q, []],
	["map", "MAP", KEY_TAB, []],
	["look_up", "LOOK UP", KEY_PAGEUP, []],
	["look_down", "LOOK DOWN", KEY_PAGEDOWN, []],
	["center_view", "CENTER VIEW", KEY_HOME, []],
	["turn_around", "TURN AROUND", KEY_BACKSPACE, []],
	["always_run", "ALWAYS RUN ON/OFF", KEY_CAPSLOCK, []],
	["whistle", "WHISTLE FOR BLUE", KEY_G, []],
	["flashlight", "FLASHLIGHT", KEY_L, []],
]

## What a key does where its label alone does not say (the KEYS page's help).
const HINTS := {
	"strafe_mode": "HOLD IT AND THE TURN KEYS STEP SIDEWAYS",
	"fire_key": "FIRES FROM THE KEYBOARD; THE LEFT MOUSE BUTTON ALWAYS FIRES",
	"holster": "PUTS THE GUN AWAY AND TAKES IT OUT AGAIN",
	"always_run": "FLIPS ALWAYS RUN ON AND OFF",
	"whistle": "AIMED AT A VARMINT: SIC 'EM. AT A PICKUP: FETCH. ELSE STAY/COME",
	"flashlight": "SWITCHES YOUR FLASHLIGHT WHEN THE POWER'S OUT",
}

## Bound key -> the default key of its action, for keys that differ.
static var _translate := {}
## Default keys whose action now has another key (they do nothing in play).
static var _freed := {}


static func option_key(action: String) -> String:
	return "key_" + action


## The KEYS page's help for `action` (labelled `label`): what it does, the
## keys it always has as well, and how to put them all back.
static func hint(action: String, label: String) -> String:
	var text: String = HINTS.get(action, "THE KEY FOR %s IN PLAY" % label)
	for entry: Array in ACTIONS:
		if entry[0] != action:
			continue
		var extra: Array = entry[3]
		var names: Array = extra.map(func(code: int) -> String: return key_name(code))
		if not names.is_empty():
			text += " (ALSO %s)" % " AND ".join(PackedStringArray(names))
	return text + ". RESET PAGE PUTS EVERY KEY BACK."


static func key_name(code: int) -> String:
	if code == KEY_NONE:
		return "-"
	return OS.get_keycode_string(code).to_upper()


## Fill the InputMap from the options (a missing key is the default).
static func register(options: Dictionary) -> void:
	_translate = {}
	_freed = {}
	var bound := {}
	for entry: Array in ACTIONS:
		var action: String = entry[0]
		var code := _int(options.get(option_key(action), entry[2]))
		bound[action] = code
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action, .2)
		var keys: Array = [code] + entry[3]
		for key_code: Variant in keys:
			if _int(key_code) == KEY_NONE:
				continue
			var event := InputEventKey.new()
			event.keycode = _int(key_code)
			if _int(key_code) == KEY_CTRL:
				# Only the left Ctrl fires, as before: the right one is free.
				event.location = KEY_LOCATION_LEFT
			InputMap.action_add_event(action, event)
		if code != _int(entry[2]):
			_translate[code] = _int(entry[2])
	for entry: Array in ACTIONS:
		var default_code := _int(entry[2])
		if _int(bound[entry[0]]) != default_code and not _translate.has(default_code):
			_freed[default_code] = true


## The key a play key handler should see for a key pressed in play.
static func translate(code: int) -> int:
	if _translate.has(code):
		return _int(_translate[code])
	if _freed.has(code):
		return KEY_NONE
	return code


static func held(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_pressed(action)


## Give `action` the key `code` in `options`; an action that had that key
## takes this one's old key, so no key does two things.
static func bind(options: Dictionary, action: String, code: int) -> void:
	var mine := option_key(action)
	var old := _int(options.get(mine, _default_of(action)))
	for entry: Array in ACTIONS:
		var other := option_key(str(entry[0]))
		if other != mine and _int(options.get(other, entry[2])) == code:
			options[other] = old
	options[mine] = code


## The key `action` has by default (KEY_NONE: no such action).
static func default_key(action: String) -> int:
	return _default_of(action)


static func _default_of(action: String) -> int:
	for entry: Array in ACTIONS:
		if entry[0] == action:
			return _int(entry[2])
	return KEY_NONE


## int() of a value read from data or a dictionary, typed (the same
## result for a number, a bool or a number written as text).
static func _int(v: Variant) -> int:
	return str(v).to_int() if v is String else v
