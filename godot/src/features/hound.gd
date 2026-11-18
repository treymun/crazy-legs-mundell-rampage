## BLUE, Mundell's bluetick coonhound: one beside each player in a campaign
## chapter, alone or in co-op, with HOUND DOG on (HoundNose.on: not the
## Crossroads, the range, a boss rematch, County Run or the versus modes).
## Numbers in data/tuning/hound.cfg; docs/dev/gameplay.md "The hound".
##
## - He goes about like a hunting dog (pass 10): calm, he ranges out ahead
##   of his player to one side, noses about there and circles back to heel,
##   trotting, loping or running as it needs; never in a player's sights (he
##   steps aside when one aims his way); clear of hazards (HoundLegs). He
##   plans his way over the level's floor when he cannot walk straight, and
##   left far behind or with no way through he turns up behind his player
##   where nobody sees him come.
## - Vehicles: with a free seat beside his player at the wheel he gets in and
##   rides along (the airboat, the car), else he follows (the mower); one
##   coming at him, he jumps aside.
## - His nose: he bays at a secret door not found yet and at a gun his player
##   ain't got (GunFinder), points at a pickup lying where his player cannot
##   see it, growls at a hand awake his player cannot see, and wags round a
##   still or scrap.
## - He goes for a hand: told (the whistle with the sights on it), or on his
##   own one badly hurt or right on his player. He bites, never for the last
##   of its health; under `pin_below` he drags it down and holds it (it cannot
##   fight or walk) for the player to finish, until it kicks free. Not the
##   bosses or the ones that fly or swim; he keeps clear of a boss winding up
##   and lets go when badly hurt. The hands kick at him.
## - He fetches: told, the pickup the sights are on; on his own now and then
##   food when his player is hurt, rounds when their gun is nearly out.
## - Hurt to nothing he goes down, whining, and never dies: a player holding
##   USE beside him gets him up, a pork rind (USE with rinds in the pocket)
##   at once, and in time he gets himself up; up again, he greets them.
## - Moods: shot near, he sulks a while, trailing behind; a twister sends him
##   cowering at his player's side; a siren sets him howling now and then.
## - The whistle (WHISTLE FOR BLUE; online and for bots Controls.item ==
##   Game.HOUND_CALL): the sights on a hand, SIC 'EM; on a pickup, FETCH;
##   else STAY, and again COME.
##
## Play, the same on every machine: everything here is carried (a SIM
## feature) and its dice are game.rng's; his looks and the badge are drawn
## from it (HoundLooks), his sounds placed by the game's. What he does for
## the looks to read: Dog.state (the constants below), Dog.job (JOBS) and
## Dog.mood (MOODS); his voice's own moments are features/hound_voice.gd.
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
const HOWL := 9
const COWER := 10
const GREET := 11
const TREAT := 12
const GROWL := 13
const RIDE := 14
## What he is up to while he goes with his player (state FOLLOW): at heel,
## ranging out, nosing about where he ranged, circling back, running to
## catch up, stepping out of a player's sights, trailing behind (sulking),
## waiting where he cannot follow.
const HEEL := 0
const RANGE := 1
const NOSING := 2
const CIRCLE := 3
const CATCH := 4
const ASIDE := 5
const TRAIL := 6
const WAIT := 7
const JOBS := ["HEEL", "RANGE", "NOSING", "CIRCLE", "CATCH", "ASIDE", "TRAIL", "WAIT"]
## How he feels: calm, happy (a still, a greeting), alert (a hand about),
## scared (a twister), sulking (shot near), hurt (backed off a fight).
const CALM := 0
const HAPPY := 1
const ALERT := 2
const SCARED := 3
const SULK := 4
const HURT := 5
const MOODS := ["CALM", "HAPPY", "ALERT", "SCARED", "SULK", "HURT"]
## How often he asks again whether a way is straight (seconds).
const LOOK_AGAIN := .2


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
	## When he last got up from down (his looks play the getting up and
	## the shake after it from here).
	var up_at := -10.0
	var next_sniff := 0.0
	var next_fetch := 0.0
	var next_nose := 0.0
	var next_kick := 0.0
	var rest_until := 0.0
	var next_whine := 0.0
	var told := false
	var flash := 0.0
	## What he is up to with his player (JOBS) and till when; how he feels
	## (MOODS) and till when.
	var job := 0
	var job_until := 0.0
	var mood := 0
	var mood_until := 0.0
	## Where he ranges to (Vector2.INF: nowhere yet).
	var roam := Vector2.INF
	## How fast he goes now (cells a second): he eases into a pace.
	var speed := 0.0
	## His planned way (cell centres, nearest first), where to and when.
	var path := PackedVector2Array()
	var path_goal := Vector2.INF
	var plan_at := -10.0
	## Whether the last plan found no way; when the next few steps of it were
	## last pulled straight.
	var no_way := false
	var pull_at := -10.0
	## Whether he can walk straight to `straight_goal`, asked at `straight_at`.
	var straight := false
	var straight_at := -10.0
	var straight_goal := Vector2.INF
	## How long he has wanted to go somewhere and not got there: where he
	## stood at the last look (every half second) and when that was.
	var stall := 0.0
	var anchor := Vector2.INF
	var anchor_at := 0.0
	## A leap he is in the air for (into a seat, down off one): where to, on
	## what floor (Vector2.INF: none).
	var hop := Vector2.INF
	var hop_z := 0.0
	## Out of a player's sights: the way he steps; how his player's sights
	## turn (radians a second, eased) and where they pointed last tick.
	var aside := Vector2.ZERO
	var p_turn := 0.0
	var p_angle := 0.0
	## The vehicle he rides in (its place in vehicles.rides; -1 none).
	var ride := -1
	var next_howl := 0.0
	var next_growl := 0.0
	## No hand awake near his player at his last sniff.
	var calm := true


