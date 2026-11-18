## Write the browser build's chapter packs and their manifest.
##
##   Godot --headless --path <project> --script res://tools/make_packs.gd -- <web build dir>
##
## The first download (index.pck) holds the title and Hickston; every other
## chapter's own files come down after the game starts, one pack each
## (src/pack_loader.gd): its music (assets_gen/lite/music_<stem>.bin), its
## enemies' pictures and baked looks (lite/art_<stem>.bin), its enemies' sounds
## (lite/sfx_<stem>.bin) and their models (the imported scenes of
## assets3d/actors/<kind>.glb), all by Assets.chapter_of, and the props only it
## shows (their baked pictures in its art file, their models:
## tools/prop_homes.gd). Hickston's pack is
## its music alone. Run tools/pack_assets.gd, tools/pack_lite.gd and the import
## first. Each pack is named after its contents' hash, so a browser that kept
## an older pack from an earlier visit fetches the new one. packs.json lists
## them in the order src/pack_loader.gd fetches them: the first chapter first.
extends SceneTree

const AssetsLib := preload("res://src/assets.gd")
const PropHomes := preload("res://tools/prop_homes.gd")

## The chapters in fetching order.
const ORDER := [
	"hickston", "fair", "sawmill", "quarry", "bayou", "speedway", "moonshine", "mothership"
]
const ACTORS := "res://assets3d/actors"
const PROPS := "res://assets3d/props"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: make_packs.gd -- <web build dir>")
		quit(1)
		return
	var out := String(args[0])
	var manifest := {}
	var total := 0
	for level_id: String in ORDER:
		var pack := pack_name(level_id)
		var parts := pack_files(level_id)
		var sums := ""
		for part: String in parts:
			if not FileAccess.file_exists(part):
				push_error("missing " + part + " (run pack_assets.gd, pack_lite.gd, --import)")
				quit(1)
				return
			sums += FileAccess.get_md5(part)
		var file := "%s-%s.pck" % [pack, sums.md5_text().substr(0, 10)]
		var target := out.path_join(file)
		var packer := PCKPacker.new()
		packer.pck_start(target)
		for part: String in parts:
			packer.add_file(part, ProjectSettings.globalize_path(part))
		# The models' ids: index.pck's id list was made without them.
		var uids := _uids(parts)
		if uids != "":
			var list_path := OS.get_cache_dir().path_join("clmr_%s.uids" % pack)
			var handle := FileAccess.open(list_path, FileAccess.WRITE)
			handle.store_string(uids)
			handle.close()
			packer.add_file(uid_list(pack), list_path)
		packer.flush()
		var handle := FileAccess.open(target, FileAccess.READ)
		manifest[pack] = {"file": file, "size": handle.get_length()}
		handle.close()
		total += int(manifest[pack]["size"])
		print("%s %.1f MB (%d files)" % [file, manifest[pack]["size"] / 1e6, parts.size()])
	var list := FileAccess.open(out.path_join("packs.json"), FileAccess.WRITE)
	# In fetching order (stringify sorts keys unless told not to).
	list.store_string(JSON.stringify(manifest, "", false))
	list.close()
	print("PACKS OK: %d, %.1f MB" % [manifest.size(), total / 1e6])
	quit()


static func pack_name(level_id: String) -> String:
	return "chapter_" + level_id


## Where a pack keeps its models' ids (src/pack_loader.gd reads it).
static func uid_list(pack: String) -> String:
	return "res://packs/%s.uids" % pack


## "uid path" a line for each imported model among `parts`.
static func _uids(parts: PackedStringArray) -> String:
	var lines := PackedStringArray()
	for part in parts:
		if not part.ends_with(".import"):
			continue
		var config := ConfigFile.new()
		if config.load(part) == OK and config.has_section_key("remap", "uid"):
			lines.append("%s %s" % [config.get_value("remap", "uid"), part.trim_suffix(".import")])
	return "\n".join(lines)


## Every res:// file chapter `level_id`'s pack holds.
static func pack_files(level_id: String) -> PackedStringArray:
	var parts := PackedStringArray()
	var stem := AssetsLib.stem_of(level_id)
	if level_id == "hickston":
		stem = "hickston"
	parts.append(AssetsLib.LITE_DIR + "music_%s.bin" % stem)
	if level_id == "hickston":
		return parts
	parts.append(AssetsLib.LITE_DIR + "art_%s.bin" % stem)
	parts.append(AssetsLib.LITE_DIR + "sfx_%s.bin" % stem)
	for model in chapter_models(level_id, PropHomes.homes()):
		parts.append_array(imported_files(model))
	return parts


## The chapter's own models: its enemies' (assets3d/actors/<kind>.glb and
## its baked rig <kind>.rig, Assets.chapter_of) and its props' (assets3d/props/<name>.glb,
## tools/prop_homes.gd: `props` is its homes()).
static func chapter_models(level_id: String, props: Dictionary) -> PackedStringArray:
	var models := PackedStringArray()
	for file in DirAccess.get_files_at(ACTORS):
		var ext := file.get_extension()
		# A kind's model and its baked ragdoll rig (RagdollRig.BAKED).
		if (ext == "glb" or ext == "rig") and AssetsLib.chapter_of(file.get_basename()) == level_id:
			models.append(ACTORS.path_join(file))
	var stem := AssetsLib.stem_of(level_id)
	for file in DirAccess.get_files_at(PROPS):
		if file.get_extension() == "glb" and stem != "" and props.get(file.get_basename()) == stem:
			models.append(PROPS.path_join(file))
	models.sort()
	return models


## A model's .import file and what its import wrote (.godot/imported), as an
## export puts them in a pack; a file that is not imported (a baked rig) as
## itself.
static func imported_files(model: String) -> PackedStringArray:
	if model.get_extension() != "glb":
		return PackedStringArray([model])
	var files := PackedStringArray([model + ".import"])
	var config := ConfigFile.new()
	if config.load(model + ".import") != OK:
		return files
	for dest: String in config.get_value("deps", "dest_files", []):
		files.append(dest)
	return files
