## COUNTY RUN's XP and supplies lying about (CLAUDE.md "County Run"). A
## county hand drops XP where it falls, on the floor it stood on (a deck, a
## ramp, the ground; out of a wall if a knock put it in one), more the
## tougher it was (max health / per_hp; elites times elite_times). Walking
## near enough takes it: within `reach` (XP MAGNET adds), on the same floor
## (no more than a step and a half up or down), with nothing solid between
## the eyes and it. Within `pull` it floats to the player first. Taking XP
## chimes and pops a "+N"; past `merge_over` lying about, piles near each
## other merge (their XP adds up). Now and then a kill leaves ammo or food
## instead (supply_chance, food_chance), which lies a minute.
class_name CountyOrbs
extends RefCounted

const CountyRun := preload("res://src/features/county_run.gd")

## Value at or past which an XP cap is silver, then gold.
static var SILVER: int = ModeData.get_value("county_orbs", "silver")
static var GOLD: int = ModeData.get_value("county_orbs", "gold")
## How high above the player's feet (or below) a pile can be and still count
## as on their floor.
static var SAME_FLOOR: float = ModeData.get_value("county_orbs", "same_floor")
## Seconds a supply lies before it goes.
static var SUPPLY_LIFE: float = ModeData.get_value("county_orbs", "supply_life")
## Seconds a "+N" rises for.
static var POP: float = ModeData.get_value("county_orbs", "pop")


static func xp_for(_game: Game, _f: CountyRun, e: Enemy) -> int:
	var x := CountyData.section("xp")
	var per_hp: float = x.get("per_hp", 34)
	var v := maxi(1, roundi(e.max_hp / maxf(1.0, per_hp)))
	if e.county_elite:
		var elite_times: int = x.get("elite_times", 4)
		v *= elite_times
	return v


## What a kill leaves where `e` fell.
static func drop(game: Game, f: CountyRun, e: Enemy) -> void:
	var z: float = game.world.stand(e)
	var at := _clear_spot(game, e.x, e.y, z)
	if not _standable(game, e.x, e.y, z):
		z = game.world.floor_under(at.x, at.y, z + .3)
	var value := xp_for(game, f, e)
	if e.county_elite:
		f.elites_down += 1
		# An elite throws its XP about in a few piles.
		var piles := 4
		for k in piles:
			var a := k * TAU / piles + .3
			var spot := _clear_spot(game, at.x + cos(a) * .6, at.y + sin(a) * .6, z)
			_lay(f, spot.x, spot.y, z, maxi(1, value / piles), "xp")
		e.county_elite = false
	else:
		_lay(f, at.x, at.y, z, value, "xp")
	var s := CountyData.section("spawn")
	var roll: float = game.rng.random()
	var supply_chance: float = s.get("supply_chance", .075)
	var food_chance: float = s.get("food_chance", .05)
	if roll < supply_chance:
		var spot := _clear_spot(game, at.x + .35, at.y, z)
		_lay(f, spot.x, spot.y, z, 1, "ammo")
	elif roll < supply_chance + food_chance:
		var spot := _clear_spot(game, at.x - .35, at.y, z)
		_lay(f, spot.x, spot.y, z, 1, "food")


static func _lay(f: CountyRun, x: float, y: float, z: float, value: int, kind: String) -> void:
	f.orbs.append([x, y, z, value, kind, f.run_time, false])


## (x, y) or the nearest spot round it the player can walk to and stand on at
## height z: open, not deep water, on ground that walks to the start.
static func _clear_spot(game: Game, x: float, y: float, z: float) -> Vector2:
	if _standable(game, x, y, z):
		return Vector2(x, y)
	for reach: float in [.3, .55, .8, 1.1, 1.6, 2.2, 3.0, 4.0]:
		for k in 12:
			var a := k * TAU / 12.0
			var sx := x + cos(a) * reach
			var sy := y + sin(a) * reach
			if _standable(game, sx, sy, game.world.floor_under(sx, sy, z + .3)):
				return Vector2(sx, sy)
	return Vector2(x, y)


