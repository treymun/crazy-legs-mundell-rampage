## Online 5v5: hosting a lobby, joining one, and the match between them
## (docs/online.md). The packets are net_wire.gd's; the match itself is
## NetSync's (the host plays the one real game, each client a copy).
##
## The host opens a lobby on a port (UPnP asks the router to open it,
## net_upnp.gd), friends join by address or join code with a name (and the
## password when there is one), pick a team and say ready; the host sets the
## lobby (name, password, room, late joining, teams) and the match (mode,
## map, length, team size, bots, their skill, friendly fire, round, buy and
## freeze time, starting cash) and starts it. Everyone gets START with their
## slot; at the end the host takes everyone BACK to the lobby. A player who
## leaves during a match is played on by a bot; with LATE JOIN on a newcomer
## takes over a bot's place.
##
## Nothing here draws or reads keys: the front end (main.gd, lobby_screens.gd)
## and tools/net_showdown_check.gd drive it alike:
##   var net := NetPlay.host_lobby(port, name, lobby)   # or NetPlay.join_lobby(...)
##   net.make_match = func(info) -> Game: ...           # a fresh game for START
##   each frame: net.poll(now_ms)
##   each tick:  host: net.host_tick({slot: controls, ...})  client: net.client_input(c)
##   each frame (client): net.client_play(frame_ticks)
class_name NetPlay
extends RefCounted

enum Role { NONE, HOST, CLIENT }

## The host's snapshots: every this many ticks (30 a second).
const SNAP_EVERY := 2
## Seconds a client is given to say HELLO, and to reach a host.
const HELLO_WAIT := 6.0
const CONNECT_WAIT := 12.0
## Ticks a client's copy plays behind the newest snapshot (smooth motion).
const PLAYOUT_BEHIND := 2
const MAX_NAME := 12
## Milliseconds a leaving side keeps the line up for its BYE to arrive.
const CLOSE_GRACE := 400.0
## Where the last name, address and lobby are remembered (never by a tool).
const REMEMBER := "user://online.json"

## The lobby's settings: key, label, values, what each value is called.
const LOBBY_ROWS := [
	["max_players", "ROOM FOR", [2, 4, 6, 8, 10], ["2", "4", "6", "8", "10"]],
	["late_join", "LATE JOIN", [true, false], ["ON", "OFF"]],
	["pick_teams", "TEAMS", [true, false], ["PLAYERS PICK", "HOST BALANCES"]],
]
const MATCH_ROWS := [
	["mode", "MODE", ["bomb", "hostage"], ["SEARCH AND DESTROY", "HOSTAGE RESCUE"]],
	["map", "MAP", ["grainyard", "holler", "salvage"], ["GRAIN CO-OP", "DISTILLERY", "SALVAGE"]],
	["rounds", "ROUNDS TO WIN", [3, 4, 5, 7, 10], ["3", "4", "5", "7", "10"]],
	["team_size", "TEAM SIZE", [1, 2, 3, 4, 5], ["1V1", "2V2", "3V3", "4V4", "5V5"]],
	["bots", "BOTS FILL", [true, false], ["ON", "OFF"]],
	["bot_skill", "BOT SKILL", [0, 1, 2, 3], ["EASY", "NORMAL", "HARD", "HOG WILD"]],
	["friendly_fire", "FRIENDLY FIRE", [false, true], ["OFF", "ON"]],
	[
		"round_seconds",
		"ROUND TIME",
		[0.0, 60.0, 90.0, 120.0, 150.0, 180.0],
		["MODE'S", "1:00", "1:30", "2:00", "2:30", "3:00"]
	],
	["buy_seconds", "BUY TIME", [10.0, 20.0, 30.0, 45.0], ["10 S", "20 S", "30 S", "45 S"]],
	["freeze_seconds", "FREEZE TIME", [3.0, 6.0, 10.0, 15.0], ["3 S", "6 S", "10 S", "15 S"]],
	[
		"start_money",
		"START CASH",
		[800, 1600, 4000, 10000, 16000],
		["800", "1600", "4000", "10000", "16000"]
	],
]
const DEFAULTS := {
	"lobby_name": "MUNDELL'S LOBBY",
	"password": "",
	"max_players": 10,
	"late_join": true,
	"pick_teams": true,
	"mode": "bomb",
	"map": "grainyard",
	"rounds": 7,
	"team_size": 5,
	"bots": true,
	"bot_skill": 1,
	"friendly_fire": false,
	"round_seconds": 0.0,
	"buy_seconds": 20.0,
	"freeze_seconds": 6.0,
	"start_money": 800,
}
const TEAM_NAMES := ["HOGS", "GATORS"]

