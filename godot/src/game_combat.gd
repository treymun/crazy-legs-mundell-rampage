## Shots, hitscan, explosions, broken glass and scenery, hazards, ground marks
## and the exchanges of fire between enemies (the game layers are listed in
## game_state.gd).
class_name GameCombat
extends GameWorld


func launch(
	x: float,
	y: float,
	z: float,
	angle: float,
	speed: float,
	kind: String,
	vz := 0.0,
	enemy := false,
	damage := 0,
	life := -1.0,
	owner := 0
) -> void:
	if life <= 0.0:
		life = 2.6 if kind == "blade" else 3.8 if enemy else 1.55
	var shot := Shot.new(
		x,
		y,
		z,
		cos(angle) * speed,
		sin(angle) * speed,
		vz,
		kind,
		life,
		enemy,
		damage,
		3 if kind == "blade" else 2 if kind == "bowling" else 0
	)
	shot.owner = owner
	shots.append(shot)


func throw_dynamite(remaining: float) -> void:
	var p := player
	var aim := p.view_angle()
	var dx := cos(aim)
	var dy := sin(aim)
	var x := p.x + dx * .21
	var y := p.y + dy * .21
	if world.blocked(x, y, .05):
		x = p.x
		y = p.y
	if remaining <= 0.0:
		explode(Shot.new(p.x, p.y, p.eye - .30, 0.0, 0.0, 0.0, "tnt", 0.0, false, 0))
		damage(21, [p.x, p.y], "LIT DYNAMITE")
		return
	shots.append(
		Shot.new(
			x,
			y,
			p.eye - .17,
			dx * 6.1,
			dy * 6.1,
			1.55 + p.pitch * .037,
			"tnt",
			remaining,
			false,
			0,
			5
		)
	)


