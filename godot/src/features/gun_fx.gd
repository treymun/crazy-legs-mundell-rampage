## The graphics-card view's own layer of gun and blast effects, shown only
## while it draws with LIGHTS AND GLOW (Effects.rich): the software view keeps
## weapon_fx.gd's as they were. Its pictures are build_gun_fx_art.gd's, hard
## edged and few-coloured like a 1997 sprite.
##
## A blast: a white star the instant it goes, a fireball rolling up in lobes
## and going over to soot (with two smaller ones beside it), a column of black
## smoke, charred scraps flung out trailing smoke, a ring of dust running out
## along the ground, and the yard lit by it a moment (lights()). A round
## striking: a burst of what it struck by material (sparks, brick dust, wood
## dust and splinters, dirt, glass, a splash, leaves) and more of it flying. A
## shot leaving the gun: burning wadding, a puff of smoke, sparks. Dynamite
## fuses and bottle rockets spit sparks; rockets and cows lay soot.
##
## Looks only: its own dice, never saved, never in the way. Everything is
## made whatever the view (so the shader view's picture does not depend on
## what was drawn before), and capped: MAX_BITS in the air, MAX_BOOMS
## fireballs, MAX_HITS strikes, and a chain of blasts throws less each.
extends GameFeature

const MAX_BITS := 150
const MAX_BOOMS := 6
const MAX_HITS := 20
## Seconds a fireball takes to burn through its eight frames.
const BOOM_LIFE := .95
const HIT_LIFE := .15
const SHOCK_LIFE := .4
## Pellets of one load that each show a strike.
const PELLET_HITS := 5
## Material -> the strike's picture (fx_hit_<it>_N).
const HIT_ART := {
	"tin": "metal",
	"steel": "metal",
	"mesh": "metal",
	"brick": "brick",
	"stone": "stone",
	"wood": "wood",
	"timber": "wood",
	"dirt": "dirt",
	"glass": "glass",
	"water": "water",
	"brush": "brush",
	"rubber": "dirt",
}


class Bit:
	var x := 0.0
	var y := 0.0
	var z := 0.0
	var vx := 0.0
	var vy := 0.0
	var vz := 0.0
	## Below zero: not out yet.
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
## [x, y, z, born, size, secondary]
var booms: Array = []
## [x, y, z, born, picture, size]
var hits: Array = []
## [x, y, z, born]
var shocks: Array = []
## When each recent blast went (a chain throws less).
var _recent: Array = []
var _seen_blasts := {}
var _following := {}
var _pellets := 0
var _smoke_next := 0.0


func id() -> String:
	return "gun_fx"


func attach() -> void:
	dice.seed = 1997
	game.shot_fired.connect(_fired)
	game.traced.connect(_traced)
	game.exploded.connect(_exploded)
	game.ticked.connect(_tick)


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
	bits.append(bit)
	if bits.size() > MAX_BITS:
		bits.pop_front()
	return bit


func _scatter(speed: float, up: float) -> Vector3:
	var a := dice.randf_range(0, TAU)
	var v := dice.randf_range(.3, 1.0) * speed
	return Vector3(cos(a) * v, sin(a) * v, dice.randf_range(.2, 1.0) * up)


func _forward() -> Vector3:
	var a: float = game.player.view_angle()
	return Vector3(cos(a), sin(a), 0.0)


## Out ahead of the muzzle, in the world.
func _ahead(far: float) -> Vector3:
	var p = game.player
	var a: float = p.view_angle()
	return Vector3(p.x + cos(a) * far - sin(a) * .1, p.y + sin(a) * far + cos(a) * .1, p.eye - .16)


# ------------------------------------------------------------------ firing


