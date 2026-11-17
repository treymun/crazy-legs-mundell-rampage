## The twister (features/county_events.gd): the siren and the scanner, then
## a funnel touches down out past the town and comes across, a little off a
## straight line, passing beside a player (or right through a barn or a water
## tower near them), and lifts again past the far side.
##
## Under the open sky within `reach` whoever stands is drawn round and in, in
## the core thrown about, hurt and knocked flat; under a roof nobody is
## touched. Breakables in the core are smashed, a set piece's parts torn
## (set_pieces.gd blast: a barn comes down in its pieces, a tower over),
## loose things torn off their places and flung (carry.gd fling), the dead
## thrown about. All of it play: game.rng and the feature's carried state.
class_name EventTwister
extends RefCounted

const Breakables := preload("res://src/features/breakables.gd")
const Carry := preload("res://src/features/carry.gd")
const Corpses := preload("res://src/features/corpses.gd")

const WARN := 0
const CROSS := 1
const LIFT := 2


static func n(ev: CountyEvents, key: String) -> float:
	return ev.n("twister", key)


## Where it touches down and where it leaves: true when a way was found.
static func start(ev: CountyEvents) -> bool:
	var g := ev.game
	var p := ev.someone()
	if p == null:
		return false
	var mid := Vector2.INF
	ev.tw_aim = -1
	var sets: SetPiecesFeature = g.features.get("set_pieces")
	if sets != null:
		var best := n(ev, "aim_set_piece")
		for i in sets.pieces.size():
			var st: Dictionary = sets.pieces[i]
			var stage: int = st["stage"]
			var what := str(st.get("kind", ""))
			if stage != SetPiecesFeature.STANDING or what == "fuel":
				continue
			var spec := sets.spec_of(i)
			var sx: float = spec.get("x", 0.0)
			var sy: float = spec.get("y", 0.0)
			var d := Vector2(sx - p.x, sy - p.y).length()
			if d < best and ev.far_from_bosses(sx, sy):
				best = d
				mid = Vector2(sx, sy)
				ev.tw_aim = i
	var w := g.world
	for attempt in 6:
		var way := Vector2.from_angle(g.rng.random() * TAU)
		var through := mid
		if through == Vector2.INF:
			var side := Vector2(-way.y, way.x)
			var off := g.rng.uniform(n(ev, "pass_near"), n(ev, "pass_far"))
			through = Vector2(p.x, p.y) + side * off * (1.0 if g.rng.random() < .5 else -1.0)
		var far := n(ev, "start_far")
		var a := _inside(w, through, -way, far)
		var b := _inside(w, through, way, far)
		if a.distance_to(b) < far * .9:
			continue
		if a.distance_to(Vector2(p.x, p.y)) < 13.0:
			var swap := a
			a = b
			b = swap
		if a.distance_to(Vector2(p.x, p.y)) < 13.0:
			continue
		if not ev.far_from_bosses(through.x, through.y):
			continue
		ev.tw_from = a
		ev.tw_to = b
		ev.tw_run = 0.0
		ev.tw_k = 0.0
		ev.tw_at = a
		ev.tw_bite = 0.0
		ev.tw_rip = 0.0
		ev.tw_fling = 0.0
		g.message("TORNADO WARNING! GET UNDER A ROOF!", 4.0)
		return true
	return false


## A point up to `far` from `at` along `way`, kept a little inside the map.
static func _inside(w: LevelData, at: Vector2, way: Vector2, far: float) -> Vector2:
	var reach := far
	while reach > 2.0:
		var q := at + way * reach
		if q.x > 2.0 and q.y > 2.0 and q.x < w.width - 2.0 and q.y < w.height - 2.0:
			return q
		reach -= 1.0
	return at


## Where it is on its way: along the line, swung a little side to side.
static func where(ev: CountyEvents) -> Vector2:
	var length := ev.tw_from.distance_to(ev.tw_to)
	var way := (ev.tw_to - ev.tw_from) / maxf(.01, length)
	var side := Vector2(-way.y, way.x)
	var t := clampf(ev.tw_run, 0.0, length + 8.0)
	var swing := sin(t * .23) * n(ev, "wobble") + sin(t * .61 + 1.3) * n(ev, "wobble") * .35
	return ev.tw_from + way * t + side * swing


## It goes up into the cloud again where it is.
static func lift(ev: CountyEvents) -> void:
	ev.phase = LIFT
	ev.since = ev.game.clock


static func step(ev: CountyEvents, dt: float) -> void:
	var g := ev.game
	var age := g.clock - ev.since
	match ev.phase:
		WARN:
			ev.tw_k = clampf(age / n(ev, "warn"), 0.0, 1.0)
			if age >= n(ev, "warn"):
				ev.phase = CROSS
				ev.since = g.clock
		CROSS:
			ev.tw_k = 1.0
			ev.tw_run += n(ev, "speed") * dt
			if ev.tw_run >= ev.tw_from.distance_to(ev.tw_to):
				lift(ev)
		LIFT:
			ev.tw_run += n(ev, "speed") * dt
			ev.tw_k = clampf(1.0 - age / n(ev, "lift"), 0.0, 1.0)
			if ev.tw_k <= 0.0:
				ev.finish()
				return
	ev.tw_at = where(ev)
	if ev.tw_k > .3:
		_pull(ev, dt)


