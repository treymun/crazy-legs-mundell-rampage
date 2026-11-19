## Bodies fall the way the killing blow throws them: a kill knocks the body
## back along the shot by the gun's weight (KNOCK), and the gun shapes it
## (`_throw`): a load of buckshot at arm's length throws a body back hard
## enough to shatter the window it hits or break through a plank fence
## (features/wall_breaks.gd crash()); a blast that only just finishes one
## throws it whole in a high arc, the cow launcher higher still and it lands
## with a moo; a rifle round drops it where it stood, a crowbar or a sling
## blade crumples it; the teat gun's milk slides it a long way. It slides down
## slopes, drops off ledges and fetches up against walls, never through them
## (tumble.gd), and a body that comes to rest in water floats and bobs there.
## The body's place is the enemy's own x and y, saved as ever; how it moves is
## only arithmetic on the hit, no dice, so play stays the same.
extends GameFeature

const WallBreaks := preload("res://src/features/wall_breaks.gd")
const Water := preload("res://src/features/water.gd")

## The knock of each gun or shot (hurt()'s `how`), units a second, and what a
## blast or a heavy pile of pellets adds for each point of damage in the hit.
const KNOCK := {
	"shotgun": 1.6,
	"revolver": 1.3,
	"rifle": .25,
	"hunter": 2.2,
	"mower": .4,
	"county45": 1.2,
	"star357": 1.6,
	"hogleg": 1.7,
	"riot_pump": 1.6,
	"tommy": .4,
	"grease_gun": .4,
	"patrol_bar": .45,
	"marksman": 1.8,
	"riveter": 1.6,
	"crowbar": .18,
	"slingblade": .22,
	"bowling": 3.6,
	"blade": 1.0,
	"ripsaw": .5,
	"pressure_gun": 2.8,
	"teat_gun": 2.4,
	"energy": 1.4,
	"blast": 2.0,
	"kick": 3.2,
	"kick_finish": 4.6,
}
const PER_POINT := {"shotgun": .03, "blast": .012}
## Buckshot this near (cells) throws a body hard: from POINT_BLANK_KNOCK up by
## POINT_BLANK_PER a point of the load, at most POINT_BLANK_MOST.
const POINT_BLANK := 2.4
const POINT_BLANK_KNOCK := 3.4
const POINT_BLANK_PER := .045
const POINT_BLANK_MOST := 7.5
## A body thrown faster than this into a wall breaks what it can there
## (wall_breaks.gd crash()), taking CRASH_DAMAGE a unit of its speed from a fence.
const CRASH_SPEED := 2.6
const CRASH_DAMAGE := 22.0
## A blast that throws a body whole: its run and lift; the cow launcher's.
const BLAST_RUN := 3.2
const BLAST_LIFT := 3.4
const COW_RUN := 3.6
const COW_LIFT := 6.4
## A rail stops a body (as tall as RAIL_TALL lying low and thrown) unless it
## comes faster than OVER_SPEED and the rail's top is under OVER_TOP over the
## body: then it tips over, keeping OVER_KEEP of its run and lifted OVER_LIFT.
const RAIL_TALL := 1.0
const OVER_SPEED := 2.2
const OVER_TOP := 1.1
const OVER_KEEP := .6
const OVER_LIFT := 1.2
## A body resting with its middle over a drop of more than EDGE_DROP slides
## off the lip that holds it at EDGE_PUSH.
const EDGE_DROP := .3
const EDGE_PUSH := .9
const EDGE_TRIES := 8
## Bodies moving at once; the slowest settle first when more fall.
const MOVING_MAX := 24
## A body floating: how high it bobs and how fast, the rings it leaves.
const BOB := .045
const BOB_SPEED := 2.1
const RING_EVERY := 1.4
## Floating bodies bobbed at once (the nearest), and how often new ones are
## looked for (a body loaded from a save lies where it was).
const FLOAT_MAX := 12
const FLOAT_LOOK := 1.0
## How much a floating body's drift on the current (Water.current) speeds
## up and slows down, and turns (radians either way), by its phase.
const DRIFT_SWAY := .35
const DRIFT_TURN := .5

