## The active bodies' steps two and three on a living man (pass 15, T11
## ACTIVE BODIES; looks only): LiveBody's rig, muscles and balance, in the
## level's real shape, with behaviours that set its targets, stiffness and
## constraints each frame before it steps. Nothing here is played back: each
## behaviour only says where a limb tries to go and how hard (a target and a
## tone) or holds a ball to a point (a pin); the rig's masses, links, joint
## stops, gravity and contacts do the rest.
##
## - **The world.** Each ball stands on the floor really under it (a stair's
##   tread, a deck, a ramp: Tumble.floor_at) and keeps out of walls, slabs'
##   sides and rails (Ragdoll._walls), so a foot steps down a stair, a shin
##   catches on a rail and a body carried over one goes over head first.
## - **Bracing.** Going over (play's down, pitched, or the torso tipping past
##   `active_tip`), the arms swing out toward where the chest will land (the
##   point the torso falls onto about the feet), stiffened (`active_brace`);
##   the head is held up off the fall (`active_head_guard`). A hand that
##   reaches the floor is held there (the fall lands on it, `active_brace_hold`
##   seconds) and the arms then give. `braced_at` and `landed_at` say when.
## - **Windmilling.** Reeling fast (`active_mill_from` map units a second),
##   the arms go round in the body's plane the way he falls (`active_mill_rate`
##   turns a second): their swing pushes back on the torso.
## - **Grabbing.** Reeling, a rail, fence, crate or car edge in reach
##   (BodyPlay.edge; play's own point when play says he held on): the near
##   hand goes to it and is pinned there (a constraint: the body hangs on it),
##   let go after `active_grab_hold` seconds or when the arm is pulled past
##   `active_grab_force` of its length (play's body went on without it).
##   `grab_log` keeps each [hand, from, to, why].
## - **Drunk** (`drunk`: the drunk coot, anyone on shine): always reeling,
##   the feet put down only by the balance controller, which looks late
##   (`active_drunk_late` seconds between looks) and steps too far
##   (`active_drunk_over` past the capture point, `active_drunk_noise` off);
##   the arms out, the ankle weak, a sway now and then from his own dice.
##
## Its own dice (seeded by the view), never game.rng; it never writes play.
class_name ActiveBody
extends LiveBody

## Numbers (effects.cfg [ragdoll] active_*: looks).
static var TIP: float = Effects.RAGDOLL.get("active_tip", .75)
static var BRACE: float = Effects.RAGDOLL.get("active_brace", 2.0)
static var BRACE_HOLD: float = Effects.RAGDOLL.get("active_brace_hold", .3)
static var HEAD_GUARD: float = Effects.RAGDOLL.get("active_head_guard", .6)
static var MILL_FROM: float = Effects.RAGDOLL.get("active_mill_from", 1.2)
static var MILL_RATE: float = Effects.RAGDOLL.get("active_mill_rate", 2.2)
static var MILL_TONE: float = Effects.RAGDOLL.get("active_mill_tone", 1.5)
static var GRAB_HOLD: Array = Effects.RAGDOLL.get("active_grab_hold", [.5, 1.0])
static var GRAB_FORCE: float = Effects.RAGDOLL.get("active_grab_force", 1.3)
static var DRUNK_LATE: float = Effects.RAGDOLL.get("active_drunk_late", .2)
static var DRUNK_OVER: float = Effects.RAGDOLL.get("active_drunk_over", 1.5)
static var DRUNK_NOISE: float = Effects.RAGDOLL.get("active_drunk_noise", .1)
static var DRUNK_SWAY: float = Effects.RAGDOLL.get("active_drunk_sway", .8)
static var DRUNK_UPRIGHT: float = Effects.RAGDOLL.get("active_drunk_upright", .4)
static var BRACE_UPRIGHT: float = Effects.RAGDOLL.get("active_brace_upright", .3)
static var RISE_TONE: float = Effects.RAGDOLL.get("active_rise_tone", 1.8)
static var SHOVED_FROM: float = Effects.RAGDOLL.get("active_shoved_from", 1.5)
## A move of play's body bigger than JUMP in a frame (map units) is carried
## over JUMP_FOR seconds.
const JUMP := .3
const JUMP_FOR := .3
## Going over a rail: the lift past clearing it (map units a second) and the
## spin about the bar (radians a second).
const OVER_LIFT := 0.0
const OVER_SPIN := 3.2
## A drunk this near the eye (cells) walks as a live body (ActorLayer3D).
static var DRUNK_REACH: float = Effects.RAGDOLL.get("active_drunk_reach", 9.0)

