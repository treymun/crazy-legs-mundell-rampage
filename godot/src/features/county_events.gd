## County events (content pass 8): now and then a campaign chapter gets one
## thing nobody planned, so no two runs through it go the same:
##
## - a twister (src/event_twister.gd) touches down out past the town and comes
##   across, pulling in whoever is out under the sky, tearing loose things off
##   their places and barns down round it, and lifts again: get under a roof;
## - a stampede (src/event_herd.gd): a herd of razorbacks comes down a street
##   or a field, trampling the hands and the player and bowling things over;
## - a revenue raid (src/event_raid.gd): revenue men storm a still or the
##   county's hands, fighting them and the player alike;
## - a blackout (src/event_dark.gd), in the night chapters: the lights go out,
##   every player gets a flashlight (L) on a battery, some hands carry
##   lanterns, the dark hides a player who keeps the light off, and the power
##   comes back in time or at the main breaker.
##
## At most one a chapter, never in a boss fight or near a boss, never where
## the level is the hub, the range or the Mothership. Whether a chapter gets
## one, which and when are picked on the first tick with game.rng (EVENTS:
## OFF, SOMETIMES, OFTEN; off, no die is cast and play is as it was). Play,
## the same on every machine: a SIM feature, every variable carried, saved in
## the save's features block (the raiders join the enemies after the level's
## own, which features/posse.gd saves). The sights and sounds are
## features/event_looks.gd's and the 3D view's. Numbers: data/tuning/events.cfg.
class_name CountyEvents
extends GameFeature

const FILE := "res://data/tuning/events.cfg"
const OFF := 0
const SOMETIMES := 1
const OFTEN := 2
## How many tries to start before the chapter's event is let go.
const TRIES := 8

## The EVENTS setting as this game has it (0 off), read on the first tick.
var on := 0
var asked := false
## This chapter's event ("" none), when it may start, and how many tries.
var planned := ""
var plan_at := -1.0
var tries := 0
## The one running ("" none), its phase, when that began, and whether this
## chapter's is spent (run or let go).
var kind := ""
var phase := 0
var since := 0.0
var spent := false
## How many of each ran (the checks and the tally read them).
var ran := {}

## The twister: where it touched down and where it leaves, where it is, how
## far along, how strong (0 a rope in the cloud .. 1 full), and its timers.
var tw_from := Vector2.ZERO
var tw_to := Vector2.ZERO
var tw_at := Vector2.ZERO
var tw_run := 0.0
var tw_k := 0.0
var tw_bite := 0.0
var tw_rip := 0.0
var tw_fling := 0.0
var tw_aim := -1
## The herd: each hog [x, y, angle, gait, state, side, floor]; the run's
## start, way and length; who was trampled when ("p<slot>", "e<uid>").
var herd: Array = []
var herd_from := Vector2.ZERO
var herd_way := Vector2.RIGHT
var herd_len := 0.0
var trampled := {}
## The raid: the spot stormed, the still there (a breakables piece, -1), the
## raiders (indexes into game.enemies), the last shots [x0, y0, z0, x1, y1,
## z1, clock], whether the still was busted.
var raid_at := Vector2.ZERO
var raid_still := -1
var raiders: Array = []
var raid_shots: Array = []
var busted := false
var raid_look := 0.0
## The blackout: the power on, when it comes back by itself, the breaker
## [x, y, facing], each player slot's flashlight [on (1/0), battery], the
## hands with lanterns (indexes into game.enemies).
var power := true
var back_at := 0.0
var breaker := Vector3.INF
var torches: Array = []
var lanterns: Array = []

## The body moved through the level for a hog (never carried: SnapCodec
## SKIP_FIELDS), and the numbers read once.
var _body: Enemy
var _n := {}


func id() -> String:
	return "events"


func attach() -> void:
	_body = Enemy.new("pig")
	game.events.exploded.connect(_blast)
	tick_with(_tick)


func detach() -> void:
	_body = null
	super()


