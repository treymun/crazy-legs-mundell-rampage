## Software renderer: a GDScript translation of the reference engine.py.
##
## The original is a 320x156 raycaster with multiple wall heights, per-height
## floor/ceiling planes, sprites, signs, wall marks and a planar mirror pass.
## Every formula mirrors the numpy source so a frame can be diffed against
## tools/frames/py_*.png (see tools/py_frame.py).
##
## Walls are drawn as projected vertical spans with a depth buffer rather than
## as a per-column ray matrix, but the winning hit per pixel is identical.
## Columns are split into bands for the thread pool; bands never share pixels.
class_name Renderer
extends RefCounted

const WIDTH := 320
const VIEW := 156
const HEIGHT := 200
const FOCAL := 230.0
const SKY_W := 512
const SKY_H := 116
const TILE_W := 128
const TILE_BYTES := TILE_W * TILE_W * 3
const WALL_STRIDE := 9
const TAU_ := 6.283185307179586


class Sprite:
	var x := 0.0
	var y := 0.0
	var image := ""
	var height := 1.0
	var z := 0.0
	var glow := false
	var flip := false
	var translucent := false
	var body := false
	var plane := NAN
	var hurt := 0.0

	func _init(px := 0.0, py := 0.0, img := "", h := 1.0, pz := 0.0) -> void:
		x = px
		y = py
		image = img
		height = h
		z = pz


class WallMark:
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var ux := 0.0
	var uy := 0.0
	var image := ""
	var radius := .06
	var material := "wood"


class GroundMark:
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var angle := 0.0
	var reach := 1.0
	var width := 1.0
	var image := ""

	func _init(px := 0.0, py := 0.0, pz := 0.0, pa := 0.0, pr := 1.0, pw := 1.0, img := "") -> void:
		x = px
		y = py
		z = pz
		angle = pa
		reach = pr
		width = pw
		image = img


var assets: Assets
var level: LevelData

var tiles: PackedByteArray
var tints := PackedFloat32Array()
var sky: Dictionary

var frame := PackedByteArray()
var depth := PackedFloat32Array()
var glass := PackedByteArray()

var rays := PackedFloat32Array()
var row_sy := PackedFloat32Array()
var minimum := PackedFloat32Array()

var time := 0.0
var world_motion := 0
var flash := 0.0
var use_threads := true
var threads := 8
var plane_cull := true

# Camera state for the pass in flight.
var cx := 0.0
var cy := 0.0
var cz := 0.0
var view_angle := 0.0
var horizon := 0.0
var parity := 1
var fx := 0.0
var fy := 0.0
var rx := 0.0
var ry := 0.0
var mirror_min := false
var mirror_x := 0.0
var sy_rows := PackedFloat32Array()
var split := 0

# Buffers for the pass in flight.
var out: PackedByteArray
var out_w := WIDTH
var col0 := 0
var col1 := WIDTH
var dep: PackedFloat32Array
var gls: PackedByteArray

var walls := PackedFloat32Array()
var seg_n := 0
var seg_c0 := PackedInt32Array()
var seg_c1 := PackedInt32Array()
var dir_x := PackedFloat32Array()
var dir_y := PackedFloat32Array()

var pane_dist := PackedFloat32Array()
var pane_rgb := PackedByteArray()
var pane_cols := PackedByteArray()

var tile_liquor := -1
var tile_eat := -1
var tile_window := -1
var tile_mirror := -1
var tile_glazing := -1

## Precomputed shade rows.
##
## The reference multiplies uint8 samples by a float32 light and a float32
## tint, so each product is rounded to float32 before the uint8 truncation.
## GDScript multiplies in float64, which truncates one level low wherever the
## float64 product lands just under an integer (e.g. 120 * .46875 * .96 is
## exactly 54.0 after float32 rounding but 53.9999987 in float64).
##
## Wall and plane lights always come from light_at(), i.e. they are exact
## multiples of 1/32, so a table of every (tint, shade step, sample) result
## restores the reference values without doing float math per pixel. Two extra
## profiles cover the sign glow (.9) and the liquor flicker (.9 * .73), which
## are the only non-stepped grades.
const SHADE_STEPS := 97
const PROFILE_GLOW := SHADE_STEPS
const PROFILE_FLICK := SHADE_STEPS + 1
const PROFILE_COUNT := SHADE_STEPS + 2
const GLOW_STEP := 29
const SHADE_ROW := 768
var shade_rows := PackedByteArray()

var art_cache := {}
var pivots := {}

var _sprite_list: Array = []
var _mark_list: Array = []
var _ground_list: Array = []


func _init(p_assets: Assets, p_level: LevelData) -> void:
	assets = p_assets
	level = p_level
	tiles = assets.tiles
	tints = level.tints
	rays.resize(WIDTH)
	for i in WIDTH:
		rays[i] = (i + .5 - WIDTH / 2.0) / FOCAL
	row_sy.resize(VIEW)
	for i in VIEW:
		row_sy[i] = i + .5
	frame.resize(WIDTH * HEIGHT * 3)
	depth.resize(WIDTH * VIEW)
	glass.resize(WIDTH * VIEW)
	minimum.resize(WIDTH)
	sy_rows.resize(VIEW)
	pane_dist.resize(WIDTH * VIEW)
	pane_rgb.resize(WIDTH * VIEW * 3)
	pane_cols.resize(WIDTH)
	dir_x.resize(WIDTH)
	dir_y.resize(WIDTH)
	depth.fill(160.0)
	pane_dist.fill(160.0)
	sky = assets.sky(level.sky)
	# Measured on a 16c/32t CPU: 8 bands is the sweet spot. Fewer leaves the
	# machine idle; more just contends (16 bands was ~50% slower than 8).
	threads = maxi(1, mini(8, OS.get_processor_count()))
	# A browser build without SharedArrayBuffer cannot start a Thread at all:
	# render the bands one after another on the main thread instead.
	if not OS.has_feature("threads"):
		use_threads = false
	tile_liquor = level.tile_id("liquor")
	tile_eat = level.tile_id("eat")
	tile_window = level.tile_id("window")
	tile_mirror = level.tile_id("mirror")
	tile_glazing = level.tile_id("glazing")
	tile_hub_wall = level.tile_id("hub_service_wall")
	tile_hub_screen = level.tile_id("hub_screen")
	tile_hub_patch = level.tile_id("hub_patch")
	tile_hub_runoff = level.tile_id("hub_runoff")
	_build_shade_rows()


## Round a double to the nearest float32, matching numpy's float32 arithmetic.
static func _round32(value: float) -> float:
	var one := PackedFloat32Array()
	one.resize(1)
	one[0] = value
	return float(one[0])


