## The COUNTY SERVERS list (lobby_screens.gd draw_servers): the always-open
## lobbies in data/tuning/servers.json, each asked every ASK_EVERY seconds
## what it is doing (an INFO knock on its own port: connect, ask, hear, hang
## up; NetPlay answers it), so a player sees them live and joins one with
## ENTER, no code. Nothing here draws or reads keys.
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


## The servers listed in data/tuning/servers.json ([] when there is none).
static func listed() -> Array:
	if not FileAccess.file_exists(LIST):
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(LIST))
	return parsed.get("servers", []) if parsed is Dictionary else []


func _init(list := listed()) -> void:
	for entry in list:
		if entry is Dictionary:
			(
				servers
				. append(
					{
						"name": String(entry.get("name", "SERVER")),
						"address": String(entry.get("address", "")),
						"port": int(entry.get("port", NetSession.PORT)),
						"wss": String(entry.get("wss", "")),
						"state": "asking",
						"info": {},
						"ping": 0.0,
						"session": null,
						"asked_at": -1.0e9,
						"sent_at": -1.0,
					}
				)
			)


## Asks and hears; call every frame while the list is shown.
func poll(now_ms: float) -> void:
	_now = now_ms
	for s: Dictionary in servers:
		var session: NetSession = s["session"]
		if session == null:
			if now_ms - float(s["asked_at"]) >= ASK_EVERY * 1000.0:
				_knock(s)
			continue
		var packets := session.poll(now_ms)
		if float(s["sent_at"]) < 0.0 and session.connected():
			session.send(
				NetSession.HOST_ID, NetSession.CH_RELIABLE, NetWire.message(NetWire.INFO, {})
			)
			s["sent_at"] = now_ms
		for packet: Array in packets:
			var bytes: PackedByteArray = packet[1]
			if not bytes.is_empty() and bytes[0] == NetWire.INFO:
				s["info"] = NetWire.info_of(bytes)
				s["ping"] = now_ms - float(s["sent_at"])
				s["state"] = "up"
				_hang_up(s)
				break
		if s["session"] != null and now_ms - float(s["asked_at"]) > WAIT * 1000.0:
			s["state"] = "silent"
			s["info"] = {}
			_hang_up(s)


## Asks every server again now.
func refresh() -> void:
	for s: Dictionary in servers:
		_hang_up(s)
		s["asked_at"] = -1.0e9


func close() -> void:
	for s: Dictionary in servers:
		_hang_up(s)


func _knock(s: Dictionary) -> void:
	s["asked_at"] = _now
	s["sent_at"] = -1.0
	if OS.has_feature("web"):
		# The browser has no ENet: the server's secure WebSocket, if it has one.
		var wss := String(s["wss"])
		s["session"] = (
			NetSession.join(wss, 0, NetSession.Transport.WEBSOCKET) if wss != "" else null
		)
	else:
		s["session"] = NetSession.join(String(s["address"]), int(s["port"]))
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
	if OS.has_feature("web") and String(s["wss"]) != "":
		return String(s["wss"])
	return "%s:%d" % [s["address"], int(s["port"])]


## Why server `i` cannot be joined now ("" when it can).
func why_not_join(i: int) -> String:
	var s: Dictionary = servers[i]
	var info: Dictionary = s["info"]
	if String(s["state"]) != "up":
		return "THAT SERVER ISN'T ANSWERING. TRY AGAIN IN A BIT."
	var version := String(ProjectSettings.get_setting("application/config/version", ""))
	if String(info.get("version", version)) != version:
		return "THAT SERVER RUNS %s. YOU RUN %s." % [info.get("version", "?"), version]
	if int(info.get("players", 0)) >= int(info.get("max_players", 10)):
		return "THAT SERVER IS FULL."
	if String(info.get("phase", "")) == "match" and not bool(info.get("late_join", true)):
		return "A MATCH IS ON THERE (NO LATE JOIN)."
	return ""
