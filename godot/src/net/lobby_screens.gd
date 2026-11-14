## The multiplayer screens (src/net/net_play.gd is what most of them show):
## MULTIPLAYER (four big choices), the COUNTY SERVERS list, the HOST and JOIN
## forms, the lobby (both teams, its main settings, TEAM / READY / KICK /
## START) and its ALL SETTINGS page, and what goes over an online match (the
## ping, the results, leaving). The keys are main_input.gd's (_key_online);
## these only draw, list the rows the cursor walks, and note every place a
## tap or click lands (`zones`, read by main_input's _tap_menu), so what is
## drawn and what a finger hits are one and the same.
class_name LobbyScreens
extends RefCounted

## The forms' rows: key, label, kind ("text", "secret", "digits", "go").
const HOST_FORM := [
	["name", "YOUR NAME", "text"],
	["lobby_name", "LOBBY NAME", "text"],
	["password", "PASSWORD", "secret"],
	["port", "PORT", "digits"],
	["go", "OPEN THE LOBBY", "go"],
]
const JOIN_FORM := [
	["name", "YOUR NAME", "text"],
	["address", "CODE OR ADDRESS", "text"],
	["password", "PASSWORD", "secret"],
	["go", "JOIN", "go"],
]
const FIELD_MOST := 21
## MULTIPLAYER's choices: id, title, what it is.
const HUB := [
	["servers", "PLAY ONLINE", "THE COUNTY SERVERS. ALWAYS OPEN."],
	["bots", "PLAY VS BOTS", "YOU AND THE BOTS. NO INTERNET NEEDED."],
	["host", "HOST A GAME", "YOUR OWN LOBBY FOR FRIENDS."],
	["join", "JOIN WITH A CODE", "TYPE IN A FRIEND'S JOIN CODE."],
]
## The lobby's main settings (its own page), and every one (ALL SETTINGS).
const LOBBY_KEYS := ["mode", "map", "store_rules", "bots", "bot_skill"]
const ALL_KEYS := [
	"mode",
	"map",
	"store_rules",
	"rounds",
	"team_size",
	"bots",
	"bot_skill",
	"friendly_fire",
	"round_seconds",
	"buy_seconds",
	"freeze_seconds",
	"start_money",
	"max_players",
	"late_join",
	"pick_teams",
	"chatter",
]
## Rows ALL SETTINGS shows at once.
const ALL_SHOWN := 12
const RED := Color8(214, 86, 64)
const GREEN := Color8(132, 206, 96)
## Second lines on the sheets: brighter than HUD.DIM, so they read.
const SOFT := Color8(214, 188, 146)
const LIT := Color(82 / 255.0, 49 / 255.0, 31 / 255.0)
const PLAIN := Color(34 / 255.0, 23 / 255.0, 17 / 255.0)
const EDGE := Color(141 / 255.0, 102 / 255.0, 65 / 255.0)
const REFRESH := Rect2i(14, 177, 70, 13)
const STEP_DOWN := Rect2i(14, 177, 30, 13)
const STEP_UP := Rect2i(48, 177, 30, 13)

## Where a tap lands this frame: [rect, id, arg] in drawing order (the last
## one drawn on top). Cleared by main_state.gd render() each frame.
static var zones: Array = []
## MULTIPLAYER's and ALL SETTINGS' cursors.
static var hub_row := 0
static var all_row := 0

# ------------------------------------------------------------------ pieces


static func clear_zones() -> void:
	zones.clear()


static func zone(rect: Rect2i, id: String, arg := 0) -> void:
	zones.append([rect, id, arg])


## [id, arg] of what a tap at `p` hits ([] nothing).
static func zone_at(p: Vector2i) -> Array:
	for i in range(zones.size() - 1, -1, -1):
		if (zones[i][0] as Rect2i).has_point(p):
			return [zones[i][1], zones[i][2]]
	return []


