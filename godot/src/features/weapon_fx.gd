## What every gun throws between its muzzle and its mark, and what its shots
## shed in the air: a hot streak off the .38 and the ranch rifle, burning
## wadding out of the sawed-off, a glowing rivet, the Copperhead's jet of
## steam, the teat gun's stream of milk (a splash and a puddle where it lands),
## sparks and chips off a swing, fuse sparks and smoke off dynamite, kegs and
## bottle rockets, the arm gun's green motes, dust off a bowling ball, a cow
## leaking milk on its way; and the dirt, cinders and dust ring of a blast.
## All of it looks only: its own dice, never saved, never in the way.
##
## Tracers, the milk and sparks are drawn on the canvas over the view
## (draw_view), not as sprites: a line from the gun's muzzle on screen to where
## the shot struck, in true perspective, so they are sharp at any distance and
## leave the barrel or the teat where the picture shows it.
extends GameFeature

const MAX_BITS := 240
const MAX_PUDDLES := 22
const PUDDLE_LIFE := 45.0
## How far ahead of the eye the muzzle on screen stands, for the perspective
## of a shot leaving it.
const MUZZLE_AHEAD := .5
const MILK_SPEED := 17.0
const JET_SPEED := 34.0
const JET_LIFE := .32
## The milk's drops, their size in the world (cells across).
const MILK_DROP := .021
## The two teat tips, from the muzzle point (between them), on the canvas.
const TEATS := [Vector2(-14.6, -2.4), Vector2(3.7, -18.3)]


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
	var bounced := false


var dice := RandomNumberGenerator.new()
var bits: Array = []
## [x, y, z, angle, size, frame, made at]
var puddles: Array = []
## Shot instance id -> [next trail time, bounces seen]
var _following := {}
var _pellets := 0
var _puddle_next := 0.0
## [fired at, speed, end, tail length, rivet, distance]
var streaks: Array = []
## [squirted at, end, distance, teat]
var squirts: Array = []
## The Copperhead's jets: [fired at, end, distance]
var jets: Array = []
var _teat := 0
## The gun these were drawn from: a switch clears what is drawn from a muzzle.
var _drawn_gun := -1


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


## One speck for another feature (impacts.gd): the same kinds, drawn and moved
## here, under the same cap.
func spawn(kind: String, at: Vector3, v: Vector3, life: float, size: float, gravity := 0.0) -> Bit:
	return _bit(kind, at, v, life, size, gravity)


## A spray of sparks off metal at `at` (they fall, bounce once and die).
func sparks(at: Vector3, count: int, speed: float) -> void:
	_sparks(at, count, speed)


## A direction at random, `speed` across at most and `up` upward at most.
func scatter(speed: float, up: float) -> Vector3:
	return _scatter(speed, up)


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
	if not game.acting_local():
		return
	_pellets = 0
	var from := _muzzle()
	var ahead := _forward()
	if gun == Weapons.SHOTGUN:
		# Burning wadding and powder thrown out ahead of the barrels.
		for _k in 3:
			var v := ahead * dice.randf_range(6.0, 9.5) + _scatter(1.4, 1.2)
			_bit("ember", from + ahead * .6, v, dice.randf_range(.45, .8), .035, 6.0)


func _traced(end: Vector3, struck: String) -> void:
	if not game.acting_local():
		return
	var gun: int = game.armory.active
	match gun:
		Weapons.REVOLVER:
			_streak(end, 70.0, 1.8, false)
		Weapons.RIFLE:
			_streak(end, 78.0, 1.5, false)
		Weapons.HUNTER:
			# A heavy round: a long, fat, bright streak.
			_streak(end, 110.0, 2.4, false)
		Weapons.MOWER, Weapons.PATROL_BAR:
			_streak(end, 82.0, 1.4, false)
		Weapons.MARKSMAN:
			_streak(end, 100.0, 2.0, false)
		Weapons.COUNTY45, Weapons.STAR357, Weapons.HOGLEG:
			_streak(end, 70.0, 1.8 if gun == Weapons.COUNTY45 else 2.1, false)
		Weapons.TOMMY, Weapons.GREASE_GUN:
			_streak(end, 66.0, 1.2, false)
		Weapons.RIOT_PUMP:
			_pellets += 1
			if _pellets <= 7:
				_streak(end, 60.0 + _pellets * 2.0, 1.1, false)
		Weapons.SHOTGUN:
			_pellets += 1
			if _pellets <= 7:
				_streak(end, 60.0 + _pellets * 2.0, 1.1, false)
		Weapons.RIVETER:
			_streak(end, 40.0, .55, true)
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


