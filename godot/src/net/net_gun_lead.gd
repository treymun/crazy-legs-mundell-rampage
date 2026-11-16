## A client's own gun drawn where its buttons have put it. The copy of the game
## only fires our gun once the host has played our input, a round trip and
## the play-out delay later; this steps our gun on from the copy with the
## inputs the host has not played into it yet, using the same sums as
## Weapons.Armory (tick, fire, start_reload, select) and nothing else: no dice,
## no hits, no shots launched, no sound. What happened on the way (a shot, a
## dry click, a reload starting, the cycle's and the reload's beats, a gun
## taken up) comes back as events for net_shot_predict.gd to show once. The
## caller puts the gun back after the frame (restore), so the copy and what it
## plays never change; only the picture (flash, kick, pose, the HUD's rounds)
## and the sound lead.
class_name NetGunLead
extends RefCounted

## The armory's fields stepped here, kept to put back after the frame.
const KEPT := [
	"active",
	"cooldown",
	"reload",
	"recoil",
	"flash",
	"switch",
	"empty",
	"shot_age",
	"last_spent",
	"holstered",
	"lower",
	"rifle_heat",
	"grinding",
	"swing_hit",
	"tnt_latched",
]


## Steps `me`'s gun through `inputs` (Game.Controls, oldest first; the first
## is our input number `first_seq`). Returns {"kept": what restore() wants,
## "events": [...]}, or {} when this gun is not led now (the world held, a
## stick of dynamite in hand, both hands on something else, out of play).
## An event: {"kind": "shot"|"dry"|"reload"|"beat"|"equip", "seq", "gun",
## "cues": [[cue, volume]...], "report" (a gun that rings round a room),
## "spent", "recoil", "shake", "message", "length"}.
static func lead(game: Game, me: Player, inputs: Array, first_seq: int) -> Dictionary:
	if not leads(game, me):
		return {}
	var arms: Weapons.Armory = me.armory
	var kept := {}
	for field: String in KEPT:
		kept[field] = arms.get(field)
	kept["loaded"] = arms.loaded
	kept["reserve"] = arms.reserve
	kept["pitch"] = me.pitch
	arms.loaded = arms.loaded.duplicate()
	arms.reserve = arms.reserve.duplicate()
	var events: Array = []
	var dt := NetSync.STEP
	var st: Game.ModeFeatureScript = game.features.get("mode")
	var held := Modes.is_tactical(game) and st != null
	var by_slot: Array = []
	if held:
		by_slot.resize(game.players.size())
	for i in inputs.size():
		var c: Game.Controls = inputs[i]
		if held and me.slot < by_slot.size():
			by_slot[me.slot] = c
			var out: Array = Modes.rules(game).hold_controls(game, st, by_slot)
			c = out[me.slot]
		if not step(me, c, dt, first_seq + i, events):
			break
	return {"kept": kept, "events": events}


## Whether `me`'s gun is led at all now: the tick would play their hands, and
## nothing but the gun is in them.
static func leads(game: Game, me: Player) -> bool:
	if me.health <= 0 or game.showing_tally or game.defeated() or game.portal_request != "":
		return false
	if Modes.holds(game) or game.hitstop > 0.0 or game.boss_hold > 0.0:
		return false
	var arms: Weapons.Armory = me.armory
	if arms.fuse > 0.0 or arms.active == Weapons.DYNAMITE:
		return false
	var carry: Game.CarryScript = game.features.get("carry")
	if carry != null and carry.held_by(me) >= 0:
		return false
	var rides: Game.VehiclesScript = game.features.get("vehicles")
	if rides != null and rides.hands_busy(me):
		return false
	return not (game.gallery != null and game.gallery.active and game.gallery.slot == me.slot)


static func restore(me: Player, kept: Dictionary) -> void:
	if kept.is_empty():
		return
	var arms: Weapons.Armory = me.armory
	for field: String in KEPT:
		arms.set(field, kept[field])
	var loaded: Array[int] = kept["loaded"]
	var reserve: Array[int] = kept["reserve"]
	arms.loaded = loaded
	arms.reserve = reserve
	var pitch: float = kept["pitch"]
	me.pitch = pitch