static func _standable(game: Game, x: float, y: float, z: float) -> bool:
	var w: LevelData = game.world
	if x < 1.0 or y < 1.0 or x >= w.width - 1 or y >= w.height - 1:
		return false
	if w.blocked(x, y, .12, z + .3) or w.deep_at(x, y):
		return false
	return CountySpawner.reached(game, x, y)


## Whether the player could take the pile at (x, y), lying at height z:
## near enough, on their floor and seen.
static func reachable(game: Game, x: float, y: float, z: float, reach: float) -> bool:
	var p: Player = game.player
	var dx := x - p.x
	var dy := y - p.y
	if dx * dx + dy * dy > reach * reach:
		return false
	var feet: float = game.world.stand(p)
	if absf(z - feet) > SAME_FLOOR:
		return false
	return game.world.visible(p.x, p.y, x, y, p.eye, z + .25)


static func magnet(f: CountyRun) -> float:
	return 1.0 + CountyBuild.perk_value(f, "xp_magnet")


static func tick(game: Game, f: CountyRun, dt: float) -> void:
	var p: Player = game.player
	if p.health <= 0:
		return
	var x := CountyData.section("xp")
	var base_reach: float = x.get("reach", .85)
	var reach := base_reach * magnet(f)
	var base_pull: float = x.get("pull", 2.2)
	var pull := base_pull * magnet(f)
	var kept: Array = []
	var took := 0
	for orb: Array in f.orbs:
		var kind := str(orb[4])
		var born: float = orb[5]
		if kind != "xp" and f.run_time - born > SUPPLY_LIFE:
			continue
		var ox: float = orb[0]
		var oy: float = orb[1]
		var oz: float = orb[2]
		if kind == "xp" and reachable(game, ox, oy, oz, pull):
			# Floats in toward the player, faster the nearer it gets.
			var dx := p.x - ox
			var dy := p.y - oy
			var d := sqrt(dx * dx + dy * dy)
			var step := minf(d, dt * (2.5 + 6.0 * (1.0 - d / pull)))
			if d > .001:
				orb[0] = ox + dx / d * step
				orb[1] = oy + dy / d * step
		var now_x: float = orb[0]
		var now_y: float = orb[1]
		if reachable(game, now_x, now_y, oz, reach if kind == "xp" else .7):
			if _take(game, f, orb):
				took += 1
				continue
		kept.append(orb)
	f.orbs = kept
	if took > 0:
		game.sound.play("county_xp", .55)
	var merge_over: int = x.get("merge_over", 70)
	if f.orbs.size() > merge_over and int(f.run_time * 2.0) != int((f.run_time - dt) * 2.0):
		var merge_reach: float = x.get("merge_reach", 1.6)
		merge(f, merge_reach)
	var live: Array = []
	for pop: Array in f.pops:
		var until: float = pop[3]
		if f.run_time < until:
			live.append(pop)
	f.pops = live


static func _take(game: Game, f: CountyRun, orb: Array) -> bool:
	var kind := str(orb[4])
	var value: int = orb[3]
	var ax: float = orb[0]
	var ay: float = orb[1]
	var az: float = orb[2]
	var at := [ax, ay, az]
	if kind == "food":
		if game.player.health >= 100:
			return false
		game.player.health = mini(100, game.player.health + 20)
		game.sound.play("crunch", .7)
		f.pops.append([at[0], at[1], at[2], f.run_time + POP, "+20 HP"])
		return true
	if kind == "ammo":
		var gun := CountyBuild.supply_target(game, f)
		if gun < 0:
			return false
		var bonus := 1.0 + CountyBuild.perk_value(f, "deep_pockets")
		var reserve: int = Weapons.PICKUP_RESERVE[gun]
		var amount := maxi(1, roundi(reserve * bonus))
		CountyBuild.give_ammo(game, f, gun, amount)
		game.sound.play("weapon_pickup", .6)
		f.pops.append(
			[at[0], at[1], at[2], f.run_time + POP, "+%d %s" % [amount, CountyData.short_name(gun)]]
		)
		return true
	if CountyBuild.has(f, "grit_armor"):
		var spec := CountyData.milestone("grit_armor")
		var most: float = spec.get("most", 40)
		var per: float = spec.get("per", 1)
		f.armor = minf(most, f.armor + per * value)
	f.pops.append([at[0], at[1], at[2], f.run_time + POP, "+%d" % value])
	game.burst(ax, ay, az + .2, "spark", 3, .8)
	CountyMode.gain(game, f, value)
	return true


