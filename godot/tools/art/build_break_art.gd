## The pictures things leave when they break (features/breakables.gd): the
## bits that fly and stay (fx_brk_<stuff>_<n>: splinters, planks, shards of
## glass and clay, torn tin, straw, stuffing, rubber, alien muck), and each
## breakable sign shot up (<sign>_shot: bullet holes through to the planks
## behind and a corner knocked off, its words left readable). And the walls
## that break (features/wall_breaks.gd): each window tile shot out
## (<material>_brk in assets/tiles: the glass gone dark, teeth of it left in
## the frame, a muntin snapped), the plank fence knocked about
## (stockyard_hit: boards out and split) and the gap a fence cell leaves when
## it goes through (stockyard_gap, a picture standing in the gap: the stumps,
## a board each side, a rail hanging).
##
##   godot --headless --path godot --script res://tools/art/build_break_art.gd [-- out=<dir>]
##
## The broken props themselves are modelled in Blender
## (scripts/blender/props_broken.py, built by build_town_props.gd). Then run
## tools/pack_assets.gd.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")
const WallArt := preload("res://tools/art/wall_break_art.gd")

## The signs that can be shot up (data/tuning/breakables.cfg lists them too).
const SIGNS := [
	"wanted_poster",
	"speedway_ad_oil",
	"speedway_ad_tires",
	"speedway_ad_chaw",
	"speedway_ad_bait",
	"bayou_gator_sign",
	"bayou_keepout_sign",
	"bayou_nofeed_sign",
	"fair_ticket_rule",
	"fair_redemption",
	"mill_pump_sign",
	"quarry_ledger",
	"ship_wanted",
	"gas_n_gut_sign",
	"lazy_eight_sign",
	"bait_ammo_sign",
	"hub_road_dept",
]

## Each kind of bit: its colours [light, mid, dark] and its two shapes.
const STUFF := {
	"wood": [[186, 140, 92], [132, 92, 56], [70, 46, 28]],
	"grey": [[184, 176, 160], [130, 122, 108], [70, 66, 58]],
	"char": [[96, 72, 52], [56, 42, 32], [24, 20, 18]],
	"glass": [[220, 240, 236], [150, 196, 190], [70, 100, 100]],
	"clay": [[226, 208, 170], [186, 160, 116], [96, 80, 60]],
	"tin": [[196, 198, 200], [128, 130, 132], [62, 62, 64]],
	"redtin": [[226, 88, 64], [170, 38, 30], [70, 20, 18]],
	"orange": [[250, 160, 70], [226, 110, 30], [110, 50, 20]],
	"straw": [[232, 204, 120], [196, 160, 84], [120, 92, 44]],
	"stuffing": [[250, 248, 240], [214, 210, 200], [140, 136, 128]],
	"rubber": [[250, 120, 120], [220, 50, 50], [110, 20, 20]],
	"pink": [[250, 160, 196], [236, 104, 150], [130, 50, 80]],
	"goo": [[170, 255, 190], [70, 190, 110], [20, 80, 40]],
	"plastic": [[240, 240, 236], [200, 200, 196], [96, 96, 96]],
}

var count_walls := 0


func _init() -> void:
	var out := Paint.repo("assets/art")
	var tiles := Paint.repo("assets/tiles")
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
			tiles = out
	DirAccess.make_dir_recursive_absolute(out)
	count_walls = WallArt.build(tiles, out)
	var count := 0
	for stuff: String in STUFF:
		for n in 2:
			_bit(stuff, n).save(out.path_join("fx_brk_%s_%d.png" % [stuff, n]))
			count += 1
	for sign: String in SIGNS:
		var path := Paint.repo("assets/art/%s.png" % sign)
		var whole := Paint.Sheet.load_png(path)
		if whole == null:
			push_error("no picture " + path)
			continue
		_shot_up(whole, sign).save(out.path_join("%s_shot.png" % sign))
		count += 1
	print("break art: %d written to %s, %d wall pictures" % [count, out, count_walls])
	quit()


static func _seed_of(text: String) -> int:
	var seed := 7
	for c in text.to_utf8_buffer():
		seed = (seed * 31 + c) % 1000003
	return seed


static func _colour(c: Array, k := 1.0) -> Color:
	return Paint.rgb(float(c[0]) * k, float(c[1]) * k, float(c[2]) * k)


