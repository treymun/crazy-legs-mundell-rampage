## How one kind's model hangs on a ragdoll (Ragdoll, src/ragdoll.gd): found
## once from the model itself (its labelled parts at the standing key "0").
##
## Thirteen points: the hips and shoulders (the torso's corners), the head,
## each elbow, hand, knee and foot. Ten rigid segments between them: the
## torso, the head, each upper arm, forearm, thigh and shin. Every part of
## the model (one bone each, actors.json `labels`) rides one segment: its
## label picks the limb, and how far down the limb it sits picks the upper or
## lower half. A kind whose parts do not make a body standing on two legs
## (a gator, a drone, a tire) has no rig (`ok` false) and keeps its scripted
## fall.
class_name RagdollRig
extends RefCounted

const HIP_L := 0
const HIP_R := 1
const SH_L := 2
const SH_R := 3
const HEAD := 4
const ELBOW_L := 5
const HAND_L := 6
const ELBOW_R := 7
const HAND_R := 8
const KNEE_L := 9
const FOOT_L := 10
const KNEE_R := 11
const FOOT_R := 12
## The belly and the back: two more balls held in the torso, as thick as it
## is (a body lies on its belly or its back, not on four corners).
const BELLY := 13
const BACK := 14
const POINTS := 15
const TORSO := 0
const HEAD_SEG := 1
## Each segment's [from, to] points (the torso is its four corners), its
## parent segment and the point that rides it at the start.
const ENDS := [
	[-1, -1],
	[-1, HEAD],
	[SH_L, ELBOW_L],
	[ELBOW_L, HAND_L],
	[SH_R, ELBOW_R],
	[ELBOW_R, HAND_R],
	[HIP_L, KNEE_L],
	[KNEE_L, FOOT_L],
	[HIP_R, KNEE_R],
	[KNEE_R, FOOT_R]
]
const PARENT := [-1, 0, 0, 2, 0, 4, 0, 6, 0, 8]
## The segment each point rides when the body is first posed from the model.
const RIDES := [0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0, 0]
## The biggest a limb's ball grows for its thickness (model units).
const THICKEST := .22
## Labels that must all have parts for a rig.
const LIMBS := ["body", "head", "arm_l", "arm_r", "leg_l", "leg_r"]
## The hull's fine ways: the points of a cube's faces FINE steps from its
## middle (218 of them at 3, at most about 18 degrees apart); a fine way
## goes in the bucket of each of ways() within BUCKET_EDGE of its nearest.
const FINE := 3
const BUCKET_EDGE := .15

var ok := false
## Where each point is at the key "0", model space (y up), and how big a ball
## it is against the floor and walls (model units).
var points := PackedVector3Array()
var radii := PackedFloat32Array()
## Each bone's segment, its pose at the key "0" and its scale once dead (a
## part the dead body has lost, the gun, is shrunk away).
var bone_seg := PackedInt32Array()
var bone_rest: Array[Transform3D] = []
var dead_scale := PackedVector3Array()
## Each segment's biggest bone (-1: none), to pose the points from the model.
var anchors := PackedInt32Array()
## Each segment's frame at the key "0" (from the points, as frames() makes it).
var rest_frames: Array[Transform3D] = []
## The points as the model's own body at rest ("down") has them: a body first
## seen already dead starts from there.
var down_points := PackedVector3Array()
## Each segment's outermost points in its rest frame (model units), in a
## bucket for each of ways() (Array[PackedVector3Array] each), and how far
## the furthest reaches from the frame's origin (_hull).
var hull: Array[Array] = []
var hull_reach := PackedFloat32Array()
var _rest_inv: Array[Basis] = []

static var _built := {}
static var _ways: Array[Vector3] = []


## Whether kind's rig has been found already.
static func has(kind: String) -> bool:
	return _built.has(kind)


## The rig of the model under `view` (an ActorView scene) for kind `kind`
## (its actors.json entry `info`), made once a kind.
static func of(kind: String, view: Node, info: Dictionary) -> RagdollRig:
	var cached: RagdollRig = _built.get(kind)
	if cached == null:
		cached = RagdollRig.new()
		cached._build(view, info)
		_built[kind] = cached
	return cached


