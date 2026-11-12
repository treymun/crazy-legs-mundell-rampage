## Paint the graphics-card view's gun and blast effects into assets/art: hard
## edged, few-colour pictures committed to the VGA palette, the way a 1997
## shooter drew its fire (build_fx_art.gd keeps the soft older set, which the
## software view still draws).
##
##   godot --headless --path godot --script res://tools/art/build_gun_fx_art.gd [-- out=<dir>]
##
##   fx_mf_<style>_<v>_<f>   muzzle flashes: style pistol, shotgun, rifle, forge,
##                           rocket, energy, steam; two of each (v), three frames
##   fx_boom_N (8)           a blast: the flash, the fireball rolling up, soot
##                           taking it over
##   fx_boomflash_N (2)      the white star of the moment it goes
##   fx_soot_N (4)           chunky black smoke for a blast's column and trails
##   fx_chunk_N (4)          a charred scrap tumbling (four turns)
##   mark_shock_N (3)        the dust ring a blast throws along the ground
##   fx_hit_<kind>_N (3)     a round striking: metal, brick, stone, wood, dirt,
##                           glass, water, brush
## Then run tools/pack_assets.gd. out= writes somewhere else instead (to compare).
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")
const FIRE := [
	Color8(70, 20, 10),
	Color8(132, 36, 12),
	Color8(196, 70, 18),
	Color8(236, 124, 30),
	Color8(252, 188, 64),
	Color8(255, 236, 152),
	Color8(255, 255, 236),
]
## A blast's fire: yellower than a flash, so a dusk tint leaves it orange.
const BOOM := [
	Color8(84, 24, 8),
	Color8(156, 48, 10),
	Color8(218, 98, 18),
	Color8(246, 156, 36),
	Color8(252, 208, 84),
	Color8(255, 242, 164),
	Color8(255, 255, 236),
]
const FORGE := [
	Color8(110, 22, 10),
	Color8(176, 48, 14),
	Color8(226, 96, 24),
	Color8(250, 160, 52),
	Color8(255, 222, 128),
	Color8(255, 250, 220),
]
const GREEN := [
	Color8(16, 70, 26),
	Color8(40, 140, 56),
	Color8(104, 220, 104),
	Color8(196, 255, 176),
	Color8(246, 255, 236),
]
const STEAM := [
	Color8(118, 128, 134),
	Color8(156, 166, 172),
	Color8(196, 204, 208),
	Color8(232, 238, 240),
	Color8(255, 255, 255),
]
const SOOT := [
	Color8(26, 22, 20),
	Color8(42, 36, 32),
	Color8(62, 54, 46),
	Color8(86, 76, 64),
	Color8(112, 100, 84),
]
## style -> [rays, ray length, ray width, core, bloom, sparks, side vents, ramp]
const STYLES := {
	"pistol": [6, .95, .10, .30, 0.0, 6, false, FIRE],
	"shotgun": [11, 1.0, .15, .36, .62, 16, false, FIRE],
	"rifle": [4, .8, .09, .24, 0.0, 5, true, FIRE],
	"forge": [3, .55, .12, .32, .3, 24, false, FORGE],
	"rocket": [5, .9, .2, .3, .78, 10, false, FIRE],
	"energy": [5, .9, .07, .22, 0.0, 8, false, GREEN],
	"steam": [0, .0, .0, .3, .8, 10, false, STEAM],
}
## kind -> [dust colour, chip colour, glows]
const HITS := {
	"metal": [Color8(255, 210, 120), Color8(255, 250, 220), true],
	"brick": [Color8(226, 156, 116), Color8(150, 60, 40), false],
	"stone": [Color8(206, 202, 190), Color8(120, 116, 108), false],
	"wood": [Color8(206, 172, 120), Color8(236, 204, 140), false],
	"dirt": [Color8(150, 116, 78), Color8(84, 60, 38), false],
	"glass": [Color8(210, 236, 248), Color8(255, 255, 255), true],
	"water": [Color8(176, 206, 214), Color8(240, 250, 252), false],
	"brush": [Color8(150, 170, 72), Color8(222, 200, 100), false],
}

