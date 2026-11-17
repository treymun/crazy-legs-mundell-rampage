## The 3D view's pictures against their references: a window tour
## (main.gd --view-tour=res://tools/picture_views.json --view-out=<dir>)
## writes <tag>_fx.png (lights and glows on, as players see it) and
## <tag>_gpu.png (off); each is held against tools/pictures_3d/<tag>_<mode>.png.
##
##   godot --headless --path godot --script res://tools/compare_3d.gd -- <dir> [update]
##
## Graphics cards rasterise edges a little differently (the references come
## from one machine, CI draws with Mesa), so a picture passes while at most
## MOST_OFF of its pixels are more than NEAR apart, channel for channel. update
## writes the tour's pictures over the references at 320x200 (commit them). Prints
## PICTURES 3D OK, or each picture that moved too far with its share.
##
## A viewpoint with `contrast` (picture_views.json: the night chapter's fields,
## a blackout) also holds a floor on how well its cast reads: the tour draws it
## again without them (<tag>_bare_fx.png, <tag>_bare_3d.png) and the cast's
## mean |dL*| against what it hides (tools/night_contrast.gd) must be at least
## that number.
extends SceneTree

const Contrast := preload("res://tools/night_contrast.gd")
const VIEWS := "res://tools/picture_views.json"

const REFS := "res://tools/pictures_3d"
const MODES: Array[String] = ["fx", "gpu"]
## How far (0-255, any channel) a pixel may move and still count as the same.
const NEAR := 24
## The share of a picture's pixels that may be further apart than that.
const MOST_OFF := .03


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("compare_3d.gd -- <tour dir> [update]")
		quit(1)
		return
	var dir := args[0]
	var refs := ProjectSettings.globalize_path(REFS)
	DirAccess.make_dir_recursive_absolute(refs)
	if args.has("update"):
		var copied := 0
		for file: String in DirAccess.get_files_at(dir):
			for mode: String in MODES:
				if file.ends_with("_%s.png" % mode) and not file.contains("_bare_"):
					_small(Image.load_from_file(dir.path_join(file))).save_png(refs.path_join(file))
					copied += 1
		print("PICTURES 3D: %d references written to %s" % [copied, refs])
		quit()
		return
	var failed := 0
	var compared := 0
	for file: String in DirAccess.get_files_at(refs):
		if not file.ends_with(".png"):
			continue
		var shown := dir.path_join(file)
		if not FileAccess.file_exists(shown):
			print("MISSING ", file)
			failed += 1
			continue
		var off := _apart(
			Image.load_from_file(refs.path_join(file)), _small(Image.load_from_file(shown))
		)
		compared += 1
		if off > MOST_OFF:
			failed += 1
			print("MOVED %s: %.1f%% of its pixels" % [file, off * 100.0])
	failed += _contrast(dir)
	if compared == 0:
		print("PICTURES 3D: no references in %s (run with update first)" % refs)
		quit(1)
		return
	if failed == 0:
		print("PICTURES 3D OK (%d pictures)" % compared)
		quit(0)
	else:
		print("PICTURES 3D: %d of %d moved too far" % [failed, compared])
		quit(1)


## The contrast floors: how many viewpoints fall short (or lack their pictures).
static func _contrast(dir: String) -> int:
	var short := 0
	var views: Variant = JSON.parse_string(FileAccess.get_file_as_string(VIEWS))
	for shot: Dictionary in views:
		if not shot.has("contrast"):
			continue
		var tag := str(shot["tag"])
		var names := [tag + "_3d", tag + "_bare_3d", tag + "_fx", tag + "_bare_fx"]
		var pictures: Array[Image] = []
		for name: String in names:
			var path := dir.path_join(name + ".png")
			if FileAccess.file_exists(path):
				pictures.append(Image.load_from_file(path))
		if pictures.size() < names.size():
			print("MISSING the contrast pictures of ", tag)
			short += 1
			continue
		var r: Dictionary = Contrast.measure(pictures[0], pictures[1], pictures[2], pictures[3])
		var floor_at: float = shot["contrast"]
		var delta: float = r["delta"]
		print(
			(
				"CONTRAST %s: the cast (%d px) reads %.1f L* from what it hides (floor %.1f)"
				% [tag, r["px"], delta, floor_at]
			)
		)
		if delta < floor_at or int(r["px"]) == 0:
			print("TOO DARK ", tag)
			short += 1
	return short


## A tour's window picture at the canvas's own size (the window is a whole
## number of times 320x200, letterboxed or not, so each pixel is a block).
static func _small(image: Image) -> Image:
	image.convert(Image.FORMAT_RGB8)
	var k := mini(image.get_width() / 320, image.get_height() / 200)
	if k <= 1:
		return image
	var left := (image.get_width() - 320 * k) / 2
	var top := (image.get_height() - 200 * k) / 2
	var out := Image.create_empty(320, 200, false, Image.FORMAT_RGB8)
	for y in 200:
		for x in 320:
			out.set_pixel(x, y, image.get_pixel(left + x * k + k / 2, top + y * k + k / 2))
	return out


## The share of pixels more than NEAR apart (1.0 when the sizes differ).
static func _apart(a: Image, b: Image) -> float:
	if a == null or b == null or a.get_size() != b.get_size():
		return 1.0
	a.convert(Image.FORMAT_RGB8)
	b.convert(Image.FORMAT_RGB8)
	var da := a.get_data()
	var db := b.get_data()
	var off := 0
	for i in range(0, da.size(), 3):
		if (
			absi(da[i] - db[i]) > NEAR
			or absi(da[i + 1] - db[i + 1]) > NEAR
			or absi(da[i + 2] - db[i + 2]) > NEAR
		):
			off += 1
	return float(off) / float(da.size() / 3)
