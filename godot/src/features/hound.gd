## BLUE, Mundell's bluetick coonhound: one beside each player in a campaign
## chapter, alone or in co-op, with HOUND DOG on (HoundNose.on: not the
## Crossroads, the range, a boss rematch, County Run or the versus modes).
## Numbers in data/tuning/hound.cfg; docs/dev/gameplay.md "The hound".
##
## - He heels behind his player, off to one side, out of their line of fire;
##   left behind he runs to catch up, and lost (no way through, far out of
##   sight) he turns up behind them.
## - His nose: he bays at a secret door not found yet and at a gun his player
##   ain't got (GunFinder), and points at a pickup lying where his player
##   cannot see it.
## - He goes for a hand: told (the whistle with the sights on it), or on his
##   own one badly hurt or right on top of his player. He bites, never for
##   the last of its health; under `pin_below` he drags it down and holds it
##   (it cannot fight or walk) for the player to finish, until it kicks free.
##   Not the bosses or the ones that fly or swim. The hands kick at him.
## - He fetches: told, the pickup the sights are on; on his own now and then
##   food when his player is hurt, rounds when their gun is nearly out. He
##   drops it at their feet.
## - Hurt to nothing he goes down, whining, and never dies: a player holding
##   USE beside him gets him up, a pork rind (USE with rinds in the pocket)
##   at once, and in time he gets himself up.
## - The whistle (WHISTLE FOR BLUE; online and for bots Controls.item ==
##   Game.HOUND_CALL): the sights on a hand, SIC 'EM; on a pickup, FETCH;
##   else STAY, and again COME.
##
## Play, the same on every machine: everything here is carried (a SIM
## feature) and its dice are game.rng's; his looks and the badge are drawn
## from it (HoundLooks), his sounds placed by the game's.
extends GameFeature

const FOLLOW := 0
const STAY := 1
const SIC := 2
const PIN := 3
const FETCH := 4
const CARRY := 5
const BAY := 6
const POINT := 7
const DOWN := 8
## His words on the badge for what he is up to.
const WORDS := ["", "STAY", "SIC", "HELD", "FETCH", "FETCH", "BAYIN'", "POINT", "DOWN"]


## One hound: his player's slot, where he is and what he is doing.
class Dog:
	var slot := 0
	var x := 0.0
	var y := 0.0
	var floor_z := 0.0
	var angle := 0.0
	var gait := 0.0
	## How fast he went last tick (cells a second): his walk or his run.
	var pace := 0.0
	var health := 100.0
	var state := 0
	var since := 0.0
	var until := 0.0
	## The hand he is after or holds (a uid; 0 none), and the pickup he goes
	## for (its uid) and what he carries ("" nothing).
	var foe := 0
	var goal_uid := 0
	var item := ""
	## Where he goes (bay, point) and what he faces there.
	var goal := Vector2.INF
	var look := Vector2.INF
	## The side of his player he heels on (1 or -1).
	var side := 1.0
	var hurt_at := -10.0
	var bite_at := 0.0
	var bark_at := -10.0
	var lost := 0.0
	var revive := 0.0
	var down_at := -1.0
	var next_sniff := 0.0
	var next_fetch := 0.0
	var next_nose := 0.0
	var next_kick := 0.0
	var rest_until := 0.0
	var next_whine := 0.0
	var told := false
	var flash := 0.0


## The hounds, one a player who has one.
var dogs: Array = []
## Whether they come along in this game (HoundNose.on, asked on the first
## tick), and whether that was asked.
var on := false
var asked := false
## What they have bayed and pointed at: HoundNose.key -> when.
var bayed := {}
## How often they did things (the tools read them).
var bays := 0
var points := 0
var bites := 0
var pins := 0
var finished := 0
var fetches := 0
var downs := 0
var revives := 0
var kicks := 0
## The body moved through the level for a hound (never carried: SnapCodec
## SKIP_FIELDS), and the numbers, read once.
var _body: Enemy
var _n := {}


func id() -> String:
	return "hound"


func attach() -> void:
	_body = Enemy.new("coot")
	_body.variant = 1.0
	for key: String in Tuning.file(HoundNose.FILE).get_section_keys("hound"):
		_n[key] = HoundNose.tuned(key)
	game.events.enemy_killed.connect(_killed)
	game.events.exploded.connect(_blast)
	tick_with(_tick)


func detach() -> void:
	_body = null
	super()


func save() -> Dictionary:
	if dogs.is_empty():
		return {}
	var rows: Array = []
	for d: Dog in dogs:
		var down := d.state == DOWN
		rows.append([d.slot, d.x, d.y, d.angle, d.health, 1 if down else 0, d.item])
	return {"dogs": rows, "bayed": bayed.keys()}


