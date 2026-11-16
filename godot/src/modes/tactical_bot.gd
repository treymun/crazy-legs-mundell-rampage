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
## In a fight it aims as a person does (bot_aim.gd: a reaction time, a flick
## that lands off and settles, a hand that strays and lags a strafer, bursts at
## range), side-steps and stands for the shot, and falls back to cover when
## hurt (by its persona). It trades a teammate's death, pushes or holds on a
## foe it lost, turns to gunfire that hurts it, keeps out of fire, spreads out
## going in and shoots boarded cover open when that is the shorter way. Its
## decisions use only what a player could see or hear about, plus the team's
## own calls.
class_name TacticalBot
extends RefCounted

const ModeFeature := preload("res://src/features/mode_feature.gd")
const WallBreaks := preload("res://src/features/wall_breaks.gd")

const LOOK_EVERY := .15
## How often a foe in sight is looked at again (a sight line is dear: a
## tick at 60 a second is .017), and the spot to have the gun on going onto a
## site (_corner_to_check).
const SIGHT_EVERY := .034
const CORNER_EVERY := .25
## Goals further than NAV_NEAR walk the field of their cell snapped to a
## NAV_GRID-cell grid (_nav_for).
const NAV_NEAR := 5.0
## An attacker falls back at this share of its persona's line, and nobody on
## the attack hides with under NO_HIDING seconds of the round left.
const ATTACK_FALL_BACK := .6
const NO_HIDING := 30.0
const NAV_GRID := 3.0
const SIGHT := 34.0
## Half the field of view it notices foes in (a person's screen and a little
## to each side), and how near it hears one whatever way it faces.
const VIEW_HALF := 1.15
const HEARS := 2.5
const TURN := .11
## BOT SKILL's MIXED: each bot its own skill by slot (modes.cfg).
const MIXED := 4
static var MIXED_SKILLS: Array = ModeData.get_value("tactical_bot", "mixed", [1])
static var PERSONAS: Array = ModeData.get_value("tactical_bot", "personas", ["careful"])
static var FALL_BACK: Dictionary = ModeData.get_value("tactical_bot", "fall_back", {})
static var PUSH_LOST: Dictionary = ModeData.get_value("tactical_bot", "push_lost", {})
static var TRADE_REACH: float = ModeData.get_value("tactical_bot", "trade_reach", 14.0)
static var TRADE_FOR: float = ModeData.get_value("tactical_bot", "trade_for", 6.0)
const ARRIVE := 1.4
const LURK_UNTIL := 22.0
const CALL_FOR := 7.0

## The team's calls: game instance -> team -> {"A": clock seen, "B": ...}.
static var calls := {}
## The attack gathering before it goes in: game instance -> {round, go,
## here: slots gathered, bots: slots that are bots}.
static var staged := {}
## Games whose calls and gathering are kept at once.
const GAMES_KEPT := 6
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
## The hand on the mouse (bot_aim.gd) and the way it plays (PERSONAS).
var aim := BotAim.new()
var persona := "careful"
## Teammates up at the last look (slot -> bool), to see one fall and trade.
var mates_up := {}
## Where to go to trade a teammate's death and where to have the gun, until.
var trade_at := Vector2.INF
var trade_look := Vector2.INF
var trade_until := 0.0
## Falling back hurt: the spot out of the foe's sight, kept until; looked for
## again after cover_look.
var cover_at := Vector2.INF
var cover_until := 0.0
var cover_look := 0.0
## Where gunfire that hurt it came from, turned to until.
var alert_at := Vector2.INF
var alert_until := 0.0
var health_was := 100
## The foe it lost was killed (no push after a dead one).
var foe_dead := false
## Where to have the gun while walking (INF: the way it goes).
var watch := Vector2.INF
## When the side-step changes way.
var strafe_flip := 0.0
## A boarded cover cell being shot open for a shorter way, and until when it
## is given up; the route leg it was last looked for at.
var board := Vector2i(-1, -1)
var board_until := 0.0
var board_leg := -1
## When the foe in sight is looked at again; the hold the gun is on going in,
## until it is looked for again.
var sight_at := 0.0
var corner := Vector2.INF
var corner_at := 0.0
## Route points moved aside for this bot this round (by leg), and the route
## point itself behind the one it walks to now (its step field is the one
## walked: the team shares it), INF when the goal is no route point.
var spread := {}
var route_point := Vector2.INF
## A goal near enough to walk straight at when it is in sight: which, until
## when that was looked at, and whether it is.
var straight_goal := Vector2.INF
var straight_at := 0.0
var straight := false
## The bots' buying ways, by slot: rifle carriers, the sniper, the one who
## buys an SMG rather than save, the one who likes a shotgun or big pistol.
## (data/tuning/modes.cfg [tactical_bot] styles)
static var STYLES: Array = ModeData.get_value("tactical_bot", "styles", [])


