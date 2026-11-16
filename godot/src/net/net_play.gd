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
## An ALWAYS-OPEN lobby (`serve_lobby`, run by lobby_server.gd on a server)
## has no host player: everyone in it is a client, the first one in is its
## ADMIN (settings, START, kick, calling everyone back, all through ASK: the
## admin's set_setting/start_match/kick/back_to_lobby send them), the next
## one in line when the admin leaves. Its matches go back to the lobby on
## their own BACK_AFTER seconds after the results come up, or at once when
## every person has left; an empty lobby goes back to its own settings.
##
## THE PARTY LINE (net_relay.gd, relay_link.gd): a host may also open a room
## on the relay in the lobby server (`party_line`), so friends join by its
## short code with no port opened (or straight to the host when its own port
## answers); the browser build hosts through it alone. join_lobby takes the
## code like an address.
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

## COUNTY RUN's feature (features/county_run.gd has no class_name).
const CountyRunScript := preload("res://src/features/county_run.gd")

## The host's snapshots: every this many ticks (30 a second).
const SNAP_EVERY := 2
## Seconds a client is given to say HELLO, and to reach a host.
const HELLO_WAIT := 6.0
const CONNECT_WAIT := 12.0
const MAX_NAME := 12
## Milliseconds a leaving side keeps the line up for its BYE to arrive.
const CLOSE_GRACE := 400.0
## Where the last name, address and lobby are remembered (never by a tool).
const REMEMBER := "user://online.json"
## Seconds an always-open lobby's results stay up before everyone is back.
const BACK_AFTER := 12.0
## Settings an always-open lobby's admin may not change.
const LOBBY_DATA := "res://data/tuning/lobby.cfg"
const SERVER_ONLY := ["lobby_name", "password", "admin", "dedicated", "locked"]

## The lobby's settings: key, label, values, what each value is called.
## The lobby's settings (data/tuning/lobby.cfg): key, label, values, what
## each value is called; MATCH_ROWS the match's own (the store rules' row is
## store.cfg's rules); DEFAULTS what a new lobby starts with.
static var LOBBY_ROWS: Array = Tuning.file(LOBBY_DATA).get_value("lobby", "lobby_rows", [])
static var MATCH_ROWS: Array = _match_rows()
static var DEFAULTS: Dictionary = Tuning.file(LOBBY_DATA).get_value("lobby", "defaults", {})
## Each mode's maps (lobby.cfg mode_maps): MAP steps through the mode's own.
static var MODE_MAPS: Dictionary = Tuning.file(LOBBY_DATA).get_value("lobby", "mode_maps", {})
const TEAM_NAMES := ["HOGS", "GATORS"]
## The party modes (campaign co-op, deathmatch, team deathmatch): people only,
## no bots, four at most; a newcomer joins a match under way (late joining)
## and someone leaving lies out of play (Modes.went_away).
const PARTY_MODES := [Modes.COOP, Modes.DEATHMATCH, Modes.TEAM]
## CAMPAIGN CO-OP's MAP that loads the host's online co-op save (main_flow).
const PARTY_SAVE := "party_save"

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
## An always-open lobby (no host player; this machine is the server).
var dedicated := false
## Who runs an always-open lobby (0: nobody in it).
var admin_id := 0
## An always-open lobby's own settings, put back when it empties.
var base_settings := {}
## An always-open lobby's server may say no to a START (too busy): "" or why.
var may_start: Callable
## When this match's results came up (ms, -1 not yet).
var tally_at := -1.0
## Lines an always-open lobby tells everyone with the next LOBBY.
var _told: PackedStringArray = []
var _now := 0.0
var _opened_at := 0.0
var _waiting_hello := {}
var _my_name := ""
var _password := ""
var _closing_at := -1.0
## What the party line was last told of the router (NEWS when it changes).
var _router_told := ""

# ------------------------------------------------------------------ opening


## A lobby hosted on `at_port` (null: the port is taken). `lobby` overrides
## DEFAULTS (lobby_name, password, ...). `open_router` asks for UPnP;
## `party_line` opens a room on the relay too (the browser build: only
## that, and null when no party line is known).
static func host_lobby(
	at_port: int,
	my_name: String,
	lobby := {},
	open_router := true,
	bind := "*",
	party_line := false
) -> NetPlay:
	var s: NetSession = null
	var web := OS.has_feature("web")
	if web and not party_line:
		return null  # a browser cannot listen
	if not web:
		s = NetSession.host(at_port, NetSession.Transport.ENET, Modes.MAX_PLAYERS - 1, bind)
		if s == null:
			return null
	var net := NetPlay.new()
	net.role = Role.HOST
	net.port = at_port
	net.my_id = NetSession.HOST_ID
	net.phase = "lobby"
	net.settings.merge(lobby, true)
	net.players.append(
		{"id": NetSession.HOST_ID, "name": clean_name(my_name), "team": -1, "ready": true}
	)
	if open_router and not web:
		net.upnp = NetUpnp.new()
		net.upnp.open(at_port)
	if party_line:
		var link := RelayLink.open_room(net.room_info(s != null))
		if link == null and s == null:
			return null
		if s == null:
			s = link
		else:
			s.also = link
		net._router_told = net._router_state()
	net.session = s
	return net


