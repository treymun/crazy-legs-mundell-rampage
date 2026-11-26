## A living hand knocked off balance by a hit (pass 15, PUNCH): play's half
## of the active bodies. The hit is an impulse on his middle (the shove a gun
## gives, hits.cfg [reaction] and the reel, made a speed: the old shoves were
## an instant jump); he is then an inverted pendulum on the foot he stands on
## (the centre of mass a height up, gravity, the foot's grip): the ankle holds
## a small push where it is (the centre of pressure moves within ANKLE of the
## foot), a bigger one makes him step, each catch step put down where the
## capture point is when the swing ends (the point where a foot stops the
## fall: the middle plus its speed over the pendulum's rate), no further than
## his reach (less on a buckled knee, a leg hit). He stays up if the steps
## catch it; when they cannot (STEPS_MOST steps and still going, or a catch
## further than his reach can ever give), he goes down: onto a knee on a
## buckled leg, else pitched over onto his hands and knees, and gets up.
## A man hit on the run keeps RUN_KEEP of his run. Hits while reeling add to
## the speed (staggers stack). Walls stop the middle (move_actor).
##
## Play, carried: one note on the enemy (`KEY`, Enemy.notes: carried online
## and saved like any field, so an older peer or save just holds no note),
## arithmetic only, no dice (game.rng is not touched, so everything else plays
## as before). Stunned while it lasts (he neither walks nor shoots). The 3D
## view's LiveBody (src/live_body.gd) reads the note for the limbs' own
## physics (the hit's way and height, down or not); it never writes play.
## Off (hits.cfg [punch] stagger=false, `ON`) the shoves are the old jumps.
class_name Stagger
extends RefCounted

const KEY := "stagger"
## The note's slots.
const PX := 0
const PY := 1
const VX := 2
const VY := 3
const SWING := 4
const STEPS := 5
const DOWN := 6
const BUCKLE := 7
const JX := 8
const JY := 9
const HZ := 10
const AT := 11
const PITCH := 12
const LAT := 13
const SIZE := 14
## Gravity (cells a second squared, as the ragdolls').
const GRAVITY := 9.4

static var ON: bool = HitData.value("punch", "stagger", true)
## The middle's height (share of the body's), the foot's grip (cells the
## centre of pressure may move off the foot), a swing's seconds (the first,
## a reflex, quicker), the reach of a step from the middle (share of the
## body's height) and on a buckled knee, the steps at most, how far past his
## reach the capture point may be before no step can catch it.
static var COM_AT: float = HitData.value("punch", "com_at", .55)
static var ANKLE: float = HitData.value("punch", "ankle", .07)
static var SWING_TIME: float = HitData.value("punch", "swing", .26)
static var FIRST_SWING: float = HitData.value("punch", "first_swing", .2)
static var REACH: float = HitData.value("punch", "reach", .33)
static var FIRST_SHARE: float = HitData.value("punch", "first_share", .7)
static var BUCKLED: float = HitData.value("punch", "buckled", .55)
static var BUCKLE_TIME: float = HitData.value("punch", "buckle_time", 1.2)
static var STEPS_MOST: int = HitData.value("punch", "steps_most", 3)
static var FALL_PAST: float = HitData.value("punch", "fall_past", 1.3)
## The shove (cells) made a speed: PUSH times the pendulum's rate, so a
## shove of d puts the capture point PUSH x d off (a step there stops him);
## no faster than PUSH_MOST. A run kept, the swing of the hips damped,
## down on a knee / pitched over and getting up (seconds), settled under
## SETTLE speed, at most LONGEST seconds in all.
static var PUSH: float = HitData.value("punch", "push", .6)
static var PUSH_MOST: float = HitData.value("punch", "push_most", 3.2)
static var RUN_KEEP: float = HitData.value("punch", "run_keep", .9)
static var DAMP: float = HitData.value("punch", "damp", .4)
static var KNEE_FOR: float = HitData.value("punch", "knee_for", .55)
static var PITCH_FOR: float = HitData.value("punch", "pitch_for", .8)
static var RISE: float = HitData.value("punch", "rise", .45)
static var SETTLE: float = HitData.value("punch", "settle", .08)
static var LONGEST: float = HitData.value("punch", "longest", 3.0)
## A plain hand's girth (cells) and how much lighter or heavier a man may
## count against him.
static var HEFT_RADIUS: float = HitData.value("punch", "heft_radius", .26)
static var HEFT_RANGE: Array = HitData.value("punch", "heft_range", [.75, 2.2])
## Kinds that never stagger (they float or roll: no feet to catch on).
static var STEADY: Array = HitData.value("punch", "steady", [])
## Where the hit being taken struck (Enemy.hurt keeps game.hit_point here
## before it lets it go): its height and how far off the middle, for the looks.
static var point := Vector3.INF