## The hounds, one a player who has one.
var dogs: Array = []
## Whether they come along in this game (HoundNose.on, asked on the first
## tick), and whether that was asked.
var on := false
var asked := false
## What they have bayed, pointed and wagged at: HoundNose.key -> when.
var bayed := {}
## The hands a hound has growled at (uid -> true).
var warned := {}
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
var asides := 0
var jumps := 0
var hops := 0
var rode := 0
var howls := 0
var growls := 0
var treats := 0
var sulks := 0
var cowers := 0
var greets := 0
var backed_off := 0
## The body moved through the level for a hound, the numbers read once, the
## level's standing hazards, this tick's dangers and the scratch field ways
## are planned on (never carried: SnapCodec SKIP_FIELDS; all of it made
## again from the level and the tick).
var _body: Enemy
var _probe: Enemy
var _n := {}
var _harms: Array = []
var _harms_read := false
var _danger: Array = []
var _bosses: Array = []
var _bosses_of := -1
var _field: FlowField


func id() -> String:
	return "hound"


func attach() -> void:
	_body = Enemy.new("coot")
	_body.variant = 1.0
	_probe = Enemy.new("coot")
	_probe.variant = 1.0
	for key: String in Tuning.file(HoundNose.FILE).get_section_keys("hound"):
		_n[key] = HoundNose.tuned(key)
	game.events.enemy_killed.connect(_killed)
	game.events.exploded.connect(_blast)
	game.events.shot_fired.connect(_shot)
	tick_with(_tick)


func detach() -> void:
	_body = null
	_probe = null
	_field = null
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
		into(d, DOWN if down == 1 else FOLLOW)
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
	if not _harms_read:
		_harms_read = true
		_harms = HoundLegs.harms_of(game, n("harm_pad"))
	if game.enemies.size() != _bosses_of:
		# The bosses, looked for again only when the hands come or go.
		_bosses_of = game.enemies.size()
		_bosses = []
		for e: Enemy in game.enemies:
			if Enemy.BOSS_TITLES.has(e.kind):
				_bosses.append(e)
	_danger = HoundLegs.dangers(game, _harms, n("telegraph_reach"), _bosses)
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
	d.job_until = game.clock + n("range_rest")
	into(d, FOLLOW)
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


func into(d: Dog, state: int) -> void:
	if d.state == PIN and state != PIN:
		# The hand he held stands up again.
		var held := HoundNose.enemy_of(game, d.foe)
		if held != null:
			held.held_cel = ""
	if state != RIDE:
		d.ride = -1
	d.state = state
	d.since = game.clock
	d.until = 0.0
	d.path = PackedVector2Array()
	d.straight_at = -10.0
	d.stall = 0.0
	d.anchor = Vector2.INF
	d.hop = Vector2.INF
	if state == FOLLOW or state == STAY or state == DOWN:
		d.foe = 0
		d.goal_uid = 0
		d.goal = Vector2.INF
		d.look = Vector2.INF
		d.told = false
	if state == FOLLOW:
		d.job = HEEL
		d.roam = Vector2.INF