func _init(p_slot := 0) -> void:
	slot = p_slot
	rng.seed = 7919 * (p_slot + 1)


# ------------------------------------------------------------------- tick


func steer(game: Game) -> Game.Controls:
	var c := Game.Controls.new()
	var p: Player = game.player
	var st: ModeFeature = Modes.feature(game)
	if st == null or not Modes.TACTICAL.has(String(st.mode)) or p.health <= 0:
		return c
	if int(st.round_no) != round_seen:
		_plan(game, st, p)
	if shopped != int(st.round_no) and TacticalMode.can_buy(game, st, p):
		_shop(game, st, p)
		shopped = int(st.round_no)
	if not buys.is_empty():
		var index: int = buys.pop_front()
		c.buy = index
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
		aim.rest(game)
		c.turn = sin(game.clock * 3.0 + slot) * .05
		c.forward = -.3
		return c
	_watch_team(game, p)
	_look(game, st, p)
	_plan_throw(game, st, p)
	route_point = Vector2.INF
	var goal := _goal(game, st, p, c)
	if not c.hold:
		goal = _tactics_goal(game, st, p, goal)
	if foe != null:
		_fight(game, st, p, c, goal)
	else:
		aim.rest(game)
		if not _shoot_board(game, p, c):
			_walk(game, p, c, goal)
	BotTactics.keep_out_of_fire(game, st, p, c)
	_unstick(game, p, c)
	return c


## This bot's skill (0 EASY .. 3 HOG WILD): the match's BOT SKILL (MIXED: by
## its place in its team, both teams alike), else the game's DIFFICULTY.
static func skill_for(game: Game, p_slot: int) -> int:
	var st: ModeFeature = Modes.feature(game)
	var skill := int(game.difficulty)
	if st != null and int(st.bot_skill) >= 0:
		skill = int(st.bot_skill)
	if skill == MIXED:
		var k := p_slot >> 1
		if p_slot >= 0 and p_slot < game.players.size():
			k = team_index(game, game.players[p_slot])
		var mixed: int = MIXED_SKILLS[k % MIXED_SKILLS.size()]
		return clampi(mixed, 0, 3)
	return clampi(skill, 0, 3)


## Called after the tick (main.gd _tick_party): nothing to settle.
func moved(_game: Game) -> void:
	pass


# ------------------------------------------------------------------ plans


## The team's site this round: the same answer for every bot on it.
static func plan_site(game: Game, st: ModeFeature) -> String:
	var sites: Variant = game.world.tactical.get("sites", {})
	var names: Array = []
	if sites is Dictionary:
		var by_name: Dictionary = sites
		names = by_name.keys()
	names.sort()
	if names.is_empty():
		return ""
	var wins: int = st.wins[0]
	var h := absi(hash(String(game.level.id)) + int(st.round_no) * 2654435761 + wins * 31)
	return str(names[(h >> 3) % names.size()])


## Where this bot is among its team's players (0..4, by slot).
static func team_index(game: Game, p: Player) -> int:
	var k := 0
	for q: Player in game.players:
		if q == p:
			return k
		if q.team == p.team:
			k += 1
	return k


func _plan(game: Game, st: ModeFeature, p: Player) -> void:
	round_seen = int(st.round_no)
	foe = null
	stuck = 0.0
	leg = 0
	hold = Vector3.INF
	route = []
	lurking = false
	throw_gun = -1
	thrown = {}
	aim.skill = skill_for(game, p.slot)
	persona = str(PERSONAS[team_index(game, p) % PERSONAS.size()])
	mates_up = {}
	trade_until = 0.0
	cover_at = Vector2.INF
	cover_until = 0.0
	alert_until = 0.0
	health_was = p.health
	watch = Vector2.INF
	board = Vector2i(-1, -1)
	board_leg = -1
	foe_lost_at = -99.0
	spread = {}
	corner_at = 0.0
	var plan: Dictionary = game.world.tactical
	var k := team_index(game, p)
	if TacticalMode.attacks(game, st, p):
		var site := plan_site(game, st)
		var other := "B" if site == "A" else "A"
		lurking = k == 4 and String(st.mode) == Modes.BOMB
		var by_site: Dictionary = plan.get("routes", {})
		var found: Variant = by_site.get(other if lurking else site, [])
		var routes: Array = found if found is Array else []
		if not routes.is_empty():
			var chosen: Array = routes[k % routes.size()]
			route = chosen.duplicate()
		stage_leg = _stage_for(game, plan, site)
	else:
		hold = _hold_for(plan, k)


static func _hold_for(plan: Dictionary, k: int) -> Vector3:
	var found: Variant = plan.get("holds", {})
	if not found is Dictionary:
		return Vector3.INF
	var holds: Dictionary = found
	var key := "A" if k < 2 else ("B" if k < 4 else "mid")
	var listed: Variant = holds.get(key, [])
	if not listed is Array:
		return Vector3.INF
	var rows: Array = listed
	if rows.is_empty():
		return Vector3.INF
	var row: Array = rows[(k % 2) % rows.size()]
	var hx: float = row[0]
	var hy: float = row[1]
	var facing: float = row[2]
	return Vector3(hx, hy, facing)


