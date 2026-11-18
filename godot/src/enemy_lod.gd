## The enemies' level of detail, and the tick's budget for their costliest
## questions. One per game (`game.enemy_lod`); nothing in it is carried: the
## level of detail is worked out each tick from what is (Enemy.lod_since,
## when a calm enemy last ticked, is the enemy's own and carried).
##
## - **Far and calm thinks less often.** An enemy far from every player
##   (`lod_far` cells, past the 14 it can see) with nothing going on (not
##   alerted, not hunting or searching or investigating a shot, not hurt
##   lately, not winding up, ducking, brawling, fetching, climbing or
##   fleeing; no boss) ticks only every `lod_step` seconds or so, with the
##   time saved up since its last tick (so its timers, walks and dice keep
##   their pace, in fewer, longer steps: fewer move_actor calls). Each wait
##   is a little different (by its uid and pose), so the far ones' turns
##   never fall on one tick together. The tick anything engages it (a shot heard, a player
##   seen, a friend's alarm, a hit, a player within `lod_far`, or in front of
##   one within `lod_view_far`) it is back to every tick, with what it saved.
##   Deterministic: players and enemies only, never the clock on the wall,
##   the same on every machine. `lod=false` in enemies.cfg turns it off.
## - **Cover a few spots a tick** (src/cover_search.gd): the spots tested
##   for cover by all the hands together are at most `cover_budget` a tick.
class_name EnemyLod
extends RefCounted

## enemies.cfg [all]: lod, lod_far, lod_step, lod_view_far, lod_view_angle,
## lod_hurt, cover_budget (load_tuning()).
static var ON := true
static var FAR := 20.0
static var STEP := .05
static var VIEW_FAR := 30.0
static var VIEW_COS := cos(deg_to_rad(55.0))
static var HURT := 3.0
static var COVER_BUDGET := 8

## The cover spots left this tick (CoverSearch), and for which tick.
var cover_left := 0
var cover_clock := -1.0
## The players who are up this tick: x, y, and their facing's cos and sin,
## four numbers each (worked out once a tick, for calm()).
var _eyes := PackedFloat64Array()
var _eyes_clock := -1.0
var _eyes_players := -1
## FAR and VIEW_FAR squared, as of the last _look().
var _far2 := 0.0
var _view2 := 0.0
## Ticks taken and waited this game, for the tools (not play).
var thought := 0
var waited := 0


static func _static_init() -> void:
	load_tuning()


## enemies.cfg's [all] values (EnemyTuning.load_tuning calls it again).
static func load_tuning() -> void:
	var cfg := Tuning.file(Tuning.ENEMIES)
	ON = cfg.get_value("all", "lod", true)
	FAR = cfg.get_value("all", "lod_far", 20.0)
	STEP = cfg.get_value("all", "lod_step", .05)
	VIEW_FAR = cfg.get_value("all", "lod_view_far", 30.0)
	var angle: float = cfg.get_value("all", "lod_view_angle", 55.0)
	VIEW_COS = cos(deg_to_rad(angle)) if angle > 0.0 else 2.0
	HURT = cfg.get_value("all", "lod_hurt", 3.0)
	COVER_BUDGET = cfg.get_value("all", "cover_budget", 8)


## The step to tick `e` with this tick (Game.tick): `wdt`, or all the time
## since its last tick when it has been waiting; 0 while a far, calm one
## waits. Enemy.lod_since (carried) is the clock of the tick it last took
## while calm, -1 otherwise: it changes only on the ticks it takes, so a
## waiting enemy changes nothing in a snapshot's delta.
func step(e: Enemy, wdt: float, game: GameState) -> float:
	if not (e.hp > 0.0) or e.dormant or e.brain == "bessie":
		# (Enemy.tick does nothing for these.)
		return wdt
	# While it waits only what others can change is asked again (calm()'s
	# `full` false); the rest on the tick after each of its own.
	var full := e.lod_since < 0.0 or game.clock - e.lod_since <= wdt * 1.5
	if not ON or not calm(e, game, full):
		thought += 1
		if e.lod_since < 0.0:
			return wdt
		# Engaged again: this tick, with what it saved.
		var owed := game.clock - e.lod_since
		e.lod_since = -1.0
		return owed
	thought += 1
	if e.lod_since < 0.0:
		# Calm from now: this tick it takes, then it waits.
		e.lod_since = game.clock
		return wdt
	# Between .6 and 1 of STEP, by its uid and how long it has lived (its
	# pose, which only moves when it ticks): each wait a little different,
	# so the far ones' turns never fall together for long.
	var since := game.clock - e.lod_since
	var turn := STEP * (.6 + .4 * fposmod(e.uid * .6180339887 + e.pose * 3.7, 1.0))
	if since < turn:
		thought -= 1
		waited += 1
		return 0.0
	e.lod_since = game.clock
	return since


## Whether `e` may think less often now: far from every player who is up,
## out of their sight lines' way, and nothing going on. `full` false asks
## only what others change (a player's place, an alarm, a shot heard, a hit,
## a critter's scare, the squad's calls): the rest only changes on its own
## ticks, and a far calm one cannot start a wind-up, a volley or a climb.
func calm(e: Enemy, game: GameState, full := true) -> bool:
	if game.clock != _eyes_clock or game.players.size() != _eyes_players:
		_look(game)
	# (Locals and the commonest answers first: asked for most enemies a tick.)
	var ex := e.x
	var ey := e.y
	var eyes := _eyes
	var n := eyes.size()
	var k := 0
	while k < n:
		var dx := ex - eyes[k]
		var dy := ey - eyes[k + 1]
		var d2 := dx * dx + dy * dy
		if d2 < _far2:
			return false
		if d2 < _view2 and dx * eyes[k + 2] + dy * eyes[k + 3] > VIEW_COS * sqrt(d2):
			# Out in front of them, near enough to watch it walk.
			return false
		k += 4
	if e.alerted or e.heard != null or e.retreat != null or e.held_cel != "" or e.hop > 0.0:
		return false
	var struck := e.struck_at
	if struck >= 0.0 and game.clock - struck < HURT:
		return false
	var m: Squad.Mind = e.mind
	if m != null and (m.investigate != null or m.regroup != null or m.flush_at > 0.0):
		return false
	if not full:
		return true
	if (
		e.windup > 0.0
		or e.volley != 0
		or e.stun > 0.0
		or e.recovery > 0.0
		or e.hit_flash > 0.0
		or e.flinch > 0.0
		or e.soak > 0.0
		or e.cover != null
		or e.grudge != null
		or e.fetching != null
		or e.ladder >= 0
		or e.climb_z > 0.0
		or e.disarmed_until >= 0.0
		or not e.cover_hunt.is_empty()
		or e.brain == "derby_champ"
	):
		return false
	return not (
		Enemy.BOSS_TITLES.has(e.kind)
		or (m != null and (m.search_until > 0.0 or m.kick_at > 0.0))
	)


func _look(game: GameState) -> void:
	_eyes_clock = game.clock
	_eyes_players = game.players.size()
	_far2 = FAR * FAR
	_view2 = VIEW_FAR * VIEW_FAR
	_eyes.resize(0)
	for q: Player in game.players:
		if q.health > 0:
			_eyes.append(q.x)
			_eyes.append(q.y)
			_eyes.append(cos(q.angle))
			_eyes.append(sin(q.angle))
