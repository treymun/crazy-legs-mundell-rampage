## The update notice (pass 14): src/update_notice.gd and the title's sign
## (src/ui/update_sign.gd, TitleScreen). Nothing here reaches the website:
## answers are handed to the notice as the request would, and the download
## is recorded, never opened.
##
##   godot --headless --path godot --script res://tools/update_check.gd
##
## - Versions compare as numbers (3.10 after 3.9), a release after its own
##   pre-releases; equal, older and garbled answers are not newer.
## - The sign only when the site names a newer version: not on equal, older,
##   garbage, an error page, a failed or timed-out request, nor with CHECK FOR
##   UPDATES off.
## - The right download per platform (Android the APK, Windows the
##   installer), none elsewhere.
## - When it asks: never in the browser, headless, a tool, a tour or bench,
##   with the setting off or on a platform without a download; one request a
##   run at most.
## - The APK it opens installs over the old copy: the Android preset keeps its
##   package name, its version code is tools/version.gd's for config/version
##   and never below 3.11.0's.
## - A tool's game makes no request (no HTTPRequest anywhere) and has no
##   notice, even asked to start one.
## - The title's sign: clear of the board and the version, reached by keys
##   up from the big plate and right from the office column, by the pointer;
##   pressing it opens the platform's download and says so; gone with the
##   setting off. Android's sign carries the small print.
## UPDATE CHECK OK when all hold.
extends SceneTree

## The two downloads, spelled out here rather than read from the notice.
const REPO := "https://github.com/treymun/crazy-legs-mundell-rampage"
const APK := REPO + "/releases/latest/download/CrazyLegsMundellRampage.apk"
const SETUP := REPO + "/releases/latest/download/CrazyLegsMundellRampage_Setup.exe"

var main
var failures: Array[String] = []
var checks := 0
var opened: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	checks += 1
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures.append(what)


func _run() -> void:
	_versions()
	_answers()
	_downloads()
	_when()
	_android_package()
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await _tool_never_asks()
	await _title_sign()
	main.queue_free()
	await process_frame
	if failures.is_empty():
		print("\n%d checks\nUPDATE CHECK OK" % checks)
		quit(0)
	else:
		print("\n%d of %d FAILED:\n  %s" % [failures.size(), checks, "\n  ".join(failures)])
		quit(1)


func _versions() -> void:
	print("\nVERSIONS")
	var newer := [
		["3.10.0", "3.9.0"],
		["3.10", "3.9"],
		["3.10.0", "3.9.9"],
		["3.11.1", "3.11.0"],
		["3.12.0", "3.11.0"],
		["4.0.0", "3.99.99"],
		["3.11.0", "3.11.0-dev.4"],
		["3.11.0-dev.5", "3.11.0-dev.4"],
		["v3.12.0", "3.11.0"],
		[" 3.12.0\n", "3.11.0"],
	]
	for pair: Array in newer:
		check(UpdateNotice.newer(pair[0], pair[1]), "%s is newer than %s" % [pair[0], pair[1]])
	var not_newer := [
		["3.9.0", "3.10.0"],
		["3.11.0", "3.11.0"],
		["3.11", "3.11.0"],
		["3.10.9", "3.11.0"],
		["3.11.0-dev.4", "3.11.0"],
		["2.99.99", "3.0.0"],
	]
	for pair: Array in not_newer:
		check(
			not UpdateNotice.newer(pair[0], pair[1]), "%s is not newer than %s" % [pair[0], pair[1]]
		)
	var garbage := [
		"",
		"garbage",
		"<!DOCTYPE html><title>404</title>",
		"3",
		"3.x.0",
		"3.12.0.1",
		"-3.12.0",
		"3.12.0 beta",
		"99999.0.0",
		"NaN.NaN.NaN",
	]
	var none_newer := true
	for text: String in garbage:
		if UpdateNotice.newer(text, "3.11.0") or UpdateNotice.newer("3.11.0", text):
			none_newer = false
			print("    newer either way: '%s'" % text)
	check(none_newer, "a garbled version is never newer, nor older (%d tried)" % garbage.size())
	check(UpdateNotice.parse(" 3.11.0\n") == [3, 11, 0, 99999], "version.txt's line reads")
	check(UpdateNotice.parse("3.11.0-dev.3") == [3, 11, 0, 3], "a pre-release reads")


