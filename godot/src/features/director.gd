## The fight-rhythm director (pass 15): a chapter's fights come as build-up,
## peak and breather instead of one hand at a time all chapter long.
##
## On the chapter's first tick it holds back `hold_share` of each district's
## hands (game.rng, out of every player's sight, never one anything names:
## src/director_beats.gd) and sets `extra_share` more beside them, all
## dormant. Then the beats:
##   CALM / BUILD  the level's own hands as placed (BUILD while any is on the
##                 party, CALM when none is);
##   PEAK          a station done, a key taken, a new district walked into or
##                 `build_for` seconds gone: the held hands within `peak_reach`
##                 steps of the party, out of sight, wake as one group and come
##                 (`peak_group_most` at most), with a holler; it ends when they
##                 are down (or after `peak_most` s);
##   BREATHER      `breather_for` seconds with no hand sent, and the peak's last
##                 kill leaves what the player is short of (src/drop_need.gd).
## A fight that has gone `long_fight` seconds without a `quiet_gap` holds any
## peak, and in it and in a breather the hands out past `guard_near` that hear
## a shot do not come to look (they did not see it: the squad's hearing).
## A trigger's alert wakes the held hands within its reach as well, so a set
## piece's hands all come.
##
## `intensity` (0..1) and `phase` ("calm", "build", "peak", "breather") are
## for the music, the RAMPAGE meter and the like to read (DirectorBeats is
## the director's choices; read these with `Director.intensity_of(game)` /
## `phase_of(game)`); `game.events.pace_changed` says when the phase moves.
## Off in County Run, the versus modes, the hub, the range, rematches, a
## chapter revisited and player maps; numbers in data/tuning/director.cfg.
## A simulation feature: every variable is carried online (the host decides)
## and saved in its block (an older save holds nothing: no hand held).
class_name Director
extends GameFeature

const CALM := "calm"
const BUILD := "build"
const PEAK := "peak"
const BREATHER := "breather"

## Decided on the first tick.
var started := false
var on := false
var phase := CALM
var intensity := 0.0
## Held hands (indexes in game.enemies: the list only grows in the modes it
## runs in), and those the peak under way woke.
var held: Array = []
var peak: Array = []
var peak_size := 0
## What brought the peak under way ("station", "key", "district", "time").
var peak_why := ""
var peak_began := -1.0
## The last time a hand of the peak was on the party.
var peak_hot := -1.0
var peaks_done := 0
var breather_until := 0.0
## When the build-up began (the timer that brings a peak anyway).
var build_from := 0.0
## A reason for a peak waiting: [why, from when]; [] none.
var pending: Array = []
## The fight under way: when it began (-1: none) and the last time a hand
## was on the party.
var fight_from := -1.0
var last_hot := -100.0
var engaged := 0
var scan_left := 0.0
## Districts the party has stood in, and the triggers whose alert it answered.
var districts := {}
var answered := {}
## The hands it never touches (DirectorBeats.named: by index, true), and
## those of the level's own it keeps still for a breather or a long fight
## (dormant till then, out of sight).
var keep := {}
## Kills in long fights (every `relief_every`-th leaves a pickup).
var relief_kills := 0
var hushed: Array = []
## A finished peak's hands still up (back to `held` once they give up).
var strays: Array = []


func id() -> String:
	return "director"


func attach() -> void:
	tick_with(_tick)
	game.events.station_done.connect(_progress.bind("station"))
	game.events.pickup_taken.connect(_taken)
	game.events.enemy_killed.connect(_fell)
	# After the squad's hearing (connected before it): the hands it sent to
	# look from far off stay put in a breather or a long fight.
	game.events.shot_fired.connect(_heard)
	game.events.boss_intro.connect(_boss_begins)
	game.events.boss_down.connect(func(_e: Enemy, _secs: float) -> void: _rest())


## The director of `game` while it runs (null otherwise).
static func of(game: Game) -> Director:
	var d: Director = game.features.get("director") if game != null else null
	return d if d != null and d.on else null


## How hot the fight is, 0 (calm) to 1 (a peak with a crowd on the party).
static func intensity_of(game: Game) -> float:
	var d := of(game)
	return 0.0 if d == null else d.intensity


