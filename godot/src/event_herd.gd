## The stampede (features/county_events.gd): a herd of razorbacks broke out
## of somebody's pen and comes down an open run (a street, a field) that
## passes near a player, a bunch of them a little apart, galloping. Whoever
## is in a hog's way is trampled (a player knocked flat, a hand hurt and
## stunned, a breakable bowled over); a blast kills the hogs it reaches.
## Past the run's end they are gone out of sight. Play: game.rng and the
## feature's carried rows; each hog drawn by its own model (scenes/actors/
## hog.tscn) through a stand-in, as BLUE is.
class_name EventHerd
extends RefCounted

const Breakables := preload("res://src/features/breakables.gd")

const RUN := 0
const DOWN := 1
const GONE := 2
## Past the run's end: scattered, each its own way, gone once out of sight.
const SCATTER := 3
## A hog's row: [x, y, angle, gait, state, side, floor].
const X := 0
const Y := 1
const ANGLE := 2
const GAIT := 3
const STATE := 4
const SIDE := 5
const FLOOR := 6


static func n(ev: CountyEvents, key: String) -> float:
	return ev.n("hogs", key)


static func f(row: Array, i: int) -> float:
	var v: float = row[i]
	return v


## Finds a run and lets the herd go down it: true when one was found.
static func start(ev: CountyEvents) -> bool:
	var g := ev.game
	var p := ev.someone()
	if p == null:
		return false
	var w := g.world
	var base := g.rng.random() * TAU
	var best := 0.0
	var best_from := Vector2.ZERO
	var best_way := Vector2.RIGHT
	for k in 16:
		var way := Vector2.from_angle(base + k * TAU / 16.0)
		var side := Vector2(-way.y, way.x)
		var q := Vector2(p.x, p.y) + side * g.rng.uniform(-n(ev, "pass_near"), n(ev, "pass_near"))
		if not _open(w, q, w.elevation(p.x, p.y)):
			continue
		var ground := w.elevation(q.x, q.y)
		var back := _reach(w, q, -way, ground, n(ev, "run_most") * .6)
		var ahead := _reach(w, q, way, ground, n(ev, "run_most") * .5)
		if back < 9.0 or back + ahead < n(ev, "run_least"):
			continue
		var from := q - way * back
		if not ev.far_from_bosses(from.x, from.y) or not ev.far_from_bosses(q.x, q.y):
			continue
		# The longest run wins, the more so when it starts out of sight.
		var score := back + ahead + (6.0 if not w.visible(p.x, p.y, from.x, from.y) else 0.0)
		if score > best:
			best = score
			best_from = from
			best_way = way
			ev.herd_len = back + ahead
	if best <= 0.0:
		return false
	ev.herd_from = best_from
	ev.herd_way = best_way
	ev.herd.clear()
	ev.trampled.clear()
	var count := int(n(ev, "count"))
	var side := Vector2(-best_way.y, best_way.x)
	var ground := w.elevation(best_from.x, best_from.y)
	for i in count:
		var lane := g.rng.uniform(-1.0, 1.0) * n(ev, "spread") * .5
		var along := (count - 1 - i) * .95 + g.rng.random() * .5
		var at := best_from + best_way * along + side * lane
		if not _open(w, at, ground):
			at = best_from + best_way * along
		ev.herd.append([at.x, at.y, best_way.angle(), g.rng.random() * TAU, RUN, lane, ground])
	g.message("HOGS LOOSE! STAMPEDE!", 3.0)
	return true


## Whether a hog fits at q on the run's ground.
static func _open(w: LevelData, q: Vector2, ground: float) -> bool:
	if q.x < 1.0 or q.y < 1.0 or q.x > w.width - 1.0 or q.y > w.height - 1.0:
		return false
	if w.blocked(q.x, q.y, .34) or w.deep_at(q.x, q.y):
		return false
	return absf(w.elevation(q.x, q.y) - ground) < .3


## How far the run is open from q along `way`, at most `most`.
static func _reach(w: LevelData, q: Vector2, way: Vector2, ground: float, most: float) -> float:
	var d := 0.0
	while d < most:
		if not _open(w, q + way * (d + .5), ground):
			break
		d += .5
	return d


