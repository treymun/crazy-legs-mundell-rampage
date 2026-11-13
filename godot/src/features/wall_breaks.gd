## Walls that break: the windows painted on building walls shoot out, and the
## plank fences get shot about and then broken through.
##
## A window is a wall piece showing a window tile (<material>_win or _lit, the
## trailers' trailer_window): a shot into its glass, or a blast near it, swaps
## its picture for <material>_brk (tools/art/wall_break_art.gd: the room dark
## behind teeth of glass, so a lit one goes dark), throws glass and plays the
## window cue. It stays a wall. A fence cell is a solid cell of a tile with a
## [fence.<tile>] section in data/tuning/breakables.cfg: shots and blasts take
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
## game_combat.gd tells it where each hitscan shot, pellet or swing met a wall
## (strike()) and every blast (blast()). What is broken saves in the feature's
## block; a save from before it restores with nothing broken.
extends GameFeature

const PATH := "res://data/tuning/breakables.cfg"
## strike()'s answers: nothing here to break, or the shot went in through a
## window's glass (now or already gone), so it leaves no hole on it.
const NONE := 0
const HOLE := 1
## crash()'s answer when the fence it hit broke through (the body goes on).
const OPENED := 2
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
## While finding the fences: the free wall pieces by cell (_loose_pieces).
var _loose := {}
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
	if (win.get("never", []) as Array).has(world.id) or not world.road_and_hub.is_empty():
		return
	_find_windows()
	_find_fences(cfg)
	for f: Fence in fences.values():
		game.renderer.sprite_art(String(f.spec.get("broken", "")))


static func _section(cfg: ConfigFile, name: String) -> Dictionary:
	var out := {}
	if cfg.has_section(name):
		for key in cfg.get_section_keys(name):
			out[key] = cfg.get_value(name, key)
	return out


# ------------------------------------------------------------------ finding


## Every wall piece showing a window that has a broken tile, on the grid, a
## cell's face.
func _find_windows() -> void:
	var world: LevelData = game.world
	var shot_of := {}
	for i in world.tile_names.size():
		var name := String(world.tile_names[i])
		for tail: String in ["_window", "_win", "_lit"]:
			if name.ends_with(tail):
				var broken := world.tile_id(name.trim_suffix(tail) + "_brk")
				if broken >= 0:
					shot_of[i] = broken
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
		face.shot = int(shot_of[tile])
		var bottom: float = world.walls[o + 6]
		var top: float = world.walls[o + 7]
		if game.renderer.tile_mode[tile] == 2:
			face.low = RenderState.WINDOW_SILL
			face.high = RenderState.WINDOW_HEAD
		else:
			face.low = top - DOWN.y * (top - bottom)
			face.high = top - DOWN.x * (top - bottom)
		windows.append(face)
		if not by_cell.has(face.cell):
			by_cell[face.cell] = []
		by_cell[face.cell].append(face)


## Every fence cell, and which of them may open.
func _find_fences(cfg: ConfigFile) -> void:
	var world: LevelData = game.world
	var specs := {}
	for section in cfg.get_sections():
		if not String(section).begins_with("fence."):
			continue
		var name := String(section).substr(6)
		var spec := _section(cfg, section)
		var tile := world.tile_id(name)
		var hit := world.tile_id(String(spec.get("hit", "")))
		# A merged run would not come apart a cell at a time.
		if tile < 0 or hit < 0 or RenderState.TILED.has(name):
			continue
		if not game.art.has_art(String(spec.get("broken", ""))):
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
			f.hit_tile = int(_faces[tile])
			f.spec = specs[tile]
			f.most = float(f.spec.get("hp", 100.0))
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
	_rule()
	_loose = {}


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
			var n := Vector2i(f.cell.x + int(e[0]), f.cell.y + int(e[1]))
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
	if world.roof[c] > 0.0:
		return false
	for e: Array in LevelEdit.EDGES:
		var n := (cy + int(e[1])) * w + cx + int(e[0])
		if world.solid[n] >= 0:
			continue
		if world.roof[n] > 0.0 or absf(world.ground[n] - world.ground[c]) > .001:
			return false
	var box := Rect2(cx - .15, cy - .15, 1.3, 1.3)
	for b: LevelData.Billboard in world.billboards:
		if box.has_point(Vector2(b.x, b.y)):
			return false
	for s: Renderer.Sprite in game.props:
		if box.has_point(Vector2(s.x, s.y)):
			return false
	for v: PackedFloat32Array in world.collision_volumes:
		if v[0] < cx + 1.05 and v[2] > cx - .05 and v[1] < cy + 1.05 and v[3] > cy - .05:
			return false
	# A free piece of wall on it (a sign's backing, a rail) would be left in the air.
	for yy in range(cy - 1, cy + 2):
		for xx in range(cx - 1, cx + 2):
			for piece: Vector3 in _loose.get(Vector2i(xx, yy), []):
				if box.has_point(Vector2(piece.x, piece.y)) and piece.z < f.top + .3:
					return false
	return true


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
		_loose[key].append(Vector3(mid.x, mid.y, world.walls[o + 6]))


