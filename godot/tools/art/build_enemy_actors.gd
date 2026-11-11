## Render the remade enemies in Blender and shrink them into assets/art.
##
##   godot --headless --path godot --script res://tools/art/build_enemy_actors.gd \
##       [-- kinds=billy,coot] [no-render] [out=<dir>]
##
## Blender (scripts/blender/enemy_actors.py, run in Blender's own Python) writes
## each cel four times oversized into _preview/enemies/raw; this shrinks them to
## game size, hardens the alpha edge the sprite renderer expects, darkens the
## silhouette by one pixel so a figure reads against any wall, grades it toward
## a worn photograph and commits it to the palette (paint.gd digitize). The
## BLENDER_PATH environment variable overrides where Blender is. no-render
## reuses the last renders. Then run tools/pack_assets.gd.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")
const SUPERSAMPLE := 4
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
	"lantern"
]


func _init() -> void:
	var kinds: Array = KINDS.duplicate()
	var render := true
	var out := Paint.repo("assets/art")
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text.begins_with("kinds="):
			kinds = Array(text.substr(6).split(","))
		elif text == "no-render":
			render = false
		elif text.begins_with("out="):
			out = text.substr(4)
	var raw := Paint.repo("_preview/enemies/raw")
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
			var cel := Paint.digitize(shrink(image, target, seed))
			cel.save(out.path_join(file))
			count += 1
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


## Down to game size with premultiplied alpha, a hard edge, a dark rim, and a
## grade toward a worn photograph (muzzle flashes and glows keep theirs).
func shrink(image: Paint.Sheet, size: Vector2i, seed: int) -> Paint.Sheet:
	# Colour weighed by alpha twice over, as the Python builder's own premultiply
	# followed by Pillow's did: a thin wing keeps its bright core over its dark
	# render edge, which is the look the cels were tuned with.
	var floats := PackedFloat32Array()
	floats.resize(image.w * image.h * 4)
	for i in image.w * image.h:
		var a := image.data[i * 4 + 3] / 255.0
		for k in 3:
			floats[i * 4 + k] = image.data[i * 4 + k] / 255.0 * a * a
		floats[i * 4 + 3] = a
	var small := Paint.Sheet.resample(floats, image.w, image.h, 4, size.x, size.y)
	var n := size.x * size.y
	var solid := PackedByteArray()
	solid.resize(n)
	for i in n:
		solid[i] = 1 if small[i * 4 + 3] >= .5 else 0
	var inner := Paint.shrink_mask(solid, size.x, size.y)
	var grain := Paint.noise(seed, n, .026)
	var out := Paint.Sheet.new(size.x, size.y)
	for i in n:
		if solid[i] == 0:
			continue
		var o := i * 4
		var alpha := maxf(small[o + 3], .02)
		var c := Vector3(small[o], small[o + 1], small[o + 2]) / (alpha * alpha)
		var bright := maxf(c.x, maxf(c.y, c.z)) > .93
		if not bright:
			var grey := (c.x + c.y + c.z) / 3.0
			c = Vector3.ONE * grey + (c - Vector3.ONE * grey) * .86
			c = (c - Vector3.ONE * .42) * 1.18 + Vector3.ONE * .52 + Vector3.ONE * grain[i]
			if inner[i] == 0:
				c *= .55
		out.data[o] = clampi(int(c.x * 255), 0, 255)
		out.data[o + 1] = clampi(int(c.y * 255), 0, 255)
		out.data[o + 2] = clampi(int(c.z * 255), 0, 255)
		out.data[o + 3] = 255
	return out
