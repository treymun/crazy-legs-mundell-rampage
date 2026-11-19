## The heavy scenes' speed work (pass 13, docs/dev/view3d.md "Keeping the
## frame cheap", checks.md "Measured in pass 13") stays exact and stays cheap.
##
##   godot --headless --path godot --script res://tools/heavy_check.gd
##
## - The wreck pieces' pair test (WreckPairs.leasts: both ways' least overlap
##   from one set of dots) gives exactly WreckPhysics._least(a, o) and
##   _least(o, a) for boxes turned and placed at random, touching and not.
## - LevelSight.visible (its blocked() and _past_cell written out) answers
##   exactly as v3.10.0's (kept here, _ref_visible) on random sight lines,
##   with and without heights, on chapters with furniture, decks and glass.
## - PhysCore.way_out (its last cell and furniture kept) gives exactly
##   v3.10.0's (_ref_way_out) for points in and about walls and furniture.
## - Counted, not timed: on hickston with a few breaks drawn by a view made
##   by hand, a frame drawn again unchanged sets no wreck piece's transform
##   (WreckLayer3D.placed) and hands no MultiMesh its rows again
##   (SpriteLayer3D.uploads).
##
## Prints HEAVY CHECK OK.
extends SceneTree

const LEVELS := ["hickston", "county_hickston", "grainyard", "mothership", "bayou"]
const LINES := 1500
const POINTS := 600

var failed := false


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	failed = failed or not ok


func _run() -> void:
	_pairs()
	var main: Node = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	for id: String in LEVELS:
		var g: Game = main.make_game(id)
		_sight(g, id)
		_way_out(g, id)
	await _drawn_again(main)
	print("HEAVY CHECK FAILED" if failed else "HEAVY CHECK OK")
	main.queue_free()
	await process_frame
	quit(1 if failed else 0)


# ------------------------------------------------------------------ pairs


func _pairs() -> void:
	var dice := RandomNumberGenerator.new()
	dice.seed = 1313
	var met := 0
	var bad := 0
	var out: Array = [Vector3.ZERO, Vector3.ZERO]
	for k in 4000:
		var a := _box(dice)
		var o := _box(dice)
		# Near each other (most touch); now and then turned alike or both
		# square (the axes' overlaps tie).
		o.p = a.p + Vector3(randf_in(dice, .4), randf_in(dice, .4), randf_in(dice, .3))
		if k % 9 == 0:
			o.q = a.q
		if k % 13 == 0:
			o.q = Quaternion.IDENTITY
			a.q = Quaternion.IDENTITY
		a.turned()
		o.turned()
		var want_a := WreckPhysics._least(a, o)
		var want_o := WreckPhysics._least(o, a)
		var got := WreckPairs.leasts(a, o, k, out)
		if want_a == Vector3.ZERO:
			bad += 1 if got or want_o != Vector3.ZERO else 0
			continue
		met += 1
		var got_a: Vector3 = out[0]
		var got_o: Vector3 = out[1]
		bad += 0 if got and got_a == want_a and got_o == want_o else 1
	_check(
		bad == 0 and met > 1000,
		(
			"pairs: %d of 4000 pairs overlap; both ways' least exactly _least's (%d differ)"
			% [met, bad]
		)
	)


static func randf_in(dice: RandomNumberGenerator, r: float) -> float:
	return dice.randf_range(-r, r)


func _box(dice: RandomNumberGenerator) -> WreckPhysics.Body:
	var b := WreckPhysics.Body.new()
	b.made_of(
		Vector3(dice.randf_range(.02, .4), dice.randf_range(.01, .1), dice.randf_range(.02, .3)),
		WreckPhysics.stuff_of("wood"),
		"board"
	)
	b.p = Vector3(dice.randf_range(5, 10), dice.randf_range(5, 10), dice.randf_range(0, 1))
	var axis := Vector3(randf_in(dice, 1.0), randf_in(dice, 1.0), randf_in(dice, 1.0))
	b.q = Quaternion(axis.normalized(), randf_in(dice, PI))
	b.awake = true
	return b


# ------------------------------------------------------------------ sight


