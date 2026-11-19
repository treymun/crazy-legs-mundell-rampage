## A dead beast's limbs, tail and head flopping (pass 13; looks only, as a
## person's ragdoll, src/ragdoll.gd, whose steps, floor, walls, friction,
## sleep and model's shape against the floor it shares): a gator, a crawler,
## a hog of the herd, the cow, hung on a BeastRig (its torso's six balls as a
## person's, then the head's, the tail's and three a leg).
##
## Held by links: the torso rigid, each leg's root in it, each leg two rigid
## halves folding at the knee only its own way (`_hinges`: a gator's and a
## crawler's splay up and out, a foreleg's knee ahead, a hind leg's behind)
## and no further than the plan's fold, swinging within a reach of the back;
## the head nods about the shoulders, each tail ball bends a little on the
## last. The muscles hold the pose it died in and go slack; then a lying
## beast's ease (a crawler's legs curling in, a hog's and the cow's legs out
## a little bent, a gator's tail lying out). Nothing dead stands (`_slump`):
## its legs give and it goes over onto the side the death's dice and the shot
## chose (`_lie`: belly down, on its side away from the shot, or onto its
## back, by effects.cfg [ragdoll] beast_<kind>), the kill's strike turning it
## that way at the part the shot met. In water each ball floats a little
## under the surface, bobbing with play's body.
class_name BeastDoll
extends Ragdoll

const B := preload("res://src/view3d/beast_rig.gd")

## Weights: the torso and a leg's root, the head, the snout, the tail's
## first ball (its last BEAST_TIP_WEIGHT), a knee, a foot.
## (Its legs light against its body, as a beast's are: heavy legs out to one
## side rolled a hog lying on its side back onto its legs, propped.)
const TORSO_WEIGHT := 1.6
const ROOT_WEIGHT := 1.2
const HEAD_WEIGHT := 1.1
const SNOUT_WEIGHT := .7
const TAIL_WEIGHT := 1.0
const TAIL_TIP_WEIGHT := .4
const KNEE_WEIGHT := .35
const FOOT_WEIGHT := .25
## A leg folds to at most this share of its reach (root to foot); a knee
## swings this share nearer or further from the back than it stands.
const FOLD := .42
const SWING := .3
## A tail ball bends on the one before by up to about 60 degrees (its
## distance from the ball two back no less than TAIL_BEND of straight).
const TAIL_BEND := .86
## Standing (its belly over its floor by more than STAND of its height
## standing) a dead beast's knees give, KNEE_GIVE map units a second a second.
const STAND := .55
## The turn onto the side it is to lie on: up to ROLL_RATE radians a second
## (by the root of its heft), till its back points within ROLL_DONE of the
## way.
const ROLL_RATE := 5.0
const ROLL_DONE := .96
## The kill's own turn about the body's length toward that side (a share of
## the hit) and how far the struck ball's pick may wander (a share of its
## reach from the middle).
const ROLL_KICK := .5
const PICK_WANDER := .35
## Its throes at the kill (map units a second, by the root of its heft): its
## tail's tip lashes across, its snout jerks up.
const LASH_LEAST := 1.2
const LASH_MOST := 2.8
const JERK_LEAST := .8
const JERK_MOST := 1.8
## A ball in water floats this share of its radius under the surface, and
## one under that rises at FLOAT_RISE map units a second.
const DUNK := .35
const FLOAT_RISE := .5

var beast: BeastRig
## The way its back is to point lying (map): up (belly down), along the side
## away from the shot, or down (on its back); the side it turns by when that
## is straight across from now.
var _lie := Vector3.ZERO
var _roll_side := Vector3.ZERO
## Each leg's knee's way to fold, in the torso's frame at rest.
var _bend_rest := PackedVector3Array()
## Its torso's lowest ball's height over the floor standing (map).
var _stand_high := 1.0
## Which balls are in water this step, and play's body's height (the water's
## surface and its bob, for one afloat).
var _wet := PackedByteArray()
var _water := false
var _float_z := -INF
## How heavy it is to the kill (effects.cfg beast_<kind> heft).
var heft := 1.0
var _feel: Array = [1.0, .4, .4, .2, .9]

## Whether each level asked has water (the last one).
static var _watered := {}


