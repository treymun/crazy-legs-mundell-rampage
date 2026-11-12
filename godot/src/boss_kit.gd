## The boss fight every boss shares (the eight with a `title` in enemies.cfg),
## called from enemies.gd and the game's layers; features/boss_fight.gd keeps
## what it saves and draws, and each boss's own moves are its file in
## src/bosses/ (BossMoves). Here:
##   phases       1 -> 2 at half health (Enemy._enrage), 2 -> 3 under a fifth
##                (PLUM DESPERATE); Maw Glorb's follow her own (mothership.gd).
##                Enemy.boss_phase is worked out from health, so a save needs
##                nothing new (features/boss_fight.gd restore sets it).
##   weak spots   a player's hit records where it struck (game.hit_point,
##                game.hit_from) and hurt() multiplies a boss's damage by its
##                BossMoves.weak_spot(); no dice, so play stays the same.
##   stagger      one instant's hits (Enemy.struck_sum) past STAGGER throw it
##                back a step and cancel its wind-up, then not again for a while;
##                the car and the airboat skid instead.
##   entrance     the world holds while the view comes round and its name comes
##                down (hold(), draw_intro(); started by the feature).
##   telegraphs   the pulse on its sprite while it winds up (pulse()); the ring
##                on the ground is the feature's.
class_name BossKit
extends RefCounted

## Each boss's moves, by kind (a kind with a `brain` of one of these gets
## that one's).
const MOVES := {
	"boss": preload("res://src/bosses/sheriff.gd"),
	"jerry": preload("res://src/bosses/jerry.gd"),
	"rudy": preload("res://src/bosses/rudy.gd"),
	"foreman": preload("res://src/bosses/foreman.gd"),
	"baron": preload("res://src/bosses/baron.gd"),
	"swamp_king": preload("res://src/bosses/swamp_king.gd"),
	"derby_champ": preload("res://src/bosses/boggs.gd"),
	"maw": preload("res://src/bosses/maw.gd"),
}
## Health left (of its whole) where a boss goes fightin' mad and plum desperate.
const MAD_AT := .5
const DESPERATE_AT := .2
## [damage in one instant that staggers, seconds before it can be again]: a
## load of buckshot at arm's length, a stick of dynamite at its feet or a
## bottle rocket does it; a revolver round never does.
const STAGGER := {
	"boss": [80.0, 3.5],
	"jerry": [85.0, 3.5],
	"rudy": [75.0, 3.5],
	"foreman": [80.0, 4.0],
	"baron": [85.0, 4.0],
	"swamp_king": [85.0, 4.5],
	"derby_champ": [95.0, 5.0],
	"maw": [150.0, 6.0],
}
const STAGGER_DEFAULT := [85.0, 4.0]
## How far a stagger throws a boss back (cells), and a car or a boat sideways.
const STAGGER_SHOVE := .45
const SKID := .35
## The entrance, in seconds; fire, jump or use cuts it short after SKIP_AFTER.
const INTRO := 1.6
const SKIP_AFTER := .25
## How near a boss the player is in its arena.
const ARENA := 14.0
## Seconds between WEAK SPOT! calls.
const WEAK_CALL_GAP := 3.5

static var _made := {}
## A tool driving the game (a SceneTree script: the walkthrough, the checks)
## gets no entrance even with game.lessons on, unless it asks for them
## (tools/boss_check.gd and physics_frames.gd do, to try and picture them).
static var tool_intros := false


## Whether a boss's entrance may hold this game: real play only.
static func intros_on(game) -> bool:
	if not game.lessons:
		return false
	var loop := Engine.get_main_loop()
	return tool_intros or loop == null or loop.get_script() == null


static func is_boss(e: Enemy) -> bool:
	return Enemy.BOSS_TITLES.has(e.kind)


## The one BossMoves for a kind (plain BossMoves when it has no file).
static func moves(kind: String) -> BossMoves:
	var found = _made.get(kind)
	if found == null:
		var script = MOVES.get(kind)
		if script == null and Enemy.DEFS.has(kind):
			script = MOVES.get(String(Enemy.DEFS[kind].get("brain", kind)))
		found = script.new() if script != null else BossMoves.new()
		_made[kind] = found
	return found


## Puts other moves in a kind's place (tools/boss_check.gd tries a weak spot
## this way); null goes back to its own file's.
static func set_moves(kind: String, other: BossMoves) -> void:
	if other == null:
		_made.erase(kind)
	else:
		_made[kind] = other


static func title(e: Enemy) -> String:
	return String(Enemy.BOSS_TITLES.get(e.kind, "BOSS"))


## The phase its health puts it in: 1, 2 under half, 3 under a fifth; Maw's
## by her own lines (two thirds, a third).
static func phase_of(e: Enemy) -> int:
	if e.max_hp <= 0.0:
		return 1
	var left := e.hp / e.max_hp
	if e.brain == "maw":
		return 3 if left <= ShipAliens.BARE_AT else 2 if left <= 2.0 / 3.0 else 1
	return 3 if left < DESPERATE_AT else 2 if left < MAD_AT else 1