## Mirrors Game.hitscan: hits actors, drums and breakable scenery, or chips the
## wall behind them. Returns true when anything was hit.
func hitscan(
	angle: float,
	slope: float,
	amount: float,
	max_range: float,
	spread: float,
	spark := true,
	pressure := false
) -> bool:
	var p := player
	var ax := cos(angle)
	var ay := sin(angle)
	var best: Enemy = null
	var near := max_range
	for enemy: Enemy in enemies:
		if not enemy.alive or enemy.brain == "bessie":
			continue
		var dx := enemy.x - p.x
		var dy := enemy.y - p.y
		var d := dx * ax + dy * ay
		var z := p.eye + d * slope
		var feet: float = enemy.z + world.elevation(enemy.x, enemy.y)
		if (
			0.0 < d
			and d < near
			and absf(dx * ay - dy * ax) < enemy.radius + spread
			and feet - .10 < z
			and z < feet + enemy.height + .10
			and world.visible(p.x, p.y, enemy.x, enemy.y, p.eye, z)
		):
			best = enemy
			near = d
	var drum = null
	for point in drums.keys():
		var vec: Vector2 = point
		var dx := vec.x - p.x
		var dy := vec.y - p.y
		var d := dx * ax + dy * ay
		var base: float = world.elevation(vec.x, vec.y)
		var z := p.eye + d * slope
		if (
			0.0 < d
			and d < near
			and absf(dx * ay - dy * ax) < .24 + spread
			and base <= z
			and z <= base + 1.10
			and world.visible(p.x, p.y, vec.x, vec.y, p.eye, z)
		):
			drum = vec
			near = d
	var scenery = null
	for prop: LevelData.Scenery in world.scenery:
		if scenery_used(prop):
			continue
		var dx := prop.x - p.x
		var dy := prop.y - p.y
		var d := dx * ax + dy * ay
		var height := p.eye + d * slope
		var base: float = world.elevation(prop.x, prop.y) + prop.z
		if (
			0.0 < d
			and d < near
			and absf(dx * ay - dy * ax) < prop.radius + spread
			and base - .08 < height
			and height < base + prop.height + .08
			and world.visible(p.x, p.y, prop.x, prop.y, p.eye, height)
		):
			scenery = prop
			near = d
	var pieces = features.get("breakables")
	if pieces != null and pieces.ray(p.x, p.y, p.eye, ax, ay, slope, near, spread) >= 0:
		near = pieces.ray_d
		_traced(ax, ay, slope, near, "thing")
		pieces.strike(pieces.ray_piece, amount, ax, ay)
		return true
	if scenery != null:
		_traced(ax, ay, slope, near, "thing")
		hit_scenery(scenery)
		return true
	if drum != null:
		_traced(ax, ay, slope, near, "thing")
		drum_hit(drum, amount)
		return true
	if best != null:
		_traced(ax, ay, slope, near, "enemy")
		# Where it struck, for a boss's weak spot (BossKit.weak).
		hit_point = Vector3(p.x + ax * near, p.y + ay * near, p.eye + near * slope)
		hit_from = Vector2(p.x, p.y)
		best.hurt(amount, self, false, pressure, null, String(Weapons.NAMES[armory.active]))
		return true
	if not spark:
		var reach := _wall_distance(ax, ay, slope, max_range)
		_traced(ax, ay, slope, reach, "air" if reach >= max_range else "wall:")
		if reach < max_range:
			_strike_wall(ax, ay, slope, reach + .7 * max_range / ceilf(max_range / .21), amount)
	if spark:
		var ended := false
		var steps := int(ceil(max_range / .105))
		for i in range(1, steps + 1):
			var d: float = i * max_range / steps
			var x := p.x + ax * d
			var y := p.y + ay * d
			var z := p.eye + d * slope
			var ix := clampi(int(x), 0, world.width - 1)
			var iy := clampi(int(y), 0, world.height - 1)
			var cell := iy * world.width + ix
			var floor_z: float = world.ground[cell]
			var roof_z: float = world.roof[cell]
			var surface_tile = null
			if z < floor_z:
				surface_tile = int(world.floor_tile[cell])
			elif 0.0 < roof_z and roof_z < z:
				surface_tile = int(world.ceiling_tile[cell])
			if surface_tile != null or world.blocked(x, y, .024, z):
				var pane = world.pane_at(x, y, z, .025)
				if pane != null:
					_traced(ax, ay, slope, d, "glass")
					shatter(pane, z)
					return true
				var mark = (
					null
					if surface_tile != null
					else renderer.wall_mark(p.x, p.y, p.eye, ax, ay, slope, d)
				)
				# A window shot out or a fence knocked about (features/wall_breaks.gd);
				# a shot in through a window's glass leaves no hole on it.
				var breaks = features.get("wall_breaks")
				if (
					surface_tile == null
					and breaks != null
					and breaks.strike(x, y, z, ax, ay, amount) == breaks.HOLE
				):
					mark = null
				# What it met (materials.gd): its chips, its sound, its hole. The
				# face as drawn when there is one (a front's bands are not its cell's).
				var kind := (
					Materials.of_tile(world, mark.tile)
					if mark != null and mark.tile >= 0
					else Materials.struck(world, x, y, z, surface_tile)
				)
				var surface := Materials.coarse(kind)
				impact_kind = kind
				if (
					mark != null
					and Materials.hole(kind) != ""
					and (
						armory.active == Weapons.REVOLVER
						or armory.active == Weapons.RIFLE
						or armory.active == Weapons.SHOTGUN
					)
				):
					mark.image = Materials.hole(kind)
					mark.radius = .09 if kind == "glass" else .051 if kind == "steel" else .060
					mark.material = surface
					# features/impacts.gd keeps them to a cap, fading the oldest first.
					wall_marks.append(mark)
					if wall_marks.size() > 160:
						wall_marks.pop_front()
				var hit_d: float = (i - .70) * max_range / steps
				x = p.x + ax * hit_d
				y = p.y + ay * hit_d
				_traced(ax, ay, slope, hit_d, "wall:" + surface)
				ended = true
				if specks.size() < 144:
					var particle := String(Materials.SPECKS.get(kind, "chips"))
					var pspeed := float(
						{"wood": .64, "metal": 1.21, "plaster": .53, "dirt": .48}.get(surface, .64)
					)
					burst(
						x,
						y,
						maxf(.04, minf(1.8, p.eye + hit_d * slope)),
						String(particle),
						3,
						float(pspeed)
					)
					gore_fx.impact(x, y, maxf(.04, minf(1.8, p.eye + hit_d * slope)), surface)
				if (
					(
						armory.active == Weapons.REVOLVER
						or armory.active == Weapons.RIFLE
						or armory.active == Weapons.SHOTGUN
						or armory.active == Weapons.RIVETER
						or armory.active == Weapons.PRESSURE
					)
					and clock >= wall_sound
				):
					wall_sound = clock + .08
					var cue := String(Materials.CUES.get(kind, "impact_wood"))
					if armory.active == Weapons.RIVETER:
						cue = "impact_rivet"
					elif armory.active == Weapons.PRESSURE:
						cue = "impact_pressure"
					sound_at(cue, x, y, .64)
				# A strong enough round goes on through a thin wall (penetration.gd).
				if (
					surface_tile == null
					and Penetration.pierce(
						self, ax, ay, slope, d, amount, max_range, spread, pressure
					)
				):
					return true
				break
		if not ended:
			_traced(ax, ay, slope, max_range, "air")
	return false


func _traced(ax: float, ay: float, slope: float, d: float, struck: String) -> void:
	var p := player
	traced.emit(Vector3(p.x + ax * d, p.y + ay * d, p.eye + d * slope), struck)


## A shot that chips nothing (the pellets past a load's first few) still
## breaks what it met at `d` along it, if that was a wall (wall_breaks.gd).
func _strike_wall(ax: float, ay: float, slope: float, d: float, amount: float) -> void:
	var breaks = features.get("wall_breaks")
	if breaks == null:
		return
	var p := player
	var x := p.x + ax * d
	var y := p.y + ay * d
	var z := p.eye + d * slope
	if x < 0.0 or y < 0.0 or x >= world.width or y >= world.height:
		return
	var cell := int(y) * world.width + int(x)
	if z < world.ground[cell] or (0.0 < world.roof[cell] and world.roof[cell] < z):
		return
	if world.blocked(x, y, .024, z):
		breaks.strike(x, y, z, ax, ay, amount)


