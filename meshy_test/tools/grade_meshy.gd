## Scratch-only: grade Meshy bakes as build_prop_meshes.gd grades its props.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")


func _init() -> void:
	var src: String = OS.get_cmdline_user_args()[0]
	for name: String in ["enemy", "hog", "tractor"]:
		var baked := Paint.Sheet.load_png(src.path_join(name + "_bake.png"))
		var full := "meshy_" + name
		var seed := 0
		for ch in full.to_utf8_buffer():
			seed += ch
		Paint.digitize(Paint.photo_grade(baked, seed)).save(Paint.repo("assets/art/mesh_%s.png" % full))
		print("graded ", full)
	quit()
