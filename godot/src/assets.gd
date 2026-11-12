## Binary asset access for the port. Raw blobs live in res://assets_gen and are
## read with FileAccess so the port loads exactly the Python project's pixels.
class_name Assets
extends RefCounted

const TILE_W := 128
const TILE_H := 128
const TILE_BYTES := TILE_W * TILE_H * 3
## Cues made here instead of recorded: the crosshair's hit knock and the
## cowbell clank of a kill (game_world.gd struck()), far-off thunder rolling
## (features/weather.gd), a spent case tinking on the ground
## (features/debris.gd) and the thud of the tally's stamps (hud.gd).
const MADE_CUES := ["hit_tick", "kill_tick", "thunder", "casing_tink", "stamp_thud"]
## Enemies only one chapter has: their pictures live in that chapter's file,
## which the browser build fetches after it starts (tools/make_packs.gd puts
## it in the chapter's pack with its music) and main_flow.gd play() waits for.
const CHAPTER_KINDS := {
	"fair": ["barker", "bottle_tosser", "crawler", "rudy"],
	"sawmill": ["chain_hand", "foreman", "lantern", "millhand"],
	"quarry": ["baron", "boilerback", "chalk_spitter", "valve_rat"],
	"bayou": ["chum_tosser", "gator", "noodler", "swamp_king"],
	"speedway": ["derby_champ", "flagman", "nitro_huffer", "pit_mechanic", "tire_roller"],
	"mothership": ["drone", "maw", "probe", "tin_guard"],
}
const CHAPTER_ART := {
	"fair": "art_fair.bin",
	"sawmill": "art_mill.bin",
	"quarry": "art_quarry.bin",
	"bayou": "art_bayou.bin",
	"speedway": "art_speedway.bin",
	"mothership": "art_mothership.bin",
}
## Chapter music still to be made (the main session's audio pass; see
## docs/new_chapters/<id>_audio.md): tools/pack_assets.gd and verify_assets.gd
## note these as pending instead of failing (pack_assets still writes the
## chapter's music file, empty if none of it is made), and the game plays
## nothing for them till they come. Take a track off once it is in
## godot/assets/music. (The firing range plays Hickston's score.) Every
## chapter's tracks are made now.
const PENDING_MUSIC: Array = []

var tile_names: PackedStringArray = PackedStringArray()
var tile_index: Dictionary = {}
var tiles: PackedByteArray = PackedByteArray()

var sky_index: Dictionary = {}
var sky_blob: PackedByteArray = PackedByteArray()

var palette: PackedByteArray = PackedByteArray()
var grain: PackedByteArray = PackedByteArray()

## The last art index read, for code with no Assets at hand (BossLooks).
static var shared_index: Dictionary = {}
var art_index: Dictionary = {}
var _art_file: FileAccess
var _art_files := {}
var _art_cache: Dictionary = {}

var sfx_index: Dictionary = {}
var sfx_rate: int = 22050
## The bank holds QOA (tools/pack_assets.gd), or 16-bit samples in an older pack.
var sfx_qoa := false
var _sfx_file: FileAccess
var _sfx_cache: Dictionary = {}

var music_index: Dictionary = {}
var music_ends: Dictionary = {}
## Open music files by name. A browser build fetches the chapters' files after
## it starts (pack_loader.gd); until one arrives its tracks are simply missing.
var _music_files := {}
var _music_cache: Dictionary = {}


func _init() -> void:
	var idx := _json("res://data/index.json")
	tile_names = PackedStringArray()
	for name in idx.get("tiles", []):
		tile_names.append(String(name))
	tile_index = {}
	for i in tile_names.size():
		tile_index[tile_names[i]] = i
	tiles = unpack_whole(FileAccess.get_file_as_bytes("res://assets_gen/tiles.bin"))

	sky_index = _json("res://assets_gen/sky_index.json")
	sky_blob = unpack_whole(FileAccess.get_file_as_bytes("res://assets_gen/sky.bin"))

	palette = FileAccess.get_file_as_bytes("res://assets_gen/palette.bin")
	grain = FileAccess.get_file_as_bytes("res://assets_gen/grain.bin")

	art_index = _json("res://assets_gen/art_index.json")
	# Shared for BossLooks (a class name here would stop tools/pack_assets.gd
	# compiling in a fresh checkout, where it runs before the class cache exists).
	shared_index = art_index
	_art_file = FileAccess.open("res://assets_gen/art.bin", FileAccess.READ)

	var sfx := _json("res://assets_gen/sfx_index.json")
	sfx_rate = int(sfx.get("rate", 22050))
	sfx_qoa = String(sfx.get("codec", "")) == "qoa"
	sfx_index = sfx.get("cues", {})
	_sfx_file = FileAccess.open("res://assets_gen/sfx.bin", FileAccess.READ)

	music_index = _json("res://assets_gen/music_index.json")
	music_ends = _json("res://assets_gen/music_ends.json")


