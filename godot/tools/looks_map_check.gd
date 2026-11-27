extends SceneTree

const Demo := preload("res://tools/looks_demo.gd")

var main
var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, text: String) -> void:
	print("  ok   " if condition else "  FAIL ", text)
	if not condition:
		failures.append(text)


func _run() -> void:
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("write="):
			var f := FileAccess.open(arg.substr(6), FileAccess.WRITE)
			f.store_string(JSON.stringify(Demo.level()))
			f.close()
			print("LOOKS DEMO WRITTEN")
			main.queue_free()
			await process_frame
			quit(0)
			return
	var t0 := Time.get_ticks_msec()
	var bare := Demo.bare()
	print("bare %d ms" % (Time.get_ticks_msec() - t0))
	t0 = Time.get_ticks_msec()
	var gg := MapLooksGrid.of(bare)
	print("grid %d ms, route pieces %d" % [Time.get_ticks_msec() - t0, gg.route.size()])
	var specs: Dictionary = Demo.looks()
	for f: Dictionary in specs["foliage"]:
		t0 = Time.get_ticks_msec()
		var done := MapFoliage.scatter(gg, f)
		print("  %s %d placed in %d ms" % [f["kind"], done["placed"], Time.get_ticks_msec() - t0])
	t0 = Time.get_ticks_msec()
	var report := {}
	var lv := Demo.level(Demo.ID, false, report)
	print("built in %d ms %s" % [Time.get_ticks_msec() - t0, report["ms"]])
	for p: Array in report["problems"]:
		print("  problem ", p)
	print("plants %d water %d vignettes %s" % [report["plants"], report["water_cells"], report["vignettes"]])
	var kinds := MapFoliage.pictures()
	var by := {}
	for b: Dictionary in lv["billboards"]:
		var k: String = kinds.get(b["image"], "-")
		by[k] = by.get(k, 0) + 1
	print(by)
	LevelData.preview[Demo.ID] = lv
	var g: Game = main.make_game(Demo.ID)
	check(g != null, "the demo loads")
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