## Whether the player is in the boss's arena (the boss bar shows, the boss
## loop plays, its entrance can start): within ARENA of it, or anywhere in
## the arena Hickston gives the sheriff and Jerry (BossFight.in_arena_at).
static func in_arena(game, e: Enemy) -> bool:
	var p = game.player
	if (
		game.level.rescue
		and (e == game.boss or e == game.jerry)
		and BossFight.in_arena_at(game, e, p.x, p.y)
	):
		return true
	return Vector2(e.x - p.x, e.y - p.y).length() < ARENA


## Enemy.tick's hook: true when the boss's own moves took the tick.
static func tick(e: Enemy, dt: float, game) -> bool:
	return moves(e.kind).tick(e, dt, game)


## How much the player's hit on a boss counts (Enemy.hurt, before the damage
## is taken): its weak_spot() at game.hit_point; 1 when the point is not known.
static func weak(e: Enemy, game, how: String) -> float:
	var hit: Vector3 = game.hit_point
	if hit == Vector3.INF:
		return 1.0
	var times := maxf(0.0, moves(e.kind).weak_spot(e, game, hit, game.hit_from, how))
	if times > 1.0:
		_weak_feedback(e, game, hit)
	return times


static func _weak_feedback(e: Enemy, game, hit: Vector3) -> void:
	_sparks(game, hit.x, hit.y, hit.z, "spark", 7, 2.6)
	# Once an instant (a load of buckshot is ten hits), then a call now and then.
	if game.clock - float(e.get_meta("weak_at", -10.0)) > .12:
		e.set_meta("weak_at", game.clock)
		game.sound_at("ricochet_tin", hit.x, hit.y, .8)
		game.boss_weak_hit.emit(e)
	if game.clock - float(e.get_meta("weak_call", -100.0)) >= WEAK_CALL_GAP:
		e.set_meta("weak_call", game.clock)
		if game.barks.enabled:
			game.callout = "WEAK SPOT!"
			game.callout_until = game.clock + 1.0


## A big hit (Enemy.hurt, after the stun it gives): stumbles back from where it
## came, its wind-up cancelled, the bar flashes. True when it staggered.
static func stagger(e: Enemy, game, from_x: float, from_y: float) -> bool:
	var m := moves(e.kind)
	if e.struck_sum < m.stagger_hit(e) or game.clock < e.stagger_ready:
		return false
	e.stagger_ready = game.clock + m.stagger_rest(e)
	e.staggered_at = game.clock
	var away := atan2(e.y - from_y, e.x - from_x)
	var floor_z: float = game.world.elevation(e.x, e.y)
	if e.brain == "derby_champ" or e.brain == "swamp_king":
		# A car or a boat does not stumble: it slews round and skids.
		var side := away + (PI / 2.0 if e.attacks % 2 else -PI / 2.0)
		game.move_actor(
			e,
			cos(away) * SKID * .5 + cos(side) * SKID,
			sin(away) * SKID * .5 + sin(side) * SKID,
			e.radius
		)
		var kind := "splash" if e.brain == "swamp_king" else "dust"
		_sparks(game, e.x, e.y, floor_z + .2, kind, 12, 1.8)
		game.sound_at("scenery_scrap", e.x, e.y, .9)
	else:
		game.move_actor(e, cos(away) * STAGGER_SHOVE, sin(away) * STAGGER_SHOVE, e.radius)
		_sparks(game, e.x, e.y, floor_z + .1, "dust", 8, 1.2)
		game.sound_at("body_thud", e.x, e.y, 1.0)
	game.sound_at("blow_grunt", e.x, e.y, .7)
	e.flinch = maxf(e.flinch, .5)
	e.stun = maxf(e.stun, .55)
	e.windup = 0.0
	e.aim_mark = null
	e.cooldown = maxf(e.cooldown, .8)
	game.shake = minf(1.0, game.shake + .25)
	game.boss_staggered.emit(e)
	return true


## Enemy.hurt's check after each hit: each phase it has newly reached, once.
static func phase_check(e: Enemy, game) -> void:
	var now := phase_of(e)
	while e.boss_phase < now:
		e.boss_phase += 1
		_new_phase(e, game, e.boss_phase)


static func _new_phase(e: Enemy, game, phase: int) -> void:
	if phase == 3 and e.brain != "maw":
		_desperate(e, game)
	var fight = game.features.get("boss_fight")
	if fight != null and phase >= 2 and game.boss_backup and e.brain != "maw":
		# Maw hollers for her own (features/mothership.gd).
		fight.backup(e, phase)
	moves(e.kind).phase_changed(e, game, phase)
	game.boss_phase.emit(e, phase)


