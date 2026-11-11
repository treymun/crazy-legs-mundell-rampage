## Draw the front end's supporting artwork into assets/art, at the game's
## own 320x200.
##
##   godot --headless --path godot --script res://tools/art/build_menu_art.gd [-- out=<dir>]
##
## The title screen keeps its backdrop and protagonist (title_backdrop.png,
## title_logo.png) and adds:
##   menu_board    weathered timber the menu is painted on
##   menu_sign     rusted tin header for the settings and other sub-screens
##   menu_sheet    the darkened yard in a timber frame those screens sit in
##   menu_glow     warm lamp light that falls on the board (flickers in game)
##   menu_wanted   the county wanted poster, nailed to the fence
##   menu_bessie   the MISSING notice for Bessie
##   menu_saucer   the thing in the sky
## Seeded, so a rerun gives the same files. Then run tools/pack_assets.gd.
## out= writes somewhere else instead (to compare).
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")


func _init() -> void:
	var art := Paint.repo("assets/art")
	var out := art
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
	DirAccess.make_dir_recursive_absolute(out)

	var board := timber(188, 112, 11, 23)
	Paint.outline(board, 0, 0, 187, 111, Color8(30, 20, 14))
	board.save(out.path_join("menu_board.png"))

	rust(296, 20, 3).save(out.path_join("menu_sign.png"))

	# Sub-screens: the same yard, pushed back and dimmed, inside a timber frame.
	var yard := Paint.Sheet.load_png(art.path_join("title_backdrop.png"))
	for k in 3:
		var soft := Paint.blur(Paint.channel(yard, k), yard.w, yard.h, 1.4)
		for i in yard.w * yard.h:
			yard.data[i * 4 + k] = int(clampf(soft[i], 0, 255) * .34)
	for i in yard.w * yard.h:
		yard.data[i * 4 + 3] = 255
	var frame := timber(320, 200, 21, 29)
	for y in 200:
		for x in 320:
			if x >= 7 and x <= 312 and y >= 7 and y <= 192:
				var o := (y * 320 + x) * 4
				for k in 4:
					frame.data[o + k] = yard.data[o + k]
	Paint.outline(frame, 7, 7, 312, 192, Color8(24, 16, 12))
	Paint.outline(frame, 8, 8, 311, 191, Color8(120, 86, 56))
	frame.save(out.path_join("menu_sheet.png"))

	glow(188, 120).save(out.path_join("menu_glow.png"))

	var poster := Paint.Sheet.load_png(art.path_join("wanted_poster.png")).resized(38, 48)
	opaque(poster)
	pinned(poster).save(out.path_join("menu_wanted.png"))

	var notice := paper(46, 40, 8, Vector3(214, 196, 158))
	Paint.outline(notice, 0, 0, 45, 39, Color8(70, 52, 38))
	Paint.rect(notice, 3, 3, 42, 9, Color8(150, 34, 24))  # the MISSING banner
	var pig := Paint.Sheet.load_png(art.path_join("bessie_0.png")).resized(38, 24)
	for y in pig.h:
		for x in pig.w:
			var o := (y * pig.w + x) * 4
			var a := pig.data[o + 3] / 255.0
			if a <= 0.0:
				continue
			var t := ((11 + y) * notice.w + 4 + x) * 4
			for k in 3:
				notice.data[t + k] = int(pig.data[o + k] * a + notice.data[t + k] * (1.0 - a))
	Paint.line2(notice, 6, 37, 39, 37, Color8(70, 52, 38))
	pinned(notice).save(out.path_join("menu_bessie.png"))

	var saucer := Paint.Sheet.new(17, 8)
	Paint.ellipse(saucer, 5, 0, 11, 5, Color8(120, 190, 150))
	Paint.ellipse(saucer, 0, 3, 16, 7, Color8(92, 100, 104))
	Paint.line2(saucer, 2, 5, 14, 5, Color8(190, 200, 198))
	for x in [3, 8, 13]:
		Paint.point(saucer, x, 6, Color8(160, 255, 150))
	saucer.save(out.path_join("menu_saucer.png"))
	print("menu art written to ", out)
	quit()


func opaque(s: Paint.Sheet) -> void:
	for i in s.w * s.h:
		s.data[i * 4 + 3] = 255


func normal(seed: int, sigma: float) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return rng.randfn(0.0, sigma)


