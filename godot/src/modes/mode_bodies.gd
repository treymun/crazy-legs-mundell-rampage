## The 3D bodies of the modes' people. The 3D view draws a sprite as its
## enemy's rigged model when the sprite names the enemy (View.Sprite.who); the
## 5v5 players (the outlaws as the county's hillbillies, the deputies as its
## yard deputies) and the hostages are no enemies, so each gets a stand-in
## here: an Enemy of that kind that is never in game.enemies and never ticks,
## set each frame from what it shows (place, heading, gait, height, when they
## fell) so the model stands, walks, aims and falls as they do. Only the view
## reads them; nothing carried or simulated changes. Everyone else who plays
## as Mundell (co-op partners, deathmatch and team deathmatch opponents,
## County Run partners, the player in the mirror) is his model, PLAYER_KIND,
## posed by player_pose().
class_name ModeBodies
extends RefCounted

## The model of Mundell himself (scripts/blender/actors_mundell.py).
const PLAYER_KIND := "mundell"
## How long a hit shows as the pain pose (seconds of game clock).
const PAIN_TIME := .3
## A player moving this fast (Player.motion) walks.
const WALKING := .1

## key -> Enemy stand-in, for the game `_game_id` only.
static var _stand_ins: Dictionary = {}
## key -> [up last frame (bool), when they fell (game clock)]
static var _fell: Dictionary = {}
## key -> [health last frame, when it last dropped (game clock)]
static var _hit: Dictionary = {}
static var _game_id := 0


static func _forget_other_games(game: Game) -> void:
	var id := game.get_instance_id()
	if id != _game_id:
		_game_id = id
		_stand_ins.clear()
		_fell.clear()
		_hit.clear()


## The stand-in under `key`, made (or remade for another kind) when needed.
static func stand_in(game: Game, key: String, kind: String) -> Enemy:
	_forget_other_games(game)
	var e: Enemy = _stand_ins.get(key)
	if e == null or e.kind != kind:
		# Mundell is no enemy kind: his stand-in is a coot wearing his name.
		e = Enemy.new(kind if Enemy.DEFS.has(kind) else "coot")
		e.kind = kind
		e.variant = 1.0
		_stand_ins[key] = e
	return e


## Player q's stand-in, posed as they are: `tall` the height their picture is
## drawn at (crouched lower).
static func for_player(game: Game, q: Player, kind: String, tall: float) -> Enemy:
	var e := stand_in(game, "p%d" % q.slot, kind)
	e.x = q.x
	e.y = q.y
	e.angle = q.angle
	e.gait = q.walk_phase
	e.height = tall
	e.died_at = fell_at(game, q)
	return e


## Hostage k's stand-in (TacticalScreens.hostage_place says where and which
## way; `gait` the carrier's while one walks them out).
static func for_hostage(
	game: Game, k: int, x: float, y: float, facing: float, gait: float, tall: float
) -> Enemy:
	var e := stand_in(game, "h%d" % k, "coot")
	e.x = x
	e.y = y
	e.angle = facing
	e.gait = gait
	e.height = tall
	return e


## Watch every player's health once a frame (the view's draw, every player,
## seen or not), so a fall is timed from when it happened.
static func watch(game: Game) -> void:
	_forget_other_games(game)
	for q: Player in game.players:
		var key := "p%d" % q.slot
		var hit: Array = _hit.get(key, [q.health, -1000.0])
		var before: int = hit[0]
		if q.health < before:
			hit[1] = game.clock
		hit[0] = q.health
		_hit[key] = hit
		var up := q.health > 0
		var was: Array = _fell.get(key, [])
		if was.is_empty():
			# First seen down: already lying there.
			_fell[key] = [up, -1000.0]
			continue
		var had: bool = was[0]
		if had and not up:
			was[1] = game.clock
		was[0] = up


## When player q fell (game clock; long ago when never seen falling).
static func fell_at(game: Game, q: Player) -> float:
	var was: Array = _fell.get("p%d" % q.slot, [])
	if was.is_empty():
		return game.clock - 1000.0
	var at: float = was[1]
	return at


## When player q was last hurt (game clock; long ago when never seen hurt).
static func hit_at(game: Game, q: Player) -> float:
	var hit: Array = _hit.get("p%d" % q.slot, [])
	if hit.is_empty():
		return game.clock - 1000.0
	var at: float = hit[1]
	return at


## The frame player q's model shows (View.Sprite.pose), named like a picture
## of `kind`: falling then down when out, else firing, flinching from a hit,
## aiming (scoped or just fired), walking (ActorView runs the walk on their
## gait) or standing; under half health the hurt look (bloodied, limping).
static func player_pose(game: Game, q: Player, kind: String) -> String:
	if q.health <= 0:
		var since := game.clock - fell_at(game, q)
		if since >= 0.0 and since < Enemy.DEATH_TIME:
			return "%s_die_%d" % [kind, mini(4, int(since / Enemy.DEATH_TIME * 5.0))]
		return kind + "_down"
	var look := kind + ("_hurt" if q.health < 50 else "")
	var age := q.armory.shot_age if q.armory != null else 1.0
	if age < .12:
		return look + "_fire"
	if game.clock - hit_at(game, q) < PAIN_TIME:
		return look + "_pain"
	if q.scoped or age < .7:
		return look + "_aim"
	if q.motion > WALKING and q.air == 0.0:
		return look + "_w0"
	return look + "_0"