## One bit, drawn small: a plank or a sliver, a shard, a tuft.
func _bit(stuff: String, n: int) -> Paint.Sheet:
	var c: Array = STUFF[stuff]
	var light := _colour(c[0])
	var mid := _colour(c[1])
	var dark := _colour(c[2])
	var s: Paint.Sheet
	match stuff:
		"wood", "grey", "char":
			if n == 0:
				# A broken plank: grain along it, one end splintered.
				s = Paint.Sheet.new(16, 5)
				Paint.polygon(
					s,
					PackedVector2Array(
						[
							Vector2(0, 1),
							Vector2(12, 0),
							Vector2(15, 1),
							Vector2(13, 2),
							Vector2(16, 3),
							Vector2(12, 4),
							Vector2(0, 4)
						]
					),
					mid
				)
				Paint.line2(s, 1, 2, 11, 1.6, light)
				Paint.line2(s, 0, 4, 12, 4, dark)
			else:
				# A sliver, at a slant.
				s = Paint.Sheet.new(10, 6)
				Paint.polygon(
					s,
					PackedVector2Array(
						[Vector2(0, 5), Vector2(7, 0), Vector2(10, 0), Vector2(3, 6), Vector2(0, 6)]
					),
					mid
				)
				Paint.line2(s, 1, 5, 7, 1, light)
		"glass", "clay", "tin", "redtin", "orange", "plastic", "pink", "rubber":
			# A shard or a torn scrap: a jagged three or four sided piece.
			s = Paint.Sheet.new(8, 7) if n == 0 else Paint.Sheet.new(7, 6)
			var pts := (
				PackedVector2Array([Vector2(0, 6), Vector2(3, 0), Vector2(8, 3), Vector2(5, 7)])
				if n == 0
				else PackedVector2Array([Vector2(0, 2), Vector2(7, 0), Vector2(4, 6)])
			)
			Paint.polygon(s, pts, mid)
			Paint.line2(s, pts[0].x, pts[0].y - 1, pts[1].x, pts[1].y + 1, light)
		"straw":
			# A wisp: a few crossed stalks.
			s = Paint.Sheet.new(12, 6)
			for k in 4:
				var y0 := 1.0 + k + (n * 2 + k) % 2
				Paint.line2(s, 0 + k, y0, 11 - k, 5.0 - y0 * .5, light if k % 2 else mid)
		_:
			# Stuffing and muck: a soft lump with a lighter top.
			s = Paint.Sheet.new(7, 6) if n == 0 else Paint.Sheet.new(6, 5)
			Paint.ellipse(s, 0, 0, s.w - 1, s.h - 1, mid)
			Paint.ellipse(s, 1, 0, s.w - 3, s.h - 3, light)
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


## The sign with bullet holes through it and a corner knocked off: the holes
## and the gap show what is behind (its plank backing), splinters at the edges.
func _shot_up(whole: Paint.Sheet, name: String) -> Paint.Sheet:
	var s := whole.duplicate_sheet()
	var dice := RandomNumberGenerator.new()
	dice.seed = _seed_of(name)
	var pale := Paint.rgb(214, 186, 140)
	# A corner knocked off with a jagged edge.
	var corner := dice.randi() % 4
	var cx := 0.0 if corner % 2 == 0 else float(s.w)
	var cy := 0.0 if corner < 2 else float(s.h)
	var leg_x := s.w * dice.randf_range(.14, .22)
	var leg_y := s.h * dice.randf_range(.22, .34)
	var sx := 1.0 if corner % 2 == 0 else -1.0
	var sy := 1.0 if corner < 2 else -1.0
	var gap := PackedVector2Array([Vector2(cx - sx * 2, cy - sy * 2)])
	gap.append(Vector2(cx + sx * leg_x, cy - sy * 2))
	for k in range(1, 5):
		var t := k / 5.0
		var jag := dice.randf_range(-2.0, 2.0)
		gap.append(Vector2(cx + sx * (leg_x * (1.0 - t) + jag), cy + sy * (leg_y * t + jag * .5)))
	gap.append(Vector2(cx - sx * 2, cy + sy * leg_y))
	var cut := Paint.Sheet.new(s.w, s.h)
	Paint.polygon(cut, gap, Color.WHITE)
	for y in s.h:
		for x in s.w:
			if cut.alpha_at(x, y) > 0:
				s.put(x, y, Color(0, 0, 0, 0))
	# Holes: shot through, a dark ring round each and a pale splinter or two.
	var holes := 5 + dice.randi() % 3
	var made := 0
	var tries := 0
	while made < holes and tries < 200:
		tries += 1
		var hx := dice.randf_range(3.0, s.w - 4.0)
		var hy := dice.randf_range(3.0, s.h - 4.0)
		if s.alpha_at(int(hx), int(hy)) < 200:
			continue
		var r := dice.randf_range(.8, 1.6) * clampf(s.h / 40.0, .8, 1.6)
		for y in range(int(hy - r - 2), int(hy + r + 3)):
			for x in range(int(hx - r - 2), int(hx + r + 3)):
				if x < 0 or y < 0 or x >= s.w or y >= s.h or s.alpha_at(x, y) == 0:
					continue
				var d := Vector2(x + .5 - hx, y + .5 - hy).length()
				if d <= r:
					s.put(x, y, Color(0, 0, 0, 0))
				elif d <= r + 1.3:
					var o := (y * s.w + x) * 4
					s.put(x, y, Paint.rgb(s.data[o] * .45, s.data[o + 1] * .42, s.data[o + 2] * .4))
		var a := dice.randf() * TAU
		s.put(int(hx + cos(a) * (r + 1.5)), int(hy + sin(a) * (r + 1.5)), pale)
		made += 1
	# The torn edge of the corner: darkened, with splinters.
	for y in s.h:
		for x in s.w:
			if s.alpha_at(x, y) == 0:
				continue
			var near := false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q := Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < s.w and q.y < s.h and cut.alpha_at(q.x, q.y) > 0:
					near = true
			if near:
				var o := (y * s.w + x) * 4
				if dice.randf() < .3:
					s.put(x, y, pale)
				else:
					s.put(x, y, Paint.rgb(s.data[o] * .5, s.data[o + 1] * .46, s.data[o + 2] * .42))
	return Paint.digitize(s, 0.0)
