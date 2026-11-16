## A dead body's limbs flopping (looks only: the 3D view's ActorView drives
## one per body it shows; play's body, features/corpses.gd, says where the
## body is and the ragdoll follows it).
##
## Thirteen balls (RagdollRig: hips, shoulders, head, elbows, hands, knees,
## feet) held together by links: the torso's four corners rigid, each limb
## half a rigid stick, ranges for the neck, the elbows, the knees and the hips
## (a knee folds no further than about 130 degrees and only forwards, an
## elbow only backwards), and no limb inside the torso, the head or the other
## leg. Solved by position steps (Verlet: each ball keeps the move it made
## last step, gravity added; then the links are put right a few passes), a
## few small steps a frame, like the bowling pins' solver
## (range_pin_physics.gd) in spirit: contacts by sphere, friction on the
## floor, and asleep (no cost at all) once nothing moves.
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
const PASSES := 3
## Asleep once no ball moves more than SLEEP_MOVE a step for SLEEP_AFTER
## seconds, or after MOST_AWAKE seconds whatever (a jitter never costs for ever).
const SLEEP_MOVE := .0008
const SLEEP_AFTER := .5
const MOST_AWAKE := 8.0
## The torso's middle may lag play's body by this much before it is pulled.
const SLACK := .3
const PULL := 8.0
## A ball's floor is asked again once it has moved this far across.
const REASK := PhysCore.REASK
## The model's shape is kept out of the floor once a ball is this near it
## (model units), to within HULL_SLACK (map units).
const HULL_NEAR := .5
const HULL_SLACK := .002
## A ball on a floor steeper than this (its fall a unit across) is pulled
## down it by the rest of the slope's share of gravity.
const SLIDE_FROM := .25
## Striking a body lying still faster than this (a step) wakes it.
const WAKE_HIT := .02
## Each of the rig's segments' balls (RagdollRig.ENDS order): the torso's
## six, the head, each limb half's two ends.
const SEG_BALLS := [
	[0, 1, 2, 3, 13, 14], [4], [2, 5], [5, 6], [3, 7], [7, 8], [0, 9], [9, 10], [1, 11], [11, 12]
]

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
## Play's body's move, given on the next step.
var _shove := Vector3.ZERO
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


## A ragdoll for a body hung on `rig`, its points at `model` (model space)
## under the model's transform `xf`.
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
	doll.size = scale
	doll.rig = rig
	doll.start(at, radii, rest)
	return doll


