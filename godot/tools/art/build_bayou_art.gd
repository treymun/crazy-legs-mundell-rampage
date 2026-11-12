## Draw Gator Bayou's own tiles, sky, painted signs and water decals (chapter
## five): black water and boardwalks, tin and board shacks on stilts, the
## cannery's block, the juke joint's paint, the cypress wall round it all.
##
##   godot --headless --path godot --script res://tools/art/build_bayou_art.gd [-- out=<dir>]
##
## Tiles go in assets/tiles (listed in data/index.json and
## assets_gen/tiles_index.json, appended at the end so no other level's tile
## numbers move), the sky with them, the signs and decals in assets/art. A
## tile wraps both ways (its noise is periodic). Seeded with its own
## generator, so a rerun gives the same files and no other chapter's art moves.
## Then run tools/pack_assets.gd.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")
const S := 128

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 5050
	var art := Paint.repo("assets/art")
	var tiles := Paint.repo("assets/tiles")
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			art = String(arg).substr(4)
			tiles = art
	DirAccess.make_dir_recursive_absolute(art)
	DirAccess.make_dir_recursive_absolute(tiles)
	var made_tiles := {
		"bayou_water": water(),
		"bayou_deep": deep(),
		"bayou_planks": planks_floor(),
		"bayou_mud": mud(),
		"bayou_marsh": marsh(),
		"bayou_stilts": stilts(),
		"bayou_bank": bank(),
		"bayou_cypress": cypress_wall(),
		"bayou_tin": tin_wall(),
		"bayou_shack": shack_wall(),
		"bayou_cannery": cannery_wall(),
		"bayou_juke": juke_wall(),
		"bayou_pen": pen_wall(),
		"bayou_reeds": reeds_wall(),
		"bayou_bridge": bridge_leaf(),
		"bayou_juke_marquee": juke_marquee(),
		"bayou_bait_neon": bait_neon(),
	}
	for material: String in ["bayou_tin", "bayou_shack", "bayou_cannery"]:
		var base: Paint.Sheet = made_tiles[material]
		made_tiles[material + "_win"] = window(base, false, material)
		made_tiles[material + "_lit"] = window(base, true, material)
	for name: String in made_tiles:
		var sheet: Paint.Sheet = made_tiles[name]
		Paint.digitize(sheet).save(tiles.path_join(name + ".png"))
	sky().save(tiles.path_join("bayou_sky.png"))
	var made := {
		"bayou_landing_sign": sign_landing(),
		"bayou_bait_sign": sign_bait(),
		"bayou_boil_sign": sign_boil(),
		"bayou_cannery_sign": sign_cannery(),
		"bayou_ice_sign": sign_ice(),
		"bayou_gator_sign": sign_gator(),
		"bayou_pit_sign": sign_pit(),
		"bayou_juke_sign": sign_juke(),
		"bayou_mudhole_sign": sign_mudhole(),
		"bayou_airboat_sign": sign_airboat(),
		"bayou_nofeed_sign": sign_nofeed(),
		"bayou_noswim_sign": sign_noswim(),
		"bayou_keepout_sign": sign_keepout(),
		"bayou_bridge_sign": sign_bridge(),
		"bayou_cabins_sign": sign_cabins(),
		"bayou_king_sign": sign_king(),
		"bayou_menu_sign": sign_menu(),
		"bayou_tide_sign": sign_tide(),
		"bayou_arrow_farm": arrow("GATOR FARM", false),
		"bayou_arrow_juke": arrow("THE MUDHOLE", true),
		"bayou_arrow_dock": arrow("AIRBOAT DOCK", true),
		"bayou_arrow_boil": arrow("CRAWFISH BOIL", false),
		"bayou_arrow_cannery": arrow("CANNERY", true),
		"bayou_arrow_landing": arrow("LANDING", false),
		"bayou_lilies": lilies(),
		"bayou_duckweed": duckweed(),
		"bayou_shells": shells(),
		"bayou_slick": slick(),
	}
	for name: String in made:
		var sheet: Paint.Sheet = made[name]
		sheet.save(art.path_join(name + ".png"))
	print(
		(
			"bayou art: %d tiles and the sky to %s, %d signs and decals to %s"
			% [made_tiles.size(), tiles, made.size(), art]
		)
	)
	quit()


# ------------------------------------------------------------------- noise


## Value noise that wraps every S pixels, `cells` across, 0 to 1.
func wrap_noise(cells: int, seed: int, size := S) -> PackedFloat32Array:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var grid := PackedFloat32Array()
	grid.resize(cells * cells)
	for i in grid.size():
		grid[i] = r.randf()
	var out := PackedFloat32Array()
	out.resize(size * size)
	for y in size:
		var fy := float(y) * cells / size
		var y0 := int(fy)
		var ty := smoothstep(0.0, 1.0, fy - y0)
		for x in size:
			var fx := float(x) * cells / size
			var x0 := int(fx)
			var tx := smoothstep(0.0, 1.0, fx - x0)
			var a := grid[(y0 % cells) * cells + x0 % cells]
			var b := grid[(y0 % cells) * cells + (x0 + 1) % cells]
			var c := grid[((y0 + 1) % cells) * cells + x0 % cells]
			var d := grid[((y0 + 1) % cells) * cells + (x0 + 1) % cells]
			out[y * size + x] = lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)
	return out


## Several wrapping octaves summed, 0 to 1.
func fractal(seed: int, octaves := [4, 8, 16, 32]) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(S * S)
	var weight := 0.0
	for k in octaves.size():
		var layer := wrap_noise(int(octaves[k]), seed + k * 101)
		var gain := pow(.55, k)
		for i in S * S:
			out[i] += layer[i] * gain
		weight += gain
	for i in S * S:
		out[i] /= weight
	return out


func c3(v: Vector3) -> Color:
	return Paint.rgb(v.x, v.y, v.z)