## How far a shot along (ax, ay, slope) goes before a wall, floor or roof stops
## it (max_range when nothing does), for the look of a shot that chips nothing.
func _wall_distance(ax: float, ay: float, slope: float, max_range: float) -> float:
	var p := player
	var steps := int(ceil(max_range / .21))
	for i in range(1, steps + 1):
		var d: float = i * max_range / steps
		var x := p.x + ax * d
		var y := p.y + ay * d
		var z := p.eye + d * slope
		var cell := (
			clampi(int(y), 0, world.height - 1) * world.width + clampi(int(x), 0, world.width - 1)
		)
		var roof_z: float = world.roof[cell]
		if z < world.ground[cell] or (0.0 < roof_z and roof_z < z) or world.blocked(x, y, .024, z):
			return (i - .7) * max_range / steps
	return max_range


func assisted_aim(angle: float, slope: float) -> Array:
	# A thumb aims less finely than a mouse: on touch the help turns too, wider.
	var mode := maxi(aim_assist, 2) if touch_aim else aim_assist
	if mode == 0:
		return [angle, slope]
	var p := player
	var threshold := .075 if touch_aim else .047 if mode == 2 else .025
	var best := INF
	var correction = null
	for e: Enemy in enemies:
		if not e.hostile or not e.alive:
			continue
		var dx := e.x - p.x
		var dy := e.y - p.y
		var distance := sqrt(dx * dx + dy * dy)
		if not (.46 < distance and distance < 18.0):
			continue
		var yaw := atan2(dy, dx)
		var error := absf(fposmod(yaw - angle + PI, TAU) - PI)
		if error > threshold:
			continue
		var target: float = world.elevation(e.x, e.y) + e.z + e.height * .58
		var vertical := (target - p.eye) / distance
		if absf(vertical - slope) > .19:
			continue
		var score := error * 12.0 + absf(vertical - slope) * .4 + distance * .009
		if score < best and world.visible(p.x, p.y, e.x, e.y, p.eye, target):
			correction = [yaw if mode == 2 else angle, vertical]
			best = score
	return correction if correction != null else [angle, slope]


## TOUCH AUTO FIRE: a hostile is in the sights of a gun that fires straight,
## close enough to the crosshair that the touch aim help would take it.
## Checked at most ten times a second.
func sights_on_enemy() -> bool:
	if clock < sights_next:
		return sights_last
	sights_next = clock + .1
	sights_last = false
	var gun := armory.active
	if armory.holstered or not bool(Weapons.FIRING[gun].get("auto_fire", false)):
		return false
	var p := player
	var angle := p.view_angle()
	var slope := (p.pitch + p.sway) / Renderer.base_focal
	for e: Enemy in enemies:
		if not e.hostile or not e.alive:
			continue
		var dx := e.x - p.x
		var dy := e.y - p.y
		var distance := sqrt(dx * dx + dy * dy)
		if distance < .3 or distance > (1.7 if gun == Weapons.CROWBAR else 16.0):
			continue
		var error := absf(fposmod(atan2(dy, dx) - angle + PI, TAU) - PI)
		if error > maxf(.06, (e.radius + .05) / distance):
			continue
		var target: float = world.elevation(e.x, e.y) + e.z + e.height * .58
		if absf((target - p.eye) / distance - slope) > .2:
			continue
		if world.visible(p.x, p.y, e.x, e.y, p.eye, target):
			sights_last = true
			return true
	return false


func shatter(pane: Vector2i, z := .99) -> void:
	if world.broken_panes.has(pane):
		return
	world.broken_panes[pane] = true
	var x := float(pane.x) + .5
	var y := float(pane.y) + .5
	sound_at("glass_break", x, y, .96)
	sound_at("glass_settle", x, y, .5)
	burst(x, y, minf(1.6, maxf(.38, z)), "glass", 17, 1.95)
	disturb(x, y, 6.8, minf(1.6, maxf(.38, z)))


func drum_hit(point: Vector2, amount: float) -> void:
	if not drums.has(point):
		return
	drums[point] = int(drums[point]) - int(amount)
	var x := point.x
	var y := point.y
	var z: float = world.elevation(x, y) + .57
	if int(drums[point]) <= 0:
		drums.erase(point)
		var pieces = features.get("breakables")
		if pieces != null:
			pieces.wreck(x, y, "town_fuel_drum_burst")
		explode(Shot.new(x, y, z, 0.0, 0.0, 0.0, "fuel", 0.0, false, 0))
	else:
		sound_at("ricochet", x, y, .6)
		burst(x, y, z, "spark", 4, .8)