## A number from events.cfg's `section`.
func n(section: String, key: String) -> float:
	var at := section + "/" + key
	if _n.has(at):
		var kept: float = _n[at]
		return kept
	var raw: Variant = Tuning.file(FILE).get_value(section, key, 0.0)
	var v := 0.0
	if raw is int:
		var whole: int = raw
		v = float(whole)
	elif raw is float:
		v = raw
	_n[at] = v
	return v


## Any other value from events.cfg (lists, ranges).
static func value(section: String, key: String, fallback: Variant) -> Variant:
	return Tuning.file(FILE).get_value(section, key, fallback)


## Entry i of a row of plain values, as a number.
static func at(row: Array, i: int) -> float:
	var v: Variant = row[i]
	if v is int:
		var whole: int = v
		return float(whole)
	var part: float = v
	return part


## A (least, most) range from events.cfg.
static func span(section: String, key: String) -> Vector2:
	var v: Variant = value(section, key, Vector2.ZERO)
	return v if v is Vector2 else Vector2.ZERO


func save() -> Dictionary:
	if not asked:
		return {}
	var out := {"planned": planned, "plan_at": plan_at, "spent": spent, "kind": kind}
	if kind == "":
		return out
	out["phase"] = phase
	out["since"] = since
	match kind:
		"twister":
			out["tw"] = [tw_from.x, tw_from.y, tw_to.x, tw_to.y, tw_run, tw_k, tw_aim]
		"hogs":
			out["herd"] = herd.duplicate(true)
			out["run"] = [herd_from.x, herd_from.y, herd_way.x, herd_way.y, herd_len]
		"raid":
			out["raid"] = [raid_at.x, raid_at.y, raid_still, 1 if busted else 0]
			out["raiders"] = raiders.duplicate()
		"blackout":
			out["dark"] = [back_at, breaker.x, breaker.y, breaker.z]
			out["torches"] = torches.duplicate(true)
			out["lanterns"] = lanterns.duplicate()
	return out


func restore(state: Dictionary) -> void:
	if state.is_empty():
		return
	asked = true
	on = game.events_on
	planned = str(state.get("planned", ""))
	var at: float = state.get("plan_at", -1.0)
	plan_at = at
	var was_spent: bool = state.get("spent", false)
	spent = was_spent
	kind = str(state.get("kind", ""))
	var ph: int = state.get("phase", 0)
	phase = ph
	var from: float = state.get("since", game.clock)
	since = from
	match kind:
		"twister":
			var t: Array = state.get("tw", [])
			if t.size() < 7:
				kind = ""
				return
			tw_from = Vector2(at(t, 0), at(t, 1))
			tw_to = Vector2(at(t, 2), at(t, 3))
			tw_run = at(t, 4)
			tw_k = at(t, 5)
			tw_aim = int(at(t, 6))
			tw_at = EventTwister.where(self)
		"hogs":
			var r: Array = state.get("run", [])
			var rows: Array = state.get("herd", [])
			if r.size() < 5:
				kind = ""
				return
			herd = rows.duplicate(true)
			herd_from = Vector2(at(r, 0), at(r, 1))
			herd_way = Vector2(at(r, 2), at(r, 3))
			herd_len = at(r, 4)
		"raid":
			var r: Array = state.get("raid", [])
			if r.size() < 4:
				kind = ""
				return
			raid_at = Vector2(at(r, 0), at(r, 1))
			raid_still = int(at(r, 2))
			busted = at(r, 3) == 1.0
			var kept: Array = state.get("raiders", [])
			raiders = _whole(kept)
		"blackout":
			var r: Array = state.get("dark", [])
			if r.size() < 4:
				kind = ""
				return
			back_at = at(r, 0)
			breaker = Vector3(at(r, 1), at(r, 2), at(r, 3))
			var kept: Array = state.get("torches", [])
			torches = kept.duplicate(true)
			var lit: Array = state.get("lanterns", [])
			lanterns = _whole(lit)
			power = false


## Indexes read back from a save (a file's numbers are all floats): whole
## numbers again, so has() and find() with an enemy's index match.
static func _whole(rows: Array) -> Array:
	var out: Array = []
	for v: Variant in rows:
		out.append(roundi(at([v], 0)))
	return out