## Every wall/plane light comes from light_at(), i.e. an exact multiple of 1/32.
## Precompute rgb * light * tint with float32 rounding at each step so the
## uint8 truncation matches the reference exactly. Two extra profiles cover the
## sign glow (max(light, .9)) and the liquor flicker (that * .73), which are the
## only grades that are not on the 1/32 grid.
func _build_shade_rows() -> void:
	var rows := tints.size() / 3
	shade_rows.resize(rows * PROFILE_COUNT * SHADE_ROW)
	var f32 := PackedFloat32Array()
	f32.resize(1)
	var prod := PackedFloat32Array()
	prod.resize(3)
	# Signs light at max(grade, .9) and the liquor tube flickers at that * .73.
	f32[0] = .9
	var glow_light := f32[0]
	f32[0] = glow_light * .73
	var flick_light := f32[0]
	var o := 0
	for r in rows:
		var tr := tints[r * 3]
		var tg := tints[r * 3 + 1]
		var tb := tints[r * 3 + 2]
		for k in PROFILE_COUNT:
			var light := float(k) / 32.0
			if k == PROFILE_GLOW:
				light = glow_light
			elif k == PROFILE_FLICK:
				light = flick_light
			for sample in 256:
				prod[0] = float(sample) * light
				prod[1] = prod[0]
				prod[2] = prod[0]
				prod[0] = float(prod[0]) * tr
				prod[1] = float(prod[1]) * tg
				prod[2] = float(prod[2]) * tb
				for ch in 3:
					var v := int(prod[ch])
					if v < 0:
						v = 0
					elif v > 255:
						v = 255
					shade_rows[o] = v
					o += 1


## Shade-step index for a light already produced by light_at().
static func shade_step(light: float) -> int:
	return clampi(int(light * 32.0 + .5), 0, SHADE_STEPS - 1)


## Reference light_at(): stepped 1/32 shades with a .19 floor.
## The reference divides first and clamps afterwards, so distant surfaces stop
## darkening at .19 instead of continuing toward zero.
static func light_at(distance: float, light: float) -> float:
	var shade := maxf(.19, light / (1.0 + .102 * distance))
	return floorf(shade * 32.0 + .5) / 32.0


static func tint_index(area: int, t: PackedFloat32Array) -> int:
	return mini(maxi(area, 0), t.size() / 3 - 1) * 3


func render(
	player: Dictionary,
	sprites: Array,
	reflection_sprite,
	flash_value: float,
	marks: Array,
	ground_marks: Array
) -> PackedByteArray:
	var px: float = player["x"]
	var py: float = player["y"]
	var pz: float = player["eye"]
	var angle: float = player["view_angle"]
	var hz := VIEW / 2.0 + float(player["pitch"]) + float(player["bob"]) + float(player["sway"])
	flash = flash_value
	var at_hub := not level.road_and_hub.is_empty() and py > 33.0
	var active := level.active_walls(at_hub)
	_prepare_hub(at_hub)
	# Fresh, exclusively-owned pass buffers every frame. PackedArray writes are
	# copy-on-write, and Godot's detach is not safe when several band threads
	# write into storage that any other reference (the previous frame handed to
	# Image.set_data, the canvas) still holds: workers would intermittently see
	# a zero-length array. Allocating per frame keeps every buffer single-owner,
	# and returning this one directly is then safe because the next frame
	# allocates a different array instead of rewriting it.
	frame = PackedByteArray()
	frame.resize(WIDTH * HEIGHT * 3)
	depth = PackedFloat32Array()
	depth.resize(WIDTH * VIEW)
	glass = PackedByteArray()
	glass.resize(WIDTH * VIEW)
	pane_dist = PackedFloat32Array()
	pane_dist.resize(WIDTH * VIEW)
	_scene(
		px,
		py,
		pz,
		angle,
		hz,
		1,
		active,
		sprites,
		marks,
		ground_marks,
		frame,
		WIDTH,
		0,
		WIDTH,
		depth,
		glass
	)
	_mirror_pass(px, py, pz, angle, hz, active, sprites, reflection_sprite, marks, ground_marks)
	return frame


func _scene(
	x: float,
	y: float,
	z: float,
	angle: float,
	hz: float,
	par: int,
	segments: PackedFloat32Array,
	sprites: Array,
	marks: Array,
	ground_marks: Array,
	buf: PackedByteArray,
	buf_w: int,
	c0: int,
	c1: int,
	depth_buf: PackedFloat32Array,
	glass_buf: PackedByteArray
) -> void:
	cx = x
	cy = y
	cz = z
	view_angle = angle
	horizon = hz
	parity = par
	fx = cos(angle)
	fy = sin(angle)
	rx = -fy * par
	ry = fx * par
	mirror_min = par < 0 and not is_nan(level.mirror_x)
	mirror_x = level.mirror_x
	out = buf
	out_w = buf_w
	col0 = c0
	col1 = c1
	dep = depth_buf
	gls = glass_buf
	# Python allocates fresh depth/pane arrays per scene; reuse the members but
	# clear them here so a reflection pass never inherits the main pass's state.
	depth_buf.fill(160.0)
	glass_buf.fill(0)
	pane_dist.fill(160.0)
	split = clampi(int(floor(hz - .5)) + 1, 0, VIEW)
	for r in VIEW:
		sy_rows[r] = row_sy[r] - hz
	for i in WIDTH:
		dir_x[i] = fx + rx * rays[i]
		dir_y[i] = fy + ry * rays[i]
	for i in WIDTH:
		pane_cols[i] = 0

	_sprite_list = sprites
	_mark_list = marks
	_ground_list = ground_marks
	_prepare(segments)
	_warm_art()

	# Bands own disjoint columns, so walls, planes and overlays all band.
	if use_threads and threads > 1 and c1 - c0 >= 96:
		_run_bands(c0, c1)
	else:
		_band(c0, c1)
	_pane_wash()


## Resolve every sprite lookup on the main thread before the band workers run.
## `art_cache` and `pivots` are plain Dictionaries; two workers inserting into
## the same Dictionary at once can corrupt its table (an access violation), and
## the first frame of a level is exactly when every sprite misses the cache.
func _warm_art() -> void:
	for s: Sprite in _sprite_list:
		var art := sprite_art(s.image)
		if s.body and not pivots.has(s.image):
			body_offset(s.image, art["data"], int(art["w"]), int(art["h"]), 1)
	for m: WallMark in _mark_list:
		sprite_art(m.image)
	for m: GroundMark in _ground_list:
		sprite_art(m.image)


var _band_per := 0
var _band_count := 0
var _workers: Array[Thread] = []


## Explicit Thread workers instead of WorkerThreadPool: the pool reuses engine
## task slots shared with the rest of the engine, which made the band workers
## observe a half-swapped set of pass buffers. Each band is a fixed column
## range and bands never share pixels, so ordering does not matter.
func _run_bands(c0: int, c1: int) -> void:
	var per := int(ceil(float(c1 - c0) / threads))
	var bands := int(ceil(float(c1 - c0) / per))
	_band_per = per
	_band_count = bands
	while _workers.size() < bands:
		_workers.append(Thread.new())
	for i in bands:
		var t: Thread = _workers[i]
		if t.is_started():
			t.wait_to_finish()
		t.start(_band_worker.bind(i, bands))
	for i in bands:
		_workers[i].wait_to_finish()