## Each open cell's stretch of floor (-1: closed): the cells a body fits in,
## joined side to side, through doors only where the player can simply walk
## through (and window panes, which break).
static func regions(g) -> PackedInt32Array:
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
		for action in trigger.get("do", []):
			if action is Dictionary and action.has("open"):
				var p: Array = action["open"]
				locked[Vector2i(int(p[0]), int(p[1]))] = true
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
	var p = game.player
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
		if not face.broken:
			_break_window(face, false)
		return HOLE
	var f: Fence = fences.get(cell)
	if f != null:
		_knock(f, amount, ax, ay)
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
		if not face.broken:
			_break_window(face, false)
		return HOLE
	var f: Fence = fences.get(cell)
	if f == null or f.stage == 2:
		return NONE
	_knock(f, amount, ax, ay)
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
	var reach := float(win.get("blast_reach", 2.4))
	for face: WindowFace in windows:
		if face.broken:
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
			_break_window(face, false)
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
		_knock(f, strength * (1.0 - d / (radius + .3)) * (.5 if energy else 1.0), away.x, away.y)


# ------------------------------------------------------------------ breaking


func _break_window(face: WindowFace, quiet: bool) -> void:
	face.broken = true
	net_version += 1
	var world: LevelData = game.world
	for i in world.walls_on(face.edge.x, face.edge.y, face.edge.z, face.edge.w):
		if int(world.walls[i * LevelData.WALL_STRIDE + 4]) == face.whole:
			world.set_wall_tile(i, face.shot)
	if quiet:
		return
	var n := face.normal()
	var at := face.middle() + n * .14
	var z := (face.low + face.high) * .5
	_drop_marks(face.middle(), n, face.low, face.high)
	_noise(win, at, z)
	var pieces = game.features.get("breakables")
	if pieces != null:
		pieces.scatter(at.x, at.y, z, "glass", int(win.get("bits", 7)), n.x * .6, n.y * .6)
	game.burst(at.x, at.y, z, "glass", int(win.get("specks", 14)), 1.8)
	game.disturb(at.x, at.y, float(win.get("heard", 6.8)), z)


## A fence cell takes `amount`: shot about past `damaged` of its hp, broken
## through at none (if it may open; else it holds, shot about).
func _knock(f: Fence, amount: float, ax: float, ay: float) -> void:
	if f.stage == 2 or amount <= 0.0:
		return
	net_version += 1
	f.hp -= amount
	if not f.opens:
		f.hp = maxf(f.hp, 1.0)
	if f.stage == 0 and f.hp <= f.most * float(f.spec.get("damaged", .6)):
		_shoot_about(f, false, ax, ay)
	if f.hp <= 0.0:
		_break_through(f, false, ax, ay)


func _shoot_about(f: Fence, quiet: bool, ax := 0.0, ay := 0.0) -> void:
	f.stage = 1
	net_version += 1
	var world: LevelData = game.world
	for e: Array in LevelEdit.EDGES:
		var edge := _own_edge(f.cell, e)
		for i in world.walls_on(edge.x, edge.y, edge.z, edge.w):
			if int(world.walls[i * LevelData.WALL_STRIDE + 4]) == f.tile:
				world.set_wall_tile(i, f.hit_tile)
	if quiet:
		return
	var at := _front(f, ax, ay)
	var z := world.ground[f.cell.y * world.width + f.cell.x] + f.top * .55
	game.sound_at(String(f.spec.get("chip", "impact_wood")), at.x, at.y, .7)
	var pieces = game.features.get("breakables")
	if pieces != null:
		pieces.scatter(at.x, at.y, z, String(f.spec.get("stuff", "wood")), 3, -ax * .4, -ay * .4)


