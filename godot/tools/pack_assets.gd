## Pack the game's art, sound, music, tiles, skies and palette into the plain
## binary files the game reads (godot/assets_gen/), from the sources in the
## repository: assets/ (art, tiles, skies, palette, grain), audio_src/final/sfx
## with audio_src/manifest.json, and godot/assets/music.
##
##   Godot --headless --path godot --script res://tools/pack_assets.gd [-- <out dir>]
##
## The packs are not committed (about 70 MB); a fresh clone or a CI job runs
## this once before opening or exporting the project. Their *_index.json files
## are committed, and tiles_index.json is also the list of tiles, in the order
## the levels number them.
##
##   tiles.bin    128x128 RGB per tile, in tiles_index.json order
##   art.bin      each picture's RGBA, deflated on its own (assets.gd inflates
##                it the first time it is drawn), + art_index.json
##   sfx.bin      every cue of the audio manifest, mono 16-bit, + sfx_index.json
##   music.bin    the menu theme and the tally tune (Ogg Vorbis), and
##   music_<chapter>.bin   each chapter's three tracks and its fight loop (a
##                browser build leaves these out of its first download:
##                tools/make_packs.gd), +
##                music_index.json (track -> file, offset, length), music_ends.json
##   sky.bin      the 512x116 panoramas, + sky_index.json
##   palette.bin  the RGB555 -> 256-colour table; grain.bin the film grain frames
extends SceneTree

## By path, not class name: CI packs before the project is imported, when
## class names do not resolve yet.
const AssetsLib := preload("res://src/assets.gd")

const SFX_RATE := 22050
const SKIES := ["sky", "fair_sky", "mill_sky", "quarry_sky", "bayou_sky", "speedway_sky"]
## Each chapter's file: its tracks, the loop its fights swell into
## (Sound.FIGHTS), then its boss loop (Sound.BOSSES).
const MUSIC_FILES := {
	"music_hickston":
	["music", "county_line", "porchlight_stomp", "fight_hickston", "boss_hickston"],
	"music_fair":
	["fair_score", "tickets_after_dark", "closing_time_shuffle", "fight_fair", "boss_fair"],
	"music_mill": ["mill_score", "green_chain", "apron_run", "fight_mill", "boss_mill"],
	"music_quarry":
	["quarry_score", "copper_and_steam", "last_load", "fight_quarry", "boss_quarry"],
	"music_bayou":
	["bayou_score", "cypress_crawl", "crawdad_boil_hop", "fight_bayou", "boss_bayou"],
	"music_speedway":
	[
		"music_speedway",
		"pit_row_boogie",
		"checkered_flag_rag",
		"fight_speedway",
		"boss_speedway",
	],
	"music_mothership": ["mothership_score", "fight_mothership", "boss_mothership"],
}
## Tracks not made yet are listed in assets.gd PENDING_MUSIC: only noted here,
## and their chapter's file is written all the same (empty if none is made).
const REQUIRED_MUSIC := ["title", "victory"]

var repo := ""
var out := ""
var failed := false


func _init() -> void:
	repo = ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	out = ProjectSettings.globalize_path("res://assets_gen")
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out = String(args[0])
	DirAccess.make_dir_recursive_absolute(out)
	var started := Time.get_ticks_msec()
	_tiles()
	_art()
	_sfx()
	_music()
	_skies()
	_copy("assets/tiles/vga_rgb555.bin", "palette.bin")
	_copy("assets/tiles/grain.bin", "grain.bin")
	_copy("assets/art/weapon_anchors.json", "weapon_anchors.json")
	if failed:
		print("PACKING FAILED")
		quit(1)
		return
	print("PACKS WRITTEN in %.1f s to %s" % [(Time.get_ticks_msec() - started) / 1000.0, out])
	quit()


func _fail(message: String) -> void:
	push_error(message)
	failed = true


func _write(name: String, data: PackedByteArray) -> void:
	var file := FileAccess.open(out.path_join(name), FileAccess.WRITE)
	file.store_buffer(data)
	file.close()


func _write_json(name: String, value) -> void:
	var file := FileAccess.open(out.path_join(name), FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "", false))
	file.close()


func _copy(source: String, name: String) -> void:
	var data := FileAccess.get_file_as_bytes(repo.path_join(source))
	if data.is_empty():
		_fail("missing " + source)
		return
	_write(name, data)