func restore(state: Dictionary) -> void:
	dogs = []
	bayed = {}
	for k: Variant in state.get("bayed", []):
		bayed[str(k)] = 0.0
	for row: Variant in state.get("dogs", []):
		var r: Array = row if row is Array else []
		if r.size() < 7:
			continue
		var d := Dog.new()
		d.slot = r[0]
		d.x = r[1]
		d.y = r[2]
		d.angle = r[3]
		d.health = r[4]
		var down: int = r[5]
		d.item = str(r[6])
		d.floor_z = game.world.floor_under(d.x, d.y, game.world.elevation(d.x, d.y) + 1.0)
		_into(d, DOWN if down == 1 else FOLLOW)
		if down == 1:
			d.down_at = game.clock
		dogs.append(d)


func tally_rows() -> Array:
	if dogs.is_empty() or pins + fetches + bays + points == 0:
		return []
	return [["BLUE", "%d FETCHED  %d HELD" % [fetches, pins]]]


## A number from hound.cfg.
func n(key: String) -> float:
	var v: float = _n.get(key, 0.0)
	return v


## Player p's hound, or null.
func dog_of(p: Player) -> Dog:
	for d: Dog in dogs:
		if d.slot == p.slot:
			return d
	return null


# ------------------------------------------------------------------ the tick


func _tick(dt: float) -> void:
	if not asked:
		asked = true
		on = HoundNose.on(game)
	if not on:
		sleep()
		return
	for p: Player in game.players:
		if p.away or dog_of(p) != null:
			continue
		dogs.append(_spawn(p))
	for d: Dog in dogs:
		if d.slot >= game.players.size():
			continue
		var p: Player = game.players[d.slot]
		if p.away:
			continue
		_step(d, p, dt)


## A new hound at player p's heel.
func _spawn(p: Player) -> Dog:
	var d := Dog.new()
	d.slot = p.slot
	d.health = n("health")
	d.side = 1.0 if p.slot % 2 == 0 else -1.0
	var at := _behind(p, d.side)
	d.x = at.x
	d.y = at.y
	d.angle = p.angle
	d.floor_z = game.world.floor_under(d.x, d.y, game.world.stand(p) + .4)
	d.next_fetch = game.clock + n("fetch_every")
	_into(d, FOLLOW)
	return d


## A spot behind player p, off to `side`, that a hound fits (beside them
## when nothing behind is open).
func _behind(p: Player, side: float) -> Vector2:
	var r := n("radius")
	for back: float in [n("heel"), .9, .5]:
		for s: float in [side, -side, 0.0]:
			var a := p.angle + PI - s * .55
			var at := Vector2(p.x + cos(a) * back, p.y + sin(a) * back)
			if game.world.blocked(at.x, at.y, r) or game.world.deep_at(at.x, at.y):
				continue
			if game.world.visible(p.x, p.y, at.x, at.y):
				return at
	return Vector2(p.x, p.y)


func _into(d: Dog, state: int) -> void:
	if d.state == PIN and state != PIN:
		# The hand he held stands up again.
		var held := HoundNose.enemy_of(game, d.foe)
		if held != null:
			held.held_cel = ""
	d.state = state
	d.since = game.clock
	d.until = 0.0
	if state == FOLLOW or state == STAY or state == DOWN:
		d.foe = 0
		d.goal_uid = 0
		d.goal = Vector2.INF
		d.look = Vector2.INF
		d.told = false


func _step(d: Dog, p: Player, dt: float) -> void:
	d.flash = maxf(0.0, d.flash - dt)
	d.pace = 0.0
	_clear_of_rides(d, dt)
	if d.state == DOWN:
		_lying(d, dt)
		return
	if game.clock - d.hurt_at > n("mend_after"):
		d.health = minf(n("health"), d.health + n("mend") * dt)
	_kicks(d, p, dt)
	if d.state == DOWN:
		return
	if p.health <= 0:
		# His player is down: he goes to them and lies by them.
		var gap := Vector2(p.x - d.x, p.y - d.y).length()
		if gap > 1.0:
			_go(d, p, p.x, p.y, n("run"), dt)
		if d.state != STAY:
			_drop(d, p)
			_into(d, STAY)
		return
	match d.state:
		FOLLOW:
			_heel(d, p, dt)
		STAY:
			pass
		SIC, PIN:
			_fight(d, p, dt)
		FETCH, CARRY:
			_fetch(d, p, dt)
		BAY, POINT:
			_nose(d, p, dt)