func _sight(g: Game, id: String) -> void:
	var w := g.world
	var dice := RandomNumberGenerator.new()
	dice.seed = hash(id)
	var bad := 0
	var seen := 0
	for k in LINES:
		var a := _open_spot(w, dice)
		var b := a + Vector2.from_angle(dice.randf() * TAU) * dice.randf_range(.5, 18.0)
		b = b.clamp(Vector2(.5, .5), Vector2(w.width - .5, w.height - .5))
		var heights := k % 4 != 0
		var z0: Variant = null
		var z1: Variant = null
		if heights:
			z0 = w.elevation(a.x, a.y) + dice.randf_range(.2, 1.8)
			z1 = w.elevation(b.x, b.y) + dice.randf_range(.2, 1.8)
		var want := _ref_visible(w, a.x, a.y, b.x, b.y, z0, z1)
		var got := LevelSight.visible(w, a.x, a.y, b.x, b.y, z0, z1)
		seen += 1 if got else 0
		bad += 0 if got == want else 1
	_check(
		bad == 0,
		"%s: %d sight lines (%d clear) as v3.10.0 saw them (%d differ)" % [id, LINES, seen, bad]
	)


func _open_spot(w: LevelData, dice: RandomNumberGenerator) -> Vector2:
	for k in 50:
		var at := Vector2(dice.randf_range(1, w.width - 1), dice.randf_range(1, w.height - 1))
		if w.solid[w.cell(at.x, at.y)] < 0:
			return at
	return Vector2(w.width * .5, w.height * .5)


# ------------------------------------------------------------------ way out


func _way_out(g: Game, id: String) -> void:
	var w := g.world
	var dice := RandomNumberGenerator.new()
	dice.seed = hash(id) + 7
	var bad := 0
	var found := 0
	# Points in and about the furniture (half of them) and anywhere.
	var spots: Array[Vector2] = []
	for f: PackedFloat32Array in w.collision_volumes:
		spots.append(Vector2((f[0] + f[2]) * .5, (f[1] + f[3]) * .5))
	for k in POINTS:
		var at := Vector2(dice.randf_range(1, w.width - 1), dice.randf_range(1, w.height - 1))
		if not spots.is_empty() and k % 2 == 0:
			at = (
				spots[dice.randi() % spots.size()] + Vector2(randf_in(dice, .7), randf_in(dice, .7))
			)
		var p := Vector3(at.x, at.y, w.elevation(at.x, at.y) + dice.randf_range(-.1, 1.2))
		var want := _ref_way_out(w, p)
		var got := PhysCore.way_out(w, p)
		found += 1 if got != Vector3.ZERO else 0
		bad += 0 if got == want else 1
	_check(
		bad == 0,
		"%s: way_out at %d points (%d out) as v3.10.0's (%d differ)" % [id, POINTS, found, bad]
	)


# ------------------------------------------------------------------ drawn again