func tally_rows() -> Array:
	var shown := kind if kind != "" else _last_ran()
	match shown:
		"twister":
			return [["TWISTER", "RODE IT OUT"]]
		"hogs":
			return [["HOGS", "STAMPEDE"]]
		"raid":
			return [["REVENUERS", "RAIDED"]]
		"blackout":
			return [["BLACKOUT", "LIGHTS OUT"]]
	return []


func _last_ran() -> String:
	for k: String in ["twister", "hogs", "raid", "blackout"]:
		if ran.has(k):
			return k
	return ""


# ------------------------------------------------------------------ the plan


## Whether events come to this game at all: a campaign chapter, alone or in
## co-op, with EVENTS on.
func allowed() -> bool:
	if game.level == null or game.in_hub or game.events_on == OFF:
		return false
	if not Campaign.ORDER.has(game.level.id) or BossRematch.active(game):
		return false
	var never: Array = value("all", "never", [])
	if never.has(game.level.id):
		return false
	var mode := Modes.mode_of(game)
	return mode == Modes.CAMPAIGN or mode == Modes.COOP


## The kinds this level can have.
func kinds_here() -> Array:
	var all: Array = value("all", "kinds", [])
	var night: Array = value("all", "night", [])
	var out: Array = []
	for k: Variant in all:
		if str(k) == "blackout" and not night.has(game.level.id):
			continue
		out.append(str(k))
	return out


## The first tick: whether the chapter gets one, which and when.
func _plan() -> void:
	asked = true
	on = game.events_on
	if not allowed():
		return
	var chance := n("all", "chance_often") if on == OFTEN else n("all", "chance_sometimes")
	if game.rng.random() >= chance:
		return
	var here := kinds_here()
	if here.is_empty():
		return
	var all: Array = value("all", "kinds", [])
	var weights: Array = value("all", "weights", [])
	var sum := 0.0
	for k: String in here:
		var w: float = weights[all.find(k)] if all.find(k) < weights.size() else 1.0
		sum += w
	var pick := game.rng.random() * sum
	planned = here[here.size() - 1]
	for k: String in here:
		var w: float = weights[all.find(k)] if all.find(k) < weights.size() else 1.0
		if pick < w:
			planned = k
			break
		pick -= w
	var when := span("all", "start_after")
	var pace := n("all", "often_pace") if on == OFTEN else 1.0
	plan_at = game.clock + game.rng.uniform(when.x, when.y) * pace


## Starts `what` now if it can (the checks call this too): true when it began.
func begin(what: String) -> bool:
	if kind != "":
		return false
	var ok := false
	match what:
		"twister":
			ok = EventTwister.start(self)
		"hogs":
			ok = EventHerd.start(self)
		"raid":
			ok = EventRaid.start(self)
		"blackout":
			ok = EventDark.start(self)
	if not ok:
		return false
	kind = what
	phase = 0
	since = game.clock
	spent = true
	var count: int = ran.get(what, 0)
	ran[what] = count + 1
	wake()
	return true


## The event is over (or cut short).
func finish() -> void:
	match kind:
		"blackout":
			EventDark.stop(self)
		"hogs":
			herd.clear()
	kind = ""
	phase = 0
	trampled.clear()


# ------------------------------------------------------------------ the tick


func _tick(dt: float) -> void:
	if not asked:
		_plan()
	if kind == "":
		if spent or planned == "":
			sleep()
			return
		if game.clock < plan_at:
			return
		if _clear() and begin(planned):
			return
		tries += 1
		plan_at = game.clock + n("all", "retry")
		if tries >= TRIES:
			spent = true
		return
	if boss_fight():
		_cut_short()
	match kind:
		"twister":
			EventTwister.step(self, dt)
		"hogs":
			EventHerd.step(self, dt)
		"raid":
			EventRaid.step(self, dt)
		"blackout":
			EventDark.step(self, dt)


## Whether it may start now: no boss fight, everyone up.
func _clear() -> bool:
	if boss_fight():
		return false
	for p: Player in game.players:
		if not p.away and p.health <= 0:
			return false
	return true