## Heeling: to his spot behind his player, a run when far, the flow field
## round walls; a sniff now and then.
func _heel(d: Dog, p: Player, dt: float) -> void:
	var spot := _heel_spot(d, p)
	var to_spot := Vector2(spot.x - d.x, spot.y - d.y).length()
	var to_p := Vector2(p.x - d.x, p.y - d.y).length()
	if to_spot > .3:
		var pace := n("run") if to_p > n("run_past") else n("walk")
		var moved := _go(d, p, spot.x, spot.y, pace, dt)
		if to_p > 2.0 and moved < pace * dt * .2:
			d.side = -d.side  # that side is shut: the other
	else:
		d.angle = _turn(d.angle, atan2(p.y - d.y, p.x - d.x), dt * 3.0)
	_find_way(d, p, to_p, dt)
	if game.clock >= d.next_sniff:
		d.next_sniff = game.clock + n("sniff_every")
		_sniff(d, p)


## His place behind his player: behind and to his side, and out of their
## sights if he is in front. His player at the wheel: behind the vehicle.
func _heel_spot(d: Dog, p: Player) -> Vector2:
	var back := n("heel")
	var rides: Game.VehiclesScript = game.features.get("vehicles")
	if rides != null and rides.seated(p):
		var v: VehicleDrive.Ride = rides.rides[rides.seat_of(p).x]
		var s := VehicleDrive.spec(v.kind)
		var tail := s.length * .5 + back
		var aside := d.side * s.width * .3
		return Vector2(
			v.x - cos(v.h) * tail - sin(v.h) * aside, v.y - sin(v.h) * tail + cos(v.h) * aside
		)
	var a := p.angle + PI - d.side * .5
	var spot := Vector2(p.x + cos(a) * back, p.y + sin(a) * back)
	if game.world.blocked(spot.x, spot.y, n("radius")):
		var b := p.angle + PI
		spot = Vector2(p.x + cos(b) * back * .7, p.y + sin(b) * back * .7)
	return spot


## Lost: too far and out of their sight (or no way to them) for long, he
## turns up behind them.
func _find_way(d: Dog, p: Player, to_p: float, dt: float) -> void:
	var stuck := (
		to_p > n("lost_far")
		or (to_p > 4.0 and p.flow != null and p.flow.distance(d.x, d.y, d.floor_z) >= FlowField.FAR)
	)
	if stuck and not game.world.visible(p.x, p.y, d.x, d.y, p.eye, d.floor_z + .4):
		d.lost += dt
	else:
		d.lost = maxf(0.0, d.lost - dt)
	if d.lost >= n("lost_for") and game.world.stand(p) - game.world.elevation(p.x, p.y) > .6:
		# Up a ladder or on a roof: he waits for them below.
		d.lost = 0.0
	if d.lost >= n("lost_for"):
		d.lost = 0.0
		var at := _behind(p, d.side)
		d.x = at.x
		d.y = at.y
		d.floor_z = game.world.floor_under(d.x, d.y, game.world.stand(p) + .4)
		d.angle = p.angle


## What his nose finds while he heels, in turn: a hand to go for, a secret
## door, new iron, a pickup out of his player's sight, something to fetch.
func _sniff(d: Dog, p: Player) -> void:
	if game.clock >= d.rest_until and d.health > n("health") * n("brave"):
		var foe := HoundNose.foe_near(
			game, d.x, d.y, d.floor_z, p, n("fight_reach"), n("pin_below"), _taken(d)
		)
		if foe != null:
			_sic(d, foe, false)
			return
	if HoundNose.fight_near(game, p.x, p.y, 10.0):
		return
	var to_p := Vector2(p.x - d.x, p.y - d.y).length()
	if to_p > n("bay_owner") or game.clock < d.next_nose:
		return
	var door := HoundNose.secret_near(game, d.x, d.y, d.floor_z, n("bay_reach"), bayed)
	if not door.is_empty():
		var front: Vector2 = door[0]
		var mid: Vector2 = door[1]
		bayed[HoundNose.key(mid)] = game.clock
		_seek(d, BAY, front, mid)
		d.next_nose = game.clock + n("bay_rest")
		return
	var iron := HoundNose.iron_near(game, p, d.x, d.y, d.floor_z, n("bay_reach"), bayed)
	if iron != Vector2.INF:
		bayed[HoundNose.key(iron)] = game.clock
		_seek(d, BAY, _short_of(d, iron, .9), iron)
		d.next_nose = game.clock + n("bay_rest")
		return
	var hid := HoundNose.hidden_near(game, p, d.x, d.y, d.floor_z, n("point_reach"), bayed)
	if hid >= 0:
		var entry: Array = game.pickups[hid]
		var hx: float = entry[1]
		var hy: float = entry[2]
		var at := Vector2(hx, hy)
		bayed[HoundNose.key(at)] = game.clock
		_seek(d, POINT, _short_of(d, at, 1.2), at)
		d.next_nose = game.clock + n("point_rest")
		return
	if game.clock >= d.next_fetch:
		d.next_fetch = game.clock + n("fetch_every") + game.rng.random() * n("fetch_every_more")
		var want := HoundNose.wanted_near(
			game, p, d.x, d.y, d.floor_z, n("fetch_own_reach"), n("fetch_hungry")
		)
		if want >= 0:
			_go_fetch(d, want, false)


