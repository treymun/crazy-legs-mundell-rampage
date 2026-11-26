## Meshy models track: grade PNGs as build_actor_meshes.gd grades an actor's
## look (Paint.photo_grade, then Paint.digitize), to try a colour fix before
## a build.
##
##   godot --headless --path godot --script res://tools/meshy/grade_png.gd \
##       --<tag> <in.png> <out.png> [...]
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var tag: String = args[0]
	var seed := 0
	for ch in tag.to_utf8_buffer():
		seed += ch
	var i := 1
	while i + 1 < args.size():
		var baked := Paint.Sheet.load_png(args[i])
		Paint.digitize(Paint.photo_grade(baked, seed)).save(args[i + 1])
		i += 2
	quit()