func _step(d: Dog, p: Player, dt: float) -> void:
	d.flash = maxf(0.0, d.flash - dt)
	d.pace = 0.0
	if d.mood != CALM and game.clock >= d.mood_until:
		d.mood = CALM
	if d.hop != Vector2.INF and d.state != RIDE:
		# Down off a seat: in the air till he lands.
		if leap(d, d.hop, d.hop_z, dt):
			d.hop = Vector2.INF
		return
	if d.state != RIDE:
		HoundMoods.clear_of_rides(self, d, dt)
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
			head(d, p, Vector2(p.x, p.y), n("run"), dt)
		if d.state != STAY:
			_drop(d, p)
			into(d, STAY)
		return
	if d.state != RIDE and d.stall > 0.0:
		# Stalled: caught inside something (a prop's corner, a door shut on
		# him)? Out.
		var free := HoundLegs.unstuck(game, _probe, d, n("radius"))
		if free != Vector2.INF:
			d.x = free.x
			d.y = free.y
	if d.state != PIN and d.state != RIDE and _out_of_harm(d, p, dt):
		return
	match d.state:
		FOLLOW:
			_with(d, p, dt)
		STAY:
			pass
		SIC, PIN:
			_fight(d, p, dt)
		FETCH, CARRY:
			_fetch(d, p, dt)
		BAY, POINT:
			_nose(d, p, dt)
		HOWL, GROWL:
			HoundMoods.standing(self, d, p, dt)
		COWER:
			HoundMoods.cower(self, d, p, dt)
		GREET:
			HoundMoods.greet(self, d, p, dt)
		TREAT:
			HoundMoods.treat(self, d, p, dt)
		RIDE:
			HoundMoods.riding(self, d, p, dt)


## Standing in harm (a boss's aim come down on him, fire, a twister coming
## over), he gets out of it first: away from the danger he is in, or to his
## player. True when that was his tick.
func _out_of_harm(d: Dog, p: Player, dt: float) -> bool:
	if not HoundLegs.harm(game, _danger, d.x, d.y):
		return false
	var away := Vector2.ZERO
	for c: Vector3 in _danger:
		var off := Vector2(d.x - c.x, d.y - c.y)
		if off.length() < c.z:
			away += off.normalized() * (c.z - off.length() + .2)
	# Out of it, leaning toward his player (not down the road a car comes up).
	var to_p := Vector2(p.x - d.x, p.y - d.y).normalized()
	var heading := to_p.angle() if away == Vector2.ZERO else (away.normalized() + to_p * .6).angle()
	d.speed = n("run")
	stride(d, heading, n("run") * dt, dt)
	return true


# ------------------------------------------------------- with his player


## Going with his player: into a vehicle beside them, out of their sights,
## catching up, sulking behind, at heel when there is trouble about, and
## else ranging out and circling back; his nose and his ears on the way.
func _with(d: Dog, p: Player, dt: float) -> void:
	var rides: Game.VehiclesScript = game.features.get("vehicles")
	var driving := rides != null and rides.seated(p)
	if driving and HoundMoods.board(self, d, p, rides, dt):
		return
	if HoundMoods.hear(self, d, p):
		return
	if game.clock >= d.next_sniff:
		d.next_sniff = game.clock + n("sniff_every")
		d.calm = not HoundNose.fight_near(game, p.x, p.y, 10.0)
		_sniff(d, p)
		if d.state != FOLLOW:
			return
	var gap := Vector2(p.x - d.x, p.y - d.y).length()
	var turned := wrapf(p.angle - d.p_angle, -PI, PI) / maxf(dt, .0001)
	d.p_turn = lerpf(d.p_turn, turned, .3)
	d.p_angle = p.angle
	# Out of a player's sights before all else.
	if d.job != ASIDE or game.clock >= d.job_until:
		HoundMoods.aside(self, d, p)
		if d.job != ASIDE or game.clock >= d.job_until:
			if d.job == ASIDE:
				_job(d, HEEL, n("range_rest"))
	if d.job == ASIDE:
		d.speed = maxf(d.speed, n("lope"))
		stride(d, d.aside.angle(), n("run") * dt, dt)
		_find_way(d, p, gap, dt)
		return
	var calm := d.calm and d.mood == CALM
	if gap > n("catch_far") or (d.job == CATCH and gap > 2.5):
		d.job = CATCH
	elif d.job == CATCH:
		_job(d, HEEL, n("range_rest"))
	elif d.mood == SULK:
		d.job = TRAIL
	elif d.job == TRAIL:
		_job(d, HEEL, n("range_rest"))
	elif not calm or driving:
		if d.job != HEEL and d.job != WAIT:
			_job(d, HEEL, n("range_rest"))
	_range(d, p, gap, calm and not driving)
	match d.job:
		HEEL, WAIT:
			_heel(d, p, gap, n("heel"), dt)
		RANGE:
			var fast := Vector2(p.vx, p.vy).length() > 2.6
			head(d, p, d.roam, n("lope") if fast else n("trot"), dt)
		NOSING:
			d.speed = 0.0
		CIRCLE:
			var spot := HoundLegs.heel_spot(game, d, p, n("heel"), n("radius"))
			var pace := n("run") if gap > n("run_past") + 2.0 else n("lope")
			head(d, p, spot, pace, dt)
		CATCH:
			head(d, p, HoundLegs.heel_spot(game, d, p, n("heel"), n("radius")), n("run"), dt)
		TRAIL:
			_heel(d, p, gap, n("sulk_heel"), dt)
	_find_way(d, p, gap, dt)


