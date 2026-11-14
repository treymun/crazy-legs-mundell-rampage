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


class Body:
	extends Tumble.Body
	var enemy: Enemy
	var feel: Tumble.Feel
	## Whether it breaks a window or fence it is thrown into, and moos landing.
	var crash := false
	var moo := false


var moving: Array = []
## Bodies at rest in water: [enemy, its phase, next ring].
var floating: Array = []
## Each body seen down, and the moment it died (one brought back and killed
## again is knocked again).
var _known := {}
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
	game.ticked.connect(_tick)


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


## How the killing blow throws it: [run, lift] along the shot, by the gun.
func _throw(e: Enemy) -> void:
	var how := e.killed_by
	var from := e.killed_from
	var speed := float(KNOCK.get(how, .8)) + float(PER_POINT.get(how, 0.0)) * e.struck_sum
	speed = minf(speed, 4.5)
	var lift := minf(1.6, speed * .3)
	var feel := _feel
	var crash := false
	var moo := false
	if how == "shotgun" and Vector2(e.x, e.y).distance_to(from) < POINT_BLANK:
		speed = minf(POINT_BLANK_MOST, POINT_BLANK_KNOCK + POINT_BLANK_PER * e.struck_sum)
		lift = 1.5
		crash = true
	elif how == "blast" or how == "energy":
		if e.blast_at != Vector2.INF:
			from = e.blast_at
		if e.killed_with == "cow":
			speed = COW_RUN
			lift = COW_LIFT
			moo = true
		else:
			speed = BLAST_RUN + float(PER_POINT["blast"]) * e.struck_sum
			lift = BLAST_LIFT
		feel = _flung
		crash = true
	elif how == "teat_gun":
		feel = _slick
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
	body.feel = feel
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
		body.feel = _feel
		body.x = e.x
		body.y = e.y
		body.z = game.world.stand(e) + e.toss
		moving.append(body)
		if moving.size() > MOVING_MAX:
			_settle(moving[0])
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
		if e.died_at == game.clock and float(_known.get(e, -1.0)) != e.died_at:
			continue
		if absf(e.x - x) > reach or absf(e.y - y) > reach:
			continue
		var push := Tumble.shove(x, y, reach, power, e.x, e.y)
		if push != Vector3.ZERO and game.world.visible(x, y, e.x, e.y):
			_known[e] = e.died_at
			_push(e, push.x, push.y, push.z)


func _settle(b: Body) -> void:
	b.rest = true
	game.gore_fx.settled(b.enemy)  # its pool spreads where it lies


func _tick(dt: float) -> void:
	for e: Enemy in game.enemies:
		if e.died_at >= 0.0 and not e.alive and float(_known.get(e, -1.0)) != e.died_at:
			_fallen(e)
	if not moving.is_empty():
		_move(dt)
	if game.clock >= _look_next:
		_look_next = game.clock + FLOAT_LOOK
		_look_for_floaters()
	if not floating.is_empty():
		_bob()


func _move(dt: float) -> void:
	var still: Array = []
	var breaks = game.features.get("wall_breaks")
	for b: Body in moving:
		var e := b.enemy
		# Two smaller steps a tick: a fast body never skips a thin wall.
		for _k in 2:
			var vx := b.vx
			var vy := b.vy
			var air: bool = b.z > game.world.floor_under(b.x, b.y, b.z + .05) + .02
			var hit := Tumble.step(game.world, b, b.feel, dt * .5)
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
			if b.moo and air and hit & Tumble.FLOOR:
				b.moo = false
				game.sound_at("cow_moo", b.x, b.y, .8)
			if hit & Tumble.RESTED:
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


## Bodies lying still in water (shallow or deep) start to float.
func _look_for_floaters() -> void:
	var busy := {}
	for b: Body in moving:
		busy[b.enemy] = true
	for e: Enemy in game.enemies:
		if e.alive or e.dormant or e.explosive or _floats.has(e) or busy.has(e) or _still(e):
			continue
		if BayouBrains.wet_at(game.world, e.x, e.y):
			_floats[e] = true
			floating.append([e, fmod(e.x * 1.7 + e.y * 2.3, TAU), game.clock])


## The nearest floating bodies bob on the water and now and then leave a ring.
func _bob() -> void:
	var water = game.features.get("water")
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
		e.toss = BOB * (1.0 + sin(game.clock * BOB_SPEED + float(f[1])))
		# The ring's clock is carried play: kept on a server's game too, which
		# has no water feature (looks only) to draw the ring.
		if game.clock >= float(f[2]):
			f[2] = game.clock + RING_EVERY
			if water != null:
				water.ring(e.x, e.y, .7)
