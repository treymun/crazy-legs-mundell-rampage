## Paint the gore sprites into assets/art: gibs, wall and floor splatters, in
## blood red and alien green.
##
##   godot --headless --path godot --script res://tools/art/build_gore_art.gd [-- out=<dir>]
##
## Each is drawn at four times its size and shrunk, then given a hard alpha
## edge like the rest of the sprites:
##   gib_<part> / gib_a_<part>   chunks thrown by an overkill (human / alien)
##   fx_blood_N / fx_acid_N      splats for walls
##   mark_blood_N / mark_acid_N  pools and drops for the floor
##   gib_m_<part>                scrap off a robot (bolt, gear, plate, spring, pipe)
##   gib_c_<part>                a chunk charred by a blast
##   mark_oil_N / fx_oil_N       a robot's oil on the floor and the walls
##   mark_streak_<blood|acid>_N  blood thrown along the floor (laid along the shot)
##   mark_print_<blood|acid>     a boot print walked out of a pool
## Then run tools/pack_assets.gd. out= writes somewhere else instead (to compare).
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")
const U := 4
const FLESH := Color8(150, 30, 26)
const FLESH_DARK := Color8(92, 14, 14)
const BONE := Color8(222, 206, 170)
const SLIME := Color8(96, 168, 60)
const SLIME_DARK := Color8(44, 96, 34)
const CHITIN := Color8(200, 214, 150)
const SIZES := {
	"eye": 14,
	"meat": 22,
	"chunk": 28,
	"organ": 26,
	"rib": 34,
	"arm": 36,
	"boot": 34,
	"head": 30,
	"hand": 18,
	"gut": 30
}
const PARTS := ["arm", "boot", "rib", "eye", "meat", "chunk", "organ", "head", "hand", "gut"]
## Scrap off a robot, and how big each is drawn.
const SCRAP := {"bolt": 14, "gear": 22, "plate": 28, "spring": 20, "pipe": 30}
const STEEL := Color8(150, 154, 160)
const STEEL_DARK := Color8(70, 74, 82)
const RUST := Color8(150, 76, 34)
const OIL := Color8(36, 30, 26)
const OIL_DEEP := Color8(14, 12, 10)

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 1997
	var out := Paint.repo("assets/art")
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	var count := 0
	for pair in [[false, "gib_"], [true, "gib_a_"]]:
		for part: String in PARTS:
			gib(part, pair[0]).save(out.path_join("%s%s.png" % [pair[1], part]))
			count += 1
	for pair in [[false, "blood"], [true, "acid"]]:
		var alien: bool = pair[0]
		for k in 4:
			splat(alien, false, 40 + k + (100 if alien else 0)).save(
				out.path_join("fx_%s_%d.png" % [pair[1], k])
			)
			count += 1
		for k in 3:
			splat(alien, true, 80 + k + (100 if alien else 0)).save(
				out.path_join("mark_%s_%d.png" % [pair[1], k])
			)
			count += 1
	for part: String in SCRAP:
		scrap(part).save(out.path_join("gib_m_%s.png" % part))
		count += 1
	for part: String in PARTS:
		charred(gib(part, false)).save(out.path_join("gib_c_%s.png" % part))
		count += 1
	for k in 3:
		splat_in(OIL, OIL_DEEP, true, 300 + k).save(out.path_join("mark_oil_%d.png" % k))
		splat_in(OIL, OIL_DEEP, false, 320 + k).save(out.path_join("fx_oil_%d.png" % k))
		count += 2
	for pair in [[false, "blood"], [true, "acid"]]:
		for k in 2:
			streak(pair[0], 400 + k + (100 if pair[0] else 0)).save(
				out.path_join("mark_streak_%s_%d.png" % [pair[1], k])
			)
			count += 1
		boot_print(pair[0]).save(out.path_join("mark_print_%s.png" % pair[1]))
		count += 1
	print("gore art: %d sprites in %s" % [count, out])
	quit()


