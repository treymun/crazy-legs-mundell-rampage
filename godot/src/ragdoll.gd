## A dead body's limbs flopping (looks only: the 3D view's ActorView drives
## one per body it shows; play's body, features/corpses.gd, says where the
## body is and the ragdoll follows it).
##
## Fifteen balls (RagdollRig: hips, shoulders, belly, back, head, elbows,
## hands, knees, feet; two more for each piece of gear it lets go of, the gun
## or the saw falling on its own) held together by links: the torso rigid,
## each limb half a rigid stick, ranges for the neck, the elbows, the knees
## and the hips (a knee folds no further than about 130 degrees, only
## forwards and never sideways; a thigh swings forwards and out within a
## hip's reach, never up through the belly or far behind; an elbow only
## backwards), and no limb inside the torso, the head or the other leg. Each
## ball has its weight (the hips and the torso lead, the hands and feet
## follow), and for the first fraction of a second the muscles still hold the
## pose it died in, going slack (`tone`); a little of a lying body's ease
## (knees a touch bent, hips straight) pulls a heap out flat for a while
## after. Solved by position steps (Verlet: each ball keeps the move it made
## last step, gravity added; then the links are put right a few passes), a
## few small steps a frame, like the bowling pins' solver
## (range_pin_physics.gd) in spirit: contacts by sphere, friction on the
## floor, and asleep (no cost at all) once nothing moves. The kill strikes it
## where the hit landed (`strike`: an impulse at a point, along a way, of a
## strength), by the gun and the zone (`knock`).
##
## The world is the level's real shape, as Tumble sees it: each ball lands on
## the highest floor under it (a deck, a stair tread, a ramp, a counter top,
## the ground), never comes up through a deck's underside, never into a wall,
## a slab's side or a rail (rails let a body by in tumble.gd; here a body's
## legs catch on one and it goes over it head first). The level's questions
## (plain floor, walls, rails, each ball's floor kept while it stays put) are
## the shared physics core's (phys_core.gd), and so is the space it shares
## with the wreck pieces: a body lies on a piece, a piece on a body. Map
## coordinates throughout: x and y across the floor, z up.
class_name Ragdoll
extends RefCounted

const STEP := 1.0 / 60.0
## At most this many steps a frame (a slow frame drops the rest of the time).
const MOST_STEPS := 3
const GRAVITY := 9.4
## Each step's move kept in the air, and the slide kept on the floor.
const AIR := .992
const GRIP := .4
## A sliding ball's loss to friction (map units a second a second).
const SLIDE_DRAG := 7.0
## Each step's move kept by every ball of a body with half its balls or more
## on the floor.
const LYING_KEEP := .8
const PASSES := 4
## Asleep once no ball moves more than SLEEP_MOVE a step for SLEEP_AFTER
## seconds, or after MOST_AWAKE seconds whatever (a jitter never costs for ever).
const SLEEP_MOVE := .0008
const SLEEP_LYING := .004
## (only once it has been dead this long: a leg balanced up or a heap going
## over moves slowly at first and must not be laid still in the act).
const SLEEP_LYING_FROM := 2.0
const SLEEP_AFTER := .5
const MOST_AWAKE := 8.0
## The torso's middle may lag play's body by this much before it is pulled.
const SLACK := .3
const PULL := 8.0
## The model's shape is kept out of the floor once a ball is this near it
## (model units), to within HULL_SLACK (map units).
const HULL_NEAR := .5
const HULL_SLACK := .002
## A ball on a floor steeper than this (its fall a unit across) is pulled
## down it by the rest of the slope's share of gravity.
const SLIDE_FROM := .25
## A ball found inside something is lifted onto a top at most this far over
## it (a stair's tread over the boot in its riser).
const STEP_UP := .3
## Striking a body lying still faster than this (a step) wakes it.
const WAKE_HIT := .02
## Each of the rig's segments' balls (RagdollRig.ENDS order): the torso's
## six, the head, each limb half's two ends.
const SEG_BALLS := [
	[0, 1, 2, 3, 13, 14], [4], [2, 5], [5, 6], [3, 7], [7, 8], [0, 9], [9, 10], [1, 11], [11, 12]
]
## Each ball's weight (RagdollRig order: hips, shoulders, head, elbows,
## hands, knees, feet, belly, back): the torso and hips lead, a hand or a foot
## is pulled along; gear past them weighs GEAR_WEIGHT a ball.
const WEIGHTS := [1.4, 1.4, 1.2, 1.2, .9, .6, .45, .6, .45, .9, .6, .9, .6, 1.4, 1.4]
const GEAR_WEIGHT := .6
## The muscles hold the pose it died in this hard at first (a share of the
## error put right each pass), going slack over the death's `fade` seconds;
## a lying body's ease pulls this hard, from EASE_FROM to EASE_TO seconds
## (gone after: it never keeps a body stirring).
const HOLD := .3
const EASE := .035
const EASE_FROM := .5
const EASE_TO := 3.0
## How far round a struck point the strike reaches (model units: a hit on the
## head moves the head, the neck and a little of the shoulders).
const STRIKE_REACH := .22
const STRIKE_MOST := 4.0
## The most a piece of gear moves (map units a second).
const GEAR_FAST := 4.5
const GEAR_WALL := .07
## A knee may be this share of the leg's length behind straight.
const KNEE_PAST := .05
## Nothing dead stands or sits up (_slump): a straight leg under an upright
## body folds at the knee, and a torso more upright than SLUMP_UP goes over
## the way it leans (the kill's way when it leans no way), at up to
## SLUMP_PULL map units a second a second, for SLUMP_FOR seconds.
const SLUMP_UP := .55
## Head this far down from its hips (the torso's fall) it lies out flat; a
## thigh this near straight down under a torso not upright is kneeling.
const HEADLONG := .2
const KNEELING := .75
const SLUMP_PULL := 12.0
const KNEE_GIVE := 4.0
const SLUMP_FOR := 4.0
## A thigh's swing within the hip's reach (radians from straight down, the
## body standing): forwards up to HIP_UP, behind HIP_BACK; its spread out of
## the body's middle HIP_OUT, across the other leg HIP_IN. Held as links (the
## knee no nearer the back, the belly or the other hip than at those turns,
## no further from the other hip): they push the torso back as much as the
## leg, so they never set a body turning of themselves.
const HIP_UP := 1.9
const HIP_BACK := .45
const HIP_OUT := .8
const HIP_IN := .2
## Play's body's move is given whole to the torso and to a limb up in the
## air; a limb on the floor takes this share of it and is dragged the rest.
const DRAG := .8

const R := preload("res://src/view3d/ragdoll_rig.gd")
const Corpses := preload("res://src/features/corpses.gd")

