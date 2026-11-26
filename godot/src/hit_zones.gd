## Where a hit lands on one of the county (Enemy.hurt): head, body, arms or
## legs, from how high on the body it struck, how far off its middle and from
## which side. Only the player's own hits have a zone: every hitscan shot,
## pellet, swing, saw blade, bowling ball and pierced round sets
## game.hit_point and game.hit_from before hurt() (a blast's point is its
## middle: the body). No dice in the damage: the zone is the hit's geometry,
## so the same shot always does the same.
##
##   head  more damage by the gun (HEAD); its hat comes off; a kill pops
##   legs  less damage (LEGS), and it limps a while (LIMP_TIME at LIMP_PACE)
##   arms  less damage (ARMS); a hand with a weapon (HELD) may drop it
##         (DROP_CHANCE, the game's rng) and must fetch it, fists only till
##         then; otherwise a wind-up's aim is thrown wide, or it fumbles
##
## A bigger instant also staggers it further (REEL: a flinch, a stumble back).
## Bosses keep their weak spots (BossKit.weak): the zone is noted on them
## (Enemy.last_zone) and nothing more. Limps and dropped weapons last seconds
## and are not saved: a save made in one comes back with the weapon in hand.
## features/hit_reads.gd shows and sounds it; this file is the play.
class_name HitZones
extends RefCounted

## Shares of the body's height: the head is above HEAD_AT, the legs below
## LEGS_BELOW. In between, a hit further off the middle than ARM_OUT of the
## radius (ARM_SIDE seen side on, an arm toward the gun) is an arm.
static var HEAD_AT: float = ModeData.get_value("hit_zones", "head_at")
static var LEGS_BELOW: float = ModeData.get_value("hit_zones", "legs_below")
static var ARM_OUT: float = ModeData.get_value("hit_zones", "arm_out")
static var ARM_SIDE: float = ModeData.get_value("hit_zones", "arm_side")
## How the 5v5 store's guns move what they hit, as enemies.gd REACTIONS has
## the campaign's: [shove in cells, stun seconds, flinch seconds].
static var MORE_REACTIONS: Dictionary = HitData.section("reaction.store")

## Damage on the head by gun (hurt()'s `how`); the rest take HEAD_DEFAULT. A
## pellet less than a single round, so a load of buckshot stays a load.
static var HEAD: Dictionary = HitData.section("head", ["default"])
static var HEAD_DEFAULT: float = HitData.value("head", "default", 1.5)
static var ARMS: float = HitData.value("zones", "arms", .82)
static var LEGS: float = HitData.value("zones", "legs", .78)
static var LIMP_TIME: float = HitData.value("zones", "limp_time", 3.0)
static var LIMP_PACE: float = HitData.value("zones", "limp_pace", .55)
## What each kind holds that it can drop, as the picture of it lying there
## (fx_drop_<held>); the rest have nothing to drop.
static var HELD: Dictionary = ModeData.get_value("hit_zones", "held")
static var DROP_CHANCE: float = ModeData.get_value("hit_zones", "drop_chance")
## Longest it goes without (it gives up looking and has it again), how long
## it stoops to pick it up, and its fists: damage, reach past its radius, and
## the time between swings.
static var DROP_TIME: float = ModeData.get_value("hit_zones", "drop_time")
static var PICK_TIME: float = ModeData.get_value("hit_zones", "pick_time")
static var PUNCH: int = ModeData.get_value("hit_zones", "punch")
static var PUNCH_REACH: float = ModeData.get_value("hit_zones", "punch_reach")
static var PUNCH_TIME: float = ModeData.get_value("hit_zones", "punch_time")
## How far a wind-up's mark is thrown aside by an arm hit, in cells.
static var AIM_THROW: float = ModeData.get_value("hit_zones", "aim_throw")
## One instant's damage that reels it further each step: [damage, stumble back
## in cells, flinch seconds, stun seconds].
static var REEL: Array = ModeData.get_value("hit_zones", "reel")
## Shells of tin and steel: a hit sparks and clanks instead of bleeding. The
## boilerback only on the boiler on his back.
static var METAL: Array = ModeData.get_value("hit_zones", "metal")

