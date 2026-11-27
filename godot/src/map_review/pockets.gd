## Dead ends on a level's open floor (MapReview's loops check): the open
## cells as a 4-way grid walked from the start, and every pocket that hangs
## off a single cell (a cut vertex: block it and the pocket is cut off).
## A pocket with nothing in it, as deep as it is, is a walk for nothing.
class_name MapPockets
extends RefCounted


## The empty pockets, biggest first and none inside another reported one:
## [{cut: the cell it hangs off, deep: steps from it to the pocket's far end,
## size: cells}]. `open` 1 for open floor; `stuff` 1 where something is.
static func empty_pockets(
	open: PackedByteArray, stuff: PackedByteArray, w: int, h: int, start: int
) -> Array[Dictionary]:
	var n := w * h
	var disc := PackedInt32Array()
	disc.resize(n)
	disc.fill(-1)
	var low := PackedInt32Array()
	low.resize(n)
	var parent := PackedInt32Array()
	parent.resize(n)
	parent.fill(-1)
	var size := PackedInt32Array()
	size.resize(n)
	var order := PackedInt32Array()
	var stack := PackedInt32Array()
	var next := PackedInt32Array()
	disc[start] = 0
	low[start] = 0
	order.append(start)
	stack.append(start)
	next.append(0)
	var t := 1
	var cands := PackedInt32Array()
	while not stack.is_empty():
		var top := stack.size() - 1
		var v := stack[top]
		var k := next[top]
		if k < 4:
			next[top] = k + 1
			var u := _neighbour(v, k, w, h)
			if u < 0 or open[u] == 0:
				continue
			if disc[u] < 0:
				parent[u] = v
				disc[u] = t
				low[u] = t
				t += 1
				order.append(u)
				stack.append(u)
				next.append(0)
			elif u != parent[v]:
				low[v] = mini(low[v], disc[u])
			continue
		stack.resize(top)
		next.resize(top)
		size[v] += 1
		var p := parent[v]
		if p >= 0:
			low[p] = mini(low[p], low[v])
			size[p] += size[v]
			if low[v] >= disc[p] and p != start:
				cands.append(v)
	# Steps from the start (every way into a pocket passes its cut).
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(-1)
	dist[start] = 0
	var queue := PackedInt32Array([start])
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for k in 4:
			var u := _neighbour(c, k, w, h)
			if u >= 0 and open[u] == 1 and dist[u] < 0:
				dist[u] = dist[c] + 1
				queue.append(u)
	var pre := PackedInt32Array()
	pre.resize(order.size() + 1)
	for i in order.size():
		pre[i + 1] = pre[i] + (1 if stuff[order[i]] != 0 else 0)
	var ranked: Array[Vector2i] = []
	for v in cands:
		ranked.append(Vector2i(size[v], v))
	ranked.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x > b.x)
	var out: Array[Dictionary] = []
	var taken: Array[Vector2i] = []
	for r in ranked:
		var v := r.y
		var a := disc[v]
		var b := a + size[v]
		if pre[b] - pre[a] != 0:
			continue
		var inside := false
		for span in taken:
			if a >= span.x and b <= span.y:
				inside = true
				break
		if inside:
			continue
		var cut := parent[v]
		var far := 0
		for i in range(a, b):
			far = maxi(far, dist[order[i]])
		taken.append(Vector2i(a, b))
		out.append({"cut": cut, "deep": far - dist[cut], "size": size[v]})
	return out


static func _neighbour(c: int, k: int, w: int, h: int) -> int:
	var x := c % w
	var y := c / w
	match k:
		0:
			x += 1
		1:
			x -= 1
		2:
			y += 1
		_:
			y -= 1
	if x < 0 or y < 0 or x >= w or y >= h:
		return -1
	return y * w + x