var pos := PackedVector3Array()
var old := PackedVector3Array()
var radius := PackedFloat32Array()
## The links: points a and b, and how near and far apart they may be.
var la := PackedInt32Array()
var lb := PackedInt32Array()
var lmin := PackedFloat32Array()
var lmax := PackedFloat32Array()
var awake := true
var still := 0.0
var age := 0.0
## Steps taken so far (the checks read it: none while asleep).
var steps := 0
## Whose it is: the moment the body died, the model's turn and size.
var died_at := -1.0
var turn := 0.0
var size := 1.0
## Where play's body was last frame (map), INF before the first.
var body := Vector3.INF
## Play's body is up off the real floor (thrown, floating): the torso is
## carried at its height, no lower than `carry`.
var carry := -INF
var _left := 0.0
var _torso_r := .1
## How near the torso's middle each limb ball may come (_links).
var _inside := PackedFloat32Array()
## Each ball's 1/weight (WEIGHTS), and where each was before the last step
## (the view draws part way from there to `pos`: smooth in slow motion).
var inv_mass := PackedFloat32Array()
var prev := PackedVector3Array()
## Soft links: points a and b, the distance the muscles hold (the pose it
## died in) and a lying body's ease's (-1: none).
var sa := PackedInt32Array()
var sb := PackedInt32Array()
var s_hold := PackedFloat32Array()
var s_ease := PackedFloat32Array()
## Seconds the muscles take to go slack (the death's own; `knock` sets it).
var fade := .18
## Which balls touched a floor last step (a limb on the floor is dragged).
var _touch := PackedByteArray()
## The way the kill sent it (flat, map): a dead body upright with nothing to
## lean it goes over this way (_slump).
var _fall_way := Vector3.ZERO
## Play's body's move, given on the next step.
var _shove := Vector3.ZERO
## The torso's pull back toward play's body (SLACK), given whole to every
## ball (it puts right a lag, it is no move of the body's own).
var _nudge := Vector3.ZERO
## Each ball's floor (kept while it stays put) and roof this step.
var _fl := PhysCore.Floors.new()
var _roofs := PackedFloat32Array()
## The rig it hangs on: its segments' outermost points keep the model's
## shape (a shoulder, a boot's toe, a hat's brim) out of the floor, not only
## the balls (_hull_floor). Null: the balls alone.
var rig: RagdollRig
## The points in the view's axes (y up), for the rig's frames.
var _up := PackedVector3Array()
## Each ball's floor's fall (Tumble.slope), asked with its floor.
var _slopes := PackedVector2Array()
## How far its balls reach from its torso's middle (kept each step).
var extent := 1.0
## The level it lies on (set each step: the wreck pieces ask for those on
## theirs).
var level: LevelData
## The body's own balls (the gear's come after; a beast's, src/beast_doll.gd,
## has more and no gear), and per ball whether it is a limb's (dragged on the
## floor, DRAG) or the core's (carried at play's body's height); each
## segment's balls and ends (RagdollRig.ENDS for a body on two legs) and the
## torso's belly and back (pass 13).
var body_n := R.POINTS
var _limb := PackedByteArray()
var _core := PackedByteArray()
var _seg_balls: Array = SEG_BALLS
var _ends: Array = R.ENDS
var _belly := R.BELLY
var _back := R.BACK
## Other balls held in the torso, lifted with its belly and back by its shape
## (a beast's legs' roots).
var _torso_more: Array[int] = []
## The share of its balls on the floor that make it lying (its motion dies
## away, a tremble is rest): half a person's; a beast on its side has its
## legs up off it.
var down_share := .5

## The ragdolls about (ActorLayer3D sets it each frame: those shown and those
## kept out of sight): a body lies on another rather than through it.
static var others: Array = []

## Steps every ragdoll on screen may still take this frame (ActorLayer3D
## sets it each frame from effects.cfg [ragdoll] budget).
static var budget := 1 << 30


## A model point under the model's transform `xf` (the view's, y up) as a map point.
static func to_map(xf: Transform3D, p: Vector3) -> Vector3:
	var g := xf * p
	return Vector3(g.x, g.z, g.y)


## A ragdoll for a body hung on `rig`, its points at `model` (model space;
## the gear's sticks after the rig's points, else as it stood) under the
## model's transform `xf`.
static func made(rig: RagdollRig, xf: Transform3D, model: PackedVector3Array) -> Ragdoll:
	var doll := Ragdoll.new()
	var scale := xf.basis.get_scale().x
	var at := PackedVector3Array()
	var rest := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in R.POINTS:
		at.append(to_map(xf, model[i]))
		rest.append(rig.points[i] * scale)
		radii.append(rig.radii[i] * scale)
	for g in rig.gear_bones.size():
		for k in RagdollRig.GEAR_BALLS:
			var i := R.POINTS + g * RagdollRig.GEAR_BALLS + k
			var p := model[i] if model.size() > i else rig.gear_ends[i - R.POINTS]
			at.append(to_map(xf, p))
			rest.append(rig.gear_ends[i - R.POINTS] * scale)
			radii.append(rig.gear_radius[g] * scale)
	doll.size = scale
	doll.rig = rig
	doll.start(at, radii, rest)
	return doll


## The kill (effects.cfg [ragdoll]): struck where the hit landed (the zone
## Enemy.last_zone names, on the side toward the shot) along the shot by the
## gun's `hit`, the whole body carried along it (`carry`) and up (`lift`),
## the knees given (`buckle`) and the body turned about itself (`spin`, a
## way of the death's own); the zone adds to it (zone_<zone>: the hit's
## share, buckle and spin added, and how quick the muscles go). Each ball a
## little differently, all by `dice` (looks only): no two deaths alike.
func knock(e: Enemy, dice: RandomNumberGenerator) -> void:
	var from := e.killed_from
	var how := e.killed_by
	var blast := (how == "blast" or how == "energy") and e.blast_at != Vector2.INF
	if blast:
		from = e.blast_at
	var away := Vector2(e.x, e.y) - from
	var key := how
	if how == "shotgun" and away.length() < Corpses.POINT_BLANK:
		key = "shotgun_near"
	var row: Array = Effects.RAGDOLL.get(
		key, Effects.RAGDOLL.get("default", [1.4, .5, 0.0, .6, .4])
	)
	var zone := e.last_zone if e.last_zone != "" and not blast else "body"
	var by: Array = Effects.RAGDOLL.get("zone_" + zone, [1.0, 0.0, 0.0, .18])
	var spread: float = Effects.RAGDOLL.get("spread", .3)
	var hit: float = row[0]
	var carry: float = row[1]
	var lift: float = row[2]
	var buckle: float = row[3]
	var spin: float = row[4]
	var share: float = by[0]
	var more_buckle: float = by[1]
	var more_spin: float = by[2]
	var slack: float = by[3]
	hit *= share
	buckle += more_buckle
	spin += more_spin
	fade = slack * dice.randf_range(.7, 1.4)
	if away.length() < .01:
		away = Vector2.from_angle(e.angle + PI)
	away = away.normalized()
	var dir := Vector3(away.x, away.y, 0.0)
	_fall_way = dir
	# The side toward the shot: its arm or leg is the one struck.
	var right := pos[R.SH_R] - pos[R.SH_L] + pos[R.HIP_R] - pos[R.HIP_L]
	right.z = 0.0
	var facing := -right.normalized().dot(dir)
	var on_right := facing > .25 or (absf(facing) <= .25 and dice.randf() < .5)
	var at := middle()
	match zone:
		"head":
			at = pos[R.HEAD]
		"arms":
			at = pos[R.ELBOW_R if on_right else R.ELBOW_L]
		"legs":
			var knee := R.KNEE_R if on_right else R.KNEE_L
			at = pos[knee].lerp(pos[R.HIP_R if on_right else R.HIP_L], dice.randf_range(0.0, .5))
		_:
			# The chest or the belly, a little toward the struck side.
			var sh := (pos[R.SH_L] + pos[R.SH_R]) * .5
			at = (pos[R.BELLY] + pos[R.BACK]) * .5
			at = at.lerp(sh, dice.randf_range(.1, .8))
			at += (pos[R.SH_R] - pos[R.SH_L]) * dice.randf_range(-.25, .25)
	if blast:
		# From under and beside it: the ball nearest the blast takes it.
		var near := 0
		var blast_at := Vector3(from.x, from.y, pos[R.FOOT_L].z)
		for i in R.POINTS:
			if pos[i].distance_squared_to(blast_at) < pos[near].distance_squared_to(blast_at):
				near = i
		at = pos[near]
		dir = (dir + Vector3(0.0, 0.0, .6)).normalized()
	var wobble := Vector3(
		dice.randf_range(-.3, .3), dice.randf_range(-.3, .3), dice.randf_range(-.15, .2)
	)
	strike(at, (dir + wobble * spread).normalized(), hit)
	# (Map space is the model's mirrored, y and z swapped: ahead is right x up.)
	var ahead := Vector3(right.y, -right.x, 0.0).normalized()
	var turn := spin * (1.0 if dice.randf() < .5 else -1.0) * dice.randf_range(.5, 1.3)
	var mid := middle()
	for i in pos.size():
		var v := dir * carry * (1.0 + dice.randf_range(-spread, spread))
		v.z += lift * (1.0 + dice.randf_range(-spread, spread))
		# About itself: a turn round the upright through its middle.
		var off := pos[i] - mid
		v += Vector3(-off.y, off.x, 0.0) * turn
		if i == R.KNEE_L or i == R.KNEE_R:
			var own := 1.0
			if zone == "legs":
				# The struck leg goes out from under it, the other folds.
				own = 1.6 if (i == R.KNEE_R) == on_right else .7
			v += ahead * buckle * own * (1.0 + dice.randf_range(-spread, spread))
			v.z -= buckle * .4 * own
		elif i <= R.HEAD or i == R.BELLY or i == R.BACK:
			v.z -= buckle * .45
		add_speed(i, v)


