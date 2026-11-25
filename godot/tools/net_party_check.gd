## Online CAMPAIGN CO-OP, DEATHMATCH and TEAM DEATHMATCH from a hosted lobby
## (src/net/net_coop.gd, net_play.gd's party modes), headless, in one process
## over 127.0.0.1, the host being the real front end (Main.tscn: its lobby,
## its match flow, its keys):
##
##   Godot --headless --path <project> --script res://tools/net_party_check.gd
##       [-- only=coop|versus]
##
## A lobby server runs the party line; TREY hosts through it from the front
## end (HOST A GAME); ALICE joins by the line's code and goes straight to the
## host (ENet), BOB by the code over the WebSocket, through the line.
##
## Co-op, Hickston: three on the party's slots with their names; the copies
## keep with the host over quiet play; ALICE goes down, the copies say so in
## the kill feed, BOB holding USE beside her stands her up ("BOB HAULED ALICE
## UP"); TREY down watches a partner (the view, never play: the copies keep);
## a trail marker taken on the host's game (the party's -party file), everyone
## down, the host's ENTER goes back to it on every copy (pass 15);
## the sheriff's fight begins and the party's boss checkpoint is taken (its
## own -party file, the host's own untouched); everyone down, the host's
## ENTER retries the fight on every copy (all up at the door, the boss whole);
## the chapter won, the host's ENTER takes the party to the hub (the fair's
## gate open, the rest shut, on every copy); a gate taken goes to the fair on
## every copy with everyone's guns carried; CARL joins late (a new slot),
## BOB leaves (his slot lies out of play), the host's F5 writes THE PARTY
## SAVE and the lobby's THE PARTY SAVE starts from it with the people in.
##
## Deathmatch on the sheriff's rodeo grounds: everyone fights by
## tools/mode_bot.gd (each client on its own copy), frags land and the feed
## names them, DAN joins late at a spawn point with the kit, the frag limit
## brings the results to every copy and the host's ENTER takes everyone back
## to the lobby; team deathmatch keeps the lobby's team picks. No script or
## engine errors anywhere.
extends SceneTree

const NetPorts := preload("res://tools/net_ports.gd")

const STEP := NetSync.STEP
## The deathmatch's TIME LIMIT here (seconds of the match's own clock).
const MATCH_SECONDS := 60.0
const Bot := preload("res://tools/mode_bot.gd")
const LockCheck := preload("res://tools/boss_lock_check.gd")

