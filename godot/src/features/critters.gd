## The county's animals on their toes, each on a little physics of its own:
##
## - chickens scatter at a shot, a blast or a player running at them, flapping
##   up and gliding off a few cells (a short ballistic hop, the fall slowed by
##   their wings), feathers flying;
## - hogs bolt in a spatter of mud; one the player hurts, and now and then
##   one a shot or a runner spooks, charges instead and bowls the player over
##   (knocked flat a moment: Player.knocked) before it runs;
## - the mule stands its ground: walk behind it and it winds up and kicks
##   you flat;
## - a cow tips (USE beside her, tip()): she leans past her balance and goes
##   over (a rigid fall about her hooves, a bounce), lies moaning a while, and
##   gets back up;
## - a gator hit in the water thrashes; a blast shoves Bessie and any animal
##   it does not kill and bowls them up off their feet.
##
## Where they run, the glides, the charges, kicks and knockdowns and the tips
## are play (the feature's carried dice, no rng of the game's; Enemy fields
## and this feature's dictionaries, carried online); feathers, mud and
## splashes are looks off their own dice. At most ACTIVE_MOST bodies fly or
## fall at once (the rest just hop) and nothing moves that is not set off.
## Nothing saved: it all lasts seconds. Below the HIGH physics tier
## (Quality.level(); always HIGH with company) fewer fly at once (_most()).
extends GameFeature

const Water := preload("res://src/features/water.gd")

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
## A flap off the ground, a chicken's, its glide (cells a second) and how
## much its wings slow the fall.
const FLAP_LIFT := 2.6
const GLIDE := 1.9
const GLIDE_FALL := .4
const GRAVITY := 9.4
## A hog charging: seconds, its pace, its butt, the share of spooked hogs
## that charge rather than run, and how long a player lies knocked flat.
const CHARGE_TIME := 2.0
const CHARGE_PACE := 2.1
const HOG_BUTT := 5
const SPOOK_CHARGE := .3
const KNOCKED := 1.1
## The mule: how near behind it counts, the wind-up, the kick, how long the
## kicking cel shows after and how soon it kicks again.
const KICK_REACH := 1.35
const KICK_WIND := .32
const KICK_SHOW := .3
const MULE_KICK := 12
const KICK_SHOVE := .9
const KICK_EVERY := 2.4
## A cow: how near the player must stand to tip her, her topple (gravity's
## pull on her lean, radians a second a second; the push that starts it),
## seconds she lies, how fast she gets up (radians a second).
const TIP_REACH := 1.3
const TIP_PULL := 7.5
const TIP_PUSH := 1.4
const TIPPED_FOR := 6.0
const GET_UP := 1.6
## How near a player stands for a cow or the mule to stand still for them.
const PLACID := 2.4
## Seconds a hit gator thrashes.
const THRASH := .6
const SPECK_CAP := 170
## Bodies flying or falling at once (gliding chickens, tipping cows).
const ACTIVE_MOST := 12

var dice := RandomNumberGenerator.new()
## The feathers', mud's and splashes' dice: looks only, never carried
## (SnapCodec SKIP_FIELDS); `dice` is play's.
var speck_dice := RandomNumberGenerator.new()
## Animals in the air: enemy -> its rise (cells a second); gliding chickens:
## enemy -> Vector2 (cells a second).
var _hops := {}
var _glides := {}
## Hogs charging: enemy -> [until when, the player's slot].
var _charging := {}
## Mules kicking: enemy -> [when it lands, the player's slot, cel shown until];
## when each may kick again.
var _kicks := {}
var _kick_ready := {}
## Cows tipped: enemy -> [lean (radians), turn (radians a second), stage (0
## going over, 1 down, 2 getting up), down until].
var _tips := {}
## Gators thrashing: enemy -> until when.
var _thrashing := {}
var _spook_next := 0.0
var _scattered := 0
var _knocked := 0
var _tipped := 0


func id() -> String:
	return "critters"


func attach() -> void:
	dice.seed = hash(game.level.id) + 1313
	speck_dice.seed = hash(game.level.id) + 1314
	game.events.shot_fired.connect(_fired)
	game.events.exploded.connect(_blast)
	game.events.ticked.connect(_tick)


## How many animals have been sent running, players knocked flat and cows
## tipped (tools read them).
func scattered() -> int:
	return _scattered


func knocked() -> int:
	return _knocked


func tipped() -> int:
	return _tipped


func charging(e: Enemy) -> bool:
	return _charging.has(e)


func gliding(e: Enemy) -> bool:
	return _glides.has(e)


func kicking(e: Enemy) -> bool:
	return _kicks.has(e)


