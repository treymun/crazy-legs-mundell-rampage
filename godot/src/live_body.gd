## A living body taking a hit (pass 15, PUNCH: the active bodies' step one,
## looks only). The 3D view's ActorView runs one for a hand that was just
## hit (the nearest few: ActorLayer3D's budget): the body becomes the
## ragdoll's rig of fifteen balls (Ragdoll: the same masses, links, joint
## stops and knee hinges a dead body has, gravity, the floor), and the
## animation only gives the pose it tries to hold (`aim`: the TARGET).
## Muscles are springs pulling each joint toward that pose as it stands to
## the torso (each pull has its pull back on the parent ball, so muscles
## alone never lift or move the body); their stiffness changes: soft the
## instant a hit lands, stiffening back over `recover`. What holds him up is
## physics too: the feet planted on the floor (gripped where they stand), the
## legs' muscles pushing against them, and the ankle's turn on the torso
## toward upright, which only a foot on the floor can give and only so much
## (`upright_most` a step). Where his middle goes across the floor is play's
## (src/stagger.gd: the pendulum and the catch steps, carried online): the
## torso is carried with play's body; the feet are not, so when the middle
## goes past them his own balance controller steps: the capture point (the
## middle plus its speed over the pendulum's rate) outside the planted feet
## swings a foot to it on an arc, which plants where it comes down (a catch
## step, counted in `catches`).
##
## A hit is an impulse at the point struck (`hit`: by the hit's way and
## strength from play's note, its height and how far off the middle), so the
## same push at the head, the chest, the shoulder or a knee gives a
## different reaction; a hand goes to a wound on the chest, belly or a
## shoulder and stays there a while (`clutch`); a leg hit buckles that knee
## (its muscles give and its pose is pulled shorter); down (play's note)
## the legs and the ankle give and he drops to a knee or pitches onto his
## hands, then the muscles stiffen and lift him back up. Hits while it runs
## add on (staggers stack). Its own dice (seeded from the body and the hit),
## never game.rng; it never writes play.
##
## Extension points (the active bodies' later steps, track T11): `tone`
## per group (TORSO, ARMS, LEGS, HEAD) and `upright` are the muscles' and the
## ankle's stiffness; `aim_override` holds a world target per ball (a brace,
## a grab's hand); `pin(i, at)` / `unpin(i)` a ball held to a point (a grab
## constraint); `push_at` an impulse; `on_floor(i)` a ball's contact. A new
## behaviour sets those each frame before `advance`; see docs/dev/gameplay.md
## "Living bodies".
class_name LiveBody
extends Ragdoll

const TORSO := 0
const ARMS := 1
const LEGS := 2
const HEAD_GROUP := 3
## Each ball's chain parent for the muscles (-1: none, the torso; -2: the
## neck, between the shoulders).
const PARENT_OF: Array[int] = [
	-1,
	-1,
	-1,
	-1,
	-2,
	R.SH_L,
	R.ELBOW_L,
	R.SH_R,
	R.ELBOW_R,
	R.HIP_L,
	R.KNEE_L,
	R.HIP_R,
	R.KNEE_R,
	-1,
	-1
]
const GROUP_OF: Array[int] = [0, 0, 0, 0, 3, 1, 1, 1, 1, 2, 2, 2, 2, 0, 0]
const TORSO_BALLS: Array[int] = [R.HIP_L, R.HIP_R, R.SH_L, R.SH_R, R.BELLY, R.BACK, R.HEAD]
const FEET: Array[int] = [R.FOOT_L, R.FOOT_R]
const KNEES: Array[int] = [R.KNEE_L, R.KNEE_R]
const HIPS: Array[int] = [R.HIP_L, R.HIP_R]
const PASSES_LIVE := 4
const AIR_LIVE := .985