## Pass 15 (hits.cfg [punch]): the sawed-off's arm's length, a close kill's
## reach, and the shoves by distance.
static var POINT_BLANK: float = HitData.value("punch", "point_blank", 1.0)
static var CLOSE_REACH: float = HitData.value("punch", "close_reach", 3.0)
static var SHOVE_NEAR: float = HitData.value("punch", "shove_near", 1.35)
static var SHOVE_FAR: float = HitData.value("punch", "shove_far", .7)
static var SHOVE_FAR_FROM: float = HitData.value("punch", "shove_far_from", 9.0)

const HitReads := preload("res://src/features/hit_reads.gd")
const Critters := preload("res://src/features/critters.gd")


## Whether it has a head and limbs to hit (the county's hands, the greys).
static func limbs(e: Enemy) -> bool:
	return Enemy.TURNS.has(e.kind) and not Enemy.BOSS_TITLES.has(e.kind)


## Whether this hit is on metal (sparks, a clank, no blood).
static func metal(e: Enemy) -> bool:
	return METAL.has(e.kind) or (e.kind == "boilerback" and e.last_side == "back")


## Enemy.hurt, before the damage is taken: where the player's hit struck, and
## how much that makes of it. 1 for anything but the player's aimed hit on a
## body with a head and limbs.
static func strike(e: Enemy, game: Game, how: String, by: Enemy) -> float:
	e.last_zone = ""
	e.last_side = ""
	var hit: Vector3 = game.hit_point
	if by != null or hit == Vector3.INF:
		return 1.0
	if how == "blast" or how == "energy":
		e.last_zone = "body"
		e.blast_at = Vector2(hit.x, hit.y)
		return 1.0
	var from: Vector2 = game.hit_from
	e.last_side = side(e, from)
	e.last_zone = zone(e, game, hit, from) if limbs(e) or BossKit.is_boss(e) else "body"
	if not limbs(e):
		return 1.0
	match e.last_zone:
		"head":
			return HEAD.get(how, HEAD_DEFAULT)
		"arms":
			return ARMS
		"legs":
			return LEGS
	return 1.0


## Which way it faced the shot: "front", "side" or "back".
static func side(e: Enemy, from: Vector2) -> String:
	var turn := absf(Enemy.angle_delta(atan2(from.y - e.y, from.x - e.x), e.angle))
	return "back" if turn > 2.3 else "side" if turn > .9 else "front"


## The zone a hit at `hit`, from `from`, is on.
static func zone(e: Enemy, game: Game, hit: Vector3, from: Vector2) -> String:
	var feet: float = game.world.stand(e) + e.z
	var up := (hit.z - feet) / maxf(.1, e.height * e.variant)
	if up >= HEAD_AT:
		return "head"
	if up < LEGS_BELOW:
		return "legs"
	var dir := Vector2(hit.x, hit.y) - from
	if dir.length() < .01:
		return "body"
	dir = dir.normalized()
	var rel := Vector2(e.x, e.y) - from
	var off := absf(rel.x * dir.y - rel.y * dir.x)
	var out := ARM_SIDE if e.last_side == "side" else ARM_OUT
	if off > e.radius * out and off < e.radius + .1:
		return "arms"
	return "body"


## The speck kind a hit throws: sparks off metal, else the kind it bleeds.
## Thrown through the game's burst() as ever (the same count, so the same
## dice), or off the feature's own dice where burst() would have thrown none.
static func splash(e: Enemy, game: Game, x: float, y: float, z: float, bleeds: String) -> void:
	if not metal(e):
		game.burst(x, y, z, bleeds, 4, .9)
		return
	if bleeds == "gore" and not game.gore:
		var fx: HitReads = game.features.get("hit_reads")
		if fx != null:
			fx.sparks(x, y, z, 4, .9)
		return
	game.burst(x, y, z, "spark", 4, .9)


