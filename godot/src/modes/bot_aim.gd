## A bot's hand on the mouse: the aim of the 5v5 bots (tactical_bot.gd), made
## to miss the way a person does. Numbers by BOT SKILL in data/tuning/modes.cfg
## [bot_aim].
##
## - A foe coming into view is noticed after a reaction time (longer off to the
##   side and far away; short for a foe it saw a moment ago, peeking again).
## - Then the crosshair is flung at it on a spring: it lands short or long
##   (flick), overshoots and settles; it never snaps.
## - The hand's aim point strays (noise), more when the bot moves, when the
##   foe runs across its view, at range and as a burst goes on; a foe running
##   sideways is followed only partly (track), so a strafer is led late.
## - It fires when its crosshair is on where it MEANS to aim, inside a cone
##   about the body's width (trigger): the stray is where the misses come from.
## - Automatic guns go in bursts at range and rest between; the gun's climb is
##   pulled back down by the same spring, partly (recoil).
## Its dice are the bot's own (seeded by slot), never game.rng: the bots play
## on the host only and their controls are what every copy plays.
class_name BotAim
extends RefCounted

static var REACTION: Array = ModeData.get_value("bot_aim", "reaction", [.42, .3, .22, .17])
static var SPRING: Array = ModeData.get_value("bot_aim", "spring", [6.5, 8.5, 11.0, 13.5])
static var DAMPING: Array = ModeData.get_value("bot_aim", "damping", [.5, .58, .66, .72])
static var TURN_MOST: Array = ModeData.get_value("bot_aim", "turn_most", [6.5, 8.5, 10.5, 12.5])
static var FLICK: Array = ModeData.get_value("bot_aim", "flick", [.4, .28, .18, .12])
static var NOISE: Array = ModeData.get_value("bot_aim", "noise", [.06, .04, .027, .019])
static var TRACK: Array = ModeData.get_value("bot_aim", "track", [.3, .5, .68, .8])
static var TRIGGER: Array = ModeData.get_value("bot_aim", "trigger", [1.8, 1.4, 1.15, 1.0])
static var RECOIL: Array = ModeData.get_value("bot_aim", "recoil", [.3, .5, .7, .82])
static var BURST: Array = ModeData.get_value("bot_aim", "burst", [2, 3, 4, 5])
static var HEAD: Array = ModeData.get_value("bot_aim", "head", [.6, .66, .72, .76])
static var MOVE_NOISE: float = ModeData.get_value("bot_aim", "move_noise", .3)
static var TARGET_NOISE: float = ModeData.get_value("bot_aim", "target_noise", .22)
static var FAR_NOISE: float = ModeData.get_value("bot_aim", "far_noise", 1.0)
static var SPRAY: float = ModeData.get_value("bot_aim", "spray", .18)
static var REST: Array = ModeData.get_value("bot_aim", "rest", [.22, .38])
static var NOTICE_TURN: float = ModeData.get_value("bot_aim", "notice_turn", .14)
static var NOTICE_FAR: float = ModeData.get_value("bot_aim", "notice_far", .007)
static var MEMORY: float = ModeData.get_value("bot_aim", "memory", 1.5)
## Half a body's width to a shot's centre line (Modes.player_in_line).
const BODY := GameState.PLAYER_RADIUS + .07
## A player's height standing and crouched (Modes.player_in_line).
const TALL := 1.08
const CROUCHED := .8
## Guns that keep firing while the trigger is held: they go in bursts.
const AUTOMATIC := ["SMG", "RIFLE", "MACHINE GUN", "SPRAYER"]
## Under this far an automatic gun sprays (no bursts), and further a pistol
## taps PISTOL_TAP seconds apart at the least (less 0.04 a skill step).
static var SPRAY_INSIDE: float = ModeData.get_value("bot_aim", "spray_inside", 6.0)
static var PISTOL_TAP: float = ModeData.get_value("bot_aim", "pistol_tap", .34)

