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


func render(
	player: Dictionary,
	sprites: Array,
	reflection_sprite,
	flash_value: float,
	marks: Array,
	ground_marks: Array
) -> PackedByteArray:
	render_begin(player, sprites, reflection_sprite, flash_value, marks, ground_marks)
	return render_end()


## The frame in steps, so the caller's own work overlaps the band threads':
## frame_begin() sets the camera and buffers up and has a band thread sort out
## the wall segments (the caller can list its sprites meanwhile);
## frame_sprites() takes the sprites and marks and starts the bands (the caller
## can draw its weapon and HUD meanwhile); render_end() waits and finishes.
var _pending: Array = []
var _begun_usec := 0
var _prepare_out := false


func render_begin(
	player: Dictionary,
	sprites: Array,
	reflection_sprite,
	flash_value: float,
	marks: Array,
	ground_marks: Array
) -> void:
	frame_begin(player, flash_value)
	frame_sprites(sprites, reflection_sprite, marks, ground_marks)


func frame_begin(player: Dictionary, flash_value: float) -> void:
	var started := Time.get_ticks_usec()
	var px: float = player["x"]
	var py: float = player["y"]
	var pz: float = player["eye"]
	var angle: float = player["view_angle"]
	var hz := (
		(VIEW / 2.0 + float(player["pitch"]) + float(player["bob"]) + float(player["sway"]))
		/ res_up
	)
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
	frame.resize(vw * (HEIGHT if detail == 0 and not layered else vh) * 3)
	if layered:
		over = PackedByteArray()
		over.resize(vw * vh * 3)
		over.fill(0)
		over_a = PackedByteArray()
		over_a.resize(vw * vh)
		over_a.fill(0)
		over_d = PackedFloat32Array()
		over_d.resize(vw * vh)
		over_d.fill(0.0)
		# Handed to a texture afterwards, so it must not be the array the band
		# threads wrote into last frame.
		pane_rgb = PackedByteArray()
		pane_rgb.resize(vw * vh * 3)
		wall_code = PackedInt32Array()
		wall_code.resize(vw * vh)
	depth = PackedFloat32Array()
	depth.resize(vw * vh)
	glass = PackedByteArray()
	glass.resize(vw * vh)
	pane_dist = PackedFloat32Array()
	pane_dist.resize(vw * vh)
	_pending = [px, py, pz, angle, hz, active]
	_scene_view(px, py, pz, angle, hz, 1, frame, vw, 0, vw, depth, glass, layered)
	if use_threads:
		_need_crew(1)
		Renderer._crew_job = _prepare.bind(active)
		_prepare_out = true
		_crew_go.post()
	else:
		_prepare(active)
	_begun_usec = Time.get_ticks_usec() - started


func frame_sprites(sprites: Array, reflection_sprite, marks: Array, ground_marks: Array) -> void:
	var started := Time.get_ticks_usec()
	if _prepare_out:
		_prepare_out = false
		_crew_done.wait()
	_pending.append_array([sprites, reflection_sprite, marks, ground_marks])
	_scene_draw(sprites, marks, ground_marks, 1, 0, vw, layered)
	_begun_usec += Time.get_ticks_usec() - started


func render_end() -> PackedByteArray:
	var started := Time.get_ticks_usec()
	_scene_end()
	var p := _pending
	_pending = []
	if layered:
		cam = {"x": p[0], "y": p[1], "z": p[2], "angle": p[3], "hz": p[4]}
		pane_any = false
		for i in vw:
			if pane_cols[i] != 0:
				pane_any = true
				break
	_mirror_pass(p[0], p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8], p[9])
	if detail != 0 and not layered:
		var small := Image.create_from_data(vw, vh, false, Image.FORMAT_RGB8, frame)
		small.resize(WIDTH, VIEW, Image.INTERPOLATE_NEAREST)
		frame = small.get_data()
		frame.resize(WIDTH * HEIGHT * 3)
	last_render_ms = (_begun_usec + Time.get_ticks_usec() - started) / 1000.0
	return frame


## A scene is set up (_scene_view), has its wall segments sorted out (_prepare),
## is drawn (_scene_draw, which may only start the band threads) and is
## finished (_scene_end).
func _scene_view(
	x: float,
	y: float,
	z: float,
	angle: float,
	hz: float,
	par: int,
	buf: PackedByteArray,
	buf_w: int,
	c0: int,
	c1: int,
	depth_buf: PackedFloat32Array,
	glass_buf: PackedByteArray,
	lay := false
) -> void:
	_lay = lay
	spr = over if lay else buf
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
	split = clampi(int(floorf(hz - .5)) + 1, 0, vh)
	for r in vh:
		sy_rows[r] = row_sy[r] - hz
	for i in vw:
		dir_x[i] = fx + rx * rays[i]
		dir_y[i] = fy + ry * rays[i]
	for i in vw:
		pane_cols[i] = 0


