## Draw what points a player at a gun they ain't got yet (feature pass 7,
## src/gun_finder.gd), in the vehicle signs' hand (build_vehicle_signs.gd):
##
##   gun_sign_way_r                   GUNS THIS WAY, a plank cut to an arrow (sawn
##                                    pointing left too: sign_way(false))
##   gun_sign_honor                   Hickston: GUNS, HONOR SYSTEM, a buck in the can
##   gun_sign_fair                    the fair: WIN A GUN on a carny's striped tin
##   gun_sign_mill                    the sawmill: MILL LEAGUE bowling, stencilled on grey tin
##   gun_sign_quarry                  the quarry: DANGER, the cow launcher, on yellow tin
##   gun_sign_chalk                   a hobo's chalk mark: a gun and an X (by a secret)
##   fx_gun_shine_0..2                the glint over a gun lying out: a spark, a cross, a star
##   gun_board                        Mundell's shadow board in the trophy shack: a painted
##                                    outline for each of the campaign's fourteen guns
##                                    (GunFinder.BOARD), MUNDELL'S IRON in the last place
##
##   godot --headless --path godot --script res://tools/art/build_gun_signs.gd [-- out=<dir>]
##
## Writes them to assets/art (the plans hang the signs by the guns; county_kit.gd
## takes them off the County Run maps). Seeded with its own generator, so a rerun
## gives the same files and no other art moves. Then run tools/pack_assets.gd.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")
## The board's grid: GunFinder.BOARD's guns (src/gun_finder.gd) five a row, a
## cell CELL pixels (features/trophy_shack.gd hangs each gun had on its own).
const COLUMNS := 5
const ROWS := 3
const CELL := Vector2i(56, 30)
const MARGIN := 8

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 7716
	var art := Paint.repo("assets/art")
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			art = String(arg).substr(4)
	DirAccess.make_dir_recursive_absolute(art)
	var made := {
		"gun_sign_way_r": sign_way(true),
		"gun_sign_honor": sign_honor(),
		"gun_sign_fair": sign_fair(),
		"gun_sign_mill": sign_mill(),
		"gun_sign_quarry": sign_quarry(),
		"gun_sign_chalk": sign_chalk(),
		"gun_board": gun_board(Paint.repo("assets/art")),
	}
	for k in 3:
		made["fx_gun_shine_%d" % k] = shine(k)
	for name: String in made:
		var sheet: Paint.Sheet = made[name]
		sheet.save(art.path_join(name + ".png"))
	print("gun signs: %d to %s" % [made.size(), art])
	quit()


# ---------------------------------------------------------------- the boards


func planks(width: int, height: int, base: Color, plank := 6) -> Paint.Sheet:
	var s := Paint.Sheet.new(width, height)
	var grain := Paint.noise(rng.randi(), width * height, .06)
	for y in height:
		var row := y / plank
		var tone := 1.0 + sin(row * 2.3) * .07
		var seam := y % plank == 0
		for x in width:
			var f := tone + grain[y * width + x] + sin(x * .21 + row * 1.7) * .03
			f *= 1.0 + (1.0 - float(y) / height) * .08
			if seam:
				f *= .55
			s.put(x, y, Color(base.r * f, base.g * f, base.b * f))
	return s


func tin(width: int, height: int, base: Color, rusty := 1.0) -> Paint.Sheet:
	var s := Paint.Sheet.new(width, height)
	var blot := Paint.cloud(64, rng.randi())
	var grit := Paint.noise(rng.randi(), width * height, .05)
	for y in height:
		for x in width:
			var edge := minf(minf(x, width - 1 - x), minf(y, height - 1 - y)) / 5.0
			var b := blot[(y * 64 / height) * 64 + (x * 64 / width)]
			var rust := clampf((b * 1.3 - clampf(edge, 0, 1) * .8 - .1) * rusty, 0, 1)
			var c := base.lerp(Color(.52, .26, .12), rust)
			var f := 1.0 + grit[y * width + x] + (sin(x * 1.4) * .04)
			s.put(x, y, Color(c.r * f, c.g * f, c.b * f))
	return s


