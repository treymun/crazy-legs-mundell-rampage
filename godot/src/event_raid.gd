## The revenue raid (features/county_events.gd): sirens, then a squad of
## revenue men come out of the player's sight and storm a moonshine still (or
## the county's hands where they gather). They fight whoever they meet: the
## county's hands (each side holds a grudge on the other: the hands come at
## them with their fists, the revenue men shoot) and the player. Once at the
## still they bust it. The raid is over when the last of them is down, or
## after `most` (any left are hands like the rest).
##
## The squad is the first kind in events.cfg [raid] kinds the game has: the
## revenooers (the Moonshine Run's agents), else the county's deputies (yard
## deputies and shield deputies, in the state's pay tonight). They join the enemies after
## the level's own (features/posse.gd saves them) and count as varmints.
class_name EventRaid
extends RefCounted

const Breakables := preload("res://src/features/breakables.gd")

const WARN := 0
const STORM := 1
## The stills' pictures.
const STILLS := ["town_still", "town_copper_vat", "town_shine_tank"]


static func n(ev: CountyEvents, key: String) -> float:
	return ev.n("raid", key)


## The kind the squad is made of (the first events.cfg lists that exists).
static func squad_kind() -> String:
	var kinds: Array = CountyEvents.value("raid", "kinds", [])
	for k: Variant in kinds:
		if Enemy.DEFS.has(str(k)):
			return str(k)
	return "yard_deputy"


## Whether hand `e` is one of the county's the raiders fight.
static func local(ev: CountyEvents, e: Enemy) -> bool:
	return (
		e.alive
		and not e.dormant
		and e.tactical()
		and not Enemy.BOSS_TITLES.has(e.kind)
		and not raider(ev, e)
	)


static func raider(ev: CountyEvents, e: Enemy) -> bool:
	if ev.raiders.is_empty():
		return false
	var i := ev.game.enemies.find(e)
	return i >= 0 and ev.raiders.has(i)


## Picks the spot and brings the squad in: true when it could.
static func start(ev: CountyEvents) -> bool:
	var g := ev.game
	var p := ev.someone()
	if p == null:
		return false
	var spot := Vector2.INF
	ev.raid_still = -1
	var pieces: Breakables = g.features.get("breakables")
	if pieces != null:
		var best := n(ev, "still_far")
		for i in pieces.pieces.size():
			var piece: Breakables.Piece = pieces.pieces[i]
			if piece.broken or not STILLS.has(piece.image):
				continue
			var d := Vector2(piece.x - p.x, piece.y - p.y).length()
			if d < best and d > 6.0 and ev.far_from_bosses(piece.x, piece.y):
				best = d
				spot = Vector2(piece.x, piece.y)
				ev.raid_still = i
	if spot == Vector2.INF:
		spot = _gathering(ev, p)
	if spot == Vector2.INF:
		return false
	var from := _way_in(ev, p, spot)
	if from == Vector2.INF:
		return false
	ev.raid_at = spot
	ev.raiders.clear()
	ev.raid_shots.clear()
	ev.busted = false
	var count := int(n(ev, "count_hard") if g.difficulty >= 2 else n(ev, "count"))
	var kind := squad_kind()
	var def: Dictionary = Enemy.DEFS[kind]
	var r: float = def.get("radius", .25)
	for k in count:
		var at := from
		# The first on the spot, the rest round it (all on one point before:
		# a knot of bodies that hardly moved).
		var rings: Array = [0.0, .9, 1.4, 2.0, 2.6] if k == 0 else [.9, 1.4, 2.0, 2.6]
		var placed := false
		# Its own turn on each ring first (as before), then round the rings
		# (pass 15: in a tight spot every first turn was walled and the squad
		# stood on one point again).
		for turn in 6:
			for reach: float in rings:
				var a := k * 2.4 + reach + turn * TAU / 6.0
				var q := from + Vector2.from_angle(a) * reach
				if g.world.blocked(q.x, q.y, r + .06) or g.world.deep_at(q.x, q.y):
					continue
				if turn > 0 and _taken(g, ev, q):
					continue
				at = q
				placed = true
				break
			if placed:
				break
		var e := Enemy.new(kind, at.x, at.y, (spot - at).angle())
		e.alerted = true
		e.target = [spot.x, spot.y]
		e.hunt_until = g.clock + 40.0
		e.flank = .5 if k % 2 == 0 else -.5
		ev.raiders.append(g.enemies.size())
		g.enemies.append(e)
		g.total_kills += 1
	g.message("REVENUERS! THE LAW'S RAIDIN' THE STILLS!", 3.5)
	return true


