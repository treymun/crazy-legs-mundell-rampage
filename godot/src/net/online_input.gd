## Taps, clicks and the pointer on the multiplayer screens (LobbyScreens
## draws them and notes where each tap lands, `LobbyScreens.zones`), their
## keys (key_online(), which main_input.gd's key() asks first: the HOST and
## JOIN forms and what is typed in them, the servers list, the lobby, the
## MULTIPLAYER and ALL SETTINGS pages, and a match's own keys online), and the
## phone's keyboard for the name, code and password fields. A tap does what
## the key for it does (main.key), so the keys stay the one place each
## screen's rules live.
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
static func settle(main: MainInput) -> void:
	if keyboard_up and not TYPED.has(main.state):
		keyboard(false)


# ------------------------------------------------------------------ taps


## A tap or left click at `at` (the 320x200 picture's own pixels).
static func tap(main: MainInput, at: Vector2i) -> void:
	var hit := LobbyScreens.zone_at(at)
	if hit.is_empty():
		return
	var id := str(hit[0])
	var arg: int = hit[1]
	keyboard(false)
	if id == "back":
		main.key(KEY_ESCAPE)
		return
	match main.state:
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
			if str(row[2]) == "go":
				main.key(KEY_ENTER)
			else:
				keyboard(true, str(main.net_form.get(str(row[0]), "")))
		"lobby":
			_tap_lobby(main, id, arg)
		"lobbyset":
			# A click on a setting (or its >) is its next value, < the last.
			LobbyScreens.all_row = arg
			if main.net != null and main.net.is_admin():
				main.key(KEY_LEFT if id == "dec" else KEY_RIGHT)
			else:
				main.sound.play("menu_move")


static func _tap_picker(main: MainInput, id: String, arg: int) -> void:
	if id == "go":
		main.showdown_row = TacticalScreens.PICKER_GO
		main.key(KEY_ENTER)
	elif id == "left" or id == "right":
		main.showdown_row = arg
		main.key(KEY_LEFT if id == "left" else KEY_RIGHT)
	else:
		main.showdown_row = arg
		main.key(KEY_RIGHT)  # a click on a row: its next value


static func _tap_servers(main: MainInput, id: String, arg: int) -> void:
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


static func _tap_lobby(main: MainInput, id: String, arg: int) -> void:
	if id == "copy":
		main.key(KEY_C)
		return
	var list := LobbyScreens.rows(main.net)
	if id == "kick_left" or id == "kick_right":
		main.lobby_row = list.find("kick")
		main.key(KEY_LEFT if id == "kick_left" else KEY_RIGHT)
		return
	var i := list.find(id)
	if i < 0:
		return
	main.lobby_row = i
	if LobbyScreens.LOBBY_KEYS.has(id):
		# A setting: a click is its next value, its < the last.
		main.key(KEY_LEFT if arg < 0 else KEY_RIGHT)
	else:
		main.key(KEY_ENTER)


## The pointer over a row picks it (no action until a click).
static func hover(main: MainInput, at: Vector2i) -> void:
	var hit := LobbyScreens.zone_at(at)
	if hit.is_empty():
		return
	var id := str(hit[0])
	var arg: int = hit[1]
	var moved := false
	match main.state:
		"multi":
			moved = id == "row" and LobbyScreens.hub_row != arg
			if moved:
				LobbyScreens.hub_row = arg
		"showdown":
			moved = id in ["row", "left", "right", "go"] and main.showdown_row != arg
			if moved:
				main.showdown_row = arg
		"servers":
			var b: NetBrowser = main.browser
			moved = b != null and id == "server" and b.row != arg + 1
			if moved:
				b.row = arg + 1
		"nethost", "netjoin":
			moved = id == "row" and main.net_row != arg
			if moved:
				main.net_row = arg
		"lobby":
			var i := LobbyScreens.rows(main.net).find(id)
			moved = i >= 0 and main.lobby_row != i
			if moved:
				main.lobby_row = i
		"lobbyset":
			moved = id in ["row", "dec", "inc"] and LobbyScreens.all_row != arg
			if moved:
				LobbyScreens.all_row = arg
	if moved:
		main.sound.play("menu_move")


# ------------------------------------------------------------------ keys


## MULTIPLAYER: up and down pick, ENTER goes, ESC back to the title.
static func key_hub(main: MainInput, code: int) -> void:
	var n := LobbyScreens.HUB.size()
	if code == KEY_ESCAPE:
		main.back_to_title()
	elif code in [KEY_UP, KEY_W, KEY_DOWN, KEY_S]:
		var step := -1 if code in [KEY_UP, KEY_W] else 1
		LobbyScreens.hub_row = posmod(LobbyScreens.hub_row + step, n)
		main.sound.play("menu_move")
	elif code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		match str(LobbyScreens.HUB[posmod(LobbyScreens.hub_row, n)][0]):
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
static func key_all(main: MainInput, code: int) -> void:
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
	var key := str(LobbyScreens.ALL_KEYS[posmod(LobbyScreens.all_row, n)])
	var current: Variant = net.settings.get(key)
	var next_value: Variant = LobbyScreens.stepped(key, current, change)
	net.set_setting(key, next_value)
	main.sound.play("menu_move")


