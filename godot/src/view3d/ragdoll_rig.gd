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
## Each kind's rig as found from its model is kept beside it
## (assets3d/actors/<kind>.rig, tools/art/bake_rigs.gd; pass 10): finding it
## took 35 to 100 ms a kind at a level's first frame (a vertex walk of 20 to
## 40 thousand vertices and the hull's 218 ways), read back it takes a
## fraction of a millisecond. A file of another format, or made from other
## actors.json labels or keys than the kind has now, is not used (the rig is
## found again); tools/load_check.gd holds every file to the rig found anew.
const BAKED := "res://assets3d/actors/%s.rig"
const BAKED_FORMAT := 3
## Labels that must all have parts for a rig.
const LIMBS := ["body", "head", "arm_l", "arm_r", "leg_l", "leg_r"]
## The hull's fine ways: the points of a cube's faces FINE steps from its
## middle (218 of them at 3, at most about 18 degrees apart); a fine way
## goes in the bucket of each of ways() within BUCKET_EDGE of its nearest.
const FINE := 3
const BUCKET_EDGE := .15
## Balls to a piece of gear the dead body lets go of (gear_bones).
const GEAR_BALLS := 3

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
## The points as the model's own body at rest ("down") has them (a tool's
## pose to drop from).
var down_points := PackedVector3Array()
## The points lying on the back on the floor (_lie_down), and the gear's
## balls beside it.
var lying_points := PackedVector3Array()
var gear_lying := PackedVector3Array()
## Each segment's outermost points in its rest frame (model units), in a
## bucket for each of ways() (Array[PackedVector3Array] each), and how far
## the furthest reaches from the frame's origin (_hull).
var hull: Array[Array] = []
var hull_reach := PackedFloat32Array()
var _rest_inv: Array[Basis] = []
## What the dead body lets go of (the gun, the saw, the shield; pass 11):
## each a cluster of the parts the dead body loses that sits by a hand, and
## falls as a rigid triangle of three balls of its own (Ragdoll: POINTS +
## GEAR_BALLS g and the next two: its two ends and a third across it, so a
## shield or a saw comes to lie flat) instead of shrinking away. Per piece:
## its bones, its balls at the standing key (model space), their radius.
var gear_bones: Array[PackedInt32Array] = []
var gear_ends := PackedVector3Array()
var gear_radius := PackedFloat32Array()
## Each piece's box's eight corners at the standing key (model space).
var gear_corners := PackedVector3Array()
## Each bone's part's box at the standing key (model space: its vertices'
## least and most), for the gear's size (baked).
var bone_lo := PackedVector3Array()
var bone_hi := PackedVector3Array()
## Each bone's piece of gear (-1: none).
var bone_gear := PackedInt32Array()
## The segment each bone is posed with (bone_seg, but a hand the model
## labels "body", holding the gun before it, rides its forearm: lying on its
## back a body held its empty hands up off its chest; _find_gear).
var bone_ride := PackedInt32Array()
## Each limb (left arm, right arm, left leg, right leg) that is one part to
## its end (a whole arm modelled as one piece, bent as it stands): it does
## not bend at its elbow or knee (1), else 0 (_find_gear).
var stiff := PackedByteArray()
## Worked out once from the rest pose (pass 15; frames_of and pose ask them
## every frame): each segment's start at rest and its end point, each
## segment's rest frame turned back, each bone's size at rest.
var _rest_start := PackedVector3Array()
var _end_of := PackedInt32Array()
var _rest_back: Array[Transform3D] = []
var _bone_size := PackedVector3Array()

static var _built := {}
## How many rigs this process found from their models' vertices (_build),
## not read back baked (tools/load_speed_check.gd holds a level's load to 0).
static var found := 0
static var _ways: Array[Vector3] = []
static var _fine: Array[Vector3] = []
static var _fine_near: Array[PackedInt32Array] = []


## Whether kind's rig has been found already.
static func has(kind: String) -> bool:
	return _built.has(kind)


