## physics_check.gd's ragdoll and slow-motion part (run from there).
##
## Ragdolls (src/ragdoll.gd on Billy's rig, view3d/ragdoll_rig.gd): a body
## dropped dead, shot down with buckshot and blasted, on decks, stair treads
## and ramps of a few levels, play's body (features/corpses.gd) moving it as
## the game does; each comes to rest lying ON the floor really under it (no
## ball sunk in, the lowest touching), never inside a wall, a slab or a rail
## at any moment, its torso by play's body, and falls asleep: left lying, it
## takes no more steps. Over a rail: a body thrown hard at the hay loft's rail
## goes over and lies on the ground below; thrown softly it stays on the loft.
## Every rigged kind but the bosses and the kinds with no legs gets a rig.
##
## Slow-mo finishers (features/finishers.gd): killing the last of three hands in
## a fight starts it (the first kill does not), it eases and ends; with SLOW-MO
## FINISHERS off, with a second player, or on a host it never starts.
extends RefCounted

const DT := 1.0 / 60.0
const TOL := .03
## view3d_check's: no part of a body at rest higher than this of its height.
const DOWN_HIGH := .5
## No part of a ragdoll at rest deeper in the floor than this (map units): the
## model's own shape is kept out of it (RagdollRig.hull), not only its balls.
const SINK := .01
## Pass 11's falls (_falls): a rigid link held within this share of its
## length, and the body still within REST_BY seconds.
const STRETCH := .1
const STRETCH_LET := .02
## (For a frame or two as it lands hard a link may give this much.)
const STRETCH_HIT := .35
## At rest by then (Ragdoll.MOST_AWAKE lays the last tremble still).
const REST_BY := Ragdoll.MOST_AWAKE + .1
const R := preload("res://src/view3d/ragdoll_rig.gd")

var check: SceneTree
var rig: RagdollRig


func _init(owner: SceneTree) -> void:
	check = owner


func _check(ok: bool, text: String) -> void:
	check.call("_check", ok, text)


func _ok(text: String) -> void:
	check.call("_ok", text)


func run(main: Node, levels: Array) -> void:
	# (Each kind's entry with fit.json's merged, as the game reads it: a
	# beast's plan, pass 13.)
	var data: Dictionary = ActorModels.new(Assets.new()).kinds
	var fits: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets3d/actors/fit.json")
	)
	var rigged := 0
	var kept: Array = []
	var ground: Game = main.make_game("hickston")
	ground.configure({})
	var floating := 0
	for kind: String in data:
		var path := "res://scenes/actors/%s.tscn" % kind
		if not ResourceLoader.exists(path):
			continue
		var view: Node = load(path).instantiate()
		check.root.add_child(view)
		var r := RagdollRig.of(kind, view, data[kind])
		var fit: Dictionary = fits.get(kind, {})
		if Enemy.BOSS_TITLES.has(kind) or not fit.get("ragdoll", true):
			# A boss's fall is its own set piece, and fit.json keeps a few
			# kinds' scripted falls (ActorView._ragdolls).
			kept.append(kind)
		elif r.ok:
			rigged += 1
			var high := _lies_low(ground, kind, view, r, data[kind])
			if high != "":
				floating += 1
				_check(false, high)
		else:
			kept.append(kind)
		view.free()
	_check(floating == 0, "every ragdoll lies with no part up in the air")
	if floating == 0:
		_ok("each kind shot down lies flat: no part up in the air, none sunk into the floor")
	for kind: String in ["billy", "coot", "flagman", "yard_deputy", "mundell"]:
		var r: RagdollRig = RagdollRig._built.get(kind)
		_check(r != null and r.ok, "%s has a ragdoll rig" % kind)
	_ok("%d kinds have ragdoll rigs; scripted falls: %s" % [rigged, ", ".join(kept)])
	rig = RagdollRig._built["billy"]
	for id: String in levels:
		var game: Game = main.make_game(id)
		game.configure({})
		_level(game)
	_rails(main)
	_stacked(ground)
	_first_seen(ground)
	_falls(ground)


