## Pictures of the update notice's sign on the title in a real window
## (src/update_notice.gd, src/ui/update_sign.gd): the Windows sign, the same
## sign picked, the Android sign with its line on installing over the old
## copy, and the PLAY page's CHECK FOR UPDATES. Nothing is asked of the
## website: the newer version is made up (UpdateNotice.take) and the download
## is never opened.
##
##   godot --path godot --audio-driver Dummy --resolution 1280x800 \
##       --script res://tools/update_frames.gd -- out=<dir>
##
## Point APPDATA at a scratch folder: it runs the game with the profile there.
extends SceneTree

var main
var out := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
	if out == "":
		push_error("out=<dir> is needed")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.touring = true
	main.state = "title"
	main.selection = 0
	await _snap("title_plain")
	for target: String in ["windows", "android"]:
		var notice := UpdateNotice.new("3.11.0", target)
		notice.opener = func(_url: String) -> void: pass
		notice.take("3.12.0")
		if main.update_notice != null:
			main.update_notice.queue_free()
		main.update_notice = notice
		main.add_child(notice)
		main.selection = 0
		main.ui.screen_for("title").call("leave_sign")
		await _snap("update_" + target)
		if target == "windows":
			main.ui.screen_for("title").call("pick_sign")
			await _snap("update_windows_picked")
	# The PLAY page at CHECK FOR UPDATES.
	main.state = "setup"
	var pages := SessionStore.setup_pages()
	for p in pages.size():
		var rows: Array = pages[p][1]
		for s in rows.size():
			if (rows[s] as SessionStore.Setting).key == "update_check":
				main.option_page = p
				main.option_scroll = 0
				main.setup_select(s)
	await _snap("update_setting")
	print("update frames written to ", out)
	main.queue_free()
	await process_frame
	quit()


func _snap(name: String) -> void:
	for i in 3:
		main.render()
		await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out.path_join(name + ".png"))