func _answers() -> void:
	print("\nTHE SIGN ONLY WHEN NEWER")
	var cases := [
		["3.12.0\n", true],
		["3.11.1", true],
		["3.11.0", false],
		["3.11.0\n", false],
		["3.10.5", false],
		["3.9.12", false],
		["garbage", false],
		["", false],
		["<html><body>Moved</body></html>", false],
		["3.12.0" + " ".repeat(10) + "and more words after it", false],
	]
	for case: Array in cases:
		var n := UpdateNotice.new("3.11.0", "windows")
		n.take(str(case[0]))
		check(
			n.shown({}) == bool(case[1]),
			(
				"the site saying '%s' %s"
				% [str(case[0]).strip_edges(), "shows the sign" if case[1] else "shows nothing"]
			)
		)
		n.free()
	var body := "3.12.0\n".to_utf8_buffer()
	var answers := [
		[HTTPRequest.RESULT_SUCCESS, 200, true, "a clean 200"],
		[HTTPRequest.RESULT_SUCCESS, 404, false, "a 404 page"],
		[HTTPRequest.RESULT_SUCCESS, 500, false, "a server error"],
		[HTTPRequest.RESULT_SUCCESS, 301, false, "a redirect never followed through"],
		[HTTPRequest.RESULT_CANT_CONNECT, 0, false, "offline (can't connect)"],
		[HTTPRequest.RESULT_CANT_RESOLVE, 0, false, "offline (no DNS)"],
		[HTTPRequest.RESULT_TIMEOUT, 0, false, "a timeout"],
		[HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR, 0, false, "a TLS failure"],
		[HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED, 200, false, "an answer too long"],
		[HTTPRequest.RESULT_CONNECTION_ERROR, 0, false, "a dropped connection"],
	]
	for a: Array in answers:
		var n := UpdateNotice.new("3.11.0", "windows")
		n.answered(int(a[0]), int(a[1]), PackedStringArray(), body)
		check(n.shown({}) == bool(a[2]), "%s: %s" % [a[3], "the sign" if a[2] else "nothing"])
		n.free()
	var off := UpdateNotice.new("3.11.0", "android")
	off.take("3.12.0")
	check(off.shown({"update_check": 1}), "the sign with CHECK FOR UPDATES on")
	check(not off.shown({"update_check": 0}), "no sign with CHECK FOR UPDATES off")
	off.free()
	var dev := UpdateNotice.new("3.12.0-dev.2", "windows")
	dev.take("3.12.0")
	check(dev.shown({}) and dev.found == "3.12.0", "a pre-release sees its release")
	dev.free()


func _downloads() -> void:
	print("\nTHE RIGHT DOWNLOAD")
	check(UpdateNotice.download_url("android") == APK, "Android opens the APK")
	check(UpdateNotice.download_url("windows") == SETUP, "Windows opens the installer")
	check(
		UpdateNotice.download_url("") == "" and UpdateNotice.download_url("linux") == "",
		"anything else has no download"
	)
	for target: String in ["android", "windows", ""]:
		var n := UpdateNotice.new("3.11.0", target)
		n.opener = func(url: String) -> void: opened.append(url)
		n.take("3.12.0")
		opened.clear()
		n.open_download()
		var want: Array[String] = []
		if target != "":
			want.append(APK if target == "android" else SETUP)
		check(
			opened == want,
			"the %s sign opens %s" % [target if target != "" else "platformless", want]
		)
		if target == "":
			check(not n.shown({}), "and a build with no download shows no sign")
		n.free()
	check(
		UpdateNotice.platform() == ("windows" if OS.get_name() == "Windows" else ""),
		"this build's platform reads %s on %s" % [UpdateNotice.platform(), OS.get_name()]
	)
	var http := UpdateNotice.new("3.11.0", "")
	http.ask()
	check(http.asked == 0 and http.get_child_count() == 0, "no download, no request")
	http.free()


