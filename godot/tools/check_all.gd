## Every headless check at once, in parallel, with one table at the end.
##
##   godot --headless --path godot --script res://tools/check_all.gd [-- lint] [fast] [quick]
##       [only=a,b] [shard=K/N] [jobs=J] [full]
##
## Each check runs in its own Godot process with its own scratch profile and
## cache folder (PROFILE_VARS), so none of them touches your saves or another
## check's files (the tools keep boss checkpoints, County Run and range
## records under OS.get_cache_dir(): shared, two checks starting chapters at
## once would clear each other's). lint also runs gdformat --check and gdlint
## from the repo's .venv, and scripts/audio_qa.py --check with its python; fast
## leaves out the campaign walkthrough, the pictures and the quest reach;
## quick runs only QUICK (a minute or two: the set to run after every change,
## the whole set at the end of a piece of work).
## check_fixes runs as its parts (check_fixes_1 ... , its PARTS) side by side.
## only= runs the named rows; shard=K/N runs the K-th of N even shares of the
## rows by CI_SECONDS (what CI's matrix runs, so every row here is in CI);
## jobs= runs at most J at once; full prints every row's whole output (in
## folded groups on GitHub Actions). Exits 1 if anything failed, and prints
## the end of each failing check's output.
extends SceneTree

## [script, the line that says it passed, its own arguments (optional)]
const CHECKS := [
	["check_shader", "SHADER OK"],
	["view3d_check", "VIEW3D CHECK OK"],
	["view_perf_check", "VIEW PERF CHECK OK"],
	["stress_bench", "STRESS CHECK OK", ["check"]],
	["actor_check", "ACTOR CHECK OK"],
	["verify_assets", "ASSETS OK"],
	["voice_check", "VOICE CHECK OK"],
	["radio_check", "RADIO CHECK OK"],
	["audio_qa_check", "AUDIO QA OK"],
	["pack_check", "PACK CHECK OK"],
	["warm_check", "WARM CHECK OK"],
	["check_fixes", "PARITY FIXES OK"],
	["physics_check", "PHYSICS OK"],
	["live_props_check", "LIVE PROPS OK"],
	["brawl_check", "BRAWL OK"],
	["climb_check", "CLIMB CHECK OK"],
	["vehicle_check", "VEHICLES OK"],
	["vehicle_cab_check", "VEHICLE CAB OK"],
	["vehicle_set_check", "VEHICLE SET OK"],
	["moonshine_check", "MOONSHINE CHECK OK"],
	["opener_check", "OPENER CHECK OK"],
	["opener_camera_check", "OPENER CAMERA OK"],
	["gun_find_check", "GUN FIND OK"],
	["pacing_check", "PACING OK"],
	["balance", "BALANCE OK", ["check"]],
	["hound_check", "HOUND CHECK OK"],
	["hound_walk_check", "HOUND WALK OK"],
	["bench_check", "BENCH CHECK OK"],
	["gun_art_check", "GUN ART OK"],
	["events_check", "EVENTS CHECK OK"],
	["wreck_check", "WRECK CHECK OK"],
	["wreck_motion_check", "WRECK MOTION OK"],
	["blast_check", "BLAST CHECK OK"],
	["plank_check", "PLANK CHECK OK"],
	["wall_looks_check", "WALL LOOKS CHECK OK"],
	["set_piece_check", "SET PIECE CHECK OK"],
	["save_fixtures", "OLD SAVES OK"],
	["level_edit_check", "LEVEL EDIT OK"],
	["quest_reach", "QUEST REACH OK"],
	["bot_campaign", "CAMPAIGN WALKTHROUGH OK"],
	["net_showdown_check", "NET SHOWDOWN OK"],
	["net_server_check", "NET SERVER OK"],
	["menu_touch_check", "MENU TOUCH OK"],
	["camera_check", "CAMERA CHECK OK"],
	["boss_end_check", "BOSS END OK"],
	["bark_check", "BARK CHECK OK"],
	["hud_layout_check", "HUD LAYOUT OK"],
	["county_check", "COUNTY CHECK OK"],
	["county_net_check", "COUNTY NET CHECK OK", ["seconds=30"]],
	["net_soak_all", "NET SOAK ALL OK", ["quick"]],
	["net_party_check", "NET PARTY OK"],
	["relay_check", "RELAY CHECK OK", ["quick"]],
	["games_check", "GAMES CHECK OK"],
	["cover_check", "COVER CHECK OK"],
	["ai_check", "AI CHECK OK"],
	["cpu_check", "CPU CHECK OK"],
	["bot_check", "BOT CHECK OK"],
	["replay_check", "REPLAY CHECK OK", ["quick"]],
	["tune_check", "TUNE CHECK OK"],
	["predict_check", "PREDICT CHECK OK"],
	["net_errors_check", "NET ERRORS OK"],
	["net_lag", "NET LAG OK", ["quick"]],
	["load_check", "LOAD CHECK OK"],
	["load_speed_check", "LOAD SPEED OK"],
	["user_map_check", "USER MAP CHECK OK"],
]
const SLOW := ["bot_campaign", "quest_reach"]
## Rows that measure timing (net_lag's limits on hits that looked like hits,
## stalls, rubber band): they run last, with nothing beside them. Beside
## another check on a 4-core runner net_lag went over its 12% limit.
const ALONE := ["net_lag"]
const QUICK := [
	"check_shader",
	"view3d_check",
	"view_perf_check",
	"actor_check",
	"verify_assets",
	"voice_check",
	"radio_check",
	"audio_qa_check",
	"save_fixtures",
	"level_edit_check",
	"menu_touch_check",
	"warm_check",
	"camera_check",
	"hud_layout_check",
	"opener_check",
	"opener_camera_check",
	"physics_check",
	"live_props_check",
	"brawl_check",
	"gun_art_check",
	"climb_check",
	"games_check",
	"cover_check",
	"ai_check",
	"cpu_check",
	"vehicle_check",
	"vehicle_cab_check",
	"wreck_check",
	"wreck_motion_check",
	"blast_check",
	"plank_check",
	"wall_looks_check",
	"tune_check",
	"predict_check",
	"net_errors_check",
	"user_map_check",
]
## Seconds each row takes on a GitHub runner, from a real run (the step times
## in the Actions log, or this table's own column there), to share the rows
## out evenly with shard=. A row not listed counts as DEFAULT_SECONDS.
const CI_SECONDS := {
	"check_fixes_1": 150,
	"check_fixes_2": 150,
	"check_fixes_3": 150,
	"check_fixes_4": 150,
	"check_fixes_5": 150,
	"check_fixes_6": 150,
	"save_fixtures": 40,
	"county_check": 42,
	"county_net_check": 30,
	"net_soak_all": 150,
	"net_party_check": 60,
	"relay_check": 25,
	"wreck_check": 30,
	"wreck_motion_check": 12,
	"cpu_check": 30,
	"set_piece_check": 45,
	"net_lag": 25,
	"bot_campaign": 22,
	"quest_reach": 20,
	"net_showdown_check": 20,
	"net_errors_check": 10,
	"live_props_check": 15,
	"brawl_check": 20,
	"physics_check": 15,
	"climb_check": 12,
	"net_server_check": 10,
	"vehicle_check": 10,
	"vehicle_set_check": 20,
	"moonshine_check": 20,
	"opener_check": 30,
	"boss_end_check": 60,
	"bark_check": 90,
	"opener_camera_check": 15,
	"gun_find_check": 25,
	"pacing_check": 20,
	"balance_1": 90,
	"balance_2": 180,
	"balance_3": 130,
	"balance_4": 280,
	"balance_5": 300,
	"hound_check": 25,
	"hound_walk_check": 100,
	"actor_check": 20,
	"view_perf_check": 15,
	"stress_bench": 45,
	"bench_check": 12,
	"gun_art_check": 6,
	"events_check": 60,
	"replay_check": 45,
	"load_check": 35,
	"load_speed_check": 40,
	"pack_check": 30,
	"tune_check": 15,
	"user_map_check": 20,
}
const DEFAULT_SECONDS := 8
## Where Godot puts user:// (APPDATA on Windows, XDG_DATA_HOME on Linux) and
## OS.get_cache_dir() (LOCALAPPDATA, XDG_CACHE_HOME): each row gets its own.
const PROFILE_VARS := ["APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CACHE_HOME"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var started := Time.get_ticks_msec()
	var rows := _rows()
	var picked: Array = []
	for row: Dictionary in rows:
		var script := String(row["script"])
		if args.has("fast") and script in SLOW:
			continue
		if args.has("quick") and not script in QUICK:
			continue
		picked.append(row)
	for arg in args:
		if arg.begins_with("only="):
			picked = _only(picked, arg.substr(5).split(","))
		elif arg.begins_with("shard="):
			picked = _shard(picked, arg.substr(6))
	if picked.is_empty():
		print("NOTHING TO RUN: an only= or shard= argument names no check")
		quit(1)
		return
	var cap := picked.size()
	for arg in args:
		if arg.begins_with("jobs="):
			cap = maxi(1, int(arg.substr(5)))
	var temp := OS.get_environment("TEMP")
	if temp.is_empty():
		temp = OS.get_cache_dir()
	var scratch := temp.path_join("clmr_checks_%d" % Time.get_unix_time_from_system())
	var jobs: Array = []
	for row: Dictionary in picked:
		jobs.append(row.merged({"job": {}, "out": "", "began": 0, "ms": 0, "done": false}))
	var lint := []
	if args.has("lint"):
		var venv := _venv()
		for tool in ["gdformat", "gdlint"]:
			var output := []
			var tool_args := (
				["--check", "src", "tools", "addons"]
				if tool == "gdformat"
				else ["src", "tools", "addons"]
			)
			var code := OS.execute(venv.path_join(tool + ".exe"), tool_args, output, true)
			lint.append([tool, code == 0, "\n".join(output)])
		# The sound measured (scripts/audio_qa.py: loudness against each family,
		# true peak, clicks, silences, loop joins, same takes, wiring).
		var qa := []
		var script := (
			ProjectSettings
			. globalize_path("res://")
			. path_join("../scripts/audio_qa.py")
			. simplify_path()
		)
		var qa_code := OS.execute(venv.path_join("python.exe"), [script, "--check"], qa, true)
		lint.append(["audio_qa", qa_code == 0, "\n".join(qa)])
	# Start rows while fewer than `cap` run; read every child's output as it
	# comes, until all have finished. ALONE rows go last, one by one, with
	# nothing beside them.
	var waiting: Array = []
	for j: Dictionary in jobs:
		if not String(j["script"]) in ALONE:
			waiting.append(j)
	for j: Dictionary in jobs:
		if String(j["script"]) in ALONE:
			waiting.append(j)
	var running := 0
	var alone := false
	while not waiting.is_empty() or running > 0:
		while not waiting.is_empty() and running < cap and not alone:
			var j: Dictionary = waiting[0]
			if String(j["script"]) in ALONE:
				if running > 0:
					break
				alone = true
			waiting.pop_front()
			j["job"] = _start(j, scratch)
			j["began"] = Time.get_ticks_msec()
			running += 1
		running = 0
		alone = false
		for j: Dictionary in jobs:
			var job: Dictionary = j["job"]
			if job.is_empty() or bool(j["done"]):
				continue
			_drain(j)
			if OS.is_process_running(int(job["pid"])):
				running += 1
				alone = alone or String(j["script"]) in ALONE
			else:
				# What it wrote just before it ended.
				_drain(j)
				j["done"] = true
				j["ms"] = Time.get_ticks_msec() - int(j["began"])
		# Often: a child whose output pipe is full waits until it is read,
		# and at 100 ms net_lag's online timing came out differently (13% of
		# hits judged misses where a plain run has 8%).
		OS.delay_msec(10)
	var failed := 0
	var groups := OS.get_environment("GITHUB_ACTIONS") == "true"
	if args.has("full"):
		for j: Dictionary in jobs:
			print(("::group::" if groups else "\n== ") + String(j["name"]))
			print(String(j["out"]).strip_edges())
			if groups:
				print("::endgroup::")
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
			if groups:
				print("::error::%s failed (its whole output is above)" % j["name"])
				# Each failing line as its own annotation: the public API shows
				# annotations without a sign-in, and the log needs one.
				var shown := 0
				for line: String in out.split("\n"):
					var text := line.strip_edges()
					if shown < 12 and (text.begins_with("FAIL") or text.contains("SCRIPT ERROR")):
						print("::error::%s: %s" % [j["name"], text.left(300)])
						shown += 1
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


## Every row: CHECKS with check_fixes split into its parts.
func _rows() -> Array:
	var rows: Array = []
	for check: Array in CHECKS:
		var script := String(check[0])
		var own: Array = check[2] if check.size() > 2 else []
		if script in ["check_fixes", "balance"]:
			# Run as its parts, one process each (check_fixes' PARTS, balance's
			# CHECK_PARTS).
			var constants: Dictionary = load("res://tools/%s.gd" % script).get_script_constant_map()
			var count: int = (
				constants["PARTS"].size() if script == "check_fixes" else constants["CHECK_PARTS"]
			)
			for k in range(1, count + 1):
				rows.append(
					{
						"name": "%s_%d" % [script, k],
						"script": script,
						"pass": check[1],
						"args": own + ["part=%d" % k]
					}
				)
			continue
		rows.append({"name": script, "script": script, "pass": check[1], "args": own})
	return rows


## The rows named (a script's name takes all its parts); empty if one is unknown.
func _only(rows: Array, names: PackedStringArray) -> Array:
	var kept: Array = []
	for name in names:
		var found := false
		for row: Dictionary in rows:
			if row["name"] == name or row["script"] == name:
				found = true
				if not kept.has(row):
					kept.append(row)
		if not found:
			push_error("check_all: no check named " + name)
			return []
	return kept


## Share the rows out over N shards, longest first onto the lightest shard
## (by CI_SECONDS), and keep the K-th.
func _shard(rows: Array, spec: String) -> Array:
	var k := int(spec.get_slice("/", 0))
	var n := int(spec.get_slice("/", 1))
	if n < 1 or k < 1 or k > n:
		return []
	var order := rows.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return _seconds(a) > _seconds(b))
	var loads: Array = []
	var shares: Array = []
	for _i in n:
		loads.append(0)
		shares.append([])
	for row: Dictionary in order:
		var lightest := 0
		for i in n:
			if int(loads[i]) < int(loads[lightest]):
				lightest = i
		loads[lightest] = int(loads[lightest]) + _seconds(row)
		shares[lightest].append(row)
	print("shard %d of %d: about %d s of checks" % [k, n, loads[k - 1]])
	return shares[k - 1]


