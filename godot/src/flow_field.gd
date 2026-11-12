## How far each open cell is from the player, in steps, out to RADIUS cells.
## An enemy that has lost sight of the player walks downhill on it, so it comes
## round walls and through doorways instead of sliding along the nearest wall
## toward where it last saw them (Enemy.tick). Worked out again when the player
## moves to another cell, at most a few times a second; the open floor is
## measured once per level, and only doors, gates and windows are asked again.
class_name FlowField
extends RefCounted

const RADIUS := 26
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


func _init(p_world: LevelData, floor_from: FlowField = null) -> void:
	world = p_world
	width = world.width
	height = world.height
	steps.resize(width * height)
	steps.fill(FAR)
	_next.resize(width * height)
	_next.fill(FAR)
	if floor_from != null:
		open = floor_from.open
		_door_at = floor_from._door_at
		return
	open.resize(width * height)
	var changing := {}
	for tile: Vector2i in world.near_doors:
		changing[tile.y * width + tile.x] = true
	for pane: Vector2i in world.pane_tiles:
		changing[pane.y * width + pane.x] = true
	for gate: LevelData.Gate in world.locked_gates:
		for gx in range(int(gate.x - gate.width * .5) - 1, int(gate.x + gate.width * .5) + 2):
			for gy in range(int(gate.y) - 1, int(gate.y) + 2):
				if gx >= 0 and gy >= 0 and gx < width and gy < height:
					changing[gy * width + gx] = true
	# A door's own cell may be marked solid; the walls beside it never open.
	var door_cells := {}
	for door: LevelData.Door in world.doors:
		changing[door.y * width + door.x] = true
		door_cells[door.y * width + door.x] = true
		_door_at[door.y * width + door.x] = door
	for cy in height:
		for cx in width:
			var cell := cy * width + cx
			if world.solid[cell] >= 0 and not door_cells.has(cell):
				continue
			if changing.has(cell):
				open[cell] = 2
			elif not world.blocked(cx + .5, cy + .5, BODY) and not world.deep_at(cx + .5, cy + .5):
				open[cell] = 1


## Measure the open floor again over a box of the map, from x0, y0 to x1, y1
## (furniture that stood there is gone: a crate shot to pieces), and measure
## the steps again from wherever they are measured from.
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
		return (
			(doors_open and every_door)
			or not world.blocked(cell % width + .5, cell / width + .5, BODY)
		)
	return kind == 1


## Measure again from the player's cell if they have moved to another one
## (with a budget, go on with a walk under way first).
func update(x: float, y: float, clock: float) -> void:
	if _head < _queue.size():
		_walk()
	var here := Vector2i(int(x), int(y))
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


## Walk on from the queue (all of it, or `budget` cells; the first walk always
## all of it, so there is an answer from the start); a finished walk becomes
## the field.
func _walk() -> void:
	var stop := _queue.size() + width * height
	if budget > 0 and _walked:
		stop = _head + budget
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
			if _next[next] != FAR or not passable(next):
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


## The heading from x, y one cell downhill toward the player, or NAN when the
## field does not reach there.
func heading(x: float, y: float) -> float:
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
	for n: Vector2i in NEIGHBOURS:
		var nx := cx + n.x
		var ny := cy + n.y
		if nx < 0 or ny < 0 or nx >= width or ny >= height:
			continue
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


## The centre of the cell `hops` steps downhill from x, y (x, y itself when it
## is out of reach), and the cells walked on the way.
func waypoint(x: float, y: float, hops: int, path: Array = []) -> Vector2:
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
func distance(x: float, y: float) -> int:
	var cx := int(x)
	var cy := int(y)
	if cx < 0 or cy < 0 or cx >= width or cy >= height:
		return FAR
	return steps[cy * width + cx]
