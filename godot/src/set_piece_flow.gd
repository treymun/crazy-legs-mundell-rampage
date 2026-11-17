## What runs out of a set piece (features/set_pieces.gd): the gas leaking
## along a fuel line and the fire that runs along it, and the flood out of a
## water tower's burst tank. Play, the game's own arithmetic (no dice): the
## same on every machine, carried in the feature's state.
##
## - Gas: each hole in a line ([trail cell, clock]) sends gas along the
##   line's cells both ways at `leak_speed`; it lies `gas_life` seconds. A gas
##   cell next to fire (features/fire.gd's burning cells, or a gas cell lit a
##   `run_step` ago) lights: fire.ignite() for `gas_burn` seconds, so it runs
##   along the line to whatever stands at its end.
## - Flood: the cells round where the tank struck, by a walk that favours the
##   way the tower fell and keeps to the ground's level (no walls, rubble,
##   steps or water), `flood` at most; its front rolls out at `flood_speed`,
##   puts fires out and washes the gas away, and shoves whoever it meets out
##   ahead of it (a player knocked off their feet, a hand floundering).
##   It stands `flood_life` seconds and drains in `drain`.
extends RefCounted

const Breakables := preload("res://src/features/breakables.gd")
const FireFeature := preload("res://src/features/fire.gd")
const Shape := preload("res://src/set_piece_shape.gd")
const NEAR := [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
	Vector2i(1, 1),
	Vector2i(-1, 1),
	Vector2i(1, -1),
	Vector2i(-1, -1)
]


static func _fire(sp: SetPiecesFeature) -> FireFeature:
	var fire: FireFeature = sp.game.features.get("fire")
	return fire


# -------------------------------------------------------------------- gas


## Part `part` of fuel line i holed at `clock`: gas leaks from the trail cell
## nearest it.
static func hole(sp: SetPiecesFeature, i: int, part: Shape.Part, clock: float) -> void:
	var cells: Array = sp.trails[i]
	if cells.is_empty():
		return
	var best := 0
	var near := INF
	for j in cells.size():
		var c: Vector2i = cells[j]
		var d := Vector2(c.x + .5 - part.p.x, c.y + .5 - part.p.y).length()
		if d < near:
			near = d
			best = j
	var st: Dictionary = sp.pieces[i]
	var holes: Array = st["holes"]
	holes.append([best, clock])
	sp.net_version += 1
	sp.wake()


## When gas from the line's holes first reaches trail cell j (INF: never).
static func arrives(st: Dictionary, j: int) -> float:
	var holes: Array = st["holes"]
	var speed := Shape.num("fuel", "leak_speed", 3.5)
	var best := INF
	for h: Array in holes:
		var at: int = h[0]
		var t0: float = h[1]
		best = minf(best, t0 + absf(j - at) / speed)
	return best


## Whether trail cell j of a line lies under gas at `clock`.
static func gas_at(st: Dictionary, j: int, clock: float) -> bool:
	var lit: Array = st["lit"]
	var was: float = lit[j]
	if was != -1.0:
		return false
	var at := arrives(st, j)
	return at <= clock and clock < at + Shape.num("fuel", "gas_life", 60.0)


static func trail_busy(sp: SetPiecesFeature, i: int) -> bool:
	var st: Dictionary = sp.pieces[i]
	var holes: Array = st["holes"]
	if holes.is_empty():
		return false
	var cells: Array = sp.trails[i]
	var last := 0.0
	for j in cells.size():
		last = maxf(last, arrives(st, j))
	return sp.game.clock < last + Shape.num("fuel", "gas_life", 60.0)