## This lobby's room on the party line (null: none).
func party_line() -> RelayLink:
	if session is RelayLink:
		return session as RelayLink
	if session != null and session.also is RelayLink:
		return session.also as RelayLink
	return null


## What the party line keeps of a hosted lobby (NetRelay's OPEN and NEWS):
## the server list's summary, listed when it has no password, and the host's
## own port and addresses for players to try first.
func room_info(direct := true) -> Dictionary:
	var lan: PackedStringArray = (
		RelayLink.test_lan if not RelayLink.test_lan.is_empty() else local_addresses()
	)
	return {
		"summary": summary(),
		"listed": str(settings.get("password", "")) == "",
		"port": port if direct else 0,
		"open": _router_state() == "open",
		"lan": Array(lan),
	}


## "open" when the router opened the port to an address the world can reach.
func _router_state() -> String:
	if upnp == null:
		return ""
	if upnp.state == "open" and upnp.external != "" and upnp.shared_address():
		return "shared"
	return upnp.state


## An always-open lobby on `at_port` with no host player (null: the port is
## taken). `lobby` overrides DEFAULTS and is what it goes back to when empty.
## `more_peers`: room on its port for the party line's (net_relay.gd).
static func serve_lobby(at_port: int, lobby := {}, bind := "*", more_peers := 0) -> NetPlay:
	# Room for a few server lists asking at once besides a full lobby.
	var s := NetSession.host(
		at_port, NetSession.Transport.ENET, Modes.MAX_PLAYERS + 6 + more_peers, bind
	)
	if s == null:
		return null
	var net := NetPlay.new()
	net.role = Role.HOST
	net.dedicated = true
	net.session = s
	net.port = at_port
	net.my_id = NetSession.HOST_ID
	net.phase = "lobby"
	net.settings.merge(lobby, true)
	if str(net.settings["mode"]) == "tagteam" and not Modes.TAGTEAM_MAPS.has(net.settings["map"]):
		net.settings["map"] = Modes.TAGTEAM_MAPS[0]
	net._mode_fits_map()
	net.base_settings = net.settings.duplicate()
	return net


## Joining the lobby at `where` (an address, address:port or a join code).
## null when the address cannot even be tried.
static func join_lobby(where: String, my_name: String, password := "") -> NetPlay:
	var room_code := NetRelay.clean_code(where)
	var target := {"host": room_code, "port": 0} if room_code != "" else parse_address(where)
	if target.is_empty():
		return null
	var s: NetSession = null
	if room_code != "":
		# A party line code: the host's own address first where it may answer.
		s = RelayLink.join_room(room_code, not OS.has_feature("web"))
	elif where.contains("://"):
		# A lobby server's WebSocket (the browser build: wss://host:443).
		s = NetSession.join(where, 0, NetSession.Transport.WEBSOCKET)
	else:
		var target_port: int = target["port"]
		s = NetSession.join(str(target["host"]), target_port)
	if s == null:
		return null
	var net := NetPlay.new()
	net.role = Role.CLIENT
	net.session = s
	net.address = str(target["host"])
	net.port = target["port"]
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
		if session == null:
			return
	var packets := session.poll(now_ms)
	var events := session.take_events()
	if role == Role.HOST:
		for id: int in events[0]:
			_waiting_hello[id] = now_ms
		for id: int in events[1]:
			_gone(id)
		for id: int in _waiting_hello.keys():
			var hello_at: float = _waiting_hello[id]
			if now_ms - hello_at > HELLO_WAIT * 1000.0:
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
			var from: int = packet[0]
			_host_message(from, kind, NetWire.info_of(bytes))
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
		# (Through the party line: what it said, "THE HOST HUNG UP" and the like.)
		_close(session.refusal() if session.refusal() != "" else "LOST THE HOST")
		return
	if phase == "match":
		_watch_tally()
	if role == Role.HOST and not dedicated:
		_watch_party_line()


## A host's room on the party line: told when the router answers; a lobby
## hosted through it alone (the browser) closes when it is lost.
func _watch_party_line() -> void:
	var link := party_line()
	if link == null:
		return
	if link == session and link.refusal() != "":
		_close(link.refusal())
		return
	var router := _router_state()
	if router != _router_told:
		_router_told = router
		link.news(room_info(link != session))


