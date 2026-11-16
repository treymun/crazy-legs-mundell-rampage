## The browser build's split into a first download (index.pck: the title and
## Hickston) and one pack per chapter (tools/make_packs.gd), and the lighter
## copy the browser and phone builds read (tools/pack_lite.gd). Holds that:
## - the name rule (Assets.chapter_of) puts things where it should;
## - every picture and cue is in the file its home says, and the files exist;
## - each level's data names nothing from another chapter's pack, and neither
##   does its play: each level is played for PLAY_SECONDS by the bot with
##   Assets.recording on, and every picture and cue asked for must be in the
##   first download or the level's own chapter's pack;
## - the export presets leave exactly the chapters' models out of the browser
##   builds' first download (`fix` writes the lists), the desktop copy of the
##   art and music out of the browser and phone builds, the lighter copy out of
##   the desktop builds;
## - the lighter copy, when built, has every picture (each one whole) and track;
## - the first download's packed files and each chapter's pack stay under
##   their budgets;
## - with build=<web build dir> (after make_packs): index.pck holds none of a
##   chapter's files and each pack in packs.json holds exactly its own.
##
##   godot --headless --path godot --script res://tools/pack_check.gd
##       [-- fix] [lite] [build=<dir>] [quick]
##
## lite: the lighter copy must be there (CI's browser job builds it first).
## quick: no play. Prints the sizes and PACK CHECK OK, or what failed.
extends SceneTree

const Pilot := preload("res://tools/bot_pilot.gd")
const Packs := preload("res://tools/make_packs.gd")
const PropHomes := preload("res://tools/prop_homes.gd")

const PLAY_SECONDS := 12.0
const STEP := 1.0 / 60.0
## The first download's packed files (assets_gen, the models, the levels;
## not the engine, its scripts or the browser's own files), and each chapter's
## pack, in MB. On 2026-11-16: 70.4 with the lighter copy (75.4 with the
## desktop's, which the checks' runners measure), the biggest pack 16.3.
const FIRST_BUDGET_MB := 80.0
const PACK_BUDGET_MB := 20.0
const WEB_PRESETS := ["Web", "Web Lite"]
const LIGHT_PRESETS := ["Web", "Web Lite", "Android"]
const DESKTOP_PRESETS := ["Windows Desktop", "Linux Server"]
## The desktop copy, which the browser and phone builds leave out.
const DESKTOP_COPY := [
	"assets_gen/art*.bin",
	"assets_gen/art_index.json",
	"assets_gen/music*.bin",
	"assets_gen/music_index.json",
]
## What a browser build's first download leaves to the packs, besides models.
const PACKED_LATER := [
	"assets_gen/sfx_*.bin", "assets_gen/lite/art_*.bin", "assets_gen/lite/music_*.bin"
]

var _failed: Array[String] = []
var _assets: Assets
var _props: Dictionary


func _init() -> void:
	_run.call_deferred()


func _fail(message: String) -> void:
	_failed.append(message)
	print("  FAIL ", message)


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	_props = PropHomes.homes()
	_assets = Assets.new()
	_rule()
	_homes()
	_levels()
	if not args.has("quick"):
		_play()
	_presets(args.has("fix"))
	_lite(args.has("lite"))
	_sizes()
	for arg: String in args:
		if arg.begins_with("build="):
			_build(arg.substr(6))
	if _failed.is_empty():
		print("PACK CHECK OK")
	else:
		print("PACK CHECK FAILED: %d" % _failed.size())
	quit(0 if _failed.is_empty() else 1)


## The name rule on names it must and must not take.
func _rule() -> void:
	var cases := {
		"gator": "bayou",
		"gator_snap": "bayou",
		"actor3d_maw_bare_p2": "mothership",
		"maw_bare": "mothership",
		"boss_swamp_king_intro": "bayou",
		"actor3d_derby_champ": "speedway",
		"range_plate_gator": "",
		"mesh_gator_hide": "",
		"fx_rudy_horn": "",
		"boss": "",
		"boss_0": "",
		"actor3d_boss_p2": "",
		"billy_0": "",
		"jerry_taunt": "",
	}
	for name: String in cases:
		if Assets.chapter_of(name) != cases[name]:
			_fail("chapter_of(%s) is '%s', not '%s'" % [name, Assets.chapter_of(name), cases[name]])


## The art file a picture belongs in by the rules ("" art.bin).
func _art_home(name: String) -> String:
	var home := Assets.art_home(name)
	if home == "" and name.begins_with("mesh_") and _props.has(name.substr(5)):
		home = "art_%s.bin" % _props[name.substr(5)]
	return home


