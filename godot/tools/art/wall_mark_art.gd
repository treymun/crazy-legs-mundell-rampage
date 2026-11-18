## What rounds and breaks leave on walls and throw off them, drawn for
## wall_break_art.gd (build_break_art.gd) into assets/art:
##
##   fx_hole_wood_N   (3) a round through a plank: the dark hole, the wood
##                    torn round it and pale splinters along the grain
##   fx_hole_brick_N  (3) a chipped crater in brick, a chunk knocked out of
##                    it to one side, raw brick inside, red dust round it
##   fx_hole_tin_N    (2) a hole punched through sheet tin, its torn petals
##                    bright, a dent round it
##   fx_hole_stone_N  (2) a pale pock crushed into stone or plaster, grey dust
##   fx_glass_web_N   (4) a pane's crack web round the hole a round made
##                    (features/wall_looks.gd lays it where the round struck)
##   fx_shard_glass, fx_shard_glass_lit  a shard's glass (a window's, a lit one's):
##                    dithered, a pale rim on its long side and its edges
##   fx_window_frame  a stick of a window's frame torn out by a blast
##
## Hard edged, few colours, put to the game's palette (Paint.digitize):
## readable as a few pixels at 320x200.
extends RefCounted

const Paint := preload("res://tools/art/paint.gd")


static func build(art: String) -> int:
	var count := 0
	for k in 3:
		wood_hole(k).save(art.path_join("fx_hole_wood_%d.png" % k))
		brick_hole(k).save(art.path_join("fx_hole_brick_%d.png" % k))
		count += 2
	for k in 2:
		tin_hole(k).save(art.path_join("fx_hole_tin_%d.png" % k))
		stone_hole(k).save(art.path_join("fx_hole_stone_%d.png" % k))
		count += 2
	for k in 4:
		web(k).save(art.path_join("fx_glass_web_%d.png" % k))
		count += 1
	glass(false).save(art.path_join("fx_shard_glass.png"))
	glass(true).save(art.path_join("fx_shard_glass_lit.png"))
	frame_stick().save(art.path_join("fx_window_frame.png"))
	return count + 3


static func _dice(text: String) -> RandomNumberGenerator:
	var dice := RandomNumberGenerator.new()
	var seed := 17
	for c in text.to_utf8_buffer():
		seed = (seed * 31 + c) % 1000003
	dice.seed = seed
	return dice


## A ragged blob round (cx, cy): `r` wide, each of `n` spokes its own reach.
static func _blob(
	cx: float, cy: float, r: float, n: int, rough: float, dice: RandomNumberGenerator
) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var turn := dice.randf_range(0.0, TAU)
	for k in n:
		var a := turn + TAU * k / n
		var reach := r * dice.randf_range(1.0 - rough, 1.0 + rough * .6)
		pts.append(Vector2(cx + cos(a) * reach, cy + sin(a) * reach))
	return pts


## A round through a plank, 32 x 32, to read from a few cells off: the dark
## hole, a pale torn rim round it outlined dark, splinters sticking out along
## the grain (up and down), a few across.
static func wood_hole(k: int) -> Paint.Sheet:
	var s := Paint.Sheet.new(32, 32)
	var dice := _dice("hole_wood_%d" % k)
	var c := Vector2(16.0 + dice.randf_range(-1.0, 1.0), 16.0 + dice.randf_range(-1.0, 1.0))
	var pale := Paint.rgb(218, 188, 138)
	var dark := Paint.rgb(56, 38, 24)
	for i in 6 + k:
		var a := (PI * .5 if i % 2 == 0 else -PI * .5) + dice.randf_range(-.4, .4)
		if i >= 5:
			a = dice.randf_range(0.0, TAU)
		var reach := dice.randf_range(11.0, 15.0) if i < 5 else dice.randf_range(8.0, 11.0)
		var d := Vector2(cos(a), sin(a))
		var side := Vector2(-d.y, d.x)
		var tip := c + d * reach
		var base := 2.6
		Paint.polygon(
			s, PackedVector2Array([c + side * (base + 1.0), tip + d, c - side * (base + 1.0)]), dark
		)
		Paint.polygon(s, PackedVector2Array([c + side * base, tip, c - side * base]), pale)
	Paint.polygon(s, _blob(c.x, c.y, 9.0, 11, .25, dice), dark)
	Paint.polygon(s, _blob(c.x, c.y, 8.0, 11, .25, dice), pale)
	Paint.polygon(s, _blob(c.x, c.y, 5.6, 9, .3, dice), Paint.rgb(70, 46, 28))
	Paint.polygon(s, _blob(c.x, c.y, 4.6, 9, .3, dice), Paint.rgb(14, 10, 8))
	return Paint.digitize(s, 0.0)