## A whole file deflated, behind "TZ01" and its size (tools/pack_assets.gd):
## the tiles and skies are half their size that way, and the browser download
## with them.
static func pack_whole(raw: PackedByteArray) -> PackedByteArray:
	var out := "TZ01".to_ascii_buffer()
	out.resize(8)
	out.encode_u32(4, raw.size())
	out.append_array(raw.compress(FileAccess.COMPRESSION_DEFLATE))
	return out


## The bytes pack_whole() packed, or `data` itself when it was never packed.
static func unpack_whole(data: PackedByteArray) -> PackedByteArray:
	if data.size() < 8 or data.slice(0, 4).get_string_from_ascii() != "TZ01":
		return data
	return data.slice(8).decompress(data.decode_u32(4), FileAccess.COMPRESSION_DEFLATE)


static func _json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("missing json " + path)
		return {}
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func tile(name: String) -> int:
	return int(tile_index.get(name, 0))


## Which chapter file a picture belongs in ("" for art.bin).
static func art_home(name: String) -> String:
	for level_id: String in CHAPTER_KINDS:
		for kind: String in CHAPTER_KINDS[level_id]:
			if name.begins_with(kind + "_"):
				return CHAPTER_ART[level_id]
	return ""


## True when every picture this level needs is here (a browser build may still
## be fetching a chapter's pack).
func chapter_ready(level_id: String) -> bool:
	var file_name := String(CHAPTER_ART.get(level_id, ""))
	return file_name == "" or FileAccess.file_exists("res://assets_gen/" + file_name)


## Returns {w, h, data:PackedByteArray} with RGBA8 pixels.
func art(name: String) -> Dictionary:
	var cached = _art_cache.get(name)
	if cached != null:
		return cached
	var info = art_index.get(name)
	var blank := {"w": 1, "h": 1, "data": PackedByteArray([0, 0, 0, 0])}
	if info == null:
		push_warning("missing art " + name)
		_art_cache[name] = blank
		return blank
	var source := _art_file
	if info.has("file"):
		var file_name := String(info["file"])
		source = _art_files.get(file_name)
		if source == null:
			source = FileAccess.open("res://assets_gen/" + file_name, FileAccess.READ)
			if source == null:
				# Not fetched yet: blank for now, and asked again next time.
				return blank
			_art_files[file_name] = source
	source.seek(int(info["offset"]))
	var w := int(info["w"])
	var h := int(info["h"])
	# Each image is stored deflated (tools/pack_assets.gd) and inflated on first use.
	var packed := source.get_buffer(int(info["size"]))
	var data := packed.decompress(w * h * 4, FileAccess.COMPRESSION_DEFLATE)
	var result := {"w": w, "h": h, "data": data}
	_art_cache[name] = result
	return result


func has_art(name: String) -> bool:
	return art_index.has(name)


## The name of picture `base` faded to `keep` (0 to 1, in eighths) of its
## strength, made from it the first time it is asked for: marks fading out
## (features/impacts.gd).
func faded_art(base: String, keep: float) -> String:
	var step := clampi(int(keep * 8.0 + .5), 0, 8)
	if step >= 8:
		return base
	var name := "%s~%d" % [base, step]
	if not _art_cache.has(name):
		var whole := art(base)
		var data: PackedByteArray = whole["data"].duplicate()
		for i in range(3, data.size(), 4):
			data[i] = data[i] * step / 8
		_art_cache[name] = {"w": whole["w"], "h": whole["h"], "data": data}
	return name


## Returns {w, h, data:RGB8} for one of the 512x116 panoramas.
func sky(name: String) -> Dictionary:
	var info = sky_index.get(name)
	if info == null:
		info = sky_index.get("sky")
		name = "sky"
	if info == null:
		return {"w": 1, "h": 1, "data": PackedByteArray([0, 0, 0])}
	var w := int(info["w"])
	var h := int(info["h"])
	var offset := int(info["offset"])
	return {"w": w, "h": h, "name": name, "data": sky_blob.slice(offset, offset + w * h * 3)}


func cue(name: String) -> AudioStreamWAV:
	var cached = _sfx_cache.get(name)
	if cached != null:
		return cached
	var info = sfx_index.get(name)
	if info == null:
		if name in MADE_CUES:
			_sfx_cache[name] = _made_cue(name)
			return _sfx_cache[name]
		return null
	_sfx_file.seek(int(info["offset"]))
	var frames := int(info["frames"])
	var stream := AudioStreamWAV.new()
	stream.mix_rate = sfx_rate
	stream.stereo = false
	if sfx_qoa:
		stream.format = AudioStreamWAV.FORMAT_QOA
		stream.data = _sfx_file.get_buffer(int(info["size"]))
	else:
		stream.format = AudioStreamWAV.FORMAT_16_BITS
		stream.data = _sfx_file.get_buffer(frames * 2)
	_sfx_cache[name] = stream
	return stream


