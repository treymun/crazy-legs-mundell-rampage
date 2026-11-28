## Walls that break: the windows painted on building walls shoot out, and the
## plank fences get shot about and then broken through.
##
## A window is a wall piece showing a window tile (<material>_win or _lit, the
## trailers' trailer_window): a shot into its glass, or a blast near it, swaps
## its picture for <material>_brk (tools/art/wall_break_art.gd: the room dark
## behind teeth of glass, so a lit one goes dark; a blast's <material>_bst,
## its frame torn out too), throws glass and plays the window cue. It stays a
## wall. A light round only shows it cracked, its glass held in its frame
## (`cracked`), until the next round, a blast or a body: play had it broken
## at the first all the same. How it looks is features/wall_looks.gd's, told
## where and how each window and fence cell was struck. A fence cell is a
## solid cell of a tile with a [fence.<tile>] section in
## data/tuning/breakables.cfg: shots and blasts take
## its hp, at `damaged` of it its faces show the `hit` tile (boards out), and at
## none it opens (LevelData.open_cell): floor for bodies, sight and shots, both
## flow fields reopen it, the cells beside it show their own face toward it and
## the `broken` picture stands in the gap.
##
## What may never open: a cell on the map's edge, one under a roof or beside
## ground at another height, one with a sign, a fixture or a free wall piece on
## it, and one whose opening would join two stretches of floor that are not
## joined now with every door the player cannot simply walk through shut (a
## key, a station, a trigger, a secret, a blast) and every gate shut: it gets
## shot about but holds (_find_fences, tools/break_check.gd). The Crossroads
## breaks nothing. Nothing about the walls changes until something breaks, so
## the view is the same picture until then.
##
## Plank walls too (a [fence.<tile>] with `sheds`, `under_roof`, `straight`):
## a shed's wall of boards between its roofed floor and the open air opens
## under its roof (src/plank_walls.gd: the gap takes the inside's roof and
## light, a gable above stays), a pen's fence under a barn's roof opens with
## the roof kept, and a straight run of planks in a yard opens like the
## stockyard's. A wall of a repeating tile (a barn's boards) is cut at the cell
## first (PlankWalls.split) so only that cell's part comes away. Such a wall
## opens only where it is plain boards both sides, has no window, door, gate
## or deck beside it and a roof at least a body's height over the gap; one
## that may not open is left whole (`only_open`).
##
## game_combat.gd tells it where each hitscan shot, pellet or swing met a wall
## (strike()) and every blast (blast()). What is broken saves in the feature's
## block; a save from before it restores with nothing broken.
extends GameFeature

const Breakables := preload("res://src/features/breakables.gd")
const PATH := "res://data/tuning/breakables.cfg"
## strike()'s answers: nothing here to break, or the shot went in through a
## window's glass (now or already gone), so it leaves no hole on it.
const NONE := 0
const HOLE := 1
## crash()'s answer when the fence it hit broke through (the body goes on).
const OPENED := 2
## How a wall was struck, for its looks (features/wall_looks.gd): a round, a
## blast, a body thrown into it.
const SHOT := 0
const BLAST := 1
const BODY := 2
## Where the glass is on a window face: across it (as a share of its length),
## and up it, by world height for a tile laid by height (RenderState's
## WINDOW_SILL to WINDOW_HEAD) or as shares of the piece's height down from
## its top for one stretched over it.
const ACROSS := Vector2(.2, .8)
const DOWN := Vector2(.26, .68)


## One window face: the wall piece on `edge` (as the list keeps it) of a solid
## cell, showing `whole`, `shot` once broken; the glass from `low` to `high`.
class WindowFace:
	var cell := Vector2i.ZERO
	var edge := Vector4.ZERO
	var whole := 0
	var shot := 0
	## Broken but still in its frame, cracked (a light round's: the glass
	## shows its web, features/wall_looks.gd, until the next round, a blast or
	## a body shoots it out). Play is the same either way: it broke.
	var cracked := false
	## Shot out by a blast: <material>_bst (its frame torn out too; -1 none).
	var blast := -1
	var blasted := false
	var low := 0.0
	var high := 0.0
	var broken := false

	func normal() -> Vector2:
		return Vector2(edge.w - edge.y, edge.x - edge.z).normalized()

	func middle() -> Vector2:
		return Vector2((edge.x + edge.z) * .5, (edge.y + edge.w) * .5)


## One fence cell.
class Fence:
	var cell := Vector2i.ZERO
	var tile := 0
	var hit_tile := 0
	var spec := {}
	var hp := 1.0
	var most := 1.0
	## 0 whole, 1 shot about, 2 broken through.
	var stage := 0
	var opens := false
	## Which way the fence runs through it: along x, else along y.
	var along_x := true
	var top := 1.0
	## A shed's wall: the roofed cell it opens into (its index; -1: none), and
	## a pen's fence under a roof (its neighbours' faces only their own height).
	var inside := -1
	var low := false


