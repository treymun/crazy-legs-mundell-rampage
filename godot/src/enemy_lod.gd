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
var eyes := PackedFloat64Array()
var _eyes_clock := -1.0
var _eyes_players := -1
## FAR and VIEW_FAR squared, as of the last _look().
var far2 := 0.0
var view2 := 0.0
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
	look(game)
	# (Worked out in the enemy's own methods, Enemy.lod_step and _lod_calm:
	# its own fields are read there at half the cost of reading them here.)
	return e.lod_step(self, wdt, game.clock)


## This tick's players for lod_step (worked out again when the clock or the
## count of players has changed since).
func look(game: GameState) -> void:
	if game.clock != _eyes_clock or game.players.size() != _eyes_players:
		_look(game)


func _look(game: GameState) -> void:
	_eyes_clock = game.clock
	_eyes_players = game.players.size()
	far2 = FAR * FAR
	view2 = VIEW_FAR * VIEW_FAR
	eyes.resize(0)
	for q: Player in game.players:
		if q.health > 0:
			eyes.append(q.x)
			eyes.append(q.y)
			eyes.append(cos(q.angle))
			eyes.append(sin(q.angle))