func _fired(gun: int) -> void:
	if not game.acting_local():
		return
	_pellets = 0
	var ahead := _forward()
	# The 5v5 store's bullet guns smoke and spark as the rifle does; its riot
	# pump as the sawed-off.
	var kind := gun
	if Weapons.FRESH_BULLETS.has(gun):
		kind = Weapons.SHOTGUN if gun == Weapons.RIOT_PUMP else Weapons.RIFLE
	match kind:
		Weapons.SHOTGUN:
			# Burning wadding and a cloud of powder smoke thrown out of both barrels.
			for _k in 6:
				var v := ahead * dice.randf_range(4.0, 8.0) + _scatter(1.6, 1.4)
				_bit("ember", _ahead(.9), v, dice.randf_range(.3, .6), .03, 5.0)
			for k in 3:
				var puff := _bit(
					"smoke",
					_ahead(1.0 + k * .35),
					ahead * (.9 - k * .2) + Vector3(0, 0, .12),
					1.4,
					.14
				)
				puff.grow = .4
		Weapons.REVOLVER, Weapons.RIFLE, Weapons.HUNTER, Weapons.MOWER:
			if game.clock >= _smoke_next:
				# A fast gun lays one cloud a while, not a wall of them.
				_smoke_next = game.clock + .2
				var puff := _bit("smoke", _ahead(1.0), ahead * .5 + Vector3(0, 0, .1), 1.0, .1)
				puff.grow = .3
			for _k in 2:
				_bit("spark", _ahead(.9), ahead * 6.0 + _scatter(1.4, 1.0), .14, .03, 4.0)
		Weapons.RIVETER:
			for _k in 3:
				_bit("spark", _ahead(.9), ahead * 4.0 + _scatter(2.0, 1.4), .2, .03, 6.0)
		Weapons.ROCKET, Weapons.COW:
			# The launcher's blast: soot rolling out round the muzzle.
			for k in 3:
				var puff := _bit("soot", _ahead(1.0 + k * .25), _scatter(.5, .3), 1.3, .22)
				puff.grow = .45


func _traced(end: Vector3, struck: String) -> void:
	var gun: int = game.armory.active
	var mode := String(Weapons.FIRING[gun].get("fire", ""))
	if mode != "hitscan" and mode != "pellets":
		return
	if gun == Weapons.PRESSURE or gun == Weapons.TEAT:
		return
	var kind := ""
	if struck == "glass":
		kind = "glass"
	elif struck.begins_with("wall:") and struck != "wall:":
		kind = String(game.impact_kind)
	if not HIT_ART.has(kind):
		return
	_pellets += 1
	if gun == Weapons.SHOTGUN and _pellets > PELLET_HITS:
		return
	var p = game.player
	var dir := (end - Vector3(p.x, p.y, p.eye)).normalized()
	var at := end - dir * .06
	var art := String(HIT_ART[kind])
	var big := 1.3 if gun == Weapons.RIFLE else .8 if gun == Weapons.SHOTGUN else 1.0
	if gun == Weapons.HUNTER or gun == Weapons.MARKSMAN:
		big = 1.7 if gun == Weapons.HUNTER else 1.5
	elif gun == Weapons.STAR357 or gun == Weapons.HOGLEG:
		big = 1.25
	elif gun == Weapons.RIOT_PUMP:
		big = .8
	elif gun == Weapons.MOWER:
		big = 1.2
	var size := (.42 if art == "metal" or art == "glass" else .6) * big
	hits.append([at.x, at.y, at.z, game.clock, art, size])
	if hits.size() > MAX_HITS:
		hits.pop_front()
	var out := -dir
	match art:
		"metal":
			for _k in 5:
				_bit(
					"spark", at, _scatter(2.6, 2.2) + out * 1.2, dice.randf_range(.18, .4), .03, 7.0
				)
		"wood":
			for _k in 2:
				_bit(
					"splinter",
					at,
					_scatter(1.6, 1.8) + out * 1.4,
					dice.randf_range(.8, 1.2),
					.05,
					8.0
				)
			_puff(at, out, "dust", .16)
		"brick", "stone":
			for _k in 3:
				_bit(
					"grit_" + art,
					at,
					_scatter(1.5, 1.6) + out * 1.2,
					dice.randf_range(.6, 1.0),
					.035,
					9.0
				)
			_puff(at, out, "dust", .2 * big)
		"dirt":
			for _k in 3:
				var v := _scatter(.9, 0.0) + out * .6
				v.z = dice.randf_range(1.6, 2.6)
				_bit("clod", at, v, dice.randf_range(.6, .9), .04, 9.0)
			_puff(at, out, "dust", .2 * big)
		"glass":
			for _k in 3:
				_bit(
					"glint",
					at,
					_scatter(1.3, 1.2) + out * 1.0,
					dice.randf_range(1.5, 3.0),
					.028,
					9.0
				)
		"brush":
			for _k in 3:
				_bit(
					"chaff", at, _scatter(.9, 1.3) + out * .6, dice.randf_range(1.2, 2.0), .05, 2.5
				)
		"water":
			for _k in 4:
				var v := _scatter(.7, 0.0)
				v.z = dice.randf_range(1.8, 3.0)
				_bit("drop", at, v, .6, .03, 9.0)


func _puff(at: Vector3, out: Vector3, kind: String, size: float) -> void:
	var puff := _bit(kind, at + out * .05, out * .45 + Vector3(0, 0, .18), .9, size)
	puff.grow = size * 2.2


