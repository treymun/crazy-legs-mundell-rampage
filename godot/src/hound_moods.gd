## BLUE's ears, moods and rides (features/hound.gd, pass 10): what he hears
## (a twister, a siren), the moments that stop him (howling, growling,
## cowering, greeting, wagging round a still), and getting into a vehicle's
## free seat beside his player, riding along and hopping out, or jumping out
## of one's way. Play, carried in the hound's Dog: the same on every machine,
## dice only from game.rng.
class_name HoundMoods
extends RefCounted


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
	d.speed = 0.0
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
		h.head(d, p, Vector2(to.x, to.y), h.n("run"), dt)
	else:
		d.speed = 0.0
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
			h.head(d, p, d.goal, h.n("run"), dt)
			return
		d.bark_at = g.clock
		d.until = g.clock + h.n("treat_for")
		h.treats += 1
		g.sound_at("hound_yip", d.x, d.y, .9)
		return
	# Round it, a little circle at his nose's length.
	var a := atan2(d.y - d.look.y, d.x - d.look.x) + dt * 2.4 * d.side
	var round_at := d.look + Vector2(cos(a), sin(a)) * 1.0
	d.speed = h.n("trot")
	h.stride(d, atan2(round_at.y - d.y, round_at.x - d.x), h.n("trot") * dt, dt)
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
			down = Vector2(v.x, v.y)
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
		if moved < absf(step) * .3:
			# A wall that side: the other.
			h.shove(d, heading.y * step, -heading.x * step)
		if g.clock - d.bark_at > 1.2:
			d.bark_at = g.clock
			g.sound_at("hound_bark", d.x, d.y, .9)