## The bar he last went over (Vector3.INF none), its way across toward
## the far side, its half thickness, until when a ball on it rolls off.
var over_at := Vector3.INF
var _over_n := Vector3.ZERO
var _over_half := .05
var _over_until := -1.0
## The level it stands in (the view's), each ball's floor this step, and
## whether all round is open floor (the cells' ground is all there is).
var world: LevelData
var floors := PackedFloat32Array()
var _open_all := true
## Play's body's speed (map units a second across the floor).
var play_v := Vector3.ZERO
## Stunned by play (a boot, a slam): fast, he is shoved.
var stunned := false
## Shoved faster than steps can keep up: the share of play's move his
## planted boots skid with (0 none).
var skid := 0.0
## Off: no behaviour sets anything (LiveBody's muscles alone; the checks).
var acts := true
## The drunk's share (0 sober, 1 the drunk coot) and his next look and sway.
var drunk := 0.0
var _look_in := 0.0
var _sway_in := .5
## Bracing: since when, toward where; a hand on the floor first (age), the
## head or a shoulder on it first (age), -1 not yet.
var bracing := false
var brace_at := Vector3.INF
var braced_at := -1.0
var landed_at := -1.0
var _brace_from := -1.0
var _brace_pins := {}
## Hands put down to push himself up (index -> true).
var _rise_pins := {}
## Windmilling: the arms' turn now (radians), how fast it goes now.
var mill := 0.0
var milling := false
## Grabbing: the hand (0 left, 1 right, -1 none), the point, pinned since
## (age, -1 reaching), until (age); play's point to hold (Vector3.INF none);
## the next look for an edge; each grab [hand, from, to, why].
var grab_hand := -1
var grab_at := Vector3.INF
var grabbed_at := -1.0
var grab_until := -1.0
var grab_point := Vector3.INF
var _look_edge := 0.0
var _grab_rest := 0.0
var grab_log: Array = []


## An active body for a body hung on `rig`, posed as `model` under `xf`.
static func made_active(rig: RagdollRig, xf: Transform3D, model: PackedVector3Array) -> ActiveBody:
	var live := ActiveBody.new()
	LiveBody.made_live(rig, xf, model, live)
	return live


## The pose to hold and play's body (LiveBody.aim); play's body also says
## which side of a rail is his (Ragdoll.body) and how fast he goes.
func aim(points: PackedVector3Array, at: Vector3, frames: int) -> void:
	var was := _body_was
	super.aim(points, at, frames)
	body = at
	if was != Vector3.INF:
		var jump := Vector2(at.x - was.x, at.y - was.y).length()
		if jump > JUMP and jump <= 1.5:
			# Play put him somewhere at once (over a rail): the torso is
			# carried there over JUMP_FOR steps, so the rail can turn him over.
			_carry_left = maxi(_carry_left, roundi(JUMP_FOR / STEP))
			_carry_step = Vector3(at.x - was.x, at.y - was.y, 0.0) / float(_carry_left)
			# (His feet go with him as they will, no grip.)
			planted[0] = Vector3.INF
			planted[1] = Vector3.INF
			swing_foot = -1
			_over(was, at)
	if was != Vector3.INF and at.z < was.z - .002 and at.z > was.z - 1.0:
		# Play's body falling (off a ledge, over a rail): the torso drops
		# with it (the limbs come by their links, trailing).
		_carry_step.z = (at.z - was.z) / float(maxi(1, _carry_left))
	if was != Vector3.INF:
		var moved := at - was
		moved.z = 0.0
		var v := moved / (maxf(1.0, float(frames)) * STEP)
		play_v = play_v.lerp(v, .5) if v.length() < 12.0 else Vector3.ZERO