## The rig of the model under `view` (an ActorView scene) for kind `kind`
## (its actors.json entry `info`), made once a kind. A kind fit.json gives a
## "beast" plan (a gator, a crawler, a hog, the cow: pass 13) hangs on a
## BeastRig instead.
static func of(kind: String, view: Node, info: Dictionary) -> RagdollRig:
	var cached: RagdollRig = _built.get(kind)
	if cached == null:
		if info.has("beast"):
			cached = BeastRig.read(kind, view, info)
		else:
			cached = baked(kind, view, info)
		if cached == null:
			cached = RagdollRig.fresh(info)
			cached.build(view, info)
		_built[kind] = cached
	return cached


## A rig not yet built for a kind of this actors.json entry: a BeastRig for
## a "beast" plan.
static func fresh(info: Dictionary) -> RagdollRig:
	return BeastRig.new() if info.has("beast") else RagdollRig.new()


## Found from the model under `view` (tools/art/bake_rigs.gd, of()).
func build(view: Node, info: Dictionary) -> void:
	_build(view, info)


## How many segments, each segment's parent, the segment each point rides at
## the start, and how many points (RagdollRig's constants; a BeastRig's own).
func segs() -> int:
	return ENDS.size()


func parent_of(s: int) -> int:
	return PARENT[s]


func rides_of(i: int) -> int:
	return RIDES[i]


func point_n() -> int:
	return POINTS


## What of the actors.json entry the rig is found from: its standing and
## dead keys and its parts' labels (a baked rig names it).
static func info_key(info: Dictionary) -> String:
	var frames: Dictionary = info.get("frames", {})
	var labels: Dictionary = info.get("labels", {})
	return var_to_str([frames.get("0"), frames.get("down"), labels]).md5_text()


## The kind's baked rig (BAKED) put back on the model under `view`, or null
## when there is none or it was made from other labels or keys.
static func baked(kind: String, view: Node, info: Dictionary) -> RagdollRig:
	var path := BAKED % kind
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 8:
		return null
	var whole: Variant = bytes_to_var(
		bytes.slice(4).decompress(bytes.decode_u32(0), FileAccess.COMPRESSION_DEFLATE)
	)
	if not whole is Array:
		return null
	var row: Array = whole
	if row.size() != 11 or row[0] != BAKED_FORMAT or row[1] != info_key(info):
		return null
	var rig := RagdollRig.new()
	if not row[2]:
		return rig
	var skeletons := view.find_children("*", "Skeleton3D", true, false)
	var players := view.find_children("*", "AnimationPlayer", true, false)
	if skeletons.is_empty() or players.is_empty():
		return null
	var skeleton := skeletons[0] as Skeleton3D
	var player := players[0] as AnimationPlayer
	var anim := player.get_animation(player.get_animation_list()[0])
	var frames: Dictionary = info.get("frames", {})
	var stand_key: float = frames["0"]
	var down_key: float = frames["down"]
	# What the build found from the model's vertices, read back; the rest
	# (the poses and what follows from them) made again as _build makes it.
	rig.points = row[3]
	rig.radii = row[4]
	rig.bone_seg = row[5]
	rig.anchors = row[6]
	rig.hull_reach = row[8]
	rig.bone_lo = row[9]
	rig.bone_hi = row[10]
	for buckets: Array in row[7]:
		var typed: Array[PackedVector3Array] = []
		for bucket: PackedVector3Array in buckets:
			typed.append(bucket)
		rig.hull.append(typed)
	rig.bone_rest = _poses(anim, skeleton, stand_key * ActorModels.KEY_TIME)
	var dead := _poses(anim, skeleton, down_key * ActorModels.KEY_TIME)
	rig.dead_scale.resize(skeleton.get_bone_count())
	for i in skeleton.get_bone_count():
		rig.dead_scale[i] = dead[i].basis.get_scale()
	rig.rest_frames = rig.frames_of(rig.points)
	for f: Transform3D in rig.rest_frames:
		rig._rest_inv.append(f.basis.inverse())
	rig.down_points = rig.points_from(dead)
	rig._find_gear()
	rig._lie_down()
	rig.ok = true
	return rig


## The rig as BAKED keeps it (tools/art/bake_rigs.gd): deflated, behind its
## size.
func to_baked(info: Dictionary) -> PackedByteArray:
	var row: Array = [BAKED_FORMAT, info_key(info), ok]
	if ok:
		row.append_array([points, radii, bone_seg, anchors, hull, hull_reach, bone_lo, bone_hi])
	else:
		row.append_array([null, null, null, null, null, null, null, null])
	var raw := var_to_bytes(row)
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, raw.size())
	out.append_array(raw.compress(FileAccess.COMPRESSION_DEFLATE))
	return out