## 0 EASY .. 3 HOG WILD.
var skill := 1
## The slot aimed at (-1 none) and when each foe was last seen (by slot).
var target := -1
var seen_at := {}
## When the hand starts to move onto the foe, and the first shot may go.
var ready_at := 0.0
## The crosshair's speed: turning (radians a second) and up and down (slope a
## second).
var turn_speed := 0.0
var lift_speed := 0.0
## Where the hand means to aim, off the mark: sideways (radians) and up
## (slope); re-picked at drift_until.
var drift := Vector2.ZERO
var drift_until := 0.0
## The foe's sideways motion across the view as the bot judges it (radians a
## second, eased).
var sweep := 0.0
var clock_was := -1.0
## The burst under way: shots fired, resting until, the gun and its rounds at
## the last look (to see a shot go).
var burst := 0
var rest_until := 0.0
var last_shot := -99.0
var gun_was := -1
var loaded_was := -1


func _init(p_skill := 1) -> void:
	skill = clampi(p_skill, 0, 3)


## Seconds since the last call (the game's tick: 1/60 online, 1/120 local).
func _step(game: Game) -> float:
	var dt := 1.0 / 60.0
	if clock_was >= 0.0:
		dt = clampf(game.clock - clock_was, 1.0 / 480.0, .1)
	clock_was = game.clock
	return dt


## A foe has come into view (`off`: radians off the middle of the view).
func notice(game: Game, p: Player, q: Player, rng: RandomNumberGenerator) -> void:
	var dx := q.x - p.x
	var dy := q.y - p.y
	var d := sqrt(dx * dx + dy * dy)
	var turn := Enemy.angle_delta(atan2(dy, dx), p.angle)
	var off := absf(turn)
	var react: float = REACTION[skill]
	react *= rng.randf_range(.8, 1.35)
	react += off * NOTICE_TURN + d * NOTICE_FAR
	var last: float = seen_at.get(q.slot, -99.0)
	var again := game.clock - last < MEMORY
	if again:
		react *= .35
	if target != q.slot or not again:
		# A new foe (or one long gone): the hand comes on it from where it is.
		sweep = 0.0
		burst = 0
		# The first fling lands short more often than long, by a share of the
		# turn it takes.
		var miss: float = FLICK[skill]
		drift.x = -signf(turn) * off * miss * rng.randf_range(-.5, 1.0)
		drift.y = rng.randf_range(-1.0, 1.0) * miss * .08
		drift_until = game.clock + react + rng.randf_range(.12, .26)
	target = q.slot
	ready_at = game.clock + react
	seen_at[q.slot] = game.clock


## The foe is still in view (kept for the next notice).
func still_seen(game: Game, q: Player) -> void:
	seen_at[q.slot] = game.clock


## No foe: the hand eases off.
func rest(game: Game) -> void:
	var dt := _step(game)
	turn_speed *= exp(-10.0 * dt)
	lift_speed *= exp(-10.0 * dt)
	if game.clock - last_shot > .35:
		burst = 0


