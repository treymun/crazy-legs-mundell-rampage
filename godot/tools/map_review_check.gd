## The design review and map check (pass 16, T2: src/map_review/,
## tools/map/map_check_cli.gd): test maps built in memory, each with one
## fault planted, must each be flagged with that fault's code, and the same
## map without it must not be: a lever nobody can reach, a big fight with no
## rounds before it, an open lot with no cover, a hand that sees the start, a
## dead end with nothing in it, a long quiet walk. The chapters as built
## (hickston, sawmill, grainyard) get no MUST FIX. Every line is filled in,
## the verdicts, the auto tour, the report, the command table, the paths from
## the repo root, the contact sheet and a bot run that clears the demo map.
##
##   godot --headless --path godot --script res://tools/map_review_check.gd
##
## Prints MAP REVIEW CHECK OK (check_all runs it).
extends SceneTree

const Compile := preload("res://tools/map/map_compile.gd")
const Source := preload("res://tools/map/map_source.gd")
const Cli := preload("res://tools/map/map_check_cli.gd")
const Bot := preload("res://tools/map/map_bot.gd")
const Playtest := preload("res://tools/map/map_playtest.gd")
const Sheet := preload("res://tools/compare_sheet.gd")
const L := preload("res://src/map_review/review_lines.gd")
const FAULT_CODES := [
	"unreached", "ammo_short", "no_cover", "spawn_seen", "dead_end", "quiet_stretch"
]

var failures: Array[String] = []
var assets: Assets


func _init() -> void:
	_run.call_deferred()


