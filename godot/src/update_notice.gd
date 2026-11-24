## The update notice (pass 14): on a player's own launch of the Windows or
## Android build, one small background request for the website's version.txt
## (the version the site was built from, release.yml's Pages step). When it
## names a newer version than this one, the title hangs a sign that opens the
## right download (UpdateSign, TitleScreen). Anything wrong (offline, a
## timeout, an error page, a garbled answer) shows nothing, and nothing is
## asked again until the next launch.
##
## Never in the browser (the page updates itself), a tool, a view tour, a
## bench, a smoke run, the dedicated servers or a headless run; never with
## CHECK FOR UPDATES off. Nothing is sent but the plain GET (Godot's own
## User-Agent); nothing else is fetched until the player picks the sign.
##
## On Android with the updater plugin (apk_installer.gd) the sign updates the
## game itself: picked, it reads the release's update.json (the APK's size
## and SHA-256, made by release.yml next to the APK), checks there is room,
## downloads the APK into the app's own folder (UpdateFetch: resumed with a
## Range after a break, retried with growing waits, HOLD IT stops it), checks
## its size and SHA-256 (a mangled file is thrown away and fetched once more),
## then hands it to Android's package installer: the player only says
## INSTALL on the system's prompt. The first time, Android's "install
## unknown apps" switch for the game is off: the sign says so and opens the
## setting, and carries on when the player comes back. Saying no to the
## prompt leaves the sign up to try again. Old APKs are thrown away once the
## game is at their version or later (tidy, at every start). Everything is
## keyed on the version, so the APK always comes from the very release whose
## update.json was read (releases/download/vN/, never latest/).
class_name UpdateNotice
extends Node

const VERSION_URL := "https://treymun.github.io/crazy-legs-mundell-rampage/version.txt"
const RELEASES := "https://github.com/treymun/crazy-legs-mundell-rampage/releases/latest/download/"
## What each platform's sign opens: the APK installs over the old copy (the
## same package, signed with the same lasting key), the installer over the
## old install. Saves live in the profile, never in the install.
const DOWNLOADS := {
	"android": RELEASES + "CrazyLegsMundellRampage.apk",
	"windows": RELEASES + "CrazyLegsMundellRampage_Setup.exe",
}
## The in-game update's files, from the release vN itself.
const RELEASE_DIR := "https://github.com/treymun/crazy-legs-mundell-rampage/releases/download/v%s/"
const APK := "CrazyLegsMundellRampage.apk"
const MANIFEST := "update.json"
## The updater's files: the APK, its .part while downloading, its .json.
const FILE_NAME := (
	"^CrazyLegsMundellRampage-(\\d{1,4}\\.\\d{1,4}\\.\\d{1,4}(?:-[A-Za-z]+\\.\\d{1,4})?)"
	+ "\\.apk(?:\\.part|\\.json)?$"
)
## update.json is a few lines; anything longer is not it.
const MANIFEST_LIMIT := 4096
## Bytes kept free beyond the download and the installer's own copy of it.
const SPARE := 32 * 1048576
## Seconds after coming back from the installer with no answer before the
## sign takes it as a no.
const NO_ANSWER := 1.5
## Seconds the one request may take before it is given up on.
const TIMEOUT := 8.0
## version.txt is one short line; anything longer is not it.
const BODY_LIMIT := 256