func explode(shot: Shot) -> void:
	var x := shot.x
	var y := shot.y
	var z := maxf(.07, shot.z)
	# Every number of the blast is its kind's (shots.cfg).
	var spec := Shots.blast(shot.kind)
	var energy := bool(spec["energy"])
	var radius := float(spec["radius"])
	var strength := float(spec["strength"])
	if strength <= 0.0:
		strength = float(shot.damage)
	if spec.has("also_sound"):
		sound_at(String(spec["also_sound"]), x, y, .9)
	blast_flash = maxf(blast_flash, float(spec["flash"]))
	var near := sqrt((player.x - x) * (player.x - x) + (player.y - y) * (player.y - y))
	shake = minf(1.0, shake + maxf(0.0, 1.0 - near / 9.0) * (.45 if energy else .9))
	duck = maxf(duck, float(spec["duck"]))
	blasts.append(Blast.new(x, y, z, "energy" if energy else "fire"))
	exploded.emit(x, y, z, energy)
	sound_at(String(spec["cue"]), x, y)
	burst(x, y, z, "plasma" if energy else "spark", 12 if energy else 23, 2.2 if energy else 3.3)
	burst(x, y, z, "dust", 6 if energy else 16, 2.3)
	wake_nearby(float(spec["wake"]), x, y)
	if not energy:
		disturb(x, y, 3.5, z)
	blast_kind = shot.kind
	for enemy: Enemy in enemies:
		var distance := sqrt((enemy.x - x) * (enemy.x - x) + (enemy.y - y) * (enemy.y - y))
		if enemy.alive and distance < radius and world.visible(x, y, enemy.x, enemy.y):
			hit_point = Vector3(x, y, z)
			hit_from = Vector2(player.x, player.y)
			enemy.hurt(
				maxi(1, int(strength * (1.0 - distance / (radius + .3)))),
				self,
				not energy,
				false,
				null,
				"energy" if energy else "blast"
			)
	blast_kind = ""
	for prop: LevelData.Scenery in world.scenery:
		if (
			sqrt((prop.x - x) * (prop.x - x) + (prop.y - y) * (prop.y - y)) < radius
			and world.visible(x, y, prop.x, prop.y)
		):
			hit_scenery(prop)
	_blast_shoves(shot, x, y, z, radius, strength, energy)
	var p := player
	var distance := sqrt((p.x - x) * (p.x - x) + (p.y - y) * (p.y - y))
	if distance < radius * .75 and world.visible(x, y, p.x, p.y):
		damage(
			maxi(2, int(float(spec["player_damage"]) * (1.0 - distance / (radius * .75)))),
			[x, y],
			"BLAST" if shot.enemy or shot.kind == "fuel" or shot.owner == -1 else "BACKBLAST"
		)
	if not energy:
		for pane in world.pane_tiles:
			if sqrt(pow(float(pane.x) + .5 - x, 2) + pow(float(pane.y) + .5 - y, 2)) < 2.0:
				shatter(pane)
		for point in drums.keys():
			var vec: Vector2 = point
			if (
				sqrt(pow(vec.x - x, 2) + pow(vec.y - y, 2)) < 2.2
				and world.visible(x, y, vec.x, vec.y)
			):
				drum_hit(vec, 20)
		for door: LevelData.Door in world.doors:
			var centre := door.center()
			if (
				(level.rescue or door.blast_only)
				and bool(spec["opens_secrets"])
				and door.secret
				and not door.opened
				and sqrt(pow(centre.x - x, 2) + pow(centre.y - y, 2)) < 1.27
			):
				toggle_door(door, true)


## What a blast does to loose things: breaks the breakables near it (an
## explosive one goes up after, the chain reaction), throws gibs, bodies, bits
## and the barrels it did not break outward, and knocks lit dynamite and
## bowling balls rolling. Its damage to enemies and the player is explode()'s.
func _blast_shoves(
	shot: Shot, x: float, y: float, z: float, radius: float, strength: float, energy: bool
) -> void:
	var power := 2.5 if energy else 4.5
	var pieces = features.get("breakables")
	if pieces != null:
		pieces.blast(x, y, z, radius, strength, energy)
	var breaks = features.get("wall_breaks")
	if breaks != null:
		breaks.blast(x, y, z, radius, strength, energy)
	gore_fx.shove(x, y, radius * 1.4, power)
	var bodies = features.get("corpses")
	if bodies != null:
		bodies.shove(x, y, radius * 1.3, power * .75)
	for other: Shot in shots:
		if other == shot or other.enemy or (other.kind != "tnt" and other.kind != "bowling"):
			continue
		var push := Tumble.shove(x, y, radius, power, other.x, other.y)
		if push != Vector3.ZERO and world.visible(x, y, other.x, other.y):
			other.vx += push.x
			other.vy += push.y
			if other.kind == "tnt":
				other.vz = maxf(other.vz, push.z * .6)
			other.resting = false


