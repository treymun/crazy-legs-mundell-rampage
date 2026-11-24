## The in-game update's download and check (update_notice.gd, Android): one
## file fetched over HTTPClient into the app's own folder, a little each
## frame. An interrupted download picks up where it stopped (an HTTP Range
## request: GitHub's asset store answers 206 through its redirect); a
## dropped line or a stall tries again after a growing wait, from what is on
## disk; a server that ignores the Range starts again from nothing. The
## check reads the file back a piece a frame through SHA-256, so a 200 MB APK
## never sits in memory.
class_name UpdateFetch
extends Node

## The download ended: `ok`, else why ("gone": no such file; "size": the
## server's file is not the size the manifest says; "disk": the file cannot
## be written (full); "redirects", or the last network failure).
signal finished(ok: bool, why: String)
## The check ended: the file is the size and SHA-256 asked for.
signal checked(ok: bool)

## Bytes read from the connection at most per read.
const CHUNK := 65536
## Bytes hashed per read while checking.
const HASH_CHUNK := 1048576
## Redirects followed per request (github.com sends one, to its asset store).
const REDIRECTS := 5

## Seconds without a byte (or a connection) before the line counts as dead.
var stall := 20.0
## Seconds waited before each retry; the download gives up after the last.
var backoff: Array[float] = [2.0, 5.0, 10.0, 20.0, 40.0]
## Microseconds of work a frame, and while `light` (a game is being played)
## one read a frame at most.
var budget_usec := 4000
var light := false
## The download: where from, where to, how big.
var origin := ""
var path := ""
var size := 0
## Bytes on disk so far, where the last request picked up from, and whether
## the server answered it as a Range (206).
var have := 0
var resumed_from := 0
var ranged := false
## "", "connect", "request", "body", "wait", "verify".
var phase := ""
## Retries used, and the seconds left before the next one.
var tries := 0
var wait_left := 0.0
## What the last failure was (shown nowhere; the checks read it).
var last_error := ""
## Requests made (each redirect hop counts).
var requests := 0
var user_agent := "GodotEngine/%s" % Engine.get_version_info().get("string", "4")

var _client: HTTPClient = null
var _file: FileAccess = null
var _url := ""
var _hops := 0
var _idle := 0.0
var _hash: HashingContext = null
var _want_hash := ""
var _read := 0


## Fetch `url` into `to` (`bytes` long), keeping whatever part of it is there.
func start(url: String, to: String, bytes: int) -> void:
	stop()
	origin = url
	path = to
	size = bytes
	tries = 0
	_hops = 0
	_request(origin)


## Stop where it is (the part on disk is kept for next time).
func stop() -> void:
	_close()
	phase = ""


## How far along the download or the check is, 0..1.
func fraction() -> float:
	if size <= 0:
		return 0.0
	if phase == "verify":
		return clampf(float(_read) / float(size), 0.0, 1.0)
	return clampf(float(have) / float(size), 0.0, 1.0)


## Whether it is fetching or checking (or waiting to fetch again).
func busy() -> bool:
	return phase != ""


## Check `file` is `bytes` long with SHA-256 `sha256` (lower-case hex):
## `checked` answers, a frame or more later.
func verify(file: String, bytes: int, sha256: String) -> void:
	stop()
	path = file
	size = bytes
	_read = 0
	_want_hash = sha256.to_lower()
	if not FileAccess.file_exists(file) or _length(file) != bytes or bytes <= 0:
		_checked.call_deferred(false)
		return
	_file = FileAccess.open(file, FileAccess.READ)
	if _file == null:
		_checked.call_deferred(false)
		return
	_hash = HashingContext.new()
	_hash.start(HashingContext.HASH_SHA256)
	phase = "verify"


