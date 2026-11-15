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
			if lv.index_cells[int(sy) * lv.width + int(sx)] == 0:
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