var out := ""
var count := 0


func _init() -> void:
	out = Paint.repo("assets/art")
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	for style: String in STYLES:
		for v in 2:
			for f in 3:
				_save(muzzle(style, v, f), "fx_mf_%s_%d_%d" % [style, v, f])
	for f in 8:
		_save(boom(f), "fx_boom_%d" % f)
	for f in 2:
		_save(boom_flash(f), "fx_boomflash_%d" % f)
	for f in 4:
		_save(soot(f), "fx_soot_%d" % f)
		_save(chunk(f), "fx_chunk_%d" % f)
	for f in 3:
		_save(shock(f), "mark_shock_%d" % f)
	for kind: String in HITS:
		for f in 3:
			_save(hit(kind, f), "fx_hit_%s_%d" % [kind, f])
	print("gun fx art: %d pictures in %s" % [count, out])
	quit()


func _save(s: Paint.Sheet, name: String) -> void:
	Paint.digitize(s, 7.0).save(out.path_join(name + ".png"))
	count += 1


func _step(ramp: Array, v: float) -> Color:
	return ramp[clampi(int(v * ramp.size()), 0, ramp.size() - 1)]


func _gap(a: float, b: float) -> float:
	return fposmod(a - b + PI, TAU) - PI


## A dark rim one pixel round everything drawn: the cartoon edge of a sprite
## of the period. Only where `only_hot` pixels border nothing, when given.
func _rim(s: Paint.Sheet, c: Color) -> void:
	var edge: Array = []
	for y in s.h:
		for x in s.w:
			if s.alpha_at(x, y) != 0:
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := x + d.x
				var ny := y + d.y
				if nx >= 0 and ny >= 0 and nx < s.w and ny < s.h and s.alpha_at(nx, ny) == 255:
					edge.append(Vector2i(x, y))
					break
	for p: Vector2i in edge:
		s.put(p.x, p.y, c)


## A muzzle flash seen from behind the gun: a hot core, flame tongues, sparks
## of burning powder; frame 2 is the ember going out in a curl of smoke.
func muzzle(style: String, variant: int, frame: int) -> Paint.Sheet:
	var n := 48
	var spec: Array = STYLES[style]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(style) + variant * 101
	var reach: float = [1.0, .74, .42][frame]
	var gain: float = [1.2, .95, .62][frame]
	var ramp: Array = spec[7]
	if ramp == FIRE:
		# A flash has no dark edge: it starts at orange.
		ramp = FIRE.slice(2)
	var rays: Array = []
	for k in int(spec[0]):
		var at := rng.randf_range(-PI, PI)
		if style == "pistol" and k < 4:
			at = k * PI / 2.0 + rng.randf_range(-.3, .3) + variant * .4
		elif style == "rifle":
			at = k * PI / 2.0 + variant * .12
		rays.append(
			[
				at,
				rng.randf_range(.55, 1.0) * float(spec[1]),
				float(spec[2]) * rng.randf_range(.7, 1.3)
			]
		)
	if bool(spec[6]):
		# The muzzle brake's side vents: flat fans out to left and right.
		rays.append([0.0, 1.0, .3])
		rays.append([PI, 1.0, .3])
	var churn := Paint.cloud(n, hash(style) + variant * 7 + frame * 3, [4, 8, 16])
	var s := Paint.Sheet.new(n, n)
	var c := (n - 1) / 2.0
	for y in n:
		for x in n:
			var dx := (x - c) / (n / 2.0)
			var dy := (y - c) / (n / 2.0)
			var r := sqrt(dx * dx + dy * dy)
			var a := atan2(dy, dx)
			var heat := exp(-pow(r / (float(spec[3]) * reach), 2)) * 1.1
			for ray: Array in rays:
				var length: float = float(ray[1]) * reach
				var across := _gap(a, ray[0]) / float(ray[2])
				heat += exp(-across * across) * clampf(1.0 - r / maxf(.05, length), 0.0, 1.0) * .95
			var bloom := float(spec[4]) * reach
			if bloom > 0.0:
				var lobe := 1.0 + .2 * sin(a * 5.0 + variant * 2.0) + .1 * sin(a * 9.0 + frame)
				heat += clampf(1.0 - r / (bloom * lobe), 0.0, 1.0) * .85
			if style == "energy":
				var ring := (r - .42 * reach) / .07
				heat += exp(-ring * ring) * .9
			heat *= gain * (.78 + .44 * churn[y * n + x])
			var i := y * n + x
			if heat > .2:
				s.put(x, y, _step(ramp, (heat - .2) / 1.0))
			elif frame == 2 and style != "energy" and r < .55:
				# The flash going out: a curl of smoke round the ember.
				var puff := churn[i] - r * .9
				if puff > .12:
					var tone := SOOT if style != "steam" else STEAM
					s.put(x, y, _step(tone, churn[(i * 7) % (n * n)] * .8 + .1))
	# Burning powder thrown out: hard bright specks along the tongues.
	for k in int(spec[5]) * (3 - frame) / 3:
		var at := rng.randf_range(-PI, PI)
		if not rays.is_empty() and k % 2 == 0:
			at = float(rays[k % rays.size()][0]) + rng.randf_range(-.2, .2)
		var d := rng.randf_range(.35, .95) * (.5 + reach * .5)
		var px := int(c + cos(at) * d * n / 2.0)
		var py := int(c + sin(at) * d * n / 2.0)
		var hot: Color = ramp[ramp.size() - 2 if k % 3 else ramp.size() - 1]
		s.put(px, py, hot)
		if frame == 0 and k % 2 == 0:
			s.put(px + 1, py, hot)
	return s


