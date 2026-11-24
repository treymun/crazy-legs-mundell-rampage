## The in-game Android update (src/update_notice.gd's flow, src/update_fetch.gd,
## src/apk_installer.gd, the sign's panel src/ui/update_sign.gd), headless,
## against a small HTTP server of its own on 127.0.0.1 (tools/update_server.gd,
## answering as GitHub does: a 302 to the asset store, Range answered 206) and
## a stand-in for the Android plugin. Nothing reaches the internet; files go
## under the cache folder.
##
##   godot --headless --path godot --script res://tools/update_flow_check.gd
##
## - update.json: read for its version only, the APK's size and SHA-256; any
##   other version, a garbled or missing entry, a bad hash or size, refused.
## - The files' names carry the version; tidy throws away the ones the game
##   is at or past, never another file.
## - The download: whole; cut off part way and picked up with a Range (206)
##   through the redirect; a server that ignores the Range starts again from
##   nothing; a mangled copy fails the SHA-256; a missing file is "gone";
##   stopped and started again it carries on from the part on disk.
## - The flow through every stage with the stand-in: GIT IT to the system's
##   prompt; the "install unknown apps" switch off (SETTIN'S opens it, coming
##   back with it on carries on); the player saying no (the sign stays, PUT IT
##   IN again); no answer at all; no room (nothing fetched); mangled once (a
##   second download) and twice (CAME OUT BAD, nothing left); a game going (no
##   installer over it); no update.json yet; CHECK FOR UPDATES turned off
##   mid-download (it stops, nothing more is asked); an APK from an earlier
##   run comes back at PUT IT IN, is checked again, and goes once the game is
##   at its version.
## - The panel's words fit the tin in every stage.
## UPDATE FLOW OK when all hold.
extends SceneTree

const Server := preload("res://tools/update_server.gd")


## The Android plugin's stand-in: the same methods and signals as the Java
## CrazyLegsUpdater, recording what it is asked.
class FakePlugin:
	extends Object
	signal resumed
	signal install_result(code: int)
	var dir := ""
	var allowed := true
	var settings_opened := 0
	var installs: Array[String] = []
	var refuse := ""

	func downloadDir() -> String:  # gdlint: ignore=function-name
		return dir

	func canInstall() -> bool:  # gdlint: ignore=function-name
		return allowed

	func openInstallSettings() -> bool:  # gdlint: ignore=function-name
		settings_opened += 1
		return true

	func install(path: String) -> String:
		installs.append(path)
		return refuse


var failures: Array[String] = []
var checks := 0
var server: Server
var dir := ""
var body := PackedByteArray()
var sha := ""


func _init() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	checks += 1
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures.append(what)


func _run() -> void:
	dir = OS.get_cache_dir().path_join("clmr_update_flow")
	_wipe()
	DirAccess.make_dir_recursive_absolute(dir)
	# A 3 MB "APK" of seeded noise.
	var dice := RandomNumberGenerator.new()
	dice.seed = 1997
	body.resize(3 * 1048576 + 4321)
	for i in body.size():
		body[i] = dice.randi() & 0xff
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(body)
	sha = h.finish().hex_encode()
	server = Server.new()
	check(server.start(), "the test server listens on 127.0.0.1")
	server.body = body
	server.manifest = _manifest("3.12.1", body.size(), sha)
	_manifests()
	_names()
	await _fetches()
	await _flow()
	_words()
	server.stop()
	_wipe()
	if failures.is_empty():
		print("\n%d checks\nUPDATE FLOW OK" % checks)
		quit(0)
	else:
		print("\n%d of %d FAILED:\n  %s" % [failures.size(), checks, "\n  ".join(failures)])
		quit(1)


func _manifest(version: String, size: Variant, hash: String) -> String:
	return (
		JSON
		. stringify(
			{
				"version": version,
				"files":
				{
					"CrazyLegsMundellRampage.apk": {"size": size, "sha256": hash},
					"CrazyLegsMundellRampage_Setup.exe": {"size": 5, "sha256": "0".repeat(64)},
				},
			}
		)
	)