## Whether `e` can be knocked off balance now (a hand on two legs, on its
## feet, not a boss: bosses have their own, BossKit.stagger).
static func can(e: Enemy) -> bool:
	return (
		ON
		and e.alive
		and e.hostile
		and HitZones.limbs(e)
		and not STEADY.has(e.kind)
		and e.ladder < 0
		and e.climb_z == 0.0
		and e.hop == 0.0
		and not e.swims
	)


## The shove of a hit (cells along `dx`, `dy`): an impulse that makes him
## reel (can()), else the old jump.
static func shove(e: Enemy, game: GameWorld, dx: float, dy: float) -> void:
	if not can(e):
		game.move_actor(e, dx, dy, e.radius)
		return
	push(e, game, Vector2(dx, dy) * rate(e) * PUSH)


## How heavy `e` is against a plain hand (his girth squared against
## HEFT_RADIUS's, within HEFT_RANGE): a push moves him that much less.
static func heft(e: Enemy) -> float:
	var r := e.radius * e.variant / HEFT_RADIUS
	var lo: float = HEFT_RANGE[0]
	var hi: float = HEFT_RANGE[1]
	return clampf(r * r, lo, hi)


## The pendulum's rate (1/s) for `e`: gravity over the middle's height, rooted.
static func rate(e: Enemy) -> float:
	return sqrt(GRAVITY / maxf(.2, COM_AT * e.height * e.variant))


## An impulse `v` (cells a second) on his middle; the zone the hit found
## (Enemy.last_zone) buckles a leg; game.hit_point's height is kept for the
## looks (the share of his height the hit landed at).
static func push(e: Enemy, game: GameWorld, v: Vector2) -> void:
	# (A copy each time: a snapshot put back on another game may share the
	# note's array with this one.)
	var held: Array = e.get_note(KEY, [])
	var s := held.duplicate()
	var fresh := s.size() != SIZE
	if fresh:
		s = []
		s.resize(SIZE)
		s.fill(0.0)
		s[PX] = e.x
		s[PY] = e.y
		s[AT] = game.clock
		if e.last_stride > 0.0 and e.pose - e.last_stride < .1:
			# On the move: he goes on with his run (his legs stop driving).
			var run := Vector2.from_angle(e.angle) * e.speed * RUN_KEEP
			s[VX] = run.x
			s[VY] = run.y
	# A heavier man is moved less by the same push.
	v /= heft(e)
	var vx: float = s[VX]
	var vy: float = s[VY]
	var now := (Vector2(vx, vy) + v).limit_length(PUSH_MOST)
	s[VX] = now.x
	s[VY] = now.y
	var jx: float = s[JX]
	var jy: float = s[JY]
	var hit_at: float = s[AT]
	# The hit's impulse (pellets of one instant summed) for the looks.
	var same := game.clock - hit_at < .06 and not fresh
	var j := (Vector2(jx, jy) if same else Vector2.ZERO) + v
	s[JX] = j.x
	s[JY] = j.y
	s[AT] = game.clock
	var hit := point
	var feet: float = game.world.stand(e) + e.z
	s[HZ] = .6
	s[LAT] = 0.0
	if hit != Vector3.INF:
		s[HZ] = clampf((hit.z - feet) / maxf(.1, e.height * e.variant), 0.0, 1.0)
		var way := v.normalized() if v.length_squared() > 1e-8 else Vector2.ZERO
		var off := Vector2(hit.x - e.x, hit.y - e.y)
		s[LAT] = clampf(way.x * off.y - way.y * off.x, -e.radius * 1.5, e.radius * 1.5)
	if e.last_zone == "legs":
		s[BUCKLE] = BUCKLE_TIME
	_keep(e, s)
	e.stun = maxf(e.stun, .05)


