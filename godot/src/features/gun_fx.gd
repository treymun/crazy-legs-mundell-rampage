## The graphics-card view's own layer of gun and blast effects, shown only
## while it draws with LIGHTS AND GLOW (Effects.rich): the software view keeps
## weapon_fx.gd's as they were. Its pictures are build_gun_fx_art.gd's, hard
## edged and few-coloured like a 1997 sprite.
##
## A blast (src/blast_looks.gd, by data/tuning/blast_looks.cfg): a white star
## the instant it goes, a fireball rolling up in lobes and going over to soot
## with smaller ones bursting beside it, a soot column rolling up into a
## mushroom, scraps arcing out trailing smoke, clods, dirt puffs rolling out
## along the ground, sparks, embers, burning drops, a crater with soot
## streaks, the yard lit by it a moment (lights()) and the view kicked
## (feel.gd punch()); each its own, by what blew and where. A vehicle hurt
## and wrecked (src/vehicle_wreck_looks.gd): engine smoke, sparks off its
## tin, its parts flying, its hulk burning and popping. A round
## striking: a burst of what it struck by material (sparks, brick dust, wood
## dust and splinters, dirt, glass, a splash, leaves) and more of it flying. A
## shot leaving the gun: burning wadding, a puff of smoke, sparks. Dynamite
## fuses and bottle rockets spit sparks; rockets and cows lay soot.
##
## Looks only: its own dice, never saved, never in the way. Everything is
## made whatever the view (so the shader view's picture does not depend on
## what was drawn before), and capped: blast_looks.cfg `most_bits` in the air
## (fewer on a phone or QUALITY LOW), MAX_BOOMS fireballs, MAX_HITS strikes,
## and a chain of blasts throws fewer bits each (never a smaller fireball).
extends GameFeature

const Bit := preload("res://src/fx_bit.gd")
## What the 3D view draws as tumbling slabs (sprites(); SlabModels LOOSE).
const TUMBLES := {
	"chunk": true, "splinter": true, "grit_brick": true, "grit_stone": true, "clod": true
}
const MAX_BOOMS := 8
const MAX_HITS := 20
## Seconds a fireball of a blast the game made without a look (a boss's)
## takes to burn through its frames.
const BOOM_LIFE := 1.0
const HIT_LIFE := .24
## The billows' and scraps' picture names by shape (fx_billow_<v>_N).
const BILLOW: Array[String] = ["fx_billow_0_", "fx_billow_1_", "fx_billow_2_"]
const BILLOW_HOT: Array[String] = ["fx_billowhot_0_", "fx_billowhot_1_", "fx_billowhot_2_"]
const BILLOW_POWDER: Array[String] = [
	"fx_billowpowder_0_", "fx_billowpowder_1_", "fx_billowpowder_2_"
]
const SCRAP_METAL := "fx_scrap_metal_"
const SCRAP_MEAT := "fx_scrap_meat_"
## Sparks drawn a frame at most (draw_view: each a stroke on the canvas).
const SPARKS_DRAWN := 48
## Seconds a burning drop lies burning once it lands.
const DROP_BURN := 1.6
## Seconds a water column takes to rise and fall back.
const GEYSER_LIFE := 1.1
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

static var _names := {}
var dice := RandomNumberGenerator.new()
## The bits in the air (FxBit). The helpers append to this same array, so it
## is changed in place, never swapped for another.
var bits: Array = []
## [x, y, z, born, scale, side lobe, fire, shape, life, flip, flash, glow]
## (src/blast_looks.gd)
var booms: Array = []
## A blast's column of water: [x, y, z, born, size].
var geysers: Array = []
var blast_looks: BlastLooks
var wrecks: VehicleWreckLooks
## Sounds to play a moment later: [when, cue, x, y, volume].
var _later: Array = []
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
	blast_looks = BlastLooks.new(game, dice, bits, booms, geysers)
	wrecks = VehicleWreckLooks.new(game, dice, bits, booms)
	game.events.shot_fired.connect(_fired)
	game.events.traced.connect(_traced)
	game.events.exploded.connect(_exploded)
	tick_with(_tick)


