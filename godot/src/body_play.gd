## The active bodies' play (pass 15, T11 ACTIVE BODIES): what a shove does to
## where a living man goes and whether he stays up, past what the stagger
## (src/stagger.gd) says. Arithmetic on play's own numbers and the level's
## shape only, no dice (game.rng is never drawn), so it is the same on every
## machine; what the looks must know is carried in one note on the enemy
## (`KEY`, Enemy.notes: online and saved like any field):
##
## - **A hand on something.** A reel his catch steps cannot stop, next to a
##   rail, a fence, a crate or a car's edge within his reach (`edge`): he
##   grabs it and stays up, held `grab_hold` seconds (stunned); the note keeps
##   the point, so every screen puts his hand on the same spot.
## - **Over a low rail.** Driven into a rail no higher than `over_high` of
##   him faster than `over_speed` (a reel, a boot's slide): over it he goes,
##   backwards, to the far side if he fits there, and down (pitched)
##   `over_down` times as long; off a loft's rail he falls the rest
##   (Climbing). A boot's slide stopped hard by a wall puts him down too.
## - **Run into by a vehicle** and still up: knocked flat (`ram_down` times
##   as long as pitched over), sliding on at `ram_share` of its speed.
## - **The drunk's lurch.** A drunk (Variants.STUMBLE) lurches sideways each
##   `lurch_gait` of his gait, his weave over-corrected (`lurch` cells; every
##   `lurch_big`-th `lurch_big_k` times that): the stagger's pendulum catches
##   it with steps or he goes down.
##
## Off (hits.cfg [bodies] play=false, `ON`): none of it, play as before.
## The looks (src/active_body.gd, src/dying_doll.gd) read the note and the
## stagger's; nothing they do comes back here.
class_name BodyPlay
extends RefCounted

const KEY := "body"
## The note's slots: what (HOLDING, OVER), the point (a grab's hand, the
## rail gone over), since and until when (game.clock).
const MODE := 0
const X := 1
const Y := 2
const Z := 3
const AT := 4
const UNTIL := 5
const SIZE := 6
const HOLDING := 1
const OVER := 2

static var ON: bool = HitData.value("bodies", "play", true)
static var GRAB_REACH: float = HitData.value("bodies", "grab_reach", .5)
static var GRAB_LOW: float = HitData.value("bodies", "grab_low", .4)
static var GRAB_HIGH: float = HitData.value("bodies", "grab_high", .75)
static var GRAB_HOLD: float = HitData.value("bodies", "grab_hold", .7)
static var OVER_HIGH: float = HitData.value("bodies", "over_high", .68)
static var OVER_LOW: float = HitData.value("bodies", "over_low", .25)
static var OVER_SPEED: float = HitData.value("bodies", "over_speed", 1.1)
static var OVER_DOWN: float = HitData.value("bodies", "over_down", 1.6)
static var OVER_DROP: float = HitData.value("bodies", "over_drop", 3.2)
static var SLAM_DOWN: float = HitData.value("bodies", "slam_down", 1.0)
static var RAM_SHARE: float = HitData.value("bodies", "ram_share", .6)
static var RAM_DOWN: float = HitData.value("bodies", "ram_down", 1.4)
static var LURCH_GAIT: float = HitData.value("bodies", "lurch_gait", 15.0)
static var LURCH: float = HitData.value("bodies", "lurch", .3)
static var LURCH_BIG: int = HitData.value("bodies", "lurch_big", 4)
static var LURCH_BIG_K: float = HitData.value("bodies", "lurch_big_k", 3.4)
## The edge probe: the ways looked (radians off the way he goes), how far
## out (shares of the reach) and how high (shares of his height between
## GRAB_LOW and GRAB_HIGH).
const WAYS := [0.0, .55, -.55, 1.15, -1.15, 1.57, -1.57]
const OUT := [.45, .75, 1.0]
const UP := [0.0, .5, 1.0]
## How far over a solid point a top is looked for (an edge, not a wall).
const TOP_ROOM := .16


