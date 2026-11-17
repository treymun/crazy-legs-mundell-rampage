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
var _tries := 0
var _wait := 0.0


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
	var line := str(ROAD_LINES.get(pack, "FETCHING THE CHAPTER"))
	return "%s... %d%%" % [line, roundi(progress(pack) * 100.0)]


## Fetch this pack next (a chapter has just started).
func want_first(pack: String) -> void:
	var at := queue.find(pack)
	if at > 0:
		queue.remove_at(at)
		queue.push_front(pack)


func _process(dt: float) -> void:
	if _wait > 0.0:
		_wait -= dt
		if _wait <= 0.0:
			_next()


func _next() -> void:
	if _busy != "" or _wait > 0.0:
		return
	if _manifest_due:
		_manifest_due = false
		_busy = MANIFEST
		_http.download_file = ""
		var asked := _http.request(_base + MANIFEST)
		if asked != OK:
			print("chapter packs: cannot ask for ", _base + MANIFEST, " (error ", asked, ")")
			_busy = ""
			_retry(MANIFEST)
		return
	while not queue.is_empty():
		var name: String = queue.pop_front()
		var entry: Dictionary = manifest[name]
		var file := str(entry["file"])
		var kept := STORE.path_join(file)
		var handle := FileAccess.open(kept, FileAccess.READ)
		var size: int = entry.get("size", -1)
		if handle != null and handle.get_length() == size:
			# Fetched on an earlier visit.
			handle.close()
			_mount(name)
			continue
		# Kept in memory and written by _done(): a browser build's HTTPRequest
		# does not write download_file, and renaming a file in a browser's
		# storage does not work either.
		_busy = name
		_http.download_file = ""
		if _http.request(_base + file) != OK:
			_busy = ""
			_retry(name)
		return


func _done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var name := _busy
	_busy = ""
	var ok := result == HTTPRequest.RESULT_SUCCESS and code == 200
	if name == MANIFEST:
		var parsed: Variant = JSON.parse_string(body.get_string_from_utf8()) if ok else null
		if not (parsed is Dictionary):
			# A site without packs yet, or no network: try again shortly.
			_retry(MANIFEST)
			return
		manifest = parsed
		for pack: String in manifest:
			queue.append(pack)
		_forget_old()
		_next()
		return
	var entry: Dictionary = manifest[name]
	var kept := STORE.path_join(str(entry["file"]))
	var size: int = entry.get("size", -1)
	if not ok or body.size() != size:
		_retry(name)
		return
	var handle := FileAccess.open(kept, FileAccess.WRITE)
	if handle == null:
		push_warning("cannot write " + kept)
		return
	handle.store_buffer(body)
	handle.close()
	_mount(name)
	_next()


func _retry(name: String) -> void:
	_tries += 1
	if _tries > 6:
		push_warning("giving up on " + name)
		return
	if name == MANIFEST:
		_manifest_due = true
	else:
		queue.push_front(name)
	_wait = 4.0 * _tries


func _mount(name: String) -> void:
	var path := STORE.path_join(str(manifest[name]["file"]))
	if ProjectSettings.load_resource_pack(path, false):
		loaded[name] = true
		_learn_ids(name)
		print("chapter pack ready: ", name)
	else:
		push_warning("could not mount " + path)


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