func _build(view: Node, info: Dictionary) -> void:
	found += 1
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
	var part_mid: Array[Vector3] = []
	var part_n := PackedInt32Array()
	part_mid.resize(bones)
	part_n.resize(bones)
	bone_lo.resize(bones)
	bone_hi.resize(bones)
	# A third of the vertices and their parts, for how thick each limb is.
	var every := PackedVector3Array()
	var every_bone := PackedInt32Array()
	# All of them, for each segment's outermost points (_hull).
	var all_at := PackedVector3Array()
	var all_bone := PackedInt32Array()
	# Each bone's label (by number) and whether it shows at the standing key,
	# found once a bone rather than once a vertex (pass 10: a kind's rig took
	# 35 to 100 ms at a level's first frame, most of it here and in _hull).
	var label_names := PackedStringArray()
	var bone_label := PackedInt32Array()
	var bone_keep := PackedByteArray()
	bone_label.resize(bones)
	bone_keep.resize(bones)
	for i in bones:
		var name: String = labels.get(skeleton.get_bone_name(i), "body")
		if not name in label_names:
			label_names.append(name)
		bone_label[i] = label_names.find(name)
		bone_keep[i] = 0 if bone_rest[i].basis.get_scale().x < .2 else 1
	var all_label := PackedInt32Array()
	for m: Node in meshes:
		var mesh := m as MeshInstance3D
		if mesh.mesh == null or mesh.skin == null:
			continue
		var skin := mesh.skin
		var bind_bone := PackedInt32Array()
		var bind_pose: Array[Transform3D] = []
		for b in skin.get_bind_count():
			var bone := skin.get_bind_bone(b)
			if bone < 0:
				bone = skeleton.find_bone(skin.get_bind_name(b))
			bind_bone.append(bone)
			bind_pose.append(skin.get_bind_pose(b))
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
				if bone_keep[bone] == 0:
					continue
				var at := bone_rest[bone] * (bind_pose[bind] * verts[v])
				part_mid[bone] += at
				if part_n[bone] == 0:
					bone_lo[bone] = at
					bone_hi[bone] = at
				else:
					bone_lo[bone] = bone_lo[bone].min(at)
					bone_hi[bone] = bone_hi[bone].max(at)
				part_n[bone] += 1
				all_at.append(at)
				all_bone.append(bone)
				# A part the dead body loses (the gun, the saw, the shield) is no
				# part of the limbs' shape (pass 11: a hand at a gun's muzzle, a
				# shoulder on the saw).
				all_label.append(bone_label[bone] if dead_scale[bone].x >= .2 else -1)
				if v % 3 == 0:
					every.append(at)
					every_bone.append(bone)
	# Each label's cloud in the vertices' order, made in one pass (appending
	# to an array held in a Dictionary copied it whole every time).
	var clouds := {}
	for l in label_names.size():
		var cloud := PackedVector3Array()
		for k in all_at.size():
			if all_label[k] == l:
				cloud.append(all_at[k])
		if not cloud.is_empty():
			clouds[label_names[l]] = cloud
	_mirror_limbs(clouds)
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
	_find_gear()
	_lie_down()
	ok = true


