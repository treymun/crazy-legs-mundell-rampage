## The bots of the 5v5 round modes (tactical_mode.gd): every player this
## machine's player does not play, in any build (main_flow.gd _take_mode gives
## each one a pilot; main.gd _tick_party asks it for controls each tick, the
## player focused).
##
## Each round it shops (TacticalShop: a rifle and a vest when the money is
## there, a sprayer or the sawed-off and a vest when it is not, saving on a bad
## run), then plays its part:
##   attackers  the team picks a site each round (plan_site); each bot walks
##              one of the map's routes there (LevelData.tactical "routes"),
##              one lurks down the other site's route for a while first. The
##              bomb carrier plants once on the site with nobody in sight; the
##              rest guard the bomb. A dropped bomb is fetched by the nearest.
##              In hostage rescue they go for the hostages, carry one to the
##              rescue box, and the others escort the carrier.
##   defenders  hold their spot ("holds": two on each site, one in the middle),
##              facing the way the attack comes; a foe seen on a site calls
##              the others over; a planted bomb draws everyone, the nearest
##              cuts the fuse; a hostage carried away is chased.
## In a fight it turns onto the nearest foe it sees with a little reaction
## time and an aim that settles (no aimbot), strafes, and fires when the
## crosshair is on them. Its decisions use only what a player could see or
## hear about, plus the team's own calls.
class_name TacticalBot
extends RefCounted

const LOOK_EVERY := .15
const SIGHT := 34.0
const TURN := .11
## By the game's DIFFICULTY (EASY..HOG WILD): seconds from first sight to the
## first shot, how far the first aim is off (radians, settling away), and how
## much the aim keeps wandering while it fires.
const REACTION := [.5, .34, .26, .19]
const AIM_ERROR := [.14, .09, .07, .05]
const WOBBLE := [.05, .03, .02, .012]
const ARRIVE := 1.4
const LURK_UNTIL := 22.0
const CALL_FOR := 7.0

## The team's calls: game instance -> team -> {"A": clock seen, "B": ...}.
static var calls := {}
## The attack gathering before it goes in: "game|round" -> {go, here: slots}.
static var staged := {}
## Seconds into a round the attack goes in, gathered or not.
const STAGE_MOST := 32.0
## How far back from the point before the site the team may gather instead.
const STAGE_BACK := 8.0

var slot := 0
var rng := RandomNumberGenerator.new()
var as_controls := true
var round_seen := -1
var shopped := -1
var route: Array = []
var leg := 0
var hold := Vector3.INF
var lurking := false
var foe: Player = null
var foe_since := 0.0
var foe_lost_at := -99.0
var foe_last := Vector2.ZERO
var next_look := 0.0
var aim_off := 0.0
var stuck := 0.0
var last_spot := Vector2.ZERO
var used_at := -99.0
var strafe_turn := 1.0
## A throw under way: the throwable, where at, until when it is given up;
## the throwables already thrown this round (by gun).
var throw_gun := -1
var throw_at := Vector2.ZERO
var throw_until := 0.0
var thrown := {}
## The store's items still to go out as buys, one a tick.
var buys: Array = []
## The route point where the attack gathers (_stage_for).
var stage_leg := -1
## The bots' buying ways, by slot: rifle carriers, the sniper, the one who
## buys an SMG rather than save, the one who likes a shotgun or big pistol.
const STYLES := [
	"rifle", "sniper", "rifle", "smg", "close", "rifle", "rifle", "smg", "close", "sniper"
]


func _init(p_slot := 0) -> void:
	slot = p_slot
	rng.seed = 7919 * (p_slot + 1)


# ------------------------------------------------------------------- tick