func _when() -> void:
	print("\nWHEN IT ASKS")
	check(
		UpdateNotice.allowed(false, false, false, true, true, "windows"),
		"a player's own Windows launch asks"
	)
	check(
		UpdateNotice.allowed(false, false, false, true, true, "android"),
		"a player's own Android launch asks"
	)
	check(
		not UpdateNotice.allowed(true, false, false, true, true, "windows"), "not the browser build"
	)
	check(not UpdateNotice.allowed(false, true, false, true, true, "windows"), "not headless")
	check(not UpdateNotice.allowed(false, false, true, true, true, "windows"), "not a tool")
	check(
		not UpdateNotice.allowed(false, false, false, false, true, "windows"),
		"not a tour, bench, smoke run, launch check or server"
	)
	check(
		not UpdateNotice.allowed(false, false, false, true, false, "windows"),
		"not with the setting off"
	)
	check(
		not UpdateNotice.allowed(false, false, false, true, true, ""),
		"not where there is no download"
	)


## The APK the Android sign opens must install over the copy on the phone:
## the same package name, a version code that never goes down (tools/
## version.gd's formula from config/version), and the version name to match.
func _android_package() -> void:
	print("\nTHE APK INSTALLS OVER THE OLD ONE")
	var presets := ConfigFile.new()
	check(presets.load("res://export_presets.cfg") == OK, "the export presets read")
	var options := ""
	for section in presets.get_sections():
		if presets.get_value(section, "platform", "") == "Android":
			options = section + ".options"
	check(options != "", "there is an Android preset")
	if options == "":
		return
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	var parts := UpdateNotice.parse(version)
	var pre := parts[3] != 99999 if not parts.is_empty() else false
	var want := (
		parts[0] * 1000000 + parts[1] * 10000 + parts[2] * 100 + (mini(parts[3], 98) if pre else 99)
		if not parts.is_empty()
		else -1
	)
	var package := str(presets.get_value(options, "package/unique_name", ""))
	var code := int(presets.get_value(options, "version/code", 0))
	check(
		package == "com.hickston.crazylegsmundell", "the package name never changes (%s)" % package
	)
	check(code == want, "the version code is %s's (%d, want %d)" % [version, code, want])
	check(code >= 3110099, "and never below 3.11.0's 3110099 (%d)" % code)
	check(
		str(presets.get_value(options, "version/name", "")) == version,
		"the version name is %s" % version
	)


func _http_nodes() -> int:
	return root.find_children("*", "HTTPRequest", true, false).size()


func _tool_never_asks() -> void:
	print("\nA TOOL NEVER ASKS")
	check(not UpdateNotice.wanted(main), "a tool's game is not one that asks")
	check(main.update_notice == null, "a tool's game has no update notice")
	main.options["update_check"] = 1
	main.start_update_check()
	for i in 10:
		await process_frame
	check(main.update_notice == null, "nor once told to start one (CHECK FOR UPDATES turned on)")
	check(_http_nodes() == 0, "and no request anywhere in the tree")
	var defaults := SessionStore.defaults()
	check(int(defaults.get("update_check", -1)) == 1, "CHECK FOR UPDATES is on by default")


