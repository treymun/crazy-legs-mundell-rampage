## Long online soaks of every online mode, headless, in one process on the
## tool's own clock (pass 12, NETSOAK): a lobby server of this build on
## 127.0.0.1 (ENet, and its WebSocket side for the last player: the
## browser's way in) with test latency, jitter and loss on every session,
## two to four players each steered by a bot from its own copy as a person
## would from their screen, and the world broken on purpose all the while.
##
##   godot --headless --path godot --script res://tools/net_soak_all.gd
##       [-- modes=county,bomb,hostage,tagteam,deathmatch,team_deathmatch,coop]
##       [people=2] [minutes=1] [lags=120] [jitter=.2] [loss=.02]
##       [wreck=1] [every=4] [late=1] [ws=1] [clock=1] [grow=.15] [putback=0]
##       [why=1] [quick]
##
## - **Modes**: the always-open lobby's (5v5 SEARCH AND DESTROY and HOSTAGE
##   RESCUE with bots filling, TAG TEAM 2V2, DEATHMATCH and TEAM DEATHMATCH,
##   COUNTY RUN co-op with the leader's card picks), and CAMPAIGN CO-OP hosted
##   from the real front end through the party line (the host plays player
##   one; one partner straight in, one through the line over WebSocket).
##   A match that ends (rounds, frag or time limit) starts again.
## - **Destruction on purpose** (`wreck`): a director on every game alike
##   (the server's and each copy, `Wrecker`) sets off chains of blasts nobody
##   threw every `every` seconds of the game's clock, inside the tick, the
##   same on every machine: at the breakables (chain blasts through barrels
##   and tanks), the barns, the water tower and the fuel line (brought down),
##   the vehicles (wrecked), the fences and windows, and among the hands (a
##   crowd thrown as bodies). Play, so every copy must keep with the server.
## - **Late join** (`late`): half way through, the last player leaves and
##   joins again into what is broken: its copy must keep, and its looks must
##   show the fallen set pieces lying in their pieces (wreckage's ruin).
## - **Fails** on any parting of a copy from the server (put back on a
##   snapshot) beyond what a late join or a lost input row explains, a
##   drop, a script or engine error, objects in the process or lists in a
##   game growing over the run's second half past `grow` (a share), and a
##   late joiner's copy or looks not right.
## - **Reports** per run: partings and where, put-backs (inputs lost), round
##   trips, bandwidth down and up per player and its p95 a second while
##   things break, the client's frame (its copy's ticks, putting snapshots
##   on, the prediction and shown shots) median / p99 / worst while quiet and
##   while things break, the server's tick, memory and objects.
##
## `putback=S`: every S seconds each copy is put back on the newest snapshot
## (as a lost input row does) and must still keep: play that a snapshot does
## not carry shows up as a parting after it. `clock`: COUNTY RUN co-op's
## copies paced by the clock (NetSync.Client by_clock on: 1, the default
## here) or the old playout (0). `quick`: County Run co-op and campaign co-op
## at 120 ms, put back every 5 s, County Run for two minutes (its objects
## and memory flat over the second), co-op for 30 s (check_all).
extends SceneTree

const NetPorts := preload("res://tools/net_ports.gd")
const CountyBot := preload("res://tools/county_bot.gd")
const ModeBot := preload("res://tools/mode_bot.gd")
const Wrecker := preload("res://tools/net_soak_wrecker.gd")

const STEP := NetSync.STEP
## Seconds after a destruction event its frames count as "while things break".
const BUSY_FOR := 3.0

var failures: Array = []
var main: Control
var opts := {
	"modes": "county,bomb,hostage,tagteam,deathmatch,team_deathmatch,coop",
	"people": 2,
	"minutes": 1.0,
	"lags": "120",
	"jitter": .2,
	"loss": .02,
	"wreck": 1,
	"every": 4.0,
	"late": 1,
	"ws": 1,
	"clock": 1,
	"grow": .25,
	"mb_min": 40.0,
	"coop_minutes": -1.0,
	"putback": 0.0,
	"why": 0,
	"places": 1,
}
var rows: Array = []

