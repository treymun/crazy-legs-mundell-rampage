## Write the browser and phone builds' lighter copy of the art and music,
## godot/assets_gen/lite/, from the packs tools/pack_assets.gd wrote. Only those
## builds read it (Assets.tier(); export_presets.cfg leaves it out of the
## desktop builds and the desktop copy out of theirs), so the desktop game
## looks and sounds as it did.
##
##   godot --headless --path godot --script res://tools/pack_lite.gd [-- full-textures]
##
##   art     the same pictures under the same names and index keys, in the
##           same files (art.bin, art_<chapter>.bin); a model's baked texture
##           (actor3d_*, mesh_*) bigger than LITE_TEXTURE on a side is halved
##           till it fits (the bosses' and cabs' 1024s: on a 320x200 view
##           they never show more than a few hundred texels across)
##   music   every track re-encoded as Ogg Vorbis at MUSIC_QUALITY by ffmpeg
##           (on PATH: CI's browser and APK jobs install it), in the same
##           files; the same samples, so music_ends.json holds. Without ffmpeg
##           the tracks are copied as they are, and the last line says so.
##
## Prints LITE PACKS WRITTEN (and "music re-encoded" when it was).
extends SceneTree

const AssetsLib := preload("res://src/assets.gd")

## A model texture's widest side in the lite art.
const LITE_TEXTURE := 512
## libvorbis -q:a: 3 is about 100 kbps for this stereo music (the desktop's
## tracks average 145): two thirds of the bytes.
const MUSIC_QUALITY := 3
## ffmpeg runs at once.
const ENCODERS := 6

var full := ""
var lite := ""
var failed := false


func _init() -> void:
	full = ProjectSettings.globalize_path(AssetsLib.FULL_DIR)
	lite = ProjectSettings.globalize_path(AssetsLib.LITE_DIR)
	DirAccess.make_dir_recursive_absolute(lite)
	var started := Time.get_ticks_msec()
	var halve := not OS.get_cmdline_user_args().has("full-textures")
	_art(halve)
	var encoded := _music()
	if failed:
		print("LITE PACKING FAILED")
		quit(1)
		return
	print(
		(
			"LITE PACKS WRITTEN in %.1f s to %s (%s)"
			% [
				(Time.get_ticks_msec() - started) / 1000.0,
				lite,
				"music re-encoded" if encoded else "MUSIC COPIED AS IT WAS: no ffmpeg"
			]
		)
	)
	quit()


func _fail(message: String) -> void:
	push_error(message)
	failed = true


func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		_fail("cannot read " + path + " (run tools/pack_assets.gd first)")
		return {}
	return parsed


