## A strong round going on through a thin wall: the ranch rifle punches
## through a plank wall, a sheet of tin or a fence and hits who is behind it,
## for less. It is play, not looks: the game's own rules (world.blocked, the
## materials' resistance, weapons.cfg `penetrate` and `penetrate_damage`), no
## dice, so the same shot always does the same thing. tools/feel_check.gd holds
## it to that.
class_name Penetration
extends RefCounted

## How finely the round is walked through what it crosses.
const STEP := .02
## How thick anything shot through may be at most, whatever the gun.
const MOST := 1.6


## The shot along (ax, ay, slope) met a wall first sampled `d_block` along it;
## if the gun in hand can get through, it goes on and hurts the first hostile
## or beast it meets within `max_range`. Returns true when one was hit.
static func pierce(
	game,
	ax: float,
	ay: float,
	slope: float,
	d_block: float,
	amount: float,
	max_range: float,
	spread: float,
	pressure := false
) -> bool:
	var gun: int = game.armory.active
	var how: Dictionary = Weapons.FIRING[gun]
	var power := float(how.get("penetrate", 0.0))
	if power <= 0.0:
		return false
	var through := crossing(game.world, game.player, ax, ay, slope, d_block, power, max_range)
	if through.is_empty():
		return false
	var p = game.player
	var entry: float = through[0]
	var exit_d: float = through[1]
	var at_exit := Vector3(p.x + ax * exit_d, p.y + ay * exit_d, p.eye + exit_d * slope)
	var at_entry := Vector3(p.x + ax * entry, p.y + ay * entry, p.eye + entry * slope)
	var target := behind(game, ax, ay, slope, exit_d, max_range, spread)
	if target == null:
		game.pierced.emit(at_entry, at_exit, "air")
		return false
	game.pierced.emit(at_entry, at_exit, "enemy")
	var reach: float = (target.x - p.x) * ax + (target.y - p.y) * ay
	game.hit_point = Vector3(p.x + ax * reach, p.y + ay * reach, p.eye + reach * slope)
	game.hit_from = Vector2(p.x, p.y)
	target.hurt(
		amount * float(how.get("penetrate_damage", .6)),
		game,
		false,
		pressure,
		null,
		String(Weapons.NAMES[gun])
	)
	return true


## Where a round with `power` to spend enters and leaves what stopped it:
## [entry, exit] distances along the shot, or [] when it cannot get through
## (too thick, too hard, the floor, the map's edge, out of range).
static func crossing(
	world: LevelData,
	p,
	ax: float,
	ay: float,
	slope: float,
	d_block: float,
	power: float,
	max_range: float
) -> Array:
	# Back up to just in front of it, then find its face.
	var d := maxf(.05, d_block - .12)
	var entry := -1.0
	var spent := 0.0
	while d < max_range:
		var x: float = p.x + ax * d
		var y: float = p.y + ay * d
		var z: float = p.eye + d * slope
		if x < 0.0 or y < 0.0 or x >= world.width or y >= world.height:
			return []
		var cell := int(y) * world.width + int(x)
		var roof: float = world.roof[cell]
		if z <= world.ground[cell] or (roof > 0.0 and z >= roof):
			return []
		var solid := world.blocked(x, y, .024, z)
		if solid:
			if entry < 0.0:
				entry = d
			var kind := Materials.struck(world, x, y, z)
			spent += Materials.resist(kind) * STEP
			if spent > power or d - entry > MOST:
				return []
		elif entry >= 0.0:
			return [entry, d]
		d += STEP
	return []


## The first hostile (or beast) along the shot past `from` that the round can
## reach unblocked from there.
static func behind(
	game, ax: float, ay: float, slope: float, from: float, max_range: float, spread: float
) -> Enemy:
	var p = game.player
	var world: LevelData = game.world
	var ex: float = p.x + ax * from
	var ey: float = p.y + ay * from
	var ez: float = p.eye + from * slope
	var best: Enemy = null
	var near := max_range
	for enemy: Enemy in game.enemies:
		if not enemy.alive or enemy.brain == "bessie":
			continue
		var dx: float = enemy.x - p.x
		var dy: float = enemy.y - p.y
		var d := dx * ax + dy * ay
		if d <= from or d >= near:
			continue
		if absf(dx * ay - dy * ax) >= enemy.radius + spread:
			continue
		var z: float = p.eye + d * slope
		var feet: float = enemy.z + world.stand(enemy)
		if z <= feet - .10 or z >= feet + enemy.height + .10:
			continue
		if not world.visible(ex, ey, enemy.x, enemy.y, ez, z):
			continue
		best = enemy
		near = d
	return best
