## The midway games' checks beyond the range's own (range_check.gd plays
## the games row), headless:
##
##   godot --headless --path godot --script res://tools/games_check.gd
##
## THE RANGE BOARD ON THE LOBBY SERVER (range_board.gd): a lobby server runs
## in this process on 127.0.0.1 and the range's posts and asks knock on it
## over ENet as a player's game would: a best comes back on the board, a
## name's best counts (a lower score leaves it), the board is best first, a
## score past what a game allows and another version's are refused, an ask
## alone hears the board, and COUNTY RUN's daily board still answers beside
## it.
## THE FAIR'S SHOOTING GALLERY (features/fair_gallery.gd): the bell starts a
## round only at the counter; a duck, a can, a bottle and the hog score what
## they are worth; a can shot off its rail flies, bounces and comes to rest
## in the booth, and hit again in the air scores again; the house pays for
## the shots; leaving the counter ends a round; the prizes pay out by score
## (a beer to the pockets, the hat and the bear kept in the save), and the
## booths add no station, door or wall to the chapter.
## THE RANGE'S DUCK ROW (range_targets.gd): a duck turned at its rail's end
## spins round on its stick (edge on halfway) instead of snapping round, and
## rides the other way showing its other face.
## THE TROPHY SHACK (features/trophy_shack.gd): from the bosses beaten (the
## gates open), the range's records and the County Run records, the shack
## stands a statuette on the plinth of each boss beaten and none for the rest,
## a cup for each game with a best, a gnome for each County Run map, and its
## card says so; the shack can be walked into from the Crossroads' start.
extends SceneTree

const NetPorts := preload("res://tools/net_ports.gd")

const RangeLayout := preload("res://src/range_layout.gd")

var failures: Array = []
var main: Control


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var tally := CrashLog.tally()
	_board()
	_gallery()
	_ducks()
	_trophies()
	tally.stop()
	_check(
		tally.errors == 0,
		(
			"no script or engine errors"
			+ ("" if tally.errors == 0 else " (%d: %s)" % [tally.errors, tally.first_errors[0]])
		)
	)
	main.queue_free()
	print("")
	print("GAMES CHECK OK" if failures.is_empty() else "%d GAMES CHECK(S) FAILED" % failures.size())
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


# ------------------------------------------------------------------ the board


func _board() -> void:
	print("THE RANGE BOARD ON THE LOBBY SERVER")
	var server: LobbyServer = null
	var port := NetPorts.pick("games_check")
	for k in 20:
		var config := {
			"bind": "127.0.0.1",
			"lobbies": [{"port": port + k, "lobby_name": "BOARD TEST", "map": "pineacres"}]
		}
		server = LobbyServer.new(config, {"difficulty": 1})
		if not server.rooms.is_empty():
			port = port + k
			break
		server.free()
		server = null
	_check(server != null, "a lobby server opens")
	if server == null:
		return
	root.add_child(server)
	server.set_process(false)
	var kept := RangeBoard.store
	RangeBoard.store = OS.get_cache_dir().path_join("clmr-games-check-board.json")
	if FileAccess.file_exists(RangeBoard.store):
		DirAccess.remove_absolute(RangeBoard.store)
	RangeBoard.server_override = {"address": "127.0.0.1", "port": port}
	RangeBoard.local = false
	RangeBoard.boards.clear()
	var now := [0.0]
	var knock := func(posts: Array, name: String, asks: Array) -> Array:
		RangeBoard.boards.clear()
		for post: Array in posts:
			RangeBoard._posts.append(post)
		for ask: String in asks:
			RangeBoard._asks.append(ask)
		RangeBoard._flush(name)
		for i in 600:
			now[0] += NetSync.STEP * 1000.0
			server.frame(now[0], NetSync.STEP)
			RangeBoard.poll(now[0])
			OS.delay_msec(1)
			if not RangeBoard.busy():
				break
		return RangeBoard.rows("bowling")
	var rows: Array = knock.call([["bowling", 187]], "alice", [])
	_check(
		rows.size() == 1 and String(rows[0][0]) == "ALICE" and int(rows[0][1]) == 187,
		"a bowling game posted comes back on the board (%s)" % [rows]
	)
	knock.call([["bowling", 150]], "bob", [])
	rows = knock.call([["bowling", 120]], "alice", [])
	_check(
		(
			rows.size() == 2
			and String(rows[0][0]) == "ALICE"
			and int(rows[0][1]) == 187
			and String(rows[1][0]) == "BOB"
		),
		"best first, and a name's best counts: a lower game leaves it (%s)" % [rows]
	)
	rows = knock.call([], "", ["bowling"])
	_check(rows.size() == 2, "an ask alone hears the board (%s)" % [rows])
	RangeBoard.boards.clear()
	var version := String(ProjectSettings.get_setting("application/config/version", ""))
	RangeBoard._send({"range": "skeeball", "post": ["CARL", 99999], "version": version})
	RangeBoard._send({"range": "skeeball", "post": ["DAVE", 200], "version": "0.0.1"})
	knock.call([["skeeball", 260]], "erin", [])
	var skee := RangeBoard.rows("skeeball")
	_check(
		skee.size() == 1 and String(skee[0][0]) == "ERIN",
		"a score past what the game allows and another version's are refused (%s)" % [skee]
	)
	var daily := CountyBoard.answer({"map": "county_bayou", "day": CountyBoard.today()})
	_check(
		(
			daily.get("map") == "county_bayou"
			and daily.get("rows") is Array
			and not daily.has("range")
		),
		"COUNTY RUN's daily board still answers beside it"
	)
	_check(FileAccess.file_exists(RangeBoard.store), "the server keeps the board in its own file")
	RangeBoard.server_override = {}
	RangeBoard.store = kept
	RangeBoard.boards.clear()
	for room in server.rooms:
		room.net.finish()
	server.queue_free()


