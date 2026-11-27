## Paint the foliage a map may scatter (pass 16, LOOKS; src/map_kit/
## foliage.gd, dressing.json "foliage") into assets/art, camera-facing sprites
## in the old pictures' look:
##
##   godot --headless --path godot --script res://tools/art/build_foliage_art.gd [-- out=<dir>]
##
##   foliage_grass_0..2   a tuft of pasture grass, green going to straw
##   foliage_weeds_0      goldenrod: leafy stems, yellow plumes
##   foliage_weeds_1      bull thistle: spiny leaves, purple heads
##   foliage_bush_0, _1   a scrub bush, leafy, lit from above; the second
##                        dry and berried
##   foliage_pine_0, _1   a loblolly pine, its boughs in ragged tiers; the
##                        second lopsided and thin
##   foliage_corn_0, _1   a hill of corn stalks, leaves arching, tassels and
##                        an ear; the second drying out
##   foliage_cypress, foliage_cypress_b, foliage_snag
##                        the bald cypresses' and the dead snag's pictures
##                        (town_cypress, town_cypress_b, town_dead_snag) as
##                        sprites of their own, so scattered ones draw in the
##                        sprite layer and not as a model each
##
## Each is drawn at four times its size from its own dice, shrunk with a hard
## edge, a dark rim and the prop pictures' grade (Paint.photo_shrink), then
## digitized to the palette. Then run tools/pack_assets.gd.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")
const U := 4


func _init() -> void:
	var out := Paint.repo("assets/art")
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	var made := 0
	for k in 3:
		_save(grass(k), Vector2i(44, 30), 301 + k, out, "foliage_grass_%d" % k)
		made += 1
	_save(goldenrod(), Vector2i(50, 62), 311, out, "foliage_weeds_0")
	_save(thistle(), Vector2i(48, 58), 312, out, "foliage_weeds_1")
	_save(bush(0), Vector2i(88, 74), 321, out, "foliage_bush_0")
	_save(bush(1), Vector2i(84, 70), 322, out, "foliage_bush_1")
	_save(pine(0), Vector2i(104, 196), 331, out, "foliage_pine_0")
	_save(pine(1), Vector2i(96, 200), 332, out, "foliage_pine_1")
	_save(corn(0), Vector2i(62, 96), 341, out, "foliage_corn_0")
	_save(corn(1), Vector2i(60, 92), 342, out, "foliage_corn_1")
	made += 8
	for pair: Array in [
		["town_cypress", "foliage_cypress"],
		["town_cypress_b", "foliage_cypress_b"],
		["town_dead_snag", "foliage_snag"]
	]:
		var src := Paint.Sheet.load_png(Paint.repo("assets/art").path_join(str(pair[0]) + ".png"))
		if src == null:
			push_error("no %s.png" % pair[0])
			continue
		src.save(out.path_join(str(pair[1]) + ".png"))
		made += 1
	print("foliage art: %d pictures in %s" % [made, out])
	quit()


func _save(im: Paint.Sheet, size: Vector2i, seed: int, out: String, name: String) -> void:
	Paint.digitize(_shrink(im, size, seed), 8.0).save(out.path_join(name + ".png"))


## Down to `size` a block of U x U at a time: a pixel is there when a third
## of its block is, its colour the block's painted pixels' mean with a little
## grain; a pixel on the edge darkened (the old sprites' rim). Thin blades
## and stems keep their line, as a hand-cut sprite's do.
static func _shrink(im: Paint.Sheet, size: Vector2i, seed: int) -> Paint.Sheet:
	var out := Paint.Sheet.new(size.x, size.y)
	var grain := Paint.noise(seed, size.x * size.y, .03)
	var solid := PackedByteArray()
	solid.resize(size.x * size.y)
	var colour: Array[Vector3] = []
	colour.resize(size.x * size.y)
	for y in size.y:
		for x in size.x:
			var sum := Vector3.ZERO
			var n := 0
			for v in U:
				for u in U:
					var sx := x * U + u
					var sy := y * U + v
					if sx >= im.w or sy >= im.h:
						continue
					var o := (sy * im.w + sx) * 4
					if im.data[o + 3] > 0:
						sum += Vector3(im.data[o], im.data[o + 1], im.data[o + 2])
						n += 1
			var i := y * size.x + x
			solid[i] = 1 if n * 3 >= U * U else 0
			colour[i] = sum / maxi(n, 1)
	for y in size.y:
		for x in size.x:
			var i := y * size.x + x
			if solid[i] == 0:
				continue
			var c := colour[i] * (1.0 + grain[i])
			var edge := false
			for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx := x + d.x
				var ny := y + d.y
				if nx < 0 or ny < 0 or nx >= size.x or ny >= size.y or solid[ny * size.x + nx] == 0:
					edge = true
			if edge:
				c *= .72
			out.put(x, y, Paint.rgb(c.x, c.y, c.z))
	return out


