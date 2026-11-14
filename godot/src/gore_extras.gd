## More gore (dev.43), all looks and all on gore.gd's own dice, so play is the
## same with gore on or off: a pool that spreads under a body once it comes to
## rest (not on water); a limb or the head taken off by a heavy hit to it,
## with the stump spurting a moment; robots (HitZones.METAL) coming apart in
## scrap and oil, not meat; a blast's kill throwing charred chunks and leaving
## soot; chunks that smear a trail as they roll and splat on the walls they
## hit; long streaks of blood thrown along a big hit; and bloody boot prints
## the player walks out of a pool.
class_name GoreExtras
extends RefCounted

## A hit this heavy to an arm, a leg or the head takes it off (a body that
## falls whole: an overkill bursts it anyway).
const LIMB_HIT := 44.0
## How long a stump spurts, and how often.
const SPURT := 1.3
const SPURT_EVERY := .07
## A pool's size by the body's, and how fast it spreads (units a second).
const POOL_SIZE := .42
const POOL_GROW := .16
## Boot prints after stepping in blood, one every PRINT_STEP walked.
const PRINTS := 7
const PRINT_STEP := .55
## Scrap off a robot.
const SCRAP_PARTS := ["bolt", "bolt", "gear", "gear", "plate", "plate", "spring", "pipe", "pipe"]
const SCRAP_SIZES := {"bolt": .1, "gear": .17, "plate": .22, "spring": .15, "pipe": .24}


static func metal(e: Enemy) -> bool:
	return HitZones.METAL.has(e.kind)


## A pool spreading under `e` where its body came to rest.
static func pool(gore, e: Enemy) -> void:
	if not gore.game.gore or not e.hostile or e.explosive or Enemy.BOSS_TITLES.has(e.kind):
		return
	var w: LevelData = gore.game.world
	if w.surface_sound(int(w.floor_tile[w.cell(e.x, e.y)])) == "water" or w.blocked(e.x, e.y):
		return
	var green := Enemy.GREEN_GIBS.has(e.kind) or Enemy.PLASMA.has(e.kind)
	var image := (
		("mark_oil_%d" if metal(e) else "mark_acid_%d" if green else "mark_blood_%d")
		% (gore.dice.randi() % 3)
	)
	var target: float = (
		POOL_SIZE * clampf(e.radius / .3, .7, 1.6) * gore.dice.randf_range(.85, 1.15)
	)
	var mark := Renderer.GroundMark.new(
		e.x, e.y, w.stand(e) + .005, gore.dice.randf() * TAU, .06, .06, image
	)
	gore.blood_marks.append(mark)
	if gore.blood_marks.size() > gore.BLOOD_CAP:
		gore.blood_marks.pop_front()
	gore.pools.append([mark, target])


## The pools still spreading.
static func grow(gore, dt: float) -> void:
	if gore.pools.is_empty():
		return
	var left: Array = []
	for p: Array in gore.pools:
		var mark: Renderer.GroundMark = p[0]
		mark.reach = minf(float(p[1]), mark.reach + POOL_GROW * dt)
		mark.width = mark.reach
		if mark.reach < float(p[1]):
			left.append(p)
	gore.pools = left


## A body that fell whole after a heavy hit to a limb or the head: that piece
## flies off and the stump spurts.
static func limb(gore, e: Enemy) -> void:
	if not gore.game.gore or metal(e) or e.struck_sum < LIMB_HIT:
		return
	var part := ""
	match e.last_zone:
		"arms":
			part = "arm" if gore.dice.randf() < .7 else "hand"
		"legs":
			part = "boot"
		"head":
			part = "head"
	if part == "":
		return
	var green := Enemy.GREEN_GIBS.has(e.kind)
	var floor_z: float = gore.game.world.stand(e)
	var away := atan2(e.y - e.killed_from.y, e.x - e.killed_from.x)
	var high := {"head": .92, "arm": .62, "hand": .55, "boot": .15}
	var g := Gore.Gib.new()
	g.x = e.x
	g.y = e.y
	g.z = floor_z + e.height * float(high[part])
	var speed: float = gore.dice.randf_range(1.6, 3.0)
	var angle: float = away + gore.dice.randf_range(-.6, .6)
	g.vx = cos(angle) * speed
	g.vy = sin(angle) * speed
	g.vz = gore.dice.randf_range(1.8, 3.2)
	g.image = ("gib_a_" if green else "gib_") + part
	g.size = float(Gore.GIB_SIZES[part])
	g.green = green
	gore.gibs.append(g)
	while gore.gibs.size() > gore.GIB_CAP:
		gore.gibs.pop_front()
	gore.spurts.append(
		[e, gore.game.clock + SPURT, 0.0, green, floor_z + e.height * float(high[part])]
	)
	gore.game.sound_at("gib_splat", e.x, e.y, .8)


## Stumps spurting.
static func spurt(gore) -> void:
	if gore.spurts.is_empty():
		return
	var game = gore.game
	var left: Array = []
	for s: Array in gore.spurts:
		var e: Enemy = s[0]
		if game.clock >= float(s[1]):
			continue
		left.append(s)
		if game.clock < float(s[2]) or game.specks.size() >= 170:
			continue
		s[2] = game.clock + SPURT_EVERY
		var fade: float = (float(s[1]) - game.clock) / SPURT
		var z := lerpf(game.world.stand(e) + .2, float(s[4]), fade)
		var a: float = gore.dice.randf() * TAU
		game.specks.append(
			Game.Speck.new(
				e.x,
				e.y,
				z,
				cos(a) * .6,
				sin(a) * .6,
				gore.dice.randf_range(1.2, 2.4) * fade + .3,
				gore.dice.randf_range(.25, .5),
				"plasma" if bool(s[3]) else "gore"
			)
		)
	gore.spurts = left


