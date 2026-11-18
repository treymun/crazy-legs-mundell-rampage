## Writes each actor kind's ragdoll rig beside its model
## (assets3d/actors/<kind>.rig, RagdollRig.BAKED): the game reads it back at
## a level's first frame instead of finding it from the model's vertices.
## Run after changing an actor's model or its actors.json labels or keys
## (tools/load_check.gd fails while a file is out of date and names this).
##
##   godot --headless --path godot --script res://tools/art/bake_rigs.gd
extends SceneTree


func _init() -> void:
	var models := ActorModels.new(Assets.new())
	var written := 0
	var size := 0
	for kind: String in models.kinds:
		var info: Dictionary = models.kinds[kind]
		var packed := models.scene(kind)
		if packed == null:
			continue
		var view := packed.instantiate()
		var rig := RagdollRig.new()
		rig._build(view, info)
		view.free()
		var bytes := rig.to_baked(info)
		var file := FileAccess.open(RagdollRig.BAKED % kind, FileAccess.WRITE)
		file.store_buffer(bytes)
		file.close()
		written += 1
		size += bytes.size()
	print("RIGS BAKED: %d kinds, %.0f KB" % [written, size / 1024.0])
	quit()
