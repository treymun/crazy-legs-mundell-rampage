## What a fight leaves lying about: brass from the rifle, a revolver's six
## dumped on reload and the shotgun's red hulls, tinking where they land;
## embers and slow smoke rising off a blast and the black scorch it leaves;
## and a wounded varmint's trail of blood. All of it looks only: its own dice,
## never saved, never in the way. Lifetimes are effects.cfg [debris]; the
## scorches stay a long while (scorch_cap of them), the oldest fading first,
## and the smoke goes off on the level's wind (wind_<level>).
##
## Brass and hulls move as loose things do (tumble.gd): they land on the floor
## really under them (a loft, a stair, a ramp), tink and bounce lower each
## time, glance off walls and furniture, turn over end on end in the air, roll
## a little and down a slope, and lie still. Embers and smoke stop at floors
## and ceilings; a scorch lies on the surface the blast was over.
extends GameFeature

const MAX_BITS := 90
## Seconds a scorch takes to fade out once its time is up.
const FADE := 2.5
## A shell's roundness against its height (its picture's), for its roll, and
## seconds a shell come to rest takes to roll the rest of the way flat.
const ROLL_R := .3
const ROLL_FLAT := .25
## A shell come down in water sinks this fast (units a second) and is gone
## after this long.
const SINK_RATE := .2
const SINK_TIME := .5

const Water := preload("res://src/features/water.gd")


## One piece of debris in the air or on the ground.
class Bit:
	extends Tumble.Body
	var age := 0.0
	var life := 1.0
	var kind := "casing"
	var size := .05
	## Turned over (View.Sprite.spin) and how fast it turns in the air.
	var spin := 0.0
	var spin_rate := 0.0
	## Its age when it came onto its floor for good (below 0: in the air) and
	## when it came to rest; how far it has turned rolling about its length.
	var landed := -1.0
	var rested := -1.0
	var roll := 0.0
	## Its age when it splashed into water and went under (below 0: never).
	var sink := -1.0


var dice := RandomNumberGenerator.new()
var bits: Array = []
## [x, y, z, angle, size, frame, made at, fading since (below 0: not yet),
## the ground mark laid for it]
var scorches: Array = []
var _trail_next := 0.0
## How brass and hulls move (effects.cfg [debris] case_*), made at attach.
var _case_feel: Tumble.Feel
var _hull_feel: Tumble.Feel
## The resting bit _tick() asks next whether it still has a floor under it.
var _wake_at := 0


func id() -> String:
	return "debris"


func attach() -> void:
	dice.seed = 1987
	_case_feel = _make_feel("case", .02, .42, 1.4)
	_hull_feel = _make_feel("hull", .03, .3, 2.2)
	game.events.shot_fired.connect(_fired)
	game.events.gun_reloading.connect(_reloading)
	game.events.exploded.connect(_exploded)
	tick_with(_tick)


func _life(key: String, fallback: float) -> float:
	var life: float = Effects.DEBRIS.get(key, fallback)
	return life


## A shell's feel from effects.cfg [debris] <kind>_bounce, _drag, _wall: a
## light, hard thing that tinks and bounces, rolls a little and lies still.
func _make_feel(kind: String, radius: float, bounce: float, drag: float) -> Tumble.Feel:
	var feel := Tumble.Feel.new(
		radius,
		_life(kind + "_wall", .45),
		_life(kind + "_bounce", bounce),
		_life(kind + "_drag", drag)
	)
	feel.grip = .55
	feel.hard = 1.1
	feel.pull = .85
	feel.climb = .04
	return feel