## The bytes of `file` on disk (0 when there is none).
static func _length(file: String) -> int:
	if not FileAccess.file_exists(file):
		return 0
	var f := FileAccess.open(file, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return n


func _process(delta: float) -> void:
	match phase:
		"connect":
			_connecting(delta)
		"request":
			_requesting(delta)
		"body":
			_reading(delta)
		"wait":
			wait_left -= delta
			if wait_left <= 0.0:
				_hops = 0
				_request(origin)
		"verify":
			_hashing()


func _request(url: String) -> void:
	_close()
	_url = url
	have = _length(path)
	if have > size:
		DirAccess.remove_absolute(path)
		have = 0
	if have == size and size > 0:
		_done(true, "")
		return
	var parts := _split(url)
	if parts.is_empty():
		_done(false, "address")
		return
	_client = HTTPClient.new()
	_client.read_chunk_size = CHUNK
	var secure: bool = parts["tls"]
	var host: String = parts["host"]
	var port: int = parts["port"]
	var tls: TLSOptions = TLSOptions.client() if secure else null
	if _client.connect_to_host(host, port, tls) != OK:
		_retry("connect")
		return
	requests += 1
	_idle = 0.0
	phase = "connect"


## scheme, host, port and path of an http(s) address ({} when it is none).
static func _split(url: String) -> Dictionary:
	var tls := url.begins_with("https://")
	if not tls and not url.begins_with("http://"):
		return {}
	var rest := url.substr(8 if tls else 7)
	var slash := rest.find("/")
	var host := rest if slash < 0 else rest.substr(0, slash)
	var where := "/" if slash < 0 else rest.substr(slash)
	var port := 443 if tls else 80
	var colon := host.rfind(":")
	if colon > 0 and host.substr(colon + 1).is_valid_int():
		port = int(host.substr(colon + 1))
		host = host.substr(0, colon)
	if host == "":
		return {}
	return {"tls": tls, "host": host, "port": port, "path": where}


func _connecting(delta: float) -> void:
	_client.poll()
	var status := _client.get_status()
	if status == HTTPClient.STATUS_RESOLVING or status == HTTPClient.STATUS_CONNECTING:
		_stalled(delta)
		return
	if status != HTTPClient.STATUS_CONNECTED:
		_retry("connect %d" % status)
		return
	var headers := PackedStringArray(["User-Agent: " + user_agent, "Accept: */*"])
	resumed_from = have
	if have > 0:
		headers.append("Range: bytes=%d-" % have)
	if _client.request(HTTPClient.METHOD_GET, str(_split(_url)["path"]), headers) != OK:
		_retry("request")
		return
	_idle = 0.0
	phase = "request"


func _requesting(delta: float) -> void:
	_client.poll()
	var status := _client.get_status()
	if status == HTTPClient.STATUS_REQUESTING:
		_stalled(delta)
		return
	if status != HTTPClient.STATUS_BODY and status != HTTPClient.STATUS_CONNECTED:
		_retry("answer %d" % status)
		return
	var code := _client.get_response_code()
	var headers := {}
	var raw: Dictionary = _client.get_response_headers_as_dictionary()
	for key: String in raw:
		headers[key.to_lower()] = str(raw[key])
	if code in [301, 302, 303, 307, 308]:
		var next := str(headers.get("location", ""))
		_hops += 1
		if next == "" or _hops > REDIRECTS:
			_done(false, "redirects")
			return
		if next.begins_with("/"):
			var parts := _split(_url)
			var secure: bool = parts["tls"]
			var port: int = parts["port"]
			next = ("https://" if secure else "http://") + str(parts["host"]) + ":%d" % port + next
		_request(next)
		return
	if code == 404 or code == 410:
		_done(false, "gone")
		return
	if code == 416:
		# Asked from past the end: a finished file is checked, anything else
		# starts again from nothing.
		if have != size:
			DirAccess.remove_absolute(path)
		_request(_url)
		return
	ranged = code == 206
	if code == 206:
		var span := _range(str(headers.get("content-range", "")))
		if span.is_empty() or span[2] != size:
			_done(false, "size")
			return
		if span[0] != have:
			DirAccess.remove_absolute(path)
			_hops = 0
			_request(origin)
			return
	elif code == 200:
		# The server ignored the Range: the whole file again from nothing.
		var length := str(headers.get("content-length", "-1")).to_int()
		if length >= 0 and length != size:
			_done(false, "size")
			return
		have = 0
	else:
		_retry("http %d" % code)
		return
	if have > 0:
		_file = FileAccess.open(path, FileAccess.READ_WRITE)
		if _file != null:
			_file.seek_end()
	else:
		_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		_done(false, "disk")
		return
	_idle = 0.0
	phase = "body"


## [first, last, total] of a Content-Range "bytes 1000-1999/200807344".
static func _range(text: String) -> Array[int]:
	var shape := RegEx.create_from_string("^bytes (\\d+)-(\\d+)/(\\d+)$")
	var m := shape.search(text.strip_edges())
	if m == null:
		return []
	var out: Array[int] = [int(m.get_string(1)), int(m.get_string(2)), int(m.get_string(3))]
	return out


func _reading(delta: float) -> void:
	var began := Time.get_ticks_usec()
	var got := false
	while true:
		_client.poll()
		if _client.get_status() != HTTPClient.STATUS_BODY:
			if have >= size:
				_done(true, "")
			else:
				_retry("cut at %d" % have)
			return
		var chunk := _client.read_response_body_chunk()
		if not chunk.is_empty():
			_file.store_buffer(chunk)
			if _file.get_error() != OK:
				_done(false, "disk")
				return
			have += chunk.size()
			got = true
			if have > size:
				DirAccess.remove_absolute(path)
				_done(false, "size")
				return
			if have == size:
				_done(true, "")
				return
		if chunk.is_empty() or light or Time.get_ticks_usec() - began > budget_usec:
			break
	if got:
		_idle = 0.0
	else:
		_stalled(delta)


func _hashing() -> void:
	var began := Time.get_ticks_usec()
	while true:
		var piece := _file.get_buffer(HASH_CHUNK)
		_read += piece.size()
		if not piece.is_empty():
			_hash.update(piece)
		if piece.size() < HASH_CHUNK or _file.eof_reached():
			var sum := _hash.finish().hex_encode()
			_close()
			phase = ""
			_checked(_read == size and sum == _want_hash)
			return
		if light or Time.get_ticks_usec() - began > budget_usec:
			return


func _stalled(delta: float) -> void:
	_idle += delta
	if _idle > stall:
		_retry("stall")


func _retry(why: String) -> void:
	_close()
	last_error = why
	tries += 1
	if tries > backoff.size():
		_done(false, why)
		return
	wait_left = backoff[tries - 1]
	phase = "wait"


func _done(ok: bool, why: String) -> void:
	_close()
	phase = ""
	if not ok:
		last_error = why
	finished.emit(ok, why)


func _checked(ok: bool) -> void:
	checked.emit(ok)


func _close() -> void:
	if _file != null:
		_file.close()
		_file = null
	if _client != null:
		_client.close()
		_client = null
	_hash = null
