## Cut the first-person cels for the thirteen weapons that are not
## photographed plates, into assets/art.
##
##   godot --headless --path godot --script res://tools/art/build_weapon_views.gd \
##       [-- only=rifle,tnt] [no-render] [out=<dir>]
##
## The crowbar, revolver and shotgun are photographs with the hands in them.
## Blender (scripts/blender/weapon_views.py, run in Blender's own Python)
## renders every other weapon through the camera of one of those plates into
## _preview/weapon_raw, so here the plate's own hand is laid over the weapon at
## the plate's own size and place, and the result goes through the layout the
## plate itself goes through (LAYOUT). A weapon held like the revolver
## therefore shows the revolver's hand where the revolver shows it. The muzzle
## points of the pistol and long guns go to assets/art/weapon_anchors.json.
## BLENDER_PATH overrides where Blender is; no-render reuses the last renders;
## out= writes the cels somewhere else and leaves the anchors alone. Then run
## tools/pack_assets.gd.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")
const Enemies := preload("res://tools/art/build_enemy_actors.gd")
const CEL := Vector2i(320, 174)
## The finished cel keeps its top 120 rows (the game's view of a gun).
const KEEP_ROWS := 120
const PLATE_AT := Vector2i(640, 448)
## Laid out at this many times the cel's size, then shrunk.
const SUPER := 3
## The hand in each plate, as an outline on the plate.
const HANDS := {
	"pistol":
	[
		"revolver",
		[
			[228, 308],
			[246, 268],
			[272, 246],
			[302, 240],
			[340, 246],
			[368, 206],
			[396, 188],
			[430, 195],
			[456, 216],
			[482, 250],
			[520, 290],
			[560, 316],
			[600, 336],
			[640, 346],
			[640, 448],
			[300, 448],
			[286, 420],
			[280, 386],
			[256, 350],
			[236, 336]
		]
	],
	"bar":
	[
		"crowbar",
		[
			[322, 268],
			[340, 236],
			[366, 216],
			[400, 210],
			[430, 226],
			[456, 250],
			[480, 280],
			[500, 320],
			[540, 360],
			[590, 376],
			[640, 400],
			[640, 432],
			[432, 432],
			[400, 400],
			[370, 370],
			[346, 340],
			[324, 302]
		]
	],
	"long":
	[
		"shotgun",
		[
			[42, 160],
			[55, 136],
			[75, 126],
			[95, 136],
			[110, 160],
			[125, 186],
			[140, 216],
			[160, 250],
			[184, 290],
			[200, 330],
			[190, 370],
			[176, 400],
			[166, 448],
			[0, 448],
			[0, 380],
			[20, 330],
			[38, 270],
			[40, 210]
		]
	],
}
## How each plate is seated in the 320x174 layout: where its corner goes, its
## scale, its turn (degrees clockwise) about a point, then the window (zoom,
## left, top) the finished cel shows.
const LAYOUT := {
	"pistol": [Vector2(144, 101), 80 / 640.0, 25.0, Vector2(201, 147), Vector3(1.70, 72.4, 57.4)],
	"long": [Vector2(155, 106), 101 / 640.0, 12.0, Vector2(235, 161), Vector3(1.75, 84.9, 67.5)],
	"bar": [Vector2(96, 30), 164 / 640.0, 0.0, Vector2.ZERO, Vector3(1.0, 0, 0)],
	"carry": [Vector2(62, 24), .306, 0.0, Vector2.ZERO, Vector3(1.0, 0, 0)],
	"ball": [Vector2(104, 22), .306, 0.0, Vector2.ZERO, Vector3(1.0, 0, 0)],
}
## Pose -> [extra clockwise turn about the wrist, shift] in layout pixels
## (CARRY: and whether the weapon shows).
const GUN := {
	"idle": [0, Vector2(0, 0)],
	"kick": [12, Vector2(-2, -6)],
	"recover": [5, Vector2(-1, -2)],
	"open": [-12, Vector2(5, 9)],
	"eject": [-16, Vector2(6, 12)],
	"load": [-16, Vector2(6, 12)],
	"close": [-6, Vector2(3, 5)],
	"grind": [2, Vector2(-2, 1)],
	"grind_hot": [3, Vector2(-3, 0)]
}
const SWING := {
	"idle": [0, Vector2(0, 0)],
	"wind": [22, Vector2(10, -6)],
	"strike": [-30, Vector2(-24, 2)],
	"follow": [-46, Vector2(-30, 12)],
	"recover": [-18, Vector2(-10, 8)]
}
const THROW := {
	"idle": [0, Vector2(0, 0)],
	"kick": [-14, Vector2(-10, -8)],
	"throw": [-26, Vector2(-22, -20)],
	"lit": [0, Vector2(0, 0)],
	"lit_alt": [0, Vector2(0, 0)],
	"dry": [0, Vector2(0, 4)]
}
const CARRY := {
	"idle": [0, Vector2(0, 0), true],
	"kick": [0, Vector2(0, -12), false],
	"recover": [0, Vector2(0, 6), false],
	"open": [0, Vector2(0, 20), false],
	"eject": [0, Vector2(0, 28), false],
	"load": [0, Vector2(0, 24), true],
	"close": [0, Vector2(0, 9), true]
}
const WRIST := {
	"pistol": Vector2(219, 145),
	"long": Vector2(248, 158),
	"bar": Vector2(212, 116),
	"carry": Vector2(160, 174),
	"ball": Vector2(202, 174)
}
const GUN_POSES := ["idle", "kick", "recover", "open", "eject", "load", "close"]
## The 5v5 store's throwables: held and thrown as the dynamite is.
const THROWN := ["flash_jar", "smudge_pot", "shine_cocktail", "firecracker_can"]
## How big a throwable's own picture in flight is (pixels across).
const THROWN_SPRITE := 22
const POSES := {
	"slingblade": ["idle", "wind", "strike", "follow", "recover"],
	"flash_jar": ["idle", "kick", "throw", "dry"],
	"smudge_pot": ["idle", "kick", "throw", "dry"],
	"shine_cocktail": ["idle", "kick", "throw", "dry"],
	"firecracker_can": ["idle", "kick", "throw", "dry"],
	"tnt": ["idle", "kick", "throw", "lit", "lit_alt", "dry"],
	"ripsaw": ["idle", "kick", "open", "eject", "load", "close", "grind", "grind_hot"],
	"crossbow": ["idle", "kick", "open", "eject", "load", "close"]
}