static func box(c: Canvas, r: Rect2i, face: Color, edge := EDGE) -> void:
	c.fill_rect(r.position.x, r.position.y, r.size.x, r.size.y, face)
	c.fill_rect(r.position.x, r.position.y, r.size.x, 1, edge)
	c.fill_rect(r.position.x, r.end.y - 1, r.size.x, 1, edge)
	c.fill_rect(r.position.x, r.position.y, 1, r.size.y, edge)
	c.fill_rect(r.end.x - 1, r.position.y, 1, r.size.y, edge)


## A button with its label, noted as a place to tap.
static func button(
	c: Canvas, r: Rect2i, label: String, hot: bool, id: String, arg := 0, dim := false
) -> void:
	box(c, r, LIT if hot else PLAIN)
	var ink := HUD.AMBER if hot else (Menu.DIM if dim else HUD.INK)
	HUD.text(
		c, label, r.position.x + r.size.x / 2, r.position.y + (r.size.y - 7) / 2, "body", ink, true
	)
	zone(r, id, arg)


static func back_button(c: Canvas, label := "BACK") -> void:
	button(c, Menu.BACK, label, false, "back")


## The keys' hint, left of BACK.
static func footer(c: Canvas, text: String) -> void:
	HUD.text(c, text, 126, 181, "mini", HUD.INK, true)


static func _note(c: Canvas, text: String, y: int, ink := HUD.AMBER) -> void:
	if text != "":
		HUD.text(c, text, 160, y, "body", ink, true)


## The multiplayer screen `main` is on (main_state.gd render()); false when
## its state is none of them.
static func draw_screen(main) -> bool:
	var c: Canvas = main.canvas
	var menu: Menu = main.menu
	match String(main.state):
		"multi":
			draw_hub(c, menu, main.net_note)
		"nethost":
			draw_host_form(c, menu, main.net_form, main.net_row, main.net_note, main.menu_clock)
		"netjoin":
			draw_join_form(c, menu, main.net_form, main.net_row, main.net_note, main.menu_clock)
		"servers":
			draw_servers(c, menu, main.browser, main.net_note, main.menu_clock)
		"lobby":
			draw_lobby(
				c, menu, main.net, main.lobby_row, main.net_note, main.net_kick, main.net_kick_armed
			)
		"lobbyset":
			draw_all_settings(c, menu, main.net, main.net_note)
		_:
			return false
	return true


# ------------------------------------------------------------------ MULTIPLAYER


## MULTIPLAYER: four big choices.
static func draw_hub(c: Canvas, menu: Menu, note: String) -> void:
	menu.draw_sheet(c, "MULTIPLAYER")
	for i in HUB.size():
		var y := 38 + i * 33
		var r := Rect2i(19, y, 282, 30)
		var here := i == posmod(hub_row, HUB.size())
		box(c, r, LIT if here else PLAIN)
		if here:
			Menu.shell(c, 25, y + 11)
		HUD.text(c, String(HUB[i][1]), 160, y + 3, "heading", HUD.AMBER if here else HUD.INK, true)
		HUD.text(c, String(HUB[i][2]), 160, y + 20, "body", SOFT, true)
		zone(r, "row", i)
	_note(c, note, 171)
	footer(c, "ARROWS PICK   ENTER GOES   ESC BACK")
	back_button(c)


# ------------------------------------------------------------------ forms


## A form's field as typed (password as dots, the caret on the row being typed).
static func field_text(row: Array, form: Dictionary, here: bool, blink: bool) -> String:
	var key := String(row[0])
	var kind := String(row[2])
	var value := String(form.get(key, ""))
	if kind == "secret":
		value = ".".repeat(value.length()) if value != "" else ("NONE" if not here else "")
	value = value.to_upper()
	if value.length() > FIELD_MOST:
		value = value.right(FIELD_MOST)
	return value + ("_" if here and blink else "")


