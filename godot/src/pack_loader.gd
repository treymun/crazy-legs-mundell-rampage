## The browser build's second download. The first one (index.pck) holds the
## title and Hickston; each chapter's own files (its music, its enemies'
## pictures, looks, sounds and models) are left out of it (export_presets.cfg)
## and published beside it as a pack (tools/make_packs.gd writes them and
## packs.json). This fetches them after the game has started, the chapter
## being played first, keeps them in the browser's storage for the next
## visit, and mounts each as it arrives. Until then that chapter's music is
## simply not there yet (assets.gd track()) and main_flow.gd play() waits for
## its pictures, saying so with the chapter's ROAD_LINES.
class_name PackLoader
extends Node

const STORE := "user://packs"
const MANIFEST := "packs.json"
const CHUNK := 4 << 20
const MAX_PACK_SIZE := 256 << 20
const MAX_MANIFEST_SIZE := 64 << 10
const MAX_ATTEMPTS := 4
## What the screen says while a chapter's pack comes down, with how far.
const ROAD_LINES := {
	"chapter_hickston": "WARMING UP THE TRUCK",
	"chapter_fair": "TOWING THE FAIRGROUNDS IN",
	"chapter_sawmill": "HAULING LOGS TO BLACKWATER",
	"chapter_quarry": "BLASTING A ROAD TO STILLWATER",
	"chapter_bayou": "POLING OUT TO GATOR BAYOU",
	"chapter_speedway": "GASSING UP FOR THE SPEEDWAY",
	"chapter_moonshine": "LOADING THE TRUNK AT GRANNY'S",
	"chapter_mothership": "HITCHING A RIDE TO THE SAUCER",
}

var manifest := {}
var queue: Array[String] = []
var loaded := {}
var _base := ""
var _http: HTTPRequest
var _busy := ""
var _manifest_due := false
var _tries := {}
var _failed := {}
var _retry_at := {}
var _priority := ""
var _clock := 0.0


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	_base = str(JavaScriptBridge.eval("new URL('.', document.baseURI).href", true))
	DirAccess.make_dir_recursive_absolute(STORE)
	_http = HTTPRequest.new()
	# The browser unzips what GitHub Pages sends gzipped (the manifest and the
	# packs both) before Godot sees it; asking for gzip made Godot unzip it
	# again, fail, and never mount a pack.
	_http.accept_gzip = false
	# Read in big bites: the request is polled once a frame, and the default
	# 64 KB a bite is under 4 MB a second at 60 frames a second.
	_http.download_chunk_size = CHUNK
	_http.timeout = 120.0
	add_child(_http)
	_http.request_completed.connect(_done)
	_manifest_due = true
	print("chapter packs from ", _base)
	_next()


## How far `pack` has come down, 0..1 (1 once it is mounted).
func progress(pack: String) -> float:
	if loaded.has(pack):
		return 1.0
	if _busy == pack and manifest.has(pack):
		var entry: Dictionary = manifest[pack]
		var total: float = entry.get("size", 1)
		return clampf(float(_http.get_downloaded_bytes()) / maxf(1.0, total), 0.0, .99)
	return 0.0


## The line the screen shows while `pack` comes down: the chapter's road
## and how far along it is.
func road_line(pack: String) -> String:
	if _failed.has(pack) or _failed.has(MANIFEST):
		return "ROAD DOWN. BACK OUT AND TRY AGAIN."
	var line := str(ROAD_LINES.get(pack, "FETCHING THE CHAPTER"))
	return "%s... %d%%" % [line, roundi(progress(pack) * 100.0)]


## Fetch this pack next (a chapter has just started).
func want_first(pack: String, retry_failed := false) -> void:
	if not ROAD_LINES.has(pack) or loaded.has(pack):
		return
	_priority = pack
	if retry_failed:
		if _failed.erase(MANIFEST):
			_tries.erase(MANIFEST)
			_manifest_due = true
		if _failed.erase(pack) and manifest.has(pack) and not queue.has(pack):
			_tries.erase(pack)
			queue.push_front(pack)
		_next()


func _process(dt: float) -> void:
	_clock += dt
	if not _retry_at.is_empty():
		_next()


func _eligible(name: String) -> bool:
	var due: float = _retry_at.get(name, 0.0)
	return _clock >= due


func _dequeue() -> String:
	if queue.has(_priority) and _eligible(_priority):
		queue.erase(_priority)
		return _priority
	for name: String in queue:
		if _eligible(name):
			queue.erase(name)
			return name
	return ""


func _next() -> void:
	if _http == null or _busy != "":
		return
	if _manifest_due:
		if not _eligible(MANIFEST):
			return
		_manifest_due = false
		_retry_at.erase(MANIFEST)
		_busy = MANIFEST
		_http.body_size_limit = MAX_MANIFEST_SIZE
		var asked := _http.request(_base + MANIFEST)
		if asked != OK:
			print("chapter packs: cannot ask for ", _base + MANIFEST, " (error ", asked, ")")
			_busy = ""
			_retry(MANIFEST)
		return
	var name := _dequeue()
	while name != "":
		_retry_at.erase(name)
		var entry: Dictionary = manifest[name]
		var file := str(entry["file"])
		var kept := STORE.path_join(file)
		var handle := FileAccess.open(kept, FileAccess.READ)
		var size: int = entry.get("size", -1)
		if handle != null:
			var same_size := handle.get_length() == size
			handle.close()
			var digest: String = entry.get("sha256", "")
			if (
				same_size
				and (digest == "" or FileAccess.get_sha256(kept) == digest)
				and _mount(name)
			):
				name = _dequeue()
				continue
			DirAccess.remove_absolute(kept)
		# Web HTTPRequest returns the data in memory, so _done writes the file.
		_busy = name
		_http.body_size_limit = size
		if _http.request(_base + file) != OK:
			_busy = ""
			_retry(name)
		return