## The hands the other hounds are after or hold.
func _taken(me: Dog) -> Dictionary:
	var out := {}
	for d: Dog in dogs:
		if d != me and (d.state == SIC or d.state == PIN):
			out[d.foe] = true
	return out


## A point `short` of `at` on his side of it.
func _short_of(d: Dog, at: Vector2, short: float) -> Vector2:
	var from := Vector2(d.x, d.y)
	var gap := from.distance_to(at)
	if gap <= short:
		return from
	return at + (from - at) / gap * short


func _seek(d: Dog, state: int, goal: Vector2, look: Vector2) -> void:
	_into(d, state)
	d.goal = goal
	d.look = look
	d.until = game.clock + 6.0


# ------------------------------------------------------------- his nose


## Going to bay or point, then baying or pointing; back to heel after.
func _nose(d: Dog, p: Player, dt: float) -> void:
	if Vector2(p.x - d.x, p.y - d.y).length() > n("bay_owner") * 1.6:
		_into(d, FOLLOW)
		return
	var gap := Vector2(d.goal.x - d.x, d.goal.y - d.y).length()
	if d.bark_at < d.since:
		# Not yet at it: on his way (a few seconds at most).
		if gap > .35 and game.clock < d.until:
			_go(d, p, d.goal.x, d.goal.y, n("run"), dt)
			return
		d.bark_at = game.clock
		d.until = game.clock + (n("bay_for") if d.state == BAY else n("point_for"))
		if d.state == BAY:
			bays += 1
			game.sound_at("hound_bay", d.x, d.y, 1.0)
			_tell(p, "BLUE'S BAYIN' AT SOMETHIN'.")
		else:
			points += 1
			game.sound_at("hound_boof", d.x, d.y, .8)
			_tell(p, "BLUE'S ON POINT. SOMETHIN' OVER THERE.")
	d.angle = _turn(d.angle, atan2(d.look.y - d.y, d.look.x - d.x), dt * 6.0)
	if game.clock >= d.until:
		_into(d, FOLLOW)


# ------------------------------------------------------------- fighting


func _sic(d: Dog, foe: Enemy, told: bool) -> void:
	_drop(d, game.players[d.slot])
	_into(d, SIC)
	d.foe = foe.uid
	d.told = told
	d.until = game.clock + 12.0
	d.bite_at = game.clock + .2
	if not foe.alerted:
		foe.alerted = true


## After a hand: run at it, bite; badly hurt, down it goes and he holds it.
func _fight(d: Dog, p: Player, dt: float) -> void:
	var e := HoundNose.enemy_of(game, d.foe)
	if e == null or not HoundNose.takes(e) or game.clock >= d.until:
		_let_go(d, e)
		return
	var gap := Vector2(e.x - d.x, e.y - d.y).length()
	var reach := e.radius + n("radius") + .3
	if d.state == SIC:
		if gap > reach:
			if not game.world.visible(d.x, d.y, e.x, e.y, d.floor_z + .4, game.world.stand(e) + .6):
				if game.clock - d.since > 3.0:
					_let_go(d, e)
					return
			_go(d, p, e.x, e.y, n("run"), dt)
			if game.clock - d.bark_at > 1.1:
				d.bark_at = game.clock
				game.sound_at("hound_bark", d.x, d.y, .9)
			return
		d.angle = atan2(e.y - d.y, e.x - d.x)
		if game.clock >= d.bite_at:
			d.bite_at = game.clock + n("bite_every")
			_bite(d, e, n("bite"))
			if e.hp <= e.max_hp * n("pin_below"):
				_into(d, PIN)
				d.foe = e.uid
				d.until = game.clock + n("pin_time")
				pins += 1
				game.sound_at("hound_growl", d.x, d.y, 1.0)
				_tell(p, "BLUE'S GOT HIM! FINISH HIM!")
		return
	# Holding it: it cannot fight or walk; he worries it, it kicks at him.
	e.stun = maxf(e.stun, .2)
	e.windup = 0.0
	e.aim_mark = null
	e.volley = 0
	e.hp = maxf(1.0, e.hp - n("pin_bite") * dt)
	# Dragged half down, leaning back from his player (so their shots land on
	# what they see), twisting in pain now and then.
	e.angle = atan2(p.y - e.y, p.x - e.x)
	var twist := fmod(game.clock + e.uid * .37, 1.1) >= .8
	e.held_cel = Variants.stem(e.kind) + ("_pain" if twist else "_die_1")
	var hold := e.radius + n("radius") + .1
	if gap > hold + .2:
		_go(d, p, e.x, e.y, n("run"), dt)
	else:
		d.angle = atan2(e.y - d.y, e.x - d.x)
	if game.clock - d.bark_at > 1.6:
		d.bark_at = game.clock
		game.sound_at("hound_growl", d.x, d.y, .8)
	if game.clock >= d.until:
		# It kicks free.
		_hurt(d, n("kick"), e.x, e.y)
		e.stun = 0.0
		_let_go(d, e)


