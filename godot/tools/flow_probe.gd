## What one chapter attempt felt like, tick by tick (tools/flow_report.gd
## plays it; pass 15 audit's measures, kept as a tool). Made at the attempt's
## start, stepped after every tick, written into the attempt's row at its end.
##
## "Hot": the bot has a target, was hurt this tick or fired in the last .8 s.
## A fight is hot stretches joined until 6 s of quiet. Alive at once: the
## alerted hostiles within 14 cells, sampled at 4 Hz while hot. Unseen damage:
## a blow whose damage_feedback heading is more than 45 degrees off the view's
## middle. Dry: every gun the bot owns is out of rounds (it fights with the
## crowbar or the blade, or has nothing). Per kill: the kind, the gun, the
## player's hit ticks on it and shots while it was the target, seconds from
## its first hit and from first being targeted, its health.
extends RefCounted

const STEP := 1.0 / 60.0
## Half the horizontal view (90 degrees across by default).
const HALF_VIEW := deg_to_rad(45.0)
## Quiet that ends a fight, and the alerted hands' reach that counts.
const FIGHT_GAP := 6.0
const NEAR := 14.0

var g: Game
var pilot: Object
var start := 0.0
var ticks := 0
var kills_was := 0
var shots := {}
var kills_by := {}
var taken := 0.0
var cause := ""
var fighting := ""
var hurt_tick := false
var hurt_amount := 0.0
var shot_tick := 0
var last_shot := -99.0
var bosses: Array = []
var hit_at := {}
## per enemy uid: {first_target, first_hit, hits, shots}
var per := {}
var kills_rows: Array = []
var picked := {}
var progress: Array = []
var pickups_start := {}
var boss_began := -1.0
# Seconds of each kind.
var t_fight := 0.0
var t_walk := 0.0
var t_idle := 0.0
var t_dry := 0.0
var t_low := 0.0
var t_melee := 0.0
var first_fight := -1.0
var last_fight := 0.0
var longest_calm := 0.0
var last_pos := Vector2.ZERO
var fights: Array = []
var fight_on := false
var fight_start := 0.0
var fight_kills0 := 0
var fight_taken0 := 0.0
var fight_peak := 0
var fight_foes := {}
## Samples while hot: 0 alerted near, 1, 2, 3, 4, 5, 6+.
var alive_hist := [0, 0, 0, 0, 0, 0, 0]
var unseen := 0.0
var seen_dmg := 0.0
var nosrc_dmg := 0.0
var hp_was := {}
var music_on := 0.0
var music_flips := 0
var music_was := false
var held := 0.0
var slow := 0.0
## The director's beats (features/director.gd), when it is there: seconds in
## each phase, the peaks begun and the hands they woke.
var phase_secs := {}
var peaks := 0
var peak_hands := 0
## Each peak: [s into the attempt, hands, why, s it lasted]; hands held at the start.
var peak_rows: Array = []
var held_start := -1
var _phase_was := ""
var _links: Array = []


func _init(game: Game, p_pilot: Object) -> void:
	g = game
	pilot = p_pilot
	start = g.clock
	kills_was = g.kills
	last_pos = Vector2(g.player.x, g.player.y)
	pickups_start = count_pickups(g)
	_link(g.events.shot_fired, _on_shot)
	_link(g.events.enemy_killed, _on_kill)
	_link(g.events.player_hurt, _on_hurt)
	_link(g.events.boss_intro, _on_intro)
	_link(g.events.boss_down, _on_down)
	_link(g.events.pickup_taken, _on_pick)
	_link(g.events.station_done, _on_station)


func _link(sig: Signal, call: Callable) -> void:
	sig.connect(call)
	_links.append([sig, call])


func unlink() -> void:
	for pair: Array in _links:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])
	_links.clear()


func _on_shot(gun: int) -> void:
	var name := str(Weapons.NAMES[gun])
	shots[name] = int(shots.get(name, 0)) + 1
	shot_tick += 1
	last_shot = g.clock


func _on_kill(e: Enemy) -> void:
	var name := str(Weapons.NAMES[g.armory.active])
	kills_by[name] = int(kills_by.get(name, 0)) + 1
	var rec: Dictionary = per.get(e.uid, {})
	if rec.is_empty() or not e.hostile:
		return
	kills_rows.append(
		[
			e.kind,
			name,
			int(rec.get("hits", 0)),
			int(rec.get("shots", 0)),
			snappedf(g.clock - float(rec.get("first_hit", g.clock)), .1),
			snappedf(g.clock - float(rec.get("first_target", g.clock)), .1),
			roundi(e.max_hp)
		]
	)
	per.erase(e.uid)


func _on_hurt(amount: float, why: String) -> void:
	taken += amount
	cause = why
	hurt_tick = true
	hurt_amount += amount


func _on_intro(e: Enemy) -> void:
	fighting = e.kind
	if boss_began < 0.0:
		boss_began = g.clock