func steer(game) -> Game.Controls:
	var c := Game.Controls.new()
	var p: Player = game.player
	var st = Modes.feature(game)
	if st == null or not Modes.TACTICAL.has(String(st.mode)) or p.health <= 0:
		return c
	if int(st.round_no) != round_seen:
		_plan(game, st, p)
	if shopped != int(st.round_no) and TacticalMode.can_buy(game, st, p):
		_shop(game, st, p)
		shopped = int(st.round_no)
	if not buys.is_empty():
		c.buy = int(buys.pop_front())
	if throw_gun >= 0 and String(st.phase) == "live":
		if _throw(game, p, c):
			return c
	_arm(game, p, c)
	if String(st.phase) == "freeze" or String(st.phase) == "over":
		c.turn = clampf(Enemy.angle_delta(_face_angle(game, st, p), p.angle), -TURN, TURN)
		return c
	if TacticalUtility.blindness(game, p) > .3:
		# Flashed: no target, no shooting, a stagger about.
		foe = null
		c.turn = sin(game.clock * 3.0 + slot) * .05
		c.forward = -.3
		return c
	_look(game, st, p)
	_plan_throw(game, st, p)
	var goal := _goal(game, st, p, c)
	if foe != null:
		_fight(game, st, p, c, goal)
	else:
		_walk(game, p, c, goal)
	_unstick(game, p, c)
	return c


static func _skill(game) -> int:
	var st = Modes.feature(game)
	if st != null and int(st.bot_skill) >= 0:
		return clampi(int(st.bot_skill), 0, 3)
	return clampi(int(game.difficulty), 0, 3)


## Called after the tick (main.gd _tick_party): nothing to settle.
func moved(_game) -> void:
	pass


# ------------------------------------------------------------------ plans


## The team's site this round: the same answer for every bot on it.
static func plan_site(game, st) -> String:
	var sites = game.world.tactical.get("sites", {})
	var names: Array = sites.keys() if sites is Dictionary else []
	names.sort()
	if names.is_empty():
		return ""
	var h := absi(
		hash(String(game.level.id)) + int(st.round_no) * 2654435761 + int(st.wins[0]) * 31
	)
	return String(names[(h >> 3) % names.size()])


## Where this bot is among its team's players (0..4, by slot).
static func team_index(game, p: Player) -> int:
	var k := 0
	for q: Player in game.players:
		if q == p:
			return k
		if q.team == p.team:
			k += 1
	return k


func _plan(game, st, p: Player) -> void:
	round_seen = int(st.round_no)
	foe = null
	stuck = 0.0
	leg = 0
	hold = Vector3.INF
	route = []
	lurking = false
	throw_gun = -1
	thrown = {}
	var plan: Dictionary = game.world.tactical
	var k := team_index(game, p)
	if TacticalMode.attacks(game, st, p):
		var site := plan_site(game, st)
		var other := "B" if site == "A" else "A"
		lurking = k == 4 and String(st.mode) == Modes.BOMB
		var routes = plan.get("routes", {}).get(other if lurking else site, [])
		if routes is Array and not routes.is_empty():
			route = (routes[k % routes.size()] as Array).duplicate()
		stage_leg = _stage_for(game, plan, site)
	else:
		hold = _hold_for(plan, k)


static func _hold_for(plan: Dictionary, k: int) -> Vector3:
	var holds = plan.get("holds", {})
	if not holds is Dictionary:
		return Vector3.INF
	var key := "A" if k < 2 else ("B" if k < 4 else "mid")
	var rows = holds.get(key, [])
	if not rows is Array or rows.is_empty():
		return Vector3.INF
	var row: Array = rows[(k % 2) % rows.size()]
	return Vector3(float(row[0]), float(row[1]), float(row[2]))


