## The lobby server's MAP SHELF (docs/online.md "Sharing maps",
## docs/dev/multiplayer.md "The map shelf"): player maps anyone put up,
## listed a page at a time (newest, most taken, or by name) and got back by
## their 8-letter code (ShareCode.short_of their hash). Asked with a SHELF
## knock on a lobby's own port (connect, ask, hear, hang up: shelf_link.gd),
## answered by `knock` from the lobby's poll. The server config's "shelf"
## ({"dir": a folder}) turns it on (lobby_server.gd).
##
##   {"do": "put", "protocol", "hash", "data", "z"}  -> {"code", "new"}
##   {"do": "list", "protocol", "sort": "new" | "took", "find", "page"}
##       -> {"rows": [[code, name, author, note, w, h, hosts, took, day], ...],
##           "page", "pages", "count"}
##   {"do": "get", "protocol", "code"}  -> {"code", "hash", "data", "z"}
##   any of them, refused  -> {"error": one plain line}
##
## Safe with strangers. A map put is held to the game's own checks
## (NetMaps.unpack: its size before and after unpacking, its hash,
## UserMap's parse and canonical form; it must host something) and its words
## to ShareCode.words_ok, before anything is kept. Only that canonical text is
## kept, as <dir>/<hash>.json: the file's name is the server's own hash of
## it, never anything a player sent, and nothing in a map is ever run. The
## caps are map_share.json's "shelf": maps on it, bytes a map, puts a day
## from an address, puts an hour from everyone, asks a minute from an
## address (a refused put counts too). Addresses are kept only as a short
## hash. <dir>/index.json is the shelf (written at once on a put, the counts
## every save_every seconds); <dir>/list.txt is it for the owner to read and
## <dir>/remove.txt takes maps off (server/map_shelf.sh), for good: a map
## taken off is banned by its hash.
class_name MapShelf
extends RefCounted

const INDEX := "index.json"
const LIST := "list.txt"
const REMOVE := "remove.txt"
const FORMAT := 1
## Seconds a knock's peer is kept for its answer to get there.
const DROP_AFTER := 5.0

var dir := ""
## Tests' overrides of map_share.json's "shelf" numbers.
var limits := {}
## code -> {code, hash, name, author, note, w, h, hosts, at, took, by}
var maps := {}
var banned := {}
## Address hash -> the times (unix seconds) of its puts in the last day,
## and of its asks in the last minute; every put in the last hour.
var puts := {}
var asks := {}
var all_puts: Array[float] = []
## Lines for the server's log (lobby_server.gd takes them).
var news: PackedStringArray = []
## Who took which map today (an address counts once a map a day).
var _took := {}
var _took_day := ""
## The codes in each order: [made at, codes].
var _order := {}
var _dirty := false
var _saved_at := 0.0
var _looked_at := -1.0e9


func _init(folder: String) -> void:
	dir = folder
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	_load()


func number(key: String) -> int:
	var value: int = limits.get(key, ShareCode.number("shelf", key))
	return value


## A SHELF knock on a lobby (NetPlay._host_message): the answer, then goodbye.
static func knock(net: NetPlay, from: int, info: Dictionary) -> void:
	net._waiting_hello.erase(from)
	if not net.player_of(from).is_empty() or net.session == null:
		return
	var reply := {"error": "THIS SERVER KEEPS NO MAP SHELF."}
	if net.shelf != null:
		var at := net.session.address_of(from)
		reply = net.shelf.answer(info, at, Time.get_unix_time_from_system())
	net.session.send(from, NetSession.CH_RELIABLE, NetWire.message(NetWire.SHELF, reply))
	net.session.poll(net._now)
	net._drop_later(from, DROP_AFTER)