## Play took him from `from` to `to` at once: across a rail (looked for along
## the way at his hips), the bar catches him under the hips and turns him
## over it: the body thrown up to clear it and spun about the bar, head
## first over the far side, the legs swung up after (the rest is the rig,
## gravity and the bar's contact).
func _over(from: Vector3, to: Vector3) -> void:
	if world == null:
		return
	var way := Vector3(to.x - from.x, to.y - from.y, 0.0)
	var far := way.length()
	if far < 1e-4:
		return
	way /= far
	var hips := (pos[R.HIP_L] + pos[R.HIP_R]) * .5
	var rail: LevelGeometry.Segment = null
	var at := Vector3.INF
	for k in range(1, 9):
		var q := Vector3(from.x, from.y, hips.z) + way * far * k / 8.0
		for up: float in [0.0, -.25, -.5]:
			rail = PhysCore.rail_at(world, q + Vector3(0.0, 0.0, up * size), .05)
			if rail != null:
				at = q + Vector3(0.0, 0.0, up * size)
				break
		if rail != null:
			break
	if rail == null:
		return
	var pivot := Vector3(at.x, at.y, rail.z1)
	var rise := maxf(0.0, rail.z1 + radius[R.HIP_L] * 1.3 - hips.z)
	var lift := sqrt(2.0 * GRAVITY * rise) + OVER_LIFT
	var spin := Vector3(0.0, 0.0, 1.0).cross(way) * OVER_SPIN
	for i in R.POINTS:
		add_speed(i, Vector3(0.0, 0.0, lift) + spin.cross(pos[i] - pivot))
	over_at = pivot
	var run := Vector2(rail.bx - rail.ax, rail.by - rail.ay).normalized()
	var n := Vector2(-run.y, run.x)
	if n.dot(Vector2(way.x, way.y)) < 0.0:
		n = -n
	_over_n = Vector3(n.x, n.y, 0.0)
	_over_half = rail.half
	_over_until = age + 1.5


## A ball lying on the bar he went over rolls off it on his far side (the
## walls hold a ball on top of a rail it came over; nothing else tips it).
func _off_bar() -> void:
	if age > _over_until:
		return
	for i in R.POINTS:
		var p := pos[i]
		var r := radius[i]
		if p.z - r > over_at.z + .06 or p.z < over_at.z - r:
			continue
		var off := (p - over_at).dot(_over_n)
		var reach := r + _over_half
		if absf(off) < reach:
			pos[i] = p + _over_n * minf(.025, reach - off)


## Play's word (LiveBody.play_says), a drunk always reeling, a man shoved
## fast while stunned reeling too.
func play_says(is_reeling: bool, is_down: int, is_pitched: bool) -> void:
	var shoved := stunned and Vector2(play_v.x, play_v.y).length() > SHOVED_FROM
	super.play_says(is_reeling or shoved or drunk > 0.0, is_down, is_pitched)


## Step for dt seconds: the behaviours set the targets, tones and pins for
## this frame first.
func advance(level: LevelData, dt: float) -> int:
	world = level
	_behave(dt)
	return super.advance(level, dt)


func done() -> bool:
	if drunk > 0.0 or grab_hand >= 0 or not _brace_pins.is_empty() or not _rise_pins.is_empty():
		return false
	return super.done()


## One step: the floors under the balls asked first, the walls and rails
## kept last.
func live_step() -> void:
	_ask_floors()
	if skid > 0.0:
		# Driven faster than he can step: his planted boots skid along the
		# floor (the grip lost), the share `skid` of play's move.
		for f in 2:
			if planted[f] != Vector3.INF:
				planted[f] = _floored(
					planted[f] + Vector3(play_v.x, play_v.y, 0.0) * STEP * skid, FEET[f]
				)
	super.live_step()
	if world != null and not _open_all:
		for i in R.POINTS:
			if pins.has(i):
				continue
			# (A ball that went through a thin rail within the step is put
			# back to where it met it: the walls then hold it on its side or
			# lift it over the top.)
			var r := radius[i]
			if pos[i].distance_squared_to(old[i]) > r * r * .25 and not _solid(world, pos[i], r):
				for k: float in [.25, .5, .75]:
					var on := old[i].lerp(pos[i], k)
					if _solid(world, on, radius[i]):
						pos[i] = on
						break
			var was_z := pos[i].z
			_walls(world, i)
			if pos[i].z > was_z:
				# (Put up on a bar or a tread: held there, not thrown up.)
				old[i] = Vector3(old[i].x, old[i].y, old[i].z + pos[i].z - was_z)
			var low := floors[i] + (_foot_up(i) if FEET.has(i) else radius[i])
			if pos[i].z < low:
				pos[i] = Vector3(pos[i].x, pos[i].y, low)
	_off_bar()
	# Held balls end the step where they are held.
	for i: int in pins:
		var at: Vector3 = pins[i]
		pos[i] = at


