## Whether single-player moves every drawn frame. The game ticks 120 times a
## second (MainState.SIM_STEP) under a screen of 120 to 240 frames; this plays
## a scene through the front end's own frame (main.advance(), then
## net_draw_begin(), render() and net_draw_end(), as main.gd _process does)
## at a screen's rate with a little frame-time wobble, and records per drawn
## frame what the 3D view placed: the camera (place and turn), the gun's
## place on the canvas, every hand's model, the shots, the wreck pieces, the
## ragdolls' bones, the vehicle, the loose bits (casings) and the gibs.
## Headless it draws the frame with a 3D view made by hand (as
## stress_bench's check); in a window with the game's own.
##
## Per thing, a frame where it is moving (the mean of its steps over the 7
## frames round it, the two biggest left out, over MOVE_MIN) that it held still
## (a step under a quarter of the middle of the steps it took round it) is
## "held"; the table gives the share of
## moving frames each thing moved in, and the frames counted. Frames the game
## itself holds still (a kill's hitstop, a boss's entrance) are not counted.
##
##   godot --headless --path godot --script res://tools/frame_smooth.gd
##       [-- hz=120,144,240] [seconds=4] [scenes=walk,blast,ride] [ways=old,new]
##       [seed=1] [check]
##   godot --path godot --audio-driver Dummy --resolution 1280x800
##       --script res://tools/frame_smooth.gd -- ...   (the game's own view)
##
## `ways`: new draws between ticks (SoloBlend, src/solo_blend.gd); old turns
## it off on the same build (as v3.11.0 drew). Each scene prints the hash of
## the game it played (Replay.state_hash and the SIM snapshot) for each way:
## the draw must never change play, so old and new print the same.
## check (check_all): walk and blast at 144 Hz for 2 s each, new and old;
## every tracked thing moved in at least CHECK_MOVED of its moving frames,
## the turn on every frame the mouse turned, and play the same both ways;
## and the blend's rules on hickston's ticks (_rules): a tick drawn at its
## share of 0 or 1 is that tick as it stands, the view turned by all of the
## mouse not yet played (where the next shot goes), a jump drawn where it
## lands, a seat taken drawn in it, nothing blended in PHOTO MODE or under a
## FRAME LIMIT of 60, and the game put back to the bit after each frame.
## Prints FRAME SMOOTH OK.
extends SceneTree

## Slower than this a frame (cells; for the turn, of the view's forward
## vector) is not moving.
const MOVE_MIN := {
	"eye": .0015,
	"turn": .0015,
	"gun (pixels)": .05,
	"gun (exact)": .02,
	"hands": .0015,
	"far hands": .0015,
	"shots": .002,
	"wreck": .0015,
	"ragdolls": .0015,
	"vehicle": .0015,
	"bits": .0015,
	"gibs": .0015,
}
const ORDER := [
	"eye",
	"turn",
	"gun (exact)",
	"gun (pixels)",
	"hands",
	"far hands",
	"shots",
	"wreck",
	"ragdolls",
	"vehicle",
	"bits",
	"gibs",
]
## check: the least share of its moving frames a thing must move in (the gun
## on the canvas moves by whole pixels, and a far calm hand only on its own
## ticks, so their rows are left out).
const CHECK_MOVED := .97
const CHECK_SKIP := ["gun (pixels)", "far hands"]