func _band_worker(slot: int, stride: int) -> void:
	var i := slot
	while i < _band_count:
		var a := col0 + i * _band_per
		var b := mini(col1, a + _band_per)
		if a < b:
			_band(a, b)
		i += stride


## One band: sky, wall spans, planes, then marks and sprites for its columns.
func _band(a: int, b: int) -> void:
	_sky_band(a, b)
	_wall_band(a, b)
	_plane_band(a, b)
	_mark_band(a, b)
	_ground_band(a, b)
	_sprite_band(a, b)


func _prepare(segments: PackedFloat32Array) -> void:
	walls = segments
	seg_n = segments.size() / WALL_STRIDE
	seg_c0.resize(seg_n)
	seg_c1.resize(seg_n)
	for i in seg_n:
		var o := i * WALL_STRIDE
		var r0x := segments[o] - cx
		var r0y := segments[o + 1] - cy
		var r1x := segments[o + 2] - cx
		var r1y := segments[o + 3] - cy
		var a0 := r0x * fx + r0y * fy
		var a1 := r1x * fx + r1y * fy
		if a0 <= .0001 and a1 <= .0001:
			seg_c0[i] = 0
			seg_c1[i] = 0
			continue
		var s0 := r0x * rx + r0y * ry
		var s1 := r1x * rx + r1y * ry
		if a0 < .02:
			var f := (a0 - .02) / (a0 - a1)
			a0 = .02
			s0 += (s1 - s0) * f
		elif a1 < .02:
			var f := (a1 - .02) / (a1 - a0)
			a1 = .02
			s1 += (s0 - s1) * f
		var m0 := WIDTH / 2.0 + s0 / a0 * FOCAL - .5
		var m1 := WIDTH / 2.0 + s1 / a1 * FOCAL - .5
		seg_c0[i] = maxi(col0, int(floor(minf(m0, m1))) - 1)
		seg_c1[i] = mini(col1, int(ceil(maxf(m0, m1))) + 2)


# -------------------------------------------------------------------- sky
func _sky_band(a: int, b: int) -> void:
	var data: PackedByteArray = sky["data"]
	var scale := 512.0 / TAU_
	var n := b - a
	var col_off := PackedInt32Array()
	col_off.resize(n)
	for i in n:
		var ang := view_angle + parity * atan(rays[a + i])
		col_off[i] = (int(ang * scale) & 511) * 3
	var row_off := PackedInt32Array()
	row_off.resize(VIEW)
	for r in VIEW:
		row_off[r] = clampi(int(93.0 + sy_rows[r] * .95), 0, 115) * SKY_W * 3
	var w := out_w
	for r in VIEW:
		var s := row_off[r]
		var d := r * w * 3 + (a - col0) * 3
		for i in n:
			var o := s + col_off[i]
			out[d] = data[o]
			out[d + 1] = data[o + 1]
			out[d + 2] = data[o + 2]
			d += 3


# -------------------------------------------------------------- wall spans
func _wall_band(a: int, b: int) -> void:
	var i := 0
	while i < seg_n:
		var s0 := maxi(a, seg_c0[i])
		var s1 := mini(b, seg_c1[i])
		if s0 < s1:
			_wall_segment(i, s0, s1)
		i += 1


func _wall_segment(i: int, a: int, b: int) -> void:
	var o := i * WALL_STRIDE
	var x1 := walls[o]
	var y1 := walls[o + 1]
	var x2 := walls[o + 2]
	var y2 := walls[o + 3]
	var material := int(walls[o + 4])
	var base_light := walls[o + 5] + flash
	var bottom := walls[o + 6]
	var top := walls[o + 7]
	var area := int(walls[o + 8])
	if top <= bottom:
		return
	var ex := x2 - x1
	var ey := y2 - y1
	var px := x1 - cx
	var py := y1 - cy
	var den_a := fx * ey - fy * ex
	var den_b := rx * ey - ry * ex
	var t_num := px * ey - py * ex
	var u_a := px * fy - py * fx
	var u_b := px * ry - py * rx
	var vspan := top - bottom
	var tile_off := material * TILE_BYTES
	var glow := material == tile_liquor or material == tile_eat or material == tile_window
	var mirror := material == tile_mirror
	var ti := tint_index(area, tints)
	var glazing := material == tile_glazing
	var hub_wall := hub_fx and material == tile_hub_wall
	var hub_screen := hub_fx and material == tile_hub_screen
	var phase := time - floorf(time / 6.1) * 6.1
	var flicker := phase > .87 and phase < 1.02
	var w := out_w
	for c in range(a, b):
		var ray := rays[c]
		var den := den_a + ray * den_b
		if absf(den) < 1e-6:
			continue
		var t := t_num / den
		if t <= .015 or t >= 160.0:
			continue
		var u := (u_a + ray * u_b) / den
		if u < -.00002 or u > 1.00002:
			continue
		if mirror_min:
			var dxv := dir_x[c]
			var dnm := dxv if absf(dxv) > .00001 else -.00001
			var min_t := (mirror_x - cx) / dnm + .008
			if min_t > .015 and t <= min_t:
				continue
		var tex_u := 1.0 - u if den < 0.0 else u
		var uu := clampi(int(tex_u * 128.0), 0, 127)
		# A glazing tile keeps its frame and mullions opaque; only the pane
		# rectangles are held back and composited after the scene (the reference
		# drops them from the opaque layer's pixel list).
		var pane_ok := glazing and uu > 5 and uu < 122 and (uu < 62 or uu > 67)
		var light := light_at(t, base_light)
		var sample_off := tile_off + uu * 3
		var step := shade_step(light)
		var profile := (ti / 3) * PROFILE_COUNT
		var row_base := (profile + step) * SHADE_ROW
		var glow_base := (profile + PROFILE_GLOW) * SHADE_ROW
		var flick_base := (profile + PROFILE_FLICK) * SHADE_ROW
		var shade := shade_rows
		var sy_lo := (cz - top) * FOCAL / t
		var sy_hi := (cz - bottom) * FOCAL / t
		if sy_lo > sy_hi:
			var swap := sy_lo
			sy_lo = sy_hi
			sy_hi = swap
		var r0 := maxi(0, int(ceil(sy_lo + horizon - .5)))
		var r1 := mini(VIEW - 1, int(floor(sy_hi + horizon - .5)))
		if r0 > r1:
			continue
		var sy := float(r0) + .5 - horizon
		var t_inv := t / FOCAL
		var row := r0
		var lx := c - col0
		var gi := row * w + lx
		var oi := gi * 3
		var depth_here := dep
		var glass_here := gls
		var hit_x := cx + t * dir_x[c]
		var hit_y := cy + t * dir_y[c]
		while row <= r1:
			var wall_z := cz - sy * t_inv
			if wall_z >= bottom and wall_z <= top and t < depth_here[gi]:
				var v := int(clampi(int((top - wall_z) / vspan * 128.0), 0, 127))
				# The road shed's hardware cloth: the open mesh is simply not
				# drawn, so whatever stands behind it shows through.
				if not (hub_screen and screen_hole(uu, v)):
					var si := sample_off + v * TILE_W * 3
					var sr := tiles[si]
					var sg := tiles[si + 1]
					var sb := tiles[si + 2]
					var base := row_base
					var bright := glow and (sr > 156 or sg > 156 or sb > 156)
					if bright and step < GLOW_STEP:
						base = flick_base if flicker and material == tile_liquor else glow_base
					var cr := shade[base + sr * 3]
					var cg := shade[base + sg * 3 + 1]
					var cb := shade[base + sb * 3 + 2]
					if bright and step >= GLOW_STEP and flicker and material == tile_liquor:
						# A tube already lit past the .9 glow floor still dips
						# to .73 of its own light; that grade is off the table.
						var dim := float(step) / 32.0 * .73
						cr = clampi(int(sr * dim * tints[ti]), 0, 255)
						cg = clampi(int(sg * dim * tints[ti + 1]), 0, 255)
						cb = clampi(int(sb * dim * tints[ti + 2]), 0, 255)
					if hub_wall:
						var shadow := tower_shadow(hit_x, hit_y, wall_z)
						if shadow < 1.0:
							cr = int(cr * shadow)
							cg = int(cg * shadow)
							cb = int(cb * shadow)
					var pane := pane_ok and v > 6 and v < 121 and (v < 67 or v > 73)
					if pane:
						if t < pane_dist[gi]:
							pane_dist[gi] = t
							var p := gi * 3
							pane_rgb[p] = cr
							pane_rgb[p + 1] = cg
							pane_rgb[p + 2] = cb
							pane_cols[c] = 1
					else:
						out[oi] = cr
						out[oi + 1] = cg
						out[oi + 2] = cb
						depth_here[gi] = t
						glass_here[gi] = (
							1
							if (
								mirror
								and parity > 0
								and uu >= 12
								and uu < 116
								and v >= 17
								and v < 108
							)
							else 0
						)
			sy += 1.0
			row += 1
			gi += w
			oi += w * 3