func _seconds(row: Dictionary) -> int:
	return int(CI_SECONDS.get(row["name"], DEFAULT_SECONDS))


## Read what a row's process has written so far.
func _drain(j: Dictionary) -> void:
	var job: Dictionary = j["job"]
	for stream in ["stdio", "stderr"]:
		var pipe: FileAccess = job.get(stream)
		if pipe == null:
			continue
		var chunk := pipe.get_buffer(65536)
		while chunk.size() > 0:
			j["out"] += chunk.get_string_from_utf8()
			chunk = pipe.get_buffer(65536)


## Start one row in its own Godot process and scratch profile.
func _start(row: Dictionary, scratch: String) -> Dictionary:
	var profile := scratch.path_join(String(row["name"]))
	DirAccess.make_dir_recursive_absolute(profile)
	# A child takes the environment as it is when it starts.
	var kept := {}
	for key in PROFILE_VARS:
		kept[key] = OS.get_environment(key)
		OS.set_environment(key, profile)
	var args: Array = row["args"]
	var job := OS.execute_with_pipe(
		OS.get_executable_path(),
		(
			[
				"--headless",
				"--path",
				ProjectSettings.globalize_path("res://"),
				"--script",
				"res://tools/%s.gd" % row["script"]
			]
			+ (["--"] + args if not args.is_empty() else [])
		),
		false
	)
	for key: String in kept:
		if String(kept[key]).is_empty():
			OS.unset_environment(key)
		else:
			OS.set_environment(key, String(kept[key]))
	return job


## The repo's .venv/Scripts: beside the project, or further up (a git
## worktree under .claude/worktrees has none of its own and shares the
## main checkout's).
func _venv() -> String:
	var dir := ProjectSettings.globalize_path("res://").simplify_path()
	for _i in 8:
		dir = dir.get_base_dir()
		var scripts := dir.path_join(".venv/Scripts")
		if FileAccess.file_exists(scripts.path_join("gdformat.exe")):
			return scripts
	return ProjectSettings.globalize_path("res://").path_join("../.venv/Scripts").simplify_path()


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
