## What every gun throws between its muzzle and its mark, and what its shots
## shed in the air: a hot streak off the .38 and the ranch rifle, burning
## wadding out of the sawed-off, a glowing rivet, the Copperhead's jet of
## steam, the teat gun's stream of milk (a splash and a puddle where it lands),
## sparks and chips off a swing, fuse sparks and smoke off dynamite, kegs and
## bottle rockets, the arm gun's green motes, dust off a bowling ball, a cow
## leaking milk on its way; and the dirt, cinders and dust ring of a blast.
## All of it looks only: its own dice, never saved, never in the way.
extends GameFeature

const MAX_BITS := 240
const MAX_PUDDLES := 22
const PUDDLE_LIFE := 45.0


## One speck of it in the air.
class Bit:
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var vx := 0.0
	var vy := 0.0
	var vz := 0.0
	## Below zero: not out yet (a drop further back in a stream).
	var age := 0.0
	var life := 1.0
	var kind := ""
	var size := .05
	var grow := 0.0
	var gravity := 0.0
	var rest := false
	var trail := 0.0


var dice := RandomNumberGenerator.new()
var bits: Array = []
## [x, y, z, angle, size, frame, made at]
var puddles: Array = []
## Shot instance id -> [next trail time, bounces seen]
var _following := {}
var _pellets := 0
var _puddle_next := 0.0


func id() -> String:
	return "weapon_fx"


func attach() -> void:
	dice.seed = 2001
	game.shot_fired.connect(_fired)
	game.traced.connect(_traced)
	game.exploded.connect(_exploded)
	game.ticked.connect(_tick)


func _add(bit: Bit) -> Bit:
	bits.append(bit)
	if bits.size() > MAX_BITS:
		bits.pop_front()
	return bit


func _bit(kind: String, at: Vector3, v: Vector3, life: float, size: float, gravity := 0.0) -> Bit:
	var bit := Bit.new()
	bit.kind = kind
	bit.x = at.x
	bit.y = at.y
	bit.z = at.z
	bit.vx = v.x
	bit.vy = v.y
	bit.vz = v.z
	bit.life = life
	bit.size = size
	bit.gravity = gravity
	return _add(bit)


## Where a shot leaves the gun, in the world: ahead, a little right and low.
func _muzzle() -> Vector3:
	var p = game.player
	var a: float = p.view_angle()
	return Vector3(
		p.x + cos(a) * .42 - sin(a) * .11, p.y + sin(a) * .42 + cos(a) * .11, p.eye - .17
	)


func _forward() -> Vector3:
	var a: float = game.player.view_angle()
	return Vector3(cos(a), sin(a), 0.0)


func _scatter(speed: float, up: float) -> Vector3:
	var a := dice.randf_range(0, TAU)
	var v := dice.randf_range(.3, 1.0) * speed
	return Vector3(cos(a) * v, sin(a) * v, dice.randf_range(.2, 1.0) * up)


# ------------------------------------------------------------------ firing


func _fired(gun: int) -> void:
	_pellets = 0
	var from := _muzzle()
	var ahead := _forward()
	if gun == Weapons.SHOTGUN:
		# Burning wadding and powder thrown out ahead of the barrels.
		for _k in 3:
			var v := ahead * dice.randf_range(6.0, 9.5) + _scatter(1.4, 1.2)
			_bit("ember", from + ahead * .6, v, dice.randf_range(.45, .8), .035, 6.0)


func _traced(end: Vector3, struck: String) -> void:
	var gun: int = game.armory.active
	match gun:
		Weapons.REVOLVER:
			_streak("tracer", end, 66.0, .04)
		Weapons.RIFLE:
			_streak("tracer", end, 72.0, .032)
		Weapons.SHOTGUN:
			_pellets += 1
			if _pellets <= 6:
				_streak("tracer", end, 58.0, .022)
		Weapons.RIVETER:
			_streak("rivet", end, 44.0, .05)
			if struck.begins_with("wall:"):
				_sparks(end, 7, 2.2)
		Weapons.PRESSURE:
			_jet(end, struck)
		Weapons.TEAT:
			_milk(end, struck)
		Weapons.CROWBAR, Weapons.SLING:
			if struck.begins_with("wall:"):
				_strike(end, struck.substr(5), 1.0)
		Weapons.RIPSAW:
			if struck.begins_with("wall:"):
				_strike(end, struck.substr(5), .6)