var windows: Array = []
## Window faces by their solid cell.
var by_cell := {}
## Fence cells by cell.
var fences := {}
## The pictures standing in fence cells broken through (two each, one a side).
var gaps: Array = []
var win := {}
var dice := RandomNumberGenerator.new()
## A fence's tile -> its `hit` tile: what a face turned toward a gap shows.
var _faces := {}
## While finding the fences: the free wall pieces by cell (_loose_pieces),
## what covers each edge (PlankWalls.coverage) and the doors, gates and panes
## by cell (a shed's wall beside one holds).
var _loose := {}
var _cover := {}
var _ways := {}
## While it is worked out: the boards' and props' places by cell, the
## collision volumes by the cells they cover (the few very big ones apart).
var _spots := {}
var _volumes := {}
var _big_volumes: Array = []
var _crash_next := -1.0
## Counts every change to a window or fence (broken, hp, stage): a host's
## NetTrack looks through the lists in NET_GUARDED only when it moved, so
## anything that changes one of them bumps it (game_host.gd).
var net_version := 0
const NET_GUARDED := ["windows", "fences"]


func id() -> String:
	return "wall_breaks"


func attach() -> void:
	dice.seed = 1931
	var cfg := Tuning.file(PATH)
	win = _section(cfg, "windows")
	var world: LevelData = game.world
	var never: Array = win.get("never", [])
	if never.has(world.id) or not world.road_and_hub.is_empty():
		return
	_find_windows()
	_find_fences(cfg)
	for f: Fence in fences.values():
		game.art.art(str(f.spec.get("broken", "")))


static func _section(cfg: ConfigFile, name: String) -> Dictionary:
	var out := {}
	if cfg.has_section(name):
		for key: String in cfg.get_section_keys(name):
			out[key] = cfg.get_value(name, key)
	return out


# ------------------------------------------------------------------ finding


## Every wall piece showing a window that has a broken tile, on the grid, a
## cell's face.
func _find_windows() -> void:
	var world: LevelData = game.world
	var shot_of := {}
	var blast_of := {}
	for i in world.tile_names.size():
		var name := String(world.tile_names[i])
		for tail: String in ["_window", "_win", "_lit"]:
			if name.ends_with(tail):
				var base := name.trim_suffix(tail)
				var broken := world.tile_id(base + "_brk")
				if broken >= 0:
					shot_of[i] = broken
				blast_of[i] = world.tile_id(base + "_bst")
				break
	var stride := LevelData.WALL_STRIDE
	for i in world.wall_count:
		var o := i * stride
		var tile := int(world.walls[o + 4])
		if not shot_of.has(tile):
			continue
		var face := WindowFace.new()
		face.edge = Vector4(
			world.walls[o], world.walls[o + 1], world.walls[o + 2], world.walls[o + 3]
		)
		var along := Vector2(face.edge.z - face.edge.x, face.edge.w - face.edge.y)
		if along.length() != 1.0 or (along.x != 0.0 and along.y != 0.0):
			continue
		var behind := face.middle() - face.normal() * .5
		face.cell = Vector2i(floori(behind.x), floori(behind.y))
		if world.solid[face.cell.y * world.width + face.cell.x] < 0:
			continue
		face.whole = tile
		face.shot = shot_of[tile]
		face.blast = blast_of.get(tile, -1)
		var bottom: float = world.walls[o + 6]
		var top: float = world.walls[o + 7]
		if (
			LevelTiles.window_band(String(world.tile_names[tile]))
			and world.tile_id(String(world.tile_names[tile]).left(-4)) >= 0
		):
			face.low = LevelTiles.WINDOW_SILL
			face.high = LevelTiles.WINDOW_HEAD
		else:
			face.low = top - DOWN.y * (top - bottom)
			face.high = top - DOWN.x * (top - bottom)
		windows.append(face)
		if not by_cell.has(face.cell):
			by_cell[face.cell] = []
		var in_cell: Array = by_cell[face.cell]
		in_cell.append(face)


## Every fence cell, and which of them may open.
func _find_fences(cfg: ConfigFile) -> void:
	var world: LevelData = game.world
	var specs := {}
	for section: String in cfg.get_sections():
		if not section.begins_with("fence."):
			continue
		var name := section.substr(6)
		var spec := _section(cfg, section)
		var never: Array = spec.get("never", [])
		if never.has(world.id):
			continue  # a level whose fences hold (the 5v5 maps: no new lanes mid-match)
		var tile := world.tile_id(name)
		var hit := world.tile_id(str(spec.get("hit", "")))
		if tile < 0 or hit < 0:
			continue
		if not game.art.has_art(str(spec.get("broken", ""))):
			continue
		specs[tile] = spec
		_faces[tile] = hit
	if specs.is_empty():
		return
	var w := world.width
	for cy in world.height:
		for cx in w:
			var tile := world.solid[cy * w + cx]
			if not specs.has(tile):
				continue
			var f := Fence.new()
			f.cell = Vector2i(cx, cy)
			f.tile = tile
			f.hit_tile = _faces[tile]
			f.spec = specs[tile]
			f.most = f.spec.get("hp", 100.0)
			f.hp = f.most
			f.top = world.wall_height[cy * w + cx]
			# Along its own fence first, else along whatever it meets.
			var by_x := _tile(cx - 1, cy) == tile or _tile(cx + 1, cy) == tile
			var by_y := _tile(cx, cy - 1) == tile or _tile(cx, cy + 1) == tile
			if by_x == by_y:
				by_x = _tile(cx - 1, cy) >= 0 or _tile(cx + 1, cy) >= 0
				by_y = _tile(cx, cy - 1) >= 0 or _tile(cx, cy + 1) >= 0
			f.along_x = by_x or not by_y
			fences[f.cell] = f
	_loose_pieces()
	_cover = PlankWalls.coverage(world)
	for door: LevelData.Door in world.doors:
		_ways[Vector2i(door.x, door.y)] = true
	for pane: Vector2i in world.pane_tiles:
		_ways[pane] = true
	for gate: Variant in world.locked_gates:
		var g: LevelData.Gate = gate
		_ways[Vector2i(floori(g.x), floori(g.y))] = true
	_index_things()
	_rule()
	_loose = {}
	_cover = {}
	_ways = {}
	_spots = {}
	_volumes = {}
	_big_volumes = []
	# A plank wall that may not open stays as built (no boards shot off a
	# building's corner, a run of them cut for nothing).
	for key: Vector2i in fences.keys():
		var f: Fence = fences[key]
		if not f.opens and f.spec.get("only_open", false):
			fences.erase(key)