## Hickston with a few breaks drawn by a view made by hand: the same frame
## drawn again sets no piece's transform and hands no rows over.
func _drawn_again(main: Node) -> void:
	main.start("hickston")
	var g: Game = main.game
	main.state = "play"
	g.cheats.god = true
	for e: Enemy in g.enemies:
		e.dormant = true
	var breaks: GameFeature = g.features.get("breakables")
	var pieces: Array = breaks.get("pieces")
	var can: Array[int] = []
	for i in pieces.size():
		var bp: Object = pieces[i]
		var spec: Dictionary = bp.get("spec")
		if not bp.get("broken") and str(spec.get("pieces", "")) != "":
			can.append(i)
	var thrown := 0
	if not can.is_empty():
		# The densest cluster (stress_bench's wreck48), seen from six cells off.
		var mid := Vector2.ZERO
		var most := -1
		for i: int in can:
			var bi: Object = pieces[i]
			var at := Vector2(bi.get("x"), bi.get("y"))
			var near := 0
			for j: int in can:
				var bj: Object = pieces[j]
				near += 1 if at.distance_to(Vector2(bj.get("x"), bj.get("y"))) < 5.0 else 0
			if near > most:
				most = near
				mid = at
		var p := g.player
		p.x = mid.x + 6.0
		p.y = mid.y
		p.angle = PI
		for i: int in can:
			var bp: Object = pieces[i]
			var at := Vector2(bp.get("x"), bp.get("y"))
			if at.distance_to(mid) < 5.0 and thrown < 6:
				breaks.call("strike", i, 9999.0, -1.0, 0.0)
				thrown += 1
	var view := WorldView3D.new(g.art)
	main.add_child(view)
	for k in 90:
		g.tick(1.0 / 60.0, Game.Controls.new())
		main.render()
		view.frame(g)
		await process_frame
	# The same frame again, twice: nothing ticked, nothing moved.
	main.render()
	view.frame(g)
	var placed := WreckLayer3D.placed
	var uploads := SpriteLayer3D.uploads
	main.render()
	view.frame(g)
	var shown: int = view.wrecks.shown().size()
	_check(
		thrown > 0 and shown > 0 and WreckLayer3D.placed == placed,
		(
			"hickston: %d breaks, %d pieces drawn; drawn again, %d transforms set (none)"
			% [thrown, shown, WreckLayer3D.placed - placed]
		)
	)
	_check(
		SpriteLayer3D.uploads == uploads,
		(
			"hickston: drawn again, %d MultiMeshes handed rows again (none)"
			% [SpriteLayer3D.uploads - uploads]
		)
	)
	view.queue_free()
	main.game = null
	await process_frame


## v3.10.0's LevelSight.visible, as it was (the reference).
## Mirrors TileMap.visible(): a stepped line-of-sight test.
static func _ref_visible(
	lv: LevelData, x: float, y: float, xx: float, yy: float, z: Variant = null, zz: Variant = null
) -> bool:
	# No heights given (z null): the flat test it always was, furniture in the
	# way whatever its height; geometry stops it where it stands in a body's
	# way (blocked(): a deck overhead does not, a stair or a wall does).
	# (The level's tables read once into locals: this loop runs for every
	# step of every sight line, and a read through `lv` costs twice a local.)
	var w := lv.width
	var hgt := lv.height
	var solid := lv.solid
	var index_cells := lv.index_cells
	var clear_cells := lv.clear_cells
	var box_cells := lv.box_cells
	var pane_cells := lv.pane_cells
	var furniture_cells := lv.furniture_cells
	var geo := lv.geo
	var distance := sqrt((xx - x) * (xx - x) + (yy - y) * (yy - y))
	var n := maxi(1, ceili(distance * 9.0))
	# With no panes and no locked gates, a step whose four corners are open floor
	# and whose cell neither index lists is clear, as blocked() would find: those
	# steps (most of them) are tested here without the call.
	# A level with glass (pass 10) too, but a step in a cell a pane may meet
	# (pane_cells) asks blocked() as ever.
	var glassless := lv.pane_tiles.is_empty()
	var plain := (
		(glassless or pane_cells.size() == w * hgt)
		and lv.locked_gates.is_empty()
		and index_cells.size() == w * hgt
	)
	var fast := plain and clear_cells.size() == w * hgt
	var boxed := fast and box_cells.size() == w * hgt
	# At heights on a level with geometry, a step in a cell the geometry alone
	# lists (no furniture, no door) whose heights lie outside the cell's sight
	# bands is clear too (LevelGeometry.sight_clear: what blocked() and
	# crosses() would find there, by a cheaper test that never says clear
	# where they would not).
	var banded := (
		plain
		and z != null
		and geo != null
		and furniture_cells.size() == w * hgt
		and geo.sight_band_at.size() == w * hgt + 1
	)
	var z0 := LevelData._float(z) if banded else 0.0
	var z1 := LevelData._float(zz) if banded else 0.0
	var i := 1
	while i < n:
		var t := float(i) / float(n)
		var sx := x + (xx - x) * t
		var sy := y + (yy - y) * t
		if fast and sx >= 0.0 and sy >= 0.0:
			var cx := int(sx)
			var cy := int(sy)
			var glass := not glassless and cx < w and cy < hgt
			if glass and pane_cells[cy * w + cx] != 0:
				pass
			elif cx < w and cy < hgt and clear_cells[cy * w + cx] != 0:
				i = LevelSight._past_cell(x, y, xx, yy, n, i, cx, cy)
				continue
			elif boxed and cx < w and cy < hgt and box_cells[cy * w + cx] != 0:
				var j := LevelSight._past_cell(x, y, xx, yy, n, i, cx, cy)
				var t1 := float(j - 1) / float(n)
				if (
					LevelSight._walls_clear(
						lv, cx, cy, sx, sy, x + (xx - x) * t1, y + (yy - y) * t1
					)
					and (
						index_cells[cy * w + cx] == 0
						or not LevelSight._boxes_met(lv, cx, cy, x, y, xx, yy, z, zz, t, t1)
					)
				):
					i = j
					continue
		if plain:
			var ax := int(sx + -.023)
			var bx := int(sx + .023)
			var ay := int(sy + -.023)
			var by := int(sy + .023)
			if ax < 0 or ay < 0 or bx >= w or by >= hgt:
				return false
			if (
				solid[ay * w + ax] >= 0
				or solid[by * w + ax] >= 0
				or solid[ay * w + bx] >= 0
				or solid[by * w + bx] >= 0
			):
				return false
			var cell := int(sy) * w + int(sx)
			var paned := not glassless and pane_cells[cell] != 0
			if index_cells[cell] == 0 and not paned:
				i += 1
				continue
			if banded and furniture_cells[cell] == 0 and not paned:
				var step_z := z0 + (z1 - z0) * t
				var back_z := z0 + (z1 - z0) * (float(i - 1) / float(n))
				if geo.sight_clear(cell, back_z, step_z):
					i += 1
					continue
		var wz: Variant = null
		if z != null:
			wz = LevelData._float(z) + (LevelData._float(zz) - LevelData._float(z)) * t
		if lv.blocked(sx, sy, .023, wz):
			return false
		if geo != null and wz != null and geo.cells[int(sy) * w + int(sx)] != 0:
			# A steep look can step over a deck thinner than one step climbs.
			var bt := float(i - 1) / float(n)
			var bz := LevelData._float(z) + (LevelData._float(zz) - LevelData._float(z)) * bt
			if geo.crosses(x + (xx - x) * bt, y + (yy - y) * bt, bz, sx, sy, LevelData._float(wz)):
				return false
		i += 1
	return true


