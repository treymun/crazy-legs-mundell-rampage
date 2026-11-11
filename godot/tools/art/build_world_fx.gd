## Paint the small things that make a fight and a level feel lived in, into
## assets/art: spent brass and shotgun hulls, embers, scorch marks, the crows
## that cross the sky and the fireflies of a summer night.
##
##   godot --headless --path godot --script res://tools/art/build_world_fx.gd [-- out=<dir>]
##
##   fx_casing        a spent rifle or revolver case, brass
##   fx_hull          a spent 12-gauge hull: red paper, brass head
##   fx_ember_N       (2) a spark of burning stuff floating up from a blast
##   mark_scorch_N    (3) the black scorch an explosion leaves on the ground
##   fx_crow_N        (2) a crow, wings up and wings down
##   fx_firefly_N     (2) a firefly lit and dark
## Then run tools/pack_assets.gd. out= writes somewhere else instead.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 1977
	var out := Paint.repo("assets/art")
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	casing().save(out.path_join("fx_casing.png"))
	hull().save(out.path_join("fx_hull.png"))
	for k in 2:
		ember(k).save(out.path_join("fx_ember_%d.png" % k))
		crow(k).save(out.path_join("fx_crow_%d.png" % k))
		firefly(k).save(out.path_join("fx_firefly_%d.png" % k))
	for k in 3:
		scorch(k).save(out.path_join("mark_scorch_%d.png" % k))
	print("world fx: 11 pictures in ", out)
	quit()


## Drawn four times over and shrunk, like the gore, for soft round edges cut hard.
func shrunk(big: Paint.Sheet, w: int, h: int, cut := 110) -> Paint.Sheet:
	var small := big.resized(w, h)
	for i in w * h:
		small.data[i * 4 + 3] = 255 if small.data[i * 4 + 3] >= cut else 0
	return small


func casing() -> Paint.Sheet:
	var s := Paint.Sheet.new(48, 20)
	Paint.rounded_rect(s, 4, 4, 38, 15, 4, Color8(176, 132, 52))
	Paint.rect(s, 36, 3, 43, 16, Color8(150, 110, 44))  # the rim
	Paint.rect(s, 6, 5, 34, 7, Color8(236, 204, 120))  # shine along the top
	Paint.rect(s, 6, 13, 34, 14, Color8(116, 82, 30))
	Paint.rect(s, 2, 6, 5, 13, Color8(96, 70, 32))  # the open, sooty mouth
	return shrunk(s, 12, 5)


func hull() -> Paint.Sheet:
	var s := Paint.Sheet.new(56, 24)
	Paint.rounded_rect(s, 4, 4, 40, 19, 3, Color8(170, 34, 28))  # red paper
	Paint.rect(s, 6, 6, 38, 8, Color8(214, 74, 60))
	Paint.rect(s, 6, 16, 38, 17, Color8(110, 20, 18))
	Paint.rect(s, 38, 3, 51, 20, Color8(184, 140, 58))  # brass head
	Paint.rect(s, 40, 5, 49, 7, Color8(236, 206, 128))
	Paint.rect(s, 49, 2, 52, 21, Color8(150, 110, 44))
	for x in range(8, 36, 6):  # the crimped, scorched end
		Paint.line2(s, 4, 6 + (x % 4), 8, 11, Color8(80, 16, 14))
	return shrunk(s, 14, 6)


func ember(k: int) -> Paint.Sheet:
	var s := Paint.Sheet.new(32, 32)
	var outer := Color8(232, 96, 24) if k == 0 else Color8(196, 60, 18)
	var inner := Color8(255, 222, 120) if k == 0 else Color8(250, 160, 60)
	Paint.ellipse(s, 7, 7, 24, 24, outer)
	Paint.ellipse(s, 12, 11, 20, 19, inner)
	return shrunk(s, 6, 6, 90)


func scorch(k: int) -> Paint.Sheet:
	var size := 96
	var s := Paint.Sheet.new(size * 2, size * 2)
	var c := size
	# A burnt blotch: ragged soot rings, darkest in the middle, with flecks thrown out.
	for ring in 4:
		var r := size * (.92 - ring * .2)
		var pts := PackedVector2Array()
		for i in 28:
			var a := i * TAU / 28.0
			var rr := r * (1.0 + rng.randf_range(-.18, .14) + .1 * sin(a * (3 + k) + k))
			pts.append(Vector2(c + cos(a) * rr, c + sin(a) * rr))
		var shade := 34 - ring * 8
		Paint.polygon(s, pts, Color8(shade, shade - 4, shade - 8, 90 + ring * 45))
	for _i in 22:
		var a := rng.randf_range(0, TAU)
		var d := size * rng.randf_range(.75, 1.0)
		var r2 := rng.randf_range(3, 8)
		Paint.ellipse(
			s,
			c + cos(a) * d - r2,
			c + sin(a) * d - r2,
			c + cos(a) * d + r2,
			c + sin(a) * d + r2,
			Color8(30, 26, 22, 170)
		)
	var out := s.resized(48, 48)
	return out


func crow(k: int) -> Paint.Sheet:
	var s := Paint.Sheet.new(96, 48)
	var black := Color8(22, 20, 24)
	Paint.ellipse(s, 34, 20, 62, 32, black)  # body
	Paint.ellipse(s, 58, 18, 70, 28, black)  # head
	Paint.polygon(
		s,
		PackedVector2Array([Vector2(69, 22), Vector2(78, 24), Vector2(69, 26)]),
		Color8(52, 46, 40)
	)
	var tail := PackedVector2Array([Vector2(34, 24), Vector2(20, 20), Vector2(22, 30)])
	Paint.polygon(s, tail, black)
	var tip := 4.0 if k == 0 else 44.0
	for side: float in [-1.0, 1.0]:
		Paint.polygon(
			s,
			PackedVector2Array([Vector2(40, 24), Vector2(56, 24), Vector2(48 + side * 26, tip)]),
			black
		)
	return shrunk(s, 24, 12)


func firefly(k: int) -> Paint.Sheet:
	var s := Paint.Sheet.new(24, 24)
	if k == 0:
		Paint.ellipse(s, 4, 4, 19, 19, Color8(186, 240, 96))
		Paint.ellipse(s, 8, 8, 15, 15, Color8(244, 255, 196))
	else:
		Paint.ellipse(s, 9, 9, 14, 14, Color8(70, 76, 40))
	return shrunk(s, 4, 4, 80)
