## How far each open cell is from the player, in steps, out to RADIUS cells.
## An enemy that has lost sight of the player walks downhill on it, so it comes
## round walls and through doorways instead of sliding along the nearest wall
## toward where it last saw them (Enemy.tick). Worked out again when the player
## moves to another cell, at most a few times a second; the open floor is
## measured once per level, and only doors, gates and windows are asked again.
class_name FlowField
extends RefCounted

const RADIUS := 26
## The reach on a level with geometry (format 2).
const GEO_RADIUS := 44
const FAR := 1 << 20
## How wide a body the open floor has to fit.
const BODY := .2
const NEIGHBOURS := [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(1, -1),
	Vector2i(-1, 1),
	Vector2i(-1, -1)
]

var world: LevelData
## How many steps out it measures; the objective compass (Game.route) measures
## the whole level, and route_map.gd also walks through every closed door.
var reach := RADIUS
## With doors_open a closed door counts as open when the player could open it
## now: not a secret one, not one a station opens, and its key in `keys` (the
## game's own key ring). route_map.gd sets every_door to walk through them all.
var doors_open := false
var every_door := false
var keys := {}
var _door_at := {}
## The barred doors by cell (pass 15): with doors_open, a walk never crosses
## one shut from the side it does not open from.
var _bars := {}
var width := 0
var height := 0
## 0 wall, 1 open floor, 2 open unless a door, gate or window is in the way.
var open := PackedByteArray()
var steps := PackedInt32Array()
var origin := Vector2i(-1, -1)
var next_at := 0.0
## Cells a call walks at most (0: the whole walk at once). The objective
## compass walks the whole level, 5 to 10 ms in one frame: Game.route spreads
## it over a few frames, and the last finished answer stands until then.
var budget := 0
var _touched := PackedInt32Array()
## The walk under way: its steps, the cells it set, its queue.
var _next := PackedInt32Array()
var _next_touched := PackedInt32Array()
var _queue := PackedInt32Array()
var _head := 0
var _walked := false
## A level with geometry (format 2) walks its nav graph: node n below
## width * height is cell n's own floor, the rest stand on decks, so a field
## tells an upper floor from the one under it. null on every other level.
var graph: LevelGeometry.NavGraph = null
## LevelData.source_key -> that level's open floor as read (a level played
## again measures nothing: tens of milliseconds of its load), the last few.
const OPENS_KEPT := 4
static var _opens := {}


func _init(p_world: LevelData, floor_from: FlowField = null) -> void:
	world = p_world
	width = world.width
	height = world.height
	var nodes := width * height
	if world.geo != null:
		graph = world.geo.nav(world) if floor_from == null else floor_from.graph
		nodes = graph.count
		# Ways up and down (stairs, ramps) are longer than the flat way across.
		reach = GEO_RADIUS
	steps.resize(nodes)
	steps.fill(FAR)
	_next.resize(nodes)
	_next.fill(FAR)
	if floor_from != null:
		open = floor_from.open
		_door_at = floor_from._door_at
		_bars = floor_from._bars
		return
	for door: LevelData.Door in world.doors:
		for n in door_nodes(door):
			_door_at[n] = door
			if door.bar_side != 0:
				_bars[n] = door
	# The level as read, nothing opened yet: its open floor as measured the
	# last time it was played. A copy each way: a packed array in a Variant
	# is shared, and reopen() writes this one.
	var key := world.source_key if world.walls_version == 0 and world.solid_version == 0 else ""
	if key != "" and _opens.has(key):
		var kept: PackedByteArray = _opens[key]
		open = kept.duplicate()
		return
	_measure_open(nodes)
	if key != "":
		if _opens.size() >= OPENS_KEPT:
			_opens.erase(_opens.keys()[0])
		_opens[key] = open.duplicate()


## The places a door stands in: its cells (a door on the ground), or the
## nodes on its floor over them (a door up on a storey, pass 16).
func door_nodes(door: LevelData.Door) -> PackedInt32Array:
	var out := PackedInt32Array()
	for at: Vector2i in door.cells():
		if at.x < 0 or at.y < 0 or at.x >= width or at.y >= height:
			continue
		var c := at.y * width + at.x
		if door.raised() and graph != null:
			var n := graph.node_at(at.x + .5, at.y + .5, width, height, door.z + .1)
			if n >= 0 and absf(graph.z[n] - door.z) < .3:
				c = n
		out.append(c)
	return out