## A fast hot speck from the muzzle to the mark, drawn with a short tail. It
## starts a cell out: any nearer, a sprite fills the lens.
func _streak(kind: String, end: Vector3, speed: float, size: float) -> void:
	var from := _muzzle()
	var way := end - from
	var far := way.length()
	if far < 1.6:
		return
	var start := from + way / far * 1.1
	_bit(kind, start, way / far * speed, (far - 1.1) / speed, size)


func _sparks(at: Vector3, count: int, speed: float) -> void:
	var back := at - _forward() * .06
	for _k in count:
		_bit("spark", back, _scatter(speed, speed * .9), dice.randf_range(.18, .4), .035, 7.0)


## A swing or the saw meeting a wall: sparks off metal, chips off wood,
## grit and a puff of dust off anything else.
func _strike(at: Vector3, surface: String, amount: float) -> void:
	var back := at - _forward() * .08
	match surface:
		"metal":
			_sparks(at, int(7 * amount), 2.4)
		"wood":
			for _k in int(5 * amount):
				_bit("chip", back, _scatter(1.8, 1.6), dice.randf_range(.5, .9), .05, 8.0)
		_:
			for _k in int(4 * amount):
				_bit("clod", back, _scatter(1.4, 1.2), dice.randf_range(.4, .7), .035, 8.0)
			var dust := _bit("dust", back, Vector3(0, 0, .2), .45, .14)
			dust.grow = .6


## The Copperhead: a jet of steam all the way to the mark, a cloud where it hits.
func _jet(end: Vector3, struck: String) -> void:
	var from := _muzzle()
	var way := end - from
	var far := way.length()
	var count := clampi(int(far / .4), 3, 16)
	for k in count:
		var f := (k + 1.0) / count
		if f * far < .9:
			continue
		var puff := _bit(
			"steam",
			from + way * f,
			Vector3(dice.randf_range(-.15, .15), dice.randf_range(-.15, .15), .35),
			.55,
			.16 + f * .2
		)
		puff.age = -f * far / 34.0
		puff.grow = 1.3
	if struck != "air":
		for _k in 3:
			var cloud := _bit("steam", end - way / maxf(far, .01) * .1, _scatter(.6, .6), .7, .3)
			cloud.age = -far / 34.0
			cloud.grow = 1.4
		if struck == "wall:metal":
			_sparks(end, 4, 1.8)


## The teat gun: a stream of drops arcing to the mark, a splash, a puddle.
func _milk(end: Vector3, struck: String) -> void:
	var from := _muzzle()
	var arrive := 0.0
	var out := (end - from).normalized() * minf(.9, (end - from).length() * .5)
	for k in 8:
		var to := end + Vector3(dice.randf_range(-.05, .05), dice.randf_range(-.05, .05), 0)
		var start := (
			from + out + Vector3(dice.randf_range(-.03, .03), dice.randf_range(-.03, .03), 0)
		)
		var way := to - start
		var far := way.length()
		if far < .2:
			continue
		var speed := dice.randf_range(15.0, 19.0)
		var t := far / speed
		var v := way / t
		# Thrown a little high so the drop's fall brings it down on the mark.
		v.z += .5 * 2.6 * t
		var drop := _bit("milk", start, v, t, dice.randf_range(.045, .065), 2.6)
		drop.age = -k * .011
		arrive = maxf(arrive, t + k * .011)
	if struck == "air":
		return
	var back := end - (end - from).normalized() * .06
	var splash := _bit("splash", back, Vector3.ZERO, .26, .28)
	splash.age = -arrive
	for _k in 2:
		var spatter := _bit("drip", back, _scatter(1.1, 1.8) + Vector3(0, 0, .6), .55, .03, 9.0)
		spatter.age = -arrive
	# Milk runs down into a pool on the floor under where it struck.
	if game.clock >= _puddle_next:
		_puddle_next = game.clock + .3
		var px := back.x
		var py := back.y
		if not game.world.blocked(px, py, .05):
			puddles.append(
				[
					px + dice.randf_range(-.08, .08),
					py + dice.randf_range(-.08, .08),
					game.world.elevation(px, py) + .005,
					dice.randf_range(0, TAU),
					dice.randf_range(.22, .36),
					dice.randi_range(0, 2),
					game.clock
				]
			)
			if puddles.size() > MAX_PUDDLES:
				puddles.pop_front()


# --------------------------------------------------------------- explosions


