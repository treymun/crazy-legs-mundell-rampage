## Slow motion on a finishing shot: the kill that ends a fight (nobody else of
## the county's hands within hits.cfg [finisher] `reach` of it, and none still
## after the player further off) drops the world into a short slow motion
## (`length` real seconds at `pace`, eased in and out by game_state.gd
## slow_pace), so the body and the bits visibly fly. A boss's fall keeps its
## own (features/boss_fight.gd: the same game.slowmo, a second at SLOWMO_PACE).
##
## Pass 15: only after a fight of FIGHT_LEAST kills or more (the kills since
## the last fight ended: a lone hand met alone no longer slows the world, which
## had come to most kills when one hand came at a time), PEAK_LENGTH when the
## kill ends the fight-rhythm director's peak (features/director.gd).
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
static var FIGHT_LEAST: int = HitData.value("finisher", "fight_least", 3)
static var PEAK_LENGTH: float = HitData.value("finisher", "peak_length", .8)

## The game clock before which no finisher comes again.
var again_at := 0.0
## How many finishers this game has had (tools read it).
var count := 0
## The kills of the fight under way (the county's hands, since the last
## kill that left nobody fighting).
var fight_kills := 0


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
	if not e.hostile or BossKit.is_boss(e):
		return
	fight_kills += 1
	if not last_of_fight(game, e):
		return
	# The fight is over, slowed or not: the next begins from nothing.
	var kills := fight_kills
	fight_kills = 0
	if game.clock < again_at or not allowed(game):
		return
	if not e.alerted:
		# Taken unawares: no fight to finish.
		return
	if kills < FIGHT_LEAST:
		return
	count += 1
	again_at = game.clock + REST
	var length := PEAK_LENGTH if peak_end(game, e) else LENGTH
	game.slowmo = maxf(game.slowmo, length)
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


## Whether `e`'s death ends the director's peak: its hands all down (the
## director may already have gone to its breather on this kill).
static func peak_end(g: Game, e: Enemy) -> bool:
	var d := Director.of(g)
	if d == null:
		return false
	if d.phase == Director.BREATHER:
		var began := d.breather_until - DirectorData.at("breather_for", g.difficulty)
		return absf(began - g.clock) < 1e-4
	var index := g.enemies.find(e)
	if d.phase != Director.PEAK or not d.peak.has(index):
		return false
	for i: int in d.peak:
		var o: Enemy = g.enemies[i]
		if o != e and o.hp > 0.0:
			return false
	return true
