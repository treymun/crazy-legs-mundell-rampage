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
## More unplayed inputs than this (a stall) are not predicted past: 1.5 s
## (it was 40 ticks, under a 250 ms link's round trip and playout, so the
## drawn player was put back hundreds of times a minute there).
const MOST := 90


## Steps `me` through `inputs` (Game.Controls, oldest first); returns what to
## hand to `restore`.
static func lead(game: Game, me: Player, inputs: Array) -> Dictionary:
	var kept := {}
	for field: String in KEPT:
		kept[field] = me.get(field)
	var dt := NetSync.STEP
	# In a vehicle (features/vehicles.gd) only the aim leads: the copy drives.
	var rides: Game.VehiclesScript = game.features.get("vehicles")
	var seated := rides != null and rides.seated(me)
	for i in range(maxi(0, inputs.size() - MOST), inputs.size()):
		var controls: Game.Controls = inputs[i]
		if seated:
			me.angle = fposmod(me.angle + controls.turn, TAU)
			me.pitch = clampf(me.pitch + controls.look, -53.0, 53.0)
			continue
		step(game, me, controls, dt)
	return kept


static func restore(me: Player, kept: Dictionary) -> void:
	for field: String in kept:
		me.set(field, kept[field])


## The drawn player eased over a correction instead of jumping: each frame,
## last frame's drawn place walked on by the inputs sent since is where the
## player expects to be; when the prediction (lead) lands elsewhere (the host
## played an input late, a body or a blow moved them), the gap is kept as an
## offset on the picture that fades over SMOOTH seconds. Looks only: the
## offset is put on for the frame and taken off with the rest (restore).
class Smoother:
	extends RefCounted
	## Seconds a correction fades over (to 1/e).
	const SMOOTH := .09
	## A gap past this is a respawn or a new round: no easing.
	const TELEPORT := 1.0
	## Off: the prediction drawn as it is (net_lag.gd's before).
	static var enabled := true

	var offset := Vector2.ZERO
	## The raw gap and the one the player saw this frame (for net_lag.gd).
	var last_gap := 0.0
	var last_seen := 0.0
	var _prev := {}
	var _prev_seq := -1

	## Puts `me` where this frame draws it; returns what to hand to restore.
	func draw(game: Game, me: Player, client: NetSync.Client, dt: float) -> Dictionary:
		var copy_state := {}
		for field: String in KEPT:
			copy_state[field] = me.get(field)
		var guess := Vector2.INF
		if not _prev.is_empty():
			NetPredict.restore(me, _prev)
			for n in range(_prev_seq, client.input_seq):
				var bytes: PackedByteArray = client.sent.get(n, PackedByteArray())
				if bytes.size() >= NetWire.CONTROL_BYTES:
					NetPredict.step(game, me, NetWire.unpack_controls(bytes), NetSync.STEP)
			guess = Vector2(me.x, me.y)
			NetPredict.restore(me, copy_state)
		var kept := NetPredict.lead(game, me, client.unplayed_inputs())
		var drawn := Vector2(me.x, me.y)
		_prev = {}
		for field: String in KEPT:
			_prev[field] = me.get(field)
		_prev_seq = client.input_seq
		last_gap = 0.0
		last_seen = 0.0
		if guess == Vector2.INF:
			return kept
		var gap := guess - drawn
		last_gap = gap.length()
		if not enabled or last_gap > TELEPORT or (offset + gap).length() > TELEPORT:
			offset = Vector2.ZERO
			last_seen = last_gap
			return kept
		var expected := offset + gap
		offset = expected * exp(-dt / SMOOTH)
		if offset.length() < .002:
			offset = Vector2.ZERO
		last_seen = (expected - offset).length()
		var at := drawn + offset
		if offset != Vector2.ZERO and not game.world.blocked(at.x, at.y, .1):
			me.x = at.x
			me.y = at.y
		return kept

	## Forgets the last frame (out of play, dead, another match).
	func reset() -> void:
		_prev = {}
		offset = Vector2.ZERO


## game.gd `_step_body`'s walking, for one tick.
static func step(game: Game, p: Player, controls: Game.Controls, dt: float) -> void:
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
