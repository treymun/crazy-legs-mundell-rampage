## A host and a client on this machine over localhost (src/net/): one process,
## two real network peers (ENet by default, WebSocket with `websocket`) and
## two games. The host runs the authoritative game with its own bot as player
## one; the client joins as player two, sends its bot's inputs (steered from
## its own copy of the game) every tick, and rebuilds the host's snapshot
## deltas. Checks that every snapshot the client rebuilt is the host's, bit
## for bit (GameSnapshot.same), and that the client's copy, stepped with the
## inputs the host played and rebuilt from a snapshot now and then, matches
## the host's snapshots; reports bandwidth and sizes. Time is the game's own
## (it runs as fast as it can); the latency, jitter and loss are added to what
## each side sends, on that clock.
##
##   godot --headless --path godot --script res://tools/net_loopback.gd
##       [-- seconds=180] [level=hickston] [lag=50] [jitter=15] [loss=0.05]
##       [snap_hz=20] [websocket] [quick]
##
## quick: the part tools/check_fixes.gd runs (run()). Prints NET LOOPBACK OK.
extends SceneTree

const MultiBots := preload("res://tools/multi_bots.gd")
const Pilot := preload("res://tools/bot_pilot.gd")
const STEP := 1.0 / 60.0
## The quick part: ENet with latency and loss, then a short WebSocket run.
const QUICK := [
	{"seconds": 6.0, "lag": 40.0, "jitter": 10.0, "loss": .05},
	{"seconds": 2.0, "lag": 0.0, "jitter": 0.0, "loss": 0.0, "websocket": true},
]

var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var args := OS.get_cmdline_user_args()
	var opts := {"seconds": 180.0, "lag": 50.0, "jitter": 15.0, "loss": .05, "snap_hz": 20}
	for arg: String in args:
		var parts := arg.split("=")
		if parts.size() == 2:
			opts[parts[0]] = parts[1] if parts[0] == "level" else float(parts[1])
	opts["websocket"] = args.has("websocket")
	var check := func(ok: bool, text: String) -> void:
		print("  ok   " if ok else "  FAIL ", text)
		if not ok:
			failures.append(text)
	# Any error at all (one that cut a run short too) fails the tool.
	var errors := CrashLog.tally()
	if args.has("quick"):
		run(main, check)
	else:
		loopback(main, check, opts)
	errors.stop()
	if errors.errors > 0:
		check.call(false, "%d error(s), the first: %s" % [errors.errors, errors.first_errors[0]])
	print("")
	print(
		"NET LOOPBACK OK" if failures.is_empty() else "NET LOOPBACK FAILED (%d)" % failures.size()
	)
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


## The quick part (tools/check_fixes.gd).
static func run(main, check: Callable) -> void:
	for opts: Dictionary in QUICK:
		loopback(main, check, opts)


