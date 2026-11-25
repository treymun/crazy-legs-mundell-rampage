## BLUE shows the way (pass 15, idea 2): a player calm and getting no nearer
## the objective for `lead_after` seconds (the walk to it, not the crow's
## flight) and BLUE takes the job LEAD: he lopes `lead_reach` cells down the
## way from them, turns back, barks and stands on point; as they come within
## `lead_near` he goes on another stretch. They get `lead_gain` cells nearer
## than they were stuck at (or near the objective): back on the way, he heels.
## A hand awake near, a mood, a vehicle or his player off after something
## else (out past `lead_far`, or `lead_wait` at a stop with them not coming)
## ends it; ignored, he tries again only after `lead_again`. Mundell says a
## "lost" line once a stuck spell. Without BLUE (HOUND DOG off) the objective
## pin pulses and Mundell's line is all (looks only, this machine's).
##
## Play: the job and its three Dog fields (lead_best, lead_at, lead_said) are
## carried with the Dog (a SIM feature; no dice). The walk from the objective
## is this object's, never carried: walked again in one go whenever what it
## was walked with changes (`sig`), so a game and its snapshot copy measure
## alike. Numbers in hound.cfg [lead]; docs/dev/gameplay.md "BLUE shows the way".
class_name HoundLead
extends RefCounted

## The walk to the objective from everywhere (doors as the pin takes them,
## barred ones one way), and what it was walked with.
var field: FlowField
var sig: Array = []
## Without BLUE: the local player's stuck spell, the pin's pulse, the line.
var best := -1
var since := 0.0
var said := false
var pulse_until := 0.0

static var _n := {}
## steps_at's "look again later" (a door swinging).
const NOT_NOW := -2
## Tools that measure his legs alone (hound_walk_check) turn it off.
static var ON := true


## A [lead] number from hound.cfg.
static func n(key: String) -> float:
	if not _n.has(key):
		var raw: Variant = Tuning.file(HoundNose.FILE).get_value("lead", key, 0.0)
		var v: float = raw
		_n[key] = v
	var got: float = _n[key]
	return got


## The hound feature's own (made on first asking; never carried).
static func of(h: Game.HoundScript) -> HoundLead:
	if h._lead == null:
		h._lead = HoundLead.new()
	return h._lead


## Steps from player p to the objective (FlowField.FAR when there is none or
## no way), the walk made again first if what it was walked with changed;
## NOT_NOW while a door swings (its leaf blocks the cells by it for a moment:
## the look waits, so a walk never depends on where a leaf was).
func steps_at(g: Game, p: Player) -> int:
	for door: LevelData.Door in g.world.doors:
		if door.progress > 0.0 and door.progress < 1.0:
			return NOT_NOW
	var found: Variant = g.objective_target()
	if found == null:
		return FlowField.FAR
	var t: Vector2 = found
	if field == null:
		field = FlowField.new(g.world, g.flow)
		field.reach = 100000
		field.doors_open = true
	var key := _sig(g, t)
	if key != sig:
		sig = key
		field.keys = g.keys
		field.origin = Vector2i(-1, -1)
		field.next_at = 0.0
		field.update(t.x, t.y, g.clock, g.world.goal_floor(t) if g.world.geo != null else NAN)
	return field.distance(p.x, p.y, g.world.stand(p))


## What the walk depends on: where to, the stations, the keys, the doors that
## open only by something (a secret found, a station, a key, a bar busted),
## the walls and the floor (a plain door at rest is no matter to it).
func _sig(g: Game, t: Vector2) -> Array:
	var out: Array = [int(t.x * 2.0), int(t.y * 2.0), g.stations_done.size(), g.keys.size()]
	var w := g.world
	for i in w.doors.size():
		var door: LevelData.Door = w.doors[i]
		if door.opened and (door.secret or door.key != "" or door.bar_side != 0):
			out.append(-1 - i)
		elif door.opened and (door.blast_only or w.controlled_doors.has(Vector2i(door.x, door.y))):
			out.append(-1 - i)
	out.append(w.walls_version)
	out.append(w.solid_version)
	out.append(hash(field.open))
	return out


## Whether it is a sample tick: every `lead_look` seconds of the game's clock
## (carried), so a snapshot copy samples on the same ticks.
static func sample(g: Game, dt: float) -> bool:
	var look := n("lead_look")
	return int(g.clock / look) != int((g.clock - dt) / look)


## Calm enough to lead: no hand awake within `lead_quiet`, his mood easy, his
## player on the ground, on foot, up and not in deep water.
static func calm(h: Game.HoundScript, d: Game.HoundScript.Dog, p: Player) -> bool:
	var g := h.game
	if d.mood != Game.HoundScript.CALM or p.health <= 0 or p.ladder >= 0:
		return false
	var rides: Game.VehiclesScript = g.features.get("vehicles")
	if rides != null and rides.seated(p):
		return false
	if g.world.stand(p) - g.world.elevation(p.x, p.y) > .6 or g.world.deep_at(p.x, p.y):
		return false
	return not HoundNose.fight_near(g, p.x, p.y, n("lead_quiet"))