var role := Role.NONE
var session: NetSession = null
## "connecting", "lobby", "match", "closed"
var phase := "connecting"
## Why it closed (shown on the title), or a refusal.
var reason := ""
var settings := DEFAULTS.duplicate()
## Everyone in the lobby, the host first: {id, name, team (-1 any), ready, slot}.
var players: Array = []
var my_id := 0
var port := NetSession.PORT
var address := ""
## What START said (level, mode, count, options, slot of each id).
var match_info := {}
var host_sync: NetSync.Host = null
var client_sync: NetSync.Client = null
## Makes the game a match is played on: info -> Game (the front end's).
var make_match: Callable
## The host's settings that change play (difficulty, gore...): every copy of
## the match is configured with them (START's "sim").
var sim_options := {}
## Lines for the front end to show ("BUBBA JOINED"), taken by take_news().
var news: PackedStringArray = []
## Set when a match began, went back to the lobby or a bot took over a slot,
## for the front end to act on (take_changes()).
var changes: Array = []
var upnp: NetUpnp = null
var _now := 0.0
var _opened_at := 0.0
var _waiting_hello := {}
var _my_name := ""
var _password := ""
var _closing_at := -1.0

# ------------------------------------------------------------------ opening


## A lobby hosted on `at_port` (null: the port is taken). `lobby` overrides
## DEFAULTS (lobby_name, password, ...). `open_router` asks for UPnP.
static func host_lobby(
	at_port: int, my_name: String, lobby := {}, open_router := true, bind := "*"
) -> NetPlay:
	var s := NetSession.host(at_port, NetSession.Transport.ENET, Modes.MAX_PLAYERS - 1, bind)
	if s == null:
		return null
	var net := NetPlay.new()
	net.role = Role.HOST
	net.session = s
	net.port = at_port
	net.my_id = NetSession.HOST_ID
	net.phase = "lobby"
	net.settings.merge(lobby, true)
	net.players.append(
		{"id": NetSession.HOST_ID, "name": clean_name(my_name), "team": -1, "ready": true}
	)
	if open_router:
		net.upnp = NetUpnp.new()
		net.upnp.open(at_port)
	return net


## Joining the lobby at `where` (an address, address:port or a join code).
## null when the address cannot even be tried.
static func join_lobby(where: String, my_name: String, password := "") -> NetPlay:
	var target := parse_address(where)
	if target.is_empty():
		return null
	var s := NetSession.join(String(target["host"]), int(target["port"]))
	if s == null:
		return null
	var net := NetPlay.new()
	net.role = Role.CLIENT
	net.session = s
	net.address = String(target["host"])
	net.port = int(target["port"])
	net.phase = "connecting"
	net._my_name = clean_name(my_name)
	net.settings.erase("password")
	net._password = password
	net._opened_at = -1.0
	return net


static func clean_name(text: String, most := MAX_NAME) -> String:
	var out := ""
	for ch in text.to_upper().strip_edges():
		var c := ch.unicode_at(0)
		if c >= 32 and c < 127 and out.length() < most:
			out += ch
	return out if out != "" else "PLAYER"


## Leaves: tells the others, and closes the session (after CLOSE_GRACE, so
## the BYE gets there first: keep calling poll(), or finish() to close now)
## and the router's port.
func leave(why := "LEFT") -> void:
	if session != null and _closing_at < 0.0:
		if role == Role.HOST:
			session.send(0, NetSession.CH_RELIABLE, NetWire.message(NetWire.BYE, {"why": why}))
		else:
			session.send(
				NetSession.HOST_ID, NetSession.CH_RELIABLE, NetWire.message(NetWire.BYE, {})
			)
		session.poll(_now)
		_closing_at = _now + CLOSE_GRACE
	host_sync = null
	client_sync = null
	if phase != "closed":
		phase = "closed"
		if reason == "":
			reason = why