func track(name: String) -> AudioStreamOggVorbis:
	var cached = _music_cache.get(name)
	if cached != null:
		return cached
	var info = music_index.get(name)
	if info == null:
		return null
	var file_name := String(info.get("file", "music.bin"))
	var handle: FileAccess = _music_files.get(file_name)
	if handle == null:
		var path := "res://assets_gen/" + file_name
		if not FileAccess.file_exists(path):
			return null
		handle = FileAccess.open(path, FileAccess.READ)
		if handle == null:
			return null
		_music_files[file_name] = handle
	handle.seek(int(info["offset"]))
	var raw := handle.get_buffer(int(info["length"]))
	var stream := AudioStreamOggVorbis.load_from_buffer(raw)
	if stream == null:
		push_warning("bad ogg " + name)
		return null
	_music_cache[name] = stream
	return stream


## Length in seconds of an Ogg track (used for the score cut-off points).
func track_length(name: String) -> float:
	var stream := track(name)
	return stream.get_length() if stream != null else 0.0


## The menu theme and the tally tune. They were short PCM jingles in a bank of
## their own; they are ordinary Ogg tracks now, so a full-length menu song costs
## megabytes rather than tens of megabytes.
func jingle(name: String) -> AudioStreamOggVorbis:
	return track(name)


func has_cue(name: String) -> bool:
	return sfx_index.has(name) or name in MADE_CUES


## A short knock (a damped tone and a click), a cowbell clank (two inharmonic
## square-ish tones), rolling thunder (low noise swelling and fading), a brass
## tink, or a rubber stamp's thud, as 16-bit samples.
func _made_cue(name: String) -> AudioStreamWAV:
	var length: float = (
		{"kill_tick": .20, "thunder": 3.2, "casing_tink": .16, "stamp_thud": .22}.get(name, .045)
	)
	var frames := int(sfx_rate * length)
	var raw := PackedByteArray()
	raw.resize(frames * 2)
	var low := 0.0
	var lower := 0.0
	for i in frames:
		var t := float(i) / sfx_rate
		var v := 0.0
		var hiss := fposmod(sin(i * 12.9898) * 43758.5453, 1.0) - .5
		match name:
			"kill_tick":
				var env := exp(-t * 22.0) * minf(1.0, t * 900.0)
				v = (
					(signf(sin(TAU * 545.0 * t)) * .55 + signf(sin(TAU * 815.0 * t)) * .45)
					* env
					* .42
				)
				v += sin(TAU * 140.0 * t) * exp(-t * 40.0) * .35
			"thunder":
				# Noise through two low passes: a crack, then a long rumble that rolls.
				low += (hiss - low) * .05
				lower += (low - lower) * .08
				var swell := minf(1.0, t * 3.0) * exp(-t * 1.1) * (.8 + .2 * sin(t * 5.3))
				v = lower * 9.0 * swell + low * 1.5 * exp(-t * 9.0)
			"casing_tink":
				v = (sin(TAU * 3150.0 * t) * .5 + sin(TAU * 4720.0 * t) * .3) * exp(-t * 38.0) * .5
			"stamp_thud":
				v = (
					sin(TAU * (90.0 - t * 120.0) * t) * exp(-t * 20.0) * .8
					+ hiss * exp(-t * 90.0) * .6
				)
			_:
				v = sin(TAU * 1380.0 * t) * exp(-t * 120.0) * .6
				v += hiss * exp(-t * 600.0) * .5
		raw.encode_s16(i * 2, clampi(int(v * 32767.0), -32768, 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sfx_rate
	stream.data = raw
	return stream


## Ambience, the jukebox, the fuse and the saw motor all loop in the reference.
## Cached streams are shared, so only looping-only cues ever get this call.
static func set_loop(stream: AudioStream, enabled: bool) -> void:
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if enabled:
			if wav.loop_mode != AudioStreamWAV.LOOP_FORWARD:
				wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
				wav.loop_begin = 0
				# Frames, whatever the encoding (a QOA bank's data is not samples).
				wav.loop_end = int(roundf(wav.get_length() * wav.mix_rate))
		elif wav.loop_mode != AudioStreamWAV.LOOP_DISABLED:
			wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	elif stream is AudioStreamOggVorbis:
		var ogg := stream as AudioStreamOggVorbis
		ogg.loop = enabled
