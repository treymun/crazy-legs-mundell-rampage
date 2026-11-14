## The armory's wall pictures of the guns and throwables that have no pickup
## picture of their own (the 5v5 store's): Blender lays each first-person model
## (scripts/blender/weapon_views.py) on its side and renders it square on
## (scripts/blender/item_pictures.py); this crops each to its edges, shrinks it
## to its size on the rack with the props' grade (paint.gd photo_shrink) and
## commits it to the palette as assets/art/item_<name>.png.
##
##   godot --headless --path godot --script res://tools/art/build_item_art.gd \
##       [-- names=hunter,tommy] [no-render] [out=<dir>]
##
## BLENDER_PATH overrides where Blender is; no-render reuses the last renders
## (_preview/items/raw). Then run tools/pack_assets.gd.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")
const Actors := preload("res://tools/art/build_enemy_actors.gd")
const SUPERSAMPLE := 4
## Pixels on the long side: long guns half again the ranch rifle's picture,
## handguns and the grease gun half that, throwables this tall.
const LONG := 72
const SHORT := 32
const THROWN := 24
const SHORT_GUNS := ["county45", "star357", "hogleg", "grease_gun"]
const THROWN_ITEMS := ["flash_jar", "smudge_pot", "shine_cocktail", "firecracker_can"]


func _init() -> void:
	var names := "all"
	var render := true
	var out := Paint.repo("assets/art")
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text.begins_with("names="):
			names = text.substr(6)
		elif text == "no-render":
			render = false
		elif text.begins_with("out="):
			out = text.substr(4)
	var raw := Paint.repo("_preview/items/raw")
	DirAccess.make_dir_recursive_absolute(raw)
	DirAccess.make_dir_recursive_absolute(out)
	if render:
		var code := OS.execute(
			Actors.blender(),
			[
				"-b",
				"-P",
				Paint.repo("scripts/blender/item_pictures.py"),
				"--",
				raw,
				names,
				str(SUPERSAMPLE)
			]
		)
		if code != 0:
			push_error("Blender failed (exit %d); set BLENDER_PATH if it is elsewhere" % code)
			quit(1)
			return
	var sizes = JSON.parse_string(FileAccess.get_file_as_string(raw.path_join("items.json")))
	if not sizes is Dictionary:
		push_error("no %s/items.json: render first" % raw)
		quit(1)
		return
	var count := 0
	for name: String in sizes:
		if names != "all" and not (name in names.split(",")):
			continue
		var image := Paint.Sheet.load_png(raw.path_join("item_%s.png" % name))
		var box := image.bbox(127)
		if box.size.x <= 0 or box.size.y <= 0:
			push_error("%s rendered empty" % name)
			continue
		var cut := image.cropped(box)
		var target: Vector2i
		if name in THROWN_ITEMS:
			target = Vector2i(maxi(1, roundi(THROWN * cut.w / float(cut.h))), THROWN)
		else:
			var wide := SHORT if name in SHORT_GUNS else LONG
			target = Vector2i(wide, maxi(1, roundi(wide * cut.h / float(cut.w))))
		var seed := 0
		for c in name.to_utf8_buffer():
			seed += c
		var sprite := Paint.digitize(Paint.photo_shrink(cut, target, seed))
		sprite.save(out.path_join("item_%s.png" % name))
		count += 1
	print("item pictures: %d written to %s" % [count, out])
	quit()
