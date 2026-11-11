## Frame-time benchmark: the simulation and the software renderer, without a window.
##
##   Godot --headless --path <project> --script res://tools/bench.gd [-- <frames>]
##
## For every chapter it stands the player in the open at the spawn, then walks
## into the nearest fight holding the trigger. Each frame is timed in parts:
## the 60 Hz tick, the full draw, and inside the draw the scene render alone.
## Prints the mean and the worst 1% per part, and what frame rate that allows.
extends SceneTree

const LEVELS := ["hickston", "fair", "sawmill", "quarry"]


func _init() -> void:
	_run.call_deferred()


func _stats(samples: PackedFloat32Array) -> Array:
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0.0
	for v in sorted:
		total += v
	var worst := sorted[mini(sorted.size() - 1, int(sorted.size() * .99))]
	return [total / maxf(1.0, sorted.size()), worst]


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var frames := int(args[0]) if args.size() > 0 else 240
	var assets := Assets.new()
	var hud := HUD.new(assets)
	var sound := Sound.new(assets)
	root.add_child(sound)
	var options := SessionStore.settings("")
	var canvas := Canvas.new()
	var all_tick := PackedFloat32Array()
	var all_draw := PackedFloat32Array()
	for level in LEVELS:
		for scene in ["idle", "fight"]:
			var game := Game.new(assets, hud, sound, level)
			game.configure(options)
			# As in a window: the display shader does the look pass (pass "cpu" to time it in software).
			game.gpu_look = not (args.size() > 1 and String(args[1]) == "cpu")
			# As in a window: the shader also draws the sky, floors and ceilings and
			# shades the walls ("classic" keeps all of it in software). There is no
			# graphics card here, so its share is not in these numbers; main.gd's
			# --view-bench times whole frames in a real window.
			game.layered = game.gpu_look and not args.has("classic")
			if args.has("low"):
				game.renderer.set_detail(1)
			if args.has("single"):
				game.renderer.use_threads = false
			var p := game.player
			var controls := Game.Controls.new()
			if scene == "fight":
				var best: Enemy = null
				for enemy: Enemy in game.enemies:
					if not enemy.hostile or enemy.dormant:
						continue
					if (
						best == null
						or (
							absf(enemy.x - p.x) + absf(enemy.y - p.y)
							< absf(best.x - p.x) + absf(best.y - p.y)
						)
					):
						best = enemy
				if best != null:
					for angle in [0.0, PI * .5, PI, -PI * .5]:
						var x := best.x - cos(angle) * 2.6
						var y := best.y - sin(angle) * 2.6
						if game.world.solid[game.world.cell(x, y)] < 0:
							p.x = x
							p.y = y
							p.angle = angle
							break
				p.health = 100000
				controls.fire = true
				controls.turn = .4
			var tick := PackedFloat32Array()
			var draw := PackedFloat32Array()
			var scene_only := PackedFloat32Array()
			var stages := [0.0, 0.0, 0.0, 0.0, 0.0]
			for i in frames:
				var t0 := Time.get_ticks_usec()
				game.tick(1.0 / 60.0, controls)
				var t1 := Time.get_ticks_usec()
				game.draw(canvas, 1, true)
				var t2 := Time.get_ticks_usec()
				if i < 20:
					continue  # caches warming
				tick.append((t1 - t0) / 1000.0)
				draw.append((t2 - t1) / 1000.0)
				scene_only.append(game.renderer.last_render_ms)
				for k in 5:
					stages[k] += float(game.stage_ms[k]) / (frames - 20)
			print(
				(
					"   sprites %.2f  scene %.2f  weapon %.2f  look %.2f  hud %.2f"
					% [stages[0], stages[1], stages[2], stages[3], stages[4]]
				)
			)
			all_tick.append_array(tick)
			all_draw.append_array(draw)
			var a := _stats(tick)
			var b := _stats(draw)
			var c := _stats(scene_only)
			var row := (
				"%-9s %-5s tick %5.2f / %5.2f ms   draw %5.2f / %5.2f ms"
				% [level, scene, a[0], a[1], b[0], b[1]]
			)
			row += (
				"   scene %5.2f / %5.2f ms   -> %3.0f fps (worst %3.0f)"
				% [c[0], c[1], 1000.0 / (a[0] + b[0]), 1000.0 / (a[1] + b[1])]
			)
			print(row)
	var a := _stats(all_tick)
	var b := _stats(all_draw)
	var total := (
		"OVERALL   tick %5.2f / %5.2f ms   draw %5.2f / %5.2f ms" % [a[0], a[1], b[0], b[1]]
	)
	total += (
		"   -> %3.0f fps mean, %3.0f fps at the worst 1%%"
		% [1000.0 / (a[0] + b[0]), 1000.0 / (a[1] + b[1])]
	)
	print(total)
	quit()
