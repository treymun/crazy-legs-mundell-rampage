## The enemies' level of detail and the tick's spike fixes (engine pass 6):
##
##   Godot --headless --path <project> --script res://tools/ai_check.gd
##
## - Sight lines: LevelData.visible() with its quick tests (a furniture
##   cell's boxes met once per cell, a geometry cell's sight bands) answers
##   exactly as the step-by-step test does, flat and at heights, on every
##   chapter, a County Run map and a versus map, before and after furniture
##   is broken out.
## - Flow fields: the walk (passable() written out) reaches the same cells
##   with the same steps as a plain walk asking passable() of each, through
##   doors shut and open.
## - Cover: CoverSearch's whole search finds the spot HandTactics.cover and
##   Enemy.find_cover found before it (both settings); in play, the hands
##   together test at most `cover_budget` spots a tick, and a search spread
##   over ticks ends where the whole one would have.
## - Idle life: the activities picked by cell are those picked over every
##   row.
## - Level of detail: far calm enemies wait their turn, the near and the
##   engaged tick every tick; a shot heard, a hit, a player walking up wake
##   one to every tick at once; nothing waits with `lod` off; a snapshot
##   taken mid-wait goes on tick for tick the same on a fresh game; the far
##   ones' turns are spread out (never all on one tick).
extends SceneTree

const STEP := 1.0 / 120.0
const SIGHT_LEVELS := [
	"hickston",
	"fair",
	"sawmill",
	"quarry",
	"bayou",
	"speedway",
	"mothership",
	"county_hickston",
	"grainyard",
]

var failures: Array = []


func _init() -> void:
	_run.call_deferred()


func _check(ok: bool, text: String) -> void:
	print("  ok   " if ok else "  FAIL ", text)
	if not ok:
		failures.append(text)