func hit_scenery(prop: LevelData.Scenery) -> void:
	if scenery_used(prop):
		return
	scenery_spent[prop.id] = true
	var reaction: Array = REACTIONS.get(prop.kind, ["scenery_scrap", "dust", 6])
	var cue: String = reaction[0]
	var particle: String = reaction[1]
	var count: int = reaction[2]
	var height: float = world.elevation(prop.x, prop.y) + prop.z + prop.height * .51
	sound_at(cue, prop.x, prop.y, .72)
	if prop.kind in ["pipe", "belt", "cans", "bottles"]:
		disturb(prop.x, prop.y, 5.2, height)
	if world.ruptures.has(prop.id):
		var rupture: Array = world.ruptures[prop.id]
		add_hazard("steam", float(rupture[0]), float(rupture[1]), .48, .66, 2.20, 8)
		sound_at("pressure_vent", float(rupture[0]), float(rupture[1]), .52)
		message(String(rupture[2]), 2.2)
	burst(prop.x, prop.y, height, particle, count, 1.1)
	if not prop.opens.is_empty():
		for door: LevelData.Door in world.doors:
			if prop.opens.has(Vector2i(door.x, door.y)):
				toggle_door(door, true)
		message("THE SERVICE CUT IS OPEN.", 2.8)
	if prop.station != "":
		for station: LevelData.Station in world.stations:
			if station.id == prop.station:
				activate_station(station)
				break


func finish_shot(shot: Shot) -> void:
	if Shots.explodes(shot.kind):
		explode(shot)
	elif shot.kind == "football":
		burst(shot.x, shot.y, shot.z, "dust", 8, 1.3)
		sound_at("football_bounce", shot.x, shot.y)
	elif shot.kind == "chalk_lob":
		add_hazard("chalk", shot.x, shot.y, .89, .08, 2.75, 6)
		sound_at("chalk_pop", shot.x, shot.y, .67)
	elif shot.kind == "fair_bottle":
		burst(shot.x, shot.y, shot.z, "glass", 13, 1.7)
		sound_at("tosser_glass", shot.x, shot.y, .8)
		var p := player
		if (
			p.air < .27
			and sqrt(pow(p.x - shot.x, 2) + pow(p.y - shot.y, 2)) < .77
			and world.visible(shot.x, shot.y, p.x, p.y, shot.z, p.eye)
		):
			damage(10, [shot.x, shot.y], "GLASS")
	elif shot.kind in ["deputy_slug", "chain_hook", "valve_slug", "wrench", "tire", "flare"]:
		burst(shot.x, shot.y, shot.z, "spark" if shot.kind == "chain_hook" else "dust", 3, .75)


func move_shot(shot: Shot, dt: float) -> bool:
	# Small swept steps catch narrow doors, shallow floors and fast enemies.
	var distance: float = sqrt(shot.vx * shot.vx + shot.vy * shot.vy + shot.vz * shot.vz) * dt
	var steps := maxi(1, int(ceil(distance / .09)))
	dt /= steps
	var gravity := Shots.gravity(shot.kind)
	var tnt := shot.kind == "tnt"
	var rolls := (tnt or shot.kind == "bowling") and not shot.enemy
	for _step in steps:
		shot.life -= dt
		if shot.life <= 0.0:
			finish_shot(shot)
			return false
		if shot.resting:
			continue
		if rolls:
			if not _roll(shot, dt, tnt):
				return false
			if not tnt and not _hits(shot, shot.x, shot.y, shot.z):
				return false
			continue
		var x := shot.x + shot.vx * dt
		var y := shot.y + shot.vy * dt
		var z := shot.z + shot.vz * dt
		shot.vz -= dt * gravity
		var wall := world.blocked(x, y, .045, z)
		if wall and not shot.enemy and not tnt:
			var pane = world.pane_at(x, y, z, .045)
			if pane != null:
				shatter(pane, z)
				wall = world.blocked(x, y, .045, z)
		var roof: float = world.roof[int(y) * world.width + int(x)] if not wall else 0.0
		var plane: bool = (
			not wall and (z < world.elevation(x, y) + .045 or (0.0 < roof and roof <= z + .045))
		)
		if wall or plane:
			if tnt and (shot.bounces <= 0 or (plane and absf(shot.vz) < .77 and not wall)):
				shot.vx = 0.0
				shot.vy = 0.0
				shot.vz = 0.0
				shot.resting = true
				continue
			if shot.bounces <= 0:
				finish_shot(shot)
				return false
			if wall:
				var across_x := world.blocked(x, shot.y, .045, z)
				var across_y := world.blocked(shot.x, y, .045, z)
				if across_x or not across_y:
					shot.vx *= -.57 if tnt else -.86
				if across_y or not across_x:
					shot.vy *= -.57 if tnt else -.86
			else:
				shot.vz *= -.46 if tnt else -.88
				if tnt:
					shot.vx *= .64
					shot.vy *= .64
			shot.bounces -= 1
			sound_at("tnt_bounce" if tnt else "saw_bounce", shot.x, shot.y)
			if not tnt:
				burst(shot.x, shot.y, shot.z, "spark", 6, 1.4)
			continue
		var travel: float = sqrt(pow(x - shot.x, 2) + pow(y - shot.y, 2))
		if shot.kind == "bottle_rocket" and shot.travelled < .78 and shot.travelled + travel >= .78:
			sound_at("rocket_whistle", x, y, .68)
		shot.travelled += travel
		shot.x = x
		shot.y = y
		shot.z = z
		var p := player
		var ricochet: bool = shot.kind == "blade" and shot.bounces < 3 and shot.travelled > .72
		if (
			((shot.enemy and shot.kind != "chalk_lob" and shot.kind != "fair_bottle") or ricochet)
			and sqrt(pow(p.x - x, 2) + pow(p.y - y, 2)) < .28
			and p.eye - (.80 if not p.crouched else .55) < z
			and z < p.eye + .32
		):
			damage(
				float(shot.damage) if shot.enemy else 24.0,
				[shot.x - shot.vx * .18, shot.y - shot.vy * .18],
				"FIRE" if shot.enemy else "RICOCHET"
			)
			finish_shot(shot)
			return false
		if shot.enemy and shot.owner != 0 and shot.travelled > .45:
			# A stray from one of the county's catching another of them.
			var struck := _county_in_the_way(shot, x, y, z)
			if struck != null:
				var thrower = instance_from_id(shot.owner)
				struck.hurt(
					float(shot.damage) * .8,
					self,
					false,
					false,
					thrower if thrower is Enemy else null
				)
				finish_shot(shot)
				return false
		if shot.enemy or tnt:
			continue
		if not _hits(shot, x, y, z):
			return false
	return true