## A robot coming apart: scrap and a slick of oil instead of meat.
static func scrap(gore, e: Enemy) -> void:
	var game = gore.game
	var floor_z: float = game.world.stand(e)
	var away := atan2(e.y - game.player.y, e.x - game.player.x)
	for part: String in SCRAP_PARTS:
		var g := Gore.Gib.new()
		var angle: float = away + gore.dice.randf_range(-1.6, 1.6)
		var speed: float = gore.dice.randf_range(1.2, 4.0)
		g.x = e.x
		g.y = e.y
		g.z = floor_z + e.height * gore.dice.randf_range(.3, .8)
		g.vx = cos(angle) * speed
		g.vy = sin(angle) * speed
		g.vz = gore.dice.randf_range(1.6, 3.8)
		g.image = "gib_m_" + part
		g.size = float(SCRAP_SIZES[part])
		g.flip = gore.dice.randf() < .5
		g.metal = true
		gore.gibs.append(g)
	while gore.gibs.size() > gore.GIB_CAP:
		gore.gibs.pop_front()
	for k in 3:
		var a: float = gore.dice.randf() * TAU
		var r: float = gore.dice.randf_range(0.0, .8)
		oil(gore, e.x + cos(a) * r, e.y + sin(a) * r, gore.dice.randf_range(.18, .4))
	game.burst(e.x, e.y, floor_z + e.height * .5, "spark", 18, 3.0)
	game.sound_at("metal_down", e.x, e.y, .95)


static func oil(gore, x: float, y: float, radius: float) -> void:
	if gore.game.world.blocked(x, y):
		return
	gore.blood_marks.append(
		Renderer.GroundMark.new(
			x,
			y,
			gore.game.world.elevation(x, y) + .004,
			gore.dice.randf() * TAU,
			radius,
			radius,
			"mark_oil_%d" % (gore.dice.randi() % 3)
		)
	)
	if gore.blood_marks.size() > gore.BLOOD_CAP:
		gore.blood_marks.pop_front()


## A streak of blood thrown along (ax, ay) from a big hit.
static func streak(
	gore, x: float, y: float, ax: float, ay: float, amount: float, green: bool
) -> void:
	var reach: float = gore.dice.randf_range(.6, 1.4)
	var at := Vector2(x + ax * reach, y + ay * reach)
	if gore.game.world.blocked(at.x, at.y):
		return
	var length := clampf(amount * .018, .45, 1.1)
	gore.blood_marks.append(
		Renderer.GroundMark.new(
			at.x,
			at.y,
			gore.game.world.elevation(at.x, at.y) + .004,
			atan2(ay, ax),
			length,
			length * .4,
			"mark_streak_%s_%d" % ["acid" if green else "blood", gore.dice.randi() % 2]
		)
	)
	if gore.blood_marks.size() > gore.BLOOD_CAP:
		gore.blood_marks.pop_front()


## A chunk flying into a wall splats on it.
static func wall_splat(gore, g: Gore.Gib) -> void:
	if g.metal:
		return
	var speed := Vector2(g.vx, g.vy).length()
	if speed < .5:
		return
	var ax := g.vx / speed
	var ay := g.vy / speed
	var mark = gore.game.renderer.wall_mark(g.x - ax * .3, g.y - ay * .3, g.z, ax, ay, 0.0, .6)
	if mark == null:
		return
	mark.image = "fx_%s_%d" % ["acid" if g.green else "blood", gore.dice.randi() % 4]
	mark.radius = gore.dice.randf_range(.1, .2)
	mark.z = clampf(g.z, .1, 1.8)
	gore.walls.append(mark)
	if gore.walls.size() > gore.SPLAT_CAP:
		gore.walls.pop_front()


## The player walks out of a pool leaving boot prints.
static func prints(gore) -> void:
	var game = gore.game
	if not game.gore:
		return
	var p: Player = game.local_player
	var here := Vector2(p.x, p.y)
	if gore.last_at == Vector2.INF:
		gore.last_at = here
		return
	var step := here.distance_to(gore.last_at)
	if step < .05:
		return
	var heading: float = (here - gore.last_at).angle()
	gore.last_at = here
	if p.air > .01:
		return
	# Standing in a pool: the boots take it up.
	for i in range(gore.blood_marks.size() - 1, maxi(-1, gore.blood_marks.size() - 40), -1):
		var mark: Renderer.GroundMark = gore.blood_marks[i]
		if mark.image.begins_with("mark_print") or mark.image.begins_with("mark_streak"):
			continue
		if Vector2(mark.x, mark.y).distance_to(here) < mark.reach * .55 and mark.reach > .2:
			gore.bloody = PRINTS
			gore.bloody_green = mark.image.begins_with("mark_acid")
			if mark.image.begins_with("mark_oil"):
				gore.bloody = 0
			break
	if gore.bloody <= 0:
		return
	gore.walked += step
	if gore.walked < PRINT_STEP:
		return
	gore.walked = 0.0
	gore.foot = not gore.foot
	var side := .09 if gore.foot else -.09
	var x := p.x - sin(heading) * side
	var y := p.y + cos(heading) * side
	if game.world.blocked(x, y):
		return
	var size := .16 * (.6 + .4 * float(gore.bloody) / PRINTS)
	gore.blood_marks.append(
		Renderer.GroundMark.new(
			x,
			y,
			game.world.stand(p) + .004,
			heading + PI / 2.0,
			size,
			size,
			"mark_print_%s" % ("acid" if gore.bloody_green else "blood")
		)
	)
	if gore.blood_marks.size() > gore.BLOOD_CAP:
		gore.blood_marks.pop_front()
	gore.bloody -= 1