func _run() -> void:
	var main: Control = load("res://src/Main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.set_process(false)
	main.state = "title"
	print("\nSIGHT LINES")
	_sight(main)
	print("\nFLOW FIELDS")
	_flow(main)
	print("\nCOVER")
	_cover(main)
	print("\nIDLE LIFE")
	_idle(main)
	print("\nLEVEL OF DETAIL")
	_lod(main)
	print("")
	print("AI CHECK OK" if failures.is_empty() else "%d CHECK(S) FAILED" % failures.size())
	main.queue_free()
	await process_frame
	quit(1 if not failures.is_empty() else 0)


# ------------------------------------------------------------ sight lines


## visible() with the quick tests and without (the arrays they read emptied:
## every step then asks blocked() as it always did).
func _sight(main) -> void:
	var assets: Assets = main.art
	for id: String in SIGHT_LEVELS:
		var lv := LevelData.load_level(id, assets)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(id)
		var lines: Array = []
		while lines.size() < 1500:
			var a := Vector2(rng.randf_range(1, lv.width - 1), rng.randf_range(1, lv.height - 1))
			var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(.5, 16.0)
			if b.x < 0 or b.y < 0 or b.x >= lv.width or b.y >= lv.height:
				continue
			if lv.solid[lv.cell(a.x, a.y)] >= 0:
				continue
			# Eyes at a body's height over the ground, or anywhere up to a roof.
			var za := lv.elevation(a.x, a.y) + rng.randf_range(.3, 1.7)
			var zb := lv.elevation(b.x, b.y) + rng.randf_range(-.2, 3.2)
			lines.append([a, b, za, zb])
		var differ := _differ(lv, lines)
		# Furniture broken out: the index's lists grow shorter, the cells stay.
		var dropped := 0
		for k in range(0, lv.collision_volumes.size(), 3):
			lv.drop_volume(lv.collision_volumes[mini(k, lv.collision_volumes.size() - 1)])
			dropped += 1
			if dropped >= 20:
				break
		differ += _differ(lv, lines)
		# Cells walled up after load (the 5v5 cover standing up again) and
		# walls opened (a fence broken through).
		var flipped := 0
		for k in lv.width * lv.height:
			if flipped < 60 and (k * 7919) % 97 == 0:
				lv.solid[k] = 0 if lv.solid[k] < 0 else -1
				flipped += 1
		differ += _differ(lv, lines)
		_check(
			differ == 0,
			"%s: %d sight lines answer as step by step (%d differ)" % [id, lines.size() * 6, differ]
		)


func _differ(lv: LevelData, lines: Array) -> int:
	var boxes := lv.box_cells
	var furniture := lv.furniture_cells
	var out := 0
	for row: Array in lines:
		var a: Vector2 = row[0]
		var b: Vector2 = row[1]
		var quick_flat := lv.visible(a.x, a.y, b.x, b.y)
		var quick_high := lv.visible(a.x, a.y, b.x, b.y, row[2], row[3])
		lv.box_cells = PackedByteArray()
		lv.furniture_cells = PackedByteArray()
		var slow_flat := lv.visible(a.x, a.y, b.x, b.y)
		var slow_high := lv.visible(a.x, a.y, b.x, b.y, row[2], row[3])
		lv.box_cells = boxes
		lv.furniture_cells = furniture
		if quick_flat != slow_flat:
			out += 1
		if quick_high != slow_high:
			out += 1
	return out


# ------------------------------------------------------------ flow fields


func _flow(main) -> void:
	for id: String in ["hickston", "sawmill", "range"]:
		var g: Game = main.make_game(id)
		var lv := g.world
		var f := FlowField.new(lv)
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var same := 0
		var tried := 0
		for k in 40:
			if k == 20:
				# Every door opened (each a "2" cell's answer changes).
				for door: LevelData.Door in lv.doors:
					door.opened = true
					door.progress = 1.0
			var x := rng.randf_range(1, lv.width - 1)
			var y := rng.randf_range(1, lv.height - 1)
			if lv.solid[lv.cell(x, y)] >= 0:
				continue
			tried += 1
			f.update(x, y, float(k) * 10.0, NAN)
			if _plain_walk_matches(f):
				same += 1
		_check(
			same == tried,
			"%s: %d of %d walks reach the same cells in the same steps" % [id, same, tried]
		)
		g.dispose()


## A walk from f's origin asking f.passable() of every cell (the walk as it
## was), against what f holds.
func _plain_walk_matches(f: FlowField) -> bool:
	var nodes := f.steps.size()
	var steps := PackedInt32Array()
	steps.resize(nodes)
	steps.fill(FlowField.FAR)
	var start := f.origin.y * f.width + f.origin.x
	if f.graph != null:
		start = -1
		for n in nodes:
			if f.steps[n] == 0:
				start = n
	if start < 0 or start >= nodes:
		return true
	var queue := PackedInt32Array([start])
	steps[start] = 0
	var head := 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		var d := steps[cell]
		if d >= f.reach:
			continue
		var next_cells := PackedInt32Array()
		if f.graph != null:
			for e in range(f.graph.first[cell], f.graph.first[cell + 1]):
				next_cells.append(f.graph.edges[e])
		else:
			var cx := cell % f.width
			var cy := cell / f.width
			for k in 4:
				var n: Vector2i = FlowField.NEIGHBOURS[k]
				if cx + n.x < 0 or cy + n.y < 0 or cx + n.x >= f.width or cy + n.y >= f.height:
					continue
				next_cells.append((cy + n.y) * f.width + cx + n.x)
		for next in next_cells:
			if steps[next] != FlowField.FAR or not f.passable(next):
				continue
			steps[next] = d + 1
			queue.append(next)
	return steps == f.steps


# ------------------------------------------------------------------ cover


func _cover(main) -> void:
	for smart in [1, 0]:
		var g: Game = main.make_game("hickston")
		g.configure({"difficulty": 2, "smart_hands": smart})
		var p := g.player
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var same := 0
		var tried := 0
		var found := 0
		for e: Enemy in g.enemies:
			if not e.tactical():
				continue
			for k in 3:
				# The player somewhere round the hand, 3 to 9 cells off.
				var at := (
					Vector2(e.x, e.y)
					+ Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(3, 9)
				)
				if g.world.blocked(at.x, at.y, .25):
					continue
				p.x = at.x
				p.y = at.y
				var want: Variant = _cover_before(e, g, smart == 1)
				var got: Variant = CoverSearch.whole(e, g, smart == 1)
				tried += 1
				if want == got:
					same += 1
				if got != null:
					found += 1
		_check(
			same == tried and found > 0,
			(
				"HANDS: %s: the whole search finds the spot it always did (%d of %d, %d found)"
				% ["SMART" if smart else "CLASSIC", same, tried, found]
			)
		)
		g.dispose()
	# In play: three hands want cover in one tick; the spots tested in each
	# tick stay within the budget, and each ends where the whole search would.
	var g2: Game = main.make_game("hickston")
	g2.configure({"difficulty": 2})
	var hands: Array = []
	for e: Enemy in g2.enemies:
		if e.tactical() and hands.size() < 3:
			hands.append(e)
	var p2 := g2.player
	p2.x = hands[0].x + 6.0
	p2.y = hands[0].y
	var wanted: Array = []
	for e: Enemy in hands:
		wanted.append(CoverSearch.whole(e, g2, true))
		e.cover_ready = 0.0
		e.cover = null
	var lod := g2.enemy_lod
	var most := 0
	var ticks := 0
	var lefts: Array = []
	g2.clock = 100.0
	for e: Enemy in hands:
		e.take_cover(g2)
	most = maxi(most, EnemyLod.COVER_BUDGET - lod.cover_left)
	while ticks < 100:
		var pending := false
		for e: Enemy in hands:
			pending = pending or not e.cover_hunt.is_empty()
		if not pending:
			break
		ticks += 1
		g2.clock += STEP
		for e: Enemy in hands:
			CoverSearch.go_on(e, g2)
		most = maxi(most, EnemyLod.COVER_BUDGET - lod.cover_left)
	var ended := 0
	for i in hands.size():
		var e: Enemy = hands[i]
		var c: Variant = null if e.cover == null else Vector2(float(e.cover[0]), float(e.cover[1]))
		if c == wanted[i]:
			ended += 1
		lefts.append(c)
	_check(
		most <= EnemyLod.COVER_BUDGET and ended == hands.size(),
		(
			(
				"three hands ducking at once: at most %d spots a tick (budget %d), %d more"
				+ " ticks, each where the whole search goes"
			)
			% [most, EnemyLod.COVER_BUDGET, ticks]
		)
	)
	g2.dispose()


## HandTactics.cover and Enemy.find_cover as they were before CoverSearch.
func _cover_before(e: Enemy, game: Game, smart: bool) -> Variant:
	var p: Player = game.player
	var w: LevelData = game.world
	var away := atan2(e.y - p.y, e.x - p.x)
	if not smart:
		var order: Array = []
		for k in 12:
			order.append([absf(Enemy.angle_delta(k * TAU / 12.0, away)), k])
		order.sort_custom(
			func(m: Array, n: Array) -> bool: return m[0] < n[0] or (m[0] == n[0] and m[1] < n[1])
		)
		for ring: float in [1.2, 2.0, 2.8, 3.6]:
			for pair: Array in order:
				var k: int = pair[1]
				var a := k * TAU / 12.0
				var cx := e.x + cos(a) * ring
				var cy := e.y + sin(a) * ring
				if w.blocked(cx, cy, e.radius) or not w.visible(e.x, e.y, cx, cy):
					continue
				var head: float = w.elevation(cx, cy) + minf(.92, e.height * .72)
				if w.visible(p.x, p.y, cx, cy, p.eye, head):
					continue
				return Vector2(cx, cy)
		return null
	var fallback: Variant = null
	var fallback_ring := 0.0
	for ring: float in [1.0, 1.7, 2.4, 3.1, 3.8]:
		if fallback != null and ring > fallback_ring + .8:
			break
		for k in 12:
			var turn := ((k + 1) >> 1) * (1 if k % 2 else -1)
			var a := away + turn * TAU / 12.0
			var cx := e.x + cos(a) * ring
			var cy := e.y + sin(a) * ring
			if w.blocked(cx, cy, e.radius) or not w.visible(e.x, e.y, cx, cy):
				continue
			var head: float = w.elevation(cx, cy) + minf(.92, e.height * .72)
			if w.visible(p.x, p.y, cx, cy, p.eye, head):
				continue
			var to := Vector2(p.x - cx, p.y - cy).normalized()
			if w.blocked(cx + to.x * (e.radius + .45), cy + to.y * (e.radius + .45), .12):
				return Vector2(cx, cy)
			if fallback == null:
				fallback = Vector2(cx, cy)
				fallback_ring = ring
	return fallback


# -------------------------------------------------------------- idle life


func _idle(main) -> void:
	var same := 0
	var tried := 0
	for id: String in ["hickston", "fair", "sawmill", "quarry", "bayou", "speedway", "mothership"]:
		var g: Game = main.make_game(id)
		var about := IdleLife.things(g)
		var by_cell := IdleLife.grid(about)
		for i in g.enemy_ids.size():
			var e: Enemy = g.enemies[i]
			var spec: Dictionary = g.level.enemies[i]
			var at := Vector2(float(spec["x"]), float(spec["y"]))
			tried += 1
			if IdleLife.pick(g, e, at, i, about) == IdleLife.pick(g, e, at, i, about, by_cell):
				same += 1
		g.dispose()
	_check(
		same == tried,
		"every chapter's enemies pick the same activity by cell (%d of %d)" % [same, tried]
	)


# ------------------------------------------------------- level of detail


func _game(main, id: String) -> Game:
	var g: Game = main.make_game(id)
	g.configure({"difficulty": 1})
	g.cheats.god = true
	return g


func _lod(main) -> void:
	var g := _game(main, "hickston")
	var p := g.player
	# A few seconds standing at the start.
	var waits := {}
	var ticked_by_tick: Array = []
	for t in 240:
		var before := {}
		for e: Enemy in g.enemies:
			before[e] = e.pose
		g.tick(STEP, Game.Controls.new())
		var n := 0
		for e: Enemy in g.enemies:
			if e.alive and e.pose != before[e]:
				n += 1
			elif e.alive and not e.dormant and e.brain != "bessie":
				waits[e] = int(waits.get(e, 0)) + 1
		ticked_by_tick.append(n)
	var far_wait := 0
	var near_wait := 0
	var far_n := 0
	for e: Enemy in g.enemies:
		if not e.alive or e.dormant or e.brain == "bessie":
			continue
		var d := Vector2(e.x - p.x, e.y - p.y).length()
		if d > EnemyLod.FAR + 4.0:
			far_n += 1
			if int(waits.get(e, 0)) > 120:
				far_wait += 1
		elif d < EnemyLod.FAR - 2.0 and int(waits.get(e, 0)) > 0 and (e.alerted or d < 10.0):
			near_wait += 1
	_check(
		far_wait > far_n / 2,
		"far calm enemies wait their turn (%d of %d far ones)" % [far_wait, far_n]
	)
	_check(near_wait == 0, "engaged and near ones tick every tick (%d waited)" % near_wait)
	# The most that tick on one tick, the near ones (every tick) aside.
	var near_n := 0
	for n: int in ticked_by_tick:
		near_n = mini(near_n if near_n > 0 else n, n)
	var most := 0
	for n: int in ticked_by_tick.slice(60):
		most = maxi(most, n - near_n)
	_check(
		most < far_n * .6,
		(
			"the far ones' turns are spread out (at most %d of %d on one tick, %d near every tick)"
			% [most, far_n, near_n]
		)
	)
	# A shot heard, a hit, a player walking up: back to every tick at once.
	var far: Enemy = null
	for e: Enemy in g.enemies:
		if e.alive and e.hostile and not e.dormant and e.mind != null and e.lod_since >= 0.0:
			far = e
			break
	_check(far != null, "a far hand is waiting")
	if far != null:
		far.mind.investigate = [p.x, p.y, g.clock + 10.0]
		var pose := far.pose
		g.tick(STEP, Game.Controls.new())
		_check(
			far.pose != pose and far.lod_since < 0.0,
			"a shot heard: it ticks the next tick, with what it saved"
		)
		far.mind.investigate = null
		for t in 30:
			g.tick(STEP, Game.Controls.new())
		far.hurt(1.0, g)
		pose = far.pose
		g.tick(STEP, Game.Controls.new())
		_check(far.pose != pose and far.lod_since < 0.0, "hit: it ticks every tick")
	# Off: nothing waits.
	var was := EnemyLod.ON
	EnemyLod.ON = false
	var g2 := _game(main, "hickston")
	var waited := 0
	for t in 60:
		g2.tick(STEP, Game.Controls.new())
		for e: Enemy in g2.enemies:
			if e.lod_since >= 0.0:
				waited += 1
	EnemyLod.ON = was
	_check(waited == 0, "lod=false: every enemy every tick")
	g2.dispose()
	# A snapshot mid-wait goes on the same on a fresh game.
	var a := _game(main, "hickston")
	for t in 100:
		a.tick(STEP, Game.Controls.new())
	var waiting := 0
	for e: Enemy in a.enemies:
		if e.lod_since >= 0.0:
			waiting += 1
	var b := _game(main, "hickston")
	GameSnapshot.apply(b, GameSnapshot.capture(a))
	var c := Game.Controls.new()
	c.forward = 1.0
	var same := true
	for t in 360:
		c.turn = .01 if t % 120 < 60 else -.01
		a.tick(STEP, c)
		b.tick(STEP, c)
		if t % 30 == 29 and var_to_bytes(_enemies_of(a)) != var_to_bytes(_enemies_of(b)):
			same = false
			break
	_check(
		waiting > 0 and same,
		"a snapshot taken with %d waiting goes on tick for tick the same" % waiting
	)
	a.dispose()
	b.dispose()
	g.dispose()


func _enemies_of(g: Game) -> Array:
	var out: Array = []
	for e: Enemy in g.enemies:
		out.append([e.x, e.y, e.angle, e.pose, e.lod_since, e.alerted, e.hp])
	return out
