## What the local player feels through a pad's motors or a phone (src/rumble_out.gd
## drives them, data/tuning/rumble.cfg has every number): each gun's shot
## its own way, a melee blow landing and the rip saw's grind, the dynamite's
## match and throw, a hurt leaning to the side it came from, the boot landing,
## a blast by how near, a hard landing by how far the feet dropped, a
## vehicle's engine, bumps, crashes and ledges, the bosses' moments, and
## anything else that shakes the screen (a boss's slam, a barn coming down).
##
## Looks only, like the screen shake and the sound: it listens to the game's
## events and reads the game, never writes it, has no dice, keeps nothing in
## a save or a snapshot. Only the local player's doings and hurts count
## (game.acting_local()), never whoever acts during the tick. A pulse is
## made as it happens and aged by the frames (mix(), from the front end), so
## a held game holds no rumble: the front end hushes it (pause, menus, the
## down screen, the window put away).
extends GameFeature

const Brawl := preload("res://src/features/brawl.gd")
const VehiclesScript := preload("res://src/features/vehicles.gd")


## One pulse: the motors' strengths at full, how long, how old; `what` made it
## (tools/rumble_check.gd reads it); a quake mixes by the bigger, not added.
class Pulse:
	extends RefCounted
	var what := ""
	var weak := 0.0
	var strong := 0.0
	var length := 0.0
	var age := 0.0
	var quake := false


var pulses: Array[Pulse] = []
## The pulses begun since the front end last took them (a phone buzzes for
## the strongest of them).
var fresh: Array[Pulse] = []
## Held while it lasts (a vehicle's engine): weak, strong; set each tick.
var bed := Vector2.ZERO
## Every pulse made, for a tool (off in play).
var keep_made := false
var made: Array[Pulse] = []

## A hurt waiting for its heading (game.damage_feedback is set after
## player_hurt is said).
var _blow := 0.0
## The screen's shake as last seen, and the rises of it this feature knows
## the cause of since (a gun's, a hurt's, a blast's: pulses of their own).
var _shake := 0.0
var _known := 0.0
## A fall: whether the feet are off the ground falling, and the highest.
var _aloft := false
var _peak := 0.0
## The dynamite: the gun held, its shot age and fuse as last seen.
var _gun := -1
var _age := 0.0
var _fuse := 0.0
## The boot: the kick last seen begun, brawl's counts then, whether its landing
## was felt; the finisher's blow last felt.
var _kick := -10.0
var _kicks := 0
var _doors := 0
var _kick_felt := true
var _finish := -10.0
## The vehicle ridden (-1: none) and how it was last tick.
var _ride := -1
var _ride_speed := 0.0
var _ride_bumps := 0
var _ride_z := 0.0
var _ride_fall := 0.0
var _kerb_at := 0.0
var _started := false


func id() -> String:
	return "rumble"


func attach() -> void:
	game.events.shot_fired.connect(_fired)
	game.events.traced.connect(_traced)
	game.events.player_hurt.connect(_hurt)
	game.events.exploded.connect(_exploded)
	game.events.boss_intro.connect(_boss.bind("intro"))
	game.events.boss_enraged.connect(_boss.bind("enraged"))
	game.events.boss_phase.connect(func(e: Enemy, _phase: int) -> void: _boss(e, "phase"))
	game.events.boss_staggered.connect(_boss.bind("staggered"))
	game.events.boss_weak_hit.connect(_boss.bind("weak_hit"))
	game.events.boss_down.connect(func(e: Enemy, _seconds: float) -> void: _boss(e, "down"))
	tick_with(_tick)


## A pulse of `p` (weak, strong, seconds) times `k`, named `what`.
func add(what: String, p: Vector3, k := 1.0, quake := false) -> void:
	if p.z <= 0.0 or k <= 0.0 or (p.x <= 0.0 and p.y <= 0.0):
		return
	var pulse := Pulse.new()
	pulse.what = what
	pulse.weak = p.x * k
	pulse.strong = p.y * k
	pulse.length = p.z
	pulse.quake = quake
	pulses.append(pulse)
	fresh.append(pulse)
	if keep_made:
		made.append(pulse)
	var most := int(RumbleData.num("all", "pulses_most", 24.0))
	while pulses.size() > maxi(1, most):
		pulses.pop_front()
	while fresh.size() > maxi(1, most):
		fresh.pop_front()