static func draw_form(
	c: Canvas,
	menu: Menu,
	heading: String,
	rows: Array,
	form: Dictionary,
	at: int,
	note: String,
	help: Array,
	clock: float
) -> void:
	menu.draw_sheet(c, heading)
	var blink := fmod(clock, .8) < .5
	for i in rows.size():
		var row: Array = rows[i]
		var y := 44 + i * 17
		var here := i == posmod(at, rows.size())
		if String(row[2]) == "go":
			button(c, Rect2i(70, y - 2, 180, 18), "", here, "row", i)
			HUD.text(c, String(row[1]), 160, y, "heading", HUD.AMBER if here else HUD.INK, true)
			continue
		if here:
			c.fill_rect(19, y - 2, 282, 14, LIT)
			Menu.shell(c, 22, y + 2)
		HUD.text(c, String(row[1]), 36, y + 1, "body", Menu.FADED)
		c.fill_rect(134, y - 1, 160, 11, Canvas.rgb(30, 20, 14))
		HUD.text(
			c,
			field_text(row, form, here, blink),
			138,
			y + 1,
			"body",
			HUD.AMBER if here else HUD.INK
		)
		zone(Rect2i(19, y - 2, 282, 15), "row", i)
	var y2 := 44 + rows.size() * 17 + 10
	_note(c, note, y2)
	for k in help.size():
		HUD.text(c, String(help[k]), 160, y2 + 12 + k * 9, "body", SOFT, true)
	footer(c, "TYPE   ENTER NEXT   ESC BACK")
	back_button(c)


static func draw_host_form(
	c: Canvas, menu: Menu, form: Dictionary, at: int, note: String, clock: float
) -> void:
	draw_form(
		c,
		menu,
		"HOST A GAME",
		HOST_FORM,
		form,
		at,
		note,
		[
			"FRIENDS ON OTHER NETWORKS NEED THE",
			"PORT OPEN (UDP). THE GAME ASKS YOUR",
			"ROUTER; IF IT WON'T, USE A VPN.",
		],
		clock
	)


static func draw_join_form(
	c: Canvas, menu: Menu, form: Dictionary, at: int, note: String, clock: float
) -> void:
	draw_form(
		c,
		menu,
		"JOIN WITH A CODE",
		JOIN_FORM,
		form,
		at,
		note,
		["YOUR FRIEND'S JOIN CODE (ABCDE-12345)", "OR ADDRESS. CTRL+V PASTES."],
		clock
	)


# ------------------------------------------------------------------ servers


## The COUNTY SERVERS list (net_browser.gd): your name, then each server live
## (row 0 the name, 1.. the servers).
static func draw_servers(
	c: Canvas, menu: Menu, browser: NetBrowser, note: String, clock: float
) -> void:
	menu.draw_sheet(c, "COUNTY SERVERS")
	if browser == null:
		back_button(c)
		return
	var at := browser.row
	var blink := fmod(clock, .8) < .5
	var here := at == 0
	if here:
		c.fill_rect(19, 38, 282, 14, LIT)
		Menu.shell(c, 22, 42)
	HUD.text(c, "YOUR NAME", 36, 41, "body", Menu.FADED)
	c.fill_rect(134, 39, 160, 11, Canvas.rgb(30, 20, 14))
	var shown := browser.name + ("_" if here and blink else "")
	HUD.text(c, shown, 138, 41, "body", HUD.AMBER if here else HUD.INK)
	zone(Rect2i(19, 37, 282, 16), "name")
	var list: Array = browser.servers
	if list.is_empty():
		HUD.text(c, "NO SERVERS HERE", 160, 90, "body", SOFT, true)
	for i in list.size():
		var s: Dictionary = list[i]
		var y := 60 + i * 34
		var r := Rect2i(19, y - 3, 282, 31)
		var picked := at == i + 1
		box(c, r, LIT if picked else PLAIN)
		if picked:
			Menu.shell(c, 23, y + 9)
		var info: Dictionary = s["info"]
		HUD.text(
			c,
			String(info.get("lobby_name", s["name"])),
			34,
			y,
			"body",
			HUD.AMBER if picked else HUD.INK
		)
		var state := String(s["state"])
		var what := "ASKING..."
		var how := ""
		var ink := SOFT
		if state == "silent":
			what = "NOT ANSWERING"
			ink = RED
		elif state == "up":
			var count := "%d/%d" % [int(info.get("players", 0)), int(info.get("max_players", 10))]
			HUD.text(c, count, 294, y, "body", HUD.AMBER if picked else HUD.INK, false, true, true)
			what = "%s - %s" % [_mode_name(info.get("mode")), _map_name(info.get("map"))]
			how = (
				"%s   %d MS"
				% [
					"MATCH ON" if String(info.get("phase", "")) == "match" else "IN THE LOBBY",
					roundi(float(s["ping"]))
				]
			)
			ink = GREEN if browser.why_not_join(i) == "" else HUD.AMBER
		HUD.text(c, what, 34, y + 10, "body", ink)
		HUD.text(c, how, 34, y + 19, "body", SOFT)
		zone(r, "server", i)
	_note(c, note, 60 + list.size() * 34 + 2)
	HUD.text(c, "THE FIRST ONE IN RUNS IT: MODE, MAP, START.", 160, 165, "body", SOFT, true)
	button(c, REFRESH, "REFRESH", false, "refresh")
	back_button(c)