## A hot streak from the muzzle to the mark (draw_view draws it).
func _streak(end: Vector3, speed: float, tail: float, rivet: bool) -> void:
	var far := _ahead_of_eye(end)
	if far < MUZZLE_AHEAD + .3:
		return
	streaks.append([game.clock, speed, end, tail, rivet, far])
	if streaks.size() > 48:
		streaks.pop_front()


## How far ahead of the eye a point is, along the view.
func _ahead_of_eye(at: Vector3) -> float:
	var p = game.player
	var a: float = p.view_angle()
	return (at.x - p.x) * cos(a) + (at.y - p.y) * sin(a)


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
			var dust := _bit("dust", back, Vector3(0, 0, .2), .4, .07)
			dust.grow = .25


## The Copperhead: a jet of steam all the way to the mark, a cloud where it hits.
func _jet(end: Vector3, struck: String) -> void:
	jets.append([game.clock, end, _ahead_of_eye(end)])
	if jets.size() > 6:
		jets.pop_front()
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


## The teat gun: a rope of milk to the mark (draw_view), a splash, a puddle.
func _milk(end: Vector3, struck: String) -> void:
	var from := _muzzle()
	var far := _ahead_of_eye(end)
	_teat = 1 - _teat
	squirts.append([game.clock, end, far, _teat])
	if squirts.size() > 24:
		squirts.pop_front()
	var arrive := maxf(0.0, far - MUZZLE_AHEAD) / MILK_SPEED
	if struck == "air":
		return
	var back := end - (end - from).normalized() * .06
	var splash := _bit("splash", back, Vector3.ZERO, .3, .3)
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
	_soaked(dt)
	_bosses()
	var wind: Vector2 = Effects.DEBRIS.get("wind_" + game.level.id, Vector2.ZERO)
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
				# Slowing, and carried off on the level's wind (effects.cfg [debris]).
				bit.vx += (wind.x - bit.vx) * minf(1.0, dt * 3.0)
				bit.vy += (wind.y - bit.vy) * minf(1.0, dt * 3.0)
			"chaff":
				# Husk and leaf: floats down, rocking on the wind.
				bit.vx += (wind.x - bit.vx) * minf(1.0, dt * 2.0)
				bit.vy += (wind.y - bit.vy) * minf(1.0, dt * 2.0)
				bit.vz = maxf(bit.vz, -.6)
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
		if game.world.blocked(nx, ny, .02):
			bit.vx *= -.3
			bit.vy *= -.3
		else:
			bit.x = nx
			bit.y = ny
		bit.z += bit.vz * dt
		var floor_z: float = game.world.elevation(bit.x, bit.y)
		if bit.z <= floor_z:
			bit.z = floor_z
			match bit.kind:
				"spark", "glint":
					# Off the floor once, then out.
					if bit.bounced or bit.vz > -1.0:
						if bit.kind == "spark":
							bit.life = bit.age
						else:
							bit.rest = true
					else:
						bit.bounced = true
						bit.vz *= -.38
						bit.vx *= .55
						bit.vy *= .55
				"drip":
					bit.life = bit.age
				"chaff":
					bit.rest = true
				"clod", "chip", "cinder", "splinter", "grit_brick", "grit_stone":
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
	while (
		not streaks.is_empty()
		and (
			(game.clock - float(streaks[0][0])) * float(streaks[0][1]) - float(streaks[0][3])
			> float(streaks[0][5])
		)
	):
		streaks.pop_front()
	while not jets.is_empty() and game.clock - float(jets[0][0]) > JET_LIFE:
		jets.pop_front()
	while (
		not squirts.is_empty()
		and (game.clock - float(squirts[0][0]) - .15) * MILK_SPEED > float(squirts[0][2])
	):
		squirts.pop_front()
	while not puddles.is_empty() and game.clock - float(puddles[0][6]) > PUDDLE_LIFE:
		puddles.pop_front()