func fill(s: Paint.Sheet, f: Callable) -> void:
	for y in s.h:
		for x in s.w:
			s.put(x, y, c3(f.call(x, y)))


func shade(s: Paint.Sheet, x: int, y: int, k: float) -> void:
	var xx := posmod(x, s.w)
	var yy := posmod(y, s.h)
	var o := (yy * s.w + xx) * 4
	for j in 3:
		s.data[o + j] = clampi(int(s.data[o + j] * k), 0, 255)


func dot(s: Paint.Sheet, x: int, y: int, c: Color) -> void:
	s.put(posmod(x, s.w), posmod(y, s.h), c)


# ---------------------------------------------------------------- the floors


## Shallow swamp water: tea-dark, the dusk lying on it in long streaks of
## orange and violet, a skin of duckweed here and there, a lily pad or two.
## The player wades it (a floor that sounds of water).
func water() -> Paint.Sheet:
	var s := Paint.Sheet.new(S, S)
	var murk := fractal(11)
	var weed := fractal(12, [8, 16, 32])
	var tint := fractal(13, [2, 4])
	fill(
		s,
		func(x: int, y: int) -> Vector3:
			var m := murk[y * S + x]
			var c := Vector3(22, 22, 20).lerp(Vector3(44, 38, 30), m)
			var fx := x / float(S) * TAU
			var fy := y / float(S) * TAU
			# The sky on the water: long soft streaks, warm or violet by patch.
			var streak := sin(fy * 6.0 + sin(fx * 2.0) * .9 + m * 2.5)
			if streak > .55:
				var sky := Vector3(84, 50, 82).lerp(Vector3(176, 96, 56), tint[y * S + x])
				c = c.lerp(sky, (streak - .55) * 1.1)
			var ripple := sin(fx * 3.0 + fy * 11.0 + sin(fy * 2.0) * 2.0)
			if ripple > .9:
				c += Vector3(30, 26, 26) * (ripple - .9) * 8.0
			if weed[y * S + x] > .7:
				c = c.lerp(Vector3(92, 104, 40), clampf((weed[y * S + x] - .7) * 7.0, 0.0, .85))
			return c
	)
	for _k in 90:
		var x := rng.randi_range(0, S - 1)
		var y := rng.randi_range(0, S - 1)
		if weed[y * S + x] > .64:
			dot(s, x, y, Color8(130, 150, 60))
	for p in [Vector3(30, 36, 7), Vector3(92, 84, 9), Vector3(18, 100, 6)]:
		lily(s, int(p.x), int(p.y), int(p.z), p.x > 60)
	return s


func lily(s: Paint.Sheet, cx: int, cy: int, r: int, flower: bool) -> void:
	var notch := rng.randf() * TAU
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			var d := Vector2(x, y).length()
			if d > r + .3:
				continue
			var a := atan2(y, x)
			if absf(angle_difference(a, notch)) < .3 and d > 1.0:
				continue
			var c := Vector3(58, 98, 42) * (1.0 - .25 * d / r)
			if d > r - 1.0:
				c *= .7
			if absf(angle_difference(a, notch + PI)) < .08 and d > 1.0:
				c *= .8
			dot(s, cx + x, cy + y, c3(c))
	if flower:
		for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
			dot(
				s,
				cx + d.x + 2,
				cy + d.y - 1,
				Color8(236, 214, 220) if d != Vector2i.ZERO else Color8(240, 200, 60)
			)


## A deep channel: black as a skillet, only the faintest dusk on it in thin
## long glints. Nobody wades this: the level's walkers keep to the boardwalks.
func deep() -> Paint.Sheet:
	var s := Paint.Sheet.new(S, S)
	var murk := fractal(21, [4, 8, 16])
	var tint := fractal(22, [2, 4])
	fill(
		s,
		func(x: int, y: int) -> Vector3:
			var m := murk[y * S + x]
			var c := Vector3(8, 9, 12).lerp(Vector3(16, 16, 20), m)
			var fx := x / float(S) * TAU
			var fy := y / float(S) * TAU
			var glint := sin(fy * 5.0 + sin(fx * 2.0 + fy) * 1.2)
			if glint > .8:
				var sky := Vector3(60, 34, 66).lerp(Vector3(120, 66, 40), tint[y * S + x])
				c = c.lerp(sky, (glint - .8) * 2.2)
			return c
	)
	for _k in 6:
		var x := rng.randi_range(4, S - 5)
		var y := rng.randi_range(4, S - 5)
		dot(s, x, y, Color8(54, 50, 58))
		dot(s, x + 1, y, Color8(40, 38, 44))
	return s


## The boardwalk: four grey planks across a tile, the black water in the gaps
## between them, nail heads at the joists, worn pale down the middle.
func planks_floor() -> Paint.Sheet:
	var s := Paint.Sheet.new(S, S)
	var grain := fractal(31, [8, 16, 32])
	var tones := [1.0, .9, 1.06, .94]
	var joints := [
		rng.randi_range(10, 50),
		rng.randi_range(60, 120),
		rng.randi_range(30, 90),
		rng.randi_range(0, 40)
	]
	fill(
		s,
		func(x: int, y: int) -> Vector3:
			var plank := y / 32
			var row := y % 32
			if row >= 30:
				return Vector3(14, 18, 14)
			var t: float = tones[plank]
			var g := grain[y * S + x]
			var streak := .5 + .5 * sin(y * 1.7 + g * 9.0 + sin(x / float(S) * TAU) * 1.5)
			var c := Vector3(128, 98, 66).lerp(Vector3(134, 122, 104), g) * t
			c *= .8 + .2 * streak
			if row < 2 or row > 27:
				c *= .7
			if absi(x - int(joints[plank])) < 1:
				c *= .4
			return c
	)
	for plank in 4:
		for jx in [
			int(joints[plank]) - 3, int(joints[plank]) + 3, posmod(int(joints[plank]) + 64, S)
		]:
			for ny in [7, 22]:
				dot(s, jx, plank * 32 + ny, Color8(60, 56, 50))
				dot(s, jx, plank * 32 + ny - 1, Color8(150, 146, 136))
	return s


