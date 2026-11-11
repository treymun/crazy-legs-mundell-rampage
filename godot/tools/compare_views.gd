## Compare the shader's view with the software view, frame by frame.
##
##   Godot --headless --path godot --script res://tools/compare_views.gd -- <dir>
##
## <dir> holds <tag>_gpu.png and <tag>_cpu.png pairs, as main.gd's
## --view-tour=<views.json> --view-out=<dir> writes them (a real window: the
## shader only runs with a graphics card, or Mesa's software one under xvfb).
## A pixel "strongly" differs when a channel is more than 40 apart. Fails when
## one pair strongly differs in more than STRONG_MAX percent of its pixels, or
## the pairs on average in more than MEAN_MAX percent; writes <tag>_diff.png
## for each pair that fails.
extends SceneTree

const STRONG_MAX := 1.5
const MEAN_MAX := 0.1


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: compare_views.gd -- <dir>")
		quit(1)
		return
	var folder := String(args[0])
	var strong_all: Array[float] = []
	var failed := PackedStringArray()
	var names := DirAccess.get_files_at(folder)
	names.sort()
	for file in names:
		if not file.ends_with("_gpu.png"):
			continue
		var tag := file.trim_suffix("_gpu.png")
		var gpu := Image.load_from_file(folder.path_join(file))
		var cpu := Image.load_from_file(folder.path_join(tag + "_cpu.png"))
		if gpu == null or cpu == null or gpu.get_size() != cpu.get_size():
			print("%-34s no matching software frame" % tag)
			failed.append(tag)
			continue
		gpu.convert(Image.FORMAT_RGB8)
		cpu.convert(Image.FORMAT_RGB8)
		var a := gpu.get_data()
		var b := cpu.get_data()
		var pixels := gpu.get_width() * gpu.get_height()
		var any := 0
		var strong := 0
		var mask := Image.create_empty(gpu.get_width(), gpu.get_height(), false, Image.FORMAT_RGB8)
		for i in pixels:
			var o := i * 3
			var apart := maxi(
				absi(a[o] - b[o]), maxi(absi(a[o + 1] - b[o + 1]), absi(a[o + 2] - b[o + 2]))
			)
			if apart > 0:
				any += 1
				if apart > 40:
					strong += 1
					mask.set_pixel(i % gpu.get_width(), i / gpu.get_width(), Color(1, .24, .24))
		var strong_pc := strong * 100.0 / pixels
		strong_all.append(strong_pc)
		var verdict := ""
		if strong_pc > STRONG_MAX:
			verdict = "  FAIL"
			failed.append(tag)
			mask.save_png(folder.path_join(tag + "_diff.png"))
		print(
			(
				"%-34s %6.2f%% differ %6.2f%% strongly%s"
				% [tag, any * 100.0 / pixels, strong_pc, verdict]
			)
		)
	if strong_all.is_empty():
		print("no *_gpu.png frames in " + folder)
		quit(1)
		return
	var mean := 0.0
	for v in strong_all:
		mean += v
	mean /= strong_all.size()
	print("mean strongly differing %.3f%% over %d pairs" % [mean, strong_all.size()])
	if mean > MEAN_MAX or not failed.is_empty():
		print("FAIL: " + ", ".join(failed) if not failed.is_empty() else "FAIL: mean too high")
		quit(1)
		return
	print("VIEWS MATCH")
	quit()
