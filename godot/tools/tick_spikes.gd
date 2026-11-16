## The worst ticks of a bot's play and what was in them (not a check; for
## finding hitches): net_bench.gd's game (a bot playing, god mode, 120 Hz)
## played `runs` times from the same start. Play is exact, so the same tick
## does the same work every run: each tick's time is its least over the runs,
## which leaves out the PC's own hiccups (another program taking the core)
## and keeps what the game did. Each feature's tick (GameFeature.tick_with)
## and each listener of the game's events (enemy_killed, blood_sprayed,
## shot_fired...) is timed apart; "core" is the rest (the bodies, the guns
## and their hits, the enemies, the shots).
##
##   godot --headless --path godot --script res://tools/tick_spikes.gd
##       [-- level=hickston] [players=1] [ticks=7200] [runs=3] [top=20]
##
## Prints the median, p95, p99 and worst tick, then the `top` worst with
## their costliest parts (microseconds), then the parts' share of the time
## the ticks over three times the median spent past it.
extends SceneTree

const Pilot := preload("res://tools/bot_pilot.gd")
const STEP := 1.0 / 120.0

## This tick's microseconds by part (features and listeners).
var parts: Dictionary = {}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var level := "hickston"
	var n := 1
	var ticks := 7200
	var runs := 3
	var top := 20
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("level="):
			level = arg.substr(6)
		elif arg.begins_with("players="):
			n = int(arg.substr(8))
		elif arg.begins_with("ticks="):
			ticks = int(arg.substr(6))
		elif arg.begins_with("runs="):
			runs = maxi(1, int(arg.substr(5)))
		elif arg.begins_with("top="):
			top = int(arg.substr(4))
	var played: Array = []
	for r in runs:
		played.append(_play(main, level, n, ticks))
	# Each tick at its least over the runs (and each part).
	var rows: Array = []
	var parted := 0
	for t in ticks:
		var best: Array = played[0][t].duplicate(true)
		for r in range(1, runs):
			var other: Array = played[r][t]
			if other[2] != best[2]:
				parted += 1
			best[0] = mini(best[0], other[0])
			for k: String in other[1]:
				best[1][k] = mini(int(best[1].get(k, 1 << 30)), int(other[1][k]))
		var listened := 0
		for k: String in best[1]:
			listened += int(best[1][k])
		best[1]["(core)"] = maxi(0, best[0] - listened)
		rows.append(best)
	if parted > 0:
		print("WARNING: %d ticks played differently between runs (not exact?)" % parted)
	var totals: Array = []
	for row: Array in rows:
		totals.append(row[0])
	totals.sort()
	var median: int = totals[totals.size() / 2]
	print(
		(
			"%s %d player%s: median %.3f ms, p95 %.3f, p99 %.3f, worst %.2f (%d ticks, least of %d runs)"
			% [
				level,
				n,
				"" if n == 1 else "s",
				median / 1000.0,
				totals[int(totals.size() * .95)] / 1000.0,
				totals[int(totals.size() * .99)] / 1000.0,
				totals[-1] / 1000.0,
				ticks,
				runs
			]
		)
	)
	var by_part := {}
	for row: Array in rows:
		for k: String in row[1]:
			if not by_part.has(k):
				by_part[k] = []
			by_part[k].append(row[1][k])
	var usual := {}
	for k: String in by_part:
		var values: Array = by_part[k]
		values.resize(rows.size())
		for i in values.size():
			if values[i] == null:
				values[i] = 0
		values.sort()
		usual[k] = values[values.size() / 2]
	var order := rows.duplicate()
	order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for row: Array in order.slice(0, top):
		print("  tick %5d %7.2f ms  %s" % [row[3], row[0] / 1000.0, _costliest(row[1], 4)])
	var past := {}
	var spiky := 0
	for row: Array in rows:
		if row[0] < median * 3:
			continue
		spiky += 1
		for k: String in row[1]:
			past[k] = int(past.get(k, 0)) + maxi(0, int(row[1][k]) - int(usual.get(k, 0)))
	print(
		(
			"ticks over 3x the median: %d; their time past the usual by part: %s"
			% [spiky, _costliest(past, 8)]
		)
	)
	main.queue_free()
	await process_frame
	quit()