func _init() -> void:
	var only := PackedStringArray()
	var render := true
	var art := Paint.repo("assets/art")
	var out := art
	for arg in OS.get_cmdline_user_args():
		var text := String(arg)
		if text.begins_with("only="):
			only = text.substr(5).split(",")
		elif text == "no-render":
			render = false
		elif text.begins_with("out="):
			out = text.substr(4)
	var raw := Paint.repo("_preview/weapon_raw")
	DirAccess.make_dir_recursive_absolute(raw)
	DirAccess.make_dir_recursive_absolute(out)
	if render:
		var code := OS.execute(
			Enemies.blender(),
			[
				"-b",
				"-P",
				Paint.repo("scripts/blender/weapon_views.py"),
				"--",
				raw,
				",".join(only) if not only.is_empty() else "all"
			]
		)
		if code != 0:
			push_error("Blender failed (exit %d); set BLENDER_PATH if it is elsewhere" % code)
			quit(1)
			return
	var views = JSON.parse_string(FileAccess.get_file_as_string(raw.path_join("views.json")))
	if not views is Dictionary:
		push_error("no %s/views.json: render first" % raw)
		quit(1)
		return
	var anchors_path := art.path_join("weapon_anchors.json")
	var anchors = JSON.parse_string(FileAccess.get_file_as_string(anchors_path))
	var count := 0
	for name: String in views:
		if not only.is_empty() and not only.has(name):
			continue
		var view: Dictionary = views[name]
		var made := cels(name, view, raw)
		var fronts: Dictionary = made[1]
		for pose: String in made[0]:
			var cel: Paint.Sheet = made[0][pose]
			Paint.digitize(kept_rows(cel)).save(out.path_join("gun_%s_%s.png" % [name, pose]))
			count += 1
		if THROWN.has(name):
			# Its own small picture, for while it flies and lies about.
			var raw_art := Paint.Sheet.load_png(raw.path_join(name + ".png"))
			var piece := raw_art.cropped(raw_art.bbox(0).grow(2))
			var k := float(THROWN_SPRITE) / maxf(piece.w, piece.h)
			piece = piece.resized(maxi(1, roundi(piece.w * k)), maxi(1, roundi(piece.h * k)))
			Paint.digitize(piece).save(out.path_join("fx_%s.png" % name))
		if String(view["rig"]) in ["pistol", "long"]:
			var points := {}
			for pose in ["idle", "kick", "recover"]:
				if fronts.has(pose):
					points[pose] = fronts[pose]
			anchors[name] = points
	if out == art:
		var file := FileAccess.open(anchors_path, FileAccess.WRITE)
		file.store_string(JSON.stringify(anchors, "", false))
	print("weapon views: %d cels in %s" % [count, out])
	quit()


