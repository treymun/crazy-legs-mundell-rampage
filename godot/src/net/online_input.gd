## Taps, clicks and the pointer on the multiplayer screens (LobbyScreens
## draws them and notes where each tap lands, `LobbyScreens.zones`), the
## MULTIPLAYER and ALL SETTINGS keys, and the phone's keyboard for the name,
## code and password fields. A tap does what the key for it does
## (main.key), so the keys stay the one place each screen's rules live.
class_name OnlineInput
extends RefCounted

## The screens whose taps are read here.
const SCREENS := ["multi", "showdown", "servers", "nethost", "netjoin", "lobby", "lobbyset"]
## The screens with a field to type in (the phone's keyboard may be up).
const TYPED := ["nethost", "netjoin", "servers"]

static var keyboard_up := false


## The phone's (or a touch browser's) keyboard up with `text` in it, or down.
static func keyboard(show: bool, text := "") -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return
	if show:
		DisplayServer.virtual_keyboard_show(text)
		keyboard_up = true
	elif keyboard_up:
		DisplayServer.virtual_keyboard_hide()
		keyboard_up = false


## The keyboard goes away when its screen does (main.gd, every frame).
static func settle(main) -> void:
	if keyboard_up and not TYPED.has(String(main.state)):
		keyboard(false)


# ------------------------------------------------------------------ taps


## A tap or left click at `at` (the 320x200 picture's own pixels).
static func tap(main, at: Vector2i) -> void:
	var hit := LobbyScreens.zone_at(at)
	if hit.is_empty():
		return
	var id := String(hit[0])
	var arg := int(hit[1])
	keyboard(false)
	if id == "back":
		main.key(KEY_ESCAPE)
		return
	match String(main.state):
		"multi":
			LobbyScreens.hub_row = arg
			main.key(KEY_ENTER)
		"showdown":
			_tap_picker(main, id, arg)
		"servers":
			_tap_servers(main, id, arg)
		"nethost", "netjoin":
			main.net_row = arg
			var rows: Array = (
				LobbyScreens.HOST_FORM if main.state == "nethost" else LobbyScreens.JOIN_FORM
			)
			var row: Array = rows[clampi(arg, 0, rows.size() - 1)]
			if String(row[2]) == "go":
				main.key(KEY_ENTER)
			else:
				keyboard(true, String(main.net_form.get(String(row[0]), "")))
		"lobby":
			_tap_lobby(main, id)
		"lobbyset":
			if id == "left" or id == "right":
				main.key(KEY_LEFT if id == "left" else KEY_RIGHT)
			elif LobbyScreens.all_row == arg:
				main.key(KEY_RIGHT)
			else:
				LobbyScreens.all_row = arg
				main.sound.play("menu_move")


static func _tap_picker(main, id: String, arg: int) -> void:
	if id == "go":
		main.showdown_row = TacticalScreens.PICKER_GO
		main.key(KEY_ENTER)
	elif id == "left" or id == "right":
		main.showdown_row = arg
		main.key(KEY_LEFT if id == "left" else KEY_RIGHT)
	elif int(main.showdown_row) == arg:
		main.key(KEY_RIGHT)  # a tap on the picked row: its next value
	else:
		main.showdown_row = arg
		main.sound.play("menu_move")


static func _tap_servers(main, id: String, arg: int) -> void:
	var b: NetBrowser = main.browser
	if b == null:
		return
	if id == "name":
		b.row = 0
		keyboard(true, b.name)
	elif id == "server":
		b.row = arg + 1
		main.key(KEY_ENTER)
	elif id == "refresh":
		b.row = maxi(1, b.row)
		main.key(KEY_R)


static func _tap_lobby(main, id: String) -> void:
	var list := LobbyScreens.rows(main.net)
	if id == "kick_left" or id == "kick_right":
		main.lobby_row = list.find("kick")
		main.key(KEY_LEFT if id == "kick_left" else KEY_RIGHT)
		return
	var i := list.find(id)
	if i < 0:
		return
	var was := posmod(int(main.lobby_row), list.size())
	main.lobby_row = i
	if was == i or id in ["team", "ready", "kick", "start", "more"]:
		main.key(KEY_ENTER)
	else:
		main.sound.play("menu_move")


## The pointer over a row picks it (no action until a click).
static func hover(main, at: Vector2i) -> void:
	var hit := LobbyScreens.zone_at(at)
	if hit.is_empty():
		return
	var id := String(hit[0])
	var arg := int(hit[1])
	var moved := false
	match String(main.state):
		"multi":
			moved = id == "row" and LobbyScreens.hub_row != arg
			if moved:
				LobbyScreens.hub_row = arg
		"showdown":
			moved = id in ["row", "left", "right", "go"] and int(main.showdown_row) != arg
			if moved:
				main.showdown_row = arg
		"servers":
			var b: NetBrowser = main.browser
			moved = b != null and id == "server" and b.row != arg + 1
			if moved:
				b.row = arg + 1
		"nethost", "netjoin":
			moved = id == "row" and int(main.net_row) != arg
			if moved:
				main.net_row = arg
		"lobby":
			var i := LobbyScreens.rows(main.net).find(id)
			moved = i >= 0 and int(main.lobby_row) != i
			if moved:
				main.lobby_row = i
		"lobbyset":
			moved = id == "row" and LobbyScreens.all_row != arg
			if moved:
				LobbyScreens.all_row = arg
	if moved:
		main.sound.play("menu_move")


# ------------------------------------------------------------------ keys


## MULTIPLAYER: up and down pick, ENTER goes, ESC back to the title.
static func key_hub(main, code: int) -> void:
	var n := LobbyScreens.HUB.size()
	if code == KEY_ESCAPE:
		main.back_to_title()
	elif code in [KEY_UP, KEY_W, KEY_DOWN, KEY_S]:
		var step := -1 if code in [KEY_UP, KEY_W] else 1
		LobbyScreens.hub_row = posmod(LobbyScreens.hub_row + step, n)
		main.sound.play("menu_move")
	elif code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		match String(LobbyScreens.HUB[posmod(LobbyScreens.hub_row, n)][0]):
			"servers":
				main.open_servers()
			"bots":
				main.state = "showdown"
				main.showdown_row = 0
				main.sound.play("menu_accept")
			"host":
				main.open_net_form(true)
			"join":
				main.open_net_form(false)


## ALL SETTINGS: up and down pick, left and right (ENTER: the next value)
## change it for whoever runs the lobby, ESC back to the lobby.
static func key_all(main, code: int) -> void:
	var net: NetPlay = main.net
	var n := LobbyScreens.ALL_KEYS.size()
	if code == KEY_ESCAPE or net == null:
		main.state = "lobby" if net != null else "multi"
		main.net_note = ""
		main.sound.play("menu_back")
		return
	if code in [KEY_UP, KEY_W, KEY_DOWN, KEY_S]:
		var step := -1 if code in [KEY_UP, KEY_W] else 1
		LobbyScreens.all_row = posmod(LobbyScreens.all_row + step, n)
		main.sound.play("menu_move")
		return
	var change := 0
	if code in [KEY_LEFT, KEY_A]:
		change = -1
	elif code in [KEY_RIGHT, KEY_D, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		change = 1
	if change == 0:
		return
	if not net.is_admin():
		main.sound.play("empty")
		return
	var key := String(LobbyScreens.ALL_KEYS[posmod(LobbyScreens.all_row, n)])
	net.set_setting(key, LobbyScreens.stepped(key, net.settings.get(key), change))
	main.sound.play("menu_move")