## A body dropped onto one lying still lies across it (no ball through the
## other's), and the one under stays as it lay.
func _stacked(game: Game) -> void:
	var at := Vector2(30.5, 30.5)
	var e := _body(game, at)
	var floor_z := e.floor_z
	var size := .5
	# A knock that leaves it on its back (on its side a body is a ridge that
	# anything dropped on rolls off): the first of a few deaths' dice that does.
	var under: Ragdoll = null
	for seed in range(1, 16):
		under = Ragdoll.made(rig, _xf(at, floor_z, 0.0, size), rig.points)
		var dice := RandomNumberGenerator.new()
		dice.seed = seed
		e.killed_by = "rifle"
		e.killed_from = at - Vector2(1.0, 0.0)
		e.last_zone = ""
		under.knock(e, dice)
		under.settle(game.world, 900)
		var hips := (under.pos[0] + under.pos[1]) * .5
		var up := (under.pos[2] + under.pos[3]) * .5 - hips
		var across := (under.pos[3] - under.pos[2]) + (under.pos[1] - under.pos[0])
		if across.cross(up).normalized().z > .6:
			break
	var was := under.pos.duplicate()
	# Dropped over where the knock left it (not where it stood).
	var lain := under.middle()
	var top := Ragdoll.made(
		rig, _xf(Vector2(lain.x, lain.y), floor_z + .3, 1.6, size), rig.down_points
	)
	Ragdoll.others = [under, top]
	for _k in 900:
		if not top.awake and not under.awake:
			break
		if top.awake:
			top.step(game.world)
		if under.awake:
			under.step(game.world)
	Ragdoll.others = []
	var through := 0.0
	for i in top.pos.size():
		for j in under.pos.size():
			var gap := top.pos[i].distance_to(under.pos[j]) - top.radius[i] - under.radius[j]
			through = maxf(through, -gap)
	var moved := 0.0
	for j in was.size():
		moved = maxf(moved, was[j].distance_to(under.pos[j]))
	_check(not top.awake and not under.awake, "a body dropped on another: both come to rest")
	_check(through < .02, "it lies across the other, not through it (%.3f in)" % through)
	# Some of it rests on the other (a ball of it on one of the other's, above
	# it): a body may slide half off a round one, never lie beside it untouched.
	var resting := 0
	for i in top.pos.size():
		for j in under.pos.size():
			var gap := top.pos[i].distance_to(under.pos[j]) - top.radius[i] - under.radius[j]
			if gap < .02 and top.pos[i].z > under.pos[j].z:
				resting += 1
	_check(resting > 0, "it rests on it (%d of its balls on the other's)" % resting)
	_check(
		under.lies_on(game.world, TOL) and moved < .3,
		"the one under (knocked %.2f) still lies on the floor" % moved
	)
	_ok(
		(
			"a body dropped on another lies across it (%.3f in); the one under, knocked, lies on"
			% through
		)
	)