func _done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var name := _busy
	_busy = ""
	if name == "":
		return
	var ok := result == HTTPRequest.RESULT_SUCCESS and code == 200
	if name == MANIFEST:
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8()) if ok else null
		var validated := _validated_manifest(parsed)
		if validated.is_empty():
			_retry(MANIFEST)
			return
		manifest = validated
		_tries.erase(MANIFEST)
		for pack: String in manifest:
			if not loaded.has(pack):
				queue.append(pack)
		_forget_old()
		_next.call_deferred()
		return
	var entry: Dictionary = manifest[name]
	var kept := STORE.path_join(str(entry["file"]))
	var size: int = entry.get("size", -1)
	var digest: String = entry.get("sha256", "")
	if not ok or body.size() != size or not _matches_digest(body, digest):
		_retry(name)
		return
	var handle := FileAccess.open(kept, FileAccess.WRITE)
	if handle == null:
		push_warning("cannot write " + kept)
		_retry(name)
		return
	var written := handle.store_buffer(body)
	handle.flush()
	var write_error := handle.get_error()
	handle.close()
	if not written or write_error != OK or not _mount(name):
		DirAccess.remove_absolute(kept)
		_retry(name)
		return
	_next.call_deferred()


func _retry(name: String) -> void:
	var tries: int = _tries.get(name, 0) + 1
	_tries[name] = tries
	if tries >= MAX_ATTEMPTS:
		push_warning("giving up on " + name)
		_failed[name] = true
	else:
		_retry_at[name] = _clock + 4.0 * tries
		if name == MANIFEST:
			_manifest_due = true
		else:
			queue.append(name)
	# Keep fetching other chapters while this one waits for a retry.
	_next.call_deferred()


static func _validated_manifest(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var entries: Dictionary = value
	if entries.size() != ROAD_LINES.size():
		return {}
	var out := {}
	for name: String in ROAD_LINES:
		var found: Variant = entries.get(name)
		if not (found is Dictionary):
			return {}
		var row: Dictionary = found
		var raw_size: Variant = row.get("size")
		if not (
			row.get("file") is String
			and (raw_size is int or raw_size is float)
			and row.get("sha256", "") is String
		):
			return {}
		var file: String = row["file"]
		var size: float = raw_size
		var digest: String = row.get("sha256", "")
		var prefix := name + "-"
		if (
			not file.begins_with(prefix)
			or not file.ends_with(".pck")
			or not _is_hex(file.trim_prefix(prefix).trim_suffix(".pck"), 10)
			or size < 1
			or size > MAX_PACK_SIZE
			or size != floorf(size)
			or (digest != "" and not _is_hex(digest, 64))
		):
			return {}
		out[name] = {"file": file, "size": int(size), "sha256": digest}
	return out


static func _is_hex(value: String, length: int) -> bool:
	return value.length() == length and value.is_valid_hex_number(false)


static func _matches_digest(body: PackedByteArray, expected: String) -> bool:
	if expected == "":
		return true  # manifests from before the full pack checksum
	var hash_context := HashingContext.new()
	hash_context.start(HashingContext.HASH_SHA256)
	hash_context.update(body)
	return hash_context.finish().hex_encode() == expected


func _mount(name: String) -> bool:
	var path := STORE.path_join(str(manifest[name]["file"]))
	if ProjectSettings.load_resource_pack(path, false):
		loaded[name] = true
		_tries.erase(name)
		_failed.erase(name)
		_learn_ids(name)
		print("chapter pack ready: ", name)
		return true
	push_warning("could not mount " + path)
	return false


## The ids of the models a pack brings (tools/make_packs.gd uid_list): the
## first download's list was made without them, and a scene naming one by id
## would fall back to its path with a warning.
func _learn_ids(name: String) -> void:
	var list := "res://packs/%s.uids" % name
	if not FileAccess.file_exists(list):
		return
	for line in FileAccess.get_file_as_string(list).split("\n", false):
		var parts := line.split(" ", false)
		if parts.size() != 2:
			continue
		var id := ResourceUID.text_to_id(parts[0])
		if id == ResourceUID.INVALID_ID:
			continue
		if ResourceUID.has_id(id):
			ResourceUID.set_id(id, parts[1])
		else:
			ResourceUID.add_id(id, parts[1])


## Packs kept from an earlier version of the game.
func _forget_old() -> void:
	var wanted := {}
	for pack: String in manifest:
		wanted[str(manifest[pack]["file"])] = true
	for file in DirAccess.get_files_at(STORE):
		if not wanted.has(file):
			DirAccess.remove_absolute(STORE.path_join(file))