## A cell's solid tile (-1 open, or off the map).
func _tile(cx: int, cy: int) -> int:
	var world: LevelData = game.world
	if cx < 0 or cy < 0 or cx >= world.width or cy >= world.height:
		return -1
	return world.solid[cy * world.width + cx]


## Which fence cells may open. Each stretch of floor the player can walk
## (doors shut that a key, a station, a trigger, a secret or a blast opens) is
## labelled; a cell opens only if every open cell beside it is one stretch's,
## counting the cells already let open, so no set of them ever joins two.
func _rule() -> void:
	var world: LevelData = game.world
	var label := regions(game)
	var w := world.width
	var keys: Array = fences.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y * w + a.x < b.y * w + b.x)
	for key: Vector2i in keys:
		var f: Fence = fences[key]
		if not _may_open(f):
			continue
		var found := -1
		var one := true
		for e: Array in LevelEdit.EDGES:
			var ex: int = e[0]
			var ey: int = e[1]
			var n := Vector2i(f.cell.x + ex, f.cell.y + ey)
			var at := label[n.y * w + n.x]
			if at < 0:
				continue
			if found >= 0 and at != found:
				one = false
			found = at
		if one and found >= 0:
			f.opens = true
			label[f.cell.y * w + f.cell.x] = found


## Whether a fence cell could open without leaving anything hanging or a step
## to draw: inside the map's edge, under the sky, the ground beside it level
## with its own, nothing standing on it or nailed to it.
func _may_open(f: Fence) -> bool:
	var world: LevelData = game.world
	var cx := f.cell.x
	var cy := f.cell.y
	var w := world.width
	if cx <= 0 or cy <= 0 or cx >= w - 1 or cy >= world.height - 1:
		return false
	var c := cy * w + cx
	var roofed := world.roof[c] > 0.0
	if roofed and not f.spec.get("under_roof", false):
		return false
	var sides: Array[int] = []
	f.inside = -1
	for e: Array in LevelEdit.EDGES:
		var ex: int = e[0]
		var ey: int = e[1]
		var n := (cy + ey) * w + cx + ex
		if world.solid[n] >= 0:
			continue
		sides.append(n)
		if absf(world.ground[n] - world.ground[c]) > .001:
			return false
		if roofed:
			# A pen's fence in a barn: the same roof all round it.
			if absf(world.roof[n] - world.roof[c]) > .001:
				return false
		elif world.roof[n] > 0.0:
			# A shed's wall: its roof on one side only.
			if not f.spec.get("sheds", false) or f.inside >= 0:
				return false
			f.inside = n
	if f.spec.get("straight", false) or f.inside >= 0:
		# Straight through: open on two opposite sides, solid on the others.
		if sides.size() != 2 or sides[0] + sides[1] != 2 * c:
			return false
	if f.inside >= 0 and not _shed_wall(f):
		f.inside = -1
		return false
	f.low = roofed
	var box := Rect2(cx - .15, cy - .15, 1.3, 1.3)
	# (Boards, props and volumes from the cells round it: _index_things.)
	for v: PackedFloat32Array in _big_volumes:
		if v[0] < cx + 1.05 and v[2] > cx - .05 and v[1] < cy + 1.05 and v[3] > cy - .05:
			return false
	for yy in range(cy - 1, cy + 2):
		for xx in range(cx - 1, cx + 2):
			var at := Vector2i(xx, yy)
			for spot: Vector2 in _spots.get(at, []):
				if box.has_point(spot):
					return false
			for v: PackedFloat32Array in _volumes.get(at, []):
				if v[0] < cx + 1.05 and v[2] > cx - .05 and v[1] < cy + 1.05 and v[3] > cy - .05:
					return false
	# A free piece of wall on it (a sign's backing, a rail) would be left in the air.
	for yy in range(cy - 1, cy + 2):
		for xx in range(cx - 1, cx + 2):
			for piece: Vector3 in _loose.get(Vector2i(xx, yy), []):
				if box.has_point(Vector2(piece.x, piece.y)) and piece.z < f.top + .3:
					return false
	return true


