## Checks of the walls that break (features/wall_breaks.gd), run by
## tools/break_check.gd: every chapter has windows that shoot out and the
## ones with plank fences have cells that break through; a shot into a
## Hickston storefront's glass shoots it out and it stays a wall; a fair fence
## cell shot about and then through is floor to bodies, sight, shots and both
## flow fields, its faces gone and its neighbours' showing; a blast does both;
## a save keeps it all; and no set of fence cells that may open joins ground
## the level keeps apart, or lets the player walk anywhere new from the start.
extends RefCounted

const LEVELS := [
	"hickston", "fair", "sawmill", "quarry", "bayou", "speedway", "mothership", "hub", "range"
]
## Levels that have to have windows, and fence cells that open.
const WINDOWS_IN := ["hickston", "fair", "sawmill", "quarry", "bayou", "speedway", "range"]
const FENCES_IN := ["hickston", "fair", "range"]


static func _game(main, level_id: String) -> Game:
	var g: Game = main.make_game(level_id)
	g.configure({})
	g.cheats.god = true
	# Nobody about to stand in a shot's way.
	for e: Enemy in g.enemies:
		e.dormant = true
	return g


static func run(main, check: Callable) -> void:
	var counts: Array = []
	var bare: Array = []
	for level_id: String in LEVELS:
		var g := _game(main, level_id)
		var wb = g.features["wall_breaks"]
		var opens := 0
		for f in wb.fences.values():
			opens += 1 if f.opens else 0
		counts.append("%s %d/%d/%d" % [level_id, wb.windows.size(), wb.fences.size(), opens])
		if WINDOWS_IN.has(level_id) and wb.windows.size() < 4:
			bare.append(level_id + " windows")
		if FENCES_IN.has(level_id) and opens < 4:
			bare.append(level_id + " fences")
		if level_id == "hub" and (not wb.windows.is_empty() or not wb.fences.is_empty()):
			bare.append("the Crossroads breaks something")
	print("    windows / fence cells / may open: ", ", ".join(counts))
	check.call(
		bare.is_empty(),
		(
			"every chapter has windows that shoot out, fences that open where it has them"
			+ ("" if bare.is_empty() else " %s" % [bare])
		)
	)
	_keeps_apart(main, check)
	_window_shot(main, check)
	_fence_shot(main, check)
	_blasts(main, check)


## Breaking every fence cell that may open, in every level, joins no two
## stretches of floor the level keeps apart (wall_breaks.gd regions(): shut
## behind a key, station, trigger, secret or blast door), lets nobody walk
## anywhere new from the start with every door open but the cells
## themselves, and leaves no cell on the map's edge open.
static func _keeps_apart(main, check: Callable) -> void:
	var joined: Array = []
	var walked: Array = []
	for level_id: String in LEVELS:
		var g := _game(main, level_id)
		var wb = g.features["wall_breaks"]
		var before: PackedInt32Array = wb.regions(g)
		var reach_before := _reach(g)
		var opened := {}
		for f in wb.fences.values():
			if f.opens:
				wb._break_through(f, true)
				opened[f.cell] = true
				var c: Vector2i = f.cell
				if c.x == 0 or c.y == 0 or c.x == g.world.width - 1 or c.y == g.world.height - 1:
					joined.append("%s %s on the edge" % [level_id, c])
		var after: PackedInt32Array = wb.regions(g)
		var seen := {}
		for i in after.size():
			if after[i] < 0 or before[i] < 0:
				continue
			var was = seen.get(after[i])
			if was == null:
				seen[after[i]] = before[i]
			elif int(was) != before[i]:
				joined.append("%s %s" % [level_id, Vector2i(i % g.world.width, i / g.world.width)])
				break
		for cell: Vector2i in _reach(g):
			if not reach_before.has(cell) and not opened.has(cell):
				walked.append("%s %s" % [level_id, cell])
				break
	check.call(
		joined.is_empty(),
		(
			"fence cells that may open join no ground the level keeps apart"
			+ ("" if joined.is_empty() else " %s" % [joined.slice(0, 6)])
		)
	)
	check.call(
		walked.is_empty(),
		(
			"and open no new ground from the start"
			+ ("" if walked.is_empty() else " %s" % [walked.slice(0, 6)])
		)
	)


## The cells the player can walk to from the start (doors and gates as open).
static func _reach(g: Game) -> Dictionary:
	var w := g.flow.width
	var h := g.flow.height
	var start := Vector2i(int(g.player.x), int(g.player.y))
	var seen := {start: true}
	var todo: Array = [start]
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		for n: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = c + n
			if q.x < 0 or q.y < 0 or q.x >= w or q.y >= h or seen.has(q):
				continue
			if g.flow.open[q.y * w + q.x] == 0:
				continue
			seen[q] = true
			todo.append(q)
	return seen


## Stand the player `far` out in front of a face (its middle, normal n) and
## aim at height z on it.
static func _face(g: Game, middle: Vector2, n: Vector2, far: float, z: float) -> bool:
	var at := middle + n * far
	if g.world.blocked(at.x, at.y, .2):
		return false
	var p := g.player
	p.x = at.x
	p.y = at.y
	p.eye = .95 + g.world.elevation(at.x, at.y)
	return g.world.visible(at.x, at.y, middle.x + n.x * .05, middle.y + n.y * .05, p.eye, z)