## One tick on foe `q`: the turn and look into `c`. True when the bot believes
## its crosshair is on the foe (where it means to aim) and may fire now.
func aim(game: Game, p: Player, q: Player, c: Game.Controls, rng: RandomNumberGenerator) -> bool:
	var dt := _step(game)
	_count_shots(game, p, rng)
	var dx := q.x - p.x
	var dy := q.y - p.y
	var d := maxf(.4, sqrt(dx * dx + dy * dy))
	var bearing := atan2(dy, dx)
	# The foe's motion across the view (from both bodies' speeds), judged with
	# a little lag.
	var across := (dx * (q.vy - p.vy) - dy * (q.vx - p.vx)) / (d * d)
	sweep = lerpf(sweep, across, minf(1.0, dt * 9.0))
	var own := Vector2(p.vx, p.vy).length()
	var sideways := absf(across) * d
	var wild: float = NOISE[skill]
	wild *= 1.0 + own * MOVE_NOISE + sideways * TARGET_NOISE + d / 25.0 * FAR_NOISE
	wild *= 1.0 + burst * SPRAY * (1.0 - _of(RECOIL, skill))
	if game.clock >= drift_until:
		drift = Vector2(_gauss(rng) * wild, _gauss(rng) * wild * .45)
		drift_until = game.clock + rng.randf_range(.12, .3)
	var feet: float = game.world.stand(q) + q.air
	var tall := CROUCHED if q.crouched else TALL
	var mark: float = feet + tall * _of(HEAD, skill)
	var slope_now := p.pitch / View.base_focal
	var slope_goal := (mark - p.eye) / d + drift.y
	if game.clock < ready_at:
		# Not noticed yet: the hand eases off where it was.
		turn_speed *= exp(-10.0 * dt)
		lift_speed *= exp(-10.0 * dt)
		c.turn = turn_speed * dt
		c.look = 0.0
		return false
	var w: float = SPRING[skill]
	var z: float = DAMPING[skill]
	var off := Enemy.angle_delta(bearing + drift.x, p.angle)
	var push := w * w * off + 2.0 * z * w * (sweep * _of(TRACK, skill) - turn_speed)
	var most: float = TURN_MOST[skill]
	turn_speed = clampf(turn_speed + push * dt, -most, most)
	c.turn = turn_speed * dt
	var lift_off := slope_goal - slope_now
	var lift_push := w * w * lift_off - 2.0 * z * w * lift_speed
	lift_speed = clampf(lift_speed + lift_push * dt, -3.0, 3.0)
	c.look = clampf(lift_speed * dt * View.base_focal, -6.0, 6.0)
	# On target as it believes: the crosshair (after this turn) inside the cone
	# round where it means to aim.
	var left := absf(Enemy.angle_delta(bearing + drift.x, p.angle + c.turn))
	var cone := atan(BODY / d) * _of(TRIGGER, skill)
	return left < cone and game.clock >= rest_until


## Whether the gun in hand may fire now in the burst (automatic guns rest
## between bursts at range; everything else as fast as it goes).
func burst_allows(game: Game, p: Player, d: float, rng: RandomNumberGenerator) -> bool:
	if game.clock < rest_until:
		return false
	var kind := TacticalShop.kind_of(p.armory.active)
	if kind == "PISTOL" and d > SPRAY_INSIDE:
		# Taps at range, the climb let settle between (a better player
		# taps faster).
		return game.clock - last_shot >= PISTOL_TAP - skill * .04
	if not AUTOMATIC.has(kind) or d < SPRAY_INSIDE:
		return true
	var most: int = BURST[skill]
	if d > 16.0:
		most = maxi(1, most - 2)
	if burst >= most:
		var pause: float = rng.randf_range(_of(REST, 0), _of(REST, 1))
		rest_until = game.clock + pause
		burst = 0
		return false
	return true


## Whether it is resting between bursts.
func resting(game: Game) -> bool:
	return game.clock < rest_until


## A shot went (its rounds dropped): the burst grows and the gun's kick throws
## the hand a little.
func _count_shots(game: Game, p: Player, rng: RandomNumberGenerator) -> void:
	var a: Weapons.Armory = p.armory
	var loaded: int = a.loaded[a.active]
	if a.active == gun_was and loaded < loaded_was:
		burst += 1
		last_shot = game.clock
		var loose: float = 1.0 - _of(RECOIL, skill)
		turn_speed += rng.randf_range(-1.0, 1.0) * .9 * loose
		lift_speed += rng.randf_range(0.0, 1.0) * .25 * loose
	elif game.clock - last_shot > .35:
		burst = 0
	gun_was = a.active
	loaded_was = loaded


## A normal die, about -1..1 for most throws (the bot's own dice).
static func _gauss(rng: RandomNumberGenerator) -> float:
	return (rng.randf() + rng.randf() + rng.randf() - 1.5) * 2.0


## A number of a tuning row (by skill, or REST's two ends).
static func _of(table: Array, i: int) -> float:
	var value: float = table[clampi(i, 0, table.size() - 1)]
	return value