static func _rgb(c: Vector3) -> Color:
	return Paint.rgb(c.x, c.y, c.z)


## A blade or leaf: a tapered band from `a` bending through `bend` to `b`,
## `width` wide at its foot.
static func _blade(
	im: Paint.Sheet, a: Vector2, bend: Vector2, b: Vector2, width: float, c: Color
) -> void:
	var steps := 10
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for k in steps + 1:
		var t := float(k) / steps
		var p := a.lerp(bend, t).lerp(bend.lerp(b, t), t)
		var q := a.lerp(bend, t + .01).lerp(bend.lerp(b, t + .01), t + .01)
		var along := (q - p).normalized() if q != p else Vector2.UP
		var side := Vector2(-along.y, along.x) * width * .5 * (1.0 - t * .92)
		left.append(p + side)
		right.append(p - side)
	right.reverse()
	Paint.polygon(im, left + right, c)


## A tuft of grass: blades from a tight foot, the dark ones behind.
func grass(variant: int) -> Paint.Sheet:
	var w := 44 * U
	var h := 30 * U
	var im := Paint.Sheet.new(w, h)
	var dice := RandomNumberGenerator.new()
	dice.seed = 9100 + variant
	var straw: float = [.1, .25, .45][variant]
	var blades := 26 + variant * 4
	for k in blades:
		var t := float(k) / blades
		var foot := Vector2(w * .5 + dice.randf_range(-w * .2, w * .2), h - 1.0)
		var lean := dice.randf_range(-1.0, 1.0)
		var tall := h * dice.randf_range(.4, .97)
		var tip := foot + Vector2(lean * w * .42, -tall)
		var bend := foot.lerp(tip, .5) + Vector2(-lean * w * .04, -tall * .18)
		var dark := Vector3(52, 72, 30).lerp(Vector3(98, 120, 46), t)
		var colour := dark.lerp(Vector3(156, 138, 74), straw * dice.randf())
		_blade(im, foot, bend, tip, U * dice.randf_range(1.5, 2.4), _rgb(colour))
	return im


## Goldenrod: leafy stems and arching yellow plumes.
func goldenrod() -> Paint.Sheet:
	var w := 50 * U
	var h := 62 * U
	var im := Paint.Sheet.new(w, h)
	var dice := RandomNumberGenerator.new()
	dice.seed = 9201
	for k in 14:
		var foot := Vector2(w * .5 + dice.randf_range(-w * .2, w * .2), h - 1.0)
		var lean := dice.randf_range(-1.0, 1.0)
		var tip := foot + Vector2(lean * w * .3, -h * dice.randf_range(.25, .45))
		_blade(im, foot, foot.lerp(tip, .5), tip, U * 2.6, _rgb(Vector3(66, 86, 34)))
	for k in 6:
		var foot := Vector2(w * (.3 + k * .08) + dice.randf_range(-U * 2, U * 2), h - 1.0)
		var top := Vector2(foot.x + dice.randf_range(-w * .16, w * .16), h * dice.randf_range(.12, .3))
		Paint.line(im, PackedVector2Array([foot, foot.lerp(top, .5) + Vector2(U * 2, 0), top]), _rgb(Vector3(88, 92, 44)), U * 1.6)
		for j in 5:
			var at := foot.lerp(top, .25 + j * .13)
			var leaf_tip := at + Vector2((-1.0 if j % 2 else 1.0) * w * .12, -h * .03)
			_blade(im, at, at.lerp(leaf_tip, .5) + Vector2(0, -U * 2), leaf_tip, U * 2.2, _rgb(Vector3(80, 104, 40)))
		# The plume: a spray of tiny yellow heads arching off the top.
		var arch := 1.0 if dice.randf() > .5 else -1.0
		for spray in 3:
			var spread := (spray - 1) * .5
			for j in 14:
				var t := float(j) / 14.0
				var p := top + Vector2((arch * .6 + spread) * t * w * .14, -t * h * .1 + t * t * h * .07)
				var r := U * dice.randf_range(1.0, 1.8)
				var c := Vector3(196, 156, 40).lerp(Vector3(232, 206, 84), dice.randf())
				var jx := dice.randf_range(-U * 1.5, U * 1.5)
				Paint.ellipse(im, p.x - r + jx, p.y - r, p.x + r + jx, p.y + r, _rgb(c))
	return im


