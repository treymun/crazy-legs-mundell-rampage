## The bits a hit knocks loose (features/hit_reads.gd): each kind's hat or
## helmet as it tumbles off a head (fx_hat_<name>_0 side on, _1 tipped over),
## and the weapons an arm hit makes a hand drop (fx_drop_long, a long gun;
## fx_drop_pistol; fx_drop_tool, a wrench or a bar). Small, hard edged,
## committed to the VGA palette like the breakables' bits.
##
##   godot --headless --path godot --script res://tools/art/build_hit_art.gd [-- out=<dir>]
##
## Then run tools/pack_assets.gd.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")

## Each hat: its shape and colours [light, mid, dark, band].
const HATS := {
	"straw": ["brim", [236, 210, 140], [204, 172, 98], [124, 96, 52], [150, 40, 30]],
	"felt": ["brim", [150, 110, 72], [112, 78, 48], [58, 40, 26], [40, 28, 20]],
	"black": ["brim", [92, 86, 80], [58, 54, 50], [26, 24, 22], [120, 96, 60]],
	"grey": ["cap", [170, 170, 160], [128, 130, 120], [66, 68, 62], [220, 220, 210]],
	"tan": ["cap", [214, 184, 132], [176, 146, 98], [96, 76, 48], [236, 224, 196]],
	"green": ["cap", [110, 150, 80], [70, 110, 52], [34, 58, 26], [230, 226, 200]],
	"red": ["cap", [230, 80, 60], [184, 42, 32], [92, 20, 16], [240, 236, 220]],
	"brown": ["cap", [156, 112, 72], [118, 82, 50], [62, 42, 26], [180, 150, 110]],
	"dark": ["cap", [96, 96, 104], [62, 62, 70], [30, 30, 36], [140, 120, 80]],
	"helmet": ["helmet", [200, 204, 206], [134, 138, 142], [62, 64, 68], [60, 210, 120]],
}


func _init() -> void:
	var out := Paint.repo("assets/art")
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	var count := 0
	for hat: String in HATS:
		for n in 2:
			_hat(hat, n).save(out.path_join("fx_hat_%s_%d.png" % [hat, n]))
			count += 1
	for held: String in ["long", "pistol", "tool"]:
		_held(held).save(out.path_join("fx_drop_%s.png" % held))
		count += 1
	print("hit art: %d written to %s" % [count, out])
	quit()


static func _c(c: Array, k := 1.0) -> Color:
	return Paint.rgb(float(c[0]) * k, float(c[1]) * k, float(c[2]) * k)


## A hat: side on (n 0), or tipped over showing its top (n 1).
func _hat(name: String, n: int) -> Paint.Sheet:
	var spec: Array = HATS[name]
	var light := _c(spec[1])
	var mid := _c(spec[2])
	var dark := _c(spec[3])
	var band := _c(spec[4])
	var s: Paint.Sheet
	match String(spec[0]):
		"brim":
			s = Paint.Sheet.new(22, 11)
			if n == 0:
				# Brim curled up at the ends, crown pinched at the top.
				Paint.ellipse(s, 0, 6, 21, 10, mid)
				Paint.ellipse(s, 0, 4, 3, 8, mid)
				Paint.ellipse(s, 18, 4, 21, 8, mid)
				Paint.polygon(
					s,
					PackedVector2Array(
						[
							Vector2(5, 8),
							Vector2(6, 2),
							Vector2(9, 0),
							Vector2(11, 1),
							Vector2(13, 0),
							Vector2(16, 2),
							Vector2(17, 8)
						]
					),
					mid
				)
				Paint.line2(s, 7, 2, 10, 1, light)
				Paint.rect(s, 6, 6, 16, 7, band)
				Paint.line2(s, 1, 9, 20, 9, dark)
			else:
				# Tipped: the brim's round and the crown's top in it.
				Paint.ellipse(s, 0, 1, 21, 10, mid)
				Paint.ellipse(s, 5, 2, 16, 8, dark)
				Paint.ellipse(s, 6, 3, 15, 7, light)
				Paint.line2(s, 9, 5, 12, 4, mid)
		"cap":
			s = Paint.Sheet.new(17, 9)
			if n == 0:
				# Crown and bill.
				Paint.ellipse(s, 1, 0, 12, 13, mid)
				Paint.rect(s, 0, 7, 16, 8, Color(0, 0, 0, 0))
				Paint.polygon(
					s,
					PackedVector2Array(
						[Vector2(10, 6), Vector2(16, 6), Vector2(16, 8), Vector2(9, 8)]
					),
					dark
				)
				Paint.line2(s, 3, 2, 7, 1, light)
				Paint.rect(s, 4, 3, 7, 5, band)
				Paint.rect(s, 1, 6, 11, 6, dark)
			else:
				# From above: the round crown, its button, the bill out front.
				Paint.ellipse(s, 0, 0, 11, 8, mid)
				Paint.polygon(
					s,
					PackedVector2Array(
						[Vector2(10, 2), Vector2(16, 3), Vector2(16, 6), Vector2(10, 7)]
					),
					dark
				)
				Paint.line2(s, 5, 0, 5, 8, dark)
				Paint.point(s, 5, 4, light)
				Paint.line2(s, 2, 2, 4, 1, light)
		_:
			s = Paint.Sheet.new(16, 10)
			if n == 0:
				# A tin dome with a rim and the goggles' strap.
				Paint.ellipse(s, 1, 0, 14, 15, mid)
				Paint.rect(s, 0, 8, 15, 9, Color(0, 0, 0, 0))
				Paint.rect(s, 0, 7, 15, 8, dark)
				Paint.line2(s, 3, 3, 7, 1, light)
				Paint.rect(s, 9, 4, 12, 5, band)
				Paint.point(s, 4, 5, dark)
				Paint.point(s, 8, 6, dark)
			else:
				Paint.ellipse(s, 0, 0, 15, 9, dark)
				Paint.ellipse(s, 2, 1, 13, 8, mid)
				Paint.ellipse(s, 4, 2, 9, 5, light)
				Paint.point(s, 11, 6, band)
	_rim(s, dark)
	return Paint.digitize(s, 4.0)


