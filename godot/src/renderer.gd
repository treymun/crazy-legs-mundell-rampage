## Software renderer, first translated from the Python game's engine.py.
##
## A 320x156 raycaster with multiple wall heights, per-height floor/ceiling
## planes, sprites, signs, wall marks and a planar mirror pass. Its pictures
## are guarded by tools/picture_check.gd's reference images; it no longer has
## to match the Python original.
##
## Walls are drawn as projected vertical spans with a depth buffer rather than
## as a per-column ray matrix, but the winning hit per pixel is identical.
## Columns are split into bands for the thread pool; bands never share pixels.
class_name Renderer
extends RenderSprites


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
## Crew threads still projecting walls (frame_begin).
var _prepare_out := 0


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
	_block_walls(level.active_base(at_hub), at_hub)
	_prepare_hub(at_hub)
	# The software view: fresh, exclusively-owned pass buffers every frame. PackedArray writes are
	# copy-on-write, and Godot's detach is not safe when several band threads
	# write into storage that any other reference (the previous frame handed to
	# Image.set_data, the canvas) still holds: workers would intermittently see
	# a zero-length array. Allocating per frame keeps every buffer single-owner,
	# and returning this one directly is then safe because the next frame
	# allocates a different array instead of rewriting it.
	if layered and frame.size() == vw * vh * 3 and over_d.size() == vw * vh:
		# Layered, nothing outside the renderer keeps these: scene_layers.gd copies
		# what it sends. So they are kept from frame to frame, and only what is
		# read before it is written starts the frame cleared: the overlay (blended
		# into), the span counts, and (in _scene_view) the distances and the glass.
		# The walls, wall codes and panes are read only where this frame's
		# distances say they were drawn.
		over.fill(0)
		over_a.fill(0)
		over_d.fill(0.0)
		span_f.fill(0.0)
		span_n.fill(0)
	else:
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
			pane_rgb = PackedByteArray()
			pane_rgb.resize(vw * vh * 3)
			wall_code = PackedInt32Array()
			wall_code.resize(vw * vh)
			span_f = PackedFloat32Array()
			span_f.resize(vw * (SPAN_K * 2 + 1) * 4)
			span_n = PackedByteArray()
			span_n.resize(vw)
		depth = PackedFloat32Array()
		depth.resize(vw * vh)
		glass = PackedByteArray()
		glass.resize(vw * vh)
		pane_dist = PackedFloat32Array()
		pane_dist.resize(vw * vh)
	_pending = [px, py, pz, angle, hz, active]
	_scene_view(px, py, pz, angle, hz, 1, frame, vw, 0, vw, depth, glass, layered)
	# The crew projects the walls (and packs them for the shader) a chunk at a
	# time while the caller lists its sprites; frame_sprites() sorts them.
	_prepare_begin(active)
	_prep_open = true
	if use_threads and _prep_chunks > 0:
		# Three chunks a thread at least: waking a thread costs more than a
		# small chunk, most of all in a browser.
		var crew := clampi(_prep_chunks / 3, 1, threads)
		_need_crew(crew)
		Renderer._crew_job = _prepare_worker
		_prepare_out = crew
		for i in crew:
			_crew_go.post()
	else:
		for k in _prep_chunks:
			_prepare_chunk(k)
	_begun_usec = Time.get_ticks_usec() - started


func frame_sprites(sprites: Array, reflection_sprite, marks: Array, ground_marks: Array) -> void:
	var started := Time.get_ticks_usec()
	# The sprites and marks are worked out while the wall segments are still
	# being sorted out on a band thread (they share no buffer), then the bands go.
	_sprite_list = sprites
	_mark_list = marks
	_ground_list = ground_marks
	_warm_art()
	for i in _prepare_out:
		_crew_done.wait()
	_prepare_out = 0
	if _prep_open:
		_prep_open = false
		_prepare_end()
	if layered:
		_cpu_columns()
		# The blocks' lists for the shader are a job for the crew beside the bands.
		_fill_due = gpu_walls
	_pending.append_array([sprites, reflection_sprite, marks, ground_marks])
	_scene_draw(sprites, marks, ground_marks, 1, 0, vw, layered, false)
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
	pane_cols.fill(0)


func _scene_draw(
	sprites: Array,
	marks: Array,
	ground_marks: Array,
	_par: int,
	c0: int,
	c1: int,
	lay: bool,
	warm := true
) -> void:
	_sprite_list = sprites
	_mark_list = marks
	_ground_list = ground_marks
	if warm:
		_warm_art()

	# Bands own disjoint columns, so walls, planes and overlays all band. A
	# mirror's reflection bands too when it is wide (standing in front of the
	# bar mirror it is most of the view, and on one thread it tripled the
	# frame); it keeps its own band balance (_mirror_pass).
	if use_threads and (threads > 1 or lay) and c1 - c0 >= 96:
		_start_bands(c0, c1)
	else:
		if _fill_due:
			_fill_due = false
			_fill_lists()
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


var _band_count := 0
var _band_next := 0
## Jobs taken before the bands (0 or 1: the shader's wall lists).
var _band_jobs := 0
var _band_lock := Mutex.new()
## One band per band thread, cut where the work was even last frame.
var _band_edges := PackedInt32Array()
var _band_cost := PackedFloat32Array()
var _band_span := Vector2i(-1, -1)
## The reflection's own cuts and timings, swapped in while it draws.
var _mirror_edges := PackedInt32Array()
var _mirror_cost := PackedFloat32Array()
var _mirror_span := Vector2i(-1, -1)
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
	# Job 0 fills the shader's wall lists when the main view has them to fill
	# (render_surfaces.gd _fill_lists); the bands follow.
	_band_jobs = 1 if _fill_due else 0
	_fill_due = false
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
		if i < _band_jobs:
			_fill_lists()
			continue
		i -= _band_jobs
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
			if _lay and (k == 0 or k == 2 or k == 5 and gpu_sprites):
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
	if not (_lay and gpu_sprites):
		_sprite_band(a, b)


# ------------------------------------------------------------------ mirror


## Trade the main view's band cuts for the reflection's (and back), so each
## keeps balancing against its own last frame.
func _swap_balance() -> void:
	var edges := _band_edges
	var cost := _band_cost
	var span := _band_span
	_band_edges = _mirror_edges
	_band_cost = _mirror_cost
	_band_span = _mirror_span
	_mirror_edges = edges
	_mirror_cost = cost
	_mirror_span = span


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
	_swap_balance()
	_scene_draw(ghost, marks, ground_marks, -1, a, b, false)
	_scene_end()
	_swap_balance()
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