## Pass 11's falls on open ground, on Billy's rig and the tin guard's (his
## shield let go of): the hand-over from the pose it died in gives no ball a
## jump; through a shotgun's throw no rigid link stretches or shrinks past
## STRETCH of its length; at rest every knee is folded forwards (never back
## past KNEE_PAST), no thigh is up through the belly (the hip's stops held),
## and it lies still within REST_BY seconds, no jitter after; the same kill
## from two other ways leaves two different bodies; a head shot drops it
## where it stood, buckshot at arm's length throws it further.
func _falls(game: Game) -> void:
	var at := Vector2(30.5, 30.5)
	for kind: String in ["billy", "tin_guard"]:
		var r: RagdollRig = RagdollRig._built.get(kind)
		if r == null or not r.ok:
			_check(false, "%s has a rig to fall with" % kind)
			continue
		var faults := PackedStringArray()
		var ends: Array = []
		var drops := {}
		var rests: Array = []
		for way: float in [0.0, 2.1]:
			for how: String in ["revolver", "head", "shotgun_near"]:
				var e := _body(game, at)
				e.killed_by = "shotgun" if how == "shotgun_near" else "revolver"
				e.last_zone = "head" if how == "head" else "body"
				var far := 1.0 if how == "shotgun_near" else 3.0
				e.killed_from = at - Vector2.from_angle(way) * far
				var doll := Ragdoll.made(r, _xf(at, e.floor_z, .3, .9), r.standing())
				var before := doll.pos.duplicate()
				doll.fit()
				var jump := 0.0
				for i in R.POINTS:
					jump = maxf(jump, before[i].distance_to(doll.pos[i]))
				var dice := RandomNumberGenerator.new()
				dice.seed = 11
				doll.knock(e, dice)
				var stretch := 0.0
				var worst := ""
				var t := 0.0
				while doll.awake and t < REST_BY + .5:
					doll.step(game.world)
					t += Ragdoll.STEP
					for k in doll.la.size():
						if doll.lmin[k] == doll.lmax[k] and doll.lmin[k] > 0.0:
							var d := doll.pos[doll.la[k]].distance_to(doll.pos[doll.lb[k]])
							# (A share of the length, a few centimetres let be: a
							# small piece of gear's 3 cm side is no limb.)
							var st := maxf(0.0, absf(d - doll.lmin[k]) - STRETCH_LET) / doll.lmin[k]
							if st > stretch:
								stretch = st
								worst = "%d-%d at %.2f s" % [doll.la[k], doll.lb[k], t]
				var name := "%s %s from %.1f" % [kind, how, way]
				if jump > .02:
					faults.append("%s: the hand-over moved a ball %.3f" % [name, jump])
				if stretch > STRETCH_HIT:
					faults.append(
						"%s: a rigid link stretched %.0f%% (%s)" % [name, stretch * 100.0, worst]
					)
				var lying := 0.0
				for k in doll.la.size():
					if doll.lmin[k] == doll.lmax[k] and doll.lmin[k] > 0.0:
						var d := doll.pos[doll.la[k]].distance_to(doll.pos[doll.lb[k]])
						var ly := maxf(0.0, absf(d - doll.lmin[k]) - STRETCH_LET) / doll.lmin[k]
						if ly > lying:
							lying = ly
							worst = "%d-%d" % [doll.la[k], doll.lb[k]]
				if lying > STRETCH:
					faults.append(
						"%s: a rigid link lies stretched %.0f%% (%s)" % [name, lying * 100.0, worst]
					)
				if doll.awake or t > REST_BY:
					faults.append("%s: still moving after %.1f s" % [name, t])
				rests.append(t)
				var knee := _knees_back(doll)
				if knee != "":
					faults.append("%s: %s" % [name, knee])
				var steps := doll.steps
				for _k in 60:
					doll.advance(game.world, DT)
				if doll.steps != steps:
					faults.append("%s: stirred lying still" % name)
				var mid := doll.middle()
				ends.append([how, way, doll.pos.duplicate()])
				drops[name] = Vector2(mid.x - at.x, mid.y - at.y).length()
		for how: String in ["revolver", "head", "shotgun_near"]:
			var a: PackedVector3Array = []
			var b: PackedVector3Array = []
			for row: Array in ends:
				if row[0] == how:
					if a.is_empty():
						a = row[2]
					else:
						b = row[2]
			# The same kill from another way: not the same body turned round.
			if _shape_gap(a, b) < .05:
				faults.append(
					"%s %s: both ways lie the same (%.3f)" % [kind, how, _shape_gap(a, b)]
				)
		var head: float = drops["%s head from 0.0" % kind]
		var near: float = drops["%s shotgun_near from 0.0" % kind]
		if not near > head:
			faults.append(
				"%s: buckshot at arm's length throws it no further than a head shot" % kind
			)
		for f in faults:
			_check(false, f)
		if faults.is_empty():
			_ok(
				(
					(
						"%s's falls: no jump at the hand-over, links held, knees forwards,"
						+ " at rest in %.1f to %.1f s, two ways two bodies"
					)
					% [kind, rests.min(), rests.max()]
				)
			)