func _shop(game: Game, st: ModeFeature, p: Player) -> void:
	var cash: int = st.money[p.slot]
	var has_long := false
	for gun: int in TacticalShop.LONG_GUNS:
		if p.armory.owned[gun]:
			has_long = true
	var half_start := int(st.round_no) == 1 or int(st.round_no) == int(st.rounds_to_win)
	var outlaw := TacticalMode.side_of(st, p) == 0
	var team: int = p.team
	var behind := 0
	if team < st.losses_in_row.size():
		behind = st.losses_in_row[team]
	var wants: Array = []
	# Each bot has its way (STYLES): most carry a rifle, one is the team's
	# sniper, one likes an SMG when money is short, one a shotgun up close.
	var style := str(STYLES[slot % STYLES.size()])
	# The team buys together: when most of it cannot buy (the team's middle
	# cash short of a rifle and a vest) a bot that could only just buy saves
	# with them, unless the losses have run long enough to force it.
	if not has_long and not half_start and behind < 2 and cash < 4600:
		if _team_cash(st, p) < 3000:
			cash = mini(cash, 1150)
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
	# grows). Under rules that sell none of those, the dearest gun they do.
	if String(st.store_rules) != "any" and not has_long:
		var pick := TacticalShop.rule_pick(game, st, p, cash)
		if pick != "" and not wants.has(pick):
			wants.insert(0, pick)
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


## The middle of the team's cash (its players by slot).
static func _team_cash(st: ModeFeature, p: Player) -> int:
	var all: Array = []
	for i in st.money.size():
		if i % 2 == p.slot % 2:
			all.append(st.money[i])
	if all.is_empty():
		return 0
	all.sort()
	var middle: int = all[all.size() >> 1]
	return middle


## The best gun in hand, reloaded when dry.
func _arm(_game: Game, p: Player, c: Game.Controls) -> void:
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
func _look(game: Game, st: ModeFeature, p: Player) -> void:
	if foe != null:
		var look_again := game.clock >= sight_at
		if look_again:
			sight_at = game.clock + SIGHT_EVERY
		if foe.health <= 0 or (look_again and not _sees(game, p, foe)):
			foe_lost_at = game.clock
			foe_dead = foe.health <= 0
			foe_last = Vector2(foe.x, foe.y)
			foe = null
		else:
			aim.still_seen(game, foe)
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
		sight_at = game.clock + SIGHT_EVERY
		aim.notice(game, p, best, rng)
		_call(game, st, p.team, best)


func _sees(game: Game, p: Player, q: Player) -> bool:
	var d := Vector2(q.x - p.x, q.y - p.y).length()
	if d > SIGHT:
		return false
	# Only what is in front (a screen and a little each side), unless close.
	var bearing := atan2(q.y - p.y, q.x - p.x)
	if d > HEARS and absf(Enemy.angle_delta(bearing, p.angle)) > VIEW_HALF:
		return false
	if TacticalUtility.smoked(game, p.x, p.y, q.x, q.y):
		return false
	return game.world.visible(p.x, p.y, q.x, q.y, p.eye, q.eye - .1)


static func _call(game: Game, _st: ModeFeature, team: int, seen: Player) -> void:
	var at := BombMode.site_at(game, seen.x, seen.y)
	if at == "":
		var sites: Variant = game.world.tactical.get("sites", {})
		if sites is Dictionary:
			var by_name: Dictionary = sites
			for name: String in by_name:
				var box: Array = by_name[name]
				var centre := TacticalMode.box_centre(box)
				if centre.distance_to(Vector2(seen.x, seen.y)) < 7.0:
					at = name
	if at == "":
		return
	var key: int = game.get_instance_id()
	if not calls.has(key):
		# Each game its own (a server plays two matches at once): the oldest
		# goes past GAMES_KEPT.
		while calls.size() >= GAMES_KEPT:
			calls.erase(calls.keys()[0])
		calls[key] = [{}, {}]
	calls[key][team][at] = game.clock


static func called(game: Game, team: int) -> String:
	var key: int = game.get_instance_id()
	if not calls.has(key):
		return ""
	var best := ""
	var latest := -1.0
	var mine: Dictionary = calls[key][team]
	for site: String in mine:
		var when: float = mine[site]
		if game.clock - when < CALL_FOR and when > latest:
			latest = when
			best = site
	return best


# ------------------------------------------------------------------- goals


## Where to go now (INF: stay where it is), with the objective's own presses
## held in the controls.
func _goal(game: Game, st: ModeFeature, p: Player, c: Game.Controls) -> Vector2:
	if String(st.mode) == Modes.BOMB:
		return _bomb_goal(game, st, p, c)
	return _hostage_goal(game, st, p, c)


