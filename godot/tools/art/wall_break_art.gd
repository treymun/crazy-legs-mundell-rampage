## The walls that break (features/wall_breaks.gd), drawn for
## build_break_art.gd: every window tile shot out (<material>_brk: the glass
## gone, the room behind it dark, teeth of glass left in the frame and the
## muntins snapped; a lit window goes dark with it), the plank fence shot
## about (stockyard_hit: boards knocked out and split, holes) and the picture
## that stands in a fence cell broken through (stockyard_gap: the stumps, a
## board left each side, a rail hanging). Each is drawn over the tile it
## breaks from, so it keeps that tile's own brick, tin or planks around it.
extends RefCounted

const Paint := preload("res://tools/art/paint.gd")

## Each window tile: its broken tile, the glass inside its frame [x0, y0, x1,
## y1] (inclusive), the upright muntin's columns and the rail's rows (-1: none).
## The building materials' are build_building_tiles.gd's window, the bayou's
## build_bayou_art.gd's, the diner's build_speedway_art.gd's.
const WINDOWS := {
	"barn_win": ["barn_brk", [34, 38, 93, 82], [62, 64], [59, 61]],
	"tin_win": ["tin_brk", [34, 38, 93, 82], [62, 64], [59, 61]],
	"brick_win": ["brick_brk", [34, 38, 93, 82], [62, 64], [59, 61]],
	"plaster_win": ["plaster_brk", [34, 38, 93, 82], [62, 64], [59, 61]],
	"cinder_win": ["cinder_brk", [34, 38, 93, 82], [62, 64], [59, 61]],
	"office_wall_win": ["office_wall_brk", [34, 38, 93, 82], [62, 64], [59, 61]],
	"fair_booth_win": ["fair_booth_brk", [34, 38, 93, 82], [62, 64], [59, 61]],
	"fair_iron_win": ["fair_iron_brk", [34, 38, 93, 82], [62, 64], [59, 61]],
	"mill_tin_win": ["mill_tin_brk", [34, 38, 93, 82], [62, 64], [59, 61]],
	"quarry_iron_win": ["quarry_iron_brk", [34, 38, 93, 82], [62, 64], [59, 61]],
	"quarry_shed_win": ["quarry_shed_brk", [34, 38, 93, 82], [62, 64], [59, 61]],
	"bayou_tin_win": ["bayou_tin_brk", [34, 36, 93, 80], [62, 64], [-1, -1]],
	"bayou_shack_win": ["bayou_shack_brk", [34, 36, 93, 80], [62, 64], [-1, -1]],
	"bayou_cannery_win": ["bayou_cannery_brk", [34, 36, 93, 80], [62, 64], [-1, -1]],
	"diner_steel_win": ["diner_steel_brk", [24, 34, 103, 88], [62, 65], [-1, -1]],
	"trailer_window": ["trailer_brk", [14, 32, 113, 69], [-1, -1], [-1, -1]],
}
## The plank fence's boards (between its dark seams) and rails, in its tile.
const BOARDS := [
	[14, 21], [23, 30], [32, 39], [41, 48], [50, 57], [59, 66], [68, 75], [78, 85], [87, 94]
]
const RAILS := [[21, 32], [57, 68], [99, 110]]


## Draw them all: tiles into `tiles`, the gap's picture into `art`.
static func build(tiles: String, art: String) -> int:
	var count := 0
	var source := Paint.repo("assets/tiles")
	for name: String in WINDOWS:
		var whole := Paint.Sheet.load_png(source.path_join(name + ".png"))
		if whole == null:
			push_error("no tile " + name)
			continue
		var row: Array = WINDOWS[name]
		_shot_out(whole, row[1], row[2], row[3], name).save(
			tiles.path_join(String(row[0]) + ".png")
		)
		count += 1
	var fence := Paint.Sheet.load_png(source.path_join("stockyard.png"))
	_fence_hit(fence).save(tiles.path_join("stockyard_hit.png"))
	_fence_gap(fence).save(art.path_join("stockyard_gap.png"))
	return count + 2


static func _dice(text: String) -> RandomNumberGenerator:
	var dice := RandomNumberGenerator.new()
	var seed := 11
	for c in text.to_utf8_buffer():
		seed = (seed * 31 + c) % 1000003
	dice.seed = seed
	return dice