func _scene_draw(
	sprites: Array, marks: Array, ground_marks: Array, par: int, c0: int, c1: int, lay: bool
) -> void:
	_sprite_list = sprites
	_mark_list = marks
	_ground_list = ground_marks
	_warm_art()

	# Bands own disjoint columns, so walls, planes and overlays all band. Only
	# the main view is worth the threads (and keeps their balance, see
	# _cut_bands); a mirror's reflection is a narrow strip.
	if use_threads and (threads > 1 or lay) and par > 0 and c1 - c0 >= 96:
		_start_bands(c0, c1)
	else:
		_band(c0, c1)


## Wait for the scene's bands, then finish what follows them.
func _scene_end() -> void:
	if _bands_out > 0:
		_band_worker()
	for i in _bands_out:
		_crew_done.wait()
	if _bands_out > 0:
		_bands_out = 0
		Renderer._crew_job = Callable()
	if not _lay:
		_pane_wash()


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


func _warm_art() -> void:
	var count := _sprite_list.size()
	_spr_c0.resize(count)
	_spr_c1.resize(count)
	_spr_f.resize(count * SPR_F)
	_spr_i.resize(count * SPR_I)
	_spr_data.resize(count)
	var mirrored := parity < 0
	var edge := level.mirror_x
	var lights := level.light
	var areas := level.area
	var tint_max := tints.size() / 3 - 1
	for i in count:
		var s: Sprite = _sprite_list[i]
		var io := i * SPR_I
		_spr_i[io] = 0
		_spr_c0[i] = 0
		_spr_c1[i] = 0
		var sx := s.x
		var sy := s.y
		var tall := s.height
		var dx := sx - cx
		var dy := sy - cy
		if mirrored and sx < edge:
			continue
		var dist := dx * fx + dy * fy
		var limit := 51.0 if tall > 2.7 else 32.0
		if dist <= .13 or dist >= limit:
			continue
		var height := int(tall / dist * focal)
		if height < 2:
			continue
		var board := not is_nan(s.plane)
		var body := s.body
		var top := 0
		if not board:
			top = int(roundf(horizon - (s.z + tall - cz) / dist * focal))
			if top >= vh or (top + height <= 0 and not body):
				continue
		var image := s.image
		var art := sprite_art(image)
		var sw: int = art["w"]
		var sh: int = art["h"]
		var data: PackedByteArray = art["data"]
		_spr_data[i] = data
		_spr_i[io + 4] = sw
		_spr_i[io + 5] = sh
		if board:
			# A painted board is projected along its own axis (_draw_sign); there
			# are few enough of them that it stays a call.
			_spr_i[io] = 2
			_spr_c1[i] = vw
			continue
		var width := maxi(1, int(height * float(sw) / float(sh)))
		var centre := vw / 2.0 + (dx * rx + dy * ry) / dist * focal
		if body:
			top += body_offset(image, data, sw, sh, height)
		if top >= vh or top + height <= 0:
			continue
		var glow := s.glow
		var ci := level.cell(sx, sy)
		var light := 1.1 if glow else light_at(dist, lights[ci])
		if body:
			light = maxf(light, .58 - .021 * dist)
		if not glow:
			light = floorf(light * 32.0 + .5) / 32.0
		var ti := mini(maxi(1 if glow else areas[ci], 0), tint_max) * 3
		var hurt := s.hurt
		var see_through := s.translucent
		var fo := i * SPR_F
		_spr_f[fo] = centre
		_spr_f[fo + 1] = dist
		_spr_f[fo + 2] = light
		_spr_f[fo + 3] = tints[ti]
		_spr_f[fo + 4] = tints[ti + 1]
		_spr_f[fo + 5] = tints[ti + 2]
		_spr_f[fo + 6] = minf(.46, hurt / .18 * .44) if hurt > 0.0 else 0.0
		_spr_i[io] = 1
		_spr_i[io + 1] = height
		_spr_i[io + 2] = top
		_spr_i[io + 3] = width
		_spr_i[io + 6] = 12 if see_through else 100
		_spr_i[io + 7] = (1 if s.flip != mirrored else 0) | (2 if see_through else 0)
		# Its left column, decided once for the whole view. Rounded per band (as
		# it used to be) a sprite landing on an exact half column, which is every
		# odd-width sprite dead ahead, sat one column further right in the band
		# holding its left edge than in the bands after it. A half goes down, as
		# it did in all those other bands.
		var left := int(ceilf(centre - width / 2.0 - .5))
		_spr_i[io + 8] = left
		_spr_c0[i] = left
		_spr_c1[i] = left + width

	count = _mark_list.size()
	_mk_f.resize(count * MK_F)
	_mk_i.resize(count * MK_I)
	_mk_data.resize(count)
	for k in count:
		var m: WallMark = _mark_list[k]
		var io := k * MK_I
		_mk_i[io] = 0
		var rxv := m.x - cx
		var ryv := m.y - cy
		var d := rxv * fx + ryv * fy
		if d <= .19 or d >= 15.0:
			continue
		var lateral := rxv * rx + ryv * ry
		var ux := m.ux
		var uy := m.uy
		var axis := ux * rx + uy * ry
		var fall := ux * fx + uy * fy
		if absf(axis * d - lateral * fall) < .08:
			continue
		var extent: float = m.radius
		var mz := m.z
		var half := focal * extent / d
		var cy_screen := horizon - (mz - cz) * focal / d
		var y0 := maxi(0, int(cy_screen - half - 1.0))
		var y1 := mini(vh, int(cy_screen + half + 2.0))
		if y0 >= y1:
			continue
		var art := sprite_art(m.image)
		_mk_data[k] = art["data"]
		var fo := k * MK_F
		_mk_f[fo] = d
		_mk_f[fo + 1] = lateral
		_mk_f[fo + 2] = axis
		_mk_f[fo + 3] = fall
		_mk_f[fo + 4] = extent
		_mk_f[fo + 5] = (lateral - axis * extent) * focal / (d - fall * extent)
		_mk_f[fo + 6] = (lateral + axis * extent) * focal / (d + fall * extent)
		_mk_f[fo + 7] = light_at(d, 1.0)
		_mk_f[fo + 8] = mz
		_mk_i[io] = 1
		_mk_i[io + 1] = y0
		_mk_i[io + 2] = y1
		_mk_i[io + 3] = int(art["w"])
		_mk_i[io + 4] = int(art["h"])

	count = _ground_list.size()
	_gm_f.resize(count * GM_F)
	_gm_i.resize(count * GM_I)
	_gm_data.resize(count)
	for k in count:
		var m: GroundMark = _ground_list[k]
		var io := k * GM_I
		_gm_i[io] = 0
		var gx := m.x
		var gy := m.y
		var gz := m.z
		var reach := m.reach
		var width := m.width
		var mx := gx - cx
		var my := gy - cy
		var radial := sqrt((gx - cx) * (gx - cx) + (gy - cy) * (gy - cy))
		if cz <= gz + .015 or radial > 26.0:
			continue
		var angle := m.angle
		var art := sprite_art(m.image)
		_gm_data[k] = art["data"]
		var fo := k * GM_F
		_gm_f[fo] = cx - gx
		_gm_f[fo + 1] = cy - gy
		_gm_f[fo + 2] = cz - gz
		_gm_f[fo + 3] = radial
		_gm_f[fo + 4] = sqrt(reach * reach + width * width)
		_gm_f[fo + 5] = cos(angle)
		_gm_f[fo + 6] = sin(angle)
		_gm_f[fo + 7] = reach
		_gm_f[fo + 8] = width
		_gm_f[fo + 9] = mx * fx + my * fy
		_gm_f[fo + 10] = mx * rx + my * ry
		_gm_i[io] = 1
		_gm_i[io + 1] = int(art["w"])
		_gm_i[io + 2] = int(art["h"])
		# The mark is a rectangle on the floor; seen from in front, it lies between
		# the screen columns of its corners. (Any corner beside or behind the eye:
		# no shortcut, every column is tested as before.)
		var lo := 1e9
		var hi := -1e9
		for corner in 4:
			var along := reach if corner < 2 else -reach
			var across := width if corner % 2 == 0 else -width
			var px := mx + along * _gm_f[fo + 5] - across * _gm_f[fo + 6]
			var py := my + along * _gm_f[fo + 6] + across * _gm_f[fo + 5]
			var ahead := px * fx + py * fy
			if ahead <= .05:
				lo = -1e9
				hi = 1e9
				break
			var column := vw / 2.0 + (px * rx + py * ry) / ahead * focal
			lo = minf(lo, column)
			hi = maxf(hi, column)
		_gm_i[io + 3] = clampi(int(floorf(maxf(lo, -4.0))) - 2, 0, vw)
		_gm_i[io + 4] = clampi(int(ceilf(minf(hi, vw + 4.0))) + 3, 0, vw)