func _build(view: Node, info: Dictionary) -> void:
	var skeletons := view.find_children("*", "Skeleton3D", true, false)
	var meshes := view.find_children("*", "MeshInstance3D", true, false)
	var players := view.find_children("*", "AnimationPlayer", true, false)
	if skeletons.is_empty() or meshes.is_empty() or players.is_empty():
		return
	var skeleton := skeletons[0] as Skeleton3D
	var player := players[0] as AnimationPlayer
	if player.get_animation_list().is_empty():
		return
	var anim := player.get_animation(player.get_animation_list()[0])
	var frames: Dictionary = info.get("frames", {})
	var labels: Dictionary = info.get("labels", {})
	if not frames.has("0") or not frames.has("down"):
		return
	var stand_key: float = frames["0"]
	var down_key: float = frames["down"]
	var bones := skeleton.get_bone_count()
	bone_rest = _poses(anim, skeleton, stand_key * ActorModels.KEY_TIME)
	var dead := _poses(anim, skeleton, down_key * ActorModels.KEY_TIME)
	dead_scale.resize(bones)
	for i in bones:
		dead_scale[i] = dead[i].basis.get_scale()
	# Every vertex where the standing key puts it, by its part's label.
	var clouds := {}
	var part_mid: Array[Vector3] = []
	var part_n := PackedInt32Array()
	part_mid.resize(bones)
	part_n.resize(bones)
	# A third of the vertices and their parts, for how thick each limb is.
	var every := PackedVector3Array()
	var every_bone := PackedInt32Array()
	# All of them, for each segment's outermost points (_hull).
	var all_at := PackedVector3Array()
	var all_bone := PackedInt32Array()
	for m: Node in meshes:
		var mesh := m as MeshInstance3D
		if mesh.mesh == null or mesh.skin == null:
			continue
		var skin := mesh.skin
		var bind_bone := PackedInt32Array()
		for b in skin.get_bind_count():
			var bone := skin.get_bind_bone(b)
			if bone < 0:
				bone = skeleton.find_bone(skin.get_bind_name(b))
			bind_bone.append(bone)
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var vb: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var vw: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if verts.is_empty() or vb.is_empty():
				continue
			var per := vb.size() / verts.size()
			for v in verts.size():
				var best := 0
				for k in per:
					if vw[v * per + k] > vw[v * per + best]:
						best = k
				var bind := vb[v * per + best]
				if bind < 0 or bind >= bind_bone.size():
					continue
				var bone := bind_bone[bind]
				if bone < 0 or bone >= bones:
					continue
				if bone_rest[bone].basis.get_scale().x < .2:
					continue
				var at := bone_rest[bone] * (skin.get_bind_pose(bind) * verts[v])
				var label: String = labels.get(skeleton.get_bone_name(bone), "body")
				if not clouds.has(label):
					clouds[label] = PackedVector3Array()
				var cloud: PackedVector3Array = clouds[label]
				cloud.append(at)
				clouds[label] = cloud
				part_mid[bone] += at
				part_n[bone] += 1
				all_at.append(at)
				all_bone.append(bone)
				if v % 3 == 0:
					every.append(at)
					every_bone.append(bone)
	for label: String in LIMBS:
		var cloud: PackedVector3Array = clouds.get(label, PackedVector3Array())
		if cloud.size() < 8:
			return
	if not _points(clouds):
		return
	# Each part's segment: by label, then the upper or lower half of the limb.
	bone_seg.resize(bones)
	anchors.resize(ENDS.size())
	anchors.fill(-1)
	var biggest := PackedInt32Array()
	biggest.resize(ENDS.size())
	for i in bones:
		var label: String = labels.get(skeleton.get_bone_name(i), "body")
		var mid: Vector3 = part_mid[i] / float(part_n[i]) if part_n[i] > 0 else bone_rest[i].origin
		var seg := TORSO
		match label:
			"head":
				seg = HEAD_SEG
			"arm_l":
				seg = _half(mid, SH_L, HAND_L, 2)
			"arm_r":
				seg = _half(mid, SH_R, HAND_R, 4)
			"leg_l":
				seg = _half(mid, HIP_L, FOOT_L, 6)
			"leg_r":
				seg = _half(mid, HIP_R, FOOT_R, 8)
		bone_seg[i] = seg
		if part_n[i] > biggest[seg]:
			biggest[seg] = part_n[i]
			anchors[seg] = i
	_thicken(every, every_bone)
	rest_frames = frames_of(points)
	_rest_inv.clear()
	for f: Transform3D in rest_frames:
		_rest_inv.append(f.basis.inverse())
	_hull(all_at, all_bone)
	down_points = points_from(dead)
	ok = true