## His tick while he goes with player p (Hound._with): true when leading took
## it (the caller only keeps him from being lost after).
static func lead(h: Game.HoundScript, d: Game.HoundScript.Dog, p: Player, dt: float) -> bool:
	var g := h.game
	var leading := d.job == Game.HoundScript.LEAD
	if not ON:
		return false
	var steps := of(h).steps_at(g, p) if sample(g, dt) and calm(h, d, p) else FlowField.FAR
	if sample(g, dt) and steps != NOT_NOW:
		if steps >= FlowField.FAR:
			d.lead_best = -1
			d.lead_at = g.clock
			if leading:
				_end(h, d, false)
			return false
		if leading:
			if steps <= d.lead_best - int(n("lead_gain")) or steps <= int(n("lead_least")):
				_end(h, d, true)
				d.lead_best = steps
				return false
		elif d.lead_best < 0 or steps < d.lead_best:
			d.lead_best = steps  # nearer: a new spell
			d.lead_at = g.clock
			d.lead_said = false
		elif g.clock - d.lead_at >= n("lead_after") and steps > int(n("lead_least")):
			leading = _start(h, d, p)
	if not leading:
		return false
	var q := HoundLegs.in_sights(g, d, h.n("clear_reach"), h.n("clear_cone"))
	if q != null and q != p:
		_end(h, d, false)  # in a partner's sights: out of them first
		return false
	_go(h, d, p, dt)
	return d.job == Game.HoundScript.LEAD


## Takes the job: the first stop down the way, and Mundell's word once.
static func _start(h: Game.HoundScript, d: Game.HoundScript.Dog, p: Player) -> bool:
	var g := h.game
	var stop := _stop(h, p, Vector2(p.x, p.y))
	if stop.is_empty():
		d.lead_at = g.clock + n("lead_again") - n("lead_after")
		return false
	d.job = Game.HoundScript.LEAD
	d.goal = stop[0]
	d.look = stop[1]
	d.until = 0.0
	d.roam = Vector2.INF
	if not d.lead_said:
		d.lead_said = true
		if p == g.player:
			g.barks.say(g, "lost", true)
	return true


## A stop `lead_reach` steps down the way from `from` (short of a shut door
## on it, never in harm, fair for him and, as he gets there, out of every
## player's sights): [where, what he points at], or [] when there is none.
static func _stop(h: Game.HoundScript, p: Player, from: Vector2) -> Array:
	var g := h.game
	var me := of(h)
	if me.field == null:
		return []
	var path: Array = []
	me.field.waypoint(from.x, from.y, int(n("lead_reach")) + 1, path, g.world.stand(p))
	var cells: Array = []
	for c: Vector2i in path:
		var shut := false
		for door: LevelData.Door in g.world.doors:
			if door.x == c.x and door.y == c.y and not door.opened:
				shut = true
		if shut:
			if cells.size() < 2:
				return [from, Vector2(c.x + .5, c.y + .5)]  # he waits by it, pointing
			break
		cells.append(c)
	if cells.size() < 2:
		return []
	var r := h.n("radius")
	var pad := h.n("harm_pad")
	var fallback: Array = []
	for i in range(mini(cells.size() - 1, int(n("lead_reach")) - 1), 0, -1):
		var c: Vector2i = cells[i]
		var on: Vector2i = cells[mini(i + 1, cells.size() - 1)]
		var ahead := Vector2(on.x + .5, on.y + .5)
		var centre := Vector2(c.x + .5, c.y + .5)
		var along := (ahead - centre).normalized() if ahead != centre else Vector2.RIGHT
		var aside := Vector2(-along.y, along.x)
		for off: float in [0.0, .55, -.55]:
			var at := centre + aside * off
			if not HoundLegs.fair(g, h._danger, p, at.x, at.y, r, pad):
				continue
			if fallback.is_empty():
				fallback = [at, ahead]
			if not HoundLegs.before_sights(g, at.x, at.y, h.n("clear_reach"), h.n("clear_cone")):
				return [at, ahead]
	return fallback


