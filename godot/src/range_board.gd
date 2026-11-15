## The firing range's records and the county's board of them. Each game's
## best (a bowling game, the duck gallery, horseshoes, the dunk tank,
## skee-ball, knock 'em down, the fair's shooting gallery) is kept on this
## machine in range-records.json beside the unlocks, never in a campaign
## save; the trophy shack (features/trophy_shack.gd) shows them. Online,
## each finished game is posted to the first server in
## data/tuning/servers.json and each station's card asks for its game's top
## five there, as COUNTY RUN's daily board does (county_board.gd): a BOARD
## knock on the lobby's port carrying "range", answered by `answer()` from
## one file on the server (user://range-board.json), a name's best counting.
## Offline it is the local bests alone. No sign-in: names are the online
## name, cleaned, and a score past what a game allows is refused.
class_name RangeBoard
extends RefCounted

const FILE := "range-records.json"
## The games, the card's names for them, and the most each allows.
const GAMES := {
	"bowling": "BOWL-O-RAMA",
	"gallery": "DUCK GALLERY",
	"horseshoes": "HORSESHOES",
	"dunk": "DUNK TANK",
	"skeeball": "SKEE-BALL",
	"bottles": "KNOCK 'EM DOWN",
	"fair_gallery": "FAIR GALLERY",
}
const MOST := {
	"bowling": 300,
	"gallery": 200,
	"horseshoes": 30,
	"dunk": 60,
	"skeeball": 900,
	"bottles": 30,
	"fair_gallery": 600,
}
## Seconds before a station asks the server again.
const ASK_AGAIN := 60.0

static var KEEP: int = RangeTuning.get_value("range_board", "keep", 30)
static var SHOWN: int = RangeTuning.get_value("range_board", "shown", 5)
static var WAIT: float = RangeTuning.get_value("range_board", "wait", 4.0)
## Where a server keeps the board (a test points it at its own folder), and
## where this machine keeps its records (tools keep theirs in the cache).
static var store := "user://range-board.json"
static var folder_override := ""
## Set by tests: answer here instead of over the network, or knock on this
## server ({address, port}) instead of servers.json's first.
static var local := false
static var server_override := {}

## {game: rows} heard ([name, score], best first).
static var boards := {}
## game -> when it was last asked (ms); what waits to go out ([game, score]
## posts, game asks); what is on its way ([session, message, sent?, asked
## at ms]).
static var _asked := {}
static var _posts: Array = []
static var _asks: Array = []
static var _knocks: Array = []
static var _now := 0.0

# ------------------------------------------------------------------ records


static func folder() -> String:
	if folder_override != "":
		return folder_override
	var loop := Engine.get_main_loop()
	if loop != null and loop.get_script() != null:
		return OS.get_cache_dir().path_join("clmr-range")
	return SessionStore.data_directory()


static func path() -> String:
	return folder().path_join(FILE)


## {game: best}.
static func read() -> Dictionary:
	if not FileAccess.file_exists(path()):
		return {}
	var raw := FileAccess.get_file_as_bytes(path())
	if raw.size() > 8192:
		return {}
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if not (parsed is Dictionary):
		return {}
	var sheet: Dictionary = parsed
	var out := {}
	for game: Variant in sheet:
		var v: Variant = sheet[game]
		if GAMES.has(str(game)) and (v is float or v is int):
			var best: int = type_convert(v, TYPE_INT)
			out[str(game)] = best
	return out


static func best(game: String) -> int:
	var b: int = read().get(game, 0)
	return b


## A game finished with `score`: kept when it is the best, and posted to the
## board online. True when it is a new best.
static func finished(game: String, score: int) -> bool:
	if not GAMES.has(game):
		return false
	var all := read()
	var was: int = all.get(game, 0)
	var fresh := score > was
	if fresh:
		all[game] = score
		DirAccess.make_dir_recursive_absolute(folder())
		if not SessionStore._write_atomic(path(), JSON.stringify(all, "\t")):
			push_warning("range records: could not write " + path())
	if score > 0:
		_posts.append([game, score])
		if local:
			_flush("")
	return fresh


