## Which boss fight is on: the boss is alive, awake and the player is in its
## arena, as far as the boss bar shows (boss_bar.gd and features/fight_music.gd
## hold the same test): within ARENA of a chapter's last boss, or in the pen at
## the top of Hickston for the sheriff and Jerry. The boss checkpoint
## (features/boss_checkpoint.gd) and the rematch (features/boss_rematch.gd)
## start from it.
class_name BossFight
extends RefCounted

const ARENA := 14.0
const PEN_Y := 10.0


## The boss whose fight it would be: the chapter's last boss, or Hickston's
## sheriff and then Jerry; null when none is awake.
static func awake(game) -> Enemy:
	for foe in [game.finale, game.boss, game.jerry]:
		if foe != null and foe.alive and foe.alerted and not foe.dormant:
			return foe
	return null


## Whether a point is in `foe`'s arena: within ARENA of a chapter's last boss;
## for Hickston's two, the box its level gives it (boss_arena: the sheriff's
## rodeo pen, Jerry's football field), or the top of the pasture.
static func in_arena_at(game, foe: Enemy, x: float, y: float) -> bool:
	if foe == game.finale:
		return Vector2(foe.x - x, foe.y - y).length() < ARENA
	var box = box_of(game, foe.kind)
	if box != null:
		return box.has_point(Vector2(x, y))
	return y < PEN_Y


## The box a kind's arena fills on its level's map (boss_arena's `box`, both
## corner cells inside), or null.
static func box_of(game, kind: String) -> Variant:
	var notes = game.level.boss_arena.get(kind, {})
	var box = notes.get("box") if notes is Dictionary else null
	if not (box is Array) or box.size() < 4:
		return null
	return Rect2(
		float(box[0]),
		float(box[1]),
		float(box[2]) - float(box[0]) + 1.0,
		float(box[3]) - float(box[1]) + 1.0
	)


## Whether a point is clear of `foe`'s arena: out of it and ARENA away.
static func clear_of(game, foe: Enemy, x: float, y: float) -> bool:
	return not in_arena_at(game, foe, x, y) and Vector2(foe.x - x, foe.y - y).length() >= ARENA


## The boss whose fight is on this moment, or null.
static func on(game) -> Enemy:
	if game.in_hub:
		return null
	var foe := awake(game)
	if foe == null or not in_arena_at(game, foe, game.player.x, game.player.y):
		return null
	return foe


## The living enemy of `kind` (a boss: there is one of each), or null.
static func of_kind(game, kind: String) -> Enemy:
	for e: Enemy in game.enemies:
		if e.kind == kind and e.hp > 0.0:
			return e
	return null
