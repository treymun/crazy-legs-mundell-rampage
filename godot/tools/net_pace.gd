## How evenly a lobby server's snapshots reach its players (pass 12): the
## server's side of "jittery". Probes join an always-open lobby on the real
## clock and note when each new snapshot comes (polled about every half a
## millisecond, so on one machine the times are the server's, not a
## network's): the gaps between them, snapshots bunched together or missing,
## and how far their arrivals wander against their ticks (what a client's
## playout depth must cover: NetSync.Client.playout_depth), with each
## snapshot packet's size against the MTU and the bandwidth down and up.
##
##   godot --headless --path godot --script res://tools/net_pace.gd
##       [-- server=<address:port>] [people=3] [watch=1] [start_when=4]
##       [seconds=60] [lag=ms] [jitter=ms] [loss=share]
##
## With `server` (a lobby server of this build in another process, say one
## pinned to a single core: docs/dev/multiplayer.md "Pacing") it joins
## `watch` light probes (they only listen and acknowledge, so their own work
## never delays what they time) and `people` players (TacticalBots steering
## from their copies, loading the server as people do); the lobby's admin
## starts the match once `start_when` are in. A second process can join the
## server's other lobby the same way (start_when=0 there: it only joins).
## `lag`, `jitter`, `loss` are a made-up network on what the probes send
## (the server's own side is its config's "test_link"; "old": true there
## runs the 3.9.0 server on this build).
##
## Without `server` it is the check (check_all): a lobby server of this
## build in this process, on its own paced loop (LobbyServer._rest), with
## two lobbies each playing a full match with bots, an extra load each tick
## standing for the slower core, and light probes; it fails when the
## snapshots bunch or the gaps' p99 is over CHECK_P99. Its first part needs
## no clock: a server on a made-up clock is stalled and must catch the time
## up with one snapshot a room, never a burst, and let go of a stall past
## LobbyServer.SLIP_MS. `old` runs the old loop (LobbyServer.paced off).
## Its made-up-clock part also holds the second round: a whole snapshot
## carries its rows, a split one's first part gives its rows, the host's input
## buffer fills before playing on. Prints NET PACE OK.
extends SceneTree

const NetPorts := preload("res://tools/net_ports.gd")
const STEP := NetSync.STEP
const STEP_US := 16667
## The check's limits: the snapshots' gap p99 (ms; the beat is 33.3) at the
## server and at a probe, and the arrivals' wander (p95 over the quickest).
const CHECK_P99 := 45.0
const CHECK_PROBE_P99 := 50.0
const CHECK_WANDER := 20.0
## The check's stand-in for a slower core: busy time added to each tick (us).
const CHECK_LOAD_US := 1500

var failures: Array = []
var main: Control
var opts := {
	"server": "",
	"people": 3,
	"watch": 1,
	"start_when": 4,
	"seconds": 60.0,
	"load_us": float(CHECK_LOAD_US),
	"lag": 0.0,
	"jitter": 0.0,
	"loss": 0.0,
}
var old := false
var server: LobbyServer = null
var probes: Array[Probe] = []
var _served_at := 0


