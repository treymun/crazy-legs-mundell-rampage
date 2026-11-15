## Where each boss's gear sits on its model (assets3d/actors "gear"): its
## middle as [ahead, right, up] and its half height and half width, each a
## share of the boss's height, for bosses.cfg [boss_gear] "at", "half" and
## "wide" (features/boss_gear.gd starts a piece shot off there).
##
##   godot --headless --path godot --script res://tools/gear_fit.gd
extends SceneTree


func _init() -> void:
	var assets := Assets.new()
	var models := ActorModels.new(assets)
	for kind: String in models.kinds:
		var info: Dictionary = models.kinds[kind]
		var gear: Dictionary = info.get("gear", {})
		if gear.is_empty():
			continue
		var names := {}
		for bone: String in gear:
			names[gear[bone]] = true
		var canvas: Array = info.get("canvas", [1.0, 1.0])
		var tall: float = canvas[1]
		var fit: float = info.get("scale", 1.0)
		for name: String in names:
			var made := models.gear_mesh(kind, name)
			if made.is_empty():
				print("%s %s: NO MESH" % [kind, name])
				continue
			var mesh: ArrayMesh = made[0]
			var middle: Vector3 = made[1]
			var box := mesh.get_aabb()
			var k := fit / tall
			print(
				(
					"%s %s: at [%.2f, %.2f, %.2f] half %.3f wide %.3f (%d tris)"
					% [
						kind,
						name,
						middle.z * k,
						-middle.x * k,
						middle.y * k,
						box.size.y * .5 * k,
						maxf(box.size.x, box.size.z) * .5 * k,
						mesh.surface_get_array_len(0) / 3,
					]
				)
			)
	quit()
