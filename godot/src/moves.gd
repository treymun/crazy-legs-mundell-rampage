## A player's walk (pass 15, MOVES): its numbers (data/tuning/modes.cfg
## [move]) and the part of the step every copy plays alike. game.gd `_walk`
## and an online client's NetPredict.step both end in body(), so what the
## host plays and what a client draws ahead of it are one sum.
## Plain arithmetic on carried fields: no dice, the same on every machine.
class_name Moves
extends RefCounted

## Cells a second walking and running, and moonshine's sprint on top.
static var WALK: float = ModeData.get_value("move", "walk", 2.75)
static var RUN: float = ModeData.get_value("move", "run", 3.85)
static var SPRINT: float = ModeData.get_value("move", "sprint", 1.42)
## The share of the speed kept wading and crouched.
static var WATER: float = ModeData.get_value("move", "water", .69)
static var CROUCH: float = ModeData.get_value("move", "crouch", .51)
## How fast the speed comes to what the keys ask (a second): on the ground
## with a key held, on the ground with none (the stop), in the air.
static var EASE_MOVE: float = ModeData.get_value("move", "ease_move", 23.0)
static var EASE_STOP: float = ModeData.get_value("move", "ease_stop", 30.0)
static var EASE_AIR: float = ModeData.get_value("move", "ease_air", 7.0)
## A jump's speed up and the fall's pull (units a second, and a second squared).
static var JUMP: float = ModeData.get_value("move", "jump", 2.7)
static var GRAVITY: float = ModeData.get_value("move", "gravity", 9.2)
## The slide: CROUCH taken going at least SLIDE_FROM on the ground starts
## one at SLIDE_SPEED (or the speed it had, if more), easing to the crouch
## walk over SLIDE_FOR seconds; it turns toward the keys at most SLIDE_STEER
## radians a second, ends on a jump (a hop out of it), against a wall (less
## than SLIDE_WALL of its step made), on letting go of CROUCH or at its end,
## and another waits SLIDE_REST seconds after it.
static var SLIDE_FROM: float = ModeData.get_value("move", "slide_from", 3.4)
static var SLIDE_SPEED: float = ModeData.get_value("move", "slide_speed", 5.0)
static var SLIDE_FOR: float = ModeData.get_value("move", "slide_for", .55)
static var SLIDE_STEER: float = ModeData.get_value("move", "slide_steer", 1.6)
static var SLIDE_WALL: float = ModeData.get_value("move", "slide_wall", .5)
static var SLIDE_REST: float = ModeData.get_value("move", "slide_rest", .8)


## The speed the keys ask for before what slows it: running or walking,
## moonshine's sprint, split over a diagonal (`magnitude`).
static func speed_of(running: bool, sprint: bool, magnitude: float) -> float:
	return (RUN if running else WALK) * (SPRINT if sprint else 1.0) / magnitude


