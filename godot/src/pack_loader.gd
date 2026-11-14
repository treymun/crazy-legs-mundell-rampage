## The browser build's second download. Each chapter's music is left out of the
## first one (export_presets.cfg) and published beside it as a small pack
## (tools/make_packs.gd writes them and packs.json). This fetches them after
## the game has started, the chapter being played first, keeps them in the
## browser's storage for the next visit, and mounts each as it arrives; until
## then that chapter's music is simply not there yet (assets.gd track()).
class_name PackLoader
extends Node

const STORE := "user://packs"
const MANIFEST := "packs.json"

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
	add_child(_http)
	_http.request_completed.connect(_done)
	_manifest_due = true
	print("music packs from ", _base)
	_next()


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
			print("music packs: cannot ask for ", _base + MANIFEST, " (error ", asked, ")")
			_busy = ""
			_retry(MANIFEST)
		return
	while not queue.is_empty():
		var name: String = queue.pop_front()
		var entry: Dictionary = manifest[name]
		var file := String(entry["file"])
		var kept := STORE.path_join(file)
		var handle := FileAccess.open(kept, FileAccess.READ)
		if handle != null and handle.get_length() == int(entry.get("size", -1)):
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
		var parsed = JSON.parse_string(body.get_string_from_utf8()) if ok else null
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
	var kept := STORE.path_join(String(entry["file"]))
	if not ok or body.size() != int(entry.get("size", -1)):
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
	var path := STORE.path_join(String(manifest[name]["file"]))
	if ProjectSettings.load_resource_pack(path, false):
		loaded[name] = true
		print("music pack ready: ", name)
	else:
		push_warning("could not mount " + path)


## Packs kept from an earlier version of the game.
func _forget_old() -> void:
	var wanted := {}
	for pack: String in manifest:
		wanted[String(manifest[pack]["file"])] = true
	for file in DirAccess.get_files_at(STORE):
		if not wanted.has(file):
			DirAccess.remove_absolute(STORE.path_join(file))
