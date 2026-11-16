## The software look pass (rampage2.look_pass), moved out of game_view.gd and
## game_state.gd: the level's wash tint, the vignette and the ordered dither
## (build_grit()), the film grain, the lamp buzz and the blast lift over the
## view rows, with the brightness grade folded in (run(), banded across
## threads), and the drunk warp. Looks only. The game's `screen_look`
## (GameState) holds one; GameView works out this frame's numbers (gain,
## frame, blast) and calls it; with the GPU look the display shader reads the
## same numbers (main_state.gd).
class_name ScreenLook
extends RefCounted

const WIDTH := GameState.WIDTH
const VIEW := GameState.VIEW
const GRAIN_STRIDE := 936
const GRAIN_FRAMES := 6

## The grit and dither of each wash made so far (build_grit): wash -> [r, g,
## b, dither], only ever read after, so every game of that wash shares them.
static var _grits := {}

## rampage2.look_pass tables: wash tint, vignette and ordered dither.
var grit_r := PackedFloat32Array()
var grit_g := PackedFloat32Array()
var grit_b := PackedFloat32Array()
var dither := PackedFloat32Array()

var threads: Array[Thread] = []
var rows_per := 0
## This frame's lamp buzz, grain frame and blast lift (GameView._look_params).
var gain := 1.0
var frame := 0
var blast := 0.0
## The brightness table folded into the pass (null: none), and the grain.
var tone: Variant = null
var grain := PackedByteArray()


func build_grit(level_id: String) -> void:
	var wash_key := str(GameState.WASH.get(level_id, [255, 255, 255, 0]))
	var made: Variant = _grits.get(wash_key)
	if made != null:
		var kept: Array = made
		grit_r = kept[0]
		grit_g = kept[1]
		grit_b = kept[2]
		dither = kept[3]
		return
	# New arrays (a packed array in a Variant is shared: these are kept).
	grit_r = PackedFloat32Array()
	grit_g = PackedFloat32Array()
	grit_b = PackedFloat32Array()
	dither = PackedFloat32Array()
	var count := WIDTH * VIEW
	grit_r.resize(count)
	grit_g.resize(count)
	grit_b.resize(count)
	dither.resize(count)
	var wash: Array = GameState.WASH.get(level_id, [255, 255, 255, 0])
	var amount := _num(wash[3])
	var tr := _num(wash[0]) / 255.0
	var tg := _num(wash[1]) / 255.0
	var tb := _num(wash[2]) / 255.0
	var w := float(maxi(WIDTH - 1, 1))
	var h := float(maxi(VIEW - 1, 1))
	for y in VIEW:
		var ny := (float(y) / h - .5) * 2.0
		for x in WIDTH:
			var nx := (float(x) / w - .5) * 2.0
			var radius := sqrt(nx * nx + ny * ny) / 1.4142
			var vignette := 1.0 - .13 * pow(radius, 2.1)
			var i := y * WIDTH + x
			grit_r[i] = ((1.0 - amount) + tr * amount) * vignette
			grit_g[i] = ((1.0 - amount) + tg * amount) * vignette
			grit_b[i] = ((1.0 - amount) + tb * amount) * vignette
			dither[i] = (_num(GameState.BAYER[(x % 4) * 4 + (y % 4)]) / 16.0 - .5) * 6.0
	_grits[wash_key] = [grit_r, grit_g, grit_b, dither]


## The pass over the view rows of `c`, in `bands` bands (1: on this thread),
## with `grade_tone` (a brightness table, or null) folded in.
func run(c: Canvas, grain_bytes: PackedByteArray, grade_tone: Variant, bands: int) -> void:
	grain = grain_bytes
	tone = grade_tone
	# Row-banded across explicit threads. This pass is ~10 ms of per-pixel float
	# work at 50k pixels, so it is worth splitting. Each worker owns a private
	# output buffer for its own rows; only writes need a single owner, and a
	# shared buffer would make every worker detach on its first write (packed
	# arrays are copy-on-write). The bands are concatenated natively with
	# append_array, and the status rows below VIEW are carried over verbatim.
	var src := c.pixels
	var view_bytes := WIDTH * VIEW * 3
	if bands <= 1:
		var dst := src.slice(0)
		_rows(dst, src, 0, VIEW)
		c.pixels = dst
		return
	rows_per = ceili(float(VIEW) / bands)
	while threads.size() < bands:
		threads.append(Thread.new())
	for i in bands:
		var t: Thread = threads[i]
		if t.is_started():
			t.wait_to_finish()
		t.start(_worker.bind(src, i))
	# Each worker builds and returns its own buffer, so no band ever writes into
	# memory another thread can see; the main thread collects the results.
	var out := PackedByteArray()
	for i in bands:
		var part: PackedByteArray = threads[i].wait_to_finish()
		if part.size() > 0:
			out.append_array(part)
	if src.size() > view_bytes:
		out.append_array(src.slice(view_bytes))
	c.pixels = out


