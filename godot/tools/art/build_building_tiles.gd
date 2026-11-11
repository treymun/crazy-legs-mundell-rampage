## Draw the wall tiles that turn a plain box into a building, into assets/tiles.
##
##   godot --headless --path godot --script res://tools/art/build_building_tiles.gd [-- out=<dir>]
##
## For each building material: <material>_win (dark glass) and <material>_lit
## (a lamp on inside); and trim_foundation and trim_eave, the bands a building
## wall stands on and is capped with. data/index.json lists the tiles the
## levels use; then run tools/pack_assets.gd. effects.cfg makes the _lit ones
## glow. out= writes somewhere else instead (to compare).
extends SceneTree

const Paint := preload("res://tools/art/paint.gd")
## The materials a building is made of (each has a plain tile in assets/tiles).
const MATERIALS := [
	"barn",
	"tin",
	"brick",
	"plaster",
	"cinder",
	"office_wall",
	"fair_booth",
	"fair_iron",
	"mill_tin",
	"quarry_iron",
	"quarry_shed",
	"hub_service_wall"
]
const METAL := ["tin", "fair_iron", "mill_tin", "quarry_iron"]

var rng := RandomNumberGenerator.new()


func _init() -> void:
	rng.seed = 1931
	var tiles := Paint.repo("assets/tiles")
	var out := tiles
	for arg in OS.get_cmdline_user_args():
		if String(arg).begins_with("out="):
			out = String(arg).substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	var count := 0
	for material: String in MATERIALS:
		var base := Paint.Sheet.load_png(tiles.path_join(material + ".png"))
		for pair in [["win", false], ["lit", true]]:
			window(base, pair[1], material in METAL).save(
				out.path_join("%s_%s.png" % [material, pair[0]])
			)
			count += 1
	foundation().save(out.path_join("trim_foundation.png"))
	eave().save(out.path_join("trim_eave.png"))
	print("building tiles: %d windows for %d materials, 2 trims" % [count, MATERIALS.size()])
	quit()


func window(base: Paint.Sheet, lit: bool, metal: bool) -> Paint.Sheet:
	var tile := base.duplicate_sheet()
	var frame := Color8(92, 98, 102) if metal else Color8(66, 48, 34)
	var edge := Color8(40, 42, 44) if metal else Color8(34, 24, 18)
	var x0 := 30
	var y0 := 34
	var x1 := 97
	var y1 := 86
	# Recess shadow, frame, then the glass.
	Paint.rect(tile, x0 - 2, y0 - 2, x1 + 2, y1 + 2, edge)
	Paint.rect(tile, x0, y0, x1, y1, frame)
	var gx0 := x0 + 4
	var gy0 := y0 + 4
	var gw := x1 - 4 - gx0 + 1
	var gh := y1 - 4 - gy0 + 1
	for yy in gh:
		for xx in gw:
			var c := Vector3.ZERO
			if lit:
				var glow := 1.0 - .35 * Vector2((xx - gw * .5) / gw, (yy - gh * .62) / gh).length()
				c = Vector3(238, 184, 92) * glow
				# A sagging curtain across the top and a shade pulled half down one side.
				if yy < 5 + 4 * absf(sin(xx / 9.0)):
					c = Vector3(150, 84, 60)
				elif xx < gw * .5 and yy < gh * .45:
					c = c * .62 + Vector3(70, 44, 30) * .38
			else:
				c = Vector3(30, 38, 48) + Vector3(16, 20, 22) * (float(yy) / gh)
				if (xx + yy) % 37 < 5 and yy < gh * .8:
					c += Vector3(26, 30, 32)
				c += Vector3(rng.randfn(0, 2.5), rng.randfn(0, 2.5), rng.randfn(0, 2.5))
			tile.put(gx0 + xx, gy0 + yy, Paint.rgb(c.x, c.y, c.z))
	# Muntins: one upright, one rail.
	var cx := (x0 + x1) / 2
	var cy := (y0 + y1) / 2
	Paint.rect(tile, cx - 1, y0, cx + 1, y1, frame)
	Paint.rect(tile, x0, cy - 1, x1, cy + 1, frame)
	# Sill with a lit top edge and a shadow under it.
	var sill := Color8(124, 130, 132) if metal else Color8(132, 108, 80)
	Paint.rect(tile, x0 - 5, y1 + 3, x1 + 5, y1 + 7, sill)
	Paint.rect(
		tile,
		x0 - 5,
		y1 + 3,
		x1 + 5,
		y1 + 3,
		Color8(mini(255, sill.r8 + 34), mini(255, sill.g8 + 34), mini(255, sill.b8 + 34))
	)
	Paint.rect(tile, x0 - 4, y1 + 8, x1 + 4, y1 + 8, edge)
	return tile


func foundation() -> Paint.Sheet:
	var tile := Paint.Sheet.new(128, 128)
	for y in 128:
		for x in 128:
			var grey := 96 + rng.randfn(0, 7) + lerpf(8, -14, y / 127.0)
			var c := Vector3(grey * 1.02, grey, grey * .95)
			# Poured in lifts: faint form lines, and block joints every 32 px.
			if y >= 40 and y < 44:
				c -= Vector3.ONE * 14
			if y >= 84 and y < 88:
				c -= Vector3.ONE * 12
			if x % 32 < 2:
				c -= Vector3.ONE * 16
			if y < 10:
				c += Vector3.ONE * 26  # the lip where the wall sits
			elif y < 14:
				c -= Vector3.ONE * 26
			if y >= 110:
				c -= Vector3.ONE * lerpf(0, 26, (y - 110) / 17.0)  # splash-back dirt
			tile.put(x, y, Paint.rgb(c.x, c.y, c.z))
	return tile


func eave() -> Paint.Sheet:
	var tile := Paint.Sheet.new(128, 128)
	for y in 128:
		for x in 128:
			var grain := rng.randfn(0, 5) + 6 * sin(x / 3.1)
			var c := Vector3(74 + grain, 54 + grain * .8, 38 + grain * .6)
			if y < 16:
				c += Vector3.ONE * 30  # the edge of the roofing over the board
			elif y < 22:
				c -= Vector3.ONE * 30
			if y >= 102:
				c -= Vector3.ONE * lerpf(4, 40, (y - 102) / 25.0)  # shadow thrown down the wall
			if y >= 22 and x % 64 < 2:
				c -= Vector3.ONE * 18  # board joints
			tile.put(x, y, Paint.rgb(c.x, c.y, c.z))
	return tile
