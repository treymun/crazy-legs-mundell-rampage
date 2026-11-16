## Scratch (track M): how deep each rigged kind's mesh sinks into the floor
## when its ragdoll is at rest, over a few kills.
extends SceneTree


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var data: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets3d/actors/actors.json")
	)
	var fits: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets3d/actors/fit.json")
	)
	var game: Game = main.make_game("hickston")
	game.configure({})
	var worst := 0.0
	var t0 := Time.get_ticks_usec()
	var steps := 0
	for kind: String in data:
		var path := "res://scenes/actors/%s.tscn" % kind
		if not ResourceLoader.exists(path):
			continue
		var fit: Dictionary = fits.get(kind, {})
		if Enemy.BOSS_TITLES.has(kind) or not fit.get("ragdoll", true):
			continue
		var view: Node = load(path).instantiate()
		root.add_child(view)
		var tb := Time.get_ticks_usec()
		var r := RagdollRig.of(kind, view, data[kind])
		print("  build %s %.1f ms" % [kind, (Time.get_ticks_usec() - tb) / 1000.0])
		if not r.ok:
			view.free()
			continue
		var line := kind + ":"
		var kmax := 0.0
		var kfloat := 9.0
		for how: String in ["shotgun", "rifle", "blast", "drop"]:
			for seed in 3:
				var res := _one(game, view, r, how, seed)
				kmax = maxf(kmax, res.x)
				kfloat = minf(kfloat, res.y)
				steps += int(res.z)
		line += " sink %.3f  lowest-gap %.3f" % [kmax, kfloat]
		worst = maxf(worst, kmax)
		print(line)
		view.free()
	print("worst sink %.3f; %.1f us a step" % [worst, (Time.get_ticks_usec() - t0) / maxf(1.0, steps)])
	var rig: RagdollRig = RagdollRig._built["billy"]
	for with_hull in [false, true, false, true]:
		var spent := 0
		var n := 0
		for seed in 8:
			var xf := Transform3D(Basis(Vector3.UP, seed).scaled(Vector3.ONE * .5), Vector3(30.5, 0.0, 30.5))
			var doll := Ragdoll.made(rig, xf, rig.points)
			if not with_hull:
				doll.rig = null
			var e: Enemy = game.enemies[0]
			e.x = 30.5
			e.y = 30.5
			e.killed_by = "shotgun"
			e.killed_from = Vector2(29.5, 30.0 + seed * .2)
			var dice := RandomNumberGenerator.new()
			dice.seed = seed
			doll.knock(e, dice)
			var t1 := Time.get_ticks_usec()
			for k in 120:
				if doll.awake:
					doll.step(game.world)
					n += 1
			spent += Time.get_ticks_usec() - t1
		print("hull %s: %.1f us a step (%d steps)" % [with_hull, spent / maxf(1.0, n), n])
	quit()


## [deepest sink, smallest gap of the lowest vertex (negative: sunk), steps]
func _one(game: Game, view: Node, r: RagdollRig, how: String, seed: int) -> Vector3:
	var at := Vector2(30.5, 30.5)
	var e: Enemy = null
	for one: Enemy in game.enemies:
		if one.hostile and not Enemy.BOSS_TITLES.has(one.kind):
			e = one
			break
	e.x = at.x
	e.y = at.y
	e.floor_z = game.world.floor_under(at.x, at.y, 99.0)
	e.alive = false
	e.last_zone = "head" if how == "rifle" else ""
	e.killed_by = "" if how == "drop" else how
	e.killed_from = at - Vector2(1.0, .3 + seed * .4)
	e.blast_at = e.killed_from if how == "blast" else Vector2.INF
	var size := .5
	var xf := Transform3D(
		Basis(Vector3.UP, .4 + seed).scaled(Vector3(size, size, size)), Vector3(at.x, 0.0, at.y)
	)
	xf.origin.y = e.floor_z
	var doll := Ragdoll.made(r, xf, r.points)
	var dice := RandomNumberGenerator.new()
	dice.seed = seed + 11
	if how != "drop":
		doll.knock(e, dice)
	doll.settle(game.world, 900)
	var back := xf.affine_inverse()
	var model := PackedVector3Array()
	for p in doll.pos:
		model.append(back * Vector3(p.x, p.z, p.y))
	var skel: Skeleton3D = view.find_children("*", "Skeleton3D", true, false)[0]
	r.pose(skel, model, true)
	var low := INF
	for m: Node in view.find_children("*", "MeshInstance3D", true, false):
		var mesh := m as MeshInstance3D
		if mesh.skin == null:
			continue
		var arrays := mesh.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var vb: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var vw: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var per := vb.size() / verts.size()
		for v in verts.size():
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
			var g := xf * (pose * (mesh.skin.get_bind_pose(bind) * verts[v]))
			if g.y - e.floor_z < low and OS.get_environment("SEGDBG") != "":
				print("  %s seg %d bone %s %.3f" % [how, r.bone_seg[bone], skel.get_bone_name(bone), g.y - e.floor_z])
			low = minf(low, g.y - e.floor_z)
	return Vector3(maxf(0.0, -low), low, doll.steps)