static func _mode_name(id) -> String:
	return value_name("mode", id).replace("SEARCH AND DESTROY", "SEARCH & DESTROY")


static func _map_name(id) -> String:
	return value_name("map", id).trim_prefix("2V2 ")


# ------------------------------------------------------------------ the lobby


## The rows the lobby's cursor walks: whoever runs the lobby (the host, an
## always-open lobby's admin) sets the main settings, kicks and starts;
## everyone picks a team, readies up and can see ALL SETTINGS.
static func rows(net: NetPlay) -> Array:
	if net == null or not net.is_admin():
		return ["team", "ready", "more"]
	return ["team"] + LOBBY_KEYS + ["more", "kick", "start"]


## The others in the lobby (whom the kick row walks through).
static func others(net: NetPlay) -> Array:
	return net.players.filter(func(p: Dictionary) -> bool: return int(p["id"]) != net.my_id)


## The name of whoever runs the lobby ("" nobody).
static func admin_name(net: NetPlay) -> String:
	var p := net.player_of(net.admin_of())
	return String(p.get("name", ""))


static func setting_row(key: String) -> Array:
	for row: Array in NetPlay.MATCH_ROWS + NetPlay.LOBBY_ROWS:
		if String(row[0]) == key:
			return row
	return []


static func value_name(key: String, value) -> String:
	var row := setting_row(key)
	if row.is_empty():
		return str(value)
	var at := (row[2] as Array).find(value)
	if at < 0:
		for i in (row[2] as Array).size():
			if str(row[2][i]) == str(value):
				at = i
	return String(row[3][at]) if at >= 0 else str(value)


## The next (step 1) or last (-1) value of a setting.
static func stepped(key: String, value, step: int):
	var row := setting_row(key)
	if row.is_empty():
		return value
	var values: Array = row[2]
	var at := values.find(value)
	if at < 0:
		for i in values.size():
			if str(values[i]) == str(value):
				at = i
	return values[posmod(at + step, values.size())]