func lying(e: Enemy) -> bool:
	return _tips.has(e)


func _animal(e: Enemy) -> bool:
	return e.alive and not e.hostile and not e.dormant and e.brain != "bessie"


## Bodies flying or falling at once at most: ACTIVE_MOST, cut to the physics
## tier (Quality.steps: HIGH all, MEDIUM two thirds, LOW half).
static func _most() -> int:
	return Quality.steps(ACTIVE_MOST)


func _active() -> int:
	return _glides.size() + _tips.size()


func _fired(gun: int) -> void:
	var p := game.player
	var noise: float = Weapons.SHOT_NOISE[gun]
	scatter(p.x, p.y, minf(SHOT_REACH, noise), p)


## Every animal within `reach` of (x, y) runs from it a moment; chickens flap
## and glide; a hog `by` a player spooked may charge them instead; the mule
## and a lying cow stand their ground.
func scatter(x: float, y: float, reach: float, by: Player = null) -> int:
	var count := 0
	for e: Enemy in game.enemies:
		if not _animal(e) or _charging.has(e) or _tips.has(e) or e.brain == "mule":
			continue
		var d := Vector2(e.x - x, e.y - y).length()
		if d >= reach:
			continue
		count += 1
		if e.brain == "pig" and by != null and dice.randf() < SPOOK_CHARGE:
			charge(e, by)
			continue
		e.heard = [x, y, game.clock, game.clock + RUN_FOR]
		if e.brain == "chicken":
			_flap(e, FLAP_LIFT * dice.randf_range(.75, 1.1), atan2(e.y - y, e.x - x))
		elif e.brain == "pig":
			_spatter(e, "soil", 4)
	_scattered += count
	return count


## A hog goes for player `p`.
func charge(e: Enemy, p: Player) -> void:
	_charging[e] = [game.clock + CHARGE_TIME, p.slot]
	e.heard = null
	game.sound_at("pig", e.x, e.y, 1.0)
	_spatter(e, "soil", 5)


## A chicken flaps up and glides off `away` (radians) when there is room.
func _flap(e: Enemy, lift: float, away: float) -> void:
	if e.hop > 0.0:
		return
	_hops[e] = lift
	e.hop = .01
	if _active() < _most():
		_glides[e] = Vector2.from_angle(away + dice.randf_range(-.5, .5)) * GLIDE
	_spatter(e, "feather", 3)
	game.sound_at("chicken", e.x, e.y, .45)


func _spatter(e: Enemy, kind: String, count: int) -> void:
	var z: float = game.world.stand(e) + e.z + e.height * .5
	for _i in count:
		if game.specks.size() >= SPECK_CAP:
			return
		var a := speck_dice.randf() * TAU
		var v := speck_dice.randf_range(.3, 1.3)
		game.specks.append(
			GameState.Speck.new(
				e.x,
				e.y,
				z,
				cos(a) * v,
				sin(a) * v,
				speck_dice.randf_range(.4, 1.8),
				speck_dice.randf_range(.35, .9),
				kind
			)
		)


## A blast: they all run, and those near it it did not kill are shoved and
## bowled up (Bessie too, who no blast hurts).
func _blast(x: float, y: float, _z: float, _energy: bool) -> void:
	scatter(x, y, BLAST_REACH)
	for e: Enemy in game.enemies:
		if not e.alive or e.hostile or e.dormant or _tips.has(e):
			continue
		var push := Tumble.shove(x, y, SHOVE_REACH, 1.0, e.x, e.y)
		if push == Vector3.ZERO or not game.world.visible(x, y, e.x, e.y):
			continue
		var run := Vector2(push.x, push.y)
		if run.length() > 0.0:
			run = run.normalized() * SHOVE_MOST * minf(1.0, push.z / .55)
		game.move_actor(e, run.x, run.y, e.radius)
		_hops.erase(e)
		_glides.erase(e)
		e.hop = 0.0
		_hops[e] = HOP_LIFT * minf(1.0, push.z / .55 + .3)
		e.hop = .01
		if e.brain == "bessie" or e.brain == "cow":
			game.sound_at("cow_moo", e.x, e.y, .9)
			_spatter(e, "soil", 6)
		elif e.brain == "chicken":
			_spatter(e, "feather", 6)
		else:
			_spatter(e, "soil", 5)


## The player's hit on an animal or a gator (HitZones.land).
func struck(e: Enemy) -> void:
	if e.brain == "pig" and e.alive and not _charging.has(e):
		charge(e, game.player)
	elif e.brain == "chicken" and e.alive:
		_flap(e, FLAP_LIFT, atan2(e.y - game.player.y, e.x - game.player.x))
	elif e.swims and not BossKit.is_boss(e) and BayouBrains.wet_at(game.world, e.x, e.y):
		_thrashing[e] = game.clock + THRASH
		game.sound_at("wade_splash", e.x, e.y, .8)
		_spatter(e, "splash", 10)
		var water: Water = game.features.get("water")
		if water != null:
			water.ring(e.x, e.y, 1.0)