var _drip_next := 0.0
var _boss_next := 0.0


## A boss fightin' mad gives off its own: the sheriff green sparks, Jerry
## steam off his head, Rudy fireworks, the foreman sawdust and sparks, the
## baron steam from his pipes. A fallen boss smoulders a while.
func _bosses() -> void:
	if game.clock < _boss_next:
		return
	_boss_next = game.clock + .09
	var p = game.player
	for e: Enemy in game.enemies:
		if not Enemy.BOSS_TITLES.has(e.kind):
			continue
		if absf(e.x - p.x) > 14.0 or absf(e.y - p.y) > 14.0:
			continue
		var floor_z: float = game.world.elevation(e.x, e.y)
		var top := Vector3(e.x, e.y, floor_z + e.z + e.height * .9)
		if not e.alive:
			if e.died_at >= 0.0 and game.clock - e.died_at < 6.0 and dice.randf() < .5:
				var smoke := _bit(
					"smoke", top - Vector3(0, 0, e.height * .5), Vector3(0, 0, .35), 1.4, .2
				)
				smoke.grow = .5
			continue
		if not e.enraged:
			continue
		match e.brain:
			"boss":
				var mote := _bit("mote", top, _scatter(.8, .6), .5, .045)
				mote.gravity = -.5
			"jerry", "baron":
				var steam := _bit("steam", top, _scatter(.3, .5), .7, .14)
				steam.grow = .6
			"rudy":
				_bit("spark", top, _scatter(1.6, 1.6), .45, .03, 4.0)
			"foreman":
				_bit("chip", top, _scatter(1.0, 1.0), .6, .04, 6.0)
				_bit("spark", top - Vector3(0, 0, .3), _scatter(1.2, .8), .3, .03, 6.0)


## Milk dripping off whoever the teat gun soaked.
func _soaked(_dt: float) -> void:
	if game.clock < _drip_next:
		return
	_drip_next = game.clock + .12
	var p = game.player
	for e: Enemy in game.enemies:
		if e.soak < .12 or not e.alive or absf(e.x - p.x) > 10.0 or absf(e.y - p.y) > 10.0:
			continue
		if dice.randf() > e.soak:
			continue
		var floor_z: float = game.world.elevation(e.x, e.y)
		var at := Vector3(
			e.x + dice.randf_range(-.15, .15),
			e.y + dice.randf_range(-.15, .15),
			floor_z + e.z + e.height * dice.randf_range(.3, .8)
		)
		_bit("drip", at, _scatter(.2, 0.0), .5, .03, 7.0)


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
					"dust", Vector3(shot.x, shot.y, floor_z + .05), Vector3(0, 0, .15), .55, .16
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
		if bit.kind == "spark" or not game.in_view(bit.x, bit.y, bit.size + .3):
			continue
		var step := bit.age / bit.life
		var name := ""
		var glow := false
		var translucent := false
		match bit.kind:
			"drip":
				name = "fx_milkdrop"
				glow = true
			"splash":
				name = "fx_milksplash_%d" % mini(2, int(step * 3.0))
				glow = true
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
				continue
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
			"splinter":
				name = "fx_splinter_%d" % (0 if bit.rest else int(bit.age * 14.0) % 2)
			"grit_brick", "grit_stone":
				name = "fx_" + bit.kind
			"chaff":
				name = "fx_chaff_%d" % (int(bit.age * 6.0 + bit.size * 97.0) % 2)
			"glint":
				# A chip of glass catching the light now and then.
				var flash := int(bit.age * 11.0 + bit.size * 131.0) % 5 == 0
				name = "fx_glint_%d" % (1 if flash else 0)
				glow = flash
		var s: Renderer.Sprite = game.pooled(bit.x, bit.y, name, bit.size, bit.z)
		s.glow = glow
		s.translucent = translucent
		out.append(s)
	return out


