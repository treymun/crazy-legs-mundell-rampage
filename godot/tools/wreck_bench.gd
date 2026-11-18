## The wreck pieces' own cost, headless (looks only: wreckage.gd's tick, its
## physics and its sounds), to hold old against new back to back:
##
##   godot --headless --path godot --script res://tools/wreck_bench.gd [-- runs=3]
##
## wreck48: hickston's densest cluster of breakables broken at once (as
## stress_bench's wreck48), about 48 pieces in the air; every: every
## breakable on hickston with pieces broken at once (48 at most lie about,
## the oldest shrink away). Each times wreckage's tick alone for 300 ticks
## from the break: the mean, the worst tick, the mean per awake piece-step and
## when the last piece went to sleep, and the work counted (awake
## piece-steps and contacts solved: the same on a busy machine). Prints the
## median of `runs` runs.
extends SceneTree

const DT := 1.0 / 60.0
const TICKS := 300


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var runs := 3
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("runs="):
			runs = int(String(arg).substr(5))
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	for scene: String in ["wreck48", "every"]:
		var rows: Array = []
		for r in runs:
			rows.append(_scene(main, scene))
		var cols := ["mean", "worst", "per_piece", "asleep", "pieces", "steps", "contacts"]
		var line := "WRECK BENCH %-8s" % scene
		for c in cols.size():
			var vals: Array = []
			for row: Array in rows:
				vals.append(row[c])
			vals.sort()
			line += "  %s %.3f" % [cols[c], vals[vals.size() / 2]]
		print(line)
	main.queue_free()
	await process_frame
	quit()


func _scene(main: Control, scene: String) -> Array:
	var g: Game = main.make_game("hickston")
	g.configure({})
	g.cheats.god = true
	for e: Enemy in g.enemies:
		e.dormant = true
	var wreck = g.features["wreckage"]
	var breaks = g.features["breakables"]
	var sets = g.features.get("set_pieces")
	g.features.erase("set_pieces")
	var can: Array = []
	for i in breaks.pieces.size():
		var bp = breaks.pieces[i]
		if not bp.broken and str(bp.spec.get("pieces", "")) != "":
			can.append(i)
	var best := Vector2.ZERO
	var most := -1
	for i: int in can:
		var at := Vector2(breaks.pieces[i].x, breaks.pieces[i].y)
		var n := 0
		for j: int in can:
			if at.distance_to(Vector2(breaks.pieces[j].x, breaks.pieces[j].y)) < 5.0:
				n += 1
		if n > most:
			most = n
			best = at
	can.sort_custom(
		func(a: int, b: int) -> bool:
			return (
				best.distance_squared_to(Vector2(breaks.pieces[a].x, breaks.pieces[a].y))
				< best.distance_squared_to(Vector2(breaks.pieces[b].x, breaks.pieces[b].y))
			)
	)
	var eye := best + Vector2(6.0, 0.0)
	g.player.x = eye.x
	g.player.y = eye.y
	var struck := 0
	for i: int in can:
		# (wreck48: the nearest eight, as stress_bench breaks them.)
		if scene == "wreck48" and struck >= 8:
			break
		var bp = breaks.pieces[i]
		if bp.broken:
			continue
		var away := Vector2(bp.x - eye.x, bp.y - eye.y).normalized()
		breaks.strike(i, 9999.0, away.x, away.y)
		struck += 1
	# The breaks are seen (wreckage throws) on its next tick: timed from there.
	var total := 0
	var worst := 0
	var piece_steps := 0
	var asleep := -1.0
	# The work, whatever the machine is doing: awake piece-steps and contacts
	# solved (counted, not timed).
	var work_steps := 0
	var contacts := 0
	for t in TICKS:
		var awake := 0
		for b in wreck.physics.bodies:
			awake += 1 if b.awake else 0
		var n: int = wreck.steps if awake <= wreck.CROWD else 1
		if n > 1 and wreck.physics._slow():
			n = 1
		var t0 := Time.get_ticks_usec()
		wreck._tick(DT)
		var us := Time.get_ticks_usec() - t0
		total += us
		worst = maxi(worst, us)
		work_steps += awake * n
		contacts += wreck.physics._pool._used * n
		piece_steps += awake
		if asleep < 0.0 and t > 2 and not wreck.physics.moving():
			asleep = t * DT
	if sets != null:
		g.features["set_pieces"] = sets
	return [
		total / 1000.0 / TICKS,
		worst / 1000.0,
		total / maxf(1.0, piece_steps),
		asleep if asleep >= 0.0 else 99.0,
		float(wreck.wrecks.size()),
		float(work_steps),
		float(contacts)
	]
