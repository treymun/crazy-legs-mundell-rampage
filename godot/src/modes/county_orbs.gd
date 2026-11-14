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

## Value at or past which an XP cap is silver, then gold.
const SILVER := 4
const GOLD := 12
## How high above the player's feet (or below) a pile can be and still count
## as on their floor.
const SAME_FLOOR := .62
## Seconds a supply lies before it goes.
const SUPPLY_LIFE := 60.0
## Seconds a "+N" rises for.
const POP := .7


static func xp_for(_game, f, e: Enemy) -> int:
	var x := CountyData.section("xp")
	var v := maxi(1, roundi(e.max_hp / maxf(1.0, float(x.get("per_hp", 34)))))
	if f.elite_ids.has(e.get_instance_id()):
		v *= int(x.get("elite_times", 4))
	return v


## What a kill leaves where `e` fell.
static func drop(game, f, e: Enemy) -> void:
	var z: float = game.world.stand(e)
	var at := _clear_spot(game, e.x, e.y, z)
	if not _standable(game, e.x, e.y, z):
		z = game.world.floor_under(at.x, at.y, z + .3)
	var value := xp_for(game, f, e)
	if f.elite_ids.has(e.get_instance_id()):
		f.elites_down += 1
		# An elite throws its XP about in a few piles.
		var piles := 4
		for k in piles:
			var a := k * TAU / piles + .3
			var spot := _clear_spot(game, at.x + cos(a) * .6, at.y + sin(a) * .6, z)
			_lay(f, spot.x, spot.y, z, maxi(1, value / piles), "xp")
		f.elite_ids.erase(e.get_instance_id())
	else:
		_lay(f, at.x, at.y, z, value, "xp")
	var s := CountyData.section("spawn")
	var roll: float = game.rng.random()
	if roll < float(s.get("supply_chance", .075)):
		var spot := _clear_spot(game, at.x + .35, at.y, z)
		_lay(f, spot.x, spot.y, z, 1, "ammo")
	elif roll < float(s.get("supply_chance", .075)) + float(s.get("food_chance", .05)):
		var spot := _clear_spot(game, at.x - .35, at.y, z)
		_lay(f, spot.x, spot.y, z, 1, "food")


static func _lay(f, x: float, y: float, z: float, value: int, kind: String) -> void:
	f.orbs.append([x, y, z, value, kind, f.run_time, false])


## (x, y) or the nearest spot round it the player can walk to and stand on at
## height z: open, not deep water, on ground that walks to the start.
static func _clear_spot(game, x: float, y: float, z: float) -> Vector2:
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


static func _standable(game, x: float, y: float, z: float) -> bool:
	var w: LevelData = game.world
	if x < 1.0 or y < 1.0 or x >= w.width - 1 or y >= w.height - 1:
		return false
	if w.blocked(x, y, .12, z + .3) or w.deep_at(x, y):
		return false
	return CountySpawner.reached(game, x, y)


## Whether the player could take the pile at (x, y), lying at height z:
## near enough, on their floor and seen.
static func reachable(game, x: float, y: float, z: float, reach: float) -> bool:
	var p: Player = game.player
	var dx := x - p.x
	var dy := y - p.y
	if dx * dx + dy * dy > reach * reach:
		return false
	var feet: float = game.world.stand(p)
	if absf(z - feet) > SAME_FLOOR:
		return false
	return game.world.visible(p.x, p.y, x, y, p.eye, z + .25)


static func magnet(f) -> float:
	return 1.0 + CountyBuild.perk_value(f, "xp_magnet")


static func tick(game, f, dt: float) -> void:
	var p: Player = game.player
	if p.health <= 0:
		return
	var x := CountyData.section("xp")
	var reach := float(x.get("reach", .85)) * magnet(f)
	var pull := float(x.get("pull", 2.2)) * magnet(f)
	var kept: Array = []
	var took := 0
	for orb: Array in f.orbs:
		var kind := String(orb[4])
		if kind != "xp" and f.run_time - float(orb[5]) > SUPPLY_LIFE:
			continue
		var ox := float(orb[0])
		var oy := float(orb[1])
		var oz := float(orb[2])
		if kind == "xp" and reachable(game, ox, oy, oz, pull):
			# Floats in toward the player, faster the nearer it gets.
			var dx := p.x - ox
			var dy := p.y - oy
			var d := sqrt(dx * dx + dy * dy)
			var step := minf(d, dt * (2.5 + 6.0 * (1.0 - d / pull)))
			if d > .001:
				orb[0] = ox + dx / d * step
				orb[1] = oy + dy / d * step
		if reachable(game, float(orb[0]), float(orb[1]), oz, reach if kind == "xp" else .7):
			if _take(game, f, orb):
				took += 1
				continue
		kept.append(orb)
	f.orbs = kept
	if took > 0:
		game.sound.play("county_xp", .55)
	if (
		f.orbs.size() > int(x.get("merge_over", 70))
		and int(f.run_time * 2.0) != int((f.run_time - dt) * 2.0)
	):
		merge(f, float(x.get("merge_reach", 1.6)))
	var live: Array = []
	for pop: Array in f.pops:
		if f.run_time < float(pop[3]):
			live.append(pop)
	f.pops = live


