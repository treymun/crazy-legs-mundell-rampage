## A contact sheet of enemy cels straight from the art folders, scaled up with
## hard pixels on a dusk grey: one row a kind, each folder's cels side by side
## (an old build's art against the new), for looking at the drawing itself.
##
##   godot --headless --path godot --script res://tools/art/enemy_sheet.gd \
##       -- out=<png> dirs=<old>,<new> [kinds=billy,coot] [cels=0,wind,hurt_0] [scale=2]
##
## A cel missing from a folder leaves its square empty; `hurt_<cel>` and
## `wind` fall back to the plain cel only when `fallback` is given.
extends SceneTree

const KINDS := [
	"clone",
	"billy",
	"big_billy",
	"coot",
	"drunk_coot",
	"alien",
	"yard_deputy",
	"shield_deputy",
	"skeeter",
	"saucer",
	"barker",
	"bottle_tosser",
	"crawler",
	"millhand",
	"chain_hand",
	"lantern",
	"boilerback",
	"chalk_spitter",
	"valve_rat",
	"noodler",
	"chum_tosser",
	"gator",
	"pit_mechanic",
	"tire_roller",
	"nitro_huffer",
	"flagman",
	"drone",
	"tin_guard",
	"probe",
	"chicken",
	"pig",
	"bessie"
]
const CELS := ["0", "side_w1", "wind", "aim", "fire", "hurt_0", "hurt_side_w1", "pain", "down"]
const BACK := Color8(58, 52, 50)


func _init() -> void:
	var out := "user://enemy_sheet.png"
	var dirs: Array = []
	var kinds: Array = KINDS.duplicate()
	var cels: Array = CELS.duplicate()
	var scale := 2
	var fallback := false
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text.begins_with("out="):
			out = text.substr(4)
		elif text.begins_with("dirs="):
			dirs = Array(text.substr(5).split(","))
		elif text.begins_with("kinds="):
			kinds = Array(text.substr(6).split(","))
		elif text.begins_with("cels="):
			cels = Array(text.substr(5).split(","))
		elif text.begins_with("scale="):
			scale = int(text.substr(6))
		elif text == "fallback":
			fallback = true
	# Each row as tall as its tallest cel, each column as wide as its widest.
	var rows: Array = []
	var widths := PackedInt32Array()
	widths.resize(dirs.size() * cels.size())
	for kind: String in kinds:
		var row := []
		var tall := 0
		for d in dirs.size():
			for c in cels.size():
				var image := _cel(String(dirs[d]), kind, String(cels[c]), fallback)
				row.append(image)
				if image != null:
					tall = maxi(tall, image.get_height() * scale)
					var i := d * cels.size() + c
					widths[i] = maxi(widths[i], image.get_width() * scale)
		if tall > 0:
			rows.append([row, tall])
	var total_w := 0
	for w in widths:
		total_w += w + 4
	total_w += 12 * (dirs.size() - 1)
	var total_h := 0
	for r: Array in rows:
		total_h += int(r[1]) + 4
	var sheet := Image.create_empty(maxi(1, total_w), maxi(1, total_h), false, Image.FORMAT_RGBA8)
	sheet.fill(BACK)
	var y := 0
	for r: Array in rows:
		var x := 0
		for i in widths.size():
			if i > 0 and i % cels.size() == 0:
				sheet.fill_rect(Rect2i(x + 4, y, 3, int(r[1]) + 4), Color8(190, 140, 60))
				x += 12
			var image: Image = r[0][i]
			if image != null:
				var big := image.duplicate()
				big.resize(
					image.get_width() * scale, image.get_height() * scale, Image.INTERPOLATE_NEAREST
				)
				var at := Vector2i(
					x + (widths[i] - big.get_width()) / 2, y + int(r[1]) - big.get_height()
				)
				sheet.blend_rect(big, Rect2i(Vector2i.ZERO, big.get_size()), at)
			x += widths[i] + 4
		y += int(r[1]) + 4
	sheet.save_png(out)
	print("ENEMY SHEET: %d kinds x %d cels -> %s" % [rows.size(), cels.size(), out])
	quit()


func _cel(dir: String, kind: String, cel: String, fallback: bool) -> Image:
	for name in _names(kind, cel, fallback):
		var path := dir.path_join(name + ".png")
		if FileAccess.file_exists(path):
			var image := Image.load_from_file(path)
			image.convert(Image.FORMAT_RGBA8)
			return image
	return null


func _names(kind: String, cel: String, fallback: bool) -> Array:
	var names := ["%s_%s" % [kind, cel]]
	if fallback:
		if cel.begins_with("hurt_"):
			names.append("%s_%s" % [kind, cel.substr(5)])
		if cel == "wind":
			names.append(kind + "_aim")
		if cel.begins_with("side_w"):
			names.append(kind + "_" + ["-1", "0", "1", "0"][int(cel.substr(6))])
		if cel == "hurt_side_w1":
			names.append(kind + "_1")
	return names