## This build's version (project.godot's config/version).
var local_version := ""
## "android" or "windows": which download the sign opens.
var target := ""
## The newer version the site names ("" until one is found: no sign).
var found := ""
## Requests made this run: never more than one.
var asked := 0
## Opens a download (OS.shell_open; a check records the address instead).
var opener := Callable(OS, "shell_open")
## The in-game update (Android with the updater): what it is doing. "" the
## sign's offer; "asking" for update.json; "fetching"; "checking" the size
## and SHA-256; "ready" checked, the installer next; "leave" Android's
## "install unknown apps" switch is off; "handed" the system's prompt is up;
## "full" no room; "bad" mangled twice; "failed" the line gave out;
## "missing" the release has no update.json (yet); "refused" the installer
## would not open.
var stage := ""
## A word on top of the stage: "held" (HOLD IT), "declined" (no to the
## prompt), "busy" (a game is going), "nosettings".
var aside := ""
## The updater (null: no in-game update, the sign opens the download), the
## folder it downloads to, and the download.
var installer: ApkInstaller = null
var folder := ""
var fetcher: UpdateFetch = null
## The APK update.json describes for `found` (0: not read yet).
var want_size := 0
var want_sha := ""
## Mangled downloads this press (the second one gives up), whether the APK on
## disk was checked this run, and the room a download needs (stage "full").
var bad_tries := 0
var verified := false
var needed := 0
## True while a game is going (the installer would end it) and while one is
## being played (the download goes gently); set by the front end.
var busy := Callable()
var light := Callable()
## The room left where the APK goes (DirAccess; a check stands in).
var space := Callable()
## Where the release's files are (RELEASE_DIR; a check serves its own).
var release_dir := RELEASE_DIR
var _http: HTTPRequest = null
var _manifest_http: HTTPRequest = null
var _resume_wait := -1.0


func _init(p_local: String, p_target: String) -> void:
	name = "UpdateNotice"
	local_version = p_local
	target = p_target


## [major, minor, patch, order] of "3.11.0", "v3.11.0", "3.11" or
## "3.11.0-dev.3" (order: a pre-release's number, a release above them all),
## or [] when the text is not a version.
static func parse(text: String) -> Array[int]:
	var shape := RegEx.create_from_string(
		"^v?(\\d{1,4})\\.(\\d{1,4})(?:\\.(\\d{1,4}))?(?:-[A-Za-z]+\\.(\\d{1,4}))?$"
	)
	var parts := shape.search(text.strip_edges())
	if parts == null:
		return []
	var out: Array[int] = [
		int(parts.get_string(1)),
		int(parts.get_string(2)),
		int(parts.get_string(3)) if parts.get_string(3) != "" else 0,
		int(parts.get_string(4)) if parts.get_string(4) != "" else 99999,
	]
	return out


## Whether `remote` is a later version than `local` (3.10.0 after 3.9.9; a
## release after its own pre-releases). Either one garbled: false.
static func newer(remote: String, local: String) -> bool:
	var a := parse(remote)
	var b := parse(local)
	if a.is_empty() or b.is_empty():
		return false
	for i in a.size():
		if a[i] != b[i]:
			return a[i] > b[i]
	return false


## Which download this build would want: "android", "windows" or "" (the
## browser, Linux and anything else have none).
static func platform() -> String:
	if OS.has_feature("web"):
		return ""
	if OS.has_feature("android"):
		return "android"
	if OS.get_name() == "Windows":
		return "windows"
	return ""


## The download a platform's sign opens ("" for none).
static func download_url(plat: String) -> String:
	return str(DOWNLOADS.get(plat, ""))


## The rules on whether to ask at all, from the plain facts (the check walks
## every one).
static func allowed(
	web: bool, headless: bool, tool: bool, player_launch: bool, setting_on: bool, plat: String
) -> bool:
	return not web and not headless and not tool and player_launch and setting_on and plat != ""


## Whether this run of the game should ask: a player's own launch of a
## Windows or Android build with CHECK FOR UPDATES on.
static func wanted(m: MainState) -> bool:
	var loop := Engine.get_main_loop()
	var tool := loop == null or loop.get_script() != null
	var player_launch := not (
		m.smoke
		or m.launch_check
		or m.touring
		or m.demo
		or m.showcase
		or m.view_tour != ""
		or m.view_bench > 0
		or m.play_bench > 0
		or m.dev_commands != ""
		or m.server_level != ""
		or m.lobby_server != ""
	)
	var setting: int = m.options.get("update_check", 1)
	return allowed(
		m.web or OS.has_feature("web"),
		DisplayServer.get_name() == "headless",
		tool,
		player_launch,
		setting == 1,
		platform()
	)