## Whether a shed's wall cell may open under its roof: no window on it, no
## door, gate, pane or deck beside it, a roof a body's height over the gap,
## and plain boards (its own, the spec's `inside` tiles, trim) on its faces up
## to the roof; what stands above the roof (a gable) stays. Sets its top.
func _shed_wall(f: Fence) -> bool:
	var world: LevelData = game.world
	var w := world.width
	if by_cell.has(f.cell):
		return false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var at := Vector2i(f.cell.x + dx, f.cell.y + dy)
			if _ways.has(at):
				return false
			if world.geo != null and world.geo.cells[at.y * w + at.x] != 0:
				return false
	var c := f.cell.y * w + f.cell.x
	var top := world.roof[f.inside]
	if top - world.ground[c] < 1.9:
		return false
	var plain := {f.tile: true, f.hit_tile: true}
	var inside: Array = f.spec.get("inside", [])
	for name: Variant in inside:
		var t := world.tile_id(str(name))
		if t >= 0:
			plain[t] = true
	for e: Array in LevelEdit.EDGES:
		var edge := _own_edge(f.cell, e)
		var rows: Array = _cover.get(edge, [])
		for row: Vector3 in rows:
			if row.y >= top - .01:
				continue
			var tile := int(row.x)
			if not plain.has(tile) and not String(world.tile_names[tile]).begins_with("trim_"):
				return false
	f.top = top - world.ground[c]
	return true


## The billboards' and props' places by the cell they are in, and the
## collision volumes by each cell they cover (one over more than 64 cells in
## a list of its own): _may_open asks only the cells round a fence, a box
## that holds everything it would have found asking them all.
func _index_things() -> void:
	var world: LevelData = game.world
	for b: LevelData.Billboard in world.billboards:
		_spot(Vector2(b.x, b.y))
	for s: View.Sprite in game.props:
		_spot(Vector2(s.x, s.y))
	for v: PackedFloat32Array in world.collision_volumes:
		var x0 := floori(v[0])
		var y0 := floori(v[1])
		var x1 := floori(v[2])
		var y1 := floori(v[3])
		if (x1 - x0 + 1) * (y1 - y0 + 1) > 64:
			_big_volumes.append(v)
			continue
		for yy in range(y0, y1 + 1):
			for xx in range(x0, x1 + 1):
				var at := Vector2i(xx, yy)
				if not _volumes.has(at):
					_volumes[at] = []
				var list: Array = _volumes[at]
				list.append(v)


func _spot(p: Vector2) -> void:
	var at := Vector2i(floori(p.x), floori(p.y))
	if not _spots.has(at):
		_spots[at] = []
	var list: Array = _spots[at]
	list.append(p)


## The free wall pieces (off the grid: signs' backings, rails, awnings) by the
## cell their middle is in: [middle x, middle y, bottom].
func _loose_pieces() -> void:
	var world: LevelData = game.world
	var stride := LevelData.WALL_STRIDE
	for i in world.wall_count:
		var o := i * stride
		var ax: float = world.walls[o]
		var ay: float = world.walls[o + 1]
		var bx: float = world.walls[o + 2]
		var by: float = world.walls[o + 3]
		if ax == floorf(ax) and ay == floorf(ay) and bx == floorf(bx) and by == floorf(by):
			continue
		var mid := Vector2((ax + bx) * .5, (ay + by) * .5)
		var key := Vector2i(floori(mid.x), floori(mid.y))
		if not _loose.has(key):
			_loose[key] = []
		var in_cell: Array = _loose[key]
		in_cell.append(Vector3(mid.x, mid.y, world.walls[o + 6]))


## Each open cell's stretch of floor (-1: closed): the cells a body fits in,
## joined side to side, through doors only where the player can simply walk
## through (and window panes, which break).
static func regions(g: Game) -> PackedInt32Array:
	var world: LevelData = g.world
	var w := world.width
	var h := world.height
	var locked := {}
	for station: LevelData.Station in world.stations:
		for p: Vector2i in station.opens:
			locked[p] = true
	for prop: LevelData.Scenery in world.scenery:
		for p: Vector2i in prop.opens:
			locked[p] = true
	for trigger: Dictionary in world.triggers:
		for action: Variant in trigger.get("do", []):
			if action is Dictionary:
				var act: Dictionary = action
				if act.has("open"):
					var p: Array = act["open"]
					var px: int = p[0]
					var py: int = p[1]
					locked[Vector2i(px, py)] = true
	var doors := {}
	for door: LevelData.Door in world.doors:
		var at := Vector2i(door.x, door.y)
		doors[at.y * w + at.x] = (
			not door.secret
			and not door.blast_only
			and door.key == ""
			and not world.controlled_doors.has(at)
			and not world.access_doors.has(at)
			and not locked.has(at)
		)
	var panes := {}
	for p: Vector2i in world.pane_tiles:
		panes[p.y * w + p.x] = true
	var open := PackedByteArray()
	open.resize(w * h)
	var flow: FlowField = g.flow
	for c in w * h:
		var kind := flow.open[c]
		if kind == 1:
			open[c] = 1
		elif kind == 2:
			if doors.has(c):
				open[c] = 1 if doors[c] else 0
			elif panes.has(c):
				open[c] = 1
			else:
				open[c] = 0 if world.blocked(c % w + .5, c / w + .5, FlowField.BODY) else 1
	var label := PackedInt32Array()
	label.resize(w * h)
	label.fill(-1)
	var next := 0
	for start in w * h:
		if open[start] == 0 or label[start] >= 0:
			continue
		label[start] = next
		var todo := PackedInt32Array([start])
		while not todo.is_empty():
			var c := todo[todo.size() - 1]
			todo.resize(todo.size() - 1)
			var cx := c % w
			var cy := c / w
			for k in 4:
				var n: Vector2i = FlowField.NEIGHBOURS[k]
				var nx := cx + n.x
				var ny := cy + n.y
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var q := ny * w + nx
				if open[q] == 1 and label[q] < 0:
					label[q] = next
					todo.append(q)
		next += 1
	return label