## An impulse at map point `at` along `dir` of `strength` (the speed it gives
## a ball weighing 1 or less there, a heavier one less): the balls near the
## point take it by how near (STRIKE_REACH); the links carry it on to the
## rest, so the part struck moves first and drags the torso, the torso struck
## moves the whole body. No ball is sent faster than STRIKE_MOST (a light
## hand flung at 30 went through walls). Looks only: a shot, a blast, a piece.
func strike(at: Vector3, dir: Vector3, strength: float) -> void:
	var reach := STRIKE_REACH * size
	for i in pos.size():
		var d2 := pos[i].distance_squared_to(at) / (reach * reach)
		if d2 > 6.0:
			continue
		var v := dir * strength * exp(-d2) * minf(inv_mass[i], 1.0)
		add_speed(i, v.limit_length(STRIKE_MOST))
	wake()


## Every ball moving at `v` (the body was walking or running when it died:
## it falls on with it).
func drift(v: Vector3) -> void:
	for i in pos.size():
		add_speed(i, v)


## Each ball going on at its own speed `v` (map units a second: a boss's
## scripted fall handed over, ActorView.BOSS_HANDOVER); it falls the way they
## go on.
func carry_on(v: PackedVector3Array) -> void:
	var sum := Vector3.ZERO
	for i in mini(v.size(), pos.size()):
		add_speed(i, v[i])
		sum += v[i]
	sum.z = 0.0
	if sum.length_squared() > 1e-6:
		_fall_way = sum.normalized()
	wake()


## The share of its speed a piece of gear keeps this step (1 unless its
## fastest ball goes over GEAR_FAST), for its ball i.
func _gear_slow(i: int) -> float:
	var first := body_n + (i - body_n) / RagdollRig.GEAR_BALLS * RagdollRig.GEAR_BALLS
	var most := 0.0
	for k in range(first, mini(first + RagdollRig.GEAR_BALLS, pos.size())):
		most = maxf(most, pos[k].distance_to(old[k]) * AIR)
	return minf(1.0, GEAR_FAST * STEP / most) if most > 1e-9 else 1.0


## Give ball i this much more velocity (map units a second).
func add_speed(i: int, v: Vector3) -> void:
	old[i] -= v * STEP


## Where ball i is drawn: `alpha` of the way from where it was before the
## last step to where it is (the time left over past the last step).
func shown(i: int, alpha: float) -> Vector3:
	return prev[i].lerp(pos[i], alpha) if awake else pos[i]


## The time left over past the last step, as a share of a step.
func alpha() -> float:
	return clampf(_left / STEP, 0.0, 1.0)


## Put its links right where it starts (the pose the animation left need not
## hold exactly to them) without giving any ball a speed for it.
func fit(passes := 8) -> void:
	var before := pos.duplicate()
	for _k in passes:
		_links()
		_hinges()
	for i in pos.size():
		old[i] += pos[i] - before[i]
		prev[i] = pos[i]
	# What it holds now is what the muscles hold.
	for k in sa.size():
		s_hold[k] = pos[sa[k]].distance_to(pos[sb[k]])


## Let it fall still at once (a body first seen long after it died): up to
## `most` steps, stopping when it sleeps.
func settle(world: LevelData, most := 240, rest := false) -> void:
	if rest:
		# Lowered at once till its lowest ball is on the floor under it.
		var gap := INF
		for i in pos.size():
			var p := pos[i]
			var under := Tumble.floor_at(world, p.x, p.y, p.z - radius[i] + .03, radius[i] * .6)
			gap = minf(gap, p.z - radius[i] - under)
		if gap > 0.0 and gap < INF:
			for i in pos.size():
				pos[i] = pos[i] - Vector3(0.0, 0.0, gap)
				old[i] = pos[i]
	for _k in most:
		if not awake:
			return
		step(world)
	# `rest`: it lies as it is now from here on (it never stirs in sight).
	if rest and awake:
		var touching := PackedByteArray()
		touching.resize(pos.size())
		_lay(world, false, touching)