## v3.10.0's PhysCore.way_out, as it was (the reference).
static func _ref_way_out(world: LevelData, at: Vector3) -> Vector3:
	var w := world.width
	var hgt := world.height
	var cells := world.solid
	var plain_world := (
		world.locked_gates.is_empty()
		and (world.pane_tiles.is_empty() or world.pane_cells.size() == w * hgt)
	)
	# Per cell: its furniture list (null: asked probe by probe); per cell and
	# furniture held, the answer (1 solid, 0 clear).
	var lists := {}
	var answers := {}
	var s := PhysCore.WALL_STEP
	while s <= PhysCore.WALL_REACH:
		for dir: Vector3 in PhysCore.WAYS:
			var probe := at + dir * s
			if probe.x < 0.0 or probe.y < 0.0 or probe.x >= w or probe.y >= hgt:
				continue
			var ix := int(probe.x)
			var iy := int(probe.y)
			var c := iy * w + ix
			if cells[c] >= 0:
				continue
			if not lists.has(c):
				lists[c] = PhysCore._held_list(world, plain_world, ix, iy, c)
			var listed: Variant = lists[c]
			if listed == null:
				if not PhysCore._in_something(world, probe):
					return dir * s
				continue
			var fixtures: Array = listed
			var held := 0
			for k in fixtures.size():
				var f: PackedFloat32Array = fixtures[k]
				if f[0] < probe.x and probe.x < f[2] and f[1] < probe.y and probe.y < f[3]:
					held |= 1 << k
			var key := c * PhysCore.HELD_KINDS + held
			var answer: int = answers.get(key, -1)
			if answer < 0:
				answer = 1 if PhysCore._in_something(world, probe) else 0
				answers[key] = answer
			if answer == 0:
				return dir * s
		s += PhysCore.WALL_STEP
	return Vector3.ZERO