## One tick of game.gd `_step_hands`' gun for `me` (the actions, the gun's
## tick, then the trigger); false where it stops being led (a stick of
## dynamite taken up).
static func step(me: Player, c: Game.Controls, dt: float, seq: int, events: Array) -> bool:
	var arms: Weapons.Armory = me.armory
	if c.weapon >= 0:
		_select(arms, c.weapon, seq, events)
	if c.cycle != 0:
		for offset in range(1, Weapons.COUNT):
			var slot := posmod(arms.active + offset * c.cycle, Weapons.COUNT)
			if arms.owned[slot]:
				_select(arms, slot, seq, events)
				break
	if c.reload:
		_start_reload(arms, seq, events)
	_tick(arms, dt, seq, events)
	if arms.active == Weapons.DYNAMITE:
		return false
	var alt := c.alt_fire
	var firing: Dictionary = Weapons.FIRING[arms.active]
	if firing.has("scope"):
		alt = false  # ALT FIRE puts the scope up: not a shot
	if c.fire or alt:
		_fire(me, alt, seq, events)
	return true


static func _event(kind: String, seq: int, gun: int, cues: Array) -> Dictionary:
	return {"kind": kind, "seq": seq, "gun": gun, "cues": cues}


## Armory.select.
static func _select(arms: Weapons.Armory, slot: int, seq: int, events: Array) -> void:
	if slot == arms.active or not arms.owned[slot]:
		return
	arms.active = slot
	arms.reload = 0.0
	arms.cooldown = 0.0
	arms.flash = 0.0
	arms.recoil = 0.0
	arms.shot_age = 1.0
	arms.grinding = false
	arms.swing_hit = false
	arms.tnt_latched = false
	arms.holstered = false
	arms.switch = .23
	events.append(_event("equip", seq, slot, [["equip_" + str(Weapons.NAMES[slot]), .61]]))


## Armory.start_reload.
static func _start_reload(arms: Weapons.Armory, seq: int, events: Array) -> bool:
	var i := arms.active
	if (
		Weapons.CAPACITY[i]
		and arms.reload <= 0.0
		and arms.reserve[i]
		and arms.loaded[i] < Weapons.CAPACITY[i]
	):
		arms.reload = Weapons.RELOAD_TIME[i]
		arms.grinding = false
		events.append(_event("reload", seq, i, [[str(Weapons.OPEN_AUDIO[i]), .85]]))
		return true
	return false


## Armory.tick, less what is not led (the fuse, a swing's blow landing).
static func _tick(arms: Weapons.Armory, dt: float, seq: int, events: Array) -> void:
	var gun := arms.active
	arms.cooldown = maxf(0.0, arms.cooldown - dt)
	arms.recoil = maxf(0.0, arms.recoil - 5.2 * dt)
	arms.flash = maxf(0.0, arms.flash - dt)
	arms.switch = maxf(0.0, arms.switch - dt)
	arms.empty = maxf(0.0, arms.empty - dt)
	var age_before := arms.shot_age
	arms.shot_age += dt
	if gun in Weapons.CYCLE_GUNS and arms.reserve[gun] > 0 and arms.reload <= 0.0:
		var span: float = Weapons.FIRE_TIME[gun]
		var hold: float = Weapons.KICK_HOLD[gun]
		if age_before < span and span > hold:
			var was: float = (age_before - hold) / (span - hold)
			var now: float = (arms.shot_age - hold) / (span - hold)
			var cycle_cues: Array = Weapons.RELOAD_AUDIO[gun]
			var cycle_beats: Array = Weapons.RELOAD_BEATS[gun]
			for k in 3:
				if was < cycle_beats[k] and now >= cycle_beats[k]:
					events.append(_event("beat", seq, gun, [[str(cycle_cues[k]), .78]]))
	arms.rifle_heat = maxf(0.0, arms.rifle_heat - dt * 1.8)
	arms.lower = maxf(0.0, minf(1.0, arms.lower + dt * (5.5 if arms.holstered else -5.5)))
	if arms.reload > 0.0:
		var reload_time: float = Weapons.RELOAD_TIME[gun]
		var before: float = 1.0 - arms.reload / reload_time
		arms.reload -= dt
		var progress: float = 1.0 - arms.reload / reload_time
		var cues: Array = Weapons.RELOAD_AUDIO.get(gun, ["eject", "load", "close"])
		var beats: Array = Weapons.RELOAD_BEATS[gun]
		for k in 3:
			if before < beats[k] and progress >= beats[k]:
				events.append(_event("beat", seq, gun, [[str(cues[k]), .78]]))
		if arms.reload <= 0.0:
			var cap: int = Weapons.CAPACITY[gun]
			var count: int = mini(cap - arms.loaded[gun], arms.reserve[gun])
			arms.loaded[gun] += count
			arms.reserve[gun] -= count
			arms.reload = 0.0