# ------------------------------------------------------- crossroads surfaces
# Port of crossroads.py: three bounded effects the reference applies only while
# the camera is in the County Crossroads half of the Hickston map.

const TOWER_X := 19.05
const TOWER_Y := 45.16
const TOWER_LEGS: Array[Vector2] = [
	Vector2(-.72, -.52), Vector2(.72, -.52), Vector2(-.72, .52), Vector2(.72, .52)
]

var tile_hub_wall := -1
var tile_hub_screen := -1
var tile_hub_patch := -1
var tile_hub_runoff := -1
var hub_fx := false
var _shadow_still := false
var _shadow_gust := 0.0
var _shadow_lx := 1.15
var _shadow_ly := .73
var _water_drift := 0.0


## Per-frame constants for the shadow and the runoff, from SCENERY MOTION
## (0 full, 1 reduced, 2 static).
func _prepare_hub(active: bool) -> void:
	hub_fx = active and tile_hub_patch >= 0
	_shadow_still = world_motion == 2
	_shadow_gust = 0.0 if _shadow_still else sin(time * .83) * (.13 if world_motion == 0 else .045)
	_shadow_lx = 1.15 + _shadow_gust
	_shadow_ly = .73 + _shadow_gust * .32
	_water_drift = (0.0 if world_motion == 2 else time) * (1.9 if world_motion == 0 else .72)


## screen_holes(): large areas of old hardware cloth between boarded repairs.
static func screen_hole(u: int, v: int) -> bool:
	if u < 7 or u > 120 or v < 7 or v > 119:
		return false
	if (u >= 48 and u <= 54) or (v >= 67 and v <= 73):
		return false
	if v > 95 and u < 42 + v / 5:
		return false
	return (u + v) % 17 >= 2 and posmod(u - v, 18) >= 2


## tower_shadow(): the water tank and its four legs thrown by a low sun, with
## scrub under the tank breaking up the edge. Returns the light multiplier.
func tower_shadow(x: float, y: float, z: float) -> float:
	if _shadow_still:
		# The reference samples a fixed 1/16-unit light volume in still mode.
		var ix := roundi((x - 17.0) * 16.0)
		var iy := roundi((y - 43.0) * 16.0)
		var iz := roundi(z * 16.0)
		if ix < 0 or ix > 160 or iy < 0 or iy > 128 or iz < 0 or iz > 16:
			return 1.0
		x = 17.0 + ix / 16.0
		y = 43.0 + iy / 16.0
		z = iz / 16.0
	var lx := _shadow_lx
	var ly := _shadow_ly
	var rxv := x - TOWER_X
	var ryv := y - TOWER_Y
	var lift := 3.83 - z
	var tank_x := (rxv - lx * lift) / 1.31
	var tank_y := (ryv - ly * lift) / .92
	var dark := clampf((1.18 - sqrt(tank_x * tank_x + tank_y * tank_y)) * 3.4, 0.0, 1.0)
	var dxv := rxv + lx * z
	var dyv := ryv + ly * z
	# A leg only darkens points within .21 of its own shadow line.
	if dxv > -.93 and dxv < .93 + 3.55 * lx and dyv > -.73 and dyv < .73 + 3.55 * ly:
		var vector := lx * lx + ly * ly
		for leg: Vector2 in TOWER_LEGS:
			var qx := dxv - leg.x
			var qy := dyv - leg.y
			var along := clampf((qx * lx + qy * ly) / vector, 0.0, 3.55)
			var off := absf(qx - along * lx) + absf(qy - along * ly)
			var post := clampf((.21 - off) * 5.0, 0.0, .80)
			if post > dark:
				dark = post
	var fx_ := (rxv - 2.72) / 1.70
	var fy_ := (ryv - 1.59) / .86
	if absf(fx_) < 1.1 and absf(fy_) < 1.1:
		var fringe := clampf((1.1 - sqrt(fx_ * fx_ + fy_ * fy_)) * 1.55, 0.0, 1.0)
		if fringe > 0.0:
			var stems := clampf(
				(sin(rxv * 14.3 + ryv * 5.1 + _shadow_gust * 8.0) - .25) * 1.2, 0.0, 1.0
			)
			var scrub := fringe * stems * .51
			if scrub > dark:
				dark = scrub
	return 1.0 - .36 * dark