func _on_down(e: Enemy, _secs: float) -> void:
	var since: float = hit_at.get(e.kind, g.clock)
	bosses.append([e.kind, snappedf(g.clock - since, .1)])
	fighting = ""
	boss_began = -1.0
	progress.append([snappedf(g.clock - start, .1), "boss"])


func _on_pick(name: String) -> void:
	var c := category(name)
	picked[c] = int(picked.get(c, 0)) + 1
	if c == "key":
		progress.append([snappedf(g.clock - start, .1), "key"])


func _on_station(id: String) -> void:
	progress.append([snappedf(g.clock - start, .1), "station:" + id])


static func category(name: String) -> String:
	if name.begins_with("scrap_"):
		return "scrap"
	if Weapons.NAMES.has(name):
		return "gun"
	if HUD.ITEMS.has(name):
		return "food"
	if GameState.AMMO.has(name):
		return "ammo"
	if name.contains("key"):
		return "key"
	return "other"


static func count_pickups(game: Game) -> Dictionary:
	var by := {}
	for entry: Array in game.pickups:
		var c := category(str(entry[0]))
		by[c] = int(by.get(c, 0)) + 1
	return by


## Before the tick: clears what a tick gathers, times the bosses' fights.
func before() -> void:
	ticks += 1
	hurt_tick = false
	hurt_amount = 0.0
	shot_tick = 0
	if ticks % 15 == 0:
		for e: Enemy in g.enemies:
			if e.alive and not hit_at.has(e.kind) and BossKit.is_boss(e) and e.hp < e.max_hp:
				hit_at[e.kind] = g.clock
				fighting = e.kind
				if boss_began < 0.0:
					boss_began = g.clock


## Every gun the player owns out of rounds (melee and endless left out).
static func dry(game: Game) -> bool:
	var a := game.armory
	var any := false
	for slot in Weapons.COUNT:
		if not a.owned[slot] or Weapons.MELEE.has(slot):
			continue
		if slot < Weapons.MAX_RESERVE.size() and Weapons.MAX_RESERVE[slot] <= 0:
			return false
		any = true
		if a.loaded[slot] + a.reserve[slot] > 0:
			return false
	return any


## After the tick.
func after() -> void:
	var now := g.clock - start
	var fm: Object = g.features.get("fight_music")
	if fm != null:
		var on: bool = fm.get("fighting")
		if on:
			music_on += STEP
		if on != music_was:
			music_flips += 1
			music_was = on
	if g.hitstop > 0.0 or g.boss_hold > 0.0:
		held += STEP
	if g.slowmo > 0.0:
		slow += STEP
	var director: Object = g.features.get("director")
	if director != null and bool(director.get("on")):
		var phase := str(director.get("phase"))
		phase_secs[phase] = float(phase_secs.get(phase, 0.0)) + STEP
		if held_start < 0:
			held_start = director.get("held").size()
		if phase == "peak" and _phase_was != "peak":
			peaks += 1
			peak_hands += int(director.get("peak_size"))
			peak_rows.append(
				[snappedf(now, .1), director.get("peak_size"), director.get("peak_why"), 0.0]
			)
		elif phase != "peak" and _phase_was == "peak" and not peak_rows.is_empty():
			var last: Array = peak_rows[peak_rows.size() - 1]
			last[3] = snappedf(now - float(last[0]), .1)
		_phase_was = phase
	var p := g.player
	var pos := Vector2(p.x, p.y)
	var moved := pos.distance_to(last_pos) > .008
	last_pos = pos
	var foe: Enemy = pilot.get("foe")
	var hot: bool = foe != null or hurt_tick or g.clock - last_shot < .8
	if foe != null:
		var rec: Dictionary = per.get(foe.uid, {})
		if rec.is_empty():
			rec = {"first_target": g.clock}
			per[foe.uid] = rec
		rec["shots"] = int(rec.get("shots", 0)) + shot_tick
		fight_foes[foe.uid] = true
	_hits()
	if dry(g):
		t_dry += STEP
	if Weapons.MELEE.has(g.armory.active) and hot:
		t_melee += STEP
	if p.health < 30:
		t_low += STEP
	if hurt_tick:
		var fb: Variant = g.damage_feedback
		if fb == null or fb[0] == null:
			nosrc_dmg += hurt_amount
		else:
			var heading: float = fb[0]
			var off := absf(fposmod(heading - p.angle + PI, TAU) - PI)
			if off > HALF_VIEW:
				unseen += hurt_amount
			else:
				seen_dmg += hurt_amount
	if ticks % 15 == 0 and hot:
		var alive_now := 0
		for e: Enemy in g.enemies:
			if not (e.alive and e.hostile and (e.alerted or e.player_seen)):
				continue
			if Vector2(e.x - p.x, e.y - p.y).length() < NEAR:
				alive_now += 1
		alive_hist[mini(6, alive_now)] += 1
		fight_peak = maxi(fight_peak, alive_now)
	if hot:
		t_fight += STEP
		if first_fight < 0.0:
			first_fight = now
		longest_calm = maxf(longest_calm, now - last_fight)
		last_fight = now
		if not fight_on:
			fight_on = true
			fight_start = now
			fight_kills0 = g.kills
			fight_taken0 = taken
			fight_peak = 0
			fight_foes = {}
	else:
		if fight_on and now - last_fight > FIGHT_GAP:
			_end_fight()
		if moved:
			t_walk += STEP
		else:
			t_idle += STEP