## Waits (a moment at most) for the goodbye to go out, then closes: the
## program is quitting.
func flush_leave() -> void:
	var began := Time.get_ticks_msec()
	var from := _now
	while session != null and Time.get_ticks_msec() - began < CLOSE_GRACE:
		poll(from + float(Time.get_ticks_msec() - began))
		OS.delay_msec(10)
	finish()


## Closes at once.
func finish() -> void:
	if session != null:
		session.close()
	session = null
	if upnp != null:
		upnp.close()
		upnp = null


## Gone for good (closed, and the BYE had its time)?
func finished() -> bool:
	return session == null


# ------------------------------------------------------------------ polling


## Reads what came in and answers it; call every frame (lobby and match).
func poll(now_ms: float) -> void:
	_now = now_ms
	if session == null:
		return
	if _closing_at >= 0.0:
		session.poll(now_ms)
		if now_ms >= _closing_at:
			finish()
		return
	if role == Role.CLIENT and phase == "connecting":
		_connecting()
	var packets := session.poll(now_ms)
	var events := session.take_events()
	if role == Role.HOST:
		for id: int in events[0]:
			_waiting_hello[id] = now_ms
		for id: int in events[1]:
			_gone(id)
		for id in _waiting_hello.keys():
			if now_ms - float(_waiting_hello[id]) > HELLO_WAIT * 1000.0:
				_waiting_hello.erase(id)
				_drop(id, "SAID NOTHING")
	var inputs: Array = []
	var snaps: Array = []
	for packet: Array in packets:
		var bytes: PackedByteArray = packet[1]
		if bytes.is_empty():
			continue
		var kind := bytes[0]
		if kind == NetWire.INPUTS:
			inputs.append(packet)
		elif kind == NetWire.SNAP:
			snaps.append(packet)
		elif role == Role.HOST:
			_host_message(int(packet[0]), kind, NetWire.info_of(bytes))
		else:
			_client_message(kind, NetWire.info_of(bytes))
		if session == null:
			return
	if host_sync != null and not inputs.is_empty():
		host_sync.take(inputs)
	if client_sync != null and not snaps.is_empty():
		client_sync.take(snaps, now_ms)
	# After the packets: a BYE that came with the hang-up says why.
	if role == Role.CLIENT and phase not in ["connecting", "closed"] and not session.connected():
		_close("LOST THE HOST")


func _connecting() -> void:
	if _opened_at < 0.0:
		_opened_at = _now
	if session.connected():
		phase = "hello"
		var version := String(ProjectSettings.get_setting("application/config/version", ""))
		session.send(
			NetSession.HOST_ID,
			NetSession.CH_RELIABLE,
			NetWire.hello(version, {"name": _my_name, "password": _password})
		)
	elif _now - _opened_at > CONNECT_WAIT * 1000.0:
		_close("COULD NOT REACH THE HOST")


func _close(why: String) -> void:
	reason = why
	phase = "closed"
	host_sync = null
	client_sync = null
	finish()


func take_news() -> PackedStringArray:
	var out := news
	news = PackedStringArray()
	return out


func take_changes() -> Array:
	var out := changes
	changes = []
	return out


# ------------------------------------------------------------------ the host


func _host_message(from: int, kind: int, info: Dictionary) -> void:
	match kind:
		NetWire.HELLO:
			_hello(from, info)
		NetWire.ASK:
			var p := player_of(from)
			if p.is_empty():
				return
			if info.has("name"):
				var was := String(p["name"])
				p["name"] = unique_name(clean_name(String(info["name"])), from)
				if was != p["name"]:
					news.append("%s IS NOW %s" % [was, p["name"]])
			if info.has("team") and bool(settings["pick_teams"]):
				p["team"] = clampi(int(info["team"]), -1, 1)
			if info.has("ready"):
				p["ready"] = bool(info["ready"])
			send_lobby()
		NetWire.BYE:
			_gone(from)
			session.drop(from)


