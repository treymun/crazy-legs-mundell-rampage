## One knock on the lobby server's MAP SHELF (map_shelf.gd): connect to the
## server the party line runs on (servers.json's first "relay": the same
## ports, nothing new to open), send one SHELF ask, hear the answer, hang up.
## CUSTOM MAPS (custom_maps_screen.gd, map_shelf_panel.gd) polls it each
## frame:
##
##   var link := ShelfLink.put(map)          # or list(sort, find, page), fetch(code)
##   link.poll(now_ms)                       # every frame
##   link.state                              # "calling", "asked", "done", "failed"
##   link.answer / link.why                  # what the shelf said / why not
##
## A tool script never reaches the real server unless it sets `server`
## (RelayLink's rule), so checks and tours stay on this machine.
class_name ShelfLink
extends RefCounted

## Where the shelf is for a test: {"host", "port"} or {"url": "ws://..."}.
static var server := {}

var state := "calling"
var why := ""
var answer := {}
var _session: NetSession = null
var _ask := PackedByteArray()
var _began := -1.0


## Put a map up: the answer's "code" (and "new": false if it was there).
static func put(map: Dictionary) -> ShelfLink:
	var info := NetMaps.packet(map)
	info["do"] = "put"
	return ShelfLink.new(info)


## A page of the shelf: "new" or "took" first, names holding `find`.
static func list(sort := "new", find := "", page := 0) -> ShelfLink:
	return ShelfLink.new({"do": "list", "sort": sort, "find": find, "page": page})


## A map by its short code (the answer is a MAP packet's: NetMaps.unpack).
static func fetch(code: String) -> ShelfLink:
	return ShelfLink.new({"do": "get", "code": code})


## Where the shelf is ({} none known, or a tool that did not say).
static func where() -> Dictionary:
	if not server.is_empty():
		return server
	var loop := Engine.get_main_loop()
	if loop != null and loop.get_script() != null:
		return {}
	var line := RelayLink.where()
	if line.is_empty():
		return {}
	return {"host": line.get("host", ""), "port": line.get("port", 0), "url": line.get("url", "")}


func _init(info: Dictionary) -> void:
	info["protocol"] = NetWire.PROTOCOL
	_ask = NetWire.message(NetWire.SHELF, info)
	var at := where()
	if at.is_empty():
		_fail("NO SHELF TO ASK: THE GAME KNOWS NO SERVER.")
		return
	var url := str(at.get("url", ""))
	if OS.has_feature("web") or str(at.get("host", "")) == "":
		if url != "":
			_session = NetSession.join(url, 0, NetSession.Transport.WEBSOCKET)
	else:
		var port: int = at.get("port", NetSession.PORT)
		_session = NetSession.join(str(at["host"]), port)
	if _session == null:
		_fail("THE SHELF AIN'T ANSWERING. TRY AGAIN IN A BIT.")


## Every frame until it is "done" or "failed".
func poll(now_ms: float) -> void:
	if _session == null:
		return
	if _began < 0.0:
		_began = now_ms
	var packets := _session.poll(now_ms)
	if state == "calling" and _session.connected():
		_session.send(NetSession.HOST_ID, NetSession.CH_RELIABLE, _ask)
		state = "asked"
	for packet: Array in packets:
		var bytes: PackedByteArray = packet[1]
		if not bytes.is_empty() and bytes[0] == NetWire.SHELF:
			answer = NetWire.info_of(bytes)
			if answer.has("error"):
				_fail(str(answer["error"]))
			else:
				state = "done"
				close()
			return
	if state == "asked" and not _session.connected():
		_fail("THE SHELF HUNG UP. AN OLDER SERVER, MAYBE: TRY AGAIN LATER.")
	elif now_ms - _began > ShareCode.number("shelf", "wait") * 1000.0:
		_fail("THE SHELF AIN'T ANSWERING. TRY AGAIN IN A BIT.")


func busy() -> bool:
	return state == "calling" or state == "asked"


func close() -> void:
	if _session != null:
		_session.close()
	_session = null


func _fail(line: String) -> void:
	state = "failed"
	why = line
	close()