## Armory.fire, less its hits: the gun's state, the rounds, and an event.
static func _fire(me: Player, both: bool, seq: int, events: Array) -> void:
	var arms: Weapons.Armory = me.armory
	var i := arms.active
	if arms.holstered:
		arms.holstered = false
		arms.switch = .20
		return
	if arms.cooldown or arms.reload or arms.switch or me.health <= 0:
		return
	var grind := i == Weapons.RIPSAW and both
	var pool := Weapons.pool_fed(i)
	if (
		((Weapons.CAPACITY[i] and not arms.loaded[i]) or (pool and not arms.reserve[i]))
		and not grind
	):
		var started := not pool and arms.auto_reload and _start_reload(arms, seq, events)
		if not started and arms.empty == 0.0:
			arms.empty = .34
			var dry := _event("dry", seq, i, [["dry_" + str(Weapons.NAMES[i]), 1.0]])
			dry["message"] = "DRY AS A BONE."
			dry["length"] = .7
			events.append(dry)
		return
	var pair: bool = (
		both
		and (
			(i == Weapons.SHOTGUN and arms.loaded[i] == 2)
			or (i == Weapons.RIVETER and arms.reserve[i] >= 2)
		)
	)
	var spent := 0 if (grind or i in [Weapons.CROWBAR, Weapons.SLING]) else (2 if pair else 1)
	if grind:
		arms.cooldown = .135
	elif i == Weapons.SHOTGUN and spent == 1 and arms.loaded[i] == 2:
		arms.cooldown = .26
	else:
		arms.cooldown = Weapons.FIRE_TIME[i] + (.18 if spent == 2 else 0.0)
	arms.recoil = Weapons.RECOIL[i] + (.19 if spent == 2 else 0.0)
	arms.flash = (.10 if spent == 2 else .072) if i in Weapons.MUZZLE_GUNS else 0.0
	arms.grinding = grind
	arms.last_spent = spent
	arms.shot_age = 0.0
	if pool:
		arms.reserve[i] -= spent
	else:
		arms.loaded[i] -= spent
	var how: Dictionary = Weapons.FIRING[i]
	if how.has("climb") and str(how.get("fire", "")) == "hitscan":
		var climb: float = how["climb"]
		var climb_heat: float = how.get("climb_heat", 0.0)
		var heat_gain: float = how.get("heat_gain", 0.0)
		me.pitch = minf(53.0, me.pitch + climb + arms.rifle_heat * climb_heat)
		arms.rifle_heat = minf(1.0, arms.rifle_heat + heat_gain)
	if grind:
		return  # the saw's grind: its own loop (set_tool), nothing to show once
	var cue := str(Weapons.NAMES[i])
	if i == Weapons.SHOTGUN and spent == 2:
		cue = "shotgun_both"
	elif i == Weapons.RIVETER and spent == 2:
		cue = "riveter_pair"
	var shot := _event("shot", seq, i, [[cue, 1.0]])
	shot["report"] = i in Weapons.MUZZLE_GUNS and i != Weapons.ARMGUN
	shot["spent"] = spent
	shot["recoil"] = arms.recoil
	var shake_by: float = Weapons.SHAKE.get(i, 0.0)
	shot["shake"] = shake_by * maxf(1, spent)
	events.append(shot)
