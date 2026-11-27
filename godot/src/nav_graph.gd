## The walkable places of a level with geometry as a graph for FlowField:
## node n < width * height is the cell n's own floor (the grid's, or the top
## of a solid slab standing on it: a stair tread, a ramp), the rest stand on
## decks over it. Edges join places a body can walk between both ways. Built
## by LevelNav.build_nav; typed as LevelGeometry.NavGraph (level_geometry.gd
## preloads this file under that name).
extends RefCounted

var count := 0
var cells := 0
var cell := PackedInt32Array()
var z := PackedFloat32Array()
## Orthogonal neighbours (CSR: first[n] .. first[n + 1] in edges).
var first := PackedInt32Array()
var edges := PackedInt32Array()
## Diagonal neighbours, the same way (only where both sides are walkable).
var dfirst := PackedInt32Array()
var dedges := PackedInt32Array()
## cell -> the deck nodes over it (a cell's own node is the cell).
var over := {}
## Ladders: each one's foot and top node (-1, -1 when it joins nothing),
## and n * count + m -> the ladder joining n and m (both ways).
var ladder_ends: Array[Vector2i] = []
var links := {}
## Whether each node's middle stands (LevelNav.stands), 1 or 0, as built
## (LevelNav.build_nav: the open floor FlowField measures; never baked, so
## empty for a graph read back).
var stood := PackedByteArray()


## The node a body at (x, y) with feet at z stands on (NAN: the cell's own).
func node_at(x: float, y: float, w: int, h: int, feet: float) -> int:
	if x < 0.0 or y < 0.0 or x >= w or y >= h:
		return -1
	var c := int(y) * w + int(x)
	if is_nan(feet) or not over.has(c):
		return c
	var best := c
	var best_z := z[c]
	for n: int in over[c]:
		var nz := z[n]
		if nz <= feet + .5 and (nz > best_z or best_z > feet + .5):
			best = n
			best_z = nz
	return best


func around(n: int) -> PackedInt32Array:
	return edges.slice(first[n], first[n + 1])