## A ragdoll for a beast hung on `rig`, its points at `model` (model space)
## under the model's transform `xf`; `kind` names its feel.
static func made_beast(
	rig: BeastRig, xf: Transform3D, model: PackedVector3Array, kind: String
) -> BeastDoll:
	var doll := BeastDoll.new()
	var scale := xf.basis.get_scale().x
	var at := PackedVector3Array()
	var rest := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in rig.points.size():
		at.append(to_map(xf, model[i] if i < model.size() else rig.points[i]))
		rest.append(rig.points[i] * scale)
		radii.append(rig.radii[i] * scale)
	doll.size = scale
	doll.rig = rig
	doll.beast = rig
	doll._feel = Effects.RAGDOLL.get("beast_" + kind, doll._feel)
	var weight: float = doll._feel[0]
	doll.heft = maxf(.2, weight)
	doll.start(at, radii, rest)
	return doll


func start(at: PackedVector3Array, radii: PackedFloat32Array, rest: PackedVector3Array) -> void:
	pos = at.duplicate()
	old = at.duplicate()
	prev = at.duplicate()
	radius = radii.duplicate()
	var count := pos.size()
	body_n = count
	_torso_r = radius[R.HIP_L]
	_belly = B.BELLY_B
	_back = B.BACK_B
	_ends = beast.ends
	_seg_balls = []
	for s in beast.ends.size():
		var balls: Array = []
		if s == 0:
			balls = [0, 1, 2, 3, 4, 5]
		else:
			if beast.ends[s][0] >= 0:
				balls.append(beast.ends[s][0])
			balls.append(beast.ends[s][1])
		_seg_balls.append(balls)
	_torso_more.clear()
	inv_mass.resize(count)
	_limb.resize(count)
	_core.resize(count)
	_wet.resize(count)
	for i in count:
		var weight := TORSO_WEIGHT
		_core[i] = 1 if i < B.TORSO_BALLS else 0
		_limb[i] = 0
		if beast.head.size() > 0 and i == beast.head[0]:
			weight = HEAD_WEIGHT
		elif beast.head.size() > 1 and i == beast.head[1]:
			weight = SNOUT_WEIGHT
		elif beast.tail.has(i):
			var k := beast.tail.find(i)
			weight = lerpf(TAIL_WEIGHT, TAIL_TIP_WEIGHT, float(k) / maxf(1.0, beast.tail.size() - 1))
			_limb[i] = 1
		elif beast.legs.has(i):
			match beast.legs.find(i) % 3:
				0:
					weight = ROOT_WEIGHT
					_core[i] = 1
					_torso_more.append(i)
				1:
					weight = KNEE_WEIGHT
					_limb[i] = 1
				2:
					weight = FOOT_WEIGHT
					_limb[i] = 1
		inv_mass[i] = 1.0 / weight
	# How near the torso's middle a limb ball may come (as near as it stands).
	var rest_mid := (rest[0] + rest[1] + rest[2] + rest[3]) * .25
	_inside.resize(count)
	for i in count:
		_inside[i] = minf(_torso_r + radius[i], rest[i].distance_to(rest_mid) * .95)
	la.clear()
	lb.clear()
	lmin.clear()
	lmax.clear()
	sa.clear()
	sb.clear()
	s_hold.clear()
	s_ease.clear()
	for i in B.TORSO_BALLS:
		for k in range(i + 1, B.TORSO_BALLS):
			_rigid(rest, i, k)
	var curl: float = _feel[4]
	for leg in beast.legs.size() / 3:
		var root := beast.legs[leg * 3]
		var knee := root + 1
		var foot := root + 2
		# The root held in the torso by its two nearest corners, belly and back.
		var corners: Array[int] = [0, 1, 2, 3]
		corners.sort_custom(
			func(a: int, b: int) -> bool:
				return rest[a].distance_squared_to(rest[root]) < rest[b].distance_squared_to(rest[root])
		)
		for t: int in [corners[0], corners[1], B.BELLY_B, B.BACK_B]:
			_rigid(rest, root, t)
		_rigid(rest, root, knee)
		_rigid(rest, knee, foot)
		var reach := rest[root].distance_to(rest[knee]) + rest[knee].distance_to(rest[foot])
		_link(root, foot, reach * FOLD, reach)
		_range(rest, knee, B.BACK_B, 1.0 - SWING, 1.0 + SWING)
		_range(rest, foot, B.BACK_B, 1.0 - SWING * 1.5, 1.0 + SWING * 1.5)
		# The muscles across the knee and the hip; a lying beast's legs lie
		# out at `curl` of their reach (a dead crawler's curl right in).
		_soft(root, foot, reach * curl)
		_soft(knee, B.BACK_B, -1.0)
	# Neighbouring legs' knees and feet apart (a pair, and each side's next).
	var legs_n := beast.legs.size() / 3
	for k in legs_n:
		for m in range(k + 1, legs_n):
			if m != k + 1 and m != k + 2:
				continue
			for part: int in [1, 2]:
				var a := beast.legs[k * 3] + part
				var b := beast.legs[m * 3] + part
				var apart := minf((radius[a] + radius[b]) * .9, rest[a].distance_to(rest[b]) * .95)
				_link(a, b, apart, INF)
	if beast.head.size() > 0:
		var skull := beast.head[0]
		_rigid(rest, skull, R.SH_L)
		_rigid(rest, skull, R.SH_R)
		_range(rest, skull, R.HIP_L, .9, 1.04)
		_range(rest, skull, R.HIP_R, .9, 1.04)
		_range(rest, skull, B.BELLY_B, .8, 1.15)
		if beast.head.size() > 1:
			var snout := beast.head[1]
			_rigid(rest, snout, skull)
			_range(rest, snout, R.SH_L, .92, 1.05)
			_range(rest, snout, R.SH_R, .92, 1.05)
			_soft(snout, B.BELLY_B, -1.0)
	var behind: Array[int] = [R.HIP_L, R.HIP_R]
	for k in beast.tail.size():
		var ball := beast.tail[k]
		if k == 0:
			_range(rest, ball, R.HIP_L, .9, 1.1)
			_range(rest, ball, R.HIP_R, .9, 1.1)
			_range(rest, ball, B.BACK_B, .85, 1.12)
			_range(rest, ball, B.BELLY_B, .85, 1.12)
		else:
			var last := beast.tail[k - 1]
			_rigid(rest, ball, last)
			var two_back := beast.tail[k - 2] if k > 1 else B.BACK_B
			var straight := rest[ball].distance_to(rest[two_back])
			_link(ball, two_back, straight * TAIL_BEND, straight * 1.02)
			_soft(ball, two_back, straight * .98)
		behind.append(ball)
	# How its knees fold, in the torso's frame at rest (`rest` is the
	# model's space, y up; map space is it mirrored, so the frame's third way
	# turns over: _torso_basis takes it as across x ahead either way).
	var inv := _torso_basis(rest).inverse()
	_bend_rest = PackedVector3Array()
	for k in beast.bend.size():
		var local := inv * beast.bend[k]
		_bend_rest.append(Vector3(local.x, local.y, -local.z))
	var floor_y := INF
	for leg in beast.legs.size() / 3:
		var foot := beast.legs[leg * 3 + 2]
		floor_y = minf(floor_y, rest[foot].y - radius[foot])
	if floor_y == INF:
		floor_y = rest[B.BELLY_B].y - radius[B.BELLY_B] * 2.0
	var low := INF
	for i in B.TORSO_BALLS:
		low = minf(low, rest[i].y - radius[i])
	_stand_high = maxf(.02, low - floor_y)
	down_share = .3
	awake = true
	still = 0.0
	age = 0.0
	_left = 0.0