var main
var hand_view: WorldView3D
var dice := RandomNumberGenerator.new()
var opts := {
	"hz": "120,144,240",
	"seconds": 4.0,
	"scenes": "walk,blast,ride",
	"ways": "old,new",
	"seed": 1.0,
}
var checking := false
var failures: Array = []
## The scene's own clock (s) and what it set up.
var t := 0.0
var scene_info := {}
## What net_draw_begin and net_draw_end took each frame of a scene (us), and
## the frame's own work (main.advance, those and main.render(); headless the
## view made by hand is left out).
var blend_us := PackedFloat64Array()
var work_us := PackedFloat64Array()


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg == "check":
			checking = true
			continue
		var parts := arg.split("=")
		if parts.size() == 2:
			opts[parts[0]] = parts[1] if parts[0] in ["hz", "scenes", "ways"] else float(parts[1])
	if checking:
		opts["hz"] = "144"
		opts["scenes"] = "walk,blast"
		opts["seconds"] = 2.0
		opts["ways"] = "old,new"
	CountyRecords.folder_override = OS.get_cache_dir().path_join("clmr-frame-smooth")
	main = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.touring = true
	Effects.enabled = true
	var windowed := DisplayServer.get_name() != "headless"
	print("FRAME SMOOTH  %s" % ("in a window" if windowed else "headless, a 3D view made by hand"))
	if checking:
		await _rules()
	for scene: String in str(opts["scenes"]).split(","):
		for hz_text: String in str(opts["hz"]).split(","):
			var hz := float(hz_text)
			var cols := []
			var heads := []
			var hashes := {}
			for way: String in str(opts["ways"]).split(","):
				var out: Dictionary = await _scene(scene, hz, way)
				if out.is_empty():
					continue
				cols.append(out)
				heads.append(way)
				hashes[way] = out["hash"]
			if cols.is_empty():
				continue
			print("\n%s at %d Hz (%s)" % [scene.to_upper(), hz, scene_info.get("where", "")])
			_table(heads, cols)
			var first: String = hashes.values()[0]
			for k in cols.size():
				print("  draw begin + end %-4s %s" % [heads[k], cols[k]["blend"]])
			for way: String in hashes:
				print("  play hash %-4s %s" % [way, hashes[way]])
				if hashes[way] != first:
					failures.append("%s %d Hz: play differs with the blend %s" % [scene, hz, way])
			if checking:
				_hold(scene, hz, heads, cols)
	for f: String in failures:
		print("  FAIL ", f)
	print(
		"FRAME SMOOTH OK" if failures.is_empty() else "FRAME SMOOTH FAILED (%d)" % failures.size()
	)
	if hand_view != null:
		hand_view.queue_free()
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


# ------------------------------------------------------------------ rules


