## map.gd's check, flow, pictures and shot (pass 16, T2: the one command an
## AI or a person runs to see what a map is like).
##
## check <id>: one headless process does validate, the build in memory, the
## design review (src/map_review/), the routes (map_playtest.gd), a bot run
## (map_bot.gd) and the plans from above (map_render.gd), then one window
## process (map_pictures.gd, the scratch APPDATA passed down) for the 3D
## pictures of the auto tour (MapTour) and a contact sheet of them all. It
## writes report.md, report.json, the plans, the pictures and sheet.png to
## out=<dir> (default godot/maps/.check/<id>/) and prints the findings and
## MAP-RESULT {verdict, counts, report, seconds}. quick: no bot run and no
## pictures. pictures=0: no window. An id with no source but a built level
## (data/<id>.json) is checked as built (no validate).
##
## flow <id> [seed=1] [skill=1] [runs=1] [diff=1]: the bot run alone.
## pictures <id> [views=<json>] [out=<dir>]: the window pictures alone.
## shot <id> ...: pictures of given places (at=, angle=, pitch= in degrees,
## or views=[{tag, at: [x, y, z], angle, pitch}]); level=<file> a level as
## it is (an older build). Every path given is from the repo root (a path
## that exists from godot/ is taken too).
##
## A run outside a scratch profile starts itself again with one (TEMP/
## clmr-map-tools), so the player's own profile is never touched.
extends RefCounted

const ScratchProfile := preload("res://tools/scratch_profile.gd")
const Playtest := preload("res://tools/map/map_playtest.gd")
const Render := preload("res://tools/map/map_render.gd")
const Bot := preload("res://tools/map/map_bot.gd")
const Sheet := preload("res://tools/compare_sheet.gd")
const L := preload("res://src/map_review/review_lines.gd")
const PICTURE_SECONDS := 240
const PROFILE_VARS := ["APPDATA", "LOCALAPPDATA", "XDG_DATA_HOME", "XDG_CACHE_HOME"]


static func run(cli, command: String) -> int:
	if not ScratchProfile.scratch():
		return _again(cli)
	cli.load_assets()
	match command:
		"check":
			return await check(cli)
		"flow":
			return await flow(cli)
		"pictures", "shot":
			return await pictures_command(cli, command)
	return 2


## The scratch profile a run outside one uses (and passes to its window).
static func scratch_dir() -> String:
	var temp := OS.get_environment("TEMP")
	if temp == "":
		temp = OS.get_environment("TMPDIR")
	if temp == "":
		temp = "/tmp"
	return temp.replace("\\", "/").path_join("clmr-map-tools")


static func _scratch_env(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir.path_join("Local"))
	OS.set_environment("APPDATA", dir)
	OS.set_environment("LOCALAPPDATA", dir.path_join("Local"))
	OS.set_environment("XDG_DATA_HOME", dir)
	OS.set_environment("XDG_CACHE_HOME", dir.path_join("Local"))
	OS.set_environment(ScratchProfile.MARKER, dir)


## Not in a scratch profile: the same command again in one, its output passed on.
static func _again(cli) -> int:
	_scratch_env(scratch_dir())
	var line: Array = ["--headless", "--path", ProjectSettings.globalize_path("res://")]
	line.append_array(["--script", "res://tools/map.gd", "--"])
	line.append_array(OS.get_cmdline_user_args())
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), PackedStringArray(line), output, true)
	for text: String in output:
		printraw(text)
	cli.result = {}
	return code


## A path as given on the command line: absolute as it is, res:// and user://
## as Godot has them, anything else from the repo root (or from godot/ when
## it is there and not at the root).
static func path(given: String) -> String:
	if given.begins_with("res://") or given.begins_with("user://"):
		return ProjectSettings.globalize_path(given)
	if given.is_absolute_path():
		return given
	var root := ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var at_root := root.path_join(given).simplify_path()
	var at_godot := ProjectSettings.globalize_path("res://").path_join(given).simplify_path()
	if not FileAccess.file_exists(at_root) and FileAccess.file_exists(at_godot):
		return at_godot
	return at_root


static func out_dir(cli, map_id: String) -> String:
	if cli.opts.has("out"):
		return path(String(cli.opts["out"]))
	return ProjectSettings.globalize_path("res://maps/.check/%s" % map_id)


