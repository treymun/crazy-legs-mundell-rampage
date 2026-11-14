## What COUNTY RUN's upgrades and milestone abilities do in a fight (CLAUDE.md
## "County Run"), from the game's events and the rules' hooks
## (county_mode.gd): fire rate and extra pellets as a shot goes, reloads sped
## up, the streaks (DEADEYE, CALLED SHOT, the SHOWDOWN's charge) and the
## close-range ones (TIGHT CHOKE, HEAVY HAND) on each hit, then what a hit
## does after (pellets and a charged round going through, a WIDE SWING, a
## shove), blasts (PACKED and SHAPED CHARGE, CHAIN REACTION), and the
## abilities: LAST STAND, SECOND WIND, MUDSLIDE, BREAKAWAY. Numbers:
## data/tuning/county.json. Dice: none (every effect is a fixed number).
class_name CountyMoves
extends RefCounted

## A varmint this tough or tougher counts for HEAVY HAND and CALLED SHOT.
const TOUGH := 90.0
## Seconds after a crowd thins that BREAKAWAY still counts it as escaped.
const ESCAPE := 2.5
## How long MUDSLIDE slides.
const SLIDE := .26
## The blast CHAIN REACTION sets off (shots.cfg [county_chain]).
const CHAIN := "county_chain"


static func gun_of_shot(kind: String) -> int:
	return Modes.shot_weapon(kind)


static func _streak_gun(gun: int) -> bool:
	return String(Weapons.FIRING[gun].get("fire", "")) == "hitscan"


# ------------------------------------------------------------------ shots


## A shot just went (before its pellets or round fly): the time to the next,
## the streak's bookkeeping, EXTRA BUCK's pellets, STEADY STOCK's climb.
static func fired(game, f, gun: int) -> void:
	var a: Weapons.Armory = game.armory
	a.cooldown *= CountyBuild.fire_scale(f, gun, game.clock < f.guard_until)
	if _streak_gun(gun):
		f.shot_gun = gun
		f.shot_hit = false
	if CountyBuild.rank(f, gun, "steady_stock") > 0:
		f.pitch_before = game.player.pitch
	var how: Dictionary = Weapons.FIRING[gun]
	var extra := CountyBuild.extra_pellets(f, gun) * maxi(1, a.last_spent)
	if extra > 0 and String(how.get("fire", "")) == "pellets":
		var p: Player = game.player
		var aim: float = p.view_angle()
		var slope: float = (p.pitch + p.sway) / Renderer.base_focal
		var tuned := Modes.shot_spread(game, p, gun, how, 0.0)
		var spread: Vector2 = tuned[0]
		for k in extra:
			var dx: float = game.rng.randf_range(-spread.x, spread.x)
			var dy: float = game.rng.randf_range(-spread.y, spread.y)
			game.hitscan(
				aim + dx,
				slope + dy,
				int(how.get("pellet_damage", Weapons.SHOTGUN_DAMAGE)),
				tuned[1],
				float(how["width"]),
				false
			)


## A player's hit about to land on `e`, `d` cells off: what it does now.
static func hit_amount(game, f, e: Enemy, amount: float, d: float) -> float:
	var gun: int = game.armory.active
	amount *= CountyBuild.damage_scale(f, gun)
	var choke := CountyBuild.rank(f, gun, "tight_choke")
	if choke > 0 and d >= 3.0 and d <= 9.0:
		amount *= 1.0 + float(CountyData.upgrade("tight_choke").get("bonus", .12)) * choke
	var eye := CountyBuild.rank(f, gun, "deadeye")
	if eye > 0:
		var spec := CountyData.upgrade("deadeye")
		amount *= 1.0 + float(spec.get("per", .06)) * eye * mini(f.streak, int(spec.get("most", 5)))
	var called := CountyBuild.rank(f, gun, "called_shot")
	if called > 0 and e.max_hp >= TOUGH and f.called_uid == e.get_instance_id():
		var spec := CountyData.upgrade("called_shot")
		amount *= (
			1.0
			+ float(spec.get("per", .05)) * called * mini(f.called_hits, int(spec.get("most", 8)))
		)
	if gun == Weapons.REVOLVER and f.six_ready and CountyBuild.has(f, "six_shooter"):
		amount *= float(CountyData.milestone("six_shooter").get("times", 2.0))
	return amount