## Notes when the match's results came up; an always-open lobby takes
## everyone back BACK_AFTER seconds later.
func _watch_tally() -> void:
	var g := match_game()
	var run: CountyRunScript = CountyMode.run(g)
	if g == null or not (g.showing_tally or (run != null and run.over)):
		return
	if tally_at < 0.0:
		tally_at = _now
	if dedicated and _now - tally_at >= BACK_AFTER * 1000.0:
		back_to_lobby()


## Whole seconds until an always-open lobby's results end (-1: not showing,
## or a lobby with a host).
func back_in() -> int:
	var served: bool = settings.get("dedicated", dedicated)
	if tally_at < 0.0 or not served:
		return -1
	return maxi(0, ceili(BACK_AFTER - (_now - tally_at) / 1000.0))


func _connecting() -> void:
	if _opened_at < 0.0:
		_opened_at = _now
	if session.refusal() != "":
		_close(session.refusal())
	elif session.connected():
		phase = "hello"
		var version := str(ProjectSettings.get_setting("application/config/version", ""))
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
		NetWire.INFO:
			_info(from)
		NetWire.BOARD:
			_board(from, info)
		NetWire.ASK:
			var p := player_of(from)
			if p.is_empty():
				return
			if info.has("name"):
				var was := str(p["name"])
				p["name"] = unique_name(clean_name(str(info["name"])), from)
				if was != p["name"]:
					_tell("%s IS NOW %s" % [was, p["name"]])
			var pick_teams: bool = settings["pick_teams"]
			if info.has("team") and pick_teams:
				var team: int = info["team"]
				p["team"] = clampi(team, -1, 1)
			if info.has("ready"):
				var ready: bool = info["ready"]
				p["ready"] = ready
			if dedicated and from == admin_id:
				_admin_asks(info)
			send_lobby()
		NetWire.BYE:
			_gone(from)
			session.drop(from)


## What an always-open lobby's admin asked for: settings, START, a kick,
## everyone back from the results.
func _admin_asks(info: Dictionary) -> void:
	var wanted: Variant = info.get("set", {})
	if wanted is Dictionary and phase == "lobby":
		var wanted_dict: Dictionary = wanted
		for key: String in wanted_dict.keys():
			var value: Variant = allowed_value(key, wanted_dict[key])
			if value != null:
				set_setting(key, value)
	if info.has("kick"):
		var kick_id: int = info["kick"]
		kick(kick_id)
	var start: bool = info.get("start", false)
	if start and phase == "lobby":
		var why := start_match()
		if why != "":
			_tell(why)
	var back: bool = info.get("back", false)
	if back and phase == "match" and tally_at >= 0.0:
		back_to_lobby()


## `value` as one of setting `key`'s own values (null: not a setting the
## admin may change, or not one of its values).
static func allowed_value(key: String, value: Variant) -> Variant:
	if SERVER_ONLY.has(key):
		return null
	for row: Array in MATCH_ROWS + LOBBY_ROWS:
		if str(row[0]) != key:
			continue
		for v: Variant in row[2]:
			if str(v) == str(value):
				return v
	return null


## A line every lobby screen shows (an always-open lobby sends it with the
## next LOBBY; a host's own front end shows it).
func _tell(line: String) -> void:
	news.append(line)
	if dedicated:
		_told.append(line)


## A server list asking what this lobby is doing: the answer, then goodbye.
func _info(from: int) -> void:
	_waiting_hello.erase(from)
	if not player_of(from).is_empty():
		return
	session.send(from, NetSession.CH_RELIABLE, NetWire.message(NetWire.INFO, summary()))
	session.poll(_now)
	_drop_later(from)


## A COUNTY RUN daily board knock: the board back, then goodbye.
func _board(from: int, info: Dictionary) -> void:
	_waiting_hello.erase(from)
	if not player_of(from).is_empty():
		return
	var reply := NetWire.message(NetWire.BOARD, CountyBoard.answer(info))
	session.send(from, NetSession.CH_RELIABLE, reply)
	session.poll(_now)
	_drop_later(from)


## What a server list shows of this lobby.
func summary() -> Dictionary:
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	var boss := player_of(admin_of())
	return {
		"lobby_name": settings["lobby_name"],
		"mode": settings["mode"],
		"map": settings["map"],
		"players": players.size(),
		"max_players": settings["max_players"],
		"team_size": settings["team_size"],
		"phase": phase,
		"late_join": settings["late_join"],
		"locked": str(settings.get("password", "")) != "",
		"admin": str(boss.get("name", "")),
		"version": version,
	}


