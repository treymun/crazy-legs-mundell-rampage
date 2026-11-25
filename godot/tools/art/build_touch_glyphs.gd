## The pictures on the touch overlay's KICK and THROW buttons (pass 15,
## src/touch_controls.gd): a cowboy boot mid-kick and a lit stick of
## dynamite, hard-edged 24x24 pixel glyphs in the HUD's ink with a dark rim
## (as its words are drawn), into assets/art/touch_kick.png and
## touch_throw.png. Drawn from shapes at four times the size, each pixel in
## or out by its coverage (no soft edges), so it reads like the rest of the
## 320x200 HUD however big the ring draws it.
##
##   godot --headless --path godot --script res://tools/art/build_touch_glyphs.gd [-- out=<dir>]
##
## Then run tools/pack_assets.gd.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")
const SIZE := 24
const SUPER := 4
## The HUD's ink (hud.gd INK), its shade, the rim, the stick and the spark.
const INK := Color8(250, 232, 193)
const SHADE := Color8(196, 158, 104)
const RIM := Color8(29, 20, 16)
const STICK := Color8(198, 48, 34)
const STICK_DARK := Color8(120, 28, 22)
const SPARK := Color8(255, 214, 90)
const SPARK_HOT := Color8(255, 250, 220)


func _init() -> void:
	var out := Paint.repo("assets/art")
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	_save(_boot(), out.path_join("touch_kick.png"))
	_save(_stick(), out.path_join("touch_throw.png"))
	print("TOUCH GLYPHS WRITTEN to %s" % out)
	quit(0)


func _save(layers: Array, path: String) -> void:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	# Each layer: [polygon or segment list, colour]; later ones on top.
	for layer: Array in layers:
		var shape: Array = layer[0]
		var colour: Color = layer[1]
		for y in SIZE:
			for x in SIZE:
				var hits := 0
				for sy in SUPER:
					for sx in SUPER:
						var at := Vector2(x + (sx + .5) / SUPER, y + (sy + .5) / SUPER)
						if _inside(shape, at):
							hits += 1
				if hits * 2 >= SUPER * SUPER:
					image.set_pixel(x, y, colour)
	_rim(image)
	image.save_png(path)


## A point in a polygon (an Array of Vector2) or near a stroke ([from, to,
## half width] as an Array of three).
func _inside(shape: Array, at: Vector2) -> bool:
	if shape.size() == 3 and shape[2] is float:
		var a: Vector2 = shape[0]
		var b: Vector2 = shape[1]
		var w: float = shape[2]
		return Geometry2D.get_closest_point_to_segment(at, a, b).distance_to(at) <= w
	return Geometry2D.is_point_in_polygon(at, PackedVector2Array(shape))


## A dark rim a pixel wide round everything drawn (the HUD's outlined look).
func _rim(image: Image) -> void:
	var solid := []
	for y in SIZE:
		for x in SIZE:
			solid.append(image.get_pixel(x, y).a > .5)
	for y in SIZE:
		for x in SIZE:
			if solid[y * SIZE + x]:
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := x + d.x
				var ny := y + d.y
				if nx >= 0 and ny >= 0 and nx < SIZE and ny < SIZE and solid[ny * SIZE + nx]:
					image.set_pixel(x, y, RIM)
					break


## A tall cowboy boot side on, toe out to the right, kicking: two swish
## lines behind it.
func _boot() -> Array:
	var boot := [
		Vector2(7, 1.5),
		Vector2(10, 3),
		Vector2(13.5, 1.5),
		Vector2(13, 11),
		Vector2(17, 13),
		Vector2(22, 14),
		Vector2(23.5, 13),
		Vector2(23, 16),
		Vector2(20.5, 18.5),
		Vector2(11, 18.5),
		Vector2(10.5, 21.5),
		Vector2(6.5, 21.5),
		Vector2(6.5, 12),
	]
	return [
		[boot, INK],
		[[Vector2(9.5, 6), Vector2(11.5, 12), .5], SHADE],
		[[Vector2(11.5, 12), Vector2(16, 14.2), .5], SHADE],
		[[Vector2(11.5, 19.2), Vector2(20.5, 19.2), .55], SHADE],
		[[Vector2(1, 8), Vector2(4, 8), .6], INK],
		[[Vector2(.5, 12), Vector2(4, 12), .6], INK],
		[[Vector2(1, 16), Vector2(4, 16), .6], INK],
	]


## A stick of dynamite on the slant, a paper band round it, its fuse lit.
func _stick() -> Array:
	var along := Vector2(1, -1).normalized()
	var side := Vector2(along.y, -along.x)
	var mid := Vector2(9.5, 15)
	var half_long := 7.5
	var half_wide := 3.0
	var body := [
		mid - along * half_long - side * half_wide,
		mid + along * half_long - side * half_wide,
		mid + along * half_long + side * half_wide,
		mid - along * half_long + side * half_wide,
	]
	var band := [
		mid - along * 1.6 - side * half_wide,
		mid + along * 1.6 - side * half_wide,
		mid + along * 1.6 + side * half_wide,
		mid - along * 1.6 + side * half_wide,
	]
	var top := mid + along * half_long
	var fuse_end := top + Vector2(3.0, -2.5)
	return [
		[body, STICK],
		[
			[
				mid - along * (half_long - .6) + side * 1.8,
				mid + along * (half_long - .6) + side * 1.8,
				.5
			],
			STICK_DARK
		],
		[band, INK],
		[[top, fuse_end, .5], SHADE],
		[[fuse_end + Vector2(-2.2, 0), fuse_end + Vector2(2.2, 0), .55], SPARK],
		[[fuse_end + Vector2(0, -2.2), fuse_end + Vector2(0, 2.2), .55], SPARK],
		[[fuse_end + Vector2(-1.5, -1.5), fuse_end + Vector2(1.5, 1.5), .5], SPARK],
		[[fuse_end + Vector2(-1.5, 1.5), fuse_end + Vector2(1.5, -1.5), .5], SPARK],
		[[fuse_end, fuse_end, .8], SPARK_HOT],
	]
