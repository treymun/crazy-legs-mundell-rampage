## THE PARTY LINE (src/net/net_relay.gd, relay_link.gd), headless, in one
## process over 127.0.0.1:
##
##   Godot --headless --path <project> --script res://tools/relay_check.gd
##       [-- seconds=<5v5 play> county=<run seconds> team=3 map=salvage quick]
##       [-- ping=<address>:<port>]   (only the echo, through a party line
##                                     running elsewhere: a local server or the VPS)
##
## A lobby server with the party line on its ports (as on the VPS) and an
## always-open lobby beside it. The line's limits on a port of its own: a
## full line or a house with its share of rooms turns a room away, a room
## over its bytes a second passes only what must arrive, an empty room
## closes and its host hears why. The lag the
## line adds: echoes straight and through it, the line polled flat out and
## at the server's 120 frames a second. Then two hosted games through it:
##   - 5v5: TREY hosts (his own port shut to the world: a home address that
##     does not answer); ALICE joins by the code over ENet (tries the host's
##     address, falls back to the line), BOB over the WebSocket (the
##     browser's way: straight to the line); a wrong code is turned away;
##     DAVE sits in the server's own lobby meanwhile and nothing crosses.
##     A match with bots, every copy kept with the host; the bytes each
##     player costs the line; CARL joins late by the code and goes straight
##     to the host (its address answers now); the host shows BOB the door
##     through the line and closes; everyone hears why and the room closes.
##   - COUNTY RUN: a host and two players through the line, the host's
##     player the leader picking cards, both copies kept with the host; the
##     host's game goes with no goodbye and the line tells both.
## Fails on any script or engine error.
extends SceneTree

const STEP := NetSync.STEP
const CountyBot := preload("res://tools/county_bot.gd")