# --------------------------------------------------------------- explosions


func _exploded(x: float, y: float, z: float, energy: bool) -> void:
	if energy:
		return
	# A chain going up throws less each blast, so a row of barrels can't swamp
	# the frame.
	var since: float = game.clock - 1.0
	while not _recent.is_empty() and float(_recent[0]) < since:
		_recent.pop_front()
	_recent.append(game.clock)
	var heavy := _recent.size() > 2
	var at := Vector3(x, y, z)
	var floor_z: float = game.world.elevation(x, y)
	# The column of black smoke rolling up after the fireball.
	for k in 2 if heavy else 6:
		var puff := _bit(
			"soot",
			Vector3(
				x + dice.randf_range(-.35, .35), y + dice.randf_range(-.35, .35), z + .2 + k * .2
			),
			Vector3(0, 0, dice.randf_range(.5, .95)),
			dice.randf_range(3.0, 4.2),
			.75 + k * .08
		)
		puff.age = -.3 - k * .1
		puff.grow = .6
	# Charred scraps flung out, trailing smoke.
	for _k in 2 if heavy else 7:
		var v := _scatter(3.6, 0.0)
		v.z = dice.randf_range(2.6, 5.2)
		var scrap := _bit("chunk", at + Vector3(0, 0, .1), v, dice.randf_range(1.2, 1.8), .1, 9.0)
		scrap.trail = dice.randf_range(0.0, .05)
	# Burning bits rising off it a while.
	for _k in 1 if heavy else 4:
		var ember := _bit("ember", at, _scatter(1.4, 1.8), dice.randf_range(1.0, 1.8), .035, -.3)
		ember.vz = maxf(ember.vz, .6)
	if z - floor_z < 1.2:
		shocks.append([x, y, floor_z + .006, game.clock])
		if shocks.size() > 4:
			shocks.pop_front()


## The fireballs: one for every blast the game has (any source), and two
## smaller ones beside a fire blast unless a chain is going.
func _new_blasts() -> void:
	if game.blasts.is_empty() and _seen_blasts.is_empty():
		return
	var live := {}
	for blast: GameState.Blast in game.blasts:
		var key := blast.get_instance_id()
		live[key] = true
		if _seen_blasts.has(key) or blast.kind != "fire":
			continue
		_seen_blasts[key] = true
		var born: float = game.clock - blast.age
		booms.append([blast.x, blast.y, blast.z, born, 1.0, false])
		if _recent.size() <= 2:
			for k in 2:
				var a := dice.randf_range(0, TAU)
				booms.append(
					[
						blast.x + cos(a) * .4,
						blast.y + sin(a) * .4,
						blast.z + dice.randf_range(.0, .3),
						born + .05 + k * .06,
						dice.randf_range(.5, .65),
						true
					]
				)
	if not _seen_blasts.is_empty():
		_seen_blasts = _keep(live)
	while booms.size() > MAX_BOOMS * 3:
		booms.pop_front()


func _keep(live: Dictionary) -> Dictionary:
	var kept := {}
	for key in _seen_blasts:
		if live.has(key):
			kept[key] = true
	return kept


# --------------------------------------------------------------------- tick


func _tick(dt: float) -> void:
	_new_blasts()
	_follow_shots()
	var wind := Vector2.ZERO
	if not bits.is_empty():
		wind = Effects.DEBRIS.get("wind_" + game.level.id, Vector2.ZERO)
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
			"soot", "smoke", "dust":
				bit.vx += (wind.x - bit.vx) * minf(1.0, dt * 1.6)
				bit.vy += (wind.y - bit.vy) * minf(1.0, dt * 1.6)
				bit.vz *= 1.0 - minf(1.0, dt * .6)
			"chaff":
				bit.vx += (wind.x - bit.vx) * minf(1.0, dt * 2.0)
				bit.vy += (wind.y - bit.vy) * minf(1.0, dt * 2.0)
				bit.vz = maxf(bit.vz, -.6)
			"chunk":
				bit.trail -= dt
				if bit.trail <= 0.0 and bit.age < bit.life * .8:
					bit.trail = .07
					var wisp := Bit.new()
					wisp.kind = "soot"
					wisp.x = bit.x
					wisp.y = bit.y
					wisp.z = bit.z
					wisp.vz = .25
					wisp.life = .8
					wisp.size = .09
					wisp.grow = .35
					kept.append(wisp)
		var nx := bit.x + bit.vx * dt
		var ny := bit.y + bit.vy * dt
		if bit.gravity > 0.0 and game.world.blocked(nx, ny, .02):
			bit.vx *= -.3
			bit.vy *= -.3
		else:
			bit.x = nx
			bit.y = ny
		bit.z += bit.vz * dt
		if bit.gravity <= 0.0:
			continue
		var floor_z: float = game.world.elevation(bit.x, bit.y)
		if bit.z <= floor_z:
			bit.z = floor_z
			if bit.kind == "spark" or bit.kind == "drop":
				bit.life = bit.age
			elif bit.vz < -2.0 and bit.kind != "chaff":
				bit.vz *= -.3
				bit.vx *= .5
				bit.vy *= .5
			else:
				bit.rest = true
	bits = kept
	if bits.size() > MAX_BITS:
		bits = bits.slice(bits.size() - MAX_BITS)
	while not booms.is_empty() and game.clock - float(booms[0][3]) > BOOM_LIFE:
		booms.pop_front()
	while not hits.is_empty() and game.clock - float(hits[0][3]) > HIT_LIFE:
		hits.pop_front()
	while not shocks.is_empty() and game.clock - float(shocks[0][3]) > SHOCK_LIFE:
		shocks.pop_front()