## Piles of XP within `reach` of each other on one floor become one (the XP
## adds up, where they lay weighted by it); supplies never merge.
static func merge(f: CountyRun, reach: float) -> void:
	var out: Array = []
	var used := {}
	for i in f.orbs.size():
		if used.has(i):
			continue
		var first: Array = f.orbs[i]
		var a: Array = first.duplicate()
		if str(a[4]) == "xp":
			for j in range(i + 1, f.orbs.size()):
				var b: Array = f.orbs[j]
				if used.has(j) or str(b[4]) != "xp":
					continue
				var az: float = a[2]
				var bz: float = b[2]
				if absf(az - bz) > .3:
					continue
				var ax: float = a[0]
				var ay: float = a[1]
				var bx: float = b[0]
				var by: float = b[1]
				if Vector2(ax, ay).distance_to(Vector2(bx, by)) > reach:
					continue
				var va: float = a[3]
				var vb: float = b[3]
				a[0] = (ax * va + bx * vb) / (va + vb)
				a[1] = (ay * va + by * vb) / (va + vb)
				a[3] = int(va + vb)
				a[6] = true
				used[j] = true
		out.append(a)
	f.orbs = out


static func total_xp(f: CountyRun) -> int:
	var n := 0
	for orb: Array in f.orbs:
		if str(orb[4]) == "xp":
			var value: int = orb[3]
			n += value
	return n


static func sprites(game: Game, f: CountyRun) -> Array:
	var out: Array = []
	var t: float = game.clock
	for orb: Array in f.orbs:
		var x: float = orb[0]
		var y: float = orb[1]
		if not game.in_view(x, y, 1.0):
			continue
		var kind := str(orb[4])
		var bob := .14 + sin(t * 3.2 + x * 1.7) * .05
		var z: float = orb[2]
		if kind == "xp":
			var value: int = orb[3]
			var tier := 2 if value >= GOLD else 1 if value >= SILVER else 0
			var frame := int(t * 8.0 + x * 3.0) % 4
			var s: View.Sprite = game.pooled(
				x, y, "county_xp_%d_%d" % [tier, frame], .2 + tier * .05, z + bob
			)
			s.glow = true
			out.append(s)
		else:
			var s: View.Sprite = game.pooled(
				x, y, "item_bullets" if kind == "ammo" else "item_rinds", .33, z + bob
			)
			s.glow = true  # supplies stand out in the dark like the XP
			out.append(s)
	return out


## The "+N" over each pile just taken, rising and fading.
static func draw_pops(c: Canvas, game: Game, f: CountyRun) -> void:
	for pop: Array in f.pops:
		var until: float = pop[3]
		var left: float = until - f.run_time
		var age: float = POP - left
		var px: float = pop[0]
		var py: float = pop[1]
		var pz: float = pop[2]
		var at: Vector3 = game.to_canvas(px, py, pz + .45 + age * .6)
		if at.z <= 0.0 or at.x < 4 or at.x > 316 or at.y < 4 or at.y > View.VIEW - 8:
			continue
		var ink := HUD.AMBER if left > POP * .4 else HUD.DIM
		HUD.text(c, str(pop[4]), int(at.x), int(at.y), "mini", ink, true)