static func step(ev: CountyEvents, dt: float) -> void:
	var g := ev.game
	var age := g.clock - ev.since
	var side := Vector2(-ev.herd_way.y, ev.herd_way.x)
	var running := 0
	for i in ev.herd.size():
		var row: Array = ev.herd[i]
		var state: int = row[STATE]
		if state != RUN and state != SCATTER:
			continue
		var at := Vector2(f(row, X), f(row, Y))
		var along := (at - ev.herd_from).dot(ev.herd_way)
		if state == RUN and (along > ev.herd_len - .6 or age > n(ev, "most")):
			# The run's end: they scatter, each off to its side.
			state = SCATTER
			row[STATE] = SCATTER
			var turn := 1.0 if f(row, SIDE) >= 0.0 else -1.0
			row[ANGLE] = ev.herd_way.angle() + turn * (1.0 + fmod(i * .37, .6))
		if state == SCATTER and (age > n(ev, "most") + 15.0 or not _seen(g, at)):
			row[STATE] = GONE
			continue
		running += 1
		var heading := f(row, ANGLE)
		if state == RUN:
			var goal := ev.herd_from + ev.herd_way * (along + 2.5) + side * f(row, SIDE)
			var want := (goal - at).angle()
			heading += clampf(wrapf(want - heading, -PI, PI), -dt * 5.0, dt * 5.0)
		var pace := n(ev, "pace") * (.88 + .16 * sin(i * 1.7 + g.clock * 2.3))
		var step_len := pace * dt * Mud.pace(g, at.x, at.y)
		var r := n(ev, "radius")
		var moved := ev.move_body(row, cos(heading) * step_len, sin(heading) * step_len, r)
		if moved < step_len * .3:
			var lean := 1.0 if f(row, SIDE) >= 0.0 else -1.0
			for turn: float in [.6 * lean, -.6 * lean, 1.2 * lean, -1.2 * lean, 2.2 * lean]:
				moved = ev.move_body(
					row, cos(heading + turn) * step_len, sin(heading + turn) * step_len, r
				)
				if moved > step_len * .3:
					heading += turn * (.5 if state == RUN else 1.0)
					break
		row[ANGLE] = heading
		row[GAIT] = f(row, GAIT) + moved * 5.2
		_trample(ev, row, heading)
	if running == 0:
		ev.finish()


## Whether any player sees (x, y).
static func _seen(g: Game, at: Vector2) -> bool:
	for p: Player in g.players:
		if p.away or p.health <= 0:
			continue
		if Vector2(p.x - at.x, p.y - at.y).length() < 20.0:
			if g.world.visible(p.x, p.y, at.x, at.y, p.eye, g.world.elevation(at.x, at.y) + .5):
				return true
	return false