## The pieces the dead body lets go of (gear_bones): the parts it loses
## (dead_scale) that show standing, joined where they lie within a tenth of
## its height of one another, kept when the cluster's middle is nearer a hand
## or an elbow than the head, a knee or a foot (a cigarette or a boot's
## second toe still shrinks away); the two biggest. Found from the poses,
## never baked.
func _find_gear() -> void:
	var height := maxf(.3, points[HEAD].y - (points[FOOT_L].y + points[FOOT_R].y) * .5)
	var lost := PackedInt32Array()
	for i in bone_rest.size():
		if dead_scale[i].x < .2 and bone_rest[i].basis.get_scale().x >= .2:
			lost.append(i)
	bone_ride = bone_seg.duplicate()
	var hips := (points[HIP_L] + points[HIP_R]) * .5
	var neck := (points[SH_L] + points[SH_R]) * .5
	var core := maxf(radii[BELLY], radii[HIP_L])
	for i in bone_seg.size():
		if bone_seg[i] != TORSO or dead_scale[i].x < .2:
			continue
		var o := bone_rest[i].origin
		var spine := o.distance_to(Geometry3D.get_closest_point_to_segment(o, hips, neck))
		var best := -1
		var best_d := INF
		for seg in range(2, 6):
			var a := points[ENDS[seg][0]]
			var b := points[ENDS[seg][1]]
			var d := o.distance_to(Geometry3D.get_closest_point_to_segment(o, a, b))
			if d < best_d:
				best_d = d
				best = seg
		# (Only a small part: a hand, a cuff; never a plate of the chest.)
		var small := i < bone_lo.size() and (bone_hi[i] - bone_lo[i]).length() < height * .12
		if small and best_d < height * .16 and best_d < spine - core * .6:
			bone_ride[i] = best
	# A limb half with no part of its own shown on the dead body: the limb is
	# one piece and bends nowhere.
	var shown := PackedInt32Array()
	shown.resize(ENDS.size())
	for i in bone_seg.size():
		if dead_scale[i].x >= .2 and bone_rest[i].basis.get_scale().x >= .2:
			shown[bone_ride[i]] += 1
	stiff = PackedByteArray()
	for limb in 4:
		var upper := 2 + limb * 2
		var one := shown[upper] == 0 or shown[upper + 1] == 0
		# A part of the upper half reaching well past the elbow (a whole arm
		# modelled bent as one piece): the limb bends nowhere either.
		var half := points[ENDS[upper][0]].distance_to(points[ENDS[upper][1]])
		if upper < hull_reach.size() and hull_reach[upper] > half * 1.45:
			one = true
		stiff.append(1 if one else 0)
	bone_gear = PackedInt32Array()
	bone_gear.resize(bone_rest.size())
	bone_gear.fill(-1)
	gear_bones.clear()
	gear_ends = PackedVector3Array()
	gear_radius = PackedFloat32Array()
	gear_corners = PackedVector3Array()
	# Clusters by single link (a part within `join` of any part of one is in it).
	var join := height * .1
	var cluster := PackedInt32Array()
	cluster.resize(lost.size())
	cluster.fill(-1)
	var clusters: Array[PackedInt32Array] = []
	for k in lost.size():
		if cluster[k] >= 0:
			continue
		var group := PackedInt32Array([k])
		cluster[k] = clusters.size()
		var at := 0
		while at < group.size():
			var o := bone_rest[lost[group[at]]].origin
			for m in lost.size():
				if cluster[m] < 0 and bone_rest[lost[m]].origin.distance_to(o) < join:
					cluster[m] = clusters.size()
					group.append(m)
			at += 1
		clusters.append(group)
	clusters.sort_custom(
		func(a: PackedInt32Array, b: PackedInt32Array) -> bool: return a.size() > b.size()
	)
	for group: PackedInt32Array in clusters:
		if gear_bones.size() >= 2:
			break
		var mid := Vector3.ZERO
		for k in group:
			mid += bone_rest[lost[k]].origin
		mid /= float(group.size())
		var held := INF
		var other := INF
		for i: int in [HAND_L, HAND_R, ELBOW_L, ELBOW_R]:
			held = minf(held, points[i].distance_to(mid))
		for i: int in [HEAD, KNEE_L, KNEE_R, FOOT_L, FOOT_R]:
			other = minf(other, points[i].distance_to(mid))
		if held >= other:
			continue
		# Its balls from its parts' boxes' corners, along its own ways (the
		# longest, the next, the thinnest: a gun held slanting is long and
		# thin all the same): the two ends of its length, a third out along
		# its width (a shield's far edge), each as thick as it is thin.
		var corners := PackedVector3Array()
		for k in group:
			var bone := lost[k]
			if bone < bone_lo.size() and bone_lo[bone] != bone_hi[bone]:
				for c in 8:
					corners.append(
						Vector3(
							bone_hi[bone].x if c & 1 else bone_lo[bone].x,
							bone_hi[bone].y if c & 2 else bone_lo[bone].y,
							bone_hi[bone].z if c & 4 else bone_lo[bone].z
						)
					)
		if corners.is_empty():
			continue
		var axes := _axes(corners)
		var lo := Vector3.INF
		var hi := -Vector3.INF
		for p in corners:
			var q := Vector3(p.dot(axes[0]), p.dot(axes[1]), p.dot(axes[2]))
			lo = lo.min(q)
			hi = hi.max(q)
		var r := clampf((hi.z - lo.z) * .5 + .005, height * .02, height * .2)
		var centre := (lo + hi) * .5
		var a := axes[0] * minf(lo.x + r, centre.x) + axes[1] * (lo.y + r) + axes[2] * centre.z
		var b := axes[0] * maxf(hi.x - r, centre.x) + axes[1] * (lo.y + r) + axes[2] * centre.z
		var c := axes[0] * centre.x + axes[1] * maxf(hi.y - r, lo.y + r * 3.0) + axes[2] * centre.z
		var bones := PackedInt32Array()
		for k in group:
			bones.append(lost[k])
			bone_gear[lost[k]] = gear_bones.size()
		gear_bones.append(bones)
		gear_ends.append_array([a, b, c])
		gear_radius.append(r)
		for k in 8:
			gear_corners.append(
				(
					axes[0] * (hi.x if k & 1 else lo.x)
					+ axes[1] * (hi.y if k & 2 else lo.y)
					+ axes[2] * (hi.z if k & 4 else lo.z)
				)
			)


