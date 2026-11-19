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

## The player's fields stepped here, kept to put back after the frame
## (floor_z: a map with decks and stairs moves it under the feet, and a copy
## left with the drawn one parted on the next tick's eye; pass 7).
const KEPT := [
	"x",
	"y",
	"vx",
	"vy",
	"air",
	"vertical_speed",
	"jump_held",
	"crouched",
	"eye",
	"angle",
	"pitch",
	"floor_z",
	"knocked",
]
## More unplayed inputs than this (a stall) are not predicted past: 1.5 s
## (it was 40 ticks, under a 250 ms link's round trip and playout, so the
## drawn player was put back hundreds of times a minute there).
const MOST := 90
## Ticks at most another player is carried on by their speed (mates_ahead).
const MATES_AHEAD := 30
## Off: our walk bumps into the others where the copy stands them, a
## round trip and the playout behind the host (net_feel `old`).
static var mates_ahead := true
## Off: our inputs walked on through a hold of the world, and the walk
## without mud and a knock-down (the old way).
static var holds_aware := true


## Steps `me` through `inputs` (Game.Controls, oldest first); returns what to
## hand to `restore`. `echoed`: how many of them the host has played already
## (its echoed rows, first in the list; -1 all): while the world holds on
## the copy (held) those are not walked, the host having played them in its
## own hold.
static func lead(game: Game, me: Player, inputs: Array, echoed := -1) -> Dictionary:
	var kept := {}
	for field: String in KEPT:
		kept[field] = me.get(field)
	var dt := NetSync.STEP
	# In a vehicle (features/vehicles.gd) only the aim leads: the copy drives.
	var rides: Game.VehiclesScript = game.features.get("vehicles")
	var seated := rides != null and rides.seated(me)
	var first := maxi(0, inputs.size() - MOST)
	if held(game):
		first = maxi(first, inputs.size() if echoed < 0 else echoed)
	var mates := _mates(game, me) if not seated else []
	for i in range(first, inputs.size()):
		var controls: Game.Controls = inputs[i]
		if seated:
			me.angle = fposmod(me.angle + controls.turn, TAU)
			me.pitch = clampf(me.pitch + controls.look, -53.0, 53.0)
			continue
		_place_mates(game, mates, i + 1)
		step(game, me, controls, dt)
	_place_mates(game, mates, 0)
	return kept


## The world holds on the copy (COUNTY RUN's cards on offer, the tally, a
## gate taken, everyone down: game.gd tick returns before anyone moves or
## turns): the host held it on the ticks it has echoed since, so the inputs
## it played then are not walked (lead's `echoed`). Walked, the drawn player
## ran and turned through a card pick and was put back when it ended. The
## ones it has not played yet are walked: by the time they reach it the hold
## is over (the copy shows the hold a one-way trip and the playout late, and
## the pick that ends it is on its way), and freezing them froze the view for
## a round trip after every pick.
static func held(game: Game) -> bool:
	if not holds_aware:
		return false
	return game.showing_tally or game.defeated() or game.portal_request != "" or Modes.holds(game)


## The other players who block us (co-op, the versus modes), with where the
## copy stands them: our walk meets them where the host will have them when
## each of our inputs is played (the i-th unplayed one on the copy's tick
## plus i+1), carried on by their speed, not where the copy has them, a
## round trip and the playout behind. Two co-op bots following each other
## were corrected 6 to 25 times a second against a partner who had moved on.
static func _mates(game: Game, me: Player) -> Array:
	var out: Array = []
	if not mates_ahead or game.players.size() < 2 or not Modes.rules(game).bodies_block():
		return out
	for q: Player in game.players:
		if q != me and q.health > 0 and not q.away:
			out.append([q, q.x, q.y])
	return out


