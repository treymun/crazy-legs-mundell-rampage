## THE PARTY LINE: a relay in the lobby server (lobby_server.gd), so anyone
## can host from the menu with no port opened, behind CGNAT, or in a browser
## (docs/online.md; how it works: docs/dev/multiplayer.md "The party line").
##
## A host's game still plays the one real game; the party line only passes
## bytes between it and its players, never looking past the first byte of a
## game packet. A host opens a ROOM and is given a short code (HKP-427);
## players join by the code, or from the COUNTY SERVERS list (a room with no
## password is listed). It knows nothing of modes, maps or snapshots: any
## NetPlay lobby (or anything else that speaks NetSession) rides it.
##
## It shares the lobby server's ports: `tap(session)` hands it each lobby's
## sessions (ENet and the browser's WebSocket), and their packets whose first
## byte is NetWire.RELAY_FIRST or more come here (NetSession.poll); a peer
## that opens, joins or looks for a room is then the party line's
## (NetSession.claim) and the lobby never hears of it again. `listen(port)`
## gives it a port of its own instead (the checks). The far end is
## relay_link.gd (RelayLink, a NetSession).
##
## The packets (first byte; a control's dictionary is NetWire.message's):
##   OPEN   host -> line: {relay, version, listed, summary, port, open, lan}
##   ROOM   line -> host: {code} or {refused}
##   LOOK   player -> line: {relay, code}; FOUND back: {direct: ["ip:port"]}
##          (the host's own addresses worth trying first) or {refused}
##   JOIN   player -> line: {relay, code}; IN back: {id} or {refused}
##   PEER   line -> host: {joined: id} or {left: id}
##   KICK   host -> line: {id}
##   NEWS   host -> line: {summary, listed, open, lan} (the lobby changed)
##   LIST   anyone -> line: {}; LIST back: {rooms: [{code, summary, ping}]}
##   STAT   line -> player: {host_ms} (the host's own trip, for the ping)
##   GONE   line -> anyone: {why} (the room closed; the line hangs up)
##   FROM   line -> host: FROM, the player's id (u32), the player's bytes
##   TO     host -> line: TO, channel, the player's id (u32, 0 everyone), bytes
## A player's own packets go as they are (the line knows their room) and come
## back as the host sent them, on the channel the host asked for.
class_name NetRelay
extends RefCounted

const VERSION := 1
const OPEN := 0xF0
const ROOM := 0xF1
const LOOK := 0xF2
const FOUND := 0xF3
const JOIN := 0xF4
const IN := 0xF5
const PEER := 0xF6
const KICK := 0xF7
const GONE := 0xF8
const NEWS := 0xF9
const LIST := 0xFA
const STAT := 0xFB
const FROM := 0xFC
const TO := 0xFD
const FROM_HEADER := 5
const TO_HEADER := 6
## A room's code: three letters with no vowels (no words), three digits.
const CODE_LETTERS := "BCDFGHJKLMNPQRSTVWXZ"
## What a config may set ("relay" in lobbies.json), and what it is if not:
## rooms open at once; players in one besides its host; bytes a second through
## one (both ways: a 5v5 with four people is about 200 KB/s); minutes a room
## with nobody in it stays open; the biggest packet passed on; seconds a
## player who only looked may stay; ENet peers each port keeps for the line;
## rooms open from one address at once (one joker cannot fill the line).
const DEFAULTS := {
	"rooms": 24,
	"per_address": 4,
	"players": 15,
	"room_bytes": 1000000,
	"idle_minutes": 30.0,
	"packet": 262144,
	"look_seconds": 10.0,
	"peers": 64,
}
## Seconds between the host's trip sent to its players.
const STAT_EVERY := 2.0
## Milliseconds a goodbye gets before the line hangs up on someone.
const CUT_AFTER := 600.0
## Seconds over twice its bytes a second before a room is shut.
const OVER_MOST := 10


## One room: its host, its players by the ids the host knows them by.
class Room:
	extends RefCounted
	var code := ""
	var host := 0
	## player id -> link key; the ids count up from 2 and are never reused.
	var players := {}
	var next_id := 2
	var summary := {}
	var listed := true
	## The host's own port, and whether its router opened it (`open`).
	var port := 0
	var open := false
	var lan: Array = []
	## Where the line sees the host from.
	var public := ""
	var made := 0.0
	## Since when nobody has been in it (-1: someone is).
	var empty_since := 0.0
	var joined := 0
	## Bytes passed: players to the host, the host to players; this second's.
	var up := 0
	var down := 0
	var window := 0
	var dropped := 0
	var over := 0
	var shown_over := false