func _hello(from: int, info: Dictionary) -> void:
	_waiting_hello.erase(from)
	if not player_of(from).is_empty():
		return
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	var refused := ""
	var who := "THE SERVER" if dedicated else "THE HOST"
	var protocol: int = info.get("protocol", 0)
	var max_players: int = settings["max_players"]
	var late_join: bool = settings["late_join"]
	if protocol != NetWire.PROTOCOL:
		refused = "%s RUNS ANOTHER VERSION (%s)" % [who, version]
	elif str(info.get("version", "")) != version:
		refused = "%s RUNS %s, YOU RUN %s" % [who, version, str(info.get("version", "?"))]
	elif (
		str(settings["password"]) != ""
		and str(info.get("password", "")) != str(settings["password"])
	):
		refused = "WRONG PASSWORD"
	elif players.size() >= max_players or (party() and players.size() >= most_players()):
		refused = "THE LOBBY IS FULL"
	elif phase == "match" and (not late_join or not _room_late()):
		refused = "A MATCH IS UNDER WAY" + ("" if late_join else " (NO LATE JOIN)")
	if refused != "":
		session.send(from, NetSession.CH_RELIABLE, NetWire.welcome({"refused": refused}))
		session.poll(_now)
		_drop_later(from)
		return
	var name := unique_name(clean_name(str(info.get("name", "PLAYER"))), from)
	var p := {"id": from, "name": name, "team": -1, "ready": false}
	players.append(p)
	_tell("%s JOINED" % name)
	if dedicated and admin_id == 0:
		admin_id = from
		_tell("%s RUNS THE LOBBY" % name)
	session.send(
		from,
		NetSession.CH_RELIABLE,
		NetWire.welcome({"id": from, "lobby": lobby_info(), "phase": phase})
	)
	NetMaps.send_to(self, from)  # a player map before anything can start on it
	if phase == "match":
		_seat_late(p)
	send_lobby()


## Room for someone joining a match under way: a bot's slot in the 5v5, a
## slot left empty or a new player in the party modes.
func _room_late() -> bool:
	if not party():
		return _bot_slot_for() >= 0
	if host_sync == null:
		return false
	if host_sync.game.players.any(func(q: Player) -> bool: return q.away):
		return true
	return host_sync.game.players.size() < most_players()


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
	_tell("%s LEFT" % p["name"])
	if phase == "match" and host_sync != null:
		host_sync.drop_remote(id)
		# (COUNTY RUN co-op: nobody takes their place; they stand where they were.
		# Co-op and deathmatch: they lie out of play until someone takes the slot.)
		if p.has("slot") and party():
			var gone_slot: int = p["slot"]
			if gone_slot < host_sync.game.players.size():
				Modes.went_away(host_sync.game, host_sync.game.players[gone_slot])
		elif p.has("slot") and not county():
			var slot: int = p["slot"]
			changes.append({"bot": slot, "name": str(p["name"])})
	if dedicated:
		_after_leaving(id)
	send_lobby()


## An always-open lobby after someone left: the next in line runs it; with
## nobody left the match ends and the lobby has its own settings again.
func _after_leaving(id: int) -> void:
	if id == admin_id:
		admin_id = players[0]["id"] if not players.is_empty() else 0
		if admin_id != 0:
			_tell("%s RUNS THE LOBBY" % players[0]["name"])
	if not players.is_empty():
		return
	if phase == "match":
		back_to_lobby()
	settings = base_settings.duplicate()
	_told.clear()


func _drop(id: int, _why: String) -> void:
	if session != null:
		session.drop(id)
	_gone(id)


## A refused client is let go once its refusal has had time to get there.
func _drop_later(id: int) -> void:
	(Engine.get_main_loop() as SceneTree).create_timer(1.0).timeout.connect(
		func() -> void:
			if session != null and player_of(id).is_empty():
				session.drop(id)
	)


func kick(id: int) -> void:
	if role == Role.CLIENT and is_admin() and id != my_id:
		ask({"kick": id})
		return
	if role != Role.HOST or id == NetSession.HOST_ID or player_of(id).is_empty():
		return
	if dedicated and id == admin_id:
		return
	var why := "THE ADMIN KICKED YOU" if dedicated else "THE HOST KICKED YOU"
	session.send(id, NetSession.CH_RELIABLE, NetWire.message(NetWire.BYE, {"why": why}))
	session.poll(_now)
	_tell("%s WAS KICKED" % player_of(id)["name"])
	_gone(id)
	_drop_later(id)


func player_of(id: int) -> Dictionary:
	for p: Dictionary in players:
		var pid: int = p["id"]
		if pid == id:
			return p
	return {}