## Bull thistle: spiny rosette leaves, stems, purple brush heads.
func thistle() -> Paint.Sheet:
	var w := 48 * U
	var h := 58 * U
	var im := Paint.Sheet.new(w, h)
	var dice := RandomNumberGenerator.new()
	dice.seed = 9202
	for k in 10:
		var foot := Vector2(w * .5, h - 1.0)
		var angle := lerpf(-2.9, -.25, float(k) / 9.0)
		var tip := foot + Vector2(cos(angle), sin(angle) * .7) * w * dice.randf_range(.32, .48)
		_blade(im, foot, foot.lerp(tip, .5) + Vector2(0, -U * 5), tip, U * 9.0, _rgb(Vector3(58, 84, 52).lerp(Vector3(92, 118, 72), dice.randf())))
		for j in 4:
			var at := foot.lerp(tip, .25 + j * .2)
			Paint.line2(im, at.x, at.y, at.x + dice.randf_range(-U * 3, U * 3), at.y - U * 3, _rgb(Vector3(196, 196, 160)), U * .8)
	for k in 4:
		var foot := Vector2(w * (.38 + k * .08), h - U * 6)
		var top := Vector2(foot.x + dice.randf_range(-w * .16, w * .16), h * dice.randf_range(.18, .36))
		Paint.line(im, PackedVector2Array([foot, top]), _rgb(Vector3(82, 100, 60)), U * 2.2)
		for j in 3:
			var at := foot.lerp(top, .3 + j * .2)
			var side := -1.0 if j % 2 else 1.0
			_blade(im, at, at + Vector2(side * U * 5, -U * 4), at + Vector2(side * U * 10, -U * 2), U * 4.0, _rgb(Vector3(76, 100, 62)))
		Paint.ellipse(im, top.x - U * 6, top.y, top.x + U * 6, top.y + U * 9, _rgb(Vector3(86, 104, 62)))
		for j in 22:
			var a := lerpf(-2.7, -.45, float(j) / 21.0)
			var tip := top + Vector2(cos(a), sin(a)) * U * dice.randf_range(6.0, 9.5)
			Paint.line2(im, top.x, top.y + U * 2, tip.x, tip.y, _rgb(Vector3(150, 66, 144).lerp(Vector3(206, 120, 192), dice.randf())), U * 1.6)
	return im


## A scrub bush: leafy blobs heaped into a dome, lit from above, a few twigs
## under it. Variant 1 is drier and carries red berries.
func bush(variant: int) -> Paint.Sheet:
	var w := (88 if variant == 0 else 84) * U
	var h := (74 if variant == 0 else 70) * U
	var im := Paint.Sheet.new(w, h)
	var dice := RandomNumberGenerator.new()
	dice.seed = 9300 + variant
	for k in 5:
		var foot := Vector2(w * .5 + dice.randf_range(-w * .08, w * .08), h - 1.0)
		var tip := Vector2(w * dice.randf_range(.25, .75), h * .55)
		Paint.line(im, PackedVector2Array([foot, tip]), _rgb(Vector3(70, 52, 34)), U * 1.8)
	var dark := Vector3(40, 60, 26) if variant == 0 else Vector3(70, 70, 34)
	var light := Vector3(112, 138, 54) if variant == 0 else Vector3(150, 140, 72)
	# Back to front, low to high: each blob of leaves lighter toward the top.
	for k in 70:
		var t := float(k) / 70.0
		var cx := w * .5 + dice.randf_range(-w * .38, w * .38) * (1.0 - t * .45)
		var cy := h * lerpf(.86, .28, t) + dice.randf_range(-h * .06, h * .06)
		var r := U * dice.randf_range(5.0, 9.0)
		var c := dark.lerp(light, clampf(t * .9 + dice.randf_range(-.15, .15), 0.0, 1.0))
		Paint.ellipse(im, cx - r, cy - r * .8, cx + r, cy + r * .8, _rgb(c))
		# Leaves catching the light on the blob's top.
		for j in 4:
			var lx := cx + dice.randf_range(-r * .7, r * .7)
			var ly := cy - r * dice.randf_range(.2, .7)
			Paint.ellipse(im, lx - U, ly - U * .7, lx + U, ly + U * .7, _rgb(c.lerp(Vector3(190, 196, 110), .35)))
	if variant == 1:
		for k in 22:
			var bx := w * dice.randf_range(.2, .8)
			var by := h * dice.randf_range(.3, .8)
			Paint.ellipse(im, bx - U * 1.2, by - U * 1.2, bx + U * 1.2, by + U * 1.2, _rgb(Vector3(170, 36, 30)))
	return im