## running_water(): ripples over the gravel of the culvert runoff. `rgb` holds
## the three gravel texels and is rewritten in place.
func running_water(rgb: PackedInt32Array, x: float, y: float) -> void:
	var edge := clampf(minf(y - 49.0, 51.0 - y) * 1.9, 0.0, 1.0)
	var drift := _water_drift
	var line := sin(13.0 * y + 1.7 * sin(x * 2.1 - drift) + .8 * sin(x * 4.3 - drift * 1.6))
	var streak := sin(x * 6.7 - drift * 3.0 + .8 * sin(y * 22.0))
	var ripples := clampf((line + .36 * streak - .63) * .62, 0.0, .62) * edge
	var mix_ := edge * .38 + ripples * .52
	rgb[0] = roundi(rgb[0] * (1.0 - mix_) + (88.0 + ripples * 154.0) * mix_)
	rgb[1] = roundi(rgb[1] * (1.0 - mix_) + (120.0 + ripples * 150.0) * mix_)
	rgb[2] = roundi(rgb[2] * (1.0 - mix_) + (132.0 + ripples * 123.0) * mix_)


# ----------------------------------------------------------------- planes
func _plane_band(a: int, b: int) -> void:
	_plane_layer(level.roof_bounds, true, 0, split, a, b)
	_plane_layer(level.floor_bounds, false, split, VIEW, a, b)


func _plane_layer(bounds: Dictionary, overhead: bool, row0: int, row1: int, a: int, b: int) -> void:
	if row1 <= row0:
		return
	var w := out_w
	var n := b - a
	var begin := PackedFloat32Array()
	var end := PackedFloat32Array()
	begin.resize(n)
	end.resize(n)
	var lit_scale := .77 if overhead else .94
	for key in bounds:
		var h: float = key
		if overhead:
			if h <= cz:
				continue
		elif h >= cz:
			continue
		var box: Vector4i = bounds[key]
		var bx0 := float(box.x)
		var by0 := float(box.y)
		var bx1 := float(box.z)
		var by1 := float(box.w)
		var tscale := absf(h - cz) * FOCAL
		# Conservative column cull: project the bbox corners and skip heights
		# whose whole box lands outside this band. The per-column test below
		# still decides the exact span, so a padded bound is always safe.
		if plane_cull:
			var cull := true
			var cmin := 1e30
			var cmax := -1e30
			for ci2 in 4:
				var px2 := bx0 if ci2 < 2 else bx1
				var py2 := by0 if ci2 % 2 == 0 else by1
				var ddx := px2 - cx
				var ddy := py2 - cy
				var d2 := ddx * fx + ddy * fy
				if d2 <= .02:
					cull = false
					break
				var col2 := WIDTH / 2.0 + (ddx * rx + ddy * ry) / d2 * FOCAL
				if col2 < cmin:
					cmin = col2
				if col2 > cmax:
					cmax = col2
			if cull and (cmax < float(a) - 2.0 or cmin > float(b) + 2.0):
				continue
		var bmin := 1e30
		var emax := -1e30
		var any := false
		var left := -1
		var right := -1
		for i in n:
			var dxv := dir_x[a + i]
			var dyv := dir_y[a + i]
			var sx := dxv if absf(dxv) > 1e-7 else 1e-7
			var syv := dyv if absf(dyv) > 1e-7 else 1e-7
			var ax := (bx0 - cx) / sx
			var bx := (bx1 - cx) / sx
			var ay := (by0 - cy) / syv
			var by := (by1 - cy) / syv
			var mn := maxf(maxf(minf(ax, bx), minf(ay, by)), .015)
			var mx := minf(maxf(ax, bx), maxf(ay, by))
			begin[i] = mn
			end[i] = mx
			if mn <= mx:
				any = true
				if mn < bmin:
					bmin = mn
				if mx > emax:
					emax = mx
				if left < 0:
					left = i
				right = i + 1
		if not any:
			continue
		var low := row1
		var high := row0 - 1
		for r in range(row0, row1):
			var t := minf(tscale / maxf(.02, absf(sy_rows[r])), 80.0)
			if t >= bmin and t <= emax:
				if r < low:
					low = r
				high = r
		if high < low:
			continue
		var caps_here: Array = level.caps.get(h, [])
		var flows: Array = []
		for f in level.moving_floors.get(h, []):
			flows.append([int(f[0]), (int(time * float(f[1]))) & 127])
		var lx0 := a - col0
		var tiles_ := tiles
		var out_ := out
		var dep_ := dep
		var gls_ := gls
		var shade_ := shade_rows
		var roof_ := level.roof
		var ground_ := level.ground
		var ceil_tile_ := level.ceiling_tile
		var floor_tile_ := level.floor_tile
		var light_ := level.light
		var area_ := level.area
		var tints_ := tints
		var tint_max := tints_.size() / 3 - 1
		var dir_x_ := dir_x
		var dir_y_ := dir_y
		var rows_ := sy_rows
		var lw := level.width
		var lh := level.height
		var has_caps := not caps_here.is_empty()
		var hub_floor := hub_fx and not overhead
		var t_patch := tile_hub_patch
		var t_wall := tile_hub_wall
		var t_runoff := tile_hub_runoff
		var water := PackedInt32Array([0, 0, 0])
		# Row-major order (the reference's layout): the distance, its light
		# falloff and the shading divisor are constant across the row, so they
		# are computed once instead of once per pixel.
		for r in range(low, high + 1):
			var t := minf(tscale / maxf(.02, absf(rows_[r])), 80.0)
			if t < bmin or t > emax:
				continue
			var falloff := 1.0 / (1.0 + .102 * t)
			var drow := r * w + lx0
			for i in range(left, right):
				if t < begin[i] or t > end[i]:
					continue
				var gi := drow + i
				if t >= dep_[gi]:
					continue
				var wx := cx + t * dir_x_[a + i]
				var wy := cy + t * dir_y_[a + i]
				var ix := int(wx)
				var iy := int(wy)
				if ix < 0 or iy < 0 or ix >= lw or iy >= lh:
					continue
				var ci := iy * lw + ix
				var tile := -1
				if overhead:
					if roof_[ci] == h:
						tile = ceil_tile_[ci]
				else:
					if ground_[ci] == h:
						tile = floor_tile_[ci]
					if has_caps:
						for cap in caps_here:
							if wx >= cap[0] and wx <= cap[2] and wy >= cap[1] and wy <= cap[3]:
								tile = int(cap[4])
								break
				if tile < 0:
					continue
				var pu := int(wx * 128.0) & 127
				var pv := int(wy * 128.0) & 127
				for f in flows:
					if tile == f[0]:
						pv = (pv + f[1]) & 127
				# light_at() and shade_step() inlined: the reference clamps the
				# quotient first, so distant surfaces stop at .19.
				var raw := (light_[ci] * lit_scale + flash) * falloff
				var shade := raw if raw > .19 else .19
				var step := int(shade * 32.0 + .5)
				if step > SHADE_STEPS - 1:
					step = SHADE_STEPS - 1
				var ti := area_[ci]
				if ti < 0:
					ti = 0
				elif ti > tint_max:
					ti = tint_max
				var si := tile * TILE_BYTES + pv * TILE_W * 3 + pu * 3
				var oi := gi * 3
				var sbase := (ti * PROFILE_COUNT + step) * SHADE_ROW
				var pr := tiles_[si]
				var pg := tiles_[si + 1]
				var pb := tiles_[si + 2]
				var shadow := 1.0
				if hub_floor:
					if tile == t_runoff:
						water[0] = pr
						water[1] = pg
						water[2] = pb
						running_water(water, wx, wy)
						pr = water[0]
						pg = water[1]
						pb = water[2]
					elif tile == t_patch or tile == t_wall:
						shadow = tower_shadow(wx, wy, h)
				if shadow < 1.0:
					# The shadow scales the stepped light, which takes it off
					# the 1/32 grid the shade table is built on.
					var lit := float(step) / 32.0 * shadow
					out_[oi] = clampi(int(pr * lit * tints_[ti * 3]), 0, 255)
					out_[oi + 1] = clampi(int(pg * lit * tints_[ti * 3 + 1]), 0, 255)
					out_[oi + 2] = clampi(int(pb * lit * tints_[ti * 3 + 2]), 0, 255)
				else:
					out_[oi] = shade_[sbase + pr * 3]
					out_[oi + 1] = shade_[sbase + pg * 3 + 1]
					out_[oi + 2] = shade_[sbase + pb * 3 + 2]
				dep_[gi] = t
				gls_[gi] = 0