## The kill's throw (effects.cfg [ragdoll]): the shoulders and head, the
## hips and the feet sent along the shot (from where it came to the body),
## the knees forwards and all of it up, each ball a little differently by
## `dice` (looks only).
func knock(e: Enemy, dice: RandomNumberGenerator) -> void:
	var from := e.killed_from
	var how := e.killed_by
	if (how == "blast" or how == "energy") and e.blast_at != Vector2.INF:
		from = e.blast_at
	var away := Vector2(e.x, e.y) - from
	var key := how
	if how == "shotgun" and away.length() < Corpses.POINT_BLANK:
		key = "shotgun_near"
	elif e.last_zone == "head" and how != "blast" and how != "energy":
		key = "head"
	var row: Array = Effects.RAGDOLL.get(
		key, Effects.RAGDOLL.get("default", [1.0, .4, 0.0, .6, 0.0])
	)
	var top: float = row[0]
	var hips: float = row[1]
	var feet: float = row[2]
	var buckle: float = row[3]
	var lift: float = row[4]
	var spread: float = Effects.RAGDOLL.get("spread", .3)
	var side: float = Effects.RAGDOLL.get("side", .35)
	if away.length() < .01:
		away = Vector2.from_angle(e.angle + PI)
	away = away.normalized()
	var dir := Vector3(away.x, away.y, 0.0)
	var cross := Vector3(-away.y, away.x, 0.0)
	var ahead := Vector3(cos(e.angle), sin(e.angle), 0.0)
	var lean := dice.randf_range(-side, side)
	for i in pos.size():
		var speed := hips
		if i == R.SH_L or i == R.SH_R or i == R.HEAD or (i >= R.ELBOW_L and i <= R.HAND_R):
			speed = top
		elif i == R.FOOT_L or i == R.FOOT_R:
			speed = feet
		elif i == R.KNEE_L or i == R.KNEE_R:
			speed = (hips + feet) * .5
		var v := dir * speed * (1.0 + dice.randf_range(-spread, spread))
		v += cross * speed * lean
		v.z += lift * (1.0 + dice.randf_range(-spread, spread))
		if i == R.KNEE_L or i == R.KNEE_R:
			v += ahead * buckle * (1.0 + dice.randf_range(-spread, spread))
			v.z -= buckle * .3
		elif i <= R.HEAD:
			v.z -= buckle * .5
		push(i, v)


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
	radius = radii.duplicate()
	_torso_r = radius[R.HIP_L]
	la.clear()
	lb.clear()
	lmin.clear()
	lmax.clear()
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
		_link(a, b, reach * fold, reach)
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
		_link(a, b, (radius[a] + radius[b]) * .9, INF)
	awake = true
	still = 0.0
	age = 0.0
	_left = 0.0


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
		shift(Vector3(off.x * k, off.y * k, 0.0))


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
	for i in count:
		var p := pos[i]
		var v := (p - old[i]) * AIR
		old[i] = p
		pos[i] = p + v + _shove - Vector3(0.0, 0.0, g)
	var shoved := _shove
	_shove = Vector3.ZERO
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
	var floors := _fl.floor
	var touching := PackedByteArray()
	touching.resize(count)
	for _pass in PASSES:
		_links()
		_hinges()
		for i in count:
			if _floor(i, floors[i], _roofs[i]):
				touching[i] = 1
	_on_bodies(touching)
	_on_boxes(world, touching)
	_hull_floor(touching)
	if not plain:
		# Last, nothing ends the step inside a wall, a slab's side or a rail
		# (the links may have pulled a ball in).
		for i in count:
			_walls(world, i)
			_floor(i, floors[i], _roofs[i])
	# Play's body's move carried the balls along; it is not theirs to keep
	# going with (each frame brings its own), as far as they made it.
	var reach := shoved.length()
	if reach > 1e-6:
		var way := shoved / reach
		for i in count:
			var k := clampf((pos[i] - old[i]).dot(way) / reach, 0.0, 1.0)
			old[i] += shoved * k
	# Friction: a ball on the floor slides less far; on a ramp steeper than
	# SLIDE_FROM it is pulled down it a little past what friction holds.
	for i in count:
		if touching[i]:
			var p := pos[i]
			var o := old[i]
			old[i] = Vector3(p.x - (p.x - o.x) * GRIP, p.y - (p.y - o.y) * GRIP, o.z)
			var fall := _slopes[i]
			var steep := fall.length()
			if steep > SLIDE_FROM:
				var pull := fall / steep * (steep - SLIDE_FROM) * GRAVITY * STEP * STEP
				old[i] -= Vector3(pull.x, pull.y, 0.0)
	var most := 0.0
	for i in count:
		most = maxf(most, pos[i].distance_squared_to(old[i]))
	if most < SLEEP_MOVE * SLEEP_MOVE:
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
			pos[i] = Vector3(p.x, p.y, maxf(p.z, under + r))
	for _k in 2:
		_hull_floor(touching)
	for i in pos.size():
		old[i] = pos[i]


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
		if o == self or o.pos.size() != pos.size():
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
	if rig == null or rig.hull.size() != R.ENDS.size():
		return
	var count := pos.size()
	if _fl.floor.size() != count:
		return
	var floors := _fl.floor
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
	for s in R.ENDS.size():
		var balls: Array = SEG_BALLS[s]
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
		if s == R.TORSO:
			# The torso turns by its four corners (the belly and the back follow).
			for b: int in [R.HIP_L, R.HIP_R, R.SH_L, R.SH_R]:
				var w := 1.0 / (.02 + _up[b].distance_squared_to(at))
				lift.append(w)
				lifted.append(b)
				wsum += w
		else:
			var a: int = R.ENDS[s][0]
			var b: int = R.ENDS[s][1]
			var from := (_up[R.SH_L] + _up[R.SH_R]) * .5 if a < 0 else _up[a]
			var run := _up[b] - from
			var t := clampf((at - from).dot(run) / maxf(run.length_squared(), 1e-6), 0.0, 1.0)
			if a < 0:
				# The head turns about the neck: the shoulders carry the neck's share.
				lift.append_array([(1.0 - t) * .5, (1.0 - t) * .5, t])
				lifted.append_array([R.SH_L, R.SH_R, b])
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
		if s == R.TORSO:
			# The belly and the back by as much as the corners on average.
			var mean := (lift[0] + lift[1] + lift[2] + lift[3]) * .25
			lift.append_array([mean, mean])
			lifted.append_array([R.BELLY, R.BACK])
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
		var fix := gap * ((d - want) / d * .5)
		pos[a] += fix
		pos[b] -= fix
	# No limb inside the torso (a ball round its middle, as thick as it is).
	var mid := middle()
	for i in range(R.ELBOW_L, R.FOOT_R + 1):
		var off := pos[i] - mid
		var d := off.length()
		var least := _torso_r + radius[i]
		if d < least and d > 1e-6:
			pos[i] = mid + off * (least / d)


## Knees bend only forwards, elbows only back.
func _hinges() -> void:
	var hips := (pos[R.HIP_L] + pos[R.HIP_R]) * .5
	var up := (pos[R.SH_L] + pos[R.SH_R]) * .5 - hips
	var across := (pos[R.SH_R] - pos[R.SH_L]) + (pos[R.HIP_R] - pos[R.HIP_L])
	var ahead := up.cross(across)
	if ahead.length_squared() < 1e-8:
		return
	ahead = ahead.normalized()
	for joint: Array in [
		[R.HIP_L, R.KNEE_L, R.FOOT_L, 1.0],
		[R.HIP_R, R.KNEE_R, R.FOOT_R, 1.0],
		[R.SH_L, R.ELBOW_L, R.HAND_L, -1.0],
		[R.SH_R, R.ELBOW_R, R.HAND_R, -1.0]
	]:
		var a: int = joint[0]
		var m: int = joint[1]
		var b: int = joint[2]
		var way: float = joint[3]
		var off := pos[m] - (pos[a] + pos[b]) * .5
		var k := off.dot(ahead) * way
		if k < 0.0:
			pos[m] -= ahead * (k * way)


## Ball i stays out of walls, slabs' sides and rails: a move that would put it
## inside one keeps to the axis that is free, or stays where it was.
func _walls(world: LevelData, i: int) -> void:
	var p := pos[i]
	var o := old[i]
	var r := radius[i]
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
	if not _solid(world, p, r) or _solid(world, o, r * .5):
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
	if carry > -INF and (i <= R.SH_R or i >= R.BELLY):
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