## Someone on the line: the host of a room, a player in one, or one looking.
class Link:
	extends RefCounted
	var key := 0
	var role := "look"
	var room: Room = null
	var id := 0
	var since := 0.0


var limits := DEFAULTS.duplicate()
var rooms := {}
## Lines for the server's log (take_news()).
var news: PackedStringArray = []
var _sessions: Array[NetSession] = []
var _own: Array[NetSession] = []
var _links := {}
## Peers on its own ports that have not said who they are yet: key -> since.
var _strangers := {}
## [due ms, key] of goodbyes waiting to hang up.
var _cuts: Array = []
var _now := 0.0
var _second_at := 0.0
var _stat_at := 0.0
var _dice := RandomNumberGenerator.new()
## Packets and bytes passed since the last status().
var _passed := 0
var _passed_bytes := 0
var _status_at := 0.0


func _init(config := {}) -> void:
	limits.merge(config, true)
	_dice.randomize()


## Shares a session's port (a lobby's): see the top of this file.
func tap(session: NetSession) -> void:
	session.tap = self
	session.tap_slot = _sessions.size()
	_sessions.append(session)


## A port of the line's own (false: taken).
func listen(
	port: int, kind := NetSession.Transport.ENET, bind := "*", tls: TLSOptions = null
) -> bool:
	var peers: int = limits["peers"]
	var s := NetSession.host(port, kind, peers, bind, tls)
	if s == null:
		return false
	tap(s)
	_own.append(s)
	return true


## Is anyone talking through it (the server keeps its quick frame rate)?
func busy() -> bool:
	for code: String in rooms:
		var room: Room = rooms[code]
		if not room.players.is_empty():
			return true
	return false


func take_news() -> PackedStringArray:
	var out := news
	news = PackedStringArray()
	return out


# ------------------------------------------------------------------ packets


## A packet for the line (NetSession.poll hands it in).
func take(session: NetSession, from: int, bytes: PackedByteArray, channel: int) -> void:
	if bytes.is_empty():
		return
	var key := (session.tap_slot << 32) | from
	var link: Link = _links.get(key)
	var kind := bytes[0]
	if link != null and link.role == "host":
		if kind == TO:
			_to_players(link.room, bytes)
		elif kind == NEWS:
			_news(link.room, NetWire.info_of(bytes))
		elif kind == KICK:
			var id: int = NetWire.info_of(bytes).get("id", 0)
			var player: int = link.room.players.get(id, -1)
			_leave(player, "THE HOST SHOWED YOU THE DOOR")
		return
	if link != null and link.role == "player":
		if kind < NetWire.RELAY_FIRST:
			_to_host(link, bytes, channel)
		return
	if kind < NetWire.RELAY_FIRST or bytes.size() > 4096:
		return  # a game packet from someone whose room is gone; a control is small
	var info := NetWire.info_of(bytes)
	match kind:
		OPEN:
			_open(session, from, key, info)
		LOOK:
			_look(session, from, key, info)
		JOIN:
			_join(session, from, key, info)
		LIST:
			session.claim(from)
			_send(key, NetSession.CH_RELIABLE, NetWire.message(LIST, {"rooms": listing()}))
			_cut_later(key)


## A peer that hung up (NetSession, for a claimed one).
func gone(session: NetSession, from: int) -> void:
	var key := (session.tap_slot << 32) | from
	_strangers.erase(key)
	var link: Link = _links.get(key)
	if link == null:
		return
	_links.erase(key)
	if link.role == "host":
		_close(link.room, "THE HOST HUNG UP")
	elif link.role == "player" and link.room != null:
		var room := link.room
		room.players.erase(link.id)
		if room.players.is_empty():
			room.empty_since = _now
		_send(room.host, NetSession.CH_RELIABLE, NetWire.message(PEER, {"left": link.id}))