## [doc, built, issues] from the source, or from data/<id>.json as built
## when there is no source (doc then holds only the id).
static func load_map(cli, map_id: String) -> Array:
	var source := "res://maps/%s.map.json" % map_id
	if FileAccess.file_exists(source):
		return cli._load(map_id)
	var raw := FileAccess.get_file_as_string("res://data/%s.json" % map_id)
	var parsed = JSON.parse_string(raw) if raw != "" else null
	if not (parsed is Dictionary):
		cli.result["error"] = (
			"no source maps/%s.map.json and no level data/%s.json" % [map_id, map_id]
		)
		return [{}, {}, []]
	var level: Dictionary = parsed
	var spawn: Array = level.get("spawn", [1.5, 1.5, 0.0])
	return [{"id": map_id, "objects": [], "_built": true}, {"level": level, "spawn": spawn}, []]


## A validate issue as a finding.
static func from_issue(i: Dictionary) -> Dictionary:
	var error: bool = i.get("severity", "") == "error"
	var at: Array = i.get("at", [])
	var f := (
		L
		. finding(
			"validate",
			"validate_error" if error else "validate_warning",
			at,
			{
				"message": "%s: %s" % [i.get("code", "?"), i.get("message", "")],
				"hint": str(i.get("hint", "Look at the object it names in the source.")),
				"object": str(i.get("object", "")),
			}
		)
	)
	if str(i.get("code", "")) == "unknown_key":
		f["level"] = "NICE"
	return f


## The source object nearest a finding's place (within .75) when it names none.
static func name_findings(findings: Array, doc: Dictionary) -> void:
	for f: Dictionary in findings:
		if str(f.get("object", "")) != "":
			continue
		var at: Array = f.get("at", [])
		if at.size() < 2:
			continue
		var best := ""
		var best_d := .75
		for o in doc.get("objects", []):
			if not (o is Dictionary) or not o.has("at"):
				continue
			var p: Array = o["at"]
			var d := Vector2(float(p[0]), float(p[1])).distance_to(Vector2(at[0], at[1]))
			if d < best_d:
				best_d = d
				best = String(o.get("id", ""))
		f["object"] = best


static func check(cli) -> int:
	var began := Time.get_ticks_msec()
	var map_id: String = cli._need_id()
	if map_id == "":
		return 2
	var quick: bool = cli.opts.has("quick")
	var dir := out_dir(cli, map_id)
	DirAccess.make_dir_recursive_absolute(dir)
	var loaded := load_map(cli, map_id)
	var doc: Dictionary = loaded[0]
	var built: Dictionary = loaded[1]
	if doc.is_empty():
		return 3
	var findings: Array = []
	for i: Dictionary in loaded[2]:
		findings.append(from_issue(i))
	var res := {"id": map_id, "quick": quick, "out": dir}
	if built.is_empty() or (built.get("level", {}) as Dictionary).is_empty():
		return _write(cli, res, findings, began)
	var level: Dictionary = built["level"]
	var lv := LevelData.from_dict(level, cli.assets)
	var meta: Dictionary = doc.get("meta", {})
	var kit: Dictionary = L.kit()
	kit.merge(meta.get("kit", {}), true)
	var review := MapReview.review(lv, {"id": map_id, "kit": kit})
	findings.append_array(review.findings)
	res["numbers"] = review.numbers
	cli.say("review: %d findings" % review.findings.size())
	# The routes: the source's own, else the spawn to every objective.
	var scenario: Dictionary = doc.get("playtest", {}).duplicate()
	if bool(doc.get("_built", false)) and not scenario.has("routes"):
		var routes: Array = []
		for stop: Array in review.stops:
			var at: Vector3 = stop[1]
			routes.append(
				{"id": "spawn_to_" + str(stop[0]), "from": "spawn", "to": [at.x, at.y, at.z]}
			)
		scenario["routes"] = routes
	var walks: Dictionary = await Playtest.run(cli, doc, built, scenario, {})
	res["routes"] = walks.get("routes", [])
	for r: Dictionary in res["routes"]:
		if not bool(r.get("reached", false)):
			var stuck: Array = r.get("stuck", [])
			(
				findings
				. append(
					(
						L
						. finding(
							"routes",
							"route_failed",
							r.get("end", []),
							{
								"from": "the start",
								"to": str(r.get("id", "?")).trim_prefix("spawn_to_"),
								"short": r.get("short", "?"),
								"end": str(r.get("end", "?")),
								"stuck": "" if stuck.is_empty() else ", stuck at %s" % str(stuck),
								"map": map_id,
							}
						)
					)
				)
			)
	cli.say("routes: %d walked" % (res["routes"] as Array).size())
	if not quick:
		var bot := await bot_run(cli, map_id, level, kit, 1, int(cli.opts.get("seed", 1)))
		res["bot"] = bot
		findings.append_array(bot_findings(bot))
		cli.say("bot: %s in %s s, %d death(s)" % [bot["outcome"], bot["secs"], bot["deaths"]])
	res["plans"] = Render.render(
		doc, built, lv, dir, ["nav", "unreachable", "spawns", "objects"], 16
	)
	if not quick and String(cli.opts.get("pictures", "1")) != "0":
		var views := MapTour.views(review)
		var shot := await pictures(map_id, level, views, dir)
		res.merge(shot)
		if shot.has("pictures_skipped"):
			findings.append(
				L.finding("pictures", "pictures_skipped", [], {"why": shot["pictures_skipped"]})
			)
		var entries: Array = []
		for p: Variant in res["plans"]:
			entries.append([String(p), String(p).get_file().get_basename()])
		for p: Dictionary in res.get("pictures", []):
			entries.append([dir.path_join(String(p["file"])), String(p["tag"])])
		var sheet := dir.path_join("sheet.png")
		if Sheet.contact(entries, sheet) > 0:
			res["sheet"] = sheet
	name_findings(findings, doc)
	return _write(cli, res, findings, began)