## The online screens' keys, and a match's online (no saving or pausing: ESC
## asks to leave; on the results the host's ENTER calls everyone back to the
## lobby). True when the key was theirs.
static func key_online(main: MainInput, code: int) -> bool:
	if main.state == "nethost" or main.state == "netjoin":
		key_net_form(main, code)
		return true
	if main.state == "servers":
		key_servers(main, code)
		return true
	if main.state == "multi":
		key_hub(main, code)
		return true
	if main.state == "lobbyset":
		key_all(main, code)
		return true
	if main.state == "lobby":
		key_lobby(main, code)
		return true
	if main.net == null or main.state != "play":
		return false
	var enter := code == KEY_ENTER or code == KEY_KP_ENTER
	if code in [KEY_F2, KEY_F3, KEY_F5, KEY_F6, KEY_F9]:
		main.notice("NO SAVING ONLINE.")
		return true
	if main.net_leave:
		if enter:
			main.net_quit()
		elif code == KEY_ESCAPE:
			main.net_leave = false
		return true
	if main.game != null and main.game.showing_tally:
		if enter or code == KEY_SPACE:
			if main.net.is_admin():
				main.net.back_to_lobby()
			return true
		if code == KEY_ESCAPE:
			main.net_leave = true
			return true
		return false
	if code == KEY_ESCAPE and not TacticalScreens.open:
		main.net_leave = true
		return true
	return false


## The COUNTY SERVERS list: up and down pick, ENTER joins, R asks again,
## ESC goes back; typing writes your name (row 0).
static func key_servers(main: MainInput, code: int) -> void:
	if code == KEY_ESCAPE or main.browser == null:
		main.close_servers()
		main.state = "multi"
		main.sound.play("menu_back")
		return
	var count := 1 + main.browser.servers.size()
	var accept := code == KEY_ENTER or code == KEY_KP_ENTER
	if code in [KEY_UP, KEY_DOWN, KEY_TAB]:
		main.browser.row = posmod(main.browser.row + (-1 if code == KEY_UP else 1), count)
		main.sound.play("menu_move")
	elif code == KEY_BACKSPACE and main.browser.row == 0:
		main.browser.name = main.browser.name.substr(0, maxi(0, main.browser.name.length() - 1))
	elif code == KEY_R and main.browser.row != 0:
		main.browser.refresh()
		main.net_note = "ASKING THE SERVERS..."
	elif accept and main.browser.row == 0:
		main.browser.row = mini(1, count - 1)
		main.sound.play("menu_move")
	elif accept:
		main.join_server(main.browser.row - 1)


## A letter of your name typed on the servers list (row 0). True when taken.
static func server_type(main: MainInput, event: InputEventKey) -> bool:
	if main.browser == null or main.browser.row != 0:
		return false
	if event.ctrl_pressed and event.keycode == KEY_V:
		main.browser.name += DisplayServer.clipboard_get().strip_edges()
	elif not event.ctrl_pressed and event.unicode >= 32 and event.unicode < 127:
		main.browser.name += String.chr(event.unicode)
	else:
		return false
	main.browser.name = main.browser.name.substr(0, NetPlay.MAX_NAME)
	main.net_note = ""
	return true


static func net_form_rows(main: MainInput) -> Array:
	return LobbyScreens.HOST_FORM if main.state == "nethost" else LobbyScreens.JOIN_FORM


## A character typed into the form's field (CTRL+V pastes). True when taken.
static func net_type(main: MainInput, event: InputEventKey) -> bool:
	var rows := net_form_rows(main)
	var row: Array = rows[posmod(main.net_row, rows.size())]
	var kind := str(row[2])
	if kind != "text" and kind != "secret" and kind != "digits":
		return false
	var field := str(row[0])
	var value := str(main.net_form.get(field, ""))
	if event.ctrl_pressed and event.keycode == KEY_V:
		value += DisplayServer.clipboard_get().strip_edges()
	elif not event.ctrl_pressed and event.unicode >= 32 and event.unicode < 127:
		var ch := String.chr(event.unicode)
		if kind == "digits" and not ch.is_valid_int():
			return true
		value += ch
	else:
		return false
	var most := 40 if field == "address" else (5 if kind == "digits" else 22)
	main.net_form[field] = value.substr(0, most)
	main.net_note = ""
	return true