func _bomb_goal(game: Game, st: ModeFeature, p: Player, c: Game.Controls) -> Vector2:
	var bomb: Dictionary = st.bomb
	var state := str(bomb.get("state", ""))
	var bomb_x: float = bomb.get("x", 0.0)
	var bomb_y: float = bomb.get("y", 0.0)
	var at := Vector2(bomb_x, bomb_y)
	var plan: Dictionary = game.world.tactical
	if TacticalMode.attacks(game, st, p):
		if state == "dropped" and _nearest_to(game, p, at):
			return at
		if state == "planted":
			var guard := at + Vector2(cos(slot * 1.7), sin(slot * 1.7)) * 3.0
			return guard if not game.world.blocked(guard.x, guard.y, .3) else at
		var carrying := false
		if state == "carried":
			var holder: int = bomb["slot"]
			carrying = holder == p.slot
		var site := plan_site(game, st)
		var sites_by: Dictionary = plan.get("sites", {})
		var box: Variant = sites_by.get(site, [])
		var centre := at
		if box is Array:
			var corners: Array = box
			if corners.size() >= 4:
				centre = TacticalMode.box_centre(corners)
		if lurking and game.clock - float(st.live_from) > LURK_UNTIL:
			# The lurk is over: straight across to the team's site.
			lurking = false
			route = [[centre.x, centre.y]]
			leg = 0
			spread = {}
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
				var planted_at: float = bomb["planted_at"]
				var left: float = BombMode.BOMB_TIMER - (game.clock - planted_at)
				if foe == null or left < BombMode.defuse_time(st, p) + 1.0:
					c.hold = true
					return Vector2.INF
			return at
		return at + Vector2(cos(slot * 2.3), sin(slot * 2.3)) * 3.5
	var heard := called(game, p.team)
	# A call brings help from the other site; with one site (TAG TEAM 2V2)
	# both are already on it, and leaving a hold for the site's middle only
	# walks them into the open.
	var sites: Variant = plan.get("sites", {})
	var one_site := false
	if sites is Dictionary:
		var by_name: Dictionary = sites
		one_site = by_name.size() == 1
	if heard != "" and not one_site and team_index(game, p) != (0 if heard == "B" else 2):
		var sites_by: Dictionary = plan.get("sites", {})
		var box: Variant = sites_by.get(heard, [])
		if box is Array:
			var corners: Array = box
			if corners.size() >= 4:
				return TacticalMode.box_centre(corners)
	return Vector2(hold.x, hold.y) if hold != Vector3.INF else Vector2.INF


func _hostage_goal(game: Game, st: ModeFeature, p: Player, c: Game.Controls) -> Vector2:
	var box := HostageMode.nearest_rescue(game, p.x, p.y)
	var carried_by: Player = null
	var mine := -1
	for i in st.hostages.size():
		var h: Array = st.hostages[i]
		if str(h[2]) == "carried":
			var s: int = h[3]
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
			if str(h[2]) != "free":
				continue
			var hx: float = h[0]
			var hy: float = h[1]
			var at := Vector2(hx, hy)
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
func _route_goal(game: Game, p: Player) -> Vector2:
	while leg < route.size():
		var point: Array = route[leg]
		var px: float = point[0]
		var py: float = point[1]
		var at := Vector2(px, py)
		route_point = at
		if leg < route.size() - 1:
			at = _spread_out(game, p, leg)
		if stage_leg >= 0 and leg > stage_leg and not lurking:
			var wait := _spread_out(game, p, stage_leg)
			if not _released(game, p, wait):
				var stage: Array = route[stage_leg]
				var sx: float = stage[0]
				var sy: float = stage[1]
				route_point = Vector2(sx, sy)
				return wait
		if at.distance_to(Vector2(p.x, p.y)) > ARRIVE:
			return at
		leg += 1
	return Vector2.INF


## Route point `index` moved aside by this bot's place in the team, so a team
## on one route walks abreast, not in a line (the point itself where that is
## not open floor). Worked out once a leg a round.
func _spread_out(game: Game, p: Player, index: int) -> Vector2:
	var point: Array = route[index]
	var px: float = point[0]
	var py: float = point[1]
	var at := Vector2(px, py)
	if spread.has(index):
		var kept: Vector2 = spread[index]
		return kept
	spread[index] = at
	var off := (team_index(game, p) - 2) * .55
	var before: Array = route[index - 1] if index > 0 else [p.x, p.y]
	var bx: float = before[0]
	var by: float = before[1]
	var along := at - Vector2(bx, by)
	if absf(off) < .01 or along.length() < .5:
		return at
	var moved := at + Vector2(-along.y, along.x).normalized() * off
	if (
		game.world.blocked(moved.x, moved.y, .35)
		or not game.world.visible(at.x, at.y, moved.x, moved.y)
	):
		return at
	spread[index] = moved
	return moved


