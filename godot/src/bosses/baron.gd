## THE COPPER BARON, the quarry's boss: steam out of the pipe outlets
## (pressure_ports), slower once the relief valves are open (enemies.cfg [baron]).
##
## Kind `baron`. His fight in the still house (quarry_plan.gd):
##   outlets      the ones that blow are those nearest where the player stood
##                as he wound up (game_world.gd pressure_ports reads them off
##                him), so standing still gets you scalded; an outlet blowing
##                under him scalds him too (features/boss_arenas.gd).
##   phase 3      COPPER RAIN: every other attack he blows his safety valve and
##                red-hot copper comes down on five marked spots round the
##                player, each a burst of steam; the house's pipes burst along
##                the walls (boss_arenas.gd).
##   weak spot    the boiler on his back with its gauge: a hit from behind him,
##                body high, counts double.
##   HOG WILD     BLOWDOWN: every third outlet attack, every outlet in the house
##                goes a beat after the ones he picked.
class_name BaronMoves
extends BossMoves

const RAIN_WINDUP := 1.15
const RAIN_DAMAGE := 16
const RAIN_RADIUS := .85
## How far off his facing a shot must come from to strike the boiler on his back.
const BEHIND := 1.95
const WEAK := 2.0
## Wind-ups and the rain's pace by difficulty, EASY .. HOG WILD.
const PACE := [1.3, 1.0, .92, .84]
## His cooldown after an attack, by phase, of what the brain gives.
const COOLDOWN := [.75, .65, .6]


## Whether his next attack (after `done` attacks) is the outlets rather than
## the steam sweep off his own boiler: every other one, and once fightin' mad
## two in three (it was every one, which left nothing aimed at the player).
static func outlets_next(done: int, mad: bool) -> bool:
	return done % 2 == 1 or (mad and done % 3 != 0)


## A load of buckshot at the range he keeps does not knock a man in a boiler
## suit off his feet; a stick of dynamite at them does, and not often.
func stagger_hit(_e: Enemy) -> float:
	return 170.0


func stagger_rest(_e: Enemy) -> float:
	return 6.0


func phase_changed(e: Enemy, game, phase: int) -> void:
	if phase == 3:
		var arenas = game.features.get("boss_arenas")
		if arenas != null:
			arenas.turn(e)


func tick(e: Enemy, dt: float, game) -> bool:
	if e.windup <= 0.0 and not e.has_meta("rain"):
		_pick_outlets(e, game)
	var paced := int(e.get_meta("paced", 0))
	if e.attacks != paced:
		# He comes again quicker than the hands do, quicker still as he weakens.
		e.set_meta("paced", e.attacks)
		e.cooldown *= float(COOLDOWN[clampi(e.boss_phase - 1, 0, 2)])
	if hog_wild(game):
		_blowdown(e, game)
	if e.has_meta("rain"):
		e.windup = maxf(0.0, e.windup - dt)
		e.angle = atan2(game.player.y - e.y, game.player.x - e.x)
		if e.windup <= 0.0 or e.stun > .3:
			_rain_done(e, game)
		return true
	if _rain_ready(e, dt, game):
		_rain(e, game)
		return true
	return false


## The outlets for his next steam attack: the ones nearest the player now
## (fixed once he winds up: the marks are where it will blow).
func _pick_outlets(e: Enemy, game) -> void:
	var ports: Array = game.world.pressure_ports
	if ports.is_empty():
		return
	var p = game.player
	var order := ports.duplicate()
	order.sort_custom(
		func(a: Vector2, b: Vector2) -> bool:
			return (
				a.distance_squared_to(Vector2(p.x, p.y)) < b.distance_squared_to(Vector2(p.x, p.y))
			)
	)
	e.set_meta("ports_for", e.attacks)
	e.set_meta("ports", order.slice(0, 3))


func _rain_ready(e: Enemy, dt: float, game) -> bool:
	if e.boss_phase < 3 or not e.alerted or e.windup > 0.0 or e.stun > 0.0:
		return false
	if e.cooldown > dt * float(game.sharpness) or e.recovery > .17 or e.attacks % 2 != 0:
		return false
	var p = game.player
	return e.player_seen and Vector2(p.x - e.x, p.y - e.y).length() <= float(Enemy.REACH[e.kind])