func _bit(kind: String, at: Vector3, v: Vector3, life: float, size: float, gravity := 0.0) -> Bit:
	var bit := Bit.make(kind, at, v, life, size, gravity)
	bits.append(bit)
	if bits.size() > blast_looks.most_bits:
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
	var p := game.player
	var a: float = p.view_angle()
	return Vector3(p.x + cos(a) * far - sin(a) * .1, p.y + sin(a) * far + cos(a) * .1, p.eye - .16)


# ------------------------------------------------------------------ firing


func _fired(gun: int) -> void:
	if game.own_quiet:
		game.hands_watch.defer(_fired.bind(gun), "shot")
		return
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


func own_shot(gun: int) -> void:
	_fired(gun)


func _traced(end: Vector3, struck: String) -> void:
	if game.own_quiet:
		game.hands_watch.defer(_traced.bind(end, struck), "trace")
		return
	var gun: int = game.armory.active
	var firing: Dictionary = Weapons.FIRING[gun]
	var mode := str(firing.get("fire", ""))
	if mode != "hitscan" and mode != "pellets":
		return
	if gun == Weapons.PRESSURE or gun == Weapons.TEAT:
		return
	var shooter := game.player
	wrecks.struck(Vector3(shooter.x, shooter.y, shooter.eye - .1), end)
	var kind := ""
	if struck == "glass":
		kind = "glass"
	elif struck.begins_with("wall:") and struck != "wall:":
		kind = game.impact_kind
	if not HIT_ART.has(kind):
		return
	_pellets += 1
	if gun == Weapons.SHOTGUN and _pellets > PELLET_HITS:
		return
	var p := game.player
	var dir := (end - Vector3(p.x, p.y, p.eye)).normalized()
	var at := end - dir * .06
	var art := str(HIT_ART[kind])
	var big := 1.3 if gun == Weapons.RIFLE else .8 if gun == Weapons.SHOTGUN else 1.0
	if gun == Weapons.HUNTER or gun == Weapons.MARKSMAN:
		big = 1.7 if gun == Weapons.HUNTER else 1.5
	elif gun == Weapons.STAR357 or gun == Weapons.HOGLEG:
		big = 1.25
	elif gun == Weapons.RIOT_PUMP:
		big = .8
	elif gun == Weapons.MOWER:
		big = 1.2
	var size := (.55 if art == "metal" or art == "glass" else .8) * big
	hits.append([at.x, at.y, at.z, game.clock, art, size])
	if hits.size() > MAX_HITS:
		hits.pop_front()
	var out := -dir
	match art:
		"metal":
			for _k in 7:
				_bit(
					"spark", at, _scatter(2.6, 2.2) + out * 1.2, dice.randf_range(.18, .4), .03, 7.0
				)
		"wood":
			for _k in 3:
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
			for _k in 5:
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
			for _k in 4:
				var v := _scatter(.9, 0.0) + out * .6
				v.z = dice.randf_range(1.6, 2.6)
				_bit("clod", at, v, dice.randf_range(.6, .9), .04, 9.0)
			_puff(at, out, "dust", .2 * big)
		"glass":
			for _k in 5:
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


func own_trace(end: Vector3, struck: String) -> void:
	_traced(end, struck)


## Something come down in water (water.gd splash()): the water strike's
## crest, as big as it was, and drops thrown up round it.
func splash(x: float, y: float, z: float, size: float) -> void:
	var at := Vector3(x, y, z)
	var crest := clampf(.35 + size * .35, .35, 1.4)
	hits.append([x, y, z + crest * .5, game.clock, "water", crest])
	if hits.size() > MAX_HITS:
		hits.pop_front()
	for _k in clampi(int(2.0 + size * 4.0), 2, 10):
		var v := _scatter(.5 + size * .3, 0.0)
		v.z = dice.randf_range(1.4, 2.4) * (.8 + minf(size, 2.0) * .25)
		_bit("drop", at, v, .6, .03, 9.0)


