## The map kit's tiles (pass 16, T5), into assets/tiles: cedar shingles worn
## grey, white clapboard with the paint going, grey weathered clapboard,
## painted trim boards, a fieldstone foundation, the church's coloured glass
## (dark and lit), a silo's concrete staves under rusty hoops, a gas
## station canopy's underside with its light boxes, and grey-painted porch
## boards worn through where folks walk, and a hay bale's side (straw in
## flakes, two twine bands). Each tiles without a seam and is
## committed to the VGA palette. data/index.json lists them at the end;
## effects.cfg [glow] makes the lit glass glow.
##
##   godot --headless --path godot --script res://tools/art/build_kit_art.gd [-- out=<dir>]
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")
const N := 128


func _init() -> void:
	var out := Paint.repo("assets/tiles")
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	var made := {
		"kit_shingle": shingle(),
		"kit_clapboard": clapboard(true),
		"kit_clapboard_grey": clapboard(false),
		"kit_trim": trim(),
		"kit_stone": stone(),
		"kit_church_glass": glass(false),
		"kit_church_glass_lit": glass(true),
		"kit_staves": staves(),
		"kit_canopy": canopy(),
		"kit_porch": porch(),
		"kit_hay": hay(),
	}
	for name: String in made:
		var sheet: Paint.Sheet = made[name]
		for i in sheet.w * sheet.h:
			sheet.data[i * 4 + 3] = 255
		sheet.save(out.path_join(name + ".png"))
	print("kit tiles: %d" % made.size())
	quit()


