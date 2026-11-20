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
## User-Agent); nothing else is fetched.
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
var _http: HTTPRequest = null


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
		found = version.trim_prefix("v")


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


func _finish() -> void:
	if _http != null:
		_http.queue_free()
		_http = null