## A bite: a share of its health, never the last of it (the kill is a
## player's), a flinch and a little blood.
func _bite(d: Dog, e: Enemy, amount: float) -> void:
	bites += 1
	e.hp = maxf(1.0, e.hp - amount)
	e.hit_flash = minf(.18, e.hit_flash + .1)
	e.flinch = maxf(e.flinch, .18)
	e.stun = maxf(e.stun, .15)
	e.windup = 0.0
	var base := game.world.stand(e)
	game.burst(e.x, e.y, base + .4, "gore", 4, 1.1)
	game.sound_at("hound_bite", d.x, d.y, .9)


func _let_go(d: Dog, _e: Enemy) -> void:
	d.rest_until = game.clock + n("rest_after_fight")
	_into(d, FOLLOW)


## A hand died: the one he held was finished by a player.
func _killed(e: Enemy) -> void:
	for d: Dog in dogs:
		if (d.state == PIN or d.state == SIC) and d.foe == e.uid:
			e.held_cel = ""
			if d.state == PIN:
				finished += 1
				if d.slot < game.players.size():
					var p: Player = game.players[d.slot]
					if p == game.player:
						game.barks.say(game, "hound_good")
			game.sound_at("hound_bark", d.x, d.y, .9)
			d.bark_at = game.clock
			_let_go(d, e)


# --------------------------------------------------------- getting hurt


## The hands near him kick at him now and then (the one he holds too).
func _kicks(d: Dog, p: Player, dt: float) -> void:
	if game.clock < d.next_kick:
		return
	var reach := n("kick_reach")
	for e: Enemy in game.enemies:
		if absf(e.x - d.x) > reach + .4 or absf(e.y - d.y) > reach + .4:
			continue
		if not (e.alive and e.hostile and e.alerted and not e.dormant):
			continue
		var held := d.state == PIN and e.uid == d.foe
		if (e.stun > 0.0 and not held) or Enemy.BOSS_TITLES.has(e.kind):
			continue
		if Vector2(e.x - d.x, e.y - d.y).length() > reach + e.radius:
			continue
		if game.rng.random() >= n("kick_rate") * dt * (.7 if held else 1.0):
			continue
		kicks += 1
		d.next_kick = game.clock + .8
		e.angle = atan2(d.y - e.y, d.x - e.x)
		e.recovery = e.recovery_time()
		_hurt(d, n("kick"), e.x, e.y)
		if d.state == DOWN:
			_tell(p, "BLUE'S DOWN! GIT HIM UP!")
		return


func _blast(x: float, y: float, _z: float, _energy: bool) -> void:
	for d: Dog in dogs:
		if d.state == DOWN:
			continue
		var gap := Vector2(d.x - x, d.y - y).length()
		if gap < n("blast_reach"):
			_hurt(d, n("blast") * (1.0 - gap / n("blast_reach")), x, y)