## The lines telling the host how friends get in (a client: where it is).
static func reach_lines(net: NetPlay) -> Array:
	if net.role != NetPlay.Role.HOST:
		var second := ""
		if bool(net.settings.get("dedicated", false)):
			second = (
				"ALWAYS-OPEN LOBBY. YOU RUN IT."
				if net.is_admin()
				else "ALWAYS-OPEN LOBBY. %s RUNS IT." % admin_name(net)
			)
		return [
			"CONNECTED TO %s   PING %d MS" % [net.address.to_upper(), roundi(net.ping_ms())], second
		]
	var lan := NetPlay.local_addresses()
	var at_home := ""
	for ip: String in lan:
		at_home += ("   " if at_home != "" else "") + ip
	var home := "SAME NETWORK OR VPN: %s" % (at_home if at_home != "" else "NONE FOUND")
	if net.port != NetSession.PORT:
		home += "  PORT %d" % net.port
	var up := net.upnp
	if up == null:
		return ["ROUTER NOT ASKED: FORWARD UDP %d FOR FRIENDS OUTSIDE" % net.port, home]
	match up.state:
		"asking":
			return ["ASKING THE ROUTER TO OPEN UDP %d..." % net.port, home]
		"open":
			if up.external == "":
				return ["ROUTER OPENED UDP %d (IT WOULD NOT SAY ITS ADDRESS)" % net.port, home]
			if up.shared_address():
				return ["YOUR PROVIDER SHARES ONE ADDRESS (CGNAT): USE A VPN", home]
			return [
				(
					"JOIN CODE %s   (%s)   C COPIES"
					% [NetPlay.to_code(up.external, net.port), up.external]
				),
				home
			]
	return ["ROUTER WON'T OPEN UDP %d: FORWARD IT OR USE A VPN" % net.port, home]


static func draw_lobby(
	c: Canvas, menu: Menu, net: NetPlay, at: int, note: String, kick_at: int, armed: bool
) -> void:
	menu.draw_sheet(c, "LOBBY")
	if net == null:
		back_button(c)
		return
	if net.phase == "connecting" or net.phase == "hello":
		HUD.text(c, "KNOCKING ON THE DOOR...", 160, 90, "body", HUD.AMBER, true)
		HUD.text(c, net.address.to_upper(), 160, 102, "body", SOFT, true)
		back_button(c, "GIVE UP")
		return
	var s := net.settings
	var title := String(s.get("lobby_name", "LOBBY"))
	if bool(s.get("locked", false)) or String(s.get("password", "")) != "":
		title += "  (PASSWORD)"
	HUD.text(c, title, 160, 32, "body", HUD.AMBER, true)
	var reach := reach_lines(net)
	HUD.text(c, String(reach[0]), 160, 42, "mini", HUD.INK, true)
	HUD.text(c, String(reach[1]), 160, 49, "mini", SOFT, true)
	_teams(c, net)
	var list := rows(net)
	var cursor := String(list[posmod(at, list.size())])
	_main_settings(c, net, cursor)
	_actions(c, net, cursor, kick_at, armed)
	var why := net.why_not_start() if net.is_admin() else ""
	if note != "":
		_note(c, note, 167)
	elif why != "":
		_note(c, why, 167, RED if cursor == "start" else SOFT)
	footer(c, "ARROWS PICK   ENTER CHANGES" if net.is_admin() else "ENTER: TEAM, READY")
	back_button(c, "CLOSE" if net.role == NetPlay.Role.HOST else "LEAVE")


## Both teams as the match would line them up (a player who did not pick goes
## where the host's balance puts them, marked ?).
static func _teams(c: Canvas, net: NetPlay) -> void:
	var size := int(net.settings.get("team_size", 5))
	var shown := [0, 0]
	for t in 2:
		var ink := Color8(232, 160, 96) if t == 0 else Color8(126, 196, 120)
		HUD.text(
			c, "%s  (%dV%d)" % [NetPlay.TEAM_NAMES[t], size, size], 22 + t * 144, 57, "body", ink
		)
	for p: Dictionary in net.players:
		var side := clampi(int(p.get("side", p.get("team", 0))), 0, 1)
		var row := int(shown[side])
		shown[side] += 1
		if row >= 5:
			continue
		var x := 22 + side * 144
		var y := 67 + row * 9
		var me := int(p["id"]) == net.my_id
		var label := String(p["name"]) + (" ?" if int(p.get("team", -1)) < 0 else "")
		var drawn := HUD.text(c, label, x, y, "body", HUD.AMBER if me else HUD.INK)
		var tag := ""
		var served := bool(net.settings.get("dedicated", net.dedicated))
		if int(p["id"]) == NetSession.HOST_ID and not served:
			tag = "HOST"
		elif served and int(p["id"]) == net.admin_of():
			tag = "ADMIN"
		if tag != "":
			HUD.text(c, tag, drawn.end.x + 4, y + 1, "mini", SOFT)
		var ready := bool(p.get("ready", false))
		HUD.text(
			c,
			"OK" if ready else "...",
			x + 130,
			y,
			"body",
			GREEN if ready else Menu.DIM,
			false,
			true,
			true
		)
	for t in 2:
		var x := 22 + t * 144
		var extra := int(shown[t]) - 5
		if extra > 0:
			HUD.text(c, "+%d MORE" % extra, x, 112, "mini", SOFT)
		elif bool(net.settings.get("bots", true)):
			var bots := size - mini(int(shown[t]), size)
			if bots > 0:
				var y := 67 + int(shown[t]) * 9
				HUD.text(c, "+ %d BOT%s" % [bots, "" if bots == 1 else "S"], x, y, "body", Menu.DIM)


