## Paint the small things that make a fight and a level feel lived in, into
## assets/art: spent brass and shotgun hulls, embers, scorch marks, the crows
## that cross the sky and the fireflies of a summer night.
##
##   godot --headless --path godot --script res://tools/art/build_world_fx.gd [-- out=<dir>]
##
##   fx_casing        a spent rifle or revolver case, brass
##   fx_hull          a spent 12-gauge hull: red paper, brass head
##   fx_ember_N       (2) a spark of burning stuff floating up from a blast
##   mark_scorch_N    (3) the black scorch an explosion leaves on the ground
##   fx_crow_N        (2) a crow, wings up and wings down
##   fx_firefly_N     (2) a firefly lit and dark
##   fx_casing_45     (pass 15) a stubby .45 case: the county .45, the tommy, the grease gun
##   fx_casing_357    a long straight .357 case, nickel-bright: the Star .357
##   fx_casing_44     a fat old .44 case, dull and sooty: the Hogleg
##   fx_casing_long   a bottlenecked rifle case: the deer rifle, the patrol rifle, the marksman
##   fx_hull_riot     a riot pump's black plastic hull, brass head
##   fx_twinkle_N     (2) the star a pickup glints with: small, and big
## Then run tools/pack_assets.gd. out= writes somewhere else instead.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 1977
	var out := Paint.repo("assets/art")
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	casing().save(out.path_join("fx_casing.png"))
	hull().save(out.path_join("fx_hull.png"))
	for k in 2:
		ember(k).save(out.path_join("fx_ember_%d.png" % k))
		crow(k).save(out.path_join("fx_crow_%d.png" % k))
		firefly(k).save(out.path_join("fx_firefly_%d.png" % k))
	for k in 3:
		scorch(k).save(out.path_join("mark_scorch_%d.png" % k))
	# What the guns throw between the muzzle and the mark (features/weapon_fx.gd).
	milk_drop().save(out.path_join("fx_milkdrop.png"))
	for k in 2:
		mote(k).save(out.path_join("fx_mote_%d.png" % k))
	for k in 3:
		milk_splash(k).save(out.path_join("fx_milksplash_%d.png" % k))
		milk_puddle(k).save(out.path_join("mark_milk_%d.png" % k))
	# A water tower's flood standing in the street (features/set_pieces.gd).
	for k in 3:
		flood_water(k).save(out.path_join("mark_flood_%d.png" % k))
	# The newer guns' brass and the pickups' glint (pass 15; no dice, so the
	# pictures above come out as before).
	casing_45().save(out.path_join("fx_casing_45.png"))
	casing_357().save(out.path_join("fx_casing_357.png"))
	casing_44().save(out.path_join("fx_casing_44.png"))
	casing_long().save(out.path_join("fx_casing_long.png"))
	hull_riot().save(out.path_join("fx_hull_riot.png"))
	for k in 2:
		twinkle(k).save(out.path_join("fx_twinkle_%d.png" % k))
	print("world fx: 30 pictures in ", out)
	quit()


## Drawn four times over and shrunk, like the gore, for soft round edges cut hard.
func shrunk(big: Paint.Sheet, w: int, h: int, cut := 110) -> Paint.Sheet:
	var small := big.resized(w, h)
	for i in w * h:
		small.data[i * 4 + 3] = 255 if small.data[i * 4 + 3] >= cut else 0
	return small


func casing() -> Paint.Sheet:
	var s := Paint.Sheet.new(48, 20)
	Paint.rounded_rect(s, 4, 4, 38, 15, 4, Color8(176, 132, 52))
	Paint.rect(s, 36, 3, 43, 16, Color8(150, 110, 44))  # the rim
	Paint.rect(s, 6, 5, 34, 7, Color8(236, 204, 120))  # shine along the top
	Paint.rect(s, 6, 13, 34, 14, Color8(116, 82, 30))
	Paint.rect(s, 2, 6, 5, 13, Color8(96, 70, 32))  # the open, sooty mouth
	return shrunk(s, 12, 5)


func hull() -> Paint.Sheet:
	var s := Paint.Sheet.new(56, 24)
	Paint.rounded_rect(s, 4, 4, 40, 19, 3, Color8(170, 34, 28))  # red paper
	Paint.rect(s, 6, 6, 38, 8, Color8(214, 74, 60))
	Paint.rect(s, 6, 16, 38, 17, Color8(110, 20, 18))
	Paint.rect(s, 38, 3, 51, 20, Color8(184, 140, 58))  # brass head
	Paint.rect(s, 40, 5, 49, 7, Color8(236, 206, 128))
	Paint.rect(s, 49, 2, 52, 21, Color8(150, 110, 44))
	for x in range(8, 36, 6):  # the crimped, scorched end
		Paint.line2(s, 4, 6 + (x % 4), 8, 11, Color8(80, 16, 14))
	return shrunk(s, 14, 6)