## "" when every knee folds forwards (no further behind straight than its
## stop), else what is wrong.
func _knees_back(doll: Ragdoll) -> String:
	var hips := (doll.pos[R.HIP_L] + doll.pos[R.HIP_R]) * .5
	var up := (doll.pos[R.SH_L] + doll.pos[R.SH_R]) * .5 - hips
	var across := (doll.pos[R.SH_R] - doll.pos[R.SH_L]) + (doll.pos[R.HIP_R] - doll.pos[R.HIP_L])
	var ahead := across.cross(up).normalized()
	for leg: Array in [[R.HIP_L, R.KNEE_L, R.FOOT_L], [R.HIP_R, R.KNEE_R, R.FOOT_R]]:
		var a: int = leg[0]
		var m: int = leg[1]
		var b: int = leg[2]
		var off := doll.pos[m] - (doll.pos[a] + doll.pos[b]) * .5
		var most := doll.pos[a].distance_to(doll.pos[b]) * (Ragdoll.KNEE_PAST + .03)
		if off.dot(ahead) < -most:
			return "a knee folds backwards (%.3f)" % off.dot(ahead)
	for k in doll.la.size():
		if (
			doll.lmax[k] == INF
			and doll.lb[k] in [R.BACK, R.BELLY]
			and doll.la[k] in [R.KNEE_L, R.KNEE_R]
		):
			var d := doll.pos[doll.la[k]].distance_to(doll.pos[doll.lb[k]])
			if d < doll.lmin[k] * .9:
				return "a thigh is past the hip's stop (%.3f of %.3f)" % [d, doll.lmin[k]]
	return ""


## How unlike two bodies lie, whatever way round: the largest difference in
## the distances between their balls (0 for the same shape turned or moved).
static func _shape_gap(a: PackedVector3Array, b: PackedVector3Array) -> float:
	if a.size() != b.size() or a.is_empty():
		return 0.0
	var most := 0.0
	for i in R.POINTS:
		for j in range(i + 1, R.POINTS):
			most = maxf(most, absf(a[i].distance_to(a[j]) - b[i].distance_to(b[j])))
	return most


## A body first seen long dead starts from the model's body at rest, takes a
## few steps at once and then lies still: no hitch, no stir after.
func _first_seen(game: Game) -> void:
	var at := Vector2(30.5, 30.5)
	var e := _body(game, at)
	var doll := Ragdoll.made(rig, _xf(at, e.floor_z, .7, .5), rig.lying_points)
	var t0 := Time.get_ticks_usec()
	doll.settle(game.world, ActorView.SETTLE, true)
	var took := (Time.get_ticks_usec() - t0) / 1000.0
	var steps := doll.steps
	for _t in 60:
		doll.advance(game.world, DT)
	_check(
		not doll.awake and steps <= ActorView.SETTLE and doll.steps == steps,
		"a body first seen long dead lies still at once (%d steps)" % steps
	)
	_check(doll.lies_on(game.world, TOL), "it lies on the floor (%s)" % _where(game.world, doll))
	_ok("a body first seen long dead: %d steps in %.2f ms, then still" % [steps, took])


static func _xf(at: Vector2, z: float, turn: float, size: float) -> Transform3D:
	return Transform3D(
		Basis(Vector3.UP, turn).scaled(Vector3(size, size, size)), Vector3(at.x, z, at.y)
	)


