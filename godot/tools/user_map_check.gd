## Player maps (src/user_maps/, net/net_maps.gd), headless:
##
##   godot --headless --path godot --script res://tools/user_map_check.gd
##
## 1. The examples load, round-trip byte for byte through the canonical text,
##    and host what they say.
## 2. Hostile and broken files are refused with one plain line and never an
##    error: empty, junk, too big, nested ten thousand deep, wrong schema, a
##    newer version, silly sizes, bad letters, things off the map or in walls,
##    too many things, and the like; a 4 MB file on disk is refused unread.
## 3. The MAP SHED's calls: a building in one box, a door, undo and redo, the
##    one-of-a-kind marks moving, a wall over a thing taking it, save and read
##    back, a full shed.
## 4. A custom map plays: alone (the lever, then the truck, by teleport), a 5v5
##    round with ten bots, COUNTY RUN (the horde comes), deathmatch.
## 5. A map save: saved and loaded; refused when the map changed, when it is
##    gone, when it is from a newer game.
## 6. The online lobby: a host on a custom map, a client joins and gets it
##    (hash checked, put where levels load, kept under shared), the match
##    starts on the same level on both; the map changed in the lobby reaches
##    everyone; hostile MAP packets (wrong hash, oversized, a zip bomb, not
##    canonical, junk) are refused and a client given one leaves with the why.
## Maps and saves go under OS.get_cache_dir(), never the player's folder.
extends SceneTree

const STEP := NetSync.STEP