## A top edge within `reach` of (at, from height `feet`) a man `tall` could
## grab: a point in something solid (a rail, a fence, furniture, a crate, a
## car) with open air TOP_ROOM over it, between GRAB_LOW and GRAB_HIGH of his
## height, the nearest of those looked at round `way` (Vector3.INF none).
## `fine` false looks at fewer (the looks, every few frames).
static func edge(
	world: LevelData, at: Vector2, feet: float, tall: float, way: Vector2, reach: float, fine := true
) -> Vector3:
	if world == null or world.geo == null:
		return Vector3.INF
	if way.length_squared() < 1e-6:
		way = Vector2(1.0, 0.0)
	way = way.normalized()
	var best := Vector3.INF
	var best_d := INF
	var ways: Array = WAYS if fine else [0.0, .8, -.8, 1.57, -1.57]
	var outs: Array = OUT if fine else [.6, .95]
	var ups: Array = UP if fine else [.2, .8]
	for turn: float in ways:
		var dir := way.rotated(turn)
		for out: float in outs:
			var q := at + dir * reach * out
			if q.distance_to(at) >= best_d:
				continue
			if PhysCore.in_wall(world, Vector3(q.x, q.y, feet)):
				continue
			for up: float in ups:
				var z := feet + tall * lerpf(GRAB_LOW, GRAB_HIGH, up)
				var p := Vector3(q.x, q.y, z)
				if not _solid(world, p) or _solid(world, p + Vector3(0.0, 0.0, TOP_ROOM)):
					continue
				# The top between z and z + TOP_ROOM, found by halving.
				var lo := z
				var hi := z + TOP_ROOM
				for _k in 5:
					var mid := (lo + hi) * .5
					if _solid(world, Vector3(q.x, q.y, mid)):
						lo = mid
					else:
						hi = mid
				best = Vector3(q.x, q.y, (lo + hi) * .5)
				best_d = q.distance_to(at)
				break
	return best


static func _solid(world: LevelData, p: Vector3) -> bool:
	return world.blocked(p.x, p.y, .03, p.z) or PhysCore.rail_at(world, p, .03) != null


## A reel the steps cannot catch (Stagger.tick, before he goes down): an
## edge in reach the way he goes, and he holds on instead (true: the reel's
## note `s` stopped where he is; false: down he goes).
static func holds_on(e: Enemy, game: GameWorld, s: Array, v: Vector2) -> bool:
	if not ON:
		return false
	var tall := e.height * e.variant
	var feet: float = game.world.stand(e) + e.z
	var p := edge(game.world, Vector2(e.x, e.y), feet, tall, v, GRAB_REACH * tall)
	if p == Vector3.INF:
		return false
	s[Stagger.VX] = 0.0
	s[Stagger.VY] = 0.0
	s[Stagger.PX] = e.x
	s[Stagger.PY] = e.y
	s[Stagger.SWING] = 0.0
	_note(e, [HOLDING, p.x, p.y, p.z, game.clock, game.clock + GRAB_HOLD])
	e.stun = maxf(e.stun, GRAB_HOLD)
	return true


## Moving at `v` (cells a second) and stopped (Stagger._move, a boot's slide):
## a low rail ahead and fast enough, he goes over it to the far side and is
## put down (true; the stagger's note `s`, when there is one, says so).
static func over_rail(e: Enemy, game: GameWorld, v: Vector2, s: Array) -> bool:
	if not ON or v.length() < OVER_SPEED or e.climb_z > 0.0 or e.ladder >= 0:
		return false
	var w := game.world
	var way := v.normalized()
	var feet: float = w.stand(e) + e.z
	var tall := e.height * e.variant
	var probe := Vector3(e.x + way.x * (e.radius + .12), e.y + way.y * (e.radius + .12), feet)
	var rail: LevelGeometry.Segment = null
	for up: float in [.3, .55, .8]:
		rail = PhysCore.rail_at(w, probe + Vector3(0.0, 0.0, tall * up * OVER_HIGH), .12)
		if rail != null:
			break
	if rail == null:
		return false
	var high := rail.z1 - feet
	if high > tall * OVER_HIGH or high < OVER_LOW:
		return false
	# The far side: along the way past the bar until he fits (within a cell
	# and a bit), on a floor no further down than OVER_DROP.
	var start := Vector2(e.x, e.y)
	var far := Vector2.INF
	var d := e.radius
	while d < e.radius * 2.0 + 1.3:
		d += .05
		var q := start + way * d
		var under := w.floor_under(q.x, q.y, feet + .2)
		if under < feet - OVER_DROP:
			continue
		if (
			PhysCore.rail_at(w, Vector3(q.x, q.y, under + .3), e.radius + .02) != null
			or PhysCore.rail_at(w, Vector3(q.x, q.y, feet + .3), e.radius + .02) != null
		):
			continue
		if w.blocked(q.x, q.y, e.radius, under + .3) or PhysCore.in_wall(w, Vector3(q.x, q.y, under)):
			continue
		# (All of him over that floor: not still on the edge he went over.)
		var back := q - way * (e.radius + .03)
		if absf(w.floor_under(back.x, back.y, feet + .2) - under) > .05:
			continue
		far = q
		break
	if far == Vector2.INF:
		return false
	var cross := start + way * _to_line(rail, start, way)
	e.x = far.x
	e.y = far.y
	# (Its floor found again where it stands now: off a loft it falls.)
	game.move_actor(e, 0.0, 0.0, e.radius)
	_note(e, [OVER, cross.x, cross.y, rail.z1, game.clock, game.clock + 2.0])
	var secs := Stagger.PITCH_FOR * OVER_DOWN
	if s.size() == Stagger.SIZE:
		s[Stagger.DOWN] = secs
		s[Stagger.PITCH] = 1.0
		s[Stagger.SWING] = 0.0
		s[Stagger.VX] = v.x * .35
		s[Stagger.VY] = v.y * .35
		e.stun = maxf(e.stun, secs + Stagger.RISE)
	else:
		knock_down(e, game, v * .35, secs)
	return true