## Where a point `u` of the way (0 the muzzle, 1 the mark) along a shot from the
## muzzle on screen to `mark` (the mark on screen) shows: the muzzle's offset
## from the line of sight shrinks as the shot goes away, in perspective.
func _along(muzzle: Vector2, mark: Vector2, far: float, u: float) -> Vector2:
	var d := MUZZLE_AHEAD + u * (far - MUZZLE_AHEAD)
	return mark + (muzzle - mark) * (1.0 - u) * MUZZLE_AHEAD / d


func _inside(at: Vector2) -> bool:
	return at.x >= 0.0 and at.y >= 0.0 and at.x < Renderer.WIDTH and at.y < Renderer.VIEW


func _segment(c: Canvas, a: Vector2, b: Vector2, colour: Color, width := 1, fast := false) -> void:
	if not _inside(a) and not _inside(b):
		return
	# Cut it at the bottom of the view (the status bar is below).
	var floor_y := Renderer.VIEW - 1.0
	if a.y > floor_y:
		a = b.lerp(a, (floor_y - b.y) / maxf(.001, a.y - b.y))
	elif b.y > floor_y:
		b = a.lerp(b, (floor_y - a.y) / maxf(.001, b.y - a.y))
	if fast:
		c.stroke(int(a.x), int(a.y), int(b.x), int(b.y), colour, width)
		return
	c.line(int(a.x), int(a.y), int(b.x), int(b.y), colour, width)


func draw_view(c: Canvas) -> void:
	if game.armory.active != _drawn_gun:
		# Streaks, milk and steam start at the muzzle in hand: never another gun's.
		_drawn_gun = game.armory.active
		streaks.clear()
		squirts.clear()
		jets.clear()
	var muzzle: Vector2 = Weapons.muzzle_at
	if muzzle.x < 0.0:
		muzzle = Vector2(Renderer.WIDTH * .62, Renderer.VIEW * .8)
	_draw_streaks(c, muzzle)
	_draw_milk(c, muzzle)
	_draw_jets(c, muzzle)
	_draw_sparks(c)