## Ask the site once, in the background. A second call does nothing.
func ask() -> void:
	if asked > 0 or download_url(target) == "":
		return
	asked += 1
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT
	_http.body_size_limit = BODY_LIMIT
	_http.max_redirects = 2
	add_child(_http)
	_http.request_completed.connect(answered)
	if _http.request(VERSION_URL) != OK:
		_finish()


## The answer (HTTPRequest.request_completed): only a clean 200 counts.
func answered(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		take(body.get_string_from_utf8())
	_finish()


## Read version.txt's text: a newer version than this one hangs the sign.
func take(text: String) -> void:
	var version := text.strip_edges()
	if version.length() <= 24 and newer(version, local_version):
		version = version.trim_prefix("v")
		if found == "" or newer(version, found):
			# Newer than an APK already fetched: that one is not wanted now.
			if found != "" and stage == "ready":
				_to("")
			found = version
			want_size = 0
			want_sha = ""
			verified = false


## Whether the title shows the sign now (CHECK FOR UPDATES can be turned off
## while it hangs).
func shown(options: Dictionary) -> bool:
	var setting: int = options.get("update_check", 1)
	return found != "" and setting == 1 and download_url(target) != ""


## The sign was picked: open the download (the browser or the phone's
## downloader takes it from there).
func open_download() -> void:
	var url := download_url(target)
	if url != "":
		opener.call(url)


## What the title says once the download is opened.
func started_note() -> String:
	if target == "android":
		return "DOWNLOADIN'. TAP IT WHEN IT'S DONE."
	return "DOWNLOADIN'. RUN IT WHEN IT'S DONE."


## The sign was picked: the in-game update's next step, else the download
## opened. What the title's note line should say.
func press() -> String:
	if not in_game():
		open_download()
		return started_note()
	match stage:
		"asking", "fetching", "checking":
			hold()
		"ready", "handed":
			put_in()
		"leave":
			_to("leave", "" if installer.open_settings() else "nosettings")
		_:
			begin()
	return ""


## Whether this sign updates the game itself (Android with the updater).
func in_game() -> bool:
	return installer != null and target == "android" and folder != ""


## Use the phone's updater: its folder, its answers, and an APK fetched on an
## earlier run (the sign comes back at PUT IT IN).
func use_installer(p_installer: ApkInstaller) -> void:
	installer = p_installer
	folder = installer.download_dir()
	installer.resumed.connect(_resumed)
	installer.answered.connect(_answered)
	fetcher = UpdateFetch.new()
	fetcher.name = "UpdateFetch"
	add_child(fetcher)
	fetcher.finished.connect(_fetched)
	fetcher.checked.connect(_checked)
	if folder == "":
		return
	tidy(folder, local_version)
	for file in DirAccess.get_files_at(folder):
		var version := file_version(file)
		if not String(file).ends_with(".apk") or not newer(version, local_version):
			continue
		var note := _read_note(version)
		if not note.is_empty() and (found == "" or newer(version, found)):
			found = version
			want_size = note["size"]
			want_sha = note["sha256"]
			_to("ready")


## The version in one of the updater's file names ("" for none of them):
## CrazyLegsMundellRampage-3.12.1.apk, its .part while downloading and its
## .json (update.json's size and SHA-256, kept beside it).
static func file_version(file: String) -> String:
	var shape := RegEx.create_from_string(FILE_NAME)
	var m := shape.search(file)
	return m.get_string(1) if m != null else ""


## Throw away the updater's files for `local` or anything older (the game is
## at that version already: it was updated). How many went.
static func tidy(dir: String, local: String) -> int:
	var gone := 0
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return 0
	for file in DirAccess.get_files_at(dir):
		var version := file_version(file)
		if version != "" and not newer(version, local):
			if DirAccess.remove_absolute(dir.path_join(file)) == OK:
				gone += 1
	return gone


## update.json's word on the APK of `version`: {"size", "sha256"}, or {}
## when it is for another version, garbled or missing the APK.
##   {"version": "3.12.1", "files": {"CrazyLegsMundellRampage.apk":
##     {"size": 200807344, "sha256": "<64 hex>"}, ...}}
static func read_manifest(text: String, version: String) -> Dictionary:
	if text.length() > MANIFEST_LIMIT:
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var data: Variant = json.data
	if not data is Dictionary:
		return {}
	var top: Dictionary = data
	if str(top.get("version", "")).trim_prefix("v") != version.trim_prefix("v"):
		return {}
	var files: Variant = top.get("files", {})
	if not files is Dictionary:
		return {}
	var file_map: Dictionary = files
	var apk: Variant = file_map.get(APK, {})
	if not apk is Dictionary:
		return {}
	var entry: Dictionary = apk
	var bytes: Variant = entry.get("size", 0)
	var sha := str(entry.get("sha256", "")).to_lower()
	if not (bytes is int or bytes is float):
		return {}
	var amount: float = bytes
	var n := floori(amount)
	if n <= 0 or n > 4 * 1024 * 1048576 or float(n) != amount:
		return {}
	if not RegEx.create_from_string("^[0-9a-f]{64}$").search(sha):
		return {}
	return {"size": n, "sha256": sha}


## The release's files for `version`.
func manifest_url(version: String) -> String:
	return release_dir % version + MANIFEST


func apk_url(version: String) -> String:
	return release_dir % version + APK


func apk_path(version := found) -> String:
	return folder.path_join("CrazyLegsMundellRampage-%s.apk" % version)


func part_path(version := found) -> String:
	return apk_path(version) + ".part"


## Megabytes, rounded up, for the sign.
static func megs(bytes: int) -> int:
	return ceili(bytes / 1048576.0)


## How far the download or the check is, 0..1.
func progress() -> float:
	return fetcher.fraction() if fetcher != null else 0.0


## GIT IT: read update.json, then fetch (or check the APK already here).
func begin() -> void:
	if found == "" or not in_game():
		return
	bad_tries = 0
	if want_size > 0:
		_have_manifest()
		return
	_to("asking")
	_manifest_http = HTTPRequest.new()
	_manifest_http.timeout = TIMEOUT
	_manifest_http.body_size_limit = MANIFEST_LIMIT
	_manifest_http.max_redirects = 4
	add_child(_manifest_http)
	_manifest_http.request_completed.connect(_manifest_answered)
	if _manifest_http.request(manifest_url(found)) != OK:
		_drop_manifest_request()
		_to("failed")


## HOLD IT: stop the request, the download or the check (the part on disk
## stays; GIT IT carries on from it).
func hold() -> void:
	_stop_all()
	_to("", "held")


## CHECK FOR UPDATES turned off: everything stops, nothing more is fetched.
func halt() -> void:
	_stop_all()
	_to("")


## PUT IT IN: the checked APK to Android's installer (checked first if this
## run has not), or what stands in the way.
func put_in() -> void:
	if not FileAccess.file_exists(apk_path()):
		verified = false
		begin()
		return
	var going: bool = busy.call() if busy.is_valid() else false
	if going:
		_to("ready", "busy")
		return
	if not verified:
		_to("checking")
		fetcher.verify(apk_path(), want_size, want_sha)
		return
	if not installer.can_install():
		_to("leave")
		return
	var why := installer.install(apk_path())
	_resume_wait = -1.0
	_to("handed" if why == "" else "refused")


func _to(next: String, why := "") -> void:
	stage = next
	aside = why


func _stop_all() -> void:
	_drop_manifest_request()
	if fetcher != null:
		fetcher.stop()
	_resume_wait = -1.0


func _drop_manifest_request() -> void:
	if _manifest_http != null:
		_manifest_http.cancel_request()
		_manifest_http.queue_free()
		_manifest_http = null


func _manifest_answered(
	result: int, code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	_drop_manifest_request()
	if stage != "asking":
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_to("failed")
		return
	var entry := read_manifest(body.get_string_from_utf8(), found) if code == 200 else {}
	if entry.is_empty():
		_to("missing")
		return
	want_size = entry["size"]
	want_sha = entry["sha256"]
	_have_manifest()


## update.json read: check an APK already fetched, else make room and fetch.
func _have_manifest() -> void:
	# Files of any other version are not wanted any more.
	for file in DirAccess.get_files_at(folder):
		var version := file_version(file)
		if version != "" and version != found:
			DirAccess.remove_absolute(folder.path_join(file))
	if FileAccess.file_exists(apk_path()):
		verified = false
		put_in()
		return
	var have := UpdateFetch._length(part_path())
	# The rest of the download, and the installer's own copy of the APK.
	needed = (want_size - have) + want_size + SPARE
	var left := _space_left()
	if left > 0 and left < needed:
		_to("full")
		return
	_to("fetching")
	fetcher.start(apk_url(found), part_path(), want_size)


func _space_left() -> int:
	if space.is_valid():
		var n: int = space.call()
		return n
	var dir := DirAccess.open(folder)
	return dir.get_space_left() if dir != null else 0


func _fetched(ok: bool, why: String) -> void:
	if stage != "fetching":
		return
	if ok:
		_to("checking")
		fetcher.verify(part_path(), want_size, want_sha)
	elif why == "gone":
		_to("missing")
	elif why == "disk":
		needed = want_size * 2 + SPARE
		_to("full")
	elif why == "size":
		_mangled(part_path())
	else:
		_to("failed")


func _checked(ok: bool) -> void:
	if stage != "checking":
		return
	var file := apk_path() if FileAccess.file_exists(apk_path()) else part_path()
	if not ok:
		_mangled(file)
		return
	if file == part_path():
		DirAccess.remove_absolute(apk_path())
		if DirAccess.rename_absolute(part_path(), apk_path()) != OK:
			_to("full")
			return
		_write_note()
	verified = true
	put_in()


## A download that is not what update.json says: thrown away and fetched
## once more from nothing; twice in a press, the sign says so.
func _mangled(file: String) -> void:
	DirAccess.remove_absolute(file)
	DirAccess.remove_absolute(apk_path() + ".json")
	verified = false
	bad_tries += 1
	if bad_tries >= 2:
		_to("bad")
		return
	_to("fetching")
	fetcher.start(apk_url(found), part_path(), want_size)


## update.json's size and SHA-256 kept beside the checked APK, so a later run
## can check it again before installing without asking the release.
func _write_note() -> void:
	var f := FileAccess.open(apk_path() + ".json", FileAccess.WRITE)
	if f != null:
		f.store_string(
			JSON.stringify(
				{"version": found, "files": {APK: {"size": want_size, "sha256": want_sha}}}
			)
		)
		f.close()


func _read_note(version: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(apk_path(version) + ".json")
	return read_manifest(text, version)


## Back in front: from the setting (carry on once it is switched on), or from
## the installer with no answer (taken as a no after a moment).
func _resumed() -> void:
	if stage == "leave" and installer.can_install():
		put_in()
	elif stage == "handed":
		_resume_wait = NO_ANSWER


func _answered(code: int) -> void:
	if stage != "handed":
		return
	_resume_wait = -1.0
	if code == ApkInstaller.DECLINED:
		_to("ready", "declined")
	elif code == ApkInstaller.DONE:
		_to("ready")
	else:
		_to("refused")


func _process(delta: float) -> void:
	if fetcher != null:
		var playing: bool = light.call() if light.is_valid() else false
		fetcher.light = playing
	if _resume_wait >= 0.0:
		_resume_wait -= delta
		if _resume_wait < 0.0 and stage == "handed":
			_to("ready", "declined")


func _finish() -> void:
	if _http != null:
		_http.queue_free()
		_http = null