## Under a fifth of its health: a holler, a stagger, sparks, and the last of it.
static func _desperate(e: Enemy, game) -> void:
	e.desperate_at = game.clock
	e.stun = maxf(e.stun, .7)
	e.windup = 0.0
	e.aim_mark = null
	e.cooldown = maxf(e.cooldown, .8)
	game.message(title(e) + " IS PLUM DESPERATE!", 2.6)
	game.sound_at(("sheriff" if e.kind == "boss" else e.kind) + "_rage", e.x, e.y, 1.0)
	game.shake = minf(1.0, game.shake + .7)
	game.blast_flash = maxf(game.blast_flash, .3)
	var floor_z: float = game.world.elevation(e.x, e.y)
	_sparks(game, e.x, e.y, floor_z + e.height * .7, "spark", 22, 2.6)
	_sparks(game, e.x, e.y, floor_z + e.height * .4, "dust", 10, 1.6)


## The glow on a boss's sprite while it winds up (Enemy.sprite's hurt flash,
## which lifts it toward white): a beat that quickens as the hit nears.
static func pulse(e: Enemy) -> float:
	if e.windup <= 0.0:
		return 0.0
	return .05 + .07 * (.5 + .5 * sin(e.pose * (14.0 + 10.0 / maxf(.15, e.windup))))


## Looks-only sparks off the feature's own dice (no game.rng).
static func _sparks(
	game, x: float, y: float, z: float, kind: String, count: int, speed: float
) -> void:
	var fight = game.features.get("boss_fight")
	if fight != null:
		fight.sparks(x, y, z, kind, count, speed)


# ------------------------------------------------------------------ entrance


## One tick of a boss's entrance (game.gd tick, instead of the world's): the
## world holds, the view eases round to the boss, and a fresh press of fire or
## jump (or use: game_world.gd interact) ends it.
static func hold(game, dt: float, controls) -> void:
	var p = game.player
	game.boss_hold = maxf(0.0, game.boss_hold - dt)
	var pressed: bool = controls.fire or controls.alt_fire or controls.jump
	if not pressed:
		game.boss_hold_armed = true
	elif game.boss_hold_armed and game.boss_hold_for - game.boss_hold > SKIP_AFTER:
		game.boss_hold = 0.0
	var e: Enemy = game.boss_hold_of
	if e != null:
		var want: float = atan2(e.y - p.y, e.x - p.x) - p.drift
		p.angle = fposmod(p.angle + Enemy.angle_delta(want, p.angle) * minf(1.0, dt * 7.0), TAU)
		p.pitch += (4.0 - p.pitch) * minf(1.0, dt * 6.0)
	p.vx = 0.0
	p.vy = 0.0
	if game.boss_hold <= 0.0:
		game.boss_hold_of = null


## The name coming down over the view (game_view.gd, over the world and the
## gun): a fair ribbon across the screen, the title slammed on it.
static func draw_intro(game, c: Canvas) -> void:
	var e: Enemy = game.boss_hold_of
	if game.boss_hold <= 0.0 or e == null:
		return
	var t: float = game.boss_hold_for - game.boss_hold
	var red := Canvas.rgb(150, 30, 24)
	var deep := Canvas.rgb(98, 18, 14)
	var gold := Canvas.rgb(236, 196, 104)
	var shade := Canvas.rgb(20, 12, 9)
	# The ribbon unrolls from the middle, then the name drops onto it.
	var half := int(lerpf(18.0, 146.0, clampf(t / .2, 0.0, 1.0)))
	var top := 56
	c.fill_rect(160 - half + 3, top + 3, half * 2, 34, shade)
	for side: int in [-1, 1]:
		# Swallowtails at either end, a shade darker.
		var x0 := 160 + side * half - (12 if side < 0 else 0)
		c.fill_rect(x0, top + 6, 12, 28, deep)
		c.fill_rect(x0 + (0 if side < 0 else 6), top + 16, 6, 8, shade)
	c.fill_rect(160 - half, top, half * 2, 34, red)
	c.fill_rect(160 - half + 3, top + 2, half * 2 - 6, 1, gold)
	c.fill_rect(160 - half + 3, top + 31, half * 2 - 6, 1, gold)
	if t < .14:
		return
	HUD.text(c, "- TONIGHT'S MAIN EVENT -", 160, top + 5, "mini", gold, true)
	var fall := clampf((t - .14) / .12, 0.0, 1.0)
	var y := int(lerpf(float(top - 30), float(top + 13), fall))
	var jolt := 0
	if fall >= 1.0 and t < .55:
		jolt = int(roundf(sin(t * 70.0) * 3.0 * (1.0 - (t - .26) / .29)))
	HUD.text(c, title(e), 160 + jolt, y, "heading", HUD.AMBER, true)
	if t > .7 and int(t * 3.0) % 2 == 0:
		HUD.text(c, "FIRE TO FIGHT", 160, top + 38, "mini", HUD.INK, true)
