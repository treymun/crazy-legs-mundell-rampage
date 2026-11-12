## Paint what bullets and blasts leave and throw (features/impacts.gd) into
## assets/art, in the chunky look of the other effects:
##
##   fx_hole_tin      a round punched through sheet tin, its torn lip bright
##   fx_hole_brick    a chipped crater in brick, red dust round it
##   fx_hole_glass    a star of cracks round a small hole in a pane
##   fx_bloodrun_N / fx_acidrun_N   (6) blood running down a wall from a splat
##   fx_scorch_wall_N (2) soot up a wall beside a blast
##   fx_splinter_N    (2) a sliver of plank tumbling
##   fx_grit_brick, fx_grit_stone   a chip of brick, of stone
##   fx_chaff_N       (2) a husk of corn or leaf off a hedge
##   fx_glint_N       a chip of glass: dull, and catching the light
##   mark_pock_N      (2) a bullet's pock in a dirt floor
##
##   godot --headless --path godot --script res://tools/art/build_impact_art.gd [-- out=<dir>]
##
## Then run tools/pack_assets.gd.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")

var dice := RandomNumberGenerator.new()


func _init() -> void:
	var out := Paint.repo("assets/art")
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	var count := 0
	dice.seed = 1977
	tin_hole().save(out.path_join("fx_hole_tin.png"))
	brick_hole().save(out.path_join("fx_hole_brick.png"))
	glass_crack().save(out.path_join("fx_hole_glass.png"))
	count += 3
	for k in 6:
		run(k, false).save(out.path_join("fx_bloodrun_%d.png" % k))
		run(k, true).save(out.path_join("fx_acidrun_%d.png" % k))
		count += 2
	for k in 2:
		wall_scorch(k).save(out.path_join("fx_scorch_wall_%d.png" % k))
		splinter(k).save(out.path_join("fx_splinter_%d.png" % k))
		chaff(k).save(out.path_join("fx_chaff_%d.png" % k))
		glint(k).save(out.path_join("fx_glint_%d.png" % k))
		pock(k).save(out.path_join("mark_pock_%d.png" % k))
		count += 5
	grit(Vector3(150, 62, 44)).save(out.path_join("fx_grit_brick.png"))
	grit(Vector3(150, 146, 136)).save(out.path_join("fx_grit_stone.png"))
	count += 2
	print("impact art: %d pictures in %s" % [count, out])
	quit()


func _c(v: Vector3, a := 255.0) -> Color:
	return Color8(
		clampi(int(v.x), 0, 255), clampi(int(v.y), 0, 255), clampi(int(v.z), 0, 255), int(a)
	)


## A hash of a pixel, 0 to 1: speckle that is the same every build.
func _speck(x: int, y: int, seed: int) -> float:
	var h := x * 374761393 + y * 668265263 + seed * 1274126177
	h = (h ^ (h >> 13)) * 1274126177
	return float((h ^ (h >> 16)) & 1023) / 1023.0


func tin_hole() -> Paint.Sheet:
	var s := Paint.Sheet.new(19, 19)
	var c := 9.0
	for y in 19:
		for x in 19:
			var dx := x - c
			var dy := y - c
			var r := sqrt(dx * dx + dy * dy)
			var a := atan2(dy, dx)
			# Petals of torn tin round the hole, pushed in.
			var lip := 3.6 + 1.6 * absf(sin(a * 3.0 + .4)) + _speck(x, y, 3) * .6
			if r < 2.4:
				s.put(x, y, _c(Vector3(14, 12, 12)))
			elif r < 3.2:
				s.put(x, y, _c(Vector3(46, 44, 48)))
			elif r < lip:
				var shine := .55 + .45 * clampf(-dx / 3.0 - dy / 4.0, -1, 1)
				s.put(x, y, _c(Vector3(168, 174, 184) * shine + Vector3(30, 30, 34)))
			elif r < lip + 1.4:
				s.put(x, y, _c(Vector3(70, 66, 64), 170))
			elif r < lip + 2.6 and _speck(x, y, 9) < .35:
				s.put(x, y, _c(Vector3(96, 76, 58), 120))
	return s