## Sets his job and how long it holds at least.
func _job(d: Dog, job: int, hold: float) -> void:
	d.job = job
	d.job_until = game.clock + hold
	if job != RANGE:
		d.roam = Vector2.INF


## The ranging round: at heel a while, out to a spot ahead and to one side
## (somewhere fair, out of every player's sights), nosing about there, and
## back to heel. Only when it is calm (`free`); his dice are game.rng's.
func _range(d: Dog, p: Player, gap: float, free: bool) -> void:
	var now := game.clock
	match d.job:
		HEEL:
			if not free or now < d.job_until or gap > n("run_past"):
				return
			var moving := Vector2(p.vx, p.vy)
			var still := moving.length() < .6
			var base := p.angle if still else moving.angle()
			var spot := HoundLegs.roam_spot(
				game,
				_danger,
				p,
				base,
				d.side,
				n("range_near_still") if still else n("range_near"),
				n("range_far_still") if still else n("range_far"),
				n("range_side_min"),
				PI * .8 if still else n("range_side_max"),
				_n
			)
			if spot == Vector2.INF:
				d.job_until = now + 1.0
				return
			d.roam = spot
			d.side = -d.side
			d.job = RANGE
			d.job_until = now + n("range_for")
		RANGE:
			var there := Vector2(d.x, d.y).distance_to(d.roam) < .6
			var behind := (
				Vector2(d.roam.x - p.x, d.roam.y - p.y).dot(Vector2(p.vx, p.vy)) < -2.0
				and Vector2(p.vx, p.vy).length() > 1.0
			)
			if there:
				_job(d, NOSING, n("sniff_stop") + game.rng.random() * n("sniff_stop_more"))
			elif now >= d.job_until or behind or gap > n("catch_far") * .8 or not free:
				_job(d, CIRCLE, 0.0)
			elif HoundLegs.before_sights(
				game, d.roam.x, d.roam.y, n("clear_reach"), n("clear_cone")
			):
				_job(d, CIRCLE, 0.0)
		NOSING:
			if now >= d.job_until or not free:
				_job(d, CIRCLE, 0.0)
		CIRCLE:
			var spot := HoundLegs.heel_spot(game, d, p, n("heel"), n("radius"))
			if Vector2(d.x, d.y).distance_to(spot) < 1.2:
				_job(d, HEEL, n("range_rest") + game.rng.random() * n("range_rest_more"))


## At heel `back` behind his player, off to his side: a run when far, a trot
## near, his face to his player once there.
func _heel(d: Dog, p: Player, gap: float, back: float, dt: float) -> void:
	var spot := HoundLegs.heel_spot(game, d, p, back, n("radius"))
	var to_spot := Vector2(spot.x - d.x, spot.y - d.y).length()
	if to_spot > .3:
		var pace := n("run") if gap > n("run_past") else n("trot")
		if d.mood == SULK:
			pace = n("sulk_pace")
		var moved := head(d, p, spot, pace, dt)
		if gap > 2.0 and moved < pace * dt * .2 and d.path.is_empty():
			d.side = -d.side  # that side is shut: the other
	else:
		d.speed = 0.0
		d.angle = HoundLegs.turn(d.angle, atan2(p.y - d.y, p.x - d.x), dt * 3.0)