## Kind `kind` shot down on open ground and posed from its ragdoll: as
## view3d_check holds the scripted fall's key "down", no part shown (a lost
## one, the gun, is shrunk away) is higher than DOWN_HIGH of its standing
## height (or half a metre), and none sinks more than SINK into the floor.
## "" when it lies well.
func _lies_low(game: Game, kind: String, view: Node, r: RagdollRig, info: Dictionary) -> String:
	var at := Vector2(30.5, 30.5)
	var e := _body(game, at)
	e.killed_by = "shotgun"
	e.killed_from = at - Vector2(1.0, .3)
	var size := .5
	var xf := Transform3D(
		Basis(Vector3.UP, .4).scaled(Vector3(size, size, size)), Vector3(at.x, 0.0, at.y)
	)
	xf.origin.y = e.floor_z
	var doll: Ragdoll = (
		BeastDoll.made_beast(r, xf, r.points, kind)
		if r is BeastRig
		else Ragdoll.made(r, xf, r.points)
	)
	var dice := RandomNumberGenerator.new()
	dice.seed = 3
	doll.knock(e, dice)
	doll.settle(game.world, 600)
	var back := xf.affine_inverse()
	var model := PackedVector3Array()
	for p in doll.pos:
		model.append(back * Vector3(p.x, p.z, p.y))
	var skel: Skeleton3D = view.find_children("*", "Skeleton3D", true, false)[0]
	r.pose(skel, model, true)
	var floor_y := (back * Vector3(at.x, e.floor_z, at.y)).y
	var height: float = info["height"]
	var top := -INF
	var top_seg := -1
	var low := INF
	var low_bone := -1
	for m: Node in view.find_children("*", "MeshInstance3D", true, false):
		var mesh := m as MeshInstance3D
		if mesh.skin == null:
			# (A held thing on its own bone, unskinned: the Meshy models'.)
			continue
		var arrays := mesh.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if arrays[Mesh.ARRAY_BONES] == null:
			continue
		var vb: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var vw: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := vb.size() / verts.size()
		for v in range(0, verts.size(), 5):
			# (Its strongest bone: a Meshy model's vertex may have several.)
			var best := 0
			for k in per:
				if vw[v * per + k] > vw[v * per + best]:
					best = k
			var bind := vb[v * per + best]
			var bone := mesh.skin.get_bind_bone(bind)
			if bone < 0:
				bone = skel.find_bone(mesh.skin.get_bind_name(bind))
			var pose := skel.get_bone_global_pose(bone)
			if pose.basis.get_scale().x < .2:
				continue
			if r.bone_gear[bone] >= 0:
				# Gear let go of (the gun, the shield) lies on its own balls;
				# a corner of its box may dip a little (_falls holds it down).
				continue
			var y := (pose * (mesh.skin.get_bind_pose(bind) * verts[v])).y - floor_y
			if y > top:
				top_seg = r.bone_seg[bone]
			top = maxf(top, y)
			if y < low:
				low_bone = bone
			low = minf(low, y)
	if doll.awake:
		return "%s: its ragdoll is still moving" % kind
	# A beast lying on its side stands as high as its torso is wide: the
	# Meshy cow's barrel is 0.94 across (the old block cow's 0.82) and lies
	# 1.01 up, its standing height 1.45; a part higher than the torso's width
	# and a tenth more is one left up in the air.
	var wide := 0.0
	if r is BeastRig:
		var box := AABB()
		var first := true
		for b in mini(r.bone_seg.size(), r.bone_lo.size()):
			if r.bone_seg[b] == 0 and r.bone_hi[b] != r.bone_lo[b]:
				var part := AABB(r.bone_lo[b], r.bone_hi[b] - r.bone_lo[b])
				box = part if first else box.merge(part)
				first = false
		# (Its narrower way across the floor: its width, whichever way it faces.)
		wide = minf(box.size.x, box.size.z)
	if top > maxf(maxf(height * DOWN_HIGH, .5 / size), wide * 1.1):
		return (
			"%s: a part (of segment %d) lies %.2f up (standing %.2f)" % [kind, top_seg, top, height]
		)
	if low < -SINK / size:
		return (
			"%s: a part sinks %.3f into the floor (bone %d, gear %d, ride %d)"
			% [kind, -low * size, low_bone, r.bone_gear[low_bone], r.bone_ride[low_bone]]
		)
	return ""


## On a level's decks, stairs and ramps: dropped, shot and blasted.
func _level(game: Game) -> void:
	var world := game.world
	var spots: Array = []
	var seen := {"deck": 0, "stair": 0, "ramp": 0}
	for s: LevelGeometry.Slab in world.geo.slabs:
		if not s.walk:
			continue
		var mid := Vector2((s.x0 + s.x1) * .5, (s.y0 + s.y1) * .5)
		if not s.inside(mid.x, mid.y):
			continue
		var top := s.top_at(mid.x, mid.y)
		if world.blocked(mid.x, mid.y, .4, top + .4):
			continue
		var what := "ramp" if s.sloped() else "stair" if s.kind == "stair" else "deck"
		if what == "deck" and s.thick <= 0.0:
			continue
		if seen[what] >= 2:
			continue
		seen[what] += 1
		spots.append([what, s, mid])
	var bad := 0
	for spot: Array in spots:
		var s: LevelGeometry.Slab = spot[1]
		var mid: Vector2 = spot[2]
		for how: String in ["drop", "shotgun", "blast"]:
			var fault := _flop(game, mid, how, s.gx, s.gy)
			if fault != "":
				bad += 1
				_check(false, "%s %s %s %s: %s" % [game.level.id, spot[0], s.id, how, fault])
	_check(not spots.is_empty(), "%s: decks, stairs or ramps to fall on" % game.level.id)
	if bad == 0:
		_check(true, "%s ragdolls" % game.level.id)
		_ok(
			(
				"%s: %d decks, %d stairs, %d ramps: dropped, shot and blasted bodies lie on them and sleep"
				% [game.level.id, seen["deck"], seen["stair"], seen["ramp"]]
			)
		)