## What a knock asked for, from `address` at `now` (unix seconds).
func answer(info: Dictionary, address: String, now: float) -> Dictionary:
	var by := _by(address)
	if _count(asks, by, now, 60.0) >= number("asks_a_minute"):
		return {"error": "SLOW DOWN, PARTNER. TRY AGAIN IN A MINUTE."}
	_note(asks, by, now, 60.0)
	var protocol := _int(info, "protocol", 0)
	if protocol != NetWire.PROTOCOL:
		var version := str(ProjectSettings.get_setting("application/config/version", ""))
		if protocol < NetWire.PROTOCOL:
			return {"error": "THE SHELF RUNS %s. UPDATE YOUR GAME TO USE IT." % version}
		return {"error": "THE SHELF RUNS AN OLDER GAME (%s)." % version}
	var what: Variant = info.get("do", "")
	var asked := str(what) if what is String else ""
	match asked:
		"put":
			return _put(info, by, now)
		"list":
			return _list(info, now)
		"get":
			return _fetch(info, by, now)
	return {"error": "THE SHELF DON'T KNOW WHAT YOU'RE ASKING."}


func take_news() -> PackedStringArray:
	var out := news
	news = PackedStringArray()
	return out


## Every frame of the server: the counts written now and then, and the
## owner's remove.txt looked for.
func housekeep(now: float) -> void:
	if now - _looked_at >= number("look_every"):
		_looked_at = now
		_take_off(now)
	if _dirty and now - _saved_at >= number("save_every"):
		save(now)


# ------------------------------------------------------------------ asks


func _put(info: Dictionary, by: String, now: float) -> Dictionary:
	var most := number("puts_a_day")
	if _count(puts, by, now, 86400.0) >= most:
		return {"error": "THAT'S %d MAPS TODAY FROM YOUR HOUSE. COME BACK TOMORROW." % most}
	var hour: Array[float] = []
	for t in all_puts:
		if now - t < 3600.0:
			hour.append(t)
	all_puts = hour
	if all_puts.size() >= number("puts_an_hour"):
		return {"error": "THE SHELF'S BUSY. TRY AGAIN IN A BIT."}
	all_puts.append(now)
	_note(puts, by, now, 86400.0)
	_dirty = true
	var got := NetMaps.unpack(info, number("most_bytes"))
	if got.has("error"):
		return got
	var map: Dictionary = got["map"]
	var hash := UserMap.hash_of(map)
	var code := ShareCode.short_of(hash)
	if banned.has(hash):
		return {"error": "THAT MAP WAS TAKEN OFF THE SHELF."}
	if maps.has(code):
		var there: Dictionary = maps[code]
		if str(there["hash"]) == hash:
			return {"code": code, "new": false}
		return {"error": "ANOTHER MAP HAS THAT CODE. CHANGE A LETTER AND TRY AGAIN."}
	var words := ShareCode.words_ok(map)
	if words != "":
		return {"error": words}
	var hosts := UserMap.hosts(map)
	if hosts.is_empty():
		return {"error": "THE MAP CAN'T HOST ANYTHING YET."}
	if maps.size() >= number("most_maps"):
		return {"error": "THE SHELF IS FULL UP. TRY AGAIN SOME OTHER DAY."}
	var path := _path(hash)
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return {"error": "THE SHELF COULDN'T KEEP IT."}
	file.store_string(UserMap.to_text(map))
	file.close()
	if DirAccess.rename_absolute(path + ".tmp", path) != OK:
		return {"error": "THE SHELF COULDN'T KEEP IT."}
	maps[code] = {
		"code": code,
		"hash": hash,
		"name": str(map["name"]),
		"author": str(map["author"]),
		"note": str(map["note"]),
		"w": UserMap.width(map),
		"h": UserMap.height(map),
		"hosts": Array(hosts),
		"at": int(now),
		"took": 0,
		"by": by,
	}
	_order.clear()
	news.append("SHELF: PUT UP %s %s BY %s" % [ShareCode.shown(code), map["name"], map["author"]])
	save(now)
	return {"code": code, "new": true}


