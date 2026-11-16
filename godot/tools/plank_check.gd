## The plank walls that break (features/wall_breaks.gd, src/plank_walls.gd;
## tools/check_all.gd runs it, quick too):
##
##   godot --headless --path godot --script res://tools/plank_check.gd
##
## For each kind (a barn's wall and a pen's fence under the barn's roof at the
## fair, a shed's wall at the sawmill, a shack's wall on the bayou, a barn's
## wall with its gable on the County Run's Hickston): there is one that may
## open; shot about, its own face shows its boards knocked out (a merged run
## of boards cut at the cell first, the rest of the run left as it was);
## broken through it is floor to bodies, sight and both flow fields, a body
## walks through it, a shed's wall keeps its roof over the gap (and the gable
## above it) and a pen's neighbours show faces only their own height; its
## planks fly and come to rest on a floor, inside nothing; a snapshot put on a
## fresh game and a save put back open the same cell with the same walls.
## (No set of them joins ground the level keeps apart: break_check's
## wall_break_check opens them all; quest_reach is unchanged by them.)
extends SceneTree

const DT := 1.0 / 60.0
## How far into anything a piece at rest may be (cells).
const TOL := .03
## [level, tile, kind]: "shed" a wall under a roof on one side, "pen" a
## fence under a roof, "gable" a shed wall with wall kept above its roof.
const CASES := [
	["fair", "barn", "shed"],
	["fair", "stockyard", "pen"],
	["sawmill", "wood", "shed"],
	["bayou", "bayou_shack", "shed"],
	["county_hickston", "barn", "gable"],
]

var failures: Array = []
var passes := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	var started := Time.get_ticks_msec()
	for case: Array in CASES:
		print("\n%s %s (%s)" % [str(case[0]).to_upper(), case[1], case[2]])
		_case(main, str(case[0]), str(case[1]), str(case[2]))
	print("")
	print(
		(
			"%d checks in %.1f s"
			% [passes + failures.size(), (Time.get_ticks_msec() - started) / 1000.0]
		)
	)
	print("PLANK CHECK OK" if failures.is_empty() else "%d PLANK CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


func _check(ok: bool, text: String) -> void:
	if ok:
		passes += 1
		print("  ok   ", text)
	else:
		print("  FAIL ", text)
		failures.append(text)


func _game(main: Control, id: String) -> Game:
	var g: Game = main.make_game(id)
	g.configure({})
	g.cheats.god = true
	for e: Enemy in g.enemies:
		e.dormant = true
	return g


func _ticks(g: Game, n: int) -> void:
	var held := Game.Controls.new()
	for i in n:
		g.tick(DT, held)


## The first fence of `tile` that may open as `kind`.
func _find(g: Game, tile: String, kind: String):
	var wb = g.features["wall_breaks"]
	var id := g.world.tile_id(tile)
	var keys: Array = wb.fences.keys()
	keys.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return a.y * 1000 + a.x < b.y * 1000 + b.x
	)
	for key: Vector2i in keys:
		var f = wb.fences[key]
		if f.tile != id or not f.opens:
			continue
		if kind == "pen" and not f.low:
			continue
		if (kind == "shed" or kind == "gable") and f.inside < 0:
			continue
		if kind == "gable" and _above(g, f.cell, g.world.roof[f.inside]) == 0:
			continue
		return f
	return null


## Pieces on the cell's own edges standing wholly at or above `top`.
static func _above(g: Game, cell: Vector2i, top: float) -> int:
	var w := g.world
	var n := 0
	var cover := PlankWalls.coverage(w)
	for e: Array in LevelEdit.EDGES:
		var key := Vector4(cell.x + e[2], cell.y + e[3], cell.x + e[4], cell.y + e[5])
		for row: Vector3 in cover.get(key, []):
			if row.y >= top - .01:
				n += 1
	return n


## The wall rows as sorted text: two games' walls compared as sets.
static func _rows(w: LevelData) -> Array:
	var out: Array = []
	for i in w.wall_count:
		var o := i * LevelData.WALL_STRIDE
		var row := []
		for k in LevelData.WALL_STRIDE:
			row.append(snappedf(w.walls[o + k], .001))
		out.append(str(row))
	out.sort()
	return out