# --------------------------------------------------------------- glazing
func _pane_wash() -> void:
	for c in range(col0, col1):
		if pane_cols[c] == 0:
			continue
		for r in VIEW:
			var gi := r * out_w + (c - col0)
			var pd := pane_dist[gi]
			if pd >= 160.0 or pd >= dep[gi]:
				continue
			var o := gi * 3
			out[o] = clampi(int(out[o] * .67 + pane_rgb[o] * .33), 0, 255)
			out[o + 1] = clampi(int(out[o + 1] * .78 + pane_rgb[o + 1] * .33), 0, 255)
			out[o + 2] = clampi(int(out[o + 2] * .82 + pane_rgb[o + 2] * .33), 0, 255)


# ------------------------------------------------------------------ mirror
func _mirror_pass(
	x: float,
	y: float,
	z: float,
	angle: float,
	hz: float,
	segments: PackedFloat32Array,
	sprites: Array,
	reflection_sprite,
	marks: Array,
	ground_marks: Array
) -> void:
	if is_nan(level.mirror_x):
		return
	var a := -1
	var b := -1
	for c in WIDTH:
		var hit := false
		for r in VIEW:
			if glass[r * WIDTH + c] != 0:
				hit = true
				break
		if hit:
			if a < 0:
				a = c
			b = c + 1
	if a < 0 or b <= a:
		return
	var w := b - a
	var rframe := PackedByteArray()
	var rdepth := PackedFloat32Array()
	var rglass := PackedByteArray()
	rframe.resize(w * VIEW * 3)
	rdepth.resize(w * VIEW)
	rglass.resize(w * VIEW)
	var ghost := sprites.duplicate()
	if reflection_sprite != null:
		ghost.append(reflection_sprite)
	# _scene retargets the pass buffers, so keep the main pass's mask/frame.
	var main_glass := glass
	var main_frame := frame
	var keep_out := out
	var keep_dep := dep
	var keep_gls := gls
	_scene(
		2.0 * level.mirror_x - x,
		y,
		z,
		PI - angle,
		hz,
		-1,
		segments,
		ghost,
		marks,
		ground_marks,
		rframe,
		w,
		a,
		b,
		rdepth,
		rglass
	)
	out = keep_out
	dep = keep_dep
	gls = keep_gls
	for r in VIEW:
		var drow := r * WIDTH
		var srow := r * w
		for c in range(a, b):
			var gi := drow + c
			if main_glass[gi] == 0:
				continue
			var si := srow + (c - a)
			var o := gi * 3
			var so := si * 3
			# Reference casts the float expression straight to uint8, so the
			# mirror composite truncates instead of rounding.
			var cr := int(rframe[so] * .81 + 7.0)
			var cg := int(rframe[so + 1] * .86 + 8.0)
			var cb := int(rframe[so + 2] * .84 + 6.0)
			if (c + r * 2) % 61 == 0:
				cr = int(float(cr) * .88) + 14
				cg = int(float(cg) * .88) + 13
				cb = int(float(cb) * .88) + 11
			main_frame[o] = clampi(cr, 0, 255)
			main_frame[o + 1] = clampi(cg, 0, 255)
			main_frame[o + 2] = clampi(cb, 0, 255)


# ----------------------------------------------------------------- sprites
func sprite_art(name: String) -> Dictionary:
	var cached = art_cache.get(name)
	if cached != null:
		return cached
	var a := assets.art(name)
	art_cache[name] = a
	return a


func body_offset(name: String, data: PackedByteArray, w: int, h: int, height: int) -> int:
	if not pivots.has(name):
		var last := -1
		for y in range(h - 1, -1, -1):
			var row := y * w * 4
			var found := false
			for x in w:
				if data[row + x * 4 + 3] > 100:
					found = true
					break
			if found:
				last = y
				break
		pivots[name] = float(h - 1 - last) / float(h) if last >= 0 else 0.0
	return int(round(height * pivots[name]))


func _sprite_band(a: int, b: int) -> void:
	for s: Sprite in _sprite_list:
		_draw_sprite(s, a, b)


