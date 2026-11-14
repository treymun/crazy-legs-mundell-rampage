## A client's own walking drawn where its keys have put it. The copy of the
## game only plays our inputs once the host has played them, a round trip and
## the play-out delay later, so walking felt like wading through syrup online.
## Each frame this steps our player on from the copy with the inputs the host
## has not played into it yet, using the same walking sums as game.gd
## `_step_body` (speed, turn, the ease in and out, jumps, the walls and bodies
## through `move_actor`) and nothing else: no sounds, no dice, no pickups.
## main.gd puts the player back after the frame is drawn, so the copy (and
## what it plays) never changes; only the picture leads.
class_name NetPredict
extends RefCounted

## The player's fields stepped here, kept to put back after the frame.
const KEPT := [
	"x", "y", "vx", "vy", "air", "vertical_speed", "jump_held", "crouched", "eye", "angle", "pitch"
]
## More unplayed inputs than this (a stall) are not predicted past.
const MOST := 40


## Steps `me` through `inputs` (Game.Controls, oldest first); returns what to
## hand to `restore`.
static func lead(game: Game, me: Player, inputs: Array) -> Dictionary:
	var kept := {}
	for field: String in KEPT:
		kept[field] = me.get(field)
	var dt := NetSync.STEP
	for i in range(maxi(0, inputs.size() - MOST), inputs.size()):
		_step(game, me, inputs[i], dt)
	return kept


static func restore(me: Player, kept: Dictionary) -> void:
	for field: String in kept:
		me.set(field, kept[field])


## game.gd `_step_body`'s walking, for one tick.
static func _step(game: Game, p: Player, controls: Game.Controls, dt: float) -> void:
	p.angle = fposmod(p.angle + controls.turn, TAU)
	p.pitch = clampf(p.pitch + controls.look, -53.0, 53.0)
	var forward: float = controls.forward
	var strafe: float = controls.strafe
	var magnitude := maxf(1.0, sqrt(forward * forward + strafe * strafe))
	var speed: float = (
		(3.85 if controls.running else 2.75) * (1.42 if p.sprint else 1.0) / magnitude
	)
	speed *= 1.0 - maxf(0.0, p.gut - 65.0) * .004 - maxf(0.0, p.drunk - 70.0) * .004
	speed *= Modes.move_scale(game, p)
	var w: LevelData = game.world
	if w.surface_sound(int(w.floor_tile[w.cell(p.x, p.y)])) == "water":
		speed *= .69
	p.crouched = controls.crouch and p.air <= .01
	if p.crouched:
		speed *= .51
	var vx := cos(p.view_angle())
	var vy := sin(p.view_angle())
	var ox := p.x
	var oy := p.y
	var response := (
		1.0 - exp(-dt * (7.0 if p.air else 23.0 if forward != 0.0 or strafe != 0.0 else 30.0))
	)
	p.vx += (speed * (forward * vx - strafe * vy) - p.vx) * response
	p.vy += (speed * (forward * vy + strafe * vx) - p.vy) * response
	game.move_actor(p, p.vx * dt, p.vy * dt, Game.PLAYER_RADIUS)
	if p.x == ox and absf(p.vx) > .02:
		p.vx = 0.0
	if p.y == oy and absf(p.vy) > .02:
		p.vy = 0.0
	if controls.jump and not p.jump_held and p.air == 0.0 and not controls.crouch:
		p.vertical_speed = 2.7
	p.jump_held = controls.jump
	if p.air > 0.0 or p.vertical_speed > 0.0:
		p.air = maxf(0.0, p.air + p.vertical_speed * dt)
		p.vertical_speed -= dt * 9.2
		if p.air == 0.0:
			p.vertical_speed = 0.0
	var ground: float = w.stand(p)
	var eye := (.68 if p.crouched else .95) + ground + p.air
	var roof: float = w.roof_over(p.x, p.y, ground)
	if roof != 0.0 and eye > roof - .22:
		eye = roof - .22
		p.vertical_speed = minf(0.0, p.vertical_speed)
	p.eye += (eye - p.eye) * minf(1.0, dt * 17.0)