## Each segment's outermost points (its parts' convex hull, a part the dead
## body loses left out), in the segment's rest frame, sorted into a bucket
## for each of the 26 ways (`ways()`): a bucket holds the hull's points that
## lie furthest out along the fine ways (FINE) nearest that way. The ragdoll
## keeps the lowest of them out of the floor, so a shoulder, a boot's toe or
## a hat's brim lying on the floor never sinks in; it looks in one bucket.
func _hull(cloud_at: PackedVector3Array, cloud_bone: PackedInt32Array) -> void:
	var local: Array[PackedVector3Array] = []
	for s in ENDS.size():
		local.append(PackedVector3Array())
	for k in cloud_at.size():
		var bone := cloud_bone[k]
		if dead_scale[bone].x < .2:
			continue
		var s := bone_seg[bone]
		local[s].append(rest_frames[s].affine_inverse() * cloud_at[k])
	var coarse := ways()
	var fine: Array[Vector3] = []
	for x in range(-FINE, FINE + 1):
		for y in range(-FINE, FINE + 1):
			for z in range(-FINE, FINE + 1):
				if maxi(absi(x), maxi(absi(y), absi(z))) == FINE:
					fine.append(Vector3(x, y, z).normalized())
	hull.clear()
	hull_reach.clear()
	for s in ENDS.size():
		var points := local[s]
		if points.size() >= 4:
			var mesh := ArrayMesh.new()
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = points
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
			var shape := mesh.create_convex_shape(true, false)
			if shape != null and shape.points.size() >= 4:
				points = shape.points
		var buckets: Array[PackedVector3Array] = []
		for c in coarse.size():
			buckets.append(PackedVector3Array())
		var reach := 0.0
		for p in points:
			reach = maxf(reach, p.length())
		if not points.is_empty():
			for way: Vector3 in fine:
				var best := points[0]
				var most := best.dot(way)
				for p in points:
					var d := p.dot(way)
					if d > most:
						most = d
						best = p
				# Into the bucket of each way near this one (a way between two
				# buckets is looked for in either).
				var near := -2.0
				for c: Vector3 in coarse:
					near = maxf(near, c.dot(way))
				for c in coarse.size():
					if coarse[c].dot(way) >= near - BUCKET_EDGE and not buckets[c].has(best):
						buckets[c].append(best)
		hull.append(buckets)
		hull_reach.append(reach)


## The 26 ways the hull's buckets look along (the cube's faces, edges and
## corners from its middle).
static func ways() -> Array[Vector3]:
	if _ways.is_empty():
		for x in range(-1, 2):
			for y in range(-1, 2):
				for z in range(-1, 2):
					if x != 0 or y != 0 or z != 0:
						_ways.append(Vector3(x, y, z).normalized())
	return _ways