func _write(path: String, data: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(data)
	file.close()


## Whether a picture is a model's baked texture (UV-mapped, read through
## textureSize in actor.gdshader, prop.gdshader and cab.gdshader, so any size
## draws the same model).
static func is_model_texture(name: String) -> bool:
	return name.begins_with("actor3d_") or name.begins_with("mesh_")


func _art(halve: bool) -> void:
	var index := _json(full.path_join("art_index.json"))
	if failed:
		return
	var sources := {}
	var blobs := {}
	var out := {}
	# Pictures that share bytes (twins) still share them: by file and offset.
	var done := {}
	var names := index.keys()
	names.sort()
	var halved := 0
	for name: String in names:
		var info: Dictionary = index[name]
		var file_name := str(info.get("file", "art.bin"))
		var key := "%s@%d" % [file_name, int(info["offset"])]
		if done.has(key):
			out[name] = Dictionary(done[key]).duplicate()
			continue
		if not sources.has(file_name):
			sources[file_name] = FileAccess.get_file_as_bytes(full.path_join(file_name))
			blobs[file_name] = PackedByteArray()
		var source: PackedByteArray = sources[file_name]
		var offset: int = info["offset"]
		var size: int = info["size"]
		var packed := source.slice(offset, offset + size)
		var w: int = info["w"]
		var h: int = info["h"]
		if halve and is_model_texture(name) and maxi(w, h) > LITE_TEXTURE:
			var image := Image.create_from_data(
				w,
				h,
				false,
				Image.FORMAT_RGBA8,
				packed.decompress(w * h * 4, FileAccess.COMPRESSION_DEFLATE)
			)
			while maxi(w, h) > LITE_TEXTURE:
				w = maxi(1, w / 2)
				h = maxi(1, h / 2)
			# Each texel the mean of the block it stands for (the atlases'
			# islands keep a margin of their own colour, so little bleeds).
			image.resize(w, h, Image.INTERPOLATE_BILINEAR)
			packed = image.get_data().compress(FileAccess.COMPRESSION_DEFLATE)
			halved += 1
		var blob: PackedByteArray = blobs[file_name]
		var entry := {"offset": blob.size(), "size": packed.size(), "w": w, "h": h}
		if info.has("file"):
			entry["file"] = file_name
		blob.append_array(packed)
		blobs[file_name] = blob
		out[name] = entry
		done[key] = entry
	var total := 0
	for file_name: String in blobs:
		_write(lite.path_join(file_name), blobs[file_name])
		total += PackedByteArray(blobs[file_name]).size()
	var text := FileAccess.open(lite.path_join("art_index.json"), FileAccess.WRITE)
	text.store_string(JSON.stringify(out, "", false))
	text.close()
	print("lite art %.2f MB in %d files, %d textures halved" % [total / 1e6, blobs.size(), halved])


## Re-encode every track; true when ffmpeg did it.
func _music() -> bool:
	var index := _json(full.path_join("music_index.json"))
	if failed:
		return false
	var have_ffmpeg := _ffmpeg_works()
	var work := OS.get_cache_dir().path_join("clmr_pack_lite")
	DirAccess.make_dir_recursive_absolute(work)
	var sources := {}
	var tracks := index.keys()
	tracks.sort()
	# Every chapter's file is written, even an empty one (pack_assets.gd).
	var files := {}
	for file in DirAccess.get_files_at(full):
		if file.begins_with("music") and file.ends_with(".bin"):
			files[file] = true
	var encoded := {}
	if have_ffmpeg:
		var running := []
		for track: String in tracks:
			var info: Dictionary = index[track]
			var file_name := str(info["file"])
			if not sources.has(file_name):
				sources[file_name] = FileAccess.get_file_as_bytes(full.path_join(file_name))
			var source: PackedByteArray = sources[file_name]
			var offset: int = info["offset"]
			var length: int = info["length"]
			var raw_path := work.path_join(track + ".in.ogg")
			_write(raw_path, source.slice(offset, offset + length))
			while running.size() >= ENCODERS:
				running = _reap(running)
			var args := [
				"-v",
				"error",
				"-y",
				"-i",
				raw_path,
				"-map_metadata",
				"-1",
				"-c:a",
				"libvorbis",
				"-q:a",
				str(MUSIC_QUALITY),
				work.path_join(track + ".out.ogg")
			]
			running.append(OS.create_process("ffmpeg", args))
		while not running.is_empty():
			running = _reap(running)
		for track: String in tracks:
			var made := FileAccess.get_file_as_bytes(work.path_join(track + ".out.ogg"))
			if made.slice(0, 4).get_string_from_ascii() != "OggS":
				_fail("ffmpeg made nothing for " + track)
				return false
			encoded[track] = made
			DirAccess.remove_absolute(work.path_join(track + ".in.ogg"))
			DirAccess.remove_absolute(work.path_join(track + ".out.ogg"))
	var blobs := {}
	for file_name: String in files:
		blobs[file_name] = PackedByteArray()
	var out := {}
	var before := 0
	var after := 0
	for track: String in tracks:
		var info: Dictionary = index[track]
		var file_name := str(info["file"])
		var data: PackedByteArray = encoded.get(track, PackedByteArray())
		if data.is_empty():
			if not sources.has(file_name):
				sources[file_name] = FileAccess.get_file_as_bytes(full.path_join(file_name))
			var source: PackedByteArray = sources[file_name]
			var offset: int = info["offset"]
			data = source.slice(offset, offset + int(info["length"]))
		before += int(info["length"])
		after += data.size()
		var blob: PackedByteArray = blobs.get(file_name, PackedByteArray())
		out[track] = {"file": file_name, "offset": blob.size(), "length": data.size()}
		blob.append_array(data)
		blobs[file_name] = blob
	for file_name: String in blobs:
		_write(lite.path_join(file_name), blobs[file_name])
	var text := FileAccess.open(lite.path_join("music_index.json"), FileAccess.WRITE)
	text.store_string(JSON.stringify(out, "", false))
	text.close()
	print("lite music %.2f MB (was %.2f MB), %d tracks" % [after / 1e6, before / 1e6, out.size()])
	return have_ffmpeg


func _ffmpeg_works() -> bool:
	var output := []
	var code := OS.execute("ffmpeg", ["-v", "error", "-hide_banner", "-encoders"], output, true)
	return code == 0 and "libvorbis" in "".join(PackedStringArray(output))


## The processes still running (waits a moment first).
func _reap(running: Array) -> Array:
	OS.delay_msec(20)
	var still := []
	for pid: int in running:
		if pid > 0 and OS.is_process_running(pid):
			still.append(pid)
	return still
