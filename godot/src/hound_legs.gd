## How BLUE gets about (features/hound.gd, pass 10): the way to where he
## goes, walked straight when he can and else planned over the level's floor
## (doors as they stand, hazards shut), with sliding round what is in the
## way and a hop out of nobody's sight when he is truly stuck; what is
## dangerous to stand in; where he ranges to; where a lost dog may turn up
## unseen; out of a player's sights; his place by a vehicle.
## Plain sums on the game and the dog: no dice of its own (a ranging spot's
## comes from game.rng, handed in), the same on every machine.
class_name HoundLegs
extends RefCounted

const FireScript := preload("res://src/features/fire.gd")
const RaceLaps := preload("res://src/features/race_laps.gd")
## A player sees what is within this cosine of where they look (the view is
## about 100 degrees wide; a little more, to be safe) or right beside them.
const VIEW_COS := .55
const VIEW_NEAR := 1.6
## How far apart a straight walk is tested (cells), and the longest tested.
const PROBE := .3
const PROBE_MOST := 14.0
## Turns tried, in order, when the way ahead is shut or dangerous.
const TURNS := [0.0, .45, -.45, .9, -.9, 1.4, -1.4, 2.0, -2.0, 2.7, -2.7]


## The level's standing hazards he keeps clear of, read once a game: (x, y,
## reach + `pad`) of each saw, chipper, zapper, hot fence, burn barrel and
## crusher (BrawlHazards; a well and a cattle guard are walked past).
static func harms_of(g: Game, pad: float) -> Array:
	var out: Array = []
	for spot: Array in BrawlHazards.spots(g.world):
		var kind: String = spot[0]
		if kind == "well" or kind == "guard":
			continue
		var reach: float = BrawlHazards.value(kind, "reach", .8)
		var sx: float = spot[1]
		var sy: float = spot[2]
		out.append(Vector3(sx, sy, reach + pad))
	return out


## What is dangerous this tick, as circles (x, y, reach): the standing
## hazards, a twister, steam and chalk, the race's cars, and a boss winding
## up (round where it aims and along the way to it). Fire and deep water are
## asked where he steps (harm()).
static func dangers(g: Game, harms: Array, telegraph: float) -> Array:
	var out: Array = harms.duplicate()
	var ev: CountyEvents = g.features.get("events")
	if ev != null and ev.kind == "twister" and ev.tw_k > .2:
		var core := ev.n("twister", "core") * (.6 + .4 * ev.tw_k)
		out.append(Vector3(ev.tw_at.x, ev.tw_at.y, core + 1.5))
	for hz: GameState.Hazard in g.hazards:
		out.append(Vector3(hz.x, hz.y, hz.radius))
	var laps: RaceLaps = g.features.get("race_laps")
	if laps != null and laps.total > 0.0:
		for car: Array in laps.cars:
			var speed: float = car[1]
			if speed > 0.0:
				var along: float = car[0]
				var at: Vector2 = laps._at(along)[0]
				out.append(Vector3(at.x, at.y, 1.6))
	for e: Enemy in g.enemies:
		if not e.alive or not Enemy.BOSS_TITLES.has(e.kind):
			continue
		out.append(Vector3(e.x, e.y, e.radius + 1.2))
		if e.windup > 0.0 and e.aim_mark is Array:
			var mark: Array = e.aim_mark
			var ax: float = mark[0]
			var ay: float = mark[1]
			out.append(Vector3(ax, ay, telegraph))
			var gap := Vector2(ax - e.x, ay - e.y).length()
			var k := 1.0
			while k < gap:
				var t := k / gap
				out.append(Vector3(lerpf(e.x, ax, t), lerpf(e.y, ay, t), 1.1))
				k += 1.0
	return out


## Whether (x, y) is somewhere he should not stand: in one of `danger`'s
## circles (grown by `pad`), on a burning cell, in deep water.
static func harm(g: Game, danger: Array, x: float, y: float, pad := 0.0) -> bool:
	for c: Vector3 in danger:
		var r := c.z + pad
		if absf(x - c.x) < r and absf(y - c.y) < r and Vector2(x - c.x, y - c.y).length() < r:
			return true
	if g.world.deep_at(x, y) and not g.world.over_deep(x, y):
		return true
	var fire: FireScript = g.features.get("fire")
	return fire != null and not fire.burning.is_empty() and fire.burning_at(x, y)