func _hello(from: int, info: Dictionary) -> void:
	_waiting_hello.erase(from)
	if not player_of(from).is_empty():
		return
	var version := String(ProjectSettings.get_setting("application/config/version", ""))
	var refused := ""
	if int(info.get("protocol", 0)) != NetWire.PROTOCOL:
		refused = "THE HOST RUNS ANOTHER VERSION (%s)" % version
	elif String(info.get("version", "")) != version:
		refused = "THE HOST RUNS %s, YOU RUN %s" % [version, String(info.get("version", "?"))]
	elif (
		String(settings["password"]) != ""
		and String(info.get("password", "")) != String(settings["password"])
	):
		refused = "WRONG PASSWORD"
	elif players.size() >= int(settings["max_players"]):
		refused = "THE LOBBY IS FULL"
	elif phase == "match" and (not bool(settings["late_join"]) or _bot_slot_for() < 0):
		refused = (
			"A MATCH IS UNDER WAY" + ("" if bool(settings["late_join"]) else " (NO LATE JOIN)")
		)
	if refused != "":
		session.send(from, NetSession.CH_RELIABLE, NetWire.welcome({"refused": refused}))
		session.poll(_now)
		_drop_later(from)
		return
	var name := unique_name(clean_name(String(info.get("name", "PLAYER"))), from)
	var p := {"id": from, "name": name, "team": -1, "ready": false}
	players.append(p)
	news.append("%s JOINED" % name)
	session.send(
		from,
		NetSession.CH_RELIABLE,
		NetWire.welcome({"id": from, "lobby": lobby_info(), "phase": phase})
	)
	if phase == "match":
		_seat_late(p)
	send_lobby()


## A name nobody else in the lobby has (a number added).
func unique_name(name: String, id: int) -> String:
	var out := name
	var n := 2
	while players.any(func(q: Dictionary) -> bool: return q["id"] != id and q["name"] == out):
		out = "%s%d" % [name.substr(0, MAX_NAME - 1), n]
		n += 1
	return out


func _gone(id: int) -> void:
	var p := player_of(id)
	_waiting_hello.erase(id)
	if p.is_empty() or id == NetSession.HOST_ID:
		return
	players.erase(p)
	news.append("%s LEFT" % p["name"])
	if phase == "match" and host_sync != null:
		host_sync.drop_remote(id)
		if p.has("slot"):
			changes.append({"bot": int(p["slot"]), "name": String(p["name"])})
	send_lobby()


func _drop(id: int, _why: String) -> void:
	if session != null:
		session.drop(id)
	_gone(id)


## A refused client is let go once its refusal has had time to get there.
func _drop_later(id: int) -> void:
	Engine.get_main_loop().create_timer(1.0).timeout.connect(
		func() -> void:
			if session != null and player_of(id).is_empty():
				session.drop(id)
	)


func kick(id: int) -> void:
	if role != Role.HOST or id == NetSession.HOST_ID or player_of(id).is_empty():
		return
	session.send(
		id, NetSession.CH_RELIABLE, NetWire.message(NetWire.BYE, {"why": "THE HOST KICKED YOU"})
	)
	session.poll(_now)
	news.append("%s WAS KICKED" % player_of(id)["name"])
	_gone(id)
	_drop_later(id)


func player_of(id: int) -> Dictionary:
	for p: Dictionary in players:
		if int(p["id"]) == id:
			return p
	return {}


## What every lobby screen shows: the settings (no password) and the players.
func lobby_info() -> Dictionary:
	var shown := settings.duplicate()
	shown["locked"] = String(settings["password"]) != ""
	shown.erase("password")
	var list: Array = []
	var plan := team_plan()
	for p: Dictionary in players:
		p["side"] = int(plan[p["id"]])
		list.append(
			{
				"id": p["id"],
				"name": p["name"],
				"team": p["team"],
				"side": p["side"],
				"ready": p["ready"],
				"slot": p.get("slot", -1)
			}
		)
	return {"settings": shown, "players": list, "phase": phase}


func send_lobby() -> void:
	if role != Role.HOST or session == null:
		return
	session.send(0, NetSession.CH_RELIABLE, NetWire.message(NetWire.LOBBY, lobby_info()))