## A station's card wants `game`'s board: asked now and then.
static func want(game: String) -> void:
	var at: float = _asked.get(game, -1e9)
	if Time.get_ticks_msec() - at < ASK_AGAIN * 1000.0:
		return
	_asked[game] = Time.get_ticks_msec()
	if not _asks.has(game):
		_asks.append(game)
	if local:
		_flush("")


## The board heard for `game` (best first), [] when none.
static func rows(game: String) -> Array:
	var got: Array = boards.get(game, [])
	return got


# ------------------------------------------------------------------ the knocks


## Every frame (main.gd): what waits goes out, the knocks are heard. Never
## from a tool, which must not knock on the real server (unless `local`).
static func frame(main: MainState) -> void:
	var loop := Engine.get_main_loop()
	var tool := loop != null and loop.get_script() != null
	if tool and not local:
		_posts.clear()
		_asks.clear()
	elif not _posts.is_empty() or not _asks.is_empty():
		var name := str(
			NetPlay.remembered().get("name", main.options.get("player_name", "MUNDELL"))
		)
		_flush(name)
	if not _knocks.is_empty():
		poll(Time.get_ticks_msec())


static func _flush(name: String) -> void:
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	var who := NetPlay.clean_name(name if name != "" else "MUNDELL")
	for post: Array in _posts:
		_send({"range": post[0], "post": [who, post[1]], "version": version})
	for game: String in _asks:
		_send({"range": game})
	_posts.clear()
	_asks.clear()


static func _server() -> Dictionary:
	if not server_override.is_empty():
		return server_override
	var list := NetBrowser.listed()
	return list[0] if not list.is_empty() and list[0] is Dictionary else {}


static func _send(info: Dictionary) -> void:
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
		_knocks.append([session, NetWire.message(NetWire.BOARD, info), false, _now])


static func poll(now_ms: float) -> void:
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
		var done := asked_at > 0.0 and now_ms - asked_at > WAIT * 1000.0
		if asked_at <= 0.0:
			k[3] = now_ms
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


static func busy() -> bool:
	return not _knocks.is_empty()


static func _heard(info: Dictionary) -> void:
	var game := str(info.get("range", ""))
	if GAMES.has(game) and info.get("rows") is Array:
		boards[game] = info["rows"]


# ------------------------------------------------------------------ the server


## A lobby server's answer to a range BOARD knock: the game's board, after
## putting in the score posted (the best a name has counts).
static func answer(info: Dictionary) -> Dictionary:
	var game := str(info.get("range", ""))
	var out := {"range": game, "rows": []}
	if not GAMES.has(game):
		return out
	var all := _read()
	var rows: Array = all.get(game, [])
	var post: Variant = info.get("post")
	var posted: Array = post if post is Array else []
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	if posted.size() == 2 and str(info.get("version", "")) == version:
		var name := NetPlay.clean_name(str(posted[0]))
		var score: int = type_convert(posted[1], TYPE_INT)
		var most: int = MOST[game]
		if name != "" and score > 0 and score <= most:
			var kept := false
			for row: Array in rows:
				if str(row[0]) == name:
					kept = true
					var was: int = type_convert(row[1], TYPE_INT)
					row[1] = maxi(was, score)
			if not kept:
				rows.append([name, score])
			rows.sort_custom(
				func(a: Array, b: Array) -> bool:
					var a_score: int = type_convert(a[1], TYPE_INT)
					var b_score: int = type_convert(b[1], TYPE_INT)
					return a_score > b_score
			)
			rows = rows.slice(0, KEEP)
			all[game] = rows
			_write(all)
	out["rows"] = rows.slice(0, SHOWN)
	return out


static func _read() -> Dictionary:
	if not FileAccess.file_exists(store):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(store))
	return parsed if parsed is Dictionary else {}


static func _write(all: Dictionary) -> void:
	var file := FileAccess.open(store, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(all))
		file.close()