## Where on the route the team gathers: the point before the site itself,
## or the one before that when the site's holds can see it (a doorway), so
## they wait out of the defenders' sight but not far back; -1 with no route.
func _stage_for(game: Game, plan: Dictionary, site: String) -> int:
	if route.size() < 2:
		return -1
	var holds_by: Dictionary = plan.get("holds", {})
	var holds: Array = holds_by.get(site, [])
	var before: Array = route[-2]
	var last_x: float = before[0]
	var last_y: float = before[1]
	var last := Vector2(last_x, last_y)
	for i in range(route.size() - 2, maxi(-1, route.size() - 4), -1):
		var point: Array = route[i]
		var px: float = point[0]
		var py: float = point[1]
		var at := Vector2(px, py)
		if at.distance_to(last) > STAGE_BACK:
			break  # too far back to gather: the point before the site it is
		var seen := false
		for h: Array in holds:
			var hx: float = h[0]
			var hy: float = h[1]
			if game.world.visible(hx, hy, at.x, at.y):
				seen = true
				break
		if not seen:
			return i
	return route.size() - 2


## Whether the attack has gone in: this bot is noted as gathered once at
## `wait`; the team goes when all but one of those up (lurker aside) are
## gathered, when a gathered one has a foe in sight, or STAGE_MOST seconds
## into the round.
func _released(game: Game, p: Player, wait: Vector2) -> bool:
	var st: ModeFeature = Modes.feature(game)
	if st == null or not TacticalMode.attacks(game, st, p):
		return true
	var key: int = game.get_instance_id()
	var round_no := int(st.round_no)
	var found: Variant = staged.get(key)
	var team: Dictionary = found if found is Dictionary else {}
	if team.get("round", -1) != round_no:
		# One round's gathering per game (a server plays two matches at once).
		if not staged.has(key):
			while staged.size() >= GAMES_KEPT:
				staged.erase(staged.keys()[0])
		team = {"round": round_no, "go": false, "here": {}, "bots": {}}
		staged[key] = team
	var gone: bool = team["go"]
	if gone:
		return true
	var gathered: Dictionary = team["here"]
	var bots: Dictionary = team["bots"]
	bots[p.slot] = true
	if Vector2(p.x, p.y).distance_to(wait) < ARRIVE * 1.6:
		gathered[p.slot] = true
	# Only bots are waited for: a person on the team (online) never says they
	# are there, and the attack used to stand STAGE_MOST seconds for them.
	var up := 0
	var here := 0
	for q: Player in game.players:
		if q.team != p.team or q.health <= 0 or team_index(game, q) == 4:
			continue
		if bots.has(q.slot):
			up += 1
			if gathered.has(q.slot):
				here += 1
		elif Vector2(q.x, q.y).distance_to(wait) < ARRIVE * 1.6:
			up += 1
			here += 1
	var seen: bool = foe != null and gathered.has(p.slot)
	if here >= maxi(1, up - 1) or seen or game.clock - float(st.live_from) > STAGE_MOST:
		team["go"] = true
		team["go_at"] = game.clock
	var go: bool = team["go"]
	if not go or seen:
		return go
	# In one after another, not in a heap: the aggressive first, the careful
	# last, a beat apart.
	var order := 0 if persona == "aggressive" else (1 if persona == "support" else 2)
	var go_at: float = team.get("go_at", game.clock)
	return game.clock >= go_at + order * .25 + team_index(game, p) * .05


## Whether `p` is the nearest of its team up to `at`.
static func _nearest_to(game: Game, p: Player, at: Vector2) -> bool:
	var mine := at.distance_to(Vector2(p.x, p.y))
	for q: Player in game.players:
		if q != p and q.team == p.team and q.health > 0:
			if at.distance_to(Vector2(q.x, q.y)) < mine - .01:
				return false
	return true


## Which way to face standing still: the hold's own way, else toward the
## middle of the map.
func _face_angle(game: Game, _st: ModeFeature, p: Player) -> float:
	if watch != Vector2.INF:
		return atan2(watch.y - p.y, watch.x - p.x)
	if hold != Vector3.INF and Vector2(hold.x, hold.y).distance_to(Vector2(p.x, p.y)) < 2.0:
		return hold.z
	if not route.is_empty():
		var at: Array = route[mini(leg, route.size() - 1)]
		var ax: float = at[0]
		var ay: float = at[1]
		return atan2(ay - p.y, ax - p.x)
	return atan2(game.world.height * .5 - p.y, game.world.width * .5 - p.x)


# ---------------------------------------------------------------- moving


