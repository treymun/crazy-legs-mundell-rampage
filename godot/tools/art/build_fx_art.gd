## Paint the muzzle flashes, smoke, blasts and impact puffs into assets/art.
##
##   godot --headless --path godot --script res://tools/art/build_fx_art.gd [-- out=<dir>]
##
## Four frames each unless noted:
##   fx_fire_N     a spiked muzzle flash dying to an ember; also a blast's fireball
##   fx_smoke_N    rolling smoke
##   fx_energy_N   the alien arm gun's discharge
##   fx_rocket_N, fx_forge_N, fx_steam_N   the same shapes in each weapon's colours
##   fx_blast_N, fx_blast_energy_N   the swelling fireball of an explosion
##   fx_puff_N     dust kicked off a wall or the ground by a bullet
##   fx_sparks_N   (three frames) a bullet striking metal
##   fx_arm_bolt   a small copy of fx_energy_1
## Then run tools/pack_assets.gd. out= writes somewhere else instead (to compare).
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")
const SIZE := 80
const FIRE := [
	[0.0, Vector3(70, 20, 8)],
	[.25, Vector3(176, 58, 16)],
	[.5, Vector3(238, 132, 34)],
	[.75, Vector3(255, 214, 96)],
	[1.0, Vector3(255, 252, 226)]
]
const PLASMA := [
	[0.0, Vector3(10, 50, 18)],
	[.3, Vector3(40, 150, 60)],
	[.6, Vector3(120, 240, 120)],
	[.85, Vector3(210, 255, 190)],
	[1.0, Vector3(250, 255, 240)]
]


func _init() -> void:
	var out := Paint.repo("assets/art")
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	var count := 0
	for frame in 4:
		var fire := flash(frame, FIRE, 3)
		fire.save(out.path_join("fx_fire_%d.png" % frame))
		smoke(frame, Vector3.ONE, 21).save(out.path_join("fx_smoke_%d.png" % frame))
		flash(frame, PLASMA, 8).save(out.path_join("fx_energy_%d.png" % frame))
		tinted(fire, Vector3(1.0, .78, .6), 0.0).save(out.path_join("fx_rocket_%d.png" % frame))
		tinted(flash(frame, FIRE, 14), Vector3(1.0, .96, .78), 0.0).save(
			out.path_join("fx_forge_%d.png" % frame)
		)
		tinted(smoke(frame, Vector3.ONE, 33), Vector3(.86, .96, 1.1), 22.0).save(
			out.path_join("fx_steam_%d.png" % frame)
		)
		puff(frame).save(out.path_join("fx_puff_%d.png" % frame))
		fireball(frame, FIRE, 41).save(out.path_join("fx_blast_%d.png" % frame))
		fireball(frame, PLASMA, 47).save(out.path_join("fx_blast_energy_%d.png" % frame))
		count += 9
	for frame in 3:
		sparks(frame).save(out.path_join("fx_sparks_%d.png" % frame))
		count += 1
	for frame in 4:
		spray(frame).save(out.path_join("fx_spray_%d.png" % frame))
		count += 1
	var bolt := Paint.Sheet.load_png(out.path_join("fx_energy_1.png")).resized(24, 24)
	bolt.save(out.path_join("fx_arm_bolt.png"))
	print("fx art: %d frames in %s" % [count, out])
	quit()


## Distance from the middle (1 at the edge) and the angle, for each pixel.
func polar(size: int) -> Array:
	var r := PackedFloat32Array()
	var a := PackedFloat32Array()
	r.resize(size * size)
	a.resize(size * size)
	var c := (size - 1) / 2.0
	for y in size:
		for x in size:
			r[y * size + x] = Vector2(x - c, y - c).length() / (size / 2.0)
			a[y * size + x] = atan2(y - c, x - c)
	return [r, a]


func ramp(heat: float, stops: Array) -> Vector3:
	var out := Vector3.ZERO
	for k in stops.size() - 1:
		var a0: float = stops[k][0]
		var a1: float = stops[k + 1][0]
		if heat >= a0:
			var t := clampf((heat - a0) / maxf(1e-6, a1 - a0), 0.0, 1.0)
			out = (stops[k][1] as Vector3).lerp(stops[k + 1][1], t)
	return out


func sheet_of(size: int, colours: PackedVector3Array, alphas: PackedFloat32Array) -> Paint.Sheet:
	var s := Paint.Sheet.new(size, size)
	for i in size * size:
		var c := colours[i]
		s.data[i * 4] = clampi(int(c.x), 0, 255)
		s.data[i * 4 + 1] = clampi(int(c.y), 0, 255)
		s.data[i * 4 + 2] = clampi(int(c.z), 0, 255)
		s.data[i * 4 + 3] = clampi(int(alphas[i]), 0, 255)
	return s