func brick_hole() -> Paint.Sheet:
	var s := Paint.Sheet.new(19, 19)
	var c := 9.0
	for y in 19:
		for x in 19:
			var dx := x - c
			var dy := y - c
			var r := sqrt(dx * dx + dy * dy) + (_speck(x, y, 5) - .5) * 1.6
			if r < 2.2:
				s.put(x, y, _c(Vector3(20, 12, 10)))
			elif r < 4.4:
				# The crater: raw brick, darker in, lit from up left.
				var lit := .7 + .3 * clampf((dx + dy) / 5.0, -1, 1)
				s.put(x, y, _c(Vector3(126, 58, 40) * lit))
			elif r < 6.4 and _speck(x, y, 7) < .6:
				s.put(x, y, _c(Vector3(176, 104, 78), 200))
			elif r < 8.6 and _speck(x, y, 11) < .25:
				s.put(x, y, _c(Vector3(150, 96, 74), 120))
	return s


func glass_crack() -> Paint.Sheet:
	var size := 32
	var s := Paint.Sheet.new(size, size)
	var c := Vector2(15.5, 15.5)
	var line_colour := _c(Vector3(226, 236, 240), 210)
	var dim := _c(Vector3(180, 196, 204), 150)
	var rays := 9
	for k in rays:
		var a := k * TAU / rays + dice.randf_range(-.25, .25)
		var length := dice.randf_range(9.0, 15.0)
		var at := c
		var heading := a
		var step := 0.0
		while step < length:
			heading += dice.randf_range(-.18, .18)
			at += Vector2(cos(heading), sin(heading))
			step += 1.0
			s.put(int(at.x), int(at.y), line_colour if step < length * .6 else dim)
	# A ring of cracks a little way out, broken.
	for k in 48:
		var a := k * TAU / 48.0
		if _speck(k, 0, 13) < .35:
			continue
		var r := 5.5 + _speck(k, 1, 17) * 1.2
		s.put(int(c.x + cos(a) * r), int(c.y + sin(a) * r), dim)
	for y in size:
		for x in size:
			var r := Vector2(x, y).distance_to(c)
			if r < 1.6:
				s.put(x, y, _c(Vector3(20, 24, 28)))
			elif r < 3.0:
				s.put(x, y, _c(Vector3(236, 244, 248), 230))
	return s


## Blood running down from the top of the picture: `stage` (0 to 5) how far.
func run(stage: int, acid: bool) -> Paint.Sheet:
	var size := 32
	var s := Paint.Sheet.new(size, size)
	var dark := Vector3(70, 150, 50) * .7 if acid else Vector3(96, 8, 8)
	var wet := Vector3(110, 196, 70) if acid else Vector3(150, 18, 16)
	var reach := (stage + 1) / 6.0
	# Three runs from under the splat, the middle one longest, each thinning
	# as it goes and ending in a bead.
	for strand in [[15.5, 1.0, 1.3], [12.0, .6, .8], [19.0, .78, .9]]:
		var cx: float = strand[0]
		var length: float = float(strand[1]) * reach * (size - 6)
		var width: float = strand[2]
		var end_x := cx
		var end_y := 4
		for y in range(4, size - 2):
			var down := y - 4.0
			if down > length:
				break
			var wobble := sin(y * .23 + cx) * .7
			var thin := width * (1.0 - .45 * down / maxf(1.0, length))
			for x in size:
				var off := absf(x + .5 - cx - wobble)
				if off <= thin:
					s.put(x, y, _c(wet if off < thin * .45 else dark, 235))
			end_x = cx + wobble
			end_y = y
		# The bead gathering at its end.
		var bx := int(end_x)
		s.put(bx, end_y + 1, _c(wet, 240))
		s.put(bx - 1, end_y + 1, _c(dark, 240))
		s.put(bx, end_y + 2, _c(dark, 240))
	return s