## A blast's fireball, frame 0 to 7: the white flash, the ball rolling up and
## out in lobes, cooling from the top, soot taking it over from the edge.
func boom(frame: int) -> Paint.Sheet:
	var n := 64
	var t := frame / 7.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 4400 + frame
	var churn := Paint.cloud(n, 911 + frame * 13, [4, 8, 16])
	var fine := Paint.cloud(n, 1301 + frame * 7, [8, 16, 32])
	var radius := .4 + .52 * sqrt(t)
	var rise := t * .26
	var smoke_k := clampf((t - .28) * 1.45, 0.0, 1.0)
	var s := Paint.Sheet.new(n, n)
	var c := (n - 1) / 2.0
	for y in n:
		for x in n:
			var i := y * n + x
			var dx := (x - c) / (n / 2.0)
			var dy := (y - c) / (n / 2.0) + rise
			var r := sqrt(dx * dx + dy * dy)
			var a := atan2(dy, dx)
			var lobes := (
				1.0
				+ .17 * sin(a * 5.0 + 1.3 + t * 1.5)
				+ .09 * sin(a * 8.0 + 2.1 - t * 2.0)
				+ .05 * sin(a * 13.0)
			)
			var edge := radius * lobes * (.84 + .3 * churn[i])
			if frame == 0:
				# The instant it goes: a star of white fire.
				var star := 0.0
				for k in 9:
					var at := k * TAU / 9.0 + .3
					star = maxf(star, exp(-pow(_gap(a, at) / .13, 2)) * (.95 if k % 2 else .7))
				edge = maxf(edge, star)
			if r > edge:
				continue
			var inner := 1.0 - r / edge
			var heat := inner * 1.35 * (1.0 - t * .78) + (fine[i] - .5) * .4 + .25 * (1.0 - t)
			# The top cools first as the ball rolls up.
			heat -= maxf(0.0, -dy) * t * .45
			var soot := smoke_k * (.55 + churn[i] * .9) - inner * (1.0 - smoke_k) * .5
			if soot > heat * 1.3:
				var shade := .45 + (-dx - dy) * .22 + fine[i] * .45 - smoke_k * .15
				s.put(x, y, _step(SOOT, shade))
			else:
				s.put(x, y, _step(BOOM, heat))
	if frame >= 1 and frame <= 4:
		_rim(s, BOOM[0])
	# Burning bits flung clear of the ball.
	if frame >= 1 and frame <= 6:
		for k in 14 - frame:
			var at := rng.randf_range(-PI, PI)
			var d := radius * rng.randf_range(1.0, 1.35)
			var px := int(c + cos(at) * d * n / 2.0)
			var py := int(c + (sin(at) * d - rise) * n / 2.0)
			s.put(px, py, BOOM[5 if k % 3 == 0 else 4])
			s.put(px, py + 1, BOOM[2])
	return s


