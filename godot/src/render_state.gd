## The software renderer's state, its shade tables and the small helpers its
## passes share. renderer.gd is a chain of layers, each extending the one
## before: RenderState -> RenderSurfaces -> RenderSprites -> Renderer. A layer
## only calls functions of its own or of the layers below it. The band loops
## stay on one object, so they keep reading their own fields at full speed.
class_name RenderState
extends RefCounted

const WIDTH := 320
const VIEW := 156
const HEIGHT := 200
const FOCAL := 230.0
const SKY_W := 512
## The size the view is actually drawn at. HIGH is the full 320x156; LOW draws
## half of that each way and doubles it up, for machines (and browsers without
## threads) that cannot keep up. Everything downstream still sees 320x200.
var vw := WIDTH
var vh := VIEW
var focal := FOCAL
var detail := 0
var res_up := 1.0
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
## Plain wall materials repeat up and along a wall at a fixed size instead of
## being stretched over whatever height the wall has (as Build tiles them).
## Tiles composed for a whole wall (signs, doors, fences, banded sheds) are not
## in this list and still stretch. A window tile in one of these materials is
## the window laid over the repeating wall at a fixed height.
const TILED := [
	"wood",
	"barn",
	"tin",
	"brick",
	"plaster",
	"cinder",
	"office_wall",
	"quarry_face",
	"hedgerow",
	"tile",
	"quarry_shed",
	"mill_log",
	"fascia"
]
const TILE_ROWS_PER_UNIT := 100.0
const TILE_ANCHOR := 1.96
const WINDOW_SILL := 1.0
const WINDOW_HEAD := 1.68
var wall_tiling := true
var tile_mode := PackedByteArray()
var tile_base := PackedInt32Array()
## Milliseconds the last render() took; read by tools/bench.gd.
var last_render_ms := 0.0
## With profile on (single thread), time per pass: sky, walls, planes, marks, ground marks, sprites.
var profile := false
var pass_ms: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var threads := 8
var plane_cull := true

