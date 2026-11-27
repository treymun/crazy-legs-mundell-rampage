## A player map in an online lobby (docs/online.md "Custom maps"): the host
## sends it to everyone who joins, and again to everyone when it picks one,
## before anything that could start a match on it (the reliable channel keeps
## the order, so a joiner always has the map before its START).
##
##   MAP  host -> client, reliable: {"hash": sha256 of the map's canonical
##        text, "data": that text's bytes, "z": their size unpacked when
##        they go zstd'd}
##
## Packed past map_share.json's "pack_over" (4 KB; protocol 7): a v1 map is
## a few KB, a bigger one is mostly repeats. A client takes it only if it
## fits: the bytes at most limits.bytes both before and after unpacking (the
## size said is checked before anything is unpacked, so no zip bomb), their
## hash the one said, the text a map UserMap.check passes and already in its
## canonical form (ShareCode.unpack_bytes, unpack). Then the map is put where
## the game loads levels (its versus copy, the one the lobby plays) and kept
## under user://maps/shared. Anything else and the client leaves the lobby
## with the reason. The lobby's settings say which map ("map" is its level
## id, "custom_map" its hash, name and author). Nothing here touches the
## party line: a MAP packet's first byte is under NetWire.RELAY_FIRST like
## any game packet, and it is far under the line's packet cap. The map shelf
## (map_shelf.gd) sends and takes maps the same way.
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
	"team_deathmatch": "deathmatch",
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
## The MODE each hosted lobby had last (which way the host stepped MODE).
static var last_mode := {}


## The lobby just opened (main_flow.gd net_open_lobby): the map HOST ONLINE
## picked goes on it.
static func after_open(net: NetPlay) -> void:
	if pending.is_empty() or net == null:
		return
	host_map(net, pending)
	pending = {}


## Put `map` on the host's lobby and send it to everyone in it.
static func host_map(net: NetPlay, map: Dictionary) -> void:
	_register(map)
	hosted[net.get_instance_id()] = map
	net.settings["map"] = UserMap.level_id(map, true)
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
	var out := ShareCode.pack(text)
	out["hash"] = UserMap.hash_text(text)
	return out


## A MAP packet's map, or why not ({"map": ...} or {"error": ...}); `most`
## bytes at most (0: the game's own limits.bytes).
static func unpack(info: Dictionary, most := 0) -> Dictionary:
	var hash: Variant = info.get("hash")
	if not hash is String:
		return {"error": "THE MAP CAME MANGLED."}
	var got := ShareCode.unpack_bytes(info, most if most > 0 else UserMap.limit("bytes"))
	if got.has("error"):
		return got
	var raw: PackedByteArray = got["bytes"]
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
	_register(map)
	received[net.get_instance_id()] = UserMap.hash_of(map)
	UserMaps.keep_shared(map)


## Both copies of a map where the game loads levels: CAMPAIGN CO-OP plays
## the map itself (hands, lever, truck), every other mode its versus copy.
static func _register(map: Dictionary) -> void:
	for versus: bool in [false, true]:
		names[UserMaps.register(map, versus)] = str(map["name"])


## The lobby's MODE fitted to a custom map (true), or the lobby is not on one
## (false; its "custom_map" goes). A MODE the map cannot host is stepped past
## the way the host stepped (the host's lobby says why), and MAP is the map's
## own level for CAMPAIGN CO-OP, its versus copy for the rest. TAG TEAM 2V2
## keeps to its own maps; an always-open lobby never gets a player map.
static func fit_mode(net: NetPlay, changed := "map") -> bool:
	var id := str(net.settings.get("map", ""))
	var key := net.get_instance_id()
	if not UserMap.is_custom(id):
		net.settings.erase("custom_map")
		last_mode.erase(key)
		return false
	var map: Dictionary = hosted.get(key, {})
	if map.is_empty():
		return true  # a client's view of the settings: the host fits them
	var can := UserMap.modes(map)
	var offered: Array = net.modes()
	var mode := str(net.settings.get("mode", ""))
	if not _hosts(can, mode):
		var at := offered.find(mode)
		var from := offered.find(str(last_mode.get(key, mode)))
		var step := 1
		if at >= 0 and from >= 0 and posmod(at - from, offered.size()) > offered.size() / 2:
			step = -1
		var picked := ""
		for k in offered.size():
			var each := str(offered[posmod(maxi(at, 0) + k * step, offered.size())])
			if _hosts(can, each):
				picked = each
				break
		var why := str(can.get(str(MODE_NEEDS.get(mode, "")), ""))
		if changed == "mode" and why != "":
			# Said in the lobby: why the MODE asked for did not take.
			net._tell(
				"%s CAN'T HOST %s: %s" % [map["name"], LobbyScreens.value_name("mode", mode), why]
			)
		elif changed == "mode" and mode == "tagteam":
			net._tell("TAG TEAM 2V2 KEEPS TO ITS OWN THREE MAPS.")
		if picked != "":
			mode = picked
			net.settings["mode"] = mode
	last_mode[key] = mode
	net.settings["map"] = UserMap.level_id(map, mode != Modes.COOP)
	return true


static func _hosts(can: Dictionary, mode: String) -> bool:
	return mode != "tagteam" and str(can.get(str(MODE_NEEDS.get(mode, "")), "no")) == ""


## What the lobby screens call a lobby's map ("" for one not custom).
static func shown_name(id: String) -> String:
	if not UserMap.is_custom(id):
		return ""
	return str(names.get(id, "A COUNTY MAP"))