func _draw_sprite(s: Sprite, a: int, b: int) -> void:
	var dx := s.x - cx
	var dy := s.y - cy
	if parity < 0 and s.x < level.mirror_x:
		return
	var dist := dx * fx + dy * fy
	var limit := 51.0 if s.height > 2.7 else 32.0
	if dist <= .13 or dist >= limit:
		return
	var lateral := dx * rx + dy * ry
	var screen_x := WIDTH / 2.0 + lateral / dist * FOCAL - a
	var height := int(s.height / dist * FOCAL)
	if height < 2:
		return
	var top := 0
	if is_nan(s.plane):
		top = int(round(horizon - (s.z + s.height - cz) / dist * FOCAL))
		if top >= VIEW or (top + height <= 0 and not s.body):
			return
	var art := sprite_art(s.image)
	var sw: int = art["w"]
	var sh: int = art["h"]
	var data: PackedByteArray = art["data"]
	if not is_nan(s.plane):
		_draw_sign(s, a, b, data, sw, sh)
		return
	var width := maxi(1, int(height * float(sw) / float(sh)))
	if screen_x < -width / 2.0 or screen_x > b - a + width / 2.0:
		return
	var left := int(round(screen_x - width / 2.0))
	if s.body:
		top += body_offset(s.image, data, sw, sh, height)
	var x0 := maxi(0, left)
	var x1 := mini(b - a, left + width)
	var y0 := maxi(0, top)
	var y1 := mini(VIEW, top + height)
	if x0 >= x1 or y0 >= y1:
		return
	var ci := level.cell(s.x, s.y)
	var light := 1.1 if s.glow else light_at(dist, level.light[ci])
	if s.body:
		light = maxf(light, .58 - .021 * dist)
	var area := 1 if s.glow else level.area[ci]
	var ti := tint_index(area, tints)
	var tr := tints[ti]
	var tg := tints[ti + 1]
	var tb := tints[ti + 2]
	var hurt_k := minf(.46, s.hurt / .18 * .44) if s.hurt > 0.0 else 0.0
	var threshold := 12 if s.translucent else 100
	var flip := s.flip != (parity < 0)
	var w := out_w
	var out_ := out
	var dep_ := dep
	var gls_ := gls
	var lx0 := a - col0
	for y in range(y0, y1):
		var syi := (y - top) * sh / height
		var drow := y * w
		for x in range(x0, x1):
			var sxi := (x - left) * sw / width
			if flip:
				sxi = sw - sxi - 1
			var sp := (syi * sw + sxi) * 4
			var alpha := data[sp + 3]
			if alpha <= threshold:
				continue
			var gi := drow + lx0 + x
			if dist >= dep_[gi] + .014:
				continue
			# The reference's order: shade (and clip) the texel first, then wash
			# the lit colour toward hot white, so a hit flash reads the same on a
			# dark or distant enemy as on a bright near one.
			var cr := clampi(int(data[sp] * light * tr), 0, 255)
			var cg := clampi(int(data[sp + 1] * light * tg), 0, 255)
			var cb := clampi(int(data[sp + 2] * light * tb), 0, 255)
			if hurt_k > 0.0:
				cr = int(cr * (1.0 - hurt_k) + 255.0 * hurt_k)
				cg = int(cg * (1.0 - hurt_k) + 232.0 * hurt_k)
				cb = int(cb * (1.0 - hurt_k) + 208.0 * hurt_k)
			var o := gi * 3
			if s.translucent:
				var cov := alpha / 255.0
				out_[o] = clampi(int(round(out_[o] * (1.0 - cov) + cr * cov)), 0, 255)
				out_[o + 1] = clampi(int(round(out_[o + 1] * (1.0 - cov) + cg * cov)), 0, 255)
				out_[o + 2] = clampi(int(round(out_[o + 2] * (1.0 - cov) + cb * cov)), 0, 255)
			else:
				out_[o] = cr
				out_[o + 1] = cg
				out_[o + 2] = cb
				dep_[gi] = dist
				gls_[gi] = 0


## Painted board: project along the sprite's world axis (draw_sign()).
func _draw_sign(s: Sprite, a: int, b: int, data: PackedByteArray, sw: int, sh: int) -> void:
	var ax := cos(s.plane)
	var ay := sin(s.plane)
	var rxv := s.x - cx
	var ryv := s.y - cy
	var side := rxv * ay - ryv * ax
	if side <= .02:
		return
	var width := s.height * float(sw) / float(sh)
	var near := rays[a]
	var far := rays[b - 1]
	var ahead := rxv * fx + ryv * fy
	var lateral := rxv * rx + ryv * ry
	var half_ahead := (ax * fx + ay * fy) * width * .5
	var half_lateral := (ax * rx + ay * ry) * width * .5
	if near * ahead - lateral > absf(near * half_ahead - half_lateral) + .002:
		return
	if lateral - far * ahead > absf(half_lateral - far * half_ahead) + .002:
		return
	var ci := level.cell(s.x, s.y)
	var area := level.area[ci]
	var ti := tint_index(area, tints)
	var tr := tints[ti]
	var tg := tints[ti + 1]
	var tb := tints[ti + 2]
	var threshold := 12 if s.translucent else 100
	var w := out_w
	var lx0 := a - col0
	for c in range(a, b):
		var ray := rays[c]
		var dxv := fx + rx * ray
		var dyv := fy + ry * ray
		var den := ay * dxv - ax * dyv
		if den <= .001:
			continue
		var d := side / den
		if d <= .13:
			continue
		var along := ((cx - s.x + dxv * d) * ax + (cy - s.y + dyv * d) * ay) / width + .5
		if along < 0.0 or along >= 1.0:
			continue
		var u := clampi(int(along * sw), 0, sw - 1)
		var light := light_at(d, level.light[ci])
		var lx := c - col0
		for r in VIEW:
			var v := (s.z + s.height - cz + sy_rows[r] * d / FOCAL) / s.height
			if v < 0.0 or v >= 1.0:
				continue
			var gi := r * w + lx
			if d >= dep[gi] + .012:
				continue
			var vv := clampi(int(v * sh), 0, sh - 1)
			var sp := (vv * sw + u) * 4
			var alpha := data[sp + 3]
			if alpha <= threshold:
				continue
			var cr := int(data[sp] * light * tr)
			var cg := int(data[sp + 1] * light * tg)
			var cb := int(data[sp + 2] * light * tb)
			var o := gi * 3
			if s.translucent:
				var cov := alpha / 255.0
				out[o] = clampi(int(round(out[o] * (1.0 - cov) + cr * cov)), 0, 255)
				out[o + 1] = clampi(int(round(out[o + 1] * (1.0 - cov) + cg * cov)), 0, 255)
				out[o + 2] = clampi(int(round(out[o + 2] * (1.0 - cov) + cb * cov)), 0, 255)
			else:
				out[o] = clampi(cr, 0, 255)
				out[o + 1] = clampi(cg, 0, 255)
				out[o + 2] = clampi(cb, 0, 255)
				dep[gi] = d
				gls[gi] = 0


# ------------------------------------------------------------- wall marks
## Mirrors engine.Renderer.wall_mark(): find the drawn wall face a hitscan hit
## and return the impact decal for it (null when nothing lines up).
func wall_mark(x: float, y: float, z: float, ax: float, ay: float, slope: float, distance: float):
	var w := level.walls
	var n := level.wall_count
	var best := -1
	var best_error := INF
	var best_t := 0.0
	for i in n:
		var o := i * WALL_STRIDE
		var ex := w[o + 2] - w[o]
		var ey := w[o + 3] - w[o + 1]
		var rx := w[o] - x
		var ry := w[o + 1] - y
		var den := ax * ey - ay * ex
		if absf(den) < 1e-6:
			continue
		var t := (rx * ey - ry * ex) / den
		var u := (rx * ay - ry * ax) / den
		if not (absf(t - distance) < .19 and t > .14 and u >= 0.0 and u <= 1.0):
			continue
		var height := z + t * slope
		if height <= w[o + 6] + .02 or height >= w[o + 7] - .02:
			continue
		if int(w[o + 4]) == level.tile_id("mirror"):
			continue
		var error := absf(t - distance)
		if error < best_error:
			best = i
			best_error = error
			best_t = t
	if best < 0:
		return null
	var o := best * WALL_STRIDE
	var ox := w[o + 2] - w[o]
	var oy := w[o + 3] - w[o + 1]
	var length := sqrt(ox * ox + oy * oy)
	var material := level.impact_surface(int(w[o + 4]))
	var kind := "stone" if material == "plaster" or material == "dirt" else material
	var mark := WallMark.new()
	mark.x = x + ax * best_t
	mark.y = y + ay * best_t
	mark.z = z + best_t * slope
	mark.ux = ox / length
	mark.uy = oy / length
	mark.image = "fx_hole_" + kind
	mark.radius = .051 if kind == "metal" else .060
	mark.material = material
	return mark