## The torso's frame (map): across, from its hips to its shoulders, and up
## out of its back.
func _torso_basis(at: PackedVector3Array) -> Basis:
	var ahead := ((at[R.SH_L] + at[R.SH_R]) - (at[R.HIP_L] + at[R.HIP_R])).normalized()
	var across := ((at[R.SH_R] - at[R.SH_L]) + (at[R.HIP_R] - at[R.HIP_L])).normalized()
	across = (across - ahead * across.dot(ahead)).normalized()
	return Basis(across, ahead, across.cross(ahead)).orthonormalized()


## How high its torso's lowest ball is over its floor (map).
func torso_up() -> float:
	var floors := _fl.floor
	var low := INF
	for i in B.TORSO_BALLS:
		var under := floors[i] if i < floors.size() else -INF
		low = minf(low, pos[i].z - radius[i] - under)
	return low


## The way its back points (map), out of its belly.
func dorsal() -> Vector3:
	return (pos[B.BACK_B] - pos[B.BELLY_B]).normalized()


## The kill (effects.cfg [ragdoll], the gun's row, as a person's, its share
## of the hit and carry and lift taken by its heft): struck at the part the
## shot met (the ball standing furthest toward the shooter, picked a little
## at random among the near ones; a blast the ball nearest it, up and away),
## carried and turned about itself, its knees given, and set turning about
## its length toward the side it is to lie on (beast_<kind>: belly, side or
## back by its dice, a blast or a load at arm's length the likelier over).
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
	var by: Array = Effects.RAGDOLL.get("zone_body", [1.0, 0.0, 0.0, .2])
	var spread: float = Effects.RAGDOLL.get("spread", .3)
	var hit: float = row[0]
	var carry: float = row[1]
	var lift: float = row[2]
	var buckle: float = row[3]
	var spin: float = row[4]
	var slack: float = by[3]
	hit /= heft
	carry /= heft
	lift /= sqrt(heft)
	spin /= heft
	fade = slack * dice.randf_range(.7, 1.4)
	if away.length() < .01:
		away = Vector2.from_angle(e.angle + PI)
	away = away.normalized()
	var dir := Vector3(away.x, away.y, 0.0)
	_fall_way = dir
	var mid := middle()
	var at := mid
	if blast:
		var near := 0
		var blast_at := Vector3(from.x, from.y, mid.z - _stand_high)
		for i in pos.size():
			if pos[i].distance_squared_to(blast_at) < pos[near].distance_squared_to(blast_at):
				near = i
		at = pos[near]
		dir = (dir + Vector3(0.0, 0.0, .6)).normalized()
	else:
		var reach := 0.0
		for p in pos:
			reach = maxf(reach, p.distance_to(mid))
		var best := 0
		var most := -INF
		for i in pos.size():
			var toward := -(pos[i] - mid).dot(dir) + dice.randf_range(-1.0, 1.0) * reach * PICK_WANDER
			if toward > most:
				most = toward
				best = i
		at = pos[best].lerp(mid, dice.randf_range(0.0, .35))
	var wobble := Vector3(
		dice.randf_range(-.3, .3), dice.randf_range(-.3, .3), dice.randf_range(-.15, .2)
	)
	strike(at, (dir + wobble * spread).normalized(), hit)
	# The side it is to lie on.
	var torso := _torso_basis(pos)
	var ahead := torso.y
	var side := Vector3(dir.x, dir.y, 0.0) - ahead * dir.dot(ahead)
	side.z = 0.0
	if side.length_squared() < 1e-4:
		side = Vector3(torso.x.x, torso.x.y, 0.0) * (1.0 if dice.randf() < .5 else -1.0)
	side = side.normalized()
	var belly: float = _feel[1]
	var flank: float = _feel[2]
	var back: float = _feel[3]
	if blast or key == "shotgun_near":
		back *= 2.0
		flank *= 1.4
	var roll := dice.randf() * (belly + flank + back)
	_roll_side = side
	if roll < belly:
		_lie = Vector3(0.0, 0.0, 1.0)
	elif roll < belly + flank:
		_lie = side
	else:
		_lie = Vector3(0.0, 0.0, -1.0)
	var turn := spin * (1.0 if dice.randf() < .5 else -1.0) * dice.randf_range(.5, 1.3)
	var over := 0.0 if _lie.z > .5 else hit * ROLL_KICK
	for i in pos.size():
		var v := dir * carry * (1.0 + dice.randf_range(-spread, spread))
		v.z += lift * (1.0 + dice.randf_range(-spread, spread))
		var off := pos[i] - mid
		v += Vector3(-off.y, off.x, 0.0) * turn
		# About its length, toward the side: its back over that way, its belly
		# the other.
		v += side * off.z * over / maxf(.05, _stand_high)
		add_speed(i, v)
	for k in beast.legs.size() / 3:
		var knee := beast.legs[k * 3 + 1]
		var bend := (torso * _bend_rest[k]) if k < _bend_rest.size() else Vector3.ZERO
		var give := buckle * (1.0 + dice.randf_range(-spread, spread))
		add_speed(knee, (bend - Vector3(0.0, 0.0, .3)) * give)
	# Its throes: the tail lashes one way, the head jerks up and drops.
	var across := Vector3(torso.x.x, torso.x.y, 0.0).normalized()
	var lash := across * dice.randf_range(LASH_LEAST, LASH_MOST) / sqrt(heft)
	if dice.randf() < .5:
		lash = -lash
	for k in beast.tail.size():
		add_speed(beast.tail[k], lash * float(k + 1) / beast.tail.size())
	if not beast.head.is_empty():
		var jerk := dice.randf_range(JERK_LEAST, JERK_MOST) / sqrt(heft)
		add_speed(beast.head[beast.head.size() - 1], Vector3(0.0, 0.0, jerk))