## The three ways a cloud of points lies along (unit, at right angles): the
## longest first, the thinnest last (a few rounds of the power method on its
## spread).
static func _axes(cloud: PackedVector3Array) -> Array[Vector3]:
	var mean := Vector3.ZERO
	for p in cloud:
		mean += p
	mean /= float(cloud.size())
	var cx := Vector3.ZERO
	var cy := Vector3.ZERO
	var cz := Vector3.ZERO
	for p in cloud:
		var d := p - mean
		cx += d * d.x
		cy += d * d.y
		cz += d * d.z
	var spread := Basis(cx, cy, cz)
	var first := Vector3(1.0, .7, .3)
	for _k in 24:
		var next := spread * first
		if next.length_squared() < 1e-12:
			break
		first = next.normalized()
	var second := first.cross(Vector3.UP if absf(first.y) < .9 else Vector3.RIGHT).normalized()
	for _k in 24:
		var next := spread * second
		next -= first * next.dot(first)
		if next.length_squared() < 1e-12:
			break
		second = next.normalized()
	return [first, second, first.cross(second).normalized()]


## The gear's sticks where the bones' poses `poses` put them (model space).
func gear_from(poses: Array[Transform3D]) -> PackedVector3Array:
	var out := PackedVector3Array()
	for g in gear_bones.size():
		var bone := gear_bones[g][0]
		var m := Transform3D.IDENTITY
		if bone < poses.size():
			var now := poses[bone]
			var rest := bone_rest[bone]
			m = (
				Transform3D(now.basis.orthonormalized(), now.origin)
				* Transform3D(rest.basis.orthonormalized(), rest.origin).affine_inverse()
			)
		for k in GEAR_BALLS:
			out.append(m * gear_ends[g * GEAR_BALLS + k])
	return out


## The points lying on the back on the floor (y 0), the torso's middle over
## the origin: the standing points turned face up about the torso's middle.
## A body first seen long dead starts so (a few steps fit it to the floor).
func _lie_down() -> void:
	var mid := (points[HIP_L] + points[HIP_R] + points[SH_L] + points[SH_R]) * .25
	var turn := Basis(Vector3.RIGHT, -PI * .5)
	lying_points = PackedVector3Array()
	var low := INF
	for i in POINTS:
		var p := turn * (points[i] - mid)
		lying_points.append(p)
		low = minf(low, p.y - radii[i])
	for i in POINTS:
		lying_points[i] = lying_points[i] - Vector3(0.0, low, 0.0)
	# The gear beside it on the floor, as it was held turned with the body.
	gear_lying = PackedVector3Array()
	for g in gear_bones.size():
		for k in GEAR_BALLS:
			var p := turn * (gear_ends[g * GEAR_BALLS + k] - mid) - Vector3(0.0, low, 0.0)
			gear_lying.append(Vector3(p.x, gear_radius[g], p.z))


