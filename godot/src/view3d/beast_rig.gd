## How a beast's model hangs on its ragdoll (pass 13: BeastDoll,
## src/beast_doll.gd): a gator, a crawler, a hog of the herd, the cow. Found
## once from the model at its standing key "0" by the plan fit.json gives the
## kind ("beast": how many legs, head and tail balls, and the way its head
## points when the model does not face +z). Every part of these models is
## labelled "body", so the rig is found from where the parts are:
##
## - the torso: six balls, as a person's (src/ragdoll.gd), so the same code
##   holds it: its corners (the hips behind and the shoulders in front, at
##   its middle height, between its legs' roots), its belly and its back;
## - the legs: the parts that reach the floor out to the sides, each grown up
##   through the parts it touches; three balls a leg, its root (held in the
##   torso), its knee (the point furthest off the line from root to foot: a
##   gator's and a crawler's legs splay up and out, a hog's hang straight)
##   and its foot;
## - the head: the parts ahead of the shoulders, a ball at the skull and one
##   at the snout (the jaws, ears and eyes ride them);
## - the tail: the parts behind the hips, cut into `tail` balls along it.
##
## Each part rides the segment of its own group it is nearest. The segments'
## frames are found as a person's: the torso from its corners, every other
## segment turned from its parent by the least turn (frames_of).
class_name BeastRig
extends RagdollRig

const BELLY_B := 4
const BACK_B := 5
const TORSO_BALLS := 6
## What BAKED holds for a beast (a row of its own: RagdollRig.baked reads
## the people's).
const BEAST_FORMAT := 1
## A part is a leg's foot when its lowest point is this share of the body's
## height off the floor and it stands this share of the torso's half width
## out from its middle; a part within REACH of the height of a leg's part (a
## crawler's foot's tip stands a little off its shin) joins the leg when it
## stands out to the foot's side at least GROW of the foot's way. (FOOT_OUT
## was .3 for the old block bodies; a Meshy cow's barrel belly is wider than
## its stance and a hind foot stepped in under it stands .27 out.)
const FOOT_LOW := .06
const FOOT_OUT := .2
const GROW := .45
const REACH := .04
## A knee off the line from root to foot by less than BENT of the leg's
## length is a straight leg's: it folds the plan's way (front legs' knees
## ahead, hind legs' behind, STRAIGHT_BEND of the leg's length).
const BENT := .14
const STRAIGHT_BEND := .05

## The plan (fit.json "beast").
var plan := {}
## Each segment's [from, to] point (-1 between the shoulders, -2 between the
## hips; the torso's [-3, -3]), its parent and each point's segment at the
## start.
var ends: Array[PackedInt32Array] = []
var parents := PackedInt32Array()
var rides := PackedInt32Array()
## Each leg's root, knee and foot (three a leg, front legs first); the head's
## balls (skull, snout); the tail's (root to tip).
var legs := PackedInt32Array()
var head := PackedInt32Array()
var tail := PackedInt32Array()
## Each leg's knee's way off the line from root to foot (model space, at the
## standing key): the way it folds.
var bend := PackedVector3Array()
## The legs' bones when the model names them (actors.json "beast_legs": a
## Meshy beast skinned smoothly over the old armature, whose parts are no
## longer blocks to be found by where they stand): no search for feet.
var _named_legs: Array[PackedInt32Array] = []


func segs() -> int:
	return ends.size()


func parent_of(s: int) -> int:
	return parents[s]


func rides_of(i: int) -> int:
	return rides[i]


func point_n() -> int:
	return points.size()


## What of the actors.json entry and its plan the rig is found from.
static func beast_key(info: Dictionary) -> String:
	var frames: Dictionary = info.get("frames", {})
	var labels: Dictionary = info.get("labels", {})
	var made_of := [
		frames.get("0"), frames.get("down"), labels, info.get("beast"), info.get("beast_legs")
	]
	return var_to_str(made_of).md5_text()