func _worker(src: PackedByteArray, slot: int) -> PackedByteArray:
	var y0 := slot * rows_per
	var y1 := mini(VIEW, y0 + rows_per)
	if y0 >= y1:
		return PackedByteArray()
	# Private buffer: one owner, so the band write cannot race with a detach.
	var part := PackedByteArray()
	part.resize((y1 - y0) * WIDTH * 3)
	_rows(part, src, y0, y1)
	return part


## Apply the look + tone passes to rows [y0, y1) of `src`, writing them into
## `dst` starting at its row 0. Both buffers are row-aligned to `y0`.
func _rows(dst: PackedByteArray, src: PackedByteArray, y0: int, y1: int) -> void:
	var grain_ := grain
	var grit_r_ := grit_r
	var grit_g_ := grit_g
	var grit_b_ := grit_b
	var dither_ := dither
	var tone_: Variant = tone
	var gain_ := gain
	var blast_add := blast
	var frame_index := frame
	# Yields: the reference runs look_pass over (0,0,WIDTH,VIEW) and then the
	# brightness grade over the same rectangle, so folding the two passes
	# together here produces identical pixels for half the memory traffic.
	var dst_row := 0
	var y := y0
	while y < y1:
		var i := y * WIDTH
		var o := dst_row
		var so := i * 3
		var gx := frame_index * VIEW + y
		var x := 0
		while x < WIDTH:
			var add := float(int(grain_[gx]) - 2) + blast_add + dither_[i]
			var r := clampi(int(float(src[so]) * (grit_r_[i] * gain_) + add), 0, 255)
			var g := clampi(int(float(src[so + 1]) * (grit_g_[i] * gain_) + add), 0, 255)
			var b := clampi(int(float(src[so + 2]) * (grit_b_[i] * gain_) + add), 0, 255)
			if tone_ != null:
				dst[o] = tone_[r]
				dst[o + 1] = tone_[g]
				dst[o + 2] = tone_[b]
			else:
				dst[o] = r
				dst[o + 1] = g
				dst[o + 2] = b
			gx += GRAIN_STRIDE
			i += 1
			o += 3
			so += 3
			x += 1
		dst_row += WIDTH * 3
		y += 1


## rampage2.drunk_warp: per-row sine shear, ghost double image, amber tint.
static func drunk_warp(c: Canvas, drunk: float, clock: float) -> void:
	if drunk < 38.0:
		return
	var strength := minf(1.0, (drunk - 38.0) / 62.0)
	var width := WIDTH
	var source := PackedByteArray()
	source.resize(width * VIEW * 3)
	var shift := PackedInt32Array()
	shift.resize(VIEW)
	for y in VIEW:
		shift[y] = roundi(sin(y * .16 + clock * 3.1) * (1.0 + 3.4 * strength))
	var pix := c.pixels
	for y in VIEW:
		var row := y * width * 3
		var offset := shift[y]
		for x in width:
			var sx := posmod(x + offset, width)
			var sp := row + sx * 3
			var dp := row + x * 3
			source[dp] = pix[sp]
			source[dp + 1] = pix[sp + 1]
			source[dp + 2] = pix[sp + 2]
	var ghost_dx := int(2 + 4 * strength)
	if sin(clock * 1.7) <= 0.0:
		ghost_dx = -ghost_dx
	var mix := .30 * strength
	for y in VIEW:
		var row := y * width * 3
		for x in width:
			var gx := posmod(x - ghost_dx, width)
			var gp := row + gx * 3
			var dp := row + x * 3
			var r := float(source[dp]) * (1.0 - mix) + float(source[gp]) * mix
			var g := float(source[dp + 1]) * (1.0 - mix) + float(source[gp + 1]) * mix
			var b := float(source[dp + 2]) * (1.0 - mix) + float(source[gp + 2]) * mix
			pix[dp] = clampi(int(r * (1.0 + .06 * strength)), 0, 255)
			pix[dp + 1] = clampi(int(g), 0, 255)
			pix[dp + 2] = clampi(int(b * (1.0 - .10 * strength)), 0, 255)


## float() of a number read from a list or dictionary, typed.
static func _num(v: Variant) -> float:
	return v