func _walk(game: Game, p: Player, c: Game.Controls, goal: Vector2) -> void:
	c.look = clampf(-p.pitch * .2, -2.0, 2.0)
	if goal == Vector2.INF:
		c.turn = clampf(Enemy.angle_delta(_face_angle(game, null, p), p.angle), -TURN, TURN)
		return
	var gap := goal.distance_to(Vector2(p.x, p.y))
	if gap < .6:
		c.turn = clampf(Enemy.angle_delta(_face_angle(game, null, p), p.angle), -TURN, TURN)
		return
	var want := _heading(game, p, _nav_for(game, p, goal, gap))
	# The gun on a spot that matters (where a foe was lost, a teammate fell,
	# gunfire came from), else on a hold as it goes onto a site.
	var check := watch if watch != Vector2.INF else _corner_to_check(game, p)
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


## Where to walk the step field of for `goal` (each new cell is a whole-map
## field walked, TacticalNav): far off, the route point itself (the team's
## field) or the goal's cell snapped to a coarse grid, so the bots' many
## passing goals (a teammate's fall, a lost foe, a carrier) share fields;
## near, the goal itself, walked straight at when it is in sight.
func _nav_for(game: Game, p: Player, goal: Vector2, gap: float) -> Vector2:
	if route_point != Vector2.INF and goal.distance_to(route_point) < 1.6:
		return route_point if gap > 3.0 else goal
	if gap > NAV_NEAR:
		straight = false
		var snapped := Vector2(
			floorf(goal.x / NAV_GRID) * NAV_GRID + NAV_GRID * .5,
			floorf(goal.y / NAV_GRID) * NAV_GRID + NAV_GRID * .5
		)
		if not game.world.blocked(snapped.x, snapped.y, .3):
			return snapped
		return goal
	if goal.distance_to(straight_goal) > .5 or game.clock >= straight_at:
		straight_goal = goal
		straight_at = game.clock + .3
		straight = game.world.visible(p.x, p.y, goal.x, goal.y)
	return goal


## An attacker on its last leg onto a site: the nearest of the map's holds
## (where defenders wait) it could see from here, to have its gun on as it
## goes in. INF when there is none, or it is not going in.
func _corner_to_check(game: Game, p: Player) -> Vector2:
	if route.is_empty() or leg != route.size() - 1 or lurking:
		return Vector2.INF
	var st: ModeFeature = Modes.feature(game)
	if st == null or not TacticalMode.attacks(game, st, p):
		return Vector2.INF
	if game.clock < corner_at:
		return corner
	corner_at = game.clock + CORNER_EVERY
	corner = _nearest_hold_seen(game, p)
	return corner


func _nearest_hold_seen(game: Game, p: Player) -> Vector2:
	var best := Vector2.INF
	var near := 18.0
	for key: String in game.world.tactical.get("holds", {}):
		for h: Array in game.world.tactical["holds"][key]:
			var hx: float = h[0]
			var hy: float = h[1]
			var at := Vector2(hx, hy)
			var d := at.distance_to(Vector2(p.x, p.y))
			if d < near and d > 2.0 and game.world.visible(p.x, p.y, at.x, at.y):
				near = d
				best = at
	return best


func _heading(game: Game, p: Player, goal: Vector2) -> float:
	var direct := atan2(goal.y - p.y, goal.x - p.x)
	if (
		goal.distance_to(Vector2(p.x, p.y)) < 1.2
		or (straight and goal.distance_to(straight_goal) < .6)
	):
		return direct
	var field := TacticalNav.field(game, goal.x, goal.y)
	var h: float = field.heading(p.x, p.y, game.world.stand(p)) if field != null else NAN
	return direct if is_nan(h) else h


## Aim at the foe as a person does (bot_aim.gd), side-step and stand for the
## shot, fall back hurt, and close in or hold by the gun's reach.
func _fight(game: Game, st: ModeFeature, p: Player, c: Game.Controls, goal: Vector2) -> void:
	var d := maxf(.4, Vector2(foe.x - p.x, foe.y - p.y).length())
	var on := aim.aim(game, p, foe, c, rng)
	var noticed := game.clock >= aim.ready_at
	# The gun for the distance; out of its reach, close in.
	var wanted := TacticalShop.gun_for(p, d)
	if wanted != p.armory.active and p.armory.switch <= 0.0 and p.armory.fuse <= 0.0:
		c.weapon = wanted
	var reach := TacticalShop.reach(p.armory.active)
	# A scoped gun: the scope up for a foe past arm's length, down up close
	# (ALT FIRE puts it up and down on a fresh press).
	var how: Dictionary = Weapons.FIRING[p.armory.active]
	var scope: float = how.get("scope", 0.0)
	var scopes := bool(scope)
	var want_scope := scopes and d > 6.0 and noticed
	if want_scope != p.scoped and not p.alt_held and p.armory.switch <= 0.0:
		c.alt_fire = true
	c.fire = on and aim.burst_allows(game, p, d, rng)
	if scopes and not p.scoped and d > 6.0:
		c.fire = false
	# Footwork: a side-step that changes way every so often; the guns that
	# want a still shooter (TacticalShop.MOVE_SPREAD) stand for the shot and
	# fire once stopped, stepping again between bursts.
	if game.clock >= strafe_flip:
		strafe_turn = -strafe_turn
		strafe_flip = game.clock + rng.randf_range(.35, .9)
	c.strafe = strafe_turn * .8 if noticed else 0.0
	var kind := TacticalShop.kind_of(p.armory.active)
	if kind in ["RIFLE", "MACHINE GUN", "SNIPER", "PISTOL"] and d > 4.0:
		if noticed and not aim.resting(game):
			c.strafe = 0.0
			if Vector2(p.vx, p.vy).length() > TacticalShop.STILL_BELOW * 1.2:
				c.fire = false
			# The careful kneel for a long shot.
			c.crouch = persona == "careful" and d > 9.0
	if _falling_back(game, st, p, c, d):
		return
	if d > reach:
		# Out of reach: attackers close in, a defender keeps to its spot and
		# lets them come.
		c.fire = false
		if TacticalMode.attacks(game, st, p) or hold == Vector3.INF:
			c.forward = 1.0
			c.running = true
			c.strafe *= .3
		else:
			c.strafe = 0.0
			c.crouch = true
	elif d < 2.0:
		c.forward = -.5
	elif goal != Vector2.INF and hold == Vector3.INF and d > 12.0:
		c.forward = .3 if persona != "careful" else 0.0