## Block letters `scale` times their size, centred on x, painted by hand:
## each letter sits a pixel up or down, the brush thins at its edges, and
## paint runs down from a few of them (`drips` in a hundred). `stencil` leaves
## the bridges a stencil's letters have (a gap down each letter's middle row).
func painted(
	s: Paint.Sheet,
	text: String,
	x: int,
	y: int,
	scale: int,
	ink: Color,
	drips := 0,
	stencil := false
) -> void:
	var width := 0
	for c in text:
		width += (int(PixelType.glyph(c, false)[1]) + 1) * scale
	width -= scale
	var at := x - width / 2
	for c in text:
		var g: Array = PixelType.glyph(c, false)
		var rows: Array = g[0]
		var gw: int = g[1]
		var lift := rng.randi_range(-1, 1) if scale > 1 and not stencil else 0
		var tone := ink.darkened(rng.randf_range(0.0, .12))
		var lowest := {}
		for r in rows.size():
			if stencil and r == 3:
				continue
			for bx in gw:
				if int(rows[r]) & (1 << (gw - 1 - bx)):
					for yy in scale:
						for xx in scale:
							var px := at + bx * scale + xx
							var py := y + r * scale + yy + lift
							var thin := (
								scale > 1
								and (xx == scale - 1 or yy == scale - 1)
								and rng.randf() < .3
							)
							_blend(s, px, py, tone if not thin else Color(tone, .55))
							lowest[px] = maxi(int(lowest.get(px, 0)), py)
		for px: int in lowest:
			if rng.randi_range(0, 99) < drips:
				var run := rng.randi_range(2, 5)
				for k in run:
					_blend(s, px, int(lowest[px]) + 1 + k, Color(tone, .85 - k * .14))
		at += (gw + 1) * scale