func _puff(at: Vector3, out: Vector3, kind: String, size: float) -> void:
	var puff := _bit(kind, at + out * .05, out * .45 + Vector3(0, 0, .18), .9, size)
	puff.grow = size * 2.2


# --------------------------------------------------------------- explosions


func _exploded(x: float, y: float, z: float, energy: bool) -> void:
	if game.blast_quiet:
		return  # shown already by an online client's own blast (net_own_shots.gd)
	if energy:
		return
	wrecks.blasted(x, y)
	# A chain going up throws fewer bits each blast (never a smaller fireball),
	# so a row of barrels reads as boom after boom without swamping the frame.
	var since: float = game.clock - 1.0
	while not _recent.is_empty():
		var oldest: float = _recent[0]
		if not (oldest < since):
			break
		_recent.pop_front()
	var less: float = blast_looks.setting("chain_less", .18)
	var least: float = blast_looks.setting("chain_least", .35)
	var share := maxf(least, 1.0 - less * _recent.size())
	_recent.append(game.clock)
	# The game's own record of this blast has its fireball here.
	if not game.blasts.is_empty():
		var last: GameState.Blast = game.blasts[game.blasts.size() - 1]
		if absf(last.x - x) < .01 and absf(last.y - y) < .01:
			_seen_blasts[last.get_instance_id()] = true
	var look := blast_looks.look_of(game.blast_kind, x, y)
	var where := blast_looks.place(x, y, z)
	blast_looks.burst(x, y, z, look, where, share)
	var floor_z: float = where["floor"]
	var wet: bool = where["water"]
	if z - floor_z < 1.2 and not wet:
		shocks.append([x, y, floor_z + .006, game.clock])
		if shocks.size() > 4:
			shocks.pop_front()
	_kick(x, y, look)
	_sounds(x, y, look)


## A blast's own layer (a fuel fireball's whoomp) now, and what it threw
## raining down a moment later.
func _sounds(x: float, y: float, look: Dictionary) -> void:
	var layer := str(look.get("layer", ""))
	if layer != "":
		game.sound_at(layer, x, y, .9)
	var scraps: float = look.get("scraps", 0)
	var from: float = blast_looks.setting("debris_from", 5)
	if scraps >= from:
		var after: float = blast_looks.setting("debris_after", .55)
		var cue := str(blast_looks.setting("debris_cue", ""))
		if cue != "" and _later.size() < 6:
			_later.append([game.clock + after * dice.randf_range(.85, 1.25), cue, x, y, .75])
			_later.sort_custom(
				func(a: Array, b: Array) -> bool:
					var at_a: float = a[0]
					var at_b: float = b[0]
					return at_a < at_b
			)


## The view kicked by a blast near the local player, by how near and how big
## (features/feel.gd punch(), as far as SCREEN SHAKE lets it; game_combat's
## shake still rattles it as before).
func _kick(x: float, y: float, look: Dictionary) -> void:
	var feel: GameFeature = game.features.get("feel")
	var ear := game.local_player
	if feel == null or ear == null:
		return
	var reach: float = blast_looks.setting("kick_reach", 7.0)
	var d := Vector2(x - ear.x, y - ear.y).length()
	if d >= reach:
		return
	var most: float = blast_looks.setting("kick", 1.0)
	var big: float = look.get("kick", 1.0)
	var k := pow(1.0 - d / reach, 2.0) * most * big
	# Away from the blast: one off to a side throws the view the other way.
	var side := sin(atan2(y - ear.y, x - ear.x) - ear.view_angle())
	feel.call("punch", -side * .03 * k, 5.0 * k, .035 * k, Vector2(-side * 9.0 * k, 12.0 * k))


## A fireball for each fire blast the game made without going off through
## explode() (a boss's flames, the bayou's gator): those that did have theirs
## from _exploded.
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
		booms.append(
			[
				blast.x,
				blast.y,
				blast.z,
				born,
				1.0,
				false,
				"d",
				dice.randi_range(0, BlastLooks.SHAPES - 1),
				BOOM_LIFE,
				dice.randf() < .5,
				1.0,
				1.0
			]
		)
	if not _seen_blasts.is_empty():
		_seen_blasts = _keep(live)
	while booms.size() > MAX_BOOMS * 4:
		booms.pop_front()