func _ask_floors() -> void:
	floors.resize(R.POINTS)
	if world == null:
		floors.fill(floor_z)
		_open_all = true
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pos:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	_open_all = PhysCore.plain_rect(
		world, int(lo.x - .3), int(lo.y - .3), int(hi.x + .3), int(hi.y + .3)
	)
	_fl.size_to(R.POINTS)
	for i in R.POINTS:
		var p := pos[i]
		if _open_all:
			floors[i] = world.ground[int(p.y) * world.width + int(p.x)]
		else:
			var r := radius[i]
			var z := maxf(p.z, old[i].z) - r + .03
			# (A ball that has hardly moved keeps the floor it was given.)
			if _fl.held(i, p.x, p.y, z):
				floors[i] = _fl.floor[i]
				continue
			floors[i] = Tumble.floor_at(world, p.x, p.y, z, r * .6)
			_fl.keep(i, p.x, p.y, z, floors[i])


## Every ball on the floor under it (LiveBody's, each its own floor).
func _floor_all() -> void:
	if floors.size() != R.POINTS:
		super._floor_all()
		return
	for i in R.POINTS:
		var low := floors[i] + (_foot_up(i) if i == R.FOOT_L or i == R.FOOT_R else radius[i])
		var p := pos[i]
		if p.z < low:
			pos[i] = Vector3(p.x, p.y, low)
			var o := old[i]
			old[i] = Vector3(lerpf(o.x, p.x, .35), lerpf(o.y, p.y, .35), o.z)


func on_floor(i: int) -> bool:
	return pos[i].z <= _floor_of(i) + radius[i] + .005


## Ball i's floor this step (play's floor before the first).
func _floor_of(i: int) -> float:
	return floors[i] if floors.size() == R.POINTS else floor_z


## A foot put down at p: on the floor really there (a step down or up).
func _floored(p: Vector3, i: int) -> Vector3:
	if world == null:
		return super._floored(p, i)
	var under := Tumble.floor_at(world, p.x, p.y, maxf(p.z, floor_z) + .3, radius[i] * .6)
	return Vector3(p.x, p.y, under + _foot_up(i))


## The behaviours: each frame's tones, targets and pins.
func _behave(dt: float) -> void:
	tone = PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
	upright = 1.0
	skid = 0.0
	var fast := Vector2(play_v.x, play_v.y).length()
	if acts and stunned and down == 0 and fast > SHOVED_FROM:
		skid = clampf((fast - SHOVED_FROM * .7) / fast, 0.0, .85)
	if not muscles or not acts or target.size() < R.POINTS:
		return
	if drunk > 0.0:
		_drunk(dt)
	_brace(dt)
	_get_up()
	if not bracing:
		_grab(dt)
		if grab_hand < 0:
			_windmill(dt)