## The open floor of a level (open): 0 wall, 1 floor, 2 a door's, a pane's
## or a gate's.
func _measure_open(nodes: int) -> void:
	open.resize(nodes)
	var changing := {}
	# (A door up on a storey changes only the places on its floor: below.)
	for tile: Vector2i in world.near_doors:
		var low := not world.raised_doors
		if not low:
			for door: LevelData.Door in world.near_doors[tile]:
				low = low or not door.raised()
		if low:
			changing[tile.y * width + tile.x] = true
	for pane: Vector2i in world.pane_tiles:
		changing[pane.y * width + pane.x] = true
	for gate: LevelData.Gate in world.locked_gates:
		for gx in range(int(gate.x - gate.width * .5) - 1, int(gate.x + gate.width * .5) + 2):
			for gy in range(int(gate.y) - 1, int(gate.y) + 2):
				if gx >= 0 and gy >= 0 and gx < width and gy < height:
					changing[gy * width + gx] = true
	for pane: LevelData.GeoPane in world.geo_panes:
		# (A pane in the geometry: the cells round it on its floor.)
		var floor_z := pane.z0 - LevelGeometry.BODY
		for c in world._pane_reach(pane):
			if graph == null or absf(graph.z[c] - floor_z) <= 1.2:
				changing[c] = true
	# A door's own cell may be marked solid; the walls beside it never open.
	var door_cells := {}
	var upper := {}
	for door: LevelData.Door in world.doors:
		if door.raised():
			_raised_round(door, upper)
			for n in door_nodes(door):
				upper[n] = true
			continue
		for at: Vector2i in door.cells():
			changing[at.y * width + at.x] = true
			door_cells[at.y * width + at.x] = true
	# The nodes the geometry stands on or near, asked all at once (LevelNav
	# shares them out over the worker threads: pass 16).
	var asked := PackedInt32Array()
	for cy in height:
		for cx in width:
			var cell := cy * width + cx
			if world.solid[cell] >= 0 and not door_cells.has(cell):
				continue
			if changing.has(cell):
				open[cell] = 2
			elif graph != null and world.geo.cells[cell] != 0:
				asked.append(cell)
			elif not world.blocked(cx + .5, cy + .5, BODY) and not world.deep_at(cx + .5, cy + .5):
				open[cell] = 1
	if graph != null:
		for n in range(width * height, graph.count):
			asked.append(n)
		var stood := LevelNav.stands_all(world.geo, world, graph, asked)
		for k in asked.size():
			var n := asked[k]
			if n >= width * height:
				open[n] = stood[k]
			elif stood[k] == 1 and not world.deep_at(n % width + .5, n / width + .5):
				open[n] = 1
	for n: int in upper:
		if n < open.size() and (n >= width * height or open[n] != 0):
			open[n] = 2


## The places on a raised door's floor round it (its cells and the ring of
## cells round them, a barn door's run too) into `into`.
func _raised_round(door: LevelData.Door, into: Dictionary) -> void:
	if graph == null:
		return
	var reach := 1 if door.span <= 1 else door.span * 2
	var far_x := door.x + 1 if door.vertical else door.x + reach
	var far_y := door.y + reach if door.vertical else door.y + 1
	for cy in range(maxi(0, door.y - 1), mini(height - 1, far_y) + 1):
		for cx in range(maxi(0, door.x - 1), mini(width - 1, far_x) + 1):
			var n := graph.node_at(cx + .5, cy + .5, width, height, door.z + .1)
			if n >= 0 and absf(graph.z[n] - door.z) < .3:
				into[n] = true


## Measure the open floor again over a box of the map, from x0, y0 to x1, y1
## (furniture that stood there is gone: a crate shot to pieces), and measure
## the steps again from wherever they are measured from.
## Shut the open floor in a box something now fills (a set piece's rubble,
## features/set_pieces.gd), and measure again.
func close(x0: float, y0: float, x1: float, y1: float) -> void:
	var shut := false
	for cy in range(maxi(0, int(y0 - BODY)), mini(height - 1, int(y1 + BODY)) + 1):
		for cx in range(maxi(0, int(x0 - BODY)), mini(width - 1, int(x1 + BODY)) + 1):
			var cell := cy * width + cx
			if open[cell] == 1 and world.blocked(cx + .5, cy + .5, BODY):
				open[cell] = 0
				shut = true
	if shut:
		origin = Vector2i(-1, -1)
		next_at = 0.0


func reopen(x0: float, y0: float, x1: float, y1: float) -> void:
	for cy in range(maxi(0, int(y0 - BODY)), mini(height - 1, int(y1 + BODY)) + 1):
		for cx in range(maxi(0, int(x0 - BODY)), mini(width - 1, int(x1 + BODY)) + 1):
			var cell := cy * width + cx
			if open[cell] != 0 or world.solid[cell] >= 0:
				continue
			if not world.blocked(cx + .5, cy + .5, BODY) and not world.deep_at(cx + .5, cy + .5):
				open[cell] = 1
	origin = Vector2i(-1, -1)
	next_at = 0.0