# One run's state.
var server: LobbyServer = null
var lobby: NetPlay = null
var nets: Array = []
var pilots := {}
var now := 0.0
var lag := 0.0
var jitter := 0.0
var loss := 0.0
var mode := ""
var port := 0
var ws_port := 0
var wreckers := {}
var busy_until := -1.0
var frame_us := {}
var forced_putbacks := 0
## A quiet or busy frame's parts: taking packets (and patching snapshots),
## playing the copy out, drawing it led (prediction and shown shots).
var parts := {}
var down_seconds := {"quiet": PackedFloat32Array(), "busy": PackedFloat32Array()}
var _down_mark := 0
var _down_at := 0.0
var _down_busy := false
var tallies := {}
var samples: Array = []
var matches := 0
var host_bot = null
## The players' copies (each run's own pool, swept as the front end would).
var copies := GamePool.new()


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var quick := false
	for arg: String in OS.get_cmdline_user_args():
		if arg == "quick":
			quick = true
			continue
		var kv := arg.split("=", true, 1)
		if kv.size() == 2 and opts.has(kv[0]):
			var was: Variant = opts[kv[0]]
			if was is String:
				opts[kv[0]] = kv[1]
			elif was is int:
				opts[kv[0]] = int(kv[1])
			else:
				opts[kv[0]] = float(kv[1])
	if quick:
		opts["modes"] = "county,coop"
		opts["minutes"] = 2.0
		opts["coop_minutes"] = .5
		opts["lags"] = "120"
		opts["putback"] = 5.0
	opts["people"] = clampi(int(opts["people"]), 2, 4)
	# Off: the old packets, no place rows sent (a measurement's before).
	NetSync.Host.send_places = int(opts["places"]) != 0
	# The engine's frames (awaited in the soak) without their sleep or cap.
	OS.low_processor_usage_mode_sleep_usec = 0
	Engine.max_fps = 0
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var tally := CrashLog.tally()
	for m: String in str(opts["modes"]).split(","):
		for lag_text: String in str(opts["lags"]).split(","):
			var l := float(lag_text)
			var row: Dictionary = await soak(
				m.strip_edges(), l, l * float(opts["jitter"]), float(opts["loss"])
			)
			if not row.is_empty():
				rows.append(row)
	tally.stop()
	_check(
		tally.errors == 0,
		(
			"no script or engine errors"
			+ ("" if tally.errors == 0 else " (%d: %s)" % [tally.errors, tally.first_errors[0]])
		)
	)
	print("")
	_table()
	print("")
	print("NET SOAK ALL OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)
		if OS.get_environment("GITHUB_ACTIONS") != "":
			print("::error title=net_soak_all.gd::%s" % text)


# ------------------------------------------------------------ the director


## The director on a game (once), and god on every machine alike in the
## co-op modes (nobody's run ends while the world is broken round them).
func _dress(g: Game) -> Game:
	if g == null:
		return g
	if mode in ["county", "coop"]:
		g.cheats.god = true
	if int(opts["wreck"]) != 0 and not wreckers.has(g):
		wreckers[g] = Wrecker.new(g, float(opts["every"]))
	return g


# ------------------------------------------------------------ one run


func soak(m: String, l: float, j: float, lo: float) -> Dictionary:
	mode = m
	lag = l
	jitter = j
	loss = lo
	nets = []
	pilots = {}
	wreckers = {}
	tallies = {}
	samples = []
	matches = 0
	busy_until = -1.0
	frame_us = {
		"quiet": PackedFloat32Array(),
		"busy": PackedFloat32Array(),
		"check": PackedFloat32Array(),
		"putback": PackedFloat32Array(),
	}
	forced_putbacks = 0
	parts = {
		"poll": PackedFloat32Array(),
		"play": PackedFloat32Array(),
		"shown": PackedFloat32Array(),
		"host": PackedFloat32Array(),
	}
	down_seconds = {"quiet": PackedFloat32Array(), "busy": PackedFloat32Array()}
	print("")
	print(
		(
			"SOAK %s, %d players, %.0f ms (+%.0f jitter, %.0f%% loss), %.1f min"
			% [mode, opts["people"], lag, jitter, loss * 100.0, opts["minutes"]]
		)
	)
	var ok := _open_coop() if mode == "coop" else _open_server()
	if not ok:
		_close()
		return {}
	var row: Dictionary = await _play()
	_close()
	return row


func _lobby_config() -> Dictionary:
	var lb := {"lobby_name": "SOAK", "mode": mode, "rounds": 10}
	match mode:
		"bomb", "hostage":
			lb["map"] = "grainyard"
			lb["team_size"] = 5
		"tagteam":
			lb["map"] = "pumpngo"
			lb["team_size"] = 2
		"deathmatch", "team_deathmatch":
			lb["map"] = "hickston:boss"
			lb["frag_limit"] = 30
			lb["time_limit"] = 900.0
		"county":
			lb["map"] = "county_hickston"
	return lb


func _open_server() -> bool:
	var base := NetPorts.pick("net_soak_all " + mode, [0], [3000])
	for k in 20:
		var lb := _lobby_config()
		lb["port"] = base + k
		lb["ws_port"] = base + k + 3000
		var config := {"bind": "127.0.0.1", "relay": {}, "lobbies": [lb]}
		server = LobbyServer.new(config, {"difficulty": 1})
		if not server.rooms.is_empty() and server.rooms[0].net.session.also != null:
			port = base + k
			ws_port = base + k + 3000
			break
		server.free()
		server = null
	if server == null:
		_check(false, "%s: the server opens a lobby" % mode)
		return false
	root.add_child(server)
	server.set_process(false)
	Engine.max_fps = 0  # (a lobby server caps the frames when it starts)
	lobby = server.rooms[0].net
	var made: Callable = lobby.make_match
	lobby.make_match = func(info: Dictionary) -> Game: return _dress(made.call(info))
	_lag(lobby.session)
	var people := int(opts["people"])
	for i in people:
		var over_ws := int(opts["ws"]) != 0 and i == people - 1 and i > 0
		var net := _join("P%d" % (i + 1), over_ws)
		if net == null or not _wait(func() -> bool: return net.phase == "lobby", 4000):
			_check(false, "%s: P%d joins the lobby (%s)" % [mode, i + 1, net.reason if net else ""])
			return false
	var admin: NetPlay = nets[0]
	for net: NetPlay in nets.slice(1):
		net.ask({"ready": true})
	_wait(func() -> bool: return _all_ready(admin, people), 2000)
	return _start()


## Everyone in the admin's lobby, and everyone else ready.
static func _all_ready(admin: NetPlay, people: int) -> bool:
	if admin.players.size() != people:
		return false
	for p: Dictionary in admin.players:
		if not bool(p.get("ready", false)) and p["id"] != admin.my_id:
			return false
	return true


func _start() -> bool:
	var admin: NetPlay = nets[0]
	var why := admin.start_match()
	var started := _wait(
		func() -> bool: return nets.all(func(n: NetPlay) -> bool: return n.client_ready()), 4000
	)
	_check(why == "" and started, "%s: the match starts on every copy (%s)" % [mode, why])
	if started:
		matches += 1
	return started


func _lag(s: NetSession) -> void:
	if s == null:
		return
	s.lag_ms = lag
	s.jitter_ms = jitter
	s.loss = loss
	if s.also != null:
		_lag(s.also)


func _join(name: String, over_ws: bool) -> NetPlay:
	var where := "127.0.0.1:%d" % port
	if over_ws:
		where = "ws://127.0.0.1:%d" % ws_port
	var net := NetPlay.join_lobby(where, name, "")
	if net == null:
		return null
	net.make_match = func(info: Dictionary) -> Game:
		var made: Game = main.net_match_game(info)
		if made != null:
			made.net_role = "copy"
			# The players' copies are the soak's, not the front end's: its
			# own sweep at a frame's end (coop's host) would let them go.
			main.games._games.erase(made)
			copies.track(made)
		return _dress(made)
	_lag(net.session)
	nets.append(net)
	if not tallies.has(name):
		tallies[name] = {
			"mismatches": 0,
			"rebuilds": 0,
			"lost": 0,
			"stale": 0,
			"no_base": 0,
			"lag": PackedFloat32Array(),
			"logs": [],
			"drops": [],
			"down": 0,
			"up": 0,
			"via": "ws" if over_ws else "enet",
		}
	return net


func _close() -> void:
	for net: NetPlay in nets:
		if net.session != null:
			net.session.close()
	if mode == "coop" and main.net != null:
		main.net.finish()
		main.net = null
		main.game = null
		RelayLink.server = {}
		RelayLink.test_lan = PackedStringArray()
	if server != null:
		for room in server.rooms:
			room.net.finish()
		server.queue_free()
		server = null
	copies.clear()
	main.games.sweep([])
	lobby = null
	host_bot = null


# ------------------------------------------------------------ frames


## One frame: the server (and the line), the host's front end in co-op, each
## player's input from their bot and their copy played out and drawn as
## main.gd draws it (led by the prediction, own shots shown, put back).
func _frame(measure := false) -> void:
	now += STEP * 1000.0
	if server != null:
		server.frame(now, STEP)
	if mode == "coop":
		_host_frame()
	var busy := now < busy_until
	for net: NetPlay in nets:
		var t0 := Time.get_ticks_usec()
		net.poll(now)
		var polled := Time.get_ticks_usec() - t0
		if net.phase != "match":
			continue
		var c := Game.Controls.new()
		var copy: Game = net.match_game() if net.client_ready() else null
		var me: Player = null
		if copy != null and net.my_slot() >= 0 and net.my_slot() < copy.players.size():
			me = copy.players[net.my_slot()]
		var bot_us := 0
		if me != null and me.health > 0:
			var b0 := Time.get_ticks_usec()
			c = _steer(net, copy, me)
			bot_us = Time.get_ticks_usec() - b0
		net.client_input(c)
		var cs: NetSync.Client = net.client_sync
		var rebuilt := 0
		var played_us := 0
		var checked := cs.checks if cs != null else 0
		if cs != null:
			cs.by_clock = int(opts["clock"]) != 0 or not net.county()
			rebuilt = cs.rebuilds
			var forced := float(opts["putback"])
			if forced > 0.0 and cs.game_tick > 0 and fmod(now, forced * 1000.0) < STEP * 1000.0:
				# A put back as a lost input row makes one: the copy onto the
				# newest snapshot; every check after it must still match.
				cs._rebuild(false)
				forced_putbacks += 1
			var p0 := Time.get_ticks_usec()
			cs.playout(1, now)
			played_us = Time.get_ticks_usec() - p0
			rebuilt = cs.rebuilds - rebuilt
		if me != null and me.health > 0 and net.client_ready() and copy.local_player == me:
			if not net.has_meta("shots"):
				net.set_meta("shots", NetShotPredict.new())
			var sp: NetShotPredict = net.get_meta("shots")
			sp.now_ms = now
			var walked := NetPredict.lead(copy, me, cs.unplayed_inputs())
			sp.restore(copy, me, sp.frame(copy, me, cs))
			NetPredict.restore(me, walked)
		if measure:
			var spent := float(Time.get_ticks_usec() - t0 - bot_us)
			var kind := "busy" if busy else "quiet"
			if cs != null and cs.checks != checked:
				kind = "check"
			if rebuilt > 0:
				kind = "putback"
			frame_us[kind].append(spent)
			if kind == "quiet" or kind == "busy":
				parts["poll"].append(polled)
				parts["play"].append(played_us)
				parts["shown"].append(spent - polled - played_us)
	_note_busy()
	if int(opts["why"]) != 0:
		_why()
	if measure:
		_bandwidth(busy)


## `why`: why each whole snapshot went, and what a delta carries a second
## after each destruction event (the biggest parts first).
func _why() -> void:
	var hs: NetSync.Host = null
	if mode == "coop":
		hs = main.net.host_sync if main.net != null else null
	elif lobby != null:
		hs = lobby.host_sync
	if hs == null:
		return
	var nfull := hs.sizes_full.size()
	if nfull != int(get_meta("nfull", 0)):
		set_meta("nfull", nfull)
		var why: Array = []
		for r: NetSync.Remote in hs.remotes.values():
			why.append("slot %d acked %d has %s" % [r.slot, r.acked, hs.history.has(r.acked)])
		print("    WHOLE at seq %d tick %d: %s" % [hs.seq, hs.tick, why])
	if busy_until > 0.0 and absf(now - (busy_until - (BUSY_FOR - 1.0) * 1000.0)) < 1.0:
		var ch: Variant = hs._change_since(hs.seq - 10, {})
		if ch is Dictionary:
			var sizes := {}
			_sizes_of(ch, "", sizes, 0)
			var list: Array = []
			for k: String in sizes:
				list.append([sizes[k], k])
			list.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
			print(
				(
					"    BUSY delta 10 back: %d B raw, %d packed: %s"
					% [var_to_bytes(ch).size(), GameSnapshot.to_bytes(ch).size(), list.slice(0, 12)]
				)
			)


func _steer(net: NetPlay, copy: Game, me: Player) -> Game.Controls:
	var key := "%s/%d" % [net.get_instance_id(), copy.get_instance_id()]
	if not pilots.has(key):
		match mode:
			"county":
				pilots[key] = CountyBot.new()
			"bomb", "hostage", "tagteam":
				pilots[key] = TacticalBot.new(net.my_slot())
			_:
				pilots[key] = ModeBot.new()
	var bot = pilots[key]
	copy.focus(me)
	var c: Game.Controls = bot.steer(copy)
	if not (bot is TacticalBot):
		# The copy shows the aim a few ticks late: turn gently.
		c.turn *= .3
		c.look *= .3
	if bot.has_method("moved"):
		bot.moved(copy)
	copy.focus(copy.local_player)
	if mode == "county":
		var f = CountyMode.run(copy)
		if f != null and not f.offer.is_empty() and CountyCoop.leader(copy) == me:
			var i := CountyBot.pick(copy, f)
			var full: bool = String(f.offer[i]["type"]) == "weapon" and CountyBuild.open_slot(f) < 0
			c.buy = CountyCoop.encode(i, 0 if full else -1)
	return c


## A destruction event on the server's game marks the next BUSY_FOR seconds.
func _note_busy() -> void:
	var g := _server_game()
	if g == null or not wreckers.has(g):
		return
	var w: Wrecker = wreckers[g]
	if w.busy:
		w.busy = false
		busy_until = now + BUSY_FOR * 1000.0


## Bytes down to the players each second, filed by whether things broke in it.
func _bandwidth(busy: bool) -> void:
	var got := 0
	for net: NetPlay in nets:
		if net.session != null:
			got += net.session.received
	_down_busy = _down_busy or busy
	if now - _down_at >= 1000.0:
		if _down_at > 0.0:
			var kb := (got - _down_mark) / 1024.0 / maxf(1, nets.size())
			down_seconds["busy" if _down_busy else "quiet"].append(kb)
		_down_mark = got
		_down_at = now
		_down_busy = false


func _server_game() -> Game:
	if mode == "coop":
		return main.net.match_game() if main.net != null else null
	return lobby.match_game() if lobby != null else null


func _wait(what: Callable, most := 600) -> bool:
	for i in most:
		if what.call():
			return true
		_frame()
	return what.call()


# ------------------------------------------------------------ the soak


func _play() -> Dictionary:
	var minutes := float(opts["minutes"])
	if mode == "coop" and float(opts["coop_minutes"]) > 0.0:
		minutes = float(opts["coop_minutes"])
	var ticks := int(minutes * 60.0 / STEP)
	var wall := Time.get_ticks_msec()
	var late_at := ticks / 2 if int(opts["late"]) != 0 else -1
	var late_ok := true
	var late_note := ""
	var serve_us := 0
	var serve_n := 0
	var worst_serve := 0
	var stalls := 0
	var last_tick := -1
	var still := 0
	_sample("start")
	for t in ticks:
		var s0 := Time.get_ticks_usec()
		_frame(true)
		var spent := Time.get_ticks_usec() - s0
		serve_us += spent
		serve_n += 1
		worst_serve = maxi(worst_serve, spent)
		_drops()
		if t > 0 and t % int(30.0 / STEP) == 0:
			_sweep()
			_sample("%d s" % int(t * STEP))
		if t == late_at:
			var r := _late_join()
			late_ok = r[0]
			late_note = r[1]
		if _match_over():
			_restart()
		# The server's match must go on: its tick moves (a held world still
		# ticks), and a copy's newest snapshot with it.
		var hs := _host_sync()
		var at_tick: int = hs.tick if hs != null else -1
		still = still + 1 if at_tick == last_tick else 0
		last_tick = at_tick
		if still == int(5.0 / STEP):
			stalls += 1
			print(
				(
					"    STALLED at tick %d: %s"
					% [
						at_tick,
						nets.map(func(n: NetPlay) -> String: return "%s %s" % [n._my_name, n.phase])
					]
				)
			)
		if t % 4 == 0:
			# A frame of the engine's own now and then, as a game has every
			# frame: until then nothing it frees at a frame's end goes (the
			# sound's finished playbacks piled up: 2,000 objects a copy a
			# minute that a real client never holds).
			await process_frame
	_sweep()
	_sample("end")
	var wall_s := (Time.get_ticks_msec() - wall) / 1000.0
	_check(stalls == 0, "%s %.0f ms: the match never stood still (%d)" % [mode, lag, stalls])
	var kept_most := 0
	for net: NetPlay in nets:
		if net.client_sync != null:
			kept_most = maxi(kept_most, net.client_sync.snaps.size())
	_check(
		kept_most <= NetSync.Client.KEEP,
		"%s %.0f ms: a copy keeps %d snapshots at most (KEEP)" % [mode, lag, kept_most]
	)
	return _report(ticks * STEP, wall_s, late_ok, late_note)


func _host_sync() -> NetSync.Host:
	if mode == "coop":
		return main.net.host_sync if main.net != null else null
	return lobby.host_sync if lobby != null else null


## The lobby took everyone back (rounds, frag or time limit): play again.
func _match_over() -> bool:
	if mode == "coop":
		return false
	return lobby != null and lobby.phase == "lobby"


func _restart() -> void:
	for net: NetPlay in nets:
		_fold(net)
	for net: NetPlay in nets:
		net.set_meta("folded", true)
	_wait(func() -> bool: return nets.all(func(n: NetPlay) -> bool: return n.phase == "lobby"), 600)
	for net: NetPlay in nets.slice(1):
		net.ask({"ready": true})
	_wait(func() -> bool: return false, 60)
	print("    the match ended: again (%d)" % (matches + 1))
	_start()
	for net: NetPlay in nets:
		net.remove_meta("folded")


func _drops() -> void:
	for net: NetPlay in nets.duplicate():
		if net.phase == "closed" and not net.has_meta("leaving"):
			var t := _tally_of(net)
			var drops: Array = t["drops"]
			drops.append(net.reason)
			print("    %s DROPPED: %s" % [net._my_name, net.reason])
			_fold(net)
			nets.erase(net)


func _tally_of(net: NetPlay) -> Dictionary:
	for name: String in tallies:
		if name.to_lower() == str(net._my_name).to_lower():
			return tallies[name]
	return tallies.values()[0]


## A player's sync tallies added to their name's (before they go, or at the end).
func _fold(net: NetPlay) -> void:
	if net.has_meta("folded"):
		return
	var t := _tally_of(net)
	var cs := net.client_sync
	if cs != null:
		t["mismatches"] += cs.mismatches
		t["rebuilds"] += cs.rebuilds
		t["lost"] += cs.rebuilds_lost
		t["stale"] += cs.stale
		t["no_base"] += cs.no_base
		var lags: PackedFloat32Array = t["lag"]
		lags.append_array(cs.lag_samples)
		var logs: Array = t["logs"]
		logs.append_array(cs.mismatch_log)
		cs.mismatches = 0
		cs.rebuilds = 0
		cs.rebuilds_lost = 0
		cs.stale = 0
		cs.no_base = 0
		cs.lag_samples = PackedFloat32Array()
		cs.mismatch_log.clear()
	if net.session != null:
		t["down"] += net.session.received
		t["up"] += net.session.sent
		net.session.received = 0
		net.session.sent = 0
		_down_mark = 0
		for n: NetPlay in nets:
			if n.session != null and n != net:
				_down_mark += n.session.received


## The last player leaves and joins again into the broken world: its copy
## keeps with the server, and its looks show every fallen set piece lying
## in its pieces.
func _late_join() -> Array:
	var net: NetPlay = nets[-1]
	var name := str(net._my_name)
	var over_ws := net.session != null and net.session.transport == NetSession.Transport.WEBSOCKET
	if mode == "coop":
		over_ws = net.has_meta("ws")
	net.set_meta("leaving", true)
	_fold(net)
	net.leave("SOAK LEAVES")
	for i in 30:
		_frame()
	net.finish()
	nets.erase(net)
	for i in 120:
		_frame()
	var again := _join_coop(name, over_ws) if mode == "coop" else _join(name, over_ws)
	if again == null:
		return [false, "could not join again"]
	if mode != "coop":
		_wait(func() -> bool: return again.phase == "lobby" or again.phase == "match", 3000)
	var seated := _wait(func() -> bool: return again.client_ready(), 3000)
	if not seated:
		return [false, "never seated again (%s, %s)" % [again.phase, again.reason]]
	# Ten seconds on: its copy must keep (one put back on the way in at most).
	var before := again.client_sync.mismatches
	for i in int(10.0 / STEP):
		_frame(true)
	var parted := again.client_sync.mismatches - before
	var copy := again.match_game()
	var sg := _server_game()
	var looks := _ruins_shown(sg, copy)
	print(
		(
			"    late join: %s seated, parted %d in 10 s, fallen set pieces %s"
			% [name, parted, looks[1]]
		)
	)
	return [parted == 0 and looks[0], "parted %d, %s" % [parted, looks[1]]]


## Every set piece down on the server lies in its pieces on a copy (its
## wreckage's ruin, synced from the snapshot): [ok, what].
func _ruins_shown(sg: Game, copy: Game) -> Array:
	if sg == null or copy == null:
		return [false, "no game"]
	var sets = sg.features.get("set_pieces")
	if sets == null or sets.pieces.is_empty():
		return [true, "none on this map"]
	var wk = copy.features.get("wreckage")
	var ruin: SetPieceWreck = wk.ruin if wk != null else null
	var down := 0
	var shown := 0
	for i in sets.pieces.size():
		var stage: int = sets.pieces[i]["stage"]
		if stage < SetPiecesFeature.FALLING or str(sets.pieces[i]["kind"]) == "fuel":
			continue
		down += 1
		# (Pieces lying still are merged into a mesh a tile: `merged`.)
		if (
			ruin != null
			and ruin.ruins.has(i)
			and not (ruin.ruins[i].bits.is_empty() and ruin.ruins[i].merged.is_empty())
		):
			shown += 1
		elif int(opts["why"]) != 0:
			var cs = copy.features.get("set_pieces")
			print(
				(
					"    NOT SHOWN %d %s: server stage %s, copy stage %s, ruin %s, merged %s, out %s"
					% [
						i,
						sets.pieces[i]["kind"],
						stage,
						cs.pieces[i]["stage"],
						ruin != null and ruin.ruins.has(i),
						ruin.ruins[i].merged.size() if ruin != null and ruin.ruins.has(i) else -1,
						sets.pieces[i]["out"]
					]
				)
			)
	return [shown == down, "%d of %d down shown in pieces" % [shown, down]]


# ------------------------------------------------------------ growth


## The front end lets a game go when what it shows changes (its GamePool):
## here the copies of players that left and of matches gone are let go so.
func _sweep() -> void:
	var kept: Array = []
	for net: NetPlay in nets:
		var g := net.match_game()
		if g != null:
			kept.append(g)
	if mode == "coop" and main.game != null:
		kept.append(main.game)
	copies.sweep(kept)
	for g: Game in wreckers.keys():
		if not is_instance_valid(g) or not (g in kept or g == _server_game()):
			wreckers.erase(g)
	for key: String in pilots.keys():
		var alive := false
		for g: Game in kept:
			if key.ends_with("/%d" % g.get_instance_id()):
				alive = true
		if not alive:
			pilots.erase(key)


## Memory, objects and the sizes of every list in the server's game and the
## first player's copy, at `when`.
func _sample(when: String) -> void:
	var lists := {}
	var sg := _server_game()
	if sg != null:
		_lists("server", sg, lists)
	if not nets.is_empty() and nets[0].match_game() != null:
		_lists("copy", nets[0].match_game(), lists)
		var hw: Variant = nets[0].match_game().get("hands_watch")
		if hw is Object:
			_measure("copy:hands_watch", hw, lists)
		if nets[0].client_sync != null:
			_measure("client_sync", nets[0].client_sync, lists)
		if nets[0].has_meta("shots"):
			_measure("shown", nets[0].get_meta("shots"), lists)
		_measure("netplay", nets[0], lists)
	if lobby != null:
		_measure("lobby", lobby, lists)
		if lobby.host_sync != null:
			_measure("host_sync", lobby.host_sync, lists)
			if lobby.host_sync.track != null:
				_measure("track", lobby.host_sync.track, lists)
	var s := {
		"when": when,
		"at": now / 1000.0,
		"mb": OS.get_static_memory_usage() / 1048576.0,
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"lists": lists,
		"wrecked": _wrecked(sg),
	}
	var grew: Array = []
	if not samples.is_empty():
		var was: Dictionary = samples[-1]["lists"]
		for key: String in lists:
			var before: int = was.get(key, 0)
			var now_n: int = lists[key]
			if now_n - before >= 20:
				grew.append([now_n - before, "%s %d" % [key, now_n]])
		grew.sort_custom(func(x: Array, y: Array) -> bool: return x[0] > y[0])
	samples.append(s)
	print(
		(
			"    %s: %.0f MB, %d objects (%d resources, cuts kept %d), %d orphan nodes; %s%s"
			% [
				when,
				s["mb"],
				s["objects"],
				s["resources"],
				WreckCuts._cache.size(),
				s["orphans"],
				s["wrecked"],
				(
					""
					if grew.is_empty()
					else (
						"; grew " + str(grew.slice(0, 6).map(func(r: Array) -> String: return r[1]))
					)
				)
			]
		)
	)


func _lists(prefix: String, g: Game, out: Dictionary) -> void:
	_measure(prefix + ":game", g, out)
	for key: String in g.features:
		_measure(prefix + ":" + key, g.features[key], out)
	var wk = g.features.get("wreckage")
	if wk != null and wk.ruin != null:
		_measure(prefix + ":ruin", wk.ruin, out)
	if wk != null and wk.physics != null:
		_measure(prefix + ":wreck_physics", wk.physics, out)


func _measure(prefix: String, obj: Object, out: Dictionary) -> void:
	for prop: Dictionary in obj.get_property_list():
		if int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var v: Variant = obj.get(prop["name"])
		if v is Array or v is Dictionary or v is PackedFloat32Array or v is PackedFloat64Array:
			out[prefix + "." + str(prop["name"])] = v.size()


func _wrecked(g: Game) -> String:
	if g == null:
		return "no game"
	var broke := 0
	var b = g.features.get("breakables")
	if b != null:
		for p in b.pieces:
			broke += 1 if p.broken else 0
	var down := 0
	var sets = g.features.get("set_pieces")
	if sets != null:
		for st: Dictionary in sets.pieces:
			down += 1 if int(st["stage"]) >= SetPiecesFeature.FALLING else 0
	var corpses := 0
	for e: Enemy in g.enemies:
		corpses += 0 if e.alive else 1
	var fired := 0
	if wreckers.has(g):
		fired = wreckers[g].fired
	return (
		"%d blasts set off, %d broken, %d set pieces down, %d bodies, %d enemies"
		% [fired, broke, down, corpses, g.enemies.size()]
	)


## What grew over the run's second half: [objects share, the lists that grew most].
func _growth() -> Array:
	if samples.size() < 3:
		return [0.0, [], 0.0]
	var mid: Dictionary = samples[samples.size() / 2]
	var last: Dictionary = samples[-1]
	var share := float(last["objects"] - mid["objects"]) / maxf(1.0, float(mid["objects"]))
	var minutes := maxf(.1, float(last["at"] - mid["at"]) / 60.0)
	var mb_min := (float(last["mb"]) - float(mid["mb"])) / minutes
	var grew: Array = []
	var a: Dictionary = mid["lists"]
	var b: Dictionary = last["lists"]
	for key: String in b:
		var was: int = a.get(key, b[key])
		var is_now: int = b[key]
		if is_now - was >= 50 and is_now > was * 1.5:
			grew.append("%s %d -> %d" % [key, was, is_now])
	return [share, grew, mb_min]


# ------------------------------------------------------------ the report


static func _q(v: PackedFloat32Array, q: float) -> float:
	if v.is_empty():
		return 0.0
	var s := v.duplicate()
	s.sort()
	return s[clampi(int((s.size() - 1) * q), 0, s.size() - 1)]


func _report(seconds: float, wall_s: float, late_ok: bool, late_note: String) -> Dictionary:
	for net: NetPlay in nets:
		_fold(net)
	var row := {
		"mode": mode,
		"lag": lag,
		"minutes": seconds / 60.0,
		"wall": wall_s,
		"matches": matches,
	}
	var parted := 0
	var rebuilds := 0
	var lost := 0
	var drops: Array = []
	var trips := PackedFloat32Array()
	var down := 0
	var up := 0
	for name: String in tallies:
		var t: Dictionary = tallies[name]
		parted += t["mismatches"]
		rebuilds += t["rebuilds"]
		lost += t["lost"]
		drops.append_array(t["drops"])
		trips.append_array(t["lag"])
		down += t["down"]
		up += t["up"]
		var logs: Array = t["logs"]
		print(
			(
				"    %s (%s): parted %d, put back %d (inputs lost %d), stale %d, no base %d%s"
				% [
					name,
					t["via"],
					t["mismatches"],
					t["rebuilds"],
					t["lost"],
					t["stale"],
					t["no_base"],
					"" if logs.is_empty() else "; at " + "; ".join(logs.slice(0, 4))
				]
			)
		)
	var n := maxf(1.0, tallies.size())
	row["parted"] = parted
	row["rebuilds"] = rebuilds
	row["lost"] = lost
	row["trip"] = _q(trips, .5)
	row["trip95"] = _q(trips, .95)
	row["down"] = down / 1024.0 / seconds / n
	row["up"] = up / 1024.0 / seconds / n
	row["down_busy95"] = _q(down_seconds["busy"], .95)
	row["down_quiet95"] = _q(down_seconds["quiet"], .95)
	for k: String in ["quiet", "busy", "check", "putback"]:
		var v: PackedFloat32Array = frame_us[k]
		row[k + "_n"] = v.size()
		row[k + "_50"] = _q(v, .5) / 1000.0
		row[k + "_99"] = _q(v, .99) / 1000.0
		row[k + "_max"] = _q(v, 1.0) / 1000.0
	print(
		(
			(
				"    a client frame's parts, median / p99: packets %.2f / %.2f ms,"
				+ " the copy played %.2f / %.2f, led and shown %.2f / %.2f"
			)
			% [
				_q(parts["poll"], .5) / 1000.0,
				_q(parts["poll"], .99) / 1000.0,
				_q(parts["play"], .5) / 1000.0,
				_q(parts["play"], .99) / 1000.0,
				_q(parts["shown"], .5) / 1000.0,
				_q(parts["shown"], .99) / 1000.0
			]
		)
	)
	print(
		(
			"    a client frame checking its copy (once a second), median / worst: %.2f / %.2f ms"
			% [row["check_50"], row["check_max"]]
		)
	)
	if not parts["host"].is_empty():
		print(
			(
				(
					"    the host's own frame (its game, the same scene as one player's),"
					+ " median / p99: %.2f / %.2f ms"
				)
				% [_q(parts["host"], .5) / 1000.0, _q(parts["host"], .99) / 1000.0]
			)
		)
	var hs: NetSync.Host = null
	if mode == "coop":
		hs = main.net.host_sync if main.net != null else null
	elif lobby != null:
		hs = lobby.host_sync
	if hs != null:
		var full := PackedFloat32Array(Array(hs.sizes_full))
		var deltas := PackedFloat32Array(Array(hs.sizes_delta))
		row["wholes"] = full.size()
		row["delta50"] = _q(deltas, .5)
		row["delta95"] = _q(deltas, .95)
		print(
			(
				(
					"    the server sent %d whole snapshots (median %.0f B) and %d deltas"
					+ " (median %.0f, p95 %.0f, worst %.0f B)"
				)
				% [
					full.size(),
					_q(full, .5),
					deltas.size(),
					row["delta50"],
					row["delta95"],
					_q(deltas, 1.0)
				]
			)
		)
	var g := _growth()
	row["obj_grow"] = g[0]
	row["mb0"] = samples[0]["mb"] if not samples.is_empty() else 0.0
	row["mb1"] = samples[-1]["mb"] if not samples.is_empty() else 0.0
	row["wrecked"] = samples[-1]["wrecked"] if not samples.is_empty() else ""
	print("    %s" % row["wrecked"])
	if not g[1].is_empty():
		print("    grew in the second half: %s" % ", ".join(g[1].slice(0, 8)))
	# The checks.
	# In the party modes the server lays a leaver out of play and seats them
	# again between ticks (Modes.went_away, join_late): every other copy is
	# put back on a snapshot for each, once.
	var allowed := 0
	if int(opts["late"]) != 0 and mode in ["coop", "deathmatch", "team_deathmatch"]:
		allowed = 2 * (tallies.size() - 1)
	_check(drops.is_empty(), "%s %.0f ms: nobody dropped %s" % [mode, lag, drops])
	_check(
		parted <= allowed,
		(
			(
				"%s %.0f ms: every copy keeps with the server (%d partings, %d inputs lost,"
				+ " %d put back on purpose)"
			)
			% [mode, lag, parted, lost, forced_putbacks]
		)
	)
	if int(opts["late"]) != 0:
		_check(
			late_ok, "%s %.0f ms: the late joiner's copy and looks (%s)" % [mode, lag, late_note]
		)
	if mode == "coop" and main.game != null:
		var kept := _saved_again(main.game)
		_check(kept == "", "coop: a save of the broken chapter reads back as it was%s" % kept)
	# Pools fill for the first minute or so: growth is judged on runs of two
	# or more, over their second half: the objects (a share; the horde of a
	# County Run grows a little all along) and the memory (MB a minute).
	# Before pass 12's round 2 the soak never let the engine run a frame, so
	# the sound's finished playbacks were never let go: +40% objects and
	# +100 MB a minute over a two-minute County Run's second half.
	if seconds >= 120.0:
		_check(
			float(g[0]) <= float(opts["grow"]) and float(g[2]) <= float(opts["mb_min"]),
			(
				"%s %.0f ms: objects and memory flat in the second half (%+.1f%%, %+.1f MB a minute)"
				% [mode, lag, float(g[0]) * 100.0, float(g[2])]
			)
		)
	return row


func _sizes_of(v: Variant, path: String, out: Dictionary, depth: int) -> void:
	if v is Dictionary and depth < 4 and not v.has("@T"):
		for k: Variant in v:
			var key := str(k)
			if depth == 1 and path == "/enemies":
				key = "*"
			_sizes_of(v[k], path + "/" + key, out, depth + 1)
		return
	out[path] = int(out.get(path, 0)) + var_to_bytes(v).size()


## The host's game saved (as THE PARTY SAVE is, SessionStore) and read back:
## what broke, came down and burned is the same ("" when it is).
func _saved_again(g: Game) -> String:
	var path := OS.get_cache_dir().path_join("net-soak-all-party.json")
	if not SessionStore.save(g, path):
		return " (no save written)"
	var back: Game = SessionStore.read(path, Callable(main, "make_game"), false)
	if back == null:
		return " (it did not read back)"
	var out := ""
	for id: String in ["breakables", "wall_breaks", "set_pieces", "fire"]:
		var a = g.features.get(id)
		var b = back.features.get(id)
		if a == null or b == null:
			continue
		# (A save is text: its whole numbers read back as floats, a last bit
		# may differ; both sides go through JSON first.)
		var w := GameSnapshot.first_difference(
			JSON.parse_string(JSON.stringify(SnapCodec.plain(a.save()))),
			JSON.parse_string(JSON.stringify(SnapCodec.plain(b.save()))),
			"",
			1e-9
		)
		if w != "":
			out += " (%s: %s)" % [id, w]
	back.dispose()
	return out


func _table() -> void:
	print(
		(
			"| mode | lag | min | parted (lost) | trip p50/p95 | down KB/s (p95 quiet/busy) | up |"
			+ " client frame quiet p50/p99/max | busy p50/p99/max | put back p50/max | MB |"
			+ " objects 2nd half |"
		)
	)
	print("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
	for r: Dictionary in rows:
		print(
			(
				(
					"| %s | %.0f | %.1f | %d (%d) | %.0f/%.0f | %.1f (%.1f/%.1f) | %.1f |"
					+ " %.2f/%.2f/%.1f ms | %.2f/%.2f/%.1f ms | %.1f/%.1f ms (%d) | %.0f->%.0f |"
					+ " %+.1f%% |"
				)
				% [
					r["mode"],
					r["lag"],
					r["minutes"],
					r["parted"],
					r["lost"],
					r["trip"],
					r["trip95"],
					r["down"],
					r["down_quiet95"],
					r["down_busy95"],
					r["up"],
					r["quiet_50"],
					r["quiet_99"],
					r["quiet_max"],
					r["busy_50"],
					r["busy_99"],
					r["busy_max"],
					r["putback_50"],
					r["putback_max"],
					r["putback_n"],
					r["mb0"],
					r["mb1"],
					r["obj_grow"] * 100.0
				]
			)
		)


# ------------------------------------------------------------ campaign co-op


## CAMPAIGN CO-OP: the real front end hosts Hickston through the party line
## of a lobby server (as net_party_check.gd), P2 straight to the host, the
## last through the line over WebSocket; the host's player one is a bot too.
func _open_coop() -> bool:
	var base := NetPorts.pick("net_soak_all coop", [0], [3000])
	for k in 20:
		var config := {
			"bind": "127.0.0.1",
			"relay": {},
			"lobbies": [{"port": base + k, "ws_port": base + k + 3000, "lobby_name": "SPARE"}]
		}
		server = LobbyServer.new(config, {"difficulty": 1})
		if not server.rooms.is_empty() and server.rooms[0].net.session.also != null:
			port = base + k
			ws_port = base + k + 3000
			break
		server.free()
		server = null
	if server == null:
		_check(false, "coop: a lobby server runs the party line")
		return false
	root.add_child(server)
	server.set_process(false)
	Engine.max_fps = 0  # (a lobby server caps the frames when it starts)
	_lag(server.rooms[0].net.session)
	RelayLink.server = {"host": "127.0.0.1", "port": port}
	RelayLink.test_lan = PackedStringArray(["127.0.0.1"])
	main.net_form = {
		"name": "Host",
		"lobby_name": "SOAK CO-OP",
		"password": "",
		"port": "0",
		"router": false,
	}
	for k in 20:
		main.net_form["port"] = str(NetPorts.pick("net_soak_all host %d" % k))
		main.net_open_lobby()
		if main.net != null:
			break
	var host: NetPlay = main.net
	if host == null:
		_check(false, "coop: the front end hosts")
		return false
	_wait(func() -> bool: return host.party_line() != null and host.party_line().state == "open")
	var line := host.party_line()
	if line == null or line.state != "open":
		_check(false, "coop: the lobby has a party line code")
		return false
	host.set_setting("mode", Modes.COOP)
	host.set_setting("map", "hickston")
	host.set_meta("code", line.code)
	var people := int(opts["people"])
	for i in range(1, people):
		var over_ws := int(opts["ws"]) != 0 and i == people - 1
		var net := _join_coop("P%d" % (i + 1), over_ws)
		if net == null or not _wait(func() -> bool: return net.phase == "lobby", 4000):
			_check(false, "coop: P%d joins by the code" % (i + 1))
			return false
	for net: NetPlay in nets:
		net.ask({"ready": true})
	_wait(
		func() -> bool:
			return host.players.all(func(p: Dictionary) -> bool: return bool(p.get("ready", false))),
		1200
	)
	var why := host.start_match()
	var started := _wait(
		func() -> bool:
			return (
				host.match_game() != null
				and nets.all(func(n: NetPlay) -> bool: return n.client_ready())
			),
		4000
	)
	_check(why == "" and started, "coop: the chapter starts on every copy (%s)" % why)
	if started:
		matches = 1
		_dress(host.match_game())
		host_bot = ModeBot.new()
	return started


func _join_coop(name: String, over_ws: bool) -> NetPlay:
	var keep := RelayLink.server
	if over_ws:
		RelayLink.server = {"url": "ws://127.0.0.1:%d" % ws_port}
	var net := NetPlay.join_lobby(str(main.net.get_meta("code")), name, "")
	RelayLink.server = keep
	if net == null:
		return null
	if over_ws:
		net.set_meta("ws", true)
	net.make_match = func(info: Dictionary) -> Game:
		var made: Game = main.net_match_game(info)
		if made != null:
			made.net_role = "copy"
			# The players' copies are the soak's, not the front end's: its
			# own sweep at a frame's end (coop's host) would let them go.
			main.games._games.erase(made)
			copies.track(made)
		return _dress(made)
	_lag(net.session)
	nets.append(net)
	if not tallies.has(name):
		tallies[name] = {
			"mismatches": 0,
			"rebuilds": 0,
			"lost": 0,
			"stale": 0,
			"no_base": 0,
			"lag": PackedFloat32Array(),
			"logs": [],
			"drops": [],
			"down": 0,
			"up": 0,
			"via": "line, ws" if over_ws else "code",
		}
	return net


## The host's front end: its lobby's changes, a tick of its match by
## main.advance with player one steered by a bot.
func _host_frame() -> void:
	var net: NetPlay = main.net
	if net == null:
		return
	if net.session != null and net.session.lag_ms != lag:
		_lag(net.session)
	net.poll(now)
	net.take_news()
	for change: Dictionary in net.take_changes():
		if change.has("started"):
			main.net_begin_match()
			_dress(main.game)
		elif change.has("lobby"):
			main.net_to_lobby()
	if net.phase == "match" and main.game != null:
		_dress(main.game)
		var g: Game = main.game
		var mine := Game.Controls.new()
		if host_bot != null and g.players[0].health > 0:
			g.focus(g.players[0])
			mine = host_bot.steer(g)
			if host_bot.has_method("moved"):
				host_bot.moved(g)
			g.focus(g.local_player)
		var h0 := Time.get_ticks_usec()
		main.advance(STEP, mine)
		parts["host"].append(Time.get_ticks_usec() - h0)