## The dark of a room seen through a hole, at row t (0 top, 1 bottom) of it.
static func _dark(t: float, dice: RandomNumberGenerator) -> Color:
	var c := Vector3(13, 10, 10).lerp(Vector3(30, 22, 18), t)
	var n := dice.randf_range(-2.5, 2.5)
	return Paint.rgb(c.x + n, c.y + n, c.z + n)


## A window shot out: the room behind it dark, glass teeth left round the
## frame catching the last light, the muntins snapped.
static func _shot_out(
	whole: Paint.Sheet, glass: Array, upright: Array, rail: Array, name: String
) -> Paint.Sheet:
	var s := whole.duplicate_sheet()
	var dice := _dice(name)
	var x0: int = glass[0]
	var y0: int = glass[1]
	var x1: int = glass[2]
	var y1: int = glass[3]
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			s.put(x, y, _dark(float(y - y0) / (y1 - y0), dice))
	# A curtain rag hanging in the dark, torn, at one side.
	var rag_x := x1 - 14 if dice.randf() < .5 else x0 + 6
	var rag_c := Vector3(86, 42, 34)
	for y in range(y0, y0 + dice.randi_range(14, 24)):
		var wide := 7 - (y - y0) / 5
		for x in range(rag_x, rag_x + maxi(2, wide)):
			var k := .55 + .2 * sin(x * 1.7)
			s.put(x, y, Paint.rgb(rag_c.x * k, rag_c.y * k, rag_c.z * k))
	# The teeth: each side of the frame keeps a jagged lip of glass.
	var edges := [
		[Vector2(x0, y0), Vector2(x1 + 1, y0), Vector2(0, 1)],
		[Vector2(x1 + 1, y0), Vector2(x1 + 1, y1 + 1), Vector2(-1, 0)],
		[Vector2(x1 + 1, y1 + 1), Vector2(x0, y1 + 1), Vector2(0, -1)],
		[Vector2(x0, y1 + 1), Vector2(x0, y0), Vector2(1, 0)],
	]
	var deep := minf(x1 - x0, y1 - y0) * .32
	for e: Array in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var inward: Vector2 = e[2]
		var pts := PackedVector2Array([a])
		var tips: Array = []
		var length := a.distance_to(b)
		var at := 0.0
		while at < length:
			at = minf(length, at + dice.randf_range(3.0, 7.0))
			var t := at / length
			# Deeper toward the corners, now and then a long spike.
			var corner := 1.0 - minf(t, 1.0 - t) * 2.0
			var depth := (
				dice.randf_range(0.0, 3.5) + corner * corner * deep * dice.randf_range(.5, 1.0)
			)
			if dice.randf() < .12:
				depth += deep * dice.randf_range(.4, .9)
			var p := a.lerp(b, t) + inward * depth
			pts.append(p)
			tips.append(p)
			if at < length:
				var back := a.lerp(b, minf(1.0, t + dice.randf_range(.01, .03)))
				pts.append(back + inward * dice.randf_range(0.0, 1.5))
		pts.append(b)
		Paint.polygon(s, pts, Paint.rgb(64, 82, 90))
		# A pale glint along each tooth's broken edge, a warm one now and then.
		for k in range(1, pts.size() - 1):
			var roll := dice.randf()
			if roll < .35:
				continue
			var c := Paint.rgb(160, 186, 186) if roll < .85 else Paint.rgb(222, 158, 96)
			Paint.line2(s, pts[k].x, pts[k].y, pts[k + 1].x, pts[k + 1].y, c)
		# Under it, the glass darkens toward the frame.
		for p: Vector2 in tips:
			var q := p - inward * 2.0
			s.put(int(q.x), int(q.y), Paint.rgb(40, 52, 58))
	# The muntins: the upright snapped, a stump at the top and at the bottom;
	# the rail kept on one side only.
	if upright[0] >= 0:
		var top_end := y0 + dice.randi_range(6, 16)
		var bottom_start := y1 - dice.randi_range(10, 24)
		for y in range(y0, y1 + 1):
			if y > top_end and y < bottom_start:
				continue
			for x in range(int(upright[0]), int(upright[1]) + 1):
				var o := (y * s.w + x) * 4
				s.put(x, y, Color8(whole.data[o], whole.data[o + 1], whole.data[o + 2]))
		s.put(int(upright[0]) + 1, top_end, Paint.rgb(214, 186, 140))
		s.put(int(upright[0]) + 1, bottom_start, Paint.rgb(214, 186, 140))
	if rail[0] >= 0:
		var keep_left := dice.randf() < .5
		var stub := dice.randi_range(8, 18)
		for y in range(int(rail[0]), int(rail[1]) + 1):
			for x in range(x0, x1 + 1):
				var kept := x < x0 + stub if keep_left else x > x1 - stub
				if not kept:
					continue
				var o := (y * s.w + x) * 4
				s.put(x, y, Color8(whole.data[o], whole.data[o + 1], whole.data[o + 2]))
	return s