var _band_count := 0
var _band_next := 0
var _band_lock := Mutex.new()
## One band per band thread, cut where the work was even last frame.
var _band_edges := PackedInt32Array()
var _band_cost := PackedFloat32Array()
var _band_span := Vector2i(-1, -1)
## Band threads still drawing (0 when no band phase is running).
var _bands_out := 0
const BAND_SHARE := 2
## Band threads shared by every renderer; they sleep on a semaphore between frames.
static var _crew: Array[Thread] = []
static var _crew_go := Semaphore.new()
static var _crew_done := Semaphore.new()
static var _crew_job: Callable
static var _crew_quit := false


static func _crew_loop() -> void:
	while true:
		_crew_go.wait()
		if _crew_quit:
			return
		_crew_job.call()
		_crew_done.post()


## Let the band threads go; call once when the program is closing.
static func stop_crew() -> void:
	_crew_quit = true
	for _i in _crew.size():
		_crew_go.post()
	for t in _crew:
		t.wait_to_finish()
	_crew.clear()
	_crew_quit = false


## Explicit Thread workers instead of WorkerThreadPool: the pool reuses engine
## task slots shared with the rest of the engine, which made the band workers
## observe a half-swapped set of pass buffers. Each band is a fixed column
## range and bands never share pixels, so ordering does not matter.
## The crew is started once and kept: starting a thread per band per frame
## cost more than some bands took to draw, and far more in a browser.
func _need_crew(count: int) -> void:
	while _crew.size() < count:
		var t := Thread.new()
		t.start(Renderer._crew_loop)
		_crew.append(t)