## COPPER RAIN: the safety valve goes and the copper comes down round the player.
func _rain(e: Enemy, game) -> void:
	var p = game.player
	var pace: float = PACE[clampi(game.difficulty, 0, 3)]
	e.windup = RAIN_WINDUP * pace
	e.aim_mark = null
	e.angle = atan2(p.y - e.y, p.x - e.x)
	e.set_meta("rain", true)
	e.set_meta("tell", "COPPER RAIN")
	var arenas = game.features.get("boss_arenas")
	var turn := e.attacks * .7
	var spots: Array = [Vector2(p.x, p.y)]
	for k in 4:
		var a := turn + k * TAU / 4.0
		spots.append(Vector2(p.x + cos(a) * 1.9, p.y + sin(a) * 1.9))
	var k := 0
	for at: Vector2 in spots:
		if game.world.blocked(at.x, at.y, .25) or arenas == null:
			continue
		arenas.drop(
			"steam", at.x, at.y, e.windup + .25 + k * .12, RAIN_RADIUS, RAIN_DAMAGE, "COPPER RAIN"
		)
		k += 1
	game.sound_at("baron_warn", e.x, e.y, 1.0)
	game.sound_at("pressure_vent", e.x, e.y, .9)
	var floor_z: float = game.world.stand(e)
	game.burst(e.x, e.y, floor_z + e.height * .9, "spark", 10, 2.4)


func _rain_done(e: Enemy, game) -> void:
	e.remove_meta("rain")
	e.remove_meta("tell")
	e.windup = 0.0
	e.attacks += 1
	e.set_meta("seen_attacks", e.attacks)
	e.cooldown = 1.4 * PACE[clampi(game.difficulty, 0, 3)]
	e.recovery = .7


## HOG WILD's blowdown: an outlet attack just went; every third one, the rest
## of the house's outlets go too, a beat later (their warning shows).
func _blowdown(e: Enemy, game) -> void:
	var seen := int(e.get_meta("seen_attacks", e.attacks))
	e.set_meta("seen_attacks", e.attacks)
	if e.attacks == seen or e.has_meta("rain"):
		return
	var ports_attack := outlets_next(e.attacks - 1, e.enraged)
	if not ports_attack or int(e.attacks / 2) % 3 != 1:
		return
	var used: Array = game.pressure_ports(e.attacks - 1)
	for point: Vector2 in game.world.pressure_ports:
		if not used.has(point):
			game.add_hazard("steam", point.x, point.y, .94, .75, 1.6, 15)
	game.message("BLOWDOWN! EVERY OUTLET'S GOING!", 1.6)
	game.sound_at("baron_rage", e.x, e.y, .8)


## The boiler on his back: hit from behind him at body height.
func weak_spot(e: Enemy, game, hit: Vector3, from: Vector2, how: String) -> float:
	if how == "blast" or how == "energy" or how == "steam" or how == "fire":
		return 1.0
	var toward_shooter := atan2(from.y - e.y, from.x - e.x)
	if absf(Enemy.angle_delta(toward_shooter, e.angle)) < BEHIND:
		return 1.0
	var up: float = (hit.z - game.world.stand(e)) / maxf(.5, e.height)
	return WEAK if up > .35 and up < .95 else 1.0


## The boiler on his back venting harder as he weakens; red-hot in phase 3.
func looks(e: Enemy, game) -> Array:
	var out: Array = []
	if e.boss_phase < 2 and not e.has_meta("rain"):
		return out
	var floor_z: float = game.world.stand(e)
	var back := Vector2(e.x - cos(e.angle) * .32, e.y - sin(e.angle) * .32)
	var puffs := 2 if e.boss_phase < 3 else 4
	for k in puffs:
		var age := fposmod(game.clock * 1.4 + float(k) / puffs, 1.0)
		var s := Renderer.Sprite.new(
			back.x + sin(game.clock * 3.0 + k) * .1,
			back.y + cos(game.clock * 2.6 + k) * .1,
			"fx_steam_%d" % mini(3, int(age * 4.0)),
			.35 + age * .5,
			floor_z + e.height * (.85 + age * .5)
		)
		s.translucent = true
		out.append(s)
	if e.boss_phase >= 3 or e.has_meta("rain"):
		var glow := Renderer.Sprite.new(
			back.x,
			back.y,
			"fx_sparks_%d" % (int(game.clock * 12.0) % 3),
			.3,
			floor_z + e.height * .62
		)
		glow.glow = true
		out.append(glow)
	return out


## His boiler goes as he falls: a roar of steam and copper.
func dying(e: Enemy, game) -> void:
	var floor_z: float = game.world.stand(e)
	game.blasts.append(GameState.Blast.new(e.x, e.y, floor_z + e.height * .7, "fire"))
	game.sound_at("boiler_release", e.x, e.y, 1.0)
	game.sound_at("pressure_vent", e.x, e.y, 1.0)
	var fight = game.features.get("boss_fight")
	if fight != null:
		fight.sparks(e.x, e.y, floor_z + e.height * .8, "dust", 24, 2.6)
		fight.sparks(e.x, e.y, floor_z + e.height * .6, "chips", 14, 3.0)
	game.message("THE BARON'S BOILER BLEW!", 2.6)