## A rolling shot's step (tumble.gd): a stick of dynamite bounces, rolls down
## slopes and off walls and lies still to burn down; a bowling ball rolls on
## till it slows, coming off two walls on the way. False: the ball is done.
func _roll(shot: Shot, dt: float, tnt: bool) -> bool:
	var before := Vector2(shot.x, shot.y)
	var hit := Tumble.step(world, shot, Tumble.shot_feel(shot.kind), dt)
	shot.travelled += before.distance_to(Vector2(shot.x, shot.y))
	if tnt:
		if hit & Tumble.WALL:
			sound_at("tnt_bounce", shot.x, shot.y)
		elif hit & Tumble.FLOOR:
			sound_at("tnt_roll", shot.x, shot.y, .7)
		if hit & Tumble.RESTED:
			shot.resting = true
		return true
	if hit & Tumble.WALL:
		shot.bounces -= 1
		sound_at("bowling_thud", shot.x, shot.y, .7)
		burst(shot.x, shot.y, shot.z, "dust", 5, 1.0)
	if shot.bounces < 0 or hit & Tumble.RESTED or shot.vx * shot.vx + shot.vy * shot.vy < .09:
		finish_shot(shot)
		return false
	return true


## What a player's shot strikes where it is now: a drum, something that
## breaks, an enemy. False when it is used up there.
func _hits(shot: Shot, x: float, y: float, z: float) -> bool:
	var drum = null
	for point in drums.keys():
		var vec: Vector2 = point
		if (
			sqrt(pow(vec.x - x, 2) + pow(vec.y - y, 2)) < .27
			and 0.0 <= z - world.elevation(vec.x, vec.y)
			and z - world.elevation(vec.x, vec.y) <= 1.07
		):
			drum = vec
			break
	if drum != null:
		drum_hit(drum, 25)
		return false
	var pieces = features.get("breakables")
	var piece: int = -1 if pieces == null else pieces.touch(x, y, z, .22)
	if piece >= 0:
		pieces.strike(piece, float(maxi(shot.damage, 25)), shot.vx, shot.vy)
		if shot.kind != "bowling" and shot.kind != "blade":
			finish_shot(shot)
			return false
		# A ball or a blade goes on through, slowed.
		shot.vx *= .8
		shot.vy *= .8
	for enemy: Enemy in enemies:
		if not enemy.alive or enemy.brain == "bessie":
			continue
		var dz: float = z - enemy.z - world.elevation(enemy.x, enemy.y)
		if (
			-.07 < dz
			and dz < enemy.height + .05
			and sqrt(pow(enemy.x - x, 2) + pow(enemy.y - y, 2)) < enemy.radius + .10
		):
			hit_point = Vector3(x, y, z)
			hit_from = Vector2(player.x, player.y)
			if shot.kind == "blade":
				enemy.hurt(shot.damage, self, false, false, null, "blade")
				sound_at("saw_hit", x, y)
			elif shot.kind == "bowling":
				var key := shot.get_instance_id()
				if not bowled.has(key):
					bowled[key] = {}
				var seen: Dictionary = bowled[key]
				var eid := enemy.get_instance_id()
				if not seen.has(eid):
					seen[eid] = true
					enemy.hurt(shot.damage, self, false, false, null, "bowling")
					sound_at("bowling_hit", x, y)
					if seen.size() == 3 and barks.enabled:
						# Three down with one ball.
						callout = "STRIKE!"
						callout_until = clock + 1.3
						sound.play("yee_haw", .7)
					burst(x, y, z, "dust", 6, 1.4)
					shot.vx *= .8
					shot.vy *= .8
			else:
				finish_shot(shot)
			return false
	return true


