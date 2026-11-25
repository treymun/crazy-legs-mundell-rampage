## What happens in play, announced in one place (`game.events`) for the
## features (src/features/), the modes, the 3D view and the tools to listen
## to, instead of each of them being written into the code that does it. A new
## feature connects here; combat, enemies and pickups never need to know it.
##
## Every Game has its own hub (a host game, a client's copy and a tool's game
## each announce their own play). Listeners are called in the order they
## connected, as Godot's signals are, so play that listens (a simulation
## feature) stays the same on every machine.
class_name GameEvents
extends RefCounted

## A level's game was made and is about to take its first tick.
signal level_started(level_id: String)
## The chapter was won (the exit, the last wave, a mode's win).
signal level_won
## An enemy died (credited to the acting player when a player's hit did it).
signal enemy_killed(enemy: Enemy)
## The acting player was hurt by `amount`; `cause` says what by.
signal player_hurt(amount: float, cause: String)
## The acting player took a pickup lying in the world.
signal pickup_taken(name: String)
## A quest station was thrown (its id).
signal station_done(station_id: String)
## The acting player's gun went off (its index in weapons.cfg).
signal shot_fired(gun: int)
## The acting player's hit landed on someone: how much, and whether it killed.
signal hit_landed(amount: float, killed: bool)
## The world stepped `dt` (slow motion included): every tick, last thing.
signal ticked(dt: float)
## A blast went off at (x, y, z); `energy` for the greys' plasma kind.
signal exploded(x: float, y: float, z: float, energy: bool)
## The acting player's gun started reloading.
signal gun_reloading(gun: int)
## A hitscan shot (a bullet, a pellet, a swing, the milk) ended at `end`:
## struck is "enemy", "thing" (a drum or scenery), "glass", "wall:<surface>"
## (wood, metal, plaster, dirt) or "air" (nothing within its range).
signal traced(end: Vector3, struck: String)
## A strong round went through a thin wall (penetration.gd): where it went in
## and came out; struck is "enemy" when it hurt someone behind, else "air".
signal pierced(entry: Vector3, exit: Vector3, struck: String)
## One of the county's hands has something to say (src/squad.gd, throttled):
## "spot", "lost", "search", "help", "flank", "cover", "brawl", "idle",
## "surprised", "hurt_bad", "regroup".
signal enemy_bark(e: Enemy, moment: String)
## Blood (or the greys' plasma) thrown from a hit body at (x, y, z), along
## (dx, dy), as much as the hit's `amount` (Gore listens: the spray, drips).
signal blood_sprayed(
	x: float, y: float, z: float, dx: float, dy: float, amount: float, plasma: bool
)
## A body was taken apart (overkill, a blast, a blade): Gore throws the chunks.
signal enemy_gibbed(enemy: Enemy)
## A body fell whole and bleeds where it lies (Gore: the pool, the trail).
signal enemy_bled_out(enemy: Enemy, plasma: bool)
## A hitscan shot struck a surface at (x, y, z) (Gore: wet walls splash).
signal wall_struck(x: float, y: float, z: float, surface: String)
## A blast shoved what lies loose within `reach` of (x, y) (Gore: chunks fly).
signal blast_shoved(x: float, y: float, reach: float, power: float)
## A breakable (features/breakables.gd) took a shot, a swing or fire that did
## not break it yet, going along (ax, ay); and one broke (both by its whole
## picture and where it stands). The moonshine stills spray from a shot pipe
## and spilled shine pools where a jug or a mash barrel broke (features/stills.gd,
## features/fire.gd).
signal prop_struck(image: String, x: float, y: float, z: float, ax: float, ay: float)
signal prop_broken(image: String, x: float, y: float, z: float)
## A boss went fightin' mad at half health (enemies.gd _enrage).
signal boss_enraged(enemy: Enemy)
## The boss fights (boss_kit.gd, features/boss_fight.gd, src/bosses/): a
## boss's fight began (its entrance), it reached a new phase (2 under half
## health, 3 under a fifth; Maw Glorb by her own), one instant's hits
## staggered it, a hit found its weak spot, and it fell `seconds` after its
## fight began (0 when it never began).
signal boss_intro(enemy: Enemy)
signal boss_phase(enemy: Enemy, phase: int)
signal boss_staggered(enemy: Enemy)
signal boss_weak_hit(enemy: Enemy)
signal boss_down(enemy: Enemy, seconds: float)
## The fight-rhythm director's beat moved (features/director.gd, pass 15):
## `phase` "calm", "build", "peak" or "breather"; `intensity` 0..1 as it is now
## (read Director.intensity_of(game) any time: it moves between phases too).
signal pace_changed(phase: String, intensity: float)