func _shop(game, st, p: Player) -> void:
	var cash := int(st.money[p.slot])
	var has_long := false
	for gun: int in TacticalShop.LONG_GUNS:
		if p.armory.owned[gun]:
			has_long = true
	var half_start := int(st.round_no) == 1 or int(st.round_no) == int(st.rounds_to_win)
	var outlaw := TacticalMode.side_of(st, p) == 0
	var team: int = p.team
	var behind := int(st.losses_in_row[team]) if team < st.losses_in_row.size() else 0
	var wants: Array = []
	# Each bot has its way (STYLES): most carry a rifle, one is the team's
	# sniper, one likes an SMG when money is short, one a shotgun up close.
	var style := String(STYLES[slot % STYLES.size()])
	if has_long:
		wants = ["vest_hat", "vest"]
	elif half_start:
		wants = (["hogleg" if outlaw else "star357"] if style in ["sniper", "close"] else ["vest"])
	elif style == "sniper" and cash >= 6000:
		wants = ["hunter" if outlaw else "marksman", "vest"]
	elif cash >= 6800 and rng.randf() < .3:
		wants = ["mower" if outlaw else "patrol_bar", "vest_hat"]
	elif cash >= 3700:
		wants = ["rifle", "vest_hat"]
	elif cash >= 3350:
		wants = ["rifle", "vest"]
	elif cash >= 2700:
		wants = ["rifle"]
	elif cash >= 1900 and (style == "smg" or behind >= 2):
		# A force buy: an SMG and a vest beats saving again.
		wants = ["grease_gun" if outlaw else "tommy", "vest"]
	elif cash >= 1750 and style == "close":
		wants = ["sawed_off" if outlaw else "riot_pump", "vest"]
	elif cash >= 1200 and behind < 2 and style in ["sniper", "close"]:
		wants = ["hogleg" if outlaw else "star357"]
	# Otherwise less than a rifle: save for the next round (the loss bonus
	# grows).
	# Spare cash on throwables: the attack smoke and flash, the defence fire.
	if not half_start:
		if TacticalMode.attacks(game, st, p):
			wants.append("smudge_pot" if team_index(game, p) % 2 == 0 else "flash_jar")
			wants.append("flash_jar")
		else:
			wants.append("shine_cocktail")
	if String(st.mode) == Modes.BOMB and TacticalMode.defends(st, p):
		if team_index(game, p) % 2 == 0:
			wants.append("snips")
	# Each goes out as a buy in the controls, one a tick (so a networked game
	# plays it on every copy), as far as the cash goes.
	var armoured := false
	for id: String in wants:
		var row := TacticalShop.item(id)
		if row.is_empty() or (id == "vest" and armoured):
			continue
		if TacticalShop.owned_fully(st, p, row):
			continue
		var price := TacticalShop.price_for(st, p, row)
		if price > cash or not TacticalShop.allowed(game, st, p, row):
			continue
		armoured = armoured or id == "vest_hat" or id == "vest"
		cash -= price
		buys.append(TacticalShop.index_of(id))


## The best gun in hand, reloaded when dry.
func _arm(_game, p: Player, c: Game.Controls) -> void:
	var a: Weapons.Armory = p.armory
	var want := TacticalShop.best_gun(p)
	if a.active != want and a.switch <= 0.0 and a.fuse <= 0.0:
		c.weapon = want
		return
	if Weapons.CAPACITY[a.active] > 0 and a.loaded[a.active] == 0 and a.reserve[a.active] > 0:
		c.reload = true


# ----------------------------------------------------------------- seeing


## Every LOOK_EVERY seconds the nearest foe in sight (the one it has kept on
## between looks); a foe seen on a site is called to the team.
func _look(game, st, p: Player) -> void:
	if foe != null:
		if foe.health <= 0 or not _sees(game, p, foe):
			foe_lost_at = game.clock
			foe_last = Vector2(foe.x, foe.y) if foe.health > 0 else foe_last
			foe = null
		else:
			return
	if game.clock < next_look:
		return
	next_look = game.clock + LOOK_EVERY + .02 * (slot % 3)
	var best: Player = null
	var near := SIGHT
	for q: Player in game.players:
		if q.team == p.team or q.health <= 0:
			continue
		var d := Vector2(q.x - p.x, q.y - p.y).length()
		if d < near and _sees(game, p, q):
			near = d
			best = q
	if best != null:
		foe = best
		foe_since = game.clock
		var miss: float = AIM_ERROR[_skill(game)]
		aim_off = rng.randf_range(-miss, miss) * clampf(near / 10.0, .5, 1.6)
		_call(game, st, p.team, best)