## Getting up after going over (play's down running out, pitched): the hands
## put on the floor under the shoulders and held there, the arms stiff,
## pushing the torso up off them while the legs take his weight back, the
## head up; then the hands let go.
func _get_up() -> void:
	if down >= 0 or not pitched:
		for hand: int in _rise_pins:
			unpin(hand)
		_rise_pins.clear()
		return
	var fr := _torso_frame(pos)
	var ahead := _ahead()
	for arm in 2:
		var hand := R.HAND_L if arm == 0 else R.HAND_R
		var sh := pos[R.SH_L if arm == 0 else R.SH_R]
		var under := Vector3(sh.x, sh.y, _floor_of(hand)) + ahead * .08 * size
		if not _rise_pins.has(hand):
			_arm_to(arm, (under - sh).normalized(), 1.0, .08)
			if on_floor(hand):
				_rise_pins[hand] = true
				pin(hand, Vector3(pos[hand].x, pos[hand].y, _floor_of(hand) + radius[hand]))
		elif pins.has(hand):
			var held: Vector3 = pins[hand]
			_arm_to(arm, (held - sh).normalized(), 1.0, .05)
			if sh.distance_to(held) > _arm_len(arm) * 1.05:
				# (Pushed up past his reach: the hand comes off the floor.)
				unpin(hand)
		else:
			_arm_to(arm, -fr.y, .95, .1)
	tone[ARMS] = RISE_TONE


## Arm `arm`'s length (map units).
func _arm_len(arm: int) -> float:
	var sh := R.SH_L if arm == 0 else R.SH_R
	var el := sh + 3 if arm == 0 else sh + 4
	return (
		(
			rig.points[sh].distance_to(rig.points[el])
			+ rig.points[el].distance_to(rig.points[el + 1])
		)
		* size
	)


## The arm `arm` (0 left, 1 right) reaching along the world way `dir` (its
## hand `reach` of its length out, the elbow bent `bend` of it), set in the
## pose's own frame (the muscles pull toward the pose as it stands to the
## torso).
func _arm_to(arm: int, dir: Vector3, reach := .97, bend := .12) -> void:
	var sh := R.SH_L if arm == 0 else R.SH_R
	var el := sh + 3 if arm == 0 else sh + 4
	var hand := el + 1
	if _stiff(sh):
		return
	var fr := _torso_frame(pos)
	var ft := _torso_frame(target)
	var back := ft * fr.transposed()
	var d := (back * dir).normalized()
	var upper := rig.points[sh].distance_to(rig.points[el]) * size
	var fore := rig.points[el].distance_to(rig.points[hand]) * size
	# (The elbow out a little from the line, toward the body's outside.)
	var out := ft.x * (-1.0 if arm == 0 else 1.0)
	var bow := (out - d * out.dot(d)).normalized() * bend * upper
	target[el] = target[sh] + d * upper * sqrt(maxf(0.0, 1.0 - bend * bend)) + bow
	target[hand] = target[sh] + d * (upper + fore) * reach


## Going over: the arms out toward where the chest will land, the head held
## off it, a hand that gets there held and the fall landing on it.
func _brace(_dt: float) -> void:
	var fr := _torso_frame(pos)
	var tipping := fr.y.z < cos(TIP) and mid_speed.z < -.05
	var falling := (down > 0 and pitched) or (tipping and down >= 0)
	if not falling:
		if bracing:
			_end_brace()
		return
	if not bracing:
		bracing = true
		_brace_from = age
		clutch_until = minf(clutch_until, age)
	if down > 0 and pitched:
		# Pitched over, he gives himself to it: the ankle lets the torso go
		# over onto the hands rather than hold him kneeling.
		upright = BRACE_UPRIGHT
	var feet := (pos[R.FOOT_L] + pos[R.FOOT_R]) * .5
	var sh := (pos[R.SH_L] + pos[R.SH_R]) * .5
	var lean := Vector3(sh.x - feet.x, sh.y - feet.y, 0.0)
	if lean.length() < .05 * size:
		lean += Vector3(mid_speed.x, mid_speed.y, 0.0) * .2
	if lean.length() < 1e-4:
		lean = _ahead()
	lean = lean.normalized()
	# (Where the shoulders come down as he goes over: ahead of them by
	# about half their height.)
	var tall := maxf(.3, sh.z - floor_z)
	var at := Vector3(sh.x, sh.y, floor_z) + lean * tall * .45
	var under := floor_z
	if world != null:
		under = Tumble.floor_at(world, at.x, at.y, sh.z, .05)
	brace_at = Vector3(at.x, at.y, under)
	var across := fr.x
	across.z = 0.0
	for arm in 2:
		var shoulder := pos[R.SH_L if arm == 0 else R.SH_R]
		var side := across * (radius[R.SH_L] * (-1.0 if arm == 0 else 1.0))
		_arm_to(arm, (brace_at + side - shoulder).normalized(), .97, .1)
	tone[ARMS] = BRACE
	# The head held up off the fall: tipped back from the way he goes over.
	var neck_t := (target[R.SH_L] + target[R.SH_R]) * .5
	var ft := _torso_frame(target)
	var back := ft * fr.transposed()
	var away := (back * -lean).normalized()
	var head_rel := target[R.HEAD] - neck_t
	var tall_head := head_rel.length()
	target[R.HEAD] = (
		neck_t + (head_rel.normalized() * cos(HEAD_GUARD) + away * sin(HEAD_GUARD)) * tall_head
	)
	tone[HEAD_GROUP] = 1.6
	# A hand on the floor is held there a moment (the fall lands on it).
	for hand: int in [R.HAND_L, R.HAND_R]:
		if on_floor(hand) and not _brace_pins.has(hand):
			if braced_at < 0.0:
				braced_at = age
			_brace_pins[hand] = age
			pin(hand, Vector3(pos[hand].x, pos[hand].y, _floor_of(hand) + radius[hand]))
	for hand: int in _brace_pins.keys():
		var since: float = _brace_pins[hand]
		if age - since > BRACE_HOLD:
			unpin(hand)
		else:
			tone[ARMS] = BRACE * (1.0 - (age - since) / BRACE_HOLD * .6)
	if landed_at < 0.0:
		for i: int in [R.HEAD, R.SH_L, R.SH_R, R.BELLY]:
			if on_floor(i):
				landed_at = age
				break


