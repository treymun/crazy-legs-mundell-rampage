class_name HeldTail
extends RefCounted
## A held thing's tail swung by a spring, looks only (actors.json "flop":
## tail bone -> the bone it hangs from; the noodler's catfish). Each tail
## bone rests on its joint and is keyed rigid with the thing; every frame
## ActorView poses it from the bone before it, turned about its joint by a
## damped spring the joint's own motion drives (it lags when the hand
## swings), sagging under its weight where the thing is held level, with
## now and then a wriggle. Never read by play.

## The spring back to the keyed shape (1/s^2) and its damping (1/s).
const STIFF := 70.0
const DAMP := 8.0
## How hard gravity and the joint's acceleration turn it (rad/s^2 per m/s^2).
const PULL := 1.6
## The most it turns off the keyed shape (radians).
const MOST := .75
## The wriggle: how far (radians), how quick, how often it comes.
const WRIGGLE := .32
const WRIGGLE_RATE := 10.0
const BURST_RATE := .8
## The longest step integrated at once, and a gap after which it starts over.
const STEP := 1.0 / 60.0
const GAP := .25
## A joint jump beyond this acceleration (m/s^2) is a cut, not a swing.
const JUMP := 80.0
## How quickly the joint's measured speed follows (s): the body is moved on
## play's ticks, not every drawn frame, so the raw speed comes in steps.
const SMOOTH := .07

var bones := PackedInt32Array()
var parents := PackedInt32Array()
## Each tail bone's rest relative to the rest of the bone it hangs from.
var rel: Array[Transform3D] = []
## Each tail's way along its length, and the way it bends side to side (its
## thinnest way: a tail fin's flat), in its bone's rest frame.
var along: Array[Vector3] = []
var bend: Array[Vector3] = []
var swing: Array[Vector3] = []
var spin: Array[Vector3] = []
var last_at: Array[Vector3] = []
var last_vel: Array[Vector3] = []
## The kind's own wriggle share and swing limit (actors.json "flop_wriggle",
## "flop_most": a chain hangs and swings but never wriggles like a fish).
var wriggle := WRIGGLE
var most := MOST
var _clock := -1.0


## The tail of the model under `view` (null when its kind has none).
static func made(view: Node, skeleton: Skeleton3D, info: Dictionary) -> HeldTail:
	var flop: Dictionary = info.get("flop", {})
	if flop.is_empty():
		return null
	var tail := HeldTail.new()
	var wriggle_k: float = info.get("flop_wriggle", 1.0)
	var most: float = info.get("flop_most", MOST)
	tail.wriggle = WRIGGLE * wriggle_k
	tail.most = most
	# Parents before children.
	var order: Array[String] = []
	var left: Array = flop.keys()
	for _round in 8:
		for bone_name: String in left.duplicate():
			var up := str(flop[bone_name])
			if not flop.has(up) or order.has(up):
				order.append(bone_name)
				left.erase(bone_name)
	for bone_name in order:
		var b := skeleton.find_bone(bone_name)
		var p := skeleton.find_bone(str(flop[bone_name]))
		if b < 0 or p < 0:
			continue
		tail.bones.append(b)
		tail.parents.append(p)
		var rest_b := skeleton.get_bone_rest(b)
		tail.rel.append(skeleton.get_bone_rest(p).affine_inverse() * rest_b)
		var cloud := HeldTail._cloud(view, bone_name)
		var mid := Vector3.ZERO
		for v in cloud:
			mid += v
		mid = mid / float(maxi(1, cloud.size()))
		tail.along.append(mid.normalized() if mid.length() > 1e-4 else Vector3.DOWN)
		tail.bend.append(HeldTail._thinnest(cloud, mid))
		tail.swing.append(Vector3.ZERO)
		tail.spin.append(Vector3.ZERO)
		tail.last_at.append(Vector3.INF)
		tail.last_vel.append(Vector3.ZERO)
	return tail if not tail.bones.is_empty() else null


## The held mesh of bone `bone_name`, in that bone's own frame.
static func _cloud(view: Node, bone_name: String) -> PackedVector3Array:
	var out := PackedVector3Array()
	for n: Node in view.find_children("*", "BoneAttachment3D", true, false):
		var attach := n as BoneAttachment3D
		if attach.bone_name != bone_name:
			continue
		for m: Node in attach.get_children():
			var held := m as MeshInstance3D
			if held == null or held.mesh == null:
				continue
			for s in held.mesh.get_surface_count():
				var verts: PackedVector3Array = held.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				for v in verts:
					out.append(held.transform * v)
	return out