## A .45 ACP case: short and fat, nearly as wide as it is long.
func casing_45() -> Paint.Sheet:
	var s := Paint.Sheet.new(40, 24)
	Paint.rounded_rect(s, 4, 4, 30, 19, 4, Color8(184, 140, 58))
	Paint.rect(s, 29, 3, 35, 20, Color8(150, 110, 44))  # the rim
	Paint.rect(s, 6, 6, 27, 8, Color8(240, 210, 128))
	Paint.rect(s, 6, 16, 27, 17, Color8(118, 84, 32))
	Paint.rect(s, 2, 7, 5, 16, Color8(92, 66, 30))  # the sooty mouth
	return shrunk(s, 10, 6)


## A .357 case: long and straight, nickel-plated and bright.
func casing_357() -> Paint.Sheet:
	var s := Paint.Sheet.new(56, 20)
	Paint.rounded_rect(s, 4, 4, 46, 15, 3, Color8(176, 176, 168))
	Paint.rect(s, 45, 3, 51, 16, Color8(140, 140, 134))
	Paint.rect(s, 6, 5, 43, 7, Color8(236, 236, 226))
	Paint.rect(s, 6, 13, 43, 14, Color8(104, 104, 100))
	Paint.rect(s, 2, 6, 5, 13, Color8(70, 66, 60))
	return shrunk(s, 14, 5)


## A .44 case off the Hogleg: fat and long, its brass gone dull and sooty.
func casing_44() -> Paint.Sheet:
	var s := Paint.Sheet.new(56, 24)
	Paint.rounded_rect(s, 4, 4, 44, 19, 4, Color8(150, 112, 50))
	Paint.rect(s, 43, 2, 51, 21, Color8(124, 92, 40))
	Paint.rect(s, 6, 6, 41, 8, Color8(204, 168, 96))
	Paint.rect(s, 6, 16, 41, 17, Color8(96, 68, 28))
	Paint.rect(s, 2, 6, 12, 17, Color8(70, 54, 34))  # soot up the mouth
	return shrunk(s, 14, 6)


## A rifle case: a long body necked down to the mouth.
func casing_long() -> Paint.Sheet:
	var s := Paint.Sheet.new(64, 20)
	Paint.rounded_rect(s, 18, 3, 56, 16, 3, Color8(180, 136, 54))
	Paint.polygon(
		s,
		PackedVector2Array([Vector2(18, 3), Vector2(10, 7), Vector2(10, 12), Vector2(18, 16)]),
		Color8(168, 126, 50)
	)
	Paint.rect(s, 3, 7, 11, 12, Color8(176, 132, 52))  # the neck
	Paint.rect(s, 55, 2, 60, 17, Color8(150, 110, 44))  # the rim
	Paint.rect(s, 19, 5, 53, 7, Color8(240, 208, 124))
	Paint.rect(s, 19, 13, 53, 14, Color8(116, 82, 30))
	Paint.rect(s, 1, 8, 3, 11, Color8(92, 66, 30))
	return shrunk(s, 16, 5)


## A riot pump's hull: black plastic, a ribbed side, a tall brass head.
func hull_riot() -> Paint.Sheet:
	var s := Paint.Sheet.new(56, 24)
	Paint.rounded_rect(s, 4, 4, 38, 19, 3, Color8(40, 42, 38))
	Paint.rect(s, 6, 6, 36, 8, Color8(92, 96, 88))
	Paint.rect(s, 6, 16, 36, 17, Color8(22, 22, 20))
	for x in range(10, 36, 7):  # the ribs
		Paint.rect(s, x, 9, x + 1, 15, Color8(62, 64, 58))
	Paint.rect(s, 36, 3, 51, 20, Color8(184, 140, 58))  # the brass head
	Paint.rect(s, 38, 5, 49, 7, Color8(236, 206, 128))
	Paint.rect(s, 49, 2, 52, 21, Color8(150, 110, 44))
	return shrunk(s, 14, 6)