func _keep(live: Dictionary) -> Dictionary:
	var kept := {}
	for key: Variant in _seen_blasts:
		if live.has(key):
			kept[key] = true
	return kept


# --------------------------------------------------------------------- tick


func _tick(dt: float) -> void:
	_new_blasts()
	_follow_shots()
	wrecks.tick()
	while not _later.is_empty():
		var due: Array = _later[0]
		var when: float = due[0]
		if game.clock < when:
			break
		_later.pop_front()
		var dx: float = due[2]
		var dy: float = due[3]
		var loud: float = due[4]
		game.sound_at(str(due[1]), dx, dy, loud)
	var wind := Vector2.ZERO
	if not bits.is_empty():
		wind = Effects.DEBRIS.get("wind_" + game.level.id, Vector2.ZERO)
	var world := game.world
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
				# Drifts on the wind; a mushroom's cap spreads out once it has
				# risen a while; a dirt puff rolls out and is slowed by the air.
				var drift := wind
				if bit.spread != Vector2.ZERO and bit.age > .45:
					drift += bit.spread
				var pull := 1.6 if bit.kind != "dust" else 2.4
				bit.vx += (drift.x - bit.vx) * minf(1.0, dt * pull)
				bit.vy += (drift.y - bit.vy) * minf(1.0, dt * pull)
				bit.vz *= 1.0 - minf(1.0, dt * .6)
			"chaff":
				bit.vx += (wind.x - bit.vx) * minf(1.0, dt * 2.0)
				bit.vy += (wind.y - bit.vy) * minf(1.0, dt * 2.0)
				bit.vz = maxf(bit.vz, -.6)
			"chunk":
				bit.trail -= dt
				if bit.trail <= 0.0 and bit.age < bit.life * .5:
					bit.trail = .14
					var wisp := Bit.make(
						"soot", Vector3(bit.x, bit.y, bit.z), Vector3(0, 0, .25), .75, .11
					)
					wisp.grow = .45
					wisp.look = "soot"
					kept.append(wisp)
		var nx := bit.x + bit.vx * dt
		var ny := bit.y + bit.vy * dt
		if bit.gravity > 0.0 and world.blocked(nx, ny, .02, bit.z):
			bit.vx *= -.3
			bit.vy *= -.3
		else:
			bit.x = nx
			bit.y = ny
		bit.z += bit.vz * dt
		if bit.gravity <= 0.0:
			continue
		var floor_z: float = world.floor_under(bit.x, bit.y, bit.z + .3)
		if bit.z <= floor_z:
			bit.z = floor_z
			if bit.kind == "spark" or bit.kind == "drop":
				bit.life = bit.age
			elif bit.kind == "burning":
				# A burning drop lies burning a moment where it fell.
				bit.rest = true
				bit.landed = bit.age
				bit.life = bit.age + DROP_BURN * (.6 + fposmod(bit.x * 7.3 + bit.y * 3.1, .8))
			elif bit.vz < -2.0 and bit.kind != "chaff":
				bit.vz *= -.3
				bit.vx *= .5
				bit.vy *= .5
			else:
				bit.rest = true
				bit.landed = bit.age
	bits.assign(kept)
	if bits.size() > blast_looks.most_bits:
		bits.assign(bits.slice(bits.size() - blast_looks.most_bits))
	var k := 0
	while k < booms.size():
		var boom: Array = booms[k]
		var boom_at: float = boom[3]
		var boom_life: float = boom[8]
		if game.clock - boom_at > boom_life:
			booms.remove_at(k)
		else:
			k += 1
	while not geysers.is_empty():
		var g: Array = geysers[0]
		var g_at: float = g[3]
		if not (game.clock - g_at > GEYSER_LIFE):
			break
		geysers.pop_front()
	while not hits.is_empty():
		var hit: Array = hits[0]
		var hit_at: float = hit[3]
		if not (game.clock - hit_at > HIT_LIFE):
			break
		hits.pop_front()
	while not shocks.is_empty():
		var ring: Array = shocks[0]
		var ring_at: float = ring[3]
		if not (game.clock - ring_at > SHOCK_LIFE):
			break
		shocks.pop_front()


