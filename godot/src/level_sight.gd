## A level's line of sight (LevelData.visible()): a stepped test along the
## line, quick over open floor, exact where panes, gates, furniture or the
## geometry's decks and stairs are in the way.
class_name LevelSight
extends RefCounted


## Mirrors TileMap.visible(): a stepped line-of-sight test.
static func visible(
	lv: LevelData, x: float, y: float, xx: float, yy: float, z: Variant = null, zz: Variant = null
) -> bool:
	# No heights given (z null): the flat test it always was, furniture in the
	# way whatever its height; geometry stops it where it stands in a body's
	# way (blocked(): a deck overhead does not, a stair or a wall does).
	var distance := sqrt((xx - x) * (xx - x) + (yy - y) * (yy - y))
	var n := maxi(1, ceili(distance * 9.0))
	# With no panes and no locked gates, a step whose four corners are open floor
	# and whose cell neither index lists is clear, as blocked() would find: those
	# steps (most of them) are tested here without the call.
	var plain := (
		lv.pane_tiles.is_empty()
		and lv.locked_gates.is_empty()
		and lv.index_cells.size() == lv.width * lv.height
	)
	var fast := plain and lv.clear_cells.size() == lv.width * lv.height
	var boxed := fast and lv.box_cells.size() == lv.width * lv.height
	# At heights on a level with geometry, a step in a cell the geometry alone
	# lists (no furniture, no door) whose heights lie outside the cell's sight
	# bands is clear too (LevelGeometry.sight_clear: what blocked() and
	# crosses() would find there, by a cheaper test that never says clear
	# where they would not).
	var banded := (
		plain
		and z != null
		and lv.geo != null
		and lv.furniture_cells.size() == lv.width * lv.height
		and lv.geo.sight_band_at.size() == lv.width * lv.height + 1
	)
	var z0 := LevelData._float(z) if banded else 0.0
	var z1 := LevelData._float(zz) if banded else 0.0
	var i := 1
	while i < n:
		var t := float(i) / float(n)
		var sx := x + (xx - x) * t
		var sy := y + (yy - y) * t
		if fast and sx >= 0.0 and sy >= 0.0:
			var cx := int(sx)
			var cy := int(sy)
			if cx < lv.width and cy < lv.height and lv.clear_cells[cy * lv.width + cx] != 0:
				i = _past_cell(x, y, xx, yy, n, i, cx, cy)
				continue
			if boxed and cx < lv.width and cy < lv.height and lv.box_cells[cy * lv.width + cx] != 0:
				var j := _past_cell(x, y, xx, yy, n, i, cx, cy)
				var t1 := float(j - 1) / float(n)
				if (
					_walls_clear(lv, cx, cy, sx, sy, x + (xx - x) * t1, y + (yy - y) * t1)
					and (
						lv.index_cells[cy * lv.width + cx] == 0
						or not _boxes_met(lv, cx, cy, x, y, xx, yy, z, zz, t, t1)
					)
				):
					i = j
					continue
		if plain:
			var ax := int(sx + -.023)
			var bx := int(sx + .023)
			var ay := int(sy + -.023)
			var by := int(sy + .023)
			if ax < 0 or ay < 0 or bx >= lv.width or by >= lv.height:
				return false
			if (
				lv.solid[ay * lv.width + ax] >= 0
				or lv.solid[by * lv.width + ax] >= 0
				or lv.solid[ay * lv.width + bx] >= 0
				or lv.solid[by * lv.width + bx] >= 0
			):
				return false
			var cell := int(sy) * lv.width + int(sx)
			if lv.index_cells[cell] == 0:
				i += 1
				continue
			if banded and lv.furniture_cells[cell] == 0:
				var step_z := z0 + (z1 - z0) * t
				var back_z := z0 + (z1 - z0) * (float(i - 1) / float(n))
				if lv.geo.sight_clear(cell, back_z, step_z):
					i += 1
					continue
		var wz: Variant = null
		if z != null:
			wz = LevelData._float(z) + (LevelData._float(zz) - LevelData._float(z)) * t
		if lv.blocked(sx, sy, .023, wz):
			return false
		if lv.geo != null and wz != null and lv.geo.cells[int(sy) * lv.width + int(sx)] != 0:
			# A steep look can step over a deck thinner than one step climbs.
			var bt := float(i - 1) / float(n)
			var bz := LevelData._float(z) + (LevelData._float(zz) - LevelData._float(z)) * bt
			if lv.geo.crosses(
				x + (xx - x) * bt, y + (yy - y) * bt, bz, sx, sy, LevelData._float(wz)
			):
				return false
		i += 1
	return true