## Shrink, add grit and a dark rim, and cut the alpha hard.
func finish(big: Paint.Sheet, size: int) -> Paint.Sheet:
	var small := big.resized(size, size)
	var n := size * size
	var mask := PackedByteArray()
	mask.resize(n)
	for i in n:
		mask[i] = 1 if small.data[i * 4 + 3] >= 120 else 0
	var inner := Paint.shrink_mask(mask, size, size)
	for i in n:
		var o := i * 4
		if mask[i] == 0:
			for k in 4:
				small.data[o + k] = 0
			continue
		var grit := rng.randfn(0, 7)
		var dark := .55 if inner[i] == 0 else 1.0
		for k in 3:
			small.data[o + k] = clampi(int((small.data[o + k] + grit) * dark), 0, 255)
		small.data[o + 3] = 255
	return small


## A lumpy round shape, its outline wobbling `rough` about the radius.
func blob(
	s: Paint.Sheet, cx: float, cy: float, r: float, c: Color, lumps := 9, rough := .28
) -> void:
	var pts := PackedVector2Array()
	for k in lumps * 3:
		var a := k * TAU / (lumps * 3)
		var rr := r * (1 + rough * sin(a * lumps + cx) + rng.randf_range(-rough, rough) * .5)
		pts.append(Vector2(cx + cos(a) * rr, cy + sin(a) * rr * .86))
	Paint.polygon(s, pts, c)


## Round every drawn shape off: lit from the upper left, dark underneath.
func shade(s: Paint.Sheet) -> void:
	var soft := Paint.blur(Paint.channel(s, 3), s.w, s.h, U * 2.2)
	for y in s.h:
		for x in s.w:
			var i := y * s.w + x
			var gx := (soft[y * s.w + mini(x + 1, s.w - 1)] - soft[y * s.w + maxi(x - 1, 0)]) * .5
			var gy := (soft[mini(y + 1, s.h - 1) * s.w + x] - soft[maxi(y - 1, 0) * s.w + x]) * .5
			var lit := clampf(-(gx + gy) / 255.0 * 9, -1, 1)
			for k in 3:
				s.data[i * 4 + k] = clampi(
					int(s.data[i * 4 + k] * (1 + lit * .55) + lit * 26), 0, 255
				)