## After a player's hit landed on `e` (d cells along ax, ay): the streaks
## count it, and it goes through, swings wide or shoves as the build says.
static func hit_after(
	game, f, e: Enemy, amount: float, d: float, ax: float, ay: float, slope: float
) -> void:
	var gun: int = game.armory.active
	var first: bool = f.shot_gun == gun and not f.shot_hit
	if first:
		f.shot_hit = true
		f.streak += 1
		if e.max_hp >= TOUGH:
			if f.called_uid == e.get_instance_id():
				f.called_hits += 1
			else:
				f.called_uid = e.get_instance_id()
				f.called_hits = 1
		if gun == Weapons.REVOLVER and CountyBuild.has(f, "six_shooter"):
			if f.six_ready:
				f.six_ready = false
				f.six_hits = 0
				_pierce(game, e, d, ax, ay, slope, amount, gun)
			else:
				f.six_hits += 1
				if f.six_hits >= int(CountyData.milestone("six_shooter").get("hits", 4)):
					f.six_ready = true
					game.sound.play("rev_lock", .9)
					Modes.say(game, "SHOWDOWN CHARGED.", 1.0)
	var heavy := CountyBuild.rank(f, gun, "heavy_hand")
	if heavy > 0 and e.alive and e.max_hp >= TOUGH:
		var spec := CountyData.upgrade("heavy_hand")
		if d <= float(spec.get("reach", 5.0)):
			e.stun = maxf(e.stun, float(spec.get("per", .2)) * heavy)
			e.windup = 0.0
			shove(game, e, .3)
	if CountyData.kind_of(gun) == CountyData.MELEE:
		var wide := CountyBuild.rank(f, gun, "wide_swing")
		if wide > 0:
			_swing_wide(game, f, e, amount, wide, gun)
		var push := CountyBuild.rank(f, gun, "crowd_control")
		if push > 0 and e.alive:
			e.stun = maxf(e.stun, .35)
			shove(game, e, float(CountyData.upgrade("crowd_control").get("per", .35)) * push)
	if (
		CountyBuild.has(f, "buckshot_breaker")
		and String(Weapons.FIRING[gun].get("fire", "")) == "pellets"
	):
		var share := float(CountyData.milestone("buckshot_breaker").get("share", .55))
		_pierce(game, e, d, ax, ay, slope, amount * share, gun)


## Pushes `e` `reach` cells straight away from the player (walls stop it).
static func shove(game, e: Enemy, reach: float) -> void:
	var p: Player = game.player
	var away := atan2(e.y - p.y, e.x - p.x)
	var steps := maxi(1, ceili(reach / .2))
	for k in steps:
		game.move_actor(e, cos(away) * reach / steps, sin(away) * reach / steps, e.radius)


## The next varmint along the shot past `first` (seen, within the gun's
## range) takes `amount`.
static func _pierce(
	game, first: Enemy, d: float, ax: float, ay: float, slope: float, amount: float, gun: int
) -> void:
	var p: Player = game.player
	var reach := float(Weapons.FIRING[gun].get("range", 20.0))
	var width := float(Weapons.FIRING[gun].get("width", .05))
	var best: Enemy = null
	var near := reach
	for e: Enemy in game.enemies:
		if e == first or not e.alive or not e.hostile:
			continue
		var dx := e.x - p.x
		var dy := e.y - p.y
		var along := dx * ax + dy * ay
		if along <= d or along >= near:
			continue
		var z: float = p.eye + along * slope
		var feet: float = e.z + game.world.stand(e)
		if (
			absf(dx * ay - dy * ax) < e.radius + width + .05
			and feet - .1 < z
			and z < feet + e.height + .1
			and game.world.visible(p.x, p.y, e.x, e.y, p.eye, z)
		):
			best = e
			near = along
	if best != null:
		best.hurt(amount, game, false, false, null, String(Weapons.NAMES[gun]))
		game.burst(best.x, best.y, p.eye + near * slope, "gore", 3, 1.0)