## The beat the chapter is in ("calm" when the director does not run).
static func phase_of(game: Game) -> String:
	var d := of(game)
	return CALM if d == null else d.phase


func _runs_here() -> bool:
	if not DirectorData.ON or not Campaign.ORDER.has(game.level.id):
		return false
	if DirectorData.chapter_off(game.level.id):
		return false
	if game.in_hub or game.revisiting or BossRematch.active(game):
		return false
	var mode := Modes.mode_of(game)
	return mode == Modes.CAMPAIGN or mode == Modes.COOP


func _tick(dt: float) -> void:
	if not started:
		started = true
		on = _runs_here()
		if on:
			_start()
	if not on:
		sleep()
		return
	_answer_alerts()
	scan_left -= dt
	if scan_left > 0.0:
		return
	scan_left = DirectorData.num("scan")
	_scan()


func _start() -> void:
	var named := DirectorBeats.named(game)
	keep = named
	held = DirectorBeats.pick_holds(game, named)
	for index: int in held:
		var e: Enemy = game.enemies[index]
		_still(e)
	held.append_array(DirectorBeats.add_extras(game, held))
	build_from = game.clock
	for q: Player in game.players:
		districts[DirectorBeats.district_at(game, q.x, q.y)] = true


## A station done or a key taken: a reason for a peak.
func _progress(_what: String, why: String) -> void:
	if on and pending.is_empty():
		pending = [why, game.clock]


func _taken(name: String) -> void:
	if name.contains("key"):
		_progress(name, "key")


## A hand of the peak down: the last one leaves the breather's pickup.
func _fell(e: Enemy) -> void:
	if not on:
		return
	if phase != PEAK:
		_relief(e)
		return
	var index := game.enemies.find(e)
	if not peak.has(index):
		return
	for i: int in peak:
		if game.enemies[i].hp > 0.0:
			return
	_breathe(e.x, e.y)
	_set_intensity()
	game.events.pace_changed.emit(phase, intensity)


## A boss's fight begins: it is the boss's (its own backup comes). The peak's
## hands and the stragglers no player can see go back to the held ones, and
## the beats rest.
func _boss_begins(_e: Enemy) -> void:
	if not on:
		return
	for i: int in peak:
		if not strays.has(i):
			strays.append(i)
	peak = []
	var left: Array = []
	for i: int in strays:
		var e: Enemy = game.enemies[i]
		if e.hp <= 0.0:
			continue
		if DirectorBeats.seen(game, e):
			left.append(i)
			continue
		_still(e)
		held.append(i)
	strays = left
	_rest()


## A breather from now (a boss's fight begun or over: no crowd on a player
## who has just had one).
func _rest() -> void:
	if not on:
		return
	pending = []
	var was := phase
	phase = BREATHER
	breather_until = game.clock + DirectorData.at("breather_for", game.difficulty)
	_set_intensity()
	if phase != was:
		game.events.pace_changed.emit(phase, intensity)


## In a long fight every `relief_every`-th kill leaves what the player is
## short of (the supply where the fight is: a grinder of a fight was where
## a ROOKIE ran dry and died).
func _relief(e: Enemy) -> void:
	if not _long_fight() or game.supply_rule == 2 or not DropNeed.on(game):
		return
	relief_kills += 1
	if relief_kills % maxi(1, roundi(DirectorData.num("relief_every"))) != 0:
		return
	var want := DropNeed.wanted(game)
	if want != "":
		game.add_pickup(want, e.x - .25, e.y)


func _heard(_gun: int) -> void:
	if not on or not (phase == BREATHER or _long_fight()):
		return
	var far := DirectorData.num("guard_near")
	for e: Enemy in game.enemies:
		if e.mind == null or e.alerted or not e.alive or e.mind.investigate == null:
			continue
		if _nearest(e) > far * far:
			e.mind.investigate = null


## The squared distance from `e` to the nearest player up.
func _nearest(e: Enemy) -> float:
	var best := INF
	for q: Player in game.players:
		if q.health > 0:
			best = minf(best, (e.x - q.x) * (e.x - q.x) + (e.y - q.y) * (e.y - q.y))
	return best


func _long_fight() -> bool:
	return (
		fight_from >= 0.0
		and game.clock - fight_from > DirectorData.at("long_fight", game.difficulty)
	)