## Bank mud: wet and dark, cypress needles rusting in it, a puddle catching sky.
func mud() -> Paint.Sheet:
	var s := Paint.Sheet.new(S, S)
	var m := fractal(41)
	var wet := fractal(42, [4, 8])
	fill(
		s,
		func(x: int, y: int) -> Vector3:
			var c := Vector3(46, 36, 26).lerp(Vector3(84, 66, 46), m[y * S + x])
			if wet[y * S + x] > .66:
				c = c.lerp(Vector3(70, 76, 70), (wet[y * S + x] - .66) * 2.5)
			return c
	)
	for k in 70:
		var x := rng.randi_range(0, S - 1)
		var y := rng.randi_range(0, S - 1)
		var a := rng.randf() * TAU
		for t in 4:
			dot(s, x + int(cos(a) * t), y + int(sin(a) * t), Color8(124, 74, 40))
	for k in 30:
		dot(s, rng.randi_range(0, S - 1), rng.randi_range(0, S - 1), Color8(30, 22, 16))
	return s


## Marsh on a hammock: sedge and dead grass over mud.
func marsh() -> Paint.Sheet:
	var s := Paint.Sheet.new(S, S)
	var m := fractal(51)
	fill(
		s,
		func(x: int, y: int) -> Vector3:
			return Vector3(48, 46, 28).lerp(Vector3(80, 84, 44), m[y * S + x])
	)
	for k in 420:
		var x := rng.randi_range(0, S - 1)
		var y := rng.randi_range(0, S - 1)
		var lean := rng.randf_range(-.6, .6)
		var dry := rng.randf() < .35
		var c := Color8(150, 132, 76) if dry else Color8(92, 116, 52)
		for t in rng.randi_range(3, 7):
			dot(s, x + int(lean * t), y - t, c.darkened(t * .04))
	return s


# ----------------------------------------------------------------- the walls


## Under a boardwalk or a stilt shack's deck: the deck's edge board along the
## top, then the dark under it with the pilings going down, slimed green at
## the waterline, the water at the foot.
func stilts() -> Paint.Sheet:
	var s := Paint.Sheet.new(S, S)
	var g := fractal(61, [8, 16, 32])
	fill(
		s,
		func(x: int, y: int) -> Vector3:
			var n := g[y * S + x]
			if y < 26:
				var c := Vector3(126, 112, 90) * (.85 + n * .3)
				if y < 3 or y > 22:
					c *= .7
				return c
			var c2 := Vector3(18, 20, 16) * (.8 + n * .4)
			for px in [24, 88]:
				var d := absf(x - px)
				if d < 8.0:
					var bulge := sqrt(1.0 - (d / 8.0) * (d / 8.0))
					c2 = Vector3(96, 82, 64) * (.45 + .55 * bulge) * (.8 + n * .4)
					if y > 92:
						c2 = c2.lerp(Vector3(60, 80, 44), .6)
			if y > 114:
				var r := sin(x / float(S) * TAU * 4.0 + y * .8)
				c2 = Vector3(20, 28, 22) + Vector3(18, 22, 18) * maxf(0.0, r)
			return c2
	)
	for x in range(4, S, 16):
		dot(s, x, 12, Color8(170, 164, 150))
	return s


## A mud bank's face where the ground is cut by the water: soil and roots.
func bank() -> Paint.Sheet:
	var s := Paint.Sheet.new(S, S)
	var g := fractal(71)
	fill(
		s,
		func(x: int, y: int) -> Vector3:
			var c := (
				Vector3(70, 54, 36).lerp(Vector3(44, 34, 24), float(y) / S)
				* (.8 + g[y * S + x] * .4)
			)
			if y < 12:
				c = Vector3(70, 84, 40) * (.8 + g[y * S + x] * .4)
			if y > 112:
				c = Vector3(24, 30, 22)
			return c
	)
	for k in 14:
		var x := rng.randi_range(0, S - 1)
		var length := rng.randi_range(20, 70)
		var wander := 0.0
		for t in length:
			wander += rng.randf_range(-.5, .5)
			dot(s, x + int(wander), 10 + t, Color8(110, 86, 60))
	return s


## The swamp's wall: cypress trunks close as a stockade, fog between the far
## ones, moss hung off the near, the crowns dark at the top, water at the foot.
func cypress_wall() -> Paint.Sheet:
	var s := Paint.Sheet.new(S, S)
	var fog := fractal(81, [4, 8])
	fill(
		s,
		func(x: int, y: int) -> Vector3:
			var c := Vector3(46, 56, 50).lerp(Vector3(70, 78, 66), fog[y * S + x])
			if y < 22:
				c = Vector3(28, 40, 24).lerp(Vector3(46, 60, 34), fog[y * S + x])
			if y > 116:
				c = Vector3(16, 22, 18)
			return c
	)
	for layer in 3:
		var tone: float = [.62, .8, 1.0][layer]
		var x := float(rng.randi_range(0, 20))
		while x < S:
			var w := rng.randf_range(5.0, 10.0) + layer * 2.0
			for y in range(14, 118):
				var flare := maxf(0.0, (y - 92) / 26.0) * w * .8
				var half := w * .5 + flare
				for dx in range(-int(half), int(half) + 1):
					var bulge := 1.0 - absf(dx) / maxf(half, 1.0)
					var groove := .85 + .15 * sin((x + dx) * 1.7 + y * .05)
					var c := Vector3(92, 80, 64) * tone * (.5 + .5 * bulge) * groove
					dot(s, int(x) + dx, y, c3(c))
			# moss beards off the near trunks
			if layer > 0:
				for k in 3:
					var mx := int(x) + rng.randi_range(-6, 6)
					var my := rng.randi_range(18, 50)
					for t in rng.randi_range(10, 30):
						dot(
							s,
							mx + int(sin(t * .4) * 1.5),
							my + t,
							Color8(150, 156, 126).darkened(t * .01)
						)
			x += rng.randf_range(14.0, 26.0)
	for k in 90:
		var x := rng.randi_range(0, S - 1)
		var y := rng.randi_range(0, 24)
		dot(s, x, y, Color8(60, 80, 40))
	return s