func _sorted_files(folder: String, extension: String) -> PackedStringArray:
	var names := PackedStringArray()
	for file in DirAccess.get_files_at(repo.path_join(folder)):
		if file.get_extension().to_lower() == extension:
			names.append(file)
	names.sort()
	return names


func _image(path: String, format: Image.Format) -> Image:
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	image.convert(format)
	return image


func _tiles() -> void:
	# tiles_index.json (committed) is the list of tiles, in the levels' numbering.
	var names: Array = (
		JSON.parse_string(FileAccess.get_file_as_string(out.path_join("tiles_index.json")))["names"]
	)
	var blob := PackedByteArray()
	var missing := PackedStringArray()
	for name: String in names:
		var image := _image(repo.path_join("assets/tiles/%s.png" % name), Image.FORMAT_RGB8)
		if image == null:
			missing.append(name)
			var blank := PackedByteArray()
			blank.resize(128 * 128 * 3)
			blob.append_array(blank)
			continue
		if image.get_width() != 128 or image.get_height() != 128:
			_fail("tile %s is %dx%d, not 128x128" % [name, image.get_width(), image.get_height()])
		blob.append_array(image.get_data())
	_write("tiles.bin", AssetsLib.pack_whole(blob))
	print("tiles.bin %.2f MB, %d tiles, missing %s" % [blob.size() / 1e6, names.size(), missing])


func _art() -> void:
	var index := {}
	var blob := PackedByteArray()
	# A chapter's own enemies go in a file of their own, which the browser
	# build fetches after it starts (src/assets.gd, tools/make_packs.gd).
	var chapter_blobs := {}
	for file_name: String in AssetsLib.CHAPTER_ART.values():
		chapter_blobs[file_name] = PackedByteArray()
	for file in _sorted_files("assets/art", "png"):
		var image := _image(repo.path_join("assets/art").path_join(file), Image.FORMAT_RGBA8)
		if image == null:
			_fail("cannot read assets/art/" + file)
			continue
		# Sprites are mostly empty air: each one is deflated on its own and
		# inflated the first time the game asks for it.
		var packed := image.get_data().compress(FileAccess.COMPRESSION_DEFLATE)
		var home := AssetsLib.art_home(file.get_basename())
		var into: PackedByteArray = blob if home == "" else chapter_blobs[home]
		var entry := {
			"offset": into.size(),
			"size": packed.size(),
			"w": image.get_width(),
			"h": image.get_height()
		}
		if home != "":
			entry["file"] = home
		index[file.get_basename()] = entry
		into.append_array(packed)
		if home != "":
			chapter_blobs[home] = into
	_write("art.bin", blob)
	for file_name: String in chapter_blobs:
		_write(file_name, chapter_blobs[file_name])
		print("%s %.2f MB" % [file_name, chapter_blobs[file_name].size() / 1e6])
	_write_json("art_index.json", index)
	print("art.bin %.2f MB, %d pictures" % [blob.size() / 1e6, index.size()])


## Mono 16-bit samples of a WAV file at SFX_RATE, or an empty array.
func _wav(path: String, problems: PackedStringArray, name: String) -> PackedByteArray:
	var data := FileAccess.get_file_as_bytes(path)
	if data.size() < 12 or data.slice(0, 4).get_string_from_ascii() != "RIFF":
		problems.append(name + ": no file")
		return PackedByteArray()
	var at := 12
	var channels := 0
	var bits := 0
	var rate := 0
	while at + 8 <= data.size():
		var chunk := data.slice(at, at + 4).get_string_from_ascii()
		var size := data.decode_u32(at + 4)
		if chunk == "fmt ":
			channels = data.decode_u16(at + 10)
			rate = data.decode_u32(at + 12)
			bits = data.decode_u16(at + 22)
		elif chunk == "data":
			if channels != 1 or bits != 16 or rate != SFX_RATE or size == 0:
				problems.append(
					"%s: %d ch, %d-bit, %d Hz, %d frames" % [name, channels, bits, rate, size / 2]
				)
				return PackedByteArray()
			return data.slice(at + 8, at + 8 + size)
		at += 8 + size + (size & 1)
	problems.append(name + ": no data")
	return PackedByteArray()