func _list(info: Dictionary, now: float) -> Dictionary:
	var sort := "took" if str(info.get("sort", "")) == "took" else "new"
	var find := ""
	var asked: Variant = UserMap._clean(info.get("find", ""), number("find_most"))
	if asked != null:
		find = str(asked)
	var codes := _sorted(sort, now)
	if find != "":
		codes = codes.filter(
			func(code: String) -> bool:
				var e: Dictionary = maps[code]
				return str(e["name"]).contains(find) or str(e["author"]).contains(find)
		)
	var per := maxi(1, number("page"))
	var pages := maxi(1, ceili(codes.size() / float(per)))
	var page := clampi(_int(info, "page", 0), 0, pages - 1)
	var rows: Array = []
	for code: String in codes.slice(page * per, page * per + per):
		var e: Dictionary = maps[code]
		var at: int = e["at"]
		(
			rows
			. append(
				[
					code,
					e["name"],
					e["author"],
					e["note"],
					e["w"],
					e["h"],
					e["hosts"],
					e["took"],
					Time.get_date_string_from_unix_time(at),
				]
			)
		)
	return {
		"rows": rows,
		"page": page,
		"pages": pages,
		"count": codes.size(),
		"sort": sort,
		"find": find
	}


func _fetch(info: Dictionary, by: String, now: float) -> Dictionary:
	var code := ShareCode.clean_short(str(info.get("code", "")))
	if code == "" or not maps.has(code):
		return {"error": "NO MAP ON THE SHELF BY THAT CODE."}
	var e: Dictionary = maps[code]
	var hash := str(e["hash"])
	var text := _read(hash)
	if text == "":
		news.append("SHELF: %s WENT MISSING; OFF THE LIST" % ShareCode.shown(code))
		maps.erase(code)
		_order.clear()
		save(now)
		return {"error": "THAT MAP WENT MISSING OFF THE SHELF."}
	var day := Time.get_date_string_from_unix_time(int(now))
	if day != _took_day:
		_took_day = day
		_took.clear()
	var key := "%s|%s" % [by, code]
	if not _took.has(key):
		_took[key] = true
		var took: int = e["took"]
		e["took"] = took + 1
		_dirty = true
	var out := ShareCode.pack(text)
	out["hash"] = hash
	out["code"] = code
	return out


## The map kept under `hash`, checked against it ("" when it is not there or
## not what it should be).
func _read(hash: String) -> String:
	var path := _path(hash)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var size := file.get_length()
	file.close()
	if size <= 0 or size > number("most_bytes"):
		return ""
	var text := FileAccess.get_file_as_bytes(path).get_string_from_utf8()
	return text if UserMap.hash_text(text) == hash else ""


## The codes in an order: "new" (newest first) or "took" (most taken first,
## its counts at most save_every seconds old).
func _sorted(sort: String, now: float) -> Array:
	var kept: Array = _order.get(sort, [])
	if not kept.is_empty():
		var made: float = kept[0]
		if sort == "new" or now - made < number("save_every"):
			var codes: Array = kept[1]
			return codes
	var out: Array = maps.keys()
	var by_took := sort == "took"
	out.sort_custom(
		func(a: String, b: String) -> bool:
			var ea: Dictionary = maps[a]
			var eb: Dictionary = maps[b]
			var ta: int = ea["took"]
			var tb: int = eb["took"]
			if by_took and ta != tb:
				return ta > tb
			var aa: int = ea["at"]
			var ab: int = eb["at"]
			if aa != ab:
				return aa > ab
			return a < b
	)
	_order[sort] = [now, out]
	return out


# ------------------------------------------------------------------ limits


## A short hash of an address: the limits' key, all the shelf keeps of it.
static func _by(address: String) -> String:
	return ("clmr-shelf|" + address).sha256_text().substr(0, 12)


