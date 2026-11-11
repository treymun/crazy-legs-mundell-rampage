## Build a level from its plan and write data/<id>.json, plus a picture of it
## from above to check the layout by eye.
##
##   godot --headless --path godot --script res://tools/levels/build_level.gd
##       -- hickston [map=<png>] [dry]
##
## The plan is tools/levels/<id>_plan.gd: a script with build(b) that lays the
## level out on a LevelBuilder (level_builder.gd) and returns the spawn
## [x, y, angle]. dry: check and draw it without writing the level. The map
## picture: floors in their tiles' colours, walls dark, enemies red, pickups
## yellow, doors blue (gold: locked, magenta: secret), stations white, empty
## ground (nothing within three cells) tinted red.
extends SceneTree

const Builder := preload("res://tools/levels/level_builder.gd")
const SCALE := 8


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: build_level.gd -- <level id> [map=<png>] [dry]")
		quit(1)
		return
	var level_id := String(args[0])
	var map_path := ""
	var dry := false
	for arg in args.slice(1):
		if String(arg).begins_with("map="):
			map_path = String(arg).substr(4)
		elif arg == "dry":
			dry = true
	var plan = load("res://tools/levels/%s_plan.gd" % level_id).new()
	var b = plan.make()
	var spawn: Array = plan.build(b)
	b.mount_signs()
	var problems: Array = b.problems(spawn)
	for p in problems:
		print("PROBLEM ", p)
	var level: Dictionary = b.finish(spawn)
	print(
		(
			"%s: %dx%d, %d walls, %d doors, %d enemies, %d pickups, %d props, %d boards"
			% [
				level_id,
				b.w,
				b.h,
				level["walls"].size(),
				b.doors.size(),
				b.enemies.size(),
				b.pickups.size(),
				b.props.size(),
				b.billboards.size()
			]
		)
	)
	# How much open ground has nothing within three cells of it.
	var dist: PackedInt32Array = b.emptiness()
	var open := 0
	var empty := 0
	for i in b.w * b.h:
		if int(b.solid[i]) < 0:
			open += 1
			if dist[i] >= 3:
				empty += 1
	print(
		"open ground %d cells, %d (%.1f%%) empty" % [open, empty, 100.0 * empty / maxf(1.0, open)]
	)
	if map_path != "":
		_picture(b, map_path)
	if not dry:
		LevelEdit.write(level_id, level)
		print("wrote ", LevelEdit.path_of(level_id))
	quit(1 if not problems.is_empty() else 0)


func _picture(b, path: String) -> void:
	var colours := {}
	var empty: PackedInt32Array = b.emptiness()
	var img := Image.create(b.w * SCALE, b.h * SCALE, false, Image.FORMAT_RGB8)
	for y in b.h:
		for x in b.w:
			var i: int = b.at(x, y)
			var c := Color(.1, .08, .07)
			if int(b.solid[i]) < 0:
				var f := int(b.floor_tile[i])
				if not colours.has(f):
					colours[f] = _tile_colour(b._name_of(f))
				c = colours[f]
				if float(b.roof[i]) > 0.0:
					c = c.darkened(.25)
				c = c.lightened(clampf(float(b.ground[i]), 0.0, .5) * .5)
				if float(b.ground[i]) < 0.0:
					c = c.darkened(.3)
				# Empty ground (nothing within three cells) shows up red.
				if empty[i] >= 3:
					c = c.lerp(Color(.9, .1, .1), .45)
			else:
				c = Color(.18, .15, .13) if float(b.wall_height[i]) < 1.6 else Color(.06, .05, .05)
			img.fill_rect(Rect2i(x * SCALE, y * SCALE, SCALE, SCALE), c)
	for f: Array in b.fixtures:
		img.fill_rect(
			Rect2i(
				int(float(f[0]) * SCALE),
				int(float(f[1]) * SCALE),
				maxi(1, int((float(f[2]) - float(f[0])) * SCALE)),
				maxi(1, int((float(f[3]) - float(f[1])) * SCALE))
			),
			Color(.35, .27, .2)
		)
	for d: Dictionary in b.doors:
		var c := Color(.3, .5, 1)
		if String(d["key"]) != "":
			c = Color(1, .8, .2)
		if bool(d["secret"]):
			c = Color(1, .2, 1)
		img.fill_rect(
			Rect2i(int(d["x"]) * SCALE + 2, int(d["y"]) * SCALE + 2, SCALE - 4, SCALE - 4), c
		)
	for p: Array in b.props:
		_dot(img, float(p[1]), float(p[2]), Color(.3, .7, .3), 2)
	for p: Array in b.pickups:
		_dot(img, float(p[1]), float(p[2]), Color(1, .9, .2), 2)
	for e: Dictionary in b.enemies:
		_dot(img, float(e["x"]), float(e["y"]), Color(1, .15, .1), 3)
	for s: Dictionary in b.stations:
		_dot(img, float(s["x"]), float(s["y"]), Color(1, 1, 1), 3)
	img.save_png(path)
	print("map ", path)


func _dot(img: Image, x: float, y: float, c: Color, r: int) -> void:
	img.fill_rect(Rect2i(int(x * SCALE) - r, int(y * SCALE) - r, r * 2, r * 2), c)


func _tile_colour(name: String) -> Color:
	var img := Image.load_from_file(_repo_path("assets/tiles/%s.png" % name))
	if img == null or img.is_empty():
		return Color(.4, .4, .4)
	img.resize(1, 1, Image.INTERPOLATE_BILINEAR)
	return img.get_pixel(0, 0)


func _repo_path(rel: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").path_join(rel).simplify_path()