static func _swing_wide(game, f, struck: Enemy, amount: float, count: int, gun: int) -> void:
	var p: Player = game.player
	var share := float(CountyData.upgrade("wide_swing").get("share", .7))
	var reach := (
		float(Weapons.FIRING[gun].get("melee_range", 1.65)) * CountyBuild.reach_scale(f, gun) + .4
	)
	var fx := cos(p.view_angle())
	var fy := sin(p.view_angle())
	var near: Array = []
	for e: Enemy in game.enemies:
		if e == struck or not e.alive or not e.hostile:
			continue
		var dx := e.x - p.x
		var dy := e.y - p.y
		var d := sqrt(dx * dx + dy * dy)
		if d > reach or d < .01 or (dx * fx + dy * fy) / d < .25:
			continue
		if Vector2(e.x, e.y).distance_to(Vector2(struck.x, struck.y)) > 1.6:
			continue
		if game.world.visible(p.x, p.y, e.x, e.y):
			near.append([d, e])
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for k in mini(count, near.size()):
		var e: Enemy = near[k][1]
		e.hurt(amount * share, game, false, false, null, String(Weapons.NAMES[gun]))
		var push := CountyBuild.rank(f, gun, "crowd_control")
		if push > 0 and e.alive:
			shove(game, e, float(CountyData.upgrade("crowd_control").get("per", .35)) * push)


## One of the player's blasts going off: a fresh shot gets CHAIN REACTION's
## allowance, a follow-up blast spends its shot's.
static func blast_began(f, kind: String) -> void:
	if kind == CHAIN:
		f.blast_origin = f.chain_origin
		return
	f.chain_serial += 1
	f.blast_origin = f.chain_serial
	if f.chain_left.size() > 64:
		f.chain_left.clear()
	f.chain_left[f.blast_origin] = int(CountyData.milestone("chain_reaction").get("most", 3))


static func blast_tuning(_game, f, shot, radius: float, strength: float) -> Array:
	var gun := gun_of_shot(String(shot.kind))
	if gun < 0:
		return [radius, strength, 0.0, 0.0]
	radius *= 1.0 + CountyBuild.value(f, gun, "packed_charge")
	strength *= CountyBuild.damage_scale(f, gun)
	var shaped := CountyBuild.rank(f, gun, "shaped_charge")
	var spec := CountyData.upgrade("shaped_charge")
	return [
		radius,
		strength,
		float(spec.get("per", .25)) * shaped,
		float(spec.get("edge", .06)) * shaped
	]


# ------------------------------------------------------------------ kills


static func killed(game, f, e: Enemy) -> void:
	if not e.hostile:
		return
	CountyOrbs.drop(game, f, e)
	f.watch.erase(e.get_instance_id())
	if f.over:
		return
	if CountyBuild.has(f, "chain_reaction") and e.killed_by == "blast" and f.blast_mine:
		var origin: int = f.blast_origin
		if int(f.chain_left.get(origin, 0)) > 0:
			f.chain_left[origin] = int(f.chain_left[origin]) - 1
			f.chains.append([e.x, e.y, game.world.stand(e) + .3, f.run_time + .14, origin])
	var gun := Weapons.NAMES.find(String(e.killed_with))
	if (
		CountyBuild.has(f, "last_stand")
		and gun >= 0
		and CountyData.kind_of(gun) == CountyData.MELEE
	):
		var was: bool = game.clock < f.guard_until
		f.guard_until = game.clock + float(CountyData.milestone("last_stand").get("seconds", 3.5))
		if not was:
			Modes.say(game, "LAST STAND!", 1.0)


# ------------------------------------------------------------------ every tick


static func tick(game, f, dt: float) -> void:
	var a: Weapons.Armory = game.armory
	var p: Player = game.player
	if f.shot_gun >= 0:
		if not f.shot_hit:
			# A miss: the streaks start over.
			f.streak = 0
			f.called_hits = 0
			if f.shot_gun == Weapons.REVOLVER:
				f.six_hits = 0
				f.six_ready = false
		f.shot_gun = -1
	var steady := CountyBuild.value(f, a.active, "steady_stock")
	if f.pitch_before > -900.0:
		p.pitch -= (p.pitch - f.pitch_before) * minf(.9, steady)
		f.pitch_before = -999.0
	if steady > 0.0:
		a.rifle_heat = maxf(0.0, a.rifle_heat - dt * 1.8 * steady)
	if a.reload > 0.0:
		var share := CountyBuild.reload_scale(f, a.active, game.clock < f.burst_until)
		if share < 1.0:
			# Never to 0 here: the armory's own tick finishes the reload.
			a.reload = maxf(.0001, a.reload - dt * (1.0 / share - 1.0))
	for shot: GameState.Shot in game.shots:
		if shot.uid == 0 and not shot.enemy and shot.slot == p.slot and shot.damage > 0:
			var gun := gun_of_shot(String(shot.kind))
			if gun >= 0 and not f.scaled.has(shot.get_instance_id()):
				shot.damage = roundi(shot.damage * CountyBuild.damage_scale(f, gun))
				f.scaled[shot.get_instance_id()] = true
	if not f.scaled.is_empty() and int(f.run_time) != int(f.run_time - dt):
		f.scaled.clear()
	_slide(game, f, dt)
	_breakaway(game, f)
	if not f.chains.is_empty():
		var left: Array = []
		for c: Array in f.chains:
			if f.run_time < float(c[3]):
				left.append(c)
				continue
			f.chain_origin = int(c[4])
			game.explode(
				GameState.Shot.new(
					float(c[0]), float(c[1]), float(c[2]), 0.0, 0.0, 0.0, CHAIN, 0.0, false, 0
				)
			)
			f.chain_origin = 0
		f.chains = left