func passable(cell: int) -> bool:
	var kind := open[cell]
	if kind == 2:
		if doors_open and _door_at.has(cell):
			var door: LevelData.Door = _door_at[cell]
			return (
				door.opened
				or every_door
				or (
					not door.secret
					and not door.blast_only
					and not world.controlled_doors.has(Vector2i(door.x, door.y))
					and (door.key == "" or keys.has(door.key))
				)
			)
		if cell >= width * height:
			# A place on a deck (a door or a pane up on a storey): asked at
			# its own height.
			return (doors_open and every_door) or not _node_blocked(cell)
		return (
			(doors_open and every_door)
			or not world.blocked(cell % width + .5, cell / width + .5, BODY)
		)
	return kind == 1


## Whether what moves (a door, a pane) stands in a body's way at node n's
## middle, at its height.
func _node_blocked(n: int) -> bool:
	var c := graph.cell[n]
	return world.geo.blocked_body(
		world, c % width + .5, c / width + .5, BODY, graph.z[n], LevelGeometry.BODY
	)


## Measure again from the player's cell if they have moved to another one
## (with a budget, go on with a walk under way first).
func update(x: float, y: float, clock: float, z := NAN) -> void:
	if _head < _queue.size():
		_walk()
	var here := Vector2i(int(x), int(y))
	if graph != null:
		var node := graph.node_at(x, y, width, height, z)
		here = Vector2i(node % width, node / width) if node >= 0 else Vector2i(-1, -1)
	if here == origin or clock < next_at:
		return
	origin = here
	next_at = clock + .25
	for cell in _next_touched:
		_next[cell] = FAR
	_next_touched.resize(0)
	_queue.resize(0)
	_head = 0
	var start := here.y * width + here.x
	if start >= 0 and start < steps.size():
		_next[start] = 0
		_next_touched.append(start)
		_queue.append(start)
	_walk()


## Whether a walk with a budget is still under way (the last finished one
## stands until it ends).
func walking() -> bool:
	return _head < _queue.size()


## Takes the field `other` walked from the cell this one would walk from now
## (the same level, the same tick: the same answer), as update() would have
## left it after walking: what it had becomes the scratch field it clears next.
func adopt(other: FlowField, clock: float) -> void:
	origin = other.origin
	next_at = clock + .25
	_next = steps
	_next_touched = _touched
	# Copies: packed arrays are shared by reference, and each field walks into
	# its own in place.
	steps = other.steps.duplicate()
	_touched = other._touched.duplicate()
	_queue.resize(0)
	_head = 0
	_walked = true


## Walk on from the queue (all of it, or `budget` cells; the first walk always
## all of it, so there is an answer from the start); a finished walk becomes
## the field.
func _walk() -> void:
	var stop := _queue.size() + width * height
	if budget > 0 and _walked:
		stop = _head + budget
	# (passable() written out for the open and the wall cells, the most of
	# them; the same cells in the same order.)
	var kinds := open
	var bars := doors_open and not every_door and not _bars.is_empty()
	if graph != null:
		var first := graph.first
		var edges := graph.edges
		while _head < _queue.size() and _head < stop:
			var cell := _queue[_head]
			_head += 1
			var d := _next[cell]
			if d >= reach:
				continue
			for e in range(first[cell], first[cell + 1]):
				var next := edges[e]
				if _next[next] != FAR:
					continue
				var kind := kinds[next]
				if kind == 0 or (kind == 2 and not passable(next)):
					continue
				if bars and _bars.has(cell) and _barred(cell, graph.cell[next]):
					continue
				_next[next] = d + 1
				_next_touched.append(next)
				_queue.append(next)
	else:
		while _head < _queue.size() and _head < stop:
			var cell := _queue[_head]
			_head += 1
			var d := _next[cell]
			if d >= reach:
				continue
			var cx := cell % width
			var cy := cell / width
			for k in 4:
				var n: Vector2i = NEIGHBOURS[k]
				var nx := cx + n.x
				var ny := cy + n.y
				if nx < 0 or ny < 0 or nx >= width or ny >= height:
					continue
				var next := ny * width + nx
				if _next[next] != FAR:
					continue
				var kind := kinds[next]
				if kind == 0 or (kind == 2 and not passable(next)):
					continue
				if bars and _bars.has(cell) and _barred(cell, next):
					continue
				_next[next] = d + 1
				_next_touched.append(next)
				_queue.append(next)
	if _head < _queue.size():
		return
	var done := _next
	_next = steps
	steps = done
	var was_touched := _next_touched
	_next_touched = _touched
	_touched = was_touched
	_queue.resize(0)
	_head = 0
	_walked = true