# ------------------------------------------------------------------- shots


## A hitscan shot, a pellet or a swing from the player going along (ax, ay)
## met a wall at (x, y, z), a point just inside it: shoot out a window there,
## or knock a fence cell about. HOLE when it went in through a window's glass.
func strike(x: float, y: float, z: float, ax: float, ay: float, amount: float) -> int:
	if windows.is_empty() and fences.is_empty():
		return NONE
	var cell := _cell_at(x, y)
	if cell.x < 0:
		return NONE
	var p := game.player
	for face: WindowFace in by_cell.get(cell, []):
		var n := face.normal()
		if n.x * ax + n.y * ay >= 0.0:
			continue
		# Where the shot crossed the face's line, and how far along the face.
		var a := Vector2(face.edge.x, face.edge.y)
		var along := Vector2(face.edge.z, face.edge.w) - a
		var den := ax * along.y - ay * along.x
		if absf(den) < 1e-6:
			continue
		var rel := a - Vector2(p.x, p.y)
		var t := (rel.x * along.y - rel.y * along.x) / den
		var u := (rel.x * ay - rel.y * ax) / den
		if t <= 0.0 or u < ACROSS.x or u > ACROSS.y:
			continue
		if Vector2(p.x + ax * t - x, p.y + ay * t - y).length() > .3:
			continue
		if z < face.low or z > face.high:
			continue
		if not face.broken or face.cracked:
			_tell_window(face, Vector3(p.x + ax * t, p.y + ay * t, z), ax, ay, amount, SHOT)
		if not face.broken:
			# Play as ever: the first round breaks it (bits, specks, heard).
			# Looks: a light one leaves the glass cracked in its frame.
			var crack_most: float = win.get("crack_most", 50.0)
			_break_window(face, false, false, amount < crack_most)
		elif face.cracked:
			_shoot_out(face, false)
		return HOLE
	var f: Fence = fences.get(cell)
	if f != null:
		_knock(f, amount, ax, ay, Vector3(x, y, z), SHOT)
	return NONE


## A body thrown along (ax, ay) struck the wall at (x, y) (features/corpses.gd),
## its shoulders at height z: a window it hit shatters (HOLE), a fence cell
## takes `amount` (OPENED when that broke it through).
func crash(x: float, y: float, z: float, ax: float, ay: float, amount: float) -> int:
	if windows.is_empty() and fences.is_empty():
		return NONE
	var cell := _cell_at(x + ax * .35, y + ay * .35)
	if cell.x < 0:
		return NONE
	var at := Vector2(x, y)
	for face: WindowFace in by_cell.get(cell, []):
		var n := face.normal()
		if n.x * ax + n.y * ay >= 0.0:
			continue
		var a := Vector2(face.edge.x, face.edge.y)
		var b := Vector2(face.edge.z, face.edge.w)
		var near := Geometry2D.get_closest_point_to_segment(at, a, b)
		var u := (near - a).length() / maxf(.01, (b - a).length())
		if u < ACROSS.x - .15 or u > ACROSS.y + .15 or near.distance_to(at) > .6:
			continue
		if z < face.low - .5 or z > face.high + .3:
			continue
		if not face.broken or face.cracked:
			_tell_window(face, Vector3(near.x, near.y, z), ax, ay, amount, BODY)
		if not face.broken:
			_break_window(face, false)
		elif face.cracked:
			_shoot_out(face, false)
		return HOLE
	var f: Fence = fences.get(cell)
	if f == null or f.stage == 2:
		return NONE
	_knock(f, amount, ax, ay, Vector3(x + ax * .35, y + ay * .35, z), BODY)
	return OPENED if f.stage == 2 else HOLE


## The solid cell a point at a wall is in (or just short of), or (-1, -1).
func _cell_at(x: float, y: float) -> Vector2i:
	var world: LevelData = game.world
	for k in 5:
		var dx := 0.0 if k == 0 else (-.03 if k % 2 == 1 else .03)
		var dy := 0.0 if k == 0 else (-.03 if k < 3 else .03)
		var cx := int(x + dx)
		var cy := int(y + dy)
		if cx >= 0 and cy >= 0 and cx < world.width and cy < world.height:
			if world.solid[cy * world.width + cx] >= 0:
				return Vector2i(cx, cy)
	return Vector2i(-1, -1)


