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
## legs catch on one and it goes over it head first). Map coordinates
## throughout: x and y across the floor, z up.
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
const REASK := .03

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
## Each ball's floor and roof this step.
var _floors := PackedFloat32Array()
var _roofs := PackedFloat32Array()
## Where each ball's floor was last asked from (INF: ask again).
var _asked := PackedVector3Array()

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
func settle(world: LevelData, most := 240) -> void:
	for _k in most:
		if not awake:
			return
		step(world)


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
	if not awake:
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
	if _floors.size() != count:
		_floors.resize(count)
		_roofs.resize(count)
		_asked.resize(count)
		_asked.fill(Vector3.INF)
	var plain := _plain(world)
	if plain:
		# Open floor all round: the cells' own ground and roof, no walls.
		for i in count:
			var p := pos[i]
			var c := int(p.y) * world.width + int(p.x)
			_floors[i] = world.ground[c]
			_roofs[i] = world.roof[c] if world.roof[c] > old[i].z + .01 else 0.0
			_asked[i] = Vector3.INF
	else:
		for i in count:
			var p := pos[i]
			var o := old[i]
			var r := radius[i]
			var z := o.z - r + .03
			var was := _asked[i]
			# The floor asked a step or two ago still holds for a ball that has
			# hardly moved across and is no higher than it was asked from.
			if (
				absf(p.x - was.x) < REASK
				and absf(p.y - was.y) < REASK
				and z <= was.z + .01
				and z >= _floors[i] - .01
			):
				continue
			_asked[i] = Vector3(p.x, p.y, z)
			_floors[i] = Tumble.floor_at(world, p.x, p.y, z, r * .6)
			_roofs[i] = world.roof_over(p.x, p.y, o.z)
	var touching := PackedByteArray()
	touching.resize(count)
	for _pass in PASSES:
		_links()
		_hinges()
		for i in count:
			if _floor(i, _floors[i], _roofs[i]):
				touching[i] = 1
	if not plain:
		# Last, nothing ends the step inside a wall, a slab's side or a rail
		# (the links may have pulled a ball in).
		for i in count:
			_walls(world, i)
			_floor(i, _floors[i], _roofs[i])
	# Play's body's move carried the balls along; it is not theirs to keep
	# going with (each frame brings its own), as far as they made it.
	var reach := shoved.length()
	if reach > 1e-6:
		var way := shoved / reach
		for i in count:
			var k := clampf((pos[i] - old[i]).dot(way) / reach, 0.0, 1.0)
			old[i] += shoved * k
	# Friction: a ball on the floor slides less far.
	for i in count:
		if touching[i]:
			var p := pos[i]
			var o := old[i]
			old[i] = Vector3(p.x - (p.x - o.x) * GRIP, p.y - (p.y - o.y) * GRIP, o.z)
	var most := 0.0
	for i in count:
		most = maxf(most, pos[i].distance_squared_to(old[i]))
	if most < SLEEP_MOVE * SLEEP_MOVE:
		still += STEP
	else:
		still = 0.0
	if still > SLEEP_AFTER or age > MOST_AWAKE:
		awake = false
		# Laid to rest on the floor really under each ball (not one asked a
		# step or two ago).
		for i in count:
			var p := pos[i]
			var r := radius[i]
			if not plain:
				var under := Tumble.floor_at(world, p.x, p.y, p.z - r + .03, r * .6)
				pos[i] = Vector3(p.x, p.y, maxf(p.z, under + r))
			old[i] = pos[i]


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
## the cells' ground and roof are all there is.
func _plain(world: LevelData) -> bool:
	if world.index_cells.size() != world.width * world.height:
		return false
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pos:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var x0 := int(lo.x - .3)
	var y0 := int(lo.y - .3)
	var x1 := int(hi.x + .3)
	var y1 := int(hi.y + .3)
	if x0 < 0 or y0 < 0 or x1 >= world.width or y1 >= world.height:
		return false
	var geo := world.geo
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var c := y * world.width + x
			if world.solid[c] >= 0 or world.index_cells[c] != 0:
				return false
			if geo != null and geo.cells[c] != 0:
				return false
	for pane: Vector2i in world.pane_tiles:
		if pane.x >= x0 - 1 and pane.x <= x1 + 1 and pane.y >= y0 - 1 and pane.y <= y1 + 1:
			return false
	for gate: LevelData.Gate in world.locked_gates:
		if (
			absf(gate.x - (lo.x + hi.x) * .5) < gate.width + 3.0
			and absf(gate.y - (lo.y + hi.y) * .5) < 3.0
		):
			return false
	return true


static func _solid(world: LevelData, p: Vector3, r: float) -> bool:
	return world.blocked(p.x, p.y, r * .8, p.z) or _rail_at(world, p, r) != null


## The rail (a free wall that lets sight by, which blocked() leaves out) a
## ball of radius r at p is in, or null.
static func _rail_at(world: LevelData, p: Vector3, r: float) -> LevelGeometry.Segment:
	if world.geo == null or world.geo.clear_at(p.x, p.y):
		return null
	for item: Variant in world.geo.near_items(p.x, p.y):
		if item is LevelGeometry.Segment:
			var s: LevelGeometry.Segment = item
			if not s.sight and p.z + r > s.z0 and p.z - r < s.z1:
				var reach := r * .8 + s.half
				if s.dist2(p.x, p.y) < reach * reach:
					return s
	return null


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