## Each limb half's and the head's balls at least as big as the limb is thick
## (how far most of its vertices lie from the line between its ends; a part
## the dead body loses, the gun, left out): a forearm or a shin lying flat
## then sinks no deeper into the floor than its ends do.
func _thicken(every: PackedVector3Array, every_bone: PackedInt32Array) -> void:
	var far: Array[PackedFloat32Array] = []
	for s in ENDS.size():
		far.append(PackedFloat32Array())
	var neck := (points[SH_L] + points[SH_R]) * .5
	for k in every.size():
		var bone := every_bone[k]
		var s := bone_seg[bone]
		if s == TORSO or dead_scale[bone].x < .2:
			continue
		var a := _from(points, s, neck)
		var b := points[ENDS[s][1]]
		var run := b - a
		var t := clampf((every[k] - a).dot(run) / maxf(run.length_squared(), 1e-6), 0.0, 1.0)
		far[s].append(every[k].distance_to(a + run * t))
	for s in range(1, ENDS.size()):
		var list := far[s]
		if list.size() < 4:
			continue
		list.sort()
		var thick := minf(list[int(list.size() * .85)], THICKEST)
		for end: int in ENDS[s]:
			if end >= 0 and end != HIP_L and end != HIP_R and end != SH_L and end != SH_R:
				radii[end] = maxf(radii[end], thick)


## Upper (`first`) or lower (`first` + 1) half of the limb from point a to b.
func _half(mid: Vector3, a: int, b: int, first: int) -> int:
	var run := points[b] - points[a]
	var t := (mid - points[a]).dot(run) / maxf(run.length_squared(), 1e-6)
	return first if t < .5 else first + 1


## The thirteen points from the parts' clouds. False when they do not make a
## body standing on two legs, head over shoulders over hips over feet.
func _points(clouds: Dictionary) -> bool:
	points.resize(POINTS)
	radii.resize(POINTS)
	var body: PackedVector3Array = clouds["body"]
	var head: PackedVector3Array = clouds["head"]
	var box := _box(body)
	var tall := box.size.y
	var top := box.end.y
	# The neck: the middle of the torso's top.
	var neck := _mean(body, func(p: Vector3) -> bool: return p.y > top - tall * .1)
	neck.y = top
	for side: Array in [["leg_l", HIP_L, KNEE_L, FOOT_L], ["leg_r", HIP_R, KNEE_R, FOOT_R]]:
		var leg: PackedVector3Array = clouds[side[0]]
		var lb := _box(leg)
		var span := lb.size.y
		var hip := _mean(leg, func(p: Vector3) -> bool: return p.y > lb.end.y - span * .12)
		hip.y = lb.end.y
		var foot := _mean(leg, func(p: Vector3) -> bool: return p.y < lb.position.y + span * .12)
		var foot_box := _box_of(
			leg, func(p: Vector3) -> bool: return p.y < lb.position.y + span * .2
		)
		var foot_r := clampf(minf(foot_box.size.x, foot_box.size.z) * .55, .03, .14)
		foot.y = lb.position.y + foot_r
		var hip_i: int = side[1]
		var knee_i: int = side[2]
		var foot_i: int = side[3]
		points[hip_i] = hip
		points[foot_i] = foot
		points[knee_i] = (hip + foot) * .5 + Vector3(0, 0, .03)
		radii[foot_i] = foot_r
		radii[knee_i] = clampf(minf(lb.size.x, lb.size.z) * .4, .04, .12)
	for side: Array in [["arm_l", SH_L, ELBOW_L, HAND_L], ["arm_r", SH_R, ELBOW_R, HAND_R]]:
		var arm: PackedVector3Array = clouds[side[0]]
		var sh := arm[0]
		for p in arm:
			if p.distance_squared_to(neck) < sh.distance_squared_to(neck):
				sh = p
		var hand := sh
		for p in arm:
			if p.distance_squared_to(sh) > hand.distance_squared_to(sh):
				hand = p
		var ab := _box(arm)
		# The joint sits a little inside the arm's nearest point.
		var arm_mid := ab.get_center()
		sh = sh + (arm_mid - sh).normalized() * minf(.06, sh.distance_to(arm_mid) * .3)
		var sh_i: int = side[1]
		var elbow_i: int = side[2]
		var hand_i: int = side[3]
		points[sh_i] = sh
		points[hand_i] = hand
		points[elbow_i] = (sh + hand) * .5 + Vector3(0, 0, -.02)
		radii[hand_i] = clampf(minf(ab.size.x, ab.size.z) * .35, .035, .1)
		radii[elbow_i] = radii[hand_i]
	var hb := _box(head)
	points[HEAD] = hb.get_center()
	radii[HEAD] = clampf(minf(hb.size.x, minf(hb.size.y, hb.size.z)) * .5, .05, .22)
	var deep := clampf(box.size.z * .3, .06, .2)
	for i: int in [HIP_L, HIP_R, SH_L, SH_R]:
		radii[i] = deep
	var hips := (points[HIP_L] + points[HIP_R]) * .5
	var shoulders := (points[SH_L] + points[SH_R]) * .5
	# The belly and the back: the torso's front and back between hips and
	# shoulders (a belly sticks out further than the corners' balls reach).
	var low := hips.y + (shoulders.y - hips.y) * .15
	var high := hips.y + (shoulders.y - hips.y) * .85
	var trunk := _box_of(body, func(p: Vector3) -> bool: return p.y > low and p.y < high)
	var thick := clampf(trunk.size.z * .3, .05, .3)
	var mid := (hips + shoulders) * .5
	points[BELLY] = Vector3(mid.x, mid.y, trunk.end.z - thick)
	points[BACK] = Vector3(mid.x, mid.y, trunk.position.z + thick)
	radii[BELLY] = thick
	radii[BACK] = thick
	# Standing on two legs, head over shoulders over hips over feet.
	var feet := (points[FOOT_L] + points[FOOT_R]) * .5
	var height := points[HEAD].y - feet.y
	return (
		height > .3
		and hips.y - feet.y > height * .2
		and shoulders.y - hips.y > height * .12
		and points[HEAD].y > shoulders.y - height * .05
		and points[SH_L].distance_to(points[SH_R]) > height * .06
		and points[HIP_L].distance_to(points[HIP_R]) > height * .02
	)