## A weapon lying on the ground, side on.
func _held(name: String) -> Paint.Sheet:
	var wood := Paint.rgb(140, 92, 50)
	var wood_light := Paint.rgb(184, 132, 78)
	var steel := Paint.rgb(96, 100, 106)
	var steel_light := Paint.rgb(170, 176, 182)
	var dark := Paint.rgb(34, 30, 28)
	var s: Paint.Sheet
	match name:
		"long":
			s = Paint.Sheet.new(28, 6)
			Paint.polygon(
				s,
				PackedVector2Array(
					[Vector2(0, 2), Vector2(9, 1), Vector2(12, 2), Vector2(12, 4), Vector2(0, 5)]
				),
				wood
			)
			Paint.line2(s, 1, 2, 9, 2, wood_light)
			Paint.rect(s, 11, 1, 27, 2, steel)
			Paint.line2(s, 12, 1, 26, 1, steel_light)
			Paint.rect(s, 13, 3, 20, 3, wood)
		"pistol":
			s = Paint.Sheet.new(13, 8)
			Paint.rect(s, 2, 1, 12, 3, steel)
			Paint.line2(s, 3, 1, 11, 1, steel_light)
			Paint.polygon(
				s,
				PackedVector2Array([Vector2(2, 3), Vector2(6, 3), Vector2(5, 7), Vector2(1, 7)]),
				wood
			)
			Paint.point(s, 6, 4, dark)
		_:
			s = Paint.Sheet.new(16, 6)
			Paint.rect(s, 0, 2, 11, 3, steel)
			Paint.line2(s, 1, 2, 10, 2, steel_light)
			Paint.polygon(
				s,
				PackedVector2Array(
					[
						Vector2(11, 0),
						Vector2(15, 0),
						Vector2(15, 2),
						Vector2(13, 2),
						Vector2(13, 3),
						Vector2(15, 3),
						Vector2(15, 5),
						Vector2(11, 5)
					]
				),
				steel
			)
	_rim(s, dark)
	return Paint.digitize(s, 4.0)


## Darken the lower and right edge of what is drawn, as the sprites' rim does.
static func _rim(s: Paint.Sheet, dark: Color) -> void:
	var edge: Array = []
	for y in s.h:
		for x in s.w:
			if s.alpha_at(x, y) == 0:
				continue
			if (
				y == s.h - 1
				or x == s.w - 1
				or s.alpha_at(x, y + 1) == 0
				or s.alpha_at(x + 1, y) == 0
			):
				edge.append(Vector2i(x, y))
	for p: Vector2i in edge:
		s.put(p.x, p.y, dark)