func _sfx() -> void:
	# Every cue in the audio manifest, nothing else; a missing or wrong file
	# stops the build, because the game drops unknown cues silently.
	var manifest = JSON.parse_string(
		FileAccess.get_file_as_string(repo.path_join("audio_src/manifest.json"))
	)
	var names: Array = (manifest["cues"] as Dictionary).keys()
	names.sort()
	var index := {}
	var blob := PackedByteArray()
	var problems := PackedStringArray()
	for name: String in names:
		var raw := _wav(repo.path_join("audio_src/final/sfx/%s.wav" % name), problems, name)
		if raw.is_empty():
			continue
		# QOA, about a fifth of the 16-bit samples and near enough the same
		# sound; Godot plays it as it is (assets.gd cue()).
		var qoa := _qoa(raw)
		if qoa.is_empty():
			problems.append(name + ": QOA encoding failed")
			continue
		index[name] = {"offset": blob.size(), "size": qoa.size(), "frames": raw.size() / 2}
		blob.append_array(qoa)
	if not problems.is_empty():
		_fail("effect bank not written, fix these cues first: " + "; ".join(problems))
		return
	_write("sfx.bin", blob)
	_write_json("sfx_index.json", {"rate": SFX_RATE, "codec": "qoa", "cues": index})
	print("sfx.bin %.2f MB, %d cues" % [blob.size() / 1e6, index.size()])


## Mono 16-bit samples at SFX_RATE as QOA, by way of a WAV Godot compresses.
func _qoa(raw: PackedByteArray) -> PackedByteArray:
	var head := PackedByteArray()
	head.resize(44)
	head.encode_u32(0, 0x46464952)
	head.encode_u32(4, 36 + raw.size())
	head.encode_u32(8, 0x45564157)
	head.encode_u32(12, 0x20746D66)
	head.encode_u32(16, 16)
	head.encode_u16(20, 1)
	head.encode_u16(22, 1)
	head.encode_u32(24, SFX_RATE)
	head.encode_u32(28, SFX_RATE * 2)
	head.encode_u16(32, 2)
	head.encode_u16(34, 16)
	head.encode_u32(36, 0x61746164)
	head.encode_u32(40, raw.size())
	head.append_array(raw)
	var stream := AudioStreamWAV.load_from_buffer(head, {"compress/mode": 2})
	if stream == null or stream.format != AudioStreamWAV.FORMAT_QOA:
		return PackedByteArray()
	return stream.data


func _music() -> void:
	var home := {}
	for file_name: String in MUSIC_FILES:
		for track: String in MUSIC_FILES[file_name]:
			home[track] = file_name
	var index := {}
	var blobs := {}
	for file in _sorted_files("godot/assets/music", "ogg"):
		var data := FileAccess.get_file_as_bytes(
			repo.path_join("godot/assets/music").path_join(file)
		)
		if data.slice(0, 4).get_string_from_ascii() != "OggS":
			_fail(file + " is not Ogg Vorbis")
			continue
		var track := file.get_basename()
		var file_name: String = home.get(track, "music")
		if not blobs.has(file_name):
			blobs[file_name] = PackedByteArray()
		var blob: PackedByteArray = blobs[file_name]
		index[track] = {"file": file_name + ".bin", "offset": blob.size(), "length": data.size()}
		blob.append_array(data)
		blobs[file_name] = blob
	for track: String in home.keys() + REQUIRED_MUSIC:
		if index.has(track):
			continue
		if track in AssetsLib.PENDING_MUSIC:
			# Not made yet (assets.gd PENDING_MUSIC): its chapter's file is written
			# all the same, so the browser packs and their loader find it.
			print("music pending: " + track)
			if not blobs.has(home[track]):
				blobs[home[track]] = PackedByteArray()
		else:
			_fail("music missing: " + track)
	for file_name: String in blobs:
		_write(file_name + ".bin", blobs[file_name])
	_write_json("music_index.json", index)
	_write_json(
		"music_ends.json",
		JSON.parse_string(
			FileAccess.get_file_as_string(repo.path_join("godot/assets/music/playback_ends.json"))
		)
	)
	print("music: %d tracks in %d files" % [index.size(), blobs.size()])


func _skies() -> void:
	var index := {}
	var blob := PackedByteArray()
	for name: String in SKIES:
		var image := _image(repo.path_join("assets/tiles/%s.png" % name), Image.FORMAT_RGB8)
		if image == null:
			_fail("missing sky " + name)
			continue
		index[name] = {"offset": blob.size(), "w": image.get_width(), "h": image.get_height()}
		blob.append_array(image.get_data())
	_write("sky.bin", AssetsLib.pack_whole(blob))
	_write_json("sky_index.json", index)
	print("sky.bin %.2f MB, %d skies" % [blob.size() / 1e6, index.size()])