## A body killed at `at` (`how`: "drop", "shotgun" from a step away, "blast"
## from beside it, thrown down the slope (gx, gy) when there is one). "" when
## all is well, else what went wrong.
func _flop(game: Game, at: Vector2, how: String, gx := 0.0, gy := 0.0) -> String:
	var world := game.world
	var e := _body(game, at)
	var down := Vector2(-gx, -gy)
	if down.length() < .01:
		down = Vector2(1.0, .35)
	down = down.normalized()
	e.killed_by = "" if how == "drop" else how
	e.killed_from = at - down * (1.0 if how == "shotgun" else .6)
	e.blast_at = e.killed_from if how == "blast" else Vector2.INF
	var corpses = game.features["corpses"]
	corpses.moving.clear()
	if how == "shotgun":
		corpses._push(e, down.x * 2.6, down.y * 2.6, .5)
	elif how == "blast":
		corpses._push(e, down.x * 3.2, down.y * 3.2, 3.0)
	var r := _run(game, e, how != "drop")
	var doll: Ragdoll = r[0]
	var inside: int = r[1]
	var body: Vector3 = r[2]
	if doll.awake:
		return "still moving after 12 s (%.3f still)" % doll.still
	if inside > 0:
		return "a ball went inside something %d times" % inside
	if not doll.lies_on(world, TOL):
		return "does not lie on the floor (%s; body at %s)" % [_where(world, doll), body]
	var mid := doll.middle()
	var off := Vector2(mid.x - body.x, mid.y - body.y).length()
	if off > Ragdoll.SLACK + .4:
		return "its torso lies %.2f from play's body" % off
	# Left lying it costs nothing: no step taken in another two seconds.
	var steps := doll.steps
	for _t in 120:
		doll.follow(body, e.toss, DT)
		doll.advance(world, DT)
	if doll.steps != steps:
		return "took %d steps lying still" % (doll.steps - steps)
	return ""


## A dead hand at `at`, standing on the floor there.
func _body(game: Game, at: Vector2) -> Enemy:
	var e: Enemy = null
	for one: Enemy in game.enemies:
		if one.hostile and not Enemy.BOSS_TITLES.has(one.kind):
			e = one
			break
	var floor_z := game.world.floor_under(at.x, at.y, 99.0)
	for s: LevelGeometry.Slab in game.world.geo.slabs:
		if s.walk and s.inside(at.x, at.y):
			floor_z = maxf(floor_z, s.top_at(at.x, at.y))
	e.x = at.x
	e.y = at.y
	e.floor_z = floor_z
	e.toss = 0.0
	e.alive = false
	e.died_at = game.clock
	e.last_zone = ""
	return e


