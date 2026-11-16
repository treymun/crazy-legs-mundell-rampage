## A player map in an online lobby (docs/online.md "Custom maps"): the host
## sends it to everyone who joins, and again to everyone when it picks one,
## before anything that could start a match on it (the reliable channel keeps
## the order, so a joiner always has the map before its START).
##
##   MAP  host -> client, reliable: {"hash": sha256 of the map's canonical
##        text, "data": that text's bytes, as they are}
##
## Not packed: a map is a few KB at most (limits.bytes) and unpacking a
## stranger's bytes is one more way in. A client takes it only if it fits:
## the bytes at most limits.bytes, their hash the one said, the text a map
## UserMap.check passes and already in its canonical form. Then the map is put where the game loads
## levels (its versus copy, the one the lobby plays) and kept under
## user://maps/shared. Anything else and the client leaves the lobby with the
## reason. The lobby's settings say which map ("map" is its level id,
## "custom_map" its hash, name and author). Nothing here touches the party
## line: a MAP packet's first byte is under NetWire.RELAY_FIRST like any game
## packet, and it is far under the line's packet cap.
class_name NetMaps
extends RefCounted

## The lobby's MODE ids and the map rules each needs (UserMap.modes).
const MODE_NEEDS := {
	"bomb": "bomb",
	"hostage": "hostage",
	"tagteam": "bomb",
	"county": "county",
	"coop": "solo",
	"deathmatch": "deathmatch",
	"team": "deathmatch",
}

## The map CUSTOM MAPS' HOST ONLINE picked, for the next lobby opened.
static var pending: Dictionary = {}
## The map each hosted lobby plays (by the NetPlay's instance id).
static var hosted := {}
## The hash of the map each client took (by the NetPlay's instance id).
static var received := {}
## What a refused map was refused for (by the NetPlay's instance id).
static var refused := {}
## A custom map's name by its level id (the lobby screens show it).
static var names := {}


## The lobby just opened (main_flow.gd net_open_lobby): the map HOST ONLINE
## picked goes on it.
static func after_open(net: NetPlay) -> void:
	if pending.is_empty() or net == null:
		return
	host_map(net, pending)
	pending = {}


## Put `map` on the host's lobby and send it to everyone in it.
static func host_map(net: NetPlay, map: Dictionary) -> void:
	var id := UserMaps.register(map, true)
	hosted[net.get_instance_id()] = map
	names[id] = str(map["name"])
	net.settings["map"] = id
	net.settings["custom_map"] = {
		"hash": UserMap.hash_of(map), "name": str(map["name"]), "author": str(map["author"])
	}
	fit_mode(net)
	send_to(net, 0)
	net.send_lobby()


## The host's map to `id` (0: everyone), when the lobby is on one.
static func send_to(net: NetPlay, id: int) -> void:
	if net.session == null or not UserMap.is_custom(str(net.settings.get("map", ""))):
		return
	var map: Dictionary = hosted.get(net.get_instance_id(), {})
	if map.is_empty():
		return
	net.session.send(id, NetSession.CH_RELIABLE, NetWire.message(NetWire.MAP, packet(map)))


static func packet(map: Dictionary) -> Dictionary:
	var text := UserMap.to_text(map)
	return {"hash": UserMap.hash_text(text), "data": text.to_utf8_buffer()}


## A MAP packet's map, or why not ({"map": ...} or {"error": ...}).
static func unpack(info: Dictionary) -> Dictionary:
	var data: Variant = info.get("data")
	var hash: Variant = info.get("hash")
	if not data is PackedByteArray or not hash is String:
		return {"error": "THE MAP CAME MANGLED."}
	var raw: PackedByteArray = data
	if raw.is_empty() or raw.size() > UserMap.limit("bytes"):
		return {"error": "THE MAP CAME TOO BIG TO BE ONE."}
	var text := raw.get_string_from_utf8()
	if UserMap.hash_text(text) != str(hash):
		return {"error": "THE MAP DIDN'T MATCH ITS HASH."}
	var parsed := UserMap.parse_text(text)
	if parsed.has("error"):
		return parsed
	var map: Dictionary = parsed["map"]
	if UserMap.to_text(map) != text:
		return {"error": "THE MAP ISN'T IN THE SHED'S OWN FORM."}
	return parsed


## A client got MAP: the map put where the game loads levels and kept, or
## the lobby left with why.
static func take(net: NetPlay, info: Dictionary) -> void:
	var got := unpack(info)
	if got.has("error"):
		refused[net.get_instance_id()] = str(got["error"])
		net.leave("THE HOST'S MAP WAS NO GOOD: " + str(got["error"]))
		return
	var map: Dictionary = got["map"]
	var id := UserMaps.register(map, true)
	names[id] = str(map["name"])
	received[net.get_instance_id()] = UserMap.hash_of(map)
	UserMaps.keep_shared(map)


## The lobby's MODE fitted to a custom map (true), or the lobby is not on one
## (false; its "custom_map" goes).
static func fit_mode(net: NetPlay) -> bool:
	var id := str(net.settings.get("map", ""))
	if not UserMap.is_custom(id):
		net.settings.erase("custom_map")
		return false
	var map: Dictionary = hosted.get(net.get_instance_id(), {})
	if map.is_empty():
		return true
	var can := UserMap.modes(map)
	var mode := str(net.settings.get("mode", ""))
	if str(can.get(str(MODE_NEEDS.get(mode, "")), "no")) == "":
		return true
	var row := LobbyScreens.setting_row("mode")
	var values: Array = row[2] if not row.is_empty() else []
	for v: Variant in values:
		var each := str(v)
		if each != "tagteam" and str(can.get(str(MODE_NEEDS.get(each, "")), "no")) == "":
			net.settings["mode"] = each
			return true
	return true


## What the lobby screens call a lobby's map ("" for one not custom).
static func shown_name(id: String) -> String:
	if not UserMap.is_custom(id):
		return ""
	return str(names.get(id, "A COUNTY MAP"))