func _break_through(f: Fence, quiet: bool, ax := 0.0, ay := 0.0) -> void:
	if f.stage < 1:
		_shoot_about(f, true)
	f.stage = 2
	f.hp = 0.0
	net_version += 1
	var world: LevelData = game.world
	var cx := f.cell.x
	var cy := f.cell.y
	world.open_cell(cx, cy, _faces)
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
	var pieces = game.features.get("breakables")
	var stuff := String(f.spec.get("stuff", "wood"))
	if pieces != null:
		pieces.scatter(at.x, at.y, z, stuff, int(f.spec.get("bits", 9)), ax, ay)
	game.burst(at.x, at.y, z, "chips", 10, 1.4)
	game.disturb(at.x, at.y, float(f.spec.get("heard", 5.0)), z)


## The picture standing in a gap: a cell wide, from the ground, one a side.
func _stand_gap(f: Fence) -> void:
	var image := String(f.spec.get("broken", ""))
	var art: Dictionary = game.renderer.sprite_art(image)
	var tall := minf(f.top, float(art["h"]) / maxf(1.0, float(art["w"])))
	var world: LevelData = game.world
	var ground := world.ground[f.cell.y * world.width + f.cell.x]
	var facing := 0.0 if f.along_x else PI * .5
	for k in 2:
		var s := Renderer.Sprite.new(f.cell.x + .5, f.cell.y + .5, image, tall, ground)
		s.plane = facing + PI * k
		gaps.append(s)


## The cell's own face toward neighbour e (LevelEdit.EDGES): [ax, ay, bx, by].
static func _own_edge(cell: Vector2i, e: Array) -> Vector4:
	return Vector4(cell.x + int(e[2]), cell.y + int(e[3]), cell.x + int(e[4]), cell.y + int(e[5]))


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


## A break's sounds (a row breaking at once is one crash).
func _noise(spec: Dictionary, at: Vector2, _z: float) -> void:
	if game.clock < _crash_next:
		return
	_crash_next = game.clock + .05
	game.sound_at(String(spec.get("cue", "glass_break")), at.x, at.y, .9)
	if spec.has("cue2"):
		game.sound_at(String(spec["cue2"]), at.x, at.y, .6)


## Holes and scorches on a face or a cell that is no longer there to hold
## them: on the face through `middle` facing `normal` (ZERO: anywhere in the
## cell round `middle`), from `low` to `high`.
func _drop_marks(middle: Vector2, normal: Vector2, low: float, high: float) -> void:
	var kept: Array = []
	for mark: Renderer.WallMark in game.wall_marks:
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
	for s: Renderer.Sprite in gaps:
		if game.in_view(s.x, s.y, .8):
			out.append(s)
	return out


# -------------------------------------------------------------------- saves


func save() -> Dictionary:
	var shot: Array = []
	for face: WindowFace in windows:
		if face.broken:
			shot.append([face.edge.x, face.edge.y, face.edge.z, face.edge.w])
	var knocked: Array = []
	var w: int = game.world.width
	var keys: Array = fences.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y * w + a.x < b.y * w + b.x)
	for key: Vector2i in keys:
		var f: Fence = fences[key]
		if f.hp < f.most:
			knocked.append([f.cell.x, f.cell.y, f.stage, snappedf(f.hp, .1)])
	if shot.is_empty() and knocked.is_empty():
		return {}
	return {"windows": shot, "fences": knocked}


func restore(state: Dictionary) -> void:
	var by_edge := {}
	for face: WindowFace in windows:
		by_edge[face.edge] = face
	for row in state.get("windows", []):
		if not (row is Array) or row.size() != 4:
			continue
		var face: WindowFace = by_edge.get(
			Vector4(float(row[0]), float(row[1]), float(row[2]), float(row[3]))
		)
		if face != null and not face.broken:
			_break_window(face, true)
	for row in state.get("fences", []):
		if not (row is Array) or row.size() != 4:
			continue
		var f: Fence = fences.get(Vector2i(int(row[0]), int(row[1])))
		var stage := int(row[2])
		# A fence shot about already goes on only to broken through (a
		# snapshot put onto a game already running: game_snapshot.gd).
		if f == null or (f.stage != 0 and f.stage >= stage):
			continue
		f.hp = clampf(float(row[3]), 0.0, f.most)
		net_version += 1
		if stage >= 2 and f.opens:
			_break_through(f, true)
		elif stage >= 1:
			f.hp = maxf(f.hp, 1.0)
			_shoot_about(f, true)