## Out of the gun's right side, tumbling.
func _eject(kind: String, count: int, spread := 1.0) -> void:
	var p := game.player
	var a: float = p.view_angle()
	for k in count:
		var bit := Bit.new()
		bit.kind = kind
		bit.size = .07 if kind == "hull" else .05
		bit.x = p.x + cos(a) * .25 - sin(a) * .12
		bit.y = p.y + sin(a) * .25 + cos(a) * .12
		bit.z = p.eye - .22
		if game.world.blocked(bit.x, bit.y, .03, bit.z):
			# Hard against a wall: out of the gun beside the shooter instead.
			bit.x = p.x
			bit.y = p.y
		var out := dice.randf_range(.9, 1.6) * spread
		bit.vx = -sin(a) * out + cos(a) * dice.randf_range(-.3, .4)
		bit.vy = cos(a) * out + sin(a) * dice.randf_range(-.3, .4)
		bit.vz = dice.randf_range(1.2, 2.2)
		bit.life = _life("case_life", 7.0)
		# Brass flips end over end out of the port, a hull lazier.
		var turn := (
			dice.randf_range(14.0, 22.0) if kind == "casing" else dice.randf_range(8.0, 12.0)
		)
		bit.spin_rate = turn if dice.randf() < .5 else -turn
		bit.spin = dice.randf_range(0.0, TAU)
		_add(bit)


func _add(bit: Bit) -> void:
	bits.append(bit)
	if bits.size() > MAX_BITS:
		bits.pop_front()


func _fired(gun: int) -> void:
	if game.own_quiet:
		game.hands_watch.defer(_fired.bind(gun), "shot")
		return
	if gun in [Weapons.RIFLE, Weapons.RIVETER, Weapons.HUNTER, Weapons.MOWER]:
		_eject("casing", 1)
	elif (
		gun
		in [
			Weapons.COUNTY45,
			Weapons.TOMMY,
			Weapons.GREASE_GUN,
			Weapons.PATROL_BAR,
			Weapons.MARKSMAN,
		]
	):
		_eject("casing", 1)
	elif gun == Weapons.RIOT_PUMP:
		_eject("hull", 1, .5)


func own_shot(gun: int) -> void:
	_fired(gun)


func _reloading(gun: int) -> void:
	if game.own_quiet:
		game.hands_watch.defer(_reloading.bind(gun), "reload")
		return
	if gun == Weapons.REVOLVER or gun == Weapons.STAR357:
		_eject("casing", 6, .4)
	elif gun == Weapons.HOGLEG:
		_eject("casing", 3, .3)
	elif gun == Weapons.SHOTGUN:
		_eject("hull", 2, .7)


func own_reload(gun: int) -> void:
	_reloading(gun)


func _exploded(x: float, y: float, z: float, energy: bool) -> void:
	if game.blast_quiet:
		return  # shown already by an online client's own blast (net_own_shots.gd)
	if energy:
		return
	# The floor the blast was over: a loft's boards, a ramp, the ground.
	var floor_z: float = Tumble.floor_at(game.world, x, y, z)
	if z - floor_z < 1.2:
		var turn := dice.randf_range(0, TAU)
		var size := dice.randf_range(.75, 1.05)
		var look := dice.randi_range(0, 2)
		var mark := View.GroundMark.new(x, y, 0.0, turn, size, size, "mark_scorch_%d" % look)
		Tumble.lay(game.world, mark, z)
		scorches.append([x, y, mark.z, turn, size, look, game.clock, -1.0, mark])
	var embers: int = Effects.DEBRIS.get("embers", 7)
	for k in embers:
		var ember := Bit.new()
		ember.kind = "ember"
		ember.x = x
		ember.y = y
		ember.z = z
		ember.vx = dice.randf_range(-1.2, 1.2)
		ember.vy = dice.randf_range(-1.2, 1.2)
		ember.vz = dice.randf_range(.6, 1.6)
		ember.life = _life("ember_life", 1.6) * dice.randf_range(.6, 1.1)
		ember.size = .045
		_add(ember)
	var puffs: int = Effects.DEBRIS.get("smoke_puffs", 3)
	for k in puffs:
		var smoke := Bit.new()
		smoke.kind = "smoke"
		smoke.x = x + dice.randf_range(-.4, .4)
		smoke.y = y + dice.randf_range(-.4, .4)
		smoke.z = z + .2
		smoke.vz = dice.randf_range(.25, .45)
		smoke.life = _life("smoke_life", 2.6)
		smoke.size = .7
		_add(smoke)


