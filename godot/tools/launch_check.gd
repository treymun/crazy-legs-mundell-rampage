## A launch the way a player's goes: the window mode from the settings, then
## play, and the start-up view check (main_state.gd _check_view) judging the
## first frames. It must end on the graphics-card view (check 1, cpu_view
## false, layered true), and with VIEW DETAIL HD on, detail -1. Until
## 2.0.0-dev.34 the check grabbed a level's first frame before the shader had
## drawn it, read the black as a mismatch and kept every launch in software:
## no HD, and about four times slower.
##
##   godot --path godot --audio-driver Dummy \
##       --script res://tools/launch_check.gd [-- <window mode 0..3>]
##
## Point APPDATA at a scratch folder holding an options.json to try a player's settings.
extends SceneTree

var main


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	main.view_check_report = true
	root.add_child(main)
	for i in 10:
		await process_frame
	var mode := (
		int(OS.get_cmdline_user_args()[0]) if not OS.get_cmdline_user_args().is_empty() else 1
	)
	main.change_window_mode(mode)
	for i in 3:
		await process_frame
	main.start("hickston")
	main.state = "play"
	for i in 240:
		await process_frame
	print(
		(
			"FS: window %s mode %d  view rect %s  viewport %s  check %d  cpu_view %s  layered %s  detail %d"
			% [
				get_root().size,
				get_root().mode,
				main.view.get_global_rect(),
				get_root().get_visible_rect().size,
				main.view_check,
				main.cpu_view,
				main.game.layered,
				main.game.renderer.detail
			]
		)
	)
	quit()