func gib(part: String, alien: bool) -> Paint.Sheet:
	var meat := SLIME if alien else FLESH
	var deep := SLIME_DARK if alien else FLESH_DARK
	var bone := CHITIN if alien else BONE
	var size: int = SIZES[part]
	var s := float(size * U)
	var im := Paint.Sheet.new(size * U, size * U)
	var skin := Color8(112, 128, 92) if alien else Color8(186, 122, 92)
	match part:
		"eye":
			blob(
				im,
				s * .45,
				s * .5,
				s * .36,
				Color8(30, 34, 30) if alien else Color8(226, 222, 204),
				5,
				.05
			)
			Paint.ellipse(
				im,
				s * .28,
				s * .34,
				s * .56,
				s * .62,
				Color8(120, 255, 140) if alien else Color8(70, 100, 60)
			)
			Paint.ellipse(im, s * .36, s * .42, s * .48, s * .54, Color8(8, 8, 8))
			Paint.line2(im, s * .7, s * .55, s * .96, s * .78, meat, U * 2)
		"meat", "chunk":
			blob(im, s * .5, s * .52, s * .36, deep, 7, .32)
			blob(im, s * .46, s * .48, s * .28, meat, 6, .3)
			if part == "chunk":
				Paint.rounded_rect(im, s * .58, s * .22, s * .86, s * .38, U * 2, bone)
				Paint.ellipse(im, s * .78, s * .16, s * .96, s * .44, bone)
		"organ":
			for k in 5:
				blob(
					im,
					s * (.28 + .11 * k),
					s * (.5 + .12 * sin(k * 1.9)),
					s * .17,
					deep if k % 2 else meat,
					5,
					.2
				)
			Paint.line2(im, s * .2, s * .7, s * .05, s * .9, deep, U * 2)
		"rib":
			Paint.rounded_rect(im, s * .44, s * .08, s * .56, s * .92, U * 2, bone)
			for k in 4:
				var y := s * (.2 + k * .19)
				Paint.arc(im, s * .1, y - s * .1, s * .9, y + s * .16, 200, 340, bone, U * 3)
			blob(im, s * .5, s * .56, s * .2, deep, 6, .35)
			blob(im, s * .42, s * .4, s * .12, meat, 5, .3)
		"arm":
			var cloth := Color8(58, 62, 54) if alien else Color8(126, 48, 42)
			Paint.line2(im, s * .16, s * .78, s * .52, s * .46, cloth, U * 8)
			Paint.line2(im, s * .5, s * .48, s * .8, s * .22, skin, U * 6)
			Paint.ellipse(im, s * .72, s * .1, s * .94, s * .32, skin)
			for k in 3:
				Paint.line2(
					im, s * .86, s * .16, s * (.99 - k * .05), s * (.02 + k * .09), skin, U * 2
				)
			blob(im, s * .16, s * .8, s * .13, deep, 5, .3)
			Paint.ellipse(im, s * .11, s * .75, s * .21, s * .85, bone)
		"head":
			blob(im, s * .5, s * .46, s * .30, skin, 6, .08)
			if alien:
				for sx: float in [.36, .64]:
					Paint.ellipse(
						im, s * (sx - .1), s * .36, s * (sx + .1), s * .56, Color8(8, 10, 12)
					)
			else:
				Paint.pieslice(im, s * .18, s * .1, s * .82, s * .6, 180, 360, Color8(70, 50, 34))
				for sx: float in [.38, .62]:
					Paint.ellipse(
						im, s * (sx - .05), s * .42, s * (sx + .05), s * .52, Color8(236, 230, 210)
					)
					Paint.ellipse(
						im, s * (sx - .02), s * .45, s * (sx + .02), s * .5, Color8(10, 10, 10)
					)
				Paint.ellipse(im, s * .4, s * .6, s * .6, s * .7, Color8(60, 14, 14))
			blob(im, s * .5, s * .82, s * .17, deep, 6, .4)
			Paint.ellipse(im, s * .44, s * .76, s * .56, s * .88, bone)
		"hand":
			blob(im, s * .45, s * .55, s * .24, skin, 5, .1)
			for k in 3 if alien else 4:
				Paint.line2(
					im, s * (.3 + k * .12), s * .42, s * (.26 + k * .15), s * .12, skin, U * 3
				)
			blob(im, s * .5, s * .82, s * .14, deep, 5, .4)
		"gut":
			var pink := Color8(150, 210, 120) if alien else Color8(196, 96, 96)
			var pts := PackedVector2Array()
			for k in 15:
				var t := k / 14.0
				pts.append(Vector2(s * (.12 + .76 * t), s * (.5 + .26 * sin(t * 9.0))))
			Paint.line(im, pts, deep, U * 8, true)
			Paint.line(im, pts, pink, U * 5, true)
		"boot":
			var leather := Color8(44, 40, 36) if alien else Color8(70, 48, 32)
			var cloth2 := Color8(52, 56, 50) if alien else Color8(66, 78, 108)
			Paint.rounded_rect(im, s * .32, s * .12, s * .58, s * .66, U * 3, cloth2)
			Paint.rounded_rect(im, s * .28, s * .5, s * .62, s * .84, U * 3, leather)
			Paint.rounded_rect(im, s * .28, s * .68, s * .92, s * .88, U * 4, leather)
			Paint.rect(im, s * .26, s * .86, s * .94, s * .92, Color8(24, 20, 18))
			blob(im, s * .45, s * .13, s * .15, deep, 5, .3)
			Paint.ellipse(im, s * .39, s * .06, s * .51, s * .18, bone)
	shade(im)
	return finish(im, size)