## The features' ticks (GameFeature.tick_with), in the order they were added
## (the features' own order), each run on `ticked` while its feature is
## awake. One listener of `ticked` runs them all, connected first, so a
## feature put to sleep (GameFeature.sleep(): nothing to do until something
## wakes it) costs nothing, and one woken runs in its old place again (in the
## same tick, when what woke it came earlier in that tick).
var _ticks: Array[Callable] = []
var _awake := PackedByteArray()
## Owner instance id -> the indices of its ticks.
var _ticks_of := {}
## While true (the dev console's `show ticks`), each tick's microseconds
## add up in `tick_us` by its place in the list; off, it costs one test a
## tick. Looks only: timing never changes what the ticks do.
var timing := false
## Features.with_hook's lists (hook -> the features with their own, in
## order) and the count of features they were made of (-1: none yet).
var hooks := {}
var hooks_of := -1
var tick_us := PackedInt64Array()


func _init() -> void:
	ticked.connect(_run_ticks)


## `on_tick(dt)` each tick while `owner` is awake (it starts awake).
func add_tick(owner: Object, on_tick: Callable) -> void:
	var key := owner.get_instance_id()
	var mine: PackedInt32Array = _ticks_of.get(key, PackedInt32Array())
	mine.append(_ticks.size())
	_ticks_of[key] = mine
	_ticks.append(on_tick)
	_awake.append(1)


## Puts `owner`'s ticks to sleep (false) or wakes them (true).
func set_awake(owner: Object, awake: bool) -> void:
	var mine: Variant = _ticks_of.get(owner.get_instance_id())
	if mine == null:
		return
	var on := 1 if awake else 0
	for i: int in mine:
		_awake[i] = on


func is_awake(owner: Object) -> bool:
	var mine: Variant = _ticks_of.get(owner.get_instance_id())
	if mine == null:
		return false
	for i: int in mine:
		if _awake[i] != 0:
			return true
	return false


## Every tick awake again (a snapshot or a save was put on the game: each
## feature sees for itself on its next tick whether it has work).
func wake_all() -> void:
	_awake.fill(1)


## [tick (Callable), awake] for each, in order (tools/tick_profile.gd times them).
func tick_list() -> Array:
	var out: Array = []
	for i in _ticks.size():
		out.append([_ticks[i], _awake[i] != 0])
	return out


## Lets go of every tick (Game.dispose()).
func clear_ticks() -> void:
	_ticks.clear()
	_awake.clear()
	_ticks_of.clear()
	hooks.clear()
	hooks_of = -1


func _run_ticks(dt: float) -> void:
	if timing:
		_run_timed(dt)
		return
	for i in _ticks.size():
		if _awake[i] != 0:
			_ticks[i].call(dt)


func _run_timed(dt: float) -> void:
	if tick_us.size() != _ticks.size():
		tick_us = PackedInt64Array()
		tick_us.resize(_ticks.size())
		tick_us.fill(0)
	for i in _ticks.size():
		if _awake[i] != 0:
			var t0 := Time.get_ticks_usec()
			_ticks[i].call(dt)
			tick_us[i] += Time.get_ticks_usec() - t0