## Whether he can walk straight from where he is to (tx, ty): `body` (a
## scratch body) walked there in short steps the way he moves (walls, steps,
## decks, deep water) goes the whole way, into nothing dangerous and off no
## ledge.
static func walk_clear(
	g: Game, body: Enemy, danger: Array, d: Game.HoundScript.Dog, tx: float, ty: float, r: float
) -> bool:
	var gap := Vector2(tx - d.x, ty - d.y).length()
	if gap > PROBE_MOST:
		return false
	if gap < .01:
		return true
	var steps := maxi(1, ceili(gap / PROBE))
	var sx := (tx - d.x) / steps
	var sy := (ty - d.y) / steps
	body.x = d.x
	body.y = d.y
	body.floor_z = d.floor_z
	body.radius = r
	for k in steps:
		var was_x := body.x
		var was_y := body.y
		var was_z := body.floor_z
		g.world.move(body, sx, sy, r)
		if absf(body.x - was_x - sx) > .01 or absf(body.y - was_y - sy) > .01:
			return false
		if body.floor_z < was_z - .7 or harm(g, danger, body.x, body.y):
			return false
	return true


## A way from the dog to `goal` over the level's floor as it stands now
## (closed doors shut, the standing hazards and fire shut): the cell centres
## to walk, nearest first, or none. `field` is a scratch flow field this
## writes over (it keeps nothing between plans, so a game and its copy plan
## the same way).
static func plan(
	g: Game,
	field: FlowField,
	harms: Array,
	d: Game.HoundScript.Dog,
	p: Player,
	goal: Vector2,
	goal_z: float,
	reach: int
) -> PackedVector2Array:
	var out := PackedVector2Array()
	field.open = p.flow.open.duplicate()
	var w := g.world
	var width := w.width
	for c: Vector3 in harms:
		for cy in range(maxi(0, int(c.y - c.z)), mini(w.height - 1, int(c.y + c.z)) + 1):
			for cx in range(maxi(0, int(c.x - c.z)), mini(width - 1, int(c.x + c.z)) + 1):
				if Vector2(cx + .5 - c.x, cy + .5 - c.y).length() < c.z + .3:
					field.open[cy * width + cx] = 0
	var fire: FireScript = g.features.get("fire")
	if fire != null:
		for row: Array in fire.burning:
			var cell: int = row[FireScript.CELL]
			if cell >= 0 and cell < width * w.height:
				field.open[cell] = 0
	field.reach = reach
	field.origin = Vector2i(-1, -1)
	field.next_at = 0.0
	field.update(goal.x, goal.y, 0.0, goal_z)
	var cells: Array = []
	field.waypoint(d.x, d.y, reach + 4, cells, d.floor_z)
	if field.distance(d.x, d.y, d.floor_z) >= FlowField.FAR:
		return out
	for cell: Vector2i in cells:
		out.append(Vector2(cell.x + .5, cell.y + .5))
	return out


## Moves him by (dx, dy) as a body of the level would go (walls, steps,
## decks): how far he went.
static func move(
	g: Game, body: Enemy, d: Game.HoundScript.Dog, dx: float, dy: float, r: float
) -> float:
	body.x = d.x
	body.y = d.y
	body.floor_z = d.floor_z
	body.radius = r
	g.world.move(body, dx, dy, r)
	var moved := Vector2(body.x - d.x, body.y - d.y).length()
	d.x = body.x
	d.y = body.y
	d.floor_z = body.floor_z
	return moved


## Whether he is caught inside something where he stands (dropped in a
## prop's corner, a door shut on him: no little step goes anywhere), and if
## so the nearest spot a short hop away he can move from (Vector2.INF: not
## caught, or nowhere). `body` is a scratch body.
static func unstuck(g: Game, body: Enemy, d: Game.HoundScript.Dog, r: float) -> Vector2:
	if _free(g, body, d.x, d.y, d.floor_z, r):
		return Vector2.INF
	for gap: float in [.15, .3, .45, .6, .8]:
		for k in 8:
			var a := k * TAU / 8.0
			var at := Vector2(d.x + cos(a) * gap, d.y + sin(a) * gap)
			if not g.world.deep_at(at.x, at.y) and _free(g, body, at.x, at.y, d.floor_z, r):
				return at
	return Vector2.INF


## Whether a body of radius r at (x, y) on a floor at z can take a little
## step some way.
static func _free(g: Game, body: Enemy, x: float, y: float, z: float, r: float) -> bool:
	for nudge: Vector2 in [Vector2(.03, 0), Vector2(-.03, 0), Vector2(0, .03), Vector2(0, -.03)]:
		body.x = x
		body.y = y
		body.floor_z = z
		body.radius = r
		g.world.move(body, nudge.x, nudge.y, r)
		if absf(body.x - x) + absf(body.y - y) > .02:
			return true
	return false


