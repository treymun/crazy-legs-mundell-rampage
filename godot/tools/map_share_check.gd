## Sharing player maps (pass 16, docs/online.md "Sharing maps"): the long
## and short codes, the MAP packet packed past a few KB, THE MAP SHELF in
## process (put, list, get, the counts, the orders and the search, what it
## keeps on disk and that it survives a restart, the limits, every hostile
## put refused with nothing kept, the owner's remove.txt, a broken index
## made again), then over ENet and the browser's WebSocket on a lobby server
## on 127.0.0.1 (put, list, get; an older game's knock and HELLO told to
## update; a message past any size dropped unread), a map off the shelf
## hosted in a player's lobby and sent to a joiner, and CUSTOM MAPS' rows by
## taps. Never the real server: ShelfLink.server is this machine's.
##
##   godot --headless --path godot --script res://tools/map_share_check.gd
##       [-- server=<address:port> [put]]
##
## server= asks a lobby server already running instead (a local one, or the
## real one after a deploy): a list, an older game's knock and HELLO, and
## with `put` a test map put up, listed, got back and hosted in a lobby of
## this machine's with a joiner (take it off again with server/map_shelf.sh).
extends SceneTree

const NetPorts := preload("res://tools/net_ports.gd")
const STEP := 1.0 / 60.0

var failures: Array = []
var now := 0.0
var server: LobbyServer = null
var nets: Array = []
var main = null


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	UserMaps.folder_override = OS.get_cache_dir().path_join("clmr-map-share-maps")
	_wipe(UserMaps.folder_override)
	var where := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("server="):
			where = arg.substr(7)
	if where != "":
		await _against(where, OS.get_cmdline_user_args().has("put"))
	else:
		_codes()
		_packets()
		_shelf_here()
		await _shelf_online()
		await _screen()
	print("")
	print("MAP SHARE OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	for net: NetPlay in nets:
		net.finish()
	if server != null:
		server.free()
	UserMaps.folder_override = ""
	ShelfLink.server = {}
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)
		if OS.get_environment("GITHUB_ACTIONS") != "":
			print("::error title=%s::%s" % [get_script().resource_path.get_file(), text])


func _example(stem: String) -> Dictionary:
	var entry := UserMaps.read("res://data/user_maps/%s.json" % stem, "example")
	var map: Dictionary = entry.get("map", {})
	return map


## A copy of `map` by another name (another hash).
func _named(map: Dictionary, name: String) -> Dictionary:
	var copy := map.duplicate(true)
	copy["name"] = name
	return copy


func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
		return
	for sub: String in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(sub))
	for file_name: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file_name))


