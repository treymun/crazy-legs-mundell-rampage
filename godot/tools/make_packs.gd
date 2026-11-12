## Write the browser build's chapter music packs and their manifest.
##
##   Godot --headless --path <project> --script res://tools/make_packs.gd -- <web build dir>
##
## Each pack holds one assets_gen/music_<chapter>.bin (tools/pack_assets.gd) and is
## named after its contents' hash, so a browser that kept an older pack from
## an earlier visit fetches the new one. packs.json lists them in the order
## src/pack_loader.gd fetches them: the first chapter first.
extends SceneTree

## Each pack and the assets_gen files in it: a chapter's music, and the
## pictures of the enemies only that chapter has (assets.gd CHAPTER_ART).
const PACKS := {
	"music_hickston": ["music_hickston.bin"],
	"music_fair": ["music_fair.bin", "art_fair.bin"],
	"music_mill": ["music_mill.bin", "art_mill.bin"],
	"music_quarry": ["music_quarry.bin", "art_quarry.bin"],
	"music_mothership": ["music_mothership.bin", "art_mothership.bin"],
}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: make_packs.gd -- <web build dir>")
		quit(1)
		return
	var out := String(args[0])
	var manifest := {}
	for pack: String in PACKS:
		var sums := ""
		for part: String in PACKS[pack]:
			var source := "res://assets_gen/" + part
			if not FileAccess.file_exists(source):
				push_error("missing " + source + " (run tools/pack_assets.gd)")
				quit(1)
				return
			sums += FileAccess.get_md5(source)
		var file := "%s-%s.pck" % [pack, sums.md5_text().substr(0, 10)]
		var target := out.path_join(file)
		var packer := PCKPacker.new()
		packer.pck_start(target)
		for part: String in PACKS[pack]:
			var source := "res://assets_gen/" + part
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