func _start_bands(c0: int, c1: int) -> void:
	var crew := clampi((c1 - c0) / 16, 1, threads)
	# Two bands a thread, taken as they come: a thread that is held up keeps one
	# small band waiting instead of an eighth of the view, and the main thread
	# takes whatever is left when it gets to _scene_end().
	_band_count = crew * BAND_SHARE
	_cut_bands(c0, c1, _band_count)
	_band_next = 0
	_need_crew(crew)
	Renderer._crew_job = _band_worker
	_bands_out = crew
	for i in crew:
		_crew_go.post()


## Where each band starts. A frame waits for its slowest band, and equal widths
## are rarely equal work (a near wall or a crowd of sprites to one side), so the
## cuts move toward where each band would have taken the same time last frame.
func _cut_bands(c0: int, c1: int, crew: int) -> void:
	if _band_edges.size() != crew + 1 or _band_span != Vector2i(c0, c1):
		_band_span = Vector2i(c0, c1)
		_band_edges.resize(crew + 1)
		_band_cost.resize(crew)
		_band_cost.fill(0.0)
		for i in crew + 1:
			_band_edges[i] = c0 + (c1 - c0) * i / crew
		return
	var total := 0.0
	for i in crew:
		total += _band_cost[i]
	if total <= 0.0:
		return
	var share := total / crew
	var edges := _band_edges.duplicate()
	var k := 0
	var before := 0.0
	for i in range(1, crew):
		var want := share * i
		while k < crew - 1 and before + _band_cost[k] < want:
			before += _band_cost[k]
			k += 1
		var part := clampf((want - before) / maxf(_band_cost[k], .000001), 0.0, 1.0)
		var ideal := _band_edges[k] + (_band_edges[k + 1] - _band_edges[k]) * part
		# Half way there each frame: the timings are noisy.
		edges[i] = int(roundf((_band_edges[i] + ideal) * .5))
	for i in range(1, crew):
		edges[i] = maxi(edges[i], edges[i - 1] + 4)
	for i in range(crew - 1, 0, -1):
		edges[i] = mini(edges[i], edges[i + 1] - 4)
	_band_edges = edges


func _band_worker() -> void:
	while true:
		_band_lock.lock()
		var i := _band_next
		_band_next += 1
		_band_lock.unlock()
		if i >= _band_count:
			return
		var began := Time.get_ticks_usec()
		_band(_band_edges[i], _band_edges[i + 1])
		_band_cost[i] = (_band_cost[i] + (Time.get_ticks_usec() - began) / 1000.0) * .5


## One band: sky, wall spans, planes, then marks and sprites for its columns.
func _band(a: int, b: int) -> void:
	if profile:
		var t := Time.get_ticks_usec()
		for k in 6:
			if _lay and (k == 0 or k == 2):
				continue
			[_sky_band, _wall_band, _plane_band, _mark_band, _ground_band, _sprite_band][k].call(
				a, b
			)
			var now := Time.get_ticks_usec()
			pass_ms[k] += (now - t) / 1000.0
			t = now
		return
	if _lay:
		_wall_band(a, b)
	else:
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
	seg_order.clear()
	cov_top.resize(vw)
	cov_bot.resize(vw)
	cov_t.resize(vw)
	cov_top.fill(vh)
	cov_bot.fill(-1)
	cov_t.fill(0.0)
	glass_cols.resize(vw)
	glass_cols.fill(0)
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
		var m0 := vw / 2.0 + s0 / a0 * focal - .5
		var m1 := vw / 2.0 + s1 / a1 * focal - .5
		seg_c0[i] = maxi(col0, int(floorf(minf(m0, m1))) - 1)
		seg_c1[i] = mini(col1, int(ceilf(maxf(m0, m1))) + 2)
		if seg_c0[i] < seg_c1[i]:
			seg_order.append(int(minf(a0, a1) * 4096.0) * 65536 + i)
	seg_order.sort()


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
	row_off.resize(vh)
	for r in vh:
		row_off[r] = clampi(int(93.0 + sy_rows[r] * res_up * .95), 0, 115) * SKY_W * 3
	var w := out_w
	for r in vh:
		var s := row_off[r]
		var d := r * w * 3 + (a - col0) * 3
		for i in n:
			var o := s + col_off[i]
			out[d] = data[o]
			out[d + 1] = data[o + 1]
			out[d + 2] = data[o + 2]
			d += 3