## A pickup's glint: a four-pointed star, white at its heart through pale
## gold to amber tips (the palette's), small (0) and big (1) on one canvas.
func twinkle(k: int) -> Paint.Sheet:
	var s := Paint.Sheet.new(13, 13)
	var heart := Color8(255, 255, 236)
	var inks: Array[Color] = [Color8(255, 240, 168), Color8(250, 210, 100), Color8(222, 150, 48)]
	var reach := 2 if k == 0 else 6
	for d in range(1, reach + 1):
		var ink: Color = inks[mini(2, int(float(d - 1) / reach * 3.0))]
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			s.put(6 + dir.x * d, 6 + dir.y * d, ink)
	s.put(6, 6, heart)
	if k == 1:
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			s.put(6 + dir.x, 6 + dir.y, heart)
		for dir: Vector2i in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			s.put(6 + dir.x, 6 + dir.y, inks[0])
			s.put(6 + dir.x * 2, 6 + dir.y * 2, inks[2])
	return s


func ember(k: int) -> Paint.Sheet:
	var s := Paint.Sheet.new(32, 32)
	var outer := Color8(232, 96, 24) if k == 0 else Color8(196, 60, 18)
	var inner := Color8(255, 222, 120) if k == 0 else Color8(250, 160, 60)
	Paint.ellipse(s, 7, 7, 24, 24, outer)
	Paint.ellipse(s, 12, 11, 20, 19, inner)
	return shrunk(s, 6, 6, 90)


func scorch(k: int) -> Paint.Sheet:
	var size := 96
	var s := Paint.Sheet.new(size * 2, size * 2)
	var c := size
	# A burnt blotch: ragged soot rings, darkest in the middle, with flecks thrown out.
	for ring in 4:
		var r := size * (.92 - ring * .2)
		var pts := PackedVector2Array()
		for i in 28:
			var a := i * TAU / 28.0
			var rr := r * (1.0 + rng.randf_range(-.18, .14) + .1 * sin(a * (3 + k) + k))
			pts.append(Vector2(c + cos(a) * rr, c + sin(a) * rr))
		var shade := 34 - ring * 8
		Paint.polygon(s, pts, Color8(shade, shade - 4, shade - 8, 90 + ring * 45))
	for _i in 22:
		var a := rng.randf_range(0, TAU)
		var d := size * rng.randf_range(.75, 1.0)
		var r2 := rng.randf_range(3, 8)
		Paint.ellipse(
			s,
			c + cos(a) * d - r2,
			c + sin(a) * d - r2,
			c + cos(a) * d + r2,
			c + sin(a) * d + r2,
			Color8(30, 26, 22, 170)
		)
	var out := s.resized(48, 48)
	return out


## A drop of milk in flight: cream white, a shine on top, a bluish belly.
func milk_drop() -> Paint.Sheet:
	var s := Paint.Sheet.new(32, 32)
	Paint.ellipse(s, 6, 4, 26, 28, Color8(196, 200, 206))
	Paint.ellipse(s, 7, 4, 25, 23, Color8(246, 242, 228))
	Paint.ellipse(s, 11, 7, 17, 13, Color8(255, 255, 250))
	return shrunk(s, 8, 8, 100)


## A green spark shed by the alien arm gun's bolt.
func mote(k: int) -> Paint.Sheet:
	var s := Paint.Sheet.new(24, 24)
	if k == 0:
		Paint.ellipse(s, 3, 3, 20, 20, Color8(90, 230, 110))
		Paint.ellipse(s, 8, 8, 15, 15, Color8(220, 255, 210))
	else:
		Paint.ellipse(s, 6, 6, 17, 17, Color8(60, 170, 80))
		Paint.ellipse(s, 10, 10, 13, 13, Color8(170, 250, 170))
	return shrunk(s, 5, 5, 80)


## Milk hitting something: a crown of drops thrown up and out, then falling.
func milk_splash(k: int) -> Paint.Sheet:
	var s := Paint.Sheet.new(96, 96)
	var cream := Color8(244, 240, 226)
	var shade := Color8(198, 202, 210)
	var spread := 14.0 + k * 13.0
	var lift := 30.0 - k * 9.0
	# The sheet of milk at the foot, thinning as the crown opens.
	var foot := 34.0 - k * 6.0
	Paint.ellipse(s, 48 - foot, 78, 48 + foot, 90, shade)
	Paint.ellipse(s, 48 - foot + 4, 78, 48 + foot - 4, 86, cream)
	for i in 9:
		var a := -PI + (i + .5) * PI / 9.0
		var x := 48.0 + cos(a) * spread * 1.6
		var y := 82.0 + sin(a) * lift * (1.3 if i % 2 else 1.0) + k * k * 4.0
		var r := (6.0 - k * 1.4) * (1.0 if i % 3 else 1.3)
		if k < 2:
			# A thread of milk back down to the sheet.
			Paint.line2(s, 48 + cos(a) * spread * .6, 82, x, y, cream, 5.0)
		Paint.ellipse(s, x - r, y - r, x + r, y + r, shade)
		Paint.ellipse(s, x - r + 1, y - r, x + r - 1, y + r - 2, cream)
	return shrunk(s, 24, 24, 100)