## Hit ticks: a hostile's health went down while the player had fired lately.
func _hits() -> void:
	if g.clock - last_shot < .6:
		for e: Enemy in g.enemies:
			if not e.hostile:
				continue
			var was: float = hp_was.get(e.uid, e.max_hp)
			if e.hp < was - .01:
				var rec: Dictionary = per.get(e.uid, {})
				if rec.is_empty():
					rec = {"first_target": g.clock}
					per[e.uid] = rec
				if not rec.has("first_hit"):
					rec["first_hit"] = g.clock
				rec["hits"] = int(rec.get("hits", 0)) + 1
			hp_was[e.uid] = e.hp
	elif ticks % 6 == 0:
		for e: Enemy in g.enemies:
			if e.hostile:
				hp_was[e.uid] = e.hp


func _end_fight() -> void:
	fight_on = false
	fights.append(
		[
			snappedf(fight_start, .1),
			snappedf(last_fight - fight_start, .1),
			g.kills - fight_kills0,
			fight_peak,
			roundi(taken - fight_taken0),
			fight_foes.size()
		]
	)


## The attempt's numbers into `row` ("clear", "death" or "timeout").
func finish(row: Dictionary, outcome: String) -> void:
	unlink()
	if fight_on:
		_end_fight()
	var p := g.player
	var secs := g.clock - start
	row["outcome"] = outcome
	row["secs"] = snappedf(secs, .1)
	row["x"] = snappedf(p.x, .1)
	row["y"] = snappedf(p.y, .1)
	var names: PackedStringArray = g.level.districts
	row["district"] = names[g.district] if g.district >= 0 and g.district < names.size() else ""
	row["cause"] = cause
	row["boss_fight"] = fighting != ""
	row["fighting"] = fighting
	var near: Array = []
	for e: Enemy in g.enemies:
		if e.alive and e.hostile and Vector2(e.x - p.x, e.y - p.y).length() < 10.0:
			if not near.has(e.kind):
				near.append(e.kind)
	row["near"] = near
	row["health"] = p.health
	row["kills"] = g.kills - kills_was
	row["taken"] = roundi(taken)
	row["eaten"] = pilot.get("eaten")
	row["shots"] = shots
	row["kills_by"] = kills_by
	row["bosses"] = bosses
	# What a death threw away: the whole attempt (the chapter from its kit),
	# the boss fight since it began (RETRY THE FIGHT), or the play since the
	# last trail marker (pass 15: BACK TO THE MARKER).
	if outcome == "death":
		var lost := secs
		var marker = g.features.get("trail_marker")
		if fighting != "" and boss_began >= 0.0:
			lost = g.clock - boss_began
		elif marker != null and float(marker.taken_at) >= 0.0:
			lost = minf(lost, g.clock - float(marker.taken_at))
		row["death_cost"] = snappedf(lost, .1)
	row["flow"] = {
		"fight": snappedf(t_fight, .1),
		"walk": snappedf(t_walk, .1),
		"idle": snappedf(t_idle, .1),
		"dry": snappedf(t_dry, .1),
		"melee_hot": snappedf(t_melee, .1),
		"low": snappedf(t_low, .1),
		"first_fight": snappedf(first_fight, .1),
		"longest_calm": snappedf(maxf(longest_calm, secs - last_fight), .1),
		"music_fight": snappedf(music_on, .1),
		"music_flips": music_flips,
		"held": snappedf(held, .1),
		"slowmo": snappedf(slow, .1),
	}
	row["fights"] = fights
	row["alive_hist"] = alive_hist
	row["dmg"] = {"unseen": roundi(unseen), "seen": roundi(seen_dmg), "nosource": roundi(nosrc_dmg)}
	row["kills_detail"] = kills_rows
	row["progress"] = progress
	row["pickups_start"] = pickups_start
	row["pickups_taken"] = picked
	row["pickups_left"] = count_pickups(g)
	if not phase_secs.is_empty():
		var by := {}
		for k: String in phase_secs:
			by[k] = snappedf(float(phase_secs[k]), .1)
		row["beats"] = {
			"phases": by,
			"peaks": peaks,
			"peak_hands": peak_hands,
			"peak_rows": peak_rows,
			"held": held_start
		}