## Whether the stretch from (ax, ay) to (bx, by), inside open cell cx, cy,
## stays out of the reach of blocked()'s corner tests (.023) from every solid
## cell round it (its box against each solid neighbour's side or corner),
## the cell itself still open (5v5 cover stands up again).
## False only means a step on it might touch one.
static func _walls_clear(
	lv: LevelData, cx: int, cy: int, ax: float, ay: float, bx: float, by: float
) -> bool:
	var reach := .023 + 1e-6
	var w := lv.width
	var c := cy * w + cx
	var low_x := minf(ax, bx) - cx >= reach
	var high_x := maxf(ax, bx) - cx <= 1.0 - reach
	var low_y := minf(ay, by) - cy >= reach
	var high_y := maxf(ay, by) - cy <= 1.0 - reach
	var solid := lv.solid
	if (
		solid[c] >= 0
		or (not low_x and solid[c - 1] >= 0)
		or (not high_x and solid[c + 1] >= 0)
		or (not low_y and solid[c - w] >= 0)
		or (not high_y and solid[c + w] >= 0)
	):
		return false
	return not (
		(not low_x and not low_y and solid[c - w - 1] >= 0)
		or (not high_x and not low_y and solid[c - w + 1] >= 0)
		or (not low_x and not high_y and solid[c + w - 1] >= 0)
		or (not high_x and not high_y and solid[c + w + 1] >= 0)
	)


## Whether the stretch of the sight line from t0 to t1 (all inside cell cx,
## cy) comes within blocked()'s reach of any box the fixtures' index lists
## there, at its heights when it has them. False means no step on it could be
## blocked by one; true only that it might (the steps are then tested).
static func _boxes_met(
	lv: LevelData,
	cx: int,
	cy: int,
	x: float,
	y: float,
	xx: float,
	yy: float,
	z: Variant,
	zz: Variant,
	t0: float,
	t1: float
) -> bool:
	var dx := xx - x
	var dy := yy - y
	var reach := .023 + 1e-4
	for f: PackedFloat32Array in lv.near_fixtures.get(Vector2i(cx, cy), LevelData.NOTHING):
		# The stretch clipped to the box grown by the reach (Liang-Barsky).
		var lo := t0
		var hi := t1
		var gx0 := x - (f[0] - reach)
		var gx1 := (f[2] + reach) - x
		var gy0 := y - (f[1] - reach)
		var gy1 := (f[3] + reach) - y
		if dx == 0.0:
			if gx0 < 0.0 or gx1 < 0.0:
				continue
		elif dx > 0.0:
			lo = maxf(lo, -gx0 / dx)
			hi = minf(hi, gx1 / dx)
		else:
			lo = maxf(lo, gx1 / dx)
			hi = minf(hi, -gx0 / dx)
		if dy == 0.0:
			if gy0 < 0.0 or gy1 < 0.0:
				continue
		elif dy > 0.0:
			lo = maxf(lo, -gy0 / dy)
			hi = minf(hi, gy1 / dy)
		else:
			lo = maxf(lo, gy1 / dy)
			hi = minf(hi, -gy0 / dy)
		if lo > hi:
			continue
		if z == null:
			return true
		var za := LevelData._float(z)
		var dz := LevelData._float(zz) - za
		var low := minf(za + dz * lo, za + dz * hi)
		var high := maxf(za + dz * lo, za + dz * hi)
		if high > f[7] - reach and low < f[4] + reach:
			return true
	return false


## The first of a sight line's n steps after step i (in clear cell cx, cy) that
## is outside that cell, or n. Worked out from where the line crosses the
## cell's sides, then checked with the steps' own sums: the step before it must
## be in the cell, and since the steps only ever move one way, so is every step
## between.
static func _past_cell(
	x: float, y: float, xx: float, yy: float, n: int, i: int, cx: int, cy: int
) -> int:
	var j := n
	var dx := xx - x
	var dy := yy - y
	if dx > 0.0:
		j = mini(j, ceili((float(cx + 1) - x) / dx * n))
	elif dx < 0.0:
		j = mini(j, ceili((float(cx) - x) / dx * n))
	if dy > 0.0:
		j = mini(j, ceili((float(cy + 1) - y) / dy * n))
	elif dy < 0.0:
		j = mini(j, ceili((float(cy) - y) / dy * n))
	j = clampi(j, i + 1, n)
	while j - 1 > i:
		var t := float(j - 1) / float(n)
		var sx := x + (xx - x) * t
		var sy := y + (yy - y) * t
		if sx >= 0.0 and sy >= 0.0 and int(sx) == cx and int(sy) == cy:
			break
		j -= 1
	return j