## Numbers (effects.cfg [ragdoll] live_*: looks).
static var TONE: float = Effects.RAGDOLL.get("live_tone", .45)
static var SOFT: float = Effects.RAGDOLL.get("live_soft", .12)
static var RECOVER: float = Effects.RAGDOLL.get("live_recover", .55)
static var UPRIGHT_MOST: float = Effects.RAGDOLL.get("live_upright_most", .05)
static var UPRIGHT: float = Effects.RAGDOLL.get("live_upright", .25)
static var CARRY: float = Effects.RAGDOLL.get("live_carry", .08)
static var SUPPORT: float = Effects.RAGDOLL.get("live_support", .1)
static var STRIKE_K: float = Effects.RAGDOLL.get("live_strike", 1.7)
static var SWING_FOR: float = Effects.RAGDOLL.get("live_swing", .22)
static var LIFT: float = Effects.RAGDOLL.get("live_lift", .09)
static var MARGIN: float = Effects.RAGDOLL.get("live_margin", .14)
static var CLUTCH: Array = Effects.RAGDOLL.get("live_clutch", [1.1, 2.2])
static var BUCKLE_DIP: float = Effects.RAGDOLL.get("live_buckle", .3)
static var LIVE_MOST: float = Effects.RAGDOLL.get("live_longest", 4.0)
static var BUCKLE_GIVE: float = Effects.RAGDOLL.get("live_buckle_give", .5)
static var ARM_SPIN: float = Effects.RAGDOLL.get("live_arm", 1.4)
static var SETTLE_K: float = Effects.RAGDOLL.get("live_settle", 1.8)
## The most the legs lift the hips a pass (map units: getting up is a push,
## not a jump).
static var RISE_MOST: float = Effects.RAGDOLL.get("live_rise", .006)
static var MUSCLE_MOST: float = Effects.RAGDOLL.get("live_muscle_most", .012)
static var SPEED_MOST: float = Effects.RAGDOLL.get("live_speed_most", 5.0)
static var DOWN_LEGS: float = Effects.RAGDOLL.get("live_down_legs", .1)
static var DOWN_UPRIGHT: float = Effects.RAGDOLL.get("live_down_upright", .5)
static var DOWN_KNEE: float = Effects.RAGDOLL.get("live_down_knee", 2.2)
static var CLUTCH_PULL: float = Effects.RAGDOLL.get("live_clutch_pull", .3)
static var SOFT_FULL: float = Effects.RAGDOLL.get("live_soft_full", 1.2)
static var HEAD_SNAP: float = Effects.RAGDOLL.get("live_head", 2.0)

## Live bodies at once (the nearest), on a phone or the LOW physics tier
## fewer (effects.cfg [ragdoll] live_most, live_phone).
static var MOST: int = Effects.RAGDOLL.get("live_most", 4)
static var MOST_PHONE: int = Effects.RAGDOLL.get("live_phone", 2)


## How many live bodies may run this frame.
static func most_now() -> int:
	var phone := (
		OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	)
	return MOST_PHONE if phone or Quality.level() == Quality.LOW else MOST


## The pose it tries to hold (map), this frame's (aim).
var target := PackedVector3Array()
## A world target per ball that wins over the pose (Vector3.INF: none).
var aim_override := PackedVector3Array()
## Per group (TORSO, ARMS, LEGS, HEAD) a share of TONE; the ankle's turn.
var tone := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
var upright := 1.0
## Off: no muscles, no ankle, no support at all (the checks: a limp body).
var muscles := true
## Play's body (map: x, y and the floor it stands on), its last, and the
## frame's move shared over the steps.
var floor_z := 0.0
var _body_was := Vector3.INF
var _carry_step := Vector3.ZERO
var _carry_left := 0
## The middle's last step and its speed (map units a second).
var _mid_was := Vector3.INF
var mid_speed := Vector3.ZERO
## Feet: planted where (Vector3.INF: free), the one swinging (-1 none), its
## swing's start, end and progress.
var planted := PackedVector3Array([Vector3.INF, Vector3.INF])
var swing_foot := -1
var _swing_from := Vector3.ZERO
var _swing_to := Vector3.ZERO
var _swing_t := 0.0
var _last_foot := -1
## A leg's length (map units).
var _leg := 1.0
var _catching := false
## Each foot's step back to the pose taken (once a reel).
var _stepped_back := PackedByteArray([0, 0])
## Catch steps taken, and each [age, foot, from, to].
var catches := 0
var step_log: Array = []
## The last hit (age), the wound (torso frame: across, up, ahead from the
## hips' middle), the clutching hand (-1 none) and until when; a buckled leg
## (0 left, 1 right, -1 none) and until when.
var hit_age := -100.0
var hits := 0
## How far the last hit softened the muscles (0 none, 1 down to SOFT).
var soft_by := 0.0
var wound := Vector3.ZERO
var clutch_hand := -1
var clutch_until := -1.0
var limp_arm := -1
var buckle_leg := -1
## How deep the buckle (0.5 a light hit .. 1).
var buckle_by := 1.0
var buckle_until := -1.0
## Play's say: down (a knee or pitched over: 1, getting up: -1, 0 up), pitched.
var down := 0
var pitched := false
## Reeling per play (a note on the enemy).
var reeling := false
## The pendulum's rate (1/s) of this body (Stagger.rate).
var omega := 3.3
## Pinned balls: index -> world point (a grab's hand; T11).
var pins := {}
var dice := RandomNumberGenerator.new()
var _frame_r := Basis.IDENTITY
var _frame_t := Basis.IDENTITY