func _tick(dt: float) -> void:
	var wind: Vector2 = Effects.DEBRIS.get("wind_" + game.level.id, Vector2.ZERO)
	var world: LevelData = game.world
	var kept: Array = []
	_wake_one()
	for bit: Bit in bits:
		bit.age += dt
		if bit.age >= bit.life:
			continue
		kept.append(bit)
		if bit.rest:
			continue
		if bit.kind == "casing" or bit.kind == "hull":
			_shell(bit, dt)
			continue
		if bit.kind == "ember":
			# Floats up, drifts, burns out.
			bit.vz -= .4 * dt
			bit.vx *= 1.0 - dt
			bit.vy *= 1.0 - dt
		else:
			bit.size += dt * .35
			bit.vx += (wind.x - bit.vx) * minf(1.0, dt * 1.5)
			bit.vy += (wind.y - bit.vy) * minf(1.0, dt * 1.5)
		var nx := bit.x + bit.vx * dt
		var ny := bit.y + bit.vy * dt
		if world.blocked(nx, ny, .02, bit.z):
			bit.vx *= -.4
			bit.vy *= -.4
		else:
			bit.x = nx
			bit.y = ny
		var was := bit.z
		bit.z += bit.vz * dt
		# Under a ceiling or a deck it spreads along it; it never sinks into a floor.
		var roof: float = world.roof_over(bit.x, bit.y, was)
		if roof > 0.0 and bit.z > roof - bit.size * .5:
			bit.z = maxf(was, roof - bit.size * .5)
			bit.vz = minf(bit.vz, 0.0)
		var floor_z: float = world.floor_under(bit.x, bit.y, was)
		if bit.z < floor_z:
			bit.z = floor_z
			bit.vz = maxf(bit.vz, 0.0)
	bits = kept
	_age_scorches()
	_trails()


## A casing or a hull: it falls, tinks off the floor and bounces lower each
## time, glances off walls, turns over in the air, rolls and lies still.
func _shell(bit: Bit, dt: float) -> void:
	var casing := bit.kind == "casing"
	if bit.sink >= 0.0:
		# Gone into the water: down under its face, then gone.
		bit.z -= SINK_RATE * dt
		if bit.age - bit.sink > SINK_TIME:
			bit.life = bit.age
		return
	var ox := bit.x
	var oy := bit.y
	var hit := Tumble.step(game.world, bit, _case_feel if casing else _hull_feel, dt)
	if (
		(hit & Tumble.FLOOR or (bit.vz == 0.0 and bit.landed < 0.0))
		and Water.splash_if(game, bit.x, bit.y, bit.z, .2)
	):
		bit.sink = bit.age
		bit.rest = false
		return
	if hit & Tumble.FLOOR:
		bit.spin_rate *= -.5
		game.sound_at("casing_tink", bit.x, bit.y, .22 if casing else .12)
	elif hit & Tumble.WALL:
		bit.spin_rate *= -.7
	# On its floor (rolling or still) the 3D view eases it over onto its side
	# from the turn it came down at (its spin then, kept) and rolls it about
	# its length by its run; off the floor again (a bounce) it tumbles anew.
	if bit.vz != 0.0:
		bit.landed = -1.0
		bit.spin += bit.spin_rate * dt
	elif bit.landed < 0.0:
		bit.landed = bit.age
	if hit & Tumble.RESTED:
		bit.rest = true
		bit.rested = bit.age
	elif bit.vz == 0.0:
		var run := Vector2(bit.x - ox, bit.y - oy).length()
		bit.roll += run / (bit.size * ROLL_R) * signf(bit.spin_rate + .001)