## How many of `by`'s times in `store` are within `span` seconds of `now`
## (older ones go).
func _count(store: Dictionary, by: String, now: float, span: float) -> int:
	var times: Array = store.get(by, [])
	var kept: Array = times.filter(func(t: float) -> bool: return now - t < span)
	if kept.is_empty():
		store.erase(by)
	else:
		store[by] = kept
	return kept.size()


## `by` asked at `now` (`span`: how long `store` keeps a time).
func _note(store: Dictionary, by: String, now: float, span: float) -> void:
	if store.size() >= number("addresses_most") and not store.has(by):
		# A crowd of addresses: forget the ones with nothing recent.
		for other: String in store.keys():
			_count(store, other, now, span)
		if store.size() >= number("addresses_most"):
			if span <= 60.0:
				store.clear()
			else:
				return  # never more than addresses_most: the hour's cap holds the rest
	var times: Array = store.get(by, [])
	times.append(now)
	store[by] = times


static func _int(info: Dictionary, key: String, fallback: int) -> int:
	var v: Variant = info.get(key, fallback)
	if v is int:
		var n: int = v
		return n
	if v is float:
		var f: float = v
		return int(f) if is_finite(f) else fallback
	return fallback


# ------------------------------------------------------------------ the files


func _path(hash: String) -> String:
	return dir.path_join(hash + ".json")


## The index read back, every entry held to what a put would have kept and
## its file there; no index (or one that does not read) is made again from
## the maps' own files.
func _load() -> void:
	var path := dir.path_join(INDEX)
	var parsed: Variant = null
	var json := JSON.new()
	if FileAccess.file_exists(path) and json.parse(FileAccess.get_file_as_string(path)) == OK:
		parsed = json.data
	if not parsed is Dictionary:
		_rebuild()
		return
	var doc: Dictionary = parsed
	var listed: Variant = doc.get("maps", [])
	var entries: Array = listed if listed is Array else []
	for v: Variant in entries:
		var e := _clean_entry(v)
		if e.is_empty() or not FileAccess.file_exists(_path(str(e["hash"]))):
			news.append("SHELF: A LISTING THAT DIDN'T HOLD UP, LEFT OUT")
			continue
		maps[str(e["code"])] = e
	var gone: Variant = doc.get("banned", [])
	var hashes: Array = gone if gone is Array else []
	for v: Variant in hashes:
		if v is String and _is_hash(str(v)):
			banned[str(v)] = true
	var kept_puts: Variant = doc.get("puts", {})
	if kept_puts is Dictionary:
		var put_dict: Dictionary = kept_puts
		for key: Variant in put_dict.keys():
			var times: Variant = put_dict[key]
			if key is String and times is Array:
				var list: Array[float] = []
				for t: Variant in times:
					if t is float or t is int:
						var stamp: float = t
						list.append(stamp)
				puts[str(key)] = list
	news.append("SHELF: %d MAPS IN %s" % [maps.size(), dir])


## The shelf made again from the files in it (each checked as a put is).
func _rebuild() -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for file_name: String in DirAccess.get_files_at(dir):
		var hash := file_name.get_basename()
		if file_name.get_extension() != "json" or not _is_hash(hash):
			continue
		var text := _read(hash)
		var parsed := UserMap.parse_text(text) if text != "" else {"error": "x"}
		var map: Dictionary = parsed.get("map", {})
		if map.is_empty() or UserMap.to_text(map) != text:
			news.append("SHELF: %s DOESN'T HOLD UP, LEFT OUT" % file_name)
			continue
		var code := ShareCode.short_of(hash)
		maps[code] = {
			"code": code,
			"hash": hash,
			"name": str(map["name"]),
			"author": str(map["author"]),
			"note": str(map["note"]),
			"w": UserMap.width(map),
			"h": UserMap.height(map),
			"hosts": Array(UserMap.hosts(map)),
			"at": FileAccess.get_modified_time(_path(hash)),
			"took": 0,
			"by": "",
		}
	news.append("SHELF: NO INDEX; %d MAPS FOUND IN %s" % [maps.size(), dir])
	_dirty = true