## Hurt under its persona's line (FALL_BACK) with the foe not nearly done:
## back off, gun still on the foe, to a spot the foe cannot see (BotTactics);
## true while it does. Out of sight it waits there a moment (_tactics_goal),
## then peeks again with the angle already held.
func _falling_back(game: Game, st: ModeFeature, p: Player, c: Game.Controls, d: float) -> bool:
	var line: float = FALL_BACK.get(persona, 35.0)
	var attacking := TacticalMode.attacks(game, st, p)
	if attacking:
		# The attack has a clock to beat: it holds on longer, and with little
		# of the round left nobody hides.
		line *= ATTACK_FALL_BACK
		var rules := Modes.rules(game) as TacticalMode
		if rules != null and str(st.bomb.get("state", "")) != "planted":
			var left := rules.round_time_of(st) - (game.clock - float(st.live_from))
			if left < NO_HIDING:
				return false
	if p.health >= line and game.clock >= cover_until:
		return false
	if foe.health < 30 and d < 12.0:
		return false  # nearly done: finish it
	if _on_objective(st, p):
		return false
	if game.clock >= cover_look:
		cover_look = game.clock + .6
		cover_at = BotTactics.cover_spot(game, p, foe)
		if cover_at != Vector2.INF and game.clock >= cover_until:
			cover_until = game.clock + rng.randf_range(2.2, 3.6)
	if cover_at == Vector2.INF:
		return false
	var to := cover_at - Vector2(p.x, p.y)
	if to.length() < .4:
		return false
	var off := Enemy.angle_delta(atan2(to.y, to.x), p.angle)
	c.forward = cos(off)
	c.strafe = sin(off)
	c.running = true
	return true


## Whether it is busy with the round's objective (carrying the bomb or a
## hostage, planting, cutting a fuse): it does not fall back or trade then.
func _on_objective(st: ModeFeature, p: Player) -> bool:
	if String(st.mode) == Modes.BOMB:
		var bomb: Dictionary = st.bomb
		var state := str(bomb.get("state", ""))
		var holder: int = bomb.get("slot", -1)
		if state == "carried" and holder == p.slot:
			return true
		if state == "planted" and TacticalMode.defends(st, p):
			var bx: float = bomb.get("x", 0.0)
			var by: float = bomb.get("y", 0.0)
			return Vector2(bx, by).distance_to(Vector2(p.x, p.y)) < BombMode.DEFUSE_REACH
		return false
	for h: Array in st.hostages:
		var carrier: int = h[3]
		if str(h[2]) == "carried" and carrier == p.slot:
			return true
	return false


# ---------------------------------------------------------------- tactics


## Teammates seen to fall (a nearby one draws it to trade: where they fell,
## the gun on where the killer was), and gunfire that hurt it with no foe in
## sight (it turns to where the nearest foe who just fired is: it heard it).
func _watch_team(game: Game, p: Player) -> void:
	for q: Player in game.players:
		if q == p or q.team != p.team:
			continue
		var up := q.health > 0
		var was: bool = mates_up.get(q.slot, up)
		mates_up[q.slot] = up
		if not was or up or foe != null:
			continue
		var gap := Vector2(q.x - p.x, q.y - p.y).length()
		if gap > TRADE_REACH * (1.3 if persona == "support" else 1.0):
			continue
		trade_at = Vector2(q.x, q.y)
		trade_until = game.clock + TRADE_FOR * (.6 if persona == "careful" else 1.0)
		trade_look = trade_at
		var by := q.downed_by
		if by >= 0 and by < game.players.size() and game.players[by].team != p.team:
			var killer: Player = game.players[by]
			trade_look = Vector2(killer.x, killer.y)
	if p.health < health_was and foe == null:
		var near := SIGHT
		for q: Player in game.players:
			if q.team == p.team or q.health <= 0 or q.armory.cooldown <= 0.0:
				continue
			var gap := Vector2(q.x - p.x, q.y - p.y).length()
			if gap < near:
				near = gap
				alert_at = (
					Vector2(q.x, q.y) + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1))
				)
				alert_until = game.clock + 2.0
	health_was = p.health