var failures: Array = []
var main: Control
var now := 0.0
var nets: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var folder := OS.get_cache_dir().path_join("clmr-user-map-check")
	_wipe(folder)
	UserMaps.folder_override = folder
	DirAccess.make_dir_recursive_absolute(folder)
	var tally := CrashLog.tally()
	print("== examples")
	_examples()
	print("== hostile files")
	_hostile()
	print("== the shed")
	_shed()
	print("== playing")
	_play_modes()
	print("== saves")
	_saves()
	print("== online")
	_online()
	tally.stop()
	_check(
		tally.errors == 0,
		(
			"no script or engine errors"
			+ ("" if tally.errors == 0 else " (%d: %s)" % [tally.errors, tally.first_errors[0]])
		)
	)
	for net: NetPlay in nets:
		if net.session != null:
			net.session.close()
	UserMaps.folder_override = ""
	_wipe(folder)
	print("")
	print("USER MAP CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)
		if OS.get_environment("GITHUB_ACTIONS") != "":
			print("::error title=user_map_check.gd::%s" % text)


func _wipe(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_wipe(dir_path.path_join(sub))
	for file_name: String in dir.get_files():
		DirAccess.remove_absolute(dir_path.path_join(file_name))
	DirAccess.remove_absolute(dir_path)


func _example(stem: String) -> Dictionary:
	return UserMaps.read(UserMaps.EXAMPLES.path_join(stem + ".json"), "example")


# ------------------------------------------------------------------ 1


func _examples() -> void:
	for stem: String in ["pucketts_back_forty", "the_sale_barn"]:
		var path := UserMaps.EXAMPLES.path_join(stem + ".json")
		var text := FileAccess.get_file_as_string(path)
		var entry := _example(stem)
		_check(not entry.has("error"), "%s loads %s" % [stem, entry.get("error", "")])
		if entry.has("error"):
			continue
		var map: Dictionary = entry["map"]
		_check(UserMap.to_text(map) == text, "%s is in the canonical text, byte for byte" % stem)
		_check(UserMap.warnings(map).is_empty(), "%s: every door hangs in a wall line" % stem)
		var level := UserMapBuild.level(map)
		var lv := LevelData.from_dict(level, main.art)
		_check(
			lv != null and lv.wall_count > 100,
			"%s compiles to a level (%d walls)" % [stem, lv.wall_count]
		)
		var spawn := Vector2(float(level["spawn"][0]), float(level["spawn"][1]))
		_check(not lv.blocked(spawn.x, spawn.y, .2), "%s: the start is open ground" % stem)
	var forty: Dictionary = _example("pucketts_back_forty")["map"]
	var barn: Dictionary = _example("the_sale_barn")["map"]
	_check(
		UserMap.hosts(forty) == PackedStringArray(["solo", "deathmatch", "county"]),
		(
			"the back forty hosts alone, deathmatch and County Run (%s)"
			% ", ".join(UserMap.hosts(forty))
		)
	)
	_check(
		UserMap.hosts(barn).size() == 5,
		"the sale barn hosts every mode (%s)" % ", ".join(UserMap.hosts(barn))
	)
	_check(
		str(UserMap.modes(forty)["bomb"]) == "NEEDS AN ATTACK START.",
		"a mode a map cannot host says why (%s)" % UserMap.modes(forty)["bomb"]
	)
	_check(
		(
			UserMap.level_id(forty) != UserMap.level_id(barn)
			and UserMap.level_id(forty).length() == UserMap.ID_PREFIX.length() + 12
		),
		"each map has its own level id (%s)" % UserMap.level_id(forty)
	)


# ------------------------------------------------------------------ 2


func _hostile() -> void:
	var good := UserMap.to_text(_example("pucketts_back_forty")["map"])
	var doc: Dictionary = JSON.parse_string(good)
	var cases := [
		["empty", ""],
		["junk", "WHAT IN TARNATION"],
		["an array", "[1, 2, 3]"],
		["a bare number", "12"],
		["too big", "{" + " ".repeat(UserMap.limit("bytes") + 10) + "}"],
		["nested 10000 deep", "[".repeat(10000) + "]".repeat(10000)],
		["nested in a key", '{"schema": ' + "[".repeat(3000) + "]".repeat(3000) + "}"],
		["broken half way", good.left(good.length() / 2)],
		["no schema", _with(doc, "schema", "")],
		["another schema", _with(doc, "schema", "clmr-map")],
		["a newer version", _with(doc, "version", 99)],
		["a version that is text", _with(doc, "version", "one")],
		["no name", _with(doc, "name", "")],
		["a name 500 long", _with(doc, "name", "A".repeat(500))],
		["a name with odd letters", _with(doc, "name", "BUBBA" + char(0) + char(0x202E) + "XX")],
		["an author that is a list", _with(doc, "author", [1, 2])],
		["a sky nobody knows", _with(doc, "mood", "hellfire")],
		["size 1000 by 1000", _with(doc, "size", [1000, 1000])],
		["size 0", _with(doc, "size", [0, 0])],
		["size halves", _with(doc, "size", [40.5, 30])],
		["size infinite", good.replace('"size": [40, 30]', '"size": [1e999, 30]')],
		["size three numbers", _with(doc, "size", [40, 30, 2])],
		["rows short", _with(doc, "rows", (doc["rows"] as Array).slice(0, 10))],
		["a row too long", _row_with(doc, 3, "#".repeat(41))],
		["a row of numbers", _row_with(doc, 3, 12345)],
		["a letter the shed does not know", _row_with(doc, 3, "Z".repeat(40))],
		["things not a list", _with(doc, "things", "lots")],
		["a thing too short", _with(doc, "things", [["hand", "billy", 3]])],
		["a thing that is text", _with(doc, "things", ["billy"])],
		["a hand nobody knows", _with(doc, "things", [["hand", "swamp_king", 5, 5, 0]])],
		["a kind nobody knows", _with(doc, "things", [["boss", "billy", 5, 5, 0]])],
		["a thing off the map", _with(doc, "things", [["hand", "billy", 400, 5, 0]])],
		["a thing at minus one", _with(doc, "things", [["hand", "billy", -1, 5, 0]])],
		["a facing of nine", _with(doc, "things", [["hand", "billy", 5, 27, 9]])],
		["a thing in a wall", _with(doc, "things", [["hand", "billy", 0, 0, 0]])],
		[
			"two things on one cell",
			_with(doc, "things", [["hand", "billy", 5, 27, 0], ["loot", "beer", 5, 27, 0]])
		],
		[
			"two starts",
			_with(doc, "things", [["mark", "start", 5, 27, 0], ["mark", "start", 6, 27, 0]])
		],
		["a lamp under the sky", _with(doc, "things", [["prop", "lamp", 5, 27, 0]])],
		["ten thousand things", _with(doc, "things", _many_things(10000))],
		["too many hands", _with(doc, "things", _many_hands(70))],
	]
	for case: Array in cases:
		var raw: PackedByteArray = str(case[1]).to_utf8_buffer()
		var got := UserMap.parse_bytes(raw)
		var said := str(got.get("error", ""))
		_check(
			(
				got.has("error")
				and not got.has("map")
				and said.length() < 80
				and said == said.to_upper()
			),
			"refused: %s (%s)" % [case[0], said]
		)
	# A huge file on disk is refused without reading it.
	var big := UserMaps.folder().path_join("huge.json")
	var file := FileAccess.open(big, FileAccess.WRITE)
	file.store_buffer(_zeros(4 * 1024 * 1024))
	file.close()
	var t0 := Time.get_ticks_msec()
	var entry := UserMaps.read(big)
	_check(
		(
			entry.has("error")
			and str(entry["error"]).begins_with("TOO BIG")
			and Time.get_ticks_msec() - t0 < 200
		),
		"a 4 MB file is refused unread (%s)" % entry.get("error", "")
	)
	DirAccess.remove_absolute(big)
	# A broken file sits on the list with its reason and plays nothing.
	var broken := UserMaps.folder().path_join("broken.json")
	file = FileAccess.open(broken, FileAccess.WRITE)
	file.store_string('{"schema": "clmr-usermap", "version": 1, "name": "OOPS"')
	file.close()
	var listed := UserMaps.list()
	var shown: Dictionary = listed[0] if not listed.is_empty() else {}
	_check(
		(
			shown.get("stem", "") == "broken"
			and shown.has("error")
			and UserMapPlay.why_not(shown, "solo") != ""
		),
		(
			"a broken file shows on the list with why and cannot be played (%s)"
			% shown.get("error", "")
		)
	)
	DirAccess.remove_absolute(broken)


func _zeros(n: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(n)
	return out


func _with(doc: Dictionary, key: String, value: Variant) -> String:
	var copy := doc.duplicate(true)
	copy[key] = value
	return JSON.stringify(copy)


func _row_with(doc: Dictionary, y: int, row: Variant) -> String:
	var copy := doc.duplicate(true)
	copy["rows"][y] = row
	return JSON.stringify(copy)


func _many_things(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(["loot", "beer", 1 + i % 38, 25 + (i / 38) % 3, 0])
	return out


func _many_hands(n: int) -> Array:
	var out: Array = []
	for i in n:
		out.append(["hand", "billy", 1 + i % 38, 25 + i / 38, 0])
	return out


# ------------------------------------------------------------------ 3


func _shed() -> void:
	var ed := MapEditor.new(UserMap.blank(24, 18, "SHED TEST"))
	_pick(ed, "INSIDE", "PLANK FLOOR")
	_pick(ed, "WALLS", "BARN BOARDS")
	ed.begin()
	ed.box(Vector2i(4, 4), Vector2i(10, 9))
	ed.end_stroke()
	_check(
		(
			UserMap.at(ed.map, 4, 4) == "#"
			and UserMap.at(ed.map, 7, 6) == "b"
			and UserMap.at(ed.map, 11, 6) == ","
		),
		"a wall box raises a building: walls round, plank floor in"
	)
	_pick(ed, "WALLS", "SWING DOOR")
	ed.begin()
	ed.apply(Vector2i(10, 6))
	ed.end_stroke()
	_check(
		UserMap.door_way(ed.map, 10, 6) == 1 and UserMap.warnings(ed.map).is_empty(),
		"a door hangs in the east wall"
	)
	_pick(ed, "MARKS", "YOUR START")
	ed.apply(Vector2i(2, 2))
	ed.apply(Vector2i(15, 12))
	_check(
		UserMap.marks(ed.map, "mark", "start") == [[15, 12, 0]],
		"placing your start again moves it (one of a kind)"
	)
	_pick(ed, "HANDS", "BILLY")
	ed.begin()
	ed.apply(Vector2i(7, 6))
	ed.end_stroke()
	_pick(ed, "WALLS", "BRICK")
	ed.begin()
	ed.apply(Vector2i(7, 6))
	ed.end_stroke()
	_check(ed.thing_at(Vector2i(7, 6)).is_empty(), "a wall painted over a hand takes the hand")
	ed.undo()
	_check(
		str(ed.thing_at(Vector2i(7, 6))[1]) == "billy" and UserMap.at(ed.map, 7, 6) == "b",
		"undo brings him back"
	)
	ed.redo()
	_check(UserMap.at(ed.map, 7, 6) == "B", "redo puts the wall back")
	ed.begin()
	ed.erase(Vector2i(7, 6))
	ed.end_stroke()
	_check(UserMap.at(ed.map, 7, 6) == ",", "tearing out a wall leaves pasture")
	_pick(ed, "PROPS", "HANGING LAMP")
	var outside := ed.apply(Vector2i(18, 3))
	_check(
		not outside and ed.note.contains("INSIDE"), "a lamp won't hang under the sky (%s)" % ed.note
	)
	ed.set_text("name", "shed test ü!")
	_check(
		str(ed.map["name"]) == "SHED TEST !",
		"a name keeps the font's letters (%s)" % ed.map["name"]
	)
	var why := ed.save()
	_check(
		why == "" and FileAccess.file_exists(UserMaps.path_of(ed.stem)),
		"the shed saves to the folder (%s)" % ed.stem
	)
	var back := UserMaps.read(UserMaps.path_of(ed.stem))
	_check(
		not back.has("error") and UserMap.to_text(back["map"]) == UserMap.to_text(ed.map),
		"and reads it back the same"
	)
	ed.next_size()
	_check(
		UserMap.width(ed.map) == 32 and UserMap.at(ed.map, 4, 4) == "#",
		"SIZE grows the map and keeps the building"
	)
	# A full shed says so instead of writing.
	var cap := UserMap.limit("maps")
	for i in cap:
		FileAccess.open(UserMaps.path_of("filler_%02d" % i), FileAccess.WRITE).store_string("{}")
	var full := MapEditor.new(UserMap.blank(16, 16, "ONE TOO MANY"))
	_check(
		full.save().begins_with("THE SHED'S FULL"),
		"a full shed refuses another map (%s)" % full.note
	)
	for i in cap:
		DirAccess.remove_absolute(UserMaps.path_of("filler_%02d" % i))


func _pick(ed: MapEditor, tab: String, label: String) -> void:
	for t in MapEditor.TABS.size():
		if str(MapEditor.TABS[t][0]) == tab:
			ed.tab = t
			var list := MapEditor.items(t)
			for i in list.size():
				if str(list[i]["label"]) == label:
					ed.pick_item(i)


# ------------------------------------------------------------------ 4


func _play_modes() -> void:
	var forty: Dictionary = _example("pucketts_back_forty")["map"]
	var barn: Dictionary = _example("the_sale_barn")["map"]
	# Alone: the lever, then the truck.
	var id := UserMaps.register(forty)
	var g: Game = main.make_game(id)
	g.configure({"difficulty": 1})
	var hands := UserMap.marks(forty, "hand", "billy").size()
	_check(
		g.level.id == id and g.enemies.size() == 17 and hands == 6,
		"alone: the back forty with its 17 hands (%d)" % g.enemies.size()
	)
	var lever: LevelData.Station = g.world.stations[0]
	var c := Game.Controls.new()
	for i in 30:
		g.tick(STEP, c)
	g.player.x = lever.x - .8
	g.player.y = lever.y
	g.player.angle = 0.0
	g.player.floor_z = g.world.floor_under(g.player.x, g.player.y, 1.0)
	g.operate_station(lever)
	_check(
		g.stations_done.has("lever") and g.exit_ready(), "throwing the big lever unlocks the truck"
	)
	var exit := g.world.extraction
	g.player.x = exit.x - .8
	g.player.y = exit.y
	g.player.floor_z = 0.0
	g.player.angle = 0.0
	for k in 3:
		GameUse.interact(g)
		g.tick(STEP, c)
	_check(g.won, "reaching the truck wins the map")
	# A 5v5 round on the sale barn, ten bots.
	var vs := UserMaps.register(barn, true)
	var m: Game = main.make_game(vs)
	m.configure({"difficulty": 1})
	_check(
		m.enemies.is_empty() and m.world.extraction == null and m.world.stations.is_empty(),
		"the versus copy has no hands, lever or truck"
	)
	Modes.setup(m, Modes.BOMB, 10, {"arena": vs, "rounds": 2})
	TacticalScreens.human = -1
	var pilots := {}
	for p: Player in m.players:
		pilots[p.slot] = TacticalBot.new(p.slot)
	var st = Modes.feature(m)
	var shots := [0]
	m.events.shot_fired.connect(func(_gun: int) -> void: shots[0] += 1)
	for i in int(70.0 / STEP):
		var given := {}
		for p: Player in m.players:
			if p.health > 0:
				m.focus(p)
				given[p.slot] = pilots[p.slot].steer(m)
		m.focus(m.local_player)
		m.tick(STEP, given)
	var fell := 0
	for p: Player in m.players:
		fell += 1 if p.health <= 0 else 0
	_check(
		int(st.round_no) >= 2 and shots[0] > 20 and fell > 0,
		(
			"5v5 on the sale barn: bots buy, fight and play rounds (round %d, %d shots, %d down)"
			% [st.round_no, shots[0], fell]
		)
	)
	# COUNTY RUN on the back forty: the horde comes.
	var cid := UserMaps.register(forty, true)
	var run: Game = main.make_game(cid)
	run.configure({"difficulty": 1})
	Modes.setup(run, Modes.COUNTY, 1, {})
	var spots := CountySpawner.spots(run)
	var most := 0
	run.cheats.god = true
	for i in int(45.0 / STEP):
		run.tick(STEP, Game.Controls.new())
		most = maxi(most, run.enemies.size())
	_check(
		spots.size() > 20 and most >= 5,
		(
			"County Run on the back forty: %d spawn spots, up to %d hands at once"
			% [spots.size(), most]
		)
	)
	# Deathmatch spreads players over it.
	var dm: Game = main.make_game(cid)
	Modes.setup(dm, Modes.DEATHMATCH, 4, {"arena": cid})
	var points := Modes.spawn_points(dm, Rect2i(), 8)
	_check(points.size() == 8, "deathmatch finds 8 spread spawn points (%d)" % points.size())
	for i in 60:
		dm.tick(STEP, {})


# ------------------------------------------------------------------ 5


func _saves() -> void:
	var source: Dictionary = _example("pucketts_back_forty")["map"]
	var ed := MapEditor.new(source)
	ed.stem = "save_test"
	ed.save()
	var entry := UserMaps.read(UserMaps.path_of("save_test"))
	var m: MainFlow = main
	var quick: String = m._save_path()
	var quick_before := FileAccess.get_modified_time(quick) if FileAccess.file_exists(quick) else -1
	var why := UserMapPlay.play(m, entry, "solo")
	_check(
		why == "" and m.game != null and m.game.level.id == entry["id"],
		"PLAY ALONE starts the map (%s)" % why
	)
	m.game.player.x += 1.0
	m.game.player.health = 77
	m.state = "play"
	UserMapPlay.save(m)
	var path := UserMaps.folder().path_join("saves/mine_save_test.json")
	_check(FileAccess.file_exists(path), "F6 writes the map's own save")
	var quick_after := FileAccess.get_modified_time(quick) if FileAccess.file_exists(quick) else -1
	_check(
		quick_after == quick_before and m.slot_source() == null,
		"and never the campaign's quicksave or slots"
	)
	var loaded: Variant = UserMapPlay.read_save(path, entry, m.make_game)
	_check(
		loaded is Game and (loaded as Game).player.health == 77,
		(
			"the save loads onto its map (health %s)"
			% (loaded.player.health if loaded is Game else loaded)
		)
	)
	_check(UserMapPlay.has_save(entry), "the list sees there is a save")
	# The map changed: refused, the file kept.
	ed.begin()
	_pick(ed, "WALLS", "BRICK")
	ed.apply(Vector2i(20, 20))
	ed.save()
	var changed := UserMaps.read(UserMaps.path_of("save_test"))
	var refused: Variant = UserMapPlay.read_save(path, changed, m.make_game)
	_check(
		refused is String and str(refused).contains("CHANGED") and FileAccess.file_exists(path),
		"a save of a map changed since is refused, kept (%s)" % refused
	)
	var gone: Variant = UserMapPlay.read_save(path, {}, m.make_game)
	_check(
		gone is String and str(gone).contains("GONE"),
		"a save of a map that is gone is refused (%s)" % gone
	)
	var text := FileAccess.get_file_as_string(path)
	var newer := UserMaps.folder().path_join("saves/newer.json")
	FileAccess.open(newer, FileAccess.WRITE).store_string(
		text.replace('"custom_save":1', '"custom_save":7')
	)
	var later: Variant = UserMapPlay.read_save(newer, entry, m.make_game)
	_check(
		later is String and str(later).contains("NEWER"),
		"a save from a newer game is refused (%s)" % later
	)
	var bent := UserMaps.folder().path_join("saves/bent.json")
	var doc: Dictionary = JSON.parse_string(text)
	doc["player"]["health"] = 500
	FileAccess.open(bent, FileAccess.WRITE).store_string(JSON.stringify(doc))
	var bad: Variant = UserMapPlay.read_save(bent, entry, m.make_game)
	_check(bad is String, "a save that does not fit its map is refused (%s)" % bad)
	m.game = null
	m.state = "title"


# ------------------------------------------------------------------ 6


func _make(info: Dictionary) -> Game:
	return main.net_match_game(info)


func _pump(frames: int) -> void:
	for i in frames:
		now += 1000.0 / 60.0
		for net: NetPlay in nets:
			net.poll(now)
		OS.delay_msec(2)


func _wait(what: Callable, most := 300) -> bool:
	for i in most:
		if what.call():
			return true
		_pump(1)
	return what.call()


func _online() -> void:
	var barn: Dictionary = _example("the_sale_barn")["map"]
	var forty: Dictionary = _example("pucketts_back_forty")["map"]
	var port := 43000 + OS.get_process_id() % 12000
	var host: NetPlay = null
	for k in 20:
		host = NetPlay.host_lobby(port + k, "Trey", {}, false, "127.0.0.1")
		if host != null:
			port += k
			break
	_check(host != null, "the host opens a lobby")
	if host == null:
		return
	host.make_match = _make
	nets.append(host)
	NetMaps.pending = barn
	NetMaps.after_open(host)
	var vs := UserMap.level_id(barn, true)
	_check(
		str(host.settings["map"]) == vs and str(host.settings["mode"]) == "bomb",
		(
			"HOST ONLINE puts the sale barn on the lobby (%s, %s)"
			% [host.settings["map"], host.settings["mode"]]
		)
	)
	# The client is another machine: it has never seen the map.
	LevelData.preview.erase(vs)
	_wipe(UserMaps.shared_folder())
	var alice := NetPlay.join_lobby("127.0.0.1:%d" % port, "alice")
	alice.make_match = _make
	nets.append(alice)
	_wait(func() -> bool: return NetMaps.received.has(alice.get_instance_id()))
	_check(alice.phase == "lobby", "ALICE joins")
	_check(
		str(NetMaps.received.get(alice.get_instance_id(), "")) == UserMap.hash_of(barn),
		"ALICE gets the map, its hash checked"
	)
	_check(LevelData.preview.has(vs), "and it is where her game loads levels from")
	var kept := UserMaps.shared_folder().path_join(UserMap.hash_of(barn).substr(0, 16) + ".json")
	_check(
		FileAccess.file_exists(kept) and not UserMaps.read(kept, "shared").has("error"),
		"and kept under shared for next time"
	)
	_wait(func() -> bool: return str(alice.settings.get("map", "")) == vs)
	_check(
		LobbyScreens.value_name("map", alice.settings["map"]) == "THE SALE BARN",
		"her lobby shows the map's name"
	)
	host.set_setting("team_size", 2)
	host.set_setting("rounds", 2)
	alice.ask({"ready": true})
	_wait(func() -> bool: return bool(host.player_of(alice.my_id).get("ready", false)))
	var why := host.start_match()
	_check(why == "", "the host starts the match on it %s" % why)
	_wait(func() -> bool: return alice.phase == "match")
	var hg := host.match_game()
	var ag := alice.match_game()
	_check(
		(
			hg != null
			and ag != null
			and hg.level.id == vs
			and ag.level.id == vs
			and hg.level.solid == ag.level.solid
			and hg.level.wall_count == ag.level.wall_count
		),
		"both play the same level (%s)" % (ag.level.id if ag != null else "none")
	)
	for t in 120:
		now += STEP * 1000.0
		for net: NetPlay in nets:
			net.poll(now)
		host.host_tick({})
		alice.client_input(Game.Controls.new())
		alice.client_play(1)
	_check(alice.client_ready() and alice.phase == "match", "the match plays on the custom map")
	host.back_to_lobby()
	_wait(func() -> bool: return alice.phase == "lobby")
	# The host picks another map: it reaches everyone in the lobby.
	NetMaps.host_map(host, forty)
	_wait(
		func() -> bool:
			return str(NetMaps.received.get(alice.get_instance_id(), "")) == UserMap.hash_of(forty)
	)
	_check(
		str(NetMaps.received.get(alice.get_instance_id(), "")) == UserMap.hash_of(forty),
		"a new map in the lobby reaches ALICE"
	)
	_check(
		str(host.settings["mode"]) == "county",
		"the lobby's MODE moves to one the map can host (%s)" % host.settings["mode"]
	)
	# The packet stays far under the party line's cap, the largest map too.
	var big := UserMap.blank(64, 64, "BIG")
	var rows: Array = big["rows"]
	var letters := ",.:=-_~mbckt123#WBNTCPLSHRJO"
	for y in range(1, 63):
		var row := "H"
		for x in range(1, 63):
			row += letters[(x * 7 + y * 13 + x * y) % letters.length()]
		rows[y] = row + "H"
	var packed := NetMaps.packet(big)
	var data: PackedByteArray = packed["data"]
	_check(
		data.size() < UserMap.limit("bytes") and data.size() < 256 * 1024,
		"the largest map's MAP packet is %d bytes" % data.size()
	)
	# Hostile packets.
	var good := NetMaps.packet(barn)
	var cases := [
		["junk", {"hash": "x", "data": PackedByteArray([1, 2, 3])}],
		["no data", {"hash": good["hash"]}],
		["data that is text", _packet_with(good, "data", "MAP")],
		["no hash", {"data": good["data"]}],
		["a wrong hash", _packet_with(good, "hash", "0".repeat(64))],
		["empty", _packet_with(good, "data", PackedByteArray())],
		["over the cap", _packet_with(good, "data", _zeros(UserMap.limit("bytes") + 1))],
		["a megabyte of nothing", _packet_with(good, "data", _zeros(1024 * 1024))],
		["not the canonical text", _packet_of(UserMap.to_text(barn).replace("\n", "\r\n"))],
		[
			"a hostile map",
			_packet_of('{"schema": "clmr-usermap", "version": 1, "name": "X", "size": [999, 2]}')
		],
	]
	for case: Array in cases:
		var got := NetMaps.unpack(case[1])
		_check(
			got.has("error") and not got.has("map"),
			"a MAP packet refused: %s (%s)" % [case[0], got.get("error", "")]
		)
	NetMaps.take(alice, cases[2][1])
	_check(
		alice.phase == "closed" and alice.reason.contains("MAP WAS NO GOOD"),
		"a client sent a bad map leaves with why (%s)" % alice.reason
	)
	host.leave()


func _packet_with(packet: Dictionary, key: String, value: Variant) -> Dictionary:
	var copy := packet.duplicate()
	copy[key] = value
	return copy


func _packet_of(text: String) -> Dictionary:
	return {"hash": UserMap.hash_text(text), "data": text.to_utf8_buffer()}