func boom_flash(frame: int) -> Paint.Sheet:
	var n := 48
	var s := Paint.Sheet.new(n, n)
	var c := (n - 1) / 2.0
	var reach := 1.0 if frame == 0 else .7
	for y in n:
		for x in n:
			var dx := (x - c) / (n / 2.0)
			var dy := (y - c) / (n / 2.0)
			var r := sqrt(dx * dx + dy * dy)
			var a := atan2(dy, dx)
			var heat := exp(-pow(r / (.34 * reach), 2)) * 1.3
			for k in 12:
				var at := k * TAU / 12.0 + frame * .26
				var length := (1.0 if k % 2 == 0 else .62) * reach
				heat += exp(-pow(_gap(a, at) / .08, 2)) * clampf(1.0 - r / length, 0.0, 1.0)
			if heat > .25:
				s.put(x, y, _step(FIRE, .35 + heat * .6))
	return s


## A lump of black blast smoke, aging 0 to 3: swelling, lumpier, thinning.
func soot(frame: int) -> Paint.Sheet:
	var n := 32
	var rng := RandomNumberGenerator.new()
	rng.seed = 77 + frame
	var blobs: Array = []
	for k in 6:
		var at := rng.randf_range(-PI, PI)
		var d := rng.randf_range(.0, .38) * (1.0 + frame * .12)
		blobs.append([cos(at) * d, sin(at) * d, rng.randf_range(.3, .5) * (1.0 + frame * .1)])
	var grain := Paint.cloud(n, 31 + frame * 5, [4, 8, 16])
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
					lit = -ex - ey
			var i := y * n + x
			if inside <= 0.0:
				continue
			# Older smoke breaks up: holes open in its edge.
			if grain[i] < frame * .12 * (1.0 - inside):
				continue
			var shade := .32 + lit * .16 + grain[i] * .35 + frame * .06
			var col := _step(SOOT, shade)
			col.a = (.94 if inside > .25 else .7) * (1.0 - frame * .12)
			s.put(x, y, col)
	return s


## A charred scrap of plank, turned `frame` eighths of a turn, its end aglow.
func chunk(frame: int) -> Paint.Sheet:
	var n := 12
	var s := Paint.Sheet.new(n, n)
	var a := frame * PI / 4.0
	var ax := Vector2(cos(a), sin(a))
	var ay := Vector2(-sin(a), cos(a))
	for y in n:
		for x in n:
			var p := Vector2(x - 5.5, y - 5.5)
			var u := p.dot(ax)
			var v := p.dot(ay)
			if absf(u) > 4.6 or absf(v) > 1.5:
				continue
			var col := Color8(104, 70, 40) if v < 0.0 else Color8(70, 46, 28)
			if u > 2.6:
				col = Color8(30, 24, 20)
			if u > 3.6 and absf(v) < .8:
				col = Color8(250, 150, 50)
			s.put(x, y, col)
	return s


## The dust ring a blast throws out along the ground, spreading and thinning.
func shock(frame: int) -> Paint.Sheet:
	var n := 64
	var grain := Paint.cloud(n, 501 + frame, [4, 8, 16])
	var s := Paint.Sheet.new(n, n)
	var c := (n - 1) / 2.0
	var outer := .55 + .2 * frame
	var width := .22 + .06 * frame
	for y in n:
		for x in n:
			var r := Vector2(x - c, y - c).length() / (n / 2.0)
			var into := (outer - r) / width
			if into < 0.0 or into > 1.0:
				continue
			var i := y * n + x
			var body := (1.0 - absf(into - .35) * 1.5) * (.6 + grain[i] * .8) - frame * .14
			if body < .25:
				continue
			var col := _step(SOOT, 2.0 + grain[i] * 2.4 - into)
			col = col.lerp(Color8(132, 112, 86), .45)
			col.a = clampf(body, 0.0, 1.0) * .8
			s.put(x, y, col)
	return s


