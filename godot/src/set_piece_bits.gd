## The pure parts of the big breaks' coming apart (src/set_piece_wreck.gd,
## looks only): when and how each of a part's pieces breaks away, the mesh a
## part's riding pieces are drawn as together, the merge of pieces at rest,
## and the cutting a worker does. Nothing here touches anything shared: a
## worker calls it.
class_name SetPieceBits
extends RefCounted

const Shape := preload("res://src/set_piece_shape.gd")


## The key of the mesh a part's riding pieces are drawn as together.
static func group_key(key: String, inputs: Array) -> String:
	return "%s|spgroup:%d" % [key.get_slice("|", 0), absi(("%s:%s" % [key, str(inputs)]).hash())]


## When and how each of a part's pieces breaks away, from its own dice
## (`inputs`: _inputs): [share of its part's move, kick, flags (1 tin, 2 a
## snapped foot, 4 pops off in a creak, 8 rides its part with the rest, drawn
## with them as one mesh until it goes),
## when it pops (a share of the creak)] a piece. Pure: a worker works it out
## with the cut.
static func schedule(subs: Array, inputs: Array) -> Array:
	var role: String = inputs[0]
	var weak: float = inputs[1]
	var blasted: bool = inputs[2]
	var creak: bool = inputs[3]
	var leans: bool = inputs[4]
	var d := RandomNumberGenerator.new()
	d.seed = inputs[5]
	d.randi()
	var early := Shape.num("looks", "early", .2) + .3 * weak + (.25 if blasted else 0.0)
	var kick := Shape.num("looks", "kick", 1.0) * (.7 + .6 * weak)
	var lowest := -1
	var highest := -1
	var low := INF
	var high := -INF
	for n in subs.size():
		var sub: WreckCuts.Part = subs[n]
		if sub.centre.z < low:
			low = sub.centre.z
			lowest = n
		if sub.centre.z > high:
			high = sub.centre.z
			highest = n
	var out: Array = []
	for n in subs.size():
		var sub: WreckCuts.Part = subs[n]
		var share := 1.0 + d.randf_range(0.0, .12)
		var piece_kick := kick * d.randf_range(.7, 1.3)
		var flags := 0
		var pop_at := 0.0
		match role:
			"wall":
				if d.randf() < early + .12:
					share = d.randf_range(.12, .85)
				if creak and d.randf() < .05 + .12 * weak:
					flags |= 4
					pop_at = d.randf_range(.12, .9)
			"roof":
				flags |= 1
				if d.randf() < early + .25:
					share = d.randf_range(.1, .8)
			"post", "leg":
				if subs.size() > 1 and n == lowest and sub.half.z < .7:
					flags |= 2
					share = 0.0
				elif subs.size() > 1 and n == highest:
					if leans or d.randf() < early:
						share = d.randf_range(.2, .6)
			"beam":
				# The ridge and the plates break in the fall, folding.
				share = d.randf_range(.2, .55) if d.randf() < .6 + .3 * weak else share
			"brace":
				if d.randf() < early + .1:
					share = d.randf_range(.25, .9)
			"deck", "tank", "hoop":
				# Burst with the tank (_burst_part).
				share = INF
		if flags & 6 == 0 and role != "pipe":
			flags |= 8
		out.append(PackedFloat32Array([share, piece_kick, flags, pop_at]))
	return out


## A part's riding pieces (flag 8) as one mesh about the part's middle.
static func group(subs: Array, sched: Array) -> WreckCuts.Part:
	var which: Array = []
	for n in subs.size():
		var row: PackedFloat32Array = sched[n]
		if int(row[2]) & 8 != 0:
			which.append(n)
	return group_of(subs, which)


## Pieces `which` of a part as one mesh about the part's middle.
static func group_of(subs: Array, which: Array) -> WreckCuts.Part:
	var whole := WreckCuts.Part.new()
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for item: Variant in which:
		var n: int = item
		var sub: WreckCuts.Part = subs[n]
		for m in sub.verts.size():
			var v := sub.centre + sub.basis * sub.verts[m]
			whole.verts.append(v)
			whole.normals.append(sub.basis * sub.normals[m])
			lo = Vector3(minf(lo.x, v.x), minf(lo.y, v.y), minf(lo.z, v.z))
			hi = Vector3(maxf(hi.x, v.x), maxf(hi.y, v.y), maxf(hi.z, v.z))
		whole.uvs.append_array(sub.uvs)
	whole.half = (hi - lo) * .5 if hi.x > lo.x else Vector3(.1, .1, .1)
	return whole


## Every key's pieces, their schedule and their riding group's mesh (on a
## worker: SetPieceMesh's cuts and these touch nothing shared).
static func cut_all(keys: Array, inputs: Array, out: Array) -> void:
	for n in keys.size():
		var subs := SetPieceMesh.cut_key(str(keys[n]))
		var made: Array = inputs[n]
		var sched := schedule(subs, made)
		out.append([subs, sched, group(subs, sched)])


## Each group's pieces as one part (on a worker: only what it is handed).
static func merge_all(groups: Array, half: Vector3, out: Array) -> void:
	for items: Variant in groups:
		var list: Array = items
		var whole := WreckCuts.Part.new()
		for item: Variant in list:
			var row: Array = item
			var sub: WreckCuts.Part = row[0]
			var at: Vector3 = row[1]
			var basis: Basis = row[2]
			for n in sub.verts.size():
				whole.verts.append(at + basis * sub.verts[n])
				whole.normals.append(basis * sub.normals[n])
			whole.uvs.append_array(sub.uvs)
		whole.half = half
		out.append(whole)


## Its thinnest axis (the one it lies on).
static func thin(h: Vector3) -> int:
	return 0 if h.x <= h.y and h.x <= h.z else 1 if h.y <= h.z else 2


static func long_axis(h: Vector3) -> int:
	return 0 if h.x >= h.y and h.x >= h.z else 1 if h.y >= h.z else 2


## How long a fall from z0 going up at vz takes to reach z (gravity g).
static func fall_time(z0: float, vz: float, z: float, g: float) -> float:
	var under := vz * vz + 2.0 * g * (z0 - z)
	return maxf(.04, (vz + sqrt(maxf(0.0, under))) / g)