func _homes() -> void:
	var dir := Assets.tier()
	for name: String in _assets.art_index:
		var info: Dictionary = _assets.art_index[name]
		var home := str(info.get("file", ""))
		if home != _art_home(name):
			_fail("picture %s is in '%s', its home is '%s'" % [name, home, _art_home(name)])
	for file_name: String in Assets.CHAPTER_ART.values():
		if not FileAccess.file_exists(dir + file_name):
			_fail("no " + dir + file_name)
	for cue: String in _assets.sfx_index:
		var info: Dictionary = _assets.sfx_index[cue]
		var chapter := Assets.chapter_of(cue)
		var want := "" if chapter == "" else "sfx_%s.bin" % Assets.stem_of(chapter)
		if str(info.get("file", "")) != want:
			_fail("cue %s is in '%s', its home is '%s'" % [cue, info.get("file", ""), want])
		elif want != "" and _assets.cue(cue) == null:
			_fail("cue %s does not open from %s" % [cue, want])


## The levels, by id, and the stem of the chapter pack each one waits for.
func _level_ids() -> Array[String]:
	var ids: Array[String] = []
	for file in DirAccess.get_files_at("res://data"):
		if file.ends_with(".json") and file != "index.json":
			ids.append(file.get_basename())
	ids.sort()
	return ids


## The chapter whose pack holds asset `name` ("" the first download, "?"
## not an asset).
func _home_of(name: String) -> String:
	if _assets.art_index.has(name):
		var info: Dictionary = _assets.art_index[name]
		return str(info.get("file", "")).trim_prefix("art_").trim_suffix(".bin")
	if _assets.sfx_index.has(name):
		var cue: Dictionary = _assets.sfx_index[name]
		return str(cue.get("file", "")).trim_prefix("sfx_").trim_suffix(".bin")
	for level_id: String in Assets.CHAPTER_KINDS:
		if name in Assets.CHAPTER_KINDS[level_id]:
			return Assets.stem_of(level_id)
	return "?"


## Every name a level's data holds is in the first download or its pack.
func _levels() -> void:
	var word := RegEx.create_from_string('"([a-z][a-z0-9_]*)"')
	for id: String in _level_ids():
		var own := Assets.stem_of(id)
		var text := FileAccess.get_file_as_string("res://data/%s.json" % id)
		var seen := {}
		for found in word.search_all(text):
			seen[found.get_string(1)] = true
		for name: String in seen:
			var home := _home_of(name)
			if home != "?" and home != "" and home != own:
				_fail("%s names %s, which comes with the %s pack" % [id, name, home])


## Plays each level and holds what it asked for to its packs.
func _play() -> void:
	var hud := HUD.new(_assets)
	var sound := Sound.new(_assets)
	root.add_child(sound)
	var played := 0
	for id: String in _level_ids():
		if id == "range":
			# The range's chapter targets wait for their packs themselves
			# (features/firing_range.gd), and on a desktop every pack is here.
			continue
		var own := Assets.stem_of(id)
		Assets.asked = {}
		Assets.recording = true
		var game := Game.new(_assets, hud, sound, id)
		game.configure({"hints": 0, "difficulty": 1})
		game.cheats.god = true
		var pilot := Pilot.new()
		pilot.whole = true
		while game.clock < PLAY_SECONDS and not game.won:
			game.tick(STEP, pilot.steer(game))
			pilot.moved(game)
		Assets.recording = false
		var wrong := PackedStringArray()
		for name: String in Assets.asked:
			var home := _home_of(name)
			if home != "?" and home != "" and home != own:
				wrong.append("%s (%s)" % [name, home])
		if not wrong.is_empty():
			_fail("%s asked for %s" % [id, ", ".join(wrong)])
		played += 1
		print("  played %-15s %4d pictures and cues asked for" % [id, Assets.asked.size()])
	sound.queue_free()
	print("  %d levels played %.0f s each" % [played, PLAY_SECONDS])


## The chapters' models the browser builds leave out of their first download.
func _chapter_models() -> PackedStringArray:
	var out := PackedStringArray()
	for level_id: String in Packs.ORDER:
		for model in Packs.chapter_models(level_id, _props):
			out.append(model.trim_prefix("res://"))
	out.sort()
	return out