func _end_brace() -> void:
	bracing = false
	for hand: int in _brace_pins.keys():
		unpin(hand)
	_brace_pins.clear()


## Reeling fast: the arms round the way he goes.
func _windmill(dt: float) -> void:
	var fast := maxf(
		Vector2(play_v.x, play_v.y).length(), Vector2(mid_speed.x, mid_speed.y).length()
	)
	milling = reeling and down == 0 and fast > MILL_FROM * size
	if not milling:
		return
	var ahead := _ahead()
	var way := 1.0 if Vector2(play_v.x, play_v.y).dot(Vector2(ahead.x, ahead.y)) >= 0.0 else -1.0
	var k := clampf((fast - MILL_FROM * size) / (MILL_FROM * size), .4, 1.0)
	mill += dt * MILL_RATE * TAU * way * k
	var fr := _torso_frame(pos)
	for arm in 2:
		var a := mill + (PI if arm == 1 else 0.0)
		var side := fr.x * (-.3 if arm == 0 else .3)
		_arm_to(arm, (fr.y * cos(a) + fr.z * sin(a) + side).normalized(), .95, .2)
	tone[ARMS] = MILL_TONE
	clutch_until = minf(clutch_until, age)


## Reeling by an edge: the near hand to it and pinned there, let go by time
## or force.
func _grab(dt: float) -> void:
	_grab_rest = maxf(0.0, _grab_rest - dt)
	if grab_hand >= 0:
		_hold(dt)
		return
	if not reeling or down > 0 or _grab_rest > 0.0 or world == null:
		return
	var point := grab_point
	if point == Vector3.INF:
		_look_edge -= dt
		if _look_edge > 0.0:
			return
		_look_edge = .1
		var mid := middle()
		var way := Vector2(mid_speed.x, mid_speed.y)
		if way.length() < .3 * size:
			return
		var tall := (target[R.HEAD].z - floor_z) * 1.08
		point = BodyPlay.edge(
			world, Vector2(mid.x, mid.y), floor_z, tall, way, BodyPlay.GRAB_REACH * tall, false
		)
		if point == Vector3.INF:
			return
	var fr := _torso_frame(pos)
	var right := (point - middle()).dot(fr.x) > 0.0
	grab_hand = 1 if right else 0
	if _stiff(R.SH_R if right else R.SH_L):
		grab_hand = 1 - grab_hand
	grab_at = point
	grabbed_at = -1.0
	var lo: float = GRAB_HOLD[0]
	var hi: float = GRAB_HOLD[1]
	grab_until = age + .35 + dice.randf_range(lo, hi)
	clutch_until = minf(clutch_until, age)