static func _write(cli, res: Dictionary, findings: Array, began: int) -> int:
	var verdict := L.verdict(findings)
	res["verdict"] = verdict
	res["findings"] = findings
	res["seconds"] = snappedf((Time.get_ticks_msec() - began) / 1000.0, .1)
	var dir: String = res["out"]
	DirAccess.make_dir_recursive_absolute(dir)
	var md := MapReport.markdown(res)
	var f := FileAccess.open(dir.path_join("report.md"), FileAccess.WRITE)
	if f == null:
		cli.result["error"] = "could not write " + dir.path_join("report.md")
		return 3
	f.store_string(md)
	f.close()
	var j := FileAccess.open(dir.path_join("report.json"), FileAccess.WRITE)
	j.store_string(JSON.stringify(res, " ", false))
	j.close()
	var counts := L.counts(findings)
	for item: Dictionary in findings:
		cli.say(
			(
				"%s %s at %s%s: %s"
				% [
					item["level"],
					item["check"],
					L.place(item.get("at", [])),
					"" if str(item.get("object", "")) == "" else " [%s]" % item["object"],
					item["what"]
				]
			)
		)
		if str(item.get("fix", "")) != "":
			cli.say("      fix: " + str(item["fix"]))
	cli.say(L.verdict_line(verdict))
	cli.say("report: " + dir.path_join("report.md"))
	cli.result["id"] = res["id"]
	cli.result["verdict"] = verdict
	cli.result["counts"] = counts
	cli.result["report"] = dir.path_join("report.md")
	cli.result["seconds"] = res["seconds"]
	if res.has("sheet"):
		cli.result["sheet"] = res["sheet"]
	return 1 if verdict == "FAIL" else 0


## The bot run on `level` (handed in as a preview).
static func bot_run(
	cli, map_id: String, level: Dictionary, kit: Dictionary, skill: int, seed_value: int
) -> Dictionary:
	LevelData.preview[map_id] = level
	var main: Control = await Playtest._main(cli)
	var bot: Dictionary = Bot.play(
		main,
		map_id,
		kit,
		skill,
		seed_value,
		{
			"seconds": L.num("bot_seconds"),
			"tries": L.whole("bot_tries"),
			"diff": int(cli.opts.get("diff", 1))
		}
	)
	main.queue_free()
	await cli.process_frame
	LevelData.preview.erase(map_id)
	return bot


