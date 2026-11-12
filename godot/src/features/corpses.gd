## Bodies fall where the shot throws them: a kill knocks the body back along
## the shot by the gun's weight (a load of buckshot more than a revolver round,
## a bowling ball more than either), a blast throws it, and it slides down
## slopes, drops off ledges and fetches up against walls, never through them
## (tumble.gd). The body's place is the enemy's own x and y, saved as ever; how
## it moves is only arithmetic on the hit, no dice, so play stays the same.
extends GameFeature

## The knock of each gun or shot (hurt()'s `how`), units a second, and what a
## blast or a heavy pile of pellets adds for each point of damage in the hit.
const KNOCK := {
	"shotgun": 1.6,
	"revolver": 1.3,
	"rifle": 1.8,
	"riveter": 1.6,
	"crowbar": 1.2,
	"slingblade": 1.5,
	"bowling": 3.6,
	"blade": 1.0,
	"ripsaw": .5,
	"pressure_gun": 2.8,
	"teat_gun": .4,
	"energy": 1.4,
	"blast": 2.0,
}
const PER_POINT := {"shotgun": .03, "blast": .012}
## Bodies moving at once; the slowest settle first when more fall.
const MOVING_MAX := 24


class Body:
	extends Tumble.Body
	var enemy: Enemy


var moving: Array = []
## Each body seen down, and the moment it died (one brought back and killed
## again is knocked again).
var _known := {}
var _feel := Tumble.Feel.new(.24, .12, .2, 2.6)
## A row of bodies landing at once is one thud, not one each.
var _thud_next := 0.0


func id() -> String:
	return "corpses"


func attach() -> void:
	_feel.climb = .1
	_feel.pull = 1.0
	_feel.hard = 1.6
	game.ticked.connect(_tick)


## The body of a kill this tick, set moving by the hit.
func _fallen(e: Enemy) -> void:
	_known[e] = e.died_at
	# A boss's fall is its own moment (enemies.gd _boss_falls): it stays where it fell.
	if _still(e):
		return
	var how := e.killed_by
	var speed := float(KNOCK.get(how, .8)) + float(PER_POINT.get(how, 0.0)) * e.struck_sum
	speed = minf(speed, 4.5)
	var away := Vector2(e.x, e.y) - e.killed_from
	if away.length() < .01:
		return
	away = away.normalized()
	_push(e, away.x * speed, away.y * speed, minf(1.6, speed * .3))


func _still(e: Enemy) -> bool:
	return (
		e.explosive or Enemy.BOSS_TITLES.has(e.kind) or e.brain in ["saucer", "skeeter", "bessie"]
	)


func _push(e: Enemy, vx: float, vy: float, vz: float) -> void:
	var body: Body = null
	for b: Body in moving:
		if b.enemy == e:
			body = b
			break
	if body == null:
		body = Body.new()
		body.enemy = e
		body.x = e.x
		body.y = e.y
		body.z = game.world.elevation(e.x, e.y) + e.toss
		moving.append(body)
		if moving.size() > MOVING_MAX:
			_settle(moving[0])
			moving.pop_front()
	body.vx += vx
	body.vy += vy
	body.vz = maxf(body.vz, vz)
	body.rest = false


## A blast throws every body near it (game_combat.gd explode()).
func shove(x: float, y: float, reach: float, power: float) -> void:
	for e: Enemy in game.enemies:
		if e.alive or e.dormant or e.died_at < 0.0 or _still(e):
			continue
		if absf(e.x - x) > reach or absf(e.y - y) > reach:
			continue
		var push := Tumble.shove(x, y, reach, power, e.x, e.y)
		if push != Vector3.ZERO and game.world.visible(x, y, e.x, e.y):
			_known[e] = e.died_at
			_push(e, push.x, push.y, push.z)


func _settle(b: Body) -> void:
	b.rest = true


func _tick(dt: float) -> void:
	for e: Enemy in game.enemies:
		if e.died_at >= 0.0 and not e.alive and float(_known.get(e, -1.0)) != e.died_at:
			_fallen(e)
	if moving.is_empty():
		return
	var still: Array = []
	for b: Body in moving:
		var e := b.enemy
		# Two smaller steps a tick: a fast body never skips a thin wall.
		for _k in 2:
			var hit := Tumble.step(game.world, b, _feel, dt * .5)
			if hit & (Tumble.WALL | Tumble.FLOOR) and game.clock >= _thud_next:
				_thud_next = game.clock + .12
				game.sound_at("body_thud", b.x, b.y, .7)
			if hit & Tumble.RESTED:
				b.rest = true
				break
		e.x = b.x
		e.y = b.y
		# Its height over the ground: thrown, or lying on a counter it landed on.
		e.toss = maxf(0.0, b.z - game.world.elevation(b.x, b.y))
		if b.rest:
			_settle(b)
			still.append(b)
	for b: Body in still:
		moving.erase(b)