func _zeros(n: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(n)
	return out


# ------------------------------------------------------------------ codes


func _codes() -> void:
	print("CODES")
	var barn := _example("the_sale_barn")
	var forty := _example("pucketts_back_forty")
	_check(not barn.is_empty() and not forty.is_empty(), "the two example maps load")
	for map: Dictionary in [barn, forty]:
		var code := ShareCode.long_of(map)
		var back := ShareCode.from_long(code)
		_check(
			(
				code.begins_with("CLMR1:")
				and back.has("map")
				and str(back["text"]) == UserMap.to_text(map)
				and UserMap.hash_of(back["map"]) == UserMap.hash_of(map)
			),
			(
				"%s: its long code (%d letters for %d bytes) gives the same map, hash kept"
				% [map["name"], code.length(), UserMap.to_text(map).length()]
			)
		)
	var code := ShareCode.long_of(barn)
	var chatty := ""
	for i in code.length():
		chatty += code[i] + ("\n  " if i % 60 == 59 else "")
	_check(ShareCode.from_long(chatty).has("map"), "a long code broken over lines by a chat reads")
	_check(ShareCode.from_long("clmr1:" + code.substr(6)).has("map"), "its prefix in small letters")
	var middle := code.length() / 2
	var swapped := "A" if code[middle] != "A" else "B"
	var bad := [
		["a letter changed", code.left(middle) + swapped + code.substr(middle + 1)],
		["cut short", code.left(code.length() - 20)],
		["no check", code.left(code.length() - 4)],
		["odd letters", code.left(middle) + "*" + code.substr(middle + 1)],
		["not a code", "HELLO THERE"],
		["just the prefix", "CLMR1:"],
		["a newer game's", "CLMR2:" + code.substr(6)],
		["a size past a map", _long_raw(UserMap.limit("bytes") + 1, _zeros(10), "AAAA")],
		[
			"a zip bomb (1 MB of nothing, said to be 32 KB)",
			_long_raw(32768, _zeros(1 << 20).compress(FileAccess.COMPRESSION_ZSTD), "AAAA")
		],
		["not the canonical text", _long_text(UserMap.to_text(barn).replace("\n", "\r\n"))],
		["a hostile map", _long_text('{"schema": "clmr-usermap", "version": 1, "size": [999, 2]}')],
	]
	for case: Array in bad:
		var got := ShareCode.from_long(str(case[1]))
		_check(
			got.has("error") and not got.has("map"),
			"a long code refused: %s (%s)" % [case[0], got.get("error", "")]
		)
	_check(
		ShareCode.from_long("CLMR2:" + code.substr(6)).get("error", "").contains("NEWER GAME"),
		"a newer game's code says to update"
	)
	var hash := UserMap.hash_of(barn)
	var short := ShareCode.short_of(hash)
	var letters_ok := short.length() == 8
	for ch in short:
		letters_ok = letters_ok and ShareCode.LETTERS.contains(ch)
	_check(letters_ok, "a short code is 8 letters of its own (%s)" % ShareCode.shown(short))
	_check(
		ShareCode.short_of(UserMap.hash_of(forty)) != short,
		"the two examples have different short codes"
	)
	var shown := ShareCode.shown(short)
	_check(
		(
			shown.length() == 9
			and shown[4] == "-"
			and ShareCode.clean_short(shown) == short
			and ShareCode.clean_short(shown.to_lower().replace("-", " ")) == short
		),
		"a short code typed with its dash, small letters or a space reads back"
	)
	_check(
		ShareCode.clean_short("0OI1-LLLL") == "0011-1111".replace("-", ""),
		"O, I and L typed are read as 0, 1 and 1"
	)
	for typed: String in ["7KQ2-M9X", "7KQ2-M9XDD", "7KQ2-M9XU", "", "7KQ2_M9XD"]:
		_check(ShareCode.clean_short(typed) == "", "not a short code: '%s'" % typed)
	_check(
		ShareCode.words_ok(barn) == "" and ShareCode.words_ok(forty) == "",
		"the examples' words are fit for the shelf"
	)
	_check(ShareCode.words_ok(_named(barn, "PUSH IT GOOD")) == "", "PUSH IT GOOD is fine")
	for name: String in ["SHIT CREEK", "5H1T CREEK", "HOLY SHITE"]:
		_check(ShareCode.words_ok(_named(barn, name)) != "", "the shelf won't print %s" % name)
	var authored := barn.duplicate(true)
	authored["author"] = "BIG FUCKER"
	_check(ShareCode.words_ok(authored).contains("AUTHOR"), "nor an author like that")


## A long code of `size` said and `packed` bytes, with `check`.
func _long_raw(size: int, packed: PackedByteArray, check: String) -> String:
	var body := PackedByteArray([(size >> 16) & 255, (size >> 8) & 255, size & 255])
	body.append_array(packed)
	var b64 := Marshalls.raw_to_base64(body).replace("+", "-").replace("/", "_")
	return "CLMR1:" + b64.replace("=", "") + check


## A long code of any text, its check right (so only the text is wrong).
func _long_text(text: String) -> String:
	var bytes := text.to_utf8_buffer()
	var check := ShareCode.short_of(text.sha256_text()).left(4)
	return _long_raw(bytes.size(), bytes.compress(FileAccess.COMPRESSION_ZSTD), check)


# ------------------------------------------------------------------ packets


func _packets() -> void:
	print("THE MAP PACKET")
	var barn := _example("the_sale_barn")
	var text := UserMap.to_text(barn)
	var packet := NetMaps.packet(barn)
	var data: PackedByteArray = packet["data"]
	_check(
		packet.has("z") and int(packet["z"]) == text.length() and data.size() < text.length() / 2,
		"a map past 4 KB goes zstd'd (%d bytes for %d)" % [data.size(), text.length()]
	)
	var got := NetMaps.unpack(packet)
	_check(
		got.has("map") and UserMap.hash_of(got["map"]) == UserMap.hash_of(barn),
		"and unpacks to the same map"
	)
	var small := UserMap.blank(12, 12, "WEE")
	var small_packet := NetMaps.packet(small)
	_check(
		not small_packet.has("z") and NetMaps.unpack(small_packet).has("map"),
		"a small map goes as it is"
	)
	var most := UserMap.limit("bytes")
	var hash := str(packet["hash"])
	var bomb := _zeros(10 << 20).compress(FileAccess.COMPRESSION_ZSTD)
	var cases := [
		["a zip bomb (10 MB of nothing said to be a map)", {"hash": hash, "data": bomb, "z": most}],
		["a size past the cap", {"hash": hash, "data": data, "z": most + 1}],
		["a size that is text", {"hash": hash, "data": data, "z": "4400"}],
		["a size below nothing", {"hash": hash, "data": data, "z": -5}],
		["a size a byte short", {"hash": hash, "data": data, "z": text.length() - 1}],
		["a size a byte long", {"hash": hash, "data": data, "z": text.length() + 1}],
		["bytes not packed, said packed", {"hash": hash, "data": text.to_utf8_buffer(), "z": 9000}],
		["packed bytes past the cap", {"hash": hash, "data": _zeros(most + 1), "z": 100}],
		["packed, its hash wrong", {"hash": "0".repeat(64), "data": data, "z": packet["z"]}],
	]
	for case: Array in cases:
		var refused := NetMaps.unpack(case[1])
		_check(
			refused.has("error") and not refused.has("map"),
			"a MAP packet refused: %s (%s)" % [case[0], refused.get("error", "")]
		)


# ------------------------------------------------------------------ the shelf here


func _put(shelf: MapShelf, map: Dictionary, from: String, t: float) -> Dictionary:
	var info := NetMaps.packet(map)
	info["do"] = "put"
	info["protocol"] = NetWire.PROTOCOL
	return shelf.answer(info, from, t)


func _ask(shelf: MapShelf, info: Dictionary, from: String, t: float) -> Dictionary:
	var asked := info.duplicate()
	asked["protocol"] = NetWire.PROTOCOL
	return shelf.answer(asked, from, t)


func _files(dir: String) -> int:
	return (
		Array(DirAccess.get_files_at(dir))
		. filter(
			func(f: String) -> bool: return f.get_extension() == "json" and f != MapShelf.INDEX
		)
		. size()
	)


func _shelf_here() -> void:
	print("THE MAP SHELF (IN PROCESS)")
	var dir := OS.get_cache_dir().path_join("clmr-map-share-shelf")
	_wipe(dir)
	var barn := _example("the_sale_barn")
	var forty := _example("pucketts_back_forty")
	var t := 1.8e9
	var shelf := MapShelf.new(dir)
	var put := _put(shelf, barn, "10.0.0.1", t)
	var barn_code := ShareCode.short_of(UserMap.hash_of(barn))
	_check(
		str(put.get("code", "")) == barn_code and put.get("new", false) == true,
		"a map put up gets its code (%s)" % ShareCode.shown(str(put.get("code", put)))
	)
	var kept := dir.path_join(UserMap.hash_of(barn) + ".json")
	_check(
		FileAccess.get_file_as_string(kept) == UserMap.to_text(barn),
		"the shelf keeps its canonical text, named by its own hash"
	)
	var again := _put(shelf, barn, "10.0.0.2", t + 1)
	_check(
		str(again.get("code", "")) == barn_code and again.get("new", true) == false,
		"the same map again: the same code, not a second copy"
	)
	_put(shelf, forty, "10.0.0.1", t + 60)
	var listed := _ask(shelf, {"do": "list"}, "10.0.0.3", t + 61)
	var rows: Array = listed.get("rows", [])
	_check(
		rows.size() == 2 and str(rows[0][1]) == str(forty["name"]) and int(listed["count"]) == 2,
		"the list, newest first (%s)" % [rows.map(func(r: Array) -> String: return str(r[1]))]
	)
	var fetched := _ask(
		shelf, {"do": "get", "code": ShareCode.shown(barn_code)}, "10.0.0.3", t + 62
	)
	var unpacked := NetMaps.unpack(fetched)
	_check(
		unpacked.has("map") and UserMap.hash_of(unpacked["map"]) == UserMap.hash_of(barn),
		"got back by its code (as typed, with the dash): the same map"
	)
	_ask(shelf, {"do": "get", "code": barn_code}, "10.0.0.3", t + 63)
	_ask(shelf, {"do": "get", "code": barn_code}, "10.0.0.4", t + 64)
	var took := _ask(shelf, {"do": "list", "sort": "took"}, "10.0.0.3", t + 65)
	var took_rows: Array = took.get("rows", [])
	_check(
		took_rows.size() == 2 and str(took_rows[0][0]) == barn_code and int(took_rows[0][7]) == 2,
		"MOST TAKEN: taken twice (once a house a day), first"
	)
	var found := _ask(shelf, {"do": "list", "find": "barn"}, "10.0.0.3", t + 66)
	var found_rows: Array = found.get("rows", [])
	_check(
		found_rows.size() == 1 and str(found_rows[0][0]) == barn_code,
		"a search by name finds only the barn"
	)
	var nothing := _ask(shelf, {"do": "get", "code": "ZZZZ-ZZZZ"}, "10.0.0.3", t + 67)
	_check(str(nothing.get("error", "")).contains("NO MAP"), "an unknown code: %s" % nothing)
	shelf.save(t + 70)
	var again_shelf := MapShelf.new(dir)
	var e: Dictionary = again_shelf.maps.get(barn_code, {})
	_check(
		again_shelf.maps.size() == 2 and int(e.get("took", 0)) == 2,
		"a restart: the shelf and its counts are still there"
	)
	_check(
		FileAccess.get_file_as_string(dir.path_join(MapShelf.LIST)).contains(
			ShareCode.shown(barn_code)
		),
		"list.txt has it for the owner"
	)
	_limits(again_shelf, barn, dir, t + 100)
	_hostile(dir, barn, t + 10000)
	_owner(dir, barn, forty, t + 20000)


func _limits(shelf: MapShelf, barn: Dictionary, dir: String, t: float) -> void:
	var day := ShareCode.number("shelf", "puts_a_day")
	var said := ""
	for i in day:
		said = str(_put(shelf, _named(barn, "RATE TEST %d" % i), "10.9.9.9", t + i).get("code", ""))
	var past := _put(shelf, _named(barn, "RATE TEST X"), "10.9.9.9", t + day)
	_check(
		said != "" and str(past.get("error", "")).contains("TOMORROW"),
		"%d puts a day from one house, then: %s" % [day, past.get("error", past)]
	)
	var later := _put(shelf, _named(barn, "RATE TEST X"), "10.9.9.9", t + 86400.0 + day)
	_check(later.has("code"), "a day later it may put again")
	var per := ShareCode.number("shelf", "asks_a_minute")
	var last := {}
	for i in per + 1:
		last = _ask(shelf, {"do": "list"}, "10.7.7.7", t + 90000.0 + i * .1)
	_check(
		str(last.get("error", "")).contains("SLOW DOWN"),
		"%d asks a minute from one house, then: %s" % [per, last.get("error", "")]
	)
	_check(
		_ask(shelf, {"do": "list"}, "10.7.7.7", t + 90061.0).has("rows"),
		"a minute later it is answered again"
	)
	var busy_dir := OS.get_cache_dir().path_join("clmr-map-share-busy")
	_wipe(busy_dir)
	var busy := MapShelf.new(busy_dir)
	busy.limits["puts_an_hour"] = 3
	var answers: Array = []
	for i in 4:
		answers.append(_put(busy, _named(barn, "BUSY %d" % i), "10.1.1.%d" % i, t + i))
	_check(
		answers[2].has("code") and str(answers[3].get("error", "")).contains("BUSY"),
		"the puts an hour from everybody are capped: %s" % answers[3].get("error", "")
	)
	var full := MapShelf.new(dir)
	full.limits["most_maps"] = full.maps.size()
	var over := _put(full, _named(barn, "ONE TOO MANY"), "10.2.2.2", t)
	_check(str(over.get("error", "")).contains("FULL"), "a full shelf: %s" % over.get("error", ""))


func _hostile(dir: String, barn: Dictionary, t: float) -> void:
	var shelf := MapShelf.new(dir)
	var before := _files(dir)
	var count := shelf.maps.size()
	var good := NetMaps.packet(barn)
	var text := UserMap.to_text(barn)
	var bomb := _zeros(10 << 20).compress(FileAccess.COMPRESSION_ZSTD)
	var blank := UserMap.blank(16, 16, "NOTHING HERE")
	var rude := _named(barn, "SHIT CREEK")
	var cases := [
		["over the size", {"do": "put", "hash": good["hash"], "data": _zeros(70000)}],
		["bad text", {"do": "put", "hash": "x", "data": PackedByteArray([1, 2, 3, 4])}],
		["not canonical", _packed(text.replace("\n", "\r\n"))],
		[
			"a wrong hash",
			{"do": "put", "hash": "0".repeat(64), "data": good["data"], "z": good["z"]}
		],
		["a zip bomb", {"do": "put", "hash": good["hash"], "data": bomb, "z": 65536}],
		[
			"a size past the cap",
			{"do": "put", "hash": good["hash"], "data": good["data"], "z": 70000}
		],
		["a hostile map", _packed('{"schema": "clmr-usermap", "version": 1, "size": [999, 2]}')],
		["a map that hosts nothing", _packed(UserMap.to_text(blank))],
		["a name the county won't print", _packed(UserMap.to_text(rude))],
		["no data at all", {"do": "put"}],
		["data that is a word", {"do": "put", "hash": good["hash"], "data": "MAP"}],
	]
	var i := 0
	for case: Array in cases:
		i += 1
		var info: Dictionary = case[1]
		info["protocol"] = NetWire.PROTOCOL
		if not info.has("do"):
			info["do"] = "put"
		var got := shelf.answer(info, "10.66.0.%d" % i, t + i)
		_check(
			got.has("error") and not got.has("code"),
			"a put refused: %s (%s)" % [case[0], got.get("error", "")]
		)
	_check(
		_files(dir) == before and shelf.maps.size() == count,
		"nothing refused was kept (%d files, %d maps)" % [_files(dir), shelf.maps.size()]
	)
	var odd := [
		["an older game", {"do": "list", "protocol": 6}, "UPDATE YOUR GAME"],
		["a newer game", {"do": "list", "protocol": 8}, "OLDER GAME"],
		["no protocol", {"do": "list"}, "UPDATE YOUR GAME"],
		["a protocol that is text", {"do": "list", "protocol": "7"}, "UPDATE"],
		["an ask nobody knows", {"do": "burn", "protocol": 7}, "DON'T KNOW"],
		["an ask that is a number", {"do": 5, "protocol": 7}, "DON'T KNOW"],
		["a code that is a list", {"do": "get", "code": [1, 2], "protocol": 7}, "NO MAP"],
	]
	for case: Array in odd:
		var got := shelf.answer(case[1], "10.67.0.1", t + 100 + i)
		i += 1
		_check(
			str(got.get("error", "")).contains(str(case[2])),
			"%s: %s" % [case[0], got.get("error", got)]
		)
	var weird := shelf.answer(
		{"do": "list", "protocol": 7, "page": "two", "find": ["x"], "sort": 9}, "10.67.0.2", t + 200
	)
	_check(
		weird.has("rows") and int(weird["page"]) == 0,
		"a list asked with nonsense for its page, search and order: the first page"
	)
	var deep := shelf.answer(
		{"do": "list", "protocol": 7, "page": 99999, "find": "ZZZZZZ"}, "10.67.0.3", t + 201
	)
	_check(
		deep.has("rows") and (deep["rows"] as Array).is_empty(),
		"a page past the end of a search finding nothing: none"
	)


## A shelf put of `text` as a map, its hash right.
func _packed(text: String) -> Dictionary:
	var out := ShareCode.pack(text)
	out["hash"] = UserMap.hash_text(text)
	out["do"] = "put"
	return out


func _owner(dir: String, barn: Dictionary, forty: Dictionary, t: float) -> void:
	var shelf := MapShelf.new(dir)
	var code := ShareCode.short_of(UserMap.hash_of(barn))
	var file := FileAccess.open(dir.path_join(MapShelf.REMOVE), FileAccess.WRITE)
	file.store_string(ShareCode.shown(code) + "\nNOT-ACODE\n")
	file.close()
	shelf.housekeep(t)
	var kept := dir.path_join(UserMap.hash_of(barn) + ".json")
	_check(
		(
			not shelf.maps.has(code)
			and not FileAccess.file_exists(kept)
			and not FileAccess.file_exists(dir.path_join(MapShelf.REMOVE))
		),
		"the owner's remove.txt takes a map off (its file too) and is cleared"
	)
	var news := " ".join(shelf.take_news())
	_check(news.contains("TOOK") and news.contains("NO MAP"), "the log says so: %s" % news)
	var back := _put(shelf, barn, "10.3.3.3", t + 1)
	_check(
		str(back.get("error", "")).contains("TAKEN OFF"),
		"a map taken off stays off: %s" % back.get("error", "")
	)
	_check(
		not FileAccess.get_file_as_string(dir.path_join(MapShelf.LIST)).contains(
			ShareCode.shown(code)
		),
		"and is off list.txt"
	)
	# A broken index: made again from the maps' files, a stray file left out.
	var junk := FileAccess.open(dir.path_join(MapShelf.INDEX), FileAccess.WRITE)
	junk.store_string("{not json")
	junk.close()
	var stray := FileAccess.open(dir.path_join("evil.json"), FileAccess.WRITE)
	stray.store_string(UserMap.to_text(_named(forty, "EVIL TWIN")))
	stray.close()
	var liar_hash := UserMap.hash_of(_named(forty, "LIAR"))
	var liar := FileAccess.open(dir.path_join(liar_hash + ".json"), FileAccess.WRITE)
	liar.store_string(UserMap.to_text(forty))
	liar.close()
	var rebuilt := MapShelf.new(dir)
	var forty_code := ShareCode.short_of(UserMap.hash_of(forty))
	_check(
		(
			rebuilt.maps.has(forty_code)
			and not rebuilt.maps.has(ShareCode.short_of(liar_hash))
			and rebuilt.maps.size() > 5
		),
		(
			"a broken index is made again from the maps (%d), a file not named by its hash left out"
			% rebuilt.maps.size()
		)
	)
	var tampered := FileAccess.open(dir.path_join(MapShelf.INDEX), FileAccess.WRITE)
	var entry: Dictionary = rebuilt.maps[forty_code].duplicate()
	entry["name"] = "<script>"
	tampered.store_string(JSON.stringify({"shelf": 1, "maps": [entry]}))
	tampered.close()
	var checked := MapShelf.new(dir)
	_check(checked.maps.is_empty(), "an index entry with odd letters is left out")
	DirAccess.remove_absolute(dir.path_join(liar_hash + ".json"))


# ------------------------------------------------------------------ online


func _pump(frames := 1) -> void:
	for i in frames:
		now += STEP * 1000.0
		if server != null:
			server.frame(now, STEP)
		for net: NetPlay in nets:
			net.poll(now)
		OS.delay_msec(2)


func _wait(what: Callable, most := 400) -> bool:
	for i in most:
		if what.call():
			return true
		_pump()
	return what.call()


func _link(link: ShelfLink) -> ShelfLink:
	_wait(
		func() -> bool:
			link.poll(now)
			return not link.busy(),
		700
	)
	return link


## A raw knock: one message of `kind` sent, the first packet back ({} none).
func _knock(port: int, kind: int, info: Dictionary, raw := PackedByteArray()) -> Dictionary:
	return _knock_at("127.0.0.1", port, kind, info, raw)


func _knock_at(
	host: String, port: int, kind: int, info: Dictionary, raw := PackedByteArray()
) -> Dictionary:
	var s := NetSession.join(host, port)
	var heard := {}
	var sent := false
	for i in 240:
		_pump()
		for packet: Array in s.poll(now):
			var bytes: PackedByteArray = packet[1]
			if not bytes.is_empty():
				heard = {"kind": int(bytes[0]), "info": NetWire.info_of(bytes)}
		if not heard.is_empty():
			break
		if not sent and s.connected():
			var message := raw if not raw.is_empty() else NetWire.message(kind, info)
			s.send(NetSession.HOST_ID, NetSession.CH_RELIABLE, message)
			sent = true
	s.close()
	return heard


func _shelf_online() -> void:
	print("THE MAP SHELF ON A LOBBY SERVER (127.0.0.1)")
	var dir := OS.get_cache_dir().path_join("clmr-map-share-server")
	_wipe(dir)
	var port := NetPorts.pick("map_share_check", [0, 1], [3000])
	var ws_port := 0
	for k in 20:
		var config := {
			"bind": "127.0.0.1",
			"shelf": {"dir": dir},
			"lobbies":
			[
				{
					"port": port + k,
					"ws_port": port + k + 3000,
					"lobby_name": "SHELF TEST",
					"mode": "bomb",
					"map": "grainyard",
				}
			]
		}
		server = LobbyServer.new(config, {"difficulty": 1})
		if not server.rooms.is_empty() and server.rooms[0].net.session.also != null:
			port += k
			ws_port = port + 3000
			break
		server.free()
		server = null
	_check(server != null and server.shelf != null, "a lobby server opens with a shelf")
	if server == null:
		return
	root.add_child(server)
	server.set_process(false)
	ShelfLink.server = {"host": "127.0.0.1", "port": port}
	var barn := _example("the_sale_barn")
	var put := _link(ShelfLink.put(barn))
	var code := str(put.answer.get("code", ""))
	_check(
		put.state == "done" and code == ShareCode.short_of(UserMap.hash_of(barn)),
		"PUT over ENet: %s %s" % [put.state, ShareCode.shown(code) if code != "" else put.why]
	)
	var listed := _link(ShelfLink.list())
	var rows: Array = listed.answer.get("rows", [])
	_check(
		listed.state == "done" and rows.size() == 1 and str(rows[0][0]) == code,
		"LIST over ENet: %d row(s)" % rows.size()
	)
	var got := _link(ShelfLink.fetch(ShareCode.shown(code)))
	var map := NetMaps.unpack(got.answer)
	_check(
		(
			got.state == "done"
			and map.has("map")
			and UserMap.hash_of(map["map"]) == UserMap.hash_of(barn)
		),
		"GET over ENet: the same map, checked as a lobby's MAP is"
	)
	ShelfLink.server = {"url": "ws://127.0.0.1:%d" % ws_port}
	var by_ws := _link(ShelfLink.list("took"))
	_check(
		by_ws.state == "done" and (by_ws.answer.get("rows", []) as Array).size() == 1,
		"LIST over the browser's WebSocket: %s" % (by_ws.why if by_ws.why != "" else "answered")
	)
	ShelfLink.server = {"host": "127.0.0.1", "port": port}
	var missing := _link(ShelfLink.fetch("ZZZZZZZZ"))
	_check(
		missing.state == "failed" and missing.why.contains("NO MAP"),
		"an unknown code over ENet: %s" % missing.why
	)
	# An older game knocking and joining.
	var old_knock := _knock(port, NetWire.SHELF, {"do": "list", "protocol": 6})
	var old_info: Dictionary = old_knock.get("info", {})
	_check(
		str(old_info.get("error", "")).contains("UPDATE YOUR GAME"),
		"an older game's shelf knock is told to update: %s" % old_info.get("error", old_knock)
	)
	var old_hello := _knock(
		port, NetWire.HELLO, {"protocol": NetWire.PROTOCOL - 1, "version": "3.14.0", "name": "OLD"}
	)
	var hello_info: Dictionary = old_hello.get("info", {})
	_check(
		(
			int(old_hello.get("kind", 0)) == NetWire.WELCOME
			and str(hello_info.get("refused", "")).contains("UPDATE YOUR GAME")
		),
		"a protocol 6 game's HELLO: %s" % hello_info.get("refused", old_hello)
	)
	var big := NetWire.message(
		NetWire.SHELF, {"do": "list", "protocol": 7, "find": "X".repeat(300000)}
	)
	var dropped := _knock(port, NetWire.SHELF, {}, big)
	_check(
		dropped.is_empty() or int(dropped.get("kind", 0)) != NetWire.SHELF,
		"a message past any message's size (%d KB) is dropped unread" % (big.size() / 1024)
	)
	_check(
		FileAccess.file_exists(dir.path_join(MapShelf.INDEX)), "the server's shelf wrote its index"
	)
	await _host_it(port + 1, map.get("map", {}))


## A lobby server already running at `where` (address:port).
func _against(where: String, put_one: bool) -> void:
	var host := where.get_slice(":", 0)
	var port := where.get_slice(":", 1).to_int()
	print("THE MAP SHELF AT %s" % where)
	ShelfLink.server = {"host": host, "port": port}
	var listed := _link(ShelfLink.list())
	_check(
		listed.state == "done",
		(
			"LIST: %s"
			% (
				"%d map(s) on the shelf" % int(listed.answer.get("count", 0))
				if listed.state == "done"
				else listed.why
			)
		)
	)
	var old_knock := _knock_at(host, port, NetWire.SHELF, {"do": "list", "protocol": 6})
	var old_info: Dictionary = old_knock.get("info", {})
	_check(
		str(old_info.get("error", "")).contains("UPDATE YOUR GAME"),
		"an older game's knock: %s" % old_info.get("error", old_knock)
	)
	var hello := {"protocol": NetWire.PROTOCOL - 1, "version": "3.14.0", "name": "OLD"}
	var old_hello := _knock_at(host, port, NetWire.HELLO, hello)
	var hello_info: Dictionary = old_hello.get("info", {})
	_check(
		str(hello_info.get("refused", "")).contains("UPDATE YOUR GAME"),
		"a protocol 6 game's HELLO: %s" % hello_info.get("refused", old_hello)
	)
	if not put_one:
		return
	var stamp := str(Time.get_unix_time_from_system()).sha256_text().substr(0, 6).to_upper()
	var map := _named(_example("the_sale_barn"), "SHELF CHECK " + stamp)
	var put := _link(ShelfLink.put(map))
	var code := str(put.answer.get("code", ""))
	_check(
		put.state == "done" and code != "",
		"PUT: %s" % (ShareCode.shown(code) if code != "" else put.why)
	)
	var found := _link(ShelfLink.list("new", "SHELF CHECK " + stamp))
	var rows: Array = found.answer.get("rows", [])
	_check(rows.size() == 1 and str(rows[0][0]) == code, "LIST by its name finds it")
	var got := _link(ShelfLink.fetch(ShareCode.shown(code)))
	var back := NetMaps.unpack(got.answer)
	_check(
		back.has("map") and UserMap.hash_of(back["map"]) == UserMap.hash_of(map),
		"GET by its code: the same map"
	)
	await _host_it(NetPorts.pick("map_share_check_live", [0, 2, 4]), back.get("map", {}))
	print(
		(
			"  (take it off: server/map_shelf.sh root@<server address> remove %s)"
			% ShareCode.shown(code)
		)
	)


## The map off the shelf hosted in a player's own lobby and sent to a joiner.
func _host_it(port: int, map: Dictionary) -> void:
	if map.is_empty():
		_check(false, "no map came off the shelf to host")
		return
	var host: NetPlay = null
	for k in 20:
		host = NetPlay.host_lobby(port + k * 2, "TREY", {}, false, "127.0.0.1")
		if host != null:
			port += k * 2
			break
	_check(host != null, "a player hosts a lobby")
	if host == null:
		return
	nets.append(host)
	NetMaps.host_map(host, map)
	var vs := UserMap.level_id(map, true)
	_check(
		str(host.settings["map"]) == vs, "with the shelf's map on it (%s)" % host.settings["map"]
	)
	LevelData.preview.erase(vs)
	LevelData.preview.erase(UserMap.level_id(map))
	var client := NetPlay.join_lobby("127.0.0.1:%d" % port, "ALICE")
	nets.append(client)
	_wait(func() -> bool: return NetMaps.received.has(client.get_instance_id()), 500)
	_check(
		(
			client.phase == "lobby"
			and str(NetMaps.received.get(client.get_instance_id(), "")) == UserMap.hash_of(map)
			and NetMaps.packet(map).has("z")
		),
		"a joiner gets it in a packed MAP packet, its hash checked (%s)" % client.phase
	)
	client.leave()
	host.leave()
	_pump(30)
	await process_frame


# ------------------------------------------------------------------ the screen


func _tap(p: Vector2i) -> void:
	var rect: Rect2 = main.viewport_rect()
	var at := rect.position + (Vector2(p) + Vector2(.5, .5)) * rect.size / Vector2(320, 200)
	for pressed in [true, false]:
		var finger := InputEventScreenTouch.new()
		finger.index = 0
		finger.position = at
		finger.pressed = pressed
		main._input(finger)


func _screen() -> void:
	print("CUSTOM MAPS: THE SHELF, A CODE, SHARE IT")
	if server == null:
		_check(false, "no server for the screen's shelf")
		return
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	_wipe(UserMaps.folder_override)
	main.state = "maps"
	main.render()
	var screen: CustomMapsScreen = main.ui.shown()
	_check(screen != null and main.state == "maps", "CUSTOM MAPS opens")
	if screen == null:
		return
	var first := UserMapPlay.ROWS_BEFORE
	_tap(CustomMapsScreen.LIST.position + Vector2i(40, 2 + CustomMapsScreen.ROW_H + 8))
	_check(UserMapPlay.row == 1, "a tap on THE MAP SHELF picks it (row %d)" % UserMapPlay.row)
	_tap(screen.plate_rect(1).get_center())
	_check(screen.shelf.open, "its plate opens the shelf")
	_wait(
		func() -> bool:
			screen.shelf.poll(now)
			return not screen.shelf.busy(),
		700
	)
	main.render()
	_check(
		screen.shelf.rows.size() == 1 and screen.shelf.state.begins_with("PAGE 1 OF 1"),
		"the shelf's page shows the map put up (%s)" % screen.shelf.state
	)
	var before := UserMapPlay.entries.size()
	_tap(screen.row_rect(0, 0).get_center())  # a tap on the picked row takes it
	_wait(
		func() -> bool:
			screen.shelf.poll(now)
			return not screen.shelf.busy(),
		700
	)
	var barn := _example("the_sale_barn")
	var picked := screen._entry()
	_check(
		(
			not screen.shelf.open
			and UserMapPlay.entries.size() == before
			and str(picked.get("hash", "")) == UserMap.hash_of(barn)
		),
		"TAKE IT HOME: the list picks it (the example, already there): %s" % UserMapPlay.note
	)
	var forty := _named(_example("pucketts_back_forty"), "CODE CREEK")
	screen.shelf.take_code(ShareCode.long_of(forty))
	picked = screen._entry()
	_check(
		(
			str(picked.get("hash", "")) == UserMap.hash_of(forty)
			and str(picked.get("source", "")) == "shared"
			and UserMapPlay.entries.size() == before + 1
		),
		"a long code pasted: the map is on the list, picked (%s)" % UserMapPlay.note
	)
	main.render()
	var actions: Array = screen._actions()
	_check(actions.has("share") and actions.has("host"), "a map offers SHARE IT and HOST ONLINE")
	UserMapPlay.action = actions.find("share")
	screen._do("share")
	_check(
		screen.shelf.armed == UserMap.hash_of(forty) and UserMapPlay.note.contains("COPIED"),
		"SHARE IT once: its long code copied, and asks again"
	)
	screen._do("share")
	_wait(
		func() -> bool:
			screen.shelf.poll(now)
			return not screen.shelf.busy(),
		700
	)
	var code := ShareCode.short_of(UserMap.hash_of(forty))
	_check(
		(
			str(screen.shelf.codes.get(UserMap.hash_of(forty), "")) == code
			and UserMapPlay.note.contains(ShareCode.shown(code))
		),
		"SHARE IT again: on the shelf, its code said (%s)" % UserMapPlay.note
	)
	main.render()
	UserMapPlay.row = 2
	UserMapPlay.action = 0
	screen._do("type")
	for ch in ShareCode.shown(code).to_lower():
		var key := InputEventKey.new()
		key.pressed = true
		key.unicode = ch.unicode_at(0)
		screen.shelf.type_key(key)
	main.render()
	var enter := InputEventKey.new()
	enter.pressed = true
	enter.keycode = KEY_ENTER
	screen.shelf.type_key(enter)
	_wait(
		func() -> bool:
			screen.shelf.poll(now)
			return not screen.shelf.busy(),
		700
	)
	_check(
		str(screen._entry().get("hash", "")) == UserMap.hash_of(forty),
		"a shelf code typed in small letters fetches it: %s" % UserMapPlay.note
	)
	ShelfLink.server = {}
	screen.shelf.open_shelf()
	screen.shelf.poll(now)
	_check(
		not screen.shelf.busy() and screen.shelf.state.contains("NO SHELF"),
		"a tool with no server set never knocks anywhere: %s" % screen.shelf.state
	)
	screen.back()
	_check(main.state == "maps" and not screen.shelf.open, "ESC closes the shelf, not the list")
	main.render()
	main.state = "title"
	main.queue_free()
	await process_frame