## Enemy.hurt, after the damage and the crosshair's mark: what the zone does.
static func land(e: Enemy, game: Game, amount: float, by: Enemy) -> void:
	var critters: Critters = game.features.get("critters")
	if critters != null and by == null:
		critters.struck(e)
	if by != null or e.last_zone == "":
		return
	var fx: HitReads = game.features.get("hit_reads")
	if fx != null:
		fx.landed(e, amount)
	if not e.alive or not e.hostile or not limbs(e):
		return
	_reel(e, game)
	match e.last_zone:
		"head":
			e.flinch = maxf(e.flinch, .34)
		"legs":
			e.limp_until = maxf(e.limp_until, game.clock + LIMP_TIME)
			e.flinch = maxf(e.flinch, .26)
		"arms":
			_arm(e, game)


## A bigger instant reels it further: each step of REEL it newly reaches
## this instant stumbles it back from the gun a little more.
static func _reel(e: Enemy, game: Game) -> void:
	if game.clock - e.reel_at > .06:
		e.reel = 0
	e.reel_at = game.clock
	var step := 0
	for k in REEL.size():
		if e.struck_sum >= REEL[k][0]:
			step = k + 1
	if step <= e.reel:
		return
	var before: float = 0.0 if e.reel == 0 else REEL[e.reel - 1][1]
	var row: Array = REEL[step - 1]
	e.reel = step
	var from: Vector2 = game.hit_from
	var away := atan2(e.y - from.y, e.x - from.x)
	var back: float = (row[1] - before) * shove_by(e, from.x, from.y)
	Stagger.shove(e, game, cos(away) * back, sin(away) * back)
	var flinch: float = row[2]
	var stun: float = row[3]
	e.flinch = maxf(e.flinch, flinch)
	e.stun = maxf(e.stun, stun)


## An arm hit: a weapon dropped (if it holds one and the dice say so), or a
## wind-up's aim thrown wide, or a fumble.
static func _arm(e: Enemy, game: Game) -> void:
	var held := str(HELD.get(e.kind, ""))
	if held != "" and e.disarmed_until < 0.0 and game.clock - e.arm_roll > .1:
		# Once an instant: a load of buckshot is ten hits.
		e.arm_roll = game.clock
		if game.rng.random() < DROP_CHANCE:
			_drop(e, game, held)
			return
	if e.windup > 0.0 and e.aim_mark is Array and len(e.aim_mark) >= 2:
		var aimed: Array = e.aim_mark
		var mark: Array = aimed.duplicate()
		var dx: float = mark[0] - e.x
		var dy: float = mark[1] - e.y
		var length := maxf(.01, sqrt(dx * dx + dy * dy))
		var turn := 1.0 if e.attacks % 2 else -1.0
		var mark_x: float = mark[0]
		var mark_y: float = mark[1]
		mark[0] = mark_x - dy / length * AIM_THROW * turn
		mark[1] = mark_y + dx / length * AIM_THROW * turn
		e.aim_mark = mark
	else:
		e.cooldown = maxf(e.cooldown, .35)


## It drops its weapon: it lands a step back from the gun (the first open,
## level spot it can see, or at its feet), and the hand has to go and get it.
static func _drop(e: Enemy, game: Game, held: String) -> void:
	e.disarmed_until = game.clock + DROP_TIME
	e.pick_at = -1.0
	e.windup = 0.0
	e.aim_mark = null
	e.volley = 0
	var world: LevelData = game.world
	var p := game.player
	var away := atan2(e.y - p.y, e.x - p.x)
	var here := world.stand(e)
	var spot := Vector2(e.x, e.y)
	for reach: float in [1.0, .75, .5, .25]:
		var at := Vector2(e.x + cos(away) * reach, e.y + sin(away) * reach)
		if (
			not world.blocked(at.x, at.y, e.radius)
			and not world.deep_at(at.x, at.y)
			and absf(world.elevation(at.x, at.y) - here) < .2
			and world.visible(e.x, e.y, at.x, at.y)
		):
			spot = at
			break
	e.arm_at = spot
	game.sound_at("scenery_scrap", e.x, e.y, .55)
	var fx: HitReads = game.features.get("hit_reads")
	if fx != null:
		fx.drop_arm(e, held, spot)


