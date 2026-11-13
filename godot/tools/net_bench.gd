## How much the network side costs (not a check; numbers to compare old and
## new code back to back): per chapter, the tick with 1, 2 and 4 players (bots
## playing, god mode), and the snapshots: a full capture, its bytes, a delta
## four ticks on (what a 30 Hz update carries at 120 Hz), applying it.
##
##   godot --headless --path godot --script res://tools/net_bench.gd
##       [-- levels=hickston,fair] [players=1,2,4] [ticks=7200] [idle]
##
## idle: the players past the first stand still instead of playing. With a
## GameHost (src/game_host.gd) it also times the host's own snapshot, delta
## and a mirror keeping up.
extends SceneTree

const Pilot := preload("res://tools/bot_pilot.gd")
const STEP := 1.0 / 120.0
const SAMPLES := 30
const GAP := 4


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var levels: Array = ["hickston", "fair", "sawmill", "quarry", "bayou", "speedway", "mothership"]
	var counts: Array = [1, 2, 4]
	var ticks := 7200
	var idle := false
	var snaps := true
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("levels="):
			levels = Array(arg.substr(7).split(","))
		elif arg.begins_with("players="):
			counts = Array(arg.substr(8).split(",")).map(func(s): return int(s))
		elif arg.begins_with("ticks="):
			ticks = int(arg.substr(6))
		elif arg == "idle":
			idle = true
		elif arg == "no-snap":
			snaps = false
	var host_script: Script = null
	for row: Dictionary in ProjectSettings.get_global_class_list():
		if String(row["class"]) == "GameHost":
			host_script = load(String(row["path"]))
	for id: String in levels:
		for n: int in counts:
			_bench(main, id, n, ticks, idle, snaps and n == 1, host_script)
	main.queue_free()
	await process_frame
	quit()


static func _made(main, id: String, players: int) -> Game:
	var g: Game = main.make_game(id)
	g.configure({"difficulty": 1})
	for done: String in Campaign.ORDER.slice(0, maxi(0, Campaign.ORDER.find(id))):
		g.history.append([done, 1, 2, 0, 1, 60])
	g.cheats.god = true
	for i in players - 1:
		var p := g.players[0]
		var at := Vector2(p.x, p.y)
		for side: Vector2 in [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]:
			var there := Vector2(p.x, p.y) + side * (1.2 + i * .3)
			if not g.world.blocked(there.x, there.y, .25):
				at = there
				break
		Players.join(g, at.x, at.y, p.angle + .5 * (i + 1))
	return g


static func _step(g: Game, pilots: Array, idle: bool) -> float:
	var given := {}
	for p: Player in g.players:
		if p.health <= 0 or (idle and p.slot > 0):
			continue
		g.focus(p)
		given[p.slot] = pilots[p.slot].steer(g)
	g.focus(g.local_player)
	var t0 := Time.get_ticks_usec()
	if g.players.size() == 1:
		g.tick(STEP, given.get(0, Game.Controls.new()))
	else:
		g.tick(STEP, given)
	var spent := (Time.get_ticks_usec() - t0) / 1000.0
	for p: Player in g.players:
		g.focus(p)
		pilots[p.slot].moved(g)
	g.focus(g.local_player)
	return spent


static func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[sorted.size() / 2])