func _to_players(room: Room, bytes: PackedByteArray) -> void:
	if bytes.size() <= TO_HEADER:
		return
	var channel: int = bytes[1]
	var to := bytes.decode_u32(2)
	var payload := bytes.slice(TO_HEADER)
	var size := payload.size()
	if not _room_for(room, size, channel):
		return
	if to != 0:
		var key: int = room.players.get(to, -1)
		if key >= 0:
			room.down += size
			_send(key, channel, payload)
		return
	for id: int in room.players:
		room.down += size
		var key: int = room.players[id]
		_send(key, channel, payload)


func _to_host(link: Link, bytes: PackedByteArray, channel: int) -> void:
	var room := link.room
	if room == null or not _room_for(room, bytes.size(), channel):
		return
	var out := PackedByteArray()
	out.resize(FROM_HEADER)
	out[0] = FROM
	out.encode_u32(1, link.id)
	out.append_array(bytes)
	room.up += bytes.size()
	_send(room.host, channel, out)


## May `size` bytes pass through `room` now? Over its bytes a second, only
## what must arrive (reliable) does; too big never.
func _room_for(room: Room, size: int, channel: int) -> bool:
	var most: int = limits["packet"]
	if size > most:
		room.dropped += 1
		return false
	room.window += size
	_passed += 1
	_passed_bytes += size
	var cap: int = limits["room_bytes"]
	if room.window > cap and channel != NetSession.CH_RELIABLE and size <= NetSession.MTU_SAFE:
		room.dropped += 1
		return false
	return true


func _send(key: int, channel: int, bytes: PackedByteArray) -> void:
	var slot := key >> 32
	if slot < _sessions.size():
		_sessions[slot].send(key & 0xFFFFFFFF, channel, bytes)


func _say(key: int, kind: int, info: Dictionary) -> void:
	_send(key, NetSession.CH_RELIABLE, NetWire.message(kind, info))


func _session_of(key: int) -> NetSession:
	var slot := key >> 32
	return _sessions[slot] if slot < _sessions.size() else null


# ------------------------------------------------------------------ rooms


func _open(session: NetSession, from: int, key: int, info: Dictionary) -> void:
	session.claim(from)
	_strangers.erase(key)
	var refused := ""
	var most: int = limits["rooms"]
	var per_address: int = limits["per_address"]
	var public := session.address_of(from)
	var from_there := 0
	for code: String in rooms:
		var other: Room = rooms[code]
		if other.public == public:
			from_there += 1
	var version: int = info.get("relay", 0)
	if version != VERSION:
		refused = "THE PARTY LINE RUNS ANOTHER VERSION"
	elif rooms.size() >= most:
		refused = "THE PARTY LINE IS FULL UP. TRY AGAIN IN A BIT."
	elif from_there >= per_address:
		refused = "YOUR HOUSE HAS %d LOBBIES ON THE PARTY LINE ALREADY" % from_there
	if refused != "":
		_say(key, ROOM, {"refused": refused})
		_cut_later(key)
		return
	var room := Room.new()
	room.code = _new_code()
	room.host = key
	room.made = _now
	room.empty_since = _now
	room.public = public
	_news(room, info)
	rooms[room.code] = room
	var link := Link.new()
	link.key = key
	link.role = "host"
	link.room = room
	link.since = _now
	_links[key] = link
	_say(key, ROOM, {"code": room.code})
	news.append(
		(
			"ROOM %s OPEN (%s, %s), %d ROOMS"
			% [room.code, str(room.summary.get("mode", "?")), room.public, rooms.size()]
		)
	)


func _news(room: Room, info: Dictionary) -> void:
	var summary: Variant = info.get("summary", room.summary)
	if summary is Dictionary:
		room.summary = summary
	var listed: bool = info.get("listed", room.listed)
	var open: bool = info.get("open", room.open)
	var port: int = info.get("port", room.port)
	room.listed = listed
	room.open = open
	room.port = port
	var lan: Variant = info.get("lan", room.lan)
	if lan is Array:
		var lan_list: Array = lan
		room.lan = lan_list.slice(0, 4)


## A code no open room has.
func _new_code() -> String:
	while true:
		var code := ""
		for i in 3:
			code += CODE_LETTERS[_dice.randi() % CODE_LETTERS.length()]
		code += "-%03d" % (_dice.randi() % 1000)
		if not rooms.has(code):
			return code
	return ""