## A blast at (x, y, z): the windows it reaches shoot out, the fence cells it
## reaches take its damage by how near.
func blast(x: float, y: float, z: float, radius: float, strength: float, energy: bool) -> void:
	var world: LevelData = game.world
	var reach: float = win.get("blast_reach", 2.4)
	for face: WindowFace in windows:
		if face.broken and not face.cracked:
			continue
		var mid := face.middle()
		if absf(mid.x - x) > reach + .5 or absf(mid.y - y) > reach + .5:
			continue
		var a := Vector2(face.edge.x, face.edge.y)
		var b := Vector2(face.edge.z, face.edge.w)
		var near := Geometry2D.get_closest_point_to_segment(Vector2(x, y), a, b)
		var front := near + face.normal() * .06
		var glass := (face.low + face.high) * .5
		if (
			near.distance_to(Vector2(x, y)) < reach
			and world.visible(x, y, front.x, front.y, z, glass)
		):
			var away := (near - Vector2(x, y)).normalized()
			_tell_window(face, Vector3(x, y, z), away.x, away.y, strength, BLAST)
			if face.broken:
				_shoot_out(face, true)
			else:
				_break_window(face, false, true)
	for f: Fence in fences.values():
		if f.stage == 2:
			continue
		var centre := Vector2(f.cell.x + .5, f.cell.y + .5)
		if absf(centre.x - x) > radius + 1.0 or absf(centre.y - y) > radius + 1.0:
			continue
		var at := Vector2(
			clampf(x, f.cell.x - .001, f.cell.x + 1.001),
			clampf(y, f.cell.y - .001, f.cell.y + 1.001)
		)
		var d := at.distance_to(Vector2(x, y))
		if d >= radius:
			continue
		var front := at + (Vector2(x, y) - at).normalized() * .06 if d > .07 else Vector2(x, y)
		if not world.visible(x, y, front.x, front.y, z, minf(z, f.top * .5)):
			continue
		var away := (centre - Vector2(x, y)).normalized()
		var power := strength * (1.0 - d / (radius + .3)) * (.5 if energy else 1.0)
		_knock(f, power, away.x, away.y, Vector3(x, y, z), BLAST)


# ------------------------------------------------------------------ breaking


## Broken (by a blast its frame torn out too: <material>_bst; `held`: its
## glass left cracked in its frame, its tile as it was, wall_looks.gd's web
## over it). What play sees is the same either way.
func _break_window(face: WindowFace, quiet: bool, blasted := false, held := false) -> void:
	face.broken = true
	face.blasted = blasted and face.blast >= 0
	face.cracked = held and not face.blasted
	net_version += 1
	if not face.cracked:
		_retile(face, face.blast if face.blasted else face.shot)
	if quiet:
		return
	game.net_facts.erase("wall_breaks")
	var n := face.normal()
	var at := face.middle() + n * .14
	var z := (face.low + face.high) * .5
	_drop_marks(face.middle(), n, face.low, face.high)
	_noise(win, at, z, face.cracked)
	var pieces: Breakables = game.features.get("breakables")
	if pieces != null:
		var bits: int = win.get("bits", 7)
		pieces.scatter(at.x, at.y, z, "glass", bits, n.x * .6, n.y * .6)
	var specks: int = win.get("specks", 14)
	game.burst(at.x, at.y, z, "glass", specks, 1.8)
	var heard: float = win.get("heard", 6.8)
	game.disturb(at.x, at.y, heard, z)


## A cracked window's glass shot out of its frame (the next round, a blast:
## its frame too, a body): only its picture and its sound; play had it
## broken already, so no dice, nobody hears more.
func _shoot_out(face: WindowFace, blasted: bool) -> void:
	game.net_facts.erase("wall_breaks")
	face.cracked = false
	face.blasted = blasted and face.blast >= 0
	net_version += 1
	_retile(face, face.blast if face.blasted else face.shot)
	var n := face.normal()
	_drop_marks(face.middle(), n, face.low, face.high)
	var at := face.middle() + n * .14
	game.sound_at(str(win.get("cue", "glass_break")), at.x, at.y, .9)


## A window face's pieces (whole, or as broken before) show `tile`.
func _retile(face: WindowFace, tile: int) -> void:
	var world: LevelData = game.world
	for i in world.walls_on(face.edge.x, face.edge.y, face.edge.z, face.edge.w):
		var now := int(world.walls[i * LevelData.WALL_STRIDE + 4])
		if now == face.whole or now == face.shot or now == face.blast:
			world.set_wall_tile(i, tile)


## A fence cell takes `amount`: shot about past `damaged` of its hp, broken
## through at none (if it may open; else it holds, shot about). Where it was
## struck (`at`) and how (SHOT, BLAST, BODY) go to its looks only.
func _knock(
	f: Fence, amount: float, ax: float, ay: float, at := Vector3(-1, -1, -1), how := SHOT
) -> void:
	if f.stage == 2 or amount <= 0.0:
		return
	net_version += 1
	var was := f.hp
	f.hp -= amount
	if not f.opens:
		f.hp = maxf(f.hp, 1.0)
	var looks: WallLooks = game.features.get("wall_looks")
	if looks != null and at.x >= 0.0:
		looks.fence_struck(f, at, Vector2(ax, ay), was - f.hp, how)
	var damaged: float = f.spec.get("damaged", .6)
	if f.stage == 0 and f.hp <= f.most * damaged:
		_shoot_about(f, false, ax, ay)
	if f.hp <= 0.0:
		_break_through(f, false, ax, ay)