func _blend(s: Paint.Sheet, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= s.w or y >= s.h:
		return
	var o := (y * s.w + x) * 4
	var a := c.a
	for k in 3:
		s.data[o + k] = int(s.data[o + k] * (1.0 - a) + c[k] * 255.0 * a)
	s.data[o + 3] = maxi(s.data[o + 3], int(a * 255))


func weather(s: Paint.Sheet, chips: int, holes: int) -> void:
	for _k in chips:
		var x := rng.randi_range(1, s.w - 2)
		var y := rng.randi_range(1, s.h - 2)
		var o := (y * s.w + x) * 4
		if s.data[o + 3] == 0:
			continue
		for k in 3:
			s.data[o + k] = int(s.data[o + k] * .72)
	for _k in holes:
		var x := rng.randi_range(3, s.w - 4)
		var y := rng.randi_range(3, s.h - 4)
		if s.data[(y * s.w + x) * 4 + 3] == 0:
			continue
		Paint.point(s, x, y, Color8(14, 10, 8))
		Paint.point(s, x + 1, y, Color8(150, 140, 128))
		Paint.point(s, x, y - 1, Color8(150, 140, 128))


func frame(s: Paint.Sheet, c: Color) -> void:
	Paint.outline(s, 0, 0, s.w - 1, s.h - 1, c)
	Paint.outline(s, 1, 1, s.w - 2, s.h - 2, c.lightened(.25))


func nails(s: Paint.Sheet) -> void:
	for p in [
		Vector2i(2, 2), Vector2i(s.w - 3, 2), Vector2i(2, s.h - 3), Vector2i(s.w - 3, s.h - 3)
	]:
		Paint.point(s, p.x, p.y, Color8(200, 196, 186))


## A long gun painted with a wide brush, muzzle to the right (x, y its butt's
## top left; about 26 by 9): stock, action, barrel, a trigger guard.
func long_gun(s: Paint.Sheet, x: int, y: int, ink: Color) -> void:
	for k in 7:
		Paint.rect(s, x + k, y + 3 - k / 3, x + k, y + 8 - k / 2, ink)  # the stock
	Paint.rect(s, x + 7, y + 1, x + 13, y + 4, ink)  # the action
	Paint.rect(s, x + 13, y + 1, x + 26, y + 2, ink)  # the barrel
	Paint.rect(s, x + 14, y + 3, x + 22, y + 3, ink)  # the forend
	Paint.rect(s, x + 9, y + 5, x + 9, y + 6, ink)
	Paint.rect(s, x + 10, y + 7, x + 12, y + 7, ink)  # the guard
	Paint.rect(s, x + 12, y + 5, x + 12, y + 6, ink)


# --------------------------------------------------------------------- signs


## A plank sawn to an arrow, pointing right (or left): GUNS THIS WAY.
func sign_way(right: bool) -> Paint.Sheet:
	var w := 100
	var h := 44
	var base := planks(w, h, Color(.7, .64, .5), 8)
	var s := Paint.Sheet.new(w, h)
	var head := 22
	for y in h:
		for x in w:
			var keep := false
			var ax := x if right else w - 1 - x
			if ax < w - head:
				keep = y >= 5 and y < h - 5
			else:
				var t := float(ax - (w - head)) / head
				var half := (h / 2.0) * (1.0 - t)
				keep = absf(y + .5 - h / 2.0) <= half
			if keep:
				var o := (y * w + x) * 4
				for k in 4:
					s.data[o + k] = base.data[o + k]
	# A dark edge where the saw went, and a lighter one where the sun lands.
	var edge := s.duplicate_sheet()
	for y in h:
		for x in w:
			var o := (y * w + x) * 4
			if s.data[o + 3] == 0:
				continue
			var rim := false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := x + d.x
				var ny := y + d.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h or s.data[(ny * w + nx) * 4 + 3] == 0:
					rim = true
			if rim:
				edge.put(x, y, Color8(46, 32, 22))
	s = edge
	var mid := (w - head) / 2 + (0 if right else head)
	painted(s, "GUNS", mid, 9, 2, Color8(178, 32, 22), 14)
	painted(s, "THIS WAY", mid, 28, 1, Color8(34, 26, 20))
	Paint.point(s, 6 if right else w - 7, h / 2, Color8(200, 196, 186))
	weather(s, 60, 2)
	return Paint.digitize(s)


func sign_honor() -> Paint.Sheet:
	var s := planks(150, 46, Color(.84, .8, .7), 8)
	long_gun(s, 8, 6, Color8(40, 30, 24))
	painted(s, "GUNS", 92, 4, 2, Color8(176, 34, 24), 20)
	painted(s, "HONOR SYSTEM", 75, 23, 1, Color8(36, 28, 22))
	painted(s, "A BUCK IN THE COFFEE CAN", 75, 33, 1, Color8(150, 30, 22))
	frame(s, Color8(62, 48, 34))
	nails(s)
	weather(s, 100, 3)
	return Paint.digitize(s)


func sign_fair() -> Paint.Sheet:
	var s := tin(150, 46, Color(.9, .84, .66), .6)
	# The carny's red and white stripes down each end.
	for y in range(2, 44):
		for x in range(2, 148):
			if x < 12 or x > 137:
				var red := ((x + y) / 4) % 2 == 0
				s.put(x, y, Color8(176, 36, 30) if red else Color8(236, 226, 200))
	painted(s, "WIN A GUN", 75, 5, 2, Color8(182, 30, 24), 10)
	painted(s, "EVERY PLAYER A WINNER", 75, 23, 1, Color8(30, 56, 120))
	painted(s, "NO REFUNDS", 75, 33, 1, Color8(150, 30, 22))
	frame(s, Color8(60, 44, 30))
	weather(s, 70, 4)
	return Paint.digitize(s)


func sign_mill() -> Paint.Sheet:
	var s := tin(140, 44, Color(.62, .64, .62))
	for x in range(3, 137):
		for y in range(3, 6):
			s.put(x, y, Color8(214, 168, 40) if (x / 6) % 2 == 0 else Color8(30, 26, 22))
	painted(s, "MILL LEAGUE", 70, 9, 2, Color8(28, 26, 24), 6, true)
	painted(s, "BOWLING NITE THURSDAY", 70, 26, 1, Color8(28, 26, 24))
	painted(s, "BRING YER OWN BALL", 70, 35, 1, Color8(160, 34, 24))
	frame(s, Color8(40, 38, 36))
	weather(s, 70, 6)
	return Paint.digitize(s)


func sign_quarry() -> Paint.Sheet:
	var s := tin(150, 46, Color(.86, .7, .2), .7)
	for x in range(2, 148):
		for y: int in [3, 4, 5, 6, 39, 40, 41, 42]:
			s.put(x, y, Color8(26, 22, 18) if ((x + y) / 5) % 2 == 0 else Color8(222, 178, 44))
	painted(s, "DANGER", 75, 8, 2, Color8(160, 28, 20), 8)
	painted(s, "COW LAUNCHER - HANDS OFF", 75, 23, 1, Color8(26, 22, 18))
	painted(s, "THAT MEANS YOU MUNDELL", 75, 31, 1, Color8(150, 26, 18))
	frame(s, Color8(52, 40, 22))
	weather(s, 80, 5)
	return Paint.digitize(s)


## A hobo's chalk mark on a wall: a crude gun, an X under it (good stuff
## here). Chalk only: the wall shows through.
func sign_chalk() -> Paint.Sheet:
	var s := Paint.Sheet.new(36, 26)
	var chalk := Color(.9, .88, .82, .85)
	long_gun(s, 4, 2, chalk)
	# Hollow out the gun so it reads as a line drawing.
	var solid := s.duplicate_sheet()
	for y in s.h:
		for x in s.w:
			var o := (y * s.w + x) * 4
			if solid.data[o + 3] == 0:
				continue
			var inner := true
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := x + d.x
				var ny := y + d.y
				if nx < 0 or ny < 0 or nx >= s.w or ny >= s.h:
					inner = false
				elif solid.data[(ny * s.w + nx) * 4 + 3] == 0:
					inner = false
			if inner:
				s.data[o + 3] = 0
	for k in 9:
		for t in 2:
			_blend(s, 13 + k + t, 15 + k, chalk if rng.randf() > .15 else Color(chalk, .4))
			_blend(s, 21 - k + t, 15 + k, chalk if rng.randf() > .15 else Color(chalk, .4))
	# Chalk on a rough wall: skips where the stick jumped, dust beside it.
	var drawn := s.duplicate_sheet()
	for y in s.h:
		for x in s.w:
			var o := (y * s.w + x) * 4
			if drawn.data[o + 3] > 0:
				var skip := rng.randf()
				if skip < .18:
					s.data[o + 3] = 0
				elif skip < .45:
					s.data[o + 3] = int(s.data[o + 3] * .55)
			elif rng.randf() < .05:
				for d: Vector2i in [
					Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)
				]:
					var nx := x + d.x
					var ny := y + d.y
					if nx >= 0 and ny >= 0 and nx < s.w and ny < s.h:
						if drawn.data[(ny * s.w + nx) * 4 + 3] > 0:
							_blend(s, x, y, Color(chalk, .3))
							break
	return s


