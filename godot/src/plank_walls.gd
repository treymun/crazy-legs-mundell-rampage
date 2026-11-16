## The level side of plank walls that break (features/wall_breaks.gd keeps
## which and when; LevelData has no room left for these): cutting a merged run
## of a repeating plank wall (LevelTiles.TILED: a barn's boards, a shed's) at
## one cell so that cell's part can be shot about or taken out alone, and
## opening a shed's wall under its roof: the gap takes the inside's roof,
## ceiling, floor, light and area (the roof runs on over it), and whatever of
## the wall stands wholly above that roof (a barn's gable) stays where it is.
## Pure arithmetic on the level's own lists, the same on every machine.
class_name PlankWalls
extends RefCounted


## Cuts every piece lying along cell (cx, cy)'s own edges (LevelEdit.EDGES,
## that way round) but longer than the edge at the edge's ends: the piece
## keeps its place in the list as its first part, the rest go at the end.
## The 3D view builds the chunks they were and are in again
## (LevelData.retiled). True when anything was cut.
static func split(w: LevelData, cx: int, cy: int) -> bool:
	var cut := false
	var count := w.wall_count
	for e: Array in LevelEdit.EDGES:
		var ex0: int = e[2]
		var ey0: int = e[3]
		var ex1: int = e[4]
		var ey1: int = e[5]
		var a := Vector2(cx + ex0, cy + ey0)
		var b := Vector2(cx + ex1, cy + ey1)
		var dir := b - a
		for i in count:
			var o := i * LevelData.WALL_STRIDE
			var pa := Vector2(w.walls[o], w.walls[o + 1])
			var pb := Vector2(w.walls[o + 2], w.walls[o + 3])
			if pa == a and pb == b:
				continue
			var along := pb - pa
			var length := along.length()
			if length <= 1.001 or not along.normalized().is_equal_approx(dir):
				continue
			# On the edge's own line, and over all of it.
			if absf((a - pa).cross(dir)) > .0001:
				continue
			var ta := (a - pa).dot(dir)
			var tb := (b - pa).dot(dir)
			if ta < -.0001 or tb > length + .0001:
				continue
			var row := w.walls.slice(o, o + LevelData.WALL_STRIDE)
			var parts: Array[Vector4] = []
			if ta > .0001:
				parts.append(Vector4(pa.x, pa.y, a.x, a.y))
			parts.append(Vector4(a.x, a.y, b.x, b.y))
			if tb < length - .0001:
				parts.append(Vector4(b.x, b.y, pb.x, pb.y))
			w.retiled.append((pa + pb) * .5)
			for k in parts.size():
				var part: Vector4 = parts[k]
				var piece := row.duplicate()
				piece[0] = part.x
				piece[1] = part.y
				piece[2] = part.z
				piece[3] = part.w
				if k == 0:
					for j in LevelData.WALL_STRIDE:
						w.walls[o + j] = piece[j]
				else:
					w.walls.append_array(piece)
				w.retiled.append(Vector2((part.x + part.z) * .5, (part.y + part.w) * .5))
			cut = true
	if cut:
		w.wall_count = w.walls.size() / LevelData.WALL_STRIDE
		w._edge_index = {}
		w._active_key = []
	return cut


## Opens the shed's wall cell (cx, cy) into the roofed cell `inside` (its
## index): the gap is under the same roof (its roof, ceiling, floor, light and
## area the inside's), then LevelData.open_cell, keeping the pieces on its
## own edges that stand wholly at or above the roof.
static func open_shed(w: LevelData, cx: int, cy: int, inside: int, faces: Dictionary) -> void:
	var c := cy * w.width + cx
	var top := w.roof[inside]
	w.roof[c] = top
	w.ceiling_tile[c] = w.ceiling_tile[inside]
	w.floor_tile[c] = w.floor_tile[inside]
	w.light[c] = w.light[inside]
	w.area[c] = w.area[inside]
	var kept := PackedFloat32Array()
	for e: Array in LevelEdit.EDGES:
		var ex0: int = e[2]
		var ey0: int = e[3]
		var ex1: int = e[4]
		var ey1: int = e[5]
		for i in w.walls_on(cx + ex0, cy + ey0, cx + ex1, cy + ey1):
			var o := i * LevelData.WALL_STRIDE
			if w.walls[o + 6] >= top - .01:
				kept.append_array(w.walls.slice(o, o + LevelData.WALL_STRIDE))
	w.open_cell(cx, cy, faces)
	if not kept.is_empty():
		w.walls.append_array(kept)
		w.wall_count = w.walls.size() / LevelData.WALL_STRIDE
		w._edge_index = {}
		w._active_key = []


## The tile, bottom and top of every piece covering each unit edge on the grid
## (a merged run counted on each edge it covers), keyed by the edge that way
## round: what a wall cell shows on each side before anything is cut.
static func coverage(w: LevelData) -> Dictionary:
	var out := {}
	for i in w.wall_count:
		var o := i * LevelData.WALL_STRIDE
		var a := Vector2(w.walls[o], w.walls[o + 1])
		var b := Vector2(w.walls[o + 2], w.walls[o + 3])
		var d := b - a
		if a != a.floor() or b != b.floor() or (d.x != 0.0 and d.y != 0.0) or d == Vector2.ZERO:
			continue
		var n := roundi(d.length())
		var u := d / d.length()
		for k in n:
			var p := a + u * k
			var key := Vector4(p.x, p.y, p.x + u.x, p.y + u.y)
			if not out.has(key):
				out[key] = []
			var list: Array = out[key]
			list.append(Vector3(w.walls[o + 4], w.walls[o + 6], w.walls[o + 7]))
	return out