## What the player's shots shed as they fly, over weapon_fx.gd's.
func _follow_shots() -> void:
	if game.shots.is_empty() and _following.is_empty():
		return
	var seen := {}
	for shot in game.shots:
		if shot.enemy:
			continue
		var key: int = shot.get_instance_id()
		seen[key] = true
		var next: float = _following.get(key, game.clock)
		if game.clock >= next:
			next = game.clock + _shed(shot)
		_following[key] = next
	if _following.size() > seen.size():
		for key in _following.keys():
			if not seen.has(key):
				_following.erase(key)


func _shed(shot) -> float:
	var at := Vector3(shot.x, shot.y, shot.z)
	var v := Vector3(shot.vx, shot.vy, shot.vz)
	match shot.kind:
		"tnt", "keg", "bolt":
			var fuse := at + Vector3(0, 0, .12 if shot.kind == "bolt" else .2)
			for _k in 1:
				_bit("spark", fuse, _scatter(1.3, 1.8), dice.randf_range(.12, .26), .03, 5.0)
			return .03
		"bottle_rocket":
			for _k in 2:
				_bit("spark", at, -v * .15 + _scatter(.9, .6), dice.randf_range(.15, .3), .03, 4.0)
			var puff := _bit("soot", at - v.normalized() * .1, Vector3(0, 0, .1), 1.1, .08)
			puff.grow = .4
			return .03
		"cow":
			var puff := _bit("soot", at - v.normalized() * .3, Vector3(0, 0, .12), 1.2, .14)
			puff.grow = .5
			_bit("spark", at - v.normalized() * .3, -v * .1 + _scatter(.8, .6), .25, .03, 4.0)
			return .05
	return 1.0


# ------------------------------------------------------------------ drawing


## A light for each fireball's afterglow and a hot spark of a strike on metal:
## [x, y, z, radius, Color, strength, flags, heat], as Effects.light() (view_lights.gd).
func lights() -> Array:
	var out: Array = []
	for boom: Array in booms:
		if bool(boom[5]):
			continue
		var age: float = game.clock - float(boom[3])
		var flash = Effects.light(
			"blast_flash", boom[0], boom[1], float(boom[2]) + .4, 1.0 - age / .14, game.clock
		)
		if flash != null and age < .14:
			out.append(flash)
		var glow = Effects.light(
			"boom_glow", boom[0], boom[1], float(boom[2]) + .5, 1.0 - age / BOOM_LIFE, game.clock
		)
		if glow != null:
			out.append(glow)
	return out


