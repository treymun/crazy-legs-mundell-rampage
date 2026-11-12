## The county's animals on their toes: chickens scatter and flap off at a
## shot, a blast or the player running at them, feathers flying; hogs bolt in
## a spatter of mud, and one the player hurts and does not kill charges them
## a moment (a butt for HOG_BUTT) before it runs; a gator hit in the water
## thrashes; a blast shoves Bessie and any animal it does not kill and bowls
## them up off their feet. Where they run and the hog's butt are play (the
## animals' own way of running, enemies.gd noise_step, set off here, with no
## dice); the flap, the hop, feathers, mud and splashes are looks off the
## feature's own dice. Nothing saved: it all lasts a second or two.
extends GameFeature

## How far a shot (at most its noise) and a blast send them running, how
## long they run, and how near a running player must come.
const SHOT_REACH := 9.0
const BLAST_REACH := 7.0
const RUN_FOR := 1.6
const RUNNING := 3.3
const SPOOK := 2.8
## A blast's shove on an animal it does not kill: reach, the most it moves
## one (cells), and the hop it bowls them up with.
const SHOVE_REACH := 3.2
const SHOVE_MOST := .6
const HOP_LIFT := 2.4
## A flap off the ground, a chicken's.
const FLAP_LIFT := 2.6
const GRAVITY := 9.4
## A hurt hog: seconds it charges, its pace, and its butt.
const CHARGE_TIME := 2.0
const CHARGE_PACE := 2.1
const HOG_BUTT := 5
## Seconds a hit gator thrashes.
const THRASH := .6
const SPECK_CAP := 170

var dice := RandomNumberGenerator.new()
## Animals in the air: enemy -> its rise (cells a second).
var _hops := {}
## Hurt hogs charging: enemy -> until when.
var _charging := {}
## Gators thrashing: enemy -> until when.
var _thrashing := {}
var _spook_next := 0.0
var _scattered := 0


func id() -> String:
	return "critters"


func attach() -> void:
	dice.seed = hash(game.level.id) + 1313
	game.shot_fired.connect(_fired)
	game.exploded.connect(_blast)
	game.ticked.connect(_tick)


## How many animals have been sent running (tools read it).
func scattered() -> int:
	return _scattered


func charging(e: Enemy) -> bool:
	return _charging.has(e)


func _animal(e: Enemy) -> bool:
	return e.alive and not e.hostile and not e.dormant and e.brain != "bessie"


func _fired(gun: int) -> void:
	var p = game.player
	scatter(p.x, p.y, minf(SHOT_REACH, float(Weapons.SHOT_NOISE[gun])))


## Every animal within `reach` of (x, y) runs from it a moment; chickens flap.
func scatter(x: float, y: float, reach: float) -> int:
	var count := 0
	for e: Enemy in game.enemies:
		if not _animal(e) or _charging.has(e):
			continue
		var d := Vector2(e.x - x, e.y - y).length()
		if d >= reach:
			continue
		e.heard = [x, y, game.clock, game.clock + RUN_FOR]
		count += 1
		if e.brain == "chicken":
			_flap(e, FLAP_LIFT * dice.randf_range(.75, 1.1))
		elif e.brain == "pig":
			_spatter(e, "soil", 4)
	_scattered += count
	return count


func _flap(e: Enemy, lift: float) -> void:
	if e.hop > 0.0:
		return
	_hops[e] = lift
	e.hop = .01
	_spatter(e, "feather", 3)
	game.sound_at("chicken", e.x, e.y, .45)


func _spatter(e: Enemy, kind: String, count: int) -> void:
	var z: float = game.world.elevation(e.x, e.y) + e.z + e.height * .5
	for _i in count:
		if game.specks.size() >= SPECK_CAP:
			return
		var a := dice.randf() * TAU
		var v := dice.randf_range(.3, 1.3)
		game.specks.append(
			GameState.Speck.new(
				e.x,
				e.y,
				z,
				cos(a) * v,
				sin(a) * v,
				dice.randf_range(.4, 1.8),
				dice.randf_range(.35, .9),
				kind
			)
		)