## The kind's baked rig put back on the model under `view`, or null when it
## has none or it was made from another plan, labels or keys.
static func read(kind: String, view: Node, info: Dictionary) -> BeastRig:
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
	if row.size() != 19 or row[0] != "beast" or row[1] != BEAST_FORMAT or row[2] != beast_key(info):
		return null
	var rig := BeastRig.new()
	rig.plan = info.get("beast", {})
	if not row[3]:
		return rig
	var skeletons := view.find_children("*", "Skeleton3D", true, false)
	var players := view.find_children("*", "AnimationPlayer", true, false)
	if skeletons.is_empty() or players.is_empty():
		return null
	rig.points = row[4]
	rig.radii = row[5]
	rig.bone_seg = row[6]
	rig.anchors = row[7]
	for buckets: Array in row[8]:
		var typed: Array[PackedVector3Array] = []
		for bucket: PackedVector3Array in buckets:
			typed.append(bucket)
		rig.hull.append(typed)
	rig.hull_reach = row[9]
	rig.bone_lo = row[10]
	rig.bone_hi = row[11]
	var flat: PackedInt32Array = row[12]
	for k in range(0, flat.size(), 2):
		rig.ends.append(PackedInt32Array([flat[k], flat[k + 1]]))
	rig.parents = row[13]
	rig.rides = row[14]
	rig.legs = row[15]
	rig.head = row[16]
	rig.tail = row[17]
	rig.bend = row[18]
	rig._posed(skeletons[0] as Skeleton3D, players[0] as AnimationPlayer, info)
	rig.ok = true
	return rig


## The rig as BAKED keeps it for a beast (tools/art/bake_rigs.gd).
func to_baked(info: Dictionary) -> PackedByteArray:
	var row: Array = ["beast", BEAST_FORMAT, beast_key(info), ok]
	if ok:
		var flat := PackedInt32Array()
		for e in ends:
			flat.append_array(e)
		row.append_array(
			[
				points,
				radii,
				bone_seg,
				anchors,
				hull,
				hull_reach,
				bone_lo,
				bone_hi,
				flat,
				parents,
				rides,
				legs,
				head,
				tail,
				bend
			]
		)
	else:
		for _k in 15:
			row.append(null)
	var raw := var_to_bytes(row)
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, raw.size())
	out.append_array(raw.compress(FileAccess.COMPRESSION_DEFLATE))
	return out


func build(view: Node, info: Dictionary) -> void:
	_build_beast(view, info)


## The poses and what follows from them (as made again from a baked rig).
func _posed(skeleton: Skeleton3D, player: AnimationPlayer, info: Dictionary) -> void:
	var anim := player.get_animation(player.get_animation_list()[0])
	var frames: Dictionary = info.get("frames", {})
	var stand_key: float = frames["0"]
	var down_key: float = frames["down"]
	bone_rest = _poses(anim, skeleton, stand_key * ActorModels.KEY_TIME)
	var dead := _poses(anim, skeleton, down_key * ActorModels.KEY_TIME)
	dead_scale.resize(skeleton.get_bone_count())
	for i in skeleton.get_bone_count():
		dead_scale[i] = dead[i].basis.get_scale()
	bone_ride = bone_seg.duplicate()
	bone_gear = PackedInt32Array()
	bone_gear.resize(bone_seg.size())
	bone_gear.fill(-1)
	rest_frames.clear()
	rest_frames = frames_of(points)
	_rest_inv.clear()
	for f: Transform3D in rest_frames:
		_rest_inv.append(f.basis.inverse())
	down_points = points_from(dead)
	# First seen long dead it lies as its model's own body at rest does (a hog
	# on its side, a crawler on its back), on the floor under its torso.
	var mid := (down_points[0] + down_points[1] + down_points[2] + down_points[3]) * .25
	var low := INF
	for i in down_points.size():
		low = minf(low, down_points[i].y - radii[i])
	lying_points = PackedVector3Array()
	for p in down_points:
		lying_points.append(Vector3(p.x - mid.x, p.y - low, p.z - mid.z))
	gear_lying = PackedVector3Array()