## The points lying on the back (lying_points), the gear beside it after.
func lying() -> PackedVector3Array:
	var out := lying_points.duplicate()
	out.append_array(gear_lying)
	return out


## Each segment's outermost points (its parts' convex hull, a part the dead
## body loses left out), in the segment's rest frame, sorted into a bucket
## for each of the 26 ways (`ways()`): a bucket holds the hull's points that
## lie furthest out along the fine ways (FINE) nearest that way. The ragdoll
## keeps the lowest of them out of the floor, so a shoulder, a boot's toe or
## a hat's brim lying on the floor never sinks in; it looks in one bucket.
func _hull(cloud_at: PackedVector3Array, cloud_bone: PackedInt32Array) -> void:
	var local: Array[PackedVector3Array] = []
	for s in segs():
		local.append(PackedVector3Array())
	for k in cloud_at.size():
		var bone := cloud_bone[k]
		if dead_scale[bone].x < .2:
			continue
		var s := bone_seg[bone]
		local[s].append(rest_frames[s].affine_inverse() * cloud_at[k])
	var coarse := ways()
	var fine := _fine_ways()
	hull.clear()
	hull_reach.clear()
	for s in segs():
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
			for w in fine.size():
				var way := fine[w]
				var best := points[0]
				var most := best.dot(way)
				for p in points:
					var d := p.dot(way)
					if d > most:
						most = d
						best = p
				# Into the bucket of each way near this one (a way between two
				# buckets is looked for in either: _fine_buckets).
				for c: int in _fine_near[w]:
					if not buckets[c].has(best):
						buckets[c].append(best)
		hull.append(buckets)
		hull_reach.append(reach)


## The hull's fine ways (FINE), found once; and for each, the buckets of
## ways() it goes in (those within BUCKET_EDGE of its nearest), as _hull
## used to work out again for every segment of every kind.
static func _fine_ways() -> Array[Vector3]:
	if _fine.is_empty():
		var coarse := ways()
		for x in range(-FINE, FINE + 1):
			for y in range(-FINE, FINE + 1):
				for z in range(-FINE, FINE + 1):
					if maxi(absi(x), maxi(absi(y), absi(z))) == FINE:
						_fine.append(Vector3(x, y, z).normalized())
		for way: Vector3 in _fine:
			var near := -2.0
			for c: Vector3 in coarse:
				near = maxf(near, c.dot(way))
			var into := PackedInt32Array()
			for c in coarse.size():
				if coarse[c].dot(way) >= near - BUCKET_EDGE:
					into.append(c)
			_fine_near.append(into)
	return _fine


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


## A limb with (almost) nothing of its own left once the dead body's lost
## parts are left out (the millhand's arm on his saw, the tin guard's behind
## his shield) takes the other side's, mirrored across the body (pass 11).
static func _mirror_limbs(clouds: Dictionary) -> void:
	for pair: Array in [
		["arm_l", "arm_r"], ["arm_r", "arm_l"], ["leg_l", "leg_r"], ["leg_r", "leg_l"]
	]:
		var own: PackedVector3Array = clouds.get(pair[0], PackedVector3Array())
		var other: PackedVector3Array = clouds.get(pair[1], PackedVector3Array())
		if own.size() >= 8 or other.size() < 8:
			continue
		var mirrored := PackedVector3Array()
		for p in other:
			mirrored.append(Vector3(-p.x, p.y, p.z))
		clouds[pair[0]] = mirrored


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
	if _rest_start.size() != ENDS.size():
		_rest_start.resize(ENDS.size())
		_end_of.resize(ENDS.size())
		for s in range(1, ENDS.size()):
			_rest_start[s] = _from(points, s, (points[SH_L] + points[SH_R]) * .5)
			_end_of[s] = ENDS[s][1]
	for s in range(1, ENDS.size()):
		var parent: int = PARENT[s]
		var base := out[parent].basis * _rest_inv[parent]
		if parent == TORSO:
			base = turn_torso
		var start := _from(at, s, shoulders)
		var rest_start := _rest_start[s]
		var end_i := _end_of[s]
		var was := base * (points[end_i] - rest_start)
		var now := at[end_i] - start
		var arc := _arc(was, now)
		out[s] = Transform3D(arc * base * rest_frames[s].basis, start)
		var limb := (s - 2) / 2
		if s >= 2 and s % 2 == 0 and limb < stiff.size() and stiff[limb] == 1:
			# One piece bent as it stands: turned whole by its elbow and its
			# hand (or knee and foot), so the bent end never swings round.
			var root: int = ENDS[s][0]
			var tip: int = ENDS[s + 1][1]
			var whole := _triangle(points, at, root, end_i, tip)
			if whole != Basis():
				out[s] = Transform3D(whole * rest_frames[s].basis, start)
	return out