static func bot_findings(bot: Dictionary) -> Array:
	var out: Array = []
	var at: Array = bot.get("at", [])
	var skill := str(bot.get("skill", "regular"))
	if bot["outcome"] != "clear":
		out.append(
			L.finding(
				"bot",
				"bot_stuck",
				at,
				{
					"skill": skill,
					"seconds": bot["secs"],
					"outcome": bot["outcome"],
					"at": L.place(at)
				}
			)
		)
	var deaths: int = bot["deaths"]
	if deaths >= L.whole("bot_deaths_should"):
		out.append(L.finding("bot", "bot_deaths", at, {"skill": skill, "deaths": deaths}))
	var flow: Dictionary = bot.get("flow", {})
	if flow.is_empty():
		return out
	var calm: float = flow.get("longest_calm", 0.0)
	if calm > L.num("bot_calm_should"):
		out.append(L.finding("bot", "bot_calm", [], {"seconds": calm, "from": "?"}))
	var secs: float = bot.get("secs", 0.0)
	var fight: float = flow.get("fight", 0.0)
	if secs > 30.0 and fight / secs < L.num("bot_fight_least"):
		out.append(
			L.finding(
				"bot", "bot_fight_share", [], {"share": "%d%%" % roundi(100.0 * fight / secs)}
			)
		)
	var lost: int = flow.get("lost30_n", 0)
	if lost >= L.whole("bot_lost_should"):
		out.append(
			L.finding("bot", "bot_lost", [], {"count": lost, "seconds": flow.get("lost30_s", 0.0)})
		)
	return out


static func flow(cli) -> int:
	var map_id: String = cli._need_id()
	if map_id == "":
		return 2
	var loaded := load_map(cli, map_id)
	var doc: Dictionary = loaded[0]
	var built: Dictionary = loaded[1]
	if built.is_empty():
		cli._report(loaded[2])
		return 1 if not doc.is_empty() else 3
	var meta: Dictionary = doc.get("meta", {})
	var kit: Dictionary = L.kit()
	kit.merge(meta.get("kit", {}), true)
	var seed_value := int(cli.opts.get("seed", 1))
	var runs := int(cli.opts.get("runs", 1))
	var skills: Array = []
	for s in String(cli.opts.get("skill", "1")).split(",", false):
		skills.append(int(s))
	var rows: Array = []
	for skill: int in skills:
		for k in runs:
			var bot := await bot_run(cli, map_id, built["level"], kit, skill, seed_value + k)
			var flow_row: Dictionary = bot["flow"]
			(
				cli
				. say(
					(
						"%s seed %d: %s in %s s, %d death(s), %d kills, fight %s s, longest calm %s s, lost %s"
						% [
							bot["skill"],
							seed_value + k,
							bot["outcome"],
							bot["secs"],
							bot["deaths"],
							bot["kills"],
							flow_row.get("fight", "?"),
							flow_row.get("longest_calm", "?"),
							flow_row.get("lost30_n", "?")
						]
					)
				)
			)
			bot.erase("attempts")
			rows.append(bot)
	cli.result["runs"] = rows
	return 0


## The window pictures of `views` (MapTour's shape) of `level`: {pictures:
## [{tag, what, file}]} or {pictures_skipped: why}.
static func pictures(map_id: String, level: Dictionary, views: Array, dir: String) -> Dictionary:
	if not ScratchProfile.scratch():
		return {"pictures_skipped": "not in a scratch profile"}
	if views.is_empty():
		return {"pictures": []}
	DirAccess.make_dir_recursive_absolute(dir)
	var level_file := dir.path_join("level.json")
	var tour_file := dir.path_join("tour.json")
	var lf := FileAccess.open(level_file, FileAccess.WRITE)
	lf.store_string(JSON.stringify(level))
	lf.close()
	var tour: Array = []
	for v: Dictionary in views:
		var row := v.duplicate()
		row["level"] = map_id
		tour.append(row)
	var tf := FileAccess.open(tour_file, FileAccess.WRITE)
	tf.store_string(JSON.stringify(tour, " "))
	tf.close()
	for v: Dictionary in tour:
		var old := dir.path_join("%s_fx.png" % v["tag"])
		if FileAccess.file_exists(old):
			DirAccess.remove_absolute(old)
	var line := PackedStringArray(
		[
			"--path",
			ProjectSettings.globalize_path("res://"),
			"--audio-driver",
			"Dummy",
			"--resolution",
			"1280x800",
			"--script",
			"res://tools/map/map_pictures.gd",
			"--",
			"level=" + level_file,
			"id=" + map_id,
			"--view-tour=" + tour_file,
			"--view-out=" + dir,
		]
	)
	var pid := OS.create_process(OS.get_executable_path(), line)
	if pid <= 0:
		return {"pictures_skipped": "the window process did not start"}
	var waited := 0
	while OS.is_process_running(pid) and waited < PICTURE_SECONDS * 10:
		OS.delay_msec(100)
		waited += 1
	if OS.is_process_running(pid):
		OS.kill(pid)
		return {"pictures_skipped": "the window process took over %d s" % PICTURE_SECONDS}
	var out: Array = []
	for v: Dictionary in tour:
		var file := "%s_fx.png" % v["tag"]
		if FileAccess.file_exists(dir.path_join(file)):
			out.append({"tag": v["tag"], "what": v.get("what", ""), "file": file})
	if out.is_empty():
		return {"pictures_skipped": "no window could open (no display?)", "pictures": []}
	return {"pictures": out}