## The plank fence shot about: boards knocked out (the dark behind showing
## between the rails), one broken off at the top, one at the bottom, one
## split, splinters pale at every break, and holes.
static func _fence_hit(whole: Paint.Sheet) -> Paint.Sheet:
	var s := whole.duplicate_sheet()
	var dice := _dice("stockyard_hit")
	# [board, from row, to row]: what of it is gone (rails stay).
	var gone := [[3, 0, 127], [8, 0, 127], [1, 0, 50], [6, 78, 127], [5, 34, 55]]
	var cut := Paint.Sheet.new(128, 128)
	for g: Array in gone:
		var board: Array = BOARDS[int(g[0])]
		var from: int = g[1]
		var to: int = g[2]
		var pts := PackedVector2Array()
		# A jagged break at each end that is not the tile's edge.
		var left := float(board[0]) - .5
		var right := float(board[1]) + 1.5
		if from <= 0:
			pts.append(Vector2(left, -1))
			pts.append(Vector2(right, -1))
		else:
			pts.append(Vector2(left, from + dice.randf_range(-4, 4)))
			for k in 3:
				pts.append(
					Vector2(lerpf(left, right, (k + 1) / 4.0), from + dice.randf_range(-7, 7))
				)
			pts.append(Vector2(right, from + dice.randf_range(-4, 4)))
		if to >= 127:
			pts.append(Vector2(right, 129))
			pts.append(Vector2(left, 129))
		else:
			pts.append(Vector2(right, to + dice.randf_range(-4, 4)))
			for k in 3:
				pts.append(Vector2(lerpf(right, left, (k + 1) / 4.0), to + dice.randf_range(-7, 7)))
			pts.append(Vector2(left, to + dice.randf_range(-4, 4)))
		Paint.polygon(cut, pts, Color.WHITE)
	for y in 128:
		var on_rail := false
		for r: Array in RAILS:
			on_rail = on_rail or (y >= int(r[0]) and y <= int(r[1]))
		for x in 128:
			if cut.alpha_at(x, y) > 0 and not on_rail:
				s.put(x, y, _dark(y / 127.0, dice))
	# Splinters where a board tore across (pale), its long sides in shadow.
	for y in 128:
		for x in 128:
			if cut.alpha_at(x, y) > 0:
				continue
			for d: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var q := Vector2i(x, y) + d
				if q.x < 0 or q.y < 0 or q.x > 127 or q.y > 127 or cut.alpha_at(q.x, q.y) == 0:
					continue
				var o := (y * 128 + x) * 4
				if d.x == 0 and dice.randf() < .6:
					s.put(x, y, Paint.rgb(212, 182, 134))
				elif d.x != 0:
					s.put(x, y, Paint.rgb(s.data[o] * .6, s.data[o + 1] * .55, s.data[o + 2] * .5))
				break
	# Holes punched through the boards still up, each with a dark ring.
	for k in 9:
		var hx := dice.randi_range(4, 123)
		var hy := dice.randi_range(4, 123)
		if cut.alpha_at(hx, hy) > 0:
			continue
		for y in range(hy - 2, hy + 3):
			for x in range(hx - 2, hx + 3):
				var d := Vector2(x - hx, y - hy).length()
				var o := (clampi(y, 0, 127) * 128 + clampi(x, 0, 127)) * 4
				if d <= 1.0:
					s.put(x, y, Paint.rgb(16, 12, 10))
				elif d <= 2.2:
					s.put(x, y, Paint.rgb(s.data[o] * .55, s.data[o + 1] * .5, s.data[o + 2] * .45))
		s.put(hx + 2, hy - 1, Paint.rgb(212, 182, 134))
	return s