## Lost: too far and out of everyone's sight (or no way to them) for long,
## he turns up behind his player where nobody sees him come; truly stuck
## where nobody looks, he hops on along his way.
func _find_way(d: Dog, p: Player, to_p: float, dt: float) -> void:
	var cut_off := (
		to_p > n("lost_far")
		or (to_p > 4.0 and d.no_way)
		or (to_p > 4.0 and p.flow != null and p.flow.distance(d.x, d.y, d.floor_z) >= FlowField.FAR)
	)
	# Whether anybody sees him is only asked when it matters (a sight test).
	var asks := cut_off or (d.stall >= n("unstick") and not d.path.is_empty())
	var hid := asks and not HoundLegs.seen(game, d.x, d.y, d.floor_z)
	if cut_off and hid:
		d.lost += dt
	else:
		d.lost = maxf(0.0, d.lost - dt)
	if d.lost >= n("lost_for") and game.world.stand(p) - game.world.elevation(p.x, p.y) > .6:
		# Up a ladder or on a roof: he waits for them below.
		d.lost = 0.0
	if d.lost >= n("lost_for"):
		d.lost = 0.0
		var at := HoundLegs.hidden_spot(
			game, _danger, p, n("hide_near"), n("hide_far"), n("radius"), n("harm_pad")
		)
		if at != Vector2.INF:
			_put(d, at, game.world.floor_under(at.x, at.y, game.world.stand(p) + .5))
			d.angle = p.angle
			jumps += 1
			_job(d, HEEL, n("range_rest"))
		else:
			d.job = WAIT
		return
	if d.stall >= n("unstick") and hid and not d.path.is_empty():
		# Caught on something nobody can see: on to the next step of his way.
		var next := d.path[mini(1, d.path.size() - 1)]
		if not HoundLegs.seen(game, next.x, next.y, d.floor_z):
			_put(d, next, game.world.floor_under(next.x, next.y, d.floor_z + .5))
			hops += 1


func _put(d: Dog, at: Vector2, floor_z: float) -> void:
	d.x = at.x
	d.y = at.y
	d.floor_z = floor_z
	d.path = PackedVector2Array()
	d.straight_at = -10.0
	d.stall = 0.0
	d.anchor = Vector2.INF
	d.speed = 0.0


## A leap toward `to` (on a floor at `z`) at his hop's speed, over what is in
## the way (into a vehicle's seat, down off it): true once there.
func leap(d: Dog, to: Vector2, z: float, dt: float) -> bool:
	var off := to - Vector2(d.x, d.y)
	var most := n("ride_hop") * 1.3 * dt
	d.angle = HoundLegs.turn(d.angle, off.angle(), dt * 12.0)
	d.gait += minf(most, off.length()) * 3.4
	if off.length() <= most:
		d.x = to.x
		d.y = to.y
		d.floor_z = z
		return true
	var step := off.normalized() * most
	d.x += step.x
	d.y += step.y
	d.floor_z = move_toward(d.floor_z, z, absf(z - d.floor_z) * most / off.length())
	d.pace = most / maxf(dt, .0001)
	return false


# ------------------------------------------------------------ getting about


## Toward `goal` at `pace` (he eases into it): straight where he can walk
## straight, else along a way planned over the level's floor, else down his
## player's flow field. Returns how far he went.
func head(d: Dog, p: Player, goal: Vector2, pace: float, dt: float) -> float:
	if goal == Vector2.INF:
		return 0.0
	var gap := Vector2(goal.x - d.x, goal.y - d.y).length()
	var ease := n("accel") * dt * (1.0 if pace >= d.speed else 1.6)
	d.speed = move_toward(d.speed, pace, ease)
	if gap < .2:
		d.speed = 0.0
		d.stall = 0.0
		d.anchor = Vector2.INF
		return 0.0
	_stalled(d)
	var heading := _way(d, p, goal)
	var length := minf(gap, maxf(d.speed, .8) * dt * Mud.pace(game, d.x, d.y))
	return stride(d, heading, length, dt)


## One stride of `length` along `heading` (or the nearest way round), with
## his gait and how long he has stalled kept.
func stride(d: Dog, heading: float, length: float, dt: float) -> float:
	var went: Array = HoundLegs.step(game, _body, _danger, d, heading, length, n("radius"))
	var moved: float = went[0]
	var took: float = went[1]
	if length > .002 and moved <= 0.0:
		d.stall = maxf(d.stall, .01)  # not an inch: caught on something?
	if moved > .0005:
		d.pace = moved / maxf(dt, .0001)
		# Radians a cell, changing where his looks go from trot to gallop.
		d.gait += moved * (3.4 if d.pace > HoundLooks.GALLOP_FROM else 6.5)
		d.angle = HoundLegs.turn(d.angle, took, dt * 10.0)
	return moved


