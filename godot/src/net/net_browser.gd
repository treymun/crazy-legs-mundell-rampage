## The COUNTY SERVERS list (lobby_screens.gd draw_servers): the always-open
## lobbies in data/tuning/servers.json, each asked every ASK_EVERY seconds
## what it is doing (an INFO knock on its own port: connect, ask, hear, hang
## up; NetPlay answers it), so a player sees them live and joins one with
## ENTER, no code. Below them, the party line's rooms (net_relay.gd: hosts'
## own lobbies with no password), asked of the line the same way (a LIST
## knock); ENTER on one joins it by its code. Nothing here draws or reads keys.
class_name NetBrowser
extends RefCounted

const LIST := "res://data/tuning/servers.json"
## Seconds between asks, and how long one waits for its answer.
const ASK_EVERY := 5.0
const WAIT := 3.0

## Each server: {name, address, port, state ("asking", "up", "silent"), info
## (its last answer: NetPlay.summary()), ping (ms), and the knock in flight}.
var servers: Array = []
## The list's cursor (0: your name, 1.. the servers) and the name typed.
var row := 1
var name := ""
var _now := 0.0
## How many of `servers` are the listed ones (the party line's rooms follow).
var _listed := 0
## The party line's knock in flight, and when it was last asked.
var _line: RelayLink = null
var _line_at := -1.0e9


## The servers listed in data/tuning/servers.json ([] when there is none).
static func listed() -> Array:
	if not FileAccess.file_exists(LIST):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LIST))
	if not parsed is Dictionary:
		return []
	var doc: Dictionary = parsed
	return doc.get("servers", [])


func _init(list := listed()) -> void:
	for entry: Variant in list:
		if entry is Dictionary:
			var e: Dictionary = entry
			var port: int = e.get("port", NetSession.PORT)
			(
				servers
				. append(
					{
						"name": str(e.get("name", "SERVER")),
						"address": str(e.get("address", "")),
						"port": port,
						"wss": str(e.get("wss", "")),
						"state": "asking",
						"info": {},
						"ping": 0.0,
						"session": null,
						"asked_at": -1.0e9,
						"sent_at": -1.0,
					}
				)
			)
	_listed = servers.size()


## Asks and hears; call every frame while the list is shown.
func poll(now_ms: float) -> void:
	_now = now_ms
	_ask_line(now_ms)
	for s: Dictionary in servers.slice(0, _listed):
		var session: NetSession = s["session"]
		var asked_at: float = s["asked_at"]
		if session == null:
			if now_ms - asked_at >= ASK_EVERY * 1000.0:
				_knock(s)
			continue
		var packets := session.poll(now_ms)
		var sent_at: float = s["sent_at"]
		if sent_at < 0.0 and session.connected():
			session.send(
				NetSession.HOST_ID, NetSession.CH_RELIABLE, NetWire.message(NetWire.INFO, {})
			)
			s["sent_at"] = now_ms
		for packet: Array in packets:
			var bytes: PackedByteArray = packet[1]
			if not bytes.is_empty() and bytes[0] == NetWire.INFO:
				s["info"] = NetWire.info_of(bytes)
				var sent_at_now: float = s["sent_at"]
				s["ping"] = now_ms - sent_at_now
				s["state"] = "up"
				_hang_up(s)
				break
		if s["session"] != null and now_ms - asked_at > WAIT * 1000.0:
			s["state"] = "silent"
			s["info"] = {}
			_hang_up(s)
	_drop_unserved()


## A lobby server says which ports it runs lobbies on (its INFO answer's
## "ports"): a listed lobby at that address on another port is not run
## there any more (server/lobbies.json has fewer lobbies than
## servers.json), so it leaves the list instead of showing NOT ANSWERING.
func _drop_unserved() -> void:
	var gone: Array = []
	for s: Dictionary in servers.slice(0, _listed):
		var info: Dictionary = s["info"]
		var ports: Array = info.get("ports", [])
		if ports.is_empty():
			continue
		for other: Dictionary in servers.slice(0, _listed):
			if other != s and other["address"] == s["address"] and not ports.has(other["port"]):
				if not gone.has(other):
					gone.append(other)
	for other: Dictionary in gone:
		_hang_up(other)
		servers.erase(other)
		_listed -= 1
	if not gone.is_empty():
		row = clampi(row, 0, servers.size())