var failures: Array = []
var main: Control
var server: LobbyServer
var now := 0.0
var nets: Array = []
var seconds := 40.0
var county_seconds := 30.0
var quick := false
var lobby_port := 0
var ws_port := 0
## God mode on every copy (the County Run: the bots play, nobody dies).
var god := false
var team := 3
var map_id := "salvage"
var ping_at := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("seconds="):
			seconds = float(arg.substr(8))
		elif arg.begins_with("county="):
			county_seconds = float(arg.substr(7))
		elif arg.begins_with("team="):
			team = int(arg.substr(5))
		elif arg.begins_with("map="):
			map_id = arg.substr(4)
		elif arg.begins_with("ping="):
			ping_at = arg.substr(5)
		elif arg == "quick":
			quick = true
	if quick:
		seconds = minf(seconds, 24.0)
		county_seconds = minf(county_seconds, 16.0)
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var tally := CrashLog.tally()
	if ping_at != "":
		_ping_elsewhere()
	else:
		_limits()
		if _server():
			_lag()
			_showdown()
			_county()
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
	RelayLink.server = {}
	RelayLink.test_lan = PackedStringArray()
	print("")
	print("RELAY CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)
		if OS.get_environment("GITHUB_ACTIONS") != "":
			print("::error title=%s::%s" % [get_script().resource_path.get_file(), text])


func _base_port() -> int:
	return 43000 + OS.get_process_id() % 12000


# ------------------------------------------------------------------ limits


## The line on a port of its own with small limits.
func _limits() -> void:
	print("THE LINE'S LIMITS")
	var relay := NetRelay.new(
		{"rooms": 3, "per_address": 2, "idle_minutes": 0.03, "room_bytes": 4000}
	)
	var port := _base_port() + 7000
	var listening := false
	for k in 20:
		if relay.listen(port + k, NetSession.Transport.ENET, "127.0.0.1"):
			port += k
			listening = true
			break
	_check(listening, "the party line listens on a port of its own")
	if not listening:
		return
	RelayLink.server = {"host": "127.0.0.1", "port": port}
	var pump := func(links: Array, until: Callable, most_ms := 4000.0) -> bool:
		var began := Time.get_ticks_msec()
		while Time.get_ticks_msec() - began < most_ms:
			var t := float(Time.get_ticks_msec())
			relay.poll(t)
			relay.flush()
			for link: RelayLink in links:
				link.poll(t)
			if until.call():
				return true
			OS.delay_msec(1)
		return until.call()
	var info := {"summary": {"lobby_name": "TEST"}, "listed": true, "port": 0, "open": false}
	var rooms: Array = []
	for i in 3:
		rooms.append(RelayLink.open_room(info))
	pump.call(
		rooms,
		func() -> bool: return rooms.all(func(r: RelayLink) -> bool: return r.state != "calling")
	)
	var states := rooms.map(func(r: RelayLink) -> String: return r.state)
	var open := states.count("open")
	var full: RelayLink = (
		rooms[2]
		if rooms[2].state == "refused"
		else (rooms[0] if rooms[0].state == "refused" else rooms[1])
	)
	_check(
		open == 2 and full.state == "refused" and full.why.begins_with("YOUR HOUSE HAS 2 LOBBIES"),
		"two rooms open, a third from the same house is turned away (%s: %s)" % [states, full.why]
	)
	# Room for more from one house, none on the line.
	relay.limits["per_address"] = 9
	relay.limits["rooms"] = 2
	var over := RelayLink.open_room(info)
	pump.call([over], func() -> bool: return over.state != "calling")
	_check(
		over.state == "refused" and over.why.begins_with("THE PARTY LINE IS FULL UP"),
		"a full line turns a room away (%s)" % over.why
	)
	over.close()
	var first: RelayLink = null
	for r: RelayLink in rooms:
		if r.state == "open" and first == null:
			first = r
	if first == null:
		return
	_check(
		NetRelay.clean_code(first.code.to_lower().replace("-", "")) == first.code,
		"a code typed small and without its dash still reads (%s)" % first.code
	)
	var asked := RelayLink.ask_rooms()
	pump.call([asked], func() -> bool: return asked.state == "done")
	_check(asked.rooms.size() == 2, "the line lists its open rooms (%d)" % asked.rooms.size())
	asked.close()
	var player := RelayLink.join_room(first.code, false)
	pump.call(
		[first, player], func() -> bool: return player.connected() and not first._players.is_empty()
	)
	_check(player.via() == "line", "a player gets in through the line (%s)" % player.state)
	first.take_events()
	# Over the room's 4000 bytes a second: the snapshots that may be lost are,
	# what must arrive does.
	var blob := PackedByteArray()
	blob.resize(400)
	blob[0] = NetWire.SNAP
	var vid: int = first._players.keys()[0]
	for i in 30:
		first.send(vid, NetSession.CH_SNAPS, blob)
	var sure := blob.duplicate()
	sure[0] = NetWire.LOBBY
	for i in 5:
		first.send(vid, NetSession.CH_RELIABLE, sure)
	var got := [0, 0]
	pump.call(
		[first],
		func() -> bool:
			for packet: Array in player.poll(float(Time.get_ticks_msec())):
				var b: PackedByteArray = packet[1]
				got[0 if b[0] == NetWire.SNAP else 1] += 1
			return got[1] >= 5,
		2000.0
	)
	var room: NetRelay.Room = relay.rooms[first.code]
	_check(
		got[0] < 30 and got[0] >= 5 and got[1] == 5 and room.dropped > 0,
		(
			(
				"over its bytes a second a room drops snapshots (%d of 30 came)"
				+ " and keeps what must arrive (%d of 5)"
			)
			% [got[0], got[1]]
		)
	)
	player.close()
	pump.call(
		rooms, func() -> bool: return relay.rooms.is_empty() and first.state == "lost", 6000.0
	)
	_check(
		(
			relay.rooms.is_empty()
			and first.state == "lost"
			and first.why.begins_with("NOBODY CAME BY")
		),
		"an empty room closes after its minutes and the host hears why (%s)" % first.why
	)
	for line: String in relay.take_news():
		print("    line: ", line)
	for r: RelayLink in rooms:
		r.close()


# ------------------------------------------------------------------ the server


func _server() -> bool:
	var port := _base_port()
	for k in 20:
		var config := {
			"bind": "127.0.0.1",
			"relay": {},
			"lobbies":
			[{"port": port + k, "ws_port": port + k + 3000, "lobby_name": "COUNTY LOBBY 1"}]
		}
		server = LobbyServer.new(config, {"difficulty": 1})
		if not server.rooms.is_empty() and server.rooms[0].net.session.also != null:
			lobby_port = port + k
			ws_port = port + k + 3000
			break
		server.free()
		server = null
	_check(
		server != null and server.relay != null, "a lobby server runs the party line on its ports"
	)
	if server == null:
		return false
	root.add_child(server)
	server.set_process(false)
	RelayLink.server = {"host": "127.0.0.1", "port": lobby_port}
	return true


## One frame of play time for the server and everyone polled.
func _frame() -> void:
	now += STEP * 1000.0
	server.frame(now, STEP)
	for net: NetPlay in nets:
		net.poll(now)
		# (Waiting on a start: the host's game ticks idle, the copies follow.)
		if net.phase == "match" and net.role == NetPlay.Role.HOST:
			net.host_tick({})
		elif net.phase == "match":
			net.client_input(Game.Controls.new())
			net.client_play(1)


func _wait(what: Callable, most := 600) -> bool:
	for i in most:
		if what.call():
			return true
		_frame()
		if i % 4 == 0:
			OS.delay_msec(1)
	return what.call()


## A player joining `where` (a code) over ENet, or the WebSocket.
func _join(where: String, name: String, over_ws := false) -> NetPlay:
	var keep := RelayLink.server
	if over_ws:
		RelayLink.server = {"url": "ws://127.0.0.1:%d" % ws_port}
	var net := NetPlay.join_lobby(where, name, "")
	RelayLink.server = keep
	if net != null:
		net.make_match = _make
		nets.append(net)
	return net


func _make(info: Dictionary) -> Game:
	var made: Game = main.net_match_game(info)
	if made != null:
		made.cheats.god = god
	return made


func _host(name: String, port_from: int) -> NetPlay:
	for k in 20:
		var host := NetPlay.host_lobby(port_from + k, name, {}, false, "127.0.0.1", true)
		if host != null:
			host.make_match = _make
			nets.append(host)
			return host
	return null


# ------------------------------------------------------------------ lag


## Round trips of a small echo, straight and through the line.
func _lag() -> void:
	print("THE LAG THE LINE ADDS")
	var port := _base_port() + 9000
	var direct_host: NetSession = null
	for k in 20:
		direct_host = NetSession.host(port + k, NetSession.Transport.ENET, 4, "127.0.0.1")
		if direct_host != null:
			port += k
			break
	var direct := NetSession.join("127.0.0.1", port)
	_spin([direct_host, direct], func() -> bool: return direct.connected())
	var room := RelayLink.open_room({"summary": {}, "listed": false, "port": 0, "open": false})
	_spin([room], func() -> bool: return room.state == "open")
	var player := RelayLink.join_room(room.code, false)
	_spin([room, player], func() -> bool: return player.connected())
	room.take_events()
	var straight := _echo(direct_host, direct, 0.0)
	var line_flat := _echo(room, player, 0.0)
	var line_paced := _echo(room, player, 1000.0 / LobbyServer.MATCH_FPS)
	print(
		(
			(
				"    round trip, median (p95): straight %.2f ms (%.2f), through the line"
				+ " %.2f (%.2f), the line at %d frames a second %.2f (%.2f)"
			)
			% [
				straight[0],
				straight[1],
				line_flat[0],
				line_flat[1],
				LobbyServer.MATCH_FPS,
				line_paced[0],
				line_paced[1]
			]
		)
	)
	_check(
		straight[0] >= 0.0 and line_flat[0] >= 0.0 and line_paced[0] >= 0.0,
		"echoes come back straight and through the line"
	)
	_check(
		line_paced[0] - straight[0] < 2.0 * 1000.0 / LobbyServer.MATCH_FPS + 10.0,
		(
			"the line adds about half a frame each way (%.2f ms; a busy PC allows more)"
			% (line_paced[0] - straight[0])
		)
	)
	for s: NetSession in [direct_host, direct, room, player]:
		s.close()


## Polls the sessions (and the server) on the real clock until `until`.
func _spin(sessions: Array, until: Callable, most_ms := 4000.0) -> bool:
	var began := Time.get_ticks_msec()
	while Time.get_ticks_msec() - began < most_ms:
		var t := float(Time.get_ticks_msec())
		if server != null:
			server.frame(t, 0.0)
		for s: NetSession in sessions:
			s.poll(t)
		if until.call():
			return true
		OS.delay_msec(1)
	return until.call()


## [median, p95] ms of 120 echoes from `player` off `host` (the server
## polled every `pace` ms, 0 flat out; -1 none came back).
func _echo(host: NetSession, player: NetSession, pace: float) -> Array:
	var trips: Array[float] = []
	var server_at := 0
	for i in 120:
		var ping := PackedByteArray([NetWire.INPUTS])
		ping.resize(9)
		var sent := Time.get_ticks_usec()
		ping.encode_s64(1, sent)
		player.send(NetSession.HOST_ID, NetSession.CH_INPUTS, ping)
		server_at -= randi() % 8333  # the server's frame at any point of the echo
		var back := false
		while not back and Time.get_ticks_usec() - sent < 500000:
			var t := Time.get_ticks_usec()
			if server != null and (pace <= 0.0 or t - server_at >= pace * 1000.0):
				server_at = t
				server.frame(t / 1000.0, 0.0)
			for packet: Array in host.poll(t / 1000.0):
				var from: int = packet[0]
				host.send(from, NetSession.CH_INPUTS, packet[1])
			for packet: Array in player.poll(t / 1000.0):
				var bytes: PackedByteArray = packet[1]
				if bytes.size() == 9 and bytes.decode_s64(1) == sent:
					trips.append((Time.get_ticks_usec() - sent) / 1000.0)
					back = true
		OS.delay_msec(2)
	if trips.is_empty():
		return [-1.0, -1.0]
	trips.sort()
	return [trips[trips.size() / 2], trips[mini(trips.size() - 1, int(trips.size() * .95))]]


## The echo through a party line running elsewhere (ping=address:port): what
## a player through it would add, against the trip to the line itself.
func _ping_elsewhere() -> void:
	var target := NetPlay.parse_address(ping_at)
	_check(not target.is_empty(), "the address reads (%s)" % ping_at)
	if target.is_empty():
		return
	RelayLink.server = {"host": target["host"], "port": target["port"]}
	var room := RelayLink.open_room({"summary": {}, "listed": false, "port": 0, "open": false})
	_spin([room], func() -> bool: return room.state != "calling", 8000.0)
	_check(room.state == "open", "a room opens on the line there (%s %s)" % [room.state, room.why])
	if room.state != "open":
		return
	var player := RelayLink.join_room(room.code, false)
	_spin([room, player], func() -> bool: return player.connected(), 8000.0)
	room.take_events()
	var trip := _echo(room, player, 0.0)
	var to_line := player.rtt(NetSession.HOST_ID)
	print(
		(
			"    through the line there: median %.1f ms (p95 %.1f); to the line (ENet's guess) %.0f ms"
			% [trip[0], trip[1], to_line]
		)
	)
	_check(trip[0] >= 0.0, "echoes come back through the line there")
	player.close()
	room.close()


# ------------------------------------------------------------------ 5v5


func _showdown() -> void:
	print("5V5 THROUGH THE PARTY LINE")
	# TREY's home address does not answer (his port is shut to the world).
	RelayLink.test_lan = PackedStringArray(["127.0.0.2"])
	var host := _host("Trey", _base_port() + 5000)
	_wait(func() -> bool: return host != null and host.party_line().state != "calling", 2000)
	var line := host.party_line() if host != null else null
	_check(
		line != null and line.state == "open" and NetRelay.clean_code(line.code) == line.code,
		"TREY hosts and the party line gives him a code (%s)" % (line.code if line != null else "-")
	)
	if line == null or line.state != "open":
		return
	var code := line.code
	var wrong := "BCD-001" if code != "BCD-001" else "BCD-002"
	var lost := _join(wrong, "Nobody")
	_wait(func() -> bool: return lost.phase == "closed", 600)
	_check(
		lost.phase == "closed" and lost.reason == "NOBODY'S ON THE PARTY LINE BY THAT CODE",
		"a wrong code is turned away (%s)" % lost.reason
	)
	nets.erase(lost)
	var dave := NetPlay.join_lobby("127.0.0.1:%d" % lobby_port, "Dave", "")
	dave.make_match = _make
	nets.append(dave)
	var began := now
	var alice := _join(code.to_lower(), "Alice")
	var bob := _join(code.replace("-", ""), "Bob", true)
	var joined_at := [0.0]  # (a lambda keeps its own copy of a plain local)
	_wait(
		func() -> bool:
			if joined_at[0] == 0.0 and alice.phase == "lobby":
				joined_at[0] = now
			return alice.phase == "lobby" and bob.phase == "lobby" and dave.phase == "lobby",
		3000
	)
	var alice_joined_at: float = joined_at[0]
	var alice_link := alice.session as RelayLink
	var bob_link := bob.session as RelayLink
	_check(
		(
			alice.phase == "lobby"
			and alice_link.via() == "line"
			and alice_link.look
			and alice_joined_at - began >= RelayLink.DIRECT_WAIT * 1000.0
		),
		(
			"ALICE (ENet) tried TREY's own address, then came in through the line (%s, %.1f s of play time)"
			% [alice_link.state, (alice_joined_at - began) / 1000.0]
		)
	)
	_check(
		bob.phase == "lobby" and bob_link.via() == "line" and not bob_link.look,
		"BOB (WebSocket, the browser's way) came straight in through the line (%s)" % bob_link.state
	)
	_check(
		(
			host.players.size() == 3
			and dave.phase == "lobby"
			and dave.settings["lobby_name"] == "COUNTY LOBBY 1"
		),
		"DAVE sits in the server's own lobby on the same port (%d in TREY's)" % host.players.size()
	)
	var list := NetBrowser.new([])
	_wait(
		func() -> bool:
			list.poll(now)
			return list.servers.size() > 0,
		600
	)
	_check(
		list.servers.size() == 1 and list.address_of(0) == code and list.why_not_join(0) == "",
		(
			"the servers list shows TREY's room and joins it by its code (%d rows)"
			% list.servers.size()
		)
	)
	list.close()
	host.set_setting("mode", Modes.BOMB)
	host.set_setting("map", map_id)
	host.set_setting("team_size", team)
	host.set_setting("rounds", 3)
	host.set_setting("freeze_seconds", 3.0)
	host.set_setting("start_money", 4000)
	host.set_setting("round_seconds", 60.0)
	alice.ask({"team": 1, "ready": true})
	bob.ask({"ready": true})
	_wait(
		func() -> bool:
			return (
				bool(host.player_of(alice.my_id).get("ready", false))
				and bool(host.player_of(bob.my_id).get("ready", false))
			),
		1200
	)
	_check(
		(
			str(alice.settings["lobby_name"]) == str(host.settings["lobby_name"])
			and str(dave.settings["lobby_name"]) == "COUNTY LOBBY 1"
		),
		"each lobby's news reaches only its own (ALICE sees %s)" % alice.settings["lobby_name"]
	)
	var why := host.start_match()
	_wait(func() -> bool: return alice.client_ready() and bob.client_ready(), 1200)
	_check(
		why == "" and alice.client_ready() and bob.client_ready(),
		"the match starts on every copy %s" % why
	)
	if not (alice.client_ready() and bob.client_ready()):
		return
	var g := host.match_game()
	var st = Modes.feature(g)
	var room: NetRelay.Room = server.relay.rooms[code]
	var up0 := room.up
	var down0 := room.down
	var pilots := {0: TacticalBot.new(0)}
	for slot: int in host.bot_slots():
		pilots[slot] = TacticalBot.new(slot)
	var players := {alice: TacticalBot.new(alice.my_slot()), bob: TacticalBot.new(bob.my_slot())}
	var ticks := int(seconds / STEP)
	var carl: NetPlay = null
	var carl_at := int(ticks * .6)
	var before_carl := {}
	var wall := Time.get_ticks_msec()
	for t in ticks:
		now += STEP * 1000.0
		server.frame(now, STEP)
		for net: NetPlay in nets:
			net.poll(now)
		for change: Dictionary in host.take_changes():
			if change.has("bot"):
				pilots[int(change["bot"])] = TacticalBot.new(int(change["bot"]))
			elif change.has("human"):
				pilots.erase(int(change["human"]))
		for net: NetPlay in players:
			net.take_changes()
			var c := Game.Controls.new()
			var bot: TacticalBot = players[net]
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
		for net: NetPlay in players:
			net.client_play(1)
		if t == carl_at:
			for net: NetPlay in [alice, bob]:
				before_carl[net] = net.client_sync.mismatches
			# TREY's address answers now (his router opened it, say).
			RelayLink.test_lan = PackedStringArray(["127.0.0.1"])
			host.send_lobby()
		if t == carl_at + 10:
			carl = _join(code, "Carl")
			players[carl] = null
		if carl != null and players[carl] == null and carl.client_ready():
			players[carl] = TacticalBot.new(carl.my_slot())
		if t % 30 == 0:
			OS.delay_msec(1)
	var played := ticks * STEP
	var people := 2.0 + (1.0 if carl != null and carl_link_via(carl) == "line" else 0.0)
	var per := [(room.up - up0) / played / people, (room.down - down0) / played / people]
	print(
		(
			(
				"    %.0f s of play in %.1f s; round %d; through the line per player:"
				+ " up %.1f KB/s, down %.1f KB/s (payload; the line's own header"
				+ " 5 B a packet up, 6 down)"
			)
			% [
				played,
				(Time.get_ticks_msec() - wall) / 1000.0,
				st.round_no,
				per[0] / 1024.0,
				per[1] / 1024.0
			]
		)
	)
	for net: NetPlay in [alice, bob, carl]:
		if net == null or net.client_sync == null:
			continue
		var cs := net.client_sync
		print(
			(
				"    %s (%s): %d checks, %d mismatches, %d rebuilds; ping %.0f ms%s"
				% [
					net._my_name,
					(net.session as RelayLink).via(),
					cs.checks,
					cs.mismatches,
					cs.rebuilds,
					net.ping_ms(),
					"" if cs.first_mismatch == "" else "; first: " + cs.first_mismatch
				]
			)
		)
	# (A late joiner's name on a bot's place parts every copy once, as on a
	# direct line: net_showdown_check allows it too.)
	for net: NetPlay in [alice, bob]:
		var cs := net.client_sync
		var early: int = before_carl.get(net, -1)
		_check(
			cs.checks > 3 and early == 0 and cs.mismatches <= 1,
			(
				"%s's copy keeps with the host through the line (%d checks, %d mismatches, %d before CARL)"
				% [net._my_name, cs.checks, cs.mismatches, early]
			)
		)
	var frags := 0
	for p: Player in g.players:
		frags += p.frags
	_check(
		int(st.round_no) >= 2 or frags > 0,
		"the match is fought (round %d, %d frags)" % [st.round_no, frags]
	)
	_check(
		per[1] > 1000.0 and per[1] < 200000.0,
		"the bytes per player are in reason (%.0f B/s down)" % per[1]
	)
	var carl_link: RelayLink = carl.session as RelayLink if carl != null else null
	_check(
		carl != null and carl.client_ready() and carl_link.via() == "direct",
		(
			"CARL joins late by the code and goes straight to the host (%s)"
			% (carl_link.state if carl_link != null else "-")
		)
	)
	if carl != null and carl.client_sync != null:
		_check(carl.client_sync.mismatches == 0, "CARL's copy keeps with the host")
	host.kick(bob.my_id)
	_wait(func() -> bool: return bob.phase == "closed", 600)
	_check(
		(
			bob.phase == "closed"
			and bob.reason == "THE HOST KICKED YOU"
			and host.player_of(bob.my_id).is_empty()
		),
		"the host shows BOB the door through the line (%s)" % bob.reason
	)
	host.leave("THE HOST CLOSED THE LOBBY")
	_wait(func() -> bool: return alice.phase == "closed" and server.relay.rooms.is_empty(), 600)
	_check(
		alice.phase == "closed" and alice.reason == "THE HOST CLOSED THE LOBBY",
		"closing tells everyone through the line (%s)" % alice.reason
	)
	_check(server.relay.rooms.is_empty(), "the room closes with its host")
	for l: String in server.relay.take_news():
		print("    line: ", l)
	dave.leave()
	_wait(func() -> bool: return dave.finished(), 60)
	for net: NetPlay in nets.duplicate():
		if net.finished() or net.phase == "closed":
			nets.erase(net)


# ------------------------------------------------------------------ County Run


func carl_link_via(net: NetPlay) -> String:
	return (net.session as RelayLink).via() if net.session is RelayLink else ""


func _county() -> void:
	print("COUNTY RUN THROUGH THE PARTY LINE")
	god = true
	RelayLink.test_lan = PackedStringArray()
	var host := _host("Trey", _base_port() + 6000)
	_wait(func() -> bool: return host != null and host.party_line().state != "calling", 2000)
	if host == null or host.party_line().state != "open":
		_check(false, "TREY opens a COUNTY RUN room")
		return
	host.set_setting("map", "county_hickston")
	var code := host.party_line().code
	var alice := _join(code, "Alice")
	var bob := _join(code, "Bob", true)
	_wait(func() -> bool: return alice.phase == "lobby" and bob.phase == "lobby", 3000)
	_check(
		host.county() and host.players.size() == 3,
		"a COUNTY RUN lobby with two players through the line (%d)" % host.players.size()
	)
	alice.ask({"ready": true})
	bob.ask({"ready": true})
	_wait(
		func() -> bool:
			return (
				bool(host.player_of(alice.my_id).get("ready", false))
				and bool(host.player_of(bob.my_id).get("ready", false))
			),
		1200
	)
	var why := host.start_match()
	_wait(func() -> bool: return alice.client_ready() and bob.client_ready(), 1200)
	_check(
		why == "" and alice.client_ready() and bob.client_ready(),
		"the run starts on every copy %s" % why
	)
	if not (alice.client_ready() and bob.client_ready()):
		return
	var g := host.match_game()
	var f = CountyMode.run(g)
	var bots := {}
	var ticks := int(county_seconds / STEP)
	for t in ticks:
		now += STEP * 1000.0
		server.frame(now, STEP)
		for net: NetPlay in nets:
			net.poll(now)
		for net: NetPlay in [alice, bob]:
			var c := Game.Controls.new()
			if net.client_ready():
				c = _county_steer(net.match_game(), net.my_slot(), bots, net)
			net.client_input(c)
		var mine := _county_steer(g, 0, bots, host, false)
		host.host_tick({0: mine})
		for net: NetPlay in [alice, bob]:
			net.client_play(1)
		if t % 30 == 0:
			OS.delay_msec(1)
	print(
		(
			"    %.0f s: level %d, %d kills, %d picks; ALICE %d checks %d mismatches, BOB %d / %d"
			% [
				f.run_time,
				f.level,
				g.kills,
				f.picks.size(),
				alice.client_sync.checks,
				alice.client_sync.mismatches,
				bob.client_sync.checks,
				bob.client_sync.mismatches
			]
		)
	)
	for net: NetPlay in [alice, bob]:
		var cs := net.client_sync
		_check(
			cs.checks > 3 and cs.mismatches == 0,
			(
				"%s's copy of the run keeps with the host (%d checks, %d mismatches%s)"
				% [
					net._my_name,
					cs.checks,
					cs.mismatches,
					"" if cs.first_mismatch == "" else ": " + cs.first_mismatch
				]
			)
		)
		var cf = CountyMode.run(net.match_game())
		_check(
			cf != null and abs(cf.level - f.level) <= 1,
			(
				"%s's copy has the party's level (%d, host %d)"
				% [net._my_name, cf.level if cf != null else -1, f.level]
			)
		)
	_check(
		f.run_time > county_seconds * .8 and f.spawned > 0,
		"the run goes on through the line (%d spawned, %d kills)" % [f.spawned, g.kills]
	)
	# The host's game goes away with no goodbye (a crash): the line tells both.
	host.finish()
	_wait(func() -> bool: return alice.phase == "closed" and bob.phase == "closed", 600)
	_check(
		alice.reason == "THE HOST HUNG UP" and bob.reason == "THE HOST HUNG UP",
		"the host gone without a word, the line tells both (%s, %s)" % [alice.reason, bob.reason]
	)


## The County Run bot's controls for `slot` in `game`; the leader picks the
## cards on offer.
func _county_steer(
	game: Game, slot: int, bots: Dictionary, key: Variant, gentle := true
) -> Game.Controls:
	var c := Game.Controls.new()
	var me: Player = game.players[slot]
	if not bots.has(key):
		bots[key] = CountyBot.new()
	var f = CountyMode.run(game)
	if me.health > 0:
		game.focus(me)
		c = bots[key].steer(game)
		if gentle:
			# A copy shows the aim a few ticks late: turn gently (county_net_check).
			c.turn *= .3
			c.look *= .3
		bots[key].moved(game)
		game.focus(game.local_player)
	if f != null and not f.offer.is_empty() and CountyCoop.leader(game) == me:
		var i := CountyBot.pick(game, f)
		var full: bool = String(f.offer[i]["type"]) == "weapon" and CountyBuild.open_slot(f) < 0
		c.buy = CountyCoop.encode(i, 0 if full else -1)
	return c