func angle_gap(a: float, b: float) -> float:
	return fposmod(a - b + PI, TAU) - PI


func flash(frame: int, stops: Array, seed: int) -> Paint.Sheet:
	var p := polar(SIZE)
	var r: PackedFloat32Array = p[0]
	var a: PackedFloat32Array = p[1]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + frame * 7
	var reach: float = [1.0, .78, .5, .3][frame]
	var spikes: int = [9, 7, 4, 0][frame]
	var heat := PackedFloat32Array()
	heat.resize(SIZE * SIZE)
	for i in heat.size():
		heat[i] = exp(-pow(r[i] / (.30 * reach), 2)) * 1.25
	for _k in spikes:
		var at := rng.randf_range(-PI, PI)
		var width := rng.randf_range(.05, .13)
		var length := rng.randf_range(.45, 1.0) * reach
		var gain := rng.randf_range(.7, 1.1)
		for i in heat.size():
			heat[i] += (
				exp(-pow(angle_gap(a[i], at) / width, 2)) * exp(-r[i] / (length * .42)) * gain
			)
	var churn := Paint.cloud(SIZE, seed * 5 + frame, [6, 12, 24])
	var fade: float = [1.0, .92, .7, .42][frame]
	var cover: float = [255, 250, 225, 170][frame]
	var grey := Paint.cloud(SIZE, seed * 11 + frame) if frame >= 2 else PackedFloat32Array()
	var colours := PackedVector3Array()
	var alphas := PackedFloat32Array()
	colours.resize(heat.size())
	alphas.resize(heat.size())
	for i in heat.size():
		var hv := clampf(heat[i] * (.8 + .4 * churn[i]) * fade, 0.0, 1.0)
		var c := ramp(hv, stops)
		var alpha := clampf((hv - .06) * 4.2, 0.0, 1.0) * cover
		if frame >= 2:
			# The flash is going out: smoke starts to show round the ember.
			var g := grey[i]
			var puff_v := clampf(1.0 - r[i] / (.62 + .1 * frame), 0.0, 1.0) * (.5 + g * .7)
			var smoke_c := Vector3(70 + g * 50, 64 + g * 46, 56 + g * 40)
			var keep := clampf(hv * 2.2, 0.0, 1.0)
			c = c * keep + smoke_c * (1.0 - keep)
			alpha = maxf(alpha, clampf(puff_v * 1.5, 0.0, 1.0) * (150 - 30 * (frame - 2)))
		colours[i] = c
		alphas[i] = alpha
	return sheet_of(SIZE, colours, alphas)


func smoke(frame: int, tint: Vector3, seed: int) -> Paint.Sheet:
	var r: PackedFloat32Array = polar(SIZE)[0]
	var grain := Paint.cloud(SIZE, seed + frame * 3)
	var lumps := Paint.cloud(SIZE, seed * 3 + frame, [3, 6, 12])
	var radius := .50 + .13 * frame
	var colours := PackedVector3Array()
	var alphas := PackedFloat32Array()
	colours.resize(SIZE * SIZE)
	alphas.resize(SIZE * SIZE)
	for i in SIZE * SIZE:
		var body := clampf((radius - r[i] * (.75 + lumps[i] * .5)) * 3.2, 0.0, 1.0)
		var shade := 58 + grain[i] * 76 + (1 - r[i]) * 22
		colours[i] = Vector3(shade * 1.04, shade * .98, shade * .9) * tint
		alphas[i] = body * (.55 + grain[i] * .45) * (178 - 34 * frame)
	return sheet_of(SIZE, colours, alphas)


func puff(frame: int) -> Paint.Sheet:
	var size := 40
	var r: PackedFloat32Array = polar(size)[0]
	var grain := Paint.cloud(size, 60 + frame, [4, 8, 16])
	var radius := .34 + .2 * frame
	var colours := PackedVector3Array()
	var alphas := PackedFloat32Array()
	colours.resize(size * size)
	alphas.resize(size * size)
	for i in size * size:
		var body := clampf((radius - r[i] * (.8 + grain[i] * .5)) * 4.0, 0.0, 1.0)
		var shade := 122 + grain[i] * 70
		colours[i] = Vector3(shade, shade * .93, shade * .8)
		alphas[i] = body * (190 - 44 * frame)
	return sheet_of(size, colours, alphas)


