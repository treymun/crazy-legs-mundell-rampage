## Map source version 2's checks (pass 16, T7), run by tools/map_check.gd
## (so by geometry_check and check_fixes) while Source.dir points at its
## scratch folder:
##
## - every v2 type compiles and validates: the two demo maps (maps/shiloh,
##   maps/feud) and a zoo of everything else (each brush, roads, water,
##   looks, logic, versus, prefabs, a curved wall, wide and upper doors,
##   panes), and every kit piece on its own;
## - planted errors give their codes, each with a hint;
## - v1 stays v1: the demo feedstore reads and writes byte for byte, needs
##   version 1, and builds the level that is committed (bar the stale empty
##   ladders key); a v1 file with one v2 object added writes version 2;
## - prefabs place, turn and mirror their objects and rename them;
## - the same source compiles to the same level twice;
## - the versus review: the multiplayer demo has no MUST FIX, a map whose
##   team starts see each other close has, deathmatch takes the map's own
##   starts.
extends RefCounted

const Source := preload("res://tools/map/map_source.gd")
const V2 := preload("res://tools/map/map_source_v2.gd")
const Compile := preload("res://tools/map/map_compile.gd")
const Validate := preload("res://tools/map/map_validate.gd")
const Edit := preload("res://tools/map/map_edit.gd")