## A trigger that fired with an alert wakes the held hands in its reach too.
func _answer_alerts() -> void:
	if game.triggers_fired.size() == answered.size() or held.is_empty():
		return
	for trigger: Dictionary in game.level.triggers:
		var tid := str(trigger.get("id", ""))
		if answered.has(tid) or not game.triggers_fired.has(tid):
			continue
		answered[tid] = true
		for action: Dictionary in trigger.get("do", []):
			if action.has("alert"):
				var reach: float = action["alert"]
				_wake(DirectorBeats.within(game, held, int(reach)), false)


func _scan() -> void:
	var near := DirectorData.num("near")
	engaged = 0
	for e: Enemy in game.enemies:
		if e.alive and e.hostile and (e.alerted or e.player_seen) and _nearest(e) < near * near:
			engaged += 1
	if engaged > 0:
		last_hot = game.clock
		if fight_from < 0.0:
			fight_from = game.clock
	elif game.clock - last_hot > DirectorData.num("quiet_gap"):
		fight_from = -1.0
	for q: Player in game.players:
		if q.health <= 0:
			continue
		var d := DirectorBeats.district_at(game, q.x, q.y)
		if not districts.has(d):
			districts[d] = true
			if pending.is_empty():
				pending = ["district", game.clock + DirectorData.num("district_settle")]
	_hush(phase == BREATHER or _long_fight())
	_gather()
	var was := phase
	match phase:
		PEAK:
			if _peak_hot():
				peak_hot = game.clock
			var cold := game.clock - peak_hot > DirectorData.num("peak_cold")
			if cold or game.clock - peak_began > DirectorData.num("peak_most"):
				_breathe(NAN, NAN)
		BREATHER:
			if game.clock >= breather_until:
				phase = BUILD if engaged > 0 else CALM
				build_from = game.clock
				pending = []
		_:
			phase = BUILD if engaged > 0 else CALM
			_maybe_peak()
	_set_intensity()
	if phase != was:
		game.events.pace_changed.emit(phase, intensity)


## A peak's stragglers that have given up the hunt go back to the held ones
## the moment no player can see them (for a later peak): a hand left standing
## where its hunt ran out, in a gap or a doorway, never keeps the way shut.
func _gather() -> void:
	if strays.is_empty():
		return
	var left: Array = []
	for i: int in strays:
		var e: Enemy = game.enemies[i]
		if e.hp <= 0.0:
			continue
		if e.alerted or DirectorBeats.seen(game, e):
			left.append(i)
			continue
		_still(e)
		held.append(i)
	strays = left


## A hand kept still: dormant, and thinking every tick again when it comes
## back (a dormant hand does not tick: its level of detail's last turn would
## otherwise be owed to it all at once, Enemy.lod_step, and it would cover in
## one step the ground of all the time it was held).
func _still(e: Enemy) -> void:
	e.dormant = true
	e.lod_since = -1.0


func _rouse(e: Enemy) -> void:
	e.dormant = false
	e.lod_since = -1.0


## In a breather or a long fight the level's own hands farther off than
## `guard_near` and nearer than `hush_reach`, out of every player's sight and
## not after anyone, keep still (dormant): the player walks on into quiet. Out
## of it, each comes back where it stood as soon as no player can see the spot.
func _hush(quiet: bool) -> void:
	if quiet:
		var near := DirectorData.num("guard_near")
		var reach := DirectorData.num("hush_reach")
		for i in game.enemies.size():
			var e: Enemy = game.enemies[i]
			if not e.alive or e.alerted or not e.hostile or keep.has(i) or BossKit.is_boss(e):
				continue
			if e.heard != null or (e.mind != null and e.mind.investigate != null):
				continue
			var d := _nearest(e)
			if d <= near * near or d > reach * reach or DirectorBeats.seen(game, e):
				continue
			_still(e)
			hushed.append(i)
		return
	if hushed.is_empty():
		return
	var left: Array = []
	for i: int in hushed:
		var e: Enemy = game.enemies[i]
		if DirectorBeats.seen(game, e):
			left.append(i)
		else:
			_rouse(e)
	hushed = left