func _sees(game, p: Player, q: Player) -> bool:
	var d := Vector2(q.x - p.x, q.y - p.y).length()
	if d > SIGHT:
		return false
	# Only what is in front: a field of view of about 150 degrees, unless close.
	var bearing := atan2(q.y - p.y, q.x - p.x)
	if d > 2.5 and absf(Enemy.angle_delta(bearing, p.angle)) > 1.3:
		return false
	if TacticalUtility.smoked(game, p.x, p.y, q.x, q.y):
		return false
	return game.world.visible(p.x, p.y, q.x, q.y, p.eye, q.eye - .1)


static func _call(game, _st, team: int, seen: Player) -> void:
	var at := BombMode.site_at(game, seen.x, seen.y)
	if at == "":
		var sites = game.world.tactical.get("sites", {})
		if sites is Dictionary:
			for name: String in sites:
				var centre := TacticalMode.box_centre(sites[name])
				if centre.distance_to(Vector2(seen.x, seen.y)) < 7.0:
					at = name
	if at == "":
		return
	var key: int = game.get_instance_id()
	if not calls.has(key):
		calls = {key: [{}, {}]}  # one game's calls at a time
	calls[key][team][at] = game.clock


static func called(game, team: int) -> String:
	var key: int = game.get_instance_id()
	if not calls.has(key):
		return ""
	var best := ""
	var latest := -1.0
	var mine: Dictionary = calls[key][team]
	for site: String in mine:
		var when := float(mine[site])
		if game.clock - when < CALL_FOR and when > latest:
			latest = when
			best = site
	return best


# ------------------------------------------------------------------- goals


## Where to go now (INF: stay where it is), with the objective's own presses
## held in the controls.
func _goal(game, st, p: Player, c: Game.Controls) -> Vector2:
	if String(st.mode) == Modes.BOMB:
		return _bomb_goal(game, st, p, c)
	return _hostage_goal(game, st, p, c)


func _bomb_goal(game, st, p: Player, c: Game.Controls) -> Vector2:
	var bomb: Dictionary = st.bomb
	var state := String(bomb.get("state", ""))
	var at := Vector2(float(bomb.get("x", 0.0)), float(bomb.get("y", 0.0)))
	var plan: Dictionary = game.world.tactical
	if TacticalMode.attacks(game, st, p):
		if state == "dropped" and _nearest_to(game, p, at):
			return at
		if state == "planted":
			var guard := at + Vector2(cos(slot * 1.7), sin(slot * 1.7)) * 3.0
			return guard if not game.world.blocked(guard.x, guard.y, .3) else at
		var carrying := state == "carried" and int(bomb["slot"]) == p.slot
		var site := plan_site(game, st)
		var box = plan.get("sites", {}).get(site, [])
		var centre := TacticalMode.box_centre(box) if box is Array and box.size() >= 4 else at
		if lurking and game.clock - float(st.live_from) > LURK_UNTIL:
			# The lurk is over: straight across to the team's site.
			lurking = false
			route = [[centre.x, centre.y]]
			leg = 0
		if carrying:
			var on_site := Vector2(p.x, p.y).distance_to(centre) < 2.2
			if BombMode.site_at(game, p.x, p.y) == site and on_site:
				if foe == null:
					c.hold = true
					return Vector2.INF
			if leg >= route.size():
				return centre
		return _route_goal(game, p)
	# Defending.
	if state == "planted":
		if _nearest_to(game, p, at) or Vector2(p.x, p.y).distance_to(at) < 2.0:
			if Vector2(p.x, p.y).distance_to(at) < BombMode.DEFUSE_REACH * .8:
				var left: float = BombMode.BOMB_TIMER - (game.clock - float(bomb["planted_at"]))
				if foe == null or left < BombMode.defuse_time(st, p) + 1.0:
					c.hold = true
					return Vector2.INF
			return at
		return at + Vector2(cos(slot * 2.3), sin(slot * 2.3)) * 3.5
	var heard := called(game, p.team)
	# A call brings help from the other site; with one site (TAG TEAM 2V2)
	# both are already on it, and leaving a hold for the site's middle only
	# walks them into the open.
	var sites = plan.get("sites", {})
	var one_site: bool = sites is Dictionary and sites.size() == 1
	if heard != "" and not one_site and team_index(game, p) != (0 if heard == "B" else 2):
		var box = plan.get("sites", {}).get(heard, [])
		if box is Array and box.size() >= 4:
			return TacticalMode.box_centre(box)
	return Vector2(hold.x, hold.y) if hold != Vector3.INF else Vector2.INF