func _title_sign() -> void:
	print("\nTHE TITLE'S SIGN")
	for target: String in ["windows", "android"]:
		var notice := UpdateNotice.new("3.11.0", target)
		notice.opener = func(url: String) -> void: opened.append(url)
		notice.take("3.12.0")
		if main.update_notice != null:
			main.update_notice.free()
		main.update_notice = notice
		main.add_child(notice)
		main.options["update_check"] = 1
		main.state = "title"
		main.selection = 0
		main.render()
		await process_frame
		var screen: TitleScreen = main.ui.screen_for("title")
		check(screen != null, "%s: the title screen is there" % target)
		if screen == null:
			continue
		screen.picked()
		var sign: PixelButton = screen.sign_button()
		check(sign != null, "%s: the sign hangs on the title" % target)
		if sign == null:
			continue
		var rect := Rect2i(sign.get_rect())
		check(rect == UpdateSign.rect(target == "android"), "%s: at its place" % target)
		var clear := Rect2i(0, 0, 320, 200).encloses(rect) and not Menu.BOARD.intersects(rect)
		for item: Dictionary in Menu.title_items(main.entries()):
			if (item["rect"] as Rect2i).intersects(rect):
				clear = false
		# The version in the bottom right corner and the logo's right end.
		if rect.intersects(Rect2i(280, 186, 40, 14)) or rect.intersects(Rect2i(0, 0, 214, 80)):
			clear = false
		check(clear, "%s: clear of the board, the logo and the version" % target)
		# Keys: up from the big plate reaches it, down goes back to the plate.
		var holder: Viewport = sign.get_viewport()
		var rows: Array[PixelButton] = []
		for child in screen.get_children():
			if child is PixelButton and child != sign:
				rows.append(child)
		rows[0].grab_focus()
		await process_frame
		_key(holder, KEY_UP)
		await process_frame
		check(
			holder.gui_get_focus_owner() == sign,
			"%s: up from the big plate picks the sign" % target
		)
		check(screen.picked() == sign, "%s: and the keys stay with it" % target)
		_key(holder, KEY_DOWN)
		await process_frame
		check(
			holder.gui_get_focus_owner() == rows[0] and screen.picked() == rows[0],
			"%s: down from the sign is back on the plate" % target
		)
		var office := -1
		var items := Menu.title_items(main.entries())
		for i in items.size():
			if int(items[i]["column"]) == 1 and office < 0:
				office = i
		rows[office].grab_focus()
		await process_frame
		_key(holder, KEY_RIGHT)
		await process_frame
		check(
			holder.gui_get_focus_owner() == sign,
			"%s: right from the office column picks it" % target
		)
		# Pressing it: ENTER on the focused sign, then a click on it.
		opened.clear()
		main.menu_note = ""
		_key(holder, KEY_ENTER)
		await process_frame
		var want := APK if target == "android" else SETUP
		check(opened == [want], "%s: ENTER opens %s" % [target, want.get_file()])
		check(main.menu_note == notice.started_note(), "%s: and the title says so" % target)
		opened.clear()
		_click(holder, Vector2(rect.get_center()))
		await process_frame
		check(opened == [want], "%s: a click (a tap) opens it too" % target)
		# CHECK FOR UPDATES turned off takes the sign down.
		main.options["update_check"] = 0
		screen.picked()
		check(screen.sign_button() == null, "%s: CHECK FOR UPDATES off takes it down" % target)
		main.options["update_check"] = 1
		screen.picked()
		check(screen.sign_button() != null, "%s: on again, back up" % target)
		screen.leave_sign()
	check(UpdateSign.NOTE.size() == 3, "Android's sign says it installs over the old copy")
	var widest := 0
	for line: String in UpdateSign.NOTE:
		widest = maxi(widest, PixelType.text_width(line, "mini"))
	check(
		widest <= UpdateSign.RECT_TALL.size.x - 6, "its small print fits the tin (%d px)" % widest
	)
	var longest := PixelType.text_width("99.99.99 OUT", "body")
	check(longest <= UpdateSign.RECT.size.x - 8, "a long version fits the sign (%d px)" % longest)
	main.update_notice.found = ""
	screen_reset()


func screen_reset() -> void:
	var screen: TitleScreen = main.ui.screen_for("title")
	screen.picked()
	check(screen.sign_button() == null, "no newer version found: no sign")


## A key as the front end hands it on (UiRoot.take: the focus follows the
## selection first, as in the game).
func _key(_holder: Viewport, code: Key) -> void:
	for down: bool in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = down
		main.ui.take(e)


func _click(holder: Viewport, at: Vector2) -> void:
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	holder.push_input(move, true)
	for down: bool in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.position = at
		e.global_position = at
		e.pressed = down
		holder.push_input(e, true)
