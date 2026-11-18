## The walls that break (features/wall_breaks.gd), drawn for
## build_break_art.gd: every window tile shot once (<material>_crk, a lit
## one's <material>_lck: the glass cracked from a hole) and shot out (<material>_brk: the glass
## gone, the room behind it dark, teeth of glass left in the frame and the
## muntins snapped; a lit window goes dark with it), the plank fence shot
## about (stockyard_hit: boards knocked out and split, holes) and the picture
## that stands in a fence cell broken through (stockyard_gap: the stumps, a
## board left each side, a rail hanging). Each is drawn over the tile it
## breaks from, so it keeps that tile's own brick, tin or planks around it.
extends RefCounted

const Paint := preload("res://tools/art/paint.gd")
const MarkArt := preload("res://tools/art/wall_mark_art.gd")

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
## The plank walls that break too (breakables.cfg [fence.wood], [fence.barn],
## [fence.bayou_shack]: a shed's wall, a plank fence): each shot about
## (<tile>_hit: its upright planks knocked out, the dark behind them) and the
## stumps left standing when it goes through (<tile>_gap), from its own tile.
const PLANK_WALLS := ["wood", "barn", "bayou_shack"]
## Their planks: eight up each tile, no rails.
const PLANKS := [[1, 14], [17, 30], [33, 46], [49, 62], [65, 78], [81, 94], [97, 110], [113, 126]]


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
		# Shot out by a blast: its frame torn out too (<material>_bst).
		_blasted(whole, row[1], name).save(
			tiles.path_join(String(row[0]).trim_suffix("_brk") + "_bst.png")
		)
		count += 2
		# Shot once: the glass cracked from the hole, still in its frame
		# (<material>_crk; a lit window's <material>_lck, still lit).
		var base := String(row[0]).trim_suffix("_brk")
		_cracked(whole, row[1], name).save(tiles.path_join(base + "_crk.png"))
		count += 1
		var lit_path := source.path_join(base + "_lit.png")
		var lit := Paint.Sheet.load_png(lit_path) if FileAccess.file_exists(lit_path) else null
		if lit != null:
			_cracked(lit, row[1], base + "_lit").save(tiles.path_join(base + "_lck.png"))
			count += 1
	var fence := Paint.Sheet.load_png(source.path_join("stockyard.png"))
	_fence_hit(fence).save(tiles.path_join("stockyard_hit.png"))
	for k in 3:
		_fence_gap(fence, true, "stockyard_gap", k).save(art.path_join(_gap_name("stockyard", k)))
	# The 5v5 maps' boarded cover (data/tuning/breakables.cfg [fence.cover_boards]):
	# the same planks gone grey, a fresh pine brace nailed across, so a
	# player can tell what will shoot through from what will not.
	var boards := _boarded(fence)
	boards.save(tiles.path_join("cover_boards.png"))
	_fence_hit(boards).save(tiles.path_join("cover_boards_hit.png"))
	_fence_gap(boards).save(art.path_join("cover_boards_gap.png"))
	for name: String in PLANK_WALLS:
		var wall := Paint.Sheet.load_png(source.path_join(name + ".png"))
		_fence_hit(wall, PLANKS, [], name + "_hit").save(tiles.path_join(name + "_hit.png"))
		for k in 3:
			_fence_gap(wall, false, name + "_gap", k).save(art.path_join(_gap_name(name, k)))
	count += MarkArt.build(art)
	return count + 7 + PLANK_WALLS.size() * 4


## A gap's picture: <tile>_gap, then _gap_1 and _gap_2 (wall_breaks.gd picks
## one by the cell).
static func _gap_name(tile: String, k: int) -> String:
	return "%s_gap%s.png" % [tile, "" if k == 0 else "_%d" % k]