static func _box(cloud: PackedVector3Array) -> AABB:
	var out := AABB(cloud[0], Vector3.ZERO)
	for p in cloud:
		out = out.expand(p)
	return out


static func _box_of(cloud: PackedVector3Array, keep: Callable) -> AABB:
	var out := AABB()
	var any := false
	for p in cloud:
		if keep.call(p):
			out = out.expand(p) if any else AABB(p, Vector3.ZERO)
			any = true
	return out


static func _mean(cloud: PackedVector3Array, keep: Callable) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for p in cloud:
		if keep.call(p):
			sum += p
			n += 1
	return sum / float(n) if n > 0 else _box(cloud).get_center()


## Every bone's pose (position, rotation, scale) at time t of the action.
static func _poses(anim: Animation, skeleton: Skeleton3D, t: float) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var bones := skeleton.get_bone_count()
	var pos: Array[Vector3] = []
	var rot: Array[Quaternion] = []
	var size: Array[Vector3] = []
	for i in bones:
		var rest := skeleton.get_bone_rest(i)
		pos.append(rest.origin)
		rot.append(rest.basis.get_rotation_quaternion())
		size.append(rest.basis.get_scale())
	for track in anim.get_track_count():
		var path := anim.track_get_path(track)
		var bone := skeleton.find_bone(path.get_concatenated_subnames())
		if bone < 0:
			continue
		match anim.track_get_type(track):
			Animation.TYPE_POSITION_3D:
				pos[bone] = anim.position_track_interpolate(track, t)
			Animation.TYPE_ROTATION_3D:
				rot[bone] = anim.rotation_track_interpolate(track, t)
			Animation.TYPE_SCALE_3D:
				size[bone] = anim.scale_track_interpolate(track, t)
	for i in bones:
		out.append(Transform3D(Basis(rot[i]).scaled(size[i]), pos[i]))
	return out