func _build_beast(view: Node, info: Dictionary) -> void:
	found += 1
	plan = info.get("beast", {})
	var skeletons := view.find_children("*", "Skeleton3D", true, false)
	var meshes := view.find_children("*", "MeshInstance3D", true, false)
	var players := view.find_children("*", "AnimationPlayer", true, false)
	if skeletons.is_empty() or meshes.is_empty() or players.is_empty():
		return
	var skeleton := skeletons[0] as Skeleton3D
	var player := players[0] as AnimationPlayer
	var frames: Dictionary = info.get("frames", {})
	if player.get_animation_list().is_empty() or not frames.has("0") or not frames.has("down"):
		return
	var anim := player.get_animation(player.get_animation_list()[0])
	var stand_key: float = frames["0"]
	var bones := skeleton.get_bone_count()
	_named_legs.clear()
	var named: Array = info.get("beast_legs", [])
	for chain: Array in named:
		var ids := PackedInt32Array()
		for bone_name: String in chain:
			var b := skeleton.find_bone(bone_name)
			if b >= 0:
				ids.append(b)
		if not ids.is_empty():
			_named_legs.append(ids)
	var rest := _poses(anim, skeleton, stand_key * ActorModels.KEY_TIME)
	# Every vertex where the standing key puts it, by its part.
	var all_at := PackedVector3Array()
	var all_bone := PackedInt32Array()
	var count := PackedInt32Array()
	count.resize(bones)
	bone_lo.resize(bones)
	bone_hi.resize(bones)
	var mids := PackedVector3Array()
	mids.resize(bones)
	for m: Node in meshes:
		var mesh := m as MeshInstance3D
		if mesh.mesh == null or mesh.skin == null:
			continue
		var skin := mesh.skin
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
				if bind < 0 or bind >= skin.get_bind_count():
					continue
				var bone := skin.get_bind_bone(bind)
				if bone < 0:
					bone = skeleton.find_bone(skin.get_bind_name(bind))
				if bone < 0 or bone >= bones or rest[bone].basis.get_scale().x < .2:
					continue
				var at := rest[bone] * (skin.get_bind_pose(bind) * verts[v])
				if count[bone] == 0:
					bone_lo[bone] = at
					bone_hi[bone] = at
				else:
					bone_lo[bone] = bone_lo[bone].min(at)
					bone_hi[bone] = bone_hi[bone].max(at)
				mids[bone] += at
				count[bone] += 1
				all_at.append(at)
				all_bone.append(bone)
	if all_at.size() < 64:
		return
	for b in bones:
		if count[b] > 0:
			mids[b] /= float(count[b])
	bone_rest = rest
	var fit := _fit(all_at, all_bone, count, mids)
	if not fit:
		return
	_posed(skeleton, player, info)
	_hull(all_at, all_bone)
	ok = true