## Layered drawing, for the display shader (palette.gdshader). The sky, the
## floors and the ceilings are left to the graphics card; walls and wall marks
## go to `frame` with their distances in `depth`; sprites and ground marks go to
## an overlay the shader lays over whichever surface turns out to be in front.
## Off, everything is composed here exactly as before (tools, the mirror).
var layered := false
var _lay := false
## The overlay: premultiplied colour, coverage, and the distance that decides
## whether a floor hides it (above zero a sprite, below zero a ground mark).
var over := PackedByteArray()
var over_a := PackedByteArray()
var over_d := PackedFloat32Array()
## Where sprites and ground marks are blended: the frame, or the overlay.
var spr := PackedByteArray()
## Layered walls. A plain wall pixel is not coloured here: the shader is handed
## which texel it shows (tile * 16384 + row * 128 + column, in the low 21 bits)
## and which shade row lights it (tint * PROFILE_COUNT + step, above them), and
## looks the colour up. That is one write per pixel in place of three texel
## reads, three table reads and three writes. A pixel that carries WALL_RGB
## instead has its colour in `frame` (signs that glow, the mirror, the hub's
## shadowed walls, anything a wall mark was blended into).
var wall_code := PackedInt32Array()
const WALL_RGB := -1
const WALL_ROW_SHIFT := 21
## Layered walls, whole spans. Most plain walls are not even coded pixel by
## pixel: a wall's run down one column is handed to the shader as one span,
## and the shader finds, for every pixel, the nearest span that covers it.
## Up to SPAN_K spans a column; past that a column falls back to the pixel
## codes above. Two RGBA float texels a span, laid out as an image of
## vw x (SPAN_K * 2): span k of column c is at (c, 2k) and (c, 2k + 1):
##   distance, bottom, top, first row * 256 + last row;
##   tile, tile outside the window band (mode 2), u * 4 + mode, shade row.
## Row 2 * SPAN_K holds each column's span count, for the shader.
const SPAN_K := 12
var span_f := PackedFloat32Array()
var span_n := PackedByteArray()
## Layered sprites. The shader draws the sprites and painted boards too, in
## list order and with the same depth tests: gpu_spr holds four RGBA float
## texels a sprite (a row of an image 4 wide), and the art goes in slots of
## a texture array of ART_SIZE squares (render_sprites.gd _gpu_sprite).
## When a frame has more sprites than GPU_SPRITES, or more different
## pictures than ART_SLOTS, the renderer draws them itself, as before.
const GPU_SPRITES := 256
const ART_SLOTS := 96
const ART_SIZE := 256
var gpu_spr := PackedFloat32Array()
var gpu_spr_n := 0
var gpu_sprites := false
## Art slot bookkeeping: picture name -> slot, each slot's picture and the
## frame it was last used, and the slots waiting to be uploaded (slot -> art;
## scene_layers.gd empties it).
var art_slot := {}
var art_name: Array = []
var art_used := PackedInt64Array()
var art_dirty := {}
var _art_frame := 0
## True when this frame's main pass drew window panes (pane_rgb / pane_dist).
var pane_any := false
## The main pass's camera, kept because the mirror pass reuses the members.
var cam := {}

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
## Wall segments on screen, nearest first, and per column the rows already
## filled by opaque wall (with the farthest depth among them): a later, farther
## span that falls wholly inside is skipped before its pixel loop.
var seg_order := PackedInt64Array()
var _spr_c0 := PackedInt32Array()
var _spr_c1 := PackedInt32Array()
var cov_top := PackedInt32Array()
var cov_bot := PackedInt32Array()
var cov_t := PackedFloat32Array()
var glass_cols := PackedByteArray()
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
	# One band thread per spare core, guessing two logical processors to a core,
	# and never more than six. A frame waits for its slowest band, so a thread
	# too many is worse than one too few: with more threads at work than cores
	# awake to run them (measured on a 16c/32t laptop on its balanced power
	# plan: the main thread and anything past six or seven band threads) one is
	# always held up and the frame with it.
	threads = clampi(OS.get_processor_count() / 2 - 1, 1, 6)
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
	var names := level.tile_names
	tile_mode.resize(names.size())
	tile_base.resize(names.size())
	for i in names.size():
		var tile_name := String(names[i])
		tile_base[i] = -1
		if TILED.has(tile_name):
			tile_mode[i] = 1
		elif tile_name.ends_with("_win") or tile_name.ends_with("_lit"):
			var plain_name := tile_name.substr(0, tile_name.length() - 4)
			if TILED.has(plain_name) and level.tile_id(plain_name) >= 0:
				tile_mode[i] = 2
				tile_base[i] = level.tile_id(plain_name)
	_build_shade_rows()


## Choose HIGH (0) or LOW (1) view detail.
func set_detail(level_of_detail: int) -> void:
	detail = clampi(level_of_detail, 0, 1)
	vw = WIDTH >> detail
	vh = VIEW >> detail
	focal = FOCAL / (1 << detail)
	res_up = float(VIEW) / vh
	for i in vw:
		rays[i] = (i + .5 - vw / 2.0) / focal


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


## What each band needs to draw this frame's sprites and marks, worked out once
## on the main thread. A band thread then reads nothing but packed arrays:
## reading a field of another object, or calling a script function, costs five
## to eleven times more while the other band threads are doing the same, and
## that was most of what a band spent on anything but pixels. It also keeps
## `art_cache` and `pivots` (plain Dictionaries, not safe to fill from two
## threads) on one thread.
const SPR_F := 7
const SPR_I := 9
const MK_F := 9
const MK_I := 5
const GM_F := 11
const GM_I := 5
## centre column, distance, light, tint r g b, hurt wash
var _spr_f := PackedFloat64Array()
## kind (0 skip, 1 sprite, 2 sign), height, top, width, art w, art h, alpha cut,
## 1 flip | 2 translucent, left column
var _spr_i := PackedInt32Array()
var _spr_data: Array = []
## distance, lateral, axis, fall, extent, left, right, light, z
var _mk_f := PackedFloat64Array()
## live, first row, last row + 1, art w, art h
var _mk_i := PackedInt32Array()
var _mk_data: Array = []
## eye - x, eye - y, eye height above it, radial, bounds, cos, sin, reach, width, ahead, side
var _gm_f := PackedFloat64Array()
## live, art w, art h, first column it can touch, last column + 1
var _gm_i := PackedInt32Array()
var _gm_data: Array = []

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
	return int(roundf(height * pivots[name]))


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