## Hurt by `amount` from (x, y): a yelp, a shove away; at nothing he goes
## down where he is.
func _hurt(d: Dog, amount: float, x: float, y: float) -> void:
	if d.state == DOWN or amount <= 0.0:
		return
	d.health -= amount
	d.hurt_at = game.clock
	d.flash = .18
	var away := atan2(d.y - y, d.x - x)
	_shove(d, cos(away) * n("kick_shove"), sin(away) * n("kick_shove"))
	if d.health > 0.0:
		game.sound_at("hound_yelp", d.x, d.y, 1.0)
		return
	d.health = 0.0
	downs += 1
	if d.slot < game.players.size():
		_drop(d, game.players[d.slot])
	game.sound_at("hound_yelp", d.x, d.y, 1.0)
	_into(d, DOWN)
	d.down_at = game.clock
	d.revive = 0.0
	d.next_whine = game.clock + 1.2


## Down: he whines; a player holding USE beside him gets him up, and in time
## he gets up himself.
func _lying(d: Dog, dt: float) -> void:
	if game.clock >= d.next_whine:
		d.next_whine = game.clock + 3.2
		game.sound_at("hound_whine", d.x, d.y, .9)
	var helper: Player = null
	for q: Player in game.players:
		if (
			q.health > 0
			and not q.away
			and q.holding
			and Vector2(q.x - d.x, q.y - d.y).length() < n("revive_reach")
		):
			helper = q
			break
	if helper != null:
		d.revive += dt
		if d.revive >= n("revive_time"):
			_up(d, n("revive_health"))
	else:
		d.revive = maxf(0.0, d.revive - dt * .5)
	if d.state == DOWN and game.clock - d.down_at >= n("get_up"):
		_up(d, n("get_up_health"))


func _up(d: Dog, health: float) -> void:
	revives += 1
	d.health = health
	d.hurt_at = game.clock
	d.rest_until = game.clock + n("rest_after_fight")
	_into(d, FOLLOW)
	game.sound_at("hound_bark", d.x, d.y, .8)


## USE beside a downed hound with a pork rind in the pocket: he eats it and
## is up at once. True when that is what USE did (game_use.gd).
func use(p: Player) -> bool:
	var d := _down_near(p)
	if d == null:
		return false
	var have: int = p.inventory.get("rinds", 0)
	if have <= 0:
		return false
	p.inventory["rinds"] = have - 1
	_up(d, n("rind_health"))
	game.sound_at("crunch", d.x, d.y, .8)
	if p == game.player:
		game.barks.say(game, "hound_up", true)
	_tell(p, "BLUE WOLFED THE RIND. GOOD BOY.")
	return true


## USE's prompt beside a downed hound ("" none).
func prompt(p: Player) -> String:
	var d := _down_near(p)
	if d == null:
		return ""
	var have: int = p.inventory.get("rinds", 0)
	if have > 0:
		return "%s: FEED BLUE A RIND" % game.use_key
	return "HOLD %s: GET BLUE UP" % game.use_key


func _down_near(p: Player) -> Dog:
	if not on or p.health <= 0:
		return null
	for d: Dog in dogs:
		if d.state == DOWN and Vector2(p.x - d.x, p.y - d.y).length() < n("revive_reach"):
			return d
	return null


# -------------------------------------------------------------- fetching


func _go_fetch(d: Dog, i: int, told: bool) -> void:
	var entry: Array = game.pickups[i]
	if entry.size() <= 3:
		return
	_into(d, FETCH)
	var uid: int = entry[3]
	d.goal_uid = uid
	d.told = told
	d.until = game.clock + 12.0


func _fetch(d: Dog, p: Player, dt: float) -> void:
	if d.state == FETCH:
		var i := HoundNose.pickup_at(game, d.goal_uid)
		if i < 0 or game.clock >= d.until:
			_into(d, FOLLOW)  # somebody took it, or he could not get to it
			return
		var entry: Array = game.pickups[i]
		var px: float = entry[1]
		var py: float = entry[2]
		if Vector2(px - d.x, py - d.y).length() > .45:
			_go(d, p, px, py, n("run"), dt)
			return
		d.item = str(entry[0])
		game.pickups.remove_at(i)
		_into(d, CARRY)
		d.until = game.clock + 30.0
		game.sound_at("hound_boof", d.x, d.y, .5)
		return
	# Carrying it back to his player's feet.
	var gap := Vector2(p.x - d.x, p.y - d.y).length()
	if gap > .95 and game.clock < d.until:
		_go(d, p, p.x, p.y, n("run"), dt)
		return
	var item := d.item
	_drop(d, p)
	fetches += 1
	game.sound_at("hound_bark", d.x, d.y, .6)
	if p == game.player:
		game.barks.say(game, "hound_good")
	_tell(p, "BLUE FETCHED YOU %s." % str(GameState.PICKUP_NAMES.get(item, item.to_upper())))
	d.bark_at = game.clock
	_into(d, FOLLOW)


