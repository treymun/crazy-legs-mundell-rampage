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


## A contact sheet (map check, pass 16): every picture in `entries` ([path,
## label]) scaled to `wide` pixels, `cols` to a row, each with its label
## lettered under it in the game's pixel font, saved to `out`. Pictures that
## cannot be read are left out; returns how many went on.
static func contact(entries: Array, out: String, cols := 3, wide := 420) -> int:
	var tiles: Array = []
	for entry: Array in entries:
		if not FileAccess.file_exists(String(entry[0])):
			continue
		var image := Image.load_from_file(String(entry[0]))
		if image == null or image.is_empty():
			continue
		image.convert(Image.FORMAT_RGB8)
		var high := int(image.get_height() * float(wide) / image.get_width())
		image.resize(wide, high, Image.INTERPOLATE_BILINEAR)
		tiles.append([image, String(entry[1]).to_upper()])
	if tiles.is_empty():
		return 0
	var label := 12
	var rows := ceili(tiles.size() / float(cols))
	var row_high: Array[int] = []
	for r in rows:
		var most := 0
		for c in cols:
			var k := r * cols + c
			if k < tiles.size():
				most = maxi(most, (tiles[k][0] as Image).get_height())
		row_high.append(most + label + GAP)
	var total := 0
	for h in row_high:
		total += h
	var sheet := Image.create_empty(cols * (wide + GAP), total, false, Image.FORMAT_RGB8)
	sheet.fill(Color8(28, 26, 24))
	var y := 0
	for r in rows:
		for c in cols:
			var k := r * cols + c
			if k >= tiles.size():
				continue
			var image: Image = tiles[k][0]
			var x := c * (wide + GAP)
			sheet.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(x, y))
			_letters(sheet, String(tiles[k][1]), x + 2, y + image.get_height() + 3)
		y += row_high[r]
	sheet.save_png(out)
	return tiles.size()


static func _letters(img: Image, text: String, x: int, y: int) -> void:
	var at := x
	for ch in text:
		var g: Array = PixelType.glyph(ch, false)
		var rows: Array = g[0]
		var gw: int = g[1]
		for ry in rows.size():
			for rx in gw:
				var px := at + rx
				var py := y + ry
				if (
					int(rows[ry]) & (1 << (gw - 1 - rx))
					and px < img.get_width()
					and py < img.get_height()
				):
					img.set_pixel(px, py, Color(1, .95, .8))
		at += gw + 1