static func _is_hash(text: String) -> bool:
	if text.length() != 64:
		return false
	for ch in text:
		if not "0123456789abcdef".contains(ch):
			return false
	return true


## An index entry as a put would have kept it ({} when it is not one).
func _clean_entry(v: Variant) -> Dictionary:
	if not v is Dictionary:
		return {}
	var d: Dictionary = v
	var hash := str(d.get("hash", ""))
	if not _is_hash(hash) or str(d.get("code", "")) != ShareCode.short_of(hash):
		return {}
	var out := {"code": ShareCode.short_of(hash), "hash": hash}
	for key: String in ["name", "author", "note"]:
		var text: Variant = UserMap._clean(d.get(key, ""), UserMap.limit(key))
		if text == null or (key == "name" and str(text) == ""):
			return {}
		out[key] = text
	for key: String in ["w", "h"]:
		var n := _int(d, key, 0)
		if n < UserMap.limit("least") or n > UserMap.limit("most"):
			return {}
		out[key] = n
	var hosts: Array = []
	var listed: Variant = d.get("hosts", [])
	var modes: Array = listed if listed is Array else []
	for mode: Variant in modes:
		if mode is String and UserMap.MODE_ORDER.has(mode) and not hosts.has(mode):
			hosts.append(mode)
	out["hosts"] = hosts
	out["at"] = maxi(0, _int(d, "at", 0))
	out["took"] = maxi(0, _int(d, "took", 0))
	var by := str(d.get("by", ""))
	out["by"] = by if by.length() <= 12 and (by == "" or by.is_valid_hex_number()) else ""
	return out


## The index (and the owner's list.txt) written now.
func save(now: float) -> void:
	_saved_at = now
	_dirty = false
	var entries: Array = []
	for code: String in _sorted("new", now):
		entries.append(maps[code])
	var gone: Array = banned.keys()
	gone.sort()
	var doc := {"shelf": FORMAT, "maps": entries, "banned": gone, "puts": puts}
	_write(dir.path_join(INDEX), JSON.stringify(doc, "\t"))
	var lines := PackedStringArray()
	lines.append("# THE MAP SHELF: %d map(s), newest first." % entries.size())
	lines.append("# Take one off: server/map_shelf.sh root@<server address> remove <code>")
	lines.append("# CODE      PUT UP      TAKEN  NAME BY AUTHOR  (FROM)")
	for e: Dictionary in entries:
		var at: int = e["at"]
		var took: int = e["took"]
		(
			lines
			. append(
				(
					"%s  %s  %5d  %s BY %s  (%s)"
					% [
						ShareCode.shown(str(e["code"])),
						Time.get_date_string_from_unix_time(at),
						took,
						e["name"],
						e["author"] if str(e["author"]) != "" else "NOBODY SAID",
						e["by"],
					]
				)
			)
		)
	_write(dir.path_join(LIST), "\n".join(lines) + "\n")


static func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return
	file.store_string(text)
	file.close()
	DirAccess.rename_absolute(path + ".tmp", path)


## The codes in the owner's remove.txt taken off the shelf for good.
func _take_off(now: float) -> void:
	var path := dir.path_join(REMOVE)
	if not FileAccess.file_exists(path):
		return
	var text := FileAccess.get_file_as_string(path).left(65536)
	DirAccess.remove_absolute(path)
	for line: String in text.split("\n", false):
		var code := ShareCode.clean_short(line.strip_edges())
		if code == "" or not maps.has(code):
			news.append("SHELF: NO MAP %s TO TAKE OFF" % line.strip_edges().left(16))
			continue
		var e: Dictionary = maps[code]
		banned[str(e["hash"])] = true
		DirAccess.remove_absolute(_path(str(e["hash"])))
		maps.erase(code)
		news.append(
			"SHELF: TOOK %s OFF (%s BY %s)" % [ShareCode.shown(code), e["name"], e["author"]]
		)
	_order.clear()
	save(now)
