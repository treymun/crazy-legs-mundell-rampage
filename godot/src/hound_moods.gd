## BLUE's ears, moods and rides (features/hound.gd, pass 10): what he hears
## (a twister, a siren), the moments that stop him (howling, growling,
## cowering, greeting, wagging round a still), and getting into a vehicle's
## free seat beside his player, riding along and hopping out, or jumping out
## of one's way. Play, carried in the hound's Dog: the same on every machine,
## dice only from game.rng.
class_name HoundMoods
extends RefCounted

## Radians a second he goes round a still or scrap (pass 12).
const TREAT_ROUND := 1.2
## Settled, he turns toward his player when he faces further off than this
## (radians), and then only part way (pass 12).
const SETTLE_OFF := 1.2
## His player walking at him closer than this share of heel_near, he gets out
## of their way (pass 12).
const MAKE_WAY := 1.3


## What he hears this tick (a twister, a siren): true when it took him off
## what he was doing.
static func hear(h: Game.HoundScript, d: Game.HoundScript.Dog, p: Player) -> bool:
	var g := h.game
	var ev: CountyEvents = g.features.get("events")
	if ev != null and ev.kind == "twister" and ev.tw_k > .1:
		var reach := ev.n("twister", "reach") + h.n("cower_reach")
		if Vector2(d.x - ev.tw_at.x, d.y - ev.tw_at.y).length() < reach:
			h.into(d, Game.HoundScript.COWER)
			d.mood = Game.HoundScript.SCARED
			d.mood_until = g.clock + 4.0
			h.cowers += 1
			g.sound_at("hound_whimper", d.x, d.y, .9)
			return true
	if g.clock < d.next_howl or not HoundNose.siren_near(g, d.x, d.y, h.n("siren_reach")):
		return false
	d.next_howl = g.clock + h.n("howl_rest")
	if g.rng.random() >= h.n("howl_chance"):
		return false
	h.into(d, Game.HoundScript.HOWL)
	d.until = g.clock + h.n("howl_for")
	h.howls += 1
	g.sound_at("hound_howl", d.x, d.y, 1.0)
	if p == g.player:
		g.barks.say(g, "hound_hush")
	return true


## Howling at a siren, or growling at a hand he smells round a corner: he
## stands, his nose to it, till it is done.
static func standing(h: Game.HoundScript, d: Game.HoundScript.Dog, p: Player, dt: float) -> void:
	h.halt(d, dt)
	if d.look != Vector2.INF:
		d.angle = HoundLegs.turn(d.angle, atan2(d.look.y - d.y, d.look.x - d.x), dt * 6.0)
	var far := Vector2(p.x - d.x, p.y - d.y).length() > h.n("catch_far")
	if h.game.clock >= d.until or far:
		h.into(d, Game.HoundScript.FOLLOW)


## A twister about: he runs to his player's side away from it and cowers
## there, whimpering, till it is gone.
static func cower(h: Game.HoundScript, d: Game.HoundScript.Dog, p: Player, dt: float) -> void:
	var g := h.game
	var ev: CountyEvents = g.features.get("events")
	var reach := 0.0
	if ev != null and ev.kind == "twister" and ev.tw_k > .1:
		reach = ev.n("twister", "reach") + h.n("cower_reach") + 2.0
	if reach <= 0.0 or Vector2(d.x - ev.tw_at.x, d.y - ev.tw_at.y).length() > reach:
		h.into(d, Game.HoundScript.FOLLOW)
		return
	d.mood = Game.HoundScript.SCARED
	d.mood_until = g.clock + 3.0
	var away := Vector2(p.x - ev.tw_at.x, p.y - ev.tw_at.y).normalized()
	var spot := Vector2(p.x, p.y) + away * .9
	if Vector2(spot.x - d.x, spot.y - d.y).length() > .35:
		h.head(d, p, spot, h.n("run"), dt)
	else:
		d.speed = 0.0
		d.angle = HoundLegs.turn(d.angle, atan2(p.y - d.y, p.x - d.x), dt * 4.0)
	if g.clock >= d.next_whine:
		d.next_whine = g.clock + 2.8
		g.sound_at("hound_whimper", d.x, d.y, .8)