## Nothing dead stands: once the muscles are going its knees give while its
## belly stands high, and it is turned about its length till its back points
## the way it is to lie (_lie). True when it lies.
func _slump(tone: float) -> bool:
	var standing := torso_up() > _stand_high * STAND
	if tone > HOLD * .5 or age > SLUMP_FOR:
		return not standing
	var torso := _torso_basis(pos)
	if standing:
		var give := KNEE_GIVE * STEP * STEP
		for k in beast.legs.size() / 3:
			var knee := beast.legs[k * 3 + 1]
			var bend := (torso * _bend_rest[k]) if k < _bend_rest.size() else Vector3.ZERO
			old[knee] -= (bend * .8 + Vector3(0.0, 0.0, -.4)) * give
	if _lie != Vector3.ZERO:
		var back := dorsal()
		var d := back.dot(_lie)
		if d >= ROLL_DONE:
			# There: it lies as it comes to rest from here (no hold to fight).
			_lie = Vector3.ZERO
		else:
			var way := _lie - back * d
			if way.length_squared() < .01:
				way = _roll_side - back * back.dot(_roll_side)
			if way.length_squared() > 1e-6:
				# Turned whole about its length (the torso, its legs' roots and
				# its head; the legs and tail follow on their links), easing in
				# and slowing as it nears the way: its feet's grip and the
				# damping of a body down never hold it propped on its legs.
				way = way.normalized()
				var axis := back.cross(way).normalized()
				var gone := acos(clampf(d, -1.0, 1.0))
				var turn := minf(ROLL_RATE / sqrt(heft) * STEP * minf(1.0, age * 2.0), gone * .25)
				var spin := Basis(axis, turn)
				var mid := middle()
				for i in pos.size():
					if _core[i] or beast.head.has(i):
						pos[i] = mid + spin * (pos[i] - mid)
	return not standing