# ------------------------------------------------------------------ the fair


func _aim(g: Game, x: float, y: float, z: float) -> void:
	var p := g.player
	var reach := Vector2(x - p.x, y - p.y).length()
	g.hitscan(atan2(y - p.y, x - p.x), (z - p.eye) / reach, 20.0, 30.0, 0.0)


func _stand(g: Game, x: float, y: float, angle: float) -> void:
	var p := g.player
	p.x = x
	p.y = y
	p.angle = angle
	p.pitch = 0.0
	p.floor_z = g.world.floor_under(x, y, .05)
	p.eye = .95 + g.world.stand(p)


func _ticks(g: Game, n: int) -> void:
	for i in n:
		g.tick(1.0 / 60.0, Game.Controls.new())


func _gallery() -> void:
	print("THE FAIR'S SHOOTING GALLERY")
	RangeBoard.folder_override = OS.get_cache_dir().path_join("clmr-games-check")
	DirAccess.make_dir_recursive_absolute(RangeBoard.folder_override)
	var g: Game = main.make_game("fair")
	g.configure({})
	g.enemies.clear()
	g.enemy_ids.clear()
	var level: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/fair.json"))
	var stations: Array = level["stations"]
	var doors: Array = level["doors"]
	_check(
		g.world.stations.size() == stations.size() and g.world.doors.size() == doors.size(),
		"the gallery and the prize booth add no station or door to the chapter"
	)
	var f = g.features["fair_gallery"]
	_check(f.on, "the fair has its shooting gallery")
	var floor_z: float = g.world.elevation(98.5, 46.0)
	# The bell from away from the counter rings but starts nothing.
	_stand(g, 98.5, 53.0, -PI / 2.0)
	_aim(g, f.BELL.x, f.BELL.y, floor_z + f.BELL.z - .08)
	_check(not f.round_on and f.bell > 0.0, "the bell rings from afar but starts no round")
	_stand(g, 98.5, 49.6, -PI / 2.0)
	_aim(g, f.BELL.x, f.BELL.y, floor_z + f.BELL.z - .08)
	_check(f.round_on, "shooting the bell at the counter starts a round")
	var shot_at := func(kind: String) -> Dictionary:
		for t: Dictionary in f.targets:
			if String(t["kind"]) == kind and g.clock >= float(t["down_until"]):
				var x := float(t["x"])
				if x > 96.6 and x < 100.4:
					return t
		return {}
	var scored := {}
	for kind: String in ["duck", "can", "bottle"]:
		var t: Dictionary = {}
		for i in 240:
			t = shot_at.call(kind)
			if not t.is_empty():
				break
			_ticks(g, 1)
		var rail: Array = f.RAILS[t["rail"]]
		var spec: Array = f.KINDS[kind]
		var before: int = f.score
		_aim(g, float(t["x"]), float(rail[0]), floor_z + float(rail[1]) + float(spec[3]))
		scored[kind] = f.score - before
	_check(
		scored == {"duck": 2, "can": 1, "bottle": 3},
		"a duck scores 2, a can 1, a bottle 3 (%s)" % [scored]
	)
	_check(f.cans.size() == 1, "the can shot leaves its rail")
	var can: Dictionary = f.cans[0]
	var peak := 0.0
	for i in 12:
		_ticks(g, 1)
		peak = maxf(peak, float(can["z"]))
	var before_air: int = f.score
	_aim(g, float(can["x"]), float(can["y"]), floor_z + float(can["z"]))
	_check(
		peak > 1.3 and f.score - before_air == f.POINTS["air_can"],
		"the can flies up off its rail and hit again in the air scores again (%.2f up)" % peak
	)
	var inside := true
	var low := 9.0
	for i in 150:
		_ticks(g, 1)
		if f.cans.is_empty():
			break
		var cx := float(can["x"])
		var cy := float(can["y"])
		inside = inside and f.BOOTH.grow(.01).has_point(Vector2(cx, cy))
		low = minf(low, float(can["z"]))
	_check(
		inside and low < .06,
		"it bounces off the booth and comes down to rest on its floor (%.3f)" % low
	)
	for i in 600:
		if f.hog_x > 96.8:
			break
		_ticks(g, 1)
	var before_hog: int = f.score
	_aim(g, f.hog_x + .08, f.HOG_Y, floor_z + f.HOG_Z + .2)
	_check(f.score - before_hog == 5, "the running hog scores 5")
	var a := g.armory
	var gun := Weapons.REVOLVER
	a.reserve[gun] = 10
	f._fired(gun)
	_check(a.reserve[gun] == 11, "the house pays for the round's shots")
	_stand(g, 98.5, 53.0, -PI / 2.0)
	_ticks(g, 2)
	_check(not f.round_on, "leaving the counter ends the round")
	# The prizes: a beer to the pockets, the hat and the bear kept.
	_stand(g, 98.5, 49.6, -PI / 2.0)
	f.start(g.player)
	f.score = 50
	g.inventory["beer"] = 0
	_ticks(g, int(f.ROUND * 60.0) + 5)
	var beer: int = g.inventory["beer"]
	_check(
		not f.round_on and beer == 1 and f.won_hat and f.won_bear,
		"a round of 50 pays a beer into the pockets, the hat and the bear (%s)" % f.last
	)
	var kept: Dictionary = f.save()
	var g2: Game = main.make_game("fair")
	g2.configure({})
	g2.features["fair_gallery"].restore(kept)
	_check(
		g2.features["fair_gallery"].won_bear and int(g2.features["fair_gallery"].best) == 50,
		"the prizes and the best are kept in the save"
	)
	_check(RangeBoard.best("fair_gallery") == 50, "the round goes to the range's records")
	var kinds := {}
	_stand(g, 94.0, 51.5, -PI * .6)
	for s: View.Sprite in f.sprites():
		kinds[s.solid if s.solid != "" else s.image] = true
	_check(
		(
			kinds.has("rail")
			and kinds.has("bell")
			and kinds.has("town_range_duck")
			and kinds.has("town_prize_bear")
			and kinds.has("hat")
			and kinds.has("beer")
		),
		"the booths show their rails, bell, ducks and prizes in 3D (%s)" % [kinds.keys()]
	)
	var c := Canvas.new()
	_stand(g, 98.5, 49.6, -PI / 2.0)
	f.draw_view(c)
	RangeBoard.folder_override = ""


