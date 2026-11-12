## Frame times as each boss falls, in a real window (the graphics-card view):
## the boss's rematch is built, the player stands at its arena entrance looking
## at it, it is struck down, and the next frames are timed, split into the
## game's tick, drawing and the wait for the frame. The fall is the costliest
## moment of a fight (gibs, debris, the loot shower, slow motion).
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/fall_bench.gd [-- kinds=boss,maw]
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

const STEP := 1.0 / 60.0
const FRAMES := 150

var main


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var kinds: Array = BossRematch.BOSSES.duplicate()
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("kinds="):
			kinds = Array(String(arg).substr(6).split(",", false))
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.touring = true
	Effects.enabled = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	for kind: String in kinds:
		await _fall(kind)
	main.queue_free()
	await process_frame
	quit()


func _fall(kind: String) -> void:
	var g: Game = BossRematch.build(Callable(main, "make_game"), kind)
	main.game = g
	g.configure(SessionStore.defaults())
	g.cheats.god = true
	var boss := BossFight.of_kind(g, kind)
	if boss == null:
		print("FALL %-12s no boss" % kind)
		return
	var p := g.player
	# A few cells off, facing it.
	var away := atan2(p.y - boss.y, p.x - boss.x)
	for r: float in [5.0, 4.0, 6.0, 3.0, 7.0]:
		var at := Vector2(boss.x + cos(away) * r, boss.y + sin(away) * r)
		if not g.world.blocked(at.x, at.y, .3) and g.world.visible(boss.x, boss.y, at.x, at.y):
			p.x = at.x
			p.y = at.y
			break
	p.angle = atan2(boss.y - p.y, boss.x - p.x)
	p.eye = .95 + g.world.elevation(p.x, p.y)
	for i in 30:
		g.tick(STEP, Game.Controls.new())
		main.render()
		await process_frame
	boss.hp = 1.0
	g.hit_point = Vector3.INF
	var last := Time.get_ticks_usec()
	boss.hurt(60.0, g, true)
	var blow := (Time.get_ticks_usec() - last) / 1000.0
	var rows: Array = []
	for i in FRAMES:
		var t0 := Time.get_ticks_usec()
		g.tick(STEP, Game.Controls.new())
		var t1 := Time.get_ticks_usec()
		main.render()
		var t2 := Time.get_ticks_usec()
		await process_frame
		var now := Time.get_ticks_usec()
		rows.append([(now - last) / 1000.0, i, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0])
		last = now
	var worst: Array = rows.duplicate()
	worst.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	var total := 0.0
	for r: Array in rows:
		total += float(r[0])
	var line := (
		"FALL %-12s blow %5.1f ms  first frame %5.1f  mean %5.2f ms  worst:"
		% [kind, blow, float(rows[0][0]), total / rows.size()]
	)
	for r: Array in worst.slice(0, 4):
		line += "  %.1f (#%d tick %.1f draw %.1f)" % [r[0], r[1], r[2], r[3]]
	print(line)