## A live body for a body hung on `rig`, posed as `model` (model space,
## the rig's fifteen points) under the model's transform `xf`.
static func made_live(rig: RagdollRig, xf: Transform3D, model: PackedVector3Array) -> LiveBody:
	var live := LiveBody.new()
	var scale := xf.basis.get_scale().x
	var at := PackedVector3Array()
	var rest := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in R.POINTS:
		at.append(Ragdoll.to_map(xf, model[i]))
		rest.append(rig.points[i] * scale)
		radii.append(rig.radii[i] * scale)
	live.size = scale
	live.rig = rig
	live.start(at, radii, rest)
	live.fit()
	live.target = live.pos.duplicate()
	# The hands may come together (a dead body's are kept as far apart as
	# they stood: a hand on a gun's stock and one on its barrel).
	for k in live.la.size():
		var a := live.la[k]
		var b := live.lb[k]
		if (a == R.HAND_L and b == R.HAND_R) or (a == R.HAND_R and b == R.HAND_L):
			live.lmin[k] = (live.radius[a] + live.radius[b]) * .9
	live._leg = (
		(
			rig.points[R.HIP_L].distance_to(rig.points[R.KNEE_L])
			+ rig.points[R.KNEE_L].distance_to(rig.points[R.FOOT_L])
		)
		* scale
	)
	live.aim_override.resize(R.POINTS)
	live.aim_override.fill(Vector3.INF)
	return live


## The pose to hold this frame (map points, the rig's fifteen), play's body
## at `body` (map x, y and the floor under it).
func aim(points: PackedVector3Array, body: Vector3, frames: int) -> void:
	if points.size() >= R.POINTS:
		target = points
	floor_z = body.z
	if _body_was == Vector3.INF:
		_body_was = body
	var moved := body - _body_was
	moved.z = 0.0
	_body_was = body
	if moved.length() > 1.5:
		# A jump (put back somewhere): the whole body goes.
		for i in pos.size():
			pos[i] += moved
			old[i] += moved
			prev[i] += moved
		for f in 2:
			if planted[f] != Vector3.INF:
				planted[f] += moved
		moved = Vector3.ZERO
	_carry_left = maxi(1, frames)
	_carry_step = moved / float(_carry_left)


## A hit: the impulse `j` (map units a second across the floor: its way and
## strength), landing `hz` of the body's height up and `lat` off its middle
## (across the impulse, map units), on zone `zone` ("head", "body", "arms",
## "legs"), from the side `side` faced. Seeded by `seed` (its own dice).
func hit(j: Vector2, hz: float, lat: float, zone: String, seed: int) -> void:
	dice.seed = seed
	hits += 1
	wake()
	var way := Vector3(j.x, j.y, 0.0)
	var strength := way.length()
	if strength < 1e-4:
		way = _ahead() * -1.0
		strength = .4
	way /= strength
	# (What is left of the last softening adds to this one: staggers stack.)
	var left := 1.0 - clampf((age - hit_age) / RECOVER, 0.0, 1.0)
	soft_by = clampf(maxf(soft_by * left, 0.0) + strength / SOFT_FULL, 0.0, 1.0)
	hit_age = age
	var hips := (pos[R.HIP_L] + pos[R.HIP_R]) * .5
	var top := pos[R.HEAD]
	var at := hips.lerp(top, clampf((hz - .45) / .5, 0.0, 1.0))
	var side := way.cross(Vector3(0.0, 0.0, 1.0)).normalized()
	at += side * lat
	var r := _torso_frame(pos)
	var leg := -1
	match zone:
		"head":
			at = pos[R.HEAD]
			strength *= HEAD_SNAP
		"legs":
			var right_side := (pos[R.KNEE_R] - pos[R.KNEE_L]).dot(side) * lat > 0.0
			leg = 1 if right_side else 0
			at = pos[KNEES[leg]].lerp(pos[HIPS[leg]], dice.randf_range(0.0, .4))
		"arms":
			strength *= ARM_SPIN
			var near_r := (pos[R.SH_R] - pos[R.SH_L]).dot(-way) < 0.0
			var hit_r := (
				near_r if absf(lat) < .05 else (pos[R.SH_R] - pos[R.SH_L]).dot(side) * lat > 0.0
			)
			# The shoulder takes it (the arm swings, the shoulders turn).
			at = pos[R.SH_R if hit_r else R.SH_L].lerp(pos[R.ELBOW_R if hit_r else R.ELBOW_L], .2)
			limp_arm = 1 if hit_r else 0
	# The impulse at the point (its torque turns the body), a touch down a
	# leg hit and up a head hit.
	var lift := .25 if zone == "head" else -.2 if zone == "legs" else 0.0
	strike(at, (way + Vector3(0.0, 0.0, lift)).normalized(), strength * STRIKE_K)
	# The hips' run across the floor is play's (carried with play's body):
	# what the impulse gave them is mostly taken back; the rest of him keeps
	# it, so a blow above the hips turns the body about them (the shoulders
	# and head thrown back, a shoulder spun round).
	var sum := (pos[R.HIP_L] - old[R.HIP_L] + pos[R.HIP_R] - old[R.HIP_R]) * .5
	sum.z = 0.0
	for i: int in HIPS:
		old[i] += sum * .8
	# Where it hurts: a hand to the wound (chest, belly, a shoulder), the
	# other side's hand, and it stays there a while.
	if zone == "body" or zone == "arms":
		var local := r.transposed() * (at - hips)
		wound = local + r.transposed() * (-way) * radius[R.BELLY] * .6
		var across := local.x
		var hand := 0 if across > 0.0 else 1
		if zone == "arms":
			hand = 1 - limp_arm
		elif absf(across) < radius[R.BELLY] * .5:
			hand = 0 if dice.randf() < .5 else 1
		# An arm modelled as one piece (RagdollRig.stiff) cannot bend to it,
		# and a hand holding a gun keeps it (RagdollRig.holds): the other
		# hand, or none.
		if _stiff(R.SH_L if hand == 0 else R.SH_R) or _holding(hand):
			hand = 1 - hand
		if (
			_stiff(R.SH_L if hand == 0 else R.SH_R)
			or _holding(hand)
			or (zone == "arms" and hand == limp_arm)
		):
			hand = -1
		clutch_hand = hand
		var lo: float = CLUTCH[0]
		var hi: float = CLUTCH[1]
		clutch_until = age + dice.randf_range(lo, hi)
	if leg >= 0:
		buckle_leg = leg
		buckle_by = clampf(.5 + strength / SOFT_FULL * .5, .5, 1.0)
		buckle_until = age + dice.randf_range(.7, 1.2)
		# The knee gives: it goes forward and down under him.
		var fwd := _ahead()
		add_speed(
			KNEES[leg],
			(fwd * .9 + Vector3(0.0, 0.0, -.5)) * minf(strength * STRIKE_K * .5, STRIKE_MOST)
		)
	if planted[0] == Vector3.INF and planted[1] == Vector3.INF:
		for f in 2:
			planted[f] = _floored(pos[FEET[f]], FEET[f])