## Play's body and its ragdoll moving together until both rest (12 s at
## most). [ragdoll, times a ball was inside something, play's body].
func _run(game: Game, e: Enemy, knocked: bool) -> Array:
	var world := game.world
	var corpses = game.features["corpses"]
	var size := e.height * e.variant / 2.0
	var turn := PI * .5 - e.angle
	var z := e.floor_z
	var xf := Transform3D(
		Basis(Vector3.UP, turn).scaled(Vector3(size, size, size)), Vector3(e.x, z, e.y)
	)
	var doll := Ragdoll.made(rig, xf, rig.points)
	doll.died_at = e.died_at
	doll.turn = turn
	var body := Vector3(e.x, e.y, z)
	doll.follow(body, 0.0, 0.0)
	if knocked:
		var dice := RandomNumberGenerator.new()
		dice.seed = 7
		doll.knock(e, dice)
	var inside := 0
	var t := 0.0
	while t < 12.0:
		if not corpses.moving.is_empty():
			corpses._move(DT)
		var floor_z: float = world.floor_under(e.x, e.y, world.stand(e) + .3)
		body = Vector3(e.x, e.y, floor_z + e.toss)
		Ragdoll.budget = 99
		doll.follow(body, e.toss, DT)
		doll.advance(world, DT)
		for i in doll.pos.size():
			if Ragdoll._solid(world, doll.pos[i], doll.radius[i] * .5):
				if inside < 1 and OS.get_environment("RAG_DEBUG") != "":
					var q := doll.pos[i]
					var near := ""
					for item: Variant in world.geo.near_items(q.x, q.y):
						if item is LevelGeometry.Slab:
							var sl: LevelGeometry.Slab = item
							if sl.near(q.x, q.y, doll.radius[i]):
								near += (
									" %s[%.2f..%.2f]"
									% [sl.id, sl.bottom_at(q.x, q.y), sl.top_at(q.x, q.y)]
								)
					print(
						(
							"    old %s solid(r) %s solid(r/2) %s floor %.3f near%s"
							% [
								doll.old[i],
								Ragdoll._solid(world, doll.old[i], doll.radius[i]),
								Ragdoll._solid(world, doll.old[i], doll.radius[i] * .5),
								doll._fl.floor[i],
								near
							]
						)
					)
					print(
						(
							"    inside: ball %d at %s (r %.3f) t %.2f rail %s blocked %s"
							% [
								i,
								doll.pos[i],
								doll.radius[i],
								t,
								Ragdoll._rail_at(world, doll.pos[i], doll.radius[i] * .5) != null,
								world.blocked(
									doll.pos[i].x, doll.pos[i].y, doll.radius[i] * .4, doll.pos[i].z
								)
							]
						)
					)
				inside += 1
		t += DT
		if corpses.moving.is_empty() and not doll.awake:
			break
	return [doll, inside, body]


func _where(world: LevelData, doll: Ragdoll) -> String:
	var out := ""
	for i in doll.pos.size():
		var p := doll.pos[i]
		var under := Tumble.floor_at(
			world, p.x, p.y, p.z + .02 - doll.radius[i], doll.radius[i] * .6
		)
		out += " %d:%.2f/%.2f" % [i, p.z - doll.radius[i], under]
	return out


## The hay loft's south rail: thrown hard, over it and down; softly, kept.
func _rails(main: Node) -> void:
	var game: Game = main.make_game("hickston")
	game.configure({})
	var world := game.world
	var loft: LevelGeometry.Slab = null
	for s: LevelGeometry.Slab in world.geo.slabs:
		if s.id == "hay_loft":
			loft = s
	if loft == null:
		_check(false, "hickston has its hay loft")
		return
	var top := loft.top
	var loft_mid := Vector2(44.5, 5.5)
	for how: String in ["drop", "shotgun", "blast"]:
		var fault := _flop(game, loft_mid, how)
		_check(fault == "", "the hay loft: a body %s: %s" % [how, fault])
	_ok("the hay loft: dropped, shot and blasted bodies lie on its boards (or below) and sleep")
	var at := Vector2(44.0, 8.9)
	var corpses = game.features["corpses"]
	var ends: Array = []
	for speed: float in [5.0, 1.6]:
		var e := _body(game, at)
		e.killed_by = "shotgun"
		e.killed_from = at - Vector2(0.0, 1.0)
		corpses.moving.clear()
		corpses._push(e, 0.0, speed, .3)
		var r := _run(game, e, true)
		var doll: Ragdoll = r[0]
		var body: Vector3 = r[2]
		ends.append(body)
		var fine: bool = r[1] == 0 and not doll.awake and doll.lies_on(world, TOL)
		_check(
			fine,
			(
				"a body thrown at %.1f into the loft's rail lies on a floor (%s, inside %d)"
				% [speed, _where(world, doll), r[1]]
			)
		)
	var over: Vector3 = ends[0]
	var kept: Vector3 = ends[1]
	_check(
		over.y > 9.6 and over.z < top - 1.0,
		"thrown hard, it goes over the rail and down (%.2f, %.2f z %.2f)" % [over.x, over.y, over.z]
	)
	_check(
		kept.y < 9.54 and absf(kept.z - top) < TOL,
		"thrown softly, the rail keeps it on the loft (y %.2f z %.2f)" % [kept.y, kept.z]
	)
	_ok("the loft's rail: thrown hard a body goes over it and lies below, softly it stays up")