## The plank fence boarded up: its boards weathered grey, and two fresh pine
## braces nailed across them corner to corner (an X), nail heads dark.
static func _boarded(whole: Paint.Sheet) -> Paint.Sheet:
	var s := whole.duplicate_sheet()
	var dice := _dice("cover_boards")
	for y in 128:
		for x in 128:
			var o := (y * 128 + x) * 4
			var grey := (s.data[o] + s.data[o + 1] + s.data[o + 2]) / 3.0
			s.put(
				x,
				y,
				Paint.rgb(
					lerpf(s.data[o], grey, .55) * .92,
					lerpf(s.data[o + 1], grey, .55) * .92,
					lerpf(s.data[o + 2], grey, .45) * .9
				)
			)
	for brace: Array in [[Vector2(6, 118), Vector2(122, 10)], [Vector2(6, 10), Vector2(122, 118)]]:
		var a: Vector2 = brace[0]
		var b: Vector2 = brace[1]
		var across := (b - a).normalized().orthogonal() * 6.5
		var board := PackedVector2Array([a + across, b + across, b - across, a - across])
		var mask := Paint.Sheet.new(128, 128)
		Paint.polygon(mask, board, Color.WHITE)
		for y in 128:
			for x in 128:
				if mask.alpha_at(x, y) == 0:
					continue
				# Pine with its grain along the board, darker at its edges.
				var along := Vector2(x, y).dot((b - a).normalized())
				var edge := absf(
					Vector2(x, y).dot(across.normalized()) - a.dot(across.normalized())
				)
				var shade := 1.0 - .28 * smoothstep(4.0, 6.5, edge)
				var grain := .93 + .07 * sin(along * .9 + dice.randf() * .6)
				s.put(
					x, y, Paint.rgb(214 * shade * grain, 172 * shade * grain, 112 * shade * grain)
				)
		for k in 5:
			var at := a.lerp(b, (k + .5) / 5.0)
			s.put(int(at.x), int(at.y), Paint.rgb(34, 28, 24))
			s.put(int(at.x) + 1, int(at.y), Paint.rgb(70, 60, 52))
	return s


static func _dice(text: String) -> RandomNumberGenerator:
	var dice := RandomNumberGenerator.new()
	var seed := 11
	for c in text.to_utf8_buffer():
		seed = (seed * 31 + c) % 1000003
	dice.seed = seed
	return dice


## A window's glass shot once: a hole where the round went through and the
## cracks running from it to the frame, a pale line with its shadow beside
## it, and a ring or two round the hole (a spider web), the rest of the pane
## as it was.
static func _cracked(whole: Paint.Sheet, glass: Array, name: String) -> Paint.Sheet:
	var s := whole.duplicate_sheet()
	var dice := _dice(name + "_crk")
	var x0: int = glass[0]
	var y0: int = glass[1]
	var x1: int = glass[2]
	var y1: int = glass[3]
	var hit := Vector2(
		lerpf(x0, x1, dice.randf_range(.3, .7)), lerpf(y0, y1, dice.randf_range(.3, .65))
	)
	var pale := Paint.rgb(226, 234, 236)
	var shade := Paint.rgb(36, 40, 46)
	var inside := func(x: int, y: int) -> bool: return x >= x0 and x <= x1 and y >= y0 and y <= y1
	# The rays: jagged, each to the frame.
	var rays := 7 + dice.randi() % 3
	for k in rays:
		var a := TAU * (k + dice.randf_range(-.3, .3)) / rays
		var at := hit
		var reach := 0.0
		while reach < 80.0:
			a += dice.randf_range(-.25, .25)
			var step := dice.randf_range(3.0, 6.0)
			var to := at + Vector2(cos(a), sin(a)) * step
			for n in int(step * 2.0):
				var q := at.lerp(to, n / (step * 2.0))
				if not inside.call(int(q.x), int(q.y)):
					reach = 999.0
					break
				s.put(int(q.x), int(q.y), pale)
				var side := Vector2(-sin(a), cos(a))
				var b := q + side
				if inside.call(int(b.x), int(b.y)):
					s.put(int(b.x), int(b.y), shade)
			at = to
			reach += step
	# The web: broken rings round the hole.
	for ring: float in [5.0, 10.0 + dice.randf_range(0.0, 3.0)]:
		for n in 40:
			if dice.randf() < .35:
				continue
			var a := TAU * n / 40.0
			var q := hit + Vector2(cos(a), sin(a)) * ring
			if inside.call(int(q.x), int(q.y)):
				s.put(int(q.x), int(q.y), pale)
	# The hole itself.
	for y in range(int(hit.y) - 2, int(hit.y) + 3):
		for x in range(int(hit.x) - 2, int(hit.x) + 3):
			var d := Vector2(x + .5, y + .5).distance_to(hit)
			if d < 1.6:
				s.put(x, y, Paint.rgb(14, 12, 12))
			elif d < 2.6:
				s.put(x, y, pale)
	return Paint.digitize(s, 0.0)


