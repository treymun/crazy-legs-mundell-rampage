## Rings on the water, all looks (the display shader draws them on the floors
## effects.cfg [water] names, and on puddles in the rain): the player's and
## every hand's strides as they wade, a splash where one steps in, drips off
## anybody standing in it, a wake behind a swimming gator and two behind the
## swamp king's airboat, and a big ring where a blast goes off in the water.
## Its own dice; nothing to save (a ring lasts a second and a half).
extends GameFeature

const Weather := preload("res://src/features/weather.gd")

## A ring: [x, y, born (game.clock), size]. The shader takes MAX_SHOWN of
## the nearest; LIFE seconds each.
const MAX_RINGS := 32
const MAX_SHOWN := 16
const LIFE := 1.6
## How far a wading body goes between strides' rings, and a wake's rings.
const STRIDE := .45
const WAKE := .3
## Splashes are heard no closer together than this (a burst of gibs is one).
const SPLASH_GAP := .1

var dice := RandomNumberGenerator.new()
var rings: Array = []
## Per body (the player is key 0, an enemy its instance id): [x, y, travelled
## since its last ring, wet last tick, next drip].
var _bodies := {}
## The floor tiles sorted for wet_at() (_sort_tiles), for that level and tables.
var _kinds := PackedByteArray()
var _kinds_of: LevelData = null
var _water: Dictionary = {}
var _puddles: Dictionary = {}
## Splashes made (tools count them), and when the next may be heard.
var splashes := 0
var _splash_next := 0.0


func id() -> String:
	return "water"


func attach() -> void:
	dice.seed = hash(game.level.id) + 77
	game.events.ticked.connect(_tick)
	game.events.exploded.connect(_blast)


## Water at the point: a floor [water] names, or a puddle-floor under the sky
## while the ground is wet enough to hold puddles.
func wet_at(x: float, y: float) -> bool:
	var world: LevelData = game.world
	if x < 0.0 or y < 0.0 or x >= world.width or y >= world.height:
		return false
	if not (
		is_same(_kinds_of, world)
		and is_same(_water, Effects.WATER)
		and is_same(_puddles, Effects.PUDDLES)
	):
		_sort_tiles(world)
	var i := int(y) * world.width + int(x)
	var tile := int(world.floor_tile[i])
	if tile < 0 or tile >= _kinds.size():
		return false
	var kind := _kinds[tile]
	if kind == 1:
		return true
	if kind == 0:
		return false
	var weather: Weather = game.features.get("weather")
	var open: bool = world.roof[i] <= world.ground[i] + .01
	return weather != null and weather.wet > .35 and open


## What each floor tile is to wet_at(): 1 water, 2 a puddle floor, 0 neither.
func _sort_tiles(world: LevelData) -> void:
	_kinds_of = world
	_water = Effects.WATER
	_puddles = Effects.PUDDLES
	_kinds = PackedByteArray()
	_kinds.resize(world.tile_names.size())
	for t in world.tile_names.size():
		var name := String(world.tile_names[t])
		_kinds[t] = 1 if _water.has(name) else 2 if _puddles.has(name) else 0


## The nearest live rings, at most MAX_SHOWN: [x, y, age, size].
func shown(px: float, py: float) -> Array:
	var near: Array = []
	for r: Array in rings:
		var born: float = r[2]
		var age: float = game.clock - born
		if age >= 0.0 and age < LIFE:
			var rx: float = r[0]
			var ry: float = r[1]
			var dx := rx - px
			var dy := ry - py
			near.append([dx * dx + dy * dy, [r[0], r[1], age, r[3]]])
	near.sort_custom(
		func(a: Array, b: Array) -> bool:
			var da: float = a[0]
			var db: float = b[0]
			return da < db
	)
	var out: Array = []
	for i in mini(MAX_SHOWN, near.size()):
		out.append(near[i][1])
	return out


func ring(x: float, y: float, size: float) -> void:
	rings.append([x, y, game.clock, size])
	if rings.size() > MAX_RINGS:
		rings.pop_front()


