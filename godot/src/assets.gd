## Binary asset access for the port. Raw blobs live in res://assets_gen and are
## read with FileAccess so the port loads exactly the Python project's pixels.
class_name Assets
extends RefCounted

const TILE_W := 128
const TILE_H := 128
const TILE_BYTES := TILE_W * TILE_H * 3

var tile_names: PackedStringArray = PackedStringArray()
var tile_index: Dictionary = {}
var tiles: PackedByteArray = PackedByteArray()

var sky_index: Dictionary = {}
var sky_blob: PackedByteArray = PackedByteArray()

var palette: PackedByteArray = PackedByteArray()
var grain: PackedByteArray = PackedByteArray()

var art_index: Dictionary = {}
var _art_file: FileAccess
var _art_cache: Dictionary = {}

var sfx_index: Dictionary = {}
var sfx_rate: int = 22050
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
	tiles = FileAccess.get_file_as_bytes("res://assets_gen/tiles.bin")

	sky_index = _json("res://assets_gen/sky_index.json")
	sky_blob = FileAccess.get_file_as_bytes("res://assets_gen/sky.bin")

	palette = FileAccess.get_file_as_bytes("res://assets_gen/palette.bin")
	grain = FileAccess.get_file_as_bytes("res://assets_gen/grain.bin")

	art_index = _json("res://assets_gen/art_index.json")
	_art_file = FileAccess.open("res://assets_gen/art.bin", FileAccess.READ)

	var sfx := _json("res://assets_gen/sfx_index.json")
	sfx_rate = int(sfx.get("rate", 22050))
	sfx_index = sfx.get("cues", {})
	_sfx_file = FileAccess.open("res://assets_gen/sfx.bin", FileAccess.READ)

	music_index = _json("res://assets_gen/music_index.json")
	music_ends = _json("res://assets_gen/music_ends.json")


static func _json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("missing json " + path)
		return {}
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func tile(name: String) -> int:
	return int(tile_index.get(name, 0))


## Returns {w, h, data:PackedByteArray} with RGBA8 pixels.
func art(name: String) -> Dictionary:
	var cached = _art_cache.get(name)
	if cached != null:
		return cached
	var info = art_index.get(name)
	if info == null:
		push_warning("missing art " + name)
		var blank := {"w": 1, "h": 1, "data": PackedByteArray([0, 0, 0, 0])}
		_art_cache[name] = blank
		return blank
	_art_file.seek(int(info["offset"]))
	var w := int(info["w"])
	var h := int(info["h"])
	# Each image is stored deflated (tools/pack_assets.gd) and inflated on first use.
	var packed := _art_file.get_buffer(int(info["size"]))
	var data := packed.decompress(w * h * 4, FileAccess.COMPRESSION_DEFLATE)
	var result := {"w": w, "h": h, "data": data}
	_art_cache[name] = result
	return result


func has_art(name: String) -> bool:
	return art_index.has(name)


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
		return null
	_sfx_file.seek(int(info["offset"]))
	var frames := int(info["frames"])
	var raw := _sfx_file.get_buffer(frames * 2)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sfx_rate
	stream.stereo = false
	stream.data = raw
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
	return sfx_index.has(name)


## Ambience, the jukebox, the fuse and the saw motor all loop in the reference.
## Cached streams are shared, so only looping-only cues ever get this call.
static func set_loop(stream: AudioStream, enabled: bool) -> void:
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if enabled:
			if wav.loop_mode != AudioStreamWAV.LOOP_FORWARD:
				wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
				wav.loop_begin = 0
				wav.loop_end = int(wav.data.size() / (4 if wav.stereo else 2))
		elif wav.loop_mode != AudioStreamWAV.LOOP_DISABLED:
			wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	elif stream is AudioStreamOggVorbis:
		var ogg := stream as AudioStreamOggVorbis
		ogg.loop = enabled