## What he carries, put down at his player's feet (where he is, if far).
func _drop(d: Dog, p: Player) -> void:
	if d.item == "":
		return
	var at := Vector2(d.x, d.y)
	if Vector2(p.x - d.x, p.y - d.y).length() < 1.6 and p.health > 0:
		at = Vector2(p.x + cos(p.angle) * .3, p.y + sin(p.angle) * .3)
	game.add_pickup(d.item, at.x, at.y, d.floor_z)
	d.item = ""


# ----------------------------------------------------------- the whistle


## Player p whistles: SIC 'EM on the hand their sights are on, FETCH the
## pickup they are on, else STAY, and again COME.
func command(p: Player) -> void:
	if not on or p.health <= 0:
		return
	var d := dog_of(p)
	if d == null:
		return
	game.sound_at("hound_whistle", p.x, p.y, .8)
	if d.state == DOWN:
		_tell(p, "BLUE'S HURT. HOLD %s BESIDE HIM." % game.use_key)
		return
	var foe := HoundNose.aimed_foe(game, p, n("sic_reach"), n("aim_cone"))
	if foe != null:
		_sic(d, foe, true)
		_say(p, "hound_sic", "SIC 'EM, BLUE!")
		return
	var i := HoundNose.aimed_pickup(game, p, n("fetch_reach"), n("aim_cone"))
	if i >= 0 and d.item == "":
		_go_fetch(d, i, true)
		_say(p, "hound_fetch", "GO FETCH, BLUE.")
		return
	if d.state == FOLLOW:
		_drop(d, p)
		_into(d, STAY)
		_say(p, "hound_stay", "STAY, BLUE.")
		return
	_drop(d, p)
	_into(d, FOLLOW)
	d.rest_until = game.clock + 1.5
	_say(p, "hound_come", "BLUE! HERE, BOY!")


## Mundell's word to his hound, said by the one who whistled (shown when it
## cannot be said).
func _say(p: Player, category: String, line: String) -> void:
	if p != game.local_player:
		return
	if game.player == p and game.barks.say(game, category, true):
		return
	_tell(p, line)


## A notice for player p's eyes only.
func _tell(p: Player, text: String) -> void:
	if p == game.local_player:
		game.notice = text
		game.message_until = game.clock + 2.2


# ---------------------------------------------------------------- moving


## Toward (tx, ty) at `pace`: straight when he can see it, else down his
## player's flow field when the point is theirs; sliding round what is in
## the way. Returns how far he went.
func _go(d: Dog, p: Player, tx: float, ty: float, pace: float, dt: float) -> float:
	var heading := atan2(ty - d.y, tx - d.x)
	var near_p := Vector2(tx - p.x, ty - p.y).length() < 2.5
	if (
		near_p
		and p.flow != null
		and not game.world.visible(d.x, d.y, tx, ty, d.floor_z + .4, game.world.stand(p) + .4)
	):
		var lead := p.flow.heading(d.x, d.y, d.floor_z)
		if not is_nan(lead):
			heading = lead
	var gap := Vector2(tx - d.x, ty - d.y).length()
	var step := minf(gap, pace * dt * Mud.pace(game, d.x, d.y))
	var moved := _move(d, cos(heading) * step, sin(heading) * step)
	if moved < step * .3:
		for turn: float in [.7, -.7, 1.3, -1.3]:
			moved = _move(d, cos(heading + turn) * step, sin(heading + turn) * step)
			if moved > step * .3:
				heading += turn
				break
	if moved > .0005:
		d.pace = moved / maxf(dt, .0001)
		d.gait += moved * (3.4 if d.pace > 4.0 else 6.5)
		d.angle = _turn(d.angle, heading, dt * 10.0)
	return moved