func splat(alien: bool, pool: bool, seed: int) -> Paint.Sheet:
	var wet := SLIME if alien else Color8(140, 22, 20)
	var deep := SLIME_DARK if alien else Color8(84, 10, 12)
	var size := 64 if pool else 48
	var s := float(size * U)
	var im := Paint.Sheet.new(size * U, size * U)
	var local := RandomNumberGenerator.new()
	local.seed = seed
	if pool:
		blob(im, s * .5, s * .5, s * local.randf_range(.26, .36), deep, 7, .22)
		blob(im, s * .5, s * .5, s * local.randf_range(.18, .26), wet, 6, .2)
		for _k in 9:
			var a := local.randf_range(0, TAU)
			var r := local.randf_range(.3, .47)
			var rr := s * local.randf_range(.012, .04)
			var x := s * (.5 + cos(a) * r)
			var y := s * (.5 + sin(a) * r)
			Paint.ellipse(im, x - rr, y - rr, x + rr, y + rr, deep)
	else:
		var cx := s * local.randf_range(.4, .6)
		var cy := s * local.randf_range(.3, .45)
		blob(im, cx, cy, s * local.randf_range(.16, .22), deep, 8, .4)
		blob(im, cx, cy, s * local.randf_range(.09, .14), wet, 6, .35)
		for _k in 14:
			var a := local.randf_range(0, TAU)
			var r := local.randf_range(.18, .46)
			var rr := s * local.randf_range(.01, .034)
			var x := cx + cos(a) * r * s
			var y := cy + sin(a) * r * s * .9
			Paint.ellipse(im, x - rr, y - rr, x + rr * 1.4, y + rr, deep)
		for _k in 4:
			var x := cx + local.randf_range(-.16, .16) * s
			var length := local.randf_range(.18, .46) * s
			var w := maxf(U, int(s * local.randf_range(.012, .028)))
			Paint.line2(im, x, cy, x, minf(s - U, cy + length), deep, w)
			Paint.ellipse(im, x - w, cy + length - w, x + w, cy + length + w, wet)
	var out := im.resized(size, size)
	var grit := Paint.noise(seed + 9, size * size, 6)
	for i in size * size:
		var o := i * 4
		for k in 3:
			out.data[o + k] = clampi(int(out.data[o + k] + grit[i]), 0, 255)
		out.data[o + 3] = 255 if out.data[o + 3] >= 110 else 0
	return out


## A piece of scrap off a robot, steel with rust and grease on it.
func scrap(part: String) -> Paint.Sheet:
	var size: int = SCRAP[part]
	var s := float(size * U)
	var im := Paint.Sheet.new(size * U, size * U)
	match part:
		"bolt":
			Paint.rounded_rect(im, s * .2, s * .2, s * .5, s * .5, U * 2, STEEL)
			Paint.line2(im, s * .4, s * .4, s * .86, s * .86, STEEL_DARK, U * 5)
			for k in 4:
				var t := .5 + k * .1
				Paint.line2(
					im, s * (t - .04), s * (t + .04), s * (t + .04), s * (t - .04), STEEL, U
				)
		"gear":
			for k in 10:
				var a := k * TAU / 10.0
				Paint.ellipse(
					im,
					s * (.5 + cos(a) * .36) - U * 3,
					s * (.5 + sin(a) * .36) - U * 3,
					s * (.5 + cos(a) * .36) + U * 3,
					s * (.5 + sin(a) * .36) + U * 3,
					STEEL
				)
			Paint.ellipse(im, s * .17, s * .17, s * .83, s * .83, STEEL)
			Paint.ellipse(im, s * .38, s * .38, s * .62, s * .62, STEEL_DARK)
			blob(im, s * .66, s * .3, s * .1, RUST, 5, .4)
		"plate":
			var pts := PackedVector2Array(
				[
					Vector2(s * .1, s * .3),
					Vector2(s * .7, s * .1),
					Vector2(s * .92, s * .5),
					Vector2(s * .6, s * .62),
					Vector2(s * .72, s * .9),
					Vector2(s * .18, s * .82)
				]
			)
			Paint.polygon(im, pts, STEEL_DARK)
			for k in 3:
				var x := s * (.28 + k * .2)
				Paint.ellipse(im, x - U * 2, s * .4 - U * 2, x + U * 2, s * .4 + U * 2, STEEL)
			blob(im, s * .3, s * .7, s * .12, RUST, 5, .4)
		"spring":
			var pts := PackedVector2Array()
			for k in 25:
				var t := k / 24.0
				pts.append(Vector2(s * (.15 + .7 * t), s * (.5 + .3 * sin(t * TAU * 3.0))))
			Paint.line(im, pts, STEEL_DARK, U * 4, true)
			Paint.line(im, pts, STEEL, U * 2, true)
		"pipe":
			Paint.line2(im, s * .14, s * .7, s * .86, s * .3, STEEL_DARK, U * 9)
			Paint.line2(im, s * .14, s * .7, s * .86, s * .3, STEEL, U * 6)
			Paint.ellipse(im, s * .76, s * .2, s * .96, s * .4, OIL_DEEP)
			blob(im, s * .3, s * .62, s * .1, RUST, 5, .4)
	shade(im)
	return finish(im, size)