## Enemy.tick's hook: a hand without its weapon goes and gets it, swinging
## its fists at the player if they come close. True when it took the tick.
static func tick(e: Enemy, dt: float, game: Game) -> bool:
	if e.disarmed_until < 0.0:
		return false
	if game.clock >= e.disarmed_until or e.arm_at == Vector2.INF:
		_rearm(e, game)
		return false
	if e.stun > 0.0:
		return true
	e.cooldown -= dt * float(game.sharpness)
	var p := game.player
	var gap := Vector2(p.x - e.x, p.y - e.y)
	if gap.length() < e.radius + PUNCH_REACH:
		e.angle = gap.angle()
		e.face_left = gap.x < 0.0
		if e.cooldown <= 0.0:
			e.cooldown = PUNCH_TIME
			game.sound_at("brawl_punch", e.x, e.y, .8)
			game.damage(PUNCH, [e.x, e.y], "STRIKE")
		return true
	var to := e.arm_at - Vector2(e.x, e.y)
	if e.pick_at < 0.0 and to.length() > .2:
		e.follow(dt, game, to.angle(), 1.1)
		return true
	if e.pick_at < 0.0:
		e.pick_at = game.clock + PICK_TIME
	if game.clock >= e.pick_at:
		_rearm(e, game)
	return true


static func _rearm(e: Enemy, game: Game) -> void:
	e.disarmed_until = -1.0
	e.pick_at = -1.0
	e.arm_at = Vector2.INF
	e.cooldown = maxf(e.cooldown, .45)
	var fx: HitReads = game.features.get("hit_reads")
	if fx != null:
		fx.picked_up(e)


## Whether a kill is an overkill that takes the body apart: far more in one
## instant than it could take, counted without the head's extra (a head shot
## pops the head, not the whole body). One barrel of buckshot throws the body
## back instead (hard at arm's length: features/corpses.gd); both barrels at
## once still take it apart.
static func overkill(e: Enemy, game: Game, how: String) -> bool:
	if how == "shotgun" and point_blank(e, game):
		# (Pass 15) the sawed-off at arm's length always takes it apart.
		return true
	if how == "shotgun" and game.armory.last_spent < 2:
		return false
	var sum := e.struck_sum
	if e.last_zone == "head" and limbs(e):
		var head: float = HEAD.get(how, HEAD_DEFAULT)
		sum /= head
	return sum >= maxf(48.0, e.max_hp * .7)


## Whether the player stands within hits.cfg [punch] `point_blank` of `e`.
static func point_blank(e: Enemy, game: Game) -> bool:
	var p := game.player
	return Vector2(e.x - p.x, e.y - p.y).length() <= POINT_BLANK


## How far a shove goes by the distance it came from (hits.cfg [punch]):
## SHOVE_NEAR times within CLOSE_REACH, SHOVE_FAR past SHOVE_FAR_FROM, eased
## between.
static func shove_by(e: Enemy, from_x: float, from_y: float) -> float:
	var d := Vector2(e.x - from_x, e.y - from_y).length()
	if d <= CLOSE_REACH:
		return SHOVE_NEAR
	var k := clampf((d - CLOSE_REACH) / maxf(.1, SHOVE_FAR_FROM - CLOSE_REACH), 0.0, 1.0)
	return lerpf(SHOVE_NEAR, SHOVE_FAR, k)


## Whether the killing blast takes the body apart. A blast at its edge that
## only just finishes one throws it whole, and the cow launcher never takes
## one apart: they go up and come down (features/corpses.gd).
static func blast_gibs(e: Enemy, game: Game) -> bool:
	if game.blast_kind == "cow":
		return false
	return e.struck_sum >= maxf(30.0, e.max_hp * .45)