## Up again: he runs to the one who got him up (Dog.goal_uid holds their
## slot), yips and wags round them.
static func greet(h: Game.HoundScript, d: Game.HoundScript.Dog, p: Player, dt: float) -> void:
	var g := h.game
	var to: Player = p
	if d.goal_uid >= 0 and d.goal_uid < g.players.size():
		to = g.players[d.goal_uid]
	var gap := Vector2(to.x - d.x, to.y - d.y).length()
	if gap > .9:
		h.head(d, p, Vector2(to.x, to.y), h.n("lope"), dt, true)
	else:
		h.halt(d, dt)
		d.angle = HoundLegs.turn(d.angle, atan2(to.y - d.y, to.x - d.x), dt * 6.0)
		if g.clock - d.bark_at > .7:
			d.bark_at = g.clock
			g.sound_at("hound_yip", d.x, d.y, .8)
	if g.clock >= d.until:
		h.into(d, Game.HoundScript.FOLLOW)


## A still or scrap: he runs to it, wags round it yipping, and comes back.
static func treat(h: Game.HoundScript, d: Game.HoundScript.Dog, p: Player, dt: float) -> void:
	var g := h.game
	var far := Vector2(p.x - d.x, p.y - d.y).length() > h.n("catch_far")
	if g.clock >= d.until or far or HoundNose.fight_near(g, p.x, p.y, 10.0):
		h.into(d, Game.HoundScript.FOLLOW)
		return
	var gap := Vector2(d.look.x - d.x, d.look.y - d.y).length()
	if d.bark_at < d.since:
		if gap > 1.3 and g.clock < d.since + 5.0 and d.stall < 1.0:
			h.head(d, p, d.goal, h.n("lope"), dt)
			return
		d.bark_at = g.clock
		d.until = g.clock + h.n("treat_for")
		h.treats += 1
		g.sound_at("hound_yip", d.x, d.y, .9)
		return
	# Round it, a little circle at his nose's length.
	# (pass 12: at an amble, once round in about five seconds; he spun round
	# it at a trot)
	var a := atan2(d.y - d.look.y, d.x - d.look.x) + dt * TREAT_ROUND * d.side
	var round_at := d.look + Vector2(cos(a), sin(a)) * 1.0
	d.speed = move_toward(d.speed, h.n("amble"), h.n("accel") * dt)
	h.stride(d, atan2(round_at.y - d.y, round_at.x - d.x), maxf(d.speed, .4) * dt, dt)
	if g.clock - d.bark_at > .9:
		d.bark_at = g.clock
		g.sound_at("hound_yip", d.x, d.y, .7)


## His player at the wheel: a free seat beside them, he goes to it and gets
## in when he reaches it (it going slow enough); true when that was his
## tick. Else (the mower, the seat taken, it gone off fast) he follows.
static func board(
	h: Game.HoundScript, d: Game.HoundScript.Dog, p: Player, rides: Game.VehiclesScript, dt: float
) -> bool:
	var g := h.game
	var at := rides.seat_of(p)
	var v: VehicleDrive.Ride = rides.rides[at.x]
	var s := VehicleDrive.spec(v.kind)
	if s.seats < 2 or v.seats.size() < 2 or v.seats[1] != -1 or v.wreck >= 0.0:
		return false
	for other: Game.HoundScript.Dog in h.dogs:
		if other != d and other.ride == at.x:
			return false
	var gap := Vector2(v.x - d.x, v.y - d.y).length()
	var slow := VehicleDrive.speed(v) < h.n("board_speed")
	if slow and gap < s.length * .5 + h.n("board_reach"):
		h.into(d, Game.HoundScript.RIDE)
		d.ride = at.x
		d.hop = HoundLegs.seat_at(v)
		h.rode += 1
		g.sound_at("hound_boof", d.x, d.y, .7)
		return true
	if gap > 9.0 or VehicleDrive.speed(v) > h.n("board_speed") * 2.0:
		return false
	var to := HoundLegs.beside(g, v, Vector2(d.x, d.y), h.n("radius"))
	if to == Vector2.INF:
		return false
	d.job = Game.HoundScript.CATCH
	h.head(d, p, to, h.n("run"), dt)
	return true