## Rusted corrugated tin: ridges, a red paint that has mostly given up, the
## galvanised showing, rust running down from the nails.
func tin_wall() -> Paint.Sheet:
	var s := Paint.Sheet.new(S, S)
	var g := fractal(91)
	var rust := fractal(92, [4, 8, 16])
	fill(
		s,
		func(x: int, y: int) -> Vector3:
			var ridge := .78 + .22 * sin(x / 8.0 * TAU)
			var paint := Vector3(132, 58, 40)
			var bare := Vector3(138, 138, 130)
			var r := rust[y * S + x]
			var c := paint.lerp(bare, clampf(g[y * S + x] * 1.6 - .5, 0.0, 1.0))
			c = c.lerp(Vector3(118, 62, 32), clampf(r * 1.8 - .7, 0.0, 1.0))
			if (y > 60 and y < 66) or y < 4 or y > 123:
				c *= .7
			return c * ridge
	)
	for x in range(4, S, 16):
		for y in [6, 68, 120]:
			dot(s, x, y, Color8(40, 30, 24))
			for t in rng.randi_range(4, 16):
				shade(s, x, y + 1 + t, .86)
	return s


## Board and batten gone grey: wide boards, battens over the joints, mildew low.
func shack_wall() -> Paint.Sheet:
	var s := Paint.Sheet.new(S, S)
	var g := fractal(101, [8, 16, 32])
	fill(
		s,
		func(x: int, y: int) -> Vector3:
			var n := g[y * S + x]
			var c := Vector3(98, 84, 66) * (.78 + n * .4)
			c *= .86 + .14 * sin(x * 1.3 + n * 11.0 + y * .02)
			var b := x % 32
			if b < 6:
				c = c * 1.12
				if b == 0 or b == 5:
					c *= .55
			if y > 96:
				c = c.lerp(Vector3(62, 76, 46), (y - 96) / 40.0)
			return c
	)
	for x in range(2, S, 32):
		for y in [10, 64, 118]:
			dot(s, x + 1, y, Color8(46, 40, 34))
	return s


## The cannery's block: painted the green of a hospital, peeling, rust run
## from the gutters, and the flood line a yard up, dark under it.
func cannery_wall() -> Paint.Sheet:
	var s := Paint.Sheet.new(S, S)
	var g := fractal(111)
	var peel := fractal(112, [8, 16])
	fill(
		s,
		func(x: int, y: int) -> Vector3:
			var course := y / 16
			var bx := (x + (8 if course % 2 else 0)) % 32
			var c := Vector3(168, 180, 158) * (.86 + g[y * S + x] * .24)
			if peel[y * S + x] > .64:
				c = Vector3(126, 124, 116) * (.9 + g[y * S + x] * .2)
			if y % 16 == 0 or bx == 0:
				c *= .62
			if y > 92:
				c *= .62
				c = c.lerp(Vector3(52, 60, 40), .35)
			elif y > 89:
				c *= .5
			return c
	)
	for k in 8:
		var x := rng.randi_range(0, S - 1)
		for t in rng.randi_range(20, 80):
			dot(s, x, t, c3(Vector3(120, 70, 40)))
	return s


## The juke joint's boards: lap siding painted whatever was left over, red,
## yellow, a turquoise, a purple door's worth, flaking back to wood.
func juke_wall() -> Paint.Sheet:
	var s := Paint.Sheet.new(S, S)
	var g := fractal(121, [8, 16, 32])
	var paints := [
		Vector3(130, 46, 38),
		Vector3(162, 136, 58),
		Vector3(58, 110, 106),
		Vector3(96, 62, 108),
		Vector3(116, 100, 80),
		Vector3(162, 136, 58),
		Vector3(130, 46, 38),
		Vector3(116, 100, 80)
	]
	fill(
		s,
		func(x: int, y: int) -> Vector3:
			var board := y / 16
			var row := y % 16
			var c: Vector3 = paints[(board + (1 if x >= 64 else 0) * 3) % paints.size()]
			var n := g[y * S + x]
			if n > .68:
				c = Vector3(110, 92, 72)
			c *= .84 + n * .3
			if row < 2:
				c *= .5
			elif row < 4:
				c *= 1.1
			return c
	)
	return s


## A gator pen: a low block wall with chain link stood on it.
func pen_wall() -> Paint.Sheet:
	var s := Paint.Sheet.new(S, S)
	var g := fractal(131)
	fill(
		s,
		func(x: int, y: int) -> Vector3:
			var n := g[y * S + x]
			if y >= 72:
				var c := Vector3(130, 128, 118) * (.85 + n * .25)
				if (y - 72) % 18 == 0 or ((x + (16 if ((y - 72) / 18) % 2 else 0)) % 32) == 0:
					c *= .6
				if y > 110:
					c = c.lerp(Vector3(56, 64, 40), .4)
				return c
			var back := Vector3(40, 46, 38) * (.8 + n * .4)
			var u := posmod(x + y, 12)
			var v := posmod(x - y, 12)
			if u == 0 or v == 0:
				back = Vector3(150, 152, 148)
			if x % 64 < 3:
				back = Vector3(120, 122, 118)
			if y < 4:
				back = Vector3(140, 142, 138)
			return back
	)
	return s