static func key_net_form(main: MainInput, code: int) -> void:
	var rows := net_form_rows(main)
	var row: Array = rows[posmod(main.net_row, rows.size())]
	var kind := str(row[2])
	var field := str(row[0])
	var accept := code == KEY_ENTER or code == KEY_KP_ENTER
	if code == KEY_ESCAPE:
		main.state = "multi"
		main.net_note = ""
		main.sound.play("menu_back")
	elif code == KEY_UP or code == KEY_DOWN or code == KEY_TAB:
		var step := -1 if code == KEY_UP else 1
		if (
			main.key_echo
			and (
				(
					(posmod(main.net_row + step, rows.size()) - posmod(main.net_row, rows.size()))
					* step
				)
				< 0
			)
		):
			return
		main.net_row = posmod(main.net_row + step, rows.size())
		main.sound.play("menu_move")
	elif code == KEY_BACKSPACE and kind in ["text", "secret", "digits"]:
		var value := str(main.net_form.get(field, ""))
		main.net_form[field] = value.substr(0, maxi(0, value.length() - 1))
	elif kind == "toggle" and (accept or code in [KEY_LEFT, KEY_RIGHT, KEY_SPACE]):
		var was_on: bool = main.net_form.get(field, true)
		main.net_form[field] = not was_on
		main.sound.play("menu_move")
	elif accept and kind == "go":
		if main.state == "nethost":
			main.net_open_lobby()
		else:
			main.net_join()
	elif accept:
		main.net_row = posmod(main.net_row + 1, rows.size())
		main.sound.play("menu_move")


static func key_lobby(main: MainInput, code: int) -> void:
	if main.net == null:
		main.state = "title"
		return
	if main.net.phase == "connecting" or main.net.phase == "hello":
		if code == KEY_ESCAPE:
			main.net_quit()
		return
	var list := LobbyScreens.rows(main.net)
	var row := str(list[posmod(main.lobby_row, list.size())])
	var host := main.net.role == NetPlay.Role.HOST
	var accept := code == KEY_ENTER or code == KEY_KP_ENTER or code == KEY_SPACE
	if not (accept and row == "kick"):
		main.net_kick_armed = false
	main.net_note = ""
	if code == KEY_ESCAPE:
		main.net_quit()
		main.sound.play("menu_back")
	elif code == KEY_C and host:
		var lines := LobbyScreens.reach_lines(main.net)
		var at := str(lines[0]).find("JOIN CODE ")
		var link := main.net.party_line()
		if link != null and link.state == "open":
			DisplayServer.clipboard_set(link.code)
			main.net_note = "PARTY LINE CODE COPIED. SEND IT TO YOUR FRIENDS."
		elif at >= 0:
			DisplayServer.clipboard_set(str(lines[0]).substr(at + 10, 11))
			main.net_note = "JOIN CODE COPIED. SEND IT TO YOUR FRIENDS."
		else:
			main.net_note = "NO JOIN CODE YET: " + str(lines[0])
	elif code in [KEY_UP, KEY_DOWN, KEY_W, KEY_S]:
		var step := -1 if code == KEY_UP or code == KEY_W else 1
		main.lobby_row = posmod(main.lobby_row + step, list.size())
		main.sound.play("menu_move")
	elif accept or code in [KEY_LEFT, KEY_RIGHT, KEY_A, KEY_D]:
		var step := -1 if code == KEY_LEFT or code == KEY_A else 1
		lobby_change(main, row, step, accept)


static func lobby_change(main: MainInput, row: String, step: int, accept: bool) -> void:
	var me := main.net.player_of(main.net.my_id)
	var host := main.net.role == NetPlay.Role.HOST
	match row:
		"team":
			var pick_teams: bool = main.net.settings.get("pick_teams", true)
			if not pick_teams:
				main.net_note = "THE HOST BALANCES THE TEAMS."
				return
			var my_team: int = me.get("team", -1)
			var team := posmod(my_team + 1 + step, 3) - 1
			if host:
				me["team"] = team
				main.net.send_lobby()
			else:
				main.net.ask({"team": team})
		"ready":
			var is_ready: bool = me.get("ready", false)
			main.net.ask({"ready": not is_ready})
		"kick":
			var others := LobbyScreens.others(main.net)
			if others.is_empty():
				return
			if not accept:
				main.net_kick = posmod(main.net_kick + step, others.size())
			elif main.net_kick_armed:
				var kick_id: int = others[posmod(main.net_kick, others.size())]["id"]
				main.net.kick(kick_id)
				main.net_kick_armed = false
			else:
				main.net_kick_armed = true
		"more":
			if accept:
				LobbyScreens.all_row = 0
				main.state = "lobbyset"
		"start":
			if not accept:
				return
			var why := main.net.start_match()
			if why != "":
				main.net_note = why
				main.sound.play("empty")
				return
		_:
			if main.net.is_admin():
				main.net.set_setting(
					row, LobbyScreens.stepped(row, main.net.settings.get(row), step)
				)
	main.sound.play("menu_move")
