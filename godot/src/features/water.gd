## Rings on the water, all looks (the display shader draws them on the floors
## effects.cfg [water] names, and on puddles in the rain): the player's and
## every hand's strides as they wade, a splash where one steps in, drips off
## anybody standing in it, a wake behind a swimming gator and two behind the
## swamp king's airboat, and a big ring where a blast goes off in the water.
## Its own dice; nothing to save (a ring lasts a second and a half).
extends GameFeature

## A ring: [x, y, born (game.clock), size]. The shader takes MAX_SHOWN of
## the nearest; LIFE seconds each.
const MAX_RINGS := 32
const MAX_SHOWN := 16
const LIFE := 1.6
## How far a wading body goes between strides' rings, and a wake's rings.
const STRIDE := .45
const WAKE := .3

var dice := RandomNumberGenerator.new()
var rings: Array = []
## Per body (the player is key 0, an enemy its instance id): [x, y, travelled
## since its last ring, wet last tick, next drip].
var _bodies := {}


func id() -> String:
	return "water"


func attach() -> void:
	dice.seed = hash(game.level.id) + 77
	game.ticked.connect(_tick)
	game.exploded.connect(_blast)


## Water at the point: a floor [water] names, or a puddle-floor under the sky
## while the ground is wet enough to hold puddles.
func wet_at(x: float, y: float) -> bool:
	var world: LevelData = game.world
	if x < 0.0 or y < 0.0 or x >= world.width or y >= world.height:
		return false
	var i := world.cell(x, y)
	var tile := int(world.floor_tile[i])
	if tile < 0 or tile >= world.tile_names.size():
		return false
	var name := String(world.tile_names[tile])
	if Effects.WATER.has(name):
		return true
	if not Effects.PUDDLES.has(name):
		return false
	var weather = game.features.get("weather")
	var open: bool = world.roof[i] <= world.ground[i] + .01
	return weather != null and weather.wet > .35 and open


## The nearest live rings, at most MAX_SHOWN: [x, y, age, size].
func shown(px: float, py: float) -> Array:
	var near: Array = []
	for r: Array in rings:
		var age: float = game.clock - float(r[2])
		if age >= 0.0 and age < LIFE:
			var dx := float(r[0]) - px
			var dy := float(r[1]) - py
			near.append([dx * dx + dy * dy, [r[0], r[1], age, r[3]]])
	near.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var out: Array = []
	for i in mini(MAX_SHOWN, near.size()):
		out.append(near[i][1])
	return out


func ring(x: float, y: float, size: float) -> void:
	rings.append([x, y, game.clock, size])
	if rings.size() > MAX_RINGS:
		rings.pop_front()


func _tick(_dt: float) -> void:
	while not rings.is_empty() and game.clock - float(rings[0][2]) >= LIFE:
		rings.pop_front()
	var p = game.player
	var seen := {}
	if p.air <= .05:
		_wade(0, p.x, p.y, 1.0, false)
	seen[0] = true
	for e: Enemy in game.enemies:
		if not e.alive or absf(e.x - p.x) > 16.0 or absf(e.y - p.y) > 16.0:
			continue
		var key := e.get_instance_id()
		seen[key] = true
		if e.brain == "swamp_king":
			_wake(key, e, 1.5, .55)
		elif e.swims:
			_wake(key, e, .8, 0.0)
		else:
			_wade(key, e.x, e.y, clampf(e.radius / .3, .7, 1.4), true)
	for key in _bodies.keys():
		if not seen.has(key):
			_bodies.erase(key)


## A wading body: a ring each stride, a splash stepping in, drips standing.
func _wade(key: int, x: float, y: float, size: float, enemy: bool) -> void:
	var wet := wet_at(x, y)
	var b: Array = _bodies.get(key, [x, y, 0.0, wet, game.clock + 1.0])
	var moved := Vector2(x - float(b[0]), y - float(b[1])).length()
	if wet:
		if not bool(b[3]) and moved > 0.0:
			ring(x, y, size * 1.6)
			game.sound_at("wade_splash", x, y, .45 if enemy else .7)
			b[2] = 0.0
		elif moved > .001:
			b[2] = float(b[2]) + moved
			if float(b[2]) >= STRIDE:
				b[2] = 0.0
				ring(x, y, size)
		elif game.clock >= float(b[4]):
			var a := dice.randf_range(0.0, TAU)
			var off := dice.randf_range(.08, .22)
			ring(x + cos(a) * off, y + sin(a) * off, size * .4)
			if not enemy:
				game.sound.play("drip_small", .35)
			b[4] = game.clock + dice.randf_range(.6, 1.6) * (1.3 if enemy else 1.0)
	b[0] = x
	b[1] = y
	b[3] = wet
	_bodies[key] = b


## A body that swims: rings dropped behind it as it goes, two to the sides
## behind a boat (`spread`), which spread into a wake.
func _wake(key: int, e: Enemy, size: float, spread: float) -> void:
	var b: Array = _bodies.get(key, [e.x, e.y, 0.0, false, 0.0])
	var moved := Vector2(e.x - float(b[0]), e.y - float(b[1])).length()
	b[2] = float(b[2]) + moved
	if b[2] >= WAKE and wet_at(e.x, e.y):
		b[2] = 0.0
		var back := Vector2(-cos(e.angle), -sin(e.angle))
		var at := Vector2(e.x, e.y) + back * (.7 if spread > 0.0 else .35)
		if spread > 0.0:
			var across := Vector2(-back.y, back.x) * spread
			ring(at.x + across.x, at.y + across.y, size * .7)
			ring(at.x - across.x, at.y - across.y, size * .7)
		ring(at.x, at.y, size)
	b[0] = e.x
	b[1] = e.y
	_bodies[key] = b


func _blast(x: float, y: float, _z: float, _energy: bool) -> void:
	if wet_at(x, y):
		ring(x, y, 2.6)
		ring(x + .3, y - .2, 1.5)