## The turn carrying the triangle of points a, b, c at rest (`rest`) onto
## where they are (`at`); the identity when either is too thin to say.
static func _triangle(
	rest: PackedVector3Array, at: PackedVector3Array, a: int, b: int, c: int
) -> Basis:
	var e0 := rest[b] - rest[a]
	var n0 := e0.cross(rest[c] - rest[a])
	var e1 := at[b] - at[a]
	var n1 := e1.cross(at[c] - at[a])
	if n0.length_squared() < 1e-8 or n1.length_squared() < 1e-8:
		return Basis()
	e0 = e0.normalized()
	n0 = n0.normalized()
	e1 = e1.normalized()
	n1 = n1.normalized()
	var from := Basis(e0, n0, e0.cross(n0))
	var to := Basis(e1, n1, e1.cross(n1))
	return to * from.transposed()


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
	if _rest_back.size() != rest_frames.size():
		_rest_back.clear()
		for f: Transform3D in rest_frames:
			_rest_back.append(f.affine_inverse())
	if _bone_size.size() != bone_rest.size():
		_bone_size.resize(bone_rest.size())
		for i in bone_rest.size():
			_bone_size[i] = bone_rest[i].basis.get_scale()
	var moves: Array[Transform3D] = []
	for s in segs():
		moves.append(now[s] * _rest_back[s])
	# The gear let go of: each piece turned as its three balls (`at` past
	# POINTS) are from how they stood.
	var held: Array[Transform3D] = []
	for g in gear_bones.size():
		var k := POINTS + g * GEAR_BALLS
		if at.size() < k + GEAR_BALLS:
			break
		var at3 := PackedVector3Array([at[k], at[k + 1], at[k + 2]])
		var was := PackedVector3Array(
			[
				gear_ends[g * GEAR_BALLS],
				gear_ends[g * GEAR_BALLS + 1],
				gear_ends[g * GEAR_BALLS + 2]
			]
		)
		var turn := _triangle(was, at3, 0, 1, 2)
		held.append(Transform3D(turn, at[k] - turn * was[0]))
	for i in bone_seg.size():
		var g := bone_gear[i] if i < bone_gear.size() else -1
		var seg := bone_ride[i] if i < bone_ride.size() else bone_seg[i]
		var p := moves[seg] * bone_rest[i]
		if g >= 0 and g < held.size():
			p = held[g] * bone_rest[i]
		var size := _bone_size[i]
		if dead and dead_scale[i].x < .2 and g < 0:
			size = Vector3(.001, .001, .001)
		skeleton.set_bone_pose_position(i, p.origin)
		skeleton.set_bone_pose_rotation(i, p.basis.get_rotation_quaternion())
		skeleton.set_bone_pose_scale(i, size)


## The points where the model's current pose (whatever it last showed) puts
## them, model space: each rides its segment's biggest part; then the gear's
## sticks (gear_from).
func posed_points(skeleton: Skeleton3D) -> PackedVector3Array:
	var poses: Array[Transform3D] = []
	for i in skeleton.get_bone_count():
		poses.append(skeleton.get_bone_pose(i))
	var out := points_from(poses)
	out.append_array(gear_from(poses))
	return out


## The points standing (the key "0"), the gear in hand.
func standing() -> PackedVector3Array:
	var out := points.duplicate()
	out.append_array(gear_ends)
	return out


## The points where the bones' poses `poses` put them, model space.
func points_from(poses: Array[Transform3D]) -> PackedVector3Array:
	var moves: Array[Transform3D] = []
	for s in segs():
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
				m = moves[parent_of(s)]
		elif s > 0:
			m = moves[parent_of(s)]
		moves.append(m)
	var out := PackedVector3Array()
	out.resize(point_n())
	for i in point_n():
		out[i] = moves[rides_of(i)] * points[i]
	return out