## The tile the wall list shows on a face's piece(s).
static func _tiles_on(g: Game, edge: Vector4) -> Array:
	var out: Array = []
	for i in g.world.walls_on(edge.x, edge.y, edge.z, edge.w):
		out.append(int(g.world.walls[i * LevelData.WALL_STRIDE + 4]))
	return out


## A shot from across the street into a Hickston storefront's glass shoots it
## out: its picture swaps, glass flies, it stays a wall; a shot at the brick
## beside a window leaves it whole; a save keeps it shot out.
static func _window_shot(main, check: Callable) -> void:
	var g := _game(main, "hickston")
	var wb = g.features["wall_breaks"]
	var face = null
	for w in wb.windows:
		var name := String(g.world.tile_names[w.whole])
		if name.begins_with("brick") and _face(g, w.middle(), w.normal(), 2.5, 1.34):
			face = w
			break
	if face == null:
		check.call(false, "a brick storefront window in Hickston to shoot at")
		return
	var mid: Vector2 = face.middle()
	var p := g.player
	var along := Vector2(face.edge.z - face.edge.x, face.edge.w - face.edge.y)
	# The brick at the window's side first, then its glass.
	var beside: Vector2 = Vector2(face.edge.x, face.edge.y) + along * .08
	var to := beside - Vector2(p.x, p.y)
	g.hitscan(to.angle(), (1.34 - p.eye) / to.length(), 36.0, 20.0, 0.0)
	var held: bool = not face.broken
	to = mid - Vector2(p.x, p.y)
	var bits_before: int = g.features["breakables"].bits.size()
	g.hitscan(to.angle(), (1.34 - p.eye) / to.length(), 36.0, 20.0, 0.0)
	var cell: Vector2i = face.cell
	check.call(
		(
			held
			and face.broken
			and _tiles_on(g, face.edge).has(face.shot)
			and not _tiles_on(g, face.edge).has(face.whole)
			and g.world.blocked(cell.x + .5, cell.y + .5, .1)
			and g.features["breakables"].bits.size() > bits_before
		),
		(
			(
				"a shot into a Hickston storefront's glass shoots it out (%s), glass flies, "
				+ "it stays a wall; the brick beside it does not"
			)
			% g.world.tile_names[face.shot]
		)
	)
	var path := OS.get_cache_dir().path_join("wall-break-check.json")
	SessionStore.save(g, path)
	var back: Game = SessionStore.read(path, Callable(main, "make_game"), false)
	var kept := false
	if back != null:
		kept = _tiles_on(back, face.edge).has(face.shot) and back.world.walls == g.world.walls
	check.call(kept, "a save keeps the window shot out")


