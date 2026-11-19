## What a player feels online, measured: an always-open lobby server
## (src/net/lobby_server.gd, as on the VPS) plays a full 5v5 with bots, and
## `people` clients join it over 127.0.0.1 ENet with test latency, jitter and
## loss on both sides (NetSession), each played by a TacticalBot steering from
## its own copy as a person would from their screen. For each link it reports:
##
## - INPUT: how many ticks the drawn player trails the server's path with the
##   client prediction (net_predict.gd) and without it, and the input's round
##   trip to the server's confirmation.
## - RUBBER BAND: each frame, where the drawn player is against where last
##   frame's prediction plus this frame's input would have put it (a jump the
##   player sees when the server's word comes in); count a minute, p95, worst.
## - OTHERS: frames where the copy (everyone else) stood still or jumped more
##   than two ticks, copies put back on a snapshot, mismatches.
## - HITS: each shot a client fired with a hitscan or pellet gun, its centre
##   line tested where the client's screen showed everyone (looked) and where
##   the server judged it (with its rewind; and without, for comparison):
##   shots that looked like a hit on someone and were judged a miss.
## - OWN SHOTS: button to the flash and bang as shown at the press
##   (net_shot_predict.gd) and as the copy played it (the old way), and how
##   often a shown shot or hit was withdrawn (`noshots`: that prediction off).
## - BANDWIDTH down and up per client, snapshot sizes, and the server's cost
##   per tick (the game, the bots, the snapshots) as a share of one core.
##
##   godot --headless --path godot --script res://tools/net_lag.gd
##       [-- lags=50,120,250] [jitter=0.2] [loss=0.02] [seconds=50]
##       [map=grainyard] [mode=bomb] [people=4] [quick] [old] [oldserver]
##       [nofeel]
##
## jitter is a share of the latency (or `jitter_ms=`). quick: one 120 ms link
## for 30 s with limits (tools/check_all.gd). Prints NET LAG OK.
extends SceneTree

const NetPorts := preload("res://tools/net_ports.gd")

const STEP := NetSync.STEP
const Loopback := preload("res://tools/net_loopback.gd")
## A rubber band jump smaller than this is not counted (cells).
const JUMP_FROM := .02
## The quick part's limits at 120 ms + 24 jitter + 2% loss.
const QUICK_LIMITS := {
	"jump_p95": .25,
	"ghost_share": .12,
	"stall_share": .08,
	"up_lost": .1,
	"down_kbs": 110.0,
	"shot_withdrawn": .1,
	"shot_late": .1,
}