# ---------------------------------------------------------------- slow motion


func finishers(main: Node) -> void:
	# Pass 15: only a fight of hits.cfg [finisher] fight_least kills (3) or
	# more ends in slow motion; a fight of two does not.
	var two := _fight(main, {}, 2)
	two.enemies[_pair[0]].hurt(999.0, two, false, false, null, "revolver")
	_tick(two, 3)
	two.enemies[_pair[1]].hurt(999.0, two, false, false, null, "revolver")
	_check(two.slowmo == 0.0, "a fight of two kills ends with no slow motion (%.2f)" % two.slowmo)
	var g := _fight(main, {}, 3)
	var a: Enemy = g.enemies[_pair[0]]
	var b: Enemy = g.enemies[_pair[1]]
	var c: Enemy = g.enemies[_pair[2]]
	a.hurt(999.0, g, false, false, null, "revolver")
	_check(g.slowmo == 0.0, "the first of three kills in a fight is no finisher")
	_tick(g, 3)
	b.hurt(999.0, g, false, false, null, "revolver")
	_tick(g, 3)
	c.hurt(999.0, g, false, false, null, "revolver")
	var started := g.slowmo
	_check(
		started > 0.0 and g.slowmo_for > 0.0,
		"the last kill of a fight of three starts the slow motion (%.2f s)" % started
	)
	var paces: Array = []
	var clock := g.clock
	while g.hitstop > 0.0:
		# The kill's hold comes first (the slow motion waits for it).
		_tick(g, 1)
	for _t in 60:
		var was := g.clock
		_tick(g, 1)
		paces.append((g.clock - was) / DT)
	var least: float = paces.min()
	_check(
		least < .4 and float(paces[0]) > least and g.slowmo == 0.0 and float(paces[59]) > .99,
		(
			"it eases down to %.2f and back, then ends (first %.2f, last %.2f)"
			% [least, paces[0], paces[59]]
		)
	)
	_check(g.clock - clock < 60 * DT, "the world went slower meanwhile")
	_ok("the last of three kills slows the world to %.2f, eased, for %.2f s" % [least, started])
	# Off, with company, or on a host: never.
	for case: String in ["off", "two players", "host"]:
		var h := _fight(main, {"finish_slowmo": 0} if case == "off" else {})
		if case == "two players":
			Modes.join_beside(h, h.player)
		elif case == "host":
			h.host = true
		for i: int in _pair:
			h.enemies[i].hurt(999.0, h, false, false, null, "revolver")
		_tick(h, 2)
		_check(h.slowmo == 0.0, "no slow motion %s (%.2f)" % [case, h.slowmo])
	_ok("never with SLOW-MO FINISHERS off, with a second player or on a host")


var _pair: Array = []


## Hickston with `hands` hands fighting the player near each other, the rest asleep.
func _fight(main: Node, options: Dictionary, hands := 3) -> Game:
	var g: Game = main.make_game("hickston")
	g.configure(options)
	g.cheats.god = true
	var first := -1
	_pair = []
	for i in g.enemies.size():
		var e: Enemy = g.enemies[i]
		e.dormant = true
		if e.hostile and not Enemy.BOSS_TITLES.has(e.kind) and _pair.size() < hands:
			if first < 0:
				first = i
				_pair.append(i)
			elif (
				Vector2(e.x, e.y).distance_to(Vector2(g.enemies[first].x, g.enemies[first].y))
				< 10.0
			):
				_pair.append(i)
	for i: int in _pair:
		var e: Enemy = g.enemies[i]
		e.dormant = false
		e.alerted = true
	return g


func _tick(g: Game, n: int) -> void:
	var held := Game.Controls.new()
	for _i in n:
		g.tick(DT, held)