## Start from points `at` (map) with radii `radii`, the links' lengths taken
## from the rig's points at rest `rest` (map units).
func start(at: PackedVector3Array, radii: PackedFloat32Array, rest: PackedVector3Array) -> void:
	pos = at.duplicate()
	old = at.duplicate()
	prev = at.duplicate()
	radius = radii.duplicate()
	_torso_r = radius[R.HIP_L]
	var rest_mid := (rest[R.HIP_L] + rest[R.HIP_R] + rest[R.SH_L] + rest[R.SH_R]) * .25
	_inside.resize(pos.size())
	for i in pos.size():
		_inside[i] = minf(_torso_r + radius[i], rest[i].distance_to(rest_mid) * .95)
	inv_mass.resize(pos.size())
	for i in pos.size():
		var weight: float = WEIGHTS[i] if i < R.POINTS else GEAR_WEIGHT
		inv_mass[i] = 1.0 / weight
	la.clear()
	lb.clear()
	lmin.clear()
	lmax.clear()
	sa.clear()
	sb.clear()
	s_hold.clear()
	s_ease.clear()
	var corners: Array[int] = [R.HIP_L, R.HIP_R, R.SH_L, R.SH_R]
	for i in 4:
		for k in range(i + 1, 4):
			_rigid(rest, corners[i], corners[k])
	for inner: int in [R.BELLY, R.BACK]:
		for corner: int in corners:
			_rigid(rest, inner, corner)
	_rigid(rest, R.BELLY, R.BACK)
	_rigid(rest, R.HEAD, R.SH_L)
	_rigid(rest, R.HEAD, R.SH_R)
	_range(rest, R.HEAD, R.HIP_L, .88, 1.03)
	_range(rest, R.HEAD, R.HIP_R, .88, 1.03)
	for limb: Array in [
		[R.SH_L, R.ELBOW_L, R.HAND_L, .4],
		[R.SH_R, R.ELBOW_R, R.HAND_R, .4],
		[R.HIP_L, R.KNEE_L, R.FOOT_L, .45],
		[R.HIP_R, R.KNEE_R, R.FOOT_R, .45]
	]:
		var a: int = limb[0]
		var m: int = limb[1]
		var b: int = limb[2]
		var fold: float = limb[3]
		_rigid(rest, a, m)
		_rigid(rest, m, b)
		var reach := rest[a].distance_to(rest[m]) + rest[m].distance_to(rest[b])
		if _stiff(a):
			# One piece to its end (a whole arm modelled bent): no bend at all.
			_rigid(rest, a, b)
		else:
			_link(a, b, reach * fold, reach)
	# Each thigh within its hip's reach (HIP_*), as links.
	for leg: Array in [[R.HIP_L, R.KNEE_L, R.HIP_R, 1.0], [R.HIP_R, R.KNEE_R, R.HIP_L, -1.0]]:
		var hip: int = leg[0]
		var knee: int = leg[1]
		var other: int = leg[2]
		var side: float = leg[3]
		var t := rest[knee] - rest[hip]
		var back := rest[hip] + Basis(Vector3.RIGHT, HIP_BACK) * t
		var bent := rest[hip] + Basis(Vector3.RIGHT, -HIP_UP) * t
		var wide := rest[hip] + Basis(Vector3.BACK, side * HIP_OUT) * t
		var narrow := rest[hip] + Basis(Vector3.BACK, -side * HIP_IN) * t
		var now_back := rest[knee].distance_to(rest[R.BACK])
		var now_belly := rest[knee].distance_to(rest[R.BELLY])
		var now_other := rest[knee].distance_to(rest[other])
		_link(knee, R.BACK, minf(back.distance_to(rest[R.BACK]), now_back), INF)
		_link(knee, R.BELLY, minf(bent.distance_to(rest[R.BELLY]), now_belly), INF)
		_link(
			knee,
			other,
			minf(narrow.distance_to(rest[other]), now_other),
			maxf(wide.distance_to(rest[other]), now_other)
		)
	# The hips fold no further than a deep crouch.
	_range(rest, R.SH_L, R.FOOT_L, .42, 1.2)
	_range(rest, R.SH_R, R.FOOT_R, .42, 1.2)
	# Nothing through anything else: the knees and feet apart, the hands off
	# the head and the hips.
	for pair: Array in [
		[R.KNEE_L, R.KNEE_R],
		[R.FOOT_L, R.FOOT_R],
		[R.HAND_L, R.HEAD],
		[R.HAND_R, R.HEAD],
		[R.HAND_L, R.HAND_R],
		[R.ELBOW_L, R.HEAD],
		[R.ELBOW_R, R.HEAD]
	]:
		var a: int = pair[0]
		var b: int = pair[1]
		# (No nearer than they stand, at most: hands on a gun stand together.)
		_link(a, b, minf((radius[a] + radius[b]) * .9, rest[a].distance_to(rest[b]) * .95), INF)
	# Each piece of gear: a rigid stick of its own, loose of the body.
	for k in range(R.POINTS, pos.size() - 2, RagdollRig.GEAR_BALLS):
		_rigid(rest, k, k + 1)
		_rigid(rest, k + 1, k + 2)
		_rigid(rest, k, k + 2)
	# The muscles: across each knee, elbow and hip, the knees apart. A lying
	# body's ease: the knees a touch bent, the hips straight, the knees no
	# wider than standing.
	for leg: Array in [
		[R.HIP_L, R.KNEE_L, R.FOOT_L, R.SH_L], [R.HIP_R, R.KNEE_R, R.FOOT_R, R.SH_R]
	]:
		var hip: int = leg[0]
		var knee: int = leg[1]
		var foot: int = leg[2]
		var sh: int = leg[3]
		var reach := rest[hip].distance_to(rest[knee]) + rest[knee].distance_to(rest[foot])
		if not _stiff(hip):
			_soft(hip, foot, reach * .95)
		_soft(sh, knee, rest[sh].distance_to(rest[knee]) * .97)
	for arm: Array in [[R.SH_L, R.ELBOW_L, R.HAND_L], [R.SH_R, R.ELBOW_R, R.HAND_R]]:
		var sh: int = arm[0]
		var elbow: int = arm[1]
		var hand: int = arm[2]
		var hip := R.HIP_L if sh == R.SH_L else R.HIP_R
		var reach := rest[sh].distance_to(rest[elbow]) + rest[elbow].distance_to(rest[hand])
		# An arm lying by its side, a little bent (not left stuck up).
		if not _stiff(sh):
			_soft(sh, hand, reach * .9)
		_soft(hip, elbow, rest[hip].distance_to(rest[elbow]) * 1.1)
	_soft(R.KNEE_L, R.KNEE_R, rest[R.KNEE_L].distance_to(rest[R.KNEE_R]))
	_soft(R.HEAD, R.BELLY, -1.0)
	body_n = R.POINTS
	_limb.resize(pos.size())
	_core.resize(pos.size())
	for i in pos.size():
		_limb[i] = 1 if (i >= R.ELBOW_L and i <= R.FOOT_R) or i >= R.POINTS else 0
		_core[i] = 1 if i <= R.SH_R or i == R.BELLY or i == R.BACK else 0
	awake = true
	still = 0.0
	age = 0.0
	_left = 0.0


## Whether the limb from point `root` (a shoulder or a hip) is one piece to
## its end (RagdollRig.stiff).
func _stiff(root: int) -> bool:
	var limb := [R.SH_L, R.SH_R, R.HIP_L, R.HIP_R].find(root)
	return rig != null and limb >= 0 and limb < rig.stiff.size() and rig.stiff[limb] == 1


func _soft(a: int, b: int, ease: float) -> void:
	sa.append(a)
	sb.append(b)
	s_hold.append(pos[a].distance_to(pos[b]))
	s_ease.append(ease)


func _rigid(rest: PackedVector3Array, a: int, b: int) -> void:
	var d := rest[a].distance_to(rest[b])
	_link(a, b, d, d)


func _range(rest: PackedVector3Array, a: int, b: int, near: float, far: float) -> void:
	var d := rest[a].distance_to(rest[b])
	_link(a, b, d * near, d * far)


func _link(a: int, b: int, near: float, far: float) -> void:
	la.append(a)
	lb.append(b)
	lmin.append(near)
	lmax.append(far)


## Give ball i a velocity (map units a second).
func push(i: int, v: Vector3) -> void:
	old[i] = pos[i] - v * STEP


## Move every ball by d on the next step (they keep it as velocity; walls
## and rails stop it as they stop any move).
func shift(d: Vector3) -> void:
	_shove += d


func wake() -> void:
	if not awake:
		awake = true
		still = 0.0
		age = minf(age, MOST_AWAKE - 2.0)


## The torso's middle.
func middle() -> Vector3:
	return (pos[R.HIP_L] + pos[R.HIP_R] + pos[R.SH_L] + pos[R.SH_R]) * .25


