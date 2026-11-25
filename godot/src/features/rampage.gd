## RAMPAGE (pass 15): kill chains fill a meter, and a full one turns Mundell
## loose for a few seconds. Numbers in hits.cfg [rampage].
##
## Each kill of a player's own (the hit that killed was his: the
## `hit_landed` with `killed` just before `enemy_killed`) fills his meter by
## `kill`, more for a head, an overkill that takes the body apart, a brawl
## finisher, a boss, and a hazard kill (`hazard_killed`: [hazard]
## `bonus_rampage`); a kill within `chain_for` of the one before adds `chain`
## for every link of the chain. The meter holds `hold` seconds after a kill,
## then drains. Full: RAMPAGE for `rampage_for` seconds (a kill in it adds
## `extend`, up to `rampage_most`), his move times `speed` (game.gd _walk) and
## his hits times `damage` (Enemy.hurt). The meter is empty again after.
##
## Looks (this machine's player only): the meter under the health on the
## status bar (HUD.rampage_meter), the view's edge burning while it lasts,
## a sting and Mundell's holler as it begins (_announce, from draw_view, so
## an online copy hears its own too), the music at its PEAK
## (features/fight_music.gd reads raging()).
##
## Alone and in co-op each player has his own; County Run too; never in the
## versus modes, the hub or the range. A simulation feature: no dice, every
## variable carried online but `_said` (this machine's: SnapCodec
## SKIP_FIELDS) and saved in its block.
class_name Rampage
extends GameFeature

static var KILL: float = HitData.value("rampage", "kill", .11)
static var HEAD: float = HitData.value("rampage", "head", .06)
static var OVERKILL: float = HitData.value("rampage", "overkill", .06)
static var FINISHER: float = HitData.value("rampage", "finisher", .12)
static var BOSS: float = HitData.value("rampage", "boss", .5)
static var CHAIN: float = HitData.value("rampage", "chain", .03)
static var CHAIN_FOR: float = HitData.value("rampage", "chain_for", 2.5)
static var CHAIN_MOST: int = HitData.value("rampage", "chain_most", 4)
static var HOLD: float = HitData.value("rampage", "hold", 3.5)
static var DRAIN: float = HitData.value("rampage", "drain", .08)
static var LENGTH: float = HitData.value("rampage", "rampage_for", 8.0)
static var EXTEND: float = HitData.value("rampage", "extend", .5)
static var MOST: float = HitData.value("rampage", "rampage_most", 14.0)
static var SPEED: float = HitData.value("rampage", "speed", 1.12)
static var DAMAGE: float = HitData.value("rampage", "damage", 1.2)
static var HAZARD: float = HitData.value("hazard", "bonus_rampage", .35)
static var WIND: float = HitData.value("finish", "wind", .15)

const RangeLayout := preload("res://src/range_layout.gd")
const VERSUS := [Modes.DEATHMATCH, Modes.TEAM, Modes.BOMB, Modes.HOSTAGE]

## Worked out on the first tick: whether it runs in this game.
var decided := false
var on := false
## By slot: the meter (0..1), the clock it holds until, the clock RAMPAGE
## runs until (0 none), when it began, the last kill and the chain's links.
var meters: Array = []
var holds: Array = []
var until: Array = []
var began: Array = []
var last_kill: Array = []
var links: Array = []
## How many RAMPAGES each slot has had this game (tools, the tally).
var count: Array = []
## The slot whose hit is killing right now (hit_landed to enemy_killed; -1).
var armed := -1
## This machine's: the RAMPAGE each slot's start was last announced for.
var _said: Array = []


func id() -> String:
	return "rampage"


func attach() -> void:
	tick_with(_tick)
	game.events.hit_landed.connect(_landed)
	game.events.enemy_killed.connect(_killed)
	game.events.hazard_killed.connect(_hazard)


## The feature in `game` while it runs (null otherwise).
static func of(game: Game) -> Rampage:
	var r: Rampage = game.features.get("rampage") if game != null else null
	return r if r != null and r.on else null


## Whether `p` is on a RAMPAGE now.
static func raging(game: Game, p: Player) -> bool:
	var r := of(game)
	return r != null and p != null and r._until(p.slot) > game.clock


## `p`'s meter (0..1; 1 throughout a RAMPAGE, running down as it ends).
static func meter_of(game: Game, p: Player) -> float:
	var r := of(game)
	if r == null or p == null:
		return 0.0
	var left := r._until(p.slot) - game.clock
	if left > 0.0:
		return clampf(left / LENGTH, 0.0, 1.0)
	return r._at(r.meters, p.slot)


## How fast `p` moves (game.gd _walk): `speed` on a RAMPAGE, else 1.
static func pace(game: Game, p: Player) -> float:
	return SPEED if raging(game, p) else 1.0


## What the acting player's hit does (Enemy.hurt, `by` null for a player's
## own): `damage` times as much on his RAMPAGE.
static func might(game: Game, by: Enemy) -> float:
	return DAMAGE if by == null and raging(game, game.player) else 1.0


func _runs_here() -> bool:
	if game.in_hub or game.level == null or game.level.id in ["hub", RangeLayout.ID]:
		return false
	return not VERSUS.has(Modes.mode_of(game))