## The gas on line i next to fire lights, a cell at a time down the line.
static func trail_tick(sp: SetPiecesFeature, i: int) -> void:
	var fire := _fire(sp)
	if fire == null or not fire.allowed():
		return
	var st: Dictionary = sp.pieces[i]
	var cells: Array = sp.trails[i]
	var lit: Array = st["lit"]
	var clock := sp.game.clock
	var step := Shape.num("fuel", "run_step", .09)
	for j in cells.size():
		if not gas_at(st, j, clock):
			continue
		var c: Vector2i = cells[j]
		var catch := false
		for n: int in [j - 1, j + 1]:
			if n >= 0 and n < cells.size():
				var was: float = lit[n]
				if was >= 0.0 and clock >= was + step:
					catch = true
		if not catch:
			for way: Vector2i in NEAR:
				if fire.burning_at(c.x + way.x + .5, c.y + way.y + .5):
					catch = true
					break
		if catch or fire.burning_at(c.x + .5, c.y + .5):
			_light(sp, fire, st, j, c)


static func _light(
	sp: SetPiecesFeature, fire: FireFeature, st: Dictionary, j: int, c: Vector2i
) -> void:
	var lit: Array = st["lit"]
	lit[j] = sp.game.clock
	sp.net_version += 1
	var w := sp.game.world
	var z := w.floor_under(c.x + .5, c.y + .5, w.elevation(c.x + .5, c.y + .5) + .5)
	fire.fresh()
	fire.ignite(c.x + .5, c.y + .5, z, Shape.num("fuel", "gas_burn", 4.5))
	# The gas flares up round what stands on it (a propane tank goes up).
	var bk: Breakables = sp.game.features.get("breakables")
	if bk != null:
		var flare := Shape.num("fuel", "flare", 30.0)
		for n in bk.pieces.size():
			var piece: Breakables.Piece = bk.pieces[n]
			if not piece.broken and Vector2(piece.x - c.x - .5, piece.y - c.y - .5).length() < .95:
				bk.strike(n, flare, 0.0, 0.0)
	if j % 3 == 0:
		sp.game.sound_at("gas_whoosh", c.x + .5, c.y + .5, .8)


## A blast lights the gas it reaches.
static func blast_lights(sp: SetPiecesFeature, x: float, y: float, _z: float) -> void:
	var fire := _fire(sp)
	if fire == null or not fire.allowed():
		return
	for i in sp.pieces.size():
		var st: Dictionary = sp.pieces[i]
		if str(st["kind"]) != "fuel":
			continue
		var cells: Array = sp.trails[i]
		for j in cells.size():
			var c: Vector2i = cells[j]
			if Vector2(c.x + .5 - x, c.y + .5 - y).length() < 2.2 and gas_at(st, j, sp.game.clock):
				_light(sp, fire, st, j, c)


# ------------------------------------------------------------------ flood


## Tower i's tank struck the ground: it bursts and the water goes.
static func burst(sp: SetPiecesFeature, i: int) -> void:
	var st: Dictionary = sp.pieces[i]
	var made: Array = sp.shapes[i]
	var g := sp.game
	var w := g.world
	var tank := -1
	for k in made.size():
		var part: Shape.Part = made[k]
		if part.role == "tank":
			tank = k
	if tank < 0:
		return
	var at: Array = sp.pose(i, tank, g.clock)
	var c: Vector3 = at[0]
	var tank_part: Shape.Part = made[tank]
	var lean_row: Array = st["lean"]
	var lean := Vector2(Shape.f(lean_row[0]), Shape.f(lean_row[1])).normalized()
	# The water lands a little past the tank's middle, the way it fell.
	var x := clampf(c.x + lean.x * .6, 1.0, w.width - 1.01)
	var y := clampf(c.y + lean.y * .6, 1.0, w.height - 1.01)
	var z := w.floor_under(x, y, c.z)
	var reach := tank_part.half.x + .5
	var v := PackedFloat32Array([x - reach, y - reach, x + reach, y + reach, z + 2.0, 0, 0, z])
	sp.crush(i, v, Shape.num("all", "crush_tank", 90.0))
	g.sound_at("tower_burst", x, y, 1.0)
	g.burst(x, y, z + .4, "splash", 26, 3.2)
	g.burst(x, y, z + .2, "wood", 14, 3.0)
	g.shake = minf(1.0, g.shake + .5)
	var flood := _spread(sp, Vector2(x, y), z, lean)
	flood["t0"] = g.clock
	sp.floods.append(flood)
	sp.net_version += 1