## Riding along in the seat beside his player; out again beside it when
## they get out, someone takes his seat or it is wrecked.
static func riding(h: Game.HoundScript, d: Game.HoundScript.Dog, p: Player, dt: float) -> void:
	var g := h.game
	var rides: Game.VehiclesScript = g.features.get("vehicles")
	if rides == null or d.ride < 0 or d.ride >= rides.rides.size():
		h.into(d, Game.HoundScript.FOLLOW)
		return
	var v: VehicleDrive.Ride = rides.rides[d.ride]
	var seat := rides.seat_of(p)
	if seat.x != d.ride or v.wreck >= 0.0 or (v.seats.size() > 1 and v.seats[1] != -1):
		var mirror := Vector2(p.x, p.y) * 2.0 - Vector2(v.x, v.y)
		var down := HoundLegs.beside(g, v, mirror, h.n("radius"))
		if down == Vector2.INF:
			# No room beside it (a dock): down at his player's feet.
			var toward := (Vector2(v.x, v.y) - Vector2(p.x, p.y)).normalized()
			down = Vector2(p.x, p.y) + toward * .5
			if HoundLegs.harm(g, [], down.x, down.y) or g.world.blocked(down.x, down.y, .2):
				down = Vector2(p.x, p.y)
		h.into(d, Game.HoundScript.FOLLOW)
		d.hop = down
		d.hop_z = g.world.floor_under(down.x, down.y, v.z + 1.0)
		g.sound_at("hound_boof", d.x, d.y, .6)
		return
	var at := HoundLegs.seat_at(v)
	d.speed = 0.0
	if d.hop != Vector2.INF:
		# On his way up into the seat (it may be moving off).
		if not h.leap(d, at, v.z, dt):
			return
		d.hop = Vector2.INF
	d.x = at.x
	d.y = at.y
	d.floor_z = v.z
	d.angle = v.h


## A vehicle coming at him: he jumps aside, off its line; one on him shoves
## him out of its hull (vehicles run hands down, never BLUE).
static func clear_of_rides(h: Game.HoundScript, d: Game.HoundScript.Dog, dt: float) -> void:
	var g := h.game
	var rides: Game.VehiclesScript = g.features.get("vehicles")
	if rides == null:
		return
	for v: VehicleDrive.Ride in rides.rides:
		if v.wreck >= 0.0:
			continue
		var s := VehicleDrive.spec(v.kind)
		var reach := s.length * .5 + h.n("ride_reach") + 1.0
		if absf(d.x - v.x) > reach or absf(d.y - v.y) > reach:
			continue
		var push := VehicleDrive.out_of(s, v, d.x, d.y, h.n("radius"))
		if push != Vector2.INF:
			h.shove(d, push.x, push.y)
			continue
		var speed := VehicleDrive.speed(v)
		if speed < h.n("ride_from") or d.state == Game.HoundScript.DOWN:
			continue
		var heading := Vector2(v.vx, v.vy) / speed
		var rel := Vector2(d.x - v.x, d.y - v.y)
		var ahead := rel.dot(heading) - s.length * .5
		var side := rel.dot(Vector2(-heading.y, heading.x))
		if ahead < -.2 or ahead > h.n("ride_reach") or absf(side) > s.width * .5 + .6:
			continue
		var away := 1.0 if side > 0.0 or (side == 0.0 and d.slot % 2 == 0) else -1.0
		var step := h.n("ride_hop") * dt * away
		var moved := h.shove(d, -heading.y * step, heading.x * step)
		var fled := Vector2(-heading.y, heading.x) * away
		if moved < absf(step) * .3:
			# A wall that side: the other.
			moved = h.shove(d, heading.y * step, -heading.x * step)
			fled = -fled
		# He bounds off that way (pass 12: he slid off sideways, standing).
		d.angle = HoundLegs.turn(d.angle, fled.angle(), dt * h.n("turn_slow") * 2.0)
		d.pace = moved / maxf(dt, .0001)
		d.speed = maxf(d.speed, d.pace)
		d.gait += moved * HoundLooks.beats_per_cell(d.gait_kind, d.stride_v) * PI * .5
		if g.clock - d.bark_at > 1.2:
			d.bark_at = g.clock
			g.sound_at("hound_bark", d.x, d.y, .9)