## Vertical boards: grain streaks, seams, knots and nail heads.
func timber(width: int, height: int, seed: int, plank: int) -> Paint.Sheet:
	var img := PackedFloat32Array()
	img.resize(width * height * 3)
	var base := Vector3(96, 66, 42)
	var x := 0
	var index := 0
	while x < width:
		var pick := RandomNumberGenerator.new()
		pick.seed = seed + index
		var w := plank + pick.randi_range(-4, 4)
		var tone := 1.0 + normal(seed * 7 + index, .09)
		var grain := Paint.noise(seed * 13 + index, maxi(w, 1), .07)
		var streak := Paint.noise(seed * 17 + index, height * maxi(w, 1), .035)
		for yy in height:
			for xx in mini(w, width - x):
				var f := 1.0 + grain[xx] + streak[yy * maxi(w, 1) + xx]
				var o := (yy * width + x + xx) * 3
				img[o] = base.x * tone * f
				img[o + 1] = base.y * tone * f
				img[o + 2] = base.z * tone * f
		for yy in height:
			for k in 3:
				img[(yy * width + x) * 3 + k] *= .45  # the seam
				if x + 1 < width:
					img[(yy * width + x + 1) * 3 + k] *= 1.12
		x += w
		index += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 99
	for _k in maxi(2, width * height / 2600):  # knots
		var cx := rng.randi_range(3, width - 4)
		var cy := rng.randi_range(3, height - 4)
		for yy in height:
			for xx in width:
				var d := pow((xx - cx) / 2.6, 2) + pow((yy - cy) / 1.6, 2)
				if d < 30.0:
					var dim := 1.0 - .45 * exp(-d)
					for k in 3:
						img[(yy * width + xx) * 3 + k] *= dim
	for xx in width:
		for k in 3:
			for yy in [0, 1]:
				img[(yy * width + xx) * 3 + k] *= .6
			for yy in [height - 2, height - 1]:
				img[(yy * width + xx) * 3 + k] *= .5
	var out := Paint.Sheet.new(width, height)
	for i in width * height:
		out.data[i * 4] = clampi(int(img[i * 3]), 0, 255)
		out.data[i * 4 + 1] = clampi(int(img[i * 3 + 1]), 0, 255)
		out.data[i * 4 + 2] = clampi(int(img[i * 3 + 2]), 0, 255)
		out.data[i * 4 + 3] = 255
	for nx in range(6, width - 4, 44):
		for ny in [4, height - 6]:
			Paint.point(out, nx, ny, Color8(40, 30, 24))
			Paint.point(out, nx, ny - 1, Color8(150, 140, 128))
	return out


## Corrugated tin gone to rust at the edges.
func rust(width: int, height: int, seed: int) -> Paint.Sheet:
	var cells := Vector2i(width / 5 + 2, height / 3 + 2)
	var pick := RandomNumberGenerator.new()
	pick.seed = seed
	var grid := PackedByteArray()
	grid.resize(cells.x * cells.y)
	for i in grid.size():
		grid[i] = int(pick.randf() * 255)
	var blot_image := Image.create_from_data(cells.x, cells.y, false, Image.FORMAT_L8, grid)
	blot_image.resize(width, height, Image.INTERPOLATE_CUBIC)
	var blot := blot_image.get_data()
	var grit := Paint.noise(seed + 1, width * height, 5)
	var out := Paint.Sheet.new(width, height)
	for y in height:
		for x in width:
			var ridge := sin(x * .9) * .5 + .5
			var tin := Vector3(132, 138, 136) * (.72 + .28 * ridge)
			var edge := minf(minf(y, height - 1 - y) / 4.0, minf(x, width - 1 - x) / 10.0)
			var amount := clampf(blot[y * width + x] / 255.0 * 1.5 - clampf(edge, 0, 1) * .75, 0, 1)
			var orange := Vector3(150, 72, 34) * (.8 + .2 * ridge)
			var c := tin * (1 - amount) + orange * amount + Vector3.ONE * grit[y * width + x]
			out.put(x, y, Paint.rgb(c.x, c.y, c.z))
	Paint.outline(out, 0, 0, width - 1, height - 1, Color8(34, 24, 18))
	for nx in [4, width - 5]:
		Paint.point(out, nx, height / 2, Color8(222, 226, 224))
		Paint.point(out, nx, height / 2 + 1, Color8(40, 34, 30))
	return out


func glow(width: int, height: int) -> Paint.Sheet:
	var out := Paint.Sheet.new(width, height)
	for y in height:
		for x in width:
			var d := (
				Vector2((x - width * .5) / (width * .5), (y - height * .18) / (height * .9))
				. length()
			)
			out.put(x, y, Color8(255, 196, 112, int(pow(clampf(1 - d, 0, 1), 2) * 86)))
	return out


func paper(width: int, height: int, seed: int, colour: Vector3) -> Paint.Sheet:
	var grit := Paint.noise(seed, width * height, 7)
	var pick := RandomNumberGenerator.new()
	pick.seed = seed + 5
	var grid := PackedByteArray()
	grid.resize(16)
	for i in 16:
		grid[i] = int(pick.randf() * 255)
	var stain_image := Image.create_from_data(4, 4, false, Image.FORMAT_L8, grid)
	stain_image.resize(width, height, Image.INTERPOLATE_CUBIC)
	var stain := stain_image.get_data()
	var out := Paint.Sheet.new(width, height)
	for i in width * height:
		var c := colour + Vector3.ONE * (grit[i] - stain[i] / 255.0 * 22)
		out.put(i % width, i / width, Paint.rgb(c.x, c.y, c.z))
	return out


## A sheet of paper with a drop shadow and a nail, on transparency.
func pinned(sheet: Paint.Sheet) -> Paint.Sheet:
	var out := Paint.Sheet.new(sheet.w + 2, sheet.h + 2)
	out.paste(Paint.Sheet.new(sheet.w, sheet.h, Color8(10, 7, 5, 150)), 2, 2)
	out.paste(sheet, 0, 0)
	Paint.point(out, sheet.w / 2, 1, Color8(40, 34, 30))
	Paint.point(out, sheet.w / 2, 0, Color8(200, 200, 196))
	return out