## What the player's shots shed as they fly, over weapon_fx.gd's.
func _follow_shots() -> void:
	if game.shots.is_empty() and _following.is_empty():
		return
	var seen := {}
	for shot: GameState.Shot in game.shots:
		if shot.enemy:
			continue
		var key: int = shot.get_instance_id()
		seen[key] = true
		var next: float = _following.get(key, game.clock)
		if game.clock >= next:
			next = game.clock + _shed(shot)
		_following[key] = next
	if _following.size() > seen.size():
		for key: Variant in _following.keys():
			if not seen.has(key):
				_following.erase(key)


func _shed(shot: GameState.Shot) -> float:
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


## A light for each fireball's flash and afterglow, by its look's `flash` and
## `glow` (a lobe beside it has none; a wreck's pop a little), and over each
## burning wreck: [x, y, z, radius, Color, strength, flags, heat], as
## Effects.light() (view_lights.gd).
func lights() -> Array:
	var out: Array = []
	for boom: Array in booms:
		var flash_k: float = boom[10]
		var glow_k: float = boom[11]
		if flash_k <= 0.0 and glow_k <= 0.0:
			continue
		var boom_at: float = boom[3]
		var age: float = game.clock - boom_at
		if age < 0.0:
			continue
		var life: float = boom[8]
		var bx: float = boom[0]
		var by: float = boom[1]
		var bz: float = boom[2]
		if age < .14 and flash_k > 0.0:
			var flash: Variant = Effects.light(
				"blast_flash", bx, by, bz + .4, (1.0 - age / .14) * flash_k, game.clock
			)
			if flash != null:
				var lit: Array = flash
				var reach: float = lit[3]
				lit[3] = reach * sqrt(flash_k)
				out.append(lit)
		var glow: Variant = Effects.light(
			"boom_glow", bx, by, bz + .5, (1.0 - age / (life * 1.2)) * glow_k, game.clock
		)
		if glow != null:
			out.append(glow)
	wrecks.lights(out)
	return out


func sprites() -> Array:
	var out: Array = []
	if not Effects.rich:
		return out
	var p := game.player
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
			"soot", "smoke", "dust":
				name = _smoke_art(bit, step)
				# The column's billows are hard-edged and solid (drawn with the
				# solid sprites: no blending, no overdraw); the rest blend.
				translucent = not bit.look.begins_with("billow")
			"ember":
				name = _nm("fx_ember_", int(bit.age * 9.0) % 2)
				glow = true
			"burning":
				# A burning drop: an ember falling, a little flame once it lies.
				if bit.rest:
					name = _nm("fx_flame_", int(bit.age * 12.0 + bit.x * 7.0) % 4)
					var left := bit.life - bit.age
					bit.size = .2 * clampf(left / .5, .2, 1.0)
				else:
					name = _nm("fx_ember_", int(bit.age * 9.0) % 2)
				glow = true
			"chunk":
				var turn := 0 if bit.rest else int(bit.age * 16.0) % 4
				if bit.look == "":
					name = _nm("fx_chunk_", turn)
				else:
					name = _nm(SCRAP_METAL if bit.look == "metal" else SCRAP_MEAT, turn)
			"splinter":
				name = _nm("fx_splinter_", 0 if bit.rest else int(bit.age * 14.0) % 2)
			"grit_brick", "grit_stone":
				name = "fx_" + bit.kind
			"clod":
				name = "fx_soil"
			"chaff":
				name = _nm("fx_chaff_", int(bit.age * 6.0 + bit.size * 97.0) % 2)
			"glint":
				var flash := int(bit.age * 11.0 + bit.size * 131.0) % 5 == 0
				name = _nm("fx_glint_", 1 if flash else 0)
				glow = flash
			"drop":
				name = "fx_glint_0"
		var s: View.Sprite = game.pooled(bit.x, bit.y, name, bit.size, bit.z)
		s.glow = glow
		s.translucent = translucent
		s.flip = bit.flip
		if TUMBLES.has(bit.kind):
			# The 3D view tumbles it in the air, by where it is (nothing kept),
			# and lays it flat on the floor.
			# Come to rest it eases over onto a face from the turn it came down
			# at (the same sum where it lies).
			s.lying = bit.rest or bit.vz == 0.0
			s.spin = (bit.x * 3.7 - bit.y * 2.9 + bit.z * 5.3) * .3 / maxf(.03, bit.size)
			if s.lying:
				s.settle = View.SETTLED
				if bit.rest and bit.landed >= 0.0:
					s.settle = minf(bit.age - bit.landed, View.SETTLED)
		out.append(s)
	for hit: Array in hits:
		var hx: float = hit[0]
		var hy: float = hit[1]
		if not game.in_view(hx, hy, .5):
			continue
		var hit_at: float = hit[3]
		var age: float = game.clock - hit_at
		var size: float = hit[5]
		var art := str(hit[4])
		var frame := mini(3, int(age / HIT_LIFE * 4.0))
		var tall := 1.5 if art == "water" else 1.0
		var hz: float = hit[2]
		var s: View.Sprite = game.pooled(
			hx, hy, "fx_hit_%s_%d" % [art, frame], size * tall, hz - size * .5
		)
		s.glow = art == "metal" or art == "glass"
		out.append(s)
	_boom_sprites(out)
	_geyser_sprites(out)
	wrecks.flames(out)
	return out