static func _read(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func _names(assets: Assets) -> Dictionary:
	var tiles := {}
	for t in assets.tile_index:
		tiles[String(t)] = true
	return {"tiles": tiles}


## Every problem of a source: shape, compile, validate. [issues, built].
static func problems(doc: Dictionary, assets: Assets) -> Array:
	var issues: Array = []
	var full := Source.expand(doc, issues)
	issues.append_array(Source.check(full, _names(assets)))
	for i: Dictionary in issues:
		if i["severity"] == "error":
			return [issues, {}]
	var built := Compile.compile(full)
	issues.append_array(built.get("issues", []))
	issues.append_array(Validate.check(full, built, assets))
	return [issues, built]


static func _errors(issues: Array) -> Array:
	var out: Array = []
	for i: Dictionary in issues:
		if i["severity"] == "error":
			out.append("%s [%s] %s" % [i["code"], i.get("object", ""), i["message"]])
	return out


static func _has(issues: Array, code: String, with_hint := true) -> bool:
	for i: Dictionary in issues:
		if String(i["code"]) == code and (not with_hint or String(i.get("hint", "")) != ""):
			return true
	return false


static func run(main, check: Callable) -> bool:
	print("MAP SOURCE VERSION 2: TYPES, PLANTED ERRORS, V1 KEPT, PREFABS, VERSUS")
	var assets: Assets = main.art
	_demos(assets, check)
	_zoo(assets, check)
	_kit_pieces(assets, check)
	_planted(assets, check)
	_v1_kept(check)
	_prefabs(check)
	_versus(main, assets, check)
	return true


static func _demos(assets: Assets, check: Callable) -> void:
	for id: String in ["shiloh", "feud"]:
		var doc := _read("res://maps/%s.map.json" % id)
		check.call(not doc.is_empty(), "the demo %s reads" % id)
		var got := problems(doc, assets)
		var errors := _errors(got[0])
		check.call(errors.is_empty(), "the demo %s has no errors %s" % [id, errors])
		check.call(V2.needed(doc, Source.TYPES) == 2, "the demo %s needs version 2" % id)
		var lines := FileAccess.get_file_as_string("res://maps/%s.map.json" % id).split("\n")
		check.call(lines.size() < 120, "the demo %s is under 120 lines (%d)" % [id, lines.size()])
		if id == "shiloh" and not (got[1] as Dictionary).is_empty():
			var again := Compile.compile(Source.expand(doc))
			check.call(
				JSON.stringify(again["level"]) == JSON.stringify(got[1]["level"]),
				"the same source compiles to the same level twice"
			)
			var level: Dictionary = got[1]["level"]
			check.call(
				int(level["geometry"]["version"]) == 2, "shiloh's geometry is version 2 (terrain)"
			)
			check.call(
				bool(level["geometry"].get("nav_via", false)), "a v2 source walks by via points"
			)
			check.call(str(level.get("mood", "")) == "farm_dusk", "the map's mood is set")
			check.call(
				not (level.get("area_moods", {}) as Dictionary).is_empty(),
				"the districts' moods are set"
			)
			check.call(
				(level["triggers"] as Array).size() == 2,
				"the kill gate and the wake zone are triggers"
			)
			check.call(
				(level["controlled_doors"] as Array).size() == 3,
				"the switch's and the gate's doors have no handles"
			)
			var keyed := 0
			for d: Dictionary in level["doors"]:
				keyed += 1 if String(d.get("key", "")) == "key_brass" else 0
			check.call(keyed == 1, "the brass key's door wants it")
			var plants := 0
			for bd: Dictionary in level["billboards"]:
				plants += 1 if String(bd["image"]).begins_with("foliage_") else 0
			check.call(plants > 100, "the foliage is planted (%d)" % plants)


## One of every non-kit v2 type on a 48 x 40 map.
static func zoo_doc() -> Dictionary:
	var doc := Source.blank("zoo", 48, 40)
	doc["version"] = 2
	doc["mood"] = "farm_dusk"
	doc["modes"] = ["solo", "deathmatch", "bomb", "hostage"]
	doc["districts"] = [
		{"id": "outside", "name": "OUTSIDE"},
		{"id": "pen", "name": "THE PEN", "rect": [30, 2, 46, 14], "mood": "barn_dark"}
	]
	doc["spawn"] = {"at": [3.5, 20.5], "angle": 0}
	doc["prefabs"] = {
		"crates":
		{
			"size": [3, 2],
			"objects":
			[{"id": "c", "type": "cover", "a": [0.5, 1], "b": [2.5, 1], "height": 1, "thick": 0.6}]
		}
	}
	var objects: Array = doc["objects"]
	(
		objects
		. append_array(
			[
				{
					"id": "knob",
					"type": "terrain",
					"rect": [4, 30, 12, 38],
					"brush": "hill",
					"height": 1.5
				},
				{
					"id": "trench",
					"type": "terrain",
					"rect": [14, 34, 24, 37],
					"brush": "ditch",
					"height": 0.5
				},
				{
					"id": "mesa",
					"type": "terrain",
					"rect": [26, 30, 34, 38],
					"brush": "plateau",
					"height": 1.0
				},
				{
					"id": "slope",
					"type": "terrain",
					"rect": [36, 30, 40, 38],
					"brush": "ramp",
					"height": 1.0,
					"toward": "e"
				},
				{
					"id": "bumps",
					"type": "terrain",
					"rect": [40, 30, 46, 38],
					"brush": "noise",
					"height": 0.6,
					"seed": 3
				},
				{"id": "soft", "type": "terrain", "rect": [40, 30, 46, 38], "brush": "smooth"},
				{
					"id": "set",
					"type": "terrain",
					"rect": [2, 2, 4, 4],
					"brush": "heights",
					"heights": [0, 0, 0, 0, 0.3, 0, 0, 0, 0]
				},
				{"id": "pike", "type": "road", "points": [[24, 1], [24, 39]], "ditch": true},
				{
					"id": "lane",
					"type": "road",
					"points": [[25, 20], [46, 20]],
					"width": 2,
					"surface": "dirt"
				},
				{"id": "run", "type": "creek", "points": [[1, 27], [47, 27]]},
				{"id": "tank", "type": "pond", "at": [8, 12], "radius": 3},
				{"id": "drink", "type": "trough", "at": [12.5, 22.5]},
				{"id": "pines", "type": "foliage", "kind": "pine", "rect": [1, 28, 14, 39]},
				{"id": "shed", "type": "shack", "at": [30, 4], "back_door": false},
				{
					"id": "coop",
					"type": "kit",
					"piece": "fence",
					"at": [30, 12],
					"w": 8,
					"kind": "picket"
				},
				{
					"id": "junk",
					"type": "dress",
					"rect": [28, 2, 46, 16],
					"theme": "junk",
					"count": 1
				},
				{"id": "wood", "type": "vignette", "name": "wood_pile", "at": [36, 4], "wall": "w"},
				{
					"id": "tower",
					"type": "set_piece",
					"kind": "tower",
					"at": [42.5, 24.5],
					"falls": [0, 1]
				},
				{
					"id": "ring",
					"type": "wall",
					"a": [0, 0],
					"b": [0, 0],
					"z1": 1.2,
					"curve": {"centre": [16, 8], "radius": 3, "from": 0, "to": 180}
				},
				{
					"id": "glass",
					"type": "wall",
					"a": [18, 14],
					"b": [22, 14],
					"openings": [{"at": 2, "width": 1, "sill": 0.9, "head": 1.7, "pane": true}]
				},
				{"id": "hall", "type": "building", "rect": [2, 15, 10, 19], "roof": 2.6},
				{"id": "double", "type": "door", "cell": [5, 18], "span": 2, "from": "n"},
				{"id": "billy_a", "type": "enemy", "kind": "billy", "at": [40.5, 8.5]},
				{"id": "billy_b", "type": "enemy", "kind": "billy", "at": [16.5, 22.5]},
				{"id": "lever", "type": "switch", "at": [31.5, 5.5], "opens": ["shed"]},
				{"id": "brass", "type": "key", "at": [6.5, 16.5], "doors": ["double"]},
				{"id": "gate", "type": "kill_gate", "rect": [38, 6, 44, 12], "opens": ["shed"]},
				{
					"id": "sleep",
					"type": "wake_zone",
					"rect": [14, 20, 20, 25],
					"trigger": [12, 18, 22, 26]
				},
				{"id": "howdy", "type": "message", "rect": [2, 19, 6, 23], "text": "HOWDY."},
				{
					"id": "flash",
					"type": "trigger",
					"when": {"station": "lever"},
					"do": [{"shake": 0.4}, {"open": "double"}]
				},
				{"id": "crates1", "type": "prefab", "name": "crates", "at": [16, 16], "turn": 1},
				{"id": "pen", "type": "prefab", "name": "hog_pen", "at": [36, 14], "mirror": true},
				{"id": "bend", "type": "via", "at": [24, 20]},
				{"id": "dm1", "type": "dm_spawn", "at": [3.5, 6.5]},
				{"id": "dm2", "type": "dm_spawn", "at": [44.5, 36.5]},
				{"id": "red", "type": "team_spawn", "team": "attack", "at": [4.5, 24.5]},
				{"id": "blue", "type": "team_spawn", "team": "defend", "at": [44.5, 4.5]},
				{"id": "site_a", "type": "bomb_site", "site": "A", "rect": [28, 22, 34, 26]},
				{"id": "held", "type": "hostage", "at": [30.5, 24.5]},
				{"id": "home", "type": "rescue_zone", "rect": [2, 22, 8, 26]},
				{
					"id": "way_a",
					"type": "bot_route",
					"site": "A",
					"points": [[12.5, 24.5], [30.5, 24.5]]
				},
				{"id": "hold_a", "type": "bot_hold", "site": "A", "at": [32.5, 23.5], "angle": 180},
				{
					"id": "truck",
					"type": "exit",
					"at": [3.5, 37.5],
					"label": "HIT THE ROAD",
					"shutdown": "lever"
				},
			]
		)
	)
	return doc


static func _zoo(assets: Assets, check: Callable) -> void:
	var doc := zoo_doc()
	var got := problems(doc, assets)
	var errors := _errors(got[0])
	check.call(errors.is_empty(), "every v2 type compiles and validates %s" % [errors])
	var built: Dictionary = got[1]
	if built.is_empty():
		return
	var level: Dictionary = built["level"]
	var tac: Dictionary = level.get("tactical", {})
	check.call(
		(tac.get("attack_spawns", []) as Array).size() == 5, "a team start gives five places"
	)
	check.call(
		(tac.get("deathmatch", []) as Array).size() == 2, "the deathmatch starts are in the plan"
	)
	check.call((tac.get("sites", {}) as Dictionary).has("A"), "the bomb site is in the plan")
	check.call((tac.get("routes", {}) as Dictionary).has("A"), "the bots' route is in the plan")
	check.call(Array(tac.get("modes", [])) == doc["modes"], "the modes are in the plan")
	var spans := 0
	for d: Dictionary in level["doors"]:
		spans += 1 if int(d.get("span", 1)) == 2 else 0
	check.call(spans == 1, "a door two cells wide")
	check.call(not (level.get("geo_panes", []) as Array).is_empty(), "a pane in a wall's opening")
	var curve := 0
	var placed := 0
	for s: Dictionary in level["geometry"]["segments"]:
		curve += 1 if String(s["id"]).begins_with("ring_") else 0
	for s: Dictionary in level["geometry"]["segments"]:
		placed += 1 if String(s["id"]).begins_with("crates1_c") else 0
	check.call(curve >= 10, "a curved wall in pieces (%d)" % curve)
	check.call(placed == 1, "a prefab's object placed and renamed")
	check.call(
		(level["geometry"]["terrain"] as Array).size() >= 7, "the brushes and the ditch are terrain"
	)


## Every kit piece as its own type (or as kit) compiles on a small map.
static func _kit_pieces(assets: Assets, check: Callable) -> void:
	var bad: Array = []
	for piece: String in KitPiece.names():
		var doc := Source.blank("kit_" + piece, 40, 40)
		var o := {"id": "it", "type": piece, "at": [8, 8]}
		if piece in V2.KIT_ONLY:
			o = {"id": "it", "type": "kit", "piece": piece, "at": [8, 8]}
		(doc["objects"] as Array).append(o)
		var got := problems(doc, assets)
		if not _errors(got[0]).is_empty():
			bad.append("%s %s" % [piece, _errors(got[0])])
	check.call(bad.is_empty(), "every kit piece compiles as a source object %s" % [bad])


static func _planted(assets: Assets, check: Callable) -> void:
	var cases := [
		["kit_option", [{"id": "h", "type": "farmhouse", "at": [4, 4], "towers": 2}]],
		["kit_size", [{"id": "h", "type": "farmhouse", "at": [4, 4], "w": 40}]],
		[
			"kit_overlap",
			[{"id": "h", "type": "shack", "at": [4, 4]}, {"id": "g", "type": "shack", "at": [6, 5]}]
		],
		["kit_outside", [{"id": "h", "type": "barn", "at": [30, 30]}]],
		[
			"terrain_brush",
			[{"id": "t", "type": "terrain", "rect": [4, 4, 8, 8], "brush": "volcano"}]
		],
		[
			"road_blocked",
			[
				{"id": "w", "type": "solid", "rect": [10, 2, 12, 20], "tile": "brick"},
				{"id": "r", "type": "road", "points": [[2, 10], [30, 10]]}
			]
		],
		[
			"logic_target",
			[{"id": "s", "type": "switch", "at": [5.5, 5.5], "opens": ["no_such_door"]}]
		],
		[
			"logic_target",
			[
				{"id": "k", "type": "kill_gate", "rect": [4, 4, 8, 8], "opens": ["h"]},
				{"id": "h", "type": "shack", "at": [20, 20]}
			]
		],
		[
			"logic_loop",
			[
				{"id": "s1", "type": "switch", "at": [5.5, 5.5], "requires": ["s2"]},
				{"id": "s2", "type": "switch", "at": [7.5, 5.5], "requires": ["s1"]}
			]
		],
		["prefab_missing", [{"id": "p", "type": "prefab", "name": "castle", "at": [4, 4]}]],
		["foliage_kind", [{"id": "f", "type": "foliage", "kind": "palm"}]],
		[
			"mode_missing",
			[
				{"id": "a", "type": "team_spawn", "team": "attack", "at": [4.5, 4.5]},
				{"id": "d", "type": "team_spawn", "team": "defend", "at": [28.5, 28.5]}
			]
		],
		[
			"versus_inside",
			[
				{"id": "w", "type": "solid", "rect": [10, 10, 14, 14], "tile": "brick"},
				{"id": "dm", "type": "dm_spawn", "at": [12.5, 12.5]}
			]
		],
		[
			"cost",
			[
				{"id": "c1", "type": "church", "at": [2, 2], "w": 10, "d": 20},
				{"id": "c2", "type": "church", "at": [13, 2], "w": 10, "d": 20},
				{"id": "c3", "type": "church", "at": [24, 2], "w": 10, "d": 20},
				{"id": "c4", "type": "church", "at": [2, 23], "w": 10, "d": 20},
				{"id": "c5", "type": "church", "at": [13, 23], "w": 10, "d": 20},
				{"id": "c6", "type": "church", "at": [24, 23], "w": 10, "d": 20}
			]
		],
	]
	for c: Array in cases:
		var doc := Source.blank("planted", 36, 44 if c[0] == "cost" else 36)
		doc["version"] = 2
		if c[0] == "mode_missing":
			doc["modes"] = ["bomb"]
		(doc["objects"] as Array).append_array(c[1])
		var got := problems(doc, assets)
		check.call(_has(got[0], c[0]), "a planted %s is named with a hint" % c[0])
	var loop := Source.blank("loop", 20, 20)
	loop["prefabs"] = {"a": [{"id": "x", "type": "prefab", "name": "a", "at": [0, 0]}]}
	(loop["objects"] as Array).append({"id": "p", "type": "prefab", "name": "a", "at": [2, 2]})
	var issues: Array = []
	Source.expand(loop, issues)
	check.call(_has(issues, "prefab_loop"), "a prefab placing itself is named")
	var low := Source.blank("low", 20, 20)
	low["version"] = 1
	(low["objects"] as Array).append({"id": "h", "type": "shack", "at": [4, 4]})
	check.call(
		_has(Source.check(low, {}), "version", true), "a v1 file using v2 is told to say version 2"
	)
	var mood := Source.blank("dull", 20, 20)
	mood["mood"] = "sunny"
	check.call(_has(Source.check(mood, {}), "mood_unknown"), "an unknown mood is named")


## A text with the checkout's line ends as the tools write them (a Windows
## checkout may have CRLF; the tools write LF).
static func _lf(text: String) -> String:
	return text.replace("\r\n", "\n")


static func _v1_kept(check: Callable) -> void:
	var path := "res://maps/feedstore.map.json"
	var text := _lf(FileAccess.get_file_as_string(path))
	var doc := _read(path)
	if FileAccess.file_exists(Source.path_of("roundtrip_v1")):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Source.path_of("roundtrip_v1")))
	check.call(Source.to_text(doc) == text, "a v1 source reads and writes byte for byte")
	check.call(V2.needed(doc, Source.TYPES) == 1, "the v1 demo needs only version 1")
	Source.write("roundtrip_v1", doc.duplicate(true))
	check.call(
		_lf(FileAccess.get_file_as_string(Source.path_of("roundtrip_v1"))) == text,
		"Source.write keeps a v1 source v1, byte for byte"
	)
	# A v1 file with one v2 object writes version 2 (only that line and the object change).
	var out := Edit.apply(
		"roundtrip_v1", "add", ['{"id": "porch_shack", "type": "shack", "at": [22, 15]}'], {}
	)
	var after := _lf(FileAccess.get_file_as_string(Source.path_of("roundtrip_v1")))
	check.call(int(out.get("exit", 1)) == 0, "a kit piece is added to a v1 file")
	check.call(after.contains('"version": 2,'), "a v1 file with one v2 object writes version 2")
	var old_lines := text.split("\n")
	var new_lines := Array(after.split("\n")).filter(
		func(l: String) -> bool: return not l.contains("porch_shack")
	)
	var changed := 0
	for i in mini(old_lines.size(), new_lines.size()):
		changed += 1 if old_lines[i] != new_lines[i] else 0
	# The version line, and a comma after what was the last object.
	check.call(
		new_lines.size() == old_lines.size() and changed == 2,
		"and nothing else changed (%d lines)" % changed
	)
	var turned := Edit.apply("roundtrip_v1", "turn", ["porch_shack"], {})
	var mirrored := Edit.apply("roundtrip_v1", "mirror", ["porch_shack"], {})
	var back := Source.read("roundtrip_v1")
	var o: Dictionary = back["objects"][Source.find(back, "porch_shack")]
	check.call(
		(
			int(turned["exit"]) == 0
			and int(mirrored["exit"]) == 0
			and int(o["turn"]) == 1
			and bool(o["mirror"])
		),
		"turn and mirror a kit piece"
	)
	check.call(
		int(Edit.apply("roundtrip_v1", "turn", ["office"], {})["exit"]) == 2, "a room does not turn"
	)
	# The committed level: what the demo source builds, bar the stale empty ladders key.
	var built := Compile.compile(doc)
	var made := LevelEdit._json(built["level"]).replace(',"ladders":[]', "")
	var kept := _lf(FileAccess.get_file_as_string("res://data/feedstore.json"))
	check.call(
		made.strip_edges() == kept.strip_edges(), "feedstore builds the level that is committed"
	)