## A step of `step` cells along `heading`, or the nearest turn off it that
## goes somewhere and does not walk him into harm (out of harm, any way
## that gets him out). Returns [how far he went, the heading taken].
static func step(
	g: Game,
	body: Enemy,
	danger: Array,
	d: Game.HoundScript.Dog,
	heading: float,
	length: float,
	r: float
) -> Array:
	var in_harm := harm(g, danger, d.x, d.y)
	var ahead := r + .3
	for turn: float in TURNS:
		var h := heading + turn
		var lx := d.x + cos(h) * (length + ahead)
		var ly := d.y + sin(h) * (length + ahead)
		if not in_harm and harm(g, danger, lx, ly):
			continue
		var was := Vector2(d.x, d.y)
		var was_z := d.floor_z
		var moved := move(g, body, d, cos(h) * length, sin(h) * length, r)
		if moved > length * .3:
			if in_harm or not harm(g, danger, d.x, d.y):
				return [moved, h]
		# Not that way: back where he stood.
		d.x = was.x
		d.y = was.y
		d.floor_z = was_z
	return [0.0, heading]


## The player whose sights he is in (closer than `reach`, within `cone`, a
## cosine, of where they look, in their sight), the nearest; null if none.
static func in_sights(g: Game, d: Game.HoundScript.Dog, reach: float, cone: float) -> Player:
	var best: Player = null
	var best_d := reach
	for q: Player in g.players:
		if q.away or q.health <= 0:
			continue
		var to := Vector2(d.x - q.x, d.y - q.y)
		var gap := to.length()
		if gap >= best_d or gap < .3:
			continue
		if to.dot(Vector2(cos(q.angle), sin(q.angle))) < cone * gap:
			continue
		if not g.world.visible(q.x, q.y, d.x, d.y, q.eye, d.floor_z + .4):
			continue
		best = q
		best_d = gap
	return best


## Whether (x, y) is in front of any player's sights (within `reach` and
## `cone` of where they look).
static func before_sights(g: Game, x: float, y: float, reach: float, cone: float) -> bool:
	for q: Player in g.players:
		if q.away or q.health <= 0:
			continue
		var to := Vector2(x - q.x, y - q.y)
		var gap := to.length()
		if gap < reach and gap > .2 and to.dot(Vector2(cos(q.angle), sin(q.angle))) > cone * gap:
			return true
	return false


## Whether any player could see (x, y) on a floor at z: in their view and in
## their sight, or right beside them.
static func seen(g: Game, x: float, y: float, z: float) -> bool:
	for q: Player in g.players:
		if q.away:
			continue
		var to := Vector2(x - q.x, y - q.y)
		var gap := to.length()
		if gap < VIEW_NEAR:
			return true
		if to.dot(Vector2(cos(q.angle), sin(q.angle))) < VIEW_COS * gap:
			continue
		if g.world.visible(q.x, q.y, x, y, q.eye, z + .4):
			return true
	return false


## Whether (x, y) is a fair place for him to stand: open for his body, not
## in harm, near player p's floor and walkable to them (their flow field
## reaches it, not by a long way round).
static func fair(
	g: Game, danger: Array, p: Player, x: float, y: float, r: float, pad: float
) -> bool:
	var w := g.world
	if x < 1.0 or y < 1.0 or x > w.width - 1 or y > w.height - 1:
		return false
	var floor_z := w.floor_under(x, y, w.stand(p) + .5)
	if w.blocked(x, y, r + .05, floor_z + .3 if w.geo != null else null):
		return false
	if absf(floor_z - w.stand(p)) > .6 or harm(g, danger, x, y, pad):
		return false
	if p.flow == null:
		return true
	var steps := p.flow.distance(x, y, floor_z)
	var straight := Vector2(x - p.x, y - p.y).length()
	return steps < FlowField.FAR and steps <= straight * 1.7 + 3.0