## In the build-up: a peak when there is a reason and hands to send.
func _maybe_peak() -> void:
	if held.is_empty() or _long_fight() or _boss_near():
		return
	var why := ""
	var due: float = pending[1] if not pending.is_empty() else INF
	if game.clock >= due:
		why = str(pending[0])
	elif game.clock - build_from >= DirectorData.at("build_for", game.difficulty):
		why = "time"
	if why == "":
		return
	# Not in the chapter's opening, nor straight after a breather (a station
	# or a key may come sooner).
	var soon := why == "station" or why == "key"
	var least_build := DirectorData.num("build_least") * (.5 if soon else 1.0)
	if game.clock < DirectorData.num("first_peak") or game.clock - build_from < least_build:
		return
	# A walk-in or the timer waits for a lull: the crowd comes after the
	# last fight, not on top of it.
	if not soon and game.clock - last_hot < DirectorData.num("peak_quiet"):
		return
	var p := _party_lead()
	var group := DirectorBeats.peak_group(game, held, p, peaks_done)
	var at := DirectorBeats.spots(game, p, group.size())
	group = group.slice(0, at.size())
	var least: int = (
		1 if why == "station" or why == "key" else roundi(DirectorData.num("peak_least"))
	)
	if group.size() < least:
		# Nobody near enough: the reason is spent, the timer tries again soon.
		pending = []
		if why == "time":
			build_from = game.clock - DirectorData.at("build_for", game.difficulty) + 5.0
		return
	pending = []
	peak = group
	peak_why = why
	peak_size = group.size()
	peak_began = game.clock
	peak_hot = game.clock
	peaks_done += 1
	phase = PEAK
	for k in group.size():
		var e: Enemy = game.enemies[group[k]]
		var spot: Vector2 = at[k]
		e.x = spot.x
		e.y = spot.y
		e.floor_z = (
			game.world.floor_under(spot.x, spot.y, p.floor_z + .05)
			if game.world.geo != null
			else 0.0
		)
		e.angle = atan2(p.y - spot.y, p.x - spot.x)
	_wake(group, true)


## The player a peak comes for: the first up by slot.
func _party_lead() -> Player:
	for q: Player in game.players:
		if q.health > 0:
			return q
	return game.player


## Whether a hand of the peak is up, alerted and near the party.
func _peak_hot() -> bool:
	var near := DirectorData.num("near")
	for i: int in peak:
		var e: Enemy = game.enemies[i]
		if e.alive and e.alerted and _nearest(e) < near * near:
			return true
	return false


## A boss near the party (awake or still waiting for them): its fight is its
## own, with its own backup; no peak there, nor just before it (a crowd
## brought to the boss's door is still there at RETRY THE FIGHT).
func _boss_near() -> bool:
	var reach := DirectorData.num("boss_quiet")
	for e: Enemy in game.enemies:
		if e.hp > 0.0 and Enemy.BOSS_TITLES.has(e.kind) and _nearest(e) < reach * reach:
			return true
	return false


## Held hands `group` come for the party (nearest player up).
func _wake(group: Array, holler: bool) -> void:
	if group.is_empty():
		return
	var hunt := DirectorData.num("peak_hunt")
	for index: int in group:
		held.erase(index)
		var e: Enemy = game.enemies[index]
		_rouse(e)
		var p := _target_of(e)
		e.wake(game, p.x, p.y)
		e.hunt_until = maxf(e.hunt_until, game.clock + hunt)
		e.cooldown = maxf(e.cooldown, .9)
	if not holler:
		return
	var first: Enemy = game.enemies[group[0]]
	if first.mind != null:
		Squad.bark(first, game, "help")
	var lines: Array = DirectorData.value("peak_lines", [])
	if not lines.is_empty():
		game.message(str(lines[(peaks_done - 1) % lines.size()]), 2.2)


func _target_of(e: Enemy) -> Player:
	var best: Player = game.player
	var least := INF
	for q: Player in game.players:
		if q.health > 0:
			var d := (e.x - q.x) * (e.x - q.x) + (e.y - q.y) * (e.y - q.y)
			if d < least:
				least = d
				best = q
	return best