## Every half second he wants to go somewhere: under a third of his pace's
## way from where he stood the last look (shut in, or to and fro on the
## spot), he has stalled that long more, and plans his way again.
func _stalled(d: Dog) -> void:
	var here := Vector2(d.x, d.y)
	if d.anchor == Vector2.INF:
		d.anchor = here
		d.anchor_at = game.clock
		return
	var span := game.clock - d.anchor_at
	if span < .5:
		return
	if here.distance_to(d.anchor) < maxf(.12, d.speed * span * .3):
		d.stall += span
		if d.stall >= n("stall_for"):
			d.plan_at = -10.0
	else:
		d.stall = 0.0
	d.anchor = here
	d.anchor_at = game.clock


## The heading toward `goal`: straight when the way is clear, else along
## his planned way (planned again when the goal moves, it is old or he
## stalls), else down his player's flow field, else straight.
func _way(d: Dog, p: Player, goal: Vector2) -> float:
	var r := n("radius")
	# Whether he can walk straight there, asked again every LOOK_AGAIN or when
	# the goal has moved (his strides keep out of harm between).
	if game.clock - d.straight_at >= LOOK_AGAIN or d.straight_goal.distance_to(goal) > .6:
		d.straight = HoundLegs.walk_clear(game, _probe, _danger, d, goal.x, goal.y, r)
		d.straight_at = game.clock
		d.straight_goal = goal
	if d.straight:
		d.path = PackedVector2Array()
		d.no_way = false
		return atan2(goal.y - d.y, goal.x - d.x)
	var since := game.clock - d.plan_at
	var stale := d.path.is_empty() or d.path_goal.distance_to(goal) > 2.5 or since > n("replan")
	if stale and since > (.6 if d.no_way else .35):
		if _field == null:
			_field = FlowField.new(game.world, p.flow)
		var goal_z := game.world.floor_under(goal.x, goal.y, game.world.stand(p) + .5)
		d.path = HoundLegs.plan(game, _field, _harms, d, p, goal, goal_z, int(n("plan_reach")))
		d.path_goal = goal
		d.plan_at = game.clock
		d.no_way = d.path.is_empty() and Vector2(goal.x - d.x, goal.y - d.y).length() > 1.0
		d.pull_at = -10.0
	while not d.path.is_empty() and Vector2(d.path[0].x - d.x, d.path[0].y - d.y).length() < .45:
		d.path.remove_at(0)
		d.pull_at = -10.0
	if not d.path.is_empty():
		# The furthest of the next few steps he can walk straight to (asked
		# when the way changes, and every LOOK_AGAIN).
		if game.clock - d.pull_at >= LOOK_AGAIN:
			d.pull_at = game.clock
			for i in range(mini(4, d.path.size()) - 1, 0, -1):
				if HoundLegs.walk_clear(game, _probe, _danger, d, d.path[i].x, d.path[i].y, r):
					d.path = d.path.slice(i)
					break
		return atan2(d.path[0].y - d.y, d.path[0].x - d.x)
	if Vector2(goal.x - d.x, goal.y - d.y).length() < 1.5:
		return atan2(goal.y - d.y, goal.x - d.x)  # the last of the way
	if p.flow != null and Vector2(goal.x - p.x, goal.y - p.y).length() < 3.0:
		var lead := p.flow.heading(d.x, d.y, d.floor_z)
		if not is_nan(lead):
			return lead
	return atan2(goal.y - d.y, goal.x - d.x)


## Moves him by (dx, dy) as a body of the level goes (a shove, a hop
## aside): how far he went.
func shove(d: Dog, dx: float, dy: float) -> float:
	return HoundLegs.move(game, _body, d, dx, dy, n("radius"))


func _shot(gun: int) -> void:
	HoundMoods.shot(self, gun)


# ------------------------------------------------------------- his nose