func _county_in_the_way(shot: Shot, x: float, y: float, z: float) -> Enemy:
	for e: Enemy in enemies:
		if not e.alive or not e.hostile or e.get_instance_id() == shot.owner:
			continue
		if absf(e.x - x) > .6 or absf(e.y - y) > .6:
			continue
		var feet: float = world.elevation(e.x, e.y) + e.z
		if (
			(e.x - x) * (e.x - x) + (e.y - y) * (e.y - y) < e.radius * e.radius
			and feet < z
			and z < feet + e.height
		):
			return e
	return null


func update_shots(dt: float) -> void:
	var kept: Array = []
	for shot in shots:
		if move_shot(shot, dt):
			kept.append(shot)
	shots = kept
	if finale != null and not finale.alive:
		var filtered: Array = []
		for shot in shots:
			if shot.kind != "foreman_cut" and shot.kind != "rudy_horn":
				filtered.append(shot)
		shots = filtered
	for speck in specks:
		speck.life -= dt
		speck.z += speck.vz * dt
		speck.vz -= dt * 6.0
		var x: float = speck.x + speck.vx * dt
		var y: float = speck.y + speck.vy * dt
		if not world.blocked(x, y):
			speck.x = x
			speck.y = y
	var alive_specks: Array = []
	for speck in specks:
		if speck.life > 0.0 and speck.z >= -.05:
			alive_specks.append(speck)
	specks = alive_specks
	gore_fx.tick(dt)
	for blast in blasts:
		blast.age += dt
	var alive_blasts: Array = []
	for blast in blasts:
		if blast.age < .64:
			alive_blasts.append(blast)
	blasts = alive_blasts


func add_hazard(
	kind: String, x: float, y: float, radius: float, warning: float, life: float, damage_amount: int
) -> void:
	if not world.blocked(x, y, .04):
		hazards.append(Hazard.new(kind, x, y, radius, warning, life, damage_amount))
		if hazards.size() > 7:
			hazards.pop_front()


func update_hazards(dt: float) -> void:
	var p := player
	for hazard: Hazard in hazards:
		hazard.age += dt
		if (
			hazard.warning <= hazard.age
			and hazard.age < hazard.life
			and hazard.age >= hazard.next_hit
			and p.air < .28
			and sqrt(pow(p.x - hazard.x, 2) + pow(p.y - hazard.y, 2)) < hazard.radius
			and world.visible(hazard.x, hazard.y, p.x, p.y)
		):
			damage(
				hazard.damage, [hazard.x, hazard.y], "STEAM" if hazard.kind == "steam" else "CHALK"
			)
			hazard.next_hit = hazard.life if hazard.kind == "steam" else hazard.age + .68
	var kept: Array = []
	for hazard: Hazard in hazards:
		if hazard.age < hazard.life:
			kept.append(hazard)
	hazards = kept