## The motors now (weak, strong, at FULL), the pulses aged `dt`: the pulses
## and the engine's hum added up to the caps, a quake by the bigger.
func mix(dt: float) -> Vector2:
	_settle()
	var hold := RumbleData.num("all", "hold", .35)
	var sum := bed
	var quake := Vector2.ZERO
	var kept: Array[Pulse] = []
	for pulse: Pulse in pulses:
		if pulse.age >= pulse.length:
			continue
		var t := pulse.age / pulse.length
		var level := 1.0 if t < hold else clampf((1.0 - t) / maxf(.01, 1.0 - hold), 0.0, 1.0)
		var at := Vector2(pulse.weak, pulse.strong) * level
		if pulse.quake:
			quake = quake.max(at)
		else:
			sum += at
		pulse.age += dt
		if pulse.age < pulse.length:
			kept.append(pulse)
	pulses = kept
	sum.x = minf(sum.x, RumbleData.num("all", "cap_weak", 1.0))
	sum.y = minf(sum.y, RumbleData.num("all", "cap_strong", 1.0))
	return sum.max(quake)


## The pulses begun since this was last asked.
func take_fresh() -> Array[Pulse]:
	var out := fresh
	fresh = []
	return out


## Nothing to feel now (the game held, a menu, the down screen): every pulse
## and the hum dropped.
func hush() -> void:
	pulses.clear()
	fresh.clear()
	bed = Vector2.ZERO
	_blow = 0.0


# ------------------------------------------------------------------ guns


func _fired(gun: int) -> void:
	if game.own_quiet:
		game.hands_watch.defer(_fired.bind(gun), "shot")
		return
	if not game.acting_local():
		return
	var arms: Weapons.Armory = game.armory
	if gun == Weapons.RIPSAW and arms.grinding:
		add("grind", RumbleData.pulse("melee", "grind"))
	else:
		var pair := RumbleData.num("all", "pair", 1.35) if arms.last_spent == 2 else 1.0
		add("gun:" + str(Weapons.NAMES[gun]), RumbleData.gun(gun), pair)
	var shake_by: float = Weapons.SHAKE.get(gun, 0.0)
	_known += shake_by * maxf(1, arms.last_spent)


## An online client's own shot shown ahead of the game (net_shot_predict.gd).
func own_shot(gun: int) -> void:
	_fired(gun)


## A swing (or the rip saw's teeth) that met something.
func _traced(end: Vector3, struck: String) -> void:
	if game.own_quiet:
		game.hands_watch.defer(_traced.bind(end, struck), "trace")
		return
	if struck == "air" or not game.acting_local():
		return
	var arms: Weapons.Armory = game.armory
	var gun: int = arms.active
	if gun == Weapons.RIPSAW and arms.grinding:
		if struck == "enemy":
			add("bite", RumbleData.pulse("melee", "bite"))
		return
	var how: Dictionary = Weapons.FIRING[gun]
	if str(how.get("fire", "")) != "melee":
		return
	var share := 1.0 if struck == "enemy" else RumbleData.num("melee", "wall", .6)
	add(
		"melee:" + str(Weapons.NAMES[gun]),
		RumbleData.pulse("melee", str(Weapons.NAMES[gun])),
		share
	)


func own_trace(end: Vector3, struck: String) -> void:
	_traced(end, struck)


# ------------------------------------------------------------------ hurts


func _hurt(amount: float, _cause: String) -> void:
	if not game.acting_local():
		return
	_blow = maxf(_blow, amount)
	_known += minf(.55, amount / 40.0)  # what game_world.gd damage() shakes


## The hurt waiting, now its heading is known: leaning to the motor on the
## side it came from (a pad's strong motor is in its left grip).
func _settle() -> void:
	if _blow <= 0.0:
		return
	var amount := _blow
	_blow = 0.0
	var full := RumbleData.num("hurt", "full", 30.0)
	var k := clampf(amount / maxf(1.0, full), RumbleData.num("hurt", "least", .25), 1.0)
	var side := 0.0
	var feedback: Variant = game.damage_feedback
	var heading: Variant = null
	if feedback is Array:
		var said: Array = feedback
		heading = said[0] if not said.is_empty() else null
	if heading != null:
		var from_angle: float = heading
		var turn := fposmod(from_angle - game.local_player.view_angle() + PI, TAU) - PI
		side = sin(turn)  # + from the right
	var lean := RumbleData.num("hurt", "lean", .5) * side
	var p := RumbleData.pulse("hurt", "pulse")
	var length := p.z * (.6 + .4 * k)
	add("hurt", Vector3(p.x * (1.0 + lean), p.y * (1.0 - lean), length), k)


# ----------------------------------------------------------------- blasts