## Play's body is at `at` (map: its x, y and the height it lies at; `up` its
## height over the real floor under it): its move since last frame moves the
## ragdoll along, and the torso is kept within SLACK of it.
func follow(at: Vector3, up: float, dt: float) -> void:
	carry = at.z if up > .02 else -INF
	if body == Vector3.INF:
		body = at
		return
	var moved := at - body
	body = at
	var flat := Vector3(moved.x, moved.y, 0.0)
	if flat.length_squared() > 1e-8 or moved.z > .0005:
		wake()
		shift(flat + Vector3(0.0, 0.0, maxf(0.0, moved.z)))
	if not awake:
		return
	var off := Vector2(at.x, at.y) - Vector2(middle().x, middle().y)
	var far := off.length()
	if far > SLACK:
		var k := (far - SLACK) / far * minf(1.0, dt * PULL)
		_nudge += Vector3(off.x * k, off.y * k, 0.0)


## Step for dt seconds (in STEP steps, at most MOST_STEPS). Returns the steps.
func advance(world: LevelData, dt: float) -> int:
	if not awake and not _pieces_stir(world):
		return 0
	_left = minf(_left + dt, STEP * MOST_STEPS)
	var n := 0
	while _left >= STEP and budget > 0:
		_left -= STEP
		budget -= 1
		step(world)
		n += 1
		if not awake:
			break
	return n


## One step.
func step(world: LevelData) -> void:
	steps += 1
	age += STEP
	var g := GRAVITY * STEP * STEP
	var count := pos.size()
	if prev.size() != count:
		prev.resize(count)
	if _touch.size() != count:
		_touch.resize(count)
	# Play's body's move: whole to the torso and the head and to any limb up
	# in the air, DRAG of it to a limb on the floor (dragged the rest by the
	# links: a body slid along trails its arms and legs, not skates).
	var carried := PackedVector3Array()
	carried.resize(count)
	var slows := PackedFloat32Array()
	for k in range(body_n, count, RagdollRig.GEAR_BALLS):
		slows.append(_gear_slow(k))
	for i in count:
		var p := pos[i]
		prev[i] = p
		var v := (p - old[i]) * AIR
		if i >= body_n:
			# Gear let go of: never so fast it could skip a plank (its three
			# balls slowed alike, or the piece would be bent out of shape).
			v *= slows[(i - body_n) / RagdollRig.GEAR_BALLS]
		old[i] = p
		var share := 1.0
		if _touch[i] and _limb[i]:
			share = DRAG
		carried[i] = _shove * share + _nudge
		pos[i] = p + v + carried[i] - Vector3(0.0, 0.0, g)
	_shove = Vector3.ZERO
	_nudge = Vector3.ZERO
	var tone := HOLD * exp(-age / maxf(fade, .02))
	var ease := 0.0
	var lying := _slump(tone)
	if lying and age > EASE_FROM and age < EASE_TO:
		ease = EASE * minf(1.0, (EASE_TO - age) / (EASE_TO - EASE_FROM) * 2.0)
	level = world
	if _roofs.size() != count:
		_roofs.resize(count)
		_slopes.resize(count)
	_fl.size_to(count)
	var plain := _plain(world)
	if plain:
		# Open floor all round: the cells' own ground and roof, no walls.
		for i in count:
			var p := pos[i]
			var c := int(p.y) * world.width + int(p.x)
			_fl.keep(i, INF, INF, INF, world.ground[c])
			_roofs[i] = world.roof[c] if world.roof[c] > old[i].z + .01 else 0.0
			_slopes[i] = Vector2.ZERO
	else:
		for i in count:
			var p := pos[i]
			var o := old[i]
			var r := radius[i]
			var z := o.z - r + .03
			# The floor asked a step or two ago still holds for a ball that has
			# hardly moved across and is no higher than it was asked from.
			if _fl.held(i, p.x, p.y, z):
				continue
			var under := Tumble.floor_at(world, p.x, p.y, z, r * .6)
			_fl.keep(i, p.x, p.y, z, under)
			_roofs[i] = world.roof_over(p.x, p.y, o.z)
			_slopes[i] = Tumble.slope(world, p.x, p.y, under)
	_before_passes(world)
	var floors := _fl.floor
	var touching := PackedByteArray()
	touching.resize(count)
	for _pass in PASSES:
		_muscles(tone, ease)
		_links()
		_hinges()
		for i in count:
			if _floor(i, floors[i], _roofs[i]):
				touching[i] = 1
	_on_bodies(touching)
	_on_boxes(world, touching)
	_hull_floor(touching)
	# The floor's and the shape's lifts put right on the links once more (a
	# body landing hard had a limb stretched for a frame or two), then the
	# floor and the wreck pieces kept again.
	_links()
	for i in count:
		if _floor(i, floors[i], _roofs[i]):
			touching[i] = 1
	_on_boxes(world, touching)
	if not plain:
		# Last, nothing ends the step inside a wall, a slab's side or a rail
		# (the links may have pulled a ball in).
		for i in count:
			_walls(world, i)
			_floor(i, floors[i], _roofs[i])
	# Play's body's move (and the torso's pull back to it) carried the balls
	# along; it is not theirs to keep going with (each frame brings its own),
	# as far as they made it (a wall in the way kept them back).
	for i in count:
		var c := carried[i]
		var reach := c.length()
		if reach > 1e-6:
			var k := clampf((pos[i] - old[i]).dot(c / reach) / reach, 0.0, 1.0)
			old[i] += c * k
	# Friction: a ball on the floor slides, losing up to SLIDE_DRAG of its
	# speed a second a second (a body knocked off its feet slides out from
	# under itself rather than pivoting on stuck boots), and slow it stops
	# (GRIP); on a ramp steeper than SLIDE_FROM it is pulled down it a little
	# past what friction holds.
	var drag := SLIDE_DRAG * STEP * STEP
	for i in count:
		if touching[i]:
			var p := pos[i]
			var o := old[i]
			var run := Vector2(p.x - o.x, p.y - o.y)
			var speed := run.length()
			var keep := GRIP if speed < drag / (1.0 - GRIP) else 1.0 - drag / speed
			old[i] = Vector3(p.x - run.x * keep, p.y - run.y * keep, o.z)
			var fall := _slopes[i]
			var steep := fall.length()
			if steep > SLIDE_FROM:
				var pull := fall / steep * (steep - SLIDE_FROM) * GRAVITY * STEP * STEP
				old[i] -= Vector3(pull.x, pull.y, 0.0)
	# Mostly down on the floor: what is left of its motion dies away (a body
	# lying settles; the joints' stops and the floor never keep it trembling).
	var down := 0
	for i in count:
		_touch[i] = touching[i]
		down += touching[i]
	var settled := down >= count * down_share
	if settled:
		for i in count:
			old[i] = pos[i] - (pos[i] - old[i]) * LYING_KEEP
	var most := 0.0
	for i in count:
		most = maxf(most, pos[i].distance_squared_to(old[i]))
	# Lying (half its balls on the floor) a tremble of a few millimetres a
	# step is rest too (the model's shape against the floor rocks a ball).
	var calm := SLEEP_LYING if settled and age > SLEEP_LYING_FROM else SLEEP_MOVE
	if most < calm * calm:
		still += STEP
	else:
		still = 0.0
	if still > SLEEP_AFTER or age > MOST_AWAKE:
		_lay(world, plain, touching)