func _manifests() -> void:
	print("\nUPDATE.JSON")
	var good := UpdateNotice.read_manifest(_manifest("3.12.1", 200807344, sha), "3.12.1")
	check(good.get("size", 0) == 200807344 and good.get("sha256", "") == sha, "a good one reads")
	check(
		not UpdateNotice.read_manifest(_manifest("v3.12.1", 5, sha), "3.12.1").is_empty(),
		"a v in front of the version is fine"
	)
	var bad := {
		"another version": _manifest("3.12.0", 5, sha),
		"a short hash": _manifest("3.12.1", 5, "abc"),
		"a hash that is not hex": _manifest("3.12.1", 5, "z".repeat(64)),
		"no size": _manifest("3.12.1", 0, sha),
		"a negative size": _manifest("3.12.1", -5, sha),
		"a size with a fraction": _manifest("3.12.1", 5.5, sha),
		"a size in words": _manifest("3.12.1", "big", sha),
		"no APK": JSON.stringify({"version": "3.12.1", "files": {}}),
		"no files": JSON.stringify({"version": "3.12.1"}),
		"garbage": "<html>404</html>",
		"empty": "",
		"too long": _manifest("3.12.1", 5, sha) + " ".repeat(5000),
	}
	for what: String in bad:
		check(UpdateNotice.read_manifest(str(bad[what]), "3.12.1").is_empty(), "refused: " + what)
	check(
		(
			UpdateNotice.read_manifest(_manifest("3.12.1", 5, sha.to_upper()), "3.12.1").get(
				"sha256"
			)
			== sha
		),
		"an upper-case hash reads as lower-case"
	)
	var n := UpdateNotice.new("3.11.0", "android")
	check(
		(
			n.manifest_url("3.12.1")
			== "https://github.com/treymun/crazy-legs-mundell-rampage/releases/download/v3.12.1/update.json"
		),
		"update.json comes from the release v3.12.1 itself"
	)
	check(
		n.apk_url("3.12.1").ends_with("/releases/download/v3.12.1/CrazyLegsMundellRampage.apk"),
		"and so does the APK (never latest/)"
	)
	n.free()


func _names() -> void:
	print("\nTHE FILES AND TIDYING")
	check(
		UpdateNotice.file_version("CrazyLegsMundellRampage-3.12.1.apk") == "3.12.1", "an APK's name"
	)
	check(
		UpdateNotice.file_version("CrazyLegsMundellRampage-3.12.1.apk.part") == "3.12.1", "a part"
	)
	check(
		UpdateNotice.file_version("CrazyLegsMundellRampage-3.12.1.apk.json") == "3.12.1", "a note"
	)
	check(
		UpdateNotice.file_version("CrazyLegsMundellRampage-3.13.0-dev.2.apk") == "3.13.0-dev.2",
		"a pre-release"
	)
	for other: String in ["saves.json", "CrazyLegsMundellRampage.apk", "x-3.12.1.apk", "../a.apk"]:
		check(UpdateNotice.file_version(other) == "", "not one of ours: " + other)
	var files := [
		"CrazyLegsMundellRampage-3.11.0.apk",
		"CrazyLegsMundellRampage-3.11.0.apk.json",
		"CrazyLegsMundellRampage-3.12.0.apk.part",
		"CrazyLegsMundellRampage-3.12.1.apk",
		"CrazyLegsMundellRampage-3.12.1.apk.json",
		"keep.txt",
	]
	for f: String in files:
		_write(dir.path_join(f), "x".to_utf8_buffer())
	var gone := UpdateNotice.tidy(dir, "3.12.0")
	var left := Array(DirAccess.get_files_at(dir))
	left.sort()
	check(gone == 3, "tidy at 3.12.0 throws away the three files of 3.11.0 and 3.12.0 (%d)" % gone)
	check(
		(
			left
			== [
				"CrazyLegsMundellRampage-3.12.1.apk",
				"CrazyLegsMundellRampage-3.12.1.apk.json",
				"keep.txt"
			]
		),
		"and keeps the newer APK and anything not ours (%s)" % ", ".join(left)
	)
	_clear()