func _rule(ok: bool, text: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", text])
	if not ok:
		failures.append(text)


## One frame as main.gd _process has it (no window input): advance, then the
## draw's begin, render and end; `look` is called between begin and end.
func _frame(dt: float, c: Game.Controls, look := Callable()) -> void:
	main.advance(dt, c)
	var aimed: Array = main.net_draw_begin(dt)
	main.render()
	if look.is_valid():
		look.call()
	main.net_draw_end(aimed)


static func _walking() -> Game.Controls:
	var c := Game.Controls.new()
	c.forward = 1.0
	c.strafe = .4
	return c


## The blend's rules on synthetic ticks (hickston, the player walking).
func _rules() -> void:
	print("\nRULES")
	main.options["frame_limit"] = 3
	var g := _level("hickston")
	var p := g.player
	var blend: SoloBlend = main.solo_blend
	var dt := 1.0 / 144.0
	for i in 40:
		_frame(dt, _walking())
	# Put back to the bit: the snapshot after a blended frame is the one
	# before it.
	var before := GameSnapshot.to_bytes(Replay.capture_quiet(g))
	var x0 := p.x
	var drawn := [0.0, 0.0]
	main.pending_turn = 0.0
	var aimed: Array = main.net_draw_begin(dt)
	drawn = [p.x, blend.last_share]
	main.render()
	main.net_draw_end(aimed)
	var after := GameSnapshot.to_bytes(Replay.capture_quiet(g))
	_rule(before == after and p.x == x0, "a blended frame puts the game back to the bit")
	var share: float = drawn[1]
	_rule(share > 0.0 and share < 1.0, "a frame between ticks is blended (share %.2f)" % share)
	_rule(absf(float(drawn[0]) - x0) > 1e-6, "the player is drawn short of the tick's place")
	# A tick boundary: a share of 1 is the tick as it stands, 0 the one before.
	var at_tick: float = main.solo_ticks
	blend.draw(g, main.solo_ticks, at_tick, null, 0.0, 0.0)
	var x_at := p.x
	blend.end()
	_rule(x_at == x0, "drawn at a share of 1 the player stands where the tick left him")
	# The mouse: the view turned by all of it not yet played.
	var turn := .123
	main.pending_turn = turn
	var a0 := p.angle
	var seen := [0.0]
	aimed = main.net_draw_begin(dt)
	seen[0] = p.angle
	main.net_draw_end(aimed)
	main.pending_turn = 0.0
	var off := absf(angle_difference(float(seen[0]), fposmod(a0 + turn, TAU)))
	_rule(off < 1e-9, "the view turns by all of the mouse not yet played (off %.9f rad)" % off)
	_rule(p.angle == a0, "and is put back after the frame")
	# The next tick turns by it: the crosshair is where the shot goes.
	var c := _walking()
	c.turn = turn
	main.advance(1.0 / 120.0 + 1e-6, c)
	off = absf(angle_difference(p.angle, float(seen[0])))
	_rule(off < 1e-9, "the next tick faces where that frame was drawn (off %.9f rad)" % off)
	# A jump (a respawn, a teleport) is drawn where it lands, from the frame
	# whose tick first has it.
	for i in 4:
		_frame(dt, _walking())
	p.x += 4.0
	var landed := [-1.0]
	var at_cur := func() -> void:
		var row: PackedFloat64Array = blend._cur[p]
		landed[0] = absf(p.x - row[1]) if blend.last_share < 1.0 else -1.0
	_frame(1.0 / 120.0 + 1e-6, _walking(), at_cur)
	var gap: float = landed[0]
	_rule(gap >= 0.0 and gap < 1e-9, "a jump of 4 cells is drawn where it lands, not slid")
	# PHOTO MODE and a FRAME LIMIT of 60 blend nothing.
	main.photo.on = true
	var shared := [1.0]
	_frame(dt, Game.Controls.new(), func() -> void: shared[0] = blend.last_share)
	main.photo.on = false
	_rule(float(shared[0]) < 0.0, "PHOTO MODE draws the game as it stands")
	main.options["frame_limit"] = 1
	_frame(dt, _walking())
	_frame(dt, _walking(), func() -> void: shared[0] = blend.last_share)
	_rule(float(shared[0]) < 0.0, "a FRAME LIMIT of 60 draws the game as it stands")
	main.options["frame_limit"] = 3
	# A seat taken is drawn in it, not slid into.
	var rides = g.features.get("vehicles")
	if rides != null and not rides.rides.is_empty():
		for i in 4:
			_frame(dt, Game.Controls.new())
		landed[0] = -1.0
		if rides.seat_in(p, 0):
			_frame(1.0 / 120.0 + 1e-6, Game.Controls.new(), at_cur)
		gap = landed[0]
		_rule(
			gap >= 0.0 and gap < 1e-9, "getting in the mower is drawn in the seat, not slid there"
		)
	main.game = null
	main.state = "title"


# ------------------------------------------------------------------ scenes


## One scene at `hz` drawn `way`; the recording's report.
func _scene(scene: String, hz: float, way: String) -> Dictionary:
	dice.seed = int(opts["seed"])
	_way(way)
	# FRAME LIMIT at this rate for the run (never saved: a tool's options
	# are not written).
	main.options["frame_limit"] = [30, 60, 120, 144, 240].find(int(hz))
	scene_info = {}
	var g: Game = call("_set_" + scene)
	if g == null:
		print("%s skipped: %s" % [scene, scene_info.get("why", "")])
		return {}
	var rec := Recording.new()
	blend_us.clear()
	work_us.clear()
	t = 0.0
	var settle := .5
	var end := settle + float(opts["seconds"])
	while t < end:
		var base := 1.0 / hz
		var dt := clampf(base + dice.randfn(0.0, base * .02), base * .5, base * 1.5)
		t += dt
		var c: Game.Controls = call("_steer_" + scene, g, dt)
		var w0 := Time.get_ticks_usec()
		main.advance(dt, c)
		if main.game != g:
			break
		var t0 := Time.get_ticks_usec()
		var aimed: Array = main.net_draw_begin(dt)
		var t1 := Time.get_ticks_usec()
		var r0 := Time.get_ticks_usec()
		main.render()
		var render_us := Time.get_ticks_usec() - r0
		_by_hand()
		if t >= settle:
			rec.frame(g, _view(), absf(c.turn) > 1e-6, g.hitstop > 0.0 or g.boss_hold > 0.0)
		var t2 := Time.get_ticks_usec()
		main.net_draw_end(aimed)
		if t >= settle:
			var w1 := Time.get_ticks_usec()
			blend_us.append(t1 - t0 + w1 - t2)
			work_us.append(w1 - w0 - (t2 - t1) + render_us)
		await process_frame
	var out := rec.report()
	var sorted := blend_us.duplicate()
	sorted.sort()
	var work := work_us.duplicate()
	work.sort()
	out["blend"] = (
		"%.3f ms median, %.3f p99; the frame's work (advance, draw begin, render, end) %.3f ms median"
		% [
			sorted[sorted.size() / 2] / 1000.0,
			sorted[int(sorted.size() * .99)] / 1000.0,
			work[work.size() / 2] / 1000.0
		]
	)
	out["hash"] = (
		"%08x %08x"
		% [
			Replay.state_hash(g) & 0xFFFFFFFF,
			hash(GameSnapshot.to_bytes(Replay.capture_quiet(g))) & 0xFFFFFFFF
		]
	)
	main.game = null
	main.state = "title"
	_way("new")
	return out


## The blend on (new) or off (old: as v3.11.0 drew).
func _way(way: String) -> void:
	SoloBlend.on = way != "old"


func _level(level_id: String) -> Game:
	main.start(level_id)
	var g: Game = main.game
	main.state = "play"
	g.cheats.god = true
	g.lessons = false
	g.barks.enabled = false
	g.message_until = 0.0
	g.district_until = 0.0
	return g


## Hickston's yard: running and turning among the hands, who are woken and
## come; a bolt thrown ahead now and then, the revolver fired.
func _set_walk() -> Game:
	var g := _level("hickston")
	var p := g.player
	var woke := 0
	var near: Array = g.enemies.duplicate()
	near.sort_custom(
		func(a: Enemy, b: Enemy) -> bool:
			return Vector2(a.x - p.x, a.y - p.y).length() < Vector2(b.x - p.x, b.y - p.y).length()
	)
	for e: Enemy in near:
		if woke >= 6 or not e.alive:
			continue
		e.dormant = false
		e.alerted = true
		woke += 1
	scene_info["where"] = "hickston, %d hands woken" % woke
	scene_info["next_bolt"] = .6
	return g


func _steer_walk(g: Game, dt: float) -> Game.Controls:
	var c := Game.Controls.new()
	c.forward = 1.0
	c.strafe = sin(t * .9) * .7
	c.running = true
	c.turn = (1.0 if sin(t * .45) >= 0.0 else -1.0) * 1.3 * dt
	c.look = sin(t * 1.3) * 6.0 * dt
	c.fire = fmod(t, .9) < .05
	if t >= float(scene_info["next_bolt"]):
		scene_info["next_bolt"] = t + .45
		var p := g.player
		g.launch(p.x, p.y, p.eye - .15, p.angle + .25, 7.0, "bolt", 0.0, false, 0, 1.6)
	return c


## Hickston's breakables: the densest cluster, three hands stood by it shot
## down one after another, then a stick of dynamite going off in its middle;
## watched from six cells, turning.
func _set_blast() -> Game:
	var g := _level("hickston")
	var breaks = g.features.get("breakables")
	if breaks == null:
		scene_info["why"] = "no breakables"
		return null
	var can: Array = []
	for i in breaks.pieces.size():
		var bp = breaks.pieces[i]
		if not bp.broken and str(bp.spec.get("pieces", "")) != "":
			can.append(Vector2(bp.x, bp.y))
	if can.is_empty():
		scene_info["why"] = "nothing breaks into pieces"
		return null
	var best := Vector2.ZERO
	var most := -1
	for at: Vector2 in can:
		var n := 0
		for other: Vector2 in can:
			if at.distance_to(other) < 4.0:
				n += 1
		if n > most:
			most = n
			best = at
	var w := g.world
	var stand := best
	for k in 32:
		var a := k * TAU / 32.0
		var at := best + Vector2(cos(a), sin(a)) * 6.0
		if (
			at.x > 1.0
			and at.y > 1.0
			and at.x < w.width - 1
			and at.y < w.height - 1
			and not w.blocked(at.x, at.y, .4)
			and w.visible(at.x, at.y, best.x, best.y, 1.2, 1.0)
		):
			stand = at
			break
	var p := g.player
	p.x = stand.x
	p.y = stand.y
	p.angle = atan2(best.y - stand.y, best.x - stand.x)
	p.floor_z = w.elevation(stand.x, stand.y)
	p.eye = .95 + p.floor_z
	var spots: Array = []
	for reach: float in [2.6, 3.0, 3.4, 3.8]:
		for k in 12:
			var a := k * TAU / 12.0
			var at := best + Vector2(cos(a), sin(a)) * reach
			var clear := not w.blocked(at.x, at.y, .3)
			for other: Vector2 in spots:
				clear = clear and other.distance_to(at) > .8
			if clear and spots.size() < 3:
				spots.append(at)
	var placed := 0
	var hands: Array = []
	for e: Enemy in g.enemies:
		if placed >= spots.size() or not e.alive or Enemy.BOSS_TITLES.has(e.kind):
			continue
		var at: Vector2 = spots[placed]
		e.x = at.x
		e.y = at.y
		hands.append(e)
		placed += 1
	scene_info["hands"] = hands
	scene_info["where"] = (
		"hickston, %d breakables round %.1f,%.1f, %d hands by it shot down"
		% [most, best.x, best.y, placed]
	)
	scene_info["blast_at"] = best
	scene_info["blown"] = false
	return g


func _steer_blast(g: Game, dt: float) -> Game.Controls:
	var c := Game.Controls.new()
	c.turn = sin(t * 1.1) * .5 * dt
	if t > 1.6 and not scene_info["blown"]:
		scene_info["blown"] = true
		var b: Vector2 = scene_info["blast_at"]
		var shot := Game.Shot.new(b.x, b.y, g.world.elevation(b.x, b.y) + .15, 0, 0, 0, "tnt")
		shot.owner = -1
		g.explode(shot)
	# The hands by it shot down one after another before it goes up: ragdolls.
	var hands: Array = scene_info["hands"]
	for k in hands.size():
		var e: Enemy = hands[k]
		if e.alive and t > .55 + k * .2:
			# Down to its last, so the round drops it whole (no overkill).
			e.hp = 1.0
			g.hit_point = Vector3.INF
			e.hurt(2.0, g, false, false, null, "revolver")
	return c


## Hickston's riding mower driven round, steering one way and the other.
func _set_ride() -> Game:
	var g := _level("hickston")
	var rides = g.features.get("vehicles")
	if rides == null or rides.rides.is_empty():
		scene_info["why"] = "no vehicle on hickston"
		return null
	if not rides.seat_in(g.player, 0):
		scene_info["why"] = "could not get in"
		return null
	scene_info["where"] = "hickston, the %s" % rides.rides[0].kind
	return g


func _steer_ride(_g: Game, dt: float) -> Game.Controls:
	var c := Game.Controls.new()
	c.forward = 1.0
	c.strafe = sin(t * .8) * .8
	c.turn = sin(t * .6) * .4 * dt
	return c


# ------------------------------------------------------------------ the view


## Headless the game draws no 3D view; one made by hand draws the frame it
## just listed (as stress_bench's check).
func _by_hand() -> void:
	if main.world_view != null or main.game == null:
		return
	if hand_view == null:
		hand_view = WorldView3D.new(main.game.art)
		main.add_child(hand_view)
	hand_view.frame(main.game)


func _view() -> WorldView3D:
	return main.world_view if main.world_view != null else hand_view


# ------------------------------------------------------------------ report


func _table(heads: Array, cols: Array) -> void:
	var head := ""
	for h: String in heads:
		head += ("%s moved" % h).lpad(14) + "frames".lpad(8)
	print("  %-16s%s" % ["", head])
	for name: String in ORDER:
		var line := ""
		var any := false
		for c: Dictionary in cols:
			var row: Array = c.get(name, [])
			if row.is_empty() or int(row[1]) == 0:
				line += "-".lpad(14) + "0".lpad(8)
			else:
				any = true
				line += ("%.1f%%" % (100.0 * float(row[0]) / float(row[1]))).lpad(14)
				line += str(row[1]).lpad(8)
		if any:
			print("  %-16s%s" % [name, line])


func _hold(scene: String, hz: float, heads: Array, cols: Array) -> void:
	var at := heads.find("new")
	if at < 0:
		return
	var c: Dictionary = cols[at]
	var seen := 0
	for name: String in ORDER:
		var row: Array = c.get(name, [])
		if row.is_empty() or int(row[1]) == 0 or CHECK_SKIP.has(name):
			continue
		seen += 1
		var share := float(row[0]) / float(row[1])
		if share < CHECK_MOVED:
			failures.append(
				(
					"%s %d Hz: %s moved in %.1f%% of its %d moving frames (at least %.0f%%)"
					% [scene, hz, name, share * 100.0, row[1], CHECK_MOVED * 100.0]
				)
			)
	var turned: Array = c.get("turn", [0, 0])
	if int(turned[1]) == 0:
		failures.append("%s %d Hz: the view never turned" % [scene, hz])
	if seen < 3:
		failures.append("%s %d Hz: only %d things seen moving" % [scene, hz, seen])


## What the view placed, frame by frame: per thing its places.
class Recording:
	extends RefCounted
	## name -> key -> [first frame, PackedVector3Array]
	var tracks := {}
	var frames := 0
	## Frames the mouse turned the view (the turn counted on those), and
	## frames the game itself held still (a kill's hitstop, a boss's entrance:
	## not counted).
	var turning := PackedByteArray()
	var stood := PackedByteArray()

	func frame(g: Game, view: WorldView3D, mouse: bool, still: bool) -> void:
		var i := frames
		frames += 1
		turning.append(1 if mouse else 0)
		stood.append(1 if still else 0)
		if view != null:
			var cam: Transform3D = view.camera.global_transform
			_note("eye", "", i, cam.origin)
			_note("turn", "", i, -cam.basis.z.normalized())
		var p := g.player
		if p.health > 0:
			var gait: float = p.motion * (.35 if p.air else 1.0) * g.bob_scale
			var gx: float = sin(p.walk_phase) * gait * 6.5 + p.sway * .7 + p.weapon_lag.x
			var gy: float = (
				(absf(cos(p.walk_phase)) * 5.2 - 2.2) * gait
				+ p.air * 5.0
				+ g.armory.lower * 88.0
				+ p.weapon_lag.y
			)
			_note("gun (exact)", "", i, Vector3(gx, gy, 0.0))
			var held: Vector2 = g.armory._hold(p, g.bob_scale, 0)
			_note("gun (pixels)", "", i, Vector3(held.x, held.y, 0.0))
		if view != null:
			for id: int in view.actors._shown:
				var av: ActorView = view.actors._shown[id]
				if not av.visible:
					continue
				if av.doll != null and not av._skeletons.is_empty():
					var sk: Skeleton3D = av._skeletons[0]
					var bone := mini(3, sk.get_bone_count() - 1)
					var at: Vector3 = av.global_transform * sk.get_bone_global_pose(bone).origin
					_note("ragdolls", str(id), i, at)
				elif av.doll == null:
					# A far, calm hand ticks only now and then (enemy_lod.gd):
					# counted apart.
					var e := instance_from_id(id) as Enemy
					var far := e != null and e.lod_since >= 0.0
					_note("far hands" if far else "hands", str(id), i, av.global_transform.origin)
			for s in view.wrecks._shown:
				var d = view.wrecks._shown[s]
				_note("wreck", str(s.get_instance_id()), i, d.node.global_transform.origin)
		for s: GameState.Shot in g.shots:
			if s.uid > 0:
				_note("shots", str(s.uid), i, Vector3(s.x, s.y, s.z))
		var rides = g.features.get("vehicles")
		if rides != null:
			for k in rides.rides.size():
				var r = rides.rides[k]
				_note("vehicle", str(k), i, Vector3(r.x, r.y, r.z))
		var debris = g.features.get("debris")
		if debris != null:
			for b in debris.bits:
				_note("bits", str(b.get_instance_id()), i, Vector3(b.x, b.y, b.z))
		for gib in g.gore_fx.gibs:
			_note("gibs", str(gib.get_instance_id()), i, Vector3(gib.x, gib.y, gib.z))

	func _note(name: String, key: String, i: int, at: Vector3) -> void:
		var rows: Dictionary = tracks.get(name, {})
		tracks[name] = rows
		var row: Array = rows.get(key, [])
		if row.is_empty() or int(row[0]) + (row[1] as PackedVector3Array).size() != i:
			# New, or seen again after a gap: a fresh track.
			if not row.is_empty():
				rows["%s@%d" % [key, int(row[0])]] = row
			row = [i, PackedVector3Array()]
			rows[key] = row
		var pts: PackedVector3Array = row[1]
		pts.append(at)
		row[1] = pts

	## name -> [frames it moved, frames it was moving].
	func report() -> Dictionary:
		var out := {}
		for name: String in tracks:
			var moved := 0
			var moving := 0
			var least: float = MOVE_MIN.get(name, .0015)
			for key: String in tracks[name]:
				var row: Array = tracks[name][key]
				var first: int = row[0]
				var pts: PackedVector3Array = row[1]
				var steps := PackedFloat64Array()
				for k in range(1, pts.size()):
					steps.append(pts[k].distance_to(pts[k - 1]))
				for k in range(3, steps.size() - 3):
					# Its pace: the mean of its 7 steps round this frame less the
					# two biggest (a jump, a blow's knock, a start from still,
					# leaves its neighbours alone; a step every other frame is
					# still a pace).
					var near := steps.slice(k - 3, k + 4)
					near.sort()
					var pace := 0.0
					for j in 5:
						pace += near[j]
					pace /= 5.0
					if pace < least:
						continue
					if name == "turn" and turning[first + k + 1] == 0:
						continue
					if stood[first + k] == 1 or stood[first + k + 1] == 1:
						continue
					moving += 1
					# Held: under a quarter of the middle of the steps it did
					# take round here (a start or a knock leaves it alone; a
					# step every other frame is held every other frame).
					var going: Array = []
					for step: float in near:
						if step > 1e-12:
							going.append(step)
					if steps[k] >= float(going[going.size() / 2]) * .25:
						moved += 1
			out[name] = [moved, moving]
		return out