## Going to his stop, then turned back to his player with a bark, then on
## point down the way; on another stretch as they come near; given up when
## they go off or never come.
static func _go(h: Game.HoundScript, d: Game.HoundScript.Dog, p: Player, dt: float) -> void:
	var g := h.game
	var me := Vector2(d.x, d.y)
	var to_p := me.distance_to(Vector2(p.x, p.y))
	if to_p > n("lead_far") and (d.until > 0.0 or to_p > n("lead_far") + 3.0):
		_end(h, d, false)
		return
	var off := Vector2(p.x - d.x, p.y - d.y)
	if d.until > 0.0 and to_p > 4.0 and d.p_v.length() > 1.0 and d.p_v.dot(off) > 0.0:
		_end(h, d, false)  # his player walking off the other way: he comes along
		return
	if d.until <= 0.0:
		# On his way there (a stall or a shut way: he stops where he got to).
		if me.distance_to(d.goal) > .4 and d.stall < 1.5:
			h.head(d, p, d.goal, h.n("lope"), dt)
			return
		if d.speed > .3:
			h.halt(d, dt)
			return
		d.speed = 0.0
		d.until = g.clock + n("lead_wait")
		_bark(h, d)
		return
	if to_p <= n("lead_near") and sample(g, dt):
		var stop := _stop(h, p, me)
		if stop.is_empty():
			_end(h, d, true)  # the way runs out here: the objective is by
			return
		d.look = stop[1]
		var there: Vector2 = stop[0]
		if there.distance_to(me) > .4:
			d.goal = there
			d.until = 0.0
			return
		d.until = g.clock + n("lead_wait")  # a shut door: he waits by it for them
	if g.clock >= d.until:
		_end(h, d, false)
		return
	if (
		fmod(g.clock - (d.until - n("lead_wait")), n("lead_bark")) < dt
		and g.clock > d.bark_at + 1.0
	):
		_bark(h, d)
	h.halt(d, dt)
	# Turned back to his player a moment after a bark, then on point down the way.
	var face := Vector2(p.x, p.y) if g.clock - d.bark_at < .9 else d.look
	d.angle = HoundLegs.turn(d.angle, atan2(face.y - d.y, face.x - d.x), dt * 4.0)


static func _bark(h: Game.HoundScript, d: Game.HoundScript.Dog) -> void:
	d.bark_at = h.game.clock
	h.game.sound_at("hound_bark", d.x, d.y, .8)


## Off the job: back on the way (`found`, and the spell is over) or given up
## (tried again after `lead_again`).
static func _end(h: Game.HoundScript, d: Game.HoundScript.Dog, found: bool) -> void:
	var g := h.game
	if d.job == Game.HoundScript.LEAD:
		d.job = Game.HoundScript.HEEL
		d.job_until = g.clock + h.n("range_rest")
	d.goal = Vector2.INF
	d.look = Vector2.INF
	d.until = 0.0
	if found:
		d.lead_best = -1
		d.lead_at = g.clock
		d.lead_said = false
	else:
		d.lead_at = g.clock + n("lead_again") - n("lead_after")


# ------------------------------------------------------------- without BLUE


## Where the hounds would come but HOUND DOG is off: a campaign chapter, alone
## or in co-op (HoundNose.on less the setting).
static func place_ok(g: Game) -> bool:
	if g.level == null or g.in_hub or g.revisiting:
		return false
	if not Campaign.ORDER.has(g.level.id) or BossRematch.active(g):
		return false
	var mode := Modes.mode_of(g)
	return mode == Modes.CAMPAIGN or mode == Modes.COOP


## Without BLUE (the hound feature's tick with him off): the local player's
## stuck spell, looks only; false where there is nothing to watch.
static func alone(h: Game.HoundScript, dt: float) -> bool:
	var g := h.game
	if not ON or not place_ok(g):
		return false
	if not sample(g, dt):
		return true
	var me := of(h)
	var p := g.local_player
	var quiet := (
		p.health > 0
		and p.ladder < 0
		and not g.world.deep_at(p.x, p.y)
		and not HoundNose.fight_near(g, p.x, p.y, n("lead_quiet"))
	)
	var steps := me.steps_at(g, p) if quiet else FlowField.FAR
	if steps == NOT_NOW:
		return true
	if steps >= FlowField.FAR:
		me.best = -1
		me.since = g.clock
	elif me.best < 0 or steps < me.best:
		me.best = steps
		me.since = g.clock
		me.said = false
		me.pulse_until = 0.0
	elif g.clock - me.since >= n("lead_after") and steps > int(n("lead_least")):
		me.pulse_until = g.clock + n("pulse_for")
		me.since = g.clock + n("lead_again") - n("lead_after")
		if not me.said:
			me.said = true
			g.barks.say(g, "lost_pin", true)
	return true


## How the objective pin pulses now (0 none .. 1), HOUND DOG off and the
## player stuck (hud.gd objective_pin).
static func pulse(g: Game) -> float:
	var hound: Game.HoundScript = g.features.get("hound")
	if hound == null or hound.on or hound._lead == null:
		return 0.0
	var me: HoundLead = hound._lead
	if g.clock >= me.pulse_until:
		return 0.0
	return .5 + .5 * sin(g.clock * 9.0)