## A code as typed ("hkp427", "HKP-427 ") as the line keeps it ("" none).
static func clean_code(text: String) -> String:
	var t := text.strip_edges().to_upper().replace("-", "").replace(" ", "")
	if t.length() != 6:
		return ""
	for i in 3:
		if not CODE_LETTERS.contains(t[i]) or not t[i + 3].is_valid_int():
			return ""
	return t.substr(0, 3) + "-" + t.substr(3)


## The room a player asked for, or why not.
func _room_asked(info: Dictionary) -> Variant:
	var version: int = info.get("relay", 0)
	if version != VERSION:
		return "THE PARTY LINE RUNS ANOTHER VERSION"
	var room: Room = rooms.get(clean_code(str(info.get("code", ""))))
	if room == null:
		return "NOBODY'S ON THE PARTY LINE BY THAT CODE"
	var most: int = limits["players"]
	if room.players.size() >= most:
		return "THAT ROOM IS FULL UP"
	return room


func _look(session: NetSession, from: int, key: int, info: Dictionary) -> void:
	session.claim(from)
	_strangers.erase(key)
	var asked: Variant = _room_asked(info)
	if asked is String:
		_say(key, FOUND, {"refused": asked})
		_cut_later(key)
		return
	var room: Room = asked
	var link := Link.new()
	link.key = key
	link.role = "look"
	link.since = _now
	_links[key] = link
	_say(key, FOUND, {"direct": _direct(room, session.address_of(from))})


## The host's own addresses a player at `seen` should try before the line:
## its home ones when both come from one address (one house), else the
## outside one when its router opened the port.
func _direct(room: Room, seen: String) -> Array:
	var out: Array = []
	if room.port <= 0:
		return out
	if seen != "" and seen == room.public:
		for ip: Variant in room.lan:
			out.append("%s:%d" % [str(ip), room.port])
	elif room.open and room.public != "":
		out.append("%s:%d" % [room.public, room.port])
	return out


func _join(session: NetSession, from: int, key: int, info: Dictionary) -> void:
	session.claim(from)
	_strangers.erase(key)
	var asked: Variant = _room_asked(info)
	if asked is String:
		_links.erase(key)
		_say(key, IN, {"refused": asked})
		_cut_later(key)
		return
	var room: Room = asked
	var link: Link = _links.get(key, Link.new())
	link.key = key
	link.role = "player"
	link.room = room
	link.id = room.next_id
	link.since = _now
	room.next_id += 1
	room.players[link.id] = key
	room.joined += 1
	room.empty_since = -1.0
	_links[key] = link
	_say(room.host, PEER, {"joined": link.id})
	_say(key, IN, {"id": link.id})


## A player let go by the line (`key` -1: nobody).
func _leave(key: int, why: String) -> void:
	var link: Link = _links.get(key)
	if link == null or link.role != "player":
		return
	var room := link.room
	room.players.erase(link.id)
	if room.players.is_empty():
		room.empty_since = _now
	_say(room.host, PEER, {"left": link.id})
	link.role = "gone"
	link.room = null
	_say(key, GONE, {"why": why})
	_cut_later(key)


func _close(room: Room, why: String) -> void:
	if not rooms.has(room.code):
		return
	rooms.erase(room.code)
	for id: int in room.players:
		var key: int = room.players[id]
		var link: Link = _links.get(key)
		if link != null:
			link.role = "gone"
			link.room = null
		_say(key, GONE, {"why": why})
		_cut_later(key)
	room.players.clear()
	var host: Link = _links.get(room.host)
	if host != null:
		host.role = "gone"
		_say(room.host, GONE, {"why": why})
		_cut_later(room.host)
	var minutes := (_now - room.made) / 60000.0
	news.append(
		(
			"ROOM %s CLOSED (%s) after %.0f min, %d joined, up %s down %s, %d dropped"
			% [room.code, why, minutes, room.joined, _size(room.up), _size(room.down), room.dropped]
		)
	)


func _cut_later(key: int) -> void:
	_cuts.append([_now + CUT_AFTER, key])


## The rooms a server list shows: no password, not full.
func listing() -> Array:
	var out: Array = []
	var most: int = limits["players"]
	for code: String in rooms:
		var room: Room = rooms[code]
		if room.listed and room.players.size() < most:
			var host := _session_of(room.host)
			var ping := host.rtt(room.host & 0xFFFFFFFF) if host != null else -1.0
			out.append({"code": code, "summary": room.summary, "host_ms": ping})
	return out