static func _take(game, f, orb: Array) -> bool:
	var kind := String(orb[4])
	var value := int(orb[3])
	var at := [float(orb[0]), float(orb[1]), float(orb[2])]
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
		var amount := maxi(1, roundi(int(Weapons.PICKUP_RESERVE[gun]) * bonus))
		CountyBuild.give_ammo(game, f, gun, amount)
		game.sound.play("weapon_pickup", .6)
		f.pops.append(
			[at[0], at[1], at[2], f.run_time + POP, "+%d %s" % [amount, CountyData.short_name(gun)]]
		)
		return true
	if CountyBuild.has(f, "grit_armor"):
		var spec := CountyData.milestone("grit_armor")
		f.armor = minf(float(spec.get("most", 40)), f.armor + float(spec.get("per", 1)) * value)
	f.pops.append([at[0], at[1], at[2], f.run_time + POP, "+%d" % value])
	game.burst(at[0], at[1], at[2] + .2, "spark", 3, .8)
	CountyMode.gain(game, f, value)
	return true


## Piles of XP within `reach` of each other on one floor become one (the XP
## adds up, where they lay weighted by it); supplies never merge.
static func merge(f, reach: float) -> void:
	var out: Array = []
	var used := {}
	for i in f.orbs.size():
		if used.has(i):
			continue
		var a: Array = f.orbs[i].duplicate()
		if String(a[4]) == "xp":
			for j in range(i + 1, f.orbs.size()):
				var b: Array = f.orbs[j]
				if used.has(j) or String(b[4]) != "xp" or absf(float(a[2]) - float(b[2])) > .3:
					continue
				if (
					Vector2(float(a[0]), float(a[1])).distance_to(Vector2(float(b[0]), float(b[1])))
					> reach
				):
					continue
				var va := float(a[3])
				var vb := float(b[3])
				a[0] = (float(a[0]) * va + float(b[0]) * vb) / (va + vb)
				a[1] = (float(a[1]) * va + float(b[1]) * vb) / (va + vb)
				a[3] = int(va + vb)
				a[6] = true
				used[j] = true
		out.append(a)
	f.orbs = out


static func total_xp(f) -> int:
	var n := 0
	for orb: Array in f.orbs:
		if String(orb[4]) == "xp":
			n += int(orb[3])
	return n


static func sprites(game, f) -> Array:
	var out: Array = []
	var t: float = game.clock
	for orb: Array in f.orbs:
		var x := float(orb[0])
		var y := float(orb[1])
		if not game.in_view(x, y, 1.0):
			continue
		var kind := String(orb[4])
		var bob := .14 + sin(t * 3.2 + x * 1.7) * .05
		if kind == "xp":
			var value := int(orb[3])
			var tier := 2 if value >= GOLD else 1 if value >= SILVER else 0
			var frame := int(t * 8.0 + x * 3.0) % 4
			var s: Renderer.Sprite = game.pooled(
				x, y, "county_xp_%d_%d" % [tier, frame], .2 + tier * .05, float(orb[2]) + bob
			)
			s.glow = true
			out.append(s)
		else:
			var s: Renderer.Sprite = game.pooled(
				x, y, "item_bullets" if kind == "ammo" else "item_rinds", .33, float(orb[2]) + bob
			)
			s.glow = true  # supplies stand out in the dark like the XP
			out.append(s)
	return out


## The "+N" over each pile just taken, rising and fading.
static func draw_pops(c: Canvas, game, f) -> void:
	for pop: Array in f.pops:
		var left: float = float(pop[3]) - f.run_time
		var age: float = POP - left
		var at: Vector3 = game.to_canvas(
			float(pop[0]), float(pop[1]), float(pop[2]) + .45 + age * .6
		)
		if at.z <= 0.0 or at.x < 4 or at.x > 316 or at.y < 4 or at.y > Renderer.VIEW - 8:
			continue
		var ink := HUD.AMBER if left > POP * .4 else HUD.DIM
		HUD.text(c, String(pop[4]), int(at.x), int(at.y), "mini", ink, true)