func _presets(fix: bool) -> void:
	var path := "res://export_presets.cfg"
	var lines := FileAccess.get_file_as_string(path).split("\n")
	var models := _chapter_models()
	var preset := ""
	var changed := false
	for i in lines.size():
		var line := lines[i].strip_edges()
		if line.begins_with("name="):
			preset = line.substr(5).trim_prefix('"').trim_suffix('"')
		if not line.begins_with("exclude_filter="):
			continue
		var value := line.substr(15).trim_prefix('"').trim_suffix('"')
		var parts := PackedStringArray()
		var listed := PackedStringArray()
		for part in value.split(","):
			var item := part.strip_edges()
			if item.begins_with("assets3d/"):
				listed.append(item)
			elif item != "":
				parts.append(item)
		listed.sort()
		if preset in WEB_PRESETS:
			for item: String in PACKED_LATER:
				if not item in parts:
					_fail("%s does not leave %s to the packs" % [preset, item])
			if listed != models:
				if fix:
					parts.append_array(models)
					var ending := "\r" if lines[i].ends_with("\r") else ""
					lines[i] = 'exclude_filter="%s"%s' % [", ".join(parts), ending]
					changed = true
					print("  wrote %s's %d chapter models" % [preset, models.size()])
				else:
					_fail(
						(
							"%s's exclude_filter lists %d models, not the chapters' %d (run with fix)"
							% [preset, listed.size(), models.size()]
						)
					)
		elif not listed.is_empty():
			_fail("%s leaves out models: %s" % [preset, ", ".join(listed)])
		if preset in LIGHT_PRESETS:
			for item: String in DESKTOP_COPY:
				if not item in parts:
					_fail("%s does not leave out %s" % [preset, item])
		if preset in DESKTOP_PRESETS and not "assets_gen/lite/*" in parts:
			_fail("%s does not leave out assets_gen/lite/*" % preset)
	if changed:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string("\n".join(lines))
		file.close()


## The lighter copy: the same pictures and tracks, each picture whole.
func _lite(required: bool) -> void:
	var lite_dir := Assets.LITE_DIR
	if not FileAccess.file_exists(lite_dir + "art_index.json"):
		if required:
			_fail("no lighter copy in %s (run tools/pack_lite.gd)" % lite_dir)
		else:
			print("  lighter copy not built here: not checked (tools/pack_lite.gd)")
		return
	var full_art := _json(Assets.FULL_DIR + "art_index.json")
	var lite_art := _json(lite_dir + "art_index.json")
	if full_art.keys().size() != lite_art.keys().size():
		_fail("the lighter art has %d pictures, the full %d" % [lite_art.size(), full_art.size()])
	var files := {}
	var halved := 0
	for name: String in full_art:
		var full: Dictionary = full_art[name]
		var lite: Variant = lite_art.get(name)
		if not lite is Dictionary:
			_fail("picture %s is not in the lighter copy" % name)
			continue
		var small: Dictionary = lite
		if str(small.get("file", "")) != str(full.get("file", "")):
			_fail("picture %s is in another file in the lighter copy" % name)
		var file_name := str(small.get("file", "art.bin"))
		if not files.has(file_name):
			files[file_name] = FileAccess.get_file_as_bytes(lite_dir + file_name)
		var blob: PackedByteArray = files[file_name]
		var w: int = small["w"]
		var h: int = small["h"]
		var at: int = small["offset"]
		var packed := blob.slice(at, at + int(small["size"]))
		if packed.decompress(w * h * 4, FileAccess.COMPRESSION_DEFLATE).size() != w * h * 4:
			_fail("picture %s does not inflate in the lighter copy" % name)
		if w != int(full["w"]):
			halved += 1
			if not (name.begins_with("actor3d_") or name.begins_with("mesh_")):
				_fail("picture %s is not a model texture but was made smaller" % name)
	var full_music := _json(Assets.FULL_DIR + "music_index.json")
	var lite_music := _json(lite_dir + "music_index.json")
	for track: String in full_music:
		if not lite_music.has(track):
			_fail("track %s is not in the lighter copy" % track)
			continue
		var entry: Dictionary = lite_music[track]
		var data := FileAccess.get_file_as_bytes(lite_dir + str(entry["file"]))
		var raw := data.slice(int(entry["offset"]), int(entry["offset"]) + int(entry["length"]))
		var stream := AudioStreamOggVorbis.load_from_buffer(raw)
		var full_entry: Dictionary = full_music[track]
		var full_data := FileAccess.get_file_as_bytes(Assets.FULL_DIR + str(full_entry["file"]))
		var was := AudioStreamOggVorbis.load_from_buffer(
			full_data.slice(
				int(full_entry["offset"]), int(full_entry["offset"]) + int(full_entry["length"])
			)
		)
		if stream == null or absf(stream.get_length() - was.get_length()) > .01:
			_fail("track %s in the lighter copy is not the same length" % track)
	print(
		(
			"  lighter copy: %d pictures (%d made smaller), %d tracks"
			% [lite_art.size(), halved, lite_music.size()]
		)
	)