## One player joined to the lobby, and what it timed.
class Probe:
	extends RefCounted
	var net: NetPlay
	var name := ""
	var light := true
	var pilot: TacticalBot = null
	var pilot_game: Game = null
	## Each new snapshot: when it came (us) and its tick.
	var at := PackedInt64Array()
	var ticks := PackedInt32Array()
	## Polls that brought more than one new snapshot (bunched).
	var doubles := 0
	## Each snapshot packet's size (bytes, a poll that brought only it).
	var sizes := PackedFloat32Array()
	var down0 := 0
	var up0 := 0
	var t0 := 0
	var stalls := 0
	var frames := 0
	var tick_was := -1
	var depths := PackedFloat32Array()


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "old":
			old = true
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
	LobbyServer.paced = not old
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var tally := CrashLog.tally()
	if str(opts["server"]) != "":
		_measure_far()
	else:
		_catch_up_check()
		_paced_check()
	tally.stop()
	_check(
		tally.errors == 0,
		(
			"no script or engine errors"
			+ ("" if tally.errors == 0 else " (%d: %s)" % [tally.errors, tally.first_errors[0]])
		)
	)
	_close_all()
	print("")
	print("NET PACE OK" if failures.is_empty() else "NET PACE FAILED (%d)" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _close_all() -> void:
	for p in probes:
		if p.net != null:
			p.net.leave("DONE")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300:
		for p in probes:
			if p.net != null:
				p.net.poll(Time.get_ticks_usec() / 1000.0)
		if server != null:
			server.frame(Time.get_ticks_usec() / 1000.0, 0.0)
		OS.delay_msec(5)
	for p in probes:
		if p.net != null:
			p.net.finish()
	probes.clear()
	if server != null:
		for room in server.rooms:
			room.net.finish()
		server.free()
		server = null


# ------------------------------------------------------------------ probes


func _join(where: String, name: String, light: bool) -> Probe:
	var net := NetPlay.join_lobby(where, name, "")
	if net == null:
		return null
	net.make_match = func(info: Dictionary) -> Game: return main.net_match_game(info)
	net.session.lag_ms = opts["lag"]
	net.session.jitter_ms = opts["jitter"]
	net.session.loss = opts["loss"]
	var p := Probe.new()
	p.net = net
	p.name = name
	p.light = light
	probes.append(p)
	return p


## Polls a probe at `now_us` and notes the snapshots that came.
func _listen(p: Probe, now_us: int) -> void:
	var net := p.net
	if net.session == null:
		return
	var cs := net.client_sync
	var seq0 := cs.latest if cs != null else -1
	var bytes0: int = net.session.received
	var packets0: int = net.session.received_packets
	net.poll(now_us / 1000.0)
	cs = net.client_sync
	if cs == null or net.session == null or cs.latest <= seq0 or seq0 < 0:
		return
	p.at.append(now_us)
	p.ticks.append(cs.latest_tick)
	var packets: int = net.session.received_packets - packets0
	if packets > 1 and cs.latest - seq0 > 1:
		p.doubles += 1
	elif packets == 1:
		p.sizes.append(net.session.received - bytes0)


## A probe's frame (a tick's time): its input (the acknowledgement) and, for
## a player, its bot's steering from its copy and the copy played on.
func _frame(p: Probe) -> void:
	var net := p.net
	if net.session == null or net.phase != "match":
		return
	var c := Game.Controls.new()
	if not p.light and net.client_ready():
		var copy := net.match_game()
		var slot := net.my_slot()
		if p.pilot_game != copy:
			p.pilot_game = copy
			p.pilot = TacticalBot.new(slot)
		if slot >= 0 and slot < copy.players.size() and copy.players[slot].health > 0:
			copy.focus(copy.players[slot])
			c = p.pilot.steer(copy)
			copy.focus(copy.local_player)
	net.client_input(c)
	if not p.light:
		net.client_play(1)
		var cs := net.client_sync
		if cs != null and cs.game_tick >= 0:
			if p.tick_was >= 0:
				p.frames += 1
				if cs.game_tick == p.tick_was:
					p.stalls += 1
			p.tick_was = cs.game_tick
			p.depths.append(cs._depth)
		if p.pilot != null and net.client_ready():
			var copy := net.match_game()
			copy.focus(copy.players[net.my_slot()])
			p.pilot.moved(copy)
			copy.focus(copy.local_player)


## Runs every probe for `seconds` on the real clock: each polled about
## every half millisecond, its frame every tick's time. `serve`: this
## process's own server gets its paced turn too.
func _run_for(seconds: float, serve := false) -> void:
	var until := Time.get_ticks_usec() + int(seconds * 1000000.0)
	var next_frame := Time.get_ticks_usec()
	while Time.get_ticks_usec() < until:
		var now := Time.get_ticks_usec()
		if serve and server != null:
			server.frame(now / 1000.0, (now - _served_at) / 1000000.0 if _served_at > 0 else 0.0)
			_served_at = now
		for p in probes:
			_listen(p, Time.get_ticks_usec())
		now = Time.get_ticks_usec()
		if now >= next_frame:
			next_frame += STEP_US
			if now - next_frame > STEP_US * 4:
				next_frame = now + STEP_US
			for p in probes:
				_frame(p)
		OS.delay_usec(400)


## Waits (polling, frames, and our server if any) until `what` holds.
func _wait(what: Callable, seconds: float, serve := false) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		if what.call():
			return true
		_run_for(.05, serve)
	return what.call()


func _reset_stats() -> void:
	for p in probes:
		p.at.clear()
		p.ticks.clear()
		p.sizes.clear()
		p.doubles = 0
		p.stalls = 0
		p.frames = 0
		p.depths.clear()
		if p.net.session != null:
			p.down0 = p.net.session.received
			p.up0 = p.net.session.sent
		p.t0 = Time.get_ticks_usec()


## A probe's numbers: gaps (ms: median, p95, p99, worst), bunched and
## missing snapshots, the arrivals' wander (ms over the quickest: p95,
## p99), packet sizes, bandwidth.
static func stats(p: Probe) -> Dictionary:
	var gaps := PackedFloat32Array()
	var wander := PackedFloat32Array()
	var beat := 0.0
	for i in range(1, p.at.size()):
		gaps.append((p.at[i] - p.at[i - 1]) / 1000.0)
	for i in p.at.size():
		wander.append((p.at[i] - p.ticks[i] * STEP * 1000000.0) / 1000.0)
	gaps.sort()
	wander.sort()
	if p.ticks.size() > 1:
		beat = (p.ticks[-1] - p.ticks[0]) * STEP * 1000.0 / (p.ticks.size() - 1)
	var quickest := wander[0] if not wander.is_empty() else 0.0
	var bunched := p.doubles
	var holes := 0
	for g in gaps:
		if g < beat * .5:
			bunched += 1
		elif g > beat * 1.5:
			holes += 1
	var sizes := p.sizes.duplicate()
	sizes.sort()
	var over := 0
	for s in sizes:
		if s > NetSession.MTU_SAFE:
			over += 1
	var secs := maxf(.001, (Time.get_ticks_usec() - p.t0) / 1000000.0)
	var depths := p.depths.duplicate()
	depths.sort()
	return {
		"snaps": p.at.size(),
		"beat": beat,
		"gap_med": _pct(gaps, .5),
		"gap_p95": _pct(gaps, .95),
		"gap_p99": _pct(gaps, .99),
		"gap_max": gaps[-1] if not gaps.is_empty() else 0.0,
		"bunched": bunched,
		"holes": holes,
		"wander_p95": _pct(wander, .95) - quickest,
		"wander_p99": _pct(wander, .99) - quickest,
		"size_med": _pct(sizes, .5),
		"size_p95": _pct(sizes, .95),
		"size_max": sizes[-1] if not sizes.is_empty() else 0.0,
		"over_mtu": over / maxf(1.0, sizes.size()),
		"down_kbs": (p.net.session.received - p.down0) / 1024.0 / secs if p.net.session else 0.0,
		"up_kbs": (p.net.session.sent - p.up0) / 1024.0 / secs if p.net.session else 0.0,
		"stall_share": p.stalls / maxf(1.0, p.frames),
		"depth_med": _pct(depths, .5),
	}


static func _pct(sorted: PackedFloat32Array, q: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[mini(sorted.size() - 1, int(sorted.size() * q))]


func _print_probe(p: Probe) -> void:
	var s := stats(p)
	print(
		(
			(
				"  %-8s %s: %d snaps, beat %.1f ms; gaps %.1f / %.1f / %.1f / %.1f ms"
				+ " (med/p95/p99/worst), %d bunched, %d missing; wander p95 %.1f p99 %.1f ms;"
				+ " packets %d / %d / %d B (%.0f%% over %d); down %.1f up %.1f KB/s%s"
			)
			% [
				p.name,
				"listens" if p.light else "plays",
				s["snaps"],
				s["beat"],
				s["gap_med"],
				s["gap_p95"],
				s["gap_p99"],
				s["gap_max"],
				s["bunched"],
				s["holes"],
				s["wander_p95"],
				s["wander_p99"],
				s["size_med"],
				s["size_p95"],
				s["size_max"],
				s["over_mtu"] * 100.0,
				NetSession.MTU_SAFE,
				s["down_kbs"],
				s["up_kbs"],
				(
					""
					if p.light
					else (
						"; others still %.1f%% of frames, depth %d ticks"
						% [s["stall_share"] * 100.0, s["depth_med"]]
					)
				),
			]
		)
	)


# ------------------------------------------------------------------ a far server


func _measure_far() -> void:
	var where := str(opts["server"])
	var watch := int(opts["watch"])
	var people := int(opts["people"])
	var start_when := int(opts["start_when"])
	for i in watch + people:
		var light := i < watch
		var p := _join(where, ("EAR%d" if light else "PLAY%d") % (i + 1), light)
		if p == null:
			_check(false, "a probe starts to join %s" % where)
			return
		var in_lobby := _wait(
			func() -> bool: return p.net.phase in ["lobby", "match", "closed"], 10.0
		)
		if not in_lobby or p.net.phase == "closed":
			_check(false, "%s gets in (%s)" % [p.name, p.net.reason])
			return
		if p.net.phase == "lobby":
			p.net.ask({"ready": true})
	var admin: Probe = null
	for p in probes:
		if p.net.is_admin():
			admin = p
	if admin != null and start_when > 0:
		_wait(func() -> bool: return admin.net.players.size() >= start_when, 120.0)
		_run_for(1.0)
		var why := admin.net.start_match()
		print("PACE: %s starts the match (%s)" % [admin.name, why if why != "" else "ok"])
	var started := _wait(
		func() -> bool: return probes.all(func(q: Probe) -> bool: return q.net.phase == "match"),
		60.0
	)
	_check(started, "every probe is in the match")
	if not started:
		return
	_run_for(3.0)
	_reset_stats()
	_run_for(float(opts["seconds"]))
	print("PACE: %.0f s against %s%s" % [opts["seconds"], where, " (old)" if old else ""])
	for p in probes:
		_print_probe(p)


# ------------------------------------------------------------------ the check


## A server on a made-up clock: a match on, then one long frame (a stall):
## the ticks it owes are played at once (MOST_STEPS a frame), only the last
## sends snapshots, and a stall past SLIP_MS lets the time go.
func _catch_up_check() -> void:
	var port := NetPorts.pick("net_pace_clock")
	server = LobbyServer.new(
		{
			"bind": "127.0.0.1",
			"lobbies": [{"port": port, "lobby_name": "PACE", "mode": "tagteam", "map": "pumpngo"}]
		},
		{"difficulty": 1}
	)
	if server.rooms.is_empty():
		_check(false, "a lobby opens on a made-up clock")
		return
	root.add_child(server)
	server.set_process(false)
	var now := [0.0]
	var tick_frame := func(ms: float) -> void:
		now[0] += ms
		server.frame(now[0], ms / 1000.0)
		for p in probes:
			p.net.poll(now[0])
			if p.net.phase == "match":
				p.net.client_input(Game.Controls.new())
		OS.delay_msec(1)
	var p := _join("127.0.0.1:%d" % port, "CLOCK", true)
	for i in 600:
		if p.net.phase == "lobby":
			break
		tick_frame.call(STEP * 1000.0)
	var why := p.net.start_match()
	for i in 600:
		if p.net.phase == "match" and p.net.client_sync.latest >= 0:
			break
		tick_frame.call(STEP * 1000.0)
	var room := server.rooms[0]
	var host := room.net.host_sync
	if host == null or p.net.phase != "match":
		_check(false, "a match starts on a made-up clock (%s)" % why)
		_close_all()
		return
	for i in 60:
		tick_frame.call(STEP * 1000.0)
	var tick0 := host.tick
	var seq0 := host.seq
	for i in 120:
		tick_frame.call(STEP * 1000.0)
	_check(
		host.tick - tick0 == 120 and host.seq - seq0 == 60,
		(
			"a tick a frame on the made-up clock, a snapshot every other (%d ticks, %d snapshots)"
			% [host.tick - tick0, host.seq - seq0]
		)
	)
	# A 100 ms stall: 6 ticks owed, played at once, one snapshot.
	tick0 = host.tick
	seq0 = host.seq
	tick_frame.call(100.0 + STEP * 1000.0 * .5)
	var played := host.tick - tick0
	var sent := host.seq - seq0
	if LobbyServer.paced:
		_check(
			played == 6 and sent == 1,
			"a 100 ms stall: its 6 ticks caught up at once, one snapshot (%d, %d)" % [played, sent]
		)
	else:
		print("  (old) a 100 ms stall: %d ticks, %d snapshots" % [played, sent])
	# Back on the beat: the schedule kept its time.
	tick0 = host.tick
	for i in 60:
		tick_frame.call(STEP * 1000.0)
	_check(host.tick - tick0 == 60, "then a tick a frame again (%d)" % (host.tick - tick0))
	# A 300 ms stall: 18 owed, MOST_STEPS now and the rest at the next frame.
	tick0 = host.tick
	seq0 = host.seq
	tick_frame.call(300.0)
	var first := host.tick - tick0
	var first_sent := host.seq - seq0
	tick_frame.call(.5)
	tick_frame.call(.5)
	var both := host.tick - tick0
	if LobbyServer.paced:
		_check(
			first == LobbyServer.MOST_STEPS and first_sent == 1 and both == 18,
			(
				"a 300 ms stall: %d ticks then the rest at once (%d in all), one snapshot a frame"
				% [first, both]
			)
		)
		# A 2 s stall is let go: the schedule starts again from now.
		var slips0 := server.slips
		tick0 = host.tick
		tick_frame.call(2000.0)
		_check(
			server.slips == slips0 + 1 and host.tick - tick0 <= 2,
			"a 2 s stall is let go, not raced after (%d ticks)" % (host.tick - tick0)
		)
		_rows_check(host)
	_close_all()


## A session that keeps what is sent instead of sending it.
class Keeper:
	extends NetSession
	var kept: Array = []

	func send(to: int, channel: int, bytes: PackedByteArray) -> void:
		kept.append([to, channel, bytes])

	func flush() -> void:
		pass


## Pass 12's second round: a whole snapshot to a client that fell behind
## carries its rows; a split snapshot's first part alone gives its rows; a
## person's inputs wait in the host's buffer after running dry.
func _rows_check(host: NetSync.Host) -> void:
	var r: NetSync.Remote = host.remotes.values()[0]
	var real := host.session
	var keeper := Keeper.new()
	host.session = keeper
	r.acked = -1
	r.full_at = -1000000
	for i in host.snap_every:
		host.play({})
	host.session = real
	var whole := {}
	for k: Array in keeper.kept:
		var bytes: PackedByteArray = k[2]
		if bytes[0] == NetWire.SNAP:
			whole = NetWire.read_snap(bytes)
	var rows: Array = whole.get("echo", [])
	var first: int = whole.get("echo_first", 0)
	_check(
		(
			whole.get("base", 0) == -1
			and rows.size() >= NetSync.Host.ECHO_TICKS
			and first + rows.size() - 1 == int(whole.get("tick", -2))
		),
		(
			"a whole snapshot to a client that fell behind carries its rows (%d, to tick %d)"
			% [rows.size(), first + rows.size() - 1]
		)
	)
	# A split snapshot: only its first part comes.
	var row := NetWire.tick_row({0: NetWire.pack_controls(Game.Controls.new())})
	var blob := PackedByteArray()
	blob.resize(3000)
	for i in blob.size():
		blob[i] = (i * 7919) % 251
	var big := NetWire.snap(900, 880, 2000, -1, [1990, [row, row, row]], blob)
	var parts := NetWire.split(big, 900)
	var cs := NetSync.Client.new(NetSession.new(), func(_id: String) -> Game: return null)
	cs.take([[1, parts[0]]])
	_check(
		parts.size() >= 3 and cs.echo.has(1990) and cs.echo.has(1992) and cs.latest < 0,
		"a split snapshot's first part alone gives its rows (%d parts)" % parts.size()
	)
	cs.take([[1, parts[2]], [1, parts[1]]])
	_check(cs.parts_joined == 1, "and its parts in any order make it whole")
	# The input buffer: dry, it fills to the buffer before playing on.
	var q := NetSync.Remote.new()
	q.slot = 0
	q.buffer = 2
	q.refill = true
	q.next = 10
	var one := NetWire.pack_controls(Game.Controls.new())
	q.waiting = {10: one, 11: one}
	host._next_input(q)
	var held := q.played
	q.waiting[12] = one
	host._next_input(q)
	_check(
		held == -1 and q.played == 10 and q.waiting.size() == 2,
		"the host's input buffer fills to %d after running dry, then plays evenly" % q.buffer
	)


## The paced loop on the real clock, loaded: two lobbies, each a match of
## bots with a light probe in it, CHECK_LOAD_US of extra work each tick.
func _paced_check() -> void:
	var port := NetPorts.pick("net_pace", [0, 1])
	server = (
		LobbyServer
		. new(
			{
				"bind": "127.0.0.1",
				"lobbies":
				[
					{
						"port": port,
						"lobby_name": "PACE 1",
						"mode": "bomb",
						"map": "grainyard",
						"team_size": 5
					},
					{"port": port + 1, "lobby_name": "PACE 2", "mode": "tagteam", "map": "pumpngo"},
				]
			},
			{"difficulty": 1}
		)
	)
	if server.rooms.size() < 2:
		_check(false, "two lobbies open")
		return
	root.add_child(server)
	server.set_process(false)
	var load_us := int(opts["load_us"])
	for room in server.rooms:
		# The slower core: busy time beside each tick.
		room.net.make_match = func(info: Dictionary) -> Game:
			var g: Game = server._make(info)
			if g != null and load_us > 0:
				g.events.ticked.connect(
					func(_dt: float) -> void:
						var t := Time.get_ticks_usec()
						while Time.get_ticks_usec() - t < load_us:
							pass
				)
			return g
	var ears: Array[Probe] = []
	for k in 2:
		var e := _join("127.0.0.1:%d" % (port + k), "EAR%d" % (k + 1), true)
		ears.append(e)
		_wait(func() -> bool: return e.net.phase == "lobby", 10.0, true)
	for e in ears:
		var why := e.net.start_match()
		if why != "":
			print("  start: %s" % why)
	var on := _wait(
		func() -> bool:
			return ears.all(
				func(e: Probe) -> bool:
					return e.net.phase == "match" and e.net.client_sync.latest >= 0
			),
		20.0,
		true
	)
	_check(on, "both lobbies play a match")
	if not on:
		_close_all()
		return
	_run_for(2.0, true)
	for room in server.rooms:
		room.gaps.clear()
		room.costs.clear()
	_reset_stats()
	var seconds := minf(float(opts["seconds"]), 12.0)
	_run_for(seconds, true)
	print(
		"  %.0f s, two matches, %d us more a tick%s:" % [seconds, load_us, " (old)" if old else ""]
	)
	for room in server.rooms:
		var pc := LobbyServer.pacing(room)
		print(
			(
				(
					"  server %s: snapshots %.1f ms apart (p99 %.1f, worst %.1f), %d bunched;"
					+ " tick %.2f ms (p99 %.2f, worst %.1f)"
				)
				% [
					room.net.settings["lobby_name"],
					pc["gap_med"],
					pc["gap_p99"],
					pc["gap_max"],
					pc["bunched"],
					pc["cost_med"],
					pc["cost_p99"],
					pc["cost_max"]
				]
			)
		)
		if not old:
			_check(
				pc["bunched"] == 0 and pc["gap_p99"] <= CHECK_P99,
				(
					"%s: no snapshots bunched (%d), gap p99 %.1f <= %.0f ms"
					% [room.net.settings["lobby_name"], pc["bunched"], pc["gap_p99"], CHECK_P99]
				)
			)
	for e in ears:
		_print_probe(e)
		var s := stats(e)
		if not old:
			_check(
				s["bunched"] == 0 and s["gap_p99"] <= CHECK_PROBE_P99,
				(
					"%s hears them evenly: %d bunched, gap p99 %.1f <= %.0f ms"
					% [e.name, s["bunched"], s["gap_p99"], CHECK_PROBE_P99]
				)
			)
			_check(
				s["wander_p95"] <= CHECK_WANDER and s["over_mtu"] == 0.0,
				(
					"%s: arrivals wander p95 %.1f <= %.0f ms, no snapshot over the MTU (%.0f%%)"
					% [e.name, s["wander_p95"], CHECK_WANDER, s["over_mtu"] * 100.0]
				)
			)
	_close_all()
