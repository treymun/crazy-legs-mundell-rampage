## The always-open lobby (src/net/lobby_server.gd, NetPlay.serve_lobby),
## headless, in one process over 127.0.0.1 with ENet:
##
##   Godot --headless --path <project> --script res://tools/net_server_check.gd
##       [-- seconds=<play>]
##
## A server opens a lobby with a password and no host player. ALICE joins
## first and runs it; BOB joins and cannot change anything; ALICE cannot
## change the password; ALICE's settings reach everyone; START waits on BOB
## (everyone hears why); the match plays with bots (BOB's copy checked against
## the server's game); the results come up and everyone is back in the lobby
## on their own. ALICE leaves and BOB runs it; BOB kicks CARL; BOB starts
## alone and leaves, and the empty lobby ends the match and has its own
## settings again. Closing the server tells everyone. Fails on any script or
## engine error.
extends SceneTree

const STEP := NetSync.STEP

var failures: Array = []
var server: LobbyServer
var main: Control
var now := 0.0
var nets: Array = []
var bots := {}
var seconds := 25.0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("seconds="):
			seconds = float(arg.substr(8))
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var tally := CrashLog.tally()
	_play()
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
	if server != null:
		for room in server.rooms:
			room.net.finish()
		server.queue_free()
	main.queue_free()
	print("")
	print("NET SERVER OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


## A client's copy of a match, as the front end makes it.
func _make(info: Dictionary) -> Game:
	return main.net_match_game(info)


## One frame for the server and every client (each client's bot steering
## its own player once its copy has the match).
func _frame() -> void:
	now += STEP * 1000.0
	server.frame(now, STEP)
	for net: NetPlay in nets:
		net.poll(now)
		if net.phase != "match" or net.role != NetPlay.Role.CLIENT:
			continue
		var c := Game.Controls.new()
		if net.client_ready():
			if not bots.has(net):
				bots[net] = TacticalBot.new(net.my_slot())
			var copy := net.match_game()
			var me: Player = copy.players[net.my_slot()]
			if me.health > 0:
				copy.focus(me)
				c = bots[net].steer(copy)
				copy.focus(copy.local_player)
		net.client_input(c)
		net.client_play(1)
	OS.delay_msec(1)


func _wait(what: Callable, most := 400) -> bool:
	for i in most:
		if what.call():
			return true
		_frame()
	return what.call()


func _join(name: String, password := "hogs") -> NetPlay:
	var net := NetPlay.join_lobby("127.0.0.1:%d" % server.rooms[0].net.port, name, password)
	net.make_match = _make
	nets.append(net)
	return net


func _play() -> void:
	var port := 43000 + OS.get_process_id() % 15000
	for k in 20:
		var config := {
			"bind": "127.0.0.1",
			"lobbies":
			[
				{
					"port": port + k,
					"lobby_name": "TEST LOBBY",
					"password": "hogs",
					"map": "pineacres",
					"team_size": 2,
					"rounds": 9,
					"round_seconds": 90.0,
					"buy_seconds": 15.0,
				}
			]
		}
		server = LobbyServer.new(config, {"difficulty": 1})
		if not server.rooms.is_empty():
			break
		server.free()
		server = null
	_check(server != null, "the server opens a lobby")
	if server == null:
		return
	root.add_child(server)
	server.set_process(false)
	var lobby: NetPlay = server.rooms[0].net
	var alice := _join("alice")
	_wait(func() -> bool: return alice.phase == "lobby" and alice.is_admin())
	_check(
		alice.phase == "lobby" and alice.is_admin() and lobby.players.size() == 1,
		"ALICE joins first and runs the lobby (no host player in it)"
	)
	var wrong := _join("eve", "pigs")
	_wait(func() -> bool: return wrong.phase == "closed")
	_check(wrong.reason == "WRONG PASSWORD", "a wrong password is turned away (%s)" % wrong.reason)
	nets.erase(wrong)
	var bob := _join("bob")
	_wait(func() -> bool: return bob.phase == "lobby" and lobby.players.size() == 2)
	_check(bob.phase == "lobby" and not bob.is_admin(), "BOB joins and does not run it")
	bob.set_setting("rounds", 10)
	bob.ask({"set": {"rounds": 10}})
	alice.ask({"set": {"password": "", "lobby_name": "MINE", "rounds": 2}})
	alice.set_setting("rounds", 3)
	alice.set_setting("freeze_seconds", 3.0)
	alice.set_setting("round_seconds", 60.0)
	alice.set_setting("start_money", 4000)
	_wait(func() -> bool: return int(bob.settings.get("start_money", 0)) == 4000)
	_check(
		int(lobby.settings["rounds"]) == 3 and int(bob.settings["start_money"]) == 4000,
		"ALICE's settings reach the server and BOB (rounds %s)" % lobby.settings["rounds"]
	)
	_check(
		(
			String(lobby.settings["password"]) == "hogs"
			and lobby.settings["lobby_name"] == "TEST LOBBY"
		),
		"the admin cannot change the password or the lobby's name"
	)
	_check(alice.start_match().begins_with("WAITING ON BOB"), "START waits on BOB (ALICE sees why)")
	alice.ask({"start": true})
	_wait(func() -> bool: return Array(bob.take_news()).has("WAITING ON BOB"), 60)
	_check(lobby.phase == "lobby", "a START the server refuses leaves everyone in the lobby")
	bob.ask({"ready": true})
	_wait(func() -> bool: return bool(alice.player_of(bob.my_id).get("ready", false)))
	var why := alice.start_match()
	_check(why == "", "ALICE starts the match %s" % why)
	_wait(func() -> bool: return alice.client_ready() and bob.client_ready())
	_check(lobby.phase == "match" and bob.client_ready(), "the match is on, both copies have it")
	var g := lobby.match_game()
	_check(
		g != null and g.players.size() == 4 and server.rooms[0].pilots.size() == 2,
		"2V2: the two people and two bots the server plays"
	)
	for i in int(seconds / STEP):
		_frame()
	var st = Modes.feature(g)
	var bc := bob.client_sync
	print(
		(
			"    %.0f s: round %d, wins %s; BOB %d checks, %d mismatches%s"
			% [
				seconds,
				st.round_no,
				st.wins,
				bc.checks,
				bc.mismatches,
				"" if bc.first_mismatch == "" else "; first: " + bc.first_mismatch
			]
		)
	)
	_check(bc.checks > 3 and bc.mismatches <= 1, "BOB's copy keeps with the server's game")
	g.won = true
	_wait(func() -> bool: return bob.back_in() > 0, 60)
	_check(bob.back_in() > 0, "the results show BOB the count back (%d)" % bob.back_in())
	_wait(
		func() -> bool: return alice.phase == "lobby" and bob.phase == "lobby",
		int(NetPlay.BACK_AFTER / STEP) + 200
	)
	_check(
		lobby.phase == "lobby" and bob.phase == "lobby",
		"everyone is back in the lobby on their own"
	)
	alice.leave()
	_wait(func() -> bool: return bob.is_admin())
	_check(bob.is_admin(), "ALICE left: BOB runs the lobby")
	var carl := _join("carl")
	_wait(func() -> bool: return carl.phase == "lobby")
	bob.kick(carl.my_id)
	_wait(func() -> bool: return carl.phase == "closed")
	_check(carl.reason == "THE ADMIN KICKED YOU", "BOB kicks CARL (%s)" % carl.reason)
	nets.erase(carl)
	bob.set_setting("team_size", 1)
	_wait(func() -> bool: return int(lobby.settings["team_size"]) == 1)
	why = bob.start_match()
	_wait(func() -> bool: return bob.client_ready())
	_check(why == "" and lobby.phase == "match", "BOB starts a 1V1 against a bot %s" % why)
	for i in 120:
		_frame()
	bob.leave()
	_wait(func() -> bool: return lobby.players.is_empty() and lobby.phase == "lobby")
	_check(
		(
			lobby.phase == "lobby"
			and lobby.admin_id == 0
			and int(lobby.settings["team_size"]) == 2
			and int(lobby.settings["rounds"]) == 9
		),
		"the empty lobby ends the match and has its own settings again"
	)
	var dave := _join("dave")
	_wait(func() -> bool: return dave.phase == "lobby" and dave.is_admin())
	_check(dave.is_admin(), "the next one in runs it")
	# As close_all() does, but with everyone polled while the goodbye goes out.
	lobby.leave("THE SERVER IS RESTARTING")
	_wait(func() -> bool: return dave.phase == "closed", 60)
	_check(
		dave.reason == "THE SERVER IS RESTARTING",
		"closing the server tells everyone (%s)" % dave.reason
	)