func _exploded(x: float, y: float, _z: float, energy: bool) -> void:
	if game.blast_quiet:
		return  # shown already by an online client's own blast (net_own_shots.gd)
	var ear := game.local_player
	var d := Vector2(ear.x - x, ear.y - y).length()
	_known += maxf(0.0, 1.0 - d / 9.0) * (.45 if energy else .9)  # explode()'s shake
	if ear.health <= 0:
		return
	var spec := Shots.blast(game.blast_kind if game.blast_kind != "" else "tnt")
	var radius: float = spec["radius"]
	var size := clampf(
		radius / maxf(.1, RumbleData.num("blast", "radius", 2.8)),
		RumbleData.num("blast", "size_least", .6),
		RumbleData.num("blast", "size_most", 1.4)
	)
	var reach := RumbleData.num("blast", "reach", 16.0) * size
	if d >= reach:
		return
	var near := pow(1.0 - d / reach, RumbleData.num("blast", "falloff", 1.6))
	var k := near * size * (RumbleData.num("blast", "energy", .6) if energy else 1.0)
	var p := RumbleData.pulse("blast", "pulse")
	var short := RumbleData.num("blast", "short", .4)
	p.z *= lerpf(short, 1.0, near)
	add("blast", p, k)


# ----------------------------------------------------------------- bosses


func _boss(_e: Enemy, moment: String) -> void:
	if game.local_player.health <= 0:
		return
	add("boss:" + moment, RumbleData.pulse("boss", moment))


# ------------------------------------------------------------- each tick


func _tick(dt: float) -> void:
	var p := game.local_player
	if p == null:
		return
	if not _started:
		_started = true
		_first(p)
	_settle()
	_quake(dt)
	if p.health <= 0:
		_aloft = false
		bed = Vector2.ZERO
		return
	_landing(p)
	_dynamite(p)
	_boot(p)
	_vehicle(p, dt)


## What was so before this feature looked: never felt as new.
func _first(p: Player) -> void:
	_shake = game.shake
	_gun = p.armory.active
	_age = p.armory.shot_age
	_fuse = p.armory.fuse
	var b: Brawl = game.features.get("brawl")
	if b != null:
		_kick = b.kicked_at.get(p.slot, -10.0)
		var last: Array = b.last_moves.get(p.slot, [])
		if not last.is_empty():
			_finish = last[1]


## A rise of the screen's shake nothing above made: a quake.
func _quake(dt: float) -> void:
	var expect := maxf(0.0, _shake - dt * 1.7) + _known  # game.gd's tick eases it 1.7 a second
	var rise := game.shake - expect
	_shake = game.shake
	_known = 0.0
	if rise < RumbleData.num("quake", "from", .08) or game.local_player.health <= 0:
		return
	var p := Vector3(
		RumbleData.num("quake", "weak", .45),
		RumbleData.num("quake", "strong", 1.0),
		RumbleData.num("quake", "seconds", .3)
	)
	add("quake", p, minf(1.0, rise), true)


## Down from a fall: by how far the feet dropped (game.feel_landed, the step's
## own landing; a ladder's is not one).
func _landing(p: Player) -> void:
	var feet := p.floor_z + p.air
	if p.air > 0.0 and p.vertical_speed != 0.0:
		_peak = maxf(_peak, feet) if _aloft else feet
		_aloft = true
		return
	if _aloft and game.feel_landed:
		var drop := _peak - p.floor_z
		var from := RumbleData.num("land", "from", .7)
		if drop >= from:
			var full := RumbleData.num("land", "full", 3.5)
			var k := clampf((drop - from) / maxf(.01, full - from), 0.0, 1.0)
			k = lerpf(RumbleData.num("land", "least", .2), 1.0, k)
			add("land", RumbleData.pulse("land", "pulse"), k)
	if p.air <= 0.0:
		_aloft = false


## The dynamite's match struck and the stick let go (not a shot_fired).
func _dynamite(p: Player) -> void:
	var arms := p.armory
	if arms.active == Weapons.DYNAMITE and _gun == Weapons.DYNAMITE:
		if arms.fuse > 0.0 and _fuse <= 0.0:
			add("tnt:light", RumbleData.pulse("dynamite", "light"))
		if arms.shot_age < _age:
			add("tnt:throw", RumbleData.pulse("dynamite", "throw"))
	_gun = arms.active
	_age = arms.shot_age
	_fuse = arms.fuse


