## Render the remade enemies in Blender and shrink them into assets/art.
##
##   godot --headless --path godot --script res://tools/art/build_enemy_actors.gd \
##       [-- kinds=billy,coot] [no-render] [out=<dir>] [raw=<dir>]
##
## Blender (scripts/blender/enemy_actors.py, run in Blender's own Python) writes
## each cel four times oversized into _preview/enemies/raw; this shrinks them to
## game size, hardens the alpha edge the sprite renderer expects, darkens the
## silhouette by one pixel so a figure reads against any wall, grades it toward
## a worn photograph and commits it to the palette (paint.gd digitize). The
## BLENDER_PATH environment variable overrides where Blender is. no-render
## reuses the last renders (raw=<dir> reads and writes them elsewhere). Then run
## tools/pack_assets.gd.
##
## The bosses (BOSSES) come out of Blender with a wind-up cel (`<kind>_wind`) and
## a set of their living cels for each later phase of the fight, battle-damaged:
## `<kind>_p2_<cel>` (below half health) and `<kind>_p3_<cel>` (below a fifth;
## Maw's bare set is `maw_p3_bare_<cel>`), which src/boss_looks.gd picks. Their
## falls are drawn beaten. They are digitized with less grain (cleaner).
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")
const SUPERSAMPLE := 4
const BOSSES := [
	"boss", "jerry", "rudy", "foreman", "baron", "swamp_king", "derby_champ", "maw", "maw_bare"
]
const BOSS_GRAIN := .011
const KINDS := [
	"billy",
	"coot",
	"boss",
	"rudy",
	"clone",
	"alien",
	"barker",
	"millhand",
	"boilerback",
	"chalk_spitter",
	"yard_deputy",
	"bottle_tosser",
	"chain_hand",
	"valve_rat",
	"foreman",
	"baron",
	"jerry",
	"skeeter",
	"saucer",
	"crawler",
	"lantern",
	"noodler",
	"chum_tosser",
	"gator",
	"swamp_king",
	"pit_mechanic",
	"tire_roller",
	"nitro_huffer",
	"flagman",
	"derby_champ",
	"drone",
	"tin_guard",
	"probe",
	"maw",
	"maw_bare"
]


func _init() -> void:
	var kinds: Array = KINDS.duplicate()
	var render := true
	var out := Paint.repo("assets/art")
	var raw := Paint.repo("_preview/enemies/raw")
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text.begins_with("kinds="):
			kinds = Array(text.substr(6).split(","))
		elif text == "no-render":
			render = false
		elif text.begins_with("out="):
			out = text.substr(4)
		elif text.begins_with("raw="):
			raw = text.substr(4)
	DirAccess.make_dir_recursive_absolute(raw)
	DirAccess.make_dir_recursive_absolute(out)
	if render:
		var code := OS.execute(
			blender(),
			[
				"-b",
				"-P",
				Paint.repo("scripts/blender/enemy_actors.py"),
				"--",
				raw,
				",".join(kinds),
				"all",
				str(SUPERSAMPLE)
			]
		)
		if code != 0:
			push_error("Blender failed (exit %d); set BLENDER_PATH if it is elsewhere" % code)
			quit(1)
			return
	var meta = JSON.parse_string(FileAccess.get_file_as_string(raw.path_join("meta.json")))
	if not meta is Dictionary:
		push_error("no %s/meta.json: render first" % raw)
		quit(1)
		return
	var files := DirAccess.get_files_at(raw)
	files.sort()
	var count := 0
	for kind: String in kinds:
		var size: Array = meta[kind]["size"]
		for file in files:
			if not (file.begins_with(kind + "_") and file.ends_with(".png")):
				continue
			var stem := file.get_basename()
			var image := Paint.Sheet.load_png(raw.path_join(file))
			var target := Vector2i(int(size[0]), int(size[1]))
			if stem.ends_with("_down"):
				image = image.cropped(image.bbox(127))
				# Halves round to even, as Python's round() did for the cels in use.
				target = Vector2i(
					maxi(1, _round_even(image.w / float(SUPERSAMPLE))),
					maxi(1, _round_even(image.h / float(SUPERSAMPLE)))
				)
			var seed := 0
			for c in stem.to_utf8_buffer():
				seed += c
			var grain := BOSS_GRAIN if kind in BOSSES else .026
			var cel := Paint.digitize(Paint.photo_shrink(image, target, seed, grain))
			cel.save(out.path_join(file))
			count += 1
			if stem.contains("_p2_") or stem.contains("_p3_"):
				continue
			# The first build of the game still asks for the old three-cel walk by name.
			for pair in [["_w0", "_1"], ["_w2", "_-1"]]:
				if stem.ends_with(pair[0]):
					cel.save(out.path_join(stem.substr(0, stem.length() - 3) + pair[1] + ".png"))
	print("enemy actors: %d cels for %s" % [count, ",".join(kinds)])
	quit()


static func blender() -> String:
	var path := OS.get_environment("BLENDER_PATH")
	if path != "":
		return path
	return OS.get_environment("LOCALAPPDATA").path_join("Programs/Blender/blender.exe")


static func _round_even(v: float) -> int:
	var low := floorf(v)
	if absf(v - low - .5) < 1e-9:
		return int(low) if int(low) % 2 == 0 else int(low) + 1
	return roundi(v)