## A pool of spilt milk on the ground, with drops flicked out around it.
func milk_puddle(k: int) -> Paint.Sheet:
	var size := 80
	var s := Paint.Sheet.new(size * 2, size * 2)
	var c := size
	var pts := PackedVector2Array()
	for i in 24:
		var a := i * TAU / 24.0
		var rr := size * .62 * (1.0 + rng.randf_range(-.22, .16) + .12 * sin(a * (2 + k) + k))
		pts.append(Vector2(c + cos(a) * rr, c + sin(a) * rr))
	Paint.polygon(s, pts, Color8(214, 216, 220, 200))
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(Vector2(c, c).lerp(p, .8))
	Paint.polygon(s, inner, Color8(240, 238, 228, 215))
	for _i in 14:
		var a := rng.randf_range(0, TAU)
		var d := size * rng.randf_range(.7, .98)
		var r2 := rng.randf_range(3, 9)
		Paint.ellipse(
			s,
			c + cos(a) * d - r2,
			c + sin(a) * d - r2,
			c + cos(a) * d + r2,
			c + sin(a) * d + r2,
			Color8(236, 234, 226, 200)
		)
	return s.resized(40, 40)


func crow(k: int) -> Paint.Sheet:
	var s := Paint.Sheet.new(96, 48)
	var black := Color8(22, 20, 24)
	Paint.ellipse(s, 34, 20, 62, 32, black)  # body
	Paint.ellipse(s, 58, 18, 70, 28, black)  # head
	Paint.polygon(
		s,
		PackedVector2Array([Vector2(69, 22), Vector2(78, 24), Vector2(69, 26)]),
		Color8(52, 46, 40)
	)
	var tail := PackedVector2Array([Vector2(34, 24), Vector2(20, 20), Vector2(22, 30)])
	Paint.polygon(s, tail, black)
	var tip := 4.0 if k == 0 else 44.0
	for side: float in [-1.0, 1.0]:
		Paint.polygon(
			s,
			PackedVector2Array([Vector2(40, 24), Vector2(56, 24), Vector2(48 + side * 26, tip)]),
			black
		)
	return shrunk(s, 24, 12)


func firefly(k: int) -> Paint.Sheet:
	var s := Paint.Sheet.new(24, 24)
	if k == 0:
		Paint.ellipse(s, 4, 4, 19, 19, Color8(186, 240, 96))
		Paint.ellipse(s, 8, 8, 15, 15, Color8(244, 255, 196))
	else:
		Paint.ellipse(s, 9, 9, 14, 14, Color8(70, 76, 40))
	return shrunk(s, 4, 4, 80)


## Muddy water standing a cell wide: dusk sky in it, ripples, a darker edge
## where it wets the dirt, its rim ragged so the cells run into each other.
func flood_water(k: int) -> Paint.Sheet:
	var size := 96
	var s := Paint.Sheet.new(size * 2, size * 2)
	var c := size
	var pts := PackedVector2Array()
	for i in 28:
		var a := i * TAU / 28.0
		var rr := size * .9 * (1.0 + rng.randf_range(-.12, .08) + .06 * sin(a * (3 + k) + k))
		pts.append(Vector2(c + cos(a) * rr, c + sin(a) * rr))
	Paint.polygon(s, pts, Color8(66, 58, 46, 220))
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(Vector2(c, c).lerp(p, .86))
	Paint.polygon(s, inner, Color8(104, 116, 128, 225))
	# The sky in it, and ripples across.
	for _i in 9:
		var y := rng.randf_range(c - size * .6, c + size * .6)
		var x0 := rng.randf_range(c - size * .7, c - size * .1)
		var x1 := x0 + rng.randf_range(size * .3, size * .8)
		Paint.rect(s, x0, y, x1, y + rng.randf_range(2, 5), Color8(162, 172, 184, 230))
	for _i in 5:
		var y := rng.randf_range(c - size * .5, c + size * .5)
		var x0 := rng.randf_range(c - size * .6, c)
		Paint.rect(s, x0, y, x0 + rng.randf_range(10, 40), y + 2, Color8(214, 196, 160, 230))
	return s.resized(48, 48)
