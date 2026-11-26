## Meshy models track: how deep an actor's held things (unskinned meshes
## hung off bones: the guns) go into its own body as it is drawn now, in
## model metres. The body is the skinned mesh posed by the skeleton (the
## arms left out: they hold the thing); a held vertex is inside where it is
## behind the nearest body vertex's normal. live_frames.gd `probe` calls it
## every picture.
extends RefCounted

const CELL := .04


## The deepest any held thing of the ActorView `view` is inside its body.
static func depth(view: Node, labels: Dictionary) -> float:
	var skels := view.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return 0.0
	var skel := skels[0] as Skeleton3D
	var body: MeshInstance3D = null
	var held: Array[MeshInstance3D] = []
	for n in view.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if m.skin != null:
			body = m
		elif m.get_parent() is BoneAttachment3D and m.visible:
			held.append(m)
	if body == null or held.is_empty():
		return 0.0
	var skin := body.skin
	var bind_xf: Array[Transform3D] = []
	var bind_ok := PackedByteArray()
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		if bone < 0:
			bone = skel.find_bone(skin.get_bind_name(b))
		var label: String = labels.get(skel.get_bone_name(bone), "body") if bone >= 0 else "arm"
		bind_ok.append(0 if label.begins_with("arm") else 1)
		bind_xf.append(
			skel.get_bone_global_pose(bone) * skin.get_bind_pose(b) if bone >= 0 else Transform3D()
		)
	var pts := PackedVector3Array()
	var nrm := PackedVector3Array()
	for s in body.mesh.get_surface_count():
		var arr := body.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var vb: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var vw: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := vb.size() / maxi(verts.size(), 1)
		for v in range(0, verts.size(), 2):
			var best := 0
			for k in per:
				if vw[v * per + k] > vw[v * per + best]:
					best = k
			if bind_ok[vb[v * per + best]] == 0:
				continue
			var p := Vector3.ZERO
			var q := Vector3.ZERO
			for k in per:
				var w := vw[v * per + k]
				if w <= 0.0:
					continue
				var xf := bind_xf[vb[v * per + k]]
				p += xf * verts[v] * w
				q += xf.basis * norms[v] * w
			pts.append(p)
			nrm.append(q.normalized())
	var grid := {}
	for i in pts.size():
		var c := Vector3i((pts[i] / CELL).floor())
		if not grid.has(c):
			grid[c] = PackedInt32Array()
		var list: PackedInt32Array = grid[c]
		list.append(i)
		grid[c] = list
	var to_skel := skel.global_transform.affine_inverse()
	var worst := 0.0
	for m in held:
		var xf := to_skel * m.global_transform
		for s in m.mesh.get_surface_count():
			var verts: PackedVector3Array = m.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in range(0, verts.size(), 2):
				var q := xf * verts[v]
				var c := Vector3i((q / CELL).floor())
				var near := -1
				var nd := 1e9
				for dx in [-1, 0, 1]:
					for dy in [-1, 0, 1]:
						for dz in [-1, 0, 1]:
							var cell := c + Vector3i(dx, dy, dz)
							if grid.has(cell):
								for i: int in grid[cell]:
									var d := pts[i].distance_squared_to(q)
									if d < nd:
										nd = d
										near = i
				if near >= 0:
					var inside := (q - pts[near]).dot(nrm[near])
					if inside < 0.0:
						worst = maxf(worst, -inside)
	return worst