## What every lobby screen shows: the settings (no password) and the players.
func lobby_info() -> Dictionary:
	var shown := settings.duplicate()
	shown["locked"] = str(settings["password"]) != ""
	shown.erase("password")
	var list: Array = []
	var plan := team_plan()
	for p: Dictionary in players:
		var side: int = plan[p["id"]]
		p["side"] = side
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
	shown["dedicated"] = dedicated
	shown["admin"] = admin_id if dedicated else NetSession.HOST_ID
	return {"settings": shown, "players": list, "phase": phase}


func send_lobby() -> void:
	if role != Role.HOST or session == null:
		return
	var info := lobby_info()
	if not _told.is_empty():
		info["news"] = Array(_told)
		_told.clear()
	session.send(0, NetSession.CH_RELIABLE, NetWire.message(NetWire.LOBBY, info))
	var link := party_line()
	if link != null and not dedicated:
		link.news(room_info(link != session))


## Does this machine run the lobby (the host, or an always-open lobby's admin)?
func is_admin() -> bool:
	if role == Role.HOST:
		return not dedicated
	var admin: int = settings.get("admin", -1)
	return role == Role.CLIENT and my_id != 0 and admin == my_id


## The id of whoever runs the lobby (0: nobody).
func admin_of() -> int:
	if role == Role.HOST:
		return admin_id if dedicated else NetSession.HOST_ID
	var admin: int = settings.get("admin", 0)
	return admin


## A host setting changed (lobby_screens.gd): every lobby hears.
func set_setting(key: String, value: Variant) -> void:
	if role == Role.CLIENT and is_admin():
		ask({"set": {key: value}})
		return
	if role != Role.HOST:
		return
	var was_tag := str(settings.get("mode", "")) == "tagteam"
	settings[key] = value
	# A mode onto one of its maps; a map that is not the mode's takes the lobby
	# to the mode it is (a 2v2 map: TAG TEAM 2V2, a chapter: CAMPAIGN CO-OP).
	_mode_fits_map(key)
	var tag := str(settings.get("mode", "")) == "tagteam"
	if tag != was_tag:
		# Onto a TAG TEAM map: its format (two a side, first to 9, short
		# rounds); back onto a 5v5 map: the 5v5's.
		settings["team_size"] = 2 if tag else 5
		settings["rounds"] = 9 if tag else 7
		settings["round_seconds"] = 90.0 if tag else 0.0
		settings["buy_seconds"] = 15.0 if tag else 20.0
	if key == "pick_teams":
		var picking: bool = value
		if not picking:
			for p: Dictionary in players:
				p["team"] = -1
	send_lobby()


## The mode a lobby's MODE plays by (Modes): TAG TEAM 2V2 is search and
## destroy two a side.
## A COUNTY RUN co-op lobby (MODE, or a county map).
func county() -> bool:
	return str(settings.get("mode", "")) == Modes.COUNTY


static func play_mode(id: String) -> String:
	return Modes.BOMB if id == "tagteam" else id


## A party mode's lobby (CAMPAIGN CO-OP, DEATHMATCH, TEAM DEATHMATCH).
func party() -> bool:
	return PARTY_MODES.has(str(settings.get("mode", "")))


## The most people the lobby's mode takes.
func most_players() -> int:
	if county():
		return CountyCoop.MOST
	return Modes.MAX_FREE_FOR_ALL if party() else Modes.MAX_PLAYERS


## The modes this lobby can play: an always-open lobby has no host to lead a
## campaign, so no CAMPAIGN CO-OP there.
func modes() -> Array:
	var row: Array = MATCH_ROWS[0][2]
	return row.filter(func(m: Variant) -> bool: return not (dedicated and str(m) == Modes.COOP))


## The maps of the lobby's mode (MAP steps through these).
func maps() -> Array:
	return MODE_MAPS.get(str(settings.get("mode", "")), [])


## MODE and MAP agree: after MODE changed, the mode's first map when the one
## set is not its; otherwise the MODE the map is (the first mode listing it:
## a 5v5 map stays with SEARCH AND DESTROY).
func _mode_fits_map(changed := "map") -> void:
	if NetMaps.fit_mode(self, changed):
		return  # a player map: the modes it can host (net_maps.gd)
	var map := str(settings.get("map", ""))
	var mode := str(settings.get("mode", ""))
	if dedicated and mode == Modes.COOP:
		mode = Modes.BOMB
		settings["mode"] = mode
	var own: Array = MODE_MAPS.get(mode, [])
	if own.has(map):
		return
	if changed == "mode" and not own.is_empty():
		settings["map"] = own[0]
		return
	for m: Variant in modes():
		var listed: Array = MODE_MAPS.get(str(m), [])
		if listed.has(map):
			settings["mode"] = str(m)
			return
	if not own.is_empty():
		settings["map"] = own[0]