## map pictures / map shot.
static func pictures_command(cli, command: String) -> int:
	var map_id: String = cli._need_id()
	if map_id == "":
		return 2
	var level := {}
	var spawn: Array = []
	if cli.opts.has("level"):
		var parsed = JSON.parse_string(
			FileAccess.get_file_as_string(path(String(cli.opts["level"])))
		)
		if not (parsed is Dictionary):
			cli.result["error"] = "level=%s is not a level file" % cli.opts["level"]
			return 3
		level = parsed
		spawn = level.get("spawn", [1.5, 1.5, 0.0])
	else:
		var loaded := load_map(cli, map_id)
		var built: Dictionary = loaded[1]
		if built.is_empty():
			cli._report(loaded[2])
			return 1 if not (loaded[0] as Dictionary).is_empty() else 3
		level = built["level"]
		spawn = built["spawn"]
	var views: Array = []
	if cli.opts.has("views"):
		var file := path(String(cli.opts["views"]))
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(file))
		if not (parsed is Array):
			cli.result["error"] = (
				"views=%s must be a JSON list of {tag, at: [x, y, z], angle, pitch} (from the repo root: %s)"
				% [cli.opts["views"], file]
			)
			return 2
		for v in parsed:
			if v is Dictionary:
				views.append(_view(v))
	elif command == "shot":
		var at := (
			String(
				cli.opts.get(
					"at", "%s,%s,%s" % [spawn[0], spawn[1], spawn[3] if spawn.size() > 3 else 0.0]
				)
			)
			. split(",")
		)
		(
			views
			. append(
				_view(
					{
						"tag": String(cli.opts.get("tag", "view")),
						"at": [float(at[0]), float(at[1]), float(at[2]) if at.size() > 2 else 0.0],
						"angle": float(cli.opts.get("angle", rad_to_deg(float(spawn[2])))),
						"pitch": float(cli.opts.get("pitch", 0.0)),
					}
				)
			)
		)
	else:
		var lv := LevelData.from_dict(level, cli.assets)
		views = MapTour.views(MapReview.review(lv, {"id": map_id}))
	var dir := (
		path(String(cli.opts["out"]))
		if cli.opts.has("out")
		else ProjectSettings.globalize_path("res://maps/.check/%s/shots" % map_id)
	)
	var shot := await pictures(map_id, level, views, dir)
	cli.result.merge(shot)
	if shot.has("pictures_skipped"):
		cli.say("pictures skipped: " + String(shot["pictures_skipped"]))
		return 1
	for p: Dictionary in shot["pictures"]:
		cli.say("wrote " + dir.path_join(String(p["file"])))
	return 0


## A view as map shot's views list gives it ({tag, at: [x, y, z], angle and
## pitch in degrees}) as the tour reads it (x, y, z, angle in radians).
static func _view(v: Dictionary) -> Dictionary:
	if v.has("x"):
		return v
	var at: Array = v.get("at", [0.0, 0.0, 0.0])
	return {
		"tag": String(v.get("tag", "view")),
		"x": float(at[0]),
		"y": float(at[1]),
		"z": float(at[2]) if at.size() > 2 else 0.0,
		"angle": deg_to_rad(float(v.get("angle", 0.0))),
		"pitch": float(v.get("pitch", 0.0)),
		"weapon": bool(v.get("weapon", false)),
		"what": String(v.get("what", v.get("tag", ""))),
	}