func sprites() -> Array:
	var out: Array = []
	if not Effects.rich:
		return out
	var p = game.player
	for bit: Bit in bits:
		if bit.age < 0.0:
			continue
		var dx: float = bit.x - p.x
		var dy: float = bit.y - p.y
		if dx * dx + dy * dy < .3 or not game.in_view(bit.x, bit.y, bit.size + .3):
			continue
		var step := bit.age / bit.life
		var name := ""
		var glow := false
		var translucent := false
		match bit.kind:
			"spark":
				continue
			"soot":
				name = "fx_soot_%d" % mini(3, int(step * 4.0))
				translucent = true
			"smoke":
				name = "fx_smoke_%d" % mini(3, int(step * 4.0))
				translucent = true
			"dust":
				name = "fx_puff_%d" % mini(3, int(step * 4.0))
				translucent = true
			"ember":
				name = "fx_ember_%d" % (int(bit.age * 9.0) % 2)
				glow = true
			"chunk":
				name = "fx_chunk_%d" % (0 if bit.rest else int(bit.age * 16.0) % 4)
			"splinter":
				name = "fx_splinter_%d" % (0 if bit.rest else int(bit.age * 14.0) % 2)
			"grit_brick", "grit_stone":
				name = "fx_" + bit.kind
			"clod":
				name = "fx_soil"
			"chaff":
				name = "fx_chaff_%d" % (int(bit.age * 6.0 + bit.size * 97.0) % 2)
			"glint":
				var flash := int(bit.age * 11.0 + bit.size * 131.0) % 5 == 0
				name = "fx_glint_%d" % (1 if flash else 0)
				glow = flash
			"drop":
				name = "fx_glint_0"
		var s: Renderer.Sprite = game.pooled(bit.x, bit.y, name, bit.size, bit.z)
		s.glow = glow
		s.translucent = translucent
		out.append(s)
	for hit: Array in hits:
		if not game.in_view(hit[0], hit[1], .5):
			continue
		var age: float = game.clock - float(hit[3])
		var size: float = hit[5]
		var art := String(hit[4])
		var frame := mini(2, int(age / HIT_LIFE * 3.0))
		var tall := 1.5 if art == "water" else 1.0
		var s: Renderer.Sprite = game.pooled(
			hit[0], hit[1], "fx_hit_%s_%d" % [art, frame], size * tall, float(hit[2]) - size * .5
		)
		s.glow = art == "metal" or art == "glass"
		out.append(s)
	_boom_sprites(out)
	return out


func _boom_sprites(out: Array) -> void:
	var p = game.player
	var order: Array = []
	for boom: Array in booms:
		var age: float = game.clock - float(boom[3])
		if age < 0.0 or not game.in_view(boom[0], boom[1], 2.5):
			continue
		var dx: float = float(boom[0]) - p.x
		var dy: float = float(boom[1]) - p.y
		order.append([dx * dx + dy * dy, boom, age])
	# Farthest first, so a nearer ball covers a farther one.
	order.sort_custom(func(a, b): return float(a[0]) > float(b[0]))
	for row: Array in order:
		var boom: Array = row[1]
		var age: float = row[2]
		var scale: float = boom[4]
		var t := clampf(age / BOOM_LIFE, 0.0, .999)
		var frame := mini(7, int(pow(t, .8) * 8.0))
		var size := (.95 + 1.7 * sqrt(t)) * scale
		var z := maxf(.02, float(boom[2]) - size * .42 + age * .55)
		var ball: Renderer.Sprite = game.pooled(boom[0], boom[1], "fx_boom_%d" % frame, size, z)
		ball.glow = frame < 5
		ball.translucent = frame >= 5
		out.append(ball)
		if age < .1 and not bool(boom[5]):
			var flash: Renderer.Sprite = game.pooled(
				boom[0], boom[1], "fx_boomflash_%d" % (0 if age < .05 else 1), 2.1, z - .3
			)
			flash.glow = true
			out.append(flash)


func ground_marks() -> Array:
	var out: Array = []
	if not Effects.rich:
		return out
	for ring: Array in shocks:
		var t: float = (game.clock - float(ring[3])) / SHOCK_LIFE
		var reach := .5 + 2.2 * sqrt(t)
		out.append(
			Renderer.GroundMark.new(
				ring[0],
				ring[1],
				ring[2],
				0.0,
				reach,
				reach,
				"mark_shock_%d" % mini(2, int(t * 3.0))
			)
		)
	return out


func draw_view(c: Canvas) -> void:
	if not Effects.rich:
		return
	# Sparks as short streaks along the way they fly, white-hot to orange.
	for bit: Bit in bits:
		if bit.kind != "spark" or bit.age < 0.0:
			continue
		var a: Vector3 = game.to_canvas(bit.x, bit.y, bit.z)
		var b: Vector3 = game.to_canvas(
			bit.x - bit.vx * .03, bit.y - bit.vy * .03, bit.z - bit.vz * .03
		)
		if a.z < 0.0 or b.z < 0.0:
			continue
		if a.y >= Renderer.VIEW or b.y >= Renderer.VIEW or a.x < 0 or a.x >= Renderer.WIDTH:
			continue
		var heat := 1.0 - bit.age / bit.life
		var colour := (
			Color8(255, 252, 220)
			if heat > .6
			else Color8(255, 200, 96) if heat > .3 else Color8(232, 112, 36)
		)
		c.stroke(int(b.x), int(b.y), int(a.x), int(a.y), colour, 2 if a.z < 1.6 else 1)