## Whether one of the squad already stands at `q`.
static func _taken(g: Game, ev: CountyEvents, q: Vector2) -> bool:
	for i: int in ev.raiders:
		var e: Enemy = g.enemies[i]
		if Vector2(e.x, e.y).distance_to(q) < .5:
			return true
	return false


## Where the county's hands gather, out of the player's way: the hand with
## the most of them near it (one alone if need be), up or asleep, or INF.
## Asleep counts: most of a chapter's hands are, and `alive` says no for
## them, which left a raid nowhere to go but a still close by (it started
## in the hickston alone).
static func _gathering(ev: CountyEvents, p: Player) -> Vector2:
	var g := ev.game
	# The most hands near one another wins; one alone will do.
	var best := -1
	var spot := Vector2.INF
	var far := CountyEvents.span("raid", "gather_far")
	for e: Enemy in g.enemies:
		if not _gathers(ev, e) or e.alerted:
			continue
		var d := Vector2(e.x - p.x, e.y - p.y).length()
		if d < far.x or d > far.y or not ev.far_from_bosses(e.x, e.y):
			continue
		var near := 0
		for o: Enemy in g.enemies:
			if o != e and _gathers(ev, o) and Vector2(o.x - e.x, o.y - e.y).length() < 6.0:
				near += 1
		if near > best:
			best = near
			spot = Vector2(e.x, e.y)
	return spot


## Whether hand `e` counts towards a gathering: one of the county's, up or
## asleep.
static func _gathers(ev: CountyEvents, e: Enemy) -> bool:
	return e.hp > 0.0 and e.tactical() and not Enemy.BOSS_TITLES.has(e.kind) and not raider(ev, e)


## An open spot `come_from` away from `spot`, out of every player's sight,
## that the player's flow field reaches (so the squad can get there), or INF.
static func _way_in(ev: CountyEvents, p: Player, spot: Vector2) -> Vector2:
	var g := ev.game
	var w := g.world
	var span := CountyEvents.span("raid", "come_from")
	var base := g.rng.random() * TAU
	var ground := w.elevation(spot.x, spot.y)
	# The rings from `come_from`, then nearer and further when none is open.
	for ring: float in [span.x, (span.x + span.y) * .5, span.y, span.x * .7, span.y * 1.3]:
		for k in 16:
			var q := spot + Vector2.from_angle(base + k * TAU / 16.0) * ring
			if q.x < 2.0 or q.y < 2.0 or q.x > w.width - 2.0 or q.y > w.height - 2.0:
				continue
			if w.blocked(q.x, q.y, .5) or w.deep_at(q.x, q.y):
				continue
			if absf(w.elevation(q.x, q.y) - ground) > .6:
				continue
			if Vector2(q.x - p.x, q.y - p.y).length() < 9.0:
				continue
			var seen := false
			for o: Player in g.players:
				if w.visible(o.x, o.y, q.x, q.y):
					seen = true
			if seen or not ev.far_from_bosses(q.x, q.y):
				continue
			if p.flow != null and p.flow.distance(q.x, q.y, ground) >= FlowField.FAR:
				continue
			return q
	return Vector2.INF


static func step(ev: CountyEvents, dt: float) -> void:
	var g := ev.game
	var age := g.clock - ev.since
	if ev.phase == WARN and age >= n(ev, "warn"):
		ev.phase = STORM
	var standing := 0
	ev.raid_look -= dt
	var look := ev.raid_look <= 0.0
	if look:
		ev.raid_look = .5
	for i: int in ev.raiders:
		if i >= g.enemies.size():
			continue
		var e: Enemy = g.enemies[i]
		if not e.alive:
			continue
		standing += 1
		if look:
			_feud_for(ev, e)
		if (
			not ev.busted
			and ev.raid_still >= 0
			and Vector2(e.x - ev.raid_at.x, e.y - ev.raid_at.y).length() < n(ev, "bust_reach")
		):
			_bust(ev, e)
	if standing == 0:
		g.message("THAT'S THE LAST OF THE REVENUERS.", 3.0)
		ev.finish()
	elif age > n(ev, "most"):
		ev.finish()