func _tick(dt: float) -> void:
	if not decided:
		decided = true
		on = _runs_here()
	if not on:
		sleep()
		return
	for slot in meters.size():
		var left := _until(slot)
		if left > 0.0 and game.clock >= left:
			# Over: the meter starts again from nothing.
			until[slot] = 0.0
			meters[slot] = 0.0
		elif left == 0.0 and game.clock >= _at(holds, slot):
			meters[slot] = maxf(0.0, _at(meters, slot) - DRAIN * dt)


func _landed(_amount: float, killed: bool) -> void:
	if killed and on and game.player != null:
		armed = game.player.slot


func _killed(e: Enemy) -> void:
	var slot := armed
	armed = -1
	if slot < 0 or not on or not e.hostile:
		return
	_grow(slot)
	var gain := KILL
	if BossKit.is_boss(e):
		gain += BOSS
	if e.last_zone == "head":
		gain += HEAD
	if e.explosive:
		gain += OVERKILL
	if _finished(slot):
		gain += FINISHER
	var link: int = links[slot]
	link = mini(link + 1, CHAIN_MOST) if game.clock - _at(last_kill, slot) <= CHAIN_FOR else 0
	links[slot] = link
	last_kill[slot] = game.clock
	gain += CHAIN * link
	_add(slot, gain)


## A hand booted into a hazard (features/brawl.gd's bonus): its kill was
## counted as he died, this is the bonus on top.
func _hazard(_e: Enemy, _kind: String, slot: int) -> void:
	if on and slot >= 0:
		_grow(slot)
		_add(slot, HAZARD)


func _add(slot: int, gain: float) -> void:
	if _until(slot) > game.clock:
		# On a RAMPAGE already: each kill keeps it going a little longer.
		until[slot] = minf(_at(began, slot) + MOST, _until(slot) + EXTEND)
		return
	holds[slot] = game.clock + HOLD
	var full := minf(1.0, _at(meters, slot) + gain)
	meters[slot] = full
	if full >= 1.0:
		until[slot] = game.clock + LENGTH
		began[slot] = game.clock
		var times: int = count[slot]
		count[slot] = times + 1


## Whether the kill just made by `slot` was a brawl finisher landing (its
## move started a wind-up ago: features/brawl.gd last_moves).
func _finished(slot: int) -> bool:
	var brawl: Object = game.features.get("brawl")
	if brawl == null:
		return false
	var moves: Dictionary = brawl.get("last_moves")
	var last: Array = moves.get(slot, [])
	if last.size() < 2:
		return false
	var started: float = last[1]
	return absf(game.clock - started - WIND) < .05


func _grow(slot: int) -> void:
	while meters.size() <= slot:
		meters.append(0.0)
		holds.append(0.0)
		until.append(0.0)
		began.append(0.0)
		last_kill.append(-100.0)
		links.append(0)
		count.append(0)


func _at(list: Array, slot: int) -> float:
	if slot < 0 or slot >= list.size():
		return 0.0
	var n: float = list[slot]
	return n


func _until(slot: int) -> float:
	return _at(until, slot)


# ------------------------------------------------------------------- looks


## The sting and Mundell's holler as this machine's player's RAMPAGE begins
## (once each: `_said`, this machine's own), then the view's edge burning.
func draw_view(c: Canvas) -> void:
	if not on:
		return
	var p := game.local_player
	if p == null or p.health <= 0:
		return
	var slot := p.slot
	var at := _at(began, slot)
	if at > 0.0 and _until(slot) > game.clock:
		while _said.size() <= slot:
			_said.append(0.0)
		if _at(_said, slot) != at:
			_said[slot] = at
			_announce()
		if not game.map:
			RampageLooks.burn(c, game, (_until(slot) - game.clock) / LENGTH, game.clock - at)


func _announce() -> void:
	if game.sound != null:
		game.sound.play("rampage_sting", .9)
	var was := game.player
	game.focus(game.local_player)
	game.barks.say(game, "rampage", true)
	game.focus(was)


# -------------------------------------------------------------------- save


func save() -> Dictionary:
	if meters.is_empty():
		return {}
	return {
		"meters": meters.duplicate(),
		"holds": holds.duplicate(),
		"until": until.duplicate(),
		"began": began.duplicate(),
		"last_kill": last_kill.duplicate(),
		"links": links.duplicate(),
		"count": count.duplicate(),
	}


## Back from a save (numbers come back as floats); an older save has none.
func restore(state: Dictionary) -> void:
	var rows: Array = state.get("meters", [])
	meters = []
	holds = []
	until = []
	began = []
	last_kill = []
	links = []
	count = []
	_said = []
	for slot in rows.size():
		_grow(slot)
		meters[slot] = clampf(_read(state, "meters", slot, 0.0), 0.0, 1.0)
		holds[slot] = _read(state, "holds", slot, 0.0)
		until[slot] = _read(state, "until", slot, 0.0)
		began[slot] = _read(state, "began", slot, 0.0)
		last_kill[slot] = _read(state, "last_kill", slot, -100.0)
		links[slot] = roundi(_read(state, "links", slot, 0.0))
		count[slot] = roundi(_read(state, "count", slot, 0.0))


func _read(state: Dictionary, key: String, slot: int, fallback: float) -> float:
	var got: Variant = state.get(key, [])
	if not got is Array:
		return fallback
	var row: Array = got
	if slot >= row.size():
		return fallback
	var v: Variant = row[slot]
	if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
		return fallback
	var n: float = v
	return n
