## The online screens (src/net/net_play.gd is what they show): the HOST
## ONLINE and JOIN ONLINE forms, the lobby (both teams, the host's settings,
## the join code and how friends get in) and what goes over a match (the
## ping, waiting for the host, leaving). The keys are main_input.gd's
## (_key_online); these only draw, and list the rows the cursor walks.
class_name LobbyScreens
extends RefCounted

## The forms' rows: key, label, kind ("text", "secret", "digits", "toggle",
## "go").
const HOST_FORM := [
	["name", "YOUR NAME", "text"],
	["lobby_name", "LOBBY NAME", "text"],
	["password", "PASSWORD", "secret"],
	["port", "PORT", "digits"],
	["router", "ASK THE ROUTER", "toggle"],
	["go", "OPEN THE LOBBY", "go"],
]
const JOIN_FORM := [
	["name", "YOUR NAME", "text"],
	["address", "CODE OR ADDRESS", "text"],
	["password", "PASSWORD", "secret"],
	["go", "JOIN", "go"],
]
const FIELD_MOST := 21
## The lobby's settings in its two columns.
const LEFT_KEYS := [
	"mode", "map", "store_rules", "rounds", "team_size", "bots", "bot_skill", "friendly_fire"
]
const RIGHT_KEYS := [
	"round_seconds",
	"buy_seconds",
	"freeze_seconds",
	"start_money",
	"max_players",
	"late_join",
	"pick_teams",
	"chatter"
]
const RED := Color8(214, 86, 64)
const GREEN := Color8(132, 206, 96)


## A form's field as typed (password as dots, the caret on the row being typed).
static func field_text(row: Array, form: Dictionary, here: bool, blink: bool) -> String:
	var key := String(row[0])
	var kind := String(row[2])
	if kind == "toggle":
		return "YES (UPNP)" if bool(form.get(key, true)) else "NO"
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
		var y := 48 + i * 17
		var here := i == posmod(at, rows.size())
		if here:
			c.fill_rect(19, y - 2, 282, 14, Canvas.rgb(82, 49, 31))
			Menu.shell(c, 22, y + 2)
		var ink := HUD.AMBER if here else HUD.INK
		if String(row[2]) == "go":
			HUD.text(c, String(row[1]), 160, y - 2, "heading", ink, true)
			continue
		HUD.text(c, String(row[1]), 36, y + 1, "body", Menu.FADED)
		c.fill_rect(134, y - 1, 160, 11, Canvas.rgb(30, 20, 14))
		HUD.text(c, field_text(row, form, here, blink), 138, y + 1, "body", ink)
	var y2 := 152
	if note != "":
		HUD.text(c, note, 160, y2, "mini", HUD.AMBER, true)
		y2 += 8
	for line: String in help:
		HUD.text(c, line, 160, y2, "mini", HUD.DIM, true)
		y2 += 7
	HUD.text(c, "TYPE   ENTER NEXT   ESC BACK", 160, 186, "mini", HUD.INK, true)


static func draw_host_form(
	c: Canvas, menu: Menu, form: Dictionary, at: int, note: String, clock: float
) -> void:
	draw_form(
		c,
		menu,
		"HOST ONLINE",
		HOST_FORM,
		form,
		at,
		note,
		[
			"FRIENDS ON OTHER NETWORKS NEED THE PORT OPEN (UDP).",
			"THE ROUTER IS ASKED FOR YOU; IF IT SAYS NO, FORWARD",
			"THE PORT OR ALL JOIN THE SAME VPN (TAILSCALE, ZEROTIER).",
		],
		clock
	)