## Reeds and cattails: a stand too thick to see through, brown heads on top.
func reeds_wall() -> Paint.Sheet:
	var s := Paint.Sheet.new(S, S, Color8(30, 40, 26))
	var g := fractal(141, [4, 8])
	fill(
		s,
		func(x: int, y: int) -> Vector3:
			return Vector3(26, 36, 22).lerp(Vector3(46, 58, 34), g[y * S + x])
	)
	for layer in 3:
		var tone: float = [.6, .8, 1.0][layer]
		for k in 40:
			var x := rng.randi_range(0, S - 1)
			var top := rng.randi_range(4, 40)
			var lean := rng.randf_range(-.08, .08)
			var c := Color(.38, .52, .24) * tone
			c.a = 1.0
			for y in range(top, S):
				dot(s, x + int(lean * (S - y)), y, c)
			if rng.randf() < .4:
				for t in 8:
					dot(s, x + int(lean * (S - top)), top + t, Color8(110, 70, 40))
					dot(s, x + 1 + int(lean * (S - top)), top + t, Color8(90, 56, 32))
	return s


## A bridge leaf stood up: the planks' underside and the beams, striped red
## and white at the edge, BRIDGE UP painted across.
func bridge_leaf() -> Paint.Sheet:
	var s := planks(S, S, Color(.42, .36, .28), 16)
	for y in S:
		for x in S:
			if x < 10 or x > S - 11:
				var stripe := ((x + y) / 10) % 2 == 0
				s.put(x, y, Color8(200, 40, 30) if stripe else Color8(236, 232, 220))
	Paint.rect(s, 10, 56, S - 11, 74, Color8(30, 26, 22))
	letters(s, "BRIDGE UP", 64, 59, 1, Color8(240, 210, 80), false)
	weather(s, 120, 4)
	return s


## The juke joint's blade sign, JUKE down a wall's height in bulbs (a wall
## tile is stretched three times as tall as it is wide, so the letters are
## drawn squat). Its bright texels glow and it buzzes (effects.cfg).
func juke_marquee() -> Paint.Sheet:
	var s := Paint.Sheet.new(S, S, Color8(30, 22, 20))
	Paint.rect(s, 14, 2, S - 15, S - 3, Color8(120, 30, 26))
	Paint.rect(s, 18, 5, S - 19, S - 6, Color8(40, 24, 20))
	for k in 4:
		letters(s, "JUKE"[k], 64, 9 + k * 30, 14, Color8(255, 226, 140), true, true, 3)
	for y in range(4, S - 4, 6):
		for x in [15, S - 16]:
			s.put(x, y, Color8(255, 230, 160) if rng.randf() < .85 else Color8(90, 70, 50))
	return s


## LIVE BAIT in a window: a neon tube that buzzes over a dark pane.
func bait_neon() -> Paint.Sheet:
	var s := shack_wall()
	Paint.rect(s, 16, 26, 111, 96, Color8(60, 48, 36))
	Paint.rect(s, 20, 30, 107, 92, Color8(18, 22, 26))
	letters(s, "LIVE", 64, 38, 3, Color8(255, 120, 150), false, true, 2)
	letters(s, "BAIT", 64, 64, 3, Color8(120, 240, 255), false, true, 2)
	return s


## A shack's window: a screen over dark (or lit, a beer sign hung in it).
func window(base: Paint.Sheet, lit: bool, material: String) -> Paint.Sheet:
	var tile := base.duplicate_sheet()
	var frame_c := Color8(70, 60, 48) if material != "bayou_cannery" else Color8(110, 112, 104)
	var x0 := 30
	var y0 := 32
	var x1 := 97
	var y1 := 84
	Paint.rect(tile, x0 - 3, y0 - 3, x1 + 3, y1 + 3, Color8(30, 26, 22))
	Paint.rect(tile, x0, y0, x1, y1, frame_c)
	for yy in range(y0 + 4, y1 - 3):
		for xx in range(x0 + 4, x1 - 3):
			var c := Vector3(24, 30, 32) + Vector3(10, 12, 14) * float(yy - y0) / (y1 - y0)
			if lit:
				var d := Vector2((xx - 64) / 34.0, (yy - 58) / 26.0).length()
				c = Vector3(236, 178, 92) * (1.0 - .4 * d)
			# window screen: a fine grid over it
			if (xx + yy) % 3 == 0:
				c *= .82
			tile.put(xx, yy, c3(c))
	if lit:
		letters(tile, "COLD", 64, 44, 1, Color8(255, 90, 80), false)
		letters(tile, "BEER", 64, 56, 1, Color8(110, 230, 255), false)
	if material == "bayou_cannery":
		for xx in range(x0 + 4, x1 - 3, 8):
			Paint.rect(tile, xx, y0 + 4, xx, y1 - 4, frame_c)
	Paint.rect(tile, (x0 + x1) / 2 - 1, y0, (x0 + x1) / 2 + 1, y1, frame_c)
	return tile


# ------------------------------------------------------------------- the sky