## The glint over a gun lying out, warm: a spark, a cross, a four-point star.
func shine(k: int) -> Paint.Sheet:
	var s := Paint.Sheet.new(11, 11)
	var core := Color8(255, 252, 230)
	var warm := Color8(255, 214, 120)
	var reach: int = [1, 3, 5][k]
	for t in range(-reach, reach + 1):
		var a := 1.0 - absf(t) / float(reach + 1)
		var c := core if absf(t) <= 1 else warm
		_blend(s, 5 + t, 5, Color(c, a))
		_blend(s, 5, 5 + t, Color(c, a))
	if k == 2:
		for t in range(-2, 3):
			_blend(s, 5 + t, 5 + t, Color(warm, .45))
			_blend(s, 5 + t, 5 - t, Color(warm, .45))
	_blend(s, 5, 5, core)
	return s


## Mundell's shadow board: pegboard, a whitewash outline painted round each
## gun where it hangs, its name on a strip of tape under it.
func gun_board(art: String) -> Paint.Sheet:
	var w := MARGIN * 2 + CELL.x * COLUMNS
	var h := MARGIN * 2 + CELL.y * ROWS
	var s := Paint.Sheet.new(w, h)
	var grit := Paint.noise(rng.randi(), w * h, .04)
	for y in h:
		for x in w:
			var f := 1.0 + grit[y * w + x]
			var c := Color(.62 * f, .48 * f, .32 * f)
			if (x - 3) % 7 == 0 and (y - 3) % 7 == 0:
				c = c.darkened(.45)  # the board's holes
			s.put(x, y, c)
	var paint := Color8(240, 236, 220)
	for i in GunFinder.BOARD.size():
		var gun: String = GunFinder.BOARD[i]
		var pic := Paint.Sheet.load_png(art.path_join("item_%s.png" % _item(gun)))
		if pic == null:
			continue
		var box := _fit(pic)
		var cell := Vector2i(MARGIN + (i % COLUMNS) * CELL.x, MARGIN + (i / COLUMNS) * CELL.y)
		var size: Vector2i = box[1]
		var at := cell + (CELL - size) / 2 - Vector2i(0, 2)
		_outline(s, pic, box[0], size, at, paint)
		# Two pegs it hangs on.
		for px: int in [at.x + size.x / 4, at.x + size.x * 3 / 4]:
			Paint.rect(
				s, px, at.y + size.y / 2 - 1, px + 1, at.y + size.y / 2, Color8(150, 140, 120)
			)
	# The last place: whose board it is, in the same whitewash.
	var last := GunFinder.BOARD.size()
	var corner := Vector2i(MARGIN + (last % COLUMNS) * CELL.x, MARGIN + (last / COLUMNS) * CELL.y)
	painted(s, "MUNDELL'S", corner.x + CELL.x / 2, corner.y + 6, 1, paint)
	painted(s, "IRON", corner.x + CELL.x / 2, corner.y + 16, 1, Color8(200, 60, 40))
	frame(s, Color8(58, 40, 26))
	weather(s, 120, 0)
	return Paint.digitize(s)