## A vehicle coming at him: he jumps aside, off its line; one on him shoves
## him out of its hull (vehicles run hands down, never BLUE).
func _clear_of_rides(d: Dog, dt: float) -> void:
	var rides: Game.VehiclesScript = game.features.get("vehicles")
	if rides == null:
		return
	for v: VehicleDrive.Ride in rides.rides:
		if v.wreck >= 0.0:
			continue
		var s := VehicleDrive.spec(v.kind)
		var reach := s.length * .5 + n("ride_reach") + 1.0
		if absf(d.x - v.x) > reach or absf(d.y - v.y) > reach:
			continue
		var push := VehicleDrive.out_of(s, v, d.x, d.y, n("radius"))
		if push != Vector2.INF:
			_move(d, push.x, push.y)
			continue
		var speed := VehicleDrive.speed(v)
		if speed < n("ride_from") or d.state == DOWN:
			continue
		var heading := Vector2(v.vx, v.vy) / speed
		var rel := Vector2(d.x - v.x, d.y - v.y)
		var ahead := rel.dot(heading) - s.length * .5
		var side := rel.dot(Vector2(-heading.y, heading.x))
		if ahead < -.2 or ahead > n("ride_reach") or absf(side) > s.width * .5 + .6:
			continue
		var away := 1.0 if side > 0.0 or (side == 0.0 and d.slot % 2 == 0) else -1.0
		var step := n("ride_hop") * dt * away
		var moved := _move(d, -heading.y * step, heading.x * step)
		if moved < absf(step) * .3:
			# A wall that side: the other.
			_move(d, heading.y * step, -heading.x * step)
		if game.clock - d.bark_at > 1.2:
			d.bark_at = game.clock
			game.sound_at("hound_bark", d.x, d.y, .9)


func _move(d: Dog, dx: float, dy: float) -> float:
	var r := n("radius")
	_body.x = d.x
	_body.y = d.y
	_body.floor_z = d.floor_z
	_body.radius = r
	game.world.move(_body, dx, dy, r)
	var moved := Vector2(_body.x - d.x, _body.y - d.y).length()
	d.x = _body.x
	d.y = _body.y
	d.floor_z = _body.floor_z
	return moved


func _shove(d: Dog, dx: float, dy: float) -> void:
	_move(d, dx, dy)


static func _turn(from: float, to: float, most: float) -> float:
	var delta := wrapf(to - from, -PI, PI)
	return from + clampf(delta, -most, most)


# ----------------------------------------------------------------- looks


## The frame his model shows (scripts/blender/actors_hound.py).
func frame(d: Dog) -> String:
	var now := game.clock
	if d.state == DOWN:
		return "down" if now - d.down_at < 1.6 or fmod(now - d.down_at, 6.0) < 1.2 else "whine"
	if now - d.hurt_at < .35:
		return "pain"
	if d.pace > 4.0:
		return "r0"
	if d.pace > .3:
		return "w0"
	match d.state:
		STAY:
			return "sit"
		PIN:
			return "pin" if fmod(now, .5) < .25 else "pin2"
		SIC:
			return "bite" if now - (d.bite_at - n("bite_every")) < .25 else "bark"
		BAY:
			return "bay" if d.bark_at >= d.since else "sniff"
		POINT:
			return "point" if d.bark_at >= d.since else "sniff"
		CARRY:
			return "fetch"
	if d.item != "":
		return "fetch"
	if now - d.bark_at < .3:
		return "bark"
	if d.slot < game.players.size():
		var p: Player = game.players[d.slot]
		if p.health <= 0:
			return "whine"
	return "0" if fmod(now + d.slot * .37, 1.1) < .55 else "wag"


func sprites() -> Array:
	var out: Array = []
	if not on:
		return out
	for d: Dog in dogs:
		if d.slot >= game.players.size() or game.players[d.slot].away:
			continue
		if not game.in_view(d.x, d.y, 1.2):
			continue
		var f := frame(d)
		# Holding a hand, his body is drawn set back from it (looks only): at
		# the hold's gap his reared-up head and paws stood inside its chest.
		var back := HoundLooks.PIN_BACK if d.state == PIN else 0.0
		var bx := d.x - cos(d.angle) * back
		var by := d.y - sin(d.angle) * back
		out.append(HoundLooks.body(game, d.slot, bx, by, d.floor_z, d.angle, d.gait, f, d.flash))
		if d.item != "":
			out.append(HoundLooks.carried(game, d.item, d.x, d.y, d.floor_z, d.angle))
	return out


## BLUE's badge keeps the view's bottom left corner (ui/hud/hud_layout.gd).
func hud_fixed(layout: HudLayout) -> void:
	if on and game.local_player != null and dog_of(game.local_player) != null:
		layout.take("badge", HoundLooks.rect())


func draw_view(c: Canvas) -> void:
	if not on or game.local_player == null:
		return
	var d := dog_of(game.local_player)
	if d == null:
		return
	HudLayout.begin(c, "badge")
	var face := "0"
	if d.state == DOWN:
		face = "down"
	elif game.clock - d.hurt_at < 1.0 or d.health < n("health") * .3:
		face = "2"
	elif d.state == SIC or d.state == PIN or d.state == BAY or d.state == POINT:
		face = "1"
	var word: String = WORDS[d.state]
	HoundLooks.badge(game, c, d.health / n("health"), face, word, d.state == DOWN)
	HudLayout.end(c)