## Is everyone ready and are the teams playable? "" when it can start.
func why_not_start() -> String:
	if phase != "lobby" or not (is_admin() or dedicated):
		return "ONLY THE HOST STARTS"
	if party():
		return _why_not_party()
	if county():
		var boss_id := admin_of()
		for p: Dictionary in players:
			var ready: bool = p["ready"]
			var pid: int = p["id"]
			if not ready and pid != boss_id:
				return "WAITING ON %s" % p["name"]
		if players.size() > CountyCoop.MOST:
			return "COUNTY RUN TAKES %d AT MOST" % CountyCoop.MOST
		return ""
	var size: int = settings["team_size"]
	var plan := team_plan()
	var count := [0, 0]
	var boss := admin_of()
	for p: Dictionary in players:
		var side: int = plan[p["id"]]
		count[side] += 1
		var ready: bool = p["ready"]
		var pid: int = p["id"]
		if not ready and pid != boss:
			return "WAITING ON %s" % p["name"]
	if count[0] > size or count[1] > size:
		return "TOO MANY ON A TEAM FOR %dV%d" % [size, size]
	var bots: bool = settings["bots"]
	if not bots and (count[0] == 0 or count[1] == 0):
		return "BOTH TEAMS NEED A PLAYER (OR BOTS ON)"
	if str(settings["mode"]) == Modes.HOSTAGE and Modes.TAGTEAM_MAPS.has(str(settings["map"])):
		return "NO HOSTAGES ON A 2V2 MAP: SEARCH AND DESTROY"
	return ""


## The party modes: everyone ready, four at most, two for a fight.
func _why_not_party() -> String:
	var boss_id := admin_of()
	for p: Dictionary in players:
		var ready: bool = p["ready"]
		var pid: int = p["id"]
		if not ready and pid != boss_id:
			return "WAITING ON %s" % p["name"]
	var mode := str(settings["mode"])
	if players.size() > most_players():
		return "FOUR AT MOST IN THIS ONE"
	if mode != Modes.COOP and players.size() < 2:
		return "IT TAKES TWO TO FIGHT. WAIT ON A FRIEND."
	var pick_teams: bool = settings["pick_teams"]
	if mode == Modes.TEAM and pick_teams:
		var plan := team_plan()
		var sides := [0, 0]
		for p: Dictionary in players:
			var side: int = plan[p["id"]]
			sides[side] += 1
		if sides[0] == 0 or sides[1] == 0:
			return "BOTH TEAMS NEED A PLAYER"
	return ""


## id -> team for the match: picks kept, the rest to the smaller team.
func team_plan() -> Dictionary:
	var out := {}
	var count := [0, 0]
	for p: Dictionary in players:
		var t: int = p["team"]
		var pick_teams: bool = settings["pick_teams"]
		if t >= 0 and pick_teams:
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
	if role == Role.CLIENT:
		var not_yet := why_not_start()
		if not_yet == "":
			ask({"start": true})
		return not_yet
	var why := why_not_start()
	if why == "" and may_start.is_valid():
		why = str(may_start.call())
	if why != "":
		return why
	var size: int = settings["team_size"]
	var plan := team_plan()
	var teams: Array = []
	var names: Array = []
	var slot_of := {}
	# The host is slot 0 (the game's own player one), then the others.
	for p: Dictionary in players:
		slot_of[p["id"]] = teams.size()
		p["slot"] = teams.size()
		var team: int = plan[p["id"]]
		teams.append(team)
		names.append(str(p["name"]))
	var bots: bool = settings["bots"]
	if bots and not county() and not party():
		for t in 2:
			while teams.count(t) < size:
				teams.append(t)
				names.append("")
	var info := {
		"level": str(Modes.arena_of(str(settings["map"]))[0]),
		"mode": play_mode(str(settings["mode"])),
		"count": teams.size(),
		"options": match_options(teams, names),
		"slots": slot_of,
		"sim": sim_options,
		# Fresh dice for each match (every copy sets them: main_flow.gd).
		"seed": int(Time.get_unix_time_from_system() * 1000.0) & 0x7FFFFFFFFFFF,
	}
	var game: Game = make_match.call(info)
	if game == null:
		return "THE MAP WOULD NOT LOAD"
	match_info = info
	tally_at = -1.0
	host_sync = NetSync.Host.new(session, game, func() -> int: return -1, SNAP_EVERY)
	for p: Dictionary in players:
		var pid: int = p["id"]
		p["ready"] = pid == NetSession.HOST_ID
		if pid != NetSession.HOST_ID:
			var slot: int = p["slot"]
			host_sync.add_remote(pid, slot)
			_send_start(pid, slot)
	phase = "match"
	changes.append({"started": true})
	send_lobby()
	return ""