## A blast: they all run, and those near it it did not kill are shoved and
## bowled up (Bessie too, who no blast hurts).
func _blast(x: float, y: float, _z: float, _energy: bool) -> void:
	scatter(x, y, BLAST_REACH)
	for e: Enemy in game.enemies:
		if not e.alive or e.hostile or e.dormant:
			continue
		var push := Tumble.shove(x, y, SHOVE_REACH, 1.0, e.x, e.y)
		if push == Vector3.ZERO or not game.world.visible(x, y, e.x, e.y):
			continue
		var run := Vector2(push.x, push.y)
		if run.length() > 0.0:
			run = run.normalized() * SHOVE_MOST * minf(1.0, push.z / .55)
		game.move_actor(e, run.x, run.y, e.radius)
		_hops.erase(e)
		e.hop = 0.0
		_hops[e] = HOP_LIFT * minf(1.0, push.z / .55 + .3)
		e.hop = .01
		if e.brain == "bessie":
			game.sound_at("cow_moo", e.x, e.y, .9)
			_spatter(e, "soil", 6)
		elif e.brain == "chicken":
			_spatter(e, "feather", 6)
		else:
			_spatter(e, "soil", 5)


## The player's hit on an animal or a gator (HitZones.land).
func struck(e: Enemy) -> void:
	if e.brain == "pig" and e.alive and not _charging.has(e):
		_charging[e] = game.clock + CHARGE_TIME
		e.heard = null
		game.sound_at("pig", e.x, e.y, 1.0)
		_spatter(e, "soil", 5)
	elif e.brain == "chicken" and e.alive:
		_flap(e, FLAP_LIFT)
	elif e.swims and not BossKit.is_boss(e) and BayouBrains.wet_at(game.world, e.x, e.y):
		_thrashing[e] = game.clock + THRASH
		game.sound_at("wade_splash", e.x, e.y, .8)
		_spatter(e, "splash", 10)
		var water = game.features.get("water")
		if water != null:
			water.ring(e.x, e.y, 1.0)


## Enemy.tick's hook for animals: a hurt hog charges the player. True when it
## took the tick.
func steer(e: Enemy, dt: float) -> bool:
	if not _charging.has(e):
		return false
	var p = game.player
	if game.clock >= float(_charging[e]) or p.health <= 0:
		_charging.erase(e)
		return false
	var gap := Vector2(p.x - e.x, p.y - e.y)
	if gap.length() < e.radius + Game.PLAYER_RADIUS + .08:
		# The butt: the player knocked back a step, the hog off and running.
		_charging.erase(e)
		game.damage(HOG_BUTT, [e.x, e.y], "HOG")
		var shove := gap.normalized() * .35
		game.move_actor(p, shove.x, shove.y, Game.PLAYER_RADIUS)
		game.sound_at("pig", e.x, e.y, 1.0)
		e.heard = [p.x, p.y, game.clock, game.clock + RUN_FOR]
		return true
	e.follow(dt, game, gap.angle(), CHARGE_PACE)
	return true


func _tick(dt: float) -> void:
	if not _hops.is_empty():
		var landed: Array = []
		for e: Enemy in _hops:
			var rise: float = _hops[e] - GRAVITY * dt
			_hops[e] = rise
			e.hop = maxf(0.0, e.hop + rise * dt)
			if e.hop <= 0.0 or not e.alive:
				e.hop = 0.0
				landed.append(e)
		for e: Enemy in landed:
			_hops.erase(e)
	if not _thrashing.is_empty():
		var done: Array = []
		for e: Enemy in _thrashing:
			if game.clock >= float(_thrashing[e]):
				done.append(e)
				continue
			# Rolling side to side in the water.
			e.face_left = int((float(_thrashing[e]) - game.clock) * 14.0) % 2 == 0
			if dice.randf() < dt * 14.0:
				_spatter(e, "splash", 2)
		for e: Enemy in done:
			_thrashing.erase(e)
	var p = game.player
	if game.clock >= _spook_next and Vector2(p.vx, p.vy).length() > RUNNING:
		# The player running at the chickens.
		_spook_next = game.clock + .25
		for e: Enemy in game.enemies:
			if (
				e.brain == "chicken"
				and _animal(e)
				and e.heard == null
				and Vector2(e.x - p.x, e.y - p.y).length() < SPOOK
			):
				e.heard = [p.x, p.y, game.clock, game.clock + RUN_FOR]
				_scattered += 1
				_flap(e, FLAP_LIFT * .8)