## The walk from its speed on (`speed`: what the keys ask, slowed by gut,
## drink, mud and the rest; `knocked`: laid flat, no walk and no jump):
## crouching, the slide, the ease in and out, the move against walls and
## bodies, the jump and the fall. True when `p` landed this step.
static func body(
	game: GameWorld,
	p: Player,
	c: Game.Controls,
	speed: float,
	forward: float,
	strafe: float,
	knocked: bool,
	dt: float
) -> bool:
	var was_crouched := p.crouched
	p.crouched = c.crouch and p.air <= .01
	var upright := speed
	if p.crouched:
		speed *= CROUCH
	if knocked:
		speed = 0.0
	var vx := cos(p.view_angle())
	var vy := sin(p.view_angle())
	var ox := p.x
	var oy := p.y
	p.slide_rest = maxf(0.0, p.slide_rest - dt)
	if p.slide > 0.0 and (not c.crouch or knocked or p.air > 0.0):
		_slide_over(p)
	elif (
		p.slide <= 0.0
		and p.crouched
		and not was_crouched
		and p.slide_rest <= 0.0
		and not knocked
		and p.vx * p.vx + p.vy * p.vy >= SLIDE_FROM * SLIDE_FROM
	):
		_slide_start(p, upright, c.running, magnitude_of(forward, strafe))
	if p.slide > 0.0:
		_slide_step(p, speed, Vector2(forward * vx - strafe * vy, forward * vy + strafe * vx), dt)
	else:
		var rate := (
			EASE_AIR if p.air else EASE_MOVE if forward != 0.0 or strafe != 0.0 else EASE_STOP
		)
		var response := 1.0 - exp(-dt * rate)
		p.vx += (speed * (forward * vx - strafe * vy) - p.vx) * response
		p.vy += (speed * (forward * vy + strafe * vx) - p.vy) * response
	game.move_actor(p, p.vx * dt, p.vy * dt, GameState.PLAYER_RADIUS)
	if p.slide > 0.0:
		# Into a wall (or a body) head on: the slide is over.
		var want := Vector2(p.vx, p.vy).length() * dt
		if Vector2(p.x - ox, p.y - oy).length() < want * SLIDE_WALL:
			_slide_over(p)
	if p.x == ox and absf(p.vx) > .02:
		p.vx = 0.0
	if p.y == oy and absf(p.vy) > .02:
		p.vy = 0.0
	if (
		c.jump
		and not p.jump_held
		and p.air == 0.0
		and (not c.crouch or p.slide > 0.0)
		and not knocked
	):
		# A jump out of a slide keeps its speed: a hop.
		if p.slide > 0.0:
			_slide_over(p)
		p.vertical_speed = JUMP
	p.jump_held = c.jump
	var landed := false
	if p.air > 0.0 or p.vertical_speed > 0.0:
		p.air = maxf(0.0, p.air + p.vertical_speed * dt)
		p.vertical_speed -= dt * GRAVITY
		if p.air == 0.0:
			p.vertical_speed = 0.0
			landed = true
	return landed


static func magnitude_of(forward: float, strafe: float) -> float:
	return maxf(1.0, sqrt(forward * forward + strafe * strafe))


## A slide begins along the way `p` is going, at SLIDE_SPEED as slowed by
## what slows the walk (`upright`: the walk's speed before the crouch), or
## faster if it was going faster (moonshine's sprint).
static func _slide_start(p: Player, upright: float, running: bool, magnitude: float) -> void:
	var plain := speed_of(running, false, magnitude)
	var share := upright / plain if plain > 0.0 else 1.0
	var going := Vector2(p.vx, p.vy)
	p.slide = SLIDE_FOR
	p.slide_dir = going.normalized()
	p.slide_top = maxf(SLIDE_SPEED * minf(share, 1.0), going.length())


## One step of a slide: the speed eases (slow at first, then quicker, as a
## boot's grip takes hold) from where it started to the crouch walk
## (`crouch_speed`), the way turned toward the keys' `wish` by SLIDE_STEER.
static func _slide_step(p: Player, crouch_speed: float, wish: Vector2, dt: float) -> void:
	if wish.length_squared() > .0001:
		var turn := p.slide_dir.angle_to(wish)
		var most := SLIDE_STEER * dt
		p.slide_dir = p.slide_dir.rotated(clampf(turn, -most, most))
	var gone := clampf(1.0 - p.slide / SLIDE_FOR, 0.0, 1.0)
	var low := minf(crouch_speed, p.slide_top)
	var now := p.slide_top + (low - p.slide_top) * gone * gone
	p.vx = p.slide_dir.x * now
	p.vy = p.slide_dir.y * now
	p.slide = maxf(0.0, p.slide - dt)
	if p.slide == 0.0:
		p.slide_rest = SLIDE_REST


static func _slide_over(p: Player) -> void:
	p.slide = 0.0
	p.slide_rest = SLIDE_REST