func check(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		print("FAIL ", what)


func _run() -> void:
	assets = Assets.new()
	_planted()
	_chapters()
	_lines_and_verdicts()
	_tour_and_report()
	_tools()
	await _bot()
	if failures.is_empty():
		print("MAP REVIEW CHECK OK")
	else:
		print("MAP REVIEW CHECK FAILED: %d" % failures.size())
	quit(0 if failures.is_empty() else 1)


## A test map: a long yard, the start at its west end, the lever and the exit
## at the east end, hands behind crates along the way with rounds and food
## by it. `width` stretches the yard (the lever and the last hand go with it).
static func doc(extra: Array, width := 48, crates := true, hands := true) -> Dictionary:
	var objects: Array = [
		{
			"id": "ground",
			"type": "yard",
			"rect": [1, 1, width - 1, 31],
			"floor": "dirt",
			"district": "yard"
		},
		{
			"id": "lever",
			"type": "station",
			"at": [width - 7.5, 16.5],
			"label": "PULL IT",
			"prop": "quest_switch"
		},
		{
			"id": "road",
			"type": "exit",
			"at": [width - 2.5, 16.5],
			"label": "GO",
			"shutdown": "lever"
		},
		{"id": "end_billy", "type": "enemy", "kind": "billy", "at": [width - 11.5, 12.5]},
		{"id": "end_shells", "type": "pickup", "name": "shells", "at": [width - 14.5, 17.5]},
	]
	if hands:
		(
			objects
			. append_array(
				[
					{"id": "west_billy", "type": "enemy", "kind": "billy", "at": [18.5, 12.5]},
					{"id": "mid_billy", "type": "enemy", "kind": "billy", "at": [26.5, 20.5]},
					{"id": "west_shells", "type": "pickup", "name": "shells", "at": [12.5, 17.5]},
					{"id": "mid_shells", "type": "pickup", "name": "shells", "at": [24.5, 15.5]},
					{"id": "mid_beer", "type": "pickup", "name": "beer", "at": [20.5, 17.5]},
				]
			)
		)
	if crates:
		var x := 8
		while x < width - 8:
			objects.append(
				{
					"id": "crates_%d" % x,
					"type": "cover",
					"a": [x, 14.6],
					"b": [x + 1.5, 14.6],
					"height": 1,
					"thick": 0.35,
					"tile": "crate_side"
				}
			)
			x += 5
	objects.append_array(extra)
	return {
		"schema": Source.SCHEMA,
		"version": Source.VERSION,
		"id": "zz_review_test",
		"size": [width, 32],
		"border": "hedgerow",
		"meta": {"title": "TEST YARD", "sky": "sky", "layout": 1},
		"districts": [{"id": "yard", "name": "THE YARD"}],
		"spawn": {"at": [3.5, 16.5], "angle": 0},
		"objects": objects,
	}


func review_of(d: Dictionary, opts := {}) -> MapReview:
	var built := Compile.compile(d)
	var level: Dictionary = built["level"]
	check(not level.is_empty(), "%s compiles" % d["id"])
	var lv := LevelData.from_dict(level, assets)
	var o: Dictionary = opts.duplicate()
	o["id"] = "zz_review_test"
	return MapReview.review(lv, o)


static func codes(r: MapReview) -> Dictionary:
	var out := {}
	for f: Dictionary in r.findings:
		out[f["code"]] = f
	return out


func _planted() -> void:
	print("planted faults")
	var clean := review_of(doc([]))
	var quiet := codes(clean)
	for code: String in FAULT_CODES:
		check(
			not quiet.has(code),
			"the clean map has no %s (%s)" % [code, quiet.get(code, {}).get("what", "")]
		)
	check(L.verdict(clean.findings) != "FAIL", "the clean map does not fail")
	var faults := {
		"unreached":
		[
			doc(
				[
					{
						"id": "hayloft",
						"type": "balcony",
						"rect": [30, 4, 34, 8],
						"top": 1.7,
						"open": "s"
					},
					{
						"id": "hay_lever",
						"type": "station",
						"at": [32.5, 6],
						"z": 1.7,
						"label": "HAY",
						"prop": "quest_switch"
					}
				]
			),
			{}
		],
		"ammo_short":
		[
			doc(
				[
					{"id": "gang_1", "type": "enemy", "kind": "billy", "at": [30.5, 22.5]},
					{"id": "gang_2", "type": "enemy", "kind": "billy", "at": [31.5, 23.5]},
					{"id": "gang_3", "type": "enemy", "kind": "billy", "at": [32.5, 22.5]},
					{"id": "gang_4", "type": "enemy", "kind": "billy", "at": [31.5, 21.5]},
					{"id": "gang_5", "type": "enemy", "kind": "billy", "at": [33.5, 23.5]},
					{"id": "gang_6", "type": "enemy", "kind": "billy", "at": [30.5, 24.5]}
				],
				48,
				true,
				false
			),
			{"kit": {"revolver": 12, "shotgun": 0}}
		],
		"no_cover": [doc([], 64, false, false), {}],
		"spawn_seen":
		[doc([{"id": "early_billy", "type": "enemy", "kind": "billy", "at": [9.5, 16.5]}]), {}],
		"dead_end":
		[
			doc(
				[
					{"id": "alley_w", "type": "solid", "rect": [20, 1, 21, 15], "tile": "barn"},
					{"id": "alley_e", "type": "solid", "rect": [22, 1, 23, 15], "tile": "barn"}
				]
			),
			{}
		],
		"quiet_stretch": [doc([], 56, true, false), {}],
	}
	for code: String in faults:
		var pair: Array = faults[code]
		var r := review_of(pair[0], pair[1])
		var got := codes(r)
		check(got.has(code), "the %s map is flagged %s (got %s)" % [code, code, got.keys()])
		if got.has(code):
			var f: Dictionary = got[code]
			print("  %s %s: %s" % [f["level"], code, f["what"]])
			check((f["at"] as Array).size() >= 2, "%s says where" % code)
	var lever := codes(review_of(faults["unreached"][0], {}))
	if lever.has("unreached"):
		check(lever["unreached"]["level"] == "MUST FIX", "an unreached lever is a MUST FIX")
		check(lever["unreached"]["object"] == "hay_lever", "the unreached finding names the lever")


func _chapters() -> void:
	print("chapters as built")
	for id: String in ["hickston", "sawmill", "grainyard"]:
		var lv := LevelData.load_level(id, assets)
		var began := Time.get_ticks_msec()
		var r := MapReview.review(lv, {"id": id})
		var counts := L.counts(r.findings)
		print(
			(
				"  %-10s %d MUST FIX, %d SHOULD, %d NICE in %d ms"
				% [
					id,
					counts["MUST FIX"],
					counts["SHOULD"],
					counts["NICE"],
					Time.get_ticks_msec() - began
				]
			)
		)
		for f: Dictionary in r.findings:
			if f["level"] == "MUST FIX":
				print("    ", f["what"])
		check(counts["MUST FIX"] == 0, "%s has no MUST FIX" % id)
		_filled(r.findings, id)


## Every finding is whole: a level, a place, what, fix and say with every
## word filled in.
func _filled(findings: Array, where: String) -> void:
	for f: Dictionary in findings:
		check(L.LEVELS.has(f["level"]), "%s: %s has a level" % [where, f["code"]])
		for key: String in ["what", "fix", "say"]:
			var text := str(f.get(key, ""))
			check(text != "", "%s: %s has its %s line" % [where, f["code"], key])
			var open := text.find("{")
			check(
				open < 0 or text.substr(open, 3) == '{"i',
				"%s: %s's %s line is filled in (%s)" % [where, f["code"], key, text]
			)
		check(
			str(f["say"]) == str(f["say"]).to_upper(),
			"%s: %s says it upper case" % [where, f["code"]]
		)


func _lines_and_verdicts() -> void:
	print("lines and verdicts")
	var lines: Dictionary = L.data()["lines"]
	for code: String in lines:
		var line: Dictionary = lines[code]
		check(L.LEVELS.has(str(line.get("level", ""))), "line %s has a level" % code)
		var f := L.finding("test", code, [1.0, 2.0, 0.0], {})
		check(f["what"] != "" and f["fix"] != "", "line %s has what and fix" % code)
	var must := L.finding("t", "unreached", [1, 1], {})
	var should := L.finding("t", "dead_end", [1, 1], {})
	var nice := L.finding("t", "flat", [1, 1], {})
	check(L.verdict([]) == "PASS", "nothing found: PASS")
	check(L.verdict([nice]) == "PASS", "NICE only: PASS")
	check(L.verdict([nice, should]) == "WORK", "a SHOULD: WORK")
	check(L.verdict([should, must]) == "FAIL", "a MUST FIX: FAIL")
	check(
		(
			L.place([3.25, 4.0, 1.7]) == "(3.3, 4.0, z 1.7)"
			or L.place([3.25, 4.0, 1.7]).begins_with("(3.")
		),
		"places read"
	)


func _tour_and_report() -> void:
	print("tour and report")
	var errors: Array = []
	var d := Source.read("feedstore", errors)
	var built := Compile.compile(d)
	var lv := LevelData.from_dict(built["level"], assets)
	var r := MapReview.review(lv, {"id": "feedstore"})
	var views := MapTour.views(r)
	check(views.size() >= 6, "the feedstore tour has views (%d)" % views.size())
	check(views[0]["tag"] == "feedstore_start", "the tour starts at the start")
	var tags := {}
	for v: Dictionary in views:
		check(not tags.has(v["tag"]), "tour tag %s once" % v["tag"])
		tags[v["tag"]] = true
		for key: String in ["level", "x", "y", "angle", "what"]:
			check(v.has(key), "tour view %s has %s" % [v["tag"], key])
	check(tags.has("feedstore_station_chute_lever"), "the tour shows the lever")
	check(views.size() <= L.whole("tour_most"), "the tour keeps to tour_most")
	var md := MapReport.markdown(
		{
			"id": "feedstore",
			"verdict": L.verdict(r.findings),
			"findings": r.findings,
			"numbers": r.numbers
		}
	)
	for heading: String in [
		"# Map check: feedstore", "## MUST FIX", "## SHOULD", "## NICE", "## The numbers"
	]:
		check(md.contains(heading), "the report has %s" % heading)


func _tools() -> void:
	print("command table, paths, sheet")
	var cli: Script = load("res://tools/map.gd")
	var table: Dictionary = cli.get_script_constant_map()["COMMANDS"]
	var methods := {}
	for m: Dictionary in cli.get_script_method_list():
		methods[m["name"]] = true
	for command: String in table:
		var handler := String(table[command])
		if handler.begins_with("res://"):
			var script: Script = load(handler)
			check(script != null and script.can_instantiate(), "%s's handler loads" % command)
		else:
			check(methods.has(handler), "%s's method %s is there" % [command, handler])
	for command: String in ["check", "flow", "pictures", "shot", "validate", "build", "render"]:
		check(table.has(command), "map.gd has %s" % command)
	var views := Cli.path("docs/map_examples/feedstore_views.json")
	check(FileAccess.file_exists(views), "a views path from the repo root is found (%s)" % views)
	check(
		Cli.path("tools/map.gd").ends_with("godot/tools/map.gd"), "a path from godot/ is found too"
	)
	var dir := OS.get_cache_dir().path_join("map_review_check")
	DirAccess.make_dir_recursive_absolute(dir)
	var a := Image.create_empty(64, 40, false, Image.FORMAT_RGB8)
	a.fill(Color.RED)
	a.save_png(dir.path_join("a.png"))
	var b := Image.create_empty(64, 40, false, Image.FORMAT_RGB8)
	b.fill(Color.BLUE)
	b.save_png(dir.path_join("b.png"))
	var n := Sheet.contact(
		[
			[dir.path_join("a.png"), "one"],
			[dir.path_join("b.png"), "two"],
			[dir.path_join("none.png"), "x"]
		],
		dir.path_join("sheet.png"),
		2,
		100
	)
	check(n == 2, "the contact sheet takes the two pictures there are")
	var sheet := Image.load_from_file(dir.path_join("sheet.png"))
	check(
		sheet != null and sheet.get_width() == 2 * (100 + Sheet.GAP),
		"the contact sheet is two wide"
	)


func _bot() -> void:
	print("bot run")
	var errors: Array = []
	var d := Source.read("feedstore", errors)
	var built := Compile.compile(d)
	LevelData.preview["feedstore"] = built["level"]
	var main: Control = await Playtest._main(self)
	var bot: Dictionary = Bot.play(main, "feedstore", L.kit(), 1, 1, {"seconds": 240.0, "tries": 2})
	print(
		(
			"  feedstore: %s in %s s, %d death(s), %d kills"
			% [bot["outcome"], bot["secs"], bot["deaths"], bot["kills"]]
		)
	)
	check(bot["outcome"] == "clear", "the bot clears the demo map")
	check((bot["flow"] as Dictionary).has("fight"), "the bot run has its flow numbers")
	var again: Dictionary = Bot.play(
		main, "feedstore", L.kit(), 1, 1, {"seconds": 240.0, "tries": 2}
	)
	check(
		again["secs"] == bot["secs"] and again["kills"] == bot["kills"],
		"the bot run plays the same twice"
	)
	main.queue_free()
	LevelData.preview.erase("feedstore")
	await process_frame