## The balls, segments and each part's segment from the vertices. False when
## the plan's legs are not found.
func _fit(
	all_at: PackedVector3Array,
	all_bone: PackedInt32Array,
	count: PackedInt32Array,
	mids: PackedVector3Array
) -> bool:
	var bones := count.size()
	var way: Array = plan.get("front", [0.0, 1.0])
	var wx: float = way[0]
	var wz: float = way[1]
	var front := Vector3(wx, 0.0, wz).normalized()
	var left := Vector3.UP.cross(front)
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for p in all_at:
		lo = lo.min(p)
		hi = hi.max(p)
	var tall := hi.y - lo.y
	var f_lo := INF
	var f_hi := -INF
	for p in all_at:
		f_lo = minf(f_lo, p.dot(front))
		f_hi = maxf(f_hi, p.dot(front))
	var length := f_hi - f_lo
	# The torso's own part: the one with the most vertices.
	var main := 0
	for b in bones:
		if count[b] > count[main]:
			main = b
	var spine_l := mids[main].dot(left)
	var spine_y := mids[main].y
	var half := 0.0
	for k in all_at.size():
		if all_bone[k] == main:
			half = maxf(half, absf(all_at[k].dot(left) - spine_l))
	# The legs: feet first (low, out to the side), joined where they touch,
	# then grown up through the parts that touch them.
	var leg_of := PackedInt32Array()
	leg_of.resize(bones)
	leg_of.fill(-1)
	# (Each to the nearest of the plan's rows of feet, two a row, its own
	# side: a crawler's feet stand closer than their parts' boxes, and some
	# of their tips a little off their shins.)
	var legs_f: float = plan.get("legs", 4.0)
	var wanted := int(legs_f)
	var rows := maxi(1, wanted / 2)
	var low_feet: Array[int] = []
	var fa := INF
	var fb := -INF
	for b in bones:
		if b == main or count[b] == 0:
			continue
		if bone_lo[b].y > lo.y + tall * FOOT_LOW:
			continue
		if absf(mids[b].dot(left) - spine_l) < half * FOOT_OUT:
			continue
		low_feet.append(b)
		fa = minf(fa, mids[b].dot(front))
		fb = maxf(fb, mids[b].dot(front))
	var feet: Array[PackedInt32Array] = []
	for k in rows * 2:
		feet.append(PackedInt32Array())
	if _named_legs.size() == rows * 2:
		low_feet.clear()
		feet = _named_legs.duplicate()
	for b: int in low_feet:
		var row := 0
		if rows > 1:
			row = clampi(roundi((fb - mids[b].dot(front)) / (fb - fa) * (rows - 1)), 0, rows - 1)
		var k := row * 2 + (0 if mids[b].dot(left) > spine_l else 1)
		var grown := feet[k]
		grown.append(b)
		feet[k] = grown
	for foot in feet:
		if foot.is_empty():
			return false
	var groups: Array[PackedInt32Array] = []
	for g in feet.size():
		var group := feet[g].duplicate()
		for b: int in group:
			leg_of[b] = g
		groups.append(group)
	var grew := _named_legs.size() != rows * 2
	var reach := Vector3.ONE * tall * REACH
	while grew:
		grew = false
		for b in bones:
			if b == main or count[b] == 0 or leg_of[b] >= 0:
				continue
			var box := AABB(bone_lo[b] - reach, bone_hi[b] - bone_lo[b] + reach * 2.0)
			var out := mids[b].dot(left) - spine_l
			for g in groups.size():
				# Out to the foot's own side, most of the way.
				var foot_out := mids[groups[g][0]].dot(left) - spine_l
				if out * signf(foot_out) < absf(foot_out) * GROW:
					continue
				var touches := false
				for o: int in groups[g]:
					if box.intersects(AABB(bone_lo[o], bone_hi[o] - bone_lo[o])):
						touches = true
						break
				if touches:
					leg_of[b] = g
					var grown := groups[g]
					grown.append(b)
					groups[g] = grown
					grew = true
					break
	# Each leg's root, knee and foot from its vertices.
	var leg_pts: Array[PackedVector3Array] = []
	var leg_r: Array[PackedFloat32Array] = []
	for g in groups.size():
		var cloud := PackedVector3Array()
		for k in all_at.size():
			if leg_of[all_bone[k]] == g:
				cloud.append(all_at[k])
		var near := PackedFloat32Array()
		var heights := PackedFloat32Array()
		for p in cloud:
			near.append(Vector2(p.dot(left) - spine_l, p.y - spine_y).length())
			heights.append(p.y)
		var root := _mean_below(cloud, near, .12)
		var foot := _mean_below(cloud, heights, .12)
		var foot_box := AABB(foot, Vector3.ZERO)
		var low_y := foot.y
		for p in cloud:
			low_y = minf(low_y, p.y)
		for p in cloud:
			if p.y < low_y + (hi.y - lo.y) * .05:
				foot_box = foot_box.expand(p)
		var foot_r := clampf(minf(foot_box.size.x, foot_box.size.z) * .5, tall * .03, tall * .14)
		foot.y = low_y + foot_r
		var run := foot - root
		var leg_len := run.length()
		var perp := PackedFloat32Array()
		var most := 0.0
		for p in cloud:
			var t := clampf((p - root).dot(run) / maxf(leg_len * leg_len, 1e-6), 0.0, 1.0)
			var d := p.distance_to(root + run * t)
			perp.append(d)
			most = maxf(most, d)
		# The knee: the leg's part whose middle stands furthest off the line
		# (a gator's, a crawler's knee joint), when it stands well off it.
		var knee := (root + foot) * .5
		var thick := _quantile(perp, .5)
		var off_most := 0.0
		for b: int in groups[g]:
			if count[b] == 0:
				# (A named leg's bone the skin gives nothing: no middle.)
				continue
			var t := clampf((mids[b] - root).dot(run) / maxf(leg_len * leg_len, 1e-6), 0.0, 1.0)
			var d := mids[b].distance_to(root + run * t)
			if d > off_most and d > leg_len * BENT:
				off_most = d
				knee = mids[b]
		var r := clampf(thick, tall * .025, tall * .16)
		leg_pts.append(PackedVector3Array([root, knee, foot]))
		# (A root is inside the torso, whose shape keeps it off the floor: a
		# small ball, or it rubbed the floor against the torso's shape.)
		leg_r.append(PackedFloat32Array([r * .5, r, foot_r]))
	# Front legs first (the furthest ahead), each pair left then right.
	var order: Array[int] = []
	for g in groups.size():
		order.append(g)
	order.sort_custom(
		func(a: int, b: int) -> bool:
			var on_a := leg_pts[a][0].dot(front)
			var on_b := leg_pts[b][0].dot(front)
			if absf(on_a - on_b) > length * .08:
				return on_a > on_b
			return leg_pts[a][0].dot(left) > leg_pts[b][0].dot(left)
	)
	var front_f := 0.0
	var rear_f := 0.0
	for k in 2:
		front_f += leg_pts[order[k]][0].dot(front) * .5
		rear_f += leg_pts[order[order.size() - 1 - k]][0].dot(front) * .5
	if front_f - rear_f < length * .05:
		front_f = mids[main].dot(front) + length * .15
		rear_f = mids[main].dot(front) - length * .15
	# The torso: its own part between (and a little past) the legs' roots.
	var t_lo := Vector3.INF
	var t_hi := -Vector3.INF
	for k in all_at.size():
		if all_bone[k] != main:
			continue
		var p := all_at[k]
		var f := p.dot(front)
		if f < rear_f - length * .1 or f > front_f + length * .1:
			continue
		var q := Vector3(p.dot(left) - spine_l, p.y, f)
		t_lo = t_lo.min(q)
		t_hi = t_hi.max(q)
	if t_lo == Vector3.INF:
		return false
	var wide := (t_hi.x - t_lo.x) * .5
	var deep := t_hi.y - t_lo.y
	var mid_y := (t_hi.y + t_lo.y) * .5
	var side := left * spine_l
	points = PackedVector3Array()
	radii = PackedFloat32Array()
	var corner_r := clampf(minf(wide, deep * .5) * .6, tall * .04, tall * .4)
	for p: Vector3 in [
		front * rear_f + left * wide * .55,
		front * rear_f - left * wide * .55,
		front * front_f + left * wide * .55,
		front * front_f - left * wide * .55
	]:
		points.append(p + side + Vector3.UP * mid_y)
		radii.append(corner_r)
	var round_r := clampf(deep * .28, tall * .04, tall * .4)
	var middle_f := front * (front_f + rear_f) * .5 + side
	points.append(middle_f + Vector3.UP * (t_lo.y + round_r))
	points.append(middle_f + Vector3.UP * (t_hi.y - round_r))
	radii.append(round_r)
	radii.append(round_r)
	ends = [PackedInt32Array([-3, -3])]
	parents = PackedInt32Array([-1])
	rides = PackedInt32Array([0, 0, 0, 0, 0, 0])
	# The head: the parts ahead of the shoulders.
	var group_of := PackedInt32Array()
	group_of.resize(bones)
	group_of.fill(0)
	head = PackedInt32Array()
	var head_f: float = plan.get("head", 0.0)
	var head_n := int(head_f)
	if head_n > 0:
		var cloud := PackedVector3Array()
		for b in bones:
			if b != main and count[b] > 0 and leg_of[b] < 0:
				if mids[b].dot(front) > front_f + length * .1:
					group_of[b] = 1
		for k in all_at.size():
			if group_of[all_bone[k]] == 1:
				cloud.append(all_at[k])
		if cloud.size() >= 8:
			var along := PackedFloat32Array()
			var h0 := INF
			var h1 := -INF
			for p in cloud:
				along.append(p.dot(front))
				h0 = minf(h0, p.dot(front))
				h1 = maxf(h1, p.dot(front))
			var span := h1 - h0
			var skull := _slice(cloud, along, h0 - 1.0, h0 + span * (.45 if head_n > 1 else 2.0))
			var skull_at: Vector3 = skull[0]
			var skull_r: float = skull[1]
			points.append(skull_at)
			radii.append(clampf(skull_r, tall * .04, tall * .3))
			ends.append(PackedInt32Array([-1, points.size() - 1]))
			parents.append(0)
			rides.append(ends.size() - 1)
			head.append(points.size() - 1)
			if head_n > 1:
				var snout := _slice(cloud, along, h1 - span * .2, h1 + 1.0)
				var snout_at: Vector3 = snout[0]
				var snout_r: float = snout[1]
				points.append(snout_at)
				radii.append(clampf(snout_r, tall * .03, tall * .25))
				ends.append(PackedInt32Array([points.size() - 2, points.size() - 1]))
				parents.append(ends.size() - 2)
				rides.append(ends.size() - 1)
				head.append(points.size() - 1)
	# The tail: the parts behind the hips, cut along it.
	tail = PackedInt32Array()
	var tail_f: float = plan.get("tail", 0.0)
	var tail_n := int(tail_f)
	if tail_n > 0:
		var cloud := PackedVector3Array()
		for b in bones:
			if b != main and count[b] > 0 and leg_of[b] < 0 and group_of[b] == 0:
				if mids[b].dot(front) < rear_f - length * .1:
					group_of[b] = 2
		for k in all_at.size():
			if group_of[all_bone[k]] == 2:
				cloud.append(all_at[k])
		if cloud.size() >= tail_n * 8:
			var along := PackedFloat32Array()
			var t0 := INF
			var t1 := -INF
			for p in cloud:
				along.append(p.dot(front))
				t0 = minf(t0, p.dot(front))
				t1 = maxf(t1, p.dot(front))
			var span := t1 - t0
			for k in tail_n:
				var cut := _slice(
					cloud, along, t1 - span * float(k + 1) / tail_n, t1 - span * float(k) / tail_n
				)
				var cut_at: Vector3 = cut[0]
				var cut_r: float = cut[1]
				points.append(cut_at)
				radii.append(clampf(cut_r, tall * .02, tall * .3))
				ends.append(
					PackedInt32Array([-2 if k == 0 else points.size() - 2, points.size() - 1])
				)
				parents.append(0 if k == 0 else ends.size() - 2)
				rides.append(ends.size() - 1)
				tail.append(points.size() - 1)
	# The legs, front first.
	legs = PackedInt32Array()
	bend = PackedVector3Array()
	for k in order.size():
		var g := order[k]
		var first := points.size()
		points.append_array(leg_pts[g])
		radii.append_array(leg_r[g])
		legs.append_array([first, first + 1, first + 2])
		rides.append(0)
		ends.append(PackedInt32Array([first, first + 1]))
		parents.append(0)
		rides.append(ends.size() - 1)
		ends.append(PackedInt32Array([first + 1, first + 2]))
		parents.append(ends.size() - 2)
		rides.append(ends.size() - 1)
		var root := leg_pts[g][0]
		var foot := leg_pts[g][2]
		var off := leg_pts[g][1] - (root + foot) * .5
		var run := foot - root
		off -= run * off.dot(run) / maxf(run.length_squared(), 1e-6)
		if off.length() < run.length() * STRAIGHT_BEND * .5:
			# A straight leg: a foreleg's knee folds ahead, a hind leg's behind.
			var ahead := front if root.dot(front) > (front_f + rear_f) * .5 else -front
			off = ahead * run.length() * STRAIGHT_BEND
			points[first + 1] = points[first + 1] + off
		bend.append(off.normalized())
	# Each part's segment: its group's nearest.
	bone_seg = PackedInt32Array()
	bone_seg.resize(bones)
	anchors = PackedInt32Array()
	anchors.resize(ends.size())
	anchors.fill(-1)
	var biggest := PackedInt32Array()
	biggest.resize(ends.size())
	for b in bones:
		var choices: Array[int] = []
		if leg_of[b] >= 0:
			var k := order.find(leg_of[b])
			var seg := _leg_seg(k)
			choices = [seg, seg + 1]
		elif group_of[b] == 1:
			for s in ends.size():
				if s > 0 and (ends[s][0] == -1 or head.has(ends[s][0])) and head.has(ends[s][1]):
					choices.append(s)
		elif group_of[b] == 2:
			for s in ends.size():
				if tail.has(ends[s][1]):
					choices.append(s)
		var seg := 0
		var best := INF
		for s: int in choices:
			var a := _start(points, s)
			var e := points[ends[s][1]]
			var d := mids[b].distance_to(Geometry3D.get_closest_point_to_segment(mids[b], a, e))
			if d < best:
				best = d
				seg = s
		bone_seg[b] = seg
		if count[b] > biggest[seg]:
			biggest[seg] = count[b]
			anchors[seg] = b
	return true


