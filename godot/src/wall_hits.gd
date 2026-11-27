## Where a straight line from (x, y, z) along (ax, ay), rising `slope` a unit,
## meets a wall face about `distance` away: the hole it leaves (a
## View.WallMark with the wall's tile and material), or null. Pure
## geometry over the level's wall rows: play asks it (hitscan's material, a
## round through a wall, blood on a wall), so it lives beside the level, not
## in any view.
class_name WallHits
extends RefCounted


static func wall_mark(
	level: LevelData,
	x: float,
	y: float,
	z: float,
	ax: float,
	ay: float,
	slope: float,
	distance: float
) -> View.WallMark:
	var w := level.walls
	var n := level.wall_count
	var best := -1
	var best_error := INF
	var best_t := 0.0
	for i in n:
		var o := i * LevelData.WALL_STRIDE
		var ex := w[o + 2] - w[o]
		var ey := w[o + 3] - w[o + 1]
		var rx := w[o] - x
		var ry := w[o + 1] - y
		var den := ax * ey - ay * ex
		if absf(den) < 1e-6:
			continue
		var t := (rx * ey - ry * ex) / den
		var u := (rx * ay - ry * ax) / den
		if not (absf(t - distance) < .19 and t > .14 and u >= 0.0 and u <= 1.0):
			continue
		var height := z + t * slope
		if height <= w[o + 6] + .02 or height >= w[o + 7] - .02:
			continue
		if int(w[o + 4]) == level.tile_id("mirror"):
			continue
		var error := absf(t - distance)
		if error < best_error:
			best = i
			best_error = error
			best_t = t
	# The rakes too (a gable, a raked wall, a slope's side: geometry version 2,
	# LevelGeometry.rakes), their bottom and top at the hit's place along them.
	var rakes := level.geo.rakes if level.geo != null else PackedFloat32Array()
	var raked := false
	var stride := LevelGeometry.RAKE_STRIDE
	for o in range(0, rakes.size(), stride):
		var ex := rakes[o + 2] - rakes[o]
		var ey := rakes[o + 3] - rakes[o + 1]
		var rx := rakes[o] - x
		var ry := rakes[o + 1] - y
		var den := ax * ey - ay * ex
		if absf(den) < 1e-6:
			continue
		var t := (rx * ey - ry * ex) / den
		var u := (rx * ay - ry * ax) / den
		if not (absf(t - distance) < .19 and t > .14 and u >= 0.0 and u <= 1.0):
			continue
		var height := z + t * slope
		var bottom := lerpf(rakes[o + 6], rakes[o + 8], u)
		var top := lerpf(rakes[o + 7], rakes[o + 9], u)
		if height <= bottom + .02 or height >= top - .02:
			continue
		var error := absf(t - distance)
		if error < best_error:
			best = o
			raked = true
			best_error = error
			best_t = t
	if best < 0:
		return null
	if raked:
		w = rakes
	var o := best if raked else best * LevelData.WALL_STRIDE
	var ox := w[o + 2] - w[o]
	var oy := w[o + 3] - w[o + 1]
	var length := sqrt(ox * ox + oy * oy)
	var material := level.impact_surface(int(w[o + 4]))
	var kind := "stone" if material == "plaster" or material == "dirt" else material
	var mark := View.WallMark.new()
	mark.x = x + ax * best_t
	mark.y = y + ay * best_t
	mark.z = z + best_t * slope
	mark.ux = ox / length
	mark.uy = oy / length
	mark.image = "fx_hole_" + kind
	mark.radius = .051 if kind == "metal" else .060
	mark.material = material
	mark.tile = int(w[o + 4])
	return mark