var failures: Array = []
var main: Control
var now := 0.0
var opts := {
	"lags": "50,120,250",
	"jitter": .2,
	"jitter_ms": -1.0,
	"loss": .02,
	"seconds": 50.0,
	"map": "grainyard",
	"mode": "bomb",
	"people": 4,
}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var quick := false
	for arg: String in OS.get_cmdline_user_args():
		if arg == "quick":
			quick = true
			continue
		if arg == "old":
			# Every fix of this pass off: the netcode as v3.1.0 had it.
			NetSync.Host.trim_echo = false
			NetSync.Host.carry = false
			NetSync.Host.per_input_view = false
			Modes.flows_in_rounds = true
			TacticalNav.worlds_kept = 1
			NetSync.Client.predict_from_echo = false
			NetSync.Client.adaptive_playout = false
			NetPredict.Smoother.enabled = false
			NetSession.throttle = true
			NetShotPredict.enabled = false
			_old_server()
			# Pass 12's (tools/net_feel.gd measures those frame by frame).
			NetSync.Client.smooth_clock = false
			NetPlay.county_by_clock = false
			NetPredict.mates_ahead = false
			NetPredict.holds_aware = false
			NetOwnShots.enabled = false
			NetSync.Client.wait_rows = false
			NetPredict.between = false
			NetBlend.enabled = false
			continue
		if arg == "oldserver":
			# Only pass 12's server side off (the 3.9.0 server).
			_old_server()
			continue
		if arg.begins_with("snaps="):
			# Snapshots every this many ticks (NetPlay.snap_every).
			NetPlay.snap_every = int(arg.substr(6))
			continue
		if arg == "nofeel":
			# Only pass 12's client side off (net_feel.gd's `old`).
			NetSync.Client.smooth_clock = false
			NetPlay.county_by_clock = false
			NetPredict.mates_ahead = false
			NetPredict.holds_aware = false
			NetOwnShots.enabled = false
			NetSync.Client.wait_rows = false
			NetPredict.between = false
			NetBlend.enabled = false
			continue
		if arg == "noshots":
			# Only the shots' prediction off (net_shot_predict.gd).
			NetShotPredict.enabled = false
			continue
		var parts := arg.split("=")
		if parts.size() == 2:
			var key := parts[0]
			opts[key] = parts[1] if key in ["lags", "map", "mode"] else float(parts[1])
	if quick:
		opts["lags"] = "120"
		opts["seconds"] = 30.0
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var tally := CrashLog.tally()
	var rows: Array = []
	for lag_text: String in str(opts["lags"]).split(","):
		var lag := float(lag_text)
		var jitter: float = opts["jitter_ms"] if opts["jitter_ms"] >= 0.0 else lag * opts["jitter"]
		var r := measure(lag, jitter, float(opts["loss"]))
		if not r.is_empty():
			rows.append(r)
	tally.stop()
	print("")
	_table(rows)
	_check(
		tally.errors == 0,
		(
			"no script or engine errors"
			+ ("" if tally.errors == 0 else " (%d: %s)" % [tally.errors, tally.first_errors[0]])
		)
	)
	if quick and not rows.is_empty() and not _within(rows[0]):
		# A real-time measure on a shared machine (CI's runners): a slow moment
		# can tip one 30 s run over a limit. One more run; a real regression
		# misses on both, and the second run's numbers are the ones checked.
		print("")
		print("  over a limit on the first run: once more")
		var again := measure(
			120.0,
			opts["jitter_ms"] if opts["jitter_ms"] >= 0.0 else 120.0 * opts["jitter"],
			float(opts["loss"])
		)
		if not again.is_empty():
			_table([again])
			rows[0] = again
	if quick and not rows.is_empty():
		var r: Dictionary = rows[0]
		_check(r["mismatches"] == 0, "the copies keep with the server (%d)" % r["mismatches"])
		_check(
			r["jump_p95"] <= QUICK_LIMITS["jump_p95"],
			"rubber band p95 %.3f <= %.2f cells" % [r["jump_p95"], QUICK_LIMITS["jump_p95"]]
		)
		_check(
			r["ghost_share"] <= QUICK_LIMITS["ghost_share"],
			(
				"shots that looked like hits but missed %.0f%% <= %.0f%%"
				% [r["ghost_share"] * 100.0, QUICK_LIMITS["ghost_share"] * 100.0]
			)
		)
		_check(
			r["stall_share"] <= QUICK_LIMITS["stall_share"],
			(
				"frames the others stood still %.1f%% <= %.0f%%"
				% [r["stall_share"] * 100.0, QUICK_LIMITS["stall_share"] * 100.0]
			)
		)
		_check(
			r["up_lost"] <= QUICK_LIMITS["up_lost"],
			"inputs lost past the link's own loss %.1f%%" % [r["up_lost"] * 100.0]
		)
		_check(
			(
				r["shots_shown"] > 0
				and r["shot_withdrawn"] <= QUICK_LIMITS["shot_withdrawn"]
				and r["shot_late"] <= QUICK_LIMITS["shot_late"]
			),
			(
				"own shots shown at the press (%d), %.0f%% withdrawn, %.0f%% not foreseen"
				% [r["shots_shown"], r["shot_withdrawn"] * 100.0, r["shot_late"] * 100.0]
			)
		)
		_check(
			r["down_kbs"] <= QUICK_LIMITS["down_kbs"],
			"down %.1f KB/s a client <= %.0f" % [r["down_kbs"], QUICK_LIMITS["down_kbs"]]
		)
	print("")
	print("NET LAG OK" if failures.is_empty() else "NET LAG FAILED (%d)" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


## Pass 12's server side off: the old loop, the echoed rows unpacked, a
## snapshot over the MTU sent reliable. The test's loss hits reliable
## packets either way (NetSession.resend_lost), as a real network's does.
static func _old_server() -> void:
	LobbyServer.paced = false
	NetWire.pack_rows = false
	NetSync.Host.split_big = false


## Whether a quick run's numbers are all within QUICK_LIMITS.
static func _within(r: Dictionary) -> bool:
	for key: String in QUICK_LIMITS:
		var most: float = QUICK_LIMITS[key]
		var got: float = r[key]
		if got > most:
			return false
	var parted: int = r["mismatches"]
	return parted == 0


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


## One link: a server, `people` clients, `seconds` of the match.
func measure(lag: float, jitter: float, loss: float) -> Dictionary:
	var server: LobbyServer = null
	var port := NetPorts.pick("net_lag")
	for k in 20:
		var lobby := {
			"port": port + k,
			"lobby_name": "LAG",
			"mode": str(opts["mode"]),
			"map": str(opts["map"]),
			"team_size": 2 if str(opts["mode"]) == "tagteam" else 5,
			"rounds": 7,
		}
		server = LobbyServer.new(
			{"bind": "127.0.0.1", "lobbies": [lobby], "snap_every": NetPlay.snap_every},
			{"difficulty": 1}
		)
		if not server.rooms.is_empty():
			port += k
			break
		server.free()
		server = null
	if server == null:
		_check(false, "the server opens a lobby")
		return {}
	root.add_child(server)
	server.set_process(false)
	var lobby_net: NetPlay = server.rooms[0].net
	var nets: Array = []
	# A member, not a local: the frame lambda below would advance its own
	# copy of a local, and the server's schedule needs the clock to move.
	now = 0.0
	var frame := func() -> void:
		now += STEP * 1000.0
		server.frame(now, STEP)
		for net: NetPlay in nets:
			net.poll(now)
			if net.phase == "match":
				net.client_input(Game.Controls.new())
				net.client_play(1)
		OS.delay_msec(1)
	var people := int(opts["people"])
	for i in people:
		var net := NetPlay.join_lobby("127.0.0.1:%d" % port, "P%d" % i, "")
		net.make_match = func(info: Dictionary) -> Game: return main.net_match_game(info)
		nets.append(net)
		for w in 400:
			if net.phase == "lobby":
				break
			frame.call()
	var admin: NetPlay = nets[0]
	for net: NetPlay in nets:
		if net != admin:
			net.ask({"ready": true})
	for w in 120:
		frame.call()
	var why := admin.start_match()
	for w in 600:
		if nets.all(func(n: NetPlay) -> bool: return n.client_ready()):
			break
		frame.call()
	if why != "" or not nets.all(func(n: NetPlay) -> bool: return n.client_ready()):
		_check(false, "the match starts with everyone (%s)" % why)
		_close(server, nets)
		return {}
	for s: NetSession in (
		[lobby_net.session] + nets.map(func(n: NetPlay) -> NetSession: return n.session)
	):
		s.lag_ms = lag
		s.jitter_ms = jitter
		s.loss = loss
	var host: NetSync.Host = lobby_net.host_sync
	var sg: Game = host.game
	# The server's judgement of every client shot (by slot: [input, looked target...]).
	var judged: Array = []
	var by_slot := {}
	for net: NetPlay in nets:
		by_slot[net.my_slot()] = net
	sg.events.shot_fired.connect(
		func(gun: int) -> void:
			var how: Dictionary = Weapons.FIRING[gun]
			var kind := str(how.get("fire", ""))
			var shooter: Player = sg.player
			if not by_slot.has(shooter.slot) or kind not in ["hitscan", "pellets"]:
				return
			var remote: NetSync.Remote = null
			for r: NetSync.Remote in host.remotes.values():
				if r.slot == shooter.slot:
					remote = r
			if remote == null:
				return
			var with_rewind := _aimed_at(sg, shooter)
			# The same shot with everyone where the server stands them now.
			var row: PackedFloat32Array = (
				sg.place_log[-1] if not sg.place_log.is_empty() else PackedFloat32Array()
			)
			var kept := []
			for q: Player in sg.players:
				kept.append([q.x, q.y, q.crouched])
				if q != shooter and q.slot * 3 + 2 < row.size():
					q.x = row[q.slot * 3]
					q.y = row[q.slot * 3 + 1]
					q.crouched = row[q.slot * 3 + 2] > .5
			var without := _aimed_at(sg, shooter)
			for q: Player in sg.players:
				q.x = kept[q.slot][0]
				q.y = kept[q.slot][1]
				q.crouched = kept[q.slot][2]
			judged.append([shooter.slot, remote.played, with_rewind, without])
	)
	var bots := {}
	var stats := {}
	for net: NetPlay in nets:
		stats[net] = {
			"looked": {},
			"prev_round": -1,
			"jumps": PackedFloat32Array(),
			"gaps": PackedFloat32Array(),
			"smoother": NetPredict.Smoother.new(),
			"frames": 0,
			"stalls": 0,
			"skips": 0,
			"tick_was": -1,
			"server_at": [],
			"copy_at": [],
			"drawn_at": [],
			"shots": NetShotPredict.new(),
			# Everyone else as that screen draws them (net_blend.gd).
			"blend": NetBlend.new(),
		}
	var down0: int = lobby_net.session.sent
	var heard0: int = lobby_net.session.received_packets
	var said0 := 0
	for net: NetPlay in nets:
		said0 += net.session.sent_packets - net.session.dropped
	var down_packets0: int = lobby_net.session.sent_packets
	var up0 := 0
	for net: NetPlay in nets:
		up0 += net.session.sent
	var room: LobbyServer.Room = server.rooms[0]
	room.ticks = 0
	room.tick_us = 0
	room.worst_us = 0
	room.bot_us = 0
	var tick_us0 := host.tick_us
	var capture_us0 := host.capture_us
	var delta_us0 := host.delta_us
	var full0 := host.sizes_full.size()
	var delta0 := host.sizes_delta.size()
	var packet0 := host.sizes_packet.size()
	var split0 := host.split_count
	var resent0: int = lobby_net.session.resent
	var frames := int(float(opts["seconds"]) / STEP)
	var wall := Time.get_ticks_msec()
	var serve_us := 0
	for f in frames:
		now += STEP * 1000.0
		var t0 := Time.get_ticks_usec()
		server.frame(now, STEP)
		serve_us += Time.get_ticks_usec() - t0
		for net: NetPlay in nets:
			net.poll(now)
			if net.phase != "match":
				continue
			var c := Game.Controls.new()
			var copy: Game = net.match_game()
			var me: Player = copy.players[net.my_slot()] if net.client_ready() else null
			if me != null and me.health > 0:
				if not bots.has(net):
					bots[net] = TacticalBot.new(net.my_slot())
				# A person aims at what the screen shows: their own player led
				# by the prediction (the copy alone is a round trip behind
				# their own turns, and a bot steering it never got on target),
				# everyone else between the copy's ticks as drawn.
				var led := NetPredict.lead(copy, me, net.client_sync.unplayed_inputs())
				var blend: NetBlend = stats[net]["blend"]
				blend.begin(copy, net.client_sync.game_tick, net.client_sync.view_at, me)
				copy.focus(me)
				c = bots[net].steer(copy)
				if c.fire and String(Modes.feature(copy).phase) == "live":
					# The shot as that screen shows it: this input's own step
					# and turn first (the host plays the body before the hands).
					NetPredict.step(copy, me, c, STEP)
					stats[net]["looked"][net.client_sync.input_seq] = _aimed_at(copy, me)
				copy.focus(copy.local_player)
				blend.end()
				NetPredict.restore(me, led)
			net.client_input(c)
			var shots: NetShotPredict = stats[net]["shots"]
			shots.now_ms = now
			net.client_play(1)
			if me != null and me.health > 0 and net.client_ready():
				# The frame as main.gd draws it: walked on, our shots shown
				# (net_shot_predict.gd), put back.
				var cs: NetSync.Client = net.client_sync
				var walked := NetPredict.lead(copy, me, cs.unplayed_inputs())
				var shown := shots.frame(copy, me, cs)
				shots.restore(copy, me, shown)
				NetPredict.restore(me, walked)
			if me != null:
				_frame_stats(net, stats[net], sg, c)
				if bots.has(net):
					copy.focus(me)
					bots[net].moved(copy)
					copy.focus(copy.local_player)
		OS.delay_msec(1)
	var wall_s := (Time.get_ticks_msec() - wall) / 1000.0
	var seconds := frames * STEP
	# The report.
	var out := {"lag": lag, "jitter": jitter, "loss": loss}
	var jumps := PackedFloat32Array()
	var gaps := PackedFloat32Array()
	var counted := 0
	var stalls := 0
	var skips := 0
	var mismatches := 0
	var rebuilds := 0
	var lost := 0
	var lags := PackedFloat32Array()
	var lead_k := []
	var copy_k := []
	for net: NetPlay in nets:
		var st: Dictionary = stats[net]
		jumps.append_array(st["jumps"])
		gaps.append_array(st["gaps"])
		counted += st["frames"]
		stalls += st["stalls"]
		skips += st["skips"]
		var cs: NetSync.Client = net.client_sync
		if cs != null:
			mismatches += cs.mismatches
			rebuilds += cs.rebuilds
			lost += cs.rebuilds_lost
			lags.append_array(cs.lag_samples)
		var shift: Array = Loopback._lead_error(st["server_at"], st["copy_at"], st["drawn_at"])
		copy_k.append(shift[0])
		lead_k.append(shift[2])
	var big := PackedFloat32Array()
	for j in jumps:
		if j >= JUMP_FROM:
			big.append(j)
	big.sort()
	var raw := PackedFloat32Array()
	for j in gaps:
		if j >= JUMP_FROM:
			raw.append(j)
	raw.sort()
	out["gaps_min"] = raw.size() / maxf(1.0, counted * STEP / 60.0)
	out["gap_p95"] = _pct(raw, .95)
	lags.sort()
	out["jumps_min"] = big.size() / maxf(1.0, counted * STEP / 60.0)
	out["jump_p95"] = _pct(big, .95)
	out["jump_max"] = big[-1] if not big.is_empty() else 0.0
	out["jump_mean"] = _mean(big)
	out["stall_share"] = stalls / maxf(1.0, counted)
	out["skip_share"] = skips / maxf(1.0, counted)
	out["mismatches"] = mismatches
	out["rebuilds"] = rebuilds
	out["lost"] = lost
	var starved := 0
	var skipped := 0
	for r: NetSync.Remote in host.remotes.values():
		starved += r.starved
		skipped += r.skipped
	out["starved"] = starved / maxf(1.0, seconds) / people
	out["skipped"] = skipped / maxf(1.0, seconds) / people
	out["confirm_ms"] = _pct(lags, .5)
	# Our own shots: button to the flash and bang (net_shot_predict.gd).
	var show_ms := PackedFloat32Array()
	var copy_ms := PackedFloat32Array()
	var tally := {}
	for net: NetPlay in nets:
		var sp: NetShotPredict = stats[net]["shots"]
		show_ms.append_array(sp.show_ms)
		copy_ms.append_array(sp.copy_ms)
		for key: String in sp.stats:
			tally[key] = int(tally.get(key, 0)) + int(sp.stats[key])
	show_ms.sort()
	copy_ms.sort()
	out["shot_show_ms"] = _pct(show_ms, .5)
	out["shot_show_p95"] = _pct(show_ms, .95)
	out["shot_copy_ms"] = _pct(copy_ms, .5)
	out["shot_copy_p95"] = _pct(copy_ms, .95)
	var shown_shots: int = tally.get("shots", 0)
	var copy_shots: int = int(tally.get("confirmed", 0)) + int(tally.get("late", 0))
	out["own_shots"] = copy_shots
	out["shots_shown"] = shown_shots
	out["shot_withdrawn"] = int(tally.get("withdrawn", 0)) / maxf(1.0, shown_shots)
	out["shot_late"] = int(tally.get("late", 0)) / maxf(1.0, copy_shots)
	out["hit_withdrawn"] = int(tally.get("hits_withdrawn", 0)) / maxf(1.0, tally.get("hits", 0))
	out["hits_shown"] = tally.get("hits", 0)
	out["drawn_k"] = _mean(PackedFloat32Array(lead_k))
	out["copy_k"] = _mean(PackedFloat32Array(copy_k))
	# Shots.
	var looked_hits := 0
	var ghosts := 0
	var lucky := 0
	var ghosts_no_rewind := 0
	var repeats := 0
	var shots := 0
	for j: Array in judged:
		var net: NetPlay = by_slot[j[0]]
		var seq: int = j[1]
		shots += 1
		if seq < 0 or not stats[net]["looked"].has(seq):
			repeats += 1
			continue
		var looked: int = stats[net]["looked"][seq]
		if looked >= 0:
			looked_hits += 1
			if j[2] != looked:
				ghosts += 1
			if j[3] != looked:
				ghosts_no_rewind += 1
		elif j[2] >= 0:
			lucky += 1
	out["shots"] = shots
	out["looked_hits"] = looked_hits
	out["ghost_share"] = ghosts / maxf(1.0, looked_hits)
	out["ghost_no_rewind"] = ghosts_no_rewind / maxf(1.0, looked_hits)
	out["lucky"] = lucky
	out["repeats"] = repeats
	# Bandwidth and the server.
	var down: int = lobby_net.session.sent - down0
	var down_packets: int = lobby_net.session.sent_packets - down_packets0
	var up := 0
	for net: NetPlay in nets:
		up += net.session.sent
	up -= up0
	var said := -said0
	for net: NetPlay in nets:
		said += net.session.sent_packets - net.session.dropped
	out["up_lost"] = 1.0 - (lobby_net.session.received_packets - heard0) / maxf(1.0, said)
	out["down_kbs"] = (down + down_packets * NetSession.HEADER_BYTES) / seconds / 1024.0 / people
	out["up_kbs"] = up / seconds / 1024.0 / people
	var deltas := host.sizes_delta.slice(delta0)
	deltas.sort()
	out["delta_med"] = deltas[deltas.size() / 2] if not deltas.is_empty() else 0
	out["delta_p95"] = deltas[int(deltas.size() * .95)] if not deltas.is_empty() else 0
	out["fulls"] = host.sizes_full.size() - full0
	var packets := host.sizes_packet.slice(packet0)
	packets.sort()
	var over := 0
	for size in packets:
		if size > NetWire.PART_MOST:
			over += 1
	out["packet_med"] = packets[packets.size() / 2] if not packets.is_empty() else 0
	out["packet_p95"] = packets[int(packets.size() * .95)] if not packets.is_empty() else 0
	out["over_mtu"] = over / maxf(1.0, packets.size())
	out["split"] = (host.split_count - split0) / maxf(1.0, packets.size())
	out["resent"] = lobby_net.session.resent - resent0
	var ticks := maxi(1, room.ticks)
	out["tick_ms"] = room.tick_us / 1000.0 / ticks
	out["worst_ms"] = room.worst_us / 1000.0
	out["game_ms"] = (host.tick_us - tick_us0) / 1000.0 / ticks
	out["bot_ms"] = room.bot_us / 1000.0 / ticks
	out["snap_ms"] = (host.capture_us - capture_us0 + host.delta_us - delta_us0) / 1000.0 / ticks
	out["look_ms"] = (host.capture_us - capture_us0) / 1000.0 / ticks
	out["serve_ms"] = serve_us / 1000.0 / ticks
	out["core"] = out["serve_ms"] * 60.0 / 1000.0
	var g_st = Modes.feature(sg)
	print(
		(
			"  %d ms +%d jitter, %d%% loss: %.0f s of %s (%s) in %.0f s, %d people, round %d"
			% [
				lag,
				jitter,
				roundi(loss * 100.0),
				seconds,
				opts["mode"],
				opts["map"],
				wall_s,
				people,
				int(g_st.round_no)
			]
		)
	)
	_close(server, nets)
	return out


## Where the client draws itself, how far that jumped, how the copy moved,
## and the shot it sees, for one frame.
func _frame_stats(net: NetPlay, st: Dictionary, sg: Game, _c: Game.Controls) -> void:
	var cs: NetSync.Client = net.client_sync
	var copy: Game = cs.game
	var me: Player = copy.players[cs.slot]
	var mode_st = Modes.feature(copy)
	var round_key := int(mode_st.round_no) * 10 + (1 if String(mode_st.phase) == "live" else 0)
	# The others: ticks the copy moved this frame.
	if st["tick_was"] >= 0 and String(mode_st.phase) == "live":
		st["frames"] += 1
		var moved: int = cs.game_tick - int(st["tick_was"])
		if moved == 0:
			st["stalls"] += 1
		elif moved > 2:
			st["skips"] += 1
	st["tick_was"] = cs.game_tick
	var smoother: NetPredict.Smoother = st["smoother"]
	if me.health <= 0 or st["prev_round"] != round_key:
		smoother.reset()
		st["prev_round"] = round_key
		if me.health <= 0:
			return
	var copy_at := Vector2(me.x, me.y)
	var kept := smoother.draw(copy, me, cs, STEP)
	var drawn := Vector2(me.x, me.y)
	if smoother.last_gap > 0.0 or smoother.last_seen > 0.0:
		st["jumps"].append(smoother.last_seen)
		st["gaps"].append(smoother.last_gap)
	NetPredict.restore(me, kept)
	if String(mode_st.phase) == "live":
		var on_server: Player = sg.players[cs.slot]
		st["server_at"].append(Vector2(on_server.x, on_server.y))
		st["copy_at"].append(copy_at)
		st["drawn_at"].append(drawn)


## The player a centre-line shot from `p` (acting) would strike (-1: none).
static func _aimed_at(game: Game, p: Player) -> int:
	var was: Player = game.player
	if was != p:
		game.focus(p)
	var aim := p.view_angle()
	var slope := (p.pitch + p.sway) / View.base_focal
	var line: Array = Modes.player_in_line(game, cos(aim), sin(aim), slope, 0.0, 40.0)
	if was != p:
		game.focus(was)
	if line.is_empty():
		return -1
	var q: Player = line[0]
	return q.slot


func _close(server: LobbyServer, nets: Array) -> void:
	for net: NetPlay in nets:
		net.leave()
		net.finish()
	for room in server.rooms:
		room.net.finish()
	server.queue_free()


static func _pct(sorted: PackedFloat32Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[mini(sorted.size() - 1, int(sorted.size() * p))]


static func _mean(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var sum := 0.0
	for v in values:
		sum += v
	return sum / values.size()


func _table(rows: Array) -> void:
	if rows.is_empty():
		return
	var line := func(label: String, fmt: String, key: String, scale := 1.0) -> void:
		var cells := PackedStringArray()
		for r: Dictionary in rows:
			cells.append((fmt % (float(r[key]) * scale)).lpad(12))
		print("  %-44s%s" % [label, "".join(cells)])
	var head := PackedStringArray()
	for r: Dictionary in rows:
		head.append(("%d+%d ms" % [r["lag"], r["jitter"]]).lpad(12))
	print(
		"  %-44s%s" % ["LINK (%d%% loss)" % roundi(float(rows[0]["loss"]) * 100.0), "".join(head)]
	)
	line.call("input: drawn trails the server by (ticks)", "%.1f", "drawn_k", -1.0)
	line.call("input: without prediction (ticks)", "%.1f", "copy_k", -1.0)
	line.call("input: round trip to confirmation (ms)", "%.0f", "confirm_ms")
	line.call("prediction: corrections a minute", "%.1f", "gaps_min")
	line.call("prediction: p95 correction (cells)", "%.3f", "gap_p95")
	line.call("  host: late inputs held a second", "%.1f", "starved")
	line.call("  host: inputs merged a second", "%.1f", "skipped")
	line.call("rubber band seen: jumps a minute", "%.1f", "jumps_min")
	line.call("rubber band seen: mean jump (cells)", "%.3f", "jump_mean")
	line.call("rubber band seen: p95 jump (cells)", "%.3f", "jump_p95")
	line.call("rubber band seen: worst jump (cells)", "%.2f", "jump_max")
	line.call("others: frames standing still (%)", "%.1f", "stall_share", 100.0)
	line.call("others: frames jumping >2 ticks (%)", "%.1f", "skip_share", 100.0)
	line.call("copies put back on a snapshot", "%.0f", "rebuilds")
	line.call("  of them for inputs lost", "%.0f", "lost")
	line.call("  mismatches", "%.0f", "mismatches")
	line.call("own shots: fired (copy)", "%.0f", "own_shots")
	line.call("own shots: shown at the press", "%.0f", "shots_shown")
	line.call("own shots: button to flash, shown (ms)", "%.0f", "shot_show_ms")
	line.call("  p95 (ms)", "%.0f", "shot_show_p95")
	line.call("own shots: button to the copy's (ms)", "%.0f", "shot_copy_ms")
	line.call("  p95 (ms)", "%.0f", "shot_copy_p95")
	line.call("own shots: shown, then withdrawn (%)", "%.1f", "shot_withdrawn", 100.0)
	line.call("own shots: fired, not foreseen (%)", "%.1f", "shot_late", 100.0)
	line.call("own hits: shown on someone", "%.0f", "hits_shown")
	line.call("own hits: withdrawn by the host (%)", "%.1f", "hit_withdrawn", 100.0)
	line.call("hits: client shots judged", "%.0f", "shots")
	line.call("hits: looked like a hit", "%.0f", "looked_hits")
	line.call("hits: looked a hit, judged a miss (%)", "%.1f", "ghost_share", 100.0)
	line.call("  the same without the rewind (%)", "%.1f", "ghost_no_rewind", 100.0)
	line.call("hits: looked a miss, judged a hit", "%.0f", "lucky")
	line.call("hits: fired on a held input (late)", "%.0f", "repeats")
	line.call("down per client (KB/s, headers)", "%.1f", "down_kbs")
	line.call("up per client (KB/s)", "%.1f", "up_kbs")
	line.call("up packets lost past the test's loss (%)", "%.1f", "up_lost", 100.0)
	line.call("delta median (bytes)", "%.0f", "delta_med")
	line.call("delta p95 (bytes)", "%.0f", "delta_p95")
	line.call("whole snapshots sent", "%.0f", "fulls")
	line.call("snapshot packet median (bytes)", "%.0f", "packet_med")
	line.call("snapshot packet p95 (bytes)", "%.0f", "packet_p95")
	line.call("snapshots over the MTU (%)", "%.1f", "over_mtu", 100.0)
	line.call("  of them sent in parts, unreliable (%)", "%.1f", "split", 100.0)
	line.call("reliable packets lost and resent (down)", "%.0f", "resent")
	line.call("server: match tick (ms)", "%.2f", "tick_ms")
	line.call("  of it the game (ms)", "%.2f", "game_ms")
	line.call("  of it snapshots (ms)", "%.2f", "snap_ms")
	line.call("    of which finding changes (ms)", "%.2f", "look_ms")
	line.call("  of it the bots (ms)", "%.2f", "bot_ms")
	line.call("server: all its work a tick (ms)", "%.2f", "serve_ms")
	line.call("server: worst tick (ms)", "%.1f", "worst_ms")
	line.call("server: share of one core (%)", "%.1f", "core", 100.0)