## A boss awake and standing.
func boss_fight() -> bool:
	for e: Enemy in game.enemies:
		if e.alive and e.alerted and Enemy.BOSS_TITLES.has(e.kind):
			return true
	return false


## Whether (x, y) is clear of every boss still standing.
func far_from_bosses(x: float, y: float) -> bool:
	var clear := n("all", "boss_clear")
	for e: Enemy in game.enemies:
		if e.alive and Enemy.BOSS_TITLES.has(e.kind):
			if Vector2(e.x - x, e.y - y).length() < clear:
				return false
	return true


## A boss fight began: the twister lifts, the herd runs off, the power comes
## back; a raid's men are ordinary hands from here.
func _cut_short() -> void:
	match kind:
		"twister":
			if phase < EventTwister.LIFT:
				EventTwister.lift(self)
		"hogs", "raid", "blackout":
			finish()


## A player chosen for the event (game.rng), alive and in the game.
func someone() -> Player:
	var up: Array = []
	for p: Player in game.players:
		if not p.away and p.health > 0:
			up.append(p)
	if up.is_empty():
		return null
	var picked: Player = game.rng.choice(up)
	return picked


## Whether (x, y) at height z has a roof over it (a body there is sheltered).
func roofed(x: float, y: float, z: float) -> bool:
	return game.world.roof_over(x, y, z + .3) != 0.0


func _blast(x: float, y: float, _z: float, _energy: bool) -> void:
	if kind == "hogs":
		EventHerd.blast(self, x, y)


## Moves a body (a hog) through the level like a hand: how far it went.
func move_body(at: Array, dx: float, dy: float, radius: float) -> float:
	var x0: float = at[0]
	var y0: float = at[1]
	var fz: float = at[6]
	_body.x = x0
	_body.y = y0
	_body.floor_z = fz
	_body.radius = radius
	game.world.move(_body, dx, dy, radius)
	at[0] = _body.x
	at[1] = _body.y
	at[6] = _body.floor_z
	return Vector2(_body.x - x0, _body.y - y0).length()


# ------------------------------------------------------------- the hooks


## Enemy.tick asks before a brawl: a raider or a hand feuding with one at
## range shoots instead of walking up to punch (event_raid.gd). True when it
## took the tick.
func feud(e: Enemy, dt: float) -> bool:
	if kind != "raid":
		return false
	return EventRaid.feud(self, e, dt)


## How far hand `e` notices player `p` in the dark, as a share (1: as ever).
func notice(e: Enemy, p: Player) -> float:
	if kind != "blackout":
		return 1.0
	return EventDark.notice(self, e, p)


## The flashlight switch (L; online Controls.item == Game.TORCH): the acting
## player's, during a blackout.
func torch(p: Player) -> void:
	if kind == "blackout":
		EventDark.toggle(self, p)


## USE beside the breaker in a blackout.
func prompt(p: Player) -> String:
	if kind != "blackout":
		return ""
	return EventDark.prompt(self, p)


func use(p: Player) -> bool:
	if kind != "blackout":
		return false
	return EventDark.use(self, p)


## Player p's flashlight: [on, battery share], or [] with none.
func torch_of(p: Player) -> Array:
	if kind != "blackout" or p.slot >= torches.size():
		return []
	var row: Array = torches[p.slot]
	var lit: int = row[0]
	var left: float = row[1]
	return [lit == 1, left / maxf(1.0, n("blackout", "battery"))]


## How dark it is now (0 lit .. `dark`): the 3D view and the gun's light.
func darkness() -> float:
	if kind != "blackout":
		return 0.0
	return EventDark.darkness(self)


## This frame's lights for player p's view: the flashlights' beams, the hands'
## lanterns, the breaker's lamp (view_lights.gd).
func lights(p: Player) -> Array:
	if kind != "blackout":
		return []
	return EventDark.lights(self, p)


## The sprites: the hogs, the breaker.
func sprites() -> Array:
	match kind:
		"hogs":
			return EventHerd.sprites(self)
		"blackout":
			return EventDark.sprites(self)
	return []