func _shoot_about(f: Fence, quiet: bool, ax := 0.0, ay := 0.0) -> void:
	f.stage = 1
	net_version += 1
	var world: LevelData = game.world
	PlankWalls.split(world, f.cell.x, f.cell.y)
	# Its own boards knocked out, and boards of another plank wall on its other
	# face (a shed's inside, a pen's barn boards) knocked out as theirs.
	var hits := {f.tile: f.hit_tile}
	var also: Array = f.spec.get("inside", [])
	for name: Variant in also:
		var t := world.tile_id(str(name))
		var t_hit := world.tile_id(str(name) + "_hit")
		if t >= 0 and t_hit >= 0 and not hits.has(t):
			hits[t] = t_hit
	# Not what stands above a shed's roof (its gable stays as it was).
	var over := world.ground[f.cell.y * world.width + f.cell.x] + f.top - .01
	for e: Array in LevelEdit.EDGES:
		var edge := _own_edge(f.cell, e)
		for i in world.walls_on(edge.x, edge.y, edge.z, edge.w):
			var tile := int(world.walls[i * LevelData.WALL_STRIDE + 4])
			if (
				hits.has(tile)
				and (f.inside < 0 or world.walls[i * LevelData.WALL_STRIDE + 6] < over)
			):
				var hit: int = hits[tile]
				world.set_wall_tile(i, hit)
	if quiet:
		return
	var at := _front(f, ax, ay)
	var z := world.ground[f.cell.y * world.width + f.cell.x] + f.top * .55
	game.sound_at(str(f.spec.get("chip", "impact_wood")), at.x, at.y, .7)
	var pieces: Breakables = game.features.get("breakables")
	if pieces != null:
		pieces.scatter(at.x, at.y, z, str(f.spec.get("stuff", "wood")), 3, -ax * .4, -ay * .4)


func _break_through(f: Fence, quiet: bool, ax := 0.0, ay := 0.0) -> void:
	if f.stage < 1:
		_shoot_about(f, true)
	f.stage = 2
	f.hp = 0.0
	net_version += 1
	var world: LevelData = game.world
	var cx := f.cell.x
	var cy := f.cell.y
	PlankWalls.split(world, cx, cy)
	if f.inside >= 0:
		PlankWalls.open_shed(world, cx, cy, f.inside, _faces)
	else:
		world.open_cell(cx, cy, _faces, f.low)
	game.reopen_paths(cx, cy, cx + 1, cy + 1)
	game.route_sig = []
	_stand_gap(f)
	if quiet:
		return
	var ground := world.ground[cy * world.width + cx]
	var z := ground + f.top * .45
	_drop_marks(Vector2(cx + .5, cy + .5), Vector2.ZERO, ground - 1.0, ground + f.top + 1.0)
	var at := Vector2(cx + .5, cy + .5)
	_noise(f.spec, at, z)
	var pieces: Breakables = game.features.get("breakables")
	var stuff := str(f.spec.get("stuff", "wood"))
	if pieces != null:
		var bits: int = f.spec.get("bits", 9)
		pieces.scatter(at.x, at.y, z, stuff, bits, ax, ay)
	# Its dice spent as ever, its specks left out: the boards bursting out
	# (features/wall_looks.gd) read better than a cloud of chips.
	game.burst(at.x, at.y, z, "chips", 10, 1.4, false)
	var heard: float = f.spec.get("heard", 5.0)
	game.disturb(at.x, at.y, heard, z)


## The picture standing in a gap: a cell wide, from the ground, one a side;
## one of its stumps' pictures (<broken>, _1, _2: tools/art/wall_break_art.gd)
## by the cell, so gaps side by side are not alike.
func _stand_gap(f: Fence) -> void:
	var image := str(f.spec.get("broken", ""))
	var pick := posmod(f.cell.x * 7 + f.cell.y * 13, 3)
	if pick > 0 and game.art.has_art("%s_%d" % [image, pick]):
		image = "%s_%d" % [image, pick]
	var art: Dictionary = game.art.art(image)
	var art_h: float = art["h"]
	var art_w: float = art["w"]
	var tall := minf(f.top, art_h / maxf(1.0, art_w))
	var world: LevelData = game.world
	var ground := world.ground[f.cell.y * world.width + f.cell.x]
	var facing := 0.0 if f.along_x else PI * .5
	for k in 2:
		var s := View.Sprite.new(f.cell.x + .5, f.cell.y + .5, image, tall, ground)
		s.plane = facing + PI * k
		gaps.append(s)


## The cell's own face toward neighbour e (LevelEdit.EDGES): [ax, ay, bx, by].
static func _own_edge(cell: Vector2i, e: Array) -> Vector4:
	var ax: int = e[2]
	var ay: int = e[3]
	var bx: int = e[4]
	var by: int = e[5]
	return Vector4(cell.x + ax, cell.y + ay, cell.x + bx, cell.y + by)


## A point just out in front of the fence cell, toward whoever shot it.
func _front(f: Fence, ax: float, ay: float) -> Vector2:
	var centre := Vector2(f.cell.x + .5, f.cell.y + .5)
	var back := Vector2(-ax, -ay)
	if back.length() < .01:
		return centre
	back = back.normalized()
	# Out of the cell along the axis the shot came in on.
	if absf(back.x) > absf(back.y):
		return centre + Vector2(signf(back.x) * .62, back.y * .3)
	return centre + Vector2(back.x * .3, signf(back.y) * .62)


## Where and how a window was struck, for its looks (features/wall_looks.gd:
## its cracks from that point, its glass flying from it).
func _tell_window(
	face: WindowFace, at: Vector3, ax: float, ay: float, amount: float, how: int
) -> void:
	var looks: WallLooks = game.features.get("wall_looks")
	if looks != null:
		looks.window_struck(face, at, Vector2(ax, ay), amount, how)