func _fetches() -> void:
	print("\nTHE DOWNLOAD")
	var fetch := UpdateFetch.new()
	fetch.backoff = [0.05, 0.1, 0.1]
	root.add_child(fetch)
	var to := dir.path_join("CrazyLegsMundellRampage-3.12.1.apk.part")
	var url := (server.base() % "3.12.1") + "CrazyLegsMundellRampage.apk"
	# Whole, in one go, through the redirect.
	var ended: Array = await _fetch(fetch, url, to, body.size())
	check(ended == [true, ""], "a whole download ends well (%s)" % [ended])
	check(UpdateFetch._length(to) == body.size() and not fetch.ranged, "all of it, from the start")
	check(fetch.requests == 2, "one request and its redirect (%d)" % fetch.requests)
	check(await _verify(fetch, to, sha), "its size and SHA-256 check out")
	check(
		not await _verify(fetch, to, sha.replace(sha[0], "f" if sha[0] != "f" else "0")),
		"a wrong hash does not"
	)
	check(not await _verify(fetch, to + ".none", sha), "nor a missing file")
	# Cut off at 1 MB: tried again, picked up with a Range.
	DirAccess.remove_absolute(to)
	server.cut_after = 1048576
	ended = await _fetch(fetch, url, to, body.size())
	check(ended == [true, ""], "cut off part way, it tries again and finishes (%s)" % [ended])
	check(fetch.tries == 1, "after one retry (%d)" % fetch.tries)
	check(
		fetch.ranged and fetch.resumed_from >= 1048576,
		"picked up at %d with a 206" % fetch.resumed_from
	)
	check(server.seen.back()[1] == "bytes=%d-" % fetch.resumed_from, "asked as a Range from there")
	check(await _verify(fetch, to, sha), "and the stitched file checks out")
	# A server that ignores the Range: from nothing again.
	_write(to, body.slice(0, 500000))
	server.ignore_range = true
	ended = await _fetch(fetch, url, to, body.size())
	server.ignore_range = false
	check(ended == [true, ""] and not fetch.ranged, "a server ignoring the Range: started again")
	check(await _verify(fetch, to, sha), "and that file checks out too")
	# A part from a different file: the hash catches it.
	DirAccess.remove_absolute(to)
	server.mangle = 1
	ended = await _fetch(fetch, url, to, body.size())
	check(
		ended == [true, ""] and not await _verify(fetch, to, sha), "a mangled copy fails the check"
	)
	# Stopped, then started again: it carries on.
	DirAccess.remove_absolute(to)
	server.pace = 65536
	fetch.start(url, to, body.size())
	for i in 400:
		server.poll()
		await process_frame
		if fetch.have > 400000:
			break
	fetch.stop()
	var held := UpdateFetch._length(to)
	check(
		held > 0 and held < body.size() and not fetch.busy(),
		"HOLD IT stops it with %d on disk" % held
	)
	ended = await _fetch(fetch, url, to, body.size())
	check(
		ended == [true, ""] and fetch.resumed_from == held, "started again it carries on from there"
	)
	check(await _verify(fetch, to, sha), "and checks out")
	server.pace = 262144
	# A file that is not there, and a size that does not match.
	ended = await _fetch(fetch, (server.base() % "3.12.1") + "nothing.bin", to + "2", 10)
	check(ended == [false, "gone"], "no such file: gone (%s)" % [ended])
	_write(to, body.slice(0, 1000))
	ended = await _fetch(fetch, url, to, body.size() + 7)
	check(
		ended[0] == false and ended[1] == "size",
		"the store's file another size: refused (%s)" % [ended]
	)
	# No server at all: it gives up after its retries.
	fetch.stall = 0.5
	ended = await _fetch(fetch, "http://127.0.0.1:1/x.apk", to + "3", 10)
	check(
		ended.size() == 2 and ended[0] == false and fetch.tries == 4,
		"nobody answering: given up after the retries (%s)" % [ended]
	)
	fetch.queue_free()
	_clear()


func _fetch(fetch: UpdateFetch, url: String, to: String, size: int) -> Array:
	var out := []
	var take := func(ok: bool, why: String) -> void: out.append_array([ok, why])
	fetch.finished.connect(take)
	fetch.start(url, to, size)
	var until := Time.get_ticks_msec() + 30000
	while out.is_empty() and Time.get_ticks_msec() < until:
		server.poll()
		await process_frame
	fetch.finished.disconnect(take)
	return out


func _verify(fetch: UpdateFetch, file: String, hash: String) -> bool:
	var out := []
	var take := func(ok: bool) -> void: out.append(ok)
	fetch.checked.connect(take)
	fetch.verify(file, body.size(), hash)
	for i in 600:
		if not out.is_empty():
			break
		await process_frame
	fetch.checked.disconnect(take)
	return not out.is_empty() and bool(out[0])


## A notice at 3.11.0 that found 3.12.1, with the stand-in plugin.
func _notice(plugin: FakePlugin, local := "3.11.0") -> UpdateNotice:
	var n := UpdateNotice.new(local, "android")
	n.release_dir = server.base()
	root.add_child(n)
	n.use_installer(ApkInstaller.new(plugin))
	n.fetcher.backoff = [0.05, 0.1]
	n.take("3.12.1")
	return n