static func _prefabs(check: Callable) -> void:
	var doc := {
		"prefabs":
		{
			"pair":
			{
				"size": [4, 2],
				"objects":
				[
					{"id": "box", "type": "solid", "rect": [0, 0, 1, 2], "tile": "brick"},
					{
						"id": "lad",
						"type": "stairs",
						"rect": [1, 0, 4, 1],
						"from": 0,
						"to": 1,
						"toward": "e"
					},
					{"id": "hut", "type": "outhouse", "at": [2, 0]},
				]
			}
		},
		"objects":
		[
			{"id": "p0", "type": "prefab", "name": "pair", "at": [10, 10]},
			{"id": "p1", "type": "prefab", "name": "pair", "at": [10, 10], "turn": 1},
			{"id": "p2", "type": "prefab", "name": "pair", "at": [10, 10], "mirror": true},
		]
	}
	var issues: Array = []
	var full := Source.expand(doc, issues)
	var by := {}
	for o: Dictionary in full["objects"]:
		by[String(o["id"])] = o
	check.call(issues.is_empty() and by.size() == 9, "a prefab places its objects, renamed")
	check.call(by.get("p0_box", {}).get("rect") == [10.0, 10.0, 11.0, 12.0], "unturned, in place")
	check.call(
		by.get("p1_box", {}).get("rect") == [10.0, 10.0, 12.0, 11.0],
		"turned, the footprint turns (%s)" % [by.get("p1_box", {}).get("rect")]
	)
	check.call(String(by.get("p1_lad", {}).get("toward", "")) == "s", "and its stairs rise south")
	check.call(
		by.get("p2_box", {}).get("rect") == [13.0, 10.0, 14.0, 12.0], "mirrored, the box goes east"
	)
	check.call(String(by.get("p2_lad", {}).get("toward", "")) == "w", "and its stairs rise west")
	check.call(
		(
			bool(by.get("p2_hut", {}).get("mirror", false))
			and by.get("p2_hut", {}).get("at") == [10.0, 10.0]
		),
		"a kit piece mirrors with it (%s)" % [by.get("p2_hut", {}).get("at")]
	)
	check.call(int(by.get("p1_hut", {}).get("turn", -1)) == 1, "and turns with it")