func _costliest(us: Dictionary, count: int) -> String:
	var rows: Array = []
	for k: String in us:
		rows.append([int(us[k]), k])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var out := ""
	for row: Array in rows.slice(0, count):
		out += "%s %d  " % [row[1], row[0]]
	return out


## One play: per tick [microseconds, parts, a fingerprint of the state, tick].
func _play(main, level: String, n: int, ticks: int) -> Array:
	var g: Game = main.make_game(level)
	g.configure({"difficulty": 1})
	for done: String in Campaign.ORDER.slice(0, maxi(0, Campaign.ORDER.find(level))):
		g.history.append([done, 1, 2, 0, 1, 60])
	g.cheats.god = true
	for i in n - 1:
		var p := g.players[0]
		var at := Vector2(p.x, p.y)
		for side: Vector2 in [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]:
			var there := Vector2(p.x, p.y) + side * (1.2 + i * .3)
			if not g.world.blocked(there.x, there.y, .25):
				at = there
				break
		Players.join(g, at.x, at.y, p.angle + .5 * (i + 1))
	var pilots: Array = []
	for i in n:
		var pilot := Pilot.new()
		pilot.as_controls = true
		pilots.append(pilot)
	_time_ticks(g)
	_time_listeners(g)
	var rows: Array = []
	for t in ticks:
		var given := {}
		for p: Player in g.players:
			if p.health <= 0:
				continue
			g.focus(p)
			given[p.slot] = pilots[p.slot].steer(g)
		g.focus(g.local_player)
		parts = {}
		var t0 := Time.get_ticks_usec()
		if g.players.size() == 1:
			g.tick(STEP, given.get(0, Game.Controls.new()))
		else:
			g.tick(STEP, given)
		var spent := Time.get_ticks_usec() - t0
		var alerted := 0
		for e: Enemy in g.enemies:
			if e.alerted and e.alive:
				alerted += 1
		rows.append([spent, parts, [alerted, g.enemies.size(), g.player.x], t])
		for p: Player in g.players:
			g.focus(p)
			pilots[p.slot].moved(g)
		g.focus(g.local_player)
	return rows


func _name(c: Callable) -> String:
	var who := c.get_object()
	if who != null and who.get_script() != null:
		return (who.get_script() as Script).resource_path.get_file().get_basename()
	return "?"


## Each feature's tick under a timer of its own (GameEvents' tick list).
func _time_ticks(g: Game) -> void:
	var ticks: Array = g.events.get("_ticks")
	for i in ticks.size():
		var c: Callable = ticks[i]
		var name := _name(c)
		ticks[i] = func(dt: float) -> void:
			var t0 := Time.get_ticks_usec()
			c.call(dt)
			parts[name] = int(parts.get(name, 0)) + Time.get_ticks_usec() - t0


## Each listener of the game's events (but `ticked`'s tick list) under a timer.
func _time_listeners(g: Game) -> void:
	var events: GameEvents = g.events
	for info: Dictionary in events.get_signal_list():
		var signal_name: String = info["name"]
		if signal_name == "ticked":
			continue
		var sig := Signal(events, signal_name)
		var links: Array = sig.get_connections()
		for link: Dictionary in links:
			sig.disconnect(link["callable"])
		for link: Dictionary in links:
			var c: Callable = link["callable"]
			var name := "%s>%s.%s" % [signal_name, _name(c), c.get_method()]
			sig.connect(
				func(...args: Array) -> void:
					var t0 := Time.get_ticks_usec()
					c.callv(args)
					parts[name] = int(parts.get(name, 0)) + Time.get_ticks_usec() - t0
			)