## The cloud's thinnest way (a few rounds of the power method on its spread
## after its longest two ways are taken out).
static func _thinnest(cloud: PackedVector3Array, mid: Vector3) -> Vector3:
	if cloud.size() < 4:
		return Vector3.RIGHT
	var spread := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	for v in cloud:
		var d := v - mid
		spread.x += d * d.x
		spread.y += d * d.y
		spread.z += d * d.z
	var ways: Array[Vector3] = []
	for k in 2:
		var w := Vector3(.57, .61, .55)
		for _round in 24:
			for prev in ways:
				w -= prev * w.dot(prev)
			w = (spread * w).normalized()
		ways.append(w)
	return ways[0].cross(ways[1]).normalized()


## Starts over (a body shown again, a cut).
func reset() -> void:
	_clock = -1.0
	for k in bones.size():
		swing[k] = Vector3.ZERO
		spin[k] = Vector3.ZERO
		last_at[k] = Vector3.INF
		last_vel[k] = Vector3.ZERO


## Poses the tail bones for this frame on top of the bones before them
## (posed already); `seed` staggers different bodies' wriggles.
func step(skeleton: Skeleton3D, clock: float, seed: int) -> void:
	var dt := clock - _clock if _clock >= 0.0 else 0.0
	_clock = clock
	if dt <= 0.0 or dt > GAP:
		dt = 0.0
	var to_world := skeleton.global_transform
	var to_skel := to_world.basis.inverse()
	var down := to_skel * Vector3(0.0, -9.8, 0.0)
	var phase := float(seed % 997) * .37
	for k in bones.size():
		var b := bones[k]
		var p := parents[k]
		var parent := Transform3D(
			Basis(skeleton.get_bone_pose_rotation(p)).scaled(skeleton.get_bone_pose_scale(p)),
			skeleton.get_bone_pose_position(p)
		)
		var base := parent * rel[k]
		if base.basis.get_scale().x < .2:
			# (shrunk away: the dead keys)
			_pose_bone(skeleton, b, base)
			continue
		var at := to_world * base.origin
		var acc := Vector3.ZERO
		if dt > 0.0 and last_at[k] != Vector3.INF:
			var raw := (at - last_at[k]) / dt
			var vel := last_vel[k].lerp(raw, 1.0 - exp(-dt / SMOOTH))
			acc = (vel - last_vel[k]) / dt
			last_vel[k] = vel
			if acc.length() > JUMP:
				acc = Vector3.ZERO
				last_vel[k] = Vector3.ZERO
		last_at[k] = at
		var axis := (base.basis * along[k]).normalized()
		var side := (base.basis * bend[k]).normalized()
		# The wriggle: now and then, the tail beating side to side, the last
		# piece a beat behind the one before it.
		var burst := clampf(sin(clock * BURST_RATE + phase) * 3.0 - 2.0, 0.0, 1.0)
		var beat := sin(clock * WRIGGLE_RATE + phase - float(k) * 1.1)
		var aim := axis.cross(side).normalized() * (wriggle * burst * beat)
		var pull := axis.cross((down - to_skel * acc).normalized()) * (PULL * 9.8)
		if dt > 0.0:
			var left := dt
			while left > 1e-5:
				var h := minf(left, STEP)
				left -= h
				var torque := pull + (aim - swing[k]) * STIFF - spin[k] * DAMP
				spin[k] += torque * h
				swing[k] += spin[k] * h
				swing[k] -= axis * swing[k].dot(axis)
				if swing[k].length() > most:
					swing[k] = swing[k].normalized() * most
					spin[k] *= .5
		var turn := Basis.IDENTITY
		if swing[k].length() > 1e-5:
			turn = Basis(swing[k].normalized(), swing[k].length())
		_pose_bone(skeleton, b, Transform3D(turn * base.basis, base.origin))


func _pose_bone(skeleton: Skeleton3D, b: int, pose: Transform3D) -> void:
	skeleton.set_bone_pose_position(b, pose.origin)
	skeleton.set_bone_pose_rotation(b, pose.basis.get_rotation_quaternion())
	skeleton.set_bone_pose_scale(b, pose.basis.get_scale())