## Knees fold only their own way (as the rig found them standing, turned
## with the torso).
func _hinges() -> void:
	if _bend_rest.is_empty():
		return
	var torso := _torso_basis(pos)
	for k in beast.legs.size() / 3:
		var a := beast.legs[k * 3]
		var m := a + 1
		var b := a + 2
		var bend := torso * _bend_rest[k]
		var off := pos[m] - (pos[a] + pos[b]) * .5
		var most := pos[a].distance_to(pos[b]) * KNEE_PAST
		var into := off.dot(bend)
		if into < -most:
			var fix := -bend * (into + most)
			if not (fix.z < 0.0 and m < _touch.size() and _touch[m]):
				pos[m] += fix


## No knee, foot, snout or tail tip inside the torso.
func _keep_out() -> void:
	var mid := middle()
	for i in range(B.TORSO_BALLS, pos.size()):
		if _core[i]:
			continue
		var off := pos[i] - mid
		var d := off.length()
		var least := _inside[i]
		if d < least and d > 1e-6:
			pos[i] = mid + off * (least / d)


## Play's body's height kept as well (the water's surface for one afloat).
func follow(at: Vector3, up: float, dt: float) -> void:
	_float_z = at.z
	super.follow(at, up, dt)


## Which balls are in water (Gator Bayou's channels and shallows).
func _before_passes(world: LevelData) -> void:
	_water = false
	if world == null or world.deep_tile < 0 and not _has_water(world):
		return
	for i in pos.size():
		var wet := BayouBrains.wet_at(world, pos[i].x, pos[i].y)
		_wet[i] = 1 if wet else 0
		_water = _water or wet


## Whether the level has any water at all (asked once a level).
static func _has_water(world: LevelData) -> bool:
	var known: Variant = _watered.get(world)
	if known == null:
		var any := false
		for c in world.floor_tile.size():
			if world.surface_sound(int(world.floor_tile[c])) == "water":
				any = true
				break
		_watered.clear()
		_watered[world] = any
		known = any
	var out: bool = known
	return out


## A ball in water floats DUNK of its radius under the surface (play's
## body's height afloat, else the floor there): its floor is that far under.
func _rest_floor(i: int, under: float) -> float:
	if not _water or i >= _wet.size() or not _wet[i]:
		return under
	return maxf(under, _float_z) - radius[i] * (1.0 + DUNK)


func _floors_now() -> PackedFloat32Array:
	if not _water:
		return _fl.floor
	var out := _fl.floor.duplicate()
	for i in out.size():
		out[i] = _rest_floor(i, out[i])
	return out


## Afloat a ball is not carried at play's body's height (it floats under it).
func _floor(i: int, under: float, roof: float) -> bool:
	if not _water or i >= _wet.size() or not _wet[i]:
		return super._floor(i, under, roof)
	var p := pos[i]
	var low := _rest_floor(i, under) + radius[i]
	var on := p.z <= low
	if on:
		# Under water it comes up slowly (a gator shot swimming surfaces; set
		# on the surface at once it leapt out of the water).
		p.z = minf(low, p.z + FLOAT_RISE * STEP)
		old[i] = Vector3(old[i].x, old[i].y, minf(old[i].z, p.z))
	if roof > 0.0 and p.z + radius[i] > roof:
		p.z = maxf(low, roof - radius[i])
	pos[i] = p
	return on