func wall_scorch(k: int) -> Paint.Sheet:
	var size := 48
	var s := Paint.Sheet.new(size, size)
	var c := Vector2(23.5, 27.0)
	for y in size:
		for x in size:
			var d := Vector2(x, y) - c
			# Soot climbs: the blotch reaches higher than it is wide.
			d.y *= 1.0 if d.y > 0.0 else .62
			var r := d.length() / 21.0
			r += (_speck(x / 3, y / 3, 21 + k) - .5) * .28
			r += sin(atan2(d.y, d.x) * (5.0 + k) + k) * .06
			if r > 1.0:
				continue
			var dark := 1.0 - r
			var tone := Vector3(18, 14, 12).lerp(Vector3(54, 44, 36), r)
			var a := clampf(dark * 1.7, 0.0, 1.0) * 235.0
			if _speck(x, y, 31 + k) > .82 and r > .5:
				a *= .4
			s.put(x, y, _c(tone, a))
	return s


func splinter(k: int) -> Paint.Sheet:
	var s := Paint.Sheet.new(10, 10)
	var a := .5 if k == 0 else 2.2
	var dir := Vector2(cos(a), sin(a))
	for t in range(-4, 5):
		var at := Vector2(4.5, 4.5) + dir * t
		var tone := Vector3(214, 176, 120) if t < 2 else Vector3(150, 110, 66)
		s.put(int(at.x), int(at.y), _c(tone))
		if absf(t) < 2:
			var side := at + Vector2(-dir.y, dir.x)
			s.put(int(side.x), int(side.y), _c(Vector3(120, 84, 50)))
	return s


func grit(tone: Vector3) -> Paint.Sheet:
	var s := Paint.Sheet.new(8, 8)
	for y in 8:
		for x in 8:
			var r := Vector2(x - 3.5, (y - 3.5) * 1.3).length() + _speck(x, y, int(tone.x)) * 1.2
			if r < 2.6:
				var lit := .75 + .25 * clampf((3.5 - x + 3.5 - y) / 4.0, -1, 1)
				s.put(x, y, _c(tone * lit))
			elif r < 3.2:
				s.put(x, y, _c(tone * .45))
	return s


func chaff(k: int) -> Paint.Sheet:
	var s := Paint.Sheet.new(10, 10)
	var tone := Vector3(176, 160, 76) if k == 0 else Vector3(92, 116, 48)
	for y in 10:
		for x in 10:
			var u := (x - 4.5) * (.9 if k == 0 else .6)
			var v := (y - 4.5) * (.45 if k == 0 else .9)
			if u * u + v * v < 4.0:
				s.put(x, y, _c(tone * (.8 + .4 * _speck(x, y, 41 + k))))
	return s


func glint(k: int) -> Paint.Sheet:
	var s := Paint.Sheet.new(8, 8)
	if k == 0:
		for y in range(2, 6):
			for x in range(2, 6):
				if (x + y) % 3 != 0:
					s.put(x, y, _c(Vector3(170, 196, 204), 220))
		s.put(3, 3, _c(Vector3(230, 244, 248)))
	else:
		for t in range(-3, 4):
			var tone := Vector3(255, 255, 250) if absf(t) < 2 else Vector3(190, 220, 240)
			s.put(3 + t, 3, _c(tone))
			s.put(3, 3 + t, _c(tone))
		s.put(4, 4, _c(Vector3(220, 236, 246), 200))
	return s


func pock(k: int) -> Paint.Sheet:
	var size := 24
	var s := Paint.Sheet.new(size, size)
	var c := 11.5
	for y in size:
		for x in size:
			var r := Vector2(x - c, y - c).length() + (_speck(x, y, 51 + k) - .5) * 2.0
			if r < 2.6:
				s.put(x, y, _c(Vector3(26, 20, 14), 240))
			elif r < 4.6:
				s.put(x, y, _c(Vector3(62, 48, 34), 210))
			elif r < 8.0 and _speck(x, y, 61 + k) < .3:
				s.put(x, y, _c(Vector3(140, 116, 84), 150))
			elif r < 11.0 and _speck(x, y, 71 + k) < .1:
				s.put(x, y, _c(Vector3(120, 98, 70), 110))
	return s