## The first segment of the k-th leg (front first).
func _leg_seg(k: int) -> int:
	return 1 + head.size() + tail.size() + k * 2


static func _sum(count: PackedInt32Array, group: PackedInt32Array) -> int:
	var n := 0
	for b in group:
		n += count[b]
	return n


## The mean of the share `share` of `cloud` with the least `key`.
static func _mean_below(
	cloud: PackedVector3Array, key: PackedFloat32Array, share: float
) -> Vector3:
	var cut := _quantile(key, share)
	var sum := Vector3.ZERO
	var n := 0
	for k in cloud.size():
		if key[k] <= cut:
			sum += cloud[k]
			n += 1
	return sum / float(maxi(1, n))


static func _quantile(values: PackedFloat32Array, share: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(int(sorted.size() * share), 0, sorted.size() - 1)]


## [the middle, how thick] of the points of `cloud` whose `along` lies
## between a and b (thick: half the least of its width and height).
static func _slice(
	cloud: PackedVector3Array, along: PackedFloat32Array, a: float, b: float
) -> Array:
	var sum := Vector3.ZERO
	var n := 0
	var box := AABB()
	for k in cloud.size():
		if along[k] >= a and along[k] <= b:
			sum += cloud[k]
			box = box.expand(cloud[k]) if n > 0 else AABB(cloud[k], Vector3.ZERO)
			n += 1
	if n == 0:
		return [Vector3.ZERO, 0.0]
	return [sum / float(n), minf(minf(box.size.x, box.size.z), box.size.y) * .5]