static func draw_join_form(
	c: Canvas, menu: Menu, form: Dictionary, at: int, note: String, clock: float
) -> void:
	draw_form(
		c,
		menu,
		"JOIN ONLINE",
		JOIN_FORM,
		form,
		at,
		note,
		[
			"THE HOST'S JOIN CODE (ABCDE-12345) OR ADDRESS,",
			"LIKE 203.0.113.7 OR 203.0.113.7:47197. CTRL+V PASTES.",
		],
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
		return
	var at := browser.row
	var blink := fmod(clock, .8) < .5
	var here := at == 0
	if here:
		c.fill_rect(19, 38, 282, 14, Canvas.rgb(82, 49, 31))
		Menu.shell(c, 22, 42)
	HUD.text(c, "YOUR NAME", 36, 41, "body", Menu.FADED)
	c.fill_rect(134, 39, 160, 11, Canvas.rgb(30, 20, 14))
	var shown := browser.name + ("_" if here and blink else "")
	HUD.text(c, shown, 138, 41, "body", HUD.AMBER if here else HUD.INK)
	var list: Array = browser.servers
	if list.is_empty():
		HUD.text(c, "NO SERVERS LISTED", 160, 90, "body", HUD.DIM, true)
	for i in list.size():
		var s: Dictionary = list[i]
		var y := 62 + i * 30
		var picked := at == i + 1
		if picked:
			c.fill_rect(19, y - 3, 282, 27, Canvas.rgb(82, 49, 31))
			Menu.shell(c, 22, y + 2)
		var info: Dictionary = s["info"]
		var title := String(info.get("lobby_name", s["name"]))
		HUD.text(c, title, 36, y, "body", HUD.AMBER if picked else HUD.INK)
		var state := String(s["state"])
		var line := "ASKING..."
		var ink := HUD.DIM
		if state == "silent":
			line = "NOT ANSWERING"
			ink = RED
		elif state == "up":
			var count := "%d/%d" % [int(info.get("players", 0)), int(info.get("max_players", 10))]
			HUD.text(c, count, 296, y, "body", HUD.AMBER if picked else HUD.INK, false, true, true)
			var doing := "MATCH ON" if String(info.get("phase", "")) == "match" else "IN THE LOBBY"
			line = (
				"%s  %s   %s   %d MS"
				% [
					value_name("mode", info.get("mode")),
					value_name("map", info.get("map")),
					doing,
					roundi(float(s["ping"]))
				]
			)
			ink = GREEN if browser.why_not_join(i) == "" else HUD.AMBER
		HUD.text(c, line, 36, y + 11, "mini", ink)
	var y2 := 62 + list.size() * 30 + 4
	if note != "":
		HUD.text(c, note, 160, y2, "mini", HUD.AMBER, true)
	HUD.text(
		c,
		"ALWAYS OPEN. THE FIRST ONE IN RUNS IT: MODE, MAP, START.",
		160,
		172,
		"mini",
		HUD.DIM,
		true
	)
	var keys := "ENTER JOINS   TYPE YOUR NAME   R ASKS AGAIN   ESC BACK"
	HUD.text(c, keys, 160, 186, "mini", HUD.INK, true)


# ------------------------------------------------------------------ the lobby


## The rows the lobby's cursor walks: the settings and actions of whoever
## runs the lobby (the host, an always-open lobby's admin), or a player's
## team and ready.
static func rows(net: NetPlay) -> Array:
	if net == null or not net.is_admin():
		return ["team", "ready"]
	return ["team"] + LEFT_KEYS + RIGHT_KEYS + ["kick", "start"]


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


## The line telling the host how friends get in.
static func reach_lines(net: NetPlay) -> Array:
	if net.role != NetPlay.Role.HOST:
		var second := ""
		if bool(net.settings.get("dedicated", false)):
			second = (
				"ALWAYS-OPEN LOBBY.  YOU RUN IT: ARROWS SET, ENTER STARTS"
				if net.is_admin()
				else "ALWAYS-OPEN LOBBY.  %s RUNS IT" % admin_name(net)
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
		return
	if net.phase == "connecting" or net.phase == "hello":
		HUD.text(c, "KNOCKING ON THE HOST'S DOOR...", 160, 90, "body", HUD.AMBER, true)
		HUD.text(c, net.address.to_upper(), 160, 104, "mini", HUD.INK, true)
		HUD.text(c, "ESC GIVES UP", 160, 186, "mini", HUD.INK, true)
		return
	var s := net.settings
	var title := String(s.get("lobby_name", "LOBBY"))
	if bool(s.get("locked", false)) or String(s.get("password", "")) != "":
		title += "  (PASSWORD)"
	HUD.text(c, title, 160, 33, "body", HUD.AMBER, true)
	var reach := reach_lines(net)
	HUD.text(c, String(reach[0]), 160, 43, "mini", HUD.INK, true)
	HUD.text(c, String(reach[1]), 160, 50, "mini", HUD.DIM, true)
	_teams(c, net)
	var list := rows(net)
	var cursor := String(list[posmod(at, list.size())])
	var host := net.is_admin()
	for col in 2:
		var keys: Array = LEFT_KEYS if col == 0 else RIGHT_KEYS
		var x0 := 22 + col * 142
		for i in keys.size():
			var key := String(keys[i])
			var y := 110 + i * 8
			var here := host and key == cursor
			if here:
				c.fill_rect(x0 - 3, y - 1, 140, 7, Canvas.rgb(82, 49, 31))
			var row := setting_row(key)
			HUD.text(c, String(row[1]), x0, y, "mini", Menu.FADED)
			var shown := value_name(key, s.get(key))
			HUD.text(
				c,
				("<%s>" % shown) if here else shown,
				x0 + 134,
				y,
				"mini",
				HUD.AMBER if here else HUD.INK,
				false,
				true,
				true
			)
	_actions(c, net, cursor, kick_at, armed)
	var hint := "LEFT/RIGHT TEAM   ENTER READY   ESC LEAVES"
	if net.role == NetPlay.Role.HOST:
		hint = "ARROWS SET   ENTER STARTS   ESC CLOSES THE LOBBY"
	elif host:
		hint = "ARROWS SET   ENTER STARTS   ESC LEAVES"
	HUD.text(
		c,
		note if note != "" else hint,
		160,
		188,
		"mini",
		HUD.AMBER if note != "" else HUD.INK,
		true
	)


## Both teams as the match would line them up (a player who did not pick goes
## where the host's balance puts them, marked ?).
static func _teams(c: Canvas, net: NetPlay) -> void:
	var size := int(net.settings.get("team_size", 5))
	var shown := [0, 0]
	for t in 2:
		var x := 82 + t * 156
		var ink := Color8(232, 160, 96) if t == 0 else Color8(126, 196, 120)
		HUD.text(c, "%s  (%dV%d)" % [NetPlay.TEAM_NAMES[t], size, size], x, 58, "body", ink, true)
	for p: Dictionary in net.players:
		var side := int(p.get("side", p.get("team", 0)))
		side = clampi(side, 0, 1)
		var y := 68 + int(shown[side]) * 7
		shown[side] += 1
		if int(shown[side]) > 5:
			continue
		var x := 22 + side * 156
		var me := int(p["id"]) == net.my_id
		var label := String(p["name"])
		if int(p.get("team", -1)) < 0:
			label += " ?"
		if int(p["id"]) == NetSession.HOST_ID:
			label += "  (HOST)"
		elif int(p["id"]) == net.admin_of():
			label += "  (ADMIN)"
		HUD.text(c, label, x, y, "mini", HUD.AMBER if me else HUD.INK)
		var ready := bool(p.get("ready", false))
		HUD.text(
			c,
			"READY" if ready else "...",
			x + 118,
			y,
			"mini",
			GREEN if ready else HUD.DIM,
			false,
			true,
			true
		)
	for t in 2:
		var extra := int(shown[t]) - 5
		if extra > 0:
			HUD.text(c, "+%d MORE" % extra, 22 + t * 156, 103, "mini", HUD.DIM)
	if bool(net.settings.get("bots", true)):
		for t in 2:
			var bots := size - mini(int(shown[t]), size)
			if bots > 0 and int(shown[t]) < 5:
				var y := 68 + int(shown[t]) * 7
				HUD.text(
					c,
					"+ %d BOT%s" % [bots, "" if bots == 1 else "S"],
					22 + t * 156,
					y,
					"mini",
					HUD.DIM
				)


static func _actions(c: Canvas, net: NetPlay, cursor: String, kick_at: int, armed: bool) -> void:
	var y := 172
	var me := net.player_of(net.my_id)
	var team := int(me.get("team", -1))
	var team_name := "ANY" if team < 0 else String(NetPlay.TEAM_NAMES[team])
	if not bool(net.settings.get("pick_teams", true)):
		team_name = "HOST BALANCES"
	_action(c, "TEAM <%s>" % team_name, 22, y, cursor == "team")
	if net.is_admin():
		var rest := others(net)
		var who := "NOBODY"
		if not rest.is_empty():
			who = String(rest[posmod(kick_at, rest.size())]["name"])
		_action(
			c,
			("ENTER AGAIN: KICK %s" % who) if armed else "KICK <%s>" % who,
			128,
			y,
			cursor == "kick"
		)
		var why := net.why_not_start()
		_action(c, "START!" if why == "" else "START", 252, y, cursor == "start", why != "")
		if cursor == "start" and why != "":
			HUD.text(c, why, 160, 180, "mini", RED, true)
	else:
		var ready := bool(me.get("ready", false))
		_action(c, "READY: %s" % ("YES" if ready else "NO"), 190, y, cursor == "ready")


static func _action(c: Canvas, label: String, x: int, y: int, here: bool, dim := false) -> void:
	if here:
		var w := PixelType.text_width(label, "body") + 6
		c.fill_rect(x - 3, y - 2, w, 11, Canvas.rgb(82, 49, 31))
	HUD.text(c, label, x, y, "body", HUD.AMBER if here else (HUD.DIM if dim else HUD.INK))


# ------------------------------------------------------------------ a match


## Over a match: waiting for the host, the ping, asking to leave.
static func draw_match(c: Canvas, net: NetPlay, game, leave_asked: bool) -> void:
	if net.role == NetPlay.Role.CLIENT:
		if not net.client_ready():
			c.fill_rect(60, 84, 200, 24, Canvas.rgb(20, 13, 9))
			HUD.text(c, "WAITING FOR THE HOST...", 160, 92, "body", HUD.AMBER, true)
		else:
			var ping := roundi(net.ping_ms())
			var ink := GREEN if ping < 80 else (HUD.AMBER if ping < 160 else RED)
			HUD.text(c, "%d MS" % ping, 316, 10, "mini", ink, false, true, true)
	if game != null and game.showing_tally:
		var line := (
			"ENTER: EVERYONE BACK TO THE LOBBY"
			if net.is_admin()
			else "WAITING FOR THE HOST TO CALL EVERYONE BACK"
		)
		var back := net.back_in()
		if back >= 0:
			line = "BACK TO THE LOBBY IN %d" % back
			if net.is_admin():
				line += "   ENTER: NOW"
		HUD.text(c, line, 160, 181, "body", HUD.AMBER, true)
	if leave_asked:
		c.fill_rect(50, 78, 220, 34, Canvas.rgb(20, 13, 9))
		var what := (
			"CLOSE THE LOBBY FOR EVERYONE?" if net.role == NetPlay.Role.HOST else "LEAVE THE MATCH?"
		)
		HUD.text(c, what, 160, 84, "body", HUD.AMBER, true)
		HUD.text(c, "ENTER YES   ESC NO", 160, 98, "mini", HUD.INK, true)