## What his nose finds while he goes with his player, in turn: a hand to go
## for, a hand awake round a corner, a secret door, new iron, a pickup out of
## his player's sight, a still or scrap, something to fetch.
func _sniff(d: Dog, p: Player) -> void:
	if game.clock >= d.rest_until and d.health > n("health") * n("brave") and d.mood != HURT:
		var foe := HoundNose.foe_near(
			game, d.x, d.y, d.floor_z, p, n("fight_reach"), n("pin_below"), _taken(d), _danger
		)
		if foe != null:
			_sic(d, foe, false)
			return
	if game.clock >= d.next_growl and d.mood != SCARED:
		var lurk := HoundNose.unseen_foe(game, d.x, d.y, p, n("growl_reach"), warned)
		if lurk != null:
			warned[lurk.uid] = true
			d.next_growl = game.clock + n("growl_rest")
			into(d, GROWL)
			d.look = Vector2(lurk.x, lurk.y)
			d.until = game.clock + n("growl_for")
			d.mood = ALERT
			d.mood_until = game.clock + 6.0
			growls += 1
			game.sound_at("hound_growl_low", d.x, d.y, .8)
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
	var treat := HoundNose.treat_near(game, d.x, d.y, d.floor_z, n("treat_reach"), bayed)
	if treat != Vector2.INF:
		bayed[HoundNose.key(treat)] = game.clock
		_seek(d, TREAT, _short_of(d, treat, 1.0), treat)
		d.mood = HAPPY
		d.mood_until = game.clock + 8.0
		if p == game.player and HoundNose.still_at(game, treat):
			game.barks.say(game, "hound_shine")
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
	into(d, state)
	# Never a spot in harm (a pickup by a burn barrel): further back.
	var back := goal - look
	if back.length() > .01:
		for k in 5:
			if not HoundLegs.harm(game, _danger, goal.x, goal.y):
				break
			goal += back.normalized() * .6
	d.goal = goal
	d.look = look
	d.until = game.clock + 6.0


## Going to bay or point, then baying or pointing; back to heel after.
func _nose(d: Dog, p: Player, dt: float) -> void:
	if Vector2(p.x - d.x, p.y - d.y).length() > n("catch_far"):
		into(d, FOLLOW)  # his player has gone on without him
		return
	var gap := Vector2(d.goal.x - d.x, d.goal.y - d.y).length()
	if d.bark_at < d.since:
		# Not yet at it: on his way (a few seconds at most; from where he is
		# when the way there is shut).
		if gap > .35 and game.clock < d.since + 3.0 and d.stall < .8:
			head(d, p, d.goal, n("run"), dt)
			return
		d.speed = 0.0
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
		if p == game.player:
			game.barks.say(game, "hound_praise")
	d.angle = HoundLegs.turn(d.angle, atan2(d.look.y - d.y, d.look.x - d.x), dt * 6.0)
	if game.clock >= d.until:
		into(d, FOLLOW)


# ------------------------------------------------------------- fighting


func _sic(d: Dog, foe: Enemy, told: bool) -> void:
	_drop(d, game.players[d.slot])
	into(d, SIC)
	d.foe = foe.uid
	d.told = told
	d.until = game.clock + 12.0
	d.bite_at = game.clock + .2
	if not foe.alerted:
		foe.alerted = true


## After a hand: run at it, bite; badly hurt, down it goes and he holds it.
## Badly hurt himself, he lets go and keeps behind his player a while.
func _fight(d: Dog, p: Player, dt: float) -> void:
	var e := HoundNose.enemy_of(game, d.foe)
	if e == null or not HoundNose.takes(e) or game.clock >= d.until:
		_let_go(d, e)
		return
	if d.health < n("health") * n("back_off"):
		_let_go(d, e)
		d.mood = HURT
		d.mood_until = game.clock + n("back_off_for")
		d.rest_until = game.clock + n("back_off_for")
		backed_off += 1
		game.sound_at("hound_whine", d.x, d.y, .8)
		return
	var gap := Vector2(e.x - d.x, e.y - d.y).length()
	var reach := e.radius + n("radius") + .3
	if d.state == SIC:
		if gap > reach:
			if not game.world.visible(d.x, d.y, e.x, e.y, d.floor_z + .4, game.world.stand(e) + .6):
				if game.clock - d.since > 3.0:
					_let_go(d, e)
					return
			if d.stall > 2.0:
				_let_go(d, e)  # no way to it (a hazard, a ledge)
				return
			head(d, p, Vector2(e.x, e.y), n("run"), dt)
			if game.clock - d.bark_at > 1.1:
				d.bark_at = game.clock
				game.sound_at("hound_bark", d.x, d.y, .9)
			return
		d.speed = 0.0
		d.angle = atan2(e.y - d.y, e.x - d.x)
		if game.clock >= d.bite_at:
			d.bite_at = game.clock + n("bite_every")
			_bite(d, e, n("bite"))
			if e.hp <= e.max_hp * n("pin_below"):
				into(d, PIN)
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
		head(d, p, Vector2(e.x, e.y), n("run"), dt)
	else:
		d.speed = 0.0
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
	into(d, FOLLOW)


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
	if game.clock < d.next_kick or d.state == RIDE:
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
	if d.state == RIDE:
		into(d, FOLLOW)
	var away := atan2(d.y - y, d.x - x)
	shove(d, cos(away) * n("kick_shove"), sin(away) * n("kick_shove"))
	if d.health > 0.0:
		game.sound_at("hound_yelp", d.x, d.y, 1.0)
		return
	d.health = 0.0
	downs += 1
	if d.slot < game.players.size():
		var p: Player = game.players[d.slot]
		_drop(d, p)
		if p == game.player:
			game.barks.say(game, "hound_down")
	game.sound_at("hound_yelp", d.x, d.y, 1.0)
	into(d, DOWN)
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
			_up(d, n("revive_health"), helper)
			if helper == game.player:
				game.barks.say(game, "hound_greet")
	else:
		d.revive = maxf(0.0, d.revive - dt * .5)
	if d.state == DOWN and game.clock - d.down_at >= n("get_up"):
		_up(d, n("get_up_health"), null)