# -------------------------------------------------------------- wall spans
## Every wall span of a band, nearest first. The segment loop is written out
## here rather than called per segment: a script call costs about ten times
## more while the other band threads are making calls of their own.
func _wall_band(band_a: int, band_b: int) -> void:
	var shade := shade_rows
	var depth_here := dep
	var glass_here := gls
	var tint_max := tints.size() / 3 - 1
	var w := out_w
	var lay := _lay
	var code_ := wall_code
	var phase := time - floorf(time / 6.1) * 6.1
	var flicker := phase > .87 and phase < 1.02
	for key in seg_order:
		var i := key & 65535
		var a := maxi(band_a, seg_c0[i])
		var b := mini(band_b, seg_c1[i])
		if a >= b:
			continue
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
			continue
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
		var ti := mini(maxi(area, 0), tint_max) * 3
		var glazing := material == tile_glazing
		var hub_wall := hub_fx and material == tile_hub_wall
		var hub_screen := hub_fx and material == tile_hub_screen
		var opaque := not glazing and not hub_screen
		var plain := not (glow or mirror or glazing or hub_wall or hub_screen)
		var mode := int(tile_mode[material]) if (wall_tiling and plain) else 0
		var along := sqrt(ex * ex + ey * ey) * 128.0
		var base_off := tile_base[material] * TILE_BYTES if mode == 2 else 0
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
			if mode == 1:
				uu = int(tex_u * along) & 127
			# A glazing tile keeps its frame and mullions opaque; only the pane
			# rectangles are held back and composited after the scene (the reference
			# drops them from the opaque layer's pixel list).
			var pane_ok := glazing and uu > 5 and uu < 122 and (uu < 62 or uu > 67)
			# light_at() and shade_step() written out: a script call costs several
			# times more when the band threads all make it at once.
			var lit := base_light / (1.0 + .102 * t)
			if lit < .19:
				lit = .19
			var sample_off := tile_off + uu * 3
			var step := clampi(int(floorf(lit * 32.0 + .5) / 32.0 * 32.0 + .5), 0, SHADE_STEPS - 1)
			var profile := (ti / 3) * PROFILE_COUNT
			var row_base := (profile + step) * SHADE_ROW
			var glow_base := (profile + PROFILE_GLOW) * SHADE_ROW
			var flick_base := (profile + PROFILE_FLICK) * SHADE_ROW
			var sy_lo := (cz - top) * focal / t
			var sy_hi := (cz - bottom) * focal / t
			if sy_lo > sy_hi:
				var swap := sy_lo
				sy_lo = sy_hi
				sy_hi = swap
			var r0 := maxi(0, int(ceilf(sy_lo + horizon - .5)))
			var r1 := mini(vh - 1, int(floorf(sy_hi + horizon - .5)))
			if r0 > r1:
				continue
			var cover_top := cov_top[c]
			var cover_bot := cov_bot[c]
			if r0 >= cover_top and r1 <= cover_bot and t >= cov_t[c]:
				continue
			var sy := float(r0) + .5 - horizon
			var t_inv := t / focal
			var row := r0
			var lx := c - col0
			var gi := row * w + lx
			var oi := gi * 3
			if plain and lay:
				# Most walls, layered: note the texel and the shade row for the shader.
				var code := material * 16384 + uu + ((profile + step) << WALL_ROW_SHIFT)
				var code_plain := code
				if mode == 2:
					code_plain = (
						tile_base[material] * 16384 + uu + ((profile + step) << WALL_ROW_SHIFT)
					)
				for _row in range(r0, r1 + 1):
					if t < depth_here[gi]:
						var wz := cz - sy * t_inv
						if wz >= bottom and wz <= top:
							var pv := 0
							var texel := code
							if mode == 0:
								pv = int((top - wz) / vspan * 128.0)
								if pv > 127:
									pv = 127
								elif pv < 0:
									pv = 0
							else:
								pv = int((TILE_ANCHOR - wz) * TILE_ROWS_PER_UNIT) & 127
								if mode == 2 and (wz < WINDOW_SILL or wz > WINDOW_HEAD):
									texel = code_plain
							code_[gi] = texel + pv * 128
							depth_here[gi] = t
							glass_here[gi] = 0
					sy += 1.0
					gi += w
				oi = gi * 3
				row = r1 + 1
			elif plain:
				# Most walls: no glow, glass, mesh or hub shadow to test per pixel.
				for _row in range(r0, r1 + 1):
					if t < depth_here[gi]:
						var wz := cz - sy * t_inv
						if wz >= bottom and wz <= top:
							var pv := 0
							var pi := sample_off
							if mode == 0:
								pv = int((top - wz) / vspan * 128.0)
								if pv > 127:
									pv = 127
								elif pv < 0:
									pv = 0
							else:
								pv = int((TILE_ANCHOR - wz) * TILE_ROWS_PER_UNIT) & 127
								if mode == 2 and (wz < WINDOW_SILL or wz > WINDOW_HEAD):
									pi = base_off + uu * 3
							pi += pv * TILE_W * 3
							out[oi] = shade[row_base + tiles[pi] * 3]
							out[oi + 1] = shade[row_base + tiles[pi + 1] * 3 + 1]
							out[oi + 2] = shade[row_base + tiles[pi + 2] * 3 + 2]
							depth_here[gi] = t
							glass_here[gi] = 0
					sy += 1.0
					gi += w
					oi += w * 3
				row = r1 + 1
			var hit_x := cx + t * dir_x[c]
			var hit_y := cy + t * dir_y[c]
			while row <= r1:
				var wall_z := cz - sy * t_inv
				if wall_z >= bottom and wall_z <= top and t < depth_here[gi]:
					var v := int(clampi(int((top - wall_z) / vspan * 128.0), 0, 127))
					# The road shed's hardware cloth: the open mesh is simply not
					# drawn, so whatever stands behind it shows through.
					if not (
						hub_screen
						and uu >= 7
						and uu <= 120
						and v >= 7
						and v <= 119
						and not ((uu >= 48 and uu <= 54) or (v >= 67 and v <= 73))
						and not (v > 95 and uu < 42 + v / 5)
						and (uu + v) % 17 >= 2
						and posmod(uu - v, 18) >= 2
					):
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
							if lay:
								code_[gi] = WALL_RGB
							if mirror:
								glass_cols[c] = 1
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
			if opaque and r1 - r0 > 2:
				# Every row strictly inside the span now holds this wall or a nearer one.
				if cover_top > cover_bot:
					cov_top[c] = r0 + 1
					cov_bot[c] = r1 - 1
					cov_t[c] = t
				elif r0 <= cover_bot and r1 >= cover_top:
					if r0 + 1 < cover_top:
						cov_top[c] = r0 + 1
					if r1 - 1 > cover_bot:
						cov_bot[c] = r1 - 1
					if t > cov_t[c]:
						cov_t[c] = t


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
	_plane_layer(level.roof_boxes, true, 0, split, a, b)
	_plane_layer(level.floor_boxes, false, split, vh, a, b)


