## Write the browser build's chapter music packs and their manifest.
##
##   Godot --headless --path <project> --script res://tools/make_packs.gd -- <web build dir>
##
## Each pack holds one assets_gen/music_<chapter>.bin (tools/pack_assets.gd) and is
## named after its contents' hash, so a browser that kept an older pack from
## an earlier visit fetches the new one. packs.json lists them in the order
## src/pack_loader.gd fetches them: the first chapter first.
extends SceneTree

const PACKS := ["music_hickston", "music_fair", "music_mill", "music_quarry"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: make_packs.gd -- <web build dir>")
		quit(1)
		return
	var out := String(args[0])
	var manifest := {}
	for pack: String in PACKS:
		var source := "res://assets_gen/%s.bin" % pack
		if not FileAccess.file_exists(source):
			push_error("missing " + source + " (run tools/pack_assets.gd)")
			quit(1)
			return
		var file := "%s-%s.pck" % [pack, FileAccess.get_md5(source).substr(0, 10)]
		var target := out.path_join(file)
		var packer := PCKPacker.new()
		packer.pck_start(target)
		packer.add_file(source, ProjectSettings.globalize_path(source))
		packer.flush()
		var handle := FileAccess.open(target, FileAccess.READ)
		manifest[pack] = {"file": file, "size": handle.get_length()}
		handle.close()
		print("%s %.1f MB" % [file, manifest[pack]["size"] / 1e6])
	var list := FileAccess.open(out.path_join("packs.json"), FileAccess.WRITE)
	# In fetching order (stringify sorts keys unless told not to).
	list.store_string(JSON.stringify(manifest, "", false))
	list.close()
	print("PACKS OK: ", manifest.size())
	quit()