## A host setting changed (lobby_screens.gd): every lobby hears.
func set_setting(key: String, value) -> void:
	if role != Role.HOST:
		return
	settings[key] = value
	if key == "pick_teams" and not bool(value):
		for p: Dictionary in players:
			p["team"] = -1
	send_lobby()


## Is everyone ready and are the teams playable? "" when it can start.
func why_not_start() -> String:
	if role != Role.HOST or phase != "lobby":
		return "ONLY THE HOST STARTS"
	var size := int(settings["team_size"])
	var plan := team_plan()
	var count := [0, 0]
	for p: Dictionary in players:
		count[int(plan[p["id"]])] += 1
		if not bool(p["ready"]):
			return "WAITING ON %s" % p["name"]
	if count[0] > size or count[1] > size:
		return "TOO MANY ON A TEAM FOR %dV%d" % [size, size]
	if not bool(settings["bots"]) and (count[0] == 0 or count[1] == 0):
		return "BOTH TEAMS NEED A PLAYER (OR BOTS ON)"
	return ""


## id -> team for the match: picks kept, the rest to the smaller team.
func team_plan() -> Dictionary:
	var out := {}
	var count := [0, 0]
	for p: Dictionary in players:
		var t := int(p["team"])
		if t >= 0 and bool(settings["pick_teams"]):
			out[p["id"]] = t
			count[t] += 1
	for p: Dictionary in players:
		if not out.has(p["id"]):
			var t := 0 if count[0] <= count[1] else 1
			out[p["id"]] = t
			count[t] += 1
	return out


## Starts the match: slots, teams and names for everyone, the game made by
## make_match, START to each client. "" or why it could not.
func start_match() -> String:
	var why := why_not_start()
	if why != "":
		return why
	var size := int(settings["team_size"])
	var plan := team_plan()
	var teams: Array = []
	var names: Array = []
	var slot_of := {}
	# The host is slot 0 (the game's own player one), then the others.
	for p: Dictionary in players:
		slot_of[p["id"]] = teams.size()
		p["slot"] = teams.size()
		teams.append(int(plan[p["id"]]))
		names.append(String(p["name"]))
	if bool(settings["bots"]):
		for t in 2:
			while teams.count(t) < size:
				teams.append(t)
				names.append("")
	var info := {
		"level": String(settings["map"]),
		"mode": String(settings["mode"]),
		"count": teams.size(),
		"options": match_options(teams, names),
		"slots": slot_of,
		"sim": sim_options,
	}
	var game: Game = make_match.call(info)
	if game == null:
		return "THE MAP WOULD NOT LOAD"
	match_info = info
	host_sync = NetSync.Host.new(session, game, func() -> int: return -1, SNAP_EVERY)
	for p: Dictionary in players:
		p["ready"] = int(p["id"]) == NetSession.HOST_ID
		if int(p["id"]) != NetSession.HOST_ID:
			host_sync.add_remote(int(p["id"]), int(p["slot"]))
			_send_start(int(p["id"]), int(p["slot"]))
	phase = "match"
	changes.append({"started": true})
	send_lobby()
	return ""


func match_options(teams: Array, names: Array) -> Dictionary:
	var out := {
		"arena": String(settings["map"]),
		"rounds": int(settings["rounds"]),
		"teams": teams,
		"names": names,
	}
	for key: String in Modes.HOST_SETTINGS:
		if settings.has(key):
			out[key] = settings[key]
	return out


func _send_start(id: int, slot: int) -> void:
	var info := match_info.duplicate()
	info.erase("slots")
	info["slot"] = slot
	info["options"] = match_options(
		match_info["options"]["teams"], _names_now(match_info["options"]["names"])
	)
	session.send(id, NetSession.CH_RELIABLE, NetWire.message(NetWire.START, info))


func _names_now(names: Array) -> Array:
	var out := names.duplicate()
	if host_sync != null:
		for q: Player in host_sync.game.players:
			if q.slot < out.size():
				out[q.slot] = q.name
	return out