static func turn_about(at: Vector2, degrees: float) -> Transform2D:
	var c := cos(deg_to_rad(degrees))
	var s := sin(deg_to_rad(degrees))
	return Transform2D(
		Vector2(c, s),
		Vector2(-s, c),
		Vector2(at.x - c * at.x + s * at.y, at.y - s * at.x - c * at.y)
	)


static func move(d: Vector2) -> Transform2D:
	return Transform2D(Vector2(1, 0), Vector2(0, 1), d)


static func grow(k: float) -> Transform2D:
	return Transform2D(Vector2(k, 0), Vector2(0, k), Vector2.ZERO)


## Taking a pixel of the 1280x896 render to the 320x174 cel.
static func to_cel(rig: String, turn: float, shift: Vector2) -> Transform2D:
	var layout: Array = LAYOUT[rig]
	var window: Vector3 = layout[4]
	var plate: Transform2D = move(layout[0]) * grow(layout[1]) * move(-Vector2(PLATE_AT))
	var seated := turn_about(layout[3], layout[2]) * plate
	var posed := move(shift) * turn_about(WRIST[rig], turn) * seated
	return grow(window.x) * move(-Vector2(window.y, window.z)) * posed


## The source seen through `matrix`: sampled at SUPER times the cel's size
## (bilinear, premultiplied), then shrunk to the cel.
func lay(source: Paint.Sheet, matrix: Transform2D) -> Paint.Sheet:
	var inverse := matrix.affine_inverse()
	var bw := CEL.x * SUPER
	var bh := CEL.y * SUPER
	var big := PackedFloat32Array()
	big.resize(bw * bh * 4)
	var sw := source.w
	var sh := source.h
	var d := source.data
	for y in bh:
		for x in bw:
			var at := inverse * Vector2((x + .5) / SUPER, (y + .5) / SUPER) - Vector2(.5, .5)
			var x0 := floori(at.x)
			var y0 := floori(at.y)
			if x0 < -1 or y0 < -1 or x0 >= sw or y0 >= sh:
				continue
			var fx := at.x - x0
			var fy := at.y - y0
			var o := (y * bw + x) * 4
			for corner in 4:
				var cx := x0 + (corner & 1)
				var cy := y0 + (corner >> 1)
				if cx < 0 or cy < 0 or cx >= sw or cy >= sh:
					continue
				var wgt := (fx if corner & 1 else 1.0 - fx) * (fy if corner >> 1 else 1.0 - fy)
				var s := (cy * sw + cx) * 4
				var a := d[s + 3] * wgt
				if a <= 0.0:
					continue
				big[o] += d[s] * a / 255.0
				big[o + 1] += d[s + 1] * a / 255.0
				big[o + 2] += d[s + 2] * a / 255.0
				big[o + 3] += a
	var small := Paint.Sheet.resample(big, bw, bh, 4, CEL.x, CEL.y)
	var cel := Paint.Sheet.new(CEL.x, CEL.y)
	for i in CEL.x * CEL.y:
		var a := clampf(small[i * 4 + 3], 0.0, 255.0)
		if a <= 0.0:
			continue
		for k in 3:
			cel.data[i * 4 + k] = clampi(roundi(small[i * 4 + k] / (a / 255.0)), 0, 255)
		cel.data[i * 4 + 3] = roundi(a)
	return cel


## Pull a clean render toward the plates: flatter colour, harder edges, grain.
## Worked on the box the weapon fills, not the whole render.
func weathered(image: Paint.Sheet, seed: int) -> Paint.Sheet:
	var box := image.bbox(0).grow(8).intersection(Rect2i(0, 0, image.w, image.h))
	var part := image.cropped(box)
	Paint.enhance(part, .80, 1.14, .94)
	Paint.unsharp(part, 2.0, 80, 2)
	var grain := Paint.noise(seed, part.w * part.h, 5.0)
	for i in part.w * part.h:
		for k in 3:
			part.data[i * 4 + k] = clampi(int(part.data[i * 4 + k] + grain[i]), 0, 255)
	var out := image.duplicate_sheet()
	for y in part.h:
		for x in part.w:
			var o := ((box.position.y + y) * image.w + box.position.x + x) * 4
			var t := (y * part.w + x) * 4
			for k in 3:
				out.data[o + k] = part.data[t + k]
	return out


func outline_of(rig: String) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p: Array in HANDS[rig][1]:
		pts.append(Vector2(p[0], p[1]))
	return pts