## The objective's goal turned by what is going on: back to cover while
## hurt, to a teammate's death to trade it, after a foe it lost (by persona);
## and where to keep the gun on the way (`watch`).
func _tactics_goal(game: Game, st: ModeFeature, p: Player, goal: Vector2) -> Vector2:
	watch = Vector2.INF
	var here := Vector2(p.x, p.y)
	if game.clock < alert_until:
		watch = alert_at
	var busy := _on_objective(st, p)
	if game.clock < cover_until and cover_at != Vector2.INF and foe == null and not busy:
		# Out of sight: wait there, the gun on where the foe was.
		watch = foe_last
		return cover_at if here.distance_to(cover_at) > .5 else Vector2.INF
	if game.clock < trade_until and not busy:
		if here.distance_to(trade_at) < 2.0:
			trade_until = 0.0
		else:
			watch = trade_look
			return trade_at
	var lost_for := game.clock - foe_lost_at
	if not foe_dead and lost_for < 3.0:
		watch = foe_last
		var push: float = PUSH_LOST.get(persona, 0.0)
		if lost_for < push and not busy and here.distance_to(foe_last) > 1.5:
			return foe_last
	return goal


## An attacker on its route with a whole boarded cover cell near that,
## shot open, would be the shorter way to its next point: it stands and
## shoots it open (BotTactics.board_for, looked for once a leg). True while
## it does.
func _shoot_board(game: Game, p: Player, c: Game.Controls) -> bool:
	if route.is_empty() or lurking or leg >= route.size():
		return false
	if board_leg != leg:
		board_leg = leg
		board = Vector2i(-1, -1)
		var point: Array = route[leg]
		var px: float = point[0]
		var py: float = point[1]
		if persona != "careful":
			board = BotTactics.board_for(game, p, Vector2(px, py))
			board_until = game.clock + 4.0
	if board.x < 0:
		return false
	var walls: WallBreaks = game.features.get("wall_breaks")
	var f: WallBreaks.Fence = null
	if walls != null and walls.fences.has(board):
		f = walls.fences[board]
	if f == null or f.stage >= 2 or game.clock > board_until:
		board = Vector2i(-1, -1)
		return false
	var at := Vector2(board.x + .5, board.y + .5)
	var d := maxf(.5, at.distance_to(Vector2(p.x, p.y)))
	var turn := Enemy.angle_delta(atan2(at.y - p.y, at.x - p.x), p.angle)
	c.turn = clampf(turn, -TURN, TURN)
	var slope := (game.world.elevation(at.x, at.y) + f.top * .5 - p.eye) / d
	c.look = clampf(slope * View.base_focal - p.pitch, -3.0, 3.0)
	c.fire = absf(turn) < .05 and p.armory.cooldown <= 0.0
	return true


## Hops and side-steps out of a spot it is wedged in; a waypoint it cannot
## reach for a while is skipped.
func _unstick(game: Game, p: Player, c: Game.Controls) -> void:
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
func _plan_throw(game: Game, st: ModeFeature, p: Player) -> void:
	if throw_gun >= 0:
		return
	var a: Weapons.Armory = p.armory
	var plan: Dictionary = game.world.tactical
	if TacticalMode.attacks(game, st, p):
		if route.is_empty() or leg != route.size() - 1:
			return
		var site := plan_site(game, st)
		var sites_by: Dictionary = plan.get("sites", {})
		var found: Variant = sites_by.get(site, [])
		if not found is Array:
			return
		var box: Array = found
		if box.size() < 4:
			return
		var centre := TacticalMode.box_centre(box)
		var holds_by: Dictionary = plan.get("holds", {})
		var holds: Variant = holds_by.get(site, [])
		if (
			a.owned[Weapons.SMUDGE_POT]
			and a.reserve[Weapons.SMUDGE_POT] > 0
			and not thrown.has(Weapons.SMUDGE_POT)
		):
			var spots: Array = holds if holds is Array else []
			if not spots.is_empty():
				var spot: Array = spots[0]
				var sx: float = spot[0]
				var sy: float = spot[1]
				_start_throw(game, Weapons.SMUDGE_POT, Vector2(sx, sy))
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


func _start_throw(game: Game, gun: int, at: Vector2) -> void:
	throw_gun = gun
	throw_at = at
	throw_until = game.clock + 2.5


## A throw under way: take the throwable up, turn on the spot, lift the aim
## for the distance, let fly. True while it is still under way.
func _throw(game: Game, p: Player, c: Game.Controls) -> bool:
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