func _ducks() -> void:
	print("THE RANGE'S DUCK ROW")
	var g: Game = main.make_game("range")
	g.configure({})
	var t = g.features["range"].targets
	var x1: float = RangeLayout.GALLERY_X[1]
	var duck: Dictionary = {}
	for m: Dictionary in t.movers:
		if int(m["row"]) == 1:
			duck = m
			break
	_check(not duck.is_empty(), "the range has a duck row")
	if duck.is_empty():
		return
	# Riding right; just turned at the end; edge on; most of the way round.
	var turns: Array = []
	for at: Array in [
		[x1 - 2.0, 1.0], [x1 - .01, -1.0], [x1 - .225, -1.0], [x1 - .4, -1.0], [x1 - 2.0, -1.0]
	]:
		duck["x"] = at[0]
		duck["dir"] = at[1]
		duck["down_until"] = 0.0
		_stand(g, float(at[0]), 49.0, -PI / 2.0)
		for s: View.Sprite in t.sprites(g):
			if s.image == "town_range_duck" and absf(s.x - float(at[0])) < .001:
				turns.append(s.plane + (PI if s.flip else 0.0))
	_check(turns.size() == 5, "each duck is drawn (%d)" % turns.size())
	if turns.size() == 5:
		var a: float = turns[0]
		var b: float = turns[1]
		var c: float = turns[2]
		var d: float = turns[3]
		var e: float = turns[4]
		_check(
			(
				absf(a) < .01
				and b < .2
				and absf(c - PI * .5) < .2
				and d > c
				and d < PI
				and absf(e - PI) < .01
			),
			"a duck turned at the rail's end spins round on its stick (%s)" % [turns]
		)