## The plate's hand on a transparent 1280x896 sheet, exactly where the plate has it.
func plate_hand(rig: String) -> Paint.Sheet:
	var source := Paint.Sheet.load_png(Paint.repo("source_art/%s_plate.png" % HANDS[rig][0]))
	var mask := Paint.Sheet.new(source.w, source.h)
	Paint.polygon(mask, outline_of(rig), Color(1, 1, 1, 1))
	var soft := Paint.blur(Paint.channel(mask, 3), source.w, source.h, 1.0)
	for i in source.w * source.h:
		source.data[i * 4 + 3] = mini(source.data[i * 4 + 3], clampi(roundi(soft[i]), 0, 255))
	var sheet := Paint.Sheet.new(1280, 896)
	sheet.composite(source, PLATE_AT.x, PLATE_AT.y)
	return sheet


## Two of the shotgun's cupping hands under something round.
func carry_hands(view: Dictionary) -> Paint.Sheet:
	var source := Paint.Sheet.load_png(Paint.repo("source_art/shotgun_plate.png"))
	var mask := Paint.Sheet.new(source.w, source.h)
	Paint.polygon(mask, outline_of("long"), Color(1, 1, 1, 1))
	for i in source.w * source.h:
		source.data[i * 4 + 3] = mini(source.data[i * 4 + 3], mask.data[i * 4 + 3])
	var cut := source.cropped(source.bbox(0))
	cut = cut.resized(roundi(cut.w * .9), roundi(cut.h * .9))
	var sheet := Paint.Sheet.new(1280, 896)
	var grip: Array = view["grip"]
	for pair in [[false, -150.0], [true, 150.0 - cut.w]]:
		var piece := cut.mirrored() if pair[0] else cut
		sheet.composite(piece, roundi(float(grip[0]) + pair[1]), roundi(float(grip[1]) - 6))
	return sheet


func spark(cel: Paint.Sheet, at: Vector2, size: int, hot: bool) -> void:
	var orange := Color8(255, 154, 48)
	for d in [
		Vector2(size, 0),
		Vector2(-size, 0),
		Vector2(0, size),
		Vector2(0, -size),
		Vector2(size * .6, size * .6),
		Vector2(-size * .6, -size * .6)
	]:
		Paint.line2(cel, at.x, at.y, at.x + d.x, at.y + d.y, orange)
	Paint.ellipse(
		cel,
		at.x - 1,
		at.y - 1,
		at.x + 1,
		at.y + 1,
		Color8(255, 242, 176) if hot else Color8(255, 208, 112)
	)


## Every pose of one weapon, and where its muzzle lands in each.
func cels(name: String, view: Dictionary, raw: String) -> Array:
	var rig := String(view["rig"])
	var seed := 0
	for c in name.to_utf8_buffer():
		seed += c
	var weapon := weathered(Paint.Sheet.load_png(raw.path_join(name + ".png")), seed)
	var hands := carry_hands(view) if rig == "carry" else plate_hand(rig)
	var held := Paint.Sheet.new(weapon.w, weapon.h)
	if rig == "carry":
		held.composite(hands)
		held.composite(weapon)
	else:
		held.composite(weapon)
		held.composite(hands)
	var table: Dictionary = (
		SWING
		if name == "slingblade"
		else THROW if name == "tnt" or THROWN.has(name) else CARRY if rig == "carry" else GUN
	)
	var out := {}
	var fronts := {}
	for pose: String in POSES.get(name, GUN_POSES):
		var entry: Array = table[pose]
		# The bowling ball is carried low on the right, the keg in front of the belly.
		var matrix := to_cel("ball" if name == "bowling_ball" else rig, entry[0], entry[1])
		var source := held
		if (
			(rig == "carry" and not entry[2])
			or ((name == "tnt" or THROWN.has(name)) and pose == "dry")
		):
			source = hands
		var cel := lay(source, matrix)
		var front: Vector2 = matrix * Vector2(view["front"][0], view["front"][1])
		if name == "tnt" and pose.begins_with("lit"):
			spark(cel, front, 5 if pose == "lit" else 3, pose == "lit")
		if pose.begins_with("grind"):
			for k in 4 if pose == "grind" else 7:
				spark(
					cel,
					Vector2(front.x + 4 + k * 5 % 19, front.y + 3 + (k * 7) % 11),
					3,
					pose == "grind_hot"
				)
		out[pose] = cel
		fronts[pose] = [snappedf(front.x, .1), snappedf(front.y, .1)]
	return [out, fronts]


## The game's view of a gun: its top rows, with a hard alpha edge.
func kept_rows(cel: Paint.Sheet) -> Paint.Sheet:
	var out := cel.cropped(Rect2i(0, 0, CEL.x, KEEP_ROWS))
	for i in out.w * out.h:
		out.data[i * 4 + 3] = 255 if out.data[i * 4 + 3] >= 112 else 0
	return out