## One host, one client, `seconds` of play; the report's numbers.
static func loopback(main, check: Callable, opts: Dictionary) -> Dictionary:
	var level := String(opts.get("level", "hickston"))
	var kind := (
		NetSession.Transport.WEBSOCKET
		if bool(opts.get("websocket", false))
		else NetSession.Transport.ENET
	)
	var tag := (
		"%s over %s" % [level, "WebSocket" if kind == NetSession.Transport.WEBSOCKET else "ENet"]
	)
	var tally := CrashLog.tally()
	# A port of its own (other checks may be running beside this one).
	var port := 40000 + OS.get_process_id() % 20000
	var hs: NetSession = null
	for k in 20:
		hs = NetSession.host(port + k, kind, 3, "127.0.0.1")
		if hs != null:
			port += k
			break
	if hs == null:
		check.call(false, "%s: the host could listen on a port" % tag)
		tally.stop()
		return {}
	var cs := NetSession.join("127.0.0.1", port, kind)
	var difficulty := 1
	var game := MultiBots.made(main, level, 1, difficulty)
	game.cheats.god = true
	var host := NetSync.Host.new(
		hs, game, func() -> int: return MultiBots.seat(game), 60 / int(opts.get("snap_hz", 20))
	)
	var client := NetSync.Client.new(
		cs, func(id: String) -> Game: return MultiBots.made(main, id, 1, difficulty)
	)
	client.keep_rebuilt = true
	var began := Time.get_ticks_msec()
	while not cs.connected() and Time.get_ticks_msec() - began < 5000:
		host.listen(0.0)
		cs.poll(0.0)
		OS.delay_msec(1)
	client.hello()
	while client.slot < 0 and client.refused == "" and Time.get_ticks_msec() - began < 5000:
		host.listen(0.0)
		client.receive(0.0)
		OS.delay_msec(1)
	check.call(
		client.slot == 1,
		(
			"%s: the client connects and is seated as player two (%d ms)"
			% [tag, Time.get_ticks_msec() - began]
		)
	)
	if client.slot != 1:
		hs.close()
		cs.close()
		tally.stop()
		return {}
	for s: NetSession in [hs, cs]:
		s.lag_ms = float(opts.get("lag", 0.0))
		s.jitter_ms = float(opts.get("jitter", 0.0))
		s.loss = float(opts.get("loss", 0.0))
	var host_bot := Pilot.new()
	host_bot.as_controls = true
	var client_bot := Pilot.new()
	client_bot.as_controls = true
	var ticks := int(float(opts.get("seconds", 10.0)) * 60.0)
	var compared := 0
	var differ := ""
	var wholes := {}
	var two_from := Vector2(game.players[1].x, game.players[1].y)
	var walked := 0.0
	var wall := Time.get_ticks_msec()
	for t in ticks:
		var now := t * 1000.0 / 60.0
		var mine := Game.Controls.new()
		var me := client.me()
		if me != null:
			client.game.focus(me)
			mine = client_bot.steer(client.game)
		client.send_input(mine)
		var p1: Player = game.players[0]
		game.focus(p1)
		var own := host_bot.steer(game)
		game.focus(game.local_player)
		var seq_was := host.seq
		host.step(now, {0: own})
		if host.seq != seq_was:
			# The host's game as it stood for that snapshot (the host keeps only
			# what changed): what the client must rebuild.
			wholes[host.seq] = NetSync.capture(game)
		game.focus(p1)
		host_bot.moved(game)
		game.focus(game.local_player)
		var two: Player = game.players[1]
		walked += Vector2(two.x, two.y).distance_to(two_from)
		two_from = Vector2(two.x, two.y)
		client.receive(now)
		if client.me() != null:
			client.game.focus(client.me())
			client_bot.moved(client.game)
		for seq in client.rebuilt.keys():
			var theirs = wholes.get(seq)
			if theirs != null:
				compared += 1
				if differ == "" and not GameSnapshot.same(theirs, client.rebuilt[seq]):
					differ = (
						"snapshot %d: %s"
						% [seq, GameSnapshot.first_difference(theirs, client.rebuilt[seq])]
					)
			client.rebuilt.erase(seq)
			wholes.erase(seq - 64)
	# What is still on its way (the client's copy checked once more at the end).
	for k in 30:
		var now := (ticks + k) * 1000.0 / 60.0
		host.listen(now)
		client.receive(now)
	var wall_s := (Time.get_ticks_msec() - wall) / 1000.0
	var seconds := ticks / 60.0
	var r: NetSync.Remote = host.remotes.values()[0] if not host.remotes.is_empty() else null
	var stats := {
		"down": hs.sent / seconds,
		"up": cs.sent / seconds,
		"down_wire": (hs.sent + hs.sent_packets * NetSession.HEADER_BYTES) / seconds,
		"up_wire": (cs.sent + cs.sent_packets * NetSession.HEADER_BYTES) / seconds,
		"full": _spread(host.sizes_full),
		"delta": _spread(host.sizes_delta),
		"input": cs.sent / maxf(1.0, cs.sent_packets),
	}
	print(
		(
			"    %s: %.0f s of play in %.1f s, lag %d ms +%d jitter, loss %d%%, %d snapshots a second"
			% [
				tag,
				seconds,
				wall_s,
				opts.get("lag", 0.0),
				opts.get("jitter", 0.0),
				roundi(float(opts.get("loss", 0.0)) * 100.0),
				roundi(60.0 / host.snap_every)
			]
		)
	)
	print(
		(
			(
				"    down %.1f KB/s (%.1f with headers), up %.1f KB/s (%.1f),"
				+ " %d+%d packets, %d dropped by the test"
			)
			% [
				stats["down"] / 1024.0,
				stats["down_wire"] / 1024.0,
				stats["up"] / 1024.0,
				stats["up_wire"] / 1024.0,
				hs.sent_packets,
				cs.sent_packets,
				hs.dropped + cs.dropped
			]
		)
	)
	print(
		(
			"    snapshots: %d whole (%s bytes), %d deltas (bytes %s); input packets %.0f bytes"
			% [
				host.sizes_full.size(),
				stats["full"],
				host.sizes_delta.size(),
				stats["delta"],
				stats["input"]
			]
		)
	)
	var lags := client.lag_samples.duplicate()
	lags.sort()
	print(
		(
			(
				"    client: %d snapshots rebuilt, %d stale, %d without a base, %d copies"
				+ " rebuilt, %d checks, input to confirmation median %.0f ms;"
				+ " host: %d late inputs, %d skipped"
			)
			% [
				client.latest + 1,
				client.stale,
				client.no_base,
				client.rebuilds,
				client.checks,
				lags[lags.size() / 2] if not lags.is_empty() else -1.0,
				r.starved if r != null else -1,
				r.skipped if r != null else -1
			]
		)
	)
	var snaps := maxi(1, host.seq + 1)
	print(
		(
			"    host costs: tick %.2f ms, capture %.1f ms, delta+bytes %.1f ms a snapshot"
			% [
				host.tick_us / 1000.0 / ticks,
				host.capture_us / 1000.0 / snaps,
				host.delta_us / 1000.0 / snaps
			]
		)
	)
	check.call(
		client.latest > ticks / host.snap_every / 2, "%s: the client gets the snapshots" % tag
	)
	check.call(
		compared > 0 and differ == "",
		(
			"%s: every snapshot the client rebuilt is the host's (%d compared)%s"
			% [tag, compared, "" if differ == "" else ": " + differ]
		)
	)
	check.call(
		client.checks > 0 and client.mismatches == 0,
		(
			"%s: the client's copy matches the host's snapshots (%d checks, %d rebuilds)%s"
			% [
				tag,
				client.checks,
				client.rebuilds,
				"" if client.mismatches == 0 else ": " + client.first_mismatch
			]
		)
	)
	check.call(
		walked > 2.0,
		"%s: the client's inputs move player two on the host (%.1f walked)" % [tag, walked]
	)
	tally.stop()
	check.call(
		tally.errors == 0,
		(
			"%s: no script or engine errors%s"
			% [tag, "" if tally.errors == 0 else ": " + tally.first_errors[0]]
		)
	)
	hs.close()
	cs.close()
	return stats


## "median / p95 / max" of sizes.
static func _spread(sizes: PackedInt32Array) -> String:
	if sizes.is_empty():
		return "none"
	var sorted := sizes.duplicate()
	sorted.sort()
	return (
		"%d / %d / %d" % [sorted[sorted.size() / 2], sorted[int(sorted.size() * .95)], sorted[-1]]
	)