## Frames until `n` reaches `stage` (or a while passes).
func _until(n: UpdateNotice, stages: Array) -> void:
	for i in 3000:
		if stages.has(n.stage):
			return
		server.poll()
		await process_frame


func _flow() -> void:
	print("\nTHE FLOW")
	var plugin := FakePlugin.new()
	plugin.dir = dir
	var apk := dir.path_join("CrazyLegsMundellRampage-3.12.1.apk")
	# GIT IT, all the way to the system's prompt.
	var n := _notice(plugin)
	check(n.in_game() and n.stage == "" and n.found == "3.12.1", "the sign offers GIT IT")
	var before := server.seen.size()
	var jsons := server.count("update.json")
	var apks := server.count(".apk")
	check(n.press() == "", "GIT IT says nothing on the title's note line (the panel does)")
	check(n.stage == "asking", "it asks for update.json first")
	await _until(n, ["handed", "failed", "missing", "bad", "full"])
	check(n.stage == "handed", "fetched, checked and handed to the installer (%s)" % n.stage)
	check(plugin.installs == [apk], "the installer got the checked APK")
	check(
		FileAccess.file_exists(apk) and not FileAccess.file_exists(apk + ".part"),
		"renamed once checked"
	)
	check(FileAccess.file_exists(apk + ".json"), "update.json's word on it kept beside it")
	check(
		server.count("update.json") == jsons + 1 and server.count(".apk") == apks + 1,
		"one update.json, one APK"
	)
	check(server.seen.size() - before == 3, "and the store's redirect: three requests in all")
	# The player says no: the sign stays, PUT IT IN again.
	plugin.install_result.emit(ApkInstaller.DECLINED)
	check(n.stage == "ready" and n.aside == "declined", "a no leaves the sign at PUT IT IN")
	n.press()
	check(n.stage == "handed" and plugin.installs.size() == 2, "PUT IT IN hands it over again")
	# Back with no answer at all: after a moment, taken as a no.
	plugin.resumed.emit()
	for i in 80:
		await create_timer(0.05).timeout
		if n.stage != "handed":
			break
	check(n.stage == "ready" and n.aside == "declined", "back with no answer: taken as a no")
	# The installer would not open.
	plugin.refuse = "no installer"
	n.press()
	check(n.stage == "refused", "an installer that will not open: WON'T TAKE")
	plugin.refuse = ""
	n.press()
	await _until(n, ["handed"])
	check(n.stage == "handed", "TRY AGIN gets there again")
	n.queue_free()
	# Started again at 3.11.0: the APK from before comes back at PUT IT IN.
	var again := UpdateNotice.new("3.11.0", "android")
	root.add_child(again)
	again.use_installer(ApkInstaller.new(plugin))
	check(
		again.found == "3.12.1" and again.stage == "ready", "a new run finds the fetched APK ready"
	)
	plugin.allowed = false
	again.press()
	check(again.stage == "checking", "it is checked again before it goes in")
	await _until(again, ["leave", "handed", "bad"])
	check(again.stage == "leave", "the switch off: ONE SWITCH (%s)" % again.stage)
	again.press()
	check(plugin.settings_opened == 1, "SETTIN'S opens the system's setting")
	plugin.resumed.emit()
	check(again.stage == "leave", "back with it still off: still asks")
	plugin.allowed = true
	plugin.resumed.emit()
	check(again.stage == "handed", "back with it on: straight to the installer")
	again.queue_free()
	# The update went in: the new version's first run throws the APK away.
	var updated := UpdateNotice.new("3.12.1", "android")
	root.add_child(updated)
	updated.use_installer(ApkInstaller.new(plugin))
	check(
		DirAccess.get_files_at(dir).is_empty(), "the updated game's first run throws the APK away"
	)
	check(updated.found == "" and updated.stage == "", "and shows no sign")
	updated.queue_free()
	# No room: nothing fetched.
	n = _notice(plugin)
	n.space = func() -> int: return 1000
	apks = server.count(".apk")
	n.press()
	await _until(n, ["full", "handed"])
	check(
		n.stage == "full" and server.count(".apk") == apks, "no room: PLUMB FULL, nothing fetched"
	)
	check(
		n.needed >= body.size() * 2, "it asks room for the download and the install (%d)" % n.needed
	)
	n.space = func() -> int: return 1 << 40
	n.press()
	check(n.stage == "fetching", "room made, TRY AGIN fetches (update.json already read)")
	n.hold()
	check(n.stage == "" and n.aside == "held" and not n.fetcher.busy(), "HOLD IT stops it")
	n.queue_free()
	_clear()
	# Mangled once: fetched again. Twice: CAME OUT BAD, nothing left.
	n = _notice(plugin)
	apks = server.count(".apk")
	server.mangle = 1
	n.press()
	await _until(n, ["handed", "bad"])
	check(
		n.stage == "handed" and server.count(".apk") == apks + 2,
		"mangled once: fetched again and in"
	)
	n.queue_free()
	_clear()
	n = _notice(plugin)
	server.mangle = 2
	n.press()
	await _until(n, ["handed", "bad"])
	check(n.stage == "bad", "mangled twice: CAME OUT BAD")
	check(DirAccess.get_files_at(dir).is_empty(), "and nothing mangled is left on the phone")
	n.queue_free()
	# A game going: no installer over it.
	n = _notice(plugin)
	n.busy = func() -> bool: return true
	var installs := plugin.installs.size()
	n.press()
	await _until(n, ["ready", "handed"])
	check(n.stage == "ready" and n.aside == "busy", "a game going: QUIT YER RUN FIRST")
	check(plugin.installs.size() == installs, "and no installer")
	n.queue_free()
	_clear()
	# No update.json (the release not out yet).
	server.no_manifest = true
	n = _notice(plugin)
	n.press()
	await _until(n, ["missing", "fetching"])
	check(n.stage == "missing", "no update.json: NOT IN YET")
	server.no_manifest = false
	n.queue_free()
	# CHECK FOR UPDATES turned off mid-download: everything stops.
	server.pace = 16384
	n = _notice(plugin)
	n.press()
	await _until(n, ["fetching"])
	for i in 10:
		server.poll()
		await process_frame
	var main: Node = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.update_notice = n
	main.options["update_check"] = 0
	main.start_update_check()
	check(n.stage == "" and not n.fetcher.busy(), "CHECK FOR UPDATES off: the download stops")
	check(not n.shown(main.options), "and the sign comes down")
	var asked := server.seen.size()
	for i in 60:
		server.poll()
		await process_frame
	check(server.seen.size() == asked, "nothing more is asked of the server")
	server.pace = 262144
	main.update_notice = null
	main.queue_free()
	n.queue_free()
	await process_frame
	plugin.free()
	_clear()