## A late joiner takes a bot's place on the team with fewer people.
func _seat_late(p: Dictionary) -> void:
	var slot := _bot_slot_for()
	if slot < 0:
		return
	p["slot"] = slot
	p["ready"] = true
	var q: Player = host_sync.game.players[slot]
	q.name = String(p["name"])
	host_sync.add_remote(int(p["id"]), slot)
	_send_start(int(p["id"]), slot)
	changes.append({"human": slot, "name": String(p["name"])})
	news.append("%s TAKES OVER FROM A BOT" % p["name"])


## The bot's slot a late joiner gets (-1: none): on the team with fewer people.
func _bot_slot_for() -> int:
	if host_sync == null:
		return -1
	var taken := {}
	var people := [0, 0]
	for p: Dictionary in players:
		if p.has("slot") and int(p["slot"]) >= 0:
			taken[int(p["slot"])] = true
			people[host_sync.game.players[int(p["slot"])].team] += 1
	var best := -1
	for q: Player in host_sync.game.players:
		if taken.has(q.slot):
			continue
		if best < 0 or people[q.team] < people[host_sync.game.players[best].team]:
			best = q.slot
	return best


## The slots no person plays (the host's front end runs a bot in each).
func bot_slots() -> Array:
	var out: Array = []
	if host_sync == null:
		return out
	var taken := {}
	for p: Dictionary in players:
		if p.has("slot"):
			taken[int(p["slot"])] = true
	for q: Player in host_sync.game.players:
		if not taken.has(q.slot):
			out.append(q.slot)
	return out


## One tick of the match: `own` holds the host's own player and the bots.
func host_tick(own: Dictionary) -> void:
	if host_sync != null:
		host_sync.play(own)


## Back to the lobby after a match (the host's ENTER on the results).
func back_to_lobby() -> void:
	if role != Role.HOST:
		return
	host_sync = null
	match_info = {}
	phase = "lobby"
	for p: Dictionary in players:
		p.erase("slot")
		p["ready"] = int(p["id"]) == NetSession.HOST_ID
	session.send(0, NetSession.CH_RELIABLE, NetWire.message(NetWire.BACK, {}))
	changes.append({"lobby": true})
	send_lobby()


# ------------------------------------------------------------------ a client


func _client_message(kind: int, info: Dictionary) -> void:
	match kind:
		NetWire.WELCOME:
			if info.has("refused"):
				_close(String(info["refused"]))
				return
			my_id = int(info.get("id", session.id()))
			phase = "lobby"
			_take_lobby(info.get("lobby", {}))
		NetWire.LOBBY:
			_take_lobby(info)
		NetWire.START:
			_start(info)
		NetWire.BACK:
			client_sync = null
			match_info = {}
			phase = "lobby"
			changes.append({"lobby": true})
		NetWire.BYE:
			_close(String(info.get("why", "THE HOST CLOSED THE LOBBY")))


func _take_lobby(info: Dictionary) -> void:
	if info.is_empty():
		return
	var shown: Dictionary = info.get("settings", {})
	settings.merge(shown, true)
	players = info.get("players", [])


## What this player wants (lobby_screens.gd): name, team, ready.
func ask(what: Dictionary) -> void:
	if role != Role.CLIENT or session == null:
		return
	session.send(NetSession.HOST_ID, NetSession.CH_RELIABLE, NetWire.message(NetWire.ASK, what))


func _start(info: Dictionary) -> void:
	match_info = info
	var game: Game = make_match.call(info)
	if game == null:
		_close("THE MAP WOULD NOT LOAD")
		return
	client_sync = NetSync.Client.new(session, func(_id: String) -> Game: return null)
	client_sync.slot = int(info["slot"])
	client_sync.level = String(info["level"])
	client_sync.game = game
	phase = "match"
	changes.append({"started": true})


## This tick's controls go to the host.
func client_input(c: Game.Controls) -> void:
	if client_sync != null:
		client_sync.send_input(c)


## Plays the copy on toward the host's newest snapshot: `ticks` (about a
## frame's worth), kept PLAYOUT_BEHIND behind it.
func client_play(ticks: int) -> void:
	if client_sync != null:
		# A tick more while it lags behind, so it never drifts away.
		var extra := 1 if client_sync.backlog() > PLAYOUT_BEHIND + 2 else 0
		client_sync.play_out(maxi(1, ticks) + extra, PLAYOUT_BEHIND)