func _plane_layer(boxes: Array, overhead: bool, row0: int, row1: int, a: int, b: int) -> void:
	if row1 <= row0:
		return
	var w := out_w
	var n := b - a
	var begin := PackedFloat32Array()
	var end := PackedFloat32Array()
	begin.resize(n)
	end.resize(n)
	var lit_scale := .77 if overhead else .94
	for entry: Array in boxes:
		var h: float = entry[0]
		if overhead:
			if h <= cz:
				continue
		elif h >= cz:
			continue
		var box: Vector4i = entry[1]
		var bx0 := float(box.x)
		var by0 := float(box.y)
		var bx1 := float(box.z)
		var by1 := float(box.w)
		var tscale := absf(h - cz) * focal
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
				var col2 := vw / 2.0 + (ddx * rx + ddy * ry) / d2 * focal
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
		var has_flows := not flows.is_empty()
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
			var last_ci := -1
			var tile := -1
			var step := 0
			var ti := 0
			var sbase := 0
			var tile_base := 0
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
				# Neighbouring pixels of a row mostly land in the same map cell:
				# its tile, light step and tint are worked out once per run.
				if ci != last_ci or has_caps:
					last_ci = ci
					tile = -1
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
					if tile >= 0:
						# light_at() and shade_step() inlined: the reference clamps the
						# quotient first, so distant surfaces stop at .19.
						var raw := (light_[ci] * lit_scale + flash) * falloff
						var shade := raw if raw > .19 else .19
						step = int(shade * 32.0 + .5)
						if step > SHADE_STEPS - 1:
							step = SHADE_STEPS - 1
						ti = area_[ci]
						if ti < 0:
							ti = 0
						elif ti > tint_max:
							ti = tint_max
						sbase = (ti * PROFILE_COUNT + step) * SHADE_ROW
						tile_base = tile * TILE_BYTES
				if tile < 0:
					continue
				var pu := int(wx * 128.0) & 127
				var pv := int(wy * 128.0) & 127
				if has_flows:
					for f in flows:
						if tile == f[0]:
							pv = (pv + f[1]) & 127
				var si := tile_base + pv * TILE_W * 3 + pu * 3
				var oi := gi * 3
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
		for r in vh:
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
	for c in vw:
		var hit := glass_cols[c] != 0
		if hit:
			# The column drew mirror glass at some point; check some of it survived.
			hit = false
			for r in vh:
				if glass[r * vw + c] != 0:
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
	rframe.resize(w * vh * 3)
	rdepth.resize(w * vh)
	rglass.resize(w * vh)
	var ghost := sprites.duplicate()
	if reflection_sprite != null:
		ghost.append(reflection_sprite)
	# _scene retargets the pass buffers, so keep the main pass's mask/frame.
	var main_glass := glass
	var main_frame := frame
	var keep_out := out
	var keep_dep := dep
	var keep_gls := gls
	var keep_pane_dist := pane_dist
	var keep_pane_rgb := pane_rgb
	if layered:
		# The reflection draws its own panes; the display shader still needs the
		# main pass's.
		pane_dist = PackedFloat32Array()
		pane_dist.resize(vw * vh)
		pane_rgb = PackedByteArray()
		pane_rgb.resize(vw * vh * 3)
	_scene_view(2.0 * level.mirror_x - x, y, z, PI - angle, hz, -1, rframe, w, a, b, rdepth, rglass)
	_prepare(segments)
	_scene_draw(ghost, marks, ground_marks, -1, a, b, false)
	_scene_end()
	out = keep_out
	dep = keep_dep
	gls = keep_gls
	pane_dist = keep_pane_dist
	pane_rgb = keep_pane_rgb
	for r in vh:
		var drow := r * vw
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
	return int(roundf(height * pivots[name]))