## The cells the water reaches, cheapest first: [cells, costs].
static func _spread(sp: SetPiecesFeature, from: Vector2, z: float, lean: Vector2) -> Dictionary:
	var w := sp.game.world
	var most := int(Shape.num("tower", "flood", 110.0))
	var start := Vector2i(int(from.x), int(from.y))
	var cost := {start: 0.0}
	var done := {}
	var cells: Array = []
	var costs: Array = []
	var open: Array = [start]
	while not open.is_empty() and cells.size() < most:
		var best := 0
		var low: float = cost[open[0]]
		for n in range(1, open.size()):
			var here: float = cost[open[n]]
			if here < low:
				low = here
				best = n
		var c: Vector2i = open[best]
		open.remove_at(best)
		if done.has(c):
			continue
		done[c] = true
		cells.append(c.y * w.width + c.x)
		costs.append(snappedf(low, .001))
		for way: Vector2i in NEAR:
			var nc: Vector2i = c + way
			if done.has(nc) or nc.x < 1 or nc.y < 1 or nc.x >= w.width - 1 or nc.y >= w.height - 1:
				continue
			var cell := nc.y * w.width + nc.x
			if w.solid[cell] >= 0 or absf(w.ground[cell] - z) > .45:
				continue
			if w.blocked(nc.x + .5, nc.y + .5, .25, z + .3):
				continue
			if Materials.of_tile(w, w.floor_tile[cell]) == "water":
				continue
			var d := Vector2(way.x, way.y)
			var step := d.length() * (1.0 + .7 * (1.0 - d.normalized().dot(lean)) * .5)
			var to := low + step
			if to < Shape.f(cost.get(nc, INF)):
				cost[nc] = to
				open.append(nc)
	return {
		"x": from.x,
		"y": from.y,
		"z": z,
		"dir": [lean.x, lean.y],
		"cells": cells,
		"costs": costs,
		"done": 0,
		"hit": {},
	}


static func flood_tick(sp: SetPiecesFeature, dt: float) -> void:
	var g := sp.game
	var w := g.world
	var speed := Shape.num("tower", "flood_speed", 7.0)
	var life := Shape.num("tower", "flood_life", 14.0)
	var drain := Shape.num("tower", "drain", 4.0)
	var fire := _fire(sp)
	var gone: Array = []
	for f: Dictionary in sp.floods:
		var t0: float = f["t0"]
		var age := g.clock - t0
		if age > life + drain:
			gone.append(f)
			continue
		var front := age * speed
		var cells: Array = f["cells"]
		var costs: Array = f["costs"]
		var done: int = f["done"]
		while done < cells.size() and Shape.f(costs[done]) <= front:
			var cell: int = cells[done]
			_wet(sp, fire, cell, done)
			done += 1
		var was_done: int = f["done"]
		if done != was_done:
			f["done"] = done
			sp.net_version += 1
		if front > Shape.f(costs[costs.size() - 1]) + 2.0:
			continue
		# The front: whoever it meets is shoved out ahead of it.
		var band := {}
		for n in range(maxi(0, done - 24), done):
			if Shape.f(costs[n]) > front - 2.0:
				var in_band: int = cells[n]
				band[in_band] = true
		if band.is_empty():
			continue
		var src := Vector2(Shape.f(f["x"]), Shape.f(f["y"]))
		var hit: Dictionary = f["hit"]
		var wash := Shape.num("tower", "wash", 4.5)
		for p: Player in g.players:
			if p.health <= 0 or not band.has(w.cell(p.x, p.y)):
				continue
			var away := (Vector2(p.x, p.y) - src).normalized()
			g.move_actor(p, away.x * wash * dt, away.y * wash * dt, GameState.PLAYER_RADIUS)
			var key := "p%d" % p.slot
			if not hit.has(key):
				hit[key] = g.clock
				p.knocked = maxf(p.knocked, Shape.num("tower", "wash_knock", .7))
				g.damage(Shape.num("tower", "wash_hurt", 6.0), [src.x, src.y], "WASHED OUT", p)
		for e: Enemy in g.enemies:
			if not e.alive or not band.has(w.cell(e.x, e.y)):
				continue
			var away := (Vector2(e.x, e.y) - src).normalized()
			g.move_actor(e, away.x * wash * dt, away.y * wash * dt, e.radius)
			var key := "e%d" % e.uid
			if not hit.has(key) and e.hostile:
				hit[key] = g.clock
				e.stun = maxf(e.stun, Shape.num("tower", "wash_stun", 1.6))
				Players.world_hurt(
					g, e, Shape.num("tower", "wash_hurt", 6.0) * 1.5, false, "washed"
				)
	for f: Dictionary in gone:
		sp.floods.erase(f)
		sp.net_version += 1