## A window shot out by a blast: the glass, its muntins and most of its
## frame gone, the room behind dark, the opening torn ragged past where the
## frame was, a stub of the sill and of the frame at a corner, splinters pale
## at every break, the wall round it sooted (fading out before the window
## band's edge, so a band laid over a wall shows no line).
static func _blasted(whole: Paint.Sheet, glass: Array, name: String) -> Paint.Sheet:
	var s := whole.duplicate_sheet()
	var dice := _dice(name + "_bst")
	var x0: int = glass[0] - 5
	var y0: int = glass[1] - 5
	var x1: int = glass[2] + 5
	var y1: int = glass[3] + 5
	var hole := Paint.Sheet.new(128, 128)
	var pts := PackedVector2Array()
	var corners: Array[Vector2] = [
		Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)
	]
	for k in 4:
		var a := corners[k]
		var b := corners[(k + 1) % 4]
		var out := (b - a).normalized().orthogonal() * -1.0
		var steps := int(a.distance_to(b) / 4.0)
		for i in steps:
			var p := a.lerp(b, float(i) / steps)
			pts.append(p + out * dice.randf_range(-2.0, 3.5))
	Paint.polygon(hole, pts, Color.WHITE)
	# The sill's stub along the bottom on one side, a frame stub at a corner.
	var left := dice.randf() < .5
	var stub := Rect2(x0 if left else x1 - 22, y1 - 4, 22, 5)
	var post := Rect2(x1 - 5 if left else x0, y0, 5, dice.randi_range(10, 20))
	var lo_v := 28
	var hi_v := 96
	for y in 128:
		for x in 128:
			var o := (y * 128 + x) * 4
			var p := Vector2(x + .5, y + .5)
			var kept := stub.has_point(p) or post.has_point(p)
			if hole.alpha_at(x, y) > 0 and not kept:
				s.put(x, y, _dark(clampf(float(y - y0) / (y1 - y0), 0.0, 1.0), dice))
				continue
			# Soot round the opening, dithered, fading out toward the band's
			# edges (rows lo_v and hi_v on a repeating wall).
			var d := maxf(maxf(x0 - p.x, p.x - x1), maxf(y0 - p.y, p.y - y1))
			var fade := clampf(minf(y - lo_v, hi_v - y) / 8.0, 0.0, 1.0)
			var soot := clampf(1.0 - d / 15.0, 0.0, 1.0) * .85 * fade
			if kept:
				soot = .25
			if soot > 0.0 and ((x + y) % 2 == 0 or soot > .45):
				var k := 1.0 - soot
				s.put(x, y, Paint.rgb(s.data[o] * k, s.data[o + 1] * k, s.data[o + 2] * k))
	# Splinters pale on the broken edges.
	for y in range(1, 127):
		for x in range(1, 127):
			if hole.alpha_at(x, y) > 0:
				continue
			var near_hole := (
				hole.alpha_at(x + 1, y) > 0
				or hole.alpha_at(x - 1, y) > 0
				or hole.alpha_at(x, y + 1) > 0
				or hole.alpha_at(x, y - 1) > 0
			)
			if near_hole and dice.randf() < .45:
				s.put(x, y, Paint.rgb(212, 180, 132))
	for r: Rect2 in [stub, post]:
		for k in 3:
			var x := int(r.position.x + dice.randf_range(0.0, r.size.x))
			s.put(x, int(r.end.y), Paint.rgb(214, 184, 136))
	return Paint.digitize(s, 0.0)


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