## The peak is over: a breather, and (`x`, `y` a number) what the player is
## short of where its last hand fell.
func _breathe(x: float, y: float) -> void:
	for i: int in peak:
		if game.enemies[i].hp > 0.0 and not strays.has(i):
			strays.append(i)
	peak = []
	phase = BREATHER
	breather_until = game.clock + DirectorData.at("breather_for", game.difficulty)
	if not is_nan(x) and game.supply_rule != 2 and DropNeed.on(game):
		var want := DropNeed.wanted(game)
		if want != "":
			game.add_pickup(want, x + .25, y)


func _set_intensity() -> void:
	var full := maxf(1.0, DirectorData.num("crowd_full"))
	var crowd := clampf(engaged / full, 0.0, 1.0)
	match phase:
		PEAK:
			intensity = .7 + .3 * crowd
		BUILD:
			intensity = .2 + .5 * crowd
		BREATHER:
			var left := (
				(breather_until - game.clock)
				/ maxf(1.0, DirectorData.at("breather_for", game.difficulty))
			)
			intensity = maxf(.35 * crowd, .25 * clampf(left, 0.0, 1.0))
		_:
			intensity = 0.0


## No trail marker in the middle of a peak (features/trail_marker.gd): one is
## taken in the breather after it, so BACK TO THE MARKER never lands the
## player in the crowd.
func marker_ready() -> bool:
	return not (on and phase == PEAK)


func save() -> Dictionary:
	if not started:
		return {}
	return {
		"on": on,
		"phase": phase,
		"held": held.duplicate(),
		"peak": peak.duplicate(),
		"peak_size": peak_size,
		"peak_why": peak_why,
		"peak_began": peak_began,
		"peak_hot": peak_hot,
		"peaks_done": peaks_done,
		"breather_until": breather_until,
		"build_from": build_from,
		"districts": districts.keys(),
		"answered": answered.keys(),
		"relief_kills": relief_kills,
		"hushed": hushed.duplicate(),
		"strays": strays.duplicate(),
	}


## A save from before the director (or one it did not run in) holds nothing:
## no hand held, the beats start from a build-up. The lighter sponges of pass
## 15: a hand saved with more health than its kind now has is brought down to it.
func restore(state: Dictionary) -> void:
	for e: Enemy in game.enemies:
		if e.hp > e.max_hp and e.max_hp > 0.0 and not BossKit.is_boss(e):
			e.hp = e.max_hp
	if not state.has("on"):
		# Nothing saved: a save from before the director, or made before
		# the chapter's first tick (then it starts as a new chapter would).
		started = game.clock > 0.0
		return
	started = true
	var was_on: bool = state.get("on", false)
	on = _runs_here() and was_on
	held = _indexes(state.get("held", []))
	peak = _indexes(state.get("peak", []))
	phase = str(state.get("phase", CALM))
	if not [CALM, BUILD, PEAK, BREATHER].has(phase):
		phase = CALM
	var size: float = state.get("peak_size", 0)
	peak_size = int(size)
	peak_why = str(state.get("peak_why", ""))
	var done: float = state.get("peaks_done", 0)
	peaks_done = int(done)
	peak_began = state.get("peak_began", -1.0)
	peak_hot = state.get("peak_hot", peak_began)
	breather_until = state.get("breather_until", 0.0)
	build_from = state.get("build_from", game.clock)
	districts = {}
	for d: Variant in state.get("districts", []):
		var n: float = d
		districts[int(n)] = true
	answered = {}
	for t: Variant in state.get("answered", []):
		answered[str(t)] = true
	hushed = _indexes(state.get("hushed", []))
	strays = _indexes(state.get("strays", []))
	var relief: float = state.get("relief_kills", 0)
	relief_kills = int(relief)
	keep = DirectorBeats.named(game)
	if not on:
		held = []
		peak = []
		hushed = []
		strays = []
		phase = CALM


## Saved indexes as ints, only those of enemies there are.
func _indexes(rows: Variant) -> Array:
	var out: Array = []
	if not rows is Array:
		return out
	for row: Variant in rows:
		if typeof(row) != TYPE_INT and typeof(row) != TYPE_FLOAT:
			continue
		var n: float = row
		var i := int(n)
		if i >= 0 and i < game.enemies.size() and not out.has(i):
			out.append(i)
	return out
