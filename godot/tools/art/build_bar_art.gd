## Draw the barred door (pass 15's loops, a door with "bar_side" in a level):
## the plank door (assets/tiles/door.png) with a heavy board dropped across it
## in two black iron brackets, nailed through, the bar's shadow under it.
##
##   godot --headless --path godot --script res://tools/art/build_bar_art.gd [-- out=<dir>]
##
## Tile (listed at the end of data/index.json and assets_gen/tiles_index.json):
##   door_barred   the shortcut's door, barred; kicked open the bar is busted
## Seeded, so a rerun gives the same file. Then run tools/pack_assets.gd.
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")

## The board's rows (its top and bottom edge) and the brackets' columns.
const BAR_TOP := 54
const BAR_BOTTOM := 71
const BRACKETS := [22, 99]

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 1515
	var tiles := Paint.repo("assets/tiles")
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			tiles = String(arg).substr(4)
	DirAccess.make_dir_recursive_absolute(tiles)
	var door := Paint.Sheet.load_png(Paint.repo("assets/tiles/door.png"))
	barred(door).save(tiles.path_join("door_barred.png"))
	print("BAR ART WRITTEN to %s" % tiles)
	quit()


func barred(door: Paint.Sheet) -> Paint.Sheet:
	var s := door.duplicate_sheet()
	# The bar's shadow on the planks under it.
	for y in range(BAR_BOTTOM + 1, BAR_BOTTOM + 6):
		for x in range(6, 122):
			_darken(s, x, y, .55 + .08 * (y - BAR_BOTTOM))
	# The board: rough-sawn oak, grain along it, a split near one end.
	var wood := Color8(118, 84, 52)
	for y in range(BAR_TOP, BAR_BOTTOM + 1):
		for x in range(4, 124):
			var grain := sin(x * .21 + sin(y * .9) * 2.2 + y * .4) * .06
			var shade := 1.0 + grain + rng.randf_range(-.05, .05)
			if y == BAR_TOP:
				shade = 1.28
			elif y == BAR_TOP + 1:
				shade *= 1.12
			elif y >= BAR_BOTTOM - 1:
				shade *= .66
			s.put(x, y, Color(wood.r * shade, wood.g * shade, wood.b * shade))
	for x in range(84, 108):
		s.put(x, BAR_TOP + 7 + (x % 3 == 0 as int), Color8(60, 40, 24))
	# Its sawn ends.
	for y in range(BAR_TOP, BAR_BOTTOM + 1):
		s.put(4, y, Color8(70, 48, 28))
		s.put(123, y, Color8(70, 48, 28))
	# The brackets: black iron straps round the board, bolted to the door.
	for bx: int in BRACKETS:
		Paint.rect(s, bx - 6, BAR_TOP - 5, bx + 6, BAR_TOP - 2, Color8(34, 32, 30))
		Paint.rect(s, bx - 6, BAR_BOTTOM + 2, bx + 6, BAR_BOTTOM + 5, Color8(34, 32, 30))
		Paint.rect(s, bx - 6, BAR_TOP - 5, bx - 4, BAR_BOTTOM + 5, Color8(28, 26, 24))
		Paint.rect(s, bx + 4, BAR_TOP - 5, bx + 6, BAR_BOTTOM + 5, Color8(28, 26, 24))
		Paint.rect(s, bx - 6, BAR_TOP - 5, bx + 6, BAR_TOP - 5, Color8(92, 88, 82))
		for k: int in [-5, 5]:
			for by: int in [BAR_TOP - 4, BAR_BOTTOM + 4]:
				s.put(bx + k, by, Color8(150, 140, 126))
		# Rust run down the planks from each bracket.
		for y in range(BAR_BOTTOM + 6, BAR_BOTTOM + 16 + rng.randi_range(0, 8)):
			_tint(s, bx - 3 + rng.randi_range(0, 6), y, Color8(120, 62, 30), .35)
	# Nail heads through the board.
	for nx: int in [40, 63, 86]:
		s.put(nx, BAR_TOP + 6, Color8(44, 40, 36))
		s.put(nx + 1, BAR_TOP + 6, Color8(150, 144, 132))
		s.put(nx, BAR_BOTTOM - 5, Color8(44, 40, 36))
	return s


func _darken(s: Paint.Sheet, x: int, y: int, k: float) -> void:
	var o := (y * s.w + x) * 4
	for c in 3:
		s.data[o + c] = int(s.data[o + c] * clampf(k, 0.0, 1.0))


func _tint(s: Paint.Sheet, x: int, y: int, ink: Color, k: float) -> void:
	if x < 0 or y < 0 or x >= s.w or y >= s.h:
		return
	var o := (y * s.w + x) * 4
	var to := [ink.r8, ink.g8, ink.b8]
	for c in 3:
		s.data[o + c] = int(lerpf(s.data[o + c], to[c], k))