# ------------------------------------------------------------------ time


## Call every frame: its own ports polled, goodbyes hung up, rooms timed out,
## the bytes a second kept, the host's trip told to its players.
func poll(now_ms: float) -> void:
	_now = now_ms
	for s in _own:
		s.poll(now_ms)  # (its packets come in through take())
		var events := s.take_events()
		for id: int in events[0]:
			_strangers[(s.tap_slot << 32) | id] = now_ms
		for id: int in events[1]:
			_strangers.erase((s.tap_slot << 32) | id)
	if not _cuts.is_empty():
		var keep: Array = []
		for cut: Array in _cuts:
			var due: float = cut[0]
			var key: int = cut[1]
			if due > now_ms:
				keep.append(cut)
				continue
			var link: Link = _links.get(key)
			if link == null or link.role == "gone":
				_links.erase(key)
				var s := _session_of(key)
				if s != null:
					s.cut(key & 0xFFFFFFFF)
		_cuts = keep
	var look_seconds: float = limits["look_seconds"]
	var look_ms := look_seconds * 1000.0
	for key: int in _strangers.keys():
		var since: float = _strangers[key]
		if now_ms - since > look_ms:
			_strangers.erase(key)
			var s := _session_of(key)
			if s != null:
				s.cut(key & 0xFFFFFFFF)
	for key: int in _links.keys():
		var link: Link = _links[key]
		if link.role == "look" and now_ms - link.since > look_ms:
			link.role = "gone"
			_cut_later(key)
	if now_ms - _second_at >= 1000.0:
		_second_at = now_ms
		_each_second()
	if now_ms - _stat_at >= STAT_EVERY * 1000.0:
		_stat_at = now_ms
		for code: String in rooms:
			var room: Room = rooms[code]
			var host := _session_of(room.host)
			if host == null or room.players.is_empty():
				continue
			var trip := host.rtt(room.host & 0xFFFFFFFF)
			for id: int in room.players:
				var key: int = room.players[id]
				_say(key, STAT, {"host_ms": trip})


func _each_second() -> void:
	var idle_minutes: float = limits["idle_minutes"]
	var idle_ms := idle_minutes * 60000.0
	var cap: int = limits["room_bytes"]
	for code: String in rooms.keys():
		var room: Room = rooms[code]
		if room.window > cap and not room.shown_over:
			room.shown_over = true
			news.append("ROOM %s OVER %s A SECOND (%s)" % [code, _size(cap), _size(room.window)])
		room.over = room.over + 1 if room.window > cap * 2 else 0
		room.window = 0
		if room.over >= OVER_MOST:
			_close(room, "TOO MUCH ON THE LINE")
		elif room.empty_since >= 0.0 and _now - room.empty_since > idle_ms:
			var minutes := maxi(1, roundi(idle_minutes))
			_close(room, "NOBODY CAME BY IN %d MINUTE%s" % [minutes, "" if minutes == 1 else "S"])


## Sends what the frame forwarded now (every session the line shares).
func flush() -> void:
	for s in _sessions:
		s.flush()


## One line for the server's status: rooms, players, what passed since the
## last one.
func status() -> String:
	var players := 0
	for code: String in rooms:
		var room: Room = rooms[code]
		players += room.players.size()
	var seconds := maxf(1.0, (_now - _status_at) / 1000.0)
	var line := (
		"PARTY LINE %d rooms, %d players, %s/s (%d packets/s)"
		% [rooms.size(), players, _size(roundi(_passed_bytes / seconds)), roundi(_passed / seconds)]
	)
	_passed = 0
	_passed_bytes = 0
	_status_at = _now
	return line


## Closes every room, telling everyone why (the server is stopping).
func close_all(why: String) -> void:
	for code: String in rooms.keys():
		var room: Room = rooms[code]
		_close(room, why)
	flush()


static func _size(bytes: int) -> String:
	if bytes >= 1048576:
		return "%.1f MB" % (bytes / 1048576.0)
	if bytes >= 1024:
		return "%.0f KB" % (bytes / 1024.0)
	return "%d B" % bytes