func _exploded(x: float, y: float, z: float, energy: bool) -> void:
	var at := Vector3(x, y, z)
	var floor_z: float = game.world.elevation(x, y)
	if energy:
		for _k in 14:
			var mote := _bit("mote", at, _scatter(2.6, 1.2), dice.randf_range(.4, .75), .045)
			mote.gravity = -.6
		return
	# Dirt and grit thrown out in arcs.
	for _k in 8:
		var v := _scatter(3.4, 0.0)
		v.z = dice.randf_range(2.2, 4.4)
		_bit("clod", at, v, dice.randf_range(1.0, 1.6), dice.randf_range(.05, .08), 9.0)
	# Burning scraps that fall trailing smoke.
	for _k in 4:
		var v := _scatter(2.0, 0.0)
		v.z = dice.randf_range(2.0, 3.4)
		_bit("cinder", at, v, dice.randf_range(1.0, 1.5), .05, 6.0)
	# A ring of dust rolling out along the ground.
	if z - floor_z < 1.4:
		for k in 10:
			var a := k * TAU / 10.0 + dice.randf_range(-.15, .15)
			var ring := _bit(
				"dust",
				Vector3(x + cos(a) * .3, y + sin(a) * .3, floor_z + .1),
				Vector3(cos(a) * 3.0, sin(a) * 3.0, .15),
				.6,
				.22
			)
			ring.grow = 1.3


# --------------------------------------------------------------------- tick


func _tick(dt: float) -> void:
	_follow_shots()
	var kept: Array = []
	for bit: Bit in bits:
		bit.age += dt
		if bit.age >= bit.life:
			continue
		kept.append(bit)
		if bit.age < 0.0 or bit.rest:
			continue
		bit.size += bit.grow * dt
		bit.vz -= bit.gravity * dt
		match bit.kind:
			"steam", "smoke", "dust":
				bit.vx *= 1.0 - minf(1.0, dt * 3.0)
				bit.vy *= 1.0 - minf(1.0, dt * 3.0)
			"cinder":
				bit.trail -= dt
				if bit.trail <= 0.0:
					bit.trail = .1
					var wisp := Bit.new()
					wisp.kind = "smoke"
					wisp.x = bit.x
					wisp.y = bit.y
					wisp.z = bit.z
					wisp.vz = .2
					wisp.life = .7
					wisp.size = .07
					wisp.grow = .3
					kept.append(wisp)
		var nx := bit.x + bit.vx * dt
		var ny := bit.y + bit.vy * dt
		var flying := bit.kind == "tracer" or bit.kind == "rivet" or bit.kind == "milk"
		if not flying and game.world.blocked(nx, ny, .02):
			bit.vx *= -.3
			bit.vy *= -.3
		else:
			bit.x = nx
			bit.y = ny
		bit.z += bit.vz * dt
		if flying:
			continue
		var floor_z: float = game.world.elevation(bit.x, bit.y)
		if bit.z <= floor_z:
			bit.z = floor_z
			match bit.kind:
				"spark", "drip":
					bit.life = bit.age
				"clod", "chip", "cinder":
					if bit.vz < -2.0:
						bit.vz *= -.3
						bit.vx *= .5
						bit.vy *= .5
					else:
						bit.rest = true
				_:
					bit.vz = maxf(bit.vz, 0.0)
	bits = kept
	if bits.size() > MAX_BITS:
		bits = bits.slice(bits.size() - MAX_BITS)
	while not puddles.is_empty() and game.clock - float(puddles[0][6]) > PUDDLE_LIFE:
		puddles.pop_front()


## What the player's shots shed as they fly.
func _follow_shots() -> void:
	var seen := {}
	for shot in game.shots:
		if shot.enemy:
			continue
		var key: int = shot.get_instance_id()
		seen[key] = true
		var state: Array = _following.get(key, [game.clock, shot.bounces])
		if shot.kind == "blade" and shot.bounces != int(state[1]):
			# The saw blade skipping off a wall.
			_sparks(Vector3(shot.x, shot.y, shot.z), 9, 2.6)
		state[1] = shot.bounces
		if game.clock >= float(state[0]):
			state[0] = game.clock + _shed(shot)
		_following[key] = state
	for key in _following.keys():
		if not seen.has(key):
			_following.erase(key)