# ------------------------------------------------------------------ the shack


func _trophies() -> void:
	print("THE TROPHY SHACK")
	var shack = load("res://src/features/trophy_shack.gd")
	RangeBoard.folder_override = OS.get_cache_dir().path_join("clmr-games-check-shack")
	CountyRecords.folder_override = RangeBoard.folder_override
	DirAccess.make_dir_recursive_absolute(RangeBoard.folder_override)
	var records := FileAccess.open(RangeBoard.path(), FileAccess.WRITE)
	records.store_string(JSON.stringify({"bowling": 187, "skeeball": 260}))
	records.close()
	var county := FileAccess.open(CountyRecords.path(), FileAccess.WRITE)
	county.store_string(
		JSON.stringify({"county_bayou": {"time": 312.0, "level": 9, "kills": 140, "runs": 3}})
	)
	county.close()
	# No boss beaten on the rematch profile: the open gates say which are.
	var profile := BossRematch.profile_path()
	var had := FileAccess.get_file_as_string(profile) if FileAccess.file_exists(profile) else ""
	if FileAccess.file_exists(profile):
		DirAccess.remove_absolute(profile)
	var g: Game = main.make_game("hub")
	g.configure({})
	g.in_hub = true
	g.world.locked_gates = []
	for gate: LevelData.Gate in g.world.hub_gates:
		if not gate.destination in ["hickston", "fair", "sawmill"]:
			g.world.locked_gates.append(gate)
	var f = g.features["trophy_shack"]
	_check(f.on, "the Crossroads has the trophy shack")
	f.refresh()
	var expect := {}
	for kind: String in BossRematch.BOSSES:
		if String(BossRematch.LEVEL_OF[kind]) in ["hickston", "fair"]:
			expect[kind] = true
	_check(
		f.beaten == expect and not expect.is_empty(),
		"the bosses of the chapters whose next gate is open are beaten (%s)" % [f.beaten.keys()]
	)
	_stand(g, 63.6, 50.0, 0.0)
	var statues := 0
	var plinths := 0
	var cups := 0
	var gnomes := 0
	for s: View.Sprite in f.sprites():
		if s.who != null:
			statues += 1
		elif s.solid == "plinth":
			plinths += 1
		elif s.image == "town_trophy":
			cups += 1
		elif s.image == "town_trophy_gnome":
			gnomes += 1
	_check(
		(
			statues == expect.size()
			and plinths == BossRematch.BOSSES.size()
			and cups == 2
			and gnomes == 1
		),
		(
			(
				"a statuette on each beaten boss's plinth, bare plinths for the rest,"
				+ " a cup a game, a gnome a map (%d %d %d %d)"
			)
			% [statues, plinths, cups, gnomes]
		)
	)
	var text := " / ".join(PackedStringArray(f.lines()))
	_check(
		(
			text.contains("BOSSES BEATEN %d OF %d" % [expect.size(), BossRematch.BOSSES.size()])
			and text.contains("BOWL-O-RAMA 187")
			and text.contains("SKEE-BALL 260")
			and text.contains("BAYOU 5:12")
		),
		"its card lists the bosses, the range's bests and the County Run record (%s)" % text
	)
	var c := Canvas.new()
	g.local_player.x = 66.5
	g.local_player.y = 50.0
	f.draw_view(c)
	_check(f.inside(g.local_player), "the card shows inside the shack")
	_check(
		not g.world.blocked(66.5, 50.0, .2) and not g.world.blocked(62.5, 50.5, .2),
		"the shack's door and floor are open"
	)
	_check(shack != null, "the shack's script loads")
	if had != "":
		var back := FileAccess.open(profile, FileAccess.WRITE)
		back.store_string(had)
		back.close()
	RangeBoard.folder_override = ""
	CountyRecords.folder_override = ""