func _hostage_goal(game, st, p: Player, c: Game.Controls) -> Vector2:
	var box := HostageMode.nearest_rescue(game, p.x, p.y)
	var carried_by: Player = null
	var mine := -1
	for i in st.hostages.size():
		var h: Array = st.hostages[i]
		if String(h[2]) == "carried":
			var s := int(h[3])
			if s == p.slot:
				mine = i
			elif s >= 0 and s < game.players.size():
				carried_by = game.players[s]
	if TacticalMode.attacks(game, st, p):
		if mine >= 0:
			return TacticalMode.box_centre(box) if not box.is_empty() else Vector2.INF
		if carried_by != null and team_index(game, p) % 2 == 0:
			return Vector2(carried_by.x, carried_by.y)  # escort
		var near := INF
		var best := Vector2.INF
		for h: Array in st.hostages:
			if String(h[2]) != "free":
				continue
			var at := Vector2(float(h[0]), float(h[1]))
			var d := at.distance_to(Vector2(p.x, p.y))
			if d < near:
				near = d
				best = at
		if best != Vector2.INF and near < HostageMode.CARRY_REACH * .9:
			if game.clock - used_at > 1.0 and foe == null:
				c.use = true
				used_at = game.clock
			return best
		if best != Vector2.INF and near < 12.0:
			return best
		return _route_goal(game, p) if leg < route.size() else best
	# Defending: after a carrier, else hold.
	if carried_by != null:
		return Vector2(carried_by.x, carried_by.y)
	return Vector2(hold.x, hold.y) if hold != Vector3.INF else Vector2.INF


## The next point of the route, moving on as each is reached. An attacker
## stops at the last point before the site (its route's next to last) until
## the team is gathered there, then they go in together (_released).
func _route_goal(game, p: Player) -> Vector2:
	while leg < route.size():
		var at := Vector2(float(route[leg][0]), float(route[leg][1]))
		if stage_leg >= 0 and leg > stage_leg and not lurking:
			var wait := Vector2(float(route[stage_leg][0]), float(route[stage_leg][1]))
			if not _released(game, p, wait):
				return wait
		if at.distance_to(Vector2(p.x, p.y)) > ARRIVE:
			return at
		leg += 1
	return Vector2.INF


## Where on the route the team gathers: the point before the site itself,
## or the one before that when the site's holds can see it (a doorway), so
## they wait out of the defenders' sight but not far back; -1 with no route.
func _stage_for(game, plan: Dictionary, site: String) -> int:
	if route.size() < 2:
		return -1
	var holds: Array = plan.get("holds", {}).get(site, [])
	var last := Vector2(float(route[-2][0]), float(route[-2][1]))
	for i in range(route.size() - 2, maxi(-1, route.size() - 4), -1):
		var at := Vector2(float(route[i][0]), float(route[i][1]))
		if at.distance_to(last) > STAGE_BACK:
			break  # too far back to gather: the point before the site it is
		var seen := false
		for h: Array in holds:
			if game.world.visible(float(h[0]), float(h[1]), at.x, at.y):
				seen = true
				break
		if not seen:
			return i
	return route.size() - 2


