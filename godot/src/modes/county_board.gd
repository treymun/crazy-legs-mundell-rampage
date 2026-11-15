## COUNTY RUN's DAILY RUN board, shared on the lobby server. A daily run is
## seeded from the day (UTC) and the map (`seed_for`), so everyone plays the
## same dice that day; its end posts the run to the first server in
## data/tuning/servers.json and the picker asks for each map's best of the
## day. Both are a BOARD knock on the lobby's own port (connect, send, hear,
## hang up), as the server list's INFO is; the server's lobbies answer from
## one file of the last DAYS days (`answer`, user://county-board.json on the
## server). No sign-in: names are the online name, cleaned, and a run past
## what a day allows is refused.
class_name CountyBoard
extends RefCounted

## Where a server keeps the boards (a test points it at its own folder).
static var store := "user://county-board.json"
## Days kept on the server, rows kept a map a day, rows sent back.
const DAYS := 7
const KEEP := 30
const SHOWN := 5
const WAIT := 4.0

## {map id: rows} heard today ([name, time, level, kills], best first).
var boards := {}
## What is on its way: [session, message, sent?, asked at ms, map].
var _knocks: Array = []
var _now := 0.0
## Set by tests: answer here instead of over the network.
static var local := false


## Today's date (UTC), "2026-11-14".
static func today() -> String:
	return Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()))


## The dice for a daily run of `map_id` on `day`.
static func seed_for(day: String, map_id: String) -> int:
	return hash("county-daily|%s|%s" % [day, map_id]) & 0x7FFFFFFFFFFF


static func _server() -> Dictionary:
	var list := NetBrowser.listed()
	return list[0] if not list.is_empty() and list[0] is Dictionary else {}


## Asks for today's board of `map_id`.
func fetch(map_id: String) -> void:
	_send({"map": map_id, "day": today()}, map_id)


## Posts a finished daily run (CountyRun result) and hears the board back.
func post(name: String, result: Dictionary, day: String) -> void:
	var map_id := str(result.get("map", ""))
	var time: float = result.get("time", 0.0)
	var level: int = result.get("level", 1)
	var kills: int = result.get("kills", 0)
	_send(
		{
			"map": map_id,
			"day": day,
			"post":
			[
				NetPlay.clean_name(name),
				snappedf(time, .1),
				level,
				kills,
			],
			"version": str(ProjectSettings.get_setting("application/config/version", "")),
		},
		map_id
	)


func _send(info: Dictionary, map_id: String) -> void:
	if local:
		_heard(answer(info))
		return
	var server := _server()
	if server.is_empty():
		return
	var session: NetSession = null
	if OS.has_feature("web"):
		var wss := str(server.get("wss", ""))
		if wss != "":
			session = NetSession.join(wss, 0, NetSession.Transport.WEBSOCKET)
	else:
		var port: int = server.get("port", NetSession.PORT)
		session = NetSession.join(str(server.get("address", "")), port)
	if session != null:
		_knocks.append([session, NetWire.message(NetWire.BOARD, info), false, _now, map_id])


## Every frame while a knock is out (main.gd).
func poll(now_ms: float) -> void:
	_now = now_ms
	var left: Array = []
	for k: Array in _knocks:
		var session: NetSession = k[0]
		var packets := session.poll(now_ms)
		var sent: bool = k[2]
		if not sent and session.connected():
			var message: PackedByteArray = k[1]
			session.send(NetSession.HOST_ID, NetSession.CH_RELIABLE, message)
			k[2] = true
		var asked_at: float = k[3]
		var done := now_ms - asked_at > WAIT * 1000.0
		for packet: Array in packets:
			var bytes: PackedByteArray = packet[1]
			if not bytes.is_empty() and bytes[0] == NetWire.BOARD:
				_heard(NetWire.info_of(bytes))
				done = true
		if done:
			session.close()
		else:
			left.append(k)
	_knocks = left


func busy() -> bool:
	return not _knocks.is_empty()


func _heard(info: Dictionary) -> void:
	if str(info.get("day", "")) == today() and info.get("rows") is Array:
		boards[str(info.get("map", ""))] = info["rows"]


## Where `name` stands on `map_id`'s board heard (1 is the best; 0: not on it).
func rank_of(map_id: String, name: String, time: float) -> int:
	var rows: Array = boards.get(map_id, [])
	for i in rows.size():
		var row_time: float = type_convert(rows[i][1], TYPE_FLOAT)
		if str(rows[i][0]) == NetPlay.clean_name(name) and absf(row_time - time) < .2:
			return i + 1
	return 0


# ------------------------------------------------------------------ the server


## A lobby server's answer to a BOARD knock: the day's board for the map,
## after putting in the run posted (the best run a name has a day counts).
static func answer(info: Dictionary) -> Dictionary:
	if info.has("range"):
		# The firing range's board rides the same knock (range_board.gd).
		return RangeBoard.answer(info)
	var map_id := str(info.get("map", ""))
	var day := str(info.get("day", ""))
	var out := {"map": map_id, "day": day, "rows": []}
	if not CountyData.MAP_IDS.has(map_id) or not _recent(day):
		return out
	var all := _read()
	var key := "%s|%s" % [day, map_id]
	var rows: Array = all.get(key, [])
	var post: Variant = info.get("post")
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	var posted: Array = post if post is Array else []
	if posted.size() == 4 and str(info.get("version", "")) == version:
		var name := NetPlay.clean_name(str(posted[0]))
		var time: float = type_convert(posted[1], TYPE_FLOAT)
		# A run cannot have lasted longer than the day has been going.
		if name != "" and time > 0.0 and time < 86400.0 * 2.0:
			var kept := false
			for row: Array in rows:
				if str(row[0]) == name:
					kept = true
					var best: float = row[1]
					if time > best:
						row[1] = time
						row[2] = type_convert(posted[2], TYPE_INT)
						row[3] = type_convert(posted[3], TYPE_INT)
			if not kept:
				var level: int = type_convert(posted[2], TYPE_INT)
				var kills: int = type_convert(posted[3], TYPE_INT)
				rows.append([name, time, clampi(level, 1, 999), clampi(kills, 0, 99999)])
			rows.sort_custom(
				func(a: Array, b: Array) -> bool:
					var a_time: float = a[1]
					var b_time: float = b[1]
					return a_time > b_time
			)
			rows = rows.slice(0, KEEP)
			all[key] = rows
			_write(all)
	out["rows"] = rows.slice(0, SHOWN)
	return out


## Today or yesterday (UTC): a run started before midnight posts after it.
static func _recent(day: String) -> bool:
	var now := int(Time.get_unix_time_from_system())
	return day == today() or day == Time.get_date_string_from_unix_time(now - 86400)


static func _read() -> Dictionary:
	if not FileAccess.file_exists(store):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(store))
	return parsed if parsed is Dictionary else {}


static func _write(all: Dictionary) -> void:
	# Only the last DAYS days.
	var now := int(Time.get_unix_time_from_system())
	var days := {}
	for k in DAYS:
		days[Time.get_date_string_from_unix_time(now - k * 86400)] = true
	for key: String in all.keys():
		if not days.has(key.get_slice("|", 0)):
			all.erase(key)
	var file := FileAccess.open(store, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(all))
		file.close()