## Sheds one helping of what this shot leaves behind; returns how long until
## the next.
func _shed(shot) -> float:
	var at := Vector3(shot.x, shot.y, shot.z)
	var v := Vector3(shot.vx, shot.vy, shot.vz)
	match shot.kind:
		"bolt", "tnt", "keg":
			# A lit fuse spitting sparks, a thread of smoke.
			var fuse := at + Vector3(0, 0, .12 if shot.kind == "bolt" else .2)
			_bit("spark", fuse, _scatter(.9, 1.2), dice.randf_range(.15, .3), .03, 4.0)
			if dice.randf() < .45:
				var thread := _bit("smoke", fuse, Vector3(0, 0, .25), .8, .06)
				thread.grow = .3
			return .035
		"bottle_rocket":
			# Fizzing gold sparks out the back, and a smoke trail.
			for _k in 2:
				_bit("spark", at, -v * .12 + _scatter(.7, .5), dice.randf_range(.18, .34), .03, 4.0)
			if dice.randf() < .6:
				var trail := _bit("smoke", at, Vector3(0, 0, .12), .9, .06)
				trail.grow = .45
			return .02
		"arm_bolt":
			var mote := _bit("mote", at, _scatter(.5, .4), dice.randf_range(.22, .38), .035)
			mote.gravity = -.4
			return .022
		"bowling":
			var floor_z: float = game.world.elevation(shot.x, shot.y)
			if shot.z - floor_z < .4 and Vector2(shot.vx, shot.vy).length() > 1.0:
				var dust := _bit(
					"dust", Vector3(shot.x, shot.y, floor_z + .05), Vector3(0, 0, .12), .5, .1
				)
				dust.grow = .55
			return .07
		"cow":
			var exhaust := _bit("smoke", at - v.normalized() * .25, Vector3(0, 0, .15), .9, .1)
			exhaust.grow = .5
			if dice.randf() < .7:
				_bit("drip", at - Vector3(0, 0, .12), _scatter(.3, 0.0), .7, .035, 7.0)
			return .055
	return 1.0


# ------------------------------------------------------------------ drawing


func sprites() -> Array:
	var out: Array = []
	var p = game.player
	for bit: Bit in bits:
		if bit.age < 0.0:
			continue
		if (bit.x - p.x) * (bit.x - p.x) + (bit.y - p.y) * (bit.y - p.y) < .3:
			continue
		var step := bit.age / bit.life
		var name := ""
		var glow := false
		var translucent := false
		match bit.kind:
			"tracer", "rivet":
				name = "fx_tracer" if bit.kind == "tracer" else "fx_ember_0"
				glow = true
				# Two fading copies behind the head make the streak.
				for k: int in [2, 1]:
					var back := .009 * k
					var tail := Renderer.Sprite.new(
						bit.x - bit.vx * back,
						bit.y - bit.vy * back,
						name,
						bit.size * (1.0 - .25 * k),
						bit.z - bit.vz * back
					)
					tail.glow = true
					out.append(tail)
			"milk", "drip":
				name = "fx_milkdrop"
			"splash":
				name = "fx_milksplash_%d" % mini(2, int(step * 3.0))
			"steam":
				name = "fx_steam_%d" % mini(3, int(step * 4.0))
				translucent = true
			"smoke":
				name = "fx_smoke_%d" % mini(3, int(step * 4.0))
				translucent = true
			"dust":
				name = "fx_puff_%d" % mini(3, int(step * 4.0))
				translucent = true
			"spark":
				name = "fx_spark"
				glow = true
			"ember", "cinder":
				name = "fx_ember_%d" % (int(bit.age * 9.0) % 2)
				glow = true
			"mote":
				name = "fx_mote_%d" % (int(bit.age * 12.0) % 2)
				glow = true
			"chip":
				name = "fx_chips"
			"clod":
				name = "fx_soil"
		var s := Renderer.Sprite.new(bit.x, bit.y, name, bit.size, bit.z)
		s.glow = glow
		s.translucent = translucent
		out.append(s)
	return out


func ground_marks() -> Array:
	var out: Array = []
	var p = game.player
	for pool: Array in puddles:
		var dx: float = float(pool[0]) - p.x
		var dy: float = float(pool[1]) - p.y
		if dx * dx + dy * dy < 144.0:
			out.append(
				Renderer.GroundMark.new(
					pool[0],
					pool[1],
					pool[2],
					pool[3],
					pool[4],
					pool[4],
					"mark_milk_%d" % int(pool[5])
				)
			)
	return out
