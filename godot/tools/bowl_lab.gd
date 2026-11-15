## The bowling lane's lab: rolls balls down the firing range's lane from a
## spread of lines (and hooks) and prints what each one leaves standing, how
## long the pins took to settle and how long a tick of the pins took, to tune
## range_bowling.gd / range_pin_physics.gd by.
##
##   Godot --headless --path <project> --script res://tools/bowl_lab.gd [-- trace]
##
## `trace` also prints the pins every half second of the first roll.
extends SceneTree

const RangeCheck := preload("res://tools/range_check.gd")
const L := preload("res://src/range_layout.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	main.return_to_title(true)
	main.campaign_run = null
	RangeCheck._pick(main, "FIRING RANGE")
	var g: Game = main.game
	var feature = g.features.get("range")
	var bowl = feature.targets.bowling
	var trace := "trace" in OS.get_cmdline_user_args()
	var lines := [
		[46.5, 0.0],
		[46.38, 0.0],
		[46.62, 0.0],
		[46.3, 0.0],
		[46.7, 0.0],
		[46.1, 0.0],
		[46.9, 0.0],
		[47.4, -3.0],
		[45.6, 3.0],
		[47.75, 0.0],
		[44.6, 0.0],
	]
	var total_ms := 0.0
	var ticks := 0
	var worst := 0.0
	for row: Array in lines:
		var x: float = row[0]
		var turn: float = row[1]
		bowl.sweep_at = -1.0
		bowl.new_game()
		var p := g.player
		p.x = x
		p.y = 50.2
		p.angle = -PI / 2.0
		feature.targets.last_angle = p.angle
		feature.targets.turn_rate = turn
		g.launch(x, 49.9, .22, -PI / 2.0, 7.4, "bowling", 0.0, false, 108, 4.5)
		var took := -1.0
		for i in 600:
			var t0 := Time.get_ticks_usec()
			g.tick(1.0 / 60.0, Game.Controls.new())
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			total_ms += ms
			worst = maxf(worst, ms)
			ticks += 1
			if trace and lines.find(row) == 0 and (i % 60 == 0 or i == 400):
				_print_pins(bowl, i / 60.0)
			if not bowl.frames[bowl.frame].is_empty() or bowl.frame > 0:
				took = i / 60.0
				break
		var left: Array = []
		for pin: Dictionary in bowl.pins:
			if not bowl.is_down(pin):
				left.append(int(pin["n"]))
		print(
			(
				"x %.2f turn %+.1f: %d down in %.1f s, standing %s  %s"
				% [x, turn, bowl.pins_down(), took, str(left), bowl.last_roll]
			)
		)
	print("pins+game tick: mean %.2f ms, worst %.2f ms" % [total_ms / ticks, worst])
	main.queue_free()
	await process_frame
	quit(0)


func _print_pins(bowl, t: float) -> void:
	var parts: PackedStringArray = []
	for pin: Dictionary in bowl.pins:
		parts.append(
			(
				"%d:%s(%.2f,%.2f,%.2f) lean %.2f %s"
				% [
					int(pin["n"]),
					str(pin["gone"]),
					float(pin["x"]),
					float(pin["y"]),
					float(pin["z"]),
					bowl.lean(pin),
					"A" if float(pin["awake"]) > 0.0 else "z"
				]
			)
		)
	print("t %.1f  " % t, "  ".join(parts))