## The body's pieces as drawn now, each against how it stands at rest: a
## bone shrunk (hidden), a limb part stretched or squashed far from its
## length, a hand inside the torso. Returns [worst problem, its words].
static func pieces(view: Node, rig: RagdollRig) -> Array:
	var skels := view.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty() or rig == null or not rig.ok:
		return [0.0, ""]
	var skel := skels[0] as Skeleton3D
	var worst := 0.0
	var said := ""
	var names := [
		"upperarm_l",
		"forearm_l",
		"hand_l",
		"upperarm_r",
		"forearm_r",
		"hand_r",
		"head",
		"thigh_l",
		"shin_l",
		"thigh_r",
		"shin_r"
	]
	for nm: String in names:
		var b := skel.find_bone(nm)
		if b < 0:
			continue
		var s := skel.get_bone_pose_scale(b).x
		if s < .5:
			var bad := 1.0 - s
			if bad > worst:
				worst = bad
				said = "%s shrunk to %.2f" % [nm, s]
	# Lengths: shoulder to elbow, elbow to wrist, as the rest has them.
	for side: String in ["l", "r"]:
		var ua := skel.find_bone("upperarm_" + side)
		var fa := skel.find_bone("forearm_" + side)
		var hd := skel.find_bone("hand_" + side)
		if ua < 0 or fa < 0 or hd < 0:
			continue
		var p_ua := skel.get_bone_global_pose(ua).origin
		var p_fa := skel.get_bone_global_pose(fa).origin
		var p_hd := skel.get_bone_global_pose(hd).origin
		var r_ua := skel.get_bone_global_rest(ua).origin
		var r_fa := skel.get_bone_global_rest(fa).origin
		var r_hd := skel.get_bone_global_rest(hd).origin
		for pair: Array in [
			[p_ua.distance_to(p_fa), r_ua.distance_to(r_fa), "upper arm"],
			[p_fa.distance_to(p_hd), r_fa.distance_to(r_hd), "forearm"]
		]:
			var now: float = pair[0]
			var was: float = pair[1]
			var off := absf(now / maxf(was, 1e-4) - 1.0)
			if off > .25 and off > worst:
				worst = off
				said = "%s %s at %.2f of its length" % [side, pair[2], now / maxf(was, 1e-4)]
		# The hand inside the torso: nearer the hips-to-shoulders line than
		# the belly's ball is thick.
		var at := rig.posed_points(skel)
		var hips := (at[RagdollRig.HIP_L] + at[RagdollRig.HIP_R]) * .5
		var neck := (at[RagdollRig.SH_L] + at[RagdollRig.SH_R]) * .5
		var c := Geometry3D.get_closest_point_to_segment(p_hd, hips, neck)
		var deep := rig.radii[RagdollRig.BELLY] * .8 - p_hd.distance_to(c)
		if deep > 0.0 and deep > worst:
			worst = deep
			said = "%s hand %.3f m inside the torso" % [side, deep]
	return [worst, said]


## How much of each arm shows from the front, the back and either side
## (model space): the body's vertices posed as drawn, the rest of the body
## drawn into a depth grid, an arm's vertex showing where nothing of the body
## is in front of it. Returns {view: [left arm share, right arm share]}.
static func arms_seen(view: Node, labels: Dictionary) -> Dictionary:
	var out := {}
	var skels := view.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return out
	var skel := skels[0] as Skeleton3D
	var body: MeshInstance3D = null
	for n in view.find_children("*", "MeshInstance3D", true, false):
		if (n as MeshInstance3D).skin != null:
			body = n as MeshInstance3D
	if body == null:
		return out
	var skin := body.skin
	var bind_xf: Array[Transform3D] = []
	var bind_side := PackedInt32Array()
	for b in skin.get_bind_count():
		var bone := skin.get_bind_bone(b)
		if bone < 0:
			bone = skel.find_bone(skin.get_bind_name(b))
		var label: String = labels.get(skel.get_bone_name(bone), "body") if bone >= 0 else "body"
		bind_side.append(0 if label == "arm_l" else 1 if label == "arm_r" else -1)
		bind_xf.append(
			skel.get_bone_global_pose(bone) * skin.get_bind_pose(b) if bone >= 0 else Transform3D()
		)
	var pts := PackedVector3Array()
	var side := PackedInt32Array()
	for s in body.mesh.get_surface_count():
		var arr := body.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var vb: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var vw: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var per := vb.size() / maxi(verts.size(), 1)
		for v in verts.size():
			var best := 0
			var p := Vector3.ZERO
			for k in per:
				var w := vw[v * per + k]
				if w > vw[v * per + best]:
					best = k
				if w > 0.0:
					p += bind_xf[vb[v * per + k]] * verts[v] * w
			pts.append(p)
			side.append(bind_side[vb[v * per + best]])
	var cell := .02
	for way: Array in [
		["front", Vector3(0, 0, 1)],
		["back", Vector3(0, 0, -1)],
		["left", Vector3(1, 0, 0)],
		["right", Vector3(-1, 0, 0)]
	]:
		var name: String = way[0]
		var d: Vector3 = way[1]
		var u := Vector3.UP
		var r := d.cross(u)
		var near := {}
		for i in pts.size():
			if side[i] >= 0:
				continue
			var key := Vector2i(floori(pts[i].dot(r) / cell), floori(pts[i].dot(u) / cell))
			var z := pts[i].dot(d)
			if not near.has(key) or z > float(near[key]):
				near[key] = z
		var seen := [0, 0]
		var all := [0, 0]
		for i in pts.size():
			if side[i] < 0:
				continue
			all[side[i]] += 1
			var key := Vector2i(floori(pts[i].dot(r) / cell), floori(pts[i].dot(u) / cell))
			if not near.has(key) or pts[i].dot(d) > float(near[key]) - .01:
				seen[side[i]] += 1
		out[name] = [
			float(seen[0]) / maxf(1.0, float(all[0])), float(seen[1]) / maxf(1.0, float(all[1]))
		]
	return out