## A round into brick, 36 x 36: a pale dust ring, the chipped crater (raw
## brick, its lit rim pale, darker in) with a chunk knocked out to one side,
## the dark hole.
static func brick_hole(k: int) -> Paint.Sheet:
	var s := Paint.Sheet.new(36, 36)
	var dice := _dice("hole_brick_%d" % k)
	var c := Vector2(18.0, 18.0)
	for i in 160:
		var a := dice.randf_range(0.0, TAU)
		var d := dice.randf_range(10.0, 17.0)
		var p := c + Vector2(cos(a), sin(a)) * d
		s.put(int(p.x), int(p.y), Paint.rgb(214, 170, 140, 190 if d < 14.0 else 120))
	var off := Vector2.from_angle(dice.randf_range(0.0, TAU)) * dice.randf_range(4.0, 6.0)
	Paint.polygon(s, _blob(c.x + off.x, c.y + off.y, 9.0, 7, .35, dice), Paint.rgb(204, 120, 86))
	Paint.polygon(s, _blob(c.x, c.y, 10.5, 10, .3, dice), Paint.rgb(196, 112, 80))
	Paint.polygon(
		s, _blob(c.x + off.x * .5, c.y + off.y * .5, 7.0, 8, .3, dice), Paint.rgb(128, 60, 42)
	)
	Paint.polygon(s, _blob(c.x, c.y, 4.2, 7, .3, dice), Paint.rgb(36, 22, 18))
	for y in 36:
		for x in 36:
			var o := (y * 36 + x) * 4
			if s.data[o + 3] < 255:
				continue
			var up := (y - 1) * 36 + x
			var left := y * 36 + x - 1
			if (y > 0 and s.data[up * 4 + 3] < 255) or (x > 0 and s.data[left * 4 + 3] < 255):
				s.put(x, y, Paint.rgb(240, 176, 136))
	return Paint.digitize(s, 0.0)


## A round through sheet tin, 28 x 28: the dent (a dark ring), the petals torn
## out and bent back (bright on their lit side, outlined dark), the hole.
static func tin_hole(k: int) -> Paint.Sheet:
	var s := Paint.Sheet.new(28, 28)
	var dice := _dice("hole_tin_%d" % k)
	var c := Vector2(14.0, 14.0)
	Paint.polygon(s, _blob(c.x, c.y, 11.5, 12, .12, dice), Paint.rgb(52, 54, 58, 220))
	var petals := 5 + k
	var turn := dice.randf_range(0.0, TAU)
	for i in petals:
		var a := turn + TAU * i / petals + dice.randf_range(-.2, .2)
		var d := Vector2(cos(a), sin(a))
		var side := Vector2(-d.y, d.x)
		var reach := dice.randf_range(8.5, 11.0)
		Paint.polygon(
			s,
			PackedVector2Array([c + side * 4.0, c + d * (reach + 1.0), c - side * 4.0]),
			Paint.rgb(30, 30, 34)
		)
		var bright := Paint.rgb(246, 246, 236) if d.y < .3 else Paint.rgb(170, 172, 168)
		Paint.polygon(
			s, PackedVector2Array([c + side * 3.0, c + d * reach, c - side * 3.0]), bright
		)
	Paint.polygon(s, _blob(c.x, c.y, 4.6, 8, .2, dice), Paint.rgb(12, 10, 10))
	return Paint.digitize(s, 0.0)


## A round into stone or plaster, 28 x 28: a grey dust ring, the pale crushed
## pock, a small dark core.
static func stone_hole(k: int) -> Paint.Sheet:
	var s := Paint.Sheet.new(28, 28)
	var dice := _dice("hole_stone_%d" % k)
	var c := Vector2(14.0, 14.0)
	for i in 110:
		var a := dice.randf_range(0.0, TAU)
		var d := dice.randf_range(7.5, 13.0)
		var p := c + Vector2(cos(a), sin(a)) * d
		s.put(int(p.x), int(p.y), Paint.rgb(190, 186, 176, 170))
	Paint.polygon(s, _blob(c.x, c.y, 8.5, 10, .3, dice), Paint.rgb(222, 218, 208))
	Paint.polygon(s, _blob(c.x + .6, c.y + .6, 5.4, 8, .3, dice), Paint.rgb(140, 136, 128))
	Paint.polygon(s, _blob(c.x + .5, c.y + .5, 2.8, 6, .2, dice), Paint.rgb(30, 28, 26))
	return Paint.digitize(s, 0.0)