## Dusk over the swamp, 512 x 116 and wrapping: violet overhead going to a
## bruised orange where the sun went down, the cypress line black against it,
## moss hung off it, a few birds going home.
func sky() -> Paint.Sheet:
	var w := 512
	var h := 116
	var s := Paint.Sheet.new(w, h)
	var cloud := wrap_noise(16, 151, 512)
	for y in h:
		for x in w:
			var t := float(y) / h
			var c := Vector3(26, 20, 44).lerp(Vector3(88, 46, 72), smoothstep(.1, .55, t))
			c = c.lerp(Vector3(196, 108, 56), smoothstep(.45, .8, t))
			var sun := exp(-pow(fposmod(x - 330.0 + 256.0, 512.0) - 256.0, 2.0) / 9000.0)
			c += Vector3(60, 34, 10) * sun * smoothstep(.4, .85, t)
			var n := cloud[(y * 512 / h) * 512 + x]
			if t < .7:
				c = c.lerp(Vector3(48, 30, 52), clampf(n * 1.5 - .7, 0.0, .7))
			s.put(x, y, c3(c))
	# the tree line: crowns flat and ragged, wrapping at the seam
	for x in w:
		var fx := x / float(w) * TAU
		var top := (
			80.0 + 6.0 * sin(fx * 3.0) + 4.0 * sin(fx * 11.0 + 1.0) + 3.0 * sin(fx * 23.0 + 2.0)
		)
		var spike := sin(fx * 37.0) * sin(fx * 7.0)
		if spike > .7:
			top -= (spike - .7) * 40.0
		for y in range(int(top), h):
			s.put(x, y, Color8(14, 16, 20))
	for k in 46:
		var x := rng.randi_range(0, w - 1)
		var y := rng.randi_range(82, 96)
		for t in rng.randi_range(5, 14):
			s.put(posmod(x + int(sin(t * .5)), w), mini(h - 1, y + t), Color8(40, 44, 44))
	for k in 7:
		var bx := rng.randi_range(0, w - 8)
		var by := rng.randi_range(30, 60)
		s.put(bx, by, Color8(20, 16, 24))
		s.put(bx + 1, by - 1, Color8(20, 16, 24))
		s.put(bx + 2, by, Color8(20, 16, 24))
		s.put(bx + 3, by - 1, Color8(20, 16, 24))
		s.put(bx + 4, by, Color8(20, 16, 24))
	return Paint.digitize(s)


# --------------------------------------------------------------- surfaces


func planks(width: int, height: int, base: Color, plank := 6) -> Paint.Sheet:
	var s := Paint.Sheet.new(width, height)
	var grain := Paint.noise(rng.randi(), width * height, .06)
	for y in height:
		var row := y / plank
		var tone := 1.0 + sin(row * 2.3) * .06
		var seam := y % plank == 0
		for x in width:
			var f := tone + grain[y * width + x] + sin(x * .21 + row * 1.7) * .03
			f *= 1.0 + (1.0 - float(y) / height) * .08
			if seam:
				f *= .55
			s.put(x, y, Color(base.r * f, base.g * f, base.b * f))
	return s


func tin(width: int, height: int, base: Color) -> Paint.Sheet:
	var s := Paint.Sheet.new(width, height)
	var blot := Paint.cloud(64, rng.randi())
	var grit := Paint.noise(rng.randi(), width * height, .05)
	for y in height:
		for x in width:
			var edge := minf(minf(x, width - 1 - x), minf(y, height - 1 - y)) / 5.0
			var b := blot[(y * 64 / height) * 64 + (x * 64 / width)]
			var rust := clampf(b * 1.3 - clampf(edge, 0, 1) * .8 - .1, 0, 1)
			var c := base.lerp(Color(.52, .26, .12), rust)
			var f := 1.0 + grit[y * width + x] + (sin(x * 1.4) * .04)
			s.put(x, y, Color(c.r * f, c.g * f, c.b * f))
	return s


## Block letters, `scale` times their size (`tall` times as high when set),
## with a drop shadow; centred on x when `centre`. Returns the width drawn.
func letters(
	s: Paint.Sheet,
	text: String,
	x: int,
	y: int,
	scale: int,
	ink: Color,
	shadow := true,
	centre := true,
	tall := 0
) -> int:
	var sy := tall if tall > 0 else scale
	var width := 0
	for c in text:
		width += (int(PixelType.glyph(c, false)[1]) + 1) * scale
	width -= scale
	var left := x - width / 2 if centre else x
	for pass_k in [1, 0] if shadow else [0]:
		var off: int = pass_k * maxi(1, scale / 2)
		var colour := Color(.08, .05, .04, .85) if pass_k == 1 else ink
		var at := left
		for c in text:
			var g: Array = PixelType.glyph(c, false)
			var rows: Array = g[0]
			var gw: int = g[1]
			for r in rows.size():
				for bx in gw:
					if int(rows[r]) & (1 << (gw - 1 - bx)):
						for yy in sy:
							for xx in scale:
								_blend(s, at + bx * scale + xx + off, y + r * sy + yy + off, colour)
			at += (gw + 1) * scale
	return width


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
		for k in 3:
			s.data[o + k] = int(s.data[o + k] * .72)
	for _k in holes:
		var x := rng.randi_range(3, s.w - 4)
		var y := rng.randi_range(3, s.h - 4)
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


## Teeth marks bitten out of a corner: the swamp's own comment on a sign.
func bitten(s: Paint.Sheet, right: bool) -> void:
	var cx := s.w - 1 if right else 0
	for k in 5:
		var r := 4 + (k % 2) * 2
		var cy := 3 + k * 5
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				if Vector2(x, y).length() <= r and cy + y >= 0 and cy + y < s.h:
					var px := cx + x
					if px >= 0 and px < s.w:
						var o := ((cy + y) * s.w + px) * 4
						s.data[o + 3] = 0


# --------------------------------------------------------------------- signs


func sign_landing() -> Paint.Sheet:
	var s := tin(120, 40, Color(.24, .44, .3))
	Paint.outline(s, 2, 2, 117, 37, Color8(232, 236, 224))
	letters(s, "COUNTY LINE", 60, 5, 1, Color8(240, 242, 236), false)
	letters(s, "LANDING", 60, 14, 2, Color8(240, 242, 236))
	letters(s, "BOAT RAMP - NO WAKE", 60, 30, 1, Color8(250, 214, 110), false)
	weather(s, 60, 6)
	return Paint.digitize(s)