## A fair fence cell that may open, shot with the revolver from in front:
## shot about after one (its faces in the `hit` tile), broken through after
## three: no face of its own left, its neighbours facing into it, floor to
## bodies, sight, shots and both flow fields, its picture standing in the gap,
## and a save keeps it so. One that may not open holds, shot about.
static func _fence_shot(main, check: Callable) -> void:
	var g := _game(main, "fair")
	var wb = g.features["wall_breaks"]
	var w := g.world
	var target = null
	var dir := Vector2.ZERO
	for f in wb.fences.values():
		if not f.opens:
			continue
		var centre := Vector2(f.cell.x + .5, f.cell.y + .5)
		for n: Vector2 in [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]:
			if _face(g, centre + n * .5, n, 2.0, .6) and _face(g, centre - n * .5, -n, 1.2, .6):
				target = f
				dir = n
				break
		if target != null:
			break
	if target == null:
		check.call(false, "a fair fence cell that may open, with room each side")
		return
	var c: Vector2i = target.cell
	var centre := Vector2(c.x + .5, c.y + .5)
	var near := centre + dir * 2.0
	var far := centre - dir * 1.2
	var shut := (
		w.blocked(centre.x, centre.y, .2)
		and not w.visible(near.x, near.y, far.x, far.y, .6, .6)
		and not g.flow.passable(c.y * w.width + c.x)
	)
	_face(g, centre + dir * .5, dir, 2.0, .6)
	var p := g.player
	var to := centre - Vector2(p.x, p.y)
	g.hitscan(to.angle(), (.6 - p.eye) / to.length(), 36.0, 20.0, 0.0)
	var own := 0
	var hit_shown := false
	for e: Array in LevelEdit.EDGES:
		var edge := Vector4(c.x + e[2], c.y + e[3], c.x + e[4], c.y + e[5])
		var tiles := _tiles_on(g, edge)
		own += tiles.size()
		hit_shown = hit_shown or tiles.has(target.hit_tile)
	var about: bool = target.stage == 1 and hit_shown and w.blocked(centre.x, centre.y, .2)
	for k in 2:
		g.hitscan(to.angle(), (.6 - p.eye) / to.length(), 36.0, 20.0, 0.0)
	var left := 0
	for e: Array in LevelEdit.EDGES:
		left += _tiles_on(g, Vector4(c.x + e[2], c.y + e[3], c.x + e[4], c.y + e[5])).size()
	# A neighbour that is solid shows a face toward the gap now.
	var facing := true
	for e: Array in LevelEdit.EDGES:
		var nx: int = c.x + int(e[0])
		var ny: int = c.y + int(e[1])
		if w.solid[ny * w.width + nx] >= 0:
			facing = (
				facing
				and not (
					_tiles_on(g, Vector4(c.x + e[4], c.y + e[5], c.x + e[2], c.y + e[3])).is_empty()
				)
			)
	var cell := c.y * w.width + c.x
	var through: bool = (
		target.stage == 2
		and left == 0
		and own > 0
		and facing
		and not w.blocked(centre.x, centre.y, .2)
		and w.visible(near.x, near.y, far.x, far.y, .6, .6)
		and g.flow.passable(cell)
		and g.route.passable(cell)
		and wb.sprites().size() >= 1
	)
	check.call(shut, "a fair fence cell stands shut to bodies, sight and paths")
	check.call(about, "one revolver round knocks it about (its faces show the boards out)")
	check.call(
		through,
		(
			"three break it through: its faces gone, its neighbours facing in, open to "
			+ "bodies, sight, shots and both paths, the gap's picture standing"
		)
	)
	# A round fired through the gap now flies on past it.
	p.x = near.x
	p.y = near.y
	p.eye = .95 + w.elevation(near.x, near.y)
	var way := (far - near).normalized()
	var reach: float = g._wall_distance(way.x, way.y, 0.0, 4.0)
	check.call(reach > near.distance_to(far), "a shot through the gap flies on (%.2f)" % reach)
	# One that may not open: shot to nothing, it holds, shot about.
	for level_id: String in LEVELS:
		var g2 := _game(main, level_id)
		var wb2 = g2.features["wall_breaks"]
		for f in wb2.fences.values():
			if f.opens:
				continue
			wb2._knock(f, 9999.0, 1.0, 0.0)
			var at: int = f.cell.y * g2.world.width + f.cell.x
			check.call(
				f.stage == 1 and g2.world.solid[at] >= 0 and not g2.flow.passable(at),
				"%s: a fence cell that may not open holds, shot about" % level_id
			)
			return


## The wall list as a sorted list of pieces (rounded), to compare two games.
static func _pieces(w: LevelData) -> Array:
	var out: Array = []
	for i in w.wall_count:
		var o := i * LevelData.WALL_STRIDE
		var row: Array = []
		for k in LevelData.WALL_STRIDE:
			row.append(snappedf(w.walls[o + k], .0001))
		out.append(str(row))
	out.sort()
	return out


## A stick of dynamite going off by a window shoots it out; one by a fence
## cell that may open takes it through.
static func _blasts(main, check: Callable) -> void:
	var g := _game(main, "hickston")
	var wb = g.features["wall_breaks"]
	var face = null
	for w in wb.windows:
		var front: Vector2 = w.middle() + w.normal() * 1.0
		if not g.world.blocked(front.x, front.y, .2):
			face = w
			break
	var fence = null
	for f in wb.fences.values():
		if not f.opens:
			continue
		for n: Vector2 in [Vector2(0, 1), Vector2(0, -1), Vector2(1, 0), Vector2(-1, 0)]:
			var at := Vector2(f.cell.x + .5, f.cell.y + .5) + n * .9
			if not g.world.blocked(at.x, at.y, .2):
				fence = [f, at]
				break
		if fence != null:
			break
	if face == null or fence == null:
		check.call(false, "a window and a fence cell in Hickston to blast")
		return
	var at: Vector2 = face.middle() + face.normal() * 1.0
	g.explode(Game.Shot.new(at.x, at.y, g.world.elevation(at.x, at.y) + .3, 0, 0, 0, "tnt"))
	var boom: Vector2 = fence[1]
	g.explode(Game.Shot.new(boom.x, boom.y, g.world.elevation(boom.x, boom.y) + .3, 0, 0, 0, "tnt"))
	check.call(
		face.broken and fence[0].stage == 2,
		"dynamite shoots out the window it goes off by and takes the fence cell through"
	)
	# A save keeps both, with the same walls (a chapter's save: Hickston).
	var c: Vector2i = fence[0].cell
	var cell := c.y * g.world.width + c.x
	var path := OS.get_cache_dir().path_join("wall-break-check.json")
	SessionStore.save(g, path)
	var back: Game = SessionStore.read(path, Callable(main, "make_game"), false)
	var kept := false
	if back != null:
		kept = (
			back.world.solid[cell] < 0
			and back.flow.passable(cell)
			and _pieces(back.world) == _pieces(g.world)
			and back.features["wall_breaks"].fences[c].stage == 2
			and _tiles_on(back, face.edge).has(face.shot)
		)
	check.call(
		kept,
		(
			"a save keeps the fence cell through and the window out, with the same walls"
			+ ("" if back != null else " (%s)" % SessionStore.last_error)
		)
	)