## What a hog runs down this tick.
static func _trample(ev: CountyEvents, row: Array, heading: float) -> void:
	var g := ev.game
	var at := Vector2(f(row, X), f(row, Y))
	var r := n(ev, "radius")
	var fz := f(row, FLOOR)
	var ahead := Vector2.from_angle(heading)
	for p: Player in g.players:
		if p.away or p.health <= 0:
			continue
		if Vector2(p.x - at.x, p.y - at.y).length() > r + GameState.PLAYER_RADIUS + .12:
			continue
		if absf(g.world.stand(p) - fz) > .6:
			continue
		var key := "p%d" % p.slot
		var last: float = ev.trampled.get(key, -10.0)
		if g.clock - last < 1.1:
			continue
		ev.trampled[key] = g.clock
		p.knocked = maxf(p.knocked, n(ev, "knock"))
		g.damage(n(ev, "trample"), [at.x, at.y], "HOGS", p)
		var off := Vector2(p.x - at.x, p.y - at.y).normalized()
		var shove := (ahead * .6 + off * .5) * .55
		g.move_actor(p, shove.x, shove.y, GameState.PLAYER_RADIUS)
	for e: Enemy in g.enemies:
		if not e.alive or e.dormant or Enemy.BOSS_TITLES.has(e.kind) or e.swims:
			continue
		if absf(e.x - at.x) > 1.0 or absf(e.y - at.y) > 1.0:
			continue
		if Vector2(e.x - at.x, e.y - at.y).length() > r + e.radius + .08:
			continue
		var key := "e%d" % e.uid
		var last: float = ev.trampled.get(key, -10.0)
		if g.clock - last < 1.4:
			continue
		ev.trampled[key] = g.clock
		e.stun = maxf(e.stun, n(ev, "stun"))
		e.flinch = maxf(e.flinch, .4)
		var off := Vector2(e.x - at.x, e.y - at.y).normalized()
		var shove := (ahead * .5 + off * .6) * .6
		g.move_actor(e, shove.x, shove.y, e.radius)
		Players.world_hurt(g, e, n(ev, "trample_enemy"), false, "trampled")
	var pieces: Breakables = g.features.get("breakables")
	if pieces == null:
		return
	for k in pieces.pieces.size():
		var piece: Breakables.Piece = pieces.pieces[k]
		if piece.broken or piece.height > 1.5 or piece.z > .4:
			continue
		if absf(piece.x - at.x) > 1.2 or absf(piece.y - at.y) > 1.2:
			continue
		if Vector2(piece.x - at.x, piece.y - at.y).length() < r + piece.radius * .8:
			var key := "b%d" % k
			if not ev.trampled.has(key):
				ev.trampled[key] = g.clock
				pieces.strike(k, n(ev, "bowl"), ahead.x, ahead.y)


## A blast at (x, y): the hogs it reaches are killed.
static func blast(ev: CountyEvents, x: float, y: float) -> void:
	var g := ev.game
	for row: Array in ev.herd:
		var state: int = row[STATE]
		if state != RUN and state != SCATTER:
			continue
		if Vector2(f(row, X) - x, f(row, Y) - y).length() < n(ev, "blast_reach"):
			row[STATE] = DOWN
			g.burst(f(row, X), f(row, Y), f(row, FLOOR) + .4, "gore", 14, 2.2)
			# Looks only: its stand-in falls from here, thrown from the blast
			# (its ragdoll, src/beast_doll.gd; never carried, no dice).
			var e := ModeBodies.stand_in(g, "hog%d" % ev.herd.find(row), "hog")
			_fell(e, g.clock, Vector2(x, y))


## A hog's stand-in dead from `at` (game clock), a blast at `from` (INF:
## none known): its model falls as a ragdoll (looks only).
static func _fell(e: Enemy, at: float, from: Vector2) -> void:
	e.hp = 0.0
	e.died_at = at
	e.killed_by = "blast"
	e.blast_at = from
	e.killed_from = from if from != Vector2.INF else Vector2(e.x, e.y)


## The hogs as the view draws them: each its model through a stand-in.
static func sprites(ev: CountyEvents) -> Array:
	var g := ev.game
	var out: Array = []
	for i in ev.herd.size():
		var row: Array = ev.herd[i]
		var state: int = row[STATE]
		if state == GONE or not g.in_view(f(row, X), f(row, Y), 1.0):
			continue
		var e := ModeBodies.stand_in(g, "hog%d" % i, "hog")
		e.x = f(row, X)
		e.y = f(row, Y)
		e.angle = f(row, ANGLE)
		e.height = .9
		e.variant = .94 + fmod(i * .37, 1.0) * .12
		if state != DOWN:
			e.hp = maxf(e.max_hp, 1.0)
			e.died_at = -1.0
		elif e.alive:
			# Down and never seen fall (a client, a save loaded, a hog that
			# came into view dead): seen alive last frame it falls from now,
			# else it lies as it fell long ago. (A stand-in shown running has
			# its gait; a new one none.)
			_fell(e, g.clock if e.gait != 0.0 else g.clock - 1000.0, Vector2.INF)
		e.gait = f(row, GAIT)
		var frame := "down" if state == DOWN else "r0"
		var s := g.pooled(e.x, e.y, "hog_" + frame, .9, f(row, FLOOR))
		s.who = e
		s.body = true
		out.append(s)
	return out