static func _bench(
	main, id: String, n: int, ticks: int, idle: bool, snaps: bool, host_script: Script
) -> void:
	var g := _made(main, id, n)
	var pilots: Array = []
	for i in n:
		var pilot := Pilot.new()
		pilot.as_controls = true
		pilots.append(pilot)
	var times: Array = []
	for t in ticks:
		times.append(_step(g, pilots, idle))
	var total := 0.0
	for ms: float in times:
		total += ms
	var sorted := times.duplicate()
	sorted.sort()
	print(
		(
			"%-10s %d player%s: tick mean %.3f ms, p95 %.3f, max %.2f (%d ticks, %d enemies)"
			% [
				id,
				n,
				"" if n == 1 else "s",
				total / maxf(1.0, times.size()),
				float(sorted[int(sorted.size() * .95)]),
				float(sorted[-1]),
				ticks,
				g.enemies.size()
			]
		)
	)
	if not snaps:
		return
	var caps: Array = []
	var snap := {}
	for k in 5:
		var t0 := Time.get_ticks_usec()
		snap = GameSnapshot.capture(g)
		caps.append((Time.get_ticks_usec() - t0) / 1000.0)
	var t1 := Time.get_ticks_usec()
	var bytes := GameSnapshot.to_bytes(snap)
	var pack_ms := (Time.get_ticks_usec() - t1) / 1000.0
	var d_ms: Array = []
	var d_cap: Array = []
	var d_size: Array = []
	var d_raw: Array = []
	var base := snap
	for s in SAMPLES:
		for k in GAP:
			_step(g, pilots, idle)
		var t2 := Time.get_ticks_usec()
		var now := GameSnapshot.capture(g)
		var t3 := Time.get_ticks_usec()
		var change = GameSnapshot.delta(base, now)
		var t4 := Time.get_ticks_usec()
		d_cap.append((t3 - t2) / 1000.0)
		d_ms.append((t4 - t3) / 1000.0)
		d_size.append(GameSnapshot.to_bytes(change).size())
		d_raw.append(var_to_bytes(change).size())
		base = now
	var fresh := _made(main, id, 1)
	var t5 := Time.get_ticks_usec()
	GameSnapshot.apply(fresh, base)
	var apply_ms := (Time.get_ticks_usec() - t5) / 1000.0
	print(
		(
			(
				"    snapshot: capture %.2f ms (min %.2f), %d bytes packed (%.2f ms to pack);"
				+ " delta of %d ticks: capture %.2f + diff %.2f ms, %d bytes packed (%d raw);"
				+ " apply to a fresh game %.2f ms"
			)
			% [
				_median(caps),
				caps.min(),
				bytes.size(),
				pack_ms,
				GAP,
				_median(d_cap),
				_median(d_ms),
				int(_median(d_size)),
				int(_median(d_raw)),
				apply_ms
			]
		)
	)
	if host_script != null:
		_bench_host(main, g, pilots, idle, host_script)


## The host's own way: delta_since an acknowledged tick, and a mirror keeping
## up with deltas only (src/game_host.gd).
static func _bench_host(main, g: Game, pilots: Array, idle: bool, host_script: Script) -> void:
	var host = host_script.call("adopt", g)
	var mirror = host_script.call("mirror_for", main.make_game(g.level.id))
	var full = host.snapshot()
	var t0 := Time.get_ticks_usec()
	mirror.take(full)
	var first_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var d_ms: Array = []
	var a_ms: Array = []
	var sizes: Array = []
	for s in SAMPLES:
		for k in GAP:
			host.step(_controls(g, pilots, idle))
		var t1 := Time.get_ticks_usec()
		var d: PackedByteArray = host.delta_since(mirror.acked)
		var t2 := Time.get_ticks_usec()
		mirror.take(d)
		var t3 := Time.get_ticks_usec()
		d_ms.append((t2 - t1) / 1000.0)
		a_ms.append((t3 - t2) / 1000.0)
		sizes.append(d.size())
	var t4 := Time.get_ticks_usec()
	var whole: PackedByteArray = host.snapshot()
	var full_ms := (Time.get_ticks_usec() - t4) / 1000.0
	print(
		(
			(
				"    host: full snapshot %.2f ms, %d bytes (mirror takes it in %.2f ms);"
				+ " delta of %d ticks %.2f ms, %d bytes; mirror applies it in %.2f ms"
			)
			% [
				full_ms,
				whole.size(),
				first_ms,
				GAP,
				_median(d_ms),
				int(_median(sizes)),
				_median(a_ms)
			]
		)
	)


static func _controls(g: Game, pilots: Array, idle: bool) -> Dictionary:
	var given := {}
	for p: Player in g.players:
		if p.health <= 0 or (idle and p.slot > 0):
			continue
		g.focus(p)
		given[p.slot] = pilots[p.slot].steer(g)
	g.focus(g.local_player)
	return given