## Each segment's frame (an orthonormal turn and an origin) from where the
## points are: the torso from its corners, the head and each limb half turned
## from its parent by the least turn that carries its rest direction onto its
## direction now (no twist of its own).
func frames_of(at: PackedVector3Array) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.resize(ENDS.size())
	var hips := (at[HIP_L] + at[HIP_R]) * .5
	var shoulders := (at[SH_L] + at[SH_R]) * .5
	var up := (shoulders - hips).normalized()
	var across := ((at[SH_R] - at[SH_L]) + (at[HIP_R] - at[HIP_L])).normalized()
	across = (across - up * across.dot(up)).normalized()
	var torso := Basis(across, up, across.cross(up)).orthonormalized()
	out[TORSO] = Transform3D(torso, hips)
	if rest_frames.is_empty():
		# The rest frames themselves: every segment starts square with the torso.
		for s in range(1, ENDS.size()):
			out[s] = Transform3D(torso, _from(at, s, shoulders))
		return out
	var turn_torso := torso * _rest_inv[TORSO]
	for s in range(1, ENDS.size()):
		var parent: int = PARENT[s]
		var base := out[parent].basis * _rest_inv[parent]
		if parent == TORSO:
			base = turn_torso
		var start := _from(at, s, shoulders)
		var rest_start := _from(points, s, (points[SH_L] + points[SH_R]) * .5)
		var end_i: int = ENDS[s][1]
		var was := base * (points[end_i] - rest_start)
		var now := at[end_i] - start
		var arc := _arc(was, now)
		out[s] = Transform3D(arc * base * rest_frames[s].basis, start)
	return out


## Where segment s starts: the neck for the head, else its first point.
static func _from(at: PackedVector3Array, s: int, neck: Vector3) -> Vector3:
	var a: int = ENDS[s][0]
	return neck if a < 0 else at[a]


## The least turn carrying direction a onto direction b.
static func _arc(a: Vector3, b: Vector3) -> Basis:
	var la := a.length()
	var lb := b.length()
	if la < 1e-6 or lb < 1e-6:
		return Basis.IDENTITY
	var u := a / la
	var v := b / lb
	var d := clampf(u.dot(v), -1.0, 1.0)
	if d > .99999:
		return Basis.IDENTITY
	var axis := u.cross(v)
	if axis.length_squared() < 1e-10:
		axis = u.cross(Vector3.RIGHT if absf(u.x) < .9 else Vector3.UP)
	return Basis(axis.normalized(), acos(d))


## Every bone's pose for the points `at` (model space), and whether each part
## is shown (`dead`: the dead body's lost parts shrunk away).
func pose(skeleton: Skeleton3D, at: PackedVector3Array, dead: bool) -> void:
	var now := frames_of(at)
	var moves: Array[Transform3D] = []
	for s in ENDS.size():
		moves.append(now[s] * rest_frames[s].affine_inverse())
	for i in bone_seg.size():
		var p := moves[bone_seg[i]] * bone_rest[i]
		var size := bone_rest[i].basis.get_scale()
		if dead and dead_scale[i].x < .2:
			size = Vector3(.001, .001, .001)
		skeleton.set_bone_pose_position(i, p.origin)
		skeleton.set_bone_pose_rotation(i, p.basis.get_rotation_quaternion())
		skeleton.set_bone_pose_scale(i, size)


## The points where the model's current pose (whatever it last showed) puts
## them, model space: each rides its segment's biggest part.
func posed_points(skeleton: Skeleton3D) -> PackedVector3Array:
	var poses: Array[Transform3D] = []
	for i in skeleton.get_bone_count():
		poses.append(skeleton.get_bone_pose(i))
	return points_from(poses)


## The points where the bones' poses `poses` put them, model space.
func points_from(poses: Array[Transform3D]) -> PackedVector3Array:
	var moves: Array[Transform3D] = []
	for s in ENDS.size():
		var a := anchors[s]
		var m := Transform3D.IDENTITY
		if a >= 0 and a < poses.size():
			var now := poses[a]
			if now.basis.get_scale().x > .2:
				var rest := bone_rest[a]
				m = (
					Transform3D(now.basis.orthonormalized(), now.origin)
					* (Transform3D(rest.basis.orthonormalized(), rest.origin).affine_inverse())
				)
			elif s > 0:
				m = moves[PARENT[s]]
		elif s > 0:
			m = moves[PARENT[s]]
		moves.append(m)
	var out := PackedVector3Array()
	out.resize(POINTS)
	for i in POINTS:
		out[i] = moves[RIDES[i]] * points[i]
	return out