## One resting shell a tick is asked whether it still has a floor under it.
func _wake_one() -> void:
	if bits.is_empty():
		return
	_wake_at = (_wake_at + 1) % bits.size()
	var bit: Bit = bits[_wake_at]
	if bit.rest and (bit.kind == "casing" or bit.kind == "hull"):
		if Tumble.unsupported(game.world, bit, _case_feel):
			bit.rest = false


## Past the cap or their life the oldest scorches fade out, then go.
func _age_scorches() -> void:
	var over := scorches.size() - int(_life("scorch_cap", 24))
	var life := _life("scorch_life", 900.0)
	var k := 0
	while k < scorches.size():
		var s: Array = scorches[k]
		var fading_at: float = s[7]
		var laid_at: float = s[6]
		if fading_at < 0.0 and (k < over or game.clock - laid_at > life):
			s[7] = game.clock
			fading_at = game.clock
		if fading_at >= 0.0 and game.clock - fading_at > FADE:
			scorches.remove_at(k)
			over -= 1
			continue
		k += 1


## A hurt enemy on the move leaves drops behind it.
func _trails() -> void:
	if not game.gore or game.clock < _trail_next:
		return
	_trail_next = game.clock + .45
	for e: Enemy in game.enemies:
		if (
			e.alive
			and e.hostile
			and e.hp < e.max_hp * .5
			and e.pose - e.last_stride < .3
			and absf(e.x - game.player.x) < 12.0
			and absf(e.y - game.player.y) < 12.0
		):
			game.gore_fx.call(
				"_stain",
				e.x + dice.randf_range(-.1, .1),
				e.y + dice.randf_range(-.1, .1),
				dice.randf_range(.04, .08),
				Enemy.PLASMA.has(e.kind),
				game.world.stand(e) + .3
			)


func sprites() -> Array:
	var out: Array = []
	var p := game.player
	for bit: Bit in bits:
		# Brass just out of the gun is at the lens: a blur filling the view's edge.
		if (bit.x - p.x) * (bit.x - p.x) + (bit.y - p.y) * (bit.y - p.y) < .36:
			continue
		if not game.in_view(bit.x, bit.y, bit.size * 2.0 + .3):
			continue
		var name := "fx_casing"
		match bit.kind:
			"hull":
				name = "fx_hull"
			"ember":
				name = "fx_ember_%d" % (int(bit.age * 9.0) % 2)
			"smoke":
				name = "fx_smoke_%d" % mini(3, int(bit.age / bit.life * 4.0))
		var s: View.Sprite = game.pooled(bit.x, bit.y, name, bit.size, bit.z)
		s.glow = bit.kind == "ember"
		s.translucent = bit.kind == "smoke"
		s.spin = bit.spin
		# On the floor (rolling or still) the 3D view lays a shell on its side,
		# easing over onto it (settle) and rolling, flat once it rests.
		s.lying = bit.rest or (bit.vz == 0.0 and (bit.kind == "casing" or bit.kind == "hull"))
		if s.lying:
			s.settle = (
				minf(bit.age - bit.landed, View.SETTLED) if bit.landed >= 0.0 else View.SETTLED
			)
			s.roll = bit.roll
			if bit.rest:
				var flat := roundf(bit.roll / PI) * PI
				var done := smoothstep(0.0, ROLL_FLAT, bit.age - bit.rested)
				s.roll = lerpf(bit.roll, flat, done)
		out.append(s)
	return out


func ground_marks() -> Array:
	var out: Array = []
	var p := game.player
	for s: Array in scorches:
		var sx: float = s[0]
		var sy: float = s[1]
		if (sx - p.x) * (sx - p.x) + (sy - p.y) * (sy - p.y) < 100.0:
			var look: int = s[5]
			var picture := "mark_scorch_%d" % look
			var fading_at: float = s[7]
			if fading_at >= 0.0:
				picture = game.art.faded_art(picture, 1.0 - (game.clock - fading_at) / FADE)
			# The mark laid when it was made (on the deck or the ramp it is on).
			var mark: View.GroundMark = s[8]
			mark.image = picture
			out.append(mark)
	return out