## The item picture for a gun (the hand-thrown dynamite's is its sticks).
static func _item(gun: String) -> String:
	return "dynamite" if gun == "tnt" else gun


## The part of a picture with paint in it, and the size it is drawn at to fit a
## cell (a pixel of art a pixel of board, shrunk to fit): [Rect2i, Vector2i].
func _fit(pic: Paint.Sheet) -> Array:
	var x0 := pic.w
	var y0 := pic.h
	var x1 := 0
	var y1 := 0
	for y in pic.h:
		for x in pic.w:
			if pic.data[(y * pic.w + x) * 4 + 3] > 100:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	var rect := Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
	var room := Vector2(CELL.x - 8, CELL.y - 6)
	var k := minf(1.0, minf(room.x / rect.size.x, room.y / rect.size.y))
	return [rect, Vector2i(maxi(1, int(rect.size.x * k)), maxi(1, int(rect.size.y * k)))]


## A brush outline round the picture's shape, drawn at `size` with its top left
## at `at`.
func _outline(
	s: Paint.Sheet, pic: Paint.Sheet, rect: Rect2i, size: Vector2i, at: Vector2i, ink: Color
) -> void:
	var inside := func(x: int, y: int) -> bool:
		if x < 0 or y < 0 or x >= size.x or y >= size.y:
			return false
		var sx := rect.position.x + x * rect.size.x / size.x
		var sy := rect.position.y + y * rect.size.y / size.y
		return pic.data[(sy * pic.w + sx) * 4 + 3] > 100
	for y in range(-1, size.y + 1):
		for x in range(-1, size.x + 1):
			if inside.call(x, y):
				continue
			var near := false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				if inside.call(x + d.x, y + d.y):
					near = true
			if near:
				# A wide brush: the line and a pixel beside it, a little patchy.
				_blend(s, at.x + x, at.y + y, Color(ink, .95 if rng.randf() > .1 else .6))
				_blend(s, at.x + x + 1, at.y + y, Color(ink, .7))