## A raider picks a fight with the nearest of the county's hands it sees
## (and that hand with it); a feud already on is kept going.
static func _feud_for(ev: CountyEvents, e: Enemy) -> void:
	var g := ev.game
	if e.grudge != null and e.grudge.alive:
		e.grudge_until = g.clock + 6.0
		if e.grudge.grudge == e:
			e.grudge.grudge_until = g.clock + 6.0
		return
	var best: Enemy = null
	var best_d := n(ev, "aim_far")
	for o: Enemy in g.enemies:
		if not local(ev, o):
			continue
		var d := Vector2(o.x - e.x, o.y - e.y).length()
		if d < best_d and g.world.visible(e.x, e.y, o.x, o.y):
			best = o
			best_d = d
	if best == null:
		if e.target == null:
			e.target = [ev.raid_at.x, ev.raid_at.y]
		return
	e.grudge = best
	e.grudge_until = g.clock + 6.0
	e.cooldown = minf(e.cooldown, .25)
	e.cover = null
	if best.grudge == null or not best.grudge.alive:
		best.wake(g, e.x, e.y)
		best.grudge = e
		best.grudge_until = g.clock + 6.0
		best.cover = null
		best.fetching = null


static func _bust(ev: CountyEvents, e: Enemy) -> void:
	var g := ev.game
	ev.busted = true
	var pieces: Breakables = g.features.get("breakables")
	if pieces == null:
		return
	var piece: Breakables.Piece = pieces.pieces[ev.raid_still]
	if piece.broken:
		return
	var way := Vector2(piece.x - e.x, piece.y - e.y).normalized()
	g.sound_at("deputy_shot", e.x, e.y, .9)
	pieces.strike(ev.raid_still, n(ev, "bust"), way.x, way.y)
	g.message("THE REVENUERS BUSTED THE STILL!", 2.5)


## Enemy.tick's question before a brawl (CountyEvents.feud): a raider with a
## grudge on a hand it can see shoots at it instead of walking up to punch
## (the hands walk up and punch, as in any brawl).
static func feud(ev: CountyEvents, e: Enemy, _dt: float) -> bool:
	var g := ev.game
	var foe := e.grudge
	if foe == null or not foe.alive or not raider(ev, e):
		return false
	var gap := Vector2(foe.x - e.x, foe.y - e.y).length()
	var eye := g.world.stand(e) + .9
	var aim := g.world.stand(foe) + minf(.9, foe.height * .7)
	if not g.world.visible(e.x, e.y, foe.x, foe.y, eye, aim):
		return false
	var heading := atan2(foe.y - e.y, foe.x - e.x)
	e.angle = heading
	e.face_left = cos(heading) < 0.0
	if e.cooldown > 0.0 or e.stun > 0.0:
		return true
	e.cooldown = n(ev, "shot_every") + g.rng.random() * n(ev, "shot_more")
	e.recovery = e.recovery_time()
	g.sound_at("deputy_shot", e.x, e.y, .85)
	var chance := n(ev, "hit") * (1.0 - .5 * clampf(gap / n(ev, "aim_far"), 0.0, 1.0))
	var end := Vector3(foe.x, foe.y, aim)
	if g.rng.random() < chance:
		foe.hurt(n(ev, "hurt"), g, false, false, e)
	else:
		var miss := Vector2(-sin(heading), cos(heading)) * (.4 + g.rng.random() * .5)
		miss *= 1.0 if g.rng.random() < .5 else -1.0
		end = Vector3(foe.x + miss.x, foe.y + miss.y, aim + g.rng.uniform(-.3, .3))
	ev.raid_shots.append([e.x, e.y, eye, end.x, end.y, end.z, g.clock])
	while ev.raid_shots.size() > 10:
		ev.raid_shots.pop_front()
	return true