## USE's boot as it lands (on a man, into the air, a door) and a finisher's
## blow, as brawl_looks.gd jolts the view for them.
func _boot(p: Player) -> void:
	var b: Brawl = game.features.get("brawl")
	if b == null:
		return
	var at: float = b.kicked_at.get(p.slot, -10.0)
	if at != _kick:
		_kick = at
		_kicks = b.kicks
		_doors = b.doors
		_kick_felt = false
	if not _kick_felt:
		var lands: float = Brawl.KICK["land"]
		var since := game.clock - at
		if b.doors > _doors:
			_kick_felt = true
			add("boot:door", RumbleData.pulse("boot", "door"))
		elif b.kicks > _kicks:
			_kick_felt = true
			add("boot:hit", RumbleData.pulse("boot", "hit"))
		elif since >= lands + .05:
			_kick_felt = true
			add("boot:miss", RumbleData.pulse("boot", "miss"))
	var last: Array = b.last_moves.get(p.slot, [])
	if last.is_empty():
		return
	var move: String = last[0]
	var started: float = last[1]
	var wind: float = Brawl.FINISH["wind"]
	if started != _finish and game.clock - started >= wind:
		_finish = started
		add("finish:" + move, RumbleData.pulse("boot", "stomp" if move == "stomp" else "finish"))


## In a vehicle: the engine's hum held while it runs (by the speed), the
## mower's cylinder, the airboat on the chop, rough ground; a wall struck, a
## kerb, a ledge, the tank going up.
func _vehicle(p: Player, dt: float) -> void:
	var rides: VehiclesScript = game.features.get("vehicles")
	var at := Vector2i(-1, -1)
	if rides != null and not rides.rides.is_empty():
		at = rides.seat_of(p)
	if at.x < 0:
		if _ride >= 0 and rides != null and _ride < rides.rides.size():
			var left: VehicleDrive.Ride = rides.rides[_ride]
			if left.wreck >= 0.0 and game.clock - left.wreck < .5:
				var was := RumbleData.vehicle_section(left.kind)
				add("vehicle:wreck", RumbleData.pulse(was, "wreck"))
		_ride = -1
		bed = Vector2.ZERO
		return
	var v: VehicleDrive.Ride = rides.rides[at.x]
	var s := VehicleDrive.spec(v.kind)
	var row := RumbleData.vehicle_section(v.kind)
	var speed := VehicleDrive.speed(v)
	if at.x != _ride:
		_ride = at.x
		_ride_speed = speed
		_ride_bumps = v.bumps
		_ride_z = v.z
		_ride_fall = 0.0
	var share := clampf(speed / maxf(1.0, s.top), 0.0, 1.0)
	var hum := Vector2.ZERO
	if v.wreck < 0.0 and v.seats[0] >= 0:
		hum = RumbleData.pair(row, "idle").lerp(RumbleData.pair(row, "top"), share)
		var chug_hz := RumbleData.num(row, "chug_hz")
		if chug_hz > 0.0 and fposmod(game.clock * chug_hz, 1.0) < .35:
			hum.y += RumbleData.num(row, "chug")
		var chop_hz := RumbleData.num(row, "chop_hz")
		if chop_hz > 0.0:
			hum.x += (
				RumbleData.num(row, "chop") * share * (.5 + .5 * sin(game.clock * TAU * chop_hz))
			)
		hum.x += RumbleData.num(row, "rough") * (s.rough + s.rough_off * .5) * share
	bed = hum
	if v.bumps != _ride_bumps:
		var struck := _ride_speed
		if struck >= RumbleData.num(row, "crash_from", 5.0):
			add("vehicle:crash", RumbleData.pulse(row, "crash"))
		elif struck >= RumbleData.num(row, "bump_from", 1.0):
			var full := RumbleData.num(row, "bump_full", 8.0)
			add("vehicle:bump", RumbleData.pulse(row, "bump"), clampf(struck / full, .25, 1.0))
	var dz := v.z - _ride_z
	if dz > VehicleFeel.BUMP_FROM and dt > 0.0 and game.clock >= _kerb_at:
		_kerb_at = game.clock + RumbleData.num(row, "kerb_gap", .2)
		add("vehicle:kerb", RumbleData.pulse(row, "kerb"))
	if dz < -.0005 and dt > 0.0:
		_ride_fall = minf(_ride_fall, dz / dt)
	elif _ride_fall < -VehicleFeel.LAND_FROM:
		var hard := clampf(-_ride_fall / maxf(.1, RumbleData.num(row, "land_full", 4.0)), .25, 1.0)
		add("vehicle:land", RumbleData.pulse(row, "land"), hard)
		_ride_fall = 0.0
	else:
		_ride_fall = 0.0
	_ride_speed = speed
	_ride_bumps = v.bumps
	_ride_z = v.z