func _hold(_dt: float) -> void:
	var hand := R.HAND_L if grab_hand == 0 else R.HAND_R
	var sh := R.SH_L if grab_hand == 0 else R.SH_R
	var el := hand - 1
	var arm := (
		(rig.points[sh].distance_to(rig.points[el]) + rig.points[el].distance_to(rig.points[hand]))
		* size
	)
	var at := grab_at + Vector3(0.0, 0.0, radius[hand] * .6)
	var why := ""
	if grabbed_at < 0.0:
		# Reaching: the hand there, the arm stiff.
		_arm_to(grab_hand, (at - pos[sh]).normalized(), 1.0, .05)
		tone[ARMS] = 1.6
		aim_override[hand] = at
		if pos[hand].distance_to(at) < radius[hand] * 1.6:
			pin(hand, at)
			aim_override[hand] = Vector3.INF
			grabbed_at = age
		elif age > grab_until or pos[sh].distance_to(at) > arm * GRAB_FORCE * 1.15:
			why = "missed"
	else:
		# Held: the arm takes the pull; it lets go by force or time.
		_arm_to(grab_hand, (at - pos[sh]).normalized(), .9, .15)
		tone[ARMS] = 1.2
		if pos[sh].distance_to(at) > arm * GRAB_FORCE:
			why = "force"
		elif age > grab_until and grab_point == Vector3.INF:
			why = "time"
		elif down > 0 and pos[sh].distance_to(at) > arm:
			why = "force"
	if why != "":
		grab_log.append([grab_hand, grabbed_at, age, why])
		unpin(hand)
		aim_override[hand] = Vector3.INF
		grab_hand = -1
		grab_at = Vector3.INF
		_grab_rest = 1.2


## The drunk: arms out, the ankle weak, a sway now and then.
func _drunk(dt: float) -> void:
	upright = DRUNK_UPRIGHT
	var fr := _torso_frame(pos)
	for arm in 2:
		var s := -1.0 if arm == 0 else 1.0
		var lift := -.35 + .3 * sin(age * (1.7 + arm * .4) + arm * 2.0)
		_arm_to(arm, (fr.x * s * cos(lift) + fr.y * sin(lift) + fr.z * .25).normalized(), .9, .25)
	tone[ARMS] = .8
	_sway_in -= dt
	if _sway_in <= 0.0 and down == 0:
		_sway_in = dice.randf_range(.45, 1.1)
		var sh := (pos[R.SH_L] + pos[R.SH_R]) * .5
		var side := fr.x * (1.0 if dice.randf() < .5 else -1.0)
		push_at(sh, (side + fr.z * dice.randf_range(-.4, .4)).normalized(), DRUNK_SWAY * drunk)


## The balance controller (LiveBody's); a drunk's looks at it come late.
func _balance() -> void:
	if drunk > 0.0 and swing_foot < 0 and down == 0:
		_look_in -= STEP
		if _look_in > 0.0:
			return
		_look_in = DRUNK_LATE * dice.randf_range(.6, 1.4)
	super._balance()


## A swing begins (LiveBody's): a drunk's goes too far and off its line.
func _start_swing(f: int, to: Vector3) -> void:
	if drunk > 0.0 and reeling and down == 0:
		var from := pos[FEET[f]]
		var other := planted[1 - f] if planted[1 - f] != Vector3.INF else from
		var run := Vector3(to.x - other.x, to.y - other.y, 0.0)
		var noise := Vector3(dice.randf_range(-1.0, 1.0), dice.randf_range(-1.0, 1.0), 0.0)
		var want := other + run * lerpf(1.0, DRUNK_OVER, drunk) + noise * DRUNK_NOISE * size * drunk
		var hip := pos[HIPS[f]]
		var flat := Vector2(want.x - hip.x, want.y - hip.y).limit_length(_leg * .9)
		to = _floored(Vector3(hip.x + flat.x, hip.y + flat.y, to.z), FEET[f])
	super._start_swing(f, to)
