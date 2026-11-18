## The blast pictures of build_gun_fx_art.gd (destruction pass 11): hard
## edged, few colours, a dark rim, committed to the VGA palette there.
##
##   fx_boom_<r><v>_<f>   a fireball, 12 frames: ramp d (dynamite, powder,
##                        propane: yellow-white) or f (fuel: deep orange going
##                        to oily black), three shapes v (their own lobes)
##   fx_soothot_N (3)     a lump of the column's soot lit orange from under
##   fx_powder_N (4)      a keg's black-powder smoke: thick, grey-white
##   fx_dirtpuff_N (4)    the dirt a blast throws out along the ground
##   fx_scrap_<k>_N (4)   flung scraps, four turns: metal (a torn sheet), meat
##   fx_geyser_N (5)      the water a blast in water throws up
##   mark_crater_N (4)    the crater a blast leaves on the ground: a burnt pit,
##                        a churned rim, soot streaks thrown out radially
extends RefCounted

const Paint := preload("res://tools/art/paint.gd")

const BOOM := [
	Color8(84, 24, 8),
	Color8(156, 48, 10),
	Color8(218, 98, 18),
	Color8(246, 156, 36),
	Color8(252, 208, 84),
	Color8(255, 242, 164),
	Color8(255, 255, 236),
]
## Fuel burning: redder and darker, the soot blacker and sooner.
const FUEL := [
	Color8(64, 14, 6),
	Color8(124, 30, 8),
	Color8(184, 58, 12),
	Color8(228, 98, 20),
	Color8(246, 150, 40),
	Color8(252, 202, 92),
	Color8(255, 238, 168),
]
const SOOT := [
	Color8(22, 18, 16),
	Color8(38, 32, 28),
	Color8(56, 48, 42),
	Color8(80, 70, 60),
	Color8(108, 96, 80),
]
const POWDER := [
	Color8(96, 94, 90),
	Color8(126, 124, 118),
	Color8(156, 154, 146),
	Color8(186, 182, 172),
	Color8(214, 210, 198),
]
const DIRT := [
	Color8(58, 44, 32),
	Color8(84, 64, 46),
	Color8(112, 88, 62),
	Color8(140, 112, 80),
	Color8(166, 138, 100),
]
## Fireball shapes: [lobes, seed, lean (x per rise)].
const SHAPES := [[5, 31, .0], [6, 57, .12], [7, 83, -.1]]


static func step(ramp: Array, v: float) -> Color:
	return ramp[clampi(int(v * ramp.size()), 0, ramp.size() - 1)]


static func gap(a: float, b: float) -> float:
	return fposmod(a - b + PI, TAU) - PI


## A dark rim one pixel round everything drawn.
static func rim(s: Paint.Sheet, c: Color) -> void:
	var edge: Array = []
	for y in s.h:
		for x in s.w:
			if s.alpha_at(x, y) != 0:
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := x + d.x
				var ny := y + d.y
				if nx >= 0 and ny >= 0 and nx < s.w and ny < s.h and s.alpha_at(nx, ny) > 200:
					edge.append(Vector2i(x, y))
					break
	for p: Vector2i in edge:
		s.put(p.x, p.y, c)