## The lobby's main settings in two columns, MODE MAP RULES | BOTS SKILL.
static func _main_settings(c: Canvas, net: NetPlay, cursor: String) -> void:
	var admin := net.is_admin()
	for i in LOBBY_KEYS.size():
		var key := String(LOBBY_KEYS[i])
		var col := 0 if i < 3 else 1
		var x0 := 20 + col * 144
		var y := 120 + (i % 3) * 11
		var here := admin and key == cursor
		if here:
			c.fill_rect(x0 - 2, y - 2, 140, 11, LIT)
		var row := setting_row(key)
		var label := String(row[1]).replace("BOT SKILL", "SKILL").replace("BOTS FILL", "BOTS")
		HUD.text(c, label, x0, y, "body", Menu.FADED)
		var value := value_name(key, net.settings.get(key))
		if key == "map":
			value = _map_name(net.settings.get(key))
		elif key == "mode":
			value = _mode_name(net.settings.get(key))
		HUD.text(c, value, x0 + 136, y, "body", HUD.AMBER if here else HUD.INK, false, true, true)
		if admin:
			zone(Rect2i(x0 - 2, y - 2, 140, 11), key)
	button(c, Rect2i(162, 140, 140, 11), "ALL SETTINGS", cursor == "more", "more")


static func _actions(c: Canvas, net: NetPlay, cursor: String, kick_at: int, armed: bool) -> void:
	var y := 153
	var me := net.player_of(net.my_id)
	var team := int(me.get("team", -1))
	var team_name := "ANY" if team < 0 else String(NetPlay.TEAM_NAMES[team])
	if not bool(net.settings.get("pick_teams", true)):
		team_name = "BALANCED"
	button(c, Rect2i(14, y, 96, 12), "TEAM: %s" % team_name, cursor == "team", "team")
	if net.is_admin():
		var rest := others(net)
		var who := "NOBODY"
		if not rest.is_empty():
			who = String(rest[posmod(kick_at, rest.size())]["name"])
		var kick := ("SURE? KICK %s" % who) if armed else "KICK %s" % who
		button(c, Rect2i(114, y, 100, 12), kick, cursor == "kick", "kick", 0, rest.is_empty())
		if rest.size() > 1:
			# Who: the button's ends step through the others.
			HUD.text(c, "<", 117, y + 3, "mini", SOFT)
			HUD.text(c, ">", 208, y + 3, "mini", SOFT)
			zone(Rect2i(114, y, 14, 12), "kick_left")
			zone(Rect2i(200, y, 14, 12), "kick_right")
		var why := net.why_not_start()
		button(c, Rect2i(218, y, 88, 12), "START!", cursor == "start", "start", 0, why != "")
	else:
		var ready := bool(me.get("ready", false))
		button(
			c,
			Rect2i(114, y, 192, 12),
			"READY" if not ready else "READY - WAITING",
			cursor == "ready",
			"ready"
		)