## The party line's rooms, asked every ASK_EVERY seconds; each is a row
## after the listed servers, joined by its code.
func _ask_line(now_ms: float) -> void:
	if _line == null:
		if now_ms - _line_at >= ASK_EVERY * 1000.0:
			_line_at = now_ms
			_line = RelayLink.ask_rooms()
		return
	_line.poll(now_ms)
	if _line.state == "done":
		_rooms(_line.rooms, _line.answered_ms)
	elif now_ms - _line_at <= WAIT * 1000.0 and _line.state == "calling":
		return
	else:
		_rooms([], 0.0)  # not answering: no rooms to show
	_line.close()
	_line = null


func _rooms(list: Array, line_ms: float) -> void:
	servers.resize(_listed)
	for entry: Variant in list:
		if not entry is Dictionary:
			continue
		var room: Dictionary = entry
		var info: Dictionary = room.get("summary", {})
		var host_ms: float = room.get("host_ms", 0.0)
		(
			servers
			. append(
				{
					"name": str(info.get("lobby_name", "A LOBBY")),
					"code": str(room.get("code", "")),
					"state": "up",
					"info": info,
					"ping": line_ms + maxf(0.0, host_ms),
					"session": null,
				}
			)
		)
	row = mini(row, servers.size())


## Asks every server (and the party line) again now.
func refresh() -> void:
	for s: Dictionary in servers.slice(0, _listed):
		_hang_up(s)
		s["asked_at"] = -1.0e9
	_line_at = -1.0e9


func close() -> void:
	for s: Dictionary in servers.slice(0, _listed):
		_hang_up(s)
	if _line != null:
		_line.close()
		_line = null


func _knock(s: Dictionary) -> void:
	s["asked_at"] = _now
	s["sent_at"] = -1.0
	if OS.has_feature("web"):
		# The browser has no ENet: the server's secure WebSocket, if it has one.
		var wss := str(s["wss"])
		s["session"] = (
			NetSession.join(wss, 0, NetSession.Transport.WEBSOCKET) if wss != "" else null
		)
	else:
		var port: int = s["port"]
		s["session"] = NetSession.join(str(s["address"]), port)
	if s["session"] == null:
		s["state"] = "silent"


func _hang_up(s: Dictionary) -> void:
	var session: NetSession = s["session"]
	if session != null:
		session.close()
	s["session"] = null


## "address:port" of server `i`, for NetPlay.join_lobby.
func address_of(i: int) -> String:
	var s: Dictionary = servers[i]
	if s.has("code"):
		return str(s["code"])  # a party line room
	if OS.has_feature("web") and str(s["wss"]) != "":
		return str(s["wss"])
	var port: int = s["port"]
	return "%s:%d" % [s["address"], port]


## Why server `i` cannot be joined now ("" when it can).
func why_not_join(i: int) -> String:
	var s: Dictionary = servers[i]
	var info: Dictionary = s["info"]
	var what := "THAT LOBBY" if s.has("code") else "THAT SERVER"
	if str(s["state"]) != "up":
		return "THAT SERVER ISN'T ANSWERING. TRY AGAIN IN A BIT."
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	if str(info.get("version", version)) != version:
		return "%s RUNS %s. YOU RUN %s." % [what, info.get("version", "?"), version]
	var players: int = info.get("players", 0)
	var max_players: int = info.get("max_players", 10)
	if players >= max_players:
		return "%s IS FULL." % what
	var late_join: bool = info.get("late_join", true)
	if str(info.get("phase", "")) == "match" and not late_join:
		return "A MATCH IS ON THERE (NO LATE JOIN)."
	return ""
