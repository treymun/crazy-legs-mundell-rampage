## Slow motion on a finishing shot: the kill that ends a fight (nobody else of
## the county's hands within hits.cfg [finisher] `reach` of it, and none still
## after the player further off) drops the world into a short slow motion
## (`length` real seconds at `pace`, eased in and out by game_state.gd
## slow_pace), so the body and the bits visibly fly. A boss's fall keeps its
## own (features/boss_fight.gd: the same game.slowmo, a second at SLOWMO_PACE).
##
## SLOW-MO FINISHERS turns it off (and a boss's fall's, game.gd). Alone only:
## never with another player (co-op, versus, County Run co-op, online), where
## the world's clock is everyone's, and never on a host. Play: its numbers are
## game.slowmo and the moment it may come again, both carried; no dice.
extends GameFeature

static var LENGTH: float = HitData.value("finisher", "length", .6)
static var PACE: float = HitData.value("finisher", "pace", .3)
static var REACH: float = HitData.value("finisher", "reach", 14.0)
static var REST: float = HitData.value("finisher", "rest", 6.0)

## The game clock before which no finisher comes again.
var again_at := 0.0
## How many finishers this game has had (tools read it).
var count := 0


func id() -> String:
	return "finishers"


func attach() -> void:
	game.events.enemy_killed.connect(_killed)


## Whether this game may slow down for a finishing shot at all.
static func allowed(g: Game) -> bool:
	if not g.finish_slowmo or g.host or g.players.size() != 1 or g.in_hub:
		return false
	var mode := Modes.feature(g)
	return mode == null or mode.mode == Modes.CAMPAIGN or mode.mode == Modes.COUNTY


func _killed(e: Enemy) -> void:
	if not e.hostile or BossKit.is_boss(e) or game.clock < again_at or not allowed(game):
		return
	if not e.alerted:
		# Taken unawares: no fight to finish.
		return
	if not last_of_fight(game, e):
		return
	count += 1
	again_at = game.clock + REST
	game.slowmo = maxf(game.slowmo, LENGTH)
	game.slowmo_for = game.slowmo
	game.slowmo_pace = PACE


## Whether `e`'s death leaves nobody fighting: no other of the county's hands
## alive within REACH of it, and none awake and after the player within twice that.
static func last_of_fight(g: Game, e: Enemy) -> bool:
	for o: Enemy in g.enemies:
		if o == e or not o.alive or o.dormant or not o.hostile:
			continue
		var d := Vector2(o.x - e.x, o.y - e.y).length()
		if d < REACH or (o.alerted and d < REACH * 2.0):
			return false
	return true
