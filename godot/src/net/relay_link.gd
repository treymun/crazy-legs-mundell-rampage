## The far end of THE PARTY LINE (net_relay.gd): a NetSession that reaches
## its peers through the relay in the lobby server, so NetPlay (and anything
## else that speaks NetSession) hosts and joins through it unchanged.
##
##   var room := RelayLink.open_room(info)   # a host: `code` once `state` is "open"
##   host_session.also = room                # its players beside the direct ones
##   var line := RelayLink.join_room("HKP-427", true)   # a player
##   line.connected()                        # through (or straight to the host)
##   var ask := RelayLink.ask_rooms()        # `rooms` once `state` is "done"
##
## A host's peers are the ids the line gives its players (2, 3, ...), their
## comings and goings come from the line (take_events), drop() asks the line
## to show one the door. A player's peer is the host (NetSession.HOST_ID), as
## on a direct line. A player that may try the host's own address first
## (`look`: the desktop game, not the browser) asks the line where the host
## is, tries those addresses for DIRECT_WAIT, and only then joins through the
## line; straight through, it is a plain line to the host (`state` "direct").
class_name RelayLink
extends NetSession

enum Role { HOST, PLAYER, ASK }

## Seconds to reach the line and hear back from it.
const REACH_WAIT := 6.0
## Seconds the host's own addresses are tried before the line.
const DIRECT_WAIT := 3.0

## Where the party line is: {host, port, url} (url: the browser's wss). A
## test sets it; else the first of data/tuning/servers.json marked "relay".
static var server := {}
## A test's stand-in for the host's home addresses (NetPlay.local_addresses).
static var test_lan := PackedStringArray()

var role := Role.HOST
## "calling", "open" (a host's room: `code`), "looking", "trying" (the host's
## own addresses), "in" (a player through the line), "direct" (a player
## straight to the host), "done" (an ask answered), "refused" or "lost"
## (`why`).
var state := "calling"
var why := ""
var code := ""
## The host's own trip to the line (a player through it: its ping adds it).
var host_ms := 0.0
## An ask's answer: [{code, summary, host_ms}].
var rooms: Array = []
## Milliseconds the line took to answer an ask (or a player's first word).
var answered_ms := 0.0
var look := false
var _hello: Array = []
var _said := false
var _began := -1.0
var _came: Array[int] = []
var _went: Array[int] = []
var _players := {}
var _tries: Array[NetSession] = []
var _tries_at := 0.0
var _direct: NetSession = null
var _vid := 0

# ------------------------------------------------------------------ opening


## A room for this host on the party line (null: no line known, or it would
## not start). `info`: NetRelay's OPEN (summary, listed, port, open, lan).
static func open_room(info: Dictionary) -> RelayLink:
	var link := RelayLink.new()
	link.role = Role.HOST
	var hello := info.duplicate()
	hello["relay"] = NetRelay.VERSION
	link._hello = [NetRelay.OPEN, hello]
	return link if link._call() else null


## A player joining room `code` (null: no line known). `may_look`: try the
## host's own addresses first (over ENet only: the browser cannot).
static func join_room(room_code: String, may_look: bool) -> RelayLink:
	var link := RelayLink.new()
	link.role = Role.PLAYER
	link.code = NetRelay.clean_code(room_code)
	if not link._call():
		return null
	# Only a game that can open a plain ENet line tries the host's own address.
	link.look = may_look and link.transport == NetSession.Transport.ENET
	var hello := {"relay": NetRelay.VERSION, "code": link.code}
	link._hello = [NetRelay.LOOK if link.look else NetRelay.JOIN, hello]
	return link


## Asks the line which rooms are listed (null: no line known).
static func ask_rooms() -> RelayLink:
	var link := RelayLink.new()
	link.role = Role.ASK
	link._hello = [NetRelay.LIST, {}]
	return link if link._call() else null


## Where the line is ({} none: a tool never reaches the real one unless it
## says where).
static func where() -> Dictionary:
	if not server.is_empty():
		return server
	var loop := Engine.get_main_loop()
	if loop != null and loop.get_script() != null:
		return {}
	for entry: Variant in NetBrowser.listed():
		if entry is Dictionary:
			var e: Dictionary = entry
			var marked: bool = e.get("relay", false)
			if marked:
				var port: int = e.get("port", NetSession.PORT)
				return {
					"host": str(e.get("address", "")), "port": port, "url": str(e.get("wss", ""))
				}
	return {}


func _call() -> bool:
	var at := where()
	if at.is_empty():
		return false
	if OS.has_feature("web") or str(at.get("host", "")) == "":
		var url := str(at.get("url", ""))
		return url != "" and dial(url, 0, NetSession.Transport.WEBSOCKET)
	var port: int = at.get("port", NetSession.PORT)
	return dial(str(at["host"]), port)


# ------------------------------------------------------------------ the session


func connected() -> bool:
	match role:
		Role.HOST:
			return state == "open"
		Role.PLAYER:
			if state == "direct":
				return _direct != null and _direct.connected()
			return state == "in" and super.connected()
	return false


func id() -> int:
	return _vid if state == "in" else super.id()


func refusal() -> String:
	return why if state in ["refused", "lost"] else ""


func extra_ms() -> float:
	return host_ms if state == "in" else 0.0


## How this player reached the host: "line", "direct" or "" (not yet).
func via() -> String:
	match state:
		"in":
			return "line"
		"direct":
			return "direct"
	return ""