## USE beside a cow: she goes over (true when one did). Any cow standing,
## near `p` and not already down.
func tip(p: Player) -> bool:
	var best: Enemy = null
	var best_d := TIP_REACH
	for e: Enemy in game.enemies:
		if e.brain != "cow" or not _animal(e) or _tips.has(e) or e.hop > 0.0:
			continue
		var d := Vector2(e.x - p.x, e.y - p.y).length()
		if d < best_d:
			best = e
			best_d = d
	if best == null or _active() >= _most():
		return false
	_tips[best] = [.06, TIP_PUSH, 0, 0.0]
	best.heard = null
	_tipped += 1
	game.sound_at("cow_moo", best.x, best.y, .7)
	return true


## Knocks player `p` flat: hurt, shoved away from `from`, down a moment.
func knock(p: Player, from: Enemy, amount: int, shove: float, cause: String) -> void:
	var away := Vector2(p.x - from.x, p.y - from.y)
	if away.length() < .01:
		away = Vector2.from_angle(from.angle)
	away = away.normalized() * shove
	game.damage(amount, [from.x, from.y], cause, p)
	game.move_actor(p, away.x, away.y, Game.PLAYER_RADIUS)
	p.knocked = KNOCKED
	p.vx = 0.0
	p.vy = 0.0
	_knocked += 1


## Enemy.tick's hook for animals: a hog charging, a mule kicking or about
## to, a cow tipped. True when it took the tick.
func steer(e: Enemy, dt: float) -> bool:
	if _tips.has(e):
		return true
	if e.brain == "mule":
		return _mule(e) or _placid(e)
	if e.brain == "cow":
		return _placid(e)
	if not _charging.has(e):
		return false
	var run: Array = _charging[e]
	var charge_until: float = run[0]
	var slot: int = run[1]
	var p: Player = game.players[slot] if slot < game.players.size() else game.player
	if game.clock >= charge_until or p.health <= 0:
		_charging.erase(e)
		return false
	var gap := Vector2(p.x - e.x, p.y - e.y)
	if gap.length() < e.radius + Game.PLAYER_RADIUS + .08:
		# The butt: the player bowled over, the hog off and running.
		_charging.erase(e)
		knock(p, e, HOG_BUTT, .45, "HOG")
		game.sound_at("pig", e.x, e.y, 1.0)
		e.heard = [p.x, p.y, game.clock, game.clock + RUN_FOR]
		return true
	e.follow(dt, game, gap.angle(), CHARGE_PACE)
	return true


## A cow or the mule does not shy from a player close by: it stands and
## grazes (so a cow can be walked up to, and the mule's rump stays put).
func _placid(e: Enemy) -> bool:
	if e.heard != null:
		return false
	for p: Player in game.players:
		if p.health > 0 and absf(p.x - e.x) < PLACID and absf(p.y - e.y) < PLACID:
			return true
	return false


## Whether player `p` stands close behind the mule (its rump to them).
func _behind(e: Enemy, p: Player, reach: float) -> bool:
	var gap := Vector2(p.x - e.x, p.y - e.y)
	if p.health <= 0 or gap.length() > reach or gap.length() < .01:
		return false
	return gap.normalized().dot(Vector2.from_angle(e.angle)) < -.45


func _mule(e: Enemy) -> bool:
	if _kicks.has(e):
		var kick: Array = _kicks[e]
		var lands: float = kick[0]
		var slot: int = kick[1]
		var shown: float = kick[2]
		if lands >= 0.0 and game.clock >= lands:
			kick[0] = -1.0
			game.sound_at("can_kick", e.x, e.y, .9)
			if slot < game.players.size():
				var p: Player = game.players[slot]
				if _behind(e, p, KICK_REACH + .25):
					knock(p, e, MULE_KICK, KICK_SHOVE, "MULE")
					game.sound_at("mule_bray", e.x, e.y, .9)
		if lands < 0.0 and game.clock >= shown:
			_kicks.erase(e)
			e.held_cel = ""
			_kick_ready[e] = game.clock + KICK_EVERY
		return true
	var ready: float = _kick_ready.get(e, 0.0)
	if game.clock < ready:
		return false
	for p: Player in game.players:
		if _behind(e, p, KICK_REACH):
			_kicks[e] = [game.clock + KICK_WIND, p.slot, game.clock + KICK_WIND + KICK_SHOW]
			e.held_cel = "mule_kick"
			e.heard = null
			game.sound_at("mule_bray", e.x, e.y, .6)
			return true
	return false


