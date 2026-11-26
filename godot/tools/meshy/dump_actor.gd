## Meshy models track: dump a kind's current model as the ragdoll rig sees it,
## frame by frame, so a new mesh can be posed the same way (meshy/README.md).
##
##   godot --headless --path godot --script res://tools/meshy/dump_actor.gd \
##       -- kinds=billy,coot out=<dir>
##
## Writes <dir>/<kind>_poses.json: the rig's fifteen points at every key of
## the action (model space, y up), each bone's pose at every key, the labels,
## the rig's radii, stiff limbs and gear bones.
extends SceneTree


func _init() -> void:
	var kinds := ""
	var out := ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("kinds="):
			kinds = arg.substr(6)
		elif arg.begins_with("out="):
			out = arg.substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	var models := ActorModels.new(Assets.new())
	for kind in kinds.split(",", false):
		var info: Dictionary = models.kinds.get(kind, {})
		var packed := models.scene(kind)
		if packed == null:
			print("no scene for ", kind)
			continue
		var view := packed.instantiate()
		var rig := RagdollRig.fresh(info)
		rig.build(view, info)
		var skel := view.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var player := view.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
		var anim := player.get_animation(player.get_animation_list()[0])
		var frames: Dictionary = info.get("frames", {})
		var dump := {
			"kind": kind,
			"ok": rig.ok,
			"frames": frames,
			"labels": info.get("labels", {}),
			"height": info.get("height", 0.0),
			"bones": [],
			"points": {},
			"poses": {},
			"rest_points": _pts(rig.points),
			"radii": Array(rig.radii),
			"stiff": Array(rig.stiff),
			"anchors": Array(rig.anchors),
			"bone_seg": Array(rig.bone_seg),
			"gear_bones": [],
			"segs": rig.segs() if rig.ok else 0,
		}
		for g: PackedInt32Array in rig.gear_bones:
			dump["gear_bones"].append(Array(g))
		for i in skel.get_bone_count():
			dump["bones"].append(skel.get_bone_name(i))
		for name: String in frames:
			var key: float = frames[name]
			var poses := RagdollRig._poses(anim, skel, key * ActorModels.KEY_TIME)
			var row: Array = []
			for p: Transform3D in poses:
				var q := p.basis.get_rotation_quaternion()
				var s := p.basis.get_scale()
				row.append([p.origin.x, p.origin.y, p.origin.z, q.x, q.y, q.z, q.w, s.x, s.y, s.z])
			dump["poses"][name] = row
			if rig.ok:
				dump["points"][name] = _pts(rig.points_from(poses))
		var f := FileAccess.open(out.path_join(kind + "_poses.json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(dump))
		f.close()
		view.free()
		print("dumped ", kind, " ok=", rig.ok, " stiff=", Array(rig.stiff))
	quit()


static func _pts(a: PackedVector3Array) -> Array:
	var out: Array = []
	for p in a:
		out.append([p.x, p.y, p.z])
	return out