## A round striking `kind`, frames 0 to 2.
func hit(kind: String, frame: int) -> Paint.Sheet:
	var n := 24
	var h := 36 if kind == "water" else 24
	var spec: Array = HITS[kind]
	var dust: Color = spec[0]
	var chip: Color = spec[1]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var s := Paint.Sheet.new(n, h)
	var c := Vector2((n - 1) / 2.0, h - n / 2.0)
	var grain := Paint.cloud(n, hash(kind) % 1000 + frame, [4, 8])
	match kind:
		"metal", "glass":
			# A star of sparks (a glint for glass), the heads flying out.
			for k in 11 if kind == "metal" else 6:
				var at := rng.randf_range(-PI, PI)
				var length := rng.randf_range(.5, 1.0) * n * .5
				var head: float = length * float([.45, .8, 1.0][frame])
				var tail: float = head - length * float([.45, .5, .3][frame])
				for d in range(int(maxf(0.0, tail)), int(head) + 1):
					var p: Vector2 = c + Vector2(cos(at), sin(at)) * d
					var col := chip if d > head - 2 else dust
					if kind == "metal" and d < head - 4:
						col = FIRE[3]
					s.put(int(p.x), int(p.y), col)
			if frame < 2:
				var core := 3 - frame * 2
				for y in range(-core, core + 1):
					for x in range(-core, core + 1):
						if absi(x) + absi(y) <= core:
							s.put(int(c.x) + x, int(c.y) + y, chip)
		"water":
			# A crown of water thrown up, falling back as drops.
			var tall: float = float([.5, 1.0, .8][frame]) * h * .8
			for k in 9:
				var x0 := c.x + (k - 4) * 2.2
				var top: float = tall * (1.0 - absf(k - 4) / 6.0) * rng.randf_range(.7, 1.0)
				for d in int(top):
					if frame == 2 and d < top * .5:
						continue
					var col := chip if d > top - 3 else dust
					s.put(int(x0), int(c.y + 4 - d), col)
				if frame >= 1:
					s.put(int(x0 + rng.randf_range(-2, 2)), int(c.y - top - 2), chip)
		_:
			# A puff of dust off the face, jets of it thrown out, chips flying.
			var radius: float = float([.26, .42, .55][frame]) * n * .5
			var jets: Array = []
			for k in 7:
				var at := rng.randf_range(-PI, PI)
				if kind == "dirt":
					at = rng.randf_range(-PI * .95, -PI * .05)
				jets.append([at, rng.randf_range(.6, 1.0)])
			for y in h:
				for x in n:
					var off := Vector2(x, y) - c
					var d := off.length()
					var a := off.angle()
					var g := grain[(y % n) * n + x]
					var reach := radius * (.75 + g * .5)
					for jet: Array in jets:
						var across := absf(_gap(a, jet[0]))
						if across < .28:
							var length: float = (
								n * .5 * float([.55, .85, 1.0][frame]) * float(jet[1])
							)
							reach = maxf(reach, length * (1.0 - across / .28))
					if d > reach or g < frame * .2 + (d / maxf(reach, 1.0)) * .25:
						continue
					var shade := clampf(1.0 - d / maxf(reach, 1.0) + g * .5, 0.0, 1.0)
					var col := (
						dust.lightened(.22)
						if shade > .8
						else dust if shade > .35 else dust.darkened(.25)
					)
					if kind == "brush" and g > .55:
						col = chip
					s.put(x, y, col)
			for k in 10:
				var jet: Array = jets[k % jets.size()]
				var at: float = float(jet[0]) + rng.randf_range(-.35, .35)
				var d: float = n * .5 * float([.5, .8, 1.0][frame]) * rng.randf_range(.6, 1.0)
				var p: Vector2 = c + Vector2(cos(at), sin(at)) * d
				s.put(int(p.x), int(p.y), chip)
				if kind == "wood" or k % 3 == 0:
					var q: Vector2 = p - Vector2(cos(at), sin(at)) * 1.5
					s.put(int(q.x), int(q.y), chip)
	return s