## How a body moves (Body.how): the feature's _feel, _slick or _flung.
enum { PLAIN, SLICK, FLUNG }


class Body:
	extends Tumble.Body
	var enemy: Enemy
	## Which of the feature's feels moves it (PLAIN, SLICK, FLUNG), by name and
	## never the Feel itself: a snapshot carries objects by value, and a copy
	## put back on one would fill a feel the bodies share with another's.
	var how := PLAIN
	## Whether it breaks a window or fence it is thrown into, and moos landing.
	var crash := false
	var moo := false
	## Times it has been pushed off a lip (_off_edge).
	var slid := 0


var moving: Array = []
## Bodies at rest in water: [enemy, its phase, next ring].
var floating: Array = []
## Each body seen down, and the moment it died (one brought back and killed
## again is knocked again).
var _known := {}
## The game's enemies when _known was last pruned of the gone (never carried).
var _counted := -1
var _floats := {}
var _feel := Tumble.Feel.new(.24, .12, .2, 2.6)
## The teat gun's milk: a body slides a long way on it.
var _slick := Tumble.Feel.new(.24, .2, .15, .55)
## A body thrown up high (a blast, the cow) bounces a little on landing.
var _flung := Tumble.Feel.new(.24, .18, .28, 2.2)
## A row of bodies landing at once is one thud, not one each.
var _thud_next := 0.0
var _look_next := 0.0
var _crashes := 0


func id() -> String:
	return "corpses"


func attach() -> void:
	for feel: Tumble.Feel in [_feel, _slick, _flung]:
		feel.climb = .1
		feel.pull = 1.0
		feel.hard = 1.6
	_slick.pull = 1.2
	tick_with(_tick)


## How many windows and fences bodies have been thrown into (tools read it).
func crashes() -> int:
	return _crashes


## The body of a kill this tick, set moving by the hit.
func _fallen(e: Enemy) -> void:
	_known[e] = e.died_at
	# A boss's fall is its own moment (enemies.gd _boss_falls): it stays where it fell.
	if _still(e):
		return
	_throw(e)
	# Down in the water where it stood: a splash (looks, if any).
	Water.splash_if(game, e.x, e.y, game.world.stand(e), 1.4)


## How the killing blow throws it: [run, lift] along the shot, by the gun.
func _throw(e: Enemy) -> void:
	var how := e.killed_by
	var from := e.killed_from
	var knock: float = KNOCK.get(how, .8)
	var per_point: float = PER_POINT.get(how, 0.0)
	var speed := knock + per_point * e.struck_sum
	speed = minf(speed, 4.5)
	var lift := minf(1.6, speed * .3)
	var moves := PLAIN
	var crash := false
	var moo := false
	if how == "shotgun" and Vector2(e.x, e.y).distance_to(from) < POINT_BLANK:
		speed = minf(POINT_BLANK_MOST, POINT_BLANK_KNOCK + POINT_BLANK_PER * e.struck_sum)
		lift = 1.5
		crash = true
	elif how == "blast" or how == "energy" or how == "roadkill":
		# (roadkill: run down by a vehicle, features/vehicles.gd; blast_at is
		# set behind the body along the vehicle's way.)
		if e.blast_at != Vector2.INF:
			from = e.blast_at
		if e.killed_with == "cow":
			speed = COW_RUN
			lift = COW_LIFT
			moo = true
		else:
			speed = BLAST_RUN + float(PER_POINT["blast"]) * e.struck_sum
			lift = BLAST_LIFT
		moves = FLUNG
		crash = true
	elif how == "kick" or how == "kick_finish":
		# A boot (features/brawl.gd): back hard along it, into what is there.
		crash = true
		lift = 1.0 if how == "kick" else 1.6
	elif how == "teat_gun":
		moves = SLICK
		lift = 0.0
	elif how in ["rifle", "mower", "tommy", "grease_gun", "patrol_bar", "crowbar", "slingblade"]:
		lift = 0.0
	var away := Vector2(e.x, e.y) - from
	if away.length() < .01:
		away = Vector2(cos(e.angle + PI), sin(e.angle + PI)) * .02
		if lift <= 0.0:
			return
	away = away.normalized()
	var body := _push(e, away.x * speed, away.y * speed, lift)
	body.how = moves
	body.crash = crash
	body.moo = moo