## A chunk as a blast leaves it: blackened, a cinder still glowing here and there.
func charred(small: Paint.Sheet) -> Paint.Sheet:
	var n := small.w * small.h
	for i in n:
		var o := i * 4
		if small.data[o + 3] == 0:
			continue
		var lum := (small.data[o] + small.data[o + 1] + small.data[o + 2]) / 3.0
		var dark := lum * .32
		small.data[o] = clampi(int(dark + 18 + small.data[o] * .1), 0, 255)
		small.data[o + 1] = clampi(int(dark + 10), 0, 255)
		small.data[o + 2] = clampi(int(dark + 6), 0, 255)
		if rng.randf() < .05:
			small.data[o] = 236
			small.data[o + 1] = 120 + rng.randi() % 60
			small.data[o + 2] = 30
	return small


## splat() in any two colours (a robot's oil).
func splat_in(wet: Color, deep: Color, pool: bool, seed: int) -> Paint.Sheet:
	var made := splat(false, pool, seed)
	var red_wet := Color8(140, 22, 20)
	for i in made.w * made.h:
		var o := i * 4
		if made.data[o + 3] == 0:
			continue
		# How far toward the wet red the pixel is, and the same in the new colours.
		var t := clampf(float(made.data[o]) / float(red_wet.r8), 0.0, 1.0)
		var c := deep.lerp(wet, t)
		made.data[o] = c.r8
		made.data[o + 1] = c.g8
		made.data[o + 2] = c.b8
	return made


## Blood thrown along the floor: drops drawn out into a long tear, wide end
## toward the hit (the game lays it along the shot).
func streak(alien: bool, seed: int) -> Paint.Sheet:
	var wet := SLIME if alien else Color8(140, 22, 20)
	var deep := SLIME_DARK if alien else Color8(84, 10, 12)
	var size := 48
	var s := float(size * U)
	var im := Paint.Sheet.new(size * U, size * U)
	var local := RandomNumberGenerator.new()
	local.seed = seed
	for k in 6:
		var y := s * (.5 + local.randf_range(-.08, .08))
		var x0 := s * local.randf_range(.08, .3)
		var x1 := s * local.randf_range(.6, .95)
		var w := s * local.randf_range(.02, .05)
		Paint.line2(im, x0, y, x1, y + local.randf_range(-.06, .06) * s, deep, maxf(U, w))
		Paint.ellipse(
			im, x0 - w * 1.6, y - w * 1.6, x0 + w * 1.6, y + w * 1.6, wet if k % 2 else deep
		)
	var out := im.resized(size, size)
	for i in size * size:
		out.data[i * 4 + 3] = 255 if out.data[i * 4 + 3] >= 110 else 0
	return out


## A boot print: sole and heel, wet in the middle, lighter at the toe.
func boot_print(alien: bool) -> Paint.Sheet:
	var deep := SLIME_DARK if alien else Color8(96, 12, 12)
	var size := 24
	var s := float(size * U)
	var im := Paint.Sheet.new(size * U, size * U)
	Paint.ellipse(im, s * .3, s * .08, s * .7, s * .56, deep)
	Paint.ellipse(im, s * .34, s * .62, s * .66, s * .92, deep)
	for k in 4:
		var y := s * (.16 + k * .1)
		Paint.rect(im, s * .32, y, s * .68, y + U * 1.5, Color(0, 0, 0, 0))
	var out := im.resized(size, size)
	for i in size * size:
		out.data[i * 4 + 3] = 220 if out.data[i * 4 + 3] >= 110 else 0
	return out
