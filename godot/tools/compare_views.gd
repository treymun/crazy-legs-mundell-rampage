## Hold the shader's view against the software view, or against its own
## references, frame by frame.
##
##   Godot --headless --path godot --script res://tools/compare_views.gd -- <dir>
##   Godot --headless --path godot --script res://tools/compare_views.gd -- <dir> refs
##   Godot --headless --path godot --script res://tools/compare_views.gd -- <dir> update
##
## <dir> holds what main.gd's --view-tour=<views.json> --view-out=<dir> writes
## (a real window: the shader only runs with a graphics card, or Mesa's
## software one under xvfb): <tag>_fx.png, the shader view as players see it;
## <tag>_gpu.png, the same without lights and glows; <tag>_cpu.png, the
## software view.
##
## With no mode each _gpu frame is held against its _cpu frame: the software
## view is the fallback, and without the shader's own effects the two agree.
## `refs` holds each _fx frame against tools/pictures_gpu/<tag>.png, the
## references of the view players see; `update` rewrites those references
## (pictures changed on purpose: commit them with the change).
##
## A pixel "strongly" differs when a channel is more than 40 apart. Fails when
## one pair strongly differs in more than STRONG_MAX percent of its pixels, or
## the pairs on average in more than MEAN_MAX percent; writes <tag>_diff.png
## for each pair that fails.
extends SceneTree

const STRONG_MAX := 1.5
const MEAN_MAX := 0.1
const REFS := "res://tools/pictures_gpu"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: compare_views.gd -- <dir> [refs|update]")
		quit(1)
		return
	var folder := String(args[0])
	var mode := String(args[1]) if args.size() > 1 else ""
	var names := DirAccess.get_files_at(folder)
	names.sort()
	if mode == "update":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REFS))
		var written := 0
		for file in names:
			if file.ends_with("_fx.png"):
				var image := Image.load_from_file(folder.path_join(file))
				image.convert(Image.FORMAT_RGB8)
				image.save_png(
					ProjectSettings.globalize_path(REFS).path_join(
						file.trim_suffix("_fx.png") + ".png"
					)
				)
				written += 1
		print("wrote %d references to %s" % [written, REFS])
		quit()
		return
	var suffix := "_fx.png" if mode == "refs" else "_gpu.png"
	var strong_all: Array[float] = []
	var failed := PackedStringArray()
	for file in names:
		if not file.ends_with(suffix):
			continue
		var tag := file.trim_suffix(suffix)
		var shown := Image.load_from_file(folder.path_join(file))
		var against_path := (
			ProjectSettings.globalize_path(REFS).path_join(tag + ".png")
			if mode == "refs"
			else folder.path_join(tag + "_cpu.png")
		)
		var against: Image = (
			Image.load_from_file(against_path) if FileAccess.file_exists(against_path) else null
		)
		if shown == null or against == null or shown.get_size() != against.get_size():
			print("%-34s nothing to hold it against (%s)" % [tag, against_path])
			failed.append(tag)
			continue
		var strong_pc := _compare(shown, against, folder.path_join(tag + "_diff.png"))
		strong_all.append(strong_pc)
		if strong_pc > STRONG_MAX:
			failed.append(tag)
	if strong_all.is_empty():
		print("no *%s frames in %s" % [suffix, folder])
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
	print("VIEWS MATCH THEIR REFERENCES" if mode == "refs" else "VIEWS MATCH")
	quit()


## Prints how far apart two frames are and returns the percentage of pixels
## that strongly differ; writes a mask to `diff_path` when that is too many.
func _compare(shown: Image, against: Image, diff_path: String) -> float:
	shown.convert(Image.FORMAT_RGB8)
	against.convert(Image.FORMAT_RGB8)
	var a := shown.get_data()
	var b := against.get_data()
	var width := shown.get_width()
	var pixels := width * shown.get_height()
	var any := 0
	var strong := 0
	var mask := Image.create_empty(width, shown.get_height(), false, Image.FORMAT_RGB8)
	for i in pixels:
		var o := i * 3
		var apart := maxi(
			absi(a[o] - b[o]), maxi(absi(a[o + 1] - b[o + 1]), absi(a[o + 2] - b[o + 2]))
		)
		if apart > 0:
			any += 1
			if apart > 40:
				strong += 1
				mask.set_pixel(i % width, i / width, Color(1, .24, .24))
	var strong_pc := strong * 100.0 / pixels
	var verdict := ""
	if strong_pc > STRONG_MAX:
		verdict = "  FAIL"
		mask.save_png(diff_path)
	print(
		(
			"%-34s %6.2f%% differ %6.2f%% strongly%s"
			% [
				diff_path.get_file().trim_suffix("_diff.png"),
				any * 100.0 / pixels,
				strong_pc,
				verdict
			]
		)
	)
	return strong_pc