## Where he ranges to: `near` to `far` cells from player p, `side_min` to
## `side_max` radians off `base` (to one side or the other, `side` first),
## somewhere fair and out of every player's sights; Vector2.INF if no try
## of a few finds one. `roll` is a game.rng draw for each try (two a try).
static func roam_spot(
	g: Game,
	danger: Array,
	p: Player,
	base: float,
	side: float,
	near: float,
	far: float,
	side_min: float,
	side_max: float,
	n: Dictionary
) -> Vector2:
	var r: float = n["radius"]
	var pad: float = n["harm_pad"]
	var reach: float = n["clear_reach"]
	var cone: float = n["clear_cone"]
	for k in 6:
		var a := base + (side if k % 2 == 0 else -side) * lerpf(side_min, side_max, g.rng.random())
		var gap := lerpf(near, far, g.rng.random())
		var at := Vector2(p.x + cos(a) * gap, p.y + sin(a) * gap)
		if before_sights(g, at.x, at.y, reach, cone - .04):
			continue
		if fair(g, danger, p, at.x, at.y, r, pad):
			return at
	return Vector2.INF


## Where a lost dog turns up: `near` to `far` cells behind player p (off
## their back, either side), fair, and seen by nobody; Vector2.INF if none.
static func hidden_spot(
	g: Game, danger: Array, p: Player, near: float, far: float, r: float, pad: float
) -> Vector2:
	var back := p.angle + PI
	var gap := near
	while gap <= far + .01:
		for turn: float in [0.0, .5, -.5, 1.0, -1.0, 1.5, -1.5]:
			var a := back + turn
			var at := Vector2(p.x + cos(a) * gap, p.y + sin(a) * gap)
			if not fair(g, danger, p, at.x, at.y, r, pad):
				continue
			if seen(g, at.x, at.y, g.world.floor_under(at.x, at.y, g.world.stand(p) + .5)):
				continue
			return at
		gap += 1.5
	return Vector2.INF


## His place behind his player, off to his side, `back` cells; behind the
## vehicle at their wheel. Straight behind when his side is shut.
static func heel_spot(
	g: Game, d: Game.HoundScript.Dog, p: Player, back: float, r: float
) -> Vector2:
	var rides: Game.VehiclesScript = g.features.get("vehicles")
	if rides != null and rides.seated(p):
		var v: VehicleDrive.Ride = rides.rides[rides.seat_of(p).x]
		var s := VehicleDrive.spec(v.kind)
		var tail := s.length * .5 + back
		var aside := d.side * s.width * .3
		return Vector2(
			v.x - cos(v.h) * tail - sin(v.h) * aside, v.y - sin(v.h) * tail + cos(v.h) * aside
		)
	var a := p.angle + PI - d.side * .5
	var spot := Vector2(p.x + cos(a) * back, p.y + sin(a) * back)
	if g.world.blocked(spot.x, spot.y, r) or g.world.deep_at(spot.x, spot.y):
		var b := p.angle + PI
		spot = Vector2(p.x + cos(b) * back * .7, p.y + sin(b) * back * .7)
	return spot


## A vehicle's second seat (where a rider sits: vehicles.gd _place, k 1).
static func seat_at(v: VehicleDrive.Ride) -> Vector2:
	var s := VehicleDrive.spec(v.kind)
	var along := s.seat - s.ride_back
	return Vector2(
		v.x + cos(v.h) * along - sin(v.h) * s.ride_side,
		v.y + sin(v.h) * along + cos(v.h) * s.ride_side
	)


## Somewhere beside vehicle v to hop down to, nearest `near`: its sides,
## behind, in front; Vector2.INF when there is no room.
static func beside(g: Game, v: VehicleDrive.Ride, near: Vector2, r: float) -> Vector2:
	var s := VehicleDrive.spec(v.kind)
	var half_w := s.width * .5 + .4
	var half_l := s.length * .5 + .4
	var f := Vector2(cos(v.h), sin(v.h))
	var side := Vector2(-sin(v.h), cos(v.h))
	var best := Vector2.INF
	var best_d := INF
	for off: Vector2 in [
		side * half_w,
		-side * half_w,
		-f * half_l,
		f * half_l,
		side * (half_w + .6),
		-side * (half_w + .6)
	]:
		var at := Vector2(v.x, v.y) + off
		if g.world.blocked(at.x, at.y, r) or harm(g, [], at.x, at.y):
			continue
		if harm(g, [], at.x + r, at.y + r) or harm(g, [], at.x - r, at.y - r):
			continue
		if absf(g.world.floor_under(at.x, at.y, v.z + 1.0) - v.z) > .8:
			continue
		var gap := at.distance_to(near)
		if gap < best_d:
			best_d = gap
			best = at
	return best


static func turn(from: float, to: float, most: float) -> float:
	var delta := wrapf(to - from, -PI, PI)
	return from + clampf(delta, -most, most)