func sparks(frame: int) -> Paint.Sheet:
	var size := 40
	var p := polar(size)
	var r: PackedFloat32Array = p[0]
	var a: PackedFloat32Array = p[1]
	var rng := RandomNumberGenerator.new()
	rng.seed = 90
	var heat := PackedFloat32Array()
	heat.resize(size * size)
	var core: float = [1.2, .7, .25][frame]
	for i in heat.size():
		heat[i] = exp(-pow(r[i] / .16, 2)) * core
	for _k in 11:
		var at := rng.randf_range(-PI, PI)
		var length := rng.randf_range(.5, 1.0)
		var head: float = [.25, .55, .85][frame] * length
		var gain: float = [1.1, .9, .6][frame]
		for i in heat.size():
			heat[i] += (
				exp(-pow(angle_gap(a[i], at) / .05, 2)) * exp(-pow((r[i] - head) / .16, 2)) * gain
			)
	var colours := PackedVector3Array()
	var alphas := PackedFloat32Array()
	colours.resize(heat.size())
	alphas.resize(heat.size())
	for i in heat.size():
		var hv := clampf(heat[i], 0.0, 1.0)
		colours[i] = ramp(hv, FIRE)
		alphas[i] = clampf((hv - .12) * 5, 0.0, 1.0) * 255
	return sheet_of(size, colours, alphas)


## The teat gun's squirt: a burst of milk beads flung out from the teat,
## thinning to a mist (four frames, like a muzzle flash).
func spray(frame: int) -> Paint.Sheet:
	var p := polar(SIZE)
	var r: PackedFloat32Array = p[0]
	var a: PackedFloat32Array = p[1]
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var body := PackedFloat32Array()
	body.resize(SIZE * SIZE)
	var core: float = [1.1, .8, .45, .2][frame]
	for i in body.size():
		body[i] = exp(-pow(r[i] / .3, 2)) * core
	for _k in 13:
		var at := rng.randf_range(-PI, PI)
		var length := rng.randf_range(.5, 1.0)
		var head: float = [.3, .55, .78, .95][frame] * length
		var gain: float = [1.0, .95, .75, .5][frame]
		for i in body.size():
			# Beads along each ray, not a smooth streak.
			var along := clampf(1.0 - absf(r[i] - head) / .3, 0.0, 1.0)
			var beads := .55 + .45 * cos(r[i] * 46.0)
			body[i] += exp(-pow(angle_gap(a[i], at) / .12, 2)) * along * beads * gain * 1.4
	var mist := Paint.cloud(SIZE, 19 + frame, [6, 12, 24])
	var colours := PackedVector3Array()
	var alphas := PackedFloat32Array()
	colours.resize(body.size())
	alphas.resize(body.size())
	for i in body.size():
		var v := clampf(body[i], 0.0, 1.0)
		var shade := 200.0 + 55.0 * v
		colours[i] = Vector3(shade, shade * .985, shade * .93)
		var haze := clampf(1.0 - r[i] / (.5 + .12 * frame), 0.0, 1.0) * mist[i] * 90.0
		alphas[i] = maxf(clampf((v - .1) * 3.5, 0.0, 1.0) * 250.0, haze * (1.0 - .2 * frame))
	return sheet_of(SIZE, colours, alphas)


## A blast: a rolling ball of fire that swells, then chars at the edges.
func fireball(frame: int, stops: Array, seed: int) -> Paint.Sheet:
	var r: PackedFloat32Array = polar(SIZE)[0]
	var churn := Paint.cloud(SIZE, seed + frame * 5)
	var radius: float = [.52, .72, .88, .98][frame]
	var fade: float = [1.0, .9, .72, .5][frame]
	var cover: float = [255, 250, 236, 214][frame]
	var colours := PackedVector3Array()
	var alphas := PackedFloat32Array()
	colours.resize(SIZE * SIZE)
	alphas.resize(SIZE * SIZE)
	for i in SIZE * SIZE:
		var edge := radius - r[i] * (.72 + churn[i] * .6)
		var hv := clampf(clampf(edge * 3.0, 0.0, 1.0) * fade * (.7 + churn[i] * .5), 0.0, 1.0)
		var c := ramp(hv, stops)
		if frame >= 2:
			var soot := clampf((r[i] - radius * .45) * 2.4, 0.0, 1.0) * (.45 + .2 * (frame - 2))
			c = c * (1 - soot) + Vector3(52, 44, 38) * soot
		colours[i] = c
		alphas[i] = clampf(edge * 5.0, 0.0, 1.0) * cover
	return sheet_of(SIZE, colours, alphas)


func tinted(s: Paint.Sheet, tint: Vector3, lift: float) -> Paint.Sheet:
	var out := s.duplicate_sheet()
	for i in s.w * s.h:
		for k in 3:
			out.data[i * 4 + k] = clampi(int(s.data[i * 4 + k] * tint[k] + lift), 0, 255)
	return out
