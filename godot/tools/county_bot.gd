## A bot that plays COUNTY RUN (tools/county_check.gd, `--county-bot` play
## tests): it shoots the nearest varmint it sees, backs away from the ones
## close by, walks to the XP it can reach when nothing is on top of it,
## switches to a gun with rounds when one runs dry and picks reward cards
## (pick(): the guaranteed upgrade first, a weapon to fill a slot, else the
## first card; milestone cards in a set order of liking). Its controls go
## through game.tick as a player's do.
extends RefCounted

const STEP := 1.0 / 60.0

var stuck := 0.0
var last := Vector2.INF
var wander := 0.0
var foe: Enemy = null


func steer(game: Game) -> Game.Controls:
	var c := Game.Controls.new()
	var p := game.player
	var f = game.features.get("county")
	foe = _nearest(game)
	var a: Weapons.Armory = game.armory
	var melee := CountyData.kind_of(a.active) == CountyData.MELEE
	# Aim at the nearest seen; fire when on it.
	if foe != null:
		var want := atan2(foe.y - p.y, foe.x - p.x)
		var turn := fposmod(want - p.angle + PI, TAU) - PI
		c.turn = clampf(turn, -.14, .14)
		var top: float = game.world.stand(foe) + foe.z + foe.height * .55
		var gap := Vector2(foe.x - p.x, foe.y - p.y).length()
		c.look = clampf((top - p.eye) / maxf(.5, gap) * Renderer.base_focal - p.pitch, -3.0, 3.0)
		var reach := 1.9 if melee else 30.0
		c.fire = absf(turn) < .09 and gap < reach
		c.alt_fire = a.active == Weapons.SHOTGUN and gap < 3.0 and absf(turn) < .09
	else:
		c.look = clampf(-p.pitch, -2.0, 2.0)
	# Where to go: away from the crowd, to XP when it is quiet, else drift.
	var push := Vector2.ZERO
	var crowd := 0
	for e: Enemy in game.enemies:
		if not e.alive or not e.hostile:
			continue
		var d := Vector2(p.x - e.x, p.y - e.y)
		var n := d.length()
		var keep := 1.6 if melee else 5.0
		if n < keep and n > .01:
			push += d / n * (keep - n)
			crowd += 1
	var goal := Vector2.ZERO
	if push.length() < .5 and f != null:
		var orb = _nearest_orb(game, f)
		if orb != null:
			goal = (orb - Vector2(p.x, p.y)).normalized()
	if melee and foe != null and push.length() < .5:
		goal = Vector2(foe.x - p.x, foe.y - p.y).normalized()
	var want_dir := push.normalized() * 1.2 + goal
	if want_dir.length() < .2:
		wander += STEP * .4
		want_dir = Vector2(cos(wander), sin(wander)) * .6
	want_dir = _clear_way(game, want_dir)
	var face := p.view_angle()
	var fx := cos(face)
	var fy := sin(face)
	c.forward = clampf(want_dir.x * fx + want_dir.y * fy, -1.0, 1.0)
	c.strafe = clampf(want_dir.x * -fy + want_dir.y * fx, -1.0, 1.0)
	c.running = crowd > 0 or goal != Vector2.ZERO
	# Dry: the next gun with rounds (melee always has some).
	var dry: bool = (
		not melee and a.reload <= 0.0 and a.loaded[a.active] == 0 and a.reserve[a.active] == 0
	)
	if dry:
		c.cycle = 1
	elif melee and f != null:
		for gun: int in CountyBuild.carried(f):
			if (
				CountyData.kind_of(gun) != CountyData.MELEE
				and (a.loaded[gun] > 0 or a.reserve[gun] > 0)
			):
				if foe == null or Vector2(foe.x - p.x, foe.y - p.y).length() > 2.5:
					c.weapon = gun
				break
	# MUDSLIDE out of a crowd.
	if crowd >= 3 and f != null and CountyBuild.has(f, "mudslide") and game.clock >= f.dash_ready:
		c.use = true
	if stuck > .4:
		c.jump = fmod(game.clock, .6) < .1
	return c


func moved(game: Game) -> void:
	var p := game.player
	if last != Vector2.INF and Vector2(p.x, p.y).distance_to(last) < .002:
		stuck += STEP
	else:
		stuck = 0.0
	last = Vector2(p.x, p.y)


## The bot's pick of the cards on offer (an index).
static func pick(game: Game, f) -> int:
	var best := 0
	var score := -1.0
	var liking := [
		"second_wind",
		"buckshot_breaker",
		"six_shooter",
		"chain_reaction",
		"grit_armor",
		"mudslide",
		"breakaway",
		"last_stand",
		"big_haul",
		"double_down",
		"iron_gut"
	]
	for i in f.offer.size():
		var c: Dictionary = f.offer[i]
		var s := 1.0
		match String(c["type"]):
			"upgrade":
				s = 5.0 if int(c["gun"]) == game.armory.active else 3.0
			"weapon":
				s = 6.0 if CountyBuild.open_slot(f) >= 0 else .5
			"perk":
				s = (
					2.0
					+ (3.0 if String(c["id"]) == "patch_up" and game.player.health < 50 else 0.0)
				)
			"milestone":
				s = 10.0 - liking.find(String(c["id"]))
		if s > score:
			score = s
			best = i
	return best


func _nearest(game: Game) -> Enemy:
	var p := game.player
	var best: Enemy = null
	var near := 22.0
	for e: Enemy in game.enemies:
		if not e.alive or not e.hostile:
			continue
		var d := Vector2(e.x - p.x, e.y - p.y).length()
		if (
			d < near
			and game.world.visible(p.x, p.y, e.x, e.y, p.eye, game.world.stand(e) + e.height * .6)
		):
			near = d
			best = e
	return best


func _nearest_orb(game: Game, f) -> Variant:
	var p := game.player
	var best = null
	var near := 12.0
	for orb: Array in f.orbs:
		var at := Vector2(float(orb[0]), float(orb[1]))
		var d := at.distance_to(Vector2(p.x, p.y))
		if d < near and absf(float(orb[2]) - game.world.stand(p)) < .6:
			if game.world.visible(p.x, p.y, at.x, at.y, p.eye, float(orb[2]) + .25):
				near = d
				best = at
	return best


## The way `want` turned until a step along it is open.
func _clear_way(game: Game, want: Vector2) -> Vector2:
	var p := game.player
	if want.length() < .01:
		return want
	for k in 8:
		var a := (
			want.angle() + (k / 2 + 1) * .55 * (1 if k % 2 == 0 else -1) if k > 0 else want.angle()
		)
		var probe := Vector2(p.x, p.y) + Vector2(cos(a), sin(a)) * .7
		if not game.world.blocked(probe.x, probe.y, .25):
			return Vector2(cos(a), sin(a)) * want.length()
	return -want