## A break's sounds (a row breaking at once is one crash).
func _noise(spec: Dictionary, at: Vector2, _z: float, crack := false) -> void:
	if game.clock < _crash_next:
		return
	_crash_next = game.clock + .05
	if crack:
		# Glass cracked in its frame: its crack, not its crash.
		game.sound_at(str(spec.get("crack_cue", "glass_settle")), at.x, at.y, .7)
		return
	game.sound_at(str(spec.get("cue", "glass_break")), at.x, at.y, .9)
	if spec.has("cue2"):
		game.sound_at(str(spec["cue2"]), at.x, at.y, .6)


## Holes and scorches on a face or a cell that is no longer there to hold
## them: on the face through `middle` facing `normal` (ZERO: anywhere in the
## cell round `middle`), from `low` to `high`.
func _drop_marks(middle: Vector2, normal: Vector2, low: float, high: float) -> void:
	var kept: Array = []
	for mark: View.WallMark in game.wall_marks:
		var off := Vector2(mark.x, mark.y) - middle
		var on := mark.z >= low - .05 and mark.z <= high + .05
		if normal == Vector2.ZERO:
			on = on and absf(off.x) < .56 and absf(off.y) < .56
		else:
			on = on and absf(off.dot(normal)) < .06 and off.length() < .56
		if not on:
			kept.append(mark)
	if kept.size() != game.wall_marks.size():
		game.wall_marks.assign(kept)


func sprites() -> Array:
	var out: Array = []
	for s: View.Sprite in gaps:
		if game.in_view(s.x, s.y, .8):
			out.append(s)
	return out


# -------------------------------------------------------------------- saves


## Nothing broken any more: the level's walls were laid down as built again
## (modes/round_cover.gd, a 5v5 round's start).
func forget() -> void:
	for face: WindowFace in windows:
		face.broken = false
		face.blasted = false
		face.cracked = false
	for f: Fence in fences.values():
		f.hp = f.most
		f.stage = 0
	gaps.clear()
	net_version += 1


func save() -> Dictionary:
	var shot: Array = []
	var cracked: Array = []
	var blasted: Array = []
	for face: WindowFace in windows:
		if face.broken:
			shot.append([face.edge.x, face.edge.y, face.edge.z, face.edge.w])
			if face.blasted:
				blasted.append([face.edge.x, face.edge.y, face.edge.z, face.edge.w])
		if face.cracked:
			cracked.append([face.edge.x, face.edge.y, face.edge.z, face.edge.w])
	var knocked: Array = []
	var w: int = game.world.width
	var keys: Array = fences.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y * w + a.x < b.y * w + b.x)
	for key: Vector2i in keys:
		var f: Fence = fences[key]
		if f.hp < f.most:
			knocked.append([f.cell.x, f.cell.y, f.stage, snappedf(f.hp, .1)])
	if shot.is_empty() and knocked.is_empty() and cracked.is_empty():
		return {}
	var out := {"windows": shot, "fences": knocked}
	if not cracked.is_empty():
		out["cracked"] = cracked
	if not blasted.is_empty():
		out["blasted"] = blasted
	return out


func restore(state: Dictionary) -> void:
	var broken := _saved_window_edges(state.get("windows", []))
	var held := _saved_window_edges(state.get("cracked", []))
	var torn := _saved_window_edges(state.get("blasted", []))
	for face: WindowFace in windows:
		var shot := broken.has(face.edge)
		var blasted := shot and face.blast >= 0 and torn.has(face.edge)
		var cracked := shot and not blasted and held.has(face.edge)
		if face.broken == shot and face.blasted == blasted and face.cracked == cracked:
			continue
		# An online snapshot may correct a window the copy broke differently.
		face.broken = shot
		face.blasted = blasted
		face.cracked = cracked
		net_version += 1
		var tile := face.whole
		if shot and not cracked:
			tile = face.blast if blasted else face.shot
		_retile(face, tile)
	for item: Variant in state.get("fences", []):
		if not (item is Array):
			continue
		var row: Array = item
		if row.size() != 4:
			continue
		var cx: int = row[0]
		var cy: int = row[1]
		var f: Fence = fences.get(Vector2i(cx, cy))
		var stage: int = row[2]
		# A fence shot about already goes on only to broken through (a
		# snapshot put onto a game already running: game_snapshot.gd).
		if f == null or (f.stage != 0 and f.stage >= stage):
			continue
		var hp: float = row[3]
		f.hp = clampf(hp, 0.0, f.most)
		net_version += 1
		if stage >= 2 and f.opens:
			_break_through(f, true)
		elif stage >= 1:
			f.hp = maxf(f.hp, 1.0)
			_shoot_about(f, true)


## A window is saved by its two endpoints, in the level's own order.
static func _saved_window_edges(rows: Variant) -> Dictionary:
	var out := {}
	if not rows is Array:
		return out
	var edges: Array = rows
	for item: Variant in edges:
		if not item is Array:
			continue
		var row: Array = item
		if row.size() != 4:
			continue
		var ax: float = row[0]
		var ay: float = row[1]
		var bx: float = row[2]
		var by: float = row[3]
		out[Vector4(ax, ay, bx, by)] = true
	return out