static func _dice(seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return rng


static func _put(s: Paint.Sheet, x: int, y: int, c: Vector3) -> void:
	s.put(posmod(x, N), posmod(y, N), Paint.rgb(c.x, c.y, c.z))


## Cedar shingles in staggered courses: each shingle its own grey-brown, a
## dark slot between them, the course above throwing a shadow, moss here and
## there, a few newer ones nailed in.
func shingle() -> Paint.Sheet:
	var s := Paint.Sheet.new(N, N)
	var rng := _dice(1601)
	var cloud := Paint.cloud_seamless(N, 1602)
	var moss := Paint.cloud_seamless(N, 1603, [8, 16, 32])
	var course := 16
	for row in N / course:
		var x := rng.randi_range(0, 12) + (8 if row % 2 else 0)
		var start := x
		while x < start + N:
			var w := rng.randi_range(8, 15)
			var tone := Vector3(108, 98, 88) * rng.randf_range(.7, 1.15)
			if rng.randf() < .06:
				tone = Vector3(128, 100, 76)  # a newer one, not grey yet
			var streaks: Array[int] = [rng.randi_range(2, w - 1), rng.randi_range(2, w - 1)]
			var butt := rng.randi_range(0, 2)
			for yy in course:
				for xx in w:
					var px := x + xx
					var py := row * course + yy
					var i := posmod(py, N) * N + posmod(px, N)
					var c := tone * (.88 + .24 * cloud[i])
					c *= 1.08 - .3 * (float(yy) / course)
					if yy < 3 + butt:
						c *= .5  # the shadow under the course above
					elif yy < 5 + butt:
						c *= 1.12
					if xx == 0:
						c = Vector3(30, 28, 26)  # the slot
					elif streaks.has(xx) and yy > 3:
						c *= .82  # a split in the grain
					if moss[i] > .7 and yy > 5:
						c = c.lerp(Vector3(84, 98, 60), clampf((moss[i] - .7) * 3.0, 0.0, .5))
					_put(s, px, py, c)
			x += w
	return Paint.digitize(s, 6.0)


## Lap boards 16 px high: the lap's dark shadow under each, a lit top, grain;
## painted white with the paint flaking off to grey wood (true), or bare
## weathered grey with old paint in the cracks (false).
func clapboard(white: bool) -> Paint.Sheet:
	var s := Paint.Sheet.new(N, N)
	var rng := _dice(1611 if white else 1612)
	var flake := Paint.cloud_seamless(N, 1613 if white else 1614, [8, 16, 32, 64])
	var grain := Paint.cloud_seamless(N, 1615, [4, 64])
	var board := 16
	for y in N:
		var yy := y % board
		var row := y / board
		var joint := (row * 37) % N
		for x in N:
			var i := y * N + x
			var wood := Vector3(120, 112, 100) * (.82 + .3 * grain[i])
			if (x + row * 5) % 9 == 0:
				wood *= .9
			var c := wood
			if white:
				var paint := Vector3(214, 210, 196) * (.94 + .1 * flake[i])
				c = paint if flake[i] < .66 else wood
				if flake[i] >= .66 and flake[i] < .69:
					c = Vector3(150, 146, 136)  # the paint's broken edge
			else:
				c = wood * Vector3(.86, .9, .94)
				if flake[i] < .2:
					c = c.lerp(Vector3(178, 172, 160), .5)  # old paint left in the grain
			if yy < 2:
				c *= .5  # the lap's shadow
			elif yy < 4:
				c *= 1.1
			elif yy > board - 3:
				c *= .82
			if absi(x - joint) < 1:
				c *= .6  # a butt joint
			c += Vector3.ONE * rng.randfn(0.0, 2.0)
			_put(s, x, y, c)
	return Paint.digitize(s, 6.0)


## Painted trim: two upright boards, white gone creamy, worn at the edges.
func trim() -> Paint.Sheet:
	var s := Paint.Sheet.new(N, N)
	var rng := _dice(1621)
	var wear := Paint.cloud_seamless(N, 1622, [8, 16, 32])
	for y in N:
		for x in N:
			var i := y * N + x
			var c := Vector3(222, 216, 196) * (.92 + .1 * wear[i])
			var edge := x % 64
			if edge < 2 or edge > 61:
				c *= .62
			elif edge < 5:
				c *= 1.06
			if wear[i] > .7:
				c = c.lerp(Vector3(122, 108, 90), .7)
			if (y + x * 3) % 23 == 0:
				c *= .95
			c += Vector3.ONE * rng.randfn(0.0, 2.0)
			_put(s, x, y, c)
	return Paint.digitize(s, 6.0)


## Fieldstone in mortar: round-ish stones of every grey and brown (the
## nearest of points that wrap round the tile), lit from above.
func stone() -> Paint.Sheet:
	var s := Paint.Sheet.new(N, N)
	var rng := _dice(1631)
	var cloud := Paint.cloud_seamless(N, 1632, [8, 16, 32, 64])
	var points: Array[Vector2] = []
	var tones: Array[Vector3] = []
	for k in 30:
		points.append(Vector2(rng.randf() * N, rng.randf() * N))
		var base := rng.randf_range(84, 140)
		tones.append(
			Vector3(base * rng.randf_range(.96, 1.12), base, base * rng.randf_range(.84, .98))
		)
	for y in N:
		for x in N:
			var near := 1e9
			var second := 1e9
			var pick := 0
			var lift := 0.0
			for k in points.size():
				var dx := absf(x - points[k].x)
				var dy := absf(y - points[k].y)
				dx = minf(dx, N - dx)
				dy = minf(dy, N - dy)
				var dist := sqrt(dx * dx * .7 + dy * dy * 1.2)
				if dist < near:
					second = near
					near = dist
					pick = k
					var up := y - points[k].y
					if absf(up) > N * .5:
						up -= signf(up) * N
					lift = -up / 14.0
				elif dist < second:
					second = dist
			var i := y * N + x
			var c := tones[pick] * (.82 + .3 * cloud[i]) * (1.0 + .18 * clampf(lift, -1.0, 1.0))
			if second - near < 2.6:
				c = Vector3(70, 66, 60) * (.9 + .2 * cloud[i])  # the mortar
			elif second - near < 4.0:
				c *= .78
			_put(s, x, y, c)
	return Paint.digitize(s, 6.0)


## Coloured glass in lead: diamond quarries round a ring in the middle, deep
## red, blue, amber and green; dark from outside, or lit from within.
func glass(lit: bool) -> Paint.Sheet:
	var s := Paint.Sheet.new(N, N)
	var rng := _dice(1641)
	var colours: Array[Vector3] = [
		Vector3(150, 30, 30),
		Vector3(40, 60, 150),
		Vector3(196, 144, 40),
		Vector3(48, 120, 60),
		Vector3(120, 40, 120)
	]
	var mid := Vector2(N * .5, N * .5)
	for y in N:
		for x in N:
			var p := Vector2(x, y)
			var r := p.distance_to(mid)
			var u := (x + y) % 32
			var v := (x - y + N) % 32
			var lead := u < 2 or v < 2
			var pane := ((x + y) / 32 + (x - y + N) / 32) % colours.size()
			if r < 30.0:
				var ang := atan2(y - mid.y, x - mid.x)
				pane = int(floor((ang + PI) / TAU * 8.0)) % 2 + 2
				lead = absf(r - 29.0) < 1.5 or fmod(ang + PI, TAU / 8.0) < .08
				if r < 9.0:
					pane = 0
					lead = absf(r - 8.0) < 1.5
			var c: Vector3 = colours[pane]
			c *= .9 + .2 * sin(x * .3) * sin(y * .21)
			if lit:
				c = c * 1.55 + Vector3(40, 34, 20)
				c *= 1.0 - .25 * (r / (N * .7))
			else:
				c *= .42
			if x < 3 or y < 3 or x > N - 4 or y > N - 4 or lead:
				c = Vector3(26, 24, 22)
			c += Vector3.ONE * rng.randfn(0.0, 1.5)
			_put(s, x, y, c)
	return Paint.digitize(s, 6.0)


## A silo's concrete staves: blocks a half tile wide in courses, each lift a
## shade apart, a rusty steel hoop round every second course, rust run down.
func staves() -> Paint.Sheet:
	var s := Paint.Sheet.new(N, N)
	var rng := _dice(1651)
	var cloud := Paint.cloud_seamless(N, 1652, [8, 16, 32, 64])
	var streak := Paint.cloud_seamless(N, 1653, [16, 64])
	var shades: Array[float] = []
	for k in 16:
		shades.append(rng.randf_range(.9, 1.08))
	for y in N:
		var course := y / 32
		for x in N:
			var i := y * N + x
			var block := ((x + (16 if course % 2 else 0)) % N) / 64
			var c := (
				Vector3(150, 148, 140) * shades[(course * 2 + block) % 16] * (.84 + .26 * cloud[i])
			)
			var cx := (x + (16 if course % 2 else 0)) % 64
			if y % 32 < 2 or cx < 2:
				c *= .7  # the joints
			var hoop := y % 64
			if hoop >= 58 and hoop < 62:
				c = Vector3(96, 58, 40) * (.8 + .3 * cloud[i])  # the hoop
				if hoop == 58:
					c *= 1.25
			elif hoop >= 62 or hoop < 22:
				var run := streak[x] * (1.0 - float((hoop + 6) % 64) / 28.0)
				if run > .45:
					c = c.lerp(Vector3(124, 80, 52), clampf((run - .45) * 2.2, 0.0, .6))
			_put(s, x, y, c)
	return Paint.digitize(s, 6.0)


## A canopy's underside: cream steel panels on seams, a light box down the
## middle, grime and bug spots round it.
func canopy() -> Paint.Sheet:
	var s := Paint.Sheet.new(N, N)
	var rng := _dice(1661)
	var grime := Paint.cloud_seamless(N, 1662, [8, 16, 32])
	for y in N:
		for x in N:
			var i := y * N + x
			var c := Vector3(206, 200, 178) * (.88 + .14 * grime[i])
			if x % 32 < 2:
				c *= .66  # a panel seam
			elif x % 32 == 2:
				c *= 1.08
			var box := absi(y - 64)
			if box < 10 and x > 12 and x < 116:
				c = Vector3(250, 246, 226) if box < 7 else Vector3(110, 108, 100)
			elif box < 18 and rng.randf() < .03:
				c = Vector3(40, 36, 30)  # the bugs it drew
			_put(s, x, y, c)
	return Paint.digitize(s, 6.0)


## Porch boards painted battleship grey, worn to the wood down the middle
## where folks walk; a dark gap and nail heads between boards.
func porch() -> Paint.Sheet:
	var s := Paint.Sheet.new(N, N)
	var rng := _dice(1671)
	var wear := Paint.cloud_seamless(N, 1672, [8, 16, 32, 64])
	var grain := Paint.cloud_seamless(N, 1673, [4, 64])
	for y in N:
		for x in N:
			var i := y * N + x
			var board := x % 16
			var c := Vector3(120, 126, 130) * (.9 + .12 * wear[i])
			var walked := wear[i] + .35 * (1.0 - absf(y - 64.0) / 64.0)
			if walked > .82:
				c = Vector3(128, 104, 78) * (.8 + .35 * grain[i])  # the wood through it
			if board < 1:
				c = Vector3(30, 28, 26)
			elif board == 1:
				c *= .8
			if (board == 3 or board == 12) and (y + x * 5) % 32 == 0:
				c = Vector3(60, 60, 64)  # a nail
			if (y + (x / 16) * 41) % N == 0:
				c *= .55  # a board's end
			c += Vector3.ONE * rng.randfn(0.0, 2.0)
			_put(s, x, y, c)
	return Paint.digitize(s, 6.0)


## A hay bale's side: short straw strokes, packed in flakes, two twine bands.
func hay() -> Paint.Sheet:
	var s := Paint.Sheet.new(N, N)
	var rng := _dice(1681)
	var cloud := Paint.cloud_seamless(N, 1682, [8, 16, 32])
	for y in N:
		for x in N:
			var i := y * N + x
			var c := Vector3(186, 160, 92) * (.78 + .3 * cloud[i])
			if y % 21 < 2:
				c *= .72  # between the flakes
			_put(s, x, y, c)
	for k in 900:
		var x := rng.randi_range(0, N - 1)
		var y := rng.randi_range(0, N - 1)
		var length := rng.randi_range(4, 11)
		var tone := Vector3(214, 190, 120) if rng.randf() < .6 else Vector3(120, 100, 56)
		for j in length:
			_put(s, x + j, y + int(j * rng.randf_range(-.3, .3)), tone * rng.randf_range(.85, 1.1))
	for band: int in [40, 88]:
		for y in N:
			for dx in 3:
				var c := Vector3(70, 56, 40) if dx < 2 else Vector3(40, 32, 24)
				_put(s, band + dx, y, c)
	return Paint.digitize(s, 6.0)