## A loblolly pine: a bare trunk, then boughs in ragged tiers narrowing to the
## top, each tier dark under and lit along its upper edge. Variant 1 leans
## and is thinner.
func pine(variant: int) -> Paint.Sheet:
	var w := (104 if variant == 0 else 96) * U
	var h := (196 if variant == 0 else 200) * U
	var im := Paint.Sheet.new(w, h)
	var dice := RandomNumberGenerator.new()
	dice.seed = 9400 + variant
	var lean := 0.0 if variant == 0 else w * .06
	var foot := Vector2(w * .5, h - 1.0)
	var crown := Vector2(w * .5 + lean, h * .02)
	Paint.polygon(
		im,
		PackedVector2Array([
			foot + Vector2(-U * 4, 0), foot + Vector2(U * 4, 0),
			crown + Vector2(U * 1.2, 0), crown + Vector2(-U * 1.2, 0)
		]),
		_rgb(Vector3(88, 60, 40))
	)
	Paint.line(im, PackedVector2Array([foot + Vector2(U * 2, 0), crown]), _rgb(Vector3(120, 86, 56)), U * 1.2)
	var tiers := 8 if variant == 0 else 7
	var bottom := h * (.62 if variant == 0 else .55)
	for k in tiers:
		var t := float(k) / tiers
		var y := lerpf(bottom, h * .04, t)
		var mid := foot.lerp(crown, 1.0 - y / h)
		var half := w * lerpf(.48, .1, t) * (dice.randf_range(.75, 1.0) if variant == 1 else 1.0)
		var drop := h * lerpf(.12, .06, t)
		var pts := PackedVector2Array([Vector2(mid.x, y - drop * .9)])
		var n := 9
		for j in n + 1:
			var u := float(j) / n
			var x := mid.x - half + u * half * 2.0
			var sag := drop * (.55 + .45 * sin(u * PI)) + dice.randf_range(-U * 3, U * 3)
			pts.append(Vector2(x + dice.randf_range(-U * 2, U * 2), y + sag * (.4 if j % 2 else 1.0)))
		var base := Vector3(30, 52, 36).lerp(Vector3(46, 74, 46), t)
		Paint.polygon(im, pts, _rgb(base))
		# The light along the bough's top and its sunny side.
		for j in 40:
			var u := dice.randf()
			var x := mid.x - half * .8 + u * half * 1.6
			var yy := y - drop * .6 * (1.0 - absf(u - .5) * 1.6) + dice.randf_range(0, drop * .8)
			var c := base.lerp(Vector3(96, 124, 70), clampf(u * .9 + dice.randf_range(-.2, .2), 0.0, 1.0))
			Paint.ellipse(im, x - U * 1.4, yy - U, x + U * 1.4, yy + U, _rgb(c))
	return im


## A hill of corn: stalks with long arching leaves, a tassel each and an ear
## on one. Variant 1 is drying: the leaves going to tan from their tips.
func corn(variant: int) -> Paint.Sheet:
	var w := (62 if variant == 0 else 60) * U
	var h := (96 if variant == 0 else 92) * U
	var im := Paint.Sheet.new(w, h)
	var dice := RandomNumberGenerator.new()
	dice.seed = 9500 + variant
	var dry := .15 if variant == 0 else .6
	var stalks := 4
	for k in stalks:
		var foot := Vector2(w * (.32 + k * .12) + dice.randf_range(-U * 2, U * 2), h - 1.0)
		var top := Vector2(foot.x + dice.randf_range(-U * 4, U * 4), h * dice.randf_range(.1, .2))
		var stalk := Vector3(120, 140, 60).lerp(Vector3(170, 150, 90), dry)
		Paint.line(im, PackedVector2Array([foot, top]), _rgb(stalk * .8), U * 2.6)
		Paint.line(im, PackedVector2Array([foot + Vector2(U, 0), top + Vector2(U, 0)]), _rgb(stalk), U * 1.0)
		for j in 6:
			var at := foot.lerp(top, .12 + j * .14)
			var side := -1.0 if (j + k) % 2 else 1.0
			var tip := at + Vector2(side * w * dice.randf_range(.28, .4), h * dice.randf_range(.02, .12))
			var bend := at + Vector2(side * w * .14, -h * .08)
			var leaf := Vector3(70, 108, 40).lerp(Vector3(176, 158, 92), clampf(dry + dice.randf_range(-.1, .2), 0.0, 1.0))
			_blade(im, at, bend, tip, U * 4.0, _rgb(leaf))
		# The tassel.
		for j in 7:
			var tip := top + Vector2(dice.randf_range(-U * 6, U * 6), -dice.randf_range(U * 3, U * 9))
			Paint.line2(im, top.x, top.y, tip.x, tip.y, _rgb(Vector3(206, 178, 104)), U * 1.0)
		if k == 1:
			var ear := foot.lerp(top, .5)
			Paint.ellipse(im, ear.x + U, ear.y - U * 6, ear.x + U * 6, ear.y + U * 6, _rgb(Vector3(150, 160, 80).lerp(Vector3(190, 170, 110), dry)))
			Paint.line2(im, ear.x + U * 4, ear.y - U * 6, ear.x + U * 6, ear.y - U * 10, _rgb(Vector3(150, 96, 60)), U * 1.2)
	return im