## What stands in a fence cell broken through, 64 x 52 (a cell wide and .8
## tall): stumps across the bottom, a board left standing at each side, the
## middle rail snapped and hanging from the left, a board hanging off it.
static func _fence_gap(whole: Paint.Sheet) -> Paint.Sheet:
	var w := 64
	var h := 52
	var dice := _dice("stockyard_gap")
	var full := Paint.Sheet.new(w, h)
	# The fence's own planks, the lower rows of its tile, half size.
	for y in h:
		for x in w:
			var o := ((24 + y * 2) * 128 + x * 2) * 4
			full.put(x, y, Color8(whole.data[o], whole.data[o + 1], whole.data[o + 2]))
	var keep := Paint.Sheet.new(w, h)
	var white := Color.WHITE
	# A board each side, broken off high on the left, lower on the right.
	Paint.polygon(
		keep,
		PackedVector2Array(
			[
				Vector2(0, 3),
				Vector2(4, 1),
				Vector2(6, 5),
				Vector2(9, 2),
				Vector2(9, h),
				Vector2(0, h)
			]
		),
		white
	)
	Paint.polygon(
		keep,
		PackedVector2Array(
			[Vector2(9, 22), Vector2(11, 17), Vector2(13, 24), Vector2(13, h), Vector2(9, h)]
		),
		white
	)
	Paint.polygon(
		keep,
		PackedVector2Array(
			[
				Vector2(54, 9),
				Vector2(57, 13),
				Vector2(60, 7),
				Vector2(64, 10),
				Vector2(64, h),
				Vector2(54, h)
			]
		),
		white
	)
	Paint.polygon(
		keep,
		PackedVector2Array(
			[Vector2(50, 30), Vector2(52, 26), Vector2(54, 31), Vector2(54, h), Vector2(50, h)]
		),
		white
	)
	# Stumps between them, each its own height, splintered to a point or two.
	var x := 13
	while x < 50:
		var wide := 4 if dice.randf() < .7 else 5
		var top := h - dice.randi_range(4, 15)
		Paint.polygon(
			keep,
			PackedVector2Array(
				[
					Vector2(x, top + dice.randi_range(0, 3)),
					Vector2(x + wide * .5, top - dice.randi_range(0, 4)),
					Vector2(x + wide, top + dice.randi_range(0, 3)),
					Vector2(x + wide, h),
					Vector2(x, h)
				]
			),
			white
		)
		x += wide + (1 if dice.randf() < .3 else 0)
	# The lower rail: kept each side, gone in the middle.
	for y in range(37, 44):
		for xx in range(0, w):
			if xx < 17 or xx > 45:
				keep.put(xx, y, white)
	var out := Paint.Sheet.new(w, h)
	for y in h:
		for xx in w:
			if keep.alpha_at(xx, y) > 0:
				var o := (y * w + xx) * 4
				out.put(xx, y, Color8(full.data[o], full.data[o + 1], full.data[o + 2]))
	# The middle rail snapped: its left half hangs, its right a stub.
	var rail := Paint.rgb(64, 52, 40)
	var rail_top := Paint.rgb(122, 104, 82)
	Paint.polygon(
		out,
		PackedVector2Array([Vector2(0, 16), Vector2(24, 26), Vector2(23, 31), Vector2(0, 22)]),
		rail
	)
	Paint.line2(out, 0, 16, 24, 26, rail_top)
	Paint.polygon(
		out,
		PackedVector2Array([Vector2(47, 17), Vector2(64, 16), Vector2(64, 22), Vector2(46, 22)]),
		rail
	)
	Paint.line2(out, 47, 16, 63, 16, rail_top)
	# A board hanging off the rail by one nail, swung down and out.
	var plank := Paint.rgb(108, 88, 64)
	Paint.polygon(
		out,
		PackedVector2Array([Vector2(15, 20), Vector2(19, 19), Vector2(30, 45), Vector2(26, 47)]),
		plank
	)
	Paint.line2(out, 16, 20, 27, 46, Paint.rgb(150, 124, 92))
	out.put(17, 21, Paint.rgb(40, 34, 30))
	# Every broken edge pale with splinters, the rest of the outline dark.
	var edge := out.duplicate_sheet()
	for y in h:
		for xx in w:
			if out.alpha_at(xx, y) == 0:
				continue
			var open := 0
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1)]:
				var q := Vector2i(xx, y) + d
				if q.x >= 0 and q.x < w and q.y >= 0 and out.alpha_at(q.x, q.y) == 0:
					open += 1
			if open > 0:
				var c := Paint.rgb(214, 186, 140) if dice.randf() < .4 else Paint.rgb(48, 38, 30)
				edge.put(xx, y, c)
	return Paint.digitize(edge, 4.0)
