## Side-by-side pictures of two window tours (main.gd --view-tour): for each
## level, its viewpoints in rows, the first tour's picture on the left and the
## second's on the right, scaled to half size.
##
##   godot --headless --path godot --script res://tools/compare_sheet.gd -- \
##       <old dir> <new dir> <out dir> [mode=fx] [left=fx]
##
## Writes <out dir>/<level>.png. The 3D rewrite's are in docs/godot3d/compare/
## (old renderer left, 3D view right).
extends SceneTree

const WIDE := 640
const GAP := 6


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("compare_sheet.gd -- <old dir> <new dir> <out dir> [mode=fx] [left=fx]")
		quit(1)
		return
	var old_dir := args[0]
	var new_dir := args[1]
	var out_dir := args[2]
	var mode := "fx"
	var left := ""
	for arg: String in args.slice(3):
		if arg.begins_with("mode="):
			mode = arg.substr(5)
		elif arg.begins_with("left="):
			left = arg.substr(5)
	if left == "":
		left = mode
	DirAccess.make_dir_recursive_absolute(out_dir)
	var levels: Array[String] = []
	for file: String in DirAccess.get_files_at("res://data"):
		if file.ends_with(".json") and file != "index.json":
			levels.append(file.get_basename())
	# Longest first: county_hickston before hickston.
	levels.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	var by_level := {}
	for file: String in DirAccess.get_files_at(new_dir):
		if not file.ends_with("_%s.png" % mode):
			continue
		var tag := file.trim_suffix("_%s.png" % mode)
		if not FileAccess.file_exists(old_dir.path_join("%s_%s.png" % [tag, left])):
			continue
		var level := "other"
		for id: String in levels:
			if tag.begins_with(id + "_") or tag.contains("_" + id + "_"):
				level = id
				break
		if not by_level.has(level):
			by_level[level] = []
		by_level[level].append(tag)
	for level: String in by_level:
		var tags: Array = by_level[level]
		tags.sort()
		var rows: Array[Array] = []
		var tall := 0
		for tag: String in tags:
			var a := _scaled(old_dir.path_join("%s_%s.png" % [tag, left]))
			var b := _scaled(new_dir.path_join("%s_%s.png" % [tag, mode]))
			rows.append([a, b])
			tall += maxi(a.get_height(), b.get_height()) + GAP
		var sheet := Image.create_empty(WIDE * 2 + GAP, maxi(1, tall), false, Image.FORMAT_RGB8)
		sheet.fill(Color8(40, 40, 40))
		var y := 0
		for row: Array in rows:
			var a: Image = row[0]
			var b: Image = row[1]
			sheet.blit_rect(a, Rect2i(Vector2i.ZERO, a.get_size()), Vector2i(0, y))
			sheet.blit_rect(b, Rect2i(Vector2i.ZERO, b.get_size()), Vector2i(WIDE + GAP, y))
			y += maxi(a.get_height(), b.get_height()) + GAP
		sheet.save_png(out_dir.path_join(level + ".png"))
	print("compare sheets: %d levels written to %s" % [by_level.size(), out_dir])
	quit()


static func _scaled(path: String) -> Image:
	var image := Image.load_from_file(path)
	image.convert(Image.FORMAT_RGB8)
	var high := int(image.get_height() * float(WIDE) / image.get_width())
	image.resize(WIDE, high, Image.INTERPOLATE_NEAREST)
	return image