func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _size(path: String) -> int:
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		return 0
	var n := handle.get_length()
	handle.close()
	return n


## The first download's packed files and each pack, against the budgets.
func _sizes() -> void:
	var dir := Assets.LITE_DIR
	if not FileAccess.file_exists(dir + "art_index.json"):
		dir = Assets.FULL_DIR
	var first := 0
	for name: String in ["art.bin", "art_index.json", "music.bin", "music_index.json"]:
		first += _size(dir + name)
	for file in DirAccess.get_files_at(Assets.FULL_DIR):
		if not (file.begins_with("art") or file.begins_with("music") or file.begins_with("sfx_")):
			first += _size(Assets.FULL_DIR + file)
	for file in DirAccess.get_files_at("res://data"):
		if file.ends_with(".json"):
			first += _size("res://data/" + file)
	var later := {}
	for model in _chapter_models():
		later["res://" + model] = true
	for folder: String in ["res://assets3d/actors", "res://assets3d/props", "res://assets3d/cabs"]:
		for file in DirAccess.get_files_at(folder):
			if file.get_extension() == "glb" and not later.has(folder.path_join(file)):
				for part in Packs.imported_files(folder.path_join(file)):
					first += _size(part)
	print("  first download's packed files %.1f MB (budget %.0f)" % [first / 1e6, FIRST_BUDGET_MB])
	if first / 1e6 > FIRST_BUDGET_MB:
		_fail("the first download is %.1f MB, over %.0f" % [first / 1e6, FIRST_BUDGET_MB])
	for level_id: String in Packs.ORDER:
		var total := 0
		for part in Packs.pack_files(level_id):
			var path := part
			if dir == Assets.FULL_DIR:
				path = part.replace(Assets.LITE_DIR, Assets.FULL_DIR)
			total += _size(path)
		print("  %-20s %.1f MB" % [Packs.pack_name(level_id), total / 1e6])
		if total / 1e6 > PACK_BUDGET_MB:
			_fail(
				(
					"%s is %.1f MB, over %.0f"
					% [Packs.pack_name(level_id), total / 1e6, PACK_BUDGET_MB]
				)
			)


## The files in a pack (res:// paths without the res://) and their sizes.
static func pck_files(path: String) -> Dictionary:
	var out := {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_32() != 0x43504447:
		return out
	var version := f.get_32()
	f.get_32()
	f.get_32()
	f.get_32()
	f.get_32()
	f.get_64()
	if version >= 3:
		f.seek(f.get_64())
	else:
		for i in 16:
			f.get_32()
	var count := f.get_32()
	for i in count:
		var name := f.get_buffer(f.get_32()).get_string_from_utf8().trim_prefix("res://")
		f.get_64()
		var size := f.get_64()
		f.get_buffer(16)
		f.get_32()
		out[name] = size
	return out


## An exported browser build: the first download and the packs.
func _build(folder: String) -> void:
	var first := pck_files(folder.path_join("index.pck"))
	if first.is_empty():
		_fail("no index.pck in " + folder)
		return
	var manifest := _json(folder.path_join("packs.json"))
	var total := 0
	for level_id: String in Packs.ORDER:
		var pack := Packs.pack_name(level_id)
		if not manifest.has(pack):
			_fail("packs.json has no " + pack)
			continue
		var entry: Dictionary = manifest[pack]
		var held := pck_files(folder.path_join(str(entry["file"])))
		var want := {}
		for part in Packs.pack_files(level_id):
			want[part.trim_prefix("res://")] = true
		for name: String in want:
			if not held.has(name):
				_fail("%s does not hold %s" % [pack, name])
			if first.has(name):
				_fail("index.pck holds %s, which comes with %s" % [name, pack])
		want[Packs.uid_list(pack).trim_prefix("res://")] = true
		for name: String in held:
			if not want.has(name):
				_fail("%s holds %s, which is not its own" % [pack, name])
		total += _size(folder.path_join(str(entry["file"])))
	for name: String in [
		"assets_gen/lite/art.bin", "assets_gen/lite/music.bin", "assets_gen/sfx.bin"
	]:
		if not first.has(name):
			_fail("index.pck has no " + name)
	for name: String in ["assets_gen/art.bin", "assets_gen/music.bin"]:
		if first.has(name):
			_fail("index.pck holds the desktop's " + name)
	print(
		(
			"  build %s: index.pck %.1f MB, the packs %.1f MB"
			% [folder, _size(folder.path_join("index.pck")) / 1e6, total / 1e6]
		)
	)