func _words() -> void:
	print("\nTHE PANEL'S WORDS")
	var plugin := FakePlugin.new()
	plugin.dir = dir
	var n := UpdateNotice.new("3.11.0", "android")
	root.add_child(n)
	n.use_installer(ApkInstaller.new(plugin))
	n.take("99.99.99")
	n.want_size = 2047 * 1048576
	n.needed = 4095 * 1048576
	n.fetcher.have = 2046 * 1048576
	var r := UpdateSign.RECT_TALL
	var worst := ""
	for pair: Array in UpdateSign.STAGES:
		n.stage = str(pair[0])
		n.aside = str(pair[1])
		for wait: bool in [false, true]:
			n.fetcher.phase = "wait" if wait else ""
			n.fetcher.wait_left = 40.0
			var said := UpdateSign.words(n)
			var notes: Array = said["notes"]
			var fits := notes.size() == 3
			for line: String in notes:
				fits = fits and PixelType.text_width(line, "mini") <= r.size.x - 6
			fits = fits and PixelType.text_width(str(said["head"]), "body") <= r.size.x - 10
			fits = fits and PixelType.text_width(str(said["line"]), "body") <= r.size.x - 8
			var action := str(said["action"])
			var style := UpdateSign.plate_style(action)
			var inset := 14 if style == "heading" else 8
			fits = fits and PixelType.text_width(action, style) <= r.size.x - inset * 2 - 2
			if not fits:
				worst += " %s/%s" % [pair[0], pair[1]]
	n.fetcher.phase = ""
	check(worst == "", "every stage's words fit the tin" + worst)
	n.queue_free()
	plugin.free()


func _write(path: String, data: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()


func _clear() -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))


func _wipe() -> void:
	if DirAccess.dir_exists_absolute(dir):
		_clear()
		DirAccess.remove_absolute(dir)