## Whether the attack has gone in: this bot is noted as gathered once at
## `wait`; the team goes when all but one of those up (lurker aside) are
## gathered, when a gathered one has a foe in sight, or STAGE_MOST seconds
## into the round.
func _released(game, p: Player, wait: Vector2) -> bool:
	var st = Modes.feature(game)
	if st == null or not TacticalMode.attacks(game, st, p):
		return true
	var key := "%d|%d" % [game.get_instance_id(), int(st.round_no)]
	if not staged.has(key):
		staged = {key: {"go": false, "here": {}}}  # one round's gathering at a time
	var team: Dictionary = staged[key]
	if bool(team["go"]):
		return true
	if Vector2(p.x, p.y).distance_to(wait) < ARRIVE * 1.6:
		team["here"][p.slot] = true
	var up := 0
	var here := 0
	for q: Player in game.players:
		if q.team == p.team and q.health > 0 and team_index(game, q) != 4:
			up += 1
			if team["here"].has(q.slot):
				here += 1
	var seen: bool = foe != null and team["here"].has(p.slot)
	if here >= maxi(1, up - 1) or seen or game.clock - float(st.live_from) > STAGE_MOST:
		team["go"] = true
	return bool(team["go"])


## Whether `p` is the nearest of its team up to `at`.
static func _nearest_to(game, p: Player, at: Vector2) -> bool:
	var mine := at.distance_to(Vector2(p.x, p.y))
	for q: Player in game.players:
		if q != p and q.team == p.team and q.health > 0:
			if at.distance_to(Vector2(q.x, q.y)) < mine - .01:
				return false
	return true


## Which way to face standing still: the hold's own way, else toward the
## middle of the map.
func _face_angle(game, _st, p: Player) -> float:
	if hold != Vector3.INF and Vector2(hold.x, hold.y).distance_to(Vector2(p.x, p.y)) < 2.0:
		return hold.z
	if not route.is_empty():
		var at: Array = route[mini(leg, route.size() - 1)]
		return atan2(float(at[1]) - p.y, float(at[0]) - p.x)
	return atan2(game.world.height * .5 - p.y, game.world.width * .5 - p.x)


# ---------------------------------------------------------------- moving


func _walk(game, p: Player, c: Game.Controls, goal: Vector2) -> void:
	c.look = clampf(-p.pitch * .2, -2.0, 2.0)
	if goal == Vector2.INF:
		c.turn = clampf(Enemy.angle_delta(_face_angle(game, null, p), p.angle), -TURN, TURN)
		return
	var gap := goal.distance_to(Vector2(p.x, p.y))
	if gap < .6:
		c.turn = clampf(Enemy.angle_delta(_face_angle(game, null, p), p.angle), -TURN, TURN)
		return
	# Recently lost a foe: look where it was on the way.
	var want := _heading(game, p, goal)
	var check := _corner_to_check(game, p)
	if check != Vector2.INF:
		# Going onto a site: the gun on the spot a defender would hold, the
		# feet still on the way (forward and strafe split along it), walking.
		var look := atan2(check.y - p.y, check.x - p.x)
		c.turn = clampf(Enemy.angle_delta(look, p.angle), -TURN, TURN)
		var off := Enemy.angle_delta(want, p.angle)
		c.forward = cos(off)
		c.strafe = sin(off)
		c.running = false
		return
	var turn := Enemy.angle_delta(want, p.angle)
	c.turn = clampf(turn, -TURN, TURN)
	c.forward = 1.0 if absf(turn) < 1.0 else .25
	c.running = gap > 2.5


## An attacker on its last leg onto a site: the nearest of the map's holds
## (where defenders wait) it could see from here, to have its gun on as it
## goes in. INF when there is none, or it is not going in.
func _corner_to_check(game, p: Player) -> Vector2:
	if route.is_empty() or leg != route.size() - 1 or lurking:
		return Vector2.INF
	var st = Modes.feature(game)
	if st == null or not TacticalMode.attacks(game, st, p):
		return Vector2.INF
	var best := Vector2.INF
	var near := 18.0
	for key: String in game.world.tactical.get("holds", {}):
		for h: Array in game.world.tactical["holds"][key]:
			var at := Vector2(float(h[0]), float(h[1]))
			var d := at.distance_to(Vector2(p.x, p.y))
			if d < near and d > 2.0 and game.world.visible(p.x, p.y, at.x, at.y):
				near = d
				best = at
	return best