func send(to: int, channel: int, bytes: PackedByteArray) -> void:
	if role == Role.HOST:
		if state != "open":
			return
		var out := PackedByteArray()
		out.resize(NetRelay.TO_HEADER)
		out[0] = NetRelay.TO
		out[1] = channel
		out.encode_u32(2, to & 0xFFFFFFFF)
		out.append_array(bytes)
		super.send(NetSession.HOST_ID, channel, out)
	elif state == "direct":
		_direct.send(to, channel, bytes)
	elif state == "in":
		super.send(NetSession.HOST_ID, channel, bytes)


## A message to the line itself.
func tell(kind: int, info: Dictionary) -> void:
	super.send(NetSession.HOST_ID, NetSession.CH_RELIABLE, NetWire.message(kind, info))


## The host's lobby changed (NetRelay's NEWS: summary, listed, open, lan).
func news(info: Dictionary) -> void:
	if role == Role.HOST and state == "open":
		tell(NetRelay.NEWS, info)


func drop(to: int) -> void:
	if role == Role.HOST and _players.has(to):
		tell(NetRelay.KICK, {"id": to})


func take_events() -> Array:
	if role == Role.PLAYER:
		return _direct.take_events() if state == "direct" else super.take_events()
	super.take_events()  # (the line itself coming and going: not a peer)
	var out := [_came.duplicate(), _went.duplicate()]
	_came.clear()
	_went.clear()
	return out


func poll(now_ms: float) -> Array:
	if state == "direct":
		return _direct.poll(now_ms)
	if _began < 0.0:
		_began = now_ms
	var raw := super.poll(now_ms)
	var through := super.connected()
	if not _said and through:
		_said = true
		var kind: int = _hello[0]
		var info: Dictionary = _hello[1]
		tell(kind, info)
	if state in ["calling", "looking"] and now_ms - _began > REACH_WAIT * 1000.0:
		_fail("refused", "THE PARTY LINE AIN'T ANSWERING")
	elif _said and not through and state in ["calling", "looking", "open", "in", "trying"]:
		_fail("lost", "THE PARTY LINE HUNG UP" if why == "" else why)
	var out: Array = []
	for packet: Array in raw:
		var bytes: PackedByteArray = packet[1]
		if bytes.is_empty():
			continue
		var kind := bytes[0]
		if kind < NetWire.RELAY_FIRST:
			if state == "in":
				out.append([NetSession.HOST_ID, bytes])
		elif kind == NetRelay.FROM:
			if bytes.size() > NetRelay.FROM_HEADER:
				out.append([bytes.decode_u32(1), bytes.slice(NetRelay.FROM_HEADER)])
		else:
			_heard(kind, NetWire.info_of(bytes), now_ms)
	if state == "trying":
		_try(now_ms)
	return out


func _heard(kind: int, info: Dictionary, now_ms: float) -> void:
	match kind:
		NetRelay.ROOM:
			if info.has("refused"):
				_fail("refused", str(info["refused"]))
			else:
				code = str(info.get("code", ""))
				state = "open"
		NetRelay.FOUND:
			answered_ms = now_ms - _began
			if info.has("refused"):
				_fail("refused", str(info["refused"]))
				return
			var direct: Array = info.get("direct", [])
			_tries.clear()
			for at: Variant in direct:
				var target := NetPlay.parse_address(str(at))
				if target.is_empty():
					continue
				var port: int = target["port"]
				var attempt := NetSession.join(str(target["host"]), port)
				if attempt != null:
					_tries.append(attempt)
			if _tries.is_empty():
				_enter(now_ms)
			else:
				state = "trying"
				_tries_at = now_ms
		NetRelay.IN:
			if info.has("refused"):
				_fail("refused", str(info["refused"]))
			else:
				_vid = info.get("id", 0)
				state = "in"
		NetRelay.PEER:
			if info.has("joined"):
				var came: int = info["joined"]
				_players[came] = true
				_came.append(came)
			elif info.has("left"):
				var went: int = info["left"]
				if _players.has(went):
					_players.erase(went)
					_went.append(went)
		NetRelay.STAT:
			host_ms = info.get("host_ms", 0.0)
		NetRelay.LIST:
			answered_ms = now_ms - _began
			rooms = info.get("rooms", [])
			state = "done"
		NetRelay.GONE:
			why = str(info.get("why", ""))


## Tries the host's own addresses; the first through is kept, else the line.
func _try(now_ms: float) -> void:
	for attempt in _tries:
		attempt.poll(now_ms)
		if attempt.connected():
			_direct = attempt
			_tries.erase(attempt)
			for other in _tries:
				other.close()
			_tries.clear()
			state = "direct"
			# (NetPlay's ping reads the line's peer.)
			var line_peer := peer
			peer = _direct.peer
			line_peer.close()
			return
	if now_ms - _tries_at > DIRECT_WAIT * 1000.0:
		for other in _tries:
			other.close()
		_tries.clear()
		_enter(now_ms)


## Joins through the line (after looking).
func _enter(now_ms: float) -> void:
	state = "calling"
	_began = now_ms
	tell(NetRelay.JOIN, {"relay": NetRelay.VERSION, "code": code})


func _fail(to_state: String, text: String) -> void:
	state = to_state
	why = text
	for went: int in _players:
		_went.append(went)
	_players.clear()


func close() -> void:
	for attempt in _tries:
		attempt.close()
	_tries.clear()
	if _direct != null:
		_direct.close()
		_direct = null
		peer = null
	super.close()