## Asleep where it is: laid on the floor really under each ball (not one
## asked a step or two ago) and the model's shape out of it, as it will lie
## from now on.
func _lay(world: LevelData, plain: bool, touching: PackedByteArray) -> void:
	awake = false
	_fl.size_to(pos.size())
	for i in pos.size():
		var p := pos[i]
		var r := radius[i]
		if not plain:
			var under := Tumble.floor_at(world, p.x, p.y, p.z - r + .03, r * .6)
			_fl.keep(i, INF, INF, INF, under)
			pos[i] = Vector3(p.x, p.y, maxf(p.z, _rest_floor(i, under) + r))
	for _k in 2:
		_hull_floor(touching)
		# (The links held again after the lifts, the floor kept: it never lies
		# with a limb pulled long.)
		_links()
		if not plain:
			for i in pos.size():
				_walls(world, i)
				var low := _rest_floor(i, _fl.floor[i]) + radius[i]
				pos[i] = Vector3(pos[i].x, pos[i].y, maxf(pos[i].z, low))
	for i in pos.size():
		old[i] = pos[i]
		if i < prev.size():
			prev[i] = pos[i]


## Once a step, its floors asked and before the links are put right (a
## beast finds which of its balls are in water here). None for a body on two
## legs.
func _before_passes(_world: LevelData) -> void:
	pass


## The floor ball i lies on, given the floor under it (a beast floats a
## ball in water a little under the surface).
func _rest_floor(_i: int, under: float) -> float:
	return under


## Each ball's floor this step, as the model's shape and the sleep keep it.
func _floors_now() -> PackedFloat32Array:
	return _fl.floor


## Other bodies (others) near: a ball inside one of theirs is pushed out of it
## (all the way when theirs lies still, half when both move), so a body
## comes to lie across another; lying on one holds it as a floor does. A
## hard knock wakes the body lying still.
func _on_bodies(touching: PackedByteArray) -> void:
	var mid := middle()
	extent = 0.0
	for i in pos.size():
		extent = maxf(extent, pos[i].distance_to(mid) + radius[i])
	if others.size() < 2:
		return
	for item: Variant in others:
		var o: Ragdoll = item
		if o == self or o.pos.is_empty() or o.level != level:
			# (A body of another level, kept by the view, is no body here.)
			continue
		var om := o.middle()
		var reach := extent + o.extent
		if absf(om.x - mid.x) > reach or absf(om.y - mid.y) > reach or absf(om.z - mid.z) > reach:
			continue
		var share := .5 if o.awake else 1.0
		for i in pos.size():
			var p := pos[i]
			var r := radius[i]
			if p.distance_to(om) > o.extent + r:
				continue
			for j in o.pos.size():
				var off := p - o.pos[j]
				var least := r + o.radius[j]
				var d2 := off.length_squared()
				if d2 >= least * least or d2 < 1e-10:
					continue
				var d := sqrt(d2)
				var n := off / d
				if not o.awake and (old[i] - p).dot(n) > WAKE_HIT:
					o.wake()
				p += n * (least - d) * share
				if n.z > .5:
					touching[i] = 1
			pos[i] = p


## Wreck pieces lying about (the level's PhysCore.Space): a ball inside one
## is pushed out of it (all the way when the piece lies still, half when it
## moves), and lying on one holds it as a floor does. A ball striking a piece
## at rest faster than WAKE_HIT wakes it and shoves it along (looks only).
func _on_boxes(world: LevelData, touching: PackedByteArray) -> void:
	var boxes := PhysCore.space(world).boxes
	if boxes.is_empty():
		return
	var mid := middle()
	for item: Variant in boxes:
		var b: PhysCore.Box = item
		var reach := extent + b.reach
		if (
			absf(b.p.x - mid.x) > reach
			or absf(b.p.y - mid.y) > reach
			or absf(b.p.z - mid.z) > reach
		):
			continue
		for i in pos.size():
			var p := pos[i]
			var r := radius[i]
			if p.distance_squared_to(b.p) > (b.reach + r) * (b.reach + r):
				continue
			var out := b.ball_out(p, r)
			var deep := out.length()
			if deep < 1e-6:
				continue
			var n := out / deep
			var hit := (old[i] - p).dot(n)
			if not b.awake and hit > WAKE_HIT:
				b.wake()
				b.v -= n * (hit / STEP) * .5
			pos[i] = p + out * (.5 if b.awake else 1.0)
			if n.z > .5:
				touching[i] = 1


## Whether a wreck piece near this body (asleep) is moving: what it lies on
## may be going, so it wakes.
func _pieces_stir(world: LevelData) -> bool:
	var space := PhysCore.space(world)
	if space.stirring == 0 or pos.is_empty():
		return false
	var mid := middle()
	for item: Variant in space.boxes:
		var b: PhysCore.Box = item
		var reach := extent + b.reach
		if (
			b.awake
			and absf(b.p.x - mid.x) < reach
			and absf(b.p.y - mid.y) < reach
			and absf(b.p.z - mid.z) < reach
		):
			wake()
			return true
	return false


## The model's own shape against the floor: each segment's outermost point
## lowest now (the rig's hull, turned as the view will turn that segment's
## parts) is kept out of the floor under its nearest ball, the segment's
## balls lifted as a stick (or the torso as a whole) would be about it. The
## lift stops the fall there (no bounce back up). Segments well over their
## floor are skipped, and a body up in the air costs nothing here.
func _hull_floor(touching: PackedByteArray) -> void:
	if rig == null or rig.hull.size() != _ends.size():
		return
	var count := pos.size()
	if _fl.floor.size() != count:
		return
	var floors := _floors_now()
	_up.resize(count)
	var near := false
	for i in count:
		var p := pos[i]
		_up[i] = Vector3(p.x, p.z, p.y)
		near = near or p.z - radius[i] - floors[i] < HULL_NEAR * size
	if not near:
		return
	var frames := rig.frames_of(_up)
	var ways := RagdollRig.ways()
	for s in _ends.size():
		var balls: Array = _seg_balls[s]
		var f := frames[s]
		var top := -INF
		for b: int in balls:
			top = maxf(top, floors[b])
		if f.origin.y - rig.hull_reach[s] * size > top + .005:
			continue
		var down := f.basis.transposed() * Vector3.DOWN
		# The bucket of the way nearest straight down, then its lowest point.
		var way := 0
		var along := -2.0
		for k in ways.size():
			var d := ways[k].dot(down)
			if d > along:
				along = d
				way = k
		var buckets: Array = rig.hull[s]
		var hull: PackedVector3Array = buckets[way]
		if hull.is_empty():
			continue
		var best := hull[0]
		var most := best.dot(down)
		for q in hull:
			var d := q.dot(down)
			if d > most:
				most = d
				best = q
		var at := f.origin + f.basis * (best * size)
		var nearest: int = balls[0]
		var gap := INF
		for b: int in balls:
			var dd := Vector2(_up[b].x - at.x, _up[b].z - at.z).length_squared()
			if dd < gap:
				gap = dd
				nearest = b
		var sink := floors[nearest] - at.y
		if sink <= HULL_SLACK:
			continue
		var lift := PackedFloat32Array()
		var wsum := 0.0
		var lifted: Array[int] = []
		if s == 0:
			# The torso turns by its four corners (the belly and the back follow).
			for b: int in [R.HIP_L, R.HIP_R, R.SH_L, R.SH_R]:
				var w := 1.0 / (.02 + _up[b].distance_squared_to(at))
				lift.append(w)
				lifted.append(b)
				wsum += w
		else:
			var a: int = _ends[s][0]
			var b: int = _ends[s][1]
			# (-1: the neck, between the shoulders; -2, a beast's tail root,
			# between the hips.)
			var one := R.SH_L if a == -1 else R.HIP_L
			var two := R.SH_R if a == -1 else R.HIP_R
			var from := (_up[one] + _up[two]) * .5 if a < 0 else _up[a]
			var run := _up[b] - from
			var t := clampf((at - from).dot(run) / maxf(run.length_squared(), 1e-6), 0.0, 1.0)
			if a < 0:
				# The head turns about the neck: the shoulders carry the neck's share.
				lift.append_array([(1.0 - t) * .5, (1.0 - t) * .5, t])
				lifted.append_array([one, two, b])
				wsum = 1.0
			elif _torso_more.has(a):
				# From a root held in the torso: only its free end lifts, and
				# only for a point out along it (near the root the torso holds
				# it up; the root lifted against the torso's links, or the knee
				# levered high, shook for ever).
				if t < .5:
					continue
				lift.append(t)
				lifted.append(b)
				wsum = 1.0
			else:
				lift.append_array([1.0 - t, t])
				lifted.append_array([a, b])
				wsum = 1.0
		# The least lifts of the balls that raise that point by `sink`.
		var sq := 0.0
		for k in lift.size():
			lift[k] /= wsum
			sq += lift[k] * lift[k]
		for k in lift.size():
			lift[k] *= sink / maxf(sq, 1e-6)
		if s == 0:
			# The belly and the back by as much as the corners on average.
			var mean := (lift[0] + lift[1] + lift[2] + lift[3]) * .25
			lift.append_array([mean, mean])
			lifted.append_array([_belly, _back])
			for b: int in _torso_more:
				lift.append(mean)
				lifted.append(b)
		for k in lifted.size():
			var b := lifted[k]
			var up := lift[k]
			if up <= 0.0:
				continue
			var p := pos[b]
			p.z += up
			pos[b] = p
			if p.z > old[b].z:
				old[b] = Vector3(old[b].x, old[b].y, p.z)
			touching[b] = 1