static func _versus(main, assets: Assets, check: Callable) -> void:
	var doc := _read("res://maps/feud.map.json")
	var got := problems(doc, assets)
	var built: Dictionary = got[1]
	if built.is_empty():
		check.call(false, "the multiplayer demo builds")
		return
	var lv := LevelData.from_dict(built["level"], assets)
	var r := MapReview.review(lv, {"id": "feud"})
	var must := 0
	for f: Dictionary in r.findings:
		must += 1 if f["level"] != "NICE" else 0
	check.call(must == 0, "the multiplayer demo passes the review (%d to fix)" % must)
	check.call(int(r.numbers.get("dm_spawns", 0)) == 8, "its deathmatch starts are reviewed")
	check.call(r.numbers.has("site_A_attack_steps"), "its sites are measured both ways")
	# The two starts in sight of each other, close: MUST FIX.
	var open := Source.blank("open", 40, 20)
	open["modes"] = ["bomb"]
	(
		(open["objects"] as Array)
		. append_array(
			[
				{"id": "a", "type": "team_spawn", "team": "attack", "at": [5.5, 10.5]},
				{"id": "d", "type": "team_spawn", "team": "defend", "at": [34.5, 10.5]},
				{"id": "s", "type": "bomb_site", "site": "A", "rect": [8, 3, 14, 7]},
				{"id": "dm1", "type": "dm_spawn", "at": [10.5, 10.5]},
				{"id": "dm2", "type": "dm_spawn", "at": [14.5, 10.5]},
			]
		)
	)
	var og := problems(open, assets)
	var ol := LevelData.from_dict(og[1]["level"], assets)
	var o_r := MapReview.review(ol, {"id": "open"})
	var codes := {}
	for f: Dictionary in o_r.findings:
		codes[String(f["code"]) + "|" + String(f["level"])] = true
	check.call(codes.has("team_spawn_seen|MUST FIX"), "team starts in plain sight are a MUST FIX")
	check.call(codes.has("teams_close|SHOULD"), "team starts close together are named")
	check.call(codes.has("spawn_open|SHOULD"), "deathmatch starts in sight close by are named")
	check.call(codes.has("dm_spawns_few|SHOULD"), "too few deathmatch starts are named")
	check.call(codes.has("site_rush|SHOULD"), "a site the attackers reach first is named")
	# Deathmatch starts on the map's own places.
	LevelData.preview["feud"] = built["level"]
	var g: Game = main.make_game("feud")
	Modes.setup(g, Modes.DEATHMATCH, 2)
	g.tick(1.0 / 60.0, Game.Controls.new())
	var st = g.features["mode"]
	var want: Array = built["level"]["tactical"]["deathmatch"]
	check.call(
		st.spawns.size() == want.size(),
		"deathmatch starts on the map's own places (%d)" % st.spawns.size()
	)
	LevelData.preview.erase("feud")