## A fireball, frame 0 to 11, of shape `v` in `ramp` ("d" or "f"). Lobes of
## fire bulge out of a hot core and roll up; the top cools first, soot eats
## in from the edge and the top, and at the end it is a lump of soot with a
## few pockets of fire still in it, breaking up.
static func boom(ramp_name: String, v: int, frame: int) -> Paint.Sheet:
	var n := 64
	var fuel := ramp_name == "f"
	var ramp: Array = FUEL if fuel else BOOM
	var t := frame / 11.0
	var shape: Array = SHAPES[v]
	var count: int = shape[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(shape[1]) * 13 + (7 if fuel else 0)
	var lean: float = shape[2]
	var churn := Paint.cloud(n, 911 + frame * 13 + v * 101, [4, 8, 16])
	var fine := Paint.cloud(n, 1301 + frame * 7 + v * 57, [8, 16, 32])
	var grow := .3 + .58 * sqrt(t)
	var rise := t * (.3 if fuel else .24)
	# Soot takes over from here on (fuel sooner).
	var smoke_k := clampf((t - (.26 if fuel else .36)) * (1.7 if fuel else 1.55), 0.0, 1.0)
	var lobes: Array = []
	for k in count:
		var at := k * TAU / count + rng.randf_range(-.35, .35)
		var far := rng.randf_range(.35, .62)
		# Lobes that go up rise faster than those that go out to the side.
		var up := -sin(at)
		(
			lobes
			. append(
				[
					cos(at) * far + lean * t,
					sin(at) * far * .8 - rise * (1.0 + maxf(0.0, up) * .6),
					rng.randf_range(.42, .62),
					rng.randf_range(0.0, TAU),
				]
			)
		)
	var s := Paint.Sheet.new(n, n)
	var c := (n - 1) / 2.0
	for y in n:
		for x in n:
			var i := y * n + x
			var dx := (x - c) / (n / 2.0)
			var dy := (y - c) / (n / 2.0)
			# The core and each lobe: how far inside the nearest, 0 at its edge.
			var core_r := grow * (.62 + .18 * churn[i])
			var cy := -rise * .8
			var inside := 1.0 - Vector2(dx - lean * t * .5, dy - cy).length() / core_r
			var lit := 0.0
			for lobe: Array in lobes:
				var lx: float = lobe[0]
				var ly: float = lobe[1]
				var lr: float = lobe[2]
				var wobble := (
					.8
					+ .26 * churn[(i + int(lobe[3] * 97.0)) % (n * n)]
					+ .14 * fine[(i * 3 + int(lobe[3] * 31.0)) % (n * n)]
				)
				var r := lr * grow * wobble
				var d := Vector2(dx - lx * grow, dy - ly * grow).length()
				var into := 1.0 - d / r
				if into > inside:
					inside = into
					lit = -(dx - lx * grow) - (dy - ly * grow)
			if frame == 0:
				# The instant it goes: a star of white fire round a hot core.
				var star := 0.0
				var a := atan2(dy, dx)
				var rays := 7 + v * 2
				for k in rays:
					var ray := k * TAU / rays + v * .4
					var length := (.95 if k % 2 else .7) - Vector2(dx, dy).length()
					star = maxf(star, exp(-pow(gap(a, ray) / .12, 2)) * length - .12)
				inside = maxf(inside, star * 1.6)
			if inside <= 0.0:
				continue
			var heat := inside * 1.3 * (1.0 - t * .7) + (fine[i] - .5) * .5 + .3 * (1.0 - t)
			heat += lit * .06 * (1.0 - t)
			# The top cools first as it rolls up.
			heat -= maxf(0.0, -dy - cy) * t * .5
			if fuel:
				heat -= .06
			var soot := smoke_k * (.5 + churn[i] * .95) - inside * (1.0 - smoke_k) * .6
			# Late on, pockets of fire still glow through the smoke.
			var pocket := fine[i] > .74 - t * .06 and inside > .35 and t < .95
			if soot > heat * 1.25 and not (pocket and smoke_k < .95):
				# Holes open in old smoke.
				if t > .8 and churn[(i * 3) % (n * n)] < (t - .8) * 1.6 * (1.0 - inside):
					continue
				var shade := .42 + lit * .2 + fine[i] * .42 - smoke_k * .2
				shade += -.12 if fuel else .1
				s.put(x, y, step(SOOT, shade))
			else:
				s.put(x, y, step(ramp, heat))
	if frame >= 1 and frame <= 7:
		rim(s, ramp[0])
	elif frame >= 8:
		rim(s, SOOT[0])
	# Burning bits flung clear of the ball.
	if frame >= 1 and frame <= 8:
		for k in 16 - frame:
			var at := rng.randf_range(-PI, PI)
			var d := grow * rng.randf_range(1.05, 1.5)
			var px := int(c + cos(at) * d * n / 2.0)
			var py := int(c + (sin(at) * d - rise) * n / 2.0)
			s.put(px, py, ramp[5 if k % 3 == 0 else 4])
			s.put(px, py + 1, ramp[2])
	return s


## A lump of soot from blobs: `tones` its ramp, `frame` 0..3 its age (bigger,
## lumpier, thinning), `under` how much of its underside is lit by fire.
static func lump(
	n: int, seed: int, frame: int, tones: Array, under: float, alpha: float
) -> Paint.Sheet:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + frame
	var blobs: Array = []
	for k in 7:
		var at := rng.randf_range(-PI, PI)
		var d := rng.randf_range(.0, .36) * (1.0 + frame * .12)
		blobs.append(
			[cos(at) * d, sin(at) * d * .8, rng.randf_range(.3, .48) * (1.0 + frame * .08)]
		)
	var grain := Paint.cloud(n, seed * 3 + frame * 5, [4, 8, 16])
	var s := Paint.Sheet.new(n, n)
	var c := (n - 1) / 2.0
	for y in n:
		for x in n:
			var dx := (x - c) / (n / 2.0)
			var dy := (y - c) / (n / 2.0)
			var inside := 0.0
			var lit := 0.0
			for b: Array in blobs:
				var ex := (dx - float(b[0])) / float(b[2])
				var ey := (dy - float(b[1])) / float(b[2])
				var v := 1.0 - (ex * ex + ey * ey)
				if v > inside:
					inside = v
					lit = -ex * .6 - ey
			var i := y * n + x
			if inside <= 0.0:
				continue
			if grain[i] < frame * .12 * (1.0 - inside):
				continue
			var shade := .3 + lit * .18 + grain[i] * .38 + frame * .05
			var col := step(tones, shade)
			if under > 0.0 and dy > .1 and grain[i] + dy * .6 > 1.0 - under:
				col = step(BOOM, .15 + (dy * .5 + grain[i] * .4) * under)
			col.a = (1.0 if inside > .22 else .78) * alpha * (1.0 - maxf(0.0, frame - 1.0) * .12)
			s.put(x, y, col)
	return s


static func soot_hot(frame: int) -> Paint.Sheet:
	return lump(32, 211, frame, SOOT, .7 - frame * .22, .96)


static func powder(frame: int) -> Paint.Sheet:
	var s := lump(40, 377, frame, POWDER, 0.0, .94)
	rim(s, POWDER[0])
	return s


static func dirt_puff(frame: int) -> Paint.Sheet:
	var s := lump(32, 433, frame, DIRT, 0.0, 1.0)
	if frame < 2:
		rim(s, DIRT[0])
	return s


## A scrap tumbling, turned `frame` eighths: a torn sheet of tin, or meat.
static func scrap(kind: String, frame: int) -> Paint.Sheet:
	var n := 12
	var s := Paint.Sheet.new(n, n)
	var a := frame * PI / 4.0
	var ax := Vector2(cos(a), sin(a))
	var ay := Vector2(-sin(a), cos(a))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var notch := rng.randf_range(-1.5, 1.5)
	for y in n:
		for x in n:
			var p := Vector2(x - 5.5, y - 5.5)
			var u := p.dot(ax)
			var v := p.dot(ay)
			if kind == "metal":
				# A jagged, bent sheet: a tooth torn out of one edge.
				if absf(u) > 5.0 or absf(v) > 3.4 - absf(u - notch) * .3:
					continue
				var col := Color8(150, 146, 136) if v < -.5 else Color8(96, 92, 86)
				if u > 3.2:
					col = Color8(40, 36, 34)
				if v < -1.6 and absf(u) < 1.5:
					col = Color8(214, 210, 196)
				s.put(x, y, col)
			else:
				if p.length() > 3.8 + sin(atan2(v, u) * 3.0) * .9:
					continue
				var col := Color8(150, 36, 30) if v < 0.0 else Color8(104, 22, 20)
				if absf(u - 1.0) < .8 and v < 0.0:
					col = Color8(226, 196, 170)
				s.put(x, y, col)
	return s


## The water a blast in water throws up: a ragged column whose crown breaks
## into spray and falls back, foam at its foot.
static func geyser(frame: int) -> Paint.Sheet:
	var w := 32
	var h := 64
	var s := Paint.Sheet.new(w, h)
	var grain := Paint.cloud(64, 707 + frame, [4, 8, 16])
	var fine := Paint.cloud(64, 811 + frame, [8, 16, 32])
	var tall: float = [.45, .85, 1.0, .9, .6][frame] * h
	var spread: float = [.4, .55, .7, .85, 1.0][frame]
	var tones := [
		Color8(70, 96, 108), Color8(118, 146, 156), Color8(168, 194, 202), Color8(226, 238, 240)
	]
	for y in h:
		var up := float(h - 1 - y)
		if up > tall:
			continue
		var k := up / maxf(1.0, tall)
		var half := (3.0 + k * k * 10.0) * spread + 2.0 + (1.0 - k) * 3.0 * spread
		for x in w:
			var dx := x - (w - 1) / 2.0
			var g := grain[(y % 64) * 64 + x]
			var f := fine[(y % 64) * 64 + x]
			if absf(dx) > half * (.7 + g * .6):
				continue
			# The crown breaks up into spray; a falling column thins from below.
			if k > .78 and f < (k - .78) * 3.2:
				continue
			if frame >= 3 and k < .55 and g < (frame - 2) * .32:
				continue
			var shade := .25 + (1.0 - absf(dx) / half) * .3 + f * .35 + k * .15 - dx / half * .12
			s.put(x, y, step(tones, shade))
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + frame
	for _k in 8 + frame * 4:
		var x := rng.randi_range(1, w - 2)
		var y := int(h - tall + rng.randf_range(-6, tall * .6 * spread))
		s.put(x, y, tones[3])
		s.put(x, y + 1, tones[1])
	rim(s, Color8(48, 66, 76))
	return s


## A blast's crater: a burnt pit, a churned rim of thrown dirt, soot streaks
## thrown out radially, flecks; variant `k`.
static func crater(k: int) -> Paint.Sheet:
	var n := 64
	var s := Paint.Sheet.new(n, n)
	var c := (n - 1) / 2.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150 + k * 31
	var grain := Paint.cloud(n, 3301 + k * 17, [4, 8, 16])
	var rays: Array = []
	for r in 10 + k * 2:
		rays.append(
			[rng.randf_range(-PI, PI), rng.randf_range(.55, 1.0), rng.randf_range(.07, .16)]
		)
	var lumps := [rng.randf_range(0, TAU), rng.randf_range(.06, .12), 2 + k % 3]
	for y in n:
		for x in n:
			var i := y * n + x
			var dx := (x - c) / (n / 2.0)
			var dy := (y - c) / (n / 2.0)
			var r := sqrt(dx * dx + dy * dy)
			var a := atan2(dy, dx)
			var ragged := 1.0 + float(lumps[1]) * sin(a * float(lumps[2]) + float(lumps[0]))
			ragged += (grain[i] - .5) * .18
			var pit := .3 * ragged
			var rim_r := .46 * ragged
			var col := Color(0, 0, 0, 0)
			if r < pit:
				# Burnt black in the middle, a little lighter toward its wall.
				var tone := 14.0 + r / pit * 18.0 + grain[i] * 10.0
				col = Color8(int(tone), int(tone * .86), int(tone * .74), 255)
			elif r < rim_r:
				# The churned rim: dirt thrown up, dark clods in it.
				var g := grain[(i * 7) % (n * n)]
				var lip := 1.0 - absf((r - pit) / (rim_r - pit) - .4) * 1.6
				var tone_i := clampi(int(lip * 1.6 + g * 1.8), 0, 3)
				col = DIRT[tone_i] if g > .42 else SOOT[1 + int(g * 4.0) % 2]
				col.a = .9
			else:
				# Soot streaks thrown out from the pit.
				for ray: Array in rays:
					var length: float = ray[1]
					var width: float = float(ray[2]) * (1.0 - (r - rim_r) / maxf(.05, length))
					if r > length or width <= 0.0:
						continue
					if absf(gap(a, ray[0])) * r < width * .5:
						var fade := 1.0 - (r - rim_r) / maxf(.05, length - rim_r)
						col = SOOT[0] if grain[i] > .4 else SOOT[1]
						col.a = .45 + .4 * fade
						break
				if col.a == 0.0 and r < .62 and grain[i] > .58:
					col = SOOT[1]
					col.a = .55
			if col.a > 0.0:
				s.put(x, y, col)
	# Clods and flecks thrown out past the streaks.
	for _k in 26:
		var at := rng.randf_range(-PI, PI)
		var d := rng.randf_range(.5, .98) * n / 2.0
		var px := int(c + cos(at) * d)
		var py := int(c + sin(at) * d)
		var col: Color = DIRT[rng.randi_range(0, 2)] if rng.randf() < .6 else SOOT[0]
		s.put(px, py, col)
		if rng.randf() < .4:
			s.put(px + 1, py, col)
	return s