## In a player's sights, or in his own player's as they swing round toward
## him: he steps aside, off their line (across it against the swing, the
## quickest way out of it).
static func aside(h: Game.HoundScript, d: Game.HoundScript.Dog, p: Player, dt: float) -> void:
	var g := h.game
	var q := HoundLegs.in_sights(g, d, h.n("clear_reach"), h.n("clear_cone"))
	var swing := absf(d.p_turn) > .6
	if q == null and swing:
		var mine := HoundLegs.in_sights(g, d, h.n("clear_reach"), h.n("clear_cone") - .1)
		if mine == p:
			var to := Vector2(d.x - p.x, d.y - p.y)
			var on_side := Vector2(cos(p.angle), sin(p.angle)).cross(to)
			if signf(on_side) == signf(d.p_turn):
				q = p  # the sights come his way
	if q == null:
		d.sighted = 0.0
		return
	# A moment first (pass 12): a look sweeping past him no longer sends him
	# darting off.
	d.sighted += dt
	if d.sighted < h.n("aside_after") and d.job != Game.HoundScript.ASIDE:
		return
	var look := Vector2(cos(q.angle), sin(q.angle))
	var to_q := Vector2(d.x - q.x, d.y - q.y)
	var side := 1.0 if look.cross(to_q) >= 0.0 else -1.0
	if q == p and swing:
		side = -signf(d.p_turn)
	d.aside = Vector2(-look.y, look.x) * side
	if d.job != Game.HoundScript.ASIDE:
		h.asides += 1
	d.job = Game.HoundScript.ASIDE
	d.job_until = g.clock + h.n("aside_for")


## A shot fired (the game's shot_fired, through the hound feature `h`): a
## dog it passed close by (in front of the shooter, within `shot_near` of its
## line, in their sight) sulks a while behind his player.
static func shot(h: Game.HoundScript, gun: int) -> void:
	if not Weapons.MUZZLE_GUNS.has(gun):
		return
	var g := h.game
	var q := g.player
	if q == null:
		return
	var look := Vector2(cos(q.angle), sin(q.angle))
	for d: Game.HoundScript.Dog in h.dogs:
		var st := d.state
		if (
			st != Game.HoundScript.FOLLOW
			and st != Game.HoundScript.STAY
			and st != Game.HoundScript.TREAT
			and st != Game.HoundScript.GREET
		):
			continue
		var to := Vector2(d.x - q.x, d.y - q.y)
		var along := to.dot(look)
		if along < .4 or along > 14.0 or absf(look.cross(to)) > h.n("shot_near"):
			continue
		if not g.world.visible(q.x, q.y, d.x, d.y, q.eye, d.floor_z + .4):
			continue
		if d.mood != Game.HoundScript.SULK:
			h.sulks += 1
			g.sound_at("hound_whine_soft", d.x, d.y, .9)
			if d.slot == q.slot and q == g.player:
				g.barks.say(g, "hound_shot")
		d.mood = Game.HoundScript.SULK
		d.mood_until = g.clock + h.n("sulk_for")
		if d.state != Game.HoundScript.FOLLOW:
			h.into(d, Game.HoundScript.FOLLOW)
		d.job = Game.HoundScript.TRAIL


## Settled by a standing player (pass 12): he eases to a stop and turns his
## head to them only when he faces well away (no turning on the spot after
## every look they take); his looks sit him down, then lay him down.
static func settle(h: Game.HoundScript, d: Game.HoundScript.Dog, p: Player, dt: float) -> void:
	if d.speed > .05:
		h.halt(d, dt)
		return
	var to_p := atan2(p.y - d.y, p.x - d.x)
	var off := wrapf(to_p - d.angle, -PI, PI)
	if absf(off) > SETTLE_OFF:
		d.angle = HoundLegs.turn(d.angle, to_p - signf(off) * SETTLE_OFF * .5, dt * 2.2)


## His player walking into him (pass 12): off their path, the side he is
## on, and on ahead of them. True when that was his tick.
static func make_way(
	h: Game.HoundScript, d: Game.HoundScript.Dog, p: Player, gap: float, dt: float
) -> bool:
	var pv := d.p_v.length()
	var off := Vector2(d.x - p.x, d.y - p.y)
	var coming := d.p_v.dot(off) > 0.0
	if pv <= .6 or gap >= h.n("heel_near") * (MAKE_WAY if coming else .8):
		return false
	var perp := Vector2(-d.p_v.y, d.p_v.x) / pv
	if perp.dot(off) < 0.0:
		perp = -perp
	# Off their path and on ahead of them a little quicker than they walk (a
	# wall that side: on ahead).
	d.speed = move_toward(d.speed, pv + h.n("amble") * .5, h.n("accel") * 1.5 * dt)
	h.stride(d, (perp * .7 + d.p_v / pv).angle(), maxf(d.speed, .4) * dt, dt, 1.2)
	return true