## The water reaches a cell: a fire there is out, gas there washed away.
static func _wet(sp: SetPiecesFeature, fire: FireFeature, cell: int, n: int) -> void:
	var g := sp.game
	var w := g.world
	var x := (cell % w.width) + .5
	var y := Shape.f(cell / w.width) + .5
	if fire != null:
		fire.douse(cell)
	for i in sp.pieces.size():
		var st: Dictionary = sp.pieces[i]
		if str(st["kind"]) != "fuel":
			continue
		var cells: Array = sp.trails[i]
		var lit: Array = st["lit"]
		for j in cells.size():
			var c: Vector2i = cells[j]
			if c.y * w.width + c.x == cell and Shape.f(lit[j]) == -1.0:
				lit[j] = -2.0
	if n % 3 == 0:
		g.burst(x, y, w.ground[cell] + .15, "splash", 3, 1.6)


# ------------------------------------------------------------------ looks


## The water standing and the gas lying, as marks on the ground.
static func marks(sp: SetPiecesFeature) -> Array:
	var out: Array = []
	var g := sp.game
	var w := g.world
	var life := Shape.num("tower", "flood_life", 14.0)
	var drain := Shape.num("tower", "drain", 4.0)
	for f: Dictionary in sp.floods:
		var cells: Array = f["cells"]
		var done: int = f["done"]
		var age := g.clock - Shape.f(f["t0"])
		var shown := done
		if age > life:
			shown = int(done * clampf(1.0 - (age - life) / drain, 0.0, 1.0))
		var z: float = f["z"]
		for n in shown:
			var cell: int = cells[n]
			var x := (cell % w.width) + .5
			var y := Shape.f(cell / w.width) + .5
			if not g.in_view(x, y, .9):
				continue
			var mark: View.GroundMark = sp.mark_cache.get(cell)
			if mark == null:
				mark = View.GroundMark.new(
					x, y, 0.0, Shape.f(cell % 5) * 1.3, .78, .78, "mark_flood_%d" % (cell % 3)
				)
				Tumble.lay(w, mark, z + .1, .01)
				sp.mark_cache[cell] = mark
			out.append(mark)
	for i in sp.pieces.size():
		var st: Dictionary = sp.pieces[i]
		if str(st["kind"]) != "fuel":
			continue
		var holes: Array = st["holes"]
		if holes.is_empty():
			continue
		var cells: Array = sp.trails[i]
		for j in cells.size():
			if not gas_at(st, j, g.clock):
				continue
			var c: Vector2i = cells[j]
			if not g.in_view(c.x + .5, c.y + .5, .8):
				continue
			var key := -1 - (i * 4096 + j)
			var mark: View.GroundMark = sp.mark_cache.get(key)
			if mark == null:
				mark = View.GroundMark.new(
					c.x + .5, c.y + .5, 0.0, j * 1.7, .5, .42, "mark_oil_%d" % (j % 3)
				)
				Tumble.lay(w, mark, w.elevation(c.x + .5, c.y + .5) + .1, .008)
				sp.mark_cache[key] = mark
			out.append(mark)
	return out