func _mark_band(a: int, b: int) -> void:
	for m: WallMark in _mark_list:
		_draw_mark(m, a, b)


func _draw_mark(m: WallMark, a: int, b: int) -> void:
	var rxv := m.x - cx
	var ryv := m.y - cy
	var d := rxv * fx + ryv * fy
	if d <= .19 or d >= 15.0:
		return
	var lateral := rxv * rx + ryv * ry
	var axis := m.ux * rx + m.uy * ry
	var fall := m.ux * fx + m.uy * fy
	if absf(axis * d - lateral * fall) < .08:
		return
	var extent: float = m.radius
	var half_w := WIDTH * .5 - a
	var left := half_w + (lateral - axis * extent) * FOCAL / (d - fall * extent)
	var right := half_w + (lateral + axis * extent) * FOCAL / (d + fall * extent)
	if absf(right - left) < .15:
		return
	var x0 := maxi(0, int(floor(minf(left, right))))
	var x1 := mini(b - a, int(ceil(maxf(left, right))))
	var half := FOCAL * extent / d
	var cy_screen := horizon - (m.z - cz) * FOCAL / d
	var y0 := maxi(0, int(cy_screen - half - 1.0))
	var y1 := mini(VIEW, int(cy_screen + half + 2.0))
	if x0 >= x1 or y0 >= y1:
		return
	var art := sprite_art(m.image)
	var sw: int = art["w"]
	var sh: int = art["h"]
	var data: PackedByteArray = art["data"]
	var light := light_at(d, 1.0)
	var w := out_w
	var lx0 := a - col0
	for y in range(y0, y1):
		var vv := (horizon - (y + .5)) * d / FOCAL + cz - m.z
		if absf(vv) > extent:
			continue
		var v := clampi(int((1.0 - vv / extent) * .5 * sh), 0, sh - 1)
		var drow := y * w
		for x in range(x0, x1):
			var proj := (x + .5 - half_w) / FOCAL
			var den := axis - proj * fall
			if absf(den) < 1e-12:
				continue
			var along := (proj * d - lateral) / den
			if absf(along) > extent:
				continue
			var dd := d + along * fall
			var gi := drow + lx0 + x
			if absf(dep[gi] - dd) >= .12 or glass[gi] != 0:
				continue
			var u := clampi(int((along / extent + 1.0) * .5 * sw), 0, sw - 1)
			var sp := (v * sw + u) * 4
			var alpha := data[sp + 3]
			if alpha <= 20:
				continue
			var mix := alpha / 255.0
			var o := gi * 3
			out[o] = clampi(int(round(out[o] * (1.0 - mix) + data[sp] * light * mix)), 0, 255)
			out[o + 1] = clampi(
				int(round(out[o + 1] * (1.0 - mix) + data[sp + 1] * light * mix)), 0, 255
			)
			out[o + 2] = clampi(
				int(round(out[o + 2] * (1.0 - mix) + data[sp + 2] * light * mix)), 0, 255
			)


# ----------------------------------------------------------- ground marks
func _ground_band(a: int, b: int) -> void:
	if _ground_list.is_empty():
		return
	var edge := maxf(absf(rays[a]), absf(rays[b - 1])) + .012
	var edge_scale := sqrt(1.0 + edge * edge)
	for m: GroundMark in _ground_list:
		var mx := m.x - cx
		var my := m.y - cy
		var reach := sqrt(m.reach * m.reach + m.width * m.width)
		var ahead := mx * fx + my * fy
		var side := mx * rx + my * ry
		if ahead + reach <= 0.0 or absf(side) - ahead * edge > reach * edge_scale:
			continue
		_draw_ground_mark(m, a, b)


func _draw_ground_mark(m: GroundMark, a: int, b: int) -> void:
	var radial := sqrt((m.x - cx) * (m.x - cx) + (m.y - cy) * (m.y - cy))
	if cz <= m.z + .015 or radial > 26.0:
		return
	var bounds := sqrt(m.reach * m.reach + m.width * m.width)
	var art := sprite_art(m.image)
	var sw: int = art["w"]
	var sh: int = art["h"]
	var data: PackedByteArray = art["data"]
	var cs := cos(m.angle)
	var sn := sin(m.angle)
	var w := out_w
	var lx0 := a - col0
	for r in VIEW:
		var sy := sy_rows[r]
		if sy <= 0.0:
			continue
		var distance := (cz - m.z) * FOCAL / maxf(sy, .015)
		if distance >= radial + bounds + 1.0:
			continue
		if distance <= maxf(0.0, (radial - bounds) * .76):
			continue
		var light := maxf(.63, light_at(distance, 1.12))
		var drow := r * w
		for i in range(a, b):
			var ray := rays[i]
			var wx := (cx - m.x) + distance * (fx + rx * ray)
			var wy := (cy - m.y) + distance * (fy + ry * ray)
			var u := (wx * cs + wy * sn) / m.reach
			var v := (-wx * sn + wy * cs) / m.width
			if absf(u) >= 1.0 or absf(v) >= 1.0:
				continue
			var gi := drow + lx0 + (i - a)
			if distance <= .015 or absf(distance - dep[gi]) >= .13:
				continue
			var au := clampi(int((u + 1.0) * .5 * sw), 0, sw - 1)
			var av := clampi(int((v + 1.0) * .5 * sh), 0, sh - 1)
			var sp := (av * sw + au) * 4
			var alpha := data[sp + 3]
			if alpha == 0:
				continue
			var cov := alpha / 255.0
			var o := gi * 3
			out[o] = clampi(int(round(out[o] * (1.0 - cov) + data[sp] * light * cov)), 0, 255)
			out[o + 1] = clampi(
				int(round(out[o + 1] * (1.0 - cov) + data[sp + 1] * light * cov)), 0, 255
			)
			out[o + 2] = clampi(
				int(round(out[o + 2] * (1.0 - cov) + data[sp + 2] * light * cov)), 0, 255
			)