func _still(e: Enemy) -> bool:
	return (
		e.explosive or Enemy.BOSS_TITLES.has(e.kind) or e.brain in ["saucer", "skeeter", "bessie"]
	)


func _push(e: Enemy, vx: float, vy: float, vz: float) -> Body:
	var body: Body = null
	for b: Body in moving:
		if b.enemy == e:
			body = b
			break
	if body == null:
		body = Body.new()
		body.enemy = e
		body.how = PLAIN
		body.x = e.x
		body.y = e.y
		body.z = game.world.stand(e) + e.toss
		moving.append(body)
		if moving.size() > MOVING_MAX:
			var oldest: Body = moving[0]
			_settle(oldest)
			moving.pop_front()
	body.vx += vx
	body.vy += vy
	body.vz = maxf(body.vz, vz)
	body.rest = false
	return body


## A blast throws every body near it (game_combat.gd explode()). One it has
## just killed is thrown by _throw() on the next tick instead, from the
## blast's middle (Enemy.blast_at).
func shove(x: float, y: float, reach: float, power: float) -> void:
	for e: Enemy in game.enemies:
		if e.alive or e.dormant or e.died_at < 0.0 or _still(e):
			continue
		var known_at: float = _known.get(e, -1.0)
		if e.died_at == game.clock and known_at != e.died_at:
			continue
		if absf(e.x - x) > reach or absf(e.y - y) > reach:
			continue
		var push := Tumble.shove(x, y, reach, power, e.x, e.y)
		if push != Vector3.ZERO and game.world.visible(x, y, e.x, e.y):
			_known[e] = e.died_at
			_push(e, push.x, push.y, push.z)


## The bodies a game no longer has (County Run clears the dead from its
## list): kept, they held every enemy ever killed, and a snapshot names an
## enemy by its uid, so a copy put back on one could not find them and
## parted at every check after (pass 12 soak: 39 against 37).
func _forget_gone() -> void:
	var here := {}
	for e: Enemy in game.enemies:
		here[e] = true
	for e: Enemy in _known.keys():
		if not here.has(e):
			_known.erase(e)


func feel_of(b: Body) -> Tumble.Feel:
	return _slick if b.how == SLICK else _flung if b.how == FLUNG else _feel


func _settle(b: Body) -> void:
	b.rest = true
	game.gore_fx.settled(b.enemy)  # its pool spreads where it lies


func _tick(dt: float) -> void:
	if game.enemies.size() != _counted:
		_counted = game.enemies.size()
		_forget_gone()
	for e: Enemy in game.enemies:
		if e.died_at >= 0.0 and not e.alive:
			var known_at: float = _known.get(e, -1.0)
			if known_at != e.died_at:
				_fallen(e)
	if not moving.is_empty():
		_move(dt)
	if game.clock >= _look_next:
		_look_next = game.clock + FLOAT_LOOK
		_look_for_floaters()
		_look_for_unheld()
	if not floating.is_empty():
		_bob(dt)


