## COUNTY RUN co-op online (src/modes/county_coop.gd), headless, in one
## process over 127.0.0.1:
##
##   Godot --headless --path <project> --script res://tools/county_net_check.gd
##       [-- seconds=<play>] [map=county_quarry]
##
## An always-open lobby on a county map: ALICE joins over ENet and runs it,
## BOB over the lobby's WebSocket side (the browser's way in). Both ready,
## ALICE starts; each plays with the County Run bot steering their own player
## in their copy, ALICE (the leader) picks every card through her controls.
## Checks: the lobby's mode follows the county map, the match is a party of
## two, both copies keep with the server's game (its checks find no parting),
## the party levels and the cards land in both players' armories on every
## copy, and no script or engine errors. Then the server's lobby takes them
## back once the run is over (killed off for the test).
extends SceneTree

const STEP := NetSync.STEP
const Bot := preload("res://tools/county_bot.gd")

var failures: Array = []
var server: LobbyServer
var main: Control
var now := 0.0
var nets: Array = []
var bots := {}
var seconds := 40.0
var map_id := "county_hickston"
var ws_port := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("seconds="):
			seconds = float(arg.substr(8))
		elif arg.begins_with("map="):
			map_id = arg.substr(4)
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
	print("")
	print("COUNTY NET CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


func _make(info: Dictionary) -> Game:
	# God mode in every copy from the start (the bots play, nobody dies).
	var made: Game = main.net_match_game(info)
	if made != null:
		made.cheats.god = true
	return made


## One frame for the server and both clients: each client's bot steers its
## own player in its copy; the leader's copy picks the cards on offer.
func _frame() -> void:
	now += STEP * 1000.0
	server.frame(now, STEP)
	for net: NetPlay in nets:
		net.poll(now)
		if net.phase != "match" or net.role != NetPlay.Role.CLIENT:
			continue
		var c := Game.Controls.new()
		if net.client_ready():
			var copy := net.match_game()
			var me: Player = copy.players[net.my_slot()]
			if not bots.has(net):
				bots[net] = Bot.new()
			var f = CountyMode.run(copy)
			if me.health > 0:
				copy.focus(me)
				c = bots[net].steer(copy)
				# The copy shows the aim a few ticks late: turn gently, or the bot
				# swings past its target and never fires (a person sees the aim at once).
				c.turn *= .3
				c.look *= .3
				bots[net].moved(copy)
				copy.focus(copy.local_player)
			if f != null and not f.offer.is_empty() and CountyCoop.leader(copy) == me:
				var i := Bot.pick(copy, f)
				var full: bool = (
					String(f.offer[i]["type"]) == "weapon" and CountyBuild.open_slot(f) < 0
				)
				c.buy = CountyCoop.encode(i, 0 if full else -1)
		net.client_input(c)
		net.client_play(1)
	OS.delay_msec(1)


func _wait(what: Callable, most := 600) -> bool:
	for i in most:
		if what.call():
			return true
		_frame()
	return what.call()


func _join(name: String, over_ws: bool) -> NetPlay:
	var where := "127.0.0.1:%d" % server.rooms[0].net.port
	if over_ws:
		where = "ws://127.0.0.1:%d" % ws_port
	var net := NetPlay.join_lobby(where, name, "")
	net.make_match = _make
	nets.append(net)
	return net


func _play() -> void:
	var port := 42000 + OS.get_process_id() % 15000
	for k in 20:
		var config := {
			"bind": "127.0.0.1",
			"lobbies":
			[{"port": port + k, "ws_port": port + k + 3000, "lobby_name": "RUN", "map": map_id}]
		}
		server = LobbyServer.new(config, {"difficulty": 1})
		ws_port = port + k + 3000
		if not server.rooms.is_empty() and server.rooms[0].net.session.also != null:
			break
		server.free()
		server = null
	_check(server != null, "the server opens a lobby on %s" % map_id)
	if server == null:
		return
	root.add_child(server)
	server.set_process(false)
	var lobby: NetPlay = server.rooms[0].net
	_check(lobby.county(), "a county map makes it a COUNTY RUN co-op lobby")
	var alice := _join("alice", false)
	_wait(func() -> bool: return alice.phase == "lobby" and alice.is_admin())
	var bob := _join("bob", true)
	_wait(func() -> bool: return bob.phase == "lobby" and lobby.players.size() == 2)
	_check(
		alice.is_admin() and bob.phase == "lobby", "ALICE (ENet) runs it, BOB came in by WebSocket"
	)
	bob.ask({"ready": true})
	_wait(func() -> bool: return bool(alice.player_of(bob.my_id).get("ready", false)))
	var why := alice.start_match()
	_wait(func() -> bool: return alice.client_ready() and bob.client_ready())
	_check(
		lobby.phase == "match" and alice.client_ready() and bob.client_ready(),
		"ALICE starts the run (%s), both copies have it" % (why if why != "" else "ok")
	)
	if not (alice.client_ready() and bob.client_ready()):
		return
	var g: Game = lobby.match_game()
	var f = CountyMode.run(g)
	_check(
		f != null and g.players.size() == 2, "the server's game is a party of two in a County Run"
	)
	if f == null:
		return
	var start_at := [
		Vector2(g.players[0].x, g.players[0].y), Vector2(g.players[1].x, g.players[1].y)
	]
	_wait(func() -> bool: return f.run_time >= seconds * .5, int(seconds / STEP) + 2000)
	# Two levels' XP at once on the server: the leader picks both cards, in turn,
	# through her controls (whatever the bots managed by themselves).
	var picked: int = f.picks.size()
	var before := [alice.client_sync.mismatches, bob.client_sync.mismatches]
	CountyMode.gain(g, f, CountyData.xp_to_next(f.level) + CountyData.xp_to_next(f.level + 1))
	_wait(func() -> bool: return f.run_time >= seconds, int(seconds / STEP) + 4000)
	var up := 0
	for e: Enemy in g.enemies:
		if e.alive and e.hostile:
			up += 1
	print(
		(
			"    spawned %d, up %d, orbs %d; walked %.1f and %.1f; shots %d"
			% [
				f.spawned,
				up,
				f.orbs.size(),
				start_at[0].distance_to(Vector2(g.players[0].x, g.players[0].y)),
				start_at[1].distance_to(Vector2(g.players[1].x, g.players[1].y)),
				g.shots.size()
			]
		)
	)
	var copies := [alice.match_game(), bob.match_game()]
	var levels: Array = []
	var same_guns := true
	for copy: Game in copies:
		var cf = CountyMode.run(copy)
		levels.append(cf.level if cf != null else -1)
		same_guns = (
			same_guns
			and copy.players[0].armory.owned == copy.players[1].armory.owned
			and copy.players[0].armory.owned == g.players[0].armory.owned
		)
	print(
		(
			"    %.0f s: level %d, %d kills, %d picks; ALICE %d checks %d mismatches, BOB %d / %d%s"
			% [
				f.run_time,
				f.level,
				g.kills,
				f.picks.size(),
				alice.client_sync.checks,
				alice.client_sync.mismatches,
				bob.client_sync.checks,
				bob.client_sync.mismatches,
				(
					""
					if bob.client_sync.first_mismatch == ""
					else "; BOB first: " + bob.client_sync.first_mismatch
				)
			]
		)
	)
	_check(
		f.level >= 3 and f.picks.size() >= picked + 2 and f.pending.is_empty(),
		"the party levels and the leader's cards land (%d picks)" % f.picks.size()
	)
	_check(
		levels.all(func(l: int) -> bool: return abs(l - f.level) <= 1),
		"both copies have the party's level (%s, server %d)" % [levels, f.level]
	)
	_check(same_guns, "everyone carries the party's guns on every copy")
	# The XP handed to the server's game outside a tick parts the copies once
	# (rebuilt from the next snapshot); before it, never.
	for k in 2:
		var net: NetPlay = [alice, bob][k]
		var cs: NetSync.Client = net.client_sync
		_check(
			cs.checks > 3 and int(before[k]) == 0 and cs.mismatches - int(before[k]) <= 1,
			(
				"%s's copy keeps with the server's game (%d checks, %d mismatches%s)"
				% [
					net._my_name,
					cs.checks,
					cs.mismatches,
					"" if cs.first_mismatch == "" else ": " + cs.first_mismatch
				]
			)
		)
	# The run ends (both down): the lobby takes everyone back on its own.
	g.cheats.god = false
	for p: Player in g.players:
		g.damage(9999, null, "test", p)
	_wait(func() -> bool: return lobby.phase == "lobby", int((NetPlay.BACK_AFTER + 3.0) / STEP))
	_check(f.over and lobby.phase == "lobby", "the run over, the lobby takes everyone back")
