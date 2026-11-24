## A tiny HTTP server on 127.0.0.1 for tools/update_flow_check.gd: it serves
## a release's update.json and APK the way GitHub does (the APK's address
## answers 302 to the asset store, which honours Range with a 206), a little
## each frame, and can cut a download off part way, ignore Range, serve a
## mangled copy or have no file at all. Polled by the check's own frames.
extends RefCounted

## The test APK and its update.json.
var body := PackedByteArray()
var manifest := ""
## Requests seen: [path, range header] each.
var seen: Array = []
## Cut the next APK answer after this many body bytes (-1: never).
var cut_after := -1
## Answer Range requests with the whole file (200), as some servers do.
var ignore_range := false
## Mangle the APK's bytes for this many more answers.
var mangle := 0
## No update.json (404).
var no_manifest := false
## Bytes sent per poll.
var pace := 262144
var port := 0

var _server := TCPServer.new()
var _peers: Array = []


func start() -> bool:
	for p in range(47310, 47390):
		if _server.listen(p, "127.0.0.1") == OK:
			port = p
			return true
	return false


func stop() -> void:
	for peer: Dictionary in _peers:
		(peer["tcp"] as StreamPeerTCP).disconnect_from_host()
	_peers.clear()
	_server.stop()


func base() -> String:
	return "http://127.0.0.1:%d/rel/v%%s/" % port


## Requests made for a path that ends with `tail`.
func count(tail: String) -> int:
	var n := 0
	for s: Array in seen:
		if String(s[0]).ends_with(tail):
			n += 1
	return n


func poll() -> void:
	while _server.is_connection_available():
		_peers.append(
			{"tcp": _server.take_connection(), "in": "", "out": PackedByteArray(), "cut": -1}
		)
	for peer: Dictionary in _peers.duplicate():
		var tcp: StreamPeerTCP = peer["tcp"]
		tcp.poll()
		if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_peers.erase(peer)
			continue
		var waiting := tcp.get_available_bytes()
		if waiting > 0:
			var got: Array = tcp.get_partial_data(waiting)
			peer["in"] = String(peer["in"]) + (got[1] as PackedByteArray).get_string_from_utf8()
			if (
				String(peer["in"]).contains("\r\n\r\n")
				and (peer["out"] as PackedByteArray).is_empty()
			):
				_answer(peer)
		var out: PackedByteArray = peer["out"]
		if out.is_empty():
			continue
		var n := mini(pace, out.size())
		var cut: int = peer["cut"]
		if cut >= 0:
			n = mini(n, cut)
		var sent: Array = tcp.put_partial_data(out.slice(0, n))
		var done: int = sent[1]
		peer["out"] = out.slice(done)
		if cut >= 0:
			peer["cut"] = cut - done
			if cut - done <= 0:
				tcp.disconnect_from_host()
				_peers.erase(peer)


func _answer(peer: Dictionary) -> void:
	var head := String(peer["in"]).split("\r\n\r\n")[0].split("\r\n")
	var path := head[0].split(" ")[1] if head[0].split(" ").size() > 1 else "/"
	var range_text := ""
	for line in head:
		if line.to_lower().begins_with("range:"):
			range_text = line.substr(6).strip_edges()
	seen.append([path, range_text])
	if path.ends_with("/update.json"):
		if no_manifest:
			peer["out"] = _head(404, "Not Found", 0)
		else:
			var data := manifest.to_utf8_buffer()
			peer["out"] = _head(200, "OK", data.size(), "application/json") + data
		return
	if path.begins_with("/rel/") and path.ends_with(".apk"):
		# github.com: the asset's address sends the client to the store.
		var to := "/store/apk?sig=%d" % seen.size()
		peer["out"] = (
			("HTTP/1.1 302 Found\r\nLocation: %s\r\nContent-Length: 0\r\n\r\n" % to)
			. to_utf8_buffer()
		)
		return
	if path.begins_with("/store/apk"):
		var data := body.duplicate()
		if mangle > 0:
			mangle -= 1
			data[data.size() / 2] = data[data.size() / 2] ^ 0xff
		var start := 0
		if range_text.begins_with("bytes=") and not ignore_range:
			start = String(range_text.substr(6).split("-")[0]).to_int()
		if start >= data.size() and start > 0:
			peer["out"] = _head(416, "Range Not Satisfiable", 0)
			return
		var part := data.slice(start)
		var head_bytes: PackedByteArray
		if start > 0:
			head_bytes = _head(
				206,
				"Partial Content",
				part.size(),
				"application/vnd.android.package-archive",
				"Content-Range: bytes %d-%d/%d\r\n" % [start, data.size() - 1, data.size()]
			)
		else:
			head_bytes = _head(200, "OK", part.size(), "application/vnd.android.package-archive")
		peer["out"] = head_bytes + part
		if cut_after >= 0:
			peer["cut"] = head_bytes.size() + cut_after
			cut_after = -1
		return
	peer["out"] = _head(404, "Not Found", 0)


func _head(
	code: int, words: String, length: int, kind := "text/plain", extra := ""
) -> PackedByteArray:
	var text := (
		"HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\n" % [code, words, kind, length]
		+ "Accept-Ranges: bytes\r\n%sConnection: close\r\n\r\n" % extra
	)
	return text.to_utf8_buffer()