## The plank fence shot about: boards knocked out (the far side's boards in
## shadow showing between the rails), one broken off at the top, one at the
## bottom, one split, splinters pale at every break, and holes.
static func _fence_hit(
	whole: Paint.Sheet, boards := BOARDS, rails := RAILS, seed := "stockyard_hit"
) -> Paint.Sheet:
	var s := whole.duplicate_sheet()
	var dice := _dice(seed)
	# [board, from row, to row]: what of it is gone (rails stay).
	var gone := [[3, 0, 127], [8, 0, 127], [1, 0, 50], [6, 78, 127], [5, 34, 55]]
	var cut := Paint.Sheet.new(128, 128)
	for g: Array in gone:
		var board: Array = boards[int(g[0]) % boards.size()]
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
		for r: Array in rails:
			on_rail = on_rail or (y >= int(r[0]) and y <= int(r[1]))
		for x in 128:
			if cut.alpha_at(x, y) > 0 and not on_rail:
				# The far side's boards seen through, in the cell's shadow (the
				# view cuts the planks out for real near the eye: wall_looks.gd;
				# this is the far-off look), never a black stripe.
				var o := (y * 128 + 127 - x) * 4
				s.put(
					x,
					y,
					Paint.rgb(
						whole.data[o] * .4 + 6,
						whole.data[o + 1] * .4 + 6,
						whole.data[o + 2] * .42 + 9
					)
				)
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
## tall): stumps across the bottom, a board left standing at each side broken
## off high, the stockyard's middle rail snapped and hanging, a board hanging
## off it. Variant k (0 to 2: <tile>_gap, _gap_1, _gap_2) breaks every stump
## and board at its own height and slant, so gaps side by side differ; each
## stump is splintered to a point or two, its broken top pale.
static func _fence_gap(
	whole: Paint.Sheet, rails := true, seed := "stockyard_gap", k := 0
) -> Paint.Sheet:
	var w := 64
	var h := 52
	var dice := _dice(seed if k == 0 else "%s_%d" % [seed, k])
	var full := Paint.Sheet.new(w, h)
	# The fence's own planks, the lower rows of its tile, half size.
	for y in h:
		for x in w:
			var o := ((24 + y * 2) * 128 + x * 2) * 4
			full.put(x, y, Color8(whole.data[o], whole.data[o + 1], whole.data[o + 2]))
	var keep := Paint.Sheet.new(w, h)
	var white := Color.WHITE
	# A board each side, broken off high, its top torn in a few teeth.
	for side in 2:
		var x0 := 0.0 if side == 0 else w - 9.0 - dice.randf_range(0.0, 3.0)
		var x1 := x0 + 9.0 + dice.randf_range(0.0, 3.0)
		if side == 0:
			x1 = 9.0 + dice.randf_range(0.0, 3.0)
		var top := dice.randf_range(1.0, 14.0)
		var pts := PackedVector2Array([Vector2(x0, h)])
		var teeth := dice.randi_range(2, 4)
		for t in teeth + 1:
			var x := lerpf(x0, x1, float(t) / teeth)
			pts.append(Vector2(x, top + (dice.randf_range(0.0, 6.0) if t % 2 == 1 else 0.0)))
		pts.append(Vector2(x1, h))
		Paint.polygon(keep, pts, white)
	# Stumps between them, each its own height, splintered to a point or two,
	# some leaning off the break.
	var x := 12.0 + dice.randf_range(0.0, 2.0)
	while x < w - 13.0:
		var wide := dice.randf_range(3.5, 5.5)
		var top := h - dice.randf_range(3.0, 22.0 if dice.randf() < .3 else 14.0)
		var lean := dice.randf_range(-2.0, 2.0)
		var pts := PackedVector2Array([Vector2(x, h)])
		pts.append(Vector2(x + lean * .3, top + dice.randf_range(0.0, 4.0)))
		pts.append(Vector2(x + wide * .35 + lean, top - dice.randf_range(0.0, 5.0)))
		if dice.randf() < .5:
			pts.append(Vector2(x + wide * .6 + lean, top + dice.randf_range(1.0, 4.0)))
			pts.append(Vector2(x + wide * .8 + lean, top - dice.randf_range(0.0, 3.0)))
		pts.append(Vector2(x + wide + lean * .3, top + dice.randf_range(0.0, 4.0)))
		pts.append(Vector2(x + wide, h))
		Paint.polygon(keep, pts, white)
		x += wide + (1.0 if dice.randf() < .3 else 0.0)
	# The lower rail: kept each side, gone in the middle.
	var cut_l := dice.randi_range(14, 20)
	var cut_r := dice.randi_range(42, 50)
	for y in range(37, 44 if rails else 37):
		for xx in range(0, w):
			if xx < cut_l or xx > cut_r:
				keep.put(xx, y, white)
	var out := Paint.Sheet.new(w, h)
	for y in h:
		for xx in w:
			if keep.alpha_at(xx, y) > 0:
				var o := (y * w + xx) * 4
				out.put(xx, y, Color8(full.data[o], full.data[o + 1], full.data[o + 2]))
	if rails:
		_hanging(out)
	# Every broken edge pale with splinters (most on the tops), the rest of
	# the outline dark.
	var edge := out.duplicate_sheet()
	for y in h:
		for xx in w:
			if out.alpha_at(xx, y) == 0:
				continue
			var open_side := 0
			var open_top := y > 0 and out.alpha_at(xx, y - 1) == 0
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0)]:
				var q := Vector2i(xx, y) + d
				if q.x >= 0 and q.x < w and out.alpha_at(q.x, q.y) == 0:
					open_side += 1
			if open_top:
				var c := Paint.rgb(222, 194, 146) if dice.randf() < .7 else Paint.rgb(176, 146, 104)
				edge.put(xx, y, c)
				if y + 1 < h and dice.randf() < .4:
					edge.put(xx, y + 1, Paint.rgb(196, 166, 120))
			elif open_side > 0:
				edge.put(xx, y, Paint.rgb(48, 38, 30))
	return Paint.digitize(edge, 4.0)


## The fence's middle rail snapped (its left half hanging, its right a stub)
## and a board hanging off it by one nail, swung down and out.
static func _hanging(out: Paint.Sheet) -> void:
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