## Up again with `health`: a bark, and he greets `helper` (his own player
## when he got up himself).
func _up(d: Dog, health: float, helper: Player) -> void:
	revives += 1
	d.up_at = game.clock
	d.health = health
	d.hurt_at = game.clock
	d.rest_until = game.clock + n("rest_after_fight")
	into(d, GREET)
	d.goal_uid = helper.slot if helper != null else d.slot
	d.until = game.clock + n("greet_for")
	d.mood = HAPPY
	d.mood_until = game.clock + 8.0
	greets += 1
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
	_up(d, n("rind_health"), p)
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
		return "BLUE'S DOWN - %s: FEED HIM A RIND" % game.use_key
	return "BLUE'S DOWN - HOLD %s" % game.use_key


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
	into(d, FETCH)
	var uid: int = entry[3]
	d.goal_uid = uid
	d.told = told
	d.until = game.clock + 12.0


func _fetch(d: Dog, p: Player, dt: float) -> void:
	if d.state == FETCH:
		var i := HoundNose.pickup_at(game, d.goal_uid)
		if i < 0 or game.clock >= d.until:
			into(d, FOLLOW)  # somebody took it, or he could not get to it
			return
		var entry: Array = game.pickups[i]
		var px: float = entry[1]
		var py: float = entry[2]
		if Vector2(px - d.x, py - d.y).length() > .45:
			head(d, p, Vector2(px, py), n("run"), dt)
			return
		d.item = str(entry[0])
		game.pickups.remove_at(i)
		into(d, CARRY)
		d.until = game.clock + 30.0
		game.sound_at("hound_boof", d.x, d.y, .5)
		return
	# Carrying it back to his player's feet.
	var gap := Vector2(p.x - d.x, p.y - d.y).length()
	if gap > .95 and game.clock < d.until:
		head(d, p, Vector2(p.x, p.y), n("run"), dt)
		return
	var item := d.item
	_drop(d, p)
	fetches += 1
	game.sound_at("hound_bark", d.x, d.y, .6)
	if p == game.player:
		game.barks.say(game, "hound_good")
	_tell(p, "BLUE FETCHED YOU %s." % str(GameState.PICKUP_NAMES.get(item, item.to_upper())))
	d.bark_at = game.clock
	into(d, FOLLOW)


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
	if d.state == RIDE:
		return  # riding along: he stays put in his seat
	if d.state == FOLLOW:
		_drop(d, p)
		into(d, STAY)
		_say(p, "hound_stay", "STAY, BLUE.")
		return
	_drop(d, p)
	into(d, FOLLOW)
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


# ----------------------------------------------------------------- looks


## The frame his model shows (actors.json "hound"; HoundLooks.pose).
func frame(d: Dog) -> String:
	var now: String = HoundLooks.pose(self, d)[0]
	return now


func sprites() -> Array:
	if not on:
		return []
	return HoundLooks.sprites(self)


## BLUE's badge keeps the view's bottom left corner (ui/hud/hud_layout.gd).
func hud_fixed(layout: HudLayout) -> void:
	HoundLooks.lay_fixed(self, layout)


## GETTIN' BLUE UP while a hand is on him.
func hud_flow(layout: HudLayout) -> void:
	HoundLooks.lay_flow(self, layout)


func draw_view(c: Canvas) -> void:
	HoundLooks.draw(self, c)