func _move(dt: float) -> void:
	var still: Array = []
	var breaks: WallBreaks = game.features.get("wall_breaks")
	for b: Body in moving:
		var e := b.enemy
		# Two smaller steps a tick: a fast body never skips a thin wall.
		for _k in 2:
			var vx := b.vx
			var vy := b.vy
			var fall := b.vz
			var air: bool = b.z > game.world.floor_under(b.x, b.y, b.z + .05) + .02
			_rails(b, dt * .5)
			var hit := Tumble.step(game.world, b, feel_of(b), dt * .5)
			if hit & Tumble.WALL and b.crash and breaks != null:
				var run := Vector2(vx, vy).length()
				if run > CRASH_SPEED:
					var dir := Vector2(vx, vy) / run
					var did: int = breaks.crash(
						b.x, b.y, b.z + .9, dir.x, dir.y, run * CRASH_DAMAGE
					)
					if did != breaks.NONE:
						_crashes += 1
					if did == breaks.OPENED:
						# Through the fence it broke: on it goes, slowed.
						b.vx = vx * .6
						b.vy = vy * .6
			if hit & (Tumble.WALL | Tumble.FLOOR) and game.clock >= _thud_next:
				_thud_next = game.clock + .12
				game.sound_at("body_thud", b.x, b.y, .7)
			# Come down in water: a splash (looks; the water feature's, if any).
			if air and b.vz <= 0.0 and b.z <= game.world.floor_under(b.x, b.y, b.z + .05) + .02:
				Water.splash_if(game, b.x, b.y, b.z, clampf(1.0 + absf(fall) * .4, 1.2, 2.4))
			if b.moo and air and hit & Tumble.FLOOR:
				b.moo = false
				game.sound_at("cow_moo", b.x, b.y, .8)
			if hit & Tumble.RESTED:
				if _off_edge(b):
					continue
				b.rest = true
				break
		e.x = b.x
		e.y = b.y
		# Its height over the ground: thrown, or lying on a counter it landed on.
		e.toss = maxf(0.0, b.z - game.world.floor_under(b.x, b.y, b.z + .05))
		if b.rest:
			_settle(b)
			still.append(b)
	for b: Body in still:
		moving.erase(b)
		if _floats.has(b.enemy):
			# Thrown again: it floats again wherever it comes to rest.
			_floats.erase(b.enemy)
			floating = floating.filter(func(f: Array) -> bool: return f[0] != b.enemy)


## A body come to rest with its middle over a drop (held up only by the lip
## of a deck, a stair or a walkway past a rail) slides off it: it is given a
## push away from what holds it. True when it was pushed.
func _off_edge(b: Body) -> bool:
	var world := game.world
	var r := feel_of(b).radius
	if b.slid >= EDGE_TRIES or world.floor_under(b.x, b.y, b.z + .05) >= b.z - EDGE_DROP:
		return false
	var away := Vector2.ZERO
	for k in 4:
		var corner := Vector2(r if k & 1 else -r, r if k & 2 else -r)
		if Tumble.floor_at(world, b.x + corner.x, b.y + corner.y, b.z) < b.z - EDGE_DROP:
			away += corner
	if away == Vector2.ZERO:
		return false
	b.slid += 1
	away = away.normalized() * EDGE_PUSH
	b.vx = away.x
	b.vy = away.y
	b.vz = -.01
	return true


## A rail (a free wall that lets sight by: tumble.gd lets loose things
## through) stops a body thrown into it, unless it comes fast enough and the
## rail is low enough to tip it over head first: then on it goes, slowed and
## lifted, over the edge of a loft or a walkway.
func _rails(b: Body, h: float) -> void:
	var world := game.world
	if world.geo == null or world.geo.clear_at(b.x, b.y):
		return
	var nx := b.x + b.vx * h
	var ny := b.y + b.vy * h
	for item: Variant in world.geo.near_items(b.x, b.y):
		if not (item is LevelGeometry.Segment):
			continue
		var s: LevelGeometry.Segment = item
		if s.sight or s.z0 >= b.z + RAIL_TALL or s.z1 <= b.z:
			continue
		var reach := feel_of(b).radius + s.half
		if s.dist2(nx, ny) >= reach * reach or s.dist2(b.x, b.y) < reach * reach:
			continue
		var run := Vector2(b.vx, b.vy)
		if run.length() > OVER_SPEED and s.z1 - b.z < OVER_TOP:
			b.vx *= OVER_KEEP
			b.vy *= OVER_KEEP
			b.vz = maxf(b.vz, OVER_LIFT)
			return
		var along := Vector2(s.bx - s.ax, s.by - s.ay).normalized()
		var n := Vector2(-along.y, along.x)
		if n.dot(Vector2(b.x - s.ax, b.y - s.ay)) < 0.0:
			n = -n
		var into := run.dot(n)
		if into < 0.0:
			run -= n * into * (1.0 + feel_of(b).wall)
			b.vx = run.x
			b.vy = run.y
		return