## Whether a walk out of barred door cell `cell` into cell `to` would be a
## way in through it from the side it does not open from (the walk goes out
## from where the way ends: a step out of the door to `to` is a body coming
## from `to` through the door).
func _barred(cell: int, to: int) -> bool:
	var door: LevelData.Door = _bars[cell]
	if door.opened:
		return false
	var side := to % width - door.x if door.vertical else to / width - door.y
	return side * door.bar_side < 0


## The heading from x, y one cell downhill toward the player, or NAN when the
## field does not reach there.
func heading(x: float, y: float, z := NAN) -> float:
	if graph != null:
		var here := graph.node_at(x, y, width, height, z)
		var n := downhill_node(here)
		if n < 0:
			return NAN
		# (Through the via point an edge bends through, while it lies ahead:
		# pass 16.)
		var to := graph.toward(here, n, x, y, width)
		return atan2(to.y - y, to.x - x)
	var to := downhill(Vector2i(int(x), int(y)))
	if to.x < 0:
		return NAN
	return atan2(to.y + .5 - y, to.x + .5 - x)


## The neighbouring cell one step nearer, or (-1, -1) when there is none.
func downhill(at: Vector2i) -> Vector2i:
	var cx := at.x
	var cy := at.y
	if cx < 0 or cy < 0 or cx >= width or cy >= height:
		return Vector2i(-1, -1)
	var best := steps[cy * width + cx]
	var to := Vector2i(-1, -1)
	if best >= FAR:
		return to
	var bars := doors_open and not every_door and not _bars.is_empty()
	for n: Vector2i in NEIGHBOURS:
		var nx := cx + n.x
		var ny := cy + n.y
		if nx < 0 or ny < 0 or nx >= width or ny >= height:
			continue
		if bars and _bars.has(ny * width + nx) and _barred(ny * width + nx, cy * width + cx):
			continue  # into a barred door from the side it does not open from
		var d := steps[ny * width + nx]
		# A diagonal step only where both cells beside it are open too.
		if (
			d < best
			and (
				n.x == 0
				or n.y == 0
				or (steps[cy * width + nx] < FAR and steps[ny * width + cx] < FAR)
			)
		):
			best = d
			to = Vector2i(nx, ny)
	return to


## The node one step nearer than node n (the nav graph's), or -1.
func downhill_node(n: int) -> int:
	if n < 0 or n >= steps.size():
		return -1
	var best := steps[n]
	if best >= FAR:
		return -1
	var to := -1
	var bars := doors_open and not every_door and not _bars.is_empty()
	for e in range(graph.first[n], graph.first[n + 1]):
		var m := graph.edges[e]
		if bars and _bars.has(m) and _barred(m, graph.cell[n]):
			continue  # into a barred door from the side it does not open from
		if steps[m] < best:
			best = steps[m]
			to = m
	for e in range(graph.dfirst[n], graph.dfirst[n + 1]):
		var m := graph.dedges[e]
		if steps[m] < best and _sides_open(n, m):
			best = steps[m]
			to = m
	return to


## A diagonal step from n to m only where both cells beside it are reached
## too (as downhill() asks of the grid): never across a corner of wall or water.
func _sides_open(n: int, m: int) -> bool:
	var sides := 0
	for e in range(graph.first[n], graph.first[n + 1]):
		var a := graph.edges[e]
		if steps[a] >= FAR:
			continue
		for e2 in range(graph.first[a], graph.first[a + 1]):
			if graph.edges[e2] == m:
				sides += 1
				break
	return sides >= 2


## The centre of the cell `hops` steps downhill from x, y (x, y itself when it
## is out of reach), and the cells walked on the way.
func waypoint(x: float, y: float, hops: int, path: Array = [], z := NAN) -> Vector2:
	if graph != null:
		var n := graph.node_at(x, y, width, height, z)
		var went := false
		for _i in hops:
			var m := downhill_node(n)
			if m < 0:
				break
			n = m
			went = true
			path.append(Vector2i(graph.cell[m] % width, graph.cell[m] / width))
		if not went:
			return Vector2(x, y)
		return Vector2(graph.cell[n] % width + .5, graph.cell[n] / width + .5)
	var at := Vector2i(int(x), int(y))
	var moved := false
	for _i in hops:
		var to := downhill(at)
		if to.x < 0:
			break
		at = to
		moved = true
		path.append(at)
	return Vector2(at.x + .5, at.y + .5) if moved else Vector2(x, y)


## Steps from x, y to the player (FAR when out of reach).
func distance(x: float, y: float, z := NAN) -> int:
	var cx := int(x)
	var cy := int(y)
	if cx < 0 or cy < 0 or cx >= width or cy >= height:
		return FAR
	if graph != null:
		return steps[graph.node_at(x, y, width, height, z)]
	return steps[cy * width + cx]
