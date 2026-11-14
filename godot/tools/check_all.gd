## Every headless check at once, in parallel, with one table at the end.
##
##   godot --headless --path godot --script res://tools/check_all.gd [-- lint] [fast]
##
## Each check runs in its own Godot process with its own scratch profile
## (APPDATA), so none of them touches your saves or another check's files.
## lint also runs gdformat --check and gdlint from the repo's .venv; fast
## leaves out the campaign walkthrough, the pictures and the quest reach. Exits 1 if anything
## failed, and prints the end of each failing check's output.
extends SceneTree

## [script, the line that says it passed]
const CHECKS := [
	["check_shader", "SHADER OK"],
	["verify_assets", "ASSETS OK"],
	["check_fixes", "PARITY FIXES OK"],
	["save_fixtures", "OLD SAVES OK"],
	["level_edit_check", "LEVEL EDIT OK"],
	["quest_reach", "QUEST REACH OK"],
	["bot_campaign", "CAMPAIGN WALKTHROUGH OK"],
	["picture_check", "PICTURES OK"],
	["net_showdown_check", "NET SHOWDOWN OK"],
	["net_server_check", "NET SERVER OK"],
	["menu_touch_check", "MENU TOUCH OK"],
]
const SLOW := ["bot_campaign", "picture_check", "quest_reach"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var started := Time.get_ticks_msec()
	var scratch := OS.get_environment("TEMP").path_join(
		"clmr_checks_%d" % Time.get_unix_time_from_system()
	)
	var kept_appdata := OS.get_environment("APPDATA")
	var jobs: Array = []
	for check: Array in CHECKS:
		if args.has("fast") and String(check[0]) in SLOW:
			continue
		var profile := scratch.path_join(String(check[0]))
		DirAccess.make_dir_recursive_absolute(profile)
		# A child takes the environment as it is when it starts.
		OS.set_environment("APPDATA", profile)
		var job := OS.execute_with_pipe(
			OS.get_executable_path(),
			[
				"--headless",
				"--path",
				ProjectSettings.globalize_path("res://"),
				"--script",
				"res://tools/%s.gd" % check[0]
			],
			false
		)
		jobs.append(
			{
				"name": check[0],
				"pass": check[1],
				"job": job,
				"out": "",
				"began": Time.get_ticks_msec(),
				"ms": 0
			}
		)
	OS.set_environment("APPDATA", kept_appdata)
	var lint := []
	if args.has("lint"):
		var venv := (
			ProjectSettings.globalize_path("res://").path_join("../.venv/Scripts").simplify_path()
		)
		for tool in ["gdformat", "gdlint"]:
			var output := []
			var tool_args := (
				["--check", "src", "tools", "addons"]
				if tool == "gdformat"
				else ["src", "tools", "addons"]
			)
			var code := OS.execute(venv.path_join(tool + ".exe"), tool_args, output, true)
			lint.append([tool, code == 0, "\n".join(output)])
	# Read every child's output as it comes, until all have finished.
	var running := jobs.size()
	while running > 0:
		running = 0
		for j: Dictionary in jobs:
			var job: Dictionary = j["job"]
			for stream in ["stdio", "stderr"]:
				var pipe: FileAccess = job.get(stream)
				if pipe == null:
					continue
				var chunk := pipe.get_buffer(65536)
				while chunk.size() > 0:
					j["out"] += chunk.get_string_from_utf8()
					chunk = pipe.get_buffer(65536)
			if OS.is_process_running(int(job["pid"])):
				running += 1
			elif int(j["ms"]) == 0:
				j["ms"] = Time.get_ticks_msec() - int(j["began"])
		OS.delay_msec(100)
	var failed := 0
	print("")
	for row: Array in lint:
		print("%-18s %s" % [row[0], "ok" if row[1] else "FAILED"])
		if not row[1]:
			failed += 1
			print(_tail(String(row[2]), 12))
	for j: Dictionary in jobs:
		var out := String(j["out"])
		var ok := out.contains(String(j["pass"])) and not out.contains("SCRIPT ERROR")
		print("%-18s %-6s %5.1f s" % [j["name"], "ok" if ok else "FAILED", int(j["ms"]) / 1000.0])
		if not ok:
			failed += 1
			print(_tail(out, 25))
	print(
		(
			"%s in %.1f s"
			% [
				"ALL CHECKS OK" if failed == 0 else "%d FAILED" % failed,
				(Time.get_ticks_msec() - started) / 1000.0
			]
		)
	)
	quit(1 if failed else 0)


## The last lines of a check's output, without the engine's exit noise.
func _tail(text: String, count: int) -> String:
	var lines := PackedStringArray()
	for line in text.split("\n"):
		if (
			line.contains("ObjectDB instances")
			or line.contains("resources still in use")
			or line.strip_edges().begins_with("at:")
		):
			continue
		lines.append("    " + line)
	return "\n".join(lines.slice(maxi(0, lines.size() - count)))