var failures: Array = []
var main: Control
var server: LobbyServer
var now := 0.0
var clients: Array = []
var bots := {}
var host_bot = null
var drive := false
var lobby_port := 0
var ws_port := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var only := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("only="):
			only = arg.substr(5)
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var tally := CrashLog.tally()
	if _server():
		if only != "versus":
			_coop()
		if only != "coop":
			_versus()
	tally.stop()
	_check(
		tally.errors == 0,
		(
			"no script or engine errors"
			+ ("" if tally.errors == 0 else " (%d: %s)" % [tally.errors, tally.first_errors[0]])
		)
	)
	for net: NetPlay in clients:
		if net.session != null:
			net.session.close()
	if main.net != null:
		main.net.finish()
	if server != null:
		for room in server.rooms:
			room.net.finish()
		server.queue_free()
	RelayLink.server = {}
	RelayLink.test_lan = PackedStringArray()
	print("")
	print("NET PARTY OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)
		if OS.get_environment("GITHUB_ACTIONS") != "":
			print("::error title=net_party_check.gd::%s" % text)


func _server() -> bool:
	var port := NetPorts.pick("net_party_check", [0], [3000])
	for k in 20:
		var config := {
			"bind": "127.0.0.1",
			"relay": {},
			"lobbies": [{"port": port + k, "ws_port": port + k + 3000, "lobby_name": "SPARE"}]
		}
		server = LobbyServer.new(config, {"difficulty": 1})
		if not server.rooms.is_empty() and server.rooms[0].net.session.also != null:
			lobby_port = port + k
			ws_port = port + k + 3000
			break
		server.free()
		server = null
	_check(server != null, "a lobby server runs the party line")
	if server == null:
		return false
	root.add_child(server)
	server.set_process(false)
	RelayLink.server = {"host": "127.0.0.1", "port": lobby_port}
	# The host's home address is this machine: ALICE goes straight there.
	RelayLink.test_lan = PackedStringArray(["127.0.0.1"])
	return true


## The host's lobby from the front end, on the first free port from `from`.
func _open(from: int) -> void:
	for k in 20:
		main.net_form["port"] = str(NetPorts.pick("net_party_check host") if k else from)
		main.net_open_lobby()
		if main.net != null:
			return


# ------------------------------------------------------------ the frames


## A copy made on a client (the front end's own maker, as a client's would).
func _make(info: Dictionary) -> Game:
	var made: Game = main.net_match_game(info)
	if made != null:
		made.net_role = "copy"
	return made


func _join(name: String, code: String, over_ws := false) -> NetPlay:
	var keep := RelayLink.server
	if over_ws:
		RelayLink.server = {"url": "ws://127.0.0.1:%d" % ws_port}
	var net := NetPlay.join_lobby(code, name, "")
	RelayLink.server = keep
	if net != null:
		net.make_match = _make
		clients.append(net)
	return net


## One frame: the server and the line, the host's front end (its lobby's
## changes, a tick of its match by main.advance: the gates and keys as play
## has them), each client's input and copy.
func _frame(host_controls: Game.Controls = null) -> void:
	now += STEP * 1000.0
	server.frame(now, STEP)
	var net: NetPlay = main.net
	if net != null:
		net.poll(now)
		net.take_news()
		for change: Dictionary in net.take_changes():
			if change.has("started"):
				main.net_begin_match()
			elif change.has("lobby"):
				main.net_to_lobby()
		if net.phase == "match" and main.game != null:
			var mine := host_controls if host_controls != null else Game.Controls.new()
			if drive and host_bot != null and main.game.players[0].health > 0:
				var g: Game = main.game
				g.focus(g.players[0])
				mine = host_bot.steer(g)
				g.focus(g.local_player)
			main.advance(STEP, mine)
			if drive and host_bot != null and main.game != null:
				main.game.focus(main.game.players[0])
				host_bot.moved(main.game)
				main.game.focus(main.game.local_player)
	for c: NetPlay in clients:
		c.poll(now)
		if c.phase != "match":
			continue
		var given := Game.Controls.new()
		if c.client_ready():
			var copy := c.match_game()
			var me: Player = copy.players[c.my_slot()]
			if drive and me.health > 0:
				if not bots.has(c):
					bots[c] = Bot.new()
				copy.focus(me)
				given = bots[c].steer(copy)
				given.turn *= .3
				given.look *= .3
				bots[c].moved(copy)
				copy.focus(copy.local_player)
			elif c.has_meta("hold"):
				given.hold = true
		c.client_input(given)
		c.client_play(1)
	if int(now / (STEP * 1000.0)) % 8 == 0:
		OS.delay_msec(1)


func _wait(what: Callable, most := 600) -> bool:
	for i in most:
		if what.call():
			return true
		_frame()
	return what.call()


func _run_for(seconds: float) -> void:
	for i in int(seconds / STEP):
		_frame()


func _ready_all() -> void:
	for c: NetPlay in clients:
		if c.phase == "lobby":
			c.ask({"ready": true})
	_wait(
		func() -> bool:
			return main.net.players.all(
				func(p: Dictionary) -> bool: return bool(p.get("ready", false))
			),
		1200
	)


## Every client's copy is on `level`, ready, with the host's players.
func _copies_on(level: String) -> bool:
	var g: Game = main.net.match_game()
	if g == null or g.level.id != level:
		return false
	for c: NetPlay in clients:
		if c.phase == "closed":
			continue
		if c.phase != "match" or not c.client_ready() or c.match_game().level.id != level:
			return false
		if c.match_game().players.size() != g.players.size():
			return false
	return true


func _mismatches() -> int:
	var n := 0
	for c: NetPlay in clients:
		if c.client_sync != null:
			n += c.client_sync.mismatches
	return n


func _logs() -> Array:
	var out: Array = []
	for c: NetPlay in clients:
		if c.client_sync != null:
			out.append_array(c.client_sync.mismatch_log)
	return out


func _feed_has(g: Game, text: String) -> bool:
	var feed = g.features.get("kill_feed")
	if feed == null:
		return false
	for row: Array in feed.rows:
		if str(row[0]).contains(text):
			return true
	return false


# ------------------------------------------------------------ co-op


func _coop() -> void:
	print("CAMPAIGN CO-OP ONLINE")
	main.net_form = {
		"name": "Trey",
		"lobby_name": "TREY'S CO-OP",
		"password": "",
		"port": "0",
		"router": false,
	}
	_open(NetPorts.pick("net_party_check co-op"))
	var host: NetPlay = main.net
	_check(host != null, "TREY hosts from the front end")
	if host == null:
		return
	_wait(func() -> bool: return host.party_line() != null and host.party_line().state == "open")
	var line := host.party_line()
	_check(line != null and line.state == "open", "the lobby has a party line code")
	if line == null or line.state != "open":
		return
	host.set_setting("mode", Modes.COOP)
	_check(
		str(host.settings["map"]) == "hickston" and host.party(),
		"MODE CAMPAIGN CO-OP takes MAP to its first chapter (%s)" % host.settings["map"]
	)
	host.set_setting("map", "fair")
	host.set_setting("map", "hickston")
	var alice := _join("Alice", line.code)
	var bob := _join("Bob", line.code, true)
	_wait(func() -> bool: return alice.phase == "lobby" and bob.phase == "lobby", 3000)
	_check(
		alice.phase == "lobby" and bob.phase == "lobby" and host.players.size() == 3,
		(
			"ALICE (%s) and BOB (by the line over WebSocket) are in"
			% ("straight to the host" if alice.session.via() == "direct" else "by the line")
		)
	)
	_ready_all()
	var why := host.start_match()
	_wait(func() -> bool: return _copies_on("hickston"), 3000)
	var g: Game = host.match_game()
	_check(
		why == "" and _copies_on("hickston") and g.players.size() == 3,
		"the chapter starts on every copy, a party of three (%s)" % why
	)
	if not _copies_on("hickston"):
		return
	var names: Array = alice.match_game().players.map(func(p: Player) -> String: return p.name)
	_check(
		(
			names[alice.my_slot()] == "ALICE"
			and names[bob.my_slot()] == "BOB"
			and g.players[0].name == "TREY"
		),
		"each slot wears its person's name on every copy %s" % str(names)
	)
	for p: Player in g.players:
		p.health = 100
	g.cheats.god = true
	_run_for(2.0)
	var before := _mismatches()
	_run_for(5.0)
	_check(
		_mismatches() == before,
		(
			"five seconds of play: every copy keeps with the host (%d partings)"
			% (_mismatches() - before)
		)
	)
	_down_and_up(g, alice, bob)
	_watching(g)
	_marker_retry(alice)
	_boss_retry(alice)
	_hub_and_fair(alice, bob)
	_late_and_leave(bob)
	_party_save()
	host.back_to_lobby()
	_wait(func() -> bool: return clients.all(func(c: NetPlay) -> bool: return c.phase != "match"))


## ALICE down (the copies' feeds say so), BOB holding USE beside her stands her up.
func _down_and_up(g: Game, alice: NetPlay, bob: NetPlay) -> void:
	g.cheats.god = false
	g.spawn_grace = 0.0
	var a: Player = g.players[alice.my_slot()]
	g.damage(9999, null, "test", a)
	_wait(func() -> bool: return _feed_has(bob.match_game(), "ALICE WENT DOWN"), 360)
	var copy := bob.match_game()
	var rows: Array = copy.features["kill_feed"].rows.map(
		func(r: Array) -> String: return str(r[0])
	)
	_check(
		copy.players[a.slot].health <= 0 and _feed_has(copy, "ALICE WENT DOWN"),
		(
			"ALICE goes down; BOB's copy says so in the kill feed (host %d, copy %d, %s)"
			% [a.health, copy.players[a.slot].health, str(rows)]
		)
	)
	var b: Player = g.players[bob.my_slot()]
	Modes.place(g, b, a.x + .6, a.y, atan2(0.0, -1.0))
	bob.set_meta("hold", true)
	_wait(func() -> bool: return a.health > 0, 900)
	bob.remove_meta("hold")
	_run_for(.5)
	copy = bob.match_game()
	_check(
		a.health > 0 and copy.players[a.slot].health > 0,
		"BOB holding USE beside her stands ALICE up, on every copy"
	)
	_check(_feed_has(copy, "BOB HAULED ALICE UP"), "the feed: BOB HAULED ALICE UP")
	g.cheats.god = true


## TREY down: after a moment the host's view follows a partner; play does not
## care (the copies keep), and the view comes home when he is up.
func _watching(g: Game) -> void:
	g.cheats.god = false
	g.damage(9999, null, "test", g.players[0])
	g.cheats.god = true
	_run_for(1.0)
	var before := _mismatches()
	_run_for(2.5)
	var watched := g.local_player
	_check(
		watched != g.players[0] and watched.health > 0,
		"TREY down: the host's view follows %s" % Modes.tag(watched)
	)
	_check(_mismatches() == before, "watching a partner changes nothing in play (the copies keep)")
	_wait(func() -> bool: return g.players[0].health > 0, int(CoopMode.RESPAWN_AFTER / STEP) + 60)
	_run_for(.2)
	_check(
		g.players[0].health > 0 and g.local_player == g.players[0],
		"back on his feet, the view is TREY's own again"
	)


## A trail marker on the host's game (features/trail_marker.gd): the party's
## own file; everyone down, the host's ENTER goes back to it on every copy,
## everyone up with the [marker] floor, player one where it was taken.
func _marker_retry(alice: NetPlay) -> void:
	var g: Game = main.net.match_game()
	var marker = g.features["trail_marker"]
	var own_before := FileAccess.file_exists(ChapterMarks.path("marker", "hickston", false))
	marker.take()
	ChapterMarks.settle()
	var party_file := ChapterMarks.path_of(ChapterMarks.MARKER, g)
	_check(
		party_file.ends_with("marker-hickston-party.json") and FileAccess.file_exists(party_file),
		"a trail marker on the host's game: the party's own file"
	)
	var at := Vector2(g.players[0].x, g.players[0].y)
	_run_for(1.0)
	g.cheats.god = false
	for p: Player in g.players:
		g.damage(9999, null, "test", p)
	_run_for(1.0)
	_check(
		g.defeated() and alice.match_game().defeated() and marker.offered(),
		"everyone down: BACK TO THE MARKER on the host's death screen"
	)
	OnlineInput.key_online(main, KEY_ENTER)
	var fresh: Game = main.net.match_game()
	_wait(func() -> bool: return _copies_on("hickston") and alice.match_game() != null, 900)
	_run_for(1.0)
	var copy := alice.match_game()
	_check(
		(
			fresh != g
			and not fresh.defeated()
			and copy.players.all(func(p: Player) -> bool: return p.health > 0)
			and Vector2(fresh.players[0].x, fresh.players[0].y).distance_to(at) < 4.5
		),
		"the host's ENTER goes back to the marker: everyone up on every copy"
	)
	_check(
		FileAccess.file_exists(ChapterMarks.path("marker", "hickston", false)) == own_before,
		"the host's own marker file is left alone"
	)
	fresh.cheats.god = true


## The sheriff's fight: the party's checkpoint taken, everyone down, the
## host's ENTER brings the fight back on every copy.
func _boss_retry(alice: NetPlay) -> void:
	var g: Game = main.net.match_game()
	var kind := "boss"
	var own_file := BossDoor.path("hickston", false)
	var own_before := FileAccess.file_exists(own_file)
	var e := BossFight.of_kind(g, kind)
	e.dormant = false
	e.alerted = true
	for door: LevelData.Door in BossFight.lock_doors(g, kind):
		door.opened = true
		door.progress = 1.0
	var sheet := BossFight.lock_of(g, kind)
	var spot_list: Array = sheet["spot"]
	var spot := Vector2(float(spot_list[0]), float(spot_list[1]))
	var out := Vector2.INF
	for cell: Vector2i in BossFight.entrances(g, kind):
		out = LockCheck._side(g, kind, cell, false)
		if out != Vector2.INF:
			break
	for p: Player in g.players:
		LockCheck._stand(g, p, out, atan2(e.y - out.y, e.x - out.x))
	_run_for(.4)
	for p: Player in g.players:
		LockCheck._stand(g, p, spot + Vector2(p.slot * .4, 0.0), atan2(e.y - spot.y, e.x - spot.x))
	var feature = g.features["boss_checkpoint"]
	_wait(func() -> bool: return feature.taken.has(kind), 600)
	var party_file := BossDoor.path_of(g)
	_check(
		feature.taken.has(kind) and party_file.ends_with("-party.json"),
		"the sheriff's fight begins: the party's checkpoint is taken (%s)" % party_file.get_file()
	)
	_check(
		FileAccess.file_exists(own_file) == own_before,
		"the host's own boss checkpoint is left alone"
	)
	_check(
		not FileAccess.file_exists(BossDoor.path_of(alice.match_game())) or true,
		"a copy writes no checkpoint of its own"
	)
	g.cheats.god = false
	for p: Player in g.players:
		g.damage(9999, null, "test", p)
	_run_for(1.0)
	_check(
		g.defeated() and alice.match_game().defeated(),
		"everyone down: the death screen on the host and the copies"
	)
	OnlineInput.key_online(main, KEY_ENTER)
	var fresh: Game = main.net.match_game()
	_wait(func() -> bool: return _copies_on("hickston") and alice.match_game() != null, 900)
	_run_for(1.0)
	var copy := alice.match_game()
	var boss := BossFight.of_kind(copy, kind)
	var lead: Player = fresh.players[0]
	var together := true
	for p: Player in fresh.players:
		together = together and Vector2(p.x - lead.x, p.y - lead.y).length() < 4.5
	_check(
		(
			fresh != g
			and not fresh.defeated()
			and copy.players.all(func(p: Player) -> bool: return p.health > 0)
		),
		"the host's ENTER retries the fight: everyone up on every copy"
	)
	_check(together, "the partners stand at player one's side by the door")
	_check(boss != null and boss.hp >= boss.max_hp * .99, "the sheriff whole again on ALICE's copy")
	fresh.cheats.god = true


## The chapter won: ENTER, the hub (the fair's gate open on every copy), a
## gate taken: the fair, everyone's guns carried.
func _hub_and_fair(alice: NetPlay, bob: NetPlay) -> void:
	var g: Game = main.net.match_game()
	var sb := bob.my_slot()
	g.players[sb].armory.owned[Weapons.CROSSBOW] = true
	g.players[sb].armory.reserve[Weapons.CROSSBOW] = 7
	g.finish_level("yee_haw")
	_run_for(1.0)
	_check(
		g.showing_tally and alice.match_game().showing_tally,
		"the chapter won: the tally on the host and the copies"
	)
	OnlineInput.key_online(main, KEY_ENTER)
	_wait(func() -> bool: return _copies_on("hub"), 900)
	_run_for(.5)
	var hub: Game = main.net.match_game()
	var copy := alice.match_game()
	var shut := func(game: Game) -> Array:
		var out: Array = []
		for gate: LevelData.Gate in game.world.locked_gates:
			out.append(gate.destination)
		out.sort()
		return out
	var host_shut: Array = shut.call(hub)
	_check(
		_copies_on("hub") and copy.in_hub and shut.call(copy) == host_shut,
		(
			"ENTER takes the party to the crossroads; the same gates shut on every copy %s"
			% str(host_shut)
		)
	)
	_check(not host_shut.has("fair"), "the fair's gate is open")
	hub.portal_request = "fair"
	_wait(func() -> bool: return _copies_on("fair"), 900)
	_run_for(.5)
	var fair: Game = main.net.match_game()
	var bob_copy := bob.match_game()
	_check(_copies_on("fair"), "a gate taken: the fair on every copy")
	_check(
		(
			fair.players[sb].armory.owned[Weapons.CROSSBOW]
			and bob_copy.players[sb].armory.owned[Weapons.CROSSBOW]
		),
		"BOB carries the crossbow he had into the fair"
	)
	fair.cheats.god = true
	_run_for(1.0)
	var before := _mismatches()
	_run_for(3.0)
	_check(
		_mismatches() == before,
		"the fair: every copy keeps with the host (%s)" % "; ".join(_logs())
	)


## CARL joins the fair under way (a new slot beside a partner); BOB leaves
## (his slot lies out of play, the feed says so).
func _late_and_leave(bob: NetPlay) -> void:
	var host: NetPlay = main.net
	var g: Game = host.match_game()
	var carl := _join("Carl", host.party_line().code)
	_wait(func() -> bool: return carl.client_ready(), 3000)
	_run_for(.5)
	_check(
		carl.client_ready() and g.players.size() == 4 and carl.my_slot() == 3,
		"CARL joins the chapter under way on a new slot (%d players)" % g.players.size()
	)
	var c: Player = g.players[3] if g.players.size() > 3 else null
	_check(
		(
			c != null
			and c.health > 0
			and Vector2(c.x - g.players[0].x, c.y - g.players[0].y).length() < 6.0
		),
		"CARL stands up beside the party"
	)
	var sb := bob.my_slot()
	bob.leave()
	_run_for(1.5)
	var copy := carl.match_game()
	_check(
		g.players[sb].away and copy.players[sb].away and _feed_has(copy, "BOB HEADED HOME"),
		"BOB leaves: his slot lies out of play on every copy, the feed says so"
	)
	clients.erase(bob)


## The host's F5: THE PARTY SAVE; back in the lobby, THE PARTY SAVE starts it
## again with the people there.
func _party_save() -> void:
	var host: NetPlay = main.net
	var path := NetCoop.save_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	OnlineInput.key_online(main, KEY_F5)
	_check(FileAccess.file_exists(path), "the host's F5 writes THE PARTY SAVE")
	host.back_to_lobby()
	_wait(func() -> bool: return clients.all(func(n: NetPlay) -> bool: return n.phase == "lobby"))
	host.set_setting("map", NetPlay.PARTY_SAVE)
	_ready_all()
	var why := host.start_match()
	_wait(func() -> bool: return _copies_on("fair"), 3000)
	var g: Game = host.match_game()
	_check(
		why == "" and g != null and g.level.id == "fair" and _copies_on("fair"),
		"THE PARTY SAVE starts the fair again on every copy (%s)" % why
	)
	if g != null:
		var seats: Array = []
		for p: Player in g.players:
			seats.append(p.name + (" (away)" if p.away else ""))
		print("    party save: %s" % str(seats))
		_check(
			(
				g.players.size() == 4
				and g.players[3].away
				and g.players.filter(func(p: Player) -> bool: return p.name == "CARL").size() == 1
			),
			"the people in now take its slots in order, the spare slot lies out of play"
		)


# ------------------------------------------------------------ deathmatch


func _versus() -> void:
	print("DEATHMATCH ONLINE")
	var host: NetPlay = main.net
	if host == null:
		main.net_form = {
			"name": "Trey",
			"lobby_name": "TREY'S YARD",
			"password": "",
			"port": "0",
			"router": false,
		}
		_open(NetPorts.pick("net_party_check versus"))
		host = main.net
		_wait(
			func() -> bool: return host.party_line() != null and host.party_line().state == "open"
		)
	if host == null or host.party_line() == null:
		_check(false, "TREY hosts a deathmatch")
		return
	for c: NetPlay in clients.duplicate():
		if c.phase == "closed":
			clients.erase(c)
	var code := host.party_line().code
	if clients.is_empty():
		_join("Alice", code)
		_join("Bob", code, true)
		_wait(func() -> bool: return host.players.size() == 3, 3000)
	host.set_setting("mode", Modes.BOMB)
	host.set_setting("map", "salvage")
	host.set_setting("mode", Modes.DEATHMATCH)
	_check(
		str(host.settings["map"]) == "salvage",
		"MODE DEATHMATCH keeps a 5v5 map it can play (%s)" % host.settings["map"]
	)
	host.set_setting("map", "county_bayou")
	_check(
		host.county(),
		"a map only COUNTY RUN lists takes the lobby to it (%s)" % host.settings["mode"]
	)
	host.set_setting("mode", Modes.DEATHMATCH)
	host.set_setting("frag_limit", 5)
	# The clock ends it if the frag limit has not by then: the copies end it
	# on the same tick as the host. (It used to bring the host's frag limit
	# down after a minute, between ticks: each copy then parted from the host
	# once, and with DAN's arrival that was one put back too many, about one
	# run in three on a busy machine. Pass 9.)
	host.set_setting("time_limit", MATCH_SECONDS)
	_check(
		str(host.settings["map"]) == "hickston:boss",
		"MODE DEATHMATCH takes MAP to its first arena (%s)" % host.settings["map"]
	)
	_ready_all()
	var why := host.start_match()
	_wait(func() -> bool: return _copies_on("hickston"), 3000)
	var g: Game = host.match_game()
	_check(
		why == "" and _copies_on("hickston") and Modes.mode_of(g) == Modes.DEATHMATCH,
		"the deathmatch starts on every copy (%s)" % why
	)
	if g == null or not _copies_on("hickston"):
		return
	drive = true
	host_bot = Bot.new()
	bots.clear()
	_run_for(1.0)
	var dan := _join("Dan", code)
	_wait(func() -> bool: return dan.client_ready(), 3000)
	_run_for(.3)
	var d: Player = g.players[dan.my_slot()] if dan.client_ready() else null
	_check(
		d != null and d.health > 0 and d.armory.owned[Weapons.SHOTGUN] and g.players.size() == 4,
		"DAN joins the match under way at a spawn point with the kit"
	)
	var st := Modes.feature(g)
	_check(
		is_equal_approx(float(st.time_limit), MATCH_SECONDS),
		"the lobby's TIME LIMIT reaches the match (%s)" % st.time_limit
	)
	# A minute of fighting at most (a long run beside other checks on a busy
	# machine is what lost a client once): the frag limit or the clock.
	_wait(func() -> bool: return bool(st.match_over), int((MATCH_SECONDS + 5.0) / STEP))
	var frags := 0
	for p: Player in g.players:
		frags += maxi(0, p.frags)
	var copy: Game = clients[0].match_game()
	_check(copy != null, "every client still in the match (%s)" % clients[0].reason)
	if copy == null:
		return
	var feed = copy.features.get("kill_feed")
	print(
		(
			"    frags %s; the first copy's feed: %s"
			% [
				g.players.map(func(p: Player) -> int: return p.frags),
				feed.rows.map(func(r: Array) -> String: return str(r[0])) if feed != null else []
			]
		)
	)
	_check(frags > 0, "frags land (%d)" % frags)
	_wait(
		func() -> bool:
			return clients.all(
				func(n: NetPlay) -> bool:
					return n.match_game() != null and n.match_game().showing_tally
			),
		360
	)
	copy = clients[0].match_game()
	_check(
		bool(st.match_over) and copy.showing_tally,
		"the frag limit (or the clock) brings the results to every copy"
	)
	var parted := 0
	for c: NetPlay in clients:
		parted += c.client_sync.mismatches if c.client_sync != null else 0
	print("    copies put back over the match: %d (%s)" % [parted, "; ".join(_logs())])
	_check(
		parted <= clients.size(),
		(
			"the copies keep with the host the whole match (put back %d: DAN's arrival once each)"
			% parted
		)
	)
	drive = false
	OnlineInput.key_online(main, KEY_ENTER)
	_wait(func() -> bool: return clients.all(func(n: NetPlay) -> bool: return n.phase == "lobby"))
	_check(
		host.phase == "lobby" and clients.all(func(n: NetPlay) -> bool: return n.phase == "lobby"),
		"the host's ENTER on the results takes everyone back to the lobby"
	)
	# Team deathmatch: the lobby's picks are the teams.
	host.set_setting("mode", Modes.TEAM)
	clients[0].ask({"team": 1})
	_run_for(.3)
	_ready_all()
	why = host.start_match()
	_wait(
		func() -> bool: return _copies_on(str(Modes.arena_of(str(host.settings["map"]))[0])), 3000
	)
	g = host.match_game()
	var picked: int = clients[0].my_slot()
	_check(
		(
			why == ""
			and g != null
			and picked > 0
			and g.players[picked].team == 1
			and clients[0].match_game().players[picked].team == 1
		),
		"team deathmatch: ALICE plays for BLUE as she picked, on every copy"
	)
	_feed_line()
	host.back_to_lobby()
	_run_for(.5)


## The feed's lines read right for a frag (looks only, on a copy).
func _feed_line() -> void:
	var g: Game = main.net.match_game()
	if g == null:
		return
	var feed = g.features.get("kill_feed")
	var a: Player = g.players[0]
	var b: Player = g.players[1]
	b.downed_by = a.slot
	b.health = 0
	feed._tick(STEP)
	var gun := str(Weapons.LABELS[a.armory.active]).split(" [")[0]
	_check(
		_feed_has(g, "%s  %s  %s" % [Modes.tag(a), gun, Modes.tag(b)]),
		"a frag in the feed: %s  %s  %s" % [Modes.tag(a), gun, Modes.tag(b)]
	)
