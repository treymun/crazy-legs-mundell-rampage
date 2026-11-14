## How a hit on one of the county reads (src/hit_zones.gd is the play): the
## sound of what it struck (a wet slap on a body, a rubbery thump on a shell,
## a ping or a clang and sparks off tin), the hat knocked off a head and
## tumbling down (tumble.gd), a head shot that kills popping, now and then a
## HEADSHOT! call, the crosshair's head mark, and a dropped weapon flying to
## where the play put it and lying there till its hand picks it up. All looks
## and sound, its own dice; nothing saved.
extends GameFeature

## Hats and dropped weapons at once; the oldest goes when more come.
const MAX_BITS := 24
## Seconds a hat lies before it goes (a weapon goes when it is picked up, or
## lies this long when its hand died first).
const LIFE := 40.0
## Each kind's hat (fx_hat_<name>_<0|1>: side on, tipped), and how tall.
const HATS := {
	"clone": "straw",
	"barker": "straw",
	"coot": "felt",
	"yard_deputy": "black",
	"billy": "grey",
	"chain_hand": "tan",
	"bottle_tosser": "green",
	"nitro_huffer": "green",
	"chum_tosser": "red",
	"pit_mechanic": "red",
	"flagman": "red",
	"valve_rat": "brown",
	"noodler": "brown",
	"millhand": "dark",
	"boilerback": "dark",
	"drone": "helmet",
	"tin_guard": "helmet",
}
const HAT_SIZE := {"straw": .13, "felt": .12, "black": .12, "helmet": .14}
const CAP_SIZE := .09
## A dropped weapon's picture (fx_drop_<held>) and how tall it lies.
const DROP_SIZE := {"long": .07, "pistol": .07, "tool": .07}
## Seconds a dropped weapon takes to land where it lies.
const DROP_FLIGHT := .42
## Seconds between HEADSHOT! calls (the first one comes at once).
const CALL_GAP := 24.0
## Seconds between the struck sounds (a load of buckshot is one sound).
const SOUND_GAP := .07
const SPECK_CAP := 170


class Bit:
	extends Tumble.Body
	var image := ""
	var size := .1
	var flip := false
	var age := 0.0
	var turn := 0.0
	## A dropped weapon: whose it is, where it flies from and lands.
	var owner: Enemy = null
	var start := Vector3.ZERO
	var land := Vector3.ZERO


var dice := RandomNumberGenerator.new()
var bits: Array = []
var _feel := Tumble.Feel.new(.05, .35, .32, 3.2)
var _sound_next := 0.0
var _call_at := -1000.0
var _pops := 0


func id() -> String:
	return "hit_reads"


func attach() -> void:
	dice.seed = hash(game.level.id) + 4021
	_feel.grip = .5
	_feel.hard = 1.4
	game.ticked.connect(_tick)


## How many heads popped this game (tools read it).
func pops() -> int:
	return _pops


## A player's hit with a zone landed (HitZones.land): its sound, its sparks,
## and a hat off on the head.
func landed(e: Enemy, amount: float) -> void:
	var floor_z: float = game.world.stand(e) + e.z
	var tall: float = e.height * e.variant
	var head := e.last_zone == "head"
	var metal := HitZones.metal(e)
	var at_z := floor_z + tall * (.9 if head else .56)
	if head and game.hit_feedback:
		game.hit_mark_head = true
	if game.clock >= _sound_next:
		_sound_next = game.clock + SOUND_GAP
		game.sound_at(_cue(e, amount, head), e.x, e.y, .62 if metal else .4)
	if metal:
		sparks(e.x, e.y, at_z, 6 if amount >= 20.0 else 3, 1.6)
	if head and HATS.has(e.kind) and not e.hatless:
		e.hatless = true
		_hat_off(e, floor_z + tall)
	if head and not e.alive and not BossKit.is_boss(e):
		# A boss's fall is its own moment (Enemy._boss_falls).
		_pop(e, floor_z + tall * .9, metal)


## What a hit on it sounds like: metal pings or clangs, a helmet rings, a shell
## thumps, a body slaps.
func _cue(e: Enemy, amount: float, head: bool) -> String:
	if HitZones.metal(e):
		return "tailgate_clang" if amount >= 30.0 else "ricochet_tin"
	if head and String(HATS.get(e.kind, "")) == "helmet":
		return "ricochet"
	if Enemy.SHELL_ACTORS.has(e.kind):
		return "impact_rubber"
	return "gib_splat" if game.gore else "body_thud"


## Sparks off the feature's own dice (no game.rng).
func sparks(x: float, y: float, z: float, count: int, speed: float) -> void:
	_specks(x, y, z, "spark", count, speed, 0.0)