## A body lying up on something (a crate, a counter top) that has since been
## broken away falls again, rather than lying on air.
func _look_for_unheld() -> void:
	for e: Enemy in game.enemies:
		if e.alive or e.dormant or e.toss <= .02 or _floats.has(e) or _still(e):
			continue
		var lying := false
		for b: Body in moving:
			lying = lying or b.enemy == e
		if lying:
			continue
		var z: float = game.world.stand(e) + e.toss
		if Tumble.floor_at(game.world, e.x, e.y, z, _feel.radius) < z - .03:
			_push(e, 0.0, 0.0, 0.0)


## Bodies lying still in water (shallow or deep) start to float.
func _look_for_floaters() -> void:
	var busy := {}
	for b: Body in moving:
		busy[b.enemy] = true
	# Already afloat: by the carried list itself (a copy rebuilt from a
	# snapshot gets `floating` but not the `_floats` set keyed by enemies, and
	# a body listed twice would drift twice as fast there).
	for f: Array in floating:
		busy[f[0]] = true
	for e: Enemy in game.enemies:
		if e.alive or e.dormant or e.explosive or _floats.has(e) or busy.has(e) or _still(e):
			continue
		if BayouBrains.wet_at(game.world, e.x, e.y):
			_floats[e] = true
			floating.append([e, fmod(e.x * 1.7 + e.y * 2.3, TAU), game.clock])


## A floating body goes slowly with the level's current (Water.current), a
## little faster and slower by its phase and turning a touch, never out of
## the water nor into a wall or the bank (it waits there). Arithmetic only:
## the same on every machine.
func _drift(e: Enemy, phase: float, dt: float) -> void:
	var flow := Water.current(game.level.id)
	if flow == Vector2.ZERO:
		return
	var sway := 1.0 + DRIFT_SWAY * sin(game.clock * .37 + phase)
	var way := flow.rotated(DRIFT_TURN * sin(game.clock * .23 + phase * 1.3)) * sway * dt
	var world := game.world
	var r := _feel.radius
	var to := Vector2(e.x + way.x, e.y + way.y)
	if not BayouBrains.wet_at(world, to.x + signf(way.x) * r, to.y + signf(way.y) * r):
		return
	if world.blocked(to.x, to.y, r, world.stand(e) + .2):
		return
	e.x = to.x
	e.y = to.y


## The nearest floating bodies bob on the water and now and then leave a ring.
func _bob(dt: float) -> void:
	var water: Water = game.features.get("water")
	var shown := 0
	for f: Array in floating:
		var e: Enemy = f[0]
		if e.alive:
			continue
		# Near any player (a body's height is carried play, the same on every
		# machine, not just the local player's surroundings).
		var near := false
		for p: Player in game.players:
			if absf(e.x - p.x) <= 14.0 and absf(e.y - p.y) <= 14.0:
				near = true
				break
		if not near or shown >= FLOAT_MAX:
			continue
		shown += 1
		var bob_phase: float = f[1]
		e.toss = BOB * (1.0 + sin(game.clock * BOB_SPEED + bob_phase))
		_drift(e, bob_phase, dt)
		# The ring's clock is carried play: kept on a server's game too, which
		# has no water feature (looks only) to draw the ring.
		var ring_at: float = f[2]
		if game.clock >= ring_at:
			f[2] = game.clock + RING_EVERY
			if water != null:
				water.ring(e.x, e.y, .7)