## `mates` (from _mates) carried `ticks` on by their speed (0: put back).
static func _place_mates(game: Game, mates: Array, ticks: int) -> void:
	var t := mini(ticks, MATES_AHEAD) * NetSync.STEP
	for row: Array in mates:
		var q: Player = row[0]
		var x0: float = row[1]
		var y0: float = row[2]
		var x := x0 + q.vx * t
		var y := y0 + q.vy * t
		if ticks == 0 or game.world.blocked(x, y, Game.PLAYER_RADIUS):
			x = x0
			y = y0
		q.x = x
		q.y = y


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
	## Our inputs the copy had not played this frame (NetPredict.ahead).
	var last_inputs := 0
	var _prev := {}
	var _prev_seq := -1

	## Puts `me` where this frame draws it; returns what to hand to restore.
	func draw(game: Game, me: Player, client: NetSync.Client, dt: float) -> Dictionary:
		var copy_state := {}
		for field: String in KEPT:
			copy_state[field] = me.get(field)
		var guess := Vector2.INF
		var inputs := client.unplayed_inputs()
		last_inputs = inputs.size()
		if not _prev.is_empty():
			NetPredict.restore(me, _prev)
			var mates := NetPredict._mates(game, me)
			for n in range(_prev_seq, client.input_seq):
				var bytes: PackedByteArray = client.sent.get(n, PackedByteArray())
				if bytes.size() >= NetWire.CONTROL_BYTES:
					# (the n-th input's place among the unplayed ones)
					NetPredict._place_mates(game, mates, inputs.size() - (client.input_seq - n) + 1)
					NetPredict.step(game, me, NetWire.unpack_controls(bytes), NetSync.STEP)
			NetPredict._place_mates(game, mates, 0)
			guess = Vector2(me.x, me.y)
			NetPredict.restore(me, copy_state)
		var kept := NetPredict.lead(game, me, inputs, client.latest_tick - client.game_tick)
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


## Off: the drawn player stands at its newest tick between ticks (the old
## way: net_lag/net_feel `old`).
static var between := true


## Our player carried on into the next tick by `share` (0 to 1: how far this
## frame is into it), walked with the keys held now, and turned by the mouse
## not sent yet (`turn`, `look`, all of it). The game ticks 60 times a second
## online, so on a faster screen the drawn player held still for a frame or
## two and then stepped; now it moves every frame (single-player, at 120
## ticks, still holds one frame in six on a 144 Hz screen). Looks only: the
## fields are put back after the frame with the rest (KEPT).
##
## `ticks` is how far past the copy's tick the next input will be played
## (our unplayed inputs and one): the others who block us stand there.
static func ahead(
	game: Game, me: Player, keys: Game.Controls, turn: float, look: float, share: float, ticks := 1
) -> void:
	var rides: Game.VehiclesScript = game.features.get("vehicles")
	if not between or keys == null or share <= 0.0 or (rides != null and rides.seated(me)):
		me.angle = fposmod(me.angle + turn, TAU)
		me.pitch = clampf(me.pitch + look, -53.0, 53.0)
		return
	var from := {}
	for field: String in KEPT:
		from[field] = me.get(field)
	var c := Game.Controls.new()
	c.forward = keys.forward
	c.strafe = keys.strafe
	c.running = keys.running
	c.crouch = keys.crouch
	c.jump = keys.jump
	c.turn = turn
	c.look = look
	var mates := _mates(game, me)
	_place_mates(game, mates, ticks)
	step(game, me, c, NetSync.STEP)
	_place_mates(game, mates, 0)
	var x0: float = from["x"]
	var y0: float = from["y"]
	var eye0: float = from["eye"]
	var air0: float = from["air"]
	var x := lerpf(x0, me.x, share)
	var y := lerpf(y0, me.y, share)
	var eye := lerpf(eye0, me.eye, share)
	var air := lerpf(air0, me.air, share)
	var angle := me.angle
	var pitch := me.pitch
	restore(me, from)
	me.angle = angle
	me.pitch = pitch
	me.eye = eye
	me.air = air
	if not game.world.blocked(x, y, .1):
		me.x = x
		me.y = y


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
	if holds_aware:
		speed *= Mud.pace(game, p.x, p.y)
	# (game.gd: the knock-down wears off before the walk looks at it)
	if holds_aware:
		p.knocked = maxf(0.0, p.knocked - dt)
	var knocked := holds_aware and p.knocked > 0.0
	var w: LevelData = game.world
	if w.surface_sound(int(w.floor_tile[w.cell(p.x, p.y)])) == "water":
		speed *= .69
	p.crouched = controls.crouch and p.air <= .01
	if p.crouched:
		speed *= .51
	if knocked:
		speed = 0.0
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
	if controls.jump and not p.jump_held and p.air == 0.0 and not controls.crouch and not knocked:
		p.vertical_speed = 2.7
	p.jump_held = controls.jump
	if p.air > 0.0 or p.vertical_speed > 0.0:
		p.air = maxf(0.0, p.air + p.vertical_speed * dt)
		p.vertical_speed -= dt * 9.2
		if p.air == 0.0:
			p.vertical_speed = 0.0
	var ground: float = w.stand(p)
	var eye := (.3 if knocked else .68 if p.crouched else .95) + ground + p.air
	var roof: float = w.roof_over(p.x, p.y, ground)
	if roof != 0.0 and eye > roof - .22:
		eye = roof - .22
		p.vertical_speed = minf(0.0, p.vertical_speed)
	p.eye += (eye - p.eye) * minf(1.0, dt * 17.0)