func _tick(dt: float) -> void:
	if not _hops.is_empty():
		_fly(dt)
	if not _tips.is_empty():
		_topple(dt)
	if not _thrashing.is_empty():
		var done: Array = []
		for e: Enemy in _thrashing:
			var thrash_until: float = _thrashing[e]
			if game.clock >= thrash_until:
				done.append(e)
				continue
			# Rolling side to side in the water.
			e.face_left = int((thrash_until - game.clock) * 14.0) % 2 == 0
			if speck_dice.randf() < dt * 14.0:
				_spatter(e, "splash", 2)
		for e: Enemy in done:
			_thrashing.erase(e)
	# A player running at the animals: the first by slot (any player's run,
	# not the local one's: this is play).
	var p: Player = null
	for each: Player in game.players:
		if Vector2(each.vx, each.vy).length() > RUNNING:
			p = each
			break
	if game.clock >= _spook_next and p != null:
		_spook_next = game.clock + .25
		for e: Enemy in game.enemies:
			if (
				(e.brain == "chicken" or e.brain == "pig")
				and _animal(e)
				and e.heard == null
				and not _charging.has(e)
				and Vector2(e.x - p.x, e.y - p.y).length() < SPOOK
			):
				_scattered += 1
				if e.brain == "pig":
					if dice.randf() < SPOOK_CHARGE:
						charge(e, p)
					else:
						e.heard = [p.x, p.y, game.clock, game.clock + RUN_FOR]
					continue
				e.heard = [p.x, p.y, game.clock, game.clock + RUN_FOR]
				_flap(e, FLAP_LIFT * .8, atan2(e.y - p.y, e.x - p.x))


## Animals in the air: they rise and fall; a gliding chicken sails on, its
## wings slowing the fall, until it lands (or strikes a wall and drops).
func _fly(dt: float) -> void:
	var landed: Array = []
	for e: Enemy in _hops:
		var rise: float = _hops[e]
		var glide: Vector2 = _glides.get(e, Vector2.ZERO)
		var pull := GRAVITY * (GLIDE_FALL if glide != Vector2.ZERO and rise < 0.0 else 1.0)
		rise -= pull * dt
		_hops[e] = rise
		e.hop = maxf(0.0, e.hop + rise * dt)
		if glide != Vector2.ZERO:
			var ox := e.x
			var oy := e.y
			game.move_actor(e, glide.x * dt, glide.y * dt, e.radius)
			e.angle = glide.angle()
			e.face_left = glide.x < 0.0
			if absf(e.x - ox) + absf(e.y - oy) < glide.length() * dt * .3:
				_glides.erase(e)
		if e.hop <= 0.0 or not e.alive:
			e.hop = 0.0
			landed.append(e)
	for e: Enemy in landed:
		_hops.erase(e)
		_glides.erase(e)


## Cows going over, lying, getting up. Going over: her lean grows under her
## own weight once past the push (a body falling about the edge of its
## hooves), a thud and a bounce at the ground, down a while, then up.
func _topple(dt: float) -> void:
	var done: Array = []
	for e: Enemy in _tips:
		var t: Array = _tips[e]
		var lean: float = t[0]
		var turn: float = t[1]
		var stage: int = t[2]
		if not e.alive:
			done.append(e)
			continue
		if stage == 0:
			turn += TIP_PULL * sin(lean) * dt
			lean += turn * dt
			if lean >= PI * .5:
				lean = PI * .5
				if turn > 1.2:
					# One bounce off the ground.
					turn = -turn * .22
					game.sound_at("impact_dirt", e.x, e.y, .8)
				else:
					stage = 1
					t[3] = game.clock + TIPPED_FOR
					game.sound_at("cow_moo", e.x, e.y, 1.0)
					_spatter(e, "soil", 6)
		elif stage == 1:
			var down_until: float = t[3]
			if game.clock >= down_until:
				stage = 2
		else:
			lean -= GET_UP * dt
			if lean <= 0.0:
				done.append(e)
		t[0] = lean
		t[1] = turn
		t[2] = stage
		# Lying, she shows her fallen picture; going over and up, her own
		# picture leaning (squashed by the lean's cosine).
		e.held_cel = "cow_down" if stage == 1 else ""
		e.squash = Enemy.DOWN_SHARE["cow"] if stage == 1 else maxf(.3, cos(lean))
	for e: Enemy in done:
		_tips.erase(e)
		e.held_cel = ""
		e.squash = 1.0