## A smoke bit's picture by its look and age: the column's soot (lit from
## under while young), a keg's powder smoke, the dirt a blast rolls out, gun
## smoke, a puff of dust.
func _smoke_art(bit: Bit, step: float) -> String:
	var frame := mini(3, int(step * 4.0))
	match bit.look:
		"billowhot":
			# Lit from under while young, over the fire.
			if bit.age < .8:
				return _nm(BILLOW_HOT[bit.shape], mini(2, int(bit.age / .8 * 3.0)))
			return _nm(BILLOW[bit.shape], frame)
		"billow":
			return _nm(BILLOW[bit.shape], frame)
		"billowpowder":
			return _nm(BILLOW_POWDER[bit.shape], frame)
		"soot":
			return _nm("fx_soot_", frame)
		"dirtpuff":
			return _nm("fx_dirtpuff_", frame)
		"smoke":
			return _nm("fx_smoke_", frame)
	match bit.kind:
		"soot":
			return _nm("fx_soot_", frame)
		"smoke":
			return _nm("fx_smoke_", frame)
	return _nm("fx_puff_", frame)


## A picture's name `prefix` + `i`, made once (a list of two hundred bits a
## frame formatted every name each time).
static func _nm(prefix: String, i: int) -> String:
	var known: Variant = _names.get(prefix)
	if known == null:
		var made := PackedStringArray()
		for k in 16:
			made.append(prefix + str(k))
		_names[prefix] = made
		known = made
	var list: PackedStringArray = known
	return list[i]


func _geyser_sprites(out: Array) -> void:
	for g: Array in geysers:
		var gx: float = g[0]
		var gy: float = g[1]
		if not game.in_view(gx, gy, 2.0):
			continue
		var g_at: float = g[3]
		var t := clampf((game.clock - g_at) / GEYSER_LIFE, 0.0, .999)
		var size: float = g[4]
		var gz: float = g[2]
		var column: View.Sprite = game.pooled(
			gx, gy, "fx_geyser_%d" % int(t * 5.0), 1.8 * size, gz - .05
		)
		out.append(column)