static func _heading(game, p: Player, goal: Vector2) -> float:
	var direct := atan2(goal.y - p.y, goal.x - p.x)
	if goal.distance_to(Vector2(p.x, p.y)) < 1.2:
		return direct
	var field := TacticalNav.field(game, goal.x, goal.y)
	var h: float = field.heading(p.x, p.y, game.world.stand(p)) if field != null else NAN
	return direct if is_nan(h) else h


## Turn onto the foe with a settling aim, strafe, and fire on target.
func _fight(game, _st, p: Player, c: Game.Controls, goal: Vector2) -> void:
	var dx := foe.x - p.x
	var dy := foe.y - p.y
	var d := maxf(.4, sqrt(dx * dx + dy * dy))
	var since: float = game.clock - foe_since
	var settle := aim_off * exp(-since * 3.0)
	var skill := _skill(game)
	var wobble: float = WOBBLE[skill] * sin(game.clock * 6.3 + slot * 1.9)
	var want := atan2(dy, dx) + settle + wobble
	var turn := Enemy.angle_delta(want, p.angle)
	c.turn = clampf(turn, -TURN, TURN)
	var target: float = game.world.stand(foe) + foe.air + .7
	var slope := (target - p.eye) / d
	c.look = clampf(slope * Renderer.base_focal - p.pitch, -3.0, 3.0)
	# On target as it means to aim (the wobble in that): some shots go wide.
	var on := absf(Enemy.angle_delta(want, p.angle)) < maxf(.03, atan(.22 / d))
	var reaction: float = REACTION[skill]
	c.fire = since > reaction and on
	# The gun for the distance; out of its reach, close in.
	var wanted := TacticalShop.gun_for(p, d)
	if wanted != p.armory.active and p.armory.switch <= 0.0 and p.armory.fuse <= 0.0:
		c.weapon = wanted
	var reach := TacticalShop.reach(p.armory.active)
	# A scoped gun: the scope up for a foe past arm's length, down up close
	# (ALT FIRE puts it up and down on a fresh press).
	var scopes := bool(Weapons.FIRING[p.armory.active].get("scope", 0.0))
	var want_scope := scopes and d > 6.0
	if want_scope != p.scoped and not p.alt_held and p.armory.switch <= 0.0:
		c.alt_fire = true
	if scopes and not p.scoped and d > 6.0:
		c.fire = false
	if fmod(game.clock + slot * .7, 1.6) < .02:
		strafe_turn = -strafe_turn
	c.strafe = strafe_turn * (.8 if since > reaction else 0.0)
	# A gun that wants a still shooter (TacticalShop.MOVE_SPREAD): step aside
	# between shots, stand to take them.
	var kind := TacticalShop.kind_of(p.armory.active)
	if kind in ["RIFLE", "MACHINE GUN", "SNIPER", "PISTOL"] and d > 4.0:
		if fmod(game.clock + slot * .37, .9) < .3:
			c.fire = false
		else:
			c.strafe = 0.0
	if d > reach:
		# Out of reach: attackers close in, a defender keeps to its spot and
		# lets them come.
		c.fire = false
		if TacticalMode.attacks(game, Modes.feature(game), p) or hold == Vector3.INF:
			c.forward = 1.0
			c.running = true
			c.strafe *= .3
		else:
			c.strafe = 0.0
			c.crouch = true
	elif d < 2.0:
		c.forward = -.5
	elif goal != Vector2.INF and hold == Vector3.INF and d > 12.0:
		c.forward = .3