func _specks(
	x: float, y: float, z: float, kind: String, count: int, speed: float, up: float
) -> void:
	for _i in count:
		if game.specks.size() >= SPECK_CAP:
			return
		var a := dice.randf() * TAU
		var v := dice.randf_range(.24, speed)
		game.specks.append(
			GameState.Speck.new(
				x,
				y,
				z,
				cos(a) * v,
				sin(a) * v,
				up + dice.randf_range(.2, speed * 1.3),
				dice.randf_range(.18, .6),
				kind
			)
		)


## A head shot that kills: the head pops (a spray up off it, a wet pop or a
## ringing helmet) and, now and then, the call.
func _pop(e: Enemy, z: float, metal: bool) -> void:
	_pops += 1
	var kind := "spark" if metal else "plasma" if Enemy.PLASMA.has(e.kind) else "gore"
	if kind != "gore" or game.gore:
		_specks(e.x, e.y, z, kind, 14, 1.4, 1.2)
	var helmet := String(HATS.get(e.kind, "")) == "helmet"
	game.sound_at("ricochet" if helmet or metal else "skeeter_pop", e.x, e.y, .75)
	if (
		game.barks.enabled
		and game.clock - _call_at >= CALL_GAP
		and game.callout_until <= game.clock
	):
		_call_at = game.clock
		game.callout = "HEADSHOT!"
		game.callout_until = game.clock + 1.1


## The hat comes off the top of its head and tumbles away from the gun.
func _hat_off(e: Enemy, top: float) -> void:
	var hat := String(HATS[e.kind])
	var b := Bit.new()
	b.image = "fx_hat_" + hat
	b.size = float(HAT_SIZE.get(hat, CAP_SIZE))
	var away := atan2(e.y - game.hit_from.y, e.x - game.hit_from.x) + dice.randf_range(-.5, .5)
	var speed := dice.randf_range(1.1, 2.1)
	b.x = e.x
	b.y = e.y
	b.z = top - b.size * .4
	b.vx = cos(away) * speed
	b.vy = sin(away) * speed
	b.vz = dice.randf_range(2.2, 3.2)
	b.flip = dice.randf() < .5
	_add(b)


## The weapon an arm hit made it drop flies from its hand to `spot`, where the
## play has it lie (HitZones._drop).
func drop_arm(e: Enemy, held: String, spot: Vector2) -> void:
	var b := Bit.new()
	b.image = "fx_drop_" + held
	b.size = float(DROP_SIZE.get(held, .07))
	b.owner = e
	b.start = Vector3(e.x, e.y, game.world.stand(e) + e.z + e.height * .5)
	b.land = Vector3(spot.x, spot.y, game.world.elevation(spot.x, spot.y))
	b.x = b.start.x
	b.y = b.start.y
	b.z = b.start.z
	b.flip = spot.x < e.x
	_add(b)


## Its hand has it again: it goes from the ground.
func picked_up(e: Enemy) -> void:
	for b: Bit in bits:
		if b.owner == e:
			bits.erase(b)
			game.sound_at("pickup", e.x, e.y, .35)
			return


func _add(b: Bit) -> void:
	bits.append(b)
	if bits.size() > MAX_BITS:
		bits.pop_front()


func _tick(dt: float) -> void:
	if bits.is_empty():
		return
	var gone: Array = []
	for b: Bit in bits:
		b.age += dt
		if b.owner != null:
			_fly(b, dt)
			if b.owner.alive and b.owner.disarmed_until < 0.0:
				gone.append(b)
			elif b.age > LIFE:
				gone.append(b)
			continue
		if b.age > LIFE:
			gone.append(b)
			continue
		if b.rest:
			continue
		var hit := Tumble.step(game.world, b, _feel, dt)
		if hit & Tumble.RESTED:
			b.rest = true
		if b.vz != 0.0:
			# Turning over as it flies.
			b.turn += dt
			if b.turn > .09:
				b.turn = 0.0
				b.flip = not b.flip
	for b: Bit in gone:
		bits.erase(b)


## A dropped weapon on its way down: a short arc, then it lies where it landed.
func _fly(b: Bit, dt: float) -> void:
	var t := minf(1.0, b.age / DROP_FLIGHT)
	b.x = lerpf(b.start.x, b.land.x, t)
	b.y = lerpf(b.start.y, b.land.y, t)
	b.z = lerpf(b.start.z, b.land.z, t) + sin(t * PI) * .35
	if t < 1.0:
		b.turn += dt
		if b.turn > .08:
			b.turn = 0.0
			b.flip = not b.flip
	elif not b.rest:
		b.rest = true
		game.sound_at("tnt_bounce", b.x, b.y, .5)


func sprites() -> Array:
	var out: Array = []
	for b: Bit in bits:
		if not game.in_view(b.x, b.y, b.size + .3):
			continue
		var cel := 0 if b.rest or b.owner != null else int(b.age * 11.0) % 2
		var name := b.image if b.owner != null else "%s_%d" % [b.image, cel]
		var s: Renderer.Sprite = game.pooled(b.x, b.y, name, b.size, b.z)
		s.flip = b.flip
		out.append(s)
	return out