func _case(main, id: String, tile: String, kind: String) -> void:
	var g := _game(main, id)
	var wb = g.features["wall_breaks"]
	var wreck = g.features["wreckage"]
	var f = _find(g, tile, kind)
	_check(f != null, "%s: a %s %s that may open" % [id, tile, kind])
	if f == null:
		return
	var w := g.world
	var cell: Vector2i = f.cell
	var c := cell.y * w.width + cell.x
	var centre := Vector2(cell.x + .5, cell.y + .5)
	var gable := 0
	var roof_was := 0.0
	if f.inside >= 0:
		roof_was = w.roof[f.inside]
		gable = _above(g, cell, roof_was)
	var runs_before := w.wall_count
	# Shot about: its own faces show the boards knocked out.
	wb._knock(f, f.most * .5, 1.0, 0.0)
	_ticks(g, 1)
	var hit_faces := 0
	for e: Array in LevelEdit.EDGES:
		var edge: Vector4 = wb._own_edge(cell, e)
		for i in w.walls_on(edge.x, edge.y, edge.z, edge.w):
			if String(w.tile_names[int(w.walls[i * LevelData.WALL_STRIDE + 4])]).ends_with("_hit"):
				hit_faces += 1
	if hit_faces == 0:
		for e: Array in LevelEdit.EDGES:
			var edge: Vector4 = wb._own_edge(cell, e)
			for i in w.walls_on(edge.x, edge.y, edge.z, edge.w):
				print(
					(
						"       face %s: %s"
						% [edge, w.tile_names[int(w.walls[i * LevelData.WALL_STRIDE + 4])]]
					)
				)
	_check(
		f.stage == 1 and hit_faces > 0,
		(
			"%s: shot about, its face shows its boards out (%d faces; %d wall pieces were %d)"
			% [id, hit_faces, w.wall_count, runs_before]
		)
	)
	_check(w.blocked(centre.x, centre.y, .2), "%s: shot about, it still stands" % id)
	# Broken through.
	var pieces_before: int = wreck.wrecks.size()
	wb._knock(f, f.most * 3.0, 1.0, 0.0)
	_ticks(g, 1)
	_check(f.stage == 2 and w.solid[c] < 0, "%s: broken through, its cell is open" % id)
	_check(not w.blocked(centre.x, centre.y, .25), "%s: a body fits in the gap" % id)
	_check(g.flow.open[c] != 0, "%s: the flow field goes through the gap" % id)
	# The two sides it parted: seen and walked from one to the other.
	var sides: Array = []
	for e: Array in LevelEdit.EDGES:
		var n := Vector2i(cell.x + e[0], cell.y + e[1])
		if w.solid[n.y * w.width + n.x] < 0:
			sides.append(Vector2(n.x + .5, n.y + .5))
	var seen: bool = (
		sides.size() >= 2
		and w.visible(
			sides[0].x, sides[0].y, sides[1].x, sides[1].y, w.ground[c] + 1.0, w.ground[c] + 1.0
		)
	)
	_check(seen, "%s: sight goes through the gap" % id)
	var p := g.player
	if sides.size() >= 2:
		p.x = sides[0].x
		p.y = sides[0].y
		p.floor_z = w.ground[c]
		p.angle = atan2(sides[1].y - sides[0].y, sides[1].x - sides[0].x)
		for t in 90:
			var walk := Game.Controls.new()
			walk.forward = 1.0
			g.tick(DT, walk)
	_check(
		sides.size() >= 2 and Vector2(p.x, p.y).distance_to(sides[0]) > 1.4,
		(
			"%s: the player walks through the gap (%.1f cells)"
			% [id, Vector2(p.x, p.y).distance_to(sides[0])]
		)
	)
	if kind == "shed" or kind == "gable":
		_check(
			absf(w.roof[c] - roof_was) < .001 and w.ceiling_tile[c] == w.ceiling_tile[f.inside],
			"%s: the roof runs on over the gap (%.2f)" % [id, w.roof[c]]
		)
	if kind == "gable":
		var still := 0
		for e: Array in LevelEdit.EDGES:
			var edge: Vector4 = wb._own_edge(cell, e)
			for i in w.walls_on(edge.x, edge.y, edge.z, edge.w):
				if w.walls[i * LevelData.WALL_STRIDE + 6] >= roof_was - .01:
					still += 1
		_check(
			still == gable and gable > 0,
			"%s: the gable over it stays (%d of %d)" % [id, still, gable]
		)
	if kind == "pen":
		var tallest := 0.0
		for e: Array in LevelEdit.EDGES:
			var n := Vector2i(cell.x + e[0], cell.y + e[1])
			var k := n.y * w.width + n.x
			if w.solid[k] < 0:
				continue
			# Its face toward the gap: the gap's own edge the other way round.
			var own: Vector4 = wb._own_edge(cell, e)
			for i in w.walls_on(own.z, own.w, own.x, own.y):
				tallest = maxf(tallest, w.walls[i * LevelData.WALL_STRIDE + 7] - w.wall_height[k])
		_check(
			tallest < .01, "%s: its neighbours' faces stand their own height under the roof" % id
		)
	# Its planks fly and come to rest on a floor.
	_check(
		wreck.wrecks.size() > pieces_before,
		"%s: its planks fly (%d)" % [id, wreck.wrecks.size() - pieces_before]
	)
	var waited := 0
	while wreck.physics.moving() and waited < 900:
		_ticks(g, 10)
		waited += 10
	var worst := 0.0
	var floating := 0
	for piece in wreck.wrecks:
		var d: float = wreck.physics.inside(piece.body)
		if d > TOL:
			print("       inside %.3f: %s at %s" % [d, piece.key, piece.body.p])
			var turn := Basis(piece.body.q)
			for k in 8:
				var q: Vector3 = piece.body.p + turn * piece.body.points[k]
				print(
					(
						"         corner %s floor %.3f solid %s"
						% [q, Tumble.floor_at(w, q.x, q.y, q.z + .02), wreck.physics.solid(q)]
					)
				)
		worst = maxf(worst, d)
		if wreck.physics.unsupported(piece.body):
			floating += 1
	_check(
		not wreck.physics.moving() and worst <= TOL and floating == 0,
		(
			"%s: they come to rest on a floor (%.1f s, worst %.3f in, %d hang)"
			% [id, waited * DT, worst, floating]
		)
	)
	# Carried: a snapshot put on a fresh game opens the same cell, the same walls.
	var snap := GameSnapshot.capture(g)
	var copy := _game(main, id)
	GameSnapshot.apply(copy, snap)
	var f2 = copy.features["wall_breaks"].fences.get(cell)
	_check(
		(
			f2 != null
			and f2.stage == 2
			and copy.world.solid[c] < 0
			and absf(copy.world.roof[c] - w.roof[c]) < .001
		),
		"%s: a snapshot carries it open" % id
	)
	_check(
		_rows(copy.world) == _rows(w), "%s: with the same walls (%d pieces)" % [id, w.wall_count]
	)
	# A save puts it back the same.
	var saved: Dictionary = wb.save()
	var loaded := _game(main, id)
	loaded.features["wall_breaks"].restore(saved)
	_check(
		loaded.world.solid[c] < 0 and _rows(loaded.world) == _rows(w),
		"%s: a save puts it back open, the same walls" % id
	)