## How far along `way` from `at` the rail's line is (cells; 0 past it).
static func _to_line(rail: LevelGeometry.Segment, at: Vector2, way: Vector2) -> float:
	var a := Vector2(rail.ax, rail.ay)
	var run := Vector2(rail.bx - rail.ax, rail.by - rail.ay)
	var n := Vector2(-run.y, run.x).normalized()
	var toward := way.dot(n)
	if absf(toward) < 1e-4:
		return 0.0
	return maxf(0.0, (a - at).dot(n) / toward)


## A boot's slide (features/brawl.gd) stopped short at `v`: over a low rail,
## or slammed into a wall hard (faster than `slam_least`) and down.
static func slide_stopped(e: Enemy, game: GameWorld, v: Vector2, slam_least: float) -> bool:
	if not ON or not e.alive or BossKit.is_boss(e):
		return false
	if over_rail(e, game, v, []):
		return true
	if v.length() > slam_least and Stagger.can(e):
		knock_down(e, game, v * .1, Stagger.PITCH_FOR * SLAM_DOWN)
	return false


## Down at once (pitched over, `secs` and then up), sliding on at `v`: a
## stagger note that starts down.
static func knock_down(e: Enemy, game: GameWorld, v: Vector2, secs: float) -> void:
	var s := []
	s.resize(Stagger.SIZE)
	s.fill(0.0)
	s[Stagger.PX] = e.x
	s[Stagger.PY] = e.y
	s[Stagger.VX] = v.x
	s[Stagger.VY] = v.y
	s[Stagger.JX] = v.x
	s[Stagger.JY] = v.y
	s[Stagger.HZ] = .5
	s[Stagger.AT] = game.clock
	s[Stagger.DOWN] = secs
	s[Stagger.PITCH] = 1.0
	var notes := e.notes.duplicate()
	notes[Stagger.KEY] = s
	e.notes = notes
	e.stun = maxf(e.stun, secs + Stagger.RISE)


## Run into by a vehicle going `v` (cells a second) and still up: a reel.
static func rammed(e: Enemy, game: GameWorld, v: Vector2) -> void:
	if not ON or not e.alive or not Stagger.can(e) or BossKit.is_boss(e):
		return
	knock_down(e, game, v * RAM_SHARE, Stagger.PITCH_FOR * RAM_DOWN)


## A drunk's walk moved his gait on from `was` (Enemy.advance): each
## LURCH_GAIT of it he lurches across his way (the side his weave leans).
static func lurch(e: Enemy, game: GameWorld, was: float) -> void:
	if not ON or LURCH_GAIT <= 0.0 or not Stagger.can(e) or Stagger.reeling(e):
		return
	var n := floori(e.gait / LURCH_GAIT)
	if n <= floori(was / LURCH_GAIT):
		return
	var big := (n + e.uid) % maxi(1, LURCH_BIG) == 0
	var lean := Variants.wobble(e)
	var side := 1.0 if lean > 0.0 or (lean == 0.0 and n % 2 == 0) else -1.0
	var across := Vector2.from_angle(e.angle + side * PI * .5)
	var by := LURCH * (LURCH_BIG_K if big else 1.0)
	Stagger.point = Vector3.INF
	Stagger.shove(e, game, across.x * by, across.y * by)


## The note's word for the looks: [mode, point] while it lasts (empty none).
static func of(e: Enemy, clock: float) -> Array:
	var n: Array = e.get_note(KEY, [])
	if n.size() != SIZE:
		return []
	var until: float = n[UNTIL]
	return n if clock < until else []


## The point a hand holds on to now (Vector3.INF none).
static func holding(e: Enemy, clock: float) -> Vector3:
	var n := of(e, clock)
	if n.is_empty():
		return Vector3.INF
	var mode: int = n[MODE]
	if mode != HOLDING:
		return Vector3.INF
	var x: float = n[X]
	var y: float = n[Y]
	var z: float = n[Z]
	return Vector3(x, y, z)


## Each tick (Enemy.tick): the note let go once it is over.
static func tick(e: Enemy, game: GameWorld) -> void:
	var n: Array = e.get_note(KEY, [])
	var until := -INF
	if n.size() == SIZE:
		until = n[UNTIL]
	if game.clock >= until:
		var notes := e.notes.duplicate()
		notes.erase(KEY)
		e.notes = notes


static func _note(e: Enemy, n: Array) -> void:
	var notes := e.notes.duplicate()
	notes[KEY] = n
	e.notes = notes