## The client's copy has the host's game on it (a first snapshot came).
func client_ready() -> bool:
	return client_sync != null and client_sync.game_tick >= 0


## The game this machine shows during a match.
func match_game() -> Game:
	if host_sync != null:
		return host_sync.game
	if client_sync != null:
		return client_sync.game
	return null


## This machine's slot in the match (-1: none).
func my_slot() -> int:
	if role == Role.HOST:
		return 0 if host_sync != null else -1
	return client_sync.slot if client_sync != null else -1


## Round trip to the host in ms (a client; 0 the host).
func ping_ms() -> float:
	if role != Role.CLIENT or session == null or not (session.peer is ENetMultiplayerPeer):
		return 0.0
	var enet := session.peer as ENetMultiplayerPeer
	var p := enet.get_peer(NetSession.HOST_ID)
	return p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) if p != null else 0.0


# ------------------------------------------------------------------ addresses


## {host, port} from "1.2.3.4", "1.2.3.4:5000", "[::1]:5000", "name:5000" or
## a join code ("ABCDE-FGHIJ"); {} when it is none of them.
static func parse_address(text: String) -> Dictionary:
	var t := text.strip_edges()
	if t == "":
		return {}
	var code := from_code(t)
	if not code.is_empty():
		return code
	var port := NetSession.PORT
	var host := t
	if t.begins_with("["):
		var close := t.find("]")
		if close < 0:
			return {}
		host = t.substr(1, close - 1)
		var rest := t.substr(close + 1)
		if rest.begins_with(":"):
			port = rest.substr(1).to_int()
	elif t.count(":") == 1:
		host = t.get_slice(":", 0)
		port = t.get_slice(":", 1).to_int()
	if port <= 0 or port > 65535 or host == "" or host.contains(" "):
		return {}
	return {"host": host, "port": port}


const CODE_ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"


## A join code for an IPv4 address and port: ten letters and digits.
static func to_code(ipv4: String, at_port := NetSession.PORT) -> String:
	var parts := ipv4.split(".")
	if parts.size() != 4:
		return ""
	var n := 0
	for part in parts:
		n = (n << 8) | (part.to_int() & 255)
	n = (n << 16) | (at_port & 0xFFFF)
	var out := ""
	for i in 10:
		out = CODE_ALPHABET[n & 31] + out
		n >>= 5
	return out.substr(0, 5) + "-" + out.substr(5)


static func from_code(text: String) -> Dictionary:
	var t := text.to_upper().replace("-", "").replace(" ", "")
	t = t.replace("O", "0").replace("I", "1").replace("L", "1")
	if t.length() != 10:
		return {}
	var n := 0
	for ch in t:
		var v := CODE_ALPHABET.find(ch)
		if v < 0:
			return {}
		n = (n << 5) | v
	var at_port := n & 0xFFFF
	n >>= 16
	var ip := "%d.%d.%d.%d" % [(n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255]
	if at_port == 0:
		return {}
	return {"host": ip, "port": at_port}


## Private, shared (CGNAT) or loopback IPv4: not reachable from outside.
static func private_address(ip: String) -> bool:
	var parts := ip.split(".")
	if parts.size() != 4:
		return false
	var a := parts[0].to_int()
	var b := parts[1].to_int()
	return (
		a == 10
		or a == 127
		or (a == 172 and b >= 16 and b < 32)
		or (a == 192 and b == 168)
		or (a == 100 and b >= 64 and b < 128)
		or (a == 169 and b == 254)
	)


## This machine's own IPv4 addresses worth telling a friend: home network
## ones (LAN) and a VPN's (Tailscale's 100.64/10 and the like).
static func local_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for ip: String in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254."):
			out.append(ip)
	return out


# ------------------------------------------------------------------ remembering


static func remembered() -> Dictionary:
	if not FileAccess.file_exists(REMEMBER):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(REMEMBER))
	return parsed if parsed is Dictionary else {}


static func remember(values: Dictionary) -> void:
	var loop := Engine.get_main_loop()
	if loop != null and loop.get_script() != null:
		return  # a tool never writes the player's profile
	var all := remembered()
	all.merge(values, true)
	var f := FileAccess.open(REMEMBER, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(all))