func match_options(teams: Array, names: Array) -> Dictionary:
	var rounds: int = settings["rounds"]
	var out := {
		"arena": str(settings["map"]),
		"rounds": rounds,
		"teams": teams,
		"names": names,
	}
	if party():
		out["frag_limit"] = settings.get("frag_limit", DeathmatchMode.FRAG_LIMIT)
		out["time_limit"] = settings.get("time_limit", DeathmatchMode.TIME_LIMIT)
		if str(settings["mode"]) == Modes.COOP:
			out["arena"] = ""
	for key: String in Modes.HOST_SETTINGS:
		if settings.has(key):
			out[key] = settings[key]
	return out


func _send_start(id: int, slot: int) -> void:
	var info := match_info.duplicate()
	info.erase("slots")
	info["slot"] = slot
	var options: Dictionary = match_info["options"]
	var teams: Array = options["teams"]
	var names: Array = options["names"]
	var given := match_options(teams, _names_now(names))
	given.merge(options, false)  # what the front end added (a hub's gates)
	info["options"] = given
	if party() and host_sync != null:
		info["count"] = host_sync.game.players.size()
	session.send(id, NetSession.CH_RELIABLE, NetWire.message(NetWire.START, info))


func _names_now(names: Array) -> Array:
	var out := names.duplicate()
	if host_sync != null:
		for q: Player in host_sync.game.players:
			if q.slot < out.size():
				out[q.slot] = q.name
	return out


## A late joiner takes a bot's place on the team with fewer people (the
## party modes: a slot left empty, or a new player: Modes.join_late).
func _seat_late(p: Dictionary) -> void:
	if party():
		var q := Modes.join_late(host_sync.game, str(p["name"]))
		if q == null:
			return
		p["slot"] = q.slot
		p["ready"] = true
		var joined_id: int = p["id"]
		host_sync.add_remote(joined_id, q.slot)
		_send_start(joined_id, q.slot)
		changes.append({"human": q.slot, "name": str(p["name"])})
		_tell("%s PULLS UP A CHAIR" % p["name"])
		return
	var slot := _bot_slot_for()
	if slot < 0:
		return
	p["slot"] = slot
	p["ready"] = true
	var q: Player = host_sync.game.players[slot]
	q.name = str(p["name"])
	var pid: int = p["id"]
	host_sync.add_remote(pid, slot)
	_send_start(pid, slot)
	changes.append({"human": slot, "name": str(p["name"])})
	_tell("%s TAKES OVER FROM A BOT" % p["name"])


## The bot's slot a late joiner gets (-1: none): on the team with fewer people.
func _bot_slot_for() -> int:
	if host_sync == null:
		return -1
	var taken := {}
	var people := [0, 0]
	for p: Dictionary in players:
		var slot: int = p.get("slot", -1)
		if p.has("slot") and slot >= 0:
			taken[slot] = true
			people[host_sync.game.players[slot].team] += 1
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
			var slot: int = p["slot"]
			taken[slot] = true
	for q: Player in host_sync.game.players:
		if not taken.has(q.slot):
			out.append(q.slot)
	return out


## The host's match goes on in another game (online co-op: the next chapter,
## the hub, a retried boss fight, a chapter from its start): every client is
## sent START for it, on its own slot. Snapshot numbers run on past the last
## game's (`seq_from`) and a client's input numbers carry on, so nothing of
## the last game still on its way is taken for the new one (NetSync). `extra`
## goes in START's options (the hub's locked gates).
func switch_match(game: Game, extra := {}) -> void:
	if role != Role.HOST or host_sync == null or game == null:
		return
	var next_seq := host_sync.seq + 1 + NetSync.Host.KEEP
	match_info["level"] = game.level.id
	match_info["count"] = game.players.size()
	var options: Dictionary = match_info["options"]
	for key: String in ["locked", "gate_modes"]:
		options.erase(key)
	options.merge(extra, true)
	match_info["seq_from"] = next_seq
	host_sync = NetSync.Host.new(session, game, func() -> int: return -1, SNAP_EVERY)
	host_sync.seq = next_seq - 1
	tally_at = -1.0
	for p: Dictionary in players:
		var pid: int = p["id"]
		if pid != NetSession.HOST_ID and p.has("slot"):
			var slot: int = p["slot"]
			host_sync.add_remote(pid, slot)
			_send_start(pid, slot)


## One tick of the match: `own` holds the host's own player and the bots.
func host_tick(own: Dictionary) -> void:
	if host_sync != null:
		host_sync.play(own)