## A pane's crack web, 64 x 64 (the hole at its middle): rays to the edge,
## each jagged, a pale line with its shadow; broken rings round the hole; a
## crazed patch right round it.
static func web(k: int) -> Paint.Sheet:
	var s := Paint.Sheet.new(64, 64)
	var dice := _dice("glass_web_%d" % k)
	var hit := Vector2(32.0, 32.0)
	var pale := Paint.rgb(228, 236, 238)
	var shade := Paint.rgb(34, 40, 46)
	var rays := 7 + k % 3 + dice.randi_range(0, 2)
	var turn := dice.randf_range(0.0, TAU)
	for r in rays:
		var a := turn + TAU * (r + dice.randf_range(-.3, .3)) / rays
		var at := hit
		var reach := 0.0
		var far := dice.randf_range(22.0, 34.0)
		while reach < far:
			a += dice.randf_range(-.28, .28)
			var step := dice.randf_range(3.0, 6.0)
			var to := at + Vector2(cos(a), sin(a)) * step
			var side := Vector2(-sin(a), cos(a))
			Paint.line2(s, at.x + side.x, at.y + side.y, to.x + side.x, to.y + side.y, shade)
			Paint.line2(s, at.x, at.y, to.x, to.y, pale)
			# Now and then a short branch.
			if dice.randf() < .18:
				var b := a + dice.randf_range(.5, 1.0) * (1.0 if dice.randf() < .5 else -1.0)
				var bt := to + Vector2(cos(b), sin(b)) * dice.randf_range(4.0, 9.0)
				Paint.line2(s, to.x, to.y, bt.x, bt.y, pale)
			at = to
			reach += step
	for ring: float in [
		5.0 + dice.randf_range(0.0, 1.5),
		11.0 + dice.randf_range(0.0, 3.0),
		19.0 + dice.randf_range(0.0, 4.0)
	]:
		var gaps := dice.randf_range(.3, .5)
		for n in 56:
			if dice.randf() < gaps:
				continue
			var a := TAU * n / 56.0
			var q := hit + Vector2(cos(a), sin(a)) * ring * dice.randf_range(.92, 1.08)
			s.put(int(q.x), int(q.y), pale)
	# Crazed right round the hole: a patch of pale flecks.
	for n in 40:
		var a := dice.randf_range(0.0, TAU)
		var q := hit + Vector2(cos(a), sin(a)) * dice.randf_range(2.0, 5.5)
		s.put(int(q.x), int(q.y), Paint.rgb(214, 226, 230, 190))
	for y in range(29, 36):
		for x in range(29, 36):
			var d := Vector2(x + .5, y + .5).distance_to(hit)
			if d < 1.8:
				s.put(x, y, Paint.rgb(14, 12, 12))
			elif d < 3.0:
				s.put(x, y, pale)
	return Paint.digitize(s, 0.0)


## A shard's glass, 32 x 32 (the template triangle's corners at (2, 30),
## (30, 30), (2, 2)): pale grey-blue with every other pair of texels clear
## (seen through; a lit window's warmer), a streak or two of glint across, a
## pale rim along its long side; its middle (the edges' colour) pale.
static func glass(lit: bool) -> Paint.Sheet:
	var s := Paint.Sheet.new(32, 32)
	var dark := Paint.rgb(104, 134, 144) if not lit else Paint.rgb(138, 136, 124)
	var mid := Paint.rgb(140, 170, 178) if not lit else Paint.rgb(176, 168, 146)
	var glint := Paint.rgb(204, 226, 228) if not lit else Paint.rgb(246, 210, 146)
	var rim := Paint.rgb(236, 246, 246) if not lit else Paint.rgb(255, 232, 178)
	# Every other pair of texels clear (the wreck shader leaves them out): the
	# glass seen through, screen-door fashion.
	for y in 32:
		for x in 32:
			if (x / 2 + y / 2) % 2 == 0:
				continue
			s.put(x, y, mid if (x + y * 3) % 5 != 0 else dark)
	for streak in 3:
		var c := 10 + streak * 9
		for t in range(-6, 7):
			var x := c + t
			var y := 30 - c + t
			if streak != 1 or absi(t) < 4:
				s.put(x, y, glint)
	for i in range(1, 31):
		s.put(i, i, rim)
		s.put(i + 1, i, rim)
	s.put(16, 16, rim)
	return Paint.digitize(s, 0.0)


## A stick of a window's frame, 32 x 8: painted wood, lit along its top,
## grain dark, its torn ends pale.
static func frame_stick() -> Paint.Sheet:
	var s := Paint.Sheet.new(32, 8)
	var dice := _dice("frame_stick")
	for y in 8:
		for x in 32:
			var c := Vector3(104, 72, 46) * dice.randf_range(.9, 1.06)
			if y < 2:
				c = Vector3(150, 110, 72)
			elif y > 5:
				c = Vector3(62, 42, 28)
			if (x * 3 + y * 7) % 11 == 0:
				c *= .7
			if x < 2 or x > 29:
				c = Vector3(214, 184, 136) if (x + y) % 2 == 0 else Vector3(176, 146, 104)
			s.put(x, y, Paint.rgb(c.x, c.y, c.z))
	return Paint.digitize(s, 0.0)