func sign_bait() -> Paint.Sheet:
	var s := planks(150, 36, Color(.52, .4, .26), 9)
	letters(s, "BAIT & TACKLE", 75, 4, 2, Color8(240, 230, 200))
	letters(s, "SHINERS CRICKETS ICE AMMO", 75, 24, 1, Color8(250, 210, 100), false)
	frame(s, Color8(40, 28, 20))
	nails(s)
	weather(s, 100, 3)
	return Paint.digitize(s)


func sign_boil() -> Paint.Sheet:
	var s := planks(130, 50, Color(.78, .74, .64), 11)
	letters(s, "CRAWFISH", 65, 4, 2, Color8(180, 40, 28))
	letters(s, "BOIL", 65, 20, 2, Color8(180, 40, 28))
	letters(s, "ALL U CAN EAT 5 BUCKS", 65, 39, 1, Color8(40, 30, 26), false)
	frame(s, Color8(70, 54, 40))
	nails(s)
	weather(s, 60, 2)
	return Paint.digitize(s)


func sign_cannery() -> Paint.Sheet:
	var s := tin(160, 40, Color(.86, .84, .76))
	Paint.rect(s, 3, 3, 156, 21, Color8(34, 70, 110))
	letters(s, "SWAMP KING", 80, 5, 2, Color8(250, 236, 196))
	letters(s, "CANNING CO. - EST. WHENEVER", 80, 27, 1, Color8(34, 70, 110), false)
	frame(s, Color8(46, 40, 34))
	weather(s, 90, 5)
	return Paint.digitize(s)


func sign_ice() -> Paint.Sheet:
	var s := tin(56, 30, Color(.84, .88, .92))
	letters(s, "ICE", 28, 4, 3, Color8(30, 90, 170))
	frame(s, Color8(40, 50, 60))
	weather(s, 40, 3)
	return Paint.digitize(s)


func sign_gator() -> Paint.Sheet:
	var s := planks(200, 44, Color(.3, .44, .22), 11)
	letters(s, "GATOR FARM", 100, 4, 3, Color8(250, 226, 90))
	letters(s, "SEE EM WRASSLED SAT. NITE", 100, 32, 1, Color8(240, 236, 220), false)
	frame(s, Color8(30, 40, 20))
	nails(s)
	weather(s, 90, 4)
	bitten(s, true)
	return Paint.digitize(s)


func sign_pit() -> Paint.Sheet:
	var s := planks(110, 36, Color(.66, .58, .44), 9)
	letters(s, "WRASSLIN PIT", 55, 4, 1, Color8(150, 30, 24), false)
	letters(s, "LOSERS FEED", 55, 15, 1, Color8(40, 30, 26), false)
	letters(s, "THE GATORS", 55, 25, 1, Color8(40, 30, 26), false)
	frame(s, Color8(60, 48, 40))
	nails(s)
	weather(s, 50, 6)
	return Paint.digitize(s)


func sign_juke() -> Paint.Sheet:
	var s := planks(130, 40, Color(.2, .16, .14), 10)
	letters(s, "LIVE MUSIC", 65, 5, 2, Color8(250, 200, 80))
	letters(s, "COLD BEER - NO FIGHTIN", 65, 26, 1, Color8(240, 120, 110), false)
	for x in range(4, 126, 6):
		for y in [1, 38]:
			s.put(x, y, Color8(255, 226, 150) if rng.randf() < .8 else Color8(90, 70, 50))
	weather(s, 50, 2)
	return Paint.digitize(s)


func sign_mudhole() -> Paint.Sheet:
	var s := planks(170, 46, Color(.18, .13, .12), 11)
	letters(s, "THE", 85, 4, 1, Color8(240, 200, 90), false)
	letters(s, "MUDHOLE", 85, 14, 3, Color8(255, 232, 150))
	for x in range(3, 168, 6):
		for y in [1, 44]:
			s.put(x, y, Color8(255, 226, 150) if rng.randf() < .85 else Color8(90, 70, 50))
	for y in range(5, 42, 6):
		for x in [1, 168]:
			s.put(x, y, Color8(255, 226, 150) if rng.randf() < .85 else Color8(90, 70, 50))
	weather(s, 40, 2)
	return Paint.digitize(s)


func sign_airboat() -> Paint.Sheet:
	var s := tin(170, 40, Color(.86, .7, .2))
	letters(s, "AIRBOAT TOURS", 85, 5, 2, Color8(40, 30, 20))
	letters(s, "NO REFUNDS IF ET", 85, 27, 1, Color8(150, 30, 24), false)
	frame(s, Color8(60, 44, 20))
	weather(s, 80, 7)
	return Paint.digitize(s)


func sign_nofeed() -> Paint.Sheet:
	var s := planks(100, 36, Color(.84, .82, .74), 9)
	letters(s, "DONT FEED", 50, 4, 1, Color8(40, 30, 26), false)
	letters(s, "THE GATORS", 50, 14, 1, Color8(40, 30, 26), false)
	letters(s, "THEYRE FED", 50, 25, 1, Color8(170, 30, 24), false)
	frame(s, Color8(60, 48, 40))
	nails(s)
	weather(s, 50, 2)
	return Paint.digitize(s)


func sign_noswim() -> Paint.Sheet:
	var s := tin(80, 30, Color(.88, .86, .8))
	letters(s, "NO", 40, 3, 2, Color8(180, 30, 24))
	letters(s, "SWIMMIN", 40, 19, 1, Color8(40, 30, 26), false)
	frame(s, Color8(60, 48, 40))
	weather(s, 40, 3)
	bitten(s, false)
	return Paint.digitize(s)


func sign_keepout() -> Paint.Sheet:
	var s := planks(110, 34, Color(.4, .34, .26), 9)
	letters(s, "KEEP OUT", 55, 4, 2, Color8(220, 40, 30))
	letters(s, "TRESPASSERS = CHUM", 55, 23, 1, Color8(236, 226, 196), false)
	frame(s, Color8(30, 22, 16))
	nails(s)
	weather(s, 80, 8)
	return Paint.digitize(s)


