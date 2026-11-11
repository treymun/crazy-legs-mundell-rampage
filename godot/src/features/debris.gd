## What a fight leaves lying about: brass from the rifle, a revolver's six
## dumped on reload and the shotgun's red hulls, tinking where they land;
## embers and slow smoke rising off a blast and the black scorch it leaves;
## and a wounded varmint's trail of blood. All of it looks only: its own dice,
## never saved, never in the way. Lifetimes are effects.cfg [debris].
extends GameFeature

const GRAVITY := 9.0
const MAX_BITS := 90
const MAX_SCORCHES := 14


## One piece of debris in the air or on the ground.
class Bit:
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var vx := 0.0
	var vy := 0.0
	var vz := 0.0
	var age := 0.0
	var life := 1.0
	var kind := "casing"
	var rest := false
	var size := .05


var dice := RandomNumberGenerator.new()
var bits: Array = []
## [x, y, z, angle, size, frame, made at]
var scorches: Array = []
var _trail_next := 0.0


func id() -> String:
	return "debris"


func attach() -> void:
	dice.seed = 1987
	game.shot_fired.connect(_fired)
	game.gun_reloading.connect(_reloading)
	game.exploded.connect(_exploded)
	game.ticked.connect(_tick)


func _life(key: String, fallback: float) -> float:
	return float(Effects.DEBRIS.get(key, fallback))


## Out of the gun's right side, tumbling.
func _eject(kind: String, count: int, spread := 1.0) -> void:
	var p = game.player
	var a: float = p.view_angle()
	for k in count:
		var bit := Bit.new()
		bit.kind = kind
		bit.size = .07 if kind == "hull" else .05
		bit.x = p.x + cos(a) * .25 - sin(a) * .12
		bit.y = p.y + sin(a) * .25 + cos(a) * .12
		bit.z = p.eye - .22
		var out := dice.randf_range(.9, 1.6) * spread
		bit.vx = -sin(a) * out + cos(a) * dice.randf_range(-.3, .4)
		bit.vy = cos(a) * out + sin(a) * dice.randf_range(-.3, .4)
		bit.vz = dice.randf_range(1.2, 2.2)
		bit.life = _life("case_life", 7.0)
		_add(bit)


func _add(bit: Bit) -> void:
	bits.append(bit)
	if bits.size() > MAX_BITS:
		bits.pop_front()


func _fired(gun: int) -> void:
	if gun == Weapons.RIFLE or gun == Weapons.RIVETER:
		_eject("casing", 1)


func _reloading(gun: int) -> void:
	if gun == Weapons.REVOLVER:
		_eject("casing", 6, .4)
	elif gun == Weapons.SHOTGUN:
		_eject("hull", 2, .7)


func _exploded(x: float, y: float, z: float, energy: bool) -> void:
	if energy:
		return
	var floor_z: float = game.world.elevation(x, y)
	if z - floor_z < 1.2:
		scorches.append(
			[
				x,
				y,
				floor_z + .004,
				dice.randf_range(0, TAU),
				dice.randf_range(.75, 1.05),
				dice.randi_range(0, 2),
				game.clock
			]
		)
		if scorches.size() > MAX_SCORCHES:
			scorches.pop_front()
	for k in int(Effects.DEBRIS.get("embers", 7)):
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
	for k in int(Effects.DEBRIS.get("smoke_puffs", 3)):
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
	var kept: Array = []
	for bit: Bit in bits:
		bit.age += dt
		if bit.age >= bit.life:
			continue
		kept.append(bit)
		if bit.rest:
			continue
		match bit.kind:
			"ember":
				# Floats up, drifts, burns out.
				bit.vz -= .4 * dt
				bit.vx *= 1.0 - dt
				bit.vy *= 1.0 - dt
			"smoke":
				bit.size += dt * .35
			_:
				bit.vz -= GRAVITY * dt
		var nx := bit.x + bit.vx * dt
		var ny := bit.y + bit.vy * dt
		if game.world.blocked(nx, ny, .02):
			bit.vx *= -.4
			bit.vy *= -.4
		else:
			bit.x = nx
			bit.y = ny
		bit.z += bit.vz * dt
		var floor_z: float = game.world.elevation(bit.x, bit.y)
		if bit.z <= floor_z and (bit.kind == "casing" or bit.kind == "hull"):
			bit.z = floor_z
			if bit.vz < -1.2:
				bit.vz *= -.35
				bit.vx *= .5
				bit.vy *= .5
				game.sound_at("casing_tink", bit.x, bit.y, .22 if bit.kind == "casing" else .12)
			else:
				bit.rest = true
	bits = kept
	while (
		not scorches.is_empty() and game.clock - float(scorches[0][6]) > _life("scorch_life", 60.0)
	):
		scorches.pop_front()
	_trails()


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
				Enemy.PLASMA.has(e.kind)
			)


func sprites() -> Array:
	var out: Array = []
	for bit: Bit in bits:
		var name := "fx_casing"
		match bit.kind:
			"hull":
				name = "fx_hull"
			"ember":
				name = "fx_ember_%d" % (int(bit.age * 9.0) % 2)
			"smoke":
				name = "fx_smoke_%d" % mini(3, int(bit.age / bit.life * 4.0))
		var s := Renderer.Sprite.new(bit.x, bit.y, name, bit.size, bit.z)
		s.glow = bit.kind == "ember"
		s.translucent = bit.kind == "smoke"
		out.append(s)
	return out


func ground_marks() -> Array:
	var out: Array = []
	var p = game.player
	for s: Array in scorches:
		if (
			(float(s[0]) - p.x) * (float(s[0]) - p.x) + (float(s[1]) - p.y) * (float(s[1]) - p.y)
			< 100.0
		):
			out.append(
				Renderer.GroundMark.new(
					s[0], s[1], s[2], s[3], s[4], s[4], "mark_scorch_%d" % int(s[5])
				)
			)
	return out