## ALL SETTINGS: every match and lobby setting, a page of them at a time;
## whoever runs the lobby changes them (ENTER or a tap on the picked row: the
## next value; < and > step either way), everyone else only reads.
static func draw_all_settings(c: Canvas, menu: Menu, net: NetPlay, note: String) -> void:
	menu.draw_sheet(c, "LOBBY SETTINGS")
	if net == null:
		back_button(c)
		return
	var admin := net.is_admin()
	all_row = clampi(all_row, 0, ALL_KEYS.size() - 1)
	var first := clampi(all_row - ALL_SHOWN / 2, 0, ALL_KEYS.size() - ALL_SHOWN)
	for k in ALL_SHOWN:
		var i := first + k
		var key := String(ALL_KEYS[i])
		var y := 36 + k * 11
		var here := i == all_row
		if here:
			c.fill_rect(19, y - 2, 282, 11, LIT)
		var row := setting_row(key)
		HUD.text(c, String(row[1]), 30, y, "body", Menu.FADED)
		var value := value_name(key, net.settings.get(key))
		if here and admin:
			value = "<  %s  >" % value
		HUD.text(c, value, 294, y, "body", HUD.AMBER if here else HUD.INK, false, true, true)
		zone(Rect2i(19, y - 2, 282, 11), "row", i)
	if first > 0:
		HUD.text(c, "MORE ABOVE", 300, 30, "mini", SOFT, false, true, true)
	if first + ALL_SHOWN < ALL_KEYS.size():
		HUD.text(c, "MORE BELOW", 300, 167, "mini", SOFT, false, true, true)
	_note(
		c, note if note != "" else ("" if admin else "ONLY %s CHANGES THESE." % _runner(net)), 167
	)
	if admin:
		button(c, STEP_DOWN, "<", false, "left")
		button(c, STEP_UP, ">", false, "right")
	footer(c, "ARROWS CHANGE   ESC BACK" if admin else "ESC BACK")
	back_button(c, "DONE")


static func _runner(net: NetPlay) -> String:
	if bool(net.settings.get("dedicated", false)):
		var who := admin_name(net)
		return who if who != "" else "WHOEVER RUNS THE LOBBY"
	return "THE HOST"


# ------------------------------------------------------------------ a match


## Over a match: waiting for the host, the ping, the results, asking to leave.
static func draw_match(c: Canvas, net: NetPlay, game, leave_asked: bool) -> void:
	if net.role == NetPlay.Role.CLIENT:
		if not net.client_ready():
			c.fill_rect(60, 84, 200, 24, Canvas.rgb(20, 13, 9))
			HUD.text(c, "WAITING FOR THE SERVER...", 160, 92, "body", HUD.AMBER, true)
		else:
			var ping := roundi(net.ping_ms())
			var ink := GREEN if ping < 80 else (HUD.AMBER if ping < 160 else RED)
			HUD.text(c, "%d MS" % ping, 316, 10, "mini", ink, false, true, true)
	if game != null and game.showing_tally and not leave_asked:
		var back := net.back_in()
		var line := "WAITING TO GO BACK TO THE LOBBY"
		if back >= 0:
			line = "BACK TO THE LOBBY IN %d" % back
		if net.is_admin():
			button(c, Rect2i(60, 176, 200, 13), "EVERYONE BACK TO THE LOBBY", true, "lobby_now")
		else:
			HUD.text(c, line, 160, 181, "body", HUD.AMBER, true)
	if leave_asked:
		box(c, Rect2i(50, 74, 220, 44), Canvas.rgb(20, 13, 9))
		var what := (
			"CLOSE THE LOBBY FOR EVERYONE?" if net.role == NetPlay.Role.HOST else "LEAVE THE MATCH?"
		)
		HUD.text(c, what, 160, 80, "body", HUD.AMBER, true)
		button(c, Rect2i(62, 96, 92, 14), "YES (ENTER)", false, "yes")
		button(c, Rect2i(166, 96, 92, 14), "NO (ESC)", false, "no")