## One tick of the reel (Enemy.tick, before its brain): the pendulum, the
## catch steps, the fall and getting up. Keeps him stunned while it lasts.
static func tick(e: Enemy, dt: float, game: GameWorld) -> void:
	var held: Array = e.get_note(KEY, [])
	var s := held.duplicate()
	if s.size() != SIZE or dt <= 0.0:
		return
	var began: float = s[AT]
	if game.clock - began > LONGEST:
		_keep(e, [])
		return
	var down: float = s[DOWN]
	var buckle: float = s[BUCKLE]
	s[BUCKLE] = maxf(0.0, buckle - dt)
	var vx0: float = s[VX]
	var vy0: float = s[VY]
	var v := Vector2(vx0, vy0)
	if down != 0.0:
		# Down (a knee, or hands and knees) and then up: what speed is left
		# goes in the slide; up when the count runs out.
		v *= exp(-8.0 * dt)
		if v.length() < SETTLE:
			v = Vector2.ZERO
		_move(e, game, v, dt, s)
		if down > 0.0:
			down = maxf(0.0, down - dt)
			s[DOWN] = down if down > 0.0 else -RISE
		else:
			down = minf(0.0, down + dt)
			s[DOWN] = down
			if down == 0.0:
				_keep(e, [])
				return
		e.stun = maxf(e.stun, maxf(0.0, down) + (RISE if down > 0.0 else -down) + .02)
		_keep(e, s)
		return
	var w := rate(e)
	var c := Vector2(e.x, e.y)
	var px: float = s[PX]
	var py: float = s[PY]
	var p := Vector2(px, py)
	var xi := c + v / w
	# The ankle: the centre of pressure moves toward the capture point within
	# the foot; the pendulum falls away from it.
	var cop := p + (xi - p).limit_length(ANKLE)
	var a := (c - cop) * (w * w) - v * DAMP
	v += a * dt
	v = v.limit_length(PUSH_MOST * 1.5)
	_move(e, game, v, dt, s)
	c = Vector2(e.x, e.y)
	var vx1: float = s[VX]
	var vy1: float = s[VY]
	v = Vector2(vx1, vy1)
	xi = c + v / w
	var reach := REACH * e.height * e.variant * (BUCKLED if buckle > 0.0 else 1.0)
	var swing: float = s[SWING]
	var steps: float = s[STEPS]
	if swing > 0.0:
		swing -= dt
		if swing <= 0.0:
			# The foot comes down where the capture point is now, if he can
			# reach so far.
			# (A first, hurried step is shorter: a hard push takes more of them.)
			var want := xi - c
			p = c + want.limit_length(reach * (FIRST_SHARE if steps == 0.0 else 1.0))
			s[PX] = p.x
			s[PY] = p.y
			steps += 1.0
			swing = 0.0
			var left := (xi - p).length()
			if left > ANKLE and (steps >= STEPS_MOST or want.length() > reach * FALL_PAST):
				# No step catches it: down he goes, unless a hand finds
				# something to hold on to (src/body_play.gd).
				if not BodyPlay.holds_on(e, game, s, v):
					_fall(e, s, v, buckle > 0.0)
					return
	elif (xi - p).length() > ANKLE * 1.2:
		swing = FIRST_SWING if steps == 0.0 else SWING_TIME
	s[SWING] = maxf(0.0, swing)
	s[STEPS] = steps
	if swing <= 0.0 and v.length() < SETTLE and (xi - p).length() <= ANKLE * 1.2:
		_keep(e, [])
		return
	_keep(e, s)
	e.stun = maxf(e.stun, .05)


## Down: on the buckled knee, else pitched over; the speed partly spent.
static func _fall(e: Enemy, s: Array, v: Vector2, knee: bool) -> void:
	s[DOWN] = KNEE_FOR if knee else PITCH_FOR
	s[PITCH] = 0.0 if knee else 1.0
	s[SWING] = 0.0
	v *= .5
	s[VX] = v.x
	s[VY] = v.y
	_keep(e, s)
	e.stun = maxf(e.stun, KNEE_FOR + RISE if knee else PITCH_FOR + RISE)


## The middle moves by its speed; a wall takes what it stops (move_actor).
static func _move(e: Enemy, game: GameWorld, v: Vector2, dt: float, s: Array) -> void:
	var ox := e.x
	var oy := e.y
	game.move_actor(e, v.x * dt, v.y * dt, e.radius)
	var moved := Vector2(e.x - ox, e.y - oy)
	var want := v * dt
	if want.length_squared() > 1e-12 and moved.length_squared() < want.length_squared() * .98:
		# Stopped (a wall, a body): only what moved is kept as speed; a low
		# rail taken hard he goes over (src/body_play.gd).
		if BodyPlay.over_rail(e, game, v, s):
			return
		v = moved / dt
	s[VX] = v.x
	s[VY] = v.y


## The note of `e` (empty: not reeling) and what it says, for the looks and
## the checks.
static func of(e: Enemy) -> Array:
	var s: Array = e.get_note(KEY, [])
	return s if s.size() == SIZE else []


static func reeling(e: Enemy) -> bool:
	return not of(e).is_empty()


## Seconds down left (0: on his feet; negative: getting up).
static func down_of(e: Enemy) -> float:
	var s := of(e)
	if s.is_empty():
		return 0.0
	var d: float = s[DOWN]
	return d


## The note kept (empty: let go) in a dictionary of the enemy's own: a
## snapshot put on another game in the same process may hand both games the
## same notes, and a note written in place there would move the other's man.
static func _keep(e: Enemy, s: Array) -> void:
	var notes := e.notes.duplicate()
	if s.is_empty():
		notes.erase(KEY)
	else:
		notes[KEY] = s
	e.notes = notes