## Each shot's streak: a white-hot head with an orange skin and a tail that
## thins out behind it.
func _draw_streaks(c: Canvas, muzzle: Vector2) -> void:
	var rich := Effects.rich and c.gpu
	var heads: Array = []
	for s: Array in streaks:
		var far: float = s[5]
		var run: float = (game.clock - float(s[0])) * float(s[1])
		var span := maxf(.01, far - MUZZLE_AHEAD)
		var head := clampf(run / span, 0.0, 1.0)
		var tail := clampf((run - float(s[3])) / span, 0.0, 1.0)
		if head <= tail:
			continue
		var end: Vector3 = s[2]
		var seen: Vector3 = game.to_canvas(end.x, end.y, end.z)
		if seen.z < 0.0:
			continue
		var mark := Vector2(seen.x, seen.y)
		var a := _along(muzzle, mark, far, tail)
		var mid := _along(muzzle, mark, far, lerpf(tail, head, .55))
		var b := _along(muzzle, mark, far, head)
		var rivet: bool = s[4]
		var skin := Color8(230, 96, 22) if rivet else Color8(214, 120, 40)
		var core := Color8(255, 200, 110) if rivet else Color8(255, 246, 196)
		# Thicker near the gun, a thread far off.
		var thick := 2 if head < .5 else 1
		if rich:
			# The shader view: a fatter, hotter streak with a glow at its head.
			thick = 3 if head < .3 else 2 if head < .7 else 1
			_segment(c, a, b, skin.darkened(.45), thick, true)
			_segment(c, mid, b, skin.lightened(.1), thick, true)
			_segment(c, a.lerp(b, .3), b, core, maxi(1, thick - 1), true)
			if _inside(b):
				heads.append([b, 3 if rivet or head < .4 else 2, rivet])
			continue
		_segment(c, a, b, skin.darkened(.35), thick)
		_segment(c, mid, b, skin, thick)
		_segment(c, mid.lerp(b, .4), b, core, 1)
		if rivet and _inside(b):
			c.fill_rect(int(b.x) - 1, int(b.y) - 1, 2, 2, core)
	if heads.is_empty():
		return
	# The heads' glow adds its light to the view, all in one go.
	c.gpu_item(Canvas.ITEM_ADD_VIEW)
	for h: Array in heads:
		var at: Vector2 = h[0]
		var r: int = h[1]
		var size := r * 4 + 1
		c.blit_rgba(
			_glow_dot(r, bool(h[2])),
			size,
			size,
			int(at.x) - r * 2,
			int(at.y) - r * 2,
			"tracer_glow|%d|%s" % [r, h[2]]
		)
	c.gpu_item(Canvas.ITEM_NORMAL_VIEW)


## A soft round of hot light `r` (2 or 3) for a tracer's head: white to
## orange, red for a rivet; to be added to what is under it.
static func _glow_dot(r: int, rivet: bool) -> PackedByteArray:
	var key := "g%d|%s" % [r, rivet]
	if _discs.has(key):
		return _discs[key]
	var size := r * 4 + 1
	var out := PackedByteArray()
	out.resize(size * size * 4)
	var hot := Color8(255, 150, 70) if rivet else Color8(255, 196, 110)
	for y in size:
		for x in size:
			var d := Vector2(x - r * 2, y - r * 2).length() / (r * 2.0 + .5)
			if d >= 1.0:
				continue
			# Stepped, not smooth: three rings of light.
			var k := 1.0 if d < .3 else .55 if d < .6 else .22
			var o := (y * size + x) * 4
			out[o] = int(hot.r8 * k)
			out[o + 1] = int(hot.g8 * k)
			out[o + 2] = int(hot.b8 * k)
			out[o + 3] = 255
	_discs[key] = out
	return out