func sign_bridge() -> Paint.Sheet:
	var s := tin(100, 36, Color(.9, .78, .2))
	letters(s, "SWING BRIDGE", 50, 4, 1, Color8(30, 24, 18), false)
	letters(s, "HONK TWICE", 50, 15, 1, Color8(30, 24, 18), false)
	letters(s, "THEN WAIT", 50, 25, 1, Color8(160, 30, 24), false)
	frame(s, Color8(50, 40, 20))
	weather(s, 60, 4)
	return Paint.digitize(s)


func sign_cabins() -> Paint.Sheet:
	var s := planks(130, 36, Color(.36, .5, .58), 9)
	letters(s, "CABINS", 65, 4, 2, Color8(246, 230, 180))
	letters(s, "9 A NITE - BUG SPRAY", 65, 24, 1, Color8(240, 236, 220), false)
	frame(s, Color8(30, 40, 46))
	nails(s)
	weather(s, 50, 3)
	return Paint.digitize(s)


func sign_king() -> Paint.Sheet:
	var s := planks(120, 46, Color(.22, .18, .3), 11)
	# a crown painted over it, gold gone brown
	var crown := PackedVector2Array(
		[
			Vector2(46, 18),
			Vector2(46, 6),
			Vector2(53, 12),
			Vector2(60, 3),
			Vector2(67, 12),
			Vector2(74, 6),
			Vector2(74, 18)
		]
	)
	Paint.polygon(s, crown, Color8(206, 170, 60))
	letters(s, "PROPERTY OF THE", 60, 22, 1, Color8(236, 226, 196), false)
	letters(s, "SWAMP KING", 60, 32, 2, Color8(240, 200, 70))
	frame(s, Color8(30, 22, 30))
	nails(s)
	weather(s, 70, 4)
	return Paint.digitize(s)


func sign_menu() -> Paint.Sheet:
	var s := planks(80, 60, Color(.2, .22, .18), 10)
	letters(s, "TONITE", 40, 4, 1, Color8(250, 210, 90), false)
	for k in 4:
		var line: String = ["BOILED BUGS", "FRIED GATOR", "FROG LEGS", "SHINE 2 BITS"][k]
		letters(s, line, 40, 16 + k * 10, 1, Color8(236, 232, 220), false)
	frame(s, Color8(60, 48, 40))
	nails(s)
	weather(s, 40, 1)
	return Paint.digitize(s)


func sign_tide() -> Paint.Sheet:
	var s := tin(70, 52, Color(.84, .84, .8))
	letters(s, "HIGH WATER", 35, 3, 1, Color8(40, 30, 26), false)
	for k in 4:
		var y := 14 + k * 9
		Paint.rect(s, 6, y + 3, 24, y + 4, Color8(40, 30, 26))
		letters(s, str(1927 + k * 22), 46, y, 1, Color8(30, 70, 140), false)
	frame(s, Color8(60, 48, 40))
	weather(s, 40, 2)
	return Paint.digitize(s)


## A plank sawn to a point, a name painted on it, nailed up to show the way.
func arrow(text: String, right: bool) -> Paint.Sheet:
	var width := 18 + PixelType.text_width(text) + 14
	var s := planks(width, 18, Color(.56, .44, .3), 6)
	for y in 18:
		var cut := absi(y - 9)
		for x in cut:
			var px := width - 1 - x if right else x
			var o := (y * width + px) * 4
			s.data[o + 3] = 0
	letters(s, text, width / 2 + (-3 if right else 3), 5, 1, Color8(244, 236, 214), false)
	weather(s, width / 2, 1)
	return Paint.digitize(s)


# --------------------------------------------------------------------- decals


## Lily pads floating, seen from above.
func lilies() -> Paint.Sheet:
	var s := Paint.Sheet.new(48, 48)
	for p in [
		Vector3(14, 16, 8),
		Vector3(32, 12, 6),
		Vector3(26, 32, 9),
		Vector3(40, 36, 5),
		Vector3(10, 36, 5)
	]:
		lily(s, int(p.x), int(p.y), int(p.z), p.y > 30 and p.x < 30)
	return Paint.digitize(s)


## Duckweed scum, ragged at the edges.
func duckweed() -> Paint.Sheet:
	var s := Paint.Sheet.new(64, 64)
	var n := Paint.cloud(64, 161)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 32, y - 32).length() / 32.0
			var v := n[y * 64 + x] - d * .6
			if v > .2:
				s.put(x, y, Color8(int(70 + v * 60), int(100 + v * 60), 40))
	return Paint.digitize(s)


## Boiled crawfish shells and corn cobs dumped by a table.
func shells() -> Paint.Sheet:
	var s := Paint.Sheet.new(48, 48)
	for k in 70:
		var a := rng.randf() * TAU
		var r := sqrt(rng.randf()) * 20.0
		var x := 24 + int(cos(a) * r)
		var y := 24 + int(sin(a) * r)
		var c := Color8(200, 60, 36) if rng.randf() < .8 else Color8(220, 196, 90)
		s.put(x, y, c)
		s.put(x + 1, y, c.darkened(.2))
	return Paint.digitize(s)


## Outboard oil on the water by the dock: a sheen of colour.
func slick() -> Paint.Sheet:
	var s := Paint.Sheet.new(64, 64)
	var n := Paint.cloud(64, 171)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 32, y - 32).length() / 32.0
			var v := n[y * 64 + x] - d * .7
			if v > .12:
				var hue := fposmod(v * 3.0 + x * .02, 1.0)
				var c := Color.from_hsv(hue, .5, .45)
				c.a = .7
				s.put(x, y, c)
	return Paint.digitize(s)
