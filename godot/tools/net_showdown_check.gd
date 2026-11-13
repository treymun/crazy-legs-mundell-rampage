## Online 5v5 from lobby to lobby (src/net/net_play.gd), headless, in one
## process over 127.0.0.1 with ENet:
##
##   Godot --headless --path <project> --script res://tools/net_showdown_check.gd
##       [-- seconds=<play>] [map=salvage] [mode=bomb] [lag=<ms>] [loss=<0..1>]
##
## A host opens a lobby with a password; ALICE joins, BOB is turned away for
## a wrong password and comes back with the right one; the host cannot start
## while someone is not ready; the host sets the match (3v3, first to 3,
## start cash, short freeze); ALICE picks the GATORS. Everyone plays: the
## host's own player and the bots by TacticalBot on the host, ALICE and BOB
## by TacticalBot on their own copies, their controls (buys too) over the
## wire. Checks the copies match the host, the names and teams arrive, the
## clients buy, rounds are played; then ALICE leaves (a bot takes over), CARL
## joins late (takes over a bot), the host takes everyone back to the lobby
## and closes it (everyone hears why). Fails on any script or engine error.
extends SceneTree

const STEP := NetSync.STEP

var failures: Array = []
var main: Control
var opts := {"seconds": 100.0, "map": "salvage", "mode": "bomb", "lag": 0.0, "loss": 0.0}
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
	for arg: String in OS.get_cmdline_user_args():
		var kv := arg.split("=")
		if kv.size() == 2:
			opts[kv[0]] = kv[1] if kv[0] in ["map", "mode"] else float(kv[1])
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
	print("")
	print("NET SHOWDOWN OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


## A match's game, as the front end makes it (main_flow.gd net_match_game).
func _make(info: Dictionary) -> Game:
	var g: Game = main.make_game(String(info["level"]))
	if g == null:
		return null
	g.configure({"difficulty": 1})
	Modes.setup(g, String(info["mode"]), int(info["count"]), info["options"])
	return g


## Polls everyone `frames` times (real time passing for the sockets).
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


func _play() -> void:
	var port := 41000 + OS.get_process_id() % 15000
	var host: NetPlay = null
	for k in 20:
		host = NetPlay.host_lobby(port + k, "Trey", {"password": "hogs"}, false, "127.0.0.1")
		if host != null:
			port += k
			break
	_check(host != null, "the host opens a lobby")
	if host == null:
		return
	host.make_match = _make
	nets.append(host)
	var code := NetPlay.to_code("127.0.0.1", port)
	_check(
		NetPlay.parse_address(code) == {"host": "127.0.0.1", "port": port},
		"a join code round-trips (%s)" % code
	)
	_check(
		(
			NetPlay.parse_address("[::1]:5000") == {"host": "::1", "port": 5000}
			and NetPlay.parse_address("10.0.0.2") == {"host": "10.0.0.2", "port": NetSession.PORT}
		),
		"addresses parse (IPv6 with a port, IPv4 alone)"
	)
	var alice := NetPlay.join_lobby(code, "alice", "hogs")
	alice.make_match = _make
	nets.append(alice)
	var bob := NetPlay.join_lobby("127.0.0.1:%d" % port, "Bob", "pigs")
	bob.make_match = _make
	nets.append(bob)
	_wait(func() -> bool: return alice.phase == "lobby" and bob.phase == "closed")
	_check(alice.phase == "lobby", "ALICE joins the lobby by its code")
	_check(
		bob.phase == "closed" and bob.reason == "WRONG PASSWORD",
		"BOB is turned away for a wrong password (%s)" % bob.reason
	)
	nets.erase(bob)
	bob = NetPlay.join_lobby("127.0.0.1:%d" % port, "Bob", "hogs")
	bob.make_match = _make
	nets.append(bob)
	_wait(func() -> bool: return bob.phase == "lobby" and host.players.size() == 3)
	_check(host.players.size() == 3, "BOB comes back with the right password")
	# The map first: a 2V2 map sets its own format, the sizes below override it.
	host.set_setting("mode", String(opts["mode"]))
	host.set_setting("map", String(opts["map"]))
	host.set_setting("team_size", 3)
	host.set_setting("rounds", 3)
	host.set_setting("freeze_seconds", 3.0)
	host.set_setting("start_money", 4000)
	host.set_setting("bot_skill", 2)
	host.set_setting("round_seconds", 60.0)
	host.set_setting("mode", String(opts["mode"]))
	host.set_setting("map", String(opts["map"]))
	alice.ask({"team": 1, "ready": true})
	_wait(func() -> bool: return bool(host.player_of(alice.my_id).get("ready", false)))
	_check(
		host.start_match().begins_with("WAITING ON BOB"),
		"the host cannot start while BOB is not ready"
	)
	bob.ask({"ready": true, "name": "bobby"})
	_wait(
		func() -> bool:
			return (
				bool(host.player_of(bob.my_id).get("ready", false))
				and int(bob.settings["start_money"]) == 4000
			)
	)
	_check(
		int(bob.settings["start_money"]) == 4000 and not bob.settings.has("password"),
		"the clients see the host's settings (not the password)"
	)
	var why := host.start_match()
	_check(why == "", "the host starts the match %s" % why)
	if why != "":
		return
	_wait(func() -> bool: return alice.phase == "match" and bob.phase == "match")
	_check(alice.phase == "match" and bob.phase == "match", "both clients get START")
	var g := host.match_game()
	var st = Modes.feature(g)
	var a_slot := alice.my_slot()
	var b_slot := bob.my_slot()
	_check(
		g.players.size() == 6 and g.players[a_slot].team == 1 and g.players[a_slot].name == "ALICE",
		"3v3 with bots, ALICE a GATOR (slot %d, team %d)" % [a_slot, g.players[a_slot].team]
	)
	var lag := float(opts["lag"])
	for net: NetPlay in nets:
		net.session.lag_ms = lag
		net.session.jitter_ms = lag * .2
		net.session.loss = float(opts["loss"])
	var pilots := {}
	for slot: int in host.bot_slots():
		pilots[slot] = TacticalBot.new(slot)
	pilots[0] = TacticalBot.new(0)
	var client_bots := {alice: TacticalBot.new(a_slot), bob: TacticalBot.new(b_slot)}
	var seconds := float(opts["seconds"])
	var ticks := int(seconds / STEP)
	var named := false
	var armoured := {}
	var alice_botted := false
	var left_at := int(ticks * .45)
	var carl: NetPlay = null
	var carl_from := int(ticks * .6)
	var wall := Time.get_ticks_msec()
	for t in ticks:
		now += STEP * 1000.0
		for net: NetPlay in nets:
			net.poll(now)
		for change: Dictionary in host.take_changes():
			if change.has("bot"):
				pilots[int(change["bot"])] = TacticalBot.new(int(change["bot"]))
			elif change.has("human"):
				pilots.erase(int(change["human"]))
		for net: NetPlay in nets.slice(1):
			if net.phase == "closed":
				continue
			net.take_changes()
			var bot: TacticalBot = client_bots.get(net)
			var c := Game.Controls.new()
			if net.client_ready() and bot != null:
				var copy := net.match_game()
				var me: Player = copy.players[net.my_slot()]
				if me.health > 0:
					copy.focus(me)
					c = bot.steer(copy)
					copy.focus(copy.local_player)
			net.client_input(c)
		var own := {}
		for slot: int in pilots:
			var p: Player = g.players[slot]
			if p.health > 0:
				g.focus(p)
				own[slot] = pilots[slot].steer(g)
		g.focus(g.local_player)
		host.host_tick(own)
		for net: NetPlay in nets.slice(1):
			net.client_play(1)
		for s: int in [a_slot, b_slot]:
			if float(st.armor[s]) > 0.0:
				armoured[s] = true
		if t == 180:
			var copy := bob.match_game()
			named = (
				bob.client_ready()
				and copy.players[a_slot].name == "ALICE"
				and copy.players[b_slot].name == "BOBBY"
			)
		if t == left_at + 30:
			alice_botted = host.player_of(alice.my_id).is_empty() and pilots.has(a_slot)
		if t == left_at:
			alice.leave()
		if t == carl_from:
			carl = NetPlay.join_lobby("127.0.0.1:%d" % port, "Carl", "hogs")
			carl.make_match = _make
			nets.append(carl)
			client_bots[carl] = null
		if carl != null and client_bots[carl] == null and carl.phase == "match":
			client_bots[carl] = TacticalBot.new(carl.my_slot())
		if t % 30 == 0:
			OS.delay_msec(1)
	print(
		(
			"    %.0f s of play in %.1f s; round %d, wins %s, %d snapshots sent"
			% [
				seconds,
				(Time.get_ticks_msec() - wall) / 1000.0,
				st.round_no,
				st.wins,
				host.host_sync.seq + 1
			]
		)
	)
	for net: NetPlay in [bob, carl]:
		if net == null or net.client_sync == null:
			continue
		var cs := net.client_sync
		print(
			(
				"    %s: %d checks, %d mismatches, %d rebuilds, %d behind; ping %.0f ms%s"
				% [
					net._my_name,
					cs.checks,
					cs.mismatches,
					cs.rebuilds,
					cs.backlog(),
					net.ping_ms(),
					"" if cs.first_mismatch == "" else "; first: " + cs.first_mismatch
				]
			)
		)
	var bc := bob.client_sync
	_check(bc != null and bc.checks > 3, "BOB's copy is checked against the host (%d)" % bc.checks)
	_check(
		bc != null and bc.mismatches <= 1,
		"BOB's copy keeps with the host (%d mismatches)" % (bc.mismatches if bc != null else -1)
	)
	_check(named, "the names reach the copies")
	_check(
		armoured.has(a_slot) and armoured.has(b_slot),
		"both clients bought vests over the wire (their buys in the controls)"
	)
	_check(int(st.round_no) >= 2, "rounds are played (round %d)" % st.round_no)
	_check(alice_botted, "ALICE left and a bot plays her slot")
	_check(
		carl != null and carl.phase == "match" and carl.client_ready(),
		"CARL joins late and gets the match"
	)
	if carl != null and carl.client_sync != null:
		var c_slot := carl.my_slot()
		_check(
			c_slot >= 0 and not pilots.has(c_slot) and g.players[c_slot].name == "CARL",
			"CARL took over a bot's place (slot %d)" % c_slot
		)
		_check(carl.client_sync.mismatches <= 1, "CARL's copy keeps with the host")
	host.back_to_lobby()
	_wait(func() -> bool: return bob.phase == "lobby" and (carl == null or carl.phase == "lobby"))
	_check(bob.phase == "lobby", "the host takes everyone back to the lobby")
	host.leave("THE HOST CLOSED THE LOBBY")
	_wait(func() -> bool: return bob.phase == "closed")
	_check(
		bob.phase == "closed" and bob.reason == "THE HOST CLOSED THE LOBBY",
		"closing the lobby tells everyone (%s)" % bob.reason
	)