## The teat gun's milk: one rope of drops from the teat to the mark, a squirt
## at a time, lifted a little in its arc and falling to it; when the trigger is
## let go its last stretch flies off the teat.
func _draw_milk(c: Canvas, muzzle: Vector2) -> void:
	if squirts.is_empty():
		return
	var p = game.player
	var light: float = game.world.light[game.world.cell(p.x, p.y)]
	var shade := clampf(.62 + .45 * light, .55, 1.0)
	var tone := clampi(int(shade * 4.0), 0, 4)
	var focal := Renderer.base_focal
	for k in squirts.size():
		var squirt: Array = squirts[k]
		var born: float = squirt[0]
		var gap := .1
		if k + 1 < squirts.size():
			gap = minf(.13, float(squirts[k + 1][0]) - born)
		var far: float = squirt[2]
		var span := maxf(.01, far - MUZZLE_AHEAD)
		var front := clampf((game.clock - born) * MILK_SPEED / span, 0.0, 1.0)
		var back := clampf((game.clock - born - gap) * MILK_SPEED / span, 0.0, 1.0)
		if front <= back:
			continue
		var end: Vector3 = squirt[1]
		var seen: Vector3 = game.to_canvas(end.x, end.y, end.z)
		if seen.z < 0.0:
			continue
		var mark := Vector2(seen.x, seen.y)
		var spout: Vector2 = muzzle + TEATS[int(squirt[3])]
		var lift := .05 + .02 * far
		# Drops spaced evenly on screen, not in the world (far off they bunch up).
		var w_front := (1.0 - front) * MUZZLE_AHEAD / (MUZZLE_AHEAD + front * span)
		var w_back := (1.0 - back) * MUZZLE_AHEAD / (MUZZLE_AHEAD + back * span)
		var reach := spout.distance_to(mark) * (w_back - w_front)
		var count := clampi(int(reach / 1.4) + 2, 2, 46)
		for j in count:
			var w := lerpf(w_back, w_front, j / maxf(1.0, count - 1.0))
			var u := MUZZLE_AHEAD * (1.0 - w) / (w * span + MUZZLE_AHEAD)
			var d := MUZZLE_AHEAD + u * span
			var at := _along(spout, mark, far, u)
			at.y -= 4.0 * lift * u * (1.0 - u) * focal / d
			# A living stream wavers a little.
			var r := clampf(MILK_DROP * focal / d, .5, 2.7)
			# Each squirt swells and narrows: the beat of the teat.
			var beat := j / maxf(1.0, count - 1.0)
			r *= .72 + .28 * sin(PI * beat)
			at.x += sin(born * 53.0 + u * 11.0) * .3 * r
			# Far along, the rope breaks up into drops.
			var hash := fposmod(sin(born * 91.0 + j * 12.9898) * 437.585, 1.0)
			if u > .62:
				if hash < (u - .62) * 1.9:
					continue
				at.y += (hash - .5) * 3.0 * (u - .62)
				at.x += (fposmod(hash * 7.31, 1.0) - .5) * 3.0 * (u - .62)
			if not _inside(at):
				continue
			var ri := clampi(int(roundf(r)), 0, 3)
			var drop := _milk_drop(ri, tone)
			var size := ri * 2 + 1
			c.blit_rgba(drop, size, size, int(at.x) - ri, int(at.y) - ri, "milk|%d|%d" % [ri, tone])


## The Copperhead's jet: a cone of steam out of the barrel to the mark, drawn
## as a dither of pale pixels (thin at the muzzle, spreading and thinning out),
## the way a 256-colour picture shows something you can see through.
func _draw_jets(c: Canvas, muzzle: Vector2) -> void:
	if jets.is_empty():
		return
	var p = game.player
	var light: float = game.world.light[game.world.cell(p.x, p.y)]
	var shade := clampf(.6 + .45 * light, .55, 1.0)
	var tone := clampi(int(shade * 4.0), 0, 4)
	var focal := Renderer.base_focal
	var frame := int(game.clock * 30.0)
	for jet: Array in jets:
		var age: float = game.clock - float(jet[0])
		var far: float = jet[2]
		var span := maxf(.01, far - MUZZLE_AHEAD)
		var front := clampf(age * JET_SPEED / span, 0.0, 1.0)
		var fade: float = 1.0 - age / JET_LIFE
		if front <= 0.0 or fade <= 0.0:
			continue
		var end: Vector3 = jet[1]
		var seen: Vector3 = game.to_canvas(end.x, end.y, end.z)
		if seen.z < 0.0:
			continue
		var mark := Vector2(seen.x, seen.y)
		for j in 16:
			var u := front * j / 15.0
			var d := MUZZLE_AHEAD + u * span
			var at := _along(muzzle, mark, far, u)
			# Rising a little as it goes, as steam does.
			at.y -= .08 * u * focal / d * (1.0 + age * 3.0)
			# A cone: barrel-thin at the muzzle, spreading as it goes.
			var spread: float = .006 + .11 * (d - MUZZLE_AHEAD)
			var r: float = clampf(spread * focal / d, 1.0, 8.0) * (1.0 + age * 1.2)
			var ri := clampi(int(roundf(r)), 1, 10)
			var thick := clampi(int(fade * (3.0 - 2.0 * u)), 0, 2)
			# Four churning speckles, a different one each frame and each ring.
			var turn := (frame + j) & 3
			var size := ri * 2 + 1
			c.blit_rgba(
				_steam_disc(ri, thick, turn, tone),
				size,
				size,
				int(at.x) - ri,
				int(at.y) - ri,
				"steam|%d|%d|%d|%d" % [ri, thick, turn, tone]
			)


