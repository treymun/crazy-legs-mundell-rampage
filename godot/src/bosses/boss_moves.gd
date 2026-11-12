## What one boss does beyond the shared boss fight (boss_kit.gd and
## features/boss_fight.gd): its own third-phase attack, arena hazards, weak
## spot and HOG WILD-only attack. Each boss has a file in src/bosses/ that
## extends this and overrides what it needs; BossKit.moves(kind) hands back
## the one instance for a kind, so every method takes the boss (`e`) and the
## game. That instance is shared by every Game: keep a fight's own state on
## the enemy (e.set_meta) or in a feature's saved block, never in fields here.
##
## Every default does nothing, so a boss without a file of its own (or with an
## empty one) fights as before. Gameplay randomness comes from game.rng;
## anything that only looks uses its own dice (features/boss_fight.gd dice).
class_name BossMoves
extends RefCounted


## The boss's fight began (it is awake and the player is in its arena, or it
## was hurt): once a save, as its entrance starts. game.boss_intro follows.
func fight_start(_e: Enemy, _game) -> void:
	pass


## It reached a new phase: 2 at half its health (fightin' mad, Enemy._enrage),
## 3 at a fifth (plum desperate); Maw Glorb's phases are her own (2/3 and a
## third, features/mothership.gd). Called after the shared phase change (the
## message, the shake, the backup) and before game.boss_phase is announced.
## Start a third-phase attack or an arena hazard here.
func phase_changed(_e: Enemy, _game, _phase: int) -> void:
	pass


## Every tick the boss is alive, before its brain (Enemy.tick, after its
## timers count down). True: this took the whole tick and the brain is
## skipped (an attack of its own in progress); false: the brain runs as usual.
func tick(_e: Enemy, _dt: float, _game) -> bool:
	return false


## How much a player's hit counts: `hit` is where it struck (a bullet or
## pellet on the boss, a shot where it touched, a blast's middle), `from` where
## the player stood, `how` the gun's name or "blast"/"energy"/a shot's kind
## (Enemy.hurt's `how`). Over 1.0 is a weak spot (sparks and WEAK SPOT!,
## game.boss_weak_hit), under 1.0 armour. Must not roll dice: the damage it
## gives is play. Only asked for the player's own hits.
func weak_spot(_e: Enemy, _game, _hit: Vector3, _from: Vector2, _how: String) -> float:
	return 1.0


## Extra warnings while it winds up (e.windup > 0): Renderer.GroundMark and
## Renderer.Sprite, mixed; the shared ring at its aim point and the pulse on
## its sprite are already drawn.
func telegraph(_e: Enemy, _game) -> Array:
	return []


## Extra sprites showing the damage it has taken this frame (e.boss_phase
## says how bad); the shared smoke and sparks are already drawn.
func looks(_e: Enemy, _game) -> Array:
	return []


## It fell: after the shared set piece (slow motion, gibs, the loot shower),
## before game.boss_down is announced.
func dying(_e: Enemy, _game) -> void:
	pass


## How hard one instant's hits (Enemy.struck_sum) must be to stagger it, and
## how long before it can be staggered again (BossKit.STAGGER by kind).
func stagger_hit(e: Enemy) -> float:
	return float(BossKit.STAGGER.get(e.kind, BossKit.STAGGER_DEFAULT)[0])


func stagger_rest(e: Enemy) -> float:
	return float(BossKit.STAGGER.get(e.kind, BossKit.STAGGER_DEFAULT)[1])


## The HOG WILD difficulty is on: its attacks only that setting gets (the
## game is passed in, as the instance is shared by every game).
func hog_wild(game) -> bool:
	return int(game.difficulty) == 3