## What it does round it this tick, by how strong it is.
static func _pull(ev: CountyEvents, dt: float) -> void:
	var g := ev.game
	var at := ev.tw_at
	var k := ev.tw_k
	var core := n(ev, "core") * (.6 + .4 * k)
	var reach := n(ev, "reach") * k
	ev.tw_bite -= dt
	ev.tw_rip -= dt
	ev.tw_fling -= dt
	var biting := ev.tw_bite <= 0.0
	if biting:
		ev.tw_bite = .5
	for p: Player in g.players:
		if p.away or p.health <= 0:
			continue
		var push := _drag(ev, Vector2(p.x, p.y), core, reach, g.world.stand(p))
		if push == Vector2.INF:
			continue
		g.move_actor(p, push.x * dt, push.y * dt, GameState.PLAYER_RADIUS)
		if Vector2(p.x, p.y).distance_to(at) < core and biting:
			p.knocked = maxf(p.knocked, n(ev, "knock"))
			g.damage(n(ev, "bite") * .5, [at.x, at.y], "TWISTER", p)
	for e: Enemy in g.enemies:
		if not e.alive or e.dormant or Enemy.BOSS_TITLES.has(e.kind) or e.swims:
			continue
		if absf(e.x - at.x) > reach or absf(e.y - at.y) > reach:
			continue
		var push := _drag(ev, Vector2(e.x, e.y), core, reach, g.world.stand(e))
		if push == Vector2.INF:
			continue
		g.move_actor(e, push.x * dt, push.y * dt, e.radius)
		if Vector2(e.x, e.y).distance_to(at) < core and biting:
			e.stun = maxf(e.stun, .6)
			e.flinch = maxf(e.flinch, .3)
			if e.hostile:
				e.alerted = true
			Players.world_hurt(g, e, n(ev, "bite_enemy") * .5, false, "twister")
	if biting:
		_smash(ev, at, core)
	if ev.tw_rip <= 0.0:
		ev.tw_rip = n(ev, "rip_every")
		var sets: SetPiecesFeature = g.features.get("set_pieces")
		var ground := g.world.elevation(at.x, at.y)
		if sets != null:
			sets.blast(at.x, at.y, ground + 1.2, core + 1.0, n(ev, "rip") * k, false)
		var bodies: Corpses = g.features.get("corpses")
		if bodies != null:
			bodies.shove(at.x, at.y, core + 1.5, 3.0 * k)
	if ev.tw_fling <= 0.0:
		ev.tw_fling = n(ev, "fling_every")
		_fling(ev, at, reach)


## The pull on a body at `q` on a floor at `z`: cells a second, or INF when it
## is out of reach or under a roof.
static func _drag(ev: CountyEvents, q: Vector2, core: float, reach: float, z: float) -> Vector2:
	var to := ev.tw_at - q
	var d := to.length()
	if d >= reach or ev.roofed(q.x, q.y, z):
		return Vector2.INF
	var inward := to / maxf(.05, d)
	var round := Vector2(-inward.y, inward.x)
	var near := 1.0 - clampf((d - core) / maxf(.1, reach - core), 0.0, 1.0)
	var pace := n(ev, "pull") * (.25 + .75 * near * near)
	var swirl := n(ev, "swirl")
	if d < core * .5:
		# In the eye: spun round, not drawn further in.
		return round * pace * 1.2
	return (inward * (1.0 - swirl) + round * swirl) * pace


## The breakables in the core are smashed.
static func _smash(ev: CountyEvents, at: Vector2, core: float) -> void:
	var g := ev.game
	var pieces: Breakables = g.features.get("breakables")
	if pieces == null:
		return
	var reach := core + n(ev, "smash")
	for i in pieces.pieces.size():
		var piece: Breakables.Piece = pieces.pieces[i]
		if piece.broken or absf(piece.x - at.x) > reach or absf(piece.y - at.y) > reach:
			continue
		if Vector2(piece.x - at.x, piece.y - at.y).length() > reach:
			continue
		if ev.roofed(piece.x, piece.y, g.world.stand(piece) + piece.z):
			continue
		var round := Vector2(-(piece.y - at.y), piece.x - at.x).normalized()
		pieces.strike(i, n(ev, "smash_hp") * .5, round.x, round.y)


## A loose thing near it torn off its place and flung round.
static func _fling(ev: CountyEvents, at: Vector2, reach: float) -> void:
	var g := ev.game
	var carry: Carry = g.features.get("carry")
	if carry == null or not carry.allowed():
		return
	var best := -1
	var best_d := reach
	for i in carry.things.size():
		var t: Carry.Thing = carry.things[i]
		if not carry.takeable(t):
			continue
		var place := carry.place_of(t)
		var d := Vector2(place.x - at.x, place.y - at.y).length()
		if d < best_d and not ev.roofed(place.x, place.y, place.z):
			best = i
			best_d = d
	if best < 0:
		return
	var thing: Carry.Thing = carry.things[best]
	var from := carry.place_of(thing)
	var inward := (at - Vector2(from.x, from.y)).normalized()
	var round := Vector2(-inward.y, inward.x)
	var speed := n(ev, "fling") / sqrt(maxf(.4, thing.weight))
	var dir := round * .8 + inward * .2 + Vector2.from_angle(g.rng.random() * TAU) * .25
	dir = dir.normalized() * speed
	carry.fling(best, dir.x, dir.y, n(ev, "fling_up") / sqrt(maxf(.4, thing.weight)))