func _sprite_band(a: int, b: int) -> void:
	var n := _sprite_list.size()
	var first := _spr_c0
	var last := _spr_c1
	var fs := _spr_f
	var ns := _spr_i
	var w := out_w
	var out_ := spr
	var dep_ := dep
	var gls_ := gls
	var lay := _lay
	var cover_ := over_a
	var far_ := over_d
	var lx0 := a - col0
	var span := b - a
	var rows := vh
	# Each sprite's texture column for every screen column, worked out once per
	# sprite instead of once per pixel.
	var across := PackedInt32Array()
	across.resize(span)
	for i in n:
		if last[i] <= a or first[i] >= b:
			continue
		var io := i * SPR_I
		if ns[io] == 2:
			_draw_sign(_sprite_list[i], a, b, _spr_data[i], ns[io + 4], ns[io + 5])
			continue
		var fo := i * SPR_F
		var width := ns[io + 3]
		var left := ns[io + 8] - a
		var height := ns[io + 1]
		var top := ns[io + 2]
		var x0 := maxi(0, left)
		var x1 := mini(span, left + width)
		var y0 := maxi(0, top)
		var y1 := mini(rows, top + height)
		if x0 >= x1 or y0 >= y1:
			continue
		# Most sprites of a town are behind a wall. Where a column already holds
		# wall from the sprite's top row to its bottom row, all of it nearer than
		# the sprite (see cov_top in _wall_band), no pixel of that column can pass
		# the depth test below: trim such columns off both sides first.
		var dist := fs[fo + 1]
		var hidden := dist - .014
		var foot := y1 - 1
		while x0 < x1:
			var c := a + x0
			if hidden >= cov_t[c] and y0 >= cov_top[c] and foot <= cov_bot[c]:
				x0 += 1
			else:
				break
		while x0 < x1:
			var c := a + x1 - 1
			if hidden >= cov_t[c] and y0 >= cov_top[c] and foot <= cov_bot[c]:
				x1 -= 1
			else:
				break
		if x0 >= x1:
			continue
		var data: PackedByteArray = _spr_data[i]
		var sw := ns[io + 4]
		var sh := ns[io + 5]
		var threshold := ns[io + 6]
		var flip := (ns[io + 7] & 1) != 0
		var translucent := (ns[io + 7] & 2) != 0
		var light := fs[fo + 2]
		var tr := fs[fo + 3]
		var tg := fs[fo + 4]
		var tb := fs[fo + 5]
		var hurt_k := fs[fo + 6]
		for x in range(x0, x1):
			var sxi := (x - left) * sw / width
			across[x] = (sw - sxi - 1 if flip else sxi) * 4
		for y in range(y0, y1):
			var srow := (y - top) * sh / height * sw * 4
			var drow := y * w + lx0
			for x in range(x0, x1):
				var sp := srow + across[x]
				var alpha := data[sp + 3]
				if alpha <= threshold:
					continue
				var gi := drow + x
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
				if translucent:
					var cov := alpha / 255.0
					out_[o] = clampi(int(roundf(out_[o] * (1.0 - cov) + cr * cov)), 0, 255)
					out_[o + 1] = clampi(int(roundf(out_[o + 1] * (1.0 - cov) + cg * cov)), 0, 255)
					out_[o + 2] = clampi(int(roundf(out_[o + 2] * (1.0 - cov) + cb * cov)), 0, 255)
					if lay:
						var have := cover_[gi]
						if have == 0:
							far_[gi] = dist
						cover_[gi] = have + int((255 - have) * cov + .5)
				else:
					out_[o] = cr
					out_[o + 1] = cg
					out_[o + 2] = cb
					dep_[gi] = dist
					if lay:
						cover_[gi] = 255
						far_[gi] = dist
					else:
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
		for r in vh:
			var v := (s.z + s.height - cz + sy_rows[r] * d / focal) / s.height
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
				spr[o] = clampi(int(roundf(spr[o] * (1.0 - cov) + cr * cov)), 0, 255)
				spr[o + 1] = clampi(int(roundf(spr[o + 1] * (1.0 - cov) + cg * cov)), 0, 255)
				spr[o + 2] = clampi(int(roundf(spr[o + 2] * (1.0 - cov) + cb * cov)), 0, 255)
				if _lay:
					var have := over_a[gi]
					if have == 0:
						over_d[gi] = d
					over_a[gi] = have + int((255 - have) * cov + .5)
			else:
				spr[o] = clampi(cr, 0, 255)
				spr[o + 1] = clampi(cg, 0, 255)
				spr[o + 2] = clampi(cb, 0, 255)
				dep[gi] = d
				if _lay:
					over_a[gi] = 255
					over_d[gi] = d
				else:
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
	var count := _mark_list.size()
	if count == 0:
		return
	var fs := _mk_f
	var ns := _mk_i
	var half_w := vw * .5 - a
	var w := out_w
	var lx0 := a - col0
	var span := b - a
	var lay := _lay
	for k in count:
		var io := k * MK_I
		if ns[io] == 0:
			continue
		var fo := k * MK_F
		var left := half_w + fs[fo + 5]
		var right := half_w + fs[fo + 6]
		if absf(right - left) < .15:
			continue
		var x0 := maxi(0, int(floorf(minf(left, right))))
		var x1 := mini(span, int(ceilf(maxf(left, right))))
		if x0 >= x1:
			continue
		var y0 := ns[io + 1]
		var y1 := ns[io + 2]
		var sw := ns[io + 3]
		var sh := ns[io + 4]
		var data: PackedByteArray = _mk_data[k]
		var d := fs[fo]
		var lateral := fs[fo + 1]
		var axis := fs[fo + 2]
		var fall := fs[fo + 3]
		var extent := fs[fo + 4]
		var light := fs[fo + 7]
		var mz := fs[fo + 8]
		for y in range(y0, y1):
			var vv := (horizon - (y + .5)) * d / focal + cz - mz
			if absf(vv) > extent:
				continue
			var v := clampi(int((1.0 - vv / extent) * .5 * sh), 0, sh - 1)
			var drow := y * w
			for x in range(x0, x1):
				var proj := (x + .5 - half_w) / focal
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
				if lay and wall_code[gi] != WALL_RGB:
					# The wall here is still a texel and a shade row: colour it the
					# way the shader would have, then the mark can go over it.
					var code := wall_code[gi] & 0xFFFFFFFF
					var pi := (code & 0x1FFFFF) * 3
					var row_base := (code >> WALL_ROW_SHIFT) * SHADE_ROW
					out[o] = shade_rows[row_base + tiles[pi] * 3]
					out[o + 1] = shade_rows[row_base + tiles[pi + 1] * 3 + 1]
					out[o + 2] = shade_rows[row_base + tiles[pi + 2] * 3 + 2]
					wall_code[gi] = WALL_RGB
				out[o] = clampi(int(roundf(out[o] * (1.0 - mix) + data[sp] * light * mix)), 0, 255)
				out[o + 1] = clampi(
					int(roundf(out[o + 1] * (1.0 - mix) + data[sp + 1] * light * mix)), 0, 255
				)
				out[o + 2] = clampi(
					int(roundf(out[o + 2] * (1.0 - mix) + data[sp + 2] * light * mix)), 0, 255
				)