# ------------------------------------------------------------------ abilities


## SECOND WIND: the hit that would have killed `p` leaves them at its health,
## everything near is thrown back and a moment of grace follows.
static func second_wind(game, f, p: Player) -> void:
	var spec := CountyData.milestone("second_wind")
	f.second_wind_used = true
	p.health = maxi(p.health, int(spec.get("health", 50)))
	f.safe_until = game.clock + 1.0
	var reach := float(spec.get("reach", 3.5))
	for e: Enemy in game.enemies:
		if e.alive and e.hostile and Vector2(e.x - p.x, e.y - p.y).length() < reach:
			e.stun = maxf(e.stun, .8)
			e.windup = 0.0
			shove(game, e, 1.6)
	game.sound.play("yee_haw", 1.0)
	game.shake = 1.0
	Modes.say(game, "SECOND WIND!", 2.0)


## MUDSLIDE on USE: true when it went.
static func dash(game, f) -> bool:
	if not CountyBuild.has(f, "mudslide") or game.player.health <= 0:
		return false
	if game.clock < f.dash_ready:
		Modes.say(game, "MUDSLIDE IN %.1fS" % (f.dash_ready - game.clock), .8)
		return true
	var p: Player = game.player
	f.dash_left = SLIDE
	var moving := Vector2(p.vx, p.vy)
	f.dash_angle = moving.angle() if moving.length() > .4 else p.view_angle()
	f.dash_ready = game.clock + float(CountyData.milestone("mudslide").get("cooldown", 6.0))
	game.sound.play("step_mud_0", 1.0)
	return true


static func _slide(game, f, dt: float) -> void:
	if f.dash_left <= 0.0:
		return
	var p: Player = game.player
	var step := minf(f.dash_left, dt)
	f.dash_left -= step
	var dist := float(CountyData.milestone("mudslide").get("distance", 4.2)) * step / SLIDE
	var ux := cos(f.dash_angle)
	var uy := sin(f.dash_angle)
	for e: Enemy in game.enemies:
		if not e.alive or not e.hostile:
			continue
		var dx := e.x - p.x
		var dy := e.y - p.y
		var along := dx * ux + dy * uy
		var side := dx * uy - dy * ux
		if along > -.2 and along < 1.2 and absf(side) < e.radius + .45:
			# Knocked aside, off the line of the slide.
			var out := 1.0 if side >= 0.0 else -1.0
			e.stun = maxf(e.stun, .6)
			e.windup = 0.0
			for k in 4:
				game.move_actor(e, uy * out * .25, -ux * out * .25, e.radius)
	var steps := maxi(1, ceili(dist / .15))
	for k in steps:
		game.move_actor(p, ux * dist / steps, uy * dist / steps, GameState.PLAYER_RADIUS)


static func _breakaway(game, f) -> void:
	if not CountyBuild.has(f, "breakaway"):
		return
	var spec := CountyData.milestone("breakaway")
	var p: Player = game.player
	var close := 0
	var near := 0
	for e: Enemy in game.enemies:
		if not e.alive or not e.hostile:
			continue
		var d := Vector2(e.x - p.x, e.y - p.y).length()
		if d < 3.0:
			close += 1
		if d < 4.5:
			near += 1
	if close >= int(spec.get("crowd", 4)):
		f.crowd_at = game.clock
	elif near == 0 and game.clock - f.crowd_at < ESCAPE and game.clock >= f.burst_ready:
		f.burst_until = game.clock + float(spec.get("seconds", 3.0))
		f.burst_ready = game.clock + float(spec.get("cooldown", 15.0))
		f.crowd_at = -10.0
		game.sound.play("whistle", .9)
		Modes.say(game, "BREAKAWAY!", 1.2)
