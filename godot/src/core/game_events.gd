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