func _links() -> void:
	for k in la.size():
		var a := la[k]
		var b := lb[k]
		var gap := pos[b] - pos[a]
		var d := gap.length()
		if d < 1e-6:
			continue
		var want := clampf(d, lmin[k], lmax[k])
		if want == d:
			continue
		# Put right by weight: the lighter end moves the more.
		var wa := inv_mass[a]
		var wb := inv_mass[b]
		var fix := gap * ((d - want) / (d * (wa + wb)))
		pos[a] += fix * wa
		pos[b] -= fix * wb
	_keep_out()


## No limb inside the torso (a ball round its middle, as thick as it is, or
## as near as the limb stands: a hand on a gun at the belly).
func _keep_out() -> void:
	var mid := middle()
	for i in range(R.ELBOW_L, R.FOOT_R + 1):
		var off := pos[i] - mid
		var d := off.length()
		var least := _inside[i]
		if d < least and d > 1e-6:
			pos[i] = mid + off * (least / d)


## Nothing dead stands or sits up: once the muscles are going (`tone` under
## half of HOLD) a leg straight under an upright torso is folded at the knee
## and an upright torso pulled over the way it leans (SLUMP_*), its hips a
## little the other way. True when the torso lies (a lying body's ease may
## pull it out flat).
func _slump(tone: float) -> bool:
	var hips := (pos[R.HIP_L] + pos[R.HIP_R]) * .5
	var up := (pos[R.SH_L] + pos[R.SH_R]) * .5 - hips
	var tall := up.length()
	if tall < 1e-5:
		return true
	up /= tall
	if tone > HOLD * .5 or age > SLUMP_FOR:
		return up.z < SLUMP_UP
	if up.z < SLUMP_UP:
		# On its knees (a thigh straight down under the hips, the torso not
		# upright): that knee slides out away from the head, the hips follow
		# it down (it lies out on its face, not kneeling face down for good).
		var head_way := Vector3(up.x, up.y, 0.0)
		if head_way.length_squared() > .01:
			head_way = head_way.normalized()
			var give := SLUMP_PULL * STEP * STEP
			for leg: Array in [[R.HIP_L, R.KNEE_L, R.FOOT_L], [R.HIP_R, R.KNEE_R, R.FOOT_R]]:
				var hip: int = leg[0]
				var knee: int = leg[1]
				var foot: int = leg[2]
				var thigh := pos[knee] - pos[hip]
				if thigh.z < -thigh.length() * KNEELING:
					old[knee] += head_way * give
					old[foot] += head_way * give
					old[hip] += Vector3(0.0, 0.0, give * .5)
	if up.z < -HEADLONG:
		# Head down, hips up (on folded legs, or stood on its shoulders): the
		# hips go over the way the legs lie (the kill's way if they lie no
		# way) and the knees slide out (it lies out flat).
		var knees := (pos[R.KNEE_L] + pos[R.KNEE_R]) * .5 - hips
		var tip := Vector3(knees.x - up.x * tall, knees.y - up.y * tall, 0.0)
		if tip.length_squared() < 1e-4:
			tip = _fall_way if _fall_way != Vector3.ZERO else Vector3(1.0, 0.0, 0.0)
		tip = tip.normalized()
		var push := (
			SLUMP_PULL * minf(1.0, (-up.z - HEADLONG) / (1.0 - HEADLONG) * 2.0) * STEP * STEP
		)
		for i: int in [R.HIP_L, R.HIP_R, R.BELLY, R.BACK, R.KNEE_L, R.KNEE_R, R.FOOT_L, R.FOOT_R]:
			old[i] -= tip * push
		return true
	if up.z < SLUMP_UP:
		return true
	# Over the way it leans, the kill's way more (a body shot from the front
	# goes over backwards though it leaned in to walk).
	var lean := Vector3(up.x, up.y, 0.0) + _fall_way * .5
	if lean.length_squared() < .0025:
		lean = Vector3(1.0, 0.0, 0.0)
	lean = lean.normalized()
	var pull := SLUMP_PULL * minf(1.0, (up.z - SLUMP_UP) / (1.0 - SLUMP_UP) * 2.0) * STEP * STEP
	for i: int in [R.SH_L, R.SH_R, R.HEAD]:
		old[i] -= lean * pull
	for i: int in [R.HIP_L, R.HIP_R]:
		old[i] += lean * pull * .3
	# A leg straight down under it gives at the knee (forwards, its hinge).
	var across := (pos[R.SH_R] - pos[R.SH_L]) + (pos[R.HIP_R] - pos[R.HIP_L])
	# (Map space is the model's mirrored, y and z swapped: ahead is across x
	# up; up x across, as this had it before pass 11, folded the knees back.)
	var ahead := across.cross(up)
	if ahead.length_squared() > 1e-8:
		ahead = ahead.normalized()
		for leg: Array in [[R.HIP_L, R.KNEE_L, R.FOOT_L], [R.HIP_R, R.KNEE_R, R.FOOT_R]]:
			var hip: int = leg[0]
			var knee: int = leg[1]
			var foot: int = leg[2]
			var run := pos[hip] - pos[foot]
			var off := (pos[knee] - (pos[hip] + pos[foot]) * .5).dot(ahead)
			if run.z > run.length() * .7 and off < run.length() * .2:
				old[knee] -= (ahead * .8 + Vector3(0.0, 0.0, -.2)) * KNEE_GIVE * STEP * STEP
	return false