## Back to the lobby after a match (the host's ENTER on the results).
func back_to_lobby() -> void:
	if role == Role.CLIENT and is_admin():
		ask({"back": true})
		return
	if role != Role.HOST:
		return
	host_sync = null
	match_info = {}
	tally_at = -1.0
	phase = "lobby"
	for p: Dictionary in players:
		p.erase("slot")
		var pid: int = p["id"]
		p["ready"] = pid == NetSession.HOST_ID
	session.send(0, NetSession.CH_RELIABLE, NetWire.message(NetWire.BACK, {}))
	changes.append({"lobby": true})
	send_lobby()


# ------------------------------------------------------------------ a client


func _client_message(kind: int, info: Dictionary) -> void:
	match kind:
		NetWire.WELCOME:
			if info.has("refused"):
				_close(str(info["refused"]))
				return
			my_id = info.get("id", session.id())
			phase = "lobby"
			var lobby: Dictionary = info.get("lobby", {})
			_take_lobby(lobby)
		NetWire.LOBBY:
			_take_lobby(info)
		NetWire.START:
			_start(info)
		NetWire.MAP:
			NetMaps.take(self, info)
		NetWire.BACK:
			client_sync = null
			match_info = {}
			tally_at = -1.0
			phase = "lobby"
			changes.append({"lobby": true})
		NetWire.BYE:
			_close(str(info.get("why", "THE HOST CLOSED THE LOBBY")))


func _take_lobby(info: Dictionary) -> void:
	if info.is_empty():
		return
	var shown: Dictionary = info.get("settings", {})
	settings.merge(shown, true)
	players = info.get("players", [])
	for line: Variant in info.get("news", []):
		news.append(str(line))


## What this player wants (lobby_screens.gd): name, team, ready.
func ask(what: Dictionary) -> void:
	if role != Role.CLIENT or session == null:
		return
	session.send(NetSession.HOST_ID, NetSession.CH_RELIABLE, NetWire.message(NetWire.ASK, what))


func _start(info: Dictionary) -> void:
	match_info = info
	tally_at = -1.0
	var game: Game = make_match.call(info)
	if game == null:
		_close("THE MAP WOULD NOT LOAD")
		return
	var was := client_sync
	client_sync = NetSync.Client.new(session, func(_id: String) -> Game: return null)
	if info.has("seq_from"):
		# The host moved the match on (switch_match): the last game's snapshots
		# still on their way are stale, and our inputs keep their numbers.
		var seq_from: int = info["seq_from"]
		client_sync.latest = seq_from - 1
		if was != null:
			client_sync.input_seq = was.input_seq
	client_sync.slot = info["slot"]
	client_sync.level = str(info["level"])
	client_sync.game = game
	phase = "match"
	changes.append({"started": true})


## This tick's controls go to the host.
func client_input(c: Game.Controls) -> void:
	if client_sync != null:
		client_sync.send_input(c)


## Plays the copy on toward the host's newest snapshot: `ticks` (about a
## frame's worth), paced by the clock (NetSync.Client.playout).
func client_play(ticks: int) -> void:
	if client_sync != null:
		# Paced by the clock, a depth behind the host that covers the link's
		# jitter (NetSync.Client.playout); it used to stand a fixed
		# two ticks behind the newest snapshot, so every late one froze
		# everyone for a frame and the catch-up after it hurried them.
		client_sync.by_clock = not county()
		client_sync.playout(ticks, _now)


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
## Through the party line it is the trip to the line and the host's own.
func ping_ms() -> float:
	if role != Role.CLIENT or session == null or not (session.peer is ENetMultiplayerPeer):
		return 0.0
	var enet := session.peer as ENetMultiplayerPeer
	var p := enet.get_peer(NetSession.HOST_ID)
	var own := p.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) if p != null else 0.0
	return own + session.extra_ms()


# ------------------------------------------------------------------ addresses


## {host, port} from "1.2.3.4", "1.2.3.4:5000", "[::1]:5000", "name:5000" or
## a join code ("ABCDE-FGHIJ"); {} when it is none of them.
static func parse_address(text: String) -> Dictionary:
	var t := text.strip_edges()
	if t == "":
		return {}
	if t.begins_with("ws://") or t.begins_with("wss://"):
		var rest := t.get_slice("://", 1)
		var at := rest.rfind(":")
		return {
			"host": rest.substr(0, at) if at > 0 else rest,
			"port": rest.substr(at + 1).to_int() if at > 0 else 443
		}
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
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REMEMBER))
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


## The match rows from lobby.cfg, the store rules' row filled from store.cfg.
static func _match_rows() -> Array:
	var rows: Array = Tuning.file(LOBBY_DATA).get_value("lobby", "match_rows", [])
	for row: Array in rows:
		if row[2] is String and row[2] == "store":
			row[2] = TacticalShop.RULE_IDS
			row[3] = TacticalShop.RULE_NAMES
	return rows
