## What the sheriff, Jerry, Rudy and the foreman share beyond BossMoves: their
## arena's hazards (features/boss_arena.gd), a wind-up of their own (an attack
## the generic brain does not know: the boss stands in its "aim" pose, the
## framework's pulse on it, then act() runs) and a few measures of a hit for
## their weak spots. State lives on the enemy (set_meta), as BossMoves asks.
extends BossMoves

## How much longer it shrugs off another stagger once it is plum desperate:
## the last of its health goes at the player, not on its heels.
const DESPERATE_REST := 1.7


func stagger_rest(e: Enemy) -> float:
	return super(e) * (DESPERATE_REST if e.boss_phase >= 3 else 1.0)


## Plum desperate, it hunkers down: a gun's hit anywhere but its weak spot
## counts DESPERATE_GUARD (blasts, fire and its own hazards count whole).
const DESPERATE_GUARD := .7


func guarded(e: Enemy, times: float) -> float:
	if times > 1.0 or e.boss_phase < 3:
		return times
	return times * DESPERATE_GUARD


## The arena feature, or null.
func arena(game):
	return game.features.get("boss_arena")


## Its fight is on: alive, awake, not held back, the world not frozen.
func fighting(e: Enemy, game) -> bool:
	return e.alive and e.alerted and not e.dormant and game.boss_hold <= 0.0


## How far round from its facing the shot came (0 in its face, PI at its back).
func off_facing(e: Enemy, from: Vector2) -> float:
	return absf(Enemy.angle_delta(atan2(from.y - e.y, from.x - e.x), e.angle))


## Where on its body a hit struck, 0 at its feet and 1 at the top of its head.
func body_height(e: Enemy, game, hit: Vector3) -> float:
	var feet: float = game.world.elevation(e.x, e.y) + e.z
	return (hit.z - feet) / maxf(.1, e.height * e.variant)


## The name of its own wind-up under way ("" for none).
func own(e: Enemy) -> String:
	return String(e.get_meta("own", ""))


## Start a wind-up of its own: `secs` in its aim pose, then act(e, game, name).
## `mark` is where the shared ring closes in (null: none).
func begin_own(e: Enemy, game, name: String, secs: float, mark = null) -> void:
	e.set_meta("own", name)
	e.windup = secs
	e.aim_mark = mark
	var p = game.player
	e.angle = atan2(p.y - e.y, p.x - e.x)
	e.face_left = cos(e.angle) < -.24


## Its own wind-up's tick: true while it holds the boss (the brain waits). A
## stun or a stagger (which zeroes the wind-up) calls it off.
func run_own(e: Enemy, game, dt: float) -> bool:
	var name := own(e)
	if name == "":
		return false
	if e.stun > 0.0 or e.windup <= 0.0:
		if e.windup <= 0.0 and e.stun <= 0.0:
			e.set_meta("own", "")
			e.aim_mark = null
			act(e, game, name)
			return true
		e.set_meta("own", "")
		e.windup = 0.0
		e.aim_mark = null
		return false
	e.windup = maxf(0.0, e.windup - dt)
	return true


## What its own wind-up does when it runs out (each boss its own).
func act(_e: Enemy, _game, _name: String) -> void:
	pass


## Ready for something of its own: not winding up, recovering or stunned.
func ready(e: Enemy) -> bool:
	return e.windup <= 0.0 and e.recovery <= .05 and e.stun <= 0.0 and own(e) == ""


## A timer kept on the boss: true once the clock passes it (unset: never).
func due(e: Enemy, game, key: String) -> bool:
	return game.clock >= float(e.get_meta(key, INF))


## The player seen from the boss, eye to eye.
func sees_player(e: Enemy, game) -> bool:
	var p = game.player
	var eye: float = game.world.elevation(e.x, e.y) + minf(.92, e.height * .72)
	return game.world.visible(e.x, e.y, p.x, p.y, eye, p.eye)


## Say something once a fight (the meta key remembers).
func say_once(e: Enemy, game, key: String, text: String, secs := 2.4) -> void:
	if e.has_meta(key):
		return
	e.set_meta(key, true)
	game.message(text, secs)


## Lane marks along a bearing from (x, y), `length` long (a charge, a cut).
func lane_marks(game, x: float, y: float, bearing: float, length: float, width := .3) -> Array:
	var out: Array = []
	var w: LevelData = game.world
	var reach := 0.0
	while reach < length:
		var step := reach + .3
		if w.blocked(x + cos(bearing) * step, y + sin(bearing) * step, .05):
			break
		reach = step
	if reach > .5:
		out.append(
			Renderer.GroundMark.new(
				x + cos(bearing) * reach * .5,
				y + sin(bearing) * reach * .5,
				w.elevation(x, y) + .004,
				bearing,
				reach * .5,
				width,
				"mark_lane"
			)
		)
	return out