## Where segment s starts: between the shoulders (-1), the hips (-2), or at
## its first point.
func _start(at: PackedVector3Array, s: int) -> Vector3:
	var a: int = ends[s][0]
	if a == -1:
		return (at[SH_L] + at[SH_R]) * .5
	if a == -2:
		return (at[HIP_L] + at[HIP_R]) * .5
	return at[maxi(a, 0)]


func frames_of(at: PackedVector3Array) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	out.resize(ends.size())
	var hips := (at[HIP_L] + at[HIP_R]) * .5
	var shoulders := (at[SH_L] + at[SH_R]) * .5
	var up := (shoulders - hips).normalized()
	var across := ((at[SH_R] - at[SH_L]) + (at[HIP_R] - at[HIP_L])).normalized()
	across = (across - up * across.dot(up)).normalized()
	var torso := Basis(across, up, across.cross(up)).orthonormalized()
	out[0] = Transform3D(torso, hips)
	if rest_frames.is_empty():
		for s in range(1, ends.size()):
			out[s] = Transform3D(torso, _start(at, s))
		return out
	var turn_torso := torso * _rest_inv[0]
	for s in range(1, ends.size()):
		var parent := parents[s]
		var base := turn_torso if parent == 0 else out[parent].basis * _rest_inv[parent]
		var start := _start(at, s)
		var end_i: int = ends[s][1]
		var was := base * (points[end_i] - _start(points, s))
		var now := at[end_i] - start
		out[s] = Transform3D(_arc(was, now) * base * rest_frames[s].basis, start)
	return out