## Hops and side-steps out of a spot it is wedged in; a waypoint it cannot
## reach for a while is skipped.
func _unstick(game, p: Player, c: Game.Controls) -> void:
	var here := Vector2(p.x, p.y)
	var trying := absf(c.forward) > .1 or absf(c.strafe) > .1
	if trying and here.distance_to(last_spot) < .012:
		stuck += 1.0 / 120.0
	else:
		stuck = maxf(0.0, stuck - 2.0 / 120.0)
	last_spot = here
	if stuck > .4:
		c.jump = fmod(game.clock, .7) < .1
		c.strafe = 1.0 if fmod(game.clock + slot, 1.4) < .7 else -1.0
		c.forward = 1.0
	if stuck > 2.5 and leg < route.size():
		leg += 1
		stuck = 0.0


# ---------------------------------------------------------------- throwing


## When to throw: an attacker coming up to its site smokes off the defenders'
## spot, then flashes into the site; a defender with a firebomb throws it at
## attackers pushing in.
func _plan_throw(game, st, p: Player) -> void:
	if throw_gun >= 0:
		return
	var a: Weapons.Armory = p.armory
	var plan: Dictionary = game.world.tactical
	if TacticalMode.attacks(game, st, p):
		if route.is_empty() or leg != route.size() - 1:
			return
		var site := plan_site(game, st)
		var box = plan.get("sites", {}).get(site, [])
		if not box is Array or box.size() < 4:
			return
		var centre := TacticalMode.box_centre(box)
		var holds = plan.get("holds", {}).get(site, [])
		if (
			a.owned[Weapons.SMUDGE_POT]
			and a.reserve[Weapons.SMUDGE_POT] > 0
			and not thrown.has(Weapons.SMUDGE_POT)
		):
			if holds is Array and not holds.is_empty():
				_start_throw(
					game, Weapons.SMUDGE_POT, Vector2(float(holds[0][0]), float(holds[0][1]))
				)
				return
		if (
			a.owned[Weapons.FLASH_JAR]
			and a.reserve[Weapons.FLASH_JAR] > 0
			and not thrown.has(Weapons.FLASH_JAR)
		):
			_start_throw(game, Weapons.FLASH_JAR, centre)
	elif foe != null and a.owned[Weapons.SHINE_COCKTAIL] and a.reserve[Weapons.SHINE_COCKTAIL] > 0:
		var d := Vector2(foe.x - p.x, foe.y - p.y).length()
		if d > 4.0 and d < 10.0 and not thrown.has(Weapons.SHINE_COCKTAIL):
			_start_throw(game, Weapons.SHINE_COCKTAIL, Vector2(foe.x, foe.y))


func _start_throw(game, gun: int, at: Vector2) -> void:
	throw_gun = gun
	throw_at = at
	throw_until = game.clock + 2.5


## A throw under way: take the throwable up, turn on the spot, lift the aim
## for the distance, let fly. True while it is still under way.
func _throw(game, p: Player, c: Game.Controls) -> bool:
	var a: Weapons.Armory = p.armory
	if game.clock > throw_until or a.reserve[throw_gun] <= 0 or not a.owned[throw_gun]:
		thrown[throw_gun] = true
		throw_gun = -1
		return false
	if a.active != throw_gun:
		c.weapon = throw_gun
	var to := throw_at - Vector2(p.x, p.y)
	var turn := Enemy.angle_delta(atan2(to.y, to.x), p.angle)
	c.turn = clampf(turn, -TURN, TURN)
	# Lift: about 6 cells flat, more the further it is to go (pixels of pitch).
	var lift := clampf(6.0 + (to.length() - 5.0) * 4.0, 2.0, 36.0)
	c.look = clampf(lift - p.pitch, -3.0, 3.0)
	if a.active == throw_gun and a.switch <= 0.0 and a.cooldown <= 0.0:
		if absf(turn) < .08 and absf(lift - p.pitch) < 4.0:
			c.fire = true
			thrown[throw_gun] = true
			throw_gun = -1
	return true
