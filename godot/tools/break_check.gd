## Checks of what breaks and what moves loose (tools/check_fixes.gd runs them;
## this also runs on its own, from a scratch profile):
##
##   Godot --headless --path <project> --script res://tools/break_check.gd
##
## Every chapter, the Crossroads and the range have things that break, each
## with its broken picture; a crate that stood in the way frees its cell for
## the paths when it breaks, and stays broken in a save; a hazard barrel set
## off sets off its neighbour (the chain reaction); a blast pushes a loose
## barrel it did not break; a body knocked into a wall stops against it, and a
## load of buckshot throws a body further than a revolver round; a stick of
## dynamite and a bowling ball roll downhill. Then the walls that break
## (tools/wall_break_check.gd): windows shot out, fence cells broken through,
## and none that opens joins ground the level keeps apart.
extends SceneTree

const LEVELS := [
	"hickston", "fair", "sawmill", "quarry", "bayou", "speedway", "mothership", "hub", "range"
]

var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	run(
		main,
		func(ok: bool, text: String) -> void:
			print("  ok   " if ok else "  FAIL ", text)
			if not ok:
				failures.append(text)
	)
	print("")
	print("BREAK CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


static func _game(main, level_id: String) -> Game:
	var g: Game = main.make_game(level_id)
	g.configure({})
	g.cheats.god = true
	return g


static func _ticks(g: Game, seconds: float) -> void:
	for _k in int(seconds * 60.0):
		g.update_shots(1.0 / 60.0)
		g.ticked.emit(1.0 / 60.0)


static func run(main, check: Callable) -> void:
	print("THINGS THAT BREAK, BODIES AND BLASTS")
	var cfg := Tuning.file("res://data/tuning/breakables.cfg")
	var pictures := true
	for section in cfg.get_sections():
		# The windows' broken pictures are tiles (wall_break_check.gd holds them).
		if section == "all" or section == "windows":
			continue
		if not main.art.has_art(String(cfg.get_value(section, "broken", ""))):
			pictures = false
			print("    no broken picture for ", section)
	check.call(pictures, "every breakable has its broken picture")
	var counts: Array = []
	for level_id: String in LEVELS:
		var g := _game(main, level_id)
		var n: int = g.features["breakables"].pieces.size()
		counts.append("%s %d" % [level_id, n])
		check.call(n >= 4, "%s has things that break (%d)" % [level_id, n])
	print("    ", ", ".join(counts))
	_opens_no_new_ground(main, check)
	_frees_its_cell(main, check)
	_chain(main, check)
	_shoves_a_barrel(main, check)
	_bodies(main, check)
	_rolls_downhill(main, check)
	preload("res://tools/wall_break_check.gd").run(main, check)


## Breaking every piece that stands in the way, in every level, lets the player
## reach no ground they could not reach before but the pieces' own cells: no
## breakable is the only thing shutting a way the level means to be shut.
static func _opens_no_new_ground(main, check: Callable) -> void:
	var opened: Array = []
	for level_id: String in LEVELS:
		var g := _game(main, level_id)
		var before := _reach(g)
		var bases: Array = []
		for p in g.features["breakables"].pieces:
			if not p.base.is_empty() and not bases.has(p.base):
				bases.append(p.base)
		for b: PackedFloat32Array in bases:
			g.world.drop_volume(b)
			g.flow.reopen(b[0], b[1], b[2], b[3])
		for cell: Vector2i in _reach(g):
			if before.has(cell):
				continue
			var near := false
			for b: PackedFloat32Array in bases:
				near = (
					near
					or (
						cell.x >= int(b[0]) - 1
						and cell.x <= int(b[2]) + 1
						and cell.y >= int(b[1]) - 1
						and cell.y <= int(b[3]) + 1
					)
				)
			if not near:
				opened.append("%s %s" % [level_id, cell])
	check.call(
		opened.is_empty(),
		(
			"breaking everything that stands in the way opens no new ground"
			+ ("" if opened.is_empty() else " %s" % [opened.slice(0, 6)])
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


## A piece that stood in the way (not one that goes up) breaks and frees its
## cell, and a save keeps it broken and out of the way.
static func _frees_its_cell(main, check: Callable) -> void:
	var g := _game(main, "hickston")
	var br = g.features["breakables"]
	var piece = null
	for p in br.pieces:
		if not p.base.is_empty() and not p.spec.has("blast"):
			piece = p
			break
	check.call(piece != null, "Hickston has a pallet stack or the like standing in the way")
	if piece == null:
		return
	var cell: int = int(piece.y) * g.world.width + int(piece.x)
	check.call(
		g.world.blocked(piece.x, piece.y, .2) and not g.flow.passable(cell),
		"%s stands in the way and closes its cell" % piece.image
	)
	br.strike(br.pieces.find(piece), 999.0, 1.0, 0.0)
	check.call(
		(
			piece.broken
			and not g.world.blocked(piece.x, piece.y, .2)
			and g.flow.passable(cell)
			and g.route.passable(cell)
		),
		"shot to pieces, it frees its cell for the paths"
	)
	check.call(br.bits.size() > 3, "and leaves its bits lying (%d)" % br.bits.size())
	var path := OS.get_cache_dir().path_join("break-check.json")
	SessionStore.save(g, path)
	var back: Game = SessionStore.read(path, Callable(main, "make_game"), false)
	var kept := false
	if back != null:
		for p in back.features["breakables"].pieces:
			if p.id == piece.id:
				kept = p.broken and not back.world.blocked(p.x, p.y, .2)
	check.call(
		kept,
		(
			"a save keeps it broken and out of the way"
			+ ("" if kept else " (%s)" % SessionStore.last_error)
		)
	)


## A hazard barrel, gas can, propane tank or crate of dynamite shot goes up,
## and its blast sets off the next one standing near it.
static func _chain(main, check: Callable) -> void:
	for level_id: String in LEVELS:
		var g := _game(main, level_id)
		var br = g.features["breakables"]
		for a in br.pieces:
			if not a.spec.has("blast"):
				continue
			for b in br.pieces:
				if (
					b == a
					or not b.spec.has("blast")
					or Vector2(a.x - b.x, a.y - b.y).length() > 2.5
					or not g.world.visible(a.x, a.y, b.x, b.y, .6, .6)
				):
					continue
				var booms := [0]
				g.exploded.connect(func(_x, _y, _z, _e) -> void: booms[0] += 1)
				br.strike(br.pieces.find(a), 999.0, 1.0, 0.0)
				_ticks(g, 1.5)
				check.call(
					a.broken and b.broken and booms[0] >= 2,
					(
						"%s: a shot %s goes up and sets off the %s by it (%d blasts)"
						% [level_id, a.image, b.image, booms[0]]
					)
				)
				return
	check.call(false, "two explosives stand close enough somewhere to chain")


## A blast that does not break a loose barrel pushes it away.
static func _shoves_a_barrel(main, check: Callable) -> void:
	var g := _game(main, "hickston")
	var br = g.features["breakables"]
	for p in br.pieces:
		if p.image != "prop_barrel":
			continue
		for a in 16:
			var at := Vector2(p.x, p.y) + Vector2.from_angle(a * TAU / 16.0) * 2.55
			if g.world.blocked(at.x, at.y, .1) or not g.world.visible(at.x, at.y, p.x, p.y):
				continue
			var was := Vector2(p.x, p.y)
			var shot := Game.Shot.new(at.x, at.y, g.world.elevation(at.x, at.y) + .5)
			shot.kind = "fuel"
			g.explode(shot)
			var now := Vector2(p.x, p.y)
			check.call(
				not p.broken and now.distance_to(at) > was.distance_to(at) + .02,
				"a blast pushes a barrel it did not break away (%.2f)" % now.distance_to(was)
			)
			return
	check.call(false, "a loose barrel with room round it in Hickston")


## A body killed by a wall is knocked against it and stops there, and
## buckshot throws a body further than a revolver round.
static func _bodies(main, check: Callable) -> void:
	var g := _game(main, "hickston")
	var hands: Array = []
	for e: Enemy in g.enemies:
		if e.hostile and e.alive and not Enemy.BOSS_TITLES.has(e.kind) and e.brain == "billy":
			hands.append(e)
	if hands.size() < 3:
		check.call(false, "three hands in Hickston to knock about")
		return
	# A spot with a wall half a cell east and room west for the player.
	var spot := Vector2i(-1, -1)
	for cy in range(2, g.world.height - 2):
		for cx in range(3, g.world.width - 3):
			if (
				g.world.solid[cy * g.world.width + cx + 1] >= 0
				and not g.world.blocked(cx + .45, cy + .5, .3)
				and not g.world.blocked(cx - 1.0, cy + .5, .3)
				and g.world.elevation(cx + .45, cy + .5) == g.world.elevation(cx - 1.0, cy + .5)
				and g.world.visible(cx - 1.0, cy + .5, cx + .45, cy + .5)
			):
				spot = Vector2i(cx, cy)
				break
		if spot.x >= 0:
			break
	var body: Enemy = hands[0]
	body.x = spot.x + .45
	body.y = spot.y + .5
	g.player.x = spot.x - 1.0
	g.player.y = spot.y + .5
	var start := body.x
	# Short of an overkill (which takes a body apart instead).
	body.hp = 30.0
	body.hurt(40.0, g, false, false, null, "shotgun")
	var clear := true
	for _k in 120:
		g.ticked.emit(1.0 / 60.0)
		clear = clear and not g.world.blocked(body.x, body.y, .2)
	check.call(
		body.x > start + .05 and clear,
		"a body knocked at a wall slides up to it and stops, never in it (%.2f)" % (body.x - start)
	)
	# Out in the open: the same spot each, one shot each way.
	var gaps: Array = []
	for k in 2:
		var g2 := _game(main, "hickston")
		var e: Enemy = g2.enemies[g.enemies.find(hands[1 + k])]
		var open := _open_spot(g2)
		e.x = open.x
		e.y = open.y
		g2.player.x = open.x - 1.2
		g2.player.y = open.y
		e.hp = 30.0
		e.hurt(40.0, g2, false, false, null, "revolver" if k == 0 else "shotgun")
		for _j in 120:
			g2.ticked.emit(1.0 / 60.0)
		gaps.append(absf(e.x - open.x))
	check.call(
		gaps[1] > gaps[0] * 1.5 and gaps[0] > .05,
		"buckshot throws a body further than a revolver round (%.2f, %.2f)" % [gaps[1], gaps[0]]
	)


## A flat stretch of floor with room for a body to slide three cells east and
## for the player a cell west.
static func _open_spot(g: Game) -> Vector2:
	var w: LevelData = g.world
	for cy in range(2, w.height - 2):
		for cx in range(3, w.width - 5):
			var at := Vector2(cx + .5, cy + .5)
			var flat := true
			for k in range(-2, 5):
				var q := at + Vector2(k * .6, 0)
				flat = (
					flat
					and not w.blocked(q.x, q.y, .35)
					and w.elevation(q.x, q.y) == w.elevation(at.x, at.y)
				)
			if flat and w.visible(at.x - 1.2, at.y, at.x, at.y):
				return at
	return Vector2(g.player.x, g.player.y)


## A stick of dynamite left at the top of a step rolls down it, and so does a
## bowling ball.
static func _rolls_downhill(main, check: Callable) -> void:
	for level_id: String in ["mothership", "bayou", "sawmill", "hickston"]:
		var g := _game(main, level_id)
		var w: LevelData = g.world
		for cy in range(1, w.height - 1):
			for cx in range(1, w.width - 3):
				var here := w.elevation(cx + .5, cy + .5)
				var drop := here - w.elevation(cx + 1.5, cy + .5)
				if (
					drop < .2
					or drop > .3
					or w.elevation(cx + 2.5, cy + .5) > here - drop
					or w.blocked(cx + .75, cy + .5, .25)
					or w.blocked(cx + 1.5, cy + .5, .25)
					or w.blocked(cx + 2.5, cy + .5, .25)
				):
					continue
				var stick := Game.Shot.new(cx + .75, cy + .5, here + .045, 0, 0, 0, "tnt", 3.0)
				g.shots.append(stick)
				_ticks(g, 1.2)
				check.call(
					stick.x > cx + 1.0 and w.elevation(stick.x, stick.y) < here,
					"%s: a stick of dynamite at a step's edge rolls down it" % level_id
				)
				var ball := Game.Shot.new(cx + .6, cy + .5, here + .22, .5, 0, 0, "bowling", 4.5)
				ball.bounces = 2
				var balls := Game.new(main.art, main.hud, main.sound, level_id)
				balls.configure({})
				balls.shots.append(ball)
				var lowest := here
				for _k in 60:
					balls.update_shots(1.0 / 60.0)
					lowest = minf(lowest, w.elevation(ball.x, ball.y))
				check.call(
					lowest < here - .1,
					"%s: a bowling ball nudged off a step rolls on down" % level_id
				)
				return
	check.call(false, "a step down with room to roll somewhere")