## Play's word on him this frame: reeling (a note), down (1 down, -1
## getting up, 0 on his feet) and pitched over (not on a knee).
func play_says(is_reeling: bool, is_down: int, is_pitched: bool) -> void:
	reeling = is_reeling
	if is_down != 0 and down == 0:
		pitched = is_pitched
		if not pitched and buckle_leg < 0:
			buckle_leg = 0 if dice.randf() < .5 else 1
	down = is_down
	if is_down != 0:
		buckle_until = maxf(buckle_until, age + .3)


## Whether it is done: no reel, settled back into its pose, the hand off the
## wound. The view hands back to the animation then.
func done() -> bool:
	if age > LIVE_MOST:
		return true
	if reeling or down != 0 or age - hit_age < RECOVER * 1.6 or age < clutch_until:
		return false
	if swing_foot >= 0:
		return false
	var off := 0.0
	for i in R.POINTS:
		off = maxf(off, pos[i].distance_to(target[i]))
	return off < .06 * size


## Whether hand `hand` (0 left, 1 right) holds a thing it keeps hold of.
func _holding(hand: int) -> bool:
	return rig != null and hand >= 0 and hand < rig.holds.size() and rig.holds[hand] == 1


## The muscles' stiffness now for group `g` (soft after a hit, back over RECOVER).
func stiff(g: int) -> float:
	if not muscles:
		return 0.0
	var since := age - hit_age
	var k := clampf(since / RECOVER, 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	# A light hit softens them a little, a heavy one all the way to SOFT.
	var t := TONE * lerpf(lerpf(1.0, SOFT, soft_by), 1.0, k) * tone[g]
	if down > 0:
		# Down: the legs give (to a knee, the buckled one first), the back
		# half holds (step one: a man knocked down, not one laid out).
		t *= DOWN_LEGS if g == LEGS else .7 if g == TORSO else .8
	elif down < 0:
		# Getting up: the legs take his weight again a little at a time.
		t *= .35 if g == LEGS else .7
	elif not reeling and k >= 1.0:
		# The reel over: he pulls himself back together (SETTLE times as
		# stiff, coming in over a moment).
		var over := clampf((age - hit_age - RECOVER) / .4, 0.0, 1.0)
		t *= lerpf(1.0, SETTLE_K, over)
	return minf(t, .9)


## Step for dt seconds (in STEP steps, at most MOST_STEPS); returns the steps.
func advance(_world: LevelData, dt: float) -> int:
	_left = minf(_left + dt, STEP * MOST_STEPS)
	var n := 0
	while _left >= STEP and budget > 0:
		_left -= STEP
		budget -= 1
		live_step()
		n += 1
	return n


## One step of the living body.
func live_step() -> void:
	steps += 1
	age += STEP
	var g := GRAVITY * STEP * STEP
	var carry_now := _carry_step if _carry_left > 0 else Vector3.ZERO
	_carry_left -= 1
	for i in R.POINTS:
		var p := pos[i]
		prev[i] = p
		# (No part faster than SPEED_MOST: the joints' corrections fighting a
		# planted foot and the floor never fling him.)
		var v := ((p - old[i]) * AIR_LIVE).limit_length(SPEED_MOST * STEP)
		old[i] = p
		pos[i] = p + v - Vector3(0.0, 0.0, g)
	# Play's body's move: whole to the torso, as no speed of its own.
	if carry_now != Vector3.ZERO:
		for i: int in TORSO_BALLS:
			pos[i] += carry_now
			old[i] += carry_now
	_frame_t = _torso_frame(target)
	var supported := _supported()
	for _pass in PASSES_LIVE:
		if muscles:
			_upright(supported)
			_pull(supported)
			_reach()
		_links()
		_hinges()
		_feet()
		_floor_all()
	# Once more after the feet and the floor: no limb ends the step stretched.
	for _k in 2:
		for _j in 2:
			_links()
		_feet(false)
		_floor_all()
	_balance()
	var mid := middle()
	if _mid_was != Vector3.INF:
		mid_speed = mid_speed.lerp((mid - _mid_was) / STEP, .5)
	_mid_was = mid
	awake = true


## The torso's frame of points `at` (columns: across, up, ahead).
static func _torso_frame(at: PackedVector3Array) -> Basis:
	var hips := (at[R.HIP_L] + at[R.HIP_R]) * .5
	var up := ((at[R.SH_L] + at[R.SH_R]) * .5 - hips).normalized()
	var across := (at[R.SH_R] - at[R.SH_L]) + (at[R.HIP_R] - at[R.HIP_L])
	across = (across - up * across.dot(up)).normalized()
	if across.length_squared() < .5 or up.length_squared() < .5:
		return Basis.IDENTITY
	return Basis(across, up, across.cross(up)).orthonormalized()


func _ahead() -> Vector3:
	var f := _torso_frame(pos)
	var a := f.z
	a.z = 0.0
	return a.normalized() if a.length_squared() > 1e-6 else Vector3(1.0, 0.0, 0.0)


## A foot on the floor (planted, or a ball down there): the ground can turn
## and hold him.
func _supported() -> bool:
	for f in 2:
		if f != swing_foot and (planted[f] != Vector3.INF or on_floor(FEET[f])):
			return true
	return false


## The ankle's turn: the torso turned toward the pose's torso, about its
## middle, at most UPRIGHT_MOST a pass (a foot on the floor only).
func _upright(supported: bool) -> void:
	if not supported:
		return
	var k := UPRIGHT * upright * (stiff(TORSO) / TONE)
	if down > 0:
		k *= DOWN_UPRIGHT * (.6 if pitched else 1.0)
	if k <= 0.0:
		return
	_frame_r = _torso_frame(pos)
	var turn := (_frame_t * _frame_r.transposed()).orthonormalized()
	var q := turn.get_rotation_quaternion()
	var angle := q.get_angle()
	if angle < 1e-4:
		return
	var axis := q.get_axis()
	var most := UPRIGHT_MOST * (2.0 if not reeling and age - hit_age > RECOVER else 1.0)
	if down < 0 or angle > .6:
		# Getting up (or far over): a push up off the floor, not a spring.
		most = UPRIGHT_MOST * .6
	var by := minf(angle * k, most)
	var b := Basis(axis.normalized(), by)
	var mid := middle()
	for i: int in TORSO_BALLS:
		pos[i] = mid + b * (pos[i] - mid)


## The muscles: each ball toward the pose as it stands to the torso, pulled
## back on its chain parent by the same (the arms, the legs, the head); the
## stance legs' push holds the hips at the pose's height over the planted
## feet; play's middle pulls the torso along.
func _pull(supported: bool) -> void:
	_frame_r = _torso_frame(pos)
	var turn := _frame_r * _frame_t.transposed()
	var neck := (pos[R.SH_L] + pos[R.SH_R]) * .5
	var neck_t := (target[R.SH_L] + target[R.SH_R]) * .5
	for i in R.POINTS:
		var par: int = PARENT_OF[i]
		if par == -1:
			continue
		var k := stiff(GROUP_OF[i])
		if i == R.KNEE_L or i == R.FOOT_L:
			k *= _leg_give(0)
		elif i == R.KNEE_R or i == R.FOOT_R:
			k *= _leg_give(1)
		if clutch_hand >= 0 and age < clutch_until and down <= 0:
			# The clutching arm goes where the hand goes (_reach), not the pose.
			var hand := R.HAND_L if clutch_hand == 0 else R.HAND_R
			if i == hand or i == hand - 1:
				continue
		if limp_arm >= 0 and age < clutch_until + .5:
			var limp_balls: Array = (
				[R.ELBOW_R, R.HAND_R] if limp_arm == 1 else [R.ELBOW_L, R.HAND_L]
			)
			if limp_balls.has(i):
				k *= .25
		if k <= 0.0:
			continue
		var from := neck if par == -2 else pos[par]
		var from_t := neck_t if par == -2 else target[par]
		var rel := target[i] - from_t
		if (i == R.KNEE_L or i == R.KNEE_R) and _buckled(0 if i == R.KNEE_L else 1):
			# A buckled knee: it gives forward and down (the pose it holds
			# folded; the hip drops with it).
			# (Down, it goes to the floor: on one knee.)
			var deep := DOWN_KNEE if down > 0 else 1.0
			rel += (_frame_t.z * .8 - _frame_t.y * .5 * deep) * BUCKLE_DIP * size * buckle_by * deep
		var want := from + turn * rel
		# (A muscle pulls so hard and no harder: MUSCLE_MOST a pass.)
		var d := (want - pos[i]).limit_length(MUSCLE_MOST * size / maxf(k, .05))
		var wi := inv_mass[i]
		if par == -2:
			var wp := (inv_mass[R.SH_L] + inv_mass[R.SH_R]) * .5
			var fix := d * (k / (wi + wp))
			pos[i] += fix * wi
			pos[R.SH_L] -= fix * wp * .5
			pos[R.SH_R] -= fix * wp * .5
		else:
			var wp := inv_mass[par]
			var fix := d * (k / (wi + wp))
			pos[i] += fix * wi
			pos[par] -= fix * wp
	# The stance legs' push: the hips held at the pose's height over the floor.
	var mid := middle()
	var mid_t := (target[R.HIP_L] + target[R.HIP_R] + target[R.SH_L] + target[R.SH_R]) * .25
	if supported:
		var legs := stiff(LEGS) / TONE
		var up := clampf((mid_t.z - mid.z) * SUPPORT * legs, -RISE_MOST, RISE_MOST)
		if down > 0:
			up = minf(up, 0.0)
		# Each side by its own leg (a buckled knee lets its hip down): the
		# torso lifted by the two's mean and rolled by their difference,
		# whole (its links stay as they are).
		var left_up := up * _leg_give(0)
		var right_up := up * _leg_give(1)
		var lift := Vector3(0.0, 0.0, (left_up + right_up) * .5)
		var width := pos[R.HIP_L].distance_to(pos[R.HIP_R])
		var roll := Basis.IDENTITY
		var ahead := _frame_r.z
		if width > 1e-4 and absf(left_up - right_up) > 1e-6:
			roll = Basis(ahead, (left_up - right_up) / width)
		for i: int in TORSO_BALLS:
			pos[i] = mid + roll * (pos[i] - mid) + lift
	# Play's middle (the pendulum's) pulls the hips across the floor (the
	# rest of the torso comes by its links, turning about them).
	var hips := (pos[R.HIP_L] + pos[R.HIP_R]) * .5
	var hips_t := (target[R.HIP_L] + target[R.HIP_R]) * .5
	var off := Vector3(hips_t.x - hips.x, hips_t.y - hips.y, 0.0) * CARRY
	for i: int in HIPS:
		pos[i] += off


## The hand on the wound, and any world targets set (aim_override).
func _reach() -> void:
	if clutch_hand >= 0 and age < clutch_until and down <= 0:
		var hand := R.HAND_L if clutch_hand == 0 else R.HAND_R
		var hips := (pos[R.HIP_L] + pos[R.HIP_R]) * .5
		var want := hips + _frame_r * wound
		# (No further than the arm reaches from its shoulder.)
		var sh := R.SH_L if clutch_hand == 0 else R.SH_R
		var reach := (
			(
				rig.points[sh].distance_to(rig.points[sh + 3 if sh == R.SH_L else sh + 4])
				+ rig.points[hand - 1].distance_to(rig.points[hand])
			)
			* size
			* .92
		)
		if want.distance_to(pos[sh]) > reach:
			want = pos[sh] + (want - pos[sh]).normalized() * reach
		# (A move of his own, soft muscles or not: it comes in over a moment.)
		var k := CLUTCH_PULL * clampf((age - hit_age) / .12, .15, 1.0)
		var d := want - pos[hand]
		# (The pull back spread over the torso: a hand pressing itself.)
		var fix := d * k
		pos[hand] += fix * .85
		for i: int in [R.HIP_L, R.HIP_R, R.SH_L, R.SH_R]:
			pos[i] -= fix * .15 * .25
	for i in aim_override.size():
		var w := aim_override[i]
		if w != Vector3.INF:
			pos[i] += (w - pos[i]) * minf(1.0, stiff(GROUP_OF[i]) * 1.4)
	for i: int in pins:
		var at: Vector3 = pins[i]
		pos[i] = at


## No limb inside the torso (Ragdoll's), but the hand on a wound presses on it.
func _keep_out() -> void:
	var mid := middle()
	var skip := -1
	if clutch_hand >= 0 and age < clutch_until:
		skip = R.HAND_L if clutch_hand == 0 else R.HAND_R
	for i in range(R.ELBOW_L, R.FOOT_R + 1):
		if i == skip or i == skip - 1:
			# (The hand and its elbow: the arm folded onto the body.)
			continue
		var off := pos[i] - mid
		var d := off.length()
		var least := _inside[i]
		if d < least and d > 1e-6:
			pos[i] = mid + off * (least / d)


## How much a leg's muscles hold (a buckled knee gives).
func _leg_give(leg: int) -> float:
	if _buckled(leg):
		return BUCKLE_GIVE
	return 1.0


func _buckled(leg: int) -> bool:
	if down > 0 and pitched:
		# Pitched over: down on both knees.
		return true
	return buckle_leg == leg and (age < buckle_until or down > 0)


## The feet: a planted one stays where it stands (its grip), unless the leg
## is pulled past its length (it drags); the swinging one goes on its arc.
func _feet(swinging := true) -> void:
	for f in 2:
		var i: int = FEET[f]
		if f == swing_foot:
			if not swinging:
				continue
			var k := clampf(_swing_t, 0.0, 1.0)
			var at := _swing_from.lerp(_swing_to, k * k * (3.0 - 2.0 * k))
			at.z += LIFT * size * sin(PI * k)
			var pull := minf(1.0, stiff(LEGS) * 1.6 + .25) if muscles else 0.0
			var d := at - pos[i]
			pos[i] += d * pull
			pos[KNEES[f]] += d * pull * .3
			continue
		if planted[f] == Vector3.INF:
			continue
		var hip: int = HIPS[f]
		var reach := _leg * 1.01
		var p := planted[f]
		var hp := pos[hip]
		if hp.distance_to(p) > reach:
			# Pulled past its leg: it drags along the floor (no grip holds that).
			var flat := Vector2(p.x - hp.x, p.y - hp.y)
			var tall := hp.z - p.z
			var across := sqrt(maxf(0.0, reach * reach - tall * tall))
			if flat.length() > across and flat.length() > 1e-5:
				flat = flat.normalized() * across
				planted[f] = Vector3(hp.x + flat.x, hp.y + flat.y, p.z)
				p = planted[f]
		pos[i] = Vector3(p.x, p.y, maxf(pos[i].z, p.z))
		old[i] = Vector3(p.x, p.y, old[i].z)


## Every ball on the floor or over it; one on it grips (friction).
func _floor_all() -> void:
	for i in R.POINTS:
		var low := floor_z + (_foot_up(i) if i == R.FOOT_L or i == R.FOOT_R else radius[i])
		var p := pos[i]
		if p.z < low:
			pos[i] = Vector3(p.x, p.y, low)
			var o := old[i]
			old[i] = Vector3(lerpf(o.x, p.x, .35), lerpf(o.y, p.y, .35), o.z)


## A foot's point put on the floor (as high over it as the pose stands the
## foot: its ball is bigger than the boot is tall).
func _floored(p: Vector3, i: int) -> Vector3:
	return Vector3(p.x, p.y, floor_z + _foot_up(i))


func _foot_up(i: int) -> float:
	var t := target[i].z - floor_z if target.size() > i else radius[i]
	return clampf(t, radius[i] * .4, radius[i])


## Whether ball i touches the floor.
func on_floor(i: int) -> bool:
	return pos[i].z <= floor_z + radius[i] + .005


## A ball held to a world point (a grab's hand; T11) and let go.
func pin(i: int, at: Vector3) -> void:
	pins[i] = at


func unpin(i: int) -> void:
	pins.erase(i)


## An impulse at map point `at` along `dir` of `strength` (Ragdoll.strike).
func push_at(at: Vector3, dir: Vector3, strength: float) -> void:
	strike(at, dir, strength)


## The balance controller: the capture point (the middle plus its speed over
## the pendulum's rate) outside the planted feet (more than MARGIN off the
## line between them) swings the foot that steps best to it; its swing ends
## planted. Off his feet (down) no step is taken; with no reel the feet go
## back with the pose (free).
func _balance() -> void:
	if swing_foot >= 0:
		_swing_t += STEP / SWING_FOR
		if _swing_t >= 1.0:
			var f := swing_foot
			planted[f] = _floored(pos[FEET[f]], FEET[f])
			if _catching:
				step_log.append([age, f, _swing_from, planted[f]])
				catches += 1
				_last_foot = f
			swing_foot = -1
		return
	if down > 0 or not muscles:
		# Off his feet: the feet lie where they fall (no grip to plant).
		if down > 0:
			planted[0] = Vector3.INF
			planted[1] = Vector3.INF
		return
	if down < 0:
		# Getting up: the feet plant where they are on the floor.
		for f in 2:
			if planted[f] == Vector3.INF and on_floor(FEET[f]):
				planted[f] = _floored(pos[FEET[f]], FEET[f])
		return
	var reel := reeling or age - hit_age < RECOVER
	if not reel:
		# Back on his feet: a foot off its place in the pose steps back to
		# it; then the feet go with the pose (held where it has them on the
		# floor, free where it lifts them).
		for f in 2:
			var t := target[FEET[f]]
			var p := planted[f]
			if p != Vector3.INF and Vector2(t.x - p.x, t.y - p.y).length() > .12 * size:
				if _stepped_back[f] == 0:
					# (One step back to its place; if that falls short, it
					# goes with the pose from there.)
					_stepped_back[f] = 1
					_start_swing(f, _floored(t, FEET[f]))
					_catching = false
					return
		for f in 2:
			var t := target[FEET[f]]
			var low := t.z - floor_z < radius[FEET[f]] * 1.5
			planted[f] = _floored(t, FEET[f]) if low else Vector3.INF
		return
	if planted[0] == Vector3.INF or planted[1] == Vector3.INF:
		for f in 2:
			if planted[f] == Vector3.INF:
				planted[f] = _floored(pos[FEET[f]], FEET[f])
	var mid := middle()
	var xi := Vector3(mid.x, mid.y, 0.0) + Vector3(mid_speed.x, mid_speed.y, 0.0) / omega
	var a := Vector2(planted[0].x, planted[0].y)
	var b := Vector2(planted[1].x, planted[1].y)
	var c := Vector2(xi.x, xi.y)
	# The pose is balanced as the animation stands it: its middle where it
	# is over its feet. Off that by more than MARGIN, a step.
	var mid_t := (target[R.HIP_L] + target[R.HIP_R] + target[R.SH_L] + target[R.SH_R]) * .25
	var feet_t := (target[R.FOOT_L] + target[R.FOOT_R]) * .5
	var lean := Vector2(mid_t.x - feet_t.x, mid_t.y - feet_t.y)
	var off := c - ((a + b) * .5 + lean)
	if off.length() <= MARGIN * size:
		return
	# The foot that steps: the other one than the last step's (a stumble
	# goes foot over foot); the first, the one nearer the fall.
	var f := 0
	if _last_foot >= 0:
		f = 1 - _last_foot
	else:
		f = 0 if a.distance_to(c) < b.distance_to(c) else 1
	var stance := b if f == 0 else a
	# Put down so the feet's middle comes under the capture point as the
	# pose stands over its feet, no nearer the other foot than a boot's
	# width, no further than the leg reaches from the hips.
	var to := (c - lean) * 2.0 - stance
	var apart := to - stance
	var least := (radius[FEET[0]] + radius[FEET[1]]) * 1.1
	if apart.length() < least:
		var away := Vector2(pos[FEET[f]].x - stance.x, pos[FEET[f]].y - stance.y)
		if away.length() < 1e-4:
			away = Vector2(off.y, -off.x)
		to = stance + away.normalized() * least
	var hip := pos[HIPS[f]]
	var flat := Vector2(to.x - hip.x, to.y - hip.y)
	var most := _leg * .85
	if flat.length() > most:
		flat = flat.normalized() * most
		to = Vector2(hip.x, hip.y) + flat
	_start_swing(f, _floored(Vector3(to.x, to.y, 0.0), FEET[f]))
	_catching = true
	_stepped_back = PackedByteArray([0, 0])


func _start_swing(f: int, to: Vector3) -> void:
	swing_foot = f
	_swing_from = pos[FEET[f]]
	_swing_to = to
	_swing_t = 0.0
	planted[f] = Vector3.INF


## The clutching hand's distance from the wound (map units; INF: none).
func hand_gap() -> float:
	if clutch_hand < 0:
		return INF
	var r := _torso_frame(pos)
	var hips := (pos[R.HIP_L] + pos[R.HIP_R]) * .5
	var hand := R.HAND_L if clutch_hand == 0 else R.HAND_R
	return pos[hand].distance_to(hips + r * wound)