## Mirrors Game.ground_marks: decals, hazard rings, boss telegraphs, actor
## shadows. `dress_marks` rows stay raw JSON ([x,y,z,angle,reach,width,image]).
func ground_marks() -> Array:
	var p := player
	var marks: Array = []
	if dress_of != world:
		dress_of = world
		dress_list = []
		dress_at = PackedFloat64Array()
		for row in world.dress_marks:
			var image := String(row[6])
			dress_list.append(
				Renderer.GroundMark.new(
					float(row[0]),
					float(row[1]),
					float(row[2]),
					float(row[3]),
					float(row[4]),
					float(row[5]),
					image
				)
			)
			dress_at.append(float(row[0]))
			dress_at.append(float(row[1]))
			dress_at.append(14.0 if image == "fx_shadow" else 9.49)
	for i in dress_list.size():
		var x := dress_at[i * 3]
		var y := dress_at[i * 3 + 1]
		var reach := dress_at[i * 3 + 2]
		if (x - p.x) * (x - p.x) + (y - p.y) * (y - p.y) < reach * reach:
			marks.append(dress_list[i])
	for stain: Renderer.GroundMark in gore_fx.blood_marks:
		if (stain.x - p.x) * (stain.x - p.x) + (stain.y - p.y) * (stain.y - p.y) < 81.0:
			marks.append(stain)
	marks.append_array(Features.ground_marks(self))
	if in_hub:
		return marks
	for hazard: Hazard in hazards:
		var kind := hazard.kind if hazard.age >= hazard.warning else "warning"
		marks.append(_spot(hazard.x, hazard.y, hazard.radius, kind))
	for point: Vector2 in world.pressure_ports:
		# The outlets in the baron's still house, glowing for whoever is near.
		if absf(point.x - player.x) < 16.0 and absf(point.y - player.y) < 12.0:
			marks.append(_spot(point.x, point.y, .38, "outlet"))
	for enemy: Enemy in enemies:
		if not enemy.alive or enemy.windup <= 0.0 or enemy.aim_mark == null:
			continue
		var mark: Array = enemy.aim_mark
		var mx: float = mark[0]
		var my: float = mark[1]
		if enemy.brain == "chalk_spitter":
			marks.append(_spot(mx, my, .89, "warning"))
		elif enemy.brain == "bottle_tosser":
			marks.append(_spot(mx, my, .77, "warning"))
		elif enemy.brain == "baron" and BaronMoves.outlets_next(enemy.attacks, enemy.enraged):
			for point: Vector2 in pressure_ports(enemy.attacks):
				marks.append(_spot(point.x, point.y, .94, "warning"))
		elif enemy.brain == "rudy":
			# The horn sweep: the fan its volley will rake along the ground.
			var toward := atan2(my - enemy.y, mx - enemy.x)
			var sweep := -1.0 if (enemy.attacks + 1) % 2 else 1.0
			for off: float in [-.16, 0.0, .12]:
				var bearing := toward + sweep * off
				var length := 0.0
				while length < 7.0:
					var step := length + .32
					if world.blocked(
						enemy.x + cos(bearing) * step, enemy.y + sin(bearing) * step, .03
					):
						break
					length = step
				if length > .6:
					marks.append(
						Renderer.GroundMark.new(
							enemy.x + cos(bearing) * length / 2.0,
							enemy.y + sin(bearing) * length / 2.0,
							world.elevation(enemy.x, enemy.y) + .003,
							bearing,
							length / 2.0,
							.22,
							"mark_lane"
						)
					)
		elif enemy.brain == "derby_champ":
			marks.append_array(DerbyChamp.marks(enemy, self))
		elif enemy.brain == "foreman":
			var direction := atan2(my - enemy.y, mx - enemy.x)
			for lane in enemy.saw_lanes(direction, enemy.attacks + 1):
				var sx: float = lane[0]
				var sy: float = lane[1]
				var bearing: float = lane[2]
				var length := 0.0
				while length < 10.0:
					var step := length + .32
					if world.blocked(sx + cos(bearing) * step, sy + sin(bearing) * step, .03):
						break
					length = step
				if length > .4:
					var hx := sx + cos(bearing) * length / 2.0
					var hy := sy + sin(bearing) * length / 2.0
					marks.append(
						Renderer.GroundMark.new(
							hx,
							hy,
							world.elevation(sx, sy) + .003,
							bearing,
							length / 2.0,
							.30,
							"mark_lane"
						)
					)
	var nearby: Array = []
	for enemy: Enemy in enemies:
		if not enemy.alive:
			continue
		var distance: float = (enemy.x - p.x) * (enemy.x - p.x) + (enemy.y - p.y) * (enemy.y - p.y)
		if distance < 64.0:
			nearby.append([distance, enemy])
	nearby.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	for i in mini(6, nearby.size()):
		var enemy: Enemy = nearby[i][1]
		var radius := enemy.radius * (1.03 if enemy.z <= .02 else 1.28)
		marks.append(
			Renderer.GroundMark.new(
				enemy.x,
				enemy.y,
				world.elevation(enemy.x, enemy.y) + .003,
				enemy.angle,
				radius * 1.24,
				radius,
				"fx_shadow"
			)
		)
	return marks


func _spot(x: float, y: float, radius: float, kind: String) -> Renderer.GroundMark:
	return Renderer.GroundMark.new(
		x, y, world.elevation(x, y) + .003, 0.0, radius, radius, "mark_" + kind
	)


# ---------------------------------------------------------------- exchanges


func tick_exchanges(combat: bool) -> void:
	if exchanges.is_empty() or (not voice_captions and sound.voice_gain == 0.0):
		return
	if combat or won:
		if caption_until > clock or exchange_pending != null:
			sound.stop_voice()
			caption_until = 0.0
			exchange_pending = null
		exchange_next = clock + 3.5
		return
	if clock < exchange_next:
		return
	exchange_next = clock + .55
	var pending = exchange_pending
	exchange_pending = null
	var pool: Array = [pending] if pending != null else exchanges
	for exchange in pool:
		if (
			stations_done.has(exchange.stop_at)
			or (pending == null and heard_exchanges.has(exchange.id))
		):
			continue
		var p := player
		if (
			sqrt((p.x - exchange.x) * (p.x - exchange.x) + (p.y - exchange.y) * (p.y - exchange.y))
			> 4.25
		):
			continue
		if not world.visible(
			p.x, p.y, exchange.x, exchange.y, p.eye, world.elevation(exchange.x, exchange.y) + .95
		):
			continue
		var index := 0 if pending == null else 1
		var place := sound_position(exchange.x, exchange.y, .74, false)
		var length: float = sound.play_voice("talk_%s_%d" % [exchange.id, index], place.x, place.y)
		caption = String(exchange.lines[index])
		caption_until = clock + maxf(1.35, length + .15)
		if pending == null:
			heard_exchanges[exchange.id] = true
			exchange_pending = exchange
			exchange_next = caption_until + .18
		else:
			exchange_next = caption_until + 8.0
		break

# --------------------------------------------------------------------- tick