## Something come down in water at (x, y, z), `size` how big (a shell .2, a
## gib or a hat .5, a board 1, a body 2): rings spreading from it, a crest of
## water and drops thrown up (gun_fx's water strike) and a splash heard, the
## sound no more than one a SPLASH_GAP. Looks only (its own dice).
func splash(x: float, y: float, z: float, size: float) -> void:
	splashes += 1
	ring(x, y, size * 1.3)
	if size >= .8:
		var a := dice.randf_range(0.0, TAU)
		ring(x + cos(a) * .25 * size, y + sin(a) * .25 * size, size * .7)
	var fx: GameFeature = game.features.get("gun_fx")
	if fx != null:
		fx.call("splash", x, y, z, size)
	if game.clock >= _splash_next:
		_splash_next = game.clock + SPLASH_GAP
		game.sound_at("wade_splash", x, y, clampf(.25 + size * .3, .25, .9))


## Splash if (x, y) is water (BayouBrains.wet_at: deep water or a water
## floor); true when it was. For anything landing: a feature calls this
## where it lands (a server's game has no water feature: `water` null).
static func splash_if(game: Game, x: float, y: float, z: float, size: float) -> bool:
	if not BayouBrains.wet_at(game.world, x, y):
		return false
	var water: GameFeature = game.features.get("water")
	if water != null:
		water.call("splash", x, y, z, size)
	return true


## The water's current on this level (effects.cfg [debris] current_<level>,
## units a second; none for most): what floats drifts on it.
static func current(level_id: String) -> Vector2:
	var flow: Vector2 = Effects.DEBRIS.get("current_" + level_id, Vector2.ZERO)
	return flow


func _tick(_dt: float) -> void:
	while not rings.is_empty():
		var oldest: Array = rings[0]
		var born: float = oldest[2]
		if game.clock - born < LIFE:
			break
		rings.pop_front()
	var p := game.player
	var seen := {}
	if p.air <= .05:
		_wade(0, p.x, p.y, 1.0, false)
	seen[0] = true
	for e: Enemy in game.enemies:
		if absf(e.x - p.x) > 16.0 or absf(e.y - p.y) > 16.0 or not e.alive:
			continue
		var key := e.get_instance_id()
		seen[key] = true
		if e.brain == "swamp_king":
			_wake(key, e, 1.5, .55)
		elif e.swims:
			_wake(key, e, .8, 0.0)
		else:
			_wade(key, e.x, e.y, clampf(e.radius / .3, .7, 1.4), true)
	# Every key seen but the player's (0, not while in the air) is in _bodies
	# now, so any other is stale only when there are more than that.
	if _bodies.size() > seen.size() - (0 if _bodies.has(0) else 1):
		for key: Variant in _bodies.keys():
			if not seen.has(key):
				_bodies.erase(key)


## A wading body: a ring each stride, a splash stepping in, drips standing.
func _wade(key: int, x: float, y: float, size: float, enemy: bool) -> void:
	var wet := wet_at(x, y)
	var known: Variant = _bodies.get(key)
	var b: Array = known if known != null else [x, y, 0.0, wet, game.clock + 1.0]
	var bx: float = b[0]
	var by: float = b[1]
	var moved := Vector2(x - bx, y - by).length()
	if wet:
		var was_wet: bool = b[3]
		var drip_at: float = b[4]
		if not was_wet and moved > 0.0:
			ring(x, y, size * 1.6)
			game.sound_at("wade_splash", x, y, .45 if enemy else .7)
			b[2] = 0.0
		elif moved > .001:
			var stride: float = b[2]
			stride += moved
			b[2] = stride
			if stride >= STRIDE:
				b[2] = 0.0
				ring(x, y, size)
		elif game.clock >= drip_at:
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
	var known: Variant = _bodies.get(key)
	var b: Array = known if known != null else [e.x, e.y, 0.0, false, 0.0]
	var bx: float = b[0]
	var by: float = b[1]
	var moved := Vector2(e.x - bx, e.y - by).length()
	var trail: float = b[2]
	b[2] = trail + moved
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