# ----------------------------------------------------------- ground marks
func _ground_band(a: int, b: int) -> void:
	var count := _ground_list.size()
	if count == 0:
		return
	var fs := _gm_f
	var ns := _gm_i
	var edge := maxf(absf(rays[a]), absf(rays[b - 1])) + .012
	var edge_scale := sqrt(1.0 + edge * edge)
	var w := out_w
	var lx0 := a - col0
	var lay := _lay
	for k in count:
		var io := k * GM_I
		if ns[io] == 0:
			continue
		var fo := k * GM_F
		var bounds := fs[fo + 4]
		var ahead := fs[fo + 9]
		if ahead + bounds <= 0.0 or absf(fs[fo + 10]) - ahead * edge > bounds * edge_scale:
			continue
		var from_x := fs[fo]
		var from_y := fs[fo + 1]
		var above := fs[fo + 2]
		var radial := fs[fo + 3]
		var cs := fs[fo + 5]
		var sn := fs[fo + 6]
		var reach := fs[fo + 7]
		var width := fs[fo + 8]
		var sw := ns[io + 1]
		var sh := ns[io + 2]
		var first := maxi(a, ns[io + 3])
		var last := mini(b, ns[io + 4])
		if first >= last:
			continue
		var data: PackedByteArray = _gm_data[k]
		for r in vh:
			var sy := sy_rows[r]
			if sy <= 0.0:
				continue
			var distance := above * focal / maxf(sy, .015)
			if distance >= radial + bounds + 1.0:
				continue
			if distance <= maxf(0.0, (radial - bounds) * .76):
				continue
			# light_at(distance, 1.12), written out (no script call in a band).
			var light := maxf(
				.63, floorf(maxf(.19, 1.12 / (1.0 + .102 * distance)) * 32.0 + .5) / 32.0
			)
			var drow := r * w
			for i in range(first, last):
				var ray := rays[i]
				var wx := from_x + distance * (fx + rx * ray)
				var wy := from_y + distance * (fy + ry * ray)
				var u := (wx * cs + wy * sn) / reach
				var v := (-wx * sn + wy * cs) / width
				if absf(u) >= 1.0 or absf(v) >= 1.0:
					continue
				var gi := drow + lx0 + (i - a)
				if distance <= .015:
					continue
				if lay:
					# The shader knows which floor shows here; only a wall in front
					# can be ruled out now.
					if dep[gi] <= distance - .13:
						continue
				elif absf(distance - dep[gi]) >= .13:
					continue
				var au := clampi(int((u + 1.0) * .5 * sw), 0, sw - 1)
				var av := clampi(int((v + 1.0) * .5 * sh), 0, sh - 1)
				var sp := (av * sw + au) * 4
				var alpha := data[sp + 3]
				if alpha == 0:
					continue
				var cov := alpha / 255.0
				var o := gi * 3
				spr[o] = clampi(int(roundf(spr[o] * (1.0 - cov) + data[sp] * light * cov)), 0, 255)
				spr[o + 1] = clampi(
					int(roundf(spr[o + 1] * (1.0 - cov) + data[sp + 1] * light * cov)), 0, 255
				)
				spr[o + 2] = clampi(
					int(roundf(spr[o + 2] * (1.0 - cov) + data[sp + 2] * light * cov)), 0, 255
				)
				if lay:
					var have := over_a[gi]
					over_a[gi] = have + int((255 - have) * cov + .5)
					over_d[gi] = -distance