static var _discs := {}


## A drop of milk `r` pixels round (0 is one pixel) in light `tone` (0 to 4):
## a cool rim, a cream body, a shine at the top.
static func _milk_drop(r: int, tone: int) -> PackedByteArray:
	var key := "m%d|%d" % [r, tone]
	if _discs.has(key):
		return _discs[key]
	var shade := tone / 4.0
	var size := r * 2 + 1
	var out := PackedByteArray()
	out.resize(size * size * 4)
	for y in size:
		for x in size:
			var dx := x - r
			var dy := y - r
			var dist := dx * dx + dy * dy
			if dist > r * r + (r if r > 0 else 0):
				continue
			var c := Color8(244, 240, 226)
			if r >= 2 and dy >= r - 1:
				c = Color8(184, 182, 176)
			if r >= 2 and dx == -1 and dy == -r + 1:
				c = Color8(255, 255, 250)
			var o := (y * size + x) * 4
			out[o] = int(c.r8 * shade)
			out[o + 1] = int(c.g8 * shade)
			out[o + 2] = int(c.b8 * shade)
			out[o + 3] = 255
	_discs[key] = out
	return out


## A ring of the Copperhead's steam, `r` pixels round: a speckle of pale pixels,
## `thick` (0 to 2) how many, fewer toward the edge; `turn` picks one of four
## speckles; `tone` (0 to 4) the light it is seen in.
static func _steam_disc(r: int, thick: int, turn: int, tone: int) -> PackedByteArray:
	var key := "s%d|%d|%d|%d" % [r, thick, turn, tone]
	if _discs.has(key):
		return _discs[key]
	var shade := clampf(tone / 4.0, .55, 1.0)
	var density: float = [.16, .27, .38][thick]
	var size := r * 2 + 1
	var out := PackedByteArray()
	out.resize(size * size * 4)
	for y in size:
		for x in size:
			var dx := x - r
			var dy := y - r
			var edge := float(dx * dx + dy * dy) / maxf(1.0, r * r)
			if edge > 1.0:
				continue
			var speck := x * 374761393 + y * 668265263 + (turn * 31 + r * 7) * 1274126177
			speck = (speck ^ (speck >> 13)) * 1274126177
			speck = (speck ^ (speck >> 16)) & 255
			if speck / 255.0 >= density * (1.0 - .7 * edge):
				continue
			var c := Color8(214, 218, 220) if edge < .35 else Color8(158, 164, 170)
			var o := (y * size + x) * 4
			out[o] = int(c.r8 * shade)
			out[o + 1] = int(c.g8 * shade)
			out[o + 2] = int(c.b8 * shade)
			out[o + 3] = 255
	_discs[key] = out
	return out


## Sparks as short bright streaks along the way they fly, white-hot to orange.
func _draw_sparks(c: Canvas) -> void:
	for bit: Bit in bits:
		if bit.kind != "spark" or bit.age < 0.0:
			continue
		var a: Vector3 = game.to_canvas(bit.x, bit.y, bit.z)
		var b: Vector3 = game.to_canvas(
			bit.x - bit.vx * .035, bit.y - bit.vy * .035, bit.z - bit.vz * .035
		)
		if a.z < 0.0 or b.z < 0.0:
			continue
		var heat := 1.0 - bit.age / bit.life
		var colour := (
			Color8(255, 250, 214)
			if heat > .66
			else Color8(255, 196, 92) if heat > .33 else Color8(226, 110, 38)
		)
		var head := Vector2(a.x, a.y)
		_segment(c, Vector2(b.x, b.y), head, colour, 2 if a.z < 1.6 else 1, Effects.rich and c.gpu)


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