## The muscles (`tone`: the pose it died in, going slack) and a lying body's
## ease (`ease`), each a share of the error put right.
func _muscles(tone: float, ease: float) -> void:
	if tone < .002 and ease <= 0.0:
		return
	for k in sa.size():
		var target := s_hold[k]
		var share := tone
		if ease > 0.0 and s_ease[k] > 0.0:
			target = (s_hold[k] * tone + s_ease[k] * ease) / maxf(tone + ease, 1e-6)
			share = tone + ease
		if share < .002:
			continue
		var a := sa[k]
		var b := sb[k]
		var gap := pos[b] - pos[a]
		var d := gap.length()
		if d < 1e-6:
			continue
		var wa := inv_mass[a]
		var wb := inv_mass[b]
		var fix := gap * ((d - target) / (d * (wa + wb)) * minf(share, 1.0))
		pos[a] += fix * wa
		pos[b] -= fix * wb


## Knees bend only forwards.
func _hinges() -> void:
	var hips := (pos[R.HIP_L] + pos[R.HIP_R]) * .5
	var up := (pos[R.SH_L] + pos[R.SH_R]) * .5 - hips
	var across := (pos[R.SH_R] - pos[R.SH_L]) + (pos[R.HIP_R] - pos[R.HIP_L])
	# (Map space is the model's mirrored, y and z swapped: ahead is across x
	# up; up x across, as this had it before pass 11, folded the knees back.)
	var ahead := across.cross(up)
	if ahead.length_squared() < 1e-8:
		return
	ahead = ahead.normalized()
	for joint: Array in [[R.HIP_L, R.KNEE_L, R.FOOT_L], [R.HIP_R, R.KNEE_R, R.FOOT_R]]:
		var a: int = joint[0]
		var m: int = joint[1]
		var b: int = joint[2]
		var off := pos[m] - (pos[a] + pos[b]) * .5
		# A leg near straight may be a touch past it (a straight leg lying on
		# its face would else be pushed into the floor, and back, for ever).
		var most := pos[a].distance_to(pos[b]) * KNEE_PAST
		var k := off.dot(ahead)
		if k < -most:
			var fix := -ahead * (k + most)
			# Never down into the floor it lies on (the floor and the knee
			# pushed it back and forth for ever): a knee down stays.
			if not (fix.z < 0.0 and m < _touch.size() and _touch[m]):
				pos[m] += fix
	# (Elbows bend any way: the shoulder turns the arm, and a plane taken from
	# the torso pushed a lying arm into the floor and back for ever.)


## Ball i stays out of walls, slabs' sides and rails: a move that would put it
## inside one keeps to the axis that is free, or stays where it was.
func _walls(world: LevelData, i: int) -> void:
	var p := pos[i]
	var o := old[i]
	var r := radius[i]
	if i >= body_n:
		# Gear is kept a little further off walls than it is thick (a thin
		# gun's balls slipped into a stair's riser and stuck there).
		r = maxf(r, GEAR_WALL)
	# Play's body went over this rail: the ball is lifted over its top bar
	# rather than held behind it (the body goes over head first, the legs
	# dragged across after).
	var rail := _rail_at(world, p, r)
	if rail != null and body != Vector3.INF:
		var toward := _side(rail, body)
		if _side(rail, o) != toward:
			p.z = maxf(p.z, rail.z1 + r)
		elif o.z - r >= rail.z1 - .03:
			# Come down on the bar from above: it rolls off on the body's side.
			var along := Vector2(rail.bx - rail.ax, rail.by - rail.ay).normalized()
			var n := Vector2(-along.y, along.x)
			var to_body := n.dot(Vector2(body.x - rail.ax, body.y - rail.ay))
			var to_ball := n.dot(Vector2(p.x - rail.ax, p.y - rail.ay))
			var reach := r * .8 + rail.half + .005
			var want := reach if to_body >= 0.0 else -reach
			if absf(to_ball) < reach:
				p.x += n.x * (want - to_ball)
				p.y += n.y * (want - to_ball)
		pos[i] = p
	if not _solid(world, p, r):
		return
	if rail != null and body != Vector3.INF and _solid(world, o, r * .5):
		# Stuck in a rail's bar on play's body's side: out to that side of it.
		var run := Vector2(rail.bx - rail.ax, rail.by - rail.ay).normalized()
		var side := Vector2(-run.y, run.x)
		var to_body := side.dot(Vector2(body.x - rail.ax, body.y - rail.ay))
		var to_ball := side.dot(Vector2(p.x - rail.ax, p.y - rail.ay))
		var reach := r * .8 + rail.half + .005
		var want := reach if to_body >= 0.0 else -reach
		if absf(to_ball) < reach:
			pos[i] = Vector3(p.x + side.x * (want - to_ball), p.y + side.y * (want - to_ball), p.z)
			old[i] = Vector3(pos[i].x, pos[i].y, o.z)
		return
	if _solid(world, o, r * .5) and rail == null:
		# In something already (a boot pushed into a stair's riser): up onto
		# the top just over it when there is one within a step, else as it is.
		var top := Tumble.floor_at(world, p.x, p.y, p.z + r + STEP_UP, r * .6)
		var lift := top + r
		if (
			lift > p.z
			and lift - p.z < STEP_UP + r
			and not _solid(world, Vector3(p.x, p.y, lift), r * .5)
		):
			pos[i] = Vector3(p.x, p.y, lift)
			old[i] = Vector3(o.x, o.y, lift)
		return
	if not _solid(world, Vector3(p.x, o.y, p.z), r):
		pos[i] = Vector3(p.x, o.y, p.z)
	elif not _solid(world, Vector3(o.x, p.y, p.z), r):
		pos[i] = Vector3(o.x, p.y, p.z)
	elif not _solid(world, Vector3(o.x, o.y, p.z), r * .5):
		# Straight up or down where it was (sliding down a wall's face).
		pos[i] = Vector3(o.x, o.y, p.z)
	else:
		pos[i] = o


## Whether every cell the body is over (and a little round it) is open floor
## with nothing of the geometry, no furniture, door, pane or gate near: then
## the cells' ground and roof are all there is (PhysCore.plain_rect).
func _plain(world: LevelData) -> bool:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pos:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return PhysCore.plain_rect(
		world, int(lo.x - .3), int(lo.y - .3), int(hi.x + .3), int(hi.y + .3)
	)


static func _solid(world: LevelData, p: Vector3, r: float) -> bool:
	return PhysCore.ball_solid(world, p, r)


static func _rail_at(world: LevelData, p: Vector3, r: float) -> LevelGeometry.Segment:
	return PhysCore.rail_at(world, p, r)


## Which side of rail s point p is on.
static func _side(s: LevelGeometry.Segment, p: Vector3) -> bool:
	return (s.bx - s.ax) * (p.y - s.ay) - (s.by - s.ay) * (p.x - s.ax) > 0.0


## Ball i on the floor under it (`under`), under any roof, and the torso no
## lower than play's body carries it. True when it touches the floor.
func _floor(i: int, under: float, roof: float) -> bool:
	var p := pos[i]
	var r := radius[i]
	var low := under + r
	if carry > -INF and _core[i]:
		low = maxf(low, carry + r * .5)
	var on := p.z <= low
	if on:
		p.z = low
	if roof > 0.0 and p.z + r > roof:
		p.z = maxf(low, roof - r)
	pos[i] = p
	return on


## Whether every ball rests on something: none sunk into the floor under it,
## and the lowest of them touching a floor (the checks use it).
func lies_on(world: LevelData, tolerance := .03) -> bool:
	var lowest := INF
	for i in pos.size():
		var under := Tumble.floor_at(
			world, pos[i].x, pos[i].y, pos[i].z + .02 - radius[i], radius[i] * .6
		)
		var gap := pos[i].z - radius[i] - under
		if gap < -tolerance:
			return false
		lowest = minf(lowest, gap)
	return lowest < tolerance