func _boom_sprites(out: Array) -> void:
	var p := game.player
	var order: Array = []
	for boom: Array in booms:
		var boom_at: float = boom[3]
		var age: float = game.clock - boom_at
		var bx: float = boom[0]
		var by: float = boom[1]
		if age < 0.0 or not game.in_view(bx, by, 2.5):
			continue
		var dx: float = bx - p.x
		var dy: float = by - p.y
		order.append([dx * dx + dy * dy, boom, age])
	# Farthest first, so a nearer ball covers a farther one.
	order.sort_custom(
		func(a: Array, b: Array) -> bool:
			var da: float = a[0]
			var db: float = b[0]
			return da > db
	)
	for row: Array in order:
		var boom: Array = row[1]
		var age: float = row[2]
		var scale: float = boom[4]
		var life: float = boom[8]
		# Its fire burns through in the first four fifths of its life (the
		# column's billows have taken over by then); the light lasts longer.
		var t := age / (life * .8)
		if t >= 1.0:
			continue
		# Its fire frames only: the smoke it goes over to is the column's
		# billows (blast_looks.gd _column), not one flat disc.
		var frame := mini(BlastLooks.SHOWN - 1, int(pow(t, .8) * BlastLooks.SHOWN))
		# A bright core out fast, then the lobes roll up and out.
		var size := (.95 + 1.45 * sqrt(minf(t, .5) / .5)) * scale
		var bx: float = boom[0]
		var by: float = boom[1]
		var bz: float = boom[2]
		var side: bool = boom[5]
		var z := maxf(.02, bz - size * .42 + age * .5 * scale)
		var shape: int = boom[7]
		var picture := "fx_boom_%s%d_%d" % [str(boom[6]), shape, frame]
		var ball: View.Sprite = game.pooled(bx, by, picture, size, z)
		ball.glow = true
		ball.flip = boom[9]
		out.append(ball)
		if age < .1 and not side:
			var flash: View.Sprite = game.pooled(
				bx, by, "fx_boomflash_%d" % (0 if age < .05 else 1), 2.1 * sqrt(scale), z - .3
			)
			flash.glow = true
			out.append(flash)


func ground_marks() -> Array:
	var out: Array = []
	if not Effects.rich:
		return out
	blast_looks.crater_marks(out)
	for ring: Array in shocks:
		var ring_at: float = ring[3]
		var t: float = (game.clock - ring_at) / SHOCK_LIFE
		var reach := .5 + 2.2 * sqrt(t)
		var rx: float = ring[0]
		var ry: float = ring[1]
		var rz: float = ring[2]
		out.append(
			View.GroundMark.new(
				rx, ry, rz, 0.0, reach, reach, "mark_shock_%d" % mini(2, int(t * 3.0))
			)
		)
	return out


func draw_view(c: Canvas) -> void:
	if not Effects.rich:
		return
	# Sparks as short streaks along the way they fly, white-hot to orange
	# (the newest SPARKS_DRAWN at most: each is a draw command).
	var drawn := 0
	for k in range(bits.size() - 1, -1, -1):
		var bit: Bit = bits[k]
		if bit.kind != "spark" or bit.age < 0.0:
			continue
		drawn += 1
		if drawn > SPARKS_DRAWN:
			break
		var a: Vector3 = game.to_canvas(bit.x, bit.y, bit.z)
		var b: Vector3 = game.to_canvas(
			bit.x - bit.vx * .03, bit.y - bit.vy * .03, bit.z - bit.vz * .03
		)
		if a.z < 0.0 or b.z < 0.0:
			continue
		if a.y >= View.VIEW or b.y >= View.VIEW or a.x < 0 or a.x >= View.WIDTH:
			continue
		var heat := 1.0 - bit.age / bit.life
		var colour := (
			Color8(255, 252, 220)
			if heat > .6
			else Color8(255, 200, 96) if heat > .3 else Color8(232, 112, 36)
		)
		c.stroke(int(b.x), int(b.y), int(a.x), int(a.y), colour, 2 if a.z < 1.6 else 1)


## A shine cocktail bursting (modes/tactical_utility.gd: its fire patch is
## play; this is only how it bursts, through its blast look).
func firebomb(x: float, y: float, z: float) -> void:
	var look := blast_looks.look_of("shine_cocktail", x, y)
	blast_looks.burst(x, y, z, look, blast_looks.place(x, y, z), 1.0)


## A wrecked vehicle's hulk (features/vehicles.gd sprites(); null: its model).
func hulk(i: int) -> View.Sprite:
	return wrecks.hulk(i) if wrecks != null else null
